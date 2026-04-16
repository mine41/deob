# README

PowerShell 反混淆工具链。当前版本已经从“仅动态回写”扩展为“动态执行 + 静态还原”的混合流程：

1. `Generate-CFG.ps1` 解析脚本并生成 CFG，同时识别可还原片段、变量位点、别名等信息。
2. `Execute-CFG.ps1` 按 CFG 节点执行，记录执行日志、节点结果、变量栈和失败信息。
3. `Rebuild-Deobfuscated.ps1` 将动态结果与静态候选合并，按轮次重建脚本直到收敛。
4. `Debug-Deobfuscation.Wpf.ps1` 提供交互式逐步调试，并对未执行分支做静态预览。
5. `Review-RoundReplay.Wpf.ps1` 基于 round 日志进行复盘、跳转和排错。

## 核心能力

- **混合解混**：执行路径上的片段优先走动态求值；未执行分支上的简单表达式可走静态还原。
- **失败继续**：节点执行报错时，执行器会记录失败，并在 CFG 允许时继续后续节点，而不是整轮直接中断。
- **手动补变量**：调试模式可为缺失变量手工输入值，帮助脚本在测试环境缺失上下文时继续推进。
- **变量栈分级显示**：默认显示用户变量和常用内部变量；可额外展开“高级内部变量”。
- **轮次复盘增强**：round 选择界面会结合 report 摘要显示 `candidates/applied/skipped`，便于快速定位异常轮次。
- **语法保护**：自动应用替换前后会做语法保护，避免生成不可解析脚本。

## 环境要求

- 运行宿主就是解混语义来源：使用 `powershell.exe` 时按 Windows PowerShell 5.1 语义分析；使用 `pwsh` 时按 PowerShell 7+ 语义分析。
- `Debug-Deobfuscation.Wpf.ps1` 与 `Review-RoundReplay.Wpf.ps1` 依赖 WPF，仅支持 Windows。
- 安装 Graphviz 的 `dot` 后可额外生成 PNG；未安装时仍可输出 DOT。

## 快速开始

> 说明：下面命令中的 `<host>` 表示当前分析宿主，可使用 `powershell.exe` 或 `pwsh`。要分析针对 PS5 的脚本请用 `powershell.exe`；要分析针对 PS7+ 的脚本请用 `pwsh`。

```powershell
# 1) 一键多轮解混淆（推荐主入口）
<host> -NoProfile -File .\Rebuild-Deobfuscated.ps1 -ScriptPath .\in\in.ps1

# 2) 调试模式（逐节点执行 + 人工改变量）
<host> -NoProfile -Sta -File .\Debug-Deobfuscation.Wpf.ps1 -ScriptPath .\in\in.ps1

# 3) 复盘已有 round 日志
<host> -NoProfile -Sta -File .\Review-RoundReplay.Wpf.ps1 -WorkDir .\in\in.rebuilt.ps1.work -Round 1
```

## 混合解混策略

### 1) 动态部分

- 已执行到的 CFG 节点，优先使用真实执行结果回写。
- 变量读取位点会尽量记录简单类型结果，并参与替换候选生成。
- 节点执行失败时，会留下失败记录；如果 CFG 还能继续，则继续向后跑。

### 2) 静态部分

- 对未执行分支，不再完全放弃；会额外扫描 AST，尝试还原“简单类型表达式”的结果。
- 当前静态还原重点覆盖：
  - 字符串、可展开字符串、`char`
  - `bool`、`$null`
  - 常见整数 / 浮点 / `decimal`
  - 安全的类型转换、括号表达式、一部分数组/子表达式包装
  - 字符串上下文中的 `+`、`-join`、`-f`
- 当未知变量只出现在**字符串兼容上下文**中时，可临时按空字符串参与静态求值；这类候选会标记为低置信度。

### 3) 自动应用规则

