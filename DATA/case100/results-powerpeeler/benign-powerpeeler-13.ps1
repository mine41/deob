$aRtIfACTDIr = Join-Path $PsSCrIpTRoOt "artifacts\settings"
if (-not (Test-Path -LiteralPath $artiFAcTdIR)) {
    $NUll = New-Item -ItemType dIrE`CtorY -Path $ARTIfAcTDir -Force
}
$sETtIngspAtH = Join-Path $ARTIFaCTDir "app-settings.json"
$SetTiNgs = [ordered]@{
    Application = "SimpleBenignBenchmark"
    Theme = "light"
    AutoSaveMinutes = 10
    StartPage = "dashboard"
}
$sETTINgS | ConvertTo-Json | Set-Content -Path $SeTTINgsPaTh -Encoding UT`F8
$lOadeD = Get-Content -LiteralPath $sETTiNgspATh -Raw | ConvertFrom-Json
Write-Output "Saved settings JSON."
Write-Output "Application: $($loaded.Application)"
Write-Output "Theme: $($loaded.Theme)"
Write-Output "Settings path: $settingsPath"
