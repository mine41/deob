$artifactDir = Join-Path $PSScriptRoot "artifacts\json"
$null = New-Item -ItemType Directory -Path $artifactDir -Force
$profilePath = Join-Path $artifactDir "theme-profile.json"
[ordered]@{ Accent = "blue"; Font = "Consolas"; Density = "compact" } | ConvertTo-Json | Set-Content -Path $profilePath -Encoding UTF8
$loaded = Get-Content -LiteralPath $profilePath -Raw | ConvertFrom-Json
Write-Output "Saved theme profile."
Write-Output "Accent: $($loaded.Accent)"

