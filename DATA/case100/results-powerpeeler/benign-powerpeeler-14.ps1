$aRTIFActdIR = Join-Path $psSCrIPtRoOT "artifacts\settings"
if (-not (Test-Path -LiteralPath $ARTiFacTDIr)) {
    $NULl = New-Item -ItemType DIrEcto`RY -Path $arTIFActDir -Force
}
$setTINgSPATh = Join-Path $ArtifaCTDiR "app-settings.json"
$SEtTiNGS = [ordered]@{
    Application = "SimpleBenignBenchmark"
    Theme = "light"
    AutoSaveMinutes = 10
    StartPage = "dashboard"
}
$SeTTINgs | ConvertTo-Json | Set-Content -Path $SEtTiNgSPATH -Encoding u`TF8
$lOAdEd = Get-Content -LiteralPath $SETtiNgSPATH -Raw | ConvertFrom-Json
Write-Output "Saved settings JSON."
Write-Output "Application: $($loaded.Application)"
Write-Output "Theme: $($loaded.Theme)"
Write-Output "Settings path: $settingsPath"
