<#
.SYNOPSIS
  基于 Rebuild-Deobfuscated 生成的 roundXX.execution.log / report / cfg 图，提供 WPF 交互界面复盘逐节点执行过程。

.DESCRIPTION
  - 4 个按钮：上一步、下一步、重置、执行到最后
  - 左侧：按时间顺序的 Node 访问帧（同一 Node 可能出现多次）
  - 右侧上方：CFG 图片（roundXX.cfg.png）+ 透明热区，可点击节点跳转；当前节点高亮
  - 右侧下方：当前节点详细信息 + 变量状态（累计状态 + 本节点 VarsRead/VarsWritten）+ report 摘要

  注意：
  - 该脚本需要 Windows + WPF（仅在 Windows 可用）
  - 建议用 pwsh 并使用 -Sta（脚本会自动尝试以 STA 重新启动自身）
  - 节点图交互依赖 Graphviz dot（用于 dot -Tplain 取布局坐标）

.EXAMPLE
  pwsh -NoProfile -Sta -File .\Review-RoundReplay.Wpf.ps1

.EXAMPLE
  pwsh -NoProfile -Sta -File .\Review-RoundReplay.Wpf.ps1 -WorkDir .\in\in.rebuilt.ps1.work -Round 1
#>

[CmdletBinding()]
param(
    [string]$WorkDir,
    [int]$Round,
    [ValidateRange(10, 5000)]
    [int]$CheckpointInterval = 200,
    # 仅用于无 GUI/自动化场景：不打开窗口，只解析并输出摘要
    [switch]$NoUI
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $IsWindows) {
    throw "该脚本仅支持 Windows（需要 WPF）。"
}

function Restart-SelfAsStaIfNeeded {
    param(
        [hashtable]$BoundParams
    )

    if ($NoUI) { return }

    $apt = [System.Threading.Thread]::CurrentThread.ApartmentState
    if ($apt -eq [System.Threading.ApartmentState]::STA) { return }

    # 重新拼接参数（避免依赖 $args）
    $argList = @('-NoProfile', '-Sta', '-File', $PSCommandPath)
    foreach ($kv in $BoundParams.GetEnumerator() | Sort-Object Key) {
        $k = $kv.Key
        $v = $kv.Value
        if ($null -eq $v) { continue }
        if ($v -is [switch] -and -not $v.IsPresent) { continue }

        $argList += ('-' + $k)
        if (-not ($v -is [switch])) {
            $argList += [string]$v
        }
    }

    $exe = $null
    try {
        $p = Get-Process -Id $PID -ErrorAction Stop
        if ($p.Path) { $exe = $p.Path }
    } catch {
        $exe = $null
    }
    if (-not $exe) {
        $cmd = Get-Command pwsh -ErrorAction SilentlyContinue
        if ($cmd) { $exe = $cmd.Source }
    }
    if (-not $exe) {
        throw "当前线程不是 STA，且无法定位 pwsh。请用以下方式启动：pwsh -NoProfile -Sta -File `"$PSCommandPath`""
    }

    & $exe @argList
    exit $LASTEXITCODE
}

Restart-SelfAsStaIfNeeded -BoundParams $PSBoundParameters

function Import-UiAssemblies {
    Add-Type -AssemblyName PresentationFramework | Out-Null
    Add-Type -AssemblyName PresentationCore | Out-Null
    Add-Type -AssemblyName WindowsBase | Out-Null
    Add-Type -AssemblyName System.Windows.Forms | Out-Null
}

Import-UiAssemblies

function Select-WorkDirDialog {
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "选择 *.work 工作目录（例如: xxx.rebuilt.ps1.work）"
    $dlg.ShowNewFolderButton = $false
    $result = $dlg.ShowDialog()
    if ($result -ne [System.Windows.Forms.DialogResult]::OK) { return $null }
    return $dlg.SelectedPath
}

function Get-RoundList {
    param([Parameter(Mandatory)][string]$Dir)

    $items = @()
    if (-not (Test-Path -LiteralPath $Dir)) { return @() }

    Get-ChildItem -LiteralPath $Dir -Filter 'round*.execution.log' -File -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.Name -match '^round(\d+)\.execution\.log$') {
            $n = [int]$Matches[1]
            $items += $n
        }
    }

    return @($items | Sort-Object -Unique)
}

function Try-Load-ReportSummary {
    param(
        [Parameter(Mandatory)][string]$ReportPath
    )

    if (-not (Test-Path -LiteralPath $ReportPath)) { return $null }
    try {
        $r = Get-Content -LiteralPath $ReportPath -Raw -ErrorAction Stop | ConvertFrom-Json -Depth 30
        return [PSCustomObject]@{
            CandidateCount = $r.CandidateCount
            AppliedCount   = $r.AppliedCount
            SkippedCount   = $r.SkippedCount
        }
    } catch {
        return $null
    }
}

function Select-RoundDialog {
    param(
        [Parameter(Mandatory)][string]$Dir
    )

    $rounds = Get-RoundList -Dir $Dir
    if ($rounds.Count -eq 0) {
        [System.Windows.MessageBox]::Show("目录中未找到 round*.execution.log: `n$Dir", "未找到 Round", "OK", "Warning") | Out-Null
        return $null
    }

    # 构造显示项（带 report 摘要）
    $rows = foreach ($n in $rounds) {
        $label = '{0:d2}' -f $n
        $reportPath = Join-Path $Dir ("round{0}.report.json" -f $label)
        $sum = Try-Load-ReportSummary -ReportPath $reportPath
        [PSCustomObject]@{
            Round  = $n
            Label  = "Round $label"
            Report = if ($sum) { "candidates=$($sum.CandidateCount) applied=$($sum.AppliedCount) skipped=$($sum.SkippedCount)" } else { "(no report)" }
        }
    }

    [xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="选择 Round" Height="360" Width="520"
        WindowStartupLocation="CenterScreen" ResizeMode="CanResize">
  <Grid Margin="10">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <TextBlock Grid.Row="0" Text="请选择要复盘的 round：" Margin="0,0,0,8"/>

    <DataGrid Grid.Row="1" Name="RoundGrid" AutoGenerateColumns="False" IsReadOnly="True"
              SelectionMode="Single" SelectionUnit="FullRow" HeadersVisibility="Column">
      <DataGrid.Columns>
        <DataGridTextColumn Header="Round" Binding="{Binding Label}" Width="120"/>
        <DataGridTextColumn Header="Report" Binding="{Binding Report}" Width="*"/>
      </DataGrid.Columns>
    </DataGrid>

    <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0">
      <Button Name="BtnOk" Content="OK" Width="90" Margin="0,0,8,0"/>
      <Button Name="BtnCancel" Content="Cancel" Width="90" IsCancel="True"/>
    </StackPanel>
  </Grid>
</Window>
'@

    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $win = [System.Windows.Markup.XamlReader]::Load($reader)

    $grid = $win.FindName('RoundGrid')
    $btnOk = $win.FindName('BtnOk')

    $grid.ItemsSource = @($rows)
    $grid.SelectedIndex = 0

    $acceptSelection = {
        $sel = $grid.SelectedItem
        if ($sel -and $null -ne $sel.Round) {
            $win.Tag = [int]$sel.Round
            $win.DialogResult = $true
            $win.Close()
        }
    }

    $btnOk.Add_Click({
        & $acceptSelection
    })

    $grid.Add_MouseDoubleClick({
        & $acceptSelection
    })

    $grid.Add_KeyDown({
        param($sender, $e)
        if ($e.Key -eq [System.Windows.Input.Key]::Enter) {
            $e.Handled = $true
            & $acceptSelection
        }
    })

    $win.Add_ContentRendered({
        $null = $grid.Focus()
    })

    $null = $win.ShowDialog()
    if ($null -ne $win.Tag) { return [int]$win.Tag }
    return $null
}

function Get-RoundFiles {
    param(
        [Parameter(Mandatory)][string]$Dir,
        [Parameter(Mandatory)][int]$RoundNumber
    )

    $label = '{0:d2}' -f $RoundNumber
    $logPath = Join-Path $Dir ("round{0}.execution.log" -f $label)
    $reportPath = Join-Path $Dir ("round{0}.report.json" -f $label)
    $dotPath = Join-Path $Dir ("round{0}.cfg.dot" -f $label)
    $pngPath = Join-Path $Dir ("round{0}.cfg.png" -f $label)

    return [PSCustomObject]@{
        Label      = $label
        LogPath    = $logPath
        ReportPath = $reportPath
        DotPath    = $dotPath
        PngPath    = $pngPath
    }
}

function Read-LogicalLogEntries {
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "找不到 execution.log: $Path"
    }

    $lines = Get-Content -LiteralPath $Path -Encoding UTF8
    $entries = New-Object System.Collections.Generic.List[object]

    $current = $null
    foreach ($line in $lines) {
        if ($line -match '^\[(\d{2}:\d{2}:\d{2}\.\d{3})\]\s*(.*)$') {
            if ($current) { $null = $entries.Add($current) }
            $current = [PSCustomObject]@{
                Time = $Matches[1]
                Msg  = $Matches[2]
            }
        } else {
            # 多行消息（Write-ExecutionLog 的 Message 内含换行时会出现）
            if (-not $current) {
                $current = [PSCustomObject]@{ Time = $null; Msg = $line }
            } else {
                $current.Msg += "`n$line"
            }
        }
    }
    if ($current) { $null = $entries.Add($current) }

    return $entries
}

