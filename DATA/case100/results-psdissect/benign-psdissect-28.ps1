${arTIFaC`T`d`ir} = Join-Path ${p`SsCr`i`PtRoOt} "artifacts\build-steps"
${Nu`LL} = New-Item -ItemType Directory -Path ${aRTI`F`A`ctDIR} -Force
${step`SP`Ath} = Join-Path ${A`RTifA`Ctd`IR} "build-steps.txt"
@("restore", "build", "test", "package", "publish") | Set-Content -Path ${S`TepS`Path} -Encoding UTF8
Get-Content -LiteralPath ${S`T`EpSPa`TH} | Select-Object -Last 2 | Set-Content -Path ${STE`p`SpatH} -Encoding UTF8
Write-Output "Kept latest 2 steps."
Write-Output "Steps path: $stepsPath"

