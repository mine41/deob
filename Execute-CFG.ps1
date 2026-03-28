# Execute-CFG.ps1
# CFG 遍历执行器 - 基础版本

. "$PSScriptRoot\ConvertTo-Expression-origin.ps1"

# 占位符标识常量 - 重建脚本时遇到此值则不替换原片段
$script:BlockedPlaceholderMarker = "__BLOCKED_PLACEHOLDER__"

# 定义占位符类 - 用于被阻止的命令结果，支持链式属性/方法访问而不报错
Add-Type -TypeDefinition @'
using System;
using System.Dynamic;
using System.Linq.Expressions;

public class BlockedCommandPlaceholder : DynamicObject
{
    // 统一的标识字符串
    public static readonly string Marker = "__BLOCKED_PLACEHOLDER__";

    public string BlockedCommand { get; set; }
    public string Reason { get; set; }

    public BlockedCommandPlaceholder() { }
    public BlockedCommandPlaceholder(string command, string reason)
    {
        BlockedCommand = command;
        Reason = reason;
    }

    // 任何属性访问返回自身
    public override bool TryGetMember(GetMemberBinder binder, out object result)
    {
        result = this;
        return true;
    }

    // 任何属性设置静默成功
    public override bool TrySetMember(SetMemberBinder binder, object value)
    {
        return true;
    }

    // 任何方法调用返回自身
    public override bool TryInvokeMember(InvokeMemberBinder binder, object[] args, out object result)
    {
        result = this;
        return true;
    }

    // 任何索引访问返回自身
    public override bool TryGetIndex(GetIndexBinder binder, object[] indexes, out object result)
    {
        result = this;
        return true;
    }

    // 任何索引设置静默成功
    public override bool TrySetIndex(SetIndexBinder binder, object[] indexes, object value)
    {
        return true;
    }

    // 作为函数调用时返回自身
    public override bool TryInvoke(InvokeBinder binder, object[] args, out object result)
    {
        result = this;
        return true;
    }

    // 类型转换 - 返回标识字符串
    public override bool TryConvert(ConvertBinder binder, out object result)
    {
        if (binder.Type == typeof(string))
        {
            result = Marker;
            return true;
        }
        if (binder.Type == typeof(bool))
        {
            result = false;
            return true;
        }
        if (binder.Type == typeof(int) || binder.Type == typeof(long) ||
            binder.Type == typeof(double) || binder.Type == typeof(float))
        {
            result = 0;
            return true;
        }
        result = null;
        return false;
    }

    // ToString 返回标识字符串
    public override string ToString()
    {
        return Marker;
    }

    // 用于判断是否为占位符
    public bool IsBlockedPlaceholder { get { return true; } }
}
'@ -ErrorAction SilentlyContinue

# 创建占位符实例的辅助函数
function New-BlockedPlaceholder {
    param(
        [string]$Command,
        [string]$Reason = "Forbidden command"
    )
    return [BlockedCommandPlaceholder]::new($Command, $Reason)
}

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
    $psVar = $ExecContext.Runspace.SessionStateProxy.PSVariable.Get($Name)
    if ($null -eq $psVar) {
        return $null
    }

    $value = $psVar.Value
    # 关键：函数输出会枚举数组，空数组会丢失为 $null；这里强制不枚举数组值。
    if ($value -is [array]) {
        Write-Output -NoEnumerate $value
        return
    }
    return $value
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
    param(
        $Value,
        [int]$Depth = 0
    )

    function Get-TextPreview {
        param(
            [string]$Text,
            [int]$MaxLen = 120
        )
        if ($null -eq $Text) { return '' }
        $clean = $Text -replace "`r", '\r' -replace "`n", '\n'
        if ($clean.Length -gt $MaxLen) {
            return $clean.Substring(0, $MaxLen - 3) + '...'
        }
        return $clean
    }

    if ($null -eq $Value) {
        return '$null'
    }

    # 占位符类型
    if ($Value -is [BlockedCommandPlaceholder]) {
        return $script:BlockedPlaceholderMarker
    }

    $type = $Value.GetType().Name

    # 避免深层递归造成过长文本
    if ($Depth -ge 3) {
        if ($Value -is [string]) {
            return "`"$(Get-TextPreview -Text $Value -MaxLen 80)`""
        }
        return "[$type]"
    }

    # Char[] 展示字符串内容
    if ($Value -is [char[]]) {
        $count = $Value.Length
        $text = -join $Value
        $preview = Get-TextPreview -Text $text -MaxLen 160
        return "[Char[]] Count=$count `"$preview`""
    }

    # Byte[] 展示十六进制预览
    if ($Value -is [byte[]]) {
        $count = $Value.Length
        $max = [Math]::Min(24, $count)
        if ($max -le 0) {
            return "[Byte[]] Count=0"
        }
        $hex = for ($i = 0; $i -lt $max; $i++) { '{0:X2}' -f $Value[$i] }
        $suffix = if ($count -gt $max) { ' ...' } else { '' }
        return "[Byte[]] Count=$count Hex=$($hex -join ' ')$suffix"
    }

    # 字典对象显示 key=value 预览
    if ($Value -is [System.Collections.IDictionary]) {
        $maxPairs = 6
        $pairs = New-Object System.Collections.Generic.List[string]
        $i = 0
        foreach ($k in $Value.Keys) {
            if ($i -ge $maxPairs) { break }
            $vText = Format-VariableValue -Value $Value[$k] -Depth ($Depth + 1)
            $pairs.Add("$k=$vText")
            $i++
        }
        $suffix = if ($Value.Count -gt $maxPairs) { '; ...' } else { '' }
        return "[$type] @{ $($pairs -join '; ')$suffix }"
    }

    # 数组/集合
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $maxPreviewItems = 8
        $knownCount = $null

        if ($Value -is [array]) {
            $knownCount = $Value.Length
        } elseif ($Value -is [System.Collections.ICollection]) {
            try { $knownCount = [int]$Value.Count } catch { $knownCount = $null }
        }

        $items = New-Object System.Collections.Generic.List[string]
        $idx = 0
        $hasMore = $false
        foreach ($item in $Value) {
            if ($idx -ge $maxPreviewItems) {
                $hasMore = $true
                break
            }
            $items.Add((Format-VariableValue -Value $item -Depth ($Depth + 1)))
            $idx++
        }

        if (-not $hasMore -and $null -ne $knownCount -and $knownCount -gt $maxPreviewItems) {
            $hasMore = $true
        }

        $suffix = if ($hasMore) { ', ...' } else { '' }
        $itemsText = $items -join ', '
        if ($null -ne $knownCount) {
            return "[$type] Count=$knownCount @($itemsText$suffix)"
        }
        return "[$type] @($itemsText$suffix)"
    }

    # 字符串
    if ($Value -is [string]) {
        return "`"$(Get-TextPreview -Text $Value -MaxLen 120)`""
    }

    # 数字/布尔
    if ($Value -is [ValueType]) {
        return "$Value"
    }

    # 其他对象
    $objText = [string]$Value
    if (-not [string]::IsNullOrWhiteSpace($objText) -and $objText -ne $type -and $objText -notmatch '^System\.') {
        $preview = Get-TextPreview -Text $objText -MaxLen 120
        return "[$type] $preview"
    }
    return "[$type]"
}

# 写日志
function Write-ExecutionLog {
    param(
        [hashtable]$Context,
        [string]$Message
    )

    # 允许禁用日志（用于高性能模式）
    if ($null -eq $Context -or [string]::IsNullOrWhiteSpace($Context.LogPath)) {
        return
    }

    $timestamp = Get-Date -Format "HH:mm:ss.fff"
    $logLine = "[$timestamp] $Message"

    # 写入文件
    Add-Content -Path $Context.LogPath -Value $logLine -Encoding UTF8

    # 同时输出到控制台（可选）
    # Write-Host $logLine
}

# 解析节点 Text（执行期仅以 Node.Text 为准）
function Get-NodeTextParseInfo {
    param(
        $Node,
        [hashtable]$Context
    )

    if (-not $Context.TextParseCache) {
        $Context.TextParseCache = @{}
    }

    $text = [string]$Node.Text
    $cacheKey = "$($Node.Id):$text"
    if ($Context.TextParseCache.ContainsKey($cacheKey)) {
        return $Context.TextParseCache[$cacheKey]
    }

    if ([string]::IsNullOrWhiteSpace($text)) {
        $result = [PSCustomObject]@{
            Success = $false
            Ast     = $null
            Tokens  = @()
            Errors  = @()
            Error   = "Node.Text is empty"
        }
        $Context.TextParseCache[$cacheKey] = $result
        return $result
    }

    $errors = $null
    $tokens = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$errors)

    $parseErrors = @($errors)
    $success = ($parseErrors.Count -eq 0)
    $errorText = if ($success) { $null } else { ($parseErrors | ForEach-Object { $_.Message }) -join "; " }

    $result = [PSCustomObject]@{
        Success = $success
        Ast     = $ast
        Tokens  = @($tokens)
        Errors  = $parseErrors
        Error   = $errorText
    }

    $Context.TextParseCache[$cacheKey] = $result
    return $result
}

function Convert-CodeForCurrentScope {
    param(
        [string]$Code,
        [hashtable]$Context
    )

    if ($Context.CurrentScopePrefix -and $Context.ScopeStack.Count -gt 0) {
        $currentScope = $Context.ScopeStack[-1]
        if ($currentScope.LocalVars -and $currentScope.LocalVars.Count -gt 0) {
            return Convert-VariableNames -Code $Code -ScopePrefix $currentScope.ScopePrefix -LocalVarNames $currentScope.LocalVars
        }
    }
    return $Code
}

function Get-FirstStatementFromScriptAst {
    param($ScriptAst)

    if ($null -eq $ScriptAst) { return $null }

    $blocks = @()
    if ($ScriptAst.BeginBlock) { $blocks += $ScriptAst.BeginBlock }
    if ($ScriptAst.ProcessBlock) { $blocks += $ScriptAst.ProcessBlock }
    if ($ScriptAst.EndBlock) { $blocks += $ScriptAst.EndBlock }

    foreach ($block in $blocks) {
        if ($block.Statements -and $block.Statements.Count -gt 0) {
            return $block.Statements[0]
        }
    }

    return $null
}

function Get-PrimaryCommandAstFromScriptAst {
    param($ScriptAst)

    $statement = Get-FirstStatementFromScriptAst -ScriptAst $ScriptAst
    if ($null -eq $statement) { return $null }

    # 在指定 AST 子树中查找“最靠前”的 CommandAst（按 Extent.StartOffset），并排除 ScriptBlockExpressionAst 内部命令
    function Find-FirstCommandAst {
        param($AstRoot)

        if ($null -eq $AstRoot) { return $null }

        $cmds = @($AstRoot.FindAll({
            param($n)
            if (-not ($n -is [System.Management.Automation.Language.CommandAst])) { return $false }

            # 排除 ScriptBlockExpressionAst 内部的命令：这些命令不在当前语句立即执行（由管道/脚本块调用逻辑单独处理）
            $ancestor = $n.Parent
            while ($null -ne $ancestor -and $ancestor -ne $AstRoot) {
                if ($ancestor -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
                    return $false
                }
                $ancestor = $ancestor.Parent
            }
            return $true
        }, $true))

        if ($cmds.Count -eq 0) { return $null }
        return @($cmds | Sort-Object { $_.Extent.StartOffset } | Select-Object -First 1)
    }

    # 1) 赋值语句：优先在右侧表达式中找命令（支持 CommandExpressionAst，如 $c = (input "xxx").Content）
    if ($statement -is [System.Management.Automation.Language.AssignmentStatementAst]) {
        return Find-FirstCommandAst -AstRoot $statement.Right
    }

    # 2) Pipeline：优先按 PipelineElements 顺序找“直接命令”，否则在 CommandExpressionAst.Expression 中找
    if ($statement -is [System.Management.Automation.Language.PipelineAst] -and
        $statement.PipelineElements -and $statement.PipelineElements.Count -gt 0) {
        foreach ($elem in $statement.PipelineElements) {
            if ($elem -is [System.Management.Automation.Language.CommandAst]) {
                return $elem
            }
            if ($elem -is [System.Management.Automation.Language.CommandExpressionAst]) {
                $cmd = Find-FirstCommandAst -AstRoot $elem.Expression
                if ($cmd) { return $cmd }
            }
        }
        return $null
    }

    # 3) 直接命令
    if ($statement -is [System.Management.Automation.Language.CommandAst]) {
        return $statement
    }

    # 4) CommandExpressionAst：在表达式中找命令
    if ($statement -is [System.Management.Automation.Language.CommandExpressionAst]) {
        return Find-FirstCommandAst -AstRoot $statement.Expression
    }

    # 5) 兜底：在整条语句中找命令
    return Find-FirstCommandAst -AstRoot $statement
}

function Get-NodeTextExecutionInfo {
    param(
        $Node,
        [hashtable]$Context
    )

    $parseInfo = Get-NodeTextParseInfo -Node $Node -Context $Context
    if (-not $parseInfo.Success) {
        return [PSCustomObject]@{
            Success       = $false
            Error         = $parseInfo.Error
            ParseInfo     = $parseInfo
            Statement     = $null
            CommandAst    = $null
            TargetVarName = $null
        }
    }

    $statement = Get-FirstStatementFromScriptAst -ScriptAst $parseInfo.Ast
    $targetVarName = $null
    if ($statement -is [System.Management.Automation.Language.AssignmentStatementAst]) {
        $leftAst = $statement.Left
        if ($leftAst -is [System.Management.Automation.Language.VariableExpressionAst]) {
            $targetVarName = $leftAst.VariablePath.UserPath
        }
    }

    return [PSCustomObject]@{
        Success       = $true
        Error         = $null
        ParseInfo     = $parseInfo
        Statement     = $statement
        CommandAst    = Get-PrimaryCommandAstFromScriptAst -ScriptAst $parseInfo.Ast
        TargetVarName = $targetVarName
    }
}

function Get-NodeTextScriptBlockArguments {
    param(
        $CallerNode,
        [string]$BlockName,
        [hashtable]$Context
    )

    $execInfo = Get-NodeTextExecutionInfo -Node $CallerNode -Context $Context
    if (-not $execInfo.Success) {
        return [PSCustomObject]@{
            Success   = $false
            Error     = $execInfo.Error
            Arguments = @()
        }
    }

    $arguments = @()
    $scriptAst = $execInfo.ParseInfo.Ast

    # 1) 优先处理 $sb.Invoke(...) 形式
    $invokeAst = $scriptAst.Find({
        param($n)
        if (-not ($n -is [System.Management.Automation.Language.InvokeMemberExpressionAst])) { return $false }
        if (-not ($n.Member -is [System.Management.Automation.Language.StringConstantExpressionAst])) { return $false }
        return $n.Member.Value -eq "Invoke"
    }, $true)

    if ($invokeAst -and $invokeAst.Arguments) {
        foreach ($argAst in $invokeAst.Arguments) {
            $argCode = Convert-CodeForCurrentScope -Code $argAst.Extent.Text -Context $Context
            $argResult = Invoke-InContext -ExecContext $Context.ExecContext -Code $argCode
            if ($argResult.Success) {
                $argValue = if ($argResult.Result -is [System.Collections.ObjectModel.Collection[System.Management.Automation.PSObject]] -and $argResult.Result.Count -eq 1) {
                    $argResult.Result[0]
                } else {
                    $argResult.Result
                }
                $arguments += $argValue
            } else {
                $arguments += $null
            }
        }

        return [PSCustomObject]@{
            Success   = $true
            Error     = $null
            Arguments = $arguments
        }
    }

    # 2) CommandAst 形式
    $cmdAst = $execInfo.CommandAst
    if (-not $cmdAst) {
        return [PSCustomObject]@{
            Success   = $true
            Error     = $null
            Arguments = @()
        }
    }

    $cmdName = $cmdAst.GetCommandName()
    if ($cmdName -in @('Invoke-Command', 'icm')) {
        $i = 1
        while ($i -lt $cmdAst.CommandElements.Count) {
            $elem = $cmdAst.CommandElements[$i]
            if ($elem -is [System.Management.Automation.Language.CommandParameterAst] -and
                $elem.ParameterName -in @('ArgumentList', 'Args')) {
                $argListAst = $null
                if ($elem.Argument) {
                    $argListAst = $elem.Argument
                } elseif ($i + 1 -lt $cmdAst.CommandElements.Count) {
                    $i++
                    $argListAst = $cmdAst.CommandElements[$i]
                }
                if ($argListAst) {
                    $arguments = Get-ArgumentListValues -Ast $argListAst -Context $Context
                    break
                }
            }
            $i++
        }

        return [PSCustomObject]@{
            Success   = $true
            Error     = $null
            Arguments = $arguments
        }
    }

    # 3) & $block / . $block 形式
    $startIndex = 1
    for ($i = 0; $i -lt $cmdAst.CommandElements.Count; $i++) {
        $elem = $cmdAst.CommandElements[$i]
        if ($elem -is [System.Management.Automation.Language.VariableExpressionAst]) {
            $varName = $elem.VariablePath.UserPath
            if ($varName -eq $BlockName) {
                $startIndex = $i + 1
                break
            }
        }
    }

    for ($i = $startIndex; $i -lt $cmdAst.CommandElements.Count; $i++) {
        $argAst = $cmdAst.CommandElements[$i]
        if ($argAst -is [System.Management.Automation.Language.CommandParameterAst]) {
            continue
        }

        $argCode = Convert-CodeForCurrentScope -Code $argAst.Extent.Text -Context $Context
        $argResult = Invoke-InContext -ExecContext $Context.ExecContext -Code $argCode
        if ($argResult.Success) {
            $argValue = if ($argResult.Result -is [System.Collections.ObjectModel.Collection[System.Management.Automation.PSObject]] -and $argResult.Result.Count -eq 1) {
                $argResult.Result[0]
            } else {
                $argResult.Result
            }
            $arguments += $argValue
        } else {
            $arguments += $null
        }
    }

    return [PSCustomObject]@{
        Success   = $true
        Error     = $null
        Arguments = $arguments
    }
}

function Get-NodeTextReturnExpression {
    param(
        $Node,
        [hashtable]$Context
    )

    $parseInfo = Get-NodeTextParseInfo -Node $Node -Context $Context
    if (-not $parseInfo.Success) {
        return [PSCustomObject]@{
            Success = $false
            Error   = $parseInfo.Error
            Code    = $null
        }
    }

    $returnAst = $parseInfo.Ast.Find({
        param($n)
        $n -is [System.Management.Automation.Language.ReturnStatementAst]
    }, $true)

    if ($returnAst -and $returnAst.Pipeline) {
        return [PSCustomObject]@{
            Success = $true
            Error   = $null
            Code    = $returnAst.Pipeline.Extent.Text
        }
    }

    return [PSCustomObject]@{
        Success = $true
        Error   = $null
        Code    = $null
    }
}

function Get-DynamicArgumentCodeFromNodeText {
    param(
        $Node,
        [hashtable]$Context,
        [string]$DynamicType
    )

    $parseInfo = Get-NodeTextParseInfo -Node $Node -Context $Context
    if (-not $parseInfo.Success) {
        return [PSCustomObject]@{
            Success = $false
            Error   = $parseInfo.Error
            Code    = $null
        }
    }

    $scriptAst = $parseInfo.Ast
    $argCode = $null

    if ($DynamicType -in @("ScriptBlockCreate", "NewScriptBlock")) {
        $invokeAsts = @($scriptAst.FindAll({
            param($n)
            $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst]
        }, $true))

        foreach ($invokeAst in $invokeAsts) {
            $memberName = $invokeAst.Member
            if ($memberName -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                $memberName = $memberName.Value
            }

            if ($DynamicType -eq "ScriptBlockCreate") {
                if ($invokeAst.Static -and $memberName -eq "Create" -and $invokeAst.Arguments -and $invokeAst.Arguments.Count -gt 0) {
                    $argCode = $invokeAst.Arguments[0].Extent.Text
                    break
                }
            } elseif ($DynamicType -eq "NewScriptBlock") {
                if (-not $invokeAst.Static -and $memberName -eq "NewScriptBlock" -and $invokeAst.Arguments -and $invokeAst.Arguments.Count -gt 0) {
                    $argCode = $invokeAst.Arguments[0].Extent.Text
                    break
                }
            }
        }
    }

    if (-not $argCode) {
        $cmdAst = Get-PrimaryCommandAstFromScriptAst -ScriptAst $scriptAst
        if ($cmdAst -and $cmdAst.CommandElements -and $cmdAst.CommandElements.Count -gt 1) {
            $cmdName = $cmdAst.GetCommandName()
            $isIex = $cmdName -in @("Invoke-Expression", "iex")
            $isScriptBlockCreateCommand = $cmdName -match '^\[(?:System\.Management\.Automation\.)?ScriptBlock\]::Create$'
            if (($DynamicType -eq "IEX" -and $isIex) -or
                ($DynamicType -eq "ScriptBlockCreate" -and $isScriptBlockCreateCommand)) {
                $argCode = $cmdAst.CommandElements[1].Extent.Text
            }
        }
    }

    return [PSCustomObject]@{
        Success = $true
        Error   = $null
        Code    = $argCode
    }
}

function Get-NodeTextResolvables {
    param(
        $Node,
        [hashtable]$Context
    )

    $parseInfo = Get-NodeTextParseInfo -Node $Node -Context $Context
    if (-not $parseInfo.Success) {
        return [PSCustomObject]@{
            Success = $false
            Error   = $parseInfo.Error
            Items   = @()
        }
    }

    $targetTypes = @(
        [System.Management.Automation.Language.BinaryExpressionAst],
        [System.Management.Automation.Language.UnaryExpressionAst],
        [System.Management.Automation.Language.InvokeMemberExpressionAst],
        [System.Management.Automation.Language.ConvertExpressionAst],
        [System.Management.Automation.Language.ExpandableStringExpressionAst],
        [System.Management.Automation.Language.IndexExpressionAst],
        [System.Management.Automation.Language.SubExpressionAst],
        [System.Management.Automation.Language.MemberExpressionAst],
        [System.Management.Automation.Language.ParenExpressionAst],
        [System.Management.Automation.Language.CommandAst]
    )

    $allExprs = @($parseInfo.Ast.FindAll({
        param($n)
        if ($n -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) { return $false }
        ($n -is [System.Management.Automation.Language.BinaryExpressionAst]) -or
        ($n -is [System.Management.Automation.Language.UnaryExpressionAst]) -or
        ($n -is [System.Management.Automation.Language.InvokeMemberExpressionAst]) -or
        ($n -is [System.Management.Automation.Language.ConvertExpressionAst]) -or
        ($n -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) -or
        ($n -is [System.Management.Automation.Language.IndexExpressionAst]) -or
        ($n -is [System.Management.Automation.Language.SubExpressionAst]) -or
        ($n -is [System.Management.Automation.Language.MemberExpressionAst]) -or
        ($n -is [System.Management.Automation.Language.ParenExpressionAst]) -or
        ($n -is [System.Management.Automation.Language.CommandAst])
    }, $true))

    $allExprs = @($allExprs | Where-Object {
        $ancestor = $_.Parent
        while ($null -ne $ancestor -and $ancestor -ne $parseInfo.Ast) {
            if ($ancestor -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
                return $false
            }
            $ancestor = $ancestor.Parent
        }
        return $true
    })

    $sortedExprs = @($allExprs | Sort-Object { $_.Extent.StartOffset })

    $originalQueues = @{}
    if ($Node.Resolvables) {
        foreach ($orig in $Node.Resolvables) {
            $qKey = "$($orig.Type)|$($orig.Text)"
            if (-not $originalQueues.ContainsKey($qKey)) {
                $originalQueues[$qKey] = [System.Collections.Generic.Queue[object]]::new()
            }
            $originalQueues[$qKey].Enqueue($orig)
        }
    }

    $items = @()
    foreach ($expr in $sortedExprs) {
        $type = switch ($true) {
            ($expr -is [System.Management.Automation.Language.BinaryExpressionAst])           { "Binary" }
            ($expr -is [System.Management.Automation.Language.UnaryExpressionAst])            { "Unary" }
            ($expr -is [System.Management.Automation.Language.InvokeMemberExpressionAst])     { "MemberInvoke" }
            ($expr -is [System.Management.Automation.Language.ConvertExpressionAst])          { "Convert" }
            ($expr -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) { "ExpandableString" }
            ($expr -is [System.Management.Automation.Language.IndexExpressionAst])            { "Index" }
            ($expr -is [System.Management.Automation.Language.SubExpressionAst])              { "SubExpression" }
            ($expr -is [System.Management.Automation.Language.MemberExpressionAst])           { "Member" }
            ($expr -is [System.Management.Automation.Language.ParenExpressionAst])            { "Paren" }
            ($expr -is [System.Management.Automation.Language.CommandAst])                    { "Command" }
            default { "Unknown" }
        }

        $depth = 0
        $ancestor = $expr.Parent
        while ($null -ne $ancestor -and $ancestor -ne $parseInfo.Ast) {
            if ($ancestor -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) { break }
            foreach ($t in $targetTypes) {
                if ($ancestor -is $t) { $depth++; break }
            }
            $ancestor = $ancestor.Parent
        }

        $mapped = $false
        $startOffset = $null
        $endOffset = $null
        $qKey = "$type|$($expr.Extent.Text)"
        if ($originalQueues.ContainsKey($qKey) -and $originalQueues[$qKey].Count -gt 0) {
            $orig = $originalQueues[$qKey].Dequeue()
            $mapped = $true
            $startOffset = $orig.StartOffset
            $endOffset = $orig.EndOffset
        }

        $items += [PSCustomObject]@{
            Type             = $type
            Ast              = $expr
            Text             = $expr.Extent.Text
            LocalStartOffset = $expr.Extent.StartOffset
            LocalEndOffset   = $expr.Extent.EndOffset
            Depth            = $depth
            Mapped           = $mapped
            StartOffset      = $startOffset
            EndOffset        = $endOffset
        }
    }

    return [PSCustomObject]@{
        Success = $true
        Error   = $null
        Items   = $items
    }
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

        # ForEach/Process 条件节点
        "ForEachCondition" {
            if ($Context.LastConditionResult) {
                $edge = $edges | Where-Object { $_.Label -eq "Has next" } | Select-Object -First 1
            } else {
                $edge = $edges | Where-Object { $_.Label -eq "No more items" } | Select-Object -First 1
            }
            if ($edge) { return @(Get-NodeById -CFG $CFG -Id $edge.To) }
            return @()
        }
        "ProcessCondition" {
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

    # 占位符类型 - 直接返回标识字符串
    if ($Value -is [BlockedCommandPlaceholder]) {
        return $script:BlockedPlaceholderMarker
    }

    # 处理 PSObject Collection（Invoke-InContext 返回类型）
    if ($Value -is [System.Collections.ObjectModel.Collection[System.Management.Automation.PSObject]]) {
        if ($Value.Count -eq 0) { return '$null' }
        # 检查是否包含占位符
        if ($Value.Count -eq 1) {
            if ($Value[0] -is [BlockedCommandPlaceholder]) {
                return $script:BlockedPlaceholderMarker
            }
            return ConvertTo-Expression -Object $Value[0] -Expand -1
        }
        # 多元素：逐个序列化
        $items = $Value | ForEach-Object {
            if ($_ -is [BlockedCommandPlaceholder]) {
                $script:BlockedPlaceholderMarker
            } else {
                ConvertTo-Expression -Object $_ -Expand -1
            }
        }
        return '@(' + ($items -join ', ') + ')'
    }

    # 处理普通数组
    if ($Value -is [array]) {
        if ($Value.Count -eq 0) { return '$null' }
        if ($Value.Count -eq 1) {
            if ($Value[0] -is [BlockedCommandPlaceholder]) {
                return $script:BlockedPlaceholderMarker
            }
            return ConvertTo-Expression -Object $Value[0] -Expand -1
        }
        $items = $Value | ForEach-Object {
            if ($_ -is [BlockedCommandPlaceholder]) {
                $script:BlockedPlaceholderMarker
            } else {
                ConvertTo-Expression -Object $_ -Expand -1
            }
        }
        return '@(' + ($items -join ', ') + ')'
    }

    return ConvertTo-Expression -Object $Value -Expand -1
}

# 检查值是否适合作为还原结果（简单值类型才有意义替换回脚本）
function Test-ResolvableValue {
    param($Value)

    if ($null -eq $Value) { return $true }

    # PSObject Collection —— 检查内部元素
    if ($Value -is [System.Collections.ObjectModel.Collection[System.Management.Automation.PSObject]]) {
        if ($Value.Count -eq 0) { return $true }
        foreach ($item in $Value) {
            if (-not (Test-ResolvableValue $item)) { return $false }
        }
        return $true
    }

    # 普通数组 —— 检查每个元素
    if ($Value -is [array]) {
        if ($Value.Count -eq 0) { return $true }
        foreach ($item in $Value) {
            if (-not (Test-ResolvableValue $item)) { return $false }
        }
        return $true
    }

    # 允许的简单类型
    if ($Value -is [string])    { return $true }
    if ($Value -is [char])      { return $true }
    if ($Value -is [bool])      { return $true }
    if ($Value -is [byte])      { return $true }
    if ($Value -is [sbyte])     { return $true }
    if ($Value -is [int16])     { return $true }
    if ($Value -is [uint16])    { return $true }
    if ($Value -is [int])       { return $true }
    if ($Value -is [uint32])    { return $true }
    if ($Value -is [int64])     { return $true }
    if ($Value -is [uint64])    { return $true }
    if ($Value -is [float])     { return $true }
    if ($Value -is [double])    { return $true }
    if ($Value -is [decimal])   { return $true }
    if ($Value -is [scriptblock]) { return $true }

    # 占位符类型 - 放行记录，重建脚本时再根据标识跳过
    if ($Value -is [BlockedCommandPlaceholder]) { return $true }

    # 其他类型（复杂对象）不适合还原
    return $false
}

# 求值节点中的可还原表达式
function Evaluate-NodeResolvables {
    param(
        $Node,
        [hashtable]$Context
    )

    # 跳过求值的类型（有副作用或不适合求值）
    $skipEvalTypes = @('Command', 'Unary')  # Command 和 Unary（可能有副作用如 ++/--）

    $resolved = Get-NodeTextResolvables -Node $Node -Context $Context
    if (-not $resolved.Success) {
        Write-ExecutionLog -Context $Context -Message "  [RESOLVE] Parse Node.Text failed at Node $($Node.Id): $($resolved.Error)"
        return
    }

    foreach ($resolvable in $resolved.Items) {
        # 跳过 Command 类型
        if ($resolvable.Type -in $skipEvalTypes) {
            continue
        }

        # 获取表达式代码
        $code = $resolvable.Text

        # 如果处于函数/脚本块作用域中，对局部变量应用前缀转换
        $code = Convert-CodeForCurrentScope -Code $code -Context $Context

        # 在当前 Runspace 上下文中求值
        $evalResult = Invoke-InContext -ExecContext $Context.ExecContext -Code $code

        if ($evalResult.Success) {
            # 检查结果是否为适合还原的简单类型
            if (-not (Test-ResolvableValue $evalResult.Result)) {
                continue
            }

            $value = Format-ResolvableValue $evalResult.Result

            # 无法映射回原偏移时，不写入替换结果（避免误替换）
            if (-not $resolvable.Mapped -or $null -eq $resolvable.StartOffset -or $null -eq $resolvable.EndOffset) {
                continue
            }

            $key = "$($Node.Id):$($resolvable.StartOffset):$($resolvable.EndOffset)"

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

# 直接执行节点（原 Invoke-Node，不进行安全检查）
function Invoke-NodeDirect {
    param(
        $Node,
        [hashtable]$Context,
        [string]$CodeOverride = $null    # 可选的代码覆盖（用于变量名转换后的代码）
    )

    # 虚拟节点（无需执行）
    $virtualTypes = @(
        'Start', 'End', 'MainStart', 'MainEnd',
        'FuncStart', 'FuncEnd', 'BlockStart', 'BlockEnd',
        'FuncParams', 'BlockParams',
        'LoopStart', 'LoopEnd', 'ProcessEnd', 'SwitchStart', 'SwitchEnd',
        'Break', 'Continue', 'Exit',
        'If Condition', 'Else', 'Merge', 'Default',
        'Try', 'Catch', 'Finally', 'FunctionDef'
    )

    if ($Node.Type -in $virtualTypes) {
        return @{
            Success  = $true
            Executed = $false
            Result   = $null
            Error    = $null
            Action   = "Skip"
        }
    }

    # 执行期统一以 Node.Text 为准（CodeOverride 最高优先级）
    $code = if ($CodeOverride) { $CodeOverride } else { $Node.Text }
    if ([string]::IsNullOrWhiteSpace($code)) {
        return @{
            Success  = $false
            Executed = $true
            Result   = $null
            Error    = "Node.Text is empty"
            Action   = "Execute"
        }
    }

    # 在变量前缀转换之前，先处理嵌入的用户函数调用（AST 来自 Node.Text 解析）
    if ($Context.FunctionSubgraphs.Count -gt 0) {
        $parseInfo = Get-NodeTextParseInfo -Node $Node -Context $Context
        if (-not $parseInfo.Success) {
            return @{
                Success  = $false
                Executed = $true
                Result   = $null
                Error    = "Parse Node.Text failed: $($parseInfo.Error)"
                Action   = "Execute"
            }
        }
        $code = Resolve-EmbeddedFunctionCalls -Code $code -Ast $parseInfo.Ast -Context $Context -NodeId $Node.Id
    }

    # 如果处于函数/脚本块作用域中，对局部变量应用前缀转换
    $code = Convert-CodeForCurrentScope -Code $code -Context $Context

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
    $conditionTypes = @('Condition', 'ForEachCondition', 'ProcessCondition', 'SwitchCondition', 'CaseCondition')
    if ($Node.Type -in $conditionTypes) {
        if ($execResult.Success -and $null -ne $execResult.Result -and $execResult.Result.Count -gt 0) {
            $Context.LastConditionResult = [bool]$execResult.Result[0]
        } else {
            $Context.LastConditionResult = $false
        }
    }

    return @{
        Success  = $execResult.Success
        Executed = $true
        Result   = $execResult.Result
        Error    = $execResult.Error
        Action   = "Execute"
    }
}

# 安全执行节点（新的主入口，包含安全检查）
function Invoke-NodeSafe {
    param(
        $Node,
        [hashtable]$Context
    )

    # 虚拟节点类型
    $virtualTypes = @(
        'Start', 'End', 'MainStart', 'MainEnd',
        'FuncStart', 'FuncEnd', 'BlockStart', 'BlockEnd',
        'FuncParams', 'BlockParams',
        'LoopStart', 'LoopEnd', 'ProcessEnd', 'SwitchStart', 'SwitchEnd',
        'If Condition', 'Else', 'Merge', 'Default',
        'Try', 'Catch', 'Finally', 'FunctionDef'
    )

    # 1. 虚拟节点检查 → 跳过执行
    if ($Node.Type -in $virtualTypes) {
        return @{
            Success  = $true
            Executed = $false
            Result   = $null
            Error    = $null
            Action   = "Skip"
        }
    }

    # 2. 脚本块调用检测 - 统一使用 Get-ScriptBlockCallInfo 处理各种形式
    if ($Context.ScriptBlockSubgraphs.Count -gt 0 -and $Node.Ast) {
        $callInfo = Get-ScriptBlockCallInfo -Node $Node -Context $Context
        if ($callInfo -and $callInfo.BlockName -and $Context.ScriptBlockSubgraphs.ContainsKey($callInfo.BlockName)) {
            Write-ExecutionLog -Context $Context -Message "  [CALL] ScriptBlock: $($callInfo.BlockName) (via $($callInfo.CallType) detection)"
            return Invoke-ScriptBlockCall -BlockName $callInfo.BlockName -CallerNode $Node -Context $Context
        }
    }

    # 2.5. 备用：静态检测（当动态检测失败时，使用 Invokes.ScriptBlocks）
    # 【重要】排除定义/赋值节点 - 只有在真正调用脚本块时才跳转
    # 定义/赋值节点的 VarsWritten 会包含脚本块变量，但不应该触发跳转
    if ($Node.Invokes -and $Node.Invokes.ScriptBlocks -and $Node.Invokes.ScriptBlocks.Count -gt 0) {
        $blockName = $Node.Invokes.ScriptBlocks[0]
        if ($Context.ScriptBlockSubgraphs.ContainsKey($blockName)) {
            # 检查是否是定义/赋值节点（VarsWritten 包含脚本块变量）
            $isDefinitionNode = $false
            if ($Node.Ast -is [System.Management.Automation.Language.AssignmentStatementAst]) {
                $isDefinitionNode = $true
            }
            # 也检查 VarsWritten 是否包含脚本块变量名（排除纯定义节点）
            if ($Node.VarsWritten) {
                foreach ($varInfo in $Node.VarsWritten) {
                    if ($varInfo.Name -eq $blockName -or $varInfo.Name -match '^_block_') {
                        $isDefinitionNode = $true
                        break
                    }
                }
            }

            if (-not $isDefinitionNode) {
                # 只有在“真正调用脚本块”的形态下才跳转
                # 避免误把 ForEach-Object/Where-Object 等 cmdlet 的脚本块参数当成调用。
                $isCallForm = $false

                if ($Node.Ast -is [System.Management.Automation.Language.CommandAst]) {
                    if ($Node.Ast.InvocationOperator -in @(
                            [System.Management.Automation.Language.TokenKind]::Ampersand,
                            [System.Management.Automation.Language.TokenKind]::Dot)) {
                        $isCallForm = $true
                    }

                    $cmdName = $Node.Ast.GetCommandName()
                    if ($cmdName -and $cmdName -ieq $blockName) {
                        $isCallForm = $true
                    }
                }
                elseif ($Node.Text -match '^\s*[&\.]') {
                    $isCallForm = $true
                }

                if ($isCallForm) {
                    Write-ExecutionLog -Context $Context -Message "  [CALL] ScriptBlock: $blockName (via Invokes.ScriptBlocks fallback)"
                    return Invoke-ScriptBlockCall -BlockName $blockName -CallerNode $Node -Context $Context
                }
            }
        }
    }

    # 2.8. 函数调用兜底：处理形如 "$_pipe_xxx | FuncName" 的 PipelineElement
    # 这类节点的主命令不一定是函数名，可能绕过常规命令解析。
    if ($Node.Type -eq 'PipelineElement' -and $Node.Invokes -and $Node.Invokes.Functions -and $Node.Invokes.Functions.Count -gt 0) {
        $funcNameFromTopLevel = $null
        $parseInfo = Get-NodeTextParseInfo -Node $Node -Context $Context
        if ($parseInfo.Success) {
            $statement = Get-FirstStatementFromScriptAst -ScriptAst $parseInfo.Ast
            if ($statement -is [System.Management.Automation.Language.PipelineAst]) {
                foreach ($elem in $statement.PipelineElements) {
                    if ($elem -is [System.Management.Automation.Language.CommandAst]) {
                        $name = $elem.GetCommandName()
                        if ($name -and $Context.FunctionSubgraphs.ContainsKey($name)) {
                            $funcNameFromTopLevel = $name
                        }
                    }
                }
            } elseif ($statement -is [System.Management.Automation.Language.CommandAst]) {
                $name = $statement.GetCommandName()
                if ($name -and $Context.FunctionSubgraphs.ContainsKey($name)) {
                    $funcNameFromTopLevel = $name
                }
            }
        }

        if ($funcNameFromTopLevel) {
            Write-ExecutionLog -Context $Context -Message "  [CALL] Function: $funcNameFromTopLevel (pipeline fallback)"
            return Invoke-FunctionCall -FuncName $funcNameFromTopLevel -CallerNode $Node -Context $Context
        }
    }

    # 3. ScriptBlockCreate / NewScriptBlock 动态执行检测
    # 这些不是命令，而是方法调用，需要单独检测
    if ($Node.DynamicInvoke) {
        $dynInfoList = if ($Node.DynamicInvoke -is [array]) { $Node.DynamicInvoke } else { @($Node.DynamicInvoke) }
        foreach ($dynInfo in $dynInfoList) {
            if ($dynInfo.Type -in @("ScriptBlockCreate", "NewScriptBlock")) {
                Write-ExecutionLog -Context $Context -Message "  [DYNAMIC] Dynamic invoke detected: $($dynInfo.Type)"
                return Handle-DynamicInvoke -Node $Node -Context $Context -DynamicInfo $dynInfo
            }
        }
    }

    # 3.5 执行前统一验证 Node.Text 可解析（严格 text-first，不回退 AST）
    $parseInfo = Get-NodeTextParseInfo -Node $Node -Context $Context
    if (-not $parseInfo.Success) {
        return @{
            Success  = $false
            Executed = $true
            Result   = $null
            Error    = "Parse Node.Text failed: $($parseInfo.Error)"
            Action   = "Execute"
        }
    }

    # 检测可疑变量名
    Test-SuspiciousVariables -Node $Node -Context $Context

    # 2. Phase 1: 还原非 Command 表达式
    $resolvedValues = Resolve-NonCommandExpressions -Node $Node -Context $Context

    # 3. Phase 2: 解析真实命令名
    $commandInfo = Get-ResolvedCommandInfo -Node $Node -Context $Context -ResolvedValues $resolvedValues

    # 4. Phase 3: 安全检查
    $checkResult = Test-CommandSafety -CommandInfo $commandInfo -Context $Context

    # 4.5. 记录别名解析结果为可还原表达式
    if ($commandInfo.HasCommand -and $commandInfo.IsAlias) {
        Record-AliasResolution -Node $Node -Context $Context -CommandInfo $commandInfo
    }

    if ($checkResult.IsForbidden) {
        Write-ExecutionLog -Context $Context -Message "  [BLOCKED] Forbidden command: $($commandInfo.ResolvedName) (original: $($commandInfo.OriginalName))"

        # 创建占位符对象
        $placeholder = New-BlockedPlaceholder -Command $commandInfo.ResolvedName -Reason $checkResult.Reason

        # 如果节点有写入的变量，将其设置为占位符，防止后续引用报错
        if ($Node.VarsWritten) {
            foreach ($varInfo in $Node.VarsWritten) {
                $Context.ExecContext.Runspace.SessionStateProxy.SetVariable($varInfo.Name, $placeholder)
                Write-ExecutionLog -Context $Context -Message "  [BLOCKED] Set `$$($varInfo.Name) = [BlockedPlaceholder]"
            }
        }

        return @{
            Success   = $true
            Executed  = $false
            Result    = $placeholder
            Error     = $null
            Action    = "Blocked"
            Command   = $commandInfo.ResolvedName
            Reason    = $checkResult.Reason
        }
    }

    # 5. Phase 4: 执行（根据检查结果选择执行方式）
    switch ($checkResult.Action) {
        "Execute" {
            # 普通执行
            $result = Invoke-NodeDirect -Node $Node -Context $Context

            # 执行成功后，对 Command 类型的可还原表达式求值
            if ($result.Success) {
                Evaluate-NodeResolvables -Node $Node -Context $Context
            }

            return $result
        }
        "ForEachObject" {
            return Invoke-ForEachObjectCmdlet -Node $Node -Context $Context
        }
        "WhereObject" {
            return Invoke-WhereObjectCmdlet -Node $Node -Context $Context
        }
        "SelectObject" {
            return Invoke-SelectObjectCmdlet -Node $Node -Context $Context
        }
        "CallFunction" {
            Write-ExecutionLog -Context $Context -Message "  [CALL] Function: $($checkResult.Target)"
            return Invoke-FunctionCall -FuncName $checkResult.Target -CallerNode $Node -Context $Context
        }
        "CallScriptBlock" {
            Write-ExecutionLog -Context $Context -Message "  [CALL] ScriptBlock: $($checkResult.Target)"
            return Invoke-ScriptBlockCall -BlockName $checkResult.Target -CallerNode $Node -Context $Context
        }
        "DynamicInvoke" {
            Write-ExecutionLog -Context $Context -Message "  [DYNAMIC] Dynamic invoke detected: $($checkResult.Target)"
            return Handle-DynamicInvoke -Node $Node -Context $Context -CommandInfo $commandInfo -DynamicTypeFromCommand $checkResult.DynamicType
        }
        default {
            # 默认执行
            $result = Invoke-NodeDirect -Node $Node -Context $Context

            if ($result.Success) {
                Evaluate-NodeResolvables -Node $Node -Context $Context
            }

            return $result
        }
    }
}

