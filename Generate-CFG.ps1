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

# 辅助函数：检测动态执行结构（iex / [ScriptBlock]::Create / NewScriptBlock）
# 返回值：$null 或 @{ Type = "IEX"|"ScriptBlockCreate"|"NewScriptBlock"; ArgAst = <Ast> }
function Get-DynamicInvokeInfo {
    param(
        [Parameter(Mandatory = $true)]
        $ast
    )

    if ($null -eq $ast) { return $null }

    # 收集所有匹配的动态执行结构
    $results = @()

    # 1. 检测 Invoke-Expression / iex
    # 查找所有 CommandAst
    $commandAsts = @($ast.FindAll({
        param($n)
        $n -is [System.Management.Automation.Language.CommandAst]
    }, $true))

    foreach ($cmdAst in $commandAsts) {
        $cmdName = $cmdAst.GetCommandName()
        if ($cmdName -in @('Invoke-Expression', 'iex')) {
            # 获取第一个参数（排除命令名本身）
            $argAst = $null
            if ($cmdAst.CommandElements.Count -gt 1) {
                $argAst = $cmdAst.CommandElements[1]
            }
            $results += @{
                Type   = "IEX"
                ArgAst = $argAst
            }
        }
    }

    # 2. 检测 [ScriptBlock]::Create() / [System.Management.Automation.ScriptBlock]::Create()
    # 查找所有 InvokeMemberExpressionAst（静态方法调用）
    $invokeMemberAsts = @($ast.FindAll({
        param($n)
        $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst]
    }, $true))

    foreach ($invokeAst in $invokeMemberAsts) {
        # 检查是否是静态调用（Static = $true）
        if (-not $invokeAst.Static) { continue }

        # 检查方法名是否是 Create
        $memberName = $invokeAst.Member
        if ($memberName -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
            $memberName = $memberName.Value
        }
        if ($memberName -ne 'Create') { continue }

        # 检查类型是否是 ScriptBlock
        $typeExpr = $invokeAst.Expression
        if ($typeExpr -is [System.Management.Automation.Language.TypeExpressionAst]) {
            $typeName = $typeExpr.TypeName.FullName
            if ($typeName -in @('ScriptBlock', 'System.Management.Automation.ScriptBlock')) {
                # 获取第一个参数
                $argAst = $null
                if ($invokeAst.Arguments.Count -gt 0) {
                    $argAst = $invokeAst.Arguments[0]
                }
                $results += @{
                    Type   = "ScriptBlockCreate"
                    ArgAst = $argAst
                }
            }
        }
    }

    # 3. 检测 $ExecutionContext.InvokeCommand.NewScriptBlock()
    # 查找所有实例方法调用
    foreach ($invokeAst in $invokeMemberAsts) {
        # 跳过静态调用
        if ($invokeAst.Static) { continue }

        # 检查方法名是否是 NewScriptBlock
        $memberName = $invokeAst.Member
        if ($memberName -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
            $memberName = $memberName.Value
        }
        if ($memberName -ne 'NewScriptBlock') { continue }

        # 获取第一个参数
        $argAst = $null
        if ($invokeAst.Arguments.Count -gt 0) {
            $argAst = $invokeAst.Arguments[0]
        }
        $results += @{
            Type   = "NewScriptBlock"
            ArgAst = $argAst
        }
    }

    # 返回结果
    if ($results.Count -eq 0) {
        return $null
    }
    elseif ($results.Count -eq 1) {
        return $results[0]
    }
    else {
        # 多个动态执行结构，返回数组
        return $results
    }
}

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
        Id            = $cfg.Nodes.Count + 1
        Type          = $type
        Text          = $text
        Line          = $line
        Ast           = $ast
        OwnerAst      = $ownerAst  # 虚拟节点所属的结构（如 switch/foreach/for 的 AST）
        VarsRead      = @()  # 当前节点读取的变量列表（元素为 { Name; Scope }）
        VarsWritten   = @()  # 当前节点写入的变量列表（元素为 { Name; Scope }）
        DynamicInvoke = $null  # 动态执行标记：@{ Type = "IEX"|"ScriptBlockCreate"|"NewScriptBlock"; ArgAst = <Ast> }
        Invokes       = @{ Functions = @(); ScriptBlocks = @() }  # 调用的函数和脚本块
        Resolvables   = @()  # 可还原表达式列表
        AliasesUsed   = @()  # 使用的别名列表 @{ Name; Target; Ast }
    }

    # 如果提供了 AST，分析该节点中的变量读写情况
    if ($null -ne $ast) {
        Populate-NodeVariableUsage -node $node
        # 检测动态执行结构
        $node.DynamicInvoke = Get-DynamicInvokeInfo -ast $ast
        # 分析函数调用和脚本块引用
        Populate-NodeInvokes -node $node -cfg $cfg
        # 分析可还原表达式
        Populate-NodeResolvables -node $node

        # 提取别名定义（Set-Alias/New-Alias）
        $commandAsts = @($ast.FindAll({
            param($n)
            $n -is [System.Management.Automation.Language.CommandAst]
        }, $true))
        foreach ($cmdAst in $commandAsts) {
            $aliasDef = Get-AliasDefinitionFromCommand -cmdAst $cmdAst
            if ($null -ne $aliasDef) {
                $cfg.DefinedAliases[$aliasDef.Name] = $aliasDef.Value
            }
        }

        # 分析别名使用（需要在提取别名定义之后，但当前节点的别名定义在后续节点才生效）
        # 注意：当前节点定义的别名，当前节点不会使用，所以顺序是对的
        Populate-NodeAliasUsage -node $node -cfg $cfg
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

    # 如果是 _block_ 变量，同步更新 Invokes.ScriptBlocks
    if ($varEntry.Name -match '^_block_[a-f0-9]{8}$') {
        $existsInInvokes = $node.Invokes.ScriptBlocks -contains $varEntry.Name
        if (-not $existsInInvokes) {
            $node.Invokes.ScriptBlocks = @($node.Invokes.ScriptBlocks) + @($varEntry.Name)
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

    # 查找变量时，需要排除 ScriptBlockExpressionAst 内部的变量
    # 因为 ScriptBlock 只是定义，内部变量在定义时不会被读写
    $varAsts = $node.Ast.FindAll({
            param($n)
            # 跳过 ScriptBlockExpressionAst 及其子节点
            if ($n -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
                return $false
            }
            $n -is [System.Management.Automation.Language.VariableExpressionAst]
        }, $true)

    # 过滤掉位于 ScriptBlockExpressionAst 内部的变量
    $varAsts = @($varAsts | Where-Object {
        $ancestor = $_.Parent
        while ($null -ne $ancestor -and $ancestor -ne $node.Ast) {
            if ($ancestor -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
                return $false
            }
            $ancestor = $ancestor.Parent
        }
        return $true
    })

    foreach ($v in $varAsts) {
        $kind = Get-VariableAccessKind -VarAst $v
        if (-not $kind) { continue }

        # 根据 VariablePath 上的标志推断作用域提示（使用统一的 VarScope 枚举）
        $scope = [VarScope]::Unspecified
        if     ($v.VariablePath.IsGlobal)  { $scope = [VarScope]::Global }
        elseif ($v.VariablePath.IsScript)  { $scope = [VarScope]::Script }
        elseif ($v.VariablePath.IsLocal)   { $scope = [VarScope]::Local }
        elseif ($v.VariablePath.IsPrivate) { $scope = [VarScope]::Private }

        # 获取纯变量名（去掉作用域前缀）
        # UserPath 包含前缀（如 "global:x"），需要去掉
        $name = $v.VariablePath.UserPath
        if ($scope -ne [VarScope]::Unspecified -and $name -match ':') {
            $name = $name -replace '^[^:]+:', ''
        }
        if ([string]::IsNullOrWhiteSpace($name)) { continue }

        # 为读取的变量添加位置信息
        $readEntry = [PSCustomObject]@{
            Name        = $name
            Scope       = $scope
            StartOffset = $v.Extent.StartOffset
            EndOffset   = $v.Extent.EndOffset
            Text        = $v.Extent.Text
        }

        # 写入的变量保持原有格式（只需知道哪些变量被写）
        $writeEntry = [PSCustomObject]@{
            Name  = $name
            Scope = $scope
        }

        switch ($kind) {
            "Read" {
                $reads += $readEntry
            }
            "Write" {
                $writes += $writeEntry
            }
            "ReadWrite" {
                $reads  += $readEntry
                $writes += $writeEntry
            }
        }
    }

    # VarsRead 不去重，保留每个变量引用的位置信息
    $node.VarsRead = @($reads)
    # VarsWritten 保持去重（写入只需要知道哪些变量被写）
    $node.VarsWritten = @(
        $writes |
            Group-Object Name, Scope |
            ForEach-Object { $_.Group[0] }
    )
}

# 辅助函数：分析节点中的函数调用和脚本块引用
function Populate-NodeInvokes {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$node,
        [Parameter(Mandatory = $true)]
        [hashtable]$cfg
    )

    $node.Invokes = @{
        Functions    = @()
        ScriptBlocks = @()
    }

    if ($null -eq $node.Ast) { return }

    # 1. 检测函数调用（查找 CommandAst）
    $commandAsts = @($node.Ast.FindAll({
        param($n)
        # 跳过 ScriptBlockExpressionAst 内部
        if ($n -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
            return $false
        }
        $n -is [System.Management.Automation.Language.CommandAst]
    }, $true))

    # 过滤掉嵌套在 ScriptBlockExpressionAst 内部的
    $commandAsts = @($commandAsts | Where-Object {
        $ancestor = $_.Parent
        while ($null -ne $ancestor -and $ancestor -ne $node.Ast) {
            if ($ancestor -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
                return $false
            }
            $ancestor = $ancestor.Parent
        }
        return $true
    })

    $funcCalls = @()
    foreach ($cmdAst in $commandAsts) {
        $cmdName = $cmdAst.GetCommandName()
        if (-not [string]::IsNullOrWhiteSpace($cmdName)) {
            if ($cfg.DefinedFunctions.Contains($cmdName)) {
                $funcCalls += $cmdName
            }
        }
    }
    $node.Invokes.Functions = @($funcCalls | Select-Object -Unique)

    # 2. 检测脚本块引用（从 VarsRead 和 VarsWritten 中筛选 _block_ 变量）
    $allVars = @($node.VarsRead) + @($node.VarsWritten)
    $blockVars = @($allVars | Where-Object {
        $_.Name -match '^_block_[a-f0-9]{8}$'
    } | ForEach-Object { $_.Name })
    $node.Invokes.ScriptBlocks = @($blockVars | Select-Object -Unique)
}

# 辅助函数：分析节点中的可还原表达式
function Populate-NodeResolvables {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$node
    )

    $node.Resolvables = @()
    if ($null -eq $node.Ast) { return }

    # 目标类型集合
    # 高优先级：Binary, Unary, MemberInvoke, Convert, ExpandableString, Index
    # 中优先级：SubExpression, Member, Paren, Command
    $targetTypes = @(
        # 原有类型
        [System.Management.Automation.Language.BinaryExpressionAst],
        [System.Management.Automation.Language.UnaryExpressionAst],
        [System.Management.Automation.Language.InvokeMemberExpressionAst],
        # 高优先级新增
        [System.Management.Automation.Language.ConvertExpressionAst],
        [System.Management.Automation.Language.ExpandableStringExpressionAst],
        [System.Management.Automation.Language.IndexExpressionAst],
        # 中优先级新增
        [System.Management.Automation.Language.SubExpressionAst],
        [System.Management.Automation.Language.MemberExpressionAst],
        [System.Management.Automation.Language.ParenExpressionAst],
        [System.Management.Automation.Language.CommandAst]
    )

    # 查找所有目标表达式（排除 ScriptBlock 内部）
    $allExprs = @($node.Ast.FindAll({
        param($n)
        if ($n -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) { return $false }
        # 原有类型
        ($n -is [System.Management.Automation.Language.BinaryExpressionAst]) -or
        ($n -is [System.Management.Automation.Language.UnaryExpressionAst]) -or
        ($n -is [System.Management.Automation.Language.InvokeMemberExpressionAst]) -or
        # 高优先级新增
        ($n -is [System.Management.Automation.Language.ConvertExpressionAst]) -or
        ($n -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) -or
        ($n -is [System.Management.Automation.Language.IndexExpressionAst]) -or
        # 中优先级新增
        ($n -is [System.Management.Automation.Language.SubExpressionAst]) -or
        ($n -is [System.Management.Automation.Language.MemberExpressionAst]) -or
        ($n -is [System.Management.Automation.Language.ParenExpressionAst]) -or
        ($n -is [System.Management.Automation.Language.CommandAst])
    }, $true))

    # 过滤掉嵌套在 ScriptBlockExpressionAst 内部的
    $allExprs = @($allExprs | Where-Object {
        $ancestor = $_.Parent
        while ($null -ne $ancestor -and $ancestor -ne $node.Ast) {
            if ($ancestor -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
                return $false
            }
            $ancestor = $ancestor.Parent
        }
        return $true
    })

    # 注意：不再过滤"只保留最外层"，记录所有层级的可还原表达式
    # 后续由 GUI 或替换阶段决定还原粒度

    # 构建结果（按 StartOffset 排序，外层在前）
    $sortedExprs = $allExprs | Sort-Object { $_.Extent.StartOffset }

    foreach ($expr in $sortedExprs) {
        $type = switch ($true) {
            # 原有类型
            ($expr -is [System.Management.Automation.Language.BinaryExpressionAst])           { "Binary" }
            ($expr -is [System.Management.Automation.Language.UnaryExpressionAst])            { "Unary" }
            ($expr -is [System.Management.Automation.Language.InvokeMemberExpressionAst])     { "MemberInvoke" }
            # 高优先级新增
            ($expr -is [System.Management.Automation.Language.ConvertExpressionAst])          { "Convert" }
            ($expr -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) { "ExpandableString" }
            ($expr -is [System.Management.Automation.Language.IndexExpressionAst])            { "Index" }
            # 中优先级新增
            ($expr -is [System.Management.Automation.Language.SubExpressionAst])              { "SubExpression" }
            ($expr -is [System.Management.Automation.Language.MemberExpressionAst])           { "Member" }
            ($expr -is [System.Management.Automation.Language.ParenExpressionAst])            { "Paren" }
            ($expr -is [System.Management.Automation.Language.CommandAst])                    { "Command" }
            default { "Unknown" }
        }

        # 计算嵌套深度（有多少个目标类型的祖先）
        $depth = 0
        $ancestor = $expr.Parent
        while ($null -ne $ancestor -and $ancestor -ne $node.Ast) {
            if ($ancestor -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) { break }
            foreach ($t in $targetTypes) {
                if ($ancestor -is $t) { $depth++; break }
            }
            $ancestor = $ancestor.Parent
        }

        $node.Resolvables += @{
            Type        = $type
            Ast         = $expr
            Text        = $expr.Extent.Text
            StartOffset = $expr.Extent.StartOffset  # 原脚本中的起始位置
            EndOffset   = $expr.Extent.EndOffset    # 原脚本中的结束位置
            Depth       = $depth                     # 嵌套深度（0=最外层）
        }
    }
}

# 辅助函数：从 Set-Alias/New-Alias 命令提取别名定义
# 返回值：@{ Name = "别名"; Value = "目标命令" } 或 $null
function Get-AliasDefinitionFromCommand {
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Language.CommandAst]$cmdAst
    )

    $cmdName = $cmdAst.GetCommandName()
    if ($cmdName -notin @('Set-Alias', 'New-Alias', 'sal', 'nal')) {
        return $null
    }

    $aliasName = $null
    $aliasValue = $null

    # 解析参数
    $elements = $cmdAst.CommandElements
    for ($i = 1; $i -lt $elements.Count; $i++) {
        $elem = $elements[$i]

        # 检查是否是参数名
        if ($elem -is [System.Management.Automation.Language.CommandParameterAst]) {
            $paramName = $elem.ParameterName.ToLower()
            # -Name 或 -n
            if ($paramName -in @('name', 'n')) {
                # 下一个元素是值
                if ($i + 1 -lt $elements.Count) {
                    $nextElem = $elements[$i + 1]
                    if ($nextElem -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                        $aliasName = $nextElem.Value
                    } elseif ($nextElem -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) {
                        $aliasName = $nextElem.Value
                    }
                    $i++
                }
            }
            # -Value 或 -val 或 -v
            elseif ($paramName -in @('value', 'val', 'v')) {
                if ($i + 1 -lt $elements.Count) {
                    $nextElem = $elements[$i + 1]
                    if ($nextElem -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                        $aliasValue = $nextElem.Value
                    } elseif ($nextElem -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) {
                        $aliasValue = $nextElem.Value
                    }
                    $i++
                }
            }
        }
        # 位置参数（sal output Invoke-Expression）
        elseif ($elem -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
            if ($null -eq $aliasName) {
                $aliasName = $elem.Value
            } elseif ($null -eq $aliasValue) {
                $aliasValue = $elem.Value
            }
        }
    }

    if ($null -ne $aliasName -and $null -ne $aliasValue) {
        return @{
            Name  = $aliasName
            Value = $aliasValue
        }
    }
    return $null
}

# 辅助函数：检测节点中的别名使用
function Populate-NodeAliasUsage {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$node,
        [Parameter(Mandatory = $true)]
        [hashtable]$cfg
    )

    $node.AliasesUsed = @()
    if ($null -eq $node.Ast) { return }

    # 查找所有 CommandAst（排除 ScriptBlock 内部）
    $commandAsts = @($node.Ast.FindAll({
        param($n)
        if ($n -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) { return $false }
        $n -is [System.Management.Automation.Language.CommandAst]
    }, $true))

    # 过滤掉嵌套在 ScriptBlockExpressionAst 内部的
    $commandAsts = @($commandAsts | Where-Object {
        $ancestor = $_.Parent
        while ($null -ne $ancestor -and $ancestor -ne $node.Ast) {
            if ($ancestor -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
                return $false
            }
            $ancestor = $ancestor.Parent
        }
        return $true
    })

    foreach ($cmdAst in $commandAsts) {
        $cmdName = $cmdAst.GetCommandName()
        if (-not [string]::IsNullOrWhiteSpace($cmdName)) {
            # 检查是否是已定义的别名
            if ($cfg.DefinedAliases.ContainsKey($cmdName)) {
                $node.AliasesUsed += @{
                    Name   = $cmdName
                    Target = $cfg.DefinedAliases[$cmdName]
                    Ast    = $cmdAst
                }
            }
        }
    }
}

# 辅助函数：查找 AST 中所有用户定义的函数调用
# 只返回调用了 DefinedFunctions 中函数的 CommandAst
# function Get-AllFunctionCalls {
#     param(
#         [Parameter(Mandatory = $true)]
#         $ast,
#         [Parameter(Mandatory = $true)]
#         [hashtable]$cfg
#     )

#     if ($null -eq $ast) { return @() }

#     $definedFuncs = $cfg.DefinedFunctions

#     $calls = $ast.FindAll({
#         param($n)
#         if (-not ($n -is [System.Management.Automation.Language.CommandAst])) { return $false }