- 动态候选默认视为高置信度，可参与自动替换。
- 静态高置信候选默认可参与自动替换。
- 静态低置信候选（例如依赖“未知变量按空字符串处理”）会保留在候选中，但默认**不自动应用**，并在 report 中以 `static_low_confidence` 归因。
- 重叠片段仍由 `OverlapStrategy`（`Inner` / `Outer`）控制。

### 4) 静态限制

以下 AST 目前不作为静态替换的目标，或只做保守处理：

- 可能有副作用的一元操作（如 `++` / `--`）
- 成员访问 / 方法调用
- 索引访问
- 复杂 pipeline
- 可能依赖运行时环境的命令调用

## 如何阅读 CFG

这一工具的 CFG 不是“按源码原样画语句块”，而是会把部分 PowerShell 结构**降级成更适合执行与复盘的中间控制流**。因此看到一些不是 PowerShell AST 原名的节点类型是正常的。

### 1) 先区分三类节点

| 类别 | 常见 Type | 说明 |
| --- | --- | --- |
| 结构节点 | `Start` / `End` / `MainStart` / `MainEnd` / `If Condition` / `Else` / `Merge` / `Default` / `Try` / `Catch` / `Finally` / `LoopStart` / `LoopEnd` / `SwitchStart` / `SwitchEnd` / `FuncStart` / `FuncEnd` / `BlockStart` / `BlockEnd` | 主要用于表达 CFG 结构、入口出口、汇合点或子图边界。调试模式下这类节点大多会自动略过。 |
| 条件节点 | `Condition` / `ForEachCondition` / `ProcessCondition` / `SwitchCondition` / `CaseCondition` | 真正负责做布尔判断，并决定走哪条边。 |
| 执行节点 | `PipelineElement` / `ForInit` / `ForIter` / `ForEachInit` / `ForEachBind` / `ForEachIter` / `ProcessInit` / `ProcessBind` / `ProcessIter` / `ProcessEnd` / `SwitchInit` / `SwitchBind` / `SwitchIter` / `Return` / `Break` / `Continue` / `Throw` / `Exit` / `AssignmentStatementAst` / `DynamicTranslation` | 会真正执行表达式、赋值、跳转或调用子图。 |

补充：
- `OutputCaptureStart` / `OutputCaptureEnd` 也是执行器专用结构节点，用于临时缓存并回收一段子流程的输出。
- 在调试 UI 里，如果你觉得“有些节点一闪而过”，通常就是因为它们属于结构节点。

### 2) 哪些控制流会被特殊处理

