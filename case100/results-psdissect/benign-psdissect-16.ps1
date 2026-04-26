${a`R`Ti`FactDIR} = & Join-Path ${pSScr`Iptro`Ot} "artifacts\system"
if (-not (& Test-Path -LiteralPath ${ar`TiFaCt`DiR})) {
    ${n`Ull} = & New-Item -ItemType Directory -Path ${art`IFact`Dir} -Force
}

${r`EPO`RTpATh} = & Join-Path ${a`RtiF`Ac`TdIR} "system-report.txt"
${lIN`eS} = @(
    'ComputerName=HOST-EXAMPLE'
    'UserName=user'
    'PowerShellVersion=7.x'
    "CurrentLocation='C:\Users\Public\Documents\sample-data\demo-path'"
    "GeneratedAt='2026-01-01T00:00:00'"
)

${LI`NES} | . Set-Content -Path ${R`Epor`Tp`ATh} -Encoding UTF8

& Write-Output "Saved system report."
& Write-Output "Report path: $reportPath"

