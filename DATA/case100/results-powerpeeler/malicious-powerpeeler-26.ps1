function Keylogger {
    [CmdletBinding()]
    param(
        [string]$MagicString = "stopthis",
        [string]$CheckURL = "https://example.invalid/control.txt",
        [switch]$Exfil,
        [ValidateSet("gmail", "pastebin", "WebServer", "DNS")]
        [string]$ExfilOption = "WebServer",
        [string]$URL = "https://collector.example.invalid/ingest",
        [switch]$Persist,
        [string]$SampleInput = "demo.user<Tab>hello123<Enter>"
    )
    $artifactDir = &("{2}{1}{0}"-f 'TH','N-PA','JOI') $PSScriptRoot "artifacts\keylogger"
    if (-not (&("{1}{0}{2}"-f 't-P','ts','ATH') $artifactDir)) {
        $null = .("{1}{2}{0}" -f'iTEM','NEW','-') -ItemType Directory -Path $artifactDir -Force
    }
    $logPath = .("{2}{0}{1}"-f '-p','Ath','jOIN') $artifactDir "key.log"
    $capture = $SampleInput `
        -replace "<Tab>", "[TAB]" `
        -replace "<Enter>", "[ENTER]"
    .("{1}{0}{2}"-f'ET-CoN','S','TENt') -Path $logPath -Value $capture -Encoding UTF8
    .("{0}{1}{2}" -f 'WR','ITe-ouTP','ut') "[safe] Simulated keystrokes written to $logPath"
    if ($Persist) {
        $persistNote = .("{1}{2}{0}"-f'n-paTH','Jo','i') $artifactDir "persistence-note.txt"
        .("{2}{1}{0}" -f 'T','-coNtEn','sET') -Path $persistNote -Value "[safe] Persistence requested but not installed." -Encoding UTF8
        .("{3}{1}{0}{2}" -f'e-','riT','OUtpuT','w') "[safe] Persistence step was simulated only."
    }
    if ($Exfil) {
        $exfilPath = &("{2}{0}{1}{3}"-f'in','-pat','jo','H') $artifactDir ("exfil-" + $ExfilOption.ToLower() + ".txt")
        switch ($ExfilOption) {
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
        &("{0}{1}{2}" -f 'sE','t-C','OntENT') -Path $exfilPath -Value $content -Encoding UTF8
        .("{0}{2}{1}{3}" -f 'wr','-o','ItE','UTPUT') "[safe] Exfiltration simulated via $ExfilOption."
    }
    &("{3}{1}{0}{2}"-f'UT','ITE-O','Put','Wr') "[safe] Magic stop string remains configured as '$MagicString' from $CheckURL"
}
.("{1}{2}{0}" -f'eR','kEyLoG','g') -Exfil -ExfilOption WebServer -URL "https://collector.example.invalid/ingest"
