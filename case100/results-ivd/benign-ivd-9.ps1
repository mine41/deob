${ARTIfaCTdir} = .("{2}{1}{0}" -f 'th' , 'Pa' , 'Join-') ${PSsCRiPTROOT} "artifacts\template"
If ( -Not (.("{1}{2}{0}" -f '-Path' , 'T' , 'est') -LiteralPath ${arTIfACtDIR} )) {
    ${Null} = .("{2}{1}{0}" -f '-Item' , 'ew' , 'N') -ItemType Directory -Path ${ARTiFActdir} -Force
}

${TMPlaTe} = 'Welcome, {{Name}}.
Your workspace room is {{Room}}.
Report date: {{Date}}.'

${reSUlT} = ${tEMPLATE}.
Replace("{{Name}}" , "Analyst Team").
Replace("{{Room}}" , "B-204").
Replace("{{Date}}" , ( & ("{2}{1}{0}" -f '-Date' , 't' , 'Ge') -Format "yyyy-MM-dd"))

${oUTPaTh} = .("{0}{2}{1}" -f 'Join-' , 'ath' , 'P') ${aRtIFACTDIr} "welcome-message.txt"
${RESUlT} | & ("{1}{0}{2}{3}" -f '-C' , 'Set' , 'onten' , 't') -Path ${oUtpATH} -Encoding UTF8

& ("{0}{2}{3}{1}" -f 'Write' , 't' , '-' , 'Outpu') "Rendered welcome template."
& ("{2}{1}{0}" -f 'put' , 'ut' , 'Write-O') "Output path: $outPath"
