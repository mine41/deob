$artifactDir = j`OIn-pa`TH $PSScriptRoot "artifacts\queue-preview"
$null = New-Item -ItemType ('Director'+'y') -Path $artifactDir -Force
$queuePath = Join-Path $artifactDir "queue.txt"
$previewPath = Join-Path $artifactDir "queue-preview.txt"
@("ingest", "review", "approve", "archive") | Set-Content -Path $queuePath -Encoding ('U'+'TF8')
Get-Content -LiteralPath $queuePath | Select-Object -First 2 | Set-Content -Path $previewPath -Encoding ('U'+'TF8')
Write-Output "Selected first 2 queue items."
Write-Output "Preview path: $previewPath"
