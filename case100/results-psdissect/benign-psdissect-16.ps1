${a`R`Ti`FactDIR} = & Join-Path ${pSScr`Iptro`Ot} "artifacts\system"
if (-not (& Test-Path -LiteralPath ${ar`TiFaCt`DiR})) {
    ${n`Ull} = & New-Item -ItemType Directory -Path ${art`IFact`Dir} -Force
}

${r`EPO`RTpATh} = & Join-Path ${a`RtiF`Ac`TdIR} "system-report.txt"
${lIN`eS} = @(
    'ComputerName=DESKTOP-S800FLV'
    'UserName=411'
    'PowerShellVersion=7.5.5'
    "CurrentLocation='C:\Users\411\Documents\安全\ps1Data\powerpeeler\测试\准确性测试'"
    "GeneratedAt='2026-04-22T00:13:17'"
)

${LI`NES} | . Set-Content -Path ${R`Epor`Tp`ATh} -Encoding UTF8

& Write-Output "Saved system report."
& Write-Output "Report path: $reportPath"

