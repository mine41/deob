$artifactDir = Join-Path $PSScriptRoot "artifacts\inventory"
If ( -Not (tst-path -LiteralPath $artifactDir )) {
    $Null = nw-item -ItemType ('Directo' + 'ry') -Path $artifactDir -Force
}

$inventoryPath = Join-Path $artifactDir "inventory.csv"
$files = gt-childitem -LiteralPath $PSScriptRoot -File | 
whre-object {
    $_.Name -Notin @("README.md" , "manifest.csv") } | 
sort-objct ('N' + 'ame') | 
Select-Object ('Nam' + 'e') , ('L' + 'e' + 'ngth') , ('Extensi' + 'o' + 'n') , ('La' + 'stWriteT' + 'i' + 'me')

$files | Export-Csv -Path $inventoryPath -NoTypeInformation -Encoding ('U' + 'TF8')

Write-Output "Exported file inventory."
Write-Output "Inventory path: $inventoryPath"
Write-Output "File count: $($files.Count)"
