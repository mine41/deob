$parts = ([System.Object[]]([string]'https://', [string]'example', [string]'.org', [string]'/api', [string]'/v1', [string]'/update', [string]'.bin'))
$url = ([string]'')
for ($i = ([int]0); $i -lt $parts.Count; $i++)
{
    $url = $url + $parts[$i]
}
Write-Output ([string]'https://example.org/api/v1/update.bin')
