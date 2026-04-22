${ARTiFacTdir} = Join-Path ${PsSCriPtRoot} "artifacts\release-preview"
${Null} = New-Item -ItemType Directory -Path ${artIfACtDir} -Force
${NOTESPATh} = Join-Path ${ArTiFACTDIR} "release-notes.txt"
${pREVIEWpATh} = Join-Path ${ARtifactDiR} "release-preview.txt"
@("intro" , "features" , "fixes" , "faq") | Set-Content -Path ${nOtesPATh} -Encoding UTF8
Get-Content -LiteralPath ${noTEsPatH} | selct-object -First 3 | set-contnt -Path ${PrEvIWPATh} -Encoding UTF8
Write-Output "Selected first 3 release notes."
Write-Output "Preview path: $previewPath"
