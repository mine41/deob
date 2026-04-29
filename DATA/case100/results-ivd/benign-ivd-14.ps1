${aRTIFActdIR} = Join-Path ${psSCrIPtRoOT} "artifacts\settings"
If ( -Not (Test-Path -LiteralPath ${ARTiFacTDIr} )) {
    ${Null} = New-Item -ItemType DIrEcto`RY -Path ${arTIFActDir} -Force
}

${setTINgSPATh} = Join-Path ${ArtifaCTDiR} "app-settings.json"
${SEtTiNGS} = [ordered]@{
    application = "SimpleBenignBenchmark"
    theme = "light"
    autosaveminutes = 10
    startpage = "dashboard"
}

${STTINgs} | ConvertTo-Json | Set-Content -Path ${SEtTiNgSPATH} -Encoding u`TF8
${lOAdEd} = Get-Content -LiteralPath ${SETtiNgSPATH} -Raw | ConvertFrom-Json 

Write-Output "Saved settings JSON."
Write-Output "Application: $($loaded.Application)"
Write-Output "Theme: $($loaded.Theme)"
Write-Output "Settings path: $settingsPath"
