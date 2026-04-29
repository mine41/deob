$artifactDir = Join-Path $PSScriptRoot "artifacts\json"
$Null = nw-item -ItemType ('Direct' + 'o' + 'ry') -Path $artifactDir -Force
$layoutPath = Join-Path $artifactDir "window-layout.json"
[ordered]@{ view = "dashboard"; 
    sidebar = "open"; 
    zoom = 125 } | convrtto-json | st-content -Path $layoutPath -Encoding ('U' + 'TF8')
$loaded = Get-Content -LiteralPath $layoutPath -Raw | ConvertFrom-Json 
Write-Output "Saved window layout."
Write-Output "View: $($loaded.View)"
