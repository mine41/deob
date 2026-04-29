function Invoke-PowerShellTcp {
    [CmdletBinding(DEFaultPAraMeTErseTNamE = "reverse")]
    param(
        [Parameter(POSItIon = 0, mAndatOrY = $true, PARAMETeRSeTnaMe = "reverse")]
        [Parameter(POsiTiON = 0, MANDaTORy = $true, pARameTErsETnaMe = "bind")]
        [string]$IPAddress,

        [Parameter(pOsItioN = 1, mANDaTORy = $true, pArAmEtERSetName = "reverse")]
        [Parameter(pOsiTiON = 1, ManDatoRY = $true, PARaMetERSEtNaME = "bind")]
        [int]$Port,

        [Parameter(PaRaMETErSETNAme = "reverse")]
        [switch]$Reverse,

        [Parameter(paRameTersETnAMe = "bind")]
        [switch]$Bind
    )

    function Invoke-SafeCommand {
        param([string]$Command)

        switch ('Get-Location') {
            "whoami" { return "lab\demo-user" }
            "hostname" { return "demo-host" }
            "Get-Date" { return (Get-Date).('T'+'oStrin'+'g')."I`N`VoKE"("s") }
            "Get-Location" { return (Get-Location)."p`ATh" }
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
        $commandBytes = $encoding.('G'+'etByt'+'es')."inv`oKE"('Get-Location')
        $receivedCommand = $encoding."gET`sTR`ing"([byte[]](71,101,116,45,76,111,99,97,116,105,111,110), 0, $commandBytes."LEN`G`TH")
        $sendback = 'lab\demo-user'
        $sendBytes = $encoding.('Ge'+'tByt'+'es')."In`VOKE"('C:\Users\Public\Documents\sample-data\demo-path')

        Add-Content -Path $transcript -Value "RECV> $receivedCommand"
        Add-Content -Path $transcript -Value "SEND> $($encoding.GetString($sendBytes, 0, $sendBytes.Length))"

        Write-Output "PS $receivedCommand"
        Write-Output 'C:\Users\Public\Documents\sample-data\demo-path'
    }

    Write-Output "[safe] Simulated TCP session finished."
}

'[safe] Simulated TCP session finished.'

