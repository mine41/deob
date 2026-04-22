${A`RTi`Fa`cTdir} = JOin-P`A`TH ${Ps`SCriPtRo`ot} "artifacts\release-preview"
${N`Ull} = neW`-i`TEM -ItemType Directory -Path ${artIfACt`D`ir} -Force
${NOTES`PA`Th} = joIn`-PaTH ${ArTi`FACTD`IR} "release-notes.txt"
${p`REVIEWpA`Th} = jOIN-pa`Th ${A`Rt`ifactDiR} "release-preview.txt"
@("intro", "features", "fixes", "faq") | s`Et-co`N`TeNT -Path ${n`OtesPA`Th} -Encoding UTF8
Ge`T`-`COntenT -LiteralPath ${n`o`TE`sPatH} | SeL`ec`T-OB`jecT -First 3 | SET-COnT`e`NT -Path ${PrEvI`eWP`ATh} -Encoding UTF8
W`RItE-ouT`Put "Selected first 3 release notes."
w`R`itE-OUtpuT "Preview path: $previewPath"
