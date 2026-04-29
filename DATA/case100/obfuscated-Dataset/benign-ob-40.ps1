$artifactDir = Jo`in-p`ATH $PSScriptRoot "artifacts\json"
$null = ne`W-itEm -ItemType ('Dire'+'ctor'+'y') -Path $artifactDir -Force
$rulesPath = Join-`PatH $artifactDir "alert-rules.json"
[ordered]@{ Channel = "email"; Level = "info"; QuietHours = "22:00-07:00" } | cOn`VEr`Tto-`jSOn | sEt-`C`Ontent -Path $rulesPath -Encoding ('U'+'TF8')
$loaded = g`eT-COn`Te`Nt -LiteralPath $rulesPath -Raw | c`Onv`e`RTfR`OM-JSon
W`Rit`E`-ouTPUT "Saved alert rules."
w`Rite-`OuTpuT "Channel: $($loaded.Channel)"
