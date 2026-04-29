$arTiFacTDir = jo`I`N-pAtH $PsSCrIPTRoot "artifacts\json"
$nUll = New-Item -ItemType Directory -Path $ARTiFActdIR -Force
$PROfilePATH = Join-Path $ArtiFAcTDIr "theme-profile.json"
[ordered]@{ Accent = "blue"; Font = "Consolas"; Density = "compact" } | ConvertTo-Json | Set-Content -Path $profiLepAth -Encoding UTF8
$loAdEd = Get-Content -LiteralPath $proFiLePATH -Raw | ConvertFrom-Json
Write-Output "Saved theme profile."
Write-Output "Accent: $($loaded.Accent)"
