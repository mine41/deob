function Invoke-PowerShellTcp {
    [CmdletBinding(DefaultParameterSetName = "reverse")]
    param(
        [Parameter(Position = 0, Mandatory = $True, ParameterSetName = "reverse")]
        [Parameter(Position = 0, Mandatory = $True, ParameterSetName = "bind")]
        [string]${i`pA`DdR`eSs},

        [Parameter(Position = 1, Mandatory = $True, ParameterSetName = "reverse")]
        [Parameter(Position = 1, Mandatory = $True, ParameterSetName = "bind")]
        [int]${pO`Rt},

        [Parameter(ParameterSetName = "reverse")]
        [switch]${RE`VeR`SE},

        [Parameter(ParameterSetName = "bind")]
        [switch]${b`inD}
    )

    function Invoke-SafeCommand {
        param([string]${c`oMmA`ND})

        switch ('') {
            "whoami" { return "lab\demo-user" }
            "hostname" { return "demo-host" }
            "Get-Date" { return (& Get-Date).ToString("s") }
            "Get-Location" { return (. Get-Location).Path }
            default { return "[safe] Command blocked: $Command" }
        }
    }

    ${a`R`TIFaCTd`ir} = . Join-Path ${P`ss`crIP`Tr`oOt} "artifacts\tcp-c2"
    if (-not (& Test-Path ${artifA`c`TdIR})) {
        ${N`Ull} = . New-Item -ItemType Directory -Path ${A`Rt`IF`ACTdIR} -Force
    }

    ${eN`coDi`NG} = & New-Object System.Text.ASCIIEncoding
    ${tr`Ans`CRI`PT} = . Join-Path ${AR`TIfA`CTDIr} "session.txt"
    ${M`Ode} = if (${B`INd}) { "bind" } else { "reverse" }

    & Set-Content -Path ${TR`ANS`c`RIpt} -Value '[safe] Starting simulated  TCP session to :4444' -Encoding UTF8
    & Write-Output '[safe] Simulating  TCP session to :4444'

    ${C`O`mMAndS} = @("whoami", "Get-Date", "hostname", "Get-Location")

    foreach (${COm`ma`ND} in ${comm`AN`Ds}) {
        ${C`oMm`AN`DByteS} = ${eN`cOD`ING}.GetBytes(${CoM`manD})
        ${rE`cEIvEdco`MMa`Nd} = ${E`NC`ODING}.GetString(${cOM`MAnd`BytES}, 0, 0)
        ${S`enD`BaCK} = 'lab\demo-user'
        ${S`eNdby`TES} = ${EN`c`odIng}.GetBytes(${s`EnDBA`CK})

        . Add-Content -Path ${TRaNSc`Ri`pt} -Value "RECV> $receivedCommand"
        . Add-Content -Path ${TRa`NSc`RI`PT} -Value "SEND> $($encoding.GetString($sendBytes, 0, 0))"

        . Write-Output "PS $receivedCommand"
        & Write-Output ${se`N`DBACk}
    }

    . Write-Output "[safe] Simulated TCP session finished."
}

'[safe] Simulated TCP session finished.'

