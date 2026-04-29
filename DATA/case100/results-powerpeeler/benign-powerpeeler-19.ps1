$arTiFaCtdIR = .("{1}{2}{0}"-f 'h','Jo','in-Pat') $PssCRipTROot "artifacts\notes"
if (-not (.("{1}{2}{0}" -f'h','T','est-Pat') -LiteralPath $aRtiFACTdir)) {
    $NuLl = .("{0}{1}"-f'N','ew-Item') -ItemType Directory -Path $ArtIFacTdiR -Force
}
$NOtespATH = .("{0}{2}{1}"-f 'Join','ath','-P') $aRtiFACTdiR "notes.txt"
$repOrTpATh = &("{1}{2}{0}"-f 'ath','J','oin-P') $ARTiFACTdIR "keyword-matches.txt"
$keYword = "release"
@(
    "Prepare release checklist."
    "Update screenshots for the user guide."
    "Confirm release date with the team."
    "Archive last quarter notes."
) | .("{0}{3}{2}{1}" -f 'Se','t','onten','t-C') -Path $noTESpATH -Encoding UTF8
$maTches = .("{0}{1}{2}"-f'Select-S','trin','g') -LiteralPath $noTeSPATh -Pattern $kEyWoRD |
    .("{0}{1}{3}{2}"-f 'F','orEa','-Object','ch') { "Line $($_.LineNumber): $($_.Line)" }
$matchES | .("{3}{1}{2}{0}" -f 'ent','on','t','Set-C') -Path $ReporTpAth -Encoding UTF8
&("{0}{2}{3}{1}"-f 'Write','t','-O','utpu') "Searched notes for keyword: $keyword"
&("{0}{1}{2}"-f'W','r','ite-Output') "Match report: $reportPath"
