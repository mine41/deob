function Get-Ast {
    param (
        [object] $InputObject
    )

    $ast = switch ($InputObject) {
        {$_ -is [string]} {
            if (Test-Path -LiteralPath $_) {
                $path = Resolve-Path -Path $_
                [System.Management.Automation.Language.Parser]::ParseFile($path.ProviderPath, [ref]$null, [ref]$null)
            }
            else {
                [System.Management.Automation.Language.Parser]::ParseInput($_, [ref]$null, [ref]$null)
            }
            break
        }
        {$_ -is [System.Management.Automation.FunctionInfo] -or
            $_ -is [System.Management.Automation.ExternalScriptInfo]} {
            $InputObject.ScriptBlock.Ast
            break
        }
        {$_ -is [scriptblock]} {
            $_.Ast
            break
        }
        Default {
            throw 'InputObject type not recognised'
        }
    }

    # $ast.FindAll({ $true }, $true)
    return $ast
}

Add-Type -TypeDefinition @"
public enum VarScope
{
    Unspecified = 0,
    Global      = 1,
    Script      = 2,
    Local       = 3,
    Private     = 4
}
"@

function ConvertTo-SingleQuotedStringLiteral {
    param([string]$Text)

    if ($null -eq $Text) { return "''" }
    return "'" + $Text.Replace("'", "''") + "'"
}

function ConvertTo-SingleQuotedHereStringLiteral {
    param([string]$Text)

    $content = if ($null -eq $Text) { '' } else { [string]$Text }
    $content = $content.TrimEnd("`r", "`n")
    return "@'`r`n$content`r`n'@"
}

function ConvertTo-CanonicalPowerShellHostCommandText {
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [string]$PayloadText,
        $HostDynamicInfo = $null
    )

    if (-not $HostDynamicInfo) {
        $HostDynamicInfo = Get-PowerShellHostDynamicInvocationInfo -CommandAst $CommandAst
    }
    if (-not $HostDynamicInfo -or -not $HostDynamicInfo.ParameterAst) {
        return $null
    }

    $originalText = [string]$CommandAst.Extent.Text
    $paramAst = $HostDynamicInfo.ParameterAst
    $prefixLen = $paramAst.Extent.StartOffset - $CommandAst.Extent.StartOffset
    if ($prefixLen -lt 0) { return $null }

    $beforeParam = $originalText.Substring(0, $prefixLen)
    $payloadLiteral = ConvertTo-SingleQuotedHereStringLiteral -Text $PayloadText
    return $beforeParam + "-Command $payloadLiteral"
}

function Test-PowerShellHostCommandName {
    param([string]$CommandName)

    if ([string]::IsNullOrWhiteSpace($CommandName)) { return $false }
    return ([string]$CommandName) -match '(?i)(^|[/\\])(powershell|pwsh)(\.exe)?$'
}

function Test-PowerShellHostParameterPrefix {
    param(
        [string]$ParameterName,
        [string]$CanonicalName
    )

    if ([string]::IsNullOrWhiteSpace($ParameterName)) { return $false }
    if ([string]::IsNullOrWhiteSpace($CanonicalName)) { return $false }

    $actual = $ParameterName.ToLowerInvariant()
    $canonical = $CanonicalName.ToLowerInvariant()
    if ($actual.Length -gt $canonical.Length) { return $false }
    return $canonical.StartsWith($actual)
}

function Resolve-PowerShellHostParameterInfo {
    param([string]$ParameterName)

    if ([string]::IsNullOrWhiteSpace($ParameterName)) { return $null }

    $normalized = ([string]$ParameterName).Trim()
    if ($normalized.StartsWith('-')) {
        $normalized = $normalized.TrimStart('-')
    }
    $normalized = $normalized.ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($normalized)) { return $null }

    $definitions = @(
        @{ CanonicalName = 'encodedcommand'; DynamicType = 'EncodedCommand';   ExpectsValue = $true;  Aliases = @('encodedcommand', 'encoded', 'enc', 'ec', 'e') },
        @{ CanonicalName = 'command';        DynamicType = 'PowerShellCommand'; ExpectsValue = $true;  Aliases = @('command', 'c') },
        @{ CanonicalName = 'executionpolicy'; DynamicType = $null;             ExpectsValue = $true;  Aliases = @('executionpolicy', 'exec', 'ex', 'ep') },
        @{ CanonicalName = 'windowstyle';    DynamicType = $null;              ExpectsValue = $true;  Aliases = @('windowstyle', 'windowstyl', 'windowsty', 'windowst', 'windows', 'window', 'windo', 'wind', 'win', 'wi', 'w') },
        @{ CanonicalName = 'noprofile';      DynamicType = $null;              ExpectsValue = $false; Aliases = @('noprofile', 'nop') },
        @{ CanonicalName = 'noninteractive'; DynamicType = $null;              ExpectsValue = $false; Aliases = @('noninteractive', 'noni') },
        @{ CanonicalName = 'nologo';         DynamicType = $null;              ExpectsValue = $false; Aliases = @('nologo', 'nol') },
        @{ CanonicalName = 'noexit';         DynamicType = $null;              ExpectsValue = $false; Aliases = @('noexit') },
        @{ CanonicalName = 'sta';            DynamicType = $null;              ExpectsValue = $false; Aliases = @('sta') },
        @{ CanonicalName = 'mta';            DynamicType = $null;              ExpectsValue = $false; Aliases = @('mta') },
        @{ CanonicalName = 'inputformat';    DynamicType = $null;              ExpectsValue = $true;  Aliases = @('inputformat') },
        @{ CanonicalName = 'outputformat';   DynamicType = $null;              ExpectsValue = $true;  Aliases = @('outputformat') },
        @{ CanonicalName = 'version';        DynamicType = $null;              ExpectsValue = $true;  Aliases = @('version') },
        @{ CanonicalName = 'file';           DynamicType = $null;              ExpectsValue = $true;  Aliases = @('file', 'f') }
    )

    foreach ($definition in $definitions) {
        foreach ($alias in @($definition.Aliases)) {
            if ($normalized -eq $alias) {
                return [PSCustomObject]@{
                    CanonicalName = [string]$definition.CanonicalName
                    DynamicType   = if ($definition.DynamicType) { [string]$definition.DynamicType } else { $null }
                    ExpectsValue  = [bool]$definition.ExpectsValue
                }
            }
        }
    }

    return $null
}

function Get-PowerShellHostBarePayloadInfo {
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Language.CommandAst]$CommandAst
    )

    $cmdName = $CommandAst.GetCommandName()
    if (-not (Test-PowerShellHostCommandName -CommandName $cmdName)) {
        return $null
    }

    $elements = @($CommandAst.CommandElements)
    if ($elements.Count -lt 2) { return $null }

    $sourceText = $CommandAst.Extent.StartScriptPosition.GetFullScript()
    $payloadIndex = $null

    for ($i = 1; $i -lt $elements.Count; $i++) {
        $elem = $elements[$i]
        if ($elem -is [System.Management.Automation.Language.CommandParameterAst]) {
            $paramInfo = Resolve-PowerShellHostParameterInfo -ParameterName ([string]$elem.ParameterName)
            if (-not $paramInfo) {
                $payloadIndex = $i
                break
            }

            if ($paramInfo.CanonicalName -eq 'file') {
                return $null
            }

            if ($paramInfo.DynamicType) {
                return $null
            }

            if ($paramInfo.ExpectsValue) {
                if ($elem.Argument) {
                    continue
                }

                if ($i + 1 -lt $elements.Count -and $elements[$i + 1] -isnot [System.Management.Automation.Language.CommandParameterAst]) {
                    $i++
                    continue
                }

                return $null
            }

            continue
        }

        $payloadIndex = $i
        break
    }

    if ($null -eq $payloadIndex) { return $null }

    $payloadStart = $elements[$payloadIndex].Extent.StartOffset
    $payloadEnd = $elements[$elements.Count - 1].Extent.EndOffset
    if ($payloadEnd -le $payloadStart) { return $null }

    $payloadText = $sourceText.Substring($payloadStart, $payloadEnd - $payloadStart).Trim()
    if ([string]::IsNullOrWhiteSpace($payloadText)) { return $null }

    return [PSCustomObject]@{
        HostCommandName = $cmdName
        DynamicType     = 'PowerShellCommand'
        ParameterName   = $null
        ParameterAst    = $null
        ArgumentAst     = $null
        PayloadText     = $payloadText
        EvaluationCode  = ConvertTo-SingleQuotedStringLiteral -Text $payloadText
        PayloadSource   = 'BareTail'
    }
}

function Get-PowerShellHostPayloadEvaluationCode {
    param($PayloadAst)

    if ($null -eq $PayloadAst) { return $null }

    if ($PayloadAst -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
        $stringType = if ($PayloadAst.PSObject.Properties['StringConstantType']) { [string]$PayloadAst.StringConstantType } else { '' }
        if ($stringType -eq 'BareWord') {
            return (ConvertTo-SingleQuotedStringLiteral -Text $PayloadAst.Value)
        }
    }

    return [string]$PayloadAst.Extent.Text
}

function Get-SafePSBaseObject {
    param($Value)

    if ($null -eq $Value) { return $null }

    try {
        $psObject = $Value.PSObject
    } catch {
        return $null
    }

    if ($null -eq $psObject) { return $null }

    try {
        return $psObject.BaseObject
    } catch {
        return $null
    }
}

function Unwrap-SafePSBaseObject {
    param($Value)

    if ($null -eq $Value) { return $null }

    $baseObject = Get-SafePSBaseObject -Value $Value
    if ($null -ne $baseObject -and $baseObject -ne $Value) {
        return $baseObject
    }

    return $Value
}

function Get-GenerateObjectPropertyValue {
    param(
        $Object,
        [Parameter(Mandatory)][string]$Name,
        $Default = $null
    )

    if ($null -eq $Object) { return $Default }

    if ($Object -is [hashtable]) {
        if ($Object.ContainsKey($Name)) {
            return $Object[$Name]
        }
        return $Default
    }

    $prop = $Object.PSObject.Properties[$Name]
    if ($null -ne $prop) {
        return $prop.Value
    }

    return $Default
}

function Convert-DynamicCommandCandidateToName {
    param($Value)

    if ($null -eq $Value) { return $null }
    $Value = Unwrap-SafePSBaseObject -Value $Value

    if ($Value -is [string]) {
        $name = $Value.Trim()
    } elseif ($Value -is [char[]]) {
        $name = (-join $Value).Trim()
    } elseif ($Value -is [array]) {
        if (@($Value).Count -eq 1) {
            return Convert-DynamicCommandCandidateToName -Value $Value[0]
        }
        return $null
    } else {
        $name = [string]$Value
        if (-not [string]::IsNullOrWhiteSpace($name)) {
            $name = $name.Trim()
        }
    }

    if ([string]::IsNullOrWhiteSpace($name)) { return $null }
    if ($name -match '^[&\.]\s*(.+)$') {
        $name = [string]$Matches[1].Trim()
    }

    return $name
}

function Resolve-SafeDynamicCommandNameExpressionValue {
    param(
        $Ast,
        [int]$Depth = 0
    )

    if ($null -eq $Ast -or $Depth -gt 24) {
        return [PSCustomObject]@{ Success = $false; Value = $null }
    }

    if ($Ast -is [System.Management.Automation.Language.CommandExpressionAst]) {
        return Resolve-SafeDynamicCommandNameExpressionValue -Ast $Ast.Expression -Depth ($Depth + 1)
    }

    if ($Ast -is [System.Management.Automation.Language.ParenExpressionAst]) {
        if ($Ast.Pipeline -and $Ast.Pipeline.PipelineElements -and $Ast.Pipeline.PipelineElements.Count -eq 1) {
            $elem = $Ast.Pipeline.PipelineElements[0]
            if ($elem -is [System.Management.Automation.Language.CommandAst]) {
                return Resolve-SafeDynamicCommandNameExpressionValue -Ast $elem -Depth ($Depth + 1)
            }
            if ($elem -is [System.Management.Automation.Language.CommandExpressionAst]) {
                return Resolve-SafeDynamicCommandNameExpressionValue -Ast $elem.Expression -Depth ($Depth + 1)
            }
            if ($elem.PSObject.Properties['Expression']) {
                return Resolve-SafeDynamicCommandNameExpressionValue -Ast $elem.Expression -Depth ($Depth + 1)
            }
        }
        return [PSCustomObject]@{ Success = $false; Value = $null }
    }

    if ($Ast -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
        return [PSCustomObject]@{ Success = $true; Value = [string]$Ast.Value }
    }

    if ($Ast -is [System.Management.Automation.Language.ConstantExpressionAst]) {
        return [PSCustomObject]@{ Success = $true; Value = $Ast.Value }
    }

    if ($Ast -is [System.Management.Automation.Language.ArrayLiteralAst]) {
        $items = @()
        foreach ($elem in $Ast.Elements) {
            $itemResult = Resolve-SafeDynamicCommandNameExpressionValue -Ast $elem -Depth ($Depth + 1)
            if (-not $itemResult.Success) {
                return [PSCustomObject]@{ Success = $false; Value = $null }
            }
            $items += $itemResult.Value
        }
        return [PSCustomObject]@{ Success = $true; Value = @($items) }
    }

    if ($Ast -is [System.Management.Automation.Language.VariableExpressionAst]) {
        $varName = [string]$Ast.VariablePath.UserPath
        if ([string]::IsNullOrWhiteSpace($varName)) {
            return [PSCustomObject]@{ Success = $false; Value = $null }
        }
        try {
            $value = Get-Variable -Name $varName -ValueOnly -ErrorAction Stop
            return [PSCustomObject]@{ Success = $true; Value = $value }
        } catch {
            return [PSCustomObject]@{ Success = $false; Value = $null }
        }
    }

    if ($Ast -is [System.Management.Automation.Language.IndexExpressionAst]) {
        $targetResult = Resolve-SafeDynamicCommandNameExpressionValue -Ast $Ast.Target -Depth ($Depth + 1)
        if (-not $targetResult.Success) {
            return [PSCustomObject]@{ Success = $false; Value = $null }
        }

        $indexAst = if ($Ast.Index -is [System.Management.Automation.Language.CommandExpressionAst]) {
            $Ast.Index.Expression
        } else {
            $Ast.Index
        }
        $indexResult = Resolve-SafeDynamicCommandNameExpressionValue -Ast $indexAst -Depth ($Depth + 1)
        if (-not $indexResult.Success) {
            return [PSCustomObject]@{ Success = $false; Value = $null }
        }

        $targetValue = $targetResult.Value
        $indexes = if ($indexResult.Value -is [array]) { @($indexResult.Value) } else { @($indexResult.Value) }
        $resolved = @()

        if ($targetValue -is [string]) {
            foreach ($idx in $indexes) {
                try {
                    $resolved += $targetValue[[int]$idx]
                } catch {
                    return [PSCustomObject]@{ Success = $false; Value = $null }
                }
            }
        } else {
            $targetItems = if (($targetValue -is [System.Collections.IEnumerable]) -and -not ($targetValue -is [string])) {
                @($targetValue)
            } else {
                @($targetValue)
            }
            foreach ($idx in $indexes) {
                try {
                    $resolved += $targetItems[[int]$idx]
                } catch {
                    return [PSCustomObject]@{ Success = $false; Value = $null }
                }
            }
        }

        if ($resolved.Count -eq 1) {
            return [PSCustomObject]@{ Success = $true; Value = $resolved[0] }
        }
        return [PSCustomObject]@{ Success = $true; Value = @($resolved) }
    }

    if ($Ast -is [System.Management.Automation.Language.BinaryExpressionAst]) {
        $leftResult = Resolve-SafeDynamicCommandNameExpressionValue -Ast $Ast.Left -Depth ($Depth + 1)
        $rightResult = Resolve-SafeDynamicCommandNameExpressionValue -Ast $Ast.Right -Depth ($Depth + 1)
        if (-not $leftResult.Success -or -not $rightResult.Success) {
            return [PSCustomObject]@{ Success = $false; Value = $null }
        }

        switch ([string]$Ast.Operator) {
            'Plus' {
                if ($leftResult.Value -is [array] -or $rightResult.Value -is [array]) {
                    return [PSCustomObject]@{ Success = $true; Value = @(@($leftResult.Value) + @($rightResult.Value)) }
                }
                return [PSCustomObject]@{ Success = $true; Value = ([string]$leftResult.Value + [string]$rightResult.Value) }
            }
            'Join' {
                $separator = [string]$rightResult.Value
                $items = @($leftResult.Value)
                return [PSCustomObject]@{ Success = $true; Value = (($items | ForEach-Object { [string]$_ }) -join $separator) }
            }
        }

        return [PSCustomObject]@{ Success = $false; Value = $null }
    }

    if ($Ast -is [System.Management.Automation.Language.ConvertExpressionAst]) {
        $childResult = Resolve-SafeDynamicCommandNameExpressionValue -Ast $Ast.Child -Depth ($Depth + 1)
        if (-not $childResult.Success) {
            return [PSCustomObject]@{ Success = $false; Value = $null }
        }

        try {
            switch ([string]$Ast.Type.TypeName.FullName) {
                'string' { return [PSCustomObject]@{ Success = $true; Value = [string]$childResult.Value } }
                'char'   { return [PSCustomObject]@{ Success = $true; Value = [char]$childResult.Value } }
                'int'    { return [PSCustomObject]@{ Success = $true; Value = [int]$childResult.Value } }
            }
        } catch {
            return [PSCustomObject]@{ Success = $false; Value = $null }
        }
    }

    return [PSCustomObject]@{ Success = $false; Value = $null }
}

function Get-WrappedDynamicInvocationInfo {
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Language.CommandAst]$CommandAst
    )

    $elements = @($CommandAst.CommandElements)
    if ($elements.Count -lt 1) { return $null }

    $wrapperOperator = $null
    $targetAst = $null
    $argumentStartIndex = $null

    switch ([string]$CommandAst.InvocationOperator) {
        'Ampersand' {
            $wrapperOperator = '&'
            $targetAst = $elements[0]
            $argumentStartIndex = 1
        }
        'Dot' {
            $wrapperOperator = '.'
            $targetAst = $elements[0]
            $argumentStartIndex = 1
        }
    }

    if (-not $wrapperOperator) {
        $headText = if ($elements[0] -and $elements[0].Extent) { [string]$elements[0].Extent.Text } else { $null }
        if ($headText -in @('&', '.')) {
            if ($elements.Count -lt 2) { return $null }
            $wrapperOperator = $headText
            $targetAst = $elements[1]
            $argumentStartIndex = 2
        }
    }

    if (-not $wrapperOperator -or $null -eq $targetAst) {
        return $null
    }

    $candidateName = $null
    if ($targetAst -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
        $candidateName = Convert-DynamicCommandCandidateToName -Value $targetAst.Value
    }
    if (-not $candidateName) {
        $safeEval = Resolve-SafeDynamicCommandNameExpressionValue -Ast $targetAst
        if ($safeEval.Success) {
            $candidateName = Convert-DynamicCommandCandidateToName -Value $safeEval.Value
        }
    }
    if ([string]::IsNullOrWhiteSpace($candidateName)) {
        return $null
    }

    if ($candidateName -in @('Invoke-Expression', 'iex')) {
        $argAst = if ($elements.Count -gt $argumentStartIndex) { $elements[$argumentStartIndex] } else { $null }
        return [PSCustomObject]@{
            DynamicType     = 'IEX'
            ArgumentAst     = $argAst
            WrapperOperator = $wrapperOperator
        }
    }

    if (Test-PowerShellHostCommandName -CommandName $candidateName) {
        for ($i = $argumentStartIndex; $i -lt $elements.Count; $i++) {
            $elem = $elements[$i]
            if ($elem -isnot [System.Management.Automation.Language.CommandParameterAst]) { continue }

            $paramName = [string]$elem.ParameterName
            $dynamicType = $null
            if (Test-PowerShellHostParameterPrefix -ParameterName $paramName -CanonicalName 'encodedcommand') {
                $dynamicType = 'EncodedCommand'
            } elseif (Test-PowerShellHostParameterPrefix -ParameterName $paramName -CanonicalName 'command') {
                $dynamicType = 'PowerShellCommand'
            }
            if (-not $dynamicType) { continue }

            $argAst = $null
            if ($elem.Argument) {
                $argAst = $elem.Argument
            } elseif ($i + 1 -lt $elements.Count) {
                $argAst = $elements[$i + 1]
            }

            return [PSCustomObject]@{
                DynamicType     = $dynamicType
                ArgumentAst     = $argAst
                WrapperOperator = $wrapperOperator
            }
        }
    }

    return $null
}

function Get-PowerShellHostDynamicInvocationInfo {
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Language.CommandAst]$CommandAst
    )

    $cmdName = $CommandAst.GetCommandName()
    if (-not (Test-PowerShellHostCommandName -CommandName $cmdName)) {
        return $null
    }

    $elements = @($CommandAst.CommandElements)
    if ($elements.Count -lt 2) { return $null }

    $sourceText = $CommandAst.Extent.StartScriptPosition.GetFullScript()

    for ($i = 1; $i -lt $elements.Count; $i++) {
        $elem = $elements[$i]
        if ($elem -isnot [System.Management.Automation.Language.CommandParameterAst]) {
            continue
        }

        $paramInfo = Resolve-PowerShellHostParameterInfo -ParameterName ([string]$elem.ParameterName)
        $paramName = if ($paramInfo) { [string]$paramInfo.CanonicalName } else { [string]$elem.ParameterName }
        $dynamicType = if ($paramInfo) { $paramInfo.DynamicType } else { $null }

        if (-not $dynamicType) {
            continue
        }

        $payloadAst = $null
        $payloadText = $null
        $evaluationCode = $null

        if ($elem.Argument) {
            $payloadAst = $elem.Argument
            $payloadText = [string]$payloadAst.Extent.Text
            $evaluationCode = Get-PowerShellHostPayloadEvaluationCode -PayloadAst $payloadAst
        } elseif ($i + 1 -lt $elements.Count) {
            $payloadAst = $elements[$i + 1]
            $payloadStart = $payloadAst.Extent.StartOffset
            $payloadEnd = if ($dynamicType -eq 'PowerShellCommand') {
                $elements[$elements.Count - 1].Extent.EndOffset
            } else {
                $payloadAst.Extent.EndOffset
            }

            if ($payloadEnd -gt $payloadStart) {
                $payloadText = $sourceText.Substring($payloadStart, $payloadEnd - $payloadStart)
                if ($dynamicType -eq 'PowerShellCommand') {
                    $payloadElems = @($elements | Select-Object -Skip ($i + 1))
                    if ($payloadElems.Count -eq 1 -and $payloadElems[0] -isnot [System.Management.Automation.Language.CommandParameterAst]) {
                        $evaluationCode = Get-PowerShellHostPayloadEvaluationCode -PayloadAst $payloadElems[0]
                    } else {
                        $evaluationCode = ConvertTo-SingleQuotedStringLiteral -Text $payloadText
                    }
                } else {
                    $evaluationCode = Get-PowerShellHostPayloadEvaluationCode -PayloadAst $payloadAst
                }
            }
        }

        return [PSCustomObject]@{
            HostCommandName = $cmdName
            DynamicType     = $dynamicType
            ParameterName   = $paramName
            ParameterAst    = $elem
            ArgumentAst     = $payloadAst
            PayloadText     = $payloadText
            EvaluationCode  = $evaluationCode
            PayloadSource   = if ($dynamicType -eq 'EncodedCommand') { 'EncodedCommand' } else { 'CommandParameter' }
        }
    }

    return Get-PowerShellHostBarePayloadInfo -CommandAst $CommandAst
}

function Get-DynamicInvokeInfo {
    param(
        [Parameter(Mandatory = $true)]
        $ast
    )

    if ($null -eq $ast) { return $null }

    $results = @()

    $commandAsts = @($ast.FindAll({
        param($n)
        $n -is [System.Management.Automation.Language.CommandAst]
    }, $true))

    foreach ($cmdAst in $commandAsts) {
        $cmdName = $cmdAst.GetCommandName()
        if ($cmdName -in @('Invoke-Expression', 'iex')) {
            $argAst = $null
            if ($cmdAst.CommandElements.Count -gt 1) {
                $argAst = $cmdAst.CommandElements[1]
            }
            $results += @{
                Type   = "IEX"
                ArgAst = $argAst
            }
        }

        $hostDynamicInfo = Get-PowerShellHostDynamicInvocationInfo -CommandAst $cmdAst
        if ($hostDynamicInfo -and (Get-GenerateObjectPropertyValue -Object $hostDynamicInfo -Name 'DynamicType' -Default $null) -eq 'PowerShellCommand') {
            $results += @{
                Type   = 'PowerShellCommand'
                ArgAst = $hostDynamicInfo.ArgumentAst
            }
        }

        $wrappedDynamicInfo = Get-WrappedDynamicInvocationInfo -CommandAst $cmdAst
        if ($wrappedDynamicInfo) {
            $results += @{
                Type   = (Get-GenerateObjectPropertyValue -Object $wrappedDynamicInfo -Name 'DynamicType' -Default $null)
                ArgAst = $wrappedDynamicInfo.ArgumentAst
            }
        }
    }

    $invokeMemberAsts = @($ast.FindAll({
        param($n)
        $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst]
    }, $true))

    foreach ($invokeAst in $invokeMemberAsts) {
        if (-not $invokeAst.Static) { continue }

        $memberName = $invokeAst.Member
        if ($memberName -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
            $memberName = $memberName.Value
        }
        if ($memberName -ne 'Create') { continue }

        $typeExpr = $invokeAst.Expression
        if ($typeExpr -is [System.Management.Automation.Language.TypeExpressionAst]) {
            $typeName = $typeExpr.TypeName.FullName
            if ($typeName -in @('ScriptBlock', 'System.Management.Automation.ScriptBlock')) {
                $argAst = $null
                if ($invokeAst.Arguments.Count -gt 0) {
                    $argAst = $invokeAst.Arguments[0]
                }
                $results += @{
                    Type   = "ScriptBlockCreate"
                    ArgAst = $argAst
                }
            }
        }
    }

    foreach ($invokeAst in $invokeMemberAsts) {
        if ($invokeAst.Static) { continue }

        $memberName = $invokeAst.Member
        if ($memberName -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
            $memberName = $memberName.Value
        }
        if ($memberName -ne 'NewScriptBlock') { continue }

        $argAst = $null
        if ($invokeAst.Arguments.Count -gt 0) {
            $argAst = $invokeAst.Arguments[0]
        }
        $results += @{
            Type   = "NewScriptBlock"
            ArgAst = $argAst
        }
    }

    if ($results.Count -eq 0) {
        return $null
    }
    elseif ($results.Count -eq 1) {
        return $results[0]
    }
    else {
        return $results
    }
}

