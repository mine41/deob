$outer = @'
$code = "Write-Output ('https://' + 'example.org' + '/api/v1/update.bin')"
$runner = [ScriptBlock]::Create($code)
. $runner
'@

$outrunner = [ScriptBlock]::Create($outer)
. $outrunner
