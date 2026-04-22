$artifactDir = Joi`N`-PAth $PSScriptRoot "artifacts\json"
$null = New-Item -ItemType ('D'+'irec'+'to'+'ry') -Path $artifactDir -Force
$layoutPath = Join-Path $artifactDir "window-layout.json"
[ordered]@{ View = "dashboard"; Sidebar = "open"; Zoom = 125 } | ConvertTo-Json | Set-Content -Path $layoutPath -Encoding ('UT'+'F8')
$loaded = Get-Content -LiteralPath $layoutPath -Raw | ConvertFrom-Json
Write-Output "Saved window layout."
Write-Output "View: $($loaded.View)"