function Add-Node {
    param(
        $cfg,
        $type,
        $text,
        $line,
        $ast = $null,
        $ownerAst = $null
    )
    $node = [PSCustomObject]@{
        Id              = $cfg.Nodes.Count + 1
        Type            = $type
        Text            = $text
        Line            = $line
        Ast             = $ast
        OwnerAst        = $ownerAst
        TextStartOffset = if ($null -ne $ast) { $ast.Extent.StartOffset } else { $null }
        TextEndOffset   = if ($null -ne $ast) { $ast.Extent.EndOffset } else { $null }
        VarsRead        = @()
        VarsWritten     = @()
        DynamicInvoke   = $null
        Invokes         = @{ Functions = @(); ScriptBlocks = @() }
        Resolvables     = @()
        AliasesUsed     = @()
    }

    if ($null -ne $ast) {
        Populate-NodeVariableUsage -node $node
        $node.DynamicInvoke = Get-DynamicInvokeInfo -ast $ast
        Populate-NodeInvokes -node $node -cfg $cfg
        Populate-NodeResolvables -node $node

        $commandAsts = @($ast.FindAll({
            param($n)
            $n -is [System.Management.Automation.Language.CommandAst]
        }, $true))
        foreach ($cmdAst in $commandAsts) {
            $aliasDef = Get-AliasDefinitionFromCommand -cmdAst $cmdAst
            if ($null -ne $aliasDef) {
                $cfg.DefinedAliases[$aliasDef.Name] = $aliasDef.Value
            }
        }

        Populate-NodeAliasUsage -node $node -cfg $cfg
    }

    $cfg.Nodes += $node
    return $node
}

function Add-Edge {
    param($cfg, $from, $to, $label = $null)
    $edge = [PSCustomObject]@{
        From  = $from
        To    = $to
        Label = $label
    }
    $cfg.Edges += $edge
}

function Add-VarToNode {
    param(
        [pscustomobject]$node,
        [pscustomobject]$varEntry,
        [ValidateSet("Read", "Write", "Both")]
        [string]$accessType
    )

    if ($accessType -in "Read", "Both") {
        $exists = $node.VarsRead | Where-Object { $_.Name -eq $varEntry.Name -and $_.Scope -eq $varEntry.Scope }
        if (-not $exists) {
            $node.VarsRead = @($node.VarsRead) + @($varEntry)
        }
    }

    if ($accessType -in "Write", "Both") {
        $exists = $node.VarsWritten | Where-Object { $_.Name -eq $varEntry.Name -and $_.Scope -eq $varEntry.Scope }
        if (-not $exists) {
            $node.VarsWritten = @($node.VarsWritten) + @($varEntry)
        }
    }

    if ($varEntry.Name -match '^_block_[a-f0-9]{8}$') {
        $existsInInvokes = $node.Invokes.ScriptBlocks -contains $varEntry.Name
        if (-not $existsInInvokes) {
            $node.Invokes.ScriptBlocks = @($node.Invokes.ScriptBlocks) + @($varEntry.Name)
        }
    }
}

function Get-VariableAccessKind {
    param(
        [System.Management.Automation.Language.VariableExpressionAst]$VarAst
    )

    if ($null -eq $VarAst) { return $null }

    $parent = $VarAst.Parent

    if ($parent -is [System.Management.Automation.Language.ArrayLiteralAst]) {
        $arrayLiteral = $parent
        $grandParent = $arrayLiteral.Parent
        if ($grandParent -is [System.Management.Automation.Language.AssignmentStatementAst]) {
            $assign = $grandParent
            if ($assign.Left -eq $arrayLiteral -or
                ($null -ne $assign.Left -and $assign.Left.Find({ param($n) $n -eq $arrayLiteral }, $true))) {
                if ($assign.Operator -ne [System.Management.Automation.Language.TokenKind]::Equals) {
                    return "ReadWrite"
                }
                else {
                    return "Write"
                }
            }
        }
    }

    if ($parent -is [System.Management.Automation.Language.AssignmentStatementAst]) {
        $assign = $parent
        $inLeft = $false
        if ($null -ne $assign.Left) {
            if ($assign.Left -eq $VarAst) {
                $inLeft = $true
            }
            elseif ($assign.Left -is [System.Management.Automation.Language.Ast]) {
                $inLeft = $assign.Left.Find({ param($n) $n -eq $VarAst }, $true)
            }
        }

        if ($inLeft) {
            if ($assign.Operator -ne [System.Management.Automation.Language.TokenKind]::Equals) {
                return "ReadWrite"
            }
            else {
                return "Write"
            }
        }
        else {
            return "Read"
        }
    }

    if ($parent -is [System.Management.Automation.Language.IndexExpressionAst]) {
        $indexExpr = $parent
        if ($indexExpr.Target -eq $VarAst) {
            $currentExpr = $indexExpr
            while ($null -ne $currentExpr) {
                $grandParent = $currentExpr.Parent
                if ($grandParent -is [System.Management.Automation.Language.AssignmentStatementAst]) {
                    $assign = $grandParent
                    $inLeft = $false
                    if ($null -ne $assign.Left) {
                        if ($assign.Left -eq $currentExpr) {
                            $inLeft = $true
                        }
                        elseif ($assign.Left -is [System.Management.Automation.Language.Ast]) {
                            $inLeft = $assign.Left.Find({ param($n) $n -eq $currentExpr }, $true)
                        }
                    }
                    if ($inLeft) {
                        return "ReadWrite"
                    }
                    break
                }
                elseif ($grandParent -is [System.Management.Automation.Language.IndexExpressionAst]) {
                    $currentExpr = $grandParent
                }
                else {
                    break
                }
            }
        }
        return "Read"
    }

    if ($parent -is [System.Management.Automation.Language.MemberExpressionAst]) {
        $memberExpr = $parent
        if ($memberExpr.Expression -eq $VarAst) {
            $currentExpr = $memberExpr
            while ($null -ne $currentExpr) {
                $grandParent = $currentExpr.Parent
                if ($grandParent -is [System.Management.Automation.Language.AssignmentStatementAst]) {
                    $assign = $grandParent
                    $inLeft = $false
                    if ($null -ne $assign.Left) {
                        if ($assign.Left -eq $currentExpr) {
                            $inLeft = $true
                        }
                        elseif ($assign.Left -is [System.Management.Automation.Language.Ast]) {
                            $inLeft = $assign.Left.Find({ param($n) $n -eq $currentExpr }, $true)
                        }
                    }
                    if ($inLeft) {
                        return "ReadWrite"
                    }
                    break
                }
                elseif ($grandParent -is [System.Management.Automation.Language.MemberExpressionAst] -or
                        $grandParent -is [System.Management.Automation.Language.IndexExpressionAst]) {
                    $currentExpr = $grandParent
                }
                else {
                    break
                }
            }
        }
        return "Read"
    }

    if ($parent -is [System.Management.Automation.Language.UnaryExpressionAst]) {
        $unary = $parent
        if ($unary.TokenKind -in @(
                [System.Management.Automation.Language.TokenKind]::PlusPlus,
                [System.Management.Automation.Language.TokenKind]::MinusMinus,
                [System.Management.Automation.Language.TokenKind]::PostfixPlusPlus,
                [System.Management.Automation.Language.TokenKind]::PostfixMinusMinus
            )) {
            return "ReadWrite"
        }
        return "Read"
    }

    if ($parent -is [System.Management.Automation.Language.ParameterAst]) {
        return "Write"
    }

    if ($parent -is [System.Management.Automation.Language.ForEachStatementAst]) {
        if ($parent.Variable -eq $VarAst) {
            return "Write"
        }
    }

    return "Read"
}

function Populate-NodeVariableUsage {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$node
    )

    if ($null -eq $node.Ast) {
        $node.VarsRead    = @()
        $node.VarsWritten = @()
        return
    }

    $reads  = @()
    $writes = @()

    $varAsts = $node.Ast.FindAll({
            param($n)
            if ($n -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
                return $false
            }
            $n -is [System.Management.Automation.Language.VariableExpressionAst]
        }, $true)

    $varAsts = @($varAsts | Where-Object {
        $ancestor = $_.Parent
        while ($null -ne $ancestor -and $ancestor -ne $node.Ast) {
            if ($ancestor -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
                return $false
            }
            $ancestor = $ancestor.Parent
        }
        return $true
    })

    foreach ($v in $varAsts) {
        $kind = Get-VariableAccessKind -VarAst $v
        if (-not $kind) { continue }

        $scope = [VarScope]::Unspecified
        if     ($v.VariablePath.IsGlobal)  { $scope = [VarScope]::Global }
        elseif ($v.VariablePath.IsScript)  { $scope = [VarScope]::Script }
        elseif ($v.VariablePath.IsLocal)   { $scope = [VarScope]::Local }
        elseif ($v.VariablePath.IsPrivate) { $scope = [VarScope]::Private }

        $name = $v.VariablePath.UserPath
        if ($scope -ne [VarScope]::Unspecified -and $name -match ':') {
            $name = $name -replace '^[^:]+:', ''
        }
        if ([string]::IsNullOrWhiteSpace($name)) { continue }

        $readEntry = [PSCustomObject]@{
            Name        = $name
            Scope       = $scope
            StartOffset = $v.Extent.StartOffset
            EndOffset   = $v.Extent.EndOffset
            Text        = $v.Extent.Text
        }

        $writeEntry = [PSCustomObject]@{
            Name  = $name
            Scope = $scope
        }

        switch ($kind) {
            "Read" {
                $reads += $readEntry
            }
            "Write" {
                $writes += $writeEntry
            }
            "ReadWrite" {
                $reads  += $readEntry
                $writes += $writeEntry
            }
        }
    }

    $node.VarsRead = @($reads)
    $node.VarsWritten = @(
        $writes |
            Group-Object Name, Scope |
            ForEach-Object { $_.Group[0] }
    )
}

function Populate-NodeInvokes {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$node,
        [Parameter(Mandatory = $true)]
        [hashtable]$cfg
    )

    $node.Invokes = @{
        Functions    = @()
        ScriptBlocks = @()
    }

    if ($null -eq $node.Ast) { return }

    $commandAsts = @($node.Ast.FindAll({
        param($n)
        if ($n -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
            return $false
        }
        $n -is [System.Management.Automation.Language.CommandAst]
    }, $true))

    $commandAsts = @($commandAsts | Where-Object {
        $ancestor = $_.Parent
        while ($null -ne $ancestor -and $ancestor -ne $node.Ast) {
            if ($ancestor -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
                return $false
            }
            $ancestor = $ancestor.Parent
        }
        return $true
    })

    $funcCalls = @()
    foreach ($cmdAst in $commandAsts) {
        $cmdName = $cmdAst.GetCommandName()
        if (-not [string]::IsNullOrWhiteSpace($cmdName)) {
            if ($cfg.DefinedFunctions.Contains($cmdName)) {
                $funcCalls += $cmdName
            }
        }
    }
    $node.Invokes.Functions = @($funcCalls | Select-Object -Unique)

    $allVars = @($node.VarsRead) + @($node.VarsWritten)
    $blockVars = @($allVars | Where-Object {
        $_.Name -match '^_block_[a-f0-9]{8}$'
    } | ForEach-Object { $_.Name })
    $node.Invokes.ScriptBlocks = @($blockVars | Select-Object -Unique)
}

function Try-DecodeEncodedCommand {
    param(
        [Parameter(Mandatory=$true)]
        [System.Management.Automation.Language.CommandAst]$CommandAst
    )

    $hostDynamicInfo = Get-PowerShellHostDynamicInvocationInfo -CommandAst $CommandAst
    if (-not $hostDynamicInfo -or (Get-GenerateObjectPropertyValue -Object $hostDynamicInfo -Name 'DynamicType' -Default $null) -ne 'EncodedCommand') {
        return $null
    }

    $valueElem = $hostDynamicInfo.ArgumentAst
    $base64String = $null
    if ($valueElem -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
        $base64String = $valueElem.Value
    } elseif ($valueElem -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) {
        $base64String = $valueElem.Value
    }

    if (-not $base64String) {
        return $null
    }

    try {
        $bytes = [Convert]::FromBase64String($base64String)

        $decoded = [Text.Encoding]::Unicode.GetString($bytes)

        $replacementText = ConvertTo-CanonicalPowerShellHostCommandText -CommandAst $CommandAst -PayloadText $decoded -HostDynamicInfo $hostDynamicInfo

        return @{
            ReplacementText = $replacementText
            DecodedContent = $decoded
            OriginalBase64 = $base64String
        }

    } catch {
        Write-Warning "[EncodedCommand] 解码失败: $_"
        return $null
    }
}

function Populate-NodeResolvables {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$node
    )

    $node.Resolvables = @()
    if ($null -eq $node.Ast) { return }

    $targetTypes = @(
        [System.Management.Automation.Language.BinaryExpressionAst],
        [System.Management.Automation.Language.UnaryExpressionAst],
        [System.Management.Automation.Language.InvokeMemberExpressionAst],
        [System.Management.Automation.Language.ConvertExpressionAst],
        [System.Management.Automation.Language.ExpandableStringExpressionAst],
        [System.Management.Automation.Language.IndexExpressionAst],
        [System.Management.Automation.Language.SubExpressionAst],
        [System.Management.Automation.Language.MemberExpressionAst],
        [System.Management.Automation.Language.ParenExpressionAst],
        [System.Management.Automation.Language.CommandAst]
    )

    $allExprs = @($node.Ast.FindAll({
        param($n)
        if ($n -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) { return $false }
        ($n -is [System.Management.Automation.Language.BinaryExpressionAst]) -or
        ($n -is [System.Management.Automation.Language.UnaryExpressionAst]) -or
        ($n -is [System.Management.Automation.Language.InvokeMemberExpressionAst]) -or
        ($n -is [System.Management.Automation.Language.ConvertExpressionAst]) -or
        ($n -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) -or
        ($n -is [System.Management.Automation.Language.IndexExpressionAst]) -or
        ($n -is [System.Management.Automation.Language.SubExpressionAst]) -or
        ($n -is [System.Management.Automation.Language.MemberExpressionAst]) -or
        ($n -is [System.Management.Automation.Language.ParenExpressionAst]) -or
        ($n -is [System.Management.Automation.Language.CommandAst])
    }, $true))

    $allExprs = @($allExprs | Where-Object {
        $ancestor = $_.Parent
        while ($null -ne $ancestor -and $ancestor -ne $node.Ast) {
            if ($ancestor -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
                return $false
            }
            $ancestor = $ancestor.Parent
        }
        return $true
    })


    $sortedExprs = $allExprs | Sort-Object { $_.Extent.StartOffset }

    foreach ($expr in $sortedExprs) {
        $type = switch ($true) {
            ($expr -is [System.Management.Automation.Language.BinaryExpressionAst])           { "Binary" }
            ($expr -is [System.Management.Automation.Language.UnaryExpressionAst])            { "Unary" }
            ($expr -is [System.Management.Automation.Language.InvokeMemberExpressionAst])     { "MemberInvoke" }
            ($expr -is [System.Management.Automation.Language.ConvertExpressionAst])          { "Convert" }
            ($expr -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) { "ExpandableString" }
            ($expr -is [System.Management.Automation.Language.IndexExpressionAst])            { "Index" }
            ($expr -is [System.Management.Automation.Language.SubExpressionAst])              { "SubExpression" }
            ($expr -is [System.Management.Automation.Language.MemberExpressionAst])           { "Member" }
            ($expr -is [System.Management.Automation.Language.ParenExpressionAst])            { "Paren" }
            ($expr -is [System.Management.Automation.Language.CommandAst])                    { "Command" }
            default { "Unknown" }
        }

        $depth = 0
        $ancestor = $expr.Parent
        while ($null -ne $ancestor -and $ancestor -ne $node.Ast) {
            if ($ancestor -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) { break }
            foreach ($t in $targetTypes) {
                if ($ancestor -is $t) { $depth++; break }
            }
            $ancestor = $ancestor.Parent
        }

        $textToUse = $expr.Extent.Text
        if ($type -eq "Command" -and $expr -is [System.Management.Automation.Language.CommandAst]) {
            $decodedInfo = Try-DecodeEncodedCommand -CommandAst $expr
            if ($decodedInfo) {
                $textToUse = $decodedInfo.ReplacementText
                Write-Verbose "[EncodedCommand] 解码成功: $($decodedInfo.OriginalBase64.Substring(0, [Math]::Min(20, $decodedInfo.OriginalBase64.Length)))... -> $($decodedInfo.DecodedContent.Substring(0, [Math]::Min(50, $decodedInfo.DecodedContent.Length)))..."
            }
        }

        $node.Resolvables += @{
            Type        = $type
            Ast         = $expr
            Text        = $textToUse
            StartOffset = $expr.Extent.StartOffset
            EndOffset   = $expr.Extent.EndOffset
            Depth       = $depth
        }
    }
}

function Get-AliasDefinitionFromCommand {
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Language.CommandAst]$cmdAst
    )

    $cmdName = $cmdAst.GetCommandName()
    if ($cmdName -notin @('Set-Alias', 'New-Alias', 'sal', 'nal')) {
        return $null
    }

    $aliasName = $null
    $aliasValue = $null

    $elements = $cmdAst.CommandElements
    for ($i = 1; $i -lt $elements.Count; $i++) {
        $elem = $elements[$i]

        if ($elem -is [System.Management.Automation.Language.CommandParameterAst]) {
            $paramName = $elem.ParameterName.ToLower()
            if ($paramName -in @('name', 'n')) {
                if ($i + 1 -lt $elements.Count) {
                    $nextElem = $elements[$i + 1]
                    if ($nextElem -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                        $aliasName = $nextElem.Value
                    } elseif ($nextElem -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) {
                        $aliasName = $nextElem.Value
                    }
                    $i++
                }
            }
            elseif ($paramName -in @('value', 'val', 'v')) {
                if ($i + 1 -lt $elements.Count) {
                    $nextElem = $elements[$i + 1]
                    if ($nextElem -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                        $aliasValue = $nextElem.Value
                    } elseif ($nextElem -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) {
                        $aliasValue = $nextElem.Value
                    }
                    $i++
                }
            }
        }
        elseif ($elem -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
            if ($null -eq $aliasName) {
                $aliasName = $elem.Value
            } elseif ($null -eq $aliasValue) {
                $aliasValue = $elem.Value
            }
        }
    }

    if ($null -ne $aliasName -and $null -ne $aliasValue) {
        return @{
            Name  = $aliasName
            Value = $aliasValue
        }
    }
    return $null
}

function Populate-NodeAliasUsage {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$node,
        [Parameter(Mandatory = $true)]
        [hashtable]$cfg
    )

    $node.AliasesUsed = @()
    if ($null -eq $node.Ast) { return }

    $commandAsts = @($node.Ast.FindAll({
        param($n)
        if ($n -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) { return $false }
        $n -is [System.Management.Automation.Language.CommandAst]
    }, $true))

    $commandAsts = @($commandAsts | Where-Object {
        $ancestor = $_.Parent
        while ($null -ne $ancestor -and $ancestor -ne $node.Ast) {
            if ($ancestor -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
                return $false
            }
            $ancestor = $ancestor.Parent
        }
        return $true
    })

    foreach ($cmdAst in $commandAsts) {
        $cmdName = $cmdAst.GetCommandName()
        if (-not [string]::IsNullOrWhiteSpace($cmdName)) {
            if ($cfg.DefinedAliases.ContainsKey($cmdName)) {
                $node.AliasesUsed += @{
                    Name   = $cmdName
                    Target = $cfg.DefinedAliases[$cmdName]
                    Ast    = $cmdAst
                }
            }
        }
    }
}

# function Get-AllFunctionCalls {
#     param(
#         [Parameter(Mandatory = $true)]
#         $ast,
#         [Parameter(Mandatory = $true)]
#         [hashtable]$cfg
#     )

#     if ($null -eq $ast) { return @() }

#     $definedFuncs = $cfg.DefinedFunctions

#     $calls = $ast.FindAll({
#         param($n)
#         if (-not ($n -is [System.Management.Automation.Language.CommandAst])) { return $false }

#         $cmdName = $n.GetCommandName()
#         if ([string]::IsNullOrWhiteSpace($cmdName)) { return $false }

#         return $definedFuncs.Contains($cmdName)
#     }, $true)

#     return @($calls)
# }

function Get-AllNestedPipelines {
    param(
        [Parameter(Mandatory = $true)]
        $ast
    )

    if ($null -eq $ast) { return @() }

    $pipelines = $ast.FindAll({
        param($n)
        if ($n -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
            return $false
        }
        $n -is [System.Management.Automation.Language.PipelineAst] -and
        $n.PipelineElements.Count -gt 1
    }, $true)

    $pipelines = @($pipelines | Where-Object {
        $ancestor = $_.Parent
        while ($null -ne $ancestor -and $ancestor -ne $ast) {
            if ($ancestor -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
                return $false
            }
            $ancestor = $ancestor.Parent
        }
        return $true
    })

    return @($pipelines)
}

function Get-AllNestedScriptBlocks {
    param(
        [Parameter(Mandatory = $true)]
        $ast
    )

    if ($null -eq $ast) {
        Write-Output -NoEnumerate @()
        return
    }

    $scriptBlocks = $ast.FindAll({
        param($n)
        $n -is [System.Management.Automation.Language.ScriptBlockExpressionAst]
    }, $true)

    $scriptBlocks = @($scriptBlocks | Where-Object {
        $ancestor = $_.Parent
        while ($null -ne $ancestor -and $ancestor -ne $ast) {
            if ($ancestor -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
                return $false
            }
            $ancestor = $ancestor.Parent
        }
        return $true
    })

    Write-Output -NoEnumerate @($scriptBlocks)
}

function Get-ScriptBlockExecutionType {
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Language.ScriptBlockExpressionAst]$scriptBlockExprAst
    )

    $parent = $scriptBlockExprAst.Parent

    if ($parent -is [System.Management.Automation.Language.AssignmentStatementAst]) {
        return "Deferred"
    }

    if ($parent -is [System.Management.Automation.Language.CommandExpressionAst]) {
        $grandParent = $parent.Parent
        if ($grandParent -is [System.Management.Automation.Language.PipelineAst]) {
            return "PipelineValue"
        }
        return "Deferred"
    }

    if ($parent -is [System.Management.Automation.Language.CommandAst]) {
        $invocationOp = $parent.InvocationOperator
        if ($invocationOp -eq [System.Management.Automation.Language.TokenKind]::Ampersand -or
            $invocationOp -eq [System.Management.Automation.Language.TokenKind]::Dot) {
            if ($parent.CommandElements.Count -eq 1 -and $parent.CommandElements[0] -eq $scriptBlockExprAst) {
                return "InvokeOnly"
            }
            return "Immediate"
        }

        $cmdName = $parent.GetCommandName()
        if ($cmdName -in @('Where-Object', 'ForEach-Object', 'Where', 'ForEach', '?', '%',
                           'Sort-Object', 'Group-Object', 'Select-Object', 'Measure-Object')) {
            return "Immediate"
        }
        if ($cmdName -in @('Invoke-Command', 'Start-Job', 'Register-ObjectEvent',
                           'Register-EngineEvent', 'New-Event')) {
            return "CmdletInvoke"
        }
    }

    if ($parent -is [System.Management.Automation.Language.InvokeMemberExpressionAst]) {
        $memberName = $parent.Member.Value
        if ($memberName -in @('Where', 'ForEach')) {
            return "Immediate"
        }
    }

    if ($parent -is [System.Management.Automation.Language.CommandParameterAst]) {
        $cmdAst = $parent.Parent
        if ($cmdAst -is [System.Management.Automation.Language.CommandAst]) {
            $cmdName = $cmdAst.GetCommandName()
            if ($cmdName -in @('Invoke-Command', 'Start-Job', 'Register-ObjectEvent',
                               'Register-EngineEvent', 'New-Event')) {
                return "CmdletInvoke"
            }
        }
        $paramName = $parent.ParameterName
        if ($paramName -in @('FilterScript', 'Process', 'Begin', 'End')) {
            return "Immediate"
        }
        return "Deferred"
    }

    return "Deferred"
}

function Convert-ProcessBlock {
    param(
        [hashtable]$cfg,
        [System.Management.Automation.Language.ScriptBlockAst]$scriptBlockAst,
        [ref]$prevNodeRef,
        [ref]$endNodeRef,
        [bool]$UseProcessInputVar = $true,
        $switchContext = $null
    )

    if ($null -eq $scriptBlockAst -or
        $null -eq $scriptBlockAst.ProcessBlock -or
        $scriptBlockAst.ProcessBlock.Statements.Count -eq 0) {
        return
    }

    $processAst = $scriptBlockAst.ProcessBlock

    $guid = [guid]::NewGuid().ToString("N").Substring(0, 12)
    $collectionVar = "__prc_$guid"
    $indexVar = "__prc_${guid}_idx"
    $currentVar = "__prc_${guid}_current"

    $collectionVarEntry = [PSCustomObject]@{ Name = $collectionVar; Scope = [VarScope]::Unspecified }
    $indexVarEntry = [PSCustomObject]@{ Name = $indexVar; Scope = [VarScope]::Unspecified }
    $currentVarEntry = [PSCustomObject]@{ Name = $currentVar; Scope = [VarScope]::Unspecified }
    $processInputEntry = [PSCustomObject]@{ Name = "__proc_input"; Scope = [VarScope]::Unspecified }

    $inputExpr = if ($UseProcessInputVar) { '$__proc_input' } else { '@()' }

    $initText = "`$$collectionVar = $inputExpr; `$$indexVar = 0"
    $initNode = Add-Node -cfg $cfg -type "ProcessInit" -text $initText -line $processAst.Extent.StartLineNumber -ast $null -ownerAst $processAst
    $initNode.VarsRead = @()
    $initNode.VarsWritten = @()
    if ($UseProcessInputVar) {
        Add-VarToNode -node $initNode -varEntry $processInputEntry -accessType "Read"
    }
    Add-VarToNode -node $initNode -varEntry $collectionVarEntry -accessType "Write"
    Add-VarToNode -node $initNode -varEntry $indexVarEntry -accessType "Write"
    if ($null -ne $prevNodeRef.Value) {
        Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $initNode.Id
    }

    $condText = "[bool](`$$indexVar -lt `$$collectionVar.Count)"
    $conditionNode = Add-Node -cfg $cfg -type "ProcessCondition" -text $condText -line $processAst.Extent.StartLineNumber -ast $null -ownerAst $processAst
    $conditionNode.VarsRead = @($indexVarEntry, $collectionVarEntry)
    $conditionNode.VarsWritten = @()
    Add-Edge -cfg $cfg -from $initNode.Id -to $conditionNode.Id

    $loopEnd = Add-Node -cfg $cfg -type "ProcessEnd" -text "End Process" -line $processAst.Extent.EndLineNumber -ast $null -ownerAst $processAst
    Add-Edge -cfg $cfg -from $conditionNode.Id -to $loopEnd.Id -label "No more items"

    $bindText = "`$$currentVar = `$$collectionVar[`$$indexVar]"
    $bindNode = Add-Node -cfg $cfg -type "ProcessBind" -text $bindText -line $processAst.Extent.StartLineNumber -ast $null -ownerAst $processAst
    $bindNode.VarsRead = @($collectionVarEntry, $indexVarEntry)
    $bindNode.VarsWritten = @($currentVarEntry)
    Add-Edge -cfg $cfg -from $conditionNode.Id -to $bindNode.Id -label "Has next"

    $iterText = "`$$indexVar++"
    $iterNode = Add-Node -cfg $cfg -type "ProcessIter" -text $iterText -line $processAst.Extent.StartLineNumber -ast $null -ownerAst $processAst
    $iterNode.VarsRead = @($indexVarEntry)
    $iterNode.VarsWritten = @($indexVarEntry)
    Add-Edge -cfg $cfg -from $iterNode.Id -to $conditionNode.Id

    $processLoopContext = [PSCustomObject]@{
        LoopEnd      = $loopEnd
        LoopContinue = $iterNode
    }

    $currentNode = $bindNode
    $bodyNodeCountBefore = $cfg.Nodes.Count
    foreach ($statement in $processAst.Statements) {
        $hasReturn = Convert-AstNode -cfg $cfg -node $statement -prevNodeRef ([ref]$currentNode) -endNodeRef $endNodeRef -loopContext $processLoopContext -switchContext $switchContext
        if ($hasReturn) { break }
    }

    Replace-PipelineCurrentInNodes -cfg $cfg -nodes $cfg.Nodes -startIndex $bodyNodeCountBefore -currentVar $currentVar -IncludePSItem

    if ($null -ne $currentNode) {
        $lastType = $currentNode.Type
        if ($lastType -notin @("Break", "Continue", "Return", "Exit", "Throw")) {
            Add-Edge -cfg $cfg -from $currentNode.Id -to $iterNode.Id
        }
    }

    $prevNodeRef.Value = $loopEnd
}

