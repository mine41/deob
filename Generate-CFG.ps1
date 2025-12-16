function Get-Ast {
    param (
        [object] $InputObject
    )

    $ast = switch ($InputObject) {
        {$_ -is [string]} {
            if (Test-Path -LiteralPath $_) {
                $path = Resolve-Path -Path $_
                [System.Management.Automation.Language.Parser]::ParseFile($path.ProviderPath, [ref]$null, [ref]$null)
            }
            else {
                [System.Management.Automation.Language.Parser]::ParseInput($_, [ref]$null, [ref]$null)
            }
            break
        }
        {$_ -is [System.Management.Automation.FunctionInfo] -or
            $_ -is [System.Management.Automation.ExternalScriptInfo]} {
            $InputObject.ScriptBlock.Ast
            break
        }
        {$_ -is [scriptblock]} {
            $_.Ast
            break
        }
        Default {
            throw 'InputObject type not recognised'
        }
    }

    # $ast.FindAll({ $true }, $true)
    return $ast
}

# 辅助函数：添加节点
function Add-Node {
    param(
        $cfg,
        $type,
        $text,
        $line,
        $ast = $null
    )
    $node = [PSCustomObject]@{
        Id    = $cfg.Nodes.Count + 1
        Type  = $type
        Text  = $text
        Line  = $line
        Ast   = $ast
    }
    $cfg.Nodes += $node
    return $node
}

# 辅助函数：添加边
function Add-Edge {
    param($cfg, $from, $to, $label = $null)
    $edge = [PSCustomObject]@{
        From  = $from
        To    = $to
        Label = $label
    }
    $cfg.Edges += $edge
}

#处理IfstatementAst
function Convert-IfAstNode {
    param(
        [hashtable]$cfg,
        [System.Management.Automation.Language.IfStatementAst]$ifAst,
        [ref]$prevNodeRef,
        $endNodeRef = $null,
        $loopContext = $null
    )
    if ($null -eq $ifAst -or $null -eq $prevNodeRef) {
        Write-Warning "Invalid input: ifAst or prevNodeRef is null"
        return
    }

    # 1. 添加条件节点（Clause[i].Item1）
    $ifNode = Add-Node -cfg $cfg -type "If Condition" -text "If Condition" -line $ifAst.Extent.StartLineNumber -ast $ifAst
    Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $ifNode.Id
    $prevNodeRef.Value = $ifNode

    # 2. 初始化分支结束节点集合
    $branchEndNodes = @()

    # 3. 处理所有 Clause（if/elseif 分支）
    foreach ($clause in $ifAst.Clauses) {
        # 3.1 添加条件子节点
        $condNode = Add-Node -cfg $cfg -type "Condition" -text $clause.Item1.Extent.Text -line $clause.Item1.Extent.StartLineNumber -ast $clause.Item1
        Add-Edge -cfg $cfg -from $ifNode.Id -to $condNode.Id -label "Condition"
        $prevNodeRef.Value = $condNode

        # 3.2 处理分支代码块（Clause[i].Item2）
        $branchHasReturn = $false
        foreach ($statement in $clause.Item2.Statements) {
            $hasReturn = Convert-AstNode -cfg $cfg -node $statement -prevNodeRef $prevNodeRef -endNodeRef $endNodeRef -loopContext $loopContext -switchContext $null
            # 如果遇到 return，停止处理后续语句
            if ($hasReturn) {
                $branchHasReturn = $true
                break
            }
        }
        # 只有当分支不以 return、break 或 continue 结束时，才添加到分支结束节点集合
        # break/continue 已经跳出了 if 语句的上下文，不应该连接到 merge 节点
        if (-not $branchHasReturn -and $null -ne $prevNodeRef.Value) {
            $lastNodeType = $prevNodeRef.Value.Type
            if ($lastNodeType -ne "Break" -and $lastNodeType -ne "Continue") {
                $branchEndNodes += $prevNodeRef.Value
            }
        }
    }

    # 4. 处理 ElseClause（如果存在显式 else）
    if ($null -ne $ifAst.ElseClause) {
        $elseNode = Add-Node -cfg $cfg -type "Else" -text "Else" -line $ifAst.ElseClause.Extent.StartLineNumber
        Add-Edge -cfg $cfg -from $ifNode.Id -to $elseNode.Id -label "Else"
        $prevNodeRef.Value = $elseNode

        # 处理 Else 代码块
        $elseHasReturn = $false
        foreach ($statement in $ifAst.ElseClause.Statements) {
            $hasReturn = Convert-AstNode -cfg $cfg -node $statement -prevNodeRef $prevNodeRef -endNodeRef $endNodeRef -loopContext $loopContext -switchContext $null
            # 如果遇到 return，停止处理后续语句
            if ($hasReturn) {
                $elseHasReturn = $true
                break
            }
        }
        # 只有当 Else 分支不以 return、break 或 continue 结束时，才添加到分支结束节点集合
        # break/continue 已经跳出了 if 语句的上下文，不应该连接到 merge 节点
        if (-not $elseHasReturn -and $null -ne $prevNodeRef.Value) {
            $lastNodeType = $prevNodeRef.Value.Type
            if ($lastNodeType -ne "Break" -and $lastNodeType -ne "Continue") {
                $branchEndNodes += $prevNodeRef.Value
            }
        }
    }
    else {
        # 如果没有显式 else，创建一个隐式 else 节点，表示"所有条件都不满足时继续执行"
        # 这个节点直接连接到 if 节点，表示后续代码会继续执行
        $implicitElseNode = Add-Node -cfg $cfg -type "Else" -text "Implicit Else" -line $ifAst.Extent.EndLineNumber -ast $ifAst
        Add-Edge -cfg $cfg -from $ifNode.Id -to $implicitElseNode.Id -label "Else"
        # 隐式 else 分支总是会继续执行后续代码，所以添加到分支结束节点集合
        $branchEndNodes += $implicitElseNode
        # 更新 prevNodeRef 为隐式 else 节点，这样后续代码会从这个节点继续
        $prevNodeRef.Value = $implicitElseNode
    }

    # 5. 如果所有分支都以 return/break/continue/exit 结束（branchEndNodes 为空）
    if ($branchEndNodes.Count -eq 0) {
        # 检查最后一个节点的类型，区分 return/exit 和 break/continue
        if ($null -ne $prevNodeRef.Value) {
            $lastNodeType = $prevNodeRef.Value.Type
            # 如果所有分支都以 return/exit 结束，连接到 End 节点
            if ($lastNodeType -in @("Return", "Exit") -and $null -ne $endNodeRef) {
                $endNode = if ($endNodeRef -is [ref]) { $endNodeRef.Value } else { $endNodeRef }
                if ($null -ne $endNode) {
                    # 所有 return 已经直接连接到 End，不需要 merge 节点
                    # 将 prevNodeRef 指向 End，这样后续语句不会被处理
                    $prevNodeRef.Value = $endNode
                    return $true  # 返回 true 表示所有分支都有 return
                }
            }
            # 如果所有分支都以 break/continue 结束，不应该将 prevNodeRef 设置为 End
            # 保持 prevNodeRef 不变（指向 break/continue 节点），返回 true 以停止处理后续语句
            return $true
        }
    }

    # 6. 创建虚拟汇聚节点（If-End）
    $mergeNode = Add-Node -cfg $cfg -type "Merge" -text "If-End" -line $ifAst.Extent.EndLineNumber -ast $ifAst

    # 7. 将所有分支结束节点连接到汇聚节点
    foreach ($endNode in $branchEndNodes) {
        Add-Edge -cfg $cfg -from $endNode.Id -to $mergeNode.Id
    }

    # 8. 更新 prevNodeRef 为汇聚节点，供后续连接
    $prevNodeRef.Value = $mergeNode
    return $false  # 返回 false 表示不是所有分支都有 return
}

