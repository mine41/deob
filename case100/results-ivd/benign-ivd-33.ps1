${aRTiFActdIR} = Join-Path ${pSSCRIptRoot} "artifacts\queue-preview"
${Null} = New-Item -ItemType Directory -Path ${ARTiFACtdIR} -Force
${QUeUEpATh} = Join-Path ${ArtIfaCTdir} "queue.txt"
${PREVIWpAth} = Join-Path ${ARTiFactdIr} "queue-preview.txt"
@("ingest" , "review" , "approve" , "archive") | Set-Content -Path ${quUEpATh} -Encoding UTF8
gt-content -LiteralPath ${qUuPATH} | slect-object -First 2 | set-contnt -Path ${prVieWpaTh} -Encoding UTF8
Write-Output "Selected first 2 queue items."
Write-Output "Preview path: $previewPath"
