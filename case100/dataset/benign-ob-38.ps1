${aR`TiFaC`Tdir} = JoI`N-PATH ${pSscrip`T`R`o`Ot} "artifacts\json"
${n`Ull} = ne`W`-ItEm -ItemType Directory -Path ${Art`If`Act`dir} -Force
${R`ULesP`AtH} = Jo`In-p`AtH ${aRti`Fac`TdiR} "alert-rules.json"
[ordered]@{ Channel = "email"; Level = "info"; QuietHours = "22:00-07:00" } | c`oNVert`To`-j`sOn | sE`T-`cont`enT -Path ${RuLes`pa`Th} -Encoding UTF8
${LOad`Ed} = GE`T-CoN`TENt -LiteralPath ${rU`lEsP`Ath} -Raw | CON`V`erTFRom`-JSON
WRI`Te-`oUtP`Ut "Saved alert rules."
WRIte`-`oU`TPUT "Channel: $($loaded.Channel)"
