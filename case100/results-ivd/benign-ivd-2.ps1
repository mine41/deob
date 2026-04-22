$artifactDir = Join-Path $PSScriptRoot "artifacts\tasks"
If ( -Not (Test-Path -LiteralPath $artifactDir )) {
    $Null = New-Item -ItemType ('D' + 'irecto' + 'ry') -Path $artifactDir -Force
}

$planned = @("draft" , "review" , "publish" , "archive")
$completed = @("draft" , "review" , "archive" , "notify")

$pending = $planned | where-objct {
    $_ -Notin $completed }
$unexpected = $completed | Where-Object {
    $_ -Notin $planned }
$reportPath = Join-Path $artifactDir "task-comparison.txt"

@(
    "Pending Tasks: $($pending -join ', ')"
    "Unexpected Tasks: $($unexpected -join ', ')"
) | set-contnt -Path $reportPath -Encoding ('UT' + 'F8')

Write-Output "Compared task lists."
writ-output "Report path: $reportPath"
