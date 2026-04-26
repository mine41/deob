function Invoke-PoshRatHttp {
    [CmdletBinding()]
    param(
        [string]${se`RVEr} = "https://c2.example.invalid",
        [string]${B`Ea`coN`patH} = "/rat/beacon",
        [string]${UP`LO`A`DpatH} = "/rat/upload",
        [int]${PO`lLC`OU`Nt} = 3
    )

    function Invoke-SafeHttpTask {
        param([string]${coM`MA`ND})

        switch (${C`oMMa`Nd}) {
            "whoami" { return "lab\demo-user" }
            "hostname" { return "demo-host" }
            "Get-Date" { return (. Get-Date).ToString("s") }
            default { return "[safe] Command blocked: $Command" }
        }
    }

    ${a`R`TI`FactDIr} = & Join-Path ${PSSc`RI`PtrOoT} "artifacts\http-c2"
    if (-not (. Test-Path ${A`R`TIFactdiR})) {
        ${N`ULl} = & New-Item -ItemType Directory -Path ${art`IFACT`d`ir} -Force
    }

    ${SeS`sio`Nid} = "demo-session"
    ${c`o`okie`JAr} = . New-Object System.Net.CookieContainer
    ${seR`V`ERUrI} = [System.Uri]${Ser`V`er}
    ${C`oo`K`iEjar}.Add((. New-Object System.Net.Cookie@('RATID', 'demo-session', '/', $Null)))

    ${T`A`sKUrl} = "{0}{1}" -f ${s`eRvEr}.TrimEnd("/"), ${bEaCo`NPa`TH}
    ${u`PlOa`duRL} = "{0}{1}" -f ${Ser`VeR}.TrimEnd("/"), ${uPL`OA`dpA`TH}
    ${tR`AnScr`ipT} = & Join-Path ${aR`T`IFaC`Tdir} "http-session.jsonl"

    ${com`m`ANDs} = @("whoami", "Get-Date", "hostname")
    & Set-Content -Path ${TRanScR`i`PT} -Value "" -Encoding UTF8

    for (${I} = 0; $False; ${I}++) {
        ${cO`MmanD} = ${C`Omm`ANDs}[${i} % ${co`mM`ANDS}.Count]
        ${re`su`lT} = &("{0}{3}{2}{1}{4}" -f 'In','e-SafeHttpTa','ok','v','sk') -Command ${cOMmA`Nd}

        ${R`ecoRD} = [pscustomobject]@{
            iteration = ${i} + 1
            task_url = ${T`AsKu`Rl}
            upload_url = ${UPlOA`D`U`Rl}
            session = ${SEs`S`IOnID}
            command = ${co`mmA`Nd}
            result = ${R`es`UlT}
        } | & ConvertTo-Json -Compress

        & Add-Content -Path ${t`RANsCr`IPT} -Value ${RE`CoRD}

        & Write-Output "[safe] GET $taskUrl"
        . Write-Output "[safe] Received task: $command"
        & Write-Output "[safe] POST $uploadUrl"
        & Write-Output "[safe] Result: $result"
    }

    & Write-Output "[safe] Simulated HTTP C2 session finished."
}

'[safe] Simulated HTTP C2 session finished.'

