<#
.SYNOPSIS
  基于 CFG 遍历执行结果（ResolvableResults）对脚本做片段回写，输出重建后的“解混淆脚本”。

.DESCRIPTION
  支持多轮迭代：每一轮都重新生成 CFG 并执行，再把可确定的可还原表达式替换回脚本；
  直到某一轮 applied replacements = 0（收敛）或达到 MaxRounds。

  约束（v1）：
  - 仅使用 ResolvableResults（不使用变量读取、也不使用内联函数调用结果）；
  - 遇到 __BLOCKED_PLACEHOLDER__ 一律跳过；
  - 同一源码片段若出现多个不同值则跳过；
  - 重叠/嵌套替换片段通过 -OverlapStrategy 控制（Outer/Inner）。

.EXAMPLE
  pwsh .\Rebuild-Deobfuscated.ps1 -ScriptPath .\in\in.ps1

.EXAMPLE
  pwsh .\Rebuild-Deobfuscated.ps1 -ScriptPath .\sample.ps1 -MaxRounds 10 -OverlapStrategy Inner
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ScriptPath,

    [string]$OutPath,

    [string]$WorkDir,

    [ValidateSet('Outer', 'Inner')]
    [string]$OverlapStrategy = 'Inner',

    [int]$MaxRounds = 5,

    [int]$MaxIterations = 1000,

    [int]$MaxTotalNodes = 50000,

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw "需要 PowerShell 7+ (pwsh) 运行重建脚本。当前版本: $($PSVersionTable.PSVersion)"
}

function New-SkipRecord {
    param(
        [string]$Reason,
        [string]$Message,
        $Item
    )

    $start = $null
    $end = $null
    $type = $null
    $nodeId = $null
    $depth = $null

    if ($Item) {
        $start = $Item.StartOffset
        $end = $Item.EndOffset
        $type = $Item.Type
        $nodeId = $Item.NodeId
        $depth = $Item.Depth
    }

    return [PSCustomObject]@{
        Reason    = $Reason
        Message   = $Message
        Start     = $start
        End       = $end
        Type      = $type
        NodeId    = $nodeId
        Depth     = $depth
        Timestamp = (Get-Date).ToString('o')
    }
}

function ConvertTo-PreviewText {
    param(
        [string]$Text,
        [int]$MaxLen = 200
    )

    if ($null -eq $Text) { return $null }
    if ($Text.Length -le $MaxLen) { return $Text }
    return $Text.Substring(0, $MaxLen) + '...'
}

function Get-FullScriptTextFromFile {
    param([Parameter(Mandatory)][string]$Path)

    # 使用 Parser.ParseFile 同一路径读取脚本文本，可最大程度保证 offset 与 AST 一致
    $ast = Get-Ast $Path
    if (-not $ast -or -not $ast.Extent -or -not $ast.Extent.StartScriptPosition) {
        throw "无法解析脚本获取全文: $Path"
    }

    return $ast.Extent.StartScriptPosition.GetFullScript()
}

