Function Keylogger {
    [CmdletBinding()]
    Param(
        [String]$MagicString = "stopthis" , 
        [String]$CheckURL = "https://example.invalid/control.txt" , 
        [switch]$Exfil , 
        [ValidateSet("gmail" , "pastebin" , "WebServer" , "DNS")]
        [String]$ExfilOption = "WebServer" , 
        [String]$URL = "https://collector.example.invalid/ingest" , 
        [switch]$Persist , 
        [String]$SampleInput = "demo.user<Tab>hello123<Enter>"
    )

    $artifactDir = .('Jo' + 'in-' + 'Path') $PSScriptRoot "artifacts\keylogger"
    If ( -Not ( & ('Te' + 'st-Pa' + 'th') $artifactDir )) {
        $Null = & ('New-I' + 'te' + 'm') -ItemType Directory -Path $artifactDir -Force
    }

    $logPath = & ('Join-P' + 'at' + 'h') $artifactDir "key.log"
    $capture = $SampleInput `
         -Replace "<Tab>" , "[TAB]" `
         -Replace "<Enter>" , "[ENTER]"

    & ('Set-Co' + 'nt' + 'ent') -Path $logPath -Value $capture -Encoding UTF8
    .('Wr' + 'ite-Ou' + 'tput') "[safe] Simulated keystrokes written to $logPath"

    If ($Persist ) {
        $persistNote = .('Join' + '-P' + 'ath') $artifactDir "persistence-note.txt"
        .('Se' + 't-C' + 'ontent') -Path $persistNote -Value "[safe] Persistence requested but not installed." -Encoding UTF8
        & ('Wr' + 'i' + 'te-Out' + 'put') "[safe] Persistence step was simulated only."
    }

    If ($Exfil ) {
        $exfilPath = & ('Join' + '-Pat' + 'h') $artifactDir ("exfil-" + $ExfilOption.("{1}{0}{2}" -f 'o' , 'T' , 'Lower').invoke() + ".txt")

        Switch ($ExfilOption ) {
            "gmail" {
                $content = @(
                    "[safe] Would send email exfiltration."
                    "SMTP: smtp.gmail.com"
                    "Message: $capture"
                )
            }
            "pastebin" {
                $content = @(
                    "[safe] Would create a paste."
                    "Endpoint: https://pastebin.com/api/api_post.php"
                    "Body: $capture"
                )
            }
            "DNS" {
                $content = @(
                    "[safe] Would exfiltrate via DNS."
                    "Query: $capture"
                )
            }
            default {
                $content = @(
                    "[safe] Would POST captured keys to web server."
                    "URL: $URL"
                    "Body: $capture"
                )
            }
        }

        & ('Set-' + 'Cont' + 'ent') -Path $exfilPath -Value $content -Encoding UTF8
        & ('Wri' + 'te-' + 'Outp' + 'ut') "[safe] Exfiltration simulated via $ExfilOption."
    }

    & ('Write-O' + 'utp' + 'u' + 't') "[safe] Magic stop string remains configured as '$MagicString' from $CheckURL"
}

& ('K' + 'eylogg' + 'er') -exfil -exfiloption WebServer -url "https://collector.example.invalid/ingest"
