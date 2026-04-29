$ARTifAcTdIR = .("{1}{0}{2}" -f 'o','J','in-Path') $PsScRIPTrooT "artifacts\greeting"
if (-not (.("{1}{0}{2}" -f'Pat','Test-','h') -LiteralPath $ArtIFaCtdir)) {
    $NuLL = &("{2}{0}{1}" -f 't','em','New-I') -ItemType Directory -Path $aRTIFAcTDIR -Force
}
$nAME = "Research Demo"
$mEsSAge = "Hello from simple benign sample, $name."
$TImesTAmp = .("{2}{0}{1}"-f't-','Date','Ge') -Format "s"
$OUTpAth = &("{0}{2}{1}{3}"-f 'Jo','P','in-','ath') $ArTIFActdIR "greeting.txt"
@(
    $messAGe
    "GeneratedAt=$timestamp"
) | &("{2}{1}{3}{0}"-f 'ntent','t','Se','-Co') -Path $OUtpATH -Encoding UTF8
&("{3}{0}{2}{1}"-f '-','put','Out','Write') $mEsSAGe
.("{0}{2}{1}{3}" -f 'Wri','Out','te-','put') "Greeting file: $outPath"