#         # 获取命令名称
#         $cmdName = $n.GetCommandName()
#         if ([string]::IsNullOrWhiteSpace($cmdName)) { return $false }

#         # 只返回已定义的用户函数
#         return $definedFuncs.Contains($cmdName)
#     }, $true)

#     return @($calls)
# }

# 辅助函数：查找 AST 中所有嵌套的多元素 Pipeline
# 注意：不深入到 ScriptBlockExpressionAst 内部，因为 ScriptBlock 内部会由 Convert-ScriptBlockDefinition 单独处理
function Get-AllNestedPipelines {
    param(
        [Parameter(Mandatory = $true)]
        $ast
    )

    if ($null -eq $ast) { return @() }

    # 在 AST 子树中查找所有多元素 PipelineAst
    $pipelines = $ast.FindAll({
        param($n)
        # 跳过 ScriptBlockExpressionAst 及其子节点
        if ($n -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
            return $false
        }
        $n -is [System.Management.Automation.Language.PipelineAst] -and
        $n.PipelineElements.Count -gt 1
    }, $true)

    # 过滤掉位于 ScriptBlockExpressionAst 内部的 Pipeline
    $pipelines = @($pipelines | Where-Object {
        $ancestor = $_.Parent
        while ($null -ne $ancestor -and $ancestor -ne $ast) {
            # 如果遇到 ScriptBlockExpressionAst，排除
            if ($ancestor -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
                return $false
            }
            $ancestor = $ancestor.Parent
        }
        return $true
    })

    return @($pipelines)
}

# 辅助函数：查找 AST 中所有嵌套的 ScriptBlockExpressionAst
# 注意：不深入到已找到的 ScriptBlockExpressionAst 内部，因为 ScriptBlock 内部会由 Convert-ScriptBlockDefinition 单独处理
function Get-AllNestedScriptBlocks {
    param(
        [Parameter(Mandatory = $true)]
        $ast
    )

    if ($null -eq $ast) { return @() }

    $scriptBlocks = $ast.FindAll({
        param($n)
        $n -is [System.Management.Automation.Language.ScriptBlockExpressionAst]
    }, $true)

    # 只保留直接子 ScriptBlock，排除嵌套在其他 ScriptBlock 内部的
    $scriptBlocks = @($scriptBlocks | Where-Object {
        $ancestor = $_.Parent
        while ($null -ne $ancestor -and $ancestor -ne $ast) {
            if ($ancestor -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
                return $false
            }
            $ancestor = $ancestor.Parent
        }
        return $true
    })

    return @($scriptBlocks)
}

# 辅助函数：判断 ScriptBlock 是立即执行还是延迟执行
# 返回值："Deferred" | "Immediate" | "InvokeOnly" | "CmdletInvoke" | "PipelineValue"
# InvokeOnly 表示 & { } 或 . { } 这种情况，只需要展开内部语句，不需要后续节点
# CmdletInvoke 表示作为 cmdlet 参数传入并被调用（如 Invoke-Command -ScriptBlock { }）
# PipelineValue 表示 ScriptBlock 作为 Pipeline 元素的值传递（如 { Get-Date } | ForEach-Object { & $_ }）
function Get-ScriptBlockExecutionType {
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Language.ScriptBlockExpressionAst]$scriptBlockExprAst
    )

    $parent = $scriptBlockExprAst.Parent

    # 赋值语句右侧 → 延迟执行
    if ($parent -is [System.Management.Automation.Language.AssignmentStatementAst]) {
        return "Deferred"
    }

    # CommandExpressionAst 中的 ScriptBlock（如 { Get-Date } | ... 中的 { Get-Date }）
    # 这种情况下 ScriptBlock 作为值传递到 Pipeline，应该保持原样
    if ($parent -is [System.Management.Automation.Language.CommandExpressionAst]) {
        # 检查是否在 Pipeline 中
        $grandParent = $parent.Parent
        if ($grandParent -is [System.Management.Automation.Language.PipelineAst]) {
            # 作为 Pipeline 元素传递值，保持原样
            return "PipelineValue"
        }
        # 独立的 CommandExpressionAst（如单独一行 { Get-Date }）
        return "Deferred"
    }

    # CommandAst 中作为参数
    if ($parent -is [System.Management.Automation.Language.CommandAst]) {
        # 检查 InvocationOperator：& 或 . 表示立即执行
        $invocationOp = $parent.InvocationOperator
        if ($invocationOp -eq [System.Management.Automation.Language.TokenKind]::Ampersand -or
            $invocationOp -eq [System.Management.Automation.Language.TokenKind]::Dot) {
            # 检查 ScriptBlock 是否是唯一的参数（即 & { } 或 . { } 形式）
            # 这种情况下只需要展开内部语句，不需要后续节点
            if ($parent.CommandElements.Count -eq 1 -and $parent.CommandElements[0] -eq $scriptBlockExprAst) {
                return "InvokeOnly"
            }
            return "Immediate"
        }

        $cmdName = $parent.GetCommandName()
        # 管道 cmdlet → 立即执行（内联展开）
        if ($cmdName -in @('Where-Object', 'ForEach-Object', 'Where', 'ForEach', '?', '%',
                           'Sort-Object', 'Group-Object', 'Select-Object', 'Measure-Object')) {
            return "Immediate"
        }
        # 调用类 cmdlet → CmdletInvoke（生成 BlockDef + 调用节点）
        if ($cmdName -in @('Invoke-Command', 'Start-Job', 'Register-ObjectEvent',
                           'Register-EngineEvent', 'New-Event')) {
            return "CmdletInvoke"
        }
    }

    # 方法调用 .Where() .ForEach() → 立即执行
    if ($parent -is [System.Management.Automation.Language.InvokeMemberExpressionAst]) {
        $memberName = $parent.Member.Value
        if ($memberName -in @('Where', 'ForEach')) {
            return "Immediate"
        }
    }

    # CommandParameterAst 的值（如 -ScriptBlock { }）
    if ($parent -is [System.Management.Automation.Language.CommandParameterAst]) {
        # 获取参数所属的 CommandAst
        $cmdAst = $parent.Parent
        if ($cmdAst -is [System.Management.Automation.Language.CommandAst]) {
            $cmdName = $cmdAst.GetCommandName()
            # 调用类 cmdlet 的参数 → CmdletInvoke
            if ($cmdName -in @('Invoke-Command', 'Start-Job', 'Register-ObjectEvent',
                               'Register-EngineEvent', 'New-Event')) {
                return "CmdletInvoke"
            }
        }
        # 检查参数名
        $paramName = $parent.ParameterName
        if ($paramName -in @('FilterScript', 'Process', 'Begin', 'End')) {
            return "Immediate"
        }
        # -Action, -ScriptBlock 等通常是延迟执行
        return "Deferred"
    }

    # 默认延迟执行
    return "Deferred"
}

# 将 ScriptBlock 的 process 块转换为可遍历的迭代结构
# 语义对齐 foreach：先初始化输入数组，再逐项绑定当前值执行主体
function Convert-ProcessBlock {
    param(
        [hashtable]$cfg,
        [System.Management.Automation.Language.ScriptBlockAst]$scriptBlockAst,
        [ref]$prevNodeRef,
        [ref]$endNodeRef,
        [bool]$UseProcessInputVar = $true,
        $switchContext = $null
    )

    if ($null -eq $scriptBlockAst -or
        $null -eq $scriptBlockAst.ProcessBlock -or
        $scriptBlockAst.ProcessBlock.Statements.Count -eq 0) {
        return
    }

    $processAst = $scriptBlockAst.ProcessBlock

    # 生成唯一变量名，避免与用户变量冲突
    $guid = [guid]::NewGuid().ToString("N").Substring(0, 12)
    $collectionVar = "__prc_$guid"
    $indexVar = "__prc_${guid}_idx"
    $currentVar = "__prc_${guid}_current"

    $collectionVarEntry = [PSCustomObject]@{ Name = $collectionVar; Scope = [VarScope]::Unspecified }
    $indexVarEntry = [PSCustomObject]@{ Name = $indexVar; Scope = [VarScope]::Unspecified }
    $currentVarEntry = [PSCustomObject]@{ Name = $currentVar; Scope = [VarScope]::Unspecified }
    $processInputEntry = [PSCustomObject]@{ Name = "__proc_input"; Scope = [VarScope]::Unspecified }

    $inputExpr = if ($UseProcessInputVar) { '$__proc_input' } else { '@()' }

    # 1) 初始化输入与索引
    $initText = "`$$collectionVar = $inputExpr; `$$indexVar = 0"
    $initNode = Add-Node -cfg $cfg -type "ProcessInit" -text $initText -line $processAst.Extent.StartLineNumber -ast $null -ownerAst $processAst
    $initNode.VarsRead = @()
    $initNode.VarsWritten = @()
    if ($UseProcessInputVar) {
        Add-VarToNode -node $initNode -varEntry $processInputEntry -accessType "Read"
    }
    Add-VarToNode -node $initNode -varEntry $collectionVarEntry -accessType "Write"
    Add-VarToNode -node $initNode -varEntry $indexVarEntry -accessType "Write"
    if ($null -ne $prevNodeRef.Value) {
        Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $initNode.Id
    }

    # 2) 条件判断
    $condText = "[bool](`$$indexVar -lt `$$collectionVar.Count)"
    $conditionNode = Add-Node -cfg $cfg -type "ProcessCondition" -text $condText -line $processAst.Extent.StartLineNumber -ast $null -ownerAst $processAst
    $conditionNode.VarsRead = @($indexVarEntry, $collectionVarEntry)
    $conditionNode.VarsWritten = @()
    Add-Edge -cfg $cfg -from $initNode.Id -to $conditionNode.Id

    # 3) 无更多输入时结束
    $loopEnd = Add-Node -cfg $cfg -type "ProcessEnd" -text "End Process" -line $processAst.Extent.EndLineNumber -ast $null -ownerAst $processAst
    Add-Edge -cfg $cfg -from $conditionNode.Id -to $loopEnd.Id -label "No more items"

    # 4) 绑定当前项
    $bindText = "`$$currentVar = `$$collectionVar[`$$indexVar]"
    $bindNode = Add-Node -cfg $cfg -type "ProcessBind" -text $bindText -line $processAst.Extent.StartLineNumber -ast $null -ownerAst $processAst
    $bindNode.VarsRead = @($collectionVarEntry, $indexVarEntry)
    $bindNode.VarsWritten = @($currentVarEntry)
    Add-Edge -cfg $cfg -from $conditionNode.Id -to $bindNode.Id -label "Has next"

    # 5) 迭代索引
    $iterText = "`$$indexVar++"
    $iterNode = Add-Node -cfg $cfg -type "ProcessIter" -text $iterText -line $processAst.Extent.StartLineNumber -ast $null -ownerAst $processAst
    $iterNode.VarsRead = @($indexVarEntry)
    $iterNode.VarsWritten = @($indexVarEntry)
    Add-Edge -cfg $cfg -from $iterNode.Id -to $conditionNode.Id

    $processLoopContext = [PSCustomObject]@{
        LoopEnd      = $loopEnd
        LoopContinue = $iterNode
    }

    # 6) 处理 process 主体语句
    $currentNode = $bindNode
    $bodyNodeCountBefore = $cfg.Nodes.Count
    foreach ($statement in $processAst.Statements) {
        $hasReturn = Convert-AstNode -cfg $cfg -node $statement -prevNodeRef ([ref]$currentNode) -endNodeRef $endNodeRef -loopContext $processLoopContext -switchContext $switchContext
        if ($hasReturn) { break }
    }

    # 将 process 主体中的 $_/$PSItem 替换为当前项变量
    Replace-PipelineCurrentInNodes -cfg $cfg -nodes $cfg.Nodes -startIndex $bodyNodeCountBefore -currentVar $currentVar -IncludePSItem

    # 7) 主体结束后进入下一轮
    if ($null -ne $currentNode) {
        $lastType = $currentNode.Type
        if ($lastType -notin @("Break", "Continue", "Return", "Exit", "Throw")) {
            Add-Edge -cfg $cfg -from $currentNode.Id -to $iterNode.Id
        }
    }

    $prevNodeRef.Value = $loopEnd
}

function Test-ForEachObjectCommandAst {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst
    )

    if ($null -eq $CommandAst) { return $false }
    $cmdName = $CommandAst.GetCommandName()
    if ([string]::IsNullOrWhiteSpace($cmdName)) { return $false }
    return ($cmdName -in @('ForEach-Object', 'ForEach', '%'))
}

function Get-ForEachObjectExpansionInfo {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst
    )

    $result = [ordered]@{
        IsForEachObject = $false
        CanExpand       = $false
        Reason          = $null
        BeginBlockAst   = $null
        ProcessBlockAst = $null
        EndBlockAst     = $null
    }

    if (-not (Test-ForEachObjectCommandAst -CommandAst $CommandAst)) {
        return [PSCustomObject]$result
    }

    $result.IsForEachObject = $true

    function Resolve-ForEachLiteralScriptBlock {
        param(
            $Ast,
            [string]$Role
        )

        if ($null -eq $Ast) {
            return @{ Success = $false; Reason = "$Role block is missing"; BlockAst = $null }
        }

        if ($Ast -isnot [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
            return @{ Success = $false; Reason = "$Role block is not a literal scriptblock"; BlockAst = $null }
        }

        $sbAst = $Ast.ScriptBlock
        if ($null -eq $sbAst) {
            return @{ Success = $false; Reason = "$Role block has no ScriptBlock AST"; BlockAst = $null }
        }

        if ($sbAst.ParamBlock) {
            return @{ Success = $false; Reason = "$Role block with param() is not expanded"; BlockAst = $null }
        }

        if ($null -ne $sbAst.BeginBlock -or $null -ne $sbAst.ProcessBlock) {
            return @{ Success = $false; Reason = "$Role block with nested begin/process is not expanded"; BlockAst = $null }
        }

        return @{ Success = $true; Reason = $null; BlockAst = $sbAst }
    }

    $beginArg = $null
    $processArg = $null
    $endArg = $null
    $positional = @()

    for ($i = 1; $i -lt $CommandAst.CommandElements.Count; $i++) {
        $elem = $CommandAst.CommandElements[$i]

        if ($elem -is [System.Management.Automation.Language.CommandParameterAst]) {
            $pname = $elem.ParameterName
            if ($pname -in @('Begin', 'Process', 'End')) {
                $argAst = $elem.Argument
                if (-not $argAst -and ($i + 1 -lt $CommandAst.CommandElements.Count)) {
                    $i++
                    $argAst = $CommandAst.CommandElements[$i]
                }

                switch ($pname) {
                    'Begin'   { $beginArg = $argAst }
                    'Process' { $processArg = $argAst }
                    'End'     { $endArg = $argAst }
                }
            }
            continue
        }

        $positional += $elem
    }

    if (-not $beginArg -and -not $processArg -and -not $endArg) {
        $blocks = @()
        foreach ($e in $positional) {
            if ($e -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
                $blocks += $e
            } elseif ($e -is [System.Management.Automation.Language.VariableExpressionAst]) {
                $result.Reason = 'variable-backed scriptblock arguments fall back to runtime execution'
                return [PSCustomObject]$result
            }
        }

        if ($blocks.Count -eq 1) {
            $processArg = $blocks[0]
        } elseif ($blocks.Count -eq 2) {
            $beginArg = $blocks[0]
            $processArg = $blocks[1]
        } elseif ($blocks.Count -ge 3) {
            $beginArg = $blocks[0]
            $processArg = $blocks[1]
            $endArg = $blocks[2]
        }
    }

    if (-not $processArg) {
        $result.Reason = 'process block is missing'
        return [PSCustomObject]$result
    }

    if ($beginArg) {
        $resolvedBegin = Resolve-ForEachLiteralScriptBlock -Ast $beginArg -Role 'Begin'
        if (-not $resolvedBegin.Success) {
            $result.Reason = $resolvedBegin.Reason
            return [PSCustomObject]$result
        }
        $result.BeginBlockAst = $resolvedBegin.BlockAst
    }

    $resolvedProcess = Resolve-ForEachLiteralScriptBlock -Ast $processArg -Role 'Process'
    if (-not $resolvedProcess.Success) {
        $result.Reason = $resolvedProcess.Reason
        return [PSCustomObject]$result
    }
    $result.ProcessBlockAst = $resolvedProcess.BlockAst

    if ($endArg) {
        $resolvedEnd = Resolve-ForEachLiteralScriptBlock -Ast $endArg -Role 'End'
        if (-not $resolvedEnd.Success) {
            $result.Reason = $resolvedEnd.Reason
            return [PSCustomObject]$result
        }
        $result.EndBlockAst = $resolvedEnd.BlockAst
    }

    $result.CanExpand = $true
    return [PSCustomObject]$result
}

function New-OutputCaptureNode {
    param(
        [hashtable]$cfg,
        [ValidateSet('OutputCaptureStart', 'OutputCaptureEnd')]
        [string]$Type,
        [string]$Text,
        [int]$Line,
        [string]$TargetVarName,
        $OwnerAst = $null
    )

    $node = Add-Node -cfg $cfg -type $Type -text $Text -line $Line -ast $null -ownerAst $OwnerAst
    $node.VarsRead = @()
    $node.VarsWritten = @()

    if ($Type -eq 'OutputCaptureEnd' -and -not [string]::IsNullOrWhiteSpace($TargetVarName)) {
        $targetVarEntry = [PSCustomObject]@{ Name = $TargetVarName; Scope = [VarScope]::Unspecified }
        Add-VarToNode -node $node -varEntry $targetVarEntry -accessType 'Write'
        $node | Add-Member -NotePropertyName 'CaptureTargetVar' -NotePropertyValue $TargetVarName -Force
    }

    return $node
}

function Convert-InlineStatementList {
    param(
        [hashtable]$cfg,
        [object[]]$Statements,
        [ref]$prevNodeRef,
        [pscustomobject]$NormalExitNode,
        $endNodeRef = $null,
        $loopContext = $null,
        [string]$CurrentVar = $null,
        [switch]$ReplacePipelineCurrent
    )

    $bodyStartIndex = $cfg.Nodes.Count
    foreach ($statement in $Statements) {
        $hasTerminator = Convert-AstNode -cfg $cfg -node $statement -prevNodeRef $prevNodeRef -endNodeRef $endNodeRef -loopContext $loopContext -switchContext $null
        if ($hasTerminator) { break }
    }

    if ($ReplacePipelineCurrent -and -not [string]::IsNullOrWhiteSpace($CurrentVar)) {
        Replace-PipelineCurrentInNodes -cfg $cfg -nodes $cfg.Nodes -startIndex $bodyStartIndex -currentVar $CurrentVar -IncludePSItem
    }

    if ($null -ne $prevNodeRef.Value) {
        $lastType = $prevNodeRef.Value.Type
        if ($lastType -notin @('Break', 'Continue', 'Return', 'Exit', 'Throw')) {
            Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $NormalExitNode.Id
        }
    }

    $prevNodeRef.Value = $NormalExitNode
}

