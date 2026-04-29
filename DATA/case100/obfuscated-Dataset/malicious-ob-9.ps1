function Invoke-PowerShellTcp {
    [CmdletBinding(DEfAULTPaRAMeTErSEtnaME = "reverse")]
    param(
        [Parameter(PoSiTIon = 0, mAnDatORY = $true, paRamETerSetnamE = "reverse")]
        [Parameter(POSiTion = 0, mANDaTOry = $true, parAmEtersETNaMe = "bind")]
        [string]$IPAddress,

        [Parameter(poSItioN = 1, mAnDATOry = $true, paRAmETersEtNAMe = "reverse")]
        [Parameter(pOSItiON = 1, mAndATOrY = $true, pArAMEteRSETnAmE = "bind")]
        [int]$Port,

        [Parameter(paRameterSeTnAME = "reverse")]
        [switch]$Reverse,

        [Parameter(pArametErSeTname = "bind")]
        [switch]$Bind
    )

    function Invoke-SafeCommand {
        param([string]$Command)

        switch ($Command) {
            "whoami" { return "lab\demo-user" }
            "hostname" { return "demo-host" }
            "Get-Date" { return (&("{1}{0}" -f 'et-Date','G')).("{2}{1}{0}" -f'ing','r','ToSt').Invoke("s") }
            "Get-Location" { return (&("{2}{0}{1}"-f'-','Location','Get'))."p`ATH" }
            default { return "[safe] Command blocked: $Command" }
        }
    }

    $artifactDir = .("{1}{0}{2}"-f '-Pa','Join','th') $PSScriptRoot "artifacts\tcp-c2"
    if (-not (.("{2}{0}{3}{1}"-f'st','Path','Te','-') $artifactDir)) {
        $null = .("{2}{1}{0}" -f'tem','-I','New') -ItemType Directory -Path $artifactDir -Force
    }

    $encoding = &("{3}{1}{0}{2}" -f'je','Ob','ct','New-') System.Text.ASCIIEncoding
    $transcript = .("{1}{0}{2}" -f 'i','Jo','n-Path') $artifactDir "session.txt"
    $mode = if ($Bind) { "bind" } else { "reverse" }

    &("{1}{0}{2}{3}" -f 'Conte','Set-','n','t') -Path $transcript -Value "[safe] Starting simulated $mode TCP session to $IPAddress`:$Port" -Encoding UTF8
    .("{3}{0}{1}{2}" -f'ri','te-Outpu','t','W') "[safe] Simulating $mode TCP session to $IPAddress`:$Port"

    $commands = @("whoami", "Get-Date", "hostname", "Get-Location")

    foreach ($command in $commands) {
        $commandBytes = $encoding.("{1}{0}{2}"-f 'B','Get','ytes').Invoke($command)
        $receivedCommand = $encoding."GET`STRI`NG"($commandBytes, 0, $commandBytes."l`EN`gTH")
        $sendback = .("{3}{0}{2}{1}"-f'v','mand','oke-SafeCom','In') -Command $receivedCommand
        $sendBytes = $encoding.("{1}{0}{2}" -f 'et','G','Bytes').Invoke($sendback)

        .("{0}{1}{2}{3}" -f 'Ad','d','-Conte','nt') -Path $transcript -Value "RECV> $receivedCommand"
        .("{2}{1}{0}"-f'ontent','d-C','Ad') -Path $transcript -Value "SEND> $($encoding.GetString($sendBytes, 0, $sendBytes.Length))"

        &("{2}{0}{1}"-f 'e-O','utput','Writ') "PS $receivedCommand"
        &("{2}{0}{1}" -f'p','ut','Write-Out') $sendback
    }

    .("{1}{0}{2}" -f 'te-Out','Wri','put') "[safe] Simulated TCP session finished."
}

.("{4}{2}{1}{6}{3}{5}{0}"-f'p','ower','oke-P','l','Inv','Tc','Shel') -IPAddress "198.51.100.25" -Port 4444 -Reverse
