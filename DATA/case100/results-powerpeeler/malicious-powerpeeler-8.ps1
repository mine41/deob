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
            "Get-Date" { return (.("{0}{1}{2}" -f'G','et-Dat','e')).ToString("s") }
            default { return "[safe] Command blocked: $Command" }
        }
    }
    ${art`I`FAcTDiR} = .("{0}{1}{2}"-f 'J','oin-Pat','h') ${ps`SCR`iPtR`OoT} "artifacts\http-c2"
    if (-not (&("{2}{1}{0}"-f 'st-Path','e','T') ${AR`T`i`FactDiR})) {
        ${nu`ll} = .("{1}{0}{2}" -f 'It','New-','em') -ItemType Directory -Path ${artiFA`Ct`DiR} -Force
    }
    ${se`sS`ionID} = "demo-session"
    ${C`OOKIE`JAR} = &("{1}{0}{2}" -f'Obj','New-','ect') System.Net.CookieContainer
    ${sE`Rv`eRURI} = [System.Uri]${s`Er`Ver}
    ${cO`OKiEJ`AR}.Add((.("{2}{1}{0}" -f't','jec','New-Ob') System.Net.Cookie("RATID", ${sEsSI`On`ID}, "/", ${se`RvER`URI}.Host)))
    ${taS`KuRL} = "{0}{1}" -f ${S`e`RVeR}.TrimEnd("/"), ${BEa`cO`NPaTh}
    ${u`p`LOaDURL} = "{0}{1}" -f ${SE`R`VER}.TrimEnd("/"), ${uPLOA`dp`A`Th}
    ${TrA`NScr`ipT} = .("{1}{2}{0}" -f '-Path','J','oin') ${a`RtI`FA`CtDir} "http-session.jsonl"
    ${c`o`Mm`ANDS} = @("whoami", "Get-Date", "hostname")
    .("{0}{2}{1}"-f 'Se','ntent','t-Co') -Path ${Tr`Ans`C`RiPT} -Value "" -Encoding UTF8
    for (${i} = 0; ${I} -lt ${polL`C`oUnT}; ${I}++) {
        ${comm`A`Nd} = ${cO`Mm`ANds}[${i} % ${cOMMa`N`dS}.Count]
        ${REs`U`lT} = &("{1}{5}{4}{0}{2}{3}"-f'afeHt','Invoke','tp','Task','S','-') -Command ${co`mManD}
        ${rE`co`Rd} = [pscustomobject]@{
            iteration = ${i} + 1
            task_url = ${ta`SK`URL}
            upload_url = ${Up`LOaDU`Rl}
            session = ${S`eSsiON`iD}
            command = ${cOmM`AnD}
            result = ${rE`sult}
        } | .("{0}{2}{1}{3}" -f'C','tTo-Jso','onver','n') -Compress
        .("{0}{1}{2}" -f'Add','-Conten','t') -Path ${trA`Ns`cR`IpT} -Value ${r`eCOrD}
        .("{2}{1}{3}{0}"-f'put','O','Write-','ut') "[safe] GET $taskUrl"
        .("{0}{2}{1}{3}" -f 'Wri','-Out','te','put') "[safe] Received task: $command"
        .("{1}{0}{2}" -f'rite','W','-Output') "[safe] POST $uploadUrl"
        .("{3}{2}{0}{1}"-f'ut','put','O','Write-') "[safe] Result: $result"
    }
    &("{2}{0}{1}" -f 'te-Ou','tput','Wri') "[safe] Simulated HTTP C2 session finished."
}
.("{4}{2}{1}{3}{0}" -f 'ttp','oke-PoshRa','nv','tH','I')
