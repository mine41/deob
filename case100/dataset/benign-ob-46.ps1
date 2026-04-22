$artifactDir = Joi`N`-PAth $PSScriptRoot "artifacts\json"
$null = N`E`w-iTeM -ItemType ('D'+'irec'+'to'+'ry') -Path $artifactDir -Force
$layoutPath = J`o`IN-Pa`Th $artifactDir "window-layout.json"
[ordered]@{ View = "dashboard"; Sidebar = "open"; Zoom = 125 } | c`onv`eRTt`o`-jSoN | S`ET`-cOnTENt -Path $layoutPath -Encoding ('UT'+'F8')
$loaded = geT-c`o`NtENT -LiteralPath $layoutPath -Raw | cOnV`eR`TfRoM-`json
W`R`Ite-`outPUt "Saved window layout."
wr`ITe-o`UTp`UT "View: $($loaded.View)"
