$ARTIfACtdIR = J`oIn-p`AtH $PsscRiptrOOt "artifacts\json"
$nUll = New-Item -ItemType Directory -Path $arTiFactDiR -Force
$PROfILEPATh = Join-Path $ArtIFACtdIr "theme-profile.json"
[ordered]@{ Accent = "blue"; Font = "Consolas"; Density = "compact" } | ConvertTo-Json | Set-Content -Path $proFiLEpATh -Encoding UTF8
$LoAdeD = Get-Content -LiteralPath $PRofilEPaTH -Raw | ConvertFrom-Json
Write-Output "Saved theme profile."
Write-Output "Accent: $($loaded.Accent)"
