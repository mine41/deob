<#
.SYNOPSIS
  基于 CFG 遍历执行结果（ResolvableResults）对脚本做片段回写，输出重建后的“解混淆脚本”。

.DESCRIPTION
  支持多轮迭代：每一轮都重新生成 CFG 并执行，再把可确定的可还原表达式替换回脚本；
  直到某一轮 applied replacements = 0（收敛）或达到 MaxRounds。

  约束（v1）：
  - 仅使用 ResolvableResults（不使用变量读取、也不使用内联函数调用结果）；
  - 遇到 __BLOCKED_PLACEHOLDER__ 一律跳过；
  - 同一源码片段若出现多个不同值则跳过；
  - 重叠/嵌套替换片段通过 -OverlapStrategy 控制（Outer/Inner）。

.EXAMPLE
  powershell.exe .\Rebuild-Deobfuscated.ps1 -ScriptPath .\in\in.ps1

.EXAMPLE
  pwsh .\Rebuild-Deobfuscated.ps1 -ScriptPath .\sample.ps1 -MaxRounds 10 -OverlapStrategy Inner
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ScriptPath,

    [string]$OutPath,

    [string]$WorkDir,

    # 是否输出完整解混淆过程（每轮 in/out/log/report + CFG dot/png）。
    # 关闭时：只输出最终重建脚本（最快，不落盘任何过程文件）。
    [bool]$FullOutput = $true,

    [ValidateSet('Outer', 'Inner')]
    [string]$OverlapStrategy = 'Inner',

    # 变量读取同位置出现多值时的处理策略：
    # - skip: 直接跳过
    # - last: 采用最后一次可用简单值
    [ValidateSet('skip', 'last')]
    [string]$VariableConflictPolicy = 'skip',

    [int]$MaxRounds = 10,

    [int]$MaxIterations = 1000,

    [int]$MaxTotalNodes = 50000,

    [int]$GlobalTimeBudgetMs = 45000,

    [int]$DynamicTimeBudgetMs = 3000,

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function New-SkipRecord {
    param(
        [string]$Reason,
        [string]$Message,
        $Item
    )

    $start = $null
    $end = $null
    $type = $null
    $nodeId = $null
    $depth = $null

    if ($Item) {
        $start = $Item.StartOffset
        $end = $Item.EndOffset
        $type = $Item.Type
        $nodeId = $Item.NodeId
        $depth = $Item.Depth
    }

    return [PSCustomObject]@{
        Reason    = $Reason
        Message   = $Message
        Start     = $start
        End       = $end
        Type      = $type
        NodeId    = $nodeId
        Depth     = $depth
        Timestamp = (Get-Date).ToString('o')
    }
}

function ConvertTo-PreviewText {
    param(
        [string]$Text,
        [int]$MaxLen = 200
    )

    if ($null -eq $Text) { return $null }
    if ($Text.Length -le $MaxLen) { return $Text }
    return $Text.Substring(0, $MaxLen) + '...'
}

function ConvertTo-SingleQuotedStringLiteral {
    param([string]$Text)

    if ($null -eq $Text) { return "''" }
    return "'" + $Text.Replace("'", "''") + "'"
}

function ConvertTo-SingleQuotedHereStringLiteral {
    param([string]$Text)

    $content = if ($null -eq $Text) { '' } else { [string]$Text }
    $content = $content.TrimEnd("`r", "`n")
    return "@'`r`n$content`r`n'@"
}

function ConvertTo-CanonicalPowerShellHostCommandText {
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [string]$PayloadText
    )

    $cmdName = $CommandAst.GetCommandName()
    if ($cmdName -notmatch '(?i)(^|[/\\])(powershell|pwsh)(\.exe)?$') {
        return $null
    }

    $elements = @($CommandAst.CommandElements)
    for ($i = 1; $i -lt $elements.Count; $i++) {
        $elem = $elements[$i]
        if ($elem -isnot [System.Management.Automation.Language.CommandParameterAst]) { continue }

        $paramName = [string]$elem.ParameterName
        if ($paramName -notmatch '^(?i:e(?:n(?:c(?:odedcommand)?)?)?|c(?:o(?:m(?:m(?:a(?:n(?:d)?)?)?)?)?)?)$') {
            continue
        }

        $originalText = [string]$CommandAst.Extent.Text
        $prefixLen = $elem.Extent.StartOffset - $CommandAst.Extent.StartOffset
        if ($prefixLen -lt 0) { return $null }

        $beforeParam = $originalText.Substring(0, $prefixLen)
        $payloadLiteral = ConvertTo-SingleQuotedHereStringLiteral -Text $PayloadText
        return $beforeParam + "-Command $payloadLiteral"
    }

    return $null
}

function Test-SimpleVariableReplacementLiteral {
    param([string]$Replacement)

    if ([string]::IsNullOrWhiteSpace($Replacement)) { return $false }

    # 集合/复杂对象字面量默认不做变量位替换（例如 @(...), @{...}, {...}）
    if ($Replacement -match '^\s*@\(') { return $false }
    if ($Replacement -match '^\s*@\{') { return $false }
    if ($Replacement -match '^\s*\{')  { return $false }

    # 其余视为简单字面量（字符串、数字、布尔、枚举/类型转换等）
    return $true
}

function Get-LastValidVariableReplacement {
    param([array]$Values)

    if (-not $Values -or $Values.Count -eq 0) { return $null }

    for ($i = $Values.Count - 1; $i -ge 0; $i--) {
        $v = [string]$Values[$i]
        if ([string]::IsNullOrWhiteSpace($v)) { continue }
        if ($v -eq '__BLOCKED_PLACEHOLDER__') { continue }
        if ($v -eq '$null') { continue }
        if (-not (Test-SimpleVariableReplacementLiteral -Replacement $v)) { continue }
        return $v
    }
    return $null
}

function Get-VariableAccessKindMapFromScriptText {
    param([Parameter(Mandatory)][string]$ScriptText)

    $map = @{}
    if ([string]::IsNullOrWhiteSpace($ScriptText)) { return $map }

    # 依赖 Generate-CFG.ps1 中的 Get-VariableAccessKind；若不可用则降级为“不做上下文过滤”。
    if (-not (Get-Command Get-VariableAccessKind -ErrorAction SilentlyContinue)) {
        return $map
    }

    try {
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($ScriptText, [ref]$tokens, [ref]$errors)
    } catch {
        return $map
    }

    if (-not $ast) { return $map }

    $varAsts = @($ast.FindAll({
            param($n)
            $n -is [System.Management.Automation.Language.VariableExpressionAst]
        }, $true))

    foreach ($vAst in $varAsts) {
        if (-not $vAst.Extent) { continue }
        $start = $vAst.Extent.StartOffset
        $end = $vAst.Extent.EndOffset
        if ($null -eq $start -or $null -eq $end -or $end -le $start) { continue }

        $kind = $null
        try {
            $kind = Get-VariableAccessKind -VarAst $vAst
        } catch {
            $kind = $null
        }
        if ([string]::IsNullOrWhiteSpace([string]$kind)) { continue }

        $parent = $vAst.Parent
        if (($parent -is [System.Management.Automation.Language.MemberExpressionAst] -or
             $parent -is [System.Management.Automation.Language.InvokeMemberExpressionAst]) -and
            $parent.Expression -eq $vAst) {
            $kind = 'MemberTarget'
        }

        $key = "$start`:$end"
        if (-not $map.ContainsKey($key)) {
            $map[$key] = $kind
            continue
        }

        # 同 offset 若出现多种判定，优先采用更严格的非 Read 判定。
        if ($map[$key] -eq 'Read' -and $kind -ne 'Read') {
            $map[$key] = $kind
        }
    }

    return $map
}

function Get-FullScriptTextFromFile {
    param([Parameter(Mandatory)][string]$Path)

    # 使用 Parser.ParseFile 同一路径读取脚本文本，可最大程度保证 offset 与 AST 一致
    $ast = Get-Ast $Path
    if (-not $ast -or -not $ast.Extent -or -not $ast.Extent.StartScriptPosition) {
        throw "无法解析脚本获取全文: $Path"
    }

    return $ast.Extent.StartScriptPosition.GetFullScript()
}

function Test-StaticReplacementScalarValue {
    param($Value)

    if ($null -eq $Value) { return $true }
    if ($Value -is [psobject] -and $null -ne $Value.BaseObject -and $Value.BaseObject -ne $Value) {
        $Value = $Value.BaseObject
    }
    if ($Value -is [scriptblock]) { return $false }
    if ($Value -is [BlockedCommandPlaceholder]) { return $false }

    if ($Value -is [string])  { return $true }
    if ($Value -is [char])    { return $true }
    if ($Value -is [bool])    { return $true }
    if ($Value -is [byte])    { return $true }
    if ($Value -is [sbyte])   { return $true }
    if ($Value -is [int16])   { return $true }
    if ($Value -is [uint16])  { return $true }
    if ($Value -is [int])     { return $true }
    if ($Value -is [uint32])  { return $true }
    if ($Value -is [int64])   { return $true }
    if ($Value -is [uint64])  { return $true }
    if ($Value -is [float])   { return $true }
    if ($Value -is [double])  { return $true }
    if ($Value -is [decimal]) { return $true }
    return $false
}

function Test-StaticBindingValue {
    param($Value)

    if ($null -eq $Value) { return $true }
    if ($Value -is [psobject] -and $null -ne $Value.BaseObject -and $Value.BaseObject -ne $Value) {
        $Value = $Value.BaseObject
    }
    if ($Value -is [scriptblock]) { return $false }
    if ($Value -is [BlockedCommandPlaceholder]) { return $false }
    if ($Value -is [System.Collections.IDictionary]) { return $false }

    if (($Value -is [System.Collections.IEnumerable]) -and -not ($Value -is [string])) {
        foreach ($item in $Value) {
            if (-not (Test-StaticBindingValue -Value $item)) { return $false }
        }
        return $true
    }

    return (Test-StaticReplacementScalarValue -Value $Value)
}

function Get-StaticValueTypeName {
    param($Value)

    if ($null -eq $Value) { return 'Null' }
    if ($Value -is [psobject] -and $null -ne $Value.BaseObject -and $Value.BaseObject -ne $Value) {
        $Value = $Value.BaseObject
    }
    if ($null -eq $Value) { return 'Null' }
    return [string]$Value.GetType().Name
}

function Replace-FirstOccurrence {
    param(
        [string]$Text,
        [string]$OldValue,
        [string]$NewValue
    )

    if ($null -eq $Text) { return $Text }
    if ([string]::IsNullOrEmpty($OldValue)) { return $Text }
    $index = $Text.IndexOf($OldValue, [System.StringComparison]::Ordinal)
    if ($index -lt 0) { return $Text }
    return $Text.Substring(0, $index) + $NewValue + $Text.Substring($index + $OldValue.Length)
}

function Convert-StaticInterpolatedValueToString {
    param($Value)

    if ($null -eq $Value) { return '' }
    if ($Value -is [psobject] -and $null -ne $Value.BaseObject -and $Value.BaseObject -ne $Value) {
        $Value = $Value.BaseObject
    }
    if (($Value -is [System.Collections.IEnumerable]) -and -not ($Value -is [string])) {
        $parts = @()
        foreach ($item in $Value) {
            $parts += (Convert-StaticInterpolatedValueToString -Value $item)
        }
        return ($parts -join ' ')
    }
    return [string]$Value
}

function Get-StaticExpressionFromPipelineAst {
    param($PipelineAst)

    if ($null -eq $PipelineAst) { return $null }

    if ($PipelineAst -is [System.Management.Automation.Language.AssignmentStatementAst]) {
        return $PipelineAst.Right
    }

    if ($PipelineAst -isnot [System.Management.Automation.Language.PipelineAst]) {
        if ($PipelineAst -is [System.Management.Automation.Language.CommandExpressionAst]) {
            return $PipelineAst.Expression
        }
        if ($PipelineAst -is [System.Management.Automation.Language.ExpressionAst]) {
            return $PipelineAst
        }
        return $null
    }

    if ($PipelineAst.PipelineElements.Count -ne 1) { return $null }

    $element = $PipelineAst.PipelineElements[0]
    if ($element -is [System.Management.Automation.Language.CommandExpressionAst]) {
        return $element.Expression
    }
    if ($element.PSObject.Properties['Expression']) {
        return $element.Expression
    }
    return $null
}

function Get-StaticExpressionFromStatementBlock {
    param([System.Management.Automation.Language.StatementBlockAst]$StatementBlockAst)

    if ($null -eq $StatementBlockAst) { return $null }
    if ($StatementBlockAst.Traps -and $StatementBlockAst.Traps.Count -gt 0) { return $null }
    return @($StatementBlockAst.Statements)
}

function Get-RawScriptTextFromFile {
    param([Parameter(Mandatory)][string]$Path)

    return [System.IO.File]::ReadAllText($Path)
}

function Test-PowerShellHostCommandName {
    param([string]$CommandName)

    if ([string]::IsNullOrWhiteSpace($CommandName)) { return $false }
    return ([string]$CommandName) -match '(?i)(^|[/\\])(powershell|pwsh)(\.exe)?$'
}

function Test-PowerShellHostParameterPrefix {
    param(
        [string]$ParameterName,
        [string]$CanonicalName
    )

    if ([string]::IsNullOrWhiteSpace($ParameterName)) { return $false }
    if ([string]::IsNullOrWhiteSpace($CanonicalName)) { return $false }

    $actual = $ParameterName.ToLowerInvariant()
    $canonical = $CanonicalName.ToLowerInvariant()
    if ($actual.Length -gt $canonical.Length) { return $false }
    return $canonical.StartsWith($actual)
}

