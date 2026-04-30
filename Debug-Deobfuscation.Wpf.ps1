<#
.SYNOPSIS
  Interactive deobfuscation debugger for a single analysis round.

.DESCRIPTION
  - Nodes execute only when the user advances the session step by step.
  - The variable stack can be inspected and edited with PowerShell expressions.
  - Condition nodes can preview the next edge so branch changes are visible.
  - Replacement candidates and rebuilt-script previews update live, and the
    current state can be exported as debug.out.ps1.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ScriptPath,

    [string]$WorkDir,

    [ValidateSet('Outer', 'Inner')]
    [string]$OverlapStrategy = 'Inner',

    [int]$MaxIterations = 1000,
    [int]$MaxTotalNodes = 50000,
    [int]$DynamicTimeBudgetMs = 60000,

    [switch]$NoUI
)

$ErrorActionPreference = 'Stop'
$script:StaticEvalOperatorCache = @{}

function Test-IsWindowsHost {
    return ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT)
}

function Get-CurrentPowerShellExecutablePath {
    $exe = $null

    try {
        $p = Get-Process -Id $PID -ErrorAction Stop
        if ($p.Path) { $exe = [string]$p.Path }
    } catch {
        $exe = $null
    }

    if (-not [string]::IsNullOrWhiteSpace($exe) -and (Test-Path -LiteralPath $exe)) {
        return $exe
    }

    foreach ($candidate in @((Join-Path $PSHOME 'powershell.exe'), (Join-Path $PSHOME 'pwsh.exe')) | Select-Object -Unique) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }

    $commandName = if ($PSVersionTable.PSEdition -eq 'Desktop') { 'powershell.exe' } else { 'pwsh' }
    $cmd = Get-Command $commandName -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd -and $cmd.Source) { return [string]$cmd.Source }

    return $null
}

if (-not (Test-IsWindowsHost)) {
    throw "该脚本仅支持 Windows（需要 WPF）。"
}

function Restart-SelfAsStaIfNeeded {
    param([hashtable]$BoundParams)

    if ($NoUI) { return }
    $apt = [System.Threading.Thread]::CurrentThread.ApartmentState
    if ($apt -eq [System.Threading.ApartmentState]::STA) { return }

    $argList = @('-NoProfile', '-Sta', '-File', $PSCommandPath)
    foreach ($kv in $BoundParams.GetEnumerator() | Sort-Object Key) {
        $k = $kv.Key
        $v = $kv.Value
        if ($null -eq $v) { continue }
        if ($v -is [switch] -and -not $v.IsPresent) { continue }
        $argList += ('-' + $k)
        if (-not ($v -is [switch])) {
            $argList += [string]$v
        }
    }

    $exe = Get-CurrentPowerShellExecutablePath
    if (-not $exe) {
        throw "当前线程不是 STA，且无法定位当前 PowerShell 宿主。请用 -Sta 运行。"
    }
    & $exe @argList
    exit $LASTEXITCODE
}

Restart-SelfAsStaIfNeeded -BoundParams $PSBoundParameters

function Import-UiAssemblies {
    Add-Type -AssemblyName PresentationFramework | Out-Null
    Add-Type -AssemblyName PresentationCore | Out-Null
    Add-Type -AssemblyName WindowsBase | Out-Null
}

Import-UiAssemblies

$uiLocPath = Join-Path $PSScriptRoot 'Ui-Localization.ps1'
if (-not (Test-Path -LiteralPath $uiLocPath)) { throw "缺少文件: $uiLocPath" }
. $uiLocPath

$script:UiLanguage = 'zh-CN'
if (-not $NoUI) {
    $selectedLanguage = Show-LanguageSelectionDialog
    if ([string]::IsNullOrWhiteSpace([string]$selectedLanguage)) { return }
    $script:UiLanguage = [string]$selectedLanguage
}
$script:UiText = Get-UiTextPack -Scope 'Debug' -Language $script:UiLanguage

function L {
    param(
        [Parameter(Mandatory)][string]$Key,
        [object[]]$FormatArgs = @()
    )

    return Get-UiText -Pack $script:UiText -Key $Key -Args $FormatArgs
}

$genPath = Join-Path $PSScriptRoot 'Generate-CFG.ps1'
$execPath = Join-Path $PSScriptRoot 'Execute-CFG.ps1'
if (-not (Test-Path -LiteralPath $genPath)) { throw "缺少文件: $genPath" }
if (-not (Test-Path -LiteralPath $execPath)) { throw "缺少文件: $execPath" }

. $genPath
. $execPath

function Get-FullScriptTextFromFile {
    param([Parameter(Mandatory)][string]$Path)
    $ast = Get-Ast $Path
    if (-not $ast -or -not $ast.Extent -or -not $ast.Extent.StartScriptPosition) {
        throw "无法解析脚本获取全文: $Path"
    }
    return $ast.Extent.StartScriptPosition.GetFullScript()
}

function ConvertTo-PreviewText {
    param(
        [string]$Text,
        [int]$MaxLen = 220
    )
    if ($null -eq $Text) { return $null }
    if ($Text.Length -le $MaxLen) { return $Text }
    return $Text.Substring(0, $MaxLen) + '...'
}

function Test-SimpleVariableReplacementLiteral {
    param([string]$Replacement)

    if ([string]::IsNullOrWhiteSpace($Replacement)) { return $false }
    if ($Replacement -match '^\s*@\(') { return $false }
    if ($Replacement -match '^\s*@\{') { return $false }
    if ($Replacement -match '^\s*\{')  { return $false }
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

        $key = "$start`:$end"
        if (-not $map.ContainsKey($key)) {
            $map[$key] = $kind
            continue
        }
        if ($map[$key] -eq 'Read' -and $kind -ne 'Read') {
            $map[$key] = $kind
        }
    }

    return $map
}

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

function Unwrap-SafePSBaseObject {
    param($Value)

    if ($null -eq $Value) { return $null }

    try {
        $psObject = $Value.PSObject
    } catch {
        return $Value
    }

    if ($null -eq $psObject) { return $Value }

    try {
        $baseObject = $psObject.BaseObject
    } catch {
        return $Value
    }

    if ($null -ne $baseObject -and $baseObject -ne $Value) {
        return $baseObject
    }

    return $Value
}

