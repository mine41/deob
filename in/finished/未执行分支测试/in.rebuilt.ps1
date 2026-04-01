if ($false) {
    # 高置信：Binary / Convert / Unary / Paren / SubExpression / ExpandableString
    $intAdd        = 3
    $intNeg        = -1
    $intPos        = +1
    $doubleVal     = 1.5
    $decimalVal    = [decimal]'1.5'
#做的好----------------------------------
    $charVal       = [char]'1'
    $boolAnd       = $False
    $boolEq        = $True
    $boolNot       = $False
    $boolBang      = $True
    $bitBnot       = -2
    $nullParen     = $null
    $parenExpr     = 3
    $subExpr       = 3
    $expandHigh    = "ab'c'"
    $joinHigh      = 'abc'
    $formatHigh    = 'abc'
#做的好----------------------------------
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


