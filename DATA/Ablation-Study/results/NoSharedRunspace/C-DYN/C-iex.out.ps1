$outer = @'
$code = "Write-Output ('https://' + 'example.org' + '/api/v1/update.bin')"
iex $code
'@

Invoke-Expression @'
$code = "Write-Output ('https://' + 'example.org' + '/api/v1/update.bin')"
iex $code
'@