| 原始结构 | CFG 中的典型展开 | 为什么会长得“不像源码” |
| --- | --- | --- |
| `if / elseif / else` | `If Condition` → `Condition` → 分支体 → `Merge` / `Else` | `If Condition` 只是结构入口，真正求值的是各个 `Condition` 节点。 |
| `for / while / do-while / do-until` | `LoopStart` + `Condition` + `ForInit` / `ForIter` + `LoopEnd` | 为了让 `break` / `continue` 有明确跳转目标，会显式建循环头尾和迭代节点。 |
| `foreach ($x in ...)` | `LoopStart` → `ForEachInit` → `ForEachCondition` → `ForEachBind` → 循环体 → `ForEachIter` → 回到 `ForEachCondition` | `foreach` 会被降级成“集合 + 索引”的显式迭代器，因此会看到内部集合/索引变量。 |
| `switch (...) { ... }` | `SwitchStart` → `SwitchInit` → `SwitchCondition` → `SwitchBind` → 多个 `CaseCondition` / `Default` → `SwitchIter` → `SwitchEnd` | 当前实现把 `switch` 对齐为“逐元素遍历 + case 判断”，这样 `break` / `continue` / `$_` 都更容易统一处理。 |
| 显式 `process {}` 块 | `ProcessInit` → `ProcessCondition` → `ProcessBind` → 主体 → `ProcessIter` → `ProcessEnd` | `process` 会被视为按输入流逐项执行的隐式循环。 |
| 管道里的 `ForEach-Object` | 会被展开成一套类似 `process` 的迭代图，还会出现 `OutputCaptureStart` / `OutputCaptureEnd` | 为了保留 begin/process/end 语义、输出聚合以及 `break` / `continue` 行为。 |
| 条件、参数默认值、表达式中的嵌套 pipeline | 会先插入若干 `PipelineElement` 节点，再把结果喂给真正的条件/参数节点 | 所以你会看到一段 pipeline 先执行，然后才进入 `Condition` 或参数节点。 |
| `try / catch / finally` | `Try` / `Catch` / `Finally` + 特殊出口重连 | 这是为了正确处理异常路径、`return`、`break`、`continue` 和 finally 收尾。 |
| `function Foo { ... }` | 主图里保留 `FunctionDef`，函数体拆成 `FuncStart` → `FuncEnd` 子图 | 定义与调用被分离；定义点不等于执行点。 |
| 脚本块 `{ ... }` | 根据场景拆成 `BlockStart` → `BlockEnd` 子图，主图里通常改成 `_block_xxx` 或赋值目标变量引用 | 这样延迟执行、管道传值、显式调用都能统一处理。 |
| `iex` / `[ScriptBlock]::Create(...)` / `NewScriptBlock(...)` | 运行时动态生成 `BlockStart` / `BlockEnd` 子图，必要时插入 `DynamicTranslation` 节点 | 动态代码不是一开始就存在于静态 CFG 里，而是在执行时追加进去。 |

补充：
- `Where-Object`、`Select-Object` 目前通常仍保留为 `PipelineElement`，但执行器会做额外语义处理。
- `switch` / `process` / `ForEach-Object` 之所以“图比较复杂”，本质上都是为了把“隐式逐项处理”变成可回放、可调试的显式控制流。

### 3) 哪些情况会产生内部变量

| 前缀 / 名称 | 何时产生 | 作用 | 默认可见性 |
| --- | --- | --- | --- |
| `_pipe_<id>` | 多元素 pipeline、或嵌套 pipeline 被提前展开时 | 保存上一个 pipeline 元素的输出，供下一个元素继续消费 | 默认显示（`pipe#xxxx`） |
| `__proc_input` | 函数 / 脚本块内部存在显式 `process {}`，调用时注入输入 | 作为 `process` 伪循环的原始输入集合 | 默认显示（`process.input`） |
| `__prc_<id>` | 显式 `process {}` 被降级成迭代结构时 | 保存 process 输入集合 | 高级内部变量 |
| `__prc_<id>_idx` | 同上 | process 当前索引 | 默认显示（`process.index#xxxx`） |
| `__prc_<id>_current` | 同上 | process 当前元素 | 默认显示（`process.current#xxxx`） |
| `__fe_<id>` | `foreach` 被降级成集合+索引迭代时 | 保存 foreach 集合 | 高级内部变量 |
| `__fe_<id>_idx` | 同上 | foreach 当前索引 | 默认显示（`foreach.index#xxxx`） |
| `__sw_<id>` | `switch` 被降级成逐元素遍历时 | 保存 switch 输入集合 | 高级内部变量 |
| `__sw_<id>_idx` | 同上 | switch 当前索引 | 默认显示（`switch.index#xxxx`） |
| `__sw_<id>_current` | 同上 | switch 当前匹配元素，`case` 体里的 `$_` / `$PSItem` 会对齐到它 | 默认显示（`switch.current#xxxx`） |
| `__pfo_in_<id>` | `ForEach-Object` 被完全展开时 | 保存进入 `ForEach-Object` 的输入集合 | 高级内部变量 |
| `__pfo_<id>_idx` | 同上 | `ForEach-Object` 当前索引 | 默认显示（`pfo.index#xxxx`） |
| `__pfo_<id>_cur` | 同上 | `ForEach-Object` 当前元素 | 默认显示（`pfo.current#xxxx`） |
| `__pfo_<id>_out` | 同上 | 聚合 begin/process/end 输出，最后回写给 `_pipe_<id>` | 高级内部变量 |
| `_sc_<id>_<name>` | 进入函数 / 脚本块调用作用域时 | 用于给局部变量加执行作用域前缀，避免和外层变量冲突 | 高级内部变量 |
| `_block_<id>` 或脚本块赋值目标变量名 | 延迟执行脚本块、管道值脚本块、cmdlet 参数脚本块被拆成子图时 | 主图里用它引用对应 `BlockStart` 子图 | 默认隐藏 |
| `_dyn_<id>` | 动态代码在运行时被解析成新脚本块时 | 引用运行时新建的动态子图 | 默认隐藏 |
| `_foreach_out_...` / `_where_out_...` / `_select_out_...` | 执行器为某些 pipeline cmdlet 结果回填赋值时临时创建 | 只是短生命周期临时变量，执行后通常立即删除 | 一般无需关注 |

