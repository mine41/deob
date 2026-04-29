${A`RtiFA`c`TDir} = Join-`PA`Th ${pS`sCRIp`Tr`O`oT} "artifacts\json"
${n`ULl} = n`ew-I`Tem -ItemType Directory -Path ${Ar`TIFA`ctD`ir} -Force
${lay`o`Utp`ATH} = join-`pa`TH ${aRt`IF`Act`dir} "window-layout.json"
[ordered]@{ View = "dashboard"; Sidebar = "open"; Zoom = 125 } | CONV`ERtto-`JSon | S`eT-`cO`Ntent -Path ${LaYoU`TP`AtH} -Encoding UTF8
${lO`AD`eD} = Get-CON`T`enT -LiteralPath ${LA`YO`UtpATH} -Raw | cOnv`er`T`FR`OM-json
wRI`Te-`outP`Ut "Saved window layout."
WRiT`E-OuT`P`UT "View: $($loaded.View)"
