${ARTIfACtdIR} = Join-Path ${PsscRiptrOOt} "artifacts\json"
${Null} = New-Item -ItemType Directory -Path ${arTiFactDiR} -Force
${PROfILEPATh} = Join-Path ${ArtIFACtdIr} "theme-profile.json"
[ordered]@{ accent = "blue"; 
    font = "Consolas"; 
    density = "compact" } | convrtto-json | Set-Content -Path ${proFiLEpATh} -Encoding UTF8
${LoAdD} = get-contnt -LiteralPath ${PRofilEPaTH} -Raw | ConvertFrom-Json 
writ-output "Saved theme profile."
writ-output "Accent: $($loaded.Accent)"