说明：
- 不是所有内部变量都会长期留在变量栈里；有些只是执行器瞬时使用的临时变量。
- 默认变量栈重点展示“对调试有帮助”的内部变量；更底层的 `_block_` / `_dyn_` / `_sc_` 等通常默认隐藏。
- 如果看到 `$_` 在某些结构里没有直接出现，往往是因为它已经被 CFG 规范化成了 `switch.current#xxxx`、`pfo.current#xxxx`、`process.current#xxxx` 这类内部变量。

### 4) 哪些东西会被拆成子图

| 场景 | 子图边界 | 说明 |
| --- | --- | --- |
| 主脚本 | `Start` → `MainStart` ... `MainEnd` → `End` | 整个脚本本身也有一层“主图”边界。 |
| 函数定义 | `FuncStart` → `FuncEnd` | 主图里只保留 `FunctionDef` 结构节点；真正执行函数体时才跳进函数子图。 |
| 延迟 / 独立脚本块 | `BlockStart` → `BlockEnd` | 主图里通常只看到 `_block_xxx` 或赋值变量；块体本身在独立子图中。 |
| 动态生成代码 | 运行时 `BlockStart` → `BlockEnd` | `iex` / `ScriptBlock::Create` 等在执行时才补出这类子图。 |

阅读建议：
- **先看主图**：判断当前是在主脚本、函数、脚本块还是动态子图里。
- **再看节点类型**：如果是 `LoopStart` / `SwitchStart` / `FuncStart` / `BlockStart` 这类节点，优先把它理解为“结构边界”，不要当成普通语句。
- **最后看内部变量**：看到 `_pipe_` / `__sw_` / `__fe_` / `__pfo_` 时，先想它们对应的是哪种“隐式迭代”或“管道中间结果”。

### 5) `Capture Process Output` 是什么

如果在 CFG 或复盘 UI 里看到：
- `Capture Begin Output`
- `Capture Process Output`
- `Capture End Output`
- `Append ... Output`

它们通常来自 **`ForEach-Object` 完全展开** 的过程。

作用是：
1. 先把 begin/process/end 某一段逻辑产生的输出临时收集起来；
2. 再在对应的 `Append ... Output` 节点统一追加到聚合变量；
3. 最终把聚合结果回写给外层 pipeline 继续流动。

所以这类节点不是“用户源码里真的写了一句 capture”，而是执行器为了正确模拟 `ForEach-Object` 输出语义而显式插入的辅助节点。

## 参数说明

### 1) `Rebuild-Deobfuscated.ps1`（主入口）

