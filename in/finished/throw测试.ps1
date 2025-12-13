# # Throw��K�(�
# # 1. 不在try-catch中的throw
# Write-Host "Before throw"
# throw "Basic error"
# Write-Host "This will never execute"

# # 2. Try-Catch中的Throw
# try {
#     Write-Host "In try block"
#     throw "Exception in try"
#     Write-Host "This will not execute"
# }
# catch {
#     Write-Host "Caught exception: $_"
# }
# Write-Host "After try-catch"

# # 2.1 特定catch中的Throw
# try {
#     Write-Host "In try block"
#     # throw "Exception in try"
#     Write-Host "This will not execute"
# }
# catch [System.DivideByZeroException]  {
#     Write-Host "Caught exception: $_"
# }
# catch [System.ArgumentException] {
#     Write-Host "Caught general exception: $_"
# }
# finally {
#     <#Do this after the try block regardless of whether an exception occurred or not#>
#     Write-Host "Finally block"
# }
# Write-Host "After try-catch"

# # 2.2 没有catch的throw
# try {
#     Write-Host "In try block"
#     throw "Exception in try"
#     exit
#     Write-Host "This will not execute"
# }
# finally {
#     <#Do this after the try block regardless of whether an exception occurred or not#>
#     Write-Host "Finally block"
# }
# Write-Host "After try-catch"


# # 3. 循环中的Throw
# try {
#     for ($i = 0; $i -lt 3; $i++) {
#         Write-Host "Loop iteration $i"
#         if ($i -eq 1) {
#             throw "Exception in loop"
#         }
#         Write-Host "After throw check $i"
#     }
# }
# catch {
#     Write-Host "Caught loop exception: $_"
# }

# # 4. If语句中的Throw
# try {
#     $x = 5
#     if ($x -gt 3) {
#         throw "Value too large"
#     }
#     Write-Host "Value is acceptable"
# }
# catch {
#     Write-Host "Caught if-throw exception: $_"
# }

# # 5. Switch语句中的Throw
# try {
#     $value = "invalid"
#     switch ($value) {
#         "valid" { Write-Host "Valid case" }
#         default { throw "Invalid value: $value" }
#     }
# }
# catch {
#     Write-Host "Caught switch-throw exception: $_"
# }

# # # 6. 嵌套Try-Catch中的Throw 
# try {
#     try {
#         Write-Host "1. try块开始" -ForegroundColor Cyan
#         throw "try中的异常"
#         Write-Host "这行不会执行" -ForegroundColor Red
#     }
#     finally {
#         Write-Host "3. finally块开始" -ForegroundColor Yellow
#         Write-Host "4. finally中抛出异常" -ForegroundColor Red
#         throw "finally中的异常"
#         Write-Host "这行不会执行" -ForegroundColor Red
#     }
#     Write-Host "try-finally之后" -ForegroundColor Gray
# }
# catch {
#     Write-Host "5. 外层catch捕获: $($_.Exception.Message)" -ForegroundColor Green
#     # 注意：这里捕获到的是finally中的异常！
# }
# finally{
#     throw "外层finally中的异常"
# }

# # 7. 多个Throw语句
# try {
#     Write-Host "Testing multiple throws"
#     $condition = $true
#     if ($condition) {
#         throw "First exception"
#     }
#     throw "This will never be reached"
# }
# catch {
#     Write-Host "Caught: $_"
# }

# 8. 外层catch中rethrow（无更外层try）
# try {
#     Write-Host "Outer try start"
#     throw "outer try exception"
# }
# catch {
#     Write-Host "In outer catch, rethrowing..."
#     throw  # 这里 rethrow，应该直接终止脚本，而不是再被当前 try 捕获
# }
# Write-Host "After outer catch rethrow"  # 理论上不可达

# 9. catch中rethrow
# try {
#     try {
#         throw "inner exception"
#     }
#     catch {
#         Write-Host "Inner catch, rethrow"
#         throw
#     }
# }
# catch {
#     Write-Host "Outer catch got: $($_.Exception.Message)"
#     throw
# }
# Write-Host "After outer catch"

# 10. finally中rethrow
# try {
#     try {
#         Write-Host "Inner try, throw"
#         throw "inner exception"
#     }
#     finally {
#         Write-Host "Inner finally, rethrow"
#         throw "inner finally exception"
#     }
# }
# finally {
#     Write-Host "Outer finally, rethrow"
#     throw "outer finally exception"
# }
# Write-Host "After outer catch"

#11. 全部rethrow
# try {
#     try {
#         Write-Host "inner try throw"
#         throw "inner try throw"
#     }
#     catch {
#         Write-Host "inner catch throw"
#         throw "inner catch throw"
#     }
#     finally {
#         Write-Host "inner finally throw"
#         throw "inner finally throw"
#     }
#     Write-Host "outer try throw"
#     throw "outer catch throw"
# }
# catch {
#     Write-Host "outer catch throw"
#     throw "outer catch throw"
# }
# finally {
#     Write-Host "outer finally throw"
#     throw "outer finally throw"
# }

