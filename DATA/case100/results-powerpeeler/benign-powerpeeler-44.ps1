$artifactDir = J`oiN-pA`Th $PSScriptRoot "artifacts\json"
$null = New-Item -ItemType ('D'+'ir'+'ectory') -Path $artifactDir -Force
$profilePath = Join-Path $artifactDir "theme-profile.json"
[ordered]@{ Accent = "blue"; Font = "Consolas"; Density = "compact" } | ConvertTo-Json | Set-Content -Path $profilePath -Encoding ('UT'+'F8')
$loaded = Get-Content -LiteralPath $profilePath -Raw | ConvertFrom-Json
Write-Output "Saved theme profile."
Write-Output "Accent: $($loaded.Accent)"
