$artifactDir = Join-Path $PSScriptRoot "artifacts\tasks"
if (-not (Test-Path -LiteralPath $artifactDir)) {
    $null = New-Item -ItemType Directory -Path $artifactDir -Force
}

$planned = @("draft", "review", "publish", "archive")
$completed = @("draft", "review", "archive", "notify")

$pending = $planned | Where-Object { $_ -notin $completed }
$unexpected = $completed | Where-Object { $_ -notin $planned }
$reportPath = Join-Path $artifactDir "task-comparison.txt"

@(
    "Pending Tasks: $($pending -join ', ')"
    "Unexpected Tasks: $($unexpected -join ', ')"
) | Set-Content -Path $reportPath -Encoding UTF8

Write-Output "Compared task lists."
Write-Output "Report path: $reportPath"
