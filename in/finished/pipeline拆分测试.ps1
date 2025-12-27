# # Pipeline 测试用例
# 100 | ForEach-Object {
#     $_++
#     Write-Host $_
# }

# # 1. 基本 pipeline
# Get-Process | Where-Object { $_.CPU -gt 100 }

# # 2. 多段 pipeline
# Get-Service | Where-Object { $_.Status -eq 'Running' } | Select-Object Name, Status | Sort-Object Name

# # 3. 赋值语句中的 pipeline
# $result = Get-Process | Where-Object { $_.Name -eq 'powershell' } | Select-Object -First 1

# # 4. 变量赋值 pipeline 结果
# $services = Get-Service | Sort-Object Status

# # 5. if 条件中的 pipeline
# if ((Get-Process | Measure-Object).Count -gt 10) {
#     Write-Host "Many processes"
# }
# elseif ($true) {
#     Write-Host "Other condition"   
# }
# else {
# }

# # 6. if 语句体内的 pipeline
# if ($true) {
#     Get-ChildItem | Where-Object { $_.Length -gt 1MB } | Remove-Item
# }

# # 7. foreach 中的 pipeline
# foreach ($item in (Get-ChildItem | Where-Object { $_.PSIsContainer })) {
#     Write-Host $item.Name
# }

# # 8. for 循环体内的 pipeline
# for ($i = 0; $i -lt 3; $i++) {
#     Get-Process | Select-Object -First $i
# }

# for ($i = 0; $i -lt (Get-Process | Measure-Object).Count; $i++) {
#     Get-Process | Select-Object -First $i
# }

# # 9. while 条件中的 pipeline
# while ((Get-Process | Where-Object { $_.Name -eq 'notepad' }).Count -gt 0) {
#     Start-Sleep -Seconds 1
# }

# # 10. while 循环体内的 pipeline
# while ($true) {
#     Get-Service | Restart-Service
#     break
# }

# # 11. do-while 中的 pipeline
# do {
#     $procs = Get-Process | Where-Object { $_.CPU -gt 50 }
# } while ((Get-Process | Measure-Object).Count -gt 0)

# # 12. do-until 中的 pipeline
# do {
#     Get-EventLog -LogName System | Select-Object -First 10
# } until ((Get-Process | Measure-Object).Count)

# # 13. switch 中的 pipeline
# switch ((Get-Date | Select-Object -ExpandProperty DayOfWeek)) {
#     'Monday' { Get-Process | Stop-Process }
#     'Friday' { Get-Service | Start-Service }
#     default { Get-ChildItem | Remove-Item }
# }

# # 14. try 块中的 pipeline
# try {
#     Get-Content "file.txt" | Set-Content "backup.txt"
# } catch {
#     Write-Host "Error"
# }

# # 15. catch 块中的 pipeline
# try {
#     throw "error"
# } catch {
#     write-Host $_
#     100 | ForEach-Object { write-Host $Error[0] }
# }

# # 16. finally 块中的 pipeline
# try {
#     Get-Process
# } finally {
#     Get-Service | Stop-Service
# }

# # 17. 函数内的 pipeline
# function Test-Pipeline {
#     Get-Process | Where-Object { $_.Name -like "p*" } | ForEach-Object { $_.Kill() }
# }

# # 18. 函数参数默认值中的 pipeline
# function Get-FirstProcess {
#     param(
#         $DefaultProc = (Get-Process | Select-Object -First 1)
#     )
#     return $DefaultProc
# }

# # 19. 函数返回 pipeline
# function Get-RunningServices {
#     return Get-Service | Where-Object { $_.Status -eq 'Running' }
# }

# # 20. 嵌套函数中的 pipeline
# function Outer {
#     function Inner {
#         Get-ChildItem | Measure-Object
#     }
#     Inner | Select-Object Count
# }

# # 21. ScriptBlock 中的 pipeline!!!!!!!!!!!!
# $scriptBlock = {
#     Write-Host "xixi"
#     Get-Process | Sort-Object CPU -Descending | Select-Object -First 5
# }

