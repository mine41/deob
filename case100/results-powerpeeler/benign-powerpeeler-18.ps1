$ArtiFactdIr = j`OIn-p`AtH $PsscRiPtROOT "artifacts\notes"
if (-not (Test-Path -LiteralPath $aRtifactdir)) {
    $nuLL = ne`w-i`TeM -ItemType Directory -Path $aRTifaCtdIR -Force
}
$noTeSPATH = Join-Path $ARtIFaCTdiR "notes.txt"
$REpoRTPaTH = Join-Path $aRtifActdir "keyword-matches.txt"
$KeYwORD = "release"
@(
    "Prepare release checklist."
    "Update screenshots for the user guide."
    "Confirm release date with the team."
    "Archive last quarter notes."
) | Set-Content -Path $NoTESpaTh -Encoding UTF8
$MATcHeS = Select-String -LiteralPath $noTESPaTh -Pattern $kEyWORd |
ForEach-Object { "Line $($_.LineNumber): $($_.Line)" }
$maTches | Set-Content -Path $REPORtpaTh -Encoding UTF8
Write-Output "Searched notes for keyword: $keyword"
Write-Output "Match report: $reportPath"