# ========== 函数和脚本块调用 ==========

# 查找函数/脚本块的结束节点
function Get-SubgraphEndNode {
    param(
        [hashtable]$CFG,
        [string]$StartType,      # "FuncStart" 或 "BlockStart"
        [string]$Name            # 函数名或块名
    )

    $endType = if ($StartType -eq "FuncStart") { "FuncEnd" } else { "BlockEnd" }
    $pattern = if ($StartType -eq "FuncStart") {
        "^End function $([regex]::Escape($Name))$"
    } else {
        # 支持 ScriptBlock 和 DynamicBlock 两种格式
        "^End (ScriptBlock|DynamicBlock) $([regex]::Escape($Name))$"
    }

    foreach ($node in $CFG.Nodes) {
        if ($node.Type -eq $endType -and $node.Text -match $pattern) {
            return $node
        }
    }

    return $null
}

# 从调用节点提取上游管道输入（_pipe_xxx）
function Get-CallerPipelineInput {
    param(
        $CallerNode,
        [hashtable]$Context
    )

    $pipeVarNames = @()

    if ($CallerNode -and $CallerNode.VarsRead) {
        foreach ($varInfo in $CallerNode.VarsRead) {
            if ($varInfo.Name -match '^_pipe_[a-f0-9]+$' -and $varInfo.Name -notin $pipeVarNames) {
                $pipeVarNames += $varInfo.Name
            }
        }
    }

    # 兜底：部分节点可能只在 VarsWritten 中记录了管道中间变量
    if ($pipeVarNames.Count -eq 0 -and $CallerNode -and $CallerNode.VarsWritten) {
        foreach ($varInfo in $CallerNode.VarsWritten) {
            if ($varInfo.Name -match '^_pipe_[a-f0-9]+$' -and $varInfo.Name -notin $pipeVarNames) {
                $pipeVarNames += $varInfo.Name
            }
        }
    }

    if ($pipeVarNames.Count -eq 0) {
        return @{
            PipeVar = $null
            Items   = @()
        }
    }

    $pipeVar = $pipeVarNames[0]
    $value = Get-VariableFromContext -ExecContext $Context.ExecContext -Name $pipeVar
    $items = if ($null -eq $value) { @() } else { @($value) }

    return @{
        PipeVar = $pipeVar
        Items   = $items
    }
}

# 将 process 输入注入当前作用域（使用带前缀变量名）
function Initialize-ProcessInputForCurrentScope {
    param(
        [hashtable]$Context,
        [array]$InputItems,
        [string]$SourcePipeVar = $null,
        [string]$InputVarName = "__proc_input"
    )

    if ($Context.ScopeStack.Count -eq 0) { return }

    $scope = $Context.ScopeStack[-1]
    if (-not $scope.LocalVars) {
        $scope.LocalVars = @()
    }
    if ($InputVarName -notin $scope.LocalVars) {
        $scope.LocalVars += $InputVarName
    }

    $actualVarName = $scope.ScopePrefix + $InputVarName
    $valueToSet = if ($null -eq $InputItems) { @() } else { @($InputItems) }
    $Context.ExecContext.Runspace.SessionStateProxy.SetVariable($actualVarName, $valueToSet)

    $sourceText = if ($SourcePipeVar) { "`$$SourcePipeVar" } else { "(empty)" }
    Write-ExecutionLog -Context $Context -Message "  [PROCESS] Set `$$actualVarName from $sourceText (Count=$($valueToSet.Count))"
}

# ========== 管道 foreach-object 支持 ==========

# Push/Pop 当前管道项（$_ / $PSItem），支持嵌套 ForEach-Object
function Push-PipelineCurrent {
    param(
        [hashtable]$Context,
        $Value
    )

    if (-not $Context.PipelineCurrentStack) {
        $Context.PipelineCurrentStack = @()
    }

    $frame = @{
        Underscore = Get-VariableFromContext -ExecContext $Context.ExecContext -Name "_"
        PSItem     = Get-VariableFromContext -ExecContext $Context.ExecContext -Name "PSItem"
    }

    $Context.PipelineCurrentStack = @($Context.PipelineCurrentStack) + @($frame)
    $Context.ExecContext.Runspace.SessionStateProxy.SetVariable("_", $Value)
    $Context.ExecContext.Runspace.SessionStateProxy.SetVariable("PSItem", $Value)
}

function Pop-PipelineCurrent {
    param([hashtable]$Context)

    if (-not $Context.PipelineCurrentStack -or $Context.PipelineCurrentStack.Count -eq 0) {
        return
    }

    $frame = $Context.PipelineCurrentStack[-1]
    if ($Context.PipelineCurrentStack.Count -eq 1) {
        $Context.PipelineCurrentStack = @()
    } else {
        $Context.PipelineCurrentStack = @($Context.PipelineCurrentStack[0..($Context.PipelineCurrentStack.Count - 2)])
    }

    $Context.ExecContext.Runspace.SessionStateProxy.SetVariable("_", $frame.Underscore)
    $Context.ExecContext.Runspace.SessionStateProxy.SetVariable("PSItem", $frame.PSItem)
}

# 输出捕获栈：用于 ForEach-Object 的逐项执行收集输出流
function Push-OutputCapture {
    param([hashtable]$Context)
    if (-not $Context.OutputCaptureStack) {
        $Context.OutputCaptureStack = @()
    }
    $Context.OutputCaptureStack = @($Context.OutputCaptureStack) + @(@{ Outputs = @() })
}

function Pop-OutputCapture {
    param([hashtable]$Context)

    if (-not $Context.OutputCaptureStack -or $Context.OutputCaptureStack.Count -eq 0) {
        return @{ Outputs = @() }
    }

    $frame = $Context.OutputCaptureStack[-1]
    if ($Context.OutputCaptureStack.Count -eq 1) {
        $Context.OutputCaptureStack = @()
    } else {
        $Context.OutputCaptureStack = @($Context.OutputCaptureStack[0..($Context.OutputCaptureStack.Count - 2)])
    }

    return $frame
}

# 将节点执行产生的输出追加到当前输出捕获帧（用于 ForEach-Object 等）
# 注意：只追加到栈顶帧，支持嵌套捕获。
function Add-OutputsToCurrentCapture {
    param(
        [hashtable]$Context,
        $Result
    )

    if (-not $Context.OutputCaptureStack -or $Context.OutputCaptureStack.Count -eq 0) {
        return
    }

    if ($null -eq $Result) { return }

    $frame = $Context.OutputCaptureStack[-1]
    if (-not $frame.ContainsKey('Outputs') -or $null -eq $frame.Outputs) {
        $frame.Outputs = @()
    }

    # Invoke-InContext 返回 Collection[PSObject]；也兼容数组/标量
    if ($Result -is [System.Collections.ObjectModel.Collection[System.Management.Automation.PSObject]]) {
        foreach ($item in $Result) {
            if ($null -ne $item) { $frame.Outputs += $item }
        }
    }
    elseif ($Result -is [array]) {
        foreach ($item in $Result) {
            if ($null -ne $item) { $frame.Outputs += $item }
        }
    }
    else {
        $frame.Outputs += $Result
    }
}

