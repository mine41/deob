${Ar`Tif`Ac`TDIr} = Join-Path ${pS`sC`RIptrOOT} "artifacts\system"
if (-not (Test-Path -LiteralPath ${Ar`TIFac`Tdir})) {
    ${N`Ull} = New-Item -ItemType Directory -Path ${a`RTif`AcTDiR} -Force
}

${R`EpO`RTPA`TH} = Join-Path ${arT`Ifa`c`TDiR} "system-report.txt"
${l`I`Nes} = @(
    'ComputerName=DESKTOP-S800FLV'
    'UserName=411'
    'PowerShellVersion=7.5.5'
    "CurrentLocation='C:\Users\411\Documents\安全\ps1Data\powerpeeler\测试\准确性测试'"
    "GeneratedAt='2026-04-22T00:13:13'"
)

${l`I`Nes} | Set-Content -Path ${RePO`Rtpa`TH} -Encoding UTF8

Write-Output "Saved system report."
Write-Output "Report path: $reportPath"

