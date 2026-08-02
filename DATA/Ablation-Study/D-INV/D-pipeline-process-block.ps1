$pairs = @(
    [pscustomobject]@{
        Scheme = 'http'
        Domain = 'noise.local'
        Path = '/stage'
        File = 'decoy.dat'
    }
    [pscustomobject]@{
        Scheme = ('ht' + 'tps')
        Domain = ('example' + '.org')
        Path = ('/api' + '/v1')
        File = ('update' + '.bin')
    }
)

$pairs | ForEach-Object {
    $url = $_.Scheme + '://' + $_.Domain + $_.Path + '/' + $_.File
    Write-Host $url
}
