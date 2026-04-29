$artifactDir = Join-Path $PSScriptRoot "artifacts\json"
$null = New-Item -ItemType Directory -Path $artifactDir -Force
$settingsPath = Join-Path $artifactDir "app-settings.json"
[ordered]@{ App = "SampleDesk"; Theme = "light"; RefreshMinutes = 15 } | ConvertTo-Json | Set-Content -Path $settingsPath -Encoding UTF8
$loaded = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
Write-Output "Saved app settings."
Write-Output "Theme: $($loaded.Theme)"
