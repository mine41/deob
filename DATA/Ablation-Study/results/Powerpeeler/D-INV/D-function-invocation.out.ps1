function Emit-Url
{
    param(
        [string]$Scheme,
        [string]$Domain,
        [string]$Path,
        [string]$File
    )
    $url = $Scheme + '://' + $Domain + $Path + '/' + $File
    Write-Host $url
}
Emit-Url ([string]'http') ([string]'noise.local') ([string]'/stage') ([string]'decoy.dat')<#$Null#>
Emit-Url ([string]'https') ([string]'example.org') ([string]'/api/v1') ([string]'update.bin')<#$Null#>
