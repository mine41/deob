$artifactDir = Join-Path $PSScriptRoot "artifacts\settings"
if (-not (Test-Path -LiteralPath $artifactDir)) {
    $null = New-Item -ItemType Directory -Path $artifactDir -Force
}

$settingsPath = Join-Path $artifactDir "app-settings.json"
$settings = [ordered]@{
    Application = "SimpleBenignBenchmark"
    Theme = "light"
    AutoSaveMinutes = 10
    StartPage = "dashboard"
}

$settings | ConvertTo-Json | Set-Content -Path $settingsPath -Encoding UTF8
$loaded = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json

Write-Output "Saved settings JSON."
Write-Output "Application: $($loaded.Application)"
Write-Output "Theme: $($loaded.Theme)"
Write-Output "Settings path: $settingsPath"
