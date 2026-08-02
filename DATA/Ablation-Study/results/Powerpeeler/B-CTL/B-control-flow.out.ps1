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
$url = Get-Url ([string]"https://") ([string]"example.org") ([string]"/api/v1/update.bin") <#
function Get-Url {
    param(
        [string]$Prefix,
        [string]$HostPart,
        [string]$PathPart
    )

    if ($Prefix) {
        for ($i = ([int]0); $i -lt ([int]1); $i++) {
            return ([string]"https://example.org/api/v1/update.bin")
        }
    }

    return $null
}
result:
[string]"https://example.org/api/v1/update.bin"
#>
Write-Output ([string]"https://example.org/api/v1/update.bin")
