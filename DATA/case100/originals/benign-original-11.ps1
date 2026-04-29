$artifactDir = Join-Path $PSScriptRoot "artifacts\logs"
if (-not (Test-Path -LiteralPath $artifactDir)) {
    $null = New-Item -ItemType Directory -Path $artifactDir -Force
}

$logPath = Join-Path $artifactDir "app.log"
$entries = @(
    "$(Get-Date -Format s) INFO Started demo log rotation."
    "$(Get-Date -Format s) INFO Loaded local sample settings."
    "$(Get-Date -Format s) INFO Rotation check completed."
)

$entries | Add-Content -Path $logPath -Encoding UTF8
$latestLines = Get-Content -LiteralPath $logPath | Select-Object -Last 5
$latestLines | Set-Content -Path $logPath -Encoding UTF8

Write-Output "Newest entries kept: $($latestLines.Count)"
Write-Output "Log path: $logPath"
