${artIFa`cTd`ir} = Join-Path ${psSC`R`iPtR`oot} "artifacts\hashes"
${iNpUt`dIR} = Join-Path ${artifa`ct`diR} "input"
if (-not (Test-Path -LiteralPath ${I`N`PUt`dIR})) {
    ${N`UlL} = New-Item -ItemType D`IrecT`oRy -Path ${I`NPutDiR} -Force
}

Set-Content -Path (Join-Path ${input`d`Ir} "alpha.txt") -Value "alpha document" -Encoding U`Tf8
Set-Content -Path (Join-Path ${inP`UT`Dir} "beta.txt") -Value "beta document" -Encoding u`Tf8

${REpO`RT`p`AtH} = Join-Path ${aRtI`F`AcTD`Ir} "hash-report.csv"
${H`AsHES} = Get-ChildItem -LiteralPath ${I`NPUtDir} -File |
    Sort-Object nA`Me |
    Get-FileHash -Algorithm S`ha2`56 |
    Select-Object p`ATh, AlgO`RIt`hm, H`AsH

${h`Ash`eS} | Export-Csv -Path ${re`P`OrTPA`Th} -NoTypeInformation -Encoding U`Tf8

Write-Output "Exported SHA256 hashes."
Write-Output "Report path: $reportPath"
