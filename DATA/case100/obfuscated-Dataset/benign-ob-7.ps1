${aR`T`IfACTdIr} = &("{1}{0}{2}"-f 'n-','Joi','Path') ${PS`SCr`iPtRO`OT} "artifacts\hashes"
${INPu`Td`IR} = .("{1}{0}{2}" -f'in-P','Jo','ath') ${ar`TiFac`TD`IR} "input"
if (-not (&("{0}{1}" -f 'T','est-Path') -LiteralPath ${I`NP`UTd`iR})) {
    ${n`ULl} = .("{2}{0}{1}"-f'-I','tem','New') -ItemType Directory -Path ${iNp`U`T`DiR} -Force
}

.("{1}{2}{3}{0}"-f't','Set-C','onte','n') -Path (.("{2}{0}{1}" -f 'oin-Pat','h','J') ${InPU`T`diR} "alpha.txt") -Value "alpha document" -Encoding UTF8
&("{2}{0}{1}{3}"-f 'o','n','Set-C','tent') -Path (&("{1}{0}" -f'oin-Path','J') ${In`PUtD`ir} "beta.txt") -Value "beta document" -Encoding UTF8

${rEPorT`p`AtH} = .("{1}{2}{3}{0}"-f 'th','Join-','P','a') ${Artifa`ct`Dir} "hash-report.csv"
${hAsh`Es} = &("{0}{1}{2}"-f'Get-','Chil','dItem') -LiteralPath ${Inp`U`TDIr} -File |
    .("{1}{2}{0}" -f'ct','Sort-Ob','je') Name |
    &("{0}{3}{2}{1}"-f 'Get','h','FileHas','-') -Algorithm SHA256 |
    &("{2}{4}{3}{0}{1}"-f 'jec','t','Sel','-Ob','ect') Path, Algorithm, Hash

${H`ASH`es} | .("{0}{2}{1}" -f'Ex','sv','port-C') -Path ${RePO`Rt`Pa`TH} -NoTypeInformation -Encoding UTF8

.("{0}{1}{2}"-f 'Write','-Out','put') "Exported SHA256 hashes."
&("{2}{0}{3}{1}"-f'i','-Output','Wr','te') "Report path: $reportPath"
