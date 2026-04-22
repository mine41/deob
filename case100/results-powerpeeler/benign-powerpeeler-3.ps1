$aRTiFActDir = Join-Path $PSscRIPTROot "artifacts\tasks"
if (-not (Test-Path -LiteralPath $ArTIFACTdir)) {
    $nUll = New-Item -ItemType DirecT`orY -Path $aRTIFAcTdIR -Force
}
$pLANNeD = @("draft", "review", "publish", "archive")
$ComPLETEd = @("draft", "review", "archive", "notify")
$peNdInG = $plAnnED | Where-Object { $_ -notin $CoMplETeD }
$uneXpeCTED = $CoMPleTED | Where-Object { $_ -notin $pLAnNED }
$reporTPatH = Join-Path $ARTiFaCTdIr "task-comparison.txt"
@(
    "Pending Tasks: $($pending -join ', ')"
    "Unexpected Tasks: $($unexpected -join ', ')"
) | Set-Content -Path $RePORTpAth -Encoding u`Tf8
Write-Output "Compared task lists."
Write-Output "Report path: $reportPath"