# 统一的“管道脚本块”单次执行：
# - 绑定当前项到 $_ / $PSItem
# - 捕获脚本块子图的可见输出流（用于 ForEach-Object / Where-Object 等）
function Invoke-PipelineScriptBlockOnce {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BlockName,
        $CurrentValue,
        [array]$ProcessInputItems = @(),
        [hashtable]$Context
    )

    if ([string]::IsNullOrWhiteSpace($BlockName)) { return @() }

    Push-PipelineCurrent -Context $Context -Value $CurrentValue
    Push-OutputCapture -Context $Context

    try {
        $null = Invoke-ScriptBlockInline -BlockName $BlockName -Context $Context -Arguments @() -ProcessInputItems $ProcessInputItems
    }
    finally {
        $cap = Pop-OutputCapture -Context $Context
        Pop-PipelineCurrent -Context $Context
    }

    return @($cap.Outputs)
}

# 如果 Node.Text 是赋值语句，则把 ValueToAssign 作为 RHS 结果写入 LHS。
# 用临时变量承载 RHS，避免破坏原表达式结构（与 ForEach-Object 赋值处理一致）。
function Apply-AssignmentIfPresentFromValue {
    param(
        $Node,
        [hashtable]$Context,
        $ValueToAssign,
        [string]$TempVarPrefix = "_pipe_cmdlet_out_",
        [string]$ActionNameForErrors = "PipelineCmdlet"
    )

    $nodeExecInfo = Get-NodeTextExecutionInfo -Node $Node -Context $Context
    if (-not $nodeExecInfo.Success) {
        return @{
            Applied = $false
            Success = $true
            Error   = $null
        }
    }

    if (-not ($nodeExecInfo.Statement -is [System.Management.Automation.Language.AssignmentStatementAst])) {
        return @{
            Applied = $false
            Success = $true
            Error   = $null
        }
    }

    $assignAst = $nodeExecInfo.Statement
    $leftText = $assignAst.Left.Extent.Text
    $opText = switch ($assignAst.Operator) {
        "Equals"           { "=" }
        "PlusEquals"       { "+=" }
        "MinusEquals"      { "-=" }
        "MultiplyEquals"   { "*=" }
        "DivideEquals"     { "/=" }
        "RemainderEquals"  { "%=" }
        default            { "=" }
    }

    $tempVar = $TempVarPrefix + [guid]::NewGuid().ToString("N").Substring(0, 8)
    $Context.ExecContext.Runspace.SessionStateProxy.SetVariable($tempVar, $ValueToAssign)

    $assignCode = "$leftText $opText `$$tempVar"
    $assignCode = Convert-CodeForCurrentScope -Code $assignCode -Context $Context
    $assignResult = Invoke-InContext -ExecContext $Context.ExecContext -Code $assignCode

    try { $Context.ExecContext.Runspace.SessionStateProxy.PSVariable.Remove($tempVar) } catch { }

    if (-not $assignResult.Success) {
        return @{
            Applied = $true
            Success = $false
            Error   = "$ActionNameForErrors assignment failed: $($assignResult.Error)"
        }
    }

    return @{
        Applied = $true
        Success = $true
        Error   = $null
    }
}

# 获取子图参数变量（仅 param(...) 中声明的变量），用于 ForEach-Object 语义：参数隔离，其余变量影响外层作用域
function Get-SubgraphParamVars {
    param(
        [hashtable]$CFG,
        [int]$StartNodeId,
        [int]$EndNodeId
    )

    if (-not $CFG -or -not $CFG.Nodes -or -not $CFG.Edges) { return @() }

    $paramNames = @()
    $visited = @{}
    $queue = [System.Collections.Generic.Queue[int]]::new()
    $queue.Enqueue($StartNodeId)

    while ($queue.Count -gt 0) {
        $nodeId = $queue.Dequeue()
        if ($visited.ContainsKey($nodeId)) { continue }
        $visited[$nodeId] = $true

        if ($nodeId -eq $EndNodeId) { continue }

        $node = $CFG.Nodes | Where-Object { $_.Id -eq $nodeId } | Select-Object -First 1
        if (-not $node) { continue }

        if ($node.Type -in @('FuncParams', 'BlockParams') -and $node.Ast -and $node.Ast.Parameters) {
            foreach ($p in $node.Ast.Parameters) {
                $name = $p.Name.VariablePath.UserPath
                if (-not [string]::IsNullOrWhiteSpace($name)) {
                    $paramNames += $name
                }
            }
            break
        }

        $edges = $CFG.Edges | Where-Object { $_.From -eq $nodeId }
        foreach ($edge in $edges) {
            if (-not $visited.ContainsKey($edge.To)) {
                $queue.Enqueue($edge.To)
            }
        }
    }

    return @($paramNames | Select-Object -Unique)
}

# 内联执行脚本块子图：不通过 CallerNode 跳转，直接同步遍历子图并返回
function Invoke-ScriptBlockInline {
    param(
        [string]$BlockName,
        [hashtable]$Context,
        [array]$Arguments = @(),
        [array]$ProcessInputItems = $null
    )

    if ([string]::IsNullOrWhiteSpace($BlockName)) { return $null }
    if (-not $Context.ScriptBlockSubgraphs.ContainsKey($BlockName)) {
        Write-ExecutionLog -Context $Context -Message "  [FOREACH] ScriptBlock subgraph not found: $BlockName"
        return $null
    }

    $blockStartId = $Context.ScriptBlockSubgraphs[$BlockName]
    $blockStartNode = Get-NodeById -CFG $Context.CFG -Id $blockStartId
    if (-not $blockStartNode) {
        Write-ExecutionLog -Context $Context -Message "  [FOREACH] ScriptBlock start node not found: $BlockName ($blockStartId)"
        return $null
    }

    $blockEndNode = Get-SubgraphEndNode -CFG $Context.CFG -StartType "BlockStart" -Name $BlockName
    if (-not $blockEndNode) {
        Write-ExecutionLog -Context $Context -Message "  [FOREACH] ScriptBlock end node not found: $BlockName"
        return $null
    }
    $blockEndId = $blockEndNode.Id

    $paramVars = Get-SubgraphParamVars -CFG $Context.CFG -StartNodeId $blockStartId -EndNodeId $blockEndId

    Push-ExecutionScope -Context $Context -ScopeType "ScriptBlock" -ScopeName $BlockName -ReturnNodeId 0 -EndNodeId $blockEndId
    $scope = $Context.ScopeStack[-1]
    $scope.LocalVars = $paramVars
    $scope.Arguments = $Arguments
    $scope.TargetVarName = $null

    # 如果脚本块内部有显式 process 块（生成期已转换为 ProcessInit/ProcessCondition/...），需要注入 $__proc_input
    $hasProcessBlock = ($blockStartNode.PSObject.Properties['HasProcessBlock'] -and [bool]$blockStartNode.HasProcessBlock)
    $processInputVarName = if ($blockStartNode.PSObject.Properties['ProcessInputVar']) {
        [string]$blockStartNode.ProcessInputVar
    } else {
        "__proc_input"
    }
    if ($hasProcessBlock) {
        $itemsToSet = if ($null -eq $ProcessInputItems) { @() } else { @($ProcessInputItems) }
        Initialize-ProcessInputForCurrentScope -Context $Context -InputItems $itemsToSet -SourcePipeVar $null -InputVarName $processInputVarName
    }

    Write-ExecutionLog -Context $Context -Message "  [INLINE] Entering ScriptBlock '$BlockName'"
    Invoke-NodeTraverse -Node $blockStartNode -Context $Context

    $result = $Context.LastSubgraphResult
    $Context.LastSubgraphResult = $null
    Write-ExecutionLog -Context $Context -Message "  [INLINE] Exited ScriptBlock '$BlockName' with result: $(Format-VariableValue $result)"
    return $result
}

# 从节点中提取 ForEach-Object 调用信息（Begin/Process/End 脚本块）
function Get-ForEachObjectInvocationInfo {
    param(
        $Node,
        [hashtable]$Context
    )

    $execInfo = Get-NodeTextExecutionInfo -Node $Node -Context $Context
    if (-not $execInfo.Success) {
        return @{
            Success = $false
            Error   = $execInfo.Error
        }
    }

    $cmdAst = $execInfo.CommandAst
    if (-not $cmdAst) {
        return @{
            Success = $false
            Error   = "No CommandAst in Node.Text"
        }
    }

    $cmdName = $cmdAst.GetCommandName()
    if ($cmdName -notin @('ForEach-Object', 'ForEach', '%')) {
        return @{
            Success = $false
            Error   = "Not a ForEach-Object command: $cmdName"
        }
    }

    $beginAst = $null
    $processAst = $null
    $endAst = $null
    $positional = @()

    for ($i = 1; $i -lt $cmdAst.CommandElements.Count; $i++) {
        $elem = $cmdAst.CommandElements[$i]

        if ($elem -is [System.Management.Automation.Language.CommandParameterAst]) {
            $pname = $elem.ParameterName
            if ($pname -in @('Begin', 'Process', 'End')) {
                $argAst = $elem.Argument
                if (-not $argAst -and ($i + 1 -lt $cmdAst.CommandElements.Count)) {
                    $i++
                    $argAst = $cmdAst.CommandElements[$i]
                }

                switch ($pname) {
                    'Begin'   { $beginAst = $argAst }
                    'Process' { $processAst = $argAst }
                    'End'     { $endAst = $argAst }
                }
            }
            continue
        }

        $positional += $elem
    }

    # 兼容位置参数：1 个=Process；2 个=Begin+Process；3 个=Begin+Process+End
    if (-not $beginAst -and -not $processAst -and -not $endAst) {
        $blocks = @()
        foreach ($e in $positional) {
            if ($e -is [System.Management.Automation.Language.VariableExpressionAst] -or
                $e -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
                $blocks += $e
            }
        }

        if ($blocks.Count -eq 1) {
            $processAst = $blocks[0]
        } elseif ($blocks.Count -eq 2) {
            $beginAst = $blocks[0]
            $processAst = $blocks[1]
        } elseif ($blocks.Count -ge 3) {
            $beginAst = $blocks[0]
            $processAst = $blocks[1]
            $endAst = $blocks[2]
        }
    }

    $beginName = if ($beginAst) { Get-ScriptBlockNameFromAst -Ast $beginAst -Context $Context } else { $null }
    $processName = if ($processAst) { Get-ScriptBlockNameFromAst -Ast $processAst -Context $Context } else { $null }
    $endName = if ($endAst) { Get-ScriptBlockNameFromAst -Ast $endAst -Context $Context } else { $null }

    if (-not $processName) {
        return @{
            Success = $false
            Error   = "Cannot resolve Process scriptblock for ForEach-Object"
        }
    }

    return @{
        Success          = $true
        Error            = $null
        CommandName      = $cmdName
        BeginBlockName   = $beginName
        ProcessBlockName = $processName
        EndBlockName     = $endName
    }
}

# 执行 ForEach-Object（逐项执行脚本块子图，并将输出写回 _pipe_ 变量）
function Invoke-ForEachObjectCmdlet {
    param(
        $Node,
        [hashtable]$Context
    )

    $info = Get-ForEachObjectInvocationInfo -Node $Node -Context $Context
    if (-not $info.Success) {
        Write-ExecutionLog -Context $Context -Message "  [FOREACH] Parse failed, fallback to direct execute: $($info.Error)"
        return Invoke-NodeDirect -Node $Node -Context $Context
    }

    $pipelineInput = Get-CallerPipelineInput -CallerNode $Node -Context $Context
    $items = @($pipelineInput.Items)
    $pipeVar = $pipelineInput.PipeVar

    $allOutputs = @()
    $stopAll = $false

    # Begin
    if ($info.BeginBlockName) {
        $Context.LastPipelineFlowControl = $null
        $allOutputs += Invoke-PipelineScriptBlockOnce -BlockName $info.BeginBlockName -CurrentValue $null -ProcessInputItems @() -Context $Context
        if ($Context.LastPipelineFlowControl -eq "Break") {
            $stopAll = $true
        }
    }

    # Process per item
    if (-not $stopAll) {
        foreach ($item in $items) {
            $Context.LastPipelineFlowControl = $null
            $allOutputs += Invoke-PipelineScriptBlockOnce -BlockName $info.ProcessBlockName -CurrentValue $item -ProcessInputItems @($item) -Context $Context
            if ($Context.LastPipelineFlowControl -eq "Break") {
                $stopAll = $true
                break
            }
        }
    }

    # End（若 break，则 End 不执行）
    if (-not $stopAll -and $info.EndBlockName) {
        $Context.LastPipelineFlowControl = $null
        $allOutputs += Invoke-PipelineScriptBlockOnce -BlockName $info.EndBlockName -CurrentValue $null -ProcessInputItems @() -Context $Context
    }

    # 将输出写回 _pipe_xxx（仅当该节点需要产生管道输出）
    $writesPipeVar = $false
    if ($pipeVar -and $Node.VarsWritten) {
        foreach ($varInfo in $Node.VarsWritten) {
            if ($varInfo.Name -eq $pipeVar) {
                $writesPipeVar = $true
                break
            }
        }
    }

    # 输出统一保持为 Collection[PSObject]，与 Invoke-InContext 返回类型一致：
    # - Count=0 表示无输出
    # - Count=1 且元素为数组对象时，语义上仍是“单个对象”，不会被误扁平化
    $valueToStore = [System.Collections.ObjectModel.Collection[System.Management.Automation.PSObject]]::new()
    foreach ($o in $allOutputs) {
        if ($null -ne $o) {
            # 允许占位符等非 PSObject 类型，统一包一层 PSObject
            [void]$valueToStore.Add([System.Management.Automation.PSObject]$o)
        }
    }

    if ($writesPipeVar) {
        $Context.ExecContext.Runspace.SessionStateProxy.SetVariable($pipeVar, $valueToStore)
        Write-ExecutionLog -Context $Context -Message "  [FOREACH] Set `$$pipeVar (Count=$($valueToStore.Count))"
    }

    # 如果该节点是赋值语句：执行赋值（避免直接执行 Node.Text 触发真正的 ForEach-Object）
    $assignApply = Apply-AssignmentIfPresentFromValue -Node $Node -Context $Context -ValueToAssign $valueToStore -TempVarPrefix "_foreach_out_" -ActionNameForErrors "ForEach-Object"
    if ($assignApply.Applied -and -not $assignApply.Success) {
        return @{
            Success  = $false
            Executed = $true
            Result   = $valueToStore
            Error    = $assignApply.Error
            Action   = "ForEachObject"
        }
    }

    return @{
        Success  = $true
        Executed = $true
        Result   = $valueToStore
        Error    = $null
        Action   = "ForEachObject"
    }
}

# 从节点中提取 Where-Object 调用信息（FilterScript 脚本块）
function Get-WhereObjectInvocationInfo {
    param(
        $Node,
        [hashtable]$Context
    )

    $execInfo = Get-NodeTextExecutionInfo -Node $Node -Context $Context
    if (-not $execInfo.Success) {
        return @{
            Success = $false
            Error   = $execInfo.Error
        }
    }

    $cmdAst = $execInfo.CommandAst
    if (-not $cmdAst) {
        return @{
            Success = $false
            Error   = "No CommandAst in Node.Text"
        }
    }

    $cmdName = $cmdAst.GetCommandName()
    if ($cmdName -notin @('Where-Object', 'Where', '?')) {
        return @{
            Success = $false
            Error   = "Not a Where-Object command: $cmdName"
        }
    }

    $filterAst = $null
    $positional = @()

    for ($i = 1; $i -lt $cmdAst.CommandElements.Count; $i++) {
        $elem = $cmdAst.CommandElements[$i]

        if ($elem -is [System.Management.Automation.Language.CommandParameterAst]) {
            $pname = $elem.ParameterName
            if ($pname -in @('FilterScript', 'Filter')) {
                $argAst = $elem.Argument
                if (-not $argAst -and ($i + 1 -lt $cmdAst.CommandElements.Count)) {
                    $i++
                    $argAst = $cmdAst.CommandElements[$i]
                }
                $filterAst = $argAst
            }
            continue
        }

        $positional += $elem
    }

    # 兼容位置参数：Where-Object { ... }
    if (-not $filterAst) {
        foreach ($e in $positional) {
            if ($e -is [System.Management.Automation.Language.VariableExpressionAst] -or
                $e -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
                $filterAst = $e
                break
            }
        }
    }

    $knownBlockNames = @()
    if ($Node.Invokes -and $Node.Invokes.ScriptBlocks) {
        $knownBlockNames = @($Node.Invokes.ScriptBlocks)
    }

    $filterName = if ($filterAst) { Get-ScriptBlockNameFromAst -Ast $filterAst -Context $Context -KnownBlockNames $knownBlockNames } else { $null }
    if (-not $filterName) {
        return @{
            Success = $false
            Error   = "Cannot resolve FilterScript scriptblock for Where-Object"
        }
    }

    return @{
        Success         = $true
        Error           = $null
        CommandName     = $cmdName
        FilterBlockName = $filterName
    }
}

# 执行 Where-Object：逐项执行 FilterScript 子图，并将符合条件的原始输入写回 _pipe_ 变量
function Invoke-WhereObjectCmdlet {
    param(
        $Node,
        [hashtable]$Context
    )

    $info = Get-WhereObjectInvocationInfo -Node $Node -Context $Context
    if (-not $info.Success) {
        Write-ExecutionLog -Context $Context -Message "  [WHERE] Parse failed, fallback to direct execute: $($info.Error)"
        return Invoke-NodeDirect -Node $Node -Context $Context
    }

    $pipelineInput = Get-CallerPipelineInput -CallerNode $Node -Context $Context
    $items = @($pipelineInput.Items)
    $pipeVar = $pipelineInput.PipeVar

    $kept = @()
    $stopAll = $false

    foreach ($item in $items) {
        $Context.LastPipelineFlowControl = $null
        $filterOutputs = Invoke-PipelineScriptBlockOnce -BlockName $info.FilterBlockName -CurrentValue $item -ProcessInputItems @($item) -Context $Context

        # PowerShell 语义：Where-Object 的真假判断基于 FilterScript 的输出流 truthiness
        # - 单个 $false -> False
        # - 多个 $false -> True（非空数组）
        $match = [bool]@($filterOutputs)
        if ($match) {
            $kept += $item
        }

        if ($Context.LastPipelineFlowControl -eq "Break") {
            $stopAll = $true
            break
        }
    }

    # 输出保持为 Collection[PSObject]，与 Invoke-InContext 返回类型一致
    $valueToStore = [System.Collections.ObjectModel.Collection[System.Management.Automation.PSObject]]::new()
    foreach ($o in $kept) {
        if ($null -ne $o) {
            [void]$valueToStore.Add([System.Management.Automation.PSObject]$o)
        }
    }

    # 将输出写回 _pipe_xxx（仅当该节点需要产生管道输出）
    $writesPipeVar = $false
    if ($pipeVar -and $Node.VarsWritten) {
        foreach ($varInfo in $Node.VarsWritten) {
            if ($varInfo.Name -eq $pipeVar) {
                $writesPipeVar = $true
                break
            }
        }
    }

    if ($writesPipeVar) {
        $Context.ExecContext.Runspace.SessionStateProxy.SetVariable($pipeVar, $valueToStore)
        Write-ExecutionLog -Context $Context -Message "  [WHERE] Set `$$pipeVar (Count=$($valueToStore.Count))"
    }

    # 赋值语句：执行赋值（避免直接执行 Node.Text 触发真正的 Where-Object）
    $assignApply = Apply-AssignmentIfPresentFromValue -Node $Node -Context $Context -ValueToAssign $valueToStore -TempVarPrefix "_where_out_" -ActionNameForErrors "Where-Object"
    if ($assignApply.Applied -and -not $assignApply.Success) {
        return @{
            Success  = $false
            Executed = $true
            Result   = $valueToStore
            Error    = $assignApply.Error
            Action   = "WhereObject"
        }
    }

    return @{
        Success  = $true
        Executed = $true
        Result   = $valueToStore
        Error    = $null
        Action   = "WhereObject"
    }
}

# ========== 管道 select-object 支持 ==========

function Get-HashtableKeyString {
    param($KeyAst)
    if ($null -eq $KeyAst) { return $null }
    if ($KeyAst -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
        return $KeyAst.Value
    }
    return [string]$KeyAst.Extent.Text
}

function Get-HashtableValueExpressionAst {
    param($StatementAst)

    if ($null -eq $StatementAst) { return $null }

    if ($StatementAst -is [System.Management.Automation.Language.PipelineAst] -and
        $StatementAst.PipelineElements -and
        $StatementAst.PipelineElements.Count -eq 1) {
        $pe = $StatementAst.PipelineElements[0]
        if ($pe -is [System.Management.Automation.Language.CommandExpressionAst]) {
            return $pe.Expression
        }
    }

    return $null
}

