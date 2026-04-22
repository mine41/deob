${aRTIFAcTdIr} = Join-Path ${pSSCRIptROOT} "artifacts\greeting"
If ( -Not (Test-Path -LiteralPath ${artIFaCTDir} )) {
    ${Null} = New-Item -ItemType dIR`EC`TorY -Path ${aRtiFACTdir} -Force
}

${NaMe} = "Research Demo"
${message} = "Hello from simple benign sample, $name."
${TimestAmp} = Get-Date -Format "s"
${oUTPaTH} = Join-Path ${aRtIFaCTDIR} "greeting.txt"

@(
    ${MssAgE} 
    "GeneratedAt=$timestamp"
) | Set-Content -Path ${oUTPAth} -Encoding Ut`F8

Write-Output ${MESsaGE} 
Write-Output "Greeting file: $outPath"
