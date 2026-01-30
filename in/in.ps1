# $e = 2
# switch ($e) {
#     1 { $f = "one" }
#     2 { $f = "two"; break }
#     3 { $f = "three" }
#     default { $f = "default" }
# }

switch(1..3) {
    1 { $f += "-one" 
    write-Host $_}
    2 { $f += "-two" 
    write-Host $_}
    3 { $f += "-three" }
}