function Test-ForEachObjectCommandAst {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst
    )

    if ($null -eq $CommandAst) { return $false }
    $cmdName = $CommandAst.GetCommandName()
    if ([string]::IsNullOrWhiteSpace($cmdName)) { return $false }
    return ($cmdName -in @('ForEach-Object', 'ForEach', '%'))
}

function Get-ContainingStatementInfo {
    param($Ast)

    $current = $Ast
    while ($null -ne $current) {
        $parent = $current.Parent
        if ($parent -is [System.Management.Automation.Language.NamedBlockAst] -or
            $parent -is [System.Management.Automation.Language.StatementBlockAst]) {
            return [PSCustomObject]@{
                StatementAst = $current
                Statements   = @($parent.Statements)
            }
        }
        $current = $parent
    }

    return $null
}

function Get-UnwrappedScriptBlockBindingAst {
    param($Ast)

    $current = $Ast
    while ($null -ne $current) {
        if ($current -is [System.Management.Automation.Language.ParenExpressionAst]) {
            $pipe = $current.Pipeline
            if ($pipe -and $pipe.PipelineElements.Count -eq 1 -and
                $pipe.PipelineElements[0] -is [System.Management.Automation.Language.CommandExpressionAst]) {
                $current = $pipe.PipelineElements[0].Expression
                continue
            }
        }
        break
    }

    return $current
}

function Resolve-CommandVariableBackedLiteralScriptBlockExpression {
    param(
        [System.Management.Automation.Language.VariableExpressionAst]$VariableAst,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$MaxAliasDepth = 4
    )

    if ($null -eq $VariableAst -or $null -eq $CommandAst -or $null -eq $VariableAst.VariablePath) {
        return $null
    }

    $statementInfo = Get-ContainingStatementInfo -Ast $CommandAst
    if ($null -eq $statementInfo -or -not $statementInfo.Statements -or $statementInfo.Statements.Count -eq 0) {
        return $null
    }

    $currentStatement = $statementInfo.StatementAst
    $statements = @($statementInfo.Statements)
    $currentIndex = [array]::IndexOf($statements, $currentStatement)
    if ($currentIndex -lt 0) {
        return $null
    }

    $visited = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $targetName = [string]$VariableAst.VariablePath.UserPath
    if ([string]::IsNullOrWhiteSpace($targetName)) {
        return $null
    }

    for ($depth = 0; $depth -lt $MaxAliasDepth; $depth++) {
        if (-not $visited.Add($targetName)) {
            return $null
        }

        $matchedAssignment = $null
        for ($i = $currentIndex - 1; $i -ge 0; $i--) {
            $statement = $statements[$i]
            if ($statement -isnot [System.Management.Automation.Language.AssignmentStatementAst]) { continue }
            if ($statement.Left -isnot [System.Management.Automation.Language.VariableExpressionAst]) { continue }

            $leftName = [string]$statement.Left.VariablePath.UserPath
            if ([string]::IsNullOrWhiteSpace($leftName)) { continue }
            if ($leftName -ine $targetName) { continue }

            $matchedAssignment = $statement
            break
        }

        if ($null -eq $matchedAssignment) {
            return $null
        }

        $rightAst = Get-UnwrappedScriptBlockBindingAst -Ast $matchedAssignment.Right
        if ($rightAst -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
            return $rightAst
        }

        if ($rightAst -is [System.Management.Automation.Language.VariableExpressionAst] -and $rightAst.VariablePath) {
            $targetName = [string]$rightAst.VariablePath.UserPath
            if ([string]::IsNullOrWhiteSpace($targetName)) {
                return $null
            }
            continue
        }

        return $null
    }

    return $null
}

function Get-ForEachObjectExpansionInfo {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst
    )

    $result = [ordered]@{
        IsForEachObject = $false
        CanExpand       = $false
        Reason          = $null
        BeginBlockAst   = $null
        ProcessBlockAst = $null
        EndBlockAst     = $null
    }

    if (-not (Test-ForEachObjectCommandAst -CommandAst $CommandAst)) {
        return [PSCustomObject]$result
    }

    $result.IsForEachObject = $true

    function Resolve-ForEachLiteralScriptBlock {
        param(
            $Ast,
            [string]$Role
        )

        if ($null -eq $Ast) {
            return @{ Success = $false; Reason = "$Role block is missing"; BlockAst = $null }
        }

        $resolvedAst = $Ast
        if ($resolvedAst -is [System.Management.Automation.Language.VariableExpressionAst]) {
            $resolvedAst = Resolve-CommandVariableBackedLiteralScriptBlockExpression -VariableAst $resolvedAst -CommandAst $CommandAst
        }

        if ($resolvedAst -isnot [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
            return @{ Success = $false; Reason = "$Role block is not a literal scriptblock"; BlockAst = $null }
        }

        $sbAst = $resolvedAst.ScriptBlock
        if ($null -eq $sbAst) {
            return @{ Success = $false; Reason = "$Role block has no ScriptBlock AST"; BlockAst = $null }
        }

        if ($sbAst.ParamBlock) {
            return @{ Success = $false; Reason = "$Role block with param() is not expanded"; BlockAst = $null }
        }

        if ($null -ne $sbAst.BeginBlock -or $null -ne $sbAst.ProcessBlock) {
            return @{ Success = $false; Reason = "$Role block with nested begin/process is not expanded"; BlockAst = $null }
        }

        return @{ Success = $true; Reason = $null; BlockAst = $sbAst }
    }

    $beginArg = $null
    $processArg = $null
    $endArg = $null
    $positional = @()

    for ($i = 1; $i -lt $CommandAst.CommandElements.Count; $i++) {
        $elem = $CommandAst.CommandElements[$i]

        if ($elem -is [System.Management.Automation.Language.CommandParameterAst]) {
            $pname = $elem.ParameterName
            if ($pname -in @('Begin', 'Process', 'End')) {
                $argAst = $elem.Argument
                if (-not $argAst -and ($i + 1 -lt $CommandAst.CommandElements.Count)) {
                    $i++
                    $argAst = $CommandAst.CommandElements[$i]
                }

                switch ($pname) {
                    'Begin'   { $beginArg = $argAst }
                    'Process' { $processArg = $argAst }
                    'End'     { $endArg = $argAst }
                }
            }
            continue
        }

        $positional += $elem
    }

    if (-not $beginArg -and -not $processArg -and -not $endArg) {
        $blocks = @()
        foreach ($e in $positional) {
            if ($e -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
                $blocks += $e
            } elseif ($e -is [System.Management.Automation.Language.VariableExpressionAst]) {
                $resolvedBlock = Resolve-CommandVariableBackedLiteralScriptBlockExpression -VariableAst $e -CommandAst $CommandAst
                if ($resolvedBlock) {
                    $blocks += $resolvedBlock
                } else {
                    $result.Reason = 'variable-backed scriptblock arguments fall back to runtime execution'
                    return [PSCustomObject]$result
                }
            }
        }

        if ($blocks.Count -eq 1) {
            $processArg = $blocks[0]
        } elseif ($blocks.Count -eq 2) {
            $beginArg = $blocks[0]
            $processArg = $blocks[1]
        } elseif ($blocks.Count -ge 3) {
            $beginArg = $blocks[0]
            $processArg = $blocks[1]
            $endArg = $blocks[2]
        }
    }

    if (-not $processArg) {
        $result.Reason = 'process block is missing'
        return [PSCustomObject]$result
    }

    if ($beginArg) {
        $resolvedBegin = Resolve-ForEachLiteralScriptBlock -Ast $beginArg -Role 'Begin'
        if (-not $resolvedBegin.Success) {
            $result.Reason = $resolvedBegin.Reason
            return [PSCustomObject]$result
        }
        $result.BeginBlockAst = $resolvedBegin.BlockAst
    }

    $resolvedProcess = Resolve-ForEachLiteralScriptBlock -Ast $processArg -Role 'Process'
    if (-not $resolvedProcess.Success) {
        $result.Reason = $resolvedProcess.Reason
        return [PSCustomObject]$result
    }
    $result.ProcessBlockAst = $resolvedProcess.BlockAst

    if ($endArg) {
        $resolvedEnd = Resolve-ForEachLiteralScriptBlock -Ast $endArg -Role 'End'
        if (-not $resolvedEnd.Success) {
            $result.Reason = $resolvedEnd.Reason
            return [PSCustomObject]$result
        }
        $result.EndBlockAst = $resolvedEnd.BlockAst
    }

    $result.CanExpand = $true
    return [PSCustomObject]$result
}

function New-OutputCaptureNode {
    param(
        [hashtable]$cfg,
        [ValidateSet('OutputCaptureStart', 'OutputCaptureEnd')]
        [string]$Type,
        [string]$Text,
        [int]$Line,
        [string]$TargetVarName,
        $OwnerAst = $null
    )

    $node = Add-Node -cfg $cfg -type $Type -text $Text -line $Line -ast $null -ownerAst $OwnerAst
    $node.VarsRead = @()
    $node.VarsWritten = @()

    if ($Type -eq 'OutputCaptureEnd' -and -not [string]::IsNullOrWhiteSpace($TargetVarName)) {
        $targetVarEntry = [PSCustomObject]@{ Name = $TargetVarName; Scope = [VarScope]::Unspecified }
        Add-VarToNode -node $node -varEntry $targetVarEntry -accessType 'Write'
        $node | Add-Member -NotePropertyName 'CaptureTargetVar' -NotePropertyValue $TargetVarName -Force
    }

    return $node
}

function Convert-InlineStatementList {
    param(
        [hashtable]$cfg,
        [object[]]$Statements,
        [ref]$prevNodeRef,
        [pscustomobject]$NormalExitNode,
        $endNodeRef = $null,
        $loopContext = $null,
        [string]$CurrentVar = $null,
        [switch]$ReplacePipelineCurrent
    )

    $bodyStartIndex = $cfg.Nodes.Count
    foreach ($statement in $Statements) {
        $hasTerminator = Convert-AstNode -cfg $cfg -node $statement -prevNodeRef $prevNodeRef -endNodeRef $endNodeRef -loopContext $loopContext -switchContext $null
        if ($hasTerminator) { break }
    }

    if ($ReplacePipelineCurrent -and -not [string]::IsNullOrWhiteSpace($CurrentVar)) {
        Replace-PipelineCurrentInNodes -cfg $cfg -nodes $cfg.Nodes -startIndex $bodyStartIndex -currentVar $CurrentVar -IncludePSItem
    }

    if ($null -ne $prevNodeRef.Value) {
        $lastType = $prevNodeRef.Value.Type
        if ($lastType -notin @('Break', 'Continue', 'Return', 'Exit', 'Throw')) {
            Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $NormalExitNode.Id
        }
    }

    $prevNodeRef.Value = $NormalExitNode
}

function Expand-ForEachObjectPipelineElement {
    param(
        [hashtable]$cfg,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [ref]$prevNodeRef,
        [string]$PipeVarName,
        [pscustomobject]$PipeVarEntry,
        [string]$IncomingEdgeLabel = 'Pipeline'
    )

    $info = Get-ForEachObjectExpansionInfo -CommandAst $CommandAst
    if (-not $info.IsForEachObject -or -not $info.CanExpand) {
        return [PSCustomObject]@{
            Expanded  = $false
            Reason    = $info.Reason
            FinalNode = $prevNodeRef.Value
        }
    }

    $line = $CommandAst.Extent.StartLineNumber
    $guid = [guid]::NewGuid().ToString('N').Substring(0, 12)
    $inputVar = "__pfo_in_$guid"
    $indexVar = "__pfo_${guid}_idx"
    $currentVar = "__pfo_${guid}_cur"
    $outputVar = "__pfo_${guid}_out"

    $inputVarEntry = [PSCustomObject]@{ Name = $inputVar; Scope = [VarScope]::Unspecified }
    $indexVarEntry = [PSCustomObject]@{ Name = $indexVar; Scope = [VarScope]::Unspecified }
    $currentVarEntry = [PSCustomObject]@{ Name = $currentVar; Scope = [VarScope]::Unspecified }
    $outputVarEntry = [PSCustomObject]@{ Name = $outputVar; Scope = [VarScope]::Unspecified }

    $initText = "`$$inputVar = `$$PipeVarName; `$$indexVar = 0; `$$outputVar = @()"
    $initNode = Add-Node -cfg $cfg -type 'ProcessInit' -text $initText -line $line -ast $null -ownerAst $CommandAst
    $initNode.VarsRead = @()
    $initNode.VarsWritten = @()
    Add-VarToNode -node $initNode -varEntry $PipeVarEntry -accessType 'Read'
    Add-VarToNode -node $initNode -varEntry $inputVarEntry -accessType 'Write'
    Add-VarToNode -node $initNode -varEntry $indexVarEntry -accessType 'Write'
    Add-VarToNode -node $initNode -varEntry $outputVarEntry -accessType 'Write'
    if ($null -ne $prevNodeRef.Value) {
        if ([string]::IsNullOrWhiteSpace($IncomingEdgeLabel)) {
            Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $initNode.Id
        } else {
            Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $initNode.Id -label $IncomingEdgeLabel
        }
    }

    $currentNode = $initNode
    $breakLoopEnd = Add-Node -cfg $cfg -type 'LoopEnd' -text 'Break ForEach-Object' -line $CommandAst.Extent.EndLineNumber -ast $null -ownerAst $CommandAst

    $beginStatements = if ($info.BeginBlockAst -and $info.BeginBlockAst.EndBlock) { @($info.BeginBlockAst.EndBlock.Statements) } else { @() }
    if ($beginStatements.Count -gt 0) {
        $beginCaptureStart = New-OutputCaptureNode -cfg $cfg -Type 'OutputCaptureStart' -Text 'Capture Begin Output' -Line $line -TargetVarName $null -OwnerAst $CommandAst
        $beginNormalCaptureEnd = New-OutputCaptureNode -cfg $cfg -Type 'OutputCaptureEnd' -Text 'Append Begin Output' -Line $line -TargetVarName $outputVar -OwnerAst $CommandAst
        $beginBreakCaptureEnd = New-OutputCaptureNode -cfg $cfg -Type 'OutputCaptureEnd' -Text 'Append Begin Output (Break)' -Line $line -TargetVarName $outputVar -OwnerAst $CommandAst
        Add-Edge -cfg $cfg -from $currentNode.Id -to $beginCaptureStart.Id

        $beginPrevNodeRef = [ref]$beginCaptureStart
        $beginLoopContext = [PSCustomObject]@{
            LoopEnd      = $beginBreakCaptureEnd
            LoopContinue = $beginNormalCaptureEnd
        }
        Convert-InlineStatementList -cfg $cfg -Statements $beginStatements -prevNodeRef $beginPrevNodeRef -NormalExitNode $beginNormalCaptureEnd -endNodeRef $beginNormalCaptureEnd -loopContext $beginLoopContext
        Add-Edge -cfg $cfg -from $beginBreakCaptureEnd.Id -to $breakLoopEnd.Id
        $currentNode = $beginNormalCaptureEnd
    }

    $conditionNode = Add-Node -cfg $cfg -type 'ProcessCondition' -text "[bool](`$$indexVar -lt `$$inputVar.Count)" -line $line -ast $null -ownerAst $CommandAst
    $conditionNode.VarsRead = @($indexVarEntry, $inputVarEntry)
    $conditionNode.VarsWritten = @()
    Add-Edge -cfg $cfg -from $currentNode.Id -to $conditionNode.Id

    $normalLoopEnd = Add-Node -cfg $cfg -type 'ProcessEnd' -text 'End ForEach-Object Process' -line $CommandAst.Extent.EndLineNumber -ast $null -ownerAst $CommandAst
    Add-Edge -cfg $cfg -from $conditionNode.Id -to $normalLoopEnd.Id -label 'No more items'

    $bindNode = Add-Node -cfg $cfg -type 'ProcessBind' -text "`$$currentVar = `$$inputVar[`$$indexVar]" -line $line -ast $null -ownerAst $CommandAst
    $bindNode.VarsRead = @($inputVarEntry, $indexVarEntry)
    $bindNode.VarsWritten = @($currentVarEntry)
    Add-Edge -cfg $cfg -from $conditionNode.Id -to $bindNode.Id -label 'Has next'

    $processCaptureStart = New-OutputCaptureNode -cfg $cfg -Type 'OutputCaptureStart' -Text 'Capture Process Output' -Line $line -TargetVarName $null -OwnerAst $CommandAst
    $processNormalCaptureEnd = New-OutputCaptureNode -cfg $cfg -Type 'OutputCaptureEnd' -Text 'Append Process Output' -Line $line -TargetVarName $outputVar -OwnerAst $CommandAst
    $processBreakCaptureEnd = New-OutputCaptureNode -cfg $cfg -Type 'OutputCaptureEnd' -Text 'Append Process Output (Break)' -Line $line -TargetVarName $outputVar -OwnerAst $CommandAst
    $processContinueCaptureEnd = New-OutputCaptureNode -cfg $cfg -Type 'OutputCaptureEnd' -Text 'Append Process Output (Continue)' -Line $line -TargetVarName $outputVar -OwnerAst $CommandAst
    Add-Edge -cfg $cfg -from $bindNode.Id -to $processCaptureStart.Id

    $processStatements = if ($info.ProcessBlockAst -and $info.ProcessBlockAst.EndBlock) { @($info.ProcessBlockAst.EndBlock.Statements) } else { @() }
    $processPrevNodeRef = [ref]$processCaptureStart
    $processLoopContext = [PSCustomObject]@{
        LoopEnd      = $processBreakCaptureEnd
        LoopContinue = $processContinueCaptureEnd
    }
    Convert-InlineStatementList -cfg $cfg -Statements $processStatements -prevNodeRef $processPrevNodeRef -NormalExitNode $processNormalCaptureEnd -endNodeRef $processNormalCaptureEnd -loopContext $processLoopContext -CurrentVar $currentVar -ReplacePipelineCurrent

    $iterNode = Add-Node -cfg $cfg -type 'ProcessIter' -text "`$$indexVar++" -line $line -ast $null -ownerAst $CommandAst
    $iterNode.VarsRead = @($indexVarEntry)
    $iterNode.VarsWritten = @($indexVarEntry)
    Add-Edge -cfg $cfg -from $processNormalCaptureEnd.Id -to $iterNode.Id
    Add-Edge -cfg $cfg -from $processContinueCaptureEnd.Id -to $iterNode.Id
    Add-Edge -cfg $cfg -from $processBreakCaptureEnd.Id -to $breakLoopEnd.Id
    Add-Edge -cfg $cfg -from $iterNode.Id -to $conditionNode.Id

    $currentNode = $normalLoopEnd
    $endStatements = if ($info.EndBlockAst -and $info.EndBlockAst.EndBlock) { @($info.EndBlockAst.EndBlock.Statements) } else { @() }
    if ($endStatements.Count -gt 0) {
        $endCaptureStart = New-OutputCaptureNode -cfg $cfg -Type 'OutputCaptureStart' -Text 'Capture End Output' -Line $line -TargetVarName $null -OwnerAst $CommandAst
        $endNormalCaptureEnd = New-OutputCaptureNode -cfg $cfg -Type 'OutputCaptureEnd' -Text 'Append End Output' -Line $line -TargetVarName $outputVar -OwnerAst $CommandAst
        Add-Edge -cfg $cfg -from $normalLoopEnd.Id -to $endCaptureStart.Id

        $endPrevNodeRef = [ref]$endCaptureStart
        $endLoopContext = [PSCustomObject]@{
            LoopEnd      = $endNormalCaptureEnd
            LoopContinue = $endNormalCaptureEnd
        }
        Convert-InlineStatementList -cfg $cfg -Statements $endStatements -prevNodeRef $endPrevNodeRef -NormalExitNode $endNormalCaptureEnd -endNodeRef $endNormalCaptureEnd -loopContext $endLoopContext
        $currentNode = $endNormalCaptureEnd
    }

    $commitNode = Add-Node -cfg $cfg -type 'AssignmentStatementAst' -text "`$$PipeVarName = `$$outputVar" -line $line -ast $null -ownerAst $CommandAst
    $commitNode.VarsRead = @($outputVarEntry)
    $commitNode.VarsWritten = @($PipeVarEntry)
    Add-Edge -cfg $cfg -from $currentNode.Id -to $commitNode.Id
    Add-Edge -cfg $cfg -from $breakLoopEnd.Id -to $commitNode.Id

    $prevNodeRef.Value = $commitNode
    return [PSCustomObject]@{
        Expanded  = $true
        Reason    = $null
        FinalNode = $commitNode
    }
}
function Mark-PipelineCmdletNode {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Node,
        $ElementAst
    )

    if (-not $Node) { return }
    if ($Node.Type -ne "PipelineElement") { return }
    if ($null -eq $ElementAst) { return }

    if ($ElementAst -is [System.Management.Automation.Language.CommandAst]) {
        $cmdName = $ElementAst.GetCommandName()
        if ([string]::IsNullOrWhiteSpace($cmdName)) { return }

        if ($cmdName -in @('ForEach-Object', 'ForEach', '%')) {
            $Node | Add-Member -NotePropertyName "PipeCmdlet" -NotePropertyValue "ForEachObject" -Force
            $Node | Add-Member -NotePropertyName "PipeCmdletName" -NotePropertyValue $cmdName -Force
            return
        }

        if ($cmdName -in @('Where-Object', 'Where', '?')) {
            $Node | Add-Member -NotePropertyName "PipeCmdlet" -NotePropertyValue "WhereObject" -Force
            $Node | Add-Member -NotePropertyName "PipeCmdletName" -NotePropertyValue $cmdName -Force
            return
        }

        if ($cmdName -in @('Select-Object', 'Select')) {
            $Node | Add-Member -NotePropertyName "PipeCmdlet" -NotePropertyValue "SelectObject" -Force
            $Node | Add-Member -NotePropertyName "PipeCmdletName" -NotePropertyValue $cmdName -Force
            return
        }
    }
}

function Convert-ScriptBlockBody {
    param(
        [hashtable]$cfg,
        [System.Management.Automation.Language.ScriptBlockAst]$scriptBlockAst,
        [ref]$prevNodeRef,
        [ref]$endNodeRef,
        [string]$paramNodeType = "BlockParams",  # ScriptParams | FuncParams | BlockParams
        $loopContext = $null,
        $switchContext = $null,
        [bool]$IsTopLevelScript = $false
    )

    if ($null -eq $scriptBlockAst) {
        return $false
    }

    $hasTerminator = $false

    if ($null -ne $scriptBlockAst.ParamBlock) {
        $paramBlock = $scriptBlockAst.ParamBlock

        $paramExpansion = Expand-NestedPipelines -cfg $cfg -ast $paramBlock -prevNodeRef $prevNodeRef

        $rawParamText = $paramBlock.Extent.Text
        if ($null -ne $paramExpansion) {
            $rawParamText = $paramExpansion.ModifiedText
        }
        $singleLineParam = ($rawParamText -split "`r?`n") -join ' '
        $singleLineParam = ($singleLineParam -replace '\s+', ' ').Trim()

        $paramNode = Add-Node -cfg $cfg -type $paramNodeType -text $singleLineParam -line $paramBlock.Extent.StartLineNumber -ast $paramBlock

        if ($null -ne $paramExpansion) {
            foreach ($pipeVarEntry in $paramExpansion.PipeVarEntries) {
                Add-VarToNode -node $paramNode -varEntry $pipeVarEntry -accessType "Read"
            }
            Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $paramNode.Id -label "Pipeline"
        } else {
            if ($null -ne $prevNodeRef.Value) {
                Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $paramNode.Id
            }
        }
        $prevNodeRef.Value = $paramNode
    }

    if ($null -ne $scriptBlockAst.BeginBlock -and $scriptBlockAst.BeginBlock.Statements.Count -gt 0) {
        foreach ($statement in $scriptBlockAst.BeginBlock.Statements) {
            $stmtHasTerminator = Convert-AstNode -cfg $cfg -node $statement -prevNodeRef $prevNodeRef -endNodeRef $endNodeRef -loopContext $loopContext -switchContext $switchContext
            if ($stmtHasTerminator) {
                $hasTerminator = $true
                break
            }
        }
    }

    if ($null -ne $scriptBlockAst.ProcessBlock -and $scriptBlockAst.ProcessBlock.Statements.Count -gt 0) {
        $useProcessInputVar = -not $IsTopLevelScript
        Convert-ProcessBlock -cfg $cfg -scriptBlockAst $scriptBlockAst -prevNodeRef $prevNodeRef -endNodeRef $endNodeRef -UseProcessInputVar:$useProcessInputVar -switchContext $switchContext
    }

    if ($null -ne $scriptBlockAst.EndBlock -and $scriptBlockAst.EndBlock.Statements.Count -gt 0) {
        foreach ($statement in $scriptBlockAst.EndBlock.Statements) {
            $stmtHasTerminator = Convert-AstNode -cfg $cfg -node $statement -prevNodeRef $prevNodeRef -endNodeRef $endNodeRef -loopContext $loopContext -switchContext $switchContext
            if ($stmtHasTerminator) {
                $hasTerminator = $true
                break
            }
        }
    }

    return $hasTerminator
}

