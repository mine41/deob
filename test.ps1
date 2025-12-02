# 生成最小测试文件
$testDot = @"
digraph G {
    a -> b;
}
"@
[System.IO.File]::WriteAllText("test.dot", $testDot, [System.Text.Encoding]::ASCII)
dot -Tpng test.dot -o test.png