function Test-StaticReplacementScalarValue {
    param($Value)

    if ($null -eq $Value) { return $true }
    $Value = Unwrap-SafePSBaseObject -Value $Value
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
    $Value = Unwrap-SafePSBaseObject -Value $Value
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
    $Value = Unwrap-SafePSBaseObject -Value $Value
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
    $Value = Unwrap-SafePSBaseObject -Value $Value
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
    param([System.Management.Automation.Language.PipelineAst]$PipelineAst)

    if ($null -eq $PipelineAst) { return $null }
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
        if ($statements[0] -isnot [System.Management.Automation.Language.PipelineAst]) { return $false }
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
            if ($statement -isnot [System.Management.Automation.Language.PipelineAst]) {
                return [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = $usedFallback; Reason = 'unsupported_statement'; Message = '子表达式包含非 Pipeline 语句' }
            }
            $expr = Get-StaticExpressionFromPipelineAst -PipelineAst $statement
            if ($null -eq $expr) {
                return [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = $usedFallback; Reason = 'unsupported_pipeline'; Message = '子表达式包含复杂 pipeline' }
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
            if ($statement -isnot [System.Management.Automation.Language.PipelineAst]) {
                return [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = $usedFallback; Reason = 'unsupported_statement'; Message = '数组表达式包含非 Pipeline 语句' }
            }
            $expr = Get-StaticExpressionFromPipelineAst -PipelineAst $statement
            if ($null -eq $expr) {
                return [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = $usedFallback; Reason = 'unsupported_pipeline'; Message = '数组表达式包含复杂 pipeline' }
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
    if ($sourceKind -eq 'VariableRead') { return 350 }
    return 300
}

function Get-SyntaxGuardDropPriority {
    param($Candidate)

    if (-not $Candidate) { return 0 }

    $type = if ($Candidate.PSObject.Properties['Type']) { [string]$Candidate.Type } else { '' }
    switch ($type) {
        'VarRead' { return 10 }
        'Inline' { return 20 }
    }

    $sourceKind = if ($Candidate.PSObject.Properties['SourceKind']) { [string]$Candidate.SourceKind } else { '' }
    switch ($sourceKind) {
        'Static' { return 30 }
        'Resolvable' { return 40 }
        'VariableRead' { return 50 }
        'DynamicInvoke' { return 100 }
        default { return 60 }
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

        $start = $null
        $end = $null
        if ($rec -is [hashtable]) {
            if ($rec.ContainsKey('ReplacementStartOffset') -and $null -ne $rec['ReplacementStartOffset']) { $start = [int]$rec['ReplacementStartOffset'] }
            if ($rec.ContainsKey('ReplacementEndOffset') -and $null -ne $rec['ReplacementEndOffset']) { $end = [int]$rec['ReplacementEndOffset'] }
        } else {
            if ($rec.PSObject.Properties['ReplacementStartOffset'] -and $null -ne $rec.ReplacementStartOffset) { $start = [int]$rec.ReplacementStartOffset }
            if ($rec.PSObject.Properties['ReplacementEndOffset'] -and $null -ne $rec.ReplacementEndOffset) { $end = [int]$rec.ReplacementEndOffset }
        }
        if ($null -eq $start) { $start = $node.TextStartOffset }
        if ($null -eq $end) { $end = $node.TextEndOffset }
        if ($null -eq $start -or $null -eq $end) {
            $skipped += New-SkipRecord -Reason 'dynamic_no_offset' -Message 'DynamicInvoke 无原始 offset，跳过' -Item $baseItem
            continue
        }
        if ($start -lt 0 -or $end -le $start -or $end -gt $ScriptText.Length) {
            $skipped += New-SkipRecord -Reason 'dynamic_out_of_range' -Message 'DynamicInvoke offset 越界' -Item $baseItem
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
            VariableName = $null
            IsSimpleVariable = $false
            IsValueChanged = $false
            ObservedValueCount = 1
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

function Get-WholeScriptDynamicLoaderReplacementCandidates {
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][string]$ScriptText
    )

    $candidates = @()
    $skipped = @()

    if ([string]::IsNullOrWhiteSpace($ScriptText)) {
        return [PSCustomObject]@{ Candidates = @(); Skipped = @() }
    }
    if (-not $Context.ExecContext) {
        return [PSCustomObject]@{ Candidates = @(); Skipped = @() }
    }
    if ($ScriptText -notmatch '(?i)\b(?:Invoke-Expression|iex)\b') {
        return [PSCustomObject]@{ Candidates = @(); Skipped = @() }
    }
    if ($ScriptText -notmatch '(?i)(DeflateStream|ReadToEnd|ToInt16|FromBase64String|-bxor|\[char\])') {
        return [PSCustomObject]@{ Candidates = @(); Skipped = @() }
    }

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($ScriptText, [ref]$tokens, [ref]$errors)
    if ($errors -and @($errors).Count -gt 0) {
        return [PSCustomObject]@{ Candidates = @(); Skipped = @() }
    }

    $statement = Get-FirstStatementFromScriptAst -ScriptAst $ast
    if ($null -eq $statement -or -not $statement.Extent) {
        return [PSCustomObject]@{ Candidates = @(); Skipped = @() }
    }

    $payloadText = $null
    $dynamicType = $null

    if ($statement -is [System.Management.Automation.Language.PipelineAst]) {
        $elements = @($statement.PipelineElements)
        if ($elements.Count -ge 1) {
            $last = $elements[$elements.Count - 1]
            if ($last -is [System.Management.Automation.Language.CommandAst]) {
                if ($elements.Count -gt 1) {
                    $cmdName = Convert-DynamicCommandCandidateToName -Value $last.GetCommandName()
                    if ($cmdName -in @('Invoke-Expression', 'iex')) {
                        $payloadText = (($elements[0..($elements.Count - 2)] | ForEach-Object { $_.Extent.Text }) -join ' | ')
                        $dynamicType = 'IEX'
                    }
                }
                if ([string]::IsNullOrWhiteSpace($payloadText)) {
                    $parseInfo = [PSCustomObject]@{ SourceText = $ScriptText }
                    $wrapped = Get-CommandAstWrappedDynamicInvocationInfo -CommandAst $last -Context $Context
                    $cmdName = Convert-DynamicCommandCandidateToName -Value $last.GetCommandName()
                    if ($wrapped.Success -and (Get-CFGObjectPropertyValue -Object $wrapped -Name 'DynamicType' -Default $null) -eq 'IEX') {
                        $payloadText = Get-CommandArgumentText -CommandAst $last -ParseInfo $parseInfo -FirstArgumentIndex $wrapped.ArgumentStartIndex
                        $dynamicType = 'IEX'
                    } elseif ($cmdName -in @('Invoke-Expression', 'iex')) {
                        $payloadText = Get-CommandArgumentText -CommandAst $last -ParseInfo $parseInfo
                        $dynamicType = 'IEX'
                    }
                }
            }
        }
    } elseif ($statement -is [System.Management.Automation.Language.CommandAst]) {
        $parseInfo = [PSCustomObject]@{ SourceText = $ScriptText }
        $wrapped = Get-CommandAstWrappedDynamicInvocationInfo -CommandAst $statement -Context $Context
        $cmdName = Convert-DynamicCommandCandidateToName -Value $statement.GetCommandName()
        if ($wrapped.Success -and (Get-CFGObjectPropertyValue -Object $wrapped -Name 'DynamicType' -Default $null) -eq 'IEX') {
            $payloadText = Get-CommandArgumentText -CommandAst $statement -ParseInfo $parseInfo -FirstArgumentIndex $wrapped.ArgumentStartIndex
            $dynamicType = 'IEX'
        } elseif ($cmdName -in @('Invoke-Expression', 'iex')) {
            $payloadText = Get-CommandArgumentText -CommandAst $statement -ParseInfo $parseInfo
            $dynamicType = 'IEX'
        }
    }

    if ([string]::IsNullOrWhiteSpace($payloadText)) {
        return [PSCustomObject]@{ Candidates = @(); Skipped = @() }
    }

    $evalCode = Convert-CodeForCurrentScope -Code $payloadText -Context $Context
    $evalResult = $null
    $tempExecContext = $null
    $contextExecUsable = $false
    if ($Context.ExecContext -and $Context.ExecContext.Runspace -and
        $Context.ExecContext.Runspace.RunspaceStateInfo -and
        [string]$Context.ExecContext.Runspace.RunspaceStateInfo.State -eq 'Opened') {
        $contextExecUsable = $true
    }
    if ($contextExecUsable) {
        $evalResult = Invoke-InContext -ExecContext $Context.ExecContext -Code $evalCode
    } else {
        $tempExecContext = New-ExecutionContext
        try {
            $evalResult = Invoke-InContext -ExecContext $tempExecContext -Code $evalCode
        } finally {
            if ($tempExecContext) {
                Close-ExecutionContext -ExecContext $tempExecContext
            }
        }
    }
    if (-not $evalResult.Success -or $null -eq $evalResult.Result) {
        $skipped += [PSCustomObject]@{
            Reason = 'dynamic_loader_eval_failed'
            Message = if ($evalResult -and $evalResult.Error) { [string]$evalResult.Error } else { 'dynamic loader evaluation failed' }
            StartOffset = [int]$statement.Extent.StartOffset
            EndOffset = [int]$statement.Extent.EndOffset
            Type = 'DynamicInvoke'
            Depth = $null
            NodeId = $null
        }
        return [PSCustomObject]@{ Candidates = @(); Skipped = @($skipped) }
    }

    $normalizedValue = Normalize-ExecutionResultValue -Value $evalResult.Result -TreatArraysAsSequence
    $materialized = Convert-DynamicInvocationValueToScriptText -Value $normalizedValue
    if (-not $materialized.Success -or [string]::IsNullOrWhiteSpace([string]$materialized.Text)) {
        return [PSCustomObject]@{ Candidates = @(); Skipped = @($skipped) }
    }

    $replacement = [string]$materialized.Text
    $original = $ScriptText.Substring([int]$statement.Extent.StartOffset, [int]$statement.Extent.EndOffset - [int]$statement.Extent.StartOffset)
    if ($original -eq $replacement) {
        return [PSCustomObject]@{ Candidates = @(); Skipped = @($skipped) }
    }

    $candidates += [PSCustomObject]@{
        StartOffset = [int]$statement.Extent.StartOffset
        EndOffset   = [int]$statement.Extent.EndOffset
        Replacement = $replacement
        Original    = $original
        Type        = 'DynamicInvoke'
        Depth       = $null
        NodeId      = $null
        SourceKind  = 'DynamicInvoke'
        Confidence  = 'High'
        UsedEmptyFallback = $false
        ResultType  = 'String'
        Executed    = $true
        VariableName = $null
        IsSimpleVariable = $false
        IsValueChanged = $false
        ObservedValueCount = 1
        DynamicStopReason = "WholeScriptLoader:$dynamicType"
        DynamicStopMessage = "Recovered whole-script dynamic loader via $($materialized.Kind)"
    }

    return [PSCustomObject]@{
        Candidates = @($candidates)
        Skipped    = @($skipped)
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
        if (-not $node -or -not $node.Resolvables) { continue }
        $nodeId = [int]$node.Id
        if ($node.PSObject.Properties['RuntimeGenerated'] -and [bool]$node.RuntimeGenerated) { continue }
        $isVisited = $false
        if ($Context.VisitedNodes) {
            $isVisited = ($Context.VisitedNodes.ContainsKey($nodeId) -or $Context.VisitedNodes.ContainsKey([string]$nodeId))
        }
        if ($isVisited) { continue }

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

            $replacement = [string](Format-ResolvableValue $resolved.Value)
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
        [Parameter(Mandatory)][string]$ScriptText
    )

    $regionMap = @{}
    $skipped = @()

    foreach ($rec in @($Context.ResolvableResults.Values)) {
        if (-not $rec -or -not $rec.Resolvable) { continue }
        $r = $rec.Resolvable
        $start = $r.StartOffset
        $end = $r.EndOffset
        $baseItem = [PSCustomObject]@{
            StartOffset = $start
            EndOffset   = $end
            Type        = $r.Type
            Depth       = $r.Depth
            NodeId      = $rec.NodeId
        }

        $node = if ($Context.CFG -and $rec.NodeId) { Get-NodeById -CFG $Context.CFG -Id $rec.NodeId } else { $null }
        if ($node -and $node.PSObject.Properties['RuntimeGenerated'] -and [bool]$node.RuntimeGenerated) {
            $skipped += New-SkipRecord -Reason 'runtime_generated' -Message '运行时子图的 Resolvable 不直接回写原脚本' -Item $baseItem
            continue
        }

        if ($null -eq $start -or $null -eq $end) {
            $skipped += New-SkipRecord -Reason 'no_offset' -Message '无 offset' -Item $baseItem
            continue
        }
        if ($start -lt 0 -or $end -le $start -or $end -gt $ScriptText.Length) {
            $skipped += New-SkipRecord -Reason 'out_of_range' -Message 'offset 越界' -Item $baseItem
            continue
        }

        $uniqueValues = @($rec.Values | Select-Object -Unique)
        if ($uniqueValues.Count -ne 1) {
            $skipped += New-SkipRecord -Reason 'inconsistent' -Message "同片段多值: $($uniqueValues.Count)" -Item $baseItem
            continue
        }

        $replacement = [string]$uniqueValues[0]
        if ($replacement -eq '__BLOCKED_PLACEHOLDER__') {
            $skipped += New-SkipRecord -Reason 'blocked' -Message '占位符跳过' -Item $baseItem
            continue
        }

        if ($replacement -eq '$null') {
            $skipped += New-SkipRecord -Reason 'null_replacement' -Message 'replacement 为 $null，默认跳过' -Item $baseItem
            continue
        }

        $original = $ScriptText.Substring($start, $end - $start)
        if ($original -eq $replacement) {
            $skipped += New-SkipRecord -Reason 'no_change' -Message '无变化' -Item $baseItem
            continue
        }

        $cand = [PSCustomObject]@{
            StartOffset = $start
            EndOffset   = $end
            Replacement = $replacement
            Original    = $original
            Type        = $r.Type
            Depth       = $r.Depth
            NodeId      = $rec.NodeId
            SourceKind     = 'Resolvable'
            VariableName   = $null
            IsSimpleVariable = $false
            IsValueChanged   = $false
            ObservedValueCount = 1
        }

        $key = "$start`:$end"
        if (-not $regionMap.ContainsKey($key)) {
            $regionMap[$key] = $cand
            continue
        }

        if ($regionMap[$key].Replacement -ne $cand.Replacement) {
            $skipped += New-SkipRecord -Reason 'conflict_same_range' -Message '同区间冲突' -Item $regionMap[$key]
            $skipped += New-SkipRecord -Reason 'conflict_same_range' -Message '同区间冲突' -Item $cand
            $null = $regionMap.Remove($key)
        }
    }

    $varAccessKindMap = Get-VariableAccessKindMapFromScriptText -ScriptText $ScriptText
    if ($Context.VariableReadResults) {
        foreach ($rec in @($Context.VariableReadResults.Values)) {
            $v = $rec.VarInfo
            if (-not $v) { continue }

            $start = $v.StartOffset
            $end = $v.EndOffset
            $isInline = ($v.PSObject.Properties['IsInlineResult'] -and $v.IsInlineResult)
            $type = if ($isInline) { 'Inline' } else { 'VarRead' }
            $nodeId = $rec.NodeId
            $varName = if ($v.PSObject.Properties['Name'] -and -not [string]::IsNullOrWhiteSpace([string]$v.Name)) { [string]$v.Name } else { [string]$v.Text }

            $baseItem = [PSCustomObject]@{
                StartOffset = $start
                EndOffset   = $end
                Type        = $type
                Depth       = $null
                NodeId      = $nodeId
            }

            $node = if ($Context.CFG -and $nodeId) { Get-NodeById -CFG $Context.CFG -Id $nodeId } else { $null }
            if ($node -and $node.PSObject.Properties['RuntimeGenerated'] -and [bool]$node.RuntimeGenerated) {
                $skipped += New-SkipRecord -Reason 'runtime_generated' -Message '运行时子图的变量读取不直接回写原脚本' -Item $baseItem
                continue
            }

            if ($null -eq $start -or $null -eq $end) {
                $skipped += New-SkipRecord -Reason 'no_offset' -Message '变量读取无 offset' -Item $baseItem
                continue
            }
            if ($start -lt 0 -or $end -le $start -or $end -gt $ScriptText.Length) {
                $skipped += New-SkipRecord -Reason 'out_of_range' -Message '变量读取 offset 越界' -Item $baseItem
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
            $isValueChanged = ($uniqueValues.Count -gt 1)

            $replacement = $null
            if ($isValueChanged) {
                $replacement = Get-LastValidVariableReplacement -Values $allValues
                if ([string]::IsNullOrWhiteSpace([string]$replacement)) {
                    $skipped += New-SkipRecord -Reason 'var_inconsistent' -Message "变量同位置多值且无可用最终值: $($uniqueValues.Count)" -Item $baseItem
                    continue
                }
            } else {
                $replacement = [string]$uniqueValues[0]
                if ($replacement -eq '__BLOCKED_PLACEHOLDER__') {
                    $skipped += New-SkipRecord -Reason 'blocked' -Message '变量值为占位符跳过' -Item $baseItem
                    continue
                }
                if ($replacement -eq '$null') {
                    $skipped += New-SkipRecord -Reason 'null_replacement' -Message '变量 replacement 为 $null，默认跳过' -Item $baseItem
                    continue
                }
                if (-not (Test-SimpleVariableReplacementLiteral -Replacement $replacement)) {
                    $skipped += New-SkipRecord -Reason 'var_not_simple' -Message '变量值非简单字面量，跳过' -Item $baseItem
                    continue
                }
            }

            $original = $ScriptText.Substring($start, $end - $start)
            if ($original -eq $replacement) {
                $skipped += New-SkipRecord -Reason 'no_change' -Message '变量 replacement 无变化' -Item $baseItem
                continue
            }

            $cand = [PSCustomObject]@{
                StartOffset = $start
                EndOffset   = $end
                Replacement = $replacement
                Original    = $original
                Type        = $type
                Depth       = $null
                NodeId      = $nodeId
                SourceKind     = 'VariableRead'
                VariableName   = $varName
                IsSimpleVariable = (-not $isInline)
                IsValueChanged   = $isValueChanged
                ObservedValueCount = $uniqueValues.Count
            }

            if (-not $regionMap.ContainsKey($key)) {
                $regionMap[$key] = $cand
                continue
            }

            if ($regionMap[$key].Replacement -ne $cand.Replacement) {
                $skipped += New-SkipRecord -Reason 'conflict_same_range' -Message '变量同区间冲突' -Item $regionMap[$key]
                $skipped += New-SkipRecord -Reason 'conflict_same_range' -Message '变量同区间冲突' -Item $cand
                $null = $regionMap.Remove($key)
            }
        }
    }

    return [PSCustomObject]@{
        Candidates = @($regionMap.Values)
        Skipped    = @($skipped)
    }
}

function Select-NonOverlappingReplacements {
    param(
        [array]$Candidates,
        [ValidateSet('Outer', 'Inner')][string]$Strategy
    )

    if (-not $Candidates -or $Candidates.Count -eq 0) {
        return [PSCustomObject]@{ Selected = @(); Skipped = @() }
    }

    $selected = @()
    $skipped = @()

    if ($Strategy -eq 'Outer') {
        $sorted = $Candidates | Sort-Object StartOffset, @{ Expression = 'EndOffset'; Descending = $true }
        $lastEnd = -1
        foreach ($c in $sorted) {
            if ($c.StartOffset -ge $lastEnd) {
                $selected += $c
                $lastEnd = $c.EndOffset
            } else {
                $skipped += New-SkipRecord -Reason 'overlap' -Message 'Outer 丢弃重叠' -Item $c
            }
        }
    } else {
        $sorted = $Candidates | Sort-Object EndOffset, @{ Expression = 'StartOffset'; Descending = $true }
        $lastEnd = -1
        foreach ($c in $sorted) {
            if ($c.StartOffset -ge $lastEnd) {
                $selected += $c
                $lastEnd = $c.EndOffset
            } else {
                $skipped += New-SkipRecord -Reason 'overlap' -Message 'Inner 丢弃重叠' -Item $c
            }
        }
        $selected = @($selected | Sort-Object StartOffset)
    }

    return [PSCustomObject]@{
        Selected = @($selected)
        Skipped  = @($skipped)
    }
}

function Get-ReplacementKey {
    param($Candidate)
    if (-not $Candidate) { return $null }
    return "$($Candidate.StartOffset):$($Candidate.EndOffset):$($Candidate.NodeId):$($Candidate.Type)"
}

function Test-ReplacementOverlap {
    param(
        [Parameter(Mandatory)]$A,
        [Parameter(Mandatory)]$B
    )
    return (($A.StartOffset -lt $B.EndOffset) -and ($B.StartOffset -lt $A.EndOffset))
}

function Resolve-SelectedCandidates {
    param(
        [array]$Candidates,
        [hashtable]$SelectedByKey,
        [hashtable]$ManualSelection,
        [ValidateSet('Outer', 'Inner')][string]$Strategy
    )

    if (-not $Candidates -or $Candidates.Count -eq 0) {
        return [PSCustomObject]@{ Selected = @(); Skipped = @() }
    }

    $picked = @($Candidates | Where-Object {
            $k = [string]$_.Key
            $SelectedByKey.ContainsKey($k) -and [bool]$SelectedByKey[$k]
        })

    if ($picked.Count -eq 0) {
        return [PSCustomObject]@{ Selected = @(); Skipped = @() }
    }

    $scored = @()
    foreach ($c in $picked) {
        $k = [string]$c.Key
        $isManual = $false
        if ($ManualSelection -and $ManualSelection.ContainsKey($k)) {
            $isManual = [bool]$ManualSelection[$k]
        }
        $span = [int]($c.EndOffset - $c.StartOffset)
        $scored += [PSCustomObject]@{
            Candidate = $c
            IsManual  = $isManual
            Span      = $span
        }
    }

    if ($Strategy -eq 'Outer') {
        $ordered = $scored | Sort-Object @{ Expression = 'IsManual'; Descending = $true }, @{ Expression = 'Span'; Descending = $true }, @{ Expression = { $_.Candidate.StartOffset } }, @{ Expression = { $_.Candidate.EndOffset } }
    } else {
        $ordered = $scored | Sort-Object @{ Expression = 'IsManual'; Descending = $true }, @{ Expression = 'Span'; Descending = $false }, @{ Expression = { $_.Candidate.StartOffset } }, @{ Expression = { $_.Candidate.EndOffset } }
    }

    $selected = @()
    $skipped = @()
    foreach ($s in $ordered) {
        $c = $s.Candidate
        $hit = $false
        foreach ($keep in $selected) {
            if (Test-ReplacementOverlap -A $c -B $keep) {
                $hit = $true
                $msg = if ($s.IsManual) { '手动选择冲突，保留优先级更高片段' } else { '自动选择冲突，保留优先级更高片段' }
                $skipped += New-SkipRecord -Reason 'overlap_conflict' -Message $msg -Item $c
                break
            }
        }
        if (-not $hit) {
            $selected += $c
        }
    }

    $selected = @($selected | Sort-Object StartOffset, EndOffset)
    return [PSCustomObject]@{
        Selected = @($selected)
        Skipped  = @($skipped)
    }
}

function Apply-ReplacementsToText {
    param(
        [Parameter(Mandatory)][string]$Text,
        [array]$Replacements
    )

    if (-not $Replacements -or $Replacements.Count -eq 0) { return $Text }

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

    return [PSCustomObject]@{
        IsValid    = (-not $errors -or $errors.Count -eq 0)
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
        [array]$Selected
    )

    if (-not $Selected -or $Selected.Count -eq 0) {
        $baseCheck = Test-PowerShellSyntax -ScriptText $ScriptText
        return [PSCustomObject]@{
            Selected = @()
            Skipped  = @()
            FinalIsValid = $baseCheck.IsValid
            FinalError = $null
        }
    }

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
            Selected = @($effective)
            Skipped  = @()
            FinalIsValid = $true
            FinalError = $null
        }
    }

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

    if (-not $check.IsValid -and $effective.Count -gt 0) {
        $ordered = @($effective | Sort-Object @{ Expression = { Get-SyntaxGuardDropPriority -Candidate $_ } }, @{ Expression = { [int]($_.EndOffset - $_.StartOffset) } }, StartOffset)
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

    if (-not $check.IsValid -and $effective.Count -gt 0) {
        foreach ($left in @($effective)) {
            $skipped += New-SkipRecord -Reason 'syntax_guard_fallback' -Message '替换后仍语法错误，清空全部替换' -Item $left
        }
        $effective = @()
        $check = Invoke-SyntaxCheckWithReplacements -SourceText $ScriptText -Replacements $effective
    }

    return [PSCustomObject]@{
        Selected = @($effective)
        Skipped  = @($skipped)
        FinalIsValid = $check.IsValid
        FinalError = $check.FirstError
    }
}

function Build-DebugPreview {
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][string]$ScriptText,
        [Parameter(Mandatory)][ValidateSet('Outer', 'Inner')][string]$Strategy,
        [hashtable]$ManualSelection
    )

    $dynamic = Get-DynamicInvokeReplacementCandidates -Context $Context -ScriptText $ScriptText
    $wholeScriptDynamic = Get-WholeScriptDynamicLoaderReplacementCandidates -Context $Context -ScriptText $ScriptText
    $base = Get-ReplacementsFromResolvableResults -Context $Context -ScriptText $ScriptText
    $static = Get-StaticReplacementCandidates -Context $Context -ScriptText $ScriptText
    $merged = Merge-ReplacementCandidatesByRange -Candidates (@($dynamic.Candidates) + @($wholeScriptDynamic.Candidates) + @($base.Candidates) + @($static.Candidates))
    $preferred = Filter-CandidatesPreferDynamicInvoke -Candidates @($merged.Candidates)

    $candidates = @()
    foreach ($cand in @($preferred.Candidates)) {
        $sourceKind = if ($cand.PSObject.Properties['SourceKind']) { [string]$cand.SourceKind } else { 'Resolvable' }
        $confidence = if ($cand.PSObject.Properties['Confidence']) { [string]$cand.Confidence } elseif ($sourceKind -eq 'Static') { 'High' } else { $null }
        $usedEmptyFallback = if ($cand.PSObject.Properties['UsedEmptyFallback']) { [bool]$cand.UsedEmptyFallback } else { $false }
        $resultType = if ($cand.PSObject.Properties['ResultType']) { [string]$cand.ResultType } else { $null }
        $executed = if ($cand.PSObject.Properties['Executed']) { [bool]$cand.Executed } else { ($sourceKind -ne 'Static') }

        $copy = [PSCustomObject]@{
            StartOffset = $cand.StartOffset
            EndOffset   = $cand.EndOffset
            Replacement = $cand.Replacement
            Original    = $cand.Original
            Type        = $cand.Type
            Depth       = $cand.Depth
            NodeId      = $cand.NodeId
            SourceKind  = $sourceKind
            Confidence  = $confidence
            UsedEmptyFallback = $usedEmptyFallback
            ResultType  = $resultType
            Executed    = $executed
            VariableName = if ($cand.PSObject.Properties['VariableName']) { [string]$cand.VariableName } else { $null }
            IsSimpleVariable = if ($cand.PSObject.Properties['IsSimpleVariable']) { [bool]$cand.IsSimpleVariable } else { $false }
            IsValueChanged = if ($cand.PSObject.Properties['IsValueChanged']) { [bool]$cand.IsValueChanged } else { $false }
            ObservedValueCount = if ($cand.PSObject.Properties['ObservedValueCount']) { [int]$cand.ObservedValueCount } else { 1 }
            DynamicStopReason = if ($cand.PSObject.Properties['DynamicStopReason']) { [string]$cand.DynamicStopReason } else { $null }
            DynamicStopMessage = if ($cand.PSObject.Properties['DynamicStopMessage']) { [string]$cand.DynamicStopMessage } else { $null }
            Key         = (Get-ReplacementKey -Candidate $cand)
            IsSelected  = $false
            IsManual    = $false
        }
        $candidates += $copy
    }

    $auto = Select-NonOverlappingReplacements -Candidates $candidates -Strategy $Strategy
    $autoKeys = @{}
    foreach ($x in @($auto.Selected)) { $autoKeys[[string]$x.Key] = $true }

    $selectedByKey = @{}
    foreach ($c in $candidates) {
        $k = [string]$c.Key
        if ($ManualSelection -and $ManualSelection.ContainsKey($k)) {
            $selectedByKey[$k] = [bool]$ManualSelection[$k]
            $c.IsManual = $true
        } else {
            if ($c.IsSimpleVariable) {
                $selectedByKey[$k] = (-not $c.IsValueChanged)
            } elseif ($c.SourceKind -eq 'Static' -and $c.UsedEmptyFallback) {
                $selectedByKey[$k] = $false
            } else {
                $selectedByKey[$k] = $autoKeys.ContainsKey($k)
            }
            $c.IsManual = $false
        }
    }

    $resolved = Resolve-SelectedCandidates -Candidates $candidates -SelectedByKey $selectedByKey -ManualSelection $ManualSelection -Strategy $Strategy
    $syntaxGuard = Ensure-SyntaxSafeReplacements -ScriptText $ScriptText -Selected $resolved.Selected
    $finalSelected = @($syntaxGuard.Selected)
    $resolvedKeys = @{}
    foreach ($x in @($finalSelected)) { $resolvedKeys[[string]$x.Key] = $true }
    foreach ($c in $candidates) {
        $c.IsSelected = $resolvedKeys.ContainsKey([string]$c.Key)
    }

    $newText = Apply-ReplacementsToText -Text $ScriptText -Replacements $finalSelected

    return [PSCustomObject]@{
        Candidates = @($candidates)
        Selected   = @($finalSelected)
        Skipped    = @($dynamic.Skipped) + @($wholeScriptDynamic.Skipped) + @($base.Skipped) + @($static.Skipped) + @($merged.Skipped) + @($preferred.Skipped) + @($resolved.Skipped) + @($syntaxGuard.Skipped)
        Rebuilt    = $newText
    }
}
function Get-DotPlainLayout {
    param([Parameter(Mandatory)][string]$DotPath)

    $dotCmd = Get-Command dot -ErrorAction SilentlyContinue
    if (-not $dotCmd) { return $null }
    if (-not (Test-Path -LiteralPath $DotPath)) { return $null }

    $plain = & $dotCmd.Source -Tplain $DotPath 2>$null
    if (-not $plain -or $plain.Count -eq 0) { return $null }

    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $nodes = @{}
    $graphW = $null
    $graphH = $null
    foreach ($line in $plain) {
        if ($line -match '^graph\s+\S+\s+(\S+)\s+(\S+)\s*$') {
            $graphW = [double]::Parse($Matches[1], $inv)
            $graphH = [double]::Parse($Matches[2], $inv)
            continue
        }
        if ($line -match '^node\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+("((?:\\.|[^"\\])*)"|<<(.+)>>)\s+.*$') {
            $id = [string]$Matches[1]
            $x = [double]::Parse($Matches[2], $inv)
            $y = [double]::Parse($Matches[3], $inv)
            $w = [double]::Parse($Matches[4], $inv)
            $h = [double]::Parse($Matches[5], $inv)
            $quoted = [string]$Matches[7]
            $html = [string]$Matches[8]
            $label = if (-not [string]::IsNullOrWhiteSpace($quoted)) {
                $quoted -replace '\\l', "`n"
            } else {
                $t = $html -replace '<BR[^>]*>', "`n"
                $t = $t -replace '<[^>]+>', ''
                [System.Net.WebUtility]::HtmlDecode($t)
            }
            $nodes[$id] = [PSCustomObject]@{
                Id = $id; X = $x; Y = $y; W = $w; H = $h; Label = $label
            }
        }
    }
    if ($null -eq $graphW -or $null -eq $graphH) { return $null }
    return [PSCustomObject]@{
        GraphWidth = $graphW
        GraphHeight = $graphH
        Nodes = $nodes
    }
}

function Get-ContextRuntimeSubgraphs {
    param([hashtable]$Context)

    if ($null -eq $Context -or -not $Context.ContainsKey('RuntimeSubgraphs') -or $null -eq $Context.RuntimeSubgraphs) {
        return @()
    }

    $ordered = New-Object System.Collections.Generic.List[object]
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    if ($Context.ContainsKey('RuntimeSubgraphOrder') -and $null -ne $Context.RuntimeSubgraphOrder) {
        foreach ($name in @($Context.RuntimeSubgraphOrder)) {
            if ([string]::IsNullOrWhiteSpace([string]$name)) { continue }
            if (-not $Context.RuntimeSubgraphs.ContainsKey($name)) { continue }
            $ordered.Add($Context.RuntimeSubgraphs[$name]) | Out-Null
            $seen.Add([string]$name) | Out-Null
        }
    }

    foreach ($entry in @($Context.RuntimeSubgraphs.Values | Sort-Object CreatedIndex, BlockName)) {
        if (-not $entry) { continue }
        $name = [string]$entry.BlockName
        if ($seen.Contains($name)) { continue }
        $ordered.Add($entry) | Out-Null
    }

    return @($ordered.ToArray())
}

function Get-RuntimeSubgraphInfoForNode {
    param(
        [hashtable]$Context,
        $Node
    )

    if ($null -eq $Context) { return $null }
    $Node = Resolve-CFGNodeValue -CFG $Context.CFG -Value $Node
    if ($null -eq $Node) { return $null }
    if (-not $Node.PSObject.Properties['RuntimeBlockName']) { return $null }

    $blockName = [string]$Node.RuntimeBlockName
    if ([string]::IsNullOrWhiteSpace($blockName)) { return $null }
    if (-not $Context.ContainsKey('RuntimeSubgraphs') -or $null -eq $Context.RuntimeSubgraphs) { return $null }
    if (-not $Context.RuntimeSubgraphs.ContainsKey($blockName)) { return $null }
    return $Context.RuntimeSubgraphs[$blockName]
}

function Get-GraphNodeIdForDisplay {
    param(
        [hashtable]$Context,
        $Node
    )

    $Node = Resolve-CFGNodeValue -CFG $Context.CFG -Value $Node
    if ($null -eq $Node) { return 0 }
    $nodeId = [int]$Node.Id

    if ($script:DebugState -and $script:DebugState.Layout -and $script:DebugState.Layout.Nodes -and $script:DebugState.Layout.Nodes.ContainsKey([string]$nodeId)) {
        return $nodeId
    }

    $runtimeInfo = Get-RuntimeSubgraphInfoForNode -Context $Context -Node $Node
    if ($runtimeInfo -and $runtimeInfo.CallerNodeId) {
        return [int]$runtimeInfo.CallerNodeId
    }

    return $nodeId
}

function Get-ReplacementOwnerNodeId {
    param(
        [hashtable]$Context,
        $Node
    )

    $Node = Resolve-CFGNodeValue -CFG $Context.CFG -Value $Node
    if ($null -eq $Node) { return $null }

    $runtimeInfo = Get-RuntimeSubgraphInfoForNode -Context $Context -Node $Node
    if ($runtimeInfo -and $runtimeInfo.CallerNodeId) {
        return [int]$runtimeInfo.CallerNodeId
    }

    return [int]$Node.Id
}

function Build-RuntimeSubgraphRows {
    param(
        [hashtable]$Context,
        $CurrentNode
    )

    $CurrentNode = Resolve-CFGNodeValue -CFG $Context.CFG -Value $CurrentNode
    $entries = Get-ContextRuntimeSubgraphs -Context $Context
    if (-not $entries -or $entries.Count -eq 0) { return @() }

    $activeBlockNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if ($Context.ScopeStack) {
        foreach ($scope in @($Context.ScopeStack)) {
            if (-not $scope -or [string]$scope.ScopeType -ne 'ScriptBlock') { continue }
            $null = $activeBlockNames.Add([string]$scope.ScopeName)
        }
    }

    $currentRuntimeBlock = $null
    if ($CurrentNode -and $CurrentNode.PSObject.Properties['RuntimeBlockName']) {
        $currentRuntimeBlock = [string]$CurrentNode.RuntimeBlockName
    }

    $rows = @()
    foreach ($info in $entries) {
        $isCurrent = (-not [string]::IsNullOrWhiteSpace($currentRuntimeBlock) -and $currentRuntimeBlock -eq [string]$info.BlockName)
        $statusKey = if ($isCurrent) {
            'Current'
        } elseif ($activeBlockNames.Contains([string]$info.BlockName)) {
            'Open'
        } else {
            'Returned'
        }
        $status = switch ($statusKey) {
            'Current' { L 'dynamic.status.current' }
            'Open' { L 'dynamic.status.open' }
            default { L 'dynamic.status.returned' }
        }

        $rows += [PSCustomObject]@{
            BlockName        = [string]$info.BlockName
            DynamicType      = [string]$info.DynamicType
            StatusKey        = $statusKey
            Status           = $status
            CallerNodeId     = if ($info.CallerNodeId) { [int]$info.CallerNodeId } else { $null }
            CallerText       = ConvertTo-PreviewText -Text ([string]$info.CallerText) -MaxLen 90
            ParentBlockName  = [string]$info.ParentBlockName
            CurrentNodeId    = if ($isCurrent -and $CurrentNode) { [int]$CurrentNode.Id } else { $null }
            CodePreview      = ConvertTo-PreviewText -Text ([string]$info.ArgumentValue) -MaxLen 120
            CreatedIndex     = if ($info.CreatedIndex) { [int]$info.CreatedIndex } else { 0 }
            BlockStartId     = if ($info.BlockStartId) { [int]$info.BlockStartId } else { $null }
            BlockEndId       = if ($info.BlockEndId) { [int]$info.BlockEndId } else { $null }
        }
    }

    return @($rows | Sort-Object CreatedIndex, BlockName)
}

function Get-RuntimeSubgraphDetailText {
    param(
        [hashtable]$Context,
        $Row
    )

    if ($null -eq $Row) { return '' }

    $info = $null
    if ($Context -and $Context.ContainsKey('RuntimeSubgraphs') -and $Context.RuntimeSubgraphs -and $Context.RuntimeSubgraphs.ContainsKey([string]$Row.BlockName)) {
        $info = $Context.RuntimeSubgraphs[[string]$Row.BlockName]
    }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("$((L 'dynamic.field.block')) : $([string]$Row.BlockName)") | Out-Null
    $lines.Add("$((L 'dynamic.field.type')) : $([string]$Row.DynamicType)") | Out-Null
    $lines.Add("$((L 'dynamic.field.status')) : $([string]$Row.Status)") | Out-Null
    if ($Row.ParentBlockName) { $lines.Add("$((L 'dynamic.field.parent')) : $([string]$Row.ParentBlockName)") | Out-Null }
    if ($Row.CallerNodeId) { $lines.Add("$((L 'dynamic.field.caller')) : Node $([int]$Row.CallerNodeId)") | Out-Null }
    if ($info -and $info.CallerText) {
        $lines.Add("$((L 'dynamic.field.caller_text')) : $([string]$info.CallerText)") | Out-Null
    }
    if ($info -and $info.ArgumentCode) {
        $lines.Add("$((L 'dynamic.field.arg_code')) : $([string]$info.ArgumentCode)") | Out-Null
    }
    if ($info -and $info.ArgumentValue) {
        $lines.Add("$((L 'dynamic.field.code')) : $([string]$info.ArgumentValue)") | Out-Null
    }
    if ($info -and $info.PSObject.Properties['StopReason'] -and $info.StopReason) {
        $lines.Add("$((L 'dynamic.field.stop_reason')) : $([string]$info.StopReason)") | Out-Null
    }
    if ($info -and $info.PSObject.Properties['StopMessage'] -and $info.StopMessage) {
        $stopReason = if ($info.PSObject.Properties['StopReason']) { [string]$info.StopReason } else { $null }
        $stopMessage = Resolve-LocalizedDiagnosticMessage -Language $script:UiLanguage -Reason $stopReason -Message ([string]$info.StopMessage)
        $lines.Add("$((L 'dynamic.field.stop_message')) : $([string]$stopMessage)") | Out-Null
    }
    if ($info -and $info.BlockStartId) {
        $lines.Add("$((L 'dynamic.field.range')) : $($info.BlockStartId) -> $($info.BlockEndId)") | Out-Null
    }
    if ($Row.CurrentNodeId) {
        $lines.Add("$((L 'dynamic.field.current')) : Node $([int]$Row.CurrentNodeId)") | Out-Null
    }

    return ($lines -join [Environment]::NewLine)
}

$scriptPathFull = (Resolve-Path -LiteralPath $ScriptPath).ProviderPath
if ([string]::IsNullOrWhiteSpace($WorkDir)) {
    $WorkDir = $scriptPathFull + '.debug.work'
}
$WorkDir = [System.IO.Path]::GetFullPath($WorkDir)
if (-not (Test-Path -LiteralPath $WorkDir)) {
    $null = New-Item -ItemType Directory -Path $WorkDir -Force
}

$cfgDotPath = Join-Path $WorkDir 'debug.cfg.dot'
$cfgPngPath = [System.IO.Path]::ChangeExtension($cfgDotPath, '.png')
$logPath = Join-Path $WorkDir 'debug.execution.log'
$outPath = Join-Path $WorkDir 'debug.out.ps1'
$reportPath = Join-Path $WorkDir 'debug.report.json'
$uiErrorLogPath = Join-Path $WorkDir 'debug.ui-error.log'
Remove-Item -LiteralPath $uiErrorLogPath -ErrorAction SilentlyContinue

$cfg = Get-ScriptControlFlow -ScriptPath $scriptPathFull
if (-not $cfg) { throw "CFG 生成失败: $scriptPathFull" }
try {
    Export-CfgToDot -finalCFG $cfg -outputPath $cfgDotPath | Out-Null
} catch {
    Write-Warning "导出 CFG 失败: $_"
}
$layout = Get-DotPlainLayout -DotPath $cfgDotPath
$scriptText = Get-FullScriptTextFromFile -Path $scriptPathFull
$session = New-CFGExecutionSession -CFG $cfg -LogPath $logPath -MaxIterations $MaxIterations -MaxTotalNodes $MaxTotalNodes -DynamicTimeBudgetMs $DynamicTimeBudgetMs
$currentHostDisplay = Format-PowerShellHostInfo -HostInfo $session.Context.HostInfo
$script:CurrentHostDisplay = $currentHostDisplay
$preview = Build-DebugPreview -Context $session.Context -ScriptText $scriptText -Strategy $OverlapStrategy

function Set-DebugWindowTitle {
    param($Window)

    if ($null -eq $Window) { return }
    $fileName = [System.IO.Path]::GetFileName($scriptPathFull)
    if ([string]::IsNullOrWhiteSpace([string]$script:CurrentHostDisplay)) {
        $Window.Title = [string](L 'xaml.window_title')
        return
    }
    $Window.Title = "{0} - {1} [{2}]" -f (L 'xaml.window_title'), $fileName, $script:CurrentHostDisplay
}

if ($NoUI) {
    [PSCustomObject]@{
        ScriptPath   = $scriptPathFull
        WorkDir      = $WorkDir
        Host         = $currentHostDisplay
        Nodes        = $cfg.Nodes.Count
        Steps        = $session.StepCounter
        HasGraphPng  = [bool](Test-Path -LiteralPath $cfgPngPath)
        RuntimeSubgraphs = if ($session.Context.ContainsKey('RuntimeSubgraphs') -and $session.Context.RuntimeSubgraphs) { [int]$session.Context.RuntimeSubgraphs.Count } else { 0 }
        Candidates   = $preview.Candidates.Count
        Selected     = $preview.Selected.Count
        Skipped      = $preview.Skipped.Count
    } | Format-List
    Close-CFGExecutionSession -Session $session
    return
}

$mainXamlText = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="__LOC_XAML_WINDOW_TITLE__" Height="920" Width="1550"
        WindowStartupLocation="CenterScreen">
  <DockPanel>
    <Border DockPanel.Dock="Top" Background="#F3F3F3" BorderBrush="#DDDDDD" BorderThickness="0,0,0,1">
      <Grid Margin="10,8">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="12"/>
          <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>
        <StackPanel Orientation="Horizontal" Grid.Column="0">
          <Button Name="BtnNext" Content="__LOC_XAML_BTN_NEXT__" Width="90" Margin="0,0,8,0"/>
          <Button Name="BtnRunAll" Content="__LOC_XAML_BTN_RUN_ALL__" Width="100" Margin="0,0,8,0"/>
          <Button Name="BtnReset" Content="__LOC_XAML_BTN_RESET__" Width="90" Margin="0,0,8,0"/>
          <Button Name="BtnExport" Content="__LOC_XAML_BTN_EXPORT__" Width="120" Margin="0,0,12,0"/>
          <TextBlock Text="__LOC_XAML_ZOOM_LABEL__" VerticalAlignment="Center" Margin="0,0,8,0" Foreground="#444"/>
          <Button Name="BtnZoomOut" Content="-" Width="28" Margin="0,0,6,0"/>
          <Slider Name="SldZoom" Width="140" Minimum="20" Maximum="300" Value="100" TickFrequency="10"
                  IsSnapToTickEnabled="False" SmallChange="5" LargeChange="20" VerticalAlignment="Center"
                  Margin="0,0,6,0"/>
          <Button Name="BtnZoomIn" Content="+" Width="28" Margin="0,0,6,0"/>
          <Button Name="BtnZoomReset" Content="100%" Width="60" Margin="0,0,6,0"/>
          <TextBlock Name="TxtZoomValue" Width="48" VerticalAlignment="Center" Foreground="#444"/>
        </StackPanel>
        <TextBlock Name="TxtStatus" Grid.Column="2" VerticalAlignment="Center" FontFamily="Consolas" FontSize="12" Foreground="#444"/>
      </Grid>
    </Border>

    <Grid>
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="500" MinWidth="280"/>
        <ColumnDefinition Width="6"/>
        <ColumnDefinition Width="*" MinWidth="520"/>
      </Grid.ColumnDefinitions>

      <DataGrid Grid.Column="0" Name="StepsGrid" Margin="10,10,6,10" AutoGenerateColumns="False" IsReadOnly="True"
                CanUserAddRows="False" SelectionMode="Single" SelectionUnit="FullRow"
                EnableRowVirtualization="True" EnableColumnVirtualization="True"
                FontFamily="Consolas" FontSize="12">
        <DataGrid.Columns>
          <DataGridTextColumn Header="Step" Binding="{Binding Step}" Width="60"/>
          <DataGridTextColumn Header="Node" Binding="{Binding NodeId}" Width="65"/>
          <DataGridTextColumn Header="__LOC_XAML_COLUMN_SCOPE__" Binding="{Binding Scope}" Width="80"/>
          <DataGridTextColumn Header="Type" Binding="{Binding NodeType}" Width="130"/>
          <DataGridTextColumn Header="Status" Binding="{Binding Status}" Width="90"/>
          <DataGridTextColumn Header="Next" Binding="{Binding NextText}" Width="*"/>
        </DataGrid.Columns>
      </DataGrid>

      <GridSplitter Grid.Column="1" Width="6" HorizontalAlignment="Stretch" VerticalAlignment="Stretch"
                    ResizeBehavior="PreviousAndNext" ResizeDirection="Columns" ShowsPreview="True"
                    Background="#E0E0E0"/>

      <Grid Grid.Column="2">
        <Grid.RowDefinitions>
          <RowDefinition Height="*" MinHeight="220"/>
          <RowDefinition Height="6"/>
          <RowDefinition Height="340" MinHeight="220"/>
        </Grid.RowDefinitions>

        <Border Grid.Row="0" Margin="6,10,10,6" BorderBrush="#DDDDDD" BorderThickness="1" Background="#FAFAFA">
          <ScrollViewer Name="GraphScroll" HorizontalScrollBarVisibility="Auto" VerticalScrollBarVisibility="Auto">
            <Grid Name="GraphContainer">
              <Image Name="GraphImage" Stretch="Fill"/>
              <Canvas Name="GraphOverlay" Background="Transparent"/>
            </Grid>
          </ScrollViewer>
        </Border>

        <GridSplitter Grid.Row="1" Height="6" HorizontalAlignment="Stretch" VerticalAlignment="Stretch"
                      ResizeBehavior="PreviousAndNext" ResizeDirection="Rows" ShowsPreview="True"
                      Background="#E0E0E0"/>

        <TabControl Grid.Row="2" Margin="6,6,10,10">
          <TabItem Header="__LOC_XAML_TAB_CURRENT_NODE__">
            <Grid Margin="10">
              <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="100" MinHeight="70"/>
                <RowDefinition Height="6"/>
                <RowDefinition Height="*" MinHeight="120"/>
              </Grid.RowDefinitions>
              <TextBlock Name="TxtNodeHeader" FontSize="14" FontWeight="Bold" TextWrapping="Wrap"/>
              <TextBlock Name="TxtNodeMeta" Grid.Row="1" Foreground="#555" Margin="0,6,0,6" TextWrapping="Wrap"/>
              <TextBlock Name="TxtNextEdge" Grid.Row="2" Foreground="#0B5394" Margin="0,0,0,8" TextWrapping="Wrap"/>
              <TextBox Name="TxtNodeCode" Grid.Row="3" FontFamily="Consolas" FontSize="12" IsReadOnly="True"
                       VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" TextWrapping="Wrap"/>

              <GridSplitter Grid.Row="4" Height="6" HorizontalAlignment="Stretch" VerticalAlignment="Stretch"
                            ResizeBehavior="PreviousAndNext" ResizeDirection="Rows"
                            ShowsPreview="True" Background="#E0E0E0"/>

              <Grid Grid.Row="5">
                <Grid.RowDefinitions>
                  <RowDefinition Height="Auto"/>
                  <RowDefinition Height="*"/>
                </Grid.RowDefinitions>
                <TextBlock Name="TxtNodeReplaceSummary" Foreground="#555" TextWrapping="Wrap"/>
                <DataGrid Name="NodeReplaceGrid" Grid.Row="1" AutoGenerateColumns="False" CanUserAddRows="False"
                          EnableRowVirtualization="True" FontFamily="Consolas" FontSize="12" Margin="0,8,0,0"
                          IsReadOnly="False">
                  <DataGrid.Columns>
                    <DataGridTemplateColumn Header="__LOC_XAML_COLUMN_REPLACE__" Width="56">
                      <DataGridTemplateColumn.CellTemplate>
                        <DataTemplate>
                          <CheckBox IsChecked="{Binding IsSelected, Mode=TwoWay, UpdateSourceTrigger=PropertyChanged}" HorizontalAlignment="Center"/>
                        </DataTemplate>
                      </DataGridTemplateColumn.CellTemplate>
                    </DataGridTemplateColumn>
                    <DataGridTextColumn Header="Type" Binding="{Binding Type}" Width="110"/>
                    <DataGridTextColumn Header="__LOC_XAML_COLUMN_SOURCE__" Binding="{Binding SourceLabel}" Width="66"/>
                    <DataGridTextColumn Header="__LOC_XAML_COLUMN_CONFIDENCE__" Binding="{Binding ConfidenceLabel}" Width="66"/>
                    <DataGridTextColumn Header="__LOC_XAML_COLUMN_VARIABLE__" Binding="{Binding VariableName}" Width="110"/>
                    <DataGridTextColumn Header="__LOC_XAML_COLUMN_CHANGED__" Binding="{Binding ChangedFlag}" Width="66"/>
                    <DataGridTextColumn Header="Original" Binding="{Binding Original}" Width="*"/>
                    <DataGridTextColumn Header="Replacement" Binding="{Binding Replacement}" Width="*"/>
                    <DataGridTextColumn Header="Start" Binding="{Binding StartOffset}" Width="70"/>
                    <DataGridTextColumn Header="End" Binding="{Binding EndOffset}" Width="70"/>
                  </DataGrid.Columns>
                </DataGrid>
              </Grid>
            </Grid>
          </TabItem>

          <TabItem Header="__LOC_XAML_TAB_VARIABLE_STACK__">
            <Grid Margin="10">
              <Grid.RowDefinitions>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
              </Grid.RowDefinitions>
              <DataGrid Name="VarGrid" Grid.Row="0" AutoGenerateColumns="False" IsReadOnly="True" CanUserAddRows="False"
                        EnableRowVirtualization="True" FontFamily="Consolas" FontSize="12">
                <DataGrid.Columns>
                  <DataGridTextColumn Header="__LOC_XAML_COLUMN_DISPLAY_NAME__" Binding="{Binding DisplayName}" Width="160"/>
                  <DataGridTextColumn Header="__LOC_XAML_COLUMN_ACTUAL_NAME__" Binding="{Binding ActualName}" Width="220"/>
                  <DataGridTextColumn Header="__LOC_XAML_COLUMN_VALUE__" Binding="{Binding ValueText}" Width="*"/>
                </DataGrid.Columns>
              </DataGrid>
              <Border Grid.Row="1" Margin="0,8,0,0" BorderBrush="#DDDDDD" BorderThickness="1" Padding="8">
                <Grid>
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="220"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                  </Grid.ColumnDefinitions>
                  <TextBlock Grid.Column="0" Text="__LOC_XAML_CURRENT_VARIABLE__" VerticalAlignment="Center"/>
                  <TextBox Grid.Column="1" Name="TxtVarName" Margin="8,0,12,0"/>
                  <TextBlock Grid.Column="2" Text="__LOC_XAML_NEW_VALUE_EXPRESSION__" VerticalAlignment="Center"/>
                  <TextBox Grid.Column="3" Name="TxtVarExpr" Margin="8,0,12,0"/>
                  <Button Grid.Column="4" Name="BtnApplyVar" Content="__LOC_XAML_BTN_APPLY_VAR__" Width="90" Margin="0,0,8,0"/>
                  <Button Grid.Column="5" Name="BtnRefreshVar" Content="__LOC_XAML_BTN_REFRESH_VAR__" Width="70"/>
                  <CheckBox Grid.Column="6" Name="ChkVarAdvanced" Content="__LOC_XAML_CHK_ADVANCED__" Margin="12,0,0,0" VerticalAlignment="Center"/>
                </Grid>
              </Border>
            </Grid>
          </TabItem>

          <TabItem Header="__LOC_XAML_TAB_EXPORT_PREVIEW__">
            <Grid Margin="10">
              <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
              </Grid.RowDefinitions>
              <TextBlock Name="TxtPreviewSummary" Foreground="#555" TextWrapping="Wrap"/>
              <TextBox Name="TxtRebuiltPreview" Grid.Row="1" FontFamily="Consolas" FontSize="12" IsReadOnly="True"
                       VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" TextWrapping="Wrap"
                       AcceptsReturn="True"/>
            </Grid>
          </TabItem>

          <TabItem Header="__LOC_XAML_TAB_RUNTIME_SUBGRAPHS__">
            <Grid Margin="10">
              <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="170" MinHeight="120"/>
                <RowDefinition Height="6"/>
                <RowDefinition Height="*"/>
              </Grid.RowDefinitions>
              <TextBlock Name="TxtDynamicSummary" Foreground="#555" TextWrapping="Wrap"/>
              <DataGrid Name="DynamicGrid" Grid.Row="1" AutoGenerateColumns="False" CanUserAddRows="False"
                        IsReadOnly="True" EnableRowVirtualization="True" FontFamily="Consolas" FontSize="12"
                        Margin="0,8,0,0" SelectionMode="Single" SelectionUnit="FullRow">
                <DataGrid.Columns>
                  <DataGridTextColumn Header="#" Binding="{Binding CreatedIndex}" Width="45"/>
                  <DataGridTextColumn Header="Block" Binding="{Binding BlockName}" Width="135"/>
                  <DataGridTextColumn Header="Type" Binding="{Binding DynamicType}" Width="110"/>
                  <DataGridTextColumn Header="Status" Binding="{Binding Status}" Width="80"/>
                  <DataGridTextColumn Header="Caller" Binding="{Binding CallerNodeId}" Width="70"/>
                  <DataGridTextColumn Header="Parent" Binding="{Binding ParentBlockName}" Width="120"/>
                  <DataGridTextColumn Header="Current" Binding="{Binding CurrentNodeId}" Width="70"/>
                  <DataGridTextColumn Header="Code" Binding="{Binding CodePreview}" Width="*"/>
                </DataGrid.Columns>
              </DataGrid>
              <GridSplitter Grid.Row="2" Height="6" HorizontalAlignment="Stretch" VerticalAlignment="Stretch"
                            ResizeBehavior="PreviousAndNext" ResizeDirection="Rows"
                            ShowsPreview="True" Background="#E0E0E0"/>
              <TextBox Name="TxtDynamicDetail" Grid.Row="3" FontFamily="Consolas" FontSize="12" IsReadOnly="True"
                       VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"
                       TextWrapping="Wrap" AcceptsReturn="True"/>
            </Grid>
          </TabItem>
        </TabControl>
      </Grid>
    </Grid>
  </DockPanel>
</Window>
'@

[xml]$mainXaml = Resolve-LocalizedTemplate -Template $mainXamlText -Pack $script:UiText
$reader = New-Object System.Xml.XmlNodeReader $mainXaml
$window = [System.Windows.Markup.XamlReader]::Load($reader)

$btnNext = $window.FindName('BtnNext')
$btnRunAll = $window.FindName('BtnRunAll')
$btnReset = $window.FindName('BtnReset')
$btnExport = $window.FindName('BtnExport')
$btnZoomOut = $window.FindName('BtnZoomOut')
$btnZoomIn = $window.FindName('BtnZoomIn')
$btnZoomReset = $window.FindName('BtnZoomReset')
$sldZoom = $window.FindName('SldZoom')
$txtZoomValue = $window.FindName('TxtZoomValue')
$txtStatus = $window.FindName('TxtStatus')
$stepsGrid = $window.FindName('StepsGrid')
$graphScroll = $window.FindName('GraphScroll')
$graphContainer = $window.FindName('GraphContainer')
$graphImage = $window.FindName('GraphImage')
$graphOverlay = $window.FindName('GraphOverlay')
$txtNodeHeader = $window.FindName('TxtNodeHeader')
$txtNodeMeta = $window.FindName('TxtNodeMeta')
$txtNextEdge = $window.FindName('TxtNextEdge')
$txtNodeCode = $window.FindName('TxtNodeCode')
$txtNodeReplaceSummary = $window.FindName('TxtNodeReplaceSummary')
$nodeReplaceGrid = $window.FindName('NodeReplaceGrid')
$varGrid = $window.FindName('VarGrid')
$txtVarName = $window.FindName('TxtVarName')
$txtVarExpr = $window.FindName('TxtVarExpr')
$btnApplyVar = $window.FindName('BtnApplyVar')
$btnRefreshVar = $window.FindName('BtnRefreshVar')
$chkVarAdvanced = $window.FindName('ChkVarAdvanced')
$txtPreviewSummary = $window.FindName('TxtPreviewSummary')
$txtRebuiltPreview = $window.FindName('TxtRebuiltPreview')
$txtDynamicSummary = $window.FindName('TxtDynamicSummary')
$dynamicGrid = $window.FindName('DynamicGrid')
$txtDynamicDetail = $window.FindName('TxtDynamicDetail')

$script:DebugState = @{
    ScriptPath     = $scriptPathFull
    WorkDir        = $WorkDir
    LogPath        = $logPath
    DotPath        = $cfgDotPath
    PngPath        = $cfgPngPath
    ReportPath     = $reportPath
    OutPath        = $outPath
    Cfg            = $cfg
    Layout         = $layout
    OriginalText   = $scriptText
    Session        = $session
    Steps          = New-Object System.Collections.ArrayList
    UserSelection  = @{}
    SelectionVersion = 0
    LastPreviewContextSig = ''
    LastPreviewSelectionVersion = -1
    PreviewStamp   = 0
    NodeRowsCache  = @{}
    LastAutoUncheckMessage = $null
    HoldPendingNextNodeId = $null
    HoldAfterNodeId = $null
    Preview        = $preview
    SelectedRuntimeBlockName = $null
    LastGraphSignature = ''
    IsRunAllActive = $false
}

$script:NodeRectsDip = @{}
$script:NodeHotRects = @{}
$script:GraphZoom = 1.0
$script:SyncingZoom = $false
$script:SyncingNodeSelection = $false
$script:SyncingDynamicSelection = $false
$script:SelectionRefreshQueued = $false
$script:RunAllTimer = $null

$highlightRect = New-Object System.Windows.Shapes.Rectangle
$highlightRect.Stroke = [System.Windows.Media.Brushes]::Red
$highlightRect.StrokeThickness = 4
$highlightRect.Fill = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(28, 255, 0, 0))
$highlightRect.Visibility = 'Collapsed'
$highlightRect.IsHitTestVisible = $false
[System.Windows.Controls.Canvas]::SetZIndex($highlightRect, 1000)
$graphOverlay.Children.Add($highlightRect) | Out-Null