function Get-SelectObjectCalculatedPropertySpecFromHashtableAst {
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Language.HashtableAst]$HashtableAst,
        [hashtable]$Context,
        [array]$KnownBlockNames = @()
    )

    $name = $null
    $exprAst = $null

    foreach ($kv in $HashtableAst.KeyValuePairs) {
        $keyAst = $kv.Item1
        $valStmt = $kv.Item2

        $keyText = (Get-HashtableKeyString -KeyAst $keyAst)
        if ([string]::IsNullOrWhiteSpace($keyText)) { continue }
        # Trim 单引号/双引号（用 `"` 方式在双引号字符串中表示字面双引号）
        $keyNorm = $keyText.Trim("'`"").ToLowerInvariant()

        $valExpr = Get-HashtableValueExpressionAst -StatementAst $valStmt

        if ($keyNorm -in @('n', 'name', 'label', 'l')) {
            if ($valExpr -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                $name = $valExpr.Value
            } elseif ($null -ne $valExpr) {
                $nameVal = Get-AstValue -Ast $valExpr -Context $Context
                if ($null -ne $nameVal) {
                    $name = [string]$nameVal
                }
            }
        }
        elseif ($keyNorm -in @('e', 'expression')) {
            if ($null -ne $valExpr) {
                $exprAst = $valExpr
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($name) -or $null -eq $exprAst) {
        return $null
    }

    $blockName = Get-ScriptBlockNameFromAst -Ast $exprAst -Context $Context -KnownBlockNames $KnownBlockNames
    if ([string]::IsNullOrWhiteSpace($blockName)) {
        return $null
    }

    return [PSCustomObject]@{
        Type      = "Calculated"
        Name      = $name
        BlockName = $blockName
        Text      = $HashtableAst.Extent.Text
    }
}

function Get-SelectObjectInvocationInfo {
    param(
        $Node,
        [hashtable]$Context
    )

    $execInfo = Get-NodeTextExecutionInfo -Node $Node -Context $Context
    if (-not $execInfo.Success) {
        return @{
            Success = $false
            Error   = $execInfo.Error
        }
    }

    $cmdAst = $execInfo.CommandAst
    if (-not $cmdAst) {
        return @{
            Success = $false
            Error   = "No CommandAst in Node.Text"
        }
    }

    $cmdName = $cmdAst.GetCommandName()
    if ($cmdName -notin @('Select-Object', 'Select')) {
        return @{
            Success = $false
            Error   = "Not a Select-Object command: $cmdName"
        }
    }

    $propertyArgAsts = @()
    $excludeArgAsts = @()
    $expandArgAst = $null
    $firstAst = $null
    $lastAst = $null
    $skipAst = $null
    $skipLastAst = $null
    $indexAst = $null
    $unique = $false
    $positional = @()

    for ($i = 1; $i -lt $cmdAst.CommandElements.Count; $i++) {
        $elem = $cmdAst.CommandElements[$i]

        if ($elem -is [System.Management.Automation.Language.CommandParameterAst]) {
            $pname = $elem.ParameterName

            # Switch 参数
            if ($pname -in @('Unique')) {
                $unique = $true
                continue
            }

            $argAst = $elem.Argument
            if (-not $argAst -and ($i + 1 -lt $cmdAst.CommandElements.Count)) {
                $i++
                $argAst = $cmdAst.CommandElements[$i]
            }

            switch ($pname) {
                'Property'        { if ($argAst) { $propertyArgAsts += $argAst } }
                'ExcludeProperty' { if ($argAst) { $excludeArgAsts += $argAst } }
                'ExpandProperty'  { if (-not $expandArgAst -and $argAst) { $expandArgAst = $argAst } }
                'First'           { if (-not $firstAst -and $argAst) { $firstAst = $argAst } }
                'Last'            { if (-not $lastAst -and $argAst) { $lastAst = $argAst } }
                'Skip'            { if (-not $skipAst -and $argAst) { $skipAst = $argAst } }
                'SkipLast'        { if (-not $skipLastAst -and $argAst) { $skipLastAst = $argAst } }
                'Index'           { if (-not $indexAst -and $argAst) { $indexAst = $argAst } }
                default { }
            }

            continue
        }

        $positional += $elem
    }

    # 兼容位置参数：Select-Object Name, Status
    if ($propertyArgAsts.Count -eq 0 -and $positional.Count -gt 0) {
        $propertyArgAsts = @($positional)
    }

    $knownBlockNames = @()
    if ($Node.Invokes -and $Node.Invokes.ScriptBlocks) {
        $knownBlockNames = @($Node.Invokes.ScriptBlocks)
    }

    function Add-PropertySpecAstsFromArg {
        param([ref]$List, $ArgAst)
        if ($null -eq $ArgAst) { return }

        if ($ArgAst -is [System.Management.Automation.Language.ArrayLiteralAst]) {
            foreach ($e in $ArgAst.Elements) {
                $List.Value += $e
            }
        } else {
            $List.Value += $ArgAst
        }
    }

    function Add-StringValuesFromArg {
        param([ref]$List, $ArgAst)
        if ($null -eq $ArgAst) { return }

        $work = @()
        if ($ArgAst -is [System.Management.Automation.Language.ArrayLiteralAst]) {
            $work = @($ArgAst.Elements)
        } else {
            $work = @($ArgAst)
        }

        foreach ($a in $work) {
            if ($a -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                $List.Value += $a.Value
            } else {
                $v = Get-AstValue -Ast $a -Context $Context
                if ($null -eq $v) { continue }
                if ($v -is [array]) {
                    foreach ($vv in $v) {
                        if ($null -ne $vv) { $List.Value += [string]$vv }
                    }
                } else {
                    $List.Value += [string]$v
                }
            }
        }
    }

    # 解析 Property 规格
    $propertySpecAsts = @()
    foreach ($a in $propertyArgAsts) {
        Add-PropertySpecAstsFromArg -List ([ref]$propertySpecAsts) -ArgAst $a
    }

    $propertySpecs = @()
    foreach ($specAst in $propertySpecAsts) {
        if ($specAst -is [System.Management.Automation.Language.HashtableAst]) {
            $calc = Get-SelectObjectCalculatedPropertySpecFromHashtableAst -HashtableAst $specAst -Context $Context -KnownBlockNames $knownBlockNames
            if (-not $calc) {
                return @{
                    Success = $false
                    Error   = "Unsupported calculated property: $($specAst.Extent.Text)"
                }
            }
            $propertySpecs += $calc
            continue
        }

        if ($specAst -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
            $propertySpecs += [PSCustomObject]@{
                Type    = "Name"
                Pattern = $specAst.Value
                Text    = $specAst.Extent.Text
            }
            continue
        }

        $v = Get-AstValue -Ast $specAst -Context $Context
        if ($null -eq $v) {
            return @{
                Success = $false
                Error   = "Cannot evaluate property spec: $($specAst.Extent.Text)"
            }
        }

        if ($v -is [array]) {
            foreach ($vv in $v) {
                if ($null -ne $vv) {
                    $propertySpecs += [PSCustomObject]@{
                        Type    = "Name"
                        Pattern = [string]$vv
                        Text    = $specAst.Extent.Text
                    }
                }
            }
        } else {
            $propertySpecs += [PSCustomObject]@{
                Type    = "Name"
                Pattern = [string]$v
                Text    = $specAst.Extent.Text
            }
        }
    }

    # ExcludeProperty
    $excludePatterns = @()
    foreach ($a in $excludeArgAsts) {
        Add-StringValuesFromArg -List ([ref]$excludePatterns) -ArgAst $a
    }

    # ExpandProperty
    $expandPropName = $null
    if ($expandArgAst) {
        if ($expandArgAst -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
            $expandPropName = $expandArgAst.Value
        } else {
            $v = Get-AstValue -Ast $expandArgAst -Context $Context
            if ($null -ne $v) { $expandPropName = [string]$v }
        }
    }

    # 数字参数
    function Get-IntArgOrNull {
        param($Ast)
        if ($null -eq $Ast) { return $null }
        $v = Get-AstValue -Ast $Ast -Context $Context
        if ($null -eq $v) { return $null }
        try { return [int]$v } catch { return $null }
    }

    function Get-IntListOrNull {
        param($Ast)
        if ($null -eq $Ast) { return $null }

        $list = @()
        if ($Ast -is [System.Management.Automation.Language.ArrayLiteralAst]) {
            foreach ($e in $Ast.Elements) {
                $iv = Get-IntArgOrNull -Ast $e
                if ($null -ne $iv) { $list += $iv }
            }
        } else {
            $iv = Get-IntArgOrNull -Ast $Ast
            if ($null -ne $iv) { $list += $iv }
        }

        if ($list.Count -eq 0) { return $null }
        return $list
    }

    $first = Get-IntArgOrNull -Ast $firstAst
    $last = Get-IntArgOrNull -Ast $lastAst
    $skip = Get-IntArgOrNull -Ast $skipAst
    $skipLast = Get-IntArgOrNull -Ast $skipLastAst
    $indexList = Get-IntListOrNull -Ast $indexAst

    return @{
        Success         = $true
        Error           = $null
        CommandName     = $cmdName
        PropertySpecs   = @($propertySpecs)
        ExcludePatterns = @($excludePatterns)
        ExpandProperty  = $expandPropName
        First           = $first
        Last            = $last
        Skip            = $skip
        SkipLast        = $skipLast
        Index           = $indexList
        Unique          = [bool]$unique
    }
}

function Invoke-SelectObjectCmdlet {
    param(
        $Node,
        [hashtable]$Context
    )

    $info = Get-SelectObjectInvocationInfo -Node $Node -Context $Context
    if (-not $info.Success) {
        Write-ExecutionLog -Context $Context -Message "  [SELECT] Parse failed, fallback to direct execute: $($info.Error)"
        return Invoke-NodeDirect -Node $Node -Context $Context
    }

    $pipelineInput = Get-CallerPipelineInput -CallerNode $Node -Context $Context
    $items = @($pipelineInput.Items)
    $pipeVar = $pipelineInput.PipeVar

    # 1) 对象级裁剪（Index / First / Last / Skip / SkipLast）
    $baseItems = @($items)

    if ($null -ne $info.SkipLast) {
        if ($info.SkipLast -lt 0) {
            return @{
                Success  = $false
                Executed = $true
                Result   = $null
                Error    = "Select-Object: SkipLast must be non-negative"
                Action   = "SelectObject"
            }
        }

        if ($info.SkipLast -ge $baseItems.Count) {
            $baseItems = @()
        } else {
            $baseItems = @($baseItems[0..($baseItems.Count - $info.SkipLast - 1)])
        }
    }

    $count = $baseItems.Count
    $indices = @()

    $skip = if ($null -ne $info.Skip) { [int]$info.Skip } else { 0 }
    $first = $info.First
    $last = $info.Last

    if ($skip -lt 0) {
        return @{
            Success  = $false
            Executed = $true
            Result   = $null
            Error    = "Select-Object: Skip must be non-negative"
            Action   = "SelectObject"
        }
    }
    if ($null -ne $first -and $first -lt 0) {
        return @{
            Success  = $false
            Executed = $true
            Result   = $null
            Error    = "Select-Object: First must be non-negative"
            Action   = "SelectObject"
        }
    }
    if ($null -ne $last -and $last -lt 0) {
        return @{
            Success  = $false
            Executed = $true
            Result   = $null
            Error    = "Select-Object: Last must be non-negative"
            Action   = "SelectObject"
        }
    }

    if ($info.Index -and $info.Index.Count -gt 0) {
        foreach ($idx in $info.Index) {
            if ($idx -lt 0) {
                return @{
                    Success  = $false
                    Executed = $true
                    Result   = $null
                    Error    = "Select-Object: Index must be non-negative"
                    Action   = "SelectObject"
                }
            }
            if ($idx -lt $count) {
                $indices += $idx
            }
        }
    }
    else {
        if ($null -ne $first -and $null -ne $last) {
            # First/Last 并存：按索引并集（保持原始顺序），Skip 仅作用于 First 侧
            $start = [Math]::Min($skip, $count)
            $endFirst = [Math]::Min($count, ($start + $first))
            for ($i = $start; $i -lt $endFirst; $i++) { $indices += $i }

            $startLast = [Math]::Max(0, ($count - $last))
            for ($i = $startLast; $i -lt $count; $i++) { $indices += $i }

            $indices = @($indices | Sort-Object -Unique)
        }
        elseif ($null -ne $first) {
            $start = [Math]::Min($skip, $count)
            $endFirst = [Math]::Min($count, ($start + $first))
            for ($i = $start; $i -lt $endFirst; $i++) { $indices += $i }
        }
        elseif ($null -ne $last) {
            # Last 模式：Skip 语义为“从末尾跳过”，窗口为 [count - skip - last, count - skip)
            $skipFromEnd = $skip
            $endExclusive = [Math]::Max(0, ($count - $skipFromEnd))
            $start = [Math]::Max(0, ($endExclusive - $last))
            for ($i = $start; $i -lt $endExclusive; $i++) { $indices += $i }
        }
        else {
            $start = [Math]::Min($skip, $count)
            for ($i = $start; $i -lt $count; $i++) { $indices += $i }
        }
    }

    $selectedItems = @()
    foreach ($i in $indices) {
        if ($i -ge 0 -and $i -lt $count) {
            $selectedItems += $baseItems[$i]
        }
    }

    function Test-NameMatchesAnyPattern {
        param(
            [string]$Name,
            [string[]]$Patterns
        )
        if ([string]::IsNullOrWhiteSpace($Name) -or -not $Patterns -or $Patterns.Count -eq 0) { return $false }
        foreach ($p in $Patterns) {
            if ([string]::IsNullOrWhiteSpace($p)) { continue }
            if ($Name -like $p) { return $true }
        }
        return $false
    }

    $outputs = @()
    $stopAll = $false

    # 2) ExpandProperty
    if (-not [string]::IsNullOrWhiteSpace($info.ExpandProperty)) {
        $propName = [string]$info.ExpandProperty

        foreach ($item in $selectedItems) {
            if ($null -eq $item) { continue }

            $prop = $item.PSObject.Properties[$propName]
            $v = if ($prop) { $prop.Value } else { $null }
            if ($null -eq $v) { continue }

            if ($v -is [string]) {
                $outputs += $v
                continue
            }

            if ($v -is [System.Collections.IEnumerable]) {
                foreach ($e in $v) {
                    if ($null -ne $e) { $outputs += $e }
                }
                continue
            }

            $outputs += $v
        }
    }
    # 3) Property 投影（含计算属性）
    elseif ($info.PropertySpecs -and $info.PropertySpecs.Count -gt 0) {
        foreach ($item in $selectedItems) {
            if ($null -eq $item) { continue }

            $outObj = New-Object PSObject

            foreach ($spec in $info.PropertySpecs) {
                if ($spec.Type -eq "Name") {
                    $pattern = [string]$spec.Pattern
                    if ([string]::IsNullOrWhiteSpace($pattern)) { continue }

                    $propNames = @($item.PSObject.Properties.Name)
                    $matched = @($propNames | Where-Object { $_ -like $pattern })

                    if ($matched.Count -gt 0) {
                        foreach ($pn in $matched) {
                            if (Test-NameMatchesAnyPattern -Name $pn -Patterns $info.ExcludePatterns) {
                                continue
                            }
                            $p = $item.PSObject.Properties[$pn]
                            $val = if ($p) { $p.Value } else { $null }
                            $outObj | Add-Member -NotePropertyName $pn -NotePropertyValue $val -Force
                        }
                    } else {
                        # 无匹配 → 按字面属性名输出 $null（包括 "*" 的情况）
                        if (-not (Test-NameMatchesAnyPattern -Name $pattern -Patterns $info.ExcludePatterns)) {
                            $outObj | Add-Member -NotePropertyName $pattern -NotePropertyValue $null -Force
                        }
                    }
                }
                elseif ($spec.Type -eq "Calculated") {
                    $propName = [string]$spec.Name
                    $blockName = [string]$spec.BlockName

                    $Context.LastPipelineFlowControl = $null
                    $exprOutputs = Invoke-PipelineScriptBlockOnce -BlockName $blockName -CurrentValue $item -ProcessInputItems @($item) -Context $Context

                    $value = $null
                    if ($exprOutputs.Count -eq 1) {
                        $value = $exprOutputs[0]
                    } elseif ($exprOutputs.Count -gt 1) {
                        $value = @($exprOutputs)
                    }

                    if (-not (Test-NameMatchesAnyPattern -Name $propName -Patterns $info.ExcludePatterns)) {
                        $outObj | Add-Member -NotePropertyName $propName -NotePropertyValue $value -Force
                    }

                    if ($Context.LastPipelineFlowControl -eq "Break") {
                        $stopAll = $true
                        break
                    }
                }
            }

            $outputs += $outObj

            if ($stopAll) { break }
        }
    }
    # 4) 无 Property：identity
    else {
        $outputs = @($selectedItems)
    }

    if ($info.Unique) {
        $outputs = @($outputs | Select-Object -Unique)
    }

    # 输出保持为 Collection[PSObject]，与 Invoke-InContext 返回类型一致
    $valueToStore = [System.Collections.ObjectModel.Collection[System.Management.Automation.PSObject]]::new()
    foreach ($o in $outputs) {
        if ($null -ne $o) {
            [void]$valueToStore.Add([System.Management.Automation.PSObject]$o)
        }
    }

    # 将输出写回 _pipe_xxx（仅当该节点需要产生管道输出）
    $writesPipeVar = $false
    if ($pipeVar -and $Node.VarsWritten) {
        foreach ($varInfo in $Node.VarsWritten) {
            if ($varInfo.Name -eq $pipeVar) {
                $writesPipeVar = $true
                break
            }
        }
    }

    if ($writesPipeVar) {
        $Context.ExecContext.Runspace.SessionStateProxy.SetVariable($pipeVar, $valueToStore)
        Write-ExecutionLog -Context $Context -Message "  [SELECT] Set `$$pipeVar (Count=$($valueToStore.Count))"
    }

    # 赋值语句：执行赋值（避免直接执行 Node.Text 触发真正的 Select-Object）
    $assignApply = Apply-AssignmentIfPresentFromValue -Node $Node -Context $Context -ValueToAssign $valueToStore -TempVarPrefix "_select_out_" -ActionNameForErrors "Select-Object"
    if ($assignApply.Applied -and -not $assignApply.Success) {
        return @{
            Success  = $false
            Executed = $true
            Result   = $valueToStore
            Error    = $assignApply.Error
            Action   = "SelectObject"
        }
    }

    return @{
        Success  = $true
        Executed = $true
        Result   = $valueToStore
        Error    = $null
        Action   = "SelectObject"
    }
}

# 执行函数调用
function Invoke-FunctionCall {
    param(
        [string]$FuncName,
        $CallerNode,
        [hashtable]$Context
    )

    # 1. 检查调用深度
    if ($Context.CallStack.Count -ge $Context.MaxCallDepth) {
        Write-ExecutionLog -Context $Context -Message "  [ERROR] Max call depth ($($Context.MaxCallDepth)) exceeded"
        return @{
            Success  = $false
            Executed = $true
            Error    = "Max call depth exceeded"
            Action   = "CallFunction"
            Target   = $FuncName
        }
    }

    # 2. 获取函数入口节点
    $funcStartId = $Context.FunctionSubgraphs[$FuncName]
    if (-not $funcStartId) {
        Write-ExecutionLog -Context $Context -Message "  [ERROR] Function not found: $FuncName"
        return @{
            Success  = $false
            Executed = $true
            Error    = "Function not found: $FuncName"
            Action   = "CallFunction"
            Target   = $FuncName
        }
    }

    # 3. 获取函数子图的结束节点
    $funcEndNode = Get-SubgraphEndNode -CFG $Context.CFG -StartType "FuncStart" -Name $FuncName
    if (-not $funcEndNode) {
        Write-ExecutionLog -Context $Context -Message "  [WARN] Function end node not found for: $FuncName"
    }
    $funcEndId = if ($funcEndNode) { $funcEndNode.Id } else { $null }

    # 4. 收集局部变量
    $localVars = @()
    if ($funcEndId) {
        $localVars = Get-SubgraphLocalVars -CFG $Context.CFG -StartNodeId $funcStartId -EndNodeId $funcEndId
    }

    # 5. 计算返回节点（调用者的下一个节点）
    $nextNodes = Get-NextNodes -CFG $Context.CFG -Node $CallerNode -Context $Context
    $returnNodeId = if ($nextNodes.Count -gt 0) { $nextNodes[0].Id } else { $null }

    # 6. 提取调用者的实参并求值（执行期从 Node.Text 解析）
    $arguments = @()
    $callerInfo = Get-NodeTextExecutionInfo -Node $CallerNode -Context $Context
    if (-not $callerInfo.Success) {
        return @{
            Success  = $false
            Executed = $true
            Error    = "Parse caller Node.Text failed: $($callerInfo.Error)"
            Action   = "CallFunction"
            Target   = $FuncName
        }
    }
    $funcStartNode = Get-NodeById -CFG $Context.CFG -Id $funcStartId
    if (-not $funcStartNode) {
        Write-ExecutionLog -Context $Context -Message "  [ERROR] Function start node not found: $FuncName ($funcStartId)"
        return @{
            Success  = $false
            Executed = $true
            Error    = "Function start node not found: $FuncName ($funcStartId)"
            Action   = "CallFunction"
            Target   = $FuncName
        }
    }
    $hasProcessBlock = ($funcStartNode.PSObject.Properties['HasProcessBlock'] -and [bool]$funcStartNode.HasProcessBlock)
    $processInputVarName = if ($funcStartNode.PSObject.Properties['ProcessInputVar']) {
        [string]$funcStartNode.ProcessInputVar
    } else {
        "__proc_input"
    }

    $cmdAst = $callerInfo.CommandAst
    if ($cmdAst -and $cmdAst.CommandElements -and $cmdAst.CommandElements.Count -gt 1) {
        for ($i = 1; $i -lt $cmdAst.CommandElements.Count; $i++) {
            $argAst = $cmdAst.CommandElements[$i]
            $argCode = $argAst.Extent.Text

            if ($argAst -and $Context.FunctionSubgraphs.Count -gt 0) {
                $argCode = Resolve-EmbeddedFunctionCalls -Code $argCode -Ast $argAst -Context $Context -NodeId $CallerNode.Id
            }

            $argCode = Convert-CodeForCurrentScope -Code $argCode -Context $Context

            $argResult = Invoke-InContext -ExecContext $Context.ExecContext -Code $argCode
            if ($argResult.Success) {
                $argValue = if ($argResult.Result -is [System.Collections.ObjectModel.Collection[System.Management.Automation.PSObject]] -and $argResult.Result.Count -eq 1) {
                    $argResult.Result[0]
                } else {
                    $argResult.Result
                }
                $arguments += $argValue
                Write-ExecutionLog -Context $Context -Message "  [ARGS] Arg[$i]: $($argAst.Extent.Text) = $(Format-VariableValue $argValue)"
            } else {
                $arguments += $null
                Write-ExecutionLog -Context $Context -Message "  [ARGS] Arg[$i]: $($argAst.Extent.Text) = (eval failed)"
            }
        }
    }

    # 7. 获取调用者的目标变量（如果是赋值语句）
    $targetVarName = if ($callerInfo -and $callerInfo.Success) { $callerInfo.TargetVarName } else { $null }

    # 8. Push 作用域（包含参数和目标变量信息）
    Push-ExecutionScope -Context $Context -ScopeType "Function" -ScopeName $FuncName -ReturnNodeId $returnNodeId -EndNodeId $funcEndId
    if ($Context.ScopeStack.Count -gt 0) {
        $Context.ScopeStack[-1].LocalVars = $localVars
        $Context.ScopeStack[-1].Arguments = $arguments
        $Context.ScopeStack[-1].TargetVarName = $targetVarName

        if ($hasProcessBlock) {
            $pipelineInput = Get-CallerPipelineInput -CallerNode $CallerNode -Context $Context
            Initialize-ProcessInputForCurrentScope -Context $Context -InputItems $pipelineInput.Items -SourcePipeVar $pipelineInput.PipeVar -InputVarName $processInputVarName
        }
    }

    # 9. 跳转执行函数子图

    # 记录函数调用
    Write-ExecutionLog -Context $Context -Message "  [FUNC] Entering function '$FuncName' at Node $funcStartId"

    return @{
        Success       = $true
        Executed      = $false    # 节点本身未执行，而是跳转
        Action        = "CallFunction"
        Target        = $FuncName
        JumpToNode    = $funcStartNode
        LocalVars     = $localVars
        Arguments     = $arguments
    }
}

# 内联执行用户定义函数（同步执行，不跳转，直接返回结果）
function Invoke-FunctionInline {
    param(
        [string]$FuncName,
        [array]$Arguments,      # 已求值的参数
        [hashtable]$Context
    )

    # 1. 检查调用深度
    if ($Context.CallStack.Count -ge $Context.MaxCallDepth) {
        Write-ExecutionLog -Context $Context -Message "  [INLINE] Max call depth exceeded for '$FuncName'"
        return $null
    }

    # 2. 获取函数入口/结束节点
    $funcStartId = $Context.FunctionSubgraphs[$FuncName]
    if (-not $funcStartId) {
        Write-ExecutionLog -Context $Context -Message "  [INLINE] Function not found: $FuncName"
        return $null
    }
    $funcStartNode = Get-NodeById -CFG $Context.CFG -Id $funcStartId
    if (-not $funcStartNode) {
        Write-ExecutionLog -Context $Context -Message "  [INLINE] Function start node not found: $FuncName ($funcStartId)"
        return $null
    }
    $hasProcessBlock = ($funcStartNode.PSObject.Properties['HasProcessBlock'] -and [bool]$funcStartNode.HasProcessBlock)
    $processInputVarName = if ($funcStartNode.PSObject.Properties['ProcessInputVar']) {
        [string]$funcStartNode.ProcessInputVar
    } else {
        "__proc_input"
    }

    $funcEndNode = Get-SubgraphEndNode -CFG $Context.CFG -StartType "FuncStart" -Name $FuncName
    $funcEndId = if ($funcEndNode) { $funcEndNode.Id } else { $null }

    # 3. 收集局部变量
    $localVars = @()
    if ($funcEndId) {
        $localVars = Get-SubgraphLocalVars -CFG $Context.CFG -StartNodeId $funcStartId -EndNodeId $funcEndId
    }

    # 4. Push 作用域（ReturnNodeId=0 表示内联调用，不跳转）
    Push-ExecutionScope -Context $Context -ScopeType "Function" -ScopeName $FuncName `
        -ReturnNodeId 0 -EndNodeId $funcEndId
    $scope = $Context.ScopeStack[-1]
    $scope.LocalVars = $localVars
    $scope.Arguments = $Arguments
    $scope.TargetVarName = $null    # 内联调用无目标变量
    if ($hasProcessBlock) {
        # 内联调用没有独立调用节点，默认注入空输入
        Initialize-ProcessInputForCurrentScope -Context $Context -InputItems @() -SourcePipeVar $null -InputVarName $processInputVarName
    }

    # 5. 遍历函数子图
    Write-ExecutionLog -Context $Context -Message "  [INLINE] Entering function '$FuncName'"
    Invoke-NodeTraverse -Node $funcStartNode -Context $Context

    # 6. 获取返回值（FuncEnd 处理中会保留 LastSubgraphResult）
    $result = $Context.LastSubgraphResult
    $Context.LastSubgraphResult = $null
    Write-ExecutionLog -Context $Context -Message "  [INLINE] Exited function '$FuncName' with result: $(Format-VariableValue $result)"
    return $result
}

# 检测代码中嵌入的用户函数调用并替换为执行结果
function Resolve-EmbeddedFunctionCalls {
    param(
        [string]$Code,          # 待处理的代码字符串
        $Ast,                   # 对应的 AST（用于精确定位）
        [hashtable]$Context,
        [int]$NodeId = -1       # 调用节点 ID（用于记录 VariableReadResults）
    )

    if (-not $Ast) { return $Code }
    if ($Context.FunctionSubgraphs.Count -eq 0) { return $Code }

    # 1. 在 AST 中查找所有 CommandAst（递归搜索）
    $funcCalls = @()
    $allCommands = $Ast.FindAll({
        param($ast)
        $ast -is [System.Management.Automation.Language.CommandAst]
    }, $true)

    foreach ($cmd in $allCommands) {
        $cmdName = $cmd.GetCommandName()
        if ($cmdName -and $Context.FunctionSubgraphs.ContainsKey($cmdName)) {
            $funcCalls += @{
                Ast      = $cmd
                FuncName = $cmdName
                Start    = $cmd.Extent.StartOffset
                End      = $cmd.Extent.EndOffset
                Text     = $cmd.Extent.Text
            }
        }
    }

    if ($funcCalls.Count -eq 0) { return $Code }

    # 2. 按位置从后往前排序（避免替换时偏移错乱）
    $funcCalls = $funcCalls | Sort-Object -Property Start -Descending

    # 3. 计算 AST 的 StartOffset 作为基准（代码字符串的起始位置）
    $baseOffset = $Ast.Extent.StartOffset

    # 4. 对每个函数调用：求值参数 → 内联执行 → 替换文本
    $result = $Code
    foreach ($call in $funcCalls) {
        # 提取并求值参数
        $args = @()
        if ($call.Ast.CommandElements.Count -gt 1) {
            for ($i = 1; $i -lt $call.Ast.CommandElements.Count; $i++) {
                $argAst = $call.Ast.CommandElements[$i]
                $argCode = $argAst.Extent.Text

                # 应用当前作用域的变量前缀
                if ($Context.ScopeStack.Count -gt 0) {
                    $scope = $Context.ScopeStack[-1]
                    if ($scope.LocalVars -and $scope.LocalVars.Count -gt 0) {
                        $argCode = Convert-VariableNames -Code $argCode `
                            -ScopePrefix $scope.ScopePrefix -LocalVarNames $scope.LocalVars
                    }
                }

                $evalResult = Invoke-InContext -ExecContext $Context.ExecContext -Code $argCode
                if ($evalResult.Success) {
                    $argValue = if ($evalResult.Result -is [System.Collections.ObjectModel.Collection[System.Management.Automation.PSObject]] -and $evalResult.Result.Count -eq 1) {
                        $evalResult.Result[0]
                    } else { $evalResult.Result }
                    $args += $argValue
                } else {
                    $args += $null
                }
            }
        }

        Write-ExecutionLog -Context $Context -Message "  [INLINE] Resolving: $($call.Text) with args: $(($args | ForEach-Object { Format-VariableValue $_ }) -join ', ')"

        # 内联执行函数
        $funcResult = Invoke-FunctionInline -FuncName $call.FuncName -Arguments $args -Context $Context

        # 生成唯一的中间变量名
        $tempVar = "_inline_" + [guid]::NewGuid().ToString("N").Substring(0,8)

        # 将返回值存入中间变量
        $Context.ExecContext.Runspace.SessionStateProxy.SetVariable($tempVar, $funcResult)

        # 记录到 VariableReadResults（函数调用的返回值）
        if ($NodeId -ge 0 -and (Test-ResolvableValue $funcResult)) {
            $inlineKey = "$($NodeId):$($call.Start):$($call.End)"
            if (-not $Context.VariableReadResults.ContainsKey($inlineKey)) {
                $Context.VariableReadResults[$inlineKey] = @{
                    NodeId  = $NodeId
                    VarInfo = [PSCustomObject]@{
                        Name           = $tempVar
                        StartOffset    = $call.Start
                        EndOffset      = $call.End
                        Text           = $call.Text
                        IsInlineResult = $true
                    }
                    Values = @()
                }
            }
            $Context.VariableReadResults[$inlineKey].Values += (Format-ResolvableValue $funcResult)
        }

        Write-ExecutionLog -Context $Context -Message "  [INLINE] Created temp var `$$tempVar = $(Format-VariableValue $funcResult)"

        # 用变量名替换代码
        $relStart = $call.Start - $baseOffset
        $relEnd = $call.End - $baseOffset
        $result = $result.Substring(0, $relStart) + "`$$tempVar" + $result.Substring($relEnd)

        Write-ExecutionLog -Context $Context -Message "  [INLINE] Result: $($call.FuncName) => $(Format-VariableValue $funcResult)"
    }

    return $result
}

