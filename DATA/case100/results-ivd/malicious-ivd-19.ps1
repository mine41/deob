Function iNvOke-SsIDEXFiL {
    [CmdletBinding()]
    Param(
        [switch]$ExfilOnly , 
        [switch]$Decode , 
        [String]$StringToExfiltrate , 
        [String]$StringToDecode 
    )

    Function coNVeRtTO-rOt13 {
        Param([String]$InputString )

        $builder = New-Object SystEM.txT.strInGBUILDer
        ForEach ($char In $InputString.tochararray()) {
            $code = [int][Char]$char 
            Switch ($code ) {
                {
                    $_ -ge 65 -And $_ -le 90 }
                {
                    [Void]$builder.append([Char]((($_ - 65 + 13) % 26) + 65))
                    Continue 
                }
                {
                    $_ -ge 97 -And $_ -le 122 }
                {
                    [Void]$builder.append([Char]((($_ - 97 + 13) % 26) + 97))
                    Continue 
                }
                default {
                    [Void]$builder.append($char )
                }
            }
        }

        Return $builder.ToString()
    }

    $artifactDir = Join-Path $PSScriptRoot "artifacts\ssid-exfil"
    If ( -Not (Test-Path $artifactDir )) {
        $Null = New-Item -ItemType direcTOry -Path $artifactDir -Force
    }

    If ($Decode ) {
        $decoded = convertto-rot13 -inputstring $StringToDecode 
        Write-Output "[safe] Decoded value: $decoded"
        Return 
    }

    If ($ExfilOnly ) {
        $plainText = $StringToExfiltrate 
    }
    Else {
        $plainText = "LAB:alice:hello"
    }

    If ([String]::IsNullOrWhiteSpace($plainText )) {
        Throw "StringToExfiltrate cannot be empty."
    }

    If ($plainText.length -gt 32) {
        Throw "The simulated SSID payload must be 32 characters or fewer."
    }

    $ssidName = convertto-rot13 -inputstring $plainText 
    $logPath = Join-Path $artifactDir "ssid-actions.txt"
    $commands = @(
        "[safe] Would run: netsh wlan set hostednetwork mode=allow ssid=""$ssidName"" key='HardtoGuess!@#123'" , 
        "[safe] Would run: netsh wlan start hostednetwork" , 
        "[safe] Plaintext source: $plainText" , 
        "[safe] ROT13 SSID: $ssidName"
    )

    Set-Content -Path $logPath -Value $commands -Encoding uTF8

    Write-Output "[safe] Simulated SSID exfiltration value: $ssidName"
    Write-Output "[safe] Actions logged to $logPath"
}

invoke-ssidexfil -exfilonly -stringtoexfiltrate "LAB:alice:hello"
