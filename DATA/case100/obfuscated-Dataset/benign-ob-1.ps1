${aRT`IfAC`T`dIR} = Join-Path ${Ps`sc`Riptroot} "artifacts\tasks"
if (-not (Test-Path -LiteralPath ${art`i`Fa`CtdiR})) {
    ${nu`Ll} = New-Item -ItemType diREC`ToRY -Path ${a`Rti`FAc`TDIR} -Force
}

${pla`Nned} = @("draft", "review", "publish", "archive")
${cOM`P`LET`ed} = @("draft", "review", "archive", "notify")

${p`ENdI`NG} = ${Pl`AnnEd} | Where-Object { ${_} -notin ${C`o`MPlEtEd} }
${un`eX`PECTED} = ${c`O`MPleted} | Where-Object { ${_} -notin ${PLAN`NeD} }
${r`Ep`ORtpa`TH} = Join-Path ${aR`TiFaC`TD`ir} "task-comparison.txt"

@(
    "Pending Tasks: $($pending -join ', ')"
    "Unexpected Tasks: $($unexpected -join ', ')"
) | Set-Content -Path ${r`Ep`ORTpaTH} -Encoding u`TF8

Write-Output "Compared task lists."
Write-Output "Report path: $reportPath"
