$artifactDir = J`oiN-pA`Th $PSScriptRoot "artifacts\json"
$null = N`ew-IT`eM -ItemType ('D'+'ir'+'ectory') -Path $artifactDir -Force
$profilePath = J`oIN-`pAth $artifactDir "theme-profile.json"
[ordered]@{ Accent = "blue"; Font = "Consolas"; Density = "compact" } | conv`eRt`T`o-j`sON | SEt`-CO`NT`ent -Path $profilePath -Encoding ('UT'+'F8')
$loaded = GEt-`C`oNteNT -LiteralPath $profilePath -Raw | coNVErTFR`o`M-JS`ON
wR`Ite-`O`UtPut "Saved theme profile."
wrItE-`O`UT`PUt "Accent: $($loaded.Accent)"