function Expand-ForEachObjectPipelineElement {
    param(
        [hashtable]$cfg,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [ref]$prevNodeRef,
        [string]$PipeVarName,
        [pscustomobject]$PipeVarEntry,
        [string]$IncomingEdgeLabel = 'Pipeline'
    )

    $info = Get-ForEachObjectExpansionInfo -CommandAst $CommandAst
    if (-not $info.IsForEachObject -or -not $info.CanExpand) {
        return [PSCustomObject]@{
            Expanded  = $false
            Reason    = $info.Reason
            FinalNode = $prevNodeRef.Value
        }
    }

    $line = $CommandAst.Extent.StartLineNumber
    $guid = [guid]::NewGuid().ToString('N').Substring(0, 12)
    $inputVar = "__pfo_in_$guid"
    $indexVar = "__pfo_${guid}_idx"
    $currentVar = "__pfo_${guid}_cur"
    $outputVar = "__pfo_${guid}_out"

    $inputVarEntry = [PSCustomObject]@{ Name = $inputVar; Scope = [VarScope]::Unspecified }
    $indexVarEntry = [PSCustomObject]@{ Name = $indexVar; Scope = [VarScope]::Unspecified }
    $currentVarEntry = [PSCustomObject]@{ Name = $currentVar; Scope = [VarScope]::Unspecified }
    $outputVarEntry = [PSCustomObject]@{ Name = $outputVar; Scope = [VarScope]::Unspecified }

    $initText = "`$$inputVar = `$$PipeVarName; `$$indexVar = 0; `$$outputVar = @()"
    $initNode = Add-Node -cfg $cfg -type 'ProcessInit' -text $initText -line $line -ast $null -ownerAst $CommandAst
    $initNode.VarsRead = @()
    $initNode.VarsWritten = @()
    Add-VarToNode -node $initNode -varEntry $PipeVarEntry -accessType 'Read'
    Add-VarToNode -node $initNode -varEntry $inputVarEntry -accessType 'Write'
    Add-VarToNode -node $initNode -varEntry $indexVarEntry -accessType 'Write'
    Add-VarToNode -node $initNode -varEntry $outputVarEntry -accessType 'Write'
    if ($null -ne $prevNodeRef.Value) {
        if ([string]::IsNullOrWhiteSpace($IncomingEdgeLabel)) {
            Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $initNode.Id
        } else {
            Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $initNode.Id -label $IncomingEdgeLabel
        }
    }

    $currentNode = $initNode
    $breakLoopEnd = Add-Node -cfg $cfg -type 'LoopEnd' -text 'Break ForEach-Object' -line $CommandAst.Extent.EndLineNumber -ast $null -ownerAst $CommandAst

    $beginStatements = if ($info.BeginBlockAst -and $info.BeginBlockAst.EndBlock) { @($info.BeginBlockAst.EndBlock.Statements) } else { @() }
    if ($beginStatements.Count -gt 0) {
        $beginCaptureStart = New-OutputCaptureNode -cfg $cfg -Type 'OutputCaptureStart' -Text 'Capture Begin Output' -Line $line -TargetVarName $null -OwnerAst $CommandAst
        $beginNormalCaptureEnd = New-OutputCaptureNode -cfg $cfg -Type 'OutputCaptureEnd' -Text 'Append Begin Output' -Line $line -TargetVarName $outputVar -OwnerAst $CommandAst
        $beginBreakCaptureEnd = New-OutputCaptureNode -cfg $cfg -Type 'OutputCaptureEnd' -Text 'Append Begin Output (Break)' -Line $line -TargetVarName $outputVar -OwnerAst $CommandAst
        Add-Edge -cfg $cfg -from $currentNode.Id -to $beginCaptureStart.Id

        $beginPrevNodeRef = [ref]$beginCaptureStart
        $beginLoopContext = [PSCustomObject]@{
            LoopEnd      = $beginBreakCaptureEnd
            LoopContinue = $beginNormalCaptureEnd
        }
        Convert-InlineStatementList -cfg $cfg -Statements $beginStatements -prevNodeRef $beginPrevNodeRef -NormalExitNode $beginNormalCaptureEnd -endNodeRef $beginNormalCaptureEnd -loopContext $beginLoopContext
        Add-Edge -cfg $cfg -from $beginBreakCaptureEnd.Id -to $breakLoopEnd.Id
        $currentNode = $beginNormalCaptureEnd
    }

    $conditionNode = Add-Node -cfg $cfg -type 'ProcessCondition' -text "[bool](`$$indexVar -lt `$$inputVar.Count)" -line $line -ast $null -ownerAst $CommandAst
    $conditionNode.VarsRead = @($indexVarEntry, $inputVarEntry)
    $conditionNode.VarsWritten = @()
    Add-Edge -cfg $cfg -from $currentNode.Id -to $conditionNode.Id

    $normalLoopEnd = Add-Node -cfg $cfg -type 'ProcessEnd' -text 'End ForEach-Object Process' -line $CommandAst.Extent.EndLineNumber -ast $null -ownerAst $CommandAst
    Add-Edge -cfg $cfg -from $conditionNode.Id -to $normalLoopEnd.Id -label 'No more items'

    $bindNode = Add-Node -cfg $cfg -type 'ProcessBind' -text "`$$currentVar = `$$inputVar[`$$indexVar]" -line $line -ast $null -ownerAst $CommandAst
    $bindNode.VarsRead = @($inputVarEntry, $indexVarEntry)
    $bindNode.VarsWritten = @($currentVarEntry)
    Add-Edge -cfg $cfg -from $conditionNode.Id -to $bindNode.Id -label 'Has next'

    $processCaptureStart = New-OutputCaptureNode -cfg $cfg -Type 'OutputCaptureStart' -Text 'Capture Process Output' -Line $line -TargetVarName $null -OwnerAst $CommandAst
    $processNormalCaptureEnd = New-OutputCaptureNode -cfg $cfg -Type 'OutputCaptureEnd' -Text 'Append Process Output' -Line $line -TargetVarName $outputVar -OwnerAst $CommandAst
    $processBreakCaptureEnd = New-OutputCaptureNode -cfg $cfg -Type 'OutputCaptureEnd' -Text 'Append Process Output (Break)' -Line $line -TargetVarName $outputVar -OwnerAst $CommandAst
    $processContinueCaptureEnd = New-OutputCaptureNode -cfg $cfg -Type 'OutputCaptureEnd' -Text 'Append Process Output (Continue)' -Line $line -TargetVarName $outputVar -OwnerAst $CommandAst
    Add-Edge -cfg $cfg -from $bindNode.Id -to $processCaptureStart.Id

    $processStatements = if ($info.ProcessBlockAst -and $info.ProcessBlockAst.EndBlock) { @($info.ProcessBlockAst.EndBlock.Statements) } else { @() }
    $processPrevNodeRef = [ref]$processCaptureStart
    $processLoopContext = [PSCustomObject]@{
        LoopEnd      = $processBreakCaptureEnd
        LoopContinue = $processContinueCaptureEnd
    }
    Convert-InlineStatementList -cfg $cfg -Statements $processStatements -prevNodeRef $processPrevNodeRef -NormalExitNode $processNormalCaptureEnd -endNodeRef $processNormalCaptureEnd -loopContext $processLoopContext -CurrentVar $currentVar -ReplacePipelineCurrent

    $iterNode = Add-Node -cfg $cfg -type 'ProcessIter' -text "`$$indexVar++" -line $line -ast $null -ownerAst $CommandAst
    $iterNode.VarsRead = @($indexVarEntry)
    $iterNode.VarsWritten = @($indexVarEntry)
    Add-Edge -cfg $cfg -from $processNormalCaptureEnd.Id -to $iterNode.Id
    Add-Edge -cfg $cfg -from $processContinueCaptureEnd.Id -to $iterNode.Id
    Add-Edge -cfg $cfg -from $processBreakCaptureEnd.Id -to $breakLoopEnd.Id
    Add-Edge -cfg $cfg -from $iterNode.Id -to $conditionNode.Id

    $currentNode = $normalLoopEnd
    $endStatements = if ($info.EndBlockAst -and $info.EndBlockAst.EndBlock) { @($info.EndBlockAst.EndBlock.Statements) } else { @() }
    if ($endStatements.Count -gt 0) {
        $endCaptureStart = New-OutputCaptureNode -cfg $cfg -Type 'OutputCaptureStart' -Text 'Capture End Output' -Line $line -TargetVarName $null -OwnerAst $CommandAst
        $endNormalCaptureEnd = New-OutputCaptureNode -cfg $cfg -Type 'OutputCaptureEnd' -Text 'Append End Output' -Line $line -TargetVarName $outputVar -OwnerAst $CommandAst
        Add-Edge -cfg $cfg -from $normalLoopEnd.Id -to $endCaptureStart.Id

        $endPrevNodeRef = [ref]$endCaptureStart
        $endLoopContext = [PSCustomObject]@{
            LoopEnd      = $endNormalCaptureEnd
            LoopContinue = $endNormalCaptureEnd
        }
        Convert-InlineStatementList -cfg $cfg -Statements $endStatements -prevNodeRef $endPrevNodeRef -NormalExitNode $endNormalCaptureEnd -endNodeRef $endNormalCaptureEnd -loopContext $endLoopContext
        $currentNode = $endNormalCaptureEnd
    }

    $commitNode = Add-Node -cfg $cfg -type 'AssignmentStatementAst' -text "`$$PipeVarName = `$$outputVar" -line $line -ast $null -ownerAst $CommandAst
    $commitNode.VarsRead = @($outputVarEntry)
    $commitNode.VarsWritten = @($PipeVarEntry)
    Add-Edge -cfg $cfg -from $currentNode.Id -to $commitNode.Id
    Add-Edge -cfg $cfg -from $breakLoopEnd.Id -to $commitNode.Id

    $prevNodeRef.Value = $commitNode
    return [PSCustomObject]@{
        Expanded  = $true
        Reason    = $null
        FinalNode = $commitNode
    }
}
# 为 PipelineElement 节点标记特殊管道 cmdlet（仅用于可视化/后续分析，不改变 CFG 结构）
function Mark-PipelineCmdletNode {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Node,
        $ElementAst
    )

    if (-not $Node) { return }
    if ($Node.Type -ne "PipelineElement") { return }
    if ($null -eq $ElementAst) { return }

    if ($ElementAst -is [System.Management.Automation.Language.CommandAst]) {
        $cmdName = $ElementAst.GetCommandName()
        if ([string]::IsNullOrWhiteSpace($cmdName)) { return }

        # ForEach-Object（以及常见别名）
        if ($cmdName -in @('ForEach-Object', 'ForEach', '%')) {
            $Node | Add-Member -NotePropertyName "PipeCmdlet" -NotePropertyValue "ForEachObject" -Force
            $Node | Add-Member -NotePropertyName "PipeCmdletName" -NotePropertyValue $cmdName -Force
            return
        }

        # Where-Object（以及常见别名）
        if ($cmdName -in @('Where-Object', 'Where', '?')) {
            $Node | Add-Member -NotePropertyName "PipeCmdlet" -NotePropertyValue "WhereObject" -Force
            $Node | Add-Member -NotePropertyName "PipeCmdletName" -NotePropertyValue $cmdName -Force
            return
        }

        # Select-Object（以及常见别名）
        if ($cmdName -in @('Select-Object', 'Select')) {
            $Node | Add-Member -NotePropertyName "PipeCmdlet" -NotePropertyValue "SelectObject" -Force
            $Node | Add-Member -NotePropertyName "PipeCmdletName" -NotePropertyValue $cmdName -Force
            return
        }
    }
}

# 通用函数：处理 ScriptBlock 的内部结构（ParamBlock + Begin/Process/End）
# 此函数统一处理脚本顶层、函数体、延迟执行 ScriptBlock、立即执行 ScriptBlock 的内部结构
# 调用者负责创建入口/出口节点，此函数只处理内部内容
function Convert-ScriptBlockBody {
    param(
        [hashtable]$cfg,
        [System.Management.Automation.Language.ScriptBlockAst]$scriptBlockAst,
        [ref]$prevNodeRef,
        [ref]$endNodeRef,
        [string]$paramNodeType = "BlockParams",  # ScriptParams | FuncParams | BlockParams
        $loopContext = $null,
        $switchContext = $null,
        [bool]$IsTopLevelScript = $false
    )

    if ($null -eq $scriptBlockAst) {
        return $false
    }

    $hasTerminator = $false

    # 1. 处理 ParamBlock（如果存在）
    if ($null -ne $scriptBlockAst.ParamBlock) {
        $paramBlock = $scriptBlockAst.ParamBlock

        # 检查 ParamBlock 中是否有嵌套 Pipeline（参数默认值中可能有 pipeline）
        $paramExpansion = Expand-NestedPipelines -cfg $cfg -ast $paramBlock -prevNodeRef $prevNodeRef

        # 将 ParamBlock 文本压缩为单行
        $rawParamText = $paramBlock.Extent.Text
        if ($null -ne $paramExpansion) {
            # 有嵌套 Pipeline，使用修改后的文本
            $rawParamText = $paramExpansion.ModifiedText
        }
        $singleLineParam = ($rawParamText -split "`r?`n") -join ' '
        $singleLineParam = ($singleLineParam -replace '\s+', ' ').Trim()

        $paramNode = Add-Node -cfg $cfg -type $paramNodeType -text $singleLineParam -line $paramBlock.Extent.StartLineNumber -ast $paramBlock

        if ($null -ne $paramExpansion) {
            # 添加 pipeVar 到 VarsRead
            foreach ($pipeVarEntry in $paramExpansion.PipeVarEntries) {
                Add-VarToNode -node $paramNode -varEntry $pipeVarEntry -accessType "Read"
            }
            # 连接最后一个 Pipeline 节点到参数节点
            Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $paramNode.Id -label "Pipeline"
        } else {
            # 无 Pipeline，直接连接
            if ($null -ne $prevNodeRef.Value) {
                Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $paramNode.Id
            }
        }
        $prevNodeRef.Value = $paramNode
    }

    # 2. 处理 BeginBlock（如果存在）
    if ($null -ne $scriptBlockAst.BeginBlock -and $scriptBlockAst.BeginBlock.Statements.Count -gt 0) {
        foreach ($statement in $scriptBlockAst.BeginBlock.Statements) {
            $stmtHasTerminator = Convert-AstNode -cfg $cfg -node $statement -prevNodeRef $prevNodeRef -endNodeRef $endNodeRef -loopContext $loopContext -switchContext $switchContext
            if ($stmtHasTerminator) {
                $hasTerminator = $true
                break
            }
        }
    }

    # 3. 处理 ProcessBlock（如果存在）- 转换为类 foreach 的迭代结构
    if ($null -ne $scriptBlockAst.ProcessBlock -and $scriptBlockAst.ProcessBlock.Statements.Count -gt 0) {
        # 顶层脚本 process 固定空输入；函数/脚本块 process 使用调用时注入的 $__proc_input
        $useProcessInputVar = -not $IsTopLevelScript
        Convert-ProcessBlock -cfg $cfg -scriptBlockAst $scriptBlockAst -prevNodeRef $prevNodeRef -endNodeRef $endNodeRef -UseProcessInputVar:$useProcessInputVar -switchContext $switchContext
    }

    # 4. 处理 EndBlock（主体代码）
    if ($null -ne $scriptBlockAst.EndBlock -and $scriptBlockAst.EndBlock.Statements.Count -gt 0) {
        foreach ($statement in $scriptBlockAst.EndBlock.Statements) {
            $stmtHasTerminator = Convert-AstNode -cfg $cfg -node $statement -prevNodeRef $prevNodeRef -endNodeRef $endNodeRef -loopContext $loopContext -switchContext $switchContext
            if ($stmtHasTerminator) {
                $hasTerminator = $true
                break
            }
        }
    }

    return $hasTerminator
}

# 辅助函数：为 ScriptBlock 创建独立子图（用于延迟执行和立即执行的 ScriptBlock）
# 返回值：@{ BlockName = "块名称"; BlockStart = 节点; BlockEnd = 节点 }
function Convert-ScriptBlockDefinition {
    param(
        [hashtable]$cfg,
        [System.Management.Automation.Language.ScriptBlockExpressionAst]$scriptBlockExprAst,
        [string]$blockName = $null  # 可选名称，如果不提供则自动生成
    )

    if ($null -eq $scriptBlockExprAst) {
        return $null
    }

    $scriptBlock = $scriptBlockExprAst.ScriptBlock

    # 如果没有提供名称，生成一个唯一名称
    if (-not $blockName) {
        $guid = [guid]::NewGuid().ToString("N").Substring(0, 8)
        $blockName = "__block_$guid"
    }

    # 创建 BlockStart 节点（不存储 AST，避免 Resolvables 误检测）
    $blockStart = Add-Node -cfg $cfg -type "BlockStart" -text "ScriptBlock $blockName" -line $scriptBlockExprAst.Extent.StartLineNumber -ast $null
    # 存储脚本块内容文本，用于运行时匹配（不使用 AST 属性，避免被 Populate-NodeResolvables 处理）
    $blockStart | Add-Member -NotePropertyName "ScriptBlockText" -NotePropertyValue $scriptBlockExprAst.Extent.Text -Force
    $hasProcessBlock = ($null -ne $scriptBlock.ProcessBlock -and $scriptBlock.ProcessBlock.Statements.Count -gt 0)
    $blockStart | Add-Member -NotePropertyName "HasProcessBlock" -NotePropertyValue $hasProcessBlock -Force
    $blockStart | Add-Member -NotePropertyName "ProcessInputVar" -NotePropertyValue "__proc_input" -Force
    $blockEnd = Add-Node -cfg $cfg -type "BlockEnd" -text "End ScriptBlock $blockName" -line $scriptBlockExprAst.Extent.EndLineNumber -ast $null

    $prevNode = $blockStart
    $prev = [ref]$prevNode
    $endRef = [ref]$blockEnd

    # 使用通用函数处理 ScriptBlock 内部结构
    $null = Convert-ScriptBlockBody -cfg $cfg -scriptBlockAst $scriptBlock -prevNodeRef $prev -endNodeRef $endRef -paramNodeType "BlockParams"

    # 连接最后一个节点到 BlockEnd
    if ($null -ne $prev.Value -and $prev.Value.Id -ne $blockEnd.Id) {
        $lastType = $prev.Value.Type
        if ($lastType -notin @("Return", "Exit", "Throw", "Break", "Continue", "End")) {
            Add-Edge -cfg $cfg -from $prev.Value.Id -to $blockEnd.Id
        }
    }

    return @{
        BlockName = $blockName
        BlockStart = $blockStart
        BlockEnd = $blockEnd
    }
}

