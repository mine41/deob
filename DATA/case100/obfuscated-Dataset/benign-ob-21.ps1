${a`R`TIF`AcTdIr} = Join-Path ${p`SSC`RIptROOT} "artifacts\greeting"
if (-not (Test-Path -LiteralPath ${art`IFa`CT`Dir})) {
    ${n`UlL} = New-Item -ItemType dIR`EC`TorY -Path ${a`RtiFAC`Tdir} -Force
}

${Na`Me} = "Research Demo"
${mes`sa`ge} = "Hello from simple benign sample, $name."
${T`ime`stAmp} = Get-Date -Format "s"
${oU`T`PaTH} = Join-Path ${aRtI`FaC`TD`IR} "greeting.txt"

@(
    ${M`ess`AgE}
    "GeneratedAt=$timestamp"
) | Set-Content -Path ${o`U`TPAth} -Encoding Ut`F8

Write-Output ${M`ESsaGE}
Write-Output "Greeting file: $outPath"
