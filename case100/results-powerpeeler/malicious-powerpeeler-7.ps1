function Invoke-PoshRatHttp {
    [CmdletBinding()]
    param(
        [string]${s`erv`Er} = "https://c2.example.invalid",
        [string]${BeaC`On`pA`Th} = "/rat/beacon",
        [string]${U`PL`oAdp`ATh} = "/rat/upload",
        [int]${poLL`Cou`NT} = 3
    )
    function Invoke-SafeHttpTask {
        param([string]${c`o`mmaND})
        switch (${c`oMM`AnD}) {
            "whoami" { return "lab\demo-user" }
            "hostname" { return "demo-host" }
            "Get-Date" { return (GET-d`ATe).ToString("s") }
            default { return "[safe] Command blocked: $Command" }
        }
    }
    ${ART`iFactD`ir} = joiN`-PA`Th ${p`sScrIpt`RoOT} "artifacts\http-c2"
    if (-not (tEs`T`-PAth ${ArT`iFAC`T`dir})) {
        ${Nu`lL} = N`e`w-ITEM -ItemType Directory -Path ${a`R`T`IFAcTDir} -Force
    }
    ${S`ES`sIoNiD} = "demo-session"
    ${Co`o`KieJ`AR} = neW`-ObJe`ct System.Net.CookieContainer
    ${s`erVer`Uri} = [System.Uri]${S`ErVer}
    ${c`oO`KIeJAR}.Add((nEW`-`oBJ`ECt System.Net.Cookie("RATID", ${Se`SS`Ion`Id}, "/", ${SErve`R`Uri}.Host)))
    ${T`A`SKUrl} = "{0}{1}" -f ${S`eRV`Er}.TrimEnd("/"), ${BeACo`NPA`Th}
    ${u`pl`oAdUrl} = "{0}{1}" -f ${SeR`VEr}.TrimEnd("/"), ${uP`loAdP`Ath}
    ${TRAN`Scr`I`Pt} = J`OiN-p`AtH ${A`R`Tif`ACtDIr} "http-session.jsonl"
    ${CO`mManDs} = @("whoami", "Get-Date", "hostname")
    s`eT-`conTENt -Path ${t`RAN`sCript} -Value "" -Encoding UTF8
    for (${I} = 0; ${i} -lt ${po`Ll`C`OUnT}; ${i}++) {
        ${co`Mm`AND} = ${CoMM`AnDs}[${i} % ${coMM`ANDS}.Count]
        ${rES`UlT} = I`NV`okE-sAFEht`TpTASK -Command ${cO`MMaND}
        ${REc`ord} = [pscustomobject]@{
            iteration = ${i} + 1
            task_url = ${TaSK`U`RL}
            upload_url = ${uP`lOADu`Rl}
            session = ${sES`s`iONId}
            command = ${CO`MM`ANd}
            result = ${r`ESuLT}
        } | C`oNVERttO`-json -Compress
        aDd-c`On`TEnt -Path ${tRAN`scRi`pt} -Value ${r`ECo`Rd}
        WR`i`Te-outpUT "[safe] GET $taskUrl"
        wRiTe`-oU`TpuT "[safe] Received task: $command"
        W`R`ITE-ouT`pUT "[safe] POST $uploadUrl"
        wRiTE`-`outpuT "[safe] Result: $result"
    }
    w`Rite-ou`T`PUt "[safe] Simulated HTTP C2 session finished."
}
Invoke-PoshRatHttp
