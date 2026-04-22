function Invoke-PowerShellTcp {
    [CmdletBinding(DEfAUltpArameterSEtNAME = "reverse")]
    param(
        [Parameter(POsItION = 0, mAndATory = $true, paRaMeTErSETnAMe = "reverse")]
        [Parameter(PosiTiON = 0, mANDATORY = $true, paRaMeTErseTnaME = "bind")]
        [string]$IPAddress,

        [Parameter(posITion = 1, MandatOry = $true, pARAMEteRsEtNAmE = "reverse")]
        [Parameter(PositION = 1, MaNdaTORy = $true, PaRAmETerSETnAme = "bind")]
        [int]$Port,

        [Parameter(pARaMETerSETnamE = "reverse")]
        [switch]$Reverse,

        [Parameter(PARamEteRSetNaME = "bind")]
        [switch]$Bind
    )

    function Invoke-SafeCommand {
        param([string]$Command)

        switch ('') {
            "whoami" { return "lab\demo-user" }
            "hostname" { return "demo-host" }
            "Get-Date" { return (.("{2}{0}{1}" -f '-Dat','e','Get')).("{0}{2}{1}"-f'ToStri','g','n').Invoke("s") }
            "Get-Location" { return (.("{0}{1}{2}{3}" -f'Get-L','o','catio','n'))."Pa`TH" }
            default { return "[safe] Command blocked: $Command" }
        }
    }

    $artifactDir = .("{2}{0}{1}"-f 'i','n-Path','Jo') $PSScriptRoot "artifacts\tcp-c2"
    if (-not (&("{1}{0}" -f'ath','Test-P') $artifactDir)) {
        $null = .("{2}{0}{1}" -f 't','em','New-I') -ItemType Directory -Path $artifactDir -Force
    }

    $encoding = &("{1}{2}{0}" -f'bject','New','-O') System.Text.ASCIIEncoding
    $transcript = &("{0}{2}{1}"-f'Joi','th','n-Pa') $artifactDir "session.txt"
    $mode = if ($Bind) { "bind" } else { "reverse" }

    .("{1}{2}{0}"-f'tent','Set-C','on') -Path $transcript -Value '[safe] Starting simulated reverse TCP session to 198.51.100.25:4444' -Encoding UTF8
    &("{0}{1}{2}"-f 'Wr','ite-O','utput') '[safe] Simulating reverse TCP session to 198.51.100.25:4444'

    $commands = @("whoami", "Get-Date", "hostname", "Get-Location")

    foreach ($command in $commands) {
        $commandBytes = $encoding.("{1}{2}{0}" -f 'tBytes','G','e').Invoke('Get-Location')
        $receivedCommand = $encoding."GETs`TR`INg"([byte[]](71,101,116,45,76,111,99,97,116,105,111,110), 0, $commandBytes."l`engTH")
        $sendback = '[safe] Command blocked: '
        $sendBytes = $encoding.("{0}{2}{1}"-f'GetB','es','yt').Invoke('[safe] Command blocked: ')

        .("{3}{2}{0}{1}" -f'n','t','te','Add-Con') -Path $transcript -Value 'RECV> '
        .("{2}{3}{1}{0}" -f'nt','e','Add-Co','nt') -Path $transcript -Value "SEND> $($encoding.GetString($sendBytes, 0, 24))"

        &("{0}{1}{2}"-f'Write','-Outpu','t') 'PS '
        .("{2}{0}{1}"-f 'rit','e-Output','W') '[safe] Command blocked: '
    }

    &("{1}{0}{2}" -f '-Out','Write','put') "[safe] Simulated TCP session finished."
}

'[safe] Simulated TCP session finished.'