function Parse-ExecutionFrames {
    param(
        [Parameter(Mandatory)]$Entries
    )

    $frames = New-Object System.Collections.ArrayList
    $nodeToFrames = @{}

    $current = $null
    $varSection = $null  # 'Read' | 'Written'

    function Add-Frame {
        param($Frame)
        if (-not $Frame) { return }
        $Frame.RawText = ($Frame.RawLines -join "`n")
        $Frame.CodePreview = if ([string]::IsNullOrWhiteSpace($Frame.Code)) {
            ""
        } else {
            $c = $Frame.Code.Trim()
            if ($c.Length -gt 120) { $c.Substring(0, 117) + '...' } else { $c }
        }
        $Frame.Index = $frames.Count
        $null = $frames.Add($Frame)

        $nid = [string]$Frame.NodeId
        if (-not $nodeToFrames.ContainsKey($nid)) { $nodeToFrames[$nid] = New-Object System.Collections.ArrayList }
        $null = $nodeToFrames[$nid].Add([int]$Frame.Index)
    }

    foreach ($e in $Entries) {
        $msg = [string]$e.Msg

        if ($msg -match '^--- Node (\d+) \[(.+?)\] ---$') {
            Add-Frame -Frame $current
            $current = [PSCustomObject]@{
                Index           = 0
                Time            = $e.Time
                NodeId          = [int]$Matches[1]
                NodeType        = [string]$Matches[2]
                Code            = $null
                Status          = $null
                Action          = $null
                Target          = $null
                Reason          = $null
                Result          = $null
                Error           = $null
                ConditionResult = $null
                VarsRead        = [ordered]@{}
                VarsWritten     = [ordered]@{}
                Events          = New-Object System.Collections.ArrayList
                RawLines        = New-Object System.Collections.ArrayList
                RawText         = ""
                CodePreview     = ""
            }
            $varSection = $null
            continue
        }

        if (-not $current) { continue }

        # 记录原始消息（保留换行）
        $null = $current.RawLines.Add($msg)

        # VarsRead/Written 的块解析
        if ($msg -match '^\s*VarsRead:\s*$') { $varSection = 'Read'; continue }
        if ($msg -match '^\s*VarsWritten:\s*$') { $varSection = 'Written'; continue }

        if ($varSection -in @('Read', 'Written')) {
            # 注意：Read-LogicalLogEntries 会去掉时间戳后的前导空格，这里必须允许 0 个或多个空白
            if ($msg -match '^\s*(\$[^=\s]+)\s*=\s*(.*)$') {
                $vn = [string]$Matches[1]
                $vv = [string]$Matches[2]
                if ($varSection -eq 'Read') {
                    $current.VarsRead[$vn] = $vv
                } else {
                    $current.VarsWritten[$vn] = $vv
                    $null = $current.Events.Add([PSCustomObject]@{ Kind = 'VarWrite'; Name = $vn; Value = $vv; Source = 'VarsWritten' })
                }
                continue
            } else {
                # 当前行不是变量行，结束该 section，继续按普通行解析
                $varSection = $null
            }
        }

        # 常规字段
        if ($msg -match '^\s*Code:\s*(.*)$') { $current.Code = [string]$Matches[1]; continue }
        if ($msg -match '^\s*Status:\s*(.*)$') { $current.Status = [string]$Matches[1]; continue }
        if ($msg -match '^\s*Action:\s*(.*)$') { $current.Action = [string]$Matches[1]; continue }
        if ($msg -match '^\s*Target:\s*(.*)$') { $current.Target = [string]$Matches[1]; continue }
        if ($msg -match '^\s*Reason:\s*(.*)$') { $current.Reason = [string]$Matches[1]; continue }
        if ($msg -match '^\s*Result:\s*(.*)$') { $current.Result = [string]$Matches[1]; continue }
        if ($msg -match '^\s*ConditionResult:\s*(.*)$') { $current.ConditionResult = [string]$Matches[1]; continue }
        if ($msg -match '^\s*Error:\s*(.*)$') { $current.Error = [string]$Matches[1]; continue }

        # 事件：变量写入
        if ($msg -match '^\s*\[BIND\]\s+(\$[^=\s]+)\s*=\s*(.*)$') {
            $null = $current.Events.Add([PSCustomObject]@{ Kind = 'VarWrite'; Name = [string]$Matches[1]; Value = [string]$Matches[2]; Source = 'BIND' })
            continue
        }
        if ($msg -match '^\s*\[BLOCKED\]\s+Set\s+(\$[^=\s]+)\s*=\s*(.*)$') {
            $null = $current.Events.Add([PSCustomObject]@{ Kind = 'VarWrite'; Name = [string]$Matches[1]; Value = [string]$Matches[2]; Source = 'BLOCKED' })
            continue
        }
        if ($msg -match '^\s*\[RETURN\]\s+Set\s+(\$[^=\s]+)\s*=\s*(.*)$') {
            $null = $current.Events.Add([PSCustomObject]@{ Kind = 'VarWrite'; Name = [string]$Matches[1]; Value = [string]$Matches[2]; Source = 'RETURN' })
            continue
        }
        if ($msg -match '^\s*\[PROCESS\]\s+Set\s+(\$[^=\s]+)\s+from\s+(.*)$') {
            $null = $current.Events.Add([PSCustomObject]@{ Kind = 'VarWrite'; Name = [string]$Matches[1]; Value = ('[PROCESS] ' + [string]$Matches[2]); Source = 'PROCESS' })
            continue
        }

        # 事件：作用域
        if ($msg -match "^\s*\[SCOPE\]\s+Push:\s+(\w+)\s+'([^']+)'\s+\(prefix=([^,]+),\s*returnTo=(\d+),\s*endNode=(\d+)\)") {
            $null = $current.Events.Add([PSCustomObject]@{
                Kind      = 'ScopePush'
                ScopeType = [string]$Matches[1]
                ScopeName = [string]$Matches[2]
                Prefix    = [string]$Matches[3]
                ReturnTo  = [int]$Matches[4]
                EndNode   = [int]$Matches[5]
            })
            continue
        }
        if ($msg -match "^\s*\[SCOPE\]\s+Pop:\s+(\w+)\s+'([^']+)'\s+\(returnTo=(\d+)\)") {
            $null = $current.Events.Add([PSCustomObject]@{
                Kind      = 'ScopePop'
                ScopeType = [string]$Matches[1]
                ScopeName = [string]$Matches[2]
                ReturnTo  = [int]$Matches[3]
            })
            continue
        }
    }

    Add-Frame -Frame $current

    return [PSCustomObject]@{
        Frames      = @($frames)
        NodeToFrame = $nodeToFrames
    }
}

function Load-Report {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        return (Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -Depth 50)
    } catch {
        return $null
    }
}

