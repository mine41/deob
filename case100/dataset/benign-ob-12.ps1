${Ar`T`iF`AcTdIr} = joIn-p`A`Th ${pS`Scr`I`pt`ROoT} "artifacts\settings"
if (-not (Test-`PA`TH -LiteralPath ${Ar`TIfactd`ir})) {
    ${n`ULL} = nEw-it`EM -ItemType Directory -Path ${ARTiF`Ac`T`DIr} -Force
}

${Se`TtING`SPA`Th} = J`oi`N`-PATH ${ARTifA`cT`diR} "app-settings.json"
${S`ETtINGS} = [ordered]@{
    Application = "SimpleBenignBenchmark"
    Theme = "light"
    AutoSaveMinutes = 10
    StartPage = "dashboard"
}

${S`Et`TInGs} | CO`N`Vert`TO-j`SOn | SE`T`-coNteNT -Path ${sEt`TiN`GSPATh} -Encoding UTF8
${loa`ded} = gET-CO`NTe`NT -LiteralPath ${seTT`In`Gsp`Ath} -Raw | coN`V`ERTfRoM-j`S`On

writE-`oUt`pUt "Saved settings JSON."
WRite-`OU`TPut "Application: $($loaded.Application)"
wRITE`-O`UtP`UT "Theme: $($loaded.Theme)"
wr`it`E-ouTPuT "Settings path: $settingsPath"
