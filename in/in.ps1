# =========================
# 8. 最简单的无参函数 + 顶层调用
# =========================
# function Test-NoParam {
#     Write-Host "Test-NoParam: start"
#     Write-Host "Test-NoParam: end"
# }

# Write-Host "Before Test-NoParam"
# Test-NoParam
# Write-Host "After Test-NoParam"


# # =========================
# # 9. 有参数函数 + return
# # =========================
# function Test-Add {
#     param(
#         [int]$a,
#         [int]$b
#     )
#     $c = $a + $b
#     Write-Host "Test-Add: $a + $b = $c"
#     return $c
# }

# Write-Host "Before Test-Add"
# $sum = Test-Add -a 1 -b 2
# Write-Host "After Test-Add: $sum"


# # =========================
# # 10. 函数内部有 if/loop/throw/try-catch-finally
# # =========================
# function Test-Complex {
#     param([int]$n, [string]$str)
#     Write-Host "Test-Complex: start n=$n"

#     if ($n -lt 0) {
#         Write-Host "n < 0, throwing" -ForegroundColor Red
#         throw "n must be >= 0"
#     }

#     $sum = 0
#     for ($i = 0; $i -lt $n; $i++) {
#         $sum += $i
#     }

#     try {
#         Write-Host "In try, sum = $sum"
#         if ($n -eq 3) {
#             throw "Test-Complex inner error"
#         }
#         Write-Host "After possible throw"
#     }
#     catch {
#         Write-Host "Test-Complex caught: $($_.Exception.Message)" -ForegroundColor Yellow
#     }
#     finally {
#         Write-Host "Test-Complex finally" -ForegroundColor Cyan
#     }

#     Write-Host "Test-Complex: end sum=$sum"
#     return $sum
# }

# Write-Host "Call Test-Complex 2"
# Test-Complex 2

# Write-Host "Call Test-Complex 3"
# Test-Complex 3

# Write-Host "Call Test-Complex -1 (will throw uncaught)"
# try {
#     Test-Complex -1
# }
# catch {
#     Write-Host "Outer caught from Test-Complex: $($_.Exception.Message)" -ForegroundColor Green
# }


# # =========================
# # 11. 函数里 rethrow，让外层 catch
# # =========================
# function Test-Rethrow {
#     Write-Host "Test-Rethrow: start"
#     try {
#         throw "inner error"
#     }
#     catch {
#         Write-Host "Test-Rethrow: inner catch, rethrow" -ForegroundColor Yellow
#         throw  # rethrow
#     }
#     Write-Host "Test-Rethrow: this will not execute"
# }

# Write-Host "Call Test-Rethrow with outer catch"
# try {
#     Test-Rethrow
# }
# catch {
#     Write-Host "Outer got from Test-Rethrow: $($_.Exception.Message)" -ForegroundColor Green
# }


# # =========================
# # 12. 函数内部的 try-finally + finally throw
# # =========================
# function Test-Finally-Throw {
#     Write-Host "Test-Finally-Throw: start"
#     try {
#         Write-Host "Inner try"
#     }
#     finally {
#         Write-Host "Inner finally throwing" -ForegroundColor Red
#         throw "from inner finally"
#     }
#     Write-Host "After inner try/finally (unreachable)"
# }

# Write-Host "Call Test-Finally-Throw with outer catch"
# try {
#     Test-Finally-Throw
# }
# catch {
#     Write-Host "Outer caught from Test-Finally-Throw: $($_.Exception.Message)" -ForegroundColor Green
# }


# # =========================
# # 13. 嵌套函数定义 + 调用
# # =========================
# function Outer-Func {
#     Write-Host "Outer-Func: start"

#     function Inner-Func {
#         param($x)
#         Write-Host "Inner-Func: x = $x"
#         return ($x * 2)
#     }

#     Write-Host "Outer-Func: calling Inner-Func"
#     $r = Inner-Func 10
#     Write-Host "Outer-Func: Inner-Func returned $r"
#     return $r
# }

# Write-Host "Call Outer-Func"
# $resultOuter = Outer-Func
# Write-Host "Result from Outer-Func = $resultOuter"


# # =========================
# # 14. 函数里 exit（脚本级终止）
# =========================
# function Test-Exit {
#     Write-Host "Test-Exit: before exit"
#     exit  # 终止整个脚本
#     Write-Host "Test-Exit: after exit (unreachable)"
# }

# # 注意：这行调用一旦执行，会直接让脚本结束，后面的逻辑不会跑
# # 需要时再取消注释：
# Write-Host "Call Test-Exit (will terminate script)"
# Test-Exit
# Write-Host "After Test-Exit (unreachable)"


# # =========================
# # 15. 函数里 try-finally 有exit（先跑finally再退出）
# =========================
# function Test-Try-finally-exit {
#     try {
#         Write-Host "before exit"
#         Exit
#         Write-Host "after exit"
#     }
#     finally {
#         write-host "function-finally"
#     }
# }

# write-host "before xixi"
# Test-Try-finally-exit
# write-host "xixi"

# # =========================
# # 16. 函数里 try-finally 有return
# =========================
# function Test-Try-finally-return {
#     try {
#         Write-Host "before return"
#         return
#         Write-Host "after return"
#     }
#     finally {
#         write-host "function-finally"
#     }
# }

# write-host "before xixi"
# Test-Try-finally-return
# write-host "xixi"

# # =========================
# # 16. try-finally 有exception, finally之后还有
# =========================

# try {
#     Write-Host "exception"
#     return
# }
# finally {
#     Write-Host "finally"
#     write-host "xixi"
# }

# Write-Host "after finally"