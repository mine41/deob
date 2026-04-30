<#
.SYNOPSIS
  Replay a recorded CFG execution round in a WPF viewer.

.DESCRIPTION
  - Provides Previous, Next, Reset, and Run To End controls.
  - Shows node-visit frames in chronological order on the left.
  - Displays the CFG image with clickable hit regions and current-node highlight.
  - Shows node details, accumulated variable state, per-node variable access,
    and round report summaries.

  Notes:
  - Windows with WPF is required.
  - The script is best launched with the intended host (powershell.exe or pwsh)
    and -Sta; it can relaunch itself when needed.
  - Interactive graph hit testing depends on Graphviz dot -Tplain.

.EXAMPLE
  powershell.exe -NoProfile -Sta -File .\Review-RoundReplay.Wpf.ps1

.EXAMPLE
  powershell.exe -NoProfile -Sta -File .\Review-RoundReplay.Wpf.ps1 -WorkDir .\in\in.rebuilt.ps1.work -Round 1
#>

[CmdletBinding()]
param(
    [string]$WorkDir,
    [int]$Round,
    [ValidateRange(10, 5000)]
    [int]$CheckpointInterval = 200,
    [switch]$NoUI
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-IsWindowsHost {
    return ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT)
}

function Get-CurrentPowerShellExecutablePath {
    $exe = $null

    try {
        $p = Get-Process -Id $PID -ErrorAction Stop
        if ($p.Path) { $exe = [string]$p.Path }
    } catch {
        $exe = $null
    }

    if (-not [string]::IsNullOrWhiteSpace($exe) -and (Test-Path -LiteralPath $exe)) {
        return $exe
    }

    foreach ($candidate in @((Join-Path $PSHOME 'powershell.exe'), (Join-Path $PSHOME 'pwsh.exe')) | Select-Object -Unique) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }

    $commandName = if ($PSVersionTable.PSEdition -eq 'Desktop') { 'powershell.exe' } else { 'pwsh' }
    $cmd = Get-Command $commandName -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd -and $cmd.Source) { return [string]$cmd.Source }

    return $null
}

function Get-ObjectPropertyValue {
    param(
        $Object,
        [Parameter(Mandatory)][string]$Name,
        $Default = $null
    )

    if ($null -eq $Object) { return $Default }

    if ($Object -is [hashtable]) {
        if ($Object.ContainsKey($Name)) { return $Object[$Name] }
        return $Default
    }

    $prop = $Object.PSObject.Properties[$Name]
    if ($null -ne $prop) { return $prop.Value }

    return $Default
}

function Get-ReportHostDisplay {
    param($ReportData)

    if (-not $ReportData) { return $null }
    $hostInfo = Get-ObjectPropertyValue -Object $ReportData -Name 'HostInfo' -Default $null
    if ($null -eq $hostInfo) { return $null }

    $display = Get-ObjectPropertyValue -Object $hostInfo -Name 'Display' -Default $null
    if (-not [string]::IsNullOrWhiteSpace([string]$display)) {
        return [string]$display
    }

    $parts = @()
    $edition = Get-ObjectPropertyValue -Object $hostInfo -Name 'Edition' -Default $null
    $version = Get-ObjectPropertyValue -Object $hostInfo -Name 'Version' -Default $null
    if ($edition) { $parts += [string]$edition }
    if ($version) { $parts += [string]$version }
    $text = ($parts -join ' ').Trim()
    $processName = Get-ObjectPropertyValue -Object $hostInfo -Name 'ProcessName' -Default $null
    if ($processName) {
        $text = "$text [$processName]"
    }
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    return $text
}

if (-not (Test-IsWindowsHost)) {
    throw "该脚本仅支持 Windows（需要 WPF）。"
}

