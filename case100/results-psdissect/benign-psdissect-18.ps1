${Art`i`Factd`Ir} = Join-Path ${P`sscRiPt`RO`OT} "artifacts\notes"
if (-not (Test-Path -LiteralPath ${a`Rt`ifact`dir})) {
    ${nu`LL} = New-Item -ItemType Directory -Path ${a`RTifaCtd`IR} -Force
}

${noTeSP`A`TH} = Join-Path ${ARtIFaC`T`diR} "notes.txt"
${R`EpoR`TPa`TH} = Join-Path ${aRt`if`Act`dir} "keyword-matches.txt"
${K`eYwORD} = "release"

@(
    "Prepare release checklist."
    "Update screenshots for the user guide."
    "Confirm release date with the team."
    "Archive last quarter notes."
) | Set-Content -Path ${N`o`TESpaTh} -Encoding UTF8

${MATcH`eS} = Select-String -LiteralPath ${n`o`TESPaTh} -Pattern ${k`EyW`ORd} |
    ForEach-Object { "Line $($_.LineNumber): $($_.Line)" }

${ma`Tches} | Set-Content -Path ${R`E`PORtpaTh} -Encoding UTF8

Write-Output "Searched notes for keyword: $keyword"
Write-Output "Match report: $reportPath"