# # 22. Invoke-Command 中的 pipeline!!!!!!!!!!!!!!
# Invoke-Command -ScriptBlock {
#     Get-Service | Where-Object { $_.StartType -eq 'Automatic' }
# }

# # 23. ForEach-Object 嵌套 pipeline!!!!!!!!!!
# Get-ChildItem | ForEach-Object {
#     Write-Host "xixi"
#     Get-Content $_.FullName | Select-String "pattern"
# }

# # 24. Where-Object 嵌套 pipeline!!!!!!!!!!!!!!!!!!!
# Get-Process | Where-Object {
#     ($_ | Get-Member).Count -gt 10
# }

# # 25. 数组中的 pipeline
# $array = @(
#     (Get-Process | Select-Object -First 1),
#     (Get-Service | Select-Object -First 1)
# )

# # 26. 哈希表中的 pipeline
# $hash = @{
#     Processes = (Get-Process | Measure-Object)
#     Services = (Get-Service | Measure-Object)
# }

# # 27. 三元运算符中的 pipeline (PowerShell 7+)
# $result = $true ? (Get-Service | Get-Process | Select-Object -First 1) : (Get-Service | Select-Object -First 1)

# # 28. 子表达式中的 pipeline
# Write-Host "Count: $((xxx | get-service | Get-Process | Measure-Object).Count)"

# # 29. 数组子表达式中的 pipeline
# $items = @(xx | Get-ChildItem | Where-Object { $_.Length -gt 0 })

# # 30. pipeline 作为命令参数
# Write-Host (Get-Process | Select-Object -First 1 | Select-Object -ExpandProperty Name)

# # 31. 多行 pipeline（反引号续行）
# Get-Process `
#     | Where-Object { $_.CPU -gt 10 } `
#     | Sort-Object CPU `
#     | Select-Object -First 5

# # 32. 管道符后换行的 pipeline
# Get-Service |
#     Where-Object { $_.Status -eq 'Running' } |
#     Select-Object Name

# # 33. 复杂嵌套: if 内 foreach 内 pipeline
# if ($true) {
#     foreach ($svc in (Get-Service | Where-Object { $_.Status -eq 'Stopped' })) {
#         $svc | Start-Service
#     }
# }

# # 34. try-catch-finally 全部包含 pipeline
# try {
#     Get-Content "data.txt" | ConvertFrom-Json | ForEach-Object { $_.Name }
# } catch {
#     $_ | Format-List | Out-String | Write-Host
# } finally {
#     Get-Process | Where-Object { $_.Name -eq 'cleanup' } | Stop-Process
# }

# # 35. switch 的每个分支都有 pipeline
# $day = Get-Date | Select-Object -ExpandProperty DayOfWeek
# switch ($day) {
#     { $_ -in 'Saturday','Sunday' } {
#         Get-Process | Stop-Process -WhatIf
#     }
#     'Monday' {
#         Get-Service | Restart-Service -WhatIf
#     }
#     default {
#         Get-ChildItem | Remove-Item -WhatIf
#     }
# }

# # 36. pipeline 带有输出重定向
# Get-Process | Out-File "processes.txt"
# Get-Service | Export-Csv "services.csv"

# # 37. pipeline 赋值给多个变量
# $a, $b, $c = Get-Process | Select-Object -First 3

# # 38. pipeline 在比较表达式中
# if ((Get-Process | Measure-Object).Count -eq (Get-Service | Measure-Object).Count) {
#     Write-Host "Equal"
# }

# # 39. pipeline 在逻辑表达式中 ！！！！！！！！！！！！！！！！！！
# if ((Get-Process | Where-Object { $_.Name -eq 'notepad' }) -and (Get-Service | Where-Object { $_.Name -eq 'Spooler' })) {
#     Write-Host "Both exist"
# }

# # 40. 单独的 pipeline 语句（无赋值）
# Get-EventLog -LogName Application -Newest 10 | Format-Table | Out-Host
