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
        $endNodeRef = $null
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
            $hasReturn = Convert-AstNode -cfg $cfg -node $statement -prevNodeRef $prevNodeRef -endNodeRef $endNodeRef
            # 如果遇到 return，停止处理后续语句
            if ($hasReturn) {
                $branchHasReturn = $true
                break
            }
        }
        # 只有当分支不以 return 结束时，才添加到分支结束节点集合
        if (-not $branchHasReturn) {
            $branchEndNodes += $prevNodeRef.Value
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
            $hasReturn = Convert-AstNode -cfg $cfg -node $statement -prevNodeRef $prevNodeRef -endNodeRef $endNodeRef
            # 如果遇到 return，停止处理后续语句
            if ($hasReturn) {
                $elseHasReturn = $true
                break
            }
        }
        # 只有当 Else 分支不以 return 结束时，才添加到分支结束节点集合
        if (-not $elseHasReturn) {
            $branchEndNodes += $prevNodeRef.Value
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

    # 5. 如果所有分支都以 return 结束（branchEndNodes 为空），不需要创建 merge 节点
    if ($branchEndNodes.Count -eq 0 -and $null -ne $endNodeRef) {
        $endNode = if ($endNodeRef -is [ref]) { $endNodeRef.Value } else { $endNodeRef }
        if ($null -ne $endNode) {
            # 所有 return 已经直接连接到 End，不需要 merge 节点
            # 将 prevNodeRef 指向 End，这样后续语句不会被处理
            $prevNodeRef.Value = $endNode
            return $true  # 返回 true 表示所有分支都有 return
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

        # 3.2 先处理循环体
        foreach ($statement in $loopAst.Body.Statements) {
            $hasReturn = Convert-AstNode -cfg $cfg -node $statement -prevNodeRef ([ref]$currentNode) -endNodeRef $endNodeRef
            # 如果遇到 return，停止处理后续语句
            if ($hasReturn) {
                break
            }
        }

        # 3.3 连接循环体到条件节点
        Add-Edge -cfg $cfg -from $currentNode.Id -to $conditionNode.Id

        # 3.4 创建两条边：
        #     - 条件满足时继续循环（回到循环开始）
        #     - 条件不满足时退出循环
        Add-Edge -cfg $cfg -from $conditionNode.Id -to $loopStart.Id -label (Get-LoopBackLabel $loopAst)

        # 3.5 创建循环结束节点
        $loopEnd = Add-Node -cfg $cfg -type "LoopEnd" -text (Get-LoopEndText $loopAst) -line $loopAst.Extent.EndLineNumber -ast $loopAst
        Add-Edge -cfg $cfg -from $conditionNode.Id -to $loopEnd.Id -label (Get-ExitLabel $loopAst)

        $prevNodeRef.Value = $loopEnd
        return  # 提前返回，避免执行通用逻辑
    }

    # 4. 添加条件节点
    $conditionNode = Add-Node -cfg $cfg -type "Condition" -text (Get-ConditionLabel $loopAst) -line $loopAst.Condition.Extent.StartLineNumber -ast $loopAst.Condition
    Add-Edge -cfg $cfg -from $currentNode.Id -to $conditionNode.Id
    $currentNode = $conditionNode

    # 5. 处理非 do-xx 的循环体（先判断后执行）
    if (-not $isDoLoop) {
        foreach ($statement in $loopAst.Body.Statements) {
            $hasReturn = Convert-AstNode -cfg $cfg -node $statement -prevNodeRef ([ref]$currentNode) -endNodeRef $endNodeRef
            # 如果遇到 return，停止处理后续语句
            if ($hasReturn) {
                break
            }
        }
        # 添加循环回边
        Add-Edge -cfg $cfg -from $currentNode.Id -to $conditionNode.Id -label "Next"
    }

    # 6. 创建循环结束节点
    $loopEnd = Add-Node -cfg $cfg -type "LoopEnd" -text (Get-LoopEndText $loopAst) -line $loopAst.Extent.EndLineNumber -ast $loopAst
    Add-Edge -cfg $cfg -from $conditionNode.Id -to $loopEnd.Id -label (Get-ExitLabel $loopAst)
    $prevNodeRef.Value = $loopEnd
}

function Convert-AstNode {
    param(
        $cfg,
        $node,
        [ref]$prevNodeRef, # 用于跨递归维护上一个节点
        $endNodeRef = $null # 可选的 End 节点引用（ref 类型），用于 Return 语句连接
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
                        $hasReturn = Convert-AstNode -cfg $cfg -node $statement -prevNodeRef $prevNodeRef -endNodeRef $endNodeRef
                        # 如果遇到 return，停止处理后续语句
                        if ($hasReturn) {
                            break
                        }
                    }
                }
            }
        }

        # 4. 连接最后一个节点到 End 节点（如果还没有被 Return 连接）
        # 如果最后一个节点是 Return 节点，它已经连接到 End，不需要再创建边
        if ($null -ne $prevNodeRef.Value -and $prevNodeRef.Value.Id -ne $endNode.Id -and $prevNodeRef.Value.Type -ne "Return") {
            Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $endNode.Id
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
    # 三、如果是IfStatementAst，创建分支
    elseif ($node -is [System.Management.Automation.Language.IfStatementAst]) {
        $allBranchesReturn = Convert-IfAstNode -cfg $cfg -ifAst $node -prevNodeRef $prevNodeRef -endNodeRef $endNodeRef
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