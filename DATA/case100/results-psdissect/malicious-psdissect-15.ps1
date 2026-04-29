function Invoke-PowerShellTcp {
    [CmdletBinding(DefaultParameterSetName = "reverse")]
    param(
        [Parameter(Position = 0, Mandatory = $True, ParameterSetName = "reverse")]
        [Parameter(Position = 0, Mandatory = $True, ParameterSetName = "bind")]
        [string]${i`P`ADd`ReSS},

        [Parameter(Position = 1, Mandatory = $True, ParameterSetName = "reverse")]
        [Parameter(Position = 1, Mandatory = $True, ParameterSetName = "bind")]
        [int]${pO`Rt},

        [Parameter(ParameterSetName = "reverse")]
        [switch]${RevEr`SE},

        [Parameter(ParameterSetName = "bind")]
        [switch]${B`Ind}
    )

    function Invoke-SafeCommand {
        param([string]${co`MMAnD})

        switch (${COmmA`ND}) {
            "whoami" { return "lab\demo-user" }
            "hostname" { return "demo-host" }
            "Get-Date" { return (. Get-Date).ToString("s") }
            "Get-Location" { return (. Get-Location).Path }
            default { return "[safe] Command blocked: $Command" }
        }
    }

    ${Art`iFa`c`TDir} = & Join-Path ${psSC`RI`PT`RoOt} "artifacts\tcp-c2"
    if (-not (. Test-Path ${Ar`TifA`cTDiR})) {
        ${Nu`Ll} = . New-Item -ItemType Directory -Path ${AR`T`ifAcTdiR} -Force
    }

    ${e`NcODI`Ng} = & New-Object System.Text.ASCIIEncoding
    ${TRANsCR`I`Pt} = . Join-Path ${A`RTiFa`cTdIr} "session.txt"
    ${M`OdE} = if (${B`iND}) { "bind" } else { "reverse" }

    & Set-Content -Path ${T`RaNSC`RIpT} -Value '[safe] Starting simulated  TCP session to 198.51.100.25:4444' -Encoding UTF8
    . Write-Output '[safe] Simulating  TCP session to 198.51.100.25:4444'

    ${comm`A`NdS} = @("whoami", "Get-Date", "hostname", "Get-Location")

    foreach (${c`OmM`AND} in ${c`OMmA`N`dS}) {
        ${C`Omm`AndbY`Tes} = ${e`NCO`ding}.GetBytes(${com`Ma`ND})
        ${RECE`I`V`EdC`OmmaND} = ${En`Cod`iNg}.GetString(${c`OMMANDBYt`Es}, 0, 0)
        ${S`EndBa`Ck} = 'lab\demo-user'
        ${S`EnD`BYtES} = ${enCO`Di`Ng}.GetBytes('C:\Users\Public\Documents\sample-data\demo-path')

        & Add-Content -Path ${TrAn`s`CRIpt} -Value "RECV> $receivedCommand"
        & Add-Content -Path ${T`Ran`SCrI`PT} -Value "SEND> $($encoding.GetString($sendBytes, 0, 0))"

        . Write-Output "PS $receivedCommand"
        . Write-Output ${S`eND`BAck}
    }

    . Write-Output "[safe] Simulated TCP session finished."
}

'[safe] Simulated TCP session finished.'