function Try-DecodeEncodedCommandValue {
    param([Parameter(Mandatory)][string]$Base64String)

    try {
        $bytes = [Convert]::FromBase64String($Base64String)
        return [Text.Encoding]::Unicode.GetString($bytes)
    } catch {
        return $null
    }
}

function Try-GetWholeScriptHostPayloadInfoLoose {
    param([Parameter(Mandatory)][string]$ScriptText)

    if ([string]::IsNullOrWhiteSpace($ScriptText)) { return $null }

    $text = $ScriptText.Trim()
    $hostMatch = [regex]::Match($text, '(?is)\b(?<cmd>(?:[A-Z]:)?[^''"\r\n]*?(?:powershell|pwsh)(?:\.exe)?)\b')
    if (-not $hostMatch.Success) { return $null }

    $tail = $text.Substring($hostMatch.Index + $hostMatch.Length)
    if ([string]::IsNullOrWhiteSpace($tail)) { return $null }

    $tokenMatches = [regex]::Matches($tail, '(?is)-(?<name>[a-z]+)\b')
    foreach ($tokenMatch in $tokenMatches) {
        $paramName = [string]$tokenMatch.Groups['name'].Value
        $valueStart = $tokenMatch.Index + $tokenMatch.Length
        $remaining = $tail.Substring($valueStart).TrimStart()
        if ([string]::IsNullOrWhiteSpace($remaining)) { continue }

        if (Test-PowerShellHostParameterPrefix -ParameterName $paramName -CanonicalName 'encodedcommand') {
            $valueMatch = [regex]::Match($remaining, '^(?<value>["'']?[^"''\s]+["'']?)')
            if (-not $valueMatch.Success) { continue }

            $encodedValue = [string]$valueMatch.Groups['value'].Value
            if (($encodedValue.StartsWith('"') -and $encodedValue.EndsWith('"')) -or ($encodedValue.StartsWith("'") -and $encodedValue.EndsWith("'"))) {
                $encodedValue = $encodedValue.Substring(1, $encodedValue.Length - 2)
            }

            $decoded = Try-DecodeEncodedCommandValue -Base64String $encodedValue
            if (-not [string]::IsNullOrWhiteSpace($decoded)) {
                return [PSCustomObject]@{
                    CommandName = $hostMatch.Groups['cmd'].Value
                    DynamicType = 'EncodedCommand'
                    PayloadText = $decoded
                }
            }
        }

        if (Test-PowerShellHostParameterPrefix -ParameterName $paramName -CanonicalName 'command') {
            $payloadText = $remaining.Trim()
            if ([string]::IsNullOrWhiteSpace($payloadText)) { continue }

            if ($payloadText.StartsWith('"')) {
                if ($payloadText.Length -ge 2 -and $payloadText.EndsWith('"')) {
                    $payloadText = $payloadText.Substring(1, $payloadText.Length - 2)
                } else {
                    $payloadText = $payloadText.Substring(1)
                }
            } elseif ($payloadText.StartsWith("'")) {
                if ($payloadText.Length -ge 2 -and $payloadText.EndsWith("'")) {
                    $payloadText = $payloadText.Substring(1, $payloadText.Length - 2)
                } else {
                    $payloadText = $payloadText.Substring(1)
                }
            }

            if (-not [string]::IsNullOrWhiteSpace($payloadText)) {
                return [PSCustomObject]@{
                    CommandName = $hostMatch.Groups['cmd'].Value
                    DynamicType = 'PowerShellCommand'
                    PayloadText = $payloadText
                }
            }
        }
    }

    return $null
}

function Get-BestEffortParseFallbackScriptText {
    param(
        [Parameter(Mandatory)][string]$ScriptText,
        [string]$ParseError
    )

    $payloadInfo = Try-GetWholeScriptHostPayloadInfo -ScriptText $ScriptText
    if (-not $payloadInfo) {
        $payloadInfo = Try-GetWholeScriptHostPayloadInfoLoose -ScriptText $ScriptText
    }

    $body = if ($payloadInfo -and -not [string]::IsNullOrWhiteSpace([string]$payloadInfo.PayloadText)) {
        [string]$payloadInfo.PayloadText
    } else {
        $ScriptText
    }

    $normalizedBody = Invoke-NormalizePlainScriptText -ScriptText $body
    if (-not [string]::IsNullOrWhiteSpace($normalizedBody)) {
        $body = $normalizedBody
    }

    $errorText = if ([string]::IsNullOrWhiteSpace($ParseError)) {
        'unknown parse error'
    } else {
        ([string]$ParseError -replace '[\r\n]+', ' ').Trim()
    }

    return "# [ParseFallback] $errorText`r`n$body"
}

function Get-StaticBinaryOperatorText {
    param($BinaryAst)

    if ($BinaryAst -and $BinaryAst.PSObject.Properties['ErrorPosition'] -and $BinaryAst.ErrorPosition) {
        return [string]$BinaryAst.ErrorPosition.Text
    }

    $op = if ($BinaryAst -and $BinaryAst.PSObject.Properties['Operator']) { [string]$BinaryAst.Operator } else { [string]$BinaryAst }
    switch ($op) {
        'Plus' { return '+' }
        'Minus' { return '-' }
        'Multiply' { return '*' }
        'Divide' { return '/' }
        'Remainder' { return '%' }
        'Rem' { return '%' }
        'Join' { return '-join' }
        'Format' { return '-f' }
        'And' { return '-and' }
        'Or' { return '-or' }
        'Xor' { return '-xor' }
        'Band' { return '-band' }
        'Bor' { return '-bor' }
        'Bxor' { return '-bxor' }
        'Shl' { return '-shl' }
        'Shr' { return '-shr' }
        'Ieq' { return '-eq' }
        'Ine' { return '-ne' }
        'Igt' { return '-gt' }
        'Ige' { return '-ge' }
        'Ilt' { return '-lt' }
        'Ile' { return '-le' }
        'Ilike' { return '-like' }
        'Inotlike' { return '-notlike' }
        'Imatch' { return '-match' }
        'Inotmatch' { return '-notmatch' }
        'Ireplace' { return '-replace' }
        'Isplit' { return '-split' }
        'Ceq' { return '-ceq' }
        'Cne' { return '-cne' }
        'Cgt' { return '-cgt' }
        'Cge' { return '-cge' }
        'Clt' { return '-clt' }
        'Cle' { return '-cle' }
        'Clike' { return '-clike' }
        'Cnotlike' { return '-cnotlike' }
        'Cmatch' { return '-cmatch' }
        'Cnotmatch' { return '-cnotmatch' }
        'Creplace' { return '-creplace' }
        'Csplit' { return '-csplit' }
        default { return $null }
    }
}

function Get-StaticUnaryOperatorText {
    param($TokenKind)

    $kind = [string]$TokenKind
    switch ($kind) {
        'Plus' { return '+' }
        'Minus' { return '-' }
        'Not' { return '-not' }
        'Exclaim' { return '!' }
        'Bnot' { return '-bnot' }
        default { return $null }
    }
}

function Get-StaticConvertTypeName {
    param([System.Management.Automation.Language.ConvertExpressionAst]$ConvertAst)

    if ($null -eq $ConvertAst -or $null -eq $ConvertAst.Type -or $null -eq $ConvertAst.Type.TypeName) {
        return $null
    }
    return [string]$ConvertAst.Type.TypeName.FullName
}

function Test-StaticAstStringCompatible {
    param(
        $Ast,
        [hashtable]$Context
    )

    if ($null -eq $Ast) { return $false }

    if ($Ast -is [System.Management.Automation.Language.StringConstantExpressionAst]) { return $true }
    if ($Ast -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) { return $true }
    if ($Ast -is [System.Management.Automation.Language.ConstantExpressionAst]) {
        return (($Ast.Value -is [string]) -or ($Ast.Value -is [char]))
    }
    if ($Ast -is [System.Management.Automation.Language.VariableExpressionAst]) {
        $resolved = Resolve-StaticVariableValue -Context $Context -Ast $Ast -AllowEmptyFallback:$false
        if (-not $resolved.Success) { return $false }
        return (($resolved.Value -is [string]) -or ($resolved.Value -is [char]))
    }
    if ($Ast -is [System.Management.Automation.Language.ConvertExpressionAst]) {
        $typeName = Get-StaticConvertTypeName -ConvertAst $Ast
        return ($typeName -and $typeName.ToLowerInvariant() -eq 'string')
    }
    if ($Ast -is [System.Management.Automation.Language.BinaryExpressionAst]) {
        $op = [string]$Ast.Operator
        if ($op -in @('Join', 'Format')) { return $true }
        if ($op -eq 'Plus') {
            return ((Test-StaticAstStringCompatible -Ast $Ast.Left -Context $Context) -or (Test-StaticAstStringCompatible -Ast $Ast.Right -Context $Context))
        }
        return $false
    }
    if ($Ast -is [System.Management.Automation.Language.ParenExpressionAst]) {
        $expr = Get-StaticExpressionFromPipelineAst -PipelineAst $Ast.Pipeline
        if ($null -eq $expr) { return $false }
        return (Test-StaticAstStringCompatible -Ast $expr -Context $Context)
    }
    if ($Ast -is [System.Management.Automation.Language.SubExpressionAst]) {
        $statements = Get-StaticExpressionFromStatementBlock -StatementBlockAst $Ast.SubExpression
        if ($null -eq $statements -or $statements.Count -ne 1) { return $false }
        $expr = Get-StaticExpressionFromPipelineAst -PipelineAst $statements[0]
        if ($null -eq $expr) { return $false }
        return (Test-StaticAstStringCompatible -Ast $expr -Context $Context)
    }
    return $false
}

function Resolve-StaticVariableValue {
    param(
        [hashtable]$Context,
        [System.Management.Automation.Language.VariableExpressionAst]$Ast,
        [bool]$AllowEmptyFallback = $false
    )

    if ($null -eq $Ast -or $null -eq $Ast.VariablePath) {
        return [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = $false; Reason = 'invalid_variable'; Message = '变量 AST 无效' }
    }

    $name = [string]$Ast.VariablePath.UserPath
    switch ($name.ToLowerInvariant()) {
        'true'  { return [PSCustomObject]@{ Success = $true; Value = $true; UsedEmptyFallback = $false; Reason = $null; Message = $null } }
        'false' { return [PSCustomObject]@{ Success = $true; Value = $false; UsedEmptyFallback = $false; Reason = $null; Message = $null } }
        'null'  { return [PSCustomObject]@{ Success = $true; Value = $null; UsedEmptyFallback = $false; Reason = $null; Message = $null } }
    }

    $psVar = $null
    try {
        if ($Context -and $Context.ExecContext -and $Context.ExecContext.Runspace) {
            $psVar = $Context.ExecContext.Runspace.SessionStateProxy.PSVariable.Get($name)
        }
    } catch {
        $psVar = $null
    }

    if ($null -ne $psVar) {
        $value = $psVar.Value
        if (Test-StaticBindingValue -Value $value) {
            return [PSCustomObject]@{ Success = $true; Value = $value; UsedEmptyFallback = $false; Reason = $null; Message = $null }
        }
        return [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = $false; Reason = 'complex_variable'; Message = ('变量值类型不支持静态求值: ' + (Get-StaticValueTypeName -Value $value)) }
    }

    if ($AllowEmptyFallback) {
        return [PSCustomObject]@{ Success = $true; Value = ''; UsedEmptyFallback = $true; Reason = $null; Message = $null }
    }

    return [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = $false; Reason = 'missing_variable'; Message = ('变量不存在: $' + $name) }
}
function Invoke-StaticBinaryOperator {
    param(
        [string]$OperatorText,
        $LeftValue,
        $RightValue
    )

    if ([string]::IsNullOrWhiteSpace($OperatorText)) {
        return [PSCustomObject]@{ Success = $false; Value = $null; Message = '未知二元操作符' }
    }

    if (-not $script:StaticEvalOperatorCache) { $script:StaticEvalOperatorCache = @{} }
    $cacheKey = 'Binary|' + $OperatorText
    if (-not $script:StaticEvalOperatorCache.ContainsKey($cacheKey)) {
        $script:StaticEvalOperatorCache[$cacheKey] = [scriptblock]::Create('param($__left,$__right) $__left ' + $OperatorText + ' $__right')
    }

    try {
        $value = & $script:StaticEvalOperatorCache[$cacheKey] $LeftValue $RightValue
        return [PSCustomObject]@{ Success = $true; Value = $value; Message = $null }
    } catch {
        return [PSCustomObject]@{ Success = $false; Value = $null; Message = $_.Exception.Message }
    }
}

function Invoke-StaticUnaryOperator {
    param(
        [string]$OperatorText,
        $Value
    )

    if ([string]::IsNullOrWhiteSpace($OperatorText)) {
        return [PSCustomObject]@{ Success = $false; Value = $null; Message = '未知一元操作符' }
    }

    if (-not $script:StaticEvalOperatorCache) { $script:StaticEvalOperatorCache = @{} }
    $cacheKey = 'Unary|' + $OperatorText
    if (-not $script:StaticEvalOperatorCache.ContainsKey($cacheKey)) {
        $script:StaticEvalOperatorCache[$cacheKey] = [scriptblock]::Create('param($__value) ' + $OperatorText + ' $__value')
    }

    try {
        $result = & $script:StaticEvalOperatorCache[$cacheKey] $Value
        return [PSCustomObject]@{ Success = $true; Value = $result; Message = $null }
    } catch {
        return [PSCustomObject]@{ Success = $false; Value = $null; Message = $_.Exception.Message }
    }
}