# 辅助函数：展开表达式中的嵌套 ScriptBlock（立即执行类型）
# 返回值：@{ ModifiedText = "修改后的文本"; ScriptBlockVarEntries = @(...); InvokeOnlyExpanded = $true/$false }
# 如果没有需要展开的 ScriptBlock，返回 $null
# 所有 ScriptBlock 都会生成独立子图，包括立即执行的
# 【已修改】去掉 BlockDef 节点，改为直接生成调用节点或用变量引用替代
function Expand-NestedScriptBlocks {
    param(
        [Parameter(Mandatory = $true)]
        $cfg,
        [Parameter(Mandatory = $true)]
        $ast,
        [Parameter(Mandatory = $true)]
        [ref]$prevNodeRef,
        $endNodeRef = $null,
        $loopContext = $null,
        $switchContext = $null
    )

    $nestedScriptBlocks = Get-AllNestedScriptBlocks -ast $ast
    if ($nestedScriptBlocks.Count -eq 0) {
        return $null
    }

    # 分类：InvokeOnly vs Immediate vs CmdletInvoke vs Deferred vs PipelineValue
    $invokeOnlyBlocks = @()
    $immediateBlocks = @()
    $cmdletInvokeBlocks = @()
    $deferredBlocks = @()
    $pipelineValueBlocks = @()

    foreach ($sb in $nestedScriptBlocks) {
        $execType = Get-ScriptBlockExecutionType -scriptBlockExprAst $sb
        switch ($execType) {
            "InvokeOnly" { $invokeOnlyBlocks += $sb }
            "Immediate" { $immediateBlocks += $sb }
            "CmdletInvoke" { $cmdletInvokeBlocks += $sb }
            "PipelineValue" { $pipelineValueBlocks += $sb }
            default { $deferredBlocks += $sb }
        }
    }

    # 处理 PipelineValue 类型的 ScriptBlock（如 { Get-Date } | ForEach-Object { & $_ }）
    # 这类 ScriptBlock 作为 Pipeline 元素的值传递，需要生成独立子图并用变量引用替代
    # 记录替换信息，后续统一替换文本
    $pipelineValueReplacements = @()
    foreach ($sb in $pipelineValueBlocks) {
        # 检查是否已处理过
        if ($cfg.ProcessedScriptBlocks.ContainsKey($sb)) {
            # 已处理过，使用已有的变量名记录替换信息
            $varName = $cfg.ProcessedScriptBlocks[$sb]
            $blockVarEntry = [PSCustomObject]@{ Name = $varName; Scope = [VarScope]::Unspecified }
            $pipelineValueReplacements += @{
                Original = $sb.Extent.Text
                Replacement = "`$$varName"
                VarEntry = $blockVarEntry
            }
            continue
        }

        $guid = [guid]::NewGuid().ToString("N").Substring(0, 8)
        $varName = "_block_$guid"
        $blockVarEntry = [PSCustomObject]@{ Name = $varName; Scope = [VarScope]::Unspecified }

        # 标记为已处理，记录变量名
        $cfg.ProcessedScriptBlocks[$sb] = $varName

        # 创建独立子图
        $null = Convert-ScriptBlockDefinition -cfg $cfg -scriptBlockExprAst $sb -blockName $varName

        # 记录替换信息
        $pipelineValueReplacements += @{
            Original = $sb.Extent.Text
            Replacement = "`$$varName"
            VarEntry = $blockVarEntry
        }
    }

    # 处理延迟执行的 ScriptBlock：创建独立子图，使用赋值目标变量名
    # 记录替换信息，用于后续统一替换文本
    $deferredReplacements = @()
    $deferredVarEntries = @()
    foreach ($sb in $deferredBlocks) {
        # 检查是否已处理过
        if ($cfg.ProcessedScriptBlocks.ContainsKey($sb)) {
            # 已处理过，检查是否是直接赋值的情况
            # 直接赋值（$var = { ... }）不需要替换文本
            $varName = $cfg.ProcessedScriptBlocks[$sb]
            $parent = $sb.Parent

            # 检查是否是直接赋值：父节点是 CommandExpressionAst，
            # 且其 Expression 就是这个 ScriptBlock
            $isDirectAssignment = $false
            if ($parent -is [System.Management.Automation.Language.CommandExpressionAst] -and
                $parent.Expression -eq $sb) {
                $grandParent = $parent.Parent
                # 检查祖父是否是赋值语句的右侧 Pipeline
                if ($grandParent -is [System.Management.Automation.Language.PipelineAst] -and
                    $grandParent.PipelineElements.Count -eq 1) {
                    $greatGrandParent = $grandParent.Parent
                    if ($greatGrandParent -is [System.Management.Automation.Language.AssignmentStatementAst]) {
                        $isDirectAssignment = $true
                    }
                }
                # 也可能赋值右侧直接是 CommandExpressionAst
                if ($grandParent -is [System.Management.Automation.Language.AssignmentStatementAst]) {
                    $isDirectAssignment = $true
                }
            }

            if ($isDirectAssignment) {
                # 直接赋值，不需要替换
                continue
            }

            # 非直接赋值，记录替换信息
            $blockVarEntry = [PSCustomObject]@{ Name = $varName; Scope = [VarScope]::Unspecified }
            $deferredReplacements += @{
                Original = $sb.Extent.Text
                Replacement = "`$$varName"
                VarEntry = $blockVarEntry
            }
            $deferredVarEntries += $blockVarEntry
            continue
        }

        # 尝试从父 AST 获取变量名（仅用于直接赋值的情况）
        $varName = $null
        $parent = $sb.Parent
        if ($parent -is [System.Management.Automation.Language.AssignmentStatementAst]) {
            # $sb = { ... } 形式
            $left = $parent.Left
            if ($left -is [System.Management.Automation.Language.VariableExpressionAst]) {
                $varName = $left.VariablePath.UserPath
            }
        }

        # 如果没有赋值目标（独立的 ScriptBlock 字面量作为值），生成唯一块名称
        if ($null -eq $varName) {
            # 生成唯一块名称（作为变量）
            $guid = [guid]::NewGuid().ToString("N").Substring(0, 8)
            $varName = "_block_$guid"
        }

        $blockVarEntry = [PSCustomObject]@{ Name = $varName; Scope = [VarScope]::Unspecified }

        # 标记为已处理，记录变量名
        $cfg.ProcessedScriptBlocks[$sb] = $varName

        # 创建独立子图
        $null = Convert-ScriptBlockDefinition -cfg $cfg -scriptBlockExprAst $sb -blockName $varName

        # 记录替换信息（只替换 ScriptBlock 本身，保留外围表达式如 .Invoke()）
        $deferredReplacements += @{
            Original = $sb.Extent.Text
            Replacement = "`$$varName"
            VarEntry = $blockVarEntry
        }
        $deferredVarEntries += $blockVarEntry
    }

    # 如果有 Deferred 类型的 ScriptBlock 需要替换
    if ($deferredReplacements.Count -gt 0) {
        # 检查是否整个 AST 就是一个独立的 ScriptBlock 字面量（如单独一行 { ... }）
        # 只有这种情况才直接创建节点
        $isStandaloneDeferred = $false
        if ($deferredBlocks.Count -eq 1) {
            $sb = $deferredBlocks[0]
            $parent = $sb.Parent
            # 检查父节点是否是 CommandExpressionAst，且祖父是 PipelineAst
            if ($parent -is [System.Management.Automation.Language.CommandExpressionAst]) {
                # 检查 CommandExpressionAst 的 Expression 是否就是这个 ScriptBlock
                if ($parent.Expression -eq $sb) {
                    $grandParent = $parent.Parent
                    # 检查是否是独立的 Pipeline（只有一个元素且就是这个 CommandExpression）
                    if ($grandParent -is [System.Management.Automation.Language.PipelineAst] -and
                        $grandParent.PipelineElements.Count -eq 1 -and
                        $grandParent.PipelineElements[0] -eq $parent -and
                        $grandParent -eq $ast) {
                        $isStandaloneDeferred = $true
                    }
                }
            }
        }

        if ($isStandaloneDeferred) {
            # 独立的 ScriptBlock 字面量，直接创建节点
            $r = $deferredReplacements[0]
            $pipeNode = Add-Node -cfg $cfg -type "PipelineElement" -text $r.Replacement -line $ast.Extent.StartLineNumber -ast $ast
            Add-VarToNode -node $pipeNode -varEntry $r.VarEntry -accessType "Read"
            if ($null -ne $prevNodeRef.Value) {
                Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $pipeNode.Id
            }
            $prevNodeRef.Value = $pipeNode

            return @{
                ModifiedText = $null
                ScriptBlockVarEntries = @()
                InvokeOnlyExpanded = $true
            }
        }

        # 否则，返回修改后的文本（保留 .Invoke() 等外围表达式）
        $modifiedText = $ast.Extent.Text
        foreach ($r in $deferredReplacements) {
            $modifiedText = $modifiedText.Replace($r.Original, $r.Replacement)
        }

        return @{
            ModifiedText = $modifiedText
            ScriptBlockVarEntries = $deferredVarEntries
            InvokeOnlyExpanded = $false
        }
    }

    # 处理 CmdletInvoke 类型（Invoke-Command -ScriptBlock { }）：直接创建调用节点（无 BlockDef）
    if ($cmdletInvokeBlocks.Count -gt 0) {
        foreach ($sb in $cmdletInvokeBlocks) {
            # 检查是否已处理过
            if ($cfg.ProcessedScriptBlocks.ContainsKey($sb)) {
                continue
            }

            # 生成唯一块名称（作为变量）
            $guid = [guid]::NewGuid().ToString("N").Substring(0, 8)
            $blockName = "_block_$guid"
            $blockVarEntry = [PSCustomObject]@{ Name = $blockName; Scope = [VarScope]::Unspecified }

            # 标记为已处理，记录变量名
            $cfg.ProcessedScriptBlocks[$sb] = $blockName

            # 【修改】不再创建 BlockDef 节点，只创建独立子图
            $null = Convert-ScriptBlockDefinition -cfg $cfg -scriptBlockExprAst $sb -blockName $blockName

            # 获取完整的 cmdlet 调用文本，将 ScriptBlock 替换为变量引用
            $parent = $sb.Parent
            $cmdAst = $null
            if ($parent -is [System.Management.Automation.Language.CommandAst]) {
                $cmdAst = $parent
            } elseif ($parent -is [System.Management.Automation.Language.CommandParameterAst]) {
                $cmdAst = $parent.Parent
            }

            if ($null -ne $cmdAst) {
                # 替换 ScriptBlock 为变量引用
                $cmdText = $cmdAst.Extent.Text
                $sbText = $sb.Extent.Text
                $modifiedCmdText = $cmdText.Replace($sbText, "`$$blockName")

                # 【修改】直接创建 PipelineElement 节点（调用节点），无 BlockDef
                $pipeNode = Add-Node -cfg $cfg -type "PipelineElement" -text $modifiedCmdText -line $cmdAst.Extent.StartLineNumber -ast $cmdAst
                Mark-PipelineCmdletNode -Node $pipeNode -ElementAst $cmdAst
                Add-VarToNode -node $pipeNode -varEntry $blockVarEntry -accessType "Read"
                if ($null -ne $prevNodeRef.Value) {
                    Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $pipeNode.Id
                }

                $prevNodeRef.Value = $pipeNode
            }
        }

        # CmdletInvoke 类型处理完成后，整个语句已经被处理
        return @{
            ModifiedText = $null
            ScriptBlockVarEntries = @()
            InvokeOnlyExpanded = $true
        }
    }

    # 处理 InvokeOnly 类型（& { } 或 . { }）：创建独立子图并返回替换信息
    # 【修改】不再直接创建 PipelineElement 节点，而是返回修改后的文本让调用方处理
    # 这样可以正确处理嵌套在赋值语句或其他表达式中的 InvokeOnly ScriptBlock
    if ($invokeOnlyBlocks.Count -gt 0) {
        $invokeOnlyReplacements = @()
        $invokeOnlyVarEntries = @()

        foreach ($sb in $invokeOnlyBlocks) {
            # 检查是否已处理过
            if ($cfg.ProcessedScriptBlocks.ContainsKey($sb)) {
                # 已处理过，使用已有的变量名记录替换信息
                $blockName = $cfg.ProcessedScriptBlocks[$sb]
                $blockVarEntry = [PSCustomObject]@{ Name = $blockName; Scope = [VarScope]::Unspecified }

                # 获取调用操作符（& 或 .）
                $parent = $sb.Parent
                $invokeOp = if ($parent -is [System.Management.Automation.Language.CommandAst]) {
                    if ($parent.InvocationOperator -eq [System.Management.Automation.Language.TokenKind]::Dot) { "." } else { "&" }
                } else { "&" }

                $invokeOnlyReplacements += @{
                    Original = $parent.Extent.Text  # 替换整个 & { } 或 . { }
                    Replacement = "$invokeOp `$$blockName"
                    VarEntry = $blockVarEntry
                }
                $invokeOnlyVarEntries += $blockVarEntry
                continue
            }

            # 生成唯一块名称（作为变量）
            $guid = [guid]::NewGuid().ToString("N").Substring(0, 8)
            $blockName = "_block_$guid"
            $blockVarEntry = [PSCustomObject]@{ Name = $blockName; Scope = [VarScope]::Unspecified }

            # 标记为已处理，记录变量名
            $cfg.ProcessedScriptBlocks[$sb] = $blockName

            # 创建独立子图
            $null = Convert-ScriptBlockDefinition -cfg $cfg -scriptBlockExprAst $sb -blockName $blockName

            # 获取调用操作符（& 或 .）
            $parent = $sb.Parent
            $invokeOp = if ($parent -is [System.Management.Automation.Language.CommandAst]) {
                if ($parent.InvocationOperator -eq [System.Management.Automation.Language.TokenKind]::Dot) { "." } else { "&" }
            } else { "&" }

            # 记录替换信息
            $invokeOnlyReplacements += @{
                Original = $parent.Extent.Text  # 替换整个 & { } 或 . { }
                Replacement = "$invokeOp `$$blockName"
                VarEntry = $blockVarEntry
            }
            $invokeOnlyVarEntries += $blockVarEntry
        }

        # 检查是否整个 AST 就是一个 InvokeOnly 调用（如独立的 & { }）
        # 只有这种情况才需要直接创建节点
        $isStandaloneInvoke = $false
        if ($invokeOnlyBlocks.Count -eq 1) {
            $sb = $invokeOnlyBlocks[0]
            $parent = $sb.Parent
            if ($parent -is [System.Management.Automation.Language.CommandAst] -and $parent -eq $ast) {
                $isStandaloneInvoke = $true
            }
            # 也检查 ast 是否是包含该 CommandAst 的 PipelineAst
            if ($ast -is [System.Management.Automation.Language.PipelineAst] -and
                $ast.PipelineElements.Count -eq 1 -and
                $ast.PipelineElements[0] -eq $parent) {
                $isStandaloneInvoke = $true
            }
        }

        if ($isStandaloneInvoke) {
            # 独立的 & { } 或 . { }，直接创建节点
            $r = $invokeOnlyReplacements[0]
            $pipeNode = Add-Node -cfg $cfg -type "PipelineElement" -text $r.Replacement -line $ast.Extent.StartLineNumber -ast $ast
            Add-VarToNode -node $pipeNode -varEntry $r.VarEntry -accessType "Read"
            if ($null -ne $prevNodeRef.Value) {
                Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $pipeNode.Id
            }
            $prevNodeRef.Value = $pipeNode

            return @{
                ModifiedText = $null
                ScriptBlockVarEntries = @()
                InvokeOnlyExpanded = $true
            }
        }

        # 否则，返回修改后的文本让调用方创建节点
        $modifiedText = $ast.Extent.Text
        foreach ($r in $invokeOnlyReplacements) {
            $modifiedText = $modifiedText.Replace($r.Original, $r.Replacement)
        }

        return @{
            ModifiedText = $modifiedText
            ScriptBlockVarEntries = $invokeOnlyVarEntries
            InvokeOnlyExpanded = $false  # 改为 false，让调用方创建节点
        }
    }

    # 如果没有 Immediate 类型也没有 PipelineValue 类型的 ScriptBlock，返回 null
    if ($immediateBlocks.Count -eq 0 -and $pipelineValueBlocks.Count -eq 0) {
        return $null
    }

    # 按位置倒序排列（从后往前处理，避免文本替换时位置偏移）
    $sortedBlocks = $immediateBlocks | Sort-Object { $_.Extent.StartOffset } -Descending

    # 记录替换信息
    $replacements = @()
    $scriptBlockVarEntries = @()

    foreach ($sb in $sortedBlocks) {
        # 检查是否已处理过
        if ($cfg.ProcessedScriptBlocks.ContainsKey($sb)) {
            # 已处理过，使用已有的变量名记录替换信息
            $blockName = $cfg.ProcessedScriptBlocks[$sb]
            $sbVarEntry = [PSCustomObject]@{ Name = $blockName; Scope = [VarScope]::Unspecified }

            # 记录替换信息
            $replacements += @{
                Original = $sb.Extent.Text
                Replacement = "`$$blockName"
            }
            $scriptBlockVarEntries += $sbVarEntry
            continue
        }

        # 生成唯一块名称
        $guid = [guid]::NewGuid().ToString("N").Substring(0, 8)
        $blockName = "_block_$guid"
        $sbVarEntry = [PSCustomObject]@{ Name = $blockName; Scope = [VarScope]::Unspecified }

        # 标记为已处理，记录变量名
        $cfg.ProcessedScriptBlocks[$sb] = $blockName

        # 【修改】不再创建 BlockDef 节点，只创建独立子图
        $null = Convert-ScriptBlockDefinition -cfg $cfg -scriptBlockExprAst $sb -blockName $blockName

        # 记录替换信息
        $originalText = $sb.Extent.Text
        $replacementText = "`$$blockName"

        $replacements += @{
            Original = $originalText
            Replacement = $replacementText
        }
        $scriptBlockVarEntries += $sbVarEntry
    }

    # 修改原始文本：替换 Immediate 类型和 PipelineValue 类型的 ScriptBlock
    $modifiedText = $ast.Extent.Text
    foreach ($r in $replacements) {
        $modifiedText = $modifiedText.Replace($r.Original, $r.Replacement)
    }
    # 也替换 PipelineValue 类型的 ScriptBlock
    foreach ($r in $pipelineValueReplacements) {
        $modifiedText = $modifiedText.Replace($r.Original, $r.Replacement)
        $scriptBlockVarEntries += $r.VarEntry
    }

    return @{
        ModifiedText = $modifiedText
        ScriptBlockVarEntries = $scriptBlockVarEntries
        InvokeOnlyExpanded = $false
    }
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

    $pipelinesWithDepth = $nestedPipelines | ForEach-Object {
        $depth = 0
        $ancestor = $_.Parent
        while ($null -ne $ancestor -and $ancestor -ne $ast) {
            if ($ancestor -is [System.Management.Automation.Language.PipelineAst] -and $ancestor.PipelineElements.Count -gt 1) {
                $depth++
            }
            $ancestor = $ancestor.Parent
        }
        [PSCustomObject]@{
            Pipeline = $_
            Depth = $depth
        }
    }

    $sortedPipelines = $pipelinesWithDepth | Sort-Object @{Expression={$_.Depth}; Descending=$true}, @{Expression={$_.Pipeline.Extent.StartOffset}; Descending=$true}

    $pipelineReplacements = @{}
    $pipeVarEntries = @()

    foreach ($pipeInfo in $sortedPipelines) {
        $pipeline = $pipeInfo.Pipeline
        $guid = [guid]::NewGuid().ToString("N").Substring(0, 8)
        $pipeVar = "_pipe_$guid"
        $pipeVarEntry = [PSCustomObject]@{ Name = $pipeVar; Scope = [VarScope]::Unspecified }

        $elements = $pipeline.PipelineElements
        $lastIndex = $elements.Count - 1

        for ($i = 0; $i -lt $elements.Count - 1; $i++) {
            $element = $elements[$i]
            $elementText = $element.Extent.Text
            $elementVarEntries = @()

            foreach ($innerPipeline in $pipelineReplacements.Keys) {
                if ($elementText.Contains($pipelineReplacements[$innerPipeline].Original)) {
                    $elementText = $elementText.Replace(
                        $pipelineReplacements[$innerPipeline].Original,
                        $pipelineReplacements[$innerPipeline].Replacement
                    )
                    $elementVarEntries += $pipelineReplacements[$innerPipeline].PipeVarEntry
                }
            }

            $expandedForEach = $false
            if ($i -gt 0 -and $element -is [System.Management.Automation.Language.CommandAst]) {
                $foreachExpansion = Expand-ForEachObjectPipelineElement -cfg $cfg -CommandAst $element -prevNodeRef $prevNodeRef -PipeVarName $pipeVar -PipeVarEntry $pipeVarEntry -IncomingEdgeLabel 'Pipeline'
                if ($foreachExpansion.Expanded) {
                    $expandedForEach = $true
                }
            }

            if ($expandedForEach) {
                continue
            }

            $sbExpansion = Expand-NestedScriptBlocks -cfg $cfg -ast $element -prevNodeRef $prevNodeRef
            if ($null -ne $sbExpansion -and -not $sbExpansion.InvokeOnlyExpanded -and $null -ne $sbExpansion.ModifiedText) {
                $nestedSBs = Get-AllNestedScriptBlocks -ast $element
                foreach ($sb in $nestedSBs) {
                    if ($cfg.ProcessedScriptBlocks.ContainsKey($sb)) {
                        $varName = $cfg.ProcessedScriptBlocks[$sb]
                        $elementText = $elementText.Replace($sb.Extent.Text, "`$$varName")
                        $elementVarEntries += [PSCustomObject]@{ Name = $varName; Scope = [VarScope]::Unspecified }
                    }
                }
            }

            if ($i -eq 0) {
                $nodeText = $elementText
            } else {
                $nodeText = "`$$pipeVar | " + $elementText
            }

            $pipeNode = Add-Node -cfg $cfg -type "PipelineElement" -text $nodeText -line $element.Extent.StartLineNumber -ast $element
            Mark-PipelineCmdletNode -Node $pipeNode -ElementAst $element

            foreach ($varEntry in $elementVarEntries) {
                Add-VarToNode -node $pipeNode -varEntry $varEntry -accessType "Read"
            }

            if ($i -eq 0) {
                Add-VarToNode -node $pipeNode -varEntry $pipeVarEntry -accessType "Write"
            } else {
                Add-VarToNode -node $pipeNode -varEntry $pipeVarEntry -accessType "Both"
            }

            if ($null -ne $prevNodeRef.Value) {
                if ($i -gt 0) {
                    Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $pipeNode.Id -label "Pipeline"
                } else {
                    Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $pipeNode.Id
                }
            }
            $prevNodeRef.Value = $pipeNode
        }

        $lastElement = $elements[$lastIndex]
        $lastElementText = $lastElement.Extent.Text
        $lastElementVarEntries = @()

        foreach ($innerPipeline in $pipelineReplacements.Keys) {
            if ($lastElementText.Contains($pipelineReplacements[$innerPipeline].Original)) {
                $lastElementText = $lastElementText.Replace(
                    $pipelineReplacements[$innerPipeline].Original,
                    $pipelineReplacements[$innerPipeline].Replacement
                )
                $lastElementVarEntries += $pipelineReplacements[$innerPipeline].PipeVarEntry
            }
        }

        $expandedLastForEach = $false
        if ($lastIndex -gt 0 -and $lastElement -is [System.Management.Automation.Language.CommandAst]) {
            $foreachExpansion = Expand-ForEachObjectPipelineElement -cfg $cfg -CommandAst $lastElement -prevNodeRef $prevNodeRef -PipeVarName $pipeVar -PipeVarEntry $pipeVarEntry -IncomingEdgeLabel 'Pipeline'
            if ($foreachExpansion.Expanded) {
                $expandedLastForEach = $true
            }
        }

        if (-not $expandedLastForEach) {
            $sbExpansion = Expand-NestedScriptBlocks -cfg $cfg -ast $lastElement -prevNodeRef $prevNodeRef
            if ($null -ne $sbExpansion -and -not $sbExpansion.InvokeOnlyExpanded -and $null -ne $sbExpansion.ModifiedText) {
                $nestedSBs = Get-AllNestedScriptBlocks -ast $lastElement
                foreach ($sb in $nestedSBs) {
                    if ($cfg.ProcessedScriptBlocks.ContainsKey($sb)) {
                        $varName = $cfg.ProcessedScriptBlocks[$sb]
                        $lastElementText = $lastElementText.Replace($sb.Extent.Text, "`$$varName")
                        $lastElementVarEntries += [PSCustomObject]@{ Name = $varName; Scope = [VarScope]::Unspecified }
                    }
                }
            }
        }

        $originalText = $pipeline.Extent.Text
        $nestedSBsInPipeline = Get-AllNestedScriptBlocks -ast $pipeline
        foreach ($sb in $nestedSBsInPipeline) {
            if ($cfg.ProcessedScriptBlocks.ContainsKey($sb)) {
                $varName = $cfg.ProcessedScriptBlocks[$sb]
                $originalText = $originalText.Replace($sb.Extent.Text, "`$$varName")
            }
        }
        foreach ($innerPipeline in $pipelineReplacements.Keys) {
            $innerR = $pipelineReplacements[$innerPipeline]
            $originalText = $originalText.Replace($innerR.Original, $innerR.Replacement)
        }

        $replacementText = if ($expandedLastForEach) { "`$$pipeVar" } else { "`$$pipeVar | " + $lastElementText }

        $pipelineReplacements[$pipeline] = @{
            Original = $originalText
            Replacement = $replacementText
            PipeVarEntry = $pipeVarEntry
            LastElementVarEntries = $lastElementVarEntries
        }
        $pipeVarEntries += $pipeVarEntry
    }

    $modifiedText = $ast.Extent.Text

    $allNestedSBs = Get-AllNestedScriptBlocks -ast $ast
    foreach ($sb in $allNestedSBs) {
        if ($cfg.ProcessedScriptBlocks.ContainsKey($sb)) {
            $varName = $cfg.ProcessedScriptBlocks[$sb]
            $modifiedText = $modifiedText.Replace($sb.Extent.Text, "`$$varName")
        }
    }

    foreach ($pipeInfo in $sortedPipelines) {
        $pipeline = $pipeInfo.Pipeline
        $r = $pipelineReplacements[$pipeline]
        $modifiedText = $modifiedText.Replace($r.Original, $r.Replacement)
    }

    $allScriptBlockVarEntries = @()
    foreach ($pipeline in $pipelineReplacements.Keys) {
        $allScriptBlockVarEntries += $pipelineReplacements[$pipeline].LastElementVarEntries
    }
    foreach ($sb in $allNestedSBs) {
        if ($cfg.ProcessedScriptBlocks.ContainsKey($sb)) {
            $varName = $cfg.ProcessedScriptBlocks[$sb]
            $allScriptBlockVarEntries += [PSCustomObject]@{ Name = $varName; Scope = [VarScope]::Unspecified }
        }
    }

    return @{
        ModifiedText = $modifiedText
        PipeVarEntries = $pipeVarEntries
        ScriptBlockVarEntries = $allScriptBlockVarEntries
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
            $condNode = Add-Node -cfg $cfg -type "Condition" -text "[bool]($($expansion.ModifiedText))" -line $conditionAst.Extent.StartLineNumber -ast $conditionAst
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
            $condNode = Add-Node -cfg $cfg -type "Condition" -text "[bool]($($conditionAst.Extent.Text))" -line $conditionAst.Extent.StartLineNumber -ast $conditionAst

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

# 替换文本中的管道当前项变量引用（$_ / $PSItem）
function Replace-PipelineCurrentVariable {
    param(
        [string]$text,
        [string]$replacementVar,
        [switch]$IncludePSItem
    )

    if ($null -eq $text) { return $text }

    # 注意：-replace 替换字符串中 $ 需要用 $$ 转义（.NET 正则替换语法）
    $result = $text -replace '\$_(?![a-zA-Z0-9_])', ('$$' + $replacementVar)
    if ($IncludePSItem) {
        $result = $result -replace '\$PSItem(?![a-zA-Z0-9_])', ('$$' + $replacementVar)
    }

    return $result
}

# 将指定范围内的 CFG 节点中的当前项变量引用替换为 $currentVar
# 同时更新变量追踪信息（VarsRead/VarsWritten 中 _ / PSItem -> $currentVar）
function Replace-PipelineCurrentInNodes {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$cfg,
        [array]$nodes,
        [int]$startIndex,
        [string]$currentVar,
        [switch]$IncludePSItem
    )

    $currentVarEntry = [PSCustomObject]@{ Name = $currentVar; Scope = [VarScope]::Unspecified }
    $pipelineVarNames = @("_")
    if ($IncludePSItem) {
        $pipelineVarNames += @("PSItem")
    }

    # 预构建索引：用于快速判断“属于嵌套子图的节点”
    # 背景：FuncEnd/BlockEnd 节点会先于子图主体创建（Start/End 连续），导致“按节点数组区间跳过子图”失效。
    # 这里改为：在遇到 FuncStart/BlockStart 时，根据 CFG Edges 计算其可达节点集合，并在替换期跳过这些节点。
    $nodeById = @{}
    foreach ($n in $nodes) {
        if ($null -ne $n -and $null -ne $n.Id) {
            $nodeById[[int]$n.Id] = $n
        }
    }

    $adj = @{}
    if ($cfg.Edges) {
        foreach ($e in $cfg.Edges) {
            if ($null -eq $e) { continue }
            $from = [int]$e.From
            if (-not $adj.ContainsKey($from)) {
                $adj[$from] = [System.Collections.Generic.List[int]]::new()
            }
            $adj[$from].Add([int]$e.To)
        }
    }

    # nodeId -> $true
    $skipNodeIds = @{}

    function Add-SubgraphSkipIds {
        param([int]$StartId)

        $q = [System.Collections.Generic.Queue[int]]::new()
        $visited = @{}
        $q.Enqueue($StartId)

        while ($q.Count -gt 0) {
            $id = $q.Dequeue()
            if ($visited.ContainsKey($id)) { continue }
            $visited[$id] = $true
            $skipNodeIds[$id] = $true

            $n = $nodeById[$id]
            if ($n -and $n.Type -in @("FuncEnd", "BlockEnd", "End", "MainEnd")) {
                continue
            }

            if ($adj.ContainsKey($id)) {
                foreach ($to in $adj[$id]) {
                    if (-not $visited.ContainsKey($to)) {
                        $q.Enqueue($to)
                    }
                }
            }
        }
    }

    for ($i = $startIndex; $i -lt $nodes.Count; $i++) {
        $node = $nodes[$i]

        # 跳过函数/脚本块子图，避免将外层 $_ 替换污染到嵌套输入上下文
        # 典型场景：process 块内部引用新的 ScriptBlock（如 ForEach-Object 的参数脚本块）
        if ($node.Type -in @("FuncStart", "BlockStart")) {
            Add-SubgraphSkipIds -StartId ([int]$node.Id)
        }

        if ($skipNodeIds.ContainsKey([int]$node.Id)) {
            continue
        }

        # 替换 Text 中的变量引用
        $newText = Replace-PipelineCurrentVariable -text $node.Text -replacementVar $currentVar -IncludePSItem:$IncludePSItem
        if ($newText -ne $node.Text) {
            $node.Text = $newText
        }

        # 替换 VarsRead 中的 _ / PSItem
        $hasPipelineRead = $false
        foreach ($name in $pipelineVarNames) {
            if ($node.VarsRead | Where-Object { $_.Name -ieq $name }) {
                $hasPipelineRead = $true
                break
            }
        }
        if ($hasPipelineRead) {
            $node.VarsRead = @($node.VarsRead | Where-Object {
                $keep = $true
                foreach ($name in $pipelineVarNames) {
                    if ($_.Name -ieq $name) {
                        $keep = $false
                        break
                    }
                }
                $keep
            })
            Add-VarToNode -node $node -varEntry $currentVarEntry -accessType "Read"
        }

        # 替换 VarsWritten 中的 _ / PSItem
        $hasPipelineWrite = $false
        foreach ($name in $pipelineVarNames) {
            if ($node.VarsWritten | Where-Object { $_.Name -ieq $name }) {
                $hasPipelineWrite = $true
                break
            }
        }
        if ($hasPipelineWrite) {
            $node.VarsWritten = @($node.VarsWritten | Where-Object {
                $keep = $true
                foreach ($name in $pipelineVarNames) {
                    if ($_.Name -ieq $name) {
                        $keep = $false
                        break
                    }
                }
                $keep
            })
            Add-VarToNode -node $node -varEntry $currentVarEntry -accessType "Write"
        }
    }
}

# 兼容旧命名：仅替换 $_，但同步支持 $PSItem
function Replace-UnderscoreVariable {
    param([string]$text, [string]$replacementVar)
    return Replace-PipelineCurrentVariable -text $text -replacementVar $replacementVar -IncludePSItem
}

# 兼容旧命名：将节点中的 $_/$PSItem 替换为指定变量
function Replace-UnderscoreInNodes {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$cfg,
        [array]$nodes,
        [int]$startIndex,
        [string]$currentVar
    )
    Replace-PipelineCurrentInNodes -cfg $cfg -nodes $nodes -startIndex $startIndex -currentVar $currentVar -IncludePSItem
}

