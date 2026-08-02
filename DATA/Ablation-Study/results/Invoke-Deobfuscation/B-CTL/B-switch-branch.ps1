$choice = 'prod'

Switch ('prod') {
    'prod' {
        $prefix = 'https://'
        $domain = 'example.org'
    }
    default {
        $prefix = 'http://'
        $domain = 'invalid.local'
    }
}

$path = '/api/v1/update.bin'
$url = 'http://invalid.local/api/v1/update.bin'
'http://invalid.local/api/v1/update.bin'