function Invoke-StaticConvertOperator {
    param(
        [string]$TypeName,
        $Value
    )

    if ([string]::IsNullOrWhiteSpace($TypeName)) {
        return [PSCustomObject]@{ Success = $false; Value = $null; Message = '未知转换类型' }
    }

    if (-not $script:StaticEvalOperatorCache) { $script:StaticEvalOperatorCache = @{} }
    $cacheKey = 'Convert|' + $TypeName
    if (-not $script:StaticEvalOperatorCache.ContainsKey($cacheKey)) {
        $script:StaticEvalOperatorCache[$cacheKey] = [scriptblock]::Create('param($__value) [' + $TypeName + ']$__value')
    }

    try {
        $result = & $script:StaticEvalOperatorCache[$cacheKey] $Value
        return [PSCustomObject]@{ Success = $true; Value = $result; Message = $null }
    } catch {
        return [PSCustomObject]@{ Success = $false; Value = $null; Message = $_.Exception.Message }
    }
}

# 辅助函数：尝试解码 powershell/pwsh -EncodedCommand 调用
# 如果是 EncodedCommand 调用，返回解码信息；否则返回 $null
function Try-DecodeEncodedCommand {
    param(
        [Parameter(Mandatory=$true)]
        [System.Management.Automation.Language.CommandAst]$CommandAst
    )

    # 获取命令名
    $cmdName = $CommandAst.GetCommandName()
    # 支持完整路径和简单命令名
    if ($cmdName -notmatch '(?i)(^|[/\\])(powershell|pwsh)(\.exe)?$') {
        return $null
    }

    # 遍历参数查找 -EncodedCommand 或 -enc
    $elements = $CommandAst.CommandElements
    for ($i = 1; $i -lt $elements.Count; $i++) {
        $elem = $elements[$i]

        # 检查是否是 -EncodedCommand 或 -enc 参数
        if ($elem -is [System.Management.Automation.Language.CommandParameterAst]) {
            $paramName = $elem.ParameterName.ToLower()

            if ($paramName -match '^(encodedcommand|enc|e)$') {
                # 获取下一个元素（Base64 字符串）
                if ($i + 1 -lt $elements.Count) {
                    $valueElem = $elements[$i + 1]
                    $base64String = $null

                    # 提取 Base64 字符串
                    if ($valueElem -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                        $base64String = $valueElem.Value
                    } elseif ($valueElem -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) {
                        $base64String = $valueElem.Value
                    }

                    if ($base64String) {
                        try {
                            # 解码 Base64
                            $bytes = [Convert]::FromBase64String($base64String)

                            # PowerShell 的 -EncodedCommand 使用 Unicode (UTF-16LE) 编码
                            $decoded = [Text.Encoding]::Unicode.GetString($bytes)

                            # 构造替换后的命令文本
                            # 将 -EncodedCommand <base64> 统一替换为 -Command @'... '@，
                            # 避免双引号/可扩展字符串带来的提前变量插值问题。
                            $replacementText = ConvertTo-CanonicalPowerShellHostCommandText -CommandAst $CommandAst -PayloadText $decoded

                            return @{
                                ReplacementText = $replacementText
                                DecodedContent = $decoded
                                OriginalBase64 = $base64String
                                IsRawScript    = $true
                            }

                        } catch {
                            Write-Warning "[EncodedCommand] 解码失败: $_"
                            return $null
                        }
                    }
                }
            }
        }
    }

    return $null
}

function Resolve-StaticAstValue {
    param(
        $Ast,
        [hashtable]$Context,
        [bool]$AllowEmptyFallback = $false
    )

    if ($null -eq $Ast) {
        return [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = $false; Reason = 'no_ast'; Message = 'AST 为空' }
    }

    if ($Ast -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
        return [PSCustomObject]@{ Success = $true; Value = $Ast.Value; UsedEmptyFallback = $false; Reason = $null; Message = $null }
    }
    if ($Ast -is [System.Management.Automation.Language.ConstantExpressionAst]) {
        return [PSCustomObject]@{ Success = $true; Value = $Ast.Value; UsedEmptyFallback = $false; Reason = $null; Message = $null }
    }
    if ($Ast -is [System.Management.Automation.Language.VariableExpressionAst]) {
        return (Resolve-StaticVariableValue -Context $Context -Ast $Ast -AllowEmptyFallback:$AllowEmptyFallback)
    }
    if ($Ast -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) {
        $text = [string]$Ast.Value
        $usedFallback = $false
        foreach ($nested in @($Ast.NestedExpressions)) {
            $nestedResult = Resolve-StaticAstValue -Ast $nested -Context $Context -AllowEmptyFallback:$true
            if (-not $nestedResult.Success) {
                return [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = $usedFallback; Reason = 'expandable_nested'; Message = $nestedResult.Message }
            }
            $usedFallback = ($usedFallback -or [bool]$nestedResult.UsedEmptyFallback)
            $replacementText = Convert-StaticInterpolatedValueToString -Value $nestedResult.Value
            $text = Replace-FirstOccurrence -Text $text -OldValue ([string]$nested.Extent.Text) -NewValue $replacementText
        }
        return [PSCustomObject]@{ Success = $true; Value = $text; UsedEmptyFallback = $usedFallback; Reason = $null; Message = $null }
    }
    if ($Ast -is [System.Management.Automation.Language.ConvertExpressionAst]) {
        $typeName = Get-StaticConvertTypeName -ConvertAst $Ast
        $childAllowFallback = ($typeName -and $typeName.ToLowerInvariant() -eq 'string')
        $childResult = Resolve-StaticAstValue -Ast $Ast.Child -Context $Context -AllowEmptyFallback:$childAllowFallback
        if (-not $childResult.Success) {
            return [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = [bool]$childResult.UsedEmptyFallback; Reason = 'convert_child'; Message = $childResult.Message }
        }
        $convertResult = Invoke-StaticConvertOperator -TypeName $typeName -Value $childResult.Value
        if (-not $convertResult.Success) {
            return [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = [bool]$childResult.UsedEmptyFallback; Reason = 'convert_failed'; Message = $convertResult.Message }
        }
        return [PSCustomObject]@{ Success = $true; Value = $convertResult.Value; UsedEmptyFallback = [bool]$childResult.UsedEmptyFallback; Reason = $null; Message = $null }
    }
    if ($Ast -is [System.Management.Automation.Language.UnaryExpressionAst]) {
        $tokenName = [string]$Ast.TokenKind
        if ($tokenName -in @('PlusPlus', 'MinusMinus', 'PostfixPlusPlus', 'PostfixMinusMinus')) {
            return [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = $false; Reason = 'unsupported_unary'; Message = '不支持有副作用的一元操作' }
        }
        $childResult = Resolve-StaticAstValue -Ast $Ast.Child -Context $Context -AllowEmptyFallback:$false
        if (-not $childResult.Success) {
            return [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = [bool]$childResult.UsedEmptyFallback; Reason = 'unary_child'; Message = $childResult.Message }
        }
        $operatorText = Get-StaticUnaryOperatorText -TokenKind $Ast.TokenKind
        $unaryResult = Invoke-StaticUnaryOperator -OperatorText $operatorText -Value $childResult.Value
        if (-not $unaryResult.Success) {
            return [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = [bool]$childResult.UsedEmptyFallback; Reason = 'unary_failed'; Message = $unaryResult.Message }
        }
        return [PSCustomObject]@{ Success = $true; Value = $unaryResult.Value; UsedEmptyFallback = [bool]$childResult.UsedEmptyFallback; Reason = $null; Message = $null }
    }
    if ($Ast -is [System.Management.Automation.Language.BinaryExpressionAst]) {
        $operatorName = [string]$Ast.Operator
        $childAllowFallback = $false
        if ($operatorName -in @('Join', 'Format')) {
            $childAllowFallback = $true
        } elseif ($operatorName -eq 'Plus') {
            $childAllowFallback = (Test-StaticAstStringCompatible -Ast $Ast -Context $Context)
        }

        $leftResult = Resolve-StaticAstValue -Ast $Ast.Left -Context $Context -AllowEmptyFallback:$childAllowFallback
        if (-not $leftResult.Success) {
            return [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = [bool]$leftResult.UsedEmptyFallback; Reason = 'binary_left'; Message = $leftResult.Message }
        }
        $rightResult = Resolve-StaticAstValue -Ast $Ast.Right -Context $Context -AllowEmptyFallback:$childAllowFallback
        if (-not $rightResult.Success) {
            return [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = ([bool]$leftResult.UsedEmptyFallback -or [bool]$rightResult.UsedEmptyFallback); Reason = 'binary_right'; Message = $rightResult.Message }
        }

        $opText = Get-StaticBinaryOperatorText -BinaryAst $Ast
        $binaryResult = Invoke-StaticBinaryOperator -OperatorText $opText -LeftValue $leftResult.Value -RightValue $rightResult.Value
        if (-not $binaryResult.Success) {
            return [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = ([bool]$leftResult.UsedEmptyFallback -or [bool]$rightResult.UsedEmptyFallback); Reason = 'binary_failed'; Message = $binaryResult.Message }
        }

        return [PSCustomObject]@{
            Success = $true
            Value = $binaryResult.Value
            UsedEmptyFallback = ([bool]$leftResult.UsedEmptyFallback -or [bool]$rightResult.UsedEmptyFallback)
            Reason = $null
            Message = $null
        }
    }
    if ($Ast -is [System.Management.Automation.Language.ParenExpressionAst]) {
        $expr = Get-StaticExpressionFromPipelineAst -PipelineAst $Ast.Pipeline
        if ($null -eq $expr) {
            return [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = $false; Reason = 'unsupported_paren'; Message = '括号表达式不是简单表达式' }
        }
        return (Resolve-StaticAstValue -Ast $expr -Context $Context -AllowEmptyFallback:$AllowEmptyFallback)
    }
    if ($Ast -is [System.Management.Automation.Language.SubExpressionAst]) {
        $statements = Get-StaticExpressionFromStatementBlock -StatementBlockAst $Ast.SubExpression
        if ($null -eq $statements) {
            return [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = $false; Reason = 'unsupported_subexpression'; Message = '子表达式包含 trap 或为空' }
        }

        $values = @()
        $usedFallback = $false
        foreach ($statement in $statements) {
            $expr = Get-StaticExpressionFromPipelineAst -PipelineAst $statement
            if ($null -eq $expr) {
                return [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = $usedFallback; Reason = 'unsupported_pipeline'; Message = '子表达式包含暂不支持的语句类型' }
            }
            $exprResult = Resolve-StaticAstValue -Ast $expr -Context $Context -AllowEmptyFallback:$AllowEmptyFallback
            if (-not $exprResult.Success) {
                return [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = ($usedFallback -or [bool]$exprResult.UsedEmptyFallback); Reason = 'subexpression_child'; Message = $exprResult.Message }
            }
            $usedFallback = ($usedFallback -or [bool]$exprResult.UsedEmptyFallback)
            $values += ,$exprResult.Value
        }

        if ($values.Count -eq 0) {
            return [PSCustomObject]@{ Success = $true; Value = @(); UsedEmptyFallback = $usedFallback; Reason = $null; Message = $null }
        }
        if ($values.Count -eq 1) {
            return [PSCustomObject]@{ Success = $true; Value = $values[0]; UsedEmptyFallback = $usedFallback; Reason = $null; Message = $null }
        }
        return [PSCustomObject]@{ Success = $true; Value = @($values); UsedEmptyFallback = $usedFallback; Reason = $null; Message = $null }
    }
    if ($Ast -is [System.Management.Automation.Language.ArrayLiteralAst]) {
        $values = @()
        $usedFallback = $false
        foreach ($element in @($Ast.Elements)) {
            $itemResult = Resolve-StaticAstValue -Ast $element -Context $Context -AllowEmptyFallback:$AllowEmptyFallback
            if (-not $itemResult.Success) {
                return [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = ($usedFallback -or [bool]$itemResult.UsedEmptyFallback); Reason = 'array_literal_child'; Message = $itemResult.Message }
            }
            $usedFallback = ($usedFallback -or [bool]$itemResult.UsedEmptyFallback)
            $values += ,$itemResult.Value
        }
        return [PSCustomObject]@{ Success = $true; Value = @($values); UsedEmptyFallback = $usedFallback; Reason = $null; Message = $null }
    }
    if ($Ast -is [System.Management.Automation.Language.ArrayExpressionAst]) {
        $statements = Get-StaticExpressionFromStatementBlock -StatementBlockAst $Ast.SubExpression
        if ($null -eq $statements) {
            return [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = $false; Reason = 'unsupported_array_expression'; Message = '数组表达式包含 trap 或为空' }
        }

        $values = @()
        $usedFallback = $false
        foreach ($statement in $statements) {
            $expr = Get-StaticExpressionFromPipelineAst -PipelineAst $statement
            if ($null -eq $expr) {
                return [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = $usedFallback; Reason = 'unsupported_pipeline'; Message = '数组表达式包含暂不支持的语句类型' }
            }
            $exprResult = Resolve-StaticAstValue -Ast $expr -Context $Context -AllowEmptyFallback:$AllowEmptyFallback
            if (-not $exprResult.Success) {
                return [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = ($usedFallback -or [bool]$exprResult.UsedEmptyFallback); Reason = 'array_expression_child'; Message = $exprResult.Message }
            }
            $usedFallback = ($usedFallback -or [bool]$exprResult.UsedEmptyFallback)
            if (($exprResult.Value -is [System.Collections.IEnumerable]) -and -not ($exprResult.Value -is [string])) {
                foreach ($item in $exprResult.Value) {
                    $values += ,$item
                }
            } else {
                $values += ,$exprResult.Value
            }
        }
        return [PSCustomObject]@{ Success = $true; Value = @($values); UsedEmptyFallback = $usedFallback; Reason = $null; Message = $null }
    }
    if ($Ast -is [System.Management.Automation.Language.CommandAst]) {
        # 尝试解码 powershell/pwsh -EncodedCommand 调用
        $decodedInfo = Try-DecodeEncodedCommand -CommandAst $Ast
        if ($decodedInfo) {
            # 返回解码后的文本作为“原样脚本文本”替换结果，避免后续被序列化成单引号字符串
            return [PSCustomObject]@{
                Success            = $true
                Value              = $decodedInfo.ReplacementText
                RawReplacementText = $decodedInfo.ReplacementText
                UsedEmptyFallback  = $false
                Reason             = $null
                Message            = $null
            }
        }
        # 如果不是 EncodedCommand，返回失败
        return [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = $false; Reason = 'unsupported_command'; Message = 'CommandAst 不是 EncodedCommand 调用' }
    }

    return [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = $false; Reason = 'unsupported_ast'; Message = ('不支持的 AST 类型: ' + $Ast.GetType().Name) }
}

