# Readme

PowerShell 反混淆工具链，核心流程：
1. `Generate-CFG.ps1` 解析脚本并生成 CFG（含可还原片段、变量/别名信息）。
2. `Execute-CFG.ps1` 按 CFG 节点执行并记录执行日志、片段求值结果。
3. `Rebuild-Deobfuscated.ps1` 基于执行结果回写脚本，支持多轮迭代直到收敛。

## 环境要求

- 必须使用 `pwsh`（PowerShell 7+）。
- `Review-RoundReplay.Wpf.ps1` 和 `Debug-Deobfuscation.Wpf.ps1` 仅支持 Windows（WPF）。
- 安装 Graphviz 的 `dot` 可生成 PNG；未安装时仍可输出 DOT。

## 快速开始

```powershell
# 1) 一键多轮解混淆（推荐主入口）
pwsh -NoProfile -File .\Rebuild-Deobfuscated.ps1 -ScriptPath .\in\in.ps1

# 2) 调试模式（逐节点执行）
pwsh -NoProfile -Sta -File .\Debug-Deobfuscation.Wpf.ps1 -ScriptPath .\in\in.ps1

# 3) 复盘已有 round 日志
pwsh -NoProfile -Sta -File .\Review-RoundReplay.Wpf.ps1 -WorkDir .\in\in.rebuilt.ps1.work -Round 1
```

## 参数说明（重点）

### 1) Rebuild-Deobfuscated.ps1（主入口）

```powershell
pwsh -NoProfile -File .\Rebuild-Deobfuscated.ps1 -ScriptPath .\target.ps1 [options]
```

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `-ScriptPath` | 必填 | 输入脚本路径。 |
| `-OutPath` | `<ScriptPath>.rebuilt.ps1` | 最终输出脚本路径。 |
| `-WorkDir` | `<OutPath>.work`（仅 `FullOutput=$true`） | 每轮过程产物目录。`FullOutput=$false` 时忽略。 |
| `-FullOutput` | `$true` | `true`：保留每轮 in/out/log/report/cfg；`false`：只输出最终脚本，最快。 |
| `-OverlapStrategy` | `Inner` | 重叠片段选择策略：`Inner`（优先内层）/`Outer`（优先外层）。 |
| `-VariableConflictPolicy` | `skip` | 变量位点多值策略：`skip`（跳过变化变量）/`last`（取最后一次可用简单值）。 |
| `-MaxRounds` | `5` | 最大迭代轮数。 |
| `-MaxIterations` | `1000` | 单轮 CFG 执行迭代上限（防死循环）。 |
| `-MaxTotalNodes` | `50000` | 单轮最大节点访问数上限。 |
| `-DryRun` | `$false` | 仅运行分析与统计，不写最终输出文件。 |

常用示例：

```powershell
# 高性能模式（不落盘每轮过程）
pwsh -NoProfile -File .\Rebuild-Deobfuscated.ps1 -ScriptPath .\in\in.ps1 -FullOutput:$false

# 值变化变量采用“最后值”
pwsh -NoProfile -File .\Rebuild-Deobfuscated.ps1 -ScriptPath .\in\in.ps1 -VariableConflictPolicy last

# 保守策略：变化变量一律跳过（默认）
pwsh -NoProfile -File .\Rebuild-Deobfuscated.ps1 -ScriptPath .\in\in.ps1 -VariableConflictPolicy skip
```

补充：
- 从当前实现看，若某轮 `applied=0`，该轮 round 文件会被清理并停止，不再保留“空替换轮次”产物。

### 2) Debug-Deobfuscation.Wpf.ps1（交互调试）

```powershell
pwsh -NoProfile -Sta -File .\Debug-Deobfuscation.Wpf.ps1 -ScriptPath .\target.ps1 [options]
```

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `-ScriptPath` | 必填 | 目标脚本路径。 |
| `-WorkDir` | `<ScriptPath>.debug.work` | 调试输出目录。 |
| `-OverlapStrategy` | `Inner` | 预览/导出时的重叠片段策略：`Inner`/`Outer`。 |
| `-MaxIterations` | `1000` | 调试会话执行迭代上限。 |
| `-MaxTotalNodes` | `50000` | 调试会话最大节点访问上限。 |
| `-NoUI` | `$false` | 无界面模式，只输出初始化摘要。 |

调试产物（在 `WorkDir`）：
- `debug.execution.log`
- `debug.cfg.dot` / `debug.cfg.png`
- `debug.out.ps1`
- `debug.report.json`

### 3) Review-RoundReplay.Wpf.ps1（round 复盘）

```powershell
pwsh -NoProfile -Sta -File .\Review-RoundReplay.Wpf.ps1 [options]
```

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `-WorkDir` | 交互选择 | `Rebuild-Deobfuscated` 生成的 `*.work` 目录。`-NoUI` 时必填。 |
| `-Round` | 交互选择（`NoUI` 下默认最新轮） | 要复盘的轮次编号。 |
| `-CheckpointInterval` | `200` | 变量状态 checkpoint 间隔。越小跳转越快但内存占用更高。 |
| `-NoUI` | `$false` | 无界面模式，只解析并输出摘要。 |

### 4) run.ps1（快速演示脚本）

- 该脚本无参数，内置分析目标为 `in/in.ps1`。
- 主要用于快速联调 `Generate-CFG.ps1 + Execute-CFG.ps1`。

## Generate / Execute 公开函数参数

### Generate-CFG.ps1

1. `Get-ScriptControlFlow -ScriptPath <string>`
2. `Export-CfgToDot -finalCFG <hashtable> [-outputPath <string>] [-AppliedNodeIds <int[]>]`

说明：
- `-AppliedNodeIds` 用于标记“实际发生替换”的节点（高亮）。
- `Export-CfgToDot` 会尝试调用 `dot` 生成 PNG；若不可用只保留 DOT。

### Execute-CFG.ps1

1. `Invoke-CFGTraversal -CFG <hashtable> [-LogPath <string>] [-MaxIterations <int>] [-MaxTotalNodes <int>]`
2. `New-CFGExecutionSession -CFG <hashtable> [-LogPath <string>] [-MaxIterations <int>] [-MaxTotalNodes <int>]`
3. `Invoke-CFGStep -Session <hashtable> [-StopAtUserNode]`
4. `Get-CFGVariableStack -Session <hashtable> [-IncludeInternal]`
5. `Set-CFGVariableValue -Session <hashtable> -VariableName <string> -ValueExpression <string>`
6. `Get-CFGNextEdgePreview -Session <hashtable>`
7. `Close-CFGExecutionSession -Session <hashtable>`

## 目录结构

- `Generate-CFG.ps1`：CFG 生成与可还原片段识别。
- `Execute-CFG.ps1`：CFG 执行器（批量执行 + 调试会话 API）。
- `Rebuild-Deobfuscated.ps1`：多轮重建主入口。
- `Debug-Deobfuscation.Wpf.ps1`：交互式调试 UI。
- `Review-RoundReplay.Wpf.ps1`：round 复盘 UI。
- `run.ps1`：快速演示入口。
- `in/`：输入脚本与测试样例目录。
