# 行为禁令实施总结

## 实施日期
2026-04-08

## 修改的文件
- `Execute-CFG.ps1`

## 实施的更改

### 1. 扩展了 ForbiddenCommands 列表

在两处位置更新了禁令列表（第5521行和第5682行）：

**新增的禁令类别：**
- 文件删除：`ri`, `erase`
- 文件移动/重命名：`Move-Item`, `move`, `mv`, `mi`, `Rename-Item`, `ren`, `rni`
- 网络操作：`Add-BitsFile`, `Complete-BitsTransfer`, `Test-NetConnection`, `ping`
- 进程控制：`Wait-Process`, `Debug-Process`
- 系统控制：`Suspend-Computer`, `Checkpoint-Computer`, `Restore-Computer`
- 远程执行：`Enter-PSSession`, `New-PSSession`, `Enable-PSSessionConfiguration`, `Register-PSSessionConfiguration`
- 用户交互：`Read-Host`, `Get-Credential`, `Out-GridView`
- 长时间等待：`Wait-Event`, `Wait-Job`
- 磁盘操作：`Set-Disk`, `Remove-Partition`, `Optimize-Volume`
- 其他：`Out-Printer`, `Stop-Transcript`

**总计：** 从 21 个命令扩展到约 65 个命令

### 2. 新增 Test-DangerousMethodCall 函数

位置：第4970行之后

功能：检测危险的 .NET 方法调用

**阻止的 .NET 方法类别：**
- 文件删除：`System.IO.File::Delete()`, `System.IO.Directory::Delete()`
- 文件移动：`System.IO.File::Move()`, `System.IO.FileInfo::MoveTo()`
- 网络操作：`System.Net.WebClient` 的所有下载/上传方法
- 网络连接：`System.Net.Sockets` 的所有连接方法
- 进程启动：`System.Diagnostics.Process::Start()`
- 线程睡眠：`System.Threading.Thread::Sleep()`
- 任务等待：`System.Threading.Tasks.Task::Wait()`

**总计：** 约 70 个 .NET 方法被阻止

### 3. 集成到 Invoke-NodeSafe 函数

位置：第2011行之后

在执行节点前调用 `Test-DangerousMethodCall` 检测危险方法。

### 4. 修复了 Get-NextNodes 函数的 Bug

位置：第1578行

**问题：** 当只有一个后继节点时，PowerShell 会自动解包数组，导致返回单个对象而不是数组。

**修复：** 使用逗号操作符 `return ,$nextNodes` 强制返回数组。

## 测试结果

使用 `test_simple.ps1` 测试脚本验证：

### 成功阻止的操作：
✅ `Remove-Item` - PowerShell 命令
✅ `[System.IO.File]::Delete()` - .NET 静态方法
✅ `Invoke-WebRequest` - PowerShell 命令
✅ `$wc.DownloadString()` - .NET 实例方法
✅ `Start-Process` - PowerShell 命令
✅ `[System.Diagnostics.Process]::Start()` - .NET 静态方法

### 正常执行的操作：
✅ `Get-Content` - 文件读取（允许）
✅ `[Convert]::FromBase64String()` - Base64 解码（允许）
✅ `Write-Host` - 输出（允许）

## 设计原则

### 阻止的操作（会导致解混淆悬挂或超出范围）：
1. **网络操作** - 会悬挂/超时/超出工作范围
2. **进程启动** - 会悬挂/等待
3. **文件删除/移动** - 防止删除工具本身
4. **用户交互** - 会悬挂等待输入
5. **长时间等待** - 会悬挂

### 不阻止的操作（解混淆可能需要）：
1. **文件读写** - 可能作为中间存储
2. **注册表操作** - 只是持久化，不会悬挂
3. **服务管理** - 不会悬挂
4. **计划任务** - 不会悬挂
5. **用户管理** - 不会悬挂
6. **模块加载** - 可能需要
7. **动态执行** - 解混淆核心（iex, ScriptBlock::Create）
8. **编码转换** - 解混淆核心（Base64, UTF8）

## 安全保障

虽然工具在沙箱中运行，但实施禁令的主要目的是：
1. **防止解混淆进程悬挂** - 避免网络请求、进程等待等操作导致超时
2. **防止工具自毁** - 避免恶意脚本删除解混淆工具本身
3. **保持工作范围** - 不解析额外下载的内容

## 日志示例

```
[20:36:31.616]   [BLOCKED] Forbidden command: Remove-Item (original: Remove-Item)
[20:36:31.641]   [BLOCKED] Dangerous .NET method: System.IO.File::Delete
[20:36:31.642]   [BLOCKED] Full call: [System.IO.File]::Delete("C:\temp\test2.txt")
[20:36:31.642]   [BLOCKED] Reason: Dangerous .NET static method call
```

所有被阻止的操作都会在执行日志中记录，便于分析恶意行为。
