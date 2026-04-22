${aRt`IFAc`TdiR} = Join-Path ${Ps`SC`R`IptRoOT} "artifacts\system"
if (-not (Test-Path -LiteralPath ${Ar`TIFa`cTD`iR})) {
    ${NU`Ll} = New-Item -ItemType dIREcTOrY -Path ${a`RT`iFA`cTdIR} -Force
}

${RE`PoR`TP`Ath} = Join-Path ${ARtI`FACT`D`IR} "system-report.txt"
${Lin`ES} = @(
    'ComputerName=DESKTOP-S800FLV'
    'UserName=411'
    'PowerShellVersion=7.5.5'
    "CurrentLocation='C:\Users\411\Documents\安全\ps1Data\powerpeeler\测试\准确性测试'"
    "GeneratedAt='2026-04-22T00:13:28'"
)

${L`INEs} | Set-Content -Path ${Repor`TPA`TH} -Encoding utF8

Write-Output "Saved system report."
Write-Output "Report path: $reportPath"