function Convert-SwitchAstNode {
    param(
        [hashtable]$cfg,
        [System.Management.Automation.Language.SwitchStatementAst]$switchAst,
        [ref]$prevNodeRef,
        $endNodeRef = $null,
        $loopContext = $null,
        $switchContext = $null
    )
    if ($null -eq $switchAst -or $null -eq $prevNodeRef) {
        Write-Warning "Invalid input: switchAst or prevNodeRef is null"
        return
    }

    # 1. 添加 Switch 条件节点（评估条件表达式，可能是数组）
    # 1.1 获取 switch 的 flags（-Wildcard, -Regex, -CaseSensitive, -Exact, -File, -Parallel）
    $switchFlags = @()
    if ($switchAst.Flags -band [System.Management.Automation.Language.SwitchFlags]::Wildcard) { $switchFlags += "-Wildcard" }
    if ($switchAst.Flags -band [System.Management.Automation.Language.SwitchFlags]::Regex) { $switchFlags += "-Regex" }
    if ($switchAst.Flags -band [System.Management.Automation.Language.SwitchFlags]::CaseSensitive) { $switchFlags += "-CaseSensitive" }
    if ($switchAst.Flags -band [System.Management.Automation.Language.SwitchFlags]::Exact) { $switchFlags += "-Exact" }
    if ($switchAst.Flags -band [System.Management.Automation.Language.SwitchFlags]::File) { $switchFlags += "-File" }
    if ($switchAst.Flags -band [System.Management.Automation.Language.SwitchFlags]::Parallel) { $switchFlags += "-Parallel" }
    $flagsText = if ($switchFlags.Count -gt 0) { " " + ($switchFlags -join " ") } else { "" }

    $switchConditionText = if ($null -ne $switchAst.Condition) { $switchAst.Condition.Extent.Text } else { "Switch Condition" }
    $switchNode = Add-Node -cfg $cfg -type "Switch Condition" -text "Switch$flagsText ($switchConditionText)" -line $switchAst.Extent.StartLineNumber -ast $switchAst
    Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $switchNode.Id

    # 2. 添加 Iterator 节点（遍历检查，类似 foreach 的 Has next?）
    $iteratorNode = Add-Node -cfg $cfg -type "Switch Iterator" -text "Has next item in ($switchConditionText)?" -line $switchAst.Extent.StartLineNumber -ast $switchAst
    Add-Edge -cfg $cfg -from $switchNode.Id -to $iteratorNode.Id

    # 3. 提前创建 Switch 的 merge 节点（供 break 和循环退出使用）
    $switchMergeNode = Add-Node -cfg $cfg -type "Merge" -text "Switch-End" -line $switchAst.Extent.EndLineNumber -ast $switchAst

    # 4. 连接 Iterator 的"无更多项"分支到 Switch-End
    Add-Edge -cfg $cfg -from $iteratorNode.Id -to $switchMergeNode.Id -label "No more items"

    # 5. 创建 Switch 上下文（供 break 和 continue 使用）
    # break: 跳出整个 switch，连接到 switchMergeNode
    # continue: 跳过当前元素，继续下一个元素，连接到 iteratorNode
    $currentSwitchContext = [PSCustomObject]@{
        SwitchMerge = $switchMergeNode
        SwitchNode = $iteratorNode  # continue 跳转到 Iterator 节点，继续下一个元素
    }

    # 6. 收集所有需要回到 Iterator 的节点（没有以 break/return/exit 结束的分支）
    $backToIteratorNodes = @()

    # 7. 处理所有 Clause（case 分支）
    foreach ($clause in $switchAst.Clauses) {
        # 7.1 添加 case 条件节点
        $caseLabelText = if ($null -ne $clause.Item1) { $clause.Item1.Extent.Text } else { "Case" }
        $caseLineNumber = if ($null -ne $clause.Item1) { $clause.Item1.Extent.StartLineNumber } else { $switchAst.Extent.StartLineNumber }
        $caseNode = Add-Node -cfg $cfg -type "Case" -text "Case $caseLabelText" -line $caseLineNumber -ast $clause.Item1
        # Iterator 连接到每个 Case（每个元素都会尝试匹配所有 case）
        Add-Edge -cfg $cfg -from $iteratorNode.Id -to $caseNode.Id -label "Match?"
        $prevNodeRef.Value = $caseNode

        # 7.2 处理分支代码块（Clause[i].Item2）
        $branchHasTerminator = $false
        foreach ($statement in $clause.Item2.Statements) {
            $hasTerminator = Convert-AstNode -cfg $cfg -node $statement -prevNodeRef $prevNodeRef -endNodeRef $endNodeRef -loopContext $loopContext -switchContext $currentSwitchContext
            # 如果遇到 return/break/continue/exit，停止处理后续语句
            if ($hasTerminator) {
                $branchHasTerminator = $true
                break
            }
        }
        # 如果分支没有以 return/break/continue/exit 结束，需要回到 Iterator 继续下一个元素
        if (-not $branchHasTerminator -and $null -ne $prevNodeRef.Value) {
            $lastNodeType = $prevNodeRef.Value.Type
            if ($lastNodeType -ne "Break" -and $lastNodeType -ne "Continue" -and $lastNodeType -ne "Return" -and $lastNodeType -ne "Exit") {
                $backToIteratorNodes += $prevNodeRef.Value
            }
        }
    }

    # 8. 处理 DefaultClause（如果存在 default）
    if ($null -ne $switchAst.Default) {
        $defaultNode = Add-Node -cfg $cfg -type "Default" -text "Default" -line $switchAst.Default.Extent.StartLineNumber -ast $switchAst.Default
        Add-Edge -cfg $cfg -from $iteratorNode.Id -to $defaultNode.Id -label "Default"
        $prevNodeRef.Value = $defaultNode

        # 处理 Default 代码块
        $defaultHasTerminator = $false
        foreach ($statement in $switchAst.Default.Statements) {
            $hasTerminator = Convert-AstNode -cfg $cfg -node $statement -prevNodeRef $prevNodeRef -endNodeRef $endNodeRef -loopContext $loopContext -switchContext $currentSwitchContext
            # 如果遇到 return/break/continue/exit，停止处理后续语句
            if ($hasTerminator) {
                $defaultHasTerminator = $true
                break
            }
        }
        # 如果 Default 分支没有以 return/break/continue/exit 结束，需要回到 Iterator
        if (-not $defaultHasTerminator -and $null -ne $prevNodeRef.Value) {
            $lastNodeType = $prevNodeRef.Value.Type
            if ($lastNodeType -ne "Break" -and $lastNodeType -ne "Continue" -and $lastNodeType -ne "Return" -and $lastNodeType -ne "Exit") {
                $backToIteratorNodes += $prevNodeRef.Value
            }
        }
    }
    else {
        # 如果没有显式 default，创建一个隐式 default 节点
        # 隐式 default 表示"当前元素不匹配任何 case"，直接回到 Iterator 继续下一个元素
        $implicitDefaultNode = Add-Node -cfg $cfg -type "Default" -text "Implicit Default (no match)" -line $switchAst.Extent.EndLineNumber -ast $switchAst
        Add-Edge -cfg $cfg -from $iteratorNode.Id -to $implicitDefaultNode.Id -label "No match"
        $backToIteratorNodes += $implicitDefaultNode
    }

    # 9. 将所有需要继续迭代的节点连接回 Iterator（形成循环）
    foreach ($node in $backToIteratorNodes) {
        Add-Edge -cfg $cfg -from $node.Id -to $iteratorNode.Id -label "Next item"
    }

    # 10. 更新 prevNodeRef 为汇聚节点，供后续连接
    $prevNodeRef.Value = $switchMergeNode
    return $false  # switch 作为循环结构，总是可以正常退出（除非所有路径都 return/exit）
}

function Convert-FunctionDefinitionAst {
    param(
        [hashtable]$cfg,
        [System.Management.Automation.Language.FunctionDefinitionAst]$funcAst
    )
    if ($null -eq $funcAst) {
        return
    }

    # 为函数体创建独立的入口/出口节点（不从 Script Start 连入）
    # FuncStart 只显示函数名，参数单独作为一个节点紧跟其后
    $funcName = $funcAst.Name
    $funcStart = Add-Node -cfg $cfg -type "FuncStart" -text "function $funcName" -line $funcAst.Extent.StartLineNumber -ast $funcAst
    $funcEnd   = Add-Node -cfg $cfg -type "FuncEnd"   -text "End function $funcName"        -line $funcAst.Extent.EndLineNumber   -ast $funcAst

    # 在函数内部构建控制流：类似 ScriptBlockAst，但使用 FuncStart/FuncEnd
    # 如果存在 ParamBlock，则在 FuncStart 后面单独插入一个参数节点
    $prevNode = $funcStart
    if ($null -ne $funcAst.Body -and $null -ne $funcAst.Body.ParamBlock) {
        $paramBlock = $funcAst.Body.ParamBlock
        # 将 ParamBlock 文本压缩为单行，避免换行和多余空格导致显示难看
        $rawParamText    = $paramBlock.Extent.Text
        $singleLineParam = ($rawParamText -split "`r?`n") -join ' '
        $singleLineParam = ($singleLineParam -replace '\s+', ' ').Trim()

        $paramNode = Add-Node -cfg $cfg -type "FuncParams" -text $singleLineParam -line $paramBlock.Extent.StartLineNumber -ast $paramBlock
        Add-Edge -cfg $cfg -from $funcStart.Id -to $paramNode.Id
        $prevNode = $paramNode
    }

    $prev = [ref]$prevNode
    $endRef = [ref]$funcEnd

    if ($null -ne $funcAst.Body -and $null -ne $funcAst.Body.EndBlock) {
        # 目前只考虑函数体中的 EndBlock（最常见的普通函数写法）
        foreach ($statement in $funcAst.Body.EndBlock.Statements) {
            $hasTerminator = Convert-AstNode -cfg $cfg -node $statement -prevNodeRef $prev -endNodeRef $endRef -loopContext $null -switchContext $null
            if ($hasTerminator) {
                break
            }
        }
    }

    # 如果最后一个节点不是 FuncEnd，并且不是显式终止语句，则连接到 FuncEnd（隐式 return）
    # 注意：当函数体中出现 exit 且被 try/finally 包裹时，finally 的出口有可能已经被特殊处理为
    #       直接连到全局 Script End（Type="End"）。这种情况下不能再从 Script End 连一条边到
    #       FuncEnd，否则就会出现“FuncEnd 接在 Script End 后面”的错误。
    if ($null -ne $prev.Value -and $prev.Value.Id -ne $funcEnd.Id) {
        $lastType = $prev.Value.Type
        if ($lastType -notin @("Return", "Exit", "Throw", "Break", "Continue", "End")) {
            Add-Edge -cfg $cfg -from $prev.Value.Id -to $funcEnd.Id
        }
    }
}

