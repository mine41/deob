# Try-Catch-Finally CFG Test Cases

# 一、基本 try-catch
# try {
#     Write-Host "try block"
#     $x = 1 / 0
#     Write-Host "after error"
# }
# catch {
#     Write-Host "caught"
# }

# 二、多个 catch（按类型匹配）
# try {
#     Write-Host "try"
# }
# catch [System.DivideByZeroException] {
#     Write-Host "divide by zero"
# }
# catch [System.ArgumentException] {
#     Write-Host "argument exception"
# }
# catch {
#     Write-Host "other exception"
# }

# 三、try-catch-finally
# try {
#     Write-Host "try"
#     $x = 1 / 0
# }
# catch {
#     Write-Host "catch"
# }
# finally {
#     Write-Host "finally always runs"
# }

# 四、try-finally（无 catch）
# try {
#     Write-Host "try"
#     Write-Host "no error here"
# }
# finally {
#     Write-Host "finally"
# }

# 五、catch 中有 return
# try {
#     Write-Host "try"
# }
# catch {
#     Write-Host "catch"
#     return "from catch"
# }
# finally {
#     Write-Host "finally still runs"
# }
# Write-Host "unreachable?"

# 六、try 中有 return
# try {
#     Write-Host "try"
#     return "from try"
#     Write-Host "unreachable"
# }
# catch {
#     Write-Host "catch"
# }
# finally {
#     Write-Host "finally still runs"
# }
# Write-Host "unreachable"

# 七、嵌套 try
# try {
#     Write-Host "outer try"
#     try {
#         Write-Host "inner try"
#     }
#     catch {
#         Write-Host "inner catch"
#     }
#     Write-Host "after inner try"
# }
# catch {
#     Write-Host "outer catch"
# }

# 八、try 在循环中
# foreach ($i in 1..3) {
#     try {
#         Write-Host "try $i"
#         if ($i -eq 2) { write-host "haha" }
#     }
#     catch {
#         Write-Host "catch $i"
#         continue
#     }
#     Write-Host "after try $i"
# }

# 九、循环在 try 中
# try {
#     foreach ($i in 1..3) {
#         Write-Host "loop $i"
#         if ($i -eq 2) { break }
#     }
#     Write-Host "after loop"
# }
# catch {
#     Write-Host "catch"
# }

# 十、所有 catch 都 return（不可达后续代码）
# try {
#     throw "error"
# }
# catch [System.Exception] {
#     return "exception"
# }
# catch {
#     return "all"
# }
# Write-Host "unreachable"

# 十一、空 catch 块
# try {
#     Write-Host "try"
#     throw "error"
# }
# catch {
#     # empty catch
# }
# Write-Host "after try"

# 当前测试：基本 try-catch-finally
# try {
#     Write-Host "In try"
#     $x = 1 / 0
#     Write-Host "After error"
# }
# catch [System.DivideByZeroException] {
#     Write-Host "Divide by zero"
# }
# catch {
#     Write-Host "Other error"
# }
# finally {
#     Write-Host "Finally"
# }
# Write-Host "Done"