function Get-ReplacementCandidatePriority {
    param($Candidate)

    if (-not $Candidate) { return 0 }
    $sourceKind = if ($Candidate.PSObject.Properties['SourceKind']) { [string]$Candidate.SourceKind } else { '' }
    if ($sourceKind -eq 'Static') {
        if ($Candidate.PSObject.Properties['UsedEmptyFallback'] -and [bool]$Candidate.UsedEmptyFallback) { return 100 }
        return 200
    }
    if ($sourceKind -eq 'DynamicInvoke') { return 400 }
    if ($sourceKind -eq 'LiteralizedCommand') { return 380 }
    if ($sourceKind -eq 'VariableRead') { return 350 }
    return 300
}

function Get-LiteralizedCommandReplacementCandidates {
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][string]$ScriptText
    )

    $candidates = @()
    $skipped = @()

    if (-not $Context.ContainsKey('LiteralizedCommandResults') -or -not $Context.LiteralizedCommandResults -or $Context.LiteralizedCommandResults.Count -eq 0) {
        return [PSCustomObject]@{
            Candidates = @()
            Skipped    = @()
        }
    }

    foreach ($rec in @($Context.LiteralizedCommandResults)) {
        if (-not $rec) { continue }

        $start = if ($rec.PSObject.Properties['StartOffset']) { $rec.StartOffset } else { $null }
        $end = if ($rec.PSObject.Properties['EndOffset']) { $rec.EndOffset } else { $null }
        $replacement = if ($rec.PSObject.Properties['ReplacementText']) { [string]$rec.ReplacementText } else { $null }
        $nodeId = if ($rec.PSObject.Properties['NodeId']) { $rec.NodeId } else { $null }

        $baseItem = [PSCustomObject]@{
            StartOffset = $start
            EndOffset   = $end
            Type        = 'LiteralizedCommand'
            Depth       = $null
            NodeId      = $nodeId
        }

        $node = if ($Context.CFG -and $nodeId) { Get-NodeById -CFG $Context.CFG -Id $nodeId } else { $null }
        if ($node -and $node.PSObject.Properties['RuntimeGenerated'] -and [bool]$node.RuntimeGenerated) {
            $skipped += New-SkipRecord -Reason 'literalized_runtime_node' -Message '运行时子图中的安全命令折叠结果不直接回写原脚本' -Item $baseItem
            continue
        }

        if ($null -eq $start -or $null -eq $end) {
            $skipped += New-SkipRecord -Reason 'literalized_no_offset' -Message '安全命令折叠结果无 offset，跳过' -Item $baseItem
            continue
        }
        if ($start -lt 0 -or $end -le $start -or $end -gt $ScriptText.Length) {
            $skipped += New-SkipRecord -Reason 'literalized_out_of_range' -Message "安全命令折叠 offset 越界: [$start-$end], len=$($ScriptText.Length)" -Item $baseItem
            continue
        }
        if ([string]::IsNullOrWhiteSpace($replacement)) {
            $skipped += New-SkipRecord -Reason 'literalized_empty' -Message '安全命令折叠 replacement 为空，跳过' -Item $baseItem
            continue
        }

        $original = $ScriptText.Substring($start, $end - $start)
        if ($original -eq $replacement) {
            $skipped += New-SkipRecord -Reason 'literalized_no_change' -Message '安全命令折叠 replacement 与原片段一致' -Item $baseItem
            continue
        }

        $candidates += [PSCustomObject]@{
            StartOffset = $start
            EndOffset   = $end
            Replacement = $replacement
            Original    = $original
            Type        = 'LiteralizedCommand'
            Depth       = $null
            NodeId      = $nodeId
            SourceKind  = 'LiteralizedCommand'
            Confidence  = 'High'
            UsedEmptyFallback = $false
            ResultType  = 'String'
            Executed    = $true
            VariableName = if ($rec.PSObject.Properties['VariableName']) { $rec.VariableName } else { $null }
            Pattern      = if ($rec.PSObject.Properties['Pattern']) { $rec.Pattern } else { $null }
        }
    }

    $merged = Merge-ReplacementCandidatesByRange -Candidates $candidates
    return [PSCustomObject]@{
        Candidates = @($merged.Candidates)
        Skipped    = @($skipped) + @($merged.Skipped)
    }
}

function Get-DynamicInvokeReplacementCandidates {
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][string]$ScriptText
    )

    $candidates = @()
    $skipped = @()

    if (-not $Context.DynamicInvokeResults -or $Context.DynamicInvokeResults.Count -eq 0) {
        return [PSCustomObject]@{
            Candidates = @()
            Skipped    = @()
        }
    }

    foreach ($rec in $Context.DynamicInvokeResults) {
        if (-not $rec) { continue }

        $nodeId = if ($rec -is [hashtable]) { $rec['NodeId'] } else { $rec.NodeId }
        $node = if ($Context.CFG -and $nodeId) { Get-NodeById -CFG $Context.CFG -Id $nodeId } else { $null }
        $replacementValue = if ($rec -is [hashtable]) {
            if ($rec.ContainsKey('ReplacementText') -and $null -ne $rec['ReplacementText']) { $rec['ReplacementText'] } else { $rec['ArgumentValue'] }
        } else {
            if ($rec.PSObject.Properties['ReplacementText'] -and $null -ne $rec.ReplacementText) { $rec.ReplacementText } else { $rec.ArgumentValue }
        }
        $replacement = if ($null -ne $replacementValue) { [string]$replacementValue } else { $null }

        $baseItem = [PSCustomObject]@{
            StartOffset = if ($node) { $node.TextStartOffset } else { $null }
            EndOffset   = if ($node) { $node.TextEndOffset } else { $null }
            Type        = 'DynamicInvoke'
            Depth       = $null
            NodeId      = $nodeId
        }

        if (-not $node) {
            $skipped += New-SkipRecord -Reason 'dynamic_node_missing' -Message "DynamicInvoke 节点不存在: NodeId=$nodeId" -Item $baseItem
            continue
        }
        if ($node.PSObject.Properties['RuntimeGenerated'] -and [bool]$node.RuntimeGenerated) {
            $skipped += New-SkipRecord -Reason 'dynamic_runtime_node' -Message '运行时子图中的 DynamicInvoke 不直接回写原脚本' -Item $baseItem
            continue
        }

        $start = $node.TextStartOffset
        $end = $node.TextEndOffset
        if ($null -eq $start -or $null -eq $end) {
            $skipped += New-SkipRecord -Reason 'dynamic_no_offset' -Message 'DynamicInvoke 无原始 offset，跳过' -Item $baseItem
            continue
        }
        if ($start -lt 0 -or $end -le $start -or $end -gt $ScriptText.Length) {
            $skipped += New-SkipRecord -Reason 'dynamic_out_of_range' -Message "DynamicInvoke offset 越界: [$start-$end], len=$($ScriptText.Length)" -Item $baseItem
            continue
        }
        if ([string]::IsNullOrWhiteSpace($replacement)) {
            $skipped += New-SkipRecord -Reason 'dynamic_empty' -Message 'DynamicInvoke 解析结果为空，跳过' -Item $baseItem
            continue
        }

        $original = $ScriptText.Substring($start, $end - $start)
        if ($original -eq $replacement) {
            $skipped += New-SkipRecord -Reason 'no_change' -Message 'DynamicInvoke replacement 与原片段一致' -Item $baseItem
            continue
        }

        $candidates += [PSCustomObject]@{
            StartOffset = $start
            EndOffset   = $end
            Replacement = $replacement
            Original    = $original
            Type        = 'DynamicInvoke'
            Depth       = $null
            NodeId      = $nodeId
            SourceKind  = 'DynamicInvoke'
            Confidence  = 'High'
            UsedEmptyFallback = $false
            ResultType  = 'String'
            Executed    = $true
            DynamicStopReason = if ($rec -is [hashtable]) { [string]$rec['StopReason'] } else { [string]$rec.StopReason }
            DynamicStopMessage = if ($rec -is [hashtable]) { [string]$rec['StopMessage'] } else { [string]$rec.StopMessage }
        }
    }

    $merged = Merge-ReplacementCandidatesByRange -Candidates $candidates
    return [PSCustomObject]@{
        Candidates = @($merged.Candidates)
        Skipped    = @($skipped) + @($merged.Skipped)
    }
}

function Merge-ReplacementCandidatesByRange {
    param([array]$Candidates)

    if (-not $Candidates -or $Candidates.Count -eq 0) {
        return [PSCustomObject]@{ Candidates = @(); Skipped = @() }
    }

    $map = @{}
    $skipped = @()
    foreach ($cand in @($Candidates | Sort-Object StartOffset, EndOffset, NodeId, Type)) {
        if (-not $cand) { continue }
        $key = "$($cand.StartOffset):$($cand.EndOffset):$($cand.NodeId):$($cand.Type)"
        if (-not $map.ContainsKey($key)) {
            $map[$key] = $cand
            continue
        }

        $existing = $map[$key]
        if ([string]$existing.Replacement -eq [string]$cand.Replacement) {
            if ((Get-ReplacementCandidatePriority -Candidate $cand) -gt (Get-ReplacementCandidatePriority -Candidate $existing)) {
                $map[$key] = $cand
            }
            continue
        }

        $newPriority = Get-ReplacementCandidatePriority -Candidate $cand
        $oldPriority = Get-ReplacementCandidatePriority -Candidate $existing
        if ($newPriority -gt $oldPriority) {
            $skipped += New-SkipRecord -Reason 'merge_same_range' -Message '同区间候选冲突，保留更高优先级候选' -Item $existing
            $map[$key] = $cand
        } else {
            $skipped += New-SkipRecord -Reason 'merge_same_range' -Message '同区间候选冲突，保留更高优先级候选' -Item $cand
        }
    }

    return [PSCustomObject]@{
        Candidates = @($map.Values | Sort-Object StartOffset, EndOffset, NodeId, Type)
        Skipped = @($skipped)
    }
}

function Filter-CandidatesPreferDynamicInvoke {
    param([array]$Candidates)

    if (-not $Candidates -or $Candidates.Count -eq 0) {
        return [PSCustomObject]@{
            Candidates = @()
            Skipped    = @()
        }
    }

    $dynamicCandidates = @($Candidates | Where-Object { [string]$_.SourceKind -eq 'DynamicInvoke' })
    if ($dynamicCandidates.Count -eq 0) {
        return [PSCustomObject]@{
            Candidates = @($Candidates)
            Skipped    = @()
        }
    }

    $kept = @()
    $skipped = @()

    foreach ($cand in $Candidates) {
        if (-not $cand) { continue }
        if ([string]$cand.SourceKind -eq 'DynamicInvoke') {
            $kept += $cand
            continue
        }

        $coveringDynamic = $dynamicCandidates | Where-Object {
            $_.StartOffset -le $cand.StartOffset -and
            $_.EndOffset -ge $cand.EndOffset -and
            (Get-ReplacementCandidatePriority -Candidate $_) -gt (Get-ReplacementCandidatePriority -Candidate $cand)
        } | Sort-Object StartOffset, @{ Expression = { $_.EndOffset - $_.StartOffset } } | Select-Object -First 1

        if ($coveringDynamic) {
            $skipped += New-SkipRecord -Reason 'prefer_dynamic_invoke' -Message '内层候选被更高优先级的 DynamicInvoke 候选覆盖，优先保留整条动态代码替换' -Item $cand
            continue
        }

        $kept += $cand
    }

    return [PSCustomObject]@{
        Candidates = @($kept)
        Skipped    = @($skipped)
    }
}

