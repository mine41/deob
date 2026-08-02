function Select-Scheme {
    param([bool]$UseSecure)

    if ($UseSecure) {
        return ([string]'https://')
    }

    return 'http://'
}

$scheme = (& {
    param([bool]$UseSecure)

    if (([bool]$True)) {
        return ([string]'https://')
    }

    return 'http://'
} $true)
$domain = 'example.org'
$path = '/api/v1/update.bin'
$url = ([string]'https://') + ([string]'example.org') + ([string]'/api/v1/update.bin')
Write-Output ([string]'https://example.org/api/v1/update.bin')
