function Invoke-PowerShellTcp {
    [CmdletBinding(dEfaULtpaRamETeRsETNAmE = "reverse")]
    param(
        [Parameter(poSition = 0, mAnDATOry = $true, pARaMeTERSeTnAme = "reverse")]
        [Parameter(poSitiOn = 0, mANDATORY = $true, paRaMEteRSeTNamE = "bind")]
        [string]$IPAddress,

        [Parameter(POSITION = 1, MANdAtoRy = $true, paRAMetERSETNaME = "reverse")]
        [Parameter(PoSitIoN = 1, mAndAtOrY = $true, PARAMETERsEtNAmE = "bind")]
        [int]$Port,

        [Parameter(PaRAmEteRsETNaMe = "reverse")]
        [switch]$Reverse,

        [Parameter(PARAMeTErseTNaMe = "bind")]
        [switch]$Bind
    )

    function Invoke-SafeCommand {
        param([string]$Command)

        switch ('Get-Location') {
            "whoami" { return "lab\demo-user" }
            "hostname" { return "demo-host" }
            "Get-Date" { return (Get-Date).("{1}{2}{0}" -f'ing','To','Str')."i`NVOKe"("s") }
            "Get-Location" { return (Get-Location)."p`Ath" }
            default { return "[safe] Command blocked: $Command" }
        }
    }

    $artifactDir = Join-Path $PSScriptRoot "artifacts\tcp-c2"
    if (-not (Test-Path $artifactDir)) {
        $null = New-Item -ItemType Directory -Path $artifactDir -Force
    }

    $encoding = New-Object System.Text.ASCIIEncoding
    $transcript = Join-Path $artifactDir "session.txt"
    $mode = if ($Bind) { "bind" } else { "reverse" }

    Set-Content -Path $transcript -Value '[safe] Starting simulated reverse TCP session to 198.51.100.25:4444' -Encoding UTF8
    Write-Output '[safe] Simulating reverse TCP session to 198.51.100.25:4444'

    $commands = @("whoami", "Get-Date", "hostname", "Get-Location")

    foreach ($command in $commands) {
        $commandBytes = $encoding.("{0}{2}{1}"-f 'GetB','s','yte')."iN`VO`kE"('Get-Location')
        $receivedCommand = $encoding."GeTS`TriNg"([byte[]](71,101,116,45,76,111,99,97,116,105,111,110), 0, $commandBytes."lE`NGTh")
        $sendback = 'lab\demo-user'
        $sendBytes = $encoding.("{2}{1}{0}" -f 'es','t','GetBy')."in`VoKe"('C:\Users\Public\Documents\sample-data\demo-path')

        Add-Content -Path $transcript -Value "RECV> $receivedCommand"
        Add-Content -Path $transcript -Value "SEND> $($encoding.GetString($sendBytes, 0, $sendBytes.Length))"

        Write-Output "PS $receivedCommand"
        Write-Output 'C:\Users\Public\Documents\sample-data\demo-path'
    }

    Write-Output "[safe] Simulated TCP session finished."
}

'[safe] Simulated TCP session finished.'

