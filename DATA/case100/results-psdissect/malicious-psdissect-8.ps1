function Invoke-PoshRatHttp {
    [CmdletBinding()]
    param(
        [string]${sE`RV`ER} = "https://c2.example.invalid",
        [string]${b`Ea`coNPaTh} = "/rat/beacon",
        [string]${U`p`LoaDP`ATH} = "/rat/upload",
        [int]${pOL`Lc`OU`Nt} = 3
    )

    function Invoke-SafeHttpTask {
        param([string]${co`m`mAnD})

        switch (${CO`mMA`Nd}) {
            "whoami" { return "lab\demo-user" }
            "hostname" { return "demo-host" }
            "Get-Date" { return (. Get-Date).ToString("s") }
            default { return "[safe] Command blocked: $Command" }
        }
    }

    ${art`I`FAcTDiR} = . Join-Path ${ps`SCR`iPtR`OoT} "artifacts\http-c2"
    if (-not (& Test-Path ${AR`T`i`FactDiR})) {
        ${nu`ll} = . New-Item -ItemType Directory -Path ${artiFA`Ct`DiR} -Force
    }

    ${se`sS`ionID} = "demo-session"
    ${C`OOKIE`JAR} = & New-Object System.Net.CookieContainer
    ${sE`Rv`eRURI} = [System.Uri]${s`Er`Ver}
    ${cO`OKiEJ`AR}.Add((. New-Object System.Net.Cookie@('RATID', 'demo-session', '/', $Null)))

    ${taS`KuRL} = "{0}{1}" -f ${S`e`RVeR}.TrimEnd("/"), ${BEa`cO`NPaTh}
    ${u`p`LOaDURL} = "{0}{1}" -f ${SE`R`VER}.TrimEnd("/"), ${uPLOA`dp`A`Th}
    ${TrA`NScr`ipT} = . Join-Path ${a`RtI`FA`CtDir} "http-session.jsonl"

    ${c`o`Mm`ANDS} = @("whoami", "Get-Date", "hostname")
    . Set-Content -Path ${Tr`Ans`C`RiPT} -Value "" -Encoding UTF8

    for (${i} = 0; $False; ${I}++) {
        ${comm`A`Nd} = ${cO`Mm`ANds}[${i} % ${cOMMa`N`dS}.Count]
        ${REs`U`lT} = &("{1}{5}{4}{0}{2}{3}"-f'afeHt','Invoke','tp','Task','S','-') -Command ${co`mManD}

        ${rE`co`Rd} = [pscustomobject]@{
            iteration = ${i} + 1
            task_url = ${ta`SK`URL}
            upload_url = ${Up`LOaDU`Rl}
            session = ${S`eSsiON`iD}
            command = ${cOmM`AnD}
            result = ${rE`sult}
        } | . ConvertTo-Json -Compress

        . Add-Content -Path ${trA`Ns`cR`IpT} -Value ${r`eCOrD}

        . Write-Output "[safe] GET $taskUrl"
        . Write-Output "[safe] Received task: $command"
        . Write-Output "[safe] POST $uploadUrl"
        . Write-Output "[safe] Result: $result"
    }

    & Write-Output "[safe] Simulated HTTP C2 session finished."
}

'[safe] Simulated HTTP C2 session finished.'

