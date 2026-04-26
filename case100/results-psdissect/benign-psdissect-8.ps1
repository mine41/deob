${artIFa`cTd`ir} = Join-Path ${psSC`R`iPtR`oot} "artifacts\hashes"
${iNpUt`dIR} = Join-Path ${artifa`ct`diR} input
if (-not (Test-Path -LiteralPath ${I`N`PUt`dIR})) {
    ${N`UlL} = New-Item -ItemType DIrecToRy -Path ${I`NPutDiR} -Force
}

Set-Content -Path (Join-Path ${input`d`Ir} "alpha.txt") -Value "alpha document" -Encoding UTf8
Set-Content -Path (Join-Path ${inP`UT`Dir} "beta.txt") -Value "beta document" -Encoding uTf8

${REpO`RT`p`AtH} = Join-Path ${aRtI`F`AcTD`Ir} "hash-report.csv"
${H`AsHES} = Get-ChildItem -LiteralPath ${I`NPUtDir} -File |
    Sort-Object nAMe |
    Get-FileHash -Algorithm Sha256 |
    Select-Object pATh, AlgORIthm, HAsH

${h`Ash`eS} | Export-Csv -Path ${re`P`OrTPA`Th} -NoTypeInformation -Encoding UTf8

Write-Output "Exported SHA256 hashes."
Write-Output "Report path: $reportPath"

