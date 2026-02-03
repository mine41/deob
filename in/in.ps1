function Get-Double { param($n); return $n * 2 }
function Get-Triple { param($x); return $x * 3 }

$a = 3
$b = "hello"
$c = $a + 2         # VarsRead: $a=3
Write-Host $a       # VarsRead: $a=3
Write-Host $b       # VarsRead: $b='hello'
Write-Host $c       # VarsRead: $c=5
Write-Host (Get-Double 5)  # Inline: (Get-Double 5)=10
Write-Host (Get-Triple $a) # Inline with var: (Get-Triple $a)=9, VarsRead: $a=3

foreach ($i in 1..3) {
    Write-Host $i   # VarsRead: $i 多个值（不一致）
}

# 一致性测试
$x = 100
for ($j = 0; $j -lt 2; $j++) {
    Write-Host $x   # VarsRead: $x=100 (2次，一致)
}
