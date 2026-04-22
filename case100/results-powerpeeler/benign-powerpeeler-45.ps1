$ARtiFAcTDir = Join-`PA`Th $pSsCRIpTrOoT "artifacts\json"
$nULl = New-Item -ItemType Directory -Path $ArTIFActDir -Force
$layoUtpATH = Join-Path $aRtIFActdir "window-layout.json"
[ordered]@{ View = "dashboard"; Sidebar = "open"; Zoom = 125 } | ConvertTo-Json | Set-Content -Path $LaYoUTPAtH -Encoding UTF8
$lOADeD = Get-Content -LiteralPath $LAYOUtpATH -Raw | ConvertFrom-Json
Write-Output "Saved window layout."
Write-Output "View: $($loaded.View)"