# 执行脚本块调用
function Invoke-ScriptBlockCall {
    param(
        [string]$BlockName,
        $CallerNode,
        [hashtable]$Context,
        [array]$PreParsedArguments = $null  # 预解析的参数（来自 Get-ScriptBlockCallInfo）
    )

    # 1. 检查调用深度
    if ($Context.CallStack.Count -ge $Context.MaxCallDepth) {
        Write-ExecutionLog -Context $Context -Message "  [ERROR] Max call depth ($($Context.MaxCallDepth)) exceeded"
        return @{
            Success  = $false
            Executed = $true
            Error    = "Max call depth exceeded"
            Action   = "CallScriptBlock"
            Target   = $BlockName
        }
    }

    # 2. 获取脚本块入口节点
    $blockStartId = $Context.ScriptBlockSubgraphs[$BlockName]
    if (-not $blockStartId) {
        Write-ExecutionLog -Context $Context -Message "  [ERROR] ScriptBlock not found: $BlockName"
        return @{
            Success  = $false
            Executed = $true
            Error    = "ScriptBlock not found: $BlockName"
            Action   = "CallScriptBlock"
            Target   = $BlockName
        }
    }

    # 3. 获取脚本块的结束节点
    $blockEndNode = Get-SubgraphEndNode -CFG $Context.CFG -StartType "BlockStart" -Name $BlockName
    if (-not $blockEndNode) {
        Write-ExecutionLog -Context $Context -Message "  [WARN] ScriptBlock end node not found for: $BlockName"
    }
    $blockEndId = if ($blockEndNode) { $blockEndNode.Id } else { $null }

    # 4. 收集局部变量
    $localVars = @()
    if ($blockEndId) {
        $localVars = Get-SubgraphLocalVars -CFG $Context.CFG -StartNodeId $blockStartId -EndNodeId $blockEndId
    }

    # 5. 计算返回节点
    $nextNodes = Get-NextNodes -CFG $Context.CFG -Node $CallerNode -Context $Context
    $returnNodeId = if ($nextNodes.Count -gt 0) { $nextNodes[0].Id } else { $null }

    # 6. 提取调用者的实参并求值
    $arguments = @()
    $callerInfo = Get-NodeTextExecutionInfo -Node $CallerNode -Context $Context
    if (-not $callerInfo.Success) {
        return @{
            Success  = $false
            Executed = $true
            Error    = "Parse caller Node.Text failed: $($callerInfo.Error)"
            Action   = "CallScriptBlock"
            Target   = $BlockName
        }
    }
    $blockStartNode = Get-NodeById -CFG $Context.CFG -Id $blockStartId
    if (-not $blockStartNode) {
        Write-ExecutionLog -Context $Context -Message "  [ERROR] ScriptBlock start node not found: $BlockName ($blockStartId)"
        return @{
            Success  = $false
            Executed = $true
            Error    = "ScriptBlock start node not found: $BlockName ($blockStartId)"
            Action   = "CallScriptBlock"
            Target   = $BlockName
        }
    }
    $hasProcessBlock = ($blockStartNode.PSObject.Properties['HasProcessBlock'] -and [bool]$blockStartNode.HasProcessBlock)
    $processInputVarName = if ($blockStartNode.PSObject.Properties['ProcessInputVar']) {
        [string]$blockStartNode.ProcessInputVar
    } else {
        "__proc_input"
    }

    # 优先使用预解析的参数（来自 Get-ScriptBlockCallInfo，用于 Invoke-Command 等形式）
    if ($null -ne $PreParsedArguments) {
        $arguments = $PreParsedArguments
        for ($i = 0; $i -lt $arguments.Count; $i++) {
            Write-ExecutionLog -Context $Context -Message "  [ARGS] Arg[$i]: (pre-parsed) = $(Format-VariableValue $arguments[$i])"
        }
    }
    # 否则从 Node.Text 解析参数
    else {
        $argInfo = Get-NodeTextScriptBlockArguments -CallerNode $CallerNode -BlockName $BlockName -Context $Context
        if (-not $argInfo.Success) {
            return @{
                Success  = $false
                Executed = $true
                Error    = "Parse arguments from Node.Text failed: $($argInfo.Error)"
                Action   = "CallScriptBlock"
                Target   = $BlockName
            }
        } else {
            $arguments = @($argInfo.Arguments)
            for ($i = 0; $i -lt $arguments.Count; $i++) {
                Write-ExecutionLog -Context $Context -Message "  [ARGS] Arg[$i]: (text-parsed) = $(Format-VariableValue $arguments[$i])"
            }
        }
    }

    # 7. 获取调用者的目标变量（如果是赋值语句）
    $targetVarName = if ($callerInfo -and $callerInfo.Success) { $callerInfo.TargetVarName } else { $null }

    # 8. Push 作用域
    Push-ExecutionScope -Context $Context -ScopeType "ScriptBlock" -ScopeName $BlockName -ReturnNodeId $returnNodeId -EndNodeId $blockEndId
    if ($Context.ScopeStack.Count -gt 0) {
        $Context.ScopeStack[-1].LocalVars = $localVars
        $Context.ScopeStack[-1].Arguments = $arguments
        $Context.ScopeStack[-1].TargetVarName = $targetVarName

        if ($hasProcessBlock) {
            $pipelineInput = Get-CallerPipelineInput -CallerNode $CallerNode -Context $Context
            Initialize-ProcessInputForCurrentScope -Context $Context -InputItems $pipelineInput.Items -SourcePipeVar $pipelineInput.PipeVar -InputVarName $processInputVarName
        }
    }

    # 9. 跳转执行脚本块子图
    Write-ExecutionLog -Context $Context -Message "  [BLOCK] Entering ScriptBlock '$BlockName' at Node $blockStartId"

    return @{
        Success       = $true
        Executed      = $false
        Action        = "CallScriptBlock"
        Target        = $BlockName
        JumpToNode    = $blockStartNode
        LocalVars     = $localVars
    }
}

# 处理动态执行（iex / ScriptBlockCreate / NewScriptBlock）- 创建 CFG 子图
function Handle-DynamicInvoke {
    param(
        $Node,
        [hashtable]$Context,
        $CommandInfo = $null,         # IEX / ScriptBlockCreate 命令名类型时由 Test-CommandSafety 传入
        $DynamicInfo = $null,         # ScriptBlockCreate / NewScriptBlock AST 类型时由 Invoke-NodeSafe 传入
        $DynamicTypeFromCommand = $null  # 从 Test-CommandSafety 传入的动态类型标记
    )

    # 1. 根据类型提取参数值
    $argumentValue = $null
    $argCode = $null
    $dynType = $null
    $isScriptBlockCreateFromCommand = $false  # 标记是否为命令名形式的 ScriptBlockCreate

    # 判断类型：DynamicInfo 类型 > 命令名类型 > IEX
    if ($DynamicInfo -and $DynamicInfo.Type -in @("ScriptBlockCreate", "NewScriptBlock")) {
        $dynType = $DynamicInfo.Type
    } elseif ($DynamicTypeFromCommand -eq "ScriptBlockCreate") {
        $dynType = "ScriptBlockCreate"
        $isScriptBlockCreateFromCommand = $true
    } else {
        $dynType = "IEX"
    }

    $argCodeInfo = Get-DynamicArgumentCodeFromNodeText -Node $Node -Context $Context -DynamicType $dynType
    if (-not $argCodeInfo.Success) {
        return @{
            Success       = $false
            Executed      = $true
            Result        = $null
            Error         = "Parse Node.Text failed: $($argCodeInfo.Error)"
            Action        = "DynamicInvoke"
            DynamicRecord = $null
        }
    }
    $argCode = $argCodeInfo.Code

    if ($argCode) {
        $evalCode = Convert-CodeForCurrentScope -Code $argCode -Context $Context
        $evalResult = Invoke-InContext -ExecContext $Context.ExecContext -Code $evalCode
        if ($evalResult.Success -and $null -ne $evalResult.Result) {
            if ($evalResult.Result -is [System.Collections.ObjectModel.Collection[System.Management.Automation.PSObject]]) {
                if ($evalResult.Result.Count -gt 0) { $argumentValue = $evalResult.Result[0] }
            } elseif ($evalResult.Result -is [array] -and $evalResult.Result.Count -eq 1) {
                $argumentValue = $evalResult.Result[0]
            } else {
                $argumentValue = $evalResult.Result
            }
        }
    }

    # 记录动态执行信息
    $dynamicRecord = @{
        NodeId        = $Node.Id
        Command       = $dynType
        ArgumentCode  = $argCode
        ArgumentValue = $argumentValue
        Timestamp     = Get-Date
    }
    $Context.DynamicInvokeResults += $dynamicRecord

    Write-ExecutionLog -Context $Context -Message "  [DYNAMIC] Type: $dynType"

    # 2. 验证参数值是字符串
    if (-not ($argumentValue -is [string]) -or [string]::IsNullOrWhiteSpace($argumentValue)) {
        Write-ExecutionLog -Context $Context -Message "  [DYNAMIC] Cannot resolve argument to string, falling back to direct execution"
        $result = Invoke-NodeDirect -Node $Node -Context $Context
        if ($result.Success) {
            Evaluate-NodeResolvables -Node $Node -Context $Context
        }
        $result.Action = "DynamicInvoke"
        $result.DynamicRecord = $dynamicRecord
        return $result
    }

    $codePreview = if ($argumentValue.Length -gt 100) { $argumentValue.Substring(0, 100) + "..." } else { $argumentValue }
    Write-ExecutionLog -Context $Context -Message "  [DYNAMIC] Code to execute: $codePreview"

    # 3. 根据类型选择不同的处理方式
    if (($DynamicInfo -and $DynamicInfo.Type -in @("ScriptBlockCreate", "NewScriptBlock")) -or $isScriptBlockCreateFromCommand) {
        # ScriptBlockCreate / NewScriptBlock：
        # 1. 创建前置节点：$_dyn_xxx = {xxx}（显示转换过程）
        # 2. 原节点中的 [ScriptBlock]::Create(xxx) 替换为 $_dyn_xxx

        # 创建运行时子图
        $subgraphResult = New-RuntimeSubgraph -cfg $Context.CFG -Code $argumentValue

        if (-not $subgraphResult.Success) {
            Write-ExecutionLog -Context $Context -Message "  [DYNAMIC] Parse error: $($subgraphResult.Error), falling back to direct execution"
            $result = Invoke-NodeDirect -Node $Node -Context $Context
            if ($result.Success) {
                Evaluate-NodeResolvables -Node $Node -Context $Context
            }
            $result.Action = "DynamicInvoke"
            $result.DynamicRecord = $dynamicRecord
            return $result
        }

        $blockName = $subgraphResult.BlockName
        $blockVarRef = "`$$blockName"
        $scriptBlockLiteral = "{$argumentValue}"

        # 注册子图
        $Context.ScriptBlockSubgraphs[$blockName] = $subgraphResult.BlockStartId
        Write-ExecutionLog -Context $Context -Message "  [DYNAMIC] Created subgraph: $blockName (Nodes $($subgraphResult.BlockStartId)-$($subgraphResult.BlockEndId))"

        # 创建前置转换节点（显示 $_dyn_xxx = {xxx}）
        $translationText = "$blockVarRef = $scriptBlockLiteral"
        $translationNode = Add-Node -cfg $Context.CFG -type "DynamicTranslation" -text $translationText -line $Node.Line -ast $null
        Write-ExecutionLog -Context $Context -Message "  [DYNAMIC] Created translation node: $translationText"

        # 将转换节点插入到 CFG 中作为当前节点的前置节点
        # 1. 找到所有指向当前节点的边，改为指向转换节点
        foreach ($edge in $Context.CFG.Edges) {
            if ($edge.To -eq $Node.Id) {
                $edge.To = $translationNode.Id
            }
        }
        # 2. 添加从转换节点到当前节点的边
        Add-Edge -cfg $Context.CFG -from $translationNode.Id -to $Node.Id
        Write-ExecutionLog -Context $Context -Message "  [DYNAMIC] Inserted translation node before Node $($Node.Id)"

        # 执行前置节点：设置 $_dyn_xxx 变量为脚本块
        $sbCode = "[ScriptBlock]::Create('$($argumentValue.Replace("'", "''"))')"
        $sbResult = Invoke-InContext -ExecContext $Context.ExecContext -Code $sbCode
        if ($sbResult.Success) {
            $Context.ExecContext.Runspace.SessionStateProxy.SetVariable($blockName, $sbResult.Result)
            Write-ExecutionLog -Context $Context -Message "  [DYNAMIC] Set `$$blockName = [ScriptBlock]"
        }

        # 记录前置节点执行（用于输出显示）
        Write-ExecutionLog -Context $Context -Message "--- Node $($translationNode.Id) [DynamicTranslation] ---"
        Write-ExecutionLog -Context $Context -Message "  Code: $translationText"
        Write-ExecutionLog -Context $Context -Message "  Status: OK (Dynamic)"
        Write-ExecutionLog -Context $Context -Message "  VarsWritten:"
        Write-ExecutionLog -Context $Context -Message "    `$$blockName = [ScriptBlock]"
        $Context.TotalVisits++

        # 找到要替换的调用表达式，替换为 $_dyn_xxx
        if ($isScriptBlockCreateFromCommand) {
            # 命令名形式：& [ScriptBlock]::Create($b) -> & $_dyn_xxx
            # CommandInfo.Ast 是整个 CommandAst
            $nodeOrigText = $Node.Text
            $cmdAst = $CommandInfo.Ast  # CommandAst

            # 获取命令元素的范围（从第一个元素到最后一个元素）
            # 例如从 [ScriptBlock]::Create 到 ($b) 或 $b
            $firstElement = $cmdAst.CommandElements[0]
            $lastElement = $cmdAst.CommandElements[$cmdAst.CommandElements.Count - 1]

            # 使用从第一个元素开始到最后一个元素结束的文本
            $startOffset = $firstElement.Extent.StartOffset
            $endOffset = $lastElement.Extent.EndOffset
            $sourceText = $cmdAst.Extent.StartScriptPosition.GetFullScript()
            $replaceText = $sourceText.Substring($startOffset, $endOffset - $startOffset)

            $newText = $nodeOrigText.Replace($replaceText, $blockVarRef)
            $Node.Text = $newText
            Write-ExecutionLog -Context $Context -Message "  [DYNAMIC] Original node text replaced: $newText"
        } elseif ($DynamicInfo -and $DynamicInfo.ArgAst) {
            $invokeAst = $DynamicInfo.ArgAst.Parent  # InvokeMemberExpressionAst
            if ($invokeAst) {
                $replaceText = $invokeAst.Extent.Text
                $nodeOrigText = $Node.Text

                # 向上遍历找到最外层包装（ParenExpression），但不包括 CommandAst
                $current = $invokeAst.Parent
                while ($current -and $current -ne $Node.Ast) {
                    if ($current -is [System.Management.Automation.Language.ParenExpressionAst]) {
                        $replaceText = $current.Extent.Text
                    }
                    if ($current -is [System.Management.Automation.Language.CommandAst]) {
                        break
                    }
                    $current = $current.Parent
                }

                $newText = $nodeOrigText.Replace($replaceText, $blockVarRef)
                $Node.Text = $newText
                Write-ExecutionLog -Context $Context -Message "  [DYNAMIC] Original node text replaced: $newText"
            }
        }

        # 清除 DynamicInvoke 标记
        $Node.DynamicInvoke = $null

        # 检查修改后的节点是否为调用形式（& $_dyn_xxx 或 . $_dyn_xxx）
        # 如果是，需要跳转到子图执行，而不是直接执行
        $isCallForm = $Node.Text -match '^[&\.]?\s*\$' -and -not $Node.VarsWritten

        if ($isCallForm) {
            # 设置调用节点的 Invokes 信息，让后续调用检测能找到
            if (-not $Node.Invokes) {
                $Node.Invokes = @{ ScriptBlocks = @() }
            }
            $Node.Invokes.ScriptBlocks = @($blockName)

            Write-ExecutionLog -Context $Context -Message "  [CALL] ScriptBlock: $blockName (via DynamicTranslation)"
            return Invoke-ScriptBlockCall -BlockName $blockName -CallerNode $Node -Context $Context
        }

        # 赋值形式（$delegate = $_dyn_xxx）：执行修改后的代码
        $execCode = $Node.Text
        if ($Context.ScopeStack.Count -gt 0) {
            $currentScope = $Context.ScopeStack[-1]
            if ($currentScope.LocalVars -and $currentScope.LocalVars.Count -gt 0) {
                $execCode = Convert-VariableNames -Code $execCode -ScopePrefix $currentScope.ScopePrefix -LocalVarNames $currentScope.LocalVars
            }
        }

        $execResult = Invoke-InContext -ExecContext $Context.ExecContext -Code $execCode

        # 记录变量到块名的映射（用于后续调用时查找正确的子图）
        if ($Node.VarsWritten -and $Node.VarsWritten.Count -gt 0) {
            foreach ($varInfo in $Node.VarsWritten) {
                # 将赋值目标变量映射到块名
                $Context.VarToBlockMapping[$varInfo.Name] = $blockName
                Write-ExecutionLog -Context $Context -Message "  [MAPPING] `$$($varInfo.Name) -> $blockName"
            }
        }

        # 记录变量写入
        if ($Node.VarsWritten -and $Node.VarsWritten.Count -gt 0) {
            Write-ExecutionLog -Context $Context -Message "  VarsWritten:"
            foreach ($varInfo in $Node.VarsWritten) {
                $varValue = Get-VariableFromContext -ExecContext $Context.ExecContext -Name $varInfo.Name
                Write-ExecutionLog -Context $Context -Message "    `$$($varInfo.Name) = $(Format-VariableValue $varValue)"
            }
        }

        Evaluate-NodeResolvables -Node $Node -Context $Context

        $result = @{
            Success     = $execResult.Success
            Executed    = $true
            Result      = $execResult.Result
            Error       = $execResult.Error
            Action      = "DynamicInvoke"
            DynamicRecord = $dynamicRecord
        }
        return $result
    } else {
        # IEX：创建子图并跳转执行（保持原有逻辑）
        $subgraphResult = New-RuntimeSubgraph -cfg $Context.CFG -Code $argumentValue

        if (-not $subgraphResult.Success) {
            Write-ExecutionLog -Context $Context -Message "  [DYNAMIC] Parse error: $($subgraphResult.Error), falling back to direct execution"
            $result = Invoke-NodeDirect -Node $Node -Context $Context
            if ($result.Success) {
                Evaluate-NodeResolvables -Node $Node -Context $Context
            }
            $result.Action = "DynamicInvoke"
            $result.DynamicRecord = $dynamicRecord
            return $result
        }

        $blockName = $subgraphResult.BlockName
        $Context.ScriptBlockSubgraphs[$blockName] = $subgraphResult.BlockStartId

        Write-ExecutionLog -Context $Context -Message "  [DYNAMIC] Created subgraph: $blockName (Nodes $($subgraphResult.BlockStartId)-$($subgraphResult.BlockEndId))"

        # IEX：用 & $_dyn_xxx 替换整个 iex 调用
        $blockVarRef = "`$$blockName"
        $Node.Text = "& $blockVarRef"
        Write-ExecutionLog -Context $Context -Message "  [DYNAMIC] Node text replaced: & $blockVarRef"

        # 设置调用节点的 Invokes 信息
        $Node.Invokes.ScriptBlocks = @($blockName)
        $Node.DynamicInvoke = $null

        # 跳转执行子图
        return Invoke-ScriptBlockCall -BlockName $blockName -CallerNode $Node -Context $Context
    }
}

