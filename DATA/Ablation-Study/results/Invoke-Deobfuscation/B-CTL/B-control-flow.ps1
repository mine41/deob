Function Get-Url {
    Param(
        [String]$Prefix , 
        [String]$HostPart , 
        [String]$PathPart 
    )

    If ($Prefix ) {
        For ($i = 0; $i -lt 1; $i ++ ) {
            Return $Prefix + $HostPart + $PathPart 
        }
    }

    Return $Null 
}

$url = get-url 'https://' 'example.org' '/api/v1/update.bin'
Write-Output $url