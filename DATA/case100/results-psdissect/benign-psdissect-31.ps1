${a`RT`ifa`CtDir} = Join-Path ${pS`Sc`RIp`TRooT} "artifacts\log-lines"
${nu`LL} = New-Item -ItemType Directory -Path ${ar`TIfaC`Td`iR} -Force
${lOgP`ATh} = Join-Path ${ARTi`F`AC`TdIR} "recent.log"
@("alpha", "beta", "gamma", "delta", "epsilon") | Set-Content -Path ${LOG`P`AtH} -Encoding UTF8
Get-Content -LiteralPath ${L`ogpa`TH} | Select-Object -Last 3 | Set-Content -Path ${L`oG`pATh} -Encoding UTF8
Write-Output "Kept latest 3 lines."
Write-Output "Log path: $logPath"

