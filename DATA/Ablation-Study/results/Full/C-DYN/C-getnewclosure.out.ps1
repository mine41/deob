$outer = ([string]@'
$code = "Write-Output ('https://' + 'example.org' + '/api/v1/update.bin')"
$runner = [ScriptBlock]::Create($code).GetNewClosure()
& $runner
'@)

$outrunner = ([scriptblock] {
$code = "Write-Output ('https://' + 'example.org' + '/api/v1/update.bin')"
$runner = [ScriptBlock]::Create($code).GetNewClosure()
& {Write-Output ([string]'https://example.org/api/v1/update.bin')}
}).GetNewClosure()
& {$code = "Write-Output ('https://' + 'example.org' + '/api/v1/update.bin')"
$runner = [ScriptBlock]::Create($code).GetNewClosure()
& {Write-Output ([string]'https://example.org/api/v1/update.bin')}}
