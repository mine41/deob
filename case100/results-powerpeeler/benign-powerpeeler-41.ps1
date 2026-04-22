$aRTiFaCTDir = J`OIn-`pa`Th $psSCriPtROOt "artifacts\json"
$NUll = New-Item -ItemType Directory -Path $ARtiFAcTDir -Force
$SETtINgspaTh = Join-Path $artIFAcTDIR "app-settings.json"
[ordered]@{ App = "SampleDesk"; Theme = "light"; RefreshMinutes = 15 } | ConvertTo-Json | Set-Content -Path $sEtTIngSpAtH -Encoding UTF8
$lOAded = Get-Content -LiteralPath $SEtTINgSPATH -Raw | ConvertFrom-Json
Write-Output "Saved app settings."
Write-Output "Theme: $($loaded.Theme)"
