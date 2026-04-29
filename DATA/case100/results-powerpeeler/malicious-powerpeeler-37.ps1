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
            "Get-Date" { return (.('Get-'+'D'+'ate')).("{0}{1}"-f'ToS','tring').Invoke("s") }
            default { return "[safe] Command blocked: $Command" }
        }
    }
    $artifactDir = .('Joi'+'n'+'-Pat'+'h') $PSScriptRoot "artifacts\http-c2"
    if (-not (.('Test-P'+'at'+'h') $artifactDir)) {
        $null = &('Ne'+'w-I'+'tem') -ItemType Directory -Path $artifactDir -Force
    }
    $sessionId = "demo-session"
    $cookieJar = .('New-Ob'+'jec'+'t') System.Net.CookieContainer
    $serverUri = [System.Uri]$Server
    $cookieJar.("{0}{1}" -f 'A','dd').Invoke((&('New-'+'O'+'b'+'ject') System.Net.Cookie("RATID", $sessionId, "/", $serverUri."HO`sT")))
    $taskUrl = "{0}{1}" -f $Server.("{1}{0}"-f 'd','TrimEn').Invoke("/"), $BeaconPath
    $uploadUrl = "{0}{1}" -f $Server.("{0}{1}{2}" -f 'Trim','En','d').Invoke("/"), $UploadPath
    $transcript = &('J'+'o'+'in-'+'Path') $artifactDir "http-session.jsonl"
    $commands = @("whoami", "Get-Date", "hostname")
    .('S'+'et-Conten'+'t') -Path $transcript -Value "" -Encoding UTF8
    for ($i = 0; $i -lt $PollCount; $i++) {
        $command = $commands[$i % $commands."c`ouNT"]
        $result = .('In'+'voke-Sa'+'f'+'eHttpTask') -Command $command
        $record = [pscustomobject]@{
            ("{2}{0}{1}" -f 'eratio','n','it') = $i + 1
            ("{0}{1}{2}" -f 'task_','u','rl') = $taskUrl
            ("{2}{1}{0}" -f'url','pload_','u') = $uploadUrl
            ("{1}{2}{0}"-f'on','sess','i') = $sessionId
            ("{0}{1}" -f 'com','mand') = $command
            ("{1}{0}" -f'lt','resu') = $result
        } | .('C'+'on'+'ve'+'rtTo-Json') -Compress
        .('Add-'+'Con'+'tent') -Path $transcript -Value $record
        &('Wri'+'t'+'e-Outpu'+'t') "[safe] GET $taskUrl"
        &('Wri'+'te-'+'Output') "[safe] Received task: $command"
        &('Wr'+'i'+'te-Output') "[safe] POST $uploadUrl"
        &('Write-Out'+'p'+'ut') "[safe] Result: $result"
    }
    .('W'+'rite-'+'Outp'+'ut') "[safe] Simulated HTTP C2 session finished."
}
.('I'+'nvoke-Po'+'shRatH'+'ttp')
