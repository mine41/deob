${artIfa`c`TDir} = Join-Path ${pSSCRIP`Tr`o`OT} "artifacts\logs"
if (-not (Test-Path -LiteralPath ${Ar`TIfa`CTDIr})) {
    ${Nu`lL} = New-Item -ItemType D`IR`ectoRy -Path ${arT`IFAct`Dir} -Force
}

${LOGp`A`TH} = Join-Path ${aRTI`Fact`D`ir} "app.log"
${ENTri`es} = @(
    "$(Get-Date -Format s) INFO Started demo log rotation."
    "$(Get-Date -Format s) INFO Loaded local sample settings."
    "$(Get-Date -Format s) INFO Rotation check completed."
)

${E`NTrIES} | Add-Content -Path ${L`oGP`AtH} -Encoding U`TF8
${LATes`TLI`Nes} = Get-Content -LiteralPath ${L`OGP`AtH} | Select-Object -Last 5
${l`AT`es`TliNEs} | Set-Content -Path ${logPa`Th} -Encoding u`TF8

Write-Output "Newest entries kept: $($latestLines.Count)"
Write-Output "Log path: $logPath"
