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

    # 1. 添加 Switch 条件节点
    $switchConditionText = if ($null -ne $switchAst.Condition) { $switchAst.Condition.Extent.Text } else { "Switch Condition" }
    $switchNode = Add-Node -cfg $cfg -type "Switch Condition" -text "Switch ($switchConditionText)" -line $switchAst.Extent.StartLineNumber -ast $switchAst
    Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $switchNode.Id
    $prevNodeRef.Value = $switchNode

    # 1.5 提前创建 Switch 的 merge 节点（供 break 使用）
    $switchMergeNode = Add-Node -cfg $cfg -type "Merge" -text "Switch-End" -line $switchAst.Extent.EndLineNumber -ast $switchAst

    # 1.6 创建 Switch 上下文（供 break 和 continue 使用）
    $currentSwitchContext = [PSCustomObject]@{
        SwitchMerge = $switchMergeNode
        SwitchNode = $switchNode  # switch 条件节点，供 continue 使用
    }

    # 2. 初始化分支结束节点集合
    $branchEndNodes = @()

    # 3. 处理所有 Clause（case 分支）
    foreach ($clause in $switchAst.Clauses) {
        # 3.1 添加 case 条件节点
        $caseLabelText = if ($null -ne $clause.Item1) { $clause.Item1.Extent.Text } else { "Case" }
        $caseLineNumber = if ($null -ne $clause.Item1) { $clause.Item1.Extent.StartLineNumber } else { $switchAst.Extent.StartLineNumber }
        $caseNode = Add-Node -cfg $cfg -type "Case" -text "Case $caseLabelText" -line $caseLineNumber -ast $clause.Item1
        Add-Edge -cfg $cfg -from $switchNode.Id -to $caseNode.Id -label "Case"
        $prevNodeRef.Value = $caseNode

        # 3.2 处理分支代码块（Clause[i].Item2）
        $branchHasReturn = $false
        foreach ($statement in $clause.Item2.Statements) {
            $hasReturn = Convert-AstNode -cfg $cfg -node $statement -prevNodeRef $prevNodeRef -endNodeRef $endNodeRef -loopContext $loopContext -switchContext $currentSwitchContext
            # 如果遇到 return/break/continue/exit，停止处理后续语句
            if ($hasReturn) {
                $branchHasReturn = $true
                break
            }
        }
        # 只有当分支不以 return、break、continue 或 exit 结束时，才添加到分支结束节点集合
        # break/continue 已经跳出了 switch 语句的上下文，不应该连接到 merge 节点
        if (-not $branchHasReturn -and $null -ne $prevNodeRef.Value) {
            $lastNodeType = $prevNodeRef.Value.Type
            if ($lastNodeType -ne "Break" -and $lastNodeType -ne "Continue") {
                $branchEndNodes += $prevNodeRef.Value
            }
        }
    }

    # 4. 处理 DefaultClause（如果存在 default）
    if ($null -ne $switchAst.Default) {
        $defaultNode = Add-Node -cfg $cfg -type "Default" -text "Default" -line $switchAst.Default.Extent.StartLineNumber -ast $switchAst.Default
        Add-Edge -cfg $cfg -from $switchNode.Id -to $defaultNode.Id -label "Default"
        $prevNodeRef.Value = $defaultNode

        # 处理 Default 代码块
        $defaultHasReturn = $false
        foreach ($statement in $switchAst.Default.Statements) {
            $hasReturn = Convert-AstNode -cfg $cfg -node $statement -prevNodeRef $prevNodeRef -endNodeRef $endNodeRef -loopContext $loopContext -switchContext $currentSwitchContext
            # 如果遇到 return/break/continue/exit，停止处理后续语句
            if ($hasReturn) {
                $defaultHasReturn = $true
                break
            }
        }
        # 只有当 Default 分支不以 return、break、continue 或 exit 结束时，才添加到分支结束节点集合
        # break/continue 已经跳出了 switch 语句的上下文，不应该连接到 merge 节点
        if (-not $defaultHasReturn -and $null -ne $prevNodeRef.Value) {
            $lastNodeType = $prevNodeRef.Value.Type
            if ($lastNodeType -ne "Break" -and $lastNodeType -ne "Continue") {
                $branchEndNodes += $prevNodeRef.Value
            }
        }
    }
    else {
        # 如果没有显式 default，创建一个隐式 default 节点，表示"所有 case 都不匹配时继续执行"
        $implicitDefaultNode = Add-Node -cfg $cfg -type "Default" -text "Implicit Default" -line $switchAst.Extent.EndLineNumber -ast $switchAst
        Add-Edge -cfg $cfg -from $switchNode.Id -to $implicitDefaultNode.Id -label "Default"
        # 隐式 default 分支总是会继续执行后续代码，所以添加到分支结束节点集合
        $branchEndNodes += $implicitDefaultNode
        # 更新 prevNodeRef 为隐式 default 节点，这样后续代码会从这个节点继续
        $prevNodeRef.Value = $implicitDefaultNode
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
                    # 所有 return/exit 已经直接连接到 End，不需要 merge 节点
                    # 将 prevNodeRef 指向 End，这样后续语句不会被处理
                    $prevNodeRef.Value = $endNode
                    return $true  # 返回 true 表示所有分支都有 return/exit
                }
            }
            # 如果所有分支都以 break/continue 结束，不应该将 prevNodeRef 设置为 End
            # 保持 prevNodeRef 不变（指向 break/continue 节点），返回 true 以停止处理后续语句
            return $true
        }
    }

    # 6. 将所有分支结束节点连接到汇聚节点（使用之前创建的 switchMergeNode）
    foreach ($endNode in $branchEndNodes) {
        Add-Edge -cfg $cfg -from $endNode.Id -to $switchMergeNode.Id
    }

    # 7. 更新 prevNodeRef 为汇聚节点，供后续连接
    $prevNodeRef.Value = $switchMergeNode
    return $false  # 返回 false 表示不是所有分支都有 return/exit
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

        # 4. 连接最后一个节点到 End 节点（如果还没有被 Return/Break/Continue/Exit 连接）
        # 如果最后一个节点是 Return/Break/Continue/Exit 节点，它已经连接到 End，不需要再创建边
        if ($null -ne $prevNodeRef.Value -and $prevNodeRef.Value.Id -ne $endNode.Id) {
            $lastNodeType = $prevNodeRef.Value.Type
            if ($lastNodeType -ne "Return" -and $lastNodeType -ne "Break" -and $lastNodeType -ne "Continue" -and $lastNodeType -ne "Exit") {
                Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $endNode.Id
            }
        }
        $prevNodeRef.Value = $endNode
    }
    # 二、如果是ReturnStatementAst，创建 Return 节点并连接到 End
    elseif ($node -is [System.Management.Automation.Language.ReturnStatementAst]) {
        $returnNode = Add-Node -cfg $cfg -type "Return" -text $node.Extent.Text -line $node.Extent.StartLineNumber -ast $node
        # 连接到上一个节点
        if ($null -ne $prevNodeRef.Value) {
            Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $returnNode.Id
        }
        # 连接到 End 节点（如果提供了 endNodeRef）
        if ($null -ne $endNodeRef) {
            $endNode = if ($endNodeRef -is [ref]) { $endNodeRef.Value } else { $endNodeRef }
            if ($null -ne $endNode) {
                Add-Edge -cfg $cfg -from $returnNode.Id -to $endNode.Id -label "Return"
            }
        }
        $prevNodeRef.Value = $returnNode
        return $true  # 返回 true 表示遇到了 return
    }
    # 二点二、如果是 ExitStatementAst，创建 Exit 节点并连接到 End（终止脚本）
    elseif ($node -is [System.Management.Automation.Language.ExitStatementAst]) {
        $exitNode = Add-Node -cfg $cfg -type "Exit" -text $node.Extent.Text -line $node.Extent.StartLineNumber -ast $node
        # 连接到上一个节点
        if ($null -ne $prevNodeRef.Value) {
            Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $exitNode.Id
        }
        # 连接到 End 节点（如果提供了 endNodeRef）
        if ($null -ne $endNodeRef) {
            $endNode = if ($endNodeRef -is [ref]) { $endNodeRef.Value } else { $endNodeRef }
            if ($null -ne $endNode) {
                Add-Edge -cfg $cfg -from $exitNode.Id -to $endNode.Id -label "Exit"
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
        write-host "foreach"
        return $false
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
            {$_ -in "Start", "End"}   { "oval" }
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




# 生成控制流图
$scriptPath = Join-Path $PSScriptRoot 'in/in.ps1'
$finalCFG = Get-ScriptControlFlow -ScriptPath $scriptPath
# 格式化输出节点列表
$finalCFG.Nodes | Select-Object Id, Type, @{
    Name="Text"
    Expression={
        $text = $_.Text
        if ($text.Length -gt 20) { $text.Substring(0, 20) + "..." } 
        else { $text }
    }
}, Line, Ast | Format-Table -AutoSize
$finalCFG.Edges | Format-Table -AutoSize
#Out-GridView 查看
# $finalCFG.Nodes | Out-GridView -Title 'CFG Nodes'
# 示例调用（使用您已有的 $finalCFG）
$dotPath = Join-Path $PSScriptRoot 'in/in.dot'
Export-CfgToDot -finalCFG $finalCFG -outputPath $dotPath