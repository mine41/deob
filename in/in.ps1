$i = 0
do {
    Write-Output $i
    if ($i -eq 2) { 
        continue
        Write-Output "Break" 
    }
    $i++
} while ($i -lt 5)
Write-Output "Done"