# 节点遍历（迭代式）
function Invoke-NodeTraverse {
    param(
        $Node,
        [hashtable]$Context
    )

    $currentNode = $Node

    while ($null -ne $currentNode) {
        # 终止条件
        if ($currentNode.Type -eq "End") {
            Write-ExecutionLog -Context $Context -Message "=== 执行结束 ==="
            break
        }

        # 处理 FuncEnd / BlockEnd - 收集返回值，返回到调用者
        if ($currentNode.Type -eq "FuncEnd" -or $currentNode.Type -eq "BlockEnd") {
            Write-ExecutionLog -Context $Context -Message "--- Node $($currentNode.Id) [$($currentNode.Type)] ---"
            Write-ExecutionLog -Context $Context -Message "  Code: $($currentNode.Text)"

            # 获取函数的最后执行结果作为返回值
            $returnValue = $Context.LastSubgraphResult

            $scope = Pop-ExecutionScope -Context $Context
            if ($scope) {
                # 根据调用方式处理返回值
                if ($scope.ReturnNodeId) {
                    # 正常调用（通过 Invoke-FunctionCall 跳转）：清空 LastSubgraphResult
                    $Context.LastSubgraphResult = $null

                    # 将返回值赋给调用者的目标变量
                    if ($scope.TargetVarName -and $null -ne $returnValue) {
                        # 检查返回后是否还在某个作用域中（调用发生在另一个函数内部）
                        $actualVarName = $scope.TargetVarName
                        if ($Context.ScopeStack.Count -gt 0) {
                            $outerScope = $Context.ScopeStack[-1]
                            # 如果目标变量是外层作用域的局部变量，使用带前缀的名称
                            if ($outerScope.LocalVars -and $scope.TargetVarName -in $outerScope.LocalVars) {
                                $actualVarName = $outerScope.ScopePrefix + $scope.TargetVarName
                            }
                        }
                        $Context.ExecContext.Runspace.SessionStateProxy.SetVariable($actualVarName, $returnValue)
                        Write-ExecutionLog -Context $Context -Message "  [RETURN] Set `$$actualVarName = $(Format-VariableValue $returnValue)"
                    }

                    Write-ExecutionLog -Context $Context -Message "  [RETURN] Returning from $($scope.ScopeType) '$($scope.ScopeName)' to Node $($scope.ReturnNodeId)"
                    $returnNode = Get-NodeById -CFG $Context.CFG -Id $scope.ReturnNodeId
                    $currentNode = $returnNode
                } else {
                    # 内联调用（ReturnNodeId=0）：保留 LastSubgraphResult 供调用者获取
                    $Context.LastSubgraphResult = $returnValue
                    Write-ExecutionLog -Context $Context -Message "  [RETURN] Inline call completed, preserving result: $(Format-VariableValue $returnValue)"
                    $currentNode = $null
                }
            } else {
                $currentNode = $null
            }
            continue  # 不继续遍历 FuncEnd/BlockEnd 的后继
        }

        # 处理 Return 节点 - 求值返回表达式，跳转到 FuncEnd
        if ($currentNode.Type -eq "Return") {
            Write-ExecutionLog -Context $Context -Message "--- Node $($currentNode.Id) [Return] ---"
            Write-ExecutionLog -Context $Context -Message "  Code: $($currentNode.Text)"

            $Context.VisitedNodes[$currentNode.Id] = ($Context.VisitedNodes[$currentNode.Id] ?? 0) + 1
            $Context.TotalVisits++

            # 如果在函数/脚本块作用域中
            if ($Context.ScopeStack.Count -gt 0) {
                $currentScope = $Context.ScopeStack[-1]

                # 求值 return 表达式（执行期从 Node.Text 解析）
                $returnValue = $null
                $retInfo = Get-NodeTextReturnExpression -Node $currentNode -Context $Context
                if (-not $retInfo.Success) {
                    Write-ExecutionLog -Context $Context -Message "  [RETURN] Parse Node.Text failed: $($retInfo.Error)"
                } elseif ($retInfo.Code) {
                    $returnCode = Convert-CodeForCurrentScope -Code $retInfo.Code -Context $Context
                    $evalResult = Invoke-InContext -ExecContext $Context.ExecContext -Code $returnCode
                    if ($evalResult.Success -and $null -ne $evalResult.Result) {
                        # Return 语句的表达式同样会写入输出流（对 ForEach-Object 等捕获场景很重要）
                        if ($Context.OutputCaptureStack -and $Context.OutputCaptureStack.Count -gt 0) {
                            Add-OutputsToCurrentCapture -Context $Context -Result $evalResult.Result
                        }

                        # 解包 PSObject Collection
                        if ($evalResult.Result -is [System.Collections.ObjectModel.Collection[System.Management.Automation.PSObject]]) {
                            if ($evalResult.Result.Count -eq 1) {
                                $returnValue = $evalResult.Result[0]
                            } elseif ($evalResult.Result.Count -gt 1) {
                                $returnValue = $evalResult.Result
                            }
                        } else {
                            $returnValue = $evalResult.Result
                        }
                        Write-ExecutionLog -Context $Context -Message "  [RETURN] Expression value: $(Format-VariableValue $returnValue)"
                    }
                }

                # 设置返回值
                $Context.LastSubgraphResult = $returnValue

                # 跳转到 FuncEnd/BlockEnd 节点
                if ($currentScope.EndNodeId) {
                    Write-ExecutionLog -Context $Context -Message "  [RETURN] Jumping to EndNode $($currentScope.EndNodeId)"
                    $endNode = Get-NodeById -CFG $Context.CFG -Id $currentScope.EndNodeId
                    $currentNode = $endNode
                } else {
                    $currentNode = $null
                }
            } else {
                # 不在函数/脚本块中的 return，跟随正常边
                $nextNodes = Get-NextNodes -CFG $Context.CFG -Node $currentNode -Context $Context
                $currentNode = if ($nextNodes.Count -gt 0) { $nextNodes[0] } else { $null }
            }
            continue  # Return 处理完毕，不继续遍历
        }

        if ($Context.TotalVisits -ge $Context.MaxTotalNodes) {
            Write-ExecutionLog -Context $Context -Message "!!! 达到最大节点访问次数 ($($Context.MaxTotalNodes)) !!!"
            break
        }

        # 循环检测
        $nodeKey = $currentNode.Id
        if (-not $Context.VisitedNodes.ContainsKey($nodeKey)) {
            $Context.VisitedNodes[$nodeKey] = 0
        }
        if ($Context.VisitedNodes[$nodeKey] -ge $Context.MaxIterations) {
            Write-ExecutionLog -Context $Context -Message "!!! 节点 $nodeKey 达到最大迭代次数 ($($Context.MaxIterations)) !!!"
            break
        }

        $Context.VisitedNodes[$nodeKey]++
        $Context.TotalVisits++

        # 先输出节点头（在执行之前）
        Write-ExecutionLog -Context $Context -Message "--- Node $($currentNode.Id) [$($currentNode.Type)] ---"
        Write-ExecutionLog -Context $Context -Message "  Code: $($currentNode.Text)"

        # 特殊处理 FuncParams / BlockParams 节点：绑定实参到形参
        if ($currentNode.Type -in @('FuncParams', 'BlockParams') -and $Context.ScopeStack.Count -gt 0) {
            $currentScope = $Context.ScopeStack[-1]
            if ($currentScope.Arguments -and $currentScope.Arguments.Count -gt 0) {
                # 从 Node.Ast (ParamBlockAst) 获取形参名
                if ($currentNode.Ast -and $currentNode.Ast.Parameters) {
                    $paramNames = @()
                    foreach ($param in $currentNode.Ast.Parameters) {
                        $paramNames += $param.Name.VariablePath.UserPath
                    }

                    # 绑定实参到带前缀的形参
                    for ($i = 0; $i -lt [Math]::Min($paramNames.Count, $currentScope.Arguments.Count); $i++) {
                        $paramName = $paramNames[$i]
                        $argValue = $currentScope.Arguments[$i]
                        $prefixedName = $currentScope.ScopePrefix + $paramName
                        $Context.ExecContext.Runspace.SessionStateProxy.SetVariable($prefixedName, $argValue)
                        Write-ExecutionLog -Context $Context -Message "  [BIND] `$$prefixedName = $(Format-VariableValue $argValue)"

                        # 把参数也加入 LocalVars 以便变量转换
                        if ($paramName -notin $currentScope.LocalVars) {
                            $currentScope.LocalVars += $paramName
                        }
                    }
                }
            }
        }

        # 记录执行前的变量值（读取的变量）
        $varsBefore = @{}
        foreach ($varInfo in $currentNode.VarsRead) {
            # 获取实际变量名（考虑作用域前缀）
            $actualVarName = $varInfo.Name
            if ($Context.ScopeStack.Count -gt 0) {
                $currentScope = $Context.ScopeStack[-1]
                if ($currentScope.LocalVars -and $varInfo.Name -in $currentScope.LocalVars) {
                    $actualVarName = $currentScope.ScopePrefix + $varInfo.Name
                }
            }

            $value = Get-VariableFromContext -ExecContext $Context.ExecContext -Name $actualVarName
            $varsBefore[$varInfo.Name] = $value

            # 记录到 VariableReadResults（只记录有位置信息且是简单类型的变量）
            # 生成的辅助变量（如 $__fe_xxx）没有位置信息，跳过
            if ($null -ne $varInfo.StartOffset -and $null -ne $varInfo.EndOffset -and (Test-ResolvableValue $value)) {
                $key = "$($currentNode.Id):$($varInfo.StartOffset):$($varInfo.EndOffset)"
                if (-not $Context.VariableReadResults.ContainsKey($key)) {
                    $Context.VariableReadResults[$key] = @{
                        NodeId  = $currentNode.Id
                        VarInfo = $varInfo
                        Values  = @()
                    }
                }
                $Context.VariableReadResults[$key].Values += (Format-ResolvableValue $value)
            }
        }

        # 执行节点
        $execResult = Invoke-NodeSafe -Node $currentNode -Context $Context

        # 输出捕获：用于 ForEach-Object 脚本块逐项执行，将“可见输出”收集到捕获帧
        if ($Context.OutputCaptureStack -and $Context.OutputCaptureStack.Count -gt 0) {
            $captureThis = $true

            # 条件/控制节点的求值结果不属于脚本输出流
            $nonOutputTypes = @('Condition', 'ForEachCondition', 'ProcessCondition', 'SwitchCondition', 'CaseCondition')
            if ($currentNode.Type -in $nonOutputTypes) {
                $captureThis = $false
            }

            # PipelineElement：仅捕获末端元素的输出；写 _pipe_ 的节点为中间步骤（只用于传递）
            if ($captureThis -and $currentNode.Type -eq 'PipelineElement' -and $currentNode.VarsWritten) {
                foreach ($v in $currentNode.VarsWritten) {
                    if ($v.Name -match '^_pipe_[a-f0-9]+$') {
                        $captureThis = $false
                        break
                    }
                }
            }

            if ($captureThis) {
                Add-OutputsToCurrentCapture -Context $Context -Result $execResult.Result
            }
        }

        # 管道控制流：Break/Continue 在 ForEach-Object 脚本块中用于控制枚举
        if ($Context.OutputCaptureStack -and $Context.OutputCaptureStack.Count -gt 0 -and $currentNode.Type -in @('Break', 'Continue')) {
            $label = $currentNode.Type
            $edge = $Context.CFG.Edges | Where-Object { $_.From -eq $currentNode.Id -and $_.Label -eq $label } | Select-Object -First 1
            if ($edge) {
                $targetNode = Get-NodeById -CFG $Context.CFG -Id $edge.To
                if ($targetNode -and $targetNode.Type -in @('BlockEnd', 'FuncEnd', 'ProcessEnd', 'End', 'MainEnd')) {
                    $Context.LastPipelineFlowControl = $label
                }
            }
        }

        # 记录执行后的变量值（写入的变量）
        $varsAfter = @{}
        foreach ($varInfo in $currentNode.VarsWritten) {
            # 获取实际变量名（考虑作用域前缀）
            $actualVarName = $varInfo.Name
            if ($Context.ScopeStack.Count -gt 0) {
                $currentScope = $Context.ScopeStack[-1]
                if ($currentScope.LocalVars -and $varInfo.Name -in $currentScope.LocalVars) {
                    $actualVarName = $currentScope.ScopePrefix + $varInfo.Name
                }
            }

            $value = Get-VariableFromContext -ExecContext $Context.ExecContext -Name $actualVarName
            $varsAfter[$varInfo.Name] = $value
        }

        # 写日志
        $shortText = $currentNode.Text  # 显示完整代码
        $status = if ($execResult.Action -eq "Blocked") {
            "BLOCKED"
        } elseif (-not $execResult.Executed) {
            "SKIP"
        } elseif ($execResult.Success) {
            "OK"
        } else {
            "ERR"
        }

        # 输出执行状态（节点头已在执行前输出）
        Write-ExecutionLog -Context $Context -Message "  Status: $status"

        # 记录额外的执行动作信息
        if ($execResult.Action -and $execResult.Action -notin @("Execute", "Skip")) {
            Write-ExecutionLog -Context $Context -Message "  Action: $($execResult.Action)"
            if ($execResult.Target) {
                Write-ExecutionLog -Context $Context -Message "  Target: $($execResult.Target)"
            }
            if ($execResult.Reason) {
                Write-ExecutionLog -Context $Context -Message "  Reason: $($execResult.Reason)"
            }
        }

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

                # 如果在函数/脚本块作用域中，更新 LastSubgraphResult 用于返回值
                if ($Context.ScopeStack.Count -gt 0) {
                    # 解包 PSObject Collection
                    if ($execResult.Result -is [System.Collections.ObjectModel.Collection[System.Management.Automation.PSObject]]) {
                        if ($execResult.Result.Count -eq 1) {
                            $Context.LastSubgraphResult = $execResult.Result[0]
                        } else {
                            $Context.LastSubgraphResult = $execResult.Result
                        }
                    } else {
                        $Context.LastSubgraphResult = $execResult.Result
                    }
                }
            }

            # 记录错误
            if (-not $execResult.Success -and $execResult.Error) {
                Write-ExecutionLog -Context $Context -Message "  Error: $($execResult.Error)"
            }

            # 记录条件结果
            if ($currentNode.Type -in @('Condition', 'ForEachCondition', 'ProcessCondition', 'SwitchCondition', 'CaseCondition')) {
                Write-ExecutionLog -Context $Context -Message "  ConditionResult: $($Context.LastConditionResult)"
            }
        }

        # 处理函数/脚本块调用 - 跳转到子图
        if ($execResult.Action -in @("CallFunction", "CallScriptBlock") -and $execResult.JumpToNode) {
            Write-ExecutionLog -Context $Context -Message "  [JUMP] Jumping to Node $($execResult.JumpToNode.Id)"
            $currentNode = $execResult.JumpToNode
            continue  # 跳转后不继续遍历当前节点的后继
        }

        # 获取后继节点并继续遍历
        $nextNodes = Get-NextNodes -CFG $Context.CFG -Node $currentNode -Context $Context
        $currentNode = if ($nextNodes.Count -gt 0) { $nextNodes[0] } else { $null }
    }
}

# ========== 作用域管理函数 ==========

# PowerShell 自动变量白名单（不添加作用域前缀）
$script:AutoVariables = @(
    '_', 'args', 'input', 'this', 'PSItem', 'PSCmdlet',
    'MyInvocation', 'PSScriptRoot', 'PSCommandPath',
    'true', 'false', 'null', 'Error', 'Host', 'PID',
    'PWD', 'ShellId', 'StackTrace', 'switch', 'foreach',
    'Matches', 'LastExitCode', 'PSBoundParameters', 'PSDefaultParameterValues'
)

# 动态执行命令列表
$script:DynamicInvokeCommands = @(
    'Invoke-Expression', 'iex'
)

# Push 作用域到栈
function Push-ExecutionScope {
    param(
        [hashtable]$Context,
        [string]$ScopeType,          # "Function" | "ScriptBlock"
        [string]$ScopeName,          # 函数名或块名
        [int]$ReturnNodeId,          # 返回后继续执行的节点 Id
        [int]$EndNodeId = 0          # FuncEnd/BlockEnd 节点 Id（用于 return 跳转）
    )

    # 使用 GUID 生成唯一前缀，避免与用户代码冲突
    $guid = [guid]::NewGuid().ToString("N").Substring(0, 8)
    $prefix = "_sc_${guid}_"

    $scope = @{
        ScopeType    = $ScopeType
        ScopeName    = $ScopeName
        ScopePrefix  = $prefix
        ReturnNodeId = $ReturnNodeId
        EndNodeId    = $EndNodeId    # FuncEnd/BlockEnd 节点，用于 return 跳转
        LocalVars    = @()           # 该作用域内定义的局部变量名（不含前缀）
    }

    $Context.ScopeStack += $scope
    $Context.CurrentScopePrefix = $prefix

    # 添加到调用栈
    $Context.CallStack += @{
        Type         = $ScopeType
        Name         = $ScopeName
        ReturnNodeId = $ReturnNodeId
    }

    Write-ExecutionLog -Context $Context -Message "  [SCOPE] Push: $ScopeType '$ScopeName' (prefix=$prefix, returnTo=$ReturnNodeId, endNode=$EndNodeId)"
}

# Pop 作用域
function Pop-ExecutionScope {
    param([hashtable]$Context)

    if ($Context.ScopeStack.Count -eq 0) {
        Write-ExecutionLog -Context $Context -Message "  [SCOPE] Warning: Scope stack is empty, cannot pop"
        return $null
    }

    $scope = $Context.ScopeStack[-1]

    # 从栈中移除
    if ($Context.ScopeStack.Count -eq 1) {
        $Context.ScopeStack = @()
    } else {
        $Context.ScopeStack = @($Context.ScopeStack[0..($Context.ScopeStack.Count - 2)])
    }

    # 清理该作用域的变量
    foreach ($varName in $scope.LocalVars) {
        $fullName = $scope.ScopePrefix + $varName
        try {
            $Context.ExecContext.Runspace.SessionStateProxy.PSVariable.Remove($fullName)
        } catch {
            # 忽略清理错误
        }
    }

    # 更新当前作用域前缀
    if ($Context.ScopeStack.Count -gt 0) {
        $Context.CurrentScopePrefix = $Context.ScopeStack[-1].ScopePrefix
    } else {
        $Context.CurrentScopePrefix = ""
    }

    # 从调用栈移除
    if ($Context.CallStack.Count -gt 0) {
        if ($Context.CallStack.Count -eq 1) {
            $Context.CallStack = @()
        } else {
            $Context.CallStack = @($Context.CallStack[0..($Context.CallStack.Count - 2)])
        }
    }

    Write-ExecutionLog -Context $Context -Message "  [SCOPE] Pop: $($scope.ScopeType) '$($scope.ScopeName)' (returnTo=$($scope.ReturnNodeId))"
    return $scope
}

# 收集子图中定义的局部变量
function Get-SubgraphLocalVars {
    param(
        [hashtable]$CFG,
        [int]$StartNodeId,
        [int]$EndNodeId
    )

    $localVars = @{}
    $visited = @{}
    $queue = [System.Collections.Generic.Queue[int]]::new()
    $queue.Enqueue($StartNodeId)

    while ($queue.Count -gt 0) {
        $nodeId = $queue.Dequeue()

        if ($visited.ContainsKey($nodeId)) { continue }
        $visited[$nodeId] = $true

        $node = $CFG.Nodes | Where-Object { $_.Id -eq $nodeId } | Select-Object -First 1
        if ($null -eq $node) { continue }
        if ($nodeId -eq $EndNodeId) { continue }

        # 收集写入的变量（Local 作用域或未指定作用域）
        if ($node.VarsWritten) {
            foreach ($varInfo in $node.VarsWritten) {
                # 跳过 global/script 作用域变量
                if ($varInfo.Scope -notin @('Global', 'Script')) {
                    $localVars[$varInfo.Name] = $true
                }
            }
        }

        # 继续遍历后继节点
        $edges = $CFG.Edges | Where-Object { $_.From -eq $nodeId }
        foreach ($edge in $edges) {
            if (-not $visited.ContainsKey($edge.To)) {
                $queue.Enqueue($edge.To)
            }
        }
    }

    return @($localVars.Keys)
}

# 转换代码中的变量名（添加作用域前缀）
function Convert-VariableNames {
    param(
        [string]$Code,
        [string]$ScopePrefix,
        [array]$LocalVarNames        # 需要转换的变量名列表
    )

    if ([string]::IsNullOrEmpty($ScopePrefix) -or $LocalVarNames.Count -eq 0) {
        return $Code
    }

    $result = $Code

    foreach ($varName in $LocalVarNames) {
        # 跳过自动变量
        if ($varName -in $script:AutoVariables) { continue }

        # 跳过已有作用域前缀的变量
        if ($varName -match '^_sc_[a-f0-9]{8}_') { continue }

        # 跳过管道变量
        if ($varName -match '^_pipe_[a-f0-9]+$') { continue }

        # 替换 $varName 为 $prefix_varName
        # 使用负向前瞻避免替换已有前缀的变量和变量名的一部分
        $pattern = '\$' + [regex]::Escape($varName) + '(?![a-zA-Z0-9_])'
        # 注意：-replace 中替换字符串的 $ 有特殊含义（如 $_ 表示整个输入），需要用 $$ 转义
        $replacement = '$$' + $ScopePrefix + $varName
        $result = $result -replace $pattern, $replacement
    }

    return $result
}

# 检测可疑变量名（尝试绕过作用域隔离）
function Test-SuspiciousVariables {
    param(
        $Node,
        [hashtable]$Context
    )

    $suspicious = @()

    $allVars = @()
    if ($Node.VarsRead) { $allVars += $Node.VarsRead }
    if ($Node.VarsWritten) { $allVars += $Node.VarsWritten }

    foreach ($varInfo in $allVars) {
        if ($varInfo.Name -match '^_sc_[a-f0-9]{8}_') {
            $suspicious += $varInfo.Name
        }
    }

    if ($suspicious.Count -gt 0) {
        Write-ExecutionLog -Context $Context -Message "  [WARN] Suspicious variable names detected: $($suspicious -join ', ')"
    }
}

# ========== 命令解析与安全检查 ==========

# 从节点中提取命令信息
function Get-ResolvedCommandInfo {
    param(
        $Node,
        [hashtable]$Context,
        [hashtable]$ResolvedValues   # 已还原的表达式值
    )

    $execInfo = Get-NodeTextExecutionInfo -Node $Node -Context $Context
    if (-not $execInfo.Success) {
        return @{ HasCommand = $false }
    }

    $cmdAst = $execInfo.CommandAst
    if (-not $cmdAst) {
        return @{ HasCommand = $false }
    }

    $cmdName = $null

    # 优先尝试静态命令名
    if ($cmdAst.GetCommandName) {
        $cmdName = $cmdAst.GetCommandName()
    }

    # 动态命令名：优先使用本轮解析出的表达式值（local 偏移）
    if (-not $cmdName -and $cmdAst.CommandElements -and $cmdAst.CommandElements.Count -gt 0) {
        $firstElement = $cmdAst.CommandElements[0]
        $localKey = "local:$($Node.Id):$($firstElement.Extent.StartOffset):$($firstElement.Extent.EndOffset)"
        if ($ResolvedValues -and $ResolvedValues.ContainsKey($localKey)) {
            $cmdName = $ResolvedValues[$localKey]
        }

        # 兜底：直接在当前上下文求值首元素
        if (-not $cmdName) {
            $nameCode = Convert-CodeForCurrentScope -Code $firstElement.Extent.Text -Context $Context
            $nameEval = Invoke-InContext -ExecContext $Context.ExecContext -Code $nameCode
            if ($nameEval.Success) {
                $nameValue = $nameEval.Result
                if ($nameValue -is [System.Collections.ObjectModel.Collection[System.Management.Automation.PSObject]]) {
                    if ($nameValue.Count -gt 0) { $nameValue = $nameValue[0] } else { $nameValue = $null }
                } elseif ($nameValue -is [array] -and $nameValue.Count -eq 1) {
                    $nameValue = $nameValue[0]
                }
                if ($null -ne $nameValue) {
                    $cmdName = [string]$nameValue
                }
            }
        }
    }

    # 最后从文本提取 token（不依赖 AST 原文）
    if (-not $cmdName -and $cmdAst.Extent -and $cmdAst.Extent.Text -match '^\s*([^\s\(]+)') {
        $cmdName = $Matches[1]
    }
    if (-not $cmdName -and $Node.Text -match '^\s*([^\s\(]+)') {
        $cmdName = $Matches[1]
    }

    if (-not $cmdName) {
        return @{ HasCommand = $false }
    }

    $cmdName = [string]$cmdName

    # 尝试定位原始 Command Resolvable（用于偏移兼容记录）
    $matchedResolvable = $null
    if ($Node.Resolvables) {
        $matchedResolvable = $Node.Resolvables |
            Where-Object { $_.Type -eq "Command" -and $_.Text -eq $cmdAst.Extent.Text } |
            Select-Object -First 1
    }

    # 检查别名
    $realName = $cmdName
    if ($Context.CFG.DefinedAliases -and $Context.CFG.DefinedAliases.ContainsKey($cmdName)) {
        $realName = $Context.CFG.DefinedAliases[$cmdName]
        return @{
            HasCommand   = $true
            OriginalName = $cmdName
            ResolvedName = $realName
            IsAlias      = $true
            Ast          = $cmdAst
            Resolvable   = $matchedResolvable
        }
    }

    return @{
        HasCommand   = $true
        OriginalName = $cmdName
        ResolvedName = $cmdName
        IsAlias      = $false
        Ast          = $cmdAst
        Resolvable   = $matchedResolvable
    }
}

# 检查命令安全性并确定执行动作
function Test-CommandSafety {
    param(
        $CommandInfo,
        [hashtable]$Context
    )

    if (-not $CommandInfo.HasCommand) {
        return @{ Action = "Execute"; IsForbidden = $false }
    }

    $cmdName = $CommandInfo.ResolvedName

    # 1. 违禁命令检查
    if ($cmdName -in $Context.ForbiddenCommands) {
        return @{
            Action      = "Block"
            IsForbidden = $true
            Reason      = "Forbidden command"
            Command     = $cmdName
        }
    }

    # 2. 动态执行检查
    if ($cmdName -in $script:DynamicInvokeCommands) {
        return @{
            Action      = "DynamicInvoke"
            IsForbidden = $false
            Target      = $cmdName
        }
    }

    # 2.5. [ScriptBlock]::Create / [System.Management.Automation.ScriptBlock]::Create 作为命令名
    # PowerShell 解析 "& [ScriptBlock]::Create($b)" 时把 [ScriptBlock]::Create 当作命令名
    if ($cmdName -match '^\[(?:System\.Management\.Automation\.)?ScriptBlock\]::Create$') {
        return @{
            Action      = "DynamicInvoke"
            IsForbidden = $false
            Target      = $cmdName
            DynamicType = "ScriptBlockCreate"
        }
    }

    # 3. 用户定义函数检查
    if ($Context.FunctionSubgraphs.ContainsKey($cmdName)) {
        return @{
            Action      = "CallFunction"
            IsForbidden = $false
            Target      = $cmdName
        }
    }

    # 3.5 ForEach-Object（管道迭代器）：需要按输入逐项执行脚本块子图
    if ($cmdName -in @('ForEach-Object', 'ForEach', '%')) {
        return @{
            Action      = "ForEachObject"
            IsForbidden = $false
            Target      = $cmdName
        }
    }

    # 3.6 Where-Object（管道过滤器）：需要按输入逐项执行 FilterScript 子图
    if ($cmdName -in @('Where-Object', 'Where', '?')) {
        return @{
            Action      = "WhereObject"
            IsForbidden = $false
            Target      = $cmdName
        }
    }

    # 3.7 Select-Object（管道投影/展开）：需要按输入逐项执行计算属性脚本块子图
    if ($cmdName -in @('Select-Object', 'Select')) {
        return @{
            Action      = "SelectObject"
            IsForbidden = $false
            Target      = $cmdName
        }
    }

    # 4. ScriptBlock 调用检查 (& $sb 或 . $sb)
    if ($cmdName -match '^_block_[a-f0-9]{8}$') {
        return @{
            Action      = "CallScriptBlock"
            IsForbidden = $false
            Target      = $cmdName
        }
    }

    # 检查是否为 ScriptBlock 变量调用
    if ($Context.ScriptBlockSubgraphs.ContainsKey($cmdName)) {
        return @{
            Action      = "CallScriptBlock"
            IsForbidden = $false
            Target      = $cmdName
        }
    }

    # 5. 普通命令
    return @{ Action = "Execute"; IsForbidden = $false }
}

# 还原非 Command 类型的表达式
function Resolve-NonCommandExpressions {
    param(
        $Node,
        [hashtable]$Context
    )

    $resolvedValues = @{}

    # 跳过求值的类型（有副作用或需要特殊处理）
    $skipEvalTypes = @('Command', 'Unary')

    $resolved = Get-NodeTextResolvables -Node $Node -Context $Context
    if (-not $resolved.Success) {
        Write-ExecutionLog -Context $Context -Message "  [RESOLVE] Parse Node.Text failed at Node $($Node.Id): $($resolved.Error)"
        return $resolvedValues
    }

    foreach ($resolvable in $resolved.Items) {
        if ($resolvable.Type -in $skipEvalTypes) {
            continue
        }

        # 获取表达式代码
        $code = $resolvable.Text

        # 如果处于函数/脚本块作用域中，对局部变量应用前缀转换
        $code = Convert-CodeForCurrentScope -Code $code -Context $Context

        # 在当前 Runspace 上下文中求值
        $evalResult = Invoke-InContext -ExecContext $Context.ExecContext -Code $code

        if ($evalResult.Success) {
            # 检查结果是否为适合还原的简单类型
            if (-not (Test-ResolvableValue $evalResult.Result)) {
                continue
            }

            $value = Format-ResolvableValue $evalResult.Result

            # 本地偏移键（给当前调用链使用）
            $localKey = "local:$($Node.Id):$($resolvable.LocalStartOffset):$($resolvable.LocalEndOffset)"
            $resolvedValues[$localKey] = $value

            # 原偏移可映射时再写回结果集（用于替换）
            if ($resolvable.Mapped -and $null -ne $resolvable.StartOffset -and $null -ne $resolvable.EndOffset) {
                $key = "$($Node.Id):$($resolvable.StartOffset):$($resolvable.EndOffset)"
                if (-not $Context.ResolvableResults.ContainsKey($key)) {
                    $Context.ResolvableResults[$key] = @{
                        NodeId     = $Node.Id
                        Resolvable = $resolvable
                        Values     = @()
                    }
                }
                $Context.ResolvableResults[$key].Values += $value
                $resolvedValues[$key] = $value
            }
        }
    }

    return $resolvedValues
}

