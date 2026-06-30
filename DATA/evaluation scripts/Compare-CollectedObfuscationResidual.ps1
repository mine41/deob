<#
Offline pairwise comparison of residual obfuscation burden based on
previously collected results.json files.

Design goals:
1. Reuse existing collected fields without rerunning any sample.
2. Compare tools only on samples that are valid for both sides.
3. Normalize each feature against the original baseline and keep the
   residual ratio within 0..100%.
4. Avoid penalizing outputs simply because deobfuscation exposes more
   explicit script text, AST nodes, or instructions.

Example:
.\Compare-CollectedObfuscationResidual.ps1 `
  -BaselineResults .\D-Script-Baseline `
  -LeftResults .\D-Script-PSDissect `
  -LeftInventory ..\ExecutionSummary\D-Script-PSDissect-inventory.csv `
  -LeftLabel PSDissect `
  -RightResults .\D-Script-PowerPeeler `
  -RightInventory ..\ExecutionSummary\D-Script-PowerPeeler-inventory.csv `
  -RightLabel PowerPeeler `
  -OutputPrefix .\pairwise-residual\D-Script-PSDissect-vs-PowerPeeler
#>

param(
    [Parameter(Mandatory = $true)][string]$BaselineResults,
    [Parameter(Mandatory = $true)][string]$LeftResults,
    [Parameter(Mandatory = $true)][string]$LeftInventory,
    [Parameter(Mandatory = $true)][string]$RightResults,
    [Parameter(Mandatory = $true)][string]$RightInventory,
    [Parameter(Mandatory = $true)][string]$OutputPrefix,
    [string]$LeftLabel = 'Left',
    [string]$RightLabel = 'Right',
    [string]$ScoreVersion = 'residual_obfuscation_burden_v1',
    [double]$WeightWrapperDepth = 35.0,
    [double]$WeightLauncherCount = 35.0,
    [double]$WeightEncodedCommandCount = 10.0,
    [double]$WeightDynamicExecPrimitiveCount = 8.0,
    [double]$WeightCompilePrimitiveCount = 8.0,
    [double]$WeightByteArrayLiteralBytes = 4.0
)

$ErrorActionPreference = 'Stop'

function Resolve-ResultsJsonPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $resolved = Resolve-Path -LiteralPath $Path
    $item = Get-Item -LiteralPath $resolved.Path
    if ($item -is [System.IO.DirectoryInfo]) {
        $jsonPath = Join-Path $item.FullName 'results.json'
        if (-not (Test-Path -LiteralPath $jsonPath)) {
            throw "results.json not found under directory: $($item.FullName)"
        }

        return $jsonPath
    }

    return $item.FullName
}

function Resolve-ExistingPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Resolve-Path -LiteralPath $Path).Path
}

function Get-InputIdentity {
    param([Parameter(Mandatory = $true)][string]$Path)

    $resolved = Resolve-Path -LiteralPath $Path
    $item = Get-Item -LiteralPath $resolved.Path
    if ($item -is [System.IO.DirectoryInfo]) {
        return $item.Name
    }

    return $item.Name
}

function Ensure-ParentDirectory {
    param([Parameter(Mandatory = $true)][string]$Path)

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
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

function Get-DoubleField {
    param(
        [Parameter(Mandatory = $true)]$Row,
        [Parameter(Mandatory = $true)][string[]]$Names,
        [double]$Default = 0.0
    )

    foreach ($name in @($Names)) {
        if ($null -eq $Row.PSObject.Properties[$name]) { continue }
        $value = $Row.$name
        if ($null -eq $value) { continue }
        return [double]$value
    }

    return $Default
}

function Get-FeatureValueMap {
    param([Parameter(Mandatory = $true)]$Row)

    return @{
        wrapperDepth = Get-DoubleField -Row $Row -Names @('entryWrapperDepth', 'wrapperDepth', 'normalizedDepth')
        launcherCount = Get-DoubleField -Row $Row -Names @('entryLauncherHopCount', 'launcherCount')
        encodedCommandCount = Get-DoubleField -Row $Row -Names @('entryEncodedCommandCount', 'encodedCommandCount')
        dynamicExecPrimitiveCount = Get-DoubleField -Row $Row -Names @('unresolvedDynamicExecCount', 'dynamicExecPrimitiveCount')
        compilePrimitiveCount = Get-DoubleField -Row $Row -Names @('unresolvedCompileCount', 'compilePrimitiveCount')
        byteArrayLiteralBytes = Get-DoubleField -Row $Row -Names @('opaqueExecByteArrayBytes', 'byteArrayLiteralBytes')
    }
}

function Transform-FeatureValue {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [double]$Value
    )

    $safeValue = [Math]::Max(0.0, $Value)
    switch ($Name) {
        'byteArrayLiteralBytes' { return [Math]::Log(1.0 + $safeValue, 2.0) }
        default { return $safeValue }
    }
}

