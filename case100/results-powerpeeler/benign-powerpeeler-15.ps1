$ArTifAcTDIr = jO`IN-`PaTH $pSsCRIptrOOT "artifacts\system"
if (-not (Test-Path -LiteralPath $ArTIFacTdir)) {
    $NUll = NEW`-It`EM -ItemType Directory -Path $aRTifAcTDiR -Force
}
$REpORTPATH = Join-Path $arTIfacTDiR "system-report.txt"
$lINes = @(
    "ComputerName=${env:COMPUTERNAME}"
    "UserName=${env:USERNAME}"
    "PowerShellVersion=$($PSVersionTable.PSVersion)"
    "CurrentLocation=$((Get-Location).Path)"
    "GeneratedAt=$(Get-Date -Format s)"
)
$lINes | Set-Content -Path $RePORtpaTH -Encoding UTF8
Write-Output "Saved system report."
Write-Output "Report path: $reportPath"
