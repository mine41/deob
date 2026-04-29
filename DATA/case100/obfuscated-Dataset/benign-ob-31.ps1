${a`RT`ifa`CtDir} = Jo`IN-`PatH ${pS`Sc`RIp`TRooT} "artifacts\log-lines"
${nu`LL} = N`e`w-iTeM -ItemType Directory -Path ${ar`TIfaC`Td`iR} -Force
${lOgP`ATh} = JOIN-p`A`Th ${ARTi`F`AC`TdIR} "recent.log"
@("alpha", "beta", "gamma", "delta", "epsilon") | SET-`co`NteNT -Path ${LOG`P`AtH} -Encoding UTF8
GET-`cOnT`ent -LiteralPath ${L`ogpa`TH} | S`E`L`eCt-OBject -Last 3 | SET-`coNt`ENT -Path ${L`oG`pATh} -Encoding UTF8
WR`iTe-OuTp`UT "Kept latest 3 lines."
wR`i`TE-O`UTput "Log path: $logPath"
