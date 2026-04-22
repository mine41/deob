$artifactDir = J`o`In-PATh $PSScriptRoot "artifacts\inventory"
if (-not (t`est`-`pATH -LiteralPath $artifactDir)) {
    $null = n`ew`-item -ItemType ('Directo'+'ry') -Path $artifactDir -Force
}

$inventoryPath = J`O`IN-Pa`TH $artifactDir "inventory.csv"
$files = g`e`T-chiLDI`Tem -LiteralPath $PSScriptRoot -File |
    W`h`erE-objE`Ct { $_.Name -notin @("README.md", "manifest.csv") } |
    SORt`-OBJ`eCT ('N'+'ame') |
    SE`LeC`T-OBJecT ('Nam'+'e'), ('L'+'e'+'ngth'), ('Extensi'+'o'+'n'), ('La'+'stWriteT'+'i'+'me')

$files | eX`PORt-`Csv -Path $inventoryPath -NoTypeInformation -Encoding ('U'+'TF8')

W`RI`Te-oUT`PUt "Exported file inventory."
writ`E`-Ou`TpuT "Inventory path: $inventoryPath"
wrITe`-O`U`TpuT "File count: $($files.Count)"
