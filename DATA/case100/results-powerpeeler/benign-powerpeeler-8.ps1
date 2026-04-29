$artIFacTdir = Join-Path $psSCRiPtRoot "artifacts\hashes"
$iNpUtdIR = Join-Path $artifactdiR "input"
if (-not (Test-Path -LiteralPath $INPUtdIR)) {
    $NUlL = New-Item -ItemType D`IrecT`oRy -Path $INPutDiR -Force
}
Set-Content -Path (Join-Path $inputdIr "alpha.txt") -Value "alpha document" -Encoding U`Tf8
Set-Content -Path (Join-Path $inPUTDir "beta.txt") -Value "beta document" -Encoding u`Tf8
$REpORTpAtH = Join-Path $aRtIFAcTDIr "hash-report.csv"
$HAsHES = Get-ChildItem -LiteralPath $INPUtDir -File |
Sort-Object nA`Me |
Get-FileHash -Algorithm S`ha2`56 |
Select-Object p`ATh, AlgO`RIt`hm, H`AsH
$hAsheS | Export-Csv -Path $rePOrTPATh -NoTypeInformation -Encoding U`Tf8
Write-Output "Exported SHA256 hashes."
Write-Output "Report path: $reportPath"
