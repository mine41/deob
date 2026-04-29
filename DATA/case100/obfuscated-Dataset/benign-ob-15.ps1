${Ar`Tif`Ac`TDIr} = jO`IN-`PaTH ${pS`sC`RIptrOOT} "artifacts\system"
if (-not (TEs`T-PATH -LiteralPath ${Ar`TIFac`Tdir})) {
    ${N`Ull} = NEW`-It`EM -ItemType Directory -Path ${a`RTif`AcTDiR} -Force
}

${R`EpO`RTPA`TH} = J`oIn-p`ATh ${arT`Ifa`c`TDiR} "system-report.txt"
${l`I`Nes} = @(
    "ComputerName=$env:COMPUTERNAME"
    "UserName=$env:USERNAME"
    "PowerShellVersion=$($PSVersionTable.PSVersion)"
    "CurrentLocation=$((Get-Location).Path)"
    "GeneratedAt=$(Get-Date -Format s)"
)

${l`I`Nes} | s`e`T-cONTENt -Path ${RePO`Rtpa`TH} -Encoding UTF8

WRIte-`Ou`T`PUT "Saved system report."
Wri`T`E-OU`TPUt "Report path: $reportPath"