function Reset-GraphOverlay {
    $script:NodeRectsDip.Clear()
    $script:NodeHotRects.Clear()
    $graphOverlay.Children.Clear()
    $graphOverlay.Children.Add($highlightRect) | Out-Null
    $highlightRect.Visibility = 'Collapsed'
}

function Set-GraphPlaceholder {
    param([string]$Message)
    $graphImage.Source = $null
    $graphImage.Width = [double]::NaN
    $graphImage.Height = [double]::NaN
    $graphContainer.Width = [double]::NaN
    $graphContainer.Height = [double]::NaN
    Reset-GraphOverlay
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text = $Message
    $tb.Margin = '20'
    $tb.FontSize = 14
    $tb.Foreground = [System.Windows.Media.Brushes]::Gray
    $graphOverlay.Children.Add($tb) | Out-Null
}

function Get-GraphStateSignature {
    param([hashtable]$Context)

    $nodeCount = if ($script:DebugState.Cfg -and $script:DebugState.Cfg.Nodes) { @($script:DebugState.Cfg.Nodes).Count } else { 0 }
    $edgeCount = if ($script:DebugState.Cfg -and $script:DebugState.Cfg.Edges) { @($script:DebugState.Cfg.Edges).Count } else { 0 }
    $runtimeCount = 0
    $dynamicCount = 0

    if ($Context) {
        if ($Context.ContainsKey('RuntimeSubgraphs') -and $Context.RuntimeSubgraphs) {
            $runtimeCount = [int]$Context.RuntimeSubgraphs.Count
        }
        if ($Context.ContainsKey('DynamicInvokeResults') -and $Context.DynamicInvokeResults) {
            $dynamicCount = [int]$Context.DynamicInvokeResults.Count
        }
    }

    return "$nodeCount|$edgeCount|$runtimeCount|$dynamicCount"
}

