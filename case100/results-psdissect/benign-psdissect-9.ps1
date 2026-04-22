${A`RT`IfaC`Tdir} = . Join-Path ${PS`sCRiPTRO`OT} "artifacts\template"
if (-not (. Test-Path -LiteralPath ${ar`TIfACtD`IR})) {
    ${nU`ll} = . New-Item -ItemType Directory -Path ${A`RTiFAct`d`ir} -Force
}

${T`eMP`laTe} = @"
Welcome, {{Name}}.
Your workspace room is {{Room}}.
Report date: {{Date}}.
"@

${reSU`lT} = ${t`EMPLATE}.
    Replace("{{Name}}", "Analyst Team").
    Replace("{{Room}}", "B-204").
    Replace("{{Date}}", '2026-04-22')

${oU`T`PaTh} = . Join-Path ${a`RtI`FACTD`Ir} "welcome-message.txt"
${RES`UlT} | & Set-Content -Path ${oUtp`ATH} -Encoding UTF8

& Write-Output "Rendered welcome template."
& Write-Output "Output path: $outPath"

