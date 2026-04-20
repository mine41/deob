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

    [int]$GlobalTimeBudgetMs = 120000,

    [int]$DynamicTimeBudgetMs = 15000,

    [bool]$SafeMode = $true,

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

function Get-RemainingTimeBudgetMs {
    param(
        [int]$BudgetMs,
        [System.Diagnostics.Stopwatch]$Stopwatch
    )

    if ($BudgetMs -le 0) { return 0 }
    if ($null -eq $Stopwatch) { return $BudgetMs }

    $remaining = [int]($BudgetMs - $Stopwatch.ElapsedMilliseconds)
    if ($remaining -lt 0) { return 0 }
    return $remaining
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

function Get-ReplacementContextInfoFromScriptText {
    param([Parameter(Mandatory)][string]$ScriptText)

    $result = [PSCustomObject]@{
        ExpandableStringRanges = @()
        CommandNameRangeKeys   = @{}
        CommandNameRanges      = @()
        DynamicPayloadRanges   = @()
        MemberNameRanges       = @()
        CommandTargetAssignmentRanges = @()
    }

    if ([string]::IsNullOrWhiteSpace($ScriptText)) {
        return $result
    }

    try {
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($ScriptText, [ref]$tokens, [ref]$errors)
    } catch {
        return $result
    }

    if (-not $ast) { return $result }

    function Add-UniqueContextRange {
        param(
            [hashtable]$SeenMap,
            [System.Collections.Generic.List[object]]$List,
            [int]$StartOffset,
            [int]$EndOffset
        )

        if ($null -eq $StartOffset -or $null -eq $EndOffset -or $EndOffset -le $StartOffset) {
            return
        }

        $key = "$StartOffset`:$EndOffset"
        if ($SeenMap.ContainsKey($key)) {
            return
        }

        $SeenMap[$key] = $true
        $List.Add([PSCustomObject]@{
                StartOffset = [int]$StartOffset
                EndOffset   = [int]$EndOffset
            }) | Out-Null
    }

    function Get-CommandArgumentAst {
        param([System.Management.Automation.Language.CommandAst]$CommandAst)

        if ($null -eq $CommandAst -or -not $CommandAst.CommandElements) { return $null }

        for ($i = 1; $i -lt $CommandAst.CommandElements.Count; $i++) {
            $elem = $CommandAst.CommandElements[$i]
            if ($elem -is [System.Management.Automation.Language.CommandParameterAst]) {
                if ($elem.Argument) {
                    return $elem.Argument
                }
                continue
            }

            return $elem
        }

        return $null
    }

    $expandableRanges = @()
    $expandableAsts = @($ast.FindAll({
            param($n)
            $n -is [System.Management.Automation.Language.ExpandableStringExpressionAst]
        }, $true))
    foreach ($expandableAst in $expandableAsts) {
        if (-not $expandableAst.Extent) { continue }
        $start = $expandableAst.Extent.StartOffset
        $end = $expandableAst.Extent.EndOffset
        if ($null -eq $start -or $null -eq $end -or $end -le $start) { continue }
        $expandableRanges += [PSCustomObject]@{
            StartOffset = [int]$start
            EndOffset   = [int]$end
        }
    }

    $commandNameRangeKeys = @{}
    $commandNameRanges = [System.Collections.Generic.List[object]]::new()
    $dynamicPayloadRanges = [System.Collections.Generic.List[object]]::new()
    $memberNameRanges = [System.Collections.Generic.List[object]]::new()
    $commandTargetAssignmentRanges = [System.Collections.Generic.List[object]]::new()
    $commandNameRangeSeen = @{}
    $dynamicPayloadRangeSeen = @{}
    $memberNameRangeSeen = @{}
    $commandTargetAssignmentRangeSeen = @{}
    $commandTargetVariableNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $commandAsts = @($ast.FindAll({
            param($n)
            $n -is [System.Management.Automation.Language.CommandAst]
        }, $true))
    foreach ($cmdAst in $commandAsts) {
        if (-not $cmdAst.CommandElements -or $cmdAst.CommandElements.Count -eq 0) { continue }
        $nameAst = $cmdAst.CommandElements[0]
        if (-not $nameAst.Extent) { continue }
        $start = $nameAst.Extent.StartOffset
        $end = $nameAst.Extent.EndOffset
        if ($null -eq $start -or $null -eq $end -or $end -le $start) { continue }
        $commandNameRangeKeys["$start`:$end"] = $true
        Add-UniqueContextRange -SeenMap $commandNameRangeSeen -List $commandNameRanges -StartOffset $start -EndOffset $end

        if (($nameAst -is [System.Management.Automation.Language.VariableExpressionAst]) -and
            ([string]$cmdAst.InvocationOperator) -in @('Ampersand', 'Dot')) {
            $varName = [string]$nameAst.VariablePath.UserPath
            if ($null -ne $nameAst.VariablePath -and $null -ne $nameAst.VariablePath.UserPath) {
                $null = $commandTargetVariableNames.Add($varName)
            }
        }

        $cmdName = $cmdAst.GetCommandName()
        if ($cmdName -in @('Invoke-Expression', 'iex')) {
            $statement = $cmdAst.Parent
            if ($statement -is [System.Management.Automation.Language.PipelineAst]) {
                $pipelineElements = @($statement.PipelineElements)
                for ($i = 0; $i -lt $pipelineElements.Count; $i++) {
                    if ($pipelineElements[$i] -ne $cmdAst) { continue }
                    if ($i -le 0) { break }

                    $payloadStart = $pipelineElements[0].Extent.StartOffset
                    $payloadEnd = $pipelineElements[$i - 1].Extent.EndOffset
                    Add-UniqueContextRange -SeenMap $dynamicPayloadRangeSeen -List $dynamicPayloadRanges -StartOffset $payloadStart -EndOffset $payloadEnd
                    break
                }
            } else {
                $argAst = Get-CommandArgumentAst -CommandAst $cmdAst
                if ($argAst -and $argAst.Extent) {
                    Add-UniqueContextRange -SeenMap $dynamicPayloadRangeSeen -List $dynamicPayloadRanges -StartOffset $argAst.Extent.StartOffset -EndOffset $argAst.Extent.EndOffset
                }
            }
        }

        if (Test-PowerShellHostCommandName -CommandName $cmdName) {
            for ($i = 1; $i -lt $cmdAst.CommandElements.Count; $i++) {
                $elem = $cmdAst.CommandElements[$i]
                if ($elem -isnot [System.Management.Automation.Language.CommandParameterAst]) { continue }

                $paramName = [string]$elem.ParameterName
                if (-not (Test-PowerShellHostParameterPrefix -ParameterName $paramName -CanonicalName 'encodedcommand') -and
                    -not (Test-PowerShellHostParameterPrefix -ParameterName $paramName -CanonicalName 'command')) {
                    continue
                }

                $argAst = $elem.Argument
                if (-not $argAst -and ($i + 1 -lt $cmdAst.CommandElements.Count)) {
                    $i++
                    $argAst = $cmdAst.CommandElements[$i]
                }

                if ($argAst -and $argAst.Extent) {
                    Add-UniqueContextRange -SeenMap $dynamicPayloadRangeSeen -List $dynamicPayloadRanges -StartOffset $argAst.Extent.StartOffset -EndOffset $argAst.Extent.EndOffset
                }
                break
            }
        }
    }

    $memberAsts = @($ast.FindAll({
            param($n)
            ($n -is [System.Management.Automation.Language.MemberExpressionAst]) -or
            ($n -is [System.Management.Automation.Language.InvokeMemberExpressionAst])
        }, $true))
    foreach ($memberAst in $memberAsts) {
        if (-not $memberAst.Member -or -not $memberAst.Member.Extent) { continue }
        Add-UniqueContextRange -SeenMap $memberNameRangeSeen -List $memberNameRanges -StartOffset $memberAst.Member.Extent.StartOffset -EndOffset $memberAst.Member.Extent.EndOffset
    }

    if ($commandTargetVariableNames.Count -gt 0) {
        $assignmentAsts = @($ast.FindAll({
                param($n)
                $n -is [System.Management.Automation.Language.AssignmentStatementAst]
            }, $true))
        foreach ($assignAst in $assignmentAsts) {
            if ($assignAst.Left -isnot [System.Management.Automation.Language.VariableExpressionAst]) { continue }
            if (-not $assignAst.Right -or -not $assignAst.Right.Extent) { continue }

            $assignedVarName = [string]$assignAst.Left.VariablePath.UserPath
            if ($null -eq $assignAst.Left.VariablePath -or $null -eq $assignAst.Left.VariablePath.UserPath) { continue }
            if (-not $commandTargetVariableNames.Contains($assignedVarName)) { continue }

            Add-UniqueContextRange -SeenMap $commandTargetAssignmentRangeSeen -List $commandTargetAssignmentRanges -StartOffset $assignAst.Right.Extent.StartOffset -EndOffset $assignAst.Right.Extent.EndOffset
        }
    }

    $result.ExpandableStringRanges = @($expandableRanges)
    $result.CommandNameRangeKeys = $commandNameRangeKeys
    $result.CommandNameRanges = @($commandNameRanges)
    $result.DynamicPayloadRanges = @($dynamicPayloadRanges)
    $result.MemberNameRanges = @($memberNameRanges)
    $result.CommandTargetAssignmentRanges = @($commandTargetAssignmentRanges)
    return $result
}

function Test-ReplacementWithinRanges {
    param(
        [int]$StartOffset,
        [int]$EndOffset,
        [array]$Ranges
    )

    if (-not $Ranges -or $Ranges.Count -eq 0) { return $false }

    foreach ($range in $Ranges) {
        if (-not $range) { continue }
        $rangeStart = [int]$range.StartOffset
        $rangeEnd = [int]$range.EndOffset
        if ($StartOffset -ge $rangeStart -and $EndOffset -le $rangeEnd) {
            return $true
        }
    }

    return $false
}

function Get-ReplacementRangeKey {
    param(
        [AllowNull()]$StartOffset,
        [AllowNull()]$EndOffset
    )

    if ($null -eq $StartOffset -or $null -eq $EndOffset) { return $null }
    return ("{0}:{1}" -f ([int]$StartOffset), ([int]$EndOffset))
}

function Test-RuntimeGeneratedNode {
    param($Node)

    return ($Node -and $Node.PSObject.Properties['RuntimeGenerated'] -and [bool]$Node.RuntimeGenerated)
}

function Get-DynamicRecordValue {
    param(
        $Record,
        [Parameter(Mandatory)][string]$Name
    )

    if ($null -eq $Record) { return $null }

    if ($Record -is [hashtable]) {
        if ($Record.ContainsKey($Name)) {
            return $Record[$Name]
        }
        return $null
    }

    if ($Record.PSObject.Properties[$Name]) {
        return $Record.$Name
    }

    return $null
}

function Get-DynamicInvokeRecordLookup {
    param([Parameter(Mandatory)][hashtable]$Context)

    if ($Context.ContainsKey('DynamicInvokeRecordLookup') -and $null -ne $Context.DynamicInvokeRecordLookup) {
        return $Context.DynamicInvokeRecordLookup
    }

    $blockByName = @{}
    foreach ($rec in @($Context.DynamicInvokeResults)) {
        if (-not $rec) { continue }
        $blockName = [string](Get-DynamicRecordValue -Record $rec -Name 'BlockName')
        if ([string]::IsNullOrWhiteSpace($blockName)) { continue }
        $blockByName[$blockName] = $rec
    }

    $lookup = [PSCustomObject]@{
        BlockByName = $blockByName
    }

    $Context.DynamicInvokeRecordLookup = $lookup
    return $lookup
}

function Resolve-DynamicInvokeOriginInfo {
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        $Record,
        $Node
    )

    $recordNodeId = Get-DynamicRecordValue -Record $Record -Name 'NodeId'
    if (-not $Node -and $Context.CFG -and $recordNodeId) {
        $Node = Get-NodeById -CFG $Context.CFG -Id ([int]$recordNodeId)
    }

    if (-not $Node) {
        return [PSCustomObject]@{
            Success       = $false
            StartOffset   = $null
            EndOffset     = $null
            NodeId        = $recordNodeId
            RuntimeDepth  = 0
            ViaRuntime    = $false
            FailureReason = 'node_missing'
        }
    }

    $directStart = Get-DynamicRecordValue -Record $Record -Name 'ReplacementStartOffset'
    $directEnd = Get-DynamicRecordValue -Record $Record -Name 'ReplacementEndOffset'

    if (-not (Test-RuntimeGeneratedNode -Node $Node)) {
        $start = if ($null -ne $directStart) { [int]$directStart } else { $Node.TextStartOffset }
        $end = if ($null -ne $directEnd) { [int]$directEnd } else { $Node.TextEndOffset }
        return [PSCustomObject]@{
            Success       = ($null -ne $start -and $null -ne $end)
            StartOffset   = $start
            EndOffset     = $end
            NodeId        = [int]$Node.Id
            RuntimeDepth  = 0
            ViaRuntime    = $false
            FailureReason = if ($null -eq $start -or $null -eq $end) { 'missing_offset' } else { $null }
        }
    }

    $lookup = Get-DynamicInvokeRecordLookup -Context $Context
    $visited = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $currentBlockName = [string](Get-DynamicRecordValue -Record $Record -Name 'BlockName')
    if ([string]::IsNullOrWhiteSpace($currentBlockName) -and $Node.PSObject.Properties['RuntimeBlockName']) {
        $currentBlockName = [string]$Node.RuntimeBlockName
    }

    $depth = 0
    while (-not [string]::IsNullOrWhiteSpace($currentBlockName) -and $visited.Add($currentBlockName)) {
        $depth++
        $runtimeInfo = if ($Context.RuntimeSubgraphs -and $Context.RuntimeSubgraphs.ContainsKey($currentBlockName)) {
            $Context.RuntimeSubgraphs[$currentBlockName]
        } else {
            $null
        }

        $creatorRecord = if ($lookup.BlockByName.ContainsKey($currentBlockName)) {
            $lookup.BlockByName[$currentBlockName]
        } else {
            $null
        }

        $creatorNode = $null
        $creatorNodeId = $null
        $start = $null
        $end = $null

        if ($creatorRecord) {
            $creatorNodeId = Get-DynamicRecordValue -Record $creatorRecord -Name 'NodeId'
            if ($Context.CFG -and $creatorNodeId) {
                $creatorNode = Get-NodeById -CFG $Context.CFG -Id ([int]$creatorNodeId)
            }
            $start = Get-DynamicRecordValue -Record $creatorRecord -Name 'ReplacementStartOffset'
            $end = Get-DynamicRecordValue -Record $creatorRecord -Name 'ReplacementEndOffset'
        }

        $missingCallerNode = $false
        if (-not $creatorNode -and $runtimeInfo -and $Context.CFG -and $runtimeInfo.CallerNodeId) {
            $creatorNodeId = [int]$runtimeInfo.CallerNodeId
            $creatorNode = Get-NodeById -CFG $Context.CFG -Id $creatorNodeId
            if (-not $creatorNode) {
                $missingCallerNode = $true
            }
        }

        if ($null -eq $start -and $runtimeInfo -and $null -ne $runtimeInfo.CallerStartOffset) {
            $start = [int]$runtimeInfo.CallerStartOffset
        }
        if ($null -eq $end -and $runtimeInfo -and $null -ne $runtimeInfo.CallerEndOffset) {
            $end = [int]$runtimeInfo.CallerEndOffset
        }

        if (-not $creatorNode) {
            break
        }

        if ($null -eq $start) { $start = $creatorNode.TextStartOffset }
        if ($null -eq $end) { $end = $creatorNode.TextEndOffset }

        if (-not (Test-RuntimeGeneratedNode -Node $creatorNode)) {
            return [PSCustomObject]@{
                Success       = ($null -ne $start -and $null -ne $end)
                StartOffset   = $start
                EndOffset     = $end
                NodeId        = [int]$creatorNode.Id
                RuntimeDepth  = $depth
                ViaRuntime    = $true
                FailureReason = if ($null -eq $start -or $null -eq $end) { 'missing_origin_offset' } else { $null }
            }
        }

        $nextBlockName = if ($creatorNode.PSObject.Properties['RuntimeBlockName']) {
            [string]$creatorNode.RuntimeBlockName
        } elseif ($runtimeInfo -and $runtimeInfo.PSObject.Properties['ParentBlockName']) {
            [string]$runtimeInfo.ParentBlockName
        } else {
            $null
        }

        if ([string]::IsNullOrWhiteSpace($nextBlockName) -and $runtimeInfo -and $runtimeInfo.PSObject.Properties['ParentBlockName']) {
            $nextBlockName = [string]$runtimeInfo.ParentBlockName
        }

        $currentBlockName = $nextBlockName
    }

    return [PSCustomObject]@{
        Success       = $false
        StartOffset   = $null
        EndOffset     = $null
        NodeId        = [int]$Node.Id
        RuntimeDepth  = $depth
        ViaRuntime    = $true
        FailureReason = if ($missingCallerNode) { 'caller_node_missing' } else { 'runtime_origin_unmapped' }
    }
}

function Get-DynamicInvokeAnchorTexts {
    param(
        $Record,
        $Node
    )

    $anchors = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)

    function Add-DynamicInvokeAnchor {
        param([string]$Text)

        if ([string]::IsNullOrWhiteSpace($Text)) { return }
        if ($seen.Add($Text)) {
            $anchors.Add($Text) | Out-Null
        }
    }

    if ($Node -and $Node.PSObject.Properties['Text']) {
        Add-DynamicInvokeAnchor -Text ([string]$Node.Text)
    }

    $preservedCommandText = Get-DynamicRecordValue -Record $Record -Name 'PreservedCommandText'
    if ($null -ne $preservedCommandText) {
        Add-DynamicInvokeAnchor -Text ([string]$preservedCommandText)
    }

    return @($anchors)
}

function Find-BestExactTextRangeInScriptText {
    param(
        [Parameter(Mandatory)][string]$ScriptText,
        [AllowEmptyCollection()][string[]]$CandidateTexts,
        [Nullable[int]]$PreferredStartOffset = $null
    )

    if ([string]::IsNullOrEmpty($ScriptText)) { return $null }
    if (-not $CandidateTexts -or $CandidateTexts.Count -eq 0) { return $null }

    $best = $null
    foreach ($candidateText in @($CandidateTexts | Sort-Object Length -Descending)) {
        if ([string]::IsNullOrWhiteSpace($candidateText)) { continue }

        $searchIndex = 0
        while ($searchIndex -lt $ScriptText.Length) {
            $pos = $ScriptText.IndexOf($candidateText, $searchIndex, [System.StringComparison]::Ordinal)
            if ($pos -lt 0) { break }

            $distance = if ($null -ne $PreferredStartOffset) {
                [Math]::Abs([int]$pos - [int]$PreferredStartOffset)
            } else {
                0
            }

            $isBetter = $false
            if (-not $best) {
                $isBetter = $true
            } elseif ($candidateText.Length -gt $best.AnchorLength) {
                $isBetter = $true
            } elseif ($candidateText.Length -eq $best.AnchorLength -and $distance -lt $best.Distance) {
                $isBetter = $true
            } elseif ($candidateText.Length -eq $best.AnchorLength -and $distance -eq $best.Distance -and $pos -lt $best.StartOffset) {
                $isBetter = $true
            }

            if ($isBetter) {
                $best = [PSCustomObject]@{
                    StartOffset  = [int]$pos
                    EndOffset    = [int]($pos + $candidateText.Length)
                    AnchorText   = [string]$candidateText
                    AnchorLength = [int]$candidateText.Length
                    Distance     = [int]$distance
                }
            }

            $searchIndex = $pos + 1
        }
    }

    return $best
}

function Resolve-DynamicInvokeRangeAgainstCurrentScript {
    param(
        [Parameter(Mandatory)][string]$ScriptText,
        [Nullable[int]]$StartOffset,
        [Nullable[int]]$EndOffset,
        $Node,
        $Record
    )

    $anchors = @(Get-DynamicInvokeAnchorTexts -Record $Record -Node $Node)

    function Test-AnchorRange {
        param(
            [Nullable[int]]$CandidateStart,
            [Nullable[int]]$CandidateEnd
        )

        if ($null -eq $CandidateStart -or $null -eq $CandidateEnd) { return $false }
        $start = [int]$CandidateStart
        $end = [int]$CandidateEnd
        if ($start -lt 0 -or $end -le $start -or $end -gt $ScriptText.Length) { return $false }
        if ($anchors.Count -eq 0) { return $true }

        $fragment = $ScriptText.Substring($start, $end - $start)
        foreach ($anchor in $anchors) {
            if ($fragment -eq [string]$anchor) {
                return $true
            }
        }

        return $false
    }

    if (Test-AnchorRange -CandidateStart $StartOffset -CandidateEnd $EndOffset) {
        return [PSCustomObject]@{
            Success        = $true
            StartOffset    = [int]$StartOffset
            EndOffset      = [int]$EndOffset
            ResolutionMode = 'direct'
        }
    }

    $nodeStart = if ($Node -and $Node.PSObject.Properties['TextStartOffset'] -and $null -ne $Node.TextStartOffset) { [int]$Node.TextStartOffset } else { $null }
    $nodeEnd = if ($Node -and $Node.PSObject.Properties['TextEndOffset'] -and $null -ne $Node.TextEndOffset) { [int]$Node.TextEndOffset } else { $null }
    if (Test-AnchorRange -CandidateStart $nodeStart -CandidateEnd $nodeEnd) {
        return [PSCustomObject]@{
            Success        = $true
            StartOffset    = [int]$nodeStart
            EndOffset      = [int]$nodeEnd
            ResolutionMode = 'node'
        }
    }

    $preferredStart = if ($null -ne $StartOffset) {
        [int]$StartOffset
    } elseif ($null -ne $nodeStart) {
        [int]$nodeStart
    } else {
        $null
    }

    $anchorMatch = Find-BestExactTextRangeInScriptText -ScriptText $ScriptText -CandidateTexts $anchors -PreferredStartOffset $preferredStart
    if ($anchorMatch) {
        return [PSCustomObject]@{
            Success        = $true
            StartOffset    = [int]$anchorMatch.StartOffset
            EndOffset      = [int]$anchorMatch.EndOffset
            ResolutionMode = 'anchor_search'
        }
    }

    $directRangeUsable = ($null -ne $StartOffset -and $null -ne $EndOffset -and [int]$StartOffset -ge 0 -and [int]$EndOffset -gt [int]$StartOffset -and [int]$EndOffset -le $ScriptText.Length)
    if ($directRangeUsable) {
        return [PSCustomObject]@{
            Success        = $true
            StartOffset    = [int]$StartOffset
            EndOffset      = [int]$EndOffset
            ResolutionMode = 'direct_unvalidated'
        }
    }

    $nodeRangeUsable = ($null -ne $nodeStart -and $null -ne $nodeEnd -and $nodeStart -ge 0 -and $nodeEnd -gt $nodeStart -and $nodeEnd -le $ScriptText.Length)
    if ($nodeRangeUsable) {
        return [PSCustomObject]@{
            Success        = $true
            StartOffset    = [int]$nodeStart
            EndOffset      = [int]$nodeEnd
            ResolutionMode = 'node_unvalidated'
        }
    }

    return [PSCustomObject]@{
        Success        = $false
        StartOffset    = $null
        EndOffset      = $null
        ResolutionMode = 'unresolved'
    }
}

