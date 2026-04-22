$artifactDir = j`oiN-PA`Th $PSScriptRoot "artifacts\log-lines"
$null = neW`-i`Tem -ItemType ('Direc'+'tor'+'y') -Path $artifactDir -Force
$logPath = j`OIn-PA`Th $artifactDir "recent.log"
@("alpha", "beta", "gamma", "delta", "epsilon") | set-Co`Nt`EnT -Path $logPath -Encoding ('UT'+'F8')
GEt-`CoNt`E`Nt -LiteralPath $logPath | S`ele`Ct-o`Bj`ecT -Last 3 | sEt-C`o`NTE`NT -Path $logPath -Encoding ('UTF'+'8')
wri`Te`-OutpUt "Kept latest 3 lines."
WrIt`e-O`UTP`Ut "Log path: $logPath"
