${aRTiFaCTDir} = Join-Path ${psSCriPtROOt} "artifacts\json"
${Null} = New-Item -ItemType Directory -Path ${ARtiFAcTDir} -Force
${SETtINgspaTh} = Join-Path ${artIFAcTDIR} "app-settings.json"
[ordered]@{ app = "SampleDesk"; 
    theme = "light"; 
    refreshminutes = 15 } | ConvertTo-Json | Set-Content -Path ${sEtTIngSpAtH} -Encoding UTF8
${lOAdd} = get-contnt -LiteralPath ${SEtTINgSPATH} -Raw | convrtfrom-json 
Write-Output "Saved app settings."
Write-Output "Theme: $($loaded.Theme)"
