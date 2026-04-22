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
                Return ( & ('Get-' + 'Da' + 'te')).("{2}{1}{0}" -f 'ng' , 'oStri' , 'T').invoke("s") }
            default {
                Return "[safe] Command blocked: $Command" }
        }
    }

    $artifactDir = & ('J' + 'oin-' + 'Pa' + 'th') $PSScriptRoot "artifacts\http-c2"
    If ( -Not (.('Tes' + 't-P' + 'ath') $artifactDir )) {
        $Null = .('New-I' + 'tem') -ItemType Directory -Path $artifactDir -Force
    }

    $sessionId = "demo-session"
    $cookieJar = & ('New-O' + 'bjec' + 't') System.Net.CookieContainer
    $serverUri = [System.Uri]$Server 
    $cookieJar.("{0}{1}" -f 'Ad' , 'd').invoke((.('New-O' + 'b' + 'j' + 'ect') System.Net.Cookie("RATID" , $sessionId , "/" , $serverUri."host")))

    $taskUrl = "{0}{1}" -f $Server.("{2}{0}{1}" -f 'rimE' , 'nd' , 'T').invoke("/") , $BeaconPath 
    $uploadUrl = "{0}{1}" -f $Server.("{1}{0}" -f 'End' , 'Trim').invoke("/") , $UploadPath 
    $transcript = & ('Join' + '-P' + 'ath') $artifactDir "http-session.jsonl"

    $commands = @("whoami" , "Get-Date" , "hostname")
    & ('Se' + 't-Con' + 'ten' + 't') -Path $transcript -Value "" -Encoding UTF8

    For ($i = 0; $i -lt $PollCount; $i ++ ) {
        $command = $commands[$i % $commands."couNt"]
        $result = .('I' + 'nvoke-S' + 'afe' + 'Htt' + 'p' + 'Tas' + 'k') -Command $command 

        $record = [pscustomobject]@{
            ("{2}{1}{0}" -f 'tion' , 'a' , 'iter') = $i + 1
            ("{1}{0}" -f '_url' , 'task') = $taskUrl 
            ("{1}{2}{0}" -f 'l' , 'upload' , '_ur') = $uploadUrl 
            ("{2}{0}{1}" -f 'si' , 'on' , 'ses') = $sessionId 
            ("{2}{1}{0}" -f 'd' , 'n' , 'comma') = $command 
            ("{1}{2}{0}" -f 't' , 'res' , 'ul') = $result 
        } | .('Conv' + 'ertTo-' + 'Json') -Compress

        & ('A' + 'dd-' + 'Co' + 'ntent') -Path $transcript -Value $record 

        .('Writ' + 'e-Outp' + 'u' + 't') "[safe] GET $taskUrl"
        & ('Wri' + 'te' + '-Outpu' + 't') "[safe] Received task: $command"
        .('W' + 'r' + 'ite-O' + 'utput') "[safe] POST $uploadUrl"
        .('Wr' + 'ite-Out' + 'p' + 'ut') "[safe] Result: $result"
    }

    & ('Write-Ou' + 'tp' + 'u' + 't') "[safe] Simulated HTTP C2 session finished."
}

& ('Invoke-PoshR' + 'at' + 'Htt' + 'p')
