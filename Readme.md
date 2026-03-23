# Readme.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

这是一个 PowerShell 脚本反混淆分析工具，大致流程为：
1.生成CFG，并查找其中的可还原表达式。
2.维护一个变量栈和共享的执行上下文，遍历cfg，对每个节点使用invoke执行，同时记录每次执行时变量的值和可还原表达式的值。
3.执行完成后，将脚本对应的片段替换为记录的值。若同一片段被执行多次对应了多个值，则放弃替换。

## 常用命令

```powershell
# 运行分析（分析 in/in.ps1 并生成控制流图）
pwsh run.ps1

# 生成 PNG 可视化（需要 Graphviz）
dot -Tpng in/in.dot -o in/in.png
```

## 代码架构

### 核心模块: Generate-CFG.ps1

这是项目的核心（4000+ 行），包含所有分析逻辑。主要功能模块：

**AST 处理**
- `Get-Ast` - 解析 PowerShell 脚本为 AST
- `Get-DynamicInvokeInfo` - 检测动态执行结构 (iex, ScriptBlock::Create)

**控制流图构建**
- `Add-Node`, `Add-Edge`, `Add-VarToNode` - CFG 基础操作
- `Get-ScriptControlFlow` - 生成完整控制流图（主入口函数）
- `Export-CfgToDot` - 导出为 GraphViz DOT 格式

**控制结构转换** (Convert-*AstNode 系列)
- `Convert-IfAstNode`, `Convert-SwitchAstNode` - 条件结构
- `Convert-LoopStatement` - 循环结构 (for/foreach/while/do)
- `Convert-TryAstNode` - try/catch/finally 结构
- `Convert-FunctionDefinitionAst` - 函数定义
- `Convert-PipelineAstNode` - 管道表达式

**变量和别名分析**
- `Populate-NodeVariableUsage` - 填充节点变量使用信息
- `Populate-NodeResolvables` - 填充可还原表达式
- `Populate-NodeAliasUsage` - 填充别名使用信息
- `Get-AliasDefinitionFromCommand` - 提取别名定义

**嵌套结构处理**
- `Expand-NestedScriptBlocks`, `Expand-NestedPipelines` - 展开嵌套结构
- `Convert-ScriptBlockBody`, `Convert-ScriptBlockDefinition` - 脚本块转换

### 数据流

```
PowerShell 脚本 → AST 解析 → 控制流图构建 → 变量追踪 → 别名识别 → 可还原表达式 → DOT/PNG 输出
```

## 目录结构

- `in/` - 测试输入文件目录
  - `in.ps1` - 当前分析的脚本
  - `in.dot`, `in.png` - 生成的控制流图
  - `finished/` - 已完成的测试用例（8 个文件覆盖各种语言特性）
- `run.ps1` - 主运行脚本
- `ast.ps1` - AST 工具脚本

## 开发约定

- 所有代码和注释使用中文
- 测试用例放在 `in/finished/` 目录
- 分析目标脚本放在 `in/in.ps1`

## 用法（必须用 pwsh）

  pwsh -NoProfile -File .\Rebuild-Deobfuscated.ps1 -ScriptPath .\in\in.ps1

  常用参数：

  # 迭代最多 10 轮，内层优先（更细粒度）
  pwsh -NoProfile -File .\Rebuild-Deobfuscated.ps1 -ScriptPath .\target.ps1 -MaxRounds 10 -OverlapStrategy Inner

  # 指定工作目录（每轮的 in/out/log/report 都在这里）
  pwsh -NoProfile -File .\Rebuild-Deobfuscated.ps1 -ScriptPath .\target.ps1 -WorkDir .\out\work

  ## 输出约定

  - 默认输出脚本：与输入同目录，命名为 原名.rebuilt.ps1
  - 默认工作目录：<OutPath>.work
  - 每轮会生成：
      - round01.in.ps1 / round01.out.ps1
      - round01.execution.log
      - round01.report.json（含 applied/skipped 统计与明细）