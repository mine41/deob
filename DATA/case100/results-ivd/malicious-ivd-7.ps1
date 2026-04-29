Function Invoke-PoshRatHttp {
    [CmdletBinding()]
    Param(
        [String]${srvEr} = "https://c2.example.invalid" , 
        [String]${BeaCOnpATh} = "/rat/beacon" , 
        [String]${UPLoAdpATh} = "/rat/upload" , 
        [int]${poLLCouNT} = 3
    )

    Function Invoke-SafeHttpTask {
        Param([String]${commaND} )

        Switch (${coMMAnD} ) {
            "whoami" {
                Return "lab\demo-user" }
            "hostname" {
                Return "demo-host" }
            "Get-Date" {
                Return (Get-Date ).ToString("s") }
            default {
                Return "[safe] Command blocked: $Command" }
        }
    }

    ${ARTiFactDir} = Join-Path ${psScrIptRoOT} "artifacts\http-c2"
    If ( -Not (Test-Path ${ArTiFACTdir} )) {
        ${Null} = nw-item -ItemType Directory -Path ${aRTIFAcTDir} -Force
    }

    ${SESsIoNiD} = "demo-session"
    ${CooKieJAR} = New-Object System.Net.CookieContainer
    ${srVerUri} = [System.Uri]${SErVer} 
    ${coOKIeJAR}.Add((New-Object System.Net.Cookie("RATID" , ${SeSSIonId} , "/" , ${SErveRUri}.host)))

    ${TASKUrl} = "{0}{1}" -f ${SRVEr}.trimend("/") , ${BeACoNPATh} 
    ${uploAdUrl} = "{0}{1}" -f ${SeRVEr}.trimend("/") , ${uPloAdPAth} 
    ${TRANScrIPt} = Join-Path ${ARTifACtDIr} "http-session.jsonl"

    ${COmManDs} = @("whoami" , "Get-Date" , "hostname")
    st-content -Path ${tRANsCript} -Value "" -Encoding UTF8

    For (${I} = 0; ${i} -lt ${poLlCOUnT}; ${i} ++ ) {
        ${coMmAND} = ${CoMMAnDs}[${i} % ${coMMANDS}.count]
        ${rESUlT} = invoke-safehttptask -Command ${cOMMaND} 

        ${REcord} = [pscustomobject]@{
            iteration = ${i} + 1
            task_url = ${TaSKURL} 
            upload_url = ${uPlOADuRl} 
            session = ${sESsiONId} 
            command = ${COMMANd} 
            result = ${rESuLT} 
        } | ConvertTo-Json -Compress

        Add-Content -Path ${tRANscRipt} -Value ${rECoRd} 

        Write-Output "[safe] GET $taskUrl"
        Write-Output "[safe] Received task: $command"
        Write-Output "[safe] POST $uploadUrl"
        Write-Output "[safe] Result: $result"
    }

    Write-Output "[safe] Simulated HTTP C2 session finished."
}

invoke-poshrathttp 
