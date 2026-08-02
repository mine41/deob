function Get-Url {
    param(
        [string]$Prefix,
        [string]$HostPart,
        [string]$PathPart
    )

    if ($Prefix) {
        for ($i = 0; $i -lt 1; $i++) {
            return $Prefix + $HostPart + $PathPart
        }
    }

    return $null
}

$url = ([string]'https://example.org/api/v1/update.bin')
Write-Output ([string]'https://example.org/api/v1/update.bin')

