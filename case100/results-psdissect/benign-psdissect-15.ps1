${Ar`Tif`Ac`TDIr} = Join-Path ${pS`sC`RIptrOOT} "artifacts\system"
if (-not (Test-Path -LiteralPath ${Ar`TIFac`Tdir})) {
    ${N`Ull} = New-Item -ItemType Directory -Path ${a`RTif`AcTDiR} -Force
}

${R`EpO`RTPA`TH} = Join-Path ${arT`Ifa`c`TDiR} "system-report.txt"
${l`I`Nes} = @(
    'ComputerName=HOST-EXAMPLE'
    'UserName=user'
    'PowerShellVersion=7.x'
    "CurrentLocation='C:\Users\Public\Documents\sample-data\demo-path'"
    "GeneratedAt='2026-01-01T00:00:00'"
)

${l`I`Nes} | Set-Content -Path ${RePO`Rtpa`TH} -Encoding UTF8

Write-Output "Saved system report."
Write-Output "Report path: $reportPath"

