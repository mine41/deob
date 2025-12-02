for ($i = 0; $i -lt 5; $i++) {
    if ($i -eq 2) { continue }
    if ($i -eq 4) { break }
    Write-Output $i
}
