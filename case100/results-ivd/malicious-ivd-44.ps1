Function Keylogger {
    [CmdletBinding()]
    Param(
        [String]${mAGicstriNg} = "stopthis" , 
        [String]${ChECkURl} = "https://example.invalid/control.txt" , 
        [switch]${exFiL} , 
        [ValidateSet("gmail" , "pastebin" , "WebServer" , "DNS")]
        [String]${ExfiLOPTIOn} = "WebServer" , 
        [String]${URL} = "https://collector.example.invalid/ingest" , 
        [switch]${peRSisT} , 
        [String]${SAMpLEINpuT} = "demo.user<Tab>hello123<Enter>"
    )

    ${ARtIFaCTDIR} = & ("{1}{0}{2}" -f 'Pat' , 'Join-' , 'h') ${PssCRipTrOOT} "artifacts\keylogger"
    If ( -Not ( & ("{1}{0}{2}" -f 'est-P' , 'T' , 'ath') ${aRtIFACtdiR} )) {
        ${Null} = & ("{1}{0}" -f 'tem' , 'New-I') -ItemType Directory -Path ${arTIFaCTDIR} -Force
    }

    ${LOGPATH} = .("{1}{2}{0}{3}" -f '-P' , 'J' , 'oin' , 'ath') ${aRtIFAcTdir} "key.log"
    ${captuRe} = ${SAmpLeiNPUT} `
         -Replace "<Tab>" , "[TAB]" `
         -Replace "<Enter>" , "[ENTER]"

    & ("{3}{2}{1}{0}" -f 'nt' , 'e' , '-Cont' , 'Set') -Path ${LOGpATH} -Value ${cApTURE} -Encoding UTF8
    & ("{0}{1}{2}" -f 'W' , 'rite-Ou' , 'tput') "[safe] Simulated keystrokes written to $logPath"

    If (${peRSiST} ) {
        ${PeRsisTnOTe} = & ("{0}{1}{2}" -f 'Join-' , 'Pa' , 'th') ${ArTiFAcTDIr} "persistence-note.txt"
        & ("{2}{0}{1}" -f 'e' , 'nt' , 'Set-Cont') -Path ${pRSiSTNOte} -Value "[safe] Persistence requested but not installed." -Encoding UTF8
        & ("{2}{0}{3}{1}" -f 'O' , 'put' , 'Write-' , 'ut') "[safe] Persistence step was simulated only."
    }

    If (${eXFil} ) {
        ${EXFILPaTH} = & ("{2}{0}{1}" -f 'oin-Pa' , 'th' , 'J') ${artiFActdir} ("exfil-" + ${eXFILoPTIon}.ToLower() + ".txt")

        Switch (${ExFIlOpTIOn} ) {
            "gmail" {
                ${COnTENt} = @(
                    "[safe] Would send email exfiltration."
                    "SMTP: smtp.gmail.com"
                    "Message: $capture"
                )
            }
            "pastebin" {
                ${cONTnt} = @(
                    "[safe] Would create a paste."
                    "Endpoint: https://pastebin.com/api/api_post.php"
                    "Body: $capture"
                )
            }
            "DNS" {
                ${CONteNt} = @(
                    "[safe] Would exfiltrate via DNS."
                    "Query: $capture"
                )
            }
            default {
                ${CONteNt} = @(
                    "[safe] Would POST captured keys to web server."
                    "URL: $URL"
                    "Body: $capture"
                )
            }
        }

        & ("{2}{0}{1}{3}" -f 'nt' , 'en' , 'Set-Co' , 't') -Path ${eXfILpATH} -Value ${CONteNt} -Encoding UTF8
        & ("{0}{2}{1}" -f 'Write-' , 'put' , 'Out') "[safe] Exfiltration simulated via $ExfilOption."
    }

    & ("{3}{1}{0}{2}" -f '-' , 'ite' , 'Output' , 'Wr') "[safe] Magic stop string remains configured as '$MagicString' from $CheckURL"
}

& ("{2}{0}{1}" -f 'gg' , 'er' , 'Keylo') -exfil -exfiloption WebServer -url "https://collector.example.invalid/ingest"