# 检测脚本块调用并返回调用信息
# 支持多种调用形式：& $block, . $block, Invoke-Command -ScriptBlock $block, $sb.Invoke()
# 返回 @{ BlockName; Arguments; CallType } 或 $null
function Get-ScriptBlockCallInfo {
    param(
        $Node,
        [hashtable]$Context
    )

    # 收集已知脚本块名称（来自 Invokes.ScriptBlocks），供各检测函数使用
    $knownBlockNames = @()
    if ($Node.Invokes -and $Node.Invokes.ScriptBlocks) {
        $knownBlockNames = @($Node.Invokes.ScriptBlocks)
    }

    # 1. 检测 $var.Invoke() 形式（InvokeMemberExpressionAst）
    $invokeAst = $null
    if ($Node.Ast -is [System.Management.Automation.Language.CommandExpressionAst]) {
        $expr = $Node.Ast.Expression
        if ($expr -is [System.Management.Automation.Language.InvokeMemberExpressionAst]) {
            $invokeAst = $expr
        }
    } elseif ($Node.Ast -is [System.Management.Automation.Language.InvokeMemberExpressionAst]) {
        $invokeAst = $Node.Ast
    }
    # 也处理赋值语句右侧的 .Invoke()，例如 $result = $sb.Invoke()
    if (-not $invokeAst -and $Node.Ast -is [System.Management.Automation.Language.AssignmentStatementAst]) {
        $pipeline = $Node.Ast.Right
        if ($pipeline -is [System.Management.Automation.Language.PipelineAst] -and $pipeline.PipelineElements.Count -gt 0) {
            $pipeElem = $pipeline.PipelineElements[0]
            if ($pipeElem -is [System.Management.Automation.Language.CommandExpressionAst] -and
                $pipeElem.Expression -is [System.Management.Automation.Language.InvokeMemberExpressionAst]) {
                $invokeAst = $pipeElem.Expression
            }
        }
    }

    if ($invokeAst -and $invokeAst.Member -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
        $invokeAst.Member.Value -eq 'Invoke') {
        return Get-InvokeMemberCallInfo -InvokeAst $invokeAst -Context $Context -KnownBlockNames $knownBlockNames
    }

    # 2. 获取 CommandAst（用于 & . Invoke-Command 形式）
    $cmdAst = $null
    if ($Node.Ast -is [System.Management.Automation.Language.AssignmentStatementAst]) {
        $pipeline = $Node.Ast.Right
        if ($pipeline -is [System.Management.Automation.Language.PipelineAst] -and $pipeline.PipelineElements.Count -gt 0) {
            $pipeElem = $pipeline.PipelineElements[0]
            if ($pipeElem -is [System.Management.Automation.Language.CommandAst]) {
                $cmdAst = $pipeElem
            }
        }
    } elseif ($Node.Ast -is [System.Management.Automation.Language.CommandAst]) {
        $cmdAst = $Node.Ast
    }

    if (-not $cmdAst) {
        return $null
    }

    # 检测 Invoke-Command -ScriptBlock 形式
    $cmdName = $cmdAst.GetCommandName()
    if ($cmdName -in @('Invoke-Command', 'icm')) {
        return Get-InvokeCommandCallInfo -CmdAst $cmdAst -Context $Context -KnownBlockNames $knownBlockNames
    }

    # 检测 & $var 或 . $var 形式
    if ($cmdAst.InvocationOperator -in @([System.Management.Automation.Language.TokenKind]::Ampersand,
                                          [System.Management.Automation.Language.TokenKind]::Dot)) {
        return Get-AmpersandDotCallInfo -CmdAst $cmdAst -Context $Context -KnownBlockNames $knownBlockNames
    }

    return $null
}

# 解析 $var.Invoke() 形式
function Get-InvokeMemberCallInfo {
    param(
        $InvokeAst,
        [hashtable]$Context,
        [array]$KnownBlockNames = @()
    )

    # 获取调用目标表达式（$var 部分）
    $targetExpr = $InvokeAst.Expression
    $blockName = Get-ScriptBlockNameFromAst -Ast $targetExpr -Context $Context -KnownBlockNames $KnownBlockNames

    if (-not $blockName) {
        return $null
    }

    return @{
        BlockName = $blockName
        Arguments = $null
        CallType  = "InvokeMethod"
    }
}

# 解析 Invoke-Command -ScriptBlock $block -ArgumentList @(...) 形式
function Get-InvokeCommandCallInfo {
    param(
        $CmdAst,
        [hashtable]$Context,
        [array]$KnownBlockNames = @()
    )

    $blockName = $null
    $arguments = $null

    # 遍历命令元素，查找 -ScriptBlock 和 -ArgumentList 参数
    $i = 1  # 跳过命令名
    while ($i -lt $CmdAst.CommandElements.Count) {
        $elem = $CmdAst.CommandElements[$i]

        if ($elem -is [System.Management.Automation.Language.CommandParameterAst]) {
            $paramName = $elem.ParameterName

            # -ScriptBlock 参数
            if ($paramName -in @('ScriptBlock', 'sb')) {
                # 参数值可能在同一元素中（-ScriptBlock:$sb）或下一个元素
                if ($elem.Argument) {
                    $blockName = Get-ScriptBlockNameFromAst -Ast $elem.Argument -Context $Context -KnownBlockNames $KnownBlockNames
                } elseif ($i + 1 -lt $CmdAst.CommandElements.Count) {
                    $i++
                    $blockName = Get-ScriptBlockNameFromAst -Ast $CmdAst.CommandElements[$i] -Context $Context -KnownBlockNames $KnownBlockNames
                }
            }
            # -ArgumentList 参数（执行期由 Node.Text 统一解析，这里不求值）
            elseif ($paramName -in @('ArgumentList', 'Args')) { }
        }
        $i++
    }

    if ($blockName) {
        return @{
            BlockName = $blockName
            Arguments = $arguments
            CallType  = "InvokeCommand"
        }
    }

    return $null
}

# 解析 & $var 或 . $var 形式
function Get-AmpersandDotCallInfo {
    param(
        $CmdAst,
        [hashtable]$Context,
        [array]$KnownBlockNames = @()
    )

    if (-not $CmdAst.CommandElements -or $CmdAst.CommandElements.Count -lt 1) {
        return $null
    }

    # 获取第一个命令元素（脚本块变量）
    $firstElement = $CmdAst.CommandElements[0]
    $blockName = Get-ScriptBlockNameFromAst -Ast $firstElement -Context $Context -KnownBlockNames $KnownBlockNames

    if (-not $blockName) {
        return $null
    }

    $callType = if ($CmdAst.InvocationOperator -eq [System.Management.Automation.Language.TokenKind]::Dot) {
        "Dot"
    } else {
        "Ampersand"
    }

    return @{
        BlockName = $blockName
        Arguments = $null
        CallType  = $callType
    }
}

# 从 AST 获取脚本块名称
function Get-ScriptBlockNameFromAst {
    param(
        $Ast,
        [hashtable]$Context,
        [array]$KnownBlockNames = @()  # 来自 Invokes.ScriptBlocks 的已知名称
    )

    # 变量表达式：$block, $_block_xxx
    if ($Ast -is [System.Management.Automation.Language.VariableExpressionAst]) {
        $varName = $Ast.VariablePath.UserPath

        # 检查是否是已知的脚本块变量
        if ($Context.ScriptBlockSubgraphs.ContainsKey($varName)) {
            return $varName
        }

        # 检查变量到块名的映射（用于动态创建的脚本块）
        if ($Context.VarToBlockMapping -and $Context.VarToBlockMapping.ContainsKey($varName)) {
            return $Context.VarToBlockMapping[$varName]
        }

        # 动态查找：获取变量值并匹配
        $actualVarName = $varName
        if ($Context.ScopeStack.Count -gt 0) {
            $currentScope = $Context.ScopeStack[-1]
            if ($currentScope.LocalVars -and $varName -in $currentScope.LocalVars) {
                $actualVarName = $currentScope.ScopePrefix + $varName
            }
        }

        $varValue = Get-VariableFromContext -ExecContext $Context.ExecContext -Name $actualVarName
        if ($varValue -is [scriptblock]) {
            # 通过内容匹配查找脚本块名称
            $sbText = $varValue.ToString().Trim()
            foreach ($blockName in $Context.ScriptBlockSubgraphs.Keys) {
                $blockStartId = $Context.ScriptBlockSubgraphs[$blockName]
                $blockStartNode = Get-NodeById -CFG $Context.CFG -Id $blockStartId
                # 使用 ScriptBlockText 属性进行匹配（不使用 Ast，避免 Resolvables 误检测）
                if ($blockStartNode.ScriptBlockText) {
                    $blockText = $blockStartNode.ScriptBlockText.Trim()
                    if ($blockText.StartsWith('{') -and $blockText.EndsWith('}')) {
                        $blockText = $blockText.Substring(1, $blockText.Length - 2).Trim()
                    }
                    if ($sbText -eq $blockText) {
                        return $blockName
                    }
                }
            }
        }
    }
    # ScriptBlockExpressionAst：直接的 { } 表达式（AST 中保留了原始脚本块）
    elseif ($Ast -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
        # 优先使用 KnownBlockNames（来自 Invokes.ScriptBlocks，CFG 已经静态分析过）
        if ($KnownBlockNames.Count -gt 0) {
            foreach ($name in $KnownBlockNames) {
                if ($Context.ScriptBlockSubgraphs.ContainsKey($name)) {
                    return $name
                }
            }
        }

        # 备用：通过内容匹配查找
        $sbText = $Ast.ScriptBlock.Extent.Text.Trim()
        foreach ($blockName in $Context.ScriptBlockSubgraphs.Keys) {
            $blockStartId = $Context.ScriptBlockSubgraphs[$blockName]
            $blockStartNode = Get-NodeById -CFG $Context.CFG -Id $blockStartId
            # 使用 ScriptBlockText 属性进行匹配
            if ($blockStartNode.ScriptBlockText) {
                $blockText = $blockStartNode.ScriptBlockText.Trim()
                if ($sbText -eq $blockText) {
                    return $blockName
                }
            }
        }
    }

    return $null
}

# 从 AST 获取 ArgumentList 的值（数组）
function Get-ArgumentListValues {
    param(
        $Ast,
        [hashtable]$Context
    )

    $values = @()

    # ArrayLiteralAst：5, 3 形式
    if ($Ast -is [System.Management.Automation.Language.ArrayLiteralAst]) {
        foreach ($elem in $Ast.Elements) {
            $values += Get-AstValue -Ast $elem -Context $Context
        }
    }
    # ArrayExpressionAst：@(5, 3) 形式
    elseif ($Ast -is [System.Management.Automation.Language.ArrayExpressionAst]) {
        if ($Ast.SubExpression -and $Ast.SubExpression.Statements) {
            foreach ($stmt in $Ast.SubExpression.Statements) {
                if ($stmt.PipelineElements -and $stmt.PipelineElements.Count -gt 0) {
                    $expr = $stmt.PipelineElements[0].Expression
                    if ($expr -is [System.Management.Automation.Language.ArrayLiteralAst]) {
                        foreach ($elem in $expr.Elements) {
                            $values += Get-AstValue -Ast $elem -Context $Context
                        }
                    } else {
                        $values += Get-AstValue -Ast $expr -Context $Context
                    }
                }
            }
        }
    }
    # 单个值
    else {
        $values += Get-AstValue -Ast $Ast -Context $Context
    }

    return $values
}

# 从 AST 求值获取值
function Get-AstValue {
    param(
        $Ast,
        [hashtable]$Context
    )

    $code = $Ast.Extent.Text

    # 应用变量前缀转换
    if ($Context.ScopeStack.Count -gt 0) {
        $currentScope = $Context.ScopeStack[-1]
        if ($currentScope.LocalVars -and $currentScope.LocalVars.Count -gt 0) {
            $code = Convert-VariableNames -Code $code -ScopePrefix $currentScope.ScopePrefix -LocalVarNames $currentScope.LocalVars
        }
    }

    $evalResult = Invoke-InContext -ExecContext $Context.ExecContext -Code $code
    if ($evalResult.Success) {
        if ($evalResult.Result -is [System.Collections.ObjectModel.Collection[System.Management.Automation.PSObject]] -and $evalResult.Result.Count -eq 1) {
            return $evalResult.Result[0]
        }
        return $evalResult.Result
    }

    return $null
}

# 记录别名解析结果为可还原表达式
function Record-AliasResolution {
    param(
        $Node,
        [hashtable]$Context,
        $CommandInfo
    )

    # 目标：只替换“命令名 token”（别名本身），不能把整个命令（含参数）替换掉。
    #
    # 需要使用“原脚本偏移”：
    # - 优先：使用生成期记录的 Command Resolvable 对应的原始 CommandAst，取其首元素 Extent 作为偏移
    # - 其次：直接从 Node.Ast（原脚本 AST）里找匹配的 CommandAst，再取首元素 Extent
    # - 最后：无法映射则跳过（避免错误替换）

    $cmdNameElement = $null

    # 1) 优先：使用生成期的原始 AST 位置信息（最可靠）
    if ($CommandInfo.Resolvable -and $CommandInfo.Resolvable.Ast -and
        ($CommandInfo.Resolvable.Ast -is [System.Management.Automation.Language.CommandAst])) {
        $origCmdAst = $CommandInfo.Resolvable.Ast
        if ($origCmdAst.CommandElements -and $origCmdAst.CommandElements.Count -gt 0) {
            $cmdNameElement = $origCmdAst.CommandElements[0]
        }
    }

    # 2) 兜底：从 Node.Ast（原脚本 AST）中查找同名命令
    if (-not $cmdNameElement -and $Node -and $Node.Ast) {
        $cmdAsts = @($Node.Ast.FindAll({
            param($n)
            if (-not ($n -is [System.Management.Automation.Language.CommandAst])) { return $false }

            # 排除 ScriptBlockExpressionAst 内部命令（它们不在当前节点直接执行）
            $ancestor = $n.Parent
            while ($null -ne $ancestor -and $ancestor -ne $Node.Ast) {
                if ($ancestor -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
                    return $false
                }
                $ancestor = $ancestor.Parent
            }
            return $true
        }, $true))

        if ($cmdAsts.Count -gt 0) {
            $matched = @()
            foreach ($c in $cmdAsts) {
                $name = $c.GetCommandName()
                if ($name -and $name -eq $CommandInfo.OriginalName) {
                    $matched += $c
                }
            }

            if ($matched.Count -gt 0) {
                $chosen = @($matched | Sort-Object { $_.Extent.StartOffset } | Select-Object -First 1)
                if ($chosen -and $chosen.CommandElements -and $chosen.CommandElements.Count -gt 0) {
                    $cmdNameElement = $chosen.CommandElements[0]
                }
            }
        }
    }

    if (-not $cmdNameElement -or -not $cmdNameElement.Extent) {
        Write-ExecutionLog -Context $Context -Message "  [ALIAS] Cannot record alias resolution: no original position info"
        return
    }

    $startOffset = $cmdNameElement.Extent.StartOffset
    $endOffset = $cmdNameElement.Extent.EndOffset

    $key = "$($Node.Id):${startOffset}:${endOffset}"

    # 创建一个伪 Resolvable 对象来记录别名
    $aliasResolvable = @{
        Type        = "Alias"
        Text        = $CommandInfo.OriginalName
        StartOffset = $startOffset
        EndOffset   = $endOffset
        Depth       = 0
        Ast         = $cmdNameElement
        # 额外信息
        AliasName   = $CommandInfo.OriginalName
        TargetName  = $CommandInfo.ResolvedName
    }

    # 记录到结果集
    if (-not $Context.ResolvableResults.ContainsKey($key)) {
        $Context.ResolvableResults[$key] = @{
            NodeId     = $Node.Id
            Resolvable = $aliasResolvable
            Values     = @()
        }
    }

    # 别名解析结果是目标命令名
    $Context.ResolvableResults[$key].Values += $CommandInfo.ResolvedName

    Write-ExecutionLog -Context $Context -Message "  [ALIAS] Recorded: $($CommandInfo.OriginalName) -> $($CommandInfo.ResolvedName)"
}

# 初始化函数和脚本块子图映射
function Initialize-SubgraphMappings {
    param(
        [hashtable]$CFG,
        [hashtable]$Context
    )

    foreach ($node in $CFG.Nodes) {
        if ($node.Type -eq "FuncStart") {
            # 从 Text 提取函数名: "function MyFunc" → "MyFunc"
            if ($node.Text -match '^function\s+(.+)$') {
                $funcName = $Matches[1]
                $Context.FunctionSubgraphs[$funcName] = $node.Id
                Write-ExecutionLog -Context $Context -Message "  [INIT] Function subgraph: $funcName -> Node $($node.Id)"
            }
        }
        elseif ($node.Type -eq "BlockStart") {
            # 从 Text 提取块名: "ScriptBlock _block_xxx" → "_block_xxx"
            if ($node.Text -match '^ScriptBlock\s+(.+)$') {
                $blockName = $Matches[1]
                $Context.ScriptBlockSubgraphs[$blockName] = $node.Id
                Write-ExecutionLog -Context $Context -Message "  [INIT] ScriptBlock subgraph: $blockName -> Node $($node.Id)"
            }
        }
    }

    Write-ExecutionLog -Context $Context -Message "  [INIT] Total functions: $($Context.FunctionSubgraphs.Count), ScriptBlocks: $($Context.ScriptBlockSubgraphs.Count)"
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

    # 创建/清空日志文件（允许 LogPath=$null 以禁用日志）
    if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
        $null = New-Item -Path $LogPath -ItemType File -Force
    }

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
        VariableReadResults = @{}  # Key: "StartOffset:EndOffset", Value: @{ VarInfo; Values }

        # 新增字段 - 安全执行与作用域管理
        ScopeStack            = @()          # 作用域栈 [{ ScopeType; ScopeName; ScopePrefix; ReturnNodeId; LocalVars }]
        CurrentScopePrefix    = ""           # 当前作用域变量前缀
        ForbiddenCommands     = @(           # 违禁命令列表
            'Remove-Item', 'del', 'rm', 'rmdir', 'rd',
            'Format-Volume', 'Clear-Disk',
            'Stop-Process', 'kill', 'spps',
            'Stop-Computer', 'Restart-Computer',
            'Set-ExecutionPolicy',
            'New-Service', 'Remove-Service',
            'Clear-Content', 'Clear-ItemProperty',
            'Remove-ItemProperty', 'Clear-RecycleBin',
            'Start-Process', 'Invoke-WebRequest', 'Invoke-RestMethod',
            'New-Object', 'Add-Type'  # 危险的 .NET 操作
        )
        FunctionSubgraphs     = @{}          # 函数名 -> FuncStart 节点 Id
        ScriptBlockSubgraphs  = @{}          # _block_xxx -> BlockStart 节点 Id
        VarToBlockMapping     = @{}          # 变量名 -> 块名 映射（用于动态创建的脚本块跟踪）
        CallStack             = @()          # 调用栈 [{ Type; Name; ReturnNodeId }]
        MaxCallDepth          = 100          # 最大调用深度
        DynamicInvokeResults  = @()          # 动态执行记录 [{ NodeId; Command; ArgumentValue }]
        LastSubgraphResult    = $null        # 子图（函数/脚本块）的最后执行结果，用于返回值传递
        PipelineCurrentStack  = @()          # $_ / $PSItem 绑定栈（用于 ForEach-Object 等嵌套管道上下文）
        OutputCaptureStack    = @()          # 输出捕获栈（用于 ForEach-Object 等逐项执行）
        LastPipelineFlowControl = $null      # "Break" 等（仅用于管道 cmdlet 控制流）
        TextParseCache        = @{}          # Node.Text 解析缓存（执行期 text-first）
        TextParseErrors       = @()          # 解析错误记录（非阻塞）
    }

    Write-ExecutionLog -Context $context -Message "=== CFG 执行开始 ==="
    Write-ExecutionLog -Context $context -Message "MaxIterations: $MaxIterations, MaxTotalNodes: $MaxTotalNodes"
    Write-ExecutionLog -Context $context -Message ""

    # 初始化子图映射
    Write-ExecutionLog -Context $context -Message "=== 初始化子图映射 ==="
    Initialize-SubgraphMappings -CFG $CFG -Context $context
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

# ========== 调试模式：会话化单步执行 API ==========

function New-CFGExecutionSession {
    param(
        [Parameter(Mandatory)]
        [hashtable]$CFG,
        [string]$LogPath = "execution.log",
        [int]$MaxIterations = 1000,
        [int]$MaxTotalNodes = 50000
    )

    if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
        $null = New-Item -Path $LogPath -ItemType File -Force
    }

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
        ResolvableResults   = @{}
        VariableReadResults = @{}

        ScopeStack            = @()
        CurrentScopePrefix    = ""
        ForbiddenCommands     = @(
            'Remove-Item', 'del', 'rm', 'rmdir', 'rd',
            'Format-Volume', 'Clear-Disk',
            'Stop-Process', 'kill', 'spps',
            'Stop-Computer', 'Restart-Computer',
            'Set-ExecutionPolicy',
            'New-Service', 'Remove-Service',
            'Clear-Content', 'Clear-ItemProperty',
            'Remove-ItemProperty', 'Clear-RecycleBin',
            'Start-Process', 'Invoke-WebRequest', 'Invoke-RestMethod',
            'New-Object', 'Add-Type'
        )
        FunctionSubgraphs      = @{}
        ScriptBlockSubgraphs   = @{}
        VarToBlockMapping      = @{}
        CallStack              = @()
        MaxCallDepth           = 100
        DynamicInvokeResults   = @()
        LastSubgraphResult     = $null
        PipelineCurrentStack   = @()
        OutputCaptureStack     = @()
        LastPipelineFlowControl = $null
        TextParseCache         = @{}
        TextParseErrors        = @()
    }

    Write-ExecutionLog -Context $context -Message "=== CFG 调试会话开始 ==="
    Write-ExecutionLog -Context $context -Message "MaxIterations: $MaxIterations, MaxTotalNodes: $MaxTotalNodes"
    Write-ExecutionLog -Context $context -Message ""
    Write-ExecutionLog -Context $context -Message "=== 初始化子图映射 ==="
    Initialize-SubgraphMappings -CFG $CFG -Context $context
    Write-ExecutionLog -Context $context -Message ""

    $startNode = $CFG.Nodes | Where-Object { $_.Type -eq "Start" } | Select-Object -First 1
    $completed = $false
    $stopReason = $null
    if ($null -eq $startNode) {
        Write-ExecutionLog -Context $context -Message "!!! 未找到 Start 节点 !!!"
        $completed = $true
        $stopReason = 'NoStartNode'
    }

    return @{
        CFG           = $CFG
        Context       = $context
        CurrentNode   = $startNode
        IsCompleted   = $completed
        StopReason    = $stopReason
        StepCounter   = 0
        History       = New-Object System.Collections.ArrayList
        SummaryLogged = $false
        Closed        = $false
    }
}

function Write-CFGExecutionSummary {
    param(
        [Parameter(Mandatory)][hashtable]$Session
    )

    if ($Session.SummaryLogged) { return }

    $context = $Session.Context
    Write-ExecutionLog -Context $context -Message ""
    Write-ExecutionLog -Context $context -Message "=== 执行统计 ==="
    Write-ExecutionLog -Context $context -Message "Total visits: $($context.TotalVisits)"
    Write-ExecutionLog -Context $context -Message "Unique nodes: $($context.VisitedNodes.Count)"
    if ($Session.StopReason) {
        Write-ExecutionLog -Context $context -Message "StopReason: $($Session.StopReason)"
    }

    $Session.SummaryLogged = $true
}

function Close-CFGExecutionSession {
    param(
        [Parameter(Mandatory)][hashtable]$Session
    )

    if ($Session.Closed) { return }
    Write-CFGExecutionSummary -Session $Session
    if ($Session.Context -and $Session.Context.ExecContext) {
        Close-ExecutionContext -ExecContext $Session.Context.ExecContext
    }
    $Session.Closed = $true
}

function Test-CFGDebugAutoPassNodeType {
    param([string]$NodeType)
    $autoTypes = @(
        'Start', 'MainStart', 'MainEnd',
        'If Condition', 'Else', 'Merge', 'Default',
        'Try', 'Catch', 'Finally', 'FunctionDef',
        'LoopStart', 'LoopEnd', 'ProcessEnd', 'SwitchStart', 'SwitchEnd',
        'FuncStart', 'BlockStart', 'FuncParams', 'BlockParams',
        'FuncEnd', 'BlockEnd', 'Return'
    )
    return ($NodeType -in $autoTypes)
}

function Get-CFGEdgeLabel {
    param(
        [Parameter(Mandatory)][hashtable]$CFG,
        [Parameter(Mandatory)][int]$FromNodeId,
        [Parameter(Mandatory)][int]$ToNodeId
    )

    $edge = $CFG.Edges | Where-Object { $_.From -eq $FromNodeId -and $_.To -eq $ToNodeId } | Select-Object -First 1
    if ($edge) { return [string]$edge.Label }
    return $null
}

function Get-CFGConditionEdgeLabel {
    param(
        [Parameter(Mandatory)][string]$NodeType,
        [Parameter(Mandatory)][bool]$ConditionValue
    )

    switch ($NodeType) {
        'Condition'        { if ($ConditionValue) { return 'True' } else { return 'False' } }
        'SwitchCondition'  { if ($ConditionValue) { return 'True' } else { return 'False' } }
        'CaseCondition'    { if ($ConditionValue) { return 'True' } else { return 'False' } }
        'ForEachCondition' { if ($ConditionValue) { return 'Has next' } else { return 'No more items' } }
        'ProcessCondition' { if ($ConditionValue) { return 'Has next' } else { return 'No more items' } }
        default            { if ($ConditionValue) { return 'True' } else { return 'False' } }
    }
}

