$artifactDir = Join-Path $PSScriptRoot "artifacts\greeting"
if (-not (Test-Path -LiteralPath $artifactDir)) {
    $null = New-Item -ItemType Directory -Path $artifactDir -Force
}

$name = "Research Demo"
$message = "Hello from simple benign sample, $name."
$timestamp = Get-Date -Format "s"
$outPath = Join-Path $artifactDir "greeting.txt"

@(
    $message
    "GeneratedAt=$timestamp"
) | Set-Content -Path $outPath -Encoding UTF8

Write-Output $message
Write-Output "Greeting file: $outPath"