```powershell
<host> -NoProfile -File .\Rebuild-Deobfuscated.ps1 -ScriptPath .\target.ps1 [options]
```

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `-ScriptPath` | 必填 | 输入脚本路径。 |
| `-OutPath` | `<ScriptPath>.rebuilt.ps1` | 最终输出脚本路径。 |
| `-WorkDir` | `<OutPath>.work`（仅 `FullOutput=$true`） | 每轮过程产物目录；`FullOutput=$false` 时忽略。 |
| `-FullOutput` | `$true` | `true`：保留每轮 in/out/log/report/cfg；`false`：只输出最终脚本。 |
| `-OverlapStrategy` | `Inner` | 重叠片段选择策略：`Inner`（优先内层）/ `Outer`（优先外层）。 |
| `-VariableConflictPolicy` | `skip` | 变量位点多值策略：`skip`（跳过变化变量）/ `last`（取最后一次可用简单值）。 |
| `-MaxRounds` | `5` | 最大迭代轮数。 |
| `-MaxIterations` | `1000` | 单轮 CFG 执行迭代上限（防死循环）。 |
| `-MaxTotalNodes` | `50000` | 单轮最大节点访问数上限。 |
| `-GlobalTimeBudgetMs` | `120000` | 单次重建全过程的总预算；`0` 表示不限制。 |
| `-DynamicTimeBudgetMs` | `15000` | 单次动态 payload 展开的预算；`0` 表示不限制。 |
| `-SafeMode` | `$true` | `true`：保留全部高风险提前停止规则；`false`：仅关闭 `Network+IEX` 与 `Network+Sleep` 两条误伤研究样本的规则。 |
| `-DryRun` | `$false` | 仅运行分析与统计，不写最终输出文件。 |

这一入口现在采用**动态 + 静态混合策略**，不再是单纯“把执行结果回写到脚本”。每轮大致流程为：

1. 运行 CFG，收集动态结果。
2. 扫描当前脚本文本，收集静态候选。
3. 合并动态/静态候选并处理重叠。
4. 默认跳过静态低置信候选。
5. 通过语法保护后写出 `roundNN.out.ps1`。

补充：
- 若某轮 `AppliedCount = 0`，该轮会视为已收敛并停止，通常不会保留“空替换轮次”的完整产物。
- 若启用 `-FullOutput:$true`，round 文件按 `round01.*`、`round02.*` 这种两位编号输出。
- round report 会额外区分 `DynamicCount`、`StaticHighCount`、`StaticLowCount`。
- 最终写出前会统一做一次语法校验；若当前结果语法无效，会回退到最后一个语法有效版本，而不是直接输出坏脚本。
- `SafeMode=$false` 不是完全关闭保护，只是放宽对无害化研究样本最常见的两条误伤规则。

常用示例：

```powershell
# 高性能模式（不落盘每轮过程）
<host> -NoProfile -File .\Rebuild-Deobfuscated.ps1 -ScriptPath .\in\in.ps1 -FullOutput:$false

# 值变化变量采用“最后值”
<host> -NoProfile -File .\Rebuild-Deobfuscated.ps1 -ScriptPath .\in\in.ps1 -VariableConflictPolicy last

# 保守策略：变化变量一律跳过（默认）
<host> -NoProfile -File .\Rebuild-Deobfuscated.ps1 -ScriptPath .\in\in.ps1 -VariableConflictPolicy skip

# 研究评测模式：放宽对 Network+IEX / Network+Sleep 的提前停止
<host> -NoProfile -File .\Rebuild-Deobfuscated.ps1 -ScriptPath .\in\in.ps1 -SafeMode:$false
```

### 2) `Debug-Deobfuscation.Wpf.ps1`（交互调试）

```powershell
<host> -NoProfile -Sta -File .\Debug-Deobfuscation.Wpf.ps1 -ScriptPath .\target.ps1 [options]
```

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `-ScriptPath` | 必填 | 目标脚本路径。 |
| `-WorkDir` | `<ScriptPath>.debug.work` | 调试输出目录。 |
| `-OverlapStrategy` | `Inner` | 预览 / 导出时的重叠片段策略：`Inner` / `Outer`。 |
| `-MaxIterations` | `1000` | 调试会话执行迭代上限。 |
| `-MaxTotalNodes` | `50000` | 调试会话最大节点访问上限。 |
| `-NoUI` | `$false` | 无界面模式，只输出初始化摘要。 |

