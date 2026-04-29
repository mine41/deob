$aRTifaCtDir = Jo`IN-`PatH $pSScRIpTRooT "artifacts\log-lines"
$nuLL = New-Item -ItemType Directory -Path $arTIfaCTdiR -Force
$lOgPATh = Join-Path $ARTiFACTdIR "recent.log"
@("alpha", "beta", "gamma", "delta", "epsilon") | Set-Content -Path $LOGPAtH -Encoding UTF8
Get-Content -LiteralPath $LogpaTH | Select-Object -Last 3 | Set-Content -Path $LoGpATh -Encoding UTF8
Write-Output "Kept latest 3 lines."
Write-Output "Log path: $logPath"