function Ensure-GraphLoaded {
    Reset-GraphOverlay
    if (-not (Test-Path -LiteralPath $script:DebugState.PngPath)) {
        Set-GraphPlaceholder -Message (L 'graph.placeholder.missing_png')
        return
    }
    try {
        $pngPath = (Resolve-Path -LiteralPath $script:DebugState.PngPath).ProviderPath
        $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
        $bmp.BeginInit()
        $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bmp.CreateOptions = [System.Windows.Media.Imaging.BitmapCreateOptions]::IgnoreImageCache
        $bmp.UriSource = [Uri]$pngPath
        $bmp.EndInit()
        $bmp.Freeze()
        $graphImage.Source = $bmp
    } catch {
        Set-GraphPlaceholder -Message (L 'graph.placeholder.load_png_failed' @($_.Exception.Message))
    }
}

function Refresh-LiveGraphArtifacts {
    param(
        [switch]$Force,
        [string]$Reason
    )

    $ctx = if ($script:DebugState.Session) { $script:DebugState.Session.Context } else { $null }
    $newSignature = Get-GraphStateSignature -Context $ctx
    if (-not $Force -and $newSignature -eq [string]$script:DebugState.LastGraphSignature) {
        return $false
    }

    try {
        Export-CfgToDot -finalCFG $script:DebugState.Cfg -outputPath $script:DebugState.DotPath | Out-Null
        $newLayout = Get-DotPlainLayout -DotPath $script:DebugState.DotPath
        if ($newLayout) {
            $script:DebugState.Layout = $newLayout
        }
        Ensure-GraphLoaded
        Apply-GraphZoom
        $script:DebugState.LastGraphSignature = $newSignature
        return $true
    } catch {
        $msg = L 'graph.refresh_failed' @($Reason, $_.Exception.Message)
        Update-StatusBar -Suffix $msg
        return $false
    }
}