# 生成 switch case 的可执行比较表达式
function Build-SwitchCaseCondition {
    param($clauseConditionAst, [string]$currentVar, [string[]]$switchFlags)

    if ($null -eq $clauseConditionAst) { return "`$true" }

    $isCaseSensitive = $switchFlags -contains "-CaseSensitive"
    $isWildcard = $switchFlags -contains "-Wildcard"
    $isRegex = $switchFlags -contains "-Regex"

    $operator = if ($isWildcard) {
        if ($isCaseSensitive) { "-clike" } else { "-like" }
    } elseif ($isRegex) {
        if ($isCaseSensitive) { "-cmatch" } else { "-match" }
    } else {
        if ($isCaseSensitive) { "-ceq" } else { "-eq" }
    }

    if ($clauseConditionAst -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
        # ScriptBlock 条件: { $_ -gt 5 } → 提取内部代码，替换 $_
        $bodyStatements = $clauseConditionAst.ScriptBlock.EndBlock.Statements
        $bodyText = ($bodyStatements | ForEach-Object { $_.Extent.Text }) -join "; "
        $replaced = Replace-UnderscoreVariable -text $bodyText -replacementVar $currentVar
        return "[bool]($replaced)"
    } else {
        return "[bool](`$$currentVar $operator $($clauseConditionAst.Extent.Text))"
    }
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
    $currentVar = "__sw_${guid}_current"

    # 预定义内部变量的条目（用于手动设置 VarsRead/VarsWritten）
    $collectionVarEntry = [PSCustomObject]@{ Name = $collectionVar; Scope = [VarScope]::Unspecified }
    $indexVarEntry = [PSCustomObject]@{ Name = $indexVar; Scope = [VarScope]::Unspecified }
    $currentVarEntry = [PSCustomObject]@{ Name = $currentVar; Scope = [VarScope]::Unspecified }
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
        $initText = "`$$collectionVar = @(" + $conditionExpansion.ModifiedText + "); `$$indexVar = 0"
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
        $initText = "`$$collectionVar = @($switchConditionText); `$$indexVar = 0"
        $initNode = Add-Node -cfg $cfg -type "SwitchInit" -text $initText -line $switchAst.Condition.Extent.StartLineNumber -ast $switchAst.Condition
        Add-Edge -cfg $cfg -from $switchStart.Id -to $initNode.Id
    }
    # 手动追加内部变量的写入
    Add-VarToNode -node $initNode -varEntry $collectionVarEntry -accessType "Write"
    Add-VarToNode -node $initNode -varEntry $indexVarEntry -accessType "Write"

    # 5. 创建 SwitchCondition（判断是否还有元素）
    # VarsRead: $__sw_xxx_idx, $__sw_xxx（手动设置）
    # ast = $null，ownerAst = $switchAst 用于 try/catch 嵌套判断
    $condText = "[bool](`$$indexVar -lt `$$collectionVar.Count)"
    $conditionNode = Add-Node -cfg $cfg -type "SwitchCondition" -text $condText -line $switchAst.Extent.StartLineNumber -ast $null -ownerAst $switchAst
    # 清空自动分析的结果，手动设置内部变量的读取
    $conditionNode.VarsRead = @($indexVarEntry, $collectionVarEntry)
    $conditionNode.VarsWritten = @()
    Add-Edge -cfg $cfg -from $initNode.Id -to $conditionNode.Id

    # 6. 创建 SwitchEnd（提前创建，供 break 和循环退出使用）
    $switchEnd = Add-Node -cfg $cfg -type "SwitchEnd" -text "End Switch" -line $switchAst.Extent.EndLineNumber -ast $null
    Add-Edge -cfg $cfg -from $conditionNode.Id -to $switchEnd.Id -label "False"

    # 7. 创建 SwitchBind（绑定当前元素到 $currentVar 和 $_）
    # VarsRead: $__sw_xxx, $__sw_xxx_idx
    # VarsWritten: $__sw_xxx_current
    # ast = $null，ownerAst = $switchAst 用于 try/catch 嵌套判断
    $bindText = "`$$currentVar = `$$collectionVar[`$$indexVar]"
    $bindNode = Add-Node -cfg $cfg -type "SwitchBind" -text $bindText -line $switchAst.Extent.StartLineNumber -ast $null -ownerAst $switchAst
    $bindNode.VarsRead = @($collectionVarEntry, $indexVarEntry)
    $bindNode.VarsWritten = @($currentVarEntry)
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
        $caseLineNumber = if ($null -ne $clause.Item1) { $clause.Item1.Extent.StartLineNumber } else { $switchAst.Extent.StartLineNumber }
        # 使用 Build-SwitchCaseCondition 生成可执行的比较表达式
        $caseCondText = Build-SwitchCaseCondition -clauseConditionAst $clause.Item1 -currentVar $currentVar -switchFlags $switchFlags
        $caseCondNode = Add-Node -cfg $cfg -type "CaseCondition" -text $caseCondText -line $caseLineNumber -ast $clause.Item1
        # 修正变量追踪：移除 $_ 的读取，添加 $currentVar 的读取
        $caseCondNode.VarsRead = @($caseCondNode.VarsRead | Where-Object { $_.Name -ne "_" })
        Add-VarToNode -node $caseCondNode -varEntry $currentVarEntry -accessType "Read"

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
        $bodyNodeCountBefore = $cfg.Nodes.Count

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

        # 10.3.1 将 CaseBody 中所有新生成节点的 $_ 替换为 $currentVar
        Replace-UnderscoreInNodes -cfg $cfg -nodes $cfg.Nodes -startIndex $bodyNodeCountBefore -currentVar $currentVar

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
        $defaultNodeCountBefore = $cfg.Nodes.Count

        foreach ($statement in $switchAst.Default.Statements) {
            $hasTerminator = Convert-AstNode -cfg $cfg -node $statement -prevNodeRef ([ref]$branchPrev) -endNodeRef $endNodeRef -loopContext $loopContext -switchContext $currentSwitchContext
            if ($hasTerminator) {
                $defaultHasTerminator = $true
                break
            }
        }

        # 将 Default body 中所有新生成节点的 $_ 替换为 $currentVar
        Replace-UnderscoreInNodes -cfg $cfg -nodes $cfg.Nodes -startIndex $defaultNodeCountBefore -currentVar $currentVar

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
    $hasProcessBlock = ($null -ne $funcAst.Body -and $null -ne $funcAst.Body.ProcessBlock -and $funcAst.Body.ProcessBlock.Statements.Count -gt 0)
    $funcStart | Add-Member -NotePropertyName "HasProcessBlock" -NotePropertyValue $hasProcessBlock -Force
    $funcStart | Add-Member -NotePropertyName "ProcessInputVar" -NotePropertyValue "__proc_input" -Force
    $funcEnd   = Add-Node -cfg $cfg -type "FuncEnd"   -text "End function $funcName"        -line $funcAst.Extent.EndLineNumber   -ast $null

    $prevNode = $funcStart
    $prev = [ref]$prevNode
    $endRef = [ref]$funcEnd

    # 使用通用函数处理函数体的 ScriptBlock
    if ($null -ne $funcAst.Body) {
        $null = Convert-ScriptBlockBody -cfg $cfg -scriptBlockAst $funcAst.Body -prevNodeRef $prev -endNodeRef $endRef -paramNodeType "FuncParams"
    }

    # 如果最后一个节点不是 FuncEnd，并且不是显式终止语句，则连接到 FuncEnd（隐式 return）
    # 注意：当函数体中出现 exit 且被 try/finally 包裹时，finally 的出口有可能已经被特殊处理为
    #       直接连到全局 Script End（Type="End"）。这种情况下不能再从 Script End 连一条边到
    #       FuncEnd，否则就会出现"FuncEnd 接在 Script End 后面"的错误。
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
        default {
            if ($null -eq $loopAst.Condition) { "`$true" }
            else { "[bool]($($loopAst.Condition.Extent.Text))" }
        }
    }
}

