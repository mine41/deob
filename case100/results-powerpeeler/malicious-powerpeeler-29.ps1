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
    ${a`RTiFa`cTdir} = &("{2}{1}{0}" -f'th','a','Join-P') ${pSSCR`iPtr`OoT} "artifacts\keylogger"
    if (-not (&("{1}{0}{2}"-f's','Te','t-Path') ${ar`T`ifACT`dir})) {
        ${n`UlL} = &("{1}{0}" -f'm','New-Ite') -ItemType Directory -Path ${ar`TIfACT`d`IR} -Force
    }
    ${lOG`p`Ath} = .("{1}{2}{0}"-f 'ath','Join','-P') ${a`RTiFAC`TDiR} "key.log"
    ${C`AP`TURE} = ${sAmpL`E`i`NPUt} `
        -replace "<Tab>", "[TAB]" `
        -replace "<Enter>", "[ENTER]"
    .("{1}{0}{2}" -f'te','Set-Con','nt') -Path ${lO`g`pATH} -Value ${CA`PTU`RE} -Encoding UTF8
    .("{3}{0}{1}{2}"-f 'rite-','Outpu','t','W') "[safe] Simulated keystrokes written to $logPath"
    if (${PErS`ISt}) {
        ${persIs`T`NOTE} = .("{0}{2}{1}"-f'Jo','-Path','in') ${ART`IFa`ctD`iR} "persistence-note.txt"
        &("{0}{2}{1}"-f'Set-Co','nt','nte') -Path ${P`eRSIstNO`Te} -Value "[safe] Persistence requested but not installed." -Encoding UTF8
        .("{2}{0}{1}" -f 'tpu','t','Write-Ou') "[safe] Persistence step was simulated only."
    }
    if (${ex`Fil}) {
        ${exF`Il`PAth} = &("{1}{0}{2}"-f'o','J','in-Path') ${ARt`IFa`c`TdiR} ("exfil-" + ${eXf`ILoP`T`ioN}.ToLower() + ".txt")
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
        .("{2}{0}{1}"-f 'C','ontent','Set-') -Path ${exF`ILp`AtH} -Value ${con`TENt} -Encoding UTF8
        .("{0}{2}{3}{1}" -f'W','-Output','rit','e') "[safe] Exfiltration simulated via $ExfilOption."
    }
    .("{2}{3}{1}{0}"-f 'Output','e-','W','rit') "[safe] Magic stop string remains configured as '$MagicString' from $CheckURL"
}
.("{0}{1}"-f 'Keylog','ger') -Exfil -ExfilOption WebServer -URL "https://collector.example.invalid/ingest"
