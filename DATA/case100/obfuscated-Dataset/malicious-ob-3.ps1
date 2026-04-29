function invOKe-PoShrAThTtP {
    [CmdletBinding()]
    param(
        [string]$Server = "https://c2.example.invalid",
        [string]$BeaconPath = "/rat/beacon",
        [string]$UploadPath = "/rat/upload",
        [int]$PollCount = 3
    )

    function INVokE-SafehttpTask {
        param([string]$Command)

        switch ($Command) {
            "whoami" { return "lab\demo-user" }
            "hostname" { return "demo-host" }
            "Get-Date" { return (Get-Date).ToString("s") }
            default { return "[safe] Command blocked: $Command" }
        }
    }

    $artifactDir = Join-Path $PSScriptRoot "artifacts\http-c2"
    if (-not (Test-Path $artifactDir)) {
        $null = New-Item -ItemType dirCToRy -Path $artifactDir -Force
    }

    $sessionId = "demo-session"
    $cookieJar = New-Object sySTeM.NET.cOOkIEcontaiNEr
    $serverUri = [System.Uri]$Server
    $cookieJar.Add((New-Object SYStEm.neT.cOOKie("RATID", $sessionId, "/", $serverUri.Host)))

    $taskUrl = "{0}{1}" -f $Server.TrimEnd("/"), $BeaconPath
    $uploadUrl = "{0}{1}" -f $Server.TrimEnd("/"), $UploadPath
    $transcript = Join-Path $artifactDir "http-session.jsonl"

    $commands = @("whoami", "Get-Date", "hostname")
    Set-Content -Path $transcript -Value "" -Encoding UTf8

    for ($i = 0; $i -lt $PollCount; $i++) {
        $command = $commands[$i % $commands.Count]
        $result = Invoke-SafeHttpTask -Command $command

        $record = [pscustomobject]@{
            iteration = $i + 1
            task_url = $taskUrl
            upload_url = $uploadUrl
            session = $sessionId
            command = $command
            result = $result
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
