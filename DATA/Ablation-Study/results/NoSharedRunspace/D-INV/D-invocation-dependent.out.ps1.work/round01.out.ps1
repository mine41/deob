$runner = {
    param(
        [string]$Scheme,
        [string]$Domain,
        [string]$Path,
        [string]$File
    )

    $url = $Scheme + '://' + $Domain + $Path + '/' + $File
    Write-Host $url
}

& {
    param(
        [string]$Scheme,
        [string]$Domain,
        [string]$Path,
        [string]$File
    )

    $url = ([string]'://') + $Domain + $Path + '/' + $File
    Write-Host $url
} 'http' 'noise.local' '/stage' 'decoy.dat'
& {
    param(
        [string]$Scheme,
        [string]$Domain,
        [string]$Path,
        [string]$File
    )

    $url = ([string]'://') + $Domain + $Path + '/' + $File
    Write-Host $url
} (https) (example.org) (/api/v1) (update.bin)