function Get-ExitLabel {
    param($loopAst)
    # do-until: 条件为真时退出循环
    # 其他循环: 条件为假时退出循环
    if ($loopAst -is [System.Management.Automation.Language.DoUntilStatementAst]) {
        return "True"
    }
    return "False"
}

function Get-LoopEndText {
    param($loopAst)
    $typeName = $loopAst.GetType().Name -replace 'StatementAst$'
    "End $typeName"
}

function Get-LoopBackLabel {
    param($loopAst)
    # do-until: 条件为假时继续循环
    # 其他循环: 条件为真时继续循环
    if ($loopAst -is [System.Management.Automation.Language.DoUntilStatementAst]) {
        return "False"
    }
    return "True"
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
        $condText = "[bool](`$$indexVar -lt `$$collectionVar.Count)"
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
            $conditionNode = Add-Node -cfg $cfg -type "Condition" -text "[bool]($($conditionExpansion.ModifiedText))" -line $conditionLine -ast $conditionAst
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
            $conditionNode = Add-Node -cfg $cfg -type "Condition" -text "[bool]($($conditionExpansion.ModifiedText))" -line $conditionLine -ast $conditionAst
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
    $firstBodyNodeId = $null
    foreach ($statement in $loopAst.Body.Statements) {
        $hasReturn = Convert-AstNode -cfg $cfg -node $statement -prevNodeRef ([ref]$currentNode) -endNodeRef $endNodeRef -loopContext $loopContext -switchContext $null

        # 记录第一个 body 节点的 ID（用于设置 "True" 标签）
        if ($null -eq $firstBodyNodeId -and $currentNode.Id -ne $conditionNode.Id) {
            $firstBodyNodeId = $currentNode.Id
            # 找到从 conditionNode 到 firstBodyNode 的边，添加 "True" 标签
            foreach ($edge in $cfg.Edges) {
                if ($edge.From -eq $conditionNode.Id -and $edge.To -eq $firstBodyNodeId) {
                    $edge.Label = "True"
                    break
                }
            }
        }

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

# 处理 AssignmentStatementAst 节点
function Convert-AssignmentAstNode {
    param(
        [hashtable]$cfg,
        [System.Management.Automation.Language.AssignmentStatementAst]$assignAst,
        [ref]$prevNodeRef
    )

    if ($assignAst.Right -is [System.Management.Automation.Language.PipelineAst] -and
        $assignAst.Right.PipelineElements.Count -gt 1) {
        $leftText = $assignAst.Left.Extent.Text
        $operatorText = switch ($assignAst.Operator) {
            "Equals"           { "=" }
            "PlusEquals"       { "+=" }
            "MinusEquals"      { "-=" }
            "MultiplyEquals"   { "*=" }
            "DivideEquals"     { "/=" }
            "RemainderEquals"  { "%=" }
            default            { "=" }
        }

        $elements = $assignAst.Right.PipelineElements
        $lastIndex = $elements.Count - 1

        $guid = [guid]::NewGuid().ToString("N").Substring(0, 8)
        $pipeVarName = "_pipe_$guid"
        $pipeVarEntry = [PSCustomObject]@{ Name = $pipeVarName; Scope = [VarScope]::Unspecified }

        for ($i = 0; $i -lt $elements.Count; $i++) {
            $element = $elements[$i]
            $baseText = $element.Extent.Text
            $hasPipelineExpansion = $false
            $allVarEntries = @()

            $pipelineExpansion = Expand-NestedPipelines -cfg $cfg -ast $element -prevNodeRef $prevNodeRef
            if ($null -ne $pipelineExpansion) {
                $baseText = $pipelineExpansion.ModifiedText
                $allVarEntries += $pipelineExpansion.PipeVarEntries
                if ($null -ne $pipelineExpansion.ScriptBlockVarEntries) {
                    $allVarEntries += $pipelineExpansion.ScriptBlockVarEntries
                }
                $hasPipelineExpansion = $true
            }

            $expandedForEach = $false
            if ($i -gt 0 -and $element -is [System.Management.Automation.Language.CommandAst]) {
                $foreachExpansion = Expand-ForEachObjectPipelineElement -cfg $cfg -CommandAst $element -prevNodeRef $prevNodeRef -PipeVarName $pipeVarName -PipeVarEntry $pipeVarEntry -IncomingEdgeLabel 'Pipeline'
                if ($foreachExpansion.Expanded) {
                    $expandedForEach = $true
                    if ($i -eq $lastIndex) {
                        $assignText = "$leftText $operatorText `$$pipeVarName"
                        $assignNode = Add-Node -cfg $cfg -type $assignAst.GetType().Name -text $assignText -line $assignAst.Extent.StartLineNumber -ast $assignAst
                        Add-VarToNode -node $assignNode -varEntry $pipeVarEntry -accessType "Read"
                        if ($null -ne $prevNodeRef.Value) {
                            Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $assignNode.Id -label "Pipeline"
                        }
                        $prevNodeRef.Value = $assignNode
                    }
                }
            }

            if ($expandedForEach) {
                continue
            }

            if (-not $hasPipelineExpansion) {
                $sbExpansion = Expand-NestedScriptBlocks -cfg $cfg -ast $element -prevNodeRef $prevNodeRef
                if ($null -ne $sbExpansion -and -not $sbExpansion.InvokeOnlyExpanded -and $null -ne $sbExpansion.ModifiedText) {
                    $baseText = $sbExpansion.ModifiedText
                    if ($null -ne $sbExpansion.ScriptBlockVarEntries) {
                        $allVarEntries += $sbExpansion.ScriptBlockVarEntries
                    }
                }
            }
            else {
                $remainingSBs = Get-AllNestedScriptBlocks -ast $element
                foreach ($sb in $remainingSBs) {
                    if ($cfg.ProcessedScriptBlocks.ContainsKey($sb)) {
                        $varName = $cfg.ProcessedScriptBlocks[$sb]
                        $baseText = $baseText.Replace($sb.Extent.Text, "`$$varName")
                        $allVarEntries += [PSCustomObject]@{ Name = $varName; Scope = [VarScope]::Unspecified }
                    }
                }
            }

            if ($i -eq 0) {
                $nodeText = $baseText
            } elseif ($i -eq $lastIndex) {
                $nodeText = "$leftText $operatorText `$$pipeVarName | " + $baseText
            } else {
                $nodeText = "`$$pipeVarName | " + $baseText
            }

            $nodeAst = if ($i -eq $lastIndex) { $assignAst } else { $element }
            $pipeNode = Add-Node -cfg $cfg -type "PipelineElement" -text $nodeText -line $element.Extent.StartLineNumber -ast $nodeAst
            Mark-PipelineCmdletNode -Node $pipeNode -ElementAst $element

            foreach ($varEntry in $allVarEntries) {
                Add-VarToNode -node $pipeNode -varEntry $varEntry -accessType "Read"
            }

            if ($i -eq 0) {
                Add-VarToNode -node $pipeNode -varEntry $pipeVarEntry -accessType "Write"
            } elseif ($i -eq $lastIndex) {
                Add-VarToNode -node $pipeNode -varEntry $pipeVarEntry -accessType "Read"
            } else {
                Add-VarToNode -node $pipeNode -varEntry $pipeVarEntry -accessType "Both"
            }

            if ($null -ne $prevNodeRef.Value) {
                if ($hasPipelineExpansion -or $i -gt 0) {
                    Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $pipeNode.Id -label "Pipeline"
                } else {
                    Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $pipeNode.Id
                }
            }
            $prevNodeRef.Value = $pipeNode
        }
        return
    }

    $isDirectScriptBlockAssignment = $false
    $nestedScriptBlocks = Get-AllNestedScriptBlocks -ast $assignAst.Right
    foreach ($sb in $nestedScriptBlocks) {
        if ($cfg.ProcessedScriptBlocks.ContainsKey($sb)) {
            continue
        }

        $execType = Get-ScriptBlockExecutionType -scriptBlockExprAst $sb
        if ($execType -eq "Deferred") {
            $varName = $null
            $left = $assignAst.Left
            if ($left -is [System.Management.Automation.Language.VariableExpressionAst]) {
                $varName = $left.VariablePath.UserPath
            }

            $isDirectAssignment = $false
            if ($null -ne $varName) {
                $rightAst = $assignAst.Right
                if ($rightAst -is [System.Management.Automation.Language.CommandExpressionAst] -and
                    $rightAst.Expression -eq $sb) {
                    $isDirectAssignment = $true
                }
                elseif ($rightAst -is [System.Management.Automation.Language.PipelineAst] -and
                    $rightAst.PipelineElements.Count -eq 1) {
                    $element = $rightAst.PipelineElements[0]
                    if ($element -is [System.Management.Automation.Language.CommandExpressionAst] -and
                        $element.Expression -eq $sb) {
                        $isDirectAssignment = $true
                    }
                }
            }

            if ($isDirectAssignment) {
                $cfg.ProcessedScriptBlocks[$sb] = $varName
                $null = Convert-ScriptBlockDefinition -cfg $cfg -scriptBlockExprAst $sb -blockName $varName
                $isDirectScriptBlockAssignment = $true
            } else {
                $guid = [guid]::NewGuid().ToString("N").Substring(0, 8)
                $blockName = "_block_$guid"
                $cfg.ProcessedScriptBlocks[$sb] = $blockName
                $null = Convert-ScriptBlockDefinition -cfg $cfg -scriptBlockExprAst $sb -blockName $blockName
            }
        }
    }

    $modifiedText = $assignAst.Extent.Text
    $hasExpansion = $false
    $hasPipelineNodes = $false
    $finalVarEntries = @()

    $pipelineExpansion = Expand-NestedPipelines -cfg $cfg -ast $assignAst.Right -prevNodeRef $prevNodeRef
    if ($null -ne $pipelineExpansion) {
        $modifiedText = $modifiedText.Replace($assignAst.Right.Extent.Text, $pipelineExpansion.ModifiedText)
        $hasExpansion = $true
        $hasPipelineNodes = $true
        if ($null -ne $pipelineExpansion.PipeVarEntries) {
            $finalVarEntries += $pipelineExpansion.PipeVarEntries
        }
        if ($null -ne $pipelineExpansion.ScriptBlockVarEntries) {
            $finalVarEntries += $pipelineExpansion.ScriptBlockVarEntries
        }
    }

    if (-not $hasPipelineNodes) {
        $scriptBlockExpansion = Expand-NestedScriptBlocks -cfg $cfg -ast $assignAst.Right -prevNodeRef $prevNodeRef
        if ($null -ne $scriptBlockExpansion) {
            if ($null -ne $scriptBlockExpansion.ModifiedText) {
                $modifiedText = $modifiedText.Replace($assignAst.Right.Extent.Text, $scriptBlockExpansion.ModifiedText)
                $hasExpansion = $true
            }
            if ($null -ne $scriptBlockExpansion.ScriptBlockVarEntries) {
                $finalVarEntries += $scriptBlockExpansion.ScriptBlockVarEntries
            }
        }
    }

    if (-not $hasExpansion -and -not $isDirectScriptBlockAssignment) {
        foreach ($sb in (Get-AllNestedScriptBlocks -ast $assignAst.Right)) {
            if ($cfg.ProcessedScriptBlocks.ContainsKey($sb)) {
                $varName = $cfg.ProcessedScriptBlocks[$sb]
                $modifiedText = $modifiedText.Replace($sb.Extent.Text, "`$$varName")
                $finalVarEntries += [PSCustomObject]@{ Name = $varName; Scope = [VarScope]::Unspecified }
            }
        }
    }

    $currentNode = Add-Node -cfg $cfg -type $assignAst.GetType().Name -text $modifiedText -line $assignAst.Extent.StartLineNumber -ast $assignAst
    foreach ($varEntry in $finalVarEntries) {
        Add-VarToNode -node $currentNode -varEntry $varEntry -accessType "Read"
    }

    if ($null -ne $prevNodeRef.Value) {
        if ($hasPipelineNodes) {
            Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $currentNode.Id -label "Pipeline"
        } else {
            Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $currentNode.Id
        }
    }
    $prevNodeRef.Value = $currentNode
}
# 处理 PipelineAst 节点
function Convert-PipelineAstNode {
    param(
        [hashtable]$cfg,
        [System.Management.Automation.Language.PipelineAst]$pipelineAst,
        [ref]$prevNodeRef,
        $endNodeRef = $null,
        $loopContext = $null,
        $switchContext = $null
    )

    $elements = $pipelineAst.PipelineElements
    $lastIndex = $elements.Count - 1

    $guid = [guid]::NewGuid().ToString("N").Substring(0, 8)
    $pipeVarName = "_pipe_$guid"
    $pipeVarEntry = [PSCustomObject]@{ Name = $pipeVarName; Scope = [VarScope]::Unspecified }

    for ($i = 0; $i -lt $elements.Count; $i++) {
        $element = $elements[$i]
        $baseText = $element.Extent.Text
        $hasExpansion = $false
        $hasPipelineExpansion = $false
        $allVarEntries = @()
        $skipNodeCreation = $false

        $pipelineExpansion = Expand-NestedPipelines -cfg $cfg -ast $element -prevNodeRef $prevNodeRef
        if ($null -ne $pipelineExpansion) {
            $baseText = $pipelineExpansion.ModifiedText
            $allVarEntries += $pipelineExpansion.PipeVarEntries
            if ($null -ne $pipelineExpansion.ScriptBlockVarEntries) {
                $allVarEntries += $pipelineExpansion.ScriptBlockVarEntries
            }
            $hasExpansion = $true
            $hasPipelineExpansion = $true
        }

        $expandedForEach = $false
        if ($i -gt 0 -and $element -is [System.Management.Automation.Language.CommandAst]) {
            $foreachExpansion = Expand-ForEachObjectPipelineElement -cfg $cfg -CommandAst $element -prevNodeRef $prevNodeRef -PipeVarName $pipeVarName -PipeVarEntry $pipeVarEntry -IncomingEdgeLabel 'Pipeline'
            if ($foreachExpansion.Expanded) {
                $expandedForEach = $true
                if ($i -eq $lastIndex) {
                    $emitNode = Add-Node -cfg $cfg -type "PipelineElement" -text "`$$pipeVarName" -line $element.Extent.StartLineNumber -ast $null -ownerAst $element
                    $emitNode.VarsRead = @($pipeVarEntry)
                    $emitNode.VarsWritten = @()
                    if ($null -ne $prevNodeRef.Value) {
                        Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $emitNode.Id -label "Pipeline"
                    }
                    $prevNodeRef.Value = $emitNode
                }
            }
        }

        if ($expandedForEach) {
            continue
        }

        if (-not $hasExpansion) {
            $scriptBlockExpansion = Expand-NestedScriptBlocks -cfg $cfg -ast $element -prevNodeRef $prevNodeRef -endNodeRef $endNodeRef -loopContext $loopContext -switchContext $switchContext
            if ($null -ne $scriptBlockExpansion) {
                if ($scriptBlockExpansion.InvokeOnlyExpanded) {
                    if ($i -gt 0 -and $null -ne $prevNodeRef.Value) {
                        $createdNode = $prevNodeRef.Value
                        $createdNode.Text = "`$$pipeVarName | " + $createdNode.Text
                        Add-VarToNode -node $createdNode -varEntry $pipeVarEntry -accessType "Read"
                    }
                    $skipNodeCreation = $true
                } elseif ($null -ne $scriptBlockExpansion.ModifiedText) {
                    $baseText = $scriptBlockExpansion.ModifiedText
                    $allVarEntries += $scriptBlockExpansion.ScriptBlockVarEntries
                    $hasExpansion = $true
                }
            }
        } else {
            $remainingSBs = Get-AllNestedScriptBlocks -ast $element
            foreach ($sb in $remainingSBs) {
                if ($cfg.ProcessedScriptBlocks.ContainsKey($sb)) {
                    $varName = $cfg.ProcessedScriptBlocks[$sb]
                    $baseText = $baseText.Replace($sb.Extent.Text, "`$$varName")
                }
            }
        }

        if ($skipNodeCreation) {
            continue
        }

        $nodeText = if ($i -gt 0) { "`$$pipeVarName | " + $baseText } else { $baseText }
        $pipeNode = Add-Node -cfg $cfg -type "PipelineElement" -text $nodeText -line $element.Extent.StartLineNumber -ast $element
        Mark-PipelineCmdletNode -Node $pipeNode -ElementAst $element

        foreach ($varEntry in $allVarEntries) {
            Add-VarToNode -node $pipeNode -varEntry $varEntry -accessType "Read"
        }

        if ($null -ne $prevNodeRef.Value) {
            if ($hasPipelineExpansion) {
                Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $pipeNode.Id -label "Pipeline"
            } elseif ($i -gt 0) {
                Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $pipeNode.Id -label "Pipeline"
            } else {
                Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $pipeNode.Id
            }
        }

        if ($i -eq 0) {
            if ($elements.Count -gt 1) {
                Add-VarToNode -node $pipeNode -varEntry $pipeVarEntry -accessType "Write"
            }
        } elseif ($i -eq $lastIndex) {
            Add-VarToNode -node $pipeNode -varEntry $pipeVarEntry -accessType "Read"
        } else {
            Add-VarToNode -node $pipeNode -varEntry $pipeVarEntry -accessType "Both"
        }

        $prevNodeRef.Value = $pipeNode
    }
}
# 处理 ReturnStatementAst 节点
# 返回 $true 表示后续语句不可达
function Convert-ReturnAstNode {
    param(
        [hashtable]$cfg,
        [System.Management.Automation.Language.ReturnStatementAst]$returnAst,
        [ref]$prevNodeRef,
        $endNodeRef = $null
    )

    # 检查 return 语句中是否有嵌套 Pipeline
    $returnExpansion = $null
    if ($null -ne $returnAst.Pipeline) {
        $returnExpansion = Expand-NestedPipelines -cfg $cfg -ast $returnAst.Pipeline -prevNodeRef $prevNodeRef
    }

    if ($null -ne $returnExpansion) {
        # 有嵌套 Pipeline，使用修改后的文本创建 Return 节点
        $modifiedReturnText = "return " + $returnExpansion.ModifiedText
        $returnNode = Add-Node -cfg $cfg -type "Return" -text $modifiedReturnText -line $returnAst.Extent.StartLineNumber -ast $returnAst
        foreach ($pipeVarEntry in $returnExpansion.PipeVarEntries) {
            Add-VarToNode -node $returnNode -varEntry $pipeVarEntry -accessType "Read"
        }
        if ($null -ne $prevNodeRef.Value) {
            Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $returnNode.Id -label "Pipeline"
        }
    } else {
        # 没有嵌套 Pipeline，正常创建 Return 节点
        $returnNode = Add-Node -cfg $cfg -type "Return" -text $returnAst.Extent.Text -line $returnAst.Extent.StartLineNumber -ast $returnAst
        if ($null -ne $prevNodeRef.Value) {
            Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $returnNode.Id
        }
    }

    # 检测是否在带 finally 的 try 中
    $inTryWithFinally = $false
    $ancestor = $returnAst.Parent
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
        $endNode = if ($endNodeRef -is [ref]) { $endNodeRef.Value } else { $endNodeRef }
        if ($null -ne $endNode) {
            Add-Edge -cfg $cfg -from $returnNode.Id -to $endNode.Id -label "Return"
        }
    }

    $prevNodeRef.Value = $returnNode
    return $true
}

# 处理 ExitStatementAst 节点
# 返回 $true 表示后续语句不可达
function Convert-ExitAstNode {
    param(
        [hashtable]$cfg,
        [System.Management.Automation.Language.ExitStatementAst]$exitAst,
        [ref]$prevNodeRef,
        $endNodeRef = $null
    )

    $exitNode = Add-Node -cfg $cfg -type "Exit" -text $exitAst.Extent.Text -line $exitAst.Extent.StartLineNumber -ast $exitAst
    if ($null -ne $prevNodeRef.Value) {
        Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $exitNode.Id
    }

    # 检测是否在带 finally 的 try 中
    $inTryWithFinally = $false
    $ancestor = $exitAst.Parent
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
        if ($script:__CFG_ScriptEndNode) {
            Add-Edge -cfg $cfg -from $exitNode.Id -to $script:__CFG_ScriptEndNode.Id -label "Exit"
        }
        elseif ($null -ne $endNodeRef) {
            $endNode = if ($endNodeRef -is [ref]) { $endNodeRef.Value } else { $endNodeRef }
            if ($null -ne $endNode) {
                Add-Edge -cfg $cfg -from $exitNode.Id -to $endNode.Id -label "Exit"
            }
        }
    }

    $prevNodeRef.Value = $exitNode
    return $true
}

