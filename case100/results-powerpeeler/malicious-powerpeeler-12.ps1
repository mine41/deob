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
        switch ($Command) {
            "whoami" { return "lab\demo-user" }
            "hostname" { return "demo-host" }
            "Get-Date" { return (&('Get'+'-'+'Date')).("{2}{0}{1}" -f'r','ing','ToSt').Invoke("s") }
            "Get-Location" { return (.('Get-'+'Lo'+'c'+'ation'))."P`ATh" }
            default { return "[safe] Command blocked: $Command" }
        }
    }
    $artifactDir = &('Jo'+'in-Pat'+'h') $PSScriptRoot "artifacts\tcp-c2"
    if (-not (.('Test-'+'Path') $artifactDir)) {
        $null = .('New-I'+'tem') -ItemType Directory -Path $artifactDir -Force
    }
    $encoding = .('New-'+'Objec'+'t') System.Text.ASCIIEncoding
    $transcript = .('Join-P'+'ath') $artifactDir "session.txt"
    $mode = if ($Bind) { "bind" } else { "reverse" }
    .('Set'+'-'+'Content') -Path $transcript -Value "[safe] Starting simulated $mode TCP session to $IPAddress`:$Port" -Encoding UTF8
    .('Writ'+'e-O'+'ut'+'put') "[safe] Simulating $mode TCP session to $IPAddress`:$Port"
    $commands = @("whoami", "Get-Date", "hostname", "Get-Location")
    foreach ($command in $commands) {
        $commandBytes = $encoding.("{0}{2}{1}"-f 'G','tBytes','e').Invoke($command)
        $receivedCommand = $encoding."gE`TsTr`iNG"($commandBytes, 0, $commandBytes."l`ENGth")
        $sendback = .('Invoke'+'-S'+'af'+'eCommand') -Command $receivedCommand
        $sendBytes = $encoding.("{2}{0}{1}"-f 'etByte','s','G').Invoke($sendback)
        &('Add-'+'C'+'o'+'ntent') -Path $transcript -Value "RECV> $receivedCommand"
        &('Add-'+'Cont'+'ent') -Path $transcript -Value "SEND> $($encoding.GetString($sendBytes, 0, $sendBytes.Length))"
        &('Wr'+'ite-Out'+'put') "PS $receivedCommand"
        .('Wri'+'te-Out'+'put') $sendback
    }
    .('Wr'+'i'+'te-Output') "[safe] Simulated TCP session finished."
}
&('Invok'+'e-'+'P'+'owe'+'rShellT'+'cp') -IPAddress "198.51.100.25" -Port 4444 -Reverse
