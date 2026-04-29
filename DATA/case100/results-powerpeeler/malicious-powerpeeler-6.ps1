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
            "Get-Date" { return (Get-Date).("{0}{1}"-f'ToStr','ing')."i`NvOkE"("s") }
            default { return "[safe] Command blocked: $Command" }
        }
    }
    $artifactDir = Join-Path $PSScriptRoot "artifacts\http-c2"
    if (-not (Test-Path $artifactDir)) {
        $null = New-Item -ItemType Directory -Path $artifactDir -Force
    }
    $sessionId = "demo-session"
    $cookieJar = New-Object System.Net.CookieContainer
    $serverUri = [System.Uri]$Server
    $cookieJar.("{1}{0}" -f'd','Ad')."INv`Oke"((New-Object System.Net.Cookie("RATID", $sessionId, "/", $serverUri."H`OST")))
    $taskUrl = "{0}{1}" -f $Server.("{2}{1}{0}" -f'End','im','Tr')."i`NvokE"("/"), $BeaconPath
    $uploadUrl = "{0}{1}" -f $Server.("{1}{2}{0}" -f'nd','Tr','imE')."InV`O`KE"("/"), $UploadPath
    $transcript = Join-Path $artifactDir "http-session.jsonl"
    $commands = @("whoami", "Get-Date", "hostname")
    Set-Content -Path $transcript -Value "" -Encoding UTF8
    for ($i = 0; $i -lt $PollCount; $i++) {
        $command = $commands[$i % $commands."cO`UNT"]
        $result = Invoke-SafeHttpTask -Command $command
        $record = [pscustomobject]@{
            ("{0}{1}{2}"-f 'i','tera','tion') = $i + 1
            ("{1}{0}{2}" -f'a','t','sk_url') = $taskUrl
            ("{0}{1}{2}"-f 'uploa','d','_url') = $uploadUrl
            ("{0}{1}{2}" -f'sess','io','n') = $sessionId
            ("{0}{2}{1}"-f 'co','nd','mma') = $command
            ("{1}{0}"-f 'ult','res') = $result
        } | ConvertTo-Json -Compress
        Add-Content -Path $transcript -Value $record
        Write-Output "[safe] GET $taskUrl"
        Write-Output "[safe] Received task: $command"
        Write-Output "[safe] POST $uploadUrl"
        Write-Output "[safe] Result: $result"
    }
    Write-Output "[safe] Simulated HTTP C2 session finished."
}
Invoke-PoshRatHttp
