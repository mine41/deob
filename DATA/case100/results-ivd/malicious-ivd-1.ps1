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
                Return (.("{1}{2}{0}" -f 'te' , 'Ge' , 't-Da')).("{0}{1}{2}" -f 'T' , 'o' , 'String').invoke("s") }
            default {
                Return "[safe] Command blocked: $Command" }
        }
    }

    $artifactDir = .("{2}{1}{0}" -f 'Path' , '-' , 'Join') $PSScriptRoot "artifacts\http-c2"
    If ( -Not (.("{2}{1}{3}{0}" -f 'ath' , '-' , 'Test' , 'P') $artifactDir )) {
        $Null = & ("{2}{1}{0}" -f 'Item' , '-' , 'New') -ItemType Directory -Path $artifactDir -Force
    }

    $sessionId = "demo-session"
    $cookieJar = .("{2}{1}{0}" -f 'ject' , 'ew-Ob' , 'N') System.Net.CookieContainer
    $serverUri = [System.Uri]$Server 
    $cookieJar.("{1}{0}" -f 'd' , 'Ad').invoke(( & ("{2}{0}{1}" -f '-Obj' , 'ect' , 'New') System.Net.Cookie("RATID" , $sessionId , "/" , $serverUri."host")))

    $taskUrl = "{0}{1}" -f $Server.("{1}{2}{0}" -f 'nd' , 'T' , 'rimE').invoke("/") , $BeaconPath 
    $uploadUrl = "{0}{1}" -f $Server.("{1}{2}{0}" -f 'End' , 'Tri' , 'm').invoke("/") , $UploadPath 
    $transcript = & ("{0}{2}{1}" -f 'Joi' , '-Path' , 'n') $artifactDir "http-session.jsonl"

    $commands = @("whoami" , "Get-Date" , "hostname")
    .("{0}{1}{2}" -f 'Set-Co' , 'n' , 'tent') -Path $transcript -Value "" -Encoding UTF8

    For ($i = 0; $i -lt $PollCount; $i ++ ) {
        $command = $commands[$i % $commands."COUnT"]
        $result = .("{4}{5}{3}{0}{1}{2}" -f 'pT' , 'a' , 'sk' , 't' , 'I' , 'nvoke-SafeHt') -Command $command 

        $record = [pscustomobject]@{
            ("{0}{2}{1}" -f 'ite' , 'n' , 'ratio') = $i + 1
            ("{2}{0}{1}" -f 'ur' , 'l' , 'task_') = $taskUrl 
            ("{1}{3}{2}{0}" -f 'oad_url' , 'u' , 'l' , 'p') = $uploadUrl 
            ("{2}{1}{0}" -f 'on' , 'i' , 'sess') = $sessionId 
            ("{2}{0}{1}" -f 'mman' , 'd' , 'co') = $command 
            ("{1}{2}{0}" -f 't' , 'r' , 'esul') = $result 
        } | .("{1}{2}{0}" -f '-Json' , 'Co' , 'nvertTo') -Compress

        & ("{2}{1}{0}{3}" -f 'd-Conten' , 'd' , 'A' , 't') -Path $transcript -Value $record 

        .("{0}{3}{1}{2}" -f 'W' , 'tpu' , 't' , 'rite-Ou') "[safe] GET $taskUrl"
        .("{2}{0}{1}" -f 'Out' , 'put' , 'Write-') "[safe] Received task: $command"
        & ("{0}{3}{2}{1}" -f 'Wr' , 'ut' , 'utp' , 'ite-O') "[safe] POST $uploadUrl"
        & ("{1}{0}{2}{3}" -f 'te-Ou' , 'Wri' , 'tpu' , 't') "[safe] Result: $result"
    }

    .("{3}{1}{2}{0}" -f 'put' , 'r' , 'ite-Out' , 'W') "[safe] Simulated HTTP C2 session finished."
}

& ("{1}{3}{4}{2}{0}" -f 'atHttp' , 'Inv' , 'oshR' , 'oke' , '-P')
