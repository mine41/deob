${aRtIfACTDIr} = Join-Path ${PsSCrIpTRoOt} "artifacts\settings"
If ( -Not (Test-Path -LiteralPath ${artiFAcTdIR} )) {
    ${Null} = New-Item -ItemType dIrE`CtorY -Path ${ARTIfAcTDir} -Force
}

${sETtIngspAtH} = Join-Path ${ARTIFaCTDir} "app-settings.json"
${SetTiNgs} = [ordered]@{
    application = "SimpleBenignBenchmark"
    theme = "light"
    autosaveminutes = 10
    startpage = "dashboard"
}

${sETTINgS} | ConvertTo-Json | Set-Content -Path ${SeTTINgsPaTh} -Encoding UT`F8
${lOadeD} = Get-Content -LiteralPath ${sETTiNgspATh} -Raw | ConvertFrom-Json 

Write-Output "Saved settings JSON."
Write-Output "Application: $($loaded.Application)"
Write-Output "Theme: $($loaded.Theme)"
Write-Output "Settings path: $settingsPath"