# 处理 BreakStatementAst 节点
# 返回 $true 表示后续语句不可达
function Convert-BreakAstNode {
    param(
        [hashtable]$cfg,
        [System.Management.Automation.Language.BreakStatementAst]$breakAst,
        [ref]$prevNodeRef,
        $endNodeRef = $null,
        $loopContext = $null,
        $switchContext = $null
    )

    $breakNode = Add-Node -cfg $cfg -type "Break" -text $breakAst.Extent.Text -line $breakAst.Extent.StartLineNumber -ast $breakAst
    if ($null -ne $prevNodeRef.Value) {
        Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $breakNode.Id
    }

    # 优先检查 switchContext
    if ($null -ne $switchContext -and $null -ne $switchContext.SwitchMerge) {
        Add-Edge -cfg $cfg -from $breakNode.Id -to $switchContext.SwitchMerge.Id -label "Break"
    }
    # 其次检查 loopContext
    elseif ($null -ne $loopContext -and $null -ne $loopContext.LoopEnd) {
        Add-Edge -cfg $cfg -from $breakNode.Id -to $loopContext.LoopEnd.Id -label "Break"
    }
    # 不在 switch 或循环中，连接到 End 节点
    else {
        if ($null -ne $endNodeRef) {
            $endNode = if ($endNodeRef -is [ref]) { $endNodeRef.Value } else { $endNodeRef }
            if ($null -ne $endNode) {
                Add-Edge -cfg $cfg -from $breakNode.Id -to $endNode.Id -label "Break"
            }
        }
    }

    $prevNodeRef.Value = $breakNode
    return $true
}

# 处理 ContinueStatementAst 节点
# 返回 $true 表示后续语句不可达
function Convert-ContinueAstNode {
    param(
        [hashtable]$cfg,
        [System.Management.Automation.Language.ContinueStatementAst]$continueAst,
        [ref]$prevNodeRef,
        $endNodeRef = $null,
        $loopContext = $null,
        $switchContext = $null
    )

    $continueNode = Add-Node -cfg $cfg -type "Continue" -text $continueAst.Extent.Text -line $continueAst.Extent.StartLineNumber -ast $continueAst
    if ($null -ne $prevNodeRef.Value) {
        Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $continueNode.Id
    }

    # 优先检查 switchContext
    if ($null -ne $switchContext -and $null -ne $switchContext.SwitchNode) {
        Add-Edge -cfg $cfg -from $continueNode.Id -to $switchContext.SwitchNode.Id -label "Continue"
    }
    # 其次检查 loopContext
    elseif ($null -ne $loopContext -and $null -ne $loopContext.LoopContinue) {
        Add-Edge -cfg $cfg -from $continueNode.Id -to $loopContext.LoopContinue.Id -label "Continue"
    }
    # 不在 switch 或循环中，连接到 End 节点
    else {
        if ($null -ne $endNodeRef) {
            $endNode = if ($endNodeRef -is [ref]) { $endNodeRef.Value } else { $endNodeRef }
            if ($null -ne $endNode) {
                Add-Edge -cfg $cfg -from $continueNode.Id -to $endNode.Id -label "Continue"
            }
        }
    }

    $prevNodeRef.Value = $continueNode
    return $true
}

# 处理 ThrowStatementAst 节点
# 返回 $true 表示后续语句不可达
function Convert-ThrowAstNode {
    param(
        [hashtable]$cfg,
        [System.Management.Automation.Language.ThrowStatementAst]$throwAst,
        [ref]$prevNodeRef,
        $endNodeRef = $null
    )

    $throwNode = Add-Node -cfg $cfg -type "Throw" -text $throwAst.Extent.Text -line $throwAst.Extent.StartLineNumber -ast $throwAst
    if ($null -ne $prevNodeRef.Value) {
        Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $throwNode.Id
    }

    # 判断是否位于 catch / finally 块内部
    $inCatch = $false
    $inFinally = $false
    $hasTryAncestor = $false
    $ancestor = $throwAst.Parent
    while ($null -ne $ancestor) {
        if ($ancestor -is [System.Management.Automation.Language.CatchClauseAst]) {
            $inCatch = $true
        }
        elseif ($ancestor -is [System.Management.Automation.Language.StatementBlockAst]) {
            $parentTry = $ancestor.Parent
            if ($parentTry -is [System.Management.Automation.Language.TryStatementAst] -and
                $parentTry.Finally -eq $ancestor) {
                $inFinally = $true
            }
        }
        elseif ($ancestor -is [System.Management.Automation.Language.TryStatementAst]) {
            $hasTryAncestor = $true
        }
        $ancestor = $ancestor.Parent
    }

    # catch/finally 中的 throw：连到 End
    if (($inCatch -or $inFinally) -and $null -ne $endNodeRef) {
        $endNode = if ($endNodeRef -is [ref]) { $endNodeRef.Value } else { $endNodeRef }
        if ($null -ne $endNode) {
            Add-Edge -cfg $cfg -from $throwNode.Id -to $endNode.Id -label "Uncaught Exception"
        }
    }
    # 不在 try 中的 throw：连到 End
    elseif (-not $hasTryAncestor -and $null -ne $endNodeRef) {
        $endNode = if ($endNodeRef -is [ref]) { $endNodeRef.Value } else { $endNodeRef }
        if ($null -ne $endNode) {
            Add-Edge -cfg $cfg -from $throwNode.Id -to $endNode.Id -label "Uncaught Exception"
        }
    }

    $prevNodeRef.Value = $throwNode
    return $true
}

