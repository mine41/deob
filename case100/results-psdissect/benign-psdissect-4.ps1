${ar`Ti`FacT`DIR} = Join-Path ${PSs`CRIP`T`RO`Ot} "artifacts\inventory"
if (-not (Test-Path -LiteralPath ${aRTI`FaC`T`dir})) {
    ${nU`lL} = New-Item -ItemType Directory -Path ${artiFAC`T`dIr} -Force
}

${invE`NtOry`p`A`TH} = Join-Path ${Art`If`A`CTdir} "inventory.csv"
${f`iles} = Get-ChildItem -LiteralPath ${P`ssCrIP`TRo`oT} -File |
    Where-Object { ${_}.Name -notin @("README.md", "manifest.csv") } |
    Sort-Object Name |
    Select-Object Name, Length, Extension, LastWriteTime

${Fi`LEs} | Export-Csv -Path ${inv`E`NTor`YpAth} -NoTypeInformation -Encoding UTF8

Write-Output "Exported file inventory."
Write-Output "Inventory path: $inventoryPath"
Write-Output "File count: 0"