function Get-DotPlainLayout {
    param([Parameter(Mandatory)][string]$DotPath)

    $dotCmd = Get-Command dot -ErrorAction SilentlyContinue
    if (-not $dotCmd) { return $null }
    if (-not (Test-Path -LiteralPath $DotPath)) { return $null }

    $plain = & $dotCmd.Source -Tplain $DotPath 2>$null
    if (-not $plain -or $plain.Count -eq 0) { return $null }

    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $nodes = @{}
    $graphW = $null
    $graphH = $null

    foreach ($line in $plain) {
        if ($line -match '^graph\s+\S+\s+(\S+)\s+(\S+)\s*$') {
            $graphW = [double]::Parse($Matches[1], $inv)
            $graphH = [double]::Parse($Matches[2], $inv)
            continue
        }

        # 兼容两种 plain node label:
        # 1) 旧格式: "text..."
        # 2) HTML-like: <<FONT ...>...</FONT><BR...>>
        if ($line -match '^node\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+("((?:\\.|[^"\\])*)"|<<(.+)>>)\s+.*$') {
            $id = [string]$Matches[1]
            $x = [double]::Parse($Matches[2], $inv)
            $y = [double]::Parse($Matches[3], $inv)
            $w = [double]::Parse($Matches[4], $inv)
            $h = [double]::Parse($Matches[5], $inv)

            $quotedLabel = [string]$Matches[7]
            $htmlLabel = [string]$Matches[8]
            $label = ''

            if (-not [string]::IsNullOrWhiteSpace($quotedLabel)) {
                $label = $quotedLabel -replace '\\l', "`n"
            } else {
                $label = $htmlLabel
                # 将 HTML-like label 转为可读文本（用于 tooltip）
                $label = $label -replace '<BR[^>]*>', "`n"
                $label = $label -replace '<[^>]+>', ''
                $label = [System.Net.WebUtility]::HtmlDecode($label)
            }

            $nodes[$id] = [PSCustomObject]@{
                Id    = $id
                X     = $x
                Y     = $y
                W     = $w
                H     = $h
                Label = $label
            }
        }
    }

    if ($null -eq $graphW -or $null -eq $graphH) { return $null }

    return [PSCustomObject]@{
        GraphWidth  = $graphW
        GraphHeight = $graphH
        Nodes       = $nodes
    }
}

function Build-Checkpoints {
    param(
        [Parameter(Mandatory)]$Frames,
        [Parameter(Mandatory)][int]$Interval
    )

    $cps = @()
    $stateVars = @{}
    $scopeStack = @()

    function Copy-Hashtable {
        param([hashtable]$Src)
        $dst = @{}
        foreach ($k in $Src.Keys) { $dst[$k] = $Src[$k] }
        return $dst
    }

    function Copy-ScopeStack {
        param($Stack)
        $copy = @()
        foreach ($s in @($Stack)) {
            if ($null -eq $s) { continue }
            if (-not $s.PSObject.Properties['ScopeType']) { continue }
            $copy += [PSCustomObject]@{
                ScopeType = $s.ScopeType
                ScopeName = $s.ScopeName
                Prefix    = $s.Prefix
                ReturnTo  = $s.ReturnTo
                EndNode   = $s.EndNode
            }
        }
        return $copy
    }

    function Remove-VarsByPrefix {
        param([hashtable]$Vars, [string]$Prefix)
        if ([string]::IsNullOrWhiteSpace($Prefix)) { return }
        $keys = @($Vars.Keys)
        foreach ($k in $keys) {
            if ($k -like ('$' + $Prefix + '*')) {
                $Vars.Remove($k) | Out-Null
            }
        }
    }

    function Apply-FrameEvents {
        param(
            [hashtable]$Vars,
            $ScopeStack,
            $Frame
        )

        if (-not $Frame) { return }
        foreach ($ev in @($Frame.Events)) {
            switch ($ev.Kind) {
                'ScopePush' {
                    $ScopeStack += [PSCustomObject]@{
                        ScopeType = $ev.ScopeType
                        ScopeName = $ev.ScopeName
                        Prefix    = $ev.Prefix
                        ReturnTo  = $ev.ReturnTo
                        EndNode   = $ev.EndNode
                    }
                }
                'ScopePop' {
                    if ($ScopeStack.Count -gt 0) {
                        $top = $ScopeStack[-1]
                        if ($ScopeStack.Count -eq 1) {
                            $ScopeStack = @()
                        } else {
                            $ScopeStack = @($ScopeStack[0..($ScopeStack.Count - 2)])
                        }
                        if ($top -and $top.PSObject.Properties['Prefix']) {
                            Remove-VarsByPrefix -Vars $Vars -Prefix $top.Prefix
                        }
                    }
                }
                'VarWrite' {
                    $Vars[[string]$ev.Name] = [string]$ev.Value
                }
            }
        }
        return @($ScopeStack)
    }

    # 初始 checkpoint（frame=-1）
    $cps += [PSCustomObject]@{
        Index      = -1
        Vars       = @{}
        ScopeStack = @()
    }

    for ($i = 0; $i -lt $Frames.Count; $i++) {
        $scopeStack = Apply-FrameEvents -Vars $stateVars -ScopeStack $scopeStack -Frame $Frames[$i]
        if (($i % $Interval) -eq 0) {
            $cps += [PSCustomObject]@{
                Index      = $i
                Vars       = Copy-Hashtable -Src $stateVars
                ScopeStack = Copy-ScopeStack -Stack $scopeStack
            }
        }
    }

    return $cps
}

function Get-StateAtIndex {
    param(
        [Parameter(Mandatory)]$Frames,
        [Parameter(Mandatory)]$Checkpoints,
        [Parameter(Mandatory)][int]$Index
    )

    if ($Index -lt 0) {
        return [PSCustomObject]@{ Vars = @{}; ScopeStack = @() }
    }

    $cp = $Checkpoints[0]
    foreach ($c in $Checkpoints) {
        if ($c.Index -le $Index) { $cp = $c } else { break }
    }

    $vars = @{}
    foreach ($k in $cp.Vars.Keys) { $vars[$k] = $cp.Vars[$k] }
    $scopeStack = @($cp.ScopeStack)

    function Remove-VarsByPrefix {
        param([hashtable]$Vars, [string]$Prefix)
        if ([string]::IsNullOrWhiteSpace($Prefix)) { return }
        $keys = @($Vars.Keys)
        foreach ($k in $keys) {
            if ($k -like ('$' + $Prefix + '*')) {
                $Vars.Remove($k) | Out-Null
            }
        }
    }

    for ($j = $cp.Index + 1; $j -le $Index; $j++) {
        $frame = $Frames[$j]
        foreach ($ev in @($frame.Events)) {
            switch ($ev.Kind) {
                'ScopePush' {
                    $scopeStack += [PSCustomObject]@{
                        ScopeType = $ev.ScopeType
                        ScopeName = $ev.ScopeName
                        Prefix    = $ev.Prefix
                        ReturnTo  = $ev.ReturnTo
                        EndNode   = $ev.EndNode
                    }
                }
                'ScopePop' {
                    if ($scopeStack.Count -gt 0) {
                        $top = $scopeStack[-1]
                        if ($scopeStack.Count -eq 1) {
                            $scopeStack = @()
                        } else {
                            $scopeStack = @($scopeStack[0..($scopeStack.Count - 2)])
                        }
                        if ($top -and $top.PSObject.Properties['Prefix']) {
                            Remove-VarsByPrefix -Vars $vars -Prefix $top.Prefix
                        }
                    }
                }
                'VarWrite' {
                    $vars[[string]$ev.Name] = [string]$ev.Value
                }
            }
        }
    }

    return [PSCustomObject]@{
        Vars       = $vars
        ScopeStack = $scopeStack
    }
}

