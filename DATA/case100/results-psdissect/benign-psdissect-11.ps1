${artIfa`c`TDir} = Join-Path ${pSSCRIP`Tr`o`OT} "artifacts\logs"
if (-not (Test-Path -LiteralPath ${Ar`TIfa`CTDIr})) {
    ${Nu`lL} = New-Item -ItemType D`IR`ectoRy -Path ${arT`IFAct`Dir} -Force
}

${LOGp`A`TH} = Join-Path ${aRTI`Fact`D`ir} "app.log"
${ENTri`es} = @(
    "'2026-04-22T00:12:49' INFO Started demo log rotation."
    "'2026-04-22T00:12:49' INFO Loaded local sample settings."
    "'2026-04-22T00:12:49' INFO Rotation check completed."
)

${E`NTrIES} | Add-Content -Path ${L`oGP`AtH} -Encoding UTF8
${LATes`TLI`Nes} = Get-Content -LiteralPath ${L`OGP`AtH} | Select-Object -Last 5
${l`AT`es`TliNEs} | Set-Content -Path ${logPa`Th} -Encoding uTF8

Write-Output "Newest entries kept: 0"
Write-Output "Log path: $logPath"

