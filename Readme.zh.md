# PSDissect: A CFG-Guided, Semantics-Preserving Interactive Deobfuscation Framework for PowerShell Scripts

PSDissect 是一个面向 PowerShell 脚本的研究型解混淆工具集，用于分析混淆脚本和动态生成脚本。它结合了 CFG 引导的多轮重建、交互式调试和轮次级回放，尽可能在保持可执行语义的前提下恢复更可读的脚本内容。

日常使用只需要记住 3 个入口：

| 脚本 | 用途 |
| --- | --- |
| `Rebuild-Deobfuscated.ps1` | 多轮自动解混，生成最终 `.rebuilt.ps1`，推荐主入口 |
| `Debug-Deobfuscation.Wpf.ps1` | 单步调试，查看 CFG、变量栈、动态子图和当前重建预览 |
| `Review-RoundReplay.Wpf.ps1` | 回放 `Rebuild` 的某一轮执行过程，适合复盘和排错 |

## 环境要求

- 宿主很重要：请用和目标脚本一致的宿主运行工具。
  - 面向 Windows PowerShell 5.1 的脚本：用 `powershell.exe`
  - 面向 PowerShell 7+ 的脚本：用 `pwsh`
- `Debug-Deobfuscation.Wpf.ps1` 和 `Review-RoundReplay.Wpf.ps1` 依赖 WPF，只支持 Windows。
- 建议安装 Graphviz 的 `dot`。
  - 已安装：可生成 PNG，并在 UI 中显示/点击节点图
  - 未安装：核心分析仍可运行，但图像体验会下降

## 快速开始

```powershell
# 1) 自动多轮解混（推荐）
.\Rebuild-Deobfuscated.ps1 -ScriptPath .\in\in.ps1

# 2) 调试模式
.\Debug-Deobfuscation.Wpf.ps1 -ScriptPath .\in\in.ps1

# 3) 回放某一轮
.\Review-RoundReplay.Wpf.ps1 -WorkDir .\in\in.rebuilt.ps1.work -Round 1
```

如果你是从外部显式启动宿主，也可以这样写：

```powershell
pwsh -NoProfile -File .\Rebuild-Deobfuscated.ps1 -ScriptPath .\in\in.ps1
pwsh -NoProfile -Sta -File .\Debug-Deobfuscation.Wpf.ps1 -ScriptPath .\in\in.ps1
pwsh -NoProfile -Sta -File .\Review-RoundReplay.Wpf.ps1 -WorkDir .\in\in.rebuilt.ps1.work -Round 1
```

