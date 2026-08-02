$parts = ([System.Object[]]([string]'https://', [string]'example.org', [string]'/api/v1', [string]'/update.bin'))
$url = ([string]'')
foreach ($part in $parts)
{
    $url = $url + $part
}
Write-Output ([string]'https://example.org/api/v1/update.bin')
