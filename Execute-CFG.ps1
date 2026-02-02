# Execute-CFG.ps1
# CFG 遍历执行器 - 基础版本

. "$PSScriptRoot\ConvertTo-Expression-origin.ps1"

# 创建执行上下文（Runspace）
function New-ExecutionContext {
    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.Open()

    return @{
        Runspace = $runspace
    }
}

# 关闭执行上下文
function Close-ExecutionContext {
    param([hashtable]$ExecContext)
    if ($ExecContext.Runspace) {
        $ExecContext.Runspace.Close()
        $ExecContext.Runspace.Dispose()
    }
}

# 在 Runspace 中执行代码
function Invoke-InContext {
    param(
        [hashtable]$ExecContext,
        [string]$Code
    )

    try {
        $ps = [powershell]::Create()
        $ps.Runspace = $ExecContext.Runspace
        $ps.AddScript($Code) | Out-Null

        $result = $ps.Invoke()

        if ($ps.HadErrors) {
            $errorMsg = $ps.Streams.Error | ForEach-Object { $_.ToString() } | Join-String -Separator "`n"
            return @{
                Success = $false
                Error   = $errorMsg
                Result  = $null
            }
        }

        return @{
            Success = $true
            Error   = $null
            Result  = $result
        }
    }
    catch {
        return @{
            Success = $false
            Error   = $_.Exception.Message
            Result  = $null
        }
    }
    finally {
        if ($ps) { $ps.Dispose() }
    }
}

# 从 Runspace 获取变量值
function Get-VariableFromContext {
    param(
        [hashtable]$ExecContext,
        [string]$Name
    )
    return $ExecContext.Runspace.SessionStateProxy.GetVariable($Name)
}

# 获取节点读写变量的当前值
function Get-NodeVariableValues {
    param(
        [hashtable]$ExecContext,
        $Node
    )

    $result = @{
        Read    = @{}
        Written = @{}
    }

    # 读取的变量
    foreach ($varInfo in $Node.VarsRead) {
        $varName = $varInfo.Name
        $value = Get-VariableFromContext -ExecContext $ExecContext -Name $varName
        $result.Read[$varName] = $value
    }

    # 写入的变量
    foreach ($varInfo in $Node.VarsWritten) {
        $varName = $varInfo.Name
        $value = Get-VariableFromContext -ExecContext $ExecContext -Name $varName
        $result.Written[$varName] = $value
    }

    return $result
}

# 格式化变量值用于日志输出
function Format-VariableValue {
    param($Value)

    if ($null -eq $Value) {
        return '$null'
    }

    $type = $Value.GetType().Name

    # 数组/集合
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $count = @($Value).Count
        if ($count -le 5) {
            $items = @($Value) | ForEach-Object { Format-VariableValue $_ }
            return "@($($items -join ', '))"
        } else {
            return "[$type] Count=$count"
        }
    }

    # 字符串
    if ($Value -is [string]) {
        if ($Value.Length -gt 50) {
            return "`"$($Value.Substring(0, 47))...`""
        }
        return "`"$Value`""
    }

    # 数字/布尔
    if ($Value -is [ValueType]) {
        return "$Value"
    }

    # 其他对象
    return "[$type]"
}

# 写日志
function Write-ExecutionLog {
    param(
        [hashtable]$Context,
        [string]$Message
    )

    $timestamp = Get-Date -Format "HH:mm:ss.fff"
    $logLine = "[$timestamp] $Message"

    # 写入文件
    Add-Content -Path $Context.LogPath -Value $logLine -Encoding UTF8

    # 同时输出到控制台（可选）
    # Write-Host $logLine
}

# 根据节点 ID 获取节点
function Get-NodeById {
    param(
        [hashtable]$CFG,
        [int]$Id
    )
    return $CFG.Nodes | Where-Object { $_.Id -eq $Id } | Select-Object -First 1
}

