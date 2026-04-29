function Invoke-PowerShellTcp {
    [CmdletBinding(DefaultParameterSetName = "reverse")]
    param(
        [Parameter(Position = 0, Mandatory = ${tR`UE}, ParameterSetName = "reverse")]
        [Parameter(Position = 0, Mandatory = ${T`Rue}, ParameterSetName = "bind")]
        [string]${i`pA`DdR`eSs},
        [Parameter(Position = 1, Mandatory = ${t`RuE}, ParameterSetName = "reverse")]
        [Parameter(Position = 1, Mandatory = ${tr`UE}, ParameterSetName = "bind")]
        [int]${pO`Rt},
        [Parameter(ParameterSetName = "reverse")]
        [switch]${RE`VeR`SE},
        [Parameter(ParameterSetName = "bind")]
        [switch]${b`inD}
    )
    function Invoke-SafeCommand {
        param([string]${c`oMmA`ND})
        switch (${C`omm`And}) {
            "whoami" { return "lab\demo-user" }
            "hostname" { return "demo-host" }
            "Get-Date" { return (&("{1}{0}"-f 'ate','Get-D')).ToString("s") }
            "Get-Location" { return (.("{0}{3}{1}{2}" -f 'Get','a','tion','-Loc')).Path }
            default { return "[safe] Command blocked: $Command" }
        }
    }
    ${a`R`TIFaCTd`ir} = .("{2}{1}{0}"-f'Path','n-','Joi') ${P`ss`crIP`Tr`oOt} "artifacts\tcp-c2"
    if (-not (&("{0}{1}{3}{2}"-f 'Tes','t','ath','-P') ${artifA`c`TdIR})) {
        ${N`Ull} = .("{1}{2}{0}" -f'm','New-','Ite') -ItemType Directory -Path ${A`Rt`IF`ACTdIR} -Force
    }
    ${eN`coDi`NG} = &("{1}{0}{2}"-f'c','New-Obje','t') System.Text.ASCIIEncoding
    ${tr`Ans`CRI`PT} = .("{0}{2}{1}"-f'J','Path','oin-') ${AR`TIfA`CTDIr} "session.txt"
    ${M`Ode} = if (${B`INd}) { "bind" } else { "reverse" }
    &("{0}{1}{2}" -f 'Set-','Co','ntent') -Path ${TR`ANS`c`RIpt} -Value "[safe] Starting simulated $mode TCP session to $IPAddress`:$Port" -Encoding UTF8
    &("{2}{0}{1}"-f'p','ut','Write-Out') "[safe] Simulating $mode TCP session to $IPAddress`:$Port"
    ${C`O`mMAndS} = @("whoami", "Get-Date", "hostname", "Get-Location")
    foreach (${COm`ma`ND} in ${comm`AN`Ds}) {
        ${C`oMm`AN`DByteS} = ${eN`cOD`ING}.GetBytes(${CoM`manD})
        ${rE`cEIvEdco`MMa`Nd} = ${E`NC`ODING}.GetString(${cOM`MAnd`BytES}, 0, ${coMmanDb`Yt`es}.Length)
        ${S`enD`BaCK} = .("{2}{3}{1}{0}"-f'mand','Com','Invoke-Sa','fe') -Command ${rece`ivE`D`coMmaNd}
        ${S`eNdby`TES} = ${EN`c`odIng}.GetBytes(${s`EnDBA`CK})
        .("{0}{1}{3}{2}" -f 'Add','-Con','t','ten') -Path ${TRaNSc`Ri`pt} -Value "RECV> $receivedCommand"
        .("{2}{1}{0}" -f'-Content','dd','A') -Path ${TRa`NSc`RI`PT} -Value "SEND> $($encoding.GetString($sendBytes, 0, $sendBytes.Length))"
        .("{2}{1}{0}" -f 'put','e-Out','Writ') "PS $receivedCommand"
        &("{3}{1}{0}{2}"-f'Ou','te-','tput','Wri') ${se`N`DBACk}
    }
    .("{2}{1}{0}{3}"-f 'tp','rite-Ou','W','ut') "[safe] Simulated TCP session finished."
}
.("{2}{1}{0}{3}"-f 'Po','-','Invoke','werShellTcp') -IPAddress "198.51.100.25" -Port 4444 -Reverse
