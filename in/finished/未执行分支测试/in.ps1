if ($false) {
    # 高置信：Binary / Convert / Unary / Paren / SubExpression / ExpandableString
    $intAdd        = 1 + 2
    $intNeg        = -([int]1)
    $intPos        = +([int]1)
    $doubleVal     = [double]1.5
    $decimalVal    = [decimal]'1.5'
    $charVal       = [char]49
    $boolAnd       = $true -and $false
    $boolEq        = 1 -eq 1
    $boolNot       = -not $true
    $boolBang      = !$false
    $bitBnot       = -bnot 1
    $nullParen     = ($null)
    $parenExpr     = (1 + 2)
    $subExpr       = $(1 + 2)
    $expandHigh    = "ab$('c')"
    $joinHigh      = @('a', 'b', 'c') -join ''
    $formatHigh    = '{0}{1}{2}' -f 'a', 'b', 'c'

    # 低置信：未知变量仅在字符串安全上下文回退为空
    $strPlusLow    = 'pre' + $missing + 'suf'
    $expandLow1    = "pre $missing suf"
    $expandLow2    = "pre $($missing + 'x') suf"
    $stringCastLow = [string]$missing
    $joinLow       = @('a', $missing, 'b') -join ''
    $formatLow     = '{0}{1}{2}' -f 'a', $missing, 'b'

    # 应失败：未知变量不在字符串安全上下文；或 AST 类型不支持
    $badPlus       = $missing + 1
    $badExpand     = "pre $($missing + 1) suf"
    $badCommand    = Get-Date
    $badMember     = $obj.Name
    $badIndex      = $arr[0]
    $badInvoke     = $missing.ToString()
}

'OK'
