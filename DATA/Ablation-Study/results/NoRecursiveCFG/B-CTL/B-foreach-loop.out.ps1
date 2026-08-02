$parts = @('https://', 'example.org', '/api/v1', '/update.bin')
$url = ''

foreach ($part in $parts) {
    $url = $url + $part
}

Write-Output ([string]'https://example.org/api/v1/update.bin')

