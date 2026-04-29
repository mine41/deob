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
        switch ($Command) {
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
    Set-Content -Path $transcript -Value "[safe] Starting simulated $mode TCP session to $IPAddress`:$Port" -Encoding UTF8
    Write-Output "[safe] Simulating $mode TCP session to $IPAddress`:$Port"
    $commands = @("whoami", "Get-Date", "hostname", "Get-Location")
    foreach ($command in $commands) {
        $commandBytes = $encoding.('G'+'etByt'+'es')."inv`oKE"($command)
        $receivedCommand = $encoding."gET`sTR`ing"($commandBytes, 0, $commandBytes."LEN`G`TH")
        $sendback = Invoke-SafeCommand -Command $receivedCommand
        $sendBytes = $encoding.('Ge'+'tByt'+'es')."In`VOKE"($sendback)
        Add-Content -Path $transcript -Value "RECV> $receivedCommand"
        Add-Content -Path $transcript -Value "SEND> $($encoding.GetString($sendBytes, 0, $sendBytes.Length))"
        Write-Output "PS $receivedCommand"
        Write-Output $sendback
    }
    Write-Output "[safe] Simulated TCP session finished."
}
Invoke-PowerShellTcp -IPAddress "198.51.100.25" -Port 4444 -Reverse
