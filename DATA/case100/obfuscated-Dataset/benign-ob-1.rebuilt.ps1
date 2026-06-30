${aRT`IfAC`T`dIR} = '%USERPROFILE%\Documents\experiment\new\deob\DATA\case100\obfuscated-Dataset\artifacts\tasks'
if ($True) {
    ${nu`Ll} = $null
}

${pla`Nned} = @("draft", "review", "publish", "archive")
${cOM`P`LET`ed} = @("draft", "review", "archive", "notify")

${p`ENdI`NG} = ${Pl`AnnEd} | Where-Object { ${_} -notin ${C`o`MPlEtEd} }
${un`eX`PECTED} = ${c`O`MPleted} | Where-Object { ${_} -notin ${PLAN`NeD} }
${r`Ep`ORtpa`TH} = '%USERPROFILE%\Documents\experiment\new\deob\DATA\case100\obfuscated-Dataset\artifacts\tasks\task-comparison.txt'

@(
    "Pending Tasks: 'draft, review, publish, archive'"
    "Unexpected Tasks: ''"
) | Set-Content -Path '%USERPROFILE%\Documents\experiment\new\deob\DATA\case100\obfuscated-Dataset\artifacts\tasks\task-comparison.txt' -Encoding uTF8

Write-Output 'Compared task lists.'
Write-Output 'Report path: %USERPROFILE%\Documents\experiment\new\deob\DATA\case100\obfuscated-Dataset\artifacts\tasks\task-comparison.txt'

<# PSDissect-SensitiveEvidence
FilePath: %USERPROFILE%\Documents\experiment\new\deob\DATA\case100\obfuscated-Dataset\artifacts\tasks
FilePath: %USERPROFILE%\Documents\experiment\new\deob\DATA\case100\obfuscated-Dataset\artifacts\tasks\task-comparison.txt
FilePath: C:\Users\411\Documents\experiment\new\deob\DATA\case100\obfuscated-Dataset\artifacts\tasks
FilePath: C:\Users\411\Documents\experiment\new\deob\DATA\case100\obfuscated-Dataset\artifacts\tasks\task-comparison.txt
#>
