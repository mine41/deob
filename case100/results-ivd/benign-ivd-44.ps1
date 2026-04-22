$artifactDir = Join-Path $PSScriptRoot "artifacts\json"
$Null = nw-itm -ItemType ('D' + 'ir' + 'ectory') -Path $artifactDir -Force
$profilePath = Join-Path $artifactDir "theme-profile.json"
[ordered]@{ accent = "blue"; 
    font = "Consolas"; 
    density = "compact" } | convrtto-json | set-contnt -Path $profilePath -Encoding ('UT' + 'F8')
$loaded = Get-Content -LiteralPath $profilePath -Raw | ConvertFrom-Json 
Write-Output "Saved theme profile."
Write-Output "Accent: $($loaded.Accent)"