function Convert-TryAstNode {
    param(
        [hashtable]$cfg,
        [System.Management.Automation.Language.TryStatementAst]$tryAst,
        [ref]$prevNodeRef,
        $endNodeRef = $null,
        $loopContext = $null,
        $switchContext = $null
    )
    if ($null -eq $tryAst -or $null -eq $prevNodeRef) {
        Write-Warning "Invalid input: tryAst or prevNodeRef is null"
        return $false
    }

    # 1. 创建 Try 入口节点
    $tryNode = Add-Node -cfg $cfg -type "Try" -text "Try" -line $tryAst.Extent.StartLineNumber -ast $tryAst
    Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $tryNode.Id
    $prevNodeRef.Value = $tryNode

    # 2. Try-End 汇聚节点（懒创建，只有真的需要汇聚时才创建，避免产生孤立的 Merge 节点）
    $tryEndNode = $null

    # 3. 提前创建 Finally 节点（如果存在）
    $finallyNode = $null
    if ($null -ne $tryAst.Finally) {
        $finallyNode = Add-Node -cfg $cfg -type "Finally" -text "Finally" -line $tryAst.Finally.Extent.StartLineNumber -ast $tryAst.Finally
    }

    # 4. 提前创建 Catch 链的第一个节点（用于异常跳转）
    $firstCatchNode = $null
    $catchNodes = @()

    foreach ($catchClause in $tryAst.CatchClauses) {
        # 获取 Catch 的异常类型
        $catchTypes = if ($catchClause.CatchTypes.Count -gt 0) {
            ($catchClause.CatchTypes | ForEach-Object { $_.TypeName.Name }) -join ", "
        } else {
            "All"  # 没有指定类型表示捕获所有异常
        }

        # 创建 Catch 节点
        $catchNode = Add-Node -cfg $cfg -type "Catch" -text "Catch [$catchTypes]" -line $catchClause.Extent.StartLineNumber -ast $catchClause
        $catchNodes += @{
            Node = $catchNode
            Clause = $catchClause
        }

        if ($null -eq $firstCatchNode) {
            $firstCatchNode = $catchNode
        }
    }

    # 5. 收集所有需要汇聚的分支结束节点
    $branchEndNodes = @()

    # 6. 记录处理前的节点数量（用于收集try块内生成的所有节点）
    $nodeCountBefore = $cfg.Nodes.Count

    # 7. 处理 Try 块
    $tryHasTerminator = $false
    foreach ($statement in $tryAst.Body.Statements) {
        $hasTerminator = Convert-AstNode -cfg $cfg -node $statement -prevNodeRef $prevNodeRef -endNodeRef $endNodeRef -loopContext $loopContext -switchContext $switchContext

        if ($hasTerminator) {
            $tryHasTerminator = $true
            break
        }
    }

    # 8. 收集Try块内生成的所有节点（除了终止语句节点）
    #    只统计“当前 try 直系 body 中”的节点，忽略嵌套的 try 块内部节点，
    #    否则内层 throw 会被错误地直接连到外层 catch。
    $tryAllNodes = @()
    $tryExitNodes = @()
    $tryReturnNodes = @()
    for ($i = $nodeCountBefore; $i -lt $cfg.Nodes.Count; $i++) {
        $node = $cfg.Nodes[$i]

        # 如果节点缺少 AST 信息，保守地认为它属于当前 try
        $isInNestedTry = $false
        if ($null -ne $node.Ast) {
            $ancestor = $node.Ast.Parent
            while ($null -ne $ancestor) {
                if ($ancestor -is [System.Management.Automation.Language.TryStatementAst]) {
                    if ($ancestor -ne $tryAst) {
                        # 该节点处于当前 try 内部的嵌套 try 中
                        $isInNestedTry = $true
                    }
                    break
                }
                $ancestor = $ancestor.Parent
            }
        }

        if ($isInNestedTry) {
            continue  # 交由内层 try 自己的 catch 处理异常，不直接连到当前 try 的 catch
        }

        # 记录 Try 块中的 Exit / Return 节点（无论如何都要触发 finally）
        if ($node.Type -eq "Exit") {
            $tryExitNodes += $node
        }
        elseif ($node.Type -eq "Return") {
            $tryReturnNodes += $node
        }

        # 排除终止语句节点和特殊节点（Try/Catch/Finally等），但保留Throw节点，因为Throw需要连接到Catch/Finally
        if ($node.Type -notin @("Return", "Exit", "Break", "Continue", "Try", "Catch", "Finally", "Merge", "Start", "End")) {
            $tryAllNodes += $node
        }
    }

    # 9. Try块内所有可能执行的节点都连接到异常处理路径（异常边）
    #    - 如果存在 Catch，则连接到第一个 Catch（后续通过 Catch 链分发）
    #    - 如果没有 Catch 但存在 Finally（try-finally），则异常直接跳到 Finally
    if ($null -ne $firstCatchNode) {
        foreach ($stmtNode in $tryAllNodes) {
            Add-Edge -cfg $cfg -from $stmtNode.Id -to $firstCatchNode.Id -label "Exception"
        }
    }
    elseif ($null -ne $finallyNode) {
        # try-finally（无 catch）的情况，异常路径直接进入 finally
        foreach ($stmtNode in $tryAllNodes) {
            Add-Edge -cfg $cfg -from $stmtNode.Id -to $finallyNode.Id -label "Exception"
        }
    }

    # 9.5. Exit / Return 不是异常，不经过 catch，但在 try 中出现时，仍然必须执行 finally
    if ($null -ne $finallyNode) {
        if ($tryExitNodes.Count -gt 0) {
            foreach ($exitNode in $tryExitNodes) {
                Add-Edge -cfg $cfg -from $exitNode.Id -to $finallyNode.Id -label "Exit"
            }
        }
        if ($tryReturnNodes.Count -gt 0) {
            foreach ($retNode in $tryReturnNodes) {
                Add-Edge -cfg $cfg -from $retNode.Id -to $finallyNode.Id -label "Return"
            }
        }
    }

    # 10. Try 块正常结束（无异常路径）
    if (-not $tryHasTerminator -and $null -ne $prevNodeRef.Value) {
        $lastNodeType = $prevNodeRef.Value.Type
        if ($lastNodeType -ne "Return" -and $lastNodeType -ne "Exit" -and $lastNodeType -ne "Break" -and $lastNodeType -ne "Continue" -and $lastNodeType -ne "Throw") {
            $branchEndNodes += $prevNodeRef.Value
        }
    }

    # 11. 处理 Catch 块（按顺序判断，只进入一个）
    # 连接 Catch 链：Catch1 --NotMatch--> Catch2 --NotMatch--> Catch3
    for ($i = 0; $i -lt $catchNodes.Count; $i++) {
        $catchInfo = $catchNodes[$i]
        $catchNode = $catchInfo.Node
        $catchClause = $catchInfo.Clause

        # 如果不是第一个 Catch，从上一个 Catch 连接过来（表示"类型不匹配，继续判断"）
        if ($i -gt 0) {
            $prevCatchNode = $catchNodes[$i - 1].Node
            Add-Edge -cfg $cfg -from $prevCatchNode.Id -to $catchNode.Id -label "Not Match"
        }

        # 处理 Catch 块内的语句
        $prevNodeRef.Value = $catchNode
        $catchHasTerminator = $false
        foreach ($statement in $catchClause.Body.Statements) {
            $hasTerminator = Convert-AstNode -cfg $cfg -node $statement -prevNodeRef $prevNodeRef -endNodeRef $endNodeRef -loopContext $loopContext -switchContext $switchContext
            if ($hasTerminator) {
                $catchHasTerminator = $true
                break
            }
        }

        # Catch 块正常结束
        if (-not $catchHasTerminator -and $null -ne $prevNodeRef.Value) {
            $lastNodeType = $prevNodeRef.Value.Type
            if ($lastNodeType -ne "Return" -and $lastNodeType -ne "Exit" -and $lastNodeType -ne "Break" -and $lastNodeType -ne "Continue" -and $lastNodeType -ne "Throw") {
                $branchEndNodes += $prevNodeRef.Value
            }
        }
    }

    # 11.5. 如果有catch块，为最后一个catch添加Uncaught Exception路径
    if ($catchNodes.Count -gt 0) {
        $lastCatchNode = $catchNodes[-1].Node
        # 从最后一个catch连接到End节点，表示"未匹配的异常"（将来可能被外层 try 重定向到更外层的 catch）
        if ($null -ne $endNodeRef) {
            $endNode = if ($endNodeRef -is [ref]) { $endNodeRef.Value } else { $endNodeRef }
            if ($null -ne $endNode) {
                Add-Edge -cfg $cfg -from $lastCatchNode.Id -to $endNode.Id -label "Uncaught Exception"
            }
        }
    }

    # 11.8. 当前 try 有 catch 的情况下，把“内部子结构”产生的
    #       "Uncaught Exception" 从 End 重定向到本 try 的第一个 catch。
    #       这里的“内部子结构”包括：
    #         - 内层嵌套 try/catch/finally
    #         - 内层 finally 中的 throw
    #         - 内层 catch 中的 rethrow
    #       但不包括：
    #         - 本 try 自己的 catch 节点产生的 Uncaught Exception（11.5 添加的那条边）
    #         - 本 try 自己的 catch 块内部的 rethrow
    #       否则会产生 catch -> catch 的自环，或者让“当前层的 rethrow”又被当前层的 catch 接住。
    # 11.8.C 当前 try 有 catch 的情况下，把“内部子结构”产生的
    #        "Uncaught Exception" 从 End 重定向到本 try 的第一个 catch。
    #        注意：即使本 try 同时有 finally，我们仍然优先建模为“先进入本层 catch”，
    #        finally 的执行统一由 12/11.8.F 中的逻辑保证。
    if ($catchNodes.Count -gt 0 -and $null -ne $firstCatchNode -and $null -ne $endNodeRef) {
        $endNode = if ($endNodeRef -is [ref]) { $endNodeRef.Value } else { $endNodeRef }
        if ($null -ne $endNode) {
            for ($i = 0; $i -lt $cfg.Edges.Count; $i++) {
                $edge = $cfg.Edges[$i]
                if ($edge.Label -ne "Uncaught Exception" -or $edge.To -ne $endNode.Id) {
                    continue
                }

                # 找到产生这个 Uncaught Exception 的节点
                $fromNode = $cfg.Nodes | Where-Object { $_.Id -eq $edge.From }
                if ($null -eq $fromNode -or $null -eq $fromNode.Ast) {
                    continue
                }

                # 1) 如果本身就是 Catch 节点，需要区分：
                #    - 来自“当前 try 自己的最后一个 catch”（11.5 添加的边）：保持为到 End，避免自环；
                #    - 来自“内层 try 的 catch”：应该被当前 try 的 catch 捕获（允许重定向）。
                if ($fromNode.Type -eq "Catch" -and $null -ne $fromNode.Ast) {
                    $catchAst = $fromNode.Ast
                    if ($catchAst -is [System.Management.Automation.Language.CatchClauseAst]) {
                        $parentTryOfCatch = $catchAst.Parent
                        if ($parentTryOfCatch -is [System.Management.Automation.Language.TryStatementAst] -and
                            $parentTryOfCatch -eq $tryAst) {
                            # 本 try 自己的 catch 节点：跳过，不重定向
                            continue
                        }
                    }
                }

                # 2) 判断该节点是否属于当前 try 的 AST 子树内
                $hasThisTryAncestor = $false
                $ancestor = $fromNode.Ast
                while ($null -ne $ancestor) {
                    if ($ancestor -is [System.Management.Automation.Language.TryStatementAst]) {
                        if ($ancestor -eq $tryAst) { $hasThisTryAncestor = $true }
                    }
                    $ancestor = $ancestor.Parent
                }

                if (-not $hasThisTryAncestor) {
                    continue
                }

                # 3) 如果 Uncaught Exception 源自“当前 try 自己的 catch 块内部”的 rethrow，
                #    也不要重定向，让它继续冒泡到更外层的 try 或脚本 End。
                $belongsToThisTryCatch = $false
                $ancestor = $fromNode.Ast.Parent
                while ($null -ne $ancestor) {
                    if ($ancestor -is [System.Management.Automation.Language.CatchClauseAst]) {
                        $parentTry = $ancestor.Parent
                        if ($parentTry -is [System.Management.Automation.Language.TryStatementAst] -and
                            $parentTry -eq $tryAst) {
                            $belongsToThisTryCatch = $true
                        }
                        break
                    }
                    $ancestor = $ancestor.Parent
                }

                if ($belongsToThisTryCatch) {
                    continue
                }

                # 4) 剩下的情况：
                #    - 内层 try/finally 中的 throw（包括 finally 中的 throw）
                #    - 内层 try 的 catch 中 rethrow
                #    这些都应该被当前 try 的 catch 捕获，而不是直接到 End。
                $edge.To = $firstCatchNode.Id
            }
        }
    }

    # 11.8.F 只要当前 try 有 finally，就把“内部子结构”产生的 Uncaught Exception
    #        从 End 重定向到本 try 的 finally 节点：
    #        - 有 catch 时：catch 处理/重新抛出的异常，在离开本层前仍然要先执行 finally；
    #        - 只有 finally（无 catch）时：未捕获异常同样要先执行 finally，再继续向外冒泡。
    if ($null -ne $finallyNode -and $null -ne $endNodeRef) {
        $endNode = if ($endNodeRef -is [ref]) { $endNodeRef.Value } else { $endNodeRef }
        if ($null -ne $endNode) {
            for ($i = 0; $i -lt $cfg.Edges.Count; $i++) {
                $edge = $cfg.Edges[$i]
                if ($edge.Label -ne "Uncaught Exception" -or $edge.To -ne $endNode.Id) {
                    continue
                }

                # 找到产生这个 Uncaught Exception 的节点
                $fromNode = $cfg.Nodes | Where-Object { $_.Id -eq $edge.From }
                if ($null -eq $fromNode -or $null -eq $fromNode.Ast) {
                    continue
                }

                # 1) 判断该节点是否属于当前 try 的 AST 子树内
                $hasThisTryAncestor = $false
                $ancestor = $fromNode.Ast
                while ($null -ne $ancestor) {
                    if ($ancestor -is [System.Management.Automation.Language.TryStatementAst]) {
                        if ($ancestor -eq $tryAst) { $hasThisTryAncestor = $true }
                    }
                    $ancestor = $ancestor.Parent
                }
                if (-not $hasThisTryAncestor) {
                    continue
                }

                # 2) 如果 Uncaught Exception 源自“本 try 自己的 finally 块内部”的 throw，
                #    不要重定向，让它继续冒泡到更外层（由外层的 try-finally 处理）。
                $inThisFinally = $false
                $ancestor = $fromNode.Ast.Parent
                while ($null -ne $ancestor) {
                    if ($ancestor -is [System.Management.Automation.Language.StatementBlockAst] -and
                        $tryAst.Finally -eq $ancestor) {
                        $inThisFinally = $true
                        break
                    }
                    $ancestor = $ancestor.Parent
                }
                if ($inThisFinally) {
                    continue
                }

                # 3) 其余情况（例如内层 try/finally、内层 catch 的 rethrow 等）
                #    在当前层都应该先执行 finally，然后再继续向外冒泡。
                $edge.To = $finallyNode.Id
            }

            # 这里不再从 finally 节点本身连出 Uncaught Exception，
            # 而是在 finally 块正常结束时，由最后一个语句节点连出（见后面的逻辑）。
        }
    }

    # 12. 如果有 Finally 块，所有分支都要经过 Finally
    if ($null -ne $finallyNode) {
        # 所有正常结束的分支连接到 Finally
        foreach ($endNode in $branchEndNodes) {
            Add-Edge -cfg $cfg -from $endNode.Id -to $finallyNode.Id
        }
        $branchEndNodes = @()  # 清空，因为现在从 Finally 继续

        # 处理 Finally 块内的语句
        $prevNodeRef.Value = $finallyNode
        $finallyHasTerminator = $false
        foreach ($statement in $tryAst.Finally.Statements) {
            $hasTerminator = Convert-AstNode -cfg $cfg -node $statement -prevNodeRef $prevNodeRef -endNodeRef $endNodeRef -loopContext $loopContext -switchContext $switchContext
            if ($hasTerminator) {
                $finallyHasTerminator = $true
                break
            }
        }

        # Finally 块正常结束
        if (-not $finallyHasTerminator -and $null -ne $prevNodeRef.Value) {
            $lastNodeType = $prevNodeRef.Value.Type

            # ① 异常路径：如果当前有未捕获异常挂起，执行完 finally 内最后一个语句后，
            #    异常应继续向外冒泡到 End。解释器在运行时根据“是否处于异常状态”
            #    选择是否走这条边。
            if ($null -ne $endNodeRef) {
                $endNode = if ($endNodeRef -is [ref]) { $endNodeRef.Value } else { $endNodeRef }
                if ($null -ne $endNode) {
                    Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $endNode.Id -label "Uncaught Exception"
                }
            }

            # ② Exit 特例：Try 块中出现过 Exit，说明存在 “Exit 整个脚本” 的路径：
            #    try { ... exit } finally { ... }  ==>  Exit -> Finally -> ScriptEnd
            if ($tryExitNodes.Count -gt 0 -and $script:__CFG_ScriptEndNode) {
                Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $script:__CFG_ScriptEndNode.Id -label "Exit"
                $prevNodeRef.Value = $script:__CFG_ScriptEndNode
                # 不把 finally 的出口加入 $branchEndNodes，这条路径视为终止
            }
            # ③ Return 特例：Try 块中出现过 Return，说明存在 “return 当前脚本块/函数” 的路径：
            #    try { ... return } finally { ... }  ==>  Return -> Finally -> End/FuncEnd
            elseif ($tryReturnNodes.Count -gt 0 -and $null -ne $endNodeRef) {
                $endNode = if ($endNodeRef -is [ref]) { $endNodeRef.Value } else { $endNodeRef }
                if ($null -ne $endNode) {
                    Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $endNode.Id -label "Return"
                    $prevNodeRef.Value = $endNode
                }
                # 同样不把 finally 的出口加入 $branchEndNodes，这条路径视为终止
            }
            else {
                # ④ 正常路径：finally 之后仍然可能继续执行后续语句
                if ($lastNodeType -ne "Return" -and $lastNodeType -ne "Exit" -and $lastNodeType -ne "Break" -and $lastNodeType -ne "Continue" -and $lastNodeType -ne "Throw") {
                    $branchEndNodes += $prevNodeRef.Value
                }
            }
        }
    }

    # 13. 所有“可继续执行”的分支汇聚到 Try-End
    if ($branchEndNodes.Count -gt 0) {
        if ($null -eq $tryEndNode) {
            $tryEndNode = Add-Node -cfg $cfg -type "Merge" -text "Try-End" -line $tryAst.Extent.EndLineNumber -ast $tryAst
        }
        foreach ($endNode in $branchEndNodes) {
            Add-Edge -cfg $cfg -from $endNode.Id -to $tryEndNode.Id
        }

        # 14. 只有存在汇聚分支时，才更新 prevNodeRef 为 Try-End
        $prevNodeRef.Value = $tryEndNode

        # 至少有一条路径可以继续执行
        return $false
    }

    # 没有任何可继续执行的分支：所有路径都在 try/catch/finally 中终止
    return $true
}

