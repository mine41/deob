${AR`TIfA`CtdIR} = J`oIn-p`AtH ${P`sscRiptrO`Ot} "artifacts\json"
${n`Ull} = NE`w-I`TEm -ItemType Directory -Path ${ar`Ti`FactD`iR} -Force
${PR`OfIL`EP`ATh} = jOin`-P`Ath ${ArtI`FACt`dIr} "theme-profile.json"
[ordered]@{ Accent = "blue"; Font = "Consolas"; Density = "compact" } | c`oNV`ert`T`O-JsOn | SE`T-`cOntEnt -Path ${pro`Fi`LEpA`Th} -Encoding UTF8
${Lo`Ad`eD} = Ge`T-cOn`T`eNT -LiteralPath ${PRofi`l`E`PaTH} -Raw | cOnv`ERTfRo`m-`jSoN
w`Rit`e-ou`TPUt "Saved theme profile."
WrIt`e`-OuTpUt "Accent: $($loaded.Accent)"
