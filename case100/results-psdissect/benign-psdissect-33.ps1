${a`RTiF`Act`dIR} = Join-Path ${pSSC`RIptR`oot} "artifacts\queue-preview"
${NU`ll} = New-Item -ItemType Directory -Path ${ARTi`F`ACt`dIR} -Force
${Q`Ue`UEpA`Th} = Join-Path ${Art`IfaCTd`ir} "queue.txt"
${PR`E`VI`eWpAth} = Join-Path ${AR`Ti`Factd`Ir} "queue-preview.txt"
@("ingest", "review", "approve", "archive") | Set-Content -Path ${qu`e`U`EpATh} -Encoding UTF8
Get-Content -LiteralPath ${qU`eu`eP`ATH} | Select-Object -First 2 | Set-Content -Path ${pr`e`VieWpaTh} -Encoding UTF8
Write-Output "Selected first 2 queue items."
Write-Output "Preview path: $previewPath"

