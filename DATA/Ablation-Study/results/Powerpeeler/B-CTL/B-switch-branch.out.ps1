$choice = ([string]'prod')
switch ($choice)
{
    'prod'
    {
        $prefix = ([string]'https://')
        $domain = ([string]'example.org')
    }
    default
    {
        $prefix = ([string]'http://')
        $domain = ([string]'invalid.local')
    }
}
$path = ([string]'/api/v1/update.bin')
$url = ([string]'https://example.org/api/v1/update.bin')
Write-Output ([string]'https://example.org/api/v1/update.bin')