function Get-StaticReplacementCandidates {
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][string]$ScriptText
    )

    $candidates = @()
    $skipped = @()
    $nodes = @()
    if ($Context -and $Context.CFG -and $Context.CFG.Nodes) {
        $nodes = @($Context.CFG.Nodes | Sort-Object Id)
    }

    foreach ($node in $nodes) {
        if (-not $node -or -not $node.Resolvables) {
            continue
        }
        $nodeId = [int]$node.Id

        # 注意：静态求值不应该受节点访问状态影响
        # 即使节点被执行过，静态可解析的表达式仍然应该被处理

        foreach ($r in @($node.Resolvables)) {
            if (-not $r) { continue }
            $start = $r.StartOffset
            $end = $r.EndOffset
            $baseItem = [PSCustomObject]@{
                StartOffset = $start
                EndOffset = $end
                Type = $r.Type
                Depth = $r.Depth
                NodeId = $nodeId
            }

            if ($null -eq $start -or $null -eq $end) {
                $skipped += New-SkipRecord -Reason 'static_no_offset' -Message '静态候选无 offset' -Item $baseItem
                continue
            }
            if ($start -lt 0 -or $end -le $start -or $end -gt $ScriptText.Length) {
                $skipped += New-SkipRecord -Reason 'static_out_of_range' -Message '静态候选 offset 越界' -Item $baseItem
                continue
            }
            if (-not $r.Ast) {
                $skipped += New-SkipRecord -Reason 'static_no_ast' -Message '静态候选缺少 AST' -Item $baseItem
                continue
            }

            $resolved = Resolve-StaticAstValue -Ast $r.Ast -Context $Context -AllowEmptyFallback:$false
            if (-not $resolved.Success) {
                $message = if ([string]::IsNullOrWhiteSpace([string]$resolved.Message)) { '静态求值失败' } else { [string]$resolved.Message }
                $skipped += New-SkipRecord -Reason 'static_eval_failed' -Message $message -Item $baseItem
                continue
            }
            if (-not (Test-StaticReplacementScalarValue -Value $resolved.Value)) {
                $skipped += New-SkipRecord -Reason 'static_non_scalar' -Message ('静态结果非标量: ' + (Get-StaticValueTypeName -Value $resolved.Value)) -Item $baseItem
                continue
            }

            if ($resolved.PSObject.Properties['RawReplacementText']) {
                $replacement = [string]$resolved.RawReplacementText
            } else {
                $replacement = [string](Format-ResolvableValue $resolved.Value)
            }
            if ($replacement -eq '__BLOCKED_PLACEHOLDER__') {
                $skipped += New-SkipRecord -Reason 'static_blocked' -Message '静态结果为占位符，跳过' -Item $baseItem
                continue
            }

            $original = $ScriptText.Substring($start, $end - $start)
            if ($original -eq $replacement) {
                $skipped += New-SkipRecord -Reason 'static_no_change' -Message '静态替换无变化' -Item $baseItem
                continue
            }

            $confidence = if ([bool]$resolved.UsedEmptyFallback) { 'Low' } else { 'High' }
            $candidates += [PSCustomObject]@{
                StartOffset = $start
                EndOffset = $end
                Replacement = $replacement
                Original = $original
                Type = $r.Type
                Depth = $r.Depth
                NodeId = $nodeId
                SourceKind = 'Static'
                Confidence = $confidence
                UsedEmptyFallback = [bool]$resolved.UsedEmptyFallback
                ResultType = (Get-StaticValueTypeName -Value $resolved.Value)
                Executed = $false
                VariableName = $null
                IsSimpleVariable = $false
                IsValueChanged = $false
                ObservedValueCount = 1
            }
        }
    }

    $merged = Merge-ReplacementCandidatesByRange -Candidates $candidates
    return [PSCustomObject]@{
        Candidates = @($merged.Candidates)
        Skipped = @($skipped) + @($merged.Skipped)
    }
}

function Get-ReplacementsFromResolvableResults {
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][string]$ScriptText,
        [Parameter(Mandatory)][ValidateSet('skip', 'last')][string]$VariableConflictPolicy
    )

    $candidates = @()
    $skipped = @()

    if (-not $Context.ResolvableResults -and -not $Context.VariableReadResults) {
        return [PSCustomObject]@{
            Candidates = @()
            Skipped    = @()
        }
    }

    # 同一片段（Start/End）可能被多个节点记录；若 replacement 不一致则判为冲突并跳过
    $regionMap = @{}          # key -> candidate
    $conflictRegions = @{}    # key -> @{ Replacements = @() }

    foreach ($rec in $Context.ResolvableResults.Values) {
        $r = $rec.Resolvable
        if (-not $r) { continue }

        $start = $r.StartOffset
        $end = $r.EndOffset
        $type = $r.Type
        $depth = $r.Depth
        $nodeId = $rec.NodeId

        $baseItem = [PSCustomObject]@{
            StartOffset = $start
            EndOffset   = $end
            Type        = $type
            Depth       = $depth
            NodeId      = $nodeId
        }

        $node = if ($Context.CFG -and $nodeId) { Get-NodeById -CFG $Context.CFG -Id $nodeId } else { $null }
        if ($node -and $node.PSObject.Properties['RuntimeGenerated'] -and [bool]$node.RuntimeGenerated) {
            $skipped += New-SkipRecord -Reason 'runtime_generated' -Message '运行时子图的 Resolvable 不直接回写原脚本' -Item $baseItem
            continue
        }

        if ($null -eq $start -or $null -eq $end) {
            $skipped += New-SkipRecord -Reason 'no_offset' -Message '无 StartOffset/EndOffset，无法回写' -Item $baseItem
            continue
        }

        if ($start -lt 0 -or $end -le $start -or $end -gt $ScriptText.Length) {
            $skipped += New-SkipRecord -Reason 'out_of_range' -Message "offset 越界: [$start-$end], len=$($ScriptText.Length)" -Item $baseItem
            continue
        }

        $uniqueValues = @($rec.Values | Select-Object -Unique)
        if ($uniqueValues.Count -ne 1) {
            $skipped += New-SkipRecord -Reason 'inconsistent' -Message "同一片段出现多个值: $($uniqueValues.Count)" -Item $baseItem
            continue
        }

        $replacement = [string]$uniqueValues[0]

        # 违禁命令占位符：跳过
        if ($replacement -eq '__BLOCKED_PLACEHOLDER__') {
            $skipped += New-SkipRecord -Reason 'blocked' -Message '值为占位符，跳过替换' -Item $baseItem
            continue
        }

        # $null 替换默认跳过：
        # 许多调用（如 [array]::Reverse($a)）通过副作用修改变量但返回 $null，
        # 若直接回写为 $null 会丢失原脚本语义。
        if ($replacement -eq '$null') {
            $skipped += New-SkipRecord -Reason 'null_replacement' -Message 'replacement 为 $null，默认跳过以避免破坏副作用语句' -Item $baseItem
            continue
        }

        $original = $ScriptText.Substring($start, $end - $start)
        if ($original -eq $replacement) {
            $skipped += New-SkipRecord -Reason 'no_change' -Message 'replacement 与原片段一致' -Item $baseItem
            continue
        }

        $cand = [PSCustomObject]@{
            StartOffset = $start
            EndOffset   = $end
            Replacement = $replacement
            Original    = $original
            Type        = $type
            Depth       = $depth
            NodeId      = $nodeId
            SourceKind  = 'Resolvable'
            Confidence  = 'High'
            UsedEmptyFallback = $false
            ResultType  = $null
            Executed    = $true
        }

        $key = "$start`:$end"

        if ($conflictRegions.ContainsKey($key)) {
            $skipped += New-SkipRecord -Reason 'conflict_same_range' -Message "同区间已冲突，忽略: [$start-$end]" -Item $cand
            continue
        }

        if (-not $regionMap.ContainsKey($key)) {
            $regionMap[$key] = $cand
            continue
        }

        $existing = $regionMap[$key]
        if ($existing.Replacement -eq $cand.Replacement) {
            # 同区间同 replacement：去重即可
            $skipped += New-SkipRecord -Reason 'duplicate' -Message "同区间重复记录，已去重: [$start-$end]" -Item $cand
            continue
        }

        # 同区间不同 replacement：判冲突，移除已有并跳过两者
        $conflictRegions[$key] = @{
            Replacements = @($existing.Replacement, $cand.Replacement)
        }
        $null = $regionMap.Remove($key)
        $skipped += New-SkipRecord -Reason 'conflict_same_range' -Message "同区间出现不同 replacement，跳过: [$start-$end]" -Item $existing
        $skipped += New-SkipRecord -Reason 'conflict_same_range' -Message "同区间出现不同 replacement，跳过: [$start-$end]" -Item $cand
    }

    # 额外候选：变量读取结果（简单类型），并处理“同位置多值变化”。
    # 变量位点必须是纯 Read 上下文；ReadWrite（例如 $x++、$x+=1）一律跳过。
    $varAccessKindMap = Get-VariableAccessKindMapFromScriptText -ScriptText $ScriptText
    if ($Context.VariableReadResults) {
        foreach ($rec in $Context.VariableReadResults.Values) {
            $v = $rec.VarInfo
            if (-not $v) { continue }

            $start = $v.StartOffset
            $end = $v.EndOffset
            $type = if ($v.PSObject.Properties['IsInlineResult'] -and $v.IsInlineResult) { 'Inline' } else { 'VarRead' }
            $depth = $null
            $nodeId = $rec.NodeId

            $baseItem = [PSCustomObject]@{
                StartOffset = $start
                EndOffset   = $end
                Type        = $type
                Depth       = $depth
                NodeId      = $nodeId
            }

            $node = if ($Context.CFG -and $nodeId) { Get-NodeById -CFG $Context.CFG -Id $nodeId } else { $null }
            if ($node -and $node.PSObject.Properties['RuntimeGenerated'] -and [bool]$node.RuntimeGenerated) {
                $skipped += New-SkipRecord -Reason 'runtime_generated' -Message '运行时子图的变量读取不直接回写原脚本' -Item $baseItem
                continue
            }

            if ($null -eq $start -or $null -eq $end) {
                $skipped += New-SkipRecord -Reason 'no_offset' -Message '变量读取无 StartOffset/EndOffset，无法回写' -Item $baseItem
                continue
            }

            if ($start -lt 0 -or $end -le $start -or $end -gt $ScriptText.Length) {
                $skipped += New-SkipRecord -Reason 'out_of_range' -Message "变量读取 offset 越界: [$start-$end], len=$($ScriptText.Length)" -Item $baseItem
                continue
            }

            $key = "$start`:$end"
            if ($type -eq 'VarRead' -and $varAccessKindMap.ContainsKey($key)) {
                $accessKind = [string]$varAccessKindMap[$key]
                if ($accessKind -ne 'Read') {
                    $skipped += New-SkipRecord -Reason 'var_write_context' -Message "变量位点为 $accessKind 上下文，跳过替换（避免生成无效语法）" -Item $baseItem
                    continue
                }
            }

            $allValues = @($rec.Values)
            $uniqueValues = @($allValues | Select-Object -Unique)
            $replacement = $null
            if ($uniqueValues.Count -ne 1) {
                if ($VariableConflictPolicy -eq 'skip') {
                    $skipped += New-SkipRecord -Reason 'var_inconsistent' -Message "变量读取同位置多值($($uniqueValues.Count))，策略=skip，跳过" -Item $baseItem
                    continue
                }

                $replacement = Get-LastValidVariableReplacement -Values $allValues
                if ([string]::IsNullOrWhiteSpace([string]$replacement)) {
                    $skipped += New-SkipRecord -Reason 'var_last_invalid' -Message "变量读取同位置多值($($uniqueValues.Count))，策略=last 但无可用最终值，跳过" -Item $baseItem
                    continue
                }
            } else {
                $replacement = [string]$uniqueValues[0]
            }

            if ($replacement -eq '__BLOCKED_PLACEHOLDER__') {
                $skipped += New-SkipRecord -Reason 'blocked' -Message '变量读取值为占位符，跳过替换' -Item $baseItem
                continue
            }
            if ($replacement -eq '$null') {
                $skipped += New-SkipRecord -Reason 'null_replacement' -Message '变量读取 replacement 为 $null，默认跳过' -Item $baseItem
                continue
            }
            if (-not (Test-SimpleVariableReplacementLiteral -Replacement $replacement)) {
                $skipped += New-SkipRecord -Reason 'var_not_simple' -Message '变量读取值非简单字面量，跳过替换' -Item $baseItem
                continue
            }

            $original = $ScriptText.Substring($start, $end - $start)
            if ($original -eq $replacement) {
                $skipped += New-SkipRecord -Reason 'no_change' -Message '变量读取 replacement 与原片段一致' -Item $baseItem
                continue
            }

            $cand = [PSCustomObject]@{
                StartOffset = $start
                EndOffset   = $end
                Replacement = $replacement
                Original    = $original
                Type        = $type
                Depth       = $depth
                NodeId      = $nodeId
                SourceKind  = 'VariableRead'
                Confidence  = 'High'
                UsedEmptyFallback = $false
                ResultType  = $null
                Executed    = $true
            }

            if ($conflictRegions.ContainsKey($key)) {
                $skipped += New-SkipRecord -Reason 'conflict_same_range' -Message "同区间已冲突，忽略变量读取: [$start-$end]" -Item $cand
                continue
            }
            if (-not $regionMap.ContainsKey($key)) {
                $regionMap[$key] = $cand
                continue
            }

            $existing = $regionMap[$key]
            if ($existing.Replacement -eq $cand.Replacement) {
                $skipped += New-SkipRecord -Reason 'duplicate' -Message "变量读取同区间重复记录，已去重: [$start-$end]" -Item $cand
                continue
            }

            $conflictRegions[$key] = @{
                Replacements = @($existing.Replacement, $cand.Replacement)
            }
            $null = $regionMap.Remove($key)
            $skipped += New-SkipRecord -Reason 'conflict_same_range' -Message "变量读取同区间出现不同 replacement，跳过: [$start-$end]" -Item $existing
            $skipped += New-SkipRecord -Reason 'conflict_same_range' -Message "变量读取同区间出现不同 replacement，跳过: [$start-$end]" -Item $cand
        }
    }

    $candidates = @($regionMap.Values)

    return [PSCustomObject]@{
        Candidates = $candidates
        Skipped    = $skipped
    }
}

function Select-NonOverlappingReplacements {
    param(
        [AllowEmptyCollection()]
        [array]$Candidates,
        [Parameter(Mandatory)][ValidateSet('Outer', 'Inner')][string]$Strategy
    )

    if (-not $Candidates -or $Candidates.Count -eq 0) {
        return [PSCustomObject]@{
            Selected = @()
            Skipped  = @()
        }
    }

    $selected = @()
    $skipped = @()

    if ($Strategy -eq 'Outer') {
        # 外层优先：Start 升序，End 降序（同 Start 先选更大跨度），贪心取不重叠集合
        $sorted = $Candidates | Sort-Object StartOffset, @{ Expression = 'EndOffset'; Descending = $true }
        $lastEnd = -1
        foreach ($c in $sorted) {
            if ($c.StartOffset -ge $lastEnd) {
                $selected += $c
                $lastEnd = $c.EndOffset
            } else {
                $skipped += New-SkipRecord -Reason 'overlap' -Message '与已选片段重叠（Outer 策略丢弃内层/后续）' -Item $c
            }
        }
    } else {
        # 内层优先：End 升序，Start 降序，使用“最早结束优先”的区间调度贪心
        $sorted = $Candidates | Sort-Object EndOffset, @{ Expression = 'StartOffset'; Descending = $true }
        $lastEnd = -1
        foreach ($c in $sorted) {
            if ($c.StartOffset -ge $lastEnd) {
                $selected += $c
                $lastEnd = $c.EndOffset
            } else {
                $skipped += New-SkipRecord -Reason 'overlap' -Message '与已选片段重叠（Inner 策略丢弃外层/冲突）' -Item $c
            }
        }

        # 统一按 Start 排序，便于后续替换/展示
        $selected = @($selected | Sort-Object StartOffset)
    }

    return [PSCustomObject]@{
        Selected = $selected
        Skipped  = $skipped
    }
}