function Resolve-WorkDirPath {
    param(
        [Parameter(Mandatory)][string]$Path
    )

    try {
        return (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
    } catch {
        throw "找不到 WorkDir: $Path"
    }
}

function Load-RoundSession {
    param(
        [Parameter(Mandatory)][string]$Dir,
        [Parameter(Mandatory)][int]$RoundNumber,
        [Parameter(Mandatory)][int]$CheckpointEvery
    )

    $resolvedDir = Resolve-WorkDirPath -Path $Dir
    $roundFiles = Get-RoundFiles -Dir $resolvedDir -RoundNumber $RoundNumber
    $roundEntries = Read-LogicalLogEntries -Path $roundFiles.LogPath
    $roundParsed = Parse-ExecutionFrames -Entries $roundEntries
    $roundFrames = @($roundParsed.Frames)
    if ($roundFrames.Count -eq 0) {
        throw "execution.log 中未解析到任何 Node 帧。"
    }

    $roundLayout = Get-DotPlainLayout -DotPath $roundFiles.DotPath
    $roundCheckpoints = Build-Checkpoints -Frames $roundFrames -Interval $CheckpointEvery

    return [PSCustomObject]@{
        WorkDir      = $resolvedDir
        Round        = $RoundNumber
        Files        = $roundFiles
        Entries      = $roundEntries
        Frames       = $roundFrames
        NodeToFrames = $roundParsed.NodeToFrame
        Report       = Load-Report -Path $roundFiles.ReportPath
        Layout       = $roundLayout
        Checkpoints  = $roundCheckpoints
    }
}

# ========== 主加载（WorkDir / Round） ==========

if ([string]::IsNullOrWhiteSpace($WorkDir) -and $NoUI) {
    throw "NoUI 模式下必须提供 -WorkDir。"
}

while ([string]::IsNullOrWhiteSpace($WorkDir)) {
    $WorkDir = Select-WorkDirDialog
    if (-not $WorkDir) { return }
}

while ($true) {
    try {
        $WorkDir = Resolve-WorkDirPath -Path $WorkDir
        break
    } catch {
        if ($NoUI) { throw }
        [System.Windows.MessageBox]::Show($_.Exception.Message, "无效 WorkDir", "OK", "Warning") | Out-Null
        $WorkDir = $null
        while ([string]::IsNullOrWhiteSpace($WorkDir)) {
            $WorkDir = Select-WorkDirDialog
            if (-not $WorkDir) { return }
        }
    }
}

if (-not $Round) {
    if ($NoUI) {
        $allRounds = Get-RoundList -Dir $WorkDir
        if ($allRounds.Count -eq 0) {
            throw "目录中未找到 round*.execution.log: $WorkDir"
        }
        $Round = [int]$allRounds[-1]
    } else {
        $Round = Select-RoundDialog -Dir $WorkDir
        if (-not $Round) { return }
    }
}

$session = Load-RoundSession -Dir $WorkDir -RoundNumber $Round -CheckpointEvery $CheckpointInterval
$WorkDir = $session.WorkDir
$Round = $session.Round
$files = $session.Files
$entries = $session.Entries
$frames = @($session.Frames)
$nodeToFrames = $session.NodeToFrames
$report = $session.Report
$layout = $session.Layout
$checkpoints = $session.Checkpoints

if ($NoUI) {
    [PSCustomObject]@{
        WorkDir      = $WorkDir
        Round        = $Round
        Frames       = $frames.Count
        NodesVisited = $nodeToFrames.Keys.Count
        HasReport    = [bool]$report
        HasGraph     = [bool]($layout -and (Test-Path -LiteralPath $files.PngPath))
    } | Format-List
    return
}

# ========== WPF 主界面 ==========

[xml]$mainXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="CFG 执行复盘器" Height="920" Width="1500"
        WindowStartupLocation="CenterScreen">
  <DockPanel>
    <Border DockPanel.Dock="Top" Background="#F3F3F3" BorderBrush="#DDDDDD" BorderThickness="0,0,0,1">
      <Grid Margin="10,8">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="12"/>
          <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>
        <StackPanel Orientation="Horizontal" Grid.Column="0">
          <Button Name="BtnOpenWorkDir" Content="打开文件" Width="90" Margin="0,0,8,0"/>
          <Button Name="BtnChangeRound" Content="更换 Round" Width="100" Margin="0,0,12,0"/>
          <Button Name="BtnPrev" Content="上一步" Width="90" Margin="0,0,8,0"/>
          <Button Name="BtnNext" Content="下一步" Width="90" Margin="0,0,8,0"/>
          <Button Name="BtnReset" Content="重置" Width="90" Margin="0,0,8,0"/>
          <Button Name="BtnLast" Content="执行到最后" Width="110" Margin="0,0,12,0"/>
          <TextBlock Text="CFG缩放" VerticalAlignment="Center" Margin="0,0,8,0" Foreground="#444"/>
          <Button Name="BtnZoomOut" Content="-" Width="28" Margin="0,0,6,0"/>
          <Slider Name="SldZoom" Width="140" Minimum="20" Maximum="300" Value="100" TickFrequency="10"
                  IsSnapToTickEnabled="False" SmallChange="5" LargeChange="20" VerticalAlignment="Center"
                  Margin="0,0,6,0"/>
          <Button Name="BtnZoomIn" Content="+" Width="28" Margin="0,0,6,0"/>
          <Button Name="BtnZoomReset" Content="100%" Width="60" Margin="0,0,6,0"/>
          <TextBlock Name="TxtZoomValue" Width="48" VerticalAlignment="Center" Foreground="#444"/>
        </StackPanel>
        <TextBlock Name="TxtStatus" Grid.Column="2" VerticalAlignment="Center" FontFamily="Consolas" FontSize="12" Foreground="#444"/>
      </Grid>
    </Border>

    <Grid>
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="480" MinWidth="260"/>
        <ColumnDefinition Width="6"/>
        <ColumnDefinition Width="*" MinWidth="460"/>
      </Grid.ColumnDefinitions>

      <DataGrid Grid.Column="0" Name="FramesGrid" Margin="10,10,6,10" AutoGenerateColumns="False" IsReadOnly="True"
                CanUserAddRows="False" SelectionMode="Single" SelectionUnit="FullRow"
                EnableRowVirtualization="True" EnableColumnVirtualization="True"
                FontFamily="Consolas" FontSize="12">
        <DataGrid.Columns>
          <DataGridTextColumn Header="#" Binding="{Binding Index}" Width="55"/>
          <DataGridTextColumn Header="Node" Binding="{Binding NodeId}" Width="65"/>
          <DataGridTextColumn Header="Type" Binding="{Binding NodeType}" Width="130"/>
          <DataGridTextColumn Header="Status" Binding="{Binding Status}" Width="85"/>
          <DataGridTextColumn Header="Code" Binding="{Binding CodePreview}" Width="*"/>
        </DataGrid.Columns>
      </DataGrid>

      <GridSplitter Grid.Column="1" Width="6" HorizontalAlignment="Stretch" VerticalAlignment="Stretch"
                    ResizeBehavior="PreviousAndNext" ResizeDirection="Columns" ShowsPreview="True"
                    Background="#E0E0E0"/>

      <Grid Grid.Column="2">
        <Grid.RowDefinitions>
          <RowDefinition Height="*" MinHeight="220"/>
          <RowDefinition Height="6"/>
          <RowDefinition Height="330" MinHeight="220"/>
        </Grid.RowDefinitions>

        <Border Grid.Row="0" Margin="6,10,10,6" BorderBrush="#DDDDDD" BorderThickness="1" Background="#FAFAFA">
          <ScrollViewer Name="GraphScroll" HorizontalScrollBarVisibility="Auto" VerticalScrollBarVisibility="Auto">
            <Grid Name="GraphContainer">
              <Image Name="GraphImage" Stretch="Fill"/>
              <Canvas Name="GraphOverlay" Background="Transparent"/>
            </Grid>
          </ScrollViewer>
        </Border>

        <GridSplitter Grid.Row="1" Height="6" HorizontalAlignment="Stretch" VerticalAlignment="Stretch"
                      ResizeBehavior="PreviousAndNext" ResizeDirection="Rows" ShowsPreview="True"
                      Background="#E0E0E0"/>

        <TabControl Grid.Row="2" Margin="6,6,10,10">
          <TabItem Header="当前节点">
            <Grid Margin="10">
              <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*" MinHeight="80"/>
                <RowDefinition Height="6"/>
                <RowDefinition Height="160" MinHeight="80"/>
              </Grid.RowDefinitions>
              <TextBlock Name="TxtNodeHeader" FontSize="14" FontWeight="Bold" TextWrapping="Wrap"/>
              <TextBlock Name="TxtNodeMeta" Grid.Row="1" Foreground="#555" Margin="0,6,0,8" TextWrapping="Wrap"/>
              <TextBox Name="TxtNodeRaw" Grid.Row="2" FontFamily="Consolas" FontSize="12" IsReadOnly="True"
                       VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" TextWrapping="Wrap"/>
              <GridSplitter Grid.Row="3" Height="6" HorizontalAlignment="Stretch" VerticalAlignment="Stretch"
                            ResizeBehavior="PreviousAndNext" ResizeDirection="Rows"
                            ShowsPreview="True" Background="#E0E0E0"/>
              <GroupBox Grid.Row="4" Header="当前节点还原片段">
                <Grid Margin="6">
                  <Grid.RowDefinitions>
                    <RowDefinition Height="*" MinHeight="50"/>
                    <RowDefinition Height="6"/>
                    <RowDefinition Height="120" MinHeight="70"/>
                  </Grid.RowDefinitions>
                  <DataGrid Name="NodeRecoveryGrid" Grid.Row="0" AutoGenerateColumns="False" IsReadOnly="True" CanUserAddRows="False"
                            EnableRowVirtualization="True" FontFamily="Consolas" FontSize="12">
                    <DataGrid.Columns>
                      <DataGridTextColumn Header="Original" Binding="{Binding Original}" Width="*"/>
                      <DataGridTextColumn Header="Replacement/Message" Binding="{Binding Replacement}" Width="*"/>
                      <DataGridTextColumn Header="Type" Binding="{Binding Type}" Width="130"/>
                      <DataGridTextColumn Header="状态" Binding="{Binding Status}" Width="90"/>
                      <DataGridTextColumn Header="Depth" Binding="{Binding Depth}" Width="70"/>
                      <DataGridTextColumn Header="Start" Binding="{Binding Start}" Width="70"/>
                      <DataGridTextColumn Header="End" Binding="{Binding End}" Width="70"/>
                    </DataGrid.Columns>
                  </DataGrid>
                  <GridSplitter Grid.Row="1" Height="6" HorizontalAlignment="Stretch" VerticalAlignment="Stretch"
                                ResizeBehavior="PreviousAndNext" ResizeDirection="Rows"
                                ShowsPreview="True" Background="#E0E0E0"/>
                  <Grid Grid.Row="2">
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="*" MinWidth="120"/>
                      <ColumnDefinition Width="6"/>
                      <ColumnDefinition Width="*" MinWidth="120"/>
                    </Grid.ColumnDefinitions>
                    <GroupBox Grid.Column="0" Header="Original 全文">
                      <TextBox Name="TxtRecoveryOriginalFull" IsReadOnly="True" FontFamily="Consolas" FontSize="12"
                               VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" TextWrapping="Wrap"
                               AcceptsReturn="True"/>
                    </GroupBox>
                    <GridSplitter Grid.Column="1" Width="6" HorizontalAlignment="Stretch" VerticalAlignment="Stretch"
                                  ResizeBehavior="PreviousAndNext" ResizeDirection="Columns"
                                  ShowsPreview="True" Background="#E0E0E0"/>
                    <GroupBox Grid.Column="2" Header="Replacement/Message 全文">
                      <TextBox Name="TxtRecoveryReplacementFull" IsReadOnly="True" FontFamily="Consolas" FontSize="12"
                               VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" TextWrapping="Wrap"
                               AcceptsReturn="True"/>
                    </GroupBox>
                  </Grid>
                </Grid>
              </GroupBox>
            </Grid>
          </TabItem>

          <TabItem Header="变量">
            <Grid Margin="10">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*" MinWidth="220"/>
                <ColumnDefinition Width="6"/>
                <ColumnDefinition Width="*" MinWidth="220"/>
                <ColumnDefinition Width="6"/>
                <ColumnDefinition Width="280" MinWidth="170"/>
              </Grid.ColumnDefinitions>
              <Grid.RowDefinitions>
                <RowDefinition Height="*" MinHeight="120"/>
                <RowDefinition Height="6"/>
                <RowDefinition Height="*" MinHeight="120"/>
              </Grid.RowDefinitions>

              <GroupBox Header="累计变量状态" Grid.Column="0" Grid.Row="0" Grid.RowSpan="3" Margin="0,0,8,0">
                <DataGrid Name="VarsStateGrid" AutoGenerateColumns="False" IsReadOnly="True" CanUserAddRows="False"
                          EnableRowVirtualization="True" FontFamily="Consolas" FontSize="12">
                  <DataGrid.Columns>
                    <DataGridTextColumn Header="变量" Binding="{Binding Name}" Width="150"/>
                    <DataGridTextColumn Header="值" Binding="{Binding Value}" Width="*"/>
                  </DataGrid.Columns>
                </DataGrid>
              </GroupBox>

              <GridSplitter Grid.Column="1" Grid.Row="0" Grid.RowSpan="3" Width="6"
                            HorizontalAlignment="Stretch" VerticalAlignment="Stretch"
                            ResizeBehavior="PreviousAndNext" ResizeDirection="Columns"
                            ShowsPreview="True" Background="#E0E0E0"/>

              <GroupBox Header="本节点 VarsRead" Grid.Column="2" Grid.Row="0" Margin="0,0,8,8">
                <DataGrid Name="VarsReadGrid" AutoGenerateColumns="False" IsReadOnly="True" CanUserAddRows="False"
                          EnableRowVirtualization="True" FontFamily="Consolas" FontSize="12">
                  <DataGrid.Columns>
                    <DataGridTextColumn Header="变量" Binding="{Binding Name}" Width="130"/>
                    <DataGridTextColumn Header="值" Binding="{Binding Value}" Width="*"/>
                  </DataGrid.Columns>
                </DataGrid>
              </GroupBox>

              <GridSplitter Grid.Column="2" Grid.Row="1" Height="6" HorizontalAlignment="Stretch" VerticalAlignment="Stretch"
                            ResizeBehavior="PreviousAndNext" ResizeDirection="Rows"
                            ShowsPreview="True" Background="#E0E0E0"/>

              <GroupBox Header="本节点 VarsWritten" Grid.Column="2" Grid.Row="2" Margin="0,0,8,0">
                <DataGrid Name="VarsWrittenGrid" AutoGenerateColumns="False" IsReadOnly="True" CanUserAddRows="False"
                          EnableRowVirtualization="True" FontFamily="Consolas" FontSize="12">
                  <DataGrid.Columns>
                    <DataGridTextColumn Header="变量" Binding="{Binding Name}" Width="130"/>
                    <DataGridTextColumn Header="值" Binding="{Binding Value}" Width="*"/>
                  </DataGrid.Columns>
                </DataGrid>
              </GroupBox>

              <GridSplitter Grid.Column="3" Grid.Row="0" Grid.RowSpan="3" Width="6"
                            HorizontalAlignment="Stretch" VerticalAlignment="Stretch"
                            ResizeBehavior="PreviousAndNext" ResizeDirection="Columns"
                            ShowsPreview="True" Background="#E0E0E0"/>

              <GroupBox Header="ScopeStack" Grid.Column="4" Grid.Row="0" Grid.RowSpan="3">
                <ListBox Name="ScopeList" FontFamily="Consolas" FontSize="12"/>
              </GroupBox>
            </Grid>
          </TabItem>

          <TabItem Header="Report">
            <Grid Margin="10">
              <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
              </Grid.RowDefinitions>
              <TextBlock Name="TxtReportSummary" Foreground="#555" TextWrapping="Wrap"/>
              <TabControl Grid.Row="1" Margin="0,8,0,0">
                <TabItem Header="Applied">
                  <DataGrid Name="AppliedGrid" IsReadOnly="True" CanUserAddRows="False" AutoGenerateColumns="True"
                            EnableRowVirtualization="True" FontFamily="Consolas" FontSize="12"/>
                </TabItem>
                <TabItem Header="Skipped">
                  <DataGrid Name="SkippedGrid" IsReadOnly="True" CanUserAddRows="False" AutoGenerateColumns="True"
                            EnableRowVirtualization="True" FontFamily="Consolas" FontSize="12"/>
                </TabItem>
              </TabControl>
            </Grid>
          </TabItem>
        </TabControl>
      </Grid>
    </Grid>
  </DockPanel>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $mainXaml
$window = [System.Windows.Markup.XamlReader]::Load($reader)

# 控件引用
$btnOpenWorkDir = $window.FindName('BtnOpenWorkDir')
$btnChangeRound = $window.FindName('BtnChangeRound')
$btnPrev = $window.FindName('BtnPrev')
$btnNext = $window.FindName('BtnNext')
$btnReset = $window.FindName('BtnReset')
$btnLast = $window.FindName('BtnLast')
$btnZoomOut = $window.FindName('BtnZoomOut')
$btnZoomIn = $window.FindName('BtnZoomIn')
$btnZoomReset = $window.FindName('BtnZoomReset')
$sldZoom = $window.FindName('SldZoom')
$txtZoomValue = $window.FindName('TxtZoomValue')
$txtStatus = $window.FindName('TxtStatus')
$framesGrid = $window.FindName('FramesGrid')
$graphScroll = $window.FindName('GraphScroll')
$graphContainer = $window.FindName('GraphContainer')
$graphImage = $window.FindName('GraphImage')
$graphOverlay = $window.FindName('GraphOverlay')
$txtNodeHeader = $window.FindName('TxtNodeHeader')
$txtNodeMeta = $window.FindName('TxtNodeMeta')
$txtNodeRaw = $window.FindName('TxtNodeRaw')
$nodeRecoveryGrid = $window.FindName('NodeRecoveryGrid')
$txtRecoveryOriginalFull = $window.FindName('TxtRecoveryOriginalFull')
$txtRecoveryReplacementFull = $window.FindName('TxtRecoveryReplacementFull')
$varsStateGrid = $window.FindName('VarsStateGrid')
$varsReadGrid = $window.FindName('VarsReadGrid')
$varsWrittenGrid = $window.FindName('VarsWrittenGrid')
$scopeList = $window.FindName('ScopeList')
$txtReportSummary = $window.FindName('TxtReportSummary')
$appliedGrid = $window.FindName('AppliedGrid')
$skippedGrid = $window.FindName('SkippedGrid')

function Update-ReportUi {
    param($ReportData)

    if ($ReportData) {
        $txtReportSummary.Text = "candidates=$($ReportData.CandidateCount) applied=$($ReportData.AppliedCount) skipped=$($ReportData.SkippedCount)  (Strategy=$($ReportData.OverlapStrategy))"

        [object[]]$appliedRows = @()
        [object[]]$skippedRows = @()
        if ($ReportData.Applied) {
            $appliedRows = @($ReportData.Applied)
        }
        if ($ReportData.Skipped) {
            $skippedRows = @($ReportData.Skipped)
        }

        $appliedGrid.ItemsSource = $appliedRows
        $skippedGrid.ItemsSource = $skippedRows
    } else {
        $txtReportSummary.Text = "(no report.json)"
        $appliedGrid.ItemsSource = @()
        $skippedGrid.ItemsSource = @()
    }
}

function Build-ReportNodeIndex {
    param($ReportData)

    $idx = @{}
    if (-not $ReportData) { return $idx }

    foreach ($a in @($ReportData.Applied)) {
        if ($null -eq $a -or $null -eq $a.NodeId) { continue }
        $nid = [string]$a.NodeId
        if (-not $idx.ContainsKey($nid)) { $idx[$nid] = New-Object System.Collections.ArrayList }
        $typeText = if ($a.Type -is [System.Array]) { (@($a.Type) -join '/') } else { [string]$a.Type }
        $null = $idx[$nid].Add([PSCustomObject]@{
            Status      = 'Applied'
            Type        = $typeText
            Depth       = [string]$a.Depth
            Start       = [string]$a.Start
            End         = [string]$a.End
            Original    = [string]$a.Original
            Replacement = [string]$a.Replacement
        })
    }

    foreach ($s in @($ReportData.Skipped)) {
        if ($null -eq $s -or $null -eq $s.NodeId) { continue }
        $nid = [string]$s.NodeId
        if (-not $idx.ContainsKey($nid)) { $idx[$nid] = New-Object System.Collections.ArrayList }
        $typeText = if ($s.Type -is [System.Array]) { (@($s.Type) -join '/') } else { [string]$s.Type }
        $msg = if ([string]::IsNullOrWhiteSpace([string]$s.Message)) { [string]$s.Reason } else { ([string]$s.Reason + ': ' + [string]$s.Message) }
        $null = $idx[$nid].Add([PSCustomObject]@{
            Status      = 'Skipped'
            Type        = $typeText
            Depth       = [string]$s.Depth
            Start       = [string]$s.Start
            End         = [string]$s.End
            Original    = ''
            Replacement = $msg
        })
    }

    return $idx
}

function Get-NodeRecoveryRows {
    param(
        [hashtable]$Index,
        [string]$NodeId
    )

    if (-not $NodeId) { return @() }
    if (-not $Index) { return @() }
    if (-not $Index.ContainsKey($NodeId)) { return @() }

    return @($Index[$NodeId] | Sort-Object @{ Expression = { $_.Status }; Descending = $false }, @{ Expression = { [int]($_.Start) }; Descending = $false }, @{ Expression = { [int]($_.Depth) }; Descending = $false })
}

function Set-RecoveryDetailText {
    param($Row)

    if ($null -eq $Row) {
        $txtRecoveryOriginalFull.Text = ""
        $txtRecoveryReplacementFull.Text = ""
        return
    }

    $txtRecoveryOriginalFull.Text = [string]$Row.Original
    $txtRecoveryReplacementFull.Text = [string]$Row.Replacement
}

function Set-NodeRecoveryRows {
    param($Rows)

    $allRows = @($Rows)
    $script:SuppressRecoverySelection = $true
    try {
        $nodeRecoveryGrid.ItemsSource = $allRows
        if ($allRows.Count -gt 0) {
            $nodeRecoveryGrid.SelectedIndex = 0
            Set-RecoveryDetailText -Row $allRows[0]
        } else {
            $nodeRecoveryGrid.SelectedIndex = -1
            Set-RecoveryDetailText -Row $null
        }
    } finally {
        $script:SuppressRecoverySelection = $false
    }
}

# 数据绑定
$framesGrid.ItemsSource = @($frames)
Update-ReportUi -ReportData $report
$script:reportNodeIndex = Build-ReportNodeIndex -ReportData $report

# 图加载与交互热区
$nodeRectsDip = @{}   # nodeId -> {Left;Top;Width;Height}
$nodeHotRects = @{}   # nodeId -> Rectangle
$highlightRect = New-Object System.Windows.Shapes.Rectangle
$highlightRect.Stroke = [System.Windows.Media.Brushes]::Red
$highlightRect.StrokeThickness = 4
$highlightRect.Fill = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(28, 255, 0, 0))
$highlightRect.Visibility = 'Collapsed'
$highlightRect.IsHitTestVisible = $false
[System.Windows.Controls.Canvas]::SetZIndex($highlightRect, 1000)
$graphOverlay.Children.Add($highlightRect) | Out-Null