function Get-LoopHeaderText {
    param($loopAst)

    switch ($loopAst) {
        {$_ -is [System.Management.Automation.Language.ForStatementAst]} {
            $init = if ($null -ne $loopAst.Initializer) { $loopAst.Initializer.Extent.Text } else { "" }
            $cond = if ($null -ne $loopAst.Condition) { $loopAst.Condition.Extent.Text } else { "" }
            $iter = if ($null -ne $loopAst.Iterator) { $loopAst.Iterator.Extent.Text } else { "" }
            "for ($init; $cond; $iter)"
        }
        {$_ -is [System.Management.Automation.Language.ForEachStatementAst]} {
            $var = $loopAst.Variable.Extent.Text
            $col = if ($null -ne $loopAst.Condition) { $loopAst.Condition.Extent.Text } else { "null" }
            "foreach ($var in $col)"
        }
        default {
            $loopAst.GetType().Name -replace 'StatementAst$'
        }
    }
}

function Get-ConditionLabel {
    param($loopAst)

    switch ($loopAst) {
        {$_ -is [System.Management.Automation.Language.ForEachStatementAst]} {
            "Has next $($loopAst.Variable.Extent.Text)?"
        }
        {$_ -is [System.Management.Automation.Language.DoUntilStatementAst]} {
            "Until ($($loopAst.Condition.Extent.Text)"
        }
        default {
            if ($null -eq $loopAst.Condition) { "AlwaysTrue" }
            else { "Condition: $($loopAst.Condition.Extent.Text)" }
        }
    }
}

