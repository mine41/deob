${a`RT`iFaCT`Dir} = J`OIn-`pa`Th ${ps`SCriPt`R`OOt} "artifacts\json"
${N`Ull} = N`EW-I`Tem -ItemType Directory -Path ${ARti`F`AcT`Dir} -Force
${SETtIN`g`spa`Th} = j`OI`N-Path ${art`IF`AcTDIR} "app-settings.json"
[ordered]@{ App = "SampleDesk"; Theme = "light"; RefreshMinutes = 15 } | CoNVertt`O-J`SoN | sE`T-CoNt`ENT -Path ${sEtTIngS`p`AtH} -Encoding UTF8
${lOAd`ed} = geT`-CoN`T`eNT -LiteralPath ${S`Et`TINg`SPATH} -Raw | CO`NV`eRTF`Rom-JSoN
wRit`E-O`UtpUt "Saved app settings."
wRI`T`E-OuTPUt "Theme: $($loaded.Theme)"
