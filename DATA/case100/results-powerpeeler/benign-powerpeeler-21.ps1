$aRTIFAcTdIr = Join-Path $pSSCRIptROOT "artifacts\greeting"
if (-not (Test-Path -LiteralPath $artIFaCTDir)) {
    $nUlL = New-Item -ItemType dIR`EC`TorY -Path $aRtiFACTdir -Force
}
$NaMe = "Research Demo"
$message = "Hello from simple benign sample, $name."
$TimestAmp = Get-Date -Format "s"
$oUTPaTH = Join-Path $aRtIFaCTDIR "greeting.txt"
@(
    $MessAgE
    "GeneratedAt=$timestamp"
) | Set-Content -Path $oUTPAth -Encoding Ut`F8
Write-Output $MESsaGE
Write-Output "Greeting file: $outPath"