function Get-ExitLabel {
    param($loopAst)

    switch ($loopAst) {
        {$_ -is [System.Management.Automation.Language.DoUntilStatementAst]} { "Until True" }
        {$_ -is [System.Management.Automation.Language.DoWhileStatementAst]} { "While False" }
        {$_ -is [System.Management.Automation.Language.ForEachStatementAst]} { "No more items" }
        default { "Condition False" }
    }
}

function Get-LoopEndText {
    param($loopAst)
    $typeName = $loopAst.GetType().Name -replace 'StatementAst$'
    "End $typeName"
}

function Get-LoopBackLabel {
    param($loopAst)

    switch ($loopAst) {
        {$_ -is [System.Management.Automation.Language.DoWhileStatementAst]} { "While True" }
        {$_ -is [System.Management.Automation.Language.DoUntilStatementAst]} { "Until False" }
    }
}

function Convert-LoopStatement {
    param(
        [hashtable]$cfg,
        [System.Management.Automation.Language.LoopStatementAst]$loopAst,
        [ref]$prevNodeRef,
        $endNodeRef = $null
    )

    # 0. 防御性检查
    if ($null -eq $loopAst -or $null -eq $prevNodeRef) {
        Write-Warning "Invalid input: loopAst or prevNodeRef is null"
        return
    }

    # 1. 获取循环元数据
    $loopType = switch ($loopAst) {
        {$_ -is [System.Management.Automation.Language.ForStatementAst]}       { "for" }
        {$_ -is [System.Management.Automation.Language.ForEachStatementAst]}    { "foreach" }
        {$_ -is [System.Management.Automation.Language.WhileStatementAst]}      { "while" }
        {$_ -is [System.Management.Automation.Language.DoWhileStatementAst]}   { "do-while" }
        {$_ -is [System.Management.Automation.Language.DoUntilStatementAst]}   { "do-until" }
        default { "unknown-loop" }
    }

    # 2. 创建循环开始节点
    $loopStart = Add-Node -cfg $cfg -type "LoopStart" -text (Get-LoopHeaderText $loopAst) -line $loopAst.Extent.StartLineNumber -ast $loopAst
    Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $loopStart.Id
    $currentNode = $loopStart

    # 3. 处理 do-while/do-until 的首次执行（先执行后判断）
    $isDoLoop = $loopType -in "do-while", "do-until"
    if ($isDoLoop) {
        # 3.1 创建专门的条件节点（放在循环体之后）
        $conditionNode = Add-Node -cfg $cfg -type "Condition" -text (Get-ConditionLabel $loopAst) -line $loopAst.Condition.Extent.StartLineNumber -ast $loopAst.Condition

        # 3.1.5 创建循环结束节点（提前创建，供 break 使用）
        $loopEnd = Add-Node -cfg $cfg -type "LoopEnd" -text (Get-LoopEndText $loopAst) -line $loopAst.Extent.EndLineNumber -ast $loopAst

        # 3.1.6 创建循环上下文（do-while/do-until 的 continue 应该跳转到条件检查）
        # 注意：continue 应该跳转到 conditionNode，而不是 loopStart
        # 因为 do-while/do-until 是先执行循环体，然后检查条件
        # continue 应该跳过循环体剩余部分，直接进行条件检查
        $loopContext = [PSCustomObject]@{
            LoopEnd = $loopEnd
            LoopContinue = $conditionNode  # do-while/do-until 的 continue 跳转到条件检查
        }

        # 3.2 先处理循环体
        foreach ($statement in $loopAst.Body.Statements) {
            $hasReturn = Convert-AstNode -cfg $cfg -node $statement -prevNodeRef ([ref]$currentNode) -endNodeRef $endNodeRef -loopContext $loopContext -switchContext $null
            # 如果遇到 return/break/continue，停止处理后续语句（这些语句不可达）
            if ($hasReturn) {
                break
            }
        }

        # 3.3 连接循环体到条件节点（只有当最后一个节点不是 break/continue 时）
        # break 节点应该只连接到 loopEnd，continue 应该只连接到循环继续点
        if ($null -ne $currentNode) {
            $lastNodeType = $currentNode.Type
            if ($lastNodeType -ne "Break" -and $lastNodeType -ne "Continue") {
                Add-Edge -cfg $cfg -from $currentNode.Id -to $conditionNode.Id
            }
        }

        # 3.4 创建两条边：
        #     - 条件满足时继续循环（回到循环开始）
        #     - 条件不满足时退出循环
        Add-Edge -cfg $cfg -from $conditionNode.Id -to $loopStart.Id -label (Get-LoopBackLabel $loopAst)
        Add-Edge -cfg $cfg -from $conditionNode.Id -to $loopEnd.Id -label (Get-ExitLabel $loopAst)

        $prevNodeRef.Value = $loopEnd
        return  # 提前返回，避免执行通用逻辑
    }

    # 4. 添加条件节点
    $conditionNode = Add-Node -cfg $cfg -type "Condition" -text (Get-ConditionLabel $loopAst) -line $loopAst.Condition.Extent.StartLineNumber -ast $loopAst.Condition
    Add-Edge -cfg $cfg -from $currentNode.Id -to $conditionNode.Id
    $currentNode = $conditionNode

    # 4.5 创建循环结束节点（提前创建，供 break 使用）
    $loopEnd = Add-Node -cfg $cfg -type "LoopEnd" -text (Get-LoopEndText $loopAst) -line $loopAst.Extent.EndLineNumber -ast $loopAst

    # 4.6 创建循环上下文（非 do-xx 循环的 continue 应该回到 conditionNode）
    $loopContext = [PSCustomObject]@{
        LoopEnd = $loopEnd
        LoopContinue = $conditionNode  # 非 do-xx 循环的 continue 回到条件节点
    }

    # 5. 处理非 do-xx 的循环体（先判断后执行）
    if (-not $isDoLoop) {
        foreach ($statement in $loopAst.Body.Statements) {
            $hasReturn = Convert-AstNode -cfg $cfg -node $statement -prevNodeRef ([ref]$currentNode) -endNodeRef $endNodeRef -loopContext $loopContext -switchContext $null
            # 如果遇到 return/break/continue，停止处理后续语句（这些语句不可达）
            if ($hasReturn) {
                break
            }
        }
        # 添加循环回边（只有当最后一个节点不是 break/continue 时）
        # break 节点应该只连接到 loopEnd，continue 应该只连接到循环继续点
        if ($null -ne $currentNode) {
            $lastNodeType = $currentNode.Type
            if ($lastNodeType -ne "Break" -and $lastNodeType -ne "Continue") {
                Add-Edge -cfg $cfg -from $currentNode.Id -to $conditionNode.Id -label "Next"
            }
        }
    }

    # 6. 连接条件节点到循环结束节点
    Add-Edge -cfg $cfg -from $conditionNode.Id -to $loopEnd.Id -label (Get-ExitLabel $loopAst)
    $prevNodeRef.Value = $loopEnd
}

