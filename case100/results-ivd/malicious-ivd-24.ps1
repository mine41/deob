Function Invoke-SSIDExfil {
    [CmdletBinding()]
    Param(
        [switch]${eXFIloNLy} , 
        [switch]${DECoDe} , 
        [String]${stRinGTOexFIlTRAtE} , 
        [String]${StRiNGtOdecoDE} 
    )

    Function ConvertTo-ROT13 {
        Param([String]${INputsTrING} )

        ${BUiLDeR} = & ("{3}{2}{0}{1}" -f 'Obj' , 'ect' , '-' , 'New') System.Text.StringBuilder
        ForEach (${Char} In ${inputSTRinG}.tochararray()) {
            ${coDe} = [int][Char]${chAr} 
            Switch (${CoDE} ) {
                {
                    ${_} -ge 65 -And ${_} -le 90 }
                {
                    [Void]${Builder}.append([Char](((${_} - 65 + 13) % 26) + 65))
                    Continue 
                }
                {
                    ${_} -ge 97 -And ${_} -le 122 }
                {
                    [Void]${BUIlDR}.append([Char](((${_} - 97 + 13) % 26) + 97))
                    Continue 
                }
                default {
                    [Void]${BUILDEr}.append(${ChAr} )
                }
            }
        }

        Return ${BUILdEr}.ToString()
    }

    ${ArtiFaCTDir} = .("{2}{0}{1}" -f 'Pa' , 'th' , 'Join-') ${PSScRiPtRoOt} "artifacts\ssid-exfil"
    If ( -Not (.("{0}{1}" -f 'Test-' , 'Path') ${aRTiFAcTdir} )) {
        ${Null} = & ("{2}{1}{0}" -f 'tem' , 'ew-I' , 'N') -ItemType Directory -Path ${artIFAcTDiR} -Force
    }

    If (${DecodE} ) {
        ${DeCODeD} = & ("{3}{0}{2}{1}" -f 'o' , 'rtTo-ROT13' , 'nve' , 'C') -inputstring ${sTRINgtODCoDE} 
        & ("{0}{1}{3}{2}" -f 'Write' , '-O' , 'ut' , 'utp') "[safe] Decoded value: $decoded"
        Return 
    }

    If (${exFIlonlY} ) {
        ${pLAINTEXt} = ${sTRINGTOEXfILTraTE} 
    }
    Else {
        ${PlAiNTeXt} = "LAB:alice:hello"
    }

    If ([String]::IsNullOrWhiteSpace(${plaINTEXt} )) {
        Throw "StringToExfiltrate cannot be empty."
    }

    If (${PlaInteXt}.length -gt 32) {
        Throw "The simulated SSID payload must be 32 characters or fewer."
    }

    ${SSIdnaMe} = & ("{3}{1}{2}{0}" -f 'T13' , 'on' , 'vertTo-RO' , 'C') -inputstring ${PlAiNTExT} 
    ${LOGpATh} = .("{0}{1}{2}" -f 'J' , 'oin' , '-Path') ${ARTIFactDIr} "ssid-actions.txt"
    ${CommaNDS} = @(
        "[safe] Would run: netsh wlan set hostednetwork mode=allow ssid=""$ssidName"" key='HardtoGuess!@#123'" , 
        "[safe] Would run: netsh wlan start hostednetwork" , 
        "[safe] Plaintext source: $plainText" , 
        "[safe] ROT13 SSID: $ssidName"
    )

    .("{2}{0}{1}" -f 'C' , 'ontent' , 'Set-') -Path ${logPath} -Value ${ComMANdS} -Encoding UTF8

    & ("{3}{1}{2}{0}" -f 'ut' , '-Out' , 'p' , 'Write') "[safe] Simulated SSID exfiltration value: $ssidName"
    & ("{2}{3}{0}{1}" -f 'utp' , 'ut' , 'W' , 'rite-O') "[safe] Actions logged to $logPath"
}

.("{2}{1}{0}{3}" -f 'k' , 'o' , 'Inv' , 'e-SSIDExfil') -exfilonly -stringtoexfiltrate "LAB:alice:hello"
