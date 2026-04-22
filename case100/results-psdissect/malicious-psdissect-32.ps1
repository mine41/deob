function Keylogger {
    [CmdletBinding()]
    param(
        [string]${mag`ic`STrinG} = "stopthis",
        [string]${C`HEcku`RL} = "https://example.invalid/control.txt",
        [switch]${e`x`FIL},
        [ValidateSet("gmail", "pastebin", "WebServer", "DNS")]
        [string]${exFI`L`oPtIoN} = "WebServer",
        [string]${u`RL} = "https://collector.example.invalid/ingest",
        [switch]${peR`SIst},
        [string]${Sa`mplE`I`NPut} = "demo.user<Tab>hello123<Enter>"
    )

    ${a`RTIF`A`CTdIR} = Join-Path ${psSCR`I`PtRooT} "artifacts\keylogger"
    if (-not (Test-Path ${aRT`ifActD`ir})) {
        ${NU`lL} = New-Item -ItemType Directory -Path ${a`RT`IFa`cTdIr} -Force
    }

    ${lO`GPa`Th} = Join-Path ${aRTIfA`cT`DIR} "key.log"
    ${c`AP`TUrE} = ${Sam`PLEiNp`Ut} `
        -replace "<Tab>", "[TAB]" `
        -replace "<Enter>", "[ENTER]"

    Set-Content -Path ${LO`g`pAth} -Value ${c`APT`Ure} -Encoding UTF8
    Write-Output "[safe] Simulated keystrokes written to $logPath"

    if (${per`s`ISt}) {
        ${Pe`R`S`ISTNote} = Join-Path ${A`RT`iF`ACtdir} "persistence-note.txt"
        Set-Content -Path ${PErSi`Stn`O`Te} -Value "[safe] Persistence requested but not installed." -Encoding UTF8
        Write-Output "[safe] Persistence step was simulated only."
    }

    if (${E`XFIl}) {
        ${Ex`FIL`pa`Th} = Join-Path ${aRtI`Fact`d`iR} ("exfil-" + ${exfIlO`P`TI`On}.ToLower() + ".txt")

        switch (${E`XfiLOP`Ti`On}) {
            "gmail" {
                ${C`onTENt} = @(
                    "[safe] Would send email exfiltration."
                    "SMTP: smtp.gmail.com"
                    "Message: $capture"
                )
            }
            "pastebin" {
                ${C`ONT`EnT} = @(
                    "[safe] Would create a paste."
                    "Endpoint: https://pastebin.com/api/api_post.php"
                    "Body: $capture"
                )
            }
            "DNS" {
                ${CONt`E`Nt} = @(
                    "[safe] Would exfiltrate via DNS."
                    "Query: $capture"
                )
            }
            default {
                ${c`ON`TEnT} = @(
                    "[safe] Would POST captured keys to web server."
                    "URL: $URL"
                    "Body: $capture"
                )
            }
        }

        Set-Content -Path ${eX`FilP`Ath} -Value ${C`ON`TenT} -Encoding UTF8
        Write-Output "[safe] Exfiltration simulated via $ExfilOption."
    }

    Write-Output "[safe] Magic stop string remains configured as '$MagicString' from $CheckURL"
}

kylOGGER -Exfil -ExfilOption WebServer -URL "https://collector.example.invalid/ingest"