$script:CurrentIndex = 0
$script:SuppressGrid = $false
$script:GraphZoom = 1.0
$script:SyncingZoomUi = $false
$script:SuppressRecoverySelection = $false

function Reset-GraphOverlayState {
    $nodeRectsDip.Clear()
    $nodeHotRects.Clear()
    $graphOverlay.Children.Clear()
    $graphOverlay.Children.Add($highlightRect) | Out-Null
    $highlightRect.Visibility = 'Collapsed'
}

function Set-GraphPlaceholder {
    param(
        [string]$Message,
        [switch]$ClearImage
    )

    if ($ClearImage) {
        $graphImage.Source = $null
        $graphImage.Width = [double]::NaN
        $graphImage.Height = [double]::NaN
        $graphContainer.Width = [double]::NaN
        $graphContainer.Height = [double]::NaN
    }

    Reset-GraphOverlayState
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text = $Message
    $tb.Margin = '20'
    $tb.FontSize = 14
    $tb.Foreground = [System.Windows.Media.Brushes]::Gray
    $graphOverlay.Children.Add($tb) | Out-Null
}

function Get-GraphSourceSizeDip {
    if (-not $graphImage.Source) { return $null }

    $w = [double]$graphImage.Source.Width
    $h = [double]$graphImage.Source.Height
    if ($w -le 0 -or $h -le 0) {
        if ($graphImage.Source.PSObject.Properties['PixelWidth'] -and $graphImage.Source.PSObject.Properties['PixelHeight']) {
            $w = [double]$graphImage.Source.PixelWidth
            $h = [double]$graphImage.Source.PixelHeight
        }
    }
    if ($w -le 0 -or $h -le 0) { return $null }

    return [PSCustomObject]@{
        Width  = $w
        Height = $h
    }
}

