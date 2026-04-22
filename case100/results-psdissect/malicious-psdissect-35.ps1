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
            "Get-Date" { return (.("{1}{0}{2}" -f 't-D','Ge','ate')).("{1}{0}"-f 'tring','ToS').Invoke("s") }
            default { return "[safe] Command blocked: $Command" }
        }
    }

    $artifactDir = .("{2}{3}{1}{0}" -f 'Path','in-','J','o') $PSScriptRoot "artifacts\http-c2"
    if (-not (.("{1}{2}{0}" -f 'Path','Tes','t-') $artifactDir)) {
        $null = &("{2}{1}{0}"-f'm','ew-Ite','N') -ItemType Directory -Path $artifactDir -Force
    }

    $sessionId = "demo-session"
    $cookieJar = .("{1}{0}{2}" -f 'bje','New-O','ct') System.Net.CookieContainer
    $serverUri = [System.Uri]$Server
    $cookieJar.("{0}{1}"-f 'A','dd').Invoke((&("{1}{0}{3}{2}"-f'ew-O','N','t','bjec') System.Net.Cookie("RATID", 'demo-session', "/", $serverUri."Ho`st")))

    $taskUrl = "{0}{1}" -f $Server.("{1}{0}" -f'nd','TrimE').Invoke("/"), $BeaconPath
    $uploadUrl = "{0}{1}" -f $Server.("{1}{0}" -f 'd','TrimEn').Invoke("/"), $UploadPath
    $transcript = &("{2}{1}{0}" -f 'ath','P','Join-') $artifactDir "http-session.jsonl"

    $commands = @("whoami", "Get-Date", "hostname")
    &("{0}{2}{1}" -f'S','tent','et-Con') -Path $transcript -Value "" -Encoding UTF8

    for ($i = 0; 0 -lt $PollCount; $i++) {
        $command = $commands[$i % $commands."CoU`NT"]
        $result = .("{5}{3}{2}{6}{4}{1}{0}" -f 'Task','ttp','af','oke-S','H','Inv','e') -Command $command

        $record = [pscustomobject]@{
            'iteration' = $i + 1
            'task_url' = $taskUrl
            'upload_url' = $uploadUrl
            'session' = $sessionId
            'command' = $command
            'result' = $result
        } | .("{1}{0}{3}{2}" -f 'vertT','Con','Json','o-') -Compress

        .("{3}{2}{1}{0}" -f 'ent','nt','o','Add-C') -Path $transcript -Value $record

        &("{0}{2}{1}{3}" -f'Write-','pu','Out','t') "[safe] GET $taskUrl"
        &("{1}{0}{2}" -f'ite','Wr','-Output') "[safe] Received task: $command"
        &("{1}{0}{2}{3}" -f'ite-','Wr','Out','put') "[safe] POST $uploadUrl"
        .("{0}{2}{3}{1}"-f 'W','Output','rite','-') "[safe] Result: $result"
    }

    &("{1}{0}{3}{2}" -f'ite','Wr','t','-Outpu') "[safe] Simulated HTTP C2 session finished."
}

'[safe] Simulated HTTP C2 session finished.'

