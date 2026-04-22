${arTiFacTDir} = Join-Path ${PsSCrIPTRoot} "artifacts\json"
${Null} = New-Item -ItemType Directory -Path ${ARTiFActdIR} -Force
${PROfilePATH} = Join-Path ${ArtiFAcTDIr} "theme-profile.json"
[ordered]@{ accent = "blue"; 
    font = "Consolas"; 
    density = "compact" } | ConvertTo-Json | st-content -Path ${profiLepAth} -Encoding UTF8
${loAdEd} = get-contnt -LiteralPath ${proFiLPATH} -Raw | convrtfrom-json 
Write-Output "Saved theme profile."
Write-Output "Accent: $($loaded.Accent)"
