$artifactDir = J`o`In-PATh $PSScriptRoot "artifacts\inventory"
if (-not (Test-Path -LiteralPath $artifactDir)) {
    $null = n`ew`-item -ItemType ('Directo'+'ry') -Path $artifactDir -Force
}
$inventoryPath = Join-Path $artifactDir "inventory.csv"
$files = g`e`T-chiLDI`Tem -LiteralPath $PSScriptRoot -File |
W`h`erE-objE`Ct { $_.Name -notin @("README.md", "manifest.csv") } |
SORt`-OBJ`eCT ('N'+'ame') |
SE`LeC`T-OBJecT ('Nam'+'e'), ('L'+'e'+'ngth'), ('Extensi'+'o'+'n'), ('La'+'stWriteT'+'i'+'me')
$files | Export-Csv -Path $inventoryPath -NoTypeInformation -Encoding ('U'+'TF8')
Write-Output "Exported file inventory."
Write-Output "Inventory path: $inventoryPath"
Write-Output "File count: $($files.Count)"
