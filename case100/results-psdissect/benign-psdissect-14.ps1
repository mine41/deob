${aR`T`I`FActdIR} = Join-Path ${p`sSCrIPt`R`o`OT} "artifacts\settings"
if (-not (Test-Path -LiteralPath ${A`R`T`iFacTDIr})) {
    ${N`ULl} = New-Item -ItemType DIrEctoRY -Path ${arTI`F`A`ctDir} -Force
}

${setT`IN`gSPA`Th} = Join-Path ${ArtifaCT`D`iR} "app-settings.json"
${SEtTi`NGS} = [ordered]@{
    Application = "SimpleBenignBenchmark"
    Theme = "light"
    AutoSaveMinutes = 10
    StartPage = "dashboard"
}

${S`eT`TIN`gs} | ConvertTo-Json | Set-Content -Path ${SEt`TiN`gS`P`ATH} -Encoding uTF8
${lO`A`dEd} = Get-Content -LiteralPath ${SE`Tti`N`gSP`ATH} -Raw | ConvertFrom-Json

Write-Output "Saved settings JSON."
Write-Output "Application: $($loaded.Application)"
Write-Output "Theme: $($loaded.Theme)"
Write-Output "Settings path: $settingsPath"