function Rebuild-GraphHotspots {
    if (-not $script:DebugState.Layout) { return }
    if (-not $graphImage.Source) { return }

    $graphW = [double]$script:DebugState.Layout.GraphWidth
    $graphH = [double]$script:DebugState.Layout.GraphHeight
    $imgW = if ($graphImage.Width -gt 0) { [double]$graphImage.Width } else { [double]$graphImage.ActualWidth }
    $imgH = if ($graphImage.Height -gt 0) { [double]$graphImage.Height } else { [double]$graphImage.ActualHeight }
    if ($imgW -le 0 -or $imgH -le 0) { return }

    $graphOverlay.Width = $imgW
    $graphOverlay.Height = $imgH
    $graphContainer.Width = $imgW
    $graphContainer.Height = $imgH

    $sx = $imgW / $graphW
    $sy = $imgH / $graphH

    $graphOverlay.Children.Clear()
    $graphOverlay.Children.Add($highlightRect) | Out-Null
    $highlightRect.Visibility = 'Collapsed'
    $script:NodeRectsDip.Clear()
    $script:NodeHotRects.Clear()

    foreach ($kv in $script:DebugState.Layout.Nodes.GetEnumerator()) {
        $n = $kv.Value
        $id = [string]$n.Id
        $left = ($n.X - ($n.W / 2.0)) * $sx
        $top = ($graphH - ($n.Y + ($n.H / 2.0))) * $sy
        $w = $n.W * $sx
        $h = $n.H * $sy

        $script:NodeRectsDip[$id] = [PSCustomObject]@{ Left = $left; Top = $top; Width = $w; Height = $h }

        $r = New-Object System.Windows.Shapes.Rectangle
        $r.Fill = [System.Windows.Media.Brushes]::Transparent
        $r.StrokeThickness = 0
        $r.ToolTip = "Node $id`n---`n$($n.Label)"
        $r.Width = $w
        $r.Height = $h
        [System.Windows.Controls.Canvas]::SetLeft($r, $left)
        [System.Windows.Controls.Canvas]::SetTop($r, $top)
        [System.Windows.Controls.Canvas]::SetZIndex($r, 10)
        $r.Add_MouseEnter({ $this.StrokeThickness = 1; $this.Stroke = [System.Windows.Media.Brushes]::DodgerBlue })
        $r.Add_MouseLeave({ $this.StrokeThickness = 0 })
        $graphOverlay.Children.Add($r) | Out-Null
        $script:NodeHotRects[$id] = $r
    }
}

function Update-Highlight {
    param([int]$NodeId)
    if ($NodeId -le 0) { $highlightRect.Visibility = 'Collapsed'; return }
    $key = [string]$NodeId
    if (-not $script:NodeRectsDip.ContainsKey($key)) { $highlightRect.Visibility = 'Collapsed'; return }
    $r = $script:NodeRectsDip[$key]
    $highlightRect.Width = $r.Width
    $highlightRect.Height = $r.Height
    [System.Windows.Controls.Canvas]::SetLeft($highlightRect, $r.Left)
    [System.Windows.Controls.Canvas]::SetTop($highlightRect, $r.Top)
    $highlightRect.Visibility = 'Visible'
}

