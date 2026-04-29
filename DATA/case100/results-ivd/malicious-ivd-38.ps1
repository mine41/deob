function Invoke-PowerShellTcp {
    [CmdletBinding(DEfAUltpArameterSEtNAME = "reverse")]
    param(
        [Parameter(POsItION = 0 , mAndATory = $true , paRaMeTErSETnAMe = "reverse")]
        [Parameter(PosiTiON = 0 , mANDATORY = $true , paRaMeTErseTnaME = "bind")]
        [string]$IPAddress , 

        [Parameter(posITion = 1 , MandatOry = $true , pARAMEteRsEtNAmE = "reverse")]
        [Parameter(PositION = 1 , MaNdaTORy = $true , PaRAmETerSETnAme = "bind")]
        [int]$Port , 

        [Parameter(pARaMETerSETnamE = "reverse")]
        [switch]$Reverse , 

        [Parameter(PARamEteRSetNaME = "bind")]
        [switch]$Bind 
    )

    function Invoke-SafeCommand {
        param([string]$Command )

        switch ($Command ) {
            "whoami" { return "lab\demo-user" }
            "hostname" { return "demo-host" }
            "Get-Date" { return (.("{2}{0}{1}" -f '-Dat' , 'e' , 'Get')).("{0}{2}{1}" -f 'ToStri' , 'g' , 'n').Invoke("s") }
            "Get-Location" { return (.("{0}{1}{2}{3}" -f 'Get-L' , 'o' , 'catio' , 'n'))."Pa`TH" }
            default { return "[safe] Command blocked: $Command" }
        }
    }

    $artifactDir = .("{2}{0}{1}" -f 'i' , 'n-Path' , 'Jo') $PSScriptRoot "artifacts\tcp-c2"
    if ( -not ( & ("{1}{0}" -f 'ath' , 'Test-P') $artifactDir )) {
        $null = .("{2}{0}{1}" -f 't' , 'em' , 'New-I') -ItemType Directory -Path $artifactDir -Force
    }

    $encoding = & ("{1}{2}{0}" -f 'bject' , 'New' , '-O') System.Text.ASCIIEncoding
    $transcript = & ("{0}{2}{1}" -f 'Joi' , 'th' , 'n-Pa') $artifactDir "session.txt"
    $mode = if ($Bind ) { "bind" } else { "reverse" }

    .("{1}{2}{0}" -f 'tent' , 'Set-C' , 'on') -Path $transcript -Value "[safe] Starting simulated $mode TCP session to $IPAddress`:$Port" -Encoding UTF8
    & ("{0}{1}{2}" -f 'Wr' , 'ite-O' , 'utput') "[safe] Simulating $mode TCP session to $IPAddress`:$Port"

    $commands = @("whoami" , "Get-Date" , "hostname" , "Get-Location")

    foreach ($command in $commands ) {
        $commandBytes = $encoding.("{1}{2}{0}" -f 'tBytes' , 'G' , 'e').Invoke($command )
        $receivedCommand = $encoding."GETs`TR`INg"($commandBytes , 0 , $commandBytes."l`engTH")
        $sendback = & ("{2}{0}{3}{1}" -f 'e-SafeComma' , 'd' , 'Invok' , 'n') -Command $receivedCommand 
        $sendBytes = $encoding.("{0}{2}{1}" -f 'GetB' , 'es' , 'yt').Invoke($sendback )

        .("{3}{2}{0}{1}" -f 'n' , 't' , 'te' , 'Add-Con') -Path $transcript -Value "RECV> $receivedCommand"
        .("{2}{3}{1}{0}" -f 'nt' , 'e' , 'Add-Co' , 'nt') -Path $transcript -Value "SEND> $($encoding.GetString($sendBytes, 0, $sendBytes.Length))"

        & ("{0}{1}{2}" -f 'Write' , '-Outpu' , 't') "PS $receivedCommand"
        .("{2}{0}{1}" -f 'rit' , 'e-Output' , 'W') $sendback 
    }

    & ("{1}{0}{2}" -f '-Out' , 'Write' , 'put') "[safe] Simulated TCP session finished."
}

& ("{1}{3}{0}{4}{2}" -f 'owerS' , 'Invo' , 'cp' , 'ke-P' , 'hellT') -IPAddress "198.51.100.25" -Port 4444 -Reverse
