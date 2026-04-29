$artifactDir = Join-Path $PSScriptRoot "artifacts\hashes"
$inputDir = Join-Path $artifactDir "input"
if (-not (Test-Path -LiteralPath $inputDir)) {
    $null = New-Item -ItemType Directory -Path $inputDir -Force
}

Set-Content -Path (Join-Path $inputDir "alpha.txt") -Value "alpha document" -Encoding UTF8
Set-Content -Path (Join-Path $inputDir "beta.txt") -Value "beta document" -Encoding UTF8

$reportPath = Join-Path $artifactDir "hash-report.csv"
$hashes = Get-ChildItem -LiteralPath $inputDir -File |
    Sort-Object Name |
    Get-FileHash -Algorithm SHA256 |
    Select-Object Path, Algorithm, Hash

$hashes | Export-Csv -Path $reportPath -NoTypeInformation -Encoding UTF8

Write-Output "Exported SHA256 hashes."
Write-Output "Report path: $reportPath"
