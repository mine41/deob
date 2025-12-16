. .\Generate-CFG.ps1
$cfg = Get-ScriptControlFlow -ScriptPath 'in/in.ps1'
$cfg.Nodes | Select-Object Id,Type,Text,Line | Format-Table -AutoSize
$cfg.Edges | Format-Table -AutoSize

$dotPath = Join-Path $PSScriptRoot 'in/in.dot'
Export-CfgToDot -finalCFG $cfg -outputPath $dotPath
