function Ke`yLO`GGer {
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
    $artifactDir = Jo`in-`path $PSScriptRoot "artifacts\keylogger"
    if (-not (T`Est-p`ATh $artifactDir)) {
        $null = neW`-`iTeM -ItemType d`Ir`eCT`Ory -Path $artifactDir -Force
    }
    $logPath = JoiN`-p`ATH $artifactDir "key.log"
    $capture = $SampleInput `
        -replace "<Tab>", "[TAB]" `
        -replace "<Enter>", "[ENTER]"
    SeT`-conte`Nt -Path $logPath -Value $capture -Encoding ut`F8
    WrITe-`ou`TPUT "[safe] Simulated keystrokes written to $logPath"
    if ($Persist) {
        $persistNote = j`OI`N-pa`Th $artifactDir "persistence-note.txt"
        Set-cONt`E`Nt -Path $persistNote -Value "[safe] Persistence requested but not installed." -Encoding ut`F8
        Wr`I`TE-OUT`PUt "[safe] Persistence step was simulated only."
    }
    if ($Exfil) {
        $exfilPath = j`OIN-`pAth $artifactDir ("exfil-" + $ExfilOption.ToLower() + ".txt")
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
        SEt`-C`O`NtENt -Path $exfilPath -Value $content -Encoding u`TF8
        wRItE-o`UTp`Ut "[safe] Exfiltration simulated via $ExfilOption."
    }
    Wr`it`e-ou`TpUt "[safe] Magic stop string remains configured as '$MagicString' from $CheckURL"
}
KeyLOGGer -Exfil -ExfilOption WeBSER`VeR -URL "https://collector.example.invalid/ingest"
