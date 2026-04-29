Function invOKe-PoShrAThTtP {
    [CmdletBinding()]
    Param(
        [String]$Server = "https://c2.example.invalid" , 
        [String]$BeaconPath = "/rat/beacon" , 
        [String]$UploadPath = "/rat/upload" , 
        [int]$PollCount = 3
    )

    Function INVokE-SafehttpTask {
        Param([String]$Command )

        Switch ($Command ) {
            "whoami" {
                Return "lab\demo-user" }
            "hostname" {
                Return "demo-host" }
            "Get-Date" {
                Return (Get-Date ).ToString("s") }
            default {
                Return "[safe] Command blocked: $Command" }
        }
    }

    $artifactDir = Join-Path $PSScriptRoot "artifacts\http-c2"
    If ( -Not (Test-Path $artifactDir )) {
        $Null = New-Item -ItemType dirCToRy -Path $artifactDir -Force
    }

    $sessionId = "demo-session"
    $cookieJar = New-Object sySTeM.NET.cOOkIEcontaiNEr
    $serverUri = [System.Uri]$Server 
    $cookieJar.Add((New-Object SYStEm.neT.cOOKie("RATID" , $sessionId , "/" , $serverUri.host)))

    $taskUrl = "{0}{1}" -f $Server.trimend("/") , $BeaconPath 
    $uploadUrl = "{0}{1}" -f $Server.trimend("/") , $UploadPath 
    $transcript = Join-Path $artifactDir "http-session.jsonl"

    $commands = @("whoami" , "Get-Date" , "hostname")
    Set-Content -Path $transcript -Value "" -Encoding UTf8

    For ($i = 0; $i -lt $PollCount; $i ++ ) {
        $command = $commands[$i % $commands.count]
        $result = invoke-safehttptask -Command $command 

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

invoke-poshrathttp 