function Apply-ReplacementsToText {
    param(
        [Parameter(Mandatory)][string]$Text,
        [AllowEmptyCollection()]
        [array]$Replacements
    )

    if (-not $Replacements -or $Replacements.Count -eq 0) {
        return $Text
    }

    # 从后往前替换，避免 offset 失效
    $ordered = $Replacements | Sort-Object StartOffset -Descending
    $result = $Text

    foreach ($r in $ordered) {
        $result = $result.Substring(0, $r.StartOffset) + $r.Replacement + $result.Substring($r.EndOffset)
    }

    return $result
}

function Test-PowerShellSyntax {
    param([Parameter(Mandatory)][string]$ScriptText)

    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($ScriptText, [ref]$tokens, [ref]$errors)

    $isValid = (-not $errors -or $errors.Count -eq 0)
    return [PSCustomObject]@{
        IsValid    = $isValid
        ErrorCount = if ($errors) { [int]$errors.Count } else { 0 }
        FirstError = if ($errors -and $errors.Count -gt 0) { [string]$errors[0].Message } else { $null }
    }
}

function Get-ReplacementIdentity {
    param($Replacement)

    if (-not $Replacement) { return '' }
    $start = if ($Replacement.PSObject.Properties['StartOffset']) { [string]$Replacement.StartOffset } else { '' }
    $end = if ($Replacement.PSObject.Properties['EndOffset']) { [string]$Replacement.EndOffset } else { '' }
    $type = if ($Replacement.PSObject.Properties['Type']) { [string]$Replacement.Type } else { '' }
    $nodeId = if ($Replacement.PSObject.Properties['NodeId']) { [string]$Replacement.NodeId } else { '' }
    $rep = if ($Replacement.PSObject.Properties['Replacement']) { [string]$Replacement.Replacement } else { '' }
    return "$start`:$end`:$type`:$nodeId`:$rep"
}

function Ensure-SyntaxSafeReplacements {
    param(
        [Parameter(Mandatory)][string]$ScriptText,
        [AllowEmptyCollection()][array]$Selected
    )

    if (-not $Selected -or $Selected.Count -eq 0) {
        $baseCheck = Test-PowerShellSyntax -ScriptText $ScriptText
        return [PSCustomObject]@{
            Selected         = @()
            Skipped          = @()
            BaselineIsValid  = $baseCheck.IsValid
            FinalIsValid     = $baseCheck.IsValid
            FinalError       = $null
        }
    }

    $baselineCheck = Test-PowerShellSyntax -ScriptText $ScriptText
    $skipped = @()
    $effective = @($Selected)

    function Invoke-SyntaxCheckWithReplacements {
        param(
            [string]$SourceText,
            [array]$Replacements
        )
        $candidateText = Apply-ReplacementsToText -Text $SourceText -Replacements $Replacements
        return (Test-PowerShellSyntax -ScriptText $candidateText)
    }

    $check = Invoke-SyntaxCheckWithReplacements -SourceText $ScriptText -Replacements $effective
    if ($check.IsValid) {
        return [PSCustomObject]@{
            Selected         = @($effective)
            Skipped          = @()
            BaselineIsValid  = $baselineCheck.IsValid
            FinalIsValid     = $true
            FinalError       = $null
        }
    }

    # 第一阶段：优先移除变量位点替换，再尝试移除 Inline 结果替换。
    foreach ($dropType in @('VarRead', 'Inline')) {
        if ($check.IsValid) { break }

        $toDrop = @($effective | Where-Object { [string]$_.Type -eq $dropType })
        if ($toDrop.Count -eq 0) { continue }

        foreach ($d in $toDrop) {
            $skipped += New-SkipRecord -Reason 'syntax_guard' -Message "替换后语法错误，移除 $dropType 候选" -Item $d
        }

        $effective = @($effective | Where-Object { [string]$_.Type -ne $dropType })
        $check = Invoke-SyntaxCheckWithReplacements -SourceText $ScriptText -Replacements $effective
    }

    # 第二阶段：若仍不合法，按“小跨度优先”继续移除，直到可解析或清空。
    if (-not $check.IsValid -and $effective.Count -gt 0) {
        $ordered = @($effective | Sort-Object @{ Expression = { [int]($_.EndOffset - $_.StartOffset) } }, StartOffset)
        foreach ($cand in $ordered) {
            if ($check.IsValid) { break }

            $candId = Get-ReplacementIdentity -Replacement $cand
            $next = @($effective | Where-Object { (Get-ReplacementIdentity -Replacement $_) -ne $candId })
            if ($next.Count -eq $effective.Count) { continue }

            $skipped += New-SkipRecord -Reason 'syntax_guard' -Message '替换后语法错误，移除该候选以保持脚本可解析' -Item $cand
            $effective = $next
            $check = Invoke-SyntaxCheckWithReplacements -SourceText $ScriptText -Replacements $effective
        }
    }

    # 最终兜底：若仍不合法，清空全部替换，确保输出至少保持原始可解析性。
    if (-not $check.IsValid -and $effective.Count -gt 0) {
        foreach ($left in @($effective)) {
            $skipped += New-SkipRecord -Reason 'syntax_guard_fallback' -Message '替换后仍语法错误，清空全部替换' -Item $left
        }
        $effective = @()
        $check = Invoke-SyntaxCheckWithReplacements -SourceText $ScriptText -Replacements $effective
    }

    return [PSCustomObject]@{
        Selected         = @($effective)
        Skipped          = @($skipped)
        BaselineIsValid  = $baselineCheck.IsValid
        FinalIsValid     = $check.IsValid
        FinalError       = $check.FirstError
    }
}

function Get-ScriptParseInfo {
    param([Parameter(Mandatory)][string]$ScriptText)

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($ScriptText, [ref]$tokens, [ref]$errors)

    return [PSCustomObject]@{
        Ast      = $ast
        Tokens   = $tokens
        Errors   = $errors
        IsValid  = (-not $errors -or $errors.Count -eq 0)
        FirstError = if ($errors -and $errors.Count -gt 0) { [string]$errors[0].Message } else { $null }
    }
}

function Get-SingleTopLevelCommandAst {
    param([Parameter(Mandatory)][string]$ScriptText)

    $parse = Get-ScriptParseInfo -ScriptText $ScriptText
    if (-not $parse.IsValid -or -not $parse.Ast) { return $null }

    $ast = $parse.Ast
    $statements = @()
    if ($ast.BeginBlock -and $ast.BeginBlock.Statements) { $statements += @($ast.BeginBlock.Statements) }
    if ($ast.ProcessBlock -and $ast.ProcessBlock.Statements) { $statements += @($ast.ProcessBlock.Statements) }
    if ($ast.EndBlock -and $ast.EndBlock.Statements) { $statements += @($ast.EndBlock.Statements) }

    if ($statements.Count -ne 1) { return $null }

    $statement = $statements[0]
    if ($statement -is [System.Management.Automation.Language.CommandAst]) {
        return $statement
    }
    if ($statement -is [System.Management.Automation.Language.PipelineAst] -and
        $statement.PipelineElements -and
        $statement.PipelineElements.Count -eq 1 -and
        $statement.PipelineElements[0] -is [System.Management.Automation.Language.CommandAst]) {
        return $statement.PipelineElements[0]
    }

    return $null
}

function Try-GetWholeScriptHostPayloadInfo {
    param([Parameter(Mandatory)][string]$ScriptText)

    $cmdAst = Get-SingleTopLevelCommandAst -ScriptText $ScriptText
    if (-not $cmdAst) { return $null }

    $decodedInfo = $null
    try {
        $decodedInfo = Try-DecodeEncodedCommand -CommandAst $cmdAst
    } catch {
        $decodedInfo = $null
    }

    if ($decodedInfo -and -not [string]::IsNullOrWhiteSpace([string]$decodedInfo.DecodedContent)) {
        return [PSCustomObject]@{
            CommandAst  = $cmdAst
            DynamicType = 'EncodedCommand'
            PayloadText = [string]$decodedInfo.DecodedContent
        }
    }

    if (-not (Get-Command Get-PowerShellHostDynamicInvocationInfo -ErrorAction SilentlyContinue)) {
        return $null
    }

    $hostInfo = Get-PowerShellHostDynamicInvocationInfo -CommandAst $cmdAst
    if (-not $hostInfo -or $hostInfo.DynamicType -ne 'PowerShellCommand') {
        return $null
    }

    $payloadText = $null
    if ($hostInfo.ArgumentAst -and $hostInfo.ArgumentAst.PSObject.Properties['Value']) {
        $payloadText = [string]$hostInfo.ArgumentAst.Value
    } elseif (-not [string]::IsNullOrWhiteSpace([string]$hostInfo.PayloadText)) {
        $payloadText = [string]$hostInfo.PayloadText
    }

    if ([string]::IsNullOrWhiteSpace($payloadText)) {
        return $null
    }

    return [PSCustomObject]@{
        CommandAst  = $cmdAst
        DynamicType = 'PowerShellCommand'
        PayloadText = $payloadText
    }
}

function Invoke-CanonicalizeKnownCommandAliases {
    param([Parameter(Mandatory)][string]$ScriptText)

    $aliasMap = @{
        'start' = 'Start-Process'
        'saps'  = 'Start-Process'
        'gp'    = 'Get-ItemProperty'
        'gc'    = 'Get-Content'
        'rd'    = 'Remove-Item'
    }

    $parse = Get-ScriptParseInfo -ScriptText $ScriptText
    if (-not $parse.IsValid -or -not $parse.Ast) {
        return $ScriptText
    }

    $replacements = @()
    $commandAsts = @($parse.Ast.FindAll({
            param($n)
            $n -is [System.Management.Automation.Language.CommandAst]
        }, $true))

    foreach ($cmdAst in $commandAsts) {
        if (-not $cmdAst.CommandElements -or $cmdAst.CommandElements.Count -eq 0) { continue }
        $cmdName = $cmdAst.GetCommandName()
        if ([string]::IsNullOrWhiteSpace($cmdName)) { continue }

        $canonical = $aliasMap[$cmdName.ToLowerInvariant()]
        if ([string]::IsNullOrWhiteSpace($canonical)) { continue }

        $nameAst = $cmdAst.CommandElements[0]
        if (-not $nameAst.Extent) { continue }

        $replacements += [PSCustomObject]@{
            Start = $nameAst.Extent.StartOffset
            End   = $nameAst.Extent.EndOffset
            Text  = $canonical
        }
    }

    if ($replacements.Count -eq 0) {
        return $ScriptText
    }

    $result = $ScriptText
    foreach ($r in @($replacements | Sort-Object Start -Descending)) {
        $result = $result.Substring(0, $r.Start) + $r.Text + $result.Substring($r.End)
    }

    $check = Test-PowerShellSyntax -ScriptText $result
    if ($check.IsValid) {
        return $result
    }

    return $ScriptText
}

