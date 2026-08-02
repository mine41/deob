$outer = @'
$code = "Write-Output ('https://' + 'example.org' + '/api/v1/update.bin')"
Write-Output ('https://' + 'example.org' + '/api/v1/update.bin')
'@

$code = "Write-Output ('https://' + 'example.org' + '/api/v1/update.bin')"
Invoke-Expression 'Write-Output (''https://'' + ''example.org'' + ''/api/v1/update.bin'')'