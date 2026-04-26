function Invoke-PowerShellTcp {
    [CmdletBinding(defAulTParaMEterSetnaME = "reverse")]
    param(
        [Parameter(POSITioN = 0, mAnDATORY = $true, PaRAmEteRSETNAME = "reverse")]
        [Parameter(PoSitIOn = 0, maNDaTory = $true, PAraMeTeRSETNAme = "bind")]
        [string]$IPAddress,

        [Parameter(PoSItIoN = 1, MANDaToRy = $true, PARAmeTersETNAME = "reverse")]
        [Parameter(pOsiTIon = 1, maNdaToRY = $true, PARaMETeRsetnaME = "bind")]
        [int]$Port,

        [Parameter(PaRAMEteRsETNAmE = "reverse")]
        [switch]$Reverse,

        [Parameter(pARamEterSeTnAME = "bind")]
        [switch]$Bind
    )

    function Invoke-SafeCommand {
        param([string]$Command)

        switch ('Get-Location') {
            "whoami" { return "lab\demo-user" }
            "hostname" { return "demo-host" }
            "Get-Date" { return (& Get-Date).("{2}{0}{1}" -f'r','ing','ToSt').Invoke("s") }
            "Get-Location" { return (. Get-Location)."P`ATh" }
            default { return "[safe] Command blocked: $Command" }
        }
    }

    $artifactDir = & Join-Path $PSScriptRoot "artifacts\tcp-c2"
    if (-not (. Test-Path $artifactDir)) {
        $null = . New-Item -ItemType Directory -Path $artifactDir -Force
    }

    $encoding = . New-Object System.Text.ASCIIEncoding
    $transcript = . Join-Path $artifactDir "session.txt"
    $mode = if ($Bind) { "bind" } else { "reverse" }

    . Set-Content -Path $transcript -Value '[safe] Starting simulated reverse TCP session to 198.51.100.25:4444' -Encoding UTF8
    . Write-Output '[safe] Simulating reverse TCP session to 198.51.100.25:4444'

    $commands = @("whoami", "Get-Date", "hostname", "Get-Location")

    foreach ($command in $commands) {
        $commandBytes = $encoding.("{0}{2}{1}"-f 'G','tBytes','e').Invoke('Get-Location')
        $receivedCommand = $encoding."gE`TsTr`iNG"([byte[]](71,101,116,45,76,111,99,97,116,105,111,110), 0, $commandBytes."l`ENGth")
        $sendback = 'lab\demo-user'
        $sendBytes = $encoding.("{2}{0}{1}"-f 'etByte','s','G').Invoke('C:\Users\Public\Documents\sample-data\demo-path')

        & Add-Content -Path $transcript -Value "RECV> $receivedCommand"
        & Add-Content -Path $transcript -Value "SEND> $($encoding.GetString($sendBytes, 0, $sendBytes.Length))"

        & Write-Output "PS $receivedCommand"
        . Write-Output 'C:\Users\Public\Documents\sample-data\demo-path'
    }

    . Write-Output "[safe] Simulated TCP session finished."
}

'[safe] Simulated TCP session finished.'

