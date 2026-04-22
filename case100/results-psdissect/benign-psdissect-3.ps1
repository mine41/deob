${a`R`TiFA`ctDir} = Join-Path ${P`S`scRI`PT`ROot} "artifacts\tasks"
if (-not (Test-Path -LiteralPath ${ArTIFA`C`Tdir})) {
    ${n`Ull} = New-Item -ItemType DirecTorY -Path ${aR`TI`FAc`TdIR} -Force
}

${p`LAN`NeD} = @("draft", "review", "publish", "archive")
${Com`PL`ETEd} = @("draft", "review", "archive", "notify")

${p`eN`dInG} = ${pl`AnnED} | Where-Object { ${_} -notin ${C`oMp`lE`TeD} }
${un`e`XpeC`TED} = ${Co`MPle`T`ED} | Where-Object { ${_} -notin ${p`L`AnNED} }
${r`eporT`PatH} = Join-Path ${ARTi`FaCT`dIr} "task-comparison.txt"

@(
    "Pending Tasks: ''"
    "Unexpected Tasks: ''"
) | Set-Content -Path ${R`ePO`R`TpAth} -Encoding uTf8

Write-Output "Compared task lists."
Write-Output "Report path: $reportPath"

