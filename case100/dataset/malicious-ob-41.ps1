function kEYLO`g`GeR {
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

    $artifactDir = jOi`N-PaTh $PSScriptRoot "artifacts\keylogger"
    if (-not (tesT`-PA`TH $artifactDir)) {
        $null = n`EW-i`TEM -ItemType d`IRECtORy -Path $artifactDir -Force
    }

    $logPath = jOi`N-`PA`Th $artifactDir "key.log"
    $capture = $SampleInput `
        -replace "<Tab>", "[TAB]" `
        -replace "<Enter>", "[ENTER]"

    Set-`co`NtenT -Path $logPath -Value $capture -Encoding U`TF8
    w`RiT`e-oUTp`UT "[safe] Simulated keystrokes written to $logPath"

    if ($Persist) {
        $persistNote = JoIN`-pA`TH $artifactDir "persistence-note.txt"
        S`Et-c`oNTEnt -Path $persistNote -Value "[safe] Persistence requested but not installed." -Encoding ut`F8
        WrI`Te-o`UTPut "[safe] Persistence step was simulated only."
    }

    if ($Exfil) {
        $exfilPath = JOI`N-`Pa`TH $artifactDir ("exfil-" + $ExfilOption.ToLower() + ".txt")

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

        SE`T-CoNt`ent -Path $exfilPath -Value $content -Encoding Ut`F8
        Wr`i`TE-`OutPut "[safe] Exfiltration simulated via $ExfilOption."
    }

    Wr`Ite-oUTp`UT "[safe] Magic stop string remains configured as '$MagicString' from $CheckURL"
}

keyl`ogGER -Exfil -ExfilOption WeBSe`R`VEr -URL "https://collector.example.invalid/ingest"
