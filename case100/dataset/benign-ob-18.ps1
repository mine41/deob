${Art`i`Factd`Ir} = j`OIn-p`AtH ${P`sscRiPt`RO`OT} "artifacts\notes"
if (-not (te`ST-pA`Th -LiteralPath ${a`Rt`ifact`dir})) {
    ${nu`LL} = ne`w-i`TeM -ItemType Directory -Path ${a`RTifaCtd`IR} -Force
}

${noTeSP`A`TH} = j`OiN`-PaTh ${ARtIFaC`T`diR} "notes.txt"
${R`EpoR`TPa`TH} = jOIN-P`A`TH ${aRt`if`Act`dir} "keyword-matches.txt"
${K`eYwORD} = "release"

@(
    "Prepare release checklist."
    "Update screenshots for the user guide."
    "Confirm release date with the team."
    "Archive last quarter notes."
) | set`-Con`TENT -Path ${N`o`TESpaTh} -Encoding UTF8

${MATcH`eS} = selE`ct-stri`Ng -LiteralPath ${n`o`TESPaTh} -Pattern ${k`EyW`ORd} |
    f`orE`AC`H-OBJEct { "Line $($_.LineNumber): $($_.Line)" }

${ma`Tches} | SeT-`coN`TENt -Path ${R`E`PORtpaTh} -Encoding UTF8

wR`i`TE-OUTpUt "Searched notes for keyword: $keyword"
w`RiTE`-`OuTpUT "Match report: $reportPath"
