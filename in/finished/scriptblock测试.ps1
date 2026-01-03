#1.&调用
# 直接执行
# & { Write-Host "使用 & 执行" 
# $x = 10
# Write-Host "x 的值是 $x"
# if ($x -eq 10) {
#     write-Host "x 等于 10"
# }
# }

# # 带参数
# & { param($name) "Hello, $name" } -name "World"

# # 执行变量中的脚本块
# $block = { param($name) "Hello, $name" }
# & $block -name "World"

#2 .执行
# 在**当前作用域**执行
# $x = 10
# . { 
#     $x = 20  # 修改当前作用域的变量
#     Write-Host "点源中: x = $x"
# }
# Write-Host "点源后: x = $x"  # x 现在是 20

#3.invoke-command 执行
# 基本执行
# Invoke-Command -ScriptBlock { "Hello" }

# # 带参数
# Invoke-Command -ScriptBlock { param($a, $b) $a + $b } -ArgumentList 5, 3

# # 远程执行
# Invoke-Command -ComputerName localhost -ScriptBlock { Get-Process }

# # 并行执行
# Invoke-Command -ScriptBlock { Start-Sleep 2; "完成" } -ThrottleLimit 5

#4.invoke-expression 执行
# 执行字符串
# Invoke-Expression 'Write-Host "Hello"'

# # 也可以执行脚本块
# Invoke-Expression -Command { Get-Date }

# iex 'Write-Host "Hello"'

#5.方式5：使用 $()子表达式
# 在字符串中执行
# "当前时间: $({ Get-Date } | ForEach-Object { & $_ })"

# # 在表达式内
# $result = $( & { 1 + 2 + 3 } )

#使用 New-Object创建委托
# 创建并执行委托
# $delegate = [ScriptBlock]::Create('"委托执行"')
# $method = $delegate.GetType().GetMethod("Invoke", [reflection.bindingflags]"Public, Instance")
# $method.Invoke($delegate, $null)

#6. 管道执行
# function Pipeline-Execution {
#     Write-Host "=== 管道执行 ===" -ForegroundColor Cyan
    
#     # 方式1: 直接管道执行
#     1..5 | & { process { "处理: $_" } }
    
#     Write-Host "`n方式2: 脚本块作为管道源" -ForegroundColor Yellow
#     & { 1; 2; 3; 4; 5 } | ForEach-Object { "接收: $_" }
    
#     Write-Host "`n方式3: 脚本块作为管道处理器" -ForegroundColor Yellow
#     $processor = { process { "处理: $($_ * 2)" } }
#     1..3 | & $processor
# }

# Pipeline-Execution

#7.反射执行
# function Reflection-Execution {
#     Write-Host "=== 反射执行 ===" -ForegroundColor Cyan
    
#     $scriptBlock = { "通过反射执行" }
    
#     # 获取 Invoke 方法
#     $method = $scriptBlock.GetType().GetMethod("Invoke")
    
#     # 执行0
#     $result = $method.Invoke($scriptBlock, @())
#     Write-Host "结果: $result" -ForegroundColor Green
    
#     # 带参数的反射执行
#     $paramBlock = { param($a, $b) $a + $b }
#     $paramMethod = $paramBlock.GetType().GetMethod("Invoke", [Type[]]@([object[]]))
#     $paramResult = $paramMethod.Invoke($paramBlock, @(, @(5, 3)))
#     Write-Host "5 + 3 = $paramResult" -ForegroundColor Green
# }

# Reflection-Execution

# #1 单一 pipeline + scriptblock
# 1..3 | ForEach-Object { $_ }

# #2 scriptblock 中顺序语句
# 1..2 | ForEach-Object {
#     $x = $_
#     $x
# }

# #3 scriptblock 中 if
# 1..3 | ForEach-Object {
#     if ($_ -gt 1) { $_ }
# }

# #4 if / else 分支
# 1..2 | ForEach-Object {
#     if ($_ -eq 1) { 10 } else { 20 }
# }

# #5 scriptblock 内再次使用 pipeline
# 1..2 | ForEach-Object {
#     $_ | Write-Output
# }

# #6 内层 pipeline + 条件
# 1..3 | ForEach-Object {
#     $_ | Where-Object { $_ -gt 1 }
# }

# #7 scriptblock 作为值返回
# $a = { 1 }
# $a | ForEach-Object { & $_ }

# #8 scriptblock 中立即执行 scriptblock
# 1..2 | ForEach-Object {
#     & { $_ }
# }

# #9 条件包裹 pipeline
# if ($true) {
#     1..2 | ForEach-Object { $_ }
# }

# #10 pipeline 中条件执行
# 1..3 | ForEach-Object {
#     if ($_ -eq 2) { return }
#     $_
# }

# #11 scriptblock 中定义 scriptblock 并执行
# 1..2 | ForEach-Object {
#     $b = { $_ }
#     & $b
# }

# #12 多层 scriptblock 嵌套
# 1..2 | ForEach-Object {
#     & { & { $_ } }
# }

# #13 scriptblock 中 continue
# 1..3 | ForEach-Object {
#     if ($_ -eq 2) { continue }
#     $_
# }

# #14 scriptblock 中 break
# 1..3 | ForEach-Object {
#     if ($_ -eq 2) { break }
#     $_
# }

# #15 pipeline + 嵌套 if + scriptblock
# 1..3 | ForEach-Object {
#     if ($_ -gt 1) {
#         & { $_ }
#     }
# }

# #16 pipeline → scriptblock → pipeline
# 1..2 | ForEach-Object {
#     & { $_ | Write-Output }
# }
