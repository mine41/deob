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

. $runner 'http' 'noise.local' '/stage' 'decoy.dat'
. $runner ('ht' + 'tps') ('example' + '.org') ('/api' + '/v1') ('update' + '.bin')
