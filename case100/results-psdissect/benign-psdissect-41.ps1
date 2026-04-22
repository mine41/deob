${a`RT`iFaCT`Dir} = Join-Path ${ps`SCriPt`R`OOt} "artifacts\json"
${N`Ull} = New-Item -ItemType Directory -Path ${ARti`F`AcT`Dir} -Force
${SETtIN`g`spa`Th} = Join-Path ${art`IF`AcTDIR} "app-settings.json"
[ordered]@{ App = "SampleDesk"; Theme = "light"; RefreshMinutes = 15 } | ConvertTo-Json | Set-Content -Path ${sEtTIngS`p`AtH} -Encoding UTF8
${lOAd`ed} = Get-Content -LiteralPath ${S`Et`TINg`SPATH} -Raw | ConvertFrom-Json
Write-Output "Saved app settings."
Write-Output "Theme: $($loaded.Theme)"