调试产物（在 `WorkDir`）：
- `debug.execution.log`
- `debug.cfg.dot` / `debug.cfg.png`
- `debug.out.ps1`
- `debug.report.json`

调试模式的重要变化：

- 预览同样采用**动态 + 静态混合策略**。
- 预览会在以下时机自动重算：
  - 初始化加载后
  - 单步执行后
  - `Run All` 后
  - 手动应用变量后
- 节点替换表会显示 `来源` / `置信`，用于区分 `Dynamic` / `Static` 以及 `High` / `Low`。
- 即使某一步执行失败，只要 CFG 还能继续，UI 仍可继续推进并保留失败记录。
- 未执行分支也会尝试做静态还原，因此预览通常比“只看执行路径”更完整。

### 3) `Review-RoundReplay.Wpf.ps1`（round 复盘）

```powershell
<host> -NoProfile -Sta -File .\Review-RoundReplay.Wpf.ps1 [options]
```

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `-WorkDir` | 交互选择 | `Rebuild-Deobfuscated.ps1` 生成的 `*.work` 目录。`-NoUI` 时必填。 |
| `-Round` | 交互选择（`NoUI` 下默认最新轮） | 要复盘的轮次编号。 |
| `-CheckpointInterval` | `200` | 变量状态 checkpoint 间隔；越小跳转越快，但内存占用更高。 |
| `-NoUI` | `$false` | 无界面模式，只解析并输出摘要。 |

复盘模式的重要变化：

- round 选择界面会读取 `roundNN.report.json` 摘要，显示每轮的 `candidates / applied / skipped`。
- 即使目录中只有 1 个 round，点击“更改 round”时仍会正常弹出选择界面，而不是直接关闭。
- 支持按 `CheckpointInterval` 回放变量状态，适合定位第 2 轮、第 3 轮这类多轮问题。

## 调试变量栈与手动补变量

调试模式新增了“把缺失变量补进去再继续跑”的能力，用来处理测试环境中拿不到真实上下文的脚本。

### 1) 变量栈展示分级

| 分级 | 默认显示 | 说明 |
| --- | --- | --- |
| `User` | 是 | 用户脚本中的普通变量。 |
| `DefaultInternal` | 是 | 常用内部变量，适合调试时观察，如 pipeline 当前项、`foreach`/`switch` 常用游标。 |
| `AdvancedInternal` | 否 | 更底层的内部集合/作用域辅助变量，需勾选“高级内部变量”后才显示。 |
| `HiddenInternal` | 否 | 默认不显示；通常仅在 API 侧使用 `-IncludeInternal` 时查看。 |

默认可见的内部变量示例：
- `pipeline.current`
- `process.input`
- `process.index#xxxx`
- `process.current#xxxx`
- `pfo.index#xxxx`
- `pfo.current#xxxx`
- `switch.index#xxxx`
- `switch.current#xxxx`
- `foreach.index#xxxx`

高级内部变量示例（需勾选“高级内部变量”）：
- `process.collection#xxxx`
- `pfo.input#xxxx`
- `pfo.output#xxxx`
- `switch.collection#xxxx`
- `foreach.collection#xxxx`
- `$name @scope#xxxx` 这类作用域快照变量

### 2) 缺失变量占位行

- 如果某个变量在当前会话里尚不存在，但工具判断它可能需要人工补值，会在变量栈中显示占位行：`(missing; set manually)`。
- 这意味着你可以先手动输入，再继续单步或 `Run All`。
- 这对于依赖 `$MyInvocation`、环境变量、外部输入等上下文的混淆脚本尤其有用。

