$ArTiFAcTdIr = joIn-p`A`Th $pSScrIptROoT "artifacts\settings"
if (-not (Test-Path -LiteralPath $ArTIfactdir)) {
    $nULL = nEw-it`EM -ItemType Directory -Path $ARTiFAcTDIr -Force
}
$SeTtINGSPATh = Join-Path $ARTifAcTdiR "app-settings.json"
$SETtINGS = [ordered]@{
    Application = "SimpleBenignBenchmark"
    Theme = "light"
    AutoSaveMinutes = 10
    StartPage = "dashboard"
}
$SEtTInGs | ConvertTo-Json | Set-Content -Path $sEtTiNGSPATh -Encoding UTF8
$loaded = Get-Content -LiteralPath $seTTInGspAth -Raw | ConvertFrom-Json
Write-Output "Saved settings JSON."
Write-Output "Application: $($loaded.Application)"
Write-Output "Theme: $($loaded.Theme)"
Write-Output "Settings path: $settingsPath"