function Format-PowerShellScriptReadable {
    param([Parameter(Mandatory)][string]$ScriptText)

    if ([string]::IsNullOrWhiteSpace($ScriptText)) {
        return $ScriptText
    }

    if ($ScriptText -match '(?m)^[ \t]*@["'']') {
        return $ScriptText
    }

    $sb = New-Object System.Text.StringBuilder
    $indent = 0
    $lineStart = $true
    $pendingIndent = $false
    $state = 'Normal'

    function Append-NewLine([System.Text.StringBuilder]$Builder, [ref]$LineStart, [ref]$PendingIndent) {
        if ($Builder.Length -eq 0 -or $Builder[$Builder.Length - 1] -ne "`n") {
            [void]$Builder.Append("`r`n")
        }
        $LineStart.Value = $true
        $PendingIndent.Value = $true
    }

    function Ensure-Indent([System.Text.StringBuilder]$Builder, [int]$Level, [ref]$LineStart, [ref]$PendingIndent) {
        if (-not $PendingIndent.Value) { return }
        for ($j = 0; $j -lt $Level; $j++) {
            [void]$Builder.Append('    ')
        }
        $PendingIndent.Value = $false
        $LineStart.Value = $false
    }

    for ($i = 0; $i -lt $ScriptText.Length; $i++) {
        $ch = $ScriptText[$i]
        $next = if ($i + 1 -lt $ScriptText.Length) { $ScriptText[$i + 1] } else { [char]0 }

        switch ($state) {
            'Single' {
                [void]$sb.Append($ch)
                if ($ch -eq "'") { $state = 'Normal' }
                $lineStart = ($ch -eq "`n")
                continue
            }
            'Double' {
                [void]$sb.Append($ch)
                if ($ch -eq '`' -and $i + 1 -lt $ScriptText.Length) {
                    $i++
                    [void]$sb.Append($ScriptText[$i])
                    $lineStart = ($ScriptText[$i] -eq "`n")
                    continue
                }
                if ($ch -eq '"') { $state = 'Normal' }
                $lineStart = ($ch -eq "`n")
                continue
            }
            'Comment' {
                [void]$sb.Append($ch)
                if ($ch -eq "`n") {
                    $state = 'Normal'
                    $lineStart = $true
                    $pendingIndent = $true
                }
                continue
            }
        }

        if ($ch -eq "`r") { continue }
        if ($ch -eq "`n") {
            Append-NewLine -Builder $sb -LineStart ([ref]$lineStart) -PendingIndent ([ref]$pendingIndent)
            continue
        }

        if ($lineStart -and ($ch -eq ' ' -or $ch -eq "`t")) {
            continue
        }

        switch ($ch) {
            "'" {
                Ensure-Indent -Builder $sb -Level $indent -LineStart ([ref]$lineStart) -PendingIndent ([ref]$pendingIndent)
                [void]$sb.Append($ch)
                $state = 'Single'
                $lineStart = $false
                continue
            }
            '"' {
                Ensure-Indent -Builder $sb -Level $indent -LineStart ([ref]$lineStart) -PendingIndent ([ref]$pendingIndent)
                [void]$sb.Append($ch)
                $state = 'Double'
                $lineStart = $false
                continue
            }
            '#' {
                Ensure-Indent -Builder $sb -Level $indent -LineStart ([ref]$lineStart) -PendingIndent ([ref]$pendingIndent)
                [void]$sb.Append($ch)
                $state = 'Comment'
                $lineStart = $false
                continue
            }
            ';' {
                Ensure-Indent -Builder $sb -Level $indent -LineStart ([ref]$lineStart) -PendingIndent ([ref]$pendingIndent)
                [void]$sb.Append(';')
                Append-NewLine -Builder $sb -LineStart ([ref]$lineStart) -PendingIndent ([ref]$pendingIndent)
                continue
            }
            '{' {
                Ensure-Indent -Builder $sb -Level $indent -LineStart ([ref]$lineStart) -PendingIndent ([ref]$pendingIndent)
                [void]$sb.Append('{')
                $indent++
                Append-NewLine -Builder $sb -LineStart ([ref]$lineStart) -PendingIndent ([ref]$pendingIndent)
                continue
            }
            '}' {
                if (-not $lineStart) {
                    Append-NewLine -Builder $sb -LineStart ([ref]$lineStart) -PendingIndent ([ref]$pendingIndent)
                }
                $indent = [Math]::Max(0, $indent - 1)
                Ensure-Indent -Builder $sb -Level $indent -LineStart ([ref]$lineStart) -PendingIndent ([ref]$pendingIndent)
                [void]$sb.Append('}')
                $lineStart = $false
                continue
            }
            default {
                Ensure-Indent -Builder $sb -Level $indent -LineStart ([ref]$lineStart) -PendingIndent ([ref]$pendingIndent)
                [void]$sb.Append($ch)
                $lineStart = $false
            }
        }
    }

    $formatted = $sb.ToString()
    $formatted = [regex]::Replace($formatted, '(?m)[ \t]+$', '')
    $filteredLines = New-Object System.Collections.Generic.List[string]
    foreach ($line in @($formatted -split "\r?\n")) {
        if ($line -match "^\s*'(?:[^']|'')*'\s*;?\s*$") {
            continue
        }
        $filteredLines.Add($line)
    }
    $formatted = ($filteredLines -join "`r`n")
    $formatted = [regex]::Replace($formatted, "(\r?\n){3,}", "`r`n`r`n")
    $formatted = $formatted.Trim()

    if ([string]::IsNullOrWhiteSpace($formatted)) {
        return $ScriptText
    }

    return ($formatted + "`r`n")
}

function Invoke-NormalizePlainScriptText {
    param([Parameter(Mandatory)][string]$ScriptText)

    $working = $ScriptText
    $working = Invoke-CanonicalizeKnownCommandAliases -ScriptText $working

    if ($working -notmatch "[`r`n]" -and $working.Contains(';')) {
        $lineBroken = ($working -replace ';', ";`r`n")
        $lineBreakCheck = Test-PowerShellSyntax -ScriptText $lineBroken
        if ($lineBreakCheck.IsValid) {
            $working = $lineBroken
        }
    }

    $formatted = Format-PowerShellScriptReadable -ScriptText $working
    $check = Test-PowerShellSyntax -ScriptText $formatted
    if ($check.IsValid) {
        $working = $formatted
    }

    return $working
}

function Invoke-PostProcessDeobfuscatedScriptText {
    param([Parameter(Mandatory)][string]$ScriptText)

    $working = $ScriptText

    while ($true) {
        $payloadInfo = Try-GetWholeScriptHostPayloadInfo -ScriptText $working
        if (-not $payloadInfo) { break }

        $payloadText = [string]$payloadInfo.PayloadText
        if ([string]::IsNullOrWhiteSpace($payloadText)) { break }

        $payloadParse = Get-ScriptParseInfo -ScriptText $payloadText
        if (-not $payloadParse.IsValid) { break }

        $working = $payloadText
    }

    $normalized = Invoke-NormalizePlainScriptText -ScriptText $working
    $check = Test-PowerShellSyntax -ScriptText $normalized
    if ($check.IsValid) {
        return $normalized
    }

    return $working
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Object
    )

    $json = $Object | ConvertTo-Json -Depth 10
    Set-Content -LiteralPath $Path -Value $json -Encoding UTF8
}

function New-CfgFromText {
    param(
        [Parameter(Mandatory)][string]$ScriptText
    )

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($ScriptText, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count -gt 0) {
        throw "脚本解析失败: $($errors[0].Message)"
    }

    # 复刻 Get-ScriptControlFlow 的 CFG 初始化（但不依赖文件路径）
    $cfg = @{
        Nodes = @()
        Edges = @()
        DefinedFunctions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        ProcessedScriptBlocks = @{}
        DefinedAliases = @{}
    }

    Convert-AstNode -cfg $cfg -node $ast -prevNodeRef ([ref]$null)
    return $cfg
}

# ========== 主流程 ==========

$scriptFullPath = (Resolve-Path -LiteralPath $ScriptPath).ProviderPath

if ([string]::IsNullOrWhiteSpace($OutPath)) {
    $dir = [System.IO.Path]::GetDirectoryName($scriptFullPath)
    $base = [System.IO.Path]::GetFileNameWithoutExtension($scriptFullPath)
    $OutPath = Join-Path $dir ($base + '.rebuilt.ps1')
}

$OutPath = [System.IO.Path]::GetFullPath($OutPath)

if ($FullOutput) {
    if ([string]::IsNullOrWhiteSpace($WorkDir)) {
        $WorkDir = $OutPath + '.work'
    }
    $WorkDir = [System.IO.Path]::GetFullPath($WorkDir)

    if (-not (Test-Path -LiteralPath $WorkDir)) {
        $null = New-Item -ItemType Directory -Path $WorkDir -Force
    }
} else {
    # Fast 模式：不创建 workdir，不落盘过程文件
    $WorkDir = $null
}

$genPath = Join-Path $PSScriptRoot 'Generate-CFG.ps1'
$execPath = Join-Path $PSScriptRoot 'Execute-CFG.ps1'

if (-not (Test-Path -LiteralPath $genPath)) { throw "缺少文件: $genPath" }
if (-not (Test-Path -LiteralPath $execPath)) { throw "缺少文件: $execPath" }

. $genPath
. $execPath

$hostInfo = Get-PowerShellHostInfo
$hostDisplay = Format-PowerShellHostInfo -HostInfo $hostInfo

Write-Host "=== 重建解混淆脚本（递归迭代）===" -ForegroundColor Cyan
Write-Host "Host       : $hostDisplay" -ForegroundColor Gray
if ($hostInfo.ExecutablePath) { Write-Host "HostExe    : $($hostInfo.ExecutablePath)" -ForegroundColor Gray }
Write-Host "ScriptPath : $scriptFullPath" -ForegroundColor Gray
Write-Host "OutPath    : $OutPath" -ForegroundColor Gray
Write-Host "FullOutput : $FullOutput" -ForegroundColor Gray
if ($FullOutput) {
    Write-Host "WorkDir    : $WorkDir" -ForegroundColor Gray
}
Write-Host "Strategy   : $OverlapStrategy" -ForegroundColor Gray
Write-Host "VarPolicy  : $VariableConflictPolicy" -ForegroundColor Gray
Write-Host "MaxRounds  : $MaxRounds" -ForegroundColor Gray
Write-Host "TimeBudget : Global=${GlobalTimeBudgetMs}ms Dynamic=${DynamicTimeBudgetMs}ms" -ForegroundColor Gray
Write-Host "DryRun     : $DryRun" -ForegroundColor Gray
Write-Host ""

$currentPath = $scriptFullPath
$currentText = $null
$finalRound = 0
$finalRoundOutPath = $null
$terminatedBy = $null
$globalStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

