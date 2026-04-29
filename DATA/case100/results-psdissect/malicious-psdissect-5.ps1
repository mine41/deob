function Invoke-PoshRatHttp {
    [CmdletBinding()]
    param(
        [string]$Server = "https://c2.example.invalid",
        [string]$BeaconPath = "/rat/beacon",
        [string]$UploadPath = "/rat/upload",
        [int]$PollCount = 3
    )

    function Invoke-SafeHttpTask {
        param([string]$Command)

        switch ($Command) {
            "whoami" { return "lab\demo-user" }
            "hostname" { return "demo-host" }
            "Get-Date" { return (& Get-Date).("{2}{1}{0}"-f'ng','oStri','T').Invoke("s") }
            default { return "[safe] Command blocked: $Command" }
        }
    }

    $artifactDir = & Join-Path $PSScriptRoot "artifacts\http-c2"
    if (-not (. Test-Path $artifactDir)) {
        $null = . New-Item -ItemType Directory -Path $artifactDir -Force
    }

    $sessionId = "demo-session"
    $cookieJar = & New-Object System.Net.CookieContainer
    $serverUri = [System.Uri]$Server
    $cookieJar.("{0}{1}" -f'Ad','d').Invoke((. New-Object System.Net.Cookie("RATID", 'demo-session', "/", $serverUri."ho`st")))

    $taskUrl = "{0}{1}" -f $Server.("{2}{0}{1}" -f 'rimE','nd','T').Invoke("/"), $BeaconPath
    $uploadUrl = "{0}{1}" -f $Server.("{1}{0}"-f 'End','Trim').Invoke("/"), $UploadPath
    $transcript = & Join-Path $artifactDir "http-session.jsonl"

    $commands = @("whoami", "Get-Date", "hostname")
    & Set-Content -Path $transcript -Value "" -Encoding UTF8

    for ($i = 0; 0 -lt $PollCount; $i++) {
        $command = $commands[$i % $commands."cou`Nt"]
        $result = .('I'+'nvoke-S'+'afe'+'Htt'+'p'+'Tas'+'k') -Command $command

        $record = [pscustomobject]@{
            'iteration' = $i + 1
            'task_url' = $taskUrl
            'upload_url' = $uploadUrl
            'session' = $sessionId
            'command' = $command
            'result' = $result
        } | . ConvertTo-Json -Compress

        & Add-Content -Path $transcript -Value $record

        . Write-Output "[safe] GET $taskUrl"
        & Write-Output "[safe] Received task: $command"
        . Write-Output "[safe] POST $uploadUrl"
        . Write-Output "[safe] Result: $result"
    }

    & Write-Output "[safe] Simulated HTTP C2 session finished."
}

'[safe] Simulated HTTP C2 session finished.'

