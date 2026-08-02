$pairs = @(
    [pscustomobject]@{
        Scheme = 'http'
        Domain = 'noise.local'
        Path = '/stage'
        File = 'decoy.dat'
    }
    [pscustomobject]@{
        Scheme = (([string]'https'))
        Domain = (([string]'example.org'))
        Path = (([string]'/api/v1'))
        File = (([string]'update.bin'))
    }
)

$pairs | ForEach-Object {
    $url = $_.Scheme + '://' + $_.Domain + $_.Path + '/' + $_.File
    Write-Host $url
}