# 获取后继节点
function Get-NextNodes {
    param(
        [hashtable]$CFG,
        $Node,
        [hashtable]$Context
    )

    $edges = $CFG.Edges | Where-Object { $_.From -eq $Node.Id }

    switch ($Node.Type) {
        # If Condition 入口 - 跟随 Condition 边
        "If Condition" {
            $edge = $edges | Where-Object { $_.Label -eq "Condition" } | Select-Object -First 1
            if ($edge) { return @(Get-NodeById -CFG $CFG -Id $edge.To) }
            return @()
        }

        # 条件节点 - 根据求值结果选择边
        "Condition" {
            if ($Context.LastConditionResult) {
                $edge = $edges | Where-Object { $_.Label -eq "True" } | Select-Object -First 1
            } else {
                $edge = $edges | Where-Object { $_.Label -eq "False" } | Select-Object -First 1
            }
            if ($edge) { return @(Get-NodeById -CFG $CFG -Id $edge.To) }
            return @()
        }

        # ForEach 条件节点
        "ForEachCondition" {
            if ($Context.LastConditionResult) {
                $edge = $edges | Where-Object { $_.Label -eq "Has next" } | Select-Object -First 1
            } else {
                $edge = $edges | Where-Object { $_.Label -eq "No more items" } | Select-Object -First 1
            }
            if ($edge) { return @(Get-NodeById -CFG $CFG -Id $edge.To) }
            return @()
        }

        # Switch 条件节点
        "SwitchCondition" {
            if ($Context.LastConditionResult) {
                $edge = $edges | Where-Object { $_.Label -eq "True" } | Select-Object -First 1
            } else {
                $edge = $edges | Where-Object { $_.Label -eq "False" } | Select-Object -First 1
            }
            if ($edge) { return @(Get-NodeById -CFG $CFG -Id $edge.To) }
            return @()
        }

        # Case 条件节点
        "CaseCondition" {
            if ($Context.LastConditionResult) {
                $edge = $edges | Where-Object { $_.Label -eq "True" } | Select-Object -First 1
            } else {
                $edge = $edges | Where-Object { $_.Label -eq "False" } | Select-Object -First 1
            }
            if ($edge) { return @(Get-NodeById -CFG $CFG -Id $edge.To) }
            return @()
        }

        # 控制流跳转节点
        "Return" {
            $edge = $edges | Where-Object { $_.Label -eq "Return" } | Select-Object -First 1
            if ($edge) { return @(Get-NodeById -CFG $CFG -Id $edge.To) }
            return @()
        }
        "Exit" {
            $edge = $edges | Where-Object { $_.Label -eq "Exit" } | Select-Object -First 1
            if ($edge) { return @(Get-NodeById -CFG $CFG -Id $edge.To) }
            return @()
        }
        "Break" {
            $edge = $edges | Where-Object { $_.Label -eq "Break" } | Select-Object -First 1
            if ($edge) { return @(Get-NodeById -CFG $CFG -Id $edge.To) }
            return @()
        }
        "Continue" {
            $edge = $edges | Where-Object { $_.Label -eq "Continue" } | Select-Object -First 1
            if ($edge) { return @(Get-NodeById -CFG $CFG -Id $edge.To) }
            return @()
        }
        "Throw" {
            # 暂不处理异常，直接终止
            return @()
        }

        # 其他节点 - 跟随顺序边
        default {
            $nextNodes = @()
            foreach ($edge in $edges) {
                # 跳过条件分支边
                if ($edge.Label -in @("True", "False", "Has next", "No more items", "Exception", "Uncaught Exception", "Not Match")) {
                    continue
                }
                $nextNode = Get-NodeById -CFG $CFG -Id $edge.To
                if ($nextNode) { $nextNodes += $nextNode }
            }
            return $nextNodes
        }
    }
}

# 格式化可还原表达式的值（用于显示和比较）
function Format-ResolvableValue {
    param($Value)

    if ($null -eq $Value) { return '$null' }

    # 处理 PSObject Collection（Invoke-InContext 返回类型）
    if ($Value -is [System.Collections.ObjectModel.Collection[System.Management.Automation.PSObject]]) {
        if ($Value.Count -eq 0) { return '$null' }
        if ($Value.Count -eq 1) { return ConvertTo-Expression -Object $Value[0] -Expand -1 }
        # 多元素：逐个序列化后包装为 @()
        $items = $Value | ForEach-Object { ConvertTo-Expression -Object $_ -Expand -1 }
        return '@(' + ($items -join ', ') + ')'
    }

    # 处理普通数组
    if ($Value -is [array]) {
        if ($Value.Count -eq 0) { return '$null' }
        if ($Value.Count -eq 1) { return ConvertTo-Expression -Object $Value[0] -Expand -1 }
        $items = $Value | ForEach-Object { ConvertTo-Expression -Object $_ -Expand -1 }
        return '@(' + ($items -join ', ') + ')'
    }

    return ConvertTo-Expression -Object $Value -Expand -1
}

# 求值节点中的可还原表达式
function Evaluate-NodeResolvables {
    param(
        $Node,
        [hashtable]$Context
    )

    # 跳过没有 Resolvables 的节点
    if ($null -eq $Node.Resolvables -or $Node.Resolvables.Count -eq 0) {
        return
    }

    # 跳过求值的类型（有副作用或不适合求值）
    $skipEvalTypes = @('Command', 'Unary')  # Command 和 Unary（可能有副作用如 ++/--）

    foreach ($resolvable in $Node.Resolvables) {
        # 跳过 Command 类型
        if ($resolvable.Type -in $skipEvalTypes) {
            continue
        }

        $key = "$($Node.Id):$($resolvable.StartOffset):$($resolvable.EndOffset)"

        # 在当前 Runspace 上下文中求值
        $evalResult = Invoke-InContext -ExecContext $Context.ExecContext -Code $resolvable.Text

        if ($evalResult.Success) {
            $value = Format-ResolvableValue $evalResult.Result

            # 记录到结果集
            if (-not $Context.ResolvableResults.ContainsKey($key)) {
                $Context.ResolvableResults[$key] = @{
                    NodeId     = $Node.Id
                    Resolvable = $resolvable
                    Values     = @()
                }
            }
            $Context.ResolvableResults[$key].Values += $value
        }
    }
}