function Apply-GraphZoom {
    $size = Get-GraphSourceSizeDip
    if (-not $size) { return }

    $targetW = [Math]::Max(1.0, $size.Width * $script:GraphZoom)
    $targetH = [Math]::Max(1.0, $size.Height * $script:GraphZoom)

    $graphImage.Width = $targetW
    $graphImage.Height = $targetH
    $graphContainer.Width = $targetW
    $graphContainer.Height = $targetH
    $graphOverlay.Width = $targetW
    $graphOverlay.Height = $targetH

    Rebuild-GraphHotspots

    if ($script:CurrentIndex -ge 0 -and $script:CurrentIndex -lt $frames.Count) {
        $cur = $frames[$script:CurrentIndex]
        if ($cur -and $null -ne $cur.NodeId) {
            Update-Highlight -NodeId ([string]$cur.NodeId)
        }
    }
}

function Set-GraphZoom {
    param(
        [Parameter(Mandatory)][double]$Zoom,
        [switch]$FromSlider
    )

    if ($Zoom -lt 0.2) { $Zoom = 0.2 }
    if ($Zoom -gt 3.0) { $Zoom = 3.0 }
    $script:GraphZoom = $Zoom

    if (-not $FromSlider) {
        $script:SyncingZoomUi = $true
        try {
            $sldZoom.Value = $Zoom * 100.0
        } finally {
            $script:SyncingZoomUi = $false
        }
    }

    $txtZoomValue.Text = ('{0:0}%' -f ($script:GraphZoom * 100.0))
    Apply-GraphZoom
}

