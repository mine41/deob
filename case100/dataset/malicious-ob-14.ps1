function Invoke-PowerShellTcp {
    [CmdletBinding(DefaultParameterSetName = "reverse")]
    param(
        [Parameter(Position = 0, Mandatory = ${tr`Ue}, ParameterSetName = "reverse")]
        [Parameter(Position = 0, Mandatory = ${T`Rue}, ParameterSetName = "bind")]
        [string]${i`PaDD`REss},

        [Parameter(Position = 1, Mandatory = ${T`RUE}, ParameterSetName = "reverse")]
        [Parameter(Position = 1, Mandatory = ${t`Rue}, ParameterSetName = "bind")]
        [int]${p`Ort},

        [Parameter(ParameterSetName = "reverse")]
        [switch]${Rev`eR`sE},

        [Parameter(ParameterSetName = "bind")]
        [switch]${bi`Nd}
    )

    function Invoke-SafeCommand {
        param([string]${CoM`m`AnD})

        switch (${c`OMM`AND}) {
            "whoami" { return "lab\demo-user" }
            "hostname" { return "demo-host" }
            "Get-Date" { return (GeT-`D`AtE).ToString("s") }
            "Get-Location" { return (Ge`T`-`lOcaTIOn).Path }
            default { return "[safe] Command blocked: $Command" }
        }
    }

    ${ArTI`Fa`c`TdIr} = J`Oi`N`-paTh ${p`S`sCrIpt`R`ooT} "artifacts\tcp-c2"
    if (-not (te`ST`-`paTH ${a`RtIfac`TD`ir})) {
        ${n`ULl} = nE`w`-ITEm -ItemType Directory -Path ${AR`TiFA`C`TDIr} -Force
    }

    ${ENc`od`ing} = NEW`-Ob`jecT System.Text.ASCIIEncoding
    ${tRANscR`i`pt} = JoI`N-P`AtH ${arTI`F`Act`diR} "session.txt"
    ${M`ode} = if (${Bi`Nd}) { "bind" } else { "reverse" }

    sET`-co`NtENT -Path ${tRA`Nsc`Ri`PT} -Value "[safe] Starting simulated $mode TCP session to $IPAddress`:$Port" -Encoding UTF8
    W`R`iTe-`OUtPUt "[safe] Simulating $mode TCP session to $IPAddress`:$Port"

    ${c`omMA`NDs} = @("whoami", "Get-Date", "hostname", "Get-Location")

    foreach (${Comma`Nd} in ${cO`m`mAN`dS}) {
        ${c`oMmAndbY`T`eS} = ${e`Nco`dInG}.GetBytes(${C`OMmaNd})
        ${REceiv`E`dcoM`M`AnD} = ${en`CodiNg}.GetString(${coM`mANd`B`Y`TeS}, 0, ${ComMA`NdBYT`eS}.Length)
        ${S`eNDb`Ack} = INVo`Ke-S`AFeC`oM`MaND -Command ${RE`ceiVeD`COm`mAnd}
        ${s`eN`DBYTes} = ${enCO`D`ing}.GetBytes(${s`E`N`DBaCk})

        AD`d-`C`onteNT -Path ${tR`AN`s`cRiPT} -Value "RECV> $receivedCommand"
        adD-`CoNT`E`Nt -Path ${TR`An`sCrIpt} -Value "SEND> $($encoding.GetString($sendBytes, 0, $sendBytes.Length))"

        W`RitE`-OUt`pUT "PS $receivedCommand"
        WRite-`o`U`TPuT ${s`e`NDBaCk}
    }

    Wr`i`TE-ouTpUT "[safe] Simulated TCP session finished."
}

InvOK`E-`P`OWErSHEllTCp -IPAddress "198.51.100.25" -Port 4444 -Reverse