# 执行节点
function Invoke-Node {
    param(
        $Node,
        [hashtable]$Context
    )

    # 虚拟节点（无需执行）
    $virtualTypes = @(
        'Start', 'End', 'MainStart', 'MainEnd',
        'FuncStart', 'FuncEnd', 'BlockStart', 'BlockEnd',
        'LoopStart', 'LoopEnd', 'SwitchStart', 'SwitchEnd',
        'If Condition', 'Else', 'Merge', 'Default',
        'Try', 'Catch', 'Finally', 'FunctionDef'
    )

    if ($Node.Type -in $virtualTypes) {
        return @{
            Success  = $true
            Executed = $false
            Result   = $null
            Error    = $null
        }
    }

    # CFG 合成节点（使用 Text 而非 AST）
    $syntheticTypes = @(
        'ForEachInit', 'ForEachCondition', 'ForEachBind', 'ForEachIter',
        'ForInit', 'ForIter',
        'SwitchInit', 'SwitchCondition', 'SwitchBind', 'SwitchIter',
        'CaseCondition',
        'PipelineElement'  # 管道元素也使用 Text（包含 $_pipe_ 变量）
    )

    # 获取要执行的代码
    $code = if ($Node.Type -in $syntheticTypes) {
        $Node.Text
    } elseif ($Node.Ast) {
        $Node.Ast.Extent.Text
    } else {
        $Node.Text
    }

    # 执行代码
    $execResult = Invoke-InContext -ExecContext $Context.ExecContext -Code $code

    # 处理管道变量：如果 VarsWritten 中有 _pipe_ 变量，将执行结果赋值给它
    if ($execResult.Success -and $Node.Type -eq 'PipelineElement') {
        foreach ($varInfo in $Node.VarsWritten) {
            if ($varInfo.Name -match '^_pipe_[a-f0-9]+$') {
                # 将执行结果赋值给管道变量
                $pipeVarName = $varInfo.Name
                $Context.ExecContext.Runspace.SessionStateProxy.SetVariable($pipeVarName, $execResult.Result)
            }
        }
    }

    # 条件节点记录结果
    $conditionTypes = @('Condition', 'ForEachCondition', 'SwitchCondition', 'CaseCondition')
    if ($Node.Type -in $conditionTypes) {
        if ($execResult.Success -and $null -ne $execResult.Result -and $execResult.Result.Count -gt 0) {
            $Context.LastConditionResult = [bool]$execResult.Result[0]
        } else {
            $Context.LastConditionResult = $false
        }
    }

    # 执行成功后，对节点中的可还原表达式求值
    if ($execResult.Success) {
        Evaluate-NodeResolvables -Node $Node -Context $Context
    }

    return @{
        Success  = $execResult.Success
        Executed = $true
        Result   = $execResult.Result
        Error    = $execResult.Error
    }
}

