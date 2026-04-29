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
        $builder = .("{1}{2}{0}" -f 't','N','ew-Objec') System.Text.StringBuilder
        foreach ($char in $InputString.("{1}{0}{2}"-f'r','ToCha','Array').Invoke()) {
            $code = [int][char]$char
            switch ($code) {
                { $_ -ge 65 -and $_ -le 90 } {
                    [void]$builder."a`pPEND"([char]((($_ - 65 + 13) % 26) + 65))
                    continue
                }
                { $_ -ge 97 -and $_ -le 122 } {
                    [void]$builder."A`p`pEND"([char]((($_ - 97 + 13) % 26) + 97))
                    continue
                }
                default {
                    [void]$builder.("{0}{2}{1}"-f 'A','end','pp').Invoke($char)
                }
            }
        }
        return $builder.("{2}{0}{1}" -f'i','ng','ToStr').Invoke()
    }
    $artifactDir = &("{3}{2}{0}{1}"-f 't','h','Pa','Join-') $PSScriptRoot "artifacts\ssid-exfil"
    if (-not (&("{1}{0}{2}" -f '-','Test','Path') $artifactDir)) {
        $null = &("{2}{1}{0}" -f'em','It','New-') -ItemType Directory -Path $artifactDir -Force
    }
    if ($Decode) {
        $decoded = &("{0}{1}{2}{3}{4}"-f'C','onv','er','tTo-','ROT13') -InputString $StringToDecode
        .("{2}{1}{0}"-f'-Output','te','Wri') "[safe] Decoded value: $decoded"
        return
    }
    if ($ExfilOnly) {
        $plainText = $StringToExfiltrate
    }
    else {
        $plainText = "LAB:alice:hello"
    }
    if ([string]::("{2}{4}{5}{0}{1}{3}"-f'Or','W','IsN','hiteSpace','u','ll').Invoke($plainText)) {
        throw "StringToExfiltrate cannot be empty."
    }
    if ($plainText."l`En`gTH" -gt 32) {
        throw "The simulated SSID payload must be 32 characters or fewer."
    }
    $ssidName = &("{1}{4}{0}{3}{2}"-f'R','Co','13','OT','nvertTo-') -InputString $plainText
    $logPath = &("{1}{2}{0}" -f'th','Join','-Pa') $artifactDir "ssid-actions.txt"
    $commands = @(
        "[safe] Would run: netsh wlan set hostednetwork mode=allow ssid=`"$ssidName`" key='HardtoGuess!@#123'",
        "[safe] Would run: netsh wlan start hostednetwork",
        "[safe] Plaintext source: $plainText",
        "[safe] ROT13 SSID: $ssidName"
    )
    &("{0}{2}{1}" -f'Set-Cont','t','en') -Path $logPath -Value $commands -Encoding UTF8
    .("{1}{2}{3}{0}" -f'put','Write-O','u','t') "[safe] Simulated SSID exfiltration value: $ssidName"
    .("{3}{2}{0}{1}" -f'Out','put','te-','Wri') "[safe] Actions logged to $logPath"
}
.("{2}{0}{4}{3}{1}" -f 'nvok','l','I','Exfi','e-SSID') -ExfilOnly -StringToExfiltrate "LAB:alice:hello"
