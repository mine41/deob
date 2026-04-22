${A`RT`IfaC`Tdir} = .("{2}{1}{0}"-f 'th','Pa','Join-') ${PS`sCRiPTRO`OT} "artifacts\template"
if (-not (.("{1}{2}{0}" -f'-Path','T','est') -LiteralPath ${ar`TIfACtD`IR})) {
    ${nU`ll} = .("{2}{1}{0}" -f'-Item','ew','N') -ItemType Directory -Path ${A`RTiFAct`d`ir} -Force
}

${T`eMP`laTe} = @"
Welcome, {{Name}}.
Your workspace room is {{Room}}.
Report date: {{Date}}.
"@

${reSU`lT} = ${t`EMPLATE}.
    Replace("{{Name}}", "Analyst Team").
    Replace("{{Room}}", "B-204").
    Replace("{{Date}}", (&("{2}{1}{0}"-f'-Date','t','Ge') -Format "yyyy-MM-dd"))

${oU`T`PaTh} = .("{0}{2}{1}" -f'Join-','ath','P') ${a`RtI`FACTD`Ir} "welcome-message.txt"
${RES`UlT} | &("{1}{0}{2}{3}"-f '-C','Set','onten','t') -Path ${oUtp`ATH} -Encoding UTF8

&("{0}{2}{3}{1}" -f 'Write','t','-','Outpu') "Rendered welcome template."
&("{2}{1}{0}"-f 'put','ut','Write-O') "Output path: $outPath"
