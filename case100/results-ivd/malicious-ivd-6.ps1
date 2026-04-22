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
                Return (Get-Date ).("{0}{1}" -f 'ToStr' , 'ing')."iNvOkE"("s") }
            default {
                Return "[safe] Command blocked: $Command" }
        }
    }

    $artifactDir = Join-Path $PSScriptRoot "artifacts\http-c2"
    If ( -Not (Test-Path $artifactDir )) {
        $Null = New-Item -ItemType Directory -Path $artifactDir -Force
    }

    $sessionId = "demo-session"
    $cookieJar = New-Object System.Net.CookieContainer
    $serverUri = [System.Uri]$Server 
    $cookieJar.("{1}{0}" -f 'd' , 'Ad')."INvOke"((New-Object System.Net.Cookie("RATID" , $sessionId , "/" , $serverUri."HOST")))

    $taskUrl = "{0}{1}" -f $Server.("{2}{1}{0}" -f 'End' , 'im' , 'Tr')."iNvokE"("/") , $BeaconPath 
    $uploadUrl = "{0}{1}" -f $Server.("{1}{2}{0}" -f 'nd' , 'Tr' , 'imE')."InVOKE"("/") , $UploadPath 
    $transcript = Join-Path $artifactDir "http-session.jsonl"

    $commands = @("whoami" , "Get-Date" , "hostname")
    Set-Content -Path $transcript -Value "" -Encoding UTF8

    For ($i = 0; $i -lt $PollCount; $i ++ ) {
        $command = $commands[$i % $commands."cOUNT"]
        $result = invoke-safehttptask -Command $command 

        $record = [pscustomobject]@{
            ("{0}{1}{2}" -f 'i' , 'tera' , 'tion') = $i + 1
            ("{1}{0}{2}" -f 'a' , 't' , 'sk_url') = $taskUrl 
            ("{0}{1}{2}" -f 'uploa' , 'd' , '_url') = $uploadUrl 
            ("{0}{1}{2}" -f 'sess' , 'io' , 'n') = $sessionId 
            ("{0}{2}{1}" -f 'co' , 'nd' , 'mma') = $command 
            ("{1}{0}" -f 'ult' , 'res') = $result 
        } | ConvertTo-Json -Compress

        Add-Content -Path $transcript -Value $record 

        Write-Output "[safe] GET $taskUrl"
        Write-Output "[safe] Received task: $command"
        Write-Output "[safe] POST $uploadUrl"
        Write-Output "[safe] Result: $result"
    }

    Write-Output "[safe] Simulated HTTP C2 session finished."
}

invoke-poshrathttp 
