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

        switch ('Get-Location') {
            "whoami" { return "lab\demo-user" }
            "hostname" { return "demo-host" }
            "Get-Date" { return (& Get-Date).("{2}{1}{0}" -f'ing','r','ToSt').Invoke("s") }
            "Get-Location" { return (& Get-Location)."p`ATH" }
            default { return "[safe] Command blocked: $Command" }
        }
    }

    $artifactDir = . Join-Path $PSScriptRoot "artifacts\tcp-c2"
    if (-not (. Test-Path $artifactDir)) {
        $null = . New-Item -ItemType Directory -Path $artifactDir -Force
    }

    $encoding = & New-Object System.Text.ASCIIEncoding
    $transcript = . Join-Path $artifactDir "session.txt"
    $mode = if ($Bind) { "bind" } else { "reverse" }

    & Set-Content -Path $transcript -Value '[safe] Starting simulated reverse TCP session to 198.51.100.25:4444' -Encoding UTF8
    . Write-Output '[safe] Simulating reverse TCP session to 198.51.100.25:4444'

    $commands = @("whoami", "Get-Date", "hostname", "Get-Location")

    foreach ($command in $commands) {
        $commandBytes = $encoding.("{1}{0}{2}"-f 'B','Get','ytes').Invoke('Get-Location')
        $receivedCommand = $encoding."GET`STRI`NG"([byte[]](71,101,116,45,76,111,99,97,116,105,111,110), 0, $commandBytes."l`EN`gTH")
        $sendback = 'lab\demo-user'
        $sendBytes = $encoding.("{1}{0}{2}" -f 'et','G','Bytes').Invoke('C:\Users\Public\Documents\sample-data\demo-path')

        . Add-Content -Path $transcript -Value "RECV> $receivedCommand"
        . Add-Content -Path $transcript -Value "SEND> $($encoding.GetString($sendBytes, 0, $sendBytes.Length))"

        & Write-Output "PS $receivedCommand"
        & Write-Output 'C:\Users\Public\Documents\sample-data\demo-path'
    }

    . Write-Output "[safe] Simulated TCP session finished."
}

'[safe] Simulated TCP session finished.'

