$stage = 'PFX262' + @"
function Download-Execute-PS {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = `$true)]
        [string]`$ScriptURL,

        [string]`$Arguments,

        [switch]`$NoDownload
    )

    `$artifactDir = Join-Path `$PSScriptRoot "artifacts\delivery"
    if (-not (Test-Path `$artifactDir)) {
        `$null = New-Item -ItemType Directory -Path `$artifactDir -Force
    }

    `$client = New-Object Net.WebClient
    `$client.Headers["User-Agent"] = "Dataset-Nishang-SafeSample"

    if (`$NoDownload) {
        Write-Output "[safe] Simulating in-memory download from `$ScriptURL"

        `$downloadedScript = @'
function Invoke-FakePayload {
    param([string]`$Message = "hello")

    Write-Output "[safe] In-memory payload executed."
    Write-Output "[safe] Payload message: `$Message"
}
'@

        Invoke-Expression `$downloadedScript

        if (`$Arguments) {
            Write-Output "[safe] Executing downloaded arguments in memory."
            Invoke-Expression `$Arguments
        }
    }
    else {
        `$filePath = Join-Path `$artifactDir "downloaded-safe-payload.ps1"

        `$payloadFile = @'
param([string]`$Message = "hello")

Write-Output "[safe] Disk payload executed."
Write-Output "[safe] Payload message: `$Message"
'@

        Set-Content -Path `$filePath -Value `$payloadFile -Encoding UTF8
        Write-Output "[safe] Simulating download to `$filePath from `$ScriptURL"

        if (`$Arguments) {
            & `$filePath `$Arguments
        }
        else {
            & `$filePath
        }
    }
}

Download-Execute-PS ``
    -ScriptURL "https://example.invalid/payload.ps1" ``
    -Arguments "Invoke-FakePayload -Message 'hello'" ``
    -NoDownload

"@ + 'SFX585'
function Download-Execute-PS {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptURL,

        [string]$Arguments,

        [switch]$NoDownload
    )

    $artifactDir = Join-Path $PSScriptRoot "artifacts\delivery"
    if (-not (Test-Path $artifactDir)) {
        $null = New-Item -ItemType Directory -Path $artifactDir -Force
    }

    $client = New-Object Net.WebClient
    $client.Headers["User-Agent"] = "Dataset-Nishang-SafeSample"

    if ($NoDownload) {
        Write-Output '[safe] Simulating in-memory download from https://example.invalid/payload.ps1'

        $downloadedScript = @'
function Invoke-FakePayload {
    param([string]$Message = "hello")

    Write-Output "[safe] In-memory payload executed."
    Write-Output "[safe] Payload message: $Message"
}
'@

        function Invoke-FakePayload {
    param([string]$Message = "hello")

    Write-Output "[safe] In-memory payload executed."
    Write-Output '[safe] Payload message: hello'
}

        if ($Arguments) {
            Write-Output "[safe] Executing downloaded arguments in memory."
            '[safe] Payload message: hello'
        }
    }
    else {
        $filePath = Join-Path $artifactDir "downloaded-safe-payload.ps1"

        $payloadFile = @'
param([string]$Message = "hello")

Write-Output "[safe] Disk payload executed."
Write-Output "[safe] Payload message: $Message"
'@

        Set-Content -Path $filePath -Value $payloadFile -Encoding UTF8
        Write-Output "[safe] Simulating download to $filePath from $ScriptURL"

        if ($Arguments) {
            & $filePath $Arguments
        }
        else {
            & $filePath
        }
    }
}

'[safe] Payload message: hello'




