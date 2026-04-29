${arTiFa`cTD`ir} = jo`I`N-pAtH ${PsSCrIP`TR`o`ot} "artifacts\json"
${n`Ull} = NEW-It`EM -ItemType Directory -Path ${A`R`TiFA`ctdIR} -Force
${P`ROfi`lePA`TH} = joi`N-`pAtH ${Arti`FA`c`TDIr} "theme-profile.json"
[ordered]@{ Accent = "blue"; Font = "Consolas"; Density = "compact" } | C`on`Ve`RtTO-jSoN | s`et-C`oNTeNT -Path ${pr`ofiLep`Ath} -Encoding UTF8
${l`o`AdEd} = GET-c`Ont`ent -LiteralPath ${pr`oFiL`ePA`TH} -Raw | ConV`erTf`R`Om-j`SON
wR`ITE`-Ou`TpuT "Saved theme profile."
W`RITe-oU`TpuT "Accent: $($loaded.Accent)"