function Convert-ScriptBlockDefinition {
    param(
        [hashtable]$cfg,
        [System.Management.Automation.Language.ScriptBlockExpressionAst]$scriptBlockExprAst,
        [string]$blockName = $null
    )

    if ($null -eq $scriptBlockExprAst) {
        return $null
    }

    $scriptBlock = $scriptBlockExprAst.ScriptBlock

    if (-not $blockName) {
        $guid = [guid]::NewGuid().ToString("N").Substring(0, 8)
        $blockName = "__block_$guid"
    }

    $blockStart = Add-Node -cfg $cfg -type "BlockStart" -text "ScriptBlock $blockName" -line $scriptBlockExprAst.Extent.StartLineNumber -ast $null
    $blockStart | Add-Member -NotePropertyName "ScriptBlockText" -NotePropertyValue $scriptBlockExprAst.Extent.Text -Force
    $blockStart | Add-Member -NotePropertyName "TextStartOffset" -NotePropertyValue $scriptBlockExprAst.Extent.StartOffset -Force
    $blockStart | Add-Member -NotePropertyName "TextEndOffset" -NotePropertyValue $scriptBlockExprAst.Extent.EndOffset -Force
    $hasProcessBlock = ($null -ne $scriptBlock.ProcessBlock -and $scriptBlock.ProcessBlock.Statements.Count -gt 0)
    $blockStart | Add-Member -NotePropertyName "HasProcessBlock" -NotePropertyValue $hasProcessBlock -Force
    $blockStart | Add-Member -NotePropertyName "ProcessInputVar" -NotePropertyValue "__proc_input" -Force
    $blockEnd = Add-Node -cfg $cfg -type "BlockEnd" -text "End ScriptBlock $blockName" -line $scriptBlockExprAst.Extent.EndLineNumber -ast $null

    $prevNode = $blockStart
    $prev = [ref]$prevNode
    $endRef = [ref]$blockEnd

    $null = Convert-ScriptBlockBody -cfg $cfg -scriptBlockAst $scriptBlock -prevNodeRef $prev -endNodeRef $endRef -paramNodeType "BlockParams"

    if ($null -ne $prev.Value -and $prev.Value.Id -ne $blockEnd.Id) {
        $lastType = $prev.Value.Type
        if ($lastType -notin @("Return", "Exit", "Throw", "Break", "Continue", "End")) {
            Add-Edge -cfg $cfg -from $prev.Value.Id -to $blockEnd.Id
        }
    }

    return @{
        BlockName = $blockName
        BlockStart = $blockStart
        BlockEnd = $blockEnd
    }
}

function Expand-NestedScriptBlocks {
    param(
        [Parameter(Mandatory = $true)]
        $cfg,
        [Parameter(Mandatory = $true)]
        $ast,
        [Parameter(Mandatory = $true)]
        [ref]$prevNodeRef,
        $endNodeRef = $null,
        $loopContext = $null,
        $switchContext = $null
    )

    $nestedScriptBlocks = Get-AllNestedScriptBlocks -ast $ast
    if ($nestedScriptBlocks.Count -eq 0) {
        return $null
    }

    $invokeOnlyBlocks = @()
    $immediateBlocks = @()
    $cmdletInvokeBlocks = @()
    $deferredBlocks = @()
    $pipelineValueBlocks = @()

    foreach ($sb in $nestedScriptBlocks) {
        $execType = Get-ScriptBlockExecutionType -scriptBlockExprAst $sb
        switch ($execType) {
            "InvokeOnly" { $invokeOnlyBlocks += $sb }
            "Immediate" { $immediateBlocks += $sb }
            "CmdletInvoke" { $cmdletInvokeBlocks += $sb }
            "PipelineValue" { $pipelineValueBlocks += $sb }
            default { $deferredBlocks += $sb }
        }
    }

    $pipelineValueReplacements = @()
    foreach ($sb in $pipelineValueBlocks) {
        if ($cfg.ProcessedScriptBlocks.ContainsKey($sb)) {
            $varName = $cfg.ProcessedScriptBlocks[$sb]
            $blockVarEntry = [PSCustomObject]@{ Name = $varName; Scope = [VarScope]::Unspecified }
            $pipelineValueReplacements += @{
                Original = $sb.Extent.Text
                Replacement = "`$$varName"
                VarEntry = $blockVarEntry
            }
            continue
        }

        $guid = [guid]::NewGuid().ToString("N").Substring(0, 8)
        $varName = "_block_$guid"
        $blockVarEntry = [PSCustomObject]@{ Name = $varName; Scope = [VarScope]::Unspecified }

        $cfg.ProcessedScriptBlocks[$sb] = $varName

        $null = Convert-ScriptBlockDefinition -cfg $cfg -scriptBlockExprAst $sb -blockName $varName

        $pipelineValueReplacements += @{
            Original = $sb.Extent.Text
            Replacement = "`$$varName"
            VarEntry = $blockVarEntry
        }
    }

    $deferredReplacements = @()
    $deferredVarEntries = @()
    foreach ($sb in $deferredBlocks) {
        if ($cfg.ProcessedScriptBlocks.ContainsKey($sb)) {
            $varName = $cfg.ProcessedScriptBlocks[$sb]
            $parent = $sb.Parent

            $isDirectAssignment = $false
            if ($parent -is [System.Management.Automation.Language.CommandExpressionAst] -and
                $parent.Expression -eq $sb) {
                $grandParent = $parent.Parent
                if ($grandParent -is [System.Management.Automation.Language.PipelineAst] -and
                    $grandParent.PipelineElements.Count -eq 1) {
                    $greatGrandParent = $grandParent.Parent
                    if ($greatGrandParent -is [System.Management.Automation.Language.AssignmentStatementAst]) {
                        $isDirectAssignment = $true
                    }
                }
                if ($grandParent -is [System.Management.Automation.Language.AssignmentStatementAst]) {
                    $isDirectAssignment = $true
                }
            }

            if ($isDirectAssignment) {
                continue
            }

            $blockVarEntry = [PSCustomObject]@{ Name = $varName; Scope = [VarScope]::Unspecified }
            $deferredReplacements += @{
                Original = $sb.Extent.Text
                Replacement = "`$$varName"
                VarEntry = $blockVarEntry
            }
            $deferredVarEntries += $blockVarEntry
            continue
        }

        $varName = $null
        $parent = $sb.Parent
        if ($parent -is [System.Management.Automation.Language.AssignmentStatementAst]) {
            $left = $parent.Left
            if ($left -is [System.Management.Automation.Language.VariableExpressionAst]) {
                $varName = $left.VariablePath.UserPath
            }
        }

        if ($null -eq $varName) {
            $guid = [guid]::NewGuid().ToString("N").Substring(0, 8)
            $varName = "_block_$guid"
        }

        $blockVarEntry = [PSCustomObject]@{ Name = $varName; Scope = [VarScope]::Unspecified }

        $cfg.ProcessedScriptBlocks[$sb] = $varName

        $null = Convert-ScriptBlockDefinition -cfg $cfg -scriptBlockExprAst $sb -blockName $varName

        $deferredReplacements += @{
            Original = $sb.Extent.Text
            Replacement = "`$$varName"
            VarEntry = $blockVarEntry
        }
        $deferredVarEntries += $blockVarEntry
    }

    if ($deferredReplacements.Count -gt 0) {
        $isStandaloneDeferred = $false
        if ($deferredBlocks.Count -eq 1) {
            $sb = $deferredBlocks[0]
            $parent = $sb.Parent
            if ($parent -is [System.Management.Automation.Language.CommandExpressionAst]) {
                if ($parent.Expression -eq $sb) {
                    $grandParent = $parent.Parent
                    if ($grandParent -is [System.Management.Automation.Language.PipelineAst] -and
                        $grandParent.PipelineElements.Count -eq 1 -and
                        $grandParent.PipelineElements[0] -eq $parent -and
                        $grandParent -eq $ast) {
                        $isStandaloneDeferred = $true
                    }
                }
            }
        }

        if ($isStandaloneDeferred) {
            $r = $deferredReplacements[0]
            $pipeNode = Add-Node -cfg $cfg -type "PipelineElement" -text $r.Replacement -line $ast.Extent.StartLineNumber -ast $ast
            Add-VarToNode -node $pipeNode -varEntry $r.VarEntry -accessType "Read"
            if ($null -ne $prevNodeRef.Value) {
                Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $pipeNode.Id
            }
            $prevNodeRef.Value = $pipeNode

            return @{
                ModifiedText = $null
                ScriptBlockVarEntries = @()
                InvokeOnlyExpanded = $true
            }
        }

        $modifiedText = $ast.Extent.Text
        foreach ($r in $deferredReplacements) {
            $modifiedText = $modifiedText.Replace($r.Original, $r.Replacement)
        }

        return @{
            ModifiedText = $modifiedText
            ScriptBlockVarEntries = $deferredVarEntries
            InvokeOnlyExpanded = $false
        }
    }

    if ($cmdletInvokeBlocks.Count -gt 0) {
        foreach ($sb in $cmdletInvokeBlocks) {
            if ($cfg.ProcessedScriptBlocks.ContainsKey($sb)) {
                continue
            }

            $guid = [guid]::NewGuid().ToString("N").Substring(0, 8)
            $blockName = "_block_$guid"
            $blockVarEntry = [PSCustomObject]@{ Name = $blockName; Scope = [VarScope]::Unspecified }

            $cfg.ProcessedScriptBlocks[$sb] = $blockName

            $null = Convert-ScriptBlockDefinition -cfg $cfg -scriptBlockExprAst $sb -blockName $blockName

            $parent = $sb.Parent
            $cmdAst = $null
            if ($parent -is [System.Management.Automation.Language.CommandAst]) {
                $cmdAst = $parent
            } elseif ($parent -is [System.Management.Automation.Language.CommandParameterAst]) {
                $cmdAst = $parent.Parent
            }

            if ($null -ne $cmdAst) {
                $cmdText = $cmdAst.Extent.Text
                $sbText = $sb.Extent.Text
                $modifiedCmdText = $cmdText.Replace($sbText, "`$$blockName")

                $pipeNode = Add-Node -cfg $cfg -type "PipelineElement" -text $modifiedCmdText -line $cmdAst.Extent.StartLineNumber -ast $cmdAst
                Mark-PipelineCmdletNode -Node $pipeNode -ElementAst $cmdAst
                Add-VarToNode -node $pipeNode -varEntry $blockVarEntry -accessType "Read"
                if ($null -ne $prevNodeRef.Value) {
                    Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $pipeNode.Id
                }

                $prevNodeRef.Value = $pipeNode
            }
        }

        return @{
            ModifiedText = $null
            ScriptBlockVarEntries = @()
            InvokeOnlyExpanded = $true
        }
    }

    if ($invokeOnlyBlocks.Count -gt 0) {
        $invokeOnlyReplacements = @()
        $invokeOnlyVarEntries = @()

        foreach ($sb in $invokeOnlyBlocks) {
            if ($cfg.ProcessedScriptBlocks.ContainsKey($sb)) {
                $blockName = $cfg.ProcessedScriptBlocks[$sb]
                $blockVarEntry = [PSCustomObject]@{ Name = $blockName; Scope = [VarScope]::Unspecified }

                $parent = $sb.Parent
                $invokeOp = if ($parent -is [System.Management.Automation.Language.CommandAst]) {
                    if ($parent.InvocationOperator -eq [System.Management.Automation.Language.TokenKind]::Dot) { "." } else { "&" }
                } else { "&" }

                $invokeOnlyReplacements += @{
                    Original = $parent.Extent.Text
                    Replacement = "$invokeOp `$$blockName"
                    VarEntry = $blockVarEntry
                }
                $invokeOnlyVarEntries += $blockVarEntry
                continue
            }

            $guid = [guid]::NewGuid().ToString("N").Substring(0, 8)
            $blockName = "_block_$guid"
            $blockVarEntry = [PSCustomObject]@{ Name = $blockName; Scope = [VarScope]::Unspecified }

            $cfg.ProcessedScriptBlocks[$sb] = $blockName

            $null = Convert-ScriptBlockDefinition -cfg $cfg -scriptBlockExprAst $sb -blockName $blockName

            $parent = $sb.Parent
            $invokeOp = if ($parent -is [System.Management.Automation.Language.CommandAst]) {
                if ($parent.InvocationOperator -eq [System.Management.Automation.Language.TokenKind]::Dot) { "." } else { "&" }
            } else { "&" }

            $invokeOnlyReplacements += @{
                Original = $parent.Extent.Text
                Replacement = "$invokeOp `$$blockName"
                VarEntry = $blockVarEntry
            }
            $invokeOnlyVarEntries += $blockVarEntry
        }

        $isStandaloneInvoke = $false
        if ($invokeOnlyBlocks.Count -eq 1) {
            $sb = $invokeOnlyBlocks[0]
            $parent = $sb.Parent
            if ($parent -is [System.Management.Automation.Language.CommandAst] -and $parent -eq $ast) {
                $isStandaloneInvoke = $true
            }
            if ($ast -is [System.Management.Automation.Language.PipelineAst] -and
                $ast.PipelineElements.Count -eq 1 -and
                $ast.PipelineElements[0] -eq $parent) {
                $isStandaloneInvoke = $true
            }
        }

        if ($isStandaloneInvoke) {
            $r = $invokeOnlyReplacements[0]
            $pipeNode = Add-Node -cfg $cfg -type "PipelineElement" -text $r.Replacement -line $ast.Extent.StartLineNumber -ast $ast
            Add-VarToNode -node $pipeNode -varEntry $r.VarEntry -accessType "Read"
            if ($null -ne $prevNodeRef.Value) {
                Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $pipeNode.Id
            }
            $prevNodeRef.Value = $pipeNode

            return @{
                ModifiedText = $null
                ScriptBlockVarEntries = @()
                InvokeOnlyExpanded = $true
            }
        }

        $modifiedText = $ast.Extent.Text
        foreach ($r in $invokeOnlyReplacements) {
            $modifiedText = $modifiedText.Replace($r.Original, $r.Replacement)
        }

        return @{
            ModifiedText = $modifiedText
            ScriptBlockVarEntries = $invokeOnlyVarEntries
            InvokeOnlyExpanded = $false
        }
    }

    if ($immediateBlocks.Count -eq 0 -and $pipelineValueBlocks.Count -eq 0) {
        return $null
    }

    $sortedBlocks = $immediateBlocks | Sort-Object { $_.Extent.StartOffset } -Descending

    $replacements = @()
    $scriptBlockVarEntries = @()

    foreach ($sb in $sortedBlocks) {
        if ($cfg.ProcessedScriptBlocks.ContainsKey($sb)) {
            $blockName = $cfg.ProcessedScriptBlocks[$sb]
            $sbVarEntry = [PSCustomObject]@{ Name = $blockName; Scope = [VarScope]::Unspecified }

            $replacements += @{
                Original = $sb.Extent.Text
                Replacement = "`$$blockName"
            }
            $scriptBlockVarEntries += $sbVarEntry
            continue
        }

        $guid = [guid]::NewGuid().ToString("N").Substring(0, 8)
        $blockName = "_block_$guid"
        $sbVarEntry = [PSCustomObject]@{ Name = $blockName; Scope = [VarScope]::Unspecified }

        $cfg.ProcessedScriptBlocks[$sb] = $blockName

        $null = Convert-ScriptBlockDefinition -cfg $cfg -scriptBlockExprAst $sb -blockName $blockName

        $originalText = $sb.Extent.Text
        $replacementText = "`$$blockName"

        $replacements += @{
            Original = $originalText
            Replacement = $replacementText
        }
        $scriptBlockVarEntries += $sbVarEntry
    }

    $modifiedText = $ast.Extent.Text
    foreach ($r in $replacements) {
        $modifiedText = $modifiedText.Replace($r.Original, $r.Replacement)
    }
    foreach ($r in $pipelineValueReplacements) {
        $modifiedText = $modifiedText.Replace($r.Original, $r.Replacement)
        $scriptBlockVarEntries += $r.VarEntry
    }

    return @{
        ModifiedText = $modifiedText
        ScriptBlockVarEntries = $scriptBlockVarEntries
        InvokeOnlyExpanded = $false
    }
}

function Expand-NestedPipelines {
    param(
        [Parameter(Mandatory = $true)]
        $cfg,
        [Parameter(Mandatory = $true)]
        $ast,
        [Parameter(Mandatory = $true)]
        [ref]$prevNodeRef
    )

    $nestedPipelines = @(Get-AllNestedPipelines -ast $ast)
    if ($nestedPipelines.Count -eq 0) {
        return $null
    }

    $pipelinesWithDepth = $nestedPipelines | ForEach-Object {
        $depth = 0
        $ancestor = $_.Parent
        while ($null -ne $ancestor -and $ancestor -ne $ast) {
            if ($ancestor -is [System.Management.Automation.Language.PipelineAst] -and $ancestor.PipelineElements.Count -gt 1) {
                $depth++
            }
            $ancestor = $ancestor.Parent
        }
        [PSCustomObject]@{
            Pipeline = $_
            Depth = $depth
        }
    }

    $sortedPipelines = $pipelinesWithDepth | Sort-Object @{Expression={$_.Depth}; Descending=$true}, @{Expression={$_.Pipeline.Extent.StartOffset}; Descending=$true}

    $pipelineReplacements = @{}
    $pipeVarEntries = @()

    foreach ($pipeInfo in $sortedPipelines) {
        $pipeline = $pipeInfo.Pipeline
        $guid = [guid]::NewGuid().ToString("N").Substring(0, 8)
        $pipeVar = "_pipe_$guid"
        $pipeVarEntry = [PSCustomObject]@{ Name = $pipeVar; Scope = [VarScope]::Unspecified }

        $elements = $pipeline.PipelineElements
        $lastIndex = $elements.Count - 1

        for ($i = 0; $i -lt $elements.Count - 1; $i++) {
            $element = $elements[$i]
            $elementText = $element.Extent.Text
            $elementVarEntries = @()

            foreach ($innerPipeline in $pipelineReplacements.Keys) {
                if ($elementText.Contains($pipelineReplacements[$innerPipeline].Original)) {
                    $elementText = $elementText.Replace(
                        $pipelineReplacements[$innerPipeline].Original,
                        $pipelineReplacements[$innerPipeline].Replacement
                    )
                    $elementVarEntries += $pipelineReplacements[$innerPipeline].PipeVarEntry
                }
            }

            $expandedForEach = $false
            if ($i -gt 0 -and $element -is [System.Management.Automation.Language.CommandAst]) {
                $foreachExpansion = Expand-ForEachObjectPipelineElement -cfg $cfg -CommandAst $element -prevNodeRef $prevNodeRef -PipeVarName $pipeVar -PipeVarEntry $pipeVarEntry -IncomingEdgeLabel 'Pipeline'
                if ($foreachExpansion.Expanded) {
                    $expandedForEach = $true
                }
            }

            if ($expandedForEach) {
                continue
            }

            $sbExpansion = Expand-NestedScriptBlocks -cfg $cfg -ast $element -prevNodeRef $prevNodeRef
            if ($null -ne $sbExpansion -and -not $sbExpansion.InvokeOnlyExpanded -and $null -ne $sbExpansion.ModifiedText) {
                $nestedSBs = Get-AllNestedScriptBlocks -ast $element
                foreach ($sb in $nestedSBs) {
                    if ($cfg.ProcessedScriptBlocks.ContainsKey($sb)) {
                        $varName = $cfg.ProcessedScriptBlocks[$sb]
                        $elementText = $elementText.Replace($sb.Extent.Text, "`$$varName")
                        $elementVarEntries += [PSCustomObject]@{ Name = $varName; Scope = [VarScope]::Unspecified }
                    }
                }
            }

            if ($i -eq 0) {
                $nodeText = $elementText
            } else {
                $nodeText = "`$$pipeVar | " + $elementText
            }

            $pipeNode = Add-Node -cfg $cfg -type "PipelineElement" -text $nodeText -line $element.Extent.StartLineNumber -ast $element
            Mark-PipelineCmdletNode -Node $pipeNode -ElementAst $element

            foreach ($varEntry in $elementVarEntries) {
                Add-VarToNode -node $pipeNode -varEntry $varEntry -accessType "Read"
            }

            if ($i -eq 0) {
                Add-VarToNode -node $pipeNode -varEntry $pipeVarEntry -accessType "Write"
            } else {
                Add-VarToNode -node $pipeNode -varEntry $pipeVarEntry -accessType "Both"
            }

            if ($null -ne $prevNodeRef.Value) {
                if ($i -gt 0) {
                    Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $pipeNode.Id -label "Pipeline"
                } else {
                    Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $pipeNode.Id
                }
            }
            $prevNodeRef.Value = $pipeNode
        }

        $lastElement = $elements[$lastIndex]
        $lastElementText = $lastElement.Extent.Text
        $lastElementVarEntries = @()

        foreach ($innerPipeline in $pipelineReplacements.Keys) {
            if ($lastElementText.Contains($pipelineReplacements[$innerPipeline].Original)) {
                $lastElementText = $lastElementText.Replace(
                    $pipelineReplacements[$innerPipeline].Original,
                    $pipelineReplacements[$innerPipeline].Replacement
                )
                $lastElementVarEntries += $pipelineReplacements[$innerPipeline].PipeVarEntry
            }
        }

        $expandedLastForEach = $false
        if ($lastIndex -gt 0 -and $lastElement -is [System.Management.Automation.Language.CommandAst]) {
            $foreachExpansion = Expand-ForEachObjectPipelineElement -cfg $cfg -CommandAst $lastElement -prevNodeRef $prevNodeRef -PipeVarName $pipeVar -PipeVarEntry $pipeVarEntry -IncomingEdgeLabel 'Pipeline'
            if ($foreachExpansion.Expanded) {
                $expandedLastForEach = $true
            }
        }

        if (-not $expandedLastForEach) {
            $sbExpansion = Expand-NestedScriptBlocks -cfg $cfg -ast $lastElement -prevNodeRef $prevNodeRef
            if ($null -ne $sbExpansion -and -not $sbExpansion.InvokeOnlyExpanded -and $null -ne $sbExpansion.ModifiedText) {
                $nestedSBs = Get-AllNestedScriptBlocks -ast $lastElement
                foreach ($sb in $nestedSBs) {
                    if ($cfg.ProcessedScriptBlocks.ContainsKey($sb)) {
                        $varName = $cfg.ProcessedScriptBlocks[$sb]
                        $lastElementText = $lastElementText.Replace($sb.Extent.Text, "`$$varName")
                        $lastElementVarEntries += [PSCustomObject]@{ Name = $varName; Scope = [VarScope]::Unspecified }
                    }
                }
            }
        }

        $originalText = $pipeline.Extent.Text
        $nestedSBsInPipeline = Get-AllNestedScriptBlocks -ast $pipeline
        foreach ($sb in $nestedSBsInPipeline) {
            if ($cfg.ProcessedScriptBlocks.ContainsKey($sb)) {
                $varName = $cfg.ProcessedScriptBlocks[$sb]
                $originalText = $originalText.Replace($sb.Extent.Text, "`$$varName")
            }
        }
        foreach ($innerPipeline in $pipelineReplacements.Keys) {
            $innerR = $pipelineReplacements[$innerPipeline]
            $originalText = $originalText.Replace($innerR.Original, $innerR.Replacement)
        }

        $replacementText = if ($expandedLastForEach) { "`$$pipeVar" } else { "`$$pipeVar | " + $lastElementText }

        $pipelineReplacements[$pipeline] = @{
            Original = $originalText
            Replacement = $replacementText
            PipeVarEntry = $pipeVarEntry
            LastElementVarEntries = $lastElementVarEntries
        }
        $pipeVarEntries += $pipeVarEntry
    }

    $modifiedText = $ast.Extent.Text

    $allNestedSBs = Get-AllNestedScriptBlocks -ast $ast
    foreach ($sb in $allNestedSBs) {
        if ($cfg.ProcessedScriptBlocks.ContainsKey($sb)) {
            $varName = $cfg.ProcessedScriptBlocks[$sb]
            $modifiedText = $modifiedText.Replace($sb.Extent.Text, "`$$varName")
        }
    }

    foreach ($pipeInfo in $sortedPipelines) {
        $pipeline = $pipeInfo.Pipeline
        $r = $pipelineReplacements[$pipeline]
        $modifiedText = $modifiedText.Replace($r.Original, $r.Replacement)
    }

    $allScriptBlockVarEntries = @()
    foreach ($pipeline in $pipelineReplacements.Keys) {
        $allScriptBlockVarEntries += $pipelineReplacements[$pipeline].LastElementVarEntries
    }
    foreach ($sb in $allNestedSBs) {
        if ($cfg.ProcessedScriptBlocks.ContainsKey($sb)) {
            $varName = $cfg.ProcessedScriptBlocks[$sb]
            $allScriptBlockVarEntries += [PSCustomObject]@{ Name = $varName; Scope = [VarScope]::Unspecified }
        }
    }

    return @{
        ModifiedText = $modifiedText
        PipeVarEntries = $pipeVarEntries
        ScriptBlockVarEntries = $allScriptBlockVarEntries
    }
}
function Convert-IfAstNode {
    param(
        [hashtable]$cfg,
        [System.Management.Automation.Language.IfStatementAst]$ifAst,
        [ref]$prevNodeRef,
        $endNodeRef = $null,
        $loopContext = $null
    )
    if ($null -eq $ifAst -or $null -eq $prevNodeRef) {
        Write-Warning "Invalid input: ifAst or prevNodeRef is null"
        return
    }

    $ifNode = Add-Node -cfg $cfg -type "If Condition" -text "If Condition" -line $ifAst.Extent.StartLineNumber -ast $null
    Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $ifNode.Id
    $prevNodeRef.Value = $ifNode

    $branchEndNodes = @()

    $previousCondNode = $null

    foreach ($clause in $ifAst.Clauses) {
        $conditionAst = $clause.Item1
        $expansion = Expand-NestedPipelines -cfg $cfg -ast $conditionAst -prevNodeRef $prevNodeRef

        if ($null -ne $expansion) {
            $condNode = Add-Node -cfg $cfg -type "Condition" -text "[bool]($($expansion.ModifiedText))" -line $conditionAst.Extent.StartLineNumber -ast $conditionAst
            foreach ($pipeVarEntry in $expansion.PipeVarEntries) {
                Add-VarToNode -node $condNode -varEntry $pipeVarEntry -accessType "Read"
            }
            if ($null -ne $prevNodeRef.Value) {
                Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $condNode.Id -label "Pipeline"
            }
        } else {
            $condNode = Add-Node -cfg $cfg -type "Condition" -text "[bool]($($conditionAst.Extent.Text))" -line $conditionAst.Extent.StartLineNumber -ast $conditionAst

            if ($null -eq $previousCondNode) {
                Add-Edge -cfg $cfg -from $ifNode.Id -to $condNode.Id -label "Condition"
            }
            else {
                Add-Edge -cfg $cfg -from $previousCondNode.Id -to $condNode.Id -label "False"
            }
        }

        $prevNodeRef.Value = $condNode

        $branchHasTerminator = $false
        $isFirstStatement = $true
        foreach ($statement in $clause.Item2.Statements) {
            $hasTerminator = Convert-AstNode -cfg $cfg -node $statement -prevNodeRef $prevNodeRef -endNodeRef $endNodeRef -loopContext $loopContext -switchContext $null

            if ($isFirstStatement) {
                $isFirstStatement = $false
                $edgeFromCond = $cfg.Edges | Where-Object { $_.From -eq $condNode.Id -and $null -eq $_.Label }
                if ($edgeFromCond) {
                    $edgeFromCond.Label = "True"
                }
            }

            if ($hasTerminator) {
                $branchHasTerminator = $true
                break
            }
        }

        $previousCondNode = $condNode

        if (-not $branchHasTerminator -and $null -ne $prevNodeRef.Value) {
            $lastNodeType = $prevNodeRef.Value.Type
            if ($lastNodeType -notin @("Break","Continue","Return","Exit","Throw")) {
                $branchEndNodes += $prevNodeRef.Value
            }
        }
    }

    if ($null -ne $ifAst.ElseClause) {
        $elseNode = Add-Node -cfg $cfg -type "Else" -text "Else" -line $ifAst.ElseClause.Extent.StartLineNumber -ast $null

        if ($null -ne $previousCondNode) {
            Add-Edge -cfg $cfg -from $previousCondNode.Id -to $elseNode.Id -label "False"
        }
        else {
            Add-Edge -cfg $cfg -from $ifNode.Id -to $elseNode.Id -label "Else"
        }

        $prevNodeRef.Value = $elseNode

        $elseHasTerminator = $false
        foreach ($statement in $ifAst.ElseClause.Statements) {
            $hasTerminator = Convert-AstNode -cfg $cfg -node $statement -prevNodeRef $prevNodeRef -endNodeRef $endNodeRef -loopContext $loopContext -switchContext $null
            if ($hasTerminator) {
                $elseHasTerminator = $true
                break
            }
        }

        if (-not $elseHasTerminator -and $null -ne $prevNodeRef.Value) {
            $lastNodeType = $prevNodeRef.Value.Type
            if ($lastNodeType -notin @("Break","Continue","Return","Exit","Throw")) {
                $branchEndNodes += $prevNodeRef.Value
            }
        }
    }
    else {
        $implicitElseNode = Add-Node -cfg $cfg -type "Else" -text "Implicit Else" -line $ifAst.Extent.EndLineNumber -ast $null

        if ($null -ne $previousCondNode) {
            Add-Edge -cfg $cfg -from $previousCondNode.Id -to $implicitElseNode.Id -label "False"
        }
        else {
            Add-Edge -cfg $cfg -from $ifNode.Id -to $implicitElseNode.Id -label "Else"
        }

        $branchEndNodes += $implicitElseNode
        $prevNodeRef.Value = $implicitElseNode
    }

    if ($branchEndNodes.Count -eq 0) {
        if ($null -ne $prevNodeRef.Value) {
            $lastNodeType = $prevNodeRef.Value.Type
            if ($lastNodeType -in @("Return", "Exit") -and $null -ne $endNodeRef) {
                $endNode = if ($endNodeRef -is [ref]) { $endNodeRef.Value } else { $endNodeRef }
                if ($null -ne $endNode) {
                    $prevNodeRef.Value = $endNode
                    return $true
                }
            }
            return $true
        }
    }

    $mergeNode = Add-Node -cfg $cfg -type "Merge" -text "If-End" -line $ifAst.Extent.EndLineNumber -ast $null

    foreach ($endNode in $branchEndNodes) {
        Add-Edge -cfg $cfg -from $endNode.Id -to $mergeNode.Id
    }

    $prevNodeRef.Value = $mergeNode
    return $false
}

