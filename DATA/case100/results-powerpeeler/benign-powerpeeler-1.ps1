$aRTIfACTdIR = Join-Path $PsscRiptroot "artifacts\tasks"
if (-not (Test-Path -LiteralPath $artiFaCtdiR)) {
    $nuLl = New-Item -ItemType diREC`ToRY -Path $aRtiFAcTDIR -Force
}
$plaNned = @("draft", "review", "publish", "archive")
$cOMPLETed = @("draft", "review", "archive", "notify")
$pENdING = $PlAnnEd | Where-Object { $_ -notin $CoMPlEtEd }
$uneXPECTED = $cOMPleted | Where-Object { $_ -notin $PLANNeD }
$rEpORtpaTH = Join-Path $aRTiFaCTDir "task-comparison.txt"
@(
    "Pending Tasks: $($pending -join ', ')"
    "Unexpected Tasks: $($unexpected -join ', ')"
) | Set-Content -Path $rEpORTpaTH -Encoding u`TF8
Write-Output "Compared task lists."
Write-Output "Report path: $reportPath"
