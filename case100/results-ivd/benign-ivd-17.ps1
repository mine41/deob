${aRtIFAcTdiR} = Join-Path ${PsSCRIptRoOT} "artifacts\system"
If ( -Not (Test-Path -LiteralPath ${ArTIFacTDiR} )) {
    ${Null} = New-Item -ItemType dIREc`T`OrY -Path ${aRTiFAcTdIR} -Force
}

${REPoRTPAth} = Join-Path ${ARtIFACTDIR} "system-report.txt"
${LinES} = @(
    "ComputerName=$env:COMPUTERNAME"
    "UserName=$env:USERNAME"
    "PowerShellVersion=$($PSVersionTable.PSVersion)"
    "CurrentLocation=$((Get-Location).Path)"
    "GeneratedAt=$(Get-Date -Format s)"
)

${LINEs} | Set-Content -Path ${ReporTPATH} -Encoding ut`F8

Write-Output "Saved system report."
Write-Output "Report path: $reportPath"
