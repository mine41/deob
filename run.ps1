. .\Generate-CFG.ps1
$cfg = Get-ScriptControlFlow -ScriptPath 'in/in.ps1'
$cfg.Nodes | Select-Object Type, Text, VarsRead, VarsWritten | Format-Table -AutoSize -Wrap
$cfg.Nodes | Out-GridView -Title 'CFG Nodes'
$cfg.Edges | Format-Table -AutoSize

$dotPath = Join-Path $PSScriptRoot 'in/in.dot'
Export-CfgToDot -finalCFG $cfg -outputPath $dotPath

Start-Process 'in/in.png'

$cfg.DefinedFunctions