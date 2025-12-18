# Write-Host "==== Var Test 1: 简单赋值 ===="
# # 1. 简单赋值：左写右读
# $a = 1
# $b = $a
# $c = $a + $b

# Write-Host "==== Var Test 2: 复合赋值与一元运算 ===="
# # 2. 复合赋值：左边读+写
# $i = 0
# $i += 1
# $i -= 2
# $i *= 3
# $i /= 4

# # 2.1 一元 ++/-- ：读+写
# $j = 10
# ++$j
# $j
# $j++
# $j
# --$j
# $j
# $j--
# $j


# 3Write-Host "==== Var Test 3: 参数与函数内部变量 ===="
# function Test-Params-And-Body {
#     param(
#         [int]$p1,
#         [string]$p2
#     )

#     # p1 / p2 在 param 中应被视为 Write（绑定形参）
#     # 这里是对参数的读
#     $local1 = $p1
#     $local2 = $p2 + "_suffix"

#     # 多次读写
#     $local1 += 5
#     $local2 = $local2.ToUpper()

#     Write-Host "p1=$p1 p2=$p2 local1=$local1 local2=$local2"
# }

# Test-Params-And-Body -p1 10 -p2 "abc"

# 4 Write-Host "==== Var Test 5: if 中的变量 ===="
# $flag = $true
# $count = 0

# if ($flag -and $count -eq 0) {
#     $count = 1
# } elseif (-not $flag) {
#     $count = 2
# }
# write-host $count

#5.1 while变量
# $count = 2
# $max = 5
# while ($count -lt $max) {
#     $count++
#     write-host "555"
#     Get-Process
# }

# Write-Host "count = $count"

#5.2 do-while变量
# do{
#     Write-Host "dowhile"
# }while($a -lt 5)

#5.3 do-until变量
# do{
#     Write-Host "dowhile"
# }until($a -lt 5)

#5.4 for变量
# for ($i = 0; $i -lt 5; $i++) {
#     Write-Host $i
# }

# 5.5 Write-Host "==== foreach + 内部读写 ===="
# $numbers = 1..3
# $sum = 0
# foreach ($n in $numbers) {
#     $sum += $n
# }

# Write-Host "sum = $sum"

# Write-Host "==== Var Test 6: try/catch/finally 中的变量 ===="
# $outer = 0
# try {
#     $outer = 10
#     $inner = 1
#     $inner++
#     throw "error with outer=$outer inner=$inner"
# }
# catch [System.DivideByZeroException]  {
#     Write-Host $outer

# }
# catch {
#     # $_ 是读写哪种你暂时可以只当读，这里主要关注 $outer/$inner
#     $catchMsg = $_.Exception.Message
#     $outer = 20
# }
# finally {
#     # finally 中既读又写
#     $outer++
#     $final = $outer
#     Write-Host "in finally, outer=$outer final=$final"
# }

# Write-Host "after try/catch/finally, outer=$outer"




# Write-Host "==== Var Test 7: 嵌套函数与闭包风格 ===="
$globalX = 100

function Outer-Func {
    param([int]$x)

    $y = $x + 1

    function Inner-Func {
        param([int]$z)
        # 这里读 globalX、x、y
        $w = $globalX + $x + $y + $z
        Write-Host "Inner-Func: w=$w"
        return $w
    }

    $resultInner = Inner-Func 5
    return $resultInner
}

$outerRes = Outer-Func 3
Write-Host "Outer-Func result = $outerRes"





# Write-Host "==== Var Test 8: hashtable / array / pipeline 中的变量 ===="
# $arr = @()
# $h = @{}

# $arr += 10
# $arr += 20
# $h["k1"] = "v1"
# $h["k2"] = $arr[0]

# # pipeline 中的变量读取
# $arr | ForEach-Object {
#     $item = $_
#     Write-Host "item from arr: $item"
# }

# Write-Host "==== Var Test 9: Switch 中的变量 ===="
# $swVar = "B"

# switch ($swVar) {
#     "A" { $msg = "got A" }
#     "B" { $msg = "got B"; $swVar = "B-modified" }
# }

# Write-Host "swVar = $swVar msg = $msg"

# Write-Host "==== Var Test 10: return/exit 与变量 ===="
# function Test-Return-Var {
#     $r = 1
#     $r += 2
#     return $r
#     $r = 999    # 不可达，看看 CFG 的 VarsWritten 是否还能看到
# }

# $rv = Test-Return-Var
# Write-Host "Test-Return-Var = $rv"

# # 注意：下面这个 exit 会终止脚本，平时测试时可以注释掉
# # $exitVar = 123
# # exit
# # $exitVar = 456   # 不可达

# Write-Host "==== Var Test 11: try-finally + return/exit 混合变量 ===="
# function Test-Try-Finally-Return {
#     $t = 0
#     try {
#         $t = 1
#         return $t
#     }
#     finally {
#         $t = 2
#         $t++
#         Write-Host "finally t=$t"
#     }
# }

# $tv = Test-Try-Finally-Return
# Write-Host "Test-Try-Finally-Return result = $tv"

# Write-Host "==== Var Test 12: 复杂表达式中的变量 ===="
# $base = 10
# $result = ($base * 2) + [Math]::Pow($base, 2)
# Write-Host "result = $result"
