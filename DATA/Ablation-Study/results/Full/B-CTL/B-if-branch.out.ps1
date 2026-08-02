function Select-Scheme {
    param([bool]$UseSecure)

    if ($UseSecure) {
        return ([string]'https://')
    }

    return 'http://'
}

$scheme = ([string]'https://')
$domain = 'example.org'
$path = '/api/v1/update.bin'
$url = ([string]'https://example.org/api/v1/update.bin')
Write-Output ([string]'https://example.org/api/v1/update.bin')
