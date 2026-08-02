$choice = 'prod'

switch ($choice) {
    'prod' {
        $prefix = 'https://'
        $domain = 'example.org'
    }
    default {
        $prefix = 'http://'
        $domain = 'invalid.local'
    }
}

$path = '/api/v1' + '/update.bin'
$url = $prefix + $domain + $path
Write-Output $url

