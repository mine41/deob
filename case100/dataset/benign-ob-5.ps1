${A`Rt`ifAC`TDir} = .("{2}{3}{0}{1}"-f'a','th','Joi','n-P') ${p`s`sCRIp`TrOoT} "artifacts\inventory"
if (-not (&("{1}{2}{0}"-f'th','Test','-Pa') -LiteralPath ${Ar`TiFA`CtdIr})) {
    ${n`UlL} = &("{1}{0}"-f '-Item','New') -ItemType Directory -Path ${aRTIf`Ac`TdIR} -Force
}

${i`NVeNto`R`YPaTh} = &("{0}{1}"-f'Joi','n-Path') ${a`RTiFAc`TD`IR} "inventory.csv"
${fiL`es} = .("{0}{3}{1}{4}{2}" -f 'Get','Chi','Item','-','ld') -LiteralPath ${pSscRIPTr`O`Ot} -File |
    &("{3}{0}{2}{1}"-f'h','Object','ere-','W') { ${_}.Name -notin @("README.md", "manifest.csv") } |
    &("{0}{2}{1}" -f 'Sort-Ob','ct','je') Name |
    &("{0}{2}{1}"-f 'Sel','ject','ect-Ob') Name, Length, Extension, LastWriteTime

${f`I`les} | &("{1}{2}{0}"-f'sv','Expo','rt-C') -Path ${in`V`eNtOR`Yp`AtH} -NoTypeInformation -Encoding UTF8

.("{2}{3}{1}{0}"-f 'utput','e-O','Wri','t') "Exported file inventory."
&("{3}{2}{1}{0}"-f'put','e-Out','t','Wri') "Inventory path: $inventoryPath"
.("{2}{1}{0}{3}" -f 'Outp','ite-','Wr','ut') "File count: $($files.Count)"
