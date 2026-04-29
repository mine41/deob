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

        $builder = .("{1}{2}{0}" -f 't' , 'N' , 'ew-Objec') System.Text.StringBuilder
        ForEach ($char In $InputString.("{1}{0}{2}" -f 'r' , 'ToCha' , 'Array').invoke()) {
            $code = [int][Char]$char 
            Switch ($code ) {
                {
                    $_ -ge 65 -And $_ -le 90 }
                {
                    [Void]$builder."apPEND"([Char]((($_ - 65 + 13) % 26) + 65))
                    Continue 
                }
                {
                    $_ -ge 97 -And $_ -le 122 }
                {
                    [Void]$builder."AppEND"([Char]((($_ - 97 + 13) % 26) + 97))
                    Continue 
                }
                default {
                    [Void]$builder.("{0}{2}{1}" -f 'A' , 'end' , 'pp').invoke($char )
                }
            }
        }

        Return $builder.("{2}{0}{1}" -f 'i' , 'ng' , 'ToStr').invoke()
    }

    $artifactDir = & ("{3}{2}{0}{1}" -f 't' , 'h' , 'Pa' , 'Join-') $PSScriptRoot "artifacts\ssid-exfil"
    If ( -Not ( & ("{1}{0}{2}" -f '-' , 'Test' , 'Path') $artifactDir )) {
        $Null = & ("{2}{1}{0}" -f 'em' , 'It' , 'New-') -ItemType Directory -Path $artifactDir -Force
    }

    If ($Decode ) {
        $decoded = & ("{0}{1}{2}{3}{4}" -f 'C' , 'onv' , 'er' , 'tTo-' , 'ROT13') -inputstring $StringToDecode 
        .("{2}{1}{0}" -f '-Output' , 'te' , 'Wri') "[safe] Decoded value: $decoded"
        Return 
    }

    If ($ExfilOnly ) {
        $plainText = $StringToExfiltrate 
    }
    Else {
        $plainText = "LAB:alice:hello"
    }

    If ([String]::("{2}{4}{5}{0}{1}{3}" -f 'Or' , 'W' , 'IsN' , 'hiteSpace' , 'u' , 'll').invoke($plainText )) {
        Throw "StringToExfiltrate cannot be empty."
    }

    If ($plainText."lEngTH" -gt 32) {
        Throw "The simulated SSID payload must be 32 characters or fewer."
    }

    $ssidName = & ("{1}{4}{0}{3}{2}" -f 'R' , 'Co' , '13' , 'OT' , 'nvertTo-') -inputstring $plainText 
    $logPath = & ("{1}{2}{0}" -f 'th' , 'Join' , '-Pa') $artifactDir "ssid-actions.txt"
    $commands = @(
        "[safe] Would run: netsh wlan set hostednetwork mode=allow ssid=""$ssidName"" key='HardtoGuess!@#123'" , 
        "[safe] Would run: netsh wlan start hostednetwork" , 
        "[safe] Plaintext source: $plainText" , 
        "[safe] ROT13 SSID: $ssidName"
    )

    & ("{0}{2}{1}" -f 'Set-Cont' , 't' , 'en') -Path $logPath -Value $commands -Encoding UTF8

    .("{1}{2}{3}{0}" -f 'put' , 'Write-O' , 'u' , 't') "[safe] Simulated SSID exfiltration value: $ssidName"
    .("{3}{2}{0}{1}" -f 'Out' , 'put' , 'te-' , 'Wri') "[safe] Actions logged to $logPath"
}

.("{2}{0}{4}{3}{1}" -f 'nvok' , 'l' , 'I' , 'Exfi' , 'e-SSID') -exfilonly -stringtoexfiltrate "LAB:alice:hello"
