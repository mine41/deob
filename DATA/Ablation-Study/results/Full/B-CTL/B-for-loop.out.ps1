$parts = @('https://', 'example', '.org', '/api', '/v1', '/update', '.bin')
$url = ''

for ($i = 0; $i -lt ([int]7); $i++) {
    $url = $url + $parts[$i]
}

Write-Output ([string]'https://example.org/api/v1/update.bin')

