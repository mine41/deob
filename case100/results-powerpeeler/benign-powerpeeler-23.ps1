$aRtifaCtDIR = Join-Path $pSScRiptRooT "artifacts\greeting"
if (-not (Test-Path -LiteralPath $ARTIfacTDIr)) {
    $NULl = New-Item -ItemType dIREc`TOrY -Path $ARTifAcTdIr -Force
}
$NAME = "Research Demo"
$MEsSagE = "Hello from simple benign sample, $name."
$timeStAmP = Get-Date -Format "s"
$oUtPaTh = Join-Path $ARtiFactDIr "greeting.txt"
@(
    $mesSAgE
    "GeneratedAt=$timestamp"
) | Set-Content -Path $ouTpATh -Encoding ut`F8
Write-Output $MessAgE
Write-Output "Greeting file: $outPath"
