Function Invoke-PoshRatHttp {
    [CmdletBinding()]
    Param(
        [String]$Server = "https://c2.example.invalid" , 
        [String]$BeaconPath = "/rat/beacon" , 
        [String]$UploadPath = "/rat/upload" , 
        [int]$PollCount = 3
    )

    Function Invoke-SafeHttpTask {
        Param([String]$Command )

        Switch ($Command ) {
            "whoami" {
                Return "lab\demo-user" }
            "hostname" {
                Return "demo-host" }
            "Get-Date" {
                Return (.("{1}{0}{2}" -f 'T' , 'geT-DA' , 'e')).ToString("s") }
            default {
                Return "[safe] Command blocked: $Command" }
        }
    }

    $artifactDir = & ("{3}{0}{2}{1}" -f '-Pa' , 'h' , 't' , 'jOIN') $PSScriptRoot "artifacts\http-c2"
    If ( -Not (.("{2}{0}{1}" -f '-p' , 'ath' , 'TeST') $artifactDir )) {
        $Null = & ("{1}{0}{2}" -f '-I' , 'NeW' , 'teM') -ItemType Directory -Path $artifactDir -Force
    }

    $sessionId = "demo-session"
    $cookieJar = .("{2}{1}{0}" -f 't' , 'OBJEC' , 'New-') System.Net.CookieContainer
    $serverUri = [System.Uri]$Server 
    $cookieJar.Add((.("{1}{2}{0}" -f 'T' , 'nEw-' , 'ObjEc') System.Net.Cookie("RATID" , $sessionId , "/" , $serverUri.host)))

    $taskUrl = "{0}{1}" -f $Server.trimend("/") , $BeaconPath 
    $uploadUrl = "{0}{1}" -f $Server.trimend("/") , $UploadPath 
    $transcript = & ("{2}{1}{0}" -f 'Ath' , 'N-p' , 'jOi') $artifactDir "http-session.jsonl"

    $commands = @("whoami" , "Get-Date" , "hostname")
    & ("{2}{0}{1}{3}" -f 'NT' , 'eN' , 'sET-Co' , 't') -Path $transcript -Value "" -Encoding UTF8

    For ($i = 0; $i -lt $PollCount; $i ++ ) {
        $command = $commands[$i % $commands.count]
        $result = & ("{3}{0}{1}{5}{6}{2}{4}" -f 'nV' , 'O' , 'AfEh' , 'i' , 'TtptASK' , 'kE' , '-s') -Command $command 

        $record = [pscustomobject]@{
            iteration = $i + 1
            task_url = $taskUrl 
            upload_url = $uploadUrl 
            session = $sessionId 
            command = $command 
            result = $result 
        } | .("{3}{2}{0}{1}" -f '-Js' , 'on' , 'Tto' , 'coNVER') -Compress

        & ("{3}{2}{0}{1}" -f 'ON' , 'tnT' , 'c' , 'aDD-') -Path $transcript -Value $record 

        & ("{1}{2}{3}{0}" -f 'tPuT' , 'wrIT' , 'e-' , 'ou') "[safe] GET $taskUrl"
        & ("{3}{1}{0}{2}" -f 'ITe-ouT' , 'R' , 'pUT' , 'W') "[safe] Received task: $command"
        .("{0}{1}{2}{3}" -f 'w' , 'RiTe-' , 'oUTPu' , 'T') "[safe] POST $uploadUrl"
        .("{2}{0}{1}" -f 'ITe-OuT' , 'PUT' , 'wR') "[safe] Result: $result"
    }

    .("{3}{1}{0}{2}" -f 'U' , '-O' , 'TPUt' , 'wriTE') "[safe] Simulated HTTP C2 session finished."
}

& ("{5}{0}{1}{4}{3}{2}" -f 'E-POs' , 'H' , 'Tp' , 'tht' , 'RA' , 'INVOk')
