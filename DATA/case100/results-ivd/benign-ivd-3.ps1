${aRTiFActDir} = Join-Path ${PSscRIPTROot} "artifacts\tasks"
If ( -Not (Test-Path -LiteralPath ${ArTIFACTdir} )) {
    ${Null} = New-Item -ItemType DirecT`orY -Path ${aRTIFAcTdIR} -Force
}

${pLANNeD} = @("draft" , "review" , "publish" , "archive")
${ComPLETEd} = @("draft" , "review" , "archive" , "notify")

${pNdInG} = ${plAnnED} | Where-Object {
    ${_} -Notin ${CoMplETeD} }
${unXpeCTED} = ${CoMPleTED} | Where-Object {
    ${_} -Notin ${pLAnNED} }
${rporTPatH} = Join-Path ${ARTiFaCTdIr} "task-comparison.txt"

@(
    "Pending Tasks: $($pending -join ', ')"
    "Unexpected Tasks: $($unexpected -join ', ')"
) | Set-Content -Path ${RPORTpAth} -Encoding u`Tf8

Write-Output "Compared task lists."
Write-Output "Report path: $reportPath"
