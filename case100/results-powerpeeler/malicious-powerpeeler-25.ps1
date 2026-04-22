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
    $artifactDir = &("{0}{1}{2}"-f 'J','oin-','Path') $PSScriptRoot "artifacts\keylogger"
    if (-not (.("{1}{2}{0}" -f'-Path','Tes','t') $artifactDir)) {
        $null = .("{0}{2}{1}" -f 'Ne','tem','w-I') -ItemType Directory -Path $artifactDir -Force
    }
    $logPath = &("{1}{0}{2}" -f 'at','Join-P','h') $artifactDir "key.log"
    $capture = $SampleInput `
        -replace "<Tab>", "[TAB]" `
        -replace "<Enter>", "[ENTER]"
    .("{3}{2}{0}{1}"-f 'C','ontent','t-','Se') -Path $logPath -Value $capture -Encoding UTF8
    .("{1}{2}{3}{0}" -f'tput','Write','-O','u') "[safe] Simulated keystrokes written to $logPath"
    if ($Persist) {
        $persistNote = &("{1}{0}{2}" -f 'oin-Pa','J','th') $artifactDir "persistence-note.txt"
        &("{2}{0}{1}" -f 'nten','t','Set-Co') -Path $persistNote -Value "[safe] Persistence requested but not installed." -Encoding UTF8
        .("{2}{1}{0}" -f't','Outpu','Write-') "[safe] Persistence step was simulated only."
    }
    if ($Exfil) {
        $exfilPath = &("{2}{0}{1}" -f 'n-','Path','Joi') $artifactDir ("exfil-" + $ExfilOption.("{1}{0}"-f'wer','ToLo').Invoke() + ".txt")
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
        &("{0}{3}{2}{1}"-f'Set','t','Conten','-') -Path $exfilPath -Value $content -Encoding UTF8
        &("{2}{0}{3}{1}" -f'-Ou','put','Write','t') "[safe] Exfiltration simulated via $ExfilOption."
    }
    .("{2}{0}{1}" -f 'i','te-Output','Wr') "[safe] Magic stop string remains configured as '$MagicString' from $CheckURL"
}
&("{1}{2}{0}"-f 'r','Keylo','gge') -Exfil -ExfilOption WebServer -URL "https://collector.example.invalid/ingest"
