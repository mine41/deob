${Ar`T`iF`AcTdIr} = Join-Path ${pS`Scr`I`pt`ROoT} "artifacts\settings"
if (-not (Test-Path -LiteralPath ${Ar`TIfactd`ir})) {
    ${n`ULL} = New-Item -ItemType Directory -Path ${ARTiF`Ac`T`DIr} -Force
}

${Se`TtING`SPA`Th} = Join-Path ${ARTifA`cT`diR} "app-settings.json"
${S`ETtINGS} = [ordered]@{
    Application = "SimpleBenignBenchmark"
    Theme = "light"
    AutoSaveMinutes = 10
    StartPage = "dashboard"
}

${S`Et`TInGs} | ConvertTo-Json | Set-Content -Path ${sEt`TiN`GSPATh} -Encoding UTF8
${loa`ded} = Get-Content -LiteralPath ${seTT`In`Gsp`Ath} -Raw | ConvertFrom-Json

Write-Output "Saved settings JSON."
Write-Output "Application: $($loaded.Application)"
Write-Output "Theme: $($loaded.Theme)"
Write-Output "Settings path: $settingsPath"

