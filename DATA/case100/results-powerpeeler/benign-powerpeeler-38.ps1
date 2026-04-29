$aRTiFaCTdir = JoI`N-PATH $pSscripTRoOt "artifacts\json"
$nUll = New-Item -ItemType Directory -Path $ArtIfActdir -Force
$RULesPAtH = Join-Path $aRtiFacTdiR "alert-rules.json"
[ordered]@{ Channel = "email"; Level = "info"; QuietHours = "22:00-07:00" } | ConvertTo-Json | Set-Content -Path $RuLespaTh -Encoding UTF8
$LOadEd = Get-Content -LiteralPath $rUlEsPAth -Raw | ConvertFrom-Json
Write-Output "Saved alert rules."
Write-Output "Channel: $($loaded.Channel)"
