${aRTifaCtDir} = Join-Path ${pSScRIpTRooT} "artifacts\log-lines"
${Null} = nw-item -ItemType Directory -Path ${arTIfaCTdiR} -Force
${lOgPATh} = Join-Path ${ARTiFACTdIR} "recent.log"
@("alpha" , "beta" , "gamma" , "delta" , "epsilon") | Set-Content -Path ${LOGPAtH} -Encoding UTF8
get-contnt -LiteralPath ${LogpaTH} | selct-object -Last 3 | Set-Content -Path ${LoGpATh} -Encoding UTF8
Write-Output "Kept latest 3 lines."
Write-Output "Log path: $logPath"
