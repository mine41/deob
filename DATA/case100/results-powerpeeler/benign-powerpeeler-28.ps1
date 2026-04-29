$arTIFaCTdir = JoiN-p`A`Th $pSsCriPtRoOt "artifacts\build-steps"
$NuLL = New-Item -ItemType Directory -Path $aRTIFActDIR -Force
$stepSPAth = Join-Path $ARTifACtdIR "build-steps.txt"
@("restore", "build", "test", "package", "publish") | Set-Content -Path $STepSPath -Encoding UTF8
Get-Content -LiteralPath $STEpSPaTH | Select-Object -Last 2 | Set-Content -Path $STEpSpatH -Encoding UTF8
Write-Output "Kept latest 2 steps."
Write-Output "Steps path: $stepsPath"
