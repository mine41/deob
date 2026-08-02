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

$runner.invoke('http' , 'noise.local' , '/stage' , 'decoy.dat')
$runner.invoke(('https') , ('example.org') , ('/api/v1') , ('update.bin'))