function Get-GraphSourceSizeDip {
    if (-not $graphImage.Source) { return $null }
    $w = [double]$graphImage.Source.Width
    $h = [double]$graphImage.Source.Height
    if ($w -le 0 -or $h -le 0) {
        if ($graphImage.Source.PSObject.Properties['PixelWidth'] -and $graphImage.Source.PSObject.Properties['PixelHeight']) {
            $w = [double]$graphImage.Source.PixelWidth
            $h = [double]$graphImage.Source.PixelHeight
        }
    }
    if ($w -le 0 -or $h -le 0) { return $null }
    return [PSCustomObject]@{ Width = $w; Height = $h }
}

function Apply-GraphZoom {
    $size = Get-GraphSourceSizeDip
    if (-not $size) { return }
    $targetW = [Math]::Max(1.0, $size.Width * $script:GraphZoom)
    $targetH = [Math]::Max(1.0, $size.Height * $script:GraphZoom)
    $graphImage.Width = $targetW
    $graphImage.Height = $targetH
    $graphContainer.Width = $targetW
    $graphContainer.Height = $targetH
    $graphOverlay.Width = $targetW
    $graphOverlay.Height = $targetH
    Rebuild-GraphHotspots
    $nid = if ($script:DebugState.Session.CurrentNode) {
        Get-GraphNodeIdForDisplay -Context $script:DebugState.Session.Context -Node $script:DebugState.Session.CurrentNode
    } else { 0 }
    Update-Highlight -NodeId $nid
}

function Set-GraphZoom {
    param(
        [Parameter(Mandatory)][double]$Zoom,
        [switch]$FromSlider
    )

    if ($Zoom -lt 0.2) { $Zoom = 0.2 }
    if ($Zoom -gt 3.0) { $Zoom = 3.0 }
    $script:GraphZoom = $Zoom
    if (-not $FromSlider) {
        $script:SyncingZoom = $true
        try { $sldZoom.Value = $Zoom * 100.0 } finally { $script:SyncingZoom = $false }
    }
    $txtZoomValue.Text = ('{0:0}%' -f ($script:GraphZoom * 100.0))
    Apply-GraphZoom
}

function Get-PreviewContextSignature {
    param([Parameter(Mandatory)][hashtable]$Context)

    $recCount = 0
    $valCount = 0
    $varRecCount = 0
    $varValCount = 0
    $dynRecCount = 0
    $runtimeBlockCount = 0
    $visitedCount = 0
    $totalVisits = 0
    if ($Context.ResolvableResults) {
        $recCount = [int]$Context.ResolvableResults.Count
        foreach ($rec in @($Context.ResolvableResults.Values)) {
            if ($rec -and $rec.Values) {
                $valCount += @($rec.Values).Count
            }
        }
    }
    if ($Context.VariableReadResults) {
        $varRecCount = [int]$Context.VariableReadResults.Count
        foreach ($rec in @($Context.VariableReadResults.Values)) {
            if ($rec -and $rec.Values) {
                $varValCount += @($rec.Values).Count
            }
        }
    }
    if ($Context.DynamicInvokeResults) {
        $dynRecCount = [int]$Context.DynamicInvokeResults.Count
    }
    if ($Context.ContainsKey('RuntimeSubgraphs') -and $Context.RuntimeSubgraphs) {
        $runtimeBlockCount = [int]$Context.RuntimeSubgraphs.Count
    }
    if ($Context.VisitedNodes) {
        $visitedCount = [int]$Context.VisitedNodes.Count
    }
    if ($Context.ContainsKey('TotalVisits')) {
        $totalVisits = [int]$Context.TotalVisits
    }
    return "$recCount|$valCount|$varRecCount|$varValCount|$dynRecCount|$runtimeBlockCount|$visitedCount|$totalVisits"
}
function Update-StatusBar {
    param([string]$Suffix)
    $sessionNow = $script:DebugState.Session
    $runtimeCount = 0
    if ($sessionNow.Context.ContainsKey('RuntimeSubgraphs') -and $sessionNow.Context.RuntimeSubgraphs) {
        $runtimeCount = [int]$sessionNow.Context.RuntimeSubgraphs.Count
    }
    $base = L 'status.base' @($script:DebugState.ScriptPath, $script:DebugState.Steps.Count, $sessionNow.Context.TotalVisits, $runtimeCount, $sessionNow.IsCompleted)
    if ($script:DebugState.HoldPendingNextNodeId) {
        $base = L 'status.hold' @($base, $script:DebugState.HoldAfterNodeId, $script:DebugState.HoldPendingNextNodeId)
    }
    if ([string]::IsNullOrWhiteSpace($Suffix)) {
        $txtStatus.Text = $base
    } else {
        $txtStatus.Text = "$base | $Suffix"
    }
}

function Clear-HoldState {
    $script:DebugState.HoldPendingNextNodeId = $null
    $script:DebugState.HoldAfterNodeId = $null
}

function Try-AdvanceFromHold {
    if (-not $script:DebugState.HoldPendingNextNodeId) { return $false }

    $toId = [int]$script:DebugState.HoldPendingNextNodeId
    $nextNode = Resolve-CFGNodeValue -CFG $script:DebugState.Cfg -Value (Get-NodeById -CFG $script:DebugState.Cfg -Id $toId)
    if ($null -eq $nextNode) {
        Clear-HoldState
        return $false
    }
    $script:DebugState.Session.CurrentNode = $nextNode
    Clear-HoldState
    return $true
}

function Try-EnterHoldAfterStep {
    param([array]$Records)

    if (-not $Records -or $Records.Count -eq 0) { return $false }
    if ($script:DebugState.HoldPendingNextNodeId) { return $false }
    $sessionCurrentNode = Resolve-CFGNodeValue -CFG $script:DebugState.Cfg -Value $script:DebugState.Session.CurrentNode
    $script:DebugState.Session.CurrentNode = $sessionCurrentNode
    if (-not $sessionCurrentNode) { return $false }

    $executed = @($Records | Where-Object { $_.Executed -and (-not $_.AutoPassed) })
    if ($executed.Count -eq 0) { return $false }
    $lastExecuted = $executed[$executed.Count - 1]
    $nodeId = [int]$lastExecuted.NodeId

    if (-not $script:DebugState.Preview -or -not $script:DebugState.Preview.Candidates) { return $false }
    $cands = @($script:DebugState.Preview.Candidates | Where-Object { [int]$_.NodeId -eq $nodeId })
    if ($cands.Count -le 0) { return $false }

    $nextNode = $sessionCurrentNode
    if ($null -eq $nextNode) { return $false }

    $holdNode = Resolve-CFGNodeValue -CFG $script:DebugState.Cfg -Value (Get-NodeById -CFG $script:DebugState.Cfg -Id $nodeId)
    if ($null -eq $holdNode) { return $false }

    $script:DebugState.HoldPendingNextNodeId = [int]$nextNode.Id
    $script:DebugState.HoldAfterNodeId = $nodeId
    $script:DebugState.Session.CurrentNode = $holdNode
    return $true
}