function Test-EffectiveDynamicReplacementCandidate {
    param($Candidate)

    if (-not $Candidate) { return $false }
    if (-not $Candidate.PSObject.Properties['SourceKind']) { return $false }
    if ([string]$Candidate.SourceKind -notin @('DynamicInvoke', 'LoaderMaterialized', 'FunctionResult')) { return $false }

    $replacement = if ($Candidate.PSObject.Properties['Replacement']) { [string]$Candidate.Replacement } else { $null }
    $original = if ($Candidate.PSObject.Properties['Original']) { [string]$Candidate.Original } else { $null }
    if ([string]::IsNullOrWhiteSpace($replacement)) { return $false }
    if ($replacement -eq '__BLOCKED_PLACEHOLDER__') { return $false }
    if ($null -ne $original -and $replacement -eq $original) { return $false }

    return ($null -ne $Candidate.StartOffset -and $null -ne $Candidate.EndOffset)
}

function Get-ProtectedDynamicReplacementRanges {
    param([AllowEmptyCollection()][array]$Candidates)

    $ranges = @()
    $seen = @{}

    if (-not $Candidates -or $Candidates.Count -eq 0) {
        return @()
    }

    foreach ($cand in @($Candidates)) {
        if (-not (Test-EffectiveDynamicReplacementCandidate -Candidate $cand)) { continue }
        if ($cand.PSObject.Properties['ProtectsInnerCandidates'] -and -not [bool]$cand.ProtectsInnerCandidates) { continue }

        $start = [int]$cand.StartOffset
        $end = [int]$cand.EndOffset
        if ($null -eq $start -or $null -eq $end -or $end -le $start) { continue }

        $key = Get-ReplacementRangeKey -StartOffset $start -EndOffset $end
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $ranges += [PSCustomObject]@{
            StartOffset = [int]$start
            EndOffset   = [int]$end
        }
    }

    return @($ranges)
}

function Test-ValidCommandNameReplacement {
    param(
        [string]$Replacement,
        [hashtable]$Context
    )

    if ([string]::IsNullOrWhiteSpace($Replacement)) { return $false }

    $text = $Replacement.Trim()
    if ($text -match "[`r`n]") { return $false }
    if ($text -match '[''"\s]') { return $false }

    $allowed = $false
    if ($text -match '^[A-Za-z_][A-Za-z0-9_.-]*$') { $allowed = $true }
    if ($text -match '^\[(?:System\.Management\.Automation\.)?ScriptBlock\]::Create$') { $allowed = $true }
    if ($text -match '^_block_[a-f0-9]{8}$') { $allowed = $true }
    if (-not $allowed) { return $false }

    if ($Context.FunctionSubgraphs -and $Context.FunctionSubgraphs.ContainsKey($text)) { return $true }
    if ($Context.ScriptBlockSubgraphs -and $Context.ScriptBlockSubgraphs.ContainsKey($text)) { return $true }
    if ($Context.CFG -and $Context.CFG.DefinedAliases -and $Context.CFG.DefinedAliases.ContainsKey($text)) { return $true }

    return ($null -ne (Get-Command -Name $text -ErrorAction SilentlyContinue | Select-Object -First 1))
}

function Filter-ReplacementCandidatesByContext {
    param(
        [AllowEmptyCollection()][array]$Candidates,
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][string]$ScriptText
    )

    if (-not $Candidates -or $Candidates.Count -eq 0) {
        return [PSCustomObject]@{
            Candidates = @()
            Skipped    = @()
        }
    }

    $contextInfo = Get-ReplacementContextInfoFromScriptText -ScriptText $ScriptText
    $dynamicRanges = Get-ProtectedDynamicReplacementRanges -Candidates $Candidates
    $kept = @()
    $skipped = @()

    foreach ($cand in $Candidates) {
        if (-not $cand) { continue }

        $start = [int]$cand.StartOffset
        $end = [int]$cand.EndOffset
        $sourceKind = if ($cand.PSObject.Properties['SourceKind']) { [string]$cand.SourceKind } else { '' }
        $rangeKey = "$start`:$end"
        $isExactCommandNameRange = $contextInfo.CommandNameRangeKeys.ContainsKey($rangeKey)
        $withinDynamicRange = (Test-ReplacementWithinRanges -StartOffset $start -EndOffset $end -Ranges $dynamicRanges)
        $withinDynamicPayload = (Test-ReplacementWithinRanges -StartOffset $start -EndOffset $end -Ranges $contextInfo.DynamicPayloadRanges)
        $withinExpandable = (Test-ReplacementWithinRanges -StartOffset $start -EndOffset $end -Ranges $contextInfo.ExpandableStringRanges)

        if ($sourceKind -notin @('DynamicInvoke', 'LoaderMaterialized', 'FunctionResult') -and $withinDynamicPayload -and $withinDynamicRange) {
            $skipped += New-SkipRecord -Reason 'dynamic_payload_protected' -Message '外层 DynamicInvoke 候选有效，动态 payload 内部局部候选跳过' -Item $cand
            continue
        }

        if ($sourceKind -notin @('DynamicInvoke', 'LoaderMaterialized', 'FunctionResult') -and $withinDynamicRange) {
            $skipped += New-SkipRecord -Reason 'dynamic_wrapper_protected' -Message '外层 DynamicInvoke 候选有效，动态调用节点内部局部候选跳过' -Item $cand
            continue
        }

        $allowInExpandable = $false
        if ($withinExpandable) {
            if ($sourceKind -in @('DynamicInvoke', 'LoaderMaterialized', 'FunctionResult', 'LiteralizedCommand', 'Resolvable')) {
                $allowInExpandable = $true
            } elseif ($sourceKind -eq 'Static' -and $cand.PSObject.Properties['Confidence'] -and [string]$cand.Confidence -eq 'High') {
                $allowInExpandable = $true
            }
        }
        if ($sourceKind -notin @('DynamicInvoke', 'LoaderMaterialized', 'FunctionResult') -and $withinExpandable -and -not $allowInExpandable) {
            $skipped += New-SkipRecord -Reason 'expandable_context_protected' -Message 'ExpandableString 内仅放行高价值高置信候选，当前候选跳过' -Item $cand
            continue
        }

        if ($sourceKind -notin @('DynamicInvoke', 'LoaderMaterialized', 'FunctionResult') -and (Test-ReplacementWithinRanges -StartOffset $start -EndOffset $end -Ranges $contextInfo.MemberNameRanges)) {
            $skipped += New-SkipRecord -Reason 'member_name_protected' -Message '成员名位点默认不做局部替换，避免破坏反射/方法调用语义' -Item $cand
            continue
        }

        if ($sourceKind -notin @('DynamicInvoke', 'LoaderMaterialized', 'FunctionResult') -and (Test-ReplacementWithinRanges -StartOffset $start -EndOffset $end -Ranges $contextInfo.CommandTargetAssignmentRanges)) {
            $skipped += New-SkipRecord -Reason 'command_target_assignment_protected' -Message '命令目标变量的赋值表达式只允许整段还原，局部候选跳过' -Item $cand
            continue
        }

        if ((Test-ReplacementWithinRanges -StartOffset $start -EndOffset $end -Ranges $contextInfo.CommandNameRanges) -and -not $isExactCommandNameRange) {
            $skipped += New-SkipRecord -Reason 'command_name_context_protected' -Message '命令位点内部不允许局部替换，避免破坏命令解析' -Item $cand
            continue
        }

        if ($isExactCommandNameRange -and $sourceKind -ne 'FunctionResult' -and -not (Test-ValidCommandNameReplacement -Replacement ([string]$cand.Replacement) -Context $Context)) {
            $skipped += New-SkipRecord -Reason 'invalid_command_name_replacement' -Message '命令位点替换结果不是高置信合法命令名，跳过' -Item $cand
            continue
        }

        $kept += $cand
    }

    return [PSCustomObject]@{
        Candidates = @($kept)
        Skipped    = @($skipped)
    }
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
    if ($Value -is [System.Collections.IDictionary]) {
        return (Test-StaticDictionaryBindingValue -Value $Value)
    }
    if (Test-StaticPropertyBagValue -Value $Value) {
        return $true
    }

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

function Test-StaticDictionaryBindingValue {
    param([System.Collections.IDictionary]$Value)

    if ($null -eq $Value) { return $false }

    foreach ($key in @($Value.Keys)) {
        if (-not (Test-StaticReplacementScalarValue -Value $key)) { return $false }
        if (-not (Test-StaticBindingValue -Value $Value[$key])) { return $false }
    }

    return $true
}

function Test-StaticPropertyBagValue {
    param($Value)

    if ($null -eq $Value) { return $false }
    if ($Value -is [psobject] -and $null -ne $Value.BaseObject -and $Value.BaseObject -ne $Value) {
        $Value = $Value.BaseObject
    }
    if ($null -eq $Value) { return $false }

    $typeName = [string]$Value.GetType().FullName
    if ($typeName -notin @('System.Management.Automation.PSCustomObject', 'System.Management.Automation.PSObject')) {
        return $false
    }

    $noteProperties = @($Value.PSObject.Properties | Where-Object { $_.MemberType -eq [System.Management.Automation.PSMemberTypes]::NoteProperty })
    foreach ($property in $noteProperties) {
        if (-not (Test-StaticBindingValue -Value $property.Value)) { return $false }
    }

    return $true
}

function New-StaticDictionaryValue {
    param([switch]$Ordered)

    if ($Ordered) {
        return ([ordered]@{})
    }

    return @{}
}

function Resolve-StaticHashtableLiteralValue {
    param(
        [System.Management.Automation.Language.HashtableAst]$HashtableAst,
        [hashtable]$Context,
        [bool]$AllowEmptyFallback = $false,
        [int]$Depth = 0,
        [switch]$Ordered
    )

    if ($null -eq $HashtableAst) {
        return New-StaticEvalFailureResult -Reason 'invalid_hashtable' -Message 'HashtableAst 为空'
    }

    $map = New-StaticDictionaryValue -Ordered:$Ordered
    $usedFallback = $false

    foreach ($pair in @($HashtableAst.KeyValuePairs)) {
        if ($null -eq $pair) { continue }

        $keyAst = if ($pair.PSObject.Properties['Item1']) { $pair.Item1 } else { $null }
        $valueStatement = if ($pair.PSObject.Properties['Item2']) { $pair.Item2 } else { $null }
        if ($null -eq $keyAst -or $null -eq $valueStatement) {
            return New-StaticEvalFailureResult -Reason 'unsupported_hashtable_pair' -Message 'Hashtable 键值对结构不受支持' -UsedEmptyFallback:$usedFallback
        }

        $keyResult = Resolve-StaticAstValue -Ast $keyAst -Context $Context -AllowEmptyFallback:$false -Depth ($Depth + 1)
        if (-not $keyResult.Success) {
            return New-StaticEvalFailureResult -Reason 'hashtable_key' -Message $keyResult.Message -UsedEmptyFallback:([bool]$keyResult.UsedEmptyFallback -or $usedFallback)
        }
        if (-not (Test-StaticReplacementScalarValue -Value $keyResult.Value)) {
            return New-StaticEvalFailureResult -Reason 'hashtable_key_complex' -Message ('Hashtable 键类型不支持静态求值: ' + (Get-StaticValueTypeName -Value $keyResult.Value)) -UsedEmptyFallback:([bool]$keyResult.UsedEmptyFallback -or $usedFallback)
        }

        $valueAst = Get-StaticExpressionFromPipelineAst -PipelineAst $valueStatement
        if ($null -eq $valueAst) {
            return New-StaticEvalFailureResult -Reason 'unsupported_pipeline' -Message 'Hashtable 值不是简单表达式' -UsedEmptyFallback:$usedFallback
        }

        $valueResult = Resolve-StaticAstValue -Ast $valueAst -Context $Context -AllowEmptyFallback:$AllowEmptyFallback -Depth ($Depth + 1)
        if (-not $valueResult.Success) {
            return New-StaticEvalFailureResult -Reason 'hashtable_value' -Message $valueResult.Message -UsedEmptyFallback:([bool]$valueResult.UsedEmptyFallback -or $usedFallback)
        }

        $usedFallback = ($usedFallback -or [bool]$keyResult.UsedEmptyFallback -or [bool]$valueResult.UsedEmptyFallback)
        $map[$keyResult.Value] = $valueResult.Value
    }

    return [PSCustomObject]@{
        Success           = $true
        Value             = $map
        UsedEmptyFallback = $usedFallback
        Reason            = $null
        Message           = $null
    }
}

function Get-StaticMemberNameText {
    param(
        $MemberAst,
        [hashtable]$Context
    )

    if ($null -eq $MemberAst) { return $null }

    if ($MemberAst -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
        return [string]$MemberAst.Value
    }
    if ($MemberAst -is [System.Management.Automation.Language.ConstantExpressionAst] -and $MemberAst.Value -is [string]) {
        return [string]$MemberAst.Value
    }
    if ($MemberAst -is [System.Management.Automation.Language.ExpandableStringExpressionAst] -and @($MemberAst.NestedExpressions).Count -eq 0) {
        return [string]$MemberAst.Value
    }

    $resolved = Resolve-StaticAstValue -Ast $MemberAst -Context $Context -AllowEmptyFallback:$false
    if (-not $resolved.Success) { return $null }
    if ($resolved.Value -is [string] -or $resolved.Value -is [char]) {
        return [string]$resolved.Value
    }

    return $null
}

function Normalize-StaticSequenceIndex {
    param(
        [int]$Index,
        [int]$Count
    )

    if ($Count -lt 0) { return $null }
    $resolved = if ($Index -lt 0) { $Count + $Index } else { $Index }
    if ($resolved -lt 0 -or $resolved -ge $Count) { return $null }
    return $resolved
}

function ConvertTo-StaticIndexList {
    param($Value)

    if ($null -eq $Value) { return $null }
    if ($Value -is [psobject] -and $null -ne $Value.BaseObject -and $Value.BaseObject -ne $Value) {
        $Value = $Value.BaseObject
    }

    $items = if (($Value -is [System.Collections.IEnumerable]) -and -not ($Value -is [string])) { @($Value) } else { @($Value) }
    $indexes = New-Object System.Collections.Generic.List[int]

    foreach ($item in $items) {
        if ($item -is [bool]) { return $null }

        try {
            if ($item -is [double] -or $item -is [float] -or $item -is [decimal]) {
                $numeric = [double]$item
                if ([Math]::Truncate($numeric) -ne $numeric) { return $null }
                $indexes.Add([int]$numeric) | Out-Null
            } elseif ($item -is [sbyte] -or $item -is [byte] -or $item -is [int16] -or $item -is [uint16] -or $item -is [int] -or $item -is [uint32] -or $item -is [int64] -or $item -is [uint64]) {
                $indexes.Add([int]$item) | Out-Null
            } elseif ($item -is [string]) {
                $parsed = 0
                if (-not [int]::TryParse($item, [ref]$parsed)) { return $null }
                $indexes.Add($parsed) | Out-Null
            } else {
                return $null
            }
        } catch {
            return $null
        }
    }

    return @($indexes.ToArray())
}

function Resolve-StaticMemberAccessValue {
    param(
        $TargetValue,
        [string]$MemberName
    )

    if ([string]::IsNullOrWhiteSpace($MemberName)) {
        return [PSCustomObject]@{ Success = $false; Value = $null; Message = '成员名为空' }
    }

    if ($TargetValue -is [psobject] -and $null -ne $TargetValue.BaseObject -and $TargetValue.BaseObject -ne $TargetValue) {
        $TargetValue = $TargetValue.BaseObject
    }
    if ($null -eq $TargetValue) {
        return [PSCustomObject]@{ Success = $false; Value = $null; Message = '成员访问目标为空' }
    }

    if ($TargetValue -is [System.Collections.IDictionary]) {
        $matchedKey = $null
        foreach ($existingKey in @($TargetValue.Keys)) {
            if (($existingKey -is [string] -or $existingKey -is [char]) -and ([string]$existingKey -ieq $MemberName)) {
                $matchedKey = $existingKey
                break
            }
        }
        if ($null -ne $matchedKey) {
            return [PSCustomObject]@{ Success = $true; Value = $TargetValue[$matchedKey]; Message = $null }
        }

        if ($MemberName -ieq 'Keys') {
            return [PSCustomObject]@{ Success = $true; Value = @($TargetValue.Keys); Message = $null }
        }
        if ($MemberName -ieq 'Values') {
            return [PSCustomObject]@{ Success = $true; Value = @($TargetValue.Values); Message = $null }
        }
    }

    if (Test-StaticPropertyBagValue -Value $TargetValue) {
        $property = @($TargetValue.PSObject.Properties.Match($MemberName) | Where-Object { $_.MemberType -eq [System.Management.Automation.PSMemberTypes]::NoteProperty } | Select-Object -First 1)
        if ($property.Count -gt 0) {
            return [PSCustomObject]@{ Success = $true; Value = $property[0].Value; Message = $null }
        }
    }

    if ($MemberName -match '^(?i:length|count)$') {
        if ($TargetValue -is [string]) {
            return [PSCustomObject]@{ Success = $true; Value = $TargetValue.Length; Message = $null }
        }
        if ($TargetValue -is [array]) {
            return [PSCustomObject]@{ Success = $true; Value = $TargetValue.Length; Message = $null }
        }
        if ($TargetValue -is [System.Collections.ICollection]) {
            return [PSCustomObject]@{ Success = $true; Value = $TargetValue.Count; Message = $null }
        }
        if (($TargetValue -is [System.Collections.IEnumerable]) -and -not ($TargetValue -is [string])) {
            return [PSCustomObject]@{ Success = $true; Value = @($TargetValue).Count; Message = $null }
        }
    }

    return [PSCustomObject]@{ Success = $false; Value = $null; Message = ('不支持的安全成员访问: ' + $MemberName) }
}

function Resolve-StaticTypeFromTypeExpressionAst {
    param([System.Management.Automation.Language.TypeExpressionAst]$TypeExpressionAst)

    if ($null -eq $TypeExpressionAst -or $null -eq $TypeExpressionAst.TypeName) { return $null }

    try {
        $reflectionType = $TypeExpressionAst.TypeName.GetReflectionType()
        if ($reflectionType) { return $reflectionType }
    } catch {}

    $fullName = [string]$TypeExpressionAst.TypeName.FullName
    if ([string]::IsNullOrWhiteSpace($fullName)) { return $null }

    try {
        $reflectionType = [Type]::GetType($fullName, $false, $true)
        if ($reflectionType) { return $reflectionType }
    } catch {}

    foreach ($assembly in [AppDomain]::CurrentDomain.GetAssemblies()) {
        try {
            $reflectionType = $assembly.GetType($fullName, $false, $true)
            if ($reflectionType) { return $reflectionType }
        } catch {}
    }

    return $null
}

function Resolve-StaticTypeMemberAccessValue {
    param(
        [Type]$TargetType,
        [string]$MemberName
    )

    if ($null -eq $TargetType -or [string]::IsNullOrWhiteSpace($MemberName)) {
        return [PSCustomObject]@{ Success = $false; Value = $null; Message = '静态成员访问缺少类型或成员名' }
    }

    if ($TargetType.IsEnum) {
        try {
            return [PSCustomObject]@{ Success = $true; Value = [Enum]::Parse($TargetType, $MemberName, $true); Message = $null }
        } catch {}
    }

    switch -Regex ($TargetType.FullName) {
        '^(?i:System\.Text\.Encoding)$' {
            switch -Regex ($MemberName) {
                '^(?i:ASCII)$'            { return [PSCustomObject]@{ Success = $true; Value = [System.Text.Encoding]::ASCII; Message = $null } }
                '^(?i:UTF8)$'             { return [PSCustomObject]@{ Success = $true; Value = [System.Text.Encoding]::UTF8; Message = $null } }
                '^(?i:Unicode)$'          { return [PSCustomObject]@{ Success = $true; Value = [System.Text.Encoding]::Unicode; Message = $null } }
                '^(?i:BigEndianUnicode)$' { return [PSCustomObject]@{ Success = $true; Value = [System.Text.Encoding]::BigEndianUnicode; Message = $null } }
                '^(?i:UTF32)$'            { return [PSCustomObject]@{ Success = $true; Value = [System.Text.Encoding]::UTF32; Message = $null } }
                '^(?i:Default)$'          { return [PSCustomObject]@{ Success = $true; Value = [System.Text.Encoding]::Default; Message = $null } }
            }
        }
    }

    return [PSCustomObject]@{ Success = $false; Value = $null; Message = ('不支持的安全静态成员访问: ' + $TargetType.FullName + '::' + $MemberName) }
}