function Get-ResidualRatio {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [double]$ToolValue,
        [double]$BaselineValue
    )

    $toolTransformed = Transform-FeatureValue -Name $Name -Value $ToolValue
    $baselineTransformed = Transform-FeatureValue -Name $Name -Value $BaselineValue

    if ($baselineTransformed -le 0.0) {
        if ($toolTransformed -le 0.0) { return 0.0 }
        return 1.0
    }

    return [Math]::Min(($toolTransformed / $baselineTransformed), 1.0)
}

function Get-WeightedResidualPercent {
    param(
        [Parameter(Mandatory = $true)][hashtable]$FeatureValues,
        [Parameter(Mandatory = $true)][hashtable]$BaselineValues,
        [Parameter(Mandatory = $true)][hashtable]$Weights
    )

    $weighted = 0.0
    $totalWeight = 0.0
    $ratios = @{}

    foreach ($name in @($Weights.Keys)) {
        $weight = [double]$Weights[$name]
        if ($weight -le 0.0) { continue }

        $ratio = Get-ResidualRatio -Name $name -ToolValue ([double]$FeatureValues[$name]) -BaselineValue ([double]$BaselineValues[$name])
        $ratios[$name] = [Math]::Round($ratio, 6)
        $weighted += ($weight * $ratio)
        $totalWeight += $weight
    }

    if ($totalWeight -le 0.0) {
        throw 'At least one positive weight is required.'
    }

    return @{
        scorePercent = [Math]::Round((100.0 * $weighted / $totalWeight), 4)
        ratios = $ratios
    }
}

function Load-ResultsMap {
    param([Parameter(Mandatory = $true)][string]$Path)

    $resolvedJsonPath = Resolve-ResultsJsonPath -Path $Path
    $rows = @(Get-Content -LiteralPath $resolvedJsonPath -Raw | ConvertFrom-Json)
    $map = @{}

    foreach ($row in @($rows)) {
        if ($null -eq $row) { continue }

        $sampleId = if ($row.sampleId) { [string]$row.sampleId } else { Get-SampleStem -Name ([string]$row.file) }
        if ([string]::IsNullOrWhiteSpace($sampleId)) { continue }
        $map[$sampleId] = $row
    }

    return @{
        path = $resolvedJsonPath
        rows = $rows
        map = $map
    }
}

function Load-ValidSampleSet {
    param([Parameter(Mandatory = $true)][string]$InventoryPath)

    $resolvedInventoryPath = Resolve-ExistingPath -Path $InventoryPath
    $rows = @(Import-Csv -LiteralPath $resolvedInventoryPath)
    $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($row in @($rows)) {
        if ($null -eq $row) { continue }
        $name = [string]$row.Name
        $result = [string]$row.Result
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        if ($result -ne 'valid') { continue }
        [void]$set.Add($name)
    }

    return @{
        path = $resolvedInventoryPath
        rows = $rows
        validSet = $set
    }
}

function Get-SortedIntersection {
    param(
        [Parameter(Mandatory = $true)][System.Collections.Generic.HashSet[string]]$LeftSet,
        [Parameter(Mandatory = $true)][System.Collections.Generic.HashSet[string]]$RightSet
    )

    $list = [System.Collections.Generic.List[string]]::new()
    foreach ($value in $LeftSet) {
        if ($RightSet.Contains($value)) {
            $list.Add($value) | Out-Null
        }
    }

    $list.Sort([System.StringComparer]::OrdinalIgnoreCase)
    return $list
}

function New-StatBucket {
    param([Parameter(Mandatory = $true)][hashtable]$Weights)

    $fieldSums = @{}
    foreach ($name in @($Weights.Keys)) {
        $fieldSums[$name] = 0.0
    }

    return @{
        sampleCount = 0
        scoreSum = 0.0
        fieldSums = $fieldSums
    }
}

function Add-StatBucketSample {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Bucket,
        [double]$ScorePercent,
        [Parameter(Mandatory = $true)][hashtable]$Ratios
    )

    $Bucket.sampleCount = [int]$Bucket.sampleCount + 1
    $Bucket.scoreSum = [double]$Bucket.scoreSum + $ScorePercent

    foreach ($name in @($Ratios.Keys)) {
        $Bucket.fieldSums[$name] = [double]$Bucket.fieldSums[$name] + [double]$Ratios[$name]
    }
}

