${aRt`IFAc`TdiR} = Join-Path ${Ps`SC`R`IptRoOT} "artifacts\system"
if (-not (Test-Path -LiteralPath ${Ar`TIFa`cTD`iR})) {
    ${NU`Ll} = New-Item -ItemType dIREc`T`OrY -Path ${a`RT`iFA`cTdIR} -Force
}

${RE`PoR`TP`Ath} = Join-Path ${ARtI`FACT`D`IR} "system-report.txt"
${Lin`ES} = @(
    "ComputerName=$env:COMPUTERNAME"
    "UserName=$env:USERNAME"
    "PowerShellVersion=$($PSVersionTable.PSVersion)"
    "CurrentLocation=$((Get-Location).Path)"
    "GeneratedAt=$(Get-Date -Format s)"
)

${L`INEs} | Set-Content -Path ${Repor`TPA`TH} -Encoding ut`F8

Write-Output "Saved system report."
Write-Output "Report path: $reportPath"