function Get-ReplacementsFromResolvableResults {
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][string]$ScriptText
    )

    $candidates = @()
    $skipped = @()

    if (-not $Context.ResolvableResults) {
        return [PSCustomObject]@{
            Candidates = @()
            Skipped    = @()
        }
    }

    # 同一片段（Start/End）可能被多个节点记录；若 replacement 不一致则判为冲突并跳过
    $regionMap = @{}          # key -> candidate
    $conflictRegions = @{}    # key -> @{ Replacements = @() }

    foreach ($rec in $Context.ResolvableResults.Values) {
        $r = $rec.Resolvable
        if (-not $r) { continue }

        $start = $r.StartOffset
        $end = $r.EndOffset
        $type = $r.Type
        $depth = $r.Depth
        $nodeId = $rec.NodeId

        $baseItem = [PSCustomObject]@{
            StartOffset = $start
            EndOffset   = $end
            Type        = $type
            Depth       = $depth
            NodeId      = $nodeId
        }

        if ($null -eq $start -or $null -eq $end) {
            $skipped += New-SkipRecord -Reason 'no_offset' -Message '无 StartOffset/EndOffset，无法回写' -Item $baseItem
            continue
        }

        if ($start -lt 0 -or $end -le $start -or $end -gt $ScriptText.Length) {
            $skipped += New-SkipRecord -Reason 'out_of_range' -Message "offset 越界: [$start-$end], len=$($ScriptText.Length)" -Item $baseItem
            continue
        }

        $uniqueValues = @($rec.Values | Select-Object -Unique)
        if ($uniqueValues.Count -ne 1) {
            $skipped += New-SkipRecord -Reason 'inconsistent' -Message "同一片段出现多个值: $($uniqueValues.Count)" -Item $baseItem
            continue
        }

        $replacement = [string]$uniqueValues[0]

        # 违禁命令占位符：跳过
        if ($replacement -eq '__BLOCKED_PLACEHOLDER__') {
            $skipped += New-SkipRecord -Reason 'blocked' -Message '值为占位符，跳过替换' -Item $baseItem
            continue
        }

        $original = $ScriptText.Substring($start, $end - $start)
        if ($original -eq $replacement) {
            $skipped += New-SkipRecord -Reason 'no_change' -Message 'replacement 与原片段一致' -Item $baseItem
            continue
        }

        $cand = [PSCustomObject]@{
            StartOffset = $start
            EndOffset   = $end
            Replacement = $replacement
            Original    = $original
            Type        = $type
            Depth       = $depth
            NodeId      = $nodeId
        }

        $key = "$start`:$end"

        if ($conflictRegions.ContainsKey($key)) {
            $skipped += New-SkipRecord -Reason 'conflict_same_range' -Message "同区间已冲突，忽略: [$start-$end]" -Item $cand
            continue
        }

        if (-not $regionMap.ContainsKey($key)) {
            $regionMap[$key] = $cand
            continue
        }

        $existing = $regionMap[$key]
        if ($existing.Replacement -eq $cand.Replacement) {
            # 同区间同 replacement：去重即可
            $skipped += New-SkipRecord -Reason 'duplicate' -Message "同区间重复记录，已去重: [$start-$end]" -Item $cand
            continue
        }

        # 同区间不同 replacement：判冲突，移除已有并跳过两者
        $conflictRegions[$key] = @{
            Replacements = @($existing.Replacement, $cand.Replacement)
        }
        $null = $regionMap.Remove($key)
        $skipped += New-SkipRecord -Reason 'conflict_same_range' -Message "同区间出现不同 replacement，跳过: [$start-$end]" -Item $existing
        $skipped += New-SkipRecord -Reason 'conflict_same_range' -Message "同区间出现不同 replacement，跳过: [$start-$end]" -Item $cand
    }

    $candidates = @($regionMap.Values)

    return [PSCustomObject]@{
        Candidates = $candidates
        Skipped    = $skipped
    }
}

function Select-NonOverlappingReplacements {
    param(
        [AllowEmptyCollection()]
        [array]$Candidates,
        [Parameter(Mandatory)][ValidateSet('Outer', 'Inner')][string]$Strategy
    )

    if (-not $Candidates -or $Candidates.Count -eq 0) {
        return [PSCustomObject]@{
            Selected = @()
            Skipped  = @()
        }
    }

    $selected = @()
    $skipped = @()

    if ($Strategy -eq 'Outer') {
        # 外层优先：Start 升序，End 降序（同 Start 先选更大跨度），贪心取不重叠集合
        $sorted = $Candidates | Sort-Object StartOffset, @{ Expression = 'EndOffset'; Descending = $true }
        $lastEnd = -1
        foreach ($c in $sorted) {
            if ($c.StartOffset -ge $lastEnd) {
                $selected += $c
                $lastEnd = $c.EndOffset
            } else {
                $skipped += New-SkipRecord -Reason 'overlap' -Message '与已选片段重叠（Outer 策略丢弃内层/后续）' -Item $c
            }
        }
    } else {
        # 内层优先：End 升序，Start 降序，使用“最早结束优先”的区间调度贪心
        $sorted = $Candidates | Sort-Object EndOffset, @{ Expression = 'StartOffset'; Descending = $true }
        $lastEnd = -1
        foreach ($c in $sorted) {
            if ($c.StartOffset -ge $lastEnd) {
                $selected += $c
                $lastEnd = $c.EndOffset
            } else {
                $skipped += New-SkipRecord -Reason 'overlap' -Message '与已选片段重叠（Inner 策略丢弃外层/冲突）' -Item $c
            }
        }

        # 统一按 Start 排序，便于后续替换/展示
        $selected = @($selected | Sort-Object StartOffset)
    }

    return [PSCustomObject]@{
        Selected = $selected
        Skipped  = $skipped
    }
}

