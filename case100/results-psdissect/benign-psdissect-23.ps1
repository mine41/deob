${a`RtifaCt`D`IR} = Join-Path ${pSSc`R`i`pt`RooT} "artifacts\greeting"
if (-not (Test-Path -LiteralPath ${ARTIfac`TD`Ir})) {
    ${NU`Ll} = New-Item -ItemType dIREcTOrY -Path ${AR`Tif`Ac`TdIr} -Force
}

${NA`ME} = "Research Demo"
${ME`sSagE} = 'Hello from simple benign sample, Research Demo.'
${t`i`meStA`mP} = Get-Date -Format s
${oUtPa`Th} = Join-Path ${ARt`i`FactDIr} "greeting.txt"

@(
    'Hello from simple benign sample, Research Demo.'
    'GeneratedAt=2026-04-22T00:14:08'
) | Set-Content -Path ${ouT`p`ATh} -Encoding utF8

Write-Output ${M`essAgE}
Write-Output "Greeting file: $outPath"

