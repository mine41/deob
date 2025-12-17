# 测试变量收集的各种场景

# 1. 数组索引赋值
$arr = @(1,2,3)
$arr[0] = 10

# 2. 属性赋值
$obj = [PSCustomObject]@{ Name = "test" }
$obj.Name = "modified"

# 3. 管道变量
1..3 | ForEach-Object { $result = $_ }

# 4. 自动变量
$x = $true
$y = $null
$z = $args
