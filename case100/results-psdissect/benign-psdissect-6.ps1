$artifactDir = Join-Path $PSScriptRoot "artifacts\inventory"
if (-not (Test-Path -LiteralPath $artifactDir)) {
    $null = New-Item -ItemType Directory -Path $artifactDir -Force
}

$inventoryPath = Join-Path $artifactDir "inventory.csv"
$files = Get-ChildItem -LiteralPath $PSScriptRoot -File |
    Where-Object { $_.Name -notin @("README.md", "manifest.csv") } |
    Sort-Object Name |
    Select-Object Name, Length, Extension, LastWriteTime

$files | Export-Csv -Path $inventoryPath -NoTypeInformation -Encoding UTF8

Write-Output "Exported file inventory."
Write-Output "Inventory path: $inventoryPath"
Write-Output "File count: 0"

