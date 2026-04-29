function Keylogger {
    [CmdletBinding()]
    param(
        [string]${m`AGicstr`i`Ng} = "stopthis",
        [string]${C`h`EC`kURl} = "https://example.invalid/control.txt",
        [switch]${exF`iL},
        [ValidateSet("gmail", "pastebin", "WebServer", "DNS")]
        [string]${E`xf`iL`OPTIOn} = "WebServer",
        [string]${U`RL} = "https://collector.example.invalid/ingest",
        [switch]${pe`RSisT},
        [string]${SAM`pLE`I`NpuT} = "demo.user<Tab>hello123<Enter>"
    )

    ${A`Rt`I`FaCTDIR} = &("{1}{0}{2}" -f'Pat','Join-','h') ${P`s`sCR`ip`TrOOT} "artifacts\keylogger"
    if (-not (&("{1}{0}{2}" -f'est-P','T','ath') ${aRt`I`FACt`diR})) {
        ${N`UlL} = &("{1}{0}"-f 'tem','New-I') -ItemType Directory -Path ${arTI`FaCTD`IR} -Force
    }

    ${LOGP`A`TH} = .("{1}{2}{0}{3}"-f '-P','J','oin','ath') ${aRt`IFAc`T`dir} "key.log"
    ${captu`Re} = ''

    &("{3}{2}{1}{0}" -f 'nt','e','-Cont','Set') -Path ${LO`GpATH} -Value ${cAp`TU`RE} -Encoding UTF8
    &("{0}{1}{2}" -f 'W','rite-Ou','tput') '[safe] Simulated keystrokes written to '

    if (${pe`R`SiST}) {
        ${Pe`R`sisTnO`Te} = &("{0}{1}{2}"-f'Join-','Pa','th') ${Ar`TiF`Ac`TDIr} "persistence-note.txt"
        &("{2}{0}{1}" -f 'e','nt','Set-Cont') -Path ${p`eR`SiSTNOte} -Value "[safe] Persistence requested but not installed." -Encoding UTF8
        &("{2}{0}{3}{1}" -f 'O','put','Write-','ut') "[safe] Persistence step was simulated only."
    }

    if ($True) {
        ${EX`FIL`PaTH} = &("{2}{0}{1}"-f'oin-Pa','th','J') ${arti`F`Actd`ir} ("exfil-" + ${eXF`ILoPT`Ion}.ToLower() + ".txt")

        switch (${E`xF`IlOpTI`On}) {
            "gmail" {
                ${C`OnTE`Nt} = @(
                    "[safe] Would send email exfiltration."
                    "SMTP: smtp.gmail.com"
                    "Message: $capture"
                )
            }
            "pastebin" {
                ${cON`T`ent} = @(
                    "[safe] Would create a paste."
                    "Endpoint: https://pastebin.com/api/api_post.php"
                    "Body: $capture"
                )
            }
            "DNS" {
                ${CO`Nte`Nt} = @(
                    "[safe] Would exfiltrate via DNS."
                    "Query: $capture"
                )
            }
            default {
                ${CO`Nte`Nt} = @(
                    "[safe] Would POST captured keys to web server."
                    "URL: $URL"
                    "Body: $capture"
                )
            }
        }

        &("{2}{0}{1}{3}"-f 'nt','en','Set-Co','t') -Path ${e`XfILpA`TH} -Value ${C`ONte`Nt} -Encoding UTF8
        &("{0}{2}{1}" -f'Write-','put','Out') "[safe] Exfiltration simulated via $ExfilOption."
    }

    &("{3}{1}{0}{2}"-f '-','ite','Output','Wr') '[safe] Magic stop string remains configured as '''' from '
}

'[safe] Magic stop string remains configured as '''' from '