function Convert-AstNode {
    param(
        $cfg,
        $node,
        [ref]$prevNodeRef, # 用于跨递归维护上一个节点
        $endNodeRef = $null, # 可选的 End 节点引用（ref 类型），用于 Return 语句连接
        $loopContext = $null, # 循环上下文，包含 loopEnd 和 loopContinue 节点
        $switchContext = $null # Switch 上下文，包含 switchMerge 节点
    )

    # 一、如果是根节点（ScriptBlockAst），处理其直接子节点
    if ($node -is [System.Management.Automation.Language.ScriptBlockAst]) {
        # 添加 "Start" 节点
        $startNode = Add-Node -cfg $cfg -type "Start" -text "Script Start" -line 0
        $prevNodeRef.Value = $startNode

        # 先创建 End 节点（但不立即连接），供 Return 语句使用
        $endNode = Add-Node -cfg $cfg -type "End" -text "Script End" -line $node.Extent.EndLineNumber
        $endNodeRef = [ref]$endNode
        # 记录全局 Script End 节点，供 Exit 在任意作用域直接终止脚本使用
        $script:__CFG_ScriptEndNode = $endNode

        # 1. 按顺序处理各个块
        $blocks = @(
            @{ Name = "Param"; Block = $node.ParamBlock }
            @{ Name = "DynamicParam"; Block = $node.DynamicParamBlock }
            @{ Name = "Begin"; Block = $node.BeginBlock }
            @{ Name = "Process"; Block = $node.ProcessBlock }
            @{ Name = "End"; Block = $node.EndBlock }
        )

        foreach ($block in $blocks) {
            #2. 只处理begin和end两种blockAst，续写
            if ($block.Name -in "Begin", "End") {
                if ($null -ne $block.Block) {
                # 3. 处理块内的每个语句
                    foreach ($statement in $block.Block.Statements) {
                        $hasReturn = Convert-AstNode -cfg $cfg -node $statement -prevNodeRef $prevNodeRef -endNodeRef $endNodeRef -loopContext $null -switchContext $null
                        # 如果遇到 return，停止处理后续语句
                        if ($hasReturn) {
                            break
                        }
                    }
                }
            }
        }

        # 4. 连接最后一个节点到 End 节点（如果还没有被 Return/Break/Continue 连接）
        # 如果最后一个节点是 Return/Break/Continue 节点，它已经连接到 End，不需要再创建边
        if ($null -ne $prevNodeRef.Value -and $prevNodeRef.Value.Id -ne $endNode.Id) {
            $lastNodeType = $prevNodeRef.Value.Type
            if ($lastNodeType -ne "Return" -and $lastNodeType -ne "Break" -and $lastNodeType -ne "Continue" -and $lastNodeType -ne "Throw") {
                Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $endNode.Id
            }
        }
        $prevNodeRef.Value = $endNode
    }
    # 二、如果是ReturnStatementAst，创建 Return 节点
    elseif ($node -is [System.Management.Automation.Language.ReturnStatementAst]) {
        $returnNode = Add-Node -cfg $cfg -type "Return" -text $node.Extent.Text -line $node.Extent.StartLineNumber -ast $node
        # 连接到上一个节点
        if ($null -ne $prevNodeRef.Value) {
            Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $returnNode.Id
        }

        # Return 一般终止当前脚本块/函数，但如果它位于“带 finally 的 try”中，
        # 必须先执行 finally，再在 finally 之后返回。这里检测是否在这样的 try 中，
        # 如果是，则暂时不连到 End，由 Convert-TryAstNode 负责通过 finally 终止。
        $inTryWithFinally = $false
        $ancestor = $node.Parent
        while ($null -ne $ancestor) {
            if ($ancestor -is [System.Management.Automation.Language.TryStatementAst]) {
                if ($null -ne $ancestor.Finally) {
                    $inTryWithFinally = $true
                }
                break
            }
            $ancestor = $ancestor.Parent
        }

        if (-not $inTryWithFinally -and $null -ne $endNodeRef) {
            # 不在任何带 finally 的 try 中：直接连接到 End / FuncEnd
            $endNode = if ($endNodeRef -is [ref]) { $endNodeRef.Value } else { $endNodeRef }
            if ($null -ne $endNode) {
                Add-Edge -cfg $cfg -from $returnNode.Id -to $endNode.Id -label "Return"
            }
        }

        $prevNodeRef.Value = $returnNode
        return $true  # 返回 true 表示遇到了 return
    }
    # 二点二、如果是 ExitStatementAst，创建 Exit 节点（终止脚本）
    elseif ($node -is [System.Management.Automation.Language.ExitStatementAst]) {
        $exitNode = Add-Node -cfg $cfg -type "Exit" -text $node.Extent.Text -line $node.Extent.StartLineNumber -ast $node
        # 连接到上一个节点
        if ($null -ne $prevNodeRef.Value) {
            Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $exitNode.Id
        }
        # Exit 始终终止整个脚本，但如果它位于某个带 finally 的 try 中，
        # 则必须先执行 finally，再在 finally 之后连到 Script End。
        # 这里检测是否处于“带 finally 的 try”内部，如果是，就不在这里直接连 Script End，
        # 由 Convert-TryAstNode 的 9.5 + 12 步负责通过 finally 终止脚本。
        $inTryWithFinally = $false
        $ancestor = $node.Parent
        while ($null -ne $ancestor) {
            if ($ancestor -is [System.Management.Automation.Language.TryStatementAst]) {
                if ($null -ne $ancestor.Finally) {
                    $inTryWithFinally = $true
                }
                break
            }
            $ancestor = $ancestor.Parent
        }

        if (-not $inTryWithFinally) {
            # 不在任何带 finally 的 try 中：直接连接到全局 Script End（如果存在）
            if ($script:__CFG_ScriptEndNode) {
                Add-Edge -cfg $cfg -from $exitNode.Id -to $script:__CFG_ScriptEndNode.Id -label "Exit"
            }
            elseif ($null -ne $endNodeRef) {
                # 兜底：如果没记录到全局 End，就退回到当前作用域的 endNodeRef
                $endNode = if ($endNodeRef -is [ref]) { $endNodeRef.Value } else { $endNodeRef }
                if ($null -ne $endNode) {
                    Add-Edge -cfg $cfg -from $exitNode.Id -to $endNode.Id -label "Exit"
                }
            }
        }
        $prevNodeRef.Value = $exitNode
        return $true  # 返回 true 表示遇到了 exit，后续语句不可达
    }
    # 二点五、如果是BreakStatementAst，创建 Break 节点并连接到 switch/循环结束节点或 End
    elseif ($node -is [System.Management.Automation.Language.BreakStatementAst]) {
        $breakNode = Add-Node -cfg $cfg -type "Break" -text $node.Extent.Text -line $node.Extent.StartLineNumber -ast $node
        # 连接到上一个节点
        if ($null -ne $prevNodeRef.Value) {
            Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $breakNode.Id
        }
        # 优先检查 switchContext，如果存在则连接到 switch 的 merge 节点
        if ($null -ne $switchContext -and $null -ne $switchContext.SwitchMerge) {
            Add-Edge -cfg $cfg -from $breakNode.Id -to $switchContext.SwitchMerge.Id -label "Break"
            $prevNodeRef.Value = $breakNode
            return $true  # 在 switch 中，break 会停止处理后续语句（因为已经跳出 switch，后续语句不可达）
        }
        # 如果提供了 loopContext，连接到循环结束节点
        elseif ($null -ne $loopContext -and $null -ne $loopContext.LoopEnd) {
            Add-Edge -cfg $cfg -from $breakNode.Id -to $loopContext.LoopEnd.Id -label "Break"
            $prevNodeRef.Value = $breakNode
            return $true  # 在循环中，break 会停止处理后续语句（因为已经跳出循环，后续语句不可达）
        }
        else {
            # 如果不在 switch 或循环中，连接到 End 节点（类似 return）
            if ($null -ne $endNodeRef) {
                $endNode = if ($endNodeRef -is [ref]) { $endNodeRef.Value } else { $endNodeRef }
                if ($null -ne $endNode) {
                    Add-Edge -cfg $cfg -from $breakNode.Id -to $endNode.Id -label "Break"
                }
            }
            $prevNodeRef.Value = $breakNode
            return $true  # 不在 switch 或循环中时，break 起到 return 的效果，停止处理后续语句
        }
    }
    # 二点六、如果是ContinueStatementAst，创建 Continue 节点并连接到 switch/循环继续节点或 End
    elseif ($node -is [System.Management.Automation.Language.ContinueStatementAst]) {
        $continueNode = Add-Node -cfg $cfg -type "Continue" -text $node.Extent.Text -line $node.Extent.StartLineNumber -ast $node
        # 连接到上一个节点
        if ($null -ne $prevNodeRef.Value) {
            Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $continueNode.Id
        }
        # 优先检查 switchContext，如果存在则连接到 switch 条件节点（跳出当前 case，继续判断下一个 case）
        if ($null -ne $switchContext -and $null -ne $switchContext.SwitchNode) {
            Add-Edge -cfg $cfg -from $continueNode.Id -to $switchContext.SwitchNode.Id -label "Continue"
            $prevNodeRef.Value = $continueNode
            return $true  # 在 switch 中，continue 会停止处理后续语句（因为已经跳出当前 case，继续判断下一个 case）
        }
        # 如果提供了 loopContext，连接到循环继续节点
        elseif ($null -ne $loopContext -and $null -ne $loopContext.LoopContinue) {
            Add-Edge -cfg $cfg -from $continueNode.Id -to $loopContext.LoopContinue.Id -label "Continue"
            $prevNodeRef.Value = $continueNode
            return $true  # 在循环中，continue 会停止处理后续语句（因为已经跳到下一次循环，后续语句不可达）
        }
        else {
            # 如果不在 switch 或循环中，连接到 End 节点（类似 return）
            if ($null -ne $endNodeRef) {
                $endNode = if ($endNodeRef -is [ref]) { $endNodeRef.Value } else { $endNodeRef }
                if ($null -ne $endNode) {
                    Add-Edge -cfg $cfg -from $continueNode.Id -to $endNode.Id -label "Continue"
                }
            }
            $prevNodeRef.Value = $continueNode
            return $true  # 不在 switch 或循环中时，continue 起到 return 的效果，停止处理后续语句
        }
    }
    # 二点七、如果是ThrowStatementAst，创建 Throw 节点并处理异常
    elseif ($node -is [System.Management.Automation.Language.ThrowStatementAst]) {
        $throwNode = Add-Node -cfg $cfg -type "Throw" -text $node.Extent.Text -line $node.Extent.StartLineNumber -ast $node
        # 连接到上一个节点
        if ($null -ne $prevNodeRef.Value) {
            Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $throwNode.Id
        }

        # 判断是否位于 catch / finally 块内部（兼容不支持 FinallyClauseAst 的旧版 PowerShell）
        $inCatch = $false
        $inFinally = $false
        $hasTryAncestor = $false
        $ancestor = $node.Parent
        while ($null -ne $ancestor) {
            if ($ancestor -is [System.Management.Automation.Language.CatchClauseAst]) {
                # 任意层级的 catch（内层或外层）都视为 inCatch
                $inCatch = $true
            }
            elseif ($ancestor -is [System.Management.Automation.Language.StatementBlockAst]) {
                # 判断这个 StatementBlockAst 是否是某个 TryStatementAst 的 Finally
                $parentTry = $ancestor.Parent
                if ($parentTry -is [System.Management.Automation.Language.TryStatementAst] -and
                    $parentTry.Finally -eq $ancestor) {
                    $inFinally = $true
                }
            }
            elseif ($ancestor -is [System.Management.Automation.Language.TryStatementAst]) {
                # 标记该 throw 出现在某个 try 块内部（由 Convert-TryAstNode 负责异常路由）
                $hasTryAncestor = $true
            }
            $ancestor = $ancestor.Parent
        }

        # 如果 throw 出现在 catch / finally 中，则表示“本层 try 不再处理该异常”：
        # - 对于 catch 中的 throw：这是“重新抛出”（rethrow）；当前 try 的 catch 已经执行过，新的异常只会交给外层 try。
        # - 对于 finally 中的 throw：finally 总是在 try/catch 之后执行，此时当前 try 的 catch 也不会再参与处理。
        # 统一建模为一条 Uncaught Exception 到 End，由外层 try（如果存在）在 Convert-TryAstNode 的 11.8 步中
        # 把这条边重定向到自身的 catch / finally；如果不存在外层 try，则表示脚本/函数在 finally 中抛出未捕获异常后终止。
        if (($inCatch -or $inFinally) -and $null -ne $endNodeRef) {
            $endNode = if ($endNodeRef -is [ref]) { $endNodeRef.Value } else { $endNodeRef }
            if ($null -ne $endNode) {
                Add-Edge -cfg $cfg -from $throwNode.Id -to $endNode.Id -label "Uncaught Exception"
            }
        }
        # 否则，如果该 throw 不在任何 try 内部，也不在 catch/finally 中，
        # 则视为“当前脚本/函数作用域内的未捕获异常”：直接连到 End/FuncEnd。
        # （位于 try 块内部的 throw，其异常路径由 Convert-TryAstNode 的 Exception 边统一处理，
        #  这里不再额外添加 Uncaught Exception -> End，避免产生重复/错误的路径。）
        elseif (-not $hasTryAncestor -and $null -ne $endNodeRef) {
            $endNode = if ($endNodeRef -is [ref]) { $endNodeRef.Value } else { $endNodeRef }
            if ($null -ne $endNode) {
                Add-Edge -cfg $cfg -from $throwNode.Id -to $endNode.Id -label "Uncaught Exception"
            }
        }

        $prevNodeRef.Value = $throwNode
        return $true  # 返回 true 表示遇到了 throw，后续语句不可达
    }
    # 二点八、如果是 FunctionDefinitionAst，创建函数定义节点，并为函数体构建独立的子CFG
    elseif ($node -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
        # 顶层：函数定义本身作为一个顺序节点出现，便于观测
        $funcName = $node.Name
        $defText = "function $funcName"
        $funcDefNode = Add-Node -cfg $cfg -type "FunctionDef" -text $defText -line $node.Extent.StartLineNumber -ast $node
        if ($null -ne $prevNodeRef.Value) {
            Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $funcDefNode.Id
        }
        $prevNodeRef.Value = $funcDefNode

        # 为函数体生成独立的 FuncStart/FuncEnd 子图（不影响当前顺序流）
        Convert-FunctionDefinitionAst -cfg $cfg -funcAst $node

        # 定义函数不会终止脚本后续语句
        return $false
    }
    # 三、如果是IfStatementAst，创建分支
    elseif ($node -is [System.Management.Automation.Language.IfStatementAst]) {
        $allBranchesReturn = Convert-IfAstNode -cfg $cfg -ifAst $node -prevNodeRef $prevNodeRef -endNodeRef $endNodeRef -loopContext $loopContext
        # 如果所有分支都有 return，返回 true 以停止处理后续语句
        return $allBranchesReturn
    }
    # 三点五、如果是SwitchStatementAst，创建分支
    elseif ($node -is [System.Management.Automation.Language.SwitchStatementAst]) {
        $allBranchesReturn = Convert-SwitchAstNode -cfg $cfg -switchAst $node -prevNodeRef $prevNodeRef -endNodeRef $endNodeRef -loopContext $loopContext
        # 如果所有分支都有 return，返回 true 以停止处理后续语句
        return $allBranchesReturn
    }
    # 四、如果是LoopStatementAst，创建循环
    elseif($node -is [System.Management.Automation.Language.LoopStatementAst]){
        Convert-LoopStatement -cfg $cfg -loopAst $node -prevNodeRef $prevNodeRef -endNodeRef $endNodeRef
        return $false
    }
    # 四点五、如果是TryStatementAst，创建 try/catch/finally 结构
    elseif ($node -is [System.Management.Automation.Language.TryStatementAst]) {
        $allBranchesReturn = Convert-TryAstNode -cfg $cfg -tryAst $node -prevNodeRef $prevNodeRef -endNodeRef $endNodeRef -loopContext $loopContext -switchContext $switchContext
        return $allBranchesReturn
    }
    # 五、其余节点
    else {
        #顺序连接当前节点和前一个节点
        $currentNode = Add-Node -cfg $cfg -type $node.GetType().Name -text $node.Extent.Text -line $node.Extent.StartLineNumber -ast $node
        # 连接到上一个节点
        if ($null -ne $prevNodeRef.Value) {
            Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $currentNode.Id
        }
        $prevNodeRef.Value = $currentNode
        return $false
    }
}

