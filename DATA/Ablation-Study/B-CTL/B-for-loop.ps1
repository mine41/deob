$parts = @('https://', 'example', '.org', '/api', '/v1', '/update', '.bin')
$url = ''

for ($i = 0; $i -lt $parts.Count; $i++) {
    $url = $url + $parts[$i]
}

Write-Output $url