function Update-PreviewUi {
    param([switch]$Force)

    $ctxSig = Get-PreviewContextSignature -Context $script:DebugState.Session.Context
    $selVer = [int]$script:DebugState.SelectionVersion
    $needRebuild = $Force `
        -or ($null -eq $script:DebugState.Preview) `
        -or ($ctxSig -ne [string]$script:DebugState.LastPreviewContextSig) `
        -or ($selVer -ne [int]$script:DebugState.LastPreviewSelectionVersion)

    if ($needRebuild) {
        $oldPreview = $script:DebugState.Preview

        $newPreview = Build-DebugPreview -Context $script:DebugState.Session.Context -ScriptText $script:DebugState.OriginalText -Strategy $OverlapStrategy -ManualSelection $script:DebugState.UserSelection

        $oldChangedMap = @{}
        $oldSelectedMap = @{}
        if ($oldPreview -and $oldPreview.Candidates) {
            foreach ($oc in @($oldPreview.Candidates)) {
                $oldChangedMap[[string]$oc.Key] = [bool]$oc.IsValueChanged
                $oldSelectedMap[[string]$oc.Key] = [bool]$oc.IsSelected
            }
        }

        $autoUnchecked = @()
        foreach ($c in @($newPreview.Candidates)) {
            if (-not $c.IsSimpleVariable) { continue }
            if (-not $c.IsValueChanged) { continue }

            $k = [string]$c.Key
            $wasChanged = $false
            if ($oldChangedMap.ContainsKey($k)) { $wasChanged = [bool]$oldChangedMap[$k] }
            if ($wasChanged) { continue }

            $wasSelected = $false
            if ($oldSelectedMap.ContainsKey($k)) { $wasSelected = [bool]$oldSelectedMap[$k] }
            if ($wasSelected) {
                $script:DebugState.UserSelection[$k] = $false
                $autoUnchecked += $c
            }
        }

        if ($autoUnchecked.Count -gt 0) {
            $script:DebugState.SelectionVersion = [int]$script:DebugState.SelectionVersion + 1
            $selVer = [int]$script:DebugState.SelectionVersion
            $newPreview = Build-DebugPreview -Context $script:DebugState.Session.Context -ScriptText $script:DebugState.OriginalText -Strategy $OverlapStrategy -ManualSelection $script:DebugState.UserSelection

            $names = @($autoUnchecked | ForEach-Object {
                    if ([string]::IsNullOrWhiteSpace([string]$_.VariableName)) {
                        '$' + [string]$_.Original
                    } else {
                        '$' + [string]$_.VariableName
                    }
                } | Select-Object -Unique)
            if ($names.Count -gt 0) {
                $script:DebugState.LastAutoUncheckMessage = L 'preview.auto_uncheck_named' @($names -join ', ')
            } else {
                $script:DebugState.LastAutoUncheckMessage = L 'preview.auto_uncheck_generic'
            }
        } else {
            $script:DebugState.LastAutoUncheckMessage = $null
        }

        $script:DebugState.Preview = $newPreview
        $script:DebugState.LastPreviewContextSig = $ctxSig
        $script:DebugState.LastPreviewSelectionVersion = $selVer
        $script:DebugState.PreviewStamp = [int]$script:DebugState.PreviewStamp + 1
        $script:DebugState.NodeRowsCache = @{}
    }

    $p = $script:DebugState.Preview
    $manualRules = if ($script:DebugState.UserSelection) { @($script:DebugState.UserSelection.Keys).Count } else { 0 }
    $changedVars = @($p.Candidates | Where-Object { $_.IsSimpleVariable -and $_.IsValueChanged }).Count
    $staticHigh = @($p.Candidates | Where-Object { $_.SourceKind -eq 'Static' -and $_.Confidence -eq 'High' }).Count
    $staticLow = @($p.Candidates | Where-Object { $_.SourceKind -eq 'Static' -and $_.Confidence -eq 'Low' }).Count
    $summary = L 'preview.summary' @($p.Candidates.Count, $p.Selected.Count, $p.Skipped.Count, $staticHigh, $staticLow, $changedVars, $OverlapStrategy, $manualRules)
    if ($staticLow -gt 0) {
        $summary = L 'preview.low_conf_note' @($summary)
    }
    $txtPreviewSummary.Text = $summary
    $txtRebuiltPreview.Text = [string]$p.Rebuilt
}

function Update-DynamicSubgraphUi {
    $currentNode = Resolve-CFGNodeValue -CFG $script:DebugState.Session.Context.CFG -Value $script:DebugState.Session.CurrentNode
    $script:DebugState.Session.CurrentNode = $currentNode
    $rows = Build-RuntimeSubgraphRows -Context $script:DebugState.Session.Context -CurrentNode $currentNode
    $dynamicGrid.ItemsSource = @($rows)

    if (-not $rows -or $rows.Count -eq 0) {
        $txtDynamicSummary.Text = L 'dynamic.none_summary'
        $txtDynamicDetail.Text = L 'dynamic.none_detail'
        $script:DebugState.SelectedRuntimeBlockName = $null
        return
    }

    $currentBlockName = $null
    if ($currentNode -and $currentNode.PSObject.Properties['RuntimeBlockName']) {
        $currentBlockName = [string]$currentNode.RuntimeBlockName
    }

    $targetRow = $null
    if (-not [string]::IsNullOrWhiteSpace($currentBlockName)) {
        $targetRow = @($rows | Where-Object { [string]$_.BlockName -eq $currentBlockName } | Select-Object -First 1)
    }
    if (-not $targetRow -and -not [string]::IsNullOrWhiteSpace([string]$script:DebugState.SelectedRuntimeBlockName)) {
        $targetRow = @($rows | Where-Object { [string]$_.BlockName -eq [string]$script:DebugState.SelectedRuntimeBlockName } | Select-Object -First 1)
    }
    if (-not $targetRow) {
        $targetRow = @($rows | Select-Object -Last 1)
    }
    if ($targetRow -and $targetRow.Count -gt 0) {
        $targetRow = $targetRow[0]
        $script:SyncingDynamicSelection = $true
        try {
            $dynamicGrid.SelectedItem = $targetRow
        } finally {
            $script:SyncingDynamicSelection = $false
        }
        $script:DebugState.SelectedRuntimeBlockName = [string]$targetRow.BlockName
        $txtDynamicDetail.Text = Get-RuntimeSubgraphDetailText -Context $script:DebugState.Session.Context -Row $targetRow
    } else {
        $script:SyncingDynamicSelection = $true
        try {
            $dynamicGrid.SelectedItem = $null
        } finally {
            $script:SyncingDynamicSelection = $false
        }
        $txtDynamicDetail.Text = ''
    }

    $activeCount = @($rows | Where-Object { $_.StatusKey -in @('Current', 'Open') }).Count
    $hostDisplay = if ([string]::IsNullOrWhiteSpace([string]$script:CurrentHostDisplay)) { '' } else { [string]$script:CurrentHostDisplay }
    $txtDynamicSummary.Text = L 'dynamic.summary' @($rows.Count, $activeCount, $hostDisplay)
}

function Set-CandidateSelection {
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][bool]$Selected
    )

    if (-not $script:DebugState.UserSelection) { $script:DebugState.UserSelection = @{} }

    $changed = $false
    if (-not $script:DebugState.UserSelection.ContainsKey($Key) -or ([bool]$script:DebugState.UserSelection[$Key] -ne $Selected)) {
        $script:DebugState.UserSelection[$Key] = $Selected
        $changed = $true
    }

    if ($Selected -and $script:DebugState.Preview -and $script:DebugState.Preview.Candidates) {
        $target = @($script:DebugState.Preview.Candidates | Where-Object { [string]$_.Key -eq $Key } | Select-Object -First 1)
        if ($target -and $target.Count -gt 0) {
            $t = $target[0]
            foreach ($other in @($script:DebugState.Preview.Candidates | Where-Object { $_.IsSelected -and [string]$_.Key -ne $Key })) {
                if (Test-ReplacementOverlap -A $t -B $other) {
                    $otherKey = [string]$other.Key
                    if (-not $script:DebugState.UserSelection.ContainsKey($otherKey) -or [bool]$script:DebugState.UserSelection[$otherKey]) {
                        $script:DebugState.UserSelection[$otherKey] = $false
                        $changed = $true
                    }
                }
            }
        }
    }

    if ($changed) {
        $script:DebugState.SelectionVersion = [int]$script:DebugState.SelectionVersion + 1
    }

    return $changed
}

function Update-NodeReplacementUi {
    param($CurrentNode)

    $CurrentNode = Resolve-CFGNodeValue -CFG $script:DebugState.Session.Context.CFG -Value $CurrentNode
    if ($null -eq $CurrentNode -or -not $script:DebugState.Preview) {
        $txtNodeReplaceSummary.Text = L 'replace.none'
        $script:SyncingNodeSelection = $true
        try { $nodeReplaceGrid.ItemsSource = @() } finally { $script:SyncingNodeSelection = $false }
        return
    }

    $ownerNodeId = Get-ReplacementOwnerNodeId -Context $script:DebugState.Session.Context -Node $CurrentNode
    $isRuntimeNode = ($ownerNodeId -ne [int]$CurrentNode.Id)
    $cacheKey = "$([int]$script:DebugState.PreviewStamp):$ownerNodeId"
    if ($script:DebugState.NodeRowsCache.ContainsKey($cacheKey)) {
        $nodeItems = @($script:DebugState.NodeRowsCache[$cacheKey])
    } else {
        $nodeItems = @($script:DebugState.Preview.Candidates |
                Where-Object { [int]$_.NodeId -eq $ownerNodeId } |
                Sort-Object StartOffset, EndOffset |
                ForEach-Object {
                    [PSCustomObject]@{
                        Key         = [string]$_.Key
                        IsSelected  = [bool]$_.IsSelected
                        StartOffset = $_.StartOffset
                        EndOffset   = $_.EndOffset
                        Type        = $_.Type
                        SourceLabel = if ([string]$_.SourceKind -eq 'Static') { L 'replace.source_static' } else { L 'replace.source_dynamic' }
                        ConfidenceLabel = switch ([string]$_.Confidence) {
                            'High' { L 'replace.confidence.high' }
                            'Low' { L 'replace.confidence.low' }
                            default { '' }
                        }
                        VariableName = if ([string]::IsNullOrWhiteSpace([string]$_.VariableName)) { '' } else { [string]$_.VariableName }
                        IsSimpleVariable = [bool]$_.IsSimpleVariable
                        IsValueChanged = [bool]$_.IsValueChanged
                        ChangedFlag = if ([bool]$_.IsValueChanged) { L 'replace.changed_flag' } else { '' }
                        Original    = [string]$_.Original
                        Replacement = [string]$_.Replacement
                    }
                })
        $script:DebugState.NodeRowsCache[$cacheKey] = @($nodeItems)
    }

    $selectedCount = @($nodeItems | Where-Object { $_.IsSelected }).Count
    $changedRows = @($nodeItems | Where-Object { $_.IsSimpleVariable -and $_.IsValueChanged })
    $changedNames = @($changedRows | ForEach-Object {
            if ([string]::IsNullOrWhiteSpace([string]$_.VariableName)) { [string]$_.Original } else { '$' + [string]$_.VariableName }
        } | Select-Object -Unique)
    $staticHigh = @($script:DebugState.Preview.Candidates | Where-Object { [int]$_.NodeId -eq $ownerNodeId -and $_.SourceKind -eq 'Static' -and $_.Confidence -eq 'High' }).Count
    $staticLow = @($script:DebugState.Preview.Candidates | Where-Object { [int]$_.NodeId -eq $ownerNodeId -and $_.SourceKind -eq 'Static' -and $_.Confidence -eq 'Low' }).Count
    $summary = L 'replace.summary' @($nodeItems.Count, $selectedCount, $staticHigh, $staticLow)
    if ($isRuntimeNode) {
        $summary = L 'replace.summary_source_node' @($summary, $ownerNodeId)
    }
    if ($changedRows.Count -gt 0) {
        $summary = L 'replace.summary_changed' @($summary, ($changedNames -join ', '))
    }
    if ($staticLow -gt 0) {
        $summary = L 'replace.summary_low_conf' @($summary)
    }
    $summary = L 'replace.summary_note' @($summary)
    $txtNodeReplaceSummary.Text = $summary

    $script:SyncingNodeSelection = $true
    try {
        $nodeReplaceGrid.ItemsSource = $nodeItems
    } finally {
        $script:SyncingNodeSelection = $false
    }
}
function Request-SelectionRefresh {
    if ($script:SelectionRefreshQueued) { return }
    if ($null -eq $window -or $null -eq $window.Dispatcher -or $window.Dispatcher.HasShutdownStarted -or $window.Dispatcher.HasShutdownFinished) {
        $script:SelectionRefreshQueued = $false
        return
    }
    $script:SelectionRefreshQueued = $true
    $null = $window.Dispatcher.InvokeAsync(
        [Action]{
            try {
                $script:SelectionRefreshQueued = $false
                if (-not $script:DebugState -or -not $script:DebugState.Session) { return }
                Update-PreviewUi
                Update-NodeReplacementUi -CurrentNode $script:DebugState.Session.CurrentNode
                Update-StatusBar -Suffix (L 'replace.selection_updated')
            } catch {
                Write-DebugUiException -Exception $_ -ActionName 'SelectionRefresh'
            }
        },
        [System.Windows.Threading.DispatcherPriority]::Background
    )
}

function Refresh-VarGrid {
    $showAdvanced = ($null -ne $chkVarAdvanced -and $chkVarAdvanced.IsChecked)
    $rows = Get-CFGVariableStack -Session $script:DebugState.Session -IncludeAdvancedInternal:$showAdvanced
    $varGrid.ItemsSource = @($rows)
}

function Append-StepRecords {
    param([array]$Records)
    foreach ($r in @($Records)) {
        $nextText = if ($r.NextNodeId) {
            if ([string]::IsNullOrWhiteSpace([string]$r.NextEdgeLabel)) {
                L 'step.next_plain' @($r.NextNodeId)
            } else {
                L 'step.next_labeled' @($r.NextEdgeLabel, $r.NextNodeId)
            }
        } else {
            ''
        }
        $row = [PSCustomObject]@{
            Step     = $r.Step
            NodeId   = $r.NodeId
            Scope    = if ($r.PSObject.Properties['RuntimeBlockName'] -and -not [string]::IsNullOrWhiteSpace([string]$r.RuntimeBlockName)) { L 'step.scope.runtime' } else { L 'step.scope.static' }
            NodeType = $r.NodeType
            Status   = $r.Status
            NextText = $nextText
        }
        $null = $script:DebugState.Steps.Add($row)
    }
    $stepsGrid.ItemsSource = @($script:DebugState.Steps)
    if ($script:DebugState.Steps.Count -gt 0) {
        $stepsGrid.SelectedIndex = $script:DebugState.Steps.Count - 1
        $stepsGrid.ScrollIntoView($stepsGrid.SelectedItem) | Out-Null
    }
}

function Update-CurrentNodeUi {
    $sessionNow = $script:DebugState.Session
    $graphRefreshed = Refresh-LiveGraphArtifacts -Reason 'UpdateCurrentNodeUi'
    $curNode = Resolve-CFGNodeValue -CFG $sessionNow.Context.CFG -Value $sessionNow.CurrentNode
    $sessionNow.CurrentNode = $curNode
    if ($sessionNow.IsCompleted -or $null -eq $curNode) {
        $txtNodeHeader.Text = L 'node.completed'
        $txtNodeMeta.Text = L 'node.stop_reason' @($sessionNow.StopReason)
        $txtNextEdge.Text = L 'node.next.none'
        $txtNodeCode.Text = ""
        Update-NodeReplacementUi -CurrentNode $null
        Update-Highlight -NodeId 0
    } else {
        $runtimeInfo = Get-RuntimeSubgraphInfoForNode -Context $sessionNow.Context -Node $curNode
        if ($runtimeInfo) {
            $txtNodeHeader.Text = L 'node.header.runtime' @($curNode.Id, $curNode.Type, $runtimeInfo.BlockName)
        } else {
            $txtNodeHeader.Text = L 'node.header.static' @($curNode.Id, $curNode.Type)
        }
        $holdHere = ($script:DebugState.HoldPendingNextNodeId -and ([int]$script:DebugState.HoldAfterNodeId -eq [int]$curNode.Id))
        if ($holdHere) {
            $txtNodeMeta.Text = L 'node.meta.hold'
        } else {
            $txtNodeMeta.Text = L 'node.meta.pending'
        }
        if ($runtimeInfo) {
            $metaSuffix = L 'node.meta.runtime.base' @($runtimeInfo.BlockName)
            if ($runtimeInfo.CallerNodeId) {
                $metaSuffix = L 'node.meta.runtime.caller' @($metaSuffix, $runtimeInfo.CallerNodeId)
            } else {
                $metaSuffix = L 'node.meta.runtime.no_caller' @($metaSuffix)
            }
            if ($runtimeInfo.ArgumentValue) {
                $metaSuffix = L 'node.meta.runtime.code' @($metaSuffix, (ConvertTo-PreviewText -Text ([string]$runtimeInfo.ArgumentValue) -MaxLen 120))
            }
            $txtNodeMeta.Text += $metaSuffix
        }
        $dynamicRecord = @($sessionNow.Context.DynamicInvokeResults | Where-Object { [int]$_.NodeId -eq [int]$curNode.Id } | Select-Object -Last 1)
        $dynamicStopReason = if ($dynamicRecord -is [hashtable]) { [string]$dynamicRecord['StopReason'] } elseif ($dynamicRecord) { [string]$dynamicRecord.StopReason } else { $null }
        $dynamicStopMessage = if ($dynamicRecord -is [hashtable]) { [string]$dynamicRecord['StopMessage'] } elseif ($dynamicRecord) { [string]$dynamicRecord.StopMessage } else { $null }
        if (-not [string]::IsNullOrWhiteSpace($dynamicStopReason)) {
            $stopText = L 'node.meta.runtime_stop' @($dynamicStopReason)
            if (-not [string]::IsNullOrWhiteSpace($dynamicStopMessage)) {
                $localizedStopMessage = Resolve-LocalizedDiagnosticMessage -Language $script:UiLanguage -Reason $dynamicStopReason -Message $dynamicStopMessage
                $stopText = L 'node.meta.runtime_stop_message' @($stopText, $localizedStopMessage)
            }
            $txtNodeMeta.Text += $stopText
        }
        $txtNodeCode.Text = [string]$curNode.Text

        if ($holdHere) {
            $toId = [int]$script:DebugState.HoldPendingNextNodeId
            $edgeLabel = $null
            if ($toId -gt 0) {
                $edgeLabel = Get-CFGEdgeLabel -CFG $script:DebugState.Cfg -FromNodeId ([int]$curNode.Id) -ToNodeId $toId
            }
            if ([string]::IsNullOrWhiteSpace([string]$edgeLabel)) {
                $txtNextEdge.Text = L 'node.next.advance_plain' @($toId)
            } else {
                $txtNextEdge.Text = L 'node.next.advance_labeled' @($edgeLabel, $toId)
            }
        } else {
            $previewEdge = Get-CFGNextEdgePreview -Session $sessionNow
            if ($previewEdge.Error) {
                $txtNextEdge.Text = L 'node.next.predict_error' @($previewEdge.Error)
            } elseif ($previewEdge.HasPreview) {
                if ($null -ne $previewEdge.PredictedCondition) {
                    $txtNextEdge.Text = L 'node.next.predict_with_condition' @($previewEdge.EdgeLabel, $previewEdge.ToNodeId, $previewEdge.PredictedCondition)
                } else {
                    $txtNextEdge.Text = L 'node.next.predict' @($previewEdge.EdgeLabel, $previewEdge.ToNodeId)
                }
            } else {
                $txtNextEdge.Text = L 'node.next.predict_none'
            }
        }
        Update-NodeReplacementUi -CurrentNode $curNode
        $graphNodeId = Get-GraphNodeIdForDisplay -Context $sessionNow.Context -Node $curNode
        Update-Highlight -NodeId $graphNodeId
    }

    $suffix = $null
    if (-not [string]::IsNullOrWhiteSpace([string]$script:DebugState.LastAutoUncheckMessage)) {
        $suffix = [string]$script:DebugState.LastAutoUncheckMessage
    }
    if ($graphRefreshed) {
        if ([string]::IsNullOrWhiteSpace([string]$suffix)) {
            $suffix = L 'status.graph_refreshed'
        } else {
            $suffix = "$suffix | $(L 'status.graph_refreshed')"
        }
    }
    Update-StatusBar -Suffix $suffix
    Update-DynamicSubgraphUi
    Update-ToolbarState
}

function Update-ToolbarState {
    $sessionNow = if ($script:DebugState) { $script:DebugState.Session } else { $null }
    $isBusy = ($script:DebugState -and $script:DebugState.IsRunAllActive -eq $true)
    $isCompleted = if ($sessionNow) { [bool]$sessionNow.IsCompleted } else { $true }
    $hasSession = ($null -ne $sessionNow)

    $btnNext.IsEnabled = ($hasSession -and (-not $isCompleted) -and (-not $isBusy))
    $btnRunAll.IsEnabled = ($hasSession -and (-not $isCompleted) -and (-not $isBusy))
    $btnReset.IsEnabled = $hasSession
    $btnExport.IsEnabled = ($hasSession -and ($isCompleted -or (-not $isBusy)))
}

function Queue-RunAllFinalizeUi {
    if ($null -eq $window -or $null -eq $window.Dispatcher -or $window.Dispatcher.HasShutdownStarted -or $window.Dispatcher.HasShutdownFinished) {
        return
    }

    $null = $window.Dispatcher.InvokeAsync(
        [Action]{
            try {
                if (-not $script:DebugState -or -not $script:DebugState.Session) { return }
                Refresh-VarGrid
                Update-PreviewUi
                Update-CurrentNodeUi
            } catch {
                Write-DebugUiException -Exception $_ -ActionName 'BtnRunAllFinalize'
            }
        },
        [System.Windows.Threading.DispatcherPriority]::Background
    )
}

function Stop-RunAllExecution {
    if ($script:RunAllTimer) {
        try {
            $script:RunAllTimer.Stop()
        } catch {
        }
        $script:RunAllTimer = $null
    }

    if ($script:DebugState) {
        $script:DebugState.IsRunAllActive = $false
    }

    Update-ToolbarState
}

function Complete-RunAllExecution {
    Stop-RunAllExecution
    Queue-RunAllFinalizeUi
}

function Start-RunAllExecution {
    if (-not $script:DebugState -or -not $script:DebugState.Session) { return }
    if ($script:DebugState.IsRunAllActive) { return }

    if ($script:DebugState.HoldPendingNextNodeId) {
        $null = Try-AdvanceFromHold
    }

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(1)
    $timer.Add_Tick({
        try {
            if (-not $script:DebugState -or -not $script:DebugState.Session) {
                Stop-RunAllExecution
                return
            }

            if ($script:DebugState.Session.IsCompleted) {
                Complete-RunAllExecution
                return
            }

            $batchSize = 40
            $batchIndex = 0
            while ($batchIndex -lt $batchSize -and -not $script:DebugState.Session.IsCompleted) {
                $res = Invoke-CFGStep -Session $script:DebugState.Session
                Append-StepRecords -Records $res.Records
                $batchIndex++
            }

            if ($script:DebugState.Session.IsCompleted) {
                Complete-RunAllExecution
            } else {
                Update-CurrentNodeUi
            }
        } catch {
            Stop-RunAllExecution
            Write-DebugUiException -Exception $_ -ActionName 'BtnRunAll'
            try {
                if ($script:DebugState -and $script:DebugState.Session) {
                    Update-CurrentNodeUi
                }
            } catch {
            }
        }
    })

    $script:RunAllTimer = $timer
    $script:DebugState.IsRunAllActive = $true
    Update-ToolbarState
    Update-StatusBar -Suffix $null
    $timer.Start()
}

function Reset-DebugSession {
    Stop-RunAllExecution
    if ($script:DebugState.Session) {
        Close-CFGExecutionSession -Session $script:DebugState.Session
    }

    $freshCfg = Get-ScriptControlFlow -ScriptPath $script:DebugState.ScriptPath
    if (-not $freshCfg) {
        throw (L 'reset.cfg_failed' @($script:DebugState.ScriptPath))
    }

    Clear-HoldState
    $script:DebugState.Cfg = $freshCfg
    $script:DebugState.Layout = $null
    $script:DebugState.OriginalText = Get-FullScriptTextFromFile -Path $script:DebugState.ScriptPath
    $script:DebugState.Session = New-CFGExecutionSession -CFG $script:DebugState.Cfg -LogPath $script:DebugState.LogPath -MaxIterations $MaxIterations -MaxTotalNodes $MaxTotalNodes -DynamicTimeBudgetMs $DynamicTimeBudgetMs
    $script:DebugState.Steps = New-Object System.Collections.ArrayList
    $script:DebugState.UserSelection = @{}
    $script:DebugState.SelectionVersion = 0
    $script:DebugState.LastPreviewContextSig = ''
    $script:DebugState.LastPreviewSelectionVersion = -1
    $script:DebugState.PreviewStamp = 0
    $script:DebugState.NodeRowsCache = @{}
    $script:DebugState.LastAutoUncheckMessage = $null
    $script:DebugState.SelectedRuntimeBlockName = $null
    $script:DebugState.LastGraphSignature = ''
    $script:DebugState.IsRunAllActive = $false
    $script:DebugState.Preview = $null
    $stepsGrid.ItemsSource = @()
    $txtVarName.Text = ""
    $txtVarExpr.Text = ""
    Refresh-VarGrid
    Refresh-LiveGraphArtifacts -Force -Reason 'Reset-DebugSession' | Out-Null
    Update-PreviewUi -Force
    Update-CurrentNodeUi
}

function Export-DebugResult {
    $p = Build-DebugPreview -Context $script:DebugState.Session.Context -ScriptText $script:DebugState.OriginalText -Strategy $OverlapStrategy -ManualSelection $script:DebugState.UserSelection
    Set-Content -LiteralPath $script:DebugState.OutPath -Value $p.Rebuilt -Encoding UTF8

    $staticHigh = @($p.Candidates | Where-Object { $_.SourceKind -eq 'Static' -and $_.Confidence -eq 'High' }).Count
    $staticLow = @($p.Candidates | Where-Object { $_.SourceKind -eq 'Static' -and $_.Confidence -eq 'Low' }).Count

    $report = [ordered]@{
        Timestamp       = (Get-Date).ToString('o')
        ScriptPath      = $script:DebugState.ScriptPath
        WorkDir         = $script:DebugState.WorkDir
        OutPath         = $script:DebugState.OutPath
        LogPath         = $script:DebugState.LogPath
        DotPath         = $script:DebugState.DotPath
        PngPath         = $script:DebugState.PngPath
        OverlapStrategy = $OverlapStrategy
        TotalVisits     = $script:DebugState.Session.Context.TotalVisits
        Steps           = $script:DebugState.Steps.Count
        StopReason      = $script:DebugState.Session.StopReason
        CandidateCount  = $p.Candidates.Count
        SelectedCount   = $p.Selected.Count
        SkippedCount    = $p.Skipped.Count
        RuntimeSubgraphCount = if ($script:DebugState.Session.Context.ContainsKey('RuntimeSubgraphs') -and $script:DebugState.Session.Context.RuntimeSubgraphs) { [int]$script:DebugState.Session.Context.RuntimeSubgraphs.Count } else { 0 }
        StaticHighCount = $staticHigh
        StaticLowCount  = $staticLow
        RuntimeSubgraphs = @(Get-ContextRuntimeSubgraphs -Context $script:DebugState.Session.Context)
        Selected        = @($p.Selected | ForEach-Object {
            [PSCustomObject]@{
                Start             = $_.StartOffset
                End               = $_.EndOffset
                NodeId            = $_.NodeId
                Type              = $_.Type
                Depth             = $_.Depth
                Original          = ConvertTo-PreviewText -Text $_.Original -MaxLen 220
                Replacement       = $_.Replacement
                SourceKind        = $_.SourceKind
                Confidence        = $_.Confidence
                UsedEmptyFallback = $_.UsedEmptyFallback
                DynamicStopReason = if ($_.PSObject.Properties['DynamicStopReason']) { $_.DynamicStopReason } else { $null }
                DynamicStopMessage = if ($_.PSObject.Properties['DynamicStopMessage']) { $_.DynamicStopMessage } else { $null }
                Executed          = $_.Executed
                ResultType        = $_.ResultType
            }
        })
        Skipped = @($p.Skipped)
    }
    $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $script:DebugState.ReportPath -Encoding UTF8

    [System.Windows.MessageBox]::Show(
        (L 'export.success_message' @("`n", $script:DebugState.OutPath, $script:DebugState.ReportPath)),
        (L 'export.success_title'),
        "OK",
        "Information"
    ) | Out-Null
}

