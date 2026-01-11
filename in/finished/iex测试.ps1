# 一、iex
# Invoke-Expression 'Write-Host "Hello"'
# iex 'Write-Host "Hello"'
# IEX 'Write-Host "Hello"'
# $t = 'Write-Host "Hello"'
# iex $t

# 二、[ScriptBlock]::Create
# $b = "Write-Host 'Hello'"
# $delegate = [ScriptBlock]::Create($b)
# $delegate.Invoke()

# $scriptBlock = [System.Management.Automation.ScriptBlock]::Create('write-host "Hello"')
# $scriptBlock.Invoke()

# $x = $ExecutionContext.InvokeCommand.NewScriptBlock(‘Write-Host "Hello"’)
# & $x