function Replace-PipelineCurrentVariable {
    param(
        [string]$text,
        [string]$replacementVar,
        [switch]$IncludePSItem
    )

    if ($null -eq $text) { return $text }

    $result = $text -replace '\$_(?![a-zA-Z0-9_])', ('$$' + $replacementVar)
    if ($IncludePSItem) {
        $result = $result -replace '\$PSItem(?![a-zA-Z0-9_])', ('$$' + $replacementVar)
    }

    return $result
}

function Replace-PipelineCurrentInNodes {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$cfg,
        [array]$nodes,
        [int]$startIndex,
        [string]$currentVar,
        [switch]$IncludePSItem
    )

    $currentVarEntry = [PSCustomObject]@{ Name = $currentVar; Scope = [VarScope]::Unspecified }
    $pipelineVarNames = @("_")
    if ($IncludePSItem) {
        $pipelineVarNames += @("PSItem")
    }

    $nodeById = @{}
    foreach ($n in $nodes) {
        if ($null -ne $n -and $null -ne $n.Id) {
            $nodeById[[int]$n.Id] = $n
        }
    }

    $adj = @{}
    if ($cfg.Edges) {
        foreach ($e in $cfg.Edges) {
            if ($null -eq $e) { continue }
            $from = [int]$e.From
            if (-not $adj.ContainsKey($from)) {
                $adj[$from] = [System.Collections.Generic.List[int]]::new()
            }
            $adj[$from].Add([int]$e.To)
        }
    }

    # nodeId -> $true
    $skipNodeIds = @{}

    function Add-SubgraphSkipIds {
        param([int]$StartId)

        $q = [System.Collections.Generic.Queue[int]]::new()
        $visited = @{}
        $q.Enqueue($StartId)

        while ($q.Count -gt 0) {
            $id = $q.Dequeue()
            if ($visited.ContainsKey($id)) { continue }
            $visited[$id] = $true
            $skipNodeIds[$id] = $true

            $n = $nodeById[$id]
            if ($n -and $n.Type -in @("FuncEnd", "BlockEnd", "End", "MainEnd")) {
                continue
            }

            if ($adj.ContainsKey($id)) {
                foreach ($to in $adj[$id]) {
                    if (-not $visited.ContainsKey($to)) {
                        $q.Enqueue($to)
                    }
                }
            }
        }
    }

    for ($i = $startIndex; $i -lt $nodes.Count; $i++) {
        $node = $nodes[$i]

        if ($node.Type -in @("FuncStart", "BlockStart")) {
            Add-SubgraphSkipIds -StartId ([int]$node.Id)
        }

        if ($skipNodeIds.ContainsKey([int]$node.Id)) {
            continue
        }

        $newText = Replace-PipelineCurrentVariable -text $node.Text -replacementVar $currentVar -IncludePSItem:$IncludePSItem
        if ($newText -ne $node.Text) {
            $node.Text = $newText
        }

        $hasPipelineRead = $false
        foreach ($name in $pipelineVarNames) {
            if ($node.VarsRead | Where-Object { $_.Name -ieq $name }) {
                $hasPipelineRead = $true
                break
            }
        }
        if ($hasPipelineRead) {
            $node.VarsRead = @($node.VarsRead | Where-Object {
                $keep = $true
                foreach ($name in $pipelineVarNames) {
                    if ($_.Name -ieq $name) {
                        $keep = $false
                        break
                    }
                }
                $keep
            })
            Add-VarToNode -node $node -varEntry $currentVarEntry -accessType "Read"
        }

        $hasPipelineWrite = $false
        foreach ($name in $pipelineVarNames) {
            if ($node.VarsWritten | Where-Object { $_.Name -ieq $name }) {
                $hasPipelineWrite = $true
                break
            }
        }
        if ($hasPipelineWrite) {
            $node.VarsWritten = @($node.VarsWritten | Where-Object {
                $keep = $true
                foreach ($name in $pipelineVarNames) {
                    if ($_.Name -ieq $name) {
                        $keep = $false
                        break
                    }
                }
                $keep
            })
            Add-VarToNode -node $node -varEntry $currentVarEntry -accessType "Write"
        }
    }
}

function Replace-UnderscoreVariable {
    param([string]$text, [string]$replacementVar)
    return Replace-PipelineCurrentVariable -text $text -replacementVar $replacementVar -IncludePSItem
}

function Replace-UnderscoreInNodes {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$cfg,
        [array]$nodes,
        [int]$startIndex,
        [string]$currentVar
    )
    Replace-PipelineCurrentInNodes -cfg $cfg -nodes $nodes -startIndex $startIndex -currentVar $currentVar -IncludePSItem
}

function Build-SwitchCaseCondition {
    param($clauseConditionAst, [string]$currentVar, [string[]]$switchFlags)

    if ($null -eq $clauseConditionAst) { return "`$true" }

    $isCaseSensitive = $switchFlags -contains "-CaseSensitive"
    $isWildcard = $switchFlags -contains "-Wildcard"
    $isRegex = $switchFlags -contains "-Regex"

    $operator = if ($isWildcard) {
        if ($isCaseSensitive) { "-clike" } else { "-like" }
    } elseif ($isRegex) {
        if ($isCaseSensitive) { "-cmatch" } else { "-match" }
    } else {
        if ($isCaseSensitive) { "-ceq" } else { "-eq" }
    }

    if ($clauseConditionAst -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
        $bodyStatements = $clauseConditionAst.ScriptBlock.EndBlock.Statements
        $bodyText = ($bodyStatements | ForEach-Object { $_.Extent.Text }) -join "; "
        $replaced = Replace-UnderscoreVariable -text $bodyText -replacementVar $currentVar
        return "[bool]($replaced)"
    } else {
        return "[bool](`$$currentVar $operator $($clauseConditionAst.Extent.Text))"
    }
}

function Convert-SwitchAstNode {
    param(
        [hashtable]$cfg,
        [System.Management.Automation.Language.SwitchStatementAst]$switchAst,
        [ref]$prevNodeRef,
        $endNodeRef = $null,
        $loopContext = $null,
        $switchContext = $null
    )
    if ($null -eq $switchAst -or $null -eq $prevNodeRef) {
        Write-Warning "Invalid input: switchAst or prevNodeRef is null"
        return
    }

    # ============================================================
    # ============================================================

    $guid = [guid]::NewGuid().ToString("N").Substring(0, 12)
    $collectionVar = "__sw_$guid"
    $indexVar = "__sw_${guid}_idx"
    $currentVar = "__sw_${guid}_current"

    $collectionVarEntry = [PSCustomObject]@{ Name = $collectionVar; Scope = [VarScope]::Unspecified }
    $indexVarEntry = [PSCustomObject]@{ Name = $indexVar; Scope = [VarScope]::Unspecified }
    $currentVarEntry = [PSCustomObject]@{ Name = $currentVar; Scope = [VarScope]::Unspecified }
    $underscoreVarEntry = [PSCustomObject]@{ Name = "_"; Scope = [VarScope]::Unspecified }

    $switchFlags = @()
    if ($switchAst.Flags -band [System.Management.Automation.Language.SwitchFlags]::Wildcard) { $switchFlags += "-Wildcard" }
    if ($switchAst.Flags -band [System.Management.Automation.Language.SwitchFlags]::Regex) { $switchFlags += "-Regex" }
    if ($switchAst.Flags -band [System.Management.Automation.Language.SwitchFlags]::CaseSensitive) { $switchFlags += "-CaseSensitive" }
    if ($switchAst.Flags -band [System.Management.Automation.Language.SwitchFlags]::Exact) { $switchFlags += "-Exact" }
    if ($switchAst.Flags -band [System.Management.Automation.Language.SwitchFlags]::File) { $switchFlags += "-File" }
    if ($switchAst.Flags -band [System.Management.Automation.Language.SwitchFlags]::Parallel) { $switchFlags += "-Parallel" }
    $flagsText = if ($switchFlags.Count -gt 0) { " " + ($switchFlags -join " ") } else { "" }

    $switchConditionText = if ($null -ne $switchAst.Condition) { $switchAst.Condition.Extent.Text } else { "Switch Condition" }

    $switchStart = Add-Node -cfg $cfg -type "SwitchStart" -text "switch$flagsText ($switchConditionText)" -line $switchAst.Extent.StartLineNumber -ast $null
    Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $switchStart.Id
    $prevNodeRef.Value = $switchStart

    $conditionExpansion = $null
    if ($null -ne $switchAst.Condition) {
        $conditionExpansion = Expand-NestedPipelines -cfg $cfg -ast $switchAst.Condition -prevNodeRef $prevNodeRef
    }

    if ($null -ne $conditionExpansion) {
        $initText = "`$$collectionVar = @(" + $conditionExpansion.ModifiedText + "); `$$indexVar = 0"
        $initNode = Add-Node -cfg $cfg -type "SwitchInit" -text $initText -line $switchAst.Condition.Extent.StartLineNumber -ast $switchAst.Condition
        foreach ($pipeVarEntry in $conditionExpansion.PipeVarEntries) {
            Add-VarToNode -node $initNode -varEntry $pipeVarEntry -accessType "Read"
        }
        if ($null -ne $prevNodeRef.Value) {
            Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $initNode.Id -label "Pipeline"
        }
    } else {
        $initText = "`$$collectionVar = @($switchConditionText); `$$indexVar = 0"
        $initNode = Add-Node -cfg $cfg -type "SwitchInit" -text $initText -line $switchAst.Condition.Extent.StartLineNumber -ast $switchAst.Condition
        Add-Edge -cfg $cfg -from $switchStart.Id -to $initNode.Id
    }
    Add-VarToNode -node $initNode -varEntry $collectionVarEntry -accessType "Write"
    Add-VarToNode -node $initNode -varEntry $indexVarEntry -accessType "Write"

    $condText = "[bool](`$$indexVar -lt `$$collectionVar.Count)"
    $conditionNode = Add-Node -cfg $cfg -type "SwitchCondition" -text $condText -line $switchAst.Extent.StartLineNumber -ast $null -ownerAst $switchAst
    $conditionNode.VarsRead = @($indexVarEntry, $collectionVarEntry)
    $conditionNode.VarsWritten = @()
    Add-Edge -cfg $cfg -from $initNode.Id -to $conditionNode.Id

    $switchEnd = Add-Node -cfg $cfg -type "SwitchEnd" -text "End Switch" -line $switchAst.Extent.EndLineNumber -ast $null
    Add-Edge -cfg $cfg -from $conditionNode.Id -to $switchEnd.Id -label "False"

    # VarsRead: $__sw_xxx, $__sw_xxx_idx
    # VarsWritten: $__sw_xxx_current
    $bindText = "`$$currentVar = `$$collectionVar[`$$indexVar]"
    $bindNode = Add-Node -cfg $cfg -type "SwitchBind" -text $bindText -line $switchAst.Extent.StartLineNumber -ast $null -ownerAst $switchAst
    $bindNode.VarsRead = @($collectionVarEntry, $indexVarEntry)
    $bindNode.VarsWritten = @($currentVarEntry)
    Add-Edge -cfg $cfg -from $conditionNode.Id -to $bindNode.Id -label "True"

    # VarsRead: $__sw_xxx_idx
    # VarsWritten: $__sw_xxx_idx
    $iterText = "`$$indexVar++"
    $iterNode = Add-Node -cfg $cfg -type "SwitchIter" -text $iterText -line $switchAst.Extent.StartLineNumber -ast $null -ownerAst $switchAst
    $iterNode.VarsRead = @($indexVarEntry)
    $iterNode.VarsWritten = @($indexVarEntry)
    Add-Edge -cfg $cfg -from $iterNode.Id -to $conditionNode.Id

    $currentSwitchContext = [PSCustomObject]@{
        SwitchMerge = $switchEnd
        SwitchNode = $iterNode
    }

    $previousCondNode = $null
    $nodesToNextCase = @()
    $nodesToIter = @()

    $caseIndex = 0
    $totalCases = $switchAst.Clauses.Count

    foreach ($clause in $switchAst.Clauses) {
        $caseIndex++
        $isLastCase = ($caseIndex -eq $totalCases) -and ($null -eq $switchAst.Default)

        $caseLineNumber = if ($null -ne $clause.Item1) { $clause.Item1.Extent.StartLineNumber } else { $switchAst.Extent.StartLineNumber }
        $caseCondText = Build-SwitchCaseCondition -clauseConditionAst $clause.Item1 -currentVar $currentVar -switchFlags $switchFlags
        $caseCondNode = Add-Node -cfg $cfg -type "CaseCondition" -text $caseCondText -line $caseLineNumber -ast $clause.Item1
        $caseCondNode.VarsRead = @($caseCondNode.VarsRead | Where-Object { $_.Name -ne "_" })
        Add-VarToNode -node $caseCondNode -varEntry $currentVarEntry -accessType "Read"

        if ($null -eq $previousCondNode) {
            Add-Edge -cfg $cfg -from $bindNode.Id -to $caseCondNode.Id
        }
        else {
            Add-Edge -cfg $cfg -from $previousCondNode.Id -to $caseCondNode.Id -label "False"
        }

        foreach ($node in $nodesToNextCase) {
            Add-Edge -cfg $cfg -from $node.Id -to $caseCondNode.Id
        }
        $nodesToNextCase = @()

        $prevNodeRef.Value = $caseCondNode
        $branchHasTerminator = $false

        $branchPrev = $caseCondNode
        $firstBodyNodeId = $null
        $bodyNodeCountBefore = $cfg.Nodes.Count

        foreach ($statement in $clause.Item2.Statements) {
            $hasTerminator = Convert-AstNode -cfg $cfg -node $statement -prevNodeRef ([ref]$branchPrev) -endNodeRef $endNodeRef -loopContext $loopContext -switchContext $currentSwitchContext

            if ($null -eq $firstBodyNodeId -and $branchPrev.Id -ne $caseCondNode.Id) {
                $firstBodyNodeId = $branchPrev.Id
                foreach ($edge in $cfg.Edges) {
                    if ($edge.From -eq $caseCondNode.Id -and $edge.To -eq $firstBodyNodeId) {
                        $edge.Label = "True"
                        break
                    }
                }
            }

            if ($hasTerminator) {
                $branchHasTerminator = $true
                break
            }
        }

        Replace-UnderscoreInNodes -cfg $cfg -nodes $cfg.Nodes -startIndex $bodyNodeCountBefore -currentVar $currentVar


        $previousCondNode = $caseCondNode

        if (-not $branchHasTerminator -and $null -ne $branchPrev) {
            $lastNodeType = $branchPrev.Type
            if ($lastNodeType -notin @("Break", "Continue", "Return", "Exit", "Throw")) {
                if ($isLastCase) {
                    $nodesToIter += $branchPrev
                }
                else {
                    $nodesToNextCase += $branchPrev
                }
            }
        }
    }

    if ($null -ne $switchAst.Default) {
        $defaultNode = Add-Node -cfg $cfg -type "Default" -text "Default" -line $switchAst.Default.Extent.StartLineNumber -ast $null

        if ($null -ne $previousCondNode) {
            Add-Edge -cfg $cfg -from $previousCondNode.Id -to $defaultNode.Id -label "False"
        }

        foreach ($node in $nodesToNextCase) {
            $nodesToIter += $node
        }
        $nodesToNextCase = @()

        $branchPrev = $defaultNode
        $defaultHasTerminator = $false
        $defaultNodeCountBefore = $cfg.Nodes.Count

        foreach ($statement in $switchAst.Default.Statements) {
            $hasTerminator = Convert-AstNode -cfg $cfg -node $statement -prevNodeRef ([ref]$branchPrev) -endNodeRef $endNodeRef -loopContext $loopContext -switchContext $currentSwitchContext
            if ($hasTerminator) {
                $defaultHasTerminator = $true
                break
            }
        }

        Replace-UnderscoreInNodes -cfg $cfg -nodes $cfg.Nodes -startIndex $defaultNodeCountBefore -currentVar $currentVar

        if (-not $defaultHasTerminator -and $null -ne $branchPrev) {
            $lastNodeType = $branchPrev.Type
            if ($lastNodeType -notin @("Break", "Continue", "Return", "Exit", "Throw")) {
                $nodesToIter += $branchPrev
            }
        }
    }
    else {
        if ($null -ne $previousCondNode) {
            Add-Edge -cfg $cfg -from $previousCondNode.Id -to $iterNode.Id -label "False"
        }

        foreach ($node in $nodesToNextCase) {
            $nodesToIter += $node
        }
    }

    foreach ($node in $nodesToIter) {
        Add-Edge -cfg $cfg -from $node.Id -to $iterNode.Id
    }

    $prevNodeRef.Value = $switchEnd
    return $false
}

function Convert-FunctionDefinitionAst {
    param(
        [hashtable]$cfg,
        [System.Management.Automation.Language.FunctionDefinitionAst]$funcAst
    )
    if ($null -eq $funcAst) {
        return
    }

    $funcName = $funcAst.Name
    $funcStart = Add-Node -cfg $cfg -type "FuncStart" -text "function $funcName" -line $funcAst.Extent.StartLineNumber -ast $null
    $hasProcessBlock = ($null -ne $funcAst.Body -and $null -ne $funcAst.Body.ProcessBlock -and $funcAst.Body.ProcessBlock.Statements.Count -gt 0)
    $funcStart | Add-Member -NotePropertyName "HasProcessBlock" -NotePropertyValue $hasProcessBlock -Force
    $funcStart | Add-Member -NotePropertyName "ProcessInputVar" -NotePropertyValue "__proc_input" -Force
    $funcEnd   = Add-Node -cfg $cfg -type "FuncEnd"   -text "End function $funcName"        -line $funcAst.Extent.EndLineNumber   -ast $null

    $prevNode = $funcStart
    $prev = [ref]$prevNode
    $endRef = [ref]$funcEnd

    if ($null -ne $funcAst.Parameters -and @($funcAst.Parameters).Count -gt 0 -and
        ($null -eq $funcAst.Body -or $null -eq $funcAst.Body.ParamBlock)) {
        $paramText = 'param(' + ((@($funcAst.Parameters) | ForEach-Object {
                    if ($_.Extent) { [string]$_.Extent.Text } else { '$null' }
                }) -join ', ') + ')'
        $paramNode = Add-Node -cfg $cfg -type "FuncParams" -text $paramText -line $funcAst.Extent.StartLineNumber -ast $null
        $paramNode | Add-Member -NotePropertyName "ParameterAsts" -NotePropertyValue @($funcAst.Parameters) -Force
        Add-Edge -cfg $cfg -from $funcStart.Id -to $paramNode.Id
        $prev.Value = $paramNode
    }

    if ($null -ne $funcAst.Body) {
        $null = Convert-ScriptBlockBody -cfg $cfg -scriptBlockAst $funcAst.Body -prevNodeRef $prev -endNodeRef $endRef -paramNodeType "FuncParams"
    }

    if ($null -ne $prev.Value -and $prev.Value.Id -ne $funcEnd.Id) {
        $lastType = $prev.Value.Type
        if ($lastType -notin @("Return", "Exit", "Throw", "Break", "Continue", "End")) {
            Add-Edge -cfg $cfg -from $prev.Value.Id -to $funcEnd.Id
        }
    }
}

