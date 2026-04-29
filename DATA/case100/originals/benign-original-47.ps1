$artifactDir = Join-Path $PSScriptRoot "artifacts\json"
$null = New-Item -ItemType Directory -Path $artifactDir -Force
$layoutPath = Join-Path $artifactDir "window-layout.json"
[ordered]@{ View = "dashboard"; Sidebar = "open"; Zoom = 125 } | ConvertTo-Json | Set-Content -Path $layoutPath -Encoding UTF8
$loaded = Get-Content -LiteralPath $layoutPath -Raw | ConvertFrom-Json
Write-Output "Saved window layout."
Write-Output "View: $($loaded.View)"
