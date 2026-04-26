${aRt`IFAc`TdiR} = Join-Path ${Ps`SC`R`IptRoOT} "artifacts\system"
if (-not (Test-Path -LiteralPath ${Ar`TIFa`cTD`iR})) {
    ${NU`Ll} = New-Item -ItemType dIREcTOrY -Path ${a`RT`iFA`cTdIR} -Force
}

${RE`PoR`TP`Ath} = Join-Path ${ARtI`FACT`D`IR} "system-report.txt"
${Lin`ES} = @(
    'ComputerName=HOST-EXAMPLE'
    'UserName=user'
    'PowerShellVersion=7.x'
    "CurrentLocation='C:\Users\Public\Documents\sample-data\demo-path'"
    "GeneratedAt='2026-01-01T00:00:00'"
)

${L`INEs} | Set-Content -Path ${Repor`TPA`TH} -Encoding utF8

Write-Output "Saved system report."
Write-Output "Report path: $reportPath"

