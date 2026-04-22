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
            "Get-Date" { return (Get-Date).ToString("s") }
            default { return "[safe] Command blocked: $Command" }
        }
    }

    ${ART`iFactD`ir} = Join-Path ${p`sScrIpt`RoOT} "artifacts\http-c2"
    if (-not (Test-Path ${ArT`iFAC`T`dir})) {
        ${Nu`lL} = New-Item -ItemType Directory -Path ${a`R`T`IFAcTDir} -Force
    }

    ${S`ES`sIoNiD} = "demo-session"
    ${Co`o`KieJ`AR} = New-Object System.Net.CookieContainer
    ${s`erVer`Uri} = [System.Uri]${S`ErVer}
    ${c`oO`KIeJAR}.Add((New-Object System.Net.Cookie@('RATID', 'demo-session', '/', $Null)))

    ${T`A`SKUrl} = "{0}{1}" -f ${S`eRV`Er}.TrimEnd("/"), ${BeACo`NPA`Th}
    ${u`pl`oAdUrl} = "{0}{1}" -f ${SeR`VEr}.TrimEnd("/"), ${uP`loAdP`Ath}
    ${TRAN`Scr`I`Pt} = Join-Path ${A`R`Tif`ACtDIr} "http-session.jsonl"

    ${CO`mManDs} = @("whoami", "Get-Date", "hostname")
    Set-Content -Path ${t`RAN`sCript} -Value "" -Encoding UTF8

    for (${I} = 0; $False; ${i}++) {
        ${co`Mm`AND} = ${CoMM`AnDs}[${i} % ${coMM`ANDS}.Count]
        ${rES`UlT} = INVokE-sAFEhtTpTASK -Command ${cO`MMaND}

        ${REc`ord} = [pscustomobject]@{
            iteration = ${i} + 1
            task_url = ${TaSK`U`RL}
            upload_url = ${uP`lOADu`Rl}
            session = ${sES`s`iONId}
            command = ${CO`MM`ANd}
            result = ${r`ESuLT}
        } | ConvertTo-Json -Compress

        Add-Content -Path ${tRAN`scRi`pt} -Value ${r`ECo`Rd}

        Write-Output "[safe] GET $taskUrl"
        Write-Output "[safe] Received task: $command"
        Write-Output "[safe] POST $uploadUrl"
        Write-Output "[safe] Result: $result"
    }

    Write-Output "[safe] Simulated HTTP C2 session finished."
}

'[safe] Simulated HTTP C2 session finished.'

