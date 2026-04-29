$artifactDir = Join-Path $PSScriptRoot "artifacts\notes"
if (-not (Test-Path -LiteralPath $artifactDir)) {
    $null = New-Item -ItemType Directory -Path $artifactDir -Force
}

$notesPath = Join-Path $artifactDir "notes.txt"
$reportPath = Join-Path $artifactDir "keyword-matches.txt"
$keyword = "release"

@(
    "Prepare release checklist."
    "Update screenshots for the user guide."
    "Confirm release date with the team."
    "Archive last quarter notes."
) | Set-Content -Path $notesPath -Encoding UTF8

$matches = Select-String -LiteralPath $notesPath -Pattern $keyword |
    ForEach-Object { "Line $($_.LineNumber): $($_.Line)" }

$matches | Set-Content -Path $reportPath -Encoding UTF8

Write-Output "Searched notes for keyword: $keyword"
Write-Output "Match report: $reportPath"
