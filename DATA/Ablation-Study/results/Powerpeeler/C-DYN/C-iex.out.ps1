$outer = ([string]@"
`$code = `"Write-Output ('https://' + 'example.org' + '/api/v1/update.bin')`"
iex `$code
"@)
$code = ([string]"Write-Output ('https://' + 'example.org' + '/api/v1/update.bin')")
Write-Output ([string]'https://example.org/api/v1/update.bin')