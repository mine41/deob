Function Keylogger {
    [CmdletBinding()]
    Param(
        [String]${MaGiCsTRING} = "stopthis" , 
        [String]${cHEckUrL} = "https://example.invalid/control.txt" , 
        [switch]${EXFiL} , 
        [ValidateSet("gmail" , "pastebin" , "WebServer" , "DNS")]
        [String]${eXFiLoPTIon} = "WebServer" , 
        [String]${URl} = "https://collector.example.invalid/ingest" , 
        [switch]${pErsISt} , 
        [String]${sAmpLEiNput} = "demo.user<Tab>hello123<Enter>"
    )

    ${ArtifActDIR} = .("{1}{0}{2}" -f 'in-P' , 'Jo' , 'ath') ${PSSCRiPTroOT} "artifacts\keylogger"
    If ( -Not (.("{2}{1}{0}" -f 'Path' , '-' , 'Test') ${ARTIfAcTDIR} )) {
        ${Null} = .("{2}{0}{1}" -f 'w-' , 'Item' , 'Ne') -ItemType Directory -Path ${ARTiFACTdiR} -Force
    }

    ${loGPaTH} = & ("{2}{1}{0}" -f '-Path' , 'in' , 'Jo') ${ARtIFaCTDir} "key.log"
    ${CAPtuRe} = ${SAmplINPUT} `
         -Replace "<Tab>" , "[TAB]" `
         -Replace "<Enter>" , "[ENTER]"

    .("{2}{1}{0}" -f 'Content' , 't-' , 'Se') -Path ${lOgpatH} -Value ${CAPTURe} -Encoding UTF8
    .("{2}{0}{3}{1}" -f 'te-Out' , 't' , 'Wri' , 'pu') "[safe] Simulated keystrokes written to $logPath"

    If (${pERSIST} ) {
        ${PersistNOTe} = & ("{2}{1}{0}" -f 'th' , 'n-Pa' , 'Joi') ${arTifACTDIr} "persistence-note.txt"
        .("{0}{2}{1}" -f 'Set-Con' , 'nt' , 'te') -Path ${PeRsistNotE} -Value "[safe] Persistence requested but not installed." -Encoding UTF8
        & ("{1}{3}{2}{0}" -f 'utput' , 'Wr' , 'te-O' , 'i') "[safe] Persistence step was simulated only."
    }

    If (${eXFIl} ) {
        ${eXFILPath} = .("{1}{0}" -f '-Path' , 'Join') ${ARtIFAcTDIR} ("exfil-" + ${eXFilopTion}.ToLower() + ".txt")

        Switch (${eXfiLOPTIon} ) {
            "gmail" {
                ${CONTENT} = @(
                    "[safe] Would send email exfiltration."
                    "SMTP: smtp.gmail.com"
                    "Message: $capture"
                )
            }
            "pastebin" {
                ${contENt} = @(
                    "[safe] Would create a paste."
                    "Endpoint: https://pastebin.com/api/api_post.php"
                    "Body: $capture"
                )
            }
            "DNS" {
                ${contENT} = @(
                    "[safe] Would exfiltrate via DNS."
                    "Query: $capture"
                )
            }
            default {
                ${cONTENt} = @(
                    "[safe] Would POST captured keys to web server."
                    "URL: $URL"
                    "Body: $capture"
                )
            }
        }

        .("{0}{2}{1}" -f 'Se' , 'Content' , 't-') -Path ${ExfilpATh} -Value ${contENT} -Encoding UTF8
        .("{3}{1}{2}{0}" -f 'tput' , 'te' , '-Ou' , 'Wri') "[safe] Exfiltration simulated via $ExfilOption."
    }

    .("{1}{2}{0}" -f 'ut' , 'Write' , '-Outp') "[safe] Magic stop string remains configured as '$MagicString' from $CheckURL"
}

.("{0}{1}{2}" -f 'K' , 'eylog' , 'ger') -exfil -exfiloption WebServer -url "https://collector.example.invalid/ingest"