function Invoke-CFGStep {
    param(
        [Parameter(Mandatory)][hashtable]$Session,
        [switch]$StopAtUserNode = $true
    )

    if ($Session.IsCompleted) {
        return @{
            Completed   = $true
            StopReason  = $Session.StopReason
            Records     = @()
            LastRecord  = $null
            CurrentNode = $Session.CurrentNode
        }
    }

    $context = $Session.Context
    $records = New-Object System.Collections.ArrayList

    function Convert-VarMapToRecord {
        param([hashtable]$VarMap)
        $out = [ordered]@{}
        foreach ($k in @($VarMap.Keys | Sort-Object)) {
            $out[$k] = Format-VariableValue $VarMap[$k]
        }
        return $out
    }

    function Add-Record {
        param($Record)
        if ($null -eq $Record.PSObject.Properties['Step']) {
            $Record | Add-Member -NotePropertyName Step -NotePropertyValue $Session.StepCounter -Force
        } else {
            $Record.Step = $Session.StepCounter
        }
        $Session.StepCounter++
        $null = $records.Add($Record)
        $null = $Session.History.Add($Record)
    }

    while (-not $Session.IsCompleted) {
        $currentNode = $Session.CurrentNode
        if ($null -eq $currentNode) {
            $Session.IsCompleted = $true
            if (-not $Session.StopReason) { $Session.StopReason = 'NoNextNode' }
            break
        }

        # 调试单步语义：
        # 本次点击如果已经自动穿过了结构节点（records.Count > 0），
        # 遇到第一个“有效执行节点”时先停下，让用户下一次点击再真正执行该节点。
        $isAutoPassCurrent = Test-CFGDebugAutoPassNodeType -NodeType $currentNode.Type
        if ($StopAtUserNode -and -not $isAutoPassCurrent -and $records.Count -gt 0) {
            break
        }

        # 终点
        if ($currentNode.Type -eq "End") {
            Write-ExecutionLog -Context $context -Message "=== 执行结束 ==="
            Add-Record ([PSCustomObject]@{
                Time             = (Get-Date).ToString('HH:mm:ss.fff')
                NodeId           = $currentNode.Id
                NodeType         = $currentNode.Type
                Code             = [string]$currentNode.Text
                Status           = 'END'
                Action           = 'End'
                Target           = $null
                Reason           = $null
                Error            = $null
                Result           = $null
                Executed         = $false
                Success          = $true
                ConditionResult  = $null
                VarsRead         = [ordered]@{}
                VarsWritten      = [ordered]@{}
                NextNodeId       = $null
                NextEdgeLabel    = $null
                AutoPassed       = $true
            })
            $Session.CurrentNode = $null
            $Session.IsCompleted = $true
            $Session.StopReason = 'EndNode'
            break
        }

        # FuncEnd / BlockEnd 特殊处理
        if ($currentNode.Type -eq "FuncEnd" -or $currentNode.Type -eq "BlockEnd") {
            Write-ExecutionLog -Context $context -Message "--- Node $($currentNode.Id) [$($currentNode.Type)] ---"
            Write-ExecutionLog -Context $context -Message "  Code: $($currentNode.Text)"

            $returnValue = $context.LastSubgraphResult
            $nextNode = $null

            $scope = Pop-ExecutionScope -Context $context
            if ($scope) {
                if ($scope.ReturnNodeId) {
                    $context.LastSubgraphResult = $null

                    if ($scope.TargetVarName -and $null -ne $returnValue) {
                        $actualVarName = $scope.TargetVarName
                        if ($context.ScopeStack.Count -gt 0) {
                            $outerScope = $context.ScopeStack[-1]
                            if ($outerScope.LocalVars -and $scope.TargetVarName -in $outerScope.LocalVars) {
                                $actualVarName = $outerScope.ScopePrefix + $scope.TargetVarName
                            }
                        }
                        $context.ExecContext.Runspace.SessionStateProxy.SetVariable($actualVarName, $returnValue)
                        Write-ExecutionLog -Context $context -Message "  [RETURN] Set `$$actualVarName = $(Format-VariableValue $returnValue)"
                    }

                    Write-ExecutionLog -Context $context -Message "  [RETURN] Returning from $($scope.ScopeType) '$($scope.ScopeName)' to Node $($scope.ReturnNodeId)"
                    $nextNode = Get-NodeById -CFG $context.CFG -Id $scope.ReturnNodeId
                } else {
                    $context.LastSubgraphResult = $returnValue
                    Write-ExecutionLog -Context $context -Message "  [RETURN] Inline call completed, preserving result: $(Format-VariableValue $returnValue)"
                }
            }

            $edgeLabel = if ($nextNode) { Get-CFGEdgeLabel -CFG $context.CFG -FromNodeId $currentNode.Id -ToNodeId $nextNode.Id } else { $null }
            Add-Record ([PSCustomObject]@{
                Time             = (Get-Date).ToString('HH:mm:ss.fff')
                NodeId           = $currentNode.Id
                NodeType         = $currentNode.Type
                Code             = [string]$currentNode.Text
                Status           = 'OK'
                Action           = 'ReturnToCaller'
                Target           = if ($nextNode) { $nextNode.Id } else { $null }
                Reason           = $null
                Error            = $null
                Result           = if ($null -ne $returnValue) { Format-VariableValue $returnValue } else { $null }
                Executed         = $false
                Success          = $true
                ConditionResult  = $null
                VarsRead         = [ordered]@{}
                VarsWritten      = [ordered]@{}
                NextNodeId       = if ($nextNode) { $nextNode.Id } else { $null }
                NextEdgeLabel    = $edgeLabel
                AutoPassed       = $true
            })

            $Session.CurrentNode = $nextNode
            if ($null -eq $nextNode) {
                $Session.IsCompleted = $true
                if (-not $Session.StopReason) { $Session.StopReason = 'NoNextNode' }
                break
            }
            continue
        }

        # Return 节点特殊处理
        if ($currentNode.Type -eq "Return") {
            Write-ExecutionLog -Context $context -Message "--- Node $($currentNode.Id) [Return] ---"
            Write-ExecutionLog -Context $context -Message "  Code: $($currentNode.Text)"

            $context.VisitedNodes[$currentNode.Id] = ($context.VisitedNodes[$currentNode.Id] ?? 0) + 1
            $context.TotalVisits++

            $returnValue = $null
            $nextNode = $null

            if ($context.ScopeStack.Count -gt 0) {
                $currentScope = $context.ScopeStack[-1]
                $retInfo = Get-NodeTextReturnExpression -Node $currentNode -Context $context
                if (-not $retInfo.Success) {
                    Write-ExecutionLog -Context $context -Message "  [RETURN] Parse Node.Text failed: $($retInfo.Error)"
                } elseif ($retInfo.Code) {
                    $returnCode = Convert-CodeForCurrentScope -Code $retInfo.Code -Context $context
                    $evalResult = Invoke-InContext -ExecContext $context.ExecContext -Code $returnCode
                    if ($evalResult.Success -and $null -ne $evalResult.Result) {
                        if ($context.OutputCaptureStack -and $context.OutputCaptureStack.Count -gt 0) {
                            Add-OutputsToCurrentCapture -Context $context -Result $evalResult.Result
                        }
                        if ($evalResult.Result -is [System.Collections.ObjectModel.Collection[System.Management.Automation.PSObject]]) {
                            if ($evalResult.Result.Count -eq 1) { $returnValue = $evalResult.Result[0] }
                            elseif ($evalResult.Result.Count -gt 1) { $returnValue = $evalResult.Result }
                        } else {
                            $returnValue = $evalResult.Result
                        }
                        Write-ExecutionLog -Context $context -Message "  [RETURN] Expression value: $(Format-VariableValue $returnValue)"
                    }
                }

                $context.LastSubgraphResult = $returnValue
                if ($currentScope.EndNodeId) {
                    Write-ExecutionLog -Context $context -Message "  [RETURN] Jumping to EndNode $($currentScope.EndNodeId)"
                    $nextNode = Get-NodeById -CFG $context.CFG -Id $currentScope.EndNodeId
                }
            } else {
                $nextNodes = Get-NextNodes -CFG $context.CFG -Node $currentNode -Context $context
                if ($nextNodes.Count -gt 0) { $nextNode = $nextNodes[0] }
            }

            $edgeLabel = if ($nextNode) { Get-CFGEdgeLabel -CFG $context.CFG -FromNodeId $currentNode.Id -ToNodeId $nextNode.Id } else { $null }
            Add-Record ([PSCustomObject]@{
                Time             = (Get-Date).ToString('HH:mm:ss.fff')
                NodeId           = $currentNode.Id
                NodeType         = $currentNode.Type
                Code             = [string]$currentNode.Text
                Status           = 'OK'
                Action           = 'Return'
                Target           = if ($nextNode) { $nextNode.Id } else { $null }
                Reason           = $null
                Error            = $null
                Result           = if ($null -ne $returnValue) { Format-VariableValue $returnValue } else { $null }
                Executed         = $true
                Success          = $true
                ConditionResult  = $null
                VarsRead         = [ordered]@{}
                VarsWritten      = [ordered]@{}
                NextNodeId       = if ($nextNode) { $nextNode.Id } else { $null }
                NextEdgeLabel    = $edgeLabel
                AutoPassed       = $true
            })

            $Session.CurrentNode = $nextNode
            if ($null -eq $nextNode) {
                $Session.IsCompleted = $true
                if (-not $Session.StopReason) { $Session.StopReason = 'NoNextNode' }
                break
            }
            continue
        }

        if ($context.TotalVisits -ge $context.MaxTotalNodes) {
            Write-ExecutionLog -Context $context -Message "!!! 达到最大节点访问次数 ($($context.MaxTotalNodes)) !!!"
            $Session.IsCompleted = $true
            $Session.StopReason = 'MaxTotalNodes'
            break
        }

        $nodeKey = $currentNode.Id
        if (-not $context.VisitedNodes.ContainsKey($nodeKey)) {
            $context.VisitedNodes[$nodeKey] = 0
        }
        if ($context.VisitedNodes[$nodeKey] -ge $context.MaxIterations) {
            Write-ExecutionLog -Context $context -Message "!!! 节点 $nodeKey 达到最大迭代次数 ($($context.MaxIterations)) !!!"
            $Session.IsCompleted = $true
            $Session.StopReason = 'MaxIterations'
            break
        }

        $context.VisitedNodes[$nodeKey]++
        $context.TotalVisits++

        Write-ExecutionLog -Context $context -Message "--- Node $($currentNode.Id) [$($currentNode.Type)] ---"
        Write-ExecutionLog -Context $context -Message "  Code: $($currentNode.Text)"

        if ($currentNode.Type -in @('FuncParams', 'BlockParams') -and $context.ScopeStack.Count -gt 0) {
            $currentScope = $context.ScopeStack[-1]
            if ($currentScope.Arguments -and $currentScope.Arguments.Count -gt 0) {
                if ($currentNode.Ast -and $currentNode.Ast.Parameters) {
                    $paramNames = @()
                    foreach ($param in $currentNode.Ast.Parameters) {
                        $paramNames += $param.Name.VariablePath.UserPath
                    }

                    for ($i = 0; $i -lt [Math]::Min($paramNames.Count, $currentScope.Arguments.Count); $i++) {
                        $paramName = $paramNames[$i]
                        $argValue = $currentScope.Arguments[$i]
                        $prefixedName = $currentScope.ScopePrefix + $paramName
                        $context.ExecContext.Runspace.SessionStateProxy.SetVariable($prefixedName, $argValue)
                        Write-ExecutionLog -Context $context -Message "  [BIND] `$$prefixedName = $(Format-VariableValue $argValue)"
                        if ($paramName -notin $currentScope.LocalVars) {
                            $currentScope.LocalVars += $paramName
                        }
                    }
                }
            }
        }

        $varsBefore = @{}
        foreach ($varInfo in @($currentNode.VarsRead)) {
            $actualVarName = $varInfo.Name
            if ($context.ScopeStack.Count -gt 0) {
                $currentScope = $context.ScopeStack[-1]
                if ($currentScope.LocalVars -and $varInfo.Name -in $currentScope.LocalVars) {
                    $actualVarName = $currentScope.ScopePrefix + $varInfo.Name
                }
            }
            $value = Get-VariableFromContext -ExecContext $context.ExecContext -Name $actualVarName
            $varsBefore[$varInfo.Name] = $value

            if ($null -ne $varInfo.StartOffset -and $null -ne $varInfo.EndOffset -and (Test-ResolvableValue $value)) {
                $key = "$($currentNode.Id):$($varInfo.StartOffset):$($varInfo.EndOffset)"
                if (-not $context.VariableReadResults.ContainsKey($key)) {
                    $context.VariableReadResults[$key] = @{
                        NodeId  = $currentNode.Id
                        VarInfo = $varInfo
                        Values  = @()
                    }
                }
                $context.VariableReadResults[$key].Values += (Format-ResolvableValue $value)
            }
        }

        $execResult = Invoke-NodeSafe -Node $currentNode -Context $context

        if ($context.OutputCaptureStack -and $context.OutputCaptureStack.Count -gt 0) {
            $captureThis = $true
            $nonOutputTypes = @('Condition', 'ForEachCondition', 'ProcessCondition', 'SwitchCondition', 'CaseCondition')
            if ($currentNode.Type -in $nonOutputTypes) { $captureThis = $false }
            if ($captureThis -and $currentNode.Type -eq 'PipelineElement' -and $currentNode.VarsWritten) {
                foreach ($v in $currentNode.VarsWritten) {
                    if ($v.Name -match '^_pipe_[a-f0-9]+$') {
                        $captureThis = $false
                        break
                    }
                }
            }
            if ($captureThis) {
                Add-OutputsToCurrentCapture -Context $context -Result $execResult.Result
            }
        }

        if ($context.OutputCaptureStack -and $context.OutputCaptureStack.Count -gt 0 -and $currentNode.Type -in @('Break', 'Continue')) {
            $label = $currentNode.Type
            $edge = $context.CFG.Edges | Where-Object { $_.From -eq $currentNode.Id -and $_.Label -eq $label } | Select-Object -First 1
            if ($edge) {
                $targetNode = Get-NodeById -CFG $context.CFG -Id $edge.To
                if ($targetNode -and $targetNode.Type -in @('BlockEnd', 'FuncEnd', 'ProcessEnd', 'End', 'MainEnd')) {
                    $context.LastPipelineFlowControl = $label
                }
            }
        }

        $varsAfter = @{}
        foreach ($varInfo in @($currentNode.VarsWritten)) {
            $actualVarName = $varInfo.Name
            if ($context.ScopeStack.Count -gt 0) {
                $currentScope = $context.ScopeStack[-1]
                if ($currentScope.LocalVars -and $varInfo.Name -in $currentScope.LocalVars) {
                    $actualVarName = $currentScope.ScopePrefix + $varInfo.Name
                }
            }
            $value = Get-VariableFromContext -ExecContext $context.ExecContext -Name $actualVarName
            $varsAfter[$varInfo.Name] = $value
        }

        $status = if ($execResult.Action -eq "Blocked") {
            "BLOCKED"
        } elseif (-not $execResult.Executed) {
            "SKIP"
        } elseif ($execResult.Success) {
            "OK"
        } else {
            "ERR"
        }

        Write-ExecutionLog -Context $context -Message "  Status: $status"
        if ($execResult.Action -and $execResult.Action -notin @("Execute", "Skip")) {
            Write-ExecutionLog -Context $context -Message "  Action: $($execResult.Action)"
            if ($execResult.Target) { Write-ExecutionLog -Context $context -Message "  Target: $($execResult.Target)" }
            if ($execResult.Reason) { Write-ExecutionLog -Context $context -Message "  Reason: $($execResult.Reason)" }
        }

        if ($execResult.Executed) {
            if ($varsBefore.Count -gt 0) {
                Write-ExecutionLog -Context $context -Message "  VarsRead:"
                foreach ($kv in $varsBefore.GetEnumerator()) {
                    Write-ExecutionLog -Context $context -Message "    `$$($kv.Key) = $(Format-VariableValue $kv.Value)"
                }
            }
            if ($varsAfter.Count -gt 0) {
                Write-ExecutionLog -Context $context -Message "  VarsWritten:"
                foreach ($kv in $varsAfter.GetEnumerator()) {
                    Write-ExecutionLog -Context $context -Message "    `$$($kv.Key) = $(Format-VariableValue $kv.Value)"
                }
            }
            if ($null -ne $execResult.Result -and $execResult.Result.Count -gt 0) {
                Write-ExecutionLog -Context $context -Message "  Result: $(Format-VariableValue $execResult.Result)"
                if ($context.ScopeStack.Count -gt 0) {
                    if ($execResult.Result -is [System.Collections.ObjectModel.Collection[System.Management.Automation.PSObject]]) {
                        if ($execResult.Result.Count -eq 1) { $context.LastSubgraphResult = $execResult.Result[0] }
                        else { $context.LastSubgraphResult = $execResult.Result }
                    } else {
                        $context.LastSubgraphResult = $execResult.Result
                    }
                }
            }
            if (-not $execResult.Success -and $execResult.Error) {
                Write-ExecutionLog -Context $context -Message "  Error: $($execResult.Error)"
            }
            if ($currentNode.Type -in @('Condition', 'ForEachCondition', 'ProcessCondition', 'SwitchCondition', 'CaseCondition')) {
                Write-ExecutionLog -Context $context -Message "  ConditionResult: $($context.LastConditionResult)"
            }
        }

        $nextNode = $null
        if ($execResult.Action -in @("CallFunction", "CallScriptBlock") -and $execResult.JumpToNode) {
            Write-ExecutionLog -Context $context -Message "  [JUMP] Jumping to Node $($execResult.JumpToNode.Id)"
            $nextNode = $execResult.JumpToNode
        } else {
            $nextNodes = Get-NextNodes -CFG $context.CFG -Node $currentNode -Context $context
            if ($nextNodes.Count -gt 0) {
                $nextNode = $nextNodes[0]
            }
        }

        $nextEdgeLabel = if ($nextNode) { Get-CFGEdgeLabel -CFG $context.CFG -FromNodeId $currentNode.Id -ToNodeId $nextNode.Id } else { $null }
        $autoPassed = Test-CFGDebugAutoPassNodeType -NodeType $currentNode.Type

        Add-Record ([PSCustomObject]@{
            Time             = (Get-Date).ToString('HH:mm:ss.fff')
            NodeId           = $currentNode.Id
            NodeType         = $currentNode.Type
            Code             = [string]$currentNode.Text
            Status           = $status
            Action           = $execResult.Action
            Target           = $execResult.Target
            Reason           = $execResult.Reason
            Error            = $execResult.Error
            Result           = if ($null -ne $execResult.Result) { Format-VariableValue $execResult.Result } else { $null }
            Executed         = [bool]$execResult.Executed
            Success          = [bool]$execResult.Success
            ConditionResult  = if ($currentNode.Type -in @('Condition', 'ForEachCondition', 'ProcessCondition', 'SwitchCondition', 'CaseCondition')) { [bool]$context.LastConditionResult } else { $null }
            VarsRead         = Convert-VarMapToRecord -VarMap $varsBefore
            VarsWritten      = Convert-VarMapToRecord -VarMap $varsAfter
            NextNodeId       = if ($nextNode) { $nextNode.Id } else { $null }
            NextEdgeLabel    = $nextEdgeLabel
            AutoPassed       = $autoPassed
        })

        $Session.CurrentNode = $nextNode
        if ($null -eq $nextNode) {
            $Session.IsCompleted = $true
            if (-not $Session.StopReason) { $Session.StopReason = 'NoNextNode' }
            break
        }

        if ($StopAtUserNode -and -not $autoPassed) {
            break
        }
    }

    if ($Session.IsCompleted) {
        Write-CFGExecutionSummary -Session $Session
    }

    return @{
        Completed   = $Session.IsCompleted
        StopReason  = $Session.StopReason
        Records     = @($records)
        LastRecord  = if ($records.Count -gt 0) { $records[$records.Count - 1] } else { $null }
        CurrentNode = $Session.CurrentNode
    }
}

function Test-CFGInternalVariableName {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) { return $true }
    if ($Name -in $script:AutoVariables) { return $true }
    if ($Name -match '^(_pipe_|_sc_[a-f0-9]{8}_|__|_fe_|_sw_|_foreach_|_where_|_select_|_proc_|_dyn_|_block_)') { return $true }
    if ($Name -in @('Error','Host','PID','PWD','ShellId','StackTrace','Matches','LastExitCode','PSBoundParameters','PSDefaultParameterValues','MyInvocation','PSScriptRoot','PSCommandPath')) { return $true }
    if ($Name -match '^PS[A-Z]') { return $true }
    return $false
}

function Get-CFGVariableStack {
    param(
        [Parameter(Mandatory)][hashtable]$Session,
        [switch]$IncludeInternal
    )

    $context = $Session.Context
    $eval = Invoke-InContext -ExecContext $context.ExecContext -Code "Get-Variable | Select-Object Name, Value"
    if (-not $eval.Success -or $null -eq $eval.Result) { return @() }

    $rows = @()
    foreach ($item in @($eval.Result)) {
        if ($null -eq $item -or -not $item.PSObject.Properties['Name']) { continue }
        $actualName = [string]$item.Name
        if ([string]::IsNullOrWhiteSpace($actualName)) { continue }

        $isInternal = Test-CFGInternalVariableName -Name $actualName
        if (-not $IncludeInternal -and $isInternal) { continue }

        $displayName = $actualName
        if ($actualName -match '^_sc_[a-f0-9]{8}_(.+)$') {
            $displayName = [string]$Matches[1]
        }

        $rows += [PSCustomObject]@{
            DisplayName = $displayName
            ActualName  = $actualName
            IsInternal  = $isInternal
            Value       = if ($item.PSObject.Properties['Value']) { $item.Value } else { $null }
            ValueText   = if ($item.PSObject.Properties['Value']) { Format-VariableValue $item.Value } else { '$null' }
        }
    }

    return @($rows | Sort-Object DisplayName, ActualName)
}

function Set-CFGVariableValue {
    param(
        [Parameter(Mandatory)][hashtable]$Session,
        [Parameter(Mandatory)][string]$VariableName,
        [Parameter(Mandatory)][string]$ValueExpression
    )

    if ([string]::IsNullOrWhiteSpace($VariableName)) {
        throw "VariableName 不能为空。"
    }
    if ([string]::IsNullOrWhiteSpace($ValueExpression)) {
        throw "ValueExpression 不能为空。"
    }

    $context = $Session.Context
    $tokens = $null
    $errors = $null
    $exprAst = [System.Management.Automation.Language.Parser]::ParseInput($ValueExpression, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count -gt 0) {
        throw "变量值表达式解析失败: $($errors[0].Message)"
    }

    $cmdAsts = @($exprAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true))
    foreach ($cmdAst in $cmdAsts) {
        $cmdName = $cmdAst.GetCommandName()
        if ([string]::IsNullOrWhiteSpace($cmdName)) { continue }
        if ($context.ForbiddenCommands -contains $cmdName) {
            throw "变量值表达式包含禁用命令: $cmdName"
        }
    }

    $evalResult = Invoke-InContext -ExecContext $context.ExecContext -Code "($ValueExpression)"
    if (-not $evalResult.Success) {
        throw "变量值求值失败: $($evalResult.Error)"
    }

    $valueToSet = $null
    if ($evalResult.Result -is [System.Collections.ObjectModel.Collection[System.Management.Automation.PSObject]]) {
        if ($evalResult.Result.Count -eq 1) {
            $valueToSet = $evalResult.Result[0]
        } elseif ($evalResult.Result.Count -gt 1) {
            $valueToSet = @($evalResult.Result)
        }
    } else {
        $valueToSet = $evalResult.Result
    }

    $context.ExecContext.Runspace.SessionStateProxy.SetVariable($VariableName, $valueToSet)

    return [PSCustomObject]@{
        Name      = $VariableName
        Value     = $valueToSet
        ValueText = Format-VariableValue $valueToSet
    }
}

function Get-CFGNextEdgePreview {
    param(
        [Parameter(Mandatory)][hashtable]$Session
    )

    if ($Session.IsCompleted -or $null -eq $Session.CurrentNode) {
        return [PSCustomObject]@{
            HasPreview         = $false
            NodeId             = $null
            NodeType           = $null
            EdgeLabel          = $null
            ToNodeId           = $null
            PredictedCondition = $null
            Error              = $null
        }
    }

    $context = $Session.Context
    $node = $Session.CurrentNode
    $conditionTypes = @('Condition', 'ForEachCondition', 'ProcessCondition', 'SwitchCondition', 'CaseCondition')

    if ($node.Type -in $conditionTypes) {
        $code = Convert-CodeForCurrentScope -Code ([string]$node.Text) -Context $context
        $eval = Invoke-InContext -ExecContext $context.ExecContext -Code $code
        if (-not $eval.Success) {
            return [PSCustomObject]@{
                HasPreview         = $false
                NodeId             = $node.Id
                NodeType           = $node.Type
                EdgeLabel          = $null
                ToNodeId           = $null
                PredictedCondition = $null
                Error              = $eval.Error
            }
        }

        $pred = $false
        if ($null -ne $eval.Result -and $eval.Result.Count -gt 0) {
            $pred = [bool]$eval.Result[0]
        }
        $label = Get-CFGConditionEdgeLabel -NodeType $node.Type -ConditionValue $pred
        $edge = $context.CFG.Edges | Where-Object { $_.From -eq $node.Id -and $_.Label -eq $label } | Select-Object -First 1
        $toNodeId = if ($edge) { [int]$edge.To } else { $null }

        return [PSCustomObject]@{
            HasPreview         = [bool]$edge
            NodeId             = $node.Id
            NodeType           = $node.Type
            EdgeLabel          = $label
            ToNodeId           = $toNodeId
            PredictedCondition = $pred
            Error              = $null
        }
    }

    $nextNodes = Get-NextNodes -CFG $context.CFG -Node $node -Context $context
    if ($nextNodes.Count -eq 0) {
        return [PSCustomObject]@{
            HasPreview         = $false
            NodeId             = $node.Id
            NodeType           = $node.Type
            EdgeLabel          = $null
            ToNodeId           = $null
            PredictedCondition = $null
            Error              = $null
        }
    }

    $nextNode = $nextNodes[0]
    $label = Get-CFGEdgeLabel -CFG $context.CFG -FromNodeId $node.Id -ToNodeId $nextNode.Id
    return [PSCustomObject]@{
        HasPreview         = $true
        NodeId             = $node.Id
        NodeType           = $node.Type
        EdgeLabel          = $label
        ToNodeId           = $nextNode.Id
        PredictedCondition = $null
        Error              = $null
    }
}
