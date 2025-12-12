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
#     throw "Exception in try"
#     Write-Host "This will not execute"
# }
# catch [System.DivideByZeroException]  {
#     Write-Host "Caught exception: $_"
# }
# catch [System.ArgumentException] {
#     Write-Host "Caught general exception: $_"
# }
# Write-Host "After try-catch"

# # 2.2 没有catch的throw
# try {
#     Write-Host "In try block"
#     throw "Exception in try"
#     Write-Host "This will not execute"
# }
# finally {
#     <#Do this after the try block regardless of whether an exception occurred or not#>
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

# # 6. 嵌套Try-Catch中的Throw 
# try {
#     try {
#         Write-Host "Inner try"
#         throw "Inner exception"
#     }
#     catch [System.InvalidOperationException] {
#         Write-Host "Specific catch - won't catch this"
#     }
# }
# catch {
#     Write-Host "Outer catch - caught: $_"
# }

# # 7. 函数中的Throw
# function Test-FunctionThrow {
#     param($param)
#     if ($param -lt 0) {
#         throw "Parameter cannot be negative"
#     }
#     return $param * 2
# }

# try {
#     $result = Test-FunctionThrow -param -5
#     Write-Host "Result: $result"
# }
# catch {
#     Write-Host "Caught function exception: $_"
# }

# # 8. 多个Throw语句
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