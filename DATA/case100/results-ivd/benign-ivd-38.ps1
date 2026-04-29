${aRTiFaCTdir} = Join-Path ${pSscripTRoOt} "artifacts\json"
${Null} = New-Item -ItemType Directory -Path ${ArtIfActdir} -Force
${RULesPAtH} = Join-Path ${aRtiFacTdiR} "alert-rules.json"
[ordered]@{ channel = "email"; 
    level = "info"; 
    quiethours = "22:00-07:00" } | ConvertTo-Json | set-contnt -Path ${RuLespaTh} -Encoding UTF8
${LOadEd} = Get-Content -LiteralPath ${rUlEsPAth} -Raw | convrtfrom-json 
Write-Output "Saved alert rules."
Write-Output "Channel: $($loaded.Channel)"