function Convert-TryAstNode {
    param(
        [hashtable]$cfg,
        [System.Management.Automation.Language.TryStatementAst]$tryAst,
        [ref]$prevNodeRef,
        $endNodeRef = $null,
        $loopContext = $null,
        $switchContext = $null
    )
    if ($null -eq $tryAst -or $null -eq $prevNodeRef) {
        Write-Warning "Invalid input: tryAst or prevNodeRef is null"
        return $false
    }

    $tryNode = Add-Node -cfg $cfg -type "Try" -text "Try" -line $tryAst.Extent.StartLineNumber -ast $null
    Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $tryNode.Id
    $prevNodeRef.Value = $tryNode

    $tryEndNode = $null

    $finallyNode = $null
    if ($null -ne $tryAst.Finally) {
        $finallyNode = Add-Node -cfg $cfg -type "Finally" -text "Finally" -line $tryAst.Finally.Extent.StartLineNumber -ast $null
    }

    $firstCatchNode = $null
    $catchNodes = @()

    $underscoreVarEntry = [PSCustomObject]@{ Name = "_"; Scope = [VarScope]::Unspecified }

    foreach ($catchClause in $tryAst.CatchClauses) {
        $catchTypes = if ($catchClause.CatchTypes.Count -gt 0) {
            ($catchClause.CatchTypes | ForEach-Object { $_.TypeName.Name }) -join ", "
        } else {
            "All"
        }

        $catchNode = Add-Node -cfg $cfg -type "Catch" -text "Catch [$catchTypes]" -line $catchClause.Extent.StartLineNumber -ast $catchClause
        $catchNode.VarsRead = @()
        $catchNode.VarsWritten = @($underscoreVarEntry)

        $catchNodes += @{
            Node = $catchNode
            Clause = $catchClause
        }

        if ($null -eq $firstCatchNode) {
            $firstCatchNode = $catchNode
        }
    }

    $branchEndNodes = @()

    $nodeCountBefore = $cfg.Nodes.Count

    $tryHasTerminator = $false
    foreach ($statement in $tryAst.Body.Statements) {
        $hasTerminator = Convert-AstNode -cfg $cfg -node $statement -prevNodeRef $prevNodeRef -endNodeRef $endNodeRef -loopContext $loopContext -switchContext $switchContext

        if ($hasTerminator) {
            $tryHasTerminator = $true
            break
        }
    }

    $tryAllNodes = @()
    $tryExitNodes = @()
    $tryReturnNodes = @()
    for ($i = $nodeCountBefore; $i -lt $cfg.Nodes.Count; $i++) {
        $node = $cfg.Nodes[$i]

        $isInNestedTry = $false
        $ancestorSource = if ($null -ne $node.OwnerAst) { $node.OwnerAst } else { $node.Ast }
        if ($null -ne $ancestorSource) {
            $ancestor = $ancestorSource.Parent
            while ($null -ne $ancestor) {
                if ($ancestor -is [System.Management.Automation.Language.TryStatementAst]) {
                    if ($ancestor -ne $tryAst) {
                        $isInNestedTry = $true
                    }
                    break
                }
                $ancestor = $ancestor.Parent
            }
        }

        if ($isInNestedTry) {
            continue
        }

        if ($node.Type -eq "Exit") {
            $tryExitNodes += $node
        }
        elseif ($node.Type -eq "Return") {
            $tryReturnNodes += $node
        }

        if ($node.Type -notin @("Return", "Exit", "Break", "Continue", "Try", "Catch", "Finally", "Merge", "Start", "End")) {
            $tryAllNodes += $node
        }
    }

    if ($null -ne $firstCatchNode) {
        foreach ($stmtNode in $tryAllNodes) {
            Add-Edge -cfg $cfg -from $stmtNode.Id -to $firstCatchNode.Id -label "Exception"
        }
    }
    elseif ($null -ne $finallyNode) {
        foreach ($stmtNode in $tryAllNodes) {
            Add-Edge -cfg $cfg -from $stmtNode.Id -to $finallyNode.Id -label "Exception"
        }
    }

    if ($null -ne $finallyNode) {
        if ($tryExitNodes.Count -gt 0) {
            foreach ($exitNode in $tryExitNodes) {
                Add-Edge -cfg $cfg -from $exitNode.Id -to $finallyNode.Id -label "Exit"
            }
        }
        if ($tryReturnNodes.Count -gt 0) {
            foreach ($retNode in $tryReturnNodes) {
                Add-Edge -cfg $cfg -from $retNode.Id -to $finallyNode.Id -label "Return"
            }
        }
    }

    if (-not $tryHasTerminator -and $null -ne $prevNodeRef.Value) {
        $lastNodeType = $prevNodeRef.Value.Type
        if ($lastNodeType -ne "Return" -and $lastNodeType -ne "Exit" -and $lastNodeType -ne "Break" -and $lastNodeType -ne "Continue" -and $lastNodeType -ne "Throw") {
            $branchEndNodes += $prevNodeRef.Value
        }
    }

    for ($i = 0; $i -lt $catchNodes.Count; $i++) {
        $catchInfo = $catchNodes[$i]
        $catchNode = $catchInfo.Node
        $catchClause = $catchInfo.Clause

        if ($i -gt 0) {
            $prevCatchNode = $catchNodes[$i - 1].Node
            Add-Edge -cfg $cfg -from $prevCatchNode.Id -to $catchNode.Id -label "Not Match"
        }

        $prevNodeRef.Value = $catchNode
        $catchHasTerminator = $false
        foreach ($statement in $catchClause.Body.Statements) {
            $hasTerminator = Convert-AstNode -cfg $cfg -node $statement -prevNodeRef $prevNodeRef -endNodeRef $endNodeRef -loopContext $loopContext -switchContext $switchContext
            if ($hasTerminator) {
                $catchHasTerminator = $true
                break
            }
        }

        if (-not $catchHasTerminator -and $null -ne $prevNodeRef.Value) {
            $lastNodeType = $prevNodeRef.Value.Type
            if ($lastNodeType -ne "Return" -and $lastNodeType -ne "Exit" -and $lastNodeType -ne "Break" -and $lastNodeType -ne "Continue" -and $lastNodeType -ne "Throw") {
                $branchEndNodes += $prevNodeRef.Value
            }
        }
    }

    if ($catchNodes.Count -gt 0) {
        $lastCatchNode = $catchNodes[-1].Node
        if ($null -ne $endNodeRef) {
            $endNode = if ($endNodeRef -is [ref]) { $endNodeRef.Value } else { $endNodeRef }
            if ($null -ne $endNode) {
                Add-Edge -cfg $cfg -from $lastCatchNode.Id -to $endNode.Id -label "Uncaught Exception"
            }
        }
    }

    if ($catchNodes.Count -gt 0 -and $null -ne $firstCatchNode -and $null -ne $endNodeRef) {
        $endNode = if ($endNodeRef -is [ref]) { $endNodeRef.Value } else { $endNodeRef }
        if ($null -ne $endNode) {
            for ($i = 0; $i -lt $cfg.Edges.Count; $i++) {
                $edge = $cfg.Edges[$i]
                if ($edge.Label -ne "Uncaught Exception" -or $edge.To -ne $endNode.Id) {
                    continue
                }

                $fromNode = $cfg.Nodes | Where-Object { $_.Id -eq $edge.From }
                $fromNodeAncestorSource = if ($null -ne $fromNode.OwnerAst) { $fromNode.OwnerAst } else { $fromNode.Ast }
                if ($null -eq $fromNode -or $null -eq $fromNodeAncestorSource) {
                    continue
                }

                if ($fromNode.Type -eq "Catch" -and $null -ne $fromNode.Ast) {
                    $catchAst = $fromNode.Ast
                    if ($catchAst -is [System.Management.Automation.Language.CatchClauseAst]) {
                        $parentTryOfCatch = $catchAst.Parent
                        if ($parentTryOfCatch -is [System.Management.Automation.Language.TryStatementAst] -and
                            $parentTryOfCatch -eq $tryAst) {
                            continue
                        }
                    }
                }

                $hasThisTryAncestor = $false
                $ancestor = $fromNodeAncestorSource
                while ($null -ne $ancestor) {
                    if ($ancestor -is [System.Management.Automation.Language.TryStatementAst]) {
                        if ($ancestor -eq $tryAst) { $hasThisTryAncestor = $true }
                    }
                    $ancestor = $ancestor.Parent
                }

                if (-not $hasThisTryAncestor) {
                    continue
                }

                $belongsToThisTryCatch = $false
                $ancestor = $fromNodeAncestorSource.Parent
                while ($null -ne $ancestor) {
                    if ($ancestor -is [System.Management.Automation.Language.CatchClauseAst]) {
                        $parentTry = $ancestor.Parent
                        if ($parentTry -is [System.Management.Automation.Language.TryStatementAst] -and
                            $parentTry -eq $tryAst) {
                            $belongsToThisTryCatch = $true
                        }
                        break
                    }
                    $ancestor = $ancestor.Parent
                }

                if ($belongsToThisTryCatch) {
                    continue
                }

                $edge.To = $firstCatchNode.Id
            }
        }
    }

    if ($null -ne $finallyNode -and $null -ne $endNodeRef) {
        $endNode = if ($endNodeRef -is [ref]) { $endNodeRef.Value } else { $endNodeRef }
        if ($null -ne $endNode) {
            for ($i = 0; $i -lt $cfg.Edges.Count; $i++) {
                $edge = $cfg.Edges[$i]
                if ($edge.Label -ne "Uncaught Exception" -or $edge.To -ne $endNode.Id) {
                    continue
                }

                $fromNode = $cfg.Nodes | Where-Object { $_.Id -eq $edge.From }
                $fromNodeAncestorSource = if ($null -ne $fromNode.OwnerAst) { $fromNode.OwnerAst } else { $fromNode.Ast }
                if ($null -eq $fromNode -or $null -eq $fromNodeAncestorSource) {
                    continue
                }

                $hasThisTryAncestor = $false
                $ancestor = $fromNodeAncestorSource
                while ($null -ne $ancestor) {
                    if ($ancestor -is [System.Management.Automation.Language.TryStatementAst]) {
                        if ($ancestor -eq $tryAst) { $hasThisTryAncestor = $true }
                    }
                    $ancestor = $ancestor.Parent
                }
                if (-not $hasThisTryAncestor) {
                    continue
                }

                $inThisFinally = $false
                $ancestor = $fromNodeAncestorSource.Parent
                while ($null -ne $ancestor) {
                    if ($ancestor -is [System.Management.Automation.Language.StatementBlockAst] -and
                        $tryAst.Finally -eq $ancestor) {
                        $inThisFinally = $true
                        break
                    }
                    $ancestor = $ancestor.Parent
                }
                if ($inThisFinally) {
                    continue
                }

                $edge.To = $finallyNode.Id
            }

        }
    }

    if ($null -ne $finallyNode) {
        foreach ($endNode in $branchEndNodes) {
            Add-Edge -cfg $cfg -from $endNode.Id -to $finallyNode.Id
        }
        $branchEndNodes = @()

        $prevNodeRef.Value = $finallyNode
        $finallyHasTerminator = $false
        foreach ($statement in $tryAst.Finally.Statements) {
            $hasTerminator = Convert-AstNode -cfg $cfg -node $statement -prevNodeRef $prevNodeRef -endNodeRef $endNodeRef -loopContext $loopContext -switchContext $switchContext
            if ($hasTerminator) {
                $finallyHasTerminator = $true
                break
            }
        }

        if (-not $finallyHasTerminator -and $null -ne $prevNodeRef.Value) {
            $lastNodeType = $prevNodeRef.Value.Type

            if ($null -ne $endNodeRef) {
                $endNode = if ($endNodeRef -is [ref]) { $endNodeRef.Value } else { $endNodeRef }
                if ($null -ne $endNode) {
                    Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $endNode.Id -label "Uncaught Exception"
                }
            }

            #    try { ... exit } finally { ... }  ==>  Exit -> Finally -> ScriptEnd
            if ($tryExitNodes.Count -gt 0 -and $script:__CFG_ScriptEndNode) {
                Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $script:__CFG_ScriptEndNode.Id -label "Exit"
                $prevNodeRef.Value = $script:__CFG_ScriptEndNode
            }
            #    try { ... return } finally { ... }  ==>  Return -> Finally -> End/FuncEnd
            elseif ($tryReturnNodes.Count -gt 0 -and $null -ne $endNodeRef) {
                $endNode = if ($endNodeRef -is [ref]) { $endNodeRef.Value } else { $endNodeRef }
                if ($null -ne $endNode) {
                    Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $endNode.Id -label "Return"
                    $prevNodeRef.Value = $endNode
                }
            }
            else {
                if ($lastNodeType -ne "Return" -and $lastNodeType -ne "Exit" -and $lastNodeType -ne "Break" -and $lastNodeType -ne "Continue" -and $lastNodeType -ne "Throw") {
                    $branchEndNodes += $prevNodeRef.Value
                }
            }
        }
    }

    if ($branchEndNodes.Count -gt 0) {
        if ($null -eq $tryEndNode) {
            $tryEndNode = Add-Node -cfg $cfg -type "Merge" -text "Try-End" -line $tryAst.Extent.EndLineNumber -ast $null
        }
        foreach ($endNode in $branchEndNodes) {
            Add-Edge -cfg $cfg -from $endNode.Id -to $tryEndNode.Id
        }

        $prevNodeRef.Value = $tryEndNode

        return $false
    }

    return $true
}

function Get-LoopHeaderText {
    param($loopAst)

    switch ($loopAst) {
        {$_ -is [System.Management.Automation.Language.ForStatementAst]} {
            $init = if ($null -ne $loopAst.Initializer) { $loopAst.Initializer.Extent.Text } else { "" }
            $cond = if ($null -ne $loopAst.Condition) { $loopAst.Condition.Extent.Text } else { "" }
            $iter = if ($null -ne $loopAst.Iterator) { $loopAst.Iterator.Extent.Text } else { "" }
            "for ($init; $cond; $iter)"
        }
        {$_ -is [System.Management.Automation.Language.ForEachStatementAst]} {
            $var = $loopAst.Variable.Extent.Text
            $col = if ($null -ne $loopAst.Condition) { $loopAst.Condition.Extent.Text } else { "null" }
            "foreach ($var in $col)"
        }
        default {
            $loopAst.GetType().Name -replace 'StatementAst$'
        }
    }
}

function Get-ConditionLabel {
    param($loopAst)

    switch ($loopAst) {
        default {
            if ($null -eq $loopAst.Condition) { "`$true" }
            else { "[bool]($($loopAst.Condition.Extent.Text))" }
        }
    }
}

function Get-ExitLabel {
    param($loopAst)
    if ($loopAst -is [System.Management.Automation.Language.DoUntilStatementAst]) {
        return "True"
    }
    return "False"
}

function Get-LoopEndText {
    param($loopAst)
    $typeName = $loopAst.GetType().Name -replace 'StatementAst$'
    "End $typeName"
}

function Get-LoopBackLabel {
    param($loopAst)
    if ($loopAst -is [System.Management.Automation.Language.DoUntilStatementAst]) {
        return "False"
    }
    return "True"
}

function Convert-LoopStatement {
    param(
        [hashtable]$cfg,
        [System.Management.Automation.Language.LoopStatementAst]$loopAst,
        [ref]$prevNodeRef,
        $endNodeRef = $null
    )

    if ($null -eq $loopAst -or $null -eq $prevNodeRef) {
        Write-Warning "Invalid input: loopAst or prevNodeRef is null"
        return
    }

    $loopType = switch ($loopAst) {
        {$_ -is [System.Management.Automation.Language.ForStatementAst]}       { "for" }
        {$_ -is [System.Management.Automation.Language.ForEachStatementAst]}    { "foreach" }
        {$_ -is [System.Management.Automation.Language.WhileStatementAst]}      { "while" }
        {$_ -is [System.Management.Automation.Language.DoWhileStatementAst]}   { "do-while" }
        {$_ -is [System.Management.Automation.Language.DoUntilStatementAst]}   { "do-until" }
        default { "unknown-loop" }
    }
    $isForEach = $loopAst -is [System.Management.Automation.Language.ForEachStatementAst]
    $isFor     = $loopAst -is [System.Management.Automation.Language.ForStatementAst]

    $loopStart = Add-Node -cfg $cfg -type "LoopStart" -text (Get-LoopHeaderText $loopAst) -line $loopAst.Extent.StartLineNumber -ast $null
    Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $loopStart.Id
    $currentNode = $loopStart

    #     for ($i = 0; $i -lt $max; $i++) { ... }
    #     => LoopStart -> (ForInit: $i = 0) -> Condition
    if ($isFor -and $null -ne $loopAst.Initializer) {
        $initAst = $loopAst.Initializer
        $initNode = Add-Node -cfg $cfg -type "ForInit" -text $initAst.Extent.Text -line $initAst.Extent.StartLineNumber -ast $initAst
        Add-Edge -cfg $cfg -from $currentNode.Id -to $initNode.Id
        $currentNode = $initNode
    }

    #     foreach ($item in $collection) { ... }
    if ($isForEach) {
        $guid = [guid]::NewGuid().ToString("N").Substring(0, 12)
        $collectionVar = "__fe_$guid"
        $indexVar = "__fe_${guid}_idx"

        $itemVarText = $loopAst.Variable.Extent.Text
        $itemVarName = $loopAst.Variable.VariablePath.UserPath
        $collectionExpr = $loopAst.Condition.Extent.Text

        $collectionVarEntry = [PSCustomObject]@{ Name = $collectionVar; Scope = [VarScope]::Unspecified }
        $indexVarEntry = [PSCustomObject]@{ Name = $indexVar; Scope = [VarScope]::Unspecified }
        $itemVarEntry = [PSCustomObject]@{ Name = $itemVarName; Scope = [VarScope]::Unspecified }


        $prevNodeRefForPipeline = [ref]$currentNode
        $conditionExpansion = Expand-NestedPipelines -cfg $cfg -ast $loopAst.Condition -prevNodeRef $prevNodeRefForPipeline
        $currentNode = $prevNodeRefForPipeline.Value

        if ($null -ne $conditionExpansion) {
            $initText = "`$$collectionVar = " + $conditionExpansion.ModifiedText + "; `$$indexVar = 0"
            $initNode = Add-Node -cfg $cfg -type "ForEachInit" -text $initText -line $loopAst.Condition.Extent.StartLineNumber -ast $loopAst.Condition
            foreach ($pipeVarEntry in $conditionExpansion.PipeVarEntries) {
                Add-VarToNode -node $initNode -varEntry $pipeVarEntry -accessType "Read"
            }
            Add-Edge -cfg $cfg -from $currentNode.Id -to $initNode.Id -label "Pipeline"
        } else {
            $initText = "`$$collectionVar = $collectionExpr; `$$indexVar = 0"
            $initNode = Add-Node -cfg $cfg -type "ForEachInit" -text $initText -line $loopAst.Condition.Extent.StartLineNumber -ast $loopAst.Condition
            Add-Edge -cfg $cfg -from $currentNode.Id -to $initNode.Id
        }
        Add-VarToNode -node $initNode -varEntry $collectionVarEntry -accessType "Write"
        Add-VarToNode -node $initNode -varEntry $indexVarEntry -accessType "Write"
        $currentNode = $initNode

        $condText = "[bool](`$$indexVar -lt `$$collectionVar.Count)"
        $conditionNode = Add-Node -cfg $cfg -type "ForEachCondition" -text $condText -line $loopAst.Extent.StartLineNumber -ast $null -ownerAst $loopAst
        $conditionNode.VarsRead = @($indexVarEntry, $collectionVarEntry)
        $conditionNode.VarsWritten = @()
        Add-Edge -cfg $cfg -from $currentNode.Id -to $conditionNode.Id

        $loopEnd = Add-Node -cfg $cfg -type "LoopEnd" -text "End ForEach" -line $loopAst.Extent.EndLineNumber -ast $null
        Add-Edge -cfg $cfg -from $conditionNode.Id -to $loopEnd.Id -label "No more items"

        $bindText = "$itemVarText = `$$collectionVar[`$$indexVar]"
        $bindNode = Add-Node -cfg $cfg -type "ForEachBind" -text $bindText -line $loopAst.Variable.Extent.StartLineNumber -ast $null -ownerAst $loopAst
        $bindNode.VarsRead = @($collectionVarEntry, $indexVarEntry)
        $bindNode.VarsWritten = @($itemVarEntry)
        Add-Edge -cfg $cfg -from $conditionNode.Id -to $bindNode.Id -label "Has next"
        $currentNode = $bindNode

        $iterText = "`$$indexVar++"
        $iterNode = Add-Node -cfg $cfg -type "ForEachIter" -text $iterText -line $loopAst.Extent.StartLineNumber -ast $null -ownerAst $loopAst
        $iterNode.VarsRead = @($indexVarEntry)
        $iterNode.VarsWritten = @($indexVarEntry)
        Add-Edge -cfg $cfg -from $iterNode.Id -to $conditionNode.Id

        $loopContext = [PSCustomObject]@{
            LoopEnd = $loopEnd
            LoopContinue = $iterNode
        }

        foreach ($statement in $loopAst.Body.Statements) {
            $hasReturn = Convert-AstNode -cfg $cfg -node $statement -prevNodeRef ([ref]$currentNode) -endNodeRef $endNodeRef -loopContext $loopContext -switchContext $null
            if ($hasReturn) { break }
        }

        if ($null -ne $currentNode -and $currentNode.Type -notin @("Break", "Continue")) {
            Add-Edge -cfg $cfg -from $currentNode.Id -to $iterNode.Id
        }

        $prevNodeRef.Value = $loopEnd
        return
    }

    $isDoLoop = $loopType -in "do-while", "do-until"
    if ($isDoLoop) {
        $loopEnd = Add-Node -cfg $cfg -type "LoopEnd" -text (Get-LoopEndText $loopAst) -line $loopAst.Extent.EndLineNumber -ast $null

        $conditionAst = $loopAst.Condition
        $conditionLine = if ($null -ne $loopAst.Condition) { $loopAst.Condition.Extent.StartLineNumber } else { $loopAst.Extent.StartLineNumber }

        $conditionExpansion = $null
        $pipelineFirstNode = $null
        if ($null -ne $loopAst.Condition) {
            $tempPrevNode = $null
            $tempPrevNodeRef = [ref]$tempPrevNode
            $conditionExpansion = Expand-NestedPipelines -cfg $cfg -ast $loopAst.Condition -prevNodeRef $tempPrevNodeRef

            if ($null -ne $conditionExpansion) {
                $pipelineFirstNode = $cfg.Nodes | Where-Object { $_.Type -eq "PipelineElement" } | Select-Object -Last ($conditionExpansion.PipeVarEntries.Count + 1) | Select-Object -First 1
            }
        }

        if ($null -ne $conditionExpansion) {
            $conditionNode = Add-Node -cfg $cfg -type "Condition" -text "[bool]($($conditionExpansion.ModifiedText))" -line $conditionLine -ast $conditionAst
            foreach ($pipeVarEntry in $conditionExpansion.PipeVarEntries) {
                Add-VarToNode -node $conditionNode -varEntry $pipeVarEntry -accessType "Read"
            }
            $lastPipeNode = $cfg.Nodes | Where-Object { $_.Type -eq "PipelineElement" } | Select-Object -Last 1
            Add-Edge -cfg $cfg -from $lastPipeNode.Id -to $conditionNode.Id -label "Pipeline"
        } else {
            $conditionNode = Add-Node -cfg $cfg -type "Condition" -text (Get-ConditionLabel $loopAst) -line $conditionLine -ast $conditionAst
        }

        $conditionEntryNode = if ($null -ne $pipelineFirstNode) { $pipelineFirstNode } else { $conditionNode }
        $loopContext = [PSCustomObject]@{
            LoopEnd = $loopEnd
            LoopContinue = $conditionEntryNode
        }

        foreach ($statement in $loopAst.Body.Statements) {
            $hasReturn = Convert-AstNode -cfg $cfg -node $statement -prevNodeRef ([ref]$currentNode) -endNodeRef $endNodeRef -loopContext $loopContext -switchContext $null
            if ($hasReturn) {
                break
            }
        }

        if ($null -ne $currentNode) {
            $lastNodeType = $currentNode.Type
            if ($lastNodeType -ne "Break" -and $lastNodeType -ne "Continue") {
                Add-Edge -cfg $cfg -from $currentNode.Id -to $conditionEntryNode.Id
            }
        }

        Add-Edge -cfg $cfg -from $conditionNode.Id -to $loopStart.Id -label (Get-LoopBackLabel $loopAst)
        Add-Edge -cfg $cfg -from $conditionNode.Id -to $loopEnd.Id -label (Get-ExitLabel $loopAst)

        $prevNodeRef.Value = $loopEnd
        return
    }

    $conditionAst = if ($isForEach) { $loopAst } else { $loopAst.Condition }
    $conditionLine = if ($null -ne $loopAst.Condition) { $loopAst.Condition.Extent.StartLineNumber } else { $loopAst.Extent.StartLineNumber }

    $conditionEntryNode = $null
    if ($null -ne $loopAst.Condition -and -not $isForEach) {
        $nodeBeforePipeline = $currentNode
        $prevNodeRefForPipeline = [ref]$currentNode
        $conditionExpansion = Expand-NestedPipelines -cfg $cfg -ast $loopAst.Condition -prevNodeRef $prevNodeRefForPipeline
        $currentNode = $prevNodeRefForPipeline.Value

        if ($null -ne $conditionExpansion) {
            $conditionNode = Add-Node -cfg $cfg -type "Condition" -text "[bool]($($conditionExpansion.ModifiedText))" -line $conditionLine -ast $conditionAst
            foreach ($pipeVarEntry in $conditionExpansion.PipeVarEntries) {
                Add-VarToNode -node $conditionNode -varEntry $pipeVarEntry -accessType "Read"
            }
            Add-Edge -cfg $cfg -from $currentNode.Id -to $conditionNode.Id -label "Pipeline"
            $pipelineEdge = $cfg.Edges | Where-Object { $_.From -eq $nodeBeforePipeline.Id } | Select-Object -Last 1
            if ($pipelineEdge) {
                $conditionEntryNode = $cfg.Nodes | Where-Object { $_.Id -eq $pipelineEdge.To }
            }
        } else {
            $conditionNode = Add-Node -cfg $cfg -type "Condition" -text (Get-ConditionLabel $loopAst) -line $conditionLine -ast $conditionAst
            Add-Edge -cfg $cfg -from $currentNode.Id -to $conditionNode.Id
            $conditionEntryNode = $conditionNode
        }
    } else {
        $conditionNode = Add-Node -cfg $cfg -type "Condition" -text (Get-ConditionLabel $loopAst) -line $conditionLine -ast $conditionAst
        Add-Edge -cfg $cfg -from $currentNode.Id -to $conditionNode.Id
        $conditionEntryNode = $conditionNode
    }
    $currentNode = $conditionNode

    $loopEnd = Add-Node -cfg $cfg -type "LoopEnd" -text (Get-LoopEndText $loopAst) -line $loopAst.Extent.EndLineNumber -ast $null

    $iteratorNode = $null
    if ($isFor -and $null -ne $loopAst.Iterator) {
        $iterAst = $loopAst.Iterator
        $iteratorNode = Add-Node -cfg $cfg -type "ForIter" -text $iterAst.Extent.Text -line $iterAst.Extent.StartLineNumber -ast $iterAst
    }

    $loopContext = [PSCustomObject]@{
        LoopEnd = $loopEnd
        LoopContinue = if ($null -ne $iteratorNode) { $iteratorNode } else { $conditionNode }
    }

    $firstBodyNodeId = $null
    foreach ($statement in $loopAst.Body.Statements) {
        $hasReturn = Convert-AstNode -cfg $cfg -node $statement -prevNodeRef ([ref]$currentNode) -endNodeRef $endNodeRef -loopContext $loopContext -switchContext $null

        if ($null -eq $firstBodyNodeId -and $currentNode.Id -ne $conditionNode.Id) {
            $firstBodyNodeId = $currentNode.Id
            foreach ($edge in $cfg.Edges) {
                if ($edge.From -eq $conditionNode.Id -and $edge.To -eq $firstBodyNodeId) {
                    $edge.Label = "True"
                    break
                }
            }
        }

        if ($hasReturn) {
            break
        }
    }
    if ($null -ne $currentNode) {
        $lastNodeType = $currentNode.Type
        if ($lastNodeType -ne "Break" -and $lastNodeType -ne "Continue") {
            if ($null -ne $iteratorNode) {
                Add-Edge -cfg $cfg -from $currentNode.Id -to $iteratorNode.Id
            } else {
                Add-Edge -cfg $cfg -from $currentNode.Id -to $conditionEntryNode.Id -label "Next"
            }
        }
    }

    if ($null -ne $iteratorNode) {
        Add-Edge -cfg $cfg -from $iteratorNode.Id -to $conditionEntryNode.Id
    }

    Add-Edge -cfg $cfg -from $conditionNode.Id -to $loopEnd.Id -label (Get-ExitLabel $loopAst)
    $prevNodeRef.Value = $loopEnd
}