如果你要用 `powershell.exe -File` 调 `Rebuild-Deobfuscated.ps1`，布尔入口参数建议直接写成普通值：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Rebuild-Deobfuscated.ps1 -ScriptPath .\in\in.ps1 -FullOutput false -SafeMode true
```

目前支持的布尔写法包括 `true/false`、`$true/$false`、`1/0`、`yes/no`、`on/off`。

## 常用流程

### 1. 自动解混

先跑：

```powershell
.\Rebuild-Deobfuscated.ps1 -ScriptPath .\target.ps1
```

结果：

- 输出脚本：`target.rebuilt.ps1`
- 工作目录：`target.rebuilt.ps1.work`（`-FullOutput $true` 时）

工作目录中通常会包含：

- `roundNN.in.ps1`
- `roundNN.out.ps1`
- `roundNN.execution.log`
- `roundNN.report.json`
- `roundNN.cfg.dot`
- `roundNN.cfg.png`（安装 `dot` 时）

适合：

- 想先快速拿到可用结果
- 需要多轮递归剥离
- 后续还想用 replay 复盘

### 2. 调试模式

```powershell
.\Debug-Deobfuscation.Wpf.ps1 -ScriptPath .\target.ps1
```

特点：

- 启动后先选择界面语言
- 可单步执行、`Run All`、重置
- 可查看和手动修改变量值
- 可实时看到当前 CFG 和红框所在节点
- 动态生成的子图会加入当前图中
- 可导出当前重建结果

默认工作目录：

- `target.ps1.debug.work`

常见文件：

- `debug.execution.log`
- `debug.cfg.dot`
- `debug.cfg.png`
- `debug.ui-error.log`

点击导出后会额外写出：

- `debug.out.ps1`
- `debug.report.json`

适合：

- 想看脚本到底执行到了哪里
- 需要人工补变量继续推进
- 需要确认动态代码何时生成、何时跳入子图

### 3. 回放某一轮

```powershell
.\Review-RoundReplay.Wpf.ps1 -WorkDir .\target.rebuilt.ps1.work -Round 1
```

特点：

- 启动后先选择界面语言
- 基于 `Rebuild` 产出的 round 文件回放
- 可逐帧前进/后退、重置、直接跳到最后
- 可查看当轮节点、变量状态、应用/跳过的替换项

注意：

- `Review-RoundReplay.Wpf.ps1` 读取的是 `Rebuild-Deobfuscated.ps1` 的 `*.work` 目录
- 它不是用来读取 `debug.work` 的

## 参数速查

### `Rebuild-Deobfuscated.ps1`

```powershell
.\Rebuild-Deobfuscated.ps1 -ScriptPath .\target.ps1 [options]
```

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `-ScriptPath` | 必填 | 输入脚本 |
| `-OutPath` | `<ScriptPath>.rebuilt.ps1` | 最终输出脚本 |
| `-WorkDir` | `<OutPath>.work` | 轮次产物目录，仅 `FullOutput=$true` 时使用 |
| `-FullOutput` | `$true` | 是否保留每轮产物 |
| `-OverlapStrategy` | `Inner` | 重叠替换策略：`Inner` / `Outer` |
| `-VariableConflictPolicy` | `skip` | 变量位点多值策略：`skip` / `last` |
| `-MaxRounds` | `10` | 最大轮数 |
| `-MaxIterations` | `1000` | 单轮最大迭代次数 |
| `-MaxTotalNodes` | `50000` | 单轮最大节点访问数 |
| `-GlobalTimeBudgetMs` | `120000` | 整体时间预算，单位为毫秒，`0` 表示不限 |
| `-DynamicTimeBudgetMs` | `15000` | 单次动态展开预算，单位为毫秒，`0` 表示不限 |
| `-SafeMode` | `$true` | 是否启用安全保护 |
| `-PreExecutionGateMode` | `Balanced` | 先审后执行门控：`Disabled` / `Conservative` / `Balanced` / `Aggressive` |
| `-OptimizationProfile` | `Default` | 行为调优 profile：`Default` / `Cmdline` / `TimeoutCoverage` |
| `-RunMetadataPath` | 未设置 | 可选；将本次运行摘要写成一份 JSON |
| `-DryRun` | `$false` | 只分析，不写最终输出 |

常用示例：

```powershell
# 高性能模式：只要最终结果，不保留 round 文件
.\Rebuild-Deobfuscated.ps1 -ScriptPath .\in\in.ps1 -FullOutput $false

# 变量冲突时取最后一次值
.\Rebuild-Deobfuscated.ps1 -ScriptPath .\in\in.ps1 -VariableConflictPolicy last

# 仅做分析，不写最终输出
.\Rebuild-Deobfuscated.ps1 -ScriptPath .\in\in.ps1 -DryRun

