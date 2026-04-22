$aRTiFactDIR = &("{2}{0}{1}{3}"-f'n-','Pa','Joi','th') $pSScrIptroOt "artifacts\system"
if (-not (&("{2}{0}{1}"-f's','t-Path','Te') -LiteralPath $arTiFaCtDiR)) {
    $nUll = &("{1}{2}{0}" -f'm','New-It','e') -ItemType Directory -Path $artIFactDir -Force
}
$rEPORTpATh = &("{1}{0}{2}"-f 'n-','Joi','Path') $aRtiFAcTdIR "system-report.txt"
$lINeS = @(
    "ComputerName=${env:COMPUTERNAME}"
    "UserName=${env:USERNAME}"
    "PowerShellVersion=$($PSVersionTable.PSVersion)"
    "CurrentLocation=$((Get-Location).Path)"
    "GeneratedAt=$(Get-Date -Format s)"
)
$LINES | .("{0}{1}{2}"-f 'S','et','-Content') -Path $REporTpATh -Encoding UTF8
&("{1}{2}{0}" -f 'put','Wr','ite-Out') "Saved system report."
&("{1}{0}{2}" -f 'ite-Ou','Wr','tput') "Report path: $reportPath"