function Get-StatBucketSummary {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Bucket,
        [Parameter(Mandatory = $true)][hashtable]$Weights
    )

    $fieldAverages = @{}
    foreach ($name in @($Weights.Keys)) {
        $avg = if ($Bucket.sampleCount -gt 0) { [double]$Bucket.fieldSums[$name] / [double]$Bucket.sampleCount } else { 0.0 }
        $fieldAverages[$name] = [Math]::Round((100.0 * $avg), 4)
    }

    return @{
        sampleCount = [int]$Bucket.sampleCount
        averageResidualPercent = if ($Bucket.sampleCount -gt 0) { [Math]::Round(([double]$Bucket.scoreSum / [double]$Bucket.sampleCount), 4) } else { 0.0 }
        fieldAverageResidualPercent = $fieldAverages
    }
}

$weights = @{
    wrapperDepth = $WeightWrapperDepth
    launcherCount = $WeightLauncherCount
    encodedCommandCount = $WeightEncodedCommandCount
    dynamicExecPrimitiveCount = $WeightDynamicExecPrimitiveCount
    compilePrimitiveCount = $WeightCompilePrimitiveCount
    byteArrayLiteralBytes = $WeightByteArrayLiteralBytes
}

$baselineData = Load-ResultsMap -Path $BaselineResults
$leftData = Load-ResultsMap -Path $LeftResults
$rightData = Load-ResultsMap -Path $RightResults
$leftInventoryData = Load-ValidSampleSet -InventoryPath $LeftInventory
$rightInventoryData = Load-ValidSampleSet -InventoryPath $RightInventory

$commonValid = Get-SortedIntersection -LeftSet $leftInventoryData.validSet -RightSet $rightInventoryData.validSet
$perSample = [System.Collections.Generic.List[object]]::new()
$leftStats = New-StatBucket -Weights $weights
$rightStats = New-StatBucket -Weights $weights

$missingBaseline = 0
$missingLeft = 0
$missingRight = 0

foreach ($sampleId in @($commonValid)) {
    if (-not $baselineData.map.ContainsKey($sampleId)) {
        $missingBaseline++
        continue
    }

    if (-not $leftData.map.ContainsKey($sampleId)) {
        $missingLeft++
        continue
    }

    if (-not $rightData.map.ContainsKey($sampleId)) {
        $missingRight++
        continue
    }

    $baselineFeatures = Get-FeatureValueMap -Row $baselineData.map[$sampleId]
    $leftFeatures = Get-FeatureValueMap -Row $leftData.map[$sampleId]
    $rightFeatures = Get-FeatureValueMap -Row $rightData.map[$sampleId]

    $leftResidual = Get-WeightedResidualPercent -FeatureValues $leftFeatures -BaselineValues $baselineFeatures -Weights $weights
    $rightResidual = Get-WeightedResidualPercent -FeatureValues $rightFeatures -BaselineValues $baselineFeatures -Weights $weights

    Add-StatBucketSample -Bucket $leftStats -ScorePercent ([double]$leftResidual.scorePercent) -Ratios $leftResidual.ratios
    Add-StatBucketSample -Bucket $rightStats -ScorePercent ([double]$rightResidual.scorePercent) -Ratios $rightResidual.ratios

    $perSample.Add([pscustomobject]@{
        sampleId = $sampleId
        baseline = $baselineFeatures
        left = [pscustomobject]@{
            label = $LeftLabel
            features = $leftFeatures
            residualPercent = [double]$leftResidual.scorePercent
            fieldResidualRatio = $leftResidual.ratios
        }
        right = [pscustomobject]@{
            label = $RightLabel
            features = $rightFeatures
            residualPercent = [double]$rightResidual.scorePercent
            fieldResidualRatio = $rightResidual.ratios
        }
    }) | Out-Null
}

