$artifactDir = Join-Path $PSScriptRoot "artifacts\greeting"
if (-not (Test-Path -LiteralPath $artifactDir)) {
    $null = New-Item -ItemType Directory -Path $artifactDir -Force
}

$name = "Research Demo"
$message = 'Hello from simple benign sample, Research Demo.'
$timestamp = Get-Date -Format s
$outPath = Join-Path $artifactDir "greeting.txt"

@(
    'Hello from simple benign sample, Research Demo.'
    'GeneratedAt=2026-04-22T00:21:04'
) | Set-Content -Path $outPath -Encoding UTF8

Write-Output 'Hello from simple benign sample, Research Demo.'
Write-Output "Greeting file: $outPath"