function Apply-ReplacementsToText {
    param(
        [Parameter(Mandatory)][string]$Text,
        [AllowEmptyCollection()]
        [array]$Replacements
    )

    if (-not $Replacements -or $Replacements.Count -eq 0) {
        return $Text
    }

    # 从后往前替换，避免 offset 失效
    $ordered = $Replacements | Sort-Object StartOffset -Descending
    $result = $Text

    foreach ($r in $ordered) {
        $result = $result.Substring(0, $r.StartOffset) + $r.Replacement + $result.Substring($r.EndOffset)
    }

    return $result
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Object
    )

    $json = $Object | ConvertTo-Json -Depth 10
    Set-Content -LiteralPath $Path -Value $json -Encoding UTF8
}

# ========== 主流程 ==========

$scriptFullPath = (Resolve-Path -LiteralPath $ScriptPath).ProviderPath

if ([string]::IsNullOrWhiteSpace($OutPath)) {
    $dir = [System.IO.Path]::GetDirectoryName($scriptFullPath)
    $base = [System.IO.Path]::GetFileNameWithoutExtension($scriptFullPath)
    $OutPath = Join-Path $dir ($base + '.rebuilt.ps1')
}

$OutPath = [System.IO.Path]::GetFullPath($OutPath)

if ([string]::IsNullOrWhiteSpace($WorkDir)) {
    $WorkDir = $OutPath + '.work'
}
$WorkDir = [System.IO.Path]::GetFullPath($WorkDir)

if (-not (Test-Path -LiteralPath $WorkDir)) {
    $null = New-Item -ItemType Directory -Path $WorkDir -Force
}

$genPath = Join-Path $PSScriptRoot 'Generate-CFG.ps1'
$execPath = Join-Path $PSScriptRoot 'Execute-CFG.ps1'

if (-not (Test-Path -LiteralPath $genPath)) { throw "缺少文件: $genPath" }
if (-not (Test-Path -LiteralPath $execPath)) { throw "缺少文件: $execPath" }

. $genPath
. $execPath

Write-Host "=== 重建解混淆脚本（递归迭代）===" -ForegroundColor Cyan
Write-Host "ScriptPath : $scriptFullPath" -ForegroundColor Gray
Write-Host "OutPath    : $OutPath" -ForegroundColor Gray
Write-Host "WorkDir    : $WorkDir" -ForegroundColor Gray
Write-Host "Strategy   : $OverlapStrategy" -ForegroundColor Gray
Write-Host "MaxRounds  : $MaxRounds" -ForegroundColor Gray
Write-Host "DryRun     : $DryRun" -ForegroundColor Gray
Write-Host ""

$currentPath = $scriptFullPath
$finalRound = 0
$finalRoundOutPath = $null
$terminatedBy = $null