# 节点遍历（递归）
function Invoke-NodeTraverse {
    param(
        $Node,
        [hashtable]$Context
    )

    # 终止条件
    if ($null -eq $Node) { return }

    if ($Node.Type -eq "End") {
        Write-ExecutionLog -Context $Context -Message "=== 执行结束 ==="
        return
    }

    if ($Context.TotalVisits -ge $Context.MaxTotalNodes) {
        Write-ExecutionLog -Context $Context -Message "!!! 达到最大节点访问次数 ($($Context.MaxTotalNodes)) !!!"
        return
    }

    # 循环检测
    $nodeKey = $Node.Id
    if (-not $Context.VisitedNodes.ContainsKey($nodeKey)) {
        $Context.VisitedNodes[$nodeKey] = 0
    }
    if ($Context.VisitedNodes[$nodeKey] -ge $Context.MaxIterations) {
        Write-ExecutionLog -Context $Context -Message "!!! 节点 $nodeKey 达到最大迭代次数 ($($Context.MaxIterations)) !!!"
        return
    }

    $Context.VisitedNodes[$nodeKey]++
    $Context.TotalVisits++

    # 记录执行前的变量值（读取的变量）
    $varsBefore = @{}
    foreach ($varInfo in $Node.VarsRead) {
        $varName = $varInfo.Name
        $value = Get-VariableFromContext -ExecContext $Context.ExecContext -Name $varName
        $varsBefore[$varName] = $value
    }

    # 执行节点
    $execResult = Invoke-Node -Node $Node -Context $Context

    # 记录执行后的变量值（写入的变量）
    $varsAfter = @{}
    foreach ($varInfo in $Node.VarsWritten) {
        $varName = $varInfo.Name
        $value = Get-VariableFromContext -ExecContext $Context.ExecContext -Name $varName
        $varsAfter[$varName] = $value
    }

    # 写日志
    $shortText = $Node.Text  # 显示完整代码
    $status = if (-not $execResult.Executed) { "SKIP" } elseif ($execResult.Success) { "OK" } else { "ERR" }

    Write-ExecutionLog -Context $Context -Message "--- Node $($Node.Id) [$status] ---"
    Write-ExecutionLog -Context $Context -Message "  Type: $($Node.Type)"
    Write-ExecutionLog -Context $Context -Message "  Code: $shortText"

    if ($execResult.Executed) {
        # 记录读取的变量
        if ($varsBefore.Count -gt 0) {
            Write-ExecutionLog -Context $Context -Message "  VarsRead:"
            foreach ($kv in $varsBefore.GetEnumerator()) {
                $formattedValue = Format-VariableValue $kv.Value
                Write-ExecutionLog -Context $Context -Message "    `$$($kv.Key) = $formattedValue"
            }
        }

        # 记录写入的变量
        if ($varsAfter.Count -gt 0) {
            Write-ExecutionLog -Context $Context -Message "  VarsWritten:"
            foreach ($kv in $varsAfter.GetEnumerator()) {
                $formattedValue = Format-VariableValue $kv.Value
                Write-ExecutionLog -Context $Context -Message "    `$$($kv.Key) = $formattedValue"
            }
        }

        # 记录执行结果
        if ($null -ne $execResult.Result -and $execResult.Result.Count -gt 0) {
            $formattedResult = Format-VariableValue $execResult.Result
            Write-ExecutionLog -Context $Context -Message "  Result: $formattedResult"
        }

        # 记录错误
        if (-not $execResult.Success -and $execResult.Error) {
            Write-ExecutionLog -Context $Context -Message "  Error: $($execResult.Error)"
        }

        # 记录条件结果
        if ($Node.Type -in @('Condition', 'ForEachCondition', 'SwitchCondition', 'CaseCondition')) {
            Write-ExecutionLog -Context $Context -Message "  ConditionResult: $($Context.LastConditionResult)"
        }
    }

    # 获取后继节点并遍历
    $nextNodes = Get-NextNodes -CFG $Context.CFG -Node $Node -Context $Context
    foreach ($next in $nextNodes) {
        Invoke-NodeTraverse -Node $next -Context $Context
    }
}

# 主入口
function Invoke-CFGTraversal {
    param(
        [Parameter(Mandatory)]
        [hashtable]$CFG,
        [string]$LogPath = "execution.log",
        [int]$MaxIterations = 1000,
        [int]$MaxTotalNodes = 50000
    )

    # 创建/清空日志文件
    $null = New-Item -Path $LogPath -ItemType File -Force

    # 创建执行上下文
    $execContext = New-ExecutionContext

    $context = @{
        CFG                 = $CFG
        ExecContext         = $execContext
        LogPath             = $LogPath
        VisitedNodes        = @{}
        MaxIterations       = $MaxIterations
        MaxTotalNodes       = $MaxTotalNodes
        TotalVisits         = 0
        LastConditionResult = $true
        ResolvableResults   = @{}  # Key: "NodeId:StartOffset:EndOffset", Value: @{ NodeId, Resolvable, Values }
    }

    Write-ExecutionLog -Context $context -Message "=== CFG 执行开始 ==="
    Write-ExecutionLog -Context $context -Message "MaxIterations: $MaxIterations, MaxTotalNodes: $MaxTotalNodes"
    Write-ExecutionLog -Context $context -Message ""

    try {
        # 找到 Start 节点
        $startNode = $CFG.Nodes | Where-Object { $_.Type -eq "Start" } | Select-Object -First 1

        if ($null -eq $startNode) {
            Write-ExecutionLog -Context $context -Message "!!! 未找到 Start 节点 !!!"
            return $context
        }

        # 开始遍历
        Invoke-NodeTraverse -Node $startNode -Context $context
    }
    finally {
        Write-ExecutionLog -Context $context -Message ""
        Write-ExecutionLog -Context $context -Message "=== 执行统计 ==="
        Write-ExecutionLog -Context $context -Message "Total visits: $($context.TotalVisits)"
        Write-ExecutionLog -Context $context -Message "Unique nodes: $($context.VisitedNodes.Count)"

        # 清理执行上下文
        Close-ExecutionContext -ExecContext $execContext
    }

    return $context
}
