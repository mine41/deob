Function Invoke-SSIDExfil {
    [CmdletBinding()]
    Param(
        [switch]${EXfIlONlY} , 
        [switch]${dECodE} , 
        [String]${sTrinGToExFiLtRATe} , 
        [String]${STRINGTOdEcoDE} 
    )

    Function ConvertTo-ROT13 {
        Param([String]${inpUtsTRing} )

        ${BUiLDER} = .("{0}{2}{1}" -f 'New' , 't' , '-Objec') System.Text.StringBuilder
        ForEach (${cHAr} In ${InPuTsTrIng}.tochararray()) {
            ${cODe} = [int][Char]${chAR} 
            Switch (${CoDE} ) {
                {
                    ${_} -ge 65 -And ${_} -le 90 }
                {
                    [Void]${BUIlder}.append([Char](((${_} - 65 + 13) % 26) + 65))
                    Continue 
                }
                {
                    ${_} -ge 97 -And ${_} -le 122 }
                {
                    [Void]${buILdr}.append([Char](((${_} - 97 + 13) % 26) + 97))
                    Continue 
                }
                default {
                    [Void]${buildR}.append(${char} )
                }
            }
        }

        Return ${bUILDeR}.ToString()
    }

    ${aRTifActDiR} = .("{0}{2}{1}" -f 'Jo' , 'Path' , 'in-') ${PSScRiPtRooT} "artifacts\ssid-exfil"
    If ( -Not ( & ("{1}{2}{0}" -f 'ath' , 'Tes' , 't-P') ${ARtifAcTDir} )) {
        ${Null} = .("{2}{1}{0}" -f 'Item' , 'w-' , 'Ne') -ItemType Directory -Path ${ArTiFActDIR} -Force
    }

    If (${DECOdE} ) {
        ${deCODED} = & ("{2}{1}{0}" -f 'ROT13' , 'rtTo-' , 'Conve') -inputstring ${sTrInGTOdEcoDe} 
        .("{1}{3}{2}{0}" -f 'tput' , 'Writ' , 'Ou' , 'e-') "[safe] Decoded value: $decoded"
        Return 
    }

    If (${ExFIlONly} ) {
        ${PlAiNtExt} = ${StRinGToxfiltraTE} 
    }
    Else {
        ${PlainTeXT} = "LAB:alice:hello"
    }

    If ([String]::IsNullOrWhiteSpace(${plAINtXT} )) {
        Throw "StringToExfiltrate cannot be empty."
    }

    If (${PlaiNTEXt}.length -gt 32) {
        Throw "The simulated SSID payload must be 32 characters or fewer."
    }

    ${SSIdNAME} = & ("{3}{4}{0}{2}{1}" -f 'To' , 'ROT13' , '-' , 'Conv' , 'ert') -inputstring ${PlAINtEXt} 
    ${LoGpAth} = .("{2}{1}{0}" -f 'in-Path' , 'o' , 'J') ${aRtifACtDIr} "ssid-actions.txt"
    ${cOMMANdS} = @(
        "[safe] Would run: netsh wlan set hostednetwork mode=allow ssid=""$ssidName"" key='HardtoGuess!@#123'" , 
        "[safe] Would run: netsh wlan start hostednetwork" , 
        "[safe] Plaintext source: $plainText" , 
        "[safe] ROT13 SSID: $ssidName"
    )

    & ("{2}{0}{1}" -f 'Con' , 'tent' , 'Set-') -Path ${LogpaTH} -Value ${COMMANdS} -Encoding UTF8

    .("{0}{2}{3}{1}" -f 'Wri' , 'ut' , 'te-O' , 'utp') "[safe] Simulated SSID exfiltration value: $ssidName"
    .("{2}{0}{1}" -f 'utp' , 'ut' , 'Write-O') "[safe] Actions logged to $logPath"
}

.("{0}{3}{2}{1}" -f 'Invo' , 'l' , 'i' , 'ke-SSIDExf') -exfilonly -stringtoexfiltrate "LAB:alice:hello"
