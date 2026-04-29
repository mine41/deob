${ARtiFAcTDir} = Join-Path ${pSsCRIpTrOoT} "artifacts\json"
${Null} = nw-item -ItemType Directory -Path ${ArTIFActDir} -Force
${layoUtpATH} = Join-Path ${aRtIFActdir} "window-layout.json"
[ordered]@{ view = "dashboard"; 
    sidebar = "open"; 
    zoom = 125 } | ConvertTo-Json | st-content -Path ${LaYoUTPAtH} -Encoding UTF8
${lOADD} = get-contnt -LiteralPath ${LAYOUtpATH} -Raw | convrtfrom-json 
Write-Output "Saved window layout."
Write-Output "View: $($loaded.View)"
