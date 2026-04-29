${aRtIfACT`D`Ir} = Join-Path ${PsSCr`IpT`RoOt} "artifacts\settings"
if (-not (Test-Path -LiteralPath ${arti`F`A`cTdIR})) {
    ${NU`ll} = New-Item -ItemType dIrECtorY -Path ${ART`IfAc`TD`ir} -Force
}

${sE`TtIngs`pAtH} = Join-Path ${AR`TIFaCT`Dir} "app-settings.json"
${Set`TiNgs} = [ordered]@{
    Application = "SimpleBenignBenchmark"
    Theme = "light"
    AutoSaveMinutes = 10
    StartPage = "dashboard"
}

${sE`TTI`NgS} | ConvertTo-Json | Set-Content -Path ${Se`TTI`Ng`sPaTh} -Encoding UTF8
${l`Oa`deD} = Get-Content -LiteralPath ${sE`T`TiNgspA`Th} -Raw | ConvertFrom-Json

Write-Output "Saved settings JSON."
Write-Output "Application: $($loaded.Application)"
Write-Output "Theme: $($loaded.Theme)"
Write-Output "Settings path: $settingsPath"

