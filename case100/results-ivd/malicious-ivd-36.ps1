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
                Return (.("{0}{2}{1}" -f 'gEt' , 'aTE' , '-D')).ToString("s") }
            default {
                Return "[safe] Command blocked: $Command" }
        }
    }

    $artifactDir = & ("{0}{2}{1}" -f 'JoIN-' , 'TH' , 'PA') $PSScriptRoot "artifacts\http-c2"
    If ( -Not ( & ("{0}{2}{1}" -f 't' , 'Th' , 'EST-Pa') $artifactDir )) {
        $Null = .("{1}{2}{0}" -f 'Tm' , 'n' , 'w-I') -ItemType Directory -Path $artifactDir -Force
    }

    $sessionId = "demo-session"
    $cookieJar = & ("{2}{1}{0}" -f 'Ct' , 'W-ObJe' , 'nE') System.Net.CookieContainer
    $serverUri = [System.Uri]$Server 
    $cookieJar.Add((.("{1}{2}{0}" -f 'ObJEcT' , 'nE' , 'w-') System.Net.Cookie("RATID" , $sessionId , "/" , $serverUri.host)))

    $taskUrl = "{0}{1}" -f $Server.trimend("/") , $BeaconPath 
    $uploadUrl = "{0}{1}" -f $Server.trimend("/") , $UploadPath 
    $transcript = & ("{2}{0}{1}" -f '-PAT' , 'H' , 'jOIn') $artifactDir "http-session.jsonl"

    $commands = @("whoami" , "Get-Date" , "hostname")
    .("{0}{3}{2}{1}" -f 'Se' , 'NT' , '-CoNT' , 't') -Path $transcript -Value "" -Encoding UTF8

    For ($i = 0; $i -lt $PollCount; $i ++ ) {
        $command = $commands[$i % $commands.count]
        $result = & ("{1}{3}{0}{2}{4}" -f 'ehTtP' , 'INvo' , 'ta' , 'k-saF' , 'Sk') -Command $command 

        $record = [pscustomobject]@{
            iteration = $i + 1
            task_url = $taskUrl 
            upload_url = $uploadUrl 
            session = $sessionId 
            command = $command 
            result = $result 
        } | & ("{2}{1}{3}{4}{0}" -f 'SoN' , 'Nv' , 'co' , 'ErT' , 'tO-J') -Compress

        .("{1}{2}{0}" -f 'ONtENT' , 'adD' , '-C') -Path $transcript -Value $record 

        & ("{3}{0}{2}{1}" -f 'iTE' , 'TPuT' , '-Ou' , 'WR') "[safe] GET $taskUrl"
        .("{1}{2}{0}" -f 'tE-oUtpUT' , 'WR' , 'I') "[safe] Received task: $command"
        .("{3}{2}{0}{1}" -f 'utpU' , 'T' , 'O' , 'wRitE-') "[safe] POST $uploadUrl"
        & ("{1}{0}{2}{3}" -f 'riT' , 'w' , 'E' , '-OUTPUt') "[safe] Result: $result"
    }

    .("{3}{2}{0}{1}" -f 'Utp' , 'Ut' , 'TE-O' , 'WRi') "[safe] Simulated HTTP C2 session finished."
}

& ("{2}{1}{3}{4}{0}" -f 'TTP' , 'VOke' , 'IN' , '-poShR' , 'atH')
