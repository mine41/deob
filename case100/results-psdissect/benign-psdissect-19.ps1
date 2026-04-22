${arTi`Fa`Ctd`IR} = . Join-Path ${PssC`Rip`TROot} "artifacts\notes"
if (-not (. Test-Path -LiteralPath ${aRti`FA`CTd`ir})) {
    ${Nu`Ll} = . New-Item -ItemType Directory -Path ${ArtI`Fa`c`TdiR} -Force
}

${NOte`spA`TH} = . Join-Path ${a`RtiF`ACTd`iR} "notes.txt"
${repOr`TpA`Th} = & Join-Path ${A`R`TiFACTdIR} "keyword-matches.txt"
${k`eY`word} = "release"

@(
    "Prepare release checklist."
    "Update screenshots for the user guide."
    "Confirm release date with the team."
    "Archive last quarter notes."
) | . Set-Content -Path ${noT`E`SpA`TH} -Encoding UTF8

${ma`Tch`es} = . Select-String -LiteralPath ${no`Te`SPA`Th} -Pattern ${k`EyWoRD} |
    . ForEach-Object { "Line $($_.LineNumber): $($_.Line)" }

${mat`ch`ES} | . Set-Content -Path ${Rep`orTp`Ath} -Encoding UTF8

& Write-Output "Searched notes for keyword: $keyword"
& Write-Output "Match report: $reportPath"

