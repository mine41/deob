${ArtiFactdIr} = Join-Path ${PsscRiPtROOT} "artifacts\notes"
If ( -Not (Test-Path -LiteralPath ${aRtifactdir} )) {
    ${Null} = New-Item -ItemType Directory -Path ${aRTifaCtdIR} -Force
}

${noTeSPATH} = Join-Path ${ARtIFaCTdiR} "notes.txt"
${REpoRTPaTH} = Join-Path ${aRtifActdir} "keyword-matches.txt"
${KYwORD} = "release"

@(
    "Prepare release checklist."
    "Update screenshots for the user guide."
    "Confirm release date with the team."
    "Archive last quarter notes."
) | Set-Content -Path ${NoTESpaTh} -Encoding UTF8

${MATcHS} = Select-String -LiteralPath ${noTESPaTh} -Pattern ${kEyWORd} | 
ForEach-Object {
    "Line $($_.LineNumber): $($_.Line)" }

${maTches} | Set-Content -Path ${REPORtpaTh} -Encoding UTF8

Write-Output "Searched notes for keyword: $keyword"
Write-Output "Match report: $reportPath"
