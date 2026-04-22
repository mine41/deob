$artifactDir = Join-Path $PSScriptRoot "artifacts\queue-preview"
$Null = nw-item -ItemType ('Director' + 'y') -Path $artifactDir -Force
$queuePath = Join-Path $artifactDir "queue.txt"
$previewPath = Join-Path $artifactDir "queue-preview.txt"
@("ingest" , "review" , "approve" , "archive") | Set-Content -Path $queuePath -Encoding ('U' + 'TF8')
get-contnt -LiteralPath $queuePath | slect-object -First 2 | st-content -Path $previewPath -Encoding ('U' + 'TF8')
Write-Output "Selected first 2 queue items."
Write-Output "Preview path: $previewPath"
