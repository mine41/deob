${arTiFa`cTD`ir} = Join-Path ${PsSCrIP`TR`o`ot} "artifacts\json"
${n`Ull} = New-Item -ItemType Directory -Path ${A`R`TiFA`ctdIR} -Force
${P`ROfi`lePA`TH} = Join-Path ${Arti`FA`c`TDIr} "theme-profile.json"
[ordered]@{ Accent = "blue"; Font = "Consolas"; Density = "compact" } | ConvertTo-Json | Set-Content -Path ${pr`ofiLep`Ath} -Encoding UTF8
${l`o`AdEd} = Get-Content -LiteralPath ${pr`oFiL`ePA`TH} -Raw | ConvertFrom-Json
Write-Output "Saved theme profile."
Write-Output "Accent: $($loaded.Accent)"