# 额外输出一份简要运行元数据
.\Rebuild-Deobfuscated.ps1 -ScriptPath .\in\in.ps1 -RunMetadataPath .\run-meta.json
```

`OptimizationProfile` 用来调整整体行为策略：

- `Default`：默认行为。
- `Cmdline`：更偏向命令行类样本，对部分回写更保守。
- `TimeoutCoverage`：更强调在预算内完成，允许跳过或浅层处理高开销阶段，以减少超时。

`PreExecutionGateMode` 用来控制“先审后执行”门控的激进程度：

- `Disabled`：关闭门控，基本回到旧的“能下钻就下钻”策略
- `Conservative`：只有明显高风险或高开销片段才会提前拦截
- `Balanced`：默认模式，适合固定预算实验，例如 `120s`
- `Aggressive`：更强调在预算内完成，会更早把复杂片段改为浅层处理或直接停止

门控对片段会给出三类决策：

- `Full`：正常继续分析和执行
- `Shallow`：继续，但会收紧预算，并跳过最昂贵的阶段
- `Stop`：不再继续深挖，直接保留当前层已经恢复出的文本或证据

如果你是在做 `120s` 左右的标准评测，推荐先用：

```powershell
.\Rebuild-Deobfuscated.ps1 -ScriptPath .\target.ps1 -FullOutput $false -MaxRounds 5 -GlobalTimeBudgetMs 120000 -DynamicTimeBudgetMs 5000 -SafeMode $false -PreExecutionGateMode Balanced
```

每轮 `report.json` 里也可能出现这些门控相关字段：`GateMode`、`GateDecision`、`GateScore`、`GateReasons`、`GateMetrics`。

### `Debug-Deobfuscation.Wpf.ps1`

```powershell
.\Debug-Deobfuscation.Wpf.ps1 -ScriptPath .\target.ps1 [options]
```

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `-ScriptPath` | 必填 | 目标脚本 |
| `-WorkDir` | `<ScriptPath>.debug.work` | 调试工作目录 |
| `-OverlapStrategy` | `Inner` | 导出预览时的重叠策略 |
| `-MaxIterations` | `1000` | 最大迭代次数 |
| `-MaxTotalNodes` | `50000` | 最大节点访问数 |
| `-DynamicTimeBudgetMs` | `60000` | 动态展开预算，单位为毫秒 |
| `-NoUI` | 关闭 | 不打开窗口，只输出初始化摘要 |

示例：

```powershell
.\Debug-Deobfuscation.Wpf.ps1 -ScriptPath .\in\in.ps1
.\Debug-Deobfuscation.Wpf.ps1 -ScriptPath .\in\in.ps1 -NoUI
```

### `Review-RoundReplay.Wpf.ps1`

```powershell
.\Review-RoundReplay.Wpf.ps1 [options]
```

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `-WorkDir` | UI 选择 | `Rebuild` 产生的 `*.work` 目录 |
| `-Round` | UI 选择 | 要回放的轮次；`-NoUI` 时默认最新轮 |
| `-CheckpointInterval` | `200` | 变量状态 checkpoint 间隔 |
| `-NoUI` | 关闭 | 不打开窗口，只输出摘要 |

示例：

```powershell
.\Review-RoundReplay.Wpf.ps1 -WorkDir .\in\in.rebuilt.ps1.work -Round 1
.\Review-RoundReplay.Wpf.ps1 -WorkDir .\in\in.rebuilt.ps1.work -NoUI
```

## 使用建议

- 优先顺序通常是：`Rebuild` -> 不满意再进 `Debug` -> 需要看某一轮细节时用 `Replay`
- 如果脚本依赖特定 PowerShell 版本，请务必用同版本宿主运行工具
- UI 脚本建议带 `-Sta` 启动；如果忘了加，脚本会尝试用同一宿主自动重启
- 调试模式里手工设置变量时，输入的是 PowerShell 表达式，例如：

```powershell
123
'abc'
$null
''
```

## 参数传递注意事项

对 `-FullOutput`、`-SafeMode` 这类布尔参数，最稳妥的方式是直接在当前 PowerShell 会话中执行脚本：

```powershell
.\Rebuild-Deobfuscated.ps1 -ScriptPath .\in\in.ps1 -FullOutput $false
```

补充：

- `pwsh -File ... -FullOutput:$false` 可以正常工作
- `powershell.exe -File ... -FullOutput:$false` 在 Windows PowerShell 5.1 下可能会把 `$false` 当成字符串，导致参数绑定失败

## 脚本化调用（可选）

如果你想在自己的脚本里复用核心能力，可以点源这两个文件：

```powershell
. .\Generate-CFG.ps1
. .\Execute-CFG.ps1
```

常用函数：

- `Get-ScriptControlFlow`
- `Export-CfgToDot`
- `Invoke-CFGTraversal`
- `New-CFGExecutionSession`
- `Invoke-CFGStep`
- `Get-CFGVariableStack`
- `Set-CFGVariableValue`
- `Get-CFGNextEdgePreview`
- `Get-CFGExecutionFailures`
- `Close-CFGExecutionSession`

## 文件说明

- `Rebuild-Deobfuscated.ps1`：自动多轮解混主入口
- `Debug-Deobfuscation.Wpf.ps1`：交互式调试
- `Review-RoundReplay.Wpf.ps1`：轮次回放
- `Generate-CFG.ps1`：CFG 生成与 DOT 导出
- `Execute-CFG.ps1`：执行器和调试会话 API
- `Ui-Localization.ps1`：debug/replay 的中英文 UI 文本
