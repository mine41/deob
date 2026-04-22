${ART`if`AcTd`IR} = . Join-Path ${P`s`ScRIPTrooT} "artifacts\greeting"
if (-not (. Test-Path -LiteralPath ${Art`IFa`Ctd`ir})) {
    ${Nu`LL} = & New-Item -ItemType Directory -Path ${aRTIF`Ac`TDIR} -Force
}

${n`AME} = "Research Demo"
${mE`s`SAge} = 'Hello from simple benign sample, Research Demo.'
${T`I`mesTAmp} = . Get-Date -Format s
${O`UT`pAth} = & Join-Path ${Ar`TIFA`ctdIR} "greeting.txt"

@(
    'Hello from simple benign sample, Research Demo.'
    'GeneratedAt=2026-04-22T00:13:58'
) | & Set-Content -Path ${OUt`pA`TH} -Encoding UTF8

& Write-Output 'Hello from simple benign sample, Research Demo.'
. Write-Output "Greeting file: $outPath"

