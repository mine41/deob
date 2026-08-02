$outer = @'
$code = "Write-Output ('https://' + 'example.org' + '/api/v1/update.bin')"
Write-Output ('https://' + 'example.org' + '/api/v1/update.bin')
'@

$code = "Write-Output ('https://' + 'example.org' + '/api/v1/update.bin')"
Write-Output ([string]'https://example.org/api/v1/update.bin')