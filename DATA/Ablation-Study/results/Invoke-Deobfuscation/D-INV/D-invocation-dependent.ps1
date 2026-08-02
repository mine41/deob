$runner = {
    Param(
        [String]$Scheme , 
        [String]$Domain , 
        [String]$Path , 
        [String]$File 
    )

    $url = $Scheme + '://' + $Domain + $Path + '/' + $File 
    Write-Host $url 
}

& $runner 'http' 'noise.local' '/stage' 'decoy.dat'
& $runner ('https') ('example.org') ('/api/v1') ('update.bin')