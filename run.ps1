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

# 显示可还原表达式和变量读取值（按节点分组）
Write-Host "`n=== Execution Results (by Node) ===" -ForegroundColor Cyan

# 收集所有有结果的节点 ID
$nodeIds = @()
$result.ResolvableResults.Values | ForEach-Object { $nodeIds += $_.NodeId }
$result.VariableReadResults.Values | ForEach-Object { $nodeIds += $_.NodeId }
$nodeIds = @($nodeIds | Sort-Object -Unique)

if ($nodeIds.Count -eq 0) {
    Write-Host "  (No values recorded)" -ForegroundColor Gray
} else {
    foreach ($nodeId in $nodeIds) {
        # 获取节点信息
        $node = $cfg.Nodes | Where-Object { $_.Id -eq $nodeId }
        if (-not $node) { continue }

        Write-Host "`nNode $nodeId ($($node.Type)):" -ForegroundColor Yellow
        Write-Host "  Code: $($node.Text)" -ForegroundColor White

        # 收集该节点的 Resolvables
        $nodeResolvables = @($result.ResolvableResults.Values | Where-Object { $_.NodeId -eq $nodeId })
        # 收集该节点的 VariableReads
        $nodeVarReads = @($result.VariableReadResults.Values | Where-Object { $_.NodeId -eq $nodeId })

        # 按 StartOffset 排序合并展示
        $allItems = @()

        foreach ($record in $nodeResolvables) {
            $r = $record.Resolvable
            $uniqueValues = @($record.Values | Select-Object -Unique)
            $consistent = $uniqueValues.Count -le 1
            $allItems += [PSCustomObject]@{
                Type        = "Resolvable"
                StartOffset = $r.StartOffset
                EndOffset   = $r.EndOffset
                Text        = $r.Text
                SubType     = $r.Type
                Depth       = $r.Depth
                Values      = $record.Values
                Consistent  = $consistent
                UniqueVals  = $uniqueValues
            }
        }

        foreach ($record in $nodeVarReads) {
            $v = $record.VarInfo
            $uniqueValues = @($record.Values | Select-Object -Unique)
            $consistent = $uniqueValues.Count -le 1
            $allItems += [PSCustomObject]@{
                Type        = if ($v.IsInlineResult) { "Inline" } else { "VarRead" }
                StartOffset = $v.StartOffset
                EndOffset   = $v.EndOffset
                Text        = $v.Text
                SubType     = $null
                Depth       = $null
                Values      = $record.Values
                Consistent  = $consistent
                UniqueVals  = $uniqueValues
            }
        }

        # 按 StartOffset 排序
        $allItems = $allItems | Sort-Object StartOffset

        foreach ($item in $allItems) {
            $offsetInfo = "[$($item.StartOffset)-$($item.EndOffset)]"
            $typeTag = switch ($item.Type) {
                "Resolvable" { "[$($item.SubType)]" }
                "Inline"     { "[Inline]" }
                "VarRead"    { "[Var]" }
            }
            $depthInfo = if ($null -ne $item.Depth) { " [D:$($item.Depth)]" } else { "" }

            Write-Host "    $offsetInfo $typeTag$depthInfo" -ForegroundColor Gray -NoNewline
            Write-Host " $($item.Text)" -ForegroundColor White

            if ($item.Values.Count -eq 0) {
                Write-Host "      => (No values)" -ForegroundColor Gray
            } elseif ($item.Consistent) {
                $suffix = if ($item.Values.Count -gt 1) { " (x$($item.Values.Count))" } else { "" }
                Write-Host "      => $($item.UniqueVals[0])$suffix" -ForegroundColor Green
            } else {
                Write-Host "      => INCONSISTENT: " -ForegroundColor Red -NoNewline
                Write-Host ($item.Values -join ', ') -ForegroundColor Yellow
            }
        }
    }
}
