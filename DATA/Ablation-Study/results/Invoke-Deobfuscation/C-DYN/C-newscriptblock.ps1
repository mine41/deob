$outer = '$code = "Write-Output (''https://'' + ''example.org'' + ''/api/v1/update.bin'')"
$runner = $ExecutionContext.InvokeCommand.NewScriptBlock($code)
& $runner'

$outrunner = $code = "Write-Output ('https://' + 'example.org' + '/api/v1/update.bin')"
$runner = $ExecutionContext.InvokeCommand.NewScriptBlock($code )
& $runner 
& $outrunner