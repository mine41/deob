$artIfacTDir = Join-Path $pSSCRIPTroOT "artifacts\logs"
if (-not (Test-Path -LiteralPath $ArTIfaCTDIr)) {
    $NulL = New-Item -ItemType D`IR`ectoRy -Path $arTIFActDir -Force
}
$LOGpATH = Join-Path $aRTIFactDir "app.log"
$ENTries = @(
    "$(Get-Date -Format s) INFO Started demo log rotation."
    "$(Get-Date -Format s) INFO Loaded local sample settings."
    "$(Get-Date -Format s) INFO Rotation check completed."
)
$ENTrIES | Add-Content -Path $LoGPAtH -Encoding U`TF8
$LATesTLINes = Get-Content -LiteralPath $LOGPAtH | Select-Object -Last 5
$lATesTliNEs | Set-Content -Path $logPaTh -Encoding u`TF8
Write-Output "Newest entries kept: $($latestLines.Count)"
Write-Output "Log path: $logPath"
