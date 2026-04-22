${a`RtifaCt`D`IR} = Join-Path ${pSSc`R`i`pt`RooT} "artifacts\greeting"
if (-not (Test-Path -LiteralPath ${ARTIfac`TD`Ir})) {
    ${NU`Ll} = New-Item -ItemType dIREc`TOrY -Path ${AR`Tif`Ac`TdIr} -Force
}

${NA`ME} = "Research Demo"
${ME`sSagE} = "Hello from simple benign sample, $name."
${t`i`meStA`mP} = Get-Date -Format "s"
${oUtPa`Th} = Join-Path ${ARt`i`FactDIr} "greeting.txt"

@(
    ${me`sSA`gE}
    "GeneratedAt=$timestamp"
) | Set-Content -Path ${ouT`p`ATh} -Encoding ut`F8

Write-Output ${M`essAgE}
Write-Output "Greeting file: $outPath"
