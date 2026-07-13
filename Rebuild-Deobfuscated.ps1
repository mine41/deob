<#
.SYNOPSIS
  Rebuild a deobfuscated PowerShell script from CFG execution results.

.DESCRIPTION
  The script iteratively regenerates the CFG, executes it, and writes resolved
  fragments back into the source until no more replacements are applied or the
  maximum round count is reached.

  Current rebuilding rules:
  - Use ResolvableResults as the primary replacement source.
  - Skip __BLOCKED_PLACEHOLDER__ values.
  - Skip a source fragment when conflicting replacements are observed.
  - Resolve overlapping or nested replacements through -OverlapStrategy.

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

    [object]$FullOutput = $true,

    [ValidateSet('Outer', 'Inner')]
    [string]$OverlapStrategy = 'Inner',

    [ValidateSet('skip', 'last')]
    [string]$VariableConflictPolicy = 'skip',

    [ValidateSet('skip', 'prefer')]
    [string]$DynamicConflictPolicy = 'skip',

    [int]$MaxRounds = 10,

    [int]$MaxIterations = 1000,

    [int]$MaxTotalNodes = 50000,

    [int]$GlobalTimeBudgetMs = 120000,

    [int]$DynamicTimeBudgetMs = 15000,

    [object]$SafeMode = $true,

    [ValidateSet('Disabled', 'Conservative', 'Balanced', 'Aggressive')]
    [string]$PreExecutionGateMode = 'Disabled',

    [ValidateSet('Default', 'Cmdline', 'AdaptiveCoverage')]
    [string]$OptimizationProfile = 'Default',

    [string]$RunMetadataPath,

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$script:StaticEvalOperatorCache = @{}

function ConvertFrom-HostBooleanArgument {
    param(
        [AllowNull()]
        [object]$Value,
        [Parameter(Mandatory)]
        [string]$ParameterName
    )

    if ($null -eq $Value) { return $null }

    if ($Value -is [bool]) {
        return $Value
    }

    if ($Value -is [System.Management.Automation.SwitchParameter]) {
        return [bool]$Value
    }

    if ($Value -is [System.Array]) {
        if ($Value.Count -eq 1) {
            return ConvertFrom-HostBooleanArgument -Value $Value[0] -ParameterName $ParameterName
        }

        throw "Parameter '$ParameterName' expects a single boolean-compatible value, but received $($Value.Count) values."
    }

    if ($Value -is [sbyte] -or
        $Value -is [byte] -or
        $Value -is [int16] -or
        $Value -is [uint16] -or
        $Value -is [int32] -or
        $Value -is [uint32] -or
        $Value -is [int64] -or
        $Value -is [uint64]) {
        if ([int64]$Value -eq 0) { return $false }
        if ([int64]$Value -eq 1) { return $true }
    }

    $text = ([string]$Value).Trim()
    switch -Regex ($text) {
        '^(?i:\$?true|1|yes|on)$'  { return $true }
        '^(?i:\$?false|0|no|off)$' { return $false }
    }

    throw "Parameter '$ParameterName' expects a boolean-compatible value. Supported values: true/false, `$true/`$false, 1/0, yes/no, on/off. Actual: '$text'."
}

$FullOutput = ConvertFrom-HostBooleanArgument -Value $FullOutput -ParameterName 'FullOutput'
$SafeMode = ConvertFrom-HostBooleanArgument -Value $SafeMode -ParameterName 'SafeMode'
$script:IsCmdlineOptimizationProfile = ([string]$OptimizationProfile -eq 'Cmdline')
$script:IsAdaptiveCoverageOptimizationProfile = ([string]$OptimizationProfile -eq 'AdaptiveCoverage')
$script:IsTimeoutCoverageOptimizationProfile = [bool]$script:IsAdaptiveCoverageOptimizationProfile
$effectiveOverlapStrategy = $OverlapStrategy
$effectiveVariableConflictPolicy = $VariableConflictPolicy
$effectiveDynamicConflictPolicy = $DynamicConflictPolicy

if ($script:IsCmdlineOptimizationProfile) {
    if (-not $PSBoundParameters.ContainsKey('OverlapStrategy') -and $effectiveOverlapStrategy -eq 'Inner') {
        $effectiveOverlapStrategy = 'Outer'
    }
    if (-not $PSBoundParameters.ContainsKey('VariableConflictPolicy') -and $effectiveVariableConflictPolicy -eq 'last') {
        $effectiveVariableConflictPolicy = 'skip'
    }
}

function Test-IsCmdlineOptimizationProfile {
    return [bool]$script:IsCmdlineOptimizationProfile
}

function Test-IsTimeoutCoverageOptimizationProfile {
    return [bool]$script:IsTimeoutCoverageOptimizationProfile
}

function Test-IsAdaptiveCoverageOptimizationProfile {
    return [bool]$script:IsAdaptiveCoverageOptimizationProfile
}

function Test-UsesFastTimeoutPostProcessProfile {
    return (Test-IsAdaptiveCoverageOptimizationProfile)
}

function Get-FastSensitivePassConfig {
    if (-not (Test-IsAdaptiveCoverageOptimizationProfile)) {
        return [PSCustomObject]@{
            Enabled               = $false
            TriggerTextLength     = 0
            MaxTargets            = 0
            MaxAstNodesPerTarget  = 0
            MaxDepth              = 0
            MaxResolvedTextLength = 0
            StaticBudgetMs        = 0
        }
    }

    return [PSCustomObject]@{
        Enabled               = $true
        TriggerTextLength     = 16384
        MaxTargets            = 256
        MaxAstNodesPerTarget  = 128
        MaxDepth              = 6
        MaxResolvedTextLength = 8192
        StaticBudgetMs        = 250
    }
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

function Get-RecordFieldValue {
    param(
        [AllowNull()]$Record,
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()]$Default = $null
    )

    if ($null -eq $Record) { return $Default }
    if ($Record -is [hashtable]) {
        if ($Record.ContainsKey($Name)) { return $Record[$Name] }
        return $Default
    }
    if ($Record.PSObject.Properties[$Name]) {
        return $Record.$Name
    }
    return $Default
}

function Add-RecordScopeMetadataToCandidate {
    param(
        [AllowNull()]$Candidate,
        [AllowNull()]$Record
    )

    if ($null -eq $Candidate -or $null -eq $Record) { return $Candidate }

    foreach ($name in @(
            'ScopeType',
            'ScopeName',
            'ScopePrefix',
            'ScopeInvocationId',
            'ParentScopeInvocationId',
            'ScopeCallerNodeId',
            'ScopeInvocationStartOffset',
            'ScopeInvocationEndOffset',
            'ScopeInvocationText')) {
        $value = Get-RecordFieldValue -Record $Record -Name $name -Default $null
        if ($null -ne $value) {
            $Candidate | Add-Member -NotePropertyName $name -NotePropertyValue $value -Force
        }
    }

    return $Candidate
}

function Test-ExpressionTextSourceStatic {
    param([AllowNull()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$tokens, [ref]$errors)
    if (-not $ast -or ($errors -and $errors.Count -gt 0)) { return $false }

    $hasVariable = $ast.Find({
            param($n)
            return ($n -is [System.Management.Automation.Language.VariableExpressionAst])
        }, $true)
    if ($hasVariable) { return $false }

    $hasCommand = $ast.Find({
            param($n)
            return ($n -is [System.Management.Automation.Language.CommandAst])
        }, $true)
    if ($hasCommand) { return $false }

    return $true
}

function Test-ReusableScriptBlockDefinitionCandidateAllowed {
    param(
        [AllowNull()]$Candidate
    )

    if (-not $Candidate -or -not $Candidate.PSObject.Properties['SourceKind']) { return $false }

    $sourceKind = [string]$Candidate.SourceKind
    if ($sourceKind -in @('MandatoryBase64', 'StaticPath', 'StaticCompressedLoader')) { return $true }

    if ($sourceKind -eq 'Static') {
        if ($Candidate.PSObject.Properties['UsedEmptyFallback'] -and [bool]$Candidate.UsedEmptyFallback) { return $false }
        $original = if ($Candidate.PSObject.Properties['Original']) { [string]$Candidate.Original } else { $null }
        if (-not [string]::IsNullOrWhiteSpace($original) -and -not (Test-ExpressionTextSourceStatic -Text $original)) { return $false }
        return $true
    }

    if ($sourceKind -eq 'Resolvable') {
        $original = if ($Candidate.PSObject.Properties['Original']) { [string]$Candidate.Original } else { $null }
        return (Test-ExpressionTextSourceStatic -Text $original)
    }

    return $false
}

function Get-ScopeAwareReplacementRangeKey {
    param(
        [int]$StartOffset,
        [int]$EndOffset,
        [AllowNull()]$Record = $null
    )

    $baseKey = "$StartOffset`:$EndOffset"
    $scopeInvocationId = Get-RecordFieldValue -Record $Record -Name 'ScopeInvocationId' -Default $null
    if (-not [string]::IsNullOrWhiteSpace([string]$scopeInvocationId)) {
        return "$baseKey`:scope:$scopeInvocationId"
    }

    return $baseKey
}

function Get-UnwrappedScriptBlockExpressionAst {
    param([AllowNull()]$Ast)

    $current = $Ast
    while ($null -ne $current) {
        if ($current -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) { return $current }
        if ($current -is [System.Management.Automation.Language.CommandExpressionAst]) {
            $current = $current.Expression
            continue
        }
        if ($current -is [System.Management.Automation.Language.ConvertExpressionAst]) {
            $current = $current.Child
            continue
        }
        if ($current -is [System.Management.Automation.Language.ParenExpressionAst]) {
            if ($current.Pipeline -and $current.Pipeline.PipelineElements.Count -eq 1) {
                $element = $current.Pipeline.PipelineElements[0]
                if ($element -is [System.Management.Automation.Language.CommandExpressionAst]) {
                    $current = $element.Expression
                    continue
                }
            }
        }
        break
    }

    return $null
}

function Get-ReusableScriptBlockDefinitionRanges {
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][string]$ScriptText
    )

    $blockNames = @{}
    $ranges = @()
    $seenRanges = @{}

    if ($Context.ContainsKey('VarToBlockMapping') -and $Context.VarToBlockMapping) {
        foreach ($value in @($Context.VarToBlockMapping.Values)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$value)) {
                $blockNames[[string]$value] = $true
            }
        }
    }

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($ScriptText, [ref]$tokens, [ref]$errors)
    if ($ast -and (-not $errors -or $errors.Count -eq 0)) {
        $functionDefinitions = @($ast.FindAll({
                    param($n)
                    return ($n -is [System.Management.Automation.Language.FunctionDefinitionAst])
                }, $true))
        foreach ($funcAst in @($functionDefinitions)) {
            if (-not $funcAst -or -not $funcAst.Body -or -not $funcAst.Body.Extent) { continue }
            $start = [int]$funcAst.Body.Extent.StartOffset
            $end = [int]$funcAst.Body.Extent.EndOffset
            if ($start -lt 0 -or $end -le $start -or $end -gt $ScriptText.Length) { continue }
            $key = "$start`:$end"
            if ($seenRanges.ContainsKey($key)) { continue }
            $seenRanges[$key] = $true
            $ranges += [PSCustomObject]@{
                BlockName   = ('function:' + [string]$funcAst.Name)
                StartOffset = $start
                EndOffset   = $end
            }
        }

        $assignedBlocks = @($ast.FindAll({
                    param($n)
                    if ($n -isnot [System.Management.Automation.Language.AssignmentStatementAst]) { return $false }
                    if ($n.Left -isnot [System.Management.Automation.Language.VariableExpressionAst]) { return $false }

                    return ($null -ne (Get-UnwrappedScriptBlockExpressionAst -Ast $n.Right))
                }, $true))

        foreach ($assignment in @($assignedBlocks)) {
            $right = Get-UnwrappedScriptBlockExpressionAst -Ast $assignment.Right
            if (-not $right -or -not $right.Extent) { continue }
            $start = [int]$right.Extent.StartOffset
            $end = [int]$right.Extent.EndOffset
            if ($start -lt 0 -or $end -le $start -or $end -gt $ScriptText.Length) { continue }
            $key = "$start`:$end"
            if ($seenRanges.ContainsKey($key)) { continue }
            $seenRanges[$key] = $true
            $ranges += [PSCustomObject]@{
                BlockName   = if ($assignment.Left -and $assignment.Left.VariablePath) { [string]$assignment.Left.VariablePath.UserPath } else { $null }
                StartOffset = $start
                EndOffset   = $end
            }
        }
    }

    if ($blockNames.Count -eq 0 -or -not $Context.ScriptBlockSubgraphs) { return @($ranges) }

    foreach ($blockName in @($blockNames.Keys)) {
        if (-not $Context.ScriptBlockSubgraphs.ContainsKey($blockName)) { continue }
        $blockStartId = $Context.ScriptBlockSubgraphs[$blockName]
        $blockStartNode = Get-NodeById -CFG $Context.CFG -Id $blockStartId
        if (-not $blockStartNode) { continue }

        $start = if ($blockStartNode.PSObject.Properties['TextStartOffset']) { $blockStartNode.TextStartOffset } else { $null }
        $end = if ($blockStartNode.PSObject.Properties['TextEndOffset']) { $blockStartNode.TextEndOffset } else { $null }
        if ($null -eq $start -or $null -eq $end) { continue }
        $start = [int]$start
        $end = [int]$end
        if ($start -lt 0 -or $end -le $start -or $end -gt $ScriptText.Length) { continue }
        $key = "$start`:$end"
        if ($seenRanges.ContainsKey($key)) { continue }
        $seenRanges[$key] = $true

        $ranges += [PSCustomObject]@{
            BlockName   = [string]$blockName
            StartOffset = $start
            EndOffset   = $end
        }
    }

    return @($ranges)
}

function Get-ContainingReusableScriptBlockRange {
    param(
        [int]$StartOffset,
        [int]$EndOffset,
        [AllowEmptyCollection()][array]$Ranges
    )

    foreach ($range in @($Ranges)) {
        if ($StartOffset -ge [int]$range.StartOffset -and $EndOffset -le [int]$range.EndOffset) {
            return $range
        }
    }

    return $null
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

function Get-OptimizationProfileSettings {
    param(
        [ValidateSet('Default', 'Cmdline', 'AdaptiveCoverage')]
        [string]$Profile,
        [int]$RequestedMaxRounds
    )

    switch ($Profile) {
        'TimeoutCoverage' {
            return [PSCustomObject]@{
                Profile                    = $Profile
                EffectiveMaxRounds         = [Math]::Max($RequestedMaxRounds, 1)
                FinalizationReserveMs      = 0
                StaticBudgetCapMs          = 0
                ShallowDynamicBudgetMs     = 2000
                ShallowMaxIterations       = 250
                ShallowMaxTotalNodes       = 8000
                NearBudgetWindowMs         = 30000
                ShallowTextLength          = 16384
                SkipCfgTextLength          = 32768
                ShallowLargeArrayCount     = 512
                SkipCfgLargeArrayCount     = 2048
                ShallowAstNodeCount        = 1200
                SkipCfgAstNodeCount        = 3500
                MaterializedPayloadRounds  = [Math]::Max($RequestedMaxRounds, 1)
                PayloadFollowupDynamicBudgetMs = 0
                PayloadFollowupMaxIterations   = 0
                PayloadFollowupMaxTotalNodes   = 0
            }
        }
        'AdaptiveCoverage' {
            return [PSCustomObject]@{
                Profile                    = $Profile
                EffectiveMaxRounds         = [Math]::Max($RequestedMaxRounds, 1)
                FinalizationReserveMs      = 0
                StaticBudgetCapMs          = 0
                ShallowDynamicBudgetMs     = 2000
                ShallowMaxIterations       = 250
                ShallowMaxTotalNodes       = 8000
                NearBudgetWindowMs         = 30000
                ShallowTextLength          = 16384
                SkipCfgTextLength          = 32768
                ShallowLargeArrayCount     = 512
                SkipCfgLargeArrayCount     = 2048
                ShallowAstNodeCount        = 1200
                SkipCfgAstNodeCount        = 3500
                MaterializedPayloadRounds  = [Math]::Max($RequestedMaxRounds, 1)
                PayloadFollowupDynamicBudgetMs = 4000
                PayloadFollowupMaxIterations   = 400
                PayloadFollowupMaxTotalNodes   = 12000
            }
        }
        default {
            return [PSCustomObject]@{
                Profile                    = $Profile
                EffectiveMaxRounds         = [Math]::Max($RequestedMaxRounds, 1)
                FinalizationReserveMs      = 0
                StaticBudgetCapMs          = 0
                ShallowDynamicBudgetMs     = 0
                ShallowMaxIterations       = 0
                ShallowMaxTotalNodes       = 0
                NearBudgetWindowMs         = 0
                ShallowTextLength          = 0
                SkipCfgTextLength          = 0
                ShallowLargeArrayCount     = 0
                SkipCfgLargeArrayCount     = 0
                ShallowAstNodeCount        = 0
                SkipCfgAstNodeCount        = 0
                MaterializedPayloadRounds  = [Math]::Max($RequestedMaxRounds, 1)
                PayloadFollowupDynamicBudgetMs = 0
                PayloadFollowupMaxIterations   = 0
                PayloadFollowupMaxTotalNodes   = 0
            }
        }
    }
}

function Get-OptimizationProfileRoundPlan {
    param(
        [Parameter(Mandatory)]
        $ProfileSettings,
        [AllowNull()]$GateDecision = $null,
        [int]$RemainingGlobalBudgetMs,
        [int]$Round,
        [bool]$IsMaterializedPayloadRound = $false
    )

    $plan = [ordered]@{
        RoundMode             = 'default'
        SkipCfgTraversal      = $false
        SkipWholeScriptDynamic = $false
        SkipStaticEval        = $false
        StopAfterThisRound    = $false
        DynamicTimeBudgetMs   = $null
        MaxIterations         = $null
        MaxTotalNodes         = $null
        Reason                = $null
    }

    $profileName = if ($null -ne $ProfileSettings -and $ProfileSettings.PSObject.Properties['Profile']) { [string]$ProfileSettings.Profile } else { '' }
    if ($profileName -notin @('TimeoutCoverage', 'AdaptiveCoverage')) {
        return [PSCustomObject]$plan
    }

    $metrics = if ($GateDecision -and $GateDecision.PSObject.Properties['Metrics']) { $GateDecision.Metrics } else { $null }
    $textLength = if ($metrics -and $metrics.PSObject.Properties['TextLength']) { [int]$metrics.TextLength } else { 0 }
    $largeArrayCount = if ($metrics -and $metrics.PSObject.Properties['LargeArrayElementCount']) { [int]$metrics.LargeArrayElementCount } else { 0 }
    $astNodeCount = if ($metrics -and $metrics.PSObject.Properties['AstNodeCount']) { [int]$metrics.AstNodeCount } else { 0 }
    $compressedLoaderHit = if ($metrics -and $metrics.PSObject.Properties['CompressedLoaderHit']) { [bool]$metrics.CompressedLoaderHit } else { $false }
    $dynamicTokenCount = if ($metrics -and $metrics.PSObject.Properties['DynamicTokenCount']) { [int]$metrics.DynamicTokenCount } else { 0 }

    $isNearBudget = ($RemainingGlobalBudgetMs -gt 0 -and $RemainingGlobalBudgetMs -le [int]$ProfileSettings.NearBudgetWindowMs)
    $isVeryLarge = (
        $textLength -ge [int]$ProfileSettings.SkipCfgTextLength -or
        $largeArrayCount -ge [int]$ProfileSettings.SkipCfgLargeArrayCount -or
        $astNodeCount -ge [int]$ProfileSettings.SkipCfgAstNodeCount
    )
    $isShallow = (
        $textLength -ge [int]$ProfileSettings.ShallowTextLength -or
        $largeArrayCount -ge [int]$ProfileSettings.ShallowLargeArrayCount -or
        $astNodeCount -ge [int]$ProfileSettings.ShallowAstNodeCount -or
        $dynamicTokenCount -ge 8 -or
        $compressedLoaderHit -or
        $isNearBudget
    )

    if ($RemainingGlobalBudgetMs -gt 0 -and $RemainingGlobalBudgetMs -le ([int]$ProfileSettings.FinalizationReserveMs + 5000)) {
        $plan.RoundMode = 'text_only'
        $plan.SkipCfgTraversal = $true
        $plan.SkipWholeScriptDynamic = $true
        $plan.SkipStaticEval = $true
        $plan.StopAfterThisRound = $true
        $plan.Reason = 'near_finalization_reserve'
        return [PSCustomObject]$plan
    }

    if ($profileName -eq 'TimeoutCoverage') {
        if ($isVeryLarge) {
            $plan.RoundMode = 'text_only'
            $plan.SkipCfgTraversal = $true
            $plan.SkipWholeScriptDynamic = $true
            $plan.SkipStaticEval = $true
            $plan.StopAfterThisRound = $true
            $plan.Reason = 'very_large_script'
            return [PSCustomObject]$plan
        }

        if ($isShallow -or $Round -gt 1) {
            $plan.RoundMode = 'shallow'
            $plan.SkipWholeScriptDynamic = $true
            $plan.SkipStaticEval = $true
            $plan.DynamicTimeBudgetMs = [int]$ProfileSettings.ShallowDynamicBudgetMs
            $plan.MaxIterations = [int]$ProfileSettings.ShallowMaxIterations
            $plan.MaxTotalNodes = [int]$ProfileSettings.ShallowMaxTotalNodes
            $plan.Reason = if ($isNearBudget) { 'near_budget_window' } elseif ($compressedLoaderHit) { 'compressed_loader' } else { 'large_or_late_round' }
        }
    } elseif ($profileName -eq 'AdaptiveCoverage') {
        if ($IsMaterializedPayloadRound) {
            $plan.RoundMode = 'payload_followup'
            $plan.DynamicTimeBudgetMs = [int]$ProfileSettings.PayloadFollowupDynamicBudgetMs
            $plan.MaxIterations = [int]$ProfileSettings.PayloadFollowupMaxIterations
            $plan.MaxTotalNodes = [int]$ProfileSettings.PayloadFollowupMaxTotalNodes
            $plan.StopAfterThisRound = $true
            $plan.Reason = 'materialized_payload_followup'
            return [PSCustomObject]$plan
        }

        if ($isVeryLarge) {
            $plan.RoundMode = 'text_only'
            $plan.SkipCfgTraversal = $true
            $plan.SkipWholeScriptDynamic = $true
            $plan.SkipStaticEval = $true
            $plan.Reason = 'very_large_script'
            return [PSCustomObject]$plan
        }

        if ($isShallow) {
            $plan.RoundMode = 'shallow'
            $plan.SkipWholeScriptDynamic = $true
            $plan.SkipStaticEval = $true
            $plan.DynamicTimeBudgetMs = [int]$ProfileSettings.ShallowDynamicBudgetMs
            $plan.MaxIterations = [int]$ProfileSettings.ShallowMaxIterations
            $plan.MaxTotalNodes = [int]$ProfileSettings.ShallowMaxTotalNodes
            $plan.Reason = if ($isNearBudget) { 'near_budget_window' } elseif ($compressedLoaderHit) { 'compressed_loader' } else { 'large_script' }
        }
    }

    $allowedRounds = if ($IsMaterializedPayloadRound) {
        [Math]::Max([int]$ProfileSettings.MaterializedPayloadRounds, 1)
    } else {
        [int]$ProfileSettings.EffectiveMaxRounds
    }
    if ($Round -ge $allowedRounds) {
        $plan.StopAfterThisRound = $true
    }

    return [PSCustomObject]$plan
}

function Get-EffectiveRoundExecutionLimits {
    param(
        [int]$BaseDynamicTimeBudgetMs,
        [int]$BaseMaxIterations,
        [int]$BaseMaxTotalNodes,
        [AllowNull()]$GateDecision = $null
    )

    $effectiveDynamicTimeBudgetMs = $BaseDynamicTimeBudgetMs
    $effectiveMaxIterations = $BaseMaxIterations
    $effectiveMaxTotalNodes = $BaseMaxTotalNodes

    if ($GateDecision -and [string]$GateDecision.Decision -eq 'Shallow') {
        if ($GateDecision.PSObject.Properties['ReducedDynamicBudgetMs'] -and $null -ne $GateDecision.ReducedDynamicBudgetMs) {
            if ($effectiveDynamicTimeBudgetMs -le 0) {
                $effectiveDynamicTimeBudgetMs = [int]$GateDecision.ReducedDynamicBudgetMs
            } else {
                $effectiveDynamicTimeBudgetMs = [Math]::Min([int]$effectiveDynamicTimeBudgetMs, [int]$GateDecision.ReducedDynamicBudgetMs)
            }
        }
        if ($GateDecision.PSObject.Properties['ReducedMaxIterations'] -and $null -ne $GateDecision.ReducedMaxIterations) {
            $effectiveMaxIterations = [Math]::Min([int]$effectiveMaxIterations, [int]$GateDecision.ReducedMaxIterations)
        }
        if ($GateDecision.PSObject.Properties['ReducedMaxTotalNodes'] -and $null -ne $GateDecision.ReducedMaxTotalNodes) {
            $effectiveMaxTotalNodes = [Math]::Min([int]$effectiveMaxTotalNodes, [int]$GateDecision.ReducedMaxTotalNodes)
        }
    }

    $dynamicDepthLimit = $null
    if ($GateDecision -and [string]$GateDecision.Decision -eq 'Shallow') {
        $dynamicDepthLimit = 1
    }

    return [PSCustomObject]@{
        DynamicTimeBudgetMs = $effectiveDynamicTimeBudgetMs
        MaxIterations       = $effectiveMaxIterations
        MaxTotalNodes       = $effectiveMaxTotalNodes
        DynamicDepthLimit   = $dynamicDepthLimit
    }
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

    if ($Replacement -match '^\s*@\(') { return $false }
    if ($Replacement -match '^\s*@\{') { return $false }
    if ($Replacement -match '^\s*\{')  { return $false }

    return $true
}

function Test-TypedScalarTypeName {
    param([AllowNull()][string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }

    $scalarTypeNames = @(
        'string', 'system.string',
        'char', 'system.char',
        'bool', 'boolean', 'system.boolean',
        'byte', 'system.byte',
        'sbyte', 'system.sbyte',
        'int16', 'short', 'system.int16',
        'uint16', 'ushort', 'system.uint16',
        'int', 'int32', 'system.int32',
        'uint32', 'uint', 'system.uint32',
        'int64', 'long', 'system.int64',
        'uint64', 'ulong', 'system.uint64',
        'float', 'single', 'system.single',
        'double', 'system.double',
        'decimal', 'system.decimal'
    )

    return ($scalarTypeNames -contains ([string]$Name).ToLowerInvariant())
}

function Get-UnwrappedParenthesizedExpressionAst {
    param($Ast)

    $current = $Ast
    while ($current -is [System.Management.Automation.Language.ParenExpressionAst]) {
        $next = Get-StaticExpressionFromPipelineAst -PipelineAst $current.Pipeline
        if (-not $next -or [object]::ReferenceEquals($next, $current)) { break }
        $current = $next
    }

    return $current
}

function Test-SimpleTypedScalarCastAst {
    param($Ast)

    $current = Get-UnwrappedParenthesizedExpressionAst -Ast $Ast
    if ($current -isnot [System.Management.Automation.Language.ConvertExpressionAst]) { return $false }
    if (-not $current.Type -or -not $current.Type.TypeName) { return $false }
    if (-not (Test-TypedScalarTypeName -Name ([string]$current.Type.TypeName.FullName))) { return $false }

    $child = Get-UnwrappedParenthesizedExpressionAst -Ast $current.Child
    if ($child -is [System.Management.Automation.Language.StringConstantExpressionAst]) { return $true }
    if ($child -is [System.Management.Automation.Language.ConstantExpressionAst]) { return $true }
    if ($child -is [System.Management.Automation.Language.VariableExpressionAst]) {
        $name = if ($child.VariablePath) { [string]$child.VariablePath.UserPath } else { '' }
        return ($name -match '^(?i:true|false)$')
    }
    if ($child -is [System.Management.Automation.Language.UnaryExpressionAst] -and $child.PSObject.Properties['Child']) {
        $unaryChild = Get-UnwrappedParenthesizedExpressionAst -Ast $child.Child
        return ($unaryChild -is [System.Management.Automation.Language.ConstantExpressionAst])
    }
    if ($child -is [System.Management.Automation.Language.ConvertExpressionAst]) {
        return (Test-SimpleTypedScalarCastAst -Ast $child)
    }

    return $false
}

function Test-TypedScalarExpressionText {
    param([AllowNull()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }

    $expr = Get-SingleTopLevelExpressionAstFromText -ScriptText $Text
    if (-not $expr) { return $false }
    return (Test-SimpleTypedScalarCastAst -Ast $expr)
}

function Get-TypedScalarExpressionRanges {
    param([Parameter(Mandatory)][string]$ScriptText)

    $parse = Get-ScriptParseInfo -ScriptText $ScriptText
    if (-not $parse.Ast) { return @() }

    $ranges = @()
    $seen = @{}
    $convertAsts = @($parse.Ast.FindAll({
                param($n)
                return (Test-SimpleTypedScalarCastAst -Ast $n)
            }, $true))

    foreach ($ast in $convertAsts) {
        if (-not $ast.Extent) { continue }
        $key = "$($ast.Extent.StartOffset):$($ast.Extent.EndOffset)"
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $ranges += [PSCustomObject]@{
            StartOffset = [int]$ast.Extent.StartOffset
            EndOffset   = [int]$ast.Extent.EndOffset
        }
    }

    return @($ranges)
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

        if ($map[$key] -eq 'Read' -and $kind -ne 'Read') {
            $map[$key] = $kind
        }
    }

    return $map
}

function Test-PipelineAutomaticVariableAst {
    param([System.Management.Automation.Language.VariableExpressionAst]$Ast)

    if ($null -eq $Ast -or $null -eq $Ast.VariablePath -or $null -eq $Ast.VariablePath.UserPath) {
        return $false
    }

    $name = [string]$Ast.VariablePath.UserPath
    if ([string]::IsNullOrWhiteSpace($name)) { return $false }

    return ($name -ieq '_' -or $name -ieq 'PSItem')
}

function Test-AstContainsPipelineAutomaticVariable {
    param([AllowNull()][System.Management.Automation.Language.Ast]$Ast)

    if ($null -eq $Ast) { return $false }

    if ($Ast -is [System.Management.Automation.Language.VariableExpressionAst]) {
        return (Test-PipelineAutomaticVariableAst -Ast $Ast)
    }

    if (-not $Ast.PSObject.Methods['FindAll']) {
        return $false
    }

    $matches = @($Ast.FindAll({
                param($n)
                if ($n -isnot [System.Management.Automation.Language.VariableExpressionAst]) {
                    return $false
                }
                return (Test-PipelineAutomaticVariableAst -Ast $n)
            }, $true))

    return ($matches.Count -gt 0)
}

function Test-ScriptBlockExpressionAssignmentRight {
    param(
        [AllowNull()][System.Management.Automation.Language.Ast]$Ast,
        [int]$Depth = 0
    )

    if ($null -eq $Ast -or $Depth -gt 8) { return $false }

    if ($Ast -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
        return $true
    }

    if ($Ast -is [System.Management.Automation.Language.ConvertExpressionAst]) {
        return (Test-ScriptBlockExpressionAssignmentRight -Ast $Ast.Child -Depth ($Depth + 1))
    }

    if ($Ast -is [System.Management.Automation.Language.CommandExpressionAst]) {
        return (Test-ScriptBlockExpressionAssignmentRight -Ast $Ast.Expression -Depth ($Depth + 1))
    }

    if ($Ast -is [System.Management.Automation.Language.ParenExpressionAst]) {
        $expr = Get-StaticExpressionFromPipelineAst -PipelineAst $Ast.Pipeline
        if ($null -ne $expr) {
            return (Test-ScriptBlockExpressionAssignmentRight -Ast $expr -Depth ($Depth + 1))
        }
    }

    return $false
}

function Test-IsSensitiveCommandNameForContext {
    param([AllowNull()][string]$CommandName)

    if ([string]::IsNullOrWhiteSpace($CommandName)) {
        return $false
    }

    return ($CommandName -match '^(?i:invoke-expression|iex|start-process|saps|invoke-webrequest|iwr|invoke-restmethod|irm|nslookup|cmd(?:\.exe)?|powershell(?:\.exe)?|pwsh(?:\.exe)?)$')
}

function Test-IsSensitiveMemberNameForContext {
    param([AllowNull()][string]$MemberName)

    if ([string]::IsNullOrWhiteSpace($MemberName)) {
        return $false
    }

    return ($MemberName -match '^(?i:DownloadString|DownloadFile|Start|Invoke|CopyHere)$')
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
        PipelineVariableRanges = @()
        PipelineSensitiveExpressionRanges = @()
        SensitiveArgumentRanges = @()
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
    $pipelineVariableRanges = [System.Collections.Generic.List[object]]::new()
    $pipelineSensitiveExpressionRanges = [System.Collections.Generic.List[object]]::new()
    $sensitiveArgumentRanges = [System.Collections.Generic.List[object]]::new()
    $commandNameRangeSeen = @{}
    $dynamicPayloadRangeSeen = @{}
    $memberNameRangeSeen = @{}
    $commandTargetAssignmentRangeSeen = @{}
    $pipelineVariableRangeSeen = @{}
    $pipelineSensitiveExpressionRangeSeen = @{}
    $sensitiveArgumentRangeSeen = @{}
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

        if (Test-IsSensitiveCommandNameForContext -CommandName $cmdName) {
            for ($i = 1; $i -lt $cmdAst.CommandElements.Count; $i++) {
                $elem = $cmdAst.CommandElements[$i]
                if ($elem -is [System.Management.Automation.Language.CommandParameterAst]) {
                    if ($elem.Argument -and $elem.Argument.Extent) {
                        Add-UniqueContextRange -SeenMap $sensitiveArgumentRangeSeen -List $sensitiveArgumentRanges -StartOffset $elem.Argument.Extent.StartOffset -EndOffset $elem.Argument.Extent.EndOffset
                    }
                    continue
                }

                if ($elem -and $elem.Extent) {
                    Add-UniqueContextRange -SeenMap $sensitiveArgumentRangeSeen -List $sensitiveArgumentRanges -StartOffset $elem.Extent.StartOffset -EndOffset $elem.Extent.EndOffset
                }
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

        if (($memberAst -is [System.Management.Automation.Language.InvokeMemberExpressionAst]) -and
            (Test-IsSensitiveMemberNameForContext -MemberName ([string]$memberAst.Member.Extent.Text))) {
            foreach ($argAst in @($memberAst.Arguments)) {
                if ($argAst -and $argAst.Extent) {
                    Add-UniqueContextRange -SeenMap $sensitiveArgumentRangeSeen -List $sensitiveArgumentRanges -StartOffset $argAst.Extent.StartOffset -EndOffset $argAst.Extent.EndOffset
                }
            }
        }
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
            if (Test-ScriptBlockExpressionAssignmentRight -Ast $assignAst.Right) { continue }

            Add-UniqueContextRange -SeenMap $commandTargetAssignmentRangeSeen -List $commandTargetAssignmentRanges -StartOffset $assignAst.Right.Extent.StartOffset -EndOffset $assignAst.Right.Extent.EndOffset
        }
    }

    $pipelineVarAsts = @($ast.FindAll({
            param($n)
            $n -is [System.Management.Automation.Language.VariableExpressionAst]
        }, $true))
    foreach ($pipelineVarAst in $pipelineVarAsts) {
        if (-not (Test-PipelineAutomaticVariableAst -Ast $pipelineVarAst)) { continue }
        if (-not $pipelineVarAst.Extent) { continue }

        $current = $pipelineVarAst.Parent
        $enclosingScriptBlock = $null
        while ($current) {
            if ($current -is [System.Management.Automation.Language.ScriptBlockAst]) {
                $enclosingScriptBlock = $current
                break
            }
            $current = $current.Parent
        }

        if (-not $enclosingScriptBlock) { continue }

        Add-UniqueContextRange -SeenMap $pipelineVariableRangeSeen -List $pipelineVariableRanges -StartOffset $pipelineVarAst.Extent.StartOffset -EndOffset $pipelineVarAst.Extent.EndOffset

        $current = $pipelineVarAst.Parent
        while ($current -and $current -ne $enclosingScriptBlock) {
            if (($current -is [System.Management.Automation.Language.ExpressionAst]) -and $current.Extent) {
                Add-UniqueContextRange -SeenMap $pipelineSensitiveExpressionRangeSeen -List $pipelineSensitiveExpressionRanges -StartOffset $current.Extent.StartOffset -EndOffset $current.Extent.EndOffset
            }
            $current = $current.Parent
        }
    }

    $result.ExpandableStringRanges = @($expandableRanges)
    $result.CommandNameRangeKeys = $commandNameRangeKeys
    $result.CommandNameRanges = @($commandNameRanges)
    $result.DynamicPayloadRanges = @($dynamicPayloadRanges)
    $result.MemberNameRanges = @($memberNameRanges)
    $result.CommandTargetAssignmentRanges = @($commandTargetAssignmentRanges)
    $result.PipelineVariableRanges = @($pipelineVariableRanges)
    $result.PipelineSensitiveExpressionRanges = @($pipelineSensitiveExpressionRanges)
    $result.SensitiveArgumentRanges = @($sensitiveArgumentRanges)
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

function Test-ReplacementExactRange {
    param(
        [int]$StartOffset,
        [int]$EndOffset,
        [array]$Ranges
    )

    if (-not $Ranges -or $Ranges.Count -eq 0) { return $false }

    foreach ($range in $Ranges) {
        if (-not $range) { continue }
        if ($null -eq $range.StartOffset -or $null -eq $range.EndOffset) { continue }
        if ([int]$range.StartOffset -eq $StartOffset -and [int]$range.EndOffset -eq $EndOffset) {
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

function Get-CmdlineProfileVariableReadGuardDecision {
    param(
        $Candidate,
        $ContextInfo
    )

    if (-not (Test-IsCmdlineOptimizationProfile)) { return $null }
    if (-not $Candidate) { return $null }
    if (-not $Candidate.PSObject.Properties['SourceKind'] -or [string]$Candidate.SourceKind -ne 'VariableRead') { return $null }

    $start = if ($Candidate.PSObject.Properties['StartOffset']) { [int]$Candidate.StartOffset } else { $null }
    $end = if ($Candidate.PSObject.Properties['EndOffset']) { [int]$Candidate.EndOffset } else { $null }
    if ($null -eq $start -or $null -eq $end) { return $null }

    $original = if ($Candidate.PSObject.Properties['Original']) { [string]$Candidate.Original } else { '' }
    $observedValueCount = if ($Candidate.PSObject.Properties['ObservedValueCount']) { [int]$Candidate.ObservedValueCount } else { 1 }
    $isValueChanged = ($Candidate.PSObject.Properties['IsValueChanged'] -and [bool]$Candidate.IsValueChanged)

    if ($isValueChanged -or $observedValueCount -gt 1) {
        return [PSCustomObject]@{
            Reason  = 'cmdline_variable_multi_value_protected'
            Message = 'Cmdline profile 下变量读取出现多值观测，默认不做 last/定值化回写'
        }
    }

    if ($original -match '^\s*\$(?i:env:[A-Za-z_][A-Za-z0-9_]*|PSScriptRoot|PSCommandPath|MyInvocation|PID|Args|Input|PSItem|_)\s*$') {
        return [PSCustomObject]@{
            Reason  = 'cmdline_variable_runtime_scoped'
            Message = 'Cmdline profile 下环境/自动变量不直接定值化回写'
        }
    }

    if ($ContextInfo) {
        if (Test-ReplacementWithinRanges -StartOffset $start -EndOffset $end -Ranges $ContextInfo.SensitiveArgumentRanges) {
            return [PSCustomObject]@{
                Reason  = 'cmdline_sensitive_argument_protected'
                Message = 'Cmdline profile 下敏感调用参数中的变量读取不直接回写，避免把运行时输入固化'
            }
        }

        if (Test-ReplacementWithinRanges -StartOffset $start -EndOffset $end -Ranges $ContextInfo.DynamicPayloadRanges) {
            return [PSCustomObject]@{
                Reason  = 'cmdline_dynamic_payload_variable_protected'
                Message = 'Cmdline profile 下动态 payload 范围内的变量读取不直接回写'
            }
        }
    }

    return $null
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
    $reusableScriptBlockRanges = Get-ReusableScriptBlockDefinitionRanges -Context $Context -ScriptText $ScriptText
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
        $withinPipelineVariable = (Test-ReplacementWithinRanges -StartOffset $start -EndOffset $end -Ranges $contextInfo.PipelineVariableRanges)
        $withinPipelineSensitiveExpression = (Test-ReplacementWithinRanges -StartOffset $start -EndOffset $end -Ranges $contextInfo.PipelineSensitiveExpressionRanges)
        $highValueSourceKinds = @('DynamicInvoke', 'LoaderMaterialized', 'FunctionResult', 'FunctionSpecializedInline', 'CanonicalCommandInvocation', 'CommandTargetAssignment', 'ScriptBlockTargetInline', 'ScriptBlockSpecializedInline')
        $allowInsideDynamicRange = $false

        $definitionRange = Get-ContainingReusableScriptBlockRange -StartOffset $start -EndOffset $end -Ranges $reusableScriptBlockRanges
        if ($definitionRange -and -not (Test-ReusableScriptBlockDefinitionCandidateAllowed -Candidate $cand)) {
            $skipped += New-SkipRecord -Reason 'scriptblock_definition_context_dependent' -Message '可复用脚本块定义体仅允许纯静态/source-level 回填，调用上下文相关候选改由调用点专用展开承载' -Item $cand
            continue
        }

        if ($withinDynamicRange -and
            $sourceKind -eq 'CanonicalCommandInvocation' -and
            $cand.PSObject.Properties['IsOriginMappedFromRuntime'] -and [bool]$cand.IsOriginMappedFromRuntime) {
            $allowInsideDynamicRange = $true
        }

        if (-not $allowInsideDynamicRange -and $sourceKind -notin $highValueSourceKinds -and $withinDynamicPayload -and $withinDynamicRange) {
            $skipped += New-SkipRecord -Reason 'dynamic_payload_protected' -Message '外层 DynamicInvoke 候选有效，动态 payload 内部局部候选跳过' -Item $cand
            continue
        }

        if (-not $allowInsideDynamicRange -and $sourceKind -notin $highValueSourceKinds -and $withinDynamicRange) {
            $skipped += New-SkipRecord -Reason 'dynamic_wrapper_protected' -Message '外层 DynamicInvoke 候选有效，动态调用节点内部局部候选跳过' -Item $cand
            continue
        }

        $allowInExpandable = $false
        if ($withinExpandable) {
            if ($sourceKind -in @('DynamicInvoke', 'LoaderMaterialized', 'FunctionResult', 'FunctionSpecializedInline', 'CanonicalCommandInvocation', 'CommandTargetAssignment', 'ScriptBlockTargetInline', 'ScriptBlockSpecializedInline', 'LiteralizedCommand', 'Resolvable')) {
                $allowInExpandable = $true
            } elseif ($sourceKind -eq 'Static' -and $cand.PSObject.Properties['Confidence'] -and [string]$cand.Confidence -eq 'High') {
                $allowInExpandable = $true
            }
        }
        if ($sourceKind -notin $highValueSourceKinds -and $withinExpandable -and -not $allowInExpandable) {
            $skipped += New-SkipRecord -Reason 'expandable_context_protected' -Message 'ExpandableString 内仅放行高价值高置信候选，当前候选跳过' -Item $cand
            continue
        }

        if ($sourceKind -eq 'VariableRead' -and $withinPipelineVariable) {
            $skipped += New-SkipRecord -Reason 'pipeline_variable_protected' -Message '脚本块中的管道变量读取不做自动回填，避免把 $_/$PSItem 固化成单次观测值' -Item $cand
            continue
        }

        $cmdlineVariableGuard = Get-CmdlineProfileVariableReadGuardDecision -Candidate $cand -ContextInfo $contextInfo
        if ($cmdlineVariableGuard) {
            $skipped += New-SkipRecord -Reason ([string]$cmdlineVariableGuard.Reason) -Message ([string]$cmdlineVariableGuard.Message) -Item $cand
            continue
        }

        if ($sourceKind -eq 'Resolvable' -and $withinPipelineSensitiveExpression) {
            $skipped += New-SkipRecord -Reason 'pipeline_expression_protected' -Message '包含 $_/$PSItem 的脚本块表达式不做自动执行结果回填，保留数据依赖语义' -Item $cand
            continue
        }

        if ($sourceKind -eq 'Static' -and $cand.PSObject.Properties['Ast'] -and (Test-AstContainsPipelineAutomaticVariable -Ast $cand.Ast)) {
            $skipped += New-SkipRecord -Reason 'pipeline_static_expression_protected' -Message '包含 $_/$PSItem 的表达式不做静态回填，避免把 pipeline 上下文变量折叠为空值或残留值' -Item $cand
            continue
        }

        if ($sourceKind -notin $highValueSourceKinds -and (Test-ReplacementWithinRanges -StartOffset $start -EndOffset $end -Ranges $contextInfo.MemberNameRanges)) {
            $skipped += New-SkipRecord -Reason 'member_name_protected' -Message '成员名位点默认不做局部替换，避免破坏反射/方法调用语义' -Item $cand
            continue
        }

        if ($sourceKind -notin $highValueSourceKinds -and (Test-ReplacementWithinRanges -StartOffset $start -EndOffset $end -Ranges $contextInfo.CommandTargetAssignmentRanges)) {
            $isExactCommandTargetAssignment = Test-ReplacementExactRange -StartOffset $start -EndOffset $end -Ranges $contextInfo.CommandTargetAssignmentRanges
            $allowWholeStaticCommandTargetAssignment = ($isExactCommandTargetAssignment -and (Test-ReusableScriptBlockDefinitionCandidateAllowed -Candidate $cand))
            if (-not $allowWholeStaticCommandTargetAssignment) {
                $skipped += New-SkipRecord -Reason 'command_target_assignment_protected' -Message '命令目标变量的赋值表达式只允许整段静态还原或高置信整段还原，局部候选跳过' -Item $cand
                continue
            }
        }

        if ((Test-ReplacementWithinRanges -StartOffset $start -EndOffset $end -Ranges $contextInfo.CommandNameRanges) -and -not $isExactCommandNameRange) {
            $skipped += New-SkipRecord -Reason 'command_name_context_protected' -Message '命令位点内部不允许局部替换，避免破坏命令解析' -Item $cand
            continue
        }

        if ($isExactCommandNameRange -and $sourceKind -notin @('FunctionResult', 'FunctionSpecializedInline', 'ScriptBlockTargetInline', 'ScriptBlockSpecializedInline') -and -not (Test-ValidCommandNameReplacement -Replacement ([string]$cand.Replacement) -Context $Context)) {
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

function Convert-StaticDictionaryToOrderedMap {
    param([System.Collections.IDictionary]$Dictionary)

    $map = [ordered]@{}
    if ($null -eq $Dictionary) {
        return $map
    }

    foreach ($key in @($Dictionary.Keys)) {
        $map[[string]$key] = $Dictionary[$key]
    }

    return $map
}

function New-StaticPathInfoValue {
    param([AllowNull()][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }

    $normalizedPath = ([string]$Path).Trim()
    if ($normalizedPath.Length -gt 3) {
        $normalizedPath = $normalizedPath.TrimEnd('\')
    }

    return [PSCustomObject]@{
        __PsDissectType = 'PathInfo'
        Path            = $normalizedPath
        ProviderPath    = $normalizedPath
    }
}

function New-StaticModeledObjectValue {
    param(
        [AllowNull()][string]$TypeName,
        [AllowNull()][System.Collections.IDictionary]$InitialProperties
    )

    $normalizedTypeName = if ([string]::IsNullOrWhiteSpace($TypeName)) { '' } else { ([string]$TypeName).Trim() }
    $normalizedTypeNameLower = $normalizedTypeName.ToLowerInvariant()

    $propertyMap = switch -Regex ($normalizedTypeNameLower) {
        '^(?:system\.diagnostics\.)?processstartinfo$' {
            [ordered]@{
                __PsDissectType = 'ProcessStartInfo'
                FileName        = $null
                Arguments       = $null
                WorkingDirectory = $null
                Verb            = $null
                WindowStyle     = $null
                UseShellExecute = $null
                UserName        = $null
                Domain          = $null
                Password        = $null
            }
            break
        }
        '^(?:wscript\.shell|shell\.application)$' {
            [ordered]@{
                __PsDissectType = if ($normalizedTypeNameLower -eq 'wscript.shell') { 'WScript.Shell' } else { $normalizedTypeName }
                SpecialFolders  = [pscustomobject]@{
                    __PsDissectType = 'WScript.Shell.SpecialFolders'
                }
            }
            break
        }
        '^(?:wscript\.shell\.shortcut|iwshshortcut)$' {
            [ordered]@{
                __PsDissectType  = 'WScript.Shell.Shortcut'
                FullName         = $null
                TargetPath       = $null
                Arguments        = $null
                WorkingDirectory = $null
                IconLocation     = $null
                Description      = $null
                WindowStyle      = $null
                Hotkey           = $null
            }
            break
        }
        '^(?:system\.net\.)?webclient$' {
            [ordered]@{
                __PsDissectType = 'WebClient'
                BaseAddress     = $null
                Proxy           = $null
                Headers         = $null
            }
            break
        }
        '^(?:system\.management\.automation\.)?(?:psobject|pscustomobject)$' {
            [ordered]@{
                __PsDissectType = 'PSObject'
            }
            break
        }
        default {
            $null
        }
    }

    if ($null -eq $propertyMap) {
        return $null
    }

    if ($InitialProperties) {
        foreach ($key in @($InitialProperties.Keys)) {
            $propertyMap[[string]$key] = $InitialProperties[$key]
        }
    }

    return ([pscustomobject]$propertyMap)
}

function Resolve-StaticSpecialFolderPath {
    param([AllowNull()][string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $null
    }

    switch -Regex ($Name.Trim()) {
        '^(?i:startup)$' {
            return '%PROGRAMDATA%\Microsoft\Windows\Start Menu\Programs\Startup'
        }
        '^(?i:desktop)$' {
            return '%USERPROFILE%\Desktop'
        }
        '^(?i:appdata)$' {
            return '%APPDATA%'
        }
        '^(?i:programs)$' {
            return '%APPDATA%\Microsoft\Windows\Start Menu\Programs'
        }
        '^(?i:startmenu)$' {
            return '%APPDATA%\Microsoft\Windows\Start Menu'
        }
    }

    return $null
}

function Set-StaticMemberAccessValue {
    param(
        $TargetValue,
        [string]$MemberName,
        $MemberValue
    )

    if ([string]::IsNullOrWhiteSpace($MemberName)) {
        return [PSCustomObject]@{ Success = $false; Message = '成员名为空' }
    }

    if ($TargetValue -is [psobject] -and $null -ne $TargetValue.BaseObject -and $TargetValue.BaseObject -ne $TargetValue) {
        $TargetValue = $TargetValue.BaseObject
    }
    if ($null -eq $TargetValue) {
        return [PSCustomObject]@{ Success = $false; Message = '成员赋值目标为空' }
    }

    if ($TargetValue -is [System.Collections.IDictionary]) {
        $matchedKey = $null
        foreach ($existingKey in @($TargetValue.Keys)) {
            if (($existingKey -is [string] -or $existingKey -is [char]) -and ([string]$existingKey -ieq $MemberName)) {
                $matchedKey = $existingKey
                break
            }
        }
        if ($null -eq $matchedKey) {
            $matchedKey = [string]$MemberName
        }
        $TargetValue[$matchedKey] = $MemberValue
        return [PSCustomObject]@{ Success = $true; Message = $null }
    }

    if (Test-StaticPropertyBagValue -Value $TargetValue) {
        $property = @(
            $TargetValue.PSObject.Properties.Match($MemberName) |
                Where-Object { $_.MemberType -eq [System.Management.Automation.PSMemberTypes]::NoteProperty } |
                Select-Object -First 1
        )
        if ($property.Count -gt 0) {
            $property[0].Value = $MemberValue
        } else {
            $TargetValue | Add-Member -NotePropertyName $MemberName -NotePropertyValue $MemberValue -Force
        }
        return [PSCustomObject]@{ Success = $true; Message = $null }
    }

    try {
        $property = @(
            $TargetValue.PSObject.Properties.Match($MemberName) |
                Where-Object {
                    $_.MemberType -eq [System.Management.Automation.PSMemberTypes]::Property -or
                    $_.MemberType -eq [System.Management.Automation.PSMemberTypes]::AliasProperty -or
                    $_.MemberType -eq [System.Management.Automation.PSMemberTypes]::NoteProperty
                } |
                Select-Object -First 1
        )
        if ($property.Count -gt 0 -and $property[0].IsSettable) {
            $property[0].Value = $MemberValue
            return [PSCustomObject]@{ Success = $true; Message = $null }
        }
    } catch {
    }

    return [PSCustomObject]@{ Success = $false; Message = ('不支持的安全成员赋值: ' + $MemberName) }
}

function Set-StaticIndexedValue {
    param(
        $TargetValue,
        $IndexValue,
        $AssignedValue
    )

    if ($TargetValue -is [psobject] -and $null -ne $TargetValue.BaseObject -and $TargetValue.BaseObject -ne $TargetValue) {
        $TargetValue = $TargetValue.BaseObject
    }
    if ($null -eq $TargetValue) {
        return [PSCustomObject]@{ Success = $false; Message = '索引赋值目标为空' }
    }

    if ($TargetValue -is [System.Collections.IDictionary]) {
        $key = if ($IndexValue -is [char[]]) { -join $IndexValue } else { $IndexValue }
        $TargetValue[$key] = $AssignedValue
        return [PSCustomObject]@{ Success = $true; Message = $null }
    }

    if ($TargetValue -is [System.Collections.IList]) {
        try {
            $index = [int]$IndexValue
        } catch {
            return [PSCustomObject]@{ Success = $false; Message = '索引赋值下标不是整数' }
        }

        if ($index -lt 0) {
            return [PSCustomObject]@{ Success = $false; Message = '索引赋值下标越界' }
        }

        if ($TargetValue.IsFixedSize) {
            if ($index -ge $TargetValue.Count) {
                return [PSCustomObject]@{ Success = $false; Message = '固定长度列表索引越界' }
            }
            $TargetValue[$index] = $AssignedValue
            return [PSCustomObject]@{ Success = $true; Message = $null }
        }

        while ($TargetValue.Count -le $index) {
            $null = $TargetValue.Add($null)
        }
        $TargetValue[$index] = $AssignedValue
        return [PSCustomObject]@{ Success = $true; Message = $null }
    }

    if ($TargetValue -is [array]) {
        try {
            $index = [int]$IndexValue
        } catch {
            return [PSCustomObject]@{ Success = $false; Message = '数组索引不是整数' }
        }

        if ($index -lt 0 -or $index -ge $TargetValue.Length) {
            return [PSCustomObject]@{ Success = $false; Message = '数组索引越界' }
        }

        $TargetValue[$index] = $AssignedValue
        return [PSCustomObject]@{ Success = $true; Message = $null }
    }

    return [PSCustomObject]@{ Success = $false; Message = '不支持的安全索引赋值目标' }
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

    try {
        $adaptedProperty = @(
            $TargetValue.PSObject.Properties.Match($MemberName) |
                Where-Object {
                    $_.IsGettable -and (
                        $_.MemberType -eq [System.Management.Automation.PSMemberTypes]::Property -or
                        $_.MemberType -eq [System.Management.Automation.PSMemberTypes]::AliasProperty -or
                        $_.MemberType -eq [System.Management.Automation.PSMemberTypes]::NoteProperty
                    )
                } |
                Select-Object -First 1
        )
        if ($adaptedProperty.Count -gt 0) {
            return [PSCustomObject]@{ Success = $true; Value = $adaptedProperty[0].Value; Message = $null }
        }
    } catch {
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

    $modeledType = $null
    if (Test-StaticPropertyBagValue -Value $TargetValue) {
        $typeProperty = @($TargetValue.PSObject.Properties.Match('__PsDissectType') | Select-Object -First 1)
        if ($typeProperty.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$typeProperty[0].Value)) {
            $modeledType = [string]$typeProperty[0].Value
        }
    }

    if ($modeledType -match '^(?i:WScript\.Shell\.SpecialFolders)$' -and $MemberName -match '^(?i:Item)$') {
        if (-not $Arguments -or $Arguments.Count -lt 1) {
            return [PSCustomObject]@{ Success = $false; Value = $null; Message = 'SpecialFolders.Item 缺少参数' }
        }

        $folderPath = Resolve-StaticSpecialFolderPath -Name ([string]$Arguments[0])
        if ([string]::IsNullOrWhiteSpace($folderPath)) {
            return [PSCustomObject]@{ Success = $false; Value = $null; Message = 'SpecialFolders.Item 参数不在静态支持范围内' }
        }

        return [PSCustomObject]@{
            Success = $true
            Value   = $folderPath
            Message = $null
        }
    }

    if ($modeledType -match '^(?i:WScript\.Shell)$' -and $MemberName -match '^(?i:CreateShortcut)$') {
        if (-not $Arguments -or $Arguments.Count -lt 1) {
            return [PSCustomObject]@{ Success = $false; Value = $null; Message = 'CreateShortcut 缺少参数' }
        }

        $shortcutPath = [string]$Arguments[0]
        if ([string]::IsNullOrWhiteSpace($shortcutPath)) {
            return [PSCustomObject]@{ Success = $false; Value = $null; Message = 'CreateShortcut 路径为空' }
        }

        $shortcutValue = New-StaticModeledObjectValue -TypeName 'WScript.Shell.Shortcut'
        if ($null -eq $shortcutValue) {
            return [PSCustomObject]@{ Success = $false; Value = $null; Message = 'CreateShortcut modeled object 初始化失败' }
        }

        $setShortcutPath = Set-StaticMemberAccessValue -TargetValue $shortcutValue -MemberName 'FullName' -MemberValue $shortcutPath
        if (-not $setShortcutPath.Success) {
            return [PSCustomObject]@{ Success = $false; Value = $null; Message = $setShortcutPath.Message }
        }

        return [PSCustomObject]@{
            Success = $true
            Value   = $shortcutValue
            Message = $null
        }
    }

    switch -Regex ($MemberName) {
        '^(?i:GetString)$' {
            if ($TargetValue -isnot [System.Text.Encoding]) {
                return [PSCustomObject]@{ Success = $false; Value = $null; Message = 'GetString 仅支持 Encoding 目标' }
            }
            if (-not $Arguments -or $Arguments.Count -lt 1) {
                return [PSCustomObject]@{ Success = $false; Value = $null; Message = 'GetString 缺少参数' }
            }

            $bytes = Try-ConvertToByteArrayFromStaticValue -Value $Arguments[0]
            if ($null -eq $bytes) {
                return [PSCustomObject]@{ Success = $false; Value = $null; Message = 'GetString 参数不是可转换的 byte[]' }
            }

            try {
                if ($Arguments.Count -ge 3) {
                    return [PSCustomObject]@{
                        Success = $true
                        Value   = $TargetValue.GetString($bytes, [int]$Arguments[1], [int]$Arguments[2])
                        Message = $null
                    }
                }

                return [PSCustomObject]@{
                    Success = $true
                    Value   = $TargetValue.GetString($bytes)
                    Message = $null
                }
            } catch {
                return [PSCustomObject]@{ Success = $false; Value = $null; Message = $_.Exception.Message }
            }
        }
        '^(?i:GetBytes)$' {
            if ($TargetValue -isnot [System.Text.Encoding]) {
                return [PSCustomObject]@{ Success = $false; Value = $null; Message = 'GetBytes 仅支持 Encoding 目标' }
            }
            if (-not $Arguments -or $Arguments.Count -lt 1) {
                return [PSCustomObject]@{ Success = $false; Value = $null; Message = 'GetBytes 缺少参数' }
            }

            try {
                if ($Arguments.Count -ge 3) {
                    return [PSCustomObject]@{
                        Success = $true
                        Value   = $TargetValue.GetBytes([string]$Arguments[0], [int]$Arguments[1], [int]$Arguments[2])
                        Message = $null
                    }
                }

                return [PSCustomObject]@{
                    Success = $true
                    Value   = $TargetValue.GetBytes([string]$Arguments[0])
                    Message = $null
                }
            } catch {
                return [PSCustomObject]@{ Success = $false; Value = $null; Message = $_.Exception.Message }
            }
        }
        '^(?i:Replace)$' {
            if ($TargetValue -isnot [string]) {
                return [PSCustomObject]@{ Success = $false; Value = $null; Message = 'Replace 仅支持字符串目标' }
            }
            if (-not $Arguments -or $Arguments.Count -lt 2) {
                return [PSCustomObject]@{ Success = $false; Value = $null; Message = 'Replace 缺少参数' }
            }

            try {
                $oldValue = [string]$Arguments[0]
                $newValue = [string]$Arguments[1]
                return [PSCustomObject]@{
                    Success = $true
                    Value   = ([string]$TargetValue).Replace($oldValue, $newValue)
                    Message = $null
                }
            } catch {
                return [PSCustomObject]@{ Success = $false; Value = $null; Message = $_.Exception.Message }
            }
        }
        '^(?i:ToCharArray)$' {
            if ($TargetValue -isnot [string]) {
                return [PSCustomObject]@{ Success = $false; Value = $null; Message = 'ToCharArray 仅支持字符串目标' }
            }
            if ($Arguments -and $Arguments.Count -gt 0) {
                return [PSCustomObject]@{ Success = $false; Value = $null; Message = 'ToCharArray 暂仅支持无参调用' }
            }

            try {
                return [PSCustomObject]@{
                    Success = $true
                    Value   = ([string]$TargetValue).ToCharArray()
                    Message = $null
                }
            } catch {
                return [PSCustomObject]@{ Success = $false; Value = $null; Message = $_.Exception.Message }
            }
        }
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

    if ($TargetType -eq [string] -and $MemberName -match '^(?i:Concat)$') {
        if (-not $Arguments -or $Arguments.Count -lt 1) {
            return [PSCustomObject]@{ Success = $false; Value = $null; Message = 'String::Concat 缺少参数' }
        }

        try {
            $parts = New-Object System.Collections.Generic.List[string]
            foreach ($arg in @($Arguments)) {
                if (($arg -is [System.Collections.IEnumerable]) -and -not ($arg -is [string])) {
                    foreach ($item in @($arg)) {
                        $parts.Add([string]$item) | Out-Null
                    }
                } else {
                    $parts.Add([string]$arg) | Out-Null
                }
            }

            return [PSCustomObject]@{
                Success = $true
                Value   = [string]::Concat(@($parts.ToArray()))
                Message = $null
            }
        } catch {
            return [PSCustomObject]@{ Success = $false; Value = $null; Message = $_.Exception.Message }
        }
    }

    if ($TargetType -eq [Convert] -or $TargetType.FullName -eq 'System.Convert') {
        if ($MemberName -match '^(?i:FromBase64String)$') {
            if (-not $Arguments -or $Arguments.Count -lt 1) {
                return [PSCustomObject]@{ Success = $false; Value = $null; Message = 'Convert::FromBase64String 缺少参数' }
            }

            $bytes = Try-DecodeBase64ToByteArray -Base64String ([string]$Arguments[0])
            if ($null -eq $bytes) {
                return [PSCustomObject]@{ Success = $false; Value = $null; Message = 'Convert::FromBase64String 解码失败' }
            }

            return [PSCustomObject]@{
                Success = $true
                Value   = $bytes
                Message = $null
            }
        }

        if ($MemberName -match '^(?i:FromBase64CharArray)$') {
            if (-not $Arguments -or $Arguments.Count -lt 1) {
                return [PSCustomObject]@{ Success = $false; Value = $null; Message = 'Convert::FromBase64CharArray 缺少参数' }
            }

            $startIndex = 0
            $length = -1
            if ($Arguments.Count -ge 3) {
                try {
                    $startIndex = [int]$Arguments[1]
                    $length = [int]$Arguments[2]
                } catch {
                    return [PSCustomObject]@{ Success = $false; Value = $null; Message = 'Convert::FromBase64CharArray 参数类型无效' }
                }
            }

            $bytes = Try-DecodeBase64CharArrayToByteArray -Value $Arguments[0] -StartIndex $startIndex -Length $length
            if ($null -eq $bytes) {
                return [PSCustomObject]@{ Success = $false; Value = $null; Message = 'Convert::FromBase64CharArray 解码失败' }
            }

            return [PSCustomObject]@{
                Success = $true
                Value   = $bytes
                Message = $null
            }
        }
    }

    if (($TargetType -eq [array] -or $TargetType.FullName -eq 'System.Array') -and $MemberName -match '^(?i:Reverse)$') {
        if (-not $Arguments -or $Arguments.Count -lt 1) {
            return [PSCustomObject]@{ Success = $false; Value = $null; Message = 'Array::Reverse 缺少参数' }
        }

        try {
            if ($Arguments.Count -ge 3) {
                [Array]::Reverse($Arguments[0], [int]$Arguments[1], [int]$Arguments[2])
            } else {
                [Array]::Reverse($Arguments[0])
            }

            return [PSCustomObject]@{
                Success = $true
                Value   = $null
                Message = $null
            }
        } catch {
            return [PSCustomObject]@{ Success = $false; Value = $null; Message = $_.Exception.Message }
        }
    }

    if (($TargetType -eq [regex] -or $TargetType.FullName -eq 'System.Text.RegularExpressions.Regex') -and $MemberName -match '^(?i:Matches)$') {
        if (-not $Arguments -or $Arguments.Count -lt 2) {
            return [PSCustomObject]@{ Success = $false; Value = $null; Message = 'Regex::Matches 缺少参数' }
        }

        try {
            if ($Arguments.Count -ge 3) {
                $options = if ($Arguments[2] -is [System.Text.RegularExpressions.RegexOptions]) {
                    $Arguments[2]
                } else {
                    [System.Text.RegularExpressions.RegexOptions]$Arguments[2]
                }
                $matches = [regex]::Matches([string]$Arguments[0], [string]$Arguments[1], $options)
            } else {
                $matches = [regex]::Matches([string]$Arguments[0], [string]$Arguments[1])
            }

            return [PSCustomObject]@{
                Success = $true
                Value   = $matches
                Message = $null
            }
        } catch {
            return [PSCustomObject]@{ Success = $false; Value = $null; Message = $_.Exception.Message }
        }
    }

    if ($TargetType.FullName -eq 'System.IO.Path' -and $MemberName -match '^(?i:Combine)$') {
        if (-not $Arguments -or $Arguments.Count -lt 2) {
            return [PSCustomObject]@{ Success = $false; Value = $null; Message = 'Path::Combine 缺少参数' }
        }

        try {
            $parts = New-Object System.Collections.Generic.List[string]
            foreach ($arg in @($Arguments)) {
                if (($arg -is [System.Collections.IEnumerable]) -and -not ($arg -is [string])) {
                    foreach ($item in @($arg)) {
                        $parts.Add([string]$item) | Out-Null
                    }
                } else {
                    $parts.Add([string]$arg) | Out-Null
                }
            }

            $combinedPath = [string]$parts[0]
            for ($i = 1; $i -lt $parts.Count; $i++) {
                $combinedPath = [System.IO.Path]::Combine($combinedPath, [string]$parts[$i])
            }

            return [PSCustomObject]@{
                Success = $true
                Value   = $combinedPath
                Message = $null
            }
        } catch {
            return [PSCustomObject]@{ Success = $false; Value = $null; Message = $_.Exception.Message }
        }
    }

    if ($TargetType.FullName -eq 'System.Environment' -and $MemberName -match '^(?i:GetFolderPath)$') {
        if (-not $Arguments -or $Arguments.Count -lt 1) {
            return [PSCustomObject]@{ Success = $false; Value = $null; Message = 'Environment::GetFolderPath 缺少参数' }
        }

        try {
            $folder = if ($Arguments[0] -is [System.Environment+SpecialFolder]) {
                $Arguments[0]
            } elseif ($Arguments[0] -is [string]) {
                [System.Enum]::Parse([System.Environment+SpecialFolder], [string]$Arguments[0], $true)
            } else {
                [System.Environment+SpecialFolder][int]$Arguments[0]
            }

            return [PSCustomObject]@{
                Success = $true
                Value   = [System.Environment]::GetFolderPath($folder)
                Message = $null
            }
        } catch {
            return [PSCustomObject]@{ Success = $false; Value = $null; Message = $_.Exception.Message }
        }
    }

    if ($TargetType.FullName -eq 'System.IO.Path' -and $MemberName -match '^(?i:GetTempPath)$') {
        if ($Arguments -and $Arguments.Count -gt 0) {
            return [PSCustomObject]@{ Success = $false; Value = $null; Message = 'Path::GetTempPath 暂仅支持无参调用' }
        }

        try {
            return [PSCustomObject]@{
                Success = $true
                Value   = [System.IO.Path]::GetTempPath()
                Message = $null
            }
        } catch {
            return [PSCustomObject]@{ Success = $false; Value = $null; Message = $_.Exception.Message }
        }
    }

    if ($TargetType.FullName -eq 'System.Environment' -and $MemberName -match '^(?i:GetEnvironmentVariable)$') {
        if (-not $Arguments -or $Arguments.Count -lt 1) {
            return [PSCustomObject]@{ Success = $false; Value = $null; Message = 'Environment::GetEnvironmentVariable 缺少参数' }
        }

        try {
            $envName = [string]$Arguments[0]
            if ([string]::IsNullOrWhiteSpace($envName)) {
                return [PSCustomObject]@{ Success = $false; Value = $null; Message = 'Environment::GetEnvironmentVariable 参数为空' }
            }

            $value = $null
            if ($Arguments.Count -ge 2) {
                $target = if ($Arguments[1] -is [System.EnvironmentVariableTarget]) {
                    [System.EnvironmentVariableTarget]$Arguments[1]
                } elseif ($Arguments[1] -is [string]) {
                    [System.Enum]::Parse([System.EnvironmentVariableTarget], [string]$Arguments[1], $true)
                } else {
                    [System.EnvironmentVariableTarget][int]$Arguments[1]
                }
                $value = [System.Environment]::GetEnvironmentVariable($envName, $target)
            } else {
                foreach ($scope in @([System.EnvironmentVariableTarget]::Process, [System.EnvironmentVariableTarget]::User, [System.EnvironmentVariableTarget]::Machine)) {
                    $value = [System.Environment]::GetEnvironmentVariable($envName, $scope)
                    if (-not [string]::IsNullOrWhiteSpace([string]$value)) {
                        break
                    }
                }
            }

            return [PSCustomObject]@{
                Success = $true
                Value   = $value
                Message = $null
            }
        } catch {
            return [PSCustomObject]@{ Success = $false; Value = $null; Message = $_.Exception.Message }
        }
    }

    if ($TargetType.FullName -eq 'System.Environment' -and $MemberName -match '^(?i:ExpandEnvironmentVariables)$') {
        if (-not $Arguments -or $Arguments.Count -lt 1) {
            return [PSCustomObject]@{ Success = $false; Value = $null; Message = 'Environment::ExpandEnvironmentVariables 缺少参数' }
        }

        try {
            return [PSCustomObject]@{
                Success = $true
                Value   = [System.Environment]::ExpandEnvironmentVariables([string]$Arguments[0])
                Message = $null
            }
        } catch {
            return [PSCustomObject]@{ Success = $false; Value = $null; Message = $_.Exception.Message }
        }
    }

    if ($TargetType.FullName -eq 'System.IO.File' -and $MemberName -match '^(?i:ReadAllBytes)$') {
        if (-not $Arguments -or $Arguments.Count -lt 1) {
            return [PSCustomObject]@{ Success = $false; Value = $null; Message = 'File::ReadAllBytes 缺少参数' }
        }

        try {
            $path = [string]$Arguments[0]
            if ([string]::IsNullOrWhiteSpace($path)) {
                return [PSCustomObject]@{ Success = $false; Value = $null; Message = 'File::ReadAllBytes 路径为空' }
            }
            if (Test-Path -LiteralPath $path) {
                return [PSCustomObject]@{
                    Success = $true
                    Value   = [System.IO.File]::ReadAllBytes($path)
                    Message = $null
                }
            }
        } catch {
            return [PSCustomObject]@{ Success = $false; Value = $null; Message = $_.Exception.Message }
        }

        return [PSCustomObject]@{ Success = $false; Value = $null; Message = 'File::ReadAllBytes 目标不存在' }
    }

    if ($TargetType.FullName -eq 'System.IO.File' -and $MemberName -match '^(?i:ReadAllText)$') {
        if (-not $Arguments -or $Arguments.Count -lt 1) {
            return [PSCustomObject]@{ Success = $false; Value = $null; Message = 'File::ReadAllText 缺少参数' }
        }

        try {
            $path = [string]$Arguments[0]
            if ([string]::IsNullOrWhiteSpace($path)) {
                return [PSCustomObject]@{ Success = $false; Value = $null; Message = 'File::ReadAllText 路径为空' }
            }
            if (Test-Path -LiteralPath $path) {
                return [PSCustomObject]@{
                    Success = $true
                    Value   = [System.IO.File]::ReadAllText($path)
                    Message = $null
                }
            }
        } catch {
            return [PSCustomObject]@{ Success = $false; Value = $null; Message = $_.Exception.Message }
        }

        return [PSCustomObject]@{ Success = $false; Value = $null; Message = 'File::ReadAllText 目标不存在' }
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

function Try-NormalizeBase64String {
    param(
        [AllowNull()][string]$Base64String,
        [bool]$AllowUrlSafe = $true
    )

    if ([string]::IsNullOrWhiteSpace($Base64String)) {
        return $null
    }

    $normalized = ([string]$Base64String).Trim()
    $normalized = [regex]::Replace($normalized, '\s+', '')
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return $null
    }

    if ($AllowUrlSafe -and ($normalized.Contains('-') -or $normalized.Contains('_'))) {
        $normalized = $normalized.Replace('-', '+').Replace('_', '/')
    }

    if ($normalized -notmatch '^[A-Za-z0-9+/=]+$') {
        return $null
    }

    $paddingIndex = $normalized.IndexOf('=')
    if ($paddingIndex -ge 0) {
        $trimmedPadding = $normalized.Substring(0, $paddingIndex)
        $padding = $normalized.Substring($paddingIndex)
        if ($trimmedPadding.Contains('=') -or $padding -notmatch '^={0,2}$') {
            return $null
        }
    }

    $remainder = $normalized.Length % 4
    if ($remainder -eq 1) {
        return $null
    }
    if ($remainder -gt 0) {
        $normalized = $normalized.PadRight($normalized.Length + (4 - $remainder), '=')
    }

    return $normalized
}

function Try-DecodeBase64ToByteArray {
    param(
        [AllowNull()][string]$Base64String,
        [bool]$AllowUrlSafe = $true
    )

    $normalized = Try-NormalizeBase64String -Base64String $Base64String -AllowUrlSafe:$AllowUrlSafe
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return $null
    }

    try {
        return [Convert]::FromBase64String($normalized)
    } catch {
        return $null
    }
}

function Convert-StaticValueToBase64CharArrayText {
    param(
        $Value,
        [int]$StartIndex = 0,
        [int]$Length = -1
    )

    if ($Value -is [psobject] -and $null -ne $Value.BaseObject -and $Value.BaseObject -ne $Value) {
        $Value = $Value.BaseObject
    }

    if ($null -eq $Value) {
        return $null
    }

    $text = $null
    if ($Value -is [string]) {
        $text = [string]$Value
    } elseif ($Value -is [char[]]) {
        $text = -join $Value
    } elseif (($Value -is [System.Collections.IEnumerable]) -and -not ($Value -is [string])) {
        try {
            $chars = @($Value | ForEach-Object { [char]$_ })
            $text = -join $chars
        } catch {
            $text = $null
        }
    }

    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }

    if ($StartIndex -lt 0 -or $StartIndex -gt $text.Length) {
        return $null
    }

    $effectiveLength = if ($Length -lt 0) { $text.Length - $StartIndex } else { $Length }
    if ($effectiveLength -lt 0 -or ($StartIndex + $effectiveLength) -gt $text.Length) {
        return $null
    }

    return $text.Substring($StartIndex, $effectiveLength)
}

function Try-DecodeBase64CharArrayToByteArray {
    param(
        $Value,
        [int]$StartIndex = 0,
        [int]$Length = -1,
        [bool]$AllowUrlSafe = $true
    )

    $text = Convert-StaticValueToBase64CharArrayText -Value $Value -StartIndex $StartIndex -Length $Length
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }

    return Try-DecodeBase64ToByteArray -Base64String $text -AllowUrlSafe:$AllowUrlSafe
}

function Try-DecodeEncodedCommandValue {
    param([Parameter(Mandatory)][string]$Base64String)

    $bytes = Try-DecodeBase64ToByteArray -Base64String $Base64String
    if ($null -eq $bytes -or $bytes.Length -eq 0) {
        return $null
    }

    try {
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

function Remove-RecoveredTextTransportArtifacts {
    param([AllowNull()][string]$Text)

    if ($null -eq $Text) {
        return $null
    }

    $clean = [string]$Text
    if ($clean.Length -gt 0 -and [int][char]$clean[0] -eq 0xFEFF) {
        $clean = $clean.Substring(1)
    }

    $clean = $clean -replace "`0+$", ''
    $clean = $clean.Trim()
    if ([string]::IsNullOrWhiteSpace($clean)) {
        return $null
    }

    return $clean
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
    if (Test-PowerShellHostParameterPrefix -ParameterName $ParameterName -CanonicalName 'file') {
        return [PSCustomObject]@{ CanonicalName = 'file'; DynamicType = $null; ExpectsValue = $true }
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

    $prefixText = $text.Substring(0, $hostMatch.Index)
    $prefixTrimmed = $prefixText.Trim()
    if (-not [string]::IsNullOrWhiteSpace($prefixTrimmed) -and
        $prefixTrimmed -notmatch '^(?i)(?:&|\.|cmd(?:\.exe)?\s+/c|cmd(?:\.exe)?\s+/r)$') {
        return $null
    }

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

    $topLevelCommand = Get-SingleTopLevelCommandAst -ScriptText $ScriptText
    if ($topLevelCommand) {
        $topLevelName = Convert-DynamicCommandCandidateToName -Value $topLevelCommand.GetCommandName()
        if (-not [string]::IsNullOrWhiteSpace($topLevelName) -and
            $topLevelName -notmatch '^(?i:cmd|cmd\.exe)$') {
            return $null
        }
    }

    return Try-GetWholeScriptHostPayloadInfoLoose -ScriptText $ScriptText
}

function Test-IsCallDepthOverflowException {
    param($ErrorObject)

    if ($null -eq $ErrorObject) {
        return $false
    }

    $fullyQualifiedErrorId = $null
    $message = $null
    $exception = $null

    if ($ErrorObject -is [System.Management.Automation.ErrorRecord]) {
        $fullyQualifiedErrorId = [string]$ErrorObject.FullyQualifiedErrorId
        $exception = $ErrorObject.Exception
        if ($exception -and -not [string]::IsNullOrWhiteSpace([string]$exception.Message)) {
            $message = [string]$exception.Message
        } else {
            $message = [string]$ErrorObject
        }
    } else {
        if ($ErrorObject.PSObject.Properties['FullyQualifiedErrorId']) {
            $fullyQualifiedErrorId = [string]$ErrorObject.FullyQualifiedErrorId
        }
        if ($ErrorObject -is [System.Exception]) {
            $exception = $ErrorObject
            $message = [string]$ErrorObject.Message
        } elseif ($ErrorObject.PSObject.Properties['Exception']) {
            $exception = $ErrorObject.Exception
            if ($exception -and -not [string]::IsNullOrWhiteSpace([string]$exception.Message)) {
                $message = [string]$exception.Message
            }
        }
        if ([string]::IsNullOrWhiteSpace($message)) {
            $message = [string]$ErrorObject
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($fullyQualifiedErrorId) -and $fullyQualifiedErrorId -match '(?i)CallDepthOverflow') {
        return $true
    }

    if (-not [string]::IsNullOrWhiteSpace($message) -and $message -match '(?i)call depth overflow') {
        return $true
    }

    $current = $exception
    $guard = 0
    while ($current -and $guard -lt 16) {
        $currentMessage = if (-not [string]::IsNullOrWhiteSpace([string]$current.Message)) {
            [string]$current.Message
        } else {
            [string]$current
        }
        if ($currentMessage -match '(?i)call depth overflow') {
            return $true
        }
        $current = $current.InnerException
        $guard++
    }

    return $false
}

function Get-ErrorSummaryText {
    param(
        $ErrorObject,
        [string]$DefaultMessage = 'unknown error'
    )

    if ($null -eq $ErrorObject) {
        return $DefaultMessage
    }

    $message = $null
    if ($ErrorObject -is [System.Management.Automation.ErrorRecord]) {
        if ($ErrorObject.Exception -and -not [string]::IsNullOrWhiteSpace([string]$ErrorObject.Exception.Message)) {
            $message = [string]$ErrorObject.Exception.Message
        } else {
            $message = [string]$ErrorObject
        }
    } elseif ($ErrorObject -is [System.Exception]) {
        $message = [string]$ErrorObject.Message
    } elseif ($ErrorObject.PSObject.Properties['Exception'] -and $ErrorObject.Exception -and -not [string]::IsNullOrWhiteSpace([string]$ErrorObject.Exception.Message)) {
        $message = [string]$ErrorObject.Exception.Message
    } else {
        $message = [string]$ErrorObject
    }

    if ([string]::IsNullOrWhiteSpace($message)) {
        $message = $DefaultMessage
    }

    return (($message -replace '[\r\n]+', ' ').Trim())
}

function Try-Resolve-WholeScriptStaticCompressedLoaderPayloadInfo {
    param(
        [Parameter(Mandatory)][string]$ScriptText
    )

    if ([string]::IsNullOrWhiteSpace($ScriptText)) {
        return $null
    }
    if ($ScriptText -notmatch '(?i)\bFromBase64String\b' -or
        $ScriptText -notmatch '(?i)\b(?:DeflateStream|GZipStream)\b' -or
        $ScriptText -notmatch '(?i)\bReadToEnd\b') {
        return $null
    }

    $statements = @(Get-TopLevelScriptStatementsFromText -ScriptText $ScriptText)
    if ($statements.Count -eq 0) {
        return $null
    }

    $ctx = New-WholeScriptStaticResolutionContext
    try {
        $staticEvalState = Get-StaticEvalState -Context $ctx
        if ($staticEvalState) {
            $staticEvalState.ValueDepthLimit = 64
            $staticEvalState.StringCompatDepthLimit = 48
        }
        $ctx.SafeMode = $true

        $prefixStatements = @()
        if ($statements.Count -gt 1) {
            $prefixStatements = @($statements | Select-Object -First ($statements.Count - 1))
            [void](Initialize-WholeScriptStaticAssignments -Statements $prefixStatements -Context $ctx)
        }

        $targetStatement = $statements[-1]
        $tryCandidate = {
            param(
                $Ast,
                [string]$Source
            )

            if ($null -eq $Ast) {
                return $null
            }

            $extentText = if ($Ast.PSObject.Properties['Extent'] -and $Ast.Extent) {
                [string]$Ast.Extent.Text
            } else {
                ''
            }
            if ($extentText -notmatch '(?i)\bFromBase64String\b' -or
                $extentText -notmatch '(?i)\b(?:DeflateStream|GZipStream)\b' -or
                $extentText -notmatch '(?i)\bReadToEnd\b') {
                return $null
            }

            $decoded = Try-DecodeStaticScriptTextFromAst -Ast $Ast -Context $ctx
            if ([string]::IsNullOrWhiteSpace($decoded)) {
                return $null
            }

            $candidateText = Try-NormalizeRecoveredScriptText -Text $decoded
            if (-not $candidateText) {
                $candidateText = Remove-RecoveredTextTransportArtifacts -Text $decoded
                if (-not [string]::IsNullOrWhiteSpace($candidateText)) {
                    $normalizedPlain = Invoke-NormalizePlainScriptText -ScriptText $candidateText
                    if (-not [string]::IsNullOrWhiteSpace($normalizedPlain)) {
                        $candidateText = Remove-RecoveredTextTransportArtifacts -Text $normalizedPlain
                    }
                }
            }

            $payloadText = Get-WholeScriptReplacementCandidateText -OriginalText $ScriptText -CandidateText $candidateText
            if (-not [string]::IsNullOrWhiteSpace($payloadText)) {
                return [PSCustomObject]@{
                    PayloadText  = [string]$payloadText
                    DecodeSource = [string]$Source
                }
            }

            return $null
        }

        $payloadInfo = $null
        if ($targetStatement -is [System.Management.Automation.Language.CommandAst]) {
            $dynamicInfo = Get-CommandAstStaticDynamicPayloadInfo -CommandAst $targetStatement -Context $ctx -PrefixStatements $prefixStatements
            if ($dynamicInfo -and $dynamicInfo.ArgumentAst) {
                $payloadInfo = & $tryCandidate $dynamicInfo.ArgumentAst 'static_compressed_loader_command'
            }
            if (-not $payloadInfo) {
                $payloadInfo = & $tryCandidate $targetStatement 'static_compressed_loader_statement'
            }
        } elseif ($targetStatement -is [System.Management.Automation.Language.PipelineAst]) {
            $elements = @($targetStatement.PipelineElements)
            if ($elements.Count -eq 1 -and $elements[0] -is [System.Management.Automation.Language.CommandAst]) {
                $dynamicInfo = Get-CommandAstStaticDynamicPayloadInfo -CommandAst $elements[0] -Context $ctx -PrefixStatements $prefixStatements
                if ($dynamicInfo -and $dynamicInfo.ArgumentAst) {
                    $payloadInfo = & $tryCandidate $dynamicInfo.ArgumentAst 'static_compressed_loader_pipeline_command'
                }
                if (-not $payloadInfo) {
                    $payloadInfo = & $tryCandidate $elements[0] 'static_compressed_loader_pipeline_statement'
                }
            } elseif ($elements.Count -eq 2 -and $elements[-1] -is [System.Management.Automation.Language.CommandAst]) {
                $sinkInfo = Get-CommandAstStaticDynamicPayloadInfo -CommandAst $elements[-1] -Context $ctx -PrefixStatements $prefixStatements
                if ($sinkInfo -and [string]$sinkInfo.DynamicType -eq 'IEX') {
                    $sourceAst = $elements[0]
                    if ($elements[0] -is [System.Management.Automation.Language.CommandExpressionAst]) {
                        $sourceAst = $elements[0].Expression
                    } elseif ($elements[0].PSObject.Properties['Expression']) {
                        $sourceAst = $elements[0].Expression
                    }
                    $payloadInfo = & $tryCandidate $sourceAst 'static_compressed_loader_pipeline_iex'
                }
                if (-not $payloadInfo) {
                    $payloadInfo = & $tryCandidate $targetStatement 'static_compressed_loader_pipeline'
                }
            } else {
                $payloadInfo = & $tryCandidate $targetStatement 'static_compressed_loader_pipeline'
            }
        }

        if (-not $payloadInfo) {
            $singleExpr = Get-SingleTopLevelExpressionAstFromText -ScriptText $ScriptText
            if ($singleExpr) {
                $payloadInfo = & $tryCandidate $singleExpr 'static_compressed_loader_expression'
            }
        }

        return $payloadInfo
    } finally {
        Close-WholeScriptStaticResolutionContext -Context $ctx
    }
}

function Try-Resolve-WholeScriptStaticPayloadInfoSafe {
    param(
        [Parameter(Mandatory)][string]$ScriptText,
        [string]$WarningContext = 'whole_script_static',
        [ValidateSet('Disabled', 'Conservative', 'Balanced', 'Aggressive')]
        [string]$PreExecutionGateMode = 'Disabled',
        [hashtable]$PreExecutionGateCache = $null,
        [bool]$SafeMode = $true
    )

    $compressedLoaderPayload = Try-Resolve-WholeScriptStaticCompressedLoaderPayloadInfo -ScriptText $ScriptText
    if ($compressedLoaderPayload -and -not [string]::IsNullOrWhiteSpace([string]$compressedLoaderPayload.PayloadText)) {
        return $compressedLoaderPayload
    }

    $gate = Get-PreExecutionGateDecision -Scope 'WholeScriptHelper' -ScriptText $ScriptText -Mode $PreExecutionGateMode -SafeMode:$SafeMode -Cache $PreExecutionGateCache
    if ([string]$gate.Decision -eq 'Stop') {
        Write-Warning ("[WholeScriptStatic] 静态恢复已跳过（{0}），命中先审后执行门控: {1}" -f $WarningContext, ((@($gate.Reasons) -join ', ')))
        return $null
    }

    try {
        return Resolve-WholeScriptStaticPayloadInfo -ScriptText $ScriptText -PreExecutionGateMode $PreExecutionGateMode -PreExecutionGateCache $PreExecutionGateCache -SafeMode:$SafeMode
    } catch {
        if (-not (Test-IsCallDepthOverflowException -ErrorObject $_)) {
            throw
        }

        $warningDetail = $null
        if ($_ -and $_.Exception -and -not [string]::IsNullOrWhiteSpace([string]$_.Exception.Message)) {
            $warningDetail = ([string]$_.Exception.Message -replace '[\r\n]+', ' ').Trim()
        } elseif ($_ -and -not [string]::IsNullOrWhiteSpace([string]$_)) {
            $warningDetail = ([string]$_ -replace '[\r\n]+', ' ').Trim()
        }
        if ([string]::IsNullOrWhiteSpace($warningDetail)) {
            $warningDetail = 'call depth overflow'
        }

        Write-Warning ("[WholeScriptStatic] 静态恢复已跳过（{0}），保留当前脚本文本: {1}" -f $WarningContext, $warningDetail)
        return $null
    }
}

function Try-Resolve-GatedRoundSafePayloadInfo {
    param(
        [Parameter(Mandatory)][string]$ScriptText,
        [AllowNull()][string]$OriginalText = $null,
        [hashtable]$PreExecutionGateCache = $null
    )

    if ([string]::IsNullOrWhiteSpace($ScriptText)) {
        return $null
    }

    $inlinePayload = Try-Resolve-WholeScriptInlineFileWritePayloadInfo -ScriptText $ScriptText
    if ($inlinePayload -and -not [string]::IsNullOrWhiteSpace([string]$inlinePayload.PayloadText)) {
        return [PSCustomObject]@{
            PayloadText = [string]$inlinePayload.PayloadText
            Source      = if ($inlinePayload.PSObject.Properties['DecodeSource']) { [string]$inlinePayload.DecodeSource } else { 'inline_file_write' }
        }
    }

    $attempts = @()

    $bootstrapHelperPayload = Try-Resolve-GatedRoundBootstrapHelperPayloadInfo -ScriptText $ScriptText -PreExecutionGateCache $PreExecutionGateCache
    if ($bootstrapHelperPayload -and -not [string]::IsNullOrWhiteSpace([string]$bootstrapHelperPayload.PayloadText)) {
        $attempts += [PSCustomObject]@{
            PayloadText = [string]$bootstrapHelperPayload.PayloadText
            Source      = if ($bootstrapHelperPayload.PSObject.Properties['Source']) { [string]$bootstrapHelperPayload.Source } else { 'gated_helper_bootstrap' }
        }
    }

    $mandatoryBase64Payload = Try-Resolve-WholeScriptMandatoryBase64PayloadInfo -ScriptText $ScriptText
    if ($mandatoryBase64Payload -and -not [string]::IsNullOrWhiteSpace([string]$mandatoryBase64Payload.PayloadText)) {
        $attempts += [PSCustomObject]@{
            PayloadText = [string]$mandatoryBase64Payload.PayloadText
            Source      = if ($mandatoryBase64Payload.PSObject.Properties['DecodeSource']) { [string]$mandatoryBase64Payload.DecodeSource } else { 'mandatory_base64_payload' }
        }
    }

    $compressedLoaderPayload = Try-Resolve-WholeScriptStaticCompressedLoaderPayloadInfo -ScriptText $ScriptText
    if ($compressedLoaderPayload -and -not [string]::IsNullOrWhiteSpace([string]$compressedLoaderPayload.PayloadText)) {
        $attempts += [PSCustomObject]@{
            PayloadText = [string]$compressedLoaderPayload.PayloadText
            Source      = if ($compressedLoaderPayload.PSObject.Properties['DecodeSource']) { [string]$compressedLoaderPayload.DecodeSource } else { 'static_compressed_loader' }
        }
    }

    $hostPayload = Resolve-WholeScriptHostPayloadInfo -ScriptText $ScriptText
    if ($hostPayload -and -not [string]::IsNullOrWhiteSpace([string]$hostPayload.PayloadText)) {
        $attempts += [PSCustomObject]@{
            PayloadText = [string]$hostPayload.PayloadText
            Source      = if ($hostPayload.PSObject.Properties['DecodeSource']) { [string]$hostPayload.DecodeSource } else { 'host_wrapper_decode' }
        }
    }

    $intermediatePrefixPayload = Try-Resolve-GatedRoundIntermediatePrefixPayloadInfo -ScriptText $ScriptText -PreExecutionGateCache $PreExecutionGateCache
    if ($intermediatePrefixPayload -and -not [string]::IsNullOrWhiteSpace([string]$intermediatePrefixPayload.PayloadText)) {
        $attempts += [PSCustomObject]@{
            PayloadText = [string]$intermediatePrefixPayload.PayloadText
            Source      = if ($intermediatePrefixPayload.PSObject.Properties['Source']) { [string]$intermediatePrefixPayload.Source } else { 'gated_intermediate_prefix_payload' }
        }
    }

    $artifactPayload = Try-Resolve-WholeScriptInlineFileWritePayloadInfo -ScriptText $ScriptText
    if ($artifactPayload -and -not [string]::IsNullOrWhiteSpace([string]$artifactPayload.PayloadText)) {
        $attempts += [PSCustomObject]@{
            PayloadText = [string]$artifactPayload.PayloadText
            Source      = if ($artifactPayload.PSObject.Properties['DecodeSource']) { [string]$artifactPayload.DecodeSource } else { 'inline_file_write' }
        }
    }

    try {
        $staticPayload = Resolve-WholeScriptStaticPayloadInfo -ScriptText $ScriptText -PreExecutionGateMode 'Disabled' -PreExecutionGateCache $PreExecutionGateCache -SafeMode:$false
    } catch {
        $staticPayload = $null
    }
    if ($staticPayload -and -not [string]::IsNullOrWhiteSpace([string]$staticPayload.PayloadText)) {
        $attempts += [PSCustomObject]@{
            PayloadText = [string]$staticPayload.PayloadText
            Source      = if ($staticPayload.PSObject.Properties['DecodeSource']) { [string]$staticPayload.DecodeSource } else { 'gated_static_payload' }
        }
    }

    $comparisonOriginal = if (-not [string]::IsNullOrWhiteSpace($OriginalText)) { [string]$OriginalText } else { [string]$ScriptText }
    foreach ($attempt in @($attempts)) {
        if ($null -eq $attempt -or [string]::IsNullOrWhiteSpace([string]$attempt.PayloadText)) {
            continue
        }

        if ([string]$attempt.Source -eq 'inline_file_write') {
            $inlinePayloadText = [string]$attempt.PayloadText
            if (-not [string]::IsNullOrWhiteSpace($inlinePayloadText) -and (Test-UsefulRecoveredScriptText -Text $inlinePayloadText)) {
                if (-not [string]::IsNullOrWhiteSpace($comparisonOriginal)) {
                    $originalNorm = Get-NormalizedScriptComparisonText -ScriptText $comparisonOriginal
                    $candidateNorm = Get-NormalizedScriptComparisonText -ScriptText $inlinePayloadText
                    if (-not [string]::IsNullOrWhiteSpace($candidateNorm) -and $candidateNorm -eq $originalNorm) {
                        continue
                    }
                }

                return [PSCustomObject]@{
                    PayloadText = $inlinePayloadText
                    Source      = [string]$attempt.Source
                }
            }
        }

        $candidateText = Get-WholeScriptReplacementCandidateText -OriginalText $comparisonOriginal -CandidateText ([string]$attempt.PayloadText)
        if (-not $candidateText -and $comparisonOriginal -ne $ScriptText) {
            $candidateText = Get-WholeScriptReplacementCandidateText -OriginalText $ScriptText -CandidateText ([string]$attempt.PayloadText)
        }
        if ([string]::IsNullOrWhiteSpace($candidateText)) {
            continue
        }
        if (-not (Test-UsefulRecoveredScriptText -Text $candidateText)) {
            continue
        }

        $parse = Get-ScriptParseInfo -ScriptText $candidateText
        if (-not $parse.IsValid) {
            continue
        }

        return [PSCustomObject]@{
            PayloadText = [string]$candidateText
            Source      = [string]$attempt.Source
        }
    }

    return $null
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

function Get-WholeScriptCandidateTopLevelCommandName {
    param([AllowNull()][string]$ScriptText)

    if ([string]::IsNullOrWhiteSpace($ScriptText)) {
        return $null
    }

    $commandAst = Get-SingleTopLevelCommandAst -ScriptText $ScriptText
    if ($null -eq $commandAst) {
        return $null
    }

    $cmdName = Convert-DynamicCommandCandidateToName -Value $commandAst.GetCommandName()
    if ([string]::IsNullOrWhiteSpace($cmdName)) {
        return $null
    }

    $canonical = Resolve-CanonicalCommandNameText -Name $cmdName
    if (-not [string]::IsNullOrWhiteSpace($canonical)) {
        return [string]$canonical
    }

    return [string]$cmdName
}

function Get-WholeScriptTrailingStatementAnchorsAfterIex {
    param([AllowNull()][string]$ScriptText)

    if ([string]::IsNullOrWhiteSpace($ScriptText)) {
        return @()
    }

    $statements = @(Get-TopLevelScriptStatementsFromText -ScriptText $ScriptText)
    if ($statements.Count -lt 2) {
        return @()
    }

    for ($i = 0; $i -lt ($statements.Count - 1); $i++) {
        $statement = $statements[$i]
        if ($null -eq $statement -or -not $statement.Extent) {
            continue
        }

        $statementText = [string]$statement.Extent.Text
        if ([string]::IsNullOrWhiteSpace($statementText) -or
            $statementText -notmatch '(?i)\b(?:Invoke-Expression|IEX)\b') {
            continue
        }

        $anchors = New-Object 'System.Collections.Generic.List[string]'
        for ($j = $i + 1; $j -lt $statements.Count; $j++) {
            $tailText = if ($statements[$j] -and $statements[$j].Extent) {
                ([string]$statements[$j].Extent.Text).Trim()
            } else {
                ''
            }

            if ([string]::IsNullOrWhiteSpace($tailText)) {
                continue
            }
            if ($tailText -match '^(?m)\s*#') {
                continue
            }

            $anchors.Add($tailText) | Out-Null
            if ($anchors.Count -ge 4) {
                break
            }
        }

        if ($anchors.Count -gt 0) {
            return @($anchors.ToArray())
        }
    }

    return @()
}

function Test-WholeScriptCandidateLooksTruncatedTail {
    param(
        [AllowNull()][string]$OriginalText,
        [AllowNull()][string]$CandidateText
    )

    if ([string]::IsNullOrWhiteSpace($OriginalText) -or [string]::IsNullOrWhiteSpace($CandidateText)) {
        return $false
    }

    $original = ([string]$OriginalText).Trim()
    $candidate = ([string]$CandidateText).Trim()
    if ([string]::IsNullOrWhiteSpace($original) -or [string]::IsNullOrWhiteSpace($candidate)) {
        return $false
    }

    $tailAnchors = @(Get-WholeScriptTrailingStatementAnchorsAfterIex -ScriptText $original)
    if ($tailAnchors.Count -gt 0) {
        $candidateNormAll = Get-NormalizedScriptComparisonText -ScriptText $candidate
        $preservedTail = $false
        foreach ($anchor in $tailAnchors) {
            $anchorNorm = Get-NormalizedScriptComparisonText -ScriptText ([string]$anchor)
            if (-not [string]::IsNullOrWhiteSpace($anchorNorm) -and
                -not [string]::IsNullOrWhiteSpace($candidateNormAll) -and
                $candidateNormAll.Contains($anchorNorm)) {
                $preservedTail = $true
                break
            }
        }

        if (-not $preservedTail) {
            return $true
        }
    }

    if ($original.Length -lt 120) {
        return $false
    }
    if ($candidate.Length -ge [Math]::Max(96, [int]($original.Length * 0.7))) {
        return $false
    }
    if (($candidate.Length / [double]$original.Length) -gt 0.45) {
        return $false
    }

    $index = $original.IndexOf($candidate, [System.StringComparison]::OrdinalIgnoreCase)
    if ($index -lt 0) {
        return $false
    }
    if ($index -eq 0) {
        return $false
    }

    $candidateParse = Get-ScriptParseInfo -ScriptText $candidate
    if (-not $candidateParse.IsValid) {
        return $true
    }

    $originalCmd = Get-WholeScriptCandidateTopLevelCommandName -ScriptText $original
    $candidateCmd = Get-WholeScriptCandidateTopLevelCommandName -ScriptText $candidate
    if (-not [string]::IsNullOrWhiteSpace($candidateCmd)) {
        if (-not [string]::IsNullOrWhiteSpace($originalCmd) -and $candidateCmd -ieq $originalCmd) {
            return $false
        }

        if ($candidateCmd -notmatch '^(?i:invoke-expression|iex|cmd|cmd\.exe|powershell|pwsh|start-process|start|saps)$' -and
            $candidate -notmatch '[`r`n;]') {
            return $true
        }
    }

    $singleExpr = Get-SingleTopLevelExpressionAstFromText -ScriptText $candidate
    if ($singleExpr -and $candidate -notmatch '[`r`n;]') {
        return $true
    }

    if ($candidate -match '^(?i:object\s+with\s+the\s+variables\b)') {
        return $true
    }

    return $false
}

function Get-WholeScriptReplacementCandidateText {
    param(
        [AllowNull()][string]$OriginalText,
        [AllowNull()][string]$CandidateText
    )

    $candidate = Get-SafeNonEmptyString -Value $CandidateText
    if (-not $candidate) {
        return $null
    }

    if (-not (Test-UsefulRecoveredScriptText -Text $candidate)) {
        return $null
    }

    if (-not [string]::IsNullOrWhiteSpace($OriginalText)) {
        $originalNorm = Get-NormalizedScriptComparisonText -ScriptText $OriginalText
        $candidateNorm = Get-NormalizedScriptComparisonText -ScriptText $candidate
        if (-not [string]::IsNullOrWhiteSpace($candidateNorm) -and $candidateNorm -eq $originalNorm) {
            return $null
        }

        if (Test-WholeScriptCandidateLooksTruncatedTail -OriginalText $OriginalText -CandidateText $candidate) {
            return $null
        }
    }

    return $candidate
}

function Get-NextRoundMaterializedPayloadInfo {
    param(
        [object[]]$Selected = @(),
        [Parameter(Mandatory)][string]$PrePostProcessText
    )

    $hasDynamicInvokeSelection = @($Selected | Where-Object { $_ -and $_.PSObject.Properties['SourceKind'] -and [string]$_.SourceKind -eq 'DynamicInvoke' }).Count -gt 0
    $cameFromHostWrapperDecode = $false
    $decodeSource = $null

    $payloadInfo = Resolve-WholeScriptHostPayloadInfo -ScriptText $PrePostProcessText
    if (-not $payloadInfo) {
        $payloadInfo = Try-Resolve-WholeScriptStaticPayloadInfoSafe -ScriptText $PrePostProcessText -WarningContext 'next_round_materialization'
    }
    $resolvedPayloadText = if ($payloadInfo) { Get-WholeScriptReplacementCandidateText -OriginalText $PrePostProcessText -CandidateText $payloadInfo.PayloadText } else { $null }
    if ($resolvedPayloadText) {
        $payloadParse = Get-ScriptParseInfo -ScriptText $resolvedPayloadText
        if ($payloadParse.IsValid) {
            $cameFromHostWrapperDecode = $true
            if ($payloadInfo.PSObject.Properties['DecodeSource'] -and -not [string]::IsNullOrWhiteSpace([string]$payloadInfo.DecodeSource)) {
                $decodeSource = [string]$payloadInfo.DecodeSource
            }
        }
    }

    $isMaterializedPayload = ($hasDynamicInvokeSelection -or $cameFromHostWrapperDecode)
    $reason = $null
    if ($hasDynamicInvokeSelection) {
        $reason = 'dynamic_invoke_selection'
    } elseif ($cameFromHostWrapperDecode) {
        $reason = if (-not [string]::IsNullOrWhiteSpace($decodeSource)) {
            $decodeSource
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
        'DotDot' { return '..' }
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
        'Join' { return '-join' }
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
    if (Test-PipelineAutomaticVariableAst -Ast $Ast) {
        return [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = $false; Reason = 'pipeline_automatic_variable'; Message = ('静态求值不绑定 pipeline 自动变量: $' + $name) }
    }

    $pathContext = $null
    switch ($name.ToLowerInvariant()) {
        'true'  { return [PSCustomObject]@{ Success = $true; Value = $true; UsedEmptyFallback = $false; Reason = $null; Message = $null } }
        'false' { return [PSCustomObject]@{ Success = $true; Value = $false; UsedEmptyFallback = $false; Reason = $null; Message = $null } }
        'null'  { return [PSCustomObject]@{ Success = $true; Value = $null; UsedEmptyFallback = $false; Reason = $null; Message = $null } }
        'testdrive' {
            $testDriveRoot = Get-WholeScriptStaticDeterministicTestDrivePath -Context $Context
            if (-not [string]::IsNullOrWhiteSpace([string]$testDriveRoot)) {
                return [PSCustomObject]@{
                    Success           = $true
                    Value             = [string]$testDriveRoot
                    UsedEmptyFallback = $false
                    Reason            = $null
                    Message           = $null
                }
            }
        }
        'pwd' {
            $pathContext = Get-WholeScriptStaticPathContext -Context $Context
            if ($pathContext -and -not [string]::IsNullOrWhiteSpace([string]$pathContext.CurrentDirectory)) {
                return [PSCustomObject]@{
                    Success           = $true
                    Value             = (New-StaticPathInfoValue -Path ([string]$pathContext.CurrentDirectory))
                    UsedEmptyFallback = $false
                    Reason            = $null
                    Message           = $null
                }
            }
        }
        'psscriptroot' {
            $pathContext = Get-WholeScriptStaticPathContext -Context $Context
            if ($pathContext -and -not [string]::IsNullOrWhiteSpace([string]$pathContext.ScriptDirectory)) {
                return [PSCustomObject]@{
                    Success           = $true
                    Value             = [string]$pathContext.ScriptDirectory
                    UsedEmptyFallback = $false
                    Reason            = $null
                    Message           = $null
                }
            }
        }
        'pscommandpath' {
            $pathContext = Get-WholeScriptStaticPathContext -Context $Context
            if ($pathContext -and -not [string]::IsNullOrWhiteSpace([string]$pathContext.ScriptPath)) {
                return [PSCustomObject]@{
                    Success           = $true
                    Value             = [string]$pathContext.ScriptPath
                    UsedEmptyFallback = $false
                    Reason            = $null
                    Message           = $null
                }
            }
        }
    }

    if ($name -match '^(?i:env:)(.+)$') {
        $envName = [string]$Matches[1]
        $envValue = Resolve-WholeScriptStaticEnvironmentValueText -Name $envName -Context $Context
        if ($null -ne $envValue) {
            return [PSCustomObject]@{
                Success           = $true
                Value             = [string]$envValue
                UsedEmptyFallback = $false
                Reason            = $null
                Message           = $null
            }
        }
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
        if ($value -is [System.Management.Automation.PathInfo]) {
            $value = New-StaticPathInfoValue -Path ([string]$value.Path)
        }
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

function Get-RecoveredTextCandidateScore {
    param([AllowNull()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return -1 }

    $score = 0
    $trimmed = $Text.Trim()
    $printableCount = 0
    foreach ($ch in $trimmed.ToCharArray()) {
        $code = [int][char]$ch
        if ($code -eq 9 -or $code -eq 10 -or $code -eq 13 -or ($code -ge 32 -and $code -le 126)) {
            $printableCount++
        }
    }
    if ($trimmed.Length -gt 0) {
        $score += [int](100 * ($printableCount / [double]$trimmed.Length))
    }

    if ($trimmed -match '^(?i)(?:https?|ftp)://') { $score += 220 }
    elseif ($trimmed -match '^(?:(?:\d{1,3}\.){3}\d{1,3})(?::\d+)?(?:/.*)?$') { $score += 210 }
    elseif ($trimmed -match '^(?i:[A-Za-z0-9.-]+\.[A-Za-z]{2,})(?:[:/].*)?$') { $score += 180 }

    if ($trimmed -match '(?i)\b(?:Invoke-Expression|iex|Start-Process|mshta(?:\.exe)?|powershell(?:\.exe)?|pwsh(?:\.exe)?|WebRequest|DownloadString|Navigate2?)\b') {
        $score += 160
    }
    if ($trimmed -match '(?i)(?:\.hta\b|-enc(?:odedcommand)?\b|-command\b|\?i=)') {
        $score += 120
    }

    $psScore = 0
    if (Get-Command Test-PowerShellTextCandidate -ErrorAction SilentlyContinue) {
        try {
            $test = Test-PowerShellTextCandidate -Text $trimmed
            if ($test -and $test.PSObject.Properties['Score']) {
                $psScore = [int]$test.Score
            }
        } catch {
            $psScore = 0
        }
    }
    $score += $psScore

    if ($trimmed.Contains([char]0)) { $score -= 200 }
    return $score
}

function Convert-ByteArrayToLikelyPlainText {
    param([byte[]]$Bytes)

    if ($null -eq $Bytes -or $Bytes.Length -eq 0) {
        return $null
    }

    $candidates = @(
        @{ Name = 'UTF8'; Encoding = [System.Text.Encoding]::UTF8 },
        @{ Name = 'Unicode'; Encoding = [System.Text.Encoding]::Unicode },
        @{ Name = 'BigEndianUnicode'; Encoding = [System.Text.Encoding]::BigEndianUnicode },
        @{ Name = 'ASCII'; Encoding = [System.Text.Encoding]::ASCII }
    )

    $bestText = $null
    $bestScore = -1
    foreach ($candidate in $candidates) {
        try {
            $text = $candidate.Encoding.GetString($Bytes)
        } catch {
            continue
        }

        $score = Get-RecoveredTextCandidateScore -Text $text
        if ($score -gt $bestScore) {
            $bestScore = $score
            $bestText = $text
        }
    }

    if ($bestScore -lt 0) {
        return $null
    }

    return $bestText
}

function Convert-StaticValueToMeaningfulString {
    param($Value)

    if ($Value -is [psobject] -and $null -ne $Value.BaseObject -and $Value.BaseObject -ne $Value) {
        $Value = $Value.BaseObject
    }

    if ($null -eq $Value) { return $null }
    if ($Value -is [string]) { return [string]$Value }
    if ($Value -is [char]) { return [string]$Value }
    if ($Value -is [char[]]) { return (-join $Value) }

    $charArray = Convert-StaticValueToCharArray -Value $Value
    $charText = if ($null -ne $charArray -and $charArray.Count -gt 0) { (-join $charArray) } else { $null }

    $byteArray = Try-ConvertToByteArrayFromStaticValue -Value $Value
    $byteText = if ($null -ne $byteArray) { Convert-ByteArrayToLikelyPlainText -Bytes $byteArray } else { $null }

    $charScore = Get-RecoveredTextCandidateScore -Text $charText
    $byteScore = Get-RecoveredTextCandidateScore -Text $byteText

    if ($byteScore -gt $charScore) {
        return $byteText
    }
    if ($charScore -ge 0) {
        return $charText
    }

    return $null
}

function Resolve-StaticAstTextInfo {
    param(
        $Ast,
        [hashtable]$Context,
        [bool]$AllowEmptyFallback = $false
    )

    if ($null -eq $Ast) { return $null }

    $resolved = Resolve-StaticAstValue -Ast $Ast -Context $Context -AllowEmptyFallback:$AllowEmptyFallback
    if (-not $resolved.Success) { return $null }

    $text = Convert-StaticValueToMeaningfulString -Value $resolved.Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }

    return [PSCustomObject]@{
        Text              = [string]$text
        Value             = $resolved.Value
        UsedEmptyFallback = [bool]$resolved.UsedEmptyFallback
    }
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
                if ($n -isnot [System.Management.Automation.Language.InvokeMemberExpressionAst]) {
                    return $false
                }

                $memberName = $null
                if ($n.Member -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                    $memberName = [string]$n.Member.Value
                } elseif ($n.Member) {
                    $memberName = [string]$n.Member.Extent.Text
                }

                return ($memberName -match '^(?i:FromBase64String)$')
            }, $true) | Select-Object -First 1)
    if ($base64Call.Count -gt 0) {
        $base64Invoke = $base64Call[0]
        if ($base64Invoke.Arguments -and $base64Invoke.Arguments.Count -gt 0) {
            $base64String = Try-GetStaticStringValue -Ast $base64Invoke.Arguments[0] -Context $Context
            if (-not [string]::IsNullOrWhiteSpace($base64String)) {
                $bytes = Try-DecodeBase64ToByteArray -Base64String $base64String

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

    $info = Resolve-StaticAstTextInfo -Ast $Ast -Context $Context -AllowEmptyFallback:$false
    if ($null -eq $info) { return $null }
    return [string]$info.Text
}

function Try-GetStaticStringValueBestEffort {
    param(
        $Ast,
        [hashtable]$Context,
        [bool]$AllowEmptyFallback = $true
    )

    $info = Resolve-StaticAstTextInfo -Ast $Ast -Context $Context -AllowEmptyFallback:$AllowEmptyFallback
    if ($null -eq $info) { return $null }
    return $info
}

function Convert-StaticValueToPipelineOutputItems {
    param($Value)

    if ($null -eq $Value) {
        return @()
    }

    if ($Value -is [psobject] -and $null -ne $Value.BaseObject -and $Value.BaseObject -ne $Value) {
        $Value = $Value.BaseObject
    }

    if (($Value -is [System.Collections.IEnumerable]) -and -not ($Value -is [string])) {
        return @($Value)
    }

    return @($Value)
}

function Convert-StaticPipelineOutputItemsToValue {
    param([object[]]$Items = @())

    $normalized = @($Items)
    if ($normalized.Count -eq 0) {
        return @()
    }
    if ($normalized.Count -eq 1) {
        return $normalized[0]
    }
    return @($normalized)
}

function Get-StaticCommandArgumentBinding {
    param([System.Management.Automation.Language.CommandAst]$CommandAst)

    $parameterMap = @{}
    $positionals = New-Object 'System.Collections.Generic.List[object]'
    $elements = if ($CommandAst) { @($CommandAst.CommandElements) } else { @() }

    for ($i = 1; $i -lt $elements.Count; $i++) {
        $elem = $elements[$i]
        if ($elem -is [System.Management.Automation.Language.CommandParameterAst]) {
            $paramName = [string]$elem.ParameterName
            if ([string]::IsNullOrWhiteSpace($paramName)) {
                continue
            }

            $argAst = $null
            if ($elem.Argument) {
                $argAst = $elem.Argument
            } elseif ($i + 1 -lt $elements.Count -and $elements[$i + 1] -isnot [System.Management.Automation.Language.CommandParameterAst]) {
                $argAst = $elements[++$i]
            }

            $parameterMap[$paramName.ToLowerInvariant()] = $argAst
            continue
        }

        $null = $positionals.Add($elem)
    }

    return [PSCustomObject]@{
        Parameters = $parameterMap
        Positional = @($positionals.ToArray())
    }
}

function Get-StaticForEachProjectionInfo {
    param([System.Management.Automation.Language.ScriptBlockAst]$ScriptBlockAst)

    if ($null -eq $ScriptBlockAst -or $ScriptBlockAst.ParamBlock) {
        return $null
    }

    $activeBlocks = @()
    foreach ($block in @($ScriptBlockAst.BeginBlock, $ScriptBlockAst.ProcessBlock, $ScriptBlockAst.EndBlock)) {
        if ($block -and @($block.Statements).Count -gt 0) {
            $activeBlocks += ,$block
        }
    }

    if ($activeBlocks.Count -ne 1) {
        return $null
    }

    $statements = @($activeBlocks[0].Statements)
    if ($statements.Count -ne 1) {
        return $null
    }

    $expr = Get-StaticExpressionFromPipelineAst -PipelineAst $statements[0]
    if ($null -eq $expr) {
        return $null
    }

    if ($expr -is [System.Management.Automation.Language.VariableExpressionAst]) {
        $name = [string]$expr.VariablePath.UserPath
        if ($name -match '^(?i:_|psitem)$') {
            return [PSCustomObject]@{
                Type       = 'Identity'
                MemberName = $null
            }
        }
    }

    if ($expr -is [System.Management.Automation.Language.MemberExpressionAst] -and -not $expr.Static) {
        if ($expr.Expression -is [System.Management.Automation.Language.VariableExpressionAst]) {
            $varName = [string]$expr.Expression.VariablePath.UserPath
            if ($varName -match '^(?i:_|psitem)$') {
                $memberName = Get-StaticMemberNameText -MemberAst $expr.Member -Context $null
                if (-not [string]::IsNullOrWhiteSpace($memberName)) {
                    return [PSCustomObject]@{
                        Type       = 'Property'
                        MemberName = $memberName
                    }
                }
            }
        }
    }

    return $null
}

function Register-WholeScriptStaticPureHelperFunction {
    param(
        [Parameter(Mandatory)][System.Management.Automation.Language.FunctionDefinitionAst]$FunctionAst,
        [Parameter(Mandatory)][hashtable]$Context,
        [int]$TimeoutMs = 2000
    )

    if (-not $Context.ExecContext) {
        return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = $false; Message = '缺少执行上下文' }
    }
    if (-not (Test-WholeScriptPureLocalHelperFunctionAllowed -FunctionAst $FunctionAst)) {
        return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = $false; Message = '函数未通过纯 helper 安全检查' }
    }
    if ($null -eq $FunctionAst.Extent -or [string]::IsNullOrWhiteSpace([string]$FunctionAst.Extent.Text)) {
        return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = $false; Message = '函数定义文本为空' }
    }

    $helperMap = Get-WholeScriptStaticPureHelperFunctionMap -Context $Context
    $name = [string]$FunctionAst.Name
    if ($helperMap.ContainsKey($name)) {
        return [PSCustomObject]@{ Success = $true; OutputItems = @(); UsedEmptyFallback = $false; Message = $null }
    }

    $runResult = Invoke-InContext -ExecContext $Context.ExecContext -Code ([string]$FunctionAst.Extent.Text) -TimeoutMs $TimeoutMs -PersistOnSuccess:$true
    if (-not $runResult.Success) {
        $message = if ($runResult.PSObject.Properties['Message'] -and -not [string]::IsNullOrWhiteSpace([string]$runResult.Message)) {
            [string]$runResult.Message
        } else {
            '纯 helper 函数注册失败'
        }
        return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = $false; Message = $message }
    }

    $helperMap[$name] = $true
    return [PSCustomObject]@{ Success = $true; OutputItems = @(); UsedEmptyFallback = $false; Message = $null }
}

function Test-WholeScriptStaticPureHelperCommandInvocationAllowed {
    param(
        [Parameter(Mandatory)][System.Management.Automation.Language.CommandAst]$CommandAst,
        [Parameter(Mandatory)][hashtable]$Context
    )

    if ($null -eq $CommandAst.Extent -or [string]::IsNullOrWhiteSpace([string]$CommandAst.Extent.Text)) {
        return $false
    }
    if ($CommandAst.Redirections -and @($CommandAst.Redirections).Count -gt 0) {
        return $false
    }

    $cmdName = Convert-DynamicCommandCandidateToName -Value $CommandAst.GetCommandName()
    if ([string]::IsNullOrWhiteSpace($cmdName)) {
        return $false
    }

    $helperMap = Get-WholeScriptStaticPureHelperFunctionMap -Context $Context
    if ($null -eq $helperMap -or -not $helperMap.ContainsKey($cmdName)) {
        return $false
    }

    return (([string]$CommandAst.Extent.Text).Length -le 512)
}

function Invoke-WholeScriptStaticPureHelperCommand {
    param(
        [Parameter(Mandatory)][System.Management.Automation.Language.CommandAst]$CommandAst,
        [Parameter(Mandatory)][hashtable]$Context,
        [int]$TimeoutMs = 2000
    )

    if (-not (Test-WholeScriptStaticPureHelperCommandInvocationAllowed -CommandAst $CommandAst -Context $Context)) {
        return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = $false; Message = '命令不是已注册的纯 helper 调用' }
    }
    if (-not $Context.ExecContext) {
        return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = $false; Message = '缺少执行上下文' }
    }

    $commandText = [string]$CommandAst.Extent.Text
    $evalCode = @"
`$__psdissect_payload = @(& {
$commandText
})
[pscustomobject]@{ Payload = `$__psdissect_payload }
"@

    $evalResult = Invoke-InContext -ExecContext $Context.ExecContext -Code $evalCode -TimeoutMs $TimeoutMs -PersistOnSuccess:$false
    if (-not $evalResult.Success -or -not $evalResult.Result -or @($evalResult.Result).Count -eq 0) {
        $message = if ($evalResult.PSObject.Properties['Message'] -and -not [string]::IsNullOrWhiteSpace([string]$evalResult.Message)) {
            [string]$evalResult.Message
        } else {
            '纯 helper 调用求值失败'
        }
        return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = $false; Message = $message }
    }

    $payloadContainer = @($evalResult.Result)[-1]
    $payloadItems = @()
    if ($payloadContainer -and $payloadContainer.PSObject.Properties['Payload']) {
        $payloadItems = @($payloadContainer.Payload)
    } else {
        $payloadItems = @($evalResult.Result)
    }

    return [PSCustomObject]@{
        Success           = $true
        OutputItems       = @($payloadItems)
        UsedEmptyFallback = $false
        Message           = $null
    }
}

function Invoke-WholeScriptStaticCommand {
    param(
        [Parameter(Mandatory)][System.Management.Automation.Language.CommandAst]$CommandAst,
        [Parameter(Mandatory)][hashtable]$Context,
        [int]$Depth = 0
    )

    if (-not $Context.ExecContext) {
        return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = $false; Message = '缺少执行上下文' }
    }

    $cmdName = Convert-DynamicCommandCandidateToName -Value $CommandAst.GetCommandName()
    if ([string]::IsNullOrWhiteSpace($cmdName)) {
        return Invoke-WholeScriptStaticSideEffectCommand -CommandAst $CommandAst -Context $Context -Depth ($Depth + 1)
    }

    $binding = Get-StaticCommandArgumentBinding -CommandAst $CommandAst

    if (Test-WholeScriptStaticPureHelperCommandInvocationAllowed -CommandAst $CommandAst -Context $Context) {
        $helperCommandResult = Invoke-WholeScriptStaticPureHelperCommand -CommandAst $CommandAst -Context $Context -TimeoutMs 2000
        if ($helperCommandResult.Success) {
            return $helperCommandResult
        }
    }

    if ($cmdName -match '^(?i:new-object)$') {
        $typeName = $null
        if ($binding.Parameters.ContainsKey('typename') -and $binding.Parameters['typename']) {
            $typeName = Try-GetStaticStringValue -Ast $binding.Parameters['typename'] -Context $Context
        }
        if ([string]::IsNullOrWhiteSpace($typeName) -and $binding.Positional.Count -gt 0) {
            $typeName = Try-GetStaticStringValue -Ast $binding.Positional[0] -Context $Context
        }

        $comObjectName = $null
        foreach ($key in @('comobject', 'com')) {
            if ($binding.Parameters.ContainsKey($key) -and $binding.Parameters[$key]) {
                $comObjectName = Try-GetStaticStringValue -Ast $binding.Parameters[$key] -Context $Context
                if (-not [string]::IsNullOrWhiteSpace($comObjectName)) {
                    break
                }
            }
        }
        if ([string]::IsNullOrWhiteSpace($typeName) -and -not [string]::IsNullOrWhiteSpace($comObjectName)) {
            $typeName = $comObjectName
        }

        $initialProperties = $null
        if ($binding.Parameters.ContainsKey('property') -and $binding.Parameters['property']) {
            $propertyResult = Resolve-StaticAstValue -Ast $binding.Parameters['property'] -Context $Context -AllowEmptyFallback:$false -Depth ($Depth + 1)
            if (-not $propertyResult.Success) {
                return [PSCustomObject]@{
                    Success           = $false
                    OutputItems       = @()
                    UsedEmptyFallback = [bool]$propertyResult.UsedEmptyFallback
                    Message           = $propertyResult.Message
                }
            }
            if ($propertyResult.Value -is [System.Collections.IDictionary]) {
                $initialProperties = Convert-StaticDictionaryToOrderedMap -Dictionary $propertyResult.Value
            }
        }

        $modeledValue = New-StaticModeledObjectValue -TypeName $typeName -InitialProperties $initialProperties
        if ($null -ne $modeledValue) {
            return [PSCustomObject]@{
                Success           = $true
                OutputItems       = @($modeledValue)
                UsedEmptyFallback = $false
                Message           = $null
            }
        }
    }

    if ($CommandAst.InvocationOperator -eq 'Ampersand' -and $CommandAst.CommandElements.Count -gt 0) {
        $targetAst = $CommandAst.CommandElements[0]
        if ($targetAst -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
            $targetAst.Static -and
            $targetAst.Expression -is [System.Management.Automation.Language.TypeExpressionAst]) {
            $targetType = Resolve-StaticTypeFromTypeExpressionAst -TypeExpressionAst $targetAst.Expression
            $memberName = Get-StaticMemberNameText -MemberAst $targetAst.Member -Context $Context
            if ($targetType -and $targetType.FullName -eq 'System.IO.File' -and -not [string]::IsNullOrWhiteSpace($memberName)) {
                $argResult = Convert-StaticMethodArguments -Arguments $targetAst.Arguments -Context $Context -Depth ($Depth + 1)
                if ($argResult.Success) {
                    $fileInvoke = Invoke-WholeScriptStaticFileTypeMethod -MemberName $memberName -Arguments $argResult.Values -Context $Context
                    if ($fileInvoke.Success) {
                        return [PSCustomObject]@{
                            Success           = $true
                            OutputItems       = @()
                            UsedEmptyFallback = [bool]$argResult.UsedEmptyFallback
                            Message           = $null
                        }
                    }
                }
            }
        }
    }

    switch -Regex ($cmdName) {
        '^(?i:get-location|gl|pwd)$' {
            $pathContext = Get-WholeScriptStaticPathContext -Context $Context
            $currentDirectory = if ($pathContext) { [string]$pathContext.CurrentDirectory } else { $null }
            if ([string]::IsNullOrWhiteSpace($currentDirectory)) {
                return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = $false; Message = 'Get-Location 当前目录不可用' }
            }

            return [PSCustomObject]@{
                Success           = $true
                OutputItems       = @((New-StaticPathInfoValue -Path $currentDirectory))
                UsedEmptyFallback = $false
                Message           = $null
            }
        }
        '^(?i:join-path)$' {
            $pathAst = $null
            foreach ($key in @('path')) {
                if ($binding.Parameters.ContainsKey($key) -and $binding.Parameters[$key]) {
                    $pathAst = $binding.Parameters[$key]
                    break
                }
            }
            if ($null -eq $pathAst -and $binding.Positional.Count -gt 0) {
                $pathAst = $binding.Positional[0]
            }

            $childAst = $null
            foreach ($key in @('childpath')) {
                if ($binding.Parameters.ContainsKey($key) -and $binding.Parameters[$key]) {
                    $childAst = $binding.Parameters[$key]
                    break
                }
            }
            if ($null -eq $childAst -and $binding.Positional.Count -gt 1) {
                $childAst = $binding.Positional[1]
            }

            $basePath = Resolve-WholeScriptStaticArtifactPathTextFromAst -Ast $pathAst -Context $Context
            $childPath = Resolve-WholeScriptStaticCommandValueTextFromAst -Ast $childAst -Context $Context -Delimiter '\'
            if ([string]::IsNullOrWhiteSpace($basePath) -or [string]::IsNullOrWhiteSpace($childPath)) {
                return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = $false; Message = 'Join-Path 参数无法静态解析' }
            }

            $combinedPath = $null
            try {
                $segments = @($childPath -split '[\\/]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                if ($segments.Count -gt 0) {
                    $combinedPath = [string]$basePath
                    foreach ($segment in @($segments)) {
                        $combinedPath = [System.IO.Path]::Combine([string]$combinedPath, [string]$segment)
                    }
                } else {
                    $combinedPath = $basePath
                }
            } catch {
                $combinedPath = ($basePath.TrimEnd('\') + '\' + $childPath.TrimStart('\'))
            }

            $combinedPath = Resolve-WholeScriptStaticDisplayPath -PathText $combinedPath -Context $Context
            if ([string]::IsNullOrWhiteSpace($combinedPath)) {
                return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = $false; Message = 'Join-Path 结果无法静态规范化' }
            }

            return [PSCustomObject]@{
                Success           = $true
                OutputItems       = @($combinedPath)
                UsedEmptyFallback = $false
                Message           = $null
            }
        }
        '^(?i:get-random|random)$' {
            $inputAst = $null
            foreach ($key in @('inputobject')) {
                if ($binding.Parameters.ContainsKey($key) -and $binding.Parameters[$key]) {
                    $inputAst = $binding.Parameters[$key]
                    break
                }
            }
            if ($null -eq $inputAst -and $binding.Positional.Count -gt 0) {
                $firstPositional = $binding.Positional[0]
                if ($firstPositional -isnot [System.Management.Automation.Language.CommandParameterAst]) {
                    $inputAst = $firstPositional
                }
            }

            if ($null -ne $inputAst) {
                $inputResult = Resolve-StaticAstValue -Ast $inputAst -Context $Context -AllowEmptyFallback:$false -Depth ($Depth + 1)
                if (-not $inputResult.Success) {
                    return [PSCustomObject]@{
                        Success           = $false
                        OutputItems       = @()
                        UsedEmptyFallback = [bool]$inputResult.UsedEmptyFallback
                        Message           = $inputResult.Message
                    }
                }

                $items = @(Convert-StaticValueToPipelineOutputItems -Value $inputResult.Value)
                if ($items.Count -eq 0) {
                    return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = [bool]$inputResult.UsedEmptyFallback; Message = 'Get-Random 输入集合为空' }
                }

                return [PSCustomObject]@{
                    Success           = $true
                    OutputItems       = @($items[0])
                    UsedEmptyFallback = [bool]$inputResult.UsedEmptyFallback
                    Message           = $null
                }
            }

            $minAst = $null
            foreach ($key in @('minimum', 'min')) {
                if ($binding.Parameters.ContainsKey($key) -and $binding.Parameters[$key]) {
                    $minAst = $binding.Parameters[$key]
                    break
                }
            }

            $maxAst = $null
            foreach ($key in @('maximum', 'max')) {
                if ($binding.Parameters.ContainsKey($key) -and $binding.Parameters[$key]) {
                    $maxAst = $binding.Parameters[$key]
                    break
                }
            }

            $minValue = [long]0
            $usedFallback = $false
            if ($null -ne $minAst) {
                $minResult = Resolve-StaticAstValue -Ast $minAst -Context $Context -AllowEmptyFallback:$false -Depth ($Depth + 1)
                if (-not $minResult.Success) {
                    return [PSCustomObject]@{
                        Success           = $false
                        OutputItems       = @()
                        UsedEmptyFallback = [bool]$minResult.UsedEmptyFallback
                        Message           = $minResult.Message
                    }
                }
                try {
                    $minValue = [long]$minResult.Value
                    $usedFallback = ($usedFallback -or [bool]$minResult.UsedEmptyFallback)
                } catch {
                    return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = [bool]$minResult.UsedEmptyFallback; Message = 'Get-Random 最小值无法转换为整数' }
                }
            }

            if ($null -ne $maxAst) {
                $maxResult = Resolve-StaticAstValue -Ast $maxAst -Context $Context -AllowEmptyFallback:$false -Depth ($Depth + 1)
                if (-not $maxResult.Success) {
                    return [PSCustomObject]@{
                        Success           = $false
                        OutputItems       = @()
                        UsedEmptyFallback = ($usedFallback -or [bool]$maxResult.UsedEmptyFallback)
                        Message           = $maxResult.Message
                    }
                }

                $maxValue = $null
                try {
                    $maxValue = [long]$maxResult.Value
                    $usedFallback = ($usedFallback -or [bool]$maxResult.UsedEmptyFallback)
                } catch {
                    return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = ($usedFallback -or [bool]$maxResult.UsedEmptyFallback); Message = 'Get-Random 最大值无法转换为整数' }
                }

                if ($maxValue -le $minValue) {
                    return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = $usedFallback; Message = 'Get-Random 最大值必须大于最小值' }
                }

                $value = $minValue
                if (($maxValue - $minValue) -gt 1) {
                    $value = $minValue + [long][Math]::Floor((($maxValue - $minValue) - 1) / 2)
                }

                return [PSCustomObject]@{
                    Success           = $true
                    OutputItems       = @($value)
                    UsedEmptyFallback = $usedFallback
                    Message           = $null
                }
            }

            return [PSCustomObject]@{
                Success           = $true
                OutputItems       = @($minValue)
                UsedEmptyFallback = $usedFallback
                Message           = $null
            }
        }
        '^(?i:get-variable|gv|variable)$' {
            $nameAst = $null
            foreach ($key in @('name', 'n')) {
                if ($binding.Parameters.ContainsKey($key) -and $binding.Parameters[$key]) {
                    $nameAst = $binding.Parameters[$key]
                    break
                }
            }
            if ($null -eq $nameAst -and $binding.Positional.Count -gt 0) {
                $nameAst = $binding.Positional[0]
            }

            $varName = Try-GetStaticStringValue -Ast $nameAst -Context $Context
            if ([string]::IsNullOrWhiteSpace($varName) -or $varName.Contains('*') -or $varName.Contains('?')) {
                return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = $false; Message = 'Get-Variable 模式不在静态支持范围内' }
            }

            try {
                $psVar = $Context.ExecContext.Runspace.SessionStateProxy.PSVariable.Get([string]$varName)
                if ($null -eq $psVar) {
                    return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = $false; Message = '变量不存在' }
                }
                return [PSCustomObject]@{
                    Success           = $true
                    OutputItems       = @($psVar)
                    UsedEmptyFallback = $false
                    Message           = $null
                }
            } catch {
                return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = $false; Message = $_.Exception.Message }
            }
        }
        '^(?i:get-item|gi|item)$' {
            $pathAst = $null
            foreach ($key in @('literalpath', 'path', 'lp')) {
                if ($binding.Parameters.ContainsKey($key) -and $binding.Parameters[$key]) {
                    $pathAst = $binding.Parameters[$key]
                    break
                }
            }
            if ($null -eq $pathAst -and $binding.Positional.Count -gt 0) {
                $pathAst = $binding.Positional[0]
            }

            $pathText = Try-GetStaticStringValue -Ast $pathAst -Context $Context
            if ([string]::IsNullOrWhiteSpace($pathText)) {
                return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = $false; Message = 'Get-Item 路径无法静态解析' }
            }

            if ($pathText -match '^(?i:variable:)(.+)$') {
                $varName = $Matches[1]
                try {
                    $psVar = $Context.ExecContext.Runspace.SessionStateProxy.PSVariable.Get([string]$varName)
                    if ($null -eq $psVar) {
                        return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = $false; Message = '变量不存在' }
                    }
                    return [PSCustomObject]@{
                        Success           = $true
                        OutputItems       = @($psVar)
                        UsedEmptyFallback = $false
                        Message           = $null
                    }
                } catch {
                    return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = $false; Message = $_.Exception.Message }
                }
            }

            if ($pathText -match '^(?i:env:)(.+)$') {
                $envName = [string]$Matches[1]
                $envValue = Resolve-WholeScriptStaticEnvironmentValueText -Name $envName -Context $Context
                if ([string]::IsNullOrWhiteSpace([string]$envValue)) {
                    return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = $false; Message = '环境变量不存在' }
                }

                return [PSCustomObject]@{
                    Success           = $true
                    OutputItems       = @([PSCustomObject]@{
                            __PsDissectType = 'PSObject'
                            Name            = $envName
                            Value           = [string]$envValue
                        })
                    UsedEmptyFallback = $false
                    Message           = $null
                }
            }

            return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = $false; Message = 'Get-Item 路径不在静态支持范围内' }
        }
        '^(?i:get-content|gc|type|cat)$' {
            $pathAst = $null
            foreach ($key in @('literalpath', 'path', 'lp')) {
                if ($binding.Parameters.ContainsKey($key) -and $binding.Parameters[$key]) {
                    $pathAst = $binding.Parameters[$key]
                    break
                }
            }
            if ($null -eq $pathAst -and $binding.Positional.Count -gt 0) {
                $pathAst = $binding.Positional[0]
            }

            $pathText = Resolve-WholeScriptStaticArtifactPathTextFromAst -Ast $pathAst -Context $Context
            if ([string]::IsNullOrWhiteSpace($pathText)) {
                return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = $false; Message = 'Get-Content 路径无法静态解析' }
            }

            $raw = $binding.Parameters.ContainsKey('raw')
            $items = Get-WholeScriptStaticFileArtifactOutputItems -Context $Context -PathText $pathText -Raw:$raw
            if ($null -eq $items) {
                return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = $false; Message = 'Get-Content 目标不在静态 artifact 范围内' }
            }

            Add-WholeScriptStaticArtifactEvent -Context $Context -Action 'read' -Path $pathText -Kind 'File' -Detail ('Get-Content' + $(if ($raw) { ' -Raw' } else { '' }))
            return [PSCustomObject]@{
                Success           = $true
                OutputItems       = @($items)
                UsedEmptyFallback = $false
                Message           = $null
            }
        }
    }

    return Invoke-WholeScriptStaticSideEffectCommand -CommandAst $CommandAst -Context $Context -Depth ($Depth + 1)
}

function Resolve-StaticPipelineAstValue {
    param(
        $PipelineAst,
        [hashtable]$Context,
        [bool]$AllowEmptyFallback = $false,
        [int]$Depth = 0
    )

    if ($null -eq $PipelineAst) {
        return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = $false; Message = 'Pipeline AST 为空' }
    }

    $expr = Get-StaticExpressionFromPipelineAst -PipelineAst $PipelineAst
    if ($null -ne $expr) {
        $exprResult = Resolve-StaticAstValue -Ast $expr -Context $Context -AllowEmptyFallback:$AllowEmptyFallback -Depth ($Depth + 1)
        if (-not $exprResult.Success) {
            return [PSCustomObject]@{
                Success          = $false
                OutputItems      = @()
                UsedEmptyFallback = [bool]$exprResult.UsedEmptyFallback
                Message          = $exprResult.Message
            }
        }

        return [PSCustomObject]@{
            Success           = $true
            OutputItems       = @(Convert-StaticValueToPipelineOutputItems -Value $exprResult.Value)
            UsedEmptyFallback = [bool]$exprResult.UsedEmptyFallback
            Message           = $null
        }
    }

    if ($PipelineAst -isnot [System.Management.Automation.Language.PipelineAst]) {
        return [PSCustomObject]@{
            Success           = $false
            OutputItems       = @()
            UsedEmptyFallback = $false
            Message           = ('暂不支持的静态 pipeline AST 类型: ' + $PipelineAst.GetType().FullName)
        }
    }

    $elements = @($PipelineAst.PipelineElements)
    if ($elements.Count -eq 1 -and $elements[0] -is [System.Management.Automation.Language.CommandAst]) {
        return Invoke-WholeScriptStaticCommand -CommandAst $elements[0] -Context $Context -Depth ($Depth + 1)
    }

    if ($elements.Count -eq 2 -and $elements[1] -is [System.Management.Automation.Language.CommandAst]) {
        $sourceExpr = $null
        if ($elements[0] -is [System.Management.Automation.Language.CommandExpressionAst]) {
            $sourceExpr = $elements[0].Expression
        } elseif ($elements[0].PSObject.Properties['Expression']) {
            $sourceExpr = $elements[0].Expression
        }

        if ($null -eq $sourceExpr) {
            return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = $false; Message = '暂不支持的静态 pipeline 源表达式' }
        }

        $sourceResult = Resolve-StaticAstValue -Ast $sourceExpr -Context $Context -AllowEmptyFallback:$AllowEmptyFallback -Depth ($Depth + 1)
        if (-not $sourceResult.Success) {
            return [PSCustomObject]@{
                Success           = $false
                OutputItems       = @()
                UsedEmptyFallback = [bool]$sourceResult.UsedEmptyFallback
                Message           = $sourceResult.Message
            }
        }

        $sinkCommand = $elements[1]
        $sinkName = Convert-DynamicCommandCandidateToName -Value $sinkCommand.GetCommandName()
        if ($sinkName -notin @('ForEach-Object', '%', 'foreach')) {
            return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = [bool]$sourceResult.UsedEmptyFallback; Message = '暂不支持的静态 pipeline 接收端' }
        }

        $binding = Get-StaticCommandArgumentBinding -CommandAst $sinkCommand
        $scriptBlockArg = $null
        foreach ($key in @('process', 'remainingscripts', 'scriptblock')) {
            if ($binding.Parameters.ContainsKey($key) -and $binding.Parameters[$key]) {
                $scriptBlockArg = $binding.Parameters[$key]
                break
            }
        }
        if ($null -eq $scriptBlockArg -and $binding.Positional.Count -gt 0) {
            $scriptBlockArg = $binding.Positional[0]
        }

        $scriptBlockAst = $null
        if ($scriptBlockArg -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
            $scriptBlockAst = $scriptBlockArg.ScriptBlock
        } elseif ($scriptBlockArg -is [System.Management.Automation.Language.ScriptBlockAst]) {
            $scriptBlockAst = $scriptBlockArg
        }
        if ($null -eq $scriptBlockAst) {
            return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = [bool]$sourceResult.UsedEmptyFallback; Message = 'ForEach-Object 缺少可静态分析的脚本块' }
        }

        $projection = Get-StaticForEachProjectionInfo -ScriptBlockAst $scriptBlockAst
        if ($null -eq $projection) {
            return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = [bool]$sourceResult.UsedEmptyFallback; Message = 'ForEach-Object 脚本块超出静态支持范围' }
        }

        $sourceItems = @(Convert-StaticValueToPipelineOutputItems -Value $sourceResult.Value)
        if ($projection.Type -eq 'Identity') {
            return [PSCustomObject]@{
                Success           = $true
                OutputItems       = @($sourceItems)
                UsedEmptyFallback = [bool]$sourceResult.UsedEmptyFallback
                Message           = $null
            }
        }

        if ($projection.Type -eq 'Property') {
            $projected = @()
            foreach ($item in $sourceItems) {
                $memberResult = Resolve-StaticMemberAccessValue -TargetValue $item -MemberName $projection.MemberName
                if (-not $memberResult.Success) {
                    return [PSCustomObject]@{
                        Success           = $false
                        OutputItems       = @()
                        UsedEmptyFallback = [bool]$sourceResult.UsedEmptyFallback
                        Message           = $memberResult.Message
                    }
                }
                $projected += ,$memberResult.Value
            }

            return [PSCustomObject]@{
                Success           = $true
                OutputItems       = @($projected)
                UsedEmptyFallback = [bool]$sourceResult.UsedEmptyFallback
                Message           = $null
            }
        }
    }

    return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = $false; Message = '暂不支持的静态 pipeline 结构' }
}

function Try-DecodeCompressedScriptTextFromByteArray {
    param(
        [byte[]]$Bytes,
        [string]$EncodingName = 'ascii'
    )

    if (-not $Bytes -or $Bytes.Length -eq 0) { return $null }
    if ($Bytes.Length -gt 1048576) { return $null }

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
        if ($decodedBytes.Length -gt 2097152) { return $null }

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
    if (Test-AstContainsPipelineAutomaticVariable -Ast $Ast) { return $null }

    function Test-LocalStaticDecodedScriptText {
        param([AllowNull()][string]$Text)

        if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
        $trimmed = ([string]$Text).Trim()
        if ($trimmed -match '^(?i)(?:[A-Za-z]:\\|\\\\|%[A-Z_][A-Z0-9_]*%\\)') { return $false }
        if ($trimmed -match '^(?i)(?:\.{1,2}\\|~\\)') { return $false }
        return ((Test-UsefulRecoveredScriptText -Text $trimmed) -and (Test-PowerShellSyntax -ScriptText $trimmed).IsValid)
    }

    $extentText = if ($Ast.PSObject.Properties['Extent'] -and $Ast.Extent) { [string]$Ast.Extent.Text } else { '' }
    $directStaticText = Try-GetStaticStringValue -Ast $Ast -Context $Context
    if (Test-LocalStaticDecodedScriptText -Text $directStaticText) {
        return $directStaticText
    }

    if ($Ast -is [System.Management.Automation.Language.ConvertExpressionAst]) {
        $typeName = Get-StaticConvertTypeName -ConvertAst $Ast
        if ($typeName -and $typeName.ToLowerInvariant() -eq 'string') {
            $childDecoded = Try-DecodeStaticScriptTextFromAst -Ast $Ast.Child -Context $Context
            if (-not [string]::IsNullOrWhiteSpace($childDecoded)) {
                return $childDecoded
            }

            $value = Try-GetStaticStringValue -Ast $Ast.Child -Context $Context
            if (Test-LocalStaticDecodedScriptText -Text $value) {
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
                if (Test-LocalStaticDecodedScriptText -Text $stringValue) {
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

function Try-DecodeEncodedCommand {
    param(
        [Parameter(Mandatory=$true)]
        [System.Management.Automation.Language.CommandAst]$CommandAst
    )

    $cmdName = $CommandAst.GetCommandName()
    if ($cmdName -notmatch '(?i)(^|[/\\])(powershell|pwsh)(\.exe)?$') {
        return $null
    }

    $elements = $CommandAst.CommandElements
    for ($i = 1; $i -lt $elements.Count; $i++) {
        $elem = $elements[$i]

        if ($elem -is [System.Management.Automation.Language.CommandParameterAst]) {
            $paramInfo = Resolve-PowerShellHostLooseParameterInfo -ParameterName ([string]$elem.ParameterName)

            if ($paramInfo -and $paramInfo.DynamicType -eq 'EncodedCommand') {
                $valueElem = $null
                if ($elem.Argument) {
                    $valueElem = $elem.Argument
                } elseif ($i + 1 -lt $elements.Count) {
                    $valueElem = $elements[$i + 1]
                }

                if ($null -ne $valueElem) {
                    $base64String = $null

                    if ($valueElem -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                        $base64String = $valueElem.Value
                    } elseif ($valueElem -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) {
                        $base64String = $valueElem.Value
                    }

                    if ($base64String) {
                        try {
                            $bytes = Try-DecodeBase64ToByteArray -Base64String $base64String
                            if ($null -eq $bytes -or $bytes.Length -eq 0) {
                                return $null
                            }

                            $decoded = [Text.Encoding]::Unicode.GetString($bytes)

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
        } elseif ($Ast -is [System.Management.Automation.Language.CommandExpressionAst]) {
            if ($null -eq $Ast.Expression) {
                $result = [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = $false; Reason = 'command_expression_empty'; Message = 'CommandExpressionAst 缺少内部表达式' }
            } else {
                $result = Resolve-StaticAstValue -Ast $Ast.Expression -Context $Context -AllowEmptyFallback:$AllowEmptyFallback -Depth ($Depth + 1)
            }
        } elseif ($Ast -is [System.Management.Automation.Language.VariableExpressionAst]) {
            $result = Resolve-StaticVariableValue -Context $Context -Ast $Ast -AllowEmptyFallback:$AllowEmptyFallback
        } elseif ($Ast -is [System.Management.Automation.Language.PipelineAst]) {
            $pipelineResult = Resolve-StaticPipelineAstValue -PipelineAst $Ast -Context $Context -AllowEmptyFallback:$AllowEmptyFallback -Depth ($Depth + 1)
            if (-not $pipelineResult.Success) {
                $result = [PSCustomObject]@{
                    Success = $false
                    Value = $null
                    UsedEmptyFallback = [bool]$pipelineResult.UsedEmptyFallback
                    Reason = 'unsupported_pipeline'
                    Message = $pipelineResult.Message
                }
            } else {
                $result = [PSCustomObject]@{
                    Success = $true
                    Value = (Convert-StaticPipelineOutputItemsToValue -Items $pipelineResult.OutputItems)
                    UsedEmptyFallback = [bool]$pipelineResult.UsedEmptyFallback
                    Reason = $null
                    Message = $null
                }
            }
        } elseif ($Ast -is [System.Management.Automation.Language.CommandAst]) {
            $commandResult = Invoke-WholeScriptStaticCommand -CommandAst $Ast -Context $Context -Depth ($Depth + 1)
            if (-not $commandResult.Success) {
                $result = [PSCustomObject]@{
                    Success = $false
                    Value = $null
                    UsedEmptyFallback = [bool]$commandResult.UsedEmptyFallback
                    Reason = 'unsupported_command'
                    Message = $commandResult.Message
                }
            } else {
                $result = [PSCustomObject]@{
                    Success = $true
                    Value = (Convert-StaticPipelineOutputItemsToValue -Items $commandResult.OutputItems)
                    UsedEmptyFallback = [bool]$commandResult.UsedEmptyFallback
                    Reason = $null
                    Message = $null
                }
            }
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
            $pipelineResult = Resolve-StaticPipelineAstValue -PipelineAst $Ast.Pipeline -Context $Context -AllowEmptyFallback:$AllowEmptyFallback -Depth ($Depth + 1)
            if (-not $pipelineResult.Success) {
                $result = [PSCustomObject]@{
                    Success = $false
                    Value = $null
                    UsedEmptyFallback = [bool]$pipelineResult.UsedEmptyFallback
                    Reason = 'unsupported_paren'
                    Message = $pipelineResult.Message
                }
            } else {
                $result = [PSCustomObject]@{
                    Success = $true
                    Value = (Convert-StaticPipelineOutputItemsToValue -Items $pipelineResult.OutputItems)
                    UsedEmptyFallback = [bool]$pipelineResult.UsedEmptyFallback
                    Reason = $null
                    Message = $null
                }
            }
        } elseif ($Ast -is [System.Management.Automation.Language.SubExpressionAst]) {
            $statements = Get-StaticExpressionFromStatementBlock -StatementBlockAst $Ast.SubExpression
            if ($null -eq $statements) {
                $result = [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = $false; Reason = 'unsupported_subexpression'; Message = '子表达式包含 trap 或为空' }
            } else {
                $values = @()
                $usedFallback = $false
                foreach ($statement in $statements) {
                    try {
                        $statementResult = Invoke-WholeScriptStaticStatement -Statement $statement -Context $Context -AllowEmptyFallback:$AllowEmptyFallback -Depth ($Depth + 1)
                    } catch {
                        if (-not (Test-IsCallDepthOverflowException -ErrorObject $_)) {
                            throw
                        }

                        $statementResult = [PSCustomObject]@{
                            Success           = $false
                            OutputItems       = @()
                            UsedEmptyFallback = $usedFallback
                            Message           = ('静态子表达式因调用深度溢出已跳过: ' + (Get-ErrorSummaryText -ErrorObject $_ -DefaultMessage 'call depth overflow'))
                        }
                    }
                    if (-not $statementResult.Success) {
                        $result = [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = ($usedFallback -or [bool]$statementResult.UsedEmptyFallback); Reason = 'subexpression_child'; Message = $statementResult.Message }
                        break
                    }
                    $usedFallback = ($usedFallback -or [bool]$statementResult.UsedEmptyFallback)
                    foreach ($item in @($statementResult.OutputItems)) {
                        $values += ,$item
                    }
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
                    try {
                        $statementResult = Invoke-WholeScriptStaticStatement -Statement $statement -Context $Context -AllowEmptyFallback:$AllowEmptyFallback -Depth ($Depth + 1)
                    } catch {
                        if (-not (Test-IsCallDepthOverflowException -ErrorObject $_)) {
                            throw
                        }

                        $statementResult = [PSCustomObject]@{
                            Success           = $false
                            OutputItems       = @()
                            UsedEmptyFallback = $usedFallback
                            Message           = ('静态数组表达式因调用深度溢出已跳过: ' + (Get-ErrorSummaryText -ErrorObject $_ -DefaultMessage 'call depth overflow'))
                        }
                    }
                    if (-not $statementResult.Success) {
                        $result = [PSCustomObject]@{ Success = $false; Value = $null; UsedEmptyFallback = ($usedFallback -or [bool]$statementResult.UsedEmptyFallback); Reason = 'array_expression_child'; Message = $statementResult.Message }
                        break
                    }
                    $usedFallback = ($usedFallback -or [bool]$statementResult.UsedEmptyFallback)
                    foreach ($item in @($statementResult.OutputItems)) {
                        $values += ,$item
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
    $isCmdline = Test-IsCmdlineOptimizationProfile
    if ($wholeScriptMaterialized) {
        if ($isCmdline) { return 650 }
        return 520
    }
    if ($sourceKind -eq 'MandatoryBase64') {
        if ($isCmdline) { return 490 }
        return 410
    }
    if ($sourceKind -eq 'DynamicInvoke') {
        if ($protectsInner -and -not [string]::IsNullOrWhiteSpace($materializationKind)) {
            if ($isCmdline) { return 540 }
            return 460
        }
        if ($protectsInner) {
            if ($isCmdline) { return 520 }
            return 440
        }
        return 400
    }
    if ($sourceKind -eq 'LoaderMaterialized') {
        if ($isCmdline) { return 500 }
        return 430
    }
    if ($sourceKind -eq 'FunctionSpecializedInline') { return 422 }
    if ($sourceKind -eq 'FunctionResult' -or $sourceKind -eq 'ScriptBlockInvocation') {
        if ($protectsInner) {
            if ($isCmdline) { return 470 }
            return 420
        }
        return 390
    }
    if ($sourceKind -eq 'ScriptBlockSpecializedInline') { return 388 }
    if ($sourceKind -eq 'ScriptBlockTargetInline') { return 386 }
    if ($sourceKind -eq 'CanonicalCommandInvocation') {
        if ($Candidate.PSObject.Properties['IsOriginMappedFromRuntime'] -and [bool]$Candidate.IsOriginMappedFromRuntime) {
            if ($isCmdline) { return 530 }
            return 450
        }
        return 395
    }
    if ($sourceKind -eq 'CommandTargetAssignment') { return 382 }
    if ($sourceKind -eq 'SensitiveSink') { return 385 }
    if ($sourceKind -eq 'LiteralizedCommand') { return 380 }
    if ($sourceKind -eq 'VariableRead') {
        if ($isCmdline) { return 220 }
        return 350
    }
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

        $cand = [PSCustomObject]@{
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
        $cand = Add-RecordScopeMetadataToCandidate -Candidate $cand -Record $rec
        $candidates += $cand
    }

    $merged = Merge-ReplacementCandidatesByRange -Candidates $candidates
    return [PSCustomObject]@{
        Candidates = @($merged.Candidates)
        Skipped    = @($skipped) + @($merged.Skipped)
    }
}

function Get-CanonicalCommandInvocationReplacementCandidates {
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][string]$ScriptText
    )

    $candidates = @()
    $skipped = @()

    if (-not $Context.ContainsKey('CanonicalCommandInvocationResults') -or
        -not $Context.CanonicalCommandInvocationResults -or
        $Context.CanonicalCommandInvocationResults.Count -eq 0) {
        return [PSCustomObject]@{
            Candidates = @()
            Skipped    = @()
        }
    }

    foreach ($rec in @($Context.CanonicalCommandInvocationResults)) {
        if (-not $rec) { continue }

        $nodeId = if ($rec.PSObject.Properties['NodeId']) { $rec.NodeId } else { $null }
        $node = if ($Context.CFG -and $nodeId) { Get-NodeById -CFG $Context.CFG -Id $nodeId } else { $null }
        $replacement = if ($rec.PSObject.Properties['ReplacementText']) { [string]$rec.ReplacementText } else { $null }

        $baseItem = [PSCustomObject]@{
            StartOffset = if ($rec.PSObject.Properties['StartOffset']) { $rec.StartOffset } else { $null }
            EndOffset   = if ($rec.PSObject.Properties['EndOffset']) { $rec.EndOffset } else { $null }
            Type        = 'CanonicalCommandInvocation'
            Depth       = $null
            NodeId      = $nodeId
        }

        if (-not $node) {
            $skipped += New-SkipRecord -Reason 'canonical_command_node_missing' -Message "Canonical command 节点不存在: NodeId=$nodeId" -Item $baseItem
            continue
        }
        if ([string]::IsNullOrWhiteSpace($replacement)) {
            $skipped += New-SkipRecord -Reason 'canonical_command_empty' -Message 'Canonical command replacement 为空，跳过' -Item $baseItem
            continue
        }

        $originInfo = Resolve-DynamicInvokeOriginInfo -Context $Context -Record $rec -Node $node
        if (-not $originInfo.Success) {
            $skipped += New-SkipRecord -Reason 'canonical_command_unmapped' -Message 'Canonical command 无法映射回原脚本位点，跳过' -Item $baseItem
            continue
        }

        $start = [int]$originInfo.StartOffset
        $end = [int]$originInfo.EndOffset
        $resolvedRange = Resolve-DynamicInvokeRangeAgainstCurrentScript -ScriptText $ScriptText -StartOffset $start -EndOffset $end -Node $node -Record $rec
        if (-not $resolvedRange.Success) {
            $skipped += New-SkipRecord -Reason 'canonical_command_out_of_range' -Message "Canonical command offset 无法映射到当前脚本文本: [$start-$end], len=$($ScriptText.Length)" -Item $baseItem
            continue
        }

        $start = [int]$resolvedRange.StartOffset
        $end = [int]$resolvedRange.EndOffset
        if ($start -lt 0 -or $end -le $start -or $end -gt $ScriptText.Length) {
            $skipped += New-SkipRecord -Reason 'canonical_command_out_of_range' -Message "Canonical command offset 越界: [$start-$end], len=$($ScriptText.Length)" -Item $baseItem
            continue
        }

        $original = $ScriptText.Substring($start, $end - $start)
        if ($original -eq $replacement) {
            $skipped += New-SkipRecord -Reason 'canonical_command_no_change' -Message 'Canonical command replacement 与原片段一致，跳过' -Item $baseItem
            continue
        }

        $cand = [PSCustomObject]@{
            StartOffset = $start
            EndOffset   = $end
            Replacement = $replacement
            Original    = $original
            Type        = 'CanonicalCommandInvocation'
            Depth       = $null
            NodeId      = $nodeId
            SourceKind  = 'CanonicalCommandInvocation'
            Confidence  = 'High'
            UsedEmptyFallback = $false
            ResultType  = 'String'
            Executed    = $true
            ResolvedName = if ($rec.PSObject.Properties['ResolvedName']) { [string]$rec.ResolvedName } else { $null }
            OriginNodeId = [int]$originInfo.NodeId
            OriginRuntimeDepth = [int]$originInfo.RuntimeDepth
            IsOriginMappedFromRuntime = [bool]$originInfo.ViaRuntime
            OriginResolutionMode = [string]$resolvedRange.ResolutionMode
            ProtectsInnerCandidates = $true
        }
        $cand = Add-RecordScopeMetadataToCandidate -Candidate $cand -Record $rec
        $candidates += $cand
    }

    $merged = Merge-ReplacementCandidatesByRange -Candidates $candidates
    return [PSCustomObject]@{
        Candidates = @($merged.Candidates)
        Skipped    = @($skipped) + @($merged.Skipped)
    }
}

function Get-CommandTargetAssignmentReplacementCandidates {
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][string]$ScriptText
    )

    $candidates = @()
    $skipped = @()

    if (-not $Context.ContainsKey('CommandTargetAssignmentResults') -or
        -not $Context.CommandTargetAssignmentResults -or
        $Context.CommandTargetAssignmentResults.Count -eq 0) {
        return [PSCustomObject]@{
            Candidates = @()
            Skipped    = @()
        }
    }

    foreach ($rec in @($Context.CommandTargetAssignmentResults)) {
        if (-not $rec) { continue }

        $start = if ($rec.PSObject.Properties['StartOffset']) { $rec.StartOffset } else { $null }
        $end = if ($rec.PSObject.Properties['EndOffset']) { $rec.EndOffset } else { $null }
        $replacement = if ($rec.PSObject.Properties['ReplacementText']) { [string]$rec.ReplacementText } else { $null }
        $nodeId = if ($rec.PSObject.Properties['NodeId']) { $rec.NodeId } else { $null }

        $baseItem = [PSCustomObject]@{
            StartOffset = $start
            EndOffset   = $end
            Type        = 'CommandTargetAssignment'
            Depth       = $null
            NodeId      = $nodeId
        }

        if ($null -eq $start -or $null -eq $end) {
            $skipped += New-SkipRecord -Reason 'command_target_assignment_no_offset' -Message '命令目标赋值结果缺少 offset，跳过' -Item $baseItem
            continue
        }
        if ($start -lt 0 -or $end -le $start -or $end -gt $ScriptText.Length) {
            $skipped += New-SkipRecord -Reason 'command_target_assignment_out_of_range' -Message "命令目标赋值 offset 越界: [$start-$end], len=$($ScriptText.Length)" -Item $baseItem
            continue
        }
        if ([string]::IsNullOrWhiteSpace($replacement)) {
            $skipped += New-SkipRecord -Reason 'command_target_assignment_empty' -Message '命令目标赋值 replacement 为空，跳过' -Item $baseItem
            continue
        }

        $original = $ScriptText.Substring([int]$start, ([int]$end - [int]$start))
        if ($original -eq $replacement) {
            $skipped += New-SkipRecord -Reason 'command_target_assignment_no_change' -Message '命令目标赋值 replacement 与原片段一致，跳过' -Item $baseItem
            continue
        }

        $cand = [PSCustomObject]@{
            StartOffset = [int]$start
            EndOffset   = [int]$end
            Replacement = $replacement
            Original    = $original
            Type        = 'CommandTargetAssignment'
            Depth       = $null
            NodeId      = $nodeId
            SourceKind  = 'CommandTargetAssignment'
            Confidence  = 'High'
            UsedEmptyFallback = $false
            ResultType  = 'String'
            Executed    = $true
            VariableName = if ($rec.PSObject.Properties['VariableName']) { [string]$rec.VariableName } else { $null }
            ResolvedName = if ($rec.PSObject.Properties['ResolvedName']) { [string]$rec.ResolvedName } else { $null }
        }
        $cand = Add-RecordScopeMetadataToCandidate -Candidate $cand -Record $rec
        $candidates += $cand
    }

    $merged = Merge-ReplacementCandidatesByRange -Candidates $candidates
    return [PSCustomObject]@{
        Candidates = @($merged.Candidates)
        Skipped    = @($skipped) + @($merged.Skipped)
    }
}

function Get-SensitiveSinkReplacementCandidates {
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][string]$ScriptText
    )

    $candidates = @()
    $skipped = @()

    if (-not $Context.ContainsKey('SensitiveSinkResults') -or -not $Context.SensitiveSinkResults -or $Context.SensitiveSinkResults.Count -eq 0) {
        return [PSCustomObject]@{
            Candidates = @()
            Skipped    = @()
        }
    }

    foreach ($rec in @($Context.SensitiveSinkResults)) {
        if (-not $rec) { continue }

        $start = if ($rec.PSObject.Properties['StartOffset']) { $rec.StartOffset } else { $null }
        $end = if ($rec.PSObject.Properties['EndOffset']) { $rec.EndOffset } else { $null }
        $replacement = if ($rec.PSObject.Properties['ReplacementText']) { [string]$rec.ReplacementText } else { $null }
        $nodeId = if ($rec.PSObject.Properties['NodeId']) { $rec.NodeId } else { $null }

        $baseItem = [PSCustomObject]@{
            StartOffset = $start
            EndOffset   = $end
            Type        = 'SensitiveSink'
            Depth       = $null
            NodeId      = $nodeId
        }

        if ($null -eq $start -or $null -eq $end) {
            $skipped += New-SkipRecord -Reason 'sensitive_sink_no_offset' -Message '敏感 sink 结果缺少 offset，跳过' -Item $baseItem
            continue
        }
        if ([string]::IsNullOrWhiteSpace($replacement)) {
            $skipped += New-SkipRecord -Reason 'sensitive_sink_empty' -Message '敏感 sink replacement 为空，跳过' -Item $baseItem
            continue
        }
        if ($start -lt 0 -or $end -le $start -or $end -gt $ScriptText.Length) {
            $skipped += New-SkipRecord -Reason 'sensitive_sink_out_of_range' -Message "敏感 sink offset 越界: [$start-$end]" -Item $baseItem
            continue
        }

        $original = $ScriptText.Substring([int]$start, ([int]$end - [int]$start))
        $recordOriginal = if ($rec.PSObject.Properties['OriginalText']) { [string]$rec.OriginalText } else { $null }
        if (-not [string]::IsNullOrEmpty($recordOriginal) -and
            -not [string]::Equals($original, $recordOriginal, [System.StringComparison]::Ordinal)) {
            $relocated = Find-BestExactTextRangeInScriptText -ScriptText $ScriptText -CandidateTexts @($recordOriginal) -PreferredStartOffset ([int]$start)
            if ($relocated) {
                $start = [int]$relocated.StartOffset
                $end = [int]$relocated.EndOffset
                $baseItem.StartOffset = $start
                $baseItem.EndOffset = $end
                $original = $ScriptText.Substring([int]$start, ([int]$end - [int]$start))
            } else {
                $skipped += New-SkipRecord -Reason 'sensitive_sink_offset_mismatch' -Message '敏感 sink offset 与原文不匹配，且无法重定位，跳过' -Item $baseItem
                continue
            }
        }
        if ($original -eq $replacement) {
            $skipped += New-SkipRecord -Reason 'sensitive_sink_no_change' -Message '敏感 sink replacement 与原片段一致，跳过' -Item $baseItem
            continue
        }

        $cand = [PSCustomObject]@{
            StartOffset = [int]$start
            EndOffset   = [int]$end
            Replacement = $replacement
            Original    = $original
            Type        = 'SensitiveSink'
            Depth       = $null
            NodeId      = $nodeId
            SourceKind  = 'SensitiveSink'
            Confidence  = 'High'
            UsedEmptyFallback = if ($rec.PSObject.Properties['UsedEmptyFallback']) { [bool]$rec.UsedEmptyFallback } else { $false }
            ResultType  = 'SensitiveSink'
            Executed    = if ($rec.PSObject.Properties['Executed']) { [bool]$rec.Executed } else { $true }
            SinkType    = if ($rec.PSObject.Properties['SinkType']) { [string]$rec.SinkType } else { $null }
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
        [Parameter(Mandatory)][string]$ScriptText,
        [ValidateSet('skip', 'prefer')]
        [string]$DynamicConflictPolicy = 'skip'
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

        $cand = [PSCustomObject]@{
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
        $cand = Add-RecordScopeMetadataToCandidate -Candidate $cand -Record $rec
        $candidates += $cand
    }

    $merged = Merge-DynamicInvokeReplacementCandidates -Candidates $candidates -ScriptText $ScriptText -DynamicConflictPolicy $DynamicConflictPolicy
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
        $skipped += New-SkipRecord -Reason 'function_result_replaced_by_specialized_inline' -Message "函数返回值不再直接回写调用点，改由调用点专用函数体承载: $funcName" -Item ([PSCustomObject]@{
                StartOffset = $start
                EndOffset   = $end
                Type        = 'FunctionInvoke'
                Depth       = $null
                NodeId      = $nodeId
            })
    }
    return [PSCustomObject]@{
        Candidates = @()
        Skipped    = @($skipped)
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

        $cand = [PSCustomObject]@{
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
        $cand = Add-RecordScopeMetadataToCandidate -Candidate $cand -Record $rec
        $candidates += $cand
    }

    $merged = Merge-ReplacementCandidatesByRange -Candidates $candidates
    return [PSCustomObject]@{
        Candidates = @($merged.Candidates)
        Skipped    = @($skipped) + @($merged.Skipped)
    }
}

function Get-FunctionDefinitionAstByName {
    param(
        [Parameter(Mandatory)][string]$ScriptText,
        [Parameter(Mandatory)][string]$FunctionName
    )

    if ([string]::IsNullOrWhiteSpace($FunctionName)) { return $null }

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($ScriptText, [ref]$tokens, [ref]$errors)
    if (-not $ast -or ($errors -and $errors.Count -gt 0)) { return $null }

    $matches = @($ast.FindAll({
                param($n)
                if ($n -isnot [System.Management.Automation.Language.FunctionDefinitionAst]) { return $false }
                return ([string]$n.Name -ieq [string]$FunctionName)
            }, $true))

    if ($matches.Count -eq 0) { return $null }
    return $matches[0]
}

function Get-FunctionInvocationArgumentText {
    param(
        [AllowNull()][string]$InvocationText,
        [AllowNull()][string]$FunctionName
    )

    if ([string]::IsNullOrWhiteSpace($InvocationText)) { return '' }

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput([string]$InvocationText, [ref]$tokens, [ref]$errors)
    if (-not $ast -or ($errors -and $errors.Count -gt 0)) { return '' }

    $cmd = @($ast.FindAll({
                param($n)
                if ($n -isnot [System.Management.Automation.Language.CommandAst]) { return $false }
                $name = $n.GetCommandName()
                if ([string]::IsNullOrWhiteSpace($FunctionName)) { return $true }
                return ($name -and [string]$name -ieq [string]$FunctionName)
            }, $true) | Select-Object -First 1)

    if ($cmd.Count -eq 0) { return '' }
    $cmdAst = $cmd[0]
    $elements = @($cmdAst.CommandElements)
    if ($elements.Count -lt 2 -or -not $elements[0].Extent) { return '' }

    $argStart = [int]$elements[0].Extent.EndOffset
    $argEnd = [int]$cmdAst.Extent.EndOffset
    if ($argStart -lt 0 -or $argEnd -le $argStart -or $argEnd -gt $InvocationText.Length) { return '' }

    return ([string]$InvocationText).Substring($argStart, $argEnd - $argStart).Trim()
}

function Add-FunctionParameterBlockIfNeeded {
    param(
        [Parameter(Mandatory)][string]$ScriptBlockText,
        [AllowNull()][System.Management.Automation.Language.FunctionDefinitionAst]$FunctionAst
    )

    if ($null -eq $FunctionAst -or $null -eq $FunctionAst.Body) { return $ScriptBlockText }
    if ($FunctionAst.Body.ParamBlock) { return $ScriptBlockText }
    if (-not $FunctionAst.Parameters -or @($FunctionAst.Parameters).Count -eq 0) { return $ScriptBlockText }

    $trimmed = ([string]$ScriptBlockText).Trim()
    if (-not ($trimmed.StartsWith('{') -and $trimmed.EndsWith('}'))) { return $ScriptBlockText }

    $paramText = 'param(' + ((@($FunctionAst.Parameters) | ForEach-Object {
                if ($_.Extent) { [string]$_.Extent.Text } else { '$null' }
            }) -join ', ') + ')'
    $inner = $trimmed.Substring(1, $trimmed.Length - 2)

    return "{`n$paramText`n$inner`n}"
}

function New-SpecializedFunctionTextForInvocation {
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][string]$ScriptText,
        [Parameter(Mandatory)]$CallInstance,
        [AllowEmptyCollection()][array]$BaseCandidates
    )

    $funcName = Get-RecordFieldValue -Record $CallInstance -Name 'FunctionName' -Default $null
    $invocationId = Get-RecordFieldValue -Record $CallInstance -Name 'InvocationId' -Default $null
    if ([string]::IsNullOrWhiteSpace([string]$funcName) -or [string]::IsNullOrWhiteSpace([string]$invocationId)) {
        return $null
    }

    $funcAst = Get-FunctionDefinitionAstByName -ScriptText $ScriptText -FunctionName ([string]$funcName)
    if (-not $funcAst -or -not $funcAst.Body -or -not $funcAst.Body.Extent) { return $null }

    $bodyStart = [int]$funcAst.Body.Extent.StartOffset
    $bodyEnd = [int]$funcAst.Body.Extent.EndOffset
    if ($bodyStart -lt 0 -or $bodyEnd -le $bodyStart -or $bodyEnd -gt $ScriptText.Length) { return $null }

    $bodyText = $ScriptText.Substring($bodyStart, $bodyEnd - $bodyStart)
    if ([string]::IsNullOrWhiteSpace($bodyText)) { return $null }

    $contextInfo = Get-ReplacementContextInfoFromScriptText -ScriptText $ScriptText
    $relativeCandidates = @()
    foreach ($cand in @($BaseCandidates)) {
        if (-not $cand) { continue }
        if (-not $cand.PSObject.Properties['StartOffset'] -or -not $cand.PSObject.Properties['EndOffset']) { continue }

        $sourceKind = if ($cand.PSObject.Properties['SourceKind']) { [string]$cand.SourceKind } else { '' }
        if ($sourceKind -in @('FunctionSpecializedInline', 'FunctionResult', 'ScriptBlockTargetInline', 'ScriptBlockSpecializedInline', 'ScriptBlockInvocation')) { continue }

        $start = [int]$cand.StartOffset
        $end = [int]$cand.EndOffset
        if ($start -lt $bodyStart -or $end -gt $bodyEnd -or $end -le $start) { continue }
        if ($sourceKind -eq 'VariableRead' -and
            (Test-ReplacementWithinRanges -StartOffset $start -EndOffset $end -Ranges $contextInfo.ExpandableStringRanges)) {
            continue
        }

        $isDefinitionSafe = Test-ReusableScriptBlockDefinitionCandidateAllowed -Candidate $cand
        $isInvocationSpecific = Test-CandidateMatchesScopeInvocation -Candidate $cand -InvocationId ([string]$invocationId)
        if (-not $isDefinitionSafe -and -not $isInvocationSpecific) { continue }

        $relativeCandidates += [PSCustomObject]@{
            StartOffset = [int]($start - $bodyStart)
            EndOffset   = [int]($end - $bodyStart)
            Replacement = [string]$cand.Replacement
            Original    = if ($cand.PSObject.Properties['Original']) { [string]$cand.Original } else { $bodyText.Substring(($start - $bodyStart), ($end - $start)) }
            Type        = if ($cand.PSObject.Properties['Type']) { $cand.Type } else { $sourceKind }
            Depth       = if ($cand.PSObject.Properties['Depth']) { $cand.Depth } else { $null }
            NodeId      = if ($cand.PSObject.Properties['NodeId']) { $cand.NodeId } else { $null }
            SourceKind  = $sourceKind
            Confidence  = if ($cand.PSObject.Properties['Confidence']) { $cand.Confidence } else { 'High' }
            ProtectsInnerCandidates = if ($cand.PSObject.Properties['ProtectsInnerCandidates']) { [bool]$cand.ProtectsInnerCandidates } else { $false }
        }
    }

    $newBodyText = $bodyText
    if ($relativeCandidates.Count -gt 0) {
        $sel = Select-NonOverlappingReplacements -Candidates $relativeCandidates -Strategy $effectiveOverlapStrategy
        $selected = @($sel.Selected)
        if ($selected.Count -gt 0) {
            $newBodyText = Apply-ReplacementsToText -Text $bodyText -Replacements $selected
        }
    }

    $newBodyText = Add-FunctionParameterBlockIfNeeded -ScriptBlockText $newBodyText -FunctionAst $funcAst
    $syntax = Test-PowerShellSyntax -ScriptText $newBodyText
    if (-not $syntax.IsValid) { return $null }

    return $newBodyText
}

function Get-FunctionSpecializedInlineReplacementCandidates {
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][string]$ScriptText,
        [AllowEmptyCollection()][array]$BaseCandidates
    )

    $candidates = @()
    $skipped = @()

    if (-not $Context.ContainsKey('FunctionCallInstances') -or -not $Context.FunctionCallInstances) {
        return [PSCustomObject]@{ Candidates = @(); Skipped = @() }
    }

    $used = @{}
    foreach ($call in @($Context.FunctionCallInstances)) {
        if (-not $call) { continue }

        $funcName = [string](Get-RecordFieldValue -Record $call -Name 'FunctionName' -Default '')
        $invocationId = [string](Get-RecordFieldValue -Record $call -Name 'InvocationId' -Default '')
        $start = Get-RecordFieldValue -Record $call -Name 'StartOffset' -Default $null
        $end = Get-RecordFieldValue -Record $call -Name 'EndOffset' -Default $null
        if ([string]::IsNullOrWhiteSpace($funcName) -or [string]::IsNullOrWhiteSpace($invocationId)) { continue }

        $baseItem = [PSCustomObject]@{
            StartOffset = $start
            EndOffset   = $end
            Type        = 'FunctionSpecializedInline'
            Depth       = $null
            NodeId      = Get-RecordFieldValue -Record $call -Name 'CallerNodeId' -Default $null
        }

        if ($null -eq $start -or $null -eq $end) {
            $skipped += New-SkipRecord -Reason 'function_specialized_no_offset' -Message "函数调用无 offset，跳过专用展开: $funcName" -Item $baseItem
            continue
        }
        $start = [int]$start
        $end = [int]$end
        if ($start -lt 0 -or $end -le $start -or $end -gt $ScriptText.Length) {
            $skipped += New-SkipRecord -Reason 'function_specialized_out_of_range' -Message "函数调用 offset 越界: [$start-$end]" -Item $baseItem
            continue
        }

        $key = "$start`:$end`:$invocationId"
        if ($used.ContainsKey($key)) { continue }
        $used[$key] = $true

        $specializedText = New-SpecializedFunctionTextForInvocation -Context $Context -ScriptText $ScriptText -CallInstance $call -BaseCandidates $BaseCandidates
        if ([string]::IsNullOrWhiteSpace($specializedText)) {
            $skipped += New-SkipRecord -Reason 'function_specialized_empty' -Message "函数调用实例没有可安全展开的函数体: $funcName" -Item $baseItem
            continue
        }

        $original = $ScriptText.Substring($start, $end - $start)
        $invocationText = [string](Get-RecordFieldValue -Record $call -Name 'InvocationText' -Default $original)
        if ([string]::IsNullOrWhiteSpace($invocationText)) { $invocationText = $original }
        $argumentText = Get-FunctionInvocationArgumentText -InvocationText $invocationText -FunctionName $funcName
        $suffix = if ([string]::IsNullOrWhiteSpace($argumentText)) { '' } else { ' ' + $argumentText }
        $replacement = "(& $specializedText$suffix)"

        if ($replacement -eq $original) {
            $skipped += New-SkipRecord -Reason 'function_specialized_no_change' -Message "函数调用专用展开无变化，跳过: $funcName" -Item $baseItem
            continue
        }

        $candidates += [PSCustomObject]@{
            StartOffset = $start
            EndOffset   = $end
            Replacement = $replacement
            Original    = $original
            Type        = 'FunctionSpecializedInline'
            Depth       = $null
            NodeId      = Get-RecordFieldValue -Record $call -Name 'CallerNodeId' -Default $null
            SourceKind  = 'FunctionSpecializedInline'
            Confidence  = 'High'
            UsedEmptyFallback = $false
            ResultType  = 'FunctionCall'
            Executed    = $true
            FunctionName = $funcName
            InvocationId = $invocationId
            ProtectsInnerCandidates = $true
        }
    }

    return [PSCustomObject]@{
        Candidates = @($candidates)
        Skipped    = @($skipped)
    }
}

function Get-NormalizedScriptBlockInlineText {
    param([AllowNull()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $trimmed = $Text.Trim()
    if ($trimmed.StartsWith('{') -and $trimmed.EndsWith('}')) {
        return $trimmed
    }
    return "{ $trimmed }"
}

function Get-ScriptBlockInlineTextByBlockName {
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [AllowNull()][string]$BlockName
    )

    if ([string]::IsNullOrWhiteSpace($BlockName)) { return $null }
    if (-not $Context.ScriptBlockSubgraphs -or -not $Context.ScriptBlockSubgraphs.ContainsKey($BlockName)) { return $null }

    $blockStartId = $Context.ScriptBlockSubgraphs[$BlockName]
    $blockStartNode = Get-NodeById -CFG $Context.CFG -Id $blockStartId
    if (-not $blockStartNode -or -not $blockStartNode.PSObject.Properties['ScriptBlockText']) { return $null }

    return Get-NormalizedScriptBlockInlineText -Text ([string]$blockStartNode.ScriptBlockText)
}

function Get-ScriptBlockTargetVariableAst {
    param([AllowNull()]$Ast)

    if ($Ast -is [System.Management.Automation.Language.VariableExpressionAst]) {
        return $Ast
    }
    if ($Ast -is [System.Management.Automation.Language.CommandExpressionAst]) {
        return Get-ScriptBlockTargetVariableAst -Ast $Ast.Expression
    }
    if ($Ast -is [System.Management.Automation.Language.ConvertExpressionAst]) {
        return Get-ScriptBlockTargetVariableAst -Ast $Ast.Child
    }
    return $null
}

function Resolve-KnownScriptBlockTargetName {
    param(
        [AllowNull()]$Ast,
        [Parameter(Mandatory)][hashtable]$Context
    )

    $varAst = Get-ScriptBlockTargetVariableAst -Ast $Ast
    if (-not $varAst -or -not $varAst.VariablePath) { return $null }

    $varName = [string]$varAst.VariablePath.UserPath
    if ([string]::IsNullOrWhiteSpace($varName)) { return $null }

    if ($Context.ScriptBlockSubgraphs -and $Context.ScriptBlockSubgraphs.ContainsKey($varName)) {
        return $varName
    }

    if ($Context.VarToBlockMapping -and $Context.VarToBlockMapping.ContainsKey($varName)) {
        $blockName = [string]$Context.VarToBlockMapping[$varName]
        if (-not [string]::IsNullOrWhiteSpace($blockName) -and
            $Context.ScriptBlockSubgraphs -and $Context.ScriptBlockSubgraphs.ContainsKey($blockName)) {
            return $blockName
        }
    }

    return $null
}

function New-ScriptBlockTargetInlineReplacementCandidate {
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][string]$ScriptText,
        [AllowNull()]$TargetAst,
        [bool]$Parenthesize = $false,
        [AllowNull()][string]$CallKind = $null
    )

    $varAst = Get-ScriptBlockTargetVariableAst -Ast $TargetAst
    if (-not $varAst -or -not $varAst.Extent) { return $null }

    $blockName = Resolve-KnownScriptBlockTargetName -Ast $varAst -Context $Context
    $blockText = Get-ScriptBlockInlineTextByBlockName -Context $Context -BlockName $blockName
    if ([string]::IsNullOrWhiteSpace($blockText)) { return $null }

    $replacement = if ($Parenthesize) { "($blockText)" } else { $blockText }
    $start = [int]$varAst.Extent.StartOffset
    $end = [int]$varAst.Extent.EndOffset
    if ($start -lt 0 -or $end -le $start -or $end -gt $ScriptText.Length) { return $null }

    $original = $ScriptText.Substring($start, $end - $start)
    if ($original -eq $replacement) { return $null }

    return [PSCustomObject]@{
        StartOffset = $start
        EndOffset   = $end
        Replacement = $replacement
        Original    = $original
        Type        = 'ScriptBlockTargetInline'
        Depth       = $null
        NodeId      = $null
        SourceKind  = 'ScriptBlockTargetInline'
        Confidence  = 'High'
        UsedEmptyFallback = $false
        ResultType  = 'ScriptBlockTarget'
        Executed    = $true
        BlockName   = [string]$blockName
        CallKind    = $CallKind
        Parenthesize = [bool]$Parenthesize
        ProtectsInnerCandidates = $false
    }
}

function Get-CommandElementNameText {
    param([AllowNull()]$Ast)

    if ($Ast -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
        return ([string]$Ast.Value)
    }
    return $null
}

function Get-ScriptBlockCommandArgumentTargets {
    param(
        [Parameter(Mandatory)][System.Management.Automation.Language.CommandAst]$CommandAst,
        [Parameter(Mandatory)][string]$CommandName
    )

    $targets = @()
    $elements = @($CommandAst.CommandElements)
    if ($elements.Count -lt 2) { return @() }

    $lowerName = $CommandName.ToLowerInvariant()
    $namedParameters = @()
    $positionalAllowed = $false

    switch ($lowerName) {
        { $_ -in @('invoke-command', 'icm') } {
            $namedParameters = @('scriptblock', 'sb')
            $positionalAllowed = $true
            break
        }
        { $_ -in @('foreach-object', 'foreach', '%') } {
            $namedParameters = @('process', 'begin', 'end', 'remainingscripts')
            $positionalAllowed = $true
            break
        }
        { $_ -in @('where-object', 'where', '?') } {
            $namedParameters = @('filterscript')
            $positionalAllowed = $true
            break
        }
        default {
            return @()
        }
    }

    $consumed = @{}
    for ($i = 1; $i -lt $elements.Count; $i++) {
        $elem = $elements[$i]
        if ($elem -isnot [System.Management.Automation.Language.CommandParameterAst]) { continue }

        $paramName = ([string]$elem.ParameterName).ToLowerInvariant()
        if ($paramName -notin $namedParameters) { continue }

        $target = if ($elem.Argument) {
            $elem.Argument
        } elseif (($i + 1) -lt $elements.Count) {
            $elements[$i + 1]
        } else {
            $null
        }
        if (-not $target) { continue }
        if (Get-ScriptBlockTargetVariableAst -Ast $target) {
            $targets += $target
            if (-not $elem.Argument) {
                $consumed[$i + 1] = $true
            }
        }
    }

    if ($positionalAllowed) {
        for ($i = 1; $i -lt $elements.Count; $i++) {
            if ($consumed.ContainsKey($i)) { continue }
            $elem = $elements[$i]
            if ($elem -is [System.Management.Automation.Language.CommandParameterAst]) {
                if (($i + 1) -lt $elements.Count) { $i++ }
                continue
            }
            if (Get-ScriptBlockTargetVariableAst -Ast $elem) {
                $targets += $elem
            }
        }
    }

    return @($targets)
}

function Get-ScriptBlockTargetInlineReplacementCandidates {
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][string]$ScriptText
    )

    $candidates = @()
    $skipped = @()
    if (-not $Context.ScriptBlockSubgraphs -or $Context.ScriptBlockSubgraphs.Count -eq 0) {
        return [PSCustomObject]@{ Candidates = @(); Skipped = @() }
    }

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($ScriptText, [ref]$tokens, [ref]$errors)
    if (-not $ast -or ($errors -and $errors.Count -gt 0)) {
        return [PSCustomObject]@{
            Candidates = @()
            Skipped    = @(New-SkipRecord -Reason 'scriptblock_target_parse_error' -Message '当前脚本文本无法解析，跳过脚本块目标内联' -Item $null)
        }
    }

    $seen = @{}
    $nodes = $ast.FindAll({
            param($n)
            return ($n -is [System.Management.Automation.Language.CommandAst] -or
                $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst])
        }, $true)

    foreach ($node in @($nodes)) {
        if ($node -is [System.Management.Automation.Language.CommandAst]) {
            $elements = @($node.CommandElements)
            if ($elements.Count -eq 0) { continue }

            if ([string]$node.InvocationOperator -in @('Ampersand', 'Dot')) {
                $cand = New-ScriptBlockTargetInlineReplacementCandidate -Context $Context -ScriptText $ScriptText -TargetAst $elements[0] -CallKind ([string]$node.InvocationOperator)
                if ($cand) {
                    $key = Get-ReplacementRangeKey -StartOffset $cand.StartOffset -EndOffset $cand.EndOffset
                    if (-not $seen.ContainsKey($key)) {
                        $seen[$key] = $true
                        $candidates += $cand
                    }
                }
                continue
            }

            $cmdName = $node.GetCommandName()
            if ([string]::IsNullOrWhiteSpace($cmdName)) {
                $cmdName = Get-CommandElementNameText -Ast $elements[0]
            }
            if ([string]::IsNullOrWhiteSpace($cmdName)) { continue }

            foreach ($target in @(Get-ScriptBlockCommandArgumentTargets -CommandAst $node -CommandName $cmdName)) {
                $cand = New-ScriptBlockTargetInlineReplacementCandidate -Context $Context -ScriptText $ScriptText -TargetAst $target -CallKind $cmdName
                if (-not $cand) { continue }

                $key = Get-ReplacementRangeKey -StartOffset $cand.StartOffset -EndOffset $cand.EndOffset
                if ($seen.ContainsKey($key)) { continue }
                $seen[$key] = $true
                $candidates += $cand
            }
        } elseif ($node -is [System.Management.Automation.Language.InvokeMemberExpressionAst]) {
            $memberName = $null
            if ($node.Member -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                $memberName = [string]$node.Member.Value
            } elseif ($node.Member -and $node.Member.Extent) {
                $memberName = [string]$node.Member.Extent.Text
            }
            if ([string]::IsNullOrWhiteSpace($memberName) -or $memberName -notin @('Invoke', 'InvokeWithContext')) { continue }

            $cand = New-ScriptBlockTargetInlineReplacementCandidate -Context $Context -ScriptText $ScriptText -TargetAst $node.Expression -Parenthesize:$true -CallKind $memberName
            if (-not $cand) { continue }

            $key = Get-ReplacementRangeKey -StartOffset $cand.StartOffset -EndOffset $cand.EndOffset
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key] = $true
            $candidates += $cand
        }
    }

    return [PSCustomObject]@{
        Candidates = @($candidates)
        Skipped    = @($skipped)
    }
}

function Test-CandidateMatchesScopeInvocation {
    param(
        [AllowNull()]$Candidate,
        [AllowNull()][string]$InvocationId
    )

    if (-not $Candidate -or [string]::IsNullOrWhiteSpace($InvocationId)) { return $false }
    if ($Candidate.PSObject.Properties['ScopeInvocationId'] -and [string]$Candidate.ScopeInvocationId -eq [string]$InvocationId) { return $true }
    if ($Candidate.PSObject.Properties['ParentScopeInvocationId'] -and [string]$Candidate.ParentScopeInvocationId -eq [string]$InvocationId) { return $true }
    return $false
}

function New-SpecializedScriptBlockTextForInvocation {
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][string]$ScriptText,
        [Parameter(Mandatory)]$CallInstance,
        [AllowEmptyCollection()][array]$BaseCandidates
    )

    $blockName = Get-RecordFieldValue -Record $CallInstance -Name 'BlockName' -Default $null
    $invocationId = Get-RecordFieldValue -Record $CallInstance -Name 'InvocationId' -Default $null
    if ([string]::IsNullOrWhiteSpace([string]$blockName) -or [string]::IsNullOrWhiteSpace([string]$invocationId)) {
        return $null
    }

    $blockStart = Get-RecordFieldValue -Record $CallInstance -Name 'BlockStartOffset' -Default $null
    $blockEnd = Get-RecordFieldValue -Record $CallInstance -Name 'BlockEndOffset' -Default $null
    if ($null -eq $blockStart -or $null -eq $blockEnd) {
        if (-not $Context.ScriptBlockSubgraphs -or -not $Context.ScriptBlockSubgraphs.ContainsKey([string]$blockName)) { return $null }
        $blockStartNode = Get-NodeById -CFG $Context.CFG -Id $Context.ScriptBlockSubgraphs[[string]$blockName]
        if (-not $blockStartNode) { return $null }
        $blockStart = if ($blockStartNode.PSObject.Properties['TextStartOffset']) { $blockStartNode.TextStartOffset } else { $null }
        $blockEnd = if ($blockStartNode.PSObject.Properties['TextEndOffset']) { $blockStartNode.TextEndOffset } else { $null }
    }

    if ($null -eq $blockStart -or $null -eq $blockEnd) { return $null }
    $blockStart = [int]$blockStart
    $blockEnd = [int]$blockEnd
    if ($blockStart -lt 0 -or $blockEnd -le $blockStart -or $blockEnd -gt $ScriptText.Length) { return $null }

    $blockText = $ScriptText.Substring($blockStart, $blockEnd - $blockStart)
    if ([string]::IsNullOrWhiteSpace($blockText)) { return $null }

    $contextInfo = Get-ReplacementContextInfoFromScriptText -ScriptText $ScriptText
    $relativeCandidates = @()
    foreach ($cand in @($BaseCandidates)) {
        if (-not $cand) { continue }
        if (-not $cand.PSObject.Properties['StartOffset'] -or -not $cand.PSObject.Properties['EndOffset']) { continue }

        $sourceKind = if ($cand.PSObject.Properties['SourceKind']) { [string]$cand.SourceKind } else { '' }
        if ($sourceKind -in @('ScriptBlockTargetInline', 'ScriptBlockSpecializedInline', 'ScriptBlockInvocation')) { continue }

        $start = [int]$cand.StartOffset
        $end = [int]$cand.EndOffset
        if ($start -lt $blockStart -or $end -gt $blockEnd -or $end -le $start) { continue }
        if ($sourceKind -eq 'VariableRead' -and
            (Test-ReplacementWithinRanges -StartOffset $start -EndOffset $end -Ranges $contextInfo.ExpandableStringRanges)) {
            continue
        }

        $isDefinitionSafe = Test-ReusableScriptBlockDefinitionCandidateAllowed -Candidate $cand
        $isInvocationSpecific = Test-CandidateMatchesScopeInvocation -Candidate $cand -InvocationId ([string]$invocationId)
        if (-not $isDefinitionSafe -and -not $isInvocationSpecific) { continue }

        $relativeCandidates += [PSCustomObject]@{
            StartOffset = [int]($start - $blockStart)
            EndOffset   = [int]($end - $blockStart)
            Replacement = [string]$cand.Replacement
            Original    = if ($cand.PSObject.Properties['Original']) { [string]$cand.Original } else { $blockText.Substring(($start - $blockStart), ($end - $start)) }
            Type        = if ($cand.PSObject.Properties['Type']) { $cand.Type } else { $sourceKind }
            Depth       = if ($cand.PSObject.Properties['Depth']) { $cand.Depth } else { $null }
            NodeId      = if ($cand.PSObject.Properties['NodeId']) { $cand.NodeId } else { $null }
            SourceKind  = $sourceKind
            Confidence  = if ($cand.PSObject.Properties['Confidence']) { $cand.Confidence } else { 'High' }
            ProtectsInnerCandidates = if ($cand.PSObject.Properties['ProtectsInnerCandidates']) { [bool]$cand.ProtectsInnerCandidates } else { $false }
        }
    }

    if ($relativeCandidates.Count -eq 0) { return $null }

    $sel = Select-NonOverlappingReplacements -Candidates $relativeCandidates -Strategy $effectiveOverlapStrategy
    $selected = @($sel.Selected)
    if ($selected.Count -eq 0) { return $null }

    $newBlockText = Apply-ReplacementsToText -Text $blockText -Replacements $selected
    if ($newBlockText -eq $blockText) { return $null }

    $syntax = Test-PowerShellSyntax -ScriptText $newBlockText
    if (-not $syntax.IsValid) { return $null }

    return $newBlockText
}

function Get-ScriptBlockSpecializedInlineReplacementCandidates {
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][string]$ScriptText,
        [AllowEmptyCollection()][array]$BaseCandidates,
        [AllowEmptyCollection()][array]$TargetCandidates
    )

    $candidates = @()
    $skipped = @()

    if (-not $Context.ContainsKey('ScriptBlockCallInstances') -or -not $Context.ScriptBlockCallInstances) {
        return [PSCustomObject]@{ Candidates = @(); Skipped = @() }
    }
    if (-not $TargetCandidates -or $TargetCandidates.Count -eq 0) {
        return [PSCustomObject]@{ Candidates = @(); Skipped = @() }
    }

    $used = @{}
    foreach ($site in @($TargetCandidates)) {
        if (-not $site -or [string]$site.SourceKind -ne 'ScriptBlockTargetInline') { continue }
        if (-not $site.PSObject.Properties['BlockName']) { continue }

        $siteBlockName = [string]$site.BlockName
        $siteStart = [int]$site.StartOffset
        $siteEnd = [int]$site.EndOffset

        $matchingCalls = @($Context.ScriptBlockCallInstances | Where-Object {
                [string](Get-RecordFieldValue -Record $_ -Name 'BlockName' -Default '') -eq $siteBlockName -and
                $null -ne (Get-RecordFieldValue -Record $_ -Name 'StartOffset' -Default $null) -and
                $null -ne (Get-RecordFieldValue -Record $_ -Name 'EndOffset' -Default $null) -and
                $siteStart -ge [int](Get-RecordFieldValue -Record $_ -Name 'StartOffset' -Default -1) -and
                $siteEnd -le [int](Get-RecordFieldValue -Record $_ -Name 'EndOffset' -Default -1)
            })

        foreach ($call in @($matchingCalls)) {
            $invocationId = [string](Get-RecordFieldValue -Record $call -Name 'InvocationId' -Default '')
            if ([string]::IsNullOrWhiteSpace($invocationId)) { continue }

            $key = "$siteStart`:$siteEnd`:$invocationId"
            if ($used.ContainsKey($key)) { continue }
            $used[$key] = $true

            $specializedText = New-SpecializedScriptBlockTextForInvocation -Context $Context -ScriptText $ScriptText -CallInstance $call -BaseCandidates $BaseCandidates
            if ([string]::IsNullOrWhiteSpace($specializedText)) {
                $skipped += New-SkipRecord -Reason 'scriptblock_specialized_empty' -Message '脚本块调用实例没有可安全内联的专用改写' -Item $site
                continue
            }

            $parenthesize = ($site.PSObject.Properties['Parenthesize'] -and [bool]$site.Parenthesize)
            $replacement = if ($parenthesize) { "($specializedText)" } else { $specializedText }
            $original = $ScriptText.Substring($siteStart, $siteEnd - $siteStart)
            if ($replacement -eq $original) {
                $skipped += New-SkipRecord -Reason 'scriptblock_specialized_no_change' -Message '专用脚本块 replacement 与原目标一致，跳过' -Item $site
                continue
            }

            $candidates += [PSCustomObject]@{
                StartOffset = $siteStart
                EndOffset   = $siteEnd
                Replacement = $replacement
                Original    = $original
                Type        = 'ScriptBlockSpecializedInline'
                Depth       = $null
                NodeId      = if ($site.PSObject.Properties['NodeId']) { $site.NodeId } else { $null }
                SourceKind  = 'ScriptBlockSpecializedInline'
                Confidence  = 'High'
                UsedEmptyFallback = $false
                ResultType  = 'ScriptBlockTarget'
                Executed    = $true
                BlockName   = $siteBlockName
                InvocationId = $invocationId
                CallKind    = if ($site.PSObject.Properties['CallKind']) { $site.CallKind } else { $null }
                Parenthesize = $parenthesize
                ProtectsInnerCandidates = $false
            }
        }
    }

    return [PSCustomObject]@{
        Candidates = @($candidates)
        Skipped    = @($skipped)
    }
}

function Get-ScriptBlockInvocationReplacementCandidates {
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][string]$ScriptText
    )

    $candidates = @()
    $skipped = @()

    if (-not $Context.ContainsKey('ScriptBlockInvocationResults') -or
        -not $Context.ScriptBlockInvocationResults -or
        $Context.ScriptBlockInvocationResults.Count -eq 0) {
        return [PSCustomObject]@{
            Candidates = @()
            Skipped    = @()
        }
    }

    foreach ($rec in @($Context.ScriptBlockInvocationResults)) {
        if (-not $rec) { continue }

        $start = if ($rec.PSObject.Properties['StartOffset']) { $rec.StartOffset } else { $null }
        $end = if ($rec.PSObject.Properties['EndOffset']) { $rec.EndOffset } else { $null }
        $nodeId = if ($rec.PSObject.Properties['NodeId']) { $rec.NodeId } else { $null }
        $replacement = if ($rec.PSObject.Properties['ReplacementText']) { [string]$rec.ReplacementText } else { $null }

        $baseItem = [PSCustomObject]@{
            StartOffset = $start
            EndOffset   = $end
            Type        = 'ScriptBlockInvocation'
            Depth       = $null
            NodeId      = $nodeId
        }

        if ($null -eq $start -or $null -eq $end) {
            $skipped += New-SkipRecord -Reason 'scriptblock_invocation_no_offset' -Message '脚本块调用缺少 offset，跳过' -Item $baseItem
            continue
        }
        if ($start -lt 0 -or $end -le $start -or $end -gt $ScriptText.Length) {
            $skipped += New-SkipRecord -Reason 'scriptblock_invocation_out_of_range' -Message "脚本块调用 offset 越界: [$start-$end], len=$($ScriptText.Length)" -Item $baseItem
            continue
        }
        if ([string]::IsNullOrWhiteSpace($replacement) -or $replacement -eq '__BLOCKED_PLACEHOLDER__') {
            $skipped += New-SkipRecord -Reason 'scriptblock_invocation_empty' -Message '脚本块调用 replacement 为空，跳过' -Item $baseItem
            continue
        }

        $blockStart = if ($rec.PSObject.Properties['BlockStartOffset']) { $rec.BlockStartOffset } else { $null }
        $blockEnd = if ($rec.PSObject.Properties['BlockEndOffset']) { $rec.BlockEndOffset } else { $null }
        if ($null -ne $blockStart -and $null -ne $blockEnd -and
            [int]$blockStart -ge 0 -and [int]$blockEnd -gt [int]$blockStart -and [int]$blockEnd -le $ScriptText.Length) {
            $blockOriginal = $ScriptText.Substring([int]$blockStart, ([int]$blockEnd - [int]$blockStart)).Trim()
            if ($blockOriginal.StartsWith('{') -and $blockOriginal.EndsWith('}')) {
                $skipped += New-SkipRecord -Reason 'scriptblock_invocation_source_backed_block' -Message '脚本块在源码中已有正文，优先改写脚本块正文而不是内联调用点' -Item $baseItem
                continue
            }
        }

        $original = $ScriptText.Substring([int]$start, ([int]$end - [int]$start))
        if ($original -eq $replacement) {
            $skipped += New-SkipRecord -Reason 'scriptblock_invocation_no_change' -Message '脚本块调用 replacement 与原片段一致，跳过' -Item $baseItem
            continue
        }

        $cand = [PSCustomObject]@{
            StartOffset = [int]$start
            EndOffset   = [int]$end
            Replacement = $replacement
            Original    = $original
            Type        = 'ScriptBlockInvocation'
            Depth       = $null
            NodeId      = $nodeId
            SourceKind  = 'ScriptBlockInvocation'
            Confidence  = 'High'
            UsedEmptyFallback = $false
            ResultType  = 'ScriptBlockInvocation'
            Executed    = $true
            ProtectsInnerCandidates = $true
            BlockName = if ($rec.PSObject.Properties['BlockName']) { [string]$rec.BlockName } else { $null }
            BlockStartOffset = if ($rec.PSObject.Properties['BlockStartOffset']) { $rec.BlockStartOffset } else { $null }
            BlockEndOffset = if ($rec.PSObject.Properties['BlockEndOffset']) { $rec.BlockEndOffset } else { $null }
        }
        $cand = Add-RecordScopeMetadataToCandidate -Candidate $cand -Record $rec
        $candidates += $cand
    }

    $merged = Merge-ScriptBlockInvocationReplacementCandidates -Candidates $candidates
    return [PSCustomObject]@{
        Candidates = @($merged.Candidates)
        Skipped    = @($skipped) + @($merged.Skipped)
    }
}

function Merge-ScriptBlockInvocationReplacementCandidates {
    param([array]$Candidates)

    if (-not $Candidates -or $Candidates.Count -eq 0) {
        return [PSCustomObject]@{ Candidates = @(); Skipped = @() }
    }

    $map = @{}
    $conflictRanges = @{}
    $skipped = @()
    foreach ($cand in @($Candidates | Sort-Object StartOffset, EndOffset, NodeId, Type)) {
        if (-not $cand) { continue }
        $key = "$($cand.StartOffset):$($cand.EndOffset):$($cand.NodeId):$($cand.Type)"
        if ($conflictRanges.ContainsKey($key)) {
            $skipped += New-SkipRecord -Reason 'scriptblock_invocation_same_range_conflict' -Message '同一脚本块调用位点产生不同结果，保守跳过该区间' -Item $cand
            continue
        }

        if (-not $map.ContainsKey($key)) {
            $map[$key] = $cand
            continue
        }

        $existing = $map[$key]
        if ([string]$existing.Replacement -eq [string]$cand.Replacement) {
            continue
        }

        $map.Remove($key)
        $conflictRanges[$key] = $true
        $message = '同一脚本块调用位点产生不同结果，保守跳过该区间'
        $skipped += New-SkipRecord -Reason 'scriptblock_invocation_same_range_conflict' -Message $message -Item $existing
        $skipped += New-SkipRecord -Reason 'scriptblock_invocation_same_range_conflict' -Message $message -Item $cand
    }

    return [PSCustomObject]@{
        Candidates = @($map.Values | Sort-Object StartOffset, EndOffset, NodeId, Type)
        Skipped    = @($skipped)
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

    $safeCompressedPayload = Try-Resolve-WholeScriptStaticCompressedLoaderPayloadInfo -ScriptText $ScriptText
    if ($safeCompressedPayload -and -not [string]::IsNullOrWhiteSpace([string]$safeCompressedPayload.PayloadText)) {
        $replacement = Get-WholeScriptReplacementCandidateText -OriginalText $ScriptText -CandidateText ([string]$safeCompressedPayload.PayloadText)
        if ($replacement -and
            (Get-NormalizedScriptComparisonText -ScriptText $replacement) -ne (Get-NormalizedScriptComparisonText -ScriptText $ScriptText)) {
            $candidates += [PSCustomObject]@{
                StartOffset            = 0
                EndOffset              = [int]$ScriptText.Length
                Replacement            = [string]$replacement
                Original               = [string]$ScriptText
                Type                   = 'DynamicInvoke'
                Depth                  = $null
                NodeId                 = $null
                SourceKind             = 'StaticCompressedLoader'
                Confidence             = 'High'
                UsedEmptyFallback      = $false
                ResultType             = 'String'
                Executed               = $false
                ProtectsInnerCandidates = $true
                WholeScriptMaterialized = $true
                MaterializationKind    = if ($safeCompressedPayload.PSObject.Properties['DecodeSource']) { [string]$safeCompressedPayload.DecodeSource } else { 'static_compressed_loader' }
                DynamicStopReason      = 'WholeScriptLoader:StaticCompressedLoader'
                DynamicStopMessage     = 'Recovered whole-script compressed loader without execution'
            }

            return [PSCustomObject]@{
                Candidates = @($candidates)
                Skipped    = @($skipped)
            }
        }
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

function Format-LiteralizedCommandValue {
    param([string]$Value)

    return (Convert-ReplacementTextToExpressionLiteral -Text $Value)
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

function Test-MandatoryBase64ConsumerText {
    param([AllowNull()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $false
    }

    return ([string]$Text -match '(?i)(EncodedCommand|FromBase64String|FromBase64CharArray)')
}

function Get-InvokeMemberNameText {
    param([System.Management.Automation.Language.InvokeMemberExpressionAst]$InvokeAst)

    if ($null -eq $InvokeAst) {
        return $null
    }

    if ($InvokeAst.Member -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
        return [string]$InvokeAst.Member.Value
    }
    if ($InvokeAst.Member -and $InvokeAst.Member.Extent) {
        return [string]$InvokeAst.Member.Extent.Text
    }

    return $null
}

function Test-MandatoryBase64CommandAst {
    param([System.Management.Automation.Language.CommandAst]$CommandAst)

    if ($null -eq $CommandAst) {
        return $false
    }

    $cmdName = Convert-DynamicCommandCandidateToName -Value $CommandAst.GetCommandName()
    if (-not (Test-PowerShellHostCommandName -CommandName $cmdName)) {
        return $false
    }

    foreach ($elem in @($CommandAst.CommandElements)) {
        if ($elem -isnot [System.Management.Automation.Language.CommandParameterAst]) {
            continue
        }

        $paramInfo = Resolve-PowerShellHostLooseParameterInfo -ParameterName ([string]$elem.ParameterName)
        if ($paramInfo -and [string]$paramInfo.DynamicType -eq 'EncodedCommand') {
            return $true
        }
    }

    return $false
}

function Test-MandatoryBase64ExpressionAst {
    param($Ast)

    if ($null -eq $Ast -or -not ($Ast -is [System.Management.Automation.Language.ExpressionAst])) {
        return $false
    }
    if (-not $Ast.Extent) {
        return $false
    }

    $extentText = [string]$Ast.Extent.Text
    if (-not (Test-MandatoryBase64ConsumerText -Text $extentText)) {
        return $false
    }

    $base64Invoke = @($Ast.FindAll({
                param($n)
                if ($n -isnot [System.Management.Automation.Language.InvokeMemberExpressionAst]) {
                    return $false
                }

                $memberName = Get-InvokeMemberNameText -InvokeAst $n
                return ($memberName -match '^(?i:FromBase64String|FromBase64CharArray)$')
            }, $true))

    return ($base64Invoke.Count -gt 0)
}

function Resolve-DirectBase64BytesFromAst {
    param(
        $Ast,
        [Parameter(Mandatory)][hashtable]$Context
    )

    if ($null -eq $Ast) {
        return $null
    }

    if ($Ast -is [System.Management.Automation.Language.ParenExpressionAst]) {
        $innerAst = Get-StaticExpressionFromPipelineAst -PipelineAst $Ast.Pipeline
        if ($innerAst) {
            return (Resolve-DirectBase64BytesFromAst -Ast $innerAst -Context $Context)
        }
    }

    if ($Ast -isnot [System.Management.Automation.Language.InvokeMemberExpressionAst]) {
        return $null
    }

    $memberName = Get-InvokeMemberNameText -InvokeAst $Ast
    if ([string]::IsNullOrWhiteSpace($memberName)) {
        return $null
    }

    if ($memberName -match '^(?i:FromBase64String)$') {
        $base64Text = $null
        if ($Ast.Arguments -and $Ast.Arguments.Count -gt 0) {
            $base64Text = Try-GetStaticStringValue -Ast $Ast.Arguments[0] -Context $Context
        }

        if ([string]::IsNullOrWhiteSpace($base64Text)) {
            return $null
        }

        return (Try-DecodeBase64ToByteArray -Base64String $base64Text)
    }

    if ($memberName -match '^(?i:FromBase64CharArray)$') {
        if (-not $Ast.Arguments -or $Ast.Arguments.Count -lt 1) {
            return $null
        }

        $sourceResolved = Resolve-StaticAstValue -Ast $Ast.Arguments[0] -Context $Context -AllowEmptyFallback:$false
        if (-not $sourceResolved -or -not $sourceResolved.Success) {
            return $null
        }

        $startIndex = 0
        $length = -1
        if ($Ast.Arguments.Count -ge 3) {
            $startResolved = Resolve-StaticAstValue -Ast $Ast.Arguments[1] -Context $Context -AllowEmptyFallback:$false
            $lengthResolved = Resolve-StaticAstValue -Ast $Ast.Arguments[2] -Context $Context -AllowEmptyFallback:$false
            if (-not $startResolved.Success -or -not $lengthResolved.Success) {
                return $null
            }

            try {
                $startIndex = [int]$startResolved.Value
                $length = [int]$lengthResolved.Value
            } catch {
                return $null
            }
        }

        return (Try-DecodeBase64CharArrayToByteArray -Value $sourceResolved.Value -StartIndex $startIndex -Length $length)
    }

    return $null
}

function Resolve-DirectBase64TextFromAst {
    param(
        $Ast,
        [Parameter(Mandatory)][hashtable]$Context
    )

    if ($null -eq $Ast) {
        return $null
    }

    if ($Ast -is [System.Management.Automation.Language.ParenExpressionAst]) {
        $innerAst = Get-StaticExpressionFromPipelineAst -PipelineAst $Ast.Pipeline
        if ($innerAst) {
            return (Resolve-DirectBase64TextFromAst -Ast $innerAst -Context $Context)
        }
    }

    if ($Ast -isnot [System.Management.Automation.Language.InvokeMemberExpressionAst]) {
        return $null
    }

    $memberName = Get-InvokeMemberNameText -InvokeAst $Ast
    if ([string]::IsNullOrWhiteSpace($memberName)) {
        return $null
    }

    if ($memberName -match '^(?i:GetString)$') {
        if (-not $Ast.Arguments -or $Ast.Arguments.Count -lt 1) {
            return $null
        }

        $bytes = Resolve-DirectBase64BytesFromAst -Ast $Ast.Arguments[0] -Context $Context
        if (-not $bytes -or $bytes.Length -eq 0) {
            return $null
        }

        $encodingResolved = Resolve-StaticAstValue -Ast $Ast.Expression -Context $Context -AllowEmptyFallback:$false
        if ($encodingResolved -and $encodingResolved.Success) {
            $encodingValue = $encodingResolved.Value
            if ($encodingValue -is [psobject] -and $null -ne $encodingValue.BaseObject -and $encodingValue.BaseObject -ne $encodingValue) {
                $encodingValue = $encodingValue.BaseObject
            }

            if ($encodingValue -is [System.Text.Encoding]) {
                try {
                    return $encodingValue.GetString($bytes)
                } catch {
                }
            }
        }

        return (Convert-ByteArrayToLikelyPlainText -Bytes $bytes)
    }

    if ($memberName -match '^(?i:FromBase64String|FromBase64CharArray)$') {
        $bytes = Resolve-DirectBase64BytesFromAst -Ast $Ast -Context $Context
        if ($bytes -and $bytes.Length -gt 0) {
            return (Convert-ByteArrayToLikelyPlainText -Bytes $bytes)
        }
    }

    return $null
}

function Get-MandatoryBase64ExpressionReplacementText {
    param(
        $Ast,
        [Parameter(Mandatory)][hashtable]$Context
    )

    if (-not (Test-MandatoryBase64ExpressionAst -Ast $Ast)) {
        return $null
    }

    $directText = Resolve-DirectBase64TextFromAst -Ast $Ast -Context $Context
    if (-not [string]::IsNullOrWhiteSpace($directText)) {
        return (Convert-ReplacementTextToExpressionLiteral -Text $directText)
    }

    try {
        $resolved = Resolve-StaticAstValue -Ast $Ast -Context $Context -AllowEmptyFallback:$false
    } catch {
        if (Test-IsCallDepthOverflowException -ErrorObject $_) {
            return $null
        }
        throw
    }

    if (-not $resolved -or -not $resolved.Success) {
        return $null
    }

    $value = $resolved.Value
    if ($value -is [psobject] -and $null -ne $value.BaseObject -and $value.BaseObject -ne $value) {
        $value = $value.BaseObject
    }

    $text = $null
    if ($value -is [string]) {
        $text = [string]$value
    } elseif ($value -is [char]) {
        $text = [string]$value
    } elseif ($value -is [char[]]) {
        $text = -join $value
    }

    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }

    return (Convert-ReplacementTextToExpressionLiteral -Text $text)
}

function Get-MandatoryBase64ReplacementCandidates {
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][string]$ScriptText
    )

    $parse = Get-ScriptParseInfo -ScriptText $ScriptText
    if (-not $parse.IsValid -or -not $parse.Ast) {
        return [PSCustomObject]@{
            Candidates = @()
            Skipped    = @()
        }
    }

    $candidates = @()
    $skipped = @()

    $null = Reset-StaticEvalState -Context $Context -TimeBudgetMs 0
    $state = Get-StaticEvalState -Context $Context
    if ($state) {
        $state.ValueDepthLimit = 96
        $state.StringCompatDepthLimit = 72
    }

    $commandAsts = @($parse.Ast.FindAll({
                param($n)
                $n -is [System.Management.Automation.Language.CommandAst] -and (Test-MandatoryBase64CommandAst -CommandAst $n)
            }, $true))

    foreach ($cmdAst in $commandAsts) {
        if ($null -eq $cmdAst -or -not $cmdAst.Extent) { continue }

        $start = [int]$cmdAst.Extent.StartOffset
        $end = [int]$cmdAst.Extent.EndOffset
        $baseItem = [PSCustomObject]@{
            StartOffset = $start
            EndOffset   = $end
            Type        = 'MandatoryBase64'
            Depth       = $null
            NodeId      = $null
        }

        if ($start -lt 0 -or $end -le $start -or $end -gt $ScriptText.Length) {
            $skipped += New-SkipRecord -Reason 'mandatory_base64_out_of_range' -Message 'Mandatory base64 command offset out of range' -Item $baseItem
            continue
        }

        try {
            $decodedInfo = Try-DecodeEncodedCommand -CommandAst $cmdAst
        } catch {
            $decodedInfo = $null
        }
        if (-not $decodedInfo -or [string]::IsNullOrWhiteSpace([string]$decodedInfo.ReplacementText)) {
            $skipped += New-SkipRecord -Reason 'mandatory_base64_decode_failed' -Message 'EncodedCommand mandatory decode failed' -Item $baseItem
            continue
        }

        $replacement = [string]$decodedInfo.ReplacementText
        $original = $ScriptText.Substring($start, $end - $start)
        if ($replacement -eq $original) {
            $skipped += New-SkipRecord -Reason 'mandatory_base64_no_change' -Message 'EncodedCommand mandatory decode produced no change' -Item $baseItem
            continue
        }

        $candidates += [PSCustomObject]@{
            StartOffset        = $start
            EndOffset          = $end
            Replacement        = $replacement
            Original           = $original
            Type               = 'MandatoryBase64'
            Depth              = $null
            NodeId             = $null
            SourceKind         = 'MandatoryBase64'
            Confidence         = 'High'
            UsedEmptyFallback  = $false
            ResultType         = 'EncodedCommandDecoded'
            Executed           = $false
            VariableName       = $null
            IsSimpleVariable   = $false
            IsValueChanged     = $false
            ObservedValueCount = 1
        }
    }

    $exprAsts = @($parse.Ast.FindAll({
                param($n)
                $n -is [System.Management.Automation.Language.ExpressionAst] -and (Test-MandatoryBase64ExpressionAst -Ast $n)
            }, $true) | Sort-Object { $_.Extent.StartOffset }, { -($_.Extent.EndOffset - $_.Extent.StartOffset) })

    foreach ($exprAst in $exprAsts) {
        if ($null -eq $exprAst -or -not $exprAst.Extent) { continue }

        $start = [int]$exprAst.Extent.StartOffset
        $end = [int]$exprAst.Extent.EndOffset
        $baseItem = [PSCustomObject]@{
            StartOffset = $start
            EndOffset   = $end
            Type        = 'MandatoryBase64'
            Depth       = $null
            NodeId      = $null
        }

        if ($start -lt 0 -or $end -le $start -or $end -gt $ScriptText.Length) {
            $skipped += New-SkipRecord -Reason 'mandatory_base64_out_of_range' -Message 'Mandatory base64 expression offset out of range' -Item $baseItem
            continue
        }

        try {
            $replacement = Get-MandatoryBase64ExpressionReplacementText -Ast $exprAst -Context $Context
        } catch {
            if (Test-IsCallDepthOverflowException -ErrorObject $_) {
                $replacement = $null
            } else {
                throw
            }
        }

        if ([string]::IsNullOrWhiteSpace($replacement)) {
            $skipped += New-SkipRecord -Reason 'mandatory_base64_non_text' -Message 'Mandatory base64 expression did not resolve to inline text' -Item $baseItem
            continue
        }

        $original = $ScriptText.Substring($start, $end - $start)
        if ($replacement -eq $original) {
            $skipped += New-SkipRecord -Reason 'mandatory_base64_no_change' -Message 'Mandatory base64 expression produced no change' -Item $baseItem
            continue
        }

        $candidates += [PSCustomObject]@{
            StartOffset        = $start
            EndOffset          = $end
            Replacement        = $replacement
            Original           = $original
            Type               = 'MandatoryBase64'
            Depth              = $null
            NodeId             = $null
            SourceKind         = 'MandatoryBase64'
            Confidence         = 'High'
            UsedEmptyFallback  = $false
            ResultType         = 'MandatoryBase64Text'
            Executed           = $false
            VariableName       = $null
            IsSimpleVariable   = $false
            IsValueChanged     = $false
            ObservedValueCount = 1
        }
    }

    $merged = Merge-ReplacementCandidatesByRange -Candidates $candidates
    return [PSCustomObject]@{
        Candidates = @($merged.Candidates)
        Skipped    = @($skipped) + @($merged.Skipped)
    }
}

function Merge-DynamicInvokeReplacementCandidates {
    param(
        [array]$Candidates,
        [string]$ScriptText,
        [ValidateSet('skip', 'prefer')]
        [string]$DynamicConflictPolicy = 'skip'
    )

    if (-not $Candidates -or $Candidates.Count -eq 0) {
        return [PSCustomObject]@{ Candidates = @(); Skipped = @() }
    }

    $map = @{}
    $conflictRanges = @{}
    $skipped = @()
    foreach ($cand in @($Candidates | Sort-Object StartOffset, EndOffset, DynamicRecordIndex)) {
        if (-not $cand) { continue }

        $key = Get-ReplacementRangeKey -StartOffset $cand.StartOffset -EndOffset $cand.EndOffset
        if ([string]::IsNullOrWhiteSpace($key)) { continue }

        if ($conflictRanges.ContainsKey($key)) {
            $skipped += New-SkipRecord -Reason 'dynamic_same_range_conflict' -Message '同区间 DynamicInvoke 产生不同结果，保守跳过该区间' -Item $cand
            continue
        }

        if (-not $map.ContainsKey($key)) {
            $map[$key] = $cand
            continue
        }

        $existing = $map[$key]
        if ([string]$existing.Replacement -ne [string]$cand.Replacement -and $DynamicConflictPolicy -eq 'skip') {
            $map.Remove($key)
            $conflictRanges[$key] = $true
            $message = '同区间 DynamicInvoke 产生不同结果，保守跳过该区间'
            $skipped += New-SkipRecord -Reason 'dynamic_same_range_conflict' -Message $message -Item $existing
            $skipped += New-SkipRecord -Reason 'dynamic_same_range_conflict' -Message $message -Item $cand
            continue
        }

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

function Filter-ScriptBlockInvocationCandidatesForUpdatedBlocks {
    param([array]$Candidates)

    if (-not $Candidates -or $Candidates.Count -eq 0) {
        return [PSCustomObject]@{
            Candidates = @()
            Skipped    = @()
        }
    }

    $blockInvocationCandidates = @($Candidates | Where-Object { $_ -and [string]$_.SourceKind -eq 'ScriptBlockInvocation' })
    if ($blockInvocationCandidates.Count -eq 0) {
        return [PSCustomObject]@{
            Candidates = @($Candidates)
            Skipped    = @()
        }
    }

    $kept = @()
    $skipped = @()
    foreach ($cand in @($Candidates)) {
        if (-not $cand) { continue }
        if ([string]$cand.SourceKind -ne 'ScriptBlockInvocation') {
            $kept += $cand
            continue
        }

        $recBlockStart = if ($cand.PSObject.Properties['BlockStartOffset']) { $cand.BlockStartOffset } else { $null }
        $recBlockEnd = if ($cand.PSObject.Properties['BlockEndOffset']) { $cand.BlockEndOffset } else { $null }
        if ($null -eq $recBlockStart -or $null -eq $recBlockEnd) {
            $kept += $cand
            continue
        }

        $blockStart = [int]$recBlockStart
        $blockEnd = [int]$recBlockEnd
        $updatesBlock = @($Candidates | Where-Object {
                $_ -and $_ -ne $cand -and
                [string]$_.SourceKind -ne 'ScriptBlockInvocation' -and
                [int]$_.StartOffset -ge $blockStart -and
                [int]$_.EndOffset -le $blockEnd
            }).Count -gt 0

        if ($updatesBlock) {
            $skipped += New-SkipRecord -Reason 'scriptblock_invocation_wait_updated_block' -Message '脚本块正文同轮被改写，调用点延后一轮内联' -Item $cand
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
        [int]$TimeBudgetMs = 0,
        [ValidateSet('Disabled', 'Conservative', 'Balanced', 'Aggressive')]
        [string]$PreExecutionGateMode = 'Disabled',
        [hashtable]$PreExecutionGateCache = $null,
        [bool]$SafeMode = $true
    )

    $candidates = @()
    $skipped = @()
    $nodes = @()
    $budgetExceeded = $false
    if ($Context -and $Context.CFG -and $Context.CFG.Nodes) {
        $nodes = @($Context.CFG.Nodes | Sort-Object Id)
    }
    $typedScalarRanges = Get-TypedScalarExpressionRanges -ScriptText $ScriptText
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

        if (Test-RuntimeGeneratedNode -Node $node) {
            foreach ($r in @($node.Resolvables)) {
                if (-not $r) { continue }
                $skipped += New-SkipRecord -Reason 'static_runtime_generated' -Message '运行时生成节点不参与原始脚本静态回填' -Item ([PSCustomObject]@{
                    StartOffset = $r.StartOffset
                    EndOffset = $r.EndOffset
                    Type = $r.Type
                    Depth = $r.Depth
                    NodeId = $nodeId
                })
            }
            continue
        }

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
            if (Test-AstContainsPipelineAutomaticVariable -Ast $r.Ast) {
                $skipped += New-SkipRecord -Reason 'pipeline_static_expression_protected' -Message '包含 $_/$PSItem 的表达式不做静态回填，避免把 pipeline 上下文变量折叠为空值或残留值' -Item $baseItem
                continue
            }

            $exprGateText = if ($r.Ast -and $r.Ast.Extent) { [string]$r.Ast.Extent.Text } else { $null }
            if (-not [string]::IsNullOrWhiteSpace($exprGateText)) {
                $exprGate = Get-PreExecutionGateDecision -Scope 'StaticExpr' -ScriptText $exprGateText -Mode $PreExecutionGateMode -SafeMode:$SafeMode -Cache $PreExecutionGateCache
                if ([string]$exprGate.Decision -eq 'Stop') {
                    $skipped += New-SkipRecord -Reason 'static_pre_execution_gate' -Message ('静态候选命中先审后执行门控: ' + ((@($exprGate.Reasons) -join ', '))) -Item $baseItem
                    continue
                }
            }

            try {
                $decodedScriptText = Try-DecodeStaticScriptTextFromAst -Ast $r.Ast -Context $Context
                if (-not [string]::IsNullOrWhiteSpace($decodedScriptText)) {
                    $replacement = $decodedScriptText
                    $original = $ScriptText.Substring($start, $end - $start)
                    if ((Test-TypedScalarExpressionText -Text $original) -or
                        (Test-ReplacementWithinRanges -StartOffset ([int]$start) -EndOffset ([int]$end) -Ranges $typedScalarRanges)) {
                        $skipped += New-SkipRecord -Reason 'static_already_typed_scalar' -Message '原片段已经是 typed scalar，跳过静态脚本文本解码' -Item $baseItem
                        continue
                    }
                    if ($original -eq $replacement) {
                        $skipped += New-SkipRecord -Reason 'static_no_change' -Message '静态整段解码结果与原片段一致' -Item $baseItem
                        continue
                    }

                    $expandableSafety = Test-ResolvableExpandableStringCandidateSafe -Original $original -Replacement $replacement -Type $r.Type
                    if (-not $expandableSafety.Safe) {
                        $skipped += New-SkipRecord -Reason ('static_' + [string]$expandableSafety.Reason) -Message $expandableSafety.Message -Item $baseItem
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
                    $typedReplacement = Format-TypedScalarResolvableValue $resolved.Value
                    if (-not [string]::IsNullOrWhiteSpace([string]$typedReplacement)) {
                        $replacement = [string]$typedReplacement
                    } else {
                        $replacement = [string](Format-ResolvableValue $resolved.Value)
                    }
                }
                if ($replacement -eq '__BLOCKED_PLACEHOLDER__') {
                    $skipped += New-SkipRecord -Reason 'static_blocked' -Message '静态结果为占位符，跳过' -Item $baseItem
                    continue
                }

                $original = $ScriptText.Substring($start, $end - $start)
                if ((Test-TypedScalarExpressionText -Text $original) -or
                    (Test-ReplacementWithinRanges -StartOffset ([int]$start) -EndOffset ([int]$end) -Ranges $typedScalarRanges)) {
                    $skipped += New-SkipRecord -Reason 'static_already_typed_scalar' -Message '原片段已经是 typed scalar，跳过重复包裹' -Item $baseItem
                    continue
                }
                if ($original -eq $replacement) {
                    $skipped += New-SkipRecord -Reason 'static_no_change' -Message '静态替换无变化' -Item $baseItem
                    continue
                }

                if (Test-PreserveWholeScriptStaticExpressionStructure -ScriptText $ScriptText -StartOffset ([int]$start) -EndOffset ([int]$end)) {
                    $skipped += New-SkipRecord -Reason 'static_preserve_whole_expression' -Message '顶层成员/索引/方法表达式保留结构，跳过整体标量折叠' -Item $baseItem
                    continue
                }

                $expandableSafety = Test-ResolvableExpandableStringCandidateSafe -Original $original -Replacement $replacement -Type $r.Type
                if (-not $expandableSafety.Safe) {
                    $skipped += New-SkipRecord -Reason ('static_' + [string]$expandableSafety.Reason) -Message $expandableSafety.Message -Item $baseItem
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

    $regionMap = @{}          # key -> candidate
    $conflictRegions = @{}    # key -> @{ Replacements = @() }
    $typedScalarRanges = Get-TypedScalarExpressionRanges -ScriptText $ScriptText

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

        if ($replacement -eq '__BLOCKED_PLACEHOLDER__') {
            $skipped += New-SkipRecord -Reason 'blocked' -Message '值为占位符，跳过替换' -Item $baseItem
            continue
        }

        if ($replacement -eq '$null') {
            $skipped += New-SkipRecord -Reason 'null_replacement' -Message 'replacement 为 $null，默认跳过以避免破坏副作用语句' -Item $baseItem
            continue
        }

        $original = $ScriptText.Substring($start, $end - $start)
        if ((Test-TypedScalarExpressionText -Text $original) -or
            (Test-ReplacementWithinRanges -StartOffset ([int]$start) -EndOffset ([int]$end) -Ranges $typedScalarRanges)) {
            $skipped += New-SkipRecord -Reason 'already_typed_scalar' -Message '原片段已经是 typed scalar，跳过重复包裹' -Item $baseItem
            continue
        }
        if ($original -eq $replacement) {
            $skipped += New-SkipRecord -Reason 'no_change' -Message 'replacement 与原片段一致' -Item $baseItem
            continue
        }
        if (Test-PreserveWholeScriptStaticExpressionStructure -ScriptText $ScriptText -StartOffset ([int]$start) -EndOffset ([int]$end)) {
            $skipped += New-SkipRecord -Reason 'preserve_whole_expression' -Message '顶层成员/索引/方法表达式保留结构，跳过整段执行结果回填' -Item $baseItem
            continue
        }
        if (Test-FormattingOnlyEquivalentReplacement -Original $original -Replacement $replacement -Type $type) {
            $skipped += New-SkipRecord -Reason 'formatting_only' -Message 'replacement 仅改变集合包装格式，跳过以避免来回震荡' -Item $baseItem
            continue
        }
        $expandableSafety = Test-ResolvableExpandableStringCandidateSafe -Original $original -Replacement $replacement -Type $type
        if (-not $expandableSafety.Safe) {
            $skipped += New-SkipRecord -Reason $expandableSafety.Reason -Message $expandableSafety.Message -Item $baseItem
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
        $cand = Add-RecordScopeMetadataToCandidate -Candidate $cand -Record $rec

        $key = Get-ScopeAwareReplacementRangeKey -StartOffset $start -EndOffset $end -Record $rec

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
            $skipped += New-SkipRecord -Reason 'duplicate' -Message "同区间重复记录，已去重: [$start-$end]" -Item $cand
            continue
        }

        $conflictRegions[$key] = @{
            Replacements = @($existing.Replacement, $cand.Replacement)
        }
        $null = $regionMap.Remove($key)
        $skipped += New-SkipRecord -Reason 'conflict_same_range' -Message "同区间出现不同 replacement，跳过: [$start-$end]" -Item $existing
        $skipped += New-SkipRecord -Reason 'conflict_same_range' -Message "同区间出现不同 replacement，跳过: [$start-$end]" -Item $cand
    }

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

            if ($type -eq 'Inline') {
                $skipped += New-SkipRecord -Reason 'inline_function_result_replaced_by_specialized_inline' -Message '内联函数返回值不直接回写，改由调用点专用函数体承载' -Item $baseItem
                continue
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

            $rangeKey = "$start`:$end"
            $key = Get-ScopeAwareReplacementRangeKey -StartOffset $start -EndOffset $end -Record $rec
            if ($type -eq 'VarRead' -and $varAccessKindMap.ContainsKey($rangeKey)) {
                $accessKind = [string]$varAccessKindMap[$rangeKey]
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
            if ((Test-TypedScalarExpressionText -Text $original) -or
                (Test-ReplacementWithinRanges -StartOffset ([int]$start) -EndOffset ([int]$end) -Ranges $typedScalarRanges)) {
                $skipped += New-SkipRecord -Reason 'var_already_typed_scalar' -Message '变量读取位于 typed scalar 内部，跳过重复包裹' -Item $baseItem
                continue
            }
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
                VariableName = $varName
                IsSimpleVariable = $true
                IsValueChanged = ($uniqueValues.Count -ne 1)
                ObservedValueCount = [int]$uniqueValues.Count
            }
            $cand = Add-RecordScopeMetadataToCandidate -Candidate $cand -Record $rec

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

function Get-SingleTopLevelExpressionAstFromText {
    param([Parameter(Mandatory)][string]$ScriptText)

    $parse = Get-ScriptParseInfo -ScriptText $ScriptText
    if (-not $parse.IsValid -or -not $parse.Ast) {
        return $null
    }

    $ast = $parse.Ast
    $statements = @()
    if ($ast.BeginBlock -and $ast.BeginBlock.Statements) { $statements += @($ast.BeginBlock.Statements) }
    if ($ast.ProcessBlock -and $ast.ProcessBlock.Statements) { $statements += @($ast.ProcessBlock.Statements) }
    if ($ast.EndBlock -and $ast.EndBlock.Statements) { $statements += @($ast.EndBlock.Statements) }

    if ($statements.Count -ne 1) {
        return $null
    }

    return (Get-StaticExpressionFromPipelineAst -PipelineAst $statements[0])
}

function Get-TopLevelScriptStatementsFromText {
    param([Parameter(Mandatory)][string]$ScriptText)

    $parse = Get-ScriptParseInfo -ScriptText $ScriptText
    if (-not $parse.IsValid -or -not $parse.Ast) {
        return @()
    }

    $ast = $parse.Ast
    $statements = @()
    if ($ast.BeginBlock -and $ast.BeginBlock.Statements) { $statements += @($ast.BeginBlock.Statements) }
    if ($ast.ProcessBlock -and $ast.ProcessBlock.Statements) { $statements += @($ast.ProcessBlock.Statements) }
    if ($ast.EndBlock -and $ast.EndBlock.Statements) { $statements += @($ast.EndBlock.Statements) }

    return @($statements)
}

function New-WholeScriptStaticResolutionContext {
    $ctx = @{
        CFG = @{ DefinedAliases = @{} }
        FunctionSubgraphs = @{}
        ScriptBlockSubgraphs = @{}
        ExecContext = $null
        PureHelperFunctions = @{}
        ScriptPath = if (-not [string]::IsNullOrWhiteSpace([string]$script:__psdissect_current_input_path)) { [string]$script:__psdissect_current_input_path } else { $null }
        PathContext = $null
        ArtifactStore = @{
            Files    = @{}
            Registry = @{}
        }
        ArtifactEvents = @()
    }

    try {
        $ctx.ExecContext = New-ExecutionContext
    } catch {
        $ctx.ExecContext = $null
    }
    Initialize-WholeScriptSpecialVariables -ExecContext $ctx.ExecContext -Context $ctx

    return $ctx
}

function Get-WholeScriptStaticPureHelperFunctionMap {
    param([hashtable]$Context)

    if ($null -eq $Context) {
        return $null
    }
    if (-not $Context.ContainsKey('PureHelperFunctions') -or $null -eq $Context.PureHelperFunctions) {
        $Context.PureHelperFunctions = @{}
    }

    return $Context.PureHelperFunctions
}

function Close-WholeScriptStaticResolutionContext {
    param([hashtable]$Context)

    if ($Context -and $Context.ExecContext) {
        try {
            Close-ExecutionContext -ExecContext $Context.ExecContext
        } catch {
        }
    }
}

function Get-WholeScriptStaticArtifactStore {
    param([hashtable]$Context)

    if ($null -eq $Context) { return $null }

    if (-not $Context.ContainsKey('ArtifactStore') -or $null -eq $Context.ArtifactStore) {
        $Context.ArtifactStore = @{
            Files    = @{}
            Registry = @{}
        }
    }
    if (-not $Context.ContainsKey('ArtifactEvents') -or $null -eq $Context.ArtifactEvents) {
        $Context.ArtifactEvents = @()
    }

    if (-not $Context.ArtifactStore.ContainsKey('Files') -or $null -eq $Context.ArtifactStore.Files) {
        $Context.ArtifactStore.Files = @{}
    }
    if (-not $Context.ArtifactStore.ContainsKey('Registry') -or $null -eq $Context.ArtifactStore.Registry) {
        $Context.ArtifactStore.Registry = @{}
    }

    return $Context.ArtifactStore
}

function Add-WholeScriptStaticArtifactEvent {
    param(
        [hashtable]$Context,
        [string]$Action,
        [string]$Path,
        [string]$Kind,
        [string]$Detail = $null
    )

    if ($null -eq $Context) { return }
    if (-not $Context.ContainsKey('ArtifactEvents') -or $null -eq $Context.ArtifactEvents) {
        $Context.ArtifactEvents = @()
    }

    $Context.ArtifactEvents += [PSCustomObject]@{
        Timestamp = (Get-Date).ToString('o')
        Action    = $Action
        Path      = $Path
        Kind      = $Kind
        Detail    = $Detail
    }
}

function Test-WholeScriptStaticRegistryPath {
    param([AllowNull()][string]$PathText)

    if ([string]::IsNullOrWhiteSpace($PathText)) {
        return $false
    }

    return ([string]$PathText).Trim() -match '^(?i:(?:registry::)?(?:hkcu|hklm|hkcr|hku|hkcc):\\|hkey_(?:current_user|local_machine|classes_root|users|current_config)\\)'
}

function Get-WholeScriptStaticPathContext {
    param([hashtable]$Context)

    if ($Context -and $Context.ContainsKey('PathContext') -and $null -ne $Context.PathContext) {
        return $Context.PathContext
    }

    $pathContext = @{
        CurrentDirectory = $null
        CurrentDriveRoot = $null
        ScriptPath       = $null
        ScriptDirectory  = $null
        EnvironmentPaths = @{}
        TestDriveRoot    = $null
    }

    $normalizePath = {
        param([AllowNull()][string]$Value)

        if ([string]::IsNullOrWhiteSpace($Value)) {
            return $null
        }

        $text = ([string]$Value).Trim() -replace '/', '\'
        try {
            if ($text -notmatch '[*?]') {
                $text = [System.IO.Path]::GetFullPath($text)
            }
        } catch {
        }
        if ($text.Length -gt 3) {
            $text = $text.TrimEnd('\')
        }
        return $text
    }

    $currentDirectory = $null
    try {
        $currentDirectory = (Get-Location).Path
    } catch {
        $currentDirectory = $null
    }
    if ([string]::IsNullOrWhiteSpace($currentDirectory)) {
        try {
            $currentDirectory = [System.Environment]::CurrentDirectory
        } catch {
            $currentDirectory = $null
        }
    }
    $currentDirectory = & $normalizePath $currentDirectory
    $pathContext.CurrentDirectory = $currentDirectory

    if (-not [string]::IsNullOrWhiteSpace($currentDirectory)) {
        try {
            $pathContext.CurrentDriveRoot = [System.IO.Path]::GetPathRoot($currentDirectory)
        } catch {
            $pathContext.CurrentDriveRoot = $null
        }
    }

    $scriptPath = $null
    if ($Context -and $Context.ContainsKey('ScriptPath') -and -not [string]::IsNullOrWhiteSpace([string]$Context.ScriptPath)) {
        $scriptPath = [string]$Context.ScriptPath
    } elseif (-not [string]::IsNullOrWhiteSpace([string]$script:__psdissect_current_input_path)) {
        $scriptPath = [string]$script:__psdissect_current_input_path
    }
    $scriptPath = & $normalizePath $scriptPath
    $pathContext.ScriptPath = $scriptPath

    $scriptDirectory = $null
    if (-not [string]::IsNullOrWhiteSpace($scriptPath)) {
        try {
            $scriptDirectory = [System.IO.Path]::GetDirectoryName($scriptPath)
        } catch {
            $scriptDirectory = $null
        }
    }
    if ([string]::IsNullOrWhiteSpace($scriptDirectory)) {
        $scriptDirectory = $currentDirectory
    }
    $pathContext.ScriptDirectory = (& $normalizePath $scriptDirectory)

    $envMap = @{}
    $addEnv = {
        param([string]$Name, [AllowNull()][string]$Value)

        if ([string]::IsNullOrWhiteSpace($Name) -or [string]::IsNullOrWhiteSpace($Value)) {
            return
        }

        $envMap[$Name.ToUpperInvariant()] = (& $normalizePath $Value)
    }

    $getFolder = {
        param([System.Environment+SpecialFolder]$Folder)
        try {
            return [System.Environment]::GetFolderPath($Folder)
        } catch {
            return $null
        }
    }

    $userProfile = if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) { $env:USERPROFILE } else { & $getFolder ([System.Environment+SpecialFolder]::UserProfile) }
    $windir = if (-not [string]::IsNullOrWhiteSpace($env:WINDIR)) { $env:WINDIR } elseif (-not [string]::IsNullOrWhiteSpace($env:SystemRoot)) { $env:SystemRoot } else { 'C:\Windows' }
    $public = if (-not [string]::IsNullOrWhiteSpace($env:PUBLIC)) {
        $env:PUBLIC
    } elseif (-not [string]::IsNullOrWhiteSpace($userProfile)) {
        try { [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($userProfile), 'Public') } catch { $null }
    } else {
        $null
    }
    $downloads = if (-not [string]::IsNullOrWhiteSpace($userProfile)) {
        try { [System.IO.Path]::Combine($userProfile, 'Downloads') } catch { $null }
    } else {
        $null
    }

    & $addEnv 'TEMP' $env:TEMP
    & $addEnv 'TMP' $env:TMP
    & $addEnv 'LOCALAPPDATA' (& $getFolder ([System.Environment+SpecialFolder]::LocalApplicationData))
    & $addEnv 'APPDATA' (& $getFolder ([System.Environment+SpecialFolder]::ApplicationData))
    & $addEnv 'PROGRAMDATA' $(if (-not [string]::IsNullOrWhiteSpace($env:ProgramData)) { $env:ProgramData } else { & $getFolder ([System.Environment+SpecialFolder]::CommonApplicationData) })
    & $addEnv 'PUBLIC' $public
    & $addEnv 'WINDIR' $windir
    & $addEnv 'SYSTEMROOT' $windir
    & $addEnv 'USERPROFILE' $userProfile
    & $addEnv 'DESKTOP' (& $getFolder ([System.Environment+SpecialFolder]::Desktop))
    & $addEnv 'DOCUMENTS' (& $getFolder ([System.Environment+SpecialFolder]::MyDocuments))
    & $addEnv 'STARTUP' (& $getFolder ([System.Environment+SpecialFolder]::Startup))
    & $addEnv 'DOWNLOADS' $downloads
    & $addEnv 'PSSCRIPTROOT' $pathContext.ScriptDirectory

    if ($pathContext.CurrentDirectory) {
        & $addEnv 'PWD' $pathContext.CurrentDirectory
        & $addEnv 'CD' $pathContext.CurrentDirectory
    }

    $testDriveRoot = $null
    $tempRoot = $null
    if ($envMap.ContainsKey('TEMP') -and -not [string]::IsNullOrWhiteSpace([string]$envMap['TEMP'])) {
        $tempRoot = [string]$envMap['TEMP']
    } elseif ($envMap.ContainsKey('TMP') -and -not [string]::IsNullOrWhiteSpace([string]$envMap['TMP'])) {
        $tempRoot = [string]$envMap['TMP']
    } elseif (-not [string]::IsNullOrWhiteSpace([string]$pathContext.CurrentDirectory)) {
        $tempRoot = [string]$pathContext.CurrentDirectory
    }
    if (-not [string]::IsNullOrWhiteSpace($tempRoot)) {
        try {
            $testDriveRoot = [System.IO.Path]::Combine($tempRoot.TrimEnd('\'), 'PSDissect-TestDrive')
        } catch {
            $testDriveRoot = ($tempRoot.TrimEnd('\') + '\PSDissect-TestDrive')
        }
    }
    $pathContext.TestDriveRoot = (& $normalizePath $testDriveRoot)
    $pathContext.EnvironmentPaths = $envMap

    if ($Context) {
        $Context.PathContext = $pathContext
    }

    return $pathContext
}

function Resolve-WholeScriptStaticEnvironmentValueText {
    param(
        [AllowNull()][string]$Name,
        [hashtable]$Context
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $null
    }

    $leafName = ([string]$Name).Trim()
    if ($leafName.StartsWith('$')) {
        $leafName = $leafName.Substring(1)
    }
    if ($leafName -match '^(?i:env:)(.+)$') {
        $leafName = [string]$Matches[1]
    }
    $leafName = $leafName.Trim('%', '{', '}', ' ')
    if ([string]::IsNullOrWhiteSpace($leafName)) {
        return $null
    }

    $pathContext = Get-WholeScriptStaticPathContext -Context $Context
    $lookupName = $leafName.ToUpperInvariant()
    if ($pathContext -and $pathContext.EnvironmentPaths -and $pathContext.EnvironmentPaths.ContainsKey($lookupName)) {
        return [string]$pathContext.EnvironmentPaths[$lookupName]
    }

    foreach ($target in @([System.EnvironmentVariableTarget]::Process, [System.EnvironmentVariableTarget]::User, [System.EnvironmentVariableTarget]::Machine)) {
        try {
            $value = [System.Environment]::GetEnvironmentVariable($leafName, $target)
            if (-not [string]::IsNullOrWhiteSpace([string]$value)) {
                return [string]$value
            }
        } catch {
        }
    }

    return $null
}

function Resolve-WholeScriptStaticDisplayPath {
    param(
        [AllowNull()][string]$PathText,
        [hashtable]$Context
    )

    if ([string]::IsNullOrWhiteSpace($PathText)) {
        return $null
    }

    $candidate = ([string]$PathText).Trim()
    $candidate = $candidate.Trim('"', "'", ' ')
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        return $null
    }

    if (Test-WholeScriptStaticRegistryPath -PathText $candidate) {
        return ((($candidate -replace '(?i)^registry::', '') -replace '/', '\').Trim())
    }

    $candidate = $candidate -replace '/', '\'
    $pathContext = Get-WholeScriptStaticPathContext -Context $Context

    if ($candidate -match '^(?i)\$env:([A-Za-z_][A-Za-z0-9_]*)(?<tail>.*)$') {
        $root = Resolve-WholeScriptStaticEnvironmentValueText -Name ([string]$Matches[1]) -Context $Context
        if (-not [string]::IsNullOrWhiteSpace($root)) {
            $tail = [string]$Matches['tail']
            $candidate = if ([string]::IsNullOrWhiteSpace($tail)) {
                $root
            } else {
                [System.IO.Path]::Combine($root.TrimEnd('\'), $tail.TrimStart('\'))
            }
        }
    } elseif ($candidate -match '^(?i)%([^%]+)%(?<tail>.*)$') {
        $root = Resolve-WholeScriptStaticEnvironmentValueText -Name ([string]$Matches[1]) -Context $Context
        if (-not [string]::IsNullOrWhiteSpace($root)) {
            $tail = [string]$Matches['tail']
            $candidate = if ([string]::IsNullOrWhiteSpace($tail)) {
                $root
            } else {
                [System.IO.Path]::Combine($root.TrimEnd('\'), $tail.TrimStart('\'))
            }
        }
    } elseif ($candidate -match '^~(?<tail>[\\\/].*)?$') {
        $root = Resolve-WholeScriptStaticEnvironmentValueText -Name 'USERPROFILE' -Context $Context
        if (-not [string]::IsNullOrWhiteSpace($root)) {
            $tail = [string]$Matches['tail']
            $candidate = if ([string]::IsNullOrWhiteSpace($tail)) {
                $root
            } else {
                [System.IO.Path]::Combine($root.TrimEnd('\'), $tail.TrimStart('\'))
            }
        }
    } elseif ($candidate -match '^(?:\.\\|\.\.\\)') {
        $basePath = if ($pathContext -and -not [string]::IsNullOrWhiteSpace([string]$pathContext.ScriptDirectory)) {
            [string]$pathContext.ScriptDirectory
        } elseif ($pathContext -and -not [string]::IsNullOrWhiteSpace([string]$pathContext.CurrentDirectory)) {
            [string]$pathContext.CurrentDirectory
        } else {
            $null
        }
        if (-not [string]::IsNullOrWhiteSpace($basePath)) {
            try {
                $candidate = [System.IO.Path]::GetFullPath((Join-Path $basePath $candidate))
            } catch {
            }
        }
    } elseif ($candidate -match '^\\(?!\\)') {
        if ($pathContext -and -not [string]::IsNullOrWhiteSpace([string]$pathContext.CurrentDriveRoot)) {
            try {
                $candidate = [System.IO.Path]::Combine([string]$pathContext.CurrentDriveRoot, $candidate.TrimStart('\'))
            } catch {
            }
        }
    }

    $candidate = $candidate -replace '/', '\'
    if ($candidate.StartsWith('\\')) {
        $prefix = if ($candidate.StartsWith('\\\\')) { '\\' } else { '\' }
        $body = $candidate.Substring($prefix.Length)
        $body = [regex]::Replace($body, '\\{2,}', '\')
        $candidate = $prefix + $body
    } else {
        $candidate = [regex]::Replace($candidate, '\\{2,}', '\')
    }

    if ($candidate -notmatch '[*?]') {
        try {
            if ($candidate -match '^(?:[A-Za-z]:\\|\\\\[^\\]+\\[^\\]+)') {
                $candidate = [System.IO.Path]::GetFullPath($candidate)
            }
        } catch {
        }
    }

    if ($candidate.Length -gt 3) {
        $candidate = $candidate.TrimEnd('\')
    }

    $candidate = Convert-WholeScriptStaticPathToSymbolicRoot -PathText $candidate -Context $Context

    return $candidate
}

function Normalize-WholeScriptStaticArtifactPath {
    param(
        [AllowNull()][string]$PathText,
        [hashtable]$Context
    )

    if ([string]::IsNullOrWhiteSpace($PathText)) {
        return $null
    }

    $trimmed = Resolve-WholeScriptStaticDisplayPath -PathText $PathText -Context $Context
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        return $null
    }

    if (Test-WholeScriptStaticRegistryPath -PathText $trimmed) {
        $normalized = $trimmed -replace '(?i)^registry::', ''
        $normalized = $normalized.Trim()
        return $normalized.ToLowerInvariant()
    }

    $normalizedPath = $trimmed -replace '/', '\'
    if ($normalizedPath.StartsWith('\\')) {
        $prefix = if ($normalizedPath.StartsWith('\\\\')) { '\\' } else { '\' }
        $body = $normalizedPath.Substring($prefix.Length)
        $body = [regex]::Replace($body, '\\{2,}', '\')
        $normalizedPath = $prefix + $body
    } else {
        $normalizedPath = [regex]::Replace($normalizedPath, '\\{2,}', '\')
    }
    if ($normalizedPath.Length -gt 3) {
        $normalizedPath = $normalizedPath.TrimEnd('\')
    }

    return $normalizedPath.ToLowerInvariant()
}

function Get-WholeScriptStaticArtifactPathInfo {
    param(
        [AllowNull()][string]$PathText,
        [hashtable]$Context
    )

    if ([string]::IsNullOrWhiteSpace($PathText)) {
        return $null
    }

    $displayPath = Resolve-WholeScriptStaticDisplayPath -PathText $PathText -Context $Context
    $canonicalPath = Normalize-WholeScriptStaticArtifactPath -PathText $displayPath -Context $Context
    if ([string]::IsNullOrWhiteSpace($canonicalPath)) {
        return $null
    }

    return [PSCustomObject]@{
        DisplayPath   = $displayPath
        CanonicalPath = $canonicalPath
        IsRegistry    = (Test-WholeScriptStaticRegistryPath -PathText $displayPath)
    }
}

function Expand-WholeScriptStaticSymbolicPathText {
    param(
        [AllowNull()][string]$PathText,
        [hashtable]$Context
    )

    if ([string]::IsNullOrWhiteSpace($PathText)) {
        return $null
    }

    $candidate = ([string]$PathText).Trim().Trim('"', "'", ' ')
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        return $null
    }

    if ($candidate -match '^(?i)\$env:([A-Za-z_][A-Za-z0-9_]*)(?<tail>.*)$') {
        $root = Resolve-WholeScriptStaticEnvironmentValueText -Name ([string]$Matches[1]) -Context $Context
        if (-not [string]::IsNullOrWhiteSpace($root)) {
            $tail = [string]$Matches['tail']
            return $(if ([string]::IsNullOrWhiteSpace($tail)) {
                    $root
                } else {
                    try {
                        [System.IO.Path]::Combine($root.TrimEnd('\'), $tail.TrimStart('\'))
                    } catch {
                        $root.TrimEnd('\') + '\' + $tail.TrimStart('\')
                    }
                })
        }
    }

    if ($candidate -match '^(?i)%([^%]+)%(?<tail>.*)$') {
        $root = Resolve-WholeScriptStaticEnvironmentValueText -Name ([string]$Matches[1]) -Context $Context
        if (-not [string]::IsNullOrWhiteSpace($root)) {
            $tail = [string]$Matches['tail']
            return $(if ([string]::IsNullOrWhiteSpace($tail)) {
                    $root
                } else {
                    try {
                        [System.IO.Path]::Combine($root.TrimEnd('\'), $tail.TrimStart('\'))
                    } catch {
                        $root.TrimEnd('\') + '\' + $tail.TrimStart('\')
                    }
                })
        }
    }

    return $candidate
}

function Get-WholeScriptStaticArtifactDisplayVariants {
    param(
        [AllowNull()][string]$PathText,
        [hashtable]$Context
    )

    if ([string]::IsNullOrWhiteSpace($PathText)) {
        return @()
    }

    $variants = New-Object 'System.Collections.Generic.List[string]'
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $addVariant = {
        param([AllowNull()][string]$Value)
        if ([string]::IsNullOrWhiteSpace($Value)) { return }
        $trimmed = ([string]$Value).Trim().Trim('"', "'", ' ')
        if ([string]::IsNullOrWhiteSpace($trimmed)) { return }
        if ($seen.Add($trimmed)) {
            $variants.Add($trimmed) | Out-Null
        }
    }

    $displayPath = Resolve-WholeScriptStaticDisplayPath -PathText $PathText -Context $Context
    & $addVariant $displayPath

    $expandedPath = Expand-WholeScriptStaticSymbolicPathText -PathText $displayPath -Context $Context
    if (-not [string]::IsNullOrWhiteSpace($expandedPath)) {
        $expandedPath = Resolve-WholeScriptStaticDisplayPath -PathText $expandedPath -Context $Context
        $expandedPath = Expand-WholeScriptStaticSymbolicPathText -PathText $expandedPath -Context $Context
        & $addVariant $expandedPath
        & $addVariant (Convert-WholeScriptStaticPathToSymbolicRoot -PathText $expandedPath -Context $Context)
    }

    return @($variants.ToArray())
}

function Add-WholeScriptStaticArtifactDisplayVariants {
    param(
        [Parameter(Mandatory)]$Record,
        [string[]]$Variants = @()
    )

    if ($null -eq $Record) {
        return
    }

    if ($null -eq $Record.DisplayVariants) {
        $Record.DisplayVariants = @()
    }

    $merged = New-Object 'System.Collections.Generic.List[string]'
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($existing in @($Record.DisplayVariants) + @($Variants)) {
        if ([string]::IsNullOrWhiteSpace([string]$existing)) { continue }
        $trimmed = ([string]$existing).Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
        if ($seen.Add($trimmed)) {
            $merged.Add($trimmed) | Out-Null
        }
    }

    $Record.DisplayVariants = @($merged.ToArray())
}

function Add-WholeScriptStaticArtifactReferencedPath {
    param(
        [Parameter(Mandatory)]$Record,
        [AllowNull()][string]$PathText,
        [hashtable]$Context
    )

    if ($null -eq $Record -or [string]::IsNullOrWhiteSpace($PathText)) {
        return
    }

    if ($null -eq $Record.ReferencedPaths) {
        $Record.ReferencedPaths = @()
    }

    $variants = Get-WholeScriptStaticArtifactDisplayVariants -PathText $PathText -Context $Context
    $merged = New-Object 'System.Collections.Generic.List[string]'
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($existing in @($Record.ReferencedPaths) + @($variants)) {
        if ([string]::IsNullOrWhiteSpace([string]$existing)) { continue }
        $trimmed = ([string]$existing).Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
        if ($seen.Add($trimmed)) {
            $merged.Add($trimmed) | Out-Null
        }
    }

    $Record.ReferencedPaths = @($merged.ToArray())
}

function Convert-WholeScriptStaticScalarToText {
    param($Value)

    if ($Value -is [System.Management.Automation.PathInfo]) {
        return [string]$Value.Path
    }

    if ($Value -is [psobject] -and $null -ne $Value.BaseObject -and $Value.BaseObject -ne $Value) {
        if (Test-StaticPropertyBagValue -Value $Value) {
            $typeProperty = @($Value.PSObject.Properties.Match('__PsDissectType') | Select-Object -First 1)
            if ($typeProperty.Count -gt 0 -and [string]$typeProperty[0].Value -eq 'PathInfo') {
                $pathProperty = @($Value.PSObject.Properties.Match('Path') | Select-Object -First 1)
                if ($pathProperty.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$pathProperty[0].Value)) {
                    return [string]$pathProperty[0].Value
                }
            }
        }
        $Value = $Value.BaseObject
    }

    if ($null -eq $Value) { return '' }
    if ($Value -is [char[]]) { return (-join $Value) }
    if ($Value -is [char]) { return [string]$Value }

    try {
        return [string]$Value
    } catch {
        return $null
    }
}

function Test-WholeScriptStaticPathLikeText {
    param([AllowNull()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $false
    }

    $candidate = ([string]$Text).Trim().Trim('"', "'", ' ')
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        return $false
    }

    if (Test-WholeScriptStaticRegistryPath -PathText $candidate) {
        return $true
    }

    if ($candidate -match '^(?i:(?:[A-Z]:\\|\\\\[^\\]+\\[^\\]+|%[A-Z0-9_]+%\\|~\\|\.{1,2}\\|\\))') {
        return $true
    }

    if ($candidate -match '(?i)(?:\\|/)[^\\/\r\n]+\.(ps1|psm1|psd1|dll|exe|cmd|bat|vbs|js)\b') {
        return $true
    }

    return ($candidate -match '(?i)PSDissect-TestDrive')
}

function Test-WholeScriptStaticPathRewriteTriggerText {
    param([AllowNull()][string]$ScriptText)

    if ([string]::IsNullOrWhiteSpace($ScriptText)) {
        return $false
    }

    return ([string]$ScriptText -match '(?i)\bJoin-Path\b|\bGet-Random\b|\$TestDrive\b|\$PSScriptRoot\b|\$PSCommandPath\b|\.ps(?:1|m1|d1)\b|\b(?:Import-Module|Out-File|Set-Content|Add-Content|New-Item)\b')
}

function Test-WholeScriptStaticPathRewriteTargetAst {
    param($Ast)

    if ($null -eq $Ast -or -not $Ast.Extent) {
        return $false
    }

    $text = [string]$Ast.Extent.Text
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $false
    }
    if ($text.Length -gt 4096) {
        return $false
    }

    if ($Ast -is [System.Management.Automation.Language.VariableExpressionAst]) {
        return $true
    }

    return ($text -match '(?i)\bJoin-Path\b|\bGet-Random\b|\$TestDrive\b|\$PSScriptRoot\b|\$PSCommandPath\b|\$env:|\$\(|\$[A-Za-z_][\w:]*|\.ps(?:1|m1|d1)\b')
}

function Get-WholeScriptDirectExecutableStatements {
    param([Parameter(Mandatory)][System.Management.Automation.Language.ScriptBlockAst]$Ast)

    $statements = New-Object 'System.Collections.Generic.List[object]'
    $seen = @{}

    $addStatement = {
        param($Statement)

        if ($null -eq $Statement -or -not $Statement.Extent) {
            return
        }

        if (($Statement -isnot [System.Management.Automation.Language.AssignmentStatementAst]) -and
            ($Statement -isnot [System.Management.Automation.Language.PipelineAst]) -and
            ($Statement -isnot [System.Management.Automation.Language.CommandAst])) {
            return
        }

        if (($Statement -is [System.Management.Automation.Language.PipelineAst]) -or
            ($Statement -is [System.Management.Automation.Language.CommandAst])) {
            $nestedScriptBlocks = @($Statement.FindAll({
                        param($n)
                        $n -is [System.Management.Automation.Language.ScriptBlockExpressionAst]
                    }, $true))
            if ($nestedScriptBlocks.Count -gt 0) {
                return
            }
        }

        $key = Get-ReplacementRangeKey -StartOffset ([int]$Statement.Extent.StartOffset) -EndOffset ([int]$Statement.Extent.EndOffset)
        if ([string]::IsNullOrWhiteSpace($key) -or $seen.ContainsKey($key)) {
            return
        }

        $seen[$key] = $true
        $statements.Add($Statement) | Out-Null
    }

    $candidateStatements = @($Ast.FindAll({
                param($n)
                if ($null -eq $n) {
                    return $false
                }

                if ($n -is [System.Management.Automation.Language.AssignmentStatementAst]) {
                    return $true
                }

                if ($n -is [System.Management.Automation.Language.PipelineAst]) {
                    return $true
                }

                return ($n -is [System.Management.Automation.Language.CommandAst] -and
                    ($n.Parent -isnot [System.Management.Automation.Language.PipelineAst]))
            }, $true))
    foreach ($statement in @($candidateStatements)) {
        & $addStatement $statement
    }

    return @($statements.ToArray() | Sort-Object { $_.Extent.StartOffset }, { $_.Extent.EndOffset })
}

function Get-WholeScriptStaticPathRewriteResolvedText {
    param(
        $Ast,
        [Parameter(Mandatory)][hashtable]$Context,
        [int]$MaxResolvedTextLength = 2048
    )

    if ($null -eq $Ast) {
        return $null
    }

    $pathText = $null
    try {
        $pathText = Resolve-WholeScriptStaticArtifactPathTextFromAst -Ast $Ast -Context $Context
    } catch {
        if (-not (Test-IsCallDepthOverflowException -ErrorObject $_)) {
            throw
        }
        $pathText = $null
    }

    if (Test-WholeScriptStaticPathLikeText -Text $pathText) {
        if ($MaxResolvedTextLength -le 0 -or ([string]$pathText).Length -le $MaxResolvedTextLength) {
            return [string]$pathText
        }
    }

    try {
        $resolved = Resolve-StaticAstValue -Ast $Ast -Context $Context -AllowEmptyFallback:$false
    } catch {
        if (-not (Test-IsCallDepthOverflowException -ErrorObject $_)) {
            throw
        }
        return $null
    }

    if (-not $resolved -or -not $resolved.Success) {
        return $null
    }

    $resolvedText = Convert-FastSensitiveResolvedValueToText -Value $resolved.Value -Context $Context -SinkKind 'FilePath' -MaxResolvedTextLength $MaxResolvedTextLength
    if (-not (Test-WholeScriptStaticPathLikeText -Text $resolvedText)) {
        return $null
    }

    return [string]$resolvedText
}

function Get-WholeScriptStaticPathRewriteCandidates {
    param([Parameter(Mandatory)][string]$ScriptText)

    if (-not (Test-WholeScriptStaticPathRewriteTriggerText -ScriptText $ScriptText)) {
        return [PSCustomObject]@{
            Candidates = @()
            Skipped    = @()
        }
    }

    $parse = Get-ScriptParseInfo -ScriptText $ScriptText
    if (-not $parse.IsValid -or -not $parse.Ast) {
        return [PSCustomObject]@{
            Candidates = @()
            Skipped    = @()
        }
    }

    $ctx = New-WholeScriptStaticResolutionContext
    try {
        $candidates = @()
        $state = Get-StaticEvalState -Context $ctx
        if ($state) {
            $state.ValueDepthLimit = 64
            $state.StringCompatDepthLimit = 48
        }
        $ctx.SafeMode = $true

        $seenRanges = @{}
        $directStatements = @(Get-WholeScriptDirectExecutableStatements -Ast $parse.Ast)
        foreach ($statement in @($directStatements)) {
            $statementCandidates = New-Object 'System.Collections.Generic.List[object]'
            $statementSeenRanges = @{}
            $addCandidateAst = {
                param($CandidateAst)

                if ($null -eq $CandidateAst -or -not $CandidateAst.Extent) {
                    return
                }

                $key = Get-ReplacementRangeKey -StartOffset ([int]$CandidateAst.Extent.StartOffset) -EndOffset ([int]$CandidateAst.Extent.EndOffset)
                if ([string]::IsNullOrWhiteSpace($key) -or $statementSeenRanges.ContainsKey($key)) {
                    return
                }

                $statementSeenRanges[$key] = $true
                $statementCandidates.Add($CandidateAst) | Out-Null
            }

            if ($statement -is [System.Management.Automation.Language.AssignmentStatementAst] -and $statement.Right) {
                & $addCandidateAst $statement.Right
            }

            $commandAsts = @($statement.FindAll({
                        param($n)
                        $n -is [System.Management.Automation.Language.CommandAst]
                    }, $true))
            foreach ($commandAst in @($commandAsts)) {
                $binding = Get-StaticCommandArgumentBinding -CommandAst $commandAst
                foreach ($entry in @($binding.Parameters.GetEnumerator())) {
                    if ($entry.Value) {
                        & $addCandidateAst $entry.Value
                    }
                }
                foreach ($positionalAst in @($binding.Positional)) {
                    if ($positionalAst) {
                        & $addCandidateAst $positionalAst
                    }
                }
            }

            foreach ($candidateAst in @($statementCandidates.ToArray() | Sort-Object { $_.Extent.StartOffset }, { -($_.Extent.EndOffset - $_.Extent.StartOffset) })) {
                if (-not (Test-WholeScriptStaticPathRewriteTargetAst -Ast $candidateAst)) {
                    continue
                }

                $start = [int]$candidateAst.Extent.StartOffset
                $end = [int]$candidateAst.Extent.EndOffset
                if ($start -lt 0 -or $end -le $start -or $end -gt $ScriptText.Length) {
                    continue
                }

                $rangeKey = Get-ReplacementRangeKey -StartOffset $start -EndOffset $end
                if ([string]::IsNullOrWhiteSpace($rangeKey) -or $seenRanges.ContainsKey($rangeKey)) {
                    continue
                }

                $original = $ScriptText.Substring($start, $end - $start)
                $resolvedText = Get-WholeScriptStaticPathRewriteResolvedText -Ast $candidateAst -Context $ctx
                if ([string]::IsNullOrWhiteSpace($resolvedText)) {
                    continue
                }

                $replacement = Convert-ReplacementTextToExpressionLiteral -Text $resolvedText
                if ([string]::IsNullOrWhiteSpace($replacement) -or $replacement -eq $original) {
                    continue
                }

                $seenRanges[$rangeKey] = $true
                $candidates += [PSCustomObject]@{
                    StartOffset        = $start
                    EndOffset          = $end
                    Replacement        = $replacement
                    Original           = $original
                    Type               = 'StaticPath'
                    Depth              = $null
                    NodeId             = $null
                    SourceKind         = 'StaticPath'
                    Confidence         = 'High'
                    UsedEmptyFallback  = $false
                    ResultType         = 'PathText'
                    Executed           = $false
                    VariableName       = $null
                    IsSimpleVariable   = $false
                    IsValueChanged     = $false
                    ObservedValueCount = 1
                    ProtectsInnerCandidates = $true
                }
            }

            try {
                [void](Invoke-WholeScriptStaticStatement -Statement $statement -Context $ctx -AllowEmptyFallback:$false)
            } catch {
                if (-not (Test-IsCallDepthOverflowException -ErrorObject $_)) {
                    throw
                }
            }
        }

        return [PSCustomObject]@{
            Candidates = @($candidates)
            Skipped    = @()
        }
    } finally {
        Close-WholeScriptStaticResolutionContext -Context $ctx
    }
}

function Invoke-WholeScriptStaticPathRewritePass {
    param([Parameter(Mandatory)][string]$ScriptText)

    if (-not (Test-WholeScriptStaticPathRewriteTriggerText -ScriptText $ScriptText)) {
        return $ScriptText
    }

    $candidateInfo = Get-WholeScriptStaticPathRewriteCandidates -ScriptText $ScriptText
    $candidates = @($candidateInfo.Candidates)
    if ($candidates.Count -eq 0) {
        return $ScriptText
    }

    $selectedInfo = Select-NonOverlappingReplacements -Candidates $candidates -Strategy 'Outer'
    $selected = @($selectedInfo.Selected)
    if ($selected.Count -eq 0) {
        return $ScriptText
    }

    $syntaxGuard = Ensure-SyntaxSafeReplacements -ScriptText $ScriptText -Selected $selected
    $selected = @($syntaxGuard.Selected)
    if ($selected.Count -eq 0) {
        return $ScriptText
    }

    $rewritten = Apply-ReplacementsToText -Text $ScriptText -Replacements $selected
    $check = Test-PowerShellSyntax -ScriptText $rewritten
    if (-not $check.IsValid) {
        return $ScriptText
    }

    return $rewritten
}

function Invoke-WholeScriptStaticGetContentMaterializationPass {
    param([Parameter(Mandatory)][string]$ScriptText)

    if ([string]::IsNullOrWhiteSpace($ScriptText) -or
        $ScriptText -notmatch '(?i)\b(?:Get-Content|gc)\b') {
        return $ScriptText
    }

    $parse = Get-ScriptParseInfo -ScriptText $ScriptText
    if (-not $parse.IsValid -or -not $parse.Ast) {
        return $ScriptText
    }

    $statements = @(Get-TopLevelScriptStatementsFromText -ScriptText $ScriptText)
    if ($statements.Count -eq 0) {
        return $ScriptText
    }

    $ctx = New-WholeScriptStaticResolutionContext
    try {
        $staticEvalState = Get-StaticEvalState -Context $ctx
        if ($staticEvalState) {
            $staticEvalState.ValueDepthLimit = 64
            $staticEvalState.StringCompatDepthLimit = 48
        }
        $ctx.SafeMode = $true

        [void](Initialize-WholeScriptStaticAssignments -Statements $statements -Context $ctx)

        $replacements = New-Object 'System.Collections.Generic.List[object]'
        foreach ($statement in @($statements)) {
            $commandAst = Get-WholeScriptSingleCommandAst -Ast $statement
            if ($commandAst -and $statement -and $statement.Extent) {
                $commandName = Convert-DynamicCommandCandidateToName -Value $commandAst.GetCommandName()
                if ($commandName -match '^(?i:Get-Content|gc)$') {
                    $binding = Get-StaticCommandArgumentBinding -CommandAst $commandAst
                    $pathAst = $null
                    foreach ($key in @('path', 'literalpath')) {
                        if ($binding.Parameters.ContainsKey($key) -and $binding.Parameters[$key]) {
                            $pathAst = $binding.Parameters[$key]
                            break
                        }
                    }
                    if ($null -eq $pathAst -and $binding.Positional.Count -gt 0) {
                        $pathAst = $binding.Positional[0]
                    }

                    $pathText = Resolve-WholeScriptStaticArtifactPathTextFromAst -Ast $pathAst -Context $ctx
                    if (-not [string]::IsNullOrWhiteSpace($pathText)) {
                        $raw = $binding.Parameters.ContainsKey('raw')
                        $items = Get-WholeScriptStaticFileArtifactOutputItems -Context $ctx -PathText $pathText -Raw:$raw
                        if ($null -ne $items -and @($items).Count -gt 0) {
                            $contentText = Convert-WholeScriptStaticOutputItemsToScriptText -Items @($items)
                            if (-not [string]::IsNullOrWhiteSpace($contentText) -and $contentText.Length -le 32768) {
                                $evidence = @(Get-WholeScriptSensitiveEvidenceFromText -Text $contentText -Source 'artifact_read' -Stage 'whole_script_artifact_read' -Context $ctx)
                                $interestingEvidence = @($evidence | Where-Object { [string]$_.Kind -in @('FilePath', 'Url', 'RegKey') })
                                if ($interestingEvidence.Count -gt 0) {
                                    $materializedLiteral = Convert-ReplacementTextToExpressionLiteral -Text $contentText
                                    $replacement = if (-not [string]::IsNullOrWhiteSpace($materializedLiteral)) {
                                        ([string]$statement.Extent.Text).TrimEnd() + "`r`n" + $materializedLiteral
                                    } else {
                                        $null
                                    }
                                    if (-not [string]::IsNullOrWhiteSpace($replacement)) {
                                        $replacements.Add([PSCustomObject]@{
                                                StartOffset = [int]$statement.Extent.StartOffset
                                                EndOffset   = [int]$statement.Extent.EndOffset
                                                Replacement = [string]$replacement
                                            }) | Out-Null
                                    }
                                }
                            }
                        }
                    }
                }
            }

            try {
                [void](Invoke-WholeScriptStaticStatement -Statement $statement -Context $ctx -AllowEmptyFallback:$false)
            } catch {
                if (-not (Test-IsCallDepthOverflowException -ErrorObject $_)) {
                    throw
                }
            }
        }

        if ($replacements.Count -eq 0) {
            return $ScriptText
        }

        $selectedInfo = Select-NonOverlappingReplacements -Candidates @($replacements.ToArray()) -Strategy 'Outer'
        $selected = @($selectedInfo.Selected)
        if ($selected.Count -eq 0) {
            return $ScriptText
        }

        $rewritten = Apply-ReplacementsToText -Text $ScriptText -Replacements $selected
        $check = Test-PowerShellSyntax -ScriptText $rewritten
        if ($check.IsValid) {
            return $rewritten
        }

        return $ScriptText
    } finally {
        Close-WholeScriptStaticResolutionContext -Context $ctx
    }
}

function Convert-WholeScriptStaticValueToDelimitedText {
    param(
        $Value,
        [string]$Delimiter = "`r`n"
    )

    if ($Value -is [psobject] -and $null -ne $Value.BaseObject -and $Value.BaseObject -ne $Value) {
        $Value = $Value.BaseObject
    }

    $parts = New-Object 'System.Collections.Generic.List[string]'
    if (($Value -is [System.Collections.IEnumerable]) -and -not ($Value -is [string]) -and -not ($Value -is [char[]])) {
        foreach ($item in @($Value)) {
            $text = Convert-WholeScriptStaticScalarToText -Value $item
            if ($null -ne $text) {
                $parts.Add($text) | Out-Null
            }
        }
    } else {
        $text = Convert-WholeScriptStaticScalarToText -Value $Value
        if ($null -ne $text) {
            $parts.Add($text) | Out-Null
        }
    }

    if ($parts.Count -eq 0) {
        return ''
    }

    return ($parts.ToArray() -join $Delimiter)
}

function Convert-WholeScriptStaticOutputItemsToScriptText {
    param([object[]]$Items = @())

    if (-not $Items -or $Items.Count -eq 0) {
        return $null
    }

    $parts = New-Object 'System.Collections.Generic.List[string]'
    foreach ($item in @($Items)) {
        $text = Convert-WholeScriptStaticScalarToText -Value $item
        if ($null -eq $text) {
            return $null
        }
        $parts.Add($text) | Out-Null
    }

    if ($parts.Count -eq 0) {
        return $null
    }

    return ($parts.ToArray() -join "`r`n")
}

function Test-WholeScriptStaticArtifactLooksPowerShell {
    param(
        [AllowNull()][string]$PathText,
        [AllowNull()][string]$ContentText
    )

    $path = if ($PathText) { [string]$PathText } else { '' }
    if ($path -match '(?i)\.(ps1|psm1|psd1)$') {
        return $true
    }

    if ([string]::IsNullOrWhiteSpace($ContentText)) {
        return $false
    }

    return (Test-UsefulRecoveredScriptText -Text ([string]$ContentText))
}

function Ensure-WholeScriptStaticFileArtifact {
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][string]$PathText,
        [string]$Kind = 'File'
    )

    $pathInfo = Get-WholeScriptStaticArtifactPathInfo -PathText $PathText -Context $Context
    if ($null -eq $pathInfo -or $pathInfo.IsRegistry) {
        return $null
    }

    $store = Get-WholeScriptStaticArtifactStore -Context $Context
    $record = if ($store.Files.ContainsKey($pathInfo.CanonicalPath)) { $store.Files[$pathInfo.CanonicalPath] } else { $null }
    $pathVariants = @(Get-WholeScriptStaticArtifactDisplayVariants -PathText $PathText -Context $Context)
    if ($null -eq $record) {
        $record = [PSCustomObject]@{
            DisplayPath   = $pathInfo.DisplayPath
            CanonicalPath = $pathInfo.CanonicalPath
            DisplayVariants = @($pathVariants)
            Kind          = $Kind
            Exists        = $true
            ContentText   = ''
            Properties    = @{}
            ReferencedPaths = @()
            DerivedEvidence = @()
            IsPowerShell  = (Test-WholeScriptStaticArtifactLooksPowerShell -PathText $pathInfo.DisplayPath -ContentText '')
        }
        $store.Files[$pathInfo.CanonicalPath] = $record
    } else {
        $record.DisplayPath = $pathInfo.DisplayPath
        $record.CanonicalPath = $pathInfo.CanonicalPath
        $record.Kind = if ([string]::IsNullOrWhiteSpace([string]$Kind)) { $record.Kind } else { $Kind }
        $record.Exists = $true
        if ($null -eq $record.Properties) {
            $record.Properties = @{}
        }
        if ($null -eq $record.ReferencedPaths) {
            $record.ReferencedPaths = @()
        }
        if ($null -eq $record.DerivedEvidence) {
            $record.DerivedEvidence = @()
        }
    }

    Add-WholeScriptStaticArtifactDisplayVariants -Record $record -Variants $pathVariants

    return $record
}

function Get-WholeScriptStaticFileArtifact {
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][string]$PathText
    )

    $pathInfo = Get-WholeScriptStaticArtifactPathInfo -PathText $PathText -Context $Context
    if ($null -eq $pathInfo -or $pathInfo.IsRegistry) {
        return $null
    }

    $store = Get-WholeScriptStaticArtifactStore -Context $Context
    if (-not $store.Files.ContainsKey($pathInfo.CanonicalPath)) {
        return $null
    }

    $record = $store.Files[$pathInfo.CanonicalPath]
    if ($null -eq $record -or -not $record.Exists) {
        return $null
    }

    return $record
}

function Set-WholeScriptStaticFileArtifactContent {
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][string]$PathText,
        [AllowNull()][string]$ContentText,
        [string]$Kind = 'File',
        [bool]$Append = $false,
        [bool]$NoNewline = $false
    )

    $record = Ensure-WholeScriptStaticFileArtifact -Context $Context -PathText $PathText -Kind $Kind
    if ($null -eq $record) {
        return $null
    }

    $text = if ($null -eq $ContentText) { '' } else { [string]$ContentText }
    if ($Append) {
        if ([string]::IsNullOrEmpty([string]$record.ContentText)) {
            $record.ContentText = $text
        } elseif ($NoNewline) {
            $record.ContentText = ([string]$record.ContentText) + $text
        } else {
            $record.ContentText = ([string]$record.ContentText) + "`r`n" + $text
        }
    } else {
        $record.ContentText = $text
    }

    $record.IsPowerShell = (Test-WholeScriptStaticArtifactLooksPowerShell -PathText $record.DisplayPath -ContentText $record.ContentText)
    return $record
}

function Convert-WholeScriptStaticBytesToArtifactText {
    param($Value)

    $bytes = Try-ConvertToByteArrayFromStaticValue -Value $Value
    if ($null -eq $bytes) {
        return ''
    }

    $decoded = Convert-ByteArrayToLikelyPlainText -Bytes $bytes
    if ($null -eq $decoded) {
        return ''
    }

    return [string]$decoded
}

function Invoke-WholeScriptStaticFileTypeMethod {
    param(
        [Parameter(Mandatory)][string]$MemberName,
        [object[]]$Arguments,
        [Parameter(Mandatory)][hashtable]$Context
    )

    switch -Regex ($MemberName) {
        '^(?i:WriteAllText)$' {
            if (-not $Arguments -or $Arguments.Count -lt 2) {
                return [PSCustomObject]@{ Success = $false; Message = 'File::WriteAllText 缺少参数' }
            }

            $pathText = Convert-WholeScriptStaticScalarToText -Value $Arguments[0]
            if ([string]::IsNullOrWhiteSpace($pathText)) {
                return [PSCustomObject]@{ Success = $false; Message = 'File::WriteAllText 路径为空' }
            }

            $contentText = Convert-WholeScriptStaticValueToDelimitedText -Value $Arguments[1] -Delimiter "`r`n"
            Set-WholeScriptStaticFileArtifactContent -Context $Context -PathText $pathText -ContentText $contentText -Kind 'File' -Append:$false | Out-Null
            Add-WholeScriptStaticArtifactEvent -Context $Context -Action 'write' -Path $pathText -Kind 'File' -Detail 'File::WriteAllText'
            return [PSCustomObject]@{ Success = $true; Message = $null }
        }
        '^(?i:AppendAllText)$' {
            if (-not $Arguments -or $Arguments.Count -lt 2) {
                return [PSCustomObject]@{ Success = $false; Message = 'File::AppendAllText 缺少参数' }
            }

            $pathText = Convert-WholeScriptStaticScalarToText -Value $Arguments[0]
            if ([string]::IsNullOrWhiteSpace($pathText)) {
                return [PSCustomObject]@{ Success = $false; Message = 'File::AppendAllText 路径为空' }
            }

            $contentText = Convert-WholeScriptStaticValueToDelimitedText -Value $Arguments[1] -Delimiter "`r`n"
            Set-WholeScriptStaticFileArtifactContent -Context $Context -PathText $pathText -ContentText $contentText -Kind 'File' -Append:$true | Out-Null
            Add-WholeScriptStaticArtifactEvent -Context $Context -Action 'write' -Path $pathText -Kind 'File' -Detail 'File::AppendAllText'
            return [PSCustomObject]@{ Success = $true; Message = $null }
        }
        '^(?i:WriteAllBytes)$' {
            if (-not $Arguments -or $Arguments.Count -lt 2) {
                return [PSCustomObject]@{ Success = $false; Message = 'File::WriteAllBytes 缺少参数' }
            }

            $pathText = Convert-WholeScriptStaticScalarToText -Value $Arguments[0]
            if ([string]::IsNullOrWhiteSpace($pathText)) {
                return [PSCustomObject]@{ Success = $false; Message = 'File::WriteAllBytes 路径为空' }
            }

            $contentText = Convert-WholeScriptStaticBytesToArtifactText -Value $Arguments[1]
            Set-WholeScriptStaticFileArtifactContent -Context $Context -PathText $pathText -ContentText $contentText -Kind 'File' -Append:$false | Out-Null
            Add-WholeScriptStaticArtifactEvent -Context $Context -Action 'write' -Path $pathText -Kind 'File' -Detail 'File::WriteAllBytes'
            return [PSCustomObject]@{ Success = $true; Message = $null }
        }
    }

    return [PSCustomObject]@{ Success = $false; Message = 'unsupported_static_file_method' }
}

function Remove-WholeScriptStaticArtifact {
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][string]$PathText
    )

    $pathInfo = Get-WholeScriptStaticArtifactPathInfo -PathText $PathText -Context $Context
    if ($null -eq $pathInfo) {
        return $false
    }

    $store = Get-WholeScriptStaticArtifactStore -Context $Context
    if ($pathInfo.IsRegistry) {
        if ($store.Registry.ContainsKey($pathInfo.CanonicalPath)) {
            $null = $store.Registry.Remove($pathInfo.CanonicalPath)
            return $true
        }
        return $false
    }

    if ($store.Files.ContainsKey($pathInfo.CanonicalPath)) {
        $null = $store.Files.Remove($pathInfo.CanonicalPath)
        return $true
    }

    return $false
}

function Set-WholeScriptStaticRegistryArtifactValue {
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][string]$PathText,
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()][string]$ValueText
    )

    $pathInfo = Get-WholeScriptStaticArtifactPathInfo -PathText $PathText -Context $Context
    if ($null -eq $pathInfo -or -not $pathInfo.IsRegistry) {
        return $null
    }

    $store = Get-WholeScriptStaticArtifactStore -Context $Context
    $record = if ($store.Registry.ContainsKey($pathInfo.CanonicalPath)) { $store.Registry[$pathInfo.CanonicalPath] } else { $null }
    if ($null -eq $record) {
        $record = [PSCustomObject]@{
            DisplayPath   = $pathInfo.DisplayPath
            CanonicalPath = $pathInfo.CanonicalPath
            Exists        = $true
            Values        = @{}
        }
        $store.Registry[$pathInfo.CanonicalPath] = $record
    }

    $record.Values[[string]$Name] = $ValueText
    return $record
}

function Get-WholeScriptStaticFileArtifactOutputItems {
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][string]$PathText,
        [bool]$Raw = $false
    )

    $record = Get-WholeScriptStaticFileArtifact -Context $Context -PathText $PathText
    if ($null -eq $record -or [string]$record.Kind -ne 'File') {
        return $null
    }

    $contentText = if ($null -eq $record.ContentText) { '' } else { [string]$record.ContentText }
    if ($Raw) {
        return @($contentText)
    }

    if ([string]::IsNullOrEmpty($contentText)) {
        return @()
    }

    return @([regex]::Split($contentText, "`r?`n"))
}

function Get-WholeScriptStaticFileArtifactPayloadInfo {
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][string]$PathText,
        [string]$DecodeSource
    )

    $record = Get-WholeScriptStaticFileArtifact -Context $Context -PathText $PathText
    if ($null -eq $record -or [string]$record.Kind -ne 'File' -or -not $record.IsPowerShell) {
        return $null
    }

    $payloadText = Try-NormalizeStaticArtifactPayloadText -Text ([string]$record.ContentText)
    if (-not $payloadText) {
        return $null
    }

    return [PSCustomObject]@{
        PayloadText  = $payloadText
        DecodeSource = $DecodeSource
        ArtifactPath = [string]$record.DisplayPath
    }
}

function Try-NormalizeStaticArtifactPayloadText {
    param([AllowNull()][string]$Text)

    $rawText = Remove-RecoveredTextTransportArtifacts -Text ([string]$Text)
    if ([string]::IsNullOrWhiteSpace($rawText)) {
        return $null
    }

    $candidate = Invoke-NormalizePlainScriptText -ScriptText $rawText
    if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-UsefulRecoveredScriptText -Text $candidate)) {
        return (Get-WholeScriptReplacementCandidateText -OriginalText $rawText -CandidateText $candidate)
    }

    $payloadText = Try-NormalizeRecoveredScriptText -Text $rawText
    if ($payloadText) {
        return $payloadText
    }

    $lines = @($rawText -split "`r?`n")
    $maxTrim = [Math]::Min(8, [Math]::Max(0, $lines.Count - 1))
    for ($skip = 1; $skip -le $maxTrim -and -not $payloadText; $skip++) {
        $candidateText = (($lines | Select-Object -Skip $skip) -join "`r`n").Trim()
        if ([string]::IsNullOrWhiteSpace($candidateText)) {
            break
        }
        $candidate = Invoke-NormalizePlainScriptText -ScriptText $candidateText
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-UsefulRecoveredScriptText -Text $candidate)) {
            $payloadText = Get-WholeScriptReplacementCandidateText -OriginalText $candidateText -CandidateText $candidate
            if ($payloadText) {
                break
            }
        }
        $payloadText = Try-NormalizeRecoveredScriptText -Text $candidateText
    }

    return $payloadText
}

function Try-Resolve-WholeScriptInlineFileWritePayloadInfo {
    param(
        [Parameter(Mandatory)][string]$ScriptText,
        [hashtable]$Context = $null
    )

    if ([string]::IsNullOrWhiteSpace($ScriptText)) {
        return $null
    }

    $patterns = @(
        '(?is)(?:Set-Content|Add-Content)\s+-Path\s+''(?<path>[^'']+\.ps(?:1|m1|d1))''\s+-Value\s+@''\r?\n(?<content>.*?)\r?\n''@',
        '(?is)(?:Set-Content|Add-Content)\s+-Path\s+''(?<path>[^'']+\.ps(?:1|m1|d1))''\s+-Value\s+@"\r?\n(?<content>.*?)\r?\n"@',
        '(?is)(?:Set-Content|Add-Content)\s+-Path\s+"(?<path>[^"]+\.ps(?:1|m1|d1))"\s+-Value\s+@''\r?\n(?<content>.*?)\r?\n''@',
        '(?is)(?:Set-Content|Add-Content)\s+-Path\s+"(?<path>[^"]+\.ps(?:1|m1|d1))"\s+-Value\s+@"\r?\n(?<content>.*?)\r?\n"@',
        '(?is)(?:Set-Content|Add-Content)\s+-LiteralPath\s+''(?<path>[^'']+\.ps(?:1|m1|d1))''\s+-Value\s+@''\r?\n(?<content>.*?)\r?\n''@',
        '(?is)(?:Set-Content|Add-Content)\s+-LiteralPath\s+''(?<path>[^'']+\.ps(?:1|m1|d1))''\s+-Value\s+@"\r?\n(?<content>.*?)\r?\n"@',
        '(?is)(?:Set-Content|Add-Content)\s+-LiteralPath\s+"(?<path>[^"]+\.ps(?:1|m1|d1))"\s+-Value\s+@''\r?\n(?<content>.*?)\r?\n''@',
        '(?is)(?:Set-Content|Add-Content)\s+-LiteralPath\s+"(?<path>[^"]+\.ps(?:1|m1|d1))"\s+-Value\s+@"\r?\n(?<content>.*?)\r?\n"@'
    )

    $sourceEvidence = @(Get-UniqueSensitiveEvidenceRecords -Evidence (Get-WholeScriptSensitiveEvidenceFromText -Text $ScriptText -Source 'inline_file_write_source' -Stage 'whole_script_source' -Context $Context))
    $sourceFilePathCount = @($sourceEvidence | Where-Object { [string]$_.Kind -eq 'FilePath' }).Count
    $sourceUrlCount = @($sourceEvidence | Where-Object { [string]$_.Kind -eq 'Url' }).Count
    $sourceEvidenceScore = (12 * $sourceFilePathCount) + (18 * $sourceUrlCount) + (6 * $sourceEvidence.Count)

    $isLikelyManagedLoaderWrapper = {
        param([string]$Text)

        if ([string]::IsNullOrWhiteSpace($Text)) {
            return $false
        }

        $candidate = Remove-RecoveredTextTransportArtifacts -Text $Text
        if ([string]::IsNullOrWhiteSpace($candidate) -or $candidate.Length -lt 2048) {
            return $false
        }

        $signals = 0
        if ($candidate -match '(?i)(?:\[Reflection\.Assembly\]|\bAssembly\]|\bAssembly\s*::\s*Load\b)') { $signals++ }
        if ($candidate -match '(?is)GetType\s*\([^)]*\)\s*\.\s*GetMethod\s*\(\s*[''"]Execute[''"]\s*\)\s*\.\s*Invoke') { $signals++ }
        if ($candidate -match '(?i)\bGZipStream\b') { $signals++ }
        if ($candidate -match '(?i)\bFromBase64String\b') { $signals++ }
        if ($candidate -match '(?i)\bwhile\s*\(\s*\$?true\s*\)') { $signals++ }
        if ($candidate -match '(?i)\bInvoke-Expression\b|\bIEX\b') { $signals++ }
        if ($candidate -match '(?i)\bGetMethod\s*\(\s*[''"]Execute[''"]\s*\)') { $signals++ }

        return ($signals -ge 2)
    }

    $scoreCandidatePayload = {
        param(
            [string]$PayloadText,
            [string]$ArtifactPath
        )

        $candidateText = Get-WholeScriptReplacementCandidateText -OriginalText $ScriptText -CandidateText $PayloadText
        if (-not $candidateText) {
            return $null
        }

        $candidateEvidence = @(Get-UniqueSensitiveEvidenceRecords -Evidence (Get-WholeScriptSensitiveEvidenceFromText -Text $candidateText -Source 'inline_file_write' -Stage 'whole_script_inline_payload' -Context $Context))
        $filePathCount = @($candidateEvidence | Where-Object { [string]$_.Kind -eq 'FilePath' }).Count
        $urlCount = @($candidateEvidence | Where-Object { [string]$_.Kind -eq 'Url' }).Count
        $regKeyCount = @($candidateEvidence | Where-Object { [string]$_.Kind -eq 'RegKey' }).Count
        $managedLoader = & $isLikelyManagedLoaderWrapper $candidateText

        $score = Get-RecoveredTextCandidateScore -Text $candidateText
        $score += (16 * $filePathCount) + (24 * $urlCount) + (10 * $regKeyCount) + (5 * $candidateEvidence.Count)
        $score += [Math]::Min([int]($candidateText.Length / 256), 160)
        if ($managedLoader) {
            $score -= 240
        }

        return [PSCustomObject]@{
            PayloadText          = [string]$candidateText
            DecodeSource         = 'inline_file_write'
            ArtifactPath         = [string]$ArtifactPath
            Score                = [int]$score
            SensitiveEvidence    = $candidateEvidence.Count
            FilePathCount        = $filePathCount
            UrlCount             = $urlCount
            RegKeyCount          = $regKeyCount
            IsManagedLoaderShell = [bool]$managedLoader
        }
    }

    $candidates = New-Object 'System.Collections.Generic.List[object]'
    foreach ($pattern in $patterns) {
        foreach ($match in @([regex]::Matches($ScriptText, $pattern))) {
            $pathText = Unwrap-PowerShellHostLooseToken -TokenText ([string]$match.Groups['path'].Value)
            if ([string]::IsNullOrWhiteSpace($pathText)) {
                continue
            }

            $normalizedPath = Resolve-WholeScriptStaticDisplayPath -PathText $pathText -Context $Context
            if ([string]::IsNullOrWhiteSpace($normalizedPath) -or $normalizedPath -notmatch '(?i)\.(ps1|psm1|psd1)$') {
                continue
            }

            $rawPayloadText = Remove-RecoveredTextTransportArtifacts -Text ([string]$match.Groups['content'].Value)
            $payloadText = $null
            if (-not [string]::IsNullOrWhiteSpace($rawPayloadText) -and (Test-UsefulRecoveredScriptText -Text $rawPayloadText)) {
                $payloadText = $rawPayloadText
            } else {
                $payloadText = Try-NormalizeStaticArtifactPayloadText -Text $rawPayloadText
            }
            if (-not $payloadText) {
                continue
            }

            $scored = & $scoreCandidatePayload $payloadText $normalizedPath
            if ($scored) {
                $candidates.Add($scored) | Out-Null
            }
        }
    }

    if ($candidates.Count -eq 0) {
        return $null
    }

    $bestCandidate = @(
        $candidates.ToArray() | Sort-Object -Property `
            @{ Expression = { [int]$_.Score }; Descending = $true }, `
            @{ Expression = { [int]$_.SensitiveEvidence }; Descending = $true }, `
            @{ Expression = { [int]$_.FilePathCount }; Descending = $true }, `
            @{ Expression = { [int]$_.UrlCount }; Descending = $true }, `
            @{ Expression = { [int]([string]$_.PayloadText).Length }; Descending = $true }
    ) | Select-Object -First 1
    if (-not $bestCandidate) {
        return $null
    }

    if ($bestCandidate.IsManagedLoaderShell -and
        $sourceEvidenceScore -ge 96 -and
        $bestCandidate.SensitiveEvidence -le [Math]::Max(2, [int][Math]::Floor($sourceEvidence.Count / 4.0)) -and
        $bestCandidate.Score -lt ($sourceEvidenceScore + 60)) {
        return $null
    }

    return [PSCustomObject]@{
        PayloadText  = [string]$bestCandidate.PayloadText
        DecodeSource = 'inline_file_write'
        ArtifactPath = [string]$bestCandidate.ArtifactPath
    }

    return $null
}

function Get-WholeScriptStaticArtifactPayloadInfoFromContext {
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [string]$DecodeSource = 'static_artifact_store'
    )

    $candidatePaths = New-Object 'System.Collections.Generic.List[string]'
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $events = @($Context.ArtifactEvents)
    [array]::Reverse($events)
    foreach ($event in @($events)) {
        if ($null -eq $event) { continue }
        if ([string]$event.Kind -ne 'File' -or [string]$event.Action -ne 'write') { continue }
        $pathText = [string]$event.Path
        if ([string]::IsNullOrWhiteSpace($pathText)) { continue }
        if ($seen.Add($pathText)) {
            $candidatePaths.Add($pathText) | Out-Null
        }
    }

    $store = Get-WholeScriptStaticArtifactStore -Context $Context
    foreach ($fileKey in @($store.Files.Keys)) {
        $record = $store.Files[$fileKey]
        if ($null -eq $record -or -not $record.Exists) { continue }
        $pathText = [string]$record.DisplayPath
        if ([string]::IsNullOrWhiteSpace($pathText)) { continue }
        if ($seen.Add($pathText)) {
            $candidatePaths.Add($pathText) | Out-Null
        }
    }

    foreach ($pathText in @($candidatePaths.ToArray())) {
        $payloadInfo = Get-WholeScriptStaticFileArtifactPayloadInfo -Context $Context -PathText $pathText -DecodeSource $DecodeSource
        if ($payloadInfo -and -not [string]::IsNullOrWhiteSpace([string]$payloadInfo.PayloadText)) {
            return $payloadInfo
        }
    }

    return $null
}

function Resolve-WholeScriptStaticArtifactPayloadInfoFromScriptText {
    param(
        [Parameter(Mandatory)][string]$ScriptText,
        [bool]$SafeMode = $true
    )

    if ([string]::IsNullOrWhiteSpace($ScriptText)) {
        return $null
    }

    $parse = Get-ScriptParseInfo -ScriptText $ScriptText
    if (-not $parse.IsValid -or -not $parse.Ast) {
        return $null
    }

    $statements = @(Get-TopLevelScriptStatementsFromText -ScriptText $ScriptText)
    if ($statements.Count -eq 0) {
        return $null
    }

    $ctx = New-WholeScriptStaticResolutionContext
    try {
        $staticEvalState = Get-StaticEvalState -Context $ctx
        if ($staticEvalState) {
            $staticEvalState.ValueDepthLimit = 64
            $staticEvalState.StringCompatDepthLimit = 48
        }
        $ctx.SafeMode = $SafeMode

        [void](Initialize-WholeScriptStaticAssignments -Statements $statements -Context $ctx)
        foreach ($statement in @($statements)) {
            try {
                [void](Invoke-WholeScriptStaticStatement -Statement $statement -Context $ctx -AllowEmptyFallback:$false)
            } catch {
                if (-not (Test-IsCallDepthOverflowException -ErrorObject $_)) {
                    throw
                }
            }
        }

        return (Get-WholeScriptStaticArtifactPayloadInfoFromContext -Context $ctx -DecodeSource 'static_artifact_store')
    } finally {
        Close-WholeScriptStaticResolutionContext -Context $ctx
    }
}

function Resolve-WholeScriptStaticArtifactPathTextFromAst {
    param(
        $Ast,
        [hashtable]$Context
    )

    if ($null -eq $Ast) {
        return $null
    }

    $text = Try-GetStaticStringValue -Ast $Ast -Context $Context
    if (-not [string]::IsNullOrWhiteSpace($text)) {
        return (Resolve-WholeScriptStaticDisplayPath -PathText ([string]$text) -Context $Context)
    }

    $resolved = Resolve-StaticAstValue -Ast $Ast -Context $Context -AllowEmptyFallback:$false
    if ($resolved -and $resolved.Success) {
        $fallbackText = Convert-WholeScriptStaticScalarToText -Value $resolved.Value
        if (-not [string]::IsNullOrWhiteSpace($fallbackText)) {
            return (Resolve-WholeScriptStaticDisplayPath -PathText ([string]$fallbackText) -Context $Context)
        }
    }

    return $null
}

function Convert-WholeScriptStaticValueToCommandLineText {
    param($Value)

    return (Convert-WholeScriptStaticValueToDelimitedText -Value $Value -Delimiter ' ')
}

function Resolve-WholeScriptStaticCommandValueTextFromAst {
    param(
        $Ast,
        [hashtable]$Context,
        [string]$Delimiter = ' '
    )

    if ($null -eq $Ast) {
        return $null
    }

    $resolved = Resolve-StaticAstValue -Ast $Ast -Context $Context -AllowEmptyFallback:$false
    if ($resolved -and $resolved.Success) {
        $text = Convert-WholeScriptStaticValueToDelimitedText -Value $resolved.Value -Delimiter $Delimiter
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            return $text
        }
    }

    $fallback = Try-GetStaticStringValue -Ast $Ast -Context $Context
    if (-not [string]::IsNullOrWhiteSpace($fallback)) {
        return [string]$fallback
    }

    return $null
}

function Resolve-WholeScriptStaticCopyDestinationPathText {
    param(
        [string]$SourcePathText,
        [string]$DestinationPathText,
        [hashtable]$Context
    )

    if ([string]::IsNullOrWhiteSpace($SourcePathText) -or [string]::IsNullOrWhiteSpace($DestinationPathText)) {
        return $DestinationPathText
    }

    $destRecord = Get-WholeScriptStaticFileArtifact -Context $Context -PathText $DestinationPathText
    $isDestinationDirectory = ($destRecord -and [string]$destRecord.Kind -eq 'Directory') -or $DestinationPathText.Trim().EndsWith('\')
    if (-not $isDestinationDirectory) {
        return $DestinationPathText
    }

    try {
        $fileName = [System.IO.Path]::GetFileName($SourcePathText.TrimEnd('\'))
        if ([string]::IsNullOrWhiteSpace($fileName)) {
            return $DestinationPathText
        }
        return [System.IO.Path]::Combine($DestinationPathText.TrimEnd('\'), $fileName)
    } catch {
        return $DestinationPathText
    }
}

function Resolve-WholeScriptStaticHostFilePayloadInfoFromCommandLineText {
    param(
        [AllowNull()][string]$CommandLineText,
        [Parameter(Mandatory)][hashtable]$Context,
        [string]$DecodeSource = 'static_artifact_host_commandline'
    )

    $payloadInfo = if (-not [string]::IsNullOrWhiteSpace($CommandLineText)) {
        Resolve-WholeScriptHostPayloadInfo -ScriptText $CommandLineText
    } else {
        $null
    }
    if ($payloadInfo -and -not [string]::IsNullOrWhiteSpace([string]$payloadInfo.PayloadText)) {
        $candidateText = Get-WholeScriptReplacementCandidateText -OriginalText $CommandLineText -CandidateText $payloadInfo.PayloadText
        if (-not $candidateText) {
            return $null
        }
        return [PSCustomObject]@{
            PayloadText  = [string]$candidateText
            DecodeSource = if ($payloadInfo.PSObject.Properties['DecodeSource']) { [string]$payloadInfo.DecodeSource } else { $DecodeSource }
        }
    }

    if ([string]::IsNullOrWhiteSpace($CommandLineText)) {
        return $null
    }

    $text = $CommandLineText.Trim()
    $hostMatch = [regex]::Match($text, '(?is)\b(?<cmd>(?:[A-Z]:)?[^''"\r\n]*?(?:powershell|pwsh)(?:\.exe)?)\b')
    if (-not $hostMatch.Success) {
        return $null
    }

    $tail = $text.Substring($hostMatch.Index + $hostMatch.Length)
    if ([string]::IsNullOrWhiteSpace($tail)) {
        return $null
    }

    $tokenMatches = @(Get-PowerShellHostLooseTokenMatches -Text $tail)
    for ($i = 0; $i -lt $tokenMatches.Count; $i++) {
        $tokenText = [string]$tokenMatches[$i].Value
        if ([string]::IsNullOrWhiteSpace($tokenText) -or -not $tokenText.StartsWith('-')) {
            continue
        }

        $paramInfo = Resolve-PowerShellHostLooseParameterInfo -ParameterName $tokenText.TrimStart('-')
        if (-not $paramInfo) {
            continue
        }

        if ($paramInfo.CanonicalName -eq 'file') {
            if ($i + 1 -ge $tokenMatches.Count) {
                return $null
            }

            $filePathText = Unwrap-PowerShellHostLooseToken -TokenText ([string]$tokenMatches[$i + 1].Value)
            return (Get-WholeScriptStaticFileArtifactPayloadInfo -Context $Context -PathText $filePathText -DecodeSource $DecodeSource)
        }

        if ($paramInfo.ExpectsValue) {
            $i++
        }
    }

    return $null
}

function Resolve-WholeScriptStaticArtifactPayloadInfoFromCommandAst {
    param(
        [Parameter(Mandatory)][System.Management.Automation.Language.CommandAst]$CommandAst,
        [Parameter(Mandatory)][hashtable]$Context
    )

    $elements = @($CommandAst.CommandElements)
    if ($elements.Count -eq 0) {
        return $null
    }

    $targetAst = $null
    switch ([string]$CommandAst.InvocationOperator) {
        'Ampersand' { if ($elements.Count -ge 1) { $targetAst = $elements[0] } }
        'Dot'       { if ($elements.Count -ge 1) { $targetAst = $elements[0] } }
    }
    if ($null -eq $targetAst) {
        $headText = if ($elements[0] -and $elements[0].Extent) { [string]$elements[0].Extent.Text } else { $null }
        if ($headText -in @('&', '.') -and $elements.Count -ge 2) {
            $targetAst = $elements[1]
        }
    }
    if ($null -ne $targetAst) {
        $artifactPath = Resolve-WholeScriptStaticArtifactPathTextFromAst -Ast $targetAst -Context $Context
        if (-not [string]::IsNullOrWhiteSpace($artifactPath)) {
            $info = Get-WholeScriptStaticFileArtifactPayloadInfo -Context $Context -PathText $artifactPath -DecodeSource 'static_artifact_invocation'
            if ($info) {
                return $info
            }
        }
    }

    $cmdName = Convert-DynamicCommandCandidateToName -Value $CommandAst.GetCommandName()
    if ([string]::IsNullOrWhiteSpace($cmdName)) {
        return $null
    }

    $binding = Get-StaticCommandArgumentBinding -CommandAst $CommandAst
    switch -Regex ($cmdName) {
        '^(?i:powershell|pwsh)(?:\.exe)?$' {
            $fileAst = $null
            foreach ($key in @('file', 'f')) {
                if ($binding.Parameters.ContainsKey($key) -and $binding.Parameters[$key]) {
                    $fileAst = $binding.Parameters[$key]
                    break
                }
            }
            if ($fileAst) {
                $artifactPath = Resolve-WholeScriptStaticArtifactPathTextFromAst -Ast $fileAst -Context $Context
                if (-not [string]::IsNullOrWhiteSpace($artifactPath)) {
                    $info = Get-WholeScriptStaticFileArtifactPayloadInfo -Context $Context -PathText $artifactPath -DecodeSource 'static_artifact_host_file'
                    if ($info) {
                        return $info
                    }
                }
            }
        }
        '^(?i:start-process|start|saps)$' {
            $fileAst = $null
            foreach ($key in @('filepath')) {
                if ($binding.Parameters.ContainsKey($key) -and $binding.Parameters[$key]) {
                    $fileAst = $binding.Parameters[$key]
                    break
                }
            }
            if ($null -eq $fileAst -and $binding.Positional.Count -gt 0) {
                $fileAst = $binding.Positional[0]
            }

            $hostPath = Resolve-WholeScriptStaticArtifactPathTextFromAst -Ast $fileAst -Context $Context
            if (-not (Test-PowerShellHostCommandName -CommandName $hostPath)) {
                break
            }

            $argAst = $null
            foreach ($key in @('argumentlist')) {
                if ($binding.Parameters.ContainsKey($key) -and $binding.Parameters[$key]) {
                    $argAst = $binding.Parameters[$key]
                    break
                }
            }
            if ($null -eq $argAst -and $binding.Positional.Count -gt 1) {
                $argAst = $binding.Positional[1]
            }

            $argumentText = Resolve-WholeScriptStaticCommandValueTextFromAst -Ast $argAst -Context $Context -Delimiter ' '
            $commandLineText = if ([string]::IsNullOrWhiteSpace($argumentText)) {
                $hostPath
            } else {
                ($hostPath + ' ' + $argumentText).Trim()
            }

            $info = Resolve-WholeScriptStaticHostFilePayloadInfoFromCommandLineText -CommandLineText $commandLineText -Context $Context -DecodeSource 'static_artifact_start_process'
            if ($info) {
                return $info
            }
        }
        '^(?i:schtasks(?:\.exe)?)$' {
            $commandText = if ($CommandAst.Extent) { [string]$CommandAst.Extent.Text } else { $null }
            if ([string]::IsNullOrWhiteSpace($commandText)) {
                break
            }

            $trMatch = [regex]::Match($commandText, '(?is)(?:^|\s)(?:/TR|-TR)\s+(?<cmd>"(?:[^"]|"")*"|''(?:[^'']|'''')*''|\S+)')
            if (-not $trMatch.Success) {
                break
            }

            $taskCommandLine = Unwrap-PowerShellHostLooseToken -TokenText ([string]$trMatch.Groups['cmd'].Value)
            $info = Resolve-WholeScriptStaticHostFilePayloadInfoFromCommandLineText -CommandLineText $taskCommandLine -Context $Context -DecodeSource 'static_artifact_schtasks_tr'
            if ($info) {
                return $info
            }
        }
    }

    return $null
}

function Get-CompatibilityWindowsPowerShellHome {
    $windowsRoot = if (-not [string]::IsNullOrWhiteSpace($env:WINDIR)) { $env:WINDIR } else { 'C:\Windows' }
    return (Join-Path $windowsRoot 'System32\WindowsPowerShell\v1.0')
}

function Resolve-CompatibilityDynamicCommandNameExpressionValue {
    param(
        $Ast,
        [int]$Depth = 0
    )

    if ($null -eq $Ast -or $Depth -gt 24) {
        return [PSCustomObject]@{ Success = $false; Value = $null }
    }

    if ($Ast -is [System.Management.Automation.Language.CommandExpressionAst]) {
        return Resolve-CompatibilityDynamicCommandNameExpressionValue -Ast $Ast.Expression -Depth ($Depth + 1)
    }

    if ($Ast -is [System.Management.Automation.Language.ParenExpressionAst]) {
        if ($Ast.Pipeline -and $Ast.Pipeline.PipelineElements -and $Ast.Pipeline.PipelineElements.Count -eq 1) {
            $elem = $Ast.Pipeline.PipelineElements[0]
            if ($elem -is [System.Management.Automation.Language.CommandAst]) {
                return Resolve-CompatibilityDynamicCommandNameExpressionValue -Ast $elem -Depth ($Depth + 1)
            }
            if ($elem -is [System.Management.Automation.Language.CommandExpressionAst]) {
                return Resolve-CompatibilityDynamicCommandNameExpressionValue -Ast $elem.Expression -Depth ($Depth + 1)
            }
            if ($elem.PSObject.Properties['Expression']) {
                return Resolve-CompatibilityDynamicCommandNameExpressionValue -Ast $elem.Expression -Depth ($Depth + 1)
            }
        }
        return [PSCustomObject]@{ Success = $false; Value = $null }
    }

    if ($Ast -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
        return [PSCustomObject]@{ Success = $true; Value = [string]$Ast.Value }
    }

    if ($Ast -is [System.Management.Automation.Language.ConstantExpressionAst]) {
        return [PSCustomObject]@{ Success = $true; Value = $Ast.Value }
    }

    if ($Ast -is [System.Management.Automation.Language.ArrayLiteralAst]) {
        $items = @()
        foreach ($elem in $Ast.Elements) {
            $itemResult = Resolve-CompatibilityDynamicCommandNameExpressionValue -Ast $elem -Depth ($Depth + 1)
            if (-not $itemResult.Success) {
                return [PSCustomObject]@{ Success = $false; Value = $null }
            }
            $items += $itemResult.Value
        }
        return [PSCustomObject]@{ Success = $true; Value = @($items) }
    }

    if ($Ast -is [System.Management.Automation.Language.VariableExpressionAst]) {
        $varName = [string]$Ast.VariablePath.UserPath
        if ([string]::IsNullOrWhiteSpace($varName)) {
            return [PSCustomObject]@{ Success = $false; Value = $null }
        }

        switch ($varName.ToLowerInvariant()) {
            'pshome' { return [PSCustomObject]@{ Success = $true; Value = (Get-CompatibilityWindowsPowerShellHome) } }
            'true'   { return [PSCustomObject]@{ Success = $true; Value = $true } }
            'false'  { return [PSCustomObject]@{ Success = $true; Value = $false } }
            'null'   { return [PSCustomObject]@{ Success = $true; Value = $null } }
        }

        if ($varName -match '^(?i:env:)(.+)$') {
            $envName = $matches[1]
            try {
                $envValue = (Get-Item -Path ("env:" + $envName) -ErrorAction Stop).Value
                return [PSCustomObject]@{ Success = $true; Value = $envValue }
            } catch {
                return [PSCustomObject]@{ Success = $false; Value = $null }
            }
        }

        try {
            $value = Get-Variable -Name $varName -ValueOnly -ErrorAction Stop
            return [PSCustomObject]@{ Success = $true; Value = $value }
        } catch {
            return [PSCustomObject]@{ Success = $false; Value = $null }
        }
    }

    if ($Ast -is [System.Management.Automation.Language.IndexExpressionAst]) {
        $targetResult = Resolve-CompatibilityDynamicCommandNameExpressionValue -Ast $Ast.Target -Depth ($Depth + 1)
        if (-not $targetResult.Success) {
            return [PSCustomObject]@{ Success = $false; Value = $null }
        }

        $indexAst = if ($Ast.Index -is [System.Management.Automation.Language.CommandExpressionAst]) {
            $Ast.Index.Expression
        } else {
            $Ast.Index
        }
        $indexResult = Resolve-CompatibilityDynamicCommandNameExpressionValue -Ast $indexAst -Depth ($Depth + 1)
        if (-not $indexResult.Success) {
            return [PSCustomObject]@{ Success = $false; Value = $null }
        }

        $targetValue = $targetResult.Value
        $indexes = if ($indexResult.Value -is [array]) { @($indexResult.Value) } else { @($indexResult.Value) }
        $resolved = @()

        if ($targetValue -is [string]) {
            foreach ($idx in $indexes) {
                try {
                    $resolved += $targetValue[[int]$idx]
                } catch {
                    return [PSCustomObject]@{ Success = $false; Value = $null }
                }
            }
        } else {
            $targetItems = if (($targetValue -is [System.Collections.IEnumerable]) -and -not ($targetValue -is [string])) {
                @($targetValue)
            } else {
                @($targetValue)
            }
            foreach ($idx in $indexes) {
                try {
                    $resolved += $targetItems[[int]$idx]
                } catch {
                    return [PSCustomObject]@{ Success = $false; Value = $null }
                }
            }
        }

        if ($resolved.Count -eq 1) {
            return [PSCustomObject]@{ Success = $true; Value = $resolved[0] }
        }
        return [PSCustomObject]@{ Success = $true; Value = @($resolved) }
    }

    if ($Ast -is [System.Management.Automation.Language.BinaryExpressionAst]) {
        $leftResult = Resolve-CompatibilityDynamicCommandNameExpressionValue -Ast $Ast.Left -Depth ($Depth + 1)
        $rightResult = Resolve-CompatibilityDynamicCommandNameExpressionValue -Ast $Ast.Right -Depth ($Depth + 1)
        if (-not $leftResult.Success -or -not $rightResult.Success) {
            return [PSCustomObject]@{ Success = $false; Value = $null }
        }

        switch ([string]$Ast.Operator) {
            'Plus' {
                if ($leftResult.Value -is [array] -or $rightResult.Value -is [array]) {
                    return [PSCustomObject]@{ Success = $true; Value = @(@($leftResult.Value) + @($rightResult.Value)) }
                }
                return [PSCustomObject]@{ Success = $true; Value = ([string]$leftResult.Value + [string]$rightResult.Value) }
            }
            'Join' {
                $separator = [string]$rightResult.Value
                $items = @($leftResult.Value)
                return [PSCustomObject]@{ Success = $true; Value = (($items | ForEach-Object { [string]$_ }) -join $separator) }
            }
        }

        return [PSCustomObject]@{ Success = $false; Value = $null }
    }

    if ($Ast -is [System.Management.Automation.Language.ConvertExpressionAst]) {
        $childResult = Resolve-CompatibilityDynamicCommandNameExpressionValue -Ast $Ast.Child -Depth ($Depth + 1)
        if (-not $childResult.Success) {
            return [PSCustomObject]@{ Success = $false; Value = $null }
        }

        try {
            switch ([string]$Ast.Type.TypeName.FullName) {
                'string' { return [PSCustomObject]@{ Success = $true; Value = [string]$childResult.Value } }
                'char'   { return [PSCustomObject]@{ Success = $true; Value = [char]$childResult.Value } }
                'int'    { return [PSCustomObject]@{ Success = $true; Value = [int]$childResult.Value } }
            }
        } catch {
            return [PSCustomObject]@{ Success = $false; Value = $null }
        }
    }

    return [PSCustomObject]@{ Success = $false; Value = $null }
}

function Get-CompatibilityWrappedDynamicInvocationInfo {
    param(
        [Parameter(Mandatory)][System.Management.Automation.Language.CommandAst]$CommandAst
    )

    $elements = @($CommandAst.CommandElements)
    if ($elements.Count -lt 1) { return $null }

    $wrapperOperator = $null
    $targetAst = $null
    $argumentStartIndex = $null

    switch ([string]$CommandAst.InvocationOperator) {
        'Ampersand' {
            $wrapperOperator = '&'
            $targetAst = $elements[0]
            $argumentStartIndex = 1
        }
        'Dot' {
            $wrapperOperator = '.'
            $targetAst = $elements[0]
            $argumentStartIndex = 1
        }
    }

    if (-not $wrapperOperator) {
        $headText = if ($elements[0] -and $elements[0].Extent) { [string]$elements[0].Extent.Text } else { $null }
        if ($headText -in @('&', '.')) {
            if ($elements.Count -lt 2) { return $null }
            $wrapperOperator = $headText
            $targetAst = $elements[1]
            $argumentStartIndex = 2
        }
    }

    if (-not $wrapperOperator -or $null -eq $targetAst) {
        return $null
    }

    $candidateName = $null
    $resolved = Resolve-CompatibilityDynamicCommandNameExpressionValue -Ast $targetAst
    if ($resolved.Success) {
        $candidateName = Convert-DynamicCommandCandidateToName -Value $resolved.Value
    }
    if ([string]::IsNullOrWhiteSpace($candidateName)) {
        return $null
    }

    $argAst = if ($elements.Count -gt $argumentStartIndex) { $elements[$argumentStartIndex] } else { $null }
    if ($candidateName -in @('Invoke-Expression', 'iex')) {
        return [PSCustomObject]@{
            DynamicType     = 'IEX'
            ArgumentAst     = $argAst
            WrapperOperator = $wrapperOperator
        }
    }

    if (Test-PowerShellHostCommandName -CommandName $candidateName) {
        return [PSCustomObject]@{
            DynamicType     = 'PowerShellCommand'
            ArgumentAst     = $argAst
            WrapperOperator = $wrapperOperator
        }
    }

    return $null
}

function Test-UsefulRecoveredScriptText {
    param([AllowNull()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $false
    }

    $parse = Get-ScriptParseInfo -ScriptText $Text
    if (-not $parse.IsValid) {
        return $false
    }

    $singleExpr = Get-SingleTopLevelExpressionAstFromText -ScriptText $Text
    if ($singleExpr) {
        if ($singleExpr -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
            return $false
        }

        if ($singleExpr -is [System.Management.Automation.Language.ExpandableStringExpressionAst] -and
            @($singleExpr.NestedExpressions).Count -eq 0) {
            return $false
        }

        if ($singleExpr -is [System.Management.Automation.Language.ConstantExpressionAst]) {
            $value = $singleExpr.Value
            if ($value -is [string] -or $value -is [char] -or $value -is [bool] -or $value -is [ValueType]) {
                return $false
            }
        }
    }

    if ($Text -match '(?i)\b(function|param|if|foreach|for|while|switch|return|try|catch|Invoke-|New-Object|Write-|Set-|Get-|Sort-|Measure-|Where-|Select-|Join-Path|Start-Process)\b') {
        return $true
    }
    if ($Text -match '[`r`n;]') {
        return $true
    }
    if ($Text -match '\$[A-Za-z_][\w:]*') {
        return $true
    }

    return (-not $singleExpr)
}

function Convert-WholeScriptHelperPayloadToCandidateText {
    param(
        $Value,
        [int]$MaxTextLength = 524288
    )

    if ($Value -is [psobject] -and $null -ne $Value.BaseObject -and $Value.BaseObject -ne $Value) {
        $Value = $Value.BaseObject
    }

    if ($null -eq $Value) {
        return $null
    }

    $text = $null
    if ($Value -is [string]) {
        $text = [string]$Value
    } elseif ($Value -is [char]) {
        $text = [string]$Value
    } elseif ($Value -is [char[]]) {
        $text = (-join $Value)
    } else {
        $text = Convert-StaticValueToMeaningfulString -Value $Value
        if ([string]::IsNullOrWhiteSpace($text) -and
            ($Value -is [System.Collections.IEnumerable]) -and
            -not ($Value -is [string]) -and
            -not ($Value -is [char[]])) {
            $parts = New-Object 'System.Collections.Generic.List[string]'
            $allTextLike = $true
            foreach ($item in @($Value)) {
                $itemText = Convert-WholeScriptHelperPayloadToCandidateText -Value $item -MaxTextLength $MaxTextLength
                if ([string]::IsNullOrWhiteSpace($itemText)) {
                    $allTextLike = $false
                    break
                }
                $parts.Add([string]$itemText) | Out-Null
            }
            if ($allTextLike -and $parts.Count -gt 0) {
                $text = ($parts.ToArray() -join '')
            }
        }
    }

    $text = Remove-RecoveredTextTransportArtifacts -Text $text
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }

    if ($text.Length -gt $MaxTextLength) {
        return $null
    }

    return [string]$text
}

function Get-WholeScriptSensitiveEvidenceFromText {
    param(
        [AllowNull()][string]$Text,
        [string]$Source = 'helper_payload',
        [string]$Stage = 'whole_script_helper',
        [hashtable]$Context = $null
    )

    $candidate = Remove-RecoveredTextTransportArtifacts -Text $Text
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        return @()
    }

    $evidence = New-Object 'System.Collections.Generic.List[object]'
    foreach ($entry in @(Get-WholeScriptRegexSensitiveEvidenceFromText -Text $candidate -Source $Source -Stage $Stage -Context $Context)) {
        if ($null -eq $entry) { continue }
        $evidence.Add($entry) | Out-Null
    }

    foreach ($entry in @(Get-WholeScriptStaticArtifactEvidenceFromScriptText -ScriptText $candidate -Source $Source -Stage $Stage -Context $Context)) {
        if ($null -eq $entry) { continue }
        Add-SensitiveEvidenceRecord -EvidenceList $evidence `
            -Kind ([string]$entry.Kind) `
            -Value ([string]$entry.Value) `
            -Source $(if ($entry.PSObject.Properties['Source']) { [string]$entry.Source } else { $Source }) `
            -Stage $(if ($entry.PSObject.Properties['Stage']) { [string]$entry.Stage } else { $Stage }) `
            -Confidence $(if ($entry.PSObject.Properties['Confidence']) { [string]$entry.Confidence } else { 'High' }) `
            -PreserveLiteral $(if ($entry.PSObject.Properties['PreserveLiteral']) { [bool]$entry.PreserveLiteral } else { $false })
    }

    return @($evidence.ToArray())
}

function Get-WholeScriptStaticArtifactEvidenceFromScriptText {
    param(
        [AllowNull()][string]$ScriptText,
        [string]$Source = 'helper_payload',
        [string]$Stage = 'whole_script_helper_static',
        [hashtable]$Context = $null
    )

    $candidate = Remove-RecoveredTextTransportArtifacts -Text $ScriptText
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        return @()
    }
    if ($candidate.Length -gt 50000) {
        return @()
    }
    if ($candidate -notmatch '(?i)(?:[A-Za-z]:\\|\\\\[^\\]+\\[^\\]+|%[A-Za-z_][A-Za-z0-9_]*%\\|\$env:[A-Za-z_][A-Za-z0-9_]*\\|\b(?:set-content|add-content|out-file|new-item|copy-item|move-item|remove-item|set-itemproperty|join-path|start-process|get-location|getfolderpath|getenvironmentvariable)\b)') {
        return @()
    }

    $parse = Get-ScriptParseInfo -ScriptText $candidate
    if (-not $parse.IsValid -or -not $parse.Ast) {
        return @()
    }

    $statements = @(Get-TopLevelScriptStatementsFromText -ScriptText $candidate)
    if ($statements.Count -eq 0) {
        return @()
    }

    $ctx = New-WholeScriptStaticResolutionContext
    if ($Context -and $Context.ContainsKey('ScriptPath') -and -not [string]::IsNullOrWhiteSpace([string]$Context.ScriptPath)) {
        $ctx.ScriptPath = [string]$Context.ScriptPath
        $ctx.PathContext = $null
    }

    try {
        $staticEvalState = Get-StaticEvalState -Context $ctx
        if ($staticEvalState) {
            $staticEvalState.ValueDepthLimit = 64
            $staticEvalState.StringCompatDepthLimit = 48
        }
        $ctx.SafeMode = $true

        [void](Initialize-WholeScriptStaticAssignments -Statements $statements -Context $ctx)
        foreach ($statement in @($statements)) {
            try {
                [void](Invoke-WholeScriptStaticStatement -Statement $statement -Context $ctx -AllowEmptyFallback:$false)
            } catch {
            }
        }

        $evidence = New-Object 'System.Collections.Generic.List[object]'
        Add-SensitiveArtifactEvidenceFromContext -Context $ctx -EvidenceList $evidence
        Add-SensitivePropertyBagEvidenceFromParse -ParseAst $parse.Ast -Context $ctx -EvidenceList $evidence

        $normalized = @()
        foreach ($entry in @(Get-UniqueSensitiveEvidenceRecords -Evidence ($evidence.ToArray()))) {
            if ($null -eq $entry) { continue }
            $normalized += [PSCustomObject]@{
                Kind       = [string]$entry.Kind
                Value      = [string]$entry.Value
                Source     = if ($entry.PSObject.Properties['Source'] -and -not [string]::IsNullOrWhiteSpace([string]$entry.Source)) { [string]$entry.Source } else { $Source }
                Stage      = $Stage
                Confidence = if ($entry.PSObject.Properties['Confidence']) { [string]$entry.Confidence } else { 'High' }
                PreserveLiteral = if ($entry.PSObject.Properties['PreserveLiteral']) { [bool]$entry.PreserveLiteral } else { $false }
            }
        }

        return @($normalized)
    } finally {
        Close-WholeScriptStaticResolutionContext -Context $ctx
    }
}

function Get-WholeScriptNormalizedPayloadInfo {
    param(
        [AllowNull()][string]$Text,
        [AllowNull()][string]$OriginalText,
        [string]$Source = 'helper_payload'
    )

    $candidate = Remove-RecoveredTextTransportArtifacts -Text $Text
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        return $null
    }

    $working = $candidate
    $scriptText = $null
    for ($i = 0; $i -lt 3; $i++) {
        $normalized = Try-NormalizeRecoveredScriptText -Text $working
        if ($normalized) {
            $scriptText = $normalized
            break
        }

        $payloadInfo = Resolve-WholeScriptHostPayloadInfo -ScriptText $working
        if (-not $payloadInfo -or [string]::IsNullOrWhiteSpace([string]$payloadInfo.PayloadText)) {
            break
        }

        $nextText = Remove-RecoveredTextTransportArtifacts -Text ([string]$payloadInfo.PayloadText)
        if ([string]::IsNullOrWhiteSpace($nextText)) {
            break
        }

        if ((Get-NormalizedScriptComparisonText -ScriptText $nextText) -eq (Get-NormalizedScriptComparisonText -ScriptText $working)) {
            break
        }

        $working = $nextText
    }

    $evidence = @(Get-WholeScriptSensitiveEvidenceFromText -Text $candidate -Source $Source -Stage 'whole_script_helper')
    if ($scriptText) {
        $finalText = Get-WholeScriptReplacementCandidateText -OriginalText $OriginalText -CandidateText $scriptText
        if ($finalText) {
            return [PSCustomObject]@{
                ScriptText = [string]$finalText
                Evidence   = @($evidence)
            }
        }
    }

    if ($evidence.Count -gt 0) {
        $body = if (-not [string]::IsNullOrWhiteSpace($OriginalText)) { [string]$OriginalText } else { [string]$candidate }
        return [PSCustomObject]@{
            ScriptText = (Append-SensitiveEvidenceCommentBlock -ScriptText $body -Evidence $evidence)
            Evidence   = @($evidence)
        }
    }

    return $null
}

function Try-NormalizeRecoveredScriptText {
    param([AllowNull()][string]$Text)

    $originalInput = Remove-RecoveredTextTransportArtifacts -Text (Get-SafeNonEmptyString -Value $Text)
    $candidate = $originalInput
    if (-not $candidate) {
        return $null
    }

    for ($i = 0; $i -lt 4; $i++) {
        $payloadInfo = Resolve-WholeScriptHostPayloadInfo -ScriptText $candidate
        if (-not $payloadInfo) { break }

        $payloadText = Get-WholeScriptReplacementCandidateText -OriginalText $candidate -CandidateText $payloadInfo.PayloadText
        if (-not $payloadText) { break }

        if ((Get-NormalizedScriptComparisonText -ScriptText $payloadText) -eq (Get-NormalizedScriptComparisonText -ScriptText $candidate)) {
            break
        }

        $candidate = Remove-RecoveredTextTransportArtifacts -Text $payloadText
        if (-not $candidate) {
            break
        }
    }

    $normalized = Invoke-NormalizePlainScriptText -ScriptText $candidate
    if (-not [string]::IsNullOrWhiteSpace($normalized)) {
        $candidate = Remove-RecoveredTextTransportArtifacts -Text $normalized
    }

    if (-not (Test-UsefulRecoveredScriptText -Text $candidate)) {
        return $null
    }

    return (Get-WholeScriptReplacementCandidateText -OriginalText $originalInput -CandidateText $candidate)
}

function Test-RecoveredScriptLooksWrapperLiteral {
    param([AllowNull()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $false
    }

    if ($Text -match '(?is)^\s*@\(\s*\[char\]') {
        return $true
    }

    $charMatches = [regex]::Matches($Text, '\[char\]', 'IgnoreCase')
    return ($charMatches.Count -ge 8)
}

function Test-WholeScriptEvalFallbackCommandAllowed {
    param([string]$CommandName)

    if ([string]::IsNullOrWhiteSpace($CommandName)) { return $false }
    return ($CommandName -match '^(?i:set-variable|sv|new-variable|nv|set-item|si|get-variable|gv|variable|get-item|gi|item|foreach-object|foreach|%|new-object|join-path|get-location|gl|pwd|out-null)$')
}

function Test-WholeScriptPureLocalHelperCommandAllowed {
    param([string]$CommandName)

    if ([string]::IsNullOrWhiteSpace($CommandName)) { return $false }
    if (Test-WholeScriptEvalFallbackCommandAllowed -CommandName $CommandName) {
        return $true
    }

    return ($CommandName -match '^(?i:get-random|random)$')
}

function Test-WholeScriptEvalFallbackMemberAllowed {
    param($Ast)

    if ($null -eq $Ast) { return $false }

    $memberName = Get-StaticMemberNameText -MemberAst $Ast.Member -Context $null
    if ([string]::IsNullOrWhiteSpace($memberName)) { return $false }

    if ($Ast -is [System.Management.Automation.Language.InvokeMemberExpressionAst]) {
        if ($Ast.Static) {
            if ($Ast.Expression -isnot [System.Management.Automation.Language.TypeExpressionAst]) {
                return $false
            }

            $targetType = Resolve-StaticTypeFromTypeExpressionAst -TypeExpressionAst $Ast.Expression
            if ($null -eq $targetType) { return $false }

            if (($targetType -eq [string] -or $targetType.FullName -eq 'System.String') -and $memberName -match '^(?i:Join)$') {
                return $true
            }
            if (($targetType -eq [regex] -or $targetType.FullName -eq 'System.Text.RegularExpressions.Regex') -and $memberName -match '^(?i:Matches)$') {
                return $true
            }
            if (($targetType -eq [array] -or $targetType.FullName -eq 'System.Array') -and $memberName -match '^(?i:Reverse)$') {
                return $true
            }
            if (($targetType -eq [convert] -or $targetType.FullName -eq 'System.Convert') -and
                $memberName -match '^(?i:FromBase64String|ToBase64String)$') {
                return $true
            }
            if ($targetType.FullName -match '^(?i:System\.Text\.Encoding)$' -and $memberName -match '^(?i:UTF8|Unicode|BigEndianUnicode|ASCII|Default|UTF32)$') {
                return $true
            }

            return $false
        }

        return ($memberName -match '^(?i:Replace|Substring|ToString|ToLower|ToUpper|Trim|TrimEnd|Split|ToCharArray|GetBytes|GetString|ReadToEnd|Read|Write|Seek|Invoke|Flush|Close|Dispose|TransformFinalBlock|CreateDecryptor|CreateEncryptor|Clear)$')
    }

    if ($Ast -is [System.Management.Automation.Language.MemberExpressionAst] -and $Ast.Static) {
        if ($Ast.Expression -isnot [System.Management.Automation.Language.TypeExpressionAst]) {
            return $false
        }

        $targetType = Resolve-StaticTypeFromTypeExpressionAst -TypeExpressionAst $Ast.Expression
        if ($null -eq $targetType) { return $false }
        return ($targetType -eq [string] -or $targetType -eq [regex] -or $targetType -eq [array] -or
            $targetType.FullName -in @('System.String', 'System.Text.RegularExpressions.Regex', 'System.Array') -or
            ($targetType.FullName -eq 'System.Text.Encoding') -or
            ($targetType.IsEnum -and $targetType.FullName -match '^(?i:System\.Security\.Cryptography\.)'))
    }

    return $true
}

function Test-WholeScriptEvalFallbackCommandAstAllowed {
    param([System.Management.Automation.Language.CommandAst]$CommandAst)

    if ($null -eq $CommandAst) { return $false }

    $cmdName = Convert-DynamicCommandCandidateToName -Value $CommandAst.GetCommandName()
    if (-not [string]::IsNullOrWhiteSpace($cmdName)) {
        if (Test-WholeScriptEvalFallbackCommandAllowed -CommandName $cmdName) {
            return $true
        }
        if (Test-WholeScriptLocalHelperNameAllowed -Name $cmdName) {
            return $true
        }
    }

    return $false
}

function Test-WholeScriptLocalHelperNameAllowed {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    return ($Name -match '^(?i:de|dec)$' -or
        $Name -match '(?i)(decode|decrypt|unwrap|inflate|expand|unpack|join|build|compose|recover|derive|byte|char|xor|bxor|rot|perm|shuffle|aes|rc4|crypto|plain|text|string)')
}

function Test-WholeScriptLocalHelperFunctionAllowed {
    param([System.Management.Automation.Language.FunctionDefinitionAst]$FunctionAst)

    if ($null -eq $FunctionAst -or [string]::IsNullOrWhiteSpace([string]$FunctionAst.Name)) {
        return $false
    }
    if (-not (Test-WholeScriptLocalHelperNameAllowed -Name ([string]$FunctionAst.Name))) {
        return $false
    }

    $text = if ($FunctionAst.Extent) { [string]$FunctionAst.Extent.Text } else { '' }
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $false
    }
    if ($text -match '(?i)\b(?:Invoke-Expression|iex|Start-Process|cmd(?:\.exe)?|powershell(?:\.exe)?|pwsh(?:\.exe)?|Invoke-WebRequest|Invoke-RestMethod|Start-BitsTransfer|Download(?:String|File)|Remove-Item|Add-Type|VirtualAlloc|WriteProcessMemory|CreateThread)\b') {
        return $false
    }

    $allowedTypePrefixes = @(
        'string',
        'array',
        'convert',
        'system\.convert',
        'system\.text\.encoding',
        'system\.io\.memorystream',
        'system\.io\.compression\.',
        'system\.security\.cryptography\.',
        'system\.bitconverter',
        'system\.math',
        'byte\[\]',
        'char\[\]',
        'int\[\]',
        'int',
        'byte',
        'char'
    )

    $typeMatches = @([regex]::Matches($text, '\[(?<type>[A-Za-z_][\w\.\[\]]+)\]'))
    foreach ($typeMatch in $typeMatches) {
        $typeName = [string]$typeMatch.Groups['type'].Value
        if ([string]::IsNullOrWhiteSpace($typeName)) { continue }
        $ok = $false
        foreach ($prefix in $allowedTypePrefixes) {
            if ($typeName -match ("^(?i:" + $prefix + ")")) {
                $ok = $true
                break
            }
        }
        if (-not $ok) {
            return $false
        }
    }

    try {
        $nodes = @($FunctionAst.FindAll({ $true }, $true))
    } catch {
        return $false
    }

    foreach ($node in $nodes) {
        if ($node -is [System.Management.Automation.Language.TrapStatementAst] -or
            $node -is [System.Management.Automation.Language.TryStatementAst]) {
            return $false
        }
        if ($node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node -ne $FunctionAst) {
            return $false
        }

        if ($node -is [System.Management.Automation.Language.CommandAst]) {
            if (-not (Test-WholeScriptEvalFallbackCommandAstAllowed -CommandAst $node)) {
                return $false
            }
            continue
        }

        if ($node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -or
            $node -is [System.Management.Automation.Language.MemberExpressionAst]) {
            if (-not (Test-WholeScriptEvalFallbackMemberAllowed -Ast $node)) {
                return $false
            }
        }
    }

    return $true
}

function Get-WholeScriptSafeLocalHelperStatements {
    param([object[]]$Statements = @())

    $helpers = New-Object System.Collections.Generic.List[object]
    foreach ($statement in @($Statements)) {
        if ($statement -isnot [System.Management.Automation.Language.FunctionDefinitionAst]) {
            break
        }
        if (-not (Test-WholeScriptLocalHelperFunctionAllowed -FunctionAst $statement)) {
            return @()
        }
        $helpers.Add($statement) | Out-Null
    }

    return @($helpers.ToArray())
}

function Test-WholeScriptEvalFallbackAllowed {
    param(
        $Ast,
        [bool]$AllowFunctionDefinitions = $false
    )

    if ($null -eq $Ast) { return $false }
    if (-not $Ast.PSObject.Methods['FindAll']) { return $false }

    try {
        $nodes = @($Ast.FindAll({ $true }, $true))
    } catch {
        return $false
    }

    foreach ($node in $nodes) {
        if ($node -is [System.Management.Automation.Language.TrapStatementAst] -or
            $node -is [System.Management.Automation.Language.TryStatementAst]) {
            return $false
        }

        if ($node -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
            if (-not $AllowFunctionDefinitions) {
                return $false
            }
            if (-not (Test-WholeScriptLocalHelperFunctionAllowed -FunctionAst $node)) {
                return $false
            }
            continue
        }

        if ($node -is [System.Management.Automation.Language.CommandAst]) {
            if (-not (Test-WholeScriptEvalFallbackCommandAstAllowed -CommandAst $node)) {
                return $false
            }
            continue
        }

        if ($node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -or
            $node -is [System.Management.Automation.Language.MemberExpressionAst]) {
            if (-not (Test-WholeScriptEvalFallbackMemberAllowed -Ast $node)) {
                return $false
            }
        }
    }

    return $true
}

function Try-EvaluateWholeScriptPayloadExpression {
    param(
        [object[]]$PrefixStatements = @(),
        $ExpressionAst,
        [int]$TimeoutMs = 4000,
        [bool]$SafeMode = $true,
        [ValidateSet('Disabled', 'Conservative', 'Balanced', 'Aggressive')]
        [string]$PreExecutionGateMode = 'Disabled',
        [hashtable]$PreExecutionGateCache = $null
    )

    if ($null -eq $ExpressionAst) {
        return $null
    }
    if ($SafeMode) {
        return $null
    }

    foreach ($statement in @($PrefixStatements)) {
        if (-not (Test-WholeScriptEvalFallbackAllowed -Ast $statement)) {
            return $null
        }
    }
    if (-not (Test-WholeScriptEvalFallbackAllowed -Ast $ExpressionAst)) {
        return $null
    }

    $gateTextParts = New-Object 'System.Collections.Generic.List[string]'
    foreach ($statement in @($PrefixStatements)) {
        if ($statement -and $statement.Extent) {
            $gateTextParts.Add([string]$statement.Extent.Text) | Out-Null
        }
    }
    if ($ExpressionAst -and $ExpressionAst.Extent) {
        $gateTextParts.Add([string]$ExpressionAst.Extent.Text) | Out-Null
    }
    $gateText = ($gateTextParts.ToArray() -join [Environment]::NewLine)
    $helperGate = Get-PreExecutionGateDecision -Scope 'WholeScriptHelper' -ScriptText $gateText -Mode $PreExecutionGateMode -SafeMode:$SafeMode -Cache $PreExecutionGateCache
    if ([string]$helperGate.Decision -eq 'Stop') {
        return $null
    }

    $execContext = $null
    try {
        $execContext = New-ExecutionContext
    } catch {
        $execContext = $null
    }
    if (-not $execContext) {
        return $null
    }
    Initialize-WholeScriptSpecialVariables -ExecContext $execContext

    try {
        foreach ($statement in @($PrefixStatements)) {
            if ($null -eq $statement -or -not $statement.Extent) {
                return $null
            }

            $statementResult = Invoke-InContext -ExecContext $execContext -Code ([string]$statement.Extent.Text) -TimeoutMs $TimeoutMs -PersistOnSuccess:$true
            if (-not $statementResult.Success) {
                return $null
            }
        }

        if (-not $ExpressionAst.Extent) {
            return $null
        }

        $exprText = [string]$ExpressionAst.Extent.Text
        if ([string]::IsNullOrWhiteSpace($exprText)) {
            return $null
        }

        $evalCode = @"
`$__psdissect_payload = @(& {
$exprText
})
[pscustomobject]@{ Payload = `$__psdissect_payload }
"@

        $evalResult = Invoke-InContext -ExecContext $execContext -Code $evalCode -TimeoutMs $TimeoutMs -PersistOnSuccess:$false
        if (-not $evalResult.Success -or -not $evalResult.Result -or @($evalResult.Result).Count -eq 0) {
            return $null
        }

        $payloadContainer = @($evalResult.Result)[-1]
        $payloadItems = @()
        if ($payloadContainer -and $payloadContainer.PSObject.Properties['Payload']) {
            $payloadItems = @($payloadContainer.Payload)
        } else {
            $payloadItems = @($evalResult.Result)
        }

        if ($payloadItems.Count -eq 0) {
            return $null
        }

        if ($payloadItems.Count -eq 1) {
            return (Convert-WholeScriptHelperPayloadToCandidateText -Value $payloadItems[0])
        }

        return (Convert-WholeScriptHelperPayloadToCandidateText -Value @($payloadItems))
    } finally {
        if ($execContext) {
            try {
                Close-ExecutionContext -ExecContext $execContext
            } catch {
            }
        }
    }
}

function Try-EvaluateWholeScriptPayloadExpressionWithLocalHelpers {
    param(
        [object[]]$PrefixStatements = @(),
        $ExpressionAst,
        [int]$TimeoutMs = 4000,
        [bool]$SafeMode = $true,
        [ValidateSet('Disabled', 'Conservative', 'Balanced', 'Aggressive')]
        [string]$PreExecutionGateMode = 'Disabled',
        [hashtable]$PreExecutionGateCache = $null
    )

    $result = Try-EvaluateWholeScriptPayloadExpression -PrefixStatements $PrefixStatements -ExpressionAst $ExpressionAst -TimeoutMs $TimeoutMs -SafeMode:$SafeMode -PreExecutionGateMode $PreExecutionGateMode -PreExecutionGateCache $PreExecutionGateCache
    if ($result) {
        return $result
    }
    if ($SafeMode) {
        return $null
    }

    $helperStatements = @(Get-WholeScriptSafeLocalHelperStatements -Statements $PrefixStatements)
    if ($helperStatements.Count -eq 0) {
        return $null
    }

    $remainingPrefix = @()
    if ($PrefixStatements.Count -gt $helperStatements.Count) {
        $remainingPrefix = @($PrefixStatements | Select-Object -Skip $helperStatements.Count)
    }

    foreach ($statement in @($remainingPrefix)) {
        if (-not (Test-WholeScriptEvalFallbackAllowed -Ast $statement)) {
            return $null
        }
    }
    if (-not (Test-WholeScriptEvalFallbackAllowed -Ast $ExpressionAst)) {
        return $null
    }

    $gateTextParts = New-Object 'System.Collections.Generic.List[string]'
    foreach ($statement in @($helperStatements + $remainingPrefix)) {
        if ($statement -and $statement.Extent) {
            $gateTextParts.Add([string]$statement.Extent.Text) | Out-Null
        }
    }
    if ($ExpressionAst -and $ExpressionAst.Extent) {
        $gateTextParts.Add([string]$ExpressionAst.Extent.Text) | Out-Null
    }
    $gateText = ($gateTextParts.ToArray() -join [Environment]::NewLine)
    $helperGate = Get-PreExecutionGateDecision -Scope 'WholeScriptHelper' -ScriptText $gateText -Mode $PreExecutionGateMode -SafeMode:$SafeMode -Cache $PreExecutionGateCache
    if ([string]$helperGate.Decision -eq 'Stop') {
        return $null
    }

    $execContext = $null
    try {
        $execContext = New-ExecutionContext
    } catch {
        $execContext = $null
    }
    if (-not $execContext) {
        return $null
    }
    Initialize-WholeScriptSpecialVariables -ExecContext $execContext

    try {
        foreach ($statement in @($helperStatements + $remainingPrefix)) {
            if ($null -eq $statement -or -not $statement.Extent) {
                return $null
            }

            $statementResult = Invoke-InContext -ExecContext $execContext -Code ([string]$statement.Extent.Text) -TimeoutMs $TimeoutMs -PersistOnSuccess:$true
            if (-not $statementResult.Success) {
                return $null
            }
        }

        if (-not $ExpressionAst.Extent) {
            return $null
        }

        $exprText = [string]$ExpressionAst.Extent.Text
        if ([string]::IsNullOrWhiteSpace($exprText)) {
            return $null
        }

        $evalCode = @"
`$__psdissect_payload = @(& {
$exprText
})
[pscustomobject]@{ Payload = `$__psdissect_payload }
"@

        $evalResult = Invoke-InContext -ExecContext $execContext -Code $evalCode -TimeoutMs $TimeoutMs -PersistOnSuccess:$false
        if (-not $evalResult.Success -or -not $evalResult.Result -or @($evalResult.Result).Count -eq 0) {
            return $null
        }

        $payloadContainer = @($evalResult.Result)[-1]
        $payloadItems = @()
        if ($payloadContainer -and $payloadContainer.PSObject.Properties['Payload']) {
            $payloadItems = @($payloadContainer.Payload)
        } else {
            $payloadItems = @($evalResult.Result)
        }

        if ($payloadItems.Count -eq 0) {
            return $null
        }

        if ($payloadItems.Count -eq 1) {
            return (Convert-WholeScriptHelperPayloadToCandidateText -Value $payloadItems[0])
        }

        return (Convert-WholeScriptHelperPayloadToCandidateText -Value @($payloadItems))
    } finally {
        if ($execContext) {
            try {
                Close-ExecutionContext -ExecContext $execContext
            } catch {
            }
        }
    }
}

function Try-EvaluateWholeScriptExpressionInExecContext {
    param(
        $ExecContext,
        $ExpressionAst,
        [int]$TimeoutMs = 4000
    )

    if ($null -eq $ExecContext -or $null -eq $ExecContext.Runspace -or $null -eq $ExpressionAst -or -not $ExpressionAst.Extent) {
        return $null
    }

    $exprText = [string]$ExpressionAst.Extent.Text
    if ([string]::IsNullOrWhiteSpace($exprText)) {
        return $null
    }

    $evalCode = @"
`$__psdissect_payload = @(& {
$exprText
})
[pscustomobject]@{ Payload = `$__psdissect_payload }
"@

    $evalResult = Invoke-InContext -ExecContext $ExecContext -Code $evalCode -TimeoutMs $TimeoutMs -PersistOnSuccess:$false
    if (-not $evalResult.Success -or -not $evalResult.Result -or @($evalResult.Result).Count -eq 0) {
        return $null
    }

    $payloadContainer = @($evalResult.Result)[-1]
    $payloadItems = @()
    if ($payloadContainer -and $payloadContainer.PSObject.Properties['Payload']) {
        $payloadItems = @($payloadContainer.Payload)
    } else {
        $payloadItems = @($evalResult.Result)
    }

    if ($payloadItems.Count -eq 0) {
        return $null
    }

    if ($payloadItems.Count -eq 1) {
        return (Convert-WholeScriptHelperPayloadToCandidateText -Value $payloadItems[0])
    }

    return (Convert-WholeScriptHelperPayloadToCandidateText -Value @($payloadItems))
}

function Get-WholeScriptAstCommandNames {
    param($Ast)

    if ($null -eq $Ast -or -not $Ast.PSObject.Methods['FindAll']) {
        return @()
    }

    $names = New-Object 'System.Collections.Generic.List[string]'
    try {
        $commandAsts = @($Ast.FindAll({
                    param($n)
                    $n -is [System.Management.Automation.Language.CommandAst]
                }, $true))
    } catch {
        return @()
    }

    foreach ($commandAst in @($commandAsts)) {
        $cmdName = Convert-DynamicCommandCandidateToName -Value $commandAst.GetCommandName()
        if ([string]::IsNullOrWhiteSpace($cmdName)) {
            continue
        }
        if ($names -notcontains [string]$cmdName) {
            $names.Add([string]$cmdName) | Out-Null
        }
    }

    return @($names.ToArray())
}

function Get-AssignmentTargetVariableName {
    param($LeftAst)

    if ($null -eq $LeftAst) {
        return $null
    }

    if ($LeftAst -is [System.Management.Automation.Language.VariableExpressionAst]) {
        return [string]$LeftAst.VariablePath.UserPath
    }

    if ($LeftAst.PSObject.Properties['Child']) {
        return (Get-AssignmentTargetVariableName -LeftAst $LeftAst.Child)
    }

    return $null
}

function Get-GatedRoundDynamicIexArgumentAst {
    param($Statement)

    if ($null -eq $Statement) {
        return $null
    }

    if ($Statement -is [System.Management.Automation.Language.PipelineAst]) {
        $elements = @($Statement.PipelineElements)
        if ($elements.Count -eq 2 -and $elements[1] -is [System.Management.Automation.Language.CommandAst]) {
            $sinkName = Convert-DynamicCommandCandidateToName -Value $elements[1].GetCommandName()
            if ($sinkName -in @('Invoke-Expression', 'iex')) {
                if ($elements[0] -is [System.Management.Automation.Language.CommandExpressionAst]) {
                    return $elements[0].Expression
                }
                if ($elements[0].PSObject.Properties['Expression']) {
                    return $elements[0].Expression
                }
            }
        }

        if ($elements.Count -eq 1 -and $elements[0] -is [System.Management.Automation.Language.CommandAst]) {
            $Statement = $elements[0]
        } else {
            return $null
        }
    }

    if ($Statement -isnot [System.Management.Automation.Language.CommandAst]) {
        return $null
    }

    $dynamicInfo = $null
    try {
        $dynamicInfo = Get-CommandAstStaticDynamicPayloadInfo -CommandAst $Statement -Context $null
    } catch {
        $dynamicInfo = $null
    }

    if ($dynamicInfo -and [string]$dynamicInfo.DynamicType -eq 'IEX' -and $dynamicInfo.ArgumentAst) {
        return $dynamicInfo.ArgumentAst
    }

    $cmdName = Convert-DynamicCommandCandidateToName -Value $Statement.GetCommandName()
    if ($cmdName -in @('Invoke-Expression', 'iex')) {
        return (Get-CommandArgumentAst -CommandAst $Statement)
    }

    return $null
}

function Get-WholeScriptContiguousWhitelistedHelperPrefixStatements {
    param(
        [object[]]$Statements = @(),
        [int]$BeforeIndex,
        [int]$MaxStatements = 24
    )

    if ($BeforeIndex -le 0 -or $Statements.Count -eq 0) {
        return @()
    }

    $selected = New-Object 'System.Collections.Generic.List[object]'
    for ($i = $BeforeIndex - 1; $i -ge 0; $i--) {
        $statement = $Statements[$i]
        if ($null -eq $statement -or -not $statement.Extent) {
            if ($selected.Count -gt 0) {
                break
            }
            continue
        }

        if (Test-WholeScriptEvalFallbackAllowed -Ast $statement -AllowFunctionDefinitions:$true) {
            if ($selected.Count -ge $MaxStatements) {
                break
            }
            $selected.Add($statement) | Out-Null
            continue
        }

        if ($selected.Count -gt 0) {
            break
        }
    }

    if ($selected.Count -eq 0) {
        return @()
    }

    $ordered = New-Object 'System.Collections.Generic.List[object]'
    for ($j = $selected.Count - 1; $j -ge 0; $j--) {
        $ordered.Add($selected[$j]) | Out-Null
    }

    return @($ordered.ToArray())
}

function Test-WholeScriptWhitelistedIexExpansionCandidate {
    param(
        [object[]]$PrefixStatements = @(),
        $ExpressionAst
    )

    $parts = New-Object 'System.Collections.Generic.List[string]'
    foreach ($statement in @($PrefixStatements)) {
        if ($statement -and $statement.Extent -and -not [string]::IsNullOrWhiteSpace([string]$statement.Extent.Text)) {
            $parts.Add([string]$statement.Extent.Text) | Out-Null
        }
    }
    if ($ExpressionAst -and $ExpressionAst.Extent -and -not [string]::IsNullOrWhiteSpace([string]$ExpressionAst.Extent.Text)) {
        $parts.Add([string]$ExpressionAst.Extent.Text) | Out-Null
    }

    $text = ($parts.ToArray() -join [Environment]::NewLine)
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $false
    }

    if ($text -notmatch '(?i)(FromBase64String|ToBase64String|GZipStream|DeflateStream|MemoryStream|StreamReader|ReadToEnd|GetBytes|GetString|TransformFinalBlock|CreateDecryptor|CreateEncryptor)') {
        return $false
    }

    if ($text -match '(?i)\b(?:Invoke-Expression|iex|Start-Process|Invoke-WebRequest|Invoke-RestMethod|Download(?:String|File)|Start-BitsTransfer|cmd(?:\.exe)?|powershell(?:\.exe)?|pwsh(?:\.exe)?|mshta(?:\.exe)?|rundll32(?:\.exe)?|regsvr32(?:\.exe)?|schtasks(?:\.exe)?|Remove-Item|Set-Content|Add-Content|New-Item|Set-ItemProperty)\b') {
        return $false
    }

    return $true
}

function Test-WholeScriptPureLocalHelperFunctionAllowed {
    param([System.Management.Automation.Language.FunctionDefinitionAst]$FunctionAst)

    if ($null -eq $FunctionAst -or [string]::IsNullOrWhiteSpace([string]$FunctionAst.Name)) {
        return $false
    }

    $text = if ($FunctionAst.Extent) { [string]$FunctionAst.Extent.Text } else { '' }
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $false
    }
    if ($text.Length -gt 8192) {
        return $false
    }

    $lineCount = ([regex]::Matches($text, "`r?`n")).Count + 1
    if ($lineCount -gt 96) {
        return $false
    }

    if ($text -match '(?i)\b(?:Invoke-Expression|iex|Start-Process|cmd(?:\.exe)?|powershell(?:\.exe)?|pwsh(?:\.exe)?|Invoke-WebRequest|Invoke-RestMethod|Start-BitsTransfer|Download(?:String|File)|Remove-Item|Set-Content|Add-Content|Clear-Content|Out-File|Copy-Item|Move-Item|Rename-Item|New-Item|Set-ItemProperty|Remove-ItemProperty|New-ItemProperty|Add-Type|VirtualAlloc|WriteProcessMemory|CreateThread)\b') {
        return $false
    }

    try {
        $nodes = @($FunctionAst.FindAll({ $true }, $true))
    } catch {
        return $false
    }

    if ($nodes.Count -gt 320) {
        return $false
    }

    foreach ($node in $nodes) {
        if ($node -is [System.Management.Automation.Language.TrapStatementAst] -or
            $node -is [System.Management.Automation.Language.TryStatementAst]) {
            return $false
        }
        if ($node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node -ne $FunctionAst) {
            return $false
        }

        if ($node -is [System.Management.Automation.Language.CommandAst]) {
            $cmdName = Convert-DynamicCommandCandidateToName -Value $node.GetCommandName()
            if (-not (Test-WholeScriptPureLocalHelperCommandAllowed -CommandName $cmdName)) {
                return $false
            }
            continue
        }

        if ($node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -or
            $node -is [System.Management.Automation.Language.MemberExpressionAst]) {
            if (-not (Test-WholeScriptEvalFallbackMemberAllowed -Ast $node)) {
                return $false
            }
        }
    }

    return $true
}

function Try-EvaluateWhitelistedWholeScriptPayloadExpression {
    param(
        [object[]]$PrefixStatements = @(),
        $ExpressionAst,
        [int]$TimeoutMs = 4000
    )

    if ($null -eq $ExpressionAst -or -not $ExpressionAst.Extent) {
        return $null
    }

    foreach ($statement in @($PrefixStatements)) {
        if (-not (Test-WholeScriptEvalFallbackAllowed -Ast $statement -AllowFunctionDefinitions:$true)) {
            return $null
        }
    }
    if (-not (Test-WholeScriptEvalFallbackAllowed -Ast $ExpressionAst)) {
        return $null
    }
    if (-not (Test-WholeScriptWhitelistedIexExpansionCandidate -PrefixStatements $PrefixStatements -ExpressionAst $ExpressionAst)) {
        return $null
    }

    $execContext = $null
    try {
        $execContext = New-ExecutionContext
    } catch {
        $execContext = $null
    }
    if (-not $execContext) {
        return $null
    }
    Initialize-WholeScriptSpecialVariables -ExecContext $execContext

    try {
        foreach ($statement in @($PrefixStatements)) {
            if ($null -eq $statement -or -not $statement.Extent) {
                return $null
            }

            $statementResult = Invoke-InContext -ExecContext $execContext -Code ([string]$statement.Extent.Text) -TimeoutMs $TimeoutMs -PersistOnSuccess:$true
            if (-not $statementResult.Success) {
                return $null
            }
        }

        return (Try-EvaluateWholeScriptExpressionInExecContext -ExecContext $execContext -ExpressionAst $ExpressionAst -TimeoutMs $TimeoutMs)
    } finally {
        if ($execContext) {
            try {
                Close-ExecutionContext -ExecContext $execContext
            } catch {
            }
        }
    }
}

function Convert-TextToPowerShellLiteralHereString {
    param([AllowNull()][string]$Text)

    $body = if ($null -eq $Text) { '' } else { [string]$Text }
    $body = $body -replace "`r?`n", "`r`n"

    if ($body -notmatch "(?m)^'@\\s*$") {
        return "@'`r`n$body`r`n'@"
    }

    if ($body -notmatch '(?m)^"@\s*$') {
        return "@""`r`n$body`r`n""@"
    }

    return "@'`r`n$body`r`n'@"
}

function Get-WhitelistedRecoveredPayloadCandidateText {
    param([AllowNull()][string]$Text)

    $payloadText = Try-NormalizeRecoveredScriptText -Text $Text
    if (-not [string]::IsNullOrWhiteSpace($payloadText)) {
        return [string]$payloadText
    }

    $rawText = Remove-RecoveredTextTransportArtifacts -Text $Text
    if ([string]::IsNullOrWhiteSpace($rawText)) {
        return $null
    }

    $syntax = Test-PowerShellSyntax -ScriptText $rawText
    if (-not $syntax.IsValid) {
        return $null
    }
    if (-not (Test-UsefulRecoveredScriptText -Text $rawText)) {
        return $null
    }

    return ($rawText.TrimEnd() + "`r`n")
}

function Test-WhitelistedIexHelperLineText {
    param([AllowNull()][string]$LineText)

    if ([string]::IsNullOrWhiteSpace($LineText)) {
        return $true
    }

    $trim = $LineText.Trim()
    if ([string]::IsNullOrWhiteSpace($trim)) {
        return $true
    }

    if ($trim -match '(?i)\b(?:Invoke-Expression|iex|Start-Process|Invoke-WebRequest|Invoke-RestMethod|Download(?:String|File)|Start-BitsTransfer|cmd(?:\.exe)?|powershell(?:\.exe)?|pwsh(?:\.exe)?|mshta(?:\.exe)?|rundll32(?:\.exe)?|regsvr32(?:\.exe)?|schtasks(?:\.exe)?|taskkill(?:\.exe)?|Remove-Item|Set-Content|Add-Content|New-Item|Set-ItemProperty)\b') {
        return $false
    }

    return ($trim -match '(?i)(FromBase64String|ToBase64String|GZipStream|DeflateStream|MemoryStream|StreamReader|ReadToEnd|New-Object|Set-Variable|Get-Item|Get-Variable|Out-Null|CompressionMode|::Decompress|\.Invoke\(|\.Write|\.Seek|^\$[A-Za-z_][A-Za-z0-9_]*\s*=|^Clear-Host$)')
}

function Try-EvaluateWhitelistedHelperBlockVariableValue {
    param(
        [string[]]$BlockLines = @(),
        [Parameter(Mandatory)][string]$VariableName,
        [int]$TimeoutMs = 4000
    )

    if ([string]::IsNullOrWhiteSpace($VariableName) -or $VariableName -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
        return $null
    }

    $blockText = (@($BlockLines) -join "`r`n").Trim()
    if ([string]::IsNullOrWhiteSpace($blockText)) {
        return $null
    }

    if ($blockText -notmatch '(?i)(FromBase64String|GZipStream|DeflateStream|MemoryStream|StreamReader|ReadToEnd)') {
        return $null
    }

    $execContext = $null
    try {
        $execContext = New-ExecutionContext
    } catch {
        $execContext = $null
    }
    if ($execContext) {
        Initialize-WholeScriptSpecialVariables -ExecContext $execContext

        try {
            $runResult = Invoke-InContext -ExecContext $execContext -Code $blockText -TimeoutMs $TimeoutMs -PersistOnSuccess:$true
            if ($runResult.Success) {
                $evalCode = @"
`$__psdissect_payload = [string]`$$VariableName
[pscustomobject]@{ Payload = `$__psdissect_payload }
"@

                $evalResult = Invoke-InContext -ExecContext $execContext -Code $evalCode -TimeoutMs $TimeoutMs -PersistOnSuccess:$false
                if ($evalResult.Success -and $evalResult.Result -and @($evalResult.Result).Count -gt 0) {
                    $payloadContainer = @($evalResult.Result)[-1]
                    if ($payloadContainer -and $payloadContainer.PSObject.Properties['Payload']) {
                        return [string]$payloadContainer.Payload
                    }

                    return [string](@($evalResult.Result) -join [Environment]::NewLine)
                }
            }
        } finally {
            try {
                Close-ExecutionContext -ExecContext $execContext
            } catch {
            }
        }
    }

    $hostPath = $null
    try {
        $hostPath = (Get-Process -Id $PID -ErrorAction Stop).Path
    } catch {
        $hostPath = $null
    }
    if ([string]::IsNullOrWhiteSpace($hostPath) -or -not (Test-Path $hostPath)) {
        $hostPath = 'pwsh'
    }

    $tmpRoot = $null
    try {
        $scriptRoot = if (-not [string]::IsNullOrWhiteSpace($PSCommandPath)) { [System.IO.Path]::GetDirectoryName($PSCommandPath) } else { $null }
        if (-not [string]::IsNullOrWhiteSpace($scriptRoot)) {
            $tmpRoot = Join-Path $scriptRoot '__psdissect_runner_tmp'
            if (-not (Test-Path $tmpRoot)) {
                [System.IO.Directory]::CreateDirectory($tmpRoot) | Out-Null
            }
        }
    } catch {
        $tmpRoot = $null
    }
    if ([string]::IsNullOrWhiteSpace($tmpRoot)) {
        $tmpRoot = [System.IO.Path]::GetTempPath()
    }
    $tmpPath = Join-Path $tmpRoot ('psdissect-whitelist-' + [Guid]::NewGuid().ToString('N') + '.ps1')
    $outPath = Join-Path $tmpRoot ('psdissect-whitelist-' + [Guid]::NewGuid().ToString('N') + '.txt')
    $escapedOutPath = $outPath.Replace("'", "''")
    $runnerLines = @($BlockLines)
    $runnerLines += ('[System.IO.File]::WriteAllText(''' + $escapedOutPath + ''', [string]$' + $VariableName + ', [System.Text.UTF8Encoding]::new($false))')
    $runnerText = ($runnerLines -join "`r`n")
    try {
        [System.IO.File]::WriteAllText($tmpPath, $runnerText, [System.Text.UTF8Encoding]::new($false))

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $hostPath
        $psi.Arguments = ('-NoProfile -NonInteractive -File "{0}"' -f $tmpPath)
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true

        $proc = [System.Diagnostics.Process]::Start($psi)
        if ($null -eq $proc) {
            return $null
        }

        if (-not $proc.WaitForExit([Math]::Max(1000, $TimeoutMs))) {
            try {
                $proc.Kill($true)
            } catch {
            }
            return $null
        }

        if (-not (Test-Path $outPath)) {
            return $null
        }

        $stdout = [System.IO.File]::ReadAllText($outPath, [System.Text.UTF8Encoding]::new($false))
        if ([string]::IsNullOrWhiteSpace($stdout)) {
            return $null
        }

        return ($stdout.TrimEnd("`r", "`n"))
    } catch {
        return $null
    } finally {
        try {
            if (Test-Path $tmpPath) {
                Remove-Item -LiteralPath $tmpPath -Force -ErrorAction SilentlyContinue
            }
            if (Test-Path $outPath) {
                Remove-Item -LiteralPath $outPath -Force -ErrorAction SilentlyContinue
            }
        } catch {
        }
    }
}

function Invoke-ExpandWholeScriptLocalIexPayloadsTextFallback {
    param([Parameter(Mandatory)][string]$ScriptText)

    if ([string]::IsNullOrWhiteSpace($ScriptText)) {
        return $ScriptText
    }
    if ($ScriptText -notmatch '(?i)\b(?:Invoke-Expression|iex)\b' -or
        $ScriptText -notmatch '(?i)\.readtoend\(\)') {
        return $ScriptText
    }

    $lines = @([regex]::Split($ScriptText, "`r?`n"))
    if ($lines.Count -eq 0) {
        return $ScriptText
    }

    $replacements = New-Object 'System.Collections.Generic.List[object]'
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = [string]$lines[$i]
        $match = [regex]::Match($line, '^\s*(?<left>\$[A-Za-z_][A-Za-z0-9_]*)\s*=\s*\$[A-Za-z_][A-Za-z0-9_]*\.readtoend\(\)\s*$')
        if (-not $match.Success) {
            continue
        }

        $varToken = [string]$match.Groups['left'].Value
        $varName = $varToken.TrimStart('$')
        $hasIexUse = $false
        for ($lookAhead = $i + 1; $lookAhead -lt [Math]::Min($lines.Count, $i + 5); $lookAhead++) {
            $nextLine = [string]$lines[$lookAhead]
            if ([string]::IsNullOrWhiteSpace($nextLine)) {
                continue
            }
            if ($nextLine -match ('^\s*(?:Invoke-Expression|IEX)\s+' + [regex]::Escape($varToken) + '\s*$')) {
                $hasIexUse = $true
            }
            break
        }
        if (-not $hasIexUse) {
            continue
        }

        $helperRev = New-Object 'System.Collections.Generic.List[string]'
        $nonEmptyCount = 0
        for ($j = $i - 1; $j -ge 0; $j--) {
            $helperLine = [string]$lines[$j]
            if ([string]::IsNullOrWhiteSpace($helperLine)) {
                if ($helperRev.Count -gt 0) {
                    $helperRev.Add($helperLine) | Out-Null
                }
                continue
            }

            if (-not (Test-WhitelistedIexHelperLineText -LineText $helperLine)) {
                if ($helperRev.Count -gt 0) {
                    break
                }
                continue
            }

            $helperRev.Add($helperLine) | Out-Null
            $nonEmptyCount++
            if ($nonEmptyCount -ge 24) {
                break
            }
        }

        if ($helperRev.Count -eq 0) {
            continue
        }

        $helperLines = New-Object 'System.Collections.Generic.List[string]'
        for ($k = $helperRev.Count - 1; $k -ge 0; $k--) {
            $helperLines.Add([string]$helperRev[$k]) | Out-Null
        }
        $helperLines.Add($line) | Out-Null

        $evaluated = Try-EvaluateWhitelistedHelperBlockVariableValue -BlockLines $helperLines.ToArray() -VariableName $varName -TimeoutMs 4000
        $payloadText = Remove-RecoveredTextTransportArtifacts -Text $evaluated
        if ([string]::IsNullOrWhiteSpace($payloadText) -or $payloadText.Length -lt 64) {
            continue
        }

        $payloadSyntax = Test-PowerShellSyntax -ScriptText $payloadText
        if (-not $payloadSyntax.IsValid -or (Test-RecoveredScriptLooksWrapperLiteral -Text $payloadText)) {
            continue
        }

        $replacementLines = New-Object 'System.Collections.Generic.List[string]'
        $replacementLines.Add(($varToken + " = @'")) | Out-Null
        foreach ($payloadLine in @([regex]::Split($payloadText.TrimEnd("`r", "`n"), "`r?`n"))) {
            $replacementLines.Add([string]$payloadLine) | Out-Null
        }
        $replacementLines.Add("'@") | Out-Null

        $replacements.Add([PSCustomObject]@{
                LineIndex = $i
                Lines     = @($replacementLines.ToArray())
            }) | Out-Null
    }

    if ($replacements.Count -eq 0) {
        return $ScriptText
    }

    $mutableLines = New-Object 'System.Collections.Generic.List[string]'
    foreach ($entry in $lines) {
        $mutableLines.Add([string]$entry) | Out-Null
    }

    foreach ($replacement in @($replacements.ToArray() | Sort-Object LineIndex -Descending)) {
        $mutableLines.RemoveAt([int]$replacement.LineIndex)
        $insertAt = [int]$replacement.LineIndex
        $replacementLines = @($replacement.Lines)
        for ($lineIndex = $replacementLines.Count - 1; $lineIndex -ge 0; $lineIndex--) {
            $mutableLines.Insert($insertAt, [string]$replacementLines[$lineIndex])
        }
    }

    $result = ($mutableLines.ToArray() -join "`r`n")
    $check = Test-PowerShellSyntax -ScriptText $result
    if ($check.IsValid) {
        return $result
    }

    return $ScriptText
}

function Invoke-ExpandWholeScriptLocalIexPayloads {
    param(
        [Parameter(Mandatory)][string]$ScriptText,
        [ValidateSet('Disabled', 'Conservative', 'Balanced', 'Aggressive')]
        [string]$PreExecutionGateMode = 'Disabled',
        [hashtable]$PreExecutionGateCache = $null
    )

    if ([string]::IsNullOrWhiteSpace($ScriptText)) {
        return $ScriptText
    }

    if ($ScriptText -notmatch '(?i)\b(?:Invoke-Expression|iex)\b' -or
        $ScriptText -notmatch '(?i)(FromBase64String|GZipStream|DeflateStream|ReadToEnd|CreateDecryptor|TransformFinalBlock)') {
        return $ScriptText
    }

    $textFallback = Invoke-ExpandWholeScriptLocalIexPayloadsTextFallback -ScriptText $ScriptText
    if ((Get-NormalizedScriptComparisonText -ScriptText $textFallback) -ne (Get-NormalizedScriptComparisonText -ScriptText $ScriptText)) {
        return $textFallback
    }

    $parse = Get-ScriptParseInfo -ScriptText $ScriptText
    if (-not $parse.IsValid -or -not $parse.Ast) {
        return $ScriptText
    }

    $topLevelStatements = @(Get-TopLevelScriptStatementsFromText -ScriptText $ScriptText)
    if ($topLevelStatements.Count -eq 0) {
        return $ScriptText
    }

    $replacements = New-Object 'System.Collections.Generic.List[object]'
    $seenRanges = @{}

    for ($i = 0; $i -lt $topLevelStatements.Count; $i++) {
        if ($replacements.Count -ge 4) {
            break
        }

        $statement = $topLevelStatements[$i]
        $iexArgAst = Get-GatedRoundDynamicIexArgumentAst -Statement $statement
        if ($null -eq $iexArgAst -or -not $iexArgAst.Extent) {
            continue
        }

        $expressionAst = $iexArgAst
        $replaceStart = [int]$iexArgAst.Extent.StartOffset
        $replaceEnd = [int]$iexArgAst.Extent.EndOffset
        $replacementPrefix = $null

        if ($iexArgAst -is [System.Management.Automation.Language.VariableExpressionAst]) {
            $varName = [string]$iexArgAst.VariablePath.UserPath
            if (-not [string]::IsNullOrWhiteSpace($varName)) {
                for ($j = $i - 1; $j -ge 0; $j--) {
                    $candidateStatement = $topLevelStatements[$j]
                    if ($candidateStatement -isnot [System.Management.Automation.Language.AssignmentStatementAst]) {
                        continue
                    }

                    $targetVarName = Get-AssignmentTargetVariableName -LeftAst $candidateStatement.Left
                    if (-not [string]::Equals([string]$targetVarName, $varName, [System.StringComparison]::OrdinalIgnoreCase)) {
                        continue
                    }

                    if ($null -eq $candidateStatement.Right -or -not $candidateStatement.Right.Extent) {
                        break
                    }

                    $expressionAst = $candidateStatement.Right
                    $replaceStart = [int]$candidateStatement.Extent.StartOffset
                    $replaceEnd = [int]$candidateStatement.Extent.EndOffset
                    $replacementPrefix = [string]$candidateStatement.Left.Extent.Text
                    $prefixStatements = @(Get-WholeScriptContiguousWhitelistedHelperPrefixStatements -Statements $topLevelStatements -BeforeIndex $j)
                    if (-not (Test-WholeScriptWhitelistedIexExpansionCandidate -PrefixStatements $prefixStatements -ExpressionAst $expressionAst)) {
                        $expressionAst = $null
                    } else {
                        $evaluated = Try-EvaluateWhitelistedWholeScriptPayloadExpression -PrefixStatements $prefixStatements -ExpressionAst $expressionAst -TimeoutMs 4000
                        $payloadText = Get-WhitelistedRecoveredPayloadCandidateText -Text $evaluated
                        if (-not [string]::IsNullOrWhiteSpace($payloadText) -and -not (Test-RecoveredScriptLooksWrapperLiteral -Text $payloadText) -and $payloadText.Length -ge 64) {
                            $replacementText = ([string]$replacementPrefix + ' = ' + (Convert-TextToPowerShellLiteralHereString -Text $payloadText))
                            $rangeKey = '{0}:{1}' -f $replaceStart, $replaceEnd
                            if (-not $seenRanges.ContainsKey($rangeKey)) {
                                $originalText = $ScriptText.Substring($replaceStart, $replaceEnd - $replaceStart)
                                if (-not [string]::Equals($originalText, $replacementText, [System.StringComparison]::Ordinal)) {
                                    $seenRanges[$rangeKey] = $true
                                    $replacements.Add([PSCustomObject]@{
                                            Start = $replaceStart
                                            End   = $replaceEnd
                                            Text  = $replacementText
                                        }) | Out-Null
                                }
                            }
                        }
                    }

                    break
                }

                continue
            }
        }

        $prefixStatements = @(Get-WholeScriptContiguousWhitelistedHelperPrefixStatements -Statements $topLevelStatements -BeforeIndex $i)
        if (-not (Test-WholeScriptWhitelistedIexExpansionCandidate -PrefixStatements $prefixStatements -ExpressionAst $expressionAst)) {
            continue
        }

        $evaluated = Try-EvaluateWhitelistedWholeScriptPayloadExpression -PrefixStatements $prefixStatements -ExpressionAst $expressionAst -TimeoutMs 4000
        $payloadText = Get-WhitelistedRecoveredPayloadCandidateText -Text $evaluated
        if ([string]::IsNullOrWhiteSpace($payloadText) -or (Test-RecoveredScriptLooksWrapperLiteral -Text $payloadText) -or $payloadText.Length -lt 64) {
            continue
        }

        $replacementText = Convert-TextToPowerShellLiteralHereString -Text $payloadText
        $rangeKey = '{0}:{1}' -f $replaceStart, $replaceEnd
        if ($seenRanges.ContainsKey($rangeKey)) {
            continue
        }

        $originalText = $ScriptText.Substring($replaceStart, $replaceEnd - $replaceStart)
        if ([string]::Equals($originalText, $replacementText, [System.StringComparison]::Ordinal)) {
            continue
        }

        $seenRanges[$rangeKey] = $true
        $replacements.Add([PSCustomObject]@{
                Start = $replaceStart
                End   = $replaceEnd
                Text  = $replacementText
            }) | Out-Null
    }

    if ($replacements.Count -eq 0) {
        return $ScriptText
    }

    $result = $ScriptText
    foreach ($replacement in @($replacements.ToArray() | Sort-Object Start -Descending)) {
        $result = $result.Substring(0, $replacement.Start) + [string]$replacement.Text + $result.Substring($replacement.End)
    }

    $check = Test-PowerShellSyntax -ScriptText $result
    if ($check.IsValid) {
        return $result
    }

    return $ScriptText
}

function Test-WholeScriptStaticLaunchableArtifactPath {
    param([AllowNull()][string]$PathText)

    if ([string]::IsNullOrWhiteSpace($PathText)) {
        return $false
    }

    $extension = ''
    try {
        $extension = [System.IO.Path]::GetExtension(([string]$PathText).Trim()).ToLowerInvariant()
    } catch {
        $extension = ''
    }

    return ($extension -in @('.ps1', '.psm1', '.psd1', '.bat', '.cmd', '.vbs'))
}

function Convert-WholeScriptStaticExpansionToCommentBlock {
    param(
        [string[]]$HeaderLines = @(),
        [AllowNull()][string]$BodyText
    )

    $body = if ($null -eq $BodyText) { '' } else { [string]$BodyText }
    $body = $body.Trim()
    if ([string]::IsNullOrWhiteSpace($body)) {
        return $null
    }

    if ($body.Length -gt 131072) {
        $body = $body.Substring(0, 131072).TrimEnd() + "`r`n...[truncated]"
    }

    $lines = New-Object 'System.Collections.Generic.List[string]'
    $lines.Add('PSDissect-LocalLaunchExpansion') | Out-Null
    foreach ($header in @($HeaderLines)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$header)) {
            $lines.Add([string]$header) | Out-Null
        }
    }
    $lines.Add('') | Out-Null
    foreach ($line in @($body -split "`r?`n")) {
        $lines.Add(([string]$line -replace '#>', '# >')) | Out-Null
    }

    return "<# " + ($lines -join "`r`n") + "`r`n#>"
}

function Split-WholeScriptStaticVbsConcatParts {
    param([AllowNull()][string]$ExpressionText)

    if ([string]::IsNullOrWhiteSpace($ExpressionText)) {
        return @()
    }

    $parts = New-Object 'System.Collections.Generic.List[string]'
    $builder = New-Object System.Text.StringBuilder
    $inQuote = $false
    $text = [string]$ExpressionText

    for ($i = 0; $i -lt $text.Length; $i++) {
        $ch = $text[$i]
        if ($ch -eq '"') {
            if ($inQuote -and ($i + 1) -lt $text.Length -and $text[$i + 1] -eq '"') {
                [void]$builder.Append('""')
                $i++
                continue
            }

            $inQuote = -not $inQuote
            [void]$builder.Append($ch)
            continue
        }

        if (-not $inQuote -and ($ch -eq '+' -or $ch -eq '&')) {
            $partText = $builder.ToString().Trim()
            if (-not [string]::IsNullOrWhiteSpace($partText)) {
                $parts.Add($partText) | Out-Null
            }
            [void]$builder.Clear()
            continue
        }

        [void]$builder.Append($ch)
    }

    $tail = $builder.ToString().Trim()
    if (-not [string]::IsNullOrWhiteSpace($tail)) {
        $parts.Add($tail) | Out-Null
    }

    return @($parts.ToArray())
}

function Get-WholeScriptStaticVbsFirstArgumentText {
    param([AllowNull()][string]$ArgumentText)

    if ([string]::IsNullOrWhiteSpace($ArgumentText)) {
        return $null
    }

    $text = [string]$ArgumentText
    $builder = New-Object System.Text.StringBuilder
    $inQuote = $false
    $parenDepth = 0

    for ($i = 0; $i -lt $text.Length; $i++) {
        $ch = $text[$i]
        if ($ch -eq '"') {
            if ($inQuote -and ($i + 1) -lt $text.Length -and $text[$i + 1] -eq '"') {
                [void]$builder.Append('""')
                $i++
                continue
            }

            $inQuote = -not $inQuote
            [void]$builder.Append($ch)
            continue
        }

        if (-not $inQuote) {
            if ($ch -eq '(') {
                $parenDepth++
            } elseif ($ch -eq ')' -and $parenDepth -gt 0) {
                $parenDepth--
            } elseif ($ch -eq ',' -and $parenDepth -le 0) {
                break
            }
        }

        [void]$builder.Append($ch)
    }

    return $builder.ToString().Trim()
}

function Resolve-WholeScriptStaticVbsStringExpressionText {
    param(
        [AllowNull()][string]$ExpressionText,
        [hashtable]$Variables
    )

    if ([string]::IsNullOrWhiteSpace($ExpressionText)) {
        return $null
    }

    $expr = ([string]$ExpressionText).Trim()
    while ($expr.StartsWith('(') -and $expr.EndsWith(')') -and $expr.Length -gt 2) {
        $expr = $expr.Substring(1, $expr.Length - 2).Trim()
    }

    if ($expr -match '^\s*"(?<text>(?:[^"]|"")*)"\s*$') {
        return ([string]$Matches['text']).Replace('""', '"')
    }

    if ($expr -match '^(?i:replace)\s*\(\s*(?<base>.+?)\s*,\s*"(?<from>(?:[^"]|"")*)"\s*,\s*"(?<to>(?:[^"]|"")*)"\s*\)\s*$') {
        $baseText = Resolve-WholeScriptStaticVbsStringExpressionText -ExpressionText ([string]$Matches['base']) -Variables $Variables
        if ([string]::IsNullOrWhiteSpace($baseText)) {
            return $null
        }

        $fromText = ([string]$Matches['from']).Replace('""', '"')
        $toText = ([string]$Matches['to']).Replace('""', '"')
        return $baseText.Replace($fromText, $toText)
    }

    if ($expr -match '^[A-Za-z_][A-Za-z0-9_]*$') {
        $key = $expr.ToLowerInvariant()
        if ($Variables -and $Variables.ContainsKey($key) -and -not [string]::IsNullOrWhiteSpace([string]$Variables[$key])) {
            return [string]$Variables[$key]
        }
    }

    $parts = @(Split-WholeScriptStaticVbsConcatParts -ExpressionText $expr)
    if ($parts.Count -gt 1) {
        $builder = New-Object System.Text.StringBuilder
        foreach ($part in @($parts)) {
            $partText = Resolve-WholeScriptStaticVbsStringExpressionText -ExpressionText $part -Variables $Variables
            if ($null -eq $partText) {
                return $null
            }
            [void]$builder.Append([string]$partText)
        }
        return $builder.ToString()
    }

    return $null
}

function Get-WholeScriptStaticLaunchCommandLinesFromArtifactText {
    param(
        [AllowNull()][string]$ArtifactText,
        [AllowNull()][string]$Extension
    )

    if ([string]::IsNullOrWhiteSpace($ArtifactText)) {
        return @()
    }

    $ext = if ([string]::IsNullOrWhiteSpace($Extension)) { '' } else { [string]$Extension.ToLowerInvariant() }
    $results = New-Object 'System.Collections.Generic.List[string]'
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $tryAdd = {
        param([AllowNull()][string]$Value)
        if ([string]::IsNullOrWhiteSpace($Value)) { return }
        $trimmed = ([string]$Value).Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) { return }
        if ($seen.Add($trimmed)) {
            $results.Add($trimmed) | Out-Null
        }
    }

    switch ($ext) {
        '.vbs' {
            $variables = @{}
            foreach ($line in @([regex]::Split([string]$ArtifactText, "`r?`n"))) {
                $trimmed = [string]$line
                if ([string]::IsNullOrWhiteSpace($trimmed)) {
                    continue
                }
                $trimmed = $trimmed.Trim()
                if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith("'")) {
                    continue
                }

                if ($trimmed -match '(?i)\.\s*run\s+(?<arg>.+)$') {
                    $argText = Get-WholeScriptStaticVbsFirstArgumentText -ArgumentText ([string]$Matches['arg'])
                    $resolvedArg = Resolve-WholeScriptStaticVbsStringExpressionText -ExpressionText $argText -Variables $variables
                    if (-not [string]::IsNullOrWhiteSpace($resolvedArg)) {
                        & $tryAdd $resolvedArg
                    }
                }

                if ($trimmed -match '^(?i)(?:set\s+)?(?<name>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*(?<rhs>.+)$') {
                    $rhsText = [string]$Matches['rhs']
                    if ($rhsText -match '(?i)\bCreateObject\s*\(') {
                        continue
                    }

                    $resolvedValue = Resolve-WholeScriptStaticVbsStringExpressionText -ExpressionText $rhsText -Variables $variables
                    if (-not [string]::IsNullOrWhiteSpace($resolvedValue)) {
                        $variables[[string]$Matches['name'].ToLowerInvariant()] = [string]$resolvedValue
                    }
                }
            }
        }
        '.bat' { }
        '.cmd' { }
        default { }
    }

    if ($results.Count -eq 0) {
        foreach ($line in @([regex]::Split([string]$ArtifactText, "`r?`n"))) {
            $trimmed = ([string]$line).Trim()
            if ([string]::IsNullOrWhiteSpace($trimmed)) {
                continue
            }
            if ($trimmed -match '^(?i)(?:rem\b|::)') {
                continue
            }
            if ($trimmed -match '(?i)\b(?:powershell|pwsh|cmd|wscript|cscript|start)\b' -or
                $trimmed -match '(?i)\.(?:ps1|psm1|psd1|bat|cmd|vbs)\b') {
                & $tryAdd $trimmed
            }
        }
    }

    return @($results.ToArray())
}

function Resolve-WholeScriptStaticArtifactPathFromCommandLineText {
    param(
        [AllowNull()][string]$CommandLineText,
        [Parameter(Mandatory)][hashtable]$Context
    )

    if ([string]::IsNullOrWhiteSpace($CommandLineText)) {
        return $null
    }

    $tokenMatches = @(Get-PowerShellHostLooseTokenMatches -Text ([string]$CommandLineText))
    foreach ($tokenMatch in @($tokenMatches)) {
        $tokenText = Unwrap-PowerShellHostLooseToken -TokenText ([string]$tokenMatch.Value)
        if (-not (Test-WholeScriptStaticLaunchableArtifactPath -PathText $tokenText)) {
            continue
        }

        $resolvedPath = Resolve-WholeScriptStaticDisplayPath -PathText $tokenText -Context $Context
        if (-not [string]::IsNullOrWhiteSpace($resolvedPath)) {
            return $resolvedPath
        }
    }

    $pattern = '(?is)(?<path>"(?:[^"]|"")+\.(?:ps1|psm1|psd1|bat|cmd|vbs)"|''(?:[^'']|'''')+\.(?:ps1|psm1|psd1|bat|cmd|vbs)''|(?:[A-Za-z]:|%[^%]+%|\$env:[A-Za-z_][A-Za-z0-9_]*|\.{1,2}[\\/])[^''""\r\n|&<>]*?\.(?:ps1|psm1|psd1|bat|cmd|vbs))'
    foreach ($match in @([regex]::Matches([string]$CommandLineText, $pattern))) {
        $candidatePath = Unwrap-PowerShellHostLooseToken -TokenText ([string]$match.Groups['path'].Value)
        if (-not (Test-WholeScriptStaticLaunchableArtifactPath -PathText $candidatePath)) {
            continue
        }

        $resolvedPath = Resolve-WholeScriptStaticDisplayPath -PathText $candidatePath -Context $Context
        if (-not [string]::IsNullOrWhiteSpace($resolvedPath)) {
            return $resolvedPath
        }
    }

    return $null
}

function Resolve-WholeScriptStaticLocalLaunchExpansionTextFromScriptText {
    param(
        [AllowNull()][string]$ScriptText,
        [hashtable]$ParentContext = $null,
        [int]$Depth = 0,
        [System.Collections.Generic.HashSet[string]]$VisitedPaths = $null
    )

    if ([string]::IsNullOrWhiteSpace($ScriptText) -or $Depth -gt 6) {
        return $null
    }

    $statements = @(Get-TopLevelScriptStatementsFromText -ScriptText $ScriptText)
    if ($statements.Count -eq 0) {
        return $null
    }

    $ctx = New-WholeScriptStaticResolutionContext
    try {
        if ($ParentContext) {
            if ($ParentContext.ContainsKey('ScriptPath') -and -not [string]::IsNullOrWhiteSpace([string]$ParentContext.ScriptPath)) {
                $ctx.ScriptPath = [string]$ParentContext.ScriptPath
            }
            if ($ParentContext.ContainsKey('PathContext') -and $null -ne $ParentContext.PathContext) {
                $ctx.PathContext = $ParentContext.PathContext
            }
        }

        $staticEvalState = Get-StaticEvalState -Context $ctx
        if ($staticEvalState) {
            $staticEvalState.ValueDepthLimit = 64
            $staticEvalState.StringCompatDepthLimit = 48
        }
        $ctx.SafeMode = $true

        $blocks = New-Object 'System.Collections.Generic.List[string]'
        foreach ($statement in @($statements)) {
            try {
                [void](Invoke-WholeScriptStaticStatement -Statement $statement -Context $ctx -AllowEmptyFallback:$false)
            } catch {
                if (-not (Test-IsCallDepthOverflowException -ErrorObject $_)) {
                    throw
                }
            }

            $blockText = Resolve-WholeScriptStaticLocalLaunchExpansionTextFromStatementAst -Statement $statement -Context $ctx -Depth ($Depth + 1) -VisitedPaths $VisitedPaths
            if (-not [string]::IsNullOrWhiteSpace($blockText)) {
                $blocks.Add([string]$blockText) | Out-Null
            }
        }

        if ($blocks.Count -eq 0) {
            return $null
        }

        return (($blocks.ToArray()) -join "`r`n`r`n")
    } finally {
        Close-WholeScriptStaticResolutionContext -Context $ctx
    }
}

function Resolve-WholeScriptStaticLocalLaunchExpansionTextFromArtifactPath {
    param(
        [AllowNull()][string]$PathText,
        [Parameter(Mandatory)][hashtable]$Context,
        [int]$Depth = 0,
        [System.Collections.Generic.HashSet[string]]$VisitedPaths = $null
    )

    if ([string]::IsNullOrWhiteSpace($PathText) -or $Depth -gt 6) {
        return $null
    }

    $pathInfo = Get-WholeScriptStaticArtifactPathInfo -PathText $PathText -Context $Context
    if ($null -eq $pathInfo -or $pathInfo.IsRegistry) {
        return $null
    }

    if ($null -eq $VisitedPaths) {
        $VisitedPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    }
    if (-not $VisitedPaths.Add([string]$pathInfo.CanonicalPath)) {
        return $null
    }

    try {
        $record = Get-WholeScriptStaticFileArtifact -Context $Context -PathText ([string]$pathInfo.DisplayPath)
        if ($null -eq $record -or [string]$record.Kind -ne 'File') {
            return $null
        }

        $contentText = if ($null -eq $record.ContentText) { '' } else { [string]$record.ContentText }
        if ([string]::IsNullOrWhiteSpace($contentText)) {
            return $null
        }

        $extension = ''
        try {
            $extension = [System.IO.Path]::GetExtension([string]$record.DisplayPath).ToLowerInvariant()
        } catch {
            $extension = ''
        }

        $blocks = New-Object 'System.Collections.Generic.List[string]'
        $headerLines = @(
            ('SourcePath: ' + [string]$record.DisplayPath),
            ('ArtifactType: ' + $(if ([bool]$record.IsPowerShell) { 'PowerShell' } elseif (-not [string]::IsNullOrWhiteSpace($extension)) { $extension } else { 'Text' }))
        )

        if ([bool]$record.IsPowerShell) {
            $payloadText = Try-NormalizeStaticArtifactPayloadText -Text $contentText
            if ([string]::IsNullOrWhiteSpace($payloadText)) {
                $payloadText = $contentText.Trim()
            }

            $mainBlock = Convert-WholeScriptStaticExpansionToCommentBlock -HeaderLines $headerLines -BodyText $payloadText
            if (-not [string]::IsNullOrWhiteSpace($mainBlock)) {
                $blocks.Add([string]$mainBlock) | Out-Null
            }

            $nestedText = Resolve-WholeScriptStaticLocalLaunchExpansionTextFromScriptText -ScriptText $payloadText -ParentContext $Context -Depth ($Depth + 1) -VisitedPaths $VisitedPaths
            if (-not [string]::IsNullOrWhiteSpace($nestedText)) {
                $blocks.Add([string]$nestedText) | Out-Null
            }
        } else {
            if ($extension -in @('.bat', '.cmd', '.vbs', '.ps1', '.psm1', '.psd1')) {
                $mainBlock = Convert-WholeScriptStaticExpansionToCommentBlock -HeaderLines $headerLines -BodyText $contentText
                if (-not [string]::IsNullOrWhiteSpace($mainBlock)) {
                    $blocks.Add([string]$mainBlock) | Out-Null
                }
            }

            foreach ($commandLine in @(Get-WholeScriptStaticLaunchCommandLinesFromArtifactText -ArtifactText $contentText -Extension $extension)) {
                $nestedText = Resolve-WholeScriptStaticLocalLaunchExpansionTextFromCommandLineText -CommandLineText $commandLine -Context $Context -Depth ($Depth + 1) -VisitedPaths $VisitedPaths
                if (-not [string]::IsNullOrWhiteSpace($nestedText)) {
                    $blocks.Add([string]$nestedText) | Out-Null
                }
            }
        }

        if ($blocks.Count -eq 0) {
            return $null
        }

        return (($blocks.ToArray()) -join "`r`n`r`n")
    } finally {
        [void]$VisitedPaths.Remove([string]$pathInfo.CanonicalPath)
    }
}

function Resolve-WholeScriptStaticLocalLaunchExpansionTextFromCommandLineText {
    param(
        [AllowNull()][string]$CommandLineText,
        [Parameter(Mandatory)][hashtable]$Context,
        [int]$Depth = 0,
        [System.Collections.Generic.HashSet[string]]$VisitedPaths = $null
    )

    if ([string]::IsNullOrWhiteSpace($CommandLineText) -or $Depth -gt 6) {
        return $null
    }

    $artifactPath = Resolve-WholeScriptStaticArtifactPathFromCommandLineText -CommandLineText $CommandLineText -Context $Context
    if ([string]::IsNullOrWhiteSpace($artifactPath)) {
        return $null
    }

    return (Resolve-WholeScriptStaticLocalLaunchExpansionTextFromArtifactPath -PathText $artifactPath -Context $Context -Depth ($Depth + 1) -VisitedPaths $VisitedPaths)
}

function Resolve-WholeScriptStaticLocalLaunchExpansionTextFromCommandAst {
    param(
        [Parameter(Mandatory)][System.Management.Automation.Language.CommandAst]$CommandAst,
        [Parameter(Mandatory)][hashtable]$Context,
        [int]$Depth = 0,
        [System.Collections.Generic.HashSet[string]]$VisitedPaths = $null
    )

    if ($Depth -gt 6) {
        return $null
    }

    $elements = @($CommandAst.CommandElements)
    if ($elements.Count -eq 0) {
        return $null
    }

    $targetAst = $null
    switch ([string]$CommandAst.InvocationOperator) {
        'Ampersand' { if ($elements.Count -ge 1) { $targetAst = $elements[0] } }
        'Dot'       { if ($elements.Count -ge 1) { $targetAst = $elements[0] } }
    }
    if ($null -eq $targetAst) {
        $headText = if ($elements[0] -and $elements[0].Extent) { [string]$elements[0].Extent.Text } else { $null }
        if ($headText -in @('&', '.') -and $elements.Count -ge 2) {
            $targetAst = $elements[1]
        }
    }
    if ($null -ne $targetAst) {
        $artifactPath = Resolve-WholeScriptStaticArtifactPathTextFromAst -Ast $targetAst -Context $Context
        if (Test-WholeScriptStaticLaunchableArtifactPath -PathText $artifactPath) {
            return (Resolve-WholeScriptStaticLocalLaunchExpansionTextFromArtifactPath -PathText $artifactPath -Context $Context -Depth ($Depth + 1) -VisitedPaths $VisitedPaths)
        }
    }

    $headPath = Resolve-WholeScriptStaticArtifactPathTextFromAst -Ast $elements[0] -Context $Context
    if (Test-WholeScriptStaticLaunchableArtifactPath -PathText $headPath) {
        return (Resolve-WholeScriptStaticLocalLaunchExpansionTextFromArtifactPath -PathText $headPath -Context $Context -Depth ($Depth + 1) -VisitedPaths $VisitedPaths)
    }

    $cmdName = Convert-DynamicCommandCandidateToName -Value $CommandAst.GetCommandName()
    if ([string]::IsNullOrWhiteSpace($cmdName)) {
        return $null
    }

    $binding = Get-StaticCommandArgumentBinding -CommandAst $CommandAst
    switch -Regex ($cmdName) {
        '^(?i:powershell|pwsh)(?:\.exe)?$' {
            foreach ($key in @('file', 'f')) {
                if ($binding.Parameters.ContainsKey($key) -and $binding.Parameters[$key]) {
                    $artifactPath = Resolve-WholeScriptStaticArtifactPathTextFromAst -Ast $binding.Parameters[$key] -Context $Context
                    if (Test-WholeScriptStaticLaunchableArtifactPath -PathText $artifactPath) {
                        return (Resolve-WholeScriptStaticLocalLaunchExpansionTextFromArtifactPath -PathText $artifactPath -Context $Context -Depth ($Depth + 1) -VisitedPaths $VisitedPaths)
                    }
                }
            }

            $commandLineText = if ($CommandAst.Extent) { [string]$CommandAst.Extent.Text } else { $null }
            return (Resolve-WholeScriptStaticLocalLaunchExpansionTextFromCommandLineText -CommandLineText $commandLineText -Context $Context -Depth ($Depth + 1) -VisitedPaths $VisitedPaths)
        }
        '^(?i:cmd|cmd\.exe|wscript|wscript\.exe|cscript|cscript\.exe)$' {
            $commandLineText = if ($CommandAst.Extent) { [string]$CommandAst.Extent.Text } else { $null }
            return (Resolve-WholeScriptStaticLocalLaunchExpansionTextFromCommandLineText -CommandLineText $commandLineText -Context $Context -Depth ($Depth + 1) -VisitedPaths $VisitedPaths)
        }
        '^(?i:start-process|start|saps)$' {
            $fileAst = $null
            foreach ($key in @('filepath')) {
                if ($binding.Parameters.ContainsKey($key) -and $binding.Parameters[$key]) {
                    $fileAst = $binding.Parameters[$key]
                    break
                }
            }
            if ($null -eq $fileAst -and $binding.Positional.Count -gt 0) {
                $fileAst = $binding.Positional[0]
            }

            $hostPath = Resolve-WholeScriptStaticArtifactPathTextFromAst -Ast $fileAst -Context $Context
            if (Test-WholeScriptStaticLaunchableArtifactPath -PathText $hostPath) {
                return (Resolve-WholeScriptStaticLocalLaunchExpansionTextFromArtifactPath -PathText $hostPath -Context $Context -Depth ($Depth + 1) -VisitedPaths $VisitedPaths)
            }

            $argAst = $null
            foreach ($key in @('argumentlist')) {
                if ($binding.Parameters.ContainsKey($key) -and $binding.Parameters[$key]) {
                    $argAst = $binding.Parameters[$key]
                    break
                }
            }
            if ($null -eq $argAst -and $binding.Positional.Count -gt 1) {
                $argAst = $binding.Positional[1]
            }

            $argumentText = Resolve-WholeScriptStaticCommandValueTextFromAst -Ast $argAst -Context $Context -Delimiter ' '
            $commandLineText = if ([string]::IsNullOrWhiteSpace($argumentText)) {
                $hostPath
            } elseif ([string]::IsNullOrWhiteSpace($hostPath)) {
                $argumentText
            } else {
                ($hostPath + ' ' + $argumentText).Trim()
            }

            return (Resolve-WholeScriptStaticLocalLaunchExpansionTextFromCommandLineText -CommandLineText $commandLineText -Context $Context -Depth ($Depth + 1) -VisitedPaths $VisitedPaths)
        }
        '^(?i:schtasks(?:\.exe)?)$' {
            $commandText = if ($CommandAst.Extent) { [string]$CommandAst.Extent.Text } else { $null }
            if ([string]::IsNullOrWhiteSpace($commandText)) {
                return $null
            }

            $trMatch = [regex]::Match($commandText, '(?is)(?:^|\s)(?:/TR|-TR)\s+(?<cmd>"(?:[^"]|"")*"|''(?:[^'']|'''')*''|\S+)')
            if (-not $trMatch.Success) {
                return $null
            }

            $taskCommandLine = Unwrap-PowerShellHostLooseToken -TokenText ([string]$trMatch.Groups['cmd'].Value)
            return (Resolve-WholeScriptStaticLocalLaunchExpansionTextFromCommandLineText -CommandLineText $taskCommandLine -Context $Context -Depth ($Depth + 1) -VisitedPaths $VisitedPaths)
        }
    }

    return $null
}

function Resolve-WholeScriptStaticLocalLaunchExpansionTextFromStatementAst {
    param(
        $Statement,
        [Parameter(Mandatory)][hashtable]$Context,
        [int]$Depth = 0,
        [System.Collections.Generic.HashSet[string]]$VisitedPaths = $null
    )

    $commandAst = Get-WholeScriptSingleCommandAst -Ast $Statement
    if ($null -eq $commandAst) {
        return $null
    }

    return (Resolve-WholeScriptStaticLocalLaunchExpansionTextFromCommandAst -CommandAst $commandAst -Context $Context -Depth ($Depth + 1) -VisitedPaths $VisitedPaths)
}

function Invoke-ExpandWholeScriptLocalArtifactLaunchPass {
    param([Parameter(Mandatory)][string]$ScriptText)

    if ([string]::IsNullOrWhiteSpace($ScriptText) -or
        $ScriptText -notmatch '(?i)\b(?:Start-Process|start|saps|powershell|pwsh|cmd|wscript|cscript|schtasks)\b') {
        return $ScriptText
    }

    $parse = Get-ScriptParseInfo -ScriptText $ScriptText
    if (-not $parse.IsValid -or -not $parse.Ast) {
        return $ScriptText
    }

    $statements = @(Get-TopLevelScriptStatementsFromText -ScriptText $ScriptText)
    if ($statements.Count -eq 0) {
        return $ScriptText
    }

    $ctx = New-WholeScriptStaticResolutionContext
    try {
        $staticEvalState = Get-StaticEvalState -Context $ctx
        if ($staticEvalState) {
            $staticEvalState.ValueDepthLimit = 64
            $staticEvalState.StringCompatDepthLimit = 48
        }
        $ctx.SafeMode = $true

        $replacements = New-Object 'System.Collections.Generic.List[object]'
        foreach ($statement in @($statements)) {
            try {
                [void](Invoke-WholeScriptStaticStatement -Statement $statement -Context $ctx -AllowEmptyFallback:$false)
            } catch {
                if (-not (Test-IsCallDepthOverflowException -ErrorObject $_)) {
                    throw
                }
            }

            if ($null -eq $statement -or $null -eq $statement.Extent) {
                continue
            }

            $launchExpansionText = Resolve-WholeScriptStaticLocalLaunchExpansionTextFromStatementAst -Statement $statement -Context $ctx -Depth 0
            if ([string]::IsNullOrWhiteSpace($launchExpansionText)) {
                continue
            }

            $replacement = ([string]$statement.Extent.Text).TrimEnd() + "`r`n" + [string]$launchExpansionText
            $replacements.Add([PSCustomObject]@{
                    StartOffset = [int]$statement.Extent.StartOffset
                    EndOffset   = [int]$statement.Extent.EndOffset
                    Replacement = [string]$replacement
                }) | Out-Null
        }

        if ($replacements.Count -eq 0) {
            return $ScriptText
        }

        $selectedInfo = Select-NonOverlappingReplacements -Candidates @($replacements.ToArray()) -Strategy 'Outer'
        $selected = @($selectedInfo.Selected)
        if ($selected.Count -eq 0) {
            return $ScriptText
        }

        $rewritten = Apply-ReplacementsToText -Text $ScriptText -Replacements $selected
        $check = Test-PowerShellSyntax -ScriptText $rewritten
        if ($check.IsValid) {
            return $rewritten
        }

        return $ScriptText
    } finally {
        Close-WholeScriptStaticResolutionContext -Context $ctx
    }
}

function Get-GatedRoundSafeExtractionSinkInfo {
    param($Statement)

    if ($null -eq $Statement -or -not $Statement.PSObject.Properties['Extent'] -or $null -eq $Statement.Extent) {
        return $null
    }

    $statementText = [string]$Statement.Extent.Text
    if ([string]::IsNullOrWhiteSpace($statementText)) {
        return $null
    }

    $reasons = New-Object 'System.Collections.Generic.List[string]'
    $tryAddReason = {
        param([string]$Reason)

        if ([string]::IsNullOrWhiteSpace($Reason)) {
            return
        }

        if (-not $reasons.Contains([string]$Reason)) {
            $reasons.Add([string]$Reason) | Out-Null
        }
    }

    $dynamicIexArgument = Get-GatedRoundDynamicIexArgumentAst -Statement $Statement
    if ($dynamicIexArgument) {
        & $tryAddReason 'dynamic_iex'
    }

    $commandNames = New-Object 'System.Collections.Generic.List[string]'
    $tryAddCommandName = {
        param([AllowNull()][string]$Name)

        if ([string]::IsNullOrWhiteSpace($Name)) {
            return
        }

        $canonicalName = [string](Convert-DynamicCommandCandidateToName -Value $Name)
        if ([string]::IsNullOrWhiteSpace($canonicalName)) {
            return
        }

        if (-not $commandNames.Contains($canonicalName)) {
            $commandNames.Add($canonicalName) | Out-Null
        }
    }

    if ($Statement -is [System.Management.Automation.Language.CommandAst]) {
        & $tryAddCommandName $Statement.GetCommandName()
    } elseif ($Statement -is [System.Management.Automation.Language.PipelineAst]) {
        foreach ($element in @($Statement.PipelineElements)) {
            if ($element -is [System.Management.Automation.Language.CommandAst]) {
                & $tryAddCommandName $element.GetCommandName()
            }
        }
    }

    foreach ($commandName in @($commandNames.ToArray())) {
        if ($commandName -match '^(?i:invoke-expression|iex)$') {
            & $tryAddReason 'invoke_expression'
        }
        if ($commandName -match '^(?i:powershell|pwsh|cmd|cmd\.exe|start-process|start|saps)$') {
            & $tryAddReason 'host_wrapper'
        }
    }

    if ($statementText -match '(?i)(?:^|\s)-(?:enc|encodedcommand)\b') {
        & $tryAddReason 'encoded_command'
    }
    if ($statementText -match '(?i)\bFromBase64String\b') {
        & $tryAddReason 'base64_decode'
    }
    if ($statementText -match '(?i)\b(?:DeflateStream|GZipStream)\b' -and
        $statementText -match '(?i)\bReadToEnd\b') {
        & $tryAddReason 'compressed_loader'
    }

    if ($reasons.Count -eq 0) {
        return $null
    }

    return [PSCustomObject]@{
        Reasons = @($reasons.ToArray())
    }
}

function Try-Resolve-GatedRoundIntermediatePrefixPayloadInfo {
    param(
        [Parameter(Mandatory)][string]$ScriptText,
        [hashtable]$PreExecutionGateCache = $null
    )

    if ([string]::IsNullOrWhiteSpace($ScriptText)) {
        return $null
    }

    $statements = @(Get-TopLevelScriptStatementsFromText -ScriptText $ScriptText)
    if ($statements.Count -lt 2) {
        return $null
    }

    for ($index = $statements.Count - 1; $index -ge 0; $index--) {
        $statement = $statements[$index]
        $sinkInfo = Get-GatedRoundSafeExtractionSinkInfo -Statement $statement
        if ($null -eq $sinkInfo -or $null -eq $statement.Extent) {
            continue
        }

        $prefixEnd = [int]$statement.Extent.EndOffset
        if ($prefixEnd -le 0 -or $prefixEnd -gt $ScriptText.Length -or $prefixEnd -eq $ScriptText.Length) {
            continue
        }

        $prefixScript = $ScriptText.Substring(0, $prefixEnd)
        if ([string]::IsNullOrWhiteSpace($prefixScript)) {
            continue
        }

        $attempts = @()

        $mandatoryBase64Payload = Try-Resolve-WholeScriptMandatoryBase64PayloadInfo -ScriptText $prefixScript
        if ($mandatoryBase64Payload -and -not [string]::IsNullOrWhiteSpace([string]$mandatoryBase64Payload.PayloadText)) {
            $attempts += [PSCustomObject]@{
                PayloadText = [string]$mandatoryBase64Payload.PayloadText
                Source      = if ($mandatoryBase64Payload.PSObject.Properties['DecodeSource']) { [string]$mandatoryBase64Payload.DecodeSource } else { 'gated_prefix_mandatory_base64' }
            }
        }

        $compressedLoaderPayload = Try-Resolve-WholeScriptStaticCompressedLoaderPayloadInfo -ScriptText $prefixScript
        if ($compressedLoaderPayload -and -not [string]::IsNullOrWhiteSpace([string]$compressedLoaderPayload.PayloadText)) {
            $attempts += [PSCustomObject]@{
                PayloadText = [string]$compressedLoaderPayload.PayloadText
                Source      = if ($compressedLoaderPayload.PSObject.Properties['DecodeSource']) { [string]$compressedLoaderPayload.DecodeSource } else { 'gated_prefix_static_compressed_loader' }
            }
        }

        $hostPayload = Resolve-WholeScriptHostPayloadInfo -ScriptText $prefixScript
        if ($hostPayload -and -not [string]::IsNullOrWhiteSpace([string]$hostPayload.PayloadText)) {
            $attempts += [PSCustomObject]@{
                PayloadText = [string]$hostPayload.PayloadText
                Source      = if ($hostPayload.PSObject.Properties['DecodeSource']) { [string]$hostPayload.DecodeSource } else { 'gated_prefix_host_wrapper' }
            }
        }

        try {
            $staticPayload = Resolve-WholeScriptStaticPayloadInfo -ScriptText $prefixScript -PreExecutionGateMode 'Disabled' -PreExecutionGateCache $PreExecutionGateCache -SafeMode:$false
        } catch {
            $staticPayload = $null
        }
        if ($staticPayload -and -not [string]::IsNullOrWhiteSpace([string]$staticPayload.PayloadText)) {
            $attempts += [PSCustomObject]@{
                PayloadText = [string]$staticPayload.PayloadText
                Source      = if ($staticPayload.PSObject.Properties['DecodeSource']) { [string]$staticPayload.DecodeSource } else { 'gated_prefix_static_payload' }
            }
        }

        foreach ($attempt in @($attempts)) {
            if ($null -eq $attempt -or [string]::IsNullOrWhiteSpace([string]$attempt.PayloadText)) {
                continue
            }

            $resultPayloadText = [string]$attempt.PayloadText
            $tailText = if ($prefixEnd -lt $ScriptText.Length) {
                [string]$ScriptText.Substring($prefixEnd)
            } else {
                ''
            }

            if (-not [string]::IsNullOrWhiteSpace($tailText)) {
                $combinedCandidate = (($resultPayloadText.TrimEnd()) + "`r`n`r`n" + $tailText.TrimStart("`r", "`n"))
                $combinedPayloadText = Get-WholeScriptReplacementCandidateText -OriginalText $ScriptText -CandidateText $combinedCandidate
                if (-not [string]::IsNullOrWhiteSpace($combinedPayloadText)) {
                    $combinedParse = Test-PowerShellSyntax -ScriptText $combinedPayloadText
                    if ($combinedParse.IsValid) {
                        $resultPayloadText = [string]$combinedPayloadText
                    }
                }
            }

            return [PSCustomObject]@{
                PayloadText     = [string]$resultPayloadText
                Source          = [string]$attempt.Source
                StatementIndex  = [int]$index
                PrefixEndOffset = [int]$prefixEnd
                SinkReasons     = @($sinkInfo.Reasons)
            }
        }
    }

    return $null
}

function Test-WholeScriptBootstrapHelperScriptAllowed {
    param(
        [string]$ScriptText,
        [string[]]$RequiredHelperNames = @()
    )

    if ([string]::IsNullOrWhiteSpace($ScriptText)) {
        return $false
    }

    $topLevelStatements = @(Get-TopLevelScriptStatementsFromText -ScriptText $ScriptText)
    if ($topLevelStatements.Count -eq 0) {
        return $false
    }

    $foundRequiredHelper = ($RequiredHelperNames.Count -eq 0)
    foreach ($statement in @($topLevelStatements)) {
        if ($statement -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
            if (-not (Test-WholeScriptLocalHelperFunctionAllowed -FunctionAst $statement)) {
                return $false
            }
            if (-not $foundRequiredHelper -and ([string]$statement.Name) -in @($RequiredHelperNames)) {
                $foundRequiredHelper = $true
            }
            continue
        }

        if (-not (Test-WholeScriptEvalFallbackAllowed -Ast $statement -AllowFunctionDefinitions:$true)) {
            return $false
        }
    }

    return $foundRequiredHelper
}

function Get-WholeScriptSingleCommandAst {
    param($Ast)

    if ($null -eq $Ast) {
        return $null
    }

    if ($Ast -is [System.Management.Automation.Language.CommandAst]) {
        return $Ast
    }

    if ($Ast -is [System.Management.Automation.Language.PipelineAst]) {
        $elements = @($Ast.PipelineElements)
        if ($elements.Count -eq 1 -and $elements[0] -is [System.Management.Automation.Language.CommandAst]) {
            return $elements[0]
        }
        return $null
    }

    if ($Ast -is [System.Management.Automation.Language.CommandExpressionAst]) {
        return (Get-WholeScriptSingleCommandAst -Ast $Ast.Expression)
    }

    return $null
}

function Get-WholeScriptKnownEncodingObject {
    param([AllowNull()][string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $null
    }

    switch -Regex (([string]$Name).Trim()) {
        '^(?i:ascii|asciiencoding)$' { return [System.Text.Encoding]::ASCII }
        '^(?i:utf8|utf8encoding)$' { return [System.Text.Encoding]::UTF8 }
        '^(?i:unicode|unicodeencoding)$' { return [System.Text.Encoding]::Unicode }
        '^(?i:bigendianunicode|bigendianunicodeencoding)$' { return [System.Text.Encoding]::BigEndianUnicode }
        '^(?i:default)$' { return [System.Text.Encoding]::Default }
        '^(?i:utf32|utf32encoding)$' { return [System.Text.Encoding]::UTF32 }
    }

    return $null
}

function Try-Resolve-WholeScriptEmbeddedPasswordDeriveTripleDesPayloadText {
    param(
        [Parameter(Mandatory)][string]$HelperScriptText,
        [Parameter(Mandatory)][System.Management.Automation.Language.CommandAst]$HelperCallAst
    )

    if ([string]::IsNullOrWhiteSpace($HelperScriptText)) {
        return $null
    }

    $callCommandName = Convert-DynamicCommandCandidateToName -Value $HelperCallAst.GetCommandName()
    if ([string]::IsNullOrWhiteSpace($callCommandName)) {
        return $null
    }

    $callElements = @($HelperCallAst.CommandElements)
    if ($callElements.Count -lt 3) {
        return $null
    }

    $callArg1 = Try-GetStaticStringValue -Ast $callElements[1] -Context $null
    $callArg2 = Try-GetStaticStringValue -Ast $callElements[2] -Context $null
    if ([string]::IsNullOrWhiteSpace($callArg1) -or [string]::IsNullOrWhiteSpace($callArg2)) {
        return $null
    }

    $helperTokens = $null
    $helperParseErrors = $null
    try {
        $helperAst = [System.Management.Automation.Language.Parser]::ParseInput($HelperScriptText, [ref]$helperTokens, [ref]$helperParseErrors)
    } catch {
        return $null
    }

    if ($null -eq $helperAst -or @($helperParseErrors).Count -gt 0) {
        return $null
    }

    $helperFunction = @($helperAst.EndBlock.Statements | Where-Object {
            $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            -not [string]::IsNullOrWhiteSpace([string]$_.Name)
        } | Select-Object -First 1)
    if ($helperFunction.Count -eq 0) {
        return $null
    }

    $helperFunctionAst = $helperFunction[0]
    if ([string]::IsNullOrWhiteSpace([string]$helperFunctionAst.Name) -or $helperFunctionAst.Name -ine $callCommandName) {
        return $null
    }

    $cipherBase64 = $null
    try {
        $stringNodes = @($helperFunctionAst.Body.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.StringConstantExpressionAst]
                }, $true))
    } catch {
        $stringNodes = @()
    }

    foreach ($stringNode in @($stringNodes)) {
        $candidateValue = [string]$stringNode.Value
        if ([string]::IsNullOrWhiteSpace($candidateValue)) {
            continue
        }
        if ($candidateValue.Length -lt 128) {
            continue
        }
        if (($candidateValue.Length % 4) -ne 0) {
            continue
        }
        if ($candidateValue -notmatch '^[A-Za-z0-9+/=]+$') {
            continue
        }

        $cipherBase64 = $candidateValue
        break
    }

    if ([string]::IsNullOrWhiteSpace($cipherBase64)) {
        return $null
    }

    $encodingName = $null
    $encodingPattern = '(?is)System\.Text\.(?<ctor>ASCIIEncoding|UTF8Encoding|UnicodeEncoding|BigEndianUnicodeEncoding|UTF32Encoding)|Encoding\]::(?<static>ASCII|UTF8|Unicode|BigEndianUnicode|Default|UTF32)'
    $encodingMatch = [regex]::Match($HelperScriptText, $encodingPattern)
    if ($encodingMatch.Success) {
        if (-not [string]::IsNullOrWhiteSpace([string]$encodingMatch.Groups['ctor'].Value)) {
            $encodingName = [string]$encodingMatch.Groups['ctor'].Value
        } elseif (-not [string]::IsNullOrWhiteSpace([string]$encodingMatch.Groups['static'].Value)) {
            $encodingName = [string]$encodingMatch.Groups['static'].Value
        }
    }

    $encoding = Get-WholeScriptKnownEncodingObject -Name $encodingName
    if ($null -eq $encoding) {
        return $null
    }

    $ivLiteral = $null
    $literalGetBytesMatches = @([regex]::Matches($HelperScriptText, '(?is)\.GetBytes\(\s*"(?<value>[^"\r\n]+)"\s*\)'))
    foreach ($literalGetBytesMatch in @($literalGetBytesMatches)) {
        $candidateIv = [string]$literalGetBytesMatch.Groups['value'].Value
        if ([string]::IsNullOrWhiteSpace($candidateIv)) {
            continue
        }
        if ($candidateIv -ieq $callArg1 -or $candidateIv -ieq $callArg2) {
            continue
        }
        $ivLiteral = $candidateIv
        break
    }

    if ([string]::IsNullOrWhiteSpace($ivLiteral)) {
        return $null
    }

    $deriveTypeToken = ('Password' + 'DeriveBytes')
    $derivePattern = '(?is)' + [regex]::Escape($deriveTypeToken) + '\(\s*\$[A-Za-z_]\w*\s*,\s*[^,]+,\s*"(?<hash>[^"]+)"\s*,\s*(?<iter>\d+)'
    $deriveMatch = [regex]::Match($HelperScriptText, $derivePattern)
    if (-not $deriveMatch.Success) {
        return $null
    }

    $hashName = [string]$deriveMatch.Groups['hash'].Value
    $iterationText = [string]$deriveMatch.Groups['iter'].Value
    $iterations = 0
    if ([string]::IsNullOrWhiteSpace($hashName) -or -not [int]::TryParse($iterationText, [ref]$iterations) -or $iterations -lt 1) {
        return $null
    }

    $keyLengthMatch = [regex]::Match($HelperScriptText, '(?is)\.GetBytes\(\s*(?<length>\d{1,3})\s*\)')
    $keyLength = 0
    if (-not $keyLengthMatch.Success -or -not [int]::TryParse([string]$keyLengthMatch.Groups['length'].Value, [ref]$keyLength) -or $keyLength -lt 8) {
        return $null
    }

    $providerTypeToken = ('Triple' + 'DES' + 'CryptoServiceProvider')
    if ($HelperScriptText -notmatch [regex]::Escape($providerTypeToken)) {
        return $null
    }
    if ($HelperScriptText -notmatch '(?is)CipherMode\]::CBC') {
        return $null
    }

    $cipherBytes = $null
    $deriveInstance = $null
    $provider = $null
    $memoryStream = $null
    $cryptoStream = $null
    try {
        $cipherBytes = [Convert]::FromBase64String($cipherBase64)
        if ($null -eq $cipherBytes -or $cipherBytes.Length -eq 0) {
            return $null
        }

        $saltBytes = $encoding.GetBytes($callArg2)
        $ivBytes = $encoding.GetBytes($ivLiteral)
        if ($null -eq $saltBytes -or $null -eq $ivBytes) {
            return $null
        }

        $deriveTypeName = 'System.Security.Cryptography.' + $deriveTypeToken
        $deriveInstance = New-Object $deriveTypeName ($callArg1, $saltBytes, $hashName, $iterations)
        if ($null -eq $deriveInstance) {
            return $null
        }

        [byte[]]$keyBytes = $deriveInstance.GetBytes($keyLength)
        if ($null -eq $keyBytes -or $keyBytes.Length -eq 0) {
            return $null
        }

        $providerTypeName = 'System.Security.Cryptography.' + $providerTypeToken
        $provider = New-Object $providerTypeName
        $provider.Mode = [System.Security.Cryptography.CipherMode]::CBC

        $decryptor = $provider.CreateDecryptor($keyBytes, $ivBytes)
        if ($null -eq $decryptor) {
            return $null
        }

        $memoryStream = New-Object System.IO.MemoryStream($cipherBytes, $true)
        $cryptoStream = New-Object System.Security.Cryptography.CryptoStream($memoryStream, $decryptor, [System.Security.Cryptography.CryptoStreamMode]::Read)
        [byte[]]$buffer = New-Object byte[]($cipherBytes.Length)
        [void]$cryptoStream.Read($buffer, 0, $buffer.Length)

        if (($buffer.Length -gt 3) -and ($buffer[0] -eq 0xEF) -and ($buffer[1] -eq 0xBB) -and ($buffer[2] -eq 0xBF)) {
            $buffer = $buffer[3..($buffer.Length - 1)]
        }

        $payloadText = $encoding.GetString($buffer).TrimEnd([char]0)
        if ([string]::IsNullOrWhiteSpace($payloadText)) {
            return $null
        }

        return $payloadText
    } catch {
        return $null
    } finally {
        if ($cryptoStream) {
            try {
                $cryptoStream.Close()
            } catch {
            }
        }
        if ($memoryStream) {
            try {
                $memoryStream.Close()
            } catch {
            }
        }
        if ($provider) {
            try {
                $provider.Clear()
            } catch {
            }
        }
    }
}

function Try-Resolve-GatedRoundStaticCryptoHelperPayloadInfo {
    param(
        $TargetExpressionAst,
        [hashtable]$HelperTextMap = $null,
        [AllowNull()][string]$OriginalText = $null
    )

    if ($null -eq $TargetExpressionAst -or $null -eq $HelperTextMap -or $HelperTextMap.Count -eq 0) {
        return $null
    }

    $helperCommandAst = Get-WholeScriptSingleCommandAst -Ast $TargetExpressionAst
    if ($null -eq $helperCommandAst) {
        return $null
    }

    $helperCommandName = Convert-DynamicCommandCandidateToName -Value $helperCommandAst.GetCommandName()
    if ([string]::IsNullOrWhiteSpace($helperCommandName)) {
        return $null
    }

    $helperScriptText = $null
    foreach ($mapKey in @($HelperTextMap.Keys)) {
        if ([string]::IsNullOrWhiteSpace([string]$mapKey)) {
            continue
        }
        if ([string]$mapKey -ieq $helperCommandName) {
            $helperScriptText = [string]$HelperTextMap[$mapKey]
            break
        }
    }

    if ([string]::IsNullOrWhiteSpace($helperScriptText)) {
        return $null
    }

    $payloadText = Try-Resolve-WholeScriptEmbeddedPasswordDeriveTripleDesPayloadText -HelperScriptText $helperScriptText -HelperCallAst $helperCommandAst
    if ([string]::IsNullOrWhiteSpace($payloadText)) {
        return $null
    }

    $comparisonOriginal = if (-not [string]::IsNullOrWhiteSpace($OriginalText)) { [string]$OriginalText } else { $null }
    $candidateVariants = New-Object 'System.Collections.Generic.List[string]'

    $normalizedPayload = Try-NormalizeRecoveredScriptText -Text $payloadText
    if (-not [string]::IsNullOrWhiteSpace($normalizedPayload)) {
        $candidateVariants.Add([string]$normalizedPayload) | Out-Null
    }

    $cleanPayloadText = Remove-RecoveredTextTransportArtifacts -Text $payloadText
    if (-not [string]::IsNullOrWhiteSpace($cleanPayloadText)) {
        $candidateVariants.Add([string]$cleanPayloadText) | Out-Null
    }

    foreach ($candidateVariant in @($candidateVariants.ToArray())) {
        $candidateScript = Get-WholeScriptReplacementCandidateText -OriginalText $comparisonOriginal -CandidateText $candidateVariant
        if ([string]::IsNullOrWhiteSpace($candidateScript)) {
            continue
        }
        if (-not (Test-UsefulRecoveredScriptText -Text $candidateScript)) {
            continue
        }

        return [PSCustomObject]@{
            PayloadText = [string]$candidateScript
            Source      = 'gated_helper_bootstrap_static_crypto'
        }
    }

    return $null
}

function Try-Resolve-GatedRoundBootstrapHelperPayloadInfo {
    param(
        [Parameter(Mandatory)][string]$ScriptText,
        [hashtable]$PreExecutionGateCache = $null,
        [int]$TimeoutMs = 4000
    )

    if ([string]::IsNullOrWhiteSpace($ScriptText)) {
        return $null
    }

    $statements = @(Get-TopLevelScriptStatementsFromText -ScriptText $ScriptText)
    if ($statements.Count -lt 2) {
        return $null
    }

    for ($targetIndex = ($statements.Count - 1); $targetIndex -ge 0; $targetIndex--) {
        $targetStatement = $statements[$targetIndex]
        $sinkArgAst = Get-GatedRoundDynamicIexArgumentAst -Statement $targetStatement
        if ($null -eq $sinkArgAst) {
            continue
        }

        $sourceAssignmentIndex = -1
        if ($sinkArgAst -is [System.Management.Automation.Language.VariableExpressionAst]) {
            $sourceVarName = [string]$sinkArgAst.VariablePath.UserPath
            if (-not [string]::IsNullOrWhiteSpace($sourceVarName)) {
                for ($j = $targetIndex - 1; $j -ge 0; $j--) {
                    $candidateAssign = $statements[$j]
                    if ($candidateAssign -isnot [System.Management.Automation.Language.AssignmentStatementAst]) {
                        continue
                    }
                    $assignedVarName = Get-AssignmentTargetVariableName -LeftAst $candidateAssign.Left
                    if ([string]::IsNullOrWhiteSpace($assignedVarName)) {
                        continue
                    }
                    if ($assignedVarName -ieq $sourceVarName) {
                        $sourceAssignmentIndex = $j
                        break
                    }
                }
            }
        }

        $targetExpressionAst = $sinkArgAst
        if ($sourceAssignmentIndex -ge 0) {
            $targetExpressionAst = $statements[$sourceAssignmentIndex].Right
        }
        if ($null -eq $targetExpressionAst) {
            continue
        }

        $helperNames = @(Get-WholeScriptAstCommandNames -Ast $targetExpressionAst | Where-Object {
                Test-WholeScriptLocalHelperNameAllowed -Name $_
            })
        if ($helperNames.Count -eq 0) {
            continue
        }

        $planIndexes = New-Object 'System.Collections.Generic.List[int]'
        $resolvedHelperNames = @()
        $resolvedHelperTexts = @{}

        foreach ($helperName in @($helperNames)) {
            for ($j = $targetIndex - 1; $j -ge 0; $j--) {
                $candidateStmt = $statements[$j]
                if ($candidateStmt -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
                    if (-not [string]::IsNullOrWhiteSpace([string]$candidateStmt.Name) -and
                        $candidateStmt.Name -ieq $helperName -and
                        (Test-WholeScriptLocalHelperFunctionAllowed -FunctionAst $candidateStmt)) {
                        if ($planIndexes -notcontains $j) {
                            $planIndexes.Add($j) | Out-Null
                        }
                        if ($resolvedHelperNames -notcontains $helperName) {
                            $resolvedHelperNames += $helperName
                        }
                        if (-not $resolvedHelperTexts.ContainsKey($helperName)) {
                            $resolvedHelperTexts[$helperName] = [string]$candidateStmt.Extent.Text
                        }
                        break
                    }
                    continue
                }

                if ($candidateStmt -isnot [System.Management.Automation.Language.AssignmentStatementAst]) {
                    continue
                }
                if ($j + 1 -ge $targetIndex) {
                    continue
                }

                $followStmt = $statements[$j + 1]
                $bootstrapArgAst = Get-GatedRoundDynamicIexArgumentAst -Statement $followStmt
                if ($bootstrapArgAst -isnot [System.Management.Automation.Language.VariableExpressionAst]) {
                    continue
                }
                $bootstrapVarName = Get-AssignmentTargetVariableName -LeftAst $candidateStmt.Left
                $invokeVarName = [string]$bootstrapArgAst.VariablePath.UserPath
                if ([string]::IsNullOrWhiteSpace($bootstrapVarName) -or
                    [string]::IsNullOrWhiteSpace($invokeVarName) -or
                    $bootstrapVarName -ine $invokeVarName) {
                    continue
                }

                $bootstrapText = Try-GetStaticStringValue -Ast $candidateStmt.Right -Context $null
                if ([string]::IsNullOrWhiteSpace($bootstrapText)) {
                    continue
                }
                if (-not (Test-WholeScriptBootstrapHelperScriptAllowed -ScriptText $bootstrapText -RequiredHelperNames @($helperName))) {
                    continue
                }

                if ($planIndexes -notcontains $j) {
                    $planIndexes.Add($j) | Out-Null
                }
                if ($planIndexes -notcontains ($j + 1)) {
                    $planIndexes.Add($j + 1) | Out-Null
                }
                if ($resolvedHelperNames -notcontains $helperName) {
                    $resolvedHelperNames += $helperName
                }
                if (-not $resolvedHelperTexts.ContainsKey($helperName) -or [string]::IsNullOrWhiteSpace([string]$resolvedHelperTexts[$helperName])) {
                    $resolvedHelperTexts[$helperName] = $bootstrapText
                }
                break
            }
        }

        if ($resolvedHelperNames.Count -eq 0) {
            continue
        }

        if ($sourceAssignmentIndex -ge 0 -and $planIndexes -notcontains $sourceAssignmentIndex) {
            $planIndexes.Add($sourceAssignmentIndex) | Out-Null
        }

        $sortedPlanIndexes = @($planIndexes | Sort-Object -Unique)
        if ($sortedPlanIndexes.Count -eq 0) {
            continue
        }

        $staticCryptoPayload = Try-Resolve-GatedRoundStaticCryptoHelperPayloadInfo -TargetExpressionAst $targetExpressionAst -HelperTextMap $resolvedHelperTexts -OriginalText $ScriptText
        if ($staticCryptoPayload -and -not [string]::IsNullOrWhiteSpace([string]$staticCryptoPayload.PayloadText)) {
            return [PSCustomObject]@{
                PayloadText = [string]$staticCryptoPayload.PayloadText
                Source      = if ($staticCryptoPayload.PSObject.Properties['Source']) { [string]$staticCryptoPayload.Source } else { 'gated_helper_bootstrap_static_crypto' }
            }
        }

        $execContext = $null
        try {
            $execContext = New-ExecutionContext
        } catch {
            $execContext = $null
        }
        if (-not $execContext) {
            continue
        }
        Initialize-WholeScriptSpecialVariables -ExecContext $execContext

        try {
            $executionFailed = $false

            foreach ($planIndex in @($sortedPlanIndexes)) {
                if ($planIndex -lt 0 -or $planIndex -ge $statements.Count) {
                    $executionFailed = $true
                    break
                }

                $planStatement = $statements[$planIndex]
                if ($null -eq $planStatement -or -not $planStatement.Extent) {
                    $executionFailed = $true
                    break
                }

                if ($planStatement -is [System.Management.Automation.Language.AssignmentStatementAst]) {
                    if (-not (Test-WholeScriptEvalFallbackAllowed -Ast $planStatement)) {
                        $executionFailed = $true
                        break
                    }

                    $assignResult = Invoke-InContext -ExecContext $execContext -Code ([string]$planStatement.Extent.Text) -TimeoutMs $TimeoutMs -PersistOnSuccess:$true
                    if (-not $assignResult.Success) {
                        $executionFailed = $true
                        break
                    }
                    continue
                }

                if ($planStatement -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
                    if (-not (Test-WholeScriptLocalHelperFunctionAllowed -FunctionAst $planStatement)) {
                        $executionFailed = $true
                        break
                    }

                    $helperResult = Invoke-InContext -ExecContext $execContext -Code ([string]$planStatement.Extent.Text) -TimeoutMs $TimeoutMs -PersistOnSuccess:$true
                    if (-not $helperResult.Success) {
                        $executionFailed = $true
                        break
                    }
                    continue
                }

                $bootstrapArgAst = Get-GatedRoundDynamicIexArgumentAst -Statement $planStatement
                if ($null -eq $bootstrapArgAst) {
                    $executionFailed = $true
                    break
                }

                $bootstrapText = Try-EvaluateWholeScriptExpressionInExecContext -ExecContext $execContext -ExpressionAst $bootstrapArgAst -TimeoutMs $TimeoutMs
                if ([string]::IsNullOrWhiteSpace($bootstrapText) -or
                    -not (Test-WholeScriptBootstrapHelperScriptAllowed -ScriptText $bootstrapText -RequiredHelperNames @($helperNames))) {
                    $executionFailed = $true
                    break
                }

                $bootstrapResult = Invoke-InContext -ExecContext $execContext -Code $bootstrapText -TimeoutMs $TimeoutMs -PersistOnSuccess:$true
                if (-not $bootstrapResult.Success) {
                    $executionFailed = $true
                    break
                }
            }

            if ($executionFailed) {
                continue
            }

            $candidateText = Try-EvaluateWholeScriptExpressionInExecContext -ExecContext $execContext -ExpressionAst $sinkArgAst -TimeoutMs $TimeoutMs
            if ([string]::IsNullOrWhiteSpace($candidateText)) {
                continue
            }

            $normalizedInfo = Get-WholeScriptNormalizedPayloadInfo -Text $candidateText -OriginalText $ScriptText -Source 'gated_helper_bootstrap'
            if ($null -eq $normalizedInfo) {
                continue
            }

            $candidateScript = if ($normalizedInfo.PSObject.Properties['ScriptText']) { [string]$normalizedInfo.ScriptText } else { $null }
            if ([string]::IsNullOrWhiteSpace($candidateScript) -or -not (Test-UsefulRecoveredScriptText -Text $candidateScript)) {
                continue
            }

            return [PSCustomObject]@{
                PayloadText = $candidateScript
                Source      = 'gated_helper_bootstrap'
            }
        } finally {
            try {
                Close-ExecutionContext -ExecContext $execContext
            } catch {
            }
        }
    }

    return $null
}

function Invoke-WholeScriptStaticSideEffectCommand {
    param(
        [Parameter(Mandatory)][System.Management.Automation.Language.CommandAst]$CommandAst,
        [Parameter(Mandatory)][hashtable]$Context,
        [int]$Depth = 0
    )

    if (-not $Context.ExecContext) {
        return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = $false; Message = '缺少执行上下文' }
    }

    $cmdName = Convert-DynamicCommandCandidateToName -Value $CommandAst.GetCommandName()
    if ([string]::IsNullOrWhiteSpace($cmdName)) {
        return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = $false; Message = '命令名无法静态解析' }
    }

    $binding = Get-StaticCommandArgumentBinding -CommandAst $CommandAst
    switch -Regex ($cmdName) {
        '^(?i:set-variable|sv|new-variable|nv)$' {
            $nameAst = $null
            foreach ($key in @('name', 'n')) {
                if ($binding.Parameters.ContainsKey($key) -and $binding.Parameters[$key]) {
                    $nameAst = $binding.Parameters[$key]
                    break
                }
            }
            if ($null -eq $nameAst -and $binding.Positional.Count -gt 0) {
                $nameAst = $binding.Positional[0]
            }

            $valueAst = $null
            foreach ($key in @('value', 'v')) {
                if ($binding.Parameters.ContainsKey($key)) {
                    $valueAst = $binding.Parameters[$key]
                    break
                }
            }
            if ($null -eq $valueAst -and $binding.Positional.Count -gt 1) {
                $valueAst = $binding.Positional[1]
            }

            $varName = Try-GetStaticStringValue -Ast $nameAst -Context $Context
            if ([string]::IsNullOrWhiteSpace($varName)) {
                return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = $false; Message = 'Set-Variable/New-Variable 的变量名无法静态解析' }
            }

            $resolvedValue = [PSCustomObject]@{ Success = $true; Value = $null; UsedEmptyFallback = $false; Message = $null }
            if ($null -ne $valueAst) {
                $resolvedValue = Resolve-StaticAstValue -Ast $valueAst -Context $Context -AllowEmptyFallback:$false -Depth ($Depth + 1)
                if (-not $resolvedValue.Success) {
                    return [PSCustomObject]@{
                        Success           = $false
                        OutputItems       = @()
                        UsedEmptyFallback = [bool]$resolvedValue.UsedEmptyFallback
                        Message           = $resolvedValue.Message
                    }
                }
                if (-not (Test-StaticBindingValue -Value $resolvedValue.Value)) {
                    return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = [bool]$resolvedValue.UsedEmptyFallback; Message = '变量值类型不支持静态绑定' }
                }
            }

            try {
                $Context.ExecContext.Runspace.SessionStateProxy.SetVariable([string]$varName, $resolvedValue.Value)
            } catch {
                return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = [bool]$resolvedValue.UsedEmptyFallback; Message = $_.Exception.Message }
            }

            return [PSCustomObject]@{
                Success           = $true
                OutputItems       = @()
                UsedEmptyFallback = [bool]$resolvedValue.UsedEmptyFallback
                Message           = $null
            }
        }
        '^(?i:set-item|si)$' {
            $pathAst = $null
            foreach ($key in @('literalpath', 'path', 'lp')) {
                if ($binding.Parameters.ContainsKey($key) -and $binding.Parameters[$key]) {
                    $pathAst = $binding.Parameters[$key]
                    break
                }
            }
            if ($null -eq $pathAst -and $binding.Positional.Count -gt 0) {
                $pathAst = $binding.Positional[0]
            }

            $pathText = Try-GetStaticStringValue -Ast $pathAst -Context $Context
            if ([string]::IsNullOrWhiteSpace($pathText) -or $pathText -notmatch '^(?i:variable:)(.+)$') {
                return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = $false; Message = 'Set-Item 路径不在静态支持范围内' }
            }

            $varName = $Matches[1]
            if ([string]::IsNullOrWhiteSpace($varName)) {
                return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = $false; Message = 'Set-Item 变量路径无效' }
            }

            $valueAst = $null
            foreach ($key in @('value')) {
                if ($binding.Parameters.ContainsKey($key)) {
                    $valueAst = $binding.Parameters[$key]
                    break
                }
            }
            if ($null -eq $valueAst -and $binding.Positional.Count -gt 1) {
                $valueAst = $binding.Positional[1]
            }
            if ($null -eq $valueAst) {
                return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = $false; Message = 'Set-Item 缺少值参数' }
            }

            $resolvedValue = Resolve-StaticAstValue -Ast $valueAst -Context $Context -AllowEmptyFallback:$false -Depth ($Depth + 1)
            if (-not $resolvedValue.Success) {
                return [PSCustomObject]@{
                    Success           = $false
                    OutputItems       = @()
                    UsedEmptyFallback = [bool]$resolvedValue.UsedEmptyFallback
                    Message           = $resolvedValue.Message
                }
            }
            if (-not (Test-StaticBindingValue -Value $resolvedValue.Value)) {
                return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = [bool]$resolvedValue.UsedEmptyFallback; Message = 'Set-Item 值类型不支持静态绑定' }
            }

            try {
                $Context.ExecContext.Runspace.SessionStateProxy.SetVariable([string]$varName, $resolvedValue.Value)
            } catch {
                return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = [bool]$resolvedValue.UsedEmptyFallback; Message = $_.Exception.Message }
            }

            return [PSCustomObject]@{
                Success           = $true
                OutputItems       = @()
                UsedEmptyFallback = [bool]$resolvedValue.UsedEmptyFallback
                Message           = $null
            }
        }
        '^(?i:new-item|ni)$' {
            $pathAst = $null
            foreach ($key in @('literalpath', 'path', 'lp')) {
                if ($binding.Parameters.ContainsKey($key) -and $binding.Parameters[$key]) {
                    $pathAst = $binding.Parameters[$key]
                    break
                }
            }
            if ($null -eq $pathAst -and $binding.Positional.Count -gt 0) {
                $pathAst = $binding.Positional[0]
            }

            $pathText = Resolve-WholeScriptStaticArtifactPathTextFromAst -Ast $pathAst -Context $Context
            if ([string]::IsNullOrWhiteSpace($pathText)) {
                return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = $false; Message = 'New-Item 路径无法静态解析' }
            }

            $itemTypeAst = $null
            foreach ($key in @('itemtype', 'type')) {
                if ($binding.Parameters.ContainsKey($key) -and $binding.Parameters[$key]) {
                    $itemTypeAst = $binding.Parameters[$key]
                    break
                }
            }
            if ($null -eq $itemTypeAst -and $binding.Positional.Count -gt 1) {
                $itemTypeAst = $binding.Positional[1]
            }
            $itemTypeText = Resolve-WholeScriptStaticCommandValueTextFromAst -Ast $itemTypeAst -Context $Context
            $kind = if ($itemTypeText -match '^(?i:directory|container)$') { 'Directory' } else { 'File' }

            if (Test-WholeScriptStaticRegistryPath -PathText $pathText) {
                Set-WholeScriptStaticRegistryArtifactValue -Context $Context -PathText $pathText -Name '(default)' -ValueText $null | Out-Null
                Add-WholeScriptStaticArtifactEvent -Context $Context -Action 'write' -Path $pathText -Kind 'Registry' -Detail 'New-Item'
            } else {
                $record = Ensure-WholeScriptStaticFileArtifact -Context $Context -PathText $pathText -Kind $kind
                if ($record -and $kind -eq 'File' -and $null -eq $record.ContentText) {
                    $record.ContentText = ''
                }
                Add-WholeScriptStaticArtifactEvent -Context $Context -Action 'write' -Path $pathText -Kind $kind -Detail 'New-Item'
            }

            return [PSCustomObject]@{ Success = $true; OutputItems = @(); UsedEmptyFallback = $false; Message = $null }
        }
        '^(?i:set-content|sc)$' {
            $pathAst = $null
            foreach ($key in @('literalpath', 'path', 'lp')) {
                if ($binding.Parameters.ContainsKey($key) -and $binding.Parameters[$key]) {
                    $pathAst = $binding.Parameters[$key]
                    break
                }
            }
            if ($null -eq $pathAst -and $binding.Positional.Count -gt 0) {
                $pathAst = $binding.Positional[0]
            }

            $pathText = Resolve-WholeScriptStaticArtifactPathTextFromAst -Ast $pathAst -Context $Context
            if ([string]::IsNullOrWhiteSpace($pathText) -or (Test-WholeScriptStaticRegistryPath -PathText $pathText)) {
                return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = $false; Message = 'Set-Content 路径不在静态 artifact 范围内' }
            }

            $valueAst = $null
            foreach ($key in @('value')) {
                if ($binding.Parameters.ContainsKey($key)) {
                    $valueAst = $binding.Parameters[$key]
                    break
                }
            }
            if ($null -eq $valueAst -and $binding.Positional.Count -gt 1) {
                $valueAst = $binding.Positional[1]
            }

            $resolvedValue = Resolve-StaticAstValue -Ast $valueAst -Context $Context -AllowEmptyFallback:$false -Depth ($Depth + 1)
            if (-not $resolvedValue.Success) {
                return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = [bool]$resolvedValue.UsedEmptyFallback; Message = $resolvedValue.Message }
            }

            $noNewline = $binding.Parameters.ContainsKey('nonewline')
            $contentText = Convert-WholeScriptStaticValueToDelimitedText -Value $resolvedValue.Value -Delimiter $(if ($noNewline) { '' } else { "`r`n" })
            Set-WholeScriptStaticFileArtifactContent -Context $Context -PathText $pathText -ContentText $contentText -Kind 'File' -Append:$false -NoNewline:$noNewline | Out-Null
            Add-WholeScriptStaticArtifactEvent -Context $Context -Action 'write' -Path $pathText -Kind 'File' -Detail 'Set-Content'

            return [PSCustomObject]@{ Success = $true; OutputItems = @(); UsedEmptyFallback = [bool]$resolvedValue.UsedEmptyFallback; Message = $null }
        }
        '^(?i:add-content|ac)$' {
            $pathAst = $null
            foreach ($key in @('literalpath', 'path', 'lp')) {
                if ($binding.Parameters.ContainsKey($key) -and $binding.Parameters[$key]) {
                    $pathAst = $binding.Parameters[$key]
                    break
                }
            }
            if ($null -eq $pathAst -and $binding.Positional.Count -gt 0) {
                $pathAst = $binding.Positional[0]
            }

            $pathText = Resolve-WholeScriptStaticArtifactPathTextFromAst -Ast $pathAst -Context $Context
            if ([string]::IsNullOrWhiteSpace($pathText) -or (Test-WholeScriptStaticRegistryPath -PathText $pathText)) {
                return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = $false; Message = 'Add-Content 路径不在静态 artifact 范围内' }
            }

            $valueAst = $null
            foreach ($key in @('value')) {
                if ($binding.Parameters.ContainsKey($key)) {
                    $valueAst = $binding.Parameters[$key]
                    break
                }
            }
            if ($null -eq $valueAst -and $binding.Positional.Count -gt 1) {
                $valueAst = $binding.Positional[1]
            }

            $resolvedValue = Resolve-StaticAstValue -Ast $valueAst -Context $Context -AllowEmptyFallback:$false -Depth ($Depth + 1)
            if (-not $resolvedValue.Success) {
                return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = [bool]$resolvedValue.UsedEmptyFallback; Message = $resolvedValue.Message }
            }

            $contentText = Convert-WholeScriptStaticValueToDelimitedText -Value $resolvedValue.Value -Delimiter "`r`n"
            Set-WholeScriptStaticFileArtifactContent -Context $Context -PathText $pathText -ContentText $contentText -Kind 'File' -Append:$true | Out-Null
            Add-WholeScriptStaticArtifactEvent -Context $Context -Action 'write' -Path $pathText -Kind 'File' -Detail 'Add-Content'

            return [PSCustomObject]@{ Success = $true; OutputItems = @(); UsedEmptyFallback = [bool]$resolvedValue.UsedEmptyFallback; Message = $null }
        }
        '^(?i:out-file)$' {
            $pathAst = $null
            foreach ($key in @('filepath', 'literalpath', 'path')) {
                if ($binding.Parameters.ContainsKey($key) -and $binding.Parameters[$key]) {
                    $pathAst = $binding.Parameters[$key]
                    break
                }
            }
            if ($null -eq $pathAst -and $binding.Positional.Count -gt 0) {
                $pathAst = $binding.Positional[0]
            }

            $pathText = Resolve-WholeScriptStaticArtifactPathTextFromAst -Ast $pathAst -Context $Context
            if ([string]::IsNullOrWhiteSpace($pathText) -or (Test-WholeScriptStaticRegistryPath -PathText $pathText)) {
                return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = $false; Message = 'Out-File 路径不在静态 artifact 范围内' }
            }

            $valueAst = $null
            foreach ($key in @('inputobject')) {
                if ($binding.Parameters.ContainsKey($key) -and $binding.Parameters[$key]) {
                    $valueAst = $binding.Parameters[$key]
                    break
                }
            }
            if ($null -eq $valueAst -and $binding.Positional.Count -gt 1) {
                $valueAst = $binding.Positional[1]
            }
            if ($null -eq $valueAst) {
                return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = $false; Message = 'Out-File 缺少可静态解析的输入对象' }
            }

            $resolvedValue = Resolve-StaticAstValue -Ast $valueAst -Context $Context -AllowEmptyFallback:$false -Depth ($Depth + 1)
            if (-not $resolvedValue.Success) {
                return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = [bool]$resolvedValue.UsedEmptyFallback; Message = $resolvedValue.Message }
            }

            $append = $binding.Parameters.ContainsKey('append')
            $noNewline = $binding.Parameters.ContainsKey('nonewline')
            $contentText = Convert-WholeScriptStaticValueToDelimitedText -Value $resolvedValue.Value -Delimiter $(if ($noNewline) { '' } else { "`r`n" })
            Set-WholeScriptStaticFileArtifactContent -Context $Context -PathText $pathText -ContentText $contentText -Kind 'File' -Append:$append -NoNewline:$noNewline | Out-Null
            Add-WholeScriptStaticArtifactEvent -Context $Context -Action 'write' -Path $pathText -Kind 'File' -Detail $(if ($append) { 'Out-File -Append' } else { 'Out-File' })

            return [PSCustomObject]@{ Success = $true; OutputItems = @(); UsedEmptyFallback = [bool]$resolvedValue.UsedEmptyFallback; Message = $null }
        }
        '^(?i:clear-content|clc)$' {
            $pathAst = $null
            foreach ($key in @('literalpath', 'path', 'lp')) {
                if ($binding.Parameters.ContainsKey($key) -and $binding.Parameters[$key]) {
                    $pathAst = $binding.Parameters[$key]
                    break
                }
            }
            if ($null -eq $pathAst -and $binding.Positional.Count -gt 0) {
                $pathAst = $binding.Positional[0]
            }

            $pathText = Resolve-WholeScriptStaticArtifactPathTextFromAst -Ast $pathAst -Context $Context
            if ([string]::IsNullOrWhiteSpace($pathText) -or (Test-WholeScriptStaticRegistryPath -PathText $pathText)) {
                return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = $false; Message = 'Clear-Content 路径不在静态 artifact 范围内' }
            }

            Set-WholeScriptStaticFileArtifactContent -Context $Context -PathText $pathText -ContentText '' -Kind 'File' | Out-Null
            Add-WholeScriptStaticArtifactEvent -Context $Context -Action 'write' -Path $pathText -Kind 'File' -Detail 'Clear-Content'
            return [PSCustomObject]@{ Success = $true; OutputItems = @(); UsedEmptyFallback = $false; Message = $null }
        }
        '^(?i:copy-item|copy|cp|cpi)$' {
            $sourceAst = $null
            foreach ($key in @('literalpath', 'path', 'lp')) {
                if ($binding.Parameters.ContainsKey($key) -and $binding.Parameters[$key]) {
                    $sourceAst = $binding.Parameters[$key]
                    break
                }
            }
            if ($null -eq $sourceAst -and $binding.Positional.Count -gt 0) {
                $sourceAst = $binding.Positional[0]
            }

            $destinationAst = $null
            foreach ($key in @('destination', 'dest')) {
                if ($binding.Parameters.ContainsKey($key) -and $binding.Parameters[$key]) {
                    $destinationAst = $binding.Parameters[$key]
                    break
                }
            }
            if ($null -eq $destinationAst -and $binding.Positional.Count -gt 1) {
                $destinationAst = $binding.Positional[1]
            }

            $sourcePathText = Resolve-WholeScriptStaticArtifactPathTextFromAst -Ast $sourceAst -Context $Context
            $destinationPathText = Resolve-WholeScriptStaticArtifactPathTextFromAst -Ast $destinationAst -Context $Context
            if ([string]::IsNullOrWhiteSpace($sourcePathText) -or [string]::IsNullOrWhiteSpace($destinationPathText)) {
                return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = $false; Message = 'Copy-Item 路径无法静态解析' }
            }

            $sourceRecord = Get-WholeScriptStaticFileArtifact -Context $Context -PathText $sourcePathText
            if ($null -eq $sourceRecord) {
                return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = $false; Message = 'Copy-Item 源不在静态 artifact 范围内' }
            }

            $resolvedDestinationPath = Resolve-WholeScriptStaticCopyDestinationPathText -SourcePathText $sourcePathText -DestinationPathText $destinationPathText -Context $Context
            $destRecord = Ensure-WholeScriptStaticFileArtifact -Context $Context -PathText $resolvedDestinationPath -Kind ([string]$sourceRecord.Kind)
            if ($null -eq $destRecord) {
                return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = $false; Message = 'Copy-Item 目标不在静态 artifact 范围内' }
            }

            $destRecord.ContentText = [string]$sourceRecord.ContentText
            $destRecord.IsPowerShell = [bool]$sourceRecord.IsPowerShell
            $destRecord.Properties = if ($null -ne $sourceRecord.Properties) { @{} + $sourceRecord.Properties } else { @{} }
            Add-WholeScriptStaticArtifactReferencedPath -Record $destRecord -PathText $sourcePathText -Context $Context
            Add-WholeScriptStaticArtifactEvent -Context $Context -Action 'write' -Path $resolvedDestinationPath -Kind ([string]$destRecord.Kind) -Detail ('Copy-Item <= ' + $sourcePathText)

            return [PSCustomObject]@{ Success = $true; OutputItems = @(); UsedEmptyFallback = $false; Message = $null }
        }
        '^(?i:remove-item|rm|ri|del|erase|rd)$' {
            $pathAst = $null
            foreach ($key in @('literalpath', 'path', 'lp')) {
                if ($binding.Parameters.ContainsKey($key) -and $binding.Parameters[$key]) {
                    $pathAst = $binding.Parameters[$key]
                    break
                }
            }
            if ($null -eq $pathAst -and $binding.Positional.Count -gt 0) {
                $pathAst = $binding.Positional[0]
            }

            $pathText = Resolve-WholeScriptStaticArtifactPathTextFromAst -Ast $pathAst -Context $Context
            if ([string]::IsNullOrWhiteSpace($pathText)) {
                return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = $false; Message = 'Remove-Item 路径无法静态解析' }
            }

            $removed = Remove-WholeScriptStaticArtifact -Context $Context -PathText $pathText
            if ($removed) {
                Add-WholeScriptStaticArtifactEvent -Context $Context -Action 'remove' -Path $pathText -Kind $(if (Test-WholeScriptStaticRegistryPath -PathText $pathText) { 'Registry' } else { 'File' }) -Detail 'Remove-Item'
            }

            return [PSCustomObject]@{ Success = $true; OutputItems = @(); UsedEmptyFallback = $false; Message = $null }
        }
        '^(?i:set-itemproperty)$' {
            $pathAst = $null
            foreach ($key in @('literalpath', 'path', 'lp')) {
                if ($binding.Parameters.ContainsKey($key) -and $binding.Parameters[$key]) {
                    $pathAst = $binding.Parameters[$key]
                    break
                }
            }
            if ($null -eq $pathAst -and $binding.Positional.Count -gt 0) {
                $pathAst = $binding.Positional[0]
            }

            $pathText = Resolve-WholeScriptStaticArtifactPathTextFromAst -Ast $pathAst -Context $Context
            if ([string]::IsNullOrWhiteSpace($pathText)) {
                return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = $false; Message = 'Set-ItemProperty 路径无法静态解析' }
            }

            $nameAst = $null
            foreach ($key in @('name')) {
                if ($binding.Parameters.ContainsKey($key) -and $binding.Parameters[$key]) {
                    $nameAst = $binding.Parameters[$key]
                    break
                }
            }
            if ($null -eq $nameAst -and $binding.Positional.Count -gt 1) {
                $nameAst = $binding.Positional[1]
            }

            $valueAst = $null
            foreach ($key in @('value')) {
                if ($binding.Parameters.ContainsKey($key) -and $binding.Parameters[$key]) {
                    $valueAst = $binding.Parameters[$key]
                    break
                }
            }
            if ($null -eq $valueAst -and $binding.Positional.Count -gt 2) {
                $valueAst = $binding.Positional[2]
            }

            $nameText = Resolve-WholeScriptStaticCommandValueTextFromAst -Ast $nameAst -Context $Context
            $valueText = Resolve-WholeScriptStaticCommandValueTextFromAst -Ast $valueAst -Context $Context
            if ([string]::IsNullOrWhiteSpace($nameText)) {
                return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = $false; Message = 'Set-ItemProperty 属性名无法静态解析' }
            }

            if (Test-WholeScriptStaticRegistryPath -PathText $pathText) {
                Set-WholeScriptStaticRegistryArtifactValue -Context $Context -PathText $pathText -Name $nameText -ValueText $valueText | Out-Null
                Add-WholeScriptStaticArtifactEvent -Context $Context -Action 'write' -Path $pathText -Kind 'Registry' -Detail ('Set-ItemProperty ' + $nameText)
            } else {
                $record = Ensure-WholeScriptStaticFileArtifact -Context $Context -PathText $pathText -Kind 'File'
                if ($null -eq $record.Properties) {
                    $record.Properties = @{}
                }
                $record.Properties[[string]$nameText] = $valueText
                Add-WholeScriptStaticArtifactEvent -Context $Context -Action 'write' -Path $pathText -Kind 'File' -Detail ('Set-ItemProperty ' + $nameText)
            }

            return [PSCustomObject]@{ Success = $true; OutputItems = @(); UsedEmptyFallback = $false; Message = $null }
        }
        '^(?i:remove-itemproperty)$' {
            $pathAst = $null
            foreach ($key in @('literalpath', 'path', 'lp')) {
                if ($binding.Parameters.ContainsKey($key) -and $binding.Parameters[$key]) {
                    $pathAst = $binding.Parameters[$key]
                    break
                }
            }
            if ($null -eq $pathAst -and $binding.Positional.Count -gt 0) {
                $pathAst = $binding.Positional[0]
            }

            $nameAst = $null
            foreach ($key in @('name')) {
                if ($binding.Parameters.ContainsKey($key) -and $binding.Parameters[$key]) {
                    $nameAst = $binding.Parameters[$key]
                    break
                }
            }
            if ($null -eq $nameAst -and $binding.Positional.Count -gt 1) {
                $nameAst = $binding.Positional[1]
            }

            $pathText = Resolve-WholeScriptStaticArtifactPathTextFromAst -Ast $pathAst -Context $Context
            $nameText = Resolve-WholeScriptStaticCommandValueTextFromAst -Ast $nameAst -Context $Context
            if ([string]::IsNullOrWhiteSpace($pathText) -or [string]::IsNullOrWhiteSpace($nameText)) {
                return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = $false; Message = 'Remove-ItemProperty 参数无法静态解析' }
            }

            if (Test-WholeScriptStaticRegistryPath -PathText $pathText) {
                $pathInfo = Get-WholeScriptStaticArtifactPathInfo -PathText $pathText -Context $Context
                $store = Get-WholeScriptStaticArtifactStore -Context $Context
                if ($pathInfo -and $store.Registry.ContainsKey($pathInfo.CanonicalPath)) {
                    $record = $store.Registry[$pathInfo.CanonicalPath]
                    if ($record.Values.ContainsKey([string]$nameText)) {
                        $null = $record.Values.Remove([string]$nameText)
                    }
                }
                Add-WholeScriptStaticArtifactEvent -Context $Context -Action 'remove' -Path $pathText -Kind 'Registry' -Detail ('Remove-ItemProperty ' + $nameText)
            } else {
                $record = Get-WholeScriptStaticFileArtifact -Context $Context -PathText $pathText
                if ($record -and $record.Properties -and $record.Properties.ContainsKey([string]$nameText)) {
                    $null = $record.Properties.Remove([string]$nameText)
                }
                Add-WholeScriptStaticArtifactEvent -Context $Context -Action 'remove' -Path $pathText -Kind 'File' -Detail ('Remove-ItemProperty ' + $nameText)
            }

            return [PSCustomObject]@{ Success = $true; OutputItems = @(); UsedEmptyFallback = $false; Message = $null }
        }
    }

    return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = $false; Message = ('暂不支持的静态副作用命令: ' + $cmdName) }
}

function Invoke-WholeScriptStaticStatement {
    param(
        $Statement,
        [Parameter(Mandatory)][hashtable]$Context,
        [bool]$AllowEmptyFallback = $false,
        [int]$Depth = 0
    )

    if ($null -eq $Statement) {
        return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = $false; Message = '语句为空' }
    }

    if ($Statement -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
        return Register-WholeScriptStaticPureHelperFunction -FunctionAst $Statement -Context $Context -TimeoutMs 2000
    }

    if ($Statement -is [System.Management.Automation.Language.AssignmentStatementAst]) {
        $rhsAst = $Statement.Right
        if ($null -eq $rhsAst) {
            return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = $false; Message = '赋值语句缺少右值' }
        }

        $resolved = Resolve-StaticAstValue -Ast $rhsAst -Context $Context -AllowEmptyFallback:$AllowEmptyFallback -Depth ($Depth + 1)
        if (-not $resolved.Success) {
            return [PSCustomObject]@{
                Success           = $false
                OutputItems       = @()
                UsedEmptyFallback = [bool]$resolved.UsedEmptyFallback
                Message           = $resolved.Message
            }
        }
        if (-not (Test-StaticBindingValue -Value $resolved.Value)) {
            return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = [bool]$resolved.UsedEmptyFallback; Message = '赋值右值类型不支持静态绑定' }
        }

        if ($Statement.Left -is [System.Management.Automation.Language.VariableExpressionAst]) {
            $varName = [string]$Statement.Left.VariablePath.UserPath
            if ([string]::IsNullOrWhiteSpace($varName)) {
                return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = [bool]$resolved.UsedEmptyFallback; Message = '变量名为空' }
            }

            if ($Context.ExecContext) {
                try {
                    $Context.ExecContext.Runspace.SessionStateProxy.SetVariable($varName, $resolved.Value)
                } catch {
                    return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = [bool]$resolved.UsedEmptyFallback; Message = $_.Exception.Message }
                }
            }
        } elseif ($Statement.Left -is [System.Management.Automation.Language.MemberExpressionAst]) {
            if ($Statement.Left.Static) {
                return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = [bool]$resolved.UsedEmptyFallback; Message = '暂不支持静态成员赋值' }
            }

            $targetResult = Resolve-StaticAstValue -Ast $Statement.Left.Expression -Context $Context -AllowEmptyFallback:$false -Depth ($Depth + 1)
            if (-not $targetResult.Success) {
                return [PSCustomObject]@{
                    Success           = $false
                    OutputItems       = @()
                    UsedEmptyFallback = ([bool]$resolved.UsedEmptyFallback -or [bool]$targetResult.UsedEmptyFallback)
                    Message           = $targetResult.Message
                }
            }

            $memberName = Get-StaticMemberNameText -MemberAst $Statement.Left.Member -Context $Context
            if ([string]::IsNullOrWhiteSpace($memberName)) {
                return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = ([bool]$resolved.UsedEmptyFallback -or [bool]$targetResult.UsedEmptyFallback); Message = '成员名无法静态解析' }
            }

            $setResult = Set-StaticMemberAccessValue -TargetValue $targetResult.Value -MemberName $memberName -MemberValue $resolved.Value
            if (-not $setResult.Success) {
                return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = ([bool]$resolved.UsedEmptyFallback -or [bool]$targetResult.UsedEmptyFallback); Message = $setResult.Message }
            }
        } elseif ($Statement.Left -is [System.Management.Automation.Language.IndexExpressionAst]) {
            $targetResult = Resolve-StaticAstValue -Ast $Statement.Left.Target -Context $Context -AllowEmptyFallback:$false -Depth ($Depth + 1)
            if (-not $targetResult.Success) {
                return [PSCustomObject]@{
                    Success           = $false
                    OutputItems       = @()
                    UsedEmptyFallback = ([bool]$resolved.UsedEmptyFallback -or [bool]$targetResult.UsedEmptyFallback)
                    Message           = $targetResult.Message
                }
            }

            $indexResult = Resolve-StaticAstValue -Ast $Statement.Left.Index -Context $Context -AllowEmptyFallback:$false -Depth ($Depth + 1)
            if (-not $indexResult.Success) {
                return [PSCustomObject]@{
                    Success           = $false
                    OutputItems       = @()
                    UsedEmptyFallback = ([bool]$resolved.UsedEmptyFallback -or [bool]$targetResult.UsedEmptyFallback -or [bool]$indexResult.UsedEmptyFallback)
                    Message           = $indexResult.Message
                }
            }

            $setResult = Set-StaticIndexedValue -TargetValue $targetResult.Value -IndexValue $indexResult.Value -AssignedValue $resolved.Value
            if (-not $setResult.Success) {
                return [PSCustomObject]@{
                    Success           = $false
                    OutputItems       = @()
                    UsedEmptyFallback = ([bool]$resolved.UsedEmptyFallback -or [bool]$targetResult.UsedEmptyFallback -or [bool]$indexResult.UsedEmptyFallback)
                    Message           = $setResult.Message
                }
            }
        } else {
            return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = [bool]$resolved.UsedEmptyFallback; Message = '暂不支持的赋值左值类型' }
        }

        return [PSCustomObject]@{
            Success           = $true
            OutputItems       = @($resolved.Value)
            UsedEmptyFallback = [bool]$resolved.UsedEmptyFallback
            Message           = $null
        }
    }

    if ($Statement -is [System.Management.Automation.Language.PipelineAst]) {
        return Resolve-StaticPipelineAstValue -PipelineAst $Statement -Context $Context -AllowEmptyFallback:$AllowEmptyFallback -Depth ($Depth + 1)
    }

    if ($Statement -is [System.Management.Automation.Language.CommandAst]) {
        return Invoke-WholeScriptStaticCommand -CommandAst $Statement -Context $Context -Depth ($Depth + 1)
    }

    if ($Statement -is [System.Management.Automation.Language.ExpressionAst]) {
        $resolved = Resolve-StaticAstValue -Ast $Statement -Context $Context -AllowEmptyFallback:$AllowEmptyFallback -Depth ($Depth + 1)
        if (-not $resolved.Success) {
            return [PSCustomObject]@{
                Success           = $false
                OutputItems       = @()
                UsedEmptyFallback = [bool]$resolved.UsedEmptyFallback
                Message           = $resolved.Message
            }
        }

        return [PSCustomObject]@{
            Success           = $true
            OutputItems       = @(Convert-StaticValueToPipelineOutputItems -Value $resolved.Value)
            UsedEmptyFallback = [bool]$resolved.UsedEmptyFallback
            Message           = $null
        }
    }

    return [PSCustomObject]@{ Success = $false; OutputItems = @(); UsedEmptyFallback = $false; Message = '暂不支持的静态语句类型' }
}

function Initialize-WholeScriptStaticAssignments {
    param(
        [object[]]$Statements = @(),
        [Parameter(Mandatory)][hashtable]$Context
    )

    if (-not $Context.ExecContext) {
        return $false
    }

    $pending = @($Statements | Where-Object { $null -ne $_ })

    $successKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $maxPasses = [Math]::Max(1, [Math]::Min(8, $pending.Count))

    for ($pass = 0; $pass -lt $maxPasses -and $pending.Count -gt 0; $pass++) {
        $state = Get-StaticEvalState -Context $Context
        if ($state) {
            $state.StringCompatCache = @{}
            $state.ValueCache = @{}
            $state.StringCompatInProgress = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
            $state.ValueInProgress = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
        }

        $progress = $false
        $nextPending = @()
        foreach ($statement in @($pending)) {
            try {
                $statementResult = Invoke-WholeScriptStaticStatement -Statement $statement -Context $Context -AllowEmptyFallback:$false
            } catch {
                if (-not (Test-IsCallDepthOverflowException -ErrorObject $_)) {
                    throw
                }

                $statementResult = [PSCustomObject]@{
                    Success           = $false
                    OutputItems       = @()
                    UsedEmptyFallback = $false
                    Message           = ('静态初始化语句因调用深度溢出已跳过: ' + (Get-ErrorSummaryText -ErrorObject $_ -DefaultMessage 'call depth overflow'))
                }
            }
            if ($statementResult.Success) {
                $statementKey = if ($statement -and $statement.Extent) {
                    '{0}:{1}' -f [int]$statement.Extent.StartOffset, [int]$statement.Extent.EndOffset
                } else {
                    'pass:{0}:{1}' -f $pass, [guid]::NewGuid().ToString('N')
                }
                if ($successKeys.Add($statementKey)) {
                    $progress = $true
                }
            } else {
                $nextPending += ,$statement
            }
        }

        if (-not $progress) {
            break
        }

        $pending = $nextPending
    }

    return ($successKeys.Count -gt 0)
}

function Get-CommandAstStaticDynamicPayloadInfo {
    param(
        [Parameter(Mandatory)][System.Management.Automation.Language.CommandAst]$CommandAst,
        [hashtable]$Context,
        [object[]]$PrefixStatements = @()
    )

    $wrapped = $null
    try {
        $wrapped = Get-WrappedDynamicInvocationInfo -CommandAst $CommandAst
    } catch {
        $wrapped = $null
    }
    if (-not $wrapped) {
        try {
            $wrapped = Get-CompatibilityWrappedDynamicInvocationInfo -CommandAst $CommandAst
        } catch {
            $wrapped = $null
        }
    }
    if ($wrapped) {
        return $wrapped
    }

    $elements = @($CommandAst.CommandElements)
    $wrapperOperator = $null
    $targetAst = $null
    $argumentStartIndex = 1

    switch ([string]$CommandAst.InvocationOperator) {
        'Ampersand' {
            if ($elements.Count -ge 1) {
                $wrapperOperator = '&'
                $targetAst = $elements[0]
            }
        }
        'Dot' {
            if ($elements.Count -ge 1) {
                $wrapperOperator = '.'
                $targetAst = $elements[0]
            }
        }
    }

    if (-not $wrapperOperator) {
        $headText = if ($elements.Count -gt 0 -and $elements[0] -and $elements[0].Extent) { [string]$elements[0].Extent.Text } else { $null }
        if ($headText -in @('&', '.')) {
            if ($elements.Count -lt 2) { return $null }
            $wrapperOperator = $headText
            $targetAst = $elements[1]
            $argumentStartIndex = 2
        }
    }

    $cmdName = $null
    if ($wrapperOperator -and $targetAst -and $Context) {
        try {
            $resolvedHead = Resolve-SafeCommandNameExpressionValue -Ast $targetAst -Context $Context
        } catch {
            $resolvedHead = $null
        }

        if ($resolvedHead -and $resolvedHead.Success) {
            $cmdName = Convert-ResolvedCommandCandidateToName -Value $resolvedHead.Value
        }

        if ([string]::IsNullOrWhiteSpace($cmdName)) {
            $staticHeadText = Try-GetStaticStringValue -Ast $targetAst -Context $Context
            if (-not [string]::IsNullOrWhiteSpace($staticHeadText)) {
                $cmdName = Convert-ResolvedCommandCandidateToName -Value $staticHeadText
            }
        }

        if ([string]::IsNullOrWhiteSpace($cmdName)) {
            $runtimeHeadText = Try-EvaluateWholeScriptPayloadExpression -PrefixStatements $PrefixStatements -ExpressionAst $targetAst
            if (-not [string]::IsNullOrWhiteSpace($runtimeHeadText)) {
                $cmdName = Convert-ResolvedCommandCandidateToName -Value $runtimeHeadText
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($cmdName)) {
        $cmdName = Convert-DynamicCommandCandidateToName -Value $CommandAst.GetCommandName()
    }

    if ($cmdName -in @('Invoke-Expression', 'iex')) {
        $argAst = if ($elements.Count -gt $argumentStartIndex) { $elements[$argumentStartIndex] } else { $null }
        return [PSCustomObject]@{
            DynamicType = 'IEX'
            ArgumentAst = $argAst
        }
    }

    if (Test-PowerShellHostCommandName -CommandName $cmdName) {
        $hostInfo = $null
        try {
            $hostInfo = Get-PowerShellHostDynamicInvocationInfo -CommandAst $CommandAst
        } catch {
            $hostInfo = $null
        }

        if ($hostInfo -and -not [string]::IsNullOrWhiteSpace([string]$hostInfo.DynamicType)) {
            return [PSCustomObject]@{
                DynamicType = [string]$hostInfo.DynamicType
                ArgumentAst = $hostInfo.ArgumentAst
            }
        }
    }

    return $null
}

function Get-WholeScriptStaticDeterministicTestDrivePath {
    param([hashtable]$Context)

    $pathContext = Get-WholeScriptStaticPathContext -Context $Context
    if ($pathContext -and -not [string]::IsNullOrWhiteSpace([string]$pathContext.TestDriveRoot)) {
        return [string]$pathContext.TestDriveRoot
    }

    if ($pathContext -and -not [string]::IsNullOrWhiteSpace([string]$pathContext.CurrentDirectory)) {
        try {
            return [System.IO.Path]::Combine([string]$pathContext.CurrentDirectory, 'PSDissect-TestDrive')
        } catch {
            return (([string]$pathContext.CurrentDirectory).TrimEnd('\') + '\PSDissect-TestDrive')
        }
    }

    return 'C:\PSDissect-TestDrive'
}

function Initialize-WholeScriptSpecialVariables {
    param(
        $ExecContext,
        [hashtable]$Context = $null
    )

    if ($null -eq $ExecContext -or $null -eq $ExecContext.Runspace) {
        return
    }

    $pathContext = Get-WholeScriptStaticPathContext -Context $Context
    $variables = [ordered]@{
        TestDrive    = Get-WholeScriptStaticDeterministicTestDrivePath -Context $Context
        PSScriptRoot = if ($pathContext) { [string]$pathContext.ScriptDirectory } else { $null }
        PSCommandPath = if ($pathContext) { [string]$pathContext.ScriptPath } else { $null }
    }

    foreach ($entry in $variables.GetEnumerator()) {
        if ([string]::IsNullOrWhiteSpace([string]$entry.Value)) {
            continue
        }
        try {
            $ExecContext.Runspace.SessionStateProxy.SetVariable([string]$entry.Key, [string]$entry.Value)
        } catch {
        }
    }
}

function Convert-WholeScriptStaticPathToSymbolicRoot {
    param(
        [AllowNull()][string]$PathText,
        [hashtable]$Context
    )

    if ([string]::IsNullOrWhiteSpace($PathText)) {
        return $null
    }

    $candidate = ([string]$PathText).Trim()
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        return $null
    }
    if ($candidate -notmatch '^(?:[A-Za-z]:\\|\\\\[^\\]+\\[^\\]+)') {
        return $candidate
    }

    $pathContext = Get-WholeScriptStaticPathContext -Context $Context
    if ($null -eq $pathContext -or $null -eq $pathContext.EnvironmentPaths) {
        return $candidate
    }

    $preferredNames = @('TEMP', 'TMP', 'APPDATA', 'LOCALAPPDATA', 'PROGRAMDATA', 'PUBLIC', 'WINDIR', 'SYSTEMROOT', 'USERPROFILE')
    $preferredRanks = @{}
    for ($i = 0; $i -lt $preferredNames.Count; $i++) {
        $preferredRanks[$preferredNames[$i]] = $i
    }

    $mappings = @()
    foreach ($entry in $pathContext.EnvironmentPaths.GetEnumerator()) {
        $name = [string]$entry.Key
        $root = [string]$entry.Value
        if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($root)) {
            continue
        }
        if ($name -notin $preferredNames) {
            continue
        }

        $mappings += [PSCustomObject]@{
            Name = $name
            Root = ($root -replace '/', '\').TrimEnd('\')
            Rank = [int]$preferredRanks[$name]
        }
    }

    foreach ($mapping in @($mappings | Sort-Object @{ Expression = { $_.Root.Length }; Descending = $true }, @{ Expression = { $_.Rank }; Descending = $false })) {
        $root = [string]$mapping.Root
        if ([string]::IsNullOrWhiteSpace($root)) {
            continue
        }

        if ($candidate.Equals($root, [System.StringComparison]::OrdinalIgnoreCase)) {
            return ('%' + [string]$mapping.Name + '%')
        }
        if ($candidate.StartsWith($root + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
            return (('%' + [string]$mapping.Name + '%') + '\' + $candidate.Substring($root.Length + 1))
        }
    }

    return $candidate
}

function Test-StatementsContainMandatoryBase64Consumer {
    param([object[]]$Statements = @())

    foreach ($statement in @($Statements)) {
        if ($null -eq $statement -or -not $statement.Extent) {
            continue
        }

        if (Test-MandatoryBase64ConsumerText -Text ([string]$statement.Extent.Text)) {
            return $true
        }
    }

    return $false
}

function Resolve-MandatoryBase64ExpressionTextValue {
    param(
        $Ast,
        [Parameter(Mandatory)][hashtable]$Context,
        [bool]$AllowIndirect = $false
    )

    if ($null -eq $Ast) {
        return $null
    }

    $containsBase64Consumer = Test-MandatoryBase64ExpressionAst -Ast $Ast
    if (-not $containsBase64Consumer -and -not $AllowIndirect) {
        return $null
    }

    $directText = Resolve-DirectBase64TextFromAst -Ast $Ast -Context $Context
    if (-not [string]::IsNullOrWhiteSpace($directText)) {
        return $directText
    }

    try {
        $resolved = Resolve-StaticAstValue -Ast $Ast -Context $Context -AllowEmptyFallback:$false
    } catch {
        if (Test-IsCallDepthOverflowException -ErrorObject $_) {
            return $null
        }
        throw
    }

    if (-not $resolved -or -not $resolved.Success) {
        return $null
    }

    return (Convert-StaticValueToMeaningfulString -Value $resolved.Value)
}

function Resolve-MandatoryBase64CommandPayloadText {
    param(
        [Parameter(Mandatory)][System.Management.Automation.Language.CommandAst]$CommandAst,
        [Parameter(Mandatory)][hashtable]$Context,
        [object[]]$PrefixStatements = @(),
        [bool]$AllowIndirect = $false
    )

    $dynamicInfo = Get-CommandAstStaticDynamicPayloadInfo -CommandAst $CommandAst -Context $Context -PrefixStatements $PrefixStatements
    if (-not $dynamicInfo -or -not $dynamicInfo.ArgumentAst) {
        return $null
    }

    if ([string]$dynamicInfo.DynamicType -eq 'EncodedCommand') {
        $encoded = Resolve-MandatoryBase64ExpressionTextValue -Ast $dynamicInfo.ArgumentAst -Context $Context -AllowIndirect:$true
        if ([string]::IsNullOrWhiteSpace($encoded)) {
            $encoded = Try-GetStaticStringValue -Ast $dynamicInfo.ArgumentAst -Context $Context
        }
        if ([string]::IsNullOrWhiteSpace($encoded)) {
            return $null
        }

        return (Try-DecodeEncodedCommandValue -Base64String $encoded)
    }

    return (Resolve-MandatoryBase64ExpressionTextValue -Ast $dynamicInfo.ArgumentAst -Context $Context -AllowIndirect:$AllowIndirect)
}

function Try-Resolve-WholeScriptMandatoryBase64PayloadInfo {
    param([Parameter(Mandatory)][string]$ScriptText)

    if ([string]::IsNullOrWhiteSpace($ScriptText)) {
        return $null
    }

    $hostPayloadInfo = Resolve-WholeScriptHostPayloadInfo -ScriptText $ScriptText
    if ($hostPayloadInfo -and [string]$hostPayloadInfo.DynamicType -eq 'EncodedCommand' -and
        -not [string]::IsNullOrWhiteSpace([string]$hostPayloadInfo.PayloadText)) {
        $normalizedHostText = Try-NormalizeRecoveredScriptText -Text ([string]$hostPayloadInfo.PayloadText)
        if (-not [string]::IsNullOrWhiteSpace($normalizedHostText)) {
            return [PSCustomObject]@{
                PayloadText  = $normalizedHostText
                DecodeSource = if ($hostPayloadInfo.PSObject.Properties['DecodeSource']) { [string]$hostPayloadInfo.DecodeSource } else { 'mandatory_base64_encodedcommand' }
            }
        }
    }

    $statements = @(Get-TopLevelScriptStatementsFromText -ScriptText $ScriptText)
    if ($statements.Count -eq 0) {
        return $null
    }

    $ctx = New-WholeScriptStaticResolutionContext
    try {
        $staticEvalState = Get-StaticEvalState -Context $ctx
        if ($staticEvalState) {
            $staticEvalState.ValueDepthLimit = 96
            $staticEvalState.StringCompatDepthLimit = 72
        }
        $ctx.SafeMode = $true

        $prefixStatements = @()
        if ($statements.Count -gt 1) {
            $prefixStatements = @($statements | Select-Object -First ($statements.Count - 1))
            [void](Initialize-WholeScriptStaticAssignments -Statements $prefixStatements -Context $ctx)
        }
        $allowIndirect = (Test-StatementsContainMandatoryBase64Consumer -Statements $prefixStatements)

        $targetStatement = $statements[-1]
        $payloadText = $null
        $decodeSource = $null

        if ($targetStatement -is [System.Management.Automation.Language.CommandAst]) {
            $payloadText = Resolve-MandatoryBase64CommandPayloadText -CommandAst $targetStatement -Context $ctx -PrefixStatements $prefixStatements -AllowIndirect:$allowIndirect
            if ($payloadText) {
                $decodeSource = 'mandatory_base64_command'
            }
        } elseif ($targetStatement -is [System.Management.Automation.Language.PipelineAst]) {
            $elements = @($targetStatement.PipelineElements)
            if ($elements.Count -eq 1 -and $elements[0] -is [System.Management.Automation.Language.CommandAst]) {
                $payloadText = Resolve-MandatoryBase64CommandPayloadText -CommandAst $elements[0] -Context $ctx -PrefixStatements $prefixStatements -AllowIndirect:$allowIndirect
                if ($payloadText) {
                    $decodeSource = 'mandatory_base64_pipeline_command'
                }
            } elseif ($elements.Count -eq 1 -and
                (($elements[0] -is [System.Management.Automation.Language.CommandExpressionAst]) -or $elements[0].PSObject.Properties['Expression'])) {
                $expr = if ($elements[0] -is [System.Management.Automation.Language.CommandExpressionAst]) {
                    $elements[0].Expression
                } else {
                    $elements[0].Expression
                }
                $payloadText = Resolve-MandatoryBase64ExpressionTextValue -Ast $expr -Context $ctx -AllowIndirect:$allowIndirect
                if ($payloadText) {
                    $decodeSource = 'mandatory_base64_pipeline_expression'
                }
            } elseif ($elements.Count -eq 2 -and $elements[-1] -is [System.Management.Automation.Language.CommandAst]) {
                $sinkInfo = Get-CommandAstStaticDynamicPayloadInfo -CommandAst $elements[-1] -Context $ctx -PrefixStatements $prefixStatements
                if ($sinkInfo -and [string]$sinkInfo.DynamicType -eq 'IEX') {
                    $sourceAst = $elements[0]
                    if ($elements[0] -is [System.Management.Automation.Language.CommandExpressionAst]) {
                        $sourceAst = $elements[0].Expression
                    } elseif ($elements[0].PSObject.Properties['Expression']) {
                        $sourceAst = $elements[0].Expression
                    } elseif ($elements[0] -is [System.Management.Automation.Language.CommandAst]) {
                        $payloadText = Resolve-MandatoryBase64CommandPayloadText -CommandAst $elements[0] -Context $ctx -PrefixStatements $prefixStatements -AllowIndirect:$allowIndirect
                    }

                    if (-not $payloadText -and $sourceAst) {
                        $payloadText = Resolve-MandatoryBase64ExpressionTextValue -Ast $sourceAst -Context $ctx -AllowIndirect:$allowIndirect
                    }
                    if ($payloadText) {
                        $decodeSource = 'mandatory_base64_pipeline_iex'
                    }
                }
            }
        }

        if (-not $payloadText -and $statements.Count -eq 1) {
            $expr = Get-SingleTopLevelExpressionAstFromText -ScriptText $ScriptText
            if ($expr) {
                $payloadText = Resolve-MandatoryBase64ExpressionTextValue -Ast $expr -Context $ctx -AllowIndirect:$allowIndirect
                if ($payloadText) {
                    $decodeSource = 'mandatory_base64_expression'
                }
            }
        }

        $payloadText = Get-WholeScriptReplacementCandidateText -OriginalText $ScriptText -CandidateText (Try-NormalizeRecoveredScriptText -Text $payloadText)
        if (-not $payloadText) {
            return $null
        }

        return [PSCustomObject]@{
            PayloadText  = $payloadText
            DecodeSource = $decodeSource
        }
    } catch {
        if (-not (Test-IsCallDepthOverflowException -ErrorObject $_)) {
            throw
        }
        return $null
    } finally {
        Close-WholeScriptStaticResolutionContext -Context $ctx
    }
}

function Resolve-WholeScriptStaticPayloadInfo {
    param(
        [Parameter(Mandatory)][string]$ScriptText,
        [ValidateSet('Disabled', 'Conservative', 'Balanced', 'Aggressive')]
        [string]$PreExecutionGateMode = 'Disabled',
        [hashtable]$PreExecutionGateCache = $null,
        [bool]$SafeMode = $true
    )

    if ([string]::IsNullOrWhiteSpace($ScriptText)) {
        return $null
    }

    $statements = @(Get-TopLevelScriptStatementsFromText -ScriptText $ScriptText)
    if ($statements.Count -eq 0) {
        return $null
    }

    $ctx = New-WholeScriptStaticResolutionContext
    try {
        $staticEvalState = Get-StaticEvalState -Context $ctx
        if ($staticEvalState) {
            $staticEvalState.ValueDepthLimit = 64
            $staticEvalState.StringCompatDepthLimit = 48
        }
        $ctx.SafeMode = $SafeMode

        $prefixStatements = @()
        if ($statements.Count -gt 1) {
            $prefixStatements = @($statements | Select-Object -First ($statements.Count - 1))
            [void](Initialize-WholeScriptStaticAssignments -Statements $prefixStatements -Context $ctx)
        }

        $targetStatement = $statements[-1]
        $payloadText = $null
        $decodeSource = $null
        $helperEvidence = @()

        $applyRuntimeHelperPayload = {
            param(
                [AllowNull()][string]$RuntimeText,
                [string]$RuntimeSource
            )

            if ([string]::IsNullOrWhiteSpace($RuntimeText)) {
                return
            }

            $normalizedInfo = Get-WholeScriptNormalizedPayloadInfo -Text $RuntimeText -OriginalText $ScriptText -Source $RuntimeSource
            if ($null -eq $normalizedInfo) {
                return
            }

            if ($normalizedInfo.PSObject.Properties['Evidence'] -and $normalizedInfo.Evidence) {
                $script:__psdissect_whole_script_helper_evidence = @($script:__psdissect_whole_script_helper_evidence + @($normalizedInfo.Evidence))
            }

            $candidateScript = if ($normalizedInfo.PSObject.Properties['ScriptText']) { [string]$normalizedInfo.ScriptText } else { $null }
            if ([string]::IsNullOrWhiteSpace($candidateScript)) {
                return
            }

            $helperGate = Get-PreExecutionGateDecision -Scope 'WholeScriptHelper' -ScriptText $candidateScript -Mode $PreExecutionGateMode -SafeMode:$SafeMode -Cache $PreExecutionGateCache
            if ([string]$helperGate.Decision -eq 'Stop') {
                return
            }

            $candidateParse = Get-ScriptParseInfo -ScriptText $candidateScript
            if ($candidateParse.IsValid) {
                if (-not $payloadText -or (Test-RecoveredScriptLooksWrapperLiteral -Text $payloadText)) {
                    $payloadText = $candidateScript
                }
            } elseif (-not $payloadText -and $candidateScript -match '(?s)<#\s*PSDissect-SensitiveEvidence') {
                $payloadText = $candidateScript
            }
        }

        $script:__psdissect_whole_script_helper_evidence = @()

        if ($targetStatement -is [System.Management.Automation.Language.CommandAst]) {
            $artifactPayloadInfo = Resolve-WholeScriptStaticArtifactPayloadInfoFromCommandAst -CommandAst $targetStatement -Context $ctx
            if ($artifactPayloadInfo -and -not [string]::IsNullOrWhiteSpace([string]$artifactPayloadInfo.PayloadText)) {
                $payloadText = [string]$artifactPayloadInfo.PayloadText
                $decodeSource = if ($artifactPayloadInfo.PSObject.Properties['DecodeSource']) { [string]$artifactPayloadInfo.DecodeSource } else { 'static_artifact_command' }
            }
        } elseif ($targetStatement -is [System.Management.Automation.Language.PipelineAst]) {
            $elements = @($targetStatement.PipelineElements)
            if ($elements.Count -eq 1 -and $elements[0] -is [System.Management.Automation.Language.CommandAst]) {
                $artifactPayloadInfo = Resolve-WholeScriptStaticArtifactPayloadInfoFromCommandAst -CommandAst $elements[0] -Context $ctx
                if ($artifactPayloadInfo -and -not [string]::IsNullOrWhiteSpace([string]$artifactPayloadInfo.PayloadText)) {
                    $payloadText = [string]$artifactPayloadInfo.PayloadText
                    $decodeSource = if ($artifactPayloadInfo.PSObject.Properties['DecodeSource']) { [string]$artifactPayloadInfo.DecodeSource } else { 'static_artifact_pipeline_command' }
                }
            } elseif ($elements.Count -eq 2 -and $elements[0] -is [System.Management.Automation.Language.CommandAst] -and $elements[1] -is [System.Management.Automation.Language.CommandAst]) {
                $sinkName = Convert-DynamicCommandCandidateToName -Value $elements[1].GetCommandName()
                if ($sinkName -in @('Invoke-Expression', 'iex')) {
                    $sourceResult = Invoke-WholeScriptStaticCommand -CommandAst $elements[0] -Context $ctx
                    if ($sourceResult -and $sourceResult.Success) {
                        $sourceText = Convert-WholeScriptStaticOutputItemsToScriptText -Items @($sourceResult.OutputItems)
                        $normalizedSourceText = Try-NormalizeRecoveredScriptText -Text $sourceText
                        if ($normalizedSourceText) {
                            $payloadText = $normalizedSourceText
                            $decodeSource = 'static_artifact_pipeline_iex'
                        }
                    }
                }
            }
        }

        if (-not $payloadText -and $targetStatement -is [System.Management.Automation.Language.CommandAst]) {
            $dynamicInfo = Get-CommandAstStaticDynamicPayloadInfo -CommandAst $targetStatement -Context $ctx -PrefixStatements $prefixStatements
                if ($dynamicInfo -and $dynamicInfo.ArgumentAst) {
                    if ([string]$dynamicInfo.DynamicType -eq 'EncodedCommand') {
                        $encoded = Try-GetStaticStringValue -Ast $dynamicInfo.ArgumentAst -Context $ctx
                        $decoded = if ($encoded) { Try-DecodeEncodedCommandValue -Base64String $encoded } else { $null }
                        $payloadText = Try-NormalizeRecoveredScriptText -Text $decoded
                        $runtimeEncoded = Try-EvaluateWholeScriptPayloadExpressionWithLocalHelpers -PrefixStatements $prefixStatements -ExpressionAst $dynamicInfo.ArgumentAst -SafeMode:$SafeMode -PreExecutionGateMode $PreExecutionGateMode -PreExecutionGateCache $PreExecutionGateCache
                        $runtimeDecoded = if ($runtimeEncoded) { Try-DecodeEncodedCommandValue -Base64String $runtimeEncoded } else { $null }
                        & $applyRuntimeHelperPayload $runtimeDecoded 'whole_script_runtime_encoded'
                    } else {
                        $payloadText = Try-NormalizeRecoveredScriptText -Text (Try-GetStaticStringValue -Ast $dynamicInfo.ArgumentAst -Context $ctx)
                        & $applyRuntimeHelperPayload (Try-EvaluateWholeScriptPayloadExpressionWithLocalHelpers -PrefixStatements $prefixStatements -ExpressionAst $dynamicInfo.ArgumentAst -SafeMode:$SafeMode -PreExecutionGateMode $PreExecutionGateMode -PreExecutionGateCache $PreExecutionGateCache) 'whole_script_runtime_dynamic'
                    }

                    if ($payloadText) {
                        $decodeSource = 'static_command_' + ([string]$dynamicInfo.DynamicType).ToLowerInvariant()
                    }
            }
        } elseif (-not $payloadText -and $targetStatement -is [System.Management.Automation.Language.PipelineAst]) {
            $elements = @($targetStatement.PipelineElements)
            if ($elements.Count -eq 1 -and $elements[0] -is [System.Management.Automation.Language.CommandAst]) {
                $dynamicInfo = Get-CommandAstStaticDynamicPayloadInfo -CommandAst $elements[0] -Context $ctx -PrefixStatements $prefixStatements
                if ($dynamicInfo -and $dynamicInfo.ArgumentAst) {
                    if ([string]$dynamicInfo.DynamicType -eq 'EncodedCommand') {
                        $encoded = Try-GetStaticStringValue -Ast $dynamicInfo.ArgumentAst -Context $ctx
                        $decoded = if ($encoded) { Try-DecodeEncodedCommandValue -Base64String $encoded } else { $null }
                        $payloadText = Try-NormalizeRecoveredScriptText -Text $decoded
                        $runtimeEncoded = Try-EvaluateWholeScriptPayloadExpressionWithLocalHelpers -PrefixStatements $prefixStatements -ExpressionAst $dynamicInfo.ArgumentAst -SafeMode:$SafeMode -PreExecutionGateMode $PreExecutionGateMode -PreExecutionGateCache $PreExecutionGateCache
                        $runtimeDecoded = if ($runtimeEncoded) { Try-DecodeEncodedCommandValue -Base64String $runtimeEncoded } else { $null }
                        & $applyRuntimeHelperPayload $runtimeDecoded 'whole_script_runtime_pipeline_encoded'
                    } else {
                        $payloadText = Try-NormalizeRecoveredScriptText -Text (Try-GetStaticStringValue -Ast $dynamicInfo.ArgumentAst -Context $ctx)
                        & $applyRuntimeHelperPayload (Try-EvaluateWholeScriptPayloadExpressionWithLocalHelpers -PrefixStatements $prefixStatements -ExpressionAst $dynamicInfo.ArgumentAst -SafeMode:$SafeMode -PreExecutionGateMode $PreExecutionGateMode -PreExecutionGateCache $PreExecutionGateCache) 'whole_script_runtime_pipeline_dynamic'
                    }

                    if ($payloadText) {
                        $decodeSource = 'static_pipeline_single_command'
                    }
                }
            } elseif ($elements.Count -eq 1 -and
                (($elements[0] -is [System.Management.Automation.Language.CommandExpressionAst]) -or $elements[0].PSObject.Properties['Expression'])) {
                $expr = if ($elements[0] -is [System.Management.Automation.Language.CommandExpressionAst]) {
                    $elements[0].Expression
                } else {
                    $elements[0].Expression
                }
                $payloadText = Try-NormalizeRecoveredScriptText -Text (Try-GetStaticStringValue -Ast $expr -Context $ctx)
                & $applyRuntimeHelperPayload (Try-EvaluateWholeScriptPayloadExpressionWithLocalHelpers -PrefixStatements $prefixStatements -ExpressionAst $expr -SafeMode:$SafeMode -PreExecutionGateMode $PreExecutionGateMode -PreExecutionGateCache $PreExecutionGateCache) 'whole_script_runtime_expression'
                if ($payloadText) {
                    $decodeSource = 'static_pipeline_single_expression'
                }
            } elseif ($elements.Count -eq 2 -and $elements[-1] -is [System.Management.Automation.Language.CommandAst]) {
                $dynamicInfo = Get-CommandAstStaticDynamicPayloadInfo -CommandAst $elements[-1] -Context $ctx -PrefixStatements $prefixStatements
                if ($dynamicInfo -and [string]$dynamicInfo.DynamicType -eq 'IEX') {
                    $sourceExpr = $null
                    if ($elements[0] -is [System.Management.Automation.Language.CommandExpressionAst]) {
                        $sourceExpr = $elements[0].Expression
                    } elseif ($elements[0].PSObject.Properties['Expression']) {
                        $sourceExpr = $elements[0].Expression
                    } elseif ($elements[0] -is [System.Management.Automation.Language.CommandAst]) {
                        $sourceDynamicInfo = Get-CommandAstStaticDynamicPayloadInfo -CommandAst $elements[0] -Context $ctx -PrefixStatements $prefixStatements
                        if ($sourceDynamicInfo -and $sourceDynamicInfo.ArgumentAst) {
                            if ([string]$sourceDynamicInfo.DynamicType -eq 'EncodedCommand') {
                                $encoded = Try-GetStaticStringValue -Ast $sourceDynamicInfo.ArgumentAst -Context $ctx
                                $decoded = if ($encoded) { Try-DecodeEncodedCommandValue -Base64String $encoded } else { $null }
                                $payloadText = Try-NormalizeRecoveredScriptText -Text $decoded
                            } else {
                                $payloadText = Try-NormalizeRecoveredScriptText -Text (Try-GetStaticStringValue -Ast $sourceDynamicInfo.ArgumentAst -Context $ctx)
                            }

                            if ($payloadText) {
                                $decodeSource = 'static_pipeline_dynamic_source'
                            }
                        }
                    }

                        if ($sourceExpr) {
                            if (-not $payloadText) {
                                $payloadText = Try-NormalizeRecoveredScriptText -Text (Try-GetStaticStringValue -Ast $sourceExpr -Context $ctx)
                            }
                            & $applyRuntimeHelperPayload (Try-EvaluateWholeScriptPayloadExpressionWithLocalHelpers -PrefixStatements $prefixStatements -ExpressionAst $sourceExpr -SafeMode:$SafeMode -PreExecutionGateMode $PreExecutionGateMode -PreExecutionGateCache $PreExecutionGateCache) 'whole_script_runtime_iex_source'
                        if ($payloadText) {
                            $decodeSource = 'static_pipeline_iex'
                        }
                    }
                }
            }
        }

        if (-not $payloadText -and $statements.Count -eq 1) {
            $expr = Get-SingleTopLevelExpressionAstFromText -ScriptText $ScriptText
            if ($expr) {
                $payloadText = Try-NormalizeRecoveredScriptText -Text (Try-GetStaticStringValue -Ast $expr -Context $ctx)
                if (-not $payloadText) {
                    & $applyRuntimeHelperPayload (Try-EvaluateWholeScriptPayloadExpressionWithLocalHelpers -ExpressionAst $expr -SafeMode:$SafeMode -PreExecutionGateMode $PreExecutionGateMode -PreExecutionGateCache $PreExecutionGateCache) 'whole_script_runtime_single_expression'
                }
                if ($payloadText) {
                    $decodeSource = 'static_whole_expression'
                }
            }
        }

        $helperEvidence = @($script:__psdissect_whole_script_helper_evidence)
        Remove-Variable -Name __psdissect_whole_script_helper_evidence -Scope Script -ErrorAction SilentlyContinue

        $payloadText = Get-WholeScriptReplacementCandidateText -OriginalText $ScriptText -CandidateText $payloadText
        if (-not $payloadText) {
            if ($helperEvidence.Count -gt 0) {
                $payloadText = Append-SensitiveEvidenceCommentBlock -ScriptText $ScriptText -Evidence $helperEvidence
            } else {
                return $null
            }
        }

        return [PSCustomObject]@{
            PayloadText  = $payloadText
            DecodeSource = $decodeSource
        }
    } finally {
        Remove-Variable -Name __psdissect_whole_script_helper_evidence -Scope Script -ErrorAction SilentlyContinue
        Close-WholeScriptStaticResolutionContext -Context $ctx
    }
}

function Test-PreserveWholeScriptStaticExpressionStructure {
    param(
        [Parameter(Mandatory)][string]$ScriptText,
        [int]$StartOffset,
        [int]$EndOffset
    )

    $expr = Get-SingleTopLevelExpressionAstFromText -ScriptText $ScriptText
    if ($null -eq $expr -or -not $expr.Extent) {
        return $false
    }

    if ([int]$expr.Extent.StartOffset -ne $StartOffset -or [int]$expr.Extent.EndOffset -ne $EndOffset) {
        return $false
    }

    return ($expr -is [System.Management.Automation.Language.MemberExpressionAst] -or
        $expr -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -or
        $expr -is [System.Management.Automation.Language.IndexExpressionAst])
}

function Get-LiteralStringValueFromExpressionText {
    param([Parameter(Mandatory)][string]$ScriptText)

    $expr = Get-SingleTopLevelExpressionAstFromText -ScriptText $ScriptText
    if ($null -eq $expr) {
        return $null
    }

    if ($expr -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
        return [string]$expr.Value
    }

    if ($expr -is [System.Management.Automation.Language.ConstantExpressionAst] -and $expr.Value -is [string]) {
        return [string]$expr.Value
    }

    if ($expr -is [System.Management.Automation.Language.ExpandableStringExpressionAst] -and @($expr.NestedExpressions).Count -eq 0) {
        return [string]$expr.Value
    }

    return $null
}

function Get-ExpandableStringLiteralOnlyValue {
    param(
        [Parameter(Mandatory)][System.Management.Automation.Language.ExpandableStringExpressionAst]$Ast,
        [Parameter(Mandatory)][string]$SourceText
    )

    if ([string]::IsNullOrEmpty($SourceText) -or $SourceText.Length -lt 2) {
        return $null
    }

    if ($SourceText[0] -ne '"' -or $SourceText[$SourceText.Length - 1] -ne '"') {
        return $null
    }

    $nestedExpressions = @($Ast.NestedExpressions | Where-Object { $_ -and $_.Extent } | Sort-Object { $_.Extent.StartOffset })
    if ($nestedExpressions.Count -eq 0) {
        return [string]$Ast.Value
    }

    $builder = New-Object System.Text.StringBuilder
    $cursor = 1
    $contentEnd = $SourceText.Length - 1

    foreach ($nested in $nestedExpressions) {
        $nestedStart = [int]$nested.Extent.StartOffset
        $nestedEnd = [int]$nested.Extent.EndOffset
        if ($nestedStart -lt $cursor) { continue }
        if ($nestedStart -gt $contentEnd) { break }

        if ($nestedStart -gt $cursor) {
            [void]$builder.Append($SourceText.Substring($cursor, $nestedStart - $cursor))
        }

        $cursor = [Math]::Min($nestedEnd, $contentEnd)
    }

    if ($cursor -lt $contentEnd) {
        [void]$builder.Append($SourceText.Substring($cursor, $contentEnd - $cursor))
    }

    $syntheticText = '"' + $builder.ToString() + '"'
    return (Get-LiteralStringValueFromExpressionText -ScriptText $syntheticText)
}

function Test-ResolvableExpandableStringCandidateSafe {
    param(
        [Parameter(Mandatory)][string]$Original,
        [Parameter(Mandatory)][string]$Replacement,
        [AllowNull()]$Type
    )

    $safeResult = [PSCustomObject]@{
        Safe    = $true
        Reason  = $null
        Message = $null
    }

    if ($Type -ne 'ExpandableString') {
        return $safeResult
    }

    $originalExpr = Get-SingleTopLevelExpressionAstFromText -ScriptText $Original
    if ($originalExpr -isnot [System.Management.Automation.Language.ExpandableStringExpressionAst]) {
        return $safeResult
    }

    if (@($originalExpr.NestedExpressions).Count -eq 0) {
        return $safeResult
    }

    $literalOnlyValue = Get-ExpandableStringLiteralOnlyValue -Ast $originalExpr -SourceText $Original
    if ($null -eq $literalOnlyValue) {
        return $safeResult
    }

    $replacementLiteral = Get-LiteralStringValueFromExpressionText -ScriptText $Replacement
    if ($null -eq $replacementLiteral) {
        $replacementLiteral = [string]$Replacement
    }

    if ([string]$replacementLiteral -eq [string]$literalOnlyValue) {
        return [PSCustomObject]@{
            Safe    = $false
            Reason  = 'resolvable_runtime_dependent_interpolation'
            Message = 'ExpandableString 的执行结果仅剩静态骨架，疑似丢失运行时插值内容，跳过回填'
        }
    }

    return $safeResult
}

function Try-Resolve-CanonicalCommandNameText {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return [PSCustomObject]@{
            Found = $false
            Name  = $null
        }
    }

    $lookup = $null
    try {
        if (Get-Command Get-SafeCommandLookupResults -ErrorAction SilentlyContinue) {
            $lookup = @(Get-SafeCommandLookupResults -Name $Name) | Select-Object -First 1
        } else {
            $lookup = @(Get-Command -Name $Name -ErrorAction SilentlyContinue) | Select-Object -First 1
        }
    } catch {
        $lookup = $null
    }

    if ($lookup) {
        if ($lookup.CommandType -eq [System.Management.Automation.CommandTypes]::Alias -and
            -not [string]::IsNullOrWhiteSpace([string]$lookup.Definition)) {
            return [PSCustomObject]@{
                Found = $true
                Name  = [string]$lookup.Definition
            }
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$lookup.Name)) {
            return [PSCustomObject]@{
                Found = $true
                Name  = [string]$lookup.Name
            }
        }
    }

    if (Get-Command Resolve-CompatibilityAliasName -ErrorAction SilentlyContinue) {
        $compatAlias = Resolve-CompatibilityAliasName -Name $Name
        if (-not [string]::IsNullOrWhiteSpace($compatAlias)) {
            return [PSCustomObject]@{
                Found = $true
                Name  = [string]$compatAlias
            }
        }
    }

    return [PSCustomObject]@{
        Found = $false
        Name  = $null
    }
}

function Resolve-CanonicalCommandNameText {
    param([string]$Name)

    $resolved = Try-Resolve-CanonicalCommandNameText -Name $Name
    if ($resolved.Found -and -not [string]::IsNullOrWhiteSpace([string]$resolved.Name)) {
        return [string]$resolved.Name
    }

    return [string]$Name
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

function Test-SensitiveLiteralizableText {
    param(
        [AllowNull()][string]$Text,
        [string]$SinkKind = 'Generic'
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $false
    }

    $trimmed = $Text.Trim()
    $isUrlLike = ($trimmed -match '^(?i)(?:https?|ftp)://') -or
        ($trimmed -match '^(?:(?:\d{1,3}\.){3}\d{1,3})(?::\d+)?(?:/.*)?$') -or
        ($trimmed -match '^(?i:[A-Za-z0-9.-]+\.[A-Za-z]{2,})(?:[:/].*)?$')
    $isProcessArgLike = $trimmed -match '(?i)(?:https?://|\.hta\b|-enc(?:odedcommand)?\b|-command\b|mshta(?:\.exe)?|powershell(?:\.exe)?|pwsh(?:\.exe)?|wscript(?:\.exe)?|cscript(?:\.exe)?|cmd(?:\.exe)?\s+/c)'
    $isRegistryLike = $trimmed -match '^(?i:(?:registry::)?(?:hkcu|hklm|hkcr|hku|hkcc):\\|hkey_(?:current_user|local_machine|classes_root|users|current_config)\\)'
    $isFilePathLike = ($trimmed -match '^(?i:[a-z]:\\)') -or
        ($trimmed -match '^\\\\[^\\]+\\[^\\]+') -or
        ($trimmed -match '^(?i)(?:\.{1,2}\\|~\\|\$env:[A-Za-z_][A-Za-z0-9_]*\\|%[A-Za-z_][A-Za-z0-9_]*%\\)') -or
        (($trimmed -match '[\\/]' -or $trimmed -match '(?i)^(?:temp|appdata|programdata|desktop|documents|downloads|startup|system32|syswow64)$') -and
            $trimmed -notmatch '^(?i)(?:https?|ftp)://')
    if ($trimmed -match '^[\\/]+[*?]') {
        $isFilePathLike = $false
    }
    $isCommandTextLike = ($trimmed -match '(?i)\b(?:invoke-expression|iex|start-process|invoke-webrequest|invoke-restmethod|downloadstring|downloadfile|set-itemproperty|new-itemproperty|reg\s+add|reg\s+query|reg\s+delete|cmd(?:\.exe)?|powershell(?:\.exe)?|pwsh(?:\.exe)?)\b') -or
        (Test-UsefulRecoveredScriptText -Text $trimmed)
    $isLauncherArgLike = $isProcessArgLike -or
        ($trimmed -match '(?i)(?:\s|^)(?:/c|/k|-command|-file|-f|-enc|-encodedcommand|javascript:|vbscript:|http://|https://|\\\\)')

    switch ($SinkKind) {
        'Url' { return $isUrlLike }
        'Host' { return ($trimmed -match '^(?:(?:\d{1,3}\.){3}\d{1,3}|[A-Za-z0-9.-]+\.[A-Za-z]{2,})$') }
        'StartProcessArgs' { return ($isProcessArgLike -or $isUrlLike) }
        'LauncherArgs' { return ($isLauncherArgLike -or $isUrlLike -or $isFilePathLike) }
        'CommandText' { return ($isCommandTextLike -or $isUrlLike -or $isFilePathLike -or $isRegistryLike) }
        'FilePath' { return $isFilePathLike }
        'DirectoryPath' { return $isFilePathLike }
        'RegKey' { return $isRegistryLike }
        'RegValueName' { return ($trimmed -match '^[A-Za-z0-9 _.-]{1,128}$') }
        default { return ($isUrlLike -or $isProcessArgLike) }
    }
}

function New-FastSensitiveEvalFailureResult {
    param(
        [string]$Reason,
        [string]$Message
    )

    return [PSCustomObject]@{
        Success           = $false
        Value             = $null
        UsedEmptyFallback = $false
        Reason            = $Reason
        Message           = $Message
    }
}

function New-FastSensitiveEvalSuccessResult {
    param(
        $Value,
        [bool]$UsedEmptyFallback = $false
    )

    return [PSCustomObject]@{
        Success           = $true
        Value             = $Value
        UsedEmptyFallback = $UsedEmptyFallback
        Reason            = $null
        Message           = $null
    }
}

function Test-FastSensitiveAstWithinBudget {
    param(
        $Ast,
        [int]$MaxAstNodesPerTarget = 128,
        [int]$MaxDepth = 6
    )

    if ($null -eq $Ast) {
        return $false
    }

    $nodes = @($Ast.FindAll({ param($n) $true }, $true))
    if ($nodes.Count -gt [Math]::Max(1, $MaxAstNodesPerTarget)) {
        return $false
    }

    $rootParent = $Ast.Parent
    foreach ($node in $nodes) {
        $depth = 0
        $cursor = $node
        while ($null -ne $cursor -and $cursor -ne $rootParent) {
            $depth++
            if ($depth -gt [Math]::Max(1, $MaxDepth)) {
                return $false
            }
            $cursor = $cursor.Parent
        }
    }

    return $true
}

function Convert-FastSensitiveResolvedTextForSinkKind {
    param(
        [AllowNull()][string]$Text,
        [hashtable]$Context,
        [string]$SinkKind = 'Generic'
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }

    $normalized = ([string]$Text).Trim().Trim('"', "'", ' ')
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return $null
    }

    switch ($SinkKind) {
        { $_ -in @('FilePath', 'DirectoryPath', 'RegKey') } {
            $pathInfo = Get-WholeScriptStaticArtifactPathInfo -PathText $normalized -Context $Context
            if ($pathInfo -and -not [string]::IsNullOrWhiteSpace([string]$pathInfo.DisplayPath)) {
                return [string]$pathInfo.DisplayPath
            }
            return (Resolve-WholeScriptStaticDisplayPath -PathText $normalized -Context $Context)
        }
        'Host' {
            return ($normalized.Trim('"', "'", ' '))
        }
        'Url' {
            return ($normalized.Trim('"', "'", ' '))
        }
        default {
            return $normalized
        }
    }
}

function Convert-FastSensitiveResolvedValueToText {
    param(
        $Value,
        [hashtable]$Context,
        [string]$SinkKind = 'Generic',
        [int]$MaxResolvedTextLength = 8192
    )

    if ($null -eq $Value) {
        return $null
    }

    $text = Convert-StaticValueToMeaningfulString -Value $Value
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }

    $normalized = Convert-FastSensitiveResolvedTextForSinkKind -Text $text -Context $Context -SinkKind $SinkKind
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return $null
    }

    if ($MaxResolvedTextLength -gt 0 -and $normalized.Length -gt $MaxResolvedTextLength) {
        return $null
    }

    return [string]$normalized
}

function Resolve-FastSensitiveArguments {
    param(
        [object[]]$Arguments = @(),
        [hashtable]$Context,
        $Config,
        [int]$Depth = 0
    )

    $values = New-Object 'System.Collections.Generic.List[object]'
    $usedEmptyFallback = $false

    foreach ($argAst in @($Arguments)) {
        $argResult = Resolve-FastSensitiveExpressionValue -Ast $argAst -Context $Context -Config $Config -Depth ($Depth + 1)
        if (-not $argResult.Success) {
            return [PSCustomObject]@{
                Success           = $false
                Values            = @()
                UsedEmptyFallback = $usedEmptyFallback
                Reason            = $argResult.Reason
                Message           = $argResult.Message
            }
        }

        $usedEmptyFallback = ($usedEmptyFallback -or [bool]$argResult.UsedEmptyFallback)
        $values.Add($argResult.Value) | Out-Null
    }

    return [PSCustomObject]@{
        Success           = $true
        Values            = @($values.ToArray())
        UsedEmptyFallback = $usedEmptyFallback
        Reason            = $null
        Message           = $null
    }
}

function Resolve-FastSensitiveCommandValue {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [hashtable]$Context,
        $Config,
        [int]$Depth = 0
    )

    if ($null -eq $CommandAst) {
        return (New-FastSensitiveEvalFailureResult -Reason 'no_command_ast' -Message '命令 AST 为空')
    }

    $resolved = Resolve-StaticAstValue -Ast $CommandAst -Context $Context -AllowEmptyFallback:$true -Depth $Depth
    if ($resolved.Success) {
        return (New-FastSensitiveEvalSuccessResult -Value $resolved.Value -UsedEmptyFallback ([bool]$resolved.UsedEmptyFallback))
    }

    return (New-FastSensitiveEvalFailureResult -Reason $resolved.Reason -Message $resolved.Message)
}

function Resolve-FastSensitiveExpressionValue {
    param(
        $Ast,
        [hashtable]$Context,
        $Config,
        [int]$Depth = 0
    )

    if ($null -eq $Ast) {
        return (New-FastSensitiveEvalFailureResult -Reason 'no_ast' -Message 'AST 为空')
    }

    $maxDepth = if ($Config -and $Config.PSObject.Properties['MaxDepth']) { [int]$Config.MaxDepth } else { 6 }
    $maxNodes = if ($Config -and $Config.PSObject.Properties['MaxAstNodesPerTarget']) { [int]$Config.MaxAstNodesPerTarget } else { 128 }
    if ($Depth -gt $maxDepth) {
        return (New-FastSensitiveEvalFailureResult -Reason 'depth_limit' -Message 'fast sensitive 深度超限')
    }

    if (-not (Test-FastSensitiveAstWithinBudget -Ast $Ast -MaxAstNodesPerTarget $maxNodes -MaxDepth $maxDepth)) {
        return (New-FastSensitiveEvalFailureResult -Reason 'shape_budget' -Message 'AST 复杂度超过 fast sensitive 限制')
    }

    if (Test-StaticEvalBudgetExceeded -Context $Context) {
        return (New-FastSensitiveEvalFailureResult -Reason 'budget_exceeded' -Message 'fast sensitive 静态预算已耗尽')
    }

    if ($Ast -is [System.Management.Automation.Language.ParenExpressionAst]) {
        $expr = Get-StaticExpressionFromPipelineAst -PipelineAst $Ast.Pipeline
        if ($null -ne $expr) {
            return (Resolve-FastSensitiveExpressionValue -Ast $expr -Context $Context -Config $Config -Depth ($Depth + 1))
        }
    }

    if ($Ast -is [System.Management.Automation.Language.SubExpressionAst]) {
        $statements = @(Get-StaticExpressionFromStatementBlock -StatementBlockAst $Ast.SubExpression)
        if ($statements.Count -eq 1) {
            $expr = Get-StaticExpressionFromPipelineAst -PipelineAst $statements[0]
            if ($null -ne $expr) {
                return (Resolve-FastSensitiveExpressionValue -Ast $expr -Context $Context -Config $Config -Depth ($Depth + 1))
            }
        }
    }

    if ($Ast -is [System.Management.Automation.Language.CommandExpressionAst] -and $Ast.Expression) {
        return (Resolve-FastSensitiveExpressionValue -Ast $Ast.Expression -Context $Context -Config $Config -Depth ($Depth + 1))
    }

    if ($Ast -is [System.Management.Automation.Language.PipelineAst]) {
        $expr = Get-StaticExpressionFromPipelineAst -PipelineAst $Ast
        if ($null -ne $expr) {
            return (Resolve-FastSensitiveExpressionValue -Ast $expr -Context $Context -Config $Config -Depth ($Depth + 1))
        }
    }

    if ($Ast -is [System.Management.Automation.Language.CommandAst]) {
        return (Resolve-FastSensitiveCommandValue -CommandAst $Ast -Context $Context -Config $Config -Depth ($Depth + 1))
    }

    $resolved = Resolve-StaticAstValue -Ast $Ast -Context $Context -AllowEmptyFallback:$true -Depth $Depth
    if ($resolved.Success) {
        return (New-FastSensitiveEvalSuccessResult -Value $resolved.Value -UsedEmptyFallback ([bool]$resolved.UsedEmptyFallback))
    }

    return (New-FastSensitiveEvalFailureResult -Reason $resolved.Reason -Message $resolved.Message)
}

function Get-FastSensitiveReplacementTextInfo {
    param(
        $Ast,
        [hashtable]$Context,
        [string]$SinkKind = 'Generic',
        $Config = $null
    )

    if ($null -eq $Ast) {
        return $null
    }

    if ($null -eq $Config) {
        $Config = Get-FastSensitivePassConfig
    }

    $resolved = Resolve-FastSensitiveExpressionValue -Ast $Ast -Context $Context -Config $Config -Depth 0
    if (-not $resolved.Success) {
        return $null
    }

    $maxResolvedTextLength = if ($Config -and $Config.PSObject.Properties['MaxResolvedTextLength']) { [int]$Config.MaxResolvedTextLength } else { 8192 }
    $replacementText = $null
    $displayText = $null

    if (($resolved.Value -is [System.Collections.IEnumerable]) -and -not ($resolved.Value -is [string]) -and -not ($resolved.Value -is [char[]])) {
        $items = @()
        foreach ($item in @(Convert-StaticValueToStringArray -Value $resolved.Value)) {
            $itemText = Convert-FastSensitiveResolvedTextForSinkKind -Text ([string]$item) -Context $Context -SinkKind $SinkKind
            if ([string]::IsNullOrWhiteSpace($itemText)) {
                continue
            }
            if ($maxResolvedTextLength -gt 0 -and $itemText.Length -gt $maxResolvedTextLength) {
                continue
            }
            if (Test-SensitiveLiteralizableText -Text $itemText -SinkKind $SinkKind) {
                $items += [string]$itemText
            }
        }
        if ($items.Count -eq 0) {
            return $null
        }
        $displayText = ($items -join ' ')
        $replacementText = '@(' + (($items | ForEach-Object { ConvertTo-SingleQuotedStringLiteral -Text ([string]$_) }) -join ', ') + ')'
    } else {
        $displayText = Convert-FastSensitiveResolvedValueToText -Value $resolved.Value -Context $Context -SinkKind $SinkKind -MaxResolvedTextLength $maxResolvedTextLength
        if ([string]::IsNullOrWhiteSpace($displayText)) {
            return $null
        }
        $replacementText = Format-LiteralizedCommandValue -Value $displayText
    }

    if ([string]::IsNullOrWhiteSpace($displayText)) {
        return $null
    }

    if (-not (Test-SensitiveLiteralizableText -Text $displayText -SinkKind $SinkKind)) {
        return $null
    }

    return [PSCustomObject]@{
        Text              = [string]$displayText
        ReplacementText   = [string]$replacementText
        UsedEmptyFallback = [bool]$resolved.UsedEmptyFallback
    }
}

function Get-StaticSensitiveReplacementTextInfo {
    param(
        $Ast,
        [hashtable]$Context,
        [string]$SinkKind = 'Generic'
    )

    if ($null -eq $Ast) { return $null }

    $resolved = Resolve-StaticAstValue -Ast $Ast -Context $Context -AllowEmptyFallback:$true
    if (-not $resolved.Success) { return $null }

    $replacementText = $null
    $displayText = $null

    if (($resolved.Value -is [System.Collections.IEnumerable]) -and -not ($resolved.Value -is [string]) -and -not ($resolved.Value -is [char[]])) {
        $items = @()
        foreach ($item in @(Convert-StaticValueToStringArray -Value $resolved.Value)) {
            if (Test-SensitiveLiteralizableText -Text ([string]$item) -SinkKind $SinkKind) {
                $items += [string]$item
            }
        }
        if ($items.Count -eq 0) {
            return $null
        }
        $displayText = ($items -join ' ')
        $replacementText = '@(' + (($items | ForEach-Object { ConvertTo-SingleQuotedStringLiteral -Text ([string]$_) }) -join ', ') + ')'
    } else {
        $textInfo = Try-GetStaticStringValueBestEffort -Ast $Ast -Context $Context -AllowEmptyFallback:$true
        if ($null -eq $textInfo -or [string]::IsNullOrWhiteSpace([string]$textInfo.Text)) {
            return $null
        }

        $displayText = [string]$textInfo.Text
        $replacementText = (Format-LiteralizedCommandValue -Value $displayText)
        $resolved | Add-Member -NotePropertyName __PsDissectSensitiveTextInfoUsed -NotePropertyValue $textInfo -Force
    }

    if (-not (Test-SensitiveLiteralizableText -Text $displayText -SinkKind $SinkKind)) {
        return $null
    }

    return [PSCustomObject]@{
        Text              = [string]$displayText
        ReplacementText   = [string]$replacementText
        UsedEmptyFallback = [bool]$resolved.UsedEmptyFallback
    }
}

function Test-CmdlineSensitiveReplacementAstShape {
    param($Ast)

    if ($null -eq $Ast) { return $false }
    if (-not (Test-IsCmdlineOptimizationProfile)) { return $true }

    if ($Ast -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
        return $true
    }

    if ($Ast -is [System.Management.Automation.Language.ConstantExpressionAst]) {
        return (($Ast.Value -is [string]) -or ($Ast.Value -is [char]))
    }

    if ($Ast -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) {
        return (@($Ast.NestedExpressions).Count -eq 0)
    }

    if ($Ast -is [System.Management.Automation.Language.ArrayLiteralAst]) {
        $elements = @($Ast.Elements)
        if ($elements.Count -eq 0) {
            return $false
        }

        foreach ($element in $elements) {
            if (-not (Test-CmdlineSensitiveReplacementAstShape -Ast $element)) {
                return $false
            }
        }

        return $true
    }

    if ($Ast -is [System.Management.Automation.Language.ParenExpressionAst]) {
        $expr = Get-StaticExpressionFromPipelineAst -PipelineAst $Ast.Pipeline
        if ($null -eq $expr) {
            return $false
        }

        return (Test-CmdlineSensitiveReplacementAstShape -Ast $expr)
    }

    if ($Ast -is [System.Management.Automation.Language.ConvertExpressionAst]) {
        $typeName = Get-StaticConvertTypeName -ConvertAst $Ast
        if ([string]::IsNullOrWhiteSpace($typeName) -or $typeName.ToLowerInvariant() -ne 'string') {
            return $false
        }

        return (Test-CmdlineSensitiveReplacementAstShape -Ast $Ast.Child)
    }

    return $false
}

function Test-CanRewriteSensitiveTargetInCmdlineProfile {
    param(
        $Ast,
        $ReplacementInfo
    )

    if (-not (Test-IsCmdlineOptimizationProfile)) { return $true }
    if ($null -eq $Ast -or $null -eq $ReplacementInfo) { return $false }
    if ([bool]$ReplacementInfo.UsedEmptyFallback) { return $false }

    return (Test-CmdlineSensitiveReplacementAstShape -Ast $Ast)
}

function Get-CmdlineSensitiveEvidenceText {
    param(
        $Ast,
        $ReplacementInfo,
        [bool]$CanRewriteTarget = $true
    )

    if ($null -eq $ReplacementInfo) { return $null }

    $text = [string]$ReplacementInfo.Text
    if (-not (Test-IsCmdlineOptimizationProfile)) { return $text }
    if ($CanRewriteTarget -or -not [bool]$ReplacementInfo.UsedEmptyFallback) { return $text }
    if ($null -eq $Ast -or -not $Ast.Extent) { return $text }

    if ($Ast -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
        return [string]$Ast.Value
    }

    if ($Ast -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) {
        $raw = [string]$Ast.Extent.Text
        if ($raw.Length -ge 2) {
            $first = $raw[0]
            $last = $raw[$raw.Length - 1]
            if ((($first -eq "'") -and ($last -eq "'")) -or (($first -eq '"') -and ($last -eq '"'))) {
                $raw = $raw.Substring(1, $raw.Length - 2)
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            return $raw
        }
    }

    return $text
}

function Get-SensitiveCommandArgumentTargets {
    param(
        [Parameter(Mandatory)][System.Management.Automation.Language.CommandAst]$CommandAst,
        [Parameter(Mandatory)][hashtable]$Context
    )

    $entries = @()
    $positionalIndex = 0
    for ($i = 1; $i -lt $CommandAst.CommandElements.Count; $i++) {
        $elem = $CommandAst.CommandElements[$i]
        if ($elem -is [System.Management.Automation.Language.CommandParameterAst]) {
            $argAst = $elem.Argument
            if (-not $argAst -and ($i + 1) -lt $CommandAst.CommandElements.Count -and
                $CommandAst.CommandElements[$i + 1] -isnot [System.Management.Automation.Language.CommandParameterAst]) {
                $i++
                $argAst = $CommandAst.CommandElements[$i]
            }

            $entries += [PSCustomObject]@{
                Kind     = 'Named'
                Name     = [string]$elem.ParameterName
                Position = $null
                Ast      = $argAst
            }
            continue
        }

        $entries += [PSCustomObject]@{
            Kind     = 'Positional'
            Name     = $null
            Position = $positionalIndex
            Ast      = $elem
        }
        $positionalIndex++
    }

    $getNamed = {
        param([string[]]$Names)
        foreach ($entry in @($entries)) {
            if ($entry.Kind -ne 'Named') { continue }
            foreach ($name in @($Names)) {
                if (-not [string]::IsNullOrWhiteSpace($name) -and [string]$entry.Name -and $entry.Name.Equals($name, [System.StringComparison]::OrdinalIgnoreCase)) {
                    return $entry
                }
            }
        }
        return $null
    }
    $getPositional = {
        param([int]$Position)
        foreach ($entry in @($entries)) {
            if ($entry.Kind -eq 'Positional' -and [int]$entry.Position -eq $Position) {
                return $entry
            }
        }
        return $null
    }

    $commandName = Convert-DynamicCommandCandidateToName -Value $CommandAst.GetCommandName()
    $normalizedCommandName = if ($commandName) { $commandName.ToLowerInvariant() } else { '' }

    switch ($normalizedCommandName) {
        { $_ -in @('invoke-webrequest', 'iwr', 'curl', 'wget', 'invoke-restmethod', 'irm') } {
            $target = & $getNamed @('Uri', 'Url')
            if (-not $target) { $target = & $getPositional 0 }
            if ($target -and $target.Ast) {
                return @([PSCustomObject]@{ Ast = $target.Ast; SinkKind = 'Url'; SinkType = 'CommandWebRequest' })
            }
        }
        'start-bitstransfer' {
            $target = & $getNamed @('Source')
            if ($target -and $target.Ast) {
                return @([PSCustomObject]@{ Ast = $target.Ast; SinkKind = 'Url'; SinkType = 'CommandBitsSource' })
            }
        }
        { $_ -in @('start-process', 'start', 'saps') } {
            $filePathTarget = & $getNamed @('FilePath')
            if (-not $filePathTarget) { $filePathTarget = & $getPositional 0 }
            $argListTarget = & $getNamed @('ArgumentList')
            if (-not $argListTarget) { $argListTarget = & $getPositional 1 }
            $workingDirectoryTarget = & $getNamed @('WorkingDirectory')

            $filePathText = if ($filePathTarget -and $filePathTarget.Ast) {
                Try-GetStaticStringValue -Ast $filePathTarget.Ast -Context $Context
            } else {
                $null
            }

            $targets = @()
            if ($filePathTarget -and $filePathTarget.Ast) {
                $targets += [PSCustomObject]@{ Ast = $filePathTarget.Ast; SinkKind = 'FilePath'; SinkType = 'CommandStartProcessFilePath' }
            }
            if ($workingDirectoryTarget -and $workingDirectoryTarget.Ast) {
                $targets += [PSCustomObject]@{ Ast = $workingDirectoryTarget.Ast; SinkKind = 'DirectoryPath'; SinkType = 'CommandStartProcessWorkingDirectory' }
            }
            if ($argListTarget -and $argListTarget.Ast -and
                ($filePathText -match '^(?i)(?:mshta|powershell|pwsh|cmd|wscript|cscript)(?:\.exe)?$')) {
                $targets += [PSCustomObject]@{ Ast = $argListTarget.Ast; SinkKind = 'LauncherArgs'; SinkType = 'CommandStartProcessArgs' }
            }
            if ($targets.Count -gt 0) { return @($targets) }
        }
        'nslookup' {
            $target = & $getPositional 0
            if ($target -and $target.Ast) {
                return @([PSCustomObject]@{ Ast = $target.Ast; SinkKind = 'Host'; SinkType = 'CommandNslookup' })
            }
        }
        { $_ -in @('set-content', 'sc', 'add-content', 'ac', 'out-file', 'copy-item', 'cp', 'cpi', 'move-item', 'mv', 'mi', 'rename-item', 'rni', 'remove-item', 'rm', 'ri', 'del', 'erase', 'test-path', 'get-content', 'gc', 'cat', 'type', 'new-item', 'ni', 'set-item', 'si', 'clear-content', 'clc') } {
            $pathTarget = & $getNamed @('LiteralPath', 'Path', 'Destination', 'Source')
            if (-not $pathTarget) { $pathTarget = & $getPositional 0 }
            if ($pathTarget -and $pathTarget.Ast) {
                return @([PSCustomObject]@{ Ast = $pathTarget.Ast; SinkKind = 'FilePath'; SinkType = 'CommandFilePath' })
            }
        }
        { $_ -in @('set-itemproperty', 'new-itemproperty', 'get-itemproperty', 'remove-itemproperty') } {
            $pathTarget = & $getNamed @('LiteralPath', 'Path', 'LP')
            if (-not $pathTarget) { $pathTarget = & $getPositional 0 }
            $nameTarget = & $getNamed @('Name')
            if (-not $nameTarget) { $nameTarget = & $getPositional 1 }

            $targets = @()
            if ($pathTarget -and $pathTarget.Ast) {
                $targets += [PSCustomObject]@{ Ast = $pathTarget.Ast; SinkKind = 'RegKey'; SinkType = 'CommandRegistryPath' }
            }
            if ($nameTarget -and $nameTarget.Ast) {
                $targets += [PSCustomObject]@{ Ast = $nameTarget.Ast; SinkKind = 'RegValueName'; SinkType = 'CommandRegistryValueName' }
            }
            if ($targets.Count -gt 0) { return @($targets) }
        }
        'invoke-expression' {
            $target = & $getPositional 0
            if ($target -and $target.Ast) {
                return @([PSCustomObject]@{ Ast = $target.Ast; SinkKind = 'CommandText'; SinkType = 'CommandInvokeExpressionText' })
            }
        }
        'iex' {
            $target = & $getPositional 0
            if ($target -and $target.Ast) {
                return @([PSCustomObject]@{ Ast = $target.Ast; SinkKind = 'CommandText'; SinkType = 'CommandInvokeExpressionText' })
            }
        }
        'reg' {
            $first = & $getPositional 0
            $second = & $getPositional 1
            if ($first -and $first.Ast -and $second -and $second.Ast) {
                $verbText = Try-GetStaticStringValue -Ast $first.Ast -Context $Context
                if ($verbText -and $verbText -match '^(?i:add|query|delete)$') {
                    return @([PSCustomObject]@{ Ast = $second.Ast; SinkKind = 'RegKey'; SinkType = 'CommandRegPath' })
                }
            }
        }
        'schtasks' {
            $target = & $getNamed @('TR')
            if ($target -and $target.Ast) {
                return @([PSCustomObject]@{ Ast = $target.Ast; SinkKind = 'LauncherArgs'; SinkType = 'CommandSchTasksTaskRun' })
            }
        }
    }

    return @()
}

function Get-SensitiveMemberInvocationTargets {
    param(
        [Parameter(Mandatory)][System.Management.Automation.Language.InvokeMemberExpressionAst]$InvokeAst,
        [Parameter(Mandatory)][hashtable]$Context
    )

    try {
        $memberName = Get-StaticMemberNameText -MemberAst $InvokeAst.Member -Context $Context
        if ([string]::IsNullOrWhiteSpace($memberName)) {
            $memberName = if ($InvokeAst.Member -and $InvokeAst.Member.Extent) { [string]$InvokeAst.Member.Extent.Text } else { $null }
        }
        if ([string]::IsNullOrWhiteSpace($memberName)) {
            return @()
        }

        $exprText = if ($InvokeAst.Expression -and $InvokeAst.Expression.Extent) { [string]$InvokeAst.Expression.Extent.Text } else { '' }
        $memberNameLower = $memberName.ToLowerInvariant()
        $expressionResult = Resolve-StaticAstValue -Ast $InvokeAst.Expression -Context $Context -AllowEmptyFallback:$true
        $expressionValue = if ($expressionResult.Success) { $expressionResult.Value } else { $null }
        $modeledType = $null
        if (Test-StaticPropertyBagValue -Value $expressionValue) {
            $typeProperty = @($expressionValue.PSObject.Properties.Match('__PsDissectType') | Select-Object -First 1)
            if ($typeProperty.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$typeProperty[0].Value)) {
                $modeledType = ([string]$typeProperty[0].Value).ToLowerInvariant()
            }
        }

        switch ($memberNameLower) {
            'create' {
                if ($exprText -match '(?i)WebRequest|HttpWebRequest' -and $InvokeAst.Arguments.Count -ge 1) {
                    return @([PSCustomObject]@{ Ast = $InvokeAst.Arguments[0]; SinkKind = 'Url'; SinkType = 'MemberWebRequestCreate' })
                }
            }
            { $_ -in @('downloadstring', 'downloaddata', 'downloadfile', 'openread', 'uploadstring', 'uploaddata', 'navigate', 'navigate2') } {
                if ($InvokeAst.Arguments.Count -ge 1) {
                    $sinkType = if ($_ -in @('navigate', 'navigate2')) { 'MemberNavigate' } else { 'MemberDownload' }
                    return @([PSCustomObject]@{ Ast = $InvokeAst.Arguments[0]; SinkKind = 'Url'; SinkType = $sinkType })
                }
            }
            'run' {
                if (($modeledType -eq 'wscript.shell' -or $modeledType -eq 'shell.application') -and $InvokeAst.Arguments.Count -ge 1) {
                    return @([PSCustomObject]@{ Ast = $InvokeAst.Arguments[0]; SinkKind = 'LauncherArgs'; SinkType = 'MemberShellRun' })
                }
            }
            'createshortcut' {
                if ($modeledType -eq 'wscript.shell' -and $InvokeAst.Arguments.Count -ge 1) {
                    return @([PSCustomObject]@{ Ast = $InvokeAst.Arguments[0]; SinkKind = 'FilePath'; SinkType = 'MemberCreateShortcutPath' })
                }
            }
            'addscript' {
                if ($InvokeAst.Arguments.Count -ge 1) {
                    return @([PSCustomObject]@{ Ast = $InvokeAst.Arguments[0]; SinkKind = 'CommandText'; SinkType = 'MemberAddScript' })
                }
            }
            'setvalue' {
                if ($InvokeAst.Arguments.Count -ge 1) {
                    $targets = @([PSCustomObject]@{ Ast = $InvokeAst.Arguments[0]; SinkKind = 'RegValueName'; SinkType = 'MemberRegistrySetValueName' })
                    if ($InvokeAst.Arguments.Count -ge 2) {
                        $targets += [PSCustomObject]@{ Ast = $InvokeAst.Arguments[1]; SinkKind = 'CommandText'; SinkType = 'MemberRegistrySetValueData' }
                    }
                    return @($targets)
                }
            }
        }

        return @()
    } catch {
        return @()
    }
}

function Add-SensitiveEvidenceRecord {
    param(
        [Parameter(Mandatory)][System.Collections.IList]$EvidenceList,
        [string]$Kind,
        [string]$Value,
        [string]$Source,
        [string]$Stage,
        [string]$Confidence = 'High',
        [bool]$PreserveLiteral = $false
    )

    if ([string]::IsNullOrWhiteSpace($Kind) -or [string]::IsNullOrWhiteSpace($Value)) {
        return
    }

    $EvidenceList.Add([PSCustomObject]@{
        Kind       = [string]$Kind
        Value      = [string]$Value
        Source     = [string]$Source
        Stage      = [string]$Stage
        Confidence = [string]$Confidence
        PreserveLiteral = [bool]$PreserveLiteral
    }) | Out-Null
}

function Normalize-WholeScriptLooseFilePathEvidenceText {
    param([AllowNull()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }

    $candidate = ([string]$Text).Trim().Trim('"', "'", ' ', "`t", "`r", "`n")
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        return $null
    }

    $candidate = $candidate.TrimEnd(',', ';')
    $extensionPathPattern = '(?i)\.(?:ps1|psm1|psd1|bat|cmd|vbs|vbe|wsf|wsh|js|jse|hta|exe|dll|lnk|zip|txt|log|dat|tmp|evtx|reg|scr|jar|msi|com)'
    if ($candidate -match ('^(?<path>.+?' + $extensionPathPattern + ')(?:\s+(?:-[A-Za-z_][\w-]*|/[ckCK]\b|\|{1,2}|>{1,2}).*)$')) {
        $candidate = [string]$Matches['path']
    } elseif ($candidate -match '^(?<path>.+?\\\*\.[A-Za-z0-9*?]+)(?:\s+(?:-[A-Za-z_][\w-]*|/[ckCK]\b|\|{1,2}|>{1,2}).*)$') {
        $candidate = [string]$Matches['path']
    }

    return $candidate.Trim().Trim('"', "'", ' ', "`t", "`r", "`n")
}

function Add-WholeScriptSensitivePathEvidenceVariants {
    param(
        [Parameter(Mandatory)][System.Collections.IList]$EvidenceList,
        [string]$Kind,
        [AllowNull()][string]$PathText,
        [string]$Source,
        [string]$Stage,
        [hashtable]$Context = $null,
        [string]$Confidence = 'High'
    )

    $normalizedPath = Normalize-WholeScriptLooseFilePathEvidenceText -Text $PathText
    if ([string]::IsNullOrWhiteSpace($normalizedPath)) {
        return
    }

    $variants = @(Get-WholeScriptStaticArtifactDisplayVariants -PathText $normalizedPath -Context $Context)
    if ($variants.Count -eq 0) {
        $variants = @($normalizedPath)
    }

    foreach ($variant in @($variants)) {
        if ([string]::IsNullOrWhiteSpace([string]$variant)) { continue }
        if (-not (Test-SensitiveLiteralizableText -Text ([string]$variant) -SinkKind $Kind)) { continue }
        Add-SensitiveEvidenceRecord -EvidenceList $EvidenceList -Kind $Kind -Value ([string]$variant) -Source $Source -Stage $Stage -Confidence $Confidence -PreserveLiteral:$true
    }
}

function Test-WholeScriptDictionaryContainsKey {
    param(
        $Dictionary,
        [AllowNull()][string]$Key
    )

    if ($null -eq $Dictionary -or [string]::IsNullOrWhiteSpace($Key)) {
        return $false
    }

    if ($Dictionary -is [System.Collections.IDictionary]) {
        return $Dictionary.Contains($Key)
    }

    if ($Dictionary.PSObject.Methods.Name -contains 'ContainsKey') {
        return $Dictionary.ContainsKey($Key)
    }

    return $false
}

function Get-WholeScriptRegexSensitiveEvidenceFromText {
    param(
        [AllowNull()][string]$Text,
        [string]$Source = 'helper_payload',
        [string]$Stage = 'whole_script_helper',
        [hashtable]$Context = $null
    )

    $candidate = Remove-RecoveredTextTransportArtifacts -Text $Text
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        return @()
    }

    $evidence = New-Object 'System.Collections.Generic.List[object]'
    $patterns = @(
        @{ Kind = 'Url'; Pattern = '(?im)\b(?:https?|ftp)://[^\s''"`<>)]+' },
        @{ Kind = 'RegKey'; Pattern = '(?im)\b(?:(?:registry::)?(?:hkcu|hklm|hkcr|hku|hkcc):\\[^\r\n''"`<>]+|hkey_(?:current_user|local_machine|classes_root|users|current_config)\\[^\r\n''"`<>]+)' },
        @{ Kind = 'FilePath'; Pattern = '(?im)(?:[A-Za-z]:\\|\\\\[^\\]+\\[^\\]+|(?:\.{1,2}\\|%[A-Za-z_][A-Za-z0-9_]*%\\|\$env:[A-Za-z_][A-Za-z0-9_]*\\|~\\))[^\r\n''"`<>|]*' }
    )

    foreach ($entry in $patterns) {
        foreach ($match in @([regex]::Matches($candidate, $entry.Pattern))) {
            $value = Remove-RecoveredTextTransportArtifacts -Text ([string]$match.Value)
            if ([string]$entry.Kind -eq 'FilePath') {
                Add-WholeScriptSensitivePathEvidenceVariants -EvidenceList $evidence -Kind 'FilePath' -PathText $value -Source $Source -Stage $Stage -Context $Context
                continue
            }

            if (-not [string]::IsNullOrWhiteSpace($value) -and
                (Test-SensitiveLiteralizableText -Text $value -SinkKind ([string]$entry.Kind))) {
                Add-SensitiveEvidenceRecord -EvidenceList $evidence -Kind ([string]$entry.Kind) -Value $value -Source $Source -Stage $Stage
            }
        }
    }

    return @($evidence.ToArray())
}

function Expand-SimpleBatchArtifactVariableText {
    param(
        [AllowNull()][string]$Text,
        [System.Collections.IDictionary]$Variables = $null,
        [hashtable]$Context = $null
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $Text
    }

    $resolved = [string]$Text
    for ($pass = 0; $pass -lt 4; $pass++) {
        $before = $resolved
        $resolved = [regex]::Replace($resolved, '(?i)%([A-Za-z_][A-Za-z0-9_]*)%', {
                param($m)
                $name = [string]$m.Groups[1].Value
                if (Test-WholeScriptDictionaryContainsKey -Dictionary $Variables -Key $name) {
                    return [string]$Variables[$name]
                }

                $envValue = Resolve-WholeScriptStaticEnvironmentValueText -Name $name -Context $Context
                if (-not [string]::IsNullOrWhiteSpace($envValue)) {
                    return [string]$envValue
                }

                return [string]$m.Value
            })
        if ($resolved -eq $before) {
            break
        }
    }

    return $resolved
}

function Get-SimpleBatchArtifactSensitiveEvidenceFromText {
    param(
        [AllowNull()][string]$Text,
        [string]$Source = 'artifact_batch',
        [string]$Stage = 'whole_script_artifact_batch',
        [hashtable]$Context = $null
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return @()
    }

    $evidence = New-Object 'System.Collections.Generic.List[object]'
    $variables = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $lines = [regex]::Split([string]$Text, "`r?`n")
    foreach ($line in $lines) {
        $trimmed = ([string]$line).Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
        if ($trimmed -match '^(?i)(?:rem\b|::)') { continue }

        if ($trimmed -match '^(?i)@?\s*set\s+"?(?<name>[A-Za-z_][A-Za-z0-9_]*)=(?<value>.*)"?\s*$') {
            $varName = [string]$Matches['name']
            $varValue = Expand-SimpleBatchArtifactVariableText -Text ([string]$Matches['value']) -Variables $variables -Context $Context
            if (-not [string]::IsNullOrWhiteSpace($varName)) {
                $variables[$varName] = [string]$varValue
            }
            foreach ($entry in @(Get-WholeScriptRegexSensitiveEvidenceFromText -Text $varValue -Source ($Source + ':set') -Stage $Stage -Context $Context)) {
                if ($null -eq $entry) { continue }
                $evidence.Add($entry) | Out-Null
            }
            continue
        }

        $resolvedLine = Expand-SimpleBatchArtifactVariableText -Text $trimmed -Variables $variables -Context $Context
        foreach ($entry in @(Get-WholeScriptRegexSensitiveEvidenceFromText -Text $resolvedLine -Source ($Source + ':line') -Stage $Stage -Context $Context)) {
            if ($null -eq $entry) { continue }
            $evidence.Add($entry) | Out-Null
        }
    }

    return @($evidence.ToArray())
}

function Resolve-SimpleVbsStringExpression {
    param(
        [AllowNull()][string]$Expression,
        [System.Collections.IDictionary]$Variables = $null
    )

    if ([string]::IsNullOrWhiteSpace($Expression)) {
        return $null
    }

    $expr = ([string]$Expression).Trim()
    if ([string]::IsNullOrWhiteSpace($expr)) {
        return $null
    }

    if ($expr -match '^"(?:[^"]|"")*"$') {
        return (($expr.Substring(1, $expr.Length - 2)) -replace '""', '"')
    }

    if ($expr -match '^(?i:[A-Za-z_][A-Za-z0-9_]*)$') {
        if (Test-WholeScriptDictionaryContainsKey -Dictionary $Variables -Key ([string]$expr)) {
            return [string]$Variables[[string]$expr]
        }
        return $null
    }

    $allowedRemainder = [regex]::Replace($expr, '"(?:[^"]|"")*"|[A-Za-z_][A-Za-z0-9_]*|\s+|[+&()]', '')
    if (-not [string]::IsNullOrWhiteSpace($allowedRemainder)) {
        return $null
    }

    $parts = New-Object 'System.Collections.Generic.List[string]'
    foreach ($token in @([regex]::Matches($expr, '"(?:[^"]|"")*"|[A-Za-z_][A-Za-z0-9_]*'))) {
        $tokenText = [string]$token.Value
        if ($tokenText -match '^"(?:[^"]|"")*"$') {
            $parts.Add(($tokenText.Substring(1, $tokenText.Length - 2) -replace '""', '"')) | Out-Null
            continue
        }

        if (Test-WholeScriptDictionaryContainsKey -Dictionary $Variables -Key $tokenText) {
            $parts.Add([string]$Variables[$tokenText]) | Out-Null
            continue
        }

        return $null
    }

    if ($parts.Count -eq 0) {
        return $null
    }

    return ($parts.ToArray() -join '')
}

function Get-SimpleVbsArtifactSensitiveEvidenceFromText {
    param(
        [AllowNull()][string]$Text,
        [string]$Source = 'artifact_vbs',
        [string]$Stage = 'whole_script_artifact_vbs',
        [hashtable]$Context = $null
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return @()
    }

    $evidence = New-Object 'System.Collections.Generic.List[object]'
    $variables = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $lines = [regex]::Split([string]$Text, "`r?`n")

    for ($pass = 0; $pass -lt 4; $pass++) {
        $changed = $false
        foreach ($line in $lines) {
            $trimmed = ([string]$line).Trim()
            if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
            if ($trimmed -match "^(?i:'|rem\b)") { continue }

            if ($trimmed -match '^(?i)(?:set\s+)?(?<name>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*(?<expr>.+?)\s*$') {
                $varName = [string]$Matches['name']
                $resolvedValue = Resolve-SimpleVbsStringExpression -Expression ([string]$Matches['expr']) -Variables $variables
                if ([string]::IsNullOrWhiteSpace($resolvedValue)) { continue }
                if ((-not (Test-WholeScriptDictionaryContainsKey -Dictionary $variables -Key $varName)) -or ($variables[$varName] -ne $resolvedValue)) {
                    $variables[$varName] = $resolvedValue
                    $changed = $true
                }
            }
        }
        if (-not $changed) { break }
    }

    foreach ($pair in $variables.GetEnumerator()) {
        foreach ($entry in @(Get-WholeScriptRegexSensitiveEvidenceFromText -Text ([string]$pair.Value) -Source ($Source + ':var:' + [string]$pair.Key) -Stage $Stage -Context $Context)) {
            if ($null -eq $entry) { continue }
            $evidence.Add($entry) | Out-Null
        }
    }

    return @($evidence.ToArray())
}

function Get-WholeScriptStaticArtifactContentProfile {
    param($Record)

    if ($null -eq $Record) {
        return 'text'
    }

    $path = if ($Record.PSObject.Properties['DisplayPath']) { [string]$Record.DisplayPath } else { '' }
    if ($path -match '(?i)\.(ps1|psm1|psd1)$') { return 'powershell' }
    if ($path -match '(?i)\.(bat|cmd)$') { return 'batch' }
    if ($path -match '(?i)\.(vbs|vbe|wsf|wsh)$') { return 'vbs' }
    if ($Record.PSObject.Properties['IsPowerShell'] -and [bool]$Record.IsPowerShell) { return 'powershell' }
    return 'text'
}

function Update-WholeScriptStaticArtifactDerivedEvidence {
    param(
        [Parameter(Mandatory)]$Record,
        [hashtable]$Context = $null
    )

    if ($null -eq $Record) {
        return @()
    }

    $contentText = if ($Record.PSObject.Properties['ContentText']) { [string]$Record.ContentText } else { '' }
    if ([string]::IsNullOrWhiteSpace($contentText)) {
        $Record.DerivedEvidence = @()
        return @()
    }

    $evidence = New-Object 'System.Collections.Generic.List[object]'
    foreach ($entry in @(Get-WholeScriptRegexSensitiveEvidenceFromText -Text $contentText -Source 'ArtifactContent' -Stage 'whole_script_artifact_content' -Context $Context)) {
        if ($null -eq $entry) { continue }
        $evidence.Add($entry) | Out-Null
    }

    switch (Get-WholeScriptStaticArtifactContentProfile -Record $Record) {
        'batch' {
            foreach ($entry in @(Get-SimpleBatchArtifactSensitiveEvidenceFromText -Text $contentText -Source 'ArtifactContentBatch' -Stage 'whole_script_artifact_batch' -Context $Context)) {
                if ($null -eq $entry) { continue }
                $evidence.Add($entry) | Out-Null
            }
        }
        'vbs' {
            foreach ($entry in @(Get-SimpleVbsArtifactSensitiveEvidenceFromText -Text $contentText -Source 'ArtifactContentVbs' -Stage 'whole_script_artifact_vbs' -Context $Context)) {
                if ($null -eq $entry) { continue }
                $evidence.Add($entry) | Out-Null
            }
        }
    }

    $Record.DerivedEvidence = @(Get-UniqueSensitiveEvidenceRecords -Evidence ($evidence.ToArray()))
    return @($Record.DerivedEvidence)
}

function Convert-SensitiveEvidenceValueToCanonical {
    param(
        [string]$Kind,
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $normalized = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return $null
    }

    switch ($Kind) {
        { $_ -in @('FilePath', 'DirectoryPath', 'RegKey') } {
            $pathInfo = Get-WholeScriptStaticArtifactPathInfo -PathText $normalized
            if ($pathInfo) { return [string]$pathInfo.DisplayPath }
            return ($normalized -replace '/', '\')
        }
        'Url' {
            return $normalized.Trim('"', "'", ' ')
        }
        default {
            return $normalized
        }
    }
}

function Get-UniqueSensitiveEvidenceRecords {
    param([object[]]$Evidence = @())

    $result = @()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in @($Evidence)) {
        if ($null -eq $entry) { continue }
        $kind = if ($entry.PSObject.Properties['Kind']) { [string]$entry.Kind } else { '' }
        $value = if ($entry.PSObject.Properties['Value']) { [string]$entry.Value } else { '' }
        $preserveLiteral = if ($entry.PSObject.Properties['PreserveLiteral']) { [bool]$entry.PreserveLiteral } else { $false }
        $canonical = if ($preserveLiteral) {
            ([string]$value).Trim()
        } else {
            Convert-SensitiveEvidenceValueToCanonical -Kind $kind -Value $value
        }
        if ([string]::IsNullOrWhiteSpace($kind) -or [string]::IsNullOrWhiteSpace($canonical)) {
            continue
        }
        $key = '{0}|{1}' -f $kind.ToLowerInvariant(), $canonical.ToLowerInvariant()
        if (-not $seen.Add($key)) {
            continue
        }

        $copy = [PSCustomObject]@{
            Kind       = $kind
            Value      = $canonical
            Source     = if ($entry.PSObject.Properties['Source']) { [string]$entry.Source } else { '' }
            Stage      = if ($entry.PSObject.Properties['Stage']) { [string]$entry.Stage } else { '' }
            Confidence = if ($entry.PSObject.Properties['Confidence']) { [string]$entry.Confidence } else { 'High' }
            PreserveLiteral = $preserveLiteral
        }
        $result += $copy
    }

    return @($result)
}

function Add-SensitiveArtifactEvidenceFromContext {
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][System.Collections.IList]$EvidenceList
    )

    $store = Get-WholeScriptStaticArtifactStore -Context $Context
    foreach ($fileKey in @($store.Files.Keys)) {
        $record = $store.Files[$fileKey]
        if ($null -eq $record) { continue }
        foreach ($variant in @($record.DisplayVariants)) {
            Add-WholeScriptSensitivePathEvidenceVariants -EvidenceList $EvidenceList -Kind 'FilePath' -PathText ([string]$variant) -Source 'ArtifactStore' -Stage 'whole_script_static' -Context $Context
        }
        if ((@($record.DisplayVariants).Count -eq 0) -and -not [string]::IsNullOrWhiteSpace([string]$record.DisplayPath)) {
            Add-WholeScriptSensitivePathEvidenceVariants -EvidenceList $EvidenceList -Kind 'FilePath' -PathText ([string]$record.DisplayPath) -Source 'ArtifactStore' -Stage 'whole_script_static' -Context $Context
        }
        foreach ($refPath in @($record.ReferencedPaths)) {
            Add-WholeScriptSensitivePathEvidenceVariants -EvidenceList $EvidenceList -Kind 'FilePath' -PathText ([string]$refPath) -Source 'ArtifactReference' -Stage 'whole_script_static' -Context $Context
        }
        if ($record.Properties -is [System.Collections.IDictionary]) {
            foreach ($propName in @($record.Properties.Keys)) {
                $propValue = $record.Properties[$propName]
                if (-not [string]::IsNullOrWhiteSpace([string]$propValue) -and (Test-SensitiveLiteralizableText -Text ([string]$propValue) -SinkKind 'FilePath')) {
                    Add-WholeScriptSensitivePathEvidenceVariants -EvidenceList $EvidenceList -Kind 'FilePath' -PathText ([string]$propValue) -Source ('ArtifactProperty:' + [string]$propName) -Stage 'whole_script_static' -Context $Context
                }
            }
        }
        foreach ($derivedEntry in @(Update-WholeScriptStaticArtifactDerivedEvidence -Record $record -Context $Context)) {
            if ($null -eq $derivedEntry) { continue }
            Add-SensitiveEvidenceRecord -EvidenceList $EvidenceList `
                -Kind ([string]$derivedEntry.Kind) `
                -Value ([string]$derivedEntry.Value) `
                -Source $(if ($derivedEntry.PSObject.Properties['Source']) { [string]$derivedEntry.Source } else { 'ArtifactDerived' }) `
                -Stage $(if ($derivedEntry.PSObject.Properties['Stage']) { [string]$derivedEntry.Stage } else { 'whole_script_static' }) `
                -Confidence $(if ($derivedEntry.PSObject.Properties['Confidence']) { [string]$derivedEntry.Confidence } else { 'High' }) `
                -PreserveLiteral $(if ($derivedEntry.PSObject.Properties['PreserveLiteral']) { [bool]$derivedEntry.PreserveLiteral } else { $false })
        }
    }

    foreach ($regKey in @($store.Registry.Keys)) {
        $record = $store.Registry[$regKey]
        if ($null -eq $record) { continue }
        if (-not [string]::IsNullOrWhiteSpace([string]$record.DisplayPath)) {
            Add-SensitiveEvidenceRecord -EvidenceList $EvidenceList -Kind 'RegKey' -Value ([string]$record.DisplayPath) -Source 'ArtifactStore' -Stage 'whole_script_static'
        }
        if ($record.Values -is [System.Collections.IDictionary]) {
            foreach ($valueName in @($record.Values.Keys)) {
                Add-SensitiveEvidenceRecord -EvidenceList $EvidenceList -Kind 'RegValueName' -Value ([string]$valueName) -Source 'ArtifactStore' -Stage 'whole_script_static'
                $valueText = $record.Values[$valueName]
                if (-not [string]::IsNullOrWhiteSpace([string]$valueText)) {
                    if (Test-SensitiveLiteralizableText -Text ([string]$valueText) -SinkKind 'FilePath') {
                        Add-WholeScriptSensitivePathEvidenceVariants -EvidenceList $EvidenceList -Kind 'FilePath' -PathText ([string]$valueText) -Source ('RegistryValue:' + [string]$valueName) -Stage 'whole_script_static' -Context $Context
                    }
                    if (Test-SensitiveLiteralizableText -Text ([string]$valueText) -SinkKind 'CommandText') {
                        Add-SensitiveEvidenceRecord -EvidenceList $EvidenceList -Kind 'CommandText' -Value ([string]$valueText) -Source ('RegistryValue:' + [string]$valueName) -Stage 'whole_script_static'
                    }
                }
            }
        }
    }

    foreach ($evt in @($Context.ArtifactEvents)) {
        if ($null -eq $evt -or [string]::IsNullOrWhiteSpace([string]$evt.Path)) { continue }
        $kind = if ([string]$evt.Kind -eq 'Registry') { 'RegKey' } else { 'FilePath' }
        if ($kind -eq 'FilePath') {
            Add-WholeScriptSensitivePathEvidenceVariants -EvidenceList $EvidenceList -Kind 'FilePath' -PathText ([string]$evt.Path) -Source ('ArtifactEvent:' + [string]$evt.Action) -Stage 'whole_script_static' -Context $Context
        } else {
            Add-SensitiveEvidenceRecord -EvidenceList $EvidenceList -Kind $kind -Value ([string]$evt.Path) -Source ('ArtifactEvent:' + [string]$evt.Action) -Stage 'whole_script_static'
        }
    }
}

function Add-SensitivePropertyBagEvidenceFromParse {
    param(
        [Parameter(Mandatory)]$ParseAst,
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][System.Collections.IList]$EvidenceList
    )

    $assignmentAsts = @($ParseAst.FindAll({
                param($n)
                $n -is [System.Management.Automation.Language.AssignmentStatementAst]
            }, $true))

    foreach ($assignment in $assignmentAsts) {
        if ($assignment.Left -isnot [System.Management.Automation.Language.MemberExpressionAst]) { continue }
        if ($assignment.Left.Static) { continue }

        $targetResult = Resolve-StaticAstValue -Ast $assignment.Left.Expression -Context $Context -AllowEmptyFallback:$true
        if (-not $targetResult.Success -or -not (Test-StaticPropertyBagValue -Value $targetResult.Value)) { continue }

        $typeProperty = @($targetResult.Value.PSObject.Properties.Match('__PsDissectType') | Select-Object -First 1)
        $modeledType = if ($typeProperty.Count -gt 0) { [string]$typeProperty[0].Value } else { '' }
        if ([string]::IsNullOrWhiteSpace($modeledType)) { continue }

        $memberName = Get-StaticMemberNameText -MemberAst $assignment.Left.Member -Context $Context
        if ([string]::IsNullOrWhiteSpace($memberName)) { continue }

        $rhsResult = Resolve-StaticAstValue -Ast $assignment.Right -Context $Context -AllowEmptyFallback:$true
        if (-not $rhsResult.Success) { continue }

        $kind = $null
        switch -Regex ($modeledType.ToLowerInvariant()) {
            '^processstartinfo$' {
                switch -Regex ($memberName.ToLowerInvariant()) {
                    '^filename$' { $kind = 'FilePath'; break }
                    '^arguments$' { $kind = 'LauncherArgs'; break }
                    '^workingdirectory$' { $kind = 'DirectoryPath'; break }
                }
                break
            }
            '^wscript\.shell\.shortcut$' {
                switch -Regex ($memberName.ToLowerInvariant()) {
                    '^(?:fullname|targetpath|iconlocation)$' { $kind = 'FilePath'; break }
                    '^arguments$' { $kind = 'LauncherArgs'; break }
                    '^workingdirectory$' { $kind = 'DirectoryPath'; break }
                }
                break
            }
            '^webclient$' {
                if ($memberName -match '^(?i:BaseAddress)$') { $kind = 'Url' }
                break
            }
        }

        if ([string]::IsNullOrWhiteSpace($kind)) { continue }

        if (($rhsResult.Value -is [System.Collections.IEnumerable]) -and -not ($rhsResult.Value -is [string]) -and -not ($rhsResult.Value -is [char[]])) {
            foreach ($item in @(Convert-StaticValueToStringArray -Value $rhsResult.Value)) {
                if (Test-SensitiveLiteralizableText -Text ([string]$item) -SinkKind $kind) {
                    if ($kind -in @('FilePath', 'DirectoryPath')) {
                        Add-WholeScriptSensitivePathEvidenceVariants -EvidenceList $EvidenceList -Kind $kind -PathText ([string]$item) -Source ($modeledType + '.' + $memberName) -Stage 'property_bag' -Context $Context
                    } else {
                        Add-SensitiveEvidenceRecord -EvidenceList $EvidenceList -Kind $kind -Value ([string]$item) -Source ($modeledType + '.' + $memberName) -Stage 'property_bag'
                    }
                }
            }
            continue
        }

        $text = Convert-StaticValueToMeaningfulString -Value $rhsResult.Value
        if (-not [string]::IsNullOrWhiteSpace($text) -and (Test-SensitiveLiteralizableText -Text $text -SinkKind $kind)) {
            if ($kind -in @('FilePath', 'DirectoryPath')) {
                Add-WholeScriptSensitivePathEvidenceVariants -EvidenceList $EvidenceList -Kind $kind -PathText $text -Source ($modeledType + '.' + $memberName) -Stage 'property_bag' -Context $Context
            } else {
                Add-SensitiveEvidenceRecord -EvidenceList $EvidenceList -Kind $kind -Value $text -Source ($modeledType + '.' + $memberName) -Stage 'property_bag'
            }
        }
    }
}

function Test-WholeScriptSensitiveEvidenceHarvestTriggerText {
    param([AllowNull()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $false
    }

    return ([string]$Text -match '(?i)(?:[A-Za-z]:\\|\\\\[^\\]+\\[^\\]+|%[A-Za-z_][A-Za-z0-9_]*%\\|\$env:[A-Za-z_][A-Za-z0-9_]*\\|https?://|(?:registry::)?(?:hkcu|hklm|hkcr|hku|hkcc):\\|hkey_(?:current_user|local_machine|classes_root|users|current_config)\\|createshortcut|specialfolders|set-content|add-content|out-file|new-item|copy-item|move-item|rename-item|start-process)')
}

function Invoke-AppendWholeScriptHarvestedSensitiveEvidenceCommentBlock {
    param(
        [Parameter(Mandatory)][string]$ScriptText,
        [string]$Source = 'postprocess_harvest',
        [string]$Stage = 'postprocess_harvest'
    )

    if ([string]::IsNullOrWhiteSpace($ScriptText)) {
        return $ScriptText
    }

    if (-not (Test-WholeScriptSensitiveEvidenceHarvestTriggerText -Text $ScriptText)) {
        return $ScriptText
    }

    $evidence = @(Get-WholeScriptSensitiveEvidenceFromText -Text $ScriptText -Source $Source -Stage $Stage)
    if ($evidence.Count -eq 0) {
        return $ScriptText
    }

    return (Append-SensitiveEvidenceCommentBlock -ScriptText $ScriptText -Evidence $evidence)
}

function Get-SensitiveEvidenceCommentBlock {
    param([object[]]$Evidence = @())

    $unique = @(Get-UniqueSensitiveEvidenceRecords -Evidence $Evidence)
    if ($unique.Count -eq 0) {
        return $null
    }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('<# PSDissect-SensitiveEvidence') | Out-Null
    foreach ($entry in @($unique | Sort-Object Kind, Value)) {
        $lines.Add(('{0}: {1}' -f [string]$entry.Kind, [string]$entry.Value)) | Out-Null
    }
    $lines.Add('#>') | Out-Null
    return (($lines.ToArray()) -join "`r`n")
}

function Append-SensitiveEvidenceCommentBlock {
    param(
        [Parameter(Mandatory)][string]$ScriptText,
        [object[]]$Evidence = @()
    )

    return $ScriptText

    $commentBlock = Get-SensitiveEvidenceCommentBlock -Evidence $Evidence
    if ([string]::IsNullOrWhiteSpace($commentBlock)) {
        return $ScriptText
    }

    if ($ScriptText -match '(?s)<#\s*PSDissect-SensitiveEvidence.*?#>\s*$') {
        return [regex]::Replace($ScriptText, '(?s)<#\s*PSDissect-SensitiveEvidence.*?#>\s*$', $commentBlock + "`r`n")
    }

    return ($ScriptText.TrimEnd() + "`r`n`r`n" + $commentBlock + "`r`n")
}

function Remove-SensitiveEvidenceCommentBlock {
    param([AllowNull()][string]$ScriptText)

    if ($null -eq $ScriptText) { return $ScriptText }
    return [regex]::Replace([string]$ScriptText, '(?s)\s*<#\s*PSDissect-SensitiveEvidence.*?#>\s*$', "`r`n")
}

function Remove-StandaloneCmdlineNoiseLines {
    param([Parameter(Mandatory)][string]$ScriptText)

    if (-not (Test-IsCmdlineOptimizationProfile)) {
        return $ScriptText
    }

    if ([string]::IsNullOrWhiteSpace($ScriptText)) {
        return $ScriptText
    }

    $lines = [regex]::Split($ScriptText, "`r?`n")
    $kept = New-Object System.Collections.Generic.List[string]

    foreach ($line in $lines) {
        $trim = $line.Trim()

        if ([string]::IsNullOrWhiteSpace($trim)) {
            $kept.Add($line) | Out-Null
            continue
        }

        if ($trim -match '^(?:;+\s*)+$') {
            continue
        }

        if ($trim -match '^(?:;?\s*(?:\(\[string\]\)\s*)?(?:''(?:[^'']|'''')*''|"(?:[^"]|"")*"))+\s*;?$') {
            continue
        }

        $kept.Add($line) | Out-Null
    }

    $candidate = ($kept.ToArray() -join "`r`n").Trim()
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        return $ScriptText
    }

    $check = Test-PowerShellSyntax -ScriptText $candidate
    if ($check.IsValid) {
        return ($candidate.TrimEnd() + "`r`n")
    }

    return $ScriptText
}

function Invoke-NormalizeSensitiveIndicatorArgumentsFast {
    param([Parameter(Mandatory)][string]$ScriptText)

    $config = Get-FastSensitivePassConfig
    if (-not $config.Enabled -or [string]::IsNullOrWhiteSpace($ScriptText)) {
        return $ScriptText
    }

    $parse = Get-ScriptParseInfo -ScriptText $ScriptText
    if (-not $parse.IsValid -or -not $parse.Ast) {
        return $ScriptText
    }

    $ctx = New-WholeScriptStaticResolutionContext
    try {
        $state = Get-StaticEvalState -Context $ctx
        if ($state) {
            $state.ValueDepthLimit = 32
            $state.StringCompatDepthLimit = 24
        }
        $null = Reset-StaticEvalState -Context $ctx -TimeBudgetMs ([int]$config.StaticBudgetMs)

        $topLevelStatements = @(Get-TopLevelScriptStatementsFromText -ScriptText $ScriptText)
        if ($topLevelStatements.Count -gt 0) {
            [void](Initialize-WholeScriptStaticAssignments -Statements $topLevelStatements -Context $ctx)
        }

        $state = Get-StaticEvalState -Context $ctx
        if ($state) {
            $state.ValueDepthLimit = 32
            $state.StringCompatDepthLimit = 24
        }
        $null = Reset-StaticEvalState -Context $ctx -TimeBudgetMs ([int]$config.StaticBudgetMs)

        $targets = New-Object 'System.Collections.Generic.List[object]'
        foreach ($cmdAst in @($parse.Ast.FindAll({
                        param($n)
                        $n -is [System.Management.Automation.Language.CommandAst]
                    }, $true))) {
            foreach ($target in @(Get-SensitiveCommandArgumentTargets -CommandAst $cmdAst -Context $ctx)) {
                if ($targets.Count -ge [int]$config.MaxTargets) { break }
                $targets.Add($target) | Out-Null
            }
            if ($targets.Count -ge [int]$config.MaxTargets) { break }
        }

        if ($targets.Count -lt [int]$config.MaxTargets) {
            foreach ($invokeAst in @($parse.Ast.FindAll({
                            param($n)
                            $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst]
                        }, $true))) {
                foreach ($target in @(Get-SensitiveMemberInvocationTargets -InvokeAst $invokeAst -Context $ctx)) {
                    if ($targets.Count -ge [int]$config.MaxTargets) { break }
                    $targets.Add($target) | Out-Null
                }
                if ($targets.Count -ge [int]$config.MaxTargets) { break }
            }
        }

        $replacements = @()
        $seenRanges = @{}
        $sensitiveEvidence = New-Object 'System.Collections.Generic.List[object]'

        foreach ($target in @($targets.ToArray())) {
            if (Test-StaticEvalBudgetExceeded -Context $ctx) {
                break
            }

            $targetAst = $target.Ast
            if ($null -eq $targetAst -or -not $targetAst.Extent) {
                continue
            }

            $replacementInfo = Get-FastSensitiveReplacementTextInfo -Ast $targetAst -Context $ctx -SinkKind ([string]$target.SinkKind) -Config $config
            if ($null -eq $replacementInfo) {
                continue
            }

            $canRewriteTarget = ((Test-CmdlineSensitiveReplacementAstShape -Ast $targetAst) -and -not [bool]$replacementInfo.UsedEmptyFallback)
            $evidenceText = Get-CmdlineSensitiveEvidenceText -Ast $targetAst -ReplacementInfo $replacementInfo -CanRewriteTarget $canRewriteTarget
            if ([string]::IsNullOrWhiteSpace($evidenceText)) {
                $evidenceText = [string]$replacementInfo.Text
            }

            Add-SensitiveEvidenceRecord -EvidenceList $sensitiveEvidence -Kind ([string]$target.SinkKind) -Value ([string]$evidenceText) -Source ([string]$target.SinkType) -Stage $(if ($canRewriteTarget) { 'fast_ast_replacement' } else { 'fast_ast_preserved' })

            if (-not $canRewriteTarget) {
                continue
            }

            $start = [int]$targetAst.Extent.StartOffset
            $end = [int]$targetAst.Extent.EndOffset
            $rangeKey = '{0}:{1}' -f $start, $end
            if ($seenRanges.ContainsKey($rangeKey)) {
                continue
            }

            $original = $ScriptText.Substring($start, $end - $start)
            if ([string]::Equals($original, [string]$replacementInfo.ReplacementText, [System.StringComparison]::Ordinal)) {
                continue
            }

            $seenRanges[$rangeKey] = $true
            $replacements += [PSCustomObject]@{
                Start = $start
                End   = $end
                Text  = [string]$replacementInfo.ReplacementText
            }
        }

        Add-SensitiveArtifactEvidenceFromContext -Context $ctx -EvidenceList $sensitiveEvidence

        if ($replacements.Count -eq 0) {
            return (Append-SensitiveEvidenceCommentBlock -ScriptText $ScriptText -Evidence ($sensitiveEvidence.ToArray()))
        }

        $result = $ScriptText
        foreach ($r in @($replacements | Sort-Object Start -Descending)) {
            $result = $result.Substring(0, $r.Start) + $r.Text + $result.Substring($r.End)
        }

        $check = Test-PowerShellSyntax -ScriptText $result
        if ($check.IsValid) {
            return (Append-SensitiveEvidenceCommentBlock -ScriptText $result -Evidence ($sensitiveEvidence.ToArray()))
        }

        return (Append-SensitiveEvidenceCommentBlock -ScriptText $ScriptText -Evidence ($sensitiveEvidence.ToArray()))
    } catch {
        return $ScriptText
    } finally {
        Close-WholeScriptStaticResolutionContext -Context $ctx
    }
}

function Invoke-NormalizeSensitiveIndicatorArguments {
    param([Parameter(Mandatory)][string]$ScriptText)

    if ([string]::IsNullOrWhiteSpace($ScriptText)) {
        return $ScriptText
    }

    $parse = Get-ScriptParseInfo -ScriptText $ScriptText
    if (-not $parse.IsValid -or -not $parse.Ast) {
        return $ScriptText
    }

    $ctx = New-WholeScriptStaticResolutionContext
    try {
        $topLevelStatements = @(Get-TopLevelScriptStatementsFromText -ScriptText $ScriptText)
        if ($topLevelStatements.Count -gt 0) {
            [void](Initialize-WholeScriptStaticAssignments -Statements $topLevelStatements -Context $ctx)
        }

        $replacements = @()
        $seenRanges = @{}
        $sensitiveEvidence = New-Object 'System.Collections.Generic.List[object]'

        $addReplacement = {
            param($TargetAst, [string]$SinkKind, [string]$SinkType)
            if ($null -eq $TargetAst -or -not $TargetAst.Extent) { return }

            $replacementInfo = Get-StaticSensitiveReplacementTextInfo -Ast $TargetAst -Context $ctx -SinkKind $SinkKind
            if ($null -eq $replacementInfo) { return }

            $canRewriteTarget = Test-CanRewriteSensitiveTargetInCmdlineProfile -Ast $TargetAst -ReplacementInfo $replacementInfo
            $evidenceText = Get-CmdlineSensitiveEvidenceText -Ast $TargetAst -ReplacementInfo $replacementInfo -CanRewriteTarget $canRewriteTarget
            if ([string]::IsNullOrWhiteSpace($evidenceText)) {
                $evidenceText = [string]$replacementInfo.Text
            }
            $evidenceStage = if ($canRewriteTarget) { 'ast_replacement' } else { 'ast_preserved' }
            Add-SensitiveEvidenceRecord -EvidenceList $sensitiveEvidence -Kind $SinkKind -Value ([string]$evidenceText) -Source $SinkType -Stage $evidenceStage

            if (-not $canRewriteTarget) {
                return
            }

            $start = [int]$TargetAst.Extent.StartOffset
            $end = [int]$TargetAst.Extent.EndOffset
            $rangeKey = '{0}:{1}' -f $start, $end
            if ($seenRanges.ContainsKey($rangeKey)) { return }

            $original = $ScriptText.Substring($start, $end - $start)
            if ([string]::Equals($original, [string]$replacementInfo.ReplacementText, [System.StringComparison]::Ordinal)) {
                return
            }

            $seenRanges[$rangeKey] = $true
            $script:__psdissect_sensitive_replacements += [PSCustomObject]@{
                Start = $start
                End   = $end
                Text  = [string]$replacementInfo.ReplacementText
                Type  = $SinkType
            }
        }

        $script:__psdissect_sensitive_replacements = @()

        $commandAsts = @($parse.Ast.FindAll({
                param($n)
                $n -is [System.Management.Automation.Language.CommandAst]
            }, $true))
        foreach ($cmdAst in $commandAsts) {
            $targets = @()
            try {
                $targets = @(Get-SensitiveCommandArgumentTargets -CommandAst $cmdAst -Context $ctx)
            } catch {
                $targets = @()
            }

            foreach ($target in $targets) {
                try {
                    & $addReplacement $target.Ast $target.SinkKind $target.SinkType
                } catch {
                }
            }
        }

        $invokeAsts = @($parse.Ast.FindAll({
                param($n)
                $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst]
            }, $true))
        foreach ($invokeAst in $invokeAsts) {
            $targets = @()
            try {
                $targets = @(Get-SensitiveMemberInvocationTargets -InvokeAst $invokeAst -Context $ctx)
            } catch {
                $targets = @()
            }

            foreach ($target in $targets) {
                try {
                    & $addReplacement $target.Ast $target.SinkKind $target.SinkType
                } catch {
                }
            }
        }

        Add-SensitiveArtifactEvidenceFromContext -Context $ctx -EvidenceList $sensitiveEvidence
        Add-SensitivePropertyBagEvidenceFromParse -ParseAst $parse.Ast -Context $ctx -EvidenceList $sensitiveEvidence

        $replacements = @($script:__psdissect_sensitive_replacements)
        Remove-Variable -Name __psdissect_sensitive_replacements -Scope Script -ErrorAction SilentlyContinue

        if ($replacements.Count -eq 0) {
            return (Append-SensitiveEvidenceCommentBlock -ScriptText $ScriptText -Evidence ($sensitiveEvidence.ToArray()))
        }

        $result = $ScriptText
        foreach ($r in @($replacements | Sort-Object Start -Descending)) {
            $result = $result.Substring(0, $r.Start) + $r.Text + $result.Substring($r.End)
        }

        $check = Test-PowerShellSyntax -ScriptText $result
        if ($check.IsValid) {
            return (Append-SensitiveEvidenceCommentBlock -ScriptText $result -Evidence ($sensitiveEvidence.ToArray()))
        }

        return (Append-SensitiveEvidenceCommentBlock -ScriptText $ScriptText -Evidence ($sensitiveEvidence.ToArray()))
    } catch {
        return $ScriptText
    } finally {
        Remove-Variable -Name __psdissect_sensitive_replacements -Scope Script -ErrorAction SilentlyContinue
        Close-WholeScriptStaticResolutionContext -Context $ctx
    }
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

    $noiseReduced = Remove-StandaloneCmdlineNoiseLines -ScriptText $working
    $check = Test-PowerShellSyntax -ScriptText $noiseReduced
    if ($check.IsValid) {
        $working = $noiseReduced
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

function Test-IsSimpleCommandArgumentValue {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }

    return ($Value -match '^[A-Za-z_][A-Za-z0-9_-]*$')
}

function Test-ExistingCommandArgumentLiteralAst {
    param([System.Management.Automation.Language.Ast]$Ast)

    if ($null -eq $Ast) {
        return $false
    }

    if ($Ast -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
        return $true
    }

    if ($Ast -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) {
        return (@($Ast.NestedExpressions).Count -eq 0)
    }

    if (($Ast -is [System.Management.Automation.Language.ArrayLiteralAst]) -or
        ($Ast -is [System.Management.Automation.Language.ArrayExpressionAst]) -or
        ($Ast -is [System.Management.Automation.Language.HashtableAst])) {
        return $true
    }

    return $false
}

function Test-IsRuntimeScopedVariableName {
    param([AllowNull()][string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $false
    }

    return ($Name -match '^(?i:env:[A-Za-z_][A-Za-z0-9_]*|PSScriptRoot|PSCommandPath|MyInvocation|PID|Args|Input|PSItem|_)$')
}

function Test-SafeSimpleCommandArgumentStaticNormalizationAst {
    param([System.Management.Automation.Language.Ast]$Ast)

    if ($null -eq $Ast) {
        return $false
    }

    $containsUnsupported = @($Ast.FindAll({
                param($n)
                ($n -is [System.Management.Automation.Language.CommandAst]) -or
                ($n -is [System.Management.Automation.Language.AssignmentStatementAst]) -or
                ($n -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) -or
                ($n -is [System.Management.Automation.Language.FunctionDefinitionAst]) -or
                ($n -is [System.Management.Automation.Language.ParamBlockAst])
            }, $true)).Count -gt 0
    if ($containsUnsupported) {
        return $false
    }

    $runtimeScopedVariable = @($Ast.FindAll({
                param($n)
                ($n -is [System.Management.Automation.Language.VariableExpressionAst]) -and
                $n.VariablePath -and
                (Test-IsRuntimeScopedVariableName -Name ([string]$n.VariablePath.UserPath))
            }, $true) | Select-Object -First 1)
    if ($runtimeScopedVariable.Count -gt 0) {
        return $false
    }

    return $true
}

function Convert-SimpleCommandArgumentResolvedTextToReplacementText {
    param([AllowNull()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }

    return (Convert-ReplacementTextToExpressionLiteral -Text $Text)
}

function Test-CommandArgumentMayBenefitFromStaticNormalization {
    param([System.Management.Automation.Language.Ast]$Ast)

    if ($null -eq $Ast -or -not $Ast.Extent) {
        return $false
    }

    if (($Ast -is [System.Management.Automation.Language.StringConstantExpressionAst]) -or
        (($Ast -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) -and @($Ast.NestedExpressions).Count -eq 0)) {
        return $false
    }

    if ($Ast -is [System.Management.Automation.Language.ArrayLiteralAst]) {
        foreach ($elem in @($Ast.Elements)) {
            if ($elem -and (Test-CommandArgumentMayBenefitFromStaticNormalization -Ast $elem)) {
                return $true
            }
        }
        return $false
    }

    return (Test-SafeSimpleCommandArgumentStaticNormalizationAst -Ast $Ast)
}

function Get-SimpleCommandArgumentReplacementText {
    param(
        [Parameter(Mandatory)][System.Management.Automation.Language.Ast]$Ast,
        [Parameter(Mandatory)][string]$SourceText,
        [hashtable]$Context = $null
    )

    if (-not $Ast.Extent) {
        return $null
    }
    if (Test-TypedScalarExpressionText -Text ([string]$Ast.Extent.Text)) {
        return $null
    }

    $value = $null
    $typedReplacement = $null
    if ($Ast -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
        $value = [string]$Ast.Value
    } elseif ($Ast -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) {
        if (@($Ast.NestedExpressions).Count -gt 0) {
            $value = $null
        } else {
            $value = Get-ExpandableStringLiteralOnlyValue -Ast $Ast -SourceText $SourceText
        }
    }

    if ([string]::IsNullOrWhiteSpace($value) -and $Context -and (Test-SafeSimpleCommandArgumentStaticNormalizationAst -Ast $Ast)) {
        try {
            $staticInfo = Resolve-StaticAstTextInfo -Ast $Ast -Context $Context -AllowEmptyFallback:$false
        } catch {
            $staticInfo = $null
        }
        if ($staticInfo -and -not [string]::IsNullOrWhiteSpace([string]$staticInfo.Text)) {
            $value = [string]$staticInfo.Text
            if ($staticInfo.PSObject.Properties['Value']) {
                $typedReplacement = Format-TypedScalarResolvableValue $staticInfo.Value
            }
        }
    }

    $replacementText = if (-not [string]::IsNullOrWhiteSpace([string]$typedReplacement)) {
        [string]$typedReplacement
    } else {
        Convert-SimpleCommandArgumentResolvedTextToReplacementText -Text $value
    }
    if ([string]::IsNullOrWhiteSpace($replacementText)) {
        return $null
    }

    if ([string]$Ast.Extent.Text -ceq [string]$replacementText) {
        return $null
    }

    return [string]$replacementText
}

function Get-SimpleCommandArgumentReplacementRecords {
    param(
        [Parameter(Mandatory)][System.Management.Automation.Language.Ast]$Ast,
        [Parameter(Mandatory)][string]$SourceText,
        [hashtable]$Context = $null
    )

    if (-not $Ast.Extent) {
        return @()
    }
    if (Test-ExistingCommandArgumentLiteralAst -Ast $Ast) {
        return @()
    }

    $candidateAsts = @()
    if ($Ast -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) {
        $candidateAsts = @($Ast)
    } elseif ($Ast -is [System.Management.Automation.Language.ArrayLiteralAst]) {
        $candidateAsts = @($Ast.Elements | Where-Object {
                $_ -and $_.Extent -and (
                    (-not (Test-ExistingCommandArgumentLiteralAst -Ast $_)) -and (
                    ($_ -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) -or
                    (Test-SafeSimpleCommandArgumentStaticNormalizationAst -Ast $_)
                    )
                )
            })
    } elseif ($Context -and (Test-SafeSimpleCommandArgumentStaticNormalizationAst -Ast $Ast)) {
        $candidateAsts = @($Ast)
    } else {
        return @()
    }

    $records = New-Object System.Collections.Generic.List[object]
    foreach ($candidateAst in $candidateAsts) {
        if (-not $candidateAst -or -not $candidateAst.Extent) { continue }

        $normalized = Get-SimpleCommandArgumentReplacementText -Ast $candidateAst -SourceText $SourceText -Context $Context
        if ([string]::IsNullOrWhiteSpace($normalized)) { continue }

        $records.Add([PSCustomObject]@{
                Start = [int]$candidateAst.Extent.StartOffset
                End   = [int]$candidateAst.Extent.EndOffset
                Text  = [string]$normalized
            }) | Out-Null
    }

    return @($records.ToArray())
}

function Invoke-CanonicalizeIndirectCommandHeads {
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
                $staticCandidate = Try-GetStaticStringValue -Ast $firstElement -Context $dummyContext
                if (Test-CommandNameExistsInContext -CommandName $staticCandidate -Context $dummyContext) {
                    $resolvedName = & $resolveCanonicalCommandName $staticCandidate
                }
            }

            if ([string]::IsNullOrWhiteSpace($resolvedName)) {
                $resolution = Resolve-CommandNameFromGetCommandExpression -CommandAst $cmdAst -FirstElementAst $firstElement -Context $dummyContext
                if ($resolution -and $resolution.Success) {
                    $resolvedName = & $resolveCanonicalCommandName ([string]$resolution.ResolvedName)
                }
            }

            if ([string]::IsNullOrWhiteSpace($resolvedName)) { continue }

            $headStart = [int]$cmdAst.Extent.StartOffset
            $headEnd = [int]$firstElement.Extent.EndOffset
            if ($headEnd -le $headStart) { continue }

            $replacementText = [string]$resolvedName
            if (Get-Command Get-ResolvedCommandHeadText -ErrorAction SilentlyContinue) {
                $replacementText = Get-ResolvedCommandHeadText -CommandAst $cmdAst -ResolvedName $resolvedName
            }

            $currentHeadText = $ScriptText.Substring($headStart, $headEnd - $headStart)
            if ([string]$currentHeadText -ceq $replacementText) { continue }

            $replacements += [PSCustomObject]@{
                Start = $headStart
                End   = $headEnd
                Text  = [string]$replacementText
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

function Invoke-CanonicalizeWildcardCommandTargets {
    param([Parameter(Mandatory)][string]$ScriptText)

    return (Invoke-CanonicalizeIndirectCommandHeads -ScriptText $ScriptText)
}

function Invoke-CanonicalizeDirectCommandNames {
    param([Parameter(Mandatory)][string]$ScriptText)

    if ([string]::IsNullOrWhiteSpace($ScriptText)) {
        return $ScriptText
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
        if ([string]$cmdAst.InvocationOperator -in @('Ampersand', 'Dot')) { continue }

        $firstElement = $cmdAst.CommandElements[0]
        if (-not $firstElement -or -not $firstElement.Extent) { continue }

        $commandName = $cmdAst.GetCommandName()
        $canonicalName = Resolve-CanonicalCommandNameText -Name $commandName
        if ([string]::IsNullOrWhiteSpace($canonicalName) -or [string]$canonicalName -eq [string]$commandName) {
            $rawCandidate = [string]$firstElement.Extent.Text
            if (-not [string]::IsNullOrWhiteSpace($rawCandidate)) {
                $rawCandidate = ($rawCandidate -replace '`', '').Trim()
                if ($rawCandidate.Length -ge 2 -and
                    (($rawCandidate.StartsWith("'") -and $rawCandidate.EndsWith("'")) -or
                     ($rawCandidate.StartsWith('"') -and $rawCandidate.EndsWith('"')))) {
                    $rawCandidate = $rawCandidate.Substring(1, $rawCandidate.Length - 2)
                }

                $rawResolution = Try-Resolve-CanonicalCommandNameText -Name $rawCandidate
                if ($rawResolution.Found -and -not [string]::IsNullOrWhiteSpace([string]$rawResolution.Name)) {
                    $canonicalName = [string]$rawResolution.Name
                }
            }
        }

        if ([string]::IsNullOrWhiteSpace($canonicalName)) { continue }
        if ([string]$firstElement.Extent.Text -ceq $canonicalName) { continue }

        $replacements += [PSCustomObject]@{
            Start = [int]$firstElement.Extent.StartOffset
            End   = [int]$firstElement.Extent.EndOffset
            Text  = [string]$canonicalName
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

function Invoke-RemoveRedundantAmpersandForDirectCommands {
    param([Parameter(Mandatory)][string]$ScriptText)

    if ([string]::IsNullOrWhiteSpace($ScriptText)) {
        return $ScriptText
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
        if ([string]$cmdAst.InvocationOperator -ne 'Ampersand') { continue }
        if (-not $cmdAst.CommandElements -or $cmdAst.CommandElements.Count -eq 0) { continue }

        $firstElement = $cmdAst.CommandElements[0]
        if (-not $firstElement -or -not $firstElement.Extent) { continue }

        $commandName = $cmdAst.GetCommandName()
        if ([string]::IsNullOrWhiteSpace($commandName)) { continue }

        $canonical = Try-Resolve-CanonicalCommandNameText -Name $commandName
        if (-not $canonical.Found -or [string]::IsNullOrWhiteSpace([string]$canonical.Name)) { continue }

        $start = [int]$cmdAst.Extent.StartOffset
        $end = [int]$firstElement.Extent.StartOffset
        if ($end -le $start) { continue }

        $prefixText = $ScriptText.Substring($start, $end - $start)
        if ($prefixText -notmatch '^\s*&\s*$') { continue }

        $replacements += [PSCustomObject]@{
            Start = $start
            End   = $end
            Text  = ''
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

function Invoke-NormalizeSimpleCommandArguments {
    param([Parameter(Mandatory)][string]$ScriptText)

    if ([string]::IsNullOrWhiteSpace($ScriptText)) {
        return $ScriptText
    }

    $parse = Get-ScriptParseInfo -ScriptText $ScriptText
    if (-not $parse.IsValid -or -not $parse.Ast) {
        return $ScriptText
    }

    $topLevelStatements = @(Get-TopLevelScriptStatementsFromText -ScriptText $ScriptText)
    if ($topLevelStatements.Count -eq 0) {
        return $ScriptText
    }

    $needsStaticContext = $false
    foreach ($statement in @($topLevelStatements)) {
        $commandAsts = @($statement.FindAll({
                    param($n)
                    $n -is [System.Management.Automation.Language.CommandAst]
                }, $true))
        foreach ($cmdAst in @($commandAsts)) {
            if (-not $cmdAst.CommandElements -or $cmdAst.CommandElements.Count -lt 2) { continue }

            for ($i = 1; $i -lt $cmdAst.CommandElements.Count; $i++) {
                $elem = $cmdAst.CommandElements[$i]
                if (-not $elem -or -not $elem.Extent) { continue }

                $targetAst = $elem
                if ($elem -is [System.Management.Automation.Language.CommandParameterAst]) {
                    $targetAst = $elem.Argument
                }

                if ($targetAst -and (Test-CommandArgumentMayBenefitFromStaticNormalization -Ast $targetAst)) {
                    $needsStaticContext = $true
                    break
                }
            }

            if ($needsStaticContext) { break }
        }

        if ($needsStaticContext) { break }
    }

    $ctx = $null
    $replacements = @()
    try {
        if ($needsStaticContext) {
            $ctx = New-WholeScriptStaticResolutionContext
            $staticEvalState = Get-StaticEvalState -Context $ctx
            if ($staticEvalState) {
                $staticEvalState.ValueDepthLimit = 96
                $staticEvalState.StringCompatDepthLimit = 72
            }
        }

        foreach ($statement in @($topLevelStatements)) {
            $statementCommandAsts = @($statement.FindAll({
                        param($n)
                        $n -is [System.Management.Automation.Language.CommandAst]
                    }, $true))

            foreach ($cmdAst in @($statementCommandAsts)) {
                if (-not $cmdAst.CommandElements -or $cmdAst.CommandElements.Count -lt 2) { continue }

                for ($i = 1; $i -lt $cmdAst.CommandElements.Count; $i++) {
                    $elem = $cmdAst.CommandElements[$i]
                    if (-not $elem -or -not $elem.Extent) { continue }

                    if ($elem -is [System.Management.Automation.Language.CommandParameterAst]) {
                        if ($elem.Argument -and $elem.Argument.Extent) {
                            foreach ($replacement in @(Get-SimpleCommandArgumentReplacementRecords -Ast $elem.Argument -SourceText $ScriptText -Context $ctx)) {
                                $replacements += $replacement
                            }
                        }

                        continue
                    }

                    foreach ($replacement in @(Get-SimpleCommandArgumentReplacementRecords -Ast $elem -SourceText $ScriptText -Context $ctx)) {
                        $replacements += $replacement
                    }
                }
            }

            if ($ctx) {
                try {
                    [void](Invoke-WholeScriptStaticStatement -Statement $statement -Context $ctx -AllowEmptyFallback:$false)
                } catch {
                    if (-not (Test-IsCallDepthOverflowException -ErrorObject $_)) {
                        throw
                    }
                }
            }
        }
    } finally {
        Close-WholeScriptStaticResolutionContext -Context $ctx
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

function Invoke-NormalizeMandatoryBase64Expressions {
    param([Parameter(Mandatory)][string]$ScriptText)

    if ([string]::IsNullOrWhiteSpace($ScriptText)) {
        return $ScriptText
    }

    $parse = Get-ScriptParseInfo -ScriptText $ScriptText
    if (-not $parse.IsValid -or -not $parse.Ast) {
        return $ScriptText
    }

    $ctx = New-WholeScriptStaticResolutionContext
    try {
        $state = Get-StaticEvalState -Context $ctx
        if ($state) {
            $state.ValueDepthLimit = 96
            $state.StringCompatDepthLimit = 72
        }

        $topLevelStatements = @(Get-TopLevelScriptStatementsFromText -ScriptText $ScriptText)
        if ($topLevelStatements.Count -gt 0) {
            [void](Initialize-WholeScriptStaticAssignments -Statements $topLevelStatements -Context $ctx)
        }

        $replacements = New-Object System.Collections.Generic.List[object]

        $commandAsts = @($parse.Ast.FindAll({
                    param($n)
                    $n -is [System.Management.Automation.Language.CommandAst] -and (Test-MandatoryBase64CommandAst -CommandAst $n)
                }, $true))
        foreach ($cmdAst in $commandAsts) {
            if (-not $cmdAst -or -not $cmdAst.Extent) { continue }

            $decodedInfo = $null
            try {
                $decodedInfo = Try-DecodeEncodedCommand -CommandAst $cmdAst
            } catch {
                $decodedInfo = $null
            }
            if (-not $decodedInfo -or [string]::IsNullOrWhiteSpace([string]$decodedInfo.ReplacementText)) {
                continue
            }

            $original = [string]$cmdAst.Extent.Text
            $replacement = [string]$decodedInfo.ReplacementText
            if ($replacement -eq $original) {
                continue
            }

            $replacements.Add([PSCustomObject]@{
                    Start = [int]$cmdAst.Extent.StartOffset
                    End   = [int]$cmdAst.Extent.EndOffset
                    Text  = $replacement
                }) | Out-Null
        }

        $exprAsts = @($parse.Ast.FindAll({
                    param($n)
                    $n -is [System.Management.Automation.Language.ExpressionAst] -and (Test-MandatoryBase64ExpressionAst -Ast $n)
                }, $true) | Sort-Object -Property @{ Expression = { [int]$_.Extent.StartOffset } }, @{ Expression = { -([int]$_.Extent.EndOffset - [int]$_.Extent.StartOffset) } })
        foreach ($exprAst in $exprAsts) {
            if (-not $exprAst -or -not $exprAst.Extent) { continue }

            $replacement = Get-MandatoryBase64ExpressionReplacementText -Ast $exprAst -Context $ctx
            if ([string]::IsNullOrWhiteSpace($replacement)) {
                continue
            }

            $original = [string]$exprAst.Extent.Text
            if ($replacement -eq $original) {
                continue
            }

            $replacements.Add([PSCustomObject]@{
                    Start = [int]$exprAst.Extent.StartOffset
                    End   = [int]$exprAst.Extent.EndOffset
                    Text  = $replacement
                }) | Out-Null
        }

        if ($replacements.Count -eq 0) {
            return $ScriptText
        }

        $selectedReplacements = @()
        foreach ($candidate in @($replacements | Sort-Object -Property @{ Expression = { [int]$_.Start } }, @{ Expression = { -([int]$_.End - [int]$_.Start) } })) {
            $overlaps = $false
            foreach ($existing in $selectedReplacements) {
                if ([int]$candidate.Start -lt [int]$existing.End -and [int]$candidate.End -gt [int]$existing.Start) {
                    $overlaps = $true
                    break
                }
            }

            if (-not $overlaps) {
                $selectedReplacements += $candidate
            }
        }

        $result = $ScriptText
        foreach ($replacement in @($selectedReplacements | Sort-Object Start -Descending)) {
            $result = $result.Substring(0, $replacement.Start) + [string]$replacement.Text + $result.Substring($replacement.End)
        }

        $check = Test-PowerShellSyntax -ScriptText $result
        if ($check.IsValid) {
            return $result
        }

        return $ScriptText
    } finally {
        Close-WholeScriptStaticResolutionContext -Context $ctx
    }
}

function Invoke-PostProcessDeobfuscatedScriptText {
    param(
        [Parameter(Mandatory)][string]$ScriptText,
        [ValidateSet('Disabled', 'Conservative', 'Balanced', 'Aggressive')]
        [string]$PreExecutionGateMode = 'Disabled',
        [bool]$SafeMode = $true,
        [hashtable]$PreExecutionGateCache = $null
    )

    $working = $ScriptText
    $fastSensitiveConfig = Get-FastSensitivePassConfig
    $fastPostProcessTriggerTextLength = if ((Test-IsAdaptiveCoverageOptimizationProfile) -and $fastSensitiveConfig.Enabled) {
        [int]$fastSensitiveConfig.TriggerTextLength
    } else {
        16384
    }
    $fastTimeoutPostProcess = ((Test-UsesFastTimeoutPostProcessProfile) -and ($working.Length -ge $fastPostProcessTriggerTextLength))
    $maxPasses = if ($fastTimeoutPostProcess) { 1 } else { 8 }

    if ($fastTimeoutPostProcess) {
        $working = Invoke-CanonicalizeIndirectCommandHeads -ScriptText $working
        $working = Invoke-CanonicalizeDirectCommandNames -ScriptText $working
        $working = Invoke-RemoveRedundantAmpersandForDirectCommands -ScriptText $working
        $working = Invoke-NormalizeSimpleCommandArguments -ScriptText $working
        $working = Invoke-WholeScriptStaticPathRewritePass -ScriptText $working
        $working = Invoke-NormalizeMandatoryBase64Expressions -ScriptText $working
        $mandatoryPayloadInfo = Try-Resolve-WholeScriptMandatoryBase64PayloadInfo -ScriptText $working
        if ($mandatoryPayloadInfo -and -not [string]::IsNullOrWhiteSpace([string]$mandatoryPayloadInfo.PayloadText)) {
            $working = [string]$mandatoryPayloadInfo.PayloadText
            $working = Invoke-CanonicalizeIndirectCommandHeads -ScriptText $working
            $working = Invoke-CanonicalizeDirectCommandNames -ScriptText $working
            $working = Invoke-RemoveRedundantAmpersandForDirectCommands -ScriptText $working
            $working = Invoke-NormalizeSimpleCommandArguments -ScriptText $working
            $working = Invoke-WholeScriptStaticPathRewritePass -ScriptText $working
            $working = Invoke-NormalizeMandatoryBase64Expressions -ScriptText $working
        }

        $stageStripped = Try-StripDuplicatedStageWrapper -ScriptText $working
        if (-not [string]::IsNullOrWhiteSpace($stageStripped)) {
            $working = $stageStripped
        }

        $expandedIexPayload = Invoke-ExpandWholeScriptLocalIexPayloads -ScriptText $working -PreExecutionGateMode $PreExecutionGateMode -PreExecutionGateCache $PreExecutionGateCache
        if ((Get-NormalizedScriptComparisonText -ScriptText $expandedIexPayload) -ne (Get-NormalizedScriptComparisonText -ScriptText $working)) {
            $expandedCheck = Test-PowerShellSyntax -ScriptText $expandedIexPayload
            if ($expandedCheck.IsValid) {
                $expandedIexPayload = Invoke-WholeScriptStaticGetContentMaterializationPass -ScriptText $expandedIexPayload
                return (Invoke-AppendWholeScriptHarvestedSensitiveEvidenceCommentBlock -ScriptText $expandedIexPayload -Source 'postprocess_fast_expanded' -Stage 'postprocess_fast_expanded')
            }
        }
        $working = $expandedIexPayload
        $working = Invoke-ExpandWholeScriptLocalArtifactLaunchPass -ScriptText $working
        $working = Invoke-WholeScriptStaticGetContentMaterializationPass -ScriptText $working

        if (Test-IsAdaptiveCoverageOptimizationProfile) {
            $working = Invoke-NormalizeSensitiveIndicatorArgumentsFast -ScriptText $working
        }

        $fastCheck = Test-PowerShellSyntax -ScriptText $working
        if ($fastCheck.IsValid) {
            return (Invoke-AppendWholeScriptHarvestedSensitiveEvidenceCommentBlock -ScriptText $working -Source 'postprocess_fast' -Stage 'postprocess_fast')
        }

        return (Invoke-AppendWholeScriptHarvestedSensitiveEvidenceCommentBlock -ScriptText $ScriptText -Source 'postprocess_fast_fallback' -Stage 'postprocess_fast_fallback')
    }

    for ($pass = 0; $pass -lt $maxPasses; $pass++) {
        $before = Get-NormalizedScriptComparisonText -ScriptText $working

        $working = Invoke-CanonicalizeIndirectCommandHeads -ScriptText $working
        $working = Invoke-CanonicalizeDirectCommandNames -ScriptText $working
        $working = Invoke-RemoveRedundantAmpersandForDirectCommands -ScriptText $working
        $working = Invoke-NormalizeSimpleCommandArguments -ScriptText $working
        $working = Invoke-WholeScriptStaticPathRewritePass -ScriptText $working
        $working = Invoke-NormalizeMandatoryBase64Expressions -ScriptText $working

        while ($true) {
            $payloadInfo = Try-Resolve-WholeScriptMandatoryBase64PayloadInfo -ScriptText $working
            if (-not $payloadInfo) {
                $payloadInfo = Resolve-WholeScriptHostPayloadInfo -ScriptText $working
            }
            if ((-not $payloadInfo) -and (-not $fastTimeoutPostProcess)) {
                $payloadInfo = Try-Resolve-WholeScriptStaticPayloadInfoSafe -ScriptText $working -WarningContext 'postprocess' -PreExecutionGateMode $PreExecutionGateMode -PreExecutionGateCache $PreExecutionGateCache -SafeMode:$SafeMode
            }
            if (-not $payloadInfo) { break }

            $payloadText = Get-WholeScriptReplacementCandidateText -OriginalText $working -CandidateText $payloadInfo.PayloadText
            if (-not $payloadText) { break }

            $payloadParse = Get-ScriptParseInfo -ScriptText $payloadText
            if (-not $payloadParse.IsValid) { break }

            if ((Get-NormalizedScriptComparisonText -ScriptText $payloadText) -eq (Get-NormalizedScriptComparisonText -ScriptText $working)) {
                break
            }

            $working = $payloadText
            $working = Invoke-CanonicalizeIndirectCommandHeads -ScriptText $working
            $working = Invoke-CanonicalizeDirectCommandNames -ScriptText $working
            $working = Invoke-RemoveRedundantAmpersandForDirectCommands -ScriptText $working
            $working = Invoke-NormalizeSimpleCommandArguments -ScriptText $working
            $working = Invoke-WholeScriptStaticPathRewritePass -ScriptText $working
            $working = Invoke-NormalizeMandatoryBase64Expressions -ScriptText $working
        }

        if (-not $fastTimeoutPostProcess) {
            $working = Invoke-NormalizeSensitiveIndicatorArguments -ScriptText $working
        }

        $stageStripped = Try-StripDuplicatedStageWrapper -ScriptText $working
        if (-not [string]::IsNullOrWhiteSpace($stageStripped)) {
            $working = $stageStripped
        }

        $working = Invoke-ExpandWholeScriptLocalIexPayloads -ScriptText $working -PreExecutionGateMode $PreExecutionGateMode -PreExecutionGateCache $PreExecutionGateCache
        $working = Invoke-ExpandWholeScriptLocalArtifactLaunchPass -ScriptText $working
        $working = Invoke-WholeScriptStaticGetContentMaterializationPass -ScriptText $working

        $after = Get-NormalizedScriptComparisonText -ScriptText $working
        if ($after -eq $before) {
            break
        }
    }

    $normalized = Invoke-NormalizePlainScriptText -ScriptText $working
    $check = Test-PowerShellSyntax -ScriptText $normalized
    if ($check.IsValid) {
        return (Invoke-AppendWholeScriptHarvestedSensitiveEvidenceCommentBlock -ScriptText $normalized -Source 'postprocess_final' -Stage 'postprocess_final')
    }

    return (Invoke-AppendWholeScriptHarvestedSensitiveEvidenceCommentBlock -ScriptText $working -Source 'postprocess_fallback' -Stage 'postprocess_fallback')
}

function Ensure-ParentDirectory {
    param([Parameter(Mandatory)][string]$Path)

    $parent = $null
    try {
        $parent = [System.IO.Path]::GetDirectoryName($Path)
    } catch {
        $parent = $null
    }

    if ([string]::IsNullOrWhiteSpace($parent)) {
        return
    }

    if (-not (Test-Path -LiteralPath $parent)) {
        $null = New-Item -ItemType Directory -Path $parent -Force
    }
}

function Move-TemporaryFileIntoPlace {
    param(
        [Parameter(Mandatory)][string]$TemporaryPath,
        [Parameter(Mandatory)][string]$DestinationPath
    )

    $sourcePath = [System.IO.Path]::GetFullPath($TemporaryPath)
    $targetPath = [System.IO.Path]::GetFullPath($DestinationPath)

    if (Test-Path -LiteralPath $targetPath) {
        $targetDirectory = [System.IO.Path]::GetDirectoryName($targetPath)
        $targetLeafName = [System.IO.Path]::GetFileName($targetPath)
        $backupPath = [System.IO.Path]::Combine($targetDirectory, ("{0}.{1}.bak" -f $targetLeafName, ([guid]::NewGuid().ToString('N'))))
        try {
            [System.IO.File]::Replace($sourcePath, $targetPath, $backupPath, $true)
        } finally {
            if (Test-Path -LiteralPath $backupPath) {
                Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
            }
        }
    } else {
        [System.IO.File]::Move($sourcePath, $targetPath)
    }
}

function Write-TextFileAtomic {
    param(
        [Parameter(Mandatory)][string]$Path,
        [AllowEmptyString()][AllowNull()][string]$Content,
        [int]$RetryCount = 3,
        [int]$RetryDelayMs = 120
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    Ensure-ParentDirectory -Path $fullPath

    $directory = [System.IO.Path]::GetDirectoryName($fullPath)
    $leafName = [System.IO.Path]::GetFileName($fullPath)
    $attempts = [Math]::Max(1, $RetryCount)
    $lastError = $null

    for ($attempt = 1; $attempt -le $attempts; $attempt++) {
        $tmpPath = [System.IO.Path]::Combine($directory, ("{0}.{1}.tmp" -f $leafName, ([guid]::NewGuid().ToString('N'))))
        try {
            $text = if ($null -eq $Content) { '' } else { [string]$Content }
            [System.IO.File]::WriteAllText($tmpPath, $text, [System.Text.UTF8Encoding]::new($false))
            Move-TemporaryFileIntoPlace -TemporaryPath $tmpPath -DestinationPath $fullPath
            return
        } catch {
            $lastError = $_
            try {
                if (Test-Path -LiteralPath $tmpPath) {
                    Remove-Item -LiteralPath $tmpPath -Force -ErrorAction SilentlyContinue
                }
            } catch {
            }

            if ($attempt -lt $attempts) {
                Start-Sleep -Milliseconds $RetryDelayMs
            }
        }
    }

    throw $lastError
}

function Copy-FileAtomic {
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$DestinationPath,
        [int]$RetryCount = 3,
        [int]$RetryDelayMs = 120
    )

    $fullDestinationPath = [System.IO.Path]::GetFullPath($DestinationPath)
    Ensure-ParentDirectory -Path $fullDestinationPath

    $directory = [System.IO.Path]::GetDirectoryName($fullDestinationPath)
    $leafName = [System.IO.Path]::GetFileName($fullDestinationPath)
    $attempts = [Math]::Max(1, $RetryCount)
    $lastError = $null

    for ($attempt = 1; $attempt -le $attempts; $attempt++) {
        $tmpPath = [System.IO.Path]::Combine($directory, ("{0}.{1}.tmp" -f $leafName, ([guid]::NewGuid().ToString('N'))))
        try {
            [System.IO.File]::Copy($SourcePath, $tmpPath, $true)
            Move-TemporaryFileIntoPlace -TemporaryPath $tmpPath -DestinationPath $fullDestinationPath
            return
        } catch {
            $lastError = $_
            try {
                if (Test-Path -LiteralPath $tmpPath) {
                    Remove-Item -LiteralPath $tmpPath -Force -ErrorAction SilentlyContinue
                }
            } catch {
            }

            if ($attempt -lt $attempts) {
                Start-Sleep -Milliseconds $RetryDelayMs
            }
        }
    }

    throw $lastError
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Object
    )

    $json = $Object | ConvertTo-Json -Depth 10
    Write-TextFileAtomic -Path $Path -Content $json
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


$scriptFullPath = (Resolve-Path -LiteralPath $ScriptPath).ProviderPath
$script:__psdissect_current_input_path = $scriptFullPath

if ([string]::IsNullOrWhiteSpace($OutPath)) {
    $dir = [System.IO.Path]::GetDirectoryName($scriptFullPath)
    $base = [System.IO.Path]::GetFileNameWithoutExtension($scriptFullPath)
    $OutPath = Join-Path $dir ($base + '.rebuilt.ps1')
}

$OutPath = [System.IO.Path]::GetFullPath($OutPath)
if (-not [string]::IsNullOrWhiteSpace($RunMetadataPath)) {
    $RunMetadataPath = [System.IO.Path]::GetFullPath($RunMetadataPath)
}

if ($FullOutput) {
    if ([string]::IsNullOrWhiteSpace($WorkDir)) {
        $WorkDir = $OutPath + '.work'
    }
    $WorkDir = [System.IO.Path]::GetFullPath($WorkDir)

    if (-not (Test-Path -LiteralPath $WorkDir)) {
        $null = New-Item -ItemType Directory -Path $WorkDir -Force
    }
} else {
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
$profileSettings = Get-OptimizationProfileSettings -Profile $OptimizationProfile -RequestedMaxRounds $MaxRounds
$effectiveMaxRounds = [int]$profileSettings.EffectiveMaxRounds
$profileChangedExecutionPlan = ($effectiveMaxRounds -ne $MaxRounds)
$completionKind = 'full'

Write-Host "=== 重建解混淆脚本（递归迭代）===" -ForegroundColor Cyan
Write-Host "Host       : $hostDisplay" -ForegroundColor Gray
if ($hostInfo.ExecutablePath) { Write-Host "HostExe    : $($hostInfo.ExecutablePath)" -ForegroundColor Gray }
Write-Host "ScriptPath : $scriptFullPath" -ForegroundColor Gray
Write-Host "OutPath    : $OutPath" -ForegroundColor Gray
Write-Host "FullOutput : $FullOutput" -ForegroundColor Gray
if ($FullOutput) {
    Write-Host "WorkDir    : $WorkDir" -ForegroundColor Gray
}
Write-Host "Profile    : $OptimizationProfile" -ForegroundColor Gray
Write-Host "Strategy   : $effectiveOverlapStrategy" -ForegroundColor Gray
Write-Host "VarPolicy  : $effectiveVariableConflictPolicy" -ForegroundColor Gray
Write-Host "DynPolicy  : $effectiveDynamicConflictPolicy" -ForegroundColor Gray
Write-Host "SafeMode   : $SafeMode" -ForegroundColor Gray
Write-Host "GateMode   : $PreExecutionGateMode" -ForegroundColor Gray
if ($effectiveMaxRounds -ne $MaxRounds) {
    Write-Host ("MaxRounds  : {0} (requested {1})" -f $effectiveMaxRounds, $MaxRounds) -ForegroundColor Gray
} else {
    Write-Host "MaxRounds  : $MaxRounds" -ForegroundColor Gray
}
Write-Host "TimeBudget : Global=${GlobalTimeBudgetMs}ms Dynamic=${DynamicTimeBudgetMs}ms" -ForegroundColor Gray
if ([int]$profileSettings.FinalizationReserveMs -gt 0) {
    Write-Host ("FinalizeReserve : {0}ms" -f $profileSettings.FinalizationReserveMs) -ForegroundColor Gray
}
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
$preExecutionGateCache = @{}

for ($round = 1; $round -le $effectiveMaxRounds; $round++) {
    $remainingGlobalBudgetMs = Get-RemainingTimeBudgetMs -BudgetMs $GlobalTimeBudgetMs -Stopwatch $globalStopwatch
    if ($GlobalTimeBudgetMs -gt 0 -and $remainingGlobalBudgetMs -le [int]$profileSettings.FinalizationReserveMs) {
        $terminatedBy = 'global_time_budget'
        $finalRound = [Math]::Max(0, $round - 1)
        if (Test-IsTimeoutCoverageOptimizationProfile) {
            $completionKind = 'budget_partial'
        }
        break
    }

    $roundLabel = '{0:d2}' -f $round
    $roundInPath = $null
    $roundOutPath = $null
    $roundLogPath = $null
    $roundReportPath = $null
    $roundCfgDotPath = $null
    $roundCfgPngPath = $null
    $cfg = $null
    $ctx = $null
    $remainingStaticBudgetMs = $null
    $roundExecutionPlan = $null

        if ($FullOutput) {
            $roundInPath = Join-Path $WorkDir ("round{0}.in.ps1" -f $roundLabel)
            $roundOutPath = Join-Path $WorkDir ("round{0}.out.ps1" -f $roundLabel)
            $roundLogPath = Join-Path $WorkDir ("round{0}.execution.log" -f $roundLabel)
            $roundReportPath = Join-Path $WorkDir ("round{0}.report.json" -f $roundLabel)
            $roundCfgDotPath = Join-Path $WorkDir ("round{0}.cfg.dot" -f $roundLabel)
        $roundCfgPngPath = [System.IO.Path]::ChangeExtension($roundCfgDotPath, '.png')

            Copy-Item -LiteralPath $currentPath -Destination $roundInPath -Force
            Write-Host ("[Round {0}/{1}] 分析+执行..." -f $round, $effectiveMaxRounds) -ForegroundColor Yellow

            $rawRoundText = Get-RawScriptTextFromFile -Path $roundInPath
            $roundParseInfo = Get-ScriptParseInfo -ScriptText $rawRoundText
            if (-not $roundParseInfo.IsValid) {
                $fallbackText = Get-BestEffortParseFallbackScriptText -ScriptText $rawRoundText -ParseError $roundParseInfo.FirstError
                Write-TextFileAtomic -Path $roundOutPath -Content $fallbackText

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

            $roundGate = Get-PreExecutionGateDecision -Scope 'Round' -ScriptText $rawRoundText -ParseInfo $roundParseInfo -Mode $PreExecutionGateMode -SafeMode:$SafeMode -Cache $preExecutionGateCache
            $effectiveRoundLimits = Get-EffectiveRoundExecutionLimits -BaseDynamicTimeBudgetMs $DynamicTimeBudgetMs -BaseMaxIterations $MaxIterations -BaseMaxTotalNodes $MaxTotalNodes -GateDecision $roundGate
            $roundExecutionPlan = Get-OptimizationProfileRoundPlan -ProfileSettings $profileSettings -GateDecision $roundGate -RemainingGlobalBudgetMs $remainingGlobalBudgetMs -Round $round -IsMaterializedPayloadRound:$currentRoundIsMaterializedPayload
            if ($roundExecutionPlan.RoundMode -ne 'default' -or $roundExecutionPlan.StopAfterThisRound) {
                $profileChangedExecutionPlan = $true
            }
            if ($roundExecutionPlan.DynamicTimeBudgetMs -gt 0) {
                $effectiveRoundLimits.DynamicTimeBudgetMs = if ($effectiveRoundLimits.DynamicTimeBudgetMs -le 0) { [int]$roundExecutionPlan.DynamicTimeBudgetMs } else { [Math]::Min([int]$effectiveRoundLimits.DynamicTimeBudgetMs, [int]$roundExecutionPlan.DynamicTimeBudgetMs) }
            }
            if ($roundExecutionPlan.MaxIterations -gt 0) {
                $effectiveRoundLimits.MaxIterations = [Math]::Min([int]$effectiveRoundLimits.MaxIterations, [int]$roundExecutionPlan.MaxIterations)
            }
            if ($roundExecutionPlan.MaxTotalNodes -gt 0) {
                $effectiveRoundLimits.MaxTotalNodes = [Math]::Min([int]$effectiveRoundLimits.MaxTotalNodes, [int]$roundExecutionPlan.MaxTotalNodes)
            }

            if ([string]$roundGate.Decision -eq 'Stop') {
                $stoppedText = Invoke-PostProcessDeobfuscatedScriptText -ScriptText $rawRoundText -PreExecutionGateMode $PreExecutionGateMode -SafeMode:$SafeMode -PreExecutionGateCache $preExecutionGateCache
                $stoppedText = if ($stoppedText -is [System.Array]) { ($stoppedText -join "`r`n") } else { [string]$stoppedText }
                $safeExtraction = Try-Resolve-GatedRoundSafePayloadInfo -ScriptText $stoppedText -OriginalText $rawRoundText -PreExecutionGateCache $preExecutionGateCache
                $continuedBySafeExtraction = ($safeExtraction -and -not [string]::IsNullOrWhiteSpace([string]$safeExtraction.PayloadText))
                $roundOutputText = if ($continuedBySafeExtraction) { [string]$safeExtraction.PayloadText } else { $stoppedText }
                Write-TextFileAtomic -Path $roundOutPath -Content $roundOutputText
                if (-not $continuedBySafeExtraction) {
                    $persistedRoundText = Get-RawScriptTextFromFile -Path $roundOutPath
                    if (-not [string]::IsNullOrWhiteSpace($persistedRoundText)) {
                        $safeExtraction = Try-Resolve-GatedRoundSafePayloadInfo -ScriptText $persistedRoundText -OriginalText $rawRoundText -PreExecutionGateCache $preExecutionGateCache
                        $continuedBySafeExtraction = ($safeExtraction -and -not [string]::IsNullOrWhiteSpace([string]$safeExtraction.PayloadText))
                        if ($continuedBySafeExtraction) {
                            $roundOutputText = [string]$safeExtraction.PayloadText
                            Write-TextFileAtomic -Path $roundOutPath -Content $roundOutputText
                        }
                    }
                }

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
                        GateMode           = $PreExecutionGateMode
                        TerminatedBy       = if ($continuedBySafeExtraction) { 'pre_execution_gate_safe_extracted' } else { 'pre_execution_gate' }
                        GateDecision       = $roundGate.Decision
                        GateScore          = $roundGate.Score
                        GateReasons        = @($roundGate.Reasons)
                        GateMetrics        = $roundGate.Metrics
                        SafeExtractionAttempted = $true
                        SafeExtractionSucceeded = [bool]$continuedBySafeExtraction
                        SafeExtractionSource = if ($continuedBySafeExtraction) { [string]$safeExtraction.Source } else { $null }
                        NextRoundIsMaterializedPayload = [bool]$continuedBySafeExtraction
                        NextRoundMaterializedPayloadReason = if ($continuedBySafeExtraction) { [string]$safeExtraction.Source } else { $null }
                        FinalSyntaxValid   = $true
                        FinalOutputSource  = 'rebuilt_output'
                        Timestamp          = (Get-Date).ToString('o')
                    }
                    Write-JsonFile -Path $roundReportPath -Object $report
                }

                $currentText = $roundOutputText
                $finalRound = $round
                $finalRoundOutPath = $roundOutPath
                $lastValidRoundOutPath = $roundOutPath
                $lastValidText = $roundOutputText
                if ($continuedBySafeExtraction) {
                    $currentPath = $roundOutPath
                    $currentRoundIsMaterializedPayload = $true
                    continue
                }

                $terminatedBy = 'pre_execution_gate'
                break
            }

            $preTraversalCheck = Get-PreTraversalStopCheckInfo -ScriptText $rawRoundText -IsMaterializedPayloadRound:$currentRoundIsMaterializedPayload
            if ($preTraversalCheck.ShouldCheck) {
                $roundStop = Test-DynamicPayloadShouldStopRecursing -ScriptText $preTraversalCheck.CheckText -SafeMode:$SafeMode -GateMode $PreExecutionGateMode -GateScope 'WholeScriptHelper' -GateCache $preExecutionGateCache
            } else {
                $roundStop = $null
            }

            if ($roundStop -and $roundStop.ShouldStop) {
                Write-TextFileAtomic -Path $roundOutPath -Content $rawRoundText

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

            $ctx = $null
            if ($roundExecutionPlan.SkipCfgTraversal) {
                $scriptText = $rawRoundText
                $currentText = $scriptText
            } else {
                $cfg = $null
                $cfgError = $null
                try {
                    $cfg = Get-ScriptControlFlow -ScriptPath $roundInPath
                } catch {
                    $cfgError = Get-ErrorSummaryText -ErrorObject $_ -DefaultMessage 'CFG generation failed'
                }
                if (-not $cfg) {
                    $fallbackText = if ($roundParseInfo.IsValid) { $rawRoundText } else { Get-BestEffortParseFallbackScriptText -ScriptText $rawRoundText -ParseError 'CFG generation failed' }
                    Write-TextFileAtomic -Path $roundOutPath -Content $fallbackText

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
                            CfgError           = $cfgError
                            ParseError         = $roundParseInfo.FirstError
                            FinalSyntaxValid   = [bool]$roundParseInfo.IsValid
                            FinalOutputSource  = 'rebuilt_output'
                            Timestamp          = (Get-Date).ToString('o')
                        }
                        Write-JsonFile -Path $roundReportPath -Object $report
                    }

                    $currentText = $fallbackText
                    $finalRound = $round
                    $finalRoundOutPath = $roundOutPath
                    if ($roundParseInfo.IsValid) {
                        $lastValidRoundOutPath = $roundOutPath
                        $lastValidText = $fallbackText
                    }
                    $terminatedBy = 'cfg_generation_failed'
                    break
                }

                $cfgTraversalError = $null
                try {
                    $ctx = Invoke-CFGTraversal -CFG $cfg -LogPath $roundLogPath -MaxIterations $effectiveRoundLimits.MaxIterations -MaxTotalNodes $effectiveRoundLimits.MaxTotalNodes -GlobalTimeBudgetMs $remainingGlobalBudgetMs -DynamicTimeBudgetMs $effectiveRoundLimits.DynamicTimeBudgetMs -SafeMode:$SafeMode
                } catch {
                    $cfgTraversalError = Get-ErrorSummaryText -ErrorObject $_ -DefaultMessage 'CFG traversal failed'
                }
                if ($null -eq $ctx) {
                    Write-TextFileAtomic -Path $roundOutPath -Content $rawRoundText

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
                            TerminatedBy       = 'cfg_traversal_failed'
                            TraversalError     = $cfgTraversalError
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
                    $terminatedBy = 'cfg_traversal_failed'
                    break
                }
                $ctx.PreExecutionGateMode = $PreExecutionGateMode
                $ctx.PreExecutionGateCache = $preExecutionGateCache
                $ctx.DynamicDepthLimit = $effectiveRoundLimits.DynamicDepthLimit

                $scriptText = Get-FullScriptTextFromFile -Path $roundInPath
                $currentText = $scriptText
            }
    } else {
        if ($null -eq $currentText) {
            $currentText = Get-FullScriptTextFromFile -Path $currentPath
        }

        Write-Host ("[Round {0}/{1}] 分析+执行 (fast)..." -f $round, $effectiveMaxRounds) -ForegroundColor Yellow

        $roundParseInfo = Get-ScriptParseInfo -ScriptText $currentText
        if (-not $roundParseInfo.IsValid) {
            $currentText = Get-BestEffortParseFallbackScriptText -ScriptText $currentText -ParseError $roundParseInfo.FirstError
            $finalRound = $round
            $terminatedBy = 'parse_failure'
            break
        }

        $roundGate = Get-PreExecutionGateDecision -Scope 'Round' -ScriptText $currentText -ParseInfo $roundParseInfo -Mode $PreExecutionGateMode -SafeMode:$SafeMode -Cache $preExecutionGateCache
        $effectiveRoundLimits = Get-EffectiveRoundExecutionLimits -BaseDynamicTimeBudgetMs $DynamicTimeBudgetMs -BaseMaxIterations $MaxIterations -BaseMaxTotalNodes $MaxTotalNodes -GateDecision $roundGate
        $roundExecutionPlan = Get-OptimizationProfileRoundPlan -ProfileSettings $profileSettings -GateDecision $roundGate -RemainingGlobalBudgetMs $remainingGlobalBudgetMs -Round $round -IsMaterializedPayloadRound:$currentRoundIsMaterializedPayload
        if ($roundExecutionPlan.RoundMode -ne 'default' -or $roundExecutionPlan.StopAfterThisRound) {
            $profileChangedExecutionPlan = $true
        }
        if ($roundExecutionPlan.DynamicTimeBudgetMs -gt 0) {
            $effectiveRoundLimits.DynamicTimeBudgetMs = if ($effectiveRoundLimits.DynamicTimeBudgetMs -le 0) { [int]$roundExecutionPlan.DynamicTimeBudgetMs } else { [Math]::Min([int]$effectiveRoundLimits.DynamicTimeBudgetMs, [int]$roundExecutionPlan.DynamicTimeBudgetMs) }
        }
        if ($roundExecutionPlan.MaxIterations -gt 0) {
            $effectiveRoundLimits.MaxIterations = [Math]::Min([int]$effectiveRoundLimits.MaxIterations, [int]$roundExecutionPlan.MaxIterations)
        }
        if ($roundExecutionPlan.MaxTotalNodes -gt 0) {
            $effectiveRoundLimits.MaxTotalNodes = [Math]::Min([int]$effectiveRoundLimits.MaxTotalNodes, [int]$roundExecutionPlan.MaxTotalNodes)
        }
        if ([string]$roundGate.Decision -eq 'Stop') {
            $stoppedText = Invoke-PostProcessDeobfuscatedScriptText -ScriptText $currentText -PreExecutionGateMode $PreExecutionGateMode -SafeMode:$SafeMode -PreExecutionGateCache $preExecutionGateCache
            $stoppedText = if ($stoppedText -is [System.Array]) { ($stoppedText -join "`r`n") } else { [string]$stoppedText }
            $safeExtraction = Try-Resolve-GatedRoundSafePayloadInfo -ScriptText $stoppedText -OriginalText $currentText -PreExecutionGateCache $preExecutionGateCache
            if ($safeExtraction -and -not [string]::IsNullOrWhiteSpace([string]$safeExtraction.PayloadText)) {
                $currentText = [string]$safeExtraction.PayloadText
                $currentRoundIsMaterializedPayload = $true
                $finalRound = $round
                continue
            }

            $currentText = $stoppedText
            $finalRound = $round
            $terminatedBy = 'pre_execution_gate'
            break
        }

        $preTraversalCheck = Get-PreTraversalStopCheckInfo -ScriptText $currentText -IsMaterializedPayloadRound:$currentRoundIsMaterializedPayload
        if ($preTraversalCheck.ShouldCheck) {
            $roundStop = Test-DynamicPayloadShouldStopRecursing -ScriptText $preTraversalCheck.CheckText -SafeMode:$SafeMode -GateMode $PreExecutionGateMode -GateScope 'WholeScriptHelper' -GateCache $preExecutionGateCache
        } else {
            $roundStop = $null
        }

        if ($roundStop -and $roundStop.ShouldStop) {
            $finalRound = $round
            $terminatedBy = 'pre_traversal_stop'
            break
        }

        $ctx = $null
        if (-not $roundExecutionPlan.SkipCfgTraversal) {
            $cfg = $null
            $cfgError = $null
            try {
                $cfg = New-CfgFromText -ScriptText $currentText
            } catch {
                $cfgError = Get-ErrorSummaryText -ErrorObject $_ -DefaultMessage 'CFG generation failed'
            }
            if (-not $cfg) {
                if (-not $roundParseInfo.IsValid) {
                    $currentText = Get-BestEffortParseFallbackScriptText -ScriptText $currentText -ParseError 'CFG generation failed'
                }
                $finalRound = $round
                $terminatedBy = 'cfg_generation_failed'
                break
            }

            try {
                $ctx = Invoke-CFGTraversal -CFG $cfg -LogPath $null -MaxIterations $effectiveRoundLimits.MaxIterations -MaxTotalNodes $effectiveRoundLimits.MaxTotalNodes -GlobalTimeBudgetMs $remainingGlobalBudgetMs -DynamicTimeBudgetMs $effectiveRoundLimits.DynamicTimeBudgetMs -SafeMode:$SafeMode
            } catch {
                $ctx = $null
            }
            if ($null -eq $ctx) {
                $finalRound = $round
                $terminatedBy = 'cfg_traversal_failed'
                break
            }
            $ctx.PreExecutionGateMode = $PreExecutionGateMode
            $ctx.PreExecutionGateCache = $preExecutionGateCache
            $ctx.DynamicDepthLimit = $effectiveRoundLimits.DynamicDepthLimit
        }

        $scriptText = $currentText
    }

    $roundBaselineSyntax = Test-PowerShellSyntax -ScriptText $scriptText
    $earlyPostProcessedText = Invoke-PostProcessDeobfuscatedScriptText -ScriptText $scriptText -PreExecutionGateMode $PreExecutionGateMode -SafeMode:$SafeMode -PreExecutionGateCache $preExecutionGateCache
    $earlyPostProcessChanged = ((Get-NormalizedScriptComparisonText -ScriptText $earlyPostProcessedText) -ne (Get-NormalizedScriptComparisonText -ScriptText $scriptText))
    $skipNextRoundPayloadProbe = $false
    if ($roundExecutionPlan) {
        if (Test-IsTimeoutCoverageOptimizationProfile) {
            $skipNextRoundPayloadProbe = ([bool]$roundExecutionPlan.StopAfterThisRound -or [bool]$roundExecutionPlan.SkipCfgTraversal)
        } elseif (Test-IsAdaptiveCoverageOptimizationProfile) {
            $skipNextRoundPayloadProbe = [bool]$roundExecutionPlan.StopAfterThisRound
        }
    }

    $hasCfgReplacementEvidence = ($null -ne $ctx -and (
            ($ctx.ContainsKey('DynamicInvokeResults') -and $ctx.DynamicInvokeResults -and $ctx.DynamicInvokeResults.Count -gt 0) -or
            ($ctx.ContainsKey('CanonicalCommandInvocationResults') -and $ctx.CanonicalCommandInvocationResults -and $ctx.CanonicalCommandInvocationResults.Count -gt 0) -or
            ($ctx.ContainsKey('CommandTargetAssignmentResults') -and $ctx.CommandTargetAssignmentResults -and $ctx.CommandTargetAssignmentResults.Count -gt 0) -or
        ($ctx.ContainsKey('FunctionInvokeResults') -and $ctx.FunctionInvokeResults -and $ctx.FunctionInvokeResults.Count -gt 0) -or
        ($ctx.ContainsKey('FunctionCallInstances') -and $ctx.FunctionCallInstances -and $ctx.FunctionCallInstances.Count -gt 0) -or
        ($ctx.ContainsKey('ScriptBlockInvocationResults') -and $ctx.ScriptBlockInvocationResults -and $ctx.ScriptBlockInvocationResults.Count -gt 0) -or
        ($ctx.ContainsKey('ScriptBlockCallInstances') -and $ctx.ScriptBlockCallInstances -and $ctx.ScriptBlockCallInstances.Count -gt 0)
        ))

    if ($earlyPostProcessChanged -and -not $hasCfgReplacementEvidence) {
        $candidates = @()
        $skipped = @()
        $selected = @()
        $newText = $earlyPostProcessedText
        $postProcessChanged = $true
        if ($skipNextRoundPayloadProbe) {
            $nextRoundMaterializedPayload = [PSCustomObject]@{
                IsMaterializedPayload = $false
                Reason                = if ($roundExecutionPlan -and -not [string]::IsNullOrWhiteSpace([string]$roundExecutionPlan.Reason)) { [string]$roundExecutionPlan.Reason } else { 'timeout_profile_skip_next_round_probe' }
                FromDynamicInvoke     = $false
                FromHostWrapperDecode = $false
            }
        } else {
            $nextRoundMaterializedPayload = Get-NextRoundMaterializedPayloadInfo -Selected $selected -PrePostProcessText $newText
        }

        if ((-not $skipNextRoundPayloadProbe) -and (-not [bool]$nextRoundMaterializedPayload.IsMaterializedPayload)) {
            $prePostProcessPayload = Resolve-WholeScriptHostPayloadInfo -ScriptText $scriptText
            if (-not $prePostProcessPayload) {
                $prePostProcessPayload = Try-Resolve-WholeScriptStaticCompressedLoaderPayloadInfo -ScriptText $scriptText
            }

            $resolvedEarlyPayloadText = if ($prePostProcessPayload) {
                Get-WholeScriptReplacementCandidateText -OriginalText $scriptText -CandidateText $prePostProcessPayload.PayloadText
            } else {
                $null
            }

            if ($resolvedEarlyPayloadText -or
                ($prePostProcessPayload -and $prePostProcessPayload.PSObject.Properties['PayloadText'] -and -not [string]::IsNullOrWhiteSpace([string]$prePostProcessPayload.PayloadText))) {
                $nextRoundMaterializedPayload = [PSCustomObject]@{
                    IsMaterializedPayload = $true
                    Reason                = if ($prePostProcessPayload.PSObject.Properties['DecodeSource'] -and -not [string]::IsNullOrWhiteSpace([string]$prePostProcessPayload.DecodeSource)) { [string]$prePostProcessPayload.DecodeSource } else { 'early_postprocess_materialized_payload' }
                    FromDynamicInvoke     = $false
                    FromHostWrapperDecode = $true
                }
            }
        }
    } elseif ($null -eq $ctx) {
        $candidates = @()
        $skipped = @()
        $selected = @()
        $newText = $scriptText
        $postProcessChanged = $false
        $nextRoundMaterializedPayload = [PSCustomObject]@{
            IsMaterializedPayload = $false
            Reason                = if ($roundExecutionPlan -and -not [string]::IsNullOrWhiteSpace([string]$roundExecutionPlan.Reason)) { [string]$roundExecutionPlan.Reason } else { 'profile_text_only' }
            FromDynamicInvoke     = $false
            FromHostWrapperDecode = $false
        }
    } else {
        $base = Get-ReplacementsFromResolvableResults -Context $ctx -ScriptText $scriptText -VariableConflictPolicy $effectiveVariableConflictPolicy
        $dynamic = Get-DynamicInvokeReplacementCandidates -Context $ctx -ScriptText $scriptText -DynamicConflictPolicy $effectiveDynamicConflictPolicy
        $canonicalCommand = Get-CanonicalCommandInvocationReplacementCandidates -Context $ctx -ScriptText $scriptText
        $commandTargetAssignments = Get-CommandTargetAssignmentReplacementCandidates -Context $ctx -ScriptText $scriptText
        $functionResults = Get-FunctionInvokeReplacementCandidates -Context $ctx -ScriptText $scriptText
        $scriptBlockTargets = Get-ScriptBlockTargetInlineReplacementCandidates -Context $ctx -ScriptText $scriptText
        $scriptBlockInvocations = Get-ScriptBlockInvocationReplacementCandidates -Context $ctx -ScriptText $scriptText
        if (($roundGate -and [bool]$roundGate.SkipWholeScriptDynamic) -or ($roundExecutionPlan -and [bool]$roundExecutionPlan.SkipWholeScriptDynamic)) {
            $wholeScriptDynamic = [PSCustomObject]@{
                Candidates = @()
                Skipped    = @(New-SkipRecord -Reason 'whole_script_dynamic_pre_execution_gate' -Message '本轮命中 shallow gate，跳过 whole-script dynamic loader 展开。' -Item $null)
            }
        } else {
            $wholeScriptDynamic = Get-WholeScriptDynamicLoaderReplacementCandidates -Context $ctx -ScriptText $scriptText
        }
        $literalized = Get-LiteralizedCommandReplacementCandidates -Context $ctx -ScriptText $scriptText
        $sensitive = Get-SensitiveSinkReplacementCandidates -Context $ctx -ScriptText $scriptText
        $mandatoryBase64 = Get-MandatoryBase64ReplacementCandidates -Context $ctx -ScriptText $scriptText
        $remainingStaticBudgetMs = Get-RemainingTimeBudgetMs -BudgetMs $GlobalTimeBudgetMs -Stopwatch $globalStopwatch
        if ([int]$profileSettings.StaticBudgetCapMs -gt 0 -and $remainingStaticBudgetMs -gt 0) {
            $remainingStaticBudgetMs = [Math]::Min([int]$remainingStaticBudgetMs, [int]$profileSettings.StaticBudgetCapMs)
        }
        if (($roundGate -and [bool]$roundGate.SkipStaticEval) -or ($roundExecutionPlan -and [bool]$roundExecutionPlan.SkipStaticEval)) {
            $static = [PSCustomObject]@{
                Candidates = @()
                Skipped    = @(New-SkipRecord -Reason 'static_pre_execution_gate' -Message '本轮命中 shallow gate，跳过静态求值。' -Item $null)
            }
        } elseif ($GlobalTimeBudgetMs -gt 0 -and $remainingStaticBudgetMs -le 0) {
            $static = [PSCustomObject]@{
                Candidates = @()
                Skipped    = @(New-SkipRecord -Reason 'static_budget_exceeded' -Message '进入静态候选阶段时全局预算已耗尽，跳过静态求值。' -Item $null)
            }
        } else {
            $static = Get-StaticReplacementCandidates -Context $ctx -ScriptText $scriptText -TimeBudgetMs $remainingStaticBudgetMs -PreExecutionGateMode $PreExecutionGateMode -PreExecutionGateCache $preExecutionGateCache -SafeMode:$SafeMode
        }
        $preSpecializedCandidates = @($dynamic.Candidates) + @($canonicalCommand.Candidates) + @($commandTargetAssignments.Candidates) + @($functionResults.Candidates) + @($scriptBlockTargets.Candidates) + @($scriptBlockInvocations.Candidates) + @($wholeScriptDynamic.Candidates) + @($sensitive.Candidates) + @($literalized.Candidates) + @($mandatoryBase64.Candidates) + @($base.Candidates) + @($static.Candidates)
        $functionSpecialized = Get-FunctionSpecializedInlineReplacementCandidates -Context $ctx -ScriptText $scriptText -BaseCandidates $preSpecializedCandidates
        $scriptBlockSpecialized = Get-ScriptBlockSpecializedInlineReplacementCandidates -Context $ctx -ScriptText $scriptText -BaseCandidates $preSpecializedCandidates -TargetCandidates @($scriptBlockTargets.Candidates)
        $merged = Merge-ReplacementCandidatesByRange -Candidates (@($preSpecializedCandidates) + @($functionSpecialized.Candidates) + @($scriptBlockSpecialized.Candidates))
        $scriptBlockInvocationFiltered = Filter-ScriptBlockInvocationCandidatesForUpdatedBlocks -Candidates @($merged.Candidates)
        $contextFiltered = Filter-ReplacementCandidatesByContext -Candidates @($scriptBlockInvocationFiltered.Candidates) -Context $ctx -ScriptText $scriptText
        $preferred = Filter-CandidatesPreferDynamicInvoke -Candidates @($contextFiltered.Candidates)

        $candidates = @($preferred.Candidates)
        $skipped = @($dynamic.Skipped) + @($canonicalCommand.Skipped) + @($commandTargetAssignments.Skipped) + @($functionResults.Skipped) + @($scriptBlockTargets.Skipped) + @($scriptBlockInvocations.Skipped) + @($functionSpecialized.Skipped) + @($scriptBlockSpecialized.Skipped) + @($wholeScriptDynamic.Skipped) + @($sensitive.Skipped) + @($literalized.Skipped) + @($mandatoryBase64.Skipped) + @($base.Skipped) + @($static.Skipped) + @($merged.Skipped) + @($scriptBlockInvocationFiltered.Skipped) + @($contextFiltered.Skipped) + @($preferred.Skipped)

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

        $sel = Select-NonOverlappingReplacements -Candidates $autoCandidates -Strategy $effectiveOverlapStrategy
        $selected = @($sel.Selected)
        $skipped += @($sel.Skipped)

        $syntaxGuard = Ensure-SyntaxSafeReplacements -ScriptText $scriptText -Selected $selected
        $selected = @($syntaxGuard.Selected)
        $skipped += @($syntaxGuard.Skipped)

        $newText = Apply-ReplacementsToText -Text $scriptText -Replacements $selected
        $postProcessedText = Invoke-PostProcessDeobfuscatedScriptText -ScriptText $newText -PreExecutionGateMode $PreExecutionGateMode -SafeMode:$SafeMode -PreExecutionGateCache $preExecutionGateCache
        $postProcessChanged = ((Get-NormalizedScriptComparisonText -ScriptText $postProcessedText) -ne (Get-NormalizedScriptComparisonText -ScriptText $newText))
        if ($postProcessChanged) {
            $newText = $postProcessedText
        }
        if ($skipNextRoundPayloadProbe) {
            $nextRoundMaterializedPayload = [PSCustomObject]@{
                IsMaterializedPayload = $false
                Reason                = if ($roundExecutionPlan -and -not [string]::IsNullOrWhiteSpace([string]$roundExecutionPlan.Reason)) { [string]$roundExecutionPlan.Reason } else { 'timeout_profile_skip_next_round_probe' }
                FromDynamicInvoke     = $false
                FromHostWrapperDecode = $false
            }
        } else {
            $nextRoundMaterializedPayload = Get-NextRoundMaterializedPayloadInfo -Selected $selected -PrePostProcessText $newText
        }
    }

    if ($roundBaselineSyntax.IsValid) {
        $roundSyntax = Test-PowerShellSyntax -ScriptText $newText
        if (-not $roundSyntax.IsValid) {
            $skipped += New-SkipRecord -Reason 'round_syntax_guard_reverted' -Message ("替换后脚本不可解析，已回退到本轮输入。Error=" + $roundSyntax.FirstError) -Item $null
            $selected = @()
            $newText = $scriptText
            $postProcessChanged = $false
            $nextRoundMaterializedPayload = [PSCustomObject]@{
                IsMaterializedPayload = $false
                Reason                = 'syntax_guard_reverted'
                FromDynamicInvoke     = $false
                FromHostWrapperDecode = $false
            }
        }
    }

    $appliedCount = $selected.Count + $(if ($postProcessChanged) { 1 } else { 0 })

    if ($selected.Count -eq 0 -and -not $postProcessChanged) {
        $noReplacementReason = Get-NoReplacementTerminationReason -CandidateCount $candidates.Count -Skipped $skipped
        $noReplacementTerminatedBy = if (
            ((Test-IsTimeoutCoverageOptimizationProfile) -and $roundExecutionPlan -and ($roundExecutionPlan.StopAfterThisRound -or $roundExecutionPlan.SkipCfgTraversal)) -or
            ((Test-IsAdaptiveCoverageOptimizationProfile) -and $roundExecutionPlan -and [bool]$roundExecutionPlan.StopAfterThisRound)
        ) {
            'stable_output'
        } else {
            'no_replacements'
        }
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
                GateMode        = $PreExecutionGateMode
                GateDecision    = if ($roundGate) { $roundGate.Decision } else { $null }
                GateScore       = if ($roundGate) { $roundGate.Score } else { $null }
                GateReasons     = if ($roundGate) { @($roundGate.Reasons) } else { @() }
                TerminatedBy    = $noReplacementTerminatedBy
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

            if (-not $finalRoundOutPath) {
                $finalRoundOutPath = $currentPath
            }
        } else {
            $currentText = $scriptText
        }

        $finalRound = $round
        $terminatedBy = $noReplacementTerminatedBy
        if ($terminatedBy -eq 'stable_output') {
            $completionKind = 'budget_partial'
        }
        break
    }

    if ($FullOutput) {
        $appliedNodeIds = @()
        foreach ($a in $selected) {
            if ($null -eq $a -or $null -eq $a.NodeId) { continue }
            if ("$($a.NodeId)" -match '^\d+$') {
                $appliedNodeIds += [int]$a.NodeId
            }
        }
        $appliedNodeIds = @($appliedNodeIds | Sort-Object -Unique)

        if ($null -ne $cfg) {
            try {
                Export-CfgToDot -finalCFG $cfg -outputPath $roundCfgDotPath -AppliedNodeIds $appliedNodeIds | Out-Null
            } catch {
                Write-Warning "导出 CFG 失败: $_"
            }
        }

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
        $mandatoryBase64Count = @($candidates | Where-Object { $_.SourceKind -eq 'MandatoryBase64' }).Count
        $dynamicCount = @($candidates | Where-Object { $_.SourceKind -eq 'DynamicInvoke' }).Count
        $literalizedCount = @($candidates | Where-Object { $_.SourceKind -eq 'LiteralizedCommand' }).Count
        $otherExecutedCount = @($candidates | Where-Object { $_.SourceKind -notin @('Static', 'DynamicInvoke', 'LiteralizedCommand', 'MandatoryBase64') }).Count

        $report = [ordered]@{
            Round           = $round
            RoundLabel      = $roundLabel
            InputPath       = $roundInPath
            OutputPath      = $roundOutPath
            ExecutionLog    = $roundLogPath
            CfgDotPath      = $roundCfgDotPath
            CfgPngPath      = $roundCfgPngPath
            HostInfo        = if ($ctx -and $ctx.PSObject.Properties['HostInfo']) { $ctx.HostInfo } else { $null }
            SafeMode        = $SafeMode
            GateMode        = $PreExecutionGateMode
            GateDecision    = if ($roundGate) { $roundGate.Decision } else { $null }
            GateScore       = if ($roundGate) { $roundGate.Score } else { $null }
            GateReasons     = if ($roundGate) { @($roundGate.Reasons) } else { @() }
            OverlapStrategy = $effectiveOverlapStrategy
            VariableConflictPolicy = $effectiveVariableConflictPolicy
            DynamicConflictPolicy = $effectiveDynamicConflictPolicy
            MaxIterations   = $effectiveRoundLimits.MaxIterations
            MaxTotalNodes   = $effectiveRoundLimits.MaxTotalNodes
            GlobalTimeBudgetMs = $GlobalTimeBudgetMs
            DynamicTimeBudgetMs = $effectiveRoundLimits.DynamicTimeBudgetMs
            ExecutionStopReason = if ($ctx -and $ctx.ContainsKey('StopReason')) { $ctx.StopReason } else { $null }
            InputIsMaterializedPayloadRound = $currentRoundIsMaterializedPayload
            PreTraversalCheckApplied = [bool]$preTraversalCheck.ShouldCheck
            PreTraversalCheckReason = $preTraversalCheck.Reason
            ProfileRoundMode = if ($roundExecutionPlan) { $roundExecutionPlan.RoundMode } else { 'default' }
            ProfileRoundReason = if ($roundExecutionPlan) { $roundExecutionPlan.Reason } else { $null }
            RemainingGlobalBudgetBeforeStatic = $remainingStaticBudgetMs
            StaticSkippedByBudget = ($null -ne $remainingStaticBudgetMs -and $GlobalTimeBudgetMs -gt 0 -and $remainingStaticBudgetMs -le 0)
            CandidateCount  = $candidates.Count
            DynamicCount    = $dynamicCount
            LiteralizedCommandCount = $literalizedCount
            MandatoryBase64Count = $mandatoryBase64Count
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

        Write-TextFileAtomic -Path $roundOutPath -Content $newText
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

    if (((Test-IsTimeoutCoverageOptimizationProfile) -or (Test-IsAdaptiveCoverageOptimizationProfile)) -and $roundExecutionPlan -and [bool]$roundExecutionPlan.StopAfterThisRound) {
        $terminatedBy = 'stable_output'
        if (Test-IsTimeoutCoverageOptimizationProfile) {
            $completionKind = 'budget_partial'
        }
        break
    }

    if (($GlobalTimeBudgetMs -gt 0 -and $globalStopwatch.ElapsedMilliseconds -ge $GlobalTimeBudgetMs) -or ($ctx -and $ctx.ContainsKey('StopReason') -and [string]$ctx.StopReason -eq 'GlobalTimeBudgetExceeded')) {
        $terminatedBy = 'global_time_budget'
        if (Test-IsTimeoutCoverageOptimizationProfile) {
            $completionKind = 'budget_partial'
        }
        break
    }

    if ($FullOutput) {
        $currentPath = $finalRoundOutPath
    } else {
        $currentPath = $scriptFullPath
    }
}

if ($FullOutput -and -not $finalRoundOutPath) {
    foreach ($candidatePath in @($lastValidRoundOutPath, $currentPath, $scriptFullPath)) {
        if (-not [string]::IsNullOrWhiteSpace($candidatePath) -and (Test-Path -LiteralPath $candidatePath)) {
            $finalRoundOutPath = $candidatePath
            break
        }
    }
}

if ($null -eq $terminatedBy) {
    $terminatedBy = 'max_rounds'
}

if ((Test-IsTimeoutCoverageOptimizationProfile) -and $completionKind -ne 'budget_partial') {
    if ($profileChangedExecutionPlan -or $terminatedBy -in @('global_time_budget', 'stable_output') -or $effectiveMaxRounds -lt $MaxRounds) {
        $completionKind = 'budget_partial'
    }
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
    if ($FullOutput) {
        foreach ($candidatePath in @($finalRoundOutPath, $lastValidRoundOutPath, $currentPath, $scriptFullPath)) {
            if ([string]::IsNullOrWhiteSpace($candidatePath) -or -not (Test-Path -LiteralPath $candidatePath)) {
                continue
            }

            $candidateInfo = Test-FileSyntaxInfo -Path $candidatePath
            if (-not $candidateInfo.Exists) {
                continue
            }

            $finalOutputPathToCopy = $candidatePath
            $finalOutputText = $candidateInfo.Text
            $finalOutputSource = 'best_effort_invalid'
            $finalSyntaxFallbackUsed = $true
            break
        }
    } else {
        $bestEffortInputText = Get-FullScriptTextFromFile -Path $scriptFullPath
        foreach ($candidateText in @($currentText, $lastValidText, $bestEffortInputText)) {
            if ($null -eq $candidateText) {
                continue
            }

            $candidateString = [string]$candidateText
            if ([string]::IsNullOrWhiteSpace($candidateString)) {
                continue
            }

            $finalOutputText = $candidateString
            $finalOutputSource = 'best_effort_invalid'
            $finalSyntaxFallbackUsed = $true
            break
        }
    }
}

if ($FullOutput -and [string]::IsNullOrWhiteSpace($finalOutputPathToCopy)) {
    throw '最终输出文件未生成。'
}

if (-not $FullOutput -and $null -eq $finalOutputText) {
    throw '最终输出文本未生成。'
}

if (-not $DryRun) {
    $outDir = [System.IO.Path]::GetDirectoryName($OutPath)
    if (-not [string]::IsNullOrWhiteSpace($outDir) -and -not (Test-Path -LiteralPath $outDir)) {
        $null = New-Item -ItemType Directory -Path $outDir -Force
    }

    if ($FullOutput) {
        if ($null -eq $finalOutputText -and -not [string]::IsNullOrWhiteSpace($finalOutputPathToCopy)) {
            $finalOutputText = Get-RawScriptTextFromFile -Path $finalOutputPathToCopy
        }
        $finalOutputText = Remove-SensitiveEvidenceCommentBlock -ScriptText $finalOutputText
        Write-TextFileAtomic -Path $OutPath -Content $finalOutputText
    } else {
        $finalOutputText = Remove-SensitiveEvidenceCommentBlock -ScriptText $finalOutputText
        Write-TextFileAtomic -Path $OutPath -Content $finalOutputText
    }
}

if (-not [string]::IsNullOrWhiteSpace($RunMetadataPath)) {
    $runMetadataDir = [System.IO.Path]::GetDirectoryName($RunMetadataPath)
    if (-not [string]::IsNullOrWhiteSpace($runMetadataDir) -and -not (Test-Path -LiteralPath $runMetadataDir)) {
        $null = New-Item -ItemType Directory -Path $runMetadataDir -Force
    }

    $runMetadata = [ordered]@{
        Profile                 = $OptimizationProfile
        CompletionKind          = $completionKind
        TerminatedBy            = $terminatedBy
        FinalOutputSource       = $finalOutputSource
        FinalSyntaxValid        = $finalSyntaxValid
        FinalSyntaxFallbackUsed = $finalSyntaxFallbackUsed
        FinalRound              = $finalRound
        RequestedMaxRounds      = $MaxRounds
        EffectiveMaxRounds      = $effectiveMaxRounds
        GlobalTimeBudgetMs      = $GlobalTimeBudgetMs
        DynamicTimeBudgetMs     = $DynamicTimeBudgetMs
        FinalizationReserveMs   = $profileSettings.FinalizationReserveMs
        ProfileChangedExecutionPlan = $profileChangedExecutionPlan
        Timestamp               = (Get-Date).ToString('o')
    }
    Write-JsonFile -Path $RunMetadataPath -Object $runMetadata
}

Write-Host "=== 完成 ===" -ForegroundColor Green
Write-Host ("TerminatedBy : {0}" -f $terminatedBy) -ForegroundColor Gray
Write-Host ("Completion   : {0}" -f $completionKind) -ForegroundColor Gray
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
