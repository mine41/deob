${aRTIfACTdIR} = Join-Path ${PsscRiptroot} "artifacts\tasks"
If ( -Not (Test-Path -LiteralPath ${artiFaCtdiR} )) {
    ${Null} = New-Item -ItemType diREC`ToRY -Path ${aRtiFAcTDIR} -Force
}

${plaNned} = @("draft" , "review" , "publish" , "archive")
${cOMPLETd} = @("draft" , "review" , "archive" , "notify")

${pENdING} = ${PlAnnEd} | Where-Object {
    ${_} -Notin ${CoMPlEtEd} }
${unXPECTED} = ${cOMPleted} | Where-Object {
    ${_} -Notin ${PLANNeD} }
${rEpORtpaTH} = Join-Path ${aRTiFaCTDir} "task-comparison.txt"

@(
    "Pending Tasks: $($pending -join ', ')"
    "Unexpected Tasks: $($unexpected -join ', ')"
) | Set-Content -Path ${rEpORTpaTH} -Encoding u`TF8

Write-Output "Compared task lists."
Write-Output "Report path: $reportPath"
