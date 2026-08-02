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

({
    param(
        [string]$Scheme,
        [string]$Domain,
        [string]$Path,
        [string]$File
    )

    $url = ([string]'http') + '://' + ([string]'noise.local') + ([string]'/stage') + '/' + ([string]'decoy.dat')
    Write-Host ([string]'http://noise.local/stage/decoy.dat')
}).Invoke('http', 'noise.local', '/stage', 'decoy.dat')
({
    param(
        [string]$Scheme,
        [string]$Domain,
        [string]$Path,
        [string]$File
    )

    $url = ([string]'https') + '://' + ([string]'example.org') + ([string]'/api/v1') + '/' + ([string]'update.bin')
    Write-Host ([string]'https://example.org/api/v1/update.bin')
}).Invoke((https), (example.org), (/api/v1), (update.bin))