for ($round = 1; $round -le $MaxRounds; $round++) {
    $remainingGlobalBudgetMs = if ($GlobalTimeBudgetMs -gt 0) { [int]($GlobalTimeBudgetMs - $globalStopwatch.ElapsedMilliseconds) } else { 0 }
    if ($GlobalTimeBudgetMs -gt 0 -and $remainingGlobalBudgetMs -le 0) {
        $terminatedBy = 'global_time_budget'
        $finalRound = [Math]::Max(0, $round - 1)
        break
    }

    $roundLabel = '{0:d2}' -f $round
    $roundInPath = $null
    $roundOutPath = $null
    $roundLogPath = $null
    $roundReportPath = $null
    $roundCfgDotPath = $null
    $roundCfgPngPath = $null

        if ($FullOutput) {
            $roundInPath = Join-Path $WorkDir ("round{0}.in.ps1" -f $roundLabel)
            $roundOutPath = Join-Path $WorkDir ("round{0}.out.ps1" -f $roundLabel)
            $roundLogPath = Join-Path $WorkDir ("round{0}.execution.log" -f $roundLabel)
            $roundReportPath = Join-Path $WorkDir ("round{0}.report.json" -f $roundLabel)
            $roundCfgDotPath = Join-Path $WorkDir ("round{0}.cfg.dot" -f $roundLabel)
        $roundCfgPngPath = [System.IO.Path]::ChangeExtension($roundCfgDotPath, '.png')

            Copy-Item -LiteralPath $currentPath -Destination $roundInPath -Force
            Write-Host ("[Round {0}/{1}] 分析+执行..." -f $round, $MaxRounds) -ForegroundColor Yellow

            $rawRoundText = Get-RawScriptTextFromFile -Path $roundInPath
            $roundParseInfo = Get-ScriptParseInfo -ScriptText $rawRoundText
            if (-not $roundParseInfo.IsValid) {
                $fallbackText = Get-BestEffortParseFallbackScriptText -ScriptText $rawRoundText -ParseError $roundParseInfo.FirstError
                Set-Content -LiteralPath $roundOutPath -Value $fallbackText -Encoding UTF8

                if ($FullOutput) {
                    $report = [ordered]@{
                        Round              = $round
                        RoundLabel         = $roundLabel
                        InputPath          = $roundInPath
                        OutputPath         = $roundOutPath
                        ExecutionLog       = $roundLogPath
                        CfgDotPath         = $roundCfgDotPath
                        CfgPngPath         = $roundCfgPngPath
                        TerminatedBy       = 'parse_failure'
                        ParseError         = $roundParseInfo.FirstError
                        Timestamp          = (Get-Date).ToString('o')
                    }
                    Write-JsonFile -Path $roundReportPath -Object $report
                }

                $currentText = $fallbackText
                $finalRound = $round
                $finalRoundOutPath = $roundOutPath
                $terminatedBy = 'parse_failure'
                break
            }

            $roundStop = Test-DynamicPayloadShouldStopRecursing -ScriptText $rawRoundText
            if ($roundStop.ShouldStop) {
                Set-Content -LiteralPath $roundOutPath -Value $rawRoundText -Encoding UTF8

                if ($FullOutput) {
                    $report = [ordered]@{
                        Round              = $round
                        RoundLabel         = $roundLabel
                        InputPath          = $roundInPath
                        OutputPath         = $roundOutPath
                        ExecutionLog       = $roundLogPath
                        CfgDotPath         = $roundCfgDotPath
                        CfgPngPath         = $roundCfgPngPath
                        TerminatedBy       = 'pre_traversal_stop'
                        StopReason         = $roundStop.StopReason
                        StopMessage        = $roundStop.Message
                        StopFeatures       = @($roundStop.Features)
                        Timestamp          = (Get-Date).ToString('o')
                    }
                    Write-JsonFile -Path $roundReportPath -Object $report
                }

                $currentText = $rawRoundText
                $finalRound = $round
                $finalRoundOutPath = $roundOutPath
                $terminatedBy = 'pre_traversal_stop'
                break
            }

            $cfg = Get-ScriptControlFlow -ScriptPath $roundInPath
            if (-not $cfg) {
                $fallbackText = Get-BestEffortParseFallbackScriptText -ScriptText $rawRoundText -ParseError 'CFG generation failed'
                Set-Content -LiteralPath $roundOutPath -Value $fallbackText -Encoding UTF8

                if ($FullOutput) {
                    $report = [ordered]@{
                        Round              = $round
                        RoundLabel         = $roundLabel
                        InputPath          = $roundInPath
                        OutputPath         = $roundOutPath
                        ExecutionLog       = $roundLogPath
                        CfgDotPath         = $roundCfgDotPath
                        CfgPngPath         = $roundCfgPngPath
                        TerminatedBy       = 'cfg_generation_failed'
                        ParseError         = $roundParseInfo.FirstError
                        Timestamp          = (Get-Date).ToString('o')
                    }
                    Write-JsonFile -Path $roundReportPath -Object $report
                }

                $currentText = $fallbackText
                $finalRound = $round
                $finalRoundOutPath = $roundOutPath
                $terminatedBy = 'cfg_generation_failed'
                break
            }

            $ctx = Invoke-CFGTraversal -CFG $cfg -LogPath $roundLogPath -MaxIterations $MaxIterations -MaxTotalNodes $MaxTotalNodes -GlobalTimeBudgetMs $remainingGlobalBudgetMs -DynamicTimeBudgetMs $DynamicTimeBudgetMs

            $scriptText = Get-FullScriptTextFromFile -Path $roundInPath
        $currentText = $scriptText
    } else {
        # Fast 模式：全程只在内存中迭代
        if ($null -eq $currentText) {
            # 第一次读取：用 ParseFile 获取同一份“解析视角”的全文，最大限度避免 offset 偏差
            $currentText = Get-FullScriptTextFromFile -Path $currentPath
        }

        Write-Host ("[Round {0}/{1}] 分析+执行 (fast)..." -f $round, $MaxRounds) -ForegroundColor Yellow

        $roundParseInfo = Get-ScriptParseInfo -ScriptText $currentText
        if (-not $roundParseInfo.IsValid) {
            $currentText = Get-BestEffortParseFallbackScriptText -ScriptText $currentText -ParseError $roundParseInfo.FirstError
            $finalRound = $round
            $terminatedBy = 'parse_failure'
            break
        }

        $roundStop = Test-DynamicPayloadShouldStopRecursing -ScriptText $currentText
        if ($roundStop.ShouldStop) {
            $finalRound = $round
            $terminatedBy = 'pre_traversal_stop'
            break
        }

        $cfg = New-CfgFromText -ScriptText $currentText
        if (-not $cfg) {
            $currentText = Get-BestEffortParseFallbackScriptText -ScriptText $currentText -ParseError 'CFG generation failed'
            $finalRound = $round
            $terminatedBy = 'cfg_generation_failed'
            break
        }

        # fast mode：禁用 execution.log（避免文件 IO）
        $ctx = Invoke-CFGTraversal -CFG $cfg -LogPath $null -MaxIterations $MaxIterations -MaxTotalNodes $MaxTotalNodes -GlobalTimeBudgetMs $remainingGlobalBudgetMs -DynamicTimeBudgetMs $DynamicTimeBudgetMs

        $scriptText = $currentText
    }

    $base = Get-ReplacementsFromResolvableResults -Context $ctx -ScriptText $scriptText -VariableConflictPolicy $VariableConflictPolicy
    $dynamic = Get-DynamicInvokeReplacementCandidates -Context $ctx -ScriptText $scriptText
    $literalized = Get-LiteralizedCommandReplacementCandidates -Context $ctx -ScriptText $scriptText
    $static = Get-StaticReplacementCandidates -Context $ctx -ScriptText $scriptText
    $merged = Merge-ReplacementCandidatesByRange -Candidates (@($dynamic.Candidates) + @($literalized.Candidates) + @($base.Candidates) + @($static.Candidates))

    $preferred = Filter-CandidatesPreferDynamicInvoke -Candidates @($merged.Candidates)

    $candidates = @($preferred.Candidates)
    $skipped = @($dynamic.Skipped) + @($literalized.Skipped) + @($base.Skipped) + @($static.Skipped) + @($merged.Skipped) + @($preferred.Skipped)

    $lowConfidence = @($candidates | Where-Object { $_.SourceKind -eq 'Static' -and $_.UsedEmptyFallback })
    foreach ($cand in $lowConfidence) {
        $skipped += New-SkipRecord -Reason 'static_low_confidence' -Message '低置信静态候选默认不自动应用' -Item $cand
    }

    $autoCandidates = @($candidates | Where-Object { -not ($_.SourceKind -eq 'Static' -and $_.UsedEmptyFallback) })
    $sel = Select-NonOverlappingReplacements -Candidates $autoCandidates -Strategy $OverlapStrategy
    $selected = @($sel.Selected)
    $skipped += @($sel.Skipped)

    $syntaxGuard = Ensure-SyntaxSafeReplacements -ScriptText $scriptText -Selected $selected
    $selected = @($syntaxGuard.Selected)
    $skipped += @($syntaxGuard.Skipped)

    $newText = Apply-ReplacementsToText -Text $scriptText -Replacements $selected
    $postProcessedText = Invoke-PostProcessDeobfuscatedScriptText -ScriptText $newText
    $postProcessChanged = ($postProcessedText -ne $newText)
    if ($postProcessChanged) {
        $newText = $postProcessedText
    }
    if ($syntaxGuard.BaselineIsValid) {
        $roundSyntax = Test-PowerShellSyntax -ScriptText $newText
        if (-not $roundSyntax.IsValid) {
            throw "语法保护失败：替换后脚本不可解析。Error=$($roundSyntax.FirstError)"
        }
    }

    $appliedCount = $selected.Count + $(if ($postProcessChanged) { 1 } else { 0 })

    # 无替换：本轮不落盘任何 round 产物，直接收敛退出
    if ($selected.Count -eq 0 -and -not $postProcessChanged) {
        Write-Host ("  candidates={0} selected={1} applied={2} skipped={3}" -f $candidates.Count, $selected.Count, $appliedCount, $skipped.Count) -ForegroundColor Gray

        if ($FullOutput) {
            # 清理本轮可能已创建的临时文件（in/log）；其余文件本轮不会生成
            $cleanupPaths = @(
                $roundInPath,
                $roundOutPath,
                $roundLogPath,
                $roundReportPath,
                $roundCfgDotPath,
                $roundCfgPngPath
            ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

            foreach ($p in $cleanupPaths) {
                if (Test-Path -LiteralPath $p) {
                    Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
                }
            }

            Write-Host "  no replacements in this round, artifacts skipped." -ForegroundColor DarkGray

            # 如果前面没有任何 round out，则最终输出回退到当前输入脚本
            if (-not $finalRoundOutPath) {
                $finalRoundOutPath = $currentPath
            }
        } else {
            $currentText = $scriptText
        }

        $finalRound = $round
        $terminatedBy = 'no_replacements'
        break
    }

    if ($FullOutput) {
        # 执行后导出 CFG（包含动态插入节点），并仅高亮“本轮实际应用替换”的节点
        $appliedNodeIds = @()
        foreach ($a in $selected) {
            if ($null -eq $a -or $null -eq $a.NodeId) { continue }
            if ("$($a.NodeId)" -match '^\d+$') {
                $appliedNodeIds += [int]$a.NodeId
            }
        }
        $appliedNodeIds = @($appliedNodeIds | Sort-Object -Unique)

        try {
            Export-CfgToDot -finalCFG $cfg -outputPath $roundCfgDotPath -AppliedNodeIds $appliedNodeIds | Out-Null
        } catch {
            Write-Warning "导出 CFG 失败: $_"
        }

        # 生成 report（尽量轻量，保留 offset 和预览）
        $skipReasonCounts = @{}
        foreach ($s in $skipped) {
            if (-not $skipReasonCounts.ContainsKey($s.Reason)) { $skipReasonCounts[$s.Reason] = 0 }
            $skipReasonCounts[$s.Reason]++
        }

        $appliedItems = @()
        foreach ($a in $selected) {
            $appliedItems += [PSCustomObject]@{
                Start             = $a.StartOffset
                End               = $a.EndOffset
                NodeId            = $a.NodeId
                Type              = $a.Type
                Depth             = $a.Depth
                OriginalLen       = if ($null -eq $a.Original) { 0 } else { $a.Original.Length }
                Original          = ConvertTo-PreviewText -Text $a.Original -MaxLen 200
                Replacement       = $a.Replacement
                SourceKind        = if ($a.PSObject.Properties['SourceKind']) { $a.SourceKind } else { 'Resolvable' }
                Confidence        = if ($a.PSObject.Properties['Confidence']) { $a.Confidence } else { 'High' }
                UsedEmptyFallback = if ($a.PSObject.Properties['UsedEmptyFallback']) { [bool]$a.UsedEmptyFallback } else { $false }
                Executed          = if ($a.PSObject.Properties['Executed']) { [bool]$a.Executed } else { $true }
                ResultType        = if ($a.PSObject.Properties['ResultType']) { $a.ResultType } else { $null }
                DynamicStopReason = if ($a.PSObject.Properties['DynamicStopReason']) { $a.DynamicStopReason } else { $null }
                DynamicStopMessage = if ($a.PSObject.Properties['DynamicStopMessage']) { $a.DynamicStopMessage } else { $null }
            }
        }

        $staticHigh = @($candidates | Where-Object { $_.SourceKind -eq 'Static' -and $_.Confidence -eq 'High' }).Count
        $staticLow = @($candidates | Where-Object { $_.SourceKind -eq 'Static' -and $_.Confidence -eq 'Low' }).Count
        $dynamicCount = @($candidates | Where-Object { $_.SourceKind -eq 'DynamicInvoke' }).Count
        $literalizedCount = @($candidates | Where-Object { $_.SourceKind -eq 'LiteralizedCommand' }).Count
        $otherExecutedCount = @($candidates | Where-Object { $_.SourceKind -notin @('Static', 'DynamicInvoke', 'LiteralizedCommand') }).Count

        $report = [ordered]@{
            Round           = $round
            RoundLabel      = $roundLabel
            InputPath       = $roundInPath
            OutputPath      = $roundOutPath
            ExecutionLog    = $roundLogPath
            CfgDotPath      = $roundCfgDotPath
            CfgPngPath      = $roundCfgPngPath
            HostInfo        = $ctx.HostInfo
            OverlapStrategy = $OverlapStrategy
            VariableConflictPolicy = $VariableConflictPolicy
            MaxIterations   = $MaxIterations
            MaxTotalNodes   = $MaxTotalNodes
            GlobalTimeBudgetMs = $GlobalTimeBudgetMs
            DynamicTimeBudgetMs = $DynamicTimeBudgetMs
            ExecutionStopReason = if ($ctx.ContainsKey('StopReason')) { $ctx.StopReason } else { $null }
            CandidateCount  = $candidates.Count
            DynamicCount    = $dynamicCount
            LiteralizedCommandCount = $literalizedCount
            OtherExecutedCount = $otherExecutedCount
            StaticHighCount = $staticHigh
            StaticLowCount  = $staticLow
            SelectedCount   = $selected.Count
            AppliedCount    = $appliedCount
            PostProcessChanged = $postProcessChanged
            SkippedCount    = $skipped.Count
            SkippedByReason = $skipReasonCounts
            AppliedNodeIds  = $appliedNodeIds
            Applied         = $appliedItems
            Skipped         = $skipped
            Timestamp       = (Get-Date).ToString('o')
        }

        Write-JsonFile -Path $roundReportPath -Object $report

        Set-Content -LiteralPath $roundOutPath -Value $newText -Encoding UTF8

        Write-Host ("  candidates={0} selected={1} applied={2} skipped={3}" -f $candidates.Count, $selected.Count, $appliedCount, $skipped.Count) -ForegroundColor Gray
        Write-Host ("  in    : {0}" -f $roundInPath) -ForegroundColor Gray
        Write-Host ("  out   : {0}" -f $roundOutPath) -ForegroundColor Gray
        Write-Host ("  log   : {0}" -f $roundLogPath) -ForegroundColor Gray
        Write-Host ("  report: {0}" -f $roundReportPath) -ForegroundColor Gray
        Write-Host ("  cfg   : {0}" -f $roundCfgDotPath) -ForegroundColor Gray
        Write-Host ""

        $finalRoundOutPath = $roundOutPath
        $currentPath = $roundOutPath
        $currentText = $newText
    } else {
        Write-Host ("  candidates={0} selected={1} applied={2} skipped={3}" -f $candidates.Count, $selected.Count, $appliedCount, $skipped.Count) -ForegroundColor Gray
        $currentText = $newText
    }

    $finalRound = $round

    if (($GlobalTimeBudgetMs -gt 0 -and $globalStopwatch.ElapsedMilliseconds -ge $GlobalTimeBudgetMs) -or ($ctx -and $ctx.ContainsKey('StopReason') -and [string]$ctx.StopReason -eq 'GlobalTimeBudgetExceeded')) {
        $terminatedBy = 'global_time_budget'
        break
    }

    # 下一轮输入
    if ($FullOutput) {
        # 下一轮输入 = 本轮输出文件
        $currentPath = $finalRoundOutPath
    } else {
        # fast：继续使用内存脚本文本
        $currentPath = $scriptFullPath
    }
}

if ($FullOutput -and -not $finalRoundOutPath) {
    if ($terminatedBy -eq 'global_time_budget') {
        $finalRoundOutPath = $currentPath
    } else {
    throw "未产生任何轮次输出，无法生成最终脚本。"
    }
}

if ($null -eq $terminatedBy) {
    $terminatedBy = 'max_rounds'
}

if (-not $DryRun) {
    $outDir = [System.IO.Path]::GetDirectoryName($OutPath)
    if (-not [string]::IsNullOrWhiteSpace($outDir) -and -not (Test-Path -LiteralPath $outDir)) {
        $null = New-Item -ItemType Directory -Path $outDir -Force
    }

    if ($FullOutput) {
        Copy-Item -LiteralPath $finalRoundOutPath -Destination $OutPath -Force
    } else {
        Set-Content -LiteralPath $OutPath -Value $currentText -Encoding UTF8
    }
}

Write-Host "=== 完成 ===" -ForegroundColor Green
Write-Host ("TerminatedBy : {0}" -f $terminatedBy) -ForegroundColor Gray
Write-Host ("FinalRound   : {0}" -f $finalRound) -ForegroundColor Gray
if ($FullOutput) {
    Write-Host ("FinalWorkOut : {0}" -f $finalRoundOutPath) -ForegroundColor Gray
}
Write-Host ("OutPath      : {0}" -f $OutPath) -ForegroundColor Gray
if ($FullOutput) {
    Write-Host ("WorkDir      : {0}" -f $WorkDir) -ForegroundColor Gray
}
