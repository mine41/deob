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
            "Get-Date" { return (&("{0}{2}{1}" -f'geT','e','-dAT')).ToString("s") }
            "Get-Location" { return (.("{0}{2}{1}" -f 'GET-lo','ON','CATi')).Path }
            default { return "[safe] Command blocked: $Command" }
        }
    }
    $artifactDir = &("{2}{1}{0}"-f 'ATH','oIn-P','j') $PSScriptRoot "artifacts\tcp-c2"
    if (-not (.("{1}{2}{0}"-f'pAth','t','est-') $artifactDir)) {
        $null = &("{0}{1}{2}"-f 'NEW','-iTE','M') -ItemType Directory -Path $artifactDir -Force
    }
    $encoding = .("{0}{1}{2}" -f 'Ne','W-','ObJEcT') System.Text.ASCIIEncoding
    $transcript = &("{1}{0}{2}"-f 'oi','J','n-pATH') $artifactDir "session.txt"
    $mode = if ($Bind) { "bind" } else { "reverse" }
    &("{0}{2}{1}" -f 'S','-COntENt','ET') -Path $transcript -Value "[safe] Starting simulated $mode TCP session to $IPAddress`:$Port" -Encoding UTF8
    &("{3}{1}{2}{0}" -f'e-OuTPUT','RI','t','W') "[safe] Simulating $mode TCP session to $IPAddress`:$Port"
    $commands = @("whoami", "Get-Date", "hostname", "Get-Location")
    foreach ($command in $commands) {
        $commandBytes = $encoding.GetBytes($command)
        $receivedCommand = $encoding.GetString($commandBytes, 0, $commandBytes.Length)
        $sendback = &("{4}{3}{0}{1}{2}" -f'-S','AFeCOMM','aND','e','InVok') -Command $receivedCommand
        $sendBytes = $encoding.GetBytes($sendback)
        .("{0}{1}{3}{2}"-f 'ad','D-C','T','oNTN') -Path $transcript -Value "RECV> $receivedCommand"
        &("{0}{3}{1}{2}"-f'a','n','TEnT','dD-cO') -Path $transcript -Value "SEND> $($encoding.GetString($sendBytes, 0, $sendBytes.Length))"
        .("{3}{2}{0}{1}" -f 'e-','oUTPUT','it','wR') "PS $receivedCommand"
        .("{3}{0}{1}{2}"-f'E-oUT','p','Ut','wRIt') $sendback
    }
    &("{1}{3}{2}{0}"-f 'uTPut','WRiT','-O','e') "[safe] Simulated TCP session finished."
}
&("{4}{2}{3}{1}{0}" -f 'CP','llT','NV','oKE-POwErsH','i') -IPAddress "198.51.100.25" -Port 4444 -Reverse
