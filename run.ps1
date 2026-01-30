. .\Generate-CFG.ps1
$cfg = Get-ScriptControlFlow -ScriptPath 'in/in.ps1'
$cfg.Nodes | Select-Object Id, Type, Text | Format-Table -AutoSize -Wrap
# $cfg.Nodes | Out-GridView -Title 'CFG Nodes'
$cfg.Edges | Format-Table -AutoSize

$dotPath = Join-Path $PSScriptRoot 'in/in.dot'
Export-CfgToDot -finalCFG $cfg -outputPath $dotPath

Start-Process 'in/in.png'

$cfg.DefinedFunctions
$cfg.ProcessedScriptBlocks

# 显示已定义的别名
Write-Host "`n=== Defined Aliases ===" -ForegroundColor Magenta
$cfg.DefinedAliases.GetEnumerator() | ForEach-Object {
    Write-Host "  $($_.Key) -> $($_.Value)" -ForegroundColor Magenta
}

# 显示每个节点的 Resolvables 内容
Write-Host "`n=== Resolvables ===" -ForegroundColor Cyan
$cfg.Nodes | ForEach-Object {
    if ($_.Resolvables.Count -gt 0) {
        Write-Host "Node $($_.Id) ($($_.Type)):" -ForegroundColor Yellow
        Write-Host "  Text: $($_.Text)"
        $_.Resolvables | ForEach-Object {
            Write-Host "  - [$($_.Type)] $($_.Text) -[$($_.Depth)]" -ForegroundColor Green
        }
    }
}

# 显示每个节点的 AliasesUsed 内容
Write-Host "`n=== Aliases Used ===" -ForegroundColor Magenta
$cfg.Nodes | ForEach-Object {
    if ($_.AliasesUsed.Count -gt 0) {
        Write-Host "Node $($_.Id) ($($_.Type)):" -ForegroundColor Yellow
        Write-Host "  Text: $($_.Text)"
        $_.AliasesUsed | ForEach-Object {
            Write-Host "  - $($_.Name) -> $($_.Target)" -ForegroundColor Magenta
        }
    }
}

# CFG 遍历执行
. .\Execute-CFG.ps1
Write-Host "`n=== CFG Traversal ===" -ForegroundColor Yellow
$logPath = Join-Path $PSScriptRoot 'in/execution.log'
$result = Invoke-CFGTraversal -CFG $cfg -LogPath $logPath
Write-Host "Total visits: $($result.TotalVisits)" -ForegroundColor Green
Write-Host "Unique nodes: $($result.VisitedNodes.Count)" -ForegroundColor Green
Write-Host "Log file: $logPath" -ForegroundColor Green