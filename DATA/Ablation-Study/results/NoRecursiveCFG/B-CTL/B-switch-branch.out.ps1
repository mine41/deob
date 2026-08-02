$choice = 'prod'

switch (([string]'prod')) {
    'prod' {
        $prefix = 'https://'
        $domain = 'example.org'
    }
    default {
        $prefix = 'http://'
        $domain = 'invalid.local'
    }
}

$path = ([string]'/api/v1/update.bin')
$url = ([string]'https://') + ([string]'example.org') + ([string]'/api/v1/update.bin')
Write-Output ([string]'https://example.org/api/v1/update.bin')

