${ART`if`AcTd`IR} = .("{1}{0}{2}" -f 'o','J','in-Path') ${P`s`ScRIPTrooT} "artifacts\greeting"
if (-not (.("{1}{0}{2}" -f'Pat','Test-','h') -LiteralPath ${Art`IFa`Ctd`ir})) {
    ${Nu`LL} = &("{2}{0}{1}" -f 't','em','New-I') -ItemType Directory -Path ${aRTIF`Ac`TDIR} -Force
}

${n`AME} = "Research Demo"
${mE`s`SAge} = "Hello from simple benign sample, $name."
${T`I`mesTAmp} = .("{2}{0}{1}"-f't-','Date','Ge') -Format "s"
${O`UT`pAth} = &("{0}{2}{1}{3}"-f 'Jo','P','in-','ath') ${Ar`TIFA`ctdIR} "greeting.txt"

@(
    ${me`ssA`Ge}
    "GeneratedAt=$timestamp"
) | &("{2}{1}{3}{0}"-f 'ntent','t','Se','-Co') -Path ${OUt`pA`TH} -Encoding UTF8

&("{3}{0}{2}{1}"-f '-','put','Out','Write') ${m`EsS`AGe}
.("{0}{2}{1}{3}" -f 'Wri','Out','te-','put') "Greeting file: $outPath"
