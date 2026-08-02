$pairs = @(
    [pscustomobject]@{
        Scheme = ([string]'http')
        Domain = ([string]'noise.local')
        Path   = ([string]'/stage')
        File   = ([string]'decoy.dat')
    }
    [pscustomobject]@{
        Scheme = ([string]'https')
        Domain = ([string]'example.org')
        Path   = ([string]'/api/v1')
        File   = ([string]'update.bin')
    }
)
$pairs | ForEach-Object {
    $url = $_.Scheme + '://' + $_.Domain + $_.Path + '/' + $_.File
    Write-Host $url
}