function Restart-SelfAsStaIfNeeded {
    param(
        [hashtable]$BoundParams
    )

    if ($NoUI) { return }

    $apt = [System.Threading.Thread]::CurrentThread.ApartmentState
    if ($apt -eq [System.Threading.ApartmentState]::STA) { return }

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

    $exe = Get-CurrentPowerShellExecutablePath
    if (-not $exe) {
        throw "当前线程不是 STA，且无法定位当前 PowerShell 宿主。请用同一宿主加 -Sta 重新启动。"
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

$uiLocPath = Join-Path $PSScriptRoot 'Ui-Localization.ps1'
if (-not (Test-Path -LiteralPath $uiLocPath)) {
    throw "缺少文件: $uiLocPath"
}
. $uiLocPath

$script:UiLanguage = 'zh-CN'
if (-not $NoUI) {
    $selectedLanguage = Show-LanguageSelectionDialog
    if ([string]::IsNullOrWhiteSpace([string]$selectedLanguage)) { return }
    $script:UiLanguage = [string]$selectedLanguage
}
$script:UiText = Get-UiTextPack -Scope 'Replay' -Language $script:UiLanguage

function L {
    param(
        [Parameter(Mandatory)][string]$Key,
        [object[]]$FormatArgs = @()
    )

    return Get-UiText -Pack $script:UiText -Key $Key -Args $FormatArgs
}

function Select-WorkDirDialog {
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = L 'folder.description'
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

    if ($items.Count -eq 0 -and (Test-Path -LiteralPath (Join-Path $Dir 'debug.execution.log'))) {
        $items += 1
    }

    return @($items | Sort-Object -Unique)
}

function Try-Load-ReportSummary {
    param(
        [Parameter(Mandatory)][string]$ReportPath
    )

    if (-not (Test-Path -LiteralPath $ReportPath)) { return $null }
    try {
        $r = Get-Content -LiteralPath $ReportPath -Raw -ErrorAction Stop | ConvertFrom-Json
        $hostDisplay = Get-ReportHostDisplay -ReportData $r
        return [PSCustomObject]@{
            CandidateCount = Get-ObjectPropertyValue -Object $r -Name 'CandidateCount' -Default 0
            AppliedCount   = Get-ObjectPropertyValue -Object $r -Name 'AppliedCount' -Default 0
            SkippedCount   = Get-ObjectPropertyValue -Object $r -Name 'SkippedCount' -Default 0
            HostDisplay    = $hostDisplay
        }
    } catch {
        return $null
    }
}

function Select-RoundDialog {
    param(
        [Parameter(Mandatory)][string]$Dir
    )

    $rounds = @(Get-RoundList -Dir $Dir)
    if ($rounds.Count -eq 0) {
        [System.Windows.MessageBox]::Show((L 'message.no_round_found' @("`n", $Dir)), (L 'title.no_round_found'), "OK", "Warning") | Out-Null
        return $null
    }

    $rows = foreach ($n in $rounds) {
        $label = '{0:d2}' -f $n
        $reportPath = Join-Path $Dir ("round{0}.report.json" -f $label)
        $sum = Try-Load-ReportSummary -ReportPath $reportPath
        $sumHostDisplay = $null
        if ($sum -and $sum.PSObject.Properties['HostDisplay']) {
            $sumHostDisplay = [string]$sum.HostDisplay
        }
        [PSCustomObject]@{
            Round  = $n
            Label  = "Round $label"
            Report = if ($sum) {
                $hostSuffix = if (-not [string]::IsNullOrWhiteSpace($sumHostDisplay)) { L 'round.report_host_suffix' @($sumHostDisplay) } else { '' }
                L 'round.report_summary' @($sum.CandidateCount, $sum.AppliedCount, $sum.SkippedCount, $hostSuffix)
            } else {
                L 'report.none_short'
            }
        }
    }

    $xamlText = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="__LOC_XAML_ROUND_PICKER_WINDOW_TITLE__" Height="360" Width="520"
        WindowStartupLocation="CenterScreen" ResizeMode="CanResize">
  <Grid Margin="10">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <TextBlock Grid.Row="0" Text="__LOC_XAML_ROUND_PICKER_PROMPT__" Margin="0,0,0,8"/>

    <DataGrid Grid.Row="1" Name="RoundGrid" AutoGenerateColumns="False" IsReadOnly="True"
              SelectionMode="Single" SelectionUnit="FullRow" HeadersVisibility="Column">
      <DataGrid.Columns>
        <DataGridTextColumn Header="__LOC_XAML_ROUND_PICKER_ROUND_HEADER__" Binding="{Binding Label}" Width="120"/>
        <DataGridTextColumn Header="__LOC_XAML_ROUND_PICKER_REPORT_HEADER__" Binding="{Binding Report}" Width="*"/>
      </DataGrid.Columns>
    </DataGrid>

    <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0">
      <Button Name="BtnOk" Content="__LOC_XAML_ROUND_PICKER_BTN_OK__" Width="90" Margin="0,0,8,0"/>
      <Button Name="BtnCancel" Content="__LOC_XAML_ROUND_PICKER_BTN_CANCEL__" Width="90" IsCancel="True"/>
    </StackPanel>
  </Grid>
</Window>
'@

    [xml]$xaml = Resolve-LocalizedTemplate -Template $xamlText -Pack $script:UiText
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

    if (-not (Test-Path -LiteralPath $logPath) -and $RoundNumber -eq 1) {
        $debugLogPath = Join-Path $Dir 'debug.execution.log'
        if (Test-Path -LiteralPath $debugLogPath) {
            return [PSCustomObject]@{
                Label          = 'debug'
                LogPath        = $debugLogPath
                ReportPath     = Join-Path $Dir 'debug.report.json'
                DotPath        = Join-Path $Dir 'debug.cfg.dot'
                PngPath        = Join-Path $Dir 'debug.cfg.png'
                IsDebugSession = $true
            }
        }
    }

    return [PSCustomObject]@{
        Label          = $label
        LogPath        = $logPath
        ReportPath     = $reportPath
        DotPath        = $dotPath
        PngPath        = $pngPath
        IsDebugSession = $false
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

        $null = $current.RawLines.Add($msg)

        if ($msg -match '^\s*VarsRead:\s*$') { $varSection = 'Read'; continue }
        if ($msg -match '^\s*VarsWritten:\s*$') { $varSection = 'Written'; continue }

        if ($varSection -in @('Read', 'Written')) {
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
                $varSection = $null
            }
        }

        if ($msg -match '^\s*Code:\s*(.*)$') { $current.Code = [string]$Matches[1]; continue }
        if ($msg -match '^\s*Status:\s*(.*)$') { $current.Status = [string]$Matches[1]; continue }
        if ($msg -match '^\s*Action:\s*(.*)$') { $current.Action = [string]$Matches[1]; continue }
        if ($msg -match '^\s*Target:\s*(.*)$') { $current.Target = [string]$Matches[1]; continue }
        if ($msg -match '^\s*Reason:\s*(.*)$') { $current.Reason = [string]$Matches[1]; continue }
        if ($msg -match '^\s*Result:\s*(.*)$') { $current.Result = [string]$Matches[1]; continue }
        if ($msg -match '^\s*ConditionResult:\s*(.*)$') { $current.ConditionResult = [string]$Matches[1]; continue }
        if ($msg -match '^\s*Error:\s*(.*)$') { $current.Error = [string]$Matches[1]; continue }

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
        $report = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json
        if ($null -eq $report) { return $null }

        $localizeItems = {
            param($Items)

            if (-not $Items) { return @() }

            return @($Items | ForEach-Object {
                    if ($null -eq $_) { return }

                    $reason = if ($_.PSObject.Properties['Reason']) { [string]$_.Reason } else { $null }
                    $row = [ordered]@{}
                    foreach ($prop in @($_.PSObject.Properties)) {
                        $value = $prop.Value
                        if ($prop.Name -eq 'Message') {
                            $value = Resolve-LocalizedDiagnosticMessage -Language $script:UiLanguage -Reason $reason -Message ([string]$prop.Value)
                        }
                        $row[$prop.Name] = $value
                    }
                    [PSCustomObject]$row
                })
        }

        $copy = [ordered]@{}
        foreach ($prop in @($report.PSObject.Properties)) {
            switch ($prop.Name) {
                'Applied' { $copy[$prop.Name] = & $localizeItems $prop.Value }
                'Skipped' { $copy[$prop.Name] = & $localizeItems $prop.Value }
                default { $copy[$prop.Name] = $prop.Value }
            }
        }

        return [PSCustomObject]$copy
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
        [System.Windows.MessageBox]::Show($_.Exception.Message, (L 'message.invalid_workdir'), "OK", "Warning") | Out-Null
        $WorkDir = $null
        while ([string]::IsNullOrWhiteSpace($WorkDir)) {
            $WorkDir = Select-WorkDirDialog
            if (-not $WorkDir) { return }
        }
    }
}

if (-not $Round) {
    if ($NoUI) {
        $allRounds = @(Get-RoundList -Dir $WorkDir)
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


$mainXamlText = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="__LOC_XAML_WINDOW_TITLE__" Height="920" Width="1500"
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
          <Button Name="BtnOpenWorkDir" Content="__LOC_XAML_BTN_OPEN_WORKDIR__" Width="90" Margin="0,0,8,0"/>
          <Button Name="BtnChangeRound" Content="__LOC_XAML_BTN_CHANGE_ROUND__" Width="100" Margin="0,0,12,0"/>
          <Button Name="BtnPrev" Content="__LOC_XAML_BTN_PREV__" Width="90" Margin="0,0,8,0"/>
          <Button Name="BtnNext" Content="__LOC_XAML_BTN_NEXT__" Width="90" Margin="0,0,8,0"/>
          <Button Name="BtnReset" Content="__LOC_XAML_BTN_RESET__" Width="90" Margin="0,0,8,0"/>
          <Button Name="BtnLast" Content="__LOC_XAML_BTN_LAST__" Width="110" Margin="0,0,12,0"/>
          <TextBlock Text="__LOC_XAML_ZOOM_LABEL__" VerticalAlignment="Center" Margin="0,0,8,0" Foreground="#444"/>
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
          <TabItem Header="__LOC_XAML_TAB_CURRENT_NODE__">
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
              <GroupBox Grid.Row="4" Header="__LOC_XAML_GROUP_CURRENT_RECOVERY__">
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
                      <DataGridTextColumn Header="__LOC_XAML_COLUMN_STATUS__" Binding="{Binding Status}" Width="90"/>
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
                    <GroupBox Grid.Column="0" Header="__LOC_XAML_GROUP_ORIGINAL_FULL__">
                      <TextBox Name="TxtRecoveryOriginalFull" IsReadOnly="True" FontFamily="Consolas" FontSize="12"
                               VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" TextWrapping="Wrap"
                               AcceptsReturn="True"/>
                    </GroupBox>
                    <GridSplitter Grid.Column="1" Width="6" HorizontalAlignment="Stretch" VerticalAlignment="Stretch"
                                  ResizeBehavior="PreviousAndNext" ResizeDirection="Columns"
                                  ShowsPreview="True" Background="#E0E0E0"/>
                    <GroupBox Grid.Column="2" Header="__LOC_XAML_GROUP_REPLACEMENT_FULL__">
                      <TextBox Name="TxtRecoveryReplacementFull" IsReadOnly="True" FontFamily="Consolas" FontSize="12"
                               VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" TextWrapping="Wrap"
                               AcceptsReturn="True"/>
                    </GroupBox>
                  </Grid>
                </Grid>
              </GroupBox>
            </Grid>
          </TabItem>

          <TabItem Header="__LOC_XAML_TAB_VARIABLES__">
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

              <GroupBox Header="__LOC_XAML_GROUP_VARIABLE_STATE__" Grid.Column="0" Grid.Row="0" Grid.RowSpan="3" Margin="0,0,8,0">
                <DataGrid Name="VarsStateGrid" AutoGenerateColumns="False" IsReadOnly="True" CanUserAddRows="False"
                          EnableRowVirtualization="True" FontFamily="Consolas" FontSize="12">
                  <DataGrid.Columns>
                    <DataGridTextColumn Header="__LOC_XAML_COLUMN_VARIABLE__" Binding="{Binding Name}" Width="150"/>
                    <DataGridTextColumn Header="__LOC_XAML_COLUMN_VALUE__" Binding="{Binding Value}" Width="*"/>
                  </DataGrid.Columns>
                </DataGrid>
              </GroupBox>

              <GridSplitter Grid.Column="1" Grid.Row="0" Grid.RowSpan="3" Width="6"
                            HorizontalAlignment="Stretch" VerticalAlignment="Stretch"
                            ResizeBehavior="PreviousAndNext" ResizeDirection="Columns"
                            ShowsPreview="True" Background="#E0E0E0"/>

              <GroupBox Header="__LOC_XAML_GROUP_VARS_READ__" Grid.Column="2" Grid.Row="0" Margin="0,0,8,8">
                <DataGrid Name="VarsReadGrid" AutoGenerateColumns="False" IsReadOnly="True" CanUserAddRows="False"
                          EnableRowVirtualization="True" FontFamily="Consolas" FontSize="12">
                  <DataGrid.Columns>
                    <DataGridTextColumn Header="__LOC_XAML_COLUMN_VARIABLE__" Binding="{Binding Name}" Width="130"/>
                    <DataGridTextColumn Header="__LOC_XAML_COLUMN_VALUE__" Binding="{Binding Value}" Width="*"/>
                  </DataGrid.Columns>
                </DataGrid>
              </GroupBox>

              <GridSplitter Grid.Column="2" Grid.Row="1" Height="6" HorizontalAlignment="Stretch" VerticalAlignment="Stretch"
                            ResizeBehavior="PreviousAndNext" ResizeDirection="Rows"
                            ShowsPreview="True" Background="#E0E0E0"/>

              <GroupBox Header="__LOC_XAML_GROUP_VARS_WRITTEN__" Grid.Column="2" Grid.Row="2" Margin="0,0,8,0">
                <DataGrid Name="VarsWrittenGrid" AutoGenerateColumns="False" IsReadOnly="True" CanUserAddRows="False"
                          EnableRowVirtualization="True" FontFamily="Consolas" FontSize="12">
                  <DataGrid.Columns>
                    <DataGridTextColumn Header="__LOC_XAML_COLUMN_VARIABLE__" Binding="{Binding Name}" Width="130"/>
                    <DataGridTextColumn Header="__LOC_XAML_COLUMN_VALUE__" Binding="{Binding Value}" Width="*"/>
                  </DataGrid.Columns>
                </DataGrid>
              </GroupBox>

              <GridSplitter Grid.Column="3" Grid.Row="0" Grid.RowSpan="3" Width="6"
                            HorizontalAlignment="Stretch" VerticalAlignment="Stretch"
                            ResizeBehavior="PreviousAndNext" ResizeDirection="Columns"
                            ShowsPreview="True" Background="#E0E0E0"/>

              <GroupBox Header="__LOC_XAML_GROUP_SCOPE_STACK__" Grid.Column="4" Grid.Row="0" Grid.RowSpan="3">
                <ListBox Name="ScopeList" FontFamily="Consolas" FontSize="12"/>
              </GroupBox>
            </Grid>
          </TabItem>

          <TabItem Header="__LOC_XAML_TAB_REPORT__">
            <Grid Margin="10">
              <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
              </Grid.RowDefinitions>
              <TextBlock Name="TxtReportSummary" Foreground="#555" TextWrapping="Wrap"/>
              <TabControl Grid.Row="1" Margin="0,8,0,0">
                <TabItem Header="__LOC_XAML_TAB_APPLIED__">
                  <DataGrid Name="AppliedGrid" IsReadOnly="True" CanUserAddRows="False" AutoGenerateColumns="True"
                            EnableRowVirtualization="True" FontFamily="Consolas" FontSize="12"/>
                </TabItem>
                <TabItem Header="__LOC_XAML_TAB_SKIPPED__">
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

[xml]$mainXaml = Resolve-LocalizedTemplate -Template $mainXamlText -Pack $script:UiText
$reader = New-Object System.Xml.XmlNodeReader $mainXaml
$window = [System.Windows.Markup.XamlReader]::Load($reader)

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
        $hostText = Get-ReportHostDisplay -ReportData $ReportData
        $hostSuffix = if ($hostText) { L 'report.summary_host_suffix' @($hostText) } else { '' }
        $candidateCount = Get-ObjectPropertyValue -Object $ReportData -Name 'CandidateCount' -Default 0
        $appliedCount = Get-ObjectPropertyValue -Object $ReportData -Name 'AppliedCount' -Default 0
        $skippedCount = Get-ObjectPropertyValue -Object $ReportData -Name 'SkippedCount' -Default 0
        $overlapStrategy = Get-ObjectPropertyValue -Object $ReportData -Name 'OverlapStrategy' -Default 'n/a'
        $txtReportSummary.Text = L 'report.summary' @($candidateCount, $appliedCount, $skippedCount, $overlapStrategy, $hostSuffix)

        [object[]]$appliedRows = @()
        [object[]]$skippedRows = @()
        $applied = Get-ObjectPropertyValue -Object $ReportData -Name 'Applied' -Default $null
        $skipped = Get-ObjectPropertyValue -Object $ReportData -Name 'Skipped' -Default $null
        if ($applied) {
            $appliedRows = @($applied)
        }
        if ($skipped) {
            $skippedRows = @($skipped)
        }

        $appliedGrid.ItemsSource = $appliedRows
        $skippedGrid.ItemsSource = $skippedRows
    } else {
        $txtReportSummary.Text = L 'report.none'
        $appliedGrid.ItemsSource = @()
        $skippedGrid.ItemsSource = @()
    }
}

function Build-ReportNodeIndex {
    param($ReportData)

    $idx = @{}
    if (-not $ReportData) { return $idx }

    foreach ($a in @(Get-ObjectPropertyValue -Object $ReportData -Name 'Applied' -Default @())) {
        $nodeId = Get-ObjectPropertyValue -Object $a -Name 'NodeId' -Default $null
        if ($null -eq $a -or $null -eq $nodeId) { continue }
        $nid = [string]$nodeId
        if (-not $idx.ContainsKey($nid)) { $idx[$nid] = New-Object System.Collections.ArrayList }
        $type = Get-ObjectPropertyValue -Object $a -Name 'Type' -Default ''
        $typeText = if ($type -is [System.Array]) { (@($type) -join '/') } else { [string]$type }
        $null = $idx[$nid].Add([PSCustomObject]@{
            Status      = L 'recovery.status.applied'
            StatusOrder = 0
            Type        = $typeText
            Depth       = [string](Get-ObjectPropertyValue -Object $a -Name 'Depth' -Default '')
            Start       = [string](Get-ObjectPropertyValue -Object $a -Name 'Start' -Default '')
            End         = [string](Get-ObjectPropertyValue -Object $a -Name 'End' -Default '')
            Original    = [string](Get-ObjectPropertyValue -Object $a -Name 'Original' -Default '')
            Replacement = [string](Get-ObjectPropertyValue -Object $a -Name 'Replacement' -Default '')
        })
    }

    foreach ($s in @(Get-ObjectPropertyValue -Object $ReportData -Name 'Skipped' -Default @())) {
        $nodeId = Get-ObjectPropertyValue -Object $s -Name 'NodeId' -Default $null
        if ($null -eq $s -or $null -eq $nodeId) { continue }
        $nid = [string]$nodeId
        if (-not $idx.ContainsKey($nid)) { $idx[$nid] = New-Object System.Collections.ArrayList }
        $type = Get-ObjectPropertyValue -Object $s -Name 'Type' -Default ''
        $typeText = if ($type -is [System.Array]) { (@($type) -join '/') } else { [string]$type }
        $reason = [string](Get-ObjectPropertyValue -Object $s -Name 'Reason' -Default '')
        $message = [string](Get-ObjectPropertyValue -Object $s -Name 'Message' -Default '')
        $msg = if ([string]::IsNullOrWhiteSpace($message)) { $reason } else { ($reason + ': ' + $message) }
        $null = $idx[$nid].Add([PSCustomObject]@{
            Status      = L 'recovery.status.skipped'
            StatusOrder = 1
            Type        = $typeText
            Depth       = [string](Get-ObjectPropertyValue -Object $s -Name 'Depth' -Default '')
            Start       = [string](Get-ObjectPropertyValue -Object $s -Name 'Start' -Default '')
            End         = [string](Get-ObjectPropertyValue -Object $s -Name 'End' -Default '')
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

    return @($Index[$NodeId] | Sort-Object StatusOrder, @{ Expression = { [int]($_.Start) }; Descending = $false }, @{ Expression = { [int]($_.Depth) }; Descending = $false })
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

$framesGrid.ItemsSource = @($frames)
Update-ReportUi -ReportData $report
$script:reportNodeIndex = Build-ReportNodeIndex -ReportData $report

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
$script:GraphZoomTransform = New-Object System.Windows.Media.ScaleTransform 1.0, 1.0
$graphContainer.LayoutTransform = $script:GraphZoomTransform

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

    $baseW = [Math]::Max(1.0, $size.Width)
    $baseH = [Math]::Max(1.0, $size.Height)

    $graphImage.Width = $baseW
    $graphImage.Height = $baseH
    $graphContainer.Width = $baseW
    $graphContainer.Height = $baseH
    $graphOverlay.Width = $baseW
    $graphOverlay.Height = $baseH

    $script:GraphZoomTransform.ScaleX = $script:GraphZoom
    $script:GraphZoomTransform.ScaleY = $script:GraphZoom

    if ($nodeRectsDip.Count -eq 0) {
        Rebuild-GraphHotspots
    }

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

function Invoke-GraphCtrlWheelZoom {
    param(
        [Parameter(Mandatory)]$MouseArgs
    )

    if ($null -eq $MouseArgs) { return }

    $modifiers = [System.Windows.Input.Keyboard]::Modifiers
    if (($modifiers -band [System.Windows.Input.ModifierKeys]::Control) -ne [System.Windows.Input.ModifierKeys]::Control) {
        return
    }

    $MouseArgs.Handled = $true

    $oldZoom = [double]$script:GraphZoom
    if ($oldZoom -le 0) { $oldZoom = 1.0 }

    $wheelSteps = [int]($MouseArgs.Delta / 120)
    if ($wheelSteps -eq 0) { $wheelSteps = if ($MouseArgs.Delta -gt 0) { 1 } else { -1 } }
    if ($wheelSteps -gt 5) { $wheelSteps = 5 }
    if ($wheelSteps -lt -5) { $wheelSteps = -5 }

    $newZoom = $oldZoom + (0.1 * $wheelSteps)
    if ($newZoom -lt 0.2) { $newZoom = 0.2 }
    if ($newZoom -gt 3.0) { $newZoom = 3.0 }

    if ([Math]::Abs($newZoom - $oldZoom) -lt 0.0001) {
        return
    }

    $scrollViewer = $graphScroll
    if ($null -eq $scrollViewer) { return }

    $viewportPoint = $MouseArgs.GetPosition($scrollViewer)
    $baseX = ([double]$scrollViewer.HorizontalOffset + [double]$viewportPoint.X) / $oldZoom
    $baseY = ([double]$scrollViewer.VerticalOffset + [double]$viewportPoint.Y) / $oldZoom

    Set-GraphZoom -Zoom $newZoom

    $targetX = [Math]::Max(0.0, ($baseX * $newZoom) - [double]$viewportPoint.X)
    $targetY = [Math]::Max(0.0, ($baseY * $newZoom) - [double]$viewportPoint.Y)

    $scrollX = [double]$targetX
    $scrollY = [double]$targetY
    $scrollAction = {
        try {
            if ($null -eq $scrollViewer) { return }
            $scrollViewer.ScrollToHorizontalOffset($scrollX)
            $scrollViewer.ScrollToVerticalOffset($scrollY)
        } catch {
        }
    }.GetNewClosure()
    $null = $scrollViewer.Dispatcher.BeginInvoke([Action]$scrollAction, [System.Windows.Threading.DispatcherPriority]::Background)
}

function Ensure-GraphLoaded {
    Reset-GraphOverlayState

    if (-not (Test-Path -LiteralPath $files.PngPath)) {
        Set-GraphPlaceholder -Message (L 'graph.placeholder.missing_png' @($files.Label)) -ClearImage
        return $false
    }

    try {
        $pngPath = (Resolve-Path -LiteralPath $files.PngPath).ProviderPath
        $graphImage.Source = $null
        $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
        $bmp.BeginInit()
        $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bmp.CreateOptions = [System.Windows.Media.Imaging.BitmapCreateOptions]::IgnoreImageCache
        $bmp.UriSource = [Uri]$pngPath
        $bmp.EndInit()
        $bmp.Freeze()
        $graphImage.Source = $bmp
    } catch {
        Set-GraphPlaceholder -Message (L 'graph.placeholder.load_png_failed' @($_.Exception.Message)) -ClearImage
        return $false
    }

    if (-not $layout) {
        Set-GraphPlaceholder -Message (L 'graph.placeholder.no_layout')
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
        $rect.ToolTip = "Node $id`n$(L 'tooltip.visits'): $visits`n---`n$label"
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

$window.Add_ContentRendered({
    Rebuild-GraphHotspots
    if ($nodeRectsDip.Count -eq 0) {
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

    try {
        $zoom = [double]$script:GraphZoom
        if ($zoom -le 0) { $zoom = 1.0 }
        $centerX = ($r.Left + ($r.Width / 2.0)) * $zoom
        $centerY = ($r.Top + ($r.Height / 2.0)) * $zoom
        $targetX = [Math]::Max(0, $centerX - ($graphScroll.ViewportWidth / 2.0))
        $targetY = [Math]::Max(0, $centerY - ($graphScroll.ViewportHeight / 2.0))
        $graphScroll.ScrollToHorizontalOffset($targetX)
        $graphScroll.ScrollToVerticalOffset($targetY)
    } catch {
    }
}

function Set-CurrentIndex {
    param(
        [Parameter(Mandatory)][int]$Index,
        [switch]$FromGrid
    )

    if ($frames.Count -le 0) {
        $txtStatus.Text = L 'status.empty' @($WorkDir, $files.Label)
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

    $txtStatus.Text = L 'status.main' @($WorkDir, $files.Label, $Index, ($frames.Count - 1), $nid, $frame.NodeType, $frame.Status)

    $txtNodeHeader.Text = L 'node.header' @($nid, $frame.NodeType)
    $txtNodeMeta.Text = L 'node.meta' @($frame.Time, $frame.Status, $frame.Action, $frame.Target, $frame.Reason, $frame.Result, $frame.ConditionResult)
    $txtNodeRaw.Text = [string]$frame.Code
    Set-NodeRecoveryRows -Rows @(Get-NodeRecoveryRows -Index $reportNodeIndex -NodeId $nid)

    $varsReadGrid.ItemsSource = @(Convert-VarHashForGrid -VarHash $frame.VarsRead)
    $varsWrittenGrid.ItemsSource = @(Convert-VarHashForGrid -VarHash $frame.VarsWritten)

    $state = Get-StateAtIndex -Frames $frames -Checkpoints $checkpoints -Index $Index
    $varsStateGrid.ItemsSource = @(Convert-VarTableForGrid -Vars $state.Vars)
    $scopeList.ItemsSource = @($state.ScopeStack | ForEach-Object { L 'scope.item' @($_.ScopeType, $_.ScopeName, $_.Prefix) })

    Update-Highlight -NodeId $nid

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

        $reportHostDisplay = Get-ReportHostDisplay -ReportData $script:report
    if ($reportHostDisplay) {
        $window.Title = L 'window.title.with_host' @($files.Label, $reportHostDisplay)
    } else {
        $window.Title = L 'window.title.no_host' @($files.Label)
    }

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

$framesGrid.Add_SelectionChanged({
    if ($script:SuppressGrid) { return }
    $sel = $framesGrid.SelectedItem
    if ($sel -and $null -ne $sel.Index) {
        Set-CurrentIndex -Index ([int]$sel.Index) -FromGrid:$true
    }
})

$nodeRecoveryGrid.Add_SelectionChanged({
    if ($script:SuppressRecoverySelection) { return }
    Set-RecoveryDetailText -Row $nodeRecoveryGrid.SelectedItem
})

$nodeRecoveryContextMenu = New-Object System.Windows.Controls.ContextMenu
$miCopyRecoveryOriginal = New-Object System.Windows.Controls.MenuItem
$miCopyRecoveryOriginal.Header = L 'menu.copy_original'
$miCopyRecoveryOriginal.Add_Click({
    $row = $nodeRecoveryGrid.SelectedItem
    $text = if ($row) { [string]$row.Original } else { [string]$txtRecoveryOriginalFull.Text }
    try { [System.Windows.Clipboard]::SetText($text) } catch {}
})
$miCopyRecoveryReplacement = New-Object System.Windows.Controls.MenuItem
$miCopyRecoveryReplacement.Header = L 'menu.copy_replacement'
$miCopyRecoveryReplacement.Add_Click({
    $row = $nodeRecoveryGrid.SelectedItem
    $text = if ($row) { [string]$row.Replacement } else { [string]$txtRecoveryReplacementFull.Text }
    try { [System.Windows.Clipboard]::SetText($text) } catch {}
})
[void]$nodeRecoveryContextMenu.Items.Add($miCopyRecoveryOriginal)
[void]$nodeRecoveryContextMenu.Items.Add($miCopyRecoveryReplacement)
$nodeRecoveryGrid.ContextMenu = $nodeRecoveryContextMenu

$btnOpenWorkDir.Add_Click({
    $newDir = Select-WorkDirDialog
    if (-not $newDir) { return }

    try {
        $newDir = Resolve-WorkDirPath -Path $newDir
    } catch {
        [System.Windows.MessageBox]::Show($_.Exception.Message, (L 'message.open_failed_title'), "OK", "Warning") | Out-Null
        return
    }

    $newRound = Select-RoundDialog -Dir $newDir
    if (-not $newRound) { return }

    try {
        Load-SessionIntoUi -TargetWorkDir $newDir -TargetRound $newRound
    } catch {
        [System.Windows.MessageBox]::Show((L 'message.open_failed_load' @($_.Exception.Message)), (L 'message.open_failed_title'), "OK", "Error") | Out-Null
    }
})

$btnChangeRound.Add_Click({
    $newRound = Select-RoundDialog -Dir $WorkDir
    if (-not $newRound) { return }

    try {
        Load-SessionIntoUi -TargetWorkDir $WorkDir -TargetRound $newRound
    } catch {
        [System.Windows.MessageBox]::Show((L 'message.change_round_failed' @($_.Exception.Message)), (L 'message.change_round_failed_title'), "OK", "Error") | Out-Null
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
$graphScroll.Add_PreviewMouseWheel({
    param($sender, $e)
    Invoke-GraphCtrlWheelZoom -MouseArgs $e
})
$graphContainer.Add_PreviewMouseWheel({
    param($sender, $e)
    Invoke-GraphCtrlWheelZoom -MouseArgs $e
})
$btnZoomOut.Add_Click({ Set-GraphZoom -Zoom ($script:GraphZoom - 0.1) })
$btnZoomIn.Add_Click({ Set-GraphZoom -Zoom ($script:GraphZoom + 0.1) })
$btnZoomReset.Add_Click({ Set-GraphZoom -Zoom 1.0 })

    $reportHostDisplay = Get-ReportHostDisplay -ReportData $script:report
    if ($reportHostDisplay) {
        $window.Title = L 'window.title.with_host' @($files.Label, $reportHostDisplay)
    } else {
        $window.Title = L 'window.title.no_host' @($files.Label)
    }
Set-GraphZoom -Zoom ($sldZoom.Value / 100.0)
$framesGrid.SelectedIndex = 0
Set-CurrentIndex -Index 0 -FromGrid:$false

$null = $window.ShowDialog()