function Convert-AssignmentAstNode {
    param(
        [hashtable]$cfg,
        [System.Management.Automation.Language.AssignmentStatementAst]$assignAst,
        [ref]$prevNodeRef
    )

    if ($assignAst.Right -is [System.Management.Automation.Language.PipelineAst] -and
        $assignAst.Right.PipelineElements.Count -gt 1) {
        $leftText = $assignAst.Left.Extent.Text
        $operatorText = switch ($assignAst.Operator) {
            "Equals"           { "=" }
            "PlusEquals"       { "+=" }
            "MinusEquals"      { "-=" }
            "MultiplyEquals"   { "*=" }
            "DivideEquals"     { "/=" }
            "RemainderEquals"  { "%=" }
            default            { "=" }
        }

        $elements = $assignAst.Right.PipelineElements
        $lastIndex = $elements.Count - 1

        $guid = [guid]::NewGuid().ToString("N").Substring(0, 8)
        $pipeVarName = "_pipe_$guid"
        $pipeVarEntry = [PSCustomObject]@{ Name = $pipeVarName; Scope = [VarScope]::Unspecified }

        for ($i = 0; $i -lt $elements.Count; $i++) {
            $element = $elements[$i]
            $baseText = $element.Extent.Text
            $hasPipelineExpansion = $false
            $allVarEntries = @()

            $pipelineExpansion = Expand-NestedPipelines -cfg $cfg -ast $element -prevNodeRef $prevNodeRef
            if ($null -ne $pipelineExpansion) {
                $baseText = $pipelineExpansion.ModifiedText
                $allVarEntries += $pipelineExpansion.PipeVarEntries
                if ($null -ne $pipelineExpansion.ScriptBlockVarEntries) {
                    $allVarEntries += $pipelineExpansion.ScriptBlockVarEntries
                }
                $hasPipelineExpansion = $true
            }

            $expandedForEach = $false
            if ($i -gt 0 -and $element -is [System.Management.Automation.Language.CommandAst]) {
                $foreachExpansion = Expand-ForEachObjectPipelineElement -cfg $cfg -CommandAst $element -prevNodeRef $prevNodeRef -PipeVarName $pipeVarName -PipeVarEntry $pipeVarEntry -IncomingEdgeLabel 'Pipeline'
                if ($foreachExpansion.Expanded) {
                    $expandedForEach = $true
                    if ($i -eq $lastIndex) {
                        $assignText = "$leftText $operatorText `$$pipeVarName"
                        $assignNode = Add-Node -cfg $cfg -type $assignAst.GetType().Name -text $assignText -line $assignAst.Extent.StartLineNumber -ast $assignAst
                        Add-VarToNode -node $assignNode -varEntry $pipeVarEntry -accessType "Read"
                        if ($null -ne $prevNodeRef.Value) {
                            Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $assignNode.Id -label "Pipeline"
                        }
                        $prevNodeRef.Value = $assignNode
                    }
                }
            }

            if ($expandedForEach) {
                continue
            }

            if (-not $hasPipelineExpansion) {
                $sbExpansion = Expand-NestedScriptBlocks -cfg $cfg -ast $element -prevNodeRef $prevNodeRef
                if ($null -ne $sbExpansion -and -not $sbExpansion.InvokeOnlyExpanded -and $null -ne $sbExpansion.ModifiedText) {
                    $baseText = $sbExpansion.ModifiedText
                    if ($null -ne $sbExpansion.ScriptBlockVarEntries) {
                        $allVarEntries += $sbExpansion.ScriptBlockVarEntries
                    }
                }
            }
            else {
                $remainingSBs = Get-AllNestedScriptBlocks -ast $element
                foreach ($sb in $remainingSBs) {
                    if ($cfg.ProcessedScriptBlocks.ContainsKey($sb)) {
                        $varName = $cfg.ProcessedScriptBlocks[$sb]
                        $baseText = $baseText.Replace($sb.Extent.Text, "`$$varName")
                        $allVarEntries += [PSCustomObject]@{ Name = $varName; Scope = [VarScope]::Unspecified }
                    }
                }
            }

            if ($i -eq 0) {
                $nodeText = $baseText
            } elseif ($i -eq $lastIndex) {
                $nodeText = "$leftText $operatorText `$$pipeVarName | " + $baseText
            } else {
                $nodeText = "`$$pipeVarName | " + $baseText
            }

            $nodeAst = if ($i -eq $lastIndex) { $assignAst } else { $element }
            $pipeNode = Add-Node -cfg $cfg -type "PipelineElement" -text $nodeText -line $element.Extent.StartLineNumber -ast $nodeAst
            Mark-PipelineCmdletNode -Node $pipeNode -ElementAst $element

            foreach ($varEntry in $allVarEntries) {
                Add-VarToNode -node $pipeNode -varEntry $varEntry -accessType "Read"
            }

            if ($i -eq 0) {
                Add-VarToNode -node $pipeNode -varEntry $pipeVarEntry -accessType "Write"
            } elseif ($i -eq $lastIndex) {
                Add-VarToNode -node $pipeNode -varEntry $pipeVarEntry -accessType "Read"
            } else {
                Add-VarToNode -node $pipeNode -varEntry $pipeVarEntry -accessType "Both"
            }

            if ($null -ne $prevNodeRef.Value) {
                if ($hasPipelineExpansion -or $i -gt 0) {
                    Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $pipeNode.Id -label "Pipeline"
                } else {
                    Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $pipeNode.Id
                }
            }
            $prevNodeRef.Value = $pipeNode
        }
        return
    }

    $isDirectScriptBlockAssignment = $false
    $nestedScriptBlocks = Get-AllNestedScriptBlocks -ast $assignAst.Right
    foreach ($sb in $nestedScriptBlocks) {
        if ($cfg.ProcessedScriptBlocks.ContainsKey($sb)) {
            continue
        }

        $execType = Get-ScriptBlockExecutionType -scriptBlockExprAst $sb
        if ($execType -eq "Deferred") {
            $varName = $null
            $left = $assignAst.Left
            if ($left -is [System.Management.Automation.Language.VariableExpressionAst]) {
                $varName = $left.VariablePath.UserPath
            }

            $isDirectAssignment = $false
            if ($null -ne $varName) {
                $rightAst = $assignAst.Right
                if ($rightAst -is [System.Management.Automation.Language.CommandExpressionAst] -and
                    $rightAst.Expression -eq $sb) {
                    $isDirectAssignment = $true
                }
                elseif ($rightAst -is [System.Management.Automation.Language.PipelineAst] -and
                    $rightAst.PipelineElements.Count -eq 1) {
                    $element = $rightAst.PipelineElements[0]
                    if ($element -is [System.Management.Automation.Language.CommandExpressionAst] -and
                        $element.Expression -eq $sb) {
                        $isDirectAssignment = $true
                    }
                }
            }

            if ($isDirectAssignment) {
                $cfg.ProcessedScriptBlocks[$sb] = $varName
                $null = Convert-ScriptBlockDefinition -cfg $cfg -scriptBlockExprAst $sb -blockName $varName
                $isDirectScriptBlockAssignment = $true
            } else {
                $guid = [guid]::NewGuid().ToString("N").Substring(0, 8)
                $blockName = "_block_$guid"
                $cfg.ProcessedScriptBlocks[$sb] = $blockName
                $null = Convert-ScriptBlockDefinition -cfg $cfg -scriptBlockExprAst $sb -blockName $blockName
            }
        }
    }

    $modifiedText = $assignAst.Extent.Text
    $hasExpansion = $false
    $hasPipelineNodes = $false
    $finalVarEntries = @()

    $pipelineExpansion = Expand-NestedPipelines -cfg $cfg -ast $assignAst.Right -prevNodeRef $prevNodeRef
    if ($null -ne $pipelineExpansion) {
        $modifiedText = $modifiedText.Replace($assignAst.Right.Extent.Text, $pipelineExpansion.ModifiedText)
        $hasExpansion = $true
        $hasPipelineNodes = $true
        if ($null -ne $pipelineExpansion.PipeVarEntries) {
            $finalVarEntries += $pipelineExpansion.PipeVarEntries
        }
        if ($null -ne $pipelineExpansion.ScriptBlockVarEntries) {
            $finalVarEntries += $pipelineExpansion.ScriptBlockVarEntries
        }
    }

    if (-not $hasPipelineNodes) {
        $scriptBlockExpansion = Expand-NestedScriptBlocks -cfg $cfg -ast $assignAst.Right -prevNodeRef $prevNodeRef
        if ($null -ne $scriptBlockExpansion) {
            if ($null -ne $scriptBlockExpansion.ModifiedText) {
                $modifiedText = $modifiedText.Replace($assignAst.Right.Extent.Text, $scriptBlockExpansion.ModifiedText)
                $hasExpansion = $true
            }
            if ($null -ne $scriptBlockExpansion.ScriptBlockVarEntries) {
                $finalVarEntries += $scriptBlockExpansion.ScriptBlockVarEntries
            }
        }
    }

    if (-not $hasExpansion -and -not $isDirectScriptBlockAssignment) {
        foreach ($sb in (Get-AllNestedScriptBlocks -ast $assignAst.Right)) {
            if ($cfg.ProcessedScriptBlocks.ContainsKey($sb)) {
                $varName = $cfg.ProcessedScriptBlocks[$sb]
                $modifiedText = $modifiedText.Replace($sb.Extent.Text, "`$$varName")
                $finalVarEntries += [PSCustomObject]@{ Name = $varName; Scope = [VarScope]::Unspecified }
            }
        }
    }

    $currentNode = Add-Node -cfg $cfg -type $assignAst.GetType().Name -text $modifiedText -line $assignAst.Extent.StartLineNumber -ast $assignAst
    foreach ($varEntry in $finalVarEntries) {
        Add-VarToNode -node $currentNode -varEntry $varEntry -accessType "Read"
    }

    if ($null -ne $prevNodeRef.Value) {
        if ($hasPipelineNodes) {
            Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $currentNode.Id -label "Pipeline"
        } else {
            Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $currentNode.Id
        }
    }
    $prevNodeRef.Value = $currentNode
}
function Convert-PipelineAstNode {
    param(
        [hashtable]$cfg,
        [System.Management.Automation.Language.PipelineAst]$pipelineAst,
        [ref]$prevNodeRef,
        $endNodeRef = $null,
        $loopContext = $null,
        $switchContext = $null
    )

    $elements = $pipelineAst.PipelineElements
    $lastIndex = $elements.Count - 1

    $guid = [guid]::NewGuid().ToString("N").Substring(0, 8)
    $pipeVarName = "_pipe_$guid"
    $pipeVarEntry = [PSCustomObject]@{ Name = $pipeVarName; Scope = [VarScope]::Unspecified }

    for ($i = 0; $i -lt $elements.Count; $i++) {
        $element = $elements[$i]
        $baseText = $element.Extent.Text
        $hasExpansion = $false
        $hasPipelineExpansion = $false
        $allVarEntries = @()
        $skipNodeCreation = $false

        $pipelineExpansion = Expand-NestedPipelines -cfg $cfg -ast $element -prevNodeRef $prevNodeRef
        if ($null -ne $pipelineExpansion) {
            $baseText = $pipelineExpansion.ModifiedText
            $allVarEntries += $pipelineExpansion.PipeVarEntries
            if ($null -ne $pipelineExpansion.ScriptBlockVarEntries) {
                $allVarEntries += $pipelineExpansion.ScriptBlockVarEntries
            }
            $hasExpansion = $true
            $hasPipelineExpansion = $true
        }

        $expandedForEach = $false
        if ($i -gt 0 -and $element -is [System.Management.Automation.Language.CommandAst]) {
            $foreachExpansion = Expand-ForEachObjectPipelineElement -cfg $cfg -CommandAst $element -prevNodeRef $prevNodeRef -PipeVarName $pipeVarName -PipeVarEntry $pipeVarEntry -IncomingEdgeLabel 'Pipeline'
            if ($foreachExpansion.Expanded) {
                $expandedForEach = $true
                if ($i -eq $lastIndex) {
                    $emitNode = Add-Node -cfg $cfg -type "PipelineElement" -text "`$$pipeVarName" -line $element.Extent.StartLineNumber -ast $null -ownerAst $element
                    $emitNode.VarsRead = @($pipeVarEntry)
                    $emitNode.VarsWritten = @()
                    if ($null -ne $prevNodeRef.Value) {
                        Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $emitNode.Id -label "Pipeline"
                    }
                    $prevNodeRef.Value = $emitNode
                }
            }
        }

        if ($expandedForEach) {
            continue
        }

        if (-not $hasExpansion) {
            $scriptBlockExpansion = Expand-NestedScriptBlocks -cfg $cfg -ast $element -prevNodeRef $prevNodeRef -endNodeRef $endNodeRef -loopContext $loopContext -switchContext $switchContext
            if ($null -ne $scriptBlockExpansion) {
                if ($scriptBlockExpansion.InvokeOnlyExpanded) {
                    if ($i -gt 0 -and $null -ne $prevNodeRef.Value) {
                        $createdNode = $prevNodeRef.Value
                        $createdNode.Text = "`$$pipeVarName | " + $createdNode.Text
                        Add-VarToNode -node $createdNode -varEntry $pipeVarEntry -accessType "Read"
                    }
                    $skipNodeCreation = $true
                } elseif ($null -ne $scriptBlockExpansion.ModifiedText) {
                    $baseText = $scriptBlockExpansion.ModifiedText
                    $allVarEntries += $scriptBlockExpansion.ScriptBlockVarEntries
                    $hasExpansion = $true
                }
            }
        } else {
            $remainingSBs = Get-AllNestedScriptBlocks -ast $element
            foreach ($sb in $remainingSBs) {
                if ($cfg.ProcessedScriptBlocks.ContainsKey($sb)) {
                    $varName = $cfg.ProcessedScriptBlocks[$sb]
                    $baseText = $baseText.Replace($sb.Extent.Text, "`$$varName")
                }
            }
        }

        if ($skipNodeCreation) {
            continue
        }

        $nodeText = if ($i -gt 0) { "`$$pipeVarName | " + $baseText } else { $baseText }
        $pipeNode = Add-Node -cfg $cfg -type "PipelineElement" -text $nodeText -line $element.Extent.StartLineNumber -ast $element
        Mark-PipelineCmdletNode -Node $pipeNode -ElementAst $element

        foreach ($varEntry in $allVarEntries) {
            Add-VarToNode -node $pipeNode -varEntry $varEntry -accessType "Read"
        }

        if ($null -ne $prevNodeRef.Value) {
            if ($hasPipelineExpansion) {
                Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $pipeNode.Id -label "Pipeline"
            } elseif ($i -gt 0) {
                Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $pipeNode.Id -label "Pipeline"
            } else {
                Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $pipeNode.Id
            }
        }

        if ($i -eq 0) {
            if ($elements.Count -gt 1) {
                Add-VarToNode -node $pipeNode -varEntry $pipeVarEntry -accessType "Write"
            }
        } elseif ($i -eq $lastIndex) {
            Add-VarToNode -node $pipeNode -varEntry $pipeVarEntry -accessType "Read"
        } else {
            Add-VarToNode -node $pipeNode -varEntry $pipeVarEntry -accessType "Both"
        }

        $prevNodeRef.Value = $pipeNode
    }
}
function Convert-ReturnAstNode {
    param(
        [hashtable]$cfg,
        [System.Management.Automation.Language.ReturnStatementAst]$returnAst,
        [ref]$prevNodeRef,
        $endNodeRef = $null
    )

    $returnExpansion = $null
    if ($null -ne $returnAst.Pipeline) {
        $returnExpansion = Expand-NestedPipelines -cfg $cfg -ast $returnAst.Pipeline -prevNodeRef $prevNodeRef
    }

    if ($null -ne $returnExpansion) {
        $modifiedReturnText = "return " + $returnExpansion.ModifiedText
        $returnNode = Add-Node -cfg $cfg -type "Return" -text $modifiedReturnText -line $returnAst.Extent.StartLineNumber -ast $returnAst
        foreach ($pipeVarEntry in $returnExpansion.PipeVarEntries) {
            Add-VarToNode -node $returnNode -varEntry $pipeVarEntry -accessType "Read"
        }
        if ($null -ne $prevNodeRef.Value) {
            Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $returnNode.Id -label "Pipeline"
        }
    } else {
        $returnNode = Add-Node -cfg $cfg -type "Return" -text $returnAst.Extent.Text -line $returnAst.Extent.StartLineNumber -ast $returnAst
        if ($null -ne $prevNodeRef.Value) {
            Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $returnNode.Id
        }
    }

    $inTryWithFinally = $false
    $ancestor = $returnAst.Parent
    while ($null -ne $ancestor) {
        if ($ancestor -is [System.Management.Automation.Language.TryStatementAst]) {
            if ($null -ne $ancestor.Finally) {
                $inTryWithFinally = $true
            }
            break
        }
        $ancestor = $ancestor.Parent
    }

    if (-not $inTryWithFinally -and $null -ne $endNodeRef) {
        $endNode = if ($endNodeRef -is [ref]) { $endNodeRef.Value } else { $endNodeRef }
        if ($null -ne $endNode) {
            Add-Edge -cfg $cfg -from $returnNode.Id -to $endNode.Id -label "Return"
        }
    }

    $prevNodeRef.Value = $returnNode
    return $true
}

function Convert-ExitAstNode {
    param(
        [hashtable]$cfg,
        [System.Management.Automation.Language.ExitStatementAst]$exitAst,
        [ref]$prevNodeRef,
        $endNodeRef = $null
    )

    $exitNode = Add-Node -cfg $cfg -type "Exit" -text $exitAst.Extent.Text -line $exitAst.Extent.StartLineNumber -ast $exitAst
    if ($null -ne $prevNodeRef.Value) {
        Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $exitNode.Id
    }

    $inTryWithFinally = $false
    $ancestor = $exitAst.Parent
    while ($null -ne $ancestor) {
        if ($ancestor -is [System.Management.Automation.Language.TryStatementAst]) {
            if ($null -ne $ancestor.Finally) {
                $inTryWithFinally = $true
            }
            break
        }
        $ancestor = $ancestor.Parent
    }

    if (-not $inTryWithFinally) {
        if ($script:__CFG_ScriptEndNode) {
            Add-Edge -cfg $cfg -from $exitNode.Id -to $script:__CFG_ScriptEndNode.Id -label "Exit"
        }
        elseif ($null -ne $endNodeRef) {
            $endNode = if ($endNodeRef -is [ref]) { $endNodeRef.Value } else { $endNodeRef }
            if ($null -ne $endNode) {
                Add-Edge -cfg $cfg -from $exitNode.Id -to $endNode.Id -label "Exit"
            }
        }
    }

    $prevNodeRef.Value = $exitNode
    return $true
}

function Convert-BreakAstNode {
    param(
        [hashtable]$cfg,
        [System.Management.Automation.Language.BreakStatementAst]$breakAst,
        [ref]$prevNodeRef,
        $endNodeRef = $null,
        $loopContext = $null,
        $switchContext = $null
    )

    $breakNode = Add-Node -cfg $cfg -type "Break" -text $breakAst.Extent.Text -line $breakAst.Extent.StartLineNumber -ast $breakAst
    if ($null -ne $prevNodeRef.Value) {
        Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $breakNode.Id
    }

    if ($null -ne $switchContext -and $null -ne $switchContext.SwitchMerge) {
        Add-Edge -cfg $cfg -from $breakNode.Id -to $switchContext.SwitchMerge.Id -label "Break"
    }
    elseif ($null -ne $loopContext -and $null -ne $loopContext.LoopEnd) {
        Add-Edge -cfg $cfg -from $breakNode.Id -to $loopContext.LoopEnd.Id -label "Break"
    }
    else {
        if ($null -ne $endNodeRef) {
            $endNode = if ($endNodeRef -is [ref]) { $endNodeRef.Value } else { $endNodeRef }
            if ($null -ne $endNode) {
                Add-Edge -cfg $cfg -from $breakNode.Id -to $endNode.Id -label "Break"
            }
        }
    }

    $prevNodeRef.Value = $breakNode
    return $true
}

function Convert-ContinueAstNode {
    param(
        [hashtable]$cfg,
        [System.Management.Automation.Language.ContinueStatementAst]$continueAst,
        [ref]$prevNodeRef,
        $endNodeRef = $null,
        $loopContext = $null,
        $switchContext = $null
    )

    $continueNode = Add-Node -cfg $cfg -type "Continue" -text $continueAst.Extent.Text -line $continueAst.Extent.StartLineNumber -ast $continueAst
    if ($null -ne $prevNodeRef.Value) {
        Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $continueNode.Id
    }

    if ($null -ne $switchContext -and $null -ne $switchContext.SwitchNode) {
        Add-Edge -cfg $cfg -from $continueNode.Id -to $switchContext.SwitchNode.Id -label "Continue"
    }
    elseif ($null -ne $loopContext -and $null -ne $loopContext.LoopContinue) {
        Add-Edge -cfg $cfg -from $continueNode.Id -to $loopContext.LoopContinue.Id -label "Continue"
    }
    else {
        if ($null -ne $endNodeRef) {
            $endNode = if ($endNodeRef -is [ref]) { $endNodeRef.Value } else { $endNodeRef }
            if ($null -ne $endNode) {
                Add-Edge -cfg $cfg -from $continueNode.Id -to $endNode.Id -label "Continue"
            }
        }
    }

    $prevNodeRef.Value = $continueNode
    return $true
}

function Convert-ThrowAstNode {
    param(
        [hashtable]$cfg,
        [System.Management.Automation.Language.ThrowStatementAst]$throwAst,
        [ref]$prevNodeRef,
        $endNodeRef = $null
    )

    $throwNode = Add-Node -cfg $cfg -type "Throw" -text $throwAst.Extent.Text -line $throwAst.Extent.StartLineNumber -ast $throwAst
    if ($null -ne $prevNodeRef.Value) {
        Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $throwNode.Id
    }

    $inCatch = $false
    $inFinally = $false
    $hasTryAncestor = $false
    $ancestor = $throwAst.Parent
    while ($null -ne $ancestor) {
        if ($ancestor -is [System.Management.Automation.Language.CatchClauseAst]) {
            $inCatch = $true
        }
        elseif ($ancestor -is [System.Management.Automation.Language.StatementBlockAst]) {
            $parentTry = $ancestor.Parent
            if ($parentTry -is [System.Management.Automation.Language.TryStatementAst] -and
                $parentTry.Finally -eq $ancestor) {
                $inFinally = $true
            }
        }
        elseif ($ancestor -is [System.Management.Automation.Language.TryStatementAst]) {
            $hasTryAncestor = $true
        }
        $ancestor = $ancestor.Parent
    }

    if (($inCatch -or $inFinally) -and $null -ne $endNodeRef) {
        $endNode = if ($endNodeRef -is [ref]) { $endNodeRef.Value } else { $endNodeRef }
        if ($null -ne $endNode) {
            Add-Edge -cfg $cfg -from $throwNode.Id -to $endNode.Id -label "Uncaught Exception"
        }
    }
    elseif (-not $hasTryAncestor -and $null -ne $endNodeRef) {
        $endNode = if ($endNodeRef -is [ref]) { $endNodeRef.Value } else { $endNodeRef }
        if ($null -ne $endNode) {
            Add-Edge -cfg $cfg -from $throwNode.Id -to $endNode.Id -label "Uncaught Exception"
        }
    }

    $prevNodeRef.Value = $throwNode
    return $true
}

function Convert-FunctionDefAstNode {
    param(
        [hashtable]$cfg,
        [System.Management.Automation.Language.FunctionDefinitionAst]$funcDefAst,
        [ref]$prevNodeRef
    )

    $funcName = $funcDefAst.Name
    $defText = "function $funcName"
    $funcDefNode = Add-Node -cfg $cfg -type "FunctionDef" -text $defText -line $funcDefAst.Extent.StartLineNumber -ast $null
    if ($null -ne $prevNodeRef.Value) {
        Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $funcDefNode.Id
    }
    $prevNodeRef.Value = $funcDefNode

    $null = $cfg.DefinedFunctions.Add($funcName)

    Convert-FunctionDefinitionAst -cfg $cfg -funcAst $funcDefAst

    return $false
}

