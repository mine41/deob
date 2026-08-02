$parts = @(@('https://' , 'example.org' , '/api/v1' , '/update.bin'))
$url = ''

ForEach ($part In $parts ) {
    $url = $url + $part 
}

Write-Output $url