function Write-DebugUiException {
    param(
        [Parameter(Mandatory)]$Exception,
        [string]$ActionName = 'UI'
    )

    $detail = New-Object System.Collections.Generic.List[string]
    $detail.Add("Time    : $((Get-Date).ToString('o'))") | Out-Null
    $detail.Add("Action  : $ActionName") | Out-Null
    $detail.Add("Message : $($Exception.Exception.Message)") | Out-Null
    if ($Exception.InvocationInfo) {
        $detail.Add("Script  : $($Exception.InvocationInfo.ScriptName)") | Out-Null
        $detail.Add("Line    : $($Exception.InvocationInfo.ScriptLineNumber)") | Out-Null
        $detail.Add("Offset  : $($Exception.InvocationInfo.OffsetInLine)") | Out-Null
        $detail.Add("Command : $($Exception.InvocationInfo.Line.Trim())") | Out-Null
    }
    if ($Exception.ScriptStackTrace) {
        $detail.Add("Stack   :") | Out-Null
        $detail.Add($Exception.ScriptStackTrace) | Out-Null
    }
    $detail.Add((''.PadLeft(72, '-'))) | Out-Null
    Add-Content -LiteralPath $uiErrorLogPath -Value ($detail -join [Environment]::NewLine) -Encoding UTF8

    $message = L 'error.ui_message' @("`n", $ActionName, $Exception.Exception.Message, $uiErrorLogPath)
    [System.Windows.MessageBox]::Show($message, (L 'error.title'), 'OK', 'Error') | Out-Null
}

function Invoke-DebugUiAction {
    param(
        [Parameter(Mandatory)][string]$ActionName,
        [Parameter(Mandatory)][scriptblock]$Action
    )

    try {
        & $Action
    } catch {
        Write-DebugUiException -Exception $_ -ActionName $ActionName
    }
}
Refresh-LiveGraphArtifacts -Force -Reason 'InitialLoad' | Out-Null
Set-GraphZoom -Zoom 1.0
Refresh-VarGrid
Update-PreviewUi
Update-CurrentNodeUi

$graphImage.Add_Loaded({ Rebuild-GraphHotspots; Update-CurrentNodeUi })
$graphImage.Add_SizeChanged({ Rebuild-GraphHotspots; Update-CurrentNodeUi })

$dynamicGrid.Add_SelectionChanged({
    if ($script:SyncingDynamicSelection) { return }
    $row = $dynamicGrid.SelectedItem
    if ($row) {
        $script:DebugState.SelectedRuntimeBlockName = [string]$row.BlockName
        $txtDynamicDetail.Text = Get-RuntimeSubgraphDetailText -Context $script:DebugState.Session.Context -Row $row
    }
})

$btnNext.Add_Click({
    Invoke-DebugUiAction -ActionName 'BtnNext' -Action {
        if (Try-AdvanceFromHold) {
            Update-CurrentNodeUi
            return
        }

        $res = Invoke-CFGStep -Session $script:DebugState.Session
        Append-StepRecords -Records $res.Records
        Refresh-VarGrid
        Update-PreviewUi
        $held = Try-EnterHoldAfterStep -Records $res.Records
        Update-CurrentNodeUi
        if ($held) {
            Update-StatusBar -Suffix (L 'btn_next_hold')
        }
    }
})

$btnRunAll.Add_Click({
    Invoke-DebugUiAction -ActionName 'BtnRunAll' -Action {
        Start-RunAllExecution
    }
})

$btnReset.Add_Click({ Reset-DebugSession })
$btnExport.Add_Click({ Export-DebugResult })

$nodeReplaceGrid.AddHandler(
    [System.Windows.Controls.Primitives.ToggleButton]::CheckedEvent,
    [System.Windows.RoutedEventHandler]{
        param($sender, $e)
        if ($script:SyncingNodeSelection) { return }
        $origin = $e.OriginalSource
        if ($origin -isnot [System.Windows.Controls.CheckBox]) { return }
        $item = $origin.DataContext
        if (-not $item -or -not $item.PSObject.Properties['Key']) { return }
        $changed = Set-CandidateSelection -Key ([string]$item.Key) -Selected $true
        if ($changed) {
            if ($item.PSObject.Properties['IsValueChanged'] -and [bool]$item.IsValueChanged) {
                $varLabel = if ($item.PSObject.Properties['VariableName'] -and -not [string]::IsNullOrWhiteSpace([string]$item.VariableName)) { '$' + [string]$item.VariableName } else { [string]$item.Original }
                Update-StatusBar -Suffix (L 'var.changed_selected' @($varLabel))
            }
            Request-SelectionRefresh
        }
    },
    $true
)

$nodeReplaceGrid.AddHandler(
    [System.Windows.Controls.Primitives.ToggleButton]::UncheckedEvent,
    [System.Windows.RoutedEventHandler]{
        param($sender, $e)
        if ($script:SyncingNodeSelection) { return }
        $origin = $e.OriginalSource
        if ($origin -isnot [System.Windows.Controls.CheckBox]) { return }
        $item = $origin.DataContext
        if (-not $item -or -not $item.PSObject.Properties['Key']) { return }
        $changed = Set-CandidateSelection -Key ([string]$item.Key) -Selected $false
        if ($changed) { Request-SelectionRefresh }
    },
    $true
)

$btnRefreshVar.Add_Click({ Refresh-VarGrid; Update-CurrentNodeUi })
$chkVarAdvanced.Add_Checked({ Refresh-VarGrid })
$chkVarAdvanced.Add_Unchecked({ Refresh-VarGrid })

$varGrid.Add_SelectionChanged({
    $row = $varGrid.SelectedItem
    if ($row) {
        $txtVarName.Text = [string]$row.ActualName
    }
})

$btnApplyVar.Add_Click({
    $selectedRow = $varGrid.SelectedItem
    $varName = [string]$txtVarName.Text
    if ([string]::IsNullOrWhiteSpace($varName) -and $selectedRow) {
        $varName = [string]$selectedRow.ActualName
    }
    if ([string]::IsNullOrWhiteSpace($varName)) {
        [System.Windows.MessageBox]::Show((L 'var.prompt_select'), (L 'var.prompt_title'), "OK", "Warning") | Out-Null
        return
    }

    $expr = [string]$txtVarExpr.Text
    if ([string]::IsNullOrWhiteSpace($expr)) {
        [System.Windows.MessageBox]::Show((L 'var.prompt_expression'), (L 'var.prompt_title'), "OK", "Warning") | Out-Null
        return
    }
    try {
        $setResult = Set-CFGVariableValue -Session $script:DebugState.Session -VariableName $varName -ValueExpression $expr
        Refresh-VarGrid
        Update-PreviewUi -Force
        Update-CurrentNodeUi
        Update-StatusBar -Suffix (L 'var.set_status' @($setResult.Name, $setResult.ValueText))
    } catch {
        [System.Windows.MessageBox]::Show((L 'var.error_set_failed' @($_.Exception.Message)), (L 'var.error_title'), "OK", "Error") | Out-Null
    }
})

$sldZoom.Add_ValueChanged({
    if ($script:SyncingZoom) { return }
    Set-GraphZoom -Zoom ($sldZoom.Value / 100.0) -FromSlider
})
$graphScroll.Add_PreviewMouseWheel({
    param($sender, $e)
    $ctrl = ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control)
    if (-not $ctrl) { return }
    if ($e.Delta -gt 0) {
        Set-GraphZoom -Zoom ($script:GraphZoom + 0.1)
    } else {
        Set-GraphZoom -Zoom ($script:GraphZoom - 0.1)
    }
    $e.Handled = $true
})
$btnZoomOut.Add_Click({ Set-GraphZoom -Zoom ($script:GraphZoom - 0.1) })
$btnZoomIn.Add_Click({ Set-GraphZoom -Zoom ($script:GraphZoom + 0.1) })
$btnZoomReset.Add_Click({ Set-GraphZoom -Zoom 1.0 })

$window.Add_Closed({
    Stop-RunAllExecution
    if ($script:DebugState.Session) {
        Close-CFGExecutionSession -Session $script:DebugState.Session
    }
})

Set-DebugWindowTitle -Window $window
try {
    $null = $window.ShowDialog()
} catch {
    Write-DebugUiException -Exception $_ -ActionName 'ShowDialog'
    throw
}





