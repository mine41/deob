function Select-Scheme {
    param([bool]$UseSecure)

    if ($UseSecure) {
        return 'https://'
    }

    return 'http://'
}

$scheme = Select-Scheme $true
$domain = 'example.org'
$path = '/api/v1/update.bin'
$url = $scheme + $domain + $path
Write-Output $url
