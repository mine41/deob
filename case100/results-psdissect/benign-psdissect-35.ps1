${A`RTi`Fa`cTdir} = Join-Path ${Ps`SCriPtRo`ot} "artifacts\release-preview"
${N`Ull} = New-Item -ItemType Directory -Path ${artIfACt`D`ir} -Force
${NOTES`PA`Th} = Join-Path ${ArTi`FACTD`IR} "release-notes.txt"
${p`REVIEWpA`Th} = Join-Path ${A`Rt`ifactDiR} "release-preview.txt"
@("intro", "features", "fixes", "faq") | Set-Content -Path ${n`OtesPA`Th} -Encoding UTF8
Get-Content -LiteralPath ${n`o`TE`sPatH} | Select-Object -First 3 | Set-Content -Path ${PrEvI`eWP`ATh} -Encoding UTF8
Write-Output "Selected first 3 release notes."
Write-Output "Preview path: $previewPath"

