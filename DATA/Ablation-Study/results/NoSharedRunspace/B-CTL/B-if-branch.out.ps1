function Select-Scheme {
    param([bool]$UseSecure)

    if ($UseSecure) {
        return 'https://'
    }

    return ([string]'http://')
}

$scheme = (& {
    param([bool]$UseSecure)

    if ($UseSecure) {
        return 'https://'
    }

    return ([string]'http://')
} $true)
$domain = 'example.org'
$path = '/api/v1/update.bin'
$url = $scheme + $domain + $path
Write-Output ([string]'example.org/api/v1/update.bin')