function Get-ScriptControlFlow {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ScriptPath
    )

    # 确保文件存在
    if (-not (Test-Path $ScriptPath)) {
        Write-Error "文件不存在: $ScriptPath"
        return $null
    }

    # 解析脚本为AST
    try {
        $ast = Get-Ast $ScriptPath
    }
    catch {
        Write-Error "解析失败: $_"
        return $null
    }

    # 初始化CFG数据结构
    $mycfg = @{
        Nodes = @()
        Edges = @()
    }

    # 处理AST节点
    Convert-AstNode -cfg $mycfg -node $ast -prevNodeRef ([ref]$null)

    return $mycfg
}

#生成图结构
function Export-CfgToDot {
    param(
        [hashtable]$finalCFG,
        [string]$outputPath = "control_flow.dot"
    )

    # 辅助函数：终极安全格式化
    function Format-DotLabel {
        param([string]$text)
        if ([string]::IsNullOrWhiteSpace($text)) { return "" }
        # 移除所有控制字符（包括换行符）
        $cleaned = [System.Text.RegularExpressions.Regex]::Replace(
            $text,
            '[\x00-\x1F\x7F]',
            ''
        )
        # 转义反斜杠和引号（但保留\l换行标记）
        $escaped = $cleaned -replace '\\', '\\' -replace '"', '\"'
            # 智能截断：优先在完整单词后截断
        if ($escaped.Length -gt 50) {
            $truncated = $escaped.Substring(0, 47)
            $lastSpace = $truncated.LastIndexOf(' ')
            if ($lastSpace -gt 40) {
                $truncated = $truncated.Substring(0, $lastSpace)
            }
            "$truncated..."
        } else {
            $escaped
        }
    }

    # 1. 生成节点定义（使用foreach语句替代ForEach-Object）
    $nodeDefinitions = @()
    foreach ($node in $finalCFG.Nodes) {
        $shape = switch ($node.Type) {
            {$_ -in "Start", "End", "FuncStart", "FuncEnd"}   { "oval" }
            {$_ -in "Condition", "If"} { "diamond" }
            {$_ -in "Merge"} { "point" }
            default                   { "box" }
        }
        $label = "Line $($node.Line)\l$($node.Type)\l$(Format-DotLabel $node.Text)"
        $nodeDefinitions += "    $($node.Id) [label=`"$label`", shape=$shape];"
    }

    # 2. 生成边定义（同样使用foreach语句）
    $edgeDefinitions = @()
    foreach ($edge in $finalCFG.Edges) {
        $line = "    $($edge.From) -> $($edge.To)"
        if (-not [string]::IsNullOrWhiteSpace($edge.Label)) {
            $line += " [label=`"$(Format-DotLabel $edge.Label)`"]"
        }
        $edgeDefinitions += "$line;"
    }

    # 3. 生成DOT内容（严格ASCII格式）
