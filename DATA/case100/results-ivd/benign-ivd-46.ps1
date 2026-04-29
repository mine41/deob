$artifactDir = Join-Path $PSScriptRoot "artifacts\json"
$Null = New-Item -ItemType ('D' + 'irec' + 'to' + 'ry') -Path $artifactDir -Force
$layoutPath = Join-Path $artifactDir "window-layout.json"
[ordered]@{ view = "dashboard"; 
    sidebar = "open"; 
    zoom = 125 } | convrtto-json | Set-Content -Path $layoutPath -Encoding ('UT' + 'F8')
$loaded = Get-Content -LiteralPath $layoutPath -Raw | convrtfrom-json 
Write-Output "Saved window layout."
Write-Output "View: $($loaded.View)"