function Convert-StaticMethodArguments {
    param(
        [object[]]$Arguments,
        [hashtable]$Context,
        [int]$Depth = 0
    )

    $values = @()
    $usedFallback = $false
    foreach ($argAst in @($Arguments)) {
        $argResult = Resolve-StaticAstValue -Ast $argAst -Context $Context -AllowEmptyFallback:$false -Depth ($Depth + 1)
        if (-not $argResult.Success) {
            return [PSCustomObject]@{
                Success           = $false
                Values            = @()
                UsedEmptyFallback = ($usedFallback -or [bool]$argResult.UsedEmptyFallback)
                Message           = $argResult.Message
            }
        }
        $usedFallback = ($usedFallback -or [bool]$argResult.UsedEmptyFallback)
        $values += ,$argResult.Value
    }

    return [PSCustomObject]@{
        Success           = $true
        Values            = @($values)
        UsedEmptyFallback = $usedFallback
        Message           = $null
    }
}

function Convert-StaticValueToStringArray {
    param($Value)

    if ($Value -is [psobject] -and $null -ne $Value.BaseObject -and $Value.BaseObject -ne $Value) {
        $Value = $Value.BaseObject
    }

    if ($null -eq $Value) { return @('') }
    if ($Value -is [string]) { return @([string]$Value) }
    if ($Value -is [char]) { return @([string]$Value) }
    if ($Value -is [char[]]) { return @((-join $Value)) }

    if (($Value -is [System.Collections.IEnumerable]) -and -not ($Value -is [string])) {
        $items = @()
        foreach ($item in $Value) {
            if ($item -is [psobject] -and $null -ne $item.BaseObject -and $item.BaseObject -ne $item) {
                $item = $item.BaseObject
            }
            if ($null -eq $item) {
                $items += ''
            } else {
                $items += [string]$item
            }
        }
        return @($items)
    }

    return @([string]$Value)
}

function Convert-StaticValueToCharArray {
    param($Value)

    if ($Value -is [psobject] -and $null -ne $Value.BaseObject -and $Value.BaseObject -ne $Value) {
        $Value = $Value.BaseObject
    }

    if ($null -eq $Value) { return @() }
    if ($Value -is [char[]]) { return @($Value) }
    if ($Value -is [char]) { return @([char]$Value) }
    if ($Value -is [string]) { return @(([string]$Value).ToCharArray()) }

    if (($Value -is [System.Collections.IEnumerable]) -and -not ($Value -is [string])) {
        $chars = New-Object System.Collections.Generic.List[char]
        foreach ($item in $Value) {
            if ($item -is [psobject] -and $null -ne $item.BaseObject -and $item.BaseObject -ne $item) {
                $item = $item.BaseObject
            }
            try {
                if ($item -is [char]) {
                    $chars.Add([char]$item) | Out-Null
                } elseif ($item -is [string] -and $item.Length -eq 1) {
                    $chars.Add([char]$item[0]) | Out-Null
                } elseif ($item -is [byte] -or $item -is [sbyte] -or $item -is [int16] -or $item -is [uint16] -or
                    $item -is [int] -or $item -is [uint32] -or $item -is [int64] -or $item -is [uint64]) {
                    $chars.Add([char][int]$item) | Out-Null
                } else {
                    return $null
                }
            } catch {
                return $null
            }
        }
        return @($chars.ToArray())
    }

    return $null
}

function Convert-StaticValueToStringSplitOptions {
    param($Value)

    if ($Value -is [System.StringSplitOptions]) {
        return [PSCustomObject]@{ Success = $true; Value = $Value }
    }

    if ($Value -is [string]) {
        try {
            return [PSCustomObject]@{ Success = $true; Value = [System.StringSplitOptions]::Parse([System.StringSplitOptions], $Value, $true) }
        } catch {
            return [PSCustomObject]@{ Success = $false; Value = $null }
        }
    }

    try {
        return [PSCustomObject]@{ Success = $true; Value = [System.StringSplitOptions][int]$Value }
    } catch {
        return [PSCustomObject]@{ Success = $false; Value = $null }
    }
}

function Resolve-StaticStringSplitInvocationValue {
    param(
        [string]$TargetValue,
        [object[]]$Arguments
    )

    if ($null -eq $TargetValue) {
        return [PSCustomObject]@{ Success = $false; Value = $null; Message = 'Split 目标为空' }
    }
    if (-not $Arguments -or $Arguments.Count -eq 0) {
        return [PSCustomObject]@{ Success = $false; Value = $null; Message = 'Split 缺少参数' }
    }

    $options = [System.StringSplitOptions]::None
    $count = $null
    $separatorArg = $Arguments[0]

    if ($Arguments.Count -ge 2) {
        $optionInfo = Convert-StaticValueToStringSplitOptions -Value $Arguments[-1]
        if ($optionInfo.Success) {
            $options = $optionInfo.Value
            if ($Arguments.Count -ge 3) {
                try { $count = [int]$Arguments[1] } catch { $count = $null }
            }
        } elseif ($Arguments.Count -eq 2) {
            try { $count = [int]$Arguments[1] } catch { $count = $null }
        } else {
            try { $count = [int]$Arguments[1] } catch { $count = $null }
        }
    }

    $charSeparators = Convert-StaticValueToCharArray -Value $separatorArg
    $stringSeparators = Convert-StaticValueToStringArray -Value $separatorArg

    try {
        if ($null -ne $count) {
            if ($stringSeparators.Count -gt 1 -or (($stringSeparators.Count -eq 1) -and $stringSeparators[0].Length -gt 1)) {
                return [PSCustomObject]@{ Success = $true; Value = $TargetValue.Split($stringSeparators, $count, $options); Message = $null }
            }
            if ($null -ne $charSeparators) {
                return [PSCustomObject]@{ Success = $true; Value = $TargetValue.Split($charSeparators, $count, $options); Message = $null }
            }
        } else {
            if ($stringSeparators.Count -gt 1 -or (($stringSeparators.Count -eq 1) -and $stringSeparators[0].Length -gt 1)) {
                return [PSCustomObject]@{ Success = $true; Value = $TargetValue.Split($stringSeparators, $options); Message = $null }
            }
            if ($null -ne $charSeparators) {
                if ($options -eq [System.StringSplitOptions]::None) {
                    return [PSCustomObject]@{ Success = $true; Value = $TargetValue.Split($charSeparators); Message = $null }
                }
                return [PSCustomObject]@{ Success = $true; Value = $TargetValue.Split($charSeparators, $options); Message = $null }
            }
        }
    } catch {
        return [PSCustomObject]@{ Success = $false; Value = $null; Message = $_.Exception.Message }
    }

    return [PSCustomObject]@{ Success = $false; Value = $null; Message = 'Split 参数类型不受支持' }
}

function Resolve-StaticMethodInvocationValue {
    param(
        $TargetValue,
        [string]$MemberName,
        [object[]]$Arguments
    )

    if ([string]::IsNullOrWhiteSpace($MemberName)) {
        return [PSCustomObject]@{ Success = $false; Value = $null; Message = '方法名为空' }
    }

    if ($TargetValue -is [psobject] -and $null -ne $TargetValue.BaseObject -and $TargetValue.BaseObject -ne $TargetValue) {
        $TargetValue = $TargetValue.BaseObject
    }

    switch -Regex ($MemberName) {
        '^(?i:Split)$' {
            if ($TargetValue -isnot [string]) {
                return [PSCustomObject]@{ Success = $false; Value = $null; Message = 'Split 仅支持字符串目标' }
            }
            return Resolve-StaticStringSplitInvocationValue -TargetValue ([string]$TargetValue) -Arguments $Arguments
        }
    }

    return [PSCustomObject]@{ Success = $false; Value = $null; Message = ('不支持的安全方法调用: ' + $MemberName) }
}

function Resolve-StaticTypeMethodInvocationValue {
    param(
        [Type]$TargetType,
        [string]$MemberName,
        [object[]]$Arguments
    )

    if ($null -eq $TargetType -or [string]::IsNullOrWhiteSpace($MemberName)) {
        return [PSCustomObject]@{ Success = $false; Value = $null; Message = '静态方法调用缺少类型或方法名' }
    }

    if ($TargetType -eq [string] -and $MemberName -match '^(?i:Join)$') {
        if (-not $Arguments -or $Arguments.Count -lt 2) {
            return [PSCustomObject]@{ Success = $false; Value = $null; Message = 'String::Join 缺少参数' }
        }

        $separator = [string]$Arguments[0]
        $values = Convert-StaticValueToStringArray -Value $Arguments[1]

        try {
            if ($Arguments.Count -ge 4) {
                return [PSCustomObject]@{
                    Success = $true
                    Value   = [string]::Join($separator, $values, [int]$Arguments[2], [int]$Arguments[3])
                    Message = $null
                }
            }

            return [PSCustomObject]@{
                Success = $true
                Value   = [string]::Join($separator, $values)
                Message = $null
            }
        } catch {
            return [PSCustomObject]@{ Success = $false; Value = $null; Message = $_.Exception.Message }
        }
    }

    return [PSCustomObject]@{ Success = $false; Value = $null; Message = ('不支持的安全静态方法调用: ' + $TargetType.FullName + '::' + $MemberName) }
}

function Resolve-StaticIndexAccessValue {
    param(
        $TargetValue,
        $IndexValue
    )

    if ($TargetValue -is [psobject] -and $null -ne $TargetValue.BaseObject -and $TargetValue.BaseObject -ne $TargetValue) {
        $TargetValue = $TargetValue.BaseObject
    }
    if ($null -eq $TargetValue) {
        return [PSCustomObject]@{ Success = $false; Value = $null; Message = '索引访问目标为空' }
    }

    if ($TargetValue -is [System.Collections.IDictionary]) {
        $keys = if (($IndexValue -is [System.Collections.IEnumerable]) -and -not ($IndexValue -is [string])) { @($IndexValue) } else { @($IndexValue) }
        $values = @()
        foreach ($lookupKey in $keys) {
            $matchedKey = $null
            foreach ($existingKey in @($TargetValue.Keys)) {
                if ($existingKey -eq $lookupKey) {
                    $matchedKey = $existingKey
                    break
                }
                if (($existingKey -is [string] -or $existingKey -is [char]) -and ($lookupKey -is [string] -or $lookupKey -is [char]) -and ([string]$existingKey -ieq [string]$lookupKey)) {
                    $matchedKey = $existingKey
                    break
                }
            }

            if ($null -eq $matchedKey) {
                return [PSCustomObject]@{ Success = $false; Value = $null; Message = ('字典中不存在键: ' + [string]$lookupKey) }
            }

            $values += ,$TargetValue[$matchedKey]
        }

        if ($values.Count -eq 1) {
            return [PSCustomObject]@{ Success = $true; Value = $values[0]; Message = $null }
        }

        return [PSCustomObject]@{ Success = $true; Value = @($values); Message = $null }
    }

    $indexes = ConvertTo-StaticIndexList -Value $IndexValue
    if (-not $indexes -or $indexes.Count -eq 0) {
        return [PSCustomObject]@{ Success = $false; Value = $null; Message = '索引值不是受支持的整数/整数数组' }
    }

    if ($TargetValue -is [string]) {
        $chars = $TargetValue.ToCharArray()
        $values = @()
        foreach ($index in $indexes) {
            $normalized = Normalize-StaticSequenceIndex -Index $index -Count $chars.Length
            if ($null -eq $normalized) {
                return [PSCustomObject]@{ Success = $false; Value = $null; Message = ('字符串索引越界: ' + $index) }
            }
            $values += ,$chars[$normalized]
        }

        if ($values.Count -eq 1) {
            return [PSCustomObject]@{ Success = $true; Value = $values[0]; Message = $null }
        }

        return [PSCustomObject]@{ Success = $true; Value = @($values); Message = $null }
    }

    $sequence = $null
    if ($TargetValue -is [array]) {
        $sequence = @($TargetValue)
    } elseif ($TargetValue -is [System.Collections.IList]) {
        $sequence = @($TargetValue)
    } elseif (($TargetValue -is [System.Collections.IEnumerable]) -and -not ($TargetValue -is [string])) {
        $sequence = @($TargetValue)
    }

    if ($null -eq $sequence) {
        return [PSCustomObject]@{ Success = $false; Value = $null; Message = ('目标类型不支持索引访问: ' + (Get-StaticValueTypeName -Value $TargetValue)) }
    }

    $values = @()
    foreach ($index in $indexes) {
        $normalized = Normalize-StaticSequenceIndex -Index $index -Count $sequence.Count
        if ($null -eq $normalized) {
            return [PSCustomObject]@{ Success = $false; Value = $null; Message = ('数组索引越界: ' + $index) }
        }
        $values += ,$sequence[$normalized]
    }

    if ($values.Count -eq 1) {
        return [PSCustomObject]@{ Success = $true; Value = $values[0]; Message = $null }
    }

    return [PSCustomObject]@{ Success = $true; Value = @($values); Message = $null }
}

function Get-FormattingEquivalentCollectionWrapperInfo {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }

    $compact = (($Text -replace '\s+', '')).Trim()
    $parenMatch = [regex]::Match($compact, '^\((?<inner>.+)\)$')
    if ($parenMatch.Success) {
        return [PSCustomObject]@{
            Kind  = 'Paren'
            Inner = [string]$parenMatch.Groups['inner'].Value
        }
    }

    $arrayMatch = [regex]::Match($compact, '^@\((?<inner>.+)\)$')
    if ($arrayMatch.Success) {
        return [PSCustomObject]@{
            Kind  = 'ArrayLiteral'
            Inner = [string]$arrayMatch.Groups['inner'].Value
        }
    }

    return $null
}