### 3) 手动赋值规则

`Set-CFGVariableValue` / 调试 UI 的“应用变量”接收的是 **PowerShell 表达式**，不是纯文本。

可直接输入：

```powershell
123
'abc'
$null
''
```

说明：
- 想设置空字符串，必须输入 `''`。
- 不能留空；空白输入会报错：`ValueExpression 不能为空。`
- 如果希望变量保持“存在但为空”，应该显式输入 `''` 或 `$null`，不要把输入框留空。

### 4) 相关公开 API

```powershell
Get-CFGVariableStack -Session <hashtable> [-IncludeAdvancedInternal] [-IncludeInternal]
Set-CFGVariableValue -Session <hashtable> -VariableName <string> -ValueExpression <string>
Get-CFGExecutionFailures -Session <hashtable>
```

其中：
- `-IncludeAdvancedInternal`：额外显示高级内部变量。
- `-IncludeInternal`：显示全部内部变量（包括默认隐藏项）。
- `Get-CFGExecutionFailures`：读取“失败但继续”的记录，便于 UI 或外部脚本分析。

## 失败继续（Failure-Tolerant Execution）

执行器现在支持“记录失败，但尽量继续”：

- 当某个节点执行失败且拿到错误信息时，会生成 failure record。
- failure record 会保存：失败节点、失败动作、原因、错误文本、是否继续、继续到哪个节点、使用了哪条边。
- 若 CFG 可以确定后继节点，执行器会记录 `[CONTINUE]` 并继续执行。
- 这让工具可以在存在局部异常（例如测试环境缺失上下文、故意抛错、路径探测失败）的情况下，仍尽量解混后续片段。

## 报告与输出文件

### 1) `roundNN.report.json`

`Rebuild-Deobfuscated.ps1` 的每轮 report 现在除了传统的 `CandidateCount / AppliedCount / SkippedCount`，还会补充：

- `DynamicCount`
- `StaticHighCount`
- `StaticLowCount`
- `SkippedByReason`
- `Applied[].SourceKind`
- `Applied[].Confidence`
- `Applied[].UsedEmptyFallback`
- `Applied[].Executed`
- `Applied[].ResultType`

这些字段可以帮助区分：
- 某轮到底主要是靠动态还是静态在推进
- 是否有大量低置信静态候选被跳过
- 实际应用的片段是否来自未执行分支

### 2) `debug.report.json`

调试导出结果同样会记录：

- `StaticHighCount`
- `StaticLowCount`
- `Selected[].SourceKind`
- `Selected[].Confidence`
- `Selected[].UsedEmptyFallback`
- `Selected[].Executed`
- `Selected[].ResultType`

因此调试导出不再只是“当前执行到哪一步”，而是“当前动态状态 + 静态补全预览”的结果快照。

## 参数组合推荐模板

### 模板 1：保守解混（推荐默认起手）

适用：
- 先保证语义稳定，尽量避免误替换。

```powershell
<host> -NoProfile -File .\Rebuild-Deobfuscated.ps1 `
  -ScriptPath .\in\in.ps1 `
  -OverlapStrategy Inner `
  -VariableConflictPolicy skip `
  -MaxRounds 5 `
  -FullOutput:$true
```

特点：
- 变化变量直接跳过（`skip`），风险最低。
- 保留完整 round 产物，便于复盘。
- 静态低置信候选仍默认不自动应用。

### 模板 2：激进解混（优先还原更多内容）

适用：
- 你接受一定误替换风险，想尽量还原更多片段。

```powershell
<host> -NoProfile -File .\Rebuild-Deobfuscated.ps1 `
  -ScriptPath .\in\in.ps1 `
  -OverlapStrategy Inner `
  -VariableConflictPolicy last `
  -MaxRounds 10 `
  -FullOutput:$true
```

特点：
- 变化变量允许回写最后值（`last`）。
- 轮次更高，适合多层混淆递归剥离。

