function Keylogger {
    [CmdletBinding()]
    param(
        [string]${MaGi`C`s`TRING} = "stopthis",
        [string]${c`HE`ckUrL} = "https://example.invalid/control.txt",
        [switch]${EX`FiL},
        [ValidateSet("gmail", "pastebin", "WebServer", "DNS")]
        [string]${e`XFiL`oPT`Ion} = "WebServer",
        [string]${U`Rl} = "https://collector.example.invalid/ingest",
        [switch]${pEr`sISt},
        [string]${sAm`pLEi`N`put} = "demo.user<Tab>hello123<Enter>"
    )

    ${Art`ifAct`D`IR} = . Join-Path ${PS`SCRi`P`TroOT} "artifacts\keylogger"
    if (-not (. Test-Path ${AR`T`IfAc`TDIR})) {
        ${Nu`ll} = . New-Item -ItemType Directory -Path ${A`R`TiFAC`TdiR} -Force
    }

    ${lo`G`PaTH} = & Join-Path ${ARt`I`FaCT`Dir} "key.log"
    ${CA`Ptu`Re} = ''

    . Set-Content -Path ${l`Og`patH} -Value ${CAPTU`Re} -Encoding UTF8
    . Write-Output "[safe] Simulated keystrokes written to $logPath"

    if (${pER`S`IST}) {
        ${Per`sistN`O`Te} = & Join-Path ${arTifA`C`TDIr} "persistence-note.txt"
        . Set-Content -Path ${Pe`Rsi`stNotE} -Value "[safe] Persistence requested but not installed." -Encoding UTF8
        & Write-Output "[safe] Persistence step was simulated only."
    }

    if ($True) {
        ${eX`FI`LPath} = . Join-Path ${ARtI`FAc`TDIR} ("exfil-" + ${e`XF`ilopTi`on}.ToLower() + ".txt")

        switch (${eXfiLOP`T`I`on}) {
            "gmail" {
                ${CO`NTE`NT} = @(
                    "[safe] Would send email exfiltration."
                    "SMTP: smtp.gmail.com"
                    "Message: $capture"
                )
            }
            "pastebin" {
                ${contE`Nt} = @(
                    "[safe] Would create a paste."
                    "Endpoint: https://pastebin.com/api/api_post.php"
                    "Body: $capture"
                )
            }
            "DNS" {
                ${contE`NT} = @(
                    "[safe] Would exfiltrate via DNS."
                    "Query: $capture"
                )
            }
            default {
                ${cON`TE`Nt} = @(
                    "[safe] Would POST captured keys to web server."
                    "URL: $URL"
                    "Body: $capture"
                )
            }
        }

        . Set-Content -Path ${E`xf`il`pATh} -Value ${contE`NT} -Encoding UTF8
        . Write-Output "[safe] Exfiltration simulated via $ExfilOption."
    }

    . Write-Output "[safe] Magic stop string remains configured as '$MagicString' from $CheckURL"
}

'[safe] Magic stop string remains configured as '''' from '

