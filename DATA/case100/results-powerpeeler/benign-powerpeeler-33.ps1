$aRTiFActdIR = J`O`In-Pa`Th $pSSCRIptRoot "artifacts\queue-preview"
$NUll = New-Item -ItemType Directory -Path $ARTiFACtdIR -Force
$QUeUEpATh = Join-Path $ArtIfaCTdir "queue.txt"
$PREVIeWpAth = Join-Path $ARTiFactdIr "queue-preview.txt"
@("ingest", "review", "approve", "archive") | Set-Content -Path $queUEpATh -Encoding UTF8
Get-Content -LiteralPath $qUeuePATH | Select-Object -First 2 | Set-Content -Path $preVieWpaTh -Encoding UTF8
Write-Output "Selected first 2 queue items."
Write-Output "Preview path: $previewPath"
