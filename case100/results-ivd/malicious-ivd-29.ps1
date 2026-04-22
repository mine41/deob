Function Keylogger {
    [CmdletBinding()]
    Param(
        [String]${mAGIcstRiNG} = "stopthis" , 
        [String]${chECkurL} = "https://example.invalid/control.txt" , 
        [switch]${EXFil} , 
        [ValidateSet("gmail" , "pastebin" , "WebServer" , "DNS")]
        [String]${ExFiLoptiON} = "WebServer" , 
        [String]${URl} = "https://collector.example.invalid/ingest" , 
        [switch]${PERSIsT} , 
        [String]${SAMplEiNPUT} = "demo.user<Tab>hello123<Enter>"
    )

    ${aRTiFacTdir} = & ("{2}{1}{0}" -f 'th' , 'a' , 'Join-P') ${pSSCRiPtrOoT} "artifacts\keylogger"
    If ( -Not ( & ("{1}{0}{2}" -f 's' , 'Te' , 't-Path') ${arTifACTdir} )) {
        ${Null} = & ("{1}{0}" -f 'm' , 'New-Ite') -ItemType Directory -Path ${arTIfACTdIR} -Force
    }

    ${lOGpAth} = .("{1}{2}{0}" -f 'ath' , 'Join' , '-P') ${aRTiFACTDiR} "key.log"
    ${CAPTURE} = ${sAmpLEiNPUt} `
         -Replace "<Tab>" , "[TAB]" `
         -Replace "<Enter>" , "[ENTER]"

    .("{1}{0}{2}" -f 'te' , 'Set-Con' , 'nt') -Path ${lOgpATH} -Value ${CAPTURE} -Encoding UTF8
    .("{3}{0}{1}{2}" -f 'rite-' , 'Outpu' , 't' , 'W') "[safe] Simulated keystrokes written to $logPath"

    If (${PErSISt} ) {
        ${persIsTNOTE} = .("{0}{2}{1}" -f 'Jo' , '-Path' , 'in') ${ARTIFactDiR} "persistence-note.txt"
        & ("{0}{2}{1}" -f 'Set-Co' , 'nt' , 'nte') -Path ${PRSIstNOTe} -Value "[safe] Persistence requested but not installed." -Encoding UTF8
        .("{2}{0}{1}" -f 'tpu' , 't' , 'Write-Ou') "[safe] Persistence step was simulated only."
    }

    If (${exFil} ) {
        ${exFIlPAth} = & ("{1}{0}{2}" -f 'o' , 'J' , 'in-Path') ${ARtIFacTdiR} ("exfil-" + ${eXfILoPTioN}.ToLower() + ".txt")

        Switch (${EXfILOpTiON} ) {
            "gmail" {
                ${coNTEnt} = @(
                    "[safe] Would send email exfiltration."
                    "SMTP: smtp.gmail.com"
                    "Message: $capture"
                )
            }
            "pastebin" {
                ${ConTENT} = @(
                    "[safe] Would create a paste."
                    "Endpoint: https://pastebin.com/api/api_post.php"
                    "Body: $capture"
                )
            }
            "DNS" {
                ${ConTeNt} = @(
                    "[safe] Would exfiltrate via DNS."
                    "Query: $capture"
                )
            }
            default {
                ${COnTeNt} = @(
                    "[safe] Would POST captured keys to web server."
                    "URL: $URL"
                    "Body: $capture"
                )
            }
        }

        .("{2}{0}{1}" -f 'C' , 'ontent' , 'Set-') -Path ${exFILpAtH} -Value ${conTENt} -Encoding UTF8
        .("{0}{2}{3}{1}" -f 'W' , '-Output' , 'rit' , 'e') "[safe] Exfiltration simulated via $ExfilOption."
    }

    .("{2}{3}{1}{0}" -f 'Output' , 'e-' , 'W' , 'rit') "[safe] Magic stop string remains configured as '$MagicString' from $CheckURL"
}

.("{0}{1}" -f 'Keylog' , 'ger') -exfil -exfiloption WebServer -url "https://collector.example.invalid/ingest"
