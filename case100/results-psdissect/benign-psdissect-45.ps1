${A`RtiFA`c`TDir} = Join-Path ${pS`sCRIp`Tr`O`oT} "artifacts\json"
${n`ULl} = New-Item -ItemType Directory -Path ${Ar`TIFA`ctD`ir} -Force
${lay`o`Utp`ATH} = Join-Path ${aRt`IF`Act`dir} "window-layout.json"
[ordered]@{ View = "dashboard"; Sidebar = "open"; Zoom = 125 } | ConvertTo-Json | Set-Content -Path ${LaYoU`TP`AtH} -Encoding UTF8
${lO`AD`eD} = Get-Content -LiteralPath ${LA`YO`UtpATH} -Raw | ConvertFrom-Json
Write-Output "Saved window layout."
Write-Output "View: $($loaded.View)"

