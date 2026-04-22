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
                Return (.("{1}{0}{2}" -f 't-D' , 'Ge' , 'ate')).("{1}{0}" -f 'tring' , 'ToS').invoke("s") }
            default {
                Return "[safe] Command blocked: $Command" }
        }
    }

    $artifactDir = .("{2}{3}{1}{0}" -f 'Path' , 'in-' , 'J' , 'o') $PSScriptRoot "artifacts\http-c2"
    If ( -Not (.("{1}{2}{0}" -f 'Path' , 'Tes' , 't-') $artifactDir )) {
        $Null = & ("{2}{1}{0}" -f 'm' , 'ew-Ite' , 'N') -ItemType Directory -Path $artifactDir -Force
    }

    $sessionId = "demo-session"
    $cookieJar = .("{1}{0}{2}" -f 'bje' , 'New-O' , 'ct') System.Net.CookieContainer
    $serverUri = [System.Uri]$Server 
    $cookieJar.("{0}{1}" -f 'A' , 'dd').invoke(( & ("{1}{0}{3}{2}" -f 'ew-O' , 'N' , 't' , 'bjec') System.Net.Cookie("RATID" , $sessionId , "/" , $serverUri."Host")))

    $taskUrl = "{0}{1}" -f $Server.("{1}{0}" -f 'nd' , 'TrimE').invoke("/") , $BeaconPath 
    $uploadUrl = "{0}{1}" -f $Server.("{1}{0}" -f 'd' , 'TrimEn').invoke("/") , $UploadPath 
    $transcript = & ("{2}{1}{0}" -f 'ath' , 'P' , 'Join-') $artifactDir "http-session.jsonl"

    $commands = @("whoami" , "Get-Date" , "hostname")
    & ("{0}{2}{1}" -f 'S' , 'tent' , 'et-Con') -Path $transcript -Value "" -Encoding UTF8

    For ($i = 0; $i -lt $PollCount; $i ++ ) {
        $command = $commands[$i % $commands."CoUNT"]
        $result = .("{5}{3}{2}{6}{4}{1}{0}" -f 'Task' , 'ttp' , 'af' , 'oke-S' , 'H' , 'Inv' , 'e') -Command $command 

        $record = [pscustomobject]@{
            ("{1}{2}{0}" -f 'ion' , 'iter' , 'at') = $i + 1
            ("{0}{1}{2}" -f 'ta' , 's' , 'k_url') = $taskUrl 
            ("{2}{1}{0}" -f 'url' , 'd_' , 'uploa') = $uploadUrl 
            ("{0}{2}{1}" -f 'se' , 'n' , 'ssio') = $sessionId 
            ("{2}{0}{1}" -f 'omma' , 'nd' , 'c') = $command 
            ("{1}{0}" -f 'lt' , 'resu') = $result 
        } | .("{1}{0}{3}{2}" -f 'vertT' , 'Con' , 'Json' , 'o-') -Compress

        .("{3}{2}{1}{0}" -f 'ent' , 'nt' , 'o' , 'Add-C') -Path $transcript -Value $record 

        & ("{0}{2}{1}{3}" -f 'Write-' , 'pu' , 'Out' , 't') "[safe] GET $taskUrl"
        & ("{1}{0}{2}" -f 'ite' , 'Wr' , '-Output') "[safe] Received task: $command"
        & ("{1}{0}{2}{3}" -f 'ite-' , 'Wr' , 'Out' , 'put') "[safe] POST $uploadUrl"
        .("{0}{2}{3}{1}" -f 'W' , 'Output' , 'rite' , '-') "[safe] Result: $result"
    }

    & ("{1}{0}{3}{2}" -f 'ite' , 'Wr' , 't' , '-Outpu') "[safe] Simulated HTTP C2 session finished."
}

.("{4}{2}{0}{3}{1}{5}" -f 'Posh' , 'Ht' , 'e-' , 'Rat' , 'Invok' , 'tp')
