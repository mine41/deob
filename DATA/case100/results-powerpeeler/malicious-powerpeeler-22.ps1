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
        $builder = New-Object System.Text.StringBuilder
        foreach ($char in $InputString.("{2}{0}{1}{3}" -f 'ha','rAr','ToC','ray')."inv`okE"()) {
            $code = [int][char]$char
            switch ($code) {
                { $_ -ge 65 -and $_ -le 90 } {
                    [void]$builder."a`P`penD"([char]((($_ - 65 + 13) % 26) + 65))
                    continue
                }
                { $_ -ge 97 -and $_ -le 122 } {
                    [void]$builder."a`Ppe`ND"([char]((($_ - 97 + 13) % 26) + 97))
                    continue
                }
                default {
                    [void]$builder.("{0}{1}" -f 'Appe','nd')."I`NVO`KE"($char)
                }
            }
        }
        return $builder.("{2}{1}{0}"-f'String','o','T')."INvO`KE"()
    }
    $artifactDir = Join-Path $PSScriptRoot "artifacts\ssid-exfil"
    if (-not (Test-Path $artifactDir)) {
        $null = New-Item -ItemType Directory -Path $artifactDir -Force
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
    if ([string]::("{1}{0}{3}{2}"-f'llOrWh','IsNu','Space','ite')."INv`oke"($plainText)) {
        throw "StringToExfiltrate cannot be empty."
    }
    if ($plainText."lENG`Th" -gt 32) {
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
    Set-Content -Path $logPath -Value $commands -Encoding UTF8
    Write-Output "[safe] Simulated SSID exfiltration value: $ssidName"
    Write-Output "[safe] Actions logged to $logPath"
}
Invoke-SSIDExfil -ExfilOnly -StringToExfiltrate "LAB:alice:hello"
