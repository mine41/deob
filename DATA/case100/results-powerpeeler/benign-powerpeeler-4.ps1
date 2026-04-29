$arTiFacTDIR = jOiN-`PA`Th $PSsCRIPTROOt "artifacts\inventory"
if (-not (Test-Path -LiteralPath $aRTIFaCTdir)) {
    $nUlL = neW-I`T`em -ItemType Directory -Path $artiFACTdIr -Force
}
$invENtOrypATH = Join-Path $ArtIfACTdir "inventory.csv"
$files = Ge`T-cHiLDIt`em -LiteralPath $PssCrIPTRooT -File |
where`-`OBjecT { $_.Name -notin @("README.md", "manifest.csv") } |
SoRT`-O`B`JECT Name |
SE`L`ect-O`BjeCt Name, Length, Extension, LastWriteTime
$FiLEs | Export-Csv -Path $invENTorYpAth -NoTypeInformation -Encoding UTF8
Write-Output "Exported file inventory."
Write-Output "Inventory path: $inventoryPath"
Write-Output "File count: $($files.Count)"
