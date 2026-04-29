Function Invoke-PoshRatHttp {
    [CmdletBinding()]
    Param(
        [String]${sERVER} = "https://c2.example.invalid" , 
        [String]${bEacoNPaTh} = "/rat/beacon" , 
        [String]${UpLoaDPATH} = "/rat/upload" , 
        [int]${pOLLcOUNt} = 3
    )

    Function Invoke-SafeHttpTask {
        Param([String]${commAnD} )

        Switch (${COmMANd} ) {
            "whoami" {
                Return "lab\demo-user" }
            "hostname" {
                Return "demo-host" }
            "Get-Date" {
                Return (.("{0}{1}{2}" -f 'G' , 'et-Dat' , 'e')).ToString("s") }
            default {
                Return "[safe] Command blocked: $Command" }
        }
    }

    ${artIFAcTDiR} = .("{0}{1}{2}" -f 'J' , 'oin-Pat' , 'h') ${psSCRiPtROoT} "artifacts\http-c2"
    If ( -Not ( & ("{2}{1}{0}" -f 'st-Path' , 'e' , 'T') ${ARTiFactDiR} )) {
        ${Null} = .("{1}{0}{2}" -f 'It' , 'New-' , 'em') -ItemType Directory -Path ${artiFACtDiR} -Force
    }

    ${sesSionID} = "demo-session"
    ${COOKIEJAR} = & ("{1}{0}{2}" -f 'Obj' , 'New-' , 'ect') System.Net.CookieContainer
    ${sERvRURI} = [System.Uri]${sErVer} 
    ${cOOKiEJAR}.Add((.("{2}{1}{0}" -f 't' , 'jec' , 'New-Ob') System.Net.Cookie("RATID" , ${sEsSIOnID} , "/" , ${seRvERURI}.host)))

    ${taSKuRL} = "{0}{1}" -f ${SRVeR}.trimend("/") , ${BEacONPaTh} 
    ${upLOaDURL} = "{0}{1}" -f ${SERVER}.trimend("/") , ${uPLOAdpATh} 
    ${TrANScripT} = .("{1}{2}{0}" -f '-Path' , 'J' , 'oin') ${aRtIFACtDir} "http-session.jsonl"

    ${coMmANDS} = @("whoami" , "Get-Date" , "hostname")
    .("{0}{2}{1}" -f 'Se' , 'ntent' , 't-Co') -Path ${TrAnsCRiPT} -Value "" -Encoding UTF8

    For (${i} = 0; ${I} -lt ${polLCoUnT}; ${I} ++ ) {
        ${commANd} = ${cOMmANds}[${i} % ${cOMMaNdS}.count]
        ${REsUlT} = & ("{1}{5}{4}{0}{2}{3}" -f 'afeHt' , 'Invoke' , 'tp' , 'Task' , 'S' , '-') -Command ${comManD} 

        ${rEcoRd} = [pscustomobject]@{
            iteration = ${i} + 1
            task_url = ${taSKURL} 
            upload_url = ${UpLOaDURl} 
            session = ${SSsiONiD} 
            command = ${cOmMAnD} 
            result = ${rEsult} 
        } | .("{0}{2}{1}{3}" -f 'C' , 'tTo-Jso' , 'onver' , 'n') -Compress

        .("{0}{1}{2}" -f 'Add' , '-Conten' , 't') -Path ${trANscRIpT} -Value ${rCOrD} 

        .("{2}{1}{3}{0}" -f 'put' , 'O' , 'Write-' , 'ut') "[safe] GET $taskUrl"
        .("{0}{2}{1}{3}" -f 'Wri' , '-Out' , 'te' , 'put') "[safe] Received task: $command"
        .("{1}{0}{2}" -f 'rite' , 'W' , '-Output') "[safe] POST $uploadUrl"
        .("{3}{2}{0}{1}" -f 'ut' , 'put' , 'O' , 'Write-') "[safe] Result: $result"
    }

    & ("{2}{0}{1}" -f 'te-Ou' , 'tput' , 'Wri') "[safe] Simulated HTTP C2 session finished."
}

.("{4}{2}{1}{3}{0}" -f 'ttp' , 'oke-PoshRa' , 'nv' , 'tH' , 'I')
