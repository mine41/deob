Function Emit-Url {
    Param(
        [String]$Scheme , 
        [String]$Domain , 
        [String]$Path , 
        [String]$File 
    )

    $url = $Scheme + '://' + $Domain + $Path + '/' + $File 
    Write-Host $url 
}

emit-url 'http' 'noise.local' '/stage' 'decoy.dat'
emit-url ('https') ('example.org') ('/api/v1') ('update.bin')