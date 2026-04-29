${a`R`Ti`FactDIR} = &("{2}{0}{1}{3}"-f'n-','Pa','Joi','th') ${pSScr`Iptro`Ot} "artifacts\system"
if (-not (&("{2}{0}{1}"-f's','t-Path','Te') -LiteralPath ${ar`TiFaCt`DiR})) {
    ${n`Ull} = &("{1}{2}{0}" -f'm','New-It','e') -ItemType Directory -Path ${art`IFact`Dir} -Force
}

${r`EPO`RTpATh} = &("{1}{0}{2}"-f 'n-','Joi','Path') ${a`RtiF`Ac`TdIR} "system-report.txt"
${lIN`eS} = @(
    "ComputerName=$env:COMPUTERNAME"
    "UserName=$env:USERNAME"
    "PowerShellVersion=$($PSVersionTable.PSVersion)"
    "CurrentLocation=$((Get-Location).Path)"
    "GeneratedAt=$(Get-Date -Format s)"
)

${LI`NES} | .("{0}{1}{2}"-f 'S','et','-Content') -Path ${R`Epor`Tp`ATh} -Encoding UTF8

&("{1}{2}{0}" -f 'put','Wr','ite-Out') "Saved system report."
&("{1}{0}{2}" -f 'ite-Ou','Wr','tput') "Report path: $reportPath"
