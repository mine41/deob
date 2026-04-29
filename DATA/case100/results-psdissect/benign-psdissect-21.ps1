${a`R`TIF`AcTdIr} = Join-Path ${p`SSC`RIptROOT} "artifacts\greeting"
if (-not (Test-Path -LiteralPath ${art`IFa`CT`Dir})) {
    ${n`UlL} = New-Item -ItemType dIRECTorY -Path ${a`RtiFAC`Tdir} -Force
}

${Na`Me} = "Research Demo"
${mes`sa`ge} = 'Hello from simple benign sample, Research Demo.'
${T`ime`stAmp} = Get-Date -Format s
${oU`T`PaTH} = Join-Path ${aRtI`FaC`TD`IR} "greeting.txt"

@(
    ${M`ess`AgE}
    'GeneratedAt=2026-04-22T00:14:01'
) | Set-Content -Path ${o`U`TPAth} -Encoding UtF8

Write-Output 'Hello from simple benign sample, Research Demo.'
Write-Output "Greeting file: $outPath"

