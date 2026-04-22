$artifactDir = Join-Path $PSScriptRoot "artifacts\queue-preview"
$null = New-Item -ItemType Directory -Path $artifactDir -Force
$queuePath = Join-Path $artifactDir "queue.txt"
$previewPath = Join-Path $artifactDir "queue-preview.txt"
@("ingest", "review", "approve", "archive") | Set-Content -Path $queuePath -Encoding UTF8
Get-Content -LiteralPath $queuePath | Select-Object -First 2 | Set-Content -Path $previewPath -Encoding UTF8
Write-Output "Selected first 2 queue items."
Write-Output "Preview path: $previewPath"

