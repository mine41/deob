function Invoke-PowerShellTcp {
    [CmdletBinding(DefaultParameterSetName = "reverse")]
    param(
        [Parameter(Position = 0, Mandatory = $true, ParameterSetName = "reverse")]
        [Parameter(Position = 0, Mandatory = $true, ParameterSetName = "bind")]
        [string]$IPAddress,

        [Parameter(Position = 1, Mandatory = $true, ParameterSetName = "reverse")]
        [Parameter(Position = 1, Mandatory = $true, ParameterSetName = "bind")]
        [int]$Port,

        [Parameter(ParameterSetName = "reverse")]
        [switch]$Reverse,

        [Parameter(ParameterSetName = "bind")]
        [switch]$Bind
    )

    function Invoke-SafeCommand {
        param([string]$Command)

        switch ($Command) {
            "whoami" { return "lab\demo-user" }
            "hostname" { return "demo-host" }
            "Get-Date" { return (& Get-Date).ToString("s") }
            "Get-Location" { return (. Get-Location).Path }
            default { return "[safe] Command blocked: $Command" }
        }
    }

    $artifactDir = & Join-Path $PSScriptRoot "artifacts\tcp-c2"
    if (-not (. Test-Path $artifactDir)) {
        $null = & New-Item -ItemType Directory -Path $artifactDir -Force
    }

    $encoding = . New-Object System.Text.ASCIIEncoding
    $transcript = & Join-Path $artifactDir "session.txt"
    $mode = if ($Bind) { "bind" } else { "reverse" }

    & Set-Content -Path $transcript -Value "[safe] Starting simulated $mode TCP session to $IPAddress`:$Port" -Encoding UTF8
    & Write-Output "[safe] Simulating $mode TCP session to $IPAddress`:$Port"

    $commands = @("whoami", "Get-Date", "hostname", "Get-Location")

    foreach ($command in $commands) {
        $commandBytes = $encoding.GetBytes($command)
        $receivedCommand = $encoding.GetString($commandBytes, 0, $commandBytes.Length)
        $sendback = &("{4}{3}{0}{1}{2}" -f'-S','AFeCOMM','aND','e','InVok') -Command $receivedCommand
        $sendBytes = $encoding.GetBytes($sendback)

        .("{0}{1}{3}{2}"-f 'ad','D-C','T','oNTN') -Path $transcript -Value "RECV> $receivedCommand"
        & Add-Content -Path $transcript -Value "SEND> $($encoding.GetString($sendBytes, 0, $sendBytes.Length))"

        . Write-Output "PS $receivedCommand"
        . Write-Output $sendback
    }

    & Write-Output "[safe] Simulated TCP session finished."
}

&("{4}{2}{3}{1}{0}" -f 'CP','llT','NV','oKE-POwErsH','i') -IPAddress "198.51.100.25" -Port 4444 -Reverse