function Ensure-GraphLoaded {
    Reset-GraphOverlayState

    if (-not (Test-Path -LiteralPath $files.PngPath)) {
        Set-GraphPlaceholder -Message "(未找到 round$($files.Label).cfg.png)" -ClearImage
        return $false
    }

    try {
        $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
        $bmp.BeginInit()
        $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bmp.UriSource = [Uri](Resolve-Path -LiteralPath $files.PngPath).ProviderPath
        $bmp.EndInit()
        $graphImage.Source = $bmp
    } catch {
        Set-GraphPlaceholder -Message "(加载 cfg.png 失败: $_)" -ClearImage
        return $false
    }

    if (-not $layout) {
        Set-GraphPlaceholder -Message "(未找到 cfg.dot 或无法运行 dot -Tplain，节点图不可交互)"
        return $true
    }

    return $true
}

[void](Ensure-GraphLoaded)

function Rebuild-GraphHotspots {
    if (-not $layout) { return }
    if (-not $graphImage.Source) { return }

    $graphW = [double]$layout.GraphWidth
    $graphH = [double]$layout.GraphHeight

    $imgW = if ($graphImage.Width -gt 0) { [double]$graphImage.Width } else { [double]$graphImage.ActualWidth }
    $imgH = if ($graphImage.Height -gt 0) { [double]$graphImage.Height } else { [double]$graphImage.ActualHeight }
    if ($imgW -le 0 -or $imgH -le 0) { return }

    # Canvas 与 Image 对齐
    $graphOverlay.Width = $imgW
    $graphOverlay.Height = $imgH

    $sx = $imgW / $graphW
    $sy = $imgH / $graphH

    $graphOverlay.Children.Clear()
    $graphOverlay.Children.Add($highlightRect) | Out-Null
    $highlightRect.Visibility = 'Collapsed'
    $nodeRectsDip.Clear()
    $nodeHotRects.Clear()

    foreach ($kv in $layout.Nodes.GetEnumerator()) {
        $n = $kv.Value
        $id = [string]$n.Id

        $left = ($n.X - ($n.W / 2.0)) * $sx
        $top = ($graphH - ($n.Y + ($n.H / 2.0))) * $sy
        $w = $n.W * $sx
        $h = $n.H * $sy

        $nodeRectsDip[$id] = [PSCustomObject]@{
            Left   = $left
            Top    = $top
            Width  = $w
            Height = $h
        }

        $rect = New-Object System.Windows.Shapes.Rectangle
        $rect.Fill = [System.Windows.Media.Brushes]::Transparent
        $rect.StrokeThickness = 0
        $rect.Tag = $id
        $label = $n.Label
        $visits = if ($nodeToFrames.ContainsKey($id)) { $nodeToFrames[$id].Count } else { 0 }
        $rect.ToolTip = "Node $id`nVisits: $visits`n---`n$label"
        $rect.Add_MouseEnter({ $this.StrokeThickness = 1; $this.Stroke = [System.Windows.Media.Brushes]::DodgerBlue })
        $rect.Add_MouseLeave({ $this.StrokeThickness = 0 })
        $rect.Add_MouseLeftButtonUp({
            $nid = [string]$this.Tag
            if (-not $nodeToFrames.ContainsKey($nid)) { return }
            $list = $nodeToFrames[$nid]
            $cur = $script:CurrentIndex
            $next = $null
            foreach ($i in $list) { if ($i -gt $cur) { $next = $i; break } }
            if ($null -eq $next) { $next = $list[0] }
            Set-CurrentIndex -Index $next -FromGrid:$false
        })

        $nodeHotRects[$id] = $rect
        [System.Windows.Controls.Canvas]::SetZIndex($rect, 10)
        $graphOverlay.Children.Add($rect) | Out-Null

        $rect.Width = $w
        $rect.Height = $h
        [System.Windows.Controls.Canvas]::SetLeft($rect, $left)
        [System.Windows.Controls.Canvas]::SetTop($rect, $top)
    }
}

$graphImage.Add_Loaded({
    Rebuild-GraphHotspots
    if ($script:CurrentIndex -ge 0 -and $script:CurrentIndex -lt $frames.Count) {
        $cur = $frames[$script:CurrentIndex]
        if ($cur -and $null -ne $cur.NodeId) {
            Update-Highlight -NodeId ([string]$cur.NodeId)
        }
    }
})
$graphImage.Add_SizeChanged({
    Rebuild-GraphHotspots
    if ($script:CurrentIndex -ge 0 -and $script:CurrentIndex -lt $frames.Count) {
        $cur = $frames[$script:CurrentIndex]
        if ($cur -and $null -ne $cur.NodeId) {
            Update-Highlight -NodeId ([string]$cur.NodeId)
        }
    }
})

# 确保首屏渲染后一定完成一次热区/高亮同步（避免 Loaded 事件错过导致红框消失）
$window.Add_ContentRendered({
    Rebuild-GraphHotspots
    if ($nodeRectsDip.Count -eq 0) {
        # 某些机器上首次渲染时图片尺寸尚未稳定，强制再尝试一次
        Start-Sleep -Milliseconds 80
        Rebuild-GraphHotspots
    }
    if ($script:CurrentIndex -ge 0 -and $script:CurrentIndex -lt $frames.Count) {
        $cur = $frames[$script:CurrentIndex]
        if ($cur -and $null -ne $cur.NodeId) {
            Update-Highlight -NodeId ([string]$cur.NodeId)
        }
    }
})

# ========== UI 更新 ==========

function Convert-VarTableForGrid {
    param([hashtable]$Vars)
    $rows = @()
    foreach ($k in @($Vars.Keys | Sort-Object)) {
        $rows += [PSCustomObject]@{ Name = $k; Value = [string]$Vars[$k] }
    }
    return $rows
}

function Convert-VarHashForGrid {
    param($VarHash)
    $rows = @()
    foreach ($k in @($VarHash.Keys | Sort-Object)) {
        $rows += [PSCustomObject]@{ Name = $k; Value = [string]$VarHash[$k] }
    }
    return $rows
}

function Update-Highlight {
    param([string]$NodeId)

    if (-not $NodeId) { $highlightRect.Visibility = 'Collapsed'; return }
    if (-not $nodeRectsDip.ContainsKey($NodeId)) { $highlightRect.Visibility = 'Collapsed'; return }

    $r = $nodeRectsDip[$NodeId]
    $highlightRect.Width = $r.Width
    $highlightRect.Height = $r.Height
    [System.Windows.Controls.Canvas]::SetLeft($highlightRect, $r.Left)
    [System.Windows.Controls.Canvas]::SetTop($highlightRect, $r.Top)
    $highlightRect.Visibility = 'Visible'

    # 尝试滚动到中间
    try {
        $centerX = $r.Left + ($r.Width / 2.0)
        $centerY = $r.Top + ($r.Height / 2.0)
        $targetX = [Math]::Max(0, $centerX - ($graphScroll.ViewportWidth / 2.0))
        $targetY = [Math]::Max(0, $centerY - ($graphScroll.ViewportHeight / 2.0))
        $graphScroll.ScrollToHorizontalOffset($targetX)
        $graphScroll.ScrollToVerticalOffset($targetY)
    } catch {
        # 忽略滚动错误
    }
}

