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
            "Get-Date" { return (.("{2}{0}{1}" -f'et-Dat','e','G')).ToString("s") }
            default { return "[safe] Command blocked: $Command" }
        }
    }
    ${a`R`TI`FactDIr} = &("{2}{1}{0}"-f 'h','oin-Pat','J') ${PSSc`RI`PtrOoT} "artifacts\http-c2"
    if (-not (.("{1}{0}" -f'est-Path','T') ${A`R`TIFactdiR})) {
        ${N`ULl} = &("{1}{0}{2}" -f'ew-I','N','tem') -ItemType Directory -Path ${art`IFACT`d`ir} -Force
    }
    ${SeS`sio`Nid} = "demo-session"
    ${c`o`okie`JAr} = .("{2}{0}{1}" -f 'bjec','t','New-O') System.Net.CookieContainer
    ${seR`V`ERUrI} = [System.Uri]${Ser`V`er}
    ${C`oo`K`iEjar}.Add((.("{1}{2}{0}" -f 't','New','-Objec') System.Net.Cookie("RATID", ${Se`SSi`Onid}, "/", ${S`e`RvERURi}.Host)))
    ${T`A`sKUrl} = "{0}{1}" -f ${s`eRvEr}.TrimEnd("/"), ${bEaCo`NPa`TH}
    ${u`PlOa`duRL} = "{0}{1}" -f ${Ser`VeR}.TrimEnd("/"), ${uPL`OA`dpA`TH}
    ${tR`AnScr`ipT} = &("{1}{2}{0}" -f'ath','Join-','P') ${aR`T`IFaC`Tdir} "http-session.jsonl"
    ${com`m`ANDs} = @("whoami", "Get-Date", "hostname")
    &("{1}{0}{3}{2}"-f 't-','Se','ent','Cont') -Path ${TRanScR`i`PT} -Value "" -Encoding UTF8
    for (${I} = 0; ${I} -lt ${P`olL`coUNt}; ${I}++) {
        ${cO`MmanD} = ${C`Omm`ANDs}[${i} % ${co`mM`ANDS}.Count]
        ${re`su`lT} = &("{0}{3}{2}{1}{4}" -f 'In','e-SafeHttpTa','ok','v','sk') -Command ${cOMmA`Nd}
        ${R`ecoRD} = [pscustomobject]@{
            iteration = ${i} + 1
            task_url = ${T`AsKu`Rl}
            upload_url = ${UPlOA`D`U`Rl}
            session = ${SEs`S`IOnID}
            command = ${co`mmA`Nd}
            result = ${R`es`UlT}
        } | &("{3}{1}{0}{2}"-f 'so','rtTo-J','n','Conve') -Compress
        &("{3}{1}{2}{0}" -f'ent','o','nt','Add-C') -Path ${t`RANsCr`IPT} -Value ${RE`CoRD}
        &("{0}{2}{1}" -f'Writ','Output','e-') "[safe] GET $taskUrl"
        .("{2}{1}{0}{3}"-f 'ite-Outp','r','W','ut') "[safe] Received task: $command"
        &("{3}{2}{0}{1}" -f '-','Output','e','Writ') "[safe] POST $uploadUrl"
        &("{2}{1}{0}" -f'ut','p','Write-Out') "[safe] Result: $result"
    }
    &("{1}{0}{2}{3}" -f 'e-O','Writ','utpu','t') "[safe] Simulated HTTP C2 session finished."
}
.("{0}{2}{1}{3}{5}{4}"-f 'Invoke','shR','-Po','atH','p','tt')
