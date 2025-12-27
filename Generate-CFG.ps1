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

# 统一的变量作用域枚举，避免在代码里到处写魔法字符串
Add-Type -TypeDefinition @"
public enum VarScope
{
    Unspecified = 0,
    Global      = 1,
    Script      = 2,
    Local       = 3,
    Private     = 4
}
"@

# 辅助函数：添加节点
function Add-Node {
    param(
        $cfg,
        $type,
        $text,
        $line,
        $ast = $null,
        $ownerAst = $null  # 节点所属的结构 AST（用于 try/catch 嵌套判断）
    )
    $node = [PSCustomObject]@{
        Id          = $cfg.Nodes.Count + 1
        Type        = $type
        Text        = $text
        Line        = $line
        Ast         = $ast
        OwnerAst    = $ownerAst  # 虚拟节点所属的结构（如 switch/foreach/for 的 AST）
        VarsRead    = @()  # 当前节点读取的变量列表（元素为 { Name; Scope }）
        VarsWritten = @()  # 当前节点写入的变量列表（元素为 { Name; Scope }）
    }

    # 如果提供了 AST，分析该节点中的变量读写情况
    if ($null -ne $ast) {
        Populate-NodeVariableUsage -node $node
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

# 辅助函数：向节点添加变量（自动去重）
function Add-VarToNode {
    param(
        [pscustomobject]$node,
        [pscustomobject]$varEntry,
        [ValidateSet("Read", "Write", "Both")]
        [string]$accessType
    )

    if ($accessType -in "Read", "Both") {
        $exists = $node.VarsRead | Where-Object { $_.Name -eq $varEntry.Name -and $_.Scope -eq $varEntry.Scope }
        if (-not $exists) {
            $node.VarsRead = @($node.VarsRead) + @($varEntry)
        }
    }

    if ($accessType -in "Write", "Both") {
        $exists = $node.VarsWritten | Where-Object { $_.Name -eq $varEntry.Name -and $_.Scope -eq $varEntry.Scope }
        if (-not $exists) {
            $node.VarsWritten = @($node.VarsWritten) + @($varEntry)
        }
    }
}

function Get-VariableAccessKind {
    param(
        [System.Management.Automation.Language.VariableExpressionAst]$VarAst
    )

    if ($null -eq $VarAst) { return $null }

    $parent = $VarAst.Parent

    # 0) 数组字面量在赋值左边：$a, $b, $c = ...
    # 变量的直接父节点是 ArrayLiteralAst，需要向上查找 AssignmentStatementAst
    if ($parent -is [System.Management.Automation.Language.ArrayLiteralAst]) {
        $arrayLiteral = $parent
        $grandParent = $arrayLiteral.Parent
        if ($grandParent -is [System.Management.Automation.Language.AssignmentStatementAst]) {
            $assign = $grandParent
            # 检查 ArrayLiteralAst 是否在赋值语句的左边
            if ($assign.Left -eq $arrayLiteral -or
                ($null -ne $assign.Left -and $assign.Left.Find({ param($n) $n -eq $arrayLiteral }, $true))) {
                # 复合赋值（+=、-= 等）视为读+写
                if ($assign.Operator -ne [System.Management.Automation.Language.TokenKind]::Equals) {
                    return "ReadWrite"
                }
                else {
                    return "Write"
                }
            }
        }
        # 如果不在赋值左边，继续后续判断
    }

    # 1) 赋值语句：左边写 / 读写，右边读
    if ($parent -is [System.Management.Automation.Language.AssignmentStatementAst]) {
        $assign = $parent
        $inLeft = $false
        if ($null -ne $assign.Left) {
            if ($assign.Left -eq $VarAst) {
                $inLeft = $true
            }
            elseif ($assign.Left -is [System.Management.Automation.Language.Ast]) {
                $inLeft = $assign.Left.Find({ param($n) $n -eq $VarAst }, $true)
            }
        }

        if ($inLeft) {
            # 复合赋值（+=、-= 等）视为读+写
            if ($assign.Operator -ne [System.Management.Automation.Language.TokenKind]::Equals) {
                return "ReadWrite"
            }
            else {
                return "Write"
            }
        }
        else {
            return "Read"
        }
    }

    # 1.5) 索引表达式在赋值左边：$h["k1"] = "v1" 或 $arr[0] = 1
    # 变量是 IndexExpressionAst 的 Target，且该 IndexExpressionAst 在赋值语句左边
    # 也需要处理嵌套情况：$nested["inner"]["key"] = "value" 或 $matrix[0][1] = 99
    if ($parent -is [System.Management.Automation.Language.IndexExpressionAst]) {
        $indexExpr = $parent
        # 检查变量是否是索引表达式的 Target（即 $h 在 $h["k1"] 中）
        if ($indexExpr.Target -eq $VarAst) {
            # 向上查找，看这个索引表达式（或其嵌套的外层）是否在赋值语句左边
            $currentExpr = $indexExpr
            while ($null -ne $currentExpr) {
                $grandParent = $currentExpr.Parent
                if ($grandParent -is [System.Management.Automation.Language.AssignmentStatementAst]) {
                    $assign = $grandParent
                    # 检查当前表达式是否在赋值语句的左边
                    $inLeft = $false
                    if ($null -ne $assign.Left) {
                        if ($assign.Left -eq $currentExpr) {
                            $inLeft = $true
                        }
                        elseif ($assign.Left -is [System.Management.Automation.Language.Ast]) {
                            $inLeft = $assign.Left.Find({ param($n) $n -eq $currentExpr }, $true)
                        }
                    }
                    if ($inLeft) {
                        # 索引赋值：修改集合元素，需要先读取集合再写入
                        return "ReadWrite"
                    }
                    break
                }
                elseif ($grandParent -is [System.Management.Automation.Language.IndexExpressionAst]) {
                    # 嵌套索引：$nested["inner"]["key"]，继续向上查找
                    $currentExpr = $grandParent
                }
                else {
                    break
                }
            }
        }
        # 如果变量在索引位置（如 $arr[$i]），则是读取
        return "Read"
    }

    # 1.6) 成员表达式在赋值左边：$obj.Prop = 2
    # 变量是 MemberExpressionAst 的 Expression（Target），且该表达式在赋值语句左边
    if ($parent -is [System.Management.Automation.Language.MemberExpressionAst]) {
        $memberExpr = $parent
        # 检查变量是否是成员表达式的 Expression（即 $obj 在 $obj.Prop 中）
        if ($memberExpr.Expression -eq $VarAst) {
            # 向上查找，看这个成员表达式（或其嵌套的外层）是否在赋值语句左边
            $currentExpr = $memberExpr
            while ($null -ne $currentExpr) {
                $grandParent = $currentExpr.Parent
                if ($grandParent -is [System.Management.Automation.Language.AssignmentStatementAst]) {
                    $assign = $grandParent
                    # 检查当前表达式是否在赋值语句的左边
                    $inLeft = $false
                    if ($null -ne $assign.Left) {
                        if ($assign.Left -eq $currentExpr) {
                            $inLeft = $true
                        }
                        elseif ($assign.Left -is [System.Management.Automation.Language.Ast]) {
                            $inLeft = $assign.Left.Find({ param($n) $n -eq $currentExpr }, $true)
                        }
                    }
                    if ($inLeft) {
                        # 属性赋值：修改对象属性，需要先读取对象再写入
                        return "ReadWrite"
                    }
                    break
                }
                elseif ($grandParent -is [System.Management.Automation.Language.MemberExpressionAst] -or
                        $grandParent -is [System.Management.Automation.Language.IndexExpressionAst]) {
                    # 嵌套成员/索引：$obj.Inner.Prop 或 $obj.Items[0]，继续向上查找
                    $currentExpr = $grandParent
                }
                else {
                    break
                }
            }
        }
        # 如果变量在其他位置，则是读取
        return "Read"
    }

    # 2) 一元运算 ++/-- ：读+写
    if ($parent -is [System.Management.Automation.Language.UnaryExpressionAst]) {
        $unary = $parent
        if ($unary.TokenKind -in @(
                [System.Management.Automation.Language.TokenKind]::PlusPlus,
                [System.Management.Automation.Language.TokenKind]::MinusMinus,
                [System.Management.Automation.Language.TokenKind]::PostfixPlusPlus,
                [System.Management.Automation.Language.TokenKind]::PostfixMinusMinus
            )) {
            return "ReadWrite"
        }
        return "Read"
    }

    # 3) 参数声明：视为写（绑定形参）
    if ($parent -is [System.Management.Automation.Language.ParameterAst]) {
        return "Write"
    }

    # 4) foreach ($x in ...) 的迭代变量：写（绑定变量）
    if ($parent -is [System.Management.Automation.Language.ForEachStatementAst]) {
        if ($parent.Variable -eq $VarAst) {
            return "Write"
        }
    }

    # 其它情况统一视为读
    return "Read"
}

function Populate-NodeVariableUsage {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$node
    )

    if ($null -eq $node.Ast) {
        $node.VarsRead    = @()
        $node.VarsWritten = @()
        return
    }

    $reads  = @()
    $writes = @()

    $varAsts = $node.Ast.FindAll({
            param($n)
            $n -is [System.Management.Automation.Language.VariableExpressionAst]
        }, $true)

    foreach ($v in $varAsts) {
        $kind = Get-VariableAccessKind -VarAst $v
        if (-not $kind) { continue }

        # VariablePath.UserPath 去掉了 $ 和作用域前缀
        $name = $v.VariablePath.UserPath
        if ([string]::IsNullOrWhiteSpace($name)) { continue }

        # 根据 VariablePath 上的标志推断作用域提示（使用统一的 VarScope 枚举）
        $scope = [VarScope]::Unspecified
        if     ($v.VariablePath.IsGlobal)  { $scope = [VarScope]::Global }
        elseif ($v.VariablePath.IsScript)  { $scope = [VarScope]::Script }
        elseif ($v.VariablePath.IsLocal)   { $scope = [VarScope]::Local }
        elseif ($v.VariablePath.IsPrivate) { $scope = [VarScope]::Private }

        $entry = [PSCustomObject]@{
            Name  = $name
            Scope = $scope
        }

        switch ($kind) {
            "Read" {
                $reads += $entry
            }
            "Write" {
                $writes += $entry
            }
            "ReadWrite" {
                $reads  += $entry
                $writes += $entry
            }
        }
    }

    # 去重：按 Name + Scope 组合去重
    $node.VarsRead = @(
        $reads |
            Group-Object Name, Scope |
            ForEach-Object { $_.Group[0] }
    )
    $node.VarsWritten = @(
        $writes |
            Group-Object Name, Scope |
            ForEach-Object { $_.Group[0] }
    )
}

# 辅助函数：查找 AST 中所有嵌套的多元素 Pipeline
function Get-AllNestedPipelines {
    param(
        [Parameter(Mandatory = $true)]
        $ast
    )

    if ($null -eq $ast) { return @() }

    # 在 AST 子树中查找所有多元素 PipelineAst
    $pipelines = $ast.FindAll({
        param($n)
        $n -is [System.Management.Automation.Language.PipelineAst] -and
        $n.PipelineElements.Count -gt 1
    }, $true)

    return @($pipelines)
}

# 辅助函数：展开表达式中的嵌套 Pipeline
# 返回值：@{ ModifiedText = "修改后的文本"; PipeVars = @("变量名列表") }
# 如果没有嵌套 Pipeline，返回 $null
function Expand-NestedPipelines {
    param(
        [Parameter(Mandatory = $true)]
        $cfg,
        [Parameter(Mandatory = $true)]
        $ast,
        [Parameter(Mandatory = $true)]
        [ref]$prevNodeRef
    )

    $nestedPipelines = Get-AllNestedPipelines -ast $ast
    if ($nestedPipelines.Count -eq 0) {
        return $null
    }

    # 按位置倒序排列（从后往前处理，避免文本替换时位置偏移）
    $sortedPipelines = $nestedPipelines | Sort-Object { $_.Extent.StartOffset } -Descending

    # 记录所有 Pipeline 的变量名和替换信息
    $replacements = @()
    $pipeVarEntries = @()

    foreach ($pipeline in $sortedPipelines) {
        $guid = [guid]::NewGuid().ToString("N").Substring(0, 8)
        $pipeVar = "__pipe_$guid"
        $pipeVarEntry = [PSCustomObject]@{ Name = $pipeVar; Scope = [VarScope]::Unspecified }

        $elements = $pipeline.PipelineElements
        $lastIndex = $elements.Count - 1

        # 拆分 Pipeline 的前 N-1 个元素为独立节点
        for ($i = 0; $i -lt $elements.Count - 1; $i++) {
            $element = $elements[$i]

            # 构建节点文本
            if ($i -eq 0) {
                $nodeText = $element.Extent.Text
            } else {
                $nodeText = "`$$pipeVar | " + $element.Extent.Text
            }

            $pipeNode = Add-Node -cfg $cfg -type "PipelineElement" -text $nodeText -line $element.Extent.StartLineNumber -ast $element

            # 变量流处理
            if ($i -eq 0) {
                # 首元素：写入 $pipeVar
                Add-VarToNode -node $pipeNode -varEntry $pipeVarEntry -accessType "Write"
            } else {
                # 中间元素：读取 + 写入 $pipeVar
                Add-VarToNode -node $pipeNode -varEntry $pipeVarEntry -accessType "Both"
            }

            # 连接边
            if ($null -ne $prevNodeRef.Value) {
                if ($i -gt 0) {
                    Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $pipeNode.Id -label "Pipeline"
                } else {
                    Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $pipeNode.Id
                }
            }
            $prevNodeRef.Value = $pipeNode
        }

        # 记录替换信息：将整个 Pipeline 替换为 "$pipeVar | 最后一个元素"
        $lastElement = $elements[$lastIndex]
        $originalText = $pipeline.Extent.Text
        $replacementText = "`$$pipeVar | " + $lastElement.Extent.Text

        $replacements += @{
            Original = $originalText
            Replacement = $replacementText
        }
        $pipeVarEntries += $pipeVarEntry
    }

    # 修改原始文本
    $modifiedText = $ast.Extent.Text
    foreach ($r in $replacements) {
        $modifiedText = $modifiedText.Replace($r.Original, $r.Replacement)
    }

    return @{
        ModifiedText = $modifiedText
        PipeVarEntries = $pipeVarEntries
    }
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

    # 1. 添加 If 入口节点
    #    If Condition 节点只是结构示意，不直接参与表达式求值和变量读写，
    #    因此不需要携带完整的 IfStatementAst，避免干扰变量分析。
    $ifNode = Add-Node -cfg $cfg -type "If Condition" -text "If Condition" -line $ifAst.Extent.StartLineNumber -ast $null
    Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $ifNode.Id
    $prevNodeRef.Value = $ifNode

    # 2. 初始化分支结束节点集合
    $branchEndNodes = @()

    # 3. 串联式处理所有 Clause（if/elseif 分支）
    $previousCondNode = $null

    foreach ($clause in $ifAst.Clauses) {
        # 3.1 检查条件中是否有嵌套 Pipeline，如果有则先展开
        $conditionAst = $clause.Item1
        $expansion = Expand-NestedPipelines -cfg $cfg -ast $conditionAst -prevNodeRef $prevNodeRef

        if ($null -ne $expansion) {
            # 有嵌套 Pipeline，使用修改后的文本创建条件节点
            $condNode = Add-Node -cfg $cfg -type "Condition" -text $expansion.ModifiedText -line $conditionAst.Extent.StartLineNumber -ast $conditionAst
            # 添加 pipeVar 到 VarsRead
            foreach ($pipeVarEntry in $expansion.PipeVarEntries) {
                Add-VarToNode -node $condNode -varEntry $pipeVarEntry -accessType "Read"
            }
            # 连接最后一个 Pipeline 节点到条件节点
            if ($null -ne $prevNodeRef.Value) {
                Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $condNode.Id -label "Pipeline"
            }
        } else {
            # 没有嵌套 Pipeline，正常创建条件节点
            $condNode = Add-Node -cfg $cfg -type "Condition" -text $conditionAst.Extent.Text -line $conditionAst.Extent.StartLineNumber -ast $conditionAst

            if ($null -eq $previousCondNode) {
                # 第一个条件从 ifNode 进入
                Add-Edge -cfg $cfg -from $ifNode.Id -to $condNode.Id -label "Condition"
            }
            else {
                # 后续条件从上一个条件的 false 分支进入
                Add-Edge -cfg $cfg -from $previousCondNode.Id -to $condNode.Id -label "False"
            }
        }

        # 当前条件为真时，进入当前分支体
        $prevNodeRef.Value = $condNode

        # 3.2 处理分支代码块（Clause[i].Item2）
        $branchHasTerminator = $false
        $isFirstStatement = $true
        foreach ($statement in $clause.Item2.Statements) {
            $hasTerminator = Convert-AstNode -cfg $cfg -node $statement -prevNodeRef $prevNodeRef -endNodeRef $endNodeRef -loopContext $loopContext -switchContext $null

            # 第一个语句处理完后，给从条件节点出发的边加上 "True" 标签
            if ($isFirstStatement) {
                $isFirstStatement = $false
                $edgeFromCond = $cfg.Edges | Where-Object { $_.From -eq $condNode.Id -and $null -eq $_.Label }
                if ($edgeFromCond) {
                    $edgeFromCond.Label = "True"
                }
            }

            # 如果遇到 return/break/continue/exit/throw 之类的终止语句，停止处理后续语句
            if ($hasTerminator) {
                $branchHasTerminator = $true
                break
            }
        }

        # 3.3 记录当前条件节点为“上一个条件”，供下一个 clause 的 False 分支使用
        $previousCondNode = $condNode

        # 3.4 如果当前分支可以正常结束，则将其出口加入分支结束集合
        #     注意：当前分支的入口是 condNode，condNode 的 True 边隐含为“进入当前分支体”，
        #           因此这里不需要显式添加 True 边标签。
        if (-not $branchHasTerminator -and $null -ne $prevNodeRef.Value) {
            $lastNodeType = $prevNodeRef.Value.Type
            if ($lastNodeType -notin @("Break","Continue","Return","Exit","Throw")) {
                $branchEndNodes += $prevNodeRef.Value
            }
        }
    }

    # 4. 处理 ElseClause（如果存在显式 else）
    if ($null -ne $ifAst.ElseClause) {
        # Else 节点同样只是结构标记，不负责表达式求值，Ast 设为 $null
        $elseNode = Add-Node -cfg $cfg -type "Else" -text "Else" -line $ifAst.ElseClause.Extent.StartLineNumber -ast $null

        if ($null -ne $previousCondNode) {
            # 所有条件都为假时，最后一个条件的 False 进入 Else
            Add-Edge -cfg $cfg -from $previousCondNode.Id -to $elseNode.Id -label "False"
        }
        else {
            # 理论上不会出现没有条件只有 else 的 If，但做个保护：直接从 ifNode 进入 else
            Add-Edge -cfg $cfg -from $ifNode.Id -to $elseNode.Id -label "Else"
        }

        $prevNodeRef.Value = $elseNode

        # 处理 Else 代码块
        $elseHasTerminator = $false
        foreach ($statement in $ifAst.ElseClause.Statements) {
            $hasTerminator = Convert-AstNode -cfg $cfg -node $statement -prevNodeRef $prevNodeRef -endNodeRef $endNodeRef -loopContext $loopContext -switchContext $null
            if ($hasTerminator) {
                $elseHasTerminator = $true
                break
            }
        }

        if (-not $elseHasTerminator -and $null -ne $prevNodeRef.Value) {
            $lastNodeType = $prevNodeRef.Value.Type
            if ($lastNodeType -notin @("Break","Continue","Return","Exit","Throw")) {
                $branchEndNodes += $prevNodeRef.Value
            }
        }
    }
    else {
        # 如果没有显式 else：当所有条件都为假时，控制流应当直接“跳过 if”继续执行后续语句。
        # 我们创建一个隐式 Else 节点作为这一情况的入口（同样不携带 Ast）。
        $implicitElseNode = Add-Node -cfg $cfg -type "Else" -text "Implicit Else" -line $ifAst.Extent.EndLineNumber -ast $null

        if ($null -ne $previousCondNode) {
            Add-Edge -cfg $cfg -from $previousCondNode.Id -to $implicitElseNode.Id -label "False"
        }
        else {
            # 理论上不会出现没有任何条件的 if，这里做保护
            Add-Edge -cfg $cfg -from $ifNode.Id -to $implicitElseNode.Id -label "Else"
        }

        # 隐式 else 分支总是会继续执行后续代码，所以添加到分支结束节点集合
        $branchEndNodes += $implicitElseNode
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
    #    If-End 仅作为结构汇聚点，不参与表达式求值和变量读写，Ast 设为 $null。
    $mergeNode = Add-Node -cfg $cfg -type "Merge" -text "If-End" -line $ifAst.Extent.EndLineNumber -ast $null

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

    # ============================================================
    # 新设计：对齐 foreach 的迭代模式
    # SwitchStart → SwitchInit → SwitchCondition → SwitchBind → [串联Case] → SwitchIter → (回到Condition)
    # ============================================================

    # 1. 生成唯一变量名（使用 GUID 确保不与用户变量冲突）
    $guid = [guid]::NewGuid().ToString("N").Substring(0, 12)
    $collectionVar = "__sw_$guid"
    $indexVar = "__sw_${guid}_idx"

    # 预定义内部变量的条目（用于手动设置 VarsRead/VarsWritten）
    $collectionVarEntry = [PSCustomObject]@{ Name = $collectionVar; Scope = [VarScope]::Unspecified }
    $indexVarEntry = [PSCustomObject]@{ Name = $indexVar; Scope = [VarScope]::Unspecified }
    $underscoreVarEntry = [PSCustomObject]@{ Name = "_"; Scope = [VarScope]::Unspecified }

    # 2. 获取 switch 的 flags（-Wildcard, -Regex, -CaseSensitive, -Exact, -File, -Parallel）
    $switchFlags = @()
    if ($switchAst.Flags -band [System.Management.Automation.Language.SwitchFlags]::Wildcard) { $switchFlags += "-Wildcard" }
    if ($switchAst.Flags -band [System.Management.Automation.Language.SwitchFlags]::Regex) { $switchFlags += "-Regex" }
    if ($switchAst.Flags -band [System.Management.Automation.Language.SwitchFlags]::CaseSensitive) { $switchFlags += "-CaseSensitive" }
    if ($switchAst.Flags -band [System.Management.Automation.Language.SwitchFlags]::Exact) { $switchFlags += "-Exact" }
    if ($switchAst.Flags -band [System.Management.Automation.Language.SwitchFlags]::File) { $switchFlags += "-File" }
    if ($switchAst.Flags -band [System.Management.Automation.Language.SwitchFlags]::Parallel) { $switchFlags += "-Parallel" }
    $flagsText = if ($switchFlags.Count -gt 0) { " " + ($switchFlags -join " ") } else { "" }

    $switchConditionText = if ($null -ne $switchAst.Condition) { $switchAst.Condition.Extent.Text } else { "Switch Condition" }

    # 3. 创建 SwitchStart（装饰节点，ast = null）
    $switchStart = Add-Node -cfg $cfg -type "SwitchStart" -text "switch$flagsText ($switchConditionText)" -line $switchAst.Extent.StartLineNumber -ast $null
    Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $switchStart.Id
    $prevNodeRef.Value = $switchStart

    # 3.5 检查条件中是否有嵌套 Pipeline，如果有则先展开
    $conditionExpansion = $null
    if ($null -ne $switchAst.Condition) {
        $conditionExpansion = Expand-NestedPipelines -cfg $cfg -ast $switchAst.Condition -prevNodeRef $prevNodeRef
    }

    # 4. 创建 SwitchInit（初始化集合和索引）
    # VarsRead: 集合表达式中的变量（由 AST 自动分析）
    # VarsWritten: $__sw_xxx, $__sw_xxx_idx（手动添加）
    if ($null -ne $conditionExpansion) {
        # 有嵌套 Pipeline，使用修改后的文本
        $initText = "`$$collectionVar = " + $conditionExpansion.ModifiedText + "; `$$indexVar = 0"
        $initNode = Add-Node -cfg $cfg -type "SwitchInit" -text $initText -line $switchAst.Condition.Extent.StartLineNumber -ast $switchAst.Condition
        # 添加 pipeVar 到 VarsRead
        foreach ($pipeVarEntry in $conditionExpansion.PipeVarEntries) {
            Add-VarToNode -node $initNode -varEntry $pipeVarEntry -accessType "Read"
        }
        # 连接最后一个 Pipeline 节点到 SwitchInit
        if ($null -ne $prevNodeRef.Value) {
            Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $initNode.Id -label "Pipeline"
        }
    } else {
        # 没有嵌套 Pipeline，正常创建
        $initText = "`$$collectionVar = $switchConditionText; `$$indexVar = 0"
        $initNode = Add-Node -cfg $cfg -type "SwitchInit" -text $initText -line $switchAst.Condition.Extent.StartLineNumber -ast $switchAst.Condition
        Add-Edge -cfg $cfg -from $switchStart.Id -to $initNode.Id
    }
    # 手动追加内部变量的写入
    Add-VarToNode -node $initNode -varEntry $collectionVarEntry -accessType "Write"
    Add-VarToNode -node $initNode -varEntry $indexVarEntry -accessType "Write"

    # 5. 创建 SwitchCondition（判断是否还有元素）
    # VarsRead: $__sw_xxx_idx, $__sw_xxx（手动设置）
    # ast = $null，ownerAst = $switchAst 用于 try/catch 嵌套判断
    $condText = "`$$indexVar -lt `$$collectionVar.Count"
    $conditionNode = Add-Node -cfg $cfg -type "SwitchCondition" -text $condText -line $switchAst.Extent.StartLineNumber -ast $null -ownerAst $switchAst
    # 清空自动分析的结果，手动设置内部变量的读取
    $conditionNode.VarsRead = @($indexVarEntry, $collectionVarEntry)
    $conditionNode.VarsWritten = @()
    Add-Edge -cfg $cfg -from $initNode.Id -to $conditionNode.Id

    # 6. 创建 SwitchEnd（提前创建，供 break 和循环退出使用）
    $switchEnd = Add-Node -cfg $cfg -type "SwitchEnd" -text "End Switch" -line $switchAst.Extent.EndLineNumber -ast $null
    Add-Edge -cfg $cfg -from $conditionNode.Id -to $switchEnd.Id -label "False"

    # 7. 创建 SwitchBind（绑定当前元素到 $_）
    # VarsRead: $__sw_xxx, $__sw_xxx_idx
    # VarsWritten: $_
    # ast = $null，ownerAst = $switchAst 用于 try/catch 嵌套判断
    $bindText = "`$_ = `$$collectionVar[`$$indexVar]"
    $bindNode = Add-Node -cfg $cfg -type "SwitchBind" -text $bindText -line $switchAst.Extent.StartLineNumber -ast $null -ownerAst $switchAst
    $bindNode.VarsRead = @($collectionVarEntry, $indexVarEntry)
    $bindNode.VarsWritten = @($underscoreVarEntry)
    Add-Edge -cfg $cfg -from $conditionNode.Id -to $bindNode.Id -label "True"

    # 8. 创建 SwitchIter（递增索引，提前创建供 continue 跳转）
    # VarsRead: $__sw_xxx_idx
    # VarsWritten: $__sw_xxx_idx
    # ast = $null，ownerAst = $switchAst 用于 try/catch 嵌套判断
    $iterText = "`$$indexVar++"
    $iterNode = Add-Node -cfg $cfg -type "SwitchIter" -text $iterText -line $switchAst.Extent.StartLineNumber -ast $null -ownerAst $switchAst
    $iterNode.VarsRead = @($indexVarEntry)
    $iterNode.VarsWritten = @($indexVarEntry)
    Add-Edge -cfg $cfg -from $iterNode.Id -to $conditionNode.Id

    # 9. 创建 Switch 上下文（供 break 和 continue 使用）
    # break: 跳出整个 switch，连接到 switchEnd
    # continue: 跳到下一个元素，连接到 iterNode
    $currentSwitchContext = [PSCustomObject]@{
        SwitchMerge = $switchEnd
        SwitchNode = $iterNode
    }

    # 10. 串联处理所有 Case
    # 记录上一个节点（用于连接 False 边）
    $previousCondNode = $null
    # 记录需要连接到下一个 CaseCondition 的节点列表（包括上一个 CaseBody 的出口）
    $nodesToNextCase = @()
    # 记录需要直接连接到 SwitchIter 的节点（最后一个 Case 的出口）
    $nodesToIter = @()

    $caseIndex = 0
    $totalCases = $switchAst.Clauses.Count

    foreach ($clause in $switchAst.Clauses) {
        $caseIndex++
        $isLastCase = ($caseIndex -eq $totalCases) -and ($null -eq $switchAst.Default)

        # 10.1 创建 CaseCondition 节点
        $caseLabelText = if ($null -ne $clause.Item1) { $clause.Item1.Extent.Text } else { "Case" }
        $caseLineNumber = if ($null -ne $clause.Item1) { $clause.Item1.Extent.StartLineNumber } else { $switchAst.Extent.StartLineNumber }
        $caseCondNode = Add-Node -cfg $cfg -type "CaseCondition" -text "Case $caseLabelText" -line $caseLineNumber -ast $clause.Item1
        # 手动追加 $_ 的读取（CaseCondition 会隐式读取 $_）
        Add-VarToNode -node $caseCondNode -varEntry $underscoreVarEntry -accessType "Read"

        # 10.2 连接到 CaseCondition
        if ($null -eq $previousCondNode) {
            # 第一个 Case：从 SwitchBind 连接
            Add-Edge -cfg $cfg -from $bindNode.Id -to $caseCondNode.Id
        }
        else {
            # 后续 Case：从上一个 CaseCondition 的 False 边连接
            Add-Edge -cfg $cfg -from $previousCondNode.Id -to $caseCondNode.Id -label "False"
        }

        # 连接上一个 CaseBody 的出口到当前 CaseCondition
        foreach ($node in $nodesToNextCase) {
            Add-Edge -cfg $cfg -from $node.Id -to $caseCondNode.Id
        }
        $nodesToNextCase = @()

        # 10.3 处理 Case 分支体
        $prevNodeRef.Value = $caseCondNode
        $branchHasTerminator = $false

        # 创建一个临时的 prevNode 用于处理分支体
        $branchPrev = $caseCondNode
        $firstBodyNodeId = $null

        foreach ($statement in $clause.Item2.Statements) {
            $hasTerminator = Convert-AstNode -cfg $cfg -node $statement -prevNodeRef ([ref]$branchPrev) -endNodeRef $endNodeRef -loopContext $loopContext -switchContext $currentSwitchContext

            # 记录第一个 body 节点的 ID（用于修改边的标签）
            if ($null -eq $firstBodyNodeId -and $branchPrev.Id -ne $caseCondNode.Id) {
                $firstBodyNodeId = $branchPrev.Id
                # 找到从 caseCondNode 到 firstBodyNode 的边，添加 "True" 标签
                foreach ($edge in $cfg.Edges) {
                    if ($edge.From -eq $caseCondNode.Id -and $edge.To -eq $firstBodyNodeId) {
                        $edge.Label = "True"
                        break
                    }
                }
            }

            if ($hasTerminator) {
                $branchHasTerminator = $true
                break
            }
        }

        # 10.4 如果分支体为空，需要特殊处理
        # （空分支意味着 CaseCondition 的 True 边直接连到下一个 CaseCondition）

        # 10.5 更新 previousCondNode 和收集出口节点
        $previousCondNode = $caseCondNode

        if (-not $branchHasTerminator -and $null -ne $branchPrev) {
            $lastNodeType = $branchPrev.Type
            if ($lastNodeType -notin @("Break", "Continue", "Return", "Exit", "Throw")) {
                if ($isLastCase) {
                    # 最后一个 Case（且没有 default）：出口直接连到 SwitchIter
                    $nodesToIter += $branchPrev
                }
                else {
                    # 非最后一个 Case：出口连到下一个 CaseCondition
                    $nodesToNextCase += $branchPrev
                }
            }
        }
    }

    # 11. 处理 Default（如果有）
    if ($null -ne $switchAst.Default) {
        $defaultNode = Add-Node -cfg $cfg -type "Default" -text "Default" -line $switchAst.Default.Extent.StartLineNumber -ast $null

        # 最后一个 CaseCondition 的 False 边连接到 Default
        if ($null -ne $previousCondNode) {
            Add-Edge -cfg $cfg -from $previousCondNode.Id -to $defaultNode.Id -label "False"
        }

        # 上一个 CaseBody 的出口连接到 SwitchIter（不是 Default）
        foreach ($node in $nodesToNextCase) {
            $nodesToIter += $node
        }
        $nodesToNextCase = @()

        # 处理 Default 分支体
        $branchPrev = $defaultNode
        $defaultHasTerminator = $false

        foreach ($statement in $switchAst.Default.Statements) {
            $hasTerminator = Convert-AstNode -cfg $cfg -node $statement -prevNodeRef ([ref]$branchPrev) -endNodeRef $endNodeRef -loopContext $loopContext -switchContext $currentSwitchContext
            if ($hasTerminator) {
                $defaultHasTerminator = $true
                break
            }
        }

        # Default 出口连接到 SwitchIter
        if (-not $defaultHasTerminator -and $null -ne $branchPrev) {
            $lastNodeType = $branchPrev.Type
            if ($lastNodeType -notin @("Break", "Continue", "Return", "Exit", "Throw")) {
                $nodesToIter += $branchPrev
            }
        }
    }
    else {
        # 没有 Default：最后一个 CaseCondition 的 False 边直接连到 SwitchIter
        if ($null -ne $previousCondNode) {
            Add-Edge -cfg $cfg -from $previousCondNode.Id -to $iterNode.Id -label "False"
        }

        # 上一个 CaseBody 的出口也连接到 SwitchIter
        foreach ($node in $nodesToNextCase) {
            $nodesToIter += $node
        }
    }

    # 12. 连接所有出口节点到 SwitchIter
    foreach ($node in $nodesToIter) {
        Add-Edge -cfg $cfg -from $node.Id -to $iterNode.Id
    }

    # 13. 更新 prevNodeRef 为 SwitchEnd
    $prevNodeRef.Value = $switchEnd
    return $false
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
    # FuncStart/FuncEnd 都是装饰节点，ast = null
    $funcName = $funcAst.Name
    $funcStart = Add-Node -cfg $cfg -type "FuncStart" -text "function $funcName" -line $funcAst.Extent.StartLineNumber -ast $null
    $funcEnd   = Add-Node -cfg $cfg -type "FuncEnd"   -text "End function $funcName"        -line $funcAst.Extent.EndLineNumber   -ast $null

    # 在函数内部构建控制流：类似 ScriptBlockAst，但使用 FuncStart/FuncEnd
    # 如果存在 ParamBlock，则在 FuncStart 后面单独插入一个参数节点
    $prevNode = $funcStart
    if ($null -ne $funcAst.Body -and $null -ne $funcAst.Body.ParamBlock) {
        $paramBlock = $funcAst.Body.ParamBlock

        # 检查 ParamBlock 中是否有嵌套 Pipeline（参数默认值中可能有 pipeline）
        $prevNodeRefForPipeline = [ref]$prevNode
        $paramExpansion = Expand-NestedPipelines -cfg $cfg -ast $paramBlock -prevNodeRef $prevNodeRefForPipeline
        $prevNode = $prevNodeRefForPipeline.Value

        # 将 ParamBlock 文本压缩为单行，避免换行和多余空格导致显示难看
        $rawParamText = $paramBlock.Extent.Text
        if ($null -ne $paramExpansion) {
            # 有嵌套 Pipeline，使用修改后的文本
            $rawParamText = $paramExpansion.ModifiedText
        }
        $singleLineParam = ($rawParamText -split "`r?`n") -join ' '
        $singleLineParam = ($singleLineParam -replace '\s+', ' ').Trim()

        $paramNode = Add-Node -cfg $cfg -type "FuncParams" -text $singleLineParam -line $paramBlock.Extent.StartLineNumber -ast $paramBlock

        if ($null -ne $paramExpansion) {
            # 添加 pipeVar 到 VarsRead
            foreach ($pipeVarEntry in $paramExpansion.PipeVarEntries) {
                Add-VarToNode -node $paramNode -varEntry $pipeVarEntry -accessType "Read"
            }
            # 连接最后一个 Pipeline 节点到 FuncParams
            Add-Edge -cfg $cfg -from $prevNode.Id -to $paramNode.Id -label "Pipeline"
        } else {
            Add-Edge -cfg $cfg -from $funcStart.Id -to $paramNode.Id
        }
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

    # 1. 创建 Try 入口节点（装饰节点，ast = null）
    $tryNode = Add-Node -cfg $cfg -type "Try" -text "Try" -line $tryAst.Extent.StartLineNumber -ast $null
    Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $tryNode.Id
    $prevNodeRef.Value = $tryNode

    # 2. Try-End 汇聚节点（懒创建，只有真的需要汇聚时才创建，避免产生孤立的 Merge 节点）
    $tryEndNode = $null

    # 3. 提前创建 Finally 节点（如果存在，装饰节点，ast = null）
    $finallyNode = $null
    if ($null -ne $tryAst.Finally) {
        $finallyNode = Add-Node -cfg $cfg -type "Finally" -text "Finally" -line $tryAst.Finally.Extent.StartLineNumber -ast $null
    }

    # 4. 提前创建 Catch 链的第一个节点（用于异常跳转）
    $firstCatchNode = $null
    $catchNodes = @()

    # 预定义 $_ 变量条目（Catch 会将异常对象绑定到 $_）
    $underscoreVarEntry = [PSCustomObject]@{ Name = "_"; Scope = [VarScope]::Unspecified }

    foreach ($catchClause in $tryAst.CatchClauses) {
        # 获取 Catch 的异常类型
        $catchTypes = if ($catchClause.CatchTypes.Count -gt 0) {
            ($catchClause.CatchTypes | ForEach-Object { $_.TypeName.Name }) -join ", "
        } else {
            "All"  # 没有指定类型表示捕获所有异常
        }

        # 创建 Catch 节点（保留 ast 用于嵌套判断，但清空自动分析的变量，只保留 $_ 写入）
        $catchNode = Add-Node -cfg $cfg -type "Catch" -text "Catch [$catchTypes]" -line $catchClause.Extent.StartLineNumber -ast $catchClause
        # Catch 节点会将异常对象绑定到 $_，所以 $_ 是写入
        # 清空自动分析的结果（避免把 catch 块内的语句变量也算进来）
        $catchNode.VarsRead = @()
        $catchNode.VarsWritten = @($underscoreVarEntry)

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

        # 判断节点是否在嵌套的内层 try 中
        # 优先使用 OwnerAst（虚拟节点所属的结构），否则使用 Ast
        $isInNestedTry = $false
        $ancestorSource = if ($null -ne $node.OwnerAst) { $node.OwnerAst } else { $node.Ast }
        if ($null -ne $ancestorSource) {
            $ancestor = $ancestorSource.Parent
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
                # 优先使用 OwnerAst（虚拟节点所属的结构），否则使用 Ast
                $fromNodeAncestorSource = if ($null -ne $fromNode.OwnerAst) { $fromNode.OwnerAst } else { $fromNode.Ast }
                if ($null -eq $fromNode -or $null -eq $fromNodeAncestorSource) {
                    continue
                }

                # 1) 如果本身就是 Catch 节点，需要区分：
                #    - 来自"当前 try 自己的最后一个 catch"（11.5 添加的边）：保持为到 End，避免自环；
                #    - 来自"内层 try 的 catch"：应该被当前 try 的 catch 捕获（允许重定向）。
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
                $ancestor = $fromNodeAncestorSource
                while ($null -ne $ancestor) {
                    if ($ancestor -is [System.Management.Automation.Language.TryStatementAst]) {
                        if ($ancestor -eq $tryAst) { $hasThisTryAncestor = $true }
                    }
                    $ancestor = $ancestor.Parent
                }

                if (-not $hasThisTryAncestor) {
                    continue
                }

                # 3) 如果 Uncaught Exception 源自"当前 try 自己的 catch 块内部"的 rethrow，
                #    也不要重定向，让它继续冒泡到更外层的 try 或脚本 End。
                $belongsToThisTryCatch = $false
                $ancestor = $fromNodeAncestorSource.Parent
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
                # 优先使用 OwnerAst（虚拟节点所属的结构），否则使用 Ast
                $fromNodeAncestorSource = if ($null -ne $fromNode.OwnerAst) { $fromNode.OwnerAst } else { $fromNode.Ast }
                if ($null -eq $fromNode -or $null -eq $fromNodeAncestorSource) {
                    continue
                }

                # 1) 判断该节点是否属于当前 try 的 AST 子树内
                $hasThisTryAncestor = $false
                $ancestor = $fromNodeAncestorSource
                while ($null -ne $ancestor) {
                    if ($ancestor -is [System.Management.Automation.Language.TryStatementAst]) {
                        if ($ancestor -eq $tryAst) { $hasThisTryAncestor = $true }
                    }
                    $ancestor = $ancestor.Parent
                }
                if (-not $hasThisTryAncestor) {
                    continue
                }

                # 2) 如果 Uncaught Exception 源自"本 try 自己的 finally 块内部"的 throw，
                #    不要重定向，让它继续冒泡到更外层（由外层的 try-finally 处理）。
                $inThisFinally = $false
                $ancestor = $fromNodeAncestorSource.Parent
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
            $tryEndNode = Add-Node -cfg $cfg -type "Merge" -text "Try-End" -line $tryAst.Extent.EndLineNumber -ast $null
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
        # foreach 现在有专用处理逻辑（ForEachCondition），不再使用此函数
        {$_ -is [System.Management.Automation.Language.DoUntilStatementAst]} {
            "Until ($($loopAst.Condition.Extent.Text))"
        }
        default {
            if ($null -eq $loopAst.Condition) { "AlwaysTrue" }
            else { $($loopAst.Condition.Extent.Text) }
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
        default { "Next Iteration" }
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
    $isForEach = $loopAst -is [System.Management.Automation.Language.ForEachStatementAst]
    $isFor     = $loopAst -is [System.Management.Automation.Language.ForStatementAst]

    # 2. 创建循环开始节点
    $loopStart = Add-Node -cfg $cfg -type "LoopStart" -text (Get-LoopHeaderText $loopAst) -line $loopAst.Extent.StartLineNumber -ast $null
    Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $loopStart.Id
    $currentNode = $loopStart

    # 2.5 for 循环的 Initializer 处理
    #     for ($i = 0; $i -lt $max; $i++) { ... }
    #     => LoopStart -> (ForInit: $i = 0) -> Condition
    if ($isFor -and $null -ne $loopAst.Initializer) {
        $initAst = $loopAst.Initializer
        $initNode = Add-Node -cfg $cfg -type "ForInit" -text $initAst.Extent.Text -line $initAst.Extent.StartLineNumber -ast $initAst
        Add-Edge -cfg $cfg -from $currentNode.Id -to $initNode.Id
        $currentNode = $initNode
    }

    # 2.6 foreach 循环的专用处理
    #     foreach ($item in $collection) { ... }
    #     => LoopStart -> ForEachInit -> ForEachCondition -> ForEachBind -> [循环体] -> ForEachIter -> ForEachCondition
    if ($isForEach) {
        # 生成唯一变量名（使用 GUID 确保不与用户变量冲突）
        $guid = [guid]::NewGuid().ToString("N").Substring(0, 12)
        $collectionVar = "__fe_$guid"
        $indexVar = "__fe_${guid}_idx"

        # 获取原始变量名（去掉 $ 前缀）
        $itemVarText = $loopAst.Variable.Extent.Text      # 如 "$item"
        $itemVarName = $loopAst.Variable.VariablePath.UserPath  # 如 "item"
        $collectionExpr = $loopAst.Condition.Extent.Text  # 如 "$array" 或 "1..10"

        # 预定义内部变量的条目（用于手动设置 VarsRead/VarsWritten）
        $collectionVarEntry = [PSCustomObject]@{ Name = $collectionVar; Scope = [VarScope]::Unspecified }
        $indexVarEntry = [PSCustomObject]@{ Name = $indexVar; Scope = [VarScope]::Unspecified }
        $itemVarEntry = [PSCustomObject]@{ Name = $itemVarName; Scope = [VarScope]::Unspecified }

        # 节点1: LoopStart (装饰节点，已在上面创建，ast = null)

        # 检查集合表达式中是否有嵌套 Pipeline，如果有则先展开
        $prevNodeRefForPipeline = [ref]$currentNode
        $conditionExpansion = Expand-NestedPipelines -cfg $cfg -ast $loopAst.Condition -prevNodeRef $prevNodeRefForPipeline
        $currentNode = $prevNodeRefForPipeline.Value

        # 节点2: ForEachInit (初始化集合和索引)
        # VarsRead: 集合表达式中的变量（由 AST 自动分析）
        # VarsWritten: $__fe_xxx, $__fe_xxx_idx（手动添加）
        if ($null -ne $conditionExpansion) {
            # 有嵌套 Pipeline，使用修改后的文本
            $initText = "`$$collectionVar = " + $conditionExpansion.ModifiedText + "; `$$indexVar = 0"
            $initNode = Add-Node -cfg $cfg -type "ForEachInit" -text $initText -line $loopAst.Condition.Extent.StartLineNumber -ast $loopAst.Condition
            # 添加 pipeVar 到 VarsRead
            foreach ($pipeVarEntry in $conditionExpansion.PipeVarEntries) {
                Add-VarToNode -node $initNode -varEntry $pipeVarEntry -accessType "Read"
            }
            # 连接最后一个 Pipeline 节点到 ForEachInit
            Add-Edge -cfg $cfg -from $currentNode.Id -to $initNode.Id -label "Pipeline"
        } else {
            # 没有嵌套 Pipeline，正常创建
            $initText = "`$$collectionVar = $collectionExpr; `$$indexVar = 0"
            $initNode = Add-Node -cfg $cfg -type "ForEachInit" -text $initText -line $loopAst.Condition.Extent.StartLineNumber -ast $loopAst.Condition
            Add-Edge -cfg $cfg -from $currentNode.Id -to $initNode.Id
        }
        # 手动追加内部变量的写入
        Add-VarToNode -node $initNode -varEntry $collectionVarEntry -accessType "Write"
        Add-VarToNode -node $initNode -varEntry $indexVarEntry -accessType "Write"
        $currentNode = $initNode

        # 节点3: ForEachCondition (判断是否还有元素)
        # VarsRead: $__fe_xxx_idx, $__fe_xxx（手动设置，因为这些是生成的变量）
        # VarsWritten: (无)
        # ast = $null，ownerAst = $loopAst 用于 try/catch 嵌套判断
        $condText = "`$$indexVar -lt `$$collectionVar.Count"
        $conditionNode = Add-Node -cfg $cfg -type "ForEachCondition" -text $condText -line $loopAst.Extent.StartLineNumber -ast $null -ownerAst $loopAst
        # 清空自动分析的结果，手动设置内部变量的读取
        $conditionNode.VarsRead = @($indexVarEntry, $collectionVarEntry)
        $conditionNode.VarsWritten = @()
        Add-Edge -cfg $cfg -from $currentNode.Id -to $conditionNode.Id

        # 节点4: LoopEnd (提前创建，供 break 使用)
        $loopEnd = Add-Node -cfg $cfg -type "LoopEnd" -text "End ForEach" -line $loopAst.Extent.EndLineNumber -ast $null
        Add-Edge -cfg $cfg -from $conditionNode.Id -to $loopEnd.Id -label "No more items"

        # 节点5: ForEachBind (绑定当前元素)
        # VarsRead: $__fe_xxx, $__fe_xxx_idx（手动添加）
        # VarsWritten: $item（由 AST 自动分析）+ 手动确保
        # ast = $null，ownerAst = $loopAst 用于 try/catch 嵌套判断
        $bindText = "$itemVarText = `$$collectionVar[`$$indexVar]"
        $bindNode = Add-Node -cfg $cfg -type "ForEachBind" -text $bindText -line $loopAst.Variable.Extent.StartLineNumber -ast $null -ownerAst $loopAst
        # 手动设置：读取内部变量，写入迭代变量
        $bindNode.VarsRead = @($collectionVarEntry, $indexVarEntry)
        $bindNode.VarsWritten = @($itemVarEntry)
        Add-Edge -cfg $cfg -from $conditionNode.Id -to $bindNode.Id -label "Has next"
        $currentNode = $bindNode

        # 节点6: ForEachIter (递增索引，提前创建供 continue 跳转)
        # VarsRead: $__fe_xxx_idx（读取当前值）
        # VarsWritten: $__fe_xxx_idx（写入新值）
        # ast = $null，ownerAst = $loopAst 用于 try/catch 嵌套判断
        $iterText = "`$$indexVar++"
        $iterNode = Add-Node -cfg $cfg -type "ForEachIter" -text $iterText -line $loopAst.Extent.StartLineNumber -ast $null -ownerAst $loopAst
        # 清空自动分析的结果，手动设置
        $iterNode.VarsRead = @($indexVarEntry)
        $iterNode.VarsWritten = @($indexVarEntry)
        Add-Edge -cfg $cfg -from $iterNode.Id -to $conditionNode.Id

        # 循环上下文：continue 跳到 ForEachIter（和 for 循环一致）
        $loopContext = [PSCustomObject]@{
            LoopEnd = $loopEnd
            LoopContinue = $iterNode
        }

        # 处理循环体
        foreach ($statement in $loopAst.Body.Statements) {
            $hasReturn = Convert-AstNode -cfg $cfg -node $statement -prevNodeRef ([ref]$currentNode) -endNodeRef $endNodeRef -loopContext $loopContext -switchContext $null
            if ($hasReturn) { break }
        }

        # 循环体结束后连到 ForEachIter
        if ($null -ne $currentNode -and $currentNode.Type -notin @("Break", "Continue")) {
            Add-Edge -cfg $cfg -from $currentNode.Id -to $iterNode.Id
        }

        $prevNodeRef.Value = $loopEnd
        return
    }

    # 3. 处理 do-while/do-until 的首次执行（先执行后判断）
    $isDoLoop = $loopType -in "do-while", "do-until"
    if ($isDoLoop) {
        # 3.1 创建循环结束节点（提前创建，供 break 使用）
        $loopEnd = Add-Node -cfg $cfg -type "LoopEnd" -text (Get-LoopEndText $loopAst) -line $loopAst.Extent.EndLineNumber -ast $null

        # 3.1.2 检查条件中是否有嵌套 Pipeline
        $conditionAst = $loopAst.Condition
        $conditionLine = if ($null -ne $loopAst.Condition) { $loopAst.Condition.Extent.StartLineNumber } else { $loopAst.Extent.StartLineNumber }

        # 先创建一个临时节点来收集 pipeline 展开的节点（循环体结束后再连接）
        $conditionExpansion = $null
        $pipelineFirstNode = $null
        if ($null -ne $loopAst.Condition) {
            # 用一个临时的 ref 来展开 pipeline
            $tempPrevNode = $null
            $tempPrevNodeRef = [ref]$tempPrevNode
            $conditionExpansion = Expand-NestedPipelines -cfg $cfg -ast $loopAst.Condition -prevNodeRef $tempPrevNodeRef

            if ($null -ne $conditionExpansion) {
                # 有嵌套 Pipeline，找到第一个 pipeline 节点
                # pipeline 节点是刚刚添加的，从当前节点数往前找
                $pipelineFirstNode = $cfg.Nodes | Where-Object { $_.Type -eq "PipelineElement" } | Select-Object -Last ($conditionExpansion.PipeVarEntries.Count + 1) | Select-Object -First 1
            }
        }

        # 3.1.3 创建条件节点
        if ($null -ne $conditionExpansion) {
            # 有嵌套 Pipeline，使用修改后的文本创建条件节点
            $conditionNode = Add-Node -cfg $cfg -type "Condition" -text $conditionExpansion.ModifiedText -line $conditionLine -ast $conditionAst
            # 添加 pipeVar 到 VarsRead
            foreach ($pipeVarEntry in $conditionExpansion.PipeVarEntries) {
                Add-VarToNode -node $conditionNode -varEntry $pipeVarEntry -accessType "Read"
            }
            # 连接最后一个 Pipeline 节点到条件节点
            $lastPipeNode = $cfg.Nodes | Where-Object { $_.Type -eq "PipelineElement" } | Select-Object -Last 1
            Add-Edge -cfg $cfg -from $lastPipeNode.Id -to $conditionNode.Id -label "Pipeline"
        } else {
            # 没有嵌套 Pipeline，正常创建条件节点
            $conditionNode = Add-Node -cfg $cfg -type "Condition" -text (Get-ConditionLabel $loopAst) -line $conditionLine -ast $conditionAst
        }

        # 3.1.6 创建循环上下文
        # do-while/do-until 的 continue 应该跳转到条件检查（或 pipeline 的第一个节点）
        $conditionEntryNode = if ($null -ne $pipelineFirstNode) { $pipelineFirstNode } else { $conditionNode }
        $loopContext = [PSCustomObject]@{
            LoopEnd = $loopEnd
            LoopContinue = $conditionEntryNode
        }

        # 3.2 先处理循环体
        foreach ($statement in $loopAst.Body.Statements) {
            $hasReturn = Convert-AstNode -cfg $cfg -node $statement -prevNodeRef ([ref]$currentNode) -endNodeRef $endNodeRef -loopContext $loopContext -switchContext $null
            if ($hasReturn) {
                break
            }
        }

        # 3.3 连接循环体到条件（或 pipeline 的第一个节点）
        if ($null -ne $currentNode) {
            $lastNodeType = $currentNode.Type
            if ($lastNodeType -ne "Break" -and $lastNodeType -ne "Continue") {
                Add-Edge -cfg $cfg -from $currentNode.Id -to $conditionEntryNode.Id
            }
        }

        # 3.4 创建两条边：
        #     - 条件满足时继续循环（回到循环开始）
        #     - 条件不满足时退出循环
        Add-Edge -cfg $cfg -from $conditionNode.Id -to $loopStart.Id -label (Get-LoopBackLabel $loopAst)
        Add-Edge -cfg $cfg -from $conditionNode.Id -to $loopEnd.Id -label (Get-ExitLabel $loopAst)

        $prevNodeRef.Value = $loopEnd
        return
    }

    # 4. 添加条件节点
    #    对 foreach，Condition 节点负责"Has next item?" 判断以及隐含的迭代变量绑定，
    #    因此将整个 ForEachStatementAst 作为 Ast，便于变量读写分析。
    $conditionAst = if ($isForEach) { $loopAst } else { $loopAst.Condition }
    $conditionLine = if ($null -ne $loopAst.Condition) { $loopAst.Condition.Extent.StartLineNumber } else { $loopAst.Extent.StartLineNumber }

    # 4.1 检查条件中是否有嵌套 Pipeline（for/while 循环）
    # $conditionEntryNode 记录条件求值的入口节点（可能是 pipeline 的第一个节点或条件节点本身）
    $conditionEntryNode = $null
    if ($null -ne $loopAst.Condition -and -not $isForEach) {
        $nodeBeforePipeline = $currentNode  # 记录 pipeline 展开前的节点
        $prevNodeRefForPipeline = [ref]$currentNode
        $conditionExpansion = Expand-NestedPipelines -cfg $cfg -ast $loopAst.Condition -prevNodeRef $prevNodeRefForPipeline
        $currentNode = $prevNodeRefForPipeline.Value

        if ($null -ne $conditionExpansion) {
            # 有嵌套 Pipeline，使用修改后的文本创建条件节点
            $conditionNode = Add-Node -cfg $cfg -type "Condition" -text $conditionExpansion.ModifiedText -line $conditionLine -ast $conditionAst
            # 添加 pipeVar 到 VarsRead
            foreach ($pipeVarEntry in $conditionExpansion.PipeVarEntries) {
                Add-VarToNode -node $conditionNode -varEntry $pipeVarEntry -accessType "Read"
            }
            # 连接最后一个 Pipeline 节点到条件节点
            Add-Edge -cfg $cfg -from $currentNode.Id -to $conditionNode.Id -label "Pipeline"
            # 找到 pipeline 展开后的第一个节点作为条件入口
            $pipelineEdge = $cfg.Edges | Where-Object { $_.From -eq $nodeBeforePipeline.Id } | Select-Object -Last 1
            if ($pipelineEdge) {
                $conditionEntryNode = $cfg.Nodes | Where-Object { $_.Id -eq $pipelineEdge.To }
            }
        } else {
            # 没有嵌套 Pipeline，正常创建条件节点
            $conditionNode = Add-Node -cfg $cfg -type "Condition" -text (Get-ConditionLabel $loopAst) -line $conditionLine -ast $conditionAst
            Add-Edge -cfg $cfg -from $currentNode.Id -to $conditionNode.Id
            $conditionEntryNode = $conditionNode
        }
    } else {
        # foreach 或无条件的情况
        $conditionNode = Add-Node -cfg $cfg -type "Condition" -text (Get-ConditionLabel $loopAst) -line $conditionLine -ast $conditionAst
        Add-Edge -cfg $cfg -from $currentNode.Id -to $conditionNode.Id
        $conditionEntryNode = $conditionNode
    }
    $currentNode = $conditionNode

    # 4.5 创建循环结束节点（提前创建，供 break 使用）
    #     LoopEnd 仅为结构示意节点，不参与实际执行，因此不需要携带完整循环 AST。
    $loopEnd = Add-Node -cfg $cfg -type "LoopEnd" -text (Get-LoopEndText $loopAst) -line $loopAst.Extent.EndLineNumber -ast $null

    # 4.6 for 循环的 Iterator 节点（提前创建，供 continue 跳转使用）
    #     for 循环的 continue 应该跳到 Iterator 而不是 Condition
    $iteratorNode = $null
    if ($isFor -and $null -ne $loopAst.Iterator) {
        $iterAst = $loopAst.Iterator
        $iteratorNode = Add-Node -cfg $cfg -type "ForIter" -text $iterAst.Extent.Text -line $iterAst.Extent.StartLineNumber -ast $iterAst
    }

    # 4.7 创建循环上下文
    #     - for 循环的 continue 跳到 Iterator 节点（如果存在），否则跳到 Condition
    #     - 其他循环的 continue 跳到 Condition 节点
    $loopContext = [PSCustomObject]@{
        LoopEnd = $loopEnd
        LoopContinue = if ($null -ne $iteratorNode) { $iteratorNode } else { $conditionNode }
    }

    # 5. 处理非 do-xx 的循环体（先判断后执行）
    foreach ($statement in $loopAst.Body.Statements) {
        $hasReturn = Convert-AstNode -cfg $cfg -node $statement -prevNodeRef ([ref]$currentNode) -endNodeRef $endNodeRef -loopContext $loopContext -switchContext $null
        if ($hasReturn) {
            break
        }
    }
    # 5.5 连接循环体到下一步
    if ($null -ne $currentNode) {
        $lastNodeType = $currentNode.Type
        if ($lastNodeType -ne "Break" -and $lastNodeType -ne "Continue") {
            if ($null -ne $iteratorNode) {
                # for 循环：body -> Iterator -> Condition
                Add-Edge -cfg $cfg -from $currentNode.Id -to $iteratorNode.Id
            } else {
                # 其他循环：body -> Condition（或条件入口节点）
                Add-Edge -cfg $cfg -from $currentNode.Id -to $conditionEntryNode.Id -label "Next"
            }
        }
    }

    # 5.6 for 循环：Iterator -> 条件入口节点（可能是 pipeline 的第一个节点）
    if ($null -ne $iteratorNode) {
        Add-Edge -cfg $cfg -from $iteratorNode.Id -to $conditionEntryNode.Id
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

        # 4. 连接最后一个节点到 End 节点（如果还没有被 Return/Break/Continue/Exit 连接）
        # 如果最后一个节点是 Return/Break/Continue/Exit/Throw 节点，它已经连接到 End，不需要再创建边
        if ($null -ne $prevNodeRef.Value -and $prevNodeRef.Value.Id -ne $endNode.Id) {
            $lastNodeType = $prevNodeRef.Value.Type
            if ($lastNodeType -ne "Return" -and $lastNodeType -ne "Break" -and $lastNodeType -ne "Continue" -and $lastNodeType -ne "Throw" -and $lastNodeType -ne "Exit") {
                Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $endNode.Id
            }
        }
        $prevNodeRef.Value = $endNode
    }
    # 二、如果是ReturnStatementAst，创建 Return 节点
    elseif ($node -is [System.Management.Automation.Language.ReturnStatementAst]) {
        # 检查 return 语句中是否有嵌套 Pipeline（如 return Get-Service | Where-Object { ... }）
        $returnExpansion = $null
        if ($null -ne $node.Pipeline) {
            $returnExpansion = Expand-NestedPipelines -cfg $cfg -ast $node.Pipeline -prevNodeRef $prevNodeRef
        }

        if ($null -ne $returnExpansion) {
            # 有嵌套 Pipeline，使用修改后的文本创建 Return 节点
            $modifiedReturnText = "return " + $returnExpansion.ModifiedText
            $returnNode = Add-Node -cfg $cfg -type "Return" -text $modifiedReturnText -line $node.Extent.StartLineNumber -ast $node
            # 添加 pipeVar 到 VarsRead
            foreach ($pipeVarEntry in $returnExpansion.PipeVarEntries) {
                Add-VarToNode -node $returnNode -varEntry $pipeVarEntry -accessType "Read"
            }
            # 连接最后一个 Pipeline 节点到 Return 节点
            if ($null -ne $prevNodeRef.Value) {
                Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $returnNode.Id -label "Pipeline"
            }
        } else {
            # 没有嵌套 Pipeline，正常创建 Return 节点
            $returnNode = Add-Node -cfg $cfg -type "Return" -text $node.Extent.Text -line $node.Extent.StartLineNumber -ast $node
            # 连接到上一个节点
            if ($null -ne $prevNodeRef.Value) {
                Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $returnNode.Id
            }
        }

        # Return 一般终止当前脚本块/函数，但如果它位于"带 finally 的 try"中，
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
        # 顶层：函数定义本身作为一个顺序节点出现（装饰节点，ast = null）
        # 函数定义不执行代码，只是声明函数，所以不需要变量分析
        $funcName = $node.Name
        $defText = "function $funcName"
        $funcDefNode = Add-Node -cfg $cfg -type "FunctionDef" -text $defText -line $node.Extent.StartLineNumber -ast $null
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
    # 四点六、如果是 AssignmentStatementAst 且右侧是多元素 PipelineAst，拆分处理
    elseif ($node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $node.Right -is [System.Management.Automation.Language.PipelineAst] -and
            $node.Right.PipelineElements.Count -gt 1) {

        $leftText = $node.Left.Extent.Text  # 如 "$result"
        $operator = $node.Operator          # 如 "Equals"
        $operatorText = switch ($operator) {
            "Equals"           { "=" }
            "PlusEquals"       { "+=" }
            "MinusEquals"      { "-=" }
            "MultiplyEquals"   { "*=" }
            "DivideEquals"     { "/=" }
            "RemainderEquals"  { "%=" }
            default            { "=" }
        }

        $elements = $node.Right.PipelineElements
        $lastIndex = $elements.Count - 1
        $underscoreEntry = [PSCustomObject]@{ Name = "_"; Scope = [VarScope]::Unspecified }

        for ($i = 0; $i -lt $elements.Count; $i++) {
            $element = $elements[$i]

            # 构建节点文本
            if ($i -eq 0) {
                # 首元素：原样
                $nodeText = $element.Extent.Text
            } elseif ($i -eq $lastIndex) {
                # 末元素：加上赋值和管道前缀
                $nodeText = "$leftText $operatorText `$_ | " + $element.Extent.Text
            } else {
                # 中间元素：只加管道前缀
                $nodeText = "`$_ | " + $element.Extent.Text
            }

            # 末元素使用整个赋值语句的 AST（用于变量分析），其他用元素自己的 AST
            $nodeAst = if ($i -eq $lastIndex) { $node } else { $element }
            $pipeNode = Add-Node -cfg $cfg -type "PipelineElement" -text $nodeText -line $element.Extent.StartLineNumber -ast $nodeAst

            # 变量流处理
            if ($i -eq 0) {
                # 首元素：写入 $_
                Add-VarToNode -node $pipeNode -varEntry $underscoreEntry -accessType "Write"
            } elseif ($i -eq $lastIndex) {
                # 末元素：读取 $_（赋值目标变量由 AST 自动分析）
                Add-VarToNode -node $pipeNode -varEntry $underscoreEntry -accessType "Read"
            } else {
                # 中间元素：读取 + 写入 $_
                Add-VarToNode -node $pipeNode -varEntry $underscoreEntry -accessType "Both"
            }

            # 连接边
            if ($null -ne $prevNodeRef.Value) {
                if ($i -gt 0) {
                    Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $pipeNode.Id -label "Pipeline"
                } else {
                    Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $pipeNode.Id
                }
            }
            $prevNodeRef.Value = $pipeNode
        }
        return $false
    }
    # 五、如果是 PipelineAst，拆分为多个节点
    elseif ($node -is [System.Management.Automation.Language.PipelineAst]) {
        $elements = $node.PipelineElements
        $lastIndex = $elements.Count - 1
        $underscoreEntry = [PSCustomObject]@{ Name = "_"; Scope = [VarScope]::Unspecified }

        for ($i = 0; $i -lt $elements.Count; $i++) {
            $element = $elements[$i]

            # 检查当前元素内部是否有嵌套的多元素 Pipeline（如子表达式中的 pipeline）
            $elementExpansion = Expand-NestedPipelines -cfg $cfg -ast $element -prevNodeRef $prevNodeRef

            if ($null -ne $elementExpansion) {
                # 有嵌套 Pipeline，使用修改后的文本
                $baseText = $elementExpansion.ModifiedText
                $nodeText = if ($i -gt 0) { "`$_ | " + $baseText } else { $baseText }
                $pipeNode = Add-Node -cfg $cfg -type "PipelineElement" -text $nodeText -line $element.Extent.StartLineNumber -ast $element

                # 添加嵌套 Pipeline 的变量到 VarsRead
                foreach ($pipeVarEntry in $elementExpansion.PipeVarEntries) {
                    Add-VarToNode -node $pipeNode -varEntry $pipeVarEntry -accessType "Read"
                }

                # 连接最后一个嵌套 Pipeline 节点到当前节点
                if ($null -ne $prevNodeRef.Value) {
                    Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $pipeNode.Id -label "Pipeline"
                }
            } else {
                # 没有嵌套 Pipeline，正常处理
                $nodeText = if ($i -gt 0) { "`$_ | " + $element.Extent.Text } else { $element.Extent.Text }
                $pipeNode = Add-Node -cfg $cfg -type "PipelineElement" -text $nodeText -line $element.Extent.StartLineNumber -ast $element

                # 连接边
                if ($null -ne $prevNodeRef.Value) {
                    if ($i -gt 0) {
                        # Pipeline 元素之间用 "Pipeline" 标签
                        Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $pipeNode.Id -label "Pipeline"
                    } else {
                        # 首元素与前一个节点的普通连接
                        Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $pipeNode.Id
                    }
                }
            }

            # 变量流处理：
            # - 首元素：只写入 $_ (产生管道输出)
            # - 中间元素：读取 + 写入 $_ (接收输入并产生输出)
            # - 末元素：只读取 $_ (接收输入，不再传递)
            if ($i -eq 0) {
                # 首元素：写入 $_
                if ($elements.Count -gt 1) {
                    Add-VarToNode -node $pipeNode -varEntry $underscoreEntry -accessType "Write"
                }
            } elseif ($i -eq $lastIndex) {
                # 末元素：只读取 $_
                Add-VarToNode -node $pipeNode -varEntry $underscoreEntry -accessType "Read"
            } else {
                # 中间元素：读取 + 写入 $_
                Add-VarToNode -node $pipeNode -varEntry $underscoreEntry -accessType "Both"
            }

            $prevNodeRef.Value = $pipeNode
        }
        return $false
    }
    # 六、其余节点（包含嵌套 Pipeline 的通用处理）
    else {
        # 检测节点内是否有嵌套的多元素 Pipeline
        $nestedPipelines = Get-AllNestedPipelines -ast $node

        if ($nestedPipelines.Count -gt 0) {
            # 按位置倒序排列（从后往前处理，避免文本替换时位置偏移）
            $sortedPipelines = $nestedPipelines | Sort-Object { $_.Extent.StartOffset } -Descending

            # 记录所有 Pipeline 的变量名和替换信息
            $replacements = @()
            $allPipelineNodes = @()

            foreach ($pipeline in $sortedPipelines) {
                $guid = [guid]::NewGuid().ToString("N").Substring(0, 8)
                $pipeVar = "__pipe_$guid"
                $pipeVarEntry = [PSCustomObject]@{ Name = $pipeVar; Scope = [VarScope]::Unspecified }

                $elements = $pipeline.PipelineElements
                $lastIndex = $elements.Count - 1

                # 拆分 Pipeline 的前 N-1 个元素为独立节点
                for ($i = 0; $i -lt $elements.Count - 1; $i++) {
                    $element = $elements[$i]

                    # 构建节点文本
                    if ($i -eq 0) {
                        $nodeText = $element.Extent.Text
                    } else {
                        $nodeText = "`$$pipeVar | " + $element.Extent.Text
                    }

                    $pipeNode = Add-Node -cfg $cfg -type "PipelineElement" -text $nodeText -line $element.Extent.StartLineNumber -ast $element

                    # 变量流处理
                    if ($i -eq 0) {
                        # 首元素：写入 $pipeVar
                        Add-VarToNode -node $pipeNode -varEntry $pipeVarEntry -accessType "Write"
                    } else {
                        # 中间元素：读取 + 写入 $pipeVar
                        Add-VarToNode -node $pipeNode -varEntry $pipeVarEntry -accessType "Both"
                    }

                    $allPipelineNodes += @{
                        Node = $pipeNode
                        PipeVar = $pipeVar
                        Index = $i
                    }
                }

                # 记录替换信息：将整个 Pipeline 替换为 "$pipeVar | 最后一个元素"
                $lastElement = $elements[$lastIndex]
                $originalText = $pipeline.Extent.Text
                $replacementText = "`$$pipeVar | " + $lastElement.Extent.Text

                $replacements += @{
                    Original = $originalText
                    Replacement = $replacementText
                    PipeVar = $pipeVar
                    PipeVarEntry = $pipeVarEntry
                }
            }

            # 连接所有 Pipeline 元素节点
            foreach ($pipeInfo in $allPipelineNodes) {
                if ($null -ne $prevNodeRef.Value) {
                    if ($pipeInfo.Index -gt 0) {
                        Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $pipeInfo.Node.Id -label "Pipeline"
                    } else {
                        Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $pipeInfo.Node.Id
                    }
                }
                $prevNodeRef.Value = $pipeInfo.Node
            }

            # 修改原始节点的文本
            $modifiedText = $node.Extent.Text
            foreach ($r in $replacements) {
                $modifiedText = $modifiedText.Replace($r.Original, $r.Replacement)
            }

            # 创建最终节点
            $finalNode = Add-Node -cfg $cfg -type $node.GetType().Name -text $modifiedText -line $node.Extent.StartLineNumber -ast $node

            # 为最终节点添加所有 pipeVar 到 VarsRead
            foreach ($r in $replacements) {
                Add-VarToNode -node $finalNode -varEntry $r.PipeVarEntry -accessType "Read"
            }

            # 连接最后一个 Pipeline 节点到最终节点
            if ($null -ne $prevNodeRef.Value) {
                Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $finalNode.Id -label "Pipeline"
            }
            $prevNodeRef.Value = $finalNode
            return $false
        }

        # 没有嵌套 Pipeline，直接创建节点
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
        # 转义反斜杠和引号
        $escaped = $cleaned.Replace('\', '\\').Replace('"', '\"')
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
            {$_ -in "Condition", "If", "ForEachCondition"}    { "diamond" }
            {$_ -in "Merge"}                                  { "point" }
            default                                           { "box" }
        }
        $label = "Id $($node.Id)\l$($node.Type)\l$(Format-DotLabel $node.Text)"
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
