${ARtifACTDir} = .("{2}{3}{0}{1}" -f 'a' , 'th' , 'Joi' , 'n-P') ${pssCRIpTrOoT} "artifacts\inventory"
If ( -Not ( & ("{1}{2}{0}" -f 'th' , 'Test' , '-Pa') -LiteralPath ${ArTiFACtdIr} )) {
    ${Null} = & ("{1}{0}" -f '-Item' , 'New') -ItemType Directory -Path ${aRTIfAcTdIR} -Force
}

${iNVeNtoRYPaTh} = & ("{0}{1}" -f 'Joi' , 'n-Path') ${aRTiFAcTDIR} "inventory.csv"
${fiLs} = .("{0}{3}{1}{4}{2}" -f 'Get' , 'Chi' , 'Item' , '-' , 'ld') -LiteralPath ${pSscRIPTrOOt} -File | 
& ("{3}{0}{2}{1}" -f 'h' , 'Object' , 'ere-' , 'W') {
    ${_}.Name -Notin @("README.md" , "manifest.csv") } | 
& ("{0}{2}{1}" -f 'Sort-Ob' , 'ct' , 'je') Name | 
& ("{0}{2}{1}" -f 'Sel' , 'ject' , 'ect-Ob') Name , Length , Extension , LastWriteTime

${fIles} | & ("{1}{2}{0}" -f 'sv' , 'Expo' , 'rt-C') -Path ${inVNtORYpAtH} -NoTypeInformation -Encoding UTF8

.("{2}{3}{1}{0}" -f 'utput' , 'e-O' , 'Wri' , 't') "Exported file inventory."
& ("{3}{2}{1}{0}" -f 'put' , 'e-Out' , 't' , 'Wri') "Inventory path: $inventoryPath"
.("{2}{1}{0}{3}" -f 'Outp' , 'ite-' , 'Wr' , 'ut') "File count: $($files.Count)"