# 处理 FunctionDefinitionAst 节点（顶层定义）
# 返回 $false 表示后续语句可达
function Convert-FunctionDefAstNode {
    param(
        [hashtable]$cfg,
        [System.Management.Automation.Language.FunctionDefinitionAst]$funcDefAst,
        [ref]$prevNodeRef
    )

    $funcName = $funcDefAst.Name
    $defText = "function $funcName"
    $funcDefNode = Add-Node -cfg $cfg -type "FunctionDef" -text $defText -line $funcDefAst.Extent.StartLineNumber -ast $null
    if ($null -ne $prevNodeRef.Value) {
        Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $funcDefNode.Id
    }
    $prevNodeRef.Value = $funcDefNode

    # 将函数名加入已定义函数集合
    $null = $cfg.DefinedFunctions.Add($funcName)

    # 为函数体生成独立的 FuncStart/FuncEnd 子图
    Convert-FunctionDefinitionAst -cfg $cfg -funcAst $funcDefAst

    return $false
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
        # 添加全局 "Start" 节点
        $startNode = Add-Node -cfg $cfg -type "Start" -text "Script Start" -line 0

        # 添加全局 "End" 节点（供 exit 语句跳转使用）
        $endNode = Add-Node -cfg $cfg -type "End" -text "Script End" -line $node.Extent.EndLineNumber
        # 记录全局 Script End 节点，供 Exit 在任意作用域直接终止脚本使用
        $script:__CFG_ScriptEndNode = $endNode

        # 创建主脚本子图入口/出口节点
        $mainStart = Add-Node -cfg $cfg -type "MainStart" -text "Main Script" -line $node.Extent.StartLineNumber -ast $null
        $mainEnd = Add-Node -cfg $cfg -type "MainEnd" -text "End Main Script" -line $node.Extent.EndLineNumber -ast $null

        # Start → MainStart
        Add-Edge -cfg $cfg -from $startNode.Id -to $mainStart.Id

        # 设置 prevNodeRef 和 endNodeRef
        $prevNodeRef.Value = $mainStart
        $mainEndRef = [ref]$mainEnd

        # 使用通用函数处理脚本的 ScriptBlock
        $null = Convert-ScriptBlockBody -cfg $cfg -scriptBlockAst $node -prevNodeRef $prevNodeRef -endNodeRef $mainEndRef -paramNodeType "ScriptParams" -IsTopLevelScript $true

        # 连接最后一个节点到 MainEnd 节点（如果还没有被终止语句连接）
        if ($null -ne $prevNodeRef.Value -and $prevNodeRef.Value.Id -ne $mainEnd.Id) {
            $lastNodeType = $prevNodeRef.Value.Type
            if ($lastNodeType -notin @("Return", "Break", "Continue", "Throw", "Exit")) {
                Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $mainEnd.Id
            }
        }

        # MainEnd → End（正常结束）
        Add-Edge -cfg $cfg -from $mainEnd.Id -to $endNode.Id

        $prevNodeRef.Value = $endNode
    }
    # 二、如果是 ReturnStatementAst
    elseif ($node -is [System.Management.Automation.Language.ReturnStatementAst]) {
        return Convert-ReturnAstNode -cfg $cfg -returnAst $node -prevNodeRef $prevNodeRef -endNodeRef $endNodeRef
    }
    # 二点二、如果是 ExitStatementAst
    elseif ($node -is [System.Management.Automation.Language.ExitStatementAst]) {
        return Convert-ExitAstNode -cfg $cfg -exitAst $node -prevNodeRef $prevNodeRef -endNodeRef $endNodeRef
    }
    # 二点五、如果是 BreakStatementAst
    elseif ($node -is [System.Management.Automation.Language.BreakStatementAst]) {
        return Convert-BreakAstNode -cfg $cfg -breakAst $node -prevNodeRef $prevNodeRef -endNodeRef $endNodeRef -loopContext $loopContext -switchContext $switchContext
    }
    # 二点六、如果是 ContinueStatementAst
    elseif ($node -is [System.Management.Automation.Language.ContinueStatementAst]) {
        return Convert-ContinueAstNode -cfg $cfg -continueAst $node -prevNodeRef $prevNodeRef -endNodeRef $endNodeRef -loopContext $loopContext -switchContext $switchContext
    }
    # 二点七、如果是 ThrowStatementAst
    elseif ($node -is [System.Management.Automation.Language.ThrowStatementAst]) {
        return Convert-ThrowAstNode -cfg $cfg -throwAst $node -prevNodeRef $prevNodeRef -endNodeRef $endNodeRef
    }
    # 二点八、如果是 FunctionDefinitionAst
    elseif ($node -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
        return Convert-FunctionDefAstNode -cfg $cfg -funcDefAst $node -prevNodeRef $prevNodeRef
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
    # 四点六、如果是 AssignmentStatementAst
    elseif ($node -is [System.Management.Automation.Language.AssignmentStatementAst]) {
        Convert-AssignmentAstNode -cfg $cfg -assignAst $node -prevNodeRef $prevNodeRef
        return $false
    }
    # 五、如果是 PipelineAst
    elseif ($node -is [System.Management.Automation.Language.PipelineAst]) {
        Convert-PipelineAstNode -cfg $cfg -pipelineAst $node -prevNodeRef $prevNodeRef -endNodeRef $endNodeRef -loopContext $loopContext -switchContext $switchContext
        return $false
    }
    # 六、其余节点（包含嵌套 Pipeline、ScriptBlock 的通用处理）
    else {
        # 检测节点内是否有嵌套的多元素 Pipeline
        $nestedPipelines = Get-AllNestedPipelines -ast $node

        if ($nestedPipelines.Count -gt 0) {
            # 按位置倒序排列（从后往前处理，避免文本替换时位置偏移）
            $sortedPipelines = $nestedPipelines | Sort-Object { $_.Extent.StartOffset } -Descending

            # 记录所有 Pipeline 的变量名和替换信息
            $replacements = @()
            $allPipelineNodes = @()

            # 第一步：收集所有 Pipeline 内所有元素的 ScriptBlock 替换信息
            # 这样可以正确构建 "修改后的原始文本" 用于最终替换
            $allScriptBlockReplacements = @{}  # ScriptBlock AST -> 变量名

            foreach ($pipeline in $sortedPipelines) {
                foreach ($element in $pipeline.PipelineElements) {
                    $nestedSBs = Get-AllNestedScriptBlocks -ast $element
                    foreach ($sb in $nestedSBs) {
                        if (-not $cfg.ProcessedScriptBlocks.ContainsKey($sb)) {
                            $execType = Get-ScriptBlockExecutionType -scriptBlockExprAst $sb
                            if ($execType -in @("Immediate", "PipelineValue", "InvokeOnly", "CmdletInvoke")) {
                                $guid = [guid]::NewGuid().ToString("N").Substring(0, 8)
                                $varName = "_block_$guid"
                                $cfg.ProcessedScriptBlocks[$sb] = $varName
                                $allScriptBlockReplacements[$sb] = $varName
                                # 创建子图
                                $null = Convert-ScriptBlockDefinition -cfg $cfg -scriptBlockExprAst $sb -blockName $varName
                            }
                        } else {
                            $allScriptBlockReplacements[$sb] = $cfg.ProcessedScriptBlocks[$sb]
                        }
                    }
                }
            }

            foreach ($pipeline in $sortedPipelines) {
                $guid = [guid]::NewGuid().ToString("N").Substring(0, 8)
                $pipeVar = "_pipe_$guid"
                $pipeVarEntry = [PSCustomObject]@{ Name = $pipeVar; Scope = [VarScope]::Unspecified }

                $elements = $pipeline.PipelineElements
                $lastIndex = $elements.Count - 1

                # 构建 "修改后的原始 Pipeline 文本"（用于最终替换）
                # 将 Pipeline 内所有 ScriptBlock 替换为对应的变量名
                $modifiedPipelineText = $pipeline.Extent.Text
                $nestedSBsInPipeline = Get-AllNestedScriptBlocks -ast $pipeline
                # 按位置倒序替换，避免偏移
                $sortedSBs = $nestedSBsInPipeline | Sort-Object { $_.Extent.StartOffset } -Descending
                foreach ($sb in $sortedSBs) {
                    if ($allScriptBlockReplacements.ContainsKey($sb)) {
                        $varName = $allScriptBlockReplacements[$sb]
                        $modifiedPipelineText = $modifiedPipelineText.Replace($sb.Extent.Text, "`$$varName")
                    }
                }

                # 拆分 Pipeline 的前 N-1 个元素为独立节点
                for ($i = 0; $i -lt $elements.Count - 1; $i++) {
                    $element = $elements[$i]
                    $elementText = $element.Extent.Text
                    $elementVarEntries = @()

                    # 替换此元素内的 ScriptBlock
                    $nestedSBsInElement = Get-AllNestedScriptBlocks -ast $element
                    $sortedSBsInElement = $nestedSBsInElement | Sort-Object { $_.Extent.StartOffset } -Descending
                    foreach ($sb in $sortedSBsInElement) {
                        if ($allScriptBlockReplacements.ContainsKey($sb)) {
                            $varName = $allScriptBlockReplacements[$sb]
                            $elementText = $elementText.Replace($sb.Extent.Text, "`$$varName")
                            $elementVarEntries += [PSCustomObject]@{ Name = $varName; Scope = [VarScope]::Unspecified }
                        }
                    }

                    # 构建节点文本
                    if ($i -eq 0) {
                        $nodeText = $elementText
                    } else {
                        $nodeText = "`$$pipeVar | " + $elementText
                    }

                    $pipeNode = Add-Node -cfg $cfg -type "PipelineElement" -text $nodeText -line $element.Extent.StartLineNumber -ast $element
                    Mark-PipelineCmdletNode -Node $pipeNode -ElementAst $element

                    # 添加 ScriptBlock 变量到 VarsRead
                    foreach ($varEntry in $elementVarEntries) {
                        Add-VarToNode -node $pipeNode -varEntry $varEntry -accessType "Read"
                    }

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

                # 处理最后一个元素中的 ScriptBlock
                $lastElement = $elements[$lastIndex]
                $lastElementText = $lastElement.Extent.Text
                $lastElementVarEntries = @()

                $nestedSBsInLast = Get-AllNestedScriptBlocks -ast $lastElement
                $sortedSBsInLast = $nestedSBsInLast | Sort-Object { $_.Extent.StartOffset } -Descending
                foreach ($sb in $sortedSBsInLast) {
                    if ($allScriptBlockReplacements.ContainsKey($sb)) {
                        $varName = $allScriptBlockReplacements[$sb]
                        $lastElementText = $lastElementText.Replace($sb.Extent.Text, "`$$varName")
                        $lastElementVarEntries += [PSCustomObject]@{ Name = $varName; Scope = [VarScope]::Unspecified }
                    }
                }

                # 记录替换信息：将整个 Pipeline（已替换 ScriptBlock）替换为 "$pipeVar | 最后一个元素"
                $replacementText = "`$$pipeVar | " + $lastElementText

                $replacements += @{
                    Original = $modifiedPipelineText  # 使用已替换 ScriptBlock 的文本
                    Replacement = $replacementText
                    PipeVar = $pipeVar
                    PipeVarEntry = $pipeVarEntry
                    LastElementVarEntries = $lastElementVarEntries
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
            # 首先替换所有 ScriptBlock（针对不在 Pipeline 内的 ScriptBlock）
            $modifiedText = $node.Extent.Text
            $allNestedSBs = Get-AllNestedScriptBlocks -ast $node
            $sortedAllSBs = $allNestedSBs | Sort-Object { $_.Extent.StartOffset } -Descending
            foreach ($sb in $sortedAllSBs) {
                if ($allScriptBlockReplacements.ContainsKey($sb)) {
                    $varName = $allScriptBlockReplacements[$sb]
                    $modifiedText = $modifiedText.Replace($sb.Extent.Text, "`$$varName")
                }
            }
            # 然后替换 Pipeline
            foreach ($r in $replacements) {
                $modifiedText = $modifiedText.Replace($r.Original, $r.Replacement)
            }

            # 创建最终节点
            $finalNode = Add-Node -cfg $cfg -type $node.GetType().Name -text $modifiedText -line $node.Extent.StartLineNumber -ast $node

            # 为最终节点添加所有 pipeVar 和 ScriptBlock 变量到 VarsRead
            foreach ($r in $replacements) {
                Add-VarToNode -node $finalNode -varEntry $r.PipeVarEntry -accessType "Read"
                # 添加最后一个元素中的 ScriptBlock 变量
                foreach ($varEntry in $r.LastElementVarEntries) {
                    Add-VarToNode -node $finalNode -varEntry $varEntry -accessType "Read"
                }
            }

            # 连接最后一个 Pipeline 节点到最终节点
            if ($null -ne $prevNodeRef.Value) {
                Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $finalNode.Id -label "Pipeline"
            }
            $prevNodeRef.Value = $finalNode
            return $false
        }

        # 检测节点内是否有嵌套的 ScriptBlock
        $nestedScriptBlocks = Get-AllNestedScriptBlocks -ast $node
        if ($nestedScriptBlocks.Count -gt 0) {
            # 分类处理
            $deferredBlocks = @()
            $immediateBlocks = @()
            $invokeOnlyBlocks = @()
            $pipelineValueBlocks = @()

            foreach ($sb in $nestedScriptBlocks) {
                $execType = Get-ScriptBlockExecutionType -scriptBlockExprAst $sb
                switch ($execType) {
                    "Deferred" { $deferredBlocks += $sb }
                    "InvokeOnly" { $invokeOnlyBlocks += $sb }
                    "PipelineValue" { $pipelineValueBlocks += $sb }
                    default { $immediateBlocks += $sb }
                }
            }

            # 处理 PipelineValue 类型的 ScriptBlock（如 { Get-Date } | ForEach-Object { & $_ }）
            # 这类 ScriptBlock 作为 Pipeline 元素的值传递，需要生成独立子图
            # 注意：这里只创建子图，替换逻辑由 Expand-NestedScriptBlocks 统一处理
            foreach ($sb in $pipelineValueBlocks) {
                # 检查是否已处理过
                if ($cfg.ProcessedScriptBlocks.ContainsKey($sb)) {
                    continue
                }

                $guid = [guid]::NewGuid().ToString("N").Substring(0, 8)
                $varName = "_block_$guid"

                # 标记为已处理，记录变量名
                $cfg.ProcessedScriptBlocks[$sb] = $varName

                # 创建独立子图
                Convert-ScriptBlockDefinition -cfg $cfg -scriptBlockExprAst $sb -blockName $varName
            }

            # 处理延迟执行的 ScriptBlock：创建独立子图，使用赋值目标变量名
            # 【已修改】去掉 BlockDef 节点
            $hasStandaloneDeferred = $false
            foreach ($sb in $deferredBlocks) {
                # 检查是否已处理过
                if ($cfg.ProcessedScriptBlocks.ContainsKey($sb)) {
                    continue
                }

                # 尝试从父 AST 获取变量名
                $varName = $null
                $parent = $sb.Parent
                if ($parent -is [System.Management.Automation.Language.AssignmentStatementAst]) {
                    $left = $parent.Left
                    if ($left -is [System.Management.Automation.Language.VariableExpressionAst]) {
                        $varName = $left.VariablePath.UserPath
                    }
                }

                # 如果没有赋值目标（独立的 ScriptBlock 字面量作为值），生成唯一块名称
                if ($null -eq $varName) {
                    $hasStandaloneDeferred = $true
                    # 生成唯一块名称（作为变量）
                    $guid = [guid]::NewGuid().ToString("N").Substring(0, 8)
                    $varName = "_block_$guid"
                    $blockVarEntry = [PSCustomObject]@{ Name = $varName; Scope = [VarScope]::Unspecified }

                    # 标记为已处理，记录变量名
                    $cfg.ProcessedScriptBlocks[$sb] = $varName

                    # 【修改】不再创建 BlockDef 节点，只创建独立子图
                    Convert-ScriptBlockDefinition -cfg $cfg -scriptBlockExprAst $sb -blockName $varName

                    # 【修改】创建 PipelineElement 节点，用 $_block_name 变量引用替代原始 ScriptBlock
                    $pipeNode = Add-Node -cfg $cfg -type "PipelineElement" -text "`$$varName" -line $sb.Extent.StartLineNumber -ast $sb
                    Add-VarToNode -node $pipeNode -varEntry $blockVarEntry -accessType "Read"
                    if ($null -ne $prevNodeRef.Value) {
                        Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $pipeNode.Id
                    }
                    $prevNodeRef.Value = $pipeNode
                } else {
                    # 有赋值目标，只创建子图（赋值语句本身会作为节点）
                    # 标记为已处理，记录变量名
                    $cfg.ProcessedScriptBlocks[$sb] = $varName
                    # 使用 $varName 作为 block 变量名
                    Convert-ScriptBlockDefinition -cfg $cfg -scriptBlockExprAst $sb -blockName $varName
                }
            }

            # 如果有独立的 ScriptBlock，已经完全处理，跳过后续节点创建
            if ($hasStandaloneDeferred) {
                return $false
            }

            # 处理 InvokeOnly 类型（如 & { } 或 . { }）：只展开内部语句
            if ($invokeOnlyBlocks.Count -gt 0) {
                $scriptBlockExpansion = Expand-NestedScriptBlocks -cfg $cfg -ast $node -prevNodeRef $prevNodeRef -endNodeRef $endNodeRef -loopContext $loopContext -switchContext $switchContext
                if ($null -ne $scriptBlockExpansion -and $scriptBlockExpansion.InvokeOnlyExpanded) {
                    # InvokeOnly 已经完全展开，不需要创建后续节点
                    return $false
                }
            }

            # 处理 Immediate 类型的 ScriptBlock：内联展开
            if ($immediateBlocks.Count -gt 0) {
                $scriptBlockExpansion = Expand-NestedScriptBlocks -cfg $cfg -ast $node -prevNodeRef $prevNodeRef -endNodeRef $endNodeRef -loopContext $loopContext -switchContext $switchContext
                if ($null -ne $scriptBlockExpansion -and -not $scriptBlockExpansion.InvokeOnlyExpanded) {
                    # 创建最终节点
                    $finalNode = Add-Node -cfg $cfg -type $node.GetType().Name -text $scriptBlockExpansion.ModifiedText -line $node.Extent.StartLineNumber -ast $node

                    # 为最终节点添加所有 ScriptBlock 变量到 VarsRead
                    foreach ($varEntry in $scriptBlockExpansion.ScriptBlockVarEntries) {
                        Add-VarToNode -node $finalNode -varEntry $varEntry -accessType "Read"
                    }

                    # 连接最后一个展开节点到最终节点
                    if ($null -ne $prevNodeRef.Value) {
                        Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $finalNode.Id -label "ScriptBlock"
                    }
                    $prevNodeRef.Value = $finalNode
                    return $false
                }
            }
        }

        # 没有嵌套 Pipeline 或 ScriptBlock，直接创建节点
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
        DefinedFunctions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)  # 已定义的函数名集合
        ProcessedScriptBlocks = @{}  # 已处理的 ScriptBlock AST -> 变量名 的映射，防止重复处理并支持查找
        DefinedAliases = @{}  # 已定义的别名映射 @{ "别名" = "目标命令" }
    }

    # 处理AST节点
    Convert-AstNode -cfg $mycfg -node $ast -prevNodeRef ([ref]$null)

    return $mycfg
}

#生成图结构
function Export-CfgToDot {
    param(
        [hashtable]$finalCFG,
        [string]$outputPath = "control_flow.dot",
        # 仅这些节点会高亮（表示“实际发生了替换”）
        [int[]]$AppliedNodeIds = @()
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

    # 辅助函数：HTML Label 安全格式化（用于节点标签）
    function Format-DotHtmlText {
        param(
            [string]$text,
            [int]$MaxLen = 80
        )

        if ([string]::IsNullOrWhiteSpace($text)) { return "" }

        # 移除控制字符（保留可见字符）
        $cleaned = [System.Text.RegularExpressions.Regex]::Replace(
            $text,
            '[\x00-\x1F\x7F]',
            ''
        )

        # 智能截断
        $trimmed = $cleaned
        if ($trimmed.Length -gt $MaxLen) {
            $prefixLen = [Math]::Max(0, $MaxLen - 3)
            $truncated = $trimmed.Substring(0, $prefixLen)
            $lastSpace = $truncated.LastIndexOf(' ')
            if ($lastSpace -gt 20) {
                $truncated = $truncated.Substring(0, $lastSpace)
            }
            $trimmed = "$truncated..."
        }

        # HTML 转义（Graphviz HTML-like label）
        $escaped = $trimmed.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;')
        return $escaped
    }

    # 构建高亮节点集合（仅实际发生替换的节点）
    $appliedNodeSet = [System.Collections.Generic.HashSet[int]]::new()
    foreach ($nid in @($AppliedNodeIds)) {
        try {
            $null = $appliedNodeSet.Add([int]$nid)
        } catch {
            # 忽略无法转换的 NodeId
        }
    }

    # 1. 生成节点定义（code 显眼 + 元信息下置；仅“实际替换节点”高亮黄色）
    $nodeDefinitions = @()
    foreach ($node in $finalCFG.Nodes) {
        $shape = switch ($node.Type) {
            {$_ -in "Start", "End", "FuncStart", "FuncEnd"}   { "oval" }
            {$_ -in "Condition", "If", "ForEachCondition", "ProcessCondition"}    { "diamond" }
            {$_ -in "Merge"}                                  { "point" }
            default                                           { "box" }
        }

        $metaLines = @()

        if ($null -ne $node.DynamicInvoke) {
            $dynType = if ($node.DynamicInvoke -is [array]) {
                ($node.DynamicInvoke | ForEach-Object { $_.Type }) -join ", "
            } else {
                $node.DynamicInvoke.Type
            }
            $metaLines += "DYN: $(Format-DotHtmlText $dynType 70)"
        }

        $hasInvokes = ($node.Invokes.Functions.Count -gt 0) -or ($node.Invokes.ScriptBlocks.Count -gt 0)
        if ($hasInvokes) {
            $invokeLabels = @()
            if ($node.Invokes.Functions.Count -gt 0) {
                $funcList = $node.Invokes.Functions -join ", "
                $invokeLabels += "Func: $funcList"
            }
            if ($node.Invokes.ScriptBlocks.Count -gt 0) {
                $blockList = $node.Invokes.ScriptBlocks -join ", "
                $invokeLabels += "Block: $blockList"
            }
            $metaLines += "CALLS: $(Format-DotHtmlText ($invokeLabels -join '; ') 90)"
        }

        $pipeVarsWritten = @($node.VarsWritten | Where-Object { $_.Name -match '^_pipe_[a-f0-9]{8}$' })
        if ($pipeVarsWritten.Count -gt 0) {
            $pipeVarList = ($pipeVarsWritten | ForEach-Object { "`$$($_.Name)" }) -join ", "
            $metaLines += "PIPE OUT: $(Format-DotHtmlText $pipeVarList 90)"
        }

        if ($node.Resolvables.Count -gt 0) {
            $metaLines += "RESOLVABLE: $($node.Resolvables.Count)"
        }

        if ($node.PSObject.Properties.Match('PipeCmdlet').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($node.PipeCmdlet)) {
            $cmdletName = $node.PipeCmdlet
            if ($node.PSObject.Properties.Match('PipeCmdletName').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($node.PipeCmdletName)) {
                $cmdletName = $node.PipeCmdletName
            }
            $metaLines += "PIPE CMDLET: $(Format-DotHtmlText $cmdletName 80)"
        }

        if ($node.AliasesUsed.Count -gt 0) {
            $aliasList = ($node.AliasesUsed | ForEach-Object { "$($_.Name)->$($_.Target)" }) -join ", "
            $metaLines += "ALIAS: $(Format-DotHtmlText $aliasList 90)"
        }

        $idTypeText = Format-DotHtmlText ("Id $($node.Id) | $($node.Type)") 80
        $codeText = Format-DotHtmlText $node.Text 90
        if ([string]::IsNullOrWhiteSpace($codeText)) { $codeText = "(empty)" }

        $labelLines = @(
            "<FONT POINT-SIZE=`"9`" COLOR=`"#666666`">$idTypeText</FONT>",
            "<B><FONT POINT-SIZE=`"16`">$codeText</FONT></B>"
        )
        foreach ($meta in $metaLines) {
            $labelLines += "<FONT POINT-SIZE=`"10`" COLOR=`"#333333`">$meta</FONT>"
        }
        $htmlLabel = "<$($labelLines -join '<BR ALIGN=`"LEFT`"/>')>"

        # 着色规则：仅实际替换节点高亮；其余全部白色
        $isAppliedNode = $false
        try {
            $isAppliedNode = $appliedNodeSet.Contains([int]$node.Id)
        } catch {
            $isAppliedNode = $false
        }

        $style = if ($isAppliedNode) {
            'style="filled,rounded", fillcolor="#fff3cc", color="#cc9900", penwidth=2'
        } else {
            'style="filled,rounded", fillcolor="#ffffff", color="#333333", penwidth=1'
        }

        $nodeDefinitions += "    $($node.Id) [label=$htmlLabel, shape=$shape, $style];"
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

# 运行时创建脚本块子图（用于动态执行的代码）
# 完整支持控制流结构
function New-RuntimeSubgraph {
    param(
        [hashtable]$cfg,              # 现有的 CFG
        [string]$Code,                # 动态执行的代码字符串
        [string]$BlockNamePrefix = "_dyn_"  # 块名前缀
    )

    $initialNodeCount = if ($null -ne $cfg.Nodes) { @($cfg.Nodes).Count } else { 0 }
    $initialEdgeCount = if ($null -ne $cfg.Edges) { @($cfg.Edges).Count } else { 0 }

    # 1. 解析代码字符串为 AST
    $errors = $null
    $tokens = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($Code, [ref]$tokens, [ref]$errors)

    if ($errors -and $errors.Count -gt 0) {
        return @{
            Success = $false
            Error = $errors[0].Message
        }
    }

    # 2. 生成唯一块名称
    $guid = [guid]::NewGuid().ToString("N").Substring(0, 8)
    $blockName = "$BlockNamePrefix$guid"

    # 3. 创建 BlockStart 和 BlockEnd 节点
    $blockStart = Add-Node -cfg $cfg -type "BlockStart" -text "DynamicBlock $blockName" -line 0 -ast $null
    # 存储脚本块内容文本，用于运行时匹配
    $blockStart | Add-Member -NotePropertyName "ScriptBlockText" -NotePropertyValue "{$Code}" -Force
    $hasProcessBlock = ($null -ne $ast.ProcessBlock -and $ast.ProcessBlock.Statements.Count -gt 0)
    $blockStart | Add-Member -NotePropertyName "HasProcessBlock" -NotePropertyValue $hasProcessBlock -Force
    $blockStart | Add-Member -NotePropertyName "ProcessInputVar" -NotePropertyValue "__proc_input" -Force
    $blockEnd = Add-Node -cfg $cfg -type "BlockEnd" -text "End DynamicBlock $blockName" -line 0 -ast $null

    $prevNode = $blockStart
    $prev = [ref]$prevNode
    $endRef = [ref]$blockEnd

    # 4. 使用 Convert-ScriptBlockBody 完整处理 AST（支持控制流）
    $null = Convert-ScriptBlockBody -cfg $cfg -scriptBlockAst $ast -prevNodeRef $prev -endNodeRef $endRef -paramNodeType "BlockParams"

    # 5. 连接最后节点到 BlockEnd
    if ($null -ne $prev.Value -and $prev.Value.Id -ne $blockEnd.Id) {
        $lastType = $prev.Value.Type
        if ($lastType -notin @("Return", "Exit", "Throw", "Break", "Continue", "End")) {
            Add-Edge -cfg $cfg -from $prev.Value.Id -to $blockEnd.Id
        }
    }

    $allNodes = if ($null -ne $cfg.Nodes) { @($cfg.Nodes) } else { @() }
    $allEdges = if ($null -ne $cfg.Edges) { @($cfg.Edges) } else { @() }
    $newNodes = if ($allNodes.Count -gt $initialNodeCount) { @($allNodes | Select-Object -Skip $initialNodeCount) } else { @() }
    $newEdges = if ($allEdges.Count -gt $initialEdgeCount) { @($allEdges | Select-Object -Skip $initialEdgeCount) } else { @() }
    if (Get-Command -Name Sync-CFGExecutionIndexesIncremental -ErrorAction SilentlyContinue) {
        try {
            $null = Sync-CFGExecutionIndexesIncremental -CFG $cfg -NewNodes $newNodes -NewEdges $newEdges
        }
        catch {
            if (Get-Command -Name Ensure-CFGExecutionIndexes -ErrorAction SilentlyContinue) {
                try {
                    $null = Ensure-CFGExecutionIndexes -CFG $cfg
                }
                catch {
                }
            }
        }
    }

    return @{
        Success = $true
        BlockName = $blockName
        BlockStartId = $blockStart.Id
        BlockEndId = $blockEnd.Id
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
