${aR`T`IfACTdIr} = & Join-Path ${PS`SCr`iPtRO`OT} "artifacts\hashes"
${INPu`Td`IR} = . Join-Path ${ar`TiFac`TD`IR} input
if (-not (& Test-Path -LiteralPath ${I`NP`UTd`iR})) {
    ${n`ULl} = . New-Item -ItemType Directory -Path ${iNp`U`T`DiR} -Force
}

. Set-Content -Path (. Join-Path ${InPU`T`diR} "alpha.txt") -Value "alpha document" -Encoding UTF8
& Set-Content -Path (& Join-Path ${In`PUtD`ir} "beta.txt") -Value "beta document" -Encoding UTF8

${rEPorT`p`AtH} = . Join-Path ${Artifa`ct`Dir} "hash-report.csv"
${hAsh`Es} = & Get-ChildItem -LiteralPath ${Inp`U`TDIr} -File |
    . Sort-Object Name |
    & Get-FileHash -Algorithm SHA256 |
    & Select-Object Path, Algorithm, Hash

${H`ASH`es} | . Export-Csv -Path ${RePO`Rt`Pa`TH} -NoTypeInformation -Encoding UTF8

. Write-Output "Exported SHA256 hashes."
& Write-Output "Report path: $reportPath"

