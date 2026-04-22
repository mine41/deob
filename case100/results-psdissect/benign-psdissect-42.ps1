${AR`TIfA`CtdIR} = Join-Path ${P`sscRiptrO`Ot} "artifacts\json"
${n`Ull} = New-Item -ItemType Directory -Path ${ar`Ti`FactD`iR} -Force
${PR`OfIL`EP`ATh} = Join-Path ${ArtI`FACt`dIr} "theme-profile.json"
[ordered]@{ Accent = "blue"; Font = "Consolas"; Density = "compact" } | ConvertTo-Json | Set-Content -Path ${pro`Fi`LEpA`Th} -Encoding UTF8
${Lo`Ad`eD} = Get-Content -LiteralPath ${PRofi`l`E`PaTH} -Raw | ConvertFrom-Json
Write-Output "Saved theme profile."
Write-Output "Accent: $($loaded.Accent)"

