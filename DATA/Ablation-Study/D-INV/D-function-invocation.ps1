function Emit-Url {
    param(
        [string]$Scheme,
        [string]$Domain,
        [string]$Path,
        [string]$File
    )

    $url = $Scheme + '://' + $Domain + $Path + '/' + $File
    Write-Host $url
}

Emit-Url 'http' 'noise.local' '/stage' 'decoy.dat'
Emit-Url ('ht' + 'tps') ('example' + '.org') ('/api' + '/v1') ('update' + '.bin')
