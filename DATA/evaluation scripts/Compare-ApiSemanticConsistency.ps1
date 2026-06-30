<#
Offline comparison of API-level semantic consistency based on previously
collected result files.

Design goals:
1. Reuse existing `effectiveApiSequence` fields without rerunning samples.
2. Compare a baseline result set and a candidate result set on shared samples.
3. Optionally restrict evaluation to inventory-marked valid samples.
4. Optionally require both API sequences to be non-empty to avoid empty-match
   inflation.

Example:
.\Compare-ApiSemanticConsistency.ps1 `
  -BaselinePath .\baseline-results `
  -CandidatePath .\candidate-results `
  -InventoryPath .\candidate-inventory.csv `
  -RequireBothNonEmpty `
  -OutputPath .\api-semantic-consistency
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][Alias('bp')][string]$BaselinePath,
    [Parameter(Mandatory = $true)][Alias('cp')][string]$CandidatePath,
    [Parameter(Mandatory = $true)][Alias('op')][string]$OutputPath,
    [string]$InventoryPath,
    [string]$ValidResultValue = 'valid',
    [string]$BaselineLabel = 'Baseline',
    [string]$CandidateLabel = 'Candidate',
    [switch]$RequireBothNonEmpty,
    [switch]$SummaryOnly,
    [switch]$IncludeSequences
)

$ErrorActionPreference = 'Stop'

function Resolve-ResultPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $resolved = Resolve-Path -LiteralPath $Path
    $item = Get-Item -LiteralPath $resolved.Path
    if ($item -is [System.IO.DirectoryInfo]) {
        $jsonlPath = Join-Path $item.FullName 'results.jsonl'
        if (Test-Path -LiteralPath $jsonlPath) {
            return $jsonlPath
        }

        $jsonPath = Join-Path $item.FullName 'results.json'
        if (Test-Path -LiteralPath $jsonPath) {
            return $jsonPath
        }

        throw "results.jsonl/results.json not found under directory: $($item.FullName)"
    }

    return $item.FullName
}

function Resolve-OptionalPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }

    return (Resolve-Path -LiteralPath $Path).Path
}

function Ensure-Directory {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Get-SampleStem {
    param([Parameter(Mandatory = $true)][string]$Name)

    foreach ($suffix in @('.deob.ps1', '.rebuilt.ps1', '.ps1')) {
        if ($Name.EndsWith($suffix, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $Name.Substring(0, $Name.Length - $suffix.Length)
        }
    }

    return [System.IO.Path]::GetFileNameWithoutExtension($Name)
}

function Convert-ToCleanSequence {
    param([object[]]$Sequence)

    return @(
        foreach ($item in @($Sequence)) {
            if ($null -eq $item) { continue }
            $text = [string]$item
            if ([string]::IsNullOrWhiteSpace($text)) { continue }
            $text
        }
    )
}

function Get-EffectiveApiSequence {
    param([Parameter(Mandatory = $true)][object]$Result)

    $effectiveApiSequence = if ($null -ne $Result.effectiveApiSequence) {
        Convert-ToCleanSequence -Sequence @($Result.effectiveApiSequence)
    } else {
        @()
    }

    if ($effectiveApiSequence.Count -gt 0) {
        return [string[]]@($effectiveApiSequence)
    }

    $apiSequence = if ($null -ne $Result.apiSequence) {
        Convert-ToCleanSequence -Sequence @($Result.apiSequence)
    } else {
        @()
    }

    $missingImportantStubbedSequence = if ($null -ne $Result.missingImportantStubbedSequence) {
        Convert-ToCleanSequence -Sequence @($Result.missingImportantStubbedSequence)
    } else {
        @()
    }

    $combinedSequence = @(@($apiSequence) + @($missingImportantStubbedSequence))
    return [string[]]@(Convert-ToCleanSequence -Sequence $combinedSequence)
}

function Read-ResultObjects {
    param([Parameter(Mandatory = $true)][string]$ResolvedPath)

    $extension = [System.IO.Path]::GetExtension($ResolvedPath)
    if ([string]::Equals($extension, '.jsonl', [System.StringComparison]::OrdinalIgnoreCase)) {
        foreach ($line in Get-Content -LiteralPath $ResolvedPath) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $line | ConvertFrom-Json
        }
        return
    }

    foreach ($row in @(Get-Content -LiteralPath $ResolvedPath -Raw | ConvertFrom-Json)) {
        if ($null -eq $row) { continue }
        $row
    }
}

function Get-ResultMap {
    param([Parameter(Mandatory = $true)][string]$Path)

    $resolvedPath = Resolve-ResultPath -Path $Path
    $map = @{}

    foreach ($row in @(Read-ResultObjects -ResolvedPath $resolvedPath)) {
        if ($null -eq $row) { continue }

        $sampleId = if ($row.sampleId) { [string]$row.sampleId } else { Get-SampleStem -Name ([string]$row.file) }
        if ([string]::IsNullOrWhiteSpace($sampleId)) { continue }

        $sequence = Get-EffectiveApiSequence -Result $row
        $map[$sampleId] = [pscustomobject]@{
            sampleId = $sampleId
            file = [string]$row.file
            apiSequence = [string[]]@($sequence)
            apiCount = @($sequence).Count
        }
    }

    return @{
        path = $resolvedPath
        map = $map
    }
}

function Get-ValidSampleSet {
    param([string]$InventoryPath, [string]$ResultValue)

    if ([string]::IsNullOrWhiteSpace($InventoryPath)) {
        return $null
    }

    $resolvedInventoryPath = Resolve-OptionalPath -Path $InventoryPath
    $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($row in @(Import-Csv -LiteralPath $resolvedInventoryPath)) {
        if ($null -eq $row) { continue }
        if ([string]::IsNullOrWhiteSpace([string]$row.Name)) { continue }
        if (-not [string]::Equals([string]$row.Result, $ResultValue, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        $set.Add([string]$row.Name) | Out-Null
    }

    return @{
        path = $resolvedInventoryPath
        set = $set
    }
}

function Test-SequenceEqual {
    param([object[]]$Left, [object[]]$Right)

    $leftItems = @($Left)
    $rightItems = @($Right)
    if ($leftItems.Count -ne $rightItems.Count) { return $false }

    for ($i = 0; $i -lt $leftItems.Count; $i++) {
        if (-not [string]::Equals([string]$leftItems[$i], [string]$rightItems[$i], [System.StringComparison]::Ordinal)) {
            return $false
        }
    }

    return $true
}

function Get-LcsLength {
    param([object[]]$Left, [object[]]$Right)

    $leftItems = @($Left)
    $rightItems = @($Right)
    $m = $leftItems.Count
    $n = $rightItems.Count
    if ($m -eq 0 -or $n -eq 0) { return 0 }

    $prev = [int[]]::new($n + 1)
    $curr = [int[]]::new($n + 1)

    for ($i = 1; $i -le $m; $i++) {
        for ($j = 1; $j -le $n; $j++) {
            if ([string]::Equals([string]$leftItems[$i - 1], [string]$rightItems[$j - 1], [System.StringComparison]::Ordinal)) {
                $curr[$j] = $prev[$j - 1] + 1
            } else {
                $curr[$j] = [Math]::Max($prev[$j], $curr[$j - 1])
            }
        }

        $tmp = $prev
        $prev = $curr
        $curr = $tmp
        [System.Array]::Clear($curr, 0, $curr.Length)
    }

    return $prev[$n]
}

function Get-OrderedSemanticMetrics {
    param(
        [object[]]$BaselineSequence,
        [object[]]$CandidateSequence,
        [bool]$ExactMatch = $false
    )

    $baselineCount = @($BaselineSequence).Count
    $candidateCount = @($CandidateSequence).Count

    if ($baselineCount -eq 0 -and $candidateCount -eq 0) {
        return [pscustomobject]@{
            lcsLength = 0
            orderedPrecision = 1.0
            orderedRecall = 1.0
            orderedF1 = 1.0
        }
    }

    if ($ExactMatch) {
        return [pscustomobject]@{
            lcsLength = $baselineCount
            orderedPrecision = 1.0
            orderedRecall = 1.0
            orderedF1 = 1.0
        }
    }

    if ($baselineCount -eq 0 -or $candidateCount -eq 0) {
        return [pscustomobject]@{
            lcsLength = 0
            orderedPrecision = 0.0
            orderedRecall = 0.0
            orderedF1 = 0.0
        }
    }

    $lcsLength = Get-LcsLength -Left $BaselineSequence -Right $CandidateSequence

    $precision = if ($candidateCount -gt 0) { [double]$lcsLength / [double]$candidateCount } else { 0.0 }
    $recall = if ($baselineCount -gt 0) { [double]$lcsLength / [double]$baselineCount } else { 0.0 }
    $f1 = if (($precision + $recall) -gt 0) { 2.0 * $precision * $recall / ($precision + $recall) } else { 0.0 }

    return [pscustomobject]@{
        lcsLength = $lcsLength
        orderedPrecision = $precision
        orderedRecall = $recall
        orderedF1 = $f1
    }
}

function Format-Percent {
    param([double]$Value)
    return ('{0:N2}%' -f $Value)
}

$baselineData = Get-ResultMap -Path $BaselinePath
$candidateData = Get-ResultMap -Path $CandidatePath
$validData = Get-ValidSampleSet -InventoryPath $InventoryPath -ResultValue $ValidResultValue

$outputDirectory = [System.IO.Path]::GetFullPath($OutputPath)
Ensure-Directory -Path $outputDirectory

$sharedIds = @($baselineData.map.Keys | Where-Object { $candidateData.map.ContainsKey($_) } | Sort-Object)
$pairRows = [System.Collections.Generic.List[object]]::new()
$filterDescriptions = [System.Collections.Generic.List[string]]::new()
if ($null -ne $validData) {
    $filterDescriptions.Add("inventory result == '$ValidResultValue'") | Out-Null
}
if ($RequireBothNonEmpty) {
    $filterDescriptions.Add('both API sequences non-empty') | Out-Null
}
if ($filterDescriptions.Count -eq 0) {
    $filterDescriptions.Add('shared sample ids only') | Out-Null
}

$filteredShared = 0
$inventoryExcluded = 0
$emptyExcluded = 0

$exactMatchCount = 0
$sumOrderedPrecision = 0.0
$sumOrderedRecall = 0.0
$sumOrderedF1 = 0.0
$baselineTotalApiCount = 0
$candidateTotalApiCount = 0
$candidateLonger = 0
$candidateShorter = 0
$sameLength = 0

foreach ($sampleId in @($sharedIds)) {
    if ($null -ne $validData -and -not $validData.set.Contains($sampleId)) {
        $inventoryExcluded++
        continue
    }

    $baseline = $baselineData.map[$sampleId]
    $candidate = $candidateData.map[$sampleId]
    $baselineCount = [int]$baseline.apiCount
    $candidateCount = [int]$candidate.apiCount

    if ($RequireBothNonEmpty -and ($baselineCount -le 0 -or $candidateCount -le 0)) {
        $emptyExcluded++
        continue
    }

    $filteredShared++
    $exactMatch = Test-SequenceEqual -Left $baseline.apiSequence -Right $candidate.apiSequence
    if ($exactMatch) { $exactMatchCount++ }

    $orderedMetrics = Get-OrderedSemanticMetrics -BaselineSequence $baseline.apiSequence -CandidateSequence $candidate.apiSequence -ExactMatch $exactMatch
    $sumOrderedPrecision += [double]$orderedMetrics.orderedPrecision
    $sumOrderedRecall += [double]$orderedMetrics.orderedRecall
    $sumOrderedF1 += [double]$orderedMetrics.orderedF1
    $baselineTotalApiCount += $baselineCount
    $candidateTotalApiCount += $candidateCount

    $lengthRelation = 'equal'
    if ($candidateCount -gt $baselineCount) {
        $candidateLonger++
        $lengthRelation = 'candidate_longer'
    } elseif ($candidateCount -lt $baselineCount) {
        $candidateShorter++
        $lengthRelation = 'candidate_shorter'
    } else {
        $sameLength++
    }

    $row = [ordered]@{
        sampleId = $sampleId
        baselineFile = $baseline.file
        candidateFile = $candidate.file
        baselineApiCount = $baselineCount
        candidateApiCount = $candidateCount
        lengthRelation = $lengthRelation
        exactApiMatch = $exactMatch
        lcsLength = [int]$orderedMetrics.lcsLength
        orderedPrecision = [Math]::Round([double]$orderedMetrics.orderedPrecision, 6)
        orderedRecall = [Math]::Round([double]$orderedMetrics.orderedRecall, 6)
        orderedF1 = [Math]::Round([double]$orderedMetrics.orderedF1, 6)
    }

    if ($IncludeSequences) {
        $row.baselineApiSequence = [object[]]@($baseline.apiSequence)
        $row.candidateApiSequence = [object[]]@($candidate.apiSequence)
    }

    $pairRows.Add([pscustomobject]$row) | Out-Null
}

$summary = [ordered]@{
    baselinePath = $baselineData.path
    candidatePath = $candidateData.path
    inventoryPath = if ($null -ne $validData) { $validData.path } else { $null }
    baselineLabel = $BaselineLabel
    candidateLabel = $CandidateLabel
    validResultValue = if ($null -ne $validData) { $ValidResultValue } else { $null }
    requireBothNonEmpty = [bool]$RequireBothNonEmpty
    summaryOnly = [bool]$SummaryOnly
    includeSequences = [bool]$IncludeSequences
    filters = @($filterDescriptions)
    sharedSamples = $sharedIds.Count
    comparedSamples = $filteredShared
    excludedByInventory = $inventoryExcluded
    excludedByEmptySequence = $emptyExcluded
    exactApiMatchCount = $exactMatchCount
    exactApiMatchPct = if ($filteredShared -gt 0) { [Math]::Round((100.0 * $exactMatchCount / $filteredShared), 4) } else { 0.0 }
    averageOrderedPrecisionPct = if ($filteredShared -gt 0) { [Math]::Round((100.0 * $sumOrderedPrecision / $filteredShared), 4) } else { 0.0 }
    averageOrderedRecallPct = if ($filteredShared -gt 0) { [Math]::Round((100.0 * $sumOrderedRecall / $filteredShared), 4) } else { 0.0 }
    averageOrderedF1Pct = if ($filteredShared -gt 0) { [Math]::Round((100.0 * $sumOrderedF1 / $filteredShared), 4) } else { 0.0 }
    averageBaselineApiCount = if ($filteredShared -gt 0) { [Math]::Round(([double]$baselineTotalApiCount / [double]$filteredShared), 4) } else { 0.0 }
    averageCandidateApiCount = if ($filteredShared -gt 0) { [Math]::Round(([double]$candidateTotalApiCount / [double]$filteredShared), 4) } else { 0.0 }
    lengthRelations = [ordered]@{
        sameLength = $sameLength
        candidateLonger = $candidateLonger
        candidateShorter = $candidateShorter
    }
}

$comparisonJsonPath = Join-Path $outputDirectory 'comparison.json'
$comparisonJsonlPath = Join-Path $outputDirectory 'comparison.jsonl'
$summaryPath = Join-Path $outputDirectory 'summary.json'
$comparisonMdPath = Join-Path $outputDirectory 'comparison.md'

$comparisonJsonWritten = $false
$comparisonJsonlWritten = $false
if (-not $SummaryOnly) {
    $pairRows | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $comparisonJsonPath -Encoding UTF8
    $comparisonJsonWritten = $true

    Remove-Item -LiteralPath $comparisonJsonlPath -ErrorAction SilentlyContinue
    foreach ($row in @($pairRows)) {
        ($row | ConvertTo-Json -Depth 8 -Compress) | Add-Content -LiteralPath $comparisonJsonlPath -Encoding UTF8
    }
    $comparisonJsonlWritten = $true
}
([pscustomobject]$summary | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $summaryPath -Encoding UTF8

$mdLines = [System.Collections.Generic.List[string]]::new()
$mdLines.Add('# API Semantic Consistency Comparison') | Out-Null
$mdLines.Add('') | Out-Null
$mdLines.Add('## Metrics') | Out-Null
$mdLines.Add('') | Out-Null
$mdLines.Add('- Primary metric: Ordered API F1, computed from LCS-derived ordered precision / recall / F1.') | Out-Null
$mdLines.Add('- Auxiliary metric: Exact API match rate, where `effectiveApiSequence` must match baseline exactly.') | Out-Null
$mdLines.Add('') | Out-Null
$mdLines.Add('## Scope') | Out-Null
$mdLines.Add('') | Out-Null
$mdLines.Add("- Baseline: $BaselineLabel") | Out-Null
$mdLines.Add("- Candidate: $CandidateLabel") | Out-Null
$mdLines.Add("- Filters: $(@($filterDescriptions) -join '; ')") | Out-Null
$mdLines.Add("- Shared samples: $($summary.sharedSamples)") | Out-Null
$mdLines.Add("- Compared samples: $($summary.comparedSamples)") | Out-Null
$mdLines.Add('') | Out-Null
$mdLines.Add('## Summary') | Out-Null
$mdLines.Add('') | Out-Null
$mdLines.Add("| Metric | Value |") | Out-Null
$mdLines.Add("|--------|------:|") | Out-Null
$mdLines.Add("| Ordered API F1 | $(Format-Percent -Value ([double]$summary.averageOrderedF1Pct)) |") | Out-Null
$mdLines.Add("| Ordered API recall | $(Format-Percent -Value ([double]$summary.averageOrderedRecallPct)) |") | Out-Null
$mdLines.Add("| Ordered API precision | $(Format-Percent -Value ([double]$summary.averageOrderedPrecisionPct)) |") | Out-Null
$mdLines.Add("| Exact API match | $(Format-Percent -Value ([double]$summary.exactApiMatchPct)) |") | Out-Null
$mdLines.Add("| Avg baseline API count | $([string]::Format('{0:N4}', [double]$summary.averageBaselineApiCount)) |") | Out-Null
$mdLines.Add("| Avg candidate API count | $([string]::Format('{0:N4}', [double]$summary.averageCandidateApiCount)) |") | Out-Null
$mdLines.Add('') | Out-Null
$mdLines.Add('## Length Relation') | Out-Null
$mdLines.Add('') | Out-Null
$mdLines.Add("| Relation | Count |") | Out-Null
$mdLines.Add("|----------|------:|") | Out-Null
$mdLines.Add("| same length | $($summary.lengthRelations.sameLength) |") | Out-Null
$mdLines.Add("| candidate longer | $($summary.lengthRelations.candidateLonger) |") | Out-Null
$mdLines.Add("| candidate shorter | $($summary.lengthRelations.candidateShorter) |") | Out-Null

$mdLines | Set-Content -LiteralPath $comparisonMdPath -Encoding UTF8

if ($comparisonJsonWritten) {
    Write-Host "Comparison JSON: $comparisonJsonPath" -ForegroundColor Yellow
}
if ($comparisonJsonlWritten) {
    Write-Host "Comparison JSONL: $comparisonJsonlPath" -ForegroundColor Yellow
}
Write-Host "Summary JSON: $summaryPath" -ForegroundColor Yellow
Write-Host "Comparison MD: $comparisonMdPath" -ForegroundColor Yellow

