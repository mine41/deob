$artifactDir = j`O`In-path $PSScriptRoot "artifacts\json"
$null = New-`ITem -ItemType ('Di'+'rector'+'y') -Path $artifactDir -Force
$rulesPath = j`oIN-PA`TH $artifactDir "alert-rules.json"
[ordered]@{ Channel = "email"; Level = "info"; QuietHours = "22:00-07:00" } | Co`N`V`eRtTO-Js`oN | sEt-cOnt`E`Nt -Path $rulesPath -Encoding ('UT'+'F8')
$loaded = GET`-`Co`Ntent -LiteralPath $rulesPath -Raw | COnV`erTf`Rom`-j`son
w`RITe-OU`TPuT "Saved alert rules."
Wri`TE`-OU`TpuT "Channel: $($loaded.Channel)"
