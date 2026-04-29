${ArTiFAcTdIr} = Join-Path ${pSScrIptROoT} "artifacts\settings"
If ( -Not (Test-Path -LiteralPath ${ArTIfactdir} )) {
    ${Null} = New-Item -ItemType Directory -Path ${ARTiFAcTDIr} -Force
}

${SeTtINGSPATh} = Join-Path ${ARTifAcTdiR} "app-settings.json"
${SETtINGS} = [ordered]@{
    application = "SimpleBenignBenchmark"
    theme = "light"
    autosaveminutes = 10
    startpage = "dashboard"
}

${SEtTInGs} | ConvertTo-Json | Set-Content -Path ${sEtTiNGSPATh} -Encoding UTF8
${loaded} = Get-Content -LiteralPath ${seTTInGspAth} -Raw | ConvertFrom-Json 

Write-Output "Saved settings JSON."
Write-Output "Application: $($loaded.Application)"
Write-Output "Theme: $($loaded.Theme)"
Write-Output "Settings path: $settingsPath"