function Test-FormattingOnlyEquivalentReplacement {
    param(
        [string]$Original,
        [string]$Replacement,
        $Type
    )

    if ([string]::IsNullOrWhiteSpace($Original) -or [string]::IsNullOrWhiteSpace($Replacement)) {
        return $false
    }

    $typeNames = if (($Type -is [System.Collections.IEnumerable]) -and -not ($Type -is [string])) {
        @($Type | ForEach-Object { [string]$_ })
    } else {
        @([string]$Type)
    }

    if (@($typeNames | Where-Object { $_ -in @('Paren', 'ArrayLiteral', 'ArrayExpression') }).Count -eq 0) {
        return $false
    }

    $originalInfo = Get-FormattingEquivalentCollectionWrapperInfo -Text $Original
    $replacementInfo = Get-FormattingEquivalentCollectionWrapperInfo -Text $Replacement
    if ($null -eq $originalInfo -or $null -eq $replacementInfo) { return $false }
    if ($originalInfo.Kind -eq $replacementInfo.Kind) { return $false }

    return ($originalInfo.Inner -eq $replacementInfo.Inner)
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

function Get-SafeNonEmptyString {
    param($Value)

    try {
        $text = [string]$Value
    } catch {
        return $null
    }

    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    return $text
}

function Resolve-PowerShellHostLooseParameterInfo {
    param([string]$ParameterName)

    if (Get-Command Resolve-PowerShellHostParameterInfo -ErrorAction SilentlyContinue) {
        return Resolve-PowerShellHostParameterInfo -ParameterName $ParameterName
    }

    if (Test-PowerShellHostParameterPrefix -ParameterName $ParameterName -CanonicalName 'encodedcommand') {
        return [PSCustomObject]@{ CanonicalName = 'encodedcommand'; DynamicType = 'EncodedCommand'; ExpectsValue = $true }
    }
    if (Test-PowerShellHostParameterPrefix -ParameterName $ParameterName -CanonicalName 'command') {
        return [PSCustomObject]@{ CanonicalName = 'command'; DynamicType = 'PowerShellCommand'; ExpectsValue = $true }
    }

    return $null
}

function Get-PowerShellHostLooseTokenMatches {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    return @([regex]::Matches($Text, '(?s)"(?:[^"]|"")*"|''(?:[^'']|'''')*''|\S+'))
}

function Unwrap-PowerShellHostLooseToken {
    param([string]$TokenText)

    if ([string]::IsNullOrWhiteSpace($TokenText)) { return $TokenText }
    if (($TokenText.StartsWith('"') -and $TokenText.EndsWith('"')) -or ($TokenText.StartsWith("'") -and $TokenText.EndsWith("'"))) {
        if ($TokenText.Length -ge 2) {
            return $TokenText.Substring(1, $TokenText.Length - 2)
        }
    }

    return $TokenText
}

function Try-GetWholeScriptHostPayloadInfoLoose {
    param([Parameter(Mandatory)][string]$ScriptText)

    if ([string]::IsNullOrWhiteSpace($ScriptText)) { return $null }

    $text = $ScriptText.Trim()
    $hostMatch = [regex]::Match($text, '(?is)\b(?<cmd>(?:[A-Z]:)?[^''"\r\n]*?(?:powershell|pwsh)(?:\.exe)?)\b')
    if (-not $hostMatch.Success) { return $null }

    $tail = $text.Substring($hostMatch.Index + $hostMatch.Length)
    if ([string]::IsNullOrWhiteSpace($tail)) { return $null }

    $tokenMatches = @(Get-PowerShellHostLooseTokenMatches -Text $tail)
    for ($i = 0; $i -lt $tokenMatches.Count; $i++) {
        $tokenMatch = $tokenMatches[$i]
        $tokenText = [string]$tokenMatch.Value
        if ([string]::IsNullOrWhiteSpace($tokenText)) { continue }

        if (-not $tokenText.StartsWith('-')) {
            $payloadText = $tail.Substring($tokenMatch.Index).Trim()
            if (-not [string]::IsNullOrWhiteSpace($payloadText)) {
                return [PSCustomObject]@{
                    CommandName  = $hostMatch.Groups['cmd'].Value
                    DynamicType  = 'PowerShellCommand'
                    PayloadText  = $payloadText
                    DecodeSource = 'host_wrapper_decode_bare_tail'
                }
            }
            continue
        }

        $paramInfo = Resolve-PowerShellHostLooseParameterInfo -ParameterName $tokenText.TrimStart('-')
        if (-not $paramInfo) {
            $payloadText = $tail.Substring($tokenMatch.Index).Trim()
            if (-not [string]::IsNullOrWhiteSpace($payloadText)) {
                return [PSCustomObject]@{
                    CommandName  = $hostMatch.Groups['cmd'].Value
                    DynamicType  = 'PowerShellCommand'
                    PayloadText  = $payloadText
                    DecodeSource = 'host_wrapper_decode_bare_tail'
                }
            }
            continue
        }

        if ($paramInfo.CanonicalName -eq 'file') {
            return $null
        }

        if ($paramInfo.DynamicType -eq 'EncodedCommand') {
            if ($i + 1 -ge $tokenMatches.Count) { return $null }

            $encodedValue = Unwrap-PowerShellHostLooseToken -TokenText ([string]$tokenMatches[$i + 1].Value)
            $decoded = Get-SafeNonEmptyString -Value (Try-DecodeEncodedCommandValue -Base64String $encodedValue)
            if ($decoded) {
                return [PSCustomObject]@{
                    CommandName  = $hostMatch.Groups['cmd'].Value
                    DynamicType  = 'EncodedCommand'
                    PayloadText  = $decoded
                    DecodeSource = 'host_wrapper_decode_encoded'
                }
            }

            return $null
        }

        if ($paramInfo.DynamicType -eq 'PowerShellCommand') {
            if ($i + 1 -ge $tokenMatches.Count) { return $null }

            $payloadText = $tail.Substring($tokenMatches[$i + 1].Index).Trim()
            if ($tokenMatches.Count -eq ($i + 2)) {
                $payloadText = Unwrap-PowerShellHostLooseToken -TokenText $payloadText
            }

            $payloadText = Get-SafeNonEmptyString -Value $payloadText
            if ($payloadText) {
                return [PSCustomObject]@{
                    CommandName  = $hostMatch.Groups['cmd'].Value
                    DynamicType  = 'PowerShellCommand'
                    PayloadText  = $payloadText
                    DecodeSource = 'host_wrapper_decode_command'
                }
            }

            return $null
        }

        if ($paramInfo.ExpectsValue) {
            if ($i + 1 -ge $tokenMatches.Count) { return $null }
            $i++
        }
    }

    return $null
}

function Resolve-WholeScriptHostPayloadInfo {
    param([Parameter(Mandatory)][string]$ScriptText)

    $payloadInfo = Try-GetWholeScriptHostPayloadInfo -ScriptText $ScriptText
    if ($payloadInfo) { return $payloadInfo }

    return Try-GetWholeScriptHostPayloadInfoLoose -ScriptText $ScriptText
}

function Get-BestEffortParseFallbackScriptText {
    param(
        [Parameter(Mandatory)][string]$ScriptText,
        [string]$ParseError
    )

    $payloadInfo = Resolve-WholeScriptHostPayloadInfo -ScriptText $ScriptText

    $resolvedPayloadText = if ($payloadInfo) { Get-SafeNonEmptyString -Value $payloadInfo.PayloadText } else { $null }
    $body = if ($resolvedPayloadText) {
        $resolvedPayloadText
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

function Get-NoReplacementTerminationReason {
    param(
        [int]$CandidateCount,
        [AllowEmptyCollection()][array]$Skipped = @()
    )

    if ($CandidateCount -le 0) {
        return 'no_candidates_generated'
    }

    $reasons = @($Skipped | Where-Object { $_ -and $_.PSObject.Properties['Reason'] } | ForEach-Object { [string]$_.Reason })
    if ($reasons.Count -eq 0) {
        return 'unknown'
    }

    if (@($reasons | Where-Object { $_ -match '^syntax_guard' }).Count -gt 0) {
        return 'all_candidates_skipped_by_syntax_guard'
    }
    if (@($reasons | Where-Object { $_ -in @('dynamic_runtime_unmapped', 'dynamic_no_offset', 'dynamic_node_missing', 'dynamic_out_of_range', 'caller_node_missing', 'runtime_origin_unmapped', 'missing_offset', 'node_missing') }).Count -gt 0) {
        return 'all_candidates_unmapped'
    }
    if (@($reasons | Where-Object { $_ -in @('dynamic_outer_candidate_ineffective', 'dynamic_outer_candidate_ineffective', 'literalized_no_change', 'dynamic_same_range_preferred', 'duplicate') }).Count -gt 0) {
        return 'all_candidates_ineffective'
    }

    return 'unknown'
}

function Test-FileSyntaxInfo {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return [PSCustomObject]@{
            Exists     = $false
            IsValid    = $false
            FirstError = 'file_not_found'
        }
    }

    $text = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path))
    $syntax = Test-PowerShellSyntax -ScriptText $text
    return [PSCustomObject]@{
        Exists     = $true
        IsValid    = [bool]$syntax.IsValid
        FirstError = $syntax.FirstError
        Text       = $text
    }
}

function Get-PreTraversalStopCheckInfo {
    param(
        [Parameter(Mandatory)][string]$ScriptText,
        [bool]$IsMaterializedPayloadRound = $false
    )

    $reason = $null
    if ($IsMaterializedPayloadRound) {
        $reason = 'materialized_payload_round'
    }

    return [PSCustomObject]@{
        ShouldCheck = [bool]$IsMaterializedPayloadRound
        Reason      = $reason
        CheckText    = $ScriptText
    }
}

function Get-NextRoundMaterializedPayloadInfo {
    param(
        [object[]]$Selected = @(),
        [Parameter(Mandatory)][string]$PrePostProcessText
    )

    $hasDynamicInvokeSelection = @($Selected | Where-Object { $_ -and $_.PSObject.Properties['SourceKind'] -and [string]$_.SourceKind -eq 'DynamicInvoke' }).Count -gt 0
    $cameFromHostWrapperDecode = $false

    $payloadInfo = Resolve-WholeScriptHostPayloadInfo -ScriptText $PrePostProcessText
    $resolvedPayloadText = if ($payloadInfo) { Get-SafeNonEmptyString -Value $payloadInfo.PayloadText } else { $null }
    if ($resolvedPayloadText) {
        $payloadParse = Get-ScriptParseInfo -ScriptText $resolvedPayloadText
        if ($payloadParse.IsValid) {
            $cameFromHostWrapperDecode = $true
        }
    }

    $isMaterializedPayload = ($hasDynamicInvokeSelection -or $cameFromHostWrapperDecode)
    $reason = $null
    if ($hasDynamicInvokeSelection) {
        $reason = 'dynamic_invoke_selection'
    } elseif ($cameFromHostWrapperDecode) {
        $reason = if ($payloadInfo -and $payloadInfo.PSObject.Properties['DecodeSource'] -and -not [string]::IsNullOrWhiteSpace([string]$payloadInfo.DecodeSource)) {
            [string]$payloadInfo.DecodeSource
        } else {
            'host_wrapper_decode'
        }
    }

    return [PSCustomObject]@{
        IsMaterializedPayload = $isMaterializedPayload
        Reason                = $reason
        FromDynamicInvoke     = $hasDynamicInvokeSelection
        FromHostWrapperDecode = $cameFromHostWrapperDecode
    }
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

function Get-StaticEvalState {
    param([hashtable]$Context)

    if ($null -eq $Context) { return $null }

    if (-not $Context.ContainsKey('StaticEvalState') -or $null -eq $Context.StaticEvalState) {
        $Context.StaticEvalState = @{
            StringCompatCache      = @{}
            ValueCache             = @{}
            StringCompatInProgress = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
            ValueInProgress        = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
            StringCompatDepthLimit = 128
            ValueDepthLimit        = 192
            BudgetMs               = 0
            Stopwatch              = $null
        }
    }

    return $Context.StaticEvalState
}

function Reset-StaticEvalState {
    param(
        [hashtable]$Context,
        [int]$TimeBudgetMs = 0
    )

    $state = Get-StaticEvalState -Context $Context
    if ($null -eq $state) { return $null }

    $state.StringCompatCache = @{}
    $state.ValueCache = @{}
    $state.StringCompatInProgress = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    $state.ValueInProgress = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    $state.BudgetMs = [Math]::Max(0, $TimeBudgetMs)
    $state.Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    return $state
}

function Get-StaticAstCacheKey {
    param(
        $Ast,
        [bool]$AllowEmptyFallback = $false,
        [string]$Prefix = ''
    )

    if ($null -eq $Ast) { return $null }

    $id = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($Ast)
    if ([string]::IsNullOrWhiteSpace($Prefix)) {
        return "$id|$AllowEmptyFallback"
    }

    return "$Prefix|$id|$AllowEmptyFallback"
}

function Test-StaticEvalBudgetExceeded {
    param([hashtable]$Context)

    $state = Get-StaticEvalState -Context $Context
    if ($null -eq $state -or -not $state.Stopwatch) { return $false }

    $budgetMs = if ($state.ContainsKey('BudgetMs') -and $null -ne $state.BudgetMs) { [int]$state.BudgetMs } else { 0 }
    if ($budgetMs -le 0) { return $false }

    return ($state.Stopwatch.ElapsedMilliseconds -ge $budgetMs)
}

function New-StaticEvalFailureResult {
    param(
        [string]$Reason,
        [string]$Message,
        [bool]$UsedEmptyFallback = $false
    )

    return [PSCustomObject]@{
        Success           = $false
        Value             = $null
        UsedEmptyFallback = $UsedEmptyFallback
        Reason            = $Reason
        Message           = $Message
    }
}

function Test-StaticEvalResultCacheable {
    param($Result)

    if (-not $Result) { return $false }
    if ($Result.Success) { return $true }

    $reason = if ($Result.PSObject.Properties['Reason']) { [string]$Result.Reason } else { '' }
    return ($reason -notin @('depth_limit', 'budget_exceeded', 'cycle_detected'))
}

function Test-StaticAstStringCompatible {
    param(
        $Ast,
        [hashtable]$Context,
        [int]$Depth = 0
    )

    if ($null -eq $Ast) { return $false }

    if (Test-StaticEvalBudgetExceeded -Context $Context) { return $false }

    $state = Get-StaticEvalState -Context $Context
    $depthLimit = if ($state -and $state.ContainsKey('StringCompatDepthLimit')) { [int]$state.StringCompatDepthLimit } else { 128 }
    if ($Depth -ge $depthLimit) { return $false }

    $cacheKey = Get-StaticAstCacheKey -Ast $Ast -Prefix 'compat'
    if ($state -and $cacheKey -and $state.StringCompatCache.ContainsKey($cacheKey)) {
        return [bool]$state.StringCompatCache[$cacheKey]
    }
    if ($state -and $cacheKey -and $state.StringCompatInProgress.Contains($cacheKey)) {
        return $false
    }

    $addedToProgress = $false
    if ($state -and $cacheKey) {
        $addedToProgress = $state.StringCompatInProgress.Add($cacheKey)
    }

    try {
        $result = $false

        if ($Ast -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
            $result = $true
        } elseif ($Ast -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) {
            $result = $true
        } elseif ($Ast -is [System.Management.Automation.Language.ConstantExpressionAst]) {
            $result = (($Ast.Value -is [string]) -or ($Ast.Value -is [char]))
        } elseif ($Ast -is [System.Management.Automation.Language.VariableExpressionAst]) {
            $resolved = Resolve-StaticVariableValue -Context $Context -Ast $Ast -AllowEmptyFallback:$false
            if ($resolved.Success) {
                $result = (($resolved.Value -is [string]) -or ($resolved.Value -is [char]))
            }
        } elseif ($Ast -is [System.Management.Automation.Language.ConvertExpressionAst]) {
            $typeName = Get-StaticConvertTypeName -ConvertAst $Ast
            $result = ($typeName -and $typeName.ToLowerInvariant() -eq 'string')
        } elseif ($Ast -is [System.Management.Automation.Language.BinaryExpressionAst]) {
            $op = [string]$Ast.Operator
            if ($op -in @('Join', 'Format')) {
                $result = $true
            } elseif ($op -eq 'Plus') {
                $result = ((Test-StaticAstStringCompatible -Ast $Ast.Left -Context $Context -Depth ($Depth + 1)) -or
                    (Test-StaticAstStringCompatible -Ast $Ast.Right -Context $Context -Depth ($Depth + 1)))
            }
        } elseif ($Ast -is [System.Management.Automation.Language.ParenExpressionAst]) {
            $expr = Get-StaticExpressionFromPipelineAst -PipelineAst $Ast.Pipeline
            if ($null -ne $expr) {
                $result = (Test-StaticAstStringCompatible -Ast $expr -Context $Context -Depth ($Depth + 1))
            }
        } elseif ($Ast -is [System.Management.Automation.Language.SubExpressionAst]) {
            $statements = Get-StaticExpressionFromStatementBlock -StatementBlockAst $Ast.SubExpression
            if ($null -ne $statements -and $statements.Count -eq 1) {
                $expr = Get-StaticExpressionFromPipelineAst -PipelineAst $statements[0]
                if ($null -ne $expr) {
                    $result = (Test-StaticAstStringCompatible -Ast $expr -Context $Context -Depth ($Depth + 1))
                }
            }
        } elseif ($Ast -is [System.Management.Automation.Language.MemberExpressionAst] -or $Ast -is [System.Management.Automation.Language.IndexExpressionAst]) {
            $resolved = Resolve-StaticAstValue -Ast $Ast -Context $Context -AllowEmptyFallback:$false -Depth ($Depth + 1)
            if ($resolved.Success) {
                $result = (($resolved.Value -is [string]) -or ($resolved.Value -is [char]) -or ($resolved.Value -is [char[]]))
            }
        }

        if ($state -and $cacheKey) {
            $state.StringCompatCache[$cacheKey] = [bool]$result
        }

        return [bool]$result
    } finally {
        if ($state -and $cacheKey -and $addedToProgress) {
            $null = $state.StringCompatInProgress.Remove($cacheKey)
        }
    }
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

function Try-ConvertToByteArrayFromStaticValue {
    param($Value)

    if ($null -eq $Value) { return $null }
    if ($Value -is [psobject] -and $null -ne $Value.BaseObject -and $Value.BaseObject -ne $Value) {
        $Value = $Value.BaseObject
    }

    if ($Value -is [byte[]]) {
        return [byte[]]$Value
    }

    if (($Value -is [System.Collections.IEnumerable]) -and -not ($Value -is [string])) {
        $bytes = New-Object System.Collections.Generic.List[byte]
        foreach ($item in $Value) {
            try {
                $bytes.Add([byte]$item) | Out-Null
            } catch {
                return $null
            }
        }
        return $bytes.ToArray()
    }

    return $null
}

function Try-GetStaticByteArrayValueFromAst {
    param(
        $Ast,
        [hashtable]$Context
    )

    if ($null -eq $Ast) { return $null }

    $resolved = Resolve-StaticAstValue -Ast $Ast -Context $Context -AllowEmptyFallback:$false
    if (-not $resolved.Success) { return $null }

    return (Try-ConvertToByteArrayFromStaticValue -Value $resolved.Value)
}

function Try-DecodeCompressedScriptTextFromReadToEndAst {
    param(
        [System.Management.Automation.Language.InvokeMemberExpressionAst]$InvokeAst,
        [hashtable]$Context,
        [string]$CallText
    )

    if ($null -eq $InvokeAst) { return $null }
    if ([string]::IsNullOrWhiteSpace($CallText)) { return $null }
    if ($CallText -notmatch '(?i)(DeflateStream|GZipStream)') { return $null }

    $encodingName = if ($CallText -match '(?i)Encoding\]::UTF8') { 'utf8' } elseif ($CallText -match '(?i)Encoding\]::Unicode') { 'unicode' } else { 'ascii' }

    $base64Call = @($InvokeAst.FindAll({
                param($n)
                $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
                $n.Extent.Text -match '(?i)FromBase64String'
            }, $true) | Select-Object -First 1)
    if ($base64Call.Count -gt 0) {
        $base64Invoke = $base64Call[0]
        if ($base64Invoke.Arguments -and $base64Invoke.Arguments.Count -gt 0) {
            $base64String = Try-GetStaticStringValue -Ast $base64Invoke.Arguments[0] -Context $Context
            if (-not [string]::IsNullOrWhiteSpace($base64String)) {
                try {
                    $bytes = [Convert]::FromBase64String($base64String)
                } catch {
                    $bytes = $null
                }

                if ($bytes) {
                    $text = Try-DecodeCompressedScriptTextFromByteArray -Bytes $bytes -EncodingName $encodingName
                    if (-not [string]::IsNullOrWhiteSpace($text) -and (Test-PowerShellSyntax -ScriptText $text).IsValid) {
                        return $text
                    }
                }
            }
        }
    }

    $byteArrayAsts = @($InvokeAst.FindAll({
                param($n)
                if ($n -is [System.Management.Automation.Language.ConvertExpressionAst]) {
                    $typeName = Get-StaticConvertTypeName -ConvertAst $n
                    return ($typeName -and $typeName -match '^(?i:byte\[\])$')
                }
                return ($n -is [System.Management.Automation.Language.ArrayLiteralAst] -or $n -is [System.Management.Automation.Language.ArrayExpressionAst])
            }, $true))

    foreach ($byteAst in $byteArrayAsts) {
        $bytes = Try-GetStaticByteArrayValueFromAst -Ast $byteAst -Context $Context
        if (-not $bytes -or $bytes.Length -eq 0) { continue }

        $text = Try-DecodeCompressedScriptTextFromByteArray -Bytes $bytes -EncodingName $encodingName
        if (-not [string]::IsNullOrWhiteSpace($text) -and (Test-PowerShellSyntax -ScriptText $text).IsValid) {
            return $text
        }
    }

    return $null
}

function Try-GetStaticStringValue {
    param(
        $Ast,
        [hashtable]$Context
    )

    if ($null -eq $Ast) { return $null }

    $resolved = Resolve-StaticAstValue -Ast $Ast -Context $Context -AllowEmptyFallback:$false
    if (-not $resolved.Success) { return $null }

    $value = $resolved.Value
    if ($value -is [psobject] -and $null -ne $value.BaseObject -and $value.BaseObject -ne $value) {
        $value = $value.BaseObject
    }

    if ($value -is [string]) {
        return [string]$value
    }
    if ($value -is [char]) {
        return [string]$value
    }
    if ($value -is [char[]]) {
        return (-join $value)
    }

    return $null
}

function Try-DecodeCompressedScriptTextFromByteArray {
    param(
        [byte[]]$Bytes,
        [string]$EncodingName = 'ascii'
    )

    if (-not $Bytes -or $Bytes.Length -eq 0) { return $null }

    try {
        $inputStream = [System.IO.MemoryStream]::new($Bytes, $false)
        try {
            try {
                $zipStream = [System.IO.Compression.DeflateStream]::new($inputStream, [System.IO.Compression.CompressionMode]::Decompress, $true)
            } catch {
                $inputStream.Position = 0
                $zipStream = [System.IO.Compression.GZipStream]::new($inputStream, [System.IO.Compression.CompressionMode]::Decompress, $true)
            }

            try {
                $outputStream = [System.IO.MemoryStream]::new()
                try {
                    $zipStream.CopyTo($outputStream)
                    $decodedBytes = $outputStream.ToArray()
                } finally {
                    $outputStream.Dispose()
                }
            } finally {
                $zipStream.Dispose()
            }
        } finally {
            $inputStream.Dispose()
        }

        if (-not $decodedBytes -or $decodedBytes.Length -eq 0) { return $null }

        $encoding = switch -Regex ($EncodingName) {
            '^(?i:utf-?8)$'   { [System.Text.Encoding]::UTF8; break }
            '^(?i:unicode|utf-?16|utf-?16le)$' { [System.Text.Encoding]::Unicode; break }
            default { [System.Text.Encoding]::ASCII; break }
        }

        $text = $encoding.GetString($decodedBytes)
        if ([string]::IsNullOrWhiteSpace($text)) { return $null }
        return $text
    } catch {
        return $null
    }
}

function Try-DecodeStaticScriptTextFromAst {
    param(
        $Ast,
        [hashtable]$Context
    )

    if ($null -eq $Ast) { return $null }

    $extentText = if ($Ast.PSObject.Properties['Extent'] -and $Ast.Extent) { [string]$Ast.Extent.Text } else { '' }

    if ($Ast -is [System.Management.Automation.Language.ConvertExpressionAst]) {
        $typeName = Get-StaticConvertTypeName -ConvertAst $Ast
        if ($typeName -and $typeName.ToLowerInvariant() -eq 'string') {
            $childDecoded = Try-DecodeStaticScriptTextFromAst -Ast $Ast.Child -Context $Context
            if (-not [string]::IsNullOrWhiteSpace($childDecoded)) {
                return $childDecoded
            }

            $value = Try-GetStaticStringValue -Ast $Ast.Child -Context $Context
            if (-not [string]::IsNullOrWhiteSpace($value) -and (Test-PowerShellSyntax -ScriptText $value).IsValid) {
                return $value
            }
        }
    }

    if ($extentText -match '(?i)\[char\]\s*\[\s*\]') {
        $resolved = Resolve-StaticAstValue -Ast $Ast -Context $Context -AllowEmptyFallback:$false
        if ($resolved.Success) {
            $value = $resolved.Value
            if ($value -is [psobject] -and $null -ne $value.BaseObject -and $value.BaseObject -ne $value) {
                $value = $value.BaseObject
            }

            $text = $null
            if ($value -is [char[]]) {
                $text = -join $value
            } elseif (($value -is [System.Collections.IEnumerable]) -and -not ($value -is [string])) {
                try {
                    $chars = @($value | ForEach-Object { [char]$_ })
                    $text = -join $chars
                } catch {
                    $text = $null
                }
            }

            if (-not [string]::IsNullOrWhiteSpace($text) -and (Test-PowerShellSyntax -ScriptText $text).IsValid) {
                return $text
            }
        }
    }

    $invokeAsts = @()
    if ($Ast -is [System.Management.Automation.Language.InvokeMemberExpressionAst]) {
        $invokeAsts = @($Ast)
    } elseif ($Ast.PSObject.Methods['FindAll']) {
        $invokeAsts = @($Ast.FindAll({
                param($n)
                $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst]
            }, $true))
    }

    foreach ($invokeAst in $invokeAsts) {
        $memberName = $null
        if ($invokeAst.Member -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
            $memberName = [string]$invokeAst.Member.Value
        } elseif ($invokeAst.Member) {
            $memberName = [string]$invokeAst.Member.Extent.Text
        }
        if ([string]::IsNullOrWhiteSpace($memberName)) { continue }

        if ($memberName -match '^(?i:ReadToEnd)$') {
            $callText = [string]$invokeAst.Extent.Text

            if ($callText -match '(?i)(DeflateStream|GZipStream)') {
                $decodedCompressedText = Try-DecodeCompressedScriptTextFromReadToEndAst -InvokeAst $invokeAst -Context $Context -CallText $callText
                if (-not [string]::IsNullOrWhiteSpace($decodedCompressedText)) {
                    return $decodedCompressedText
                }
            }

            if ($callText -match '(?i)SecureStringToGlobalAllocUnicode' -or $callText -match '(?i)PtrToStringUni') {
                $stringValue = Try-GetStaticStringValue -Ast $invokeAst -Context $Context
                if (-not [string]::IsNullOrWhiteSpace($stringValue) -and (Test-PowerShellSyntax -ScriptText $stringValue).IsValid) {
                    return $stringValue
                }
            }
        }
    }

    return $null
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

        if ($elem -is [System.Management.Automation.Language.CommandParameterAst]) {
            $paramInfo = Resolve-PowerShellHostLooseParameterInfo -ParameterName ([string]$elem.ParameterName)

            if ($paramInfo -and $paramInfo.DynamicType -eq 'EncodedCommand') {
                # 获取下一个元素（Base64 字符串）
                $valueElem = $null
                if ($elem.Argument) {
                    $valueElem = $elem.Argument
                } elseif ($i + 1 -lt $elements.Count) {
                    $valueElem = $elements[$i + 1]
                }

                if ($null -ne $valueElem) {
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
        [bool]$AllowEmptyFallback = $false,
        [int]$Depth = 0
    )

    if ($null -eq $Ast) {
        return New-StaticEvalFailureResult -Reason 'no_ast' -Message 'AST 为空'
    }

    if (Test-StaticEvalBudgetExceeded -Context $Context) {
        return New-StaticEvalFailureResult -Reason 'budget_exceeded' -Message '静态求值预算已耗尽'
    }

    $state = Get-StaticEvalState -Context $Context
    $depthLimit = if ($state -and $state.ContainsKey('ValueDepthLimit')) { [int]$state.ValueDepthLimit } else { 192 }
    if ($Depth -ge $depthLimit) {
        return New-StaticEvalFailureResult -Reason 'depth_limit' -Message ("静态求值递归过深（Depth={0}, Limit={1}）" -f $Depth, $depthLimit)
    }

    $cacheKey = Get-StaticAstCacheKey -Ast $Ast -AllowEmptyFallback:$AllowEmptyFallback -Prefix 'value'
    if ($state -and $cacheKey -and $state.ValueCache.ContainsKey($cacheKey)) {
        return $state.ValueCache[$cacheKey]
    }
    if ($state -and $cacheKey -and $state.ValueInProgress.Contains($cacheKey)) {
        return New-StaticEvalFailureResult -Reason 'cycle_detected' -Message '静态求值检测到循环引用'
    }

    $addedToProgress = $false
    if ($state -and $cacheKey) {
        $addedToProgress = $state.ValueInProgress.Add($cacheKey)
    }

    try {
        $result = $null

        if ($Ast -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
            $result = [PSCustomObject]@{ Success = $true; Value = $Ast.Value; UsedEmptyFallback = $false; Reason = $null; Message = $null }
        } elseif ($Ast -is [System.Management.Automation.Language.ConstantExpressionAst]) {
            $result = [PSCustomObject]@{ Success = $true; Value = $Ast.Value; UsedEmptyFallback = $false; Reason = $null; Message = $null }
        } elseif ($Ast -is [System.Management.Automation.Language.VariableExpressionAst]) {
            $result = Resolve-StaticVariableValue -Context $Context -Ast $Ast -AllowEmptyFallback:$AllowEmptyFallback
        } elseif ($Ast -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) {
            $text = [string]$Ast.Value
            $usedFallback = $false
            foreach ($nested in @($Ast.NestedExpressions)) {
                $nestedResult = Resolve-StaticAstValue -Ast $nested -Context $Context -AllowEmptyFallback:$true -Depth ($Depth + 1)
                if (-not $nestedResult.Success) {
                    $result = [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = $usedFallback; Reason = 'expandable_nested'; Message = $nestedResult.Message }
                    break
                }
                $usedFallback = ($usedFallback -or [bool]$nestedResult.UsedEmptyFallback)
                $replacementText = Convert-StaticInterpolatedValueToString -Value $nestedResult.Value
                $text = Replace-FirstOccurrence -Text $text -OldValue ([string]$nested.Extent.Text) -NewValue $replacementText
            }

            if (-not $result) {
                $result = [PSCustomObject]@{ Success = $true; Value = $text; UsedEmptyFallback = $usedFallback; Reason = $null; Message = $null }
            }
        } elseif ($Ast -is [System.Management.Automation.Language.ConvertExpressionAst]) {
            $typeName = Get-StaticConvertTypeName -ConvertAst $Ast
            $normalizedTypeName = if ($typeName) { $typeName.ToLowerInvariant() } else { $null }

            if ($Ast.Child -is [System.Management.Automation.Language.HashtableAst] -and $normalizedTypeName -eq 'ordered') {
                $result = Resolve-StaticHashtableLiteralValue -HashtableAst $Ast.Child -Context $Context -AllowEmptyFallback:$AllowEmptyFallback -Depth ($Depth + 1) -Ordered
            } elseif ($Ast.Child -is [System.Management.Automation.Language.HashtableAst] -and $normalizedTypeName -eq 'pscustomobject') {
                $hashResult = Resolve-StaticHashtableLiteralValue -HashtableAst $Ast.Child -Context $Context -AllowEmptyFallback:$AllowEmptyFallback -Depth ($Depth + 1) -Ordered
                if (-not $hashResult.Success) {
                    $result = [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = [bool]$hashResult.UsedEmptyFallback; Reason = 'convert_child'; Message = $hashResult.Message }
                } else {
                    $propertyMap = [ordered]@{}
                    foreach ($key in @($hashResult.Value.Keys)) {
                        $propertyMap[[string]$key] = $hashResult.Value[$key]
                    }
                    $result = [PSCustomObject]@{ Success = $true; Value = ([pscustomobject]$propertyMap); UsedEmptyFallback = [bool]$hashResult.UsedEmptyFallback; Reason = $null; Message = $null }
                }
            }

            if (-not $result) {
                $childAllowFallback = ($typeName -and $typeName.ToLowerInvariant() -eq 'string')
                $childResult = Resolve-StaticAstValue -Ast $Ast.Child -Context $Context -AllowEmptyFallback:$childAllowFallback -Depth ($Depth + 1)
                if (-not $childResult.Success) {
                    $result = [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = [bool]$childResult.UsedEmptyFallback; Reason = 'convert_child'; Message = $childResult.Message }
                } else {
                    $convertResult = Invoke-StaticConvertOperator -TypeName $typeName -Value $childResult.Value
                    if (-not $convertResult.Success) {
                        $result = [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = [bool]$childResult.UsedEmptyFallback; Reason = 'convert_failed'; Message = $convertResult.Message }
                    } else {
                        $result = [PSCustomObject]@{ Success = $true; Value = $convertResult.Value; UsedEmptyFallback = [bool]$childResult.UsedEmptyFallback; Reason = $null; Message = $null }
                    }
                }
            }
        } elseif ($Ast -is [System.Management.Automation.Language.HashtableAst]) {
            $result = Resolve-StaticHashtableLiteralValue -HashtableAst $Ast -Context $Context -AllowEmptyFallback:$AllowEmptyFallback -Depth ($Depth + 1)
        } elseif ($Ast -is [System.Management.Automation.Language.UnaryExpressionAst]) {
            $tokenName = [string]$Ast.TokenKind
            if ($tokenName -in @('PlusPlus', 'MinusMinus', 'PostfixPlusPlus', 'PostfixMinusMinus')) {
                $result = [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = $false; Reason = 'unsupported_unary'; Message = '不支持有副作用的一元操作' }
            } else {
                $childResult = Resolve-StaticAstValue -Ast $Ast.Child -Context $Context -AllowEmptyFallback:$false -Depth ($Depth + 1)
                if (-not $childResult.Success) {
                    $result = [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = [bool]$childResult.UsedEmptyFallback; Reason = 'unary_child'; Message = $childResult.Message }
                } else {
                    $operatorText = Get-StaticUnaryOperatorText -TokenKind $Ast.TokenKind
                    $unaryResult = Invoke-StaticUnaryOperator -OperatorText $operatorText -Value $childResult.Value
                    if (-not $unaryResult.Success) {
                        $result = [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = [bool]$childResult.UsedEmptyFallback; Reason = 'unary_failed'; Message = $unaryResult.Message }
                    } else {
                        $result = [PSCustomObject]@{ Success = $true; Value = $unaryResult.Value; UsedEmptyFallback = [bool]$childResult.UsedEmptyFallback; Reason = $null; Message = $null }
                    }
                }
            }
        } elseif ($Ast -is [System.Management.Automation.Language.BinaryExpressionAst]) {
            $operatorName = [string]$Ast.Operator
            $childAllowFallback = $false
            if ($operatorName -in @('Join', 'Format')) {
                $childAllowFallback = $true
            } elseif ($operatorName -eq 'Plus') {
                $childAllowFallback = (Test-StaticAstStringCompatible -Ast $Ast -Context $Context -Depth ($Depth + 1))
            }

            $leftResult = Resolve-StaticAstValue -Ast $Ast.Left -Context $Context -AllowEmptyFallback:$childAllowFallback -Depth ($Depth + 1)
            if (-not $leftResult.Success) {
                $result = [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = [bool]$leftResult.UsedEmptyFallback; Reason = 'binary_left'; Message = $leftResult.Message }
            } else {
                $rightResult = Resolve-StaticAstValue -Ast $Ast.Right -Context $Context -AllowEmptyFallback:$childAllowFallback -Depth ($Depth + 1)
                if (-not $rightResult.Success) {
                    $result = [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = ([bool]$leftResult.UsedEmptyFallback -or [bool]$rightResult.UsedEmptyFallback); Reason = 'binary_right'; Message = $rightResult.Message }
                } else {
                    $opText = Get-StaticBinaryOperatorText -BinaryAst $Ast
                    $binaryResult = Invoke-StaticBinaryOperator -OperatorText $opText -LeftValue $leftResult.Value -RightValue $rightResult.Value
                    if (-not $binaryResult.Success) {
                        $result = [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = ([bool]$leftResult.UsedEmptyFallback -or [bool]$rightResult.UsedEmptyFallback); Reason = 'binary_failed'; Message = $binaryResult.Message }
                    } else {
                        $result = [PSCustomObject]@{
                            Success = $true
                            Value = $binaryResult.Value
                            UsedEmptyFallback = ([bool]$leftResult.UsedEmptyFallback -or [bool]$rightResult.UsedEmptyFallback)
                            Reason = $null
                            Message = $null
                        }
                    }
                }
            }
        } elseif ($Ast -is [System.Management.Automation.Language.ParenExpressionAst]) {
            $expr = Get-StaticExpressionFromPipelineAst -PipelineAst $Ast.Pipeline
            if ($null -eq $expr) {
                $result = [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = $false; Reason = 'unsupported_paren'; Message = '括号表达式不是简单表达式' }
            } else {
                $result = Resolve-StaticAstValue -Ast $expr -Context $Context -AllowEmptyFallback:$AllowEmptyFallback -Depth ($Depth + 1)
            }
        } elseif ($Ast -is [System.Management.Automation.Language.SubExpressionAst]) {
            $statements = Get-StaticExpressionFromStatementBlock -StatementBlockAst $Ast.SubExpression
            if ($null -eq $statements) {
                $result = [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = $false; Reason = 'unsupported_subexpression'; Message = '子表达式包含 trap 或为空' }
            } else {
                $values = @()
                $usedFallback = $false
                foreach ($statement in $statements) {
                    $expr = Get-StaticExpressionFromPipelineAst -PipelineAst $statement
                    if ($null -eq $expr) {
                        $result = [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = $usedFallback; Reason = 'unsupported_pipeline'; Message = '子表达式包含暂不支持的语句类型' }
                        break
                    }
                    $exprResult = Resolve-StaticAstValue -Ast $expr -Context $Context -AllowEmptyFallback:$AllowEmptyFallback -Depth ($Depth + 1)
                    if (-not $exprResult.Success) {
                        $result = [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = ($usedFallback -or [bool]$exprResult.UsedEmptyFallback); Reason = 'subexpression_child'; Message = $exprResult.Message }
                        break
                    }
                    $usedFallback = ($usedFallback -or [bool]$exprResult.UsedEmptyFallback)
                    $values += ,$exprResult.Value
                }

                if (-not $result) {
                    if ($values.Count -eq 0) {
                        $result = [PSCustomObject]@{ Success = $true; Value = @(); UsedEmptyFallback = $usedFallback; Reason = $null; Message = $null }
                    } elseif ($values.Count -eq 1) {
                        $result = [PSCustomObject]@{ Success = $true; Value = $values[0]; UsedEmptyFallback = $usedFallback; Reason = $null; Message = $null }
                    } else {
                        $result = [PSCustomObject]@{ Success = $true; Value = @($values); UsedEmptyFallback = $usedFallback; Reason = $null; Message = $null }
                    }
                }
            }
        } elseif ($Ast -is [System.Management.Automation.Language.ArrayLiteralAst]) {
            $values = @()
            $usedFallback = $false
            foreach ($element in @($Ast.Elements)) {
                $itemResult = Resolve-StaticAstValue -Ast $element -Context $Context -AllowEmptyFallback:$AllowEmptyFallback -Depth ($Depth + 1)
                if (-not $itemResult.Success) {
                    $result = [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = ($usedFallback -or [bool]$itemResult.UsedEmptyFallback); Reason = 'array_literal_child'; Message = $itemResult.Message }
                    break
                }
                $usedFallback = ($usedFallback -or [bool]$itemResult.UsedEmptyFallback)
                $values += ,$itemResult.Value
            }

            if (-not $result) {
                $result = [PSCustomObject]@{ Success = $true; Value = @($values); UsedEmptyFallback = $usedFallback; Reason = $null; Message = $null }
            }
        } elseif ($Ast -is [System.Management.Automation.Language.ArrayExpressionAst]) {
            $statements = Get-StaticExpressionFromStatementBlock -StatementBlockAst $Ast.SubExpression
            if ($null -eq $statements) {
                $result = [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = $false; Reason = 'unsupported_array_expression'; Message = '数组表达式包含 trap 或为空' }
            } else {
                $values = @()
                $usedFallback = $false
                foreach ($statement in $statements) {
                    $expr = Get-StaticExpressionFromPipelineAst -PipelineAst $statement
                    if ($null -eq $expr) {
                        $result = [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = $usedFallback; Reason = 'unsupported_pipeline'; Message = '数组表达式包含暂不支持的语句类型' }
                        break
                    }
                    $exprResult = Resolve-StaticAstValue -Ast $expr -Context $Context -AllowEmptyFallback:$AllowEmptyFallback -Depth ($Depth + 1)
                    if (-not $exprResult.Success) {
                        $result = [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = ($usedFallback -or [bool]$exprResult.UsedEmptyFallback); Reason = 'array_expression_child'; Message = $exprResult.Message }
                        break
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

                if (-not $result) {
                    $result = [PSCustomObject]@{ Success = $true; Value = @($values); UsedEmptyFallback = $usedFallback; Reason = $null; Message = $null }
                }
            }
        } elseif ($Ast -is [System.Management.Automation.Language.InvokeMemberExpressionAst]) {
            $argResult = Convert-StaticMethodArguments -Arguments $Ast.Arguments -Context $Context -Depth ($Depth + 1)
            if (-not $argResult.Success) {
                $result = [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = [bool]$argResult.UsedEmptyFallback; Reason = 'invoke_args'; Message = $argResult.Message }
            } elseif ($Ast.Static) {
                $memberName = Get-StaticMemberNameText -MemberAst $Ast.Member -Context $Context
                $targetType = if ($Ast.Expression -is [System.Management.Automation.Language.TypeExpressionAst]) {
                    Resolve-StaticTypeFromTypeExpressionAst -TypeExpressionAst $Ast.Expression
                } else {
                    $null
                }

                if ([string]::IsNullOrWhiteSpace($memberName)) {
                    $result = [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = [bool]$argResult.UsedEmptyFallback; Reason = 'invoke_name'; Message = '静态方法名无法解析' }
                } elseif ($null -eq $targetType) {
                    $result = [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = [bool]$argResult.UsedEmptyFallback; Reason = 'invoke_type'; Message = '静态方法调用的类型无法解析' }
                } else {
                    $invokeResult = Resolve-StaticTypeMethodInvocationValue -TargetType $targetType -MemberName $memberName -Arguments $argResult.Values
                    if (-not $invokeResult.Success) {
                        $result = [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = [bool]$argResult.UsedEmptyFallback; Reason = 'invoke_failed'; Message = $invokeResult.Message }
                    } else {
                        $result = [PSCustomObject]@{ Success = $true; Value = $invokeResult.Value; UsedEmptyFallback = [bool]$argResult.UsedEmptyFallback; Reason = $null; Message = $null }
                    }
                }
            } else {
                $targetResult = Resolve-StaticAstValue -Ast $Ast.Expression -Context $Context -AllowEmptyFallback:$false -Depth ($Depth + 1)
                if (-not $targetResult.Success) {
                    $result = [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = ([bool]$targetResult.UsedEmptyFallback -or [bool]$argResult.UsedEmptyFallback); Reason = 'invoke_target'; Message = $targetResult.Message }
                } else {
                    $memberName = Get-StaticMemberNameText -MemberAst $Ast.Member -Context $Context
                    if ([string]::IsNullOrWhiteSpace($memberName)) {
                        $result = [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = ([bool]$targetResult.UsedEmptyFallback -or [bool]$argResult.UsedEmptyFallback); Reason = 'invoke_name'; Message = '方法名无法静态解析' }
                    } else {
                        $invokeResult = Resolve-StaticMethodInvocationValue -TargetValue $targetResult.Value -MemberName $memberName -Arguments $argResult.Values
                        if (-not $invokeResult.Success) {
                            $result = [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = ([bool]$targetResult.UsedEmptyFallback -or [bool]$argResult.UsedEmptyFallback); Reason = 'invoke_failed'; Message = $invokeResult.Message }
                        } else {
                            $result = [PSCustomObject]@{ Success = $true; Value = $invokeResult.Value; UsedEmptyFallback = ([bool]$targetResult.UsedEmptyFallback -or [bool]$argResult.UsedEmptyFallback); Reason = $null; Message = $null }
                        }
                    }
                }
            }
        } elseif ($Ast -is [System.Management.Automation.Language.MemberExpressionAst]) {
            if ($Ast.Static) {
                $memberName = Get-StaticMemberNameText -MemberAst $Ast.Member -Context $Context
                $targetType = if ($Ast.Expression -is [System.Management.Automation.Language.TypeExpressionAst]) {
                    Resolve-StaticTypeFromTypeExpressionAst -TypeExpressionAst $Ast.Expression
                } else {
                    $null
                }

                if ([string]::IsNullOrWhiteSpace($memberName)) {
                    $result = [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = $false; Reason = 'member_name'; Message = '成员名无法静态解析' }
                } elseif ($null -eq $targetType) {
                    $result = [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = $false; Reason = 'unsupported_static_member'; Message = '静态成员访问的类型无法解析' }
                } else {
                    $staticMemberResult = Resolve-StaticTypeMemberAccessValue -TargetType $targetType -MemberName $memberName
                    if (-not $staticMemberResult.Success) {
                        $result = [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = $false; Reason = 'unsupported_static_member'; Message = $staticMemberResult.Message }
                    } else {
                        $result = [PSCustomObject]@{ Success = $true; Value = $staticMemberResult.Value; UsedEmptyFallback = $false; Reason = $null; Message = $null }
                    }
                }
            } else {
                $targetResult = Resolve-StaticAstValue -Ast $Ast.Expression -Context $Context -AllowEmptyFallback:$false -Depth ($Depth + 1)
                if (-not $targetResult.Success) {
                    $result = [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = [bool]$targetResult.UsedEmptyFallback; Reason = 'member_target'; Message = $targetResult.Message }
                } else {
                    $memberName = Get-StaticMemberNameText -MemberAst $Ast.Member -Context $Context
                    if ([string]::IsNullOrWhiteSpace($memberName)) {
                        $result = [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = [bool]$targetResult.UsedEmptyFallback; Reason = 'member_name'; Message = '成员名无法静态解析' }
                    } else {
                        $memberResult = Resolve-StaticMemberAccessValue -TargetValue $targetResult.Value -MemberName $memberName
                        if (-not $memberResult.Success) {
                            $result = [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = [bool]$targetResult.UsedEmptyFallback; Reason = 'member_failed'; Message = $memberResult.Message }
                        } else {
                            $result = [PSCustomObject]@{ Success = $true; Value = $memberResult.Value; UsedEmptyFallback = [bool]$targetResult.UsedEmptyFallback; Reason = $null; Message = $null }
                        }
                    }
                }
            }
        } elseif ($Ast -is [System.Management.Automation.Language.IndexExpressionAst]) {
            $targetResult = Resolve-StaticAstValue -Ast $Ast.Target -Context $Context -AllowEmptyFallback:$false -Depth ($Depth + 1)
            if (-not $targetResult.Success) {
                $result = [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = [bool]$targetResult.UsedEmptyFallback; Reason = 'index_target'; Message = $targetResult.Message }
            } else {
                $indexResult = Resolve-StaticAstValue -Ast $Ast.Index -Context $Context -AllowEmptyFallback:$false -Depth ($Depth + 1)
                if (-not $indexResult.Success) {
                    $result = [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = ([bool]$targetResult.UsedEmptyFallback -or [bool]$indexResult.UsedEmptyFallback); Reason = 'index_value'; Message = $indexResult.Message }
                } else {
                    $accessResult = Resolve-StaticIndexAccessValue -TargetValue $targetResult.Value -IndexValue $indexResult.Value
                    if (-not $accessResult.Success) {
                        $result = [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = ([bool]$targetResult.UsedEmptyFallback -or [bool]$indexResult.UsedEmptyFallback); Reason = 'index_failed'; Message = $accessResult.Message }
                    } else {
                        $result = [PSCustomObject]@{
                            Success = $true
                            Value = $accessResult.Value
                            UsedEmptyFallback = ([bool]$targetResult.UsedEmptyFallback -or [bool]$indexResult.UsedEmptyFallback)
                            Reason = $null
                            Message = $null
                        }
                    }
                }
            }
        } elseif ($Ast -is [System.Management.Automation.Language.CommandAst]) {
            $decodedInfo = Try-DecodeEncodedCommand -CommandAst $Ast
            if ($decodedInfo) {
                $result = [PSCustomObject]@{
                    Success            = $true
                    Value              = $decodedInfo.ReplacementText
                    RawReplacementText = $decodedInfo.ReplacementText
                    UsedEmptyFallback  = $false
                    Reason             = $null
                    Message            = $null
                }
            } else {
                $result = [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = $false; Reason = 'unsupported_command'; Message = 'CommandAst 不是 EncodedCommand 调用' }
            }
        } else {
            $result = [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = $false; Reason = 'unsupported_ast'; Message = ('不支持的 AST 类型: ' + $Ast.GetType().Name) }
        }

        if ($state -and $cacheKey -and (Test-StaticEvalResultCacheable -Result $result)) {
            $state.ValueCache[$cacheKey] = $result
        }

        return $result
    } finally {
        if ($state -and $cacheKey -and $addedToProgress) {
            $null = $state.ValueInProgress.Remove($cacheKey)
        }
    }
}

function Get-ReplacementCandidatePriority {
    param($Candidate)

    if (-not $Candidate) { return 0 }
    $sourceKind = if ($Candidate.PSObject.Properties['SourceKind']) { [string]$Candidate.SourceKind } else { '' }
    $materializationKind = if ($Candidate.PSObject.Properties['MaterializationKind']) { [string]$Candidate.MaterializationKind } else { $null }
    $protectsInner = ($Candidate.PSObject.Properties['ProtectsInnerCandidates'] -and [bool]$Candidate.ProtectsInnerCandidates)
    $wholeScriptMaterialized = ($Candidate.PSObject.Properties['WholeScriptMaterialized'] -and [bool]$Candidate.WholeScriptMaterialized)
    if ($wholeScriptMaterialized) {
        return 520
    }
    if ($sourceKind -eq 'DynamicInvoke') {
        if ($protectsInner -and -not [string]::IsNullOrWhiteSpace($materializationKind)) { return 460 }
        if ($protectsInner) { return 440 }
        return 400
    }
    if ($sourceKind -eq 'LoaderMaterialized') { return 430 }
    if ($sourceKind -eq 'FunctionResult') {
        if ($protectsInner) { return 420 }
        return 390
    }
    if ($sourceKind -eq 'LiteralizedCommand') { return 380 }
    if ($sourceKind -eq 'VariableRead') { return 350 }
    if ($sourceKind -eq 'Static') {
        if ($Candidate.PSObject.Properties['UsedEmptyFallback'] -and [bool]$Candidate.UsedEmptyFallback) { return 100 }
        return 200
    }
    return 300
}

function Get-SyntaxGuardDropPriority {
    param($Candidate)

    if (-not $Candidate) { return 0 }

    $priority = Get-ReplacementCandidatePriority -Candidate $Candidate
    if ($Candidate.PSObject.Properties['WholeScriptMaterialized'] -and [bool]$Candidate.WholeScriptMaterialized) {
        return $priority + 200
    }
    $type = if ($Candidate.PSObject.Properties['Type']) { [string]$Candidate.Type } else { '' }

    switch ($type) {
        'VarRead' { return $priority - 250 }
        'Inline' { return $priority - 220 }
        'CommandName' { return $priority - 180 }
        'Binary' { return $priority - 150 }
        default { return $priority }
    }
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
        if ($replacement -eq '__BLOCKED_PLACEHOLDER__') {
            $skipped += New-SkipRecord -Reason 'literalized_blocked' -Message '安全命令折叠结果为占位符，保留原命令文本' -Item $baseItem
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

    $recordIndex = 0
    foreach ($rec in $Context.DynamicInvokeResults) {
        $recordIndex++
        if (-not $rec) { continue }

        $nodeId = if ($rec -is [hashtable]) { $rec['NodeId'] } else { $rec.NodeId }
        $node = if ($Context.CFG -and $nodeId) { Get-NodeById -CFG $Context.CFG -Id $nodeId } else { $null }
        $replacementValue = if ($rec -is [hashtable]) {
            if ($rec.ContainsKey('ReplacementText') -and $null -ne $rec['ReplacementText']) { $rec['ReplacementText'] } else { $rec['ArgumentValue'] }
        } else {
            if ($rec.PSObject.Properties['ReplacementText'] -and $null -ne $rec.ReplacementText) { $rec.ReplacementText } else { $rec.ArgumentValue }
        }
        $replacement = if ($null -ne $replacementValue) { [string]$replacementValue } else { $null }
        $preservedCommandText = if ($rec -is [hashtable]) {
            if ($rec.ContainsKey('PreservedCommandText') -and $null -ne $rec['PreservedCommandText']) { [string]$rec['PreservedCommandText'] } else { $null }
        } else {
            if ($rec.PSObject.Properties['PreservedCommandText'] -and $null -ne $rec.PreservedCommandText) { [string]$rec.PreservedCommandText } else { $null }
        }
        $materializationKind = if ($rec -is [hashtable]) {
            if ($rec.ContainsKey('MaterializationKind') -and $null -ne $rec['MaterializationKind']) { [string]$rec['MaterializationKind'] } else { $null }
        } else {
            if ($rec.PSObject.Properties['MaterializationKind'] -and $null -ne $rec.MaterializationKind) { [string]$rec.MaterializationKind } else { $null }
        }

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

        $originInfo = Resolve-DynamicInvokeOriginInfo -Context $Context -Record $rec -Node $node
        if (-not $originInfo.Success) {
            $skipReason = switch ([string]$originInfo.FailureReason) {
                'caller_node_missing' { 'caller_node_missing' }
                'runtime_origin_unmapped' { 'dynamic_runtime_unmapped' }
                'missing_offset' { 'dynamic_no_offset' }
                'node_missing' { 'dynamic_node_missing' }
                default { if (Test-RuntimeGeneratedNode -Node $node) { 'dynamic_runtime_unmapped' } else { 'dynamic_no_offset' } }
            }
            $skipMessage = switch ($skipReason) {
                'caller_node_missing' { '运行时子图的调用者节点缺失，无法映射回原脚本位点' }
                'dynamic_runtime_unmapped' { '运行时子图中的 DynamicInvoke 已有结果，但未能映射回原脚本位点' }
                'dynamic_node_missing' { "DynamicInvoke 节点不存在: NodeId=$nodeId" }
                default { 'DynamicInvoke 无原始 offset，跳过' }
            }
            $skipped += New-SkipRecord -Reason $skipReason -Message $skipMessage -Item $baseItem
            continue
        }

        $start = [int]$originInfo.StartOffset
        $end = [int]$originInfo.EndOffset
        $resolvedRange = Resolve-DynamicInvokeRangeAgainstCurrentScript -ScriptText $ScriptText -StartOffset $start -EndOffset $end -Node $node -Record $rec
        if (-not $resolvedRange.Success) {
            $skipped += New-SkipRecord -Reason 'dynamic_out_of_range' -Message "DynamicInvoke offset 无法映射到当前脚本文本: [$start-$end], len=$($ScriptText.Length)" -Item $baseItem
            continue
        }

        $start = [int]$resolvedRange.StartOffset
        $end = [int]$resolvedRange.EndOffset
        if ($null -eq $start -or $null -eq $end) {
            $skipped += New-SkipRecord -Reason 'dynamic_no_offset' -Message 'DynamicInvoke 无原始 offset，跳过' -Item $baseItem
            continue
        }
        if ($start -lt 0 -or $end -le $start -or $end -gt $ScriptText.Length) {
            $skipped += New-SkipRecord -Reason 'dynamic_out_of_range' -Message "DynamicInvoke offset 越界: [$start-$end], len=$($ScriptText.Length)" -Item $baseItem
            continue
        }

        if ($replacement -eq '__BLOCKED_PLACEHOLDER__' -and -not [string]::IsNullOrWhiteSpace($preservedCommandText)) {
            $replacement = $preservedCommandText
        }
        if ([string]::IsNullOrWhiteSpace($replacement)) {
            $skipped += New-SkipRecord -Reason 'dynamic_empty' -Message 'DynamicInvoke 解析结果为空，跳过' -Item $baseItem
            continue
        }
        if ($replacement -eq '__BLOCKED_PLACEHOLDER__') {
            $skipped += New-SkipRecord -Reason 'dynamic_blocked' -Message 'DynamicInvoke 结果为占位符，保留原命令文本' -Item $baseItem
            continue
        }

        $original = $ScriptText.Substring($start, $end - $start)
        if ($original -eq $replacement) {
            $skipped += New-SkipRecord -Reason 'dynamic_outer_candidate_ineffective' -Message 'DynamicInvoke replacement 与原片段一致，外层候选不参与压制内层候选' -Item $baseItem
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
            OriginStartOffset = $start
            OriginEndOffset = $end
            OriginRangeKey = (Get-ReplacementRangeKey -StartOffset $start -EndOffset $end)
            OriginNodeId = [int]$originInfo.NodeId
            OriginRuntimeDepth = [int]$originInfo.RuntimeDepth
            IsOriginMappedFromRuntime = [bool]$originInfo.ViaRuntime
            OriginResolutionMode = [string]$resolvedRange.ResolutionMode
            DynamicRecordIndex = $recordIndex
            ProtectsInnerCandidates = $true
            MaterializationKind = $materializationKind
            DynamicStopReason = if ($rec -is [hashtable]) { [string]$rec['StopReason'] } else { [string]$rec.StopReason }
            DynamicStopMessage = if ($rec -is [hashtable]) { [string]$rec['StopMessage'] } else { [string]$rec.StopMessage }
        }
    }

    $merged = Merge-DynamicInvokeReplacementCandidates -Candidates $candidates -ScriptText $ScriptText
    return [PSCustomObject]@{
        Candidates = @($merged.Candidates)
        Skipped    = @($skipped) + @($merged.Skipped)
    }
}

function Get-FunctionInvokeReplacementCandidates {
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][string]$ScriptText
    )

    $candidates = @()
    $skipped = @()

    if (-not $Context.FunctionInvokeResults -or $Context.FunctionInvokeResults.Count -eq 0) {
        return [PSCustomObject]@{
            Candidates = @()
            Skipped    = @()
        }
    }

    foreach ($rec in @($Context.FunctionInvokeResults)) {
        if (-not $rec) { continue }

        $start = if ($rec -is [hashtable]) { $rec['StartOffset'] } else { $rec.StartOffset }
        $end = if ($rec -is [hashtable]) { $rec['EndOffset'] } else { $rec.EndOffset }
        $nodeId = if ($rec -is [hashtable]) { $rec['NodeId'] } else { $rec.NodeId }
        $funcName = if ($rec -is [hashtable]) { [string]$rec['FunctionName'] } else { [string]$rec.FunctionName }
        $replacement = if ($rec -is [hashtable]) { [string]$rec['ReplacementText'] } else { [string]$rec.ReplacementText }

        $baseItem = [PSCustomObject]@{
            StartOffset = $start
            EndOffset   = $end
            Type        = 'FunctionInvoke'
            Depth       = $null
            NodeId      = $nodeId
        }

        if ($null -eq $start -or $null -eq $end) {
            $skipped += New-SkipRecord -Reason 'function_result_no_offset' -Message "函数返回值无 offset，跳过: $funcName" -Item $baseItem
            continue
        }
        if ($start -lt 0 -or $end -le $start -or $end -gt $ScriptText.Length) {
            $skipped += New-SkipRecord -Reason 'function_result_out_of_range' -Message "函数返回值 offset 越界: [$start-$end]" -Item $baseItem
            continue
        }
        if ([string]::IsNullOrWhiteSpace($replacement) -or $replacement -eq '__BLOCKED_PLACEHOLDER__') {
            $skipped += New-SkipRecord -Reason 'function_result_empty' -Message "函数返回值为空或被阻断，跳过: $funcName" -Item $baseItem
            continue
        }

        $original = $ScriptText.Substring([int]$start, ([int]$end - [int]$start))
        if ($original -eq $replacement) {
            $skipped += New-SkipRecord -Reason 'function_result_no_change' -Message "函数返回值 replacement 与原片段一致，跳过: $funcName" -Item $baseItem
            continue
        }

        $candidates += [PSCustomObject]@{
            StartOffset = [int]$start
            EndOffset   = [int]$end
            Replacement = $replacement
            Original    = $original
            Type        = 'FunctionInvoke'
            Depth       = $null
            NodeId      = $nodeId
            SourceKind  = 'FunctionResult'
            Confidence  = 'High'
            UsedEmptyFallback = $false
            ResultType  = 'FunctionResult'
            Executed    = $true
            ProtectsInnerCandidates = $true
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
    if ($ScriptText -notmatch '(?i)(DeflateStream|ReadToEnd|ToInt16|FromBase64String|-bxor|\[char\]|ConvertTo-SecureString|PSCredential|GetNetworkCredential|SecureStringToGlobalAlloc|PtrToString)') {
        return [PSCustomObject]@{ Candidates = @(); Skipped = @() }
    }

    $parse = Get-ScriptParseInfo -ScriptText $ScriptText
    if (-not $parse.IsValid -or -not $parse.Ast) {
        return [PSCustomObject]@{ Candidates = @(); Skipped = @() }
    }

    $statement = Get-FirstStatementFromScriptAst -ScriptAst $parse.Ast
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
                    $wrapped = $null
                    try {
                        $wrapped = Get-CommandAstWrappedDynamicInvocationInfo -CommandAst $last -Context $Context
                    } catch {
                        $wrapped = [PSCustomObject]@{
                            Success = $false
                            DynamicType = $null
                            ArgumentStartIndex = $null
                        }
                    }
                    $cmdName = Convert-DynamicCommandCandidateToName -Value $last.GetCommandName()
                    if ($wrapped.Success -and $wrapped.DynamicType -eq 'IEX') {
                        $payloadText = Get-CommandArgumentText -CommandAst $last -ParseInfo $parse -FirstArgumentIndex $wrapped.ArgumentStartIndex
                        $dynamicType = 'IEX'
                    } elseif ($cmdName -in @('Invoke-Expression', 'iex')) {
                        $payloadText = Get-CommandArgumentText -CommandAst $last -ParseInfo $parse
                        $dynamicType = 'IEX'
                    }
                }
            }
        }
    } elseif ($statement -is [System.Management.Automation.Language.CommandAst]) {
        $wrapped = $null
        try {
            $wrapped = Get-CommandAstWrappedDynamicInvocationInfo -CommandAst $statement -Context $Context
        } catch {
            $wrapped = [PSCustomObject]@{
                Success = $false
                DynamicType = $null
                ArgumentStartIndex = $null
            }
        }
        $cmdName = Convert-DynamicCommandCandidateToName -Value $statement.GetCommandName()
        if ($wrapped.Success -and $wrapped.DynamicType -eq 'IEX') {
            $payloadText = Get-CommandArgumentText -CommandAst $statement -ParseInfo $parse -FirstArgumentIndex $wrapped.ArgumentStartIndex
            $dynamicType = 'IEX'
        } elseif ($cmdName -in @('Invoke-Expression', 'iex')) {
            $payloadText = Get-CommandArgumentText -CommandAst $statement -ParseInfo $parse
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
        $skipped += New-SkipRecord -Reason 'dynamic_loader_eval_failed' -Message $(if ($evalResult -and $evalResult.Error) { [string]$evalResult.Error } else { 'dynamic loader evaluation failed' }) -Item ([PSCustomObject]@{
                StartOffset = [int]$statement.Extent.StartOffset
                EndOffset = [int]$statement.Extent.EndOffset
                Type = 'DynamicInvoke'
                Depth = $null
                NodeId = $null
            })
        return [PSCustomObject]@{ Candidates = @(); Skipped = @($skipped) }
    }

    $normalizedValue = Normalize-ExecutionResultValue -Value $evalResult.Result -TreatArraysAsSequence
    $materialized = Convert-DynamicInvocationValueToScriptText -Value $normalizedValue
    if (-not $materialized.Success -or [string]::IsNullOrWhiteSpace([string]$materialized.Text)) {
        return [PSCustomObject]@{ Candidates = @(); Skipped = @($skipped) }
    }

    $replacement = [string]$materialized.Text
    $start = [int]$statement.Extent.StartOffset
    $end = [int]$statement.Extent.EndOffset
    $original = $ScriptText.Substring($start, $end - $start)
    if ($original -eq $replacement) {
        return [PSCustomObject]@{ Candidates = @(); Skipped = @($skipped) }
    }

    $candidates += [PSCustomObject]@{
        StartOffset = $start
        EndOffset   = $end
        Replacement = $replacement
        Original    = $original
        Type        = 'DynamicInvoke'
        Depth       = $null
        NodeId      = $null
        SourceKind  = 'LoaderMaterialized'
        Confidence  = 'High'
        UsedEmptyFallback = $false
        ResultType  = 'String'
        Executed    = $true
        ProtectsInnerCandidates = $true
        WholeScriptMaterialized = $true
        MaterializationKind = $materialized.Kind
        DynamicStopReason = "WholeScriptLoader:$dynamicType"
        DynamicStopMessage = "Recovered whole-script dynamic loader via $($materialized.Kind)"
    }

    return [PSCustomObject]@{
        Candidates = @($candidates)
        Skipped    = @($skipped)
    }
}

function Get-PreferredDynamicReplacementCandidate {
    param(
        [Parameter(Mandatory)]$Left,
        [Parameter(Mandatory)]$Right
    )

    $leftDepth = if ($Left.PSObject.Properties['OriginRuntimeDepth']) { [int]$Left.OriginRuntimeDepth } else { 0 }
    $rightDepth = if ($Right.PSObject.Properties['OriginRuntimeDepth']) { [int]$Right.OriginRuntimeDepth } else { 0 }
    if ($leftDepth -ne $rightDepth) {
        return $(if ($rightDepth -gt $leftDepth) { $Right } else { $Left })
    }

    $leftIndex = if ($Left.PSObject.Properties['DynamicRecordIndex']) { [int]$Left.DynamicRecordIndex } else { 0 }
    $rightIndex = if ($Right.PSObject.Properties['DynamicRecordIndex']) { [int]$Right.DynamicRecordIndex } else { 0 }
    if ($leftIndex -ne $rightIndex) {
        return $(if ($rightIndex -gt $leftIndex) { $Right } else { $Left })
    }

    $leftRuntime = if ($Left.PSObject.Properties['IsOriginMappedFromRuntime']) { [bool]$Left.IsOriginMappedFromRuntime } else { $false }
    $rightRuntime = if ($Right.PSObject.Properties['IsOriginMappedFromRuntime']) { [bool]$Right.IsOriginMappedFromRuntime } else { $false }
    if ($leftRuntime -ne $rightRuntime) {
        return $(if ($rightRuntime) { $Right } else { $Left })
    }

    $leftLen = if ($Left.PSObject.Properties['Replacement'] -and $null -ne $Left.Replacement) { ([string]$Left.Replacement).Length } else { 0 }
    $rightLen = if ($Right.PSObject.Properties['Replacement'] -and $null -ne $Right.Replacement) { ([string]$Right.Replacement).Length } else { 0 }
    if ($leftLen -ne $rightLen) {
        return $(if ($rightLen -gt $leftLen) { $Right } else { $Left })
    }

    return $Left
}

function Test-ReplacementCandidateSyntaxValidity {
    param(
        [Parameter(Mandatory)][string]$ScriptText,
        [Parameter(Mandatory)]$Candidate
    )

    if (-not $Candidate) { return $false }
    if ($null -eq $Candidate.StartOffset -or $null -eq $Candidate.EndOffset) { return $false }

    $start = [int]$Candidate.StartOffset
    $end = [int]$Candidate.EndOffset
    if ($start -lt 0 -or $end -le $start -or $end -gt $ScriptText.Length) { return $false }

    $candidateText = $ScriptText.Substring(0, $start) + [string]$Candidate.Replacement + $ScriptText.Substring($end)
    return (Test-PowerShellSyntax -ScriptText $candidateText).IsValid
}

function Copy-ReplacementCandidate {
    param($Candidate)

    if (-not $Candidate) { return $null }

    $copy = [PSCustomObject]@{}
    foreach ($prop in $Candidate.PSObject.Properties) {
        $copy | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value -Force
    }
    return $copy
}

function Convert-ReplacementTextToExpressionLiteral {
    param([string]$Text)

    if ($null -eq $Text) { return "''" }
    if ($Text -match "[`r`n]") {
        return ConvertTo-SingleQuotedHereStringLiteral -Text $Text
    }
    return ConvertTo-SingleQuotedStringLiteral -Text $Text
}

function Get-SyntaxAdaptedReplacementCandidate {
    param(
        [Parameter(Mandatory)][string]$ScriptText,
        [Parameter(Mandatory)][array]$CurrentSelected,
        [Parameter(Mandatory)]$Candidate
    )

    if (-not $Candidate) { return $null }
    if ($Candidate.PSObject.Properties['WholeScriptMaterialized'] -and [bool]$Candidate.WholeScriptMaterialized) { return $null }

    $candidateType = if ($Candidate.PSObject.Properties['Type']) { [string]$Candidate.Type } else { '' }
    if ($candidateType -in @('CommandName', 'LiteralizedCommand', 'VarRead', 'Inline')) { return $null }

    $replacementText = if ($Candidate.PSObject.Properties['Replacement']) { [string]$Candidate.Replacement } else { $null }
    if ([string]::IsNullOrWhiteSpace($replacementText)) { return $null }
    if ($replacementText -match "^\s*'(.|'')*'\s*$") { return $null }
    if ($replacementText -match "^\s*@'") { return $null }

    if (Test-ReplacementCandidateSyntaxValidity -ScriptText $ScriptText -Candidate $Candidate) {
        return $null
    }

    $adapted = Copy-ReplacementCandidate -Candidate $Candidate
    $adapted.Replacement = Convert-ReplacementTextToExpressionLiteral -Text $replacementText
    if ([string]$adapted.Replacement -eq $replacementText) { return $null }
    if (-not (Test-ReplacementCandidateSyntaxValidity -ScriptText $ScriptText -Candidate $adapted)) {
        return $null
    }

    $candidateId = Get-ReplacementIdentity -Replacement $Candidate
    $adaptedSet = @()
    foreach ($item in $CurrentSelected) {
        if ((Get-ReplacementIdentity -Replacement $item) -eq $candidateId) {
            $adaptedSet += $adapted
        } else {
            $adaptedSet += $item
        }
    }

    $fullText = Apply-ReplacementsToText -Text $ScriptText -Replacements $adaptedSet
    $fullCheck = Test-PowerShellSyntax -ScriptText $fullText
    if (-not $fullCheck.IsValid) {
        return $null
    }

    return $adapted
}

function Merge-DynamicInvokeReplacementCandidates {
    param(
        [array]$Candidates,
        [string]$ScriptText
    )

    if (-not $Candidates -or $Candidates.Count -eq 0) {
        return [PSCustomObject]@{ Candidates = @(); Skipped = @() }
    }

    $map = @{}
    $skipped = @()
    foreach ($cand in @($Candidates | Sort-Object StartOffset, EndOffset, DynamicRecordIndex)) {
        if (-not $cand) { continue }

        $key = Get-ReplacementRangeKey -StartOffset $cand.StartOffset -EndOffset $cand.EndOffset
        if ([string]::IsNullOrWhiteSpace($key)) { continue }

        if (-not $map.ContainsKey($key)) {
            $map[$key] = $cand
            continue
        }

        $existing = $map[$key]
        $preferred = Get-PreferredDynamicReplacementCandidate -Left $existing -Right $cand
        if (-not [string]::IsNullOrWhiteSpace($ScriptText) -and [string]$existing.Replacement -ne [string]$cand.Replacement) {
            $preferredIsValid = Test-ReplacementCandidateSyntaxValidity -ScriptText $ScriptText -Candidate $preferred
            if (-not $preferredIsValid) {
                $alternate = if ($preferred -eq $existing) { $cand } else { $existing }
                if (Test-ReplacementCandidateSyntaxValidity -ScriptText $ScriptText -Candidate $alternate) {
                    $preferred = $alternate
                }
            }
        }
        $dropped = if ($preferred -eq $existing) { $cand } else { $existing }
        if ($preferred -ne $existing) {
            $map[$key] = $preferred
        }

        $reason = if ([string]$existing.Replacement -eq [string]$cand.Replacement) { 'duplicate' } else { 'dynamic_same_range_preferred' }
        $message = if ($reason -eq 'duplicate') {
            "DynamicInvoke 同区间重复记录，已去重: [$($cand.StartOffset)-$($cand.EndOffset)]"
        } else {
            '同区间 DynamicInvoke 候选冲突，保留更深或更新的候选'
        }
        $skipped += New-SkipRecord -Reason $reason -Message $message -Item $dropped
    }

    return [PSCustomObject]@{
        Candidates = @($map.Values | Sort-Object StartOffset, EndOffset)
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

    $dynamicCandidates = @($Candidates | Where-Object { [string]$_.SourceKind -in @('DynamicInvoke', 'LoaderMaterialized', 'FunctionResult') })
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
        if ([string]$cand.SourceKind -in @('DynamicInvoke', 'LoaderMaterialized', 'FunctionResult')) {
            $kept += $cand
            continue
        }

        $coveringDynamic = $dynamicCandidates | Where-Object {
            $_.StartOffset -le $cand.StartOffset -and
            $_.EndOffset -ge $cand.EndOffset -and
            (Test-EffectiveDynamicReplacementCandidate -Candidate $_) -and
            ($_.PSObject.Properties['ProtectsInnerCandidates'] -and [bool]$_.ProtectsInnerCandidates) -and
            (Get-ReplacementCandidatePriority -Candidate $_) -gt (Get-ReplacementCandidatePriority -Candidate $cand)
        } | Sort-Object StartOffset, @{ Expression = { $_.EndOffset - $_.StartOffset } } | Select-Object -First 1

        if ($coveringDynamic) {
            $skipped += New-SkipRecord -Reason 'dynamic_preferred_outer_effective' -Message '外层 DynamicInvoke 候选有效，内层候选被更高优先级整段替换覆盖' -Item $cand
            continue
        }

        $kept += $cand
    }

    return [PSCustomObject]@{
        Candidates = @($kept)
        Skipped    = @($skipped)
    }
}

function Test-StaticLowConfidenceCandidateAutoApply {
    param(
        $Candidate,
        [Parameter(Mandatory)][string]$ScriptText,
        [Parameter(Mandatory)][hashtable]$Context,
        $ContextInfo = $null
    )

    if (-not $Candidate) { return $false }
    if (-not $Candidate.PSObject.Properties['SourceKind'] -or [string]$Candidate.SourceKind -ne 'Static') { return $false }
    if (-not $Candidate.PSObject.Properties['UsedEmptyFallback'] -or -not [bool]$Candidate.UsedEmptyFallback) { return $true }

    if ($null -eq $ContextInfo) {
        $ContextInfo = Get-ReplacementContextInfoFromScriptText -ScriptText $ScriptText
    }

    $start = if ($Candidate.PSObject.Properties['StartOffset']) { [int]$Candidate.StartOffset } else { $null }
    $end = if ($Candidate.PSObject.Properties['EndOffset']) { [int]$Candidate.EndOffset } else { $null }
    $rangeKey = Get-ReplacementRangeKey -StartOffset $start -EndOffset $end
    $replacement = if ($Candidate.PSObject.Properties['Replacement']) { [string]$Candidate.Replacement } else { $null }
    $original = if ($Candidate.PSObject.Properties['Original']) {
        [string]$Candidate.Original
    } elseif ($null -ne $start -and $null -ne $end -and $start -ge 0 -and $end -gt $start -and $end -le $ScriptText.Length) {
        $ScriptText.Substring($start, $end - $start)
    } else {
        $null
    }

    if ($rangeKey -and $ContextInfo.CommandNameRangeKeys.ContainsKey($rangeKey)) { return $true }
    if ($null -ne $start -and $null -ne $end -and (Test-ReplacementWithinRanges -StartOffset $start -EndOffset $end -Ranges $ContextInfo.DynamicPayloadRanges)) { return $true }
    if ($replacement -match '^(?i:https?|ftp)://\S+$') { return $true }

    $trim = if ($null -ne $replacement) { $replacement.Trim() } else { '' }
    if ($trim.StartsWith('{') -and $trim.EndsWith('}')) {
        $check = Test-PowerShellSyntax -ScriptText $trim
        if ($check.IsValid) { return $true }
    }

    if (([string]$original -match '(?i)(FromBase64String|EncodedCommand|DeflateStream|GZipStream|ScriptBlock\]::Create|NewScriptBlock|IEX|Invoke-Expression)') -and
        -not [string]::IsNullOrWhiteSpace($replacement)) {
        return $true
    }

    return $false
}

function Get-StaticReplacementCandidates {
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][string]$ScriptText,
        [int]$TimeBudgetMs = 0
    )

    $candidates = @()
    $skipped = @()
    $nodes = @()
    $budgetExceeded = $false
    if ($Context -and $Context.CFG -and $Context.CFG.Nodes) {
        $nodes = @($Context.CFG.Nodes | Sort-Object Id)
    }
    $null = Reset-StaticEvalState -Context $Context -TimeBudgetMs $TimeBudgetMs

    foreach ($node in $nodes) {
        if (Test-StaticEvalBudgetExceeded -Context $Context) {
            $skipped += New-SkipRecord -Reason 'static_budget_exceeded' -Message '静态候选阶段预算已耗尽，停止继续扫描。' -Item $null
            $budgetExceeded = $true
            break
        }
        if (-not $node -or -not $node.Resolvables) {
            continue
        }
        $nodeId = [int]$node.Id

        # 注意：静态求值不应该受节点访问状态影响
        # 即使节点被执行过，静态可解析的表达式仍然应该被处理

        foreach ($r in @($node.Resolvables)) {
            if (Test-StaticEvalBudgetExceeded -Context $Context) {
                $skipped += New-SkipRecord -Reason 'static_budget_exceeded' -Message '静态候选阶段预算已耗尽，停止继续扫描。' -Item $null
                $budgetExceeded = $true
                break
            }
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

            try {
                $decodedScriptText = Try-DecodeStaticScriptTextFromAst -Ast $r.Ast -Context $Context
                if (-not [string]::IsNullOrWhiteSpace($decodedScriptText)) {
                    $replacement = $decodedScriptText
                    $original = $ScriptText.Substring($start, $end - $start)
                    if ($original -eq $replacement) {
                        $skipped += New-SkipRecord -Reason 'static_no_change' -Message '静态整段解码结果与原片段一致' -Item $baseItem
                        continue
                    }

                    $candidates += [PSCustomObject]@{
                        StartOffset = $start
                        EndOffset = $end
                        Replacement = $replacement
                        Original = $original
                        Type = $r.Type
                        Depth = $r.Depth
                        NodeId = $nodeId
                        SourceKind = 'Static'
                        Confidence = 'High'
                        UsedEmptyFallback = $false
                        ResultType = 'DecodedScriptText'
                        Executed = $false
                        VariableName = $null
                        IsSimpleVariable = $false
                        IsValueChanged = $false
                        ObservedValueCount = 1
                    }
                    continue
                }

                $resolved = Resolve-StaticAstValue -Ast $r.Ast -Context $Context -AllowEmptyFallback:$false
                if (-not $resolved.Success) {
                    $message = if ([string]::IsNullOrWhiteSpace([string]$resolved.Message)) { '静态求值失败' } else { [string]$resolved.Message }
                    $reason = if ([string]$resolved.Reason -eq 'budget_exceeded') { 'static_budget_exceeded' } else { 'static_eval_failed' }
                    $skipped += New-SkipRecord -Reason $reason -Message $message -Item $baseItem
                    if ([string]$resolved.Reason -eq 'budget_exceeded') {
                        $budgetExceeded = $true
                        break
                    }
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
            } catch {
                $ex = $_.Exception
                $message = if ($ex) { "{0}: {1}" -f $ex.GetType().Name, $ex.Message } else { [string]$_ }
                $skipped += New-SkipRecord -Reason 'static_exception' -Message ('静态候选异常，已跳过: ' + $message) -Item $baseItem
                continue
            }
        }

        if ($budgetExceeded) {
            break
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
        if (Test-FormattingOnlyEquivalentReplacement -Original $original -Replacement $replacement -Type $type) {
            $skipped += New-SkipRecord -Reason 'formatting_only' -Message 'replacement 仅改变集合包装格式，跳过以避免来回震荡' -Item $baseItem
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
            $varName = if ($v.PSObject.Properties['Name']) { [string]$v.Name } else { $null }

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

            if ($type -eq 'VarRead' -and $varName -in @('PSScriptRoot', 'PSCommandPath', 'MyInvocation')) {
                $skipped += New-SkipRecord -Reason 'host_scoped_variable' -Message "宿主相关自动变量 `$${varName} 不直接回写，保留原始引用" -Item $baseItem
                continue
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

    $sorted = if ($Strategy -eq 'Outer') {
        $Candidates | Sort-Object `
            @{ Expression = { Get-ReplacementCandidatePriority -Candidate $_ }; Descending = $true }, `
            @{ Expression = { if ($_.PSObject.Properties['ProtectsInnerCandidates'] -and [bool]$_.ProtectsInnerCandidates) { 1 } else { 0 } }; Descending = $true }, `
            StartOffset, `
            @{ Expression = 'EndOffset'; Descending = $true }
    } else {
        $Candidates | Sort-Object `
            @{ Expression = { Get-ReplacementCandidatePriority -Candidate $_ }; Descending = $true }, `
            @{ Expression = { if ($_.PSObject.Properties['ProtectsInnerCandidates'] -and [bool]$_.ProtectsInnerCandidates) { 1 } else { 0 } }; Descending = $true }, `
            EndOffset, `
            @{ Expression = 'StartOffset'; Descending = $true }
    }

    foreach ($c in $sorted) {
        $conflict = $selected | Where-Object {
            $_.StartOffset -lt $c.EndOffset -and $c.StartOffset -lt $_.EndOffset
        } | Select-Object -First 1

        if (-not $conflict) {
            $selected += $c
            continue
        }

        $skipReason = if (($c.PSObject.Properties['SourceKind'] -and [string]$c.SourceKind -in @('DynamicInvoke', 'LoaderMaterialized')) -or
            ($c.PSObject.Properties['ProtectsInnerCandidates'] -and [bool]$c.ProtectsInnerCandidates)) {
            'overlap_retained_higher_priority'
        } else {
            'overlap'
        }
        $skipMessage = if ($skipReason -eq 'overlap_retained_higher_priority') {
            '与已选高优先级整段候选重叠，丢弃当前片段'
        } elseif ($Strategy -eq 'Outer') {
            '与已选片段重叠（Outer 策略丢弃内层/后续）'
        } else {
            '与已选片段重叠（Inner 策略丢弃外层/冲突）'
        }
        $skipped += New-SkipRecord -Reason $skipReason -Message $skipMessage -Item $c
    }

    return [PSCustomObject]@{
        Selected = @($selected | Sort-Object StartOffset)
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

    if (-not $check.IsValid -and $effective.Count -gt 0) {
        $orderedForAdaptation = @($effective | Sort-Object @{ Expression = { Get-ReplacementCandidatePriority -Candidate $_ }; Descending = $true }, @{ Expression = { [int]($_.EndOffset - $_.StartOffset) }; Descending = $true }, StartOffset)
        foreach ($cand in $orderedForAdaptation) {
            $adapted = Get-SyntaxAdaptedReplacementCandidate -ScriptText $ScriptText -CurrentSelected $effective -Candidate $cand
            if (-not $adapted) { continue }

            $candId = Get-ReplacementIdentity -Replacement $cand
            $next = @()
            foreach ($item in $effective) {
                if ((Get-ReplacementIdentity -Replacement $item) -eq $candId) {
                    $next += $adapted
                } else {
                    $next += $item
                }
            }

            $effective = @($next)
            $skipped += New-SkipRecord -Reason 'syntax_guard_literalized' -Message '将表达式上下文中的候选回写为字符串字面量，避免生成裸命令文本导致语法错误' -Item $cand
            $check = Invoke-SyntaxCheckWithReplacements -SourceText $ScriptText -Replacements $effective
            if ($check.IsValid) { break }
        }

        if ($check.IsValid) {
            return [PSCustomObject]@{
                Selected         = @($effective)
                Skipped          = @($skipped)
                BaselineIsValid  = $baselineCheck.IsValid
                FinalIsValid     = $true
                FinalError       = $null
            }
        }
    }

    # 优先尝试单独保留“整段物化”候选，避免它被局部 wrapper/碎片拖累。
    if (-not $check.IsValid -and $effective.Count -gt 0) {
        $wholeScriptKeepers = @($effective | Where-Object {
            $_ -and $_.PSObject.Properties['WholeScriptMaterialized'] -and [bool]$_.WholeScriptMaterialized
        } | Sort-Object @{ Expression = { Get-ReplacementCandidatePriority -Candidate $_ }; Descending = $true }, @{ Expression = { [int]($_.EndOffset - $_.StartOffset) }; Descending = $true }, StartOffset)

        foreach ($keeper in $wholeScriptKeepers) {
            $candidateSet = @($keeper)
            $candidateCheck = Invoke-SyntaxCheckWithReplacements -SourceText $ScriptText -Replacements $candidateSet
            if (-not $candidateCheck.IsValid) { continue }

            foreach ($dropped in @($effective | Where-Object { (Get-ReplacementIdentity -Replacement $_) -ne (Get-ReplacementIdentity -Replacement $keeper) })) {
                $skipped += New-SkipRecord -Reason 'syntax_guard_preserved_whole_script' -Message '优先保留可解析的整段物化候选，移除其余碎片候选' -Item $dropped
            }

            $effective = $candidateSet
            $check = $candidateCheck
            break
        }
    }

    # 第一阶段：优先移除容易打碎语法的低优先级片段。
    foreach ($dropType in @('VarRead', 'Inline', 'CommandName', 'Binary')) {
        if ($check.IsValid) { break }

        $toDrop = @($effective | Where-Object { [string]$_.Type -eq $dropType })
        if ($toDrop.Count -eq 0) { continue }

        foreach ($d in $toDrop) {
            $skipped += New-SkipRecord -Reason 'syntax_guard' -Message "替换后语法错误，移除 $dropType 候选" -Item $d
        }

        $effective = @($effective | Where-Object { [string]$_.Type -ne $dropType })
        $check = Invoke-SyntaxCheckWithReplacements -SourceText $ScriptText -Replacements $effective
    }

    # 第二阶段：若存在高优先级整段候选，优先保留它们，丢弃其余碎片候选。
    if (-not $check.IsValid -and $effective.Count -gt 0) {
        $highPriority = @($effective | Where-Object { (Get-ReplacementCandidatePriority -Candidate $_) -ge 430 })
        if ($highPriority.Count -gt 0) {
            $highPriority = @($highPriority | Sort-Object @{ Expression = { Get-ReplacementCandidatePriority -Candidate $_ }; Descending = $true }, @{ Expression = { [int]($_.EndOffset - $_.StartOffset) }; Descending = $true }, StartOffset)
            foreach ($keeper in $highPriority) {
                $candidateSet = @($effective | Where-Object {
                    $same = ((Get-ReplacementIdentity -Replacement $_) -eq (Get-ReplacementIdentity -Replacement $keeper))
                    $nonOverlap = ($_.EndOffset -le $keeper.StartOffset -or $_.StartOffset -ge $keeper.EndOffset)
                    $same -or $nonOverlap
                })
                $candidateCheck = Invoke-SyntaxCheckWithReplacements -SourceText $ScriptText -Replacements $candidateSet
                if (-not $candidateCheck.IsValid) { continue }

                foreach ($dropped in @($effective | Where-Object { (Get-ReplacementIdentity -Replacement $_) -notin @($candidateSet | ForEach-Object { Get-ReplacementIdentity -Replacement $_ }) })) {
                    $skipped += New-SkipRecord -Reason 'syntax_guard_preserved_high_priority' -Message '优先保留高优先级整段候选，移除冲突碎片' -Item $dropped
                }

                $effective = $candidateSet
                $check = $candidateCheck
                break
            }
        }
    }

    # 第三阶段：若仍不合法，按“低优先级、小跨度优先”继续移除，直到可解析或清空。
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

    $decodedText = if ($decodedInfo) { Get-SafeNonEmptyString -Value $decodedInfo.DecodedContent } else { $null }
    if ($decodedText) {
        return [PSCustomObject]@{
            CommandAst    = $cmdAst
            DynamicType   = 'EncodedCommand'
            PayloadText   = $decodedText
            DecodeSource  = 'host_wrapper_decode_encoded'
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
        $payloadText = Get-SafeNonEmptyString -Value $hostInfo.ArgumentAst.Value
    } elseif ($hostInfo.PSObject.Properties['PayloadText']) {
        $payloadText = Get-SafeNonEmptyString -Value $hostInfo.PayloadText
    }

    if (-not $payloadText) {
        return $null
    }

    $decodeSource = 'host_wrapper_decode_command'
    if ($hostInfo.PSObject.Properties['PayloadSource'] -and [string]$hostInfo.PayloadSource -eq 'BareTail') {
        $decodeSource = 'host_wrapper_decode_bare_tail'
    }

    return [PSCustomObject]@{
        CommandAst    = $cmdAst
        DynamicType   = 'PowerShellCommand'
        PayloadText   = $payloadText
        DecodeSource  = $decodeSource
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
    $parenDepth = 0
    $bracketDepth = 0

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
                if ($parenDepth -eq 0 -and $bracketDepth -eq 0) {
                    Append-NewLine -Builder $sb -LineStart ([ref]$lineStart) -PendingIndent ([ref]$pendingIndent)
                } else {
                    $lineStart = $false
                }
                continue
            }
            '(' {
                Ensure-Indent -Builder $sb -Level $indent -LineStart ([ref]$lineStart) -PendingIndent ([ref]$pendingIndent)
                [void]$sb.Append('(')
                $parenDepth++
                $lineStart = $false
                continue
            }
            ')' {
                Ensure-Indent -Builder $sb -Level $indent -LineStart ([ref]$lineStart) -PendingIndent ([ref]$pendingIndent)
                [void]$sb.Append(')')
                $parenDepth = [Math]::Max(0, $parenDepth - 1)
                $lineStart = $false
                continue
            }
            '[' {
                Ensure-Indent -Builder $sb -Level $indent -LineStart ([ref]$lineStart) -PendingIndent ([ref]$pendingIndent)
                [void]$sb.Append('[')
                $bracketDepth++
                $lineStart = $false
                continue
            }
            ']' {
                Ensure-Indent -Builder $sb -Level $indent -LineStart ([ref]$lineStart) -PendingIndent ([ref]$pendingIndent)
                [void]$sb.Append(']')
                $bracketDepth = [Math]::Max(0, $bracketDepth - 1)
                $lineStart = $false
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

function Get-NormalizedScriptComparisonText {
    param([string]$ScriptText)

    if ($null -eq $ScriptText) { return '' }

    $text = [string]$ScriptText
    $text = $text -replace "`r`n", "`n"
    $text = $text -replace "`r", "`n"
    $text = [regex]::Replace($text, "[ \t]+(?=`n)", '')
    $text = [regex]::Replace($text, "(?:`n)+$", "`n")
    return $text
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

function Try-StripDuplicatedStageWrapper {
    param([Parameter(Mandatory)][string]$ScriptText)

    if ([string]::IsNullOrWhiteSpace($ScriptText)) {
        return $null
    }

    $match = [regex]::Match($ScriptText, '(?s)^\s*\$stage\s*=\s*@''\r?\n(?<wrapped>.*?)\r?\n''@\s*(?<tail>.+?)\s*$')
    if (-not $match.Success) {
        return $null
    }

    $wrapped = [string]$match.Groups['wrapped'].Value
    $tail = [string]$match.Groups['tail'].Value
    if ([string]::IsNullOrWhiteSpace($wrapped) -or [string]::IsNullOrWhiteSpace($tail)) {
        return $null
    }

    $cleanWrapped = $wrapped
    $cleanWrapped = [regex]::Replace($cleanWrapped, '^\s*PFX\d+', '', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $cleanWrapped = [regex]::Replace($cleanWrapped, '\r?\nSFX\d+\s*$', '', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $cleanWrapped = $cleanWrapped.Trim()
    $tail = $tail.Trim()

    $tailSyntax = Test-PowerShellSyntax -ScriptText $tail
    $wrappedSyntax = Test-PowerShellSyntax -ScriptText $cleanWrapped

    if ($tailSyntax.IsValid) {
        $tailNorm = Get-NormalizedScriptComparisonText -ScriptText $tail
        $wrappedNorm = Get-NormalizedScriptComparisonText -ScriptText $cleanWrapped
        if (($wrappedSyntax.IsValid -and $tailNorm -eq $wrappedNorm) -or -not $wrappedSyntax.IsValid) {
            return ($tail.TrimEnd() + "`r`n")
        }
    }

    if ($wrappedSyntax.IsValid) {
        return ($cleanWrapped.TrimEnd() + "`r`n")
    }

    return $null
}

function Invoke-CanonicalizeWildcardCommandTargets {
    param([Parameter(Mandatory)][string]$ScriptText)

    if ([string]::IsNullOrWhiteSpace($ScriptText)) {
        return $ScriptText
    }

    if (-not (Get-Command Resolve-CommandNameFromGetCommandExpression -ErrorAction SilentlyContinue) -or
        -not (Get-Command Resolve-SafeCommandNameExpressionValue -ErrorAction SilentlyContinue) -or
        -not (Get-Command Convert-ResolvedCommandCandidateToName -ErrorAction SilentlyContinue) -or
        -not (Get-Command Test-CommandNameExistsInContext -ErrorAction SilentlyContinue) -or
        -not (Get-Command Get-SafeCommandLookupResults -ErrorAction SilentlyContinue)) {
        return $ScriptText
    }

    $parse = Get-ScriptParseInfo -ScriptText $ScriptText
    if (-not $parse.IsValid -or -not $parse.Ast) {
        return $ScriptText
    }

    $dummyContext = @{
        CFG = @{ DefinedAliases = @{} }
        FunctionSubgraphs = @{}
        ScriptBlockSubgraphs = @{}
        ExecContext = $null
    }

    $execContext = $null
    try {
        $execContext = New-ExecutionContext
        $dummyContext.ExecContext = $execContext
    } catch {
        $execContext = $null
    }

    $resolveCanonicalCommandName = {
        param([string]$Name)

        if ([string]::IsNullOrWhiteSpace($Name)) {
            return $null
        }

        $lookup = @(Get-SafeCommandLookupResults -Name $Name) | Select-Object -First 1
        if ($lookup) {
            if ($lookup.CommandType -eq [System.Management.Automation.CommandTypes]::Alias -and
                -not [string]::IsNullOrWhiteSpace([string]$lookup.Definition)) {
                return [string]$lookup.Definition
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$lookup.Name)) {
                return [string]$lookup.Name
            }
        }

        $compatAlias = Resolve-CompatibilityAliasName -Name $Name
        if (-not [string]::IsNullOrWhiteSpace($compatAlias)) {
            return [string]$compatAlias
        }

        return [string]$Name
    }

    try {
        $replacements = @()
        $commandAsts = @($parse.Ast.FindAll({
                param($n)
                $n -is [System.Management.Automation.Language.CommandAst]
            }, $true))

        foreach ($cmdAst in $commandAsts) {
            if (-not $cmdAst.CommandElements -or $cmdAst.CommandElements.Count -eq 0) { continue }

            $firstElement = $cmdAst.CommandElements[0]
            if (-not $firstElement -or -not $firstElement.Extent) { continue }
            if ($cmdAst.GetCommandName() -and
                (($firstElement -is [System.Management.Automation.Language.StringConstantExpressionAst]) -or
                 ($firstElement -is [System.Management.Automation.Language.ExpandableStringExpressionAst]))) {
                continue
            }

            $resolvedName = $null
            $safeEval = Resolve-SafeCommandNameExpressionValue -Ast $firstElement -Context $dummyContext
            if ($safeEval -and $safeEval.Success) {
                $candidateName = Convert-ResolvedCommandCandidateToName -Value $safeEval.Value
                if (Test-CommandNameExistsInContext -CommandName $candidateName -Context $dummyContext) {
                    $resolvedName = & $resolveCanonicalCommandName $candidateName
                }
            }

            if ([string]::IsNullOrWhiteSpace($resolvedName)) {
                $resolution = Resolve-CommandNameFromGetCommandExpression -CommandAst $cmdAst -FirstElementAst $firstElement -Context $dummyContext
                if ($resolution -and $resolution.Success) {
                    $resolvedName = & $resolveCanonicalCommandName ([string]$resolution.ResolvedName)
                }
            }

            if ([string]::IsNullOrWhiteSpace($resolvedName)) { continue }
            if ([string]$firstElement.Extent.Text -eq $resolvedName) { continue }

            $replacements += [PSCustomObject]@{
                Start = [int]$firstElement.Extent.StartOffset
                End   = [int]$firstElement.Extent.EndOffset
                Text  = [string]$resolvedName
            }
        }
    } finally {
        if ($execContext) {
            Close-ExecutionContext -ExecContext $execContext
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

function Invoke-PostProcessDeobfuscatedScriptText {
    param([Parameter(Mandatory)][string]$ScriptText)

    $working = $ScriptText

    while ($true) {
        $payloadInfo = Resolve-WholeScriptHostPayloadInfo -ScriptText $working
        if (-not $payloadInfo) { break }

        $payloadText = Get-SafeNonEmptyString -Value $payloadInfo.PayloadText
        if (-not $payloadText) { break }

        $payloadParse = Get-ScriptParseInfo -ScriptText $payloadText
        if (-not $payloadParse.IsValid) { break }

        $working = $payloadText
    }

    $stageStripped = Try-StripDuplicatedStageWrapper -ScriptText $working
    if (-not [string]::IsNullOrWhiteSpace($stageStripped)) {
        $working = $stageStripped
    }

    $working = Invoke-CanonicalizeWildcardCommandTargets -ScriptText $working
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
Write-Host "SafeMode   : $SafeMode" -ForegroundColor Gray
Write-Host "MaxRounds  : $MaxRounds" -ForegroundColor Gray
Write-Host "TimeBudget : Global=${GlobalTimeBudgetMs}ms Dynamic=${DynamicTimeBudgetMs}ms" -ForegroundColor Gray
Write-Host "DryRun     : $DryRun" -ForegroundColor Gray
Write-Host ""

$currentPath = $scriptFullPath
$currentText = $null
$finalRound = 0
$finalRoundOutPath = $null
$terminatedBy = $null
$lastValidRoundOutPath = $null
$lastValidText = $null
$finalOutputSource = $null
$finalSyntaxFallbackUsed = $false
$globalStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$currentRoundIsMaterializedPayload = $false

for ($round = 1; $round -le $MaxRounds; $round++) {
    $remainingGlobalBudgetMs = Get-RemainingTimeBudgetMs -BudgetMs $GlobalTimeBudgetMs -Stopwatch $globalStopwatch
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
                        SafeMode           = $SafeMode
                        TerminatedBy       = 'parse_failure'
                        ParseError         = $roundParseInfo.FirstError
                        FinalSyntaxValid   = $false
                        FinalOutputSource  = 'rebuilt_output'
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

            $preTraversalCheck = Get-PreTraversalStopCheckInfo -ScriptText $rawRoundText -IsMaterializedPayloadRound:$currentRoundIsMaterializedPayload
            if ($preTraversalCheck.ShouldCheck) {
                $roundStop = Test-DynamicPayloadShouldStopRecursing -ScriptText $preTraversalCheck.CheckText -SafeMode:$SafeMode
            } else {
                $roundStop = $null
            }

            if ($roundStop -and $roundStop.ShouldStop) {
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
                        SafeMode           = $SafeMode
                        TerminatedBy       = 'pre_traversal_stop'
                        InputIsMaterializedPayloadRound = $currentRoundIsMaterializedPayload
                        PreTraversalCheckApplied = $true
                        PreTraversalCheckReason = $preTraversalCheck.Reason
                        StopReason         = $roundStop.StopReason
                        StopMessage        = $roundStop.Message
                        StopFeatures       = @($roundStop.Features)
                        FinalSyntaxValid   = $true
                        FinalOutputSource  = 'rebuilt_output'
                        Timestamp          = (Get-Date).ToString('o')
                    }
                    Write-JsonFile -Path $roundReportPath -Object $report
                }

                $currentText = $rawRoundText
                $finalRound = $round
                $finalRoundOutPath = $roundOutPath
                $lastValidRoundOutPath = $roundOutPath
                $lastValidText = $rawRoundText
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
                        SafeMode           = $SafeMode
                        TerminatedBy       = 'cfg_generation_failed'
                        ParseError         = $roundParseInfo.FirstError
                        FinalSyntaxValid   = $false
                        FinalOutputSource  = 'rebuilt_output'
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

            $ctx = Invoke-CFGTraversal -CFG $cfg -LogPath $roundLogPath -MaxIterations $MaxIterations -MaxTotalNodes $MaxTotalNodes -GlobalTimeBudgetMs $remainingGlobalBudgetMs -DynamicTimeBudgetMs $DynamicTimeBudgetMs -SafeMode:$SafeMode

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

        $preTraversalCheck = Get-PreTraversalStopCheckInfo -ScriptText $currentText -IsMaterializedPayloadRound:$currentRoundIsMaterializedPayload
        if ($preTraversalCheck.ShouldCheck) {
            $roundStop = Test-DynamicPayloadShouldStopRecursing -ScriptText $preTraversalCheck.CheckText -SafeMode:$SafeMode
        } else {
            $roundStop = $null
        }

        if ($roundStop -and $roundStop.ShouldStop) {
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
        $ctx = Invoke-CFGTraversal -CFG $cfg -LogPath $null -MaxIterations $MaxIterations -MaxTotalNodes $MaxTotalNodes -GlobalTimeBudgetMs $remainingGlobalBudgetMs -DynamicTimeBudgetMs $DynamicTimeBudgetMs -SafeMode:$SafeMode

        $scriptText = $currentText
    }

    $base = Get-ReplacementsFromResolvableResults -Context $ctx -ScriptText $scriptText -VariableConflictPolicy $VariableConflictPolicy
    $dynamic = Get-DynamicInvokeReplacementCandidates -Context $ctx -ScriptText $scriptText
    $functionResults = Get-FunctionInvokeReplacementCandidates -Context $ctx -ScriptText $scriptText
    $wholeScriptDynamic = Get-WholeScriptDynamicLoaderReplacementCandidates -Context $ctx -ScriptText $scriptText
    $literalized = Get-LiteralizedCommandReplacementCandidates -Context $ctx -ScriptText $scriptText
    $remainingStaticBudgetMs = Get-RemainingTimeBudgetMs -BudgetMs $GlobalTimeBudgetMs -Stopwatch $globalStopwatch
    if ($GlobalTimeBudgetMs -gt 0 -and $remainingStaticBudgetMs -le 0) {
        $static = [PSCustomObject]@{
            Candidates = @()
            Skipped    = @(New-SkipRecord -Reason 'static_budget_exceeded' -Message '进入静态候选阶段时全局预算已耗尽，跳过静态求值。' -Item $null)
        }
    } else {
        $static = Get-StaticReplacementCandidates -Context $ctx -ScriptText $scriptText -TimeBudgetMs $remainingStaticBudgetMs
    }
    $merged = Merge-ReplacementCandidatesByRange -Candidates (@($dynamic.Candidates) + @($functionResults.Candidates) + @($wholeScriptDynamic.Candidates) + @($literalized.Candidates) + @($base.Candidates) + @($static.Candidates))
    $contextFiltered = Filter-ReplacementCandidatesByContext -Candidates @($merged.Candidates) -Context $ctx -ScriptText $scriptText
    $preferred = Filter-CandidatesPreferDynamicInvoke -Candidates @($contextFiltered.Candidates)

    $candidates = @($preferred.Candidates)
    $skipped = @($dynamic.Skipped) + @($functionResults.Skipped) + @($wholeScriptDynamic.Skipped) + @($literalized.Skipped) + @($base.Skipped) + @($static.Skipped) + @($merged.Skipped) + @($contextFiltered.Skipped) + @($preferred.Skipped)

    $contextInfoForLowConfidence = Get-ReplacementContextInfoFromScriptText -ScriptText $scriptText
    $autoCandidates = @()
    foreach ($cand in @($candidates)) {
        $isLowConfidenceStatic = ($cand -and $cand.PSObject.Properties['SourceKind'] -and [string]$cand.SourceKind -eq 'Static' -and
            $cand.PSObject.Properties['UsedEmptyFallback'] -and [bool]$cand.UsedEmptyFallback)
        if (-not $isLowConfidenceStatic) {
            $autoCandidates += $cand
            continue
        }

        if (Test-StaticLowConfidenceCandidateAutoApply -Candidate $cand -ScriptText $scriptText -Context $ctx -ContextInfo $contextInfoForLowConfidence) {
            $autoCandidates += $cand
            continue
        }

        $skipped += New-SkipRecord -Reason 'static_low_confidence' -Message '低置信静态候选默认不自动应用' -Item $cand
    }

    $sel = Select-NonOverlappingReplacements -Candidates $autoCandidates -Strategy $OverlapStrategy
    $selected = @($sel.Selected)
    $skipped += @($sel.Skipped)

    $syntaxGuard = Ensure-SyntaxSafeReplacements -ScriptText $scriptText -Selected $selected
    $selected = @($syntaxGuard.Selected)
    $skipped += @($syntaxGuard.Skipped)

    $newText = Apply-ReplacementsToText -Text $scriptText -Replacements $selected
    $nextRoundMaterializedPayload = Get-NextRoundMaterializedPayloadInfo -Selected $selected -PrePostProcessText $newText
    $postProcessedText = Invoke-PostProcessDeobfuscatedScriptText -ScriptText $newText
    $postProcessChanged = ((Get-NormalizedScriptComparisonText -ScriptText $postProcessedText) -ne (Get-NormalizedScriptComparisonText -ScriptText $newText))
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
        $noReplacementReason = Get-NoReplacementTerminationReason -CandidateCount $candidates.Count -Skipped $skipped
        Write-Host ("  candidates={0} selected={1} applied={2} skipped={3}" -f $candidates.Count, $selected.Count, $appliedCount, $skipped.Count) -ForegroundColor Gray

        if ($FullOutput) {
            $report = [ordered]@{
                Round           = $round
                RoundLabel      = $roundLabel
                InputPath       = $roundInPath
                OutputPath      = $null
                ExecutionLog    = $roundLogPath
                CfgDotPath      = $roundCfgDotPath
                CfgPngPath      = $roundCfgPngPath
                SafeMode        = $SafeMode
                TerminatedBy    = 'no_replacements'
                NoReplacementReason = $noReplacementReason
                CandidateCount  = $candidates.Count
                SelectedCount   = 0
                AppliedCount    = 0
                SkippedCount    = $skipped.Count
                Skipped         = $skipped
                Timestamp       = (Get-Date).ToString('o')
            }
            Write-JsonFile -Path $roundReportPath -Object $report

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
                MaterializationKind = if ($a.PSObject.Properties['MaterializationKind']) { $a.MaterializationKind } else { $null }
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
            SafeMode        = $SafeMode
            OverlapStrategy = $OverlapStrategy
            VariableConflictPolicy = $VariableConflictPolicy
            MaxIterations   = $MaxIterations
            MaxTotalNodes   = $MaxTotalNodes
            GlobalTimeBudgetMs = $GlobalTimeBudgetMs
            DynamicTimeBudgetMs = $DynamicTimeBudgetMs
            ExecutionStopReason = if ($ctx.ContainsKey('StopReason')) { $ctx.StopReason } else { $null }
            InputIsMaterializedPayloadRound = $currentRoundIsMaterializedPayload
            PreTraversalCheckApplied = [bool]$preTraversalCheck.ShouldCheck
            PreTraversalCheckReason = $preTraversalCheck.Reason
            RemainingGlobalBudgetBeforeStatic = $remainingStaticBudgetMs
            StaticSkippedByBudget = ($GlobalTimeBudgetMs -gt 0 -and $remainingStaticBudgetMs -le 0)
            CandidateCount  = $candidates.Count
            DynamicCount    = $dynamicCount
            LiteralizedCommandCount = $literalizedCount
            OtherExecutedCount = $otherExecutedCount
            StaticHighCount = $staticHigh
            StaticLowCount  = $staticLow
            SelectedCount   = $selected.Count
            AppliedCount    = $appliedCount
            PostProcessChanged = $postProcessChanged
            NextRoundIsMaterializedPayload = [bool]$nextRoundMaterializedPayload.IsMaterializedPayload
            NextRoundMaterializedPayloadReason = $nextRoundMaterializedPayload.Reason
            SkippedCount    = $skipped.Count
            SkippedByReason = $skipReasonCounts
            AppliedNodeIds  = $appliedNodeIds
            Applied         = $appliedItems
            Skipped         = $skipped
            Timestamp       = (Get-Date).ToString('o')
        }

        Write-JsonFile -Path $roundReportPath -Object $report

        Set-Content -LiteralPath $roundOutPath -Value $newText -Encoding UTF8
        $lastValidRoundOutPath = $roundOutPath
        $lastValidText = $newText

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
        $lastValidText = $newText
    }

    $currentRoundIsMaterializedPayload = [bool]$nextRoundMaterializedPayload.IsMaterializedPayload

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

$finalOutputPathToCopy = $null
$finalOutputText = $null
$finalSyntaxValid = $false

if ($FullOutput) {
    $preferredInfo = Test-FileSyntaxInfo -Path $finalRoundOutPath
    if ($preferredInfo.Exists -and $preferredInfo.IsValid) {
        $finalOutputPathToCopy = $finalRoundOutPath
        $finalOutputText = $preferredInfo.Text
        $finalOutputSource = 'rebuilt_output'
        $finalSyntaxValid = $true
    } elseif (-not [string]::IsNullOrWhiteSpace($lastValidRoundOutPath)) {
        $fallbackInfo = Test-FileSyntaxInfo -Path $lastValidRoundOutPath
        if ($fallbackInfo.Exists -and $fallbackInfo.IsValid) {
            $finalOutputPathToCopy = $lastValidRoundOutPath
            $finalOutputText = $fallbackInfo.Text
            $finalOutputSource = 'last_valid_round'
            $finalSyntaxValid = $true
            $finalSyntaxFallbackUsed = $true
        }
    }

    if (-not $finalSyntaxValid) {
        $inputInfo = Test-FileSyntaxInfo -Path $currentPath
        if ($inputInfo.Exists -and $inputInfo.IsValid) {
            $finalOutputPathToCopy = $currentPath
            $finalOutputText = $inputInfo.Text
            $finalOutputSource = 'current_input'
            $finalSyntaxValid = $true
            $finalSyntaxFallbackUsed = $true
        }
    }
} else {
    $preferredText = if ($null -eq $currentText) { '' } else { [string]$currentText }
    $preferredSyntax = Test-PowerShellSyntax -ScriptText $preferredText
    if ($preferredSyntax.IsValid) {
        $finalOutputText = $preferredText
        $finalOutputSource = 'rebuilt_output'
        $finalSyntaxValid = $true
    } elseif (-not [string]::IsNullOrWhiteSpace($lastValidText)) {
        $lastValidSyntax = Test-PowerShellSyntax -ScriptText $lastValidText
        if ($lastValidSyntax.IsValid) {
            $finalOutputText = $lastValidText
            $finalOutputSource = 'last_valid_round'
            $finalSyntaxValid = $true
            $finalSyntaxFallbackUsed = $true
        }
    }

    if (-not $finalSyntaxValid) {
        $inputText = Get-FullScriptTextFromFile -Path $scriptFullPath
        $inputSyntax = Test-PowerShellSyntax -ScriptText $inputText
        if ($inputSyntax.IsValid) {
            $finalOutputText = $inputText
            $finalOutputSource = 'current_input'
            $finalSyntaxValid = $true
            $finalSyntaxFallbackUsed = $true
        }
    }
}

if (-not $finalSyntaxValid) {
    throw '最终输出语法仍无效，且无法回退到语法有效版本。'
}

if (-not $DryRun) {
    $outDir = [System.IO.Path]::GetDirectoryName($OutPath)
    if (-not [string]::IsNullOrWhiteSpace($outDir) -and -not (Test-Path -LiteralPath $outDir)) {
        $null = New-Item -ItemType Directory -Path $outDir -Force
    }

    if ($FullOutput) {
        Copy-Item -LiteralPath $finalOutputPathToCopy -Destination $OutPath -Force
    } else {
        Set-Content -LiteralPath $OutPath -Value $finalOutputText -Encoding UTF8
    }
}

Write-Host "=== 完成 ===" -ForegroundColor Green
Write-Host ("TerminatedBy : {0}" -f $terminatedBy) -ForegroundColor Gray
Write-Host ("FinalRound   : {0}" -f $finalRound) -ForegroundColor Gray
if ($FullOutput) {
    Write-Host ("FinalWorkOut : {0}" -f $finalRoundOutPath) -ForegroundColor Gray
}
Write-Host ("FinalSource  : {0}" -f $finalOutputSource) -ForegroundColor Gray
Write-Host ("FinalSyntax  : {0}" -f $finalSyntaxValid) -ForegroundColor Gray
Write-Host ("OutPath      : {0}" -f $OutPath) -ForegroundColor Gray
if ($FullOutput) {
    Write-Host ("WorkDir      : {0}" -f $WorkDir) -ForegroundColor Gray
}