for ($round = 1; $round -le $MaxRounds; $round++) {
    $roundLabel = '{0:d2}' -f $round
    $roundInPath = Join-Path $WorkDir ("round{0}.in.ps1" -f $roundLabel)
    $roundOutPath = Join-Path $WorkDir ("round{0}.out.ps1" -f $roundLabel)
    $roundLogPath = Join-Path $WorkDir ("round{0}.execution.log" -f $roundLabel)
    $roundReportPath = Join-Path $WorkDir ("round{0}.report.json" -f $roundLabel)

    Copy-Item -LiteralPath $currentPath -Destination $roundInPath -Force

    Write-Host ("[Round {0}/{1}] 分析+执行..." -f $round, $MaxRounds) -ForegroundColor Yellow

    $cfg = Get-ScriptControlFlow -ScriptPath $roundInPath
    if (-not $cfg) {
        throw "CFG 生成失败: $roundInPath"
    }

    $ctx = Invoke-CFGTraversal -CFG $cfg -LogPath $roundLogPath -MaxIterations $MaxIterations -MaxTotalNodes $MaxTotalNodes

    $scriptText = Get-FullScriptTextFromFile -Path $roundInPath

    $base = Get-ReplacementsFromResolvableResults -Context $ctx -ScriptText $scriptText
    $candidates = @($base.Candidates)
    $skipped = @($base.Skipped)

    $sel = Select-NonOverlappingReplacements -Candidates $candidates -Strategy $OverlapStrategy
    $selected = @($sel.Selected)
    $skipped += @($sel.Skipped)

    $newText = Apply-ReplacementsToText -Text $scriptText -Replacements $selected

    # 生成 report（尽量轻量，保留 offset 和预览）
    $skipReasonCounts = @{}
    foreach ($s in $skipped) {
        if (-not $skipReasonCounts.ContainsKey($s.Reason)) { $skipReasonCounts[$s.Reason] = 0 }
        $skipReasonCounts[$s.Reason]++
    }

    $appliedItems = @()
    foreach ($a in $selected) {
        $appliedItems += [PSCustomObject]@{
            Start       = $a.StartOffset
            End         = $a.EndOffset
            NodeId      = $a.NodeId
            Type        = $a.Type
            Depth       = $a.Depth
            OriginalLen = if ($null -eq $a.Original) { 0 } else { $a.Original.Length }
            Original    = ConvertTo-PreviewText -Text $a.Original -MaxLen 200
            Replacement = $a.Replacement
        }
    }

    $report = [ordered]@{
        Round           = $round
        RoundLabel      = $roundLabel
        InputPath       = $roundInPath
        OutputPath      = $roundOutPath
        ExecutionLog    = $roundLogPath
        OverlapStrategy = $OverlapStrategy
        MaxIterations   = $MaxIterations
        MaxTotalNodes   = $MaxTotalNodes
        CandidateCount  = $candidates.Count
        SelectedCount   = $selected.Count
        AppliedCount    = $selected.Count
        SkippedCount    = $skipped.Count
        SkippedByReason = $skipReasonCounts
        Applied         = $appliedItems
        Skipped         = $skipped
        Timestamp       = (Get-Date).ToString('o')
    }

    Write-JsonFile -Path $roundReportPath -Object $report

    if (-not $DryRun) {
        Set-Content -LiteralPath $roundOutPath -Value $newText -Encoding UTF8
    } else {
        # DryRun 仍然写出 out 文件供下一轮继续（但最终不会写 OutPath）
        Set-Content -LiteralPath $roundOutPath -Value $newText -Encoding UTF8
    }

    Write-Host ("  candidates={0} selected={1} applied={2} skipped={3}" -f $candidates.Count, $selected.Count, $selected.Count, $skipped.Count) -ForegroundColor Gray
    Write-Host ("  in    : {0}" -f $roundInPath) -ForegroundColor Gray
    Write-Host ("  out   : {0}" -f $roundOutPath) -ForegroundColor Gray
    Write-Host ("  log   : {0}" -f $roundLogPath) -ForegroundColor Gray
    Write-Host ("  report: {0}" -f $roundReportPath) -ForegroundColor Gray
    Write-Host ""

    $finalRound = $round
    $finalRoundOutPath = $roundOutPath

    if ($selected.Count -eq 0) {
        $terminatedBy = 'no_replacements'
        break
    }

    # 下一轮输入 = 本轮输出
    $currentPath = $roundOutPath
}

if (-not $finalRoundOutPath) {
    throw "未产生任何轮次输出，无法生成最终脚本。"
}

if ($null -eq $terminatedBy) {
    $terminatedBy = 'max_rounds'
}

if (-not $DryRun) {
    $outDir = [System.IO.Path]::GetDirectoryName($OutPath)
    if (-not [string]::IsNullOrWhiteSpace($outDir) -and -not (Test-Path -LiteralPath $outDir)) {
        $null = New-Item -ItemType Directory -Path $outDir -Force
    }
    Copy-Item -LiteralPath $finalRoundOutPath -Destination $OutPath -Force
}

Write-Host "=== 完成 ===" -ForegroundColor Green
Write-Host ("TerminatedBy : {0}" -f $terminatedBy) -ForegroundColor Gray
Write-Host ("FinalRound   : {0}" -f $finalRound) -ForegroundColor Gray
Write-Host ("FinalWorkOut : {0}" -f $finalRoundOutPath) -ForegroundColor Gray
Write-Host ("OutPath      : {0}" -f $OutPath) -ForegroundColor Gray
Write-Host ("WorkDir      : {0}" -f $WorkDir) -ForegroundColor Gray
