param($n=3)

process {
    $_
}

end {
    Write-Host "n=$n"

    if ($n -gt 1) {
        2 | & $PSCommandPath ($n-1)
    }
}