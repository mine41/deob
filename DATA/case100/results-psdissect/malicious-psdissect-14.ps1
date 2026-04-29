function Invoke-PowerShellTcp {
    [CmdletBinding(DefaultParameterSetName = "reverse")]
    param(
        [Parameter(Position = 0, Mandatory = $True, ParameterSetName = "reverse")]
        [Parameter(Position = 0, Mandatory = $True, ParameterSetName = "bind")]
        [string]${i`PaDD`REss},

        [Parameter(Position = 1, Mandatory = $True, ParameterSetName = "reverse")]
        [Parameter(Position = 1, Mandatory = $True, ParameterSetName = "bind")]
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
            "Get-Date" { return (Get-Date).ToString("s") }
            "Get-Location" { return (Get-Location).Path }
            default { return "[safe] Command blocked: $Command" }
        }
    }

    ${ArTI`Fa`c`TdIr} = Join-Path ${p`S`sCrIpt`R`ooT} "artifacts\tcp-c2"
    if (-not (Test-Path ${a`RtIfac`TD`ir})) {
        ${n`ULl} = New-Item -ItemType Directory -Path ${AR`TiFA`C`TDIr} -Force
    }

    ${ENc`od`ing} = New-Object System.Text.ASCIIEncoding
    ${tRANscR`i`pt} = Join-Path ${arTI`F`Act`diR} "session.txt"
    ${M`ode} = if (${Bi`Nd}) { "bind" } else { "reverse" }

    Set-Content -Path ${tRA`Nsc`Ri`PT} -Value '[safe] Starting simulated  TCP session to 198.51.100.25:4444' -Encoding UTF8
    Write-Output '[safe] Simulating  TCP session to 198.51.100.25:4444'

    ${c`omMA`NDs} = @("whoami", "Get-Date", "hostname", "Get-Location")

    foreach (${Comma`Nd} in ${cO`m`mAN`dS}) {
        ${c`oMmAndbY`T`eS} = ${e`Nco`dInG}.GetBytes(${C`OMmaNd})
        ${REceiv`E`dcoM`M`AnD} = ${en`CodiNg}.GetString(${coM`mANd`B`Y`TeS}, 0, ${ComMA`NdBYT`eS}.Length)
        ${S`eNDb`Ack} = 'lab\demo-user'
        ${s`eN`DBYTes} = ${enCO`D`ing}.GetBytes(${s`E`N`DBaCk})

        Add-Content -Path ${tR`AN`s`cRiPT} -Value "RECV> $receivedCommand"
        Add-Content -Path ${TR`An`sCrIpt} -Value "SEND> $($encoding.GetString($sendBytes, 0, 0))"

        Write-Output "PS $receivedCommand"
        Write-Output 'C:\Users\Public\Documents\sample-data\demo-path'
    }

    Write-Output "[safe] Simulated TCP session finished."
}

'[safe] Simulated TCP session finished.'

