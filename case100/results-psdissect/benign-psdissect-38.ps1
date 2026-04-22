${aR`TiFaC`Tdir} = Join-Path ${pSscrip`T`R`o`Ot} "artifacts\json"
${n`Ull} = New-Item -ItemType Directory -Path ${Art`If`Act`dir} -Force
${R`ULesP`AtH} = Join-Path ${aRti`Fac`TdiR} "alert-rules.json"
[ordered]@{ Channel = "email"; Level = "info"; QuietHours = "22:00-07:00" } | ConvertTo-Json | Set-Content -Path ${RuLes`pa`Th} -Encoding UTF8
${LOad`Ed} = Get-Content -LiteralPath ${rU`lEsP`Ath} -Raw | ConvertFrom-Json
Write-Output "Saved alert rules."
Write-Output "Channel: $($loaded.Channel)"