$summary = [pscustomobject]@{
    scoreVersion = $ScoreVersion
    baselineReferencePercent = 100.0
    baselineResults = Get-InputIdentity -Path $BaselineResults
    leftResults = Get-InputIdentity -Path $LeftResults
    leftInventory = Get-InputIdentity -Path $LeftInventory
    leftLabel = $LeftLabel
    rightResults = Get-InputIdentity -Path $RightResults
    rightInventory = Get-InputIdentity -Path $RightInventory
    rightLabel = $RightLabel
    commonValidCountFromInventory = $commonValid.Count
    comparedSampleCount = $perSample.Count
    missingBaselineResultCount = $missingBaseline
    missingLeftResultCount = $missingLeft
    missingRightResultCount = $missingRight
    weights = $weights
    leftSummary = Get-StatBucketSummary -Bucket $leftStats -Weights $weights
    rightSummary = Get-StatBucketSummary -Bucket $rightStats -Weights $weights
}

$jsonPath = "$OutputPrefix.json"
$summaryPath = "$OutputPrefix.summary.json"
$markdownPath = "$OutputPrefix.md"

Ensure-ParentDirectory -Path $jsonPath
Ensure-ParentDirectory -Path $summaryPath
Ensure-ParentDirectory -Path $markdownPath

Set-Content -LiteralPath $jsonPath -Value ($perSample | ConvertTo-Json -Depth 8) -Encoding UTF8
Set-Content -LiteralPath $summaryPath -Value ($summary | ConvertTo-Json -Depth 8) -Encoding UTF8

$leftAvg = [double]$summary.leftSummary.averageResidualPercent
$rightAvg = [double]$summary.rightSummary.averageResidualPercent
$winner = if ($leftAvg -lt $rightAvg) { $LeftLabel } elseif ($rightAvg -lt $leftAvg) { $RightLabel } else { 'Tie' }

$md = @(
    "# $ScoreVersion",
    "",
    "- Baseline reference: 100.00% by definition.",
    "- Comparison scope: common valid only.",
    "- Lower residual percentage means lower remaining obfuscation burden.",
    "",
    "| Pair | Common Valid | Compared | $LeftLabel Residual | $RightLabel Residual | Better |",
    "|------|-------------:|---------:|--------------------:|---------------------:|--------|",
    "| $LeftLabel vs $RightLabel | $($summary.commonValidCountFromInventory) | $($summary.comparedSampleCount) | $([string]::Format('{0:N4}%', $leftAvg)) | $([string]::Format('{0:N4}%', $rightAvg)) | $winner |",
    "",
    "## Field Average Residual",
    "",
    "| Field | $LeftLabel | $RightLabel |",
    "|------|------------:|-------------:|",
    "| wrapperDepth | $([string]::Format('{0:N4}%', [double]$summary.leftSummary.fieldAverageResidualPercent.wrapperDepth)) | $([string]::Format('{0:N4}%', [double]$summary.rightSummary.fieldAverageResidualPercent.wrapperDepth)) |",
    "| launcherCount | $([string]::Format('{0:N4}%', [double]$summary.leftSummary.fieldAverageResidualPercent.launcherCount)) | $([string]::Format('{0:N4}%', [double]$summary.rightSummary.fieldAverageResidualPercent.launcherCount)) |",
    "| encodedCommandCount | $([string]::Format('{0:N4}%', [double]$summary.leftSummary.fieldAverageResidualPercent.encodedCommandCount)) | $([string]::Format('{0:N4}%', [double]$summary.rightSummary.fieldAverageResidualPercent.encodedCommandCount)) |",
    "| dynamicExecPrimitiveCount | $([string]::Format('{0:N4}%', [double]$summary.leftSummary.fieldAverageResidualPercent.dynamicExecPrimitiveCount)) | $([string]::Format('{0:N4}%', [double]$summary.rightSummary.fieldAverageResidualPercent.dynamicExecPrimitiveCount)) |",
    "| compilePrimitiveCount | $([string]::Format('{0:N4}%', [double]$summary.leftSummary.fieldAverageResidualPercent.compilePrimitiveCount)) | $([string]::Format('{0:N4}%', [double]$summary.rightSummary.fieldAverageResidualPercent.compilePrimitiveCount)) |",
    "| byteArrayLiteralBytes | $([string]::Format('{0:N4}%', [double]$summary.leftSummary.fieldAverageResidualPercent.byteArrayLiteralBytes)) | $([string]::Format('{0:N4}%', [double]$summary.rightSummary.fieldAverageResidualPercent.byteArrayLiteralBytes)) |"
)
Set-Content -LiteralPath $markdownPath -Value ($md -join [Environment]::NewLine) -Encoding UTF8

Write-Host "Saved per-sample residuals: $jsonPath" -ForegroundColor Green
Write-Host "Saved summary: $summaryPath" -ForegroundColor Green
Write-Host "Saved markdown: $markdownPath" -ForegroundColor Green
