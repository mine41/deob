${ArTifAcTDIr} = Join-Path ${pSsCRIptrOOT} "artifacts\system"
If ( -Not (Test-Path -LiteralPath ${ArTIFacTdir} )) {
    ${Null} = New-Item -ItemType Directory -Path ${aRTifAcTDiR} -Force
}

${REpORTPATH} = Join-Path ${arTIfacTDiR} "system-report.txt"
${lINes} = @(
    "ComputerName=$env:COMPUTERNAME"
    "UserName=$env:USERNAME"
    "PowerShellVersion=$($PSVersionTable.PSVersion)"
    "CurrentLocation=$((Get-Location).Path)"
    "GeneratedAt=$(Get-Date -Format s)"
)

${lINes} | st-content -Path ${RePORtpaTH} -Encoding UTF8

Write-Output "Saved system report."
Write-Output "Report path: $reportPath"