$dotContent = @"
digraph G {
    rankdir=TB;
    node [
        fontname="Consolas"
        shape=box
        width=0
        height=0
        margin="0.2,0.1"
        fontsize=10
    ];
    edge [fontname="Arial", arrowhead=vee, fontsize=9];

    // Nodes
$($nodeDefinitions -join "`n")

    // Edges
$($edgeDefinitions -join "`n")
}
"@

    # 4. 用二进制方式写入文件（绝对无BOM）
    try {
        $ascii = [System.Text.Encoding]::ASCII
        [System.IO.File]::WriteAllText($outputPath, $dotContent, $ascii)
        Write-Host ("DOT文件已生成: {0}" -f $outputPath) -ForegroundColor Green

        # 5. 直接调用原生dot.exe（绕过PowerShell）
        $pngPath = [System.IO.Path]::ChangeExtension($outputPath, ".png")
        $dotExe = Get-Command dot -ErrorAction Stop | Select-Object -ExpandProperty Source
        & $dotExe -Tpng $outputPath -o $pngPath 2>&1 | Out-Null

        if (Test-Path $pngPath) {
            Write-Host ("流程图已生成: {0}" -f $pngPath) -ForegroundColor Green
            return $pngPath
        } else {
            Write-Warning ("生成失败，请手动执行: {0} -Tpng `"{1}`" -o `"{2}`"" -f $dotExe, $outputPath, $pngPath)
        }
    } 
    catch 
    {
        Write-Warning "致命错误: $_"
        # 输出问题内容供调试（PS5安全写法）
        $dotContent | Out-Host
    }
}




# # 生成控制流图
# $scriptPath = Join-Path $PSScriptRoot 'in/in.ps1'
# $finalCFG = Get-ScriptControlFlow -ScriptPath $scriptPath
# # 格式化输出节点列表
# $finalCFG.Nodes | Select-Object Id, Type, @{
#     Name="Text"
#     Expression={
#         $text = $_.Text
#         if ($text.Length -gt 20) { $text.Substring(0, 20) + "..." } 
#         else { $text }
#     }
# }, Line, Ast | Format-Table -AutoSize
# $finalCFG.Edges | Format-Table -AutoSize
# #Out-GridView 查看
# # $finalCFG.Nodes | Out-GridView -Title 'CFG Nodes'
# # 示例调用（使用您已有的 $finalCFG）
# $dotPath = Join-Path $PSScriptRoot 'in/in.dot'
# Export-CfgToDot -finalCFG $finalCFG -outputPath $dotPath
