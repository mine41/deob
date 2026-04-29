${ar`Ti`FacT`DIR} = jOiN-`PA`Th ${PSs`CRIP`T`RO`Ot} "artifacts\inventory"
if (-not (t`esT-P`ATH -LiteralPath ${aRTI`FaC`T`dir})) {
    ${nU`lL} = neW-I`T`em -ItemType Directory -Path ${artiFAC`T`dIr} -Force
}

${invE`NtOry`p`A`TH} = join-P`ATh ${Art`If`A`CTdir} "inventory.csv"
${f`iles} = Ge`T-cHiLDIt`em -LiteralPath ${P`ssCrIP`TRo`oT} -File |
    where`-`OBjecT { ${_}.Name -notin @("README.md", "manifest.csv") } |
    SoRT`-O`B`JECT Name |
    SE`L`ect-O`BjeCt Name, Length, Extension, LastWriteTime

${Fi`LEs} | exP`oR`T-`cSv -Path ${inv`E`NTor`YpAth} -NoTypeInformation -Encoding UTF8

w`RI`Te-out`puT "Exported file inventory."
w`RIte-oUt`put "Inventory path: $inventoryPath"
wrIT`e-`o`UTpUt "File count: $($files.Count)"
