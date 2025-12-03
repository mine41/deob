#测试用文件
# # 一、普通
# $fruit = "Apple"

# switch ($fruit) {
#     "Apple"  { Write-Host "It's a red fruit." }
#     "Banana" { Write-Host "It's a yellow fruit." }
#     "Orange" { Write-Host "It's an orange fruit." }
#     default  { Write-Host "I don't know this fruit." }
# }

# # 二、数组
# switch (1, 2, 3) {
#     1 { "one" }
#     2 { "two" }
#     3 { "three" 
#     write-host "This will not be executed"
# }
# }

# Write-Host "Done"

# #三、break continue
# switch (1, 2, 3, 4, 5) {
#     1 { "one" }
#     2 { "two"; break ; "This will not be executed" }
#     3 { "three"; continue ; "This will not be executed" }
#     4 { "four" }
#     5 { "five" }
# }

# 四、-wildcard通配符匹配
# $file = "report.pdf"

# switch -Wildcard ($file) {
#     "*.txt"  { "这是一个文本文件" }
#     "*.pdf"  { "这是一个PDF文档" }
#     "*.xls*" { "这是一个Excel文件 (xlsx, xls)" } # 匹配 .xlsx 和 .xls
#     default  { "未知文件类型" }
# }

# 五、exit、return
# switch (1, 2, 3, 4, 5) {
#     1 { "one" }
#     2 { "two"; exit ; "This will not be executed" }
#     3 { "three"; return ; "This will not be executed" }
#     4 { "four" }
#     5 { "five" }
# }

# 六、脚本块条件和常量混用
# $value = 15

# switch ($value) {
#     { $_ -lt 10 }  { "$_ 小于 10" }
#     { $_ % 2 -eq 0 } { "$_ 是偶数" }
#     { $_ -gt 10 -and $_ -lt 20 } { "$_ 在 10 到 20 之间" } # 这个会匹配
#     15 { "$_ 是 15" }
#     default { "$_ 是其他数字" }
# }

# 七、无 default（隐式 default）
# switch (1, 2, 3) {
#     1 { "one" }
#     2 { "two" }
#     # 没有 default，当值为 3 时走隐式 default
# }

# 八、嵌套 switch
# switch (1, 2) {
#     1 {
#         switch ("a", "b") {
#             "a" { "inner a" }
#             "b" { "inner b"; break }  # 这个 break 只跳出内层
#         }
#         "after inner switch"
#     }
#     2 { "two" }
# }

# 九、switch 嵌套在循环中（测试 break/continue 的作用域）
# foreach ($i in 1..2) {
#     switch ($i) {
#         1 { "one"; continue }  # continue 影响 switch 还是 foreach？
#         2 { "two"; break }     # break 影响 switch 还是 foreach？
#     }
#     "after switch in loop"
# }

# 十、循环嵌套在 switch 中
# switch (1, 2) {
#     1 {
#         foreach ($j in 1..3) {
#             if ($j -eq 2) { break }  # 这个 break 跳出 foreach
#             "loop $j"
#         }
#         "after loop"
#     }
#     2 { "two" }
# }

# 十一、-Regex 参数
# switch -Regex ("hello123") {
#     "^\d+$"    { "pure number" }
#     "^[a-z]+$" { "pure letters" }
#     "\d+"      { "contains numbers" }  # 会匹配
#     default    { "no match" }
# }

# 十二、多个 case 匹配同一个值（fall-through 行为）
# switch (10) {
#     { $_ -gt 5 }  { "greater than 5" }   # 匹配
#     { $_ -gt 8 }  { "greater than 8" }   # 也匹配！
#     { $_ -eq 10 } { "equals 10" }        # 也匹配！
#     10            { "literal 10" }       # 也匹配！
# }

# 十三、空 case body
# switch (1, 2, 3) {
#     1 { }  # 空操作
#     2 { "two" }
#     3 { }  # 空操作
# }

# 十四、所有分支都 return/exit（无法到达 switch 后的代码）
# switch (1, 2) {
#     1 { return "one" }
#     2 { return "two" }
#     default { return "default" }
# }
# Write-Host "This should be unreachable"