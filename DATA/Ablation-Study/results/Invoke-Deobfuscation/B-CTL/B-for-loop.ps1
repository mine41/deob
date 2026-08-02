$parts = @(@('https://' , 'example' , '.org' , '/api' , '/v1' , '/update' , '.bin'))
$url = ''

For ($i = 0; $i -lt $parts.count; $i ++ ) {
    $url = $url + $parts[$i]
}

Write-Output $url