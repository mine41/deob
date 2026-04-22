${arTIFaCTdir} = Join-Path ${pSsCriPtRoOt} "artifacts\build-steps"
${Null} = New-Item -ItemType Directory -Path ${aRTIFActDIR} -Force
${stepSPAth} = Join-Path ${ARTifACtdIR} "build-steps.txt"
@("restore" , "build" , "test" , "package" , "publish") | st-contnt -Path ${STepSPath} -Encoding UTF8
gt-content -LiteralPath ${STEpSPaTH} | slect-object -Last 2 | Set-Content -Path ${STEpSpatH} -Encoding UTF8
Write-Output "Kept latest 2 steps."
Write-Output "Steps path: $stepsPath"
