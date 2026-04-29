${aRTIfACTdIr} = & ("{1}{0}{2}" -f 'n-' , 'Joi' , 'Path') ${PSSCriPtROOT} "artifacts\hashes"
${INPuTdIR} = .("{1}{0}{2}" -f 'in-P' , 'Jo' , 'ath') ${arTiFacTDIR} "input"
If ( -Not ( & ("{0}{1}" -f 'T' , 'est-Path') -LiteralPath ${INPUTdiR} )) {
    ${Null} = .("{2}{0}{1}" -f '-I' , 'tem' , 'New') -ItemType Directory -Path ${iNpUTDiR} -Force
}

.("{1}{2}{3}{0}" -f 't' , 'Set-C' , 'onte' , 'n') -Path (.("{2}{0}{1}" -f 'oin-Pat' , 'h' , 'J') ${InPUTdiR} "alpha.txt") -Value "alpha document" -Encoding UTF8
& ("{2}{0}{1}{3}" -f 'o' , 'n' , 'Set-C' , 'tent') -Path ( & ("{1}{0}" -f 'oin-Path' , 'J') ${InPUtDir} "beta.txt") -Value "beta document" -Encoding UTF8

${rEPorTpAtH} = .("{1}{2}{3}{0}" -f 'th' , 'Join-' , 'P' , 'a') ${ArtifactDir} "hash-report.csv"
${hAshEs} = & ("{0}{1}{2}" -f 'Get-' , 'Chil' , 'dItem') -LiteralPath ${InpUTDIr} -File | 
.("{1}{2}{0}" -f 'ct' , 'Sort-Ob' , 'je') Name | 
& ("{0}{3}{2}{1}" -f 'Get' , 'h' , 'FileHas' , '-') -Algorithm SHA256 | 
& ("{2}{4}{3}{0}{1}" -f 'jec' , 't' , 'Sel' , '-Ob' , 'ect') Path , Algorithm , Hash

${HASHs} | .("{0}{2}{1}" -f 'Ex' , 'sv' , 'port-C') -Path ${RePORtPaTH} -NoTypeInformation -Encoding UTF8

.("{0}{1}{2}" -f 'Write' , '-Out' , 'put') "Exported SHA256 hashes."
& ("{2}{0}{3}{1}" -f 'i' , '-Output' , 'Wr' , 'te') "Report path: $reportPath"
