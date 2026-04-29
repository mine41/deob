$aRtIFAcTdiR = Join-Path $PsSCRIptRoOT "artifacts\system"
if (-not (Test-Path -LiteralPath $ArTIFacTDiR)) {
    $NULl = New-Item -ItemType dIREc`T`OrY -Path $aRTiFAcTdIR -Force
}
$REPoRTPAth = Join-Path $ARtIFACTDIR "system-report.txt"
$LinES = @(
    "ComputerName=${env:COMPUTERNAME}"
    "UserName=${env:USERNAME}"
    "PowerShellVersion=$($PSVersionTable.PSVersion)"
    "CurrentLocation=$((Get-Location).Path)"
    "GeneratedAt=$(Get-Date -Format s)"
)
$LINEs | Set-Content -Path $ReporTPATH -Encoding ut`F8
Write-Output "Saved system report."
Write-Output "Report path: $reportPath"
