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

@([pscustomobject]@{Scheme='http';Domain='noise.local';Path='/stage';File='decoy.dat'}) | ForEach-Object {
    $url = $_.Scheme + '://' + $_.Domain + $_.Path + '/' + $_.File
        Write-Host ([string]'http://noise.local/stage/decoy.dat')
}

@([pscustomobject]@{Scheme='https';Domain='example.org';Path='/api/v1';File='update.bin'}) | ForEach-Object {
    $url = $_.Scheme + '://' + $_.Domain + $_.Path + '/' + $_.File
        Write-Host ([string]'https://example.org/api/v1/update.bin')
}
