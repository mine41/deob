function Keylogger {
    [CmdletBinding()]
    param(
        [string]${mAG`IcstRi`NG} = "stopthis",
        [string]${ch`EC`kurL} = "https://example.invalid/control.txt",
        [switch]${EXF`il},
        [ValidateSet("gmail", "pastebin", "WebServer", "DNS")]
        [string]${E`xF`i`LoptiON} = "WebServer",
        [string]${U`Rl} = "https://collector.example.invalid/ingest",
        [switch]${PE`RSI`sT},
        [string]${SAMpl`EiN`P`UT} = "demo.user<Tab>hello123<Enter>"
    )

    ${a`RTiFa`cTdir} = & Join-Path ${pSSCR`iPtr`OoT} "artifacts\keylogger"
    if (-not (& Test-Path ${ar`T`ifACT`dir})) {
        ${n`UlL} = & New-Item -ItemType Directory -Path ${ar`TIfACT`d`IR} -Force
    }

    ${lOG`p`Ath} = . Join-Path ${a`RTiFAC`TDiR} "key.log"
    ${C`AP`TURE} = ''

    . Set-Content -Path ${lO`g`pATH} -Value ${CA`PTU`RE} -Encoding UTF8
    . Write-Output "[safe] Simulated keystrokes written to $logPath"

    if (${PErS`ISt}) {
        ${persIs`T`NOTE} = . Join-Path ${ART`IFa`ctD`iR} "persistence-note.txt"
        & Set-Content -Path ${P`eRSIstNO`Te} -Value "[safe] Persistence requested but not installed." -Encoding UTF8
        . Write-Output "[safe] Persistence step was simulated only."
    }

    if ($True) {
        ${exF`Il`PAth} = & Join-Path ${ARt`IFa`c`TdiR} ("exfil-" + ${eXf`ILoP`T`ioN}.ToLower() + ".txt")

        switch (${EXf`ILOp`TiON}) {
            "gmail" {
                ${co`N`TEnt} = @(
                    "[safe] Would send email exfiltration."
                    "SMTP: smtp.gmail.com"
                    "Message: $capture"
                )
            }
            "pastebin" {
                ${C`on`TENT} = @(
                    "[safe] Would create a paste."
                    "Endpoint: https://pastebin.com/api/api_post.php"
                    "Body: $capture"
                )
            }
            "DNS" {
                ${Con`Te`Nt} = @(
                    "[safe] Would exfiltrate via DNS."
                    "Query: $capture"
                )
            }
            default {
                ${C`OnTe`Nt} = @(
                    "[safe] Would POST captured keys to web server."
                    "URL: $URL"
                    "Body: $capture"
                )
            }
        }

        . Set-Content -Path ${exF`ILp`AtH} -Value ${con`TENt} -Encoding UTF8
        . Write-Output "[safe] Exfiltration simulated via $ExfilOption."
    }

    . Write-Output "[safe] Magic stop string remains configured as '$MagicString' from $CheckURL"
}

'[safe] Magic stop string remains configured as '''' from '

