# $e = 2
# switch ($e) {
#     1 { $f = "one" }
#     2 { $f = "two"; break }
#     3 { $f = "three" }
#     default { $f = "default" }
# }

# switch(1..3) {
#     1 { $f += "-one" 
#     write-Host $_}
#     2 { $f += "-two" 
#     write-Host $_}
#     3 { $f += "-three" }
# }

$value = 15

switch ($value) {
    { $_ -lt 10 }  { "$_ 小于 10" }
    default { "$_ 是其他数字" }
}