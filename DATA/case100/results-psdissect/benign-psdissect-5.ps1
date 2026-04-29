${A`Rt`ifAC`TDir} = . Join-Path ${p`s`sCRIp`TrOoT} "artifacts\inventory"
if (-not (& Test-Path -LiteralPath ${Ar`TiFA`CtdIr})) {
    ${n`UlL} = & New-Item -ItemType Directory -Path ${aRTIf`Ac`TdIR} -Force
}

${i`NVeNto`R`YPaTh} = & Join-Path ${a`RTiFAc`TD`IR} "inventory.csv"
${fiL`es} = . Get-ChildItem -LiteralPath ${pSscRIPTr`O`Ot} -File |
    & Where-Object { ${_}.Name -notin @("README.md", "manifest.csv") } |
    & Sort-Object Name |
    & Select-Object Name, Length, Extension, LastWriteTime

${f`I`les} | & Export-Csv -Path ${in`V`eNtOR`Yp`AtH} -NoTypeInformation -Encoding UTF8

. Write-Output "Exported file inventory."
& Write-Output "Inventory path: $inventoryPath"
. Write-Output "File count: 0"