### 模板 3：高性能批处理（只要最终结果）

适用：
- 批量脚本快速跑，不需要过程文件和图。

```powershell
<host> -NoProfile -File .\Rebuild-Deobfuscated.ps1 `
  -ScriptPath .\in\in.ps1 `
  -FullOutput:$false `
  -MaxRounds 10 `
  -VariableConflictPolicy skip
```

特点：
- 不写 round 日志 / report / cfg，速度和 IO 最优。
- 仅输出最终 `.rebuilt.ps1`。

### 模板 4：预评估模式（只看统计不落最终结果）

适用：
- 先评估可替换规模，再决定是否真正输出。

```powershell
<host> -NoProfile -File .\Rebuild-Deobfuscated.ps1 `
  -ScriptPath .\in\in.ps1 `
  -DryRun `
  -FullOutput:$true `
  -VariableConflictPolicy skip
```

特点：
- 会跑分析和 round 统计，但不会写最终 `OutPath` 文件。

### 模板 5：交互调试模式（逐节点控制）

适用：
- 需要人工介入改变量、选分支、手选替换片段。

```powershell
<host> -NoProfile -Sta -File .\Debug-Deobfuscation.Wpf.ps1 `
  -ScriptPath .\in\in.ps1 `
  -OverlapStrategy Inner `
  -MaxIterations 1000 `
  -MaxTotalNodes 50000
```

特点：
- 可以在失败后继续推进。
- 可以补缺失变量，再继续执行。
- 可同时观察动态结果与未执行分支的静态预览。

### 模板 6：Round 复盘模式（回看执行细节）

适用：
- 已有 `*.work`，需要按节点回放与排错。

```powershell
<host> -NoProfile -Sta -File .\Review-RoundReplay.Wpf.ps1 `
  -WorkDir .\in\in.rebuilt.ps1.work `
  -Round 1 `
  -CheckpointInterval 200
```

## Generate / Execute 公开函数参数

### `Generate-CFG.ps1`

1. `Get-ScriptControlFlow -ScriptPath <string>`
2. `Export-CfgToDot -finalCFG <hashtable> [-outputPath <string>] [-AppliedNodeIds <int[]>]`

说明：
- `-AppliedNodeIds` 用于标记“实际发生替换”的节点（高亮）。
- `Export-CfgToDot` 会尝试调用 `dot` 生成 PNG；若不可用只保留 DOT。

### `Execute-CFG.ps1`

1. `Invoke-CFGTraversal -CFG <hashtable> [-LogPath <string>] [-MaxIterations <int>] [-MaxTotalNodes <int>]`
2. `New-CFGExecutionSession -CFG <hashtable> [-LogPath <string>] [-MaxIterations <int>] [-MaxTotalNodes <int>]`
3. `Invoke-CFGStep -Session <hashtable> [-StopAtUserNode]`
4. `Get-CFGVariableStack -Session <hashtable> [-IncludeAdvancedInternal] [-IncludeInternal]`
5. `Set-CFGVariableValue -Session <hashtable> -VariableName <string> -ValueExpression <string>`
6. `Get-CFGNextEdgePreview -Session <hashtable>`
7. `Get-CFGExecutionFailures -Session <hashtable>`
8. `Close-CFGExecutionSession -Session <hashtable>`

## 目录结构

- `Generate-CFG.ps1`：CFG 生成与可还原片段识别。
- `Execute-CFG.ps1`：CFG 执行器（批量执行 + 调试会话 API + 失败记录 + 变量栈）。
- `Rebuild-Deobfuscated.ps1`：多轮重建主入口（动态 + 静态混合策略）。
- `Debug-Deobfuscation.Wpf.ps1`：交互式调试 UI（逐步执行、补变量、静态预览）。
- `Review-RoundReplay.Wpf.ps1`：round 复盘 UI。
- `in/`：输入脚本与测试样例目录。



