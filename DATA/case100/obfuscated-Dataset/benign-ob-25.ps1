('kdmartifactDir = &(1Ca{1}{0}{2}1Ca -fbR0inbR0,bR0JobR0,bR0-'+'PathbR0) kdmPSSc'+'riptRoot 1CaartifactsPb5s'+'ettings1Ca
if (-not (&'+'(1Ca{0}{1}{2}1Ca-fbR0TesbR0,bR0t-PatbR0,bR0hbR0) -Liter'+'alPath kdmartifactDir)) {
    kdmnull = &(1Ca{1}{2}{0}1Ca-f bR0mbR0,bR0New-ItbR0,bR0ebR0) -ItemT'+'ype Directory -Path kdmarti'+'factDir -Force
}

kdmsettingsPath = &(1Ca{2}{1}'+'{0}1C'+'a -fbR0hbR0'+',bR0in-PatbR0,bR0JobR0) kdmart'+'ifactDir 1Caapp-settings.json1Ca
kdmse'+'ttings = [ordered]@{
    Application ='+' 1CaSimpleBenignBenchmark1Ca
    Theme = 1Calight1Ca
    Au'+'toSave'+'Minutes = 10
    StartPage = 1Cadashboard1Ca
}

kdmsettings DoN &(1Ca{1}{2}{0}1Ca -fbR0o-JsonbR0,bR0ConbR0,bR0ve'+'rtTbR0) DoN .(1Ca{1}{0}{3}{2}1Ca -fbR0obR0,bR0Set-CbR0,bR0tentbR0,bR0nbR0) -Path kdms'+'ettings'+'Path -Encoding UTF8
kdmloa'+'ded = &(1Ca{0}{2}{3}{1}1Ca -f bR0GebR0'+',bR'+'0entbR0,'+'bR0tbR0,bR0-ContbR0) -Li'+'teralPath '+'kdmsettingsPath -Raw DoN &(1Ca{1}{2}{3}{0}1Ca-f bR0-JsonbR0,bR0ConvertbR0'+',bR0FrobR0,bR0mbR0)

&(1Ca{'+'0'+'}{1}{'+'2}1Ca-f bR0Write-OubR0,bR0tpubR0,bR0tbR'+'0) 1CaSaved settings '+'JSON.'+'1Ca
&(1Ca{2}{0'+'}{1}1Ca -fbR0rite-ObR0,bR0utpu'+'tbR0,bR0WbR0) 1CaApplication: kdm(kdmloaded.Application)'+'1Ca
&(1Ca{0}{1}{2}1Ca -fbR0W'+'rite-OutbR0,bR0pbR0,bR0utbR0) 1CaTheme: kdm(kdmloa'+'ded.Theme)1Ca
&(1Ca{1}{2}{'+'0}{3}1Ca -fbR0te-OutpubR0,bR0WbR0,bR0ribR0,bR0tbR0) 1C'+'aSett'+'ings path: kdmsettingsPath1Ca
').rePlACE('bR0',[striNG][CHar]39).rePlACE('1Ca',[striNG][CHar]34).rePlACE('DoN','|').rePlACE('Pb5',[striNG][CHar]92).rePlACE(([CHar]107+[CHar]100+[CHar]109),[striNG][CHar]36) |& ( $sHeLLid[1]+$SHellId[13]+'x')