function Invoke_Hello_statebag_single {
    $ctx = [ordered]@{
        Parts = @{}
        Key   = 41
    }

    function Invoke_Hello_stash_all {
        param([hashtable]$State)
        $State.Parts['p0'] = @(126, 91, 64, 93, 76, 4, 97, 70, 90, 93, 9, 11, 97, 76, 69, 69, 70, 11)
    }

    function Invoke_Hello_decode {
        param([int[]]$Values, [int]$Key)

        $buffer = New-Object char[] $Values.Count
        for ($i = 0; $i -lt $Values.Count; $i++) {
            $buffer[$i] = [char]($Values[$i] -bxor $Key)
        }

        return(-join $buffer)
    }

    & Invoke_Hello_stash_all -State $ctx
    $scriptText = (& Invoke_Hello_decode -Values $ctx.Parts['p0'] -Key $ctx.Key)
    Invoke-Expression $scriptText
}

Invoke_Hello_statebag_single