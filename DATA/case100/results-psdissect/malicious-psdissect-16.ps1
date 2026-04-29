function Invoke-SSIDExfil {
    [CmdletBinding()]
    param(
        [switch]$ExfilOnly,
        [switch]$Decode,
        [string]$StringToExfiltrate,
        [string]$StringToDecode
    )

    function ConvertTo-ROT13 {
        param([string]$InputString)

        $builder = . New-Object System.Text.StringBuilder
        foreach ($char in @([char]'L', [char]'A', [char]'B', [char]':', [char]'a', [char]'l', [char]'i', [char]'c', [char]'e', [char]':', [char]'h', [char]'e', [char]'l', [char]'l', [char]'o')) {
            $code = 111
            switch (111) {
                { $_ -ge 65 -and $_ -le 90 } {
                    [void]$builder."a`pPEND"([char]((($_ - 65 + 13) % 26) + 65))
                    continue
                }
                { $_ -ge 97 -and $_ -le 122 } {
                    [void]$builder."A`p`pEND"([char]((($_ - 97 + 13) % 26) + 97))
                    continue
                }
                default {
                    [void]$builder.("{0}{2}{1}"-f 'A','end','pp').Invoke([char]':')
                }
            }
        }

        return $builder.("{2}{0}{1}" -f'i','ng','ToStr').Invoke()
    }

    $artifactDir = & Join-Path $PSScriptRoot "artifacts\ssid-exfil"
    if (-not (& Test-Path $artifactDir)) {
        $null = & New-Item -ItemType Directory -Path $artifactDir -Force
    }

    if ($Decode) {
        $decoded = &("{0}{1}{2}{3}{4}"-f'C','onv','er','tTo-','ROT13') -InputString $StringToDecode
        . Write-Output "[safe] Decoded value: $decoded"
        return
    }

    if ($True) {
        $plainText = 'LAB:alice:hello'
    }
    else {
        $plainText = "LAB:alice:hello"
    }

    if ([string]::("{2}{4}{5}{0}{1}{3}"-f'Or','W','IsN','hiteSpace','u','ll').Invoke('LAB:alice:hello')) {
        throw "StringToExfiltrate cannot be empty."
    }

    if ($False) {
        throw "The simulated SSID payload must be 32 characters or fewer."
    }

    $ssidName = 'YYYYYNNNNNOOOOO:::::nnnnnyyyyyvvvvvppppprrrrr:::::uuuuurrrrryyyyyyyyyybbbbb'
    $logPath = & Join-Path $artifactDir "ssid-actions.txt"
    $commands = @(
        '[safe] Would run: netsh wlan set hostednetwork mode=allow ssid="YYYYYNNNNNOOOOO:::::nnnnnyyyyyvvvvvppppprrrrr:::::uuuuurrrrryyyyyyyyyybbbbb" key=''HardtoGuess!@#123''',
        "[safe] Would run: netsh wlan start hostednetwork",
        '[safe] Plaintext source: LAB:alice:hello',
        '[safe] ROT13 SSID: YYYYYNNNNNOOOOO:::::nnnnnyyyyyvvvvvppppprrrrr:::::uuuuurrrrryyyyyyyyyybbbbb'
    )

    & Set-Content -Path $logPath -Value $commands -Encoding UTF8

    . Write-Output '[safe] Simulated SSID exfiltration value: YYYYYNNNNNOOOOO:::::nnnnnyyyyyvvvvvppppprrrrr:::::uuuuurrrrryyyyyyyyyybbbbb'
    . Write-Output "[safe] Actions logged to $logPath"
}

'[safe] Actions logged to '

