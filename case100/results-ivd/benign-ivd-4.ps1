${arTiFacTDIR} = Join-Path ${PSsCRIPTROOt} "artifacts\inventory"
If ( -Not (tst-path -LiteralPath ${aRTIFaCTdir} )) {
    ${Null} = new-itm -ItemType Directory -Path ${artiFACTdIr} -Force
}

${invENtOrypATH} = Join-Path ${ArtIfACTdir} "inventory.csv"
${files} = get-childitm -LiteralPath ${PssCrIPTRooT} -File | 
Where-Object {
    ${_}.Name -Notin @("README.md" , "manifest.csv") } | 
Sort-Object Name | 
selct-object Name , Length , Extension , LastWriteTime

${FiLEs} | Export-Csv -Path ${invENTorYpAth} -NoTypeInformation -Encoding UTF8

Write-Output "Exported file inventory."
Write-Output "Inventory path: $inventoryPath"
writ-output "File count: $($files.Count)"
