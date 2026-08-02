function Select-Scheme {
    param([bool]$UseSecure)
    if ($UseSecure) {
        return 'https://'
    }
    return 'http://'
}
$scheme = Select-Scheme $true <#
function Select-Scheme {
    param([bool]$UseSecure)

    if ($UseSecure) {
        return ([string]"https://")
    }

    return ([string]"http://")
}
result:
[string]"https://"
#>
$domain = ([string]"example.org")
$path = ([string]"/api/v1/update.bin")
$url = ([string]"https://example.org/api/v1/update.bin")
Write-Output ([string]"https://example.org/api/v1/update.bin")