function Convert-AstNode {
    param(
        $cfg,
        $node,
        [ref]$prevNodeRef,
        $endNodeRef = $null,
        $loopContext = $null,
        $switchContext = $null
    )

    if ($node -is [System.Management.Automation.Language.ScriptBlockAst]) {
        $startNode = Add-Node -cfg $cfg -type "Start" -text "Script Start" -line 0

        $endNode = Add-Node -cfg $cfg -type "End" -text "Script End" -line $node.Extent.EndLineNumber
        $script:__CFG_ScriptEndNode = $endNode

        $mainStart = Add-Node -cfg $cfg -type "MainStart" -text "Main Script" -line $node.Extent.StartLineNumber -ast $null
        $mainEnd = Add-Node -cfg $cfg -type "MainEnd" -text "End Main Script" -line $node.Extent.EndLineNumber -ast $null

        Add-Edge -cfg $cfg -from $startNode.Id -to $mainStart.Id

        $prevNodeRef.Value = $mainStart
        $mainEndRef = [ref]$mainEnd

        $null = Convert-ScriptBlockBody -cfg $cfg -scriptBlockAst $node -prevNodeRef $prevNodeRef -endNodeRef $mainEndRef -paramNodeType "ScriptParams" -IsTopLevelScript $true

        if ($null -ne $prevNodeRef.Value -and $prevNodeRef.Value.Id -ne $mainEnd.Id) {
            $lastNodeType = $prevNodeRef.Value.Type
            if ($lastNodeType -notin @("Return", "Break", "Continue", "Throw", "Exit")) {
                Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $mainEnd.Id
            }
        }

        Add-Edge -cfg $cfg -from $mainEnd.Id -to $endNode.Id

        $prevNodeRef.Value = $endNode
    }
    elseif ($node -is [System.Management.Automation.Language.ReturnStatementAst]) {
        return Convert-ReturnAstNode -cfg $cfg -returnAst $node -prevNodeRef $prevNodeRef -endNodeRef $endNodeRef
    }
    elseif ($node -is [System.Management.Automation.Language.ExitStatementAst]) {
        return Convert-ExitAstNode -cfg $cfg -exitAst $node -prevNodeRef $prevNodeRef -endNodeRef $endNodeRef
    }
    elseif ($node -is [System.Management.Automation.Language.BreakStatementAst]) {
        return Convert-BreakAstNode -cfg $cfg -breakAst $node -prevNodeRef $prevNodeRef -endNodeRef $endNodeRef -loopContext $loopContext -switchContext $switchContext
    }
    elseif ($node -is [System.Management.Automation.Language.ContinueStatementAst]) {
        return Convert-ContinueAstNode -cfg $cfg -continueAst $node -prevNodeRef $prevNodeRef -endNodeRef $endNodeRef -loopContext $loopContext -switchContext $switchContext
    }
    elseif ($node -is [System.Management.Automation.Language.ThrowStatementAst]) {
        return Convert-ThrowAstNode -cfg $cfg -throwAst $node -prevNodeRef $prevNodeRef -endNodeRef $endNodeRef
    }
    elseif ($node -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
        return Convert-FunctionDefAstNode -cfg $cfg -funcDefAst $node -prevNodeRef $prevNodeRef
    }
    elseif ($node -is [System.Management.Automation.Language.IfStatementAst]) {
        $allBranchesReturn = Convert-IfAstNode -cfg $cfg -ifAst $node -prevNodeRef $prevNodeRef -endNodeRef $endNodeRef -loopContext $loopContext
        return $allBranchesReturn
    }
    elseif ($node -is [System.Management.Automation.Language.SwitchStatementAst]) {
        $allBranchesReturn = Convert-SwitchAstNode -cfg $cfg -switchAst $node -prevNodeRef $prevNodeRef -endNodeRef $endNodeRef -loopContext $loopContext
        return $allBranchesReturn
    }
    elseif($node -is [System.Management.Automation.Language.LoopStatementAst]){
        Convert-LoopStatement -cfg $cfg -loopAst $node -prevNodeRef $prevNodeRef -endNodeRef $endNodeRef
        return $false
    }
    elseif ($node -is [System.Management.Automation.Language.TryStatementAst]) {
        $allBranchesReturn = Convert-TryAstNode -cfg $cfg -tryAst $node -prevNodeRef $prevNodeRef -endNodeRef $endNodeRef -loopContext $loopContext -switchContext $switchContext
        return $allBranchesReturn
    }
    elseif ($node -is [System.Management.Automation.Language.AssignmentStatementAst]) {
        Convert-AssignmentAstNode -cfg $cfg -assignAst $node -prevNodeRef $prevNodeRef
        return $false
    }
    elseif ($node -is [System.Management.Automation.Language.PipelineAst]) {
        Convert-PipelineAstNode -cfg $cfg -pipelineAst $node -prevNodeRef $prevNodeRef -endNodeRef $endNodeRef -loopContext $loopContext -switchContext $switchContext
        return $false
    }
    else {
        $nestedPipelines = @(Get-AllNestedPipelines -ast $node)

        if ($nestedPipelines.Count -gt 0) {
            $sortedPipelines = $nestedPipelines | Sort-Object { $_.Extent.StartOffset } -Descending

            $replacements = @()
            $allPipelineNodes = @()

            $allScriptBlockReplacements = @{}

            foreach ($pipeline in $sortedPipelines) {
                foreach ($element in $pipeline.PipelineElements) {
                    $nestedSBs = Get-AllNestedScriptBlocks -ast $element
                    foreach ($sb in $nestedSBs) {
                        if (-not $cfg.ProcessedScriptBlocks.ContainsKey($sb)) {
                            $execType = Get-ScriptBlockExecutionType -scriptBlockExprAst $sb
                            if ($execType -in @("Immediate", "PipelineValue", "InvokeOnly", "CmdletInvoke")) {
                                $guid = [guid]::NewGuid().ToString("N").Substring(0, 8)
                                $varName = "_block_$guid"
                                $cfg.ProcessedScriptBlocks[$sb] = $varName
                                $allScriptBlockReplacements[$sb] = $varName
                                $null = Convert-ScriptBlockDefinition -cfg $cfg -scriptBlockExprAst $sb -blockName $varName
                            }
                        } else {
                            $allScriptBlockReplacements[$sb] = $cfg.ProcessedScriptBlocks[$sb]
                        }
                    }
                }
            }

            foreach ($pipeline in $sortedPipelines) {
                $guid = [guid]::NewGuid().ToString("N").Substring(0, 8)
                $pipeVar = "_pipe_$guid"
                $pipeVarEntry = [PSCustomObject]@{ Name = $pipeVar; Scope = [VarScope]::Unspecified }

                $elements = $pipeline.PipelineElements
                $lastIndex = $elements.Count - 1

                $modifiedPipelineText = $pipeline.Extent.Text
                $nestedSBsInPipeline = Get-AllNestedScriptBlocks -ast $pipeline
                $sortedSBs = $nestedSBsInPipeline | Sort-Object { $_.Extent.StartOffset } -Descending
                foreach ($sb in $sortedSBs) {
                    if ($allScriptBlockReplacements.ContainsKey($sb)) {
                        $varName = $allScriptBlockReplacements[$sb]
                        $modifiedPipelineText = $modifiedPipelineText.Replace($sb.Extent.Text, "`$$varName")
                    }
                }

                for ($i = 0; $i -lt $elements.Count - 1; $i++) {
                    $element = $elements[$i]
                    $elementText = $element.Extent.Text
                    $elementVarEntries = @()

                    $nestedSBsInElement = Get-AllNestedScriptBlocks -ast $element
                    $sortedSBsInElement = $nestedSBsInElement | Sort-Object { $_.Extent.StartOffset } -Descending
                    foreach ($sb in $sortedSBsInElement) {
                        if ($allScriptBlockReplacements.ContainsKey($sb)) {
                            $varName = $allScriptBlockReplacements[$sb]
                            $elementText = $elementText.Replace($sb.Extent.Text, "`$$varName")
                            $elementVarEntries += [PSCustomObject]@{ Name = $varName; Scope = [VarScope]::Unspecified }
                        }
                    }

                    if ($i -eq 0) {
                        $nodeText = $elementText
                    } else {
                        $nodeText = "`$$pipeVar | " + $elementText
                    }

                    $pipeNode = Add-Node -cfg $cfg -type "PipelineElement" -text $nodeText -line $element.Extent.StartLineNumber -ast $element
                    Mark-PipelineCmdletNode -Node $pipeNode -ElementAst $element

                    foreach ($varEntry in $elementVarEntries) {
                        Add-VarToNode -node $pipeNode -varEntry $varEntry -accessType "Read"
                    }

                    if ($i -eq 0) {
                        Add-VarToNode -node $pipeNode -varEntry $pipeVarEntry -accessType "Write"
                    } else {
                        Add-VarToNode -node $pipeNode -varEntry $pipeVarEntry -accessType "Both"
                    }

                    $allPipelineNodes += @{
                        Node = $pipeNode
                        PipeVar = $pipeVar
                        Index = $i
                    }
                }

                $lastElement = $elements[$lastIndex]
                $lastElementText = $lastElement.Extent.Text
                $lastElementVarEntries = @()

                $nestedSBsInLast = Get-AllNestedScriptBlocks -ast $lastElement
                $sortedSBsInLast = $nestedSBsInLast | Sort-Object { $_.Extent.StartOffset } -Descending
                foreach ($sb in $sortedSBsInLast) {
                    if ($allScriptBlockReplacements.ContainsKey($sb)) {
                        $varName = $allScriptBlockReplacements[$sb]
                        $lastElementText = $lastElementText.Replace($sb.Extent.Text, "`$$varName")
                        $lastElementVarEntries += [PSCustomObject]@{ Name = $varName; Scope = [VarScope]::Unspecified }
                    }
                }

                $replacementText = "`$$pipeVar | " + $lastElementText

                $replacements += @{
                    Original = $modifiedPipelineText
                    Replacement = $replacementText
                    PipeVar = $pipeVar
                    PipeVarEntry = $pipeVarEntry
                    LastElementVarEntries = $lastElementVarEntries
                }
            }

            foreach ($pipeInfo in $allPipelineNodes) {
                if ($null -ne $prevNodeRef.Value) {
                    if ($pipeInfo.Index -gt 0) {
                        Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $pipeInfo.Node.Id -label "Pipeline"
                    } else {
                        Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $pipeInfo.Node.Id
                    }
                }
                $prevNodeRef.Value = $pipeInfo.Node
            }

            $modifiedText = $node.Extent.Text
            $allNestedSBs = Get-AllNestedScriptBlocks -ast $node
            $sortedAllSBs = $allNestedSBs | Sort-Object { $_.Extent.StartOffset } -Descending
            foreach ($sb in $sortedAllSBs) {
                if ($allScriptBlockReplacements.ContainsKey($sb)) {
                    $varName = $allScriptBlockReplacements[$sb]
                    $modifiedText = $modifiedText.Replace($sb.Extent.Text, "`$$varName")
                }
            }
            foreach ($r in $replacements) {
                $modifiedText = $modifiedText.Replace($r.Original, $r.Replacement)
            }

            $finalNode = Add-Node -cfg $cfg -type $node.GetType().Name -text $modifiedText -line $node.Extent.StartLineNumber -ast $node

            foreach ($r in $replacements) {
                Add-VarToNode -node $finalNode -varEntry $r.PipeVarEntry -accessType "Read"
                foreach ($varEntry in $r.LastElementVarEntries) {
                    Add-VarToNode -node $finalNode -varEntry $varEntry -accessType "Read"
                }
            }

            if ($null -ne $prevNodeRef.Value) {
                Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $finalNode.Id -label "Pipeline"
            }
            $prevNodeRef.Value = $finalNode
            return $false
        }

        $nestedScriptBlocks = Get-AllNestedScriptBlocks -ast $node
        if ($nestedScriptBlocks.Count -gt 0) {
            $deferredBlocks = @()
            $immediateBlocks = @()
            $invokeOnlyBlocks = @()
            $pipelineValueBlocks = @()

            foreach ($sb in $nestedScriptBlocks) {
                $execType = Get-ScriptBlockExecutionType -scriptBlockExprAst $sb
                switch ($execType) {
                    "Deferred" { $deferredBlocks += $sb }
                    "InvokeOnly" { $invokeOnlyBlocks += $sb }
                    "PipelineValue" { $pipelineValueBlocks += $sb }
                    default { $immediateBlocks += $sb }
                }
            }

            foreach ($sb in $pipelineValueBlocks) {
                if ($cfg.ProcessedScriptBlocks.ContainsKey($sb)) {
                    continue
                }

                $guid = [guid]::NewGuid().ToString("N").Substring(0, 8)
                $varName = "_block_$guid"

                $cfg.ProcessedScriptBlocks[$sb] = $varName

                Convert-ScriptBlockDefinition -cfg $cfg -scriptBlockExprAst $sb -blockName $varName
            }

            $hasStandaloneDeferred = $false
            foreach ($sb in $deferredBlocks) {
                if ($cfg.ProcessedScriptBlocks.ContainsKey($sb)) {
                    continue
                }

                $varName = $null
                $parent = $sb.Parent
                if ($parent -is [System.Management.Automation.Language.AssignmentStatementAst]) {
                    $left = $parent.Left
                    if ($left -is [System.Management.Automation.Language.VariableExpressionAst]) {
                        $varName = $left.VariablePath.UserPath
                    }
                }

                if ($null -eq $varName) {
                    $hasStandaloneDeferred = $true
                    $guid = [guid]::NewGuid().ToString("N").Substring(0, 8)
                    $varName = "_block_$guid"
                    $blockVarEntry = [PSCustomObject]@{ Name = $varName; Scope = [VarScope]::Unspecified }

                    $cfg.ProcessedScriptBlocks[$sb] = $varName

                    Convert-ScriptBlockDefinition -cfg $cfg -scriptBlockExprAst $sb -blockName $varName

                    $pipeNode = Add-Node -cfg $cfg -type "PipelineElement" -text "`$$varName" -line $sb.Extent.StartLineNumber -ast $sb
                    Add-VarToNode -node $pipeNode -varEntry $blockVarEntry -accessType "Read"
                    if ($null -ne $prevNodeRef.Value) {
                        Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $pipeNode.Id
                    }
                    $prevNodeRef.Value = $pipeNode
                } else {
                    $cfg.ProcessedScriptBlocks[$sb] = $varName
                    Convert-ScriptBlockDefinition -cfg $cfg -scriptBlockExprAst $sb -blockName $varName
                }
            }

            if ($hasStandaloneDeferred) {
                return $false
            }

            if ($invokeOnlyBlocks.Count -gt 0) {
                $scriptBlockExpansion = Expand-NestedScriptBlocks -cfg $cfg -ast $node -prevNodeRef $prevNodeRef -endNodeRef $endNodeRef -loopContext $loopContext -switchContext $switchContext
                if ($null -ne $scriptBlockExpansion -and $scriptBlockExpansion.InvokeOnlyExpanded) {
                    return $false
                }
            }

            if ($immediateBlocks.Count -gt 0) {
                $scriptBlockExpansion = Expand-NestedScriptBlocks -cfg $cfg -ast $node -prevNodeRef $prevNodeRef -endNodeRef $endNodeRef -loopContext $loopContext -switchContext $switchContext
                if ($null -ne $scriptBlockExpansion -and -not $scriptBlockExpansion.InvokeOnlyExpanded) {
                    $finalNode = Add-Node -cfg $cfg -type $node.GetType().Name -text $scriptBlockExpansion.ModifiedText -line $node.Extent.StartLineNumber -ast $node

                    foreach ($varEntry in $scriptBlockExpansion.ScriptBlockVarEntries) {
                        Add-VarToNode -node $finalNode -varEntry $varEntry -accessType "Read"
                    }

                    if ($null -ne $prevNodeRef.Value) {
                        Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $finalNode.Id -label "ScriptBlock"
                    }
                    $prevNodeRef.Value = $finalNode
                    return $false
                }
            }
        }

        $currentNode = Add-Node -cfg $cfg -type $node.GetType().Name -text $node.Extent.Text -line $node.Extent.StartLineNumber -ast $node
        if ($null -ne $prevNodeRef.Value) {
            Add-Edge -cfg $cfg -from $prevNodeRef.Value.Id -to $currentNode.Id
        }
        $prevNodeRef.Value = $currentNode
        return $false
    }
}

function Get-ScriptControlFlow {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ScriptPath
    )

    if (-not (Test-Path $ScriptPath)) {
        Write-Error "文件不存在: $ScriptPath"
        return $null
    }

    try {
        $ast = Get-Ast $ScriptPath
    }
    catch {
        Write-Error "解析失败: $_"
        return $null
    }

    $mycfg = @{
        Nodes = @()
        Edges = @()
        DefinedFunctions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        ProcessedScriptBlocks = @{}
        DefinedAliases = @{}
        SourcePath = $ScriptPath
        SourceText = if (Test-Path -LiteralPath $ScriptPath) { Get-Content -LiteralPath $ScriptPath -Raw } else { $null }
        FunctionTexts = @{}
    }

    $functionAsts = @($ast.FindAll({
                param($n)
                $n -is [System.Management.Automation.Language.FunctionDefinitionAst]
            }, $true))
    foreach ($funcAst in $functionAsts) {
        if ($null -eq $funcAst -or [string]::IsNullOrWhiteSpace([string]$funcAst.Name)) { continue }
        $mycfg.FunctionTexts[[string]$funcAst.Name] = [string]$funcAst.Extent.Text
    }

    Convert-AstNode -cfg $mycfg -node $ast -prevNodeRef ([ref]$null)

    return $mycfg
}

function Export-CfgToDot {
    param(
        [hashtable]$finalCFG,
        [string]$outputPath = "control_flow.dot",
        [int[]]$AppliedNodeIds = @()
    )

    function Format-DotLabel {
        param([string]$text)
        if ([string]::IsNullOrWhiteSpace($text)) { return "" }
        $cleaned = [System.Text.RegularExpressions.Regex]::Replace(
            $text,
            '[\x00-\x1F\x7F]',
            ''
        )
        $escaped = $cleaned.Replace('\', '\\').Replace('"', '\"')
        if ($escaped.Length -gt 50) {
            $truncated = $escaped.Substring(0, 47)
            $lastSpace = $truncated.LastIndexOf(' ')
            if ($lastSpace -gt 40) {
                $truncated = $truncated.Substring(0, $lastSpace)
            }
            "$truncated..."
        } else {
            $escaped
        }
    }

    function Format-DotHtmlText {
        param(
            [string]$text,
            [int]$MaxLen = 80
        )

        if ([string]::IsNullOrWhiteSpace($text)) { return "" }

        $cleaned = [System.Text.RegularExpressions.Regex]::Replace(
            $text,
            '[\x00-\x1F\x7F]',
            ''
        )

        $trimmed = $cleaned
        if ($trimmed.Length -gt $MaxLen) {
            $prefixLen = [Math]::Max(0, $MaxLen - 3)
            $truncated = $trimmed.Substring(0, $prefixLen)
            $lastSpace = $truncated.LastIndexOf(' ')
            if ($lastSpace -gt 20) {
                $truncated = $truncated.Substring(0, $lastSpace)
            }
            $trimmed = "$truncated..."
        }

        $escaped = $trimmed.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;')
        return $escaped
    }

    $appliedNodeSet = [System.Collections.Generic.HashSet[int]]::new()
    foreach ($nid in @($AppliedNodeIds)) {
        try {
            $null = $appliedNodeSet.Add([int]$nid)
        } catch {
        }
    }

    $nodeDefinitions = @()
    foreach ($node in $finalCFG.Nodes) {
        $shape = switch ($node.Type) {
            {$_ -in "Start", "End", "FuncStart", "FuncEnd"}   { "oval" }
            {$_ -in "Condition", "If", "ForEachCondition", "ProcessCondition"}    { "diamond" }
            {$_ -in "Merge"}                                  { "point" }
            default                                           { "box" }
        }

        $metaLines = @()

        if ($null -ne $node.DynamicInvoke) {
            $dynType = if ($node.DynamicInvoke -is [array]) {
                ($node.DynamicInvoke | ForEach-Object { $_.Type }) -join ", "
            } else {
                $node.DynamicInvoke.Type
            }
            $metaLines += "DYN: $(Format-DotHtmlText $dynType 70)"
        }

        $hasInvokes = ($node.Invokes.Functions.Count -gt 0) -or ($node.Invokes.ScriptBlocks.Count -gt 0)
        if ($hasInvokes) {
            $invokeLabels = @()
            if ($node.Invokes.Functions.Count -gt 0) {
                $funcList = $node.Invokes.Functions -join ", "
                $invokeLabels += "Func: $funcList"
            }
            if ($node.Invokes.ScriptBlocks.Count -gt 0) {
                $blockList = $node.Invokes.ScriptBlocks -join ", "
                $invokeLabels += "Block: $blockList"
            }
            $metaLines += "CALLS: $(Format-DotHtmlText ($invokeLabels -join '; ') 90)"
        }

        $pipeVarsWritten = @($node.VarsWritten | Where-Object { $_.Name -match '^_pipe_[a-f0-9]{8}$' })
        if ($pipeVarsWritten.Count -gt 0) {
            $pipeVarList = ($pipeVarsWritten | ForEach-Object { "`$$($_.Name)" }) -join ", "
            $metaLines += "PIPE OUT: $(Format-DotHtmlText $pipeVarList 90)"
        }

        if ($node.Resolvables.Count -gt 0) {
            $metaLines += "RESOLVABLE: $($node.Resolvables.Count)"
        }

        if ($node.PSObject.Properties.Match('PipeCmdlet').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($node.PipeCmdlet)) {
            $cmdletName = $node.PipeCmdlet
            if ($node.PSObject.Properties.Match('PipeCmdletName').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($node.PipeCmdletName)) {
                $cmdletName = $node.PipeCmdletName
            }
            $metaLines += "PIPE CMDLET: $(Format-DotHtmlText $cmdletName 80)"
        }

        if ($node.AliasesUsed.Count -gt 0) {
            $aliasList = ($node.AliasesUsed | ForEach-Object { "$($_.Name)->$($_.Target)" }) -join ", "
            $metaLines += "ALIAS: $(Format-DotHtmlText $aliasList 90)"
        }

        $idTypeText = Format-DotHtmlText ("Id $($node.Id) | $($node.Type)") 80
        $codeText = Format-DotHtmlText $node.Text 90
        if ([string]::IsNullOrWhiteSpace($codeText)) { $codeText = "(empty)" }

        $labelLines = @(
            "<FONT POINT-SIZE=`"9`" COLOR=`"#666666`">$idTypeText</FONT>",
            "<B><FONT POINT-SIZE=`"16`">$codeText</FONT></B>"
        )
        foreach ($meta in $metaLines) {
            $labelLines += "<FONT POINT-SIZE=`"10`" COLOR=`"#333333`">$meta</FONT>"
        }
        $htmlLabel = "<$($labelLines -join '<BR ALIGN=`"LEFT`"/>')>"

        $isAppliedNode = $false
        try {
            $isAppliedNode = $appliedNodeSet.Contains([int]$node.Id)
        } catch {
            $isAppliedNode = $false
        }

        $style = if ($isAppliedNode) {
            'style="filled,rounded", fillcolor="#fff3cc", color="#cc9900", penwidth=2'
        } else {
            'style="filled,rounded", fillcolor="#ffffff", color="#333333", penwidth=1'
        }

        $nodeDefinitions += "    $($node.Id) [label=$htmlLabel, shape=$shape, $style];"
    }

    $edgeDefinitions = @()
    foreach ($edge in $finalCFG.Edges) {
        $line = "    $($edge.From) -> $($edge.To)"
        if (-not [string]::IsNullOrWhiteSpace($edge.Label)) {
            $line += " [label=`"$(Format-DotLabel $edge.Label)`"]"
        }
        $edgeDefinitions += "$line;"
    }

$dotContent = @"
digraph G {
    rankdir=TB;
    node [
        fontname="Consolas"
        shape=box
        width=0
        height=0
        margin="0.2,0.1"
        fontsize=10
    ];
    edge [fontname="Arial", arrowhead=vee, fontsize=9];

    // Nodes
$($nodeDefinitions -join "`n")

    // Edges
$($edgeDefinitions -join "`n")
}
"@

    try {
        $ascii = [System.Text.Encoding]::ASCII
        [System.IO.File]::WriteAllText($outputPath, $dotContent, $ascii)
        Write-Host ("DOT文件已生成: {0}" -f $outputPath) -ForegroundColor Green

        $pngPath = [System.IO.Path]::ChangeExtension($outputPath, ".png")
        $dotExe = Get-Command dot -ErrorAction Stop | Select-Object -ExpandProperty Source
        & $dotExe -Tpng $outputPath -o $pngPath 2>&1 | Out-Null

        if (Test-Path $pngPath) {
            Write-Host ("流程图已生成: {0}" -f $pngPath) -ForegroundColor Green
            return $pngPath
        } else {
            Write-Warning ("生成失败，请手动执行: {0} -Tpng `"{1}`" -o `"{2}`"" -f $dotExe, $outputPath, $pngPath)
        }
    } 
    catch 
    {
        Write-Warning "致命错误: $_"
        $dotContent | Out-Host
    }
}

function New-RuntimeSubgraph {
    param(
        [hashtable]$cfg,
        [string]$Code,
        [string]$BlockNamePrefix = "_dyn_"
    )

    $initialNodeCount = if ($null -ne $cfg.Nodes) { @($cfg.Nodes).Count } else { 0 }
    $initialEdgeCount = if ($null -ne $cfg.Edges) { @($cfg.Edges).Count } else { 0 }

    $errors = $null
    $tokens = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($Code, [ref]$tokens, [ref]$errors)

    if ($errors -and $errors.Count -gt 0) {
        return @{
            Success = $false
            Error = $errors[0].Message
        }
    }

    $guid = [guid]::NewGuid().ToString("N").Substring(0, 8)
    $blockName = "$BlockNamePrefix$guid"

    $blockStart = Add-Node -cfg $cfg -type "BlockStart" -text "DynamicBlock $blockName" -line 0 -ast $null
    $blockStart | Add-Member -NotePropertyName "ScriptBlockText" -NotePropertyValue "{$Code}" -Force
    $hasProcessBlock = ($null -ne $ast.ProcessBlock -and $ast.ProcessBlock.Statements.Count -gt 0)
    $blockStart | Add-Member -NotePropertyName "HasProcessBlock" -NotePropertyValue $hasProcessBlock -Force
    $blockStart | Add-Member -NotePropertyName "ProcessInputVar" -NotePropertyValue "__proc_input" -Force
    $blockEnd = Add-Node -cfg $cfg -type "BlockEnd" -text "End DynamicBlock $blockName" -line 0 -ast $null

    $prevNode = $blockStart
    $prev = [ref]$prevNode
    $endRef = [ref]$blockEnd

    $null = Convert-ScriptBlockBody -cfg $cfg -scriptBlockAst $ast -prevNodeRef $prev -endNodeRef $endRef -paramNodeType "BlockParams"

    if ($null -ne $prev.Value -and $prev.Value.Id -ne $blockEnd.Id) {
        $lastType = $prev.Value.Type
        if ($lastType -notin @("Return", "Exit", "Throw", "Break", "Continue", "End")) {
            Add-Edge -cfg $cfg -from $prev.Value.Id -to $blockEnd.Id
        }
    }

    $allNodes = if ($null -ne $cfg.Nodes) { @($cfg.Nodes) } else { @() }
    $allEdges = if ($null -ne $cfg.Edges) { @($cfg.Edges) } else { @() }
    $newNodes = if ($allNodes.Count -gt $initialNodeCount) { @($allNodes | Select-Object -Skip $initialNodeCount) } else { @() }
    $newEdges = if ($allEdges.Count -gt $initialEdgeCount) { @($allEdges | Select-Object -Skip $initialEdgeCount) } else { @() }
    foreach ($node in $newNodes) {
        $node | Add-Member -NotePropertyName "RuntimeGenerated" -NotePropertyValue $true -Force
        $node | Add-Member -NotePropertyName "RuntimeBlockName" -NotePropertyValue $blockName -Force
    }
    if (Get-Command -Name Sync-CFGExecutionIndexesIncremental -ErrorAction SilentlyContinue) {
        try {
            $null = Sync-CFGExecutionIndexesIncremental -CFG $cfg -NewNodes $newNodes -NewEdges $newEdges
        }
        catch {
            if (Get-Command -Name Ensure-CFGExecutionIndexes -ErrorAction SilentlyContinue) {
                try {
                    $null = Ensure-CFGExecutionIndexes -CFG $cfg
                }
                catch {
                }
            }
        }
    }

    return @{
        Success = $true
        BlockName = $blockName
        BlockStartId = $blockStart.Id
        BlockEndId = $blockEnd.Id
        NewNodeIds = @($newNodes | ForEach-Object { [int]$_.Id })
    }
}


# $scriptPath = Join-Path $PSScriptRoot 'in/in.ps1'
# $finalCFG = Get-ScriptControlFlow -ScriptPath $scriptPath
# $finalCFG.Nodes | Select-Object Id, Type, @{
#     Name="Text"
#     Expression={
#         $text = $_.Text
#         if ($text.Length -gt 20) { $text.Substring(0, 20) + "..." } 
#         else { $text }
#     }
# }, Line, Ast | Format-Table -AutoSize
# $finalCFG.Edges | Format-Table -AutoSize
# # $finalCFG.Nodes | Out-GridView -Title 'CFG Nodes'
# $dotPath = Join-Path $PSScriptRoot 'in/in.dot'
# Export-CfgToDot -finalCFG $finalCFG -outputPath $dotPath
