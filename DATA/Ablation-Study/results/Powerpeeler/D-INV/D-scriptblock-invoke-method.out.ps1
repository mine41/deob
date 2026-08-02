$runner = ([scriptblock] {
        param(
            [string]$Scheme,
            [string]$Domain,
            [string]$Path,
            [string]$File
        )
        $url = $Scheme + '://' + $Domain + $Path + '/' + $File
        Write-Host $url
    })
([System.Collections.ObjectModel.Collection[psobject]]@())
([System.Collections.ObjectModel.Collection[psobject]]@())
