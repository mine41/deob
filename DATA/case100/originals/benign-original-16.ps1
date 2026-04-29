$artifactDir = Join-Path $PSScriptRoot "artifacts\system"
if (-not (Test-Path -LiteralPath $artifactDir)) {
    $null = New-Item -ItemType Directory -Path $artifactDir -Force
}

$reportPath = Join-Path $artifactDir "system-report.txt"
$lines = @(
    "ComputerName=$env:COMPUTERNAME"
    "UserName=$env:USERNAME"
    "PowerShellVersion=$($PSVersionTable.PSVersion)"
    "CurrentLocation=$((Get-Location).Path)"
    "GeneratedAt=$(Get-Date -Format s)"
)

$lines | Set-Content -Path $reportPath -Encoding UTF8

Write-Output "Saved system report."
Write-Output "Report path: $reportPath"
