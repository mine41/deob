$pairs = @(
    [pscustomobject]@{
        scheme = 'http'
        domain = 'noise.local'
        path = '/stage'
        file = 'decoy.dat'
    }
    [pscustomobject]@{
        scheme = 'https'
        domain = 'example.org'
        path = '/api/v1'
        file = 'update.bin'
    }
)

$pairs | ForEach-Object {
    $url = $_.scheme + '://' + $_.domain + $_.path + '/' + $_.file
    Write-Host $url 
}