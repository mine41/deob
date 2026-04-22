function Invoke_Hello_readable_no_stash {
    $ctx = [ordered]@{
        Parts = @{}
        Key   = 41
    }

    $ctx.Parts['p0'] = @(126, 91, 64, 93, 76, 4, 97, 70, 90, 93, 9, 11, 97, 76, 69, 69, 70, 11)

    function Invoke_Hello_decode {
        param([int[]]$Values, [int]$Key)

        $buffer = New-Object char[] $Values.Count
        for ($i = 0; $i -lt $Values.Count; $i++) {
            $buffer[$i] = [char]($Values[$i] -bxor $Key)
        }

        return (-join $buffer)
    }

    $scriptText = (& Invoke_Hello_decode -Values $ctx.Parts['p0'] -Key $ctx.Key)
    Invoke-Expression $scriptText
}

Invoke_Hello_readable_no_stash
