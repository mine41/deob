Function Invoke-PoshRatHttp {
    [CmdletBinding()]
    Param(
        [String]${seRVEr} = "https://c2.example.invalid" , 
        [String]${BEacoNpatH} = "/rat/beacon" , 
        [String]${UPLOADpatH} = "/rat/upload" , 
        [int]${POlLCOUNt} = 3
    )

    Function Invoke-SafeHttpTask {
        Param([String]${coMMAND} )

        Switch (${CoMMaNd} ) {
            "whoami" {
                Return "lab\demo-user" }
            "hostname" {
                Return "demo-host" }
            "Get-Date" {
                Return (.("{2}{0}{1}" -f 'et-Dat' , 'e' , 'G')).ToString("s") }
            default {
                Return "[safe] Command blocked: $Command" }
        }
    }

    ${aRTIFactDIr} = & ("{2}{1}{0}" -f 'h' , 'oin-Pat' , 'J') ${PSScRIPtrOoT} "artifacts\http-c2"
    If ( -Not (.("{1}{0}" -f 'est-Path' , 'T') ${ARTIFactdiR} )) {
        ${Null} = & ("{1}{0}{2}" -f 'ew-I' , 'N' , 'tem') -ItemType Directory -Path ${artIFACTdir} -Force
    }

    ${SeSsioNid} = "demo-session"
    ${cookieJAr} = .("{2}{0}{1}" -f 'bjec' , 't' , 'New-O') System.Net.CookieContainer
    ${seRVERUrI} = [System.Uri]${SerVr} 
    ${CooKiEjar}.Add((.("{1}{2}{0}" -f 't' , 'New' , '-Objec') System.Net.Cookie("RATID" , ${SeSSiOnid} , "/" , ${SRvERURi}.host)))

    ${TAsKUrl} = "{0}{1}" -f ${sRvEr}.trimend("/") , ${bEaCoNPaTH} 
    ${uPlOaduRL} = "{0}{1}" -f ${SerVeR}.trimend("/") , ${uPLOAdpATH} 
    ${tRAnScripT} = & ("{1}{2}{0}" -f 'ath' , 'Join-' , 'P') ${aRTIFaCTdir} "http-session.jsonl"

    ${commANDs} = @("whoami" , "Get-Date" , "hostname")
    & ("{1}{0}{3}{2}" -f 't-' , 'Se' , 'ent' , 'Cont') -Path ${TRanScRiPT} -Value "" -Encoding UTF8

    For (${I} = 0; ${I} -lt ${PolLcoUNt}; ${I} ++ ) {
        ${cOMmanD} = ${COmmANDs}[${i} % ${comMANDS}.count]
        ${resulT} = & ("{0}{3}{2}{1}{4}" -f 'In' , 'e-SafeHttpTa' , 'ok' , 'v' , 'sk') -Command ${cOMmANd} 

        ${RcoRD} = [pscustomobject]@{
            iteration = ${i} + 1
            task_url = ${TAsKuRl} 
            upload_url = ${UPlOADURl} 
            session = ${SEsSIOnID} 
            command = ${commANd} 
            result = ${RsUlT} 
        } | & ("{3}{1}{0}{2}" -f 'so' , 'rtTo-J' , 'n' , 'Conve') -Compress

        & ("{3}{1}{2}{0}" -f 'ent' , 'o' , 'nt' , 'Add-C') -Path ${tRANsCrIPT} -Value ${RECoRD} 

        & ("{0}{2}{1}" -f 'Writ' , 'Output' , 'e-') "[safe] GET $taskUrl"
        .("{2}{1}{0}{3}" -f 'ite-Outp' , 'r' , 'W' , 'ut') "[safe] Received task: $command"
        & ("{3}{2}{0}{1}" -f '-' , 'Output' , 'e' , 'Writ') "[safe] POST $uploadUrl"
        & ("{2}{1}{0}" -f 'ut' , 'p' , 'Write-Out') "[safe] Result: $result"
    }

    & ("{1}{0}{2}{3}" -f 'e-O' , 'Writ' , 'utpu' , 't') "[safe] Simulated HTTP C2 session finished."
}

.("{0}{2}{1}{3}{5}{4}" -f 'Invoke' , 'shR' , '-Po' , 'atH' , 'p' , 'tt')
