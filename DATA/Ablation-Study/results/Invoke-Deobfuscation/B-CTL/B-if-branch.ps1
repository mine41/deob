Function Select-Scheme {
    Param([bool]$UseSecure )

    If ($UseSecure ) {
        Return 'https://'
    }

    Return 'http://'
}

$scheme = select-scheme $True 
$domain = 'example.org'
$path = '/api/v1/update.bin'
$url = $scheme + 'example.org' + '/api/v1/update.bin'
Write-Output $url