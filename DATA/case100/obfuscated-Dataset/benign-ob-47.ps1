$artifactDir = jOi`N`-pATH $PSScriptRoot "artifacts\json"
$null = n`eW-ITEm -ItemType ('Direct'+'o'+'ry') -Path $artifactDir -Force
$layoutPath = JoI`N-pa`Th $artifactDir "window-layout.json"
[ordered]@{ View = "dashboard"; Sidebar = "open"; Zoom = 125 } | c`onV`eRTTo-`json | S`e`T-coN`TenT -Path $layoutPath -Encoding ('U'+'TF8')
$loaded = gEt`-c`On`TenT -LiteralPath $layoutPath -Raw | cOnv`ErTfr`o`m-JSOn
WRI`TE-oUt`Put "Saved window layout."
wRiTe`-`OUt`PUT "View: $($loaded.View)"