function Set-CurrentIndex {
    param(
        [Parameter(Mandatory)][int]$Index,
        [switch]$FromGrid
    )

    if ($frames.Count -le 0) {
        $txtStatus.Text = "WorkDir=$WorkDir | Round=$($files.Label) | (无可用帧)"
        $txtNodeHeader.Text = ""
        $txtNodeMeta.Text = ""
        $txtNodeRaw.Text = ""
        Set-NodeRecoveryRows -Rows @()
        $varsReadGrid.ItemsSource = @()
        $varsWrittenGrid.ItemsSource = @()
        $varsStateGrid.ItemsSource = @()
        $scopeList.ItemsSource = @()
        Update-Highlight -NodeId $null
        $btnPrev.IsEnabled = $false
        $btnNext.IsEnabled = $false
        return
    }

    if ($Index -lt 0) { $Index = 0 }
    if ($Index -ge $frames.Count) { $Index = $frames.Count - 1 }
    $script:CurrentIndex = $Index

    $frame = $frames[$Index]
    $nid = [string]$frame.NodeId

    $txtStatus.Text = "WorkDir=$WorkDir | Round=$($files.Label) | Frame=$Index/$($frames.Count-1) | Node=$nid [$($frame.NodeType)] | Status=$($frame.Status)"

    $txtNodeHeader.Text = "Node $nid [$($frame.NodeType)]"
    $txtNodeMeta.Text = "Time=$($frame.Time)  Status=$($frame.Status)  Action=$($frame.Action)  Target=$($frame.Target)  Reason=$($frame.Reason)  Result=$($frame.Result)  Condition=$($frame.ConditionResult)"
    # 当前节点页编辑框仅展示代码本体，不重复展示状态/变量等信息
    $txtNodeRaw.Text = [string]$frame.Code
    Set-NodeRecoveryRows -Rows @(Get-NodeRecoveryRows -Index $reportNodeIndex -NodeId $nid)

    $varsReadGrid.ItemsSource = @(Convert-VarHashForGrid -VarHash $frame.VarsRead)
    $varsWrittenGrid.ItemsSource = @(Convert-VarHashForGrid -VarHash $frame.VarsWritten)

    $state = Get-StateAtIndex -Frames $frames -Checkpoints $checkpoints -Index $Index
    $varsStateGrid.ItemsSource = @(Convert-VarTableForGrid -Vars $state.Vars)
    $scopeList.ItemsSource = @($state.ScopeStack | ForEach-Object { "$($_.ScopeType) $($_.ScopeName) (prefix=$($_.Prefix))" })

    Update-Highlight -NodeId $nid

    # 更新按钮可用性
    $btnPrev.IsEnabled = ($Index -gt 0)
    $btnNext.IsEnabled = ($Index -lt ($frames.Count - 1))

    if (-not $FromGrid) {
        $script:SuppressGrid = $true
        try {
            $framesGrid.SelectedIndex = $Index
            $framesGrid.ScrollIntoView($framesGrid.SelectedItem) | Out-Null
        } finally {
            $script:SuppressGrid = $false
        }
    }
}

function Load-SessionIntoUi {
    param(
        [Parameter(Mandatory)][string]$TargetWorkDir,
        [Parameter(Mandatory)][int]$TargetRound
    )

    $newSession = Load-RoundSession -Dir $TargetWorkDir -RoundNumber $TargetRound -CheckpointEvery $CheckpointInterval

    $script:WorkDir = $newSession.WorkDir
    $script:Round = $newSession.Round
    $script:files = $newSession.Files
    $script:entries = $newSession.Entries
    $script:frames = @($newSession.Frames)
    $script:nodeToFrames = $newSession.NodeToFrames
    $script:report = $newSession.Report
    $script:layout = $newSession.Layout
    $script:checkpoints = $newSession.Checkpoints

    $window.Title = "CFG 执行复盘器 - Round $($files.Label)"

    $script:SuppressGrid = $true
    try {
        $framesGrid.ItemsSource = @($frames)
        $framesGrid.SelectedIndex = -1
    } finally {
        $script:SuppressGrid = $false
    }

    Update-ReportUi -ReportData $report
    $script:reportNodeIndex = Build-ReportNodeIndex -ReportData $report
    [void](Ensure-GraphLoaded)
    Set-GraphZoom -Zoom $script:GraphZoom

    Set-CurrentIndex -Index 0 -FromGrid:$false
}

# 左侧列表点击跳转
$framesGrid.Add_SelectionChanged({
    if ($script:SuppressGrid) { return }
    $sel = $framesGrid.SelectedItem
    if ($sel -and $null -ne $sel.Index) {
        Set-CurrentIndex -Index ([int]$sel.Index) -FromGrid:$true
    }
})

# 当前节点还原片段：选中项联动全文预览
$nodeRecoveryGrid.Add_SelectionChanged({
    if ($script:SuppressRecoverySelection) { return }
    Set-RecoveryDetailText -Row $nodeRecoveryGrid.SelectedItem
})

# 当前节点还原片段：右键复制完整值
$nodeRecoveryContextMenu = New-Object System.Windows.Controls.ContextMenu
$miCopyRecoveryOriginal = New-Object System.Windows.Controls.MenuItem
$miCopyRecoveryOriginal.Header = '复制 Original'
$miCopyRecoveryOriginal.Add_Click({
    $row = $nodeRecoveryGrid.SelectedItem
    $text = if ($row) { [string]$row.Original } else { [string]$txtRecoveryOriginalFull.Text }
    try { [System.Windows.Clipboard]::SetText($text) } catch {}
})
$miCopyRecoveryReplacement = New-Object System.Windows.Controls.MenuItem
$miCopyRecoveryReplacement.Header = '复制 Replacement/Message'
$miCopyRecoveryReplacement.Add_Click({
    $row = $nodeRecoveryGrid.SelectedItem
    $text = if ($row) { [string]$row.Replacement } else { [string]$txtRecoveryReplacementFull.Text }
    try { [System.Windows.Clipboard]::SetText($text) } catch {}
})
[void]$nodeRecoveryContextMenu.Items.Add($miCopyRecoveryOriginal)
[void]$nodeRecoveryContextMenu.Items.Add($miCopyRecoveryReplacement)
$nodeRecoveryGrid.ContextMenu = $nodeRecoveryContextMenu

# 按钮行为
$btnOpenWorkDir.Add_Click({
    $newDir = Select-WorkDirDialog
    if (-not $newDir) { return }

    try {
        $newDir = Resolve-WorkDirPath -Path $newDir
    } catch {
        [System.Windows.MessageBox]::Show($_.Exception.Message, "打开文件失败", "OK", "Warning") | Out-Null
        return
    }

    $newRound = Select-RoundDialog -Dir $newDir
    if (-not $newRound) { return }

    try {
        Load-SessionIntoUi -TargetWorkDir $newDir -TargetRound $newRound
    } catch {
        [System.Windows.MessageBox]::Show("加载失败: $($_.Exception.Message)", "打开文件失败", "OK", "Error") | Out-Null
    }
})

$btnChangeRound.Add_Click({
    $newRound = Select-RoundDialog -Dir $WorkDir
    if (-not $newRound) { return }

    try {
        Load-SessionIntoUi -TargetWorkDir $WorkDir -TargetRound $newRound
    } catch {
        [System.Windows.MessageBox]::Show("切换 round 失败: $($_.Exception.Message)", "更换 Round 失败", "OK", "Error") | Out-Null
    }
})

$btnPrev.Add_Click({ Set-CurrentIndex -Index ($script:CurrentIndex - 1) -FromGrid:$false })
$btnNext.Add_Click({ Set-CurrentIndex -Index ($script:CurrentIndex + 1) -FromGrid:$false })
$btnReset.Add_Click({ Set-CurrentIndex -Index 0 -FromGrid:$false })
$btnLast.Add_Click({ Set-CurrentIndex -Index ($frames.Count - 1) -FromGrid:$false })

$sldZoom.Add_ValueChanged({
    if ($script:SyncingZoomUi) { return }
    Set-GraphZoom -Zoom ($sldZoom.Value / 100.0) -FromSlider
})
$btnZoomOut.Add_Click({ Set-GraphZoom -Zoom ($script:GraphZoom - 0.1) })
$btnZoomIn.Add_Click({ Set-GraphZoom -Zoom ($script:GraphZoom + 0.1) })
$btnZoomReset.Add_Click({ Set-GraphZoom -Zoom 1.0 })

# 初始化
$window.Title = "CFG 执行复盘器 - Round $($files.Label)"
Set-GraphZoom -Zoom ($sldZoom.Value / 100.0)
$framesGrid.SelectedIndex = 0
Set-CurrentIndex -Index 0 -FromGrid:$false

$null = $window.ShowDialog()
