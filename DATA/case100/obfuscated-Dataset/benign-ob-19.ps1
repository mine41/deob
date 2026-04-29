${arTi`Fa`Ctd`IR} = .("{1}{2}{0}"-f 'h','Jo','in-Pat') ${PssC`Rip`TROot} "artifacts\notes"
if (-not (.("{1}{2}{0}" -f'h','T','est-Pat') -LiteralPath ${aRti`FA`CTd`ir})) {
    ${Nu`Ll} = .("{0}{1}"-f'N','ew-Item') -ItemType Directory -Path ${ArtI`Fa`c`TdiR} -Force
}

${NOte`spA`TH} = .("{0}{2}{1}"-f 'Join','ath','-P') ${a`RtiF`ACTd`iR} "notes.txt"
${repOr`TpA`Th} = &("{1}{2}{0}"-f 'ath','J','oin-P') ${A`R`TiFACTdIR} "keyword-matches.txt"
${k`eY`word} = "release"

@(
    "Prepare release checklist."
    "Update screenshots for the user guide."
    "Confirm release date with the team."
    "Archive last quarter notes."
) | .("{0}{3}{2}{1}" -f 'Se','t','onten','t-C') -Path ${noT`E`SpA`TH} -Encoding UTF8

${ma`Tch`es} = .("{0}{1}{2}"-f'Select-S','trin','g') -LiteralPath ${no`Te`SPA`Th} -Pattern ${k`EyWoRD} |
    .("{0}{1}{3}{2}"-f 'F','orEa','-Object','ch') { "Line $($_.LineNumber): $($_.Line)" }

${mat`ch`ES} | .("{3}{1}{2}{0}" -f 'ent','on','t','Set-C') -Path ${Rep`orTp`Ath} -Encoding UTF8

&("{0}{2}{3}{1}"-f 'Write','t','-O','utpu') "Searched notes for keyword: $keyword"
&("{0}{1}{2}"-f'W','r','ite-Output') "Match report: $reportPath"
