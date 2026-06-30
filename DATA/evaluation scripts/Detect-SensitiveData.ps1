param(
    [Parameter(Mandatory=$true)]
    [string]$DatasetPath,

    [Parameter(Mandatory=$true)]
    [string]$OutputPath,

    [int]$MaxFileSizeMB = 50,

    [ValidateRange(1, 256)]
    [int]$ThrottleLimit = 16,

    [ValidateRange(1, 4096)]
    [int]$ChunkCount = 128,

    [switch]$ForceRescan,

    [ValidateRange(50, 60000)]
    [int]$ProgressRefreshMs = 100
)

$Script:AnalyzerVersion = 'Detect-SensitiveData'

# Compile regex patterns
$IPRegex = [regex]::new(
    '(?<!\d)(?:\d{1,3}\.){3}\d{1,3}(?!\d)(?=.*\d{2})',
    'Compiled'
)

$URLRegex = [regex]::new(
    '(?i)(?:https?|ftp)://[a-z0-9][-a-z0-9.]*[a-z0-9](?::[0-9]+)?(?:/[^\s"''<>()]*)?',
    'Compiled'
)

$FilePathRegex = [regex]::new(
    '(?i)(?:[A-Za-z]:\\|\$env:[a-z_]+\\|%[a-z0-9_]+%\\)[^\\/:*?"<>|\r\n]{1,}(?:\\[^\\/:*?"<>|\r\n]{1,})*',
    'Compiled'
)

$VariablePathRegex = [regex]::new(
    '(?i)\$[a-z_][a-z0-9_]*(?:\\[^\\/:*?"<>|\r\n;]+)+',
    'Compiled'
)

$RegKeyRegex = [regex]::new(
    '(?i)(?:^|[\s=:(,])((?:HKLM|HKCU|HKCR|HKU|HKCC|HKEY_LOCAL_MACHINE|HKEY_CURRENT_USER|HKEY_CLASSES_ROOT|HKEY_USERS|HKEY_CURRENT_CONFIG):?\\[a-z0-9_ .\-(){}]+)',
    'Compiled'
)

$RawExcludedPathPatterns = @(
    '(?i)^[A-Za-z]:\\Windows\\System32\\WindowsPowerShell\\',
    '(?i)^[A-Za-z]:\\Windows\\SysWOW64\\WindowsPowerShell\\',
    '(?i)^[A-Za-z]:\\Windows\\Sysnative\\WindowsPowerShell\\',
    '(?i)^[A-Za-z]:\\Program Files\\PowerShell\\',
    '(?i)^[A-Za-z]:\\Program Files \(x86\)\\PowerShell\\',
    '^[A-Za-z]:\\$'
)

$FairExcludedPathPatterns = @(
    '(?i)^%TEMP%\\PowerPeeler-[^\\]+\\process\\[^\\]+\\runtime\\sandbox(?:\\|$)',
    '(?i)^%TEMP%\\PowerPeeler-[^\\]+\\runtime\\sandbox(?:\\|$)',
    '(?i)^%WINDIR%\\System32\\WindowsPowerShell\\',
    '(?i)^%WINDIR%\\SysWOW64\\WindowsPowerShell\\',
    '(?i)^%WINDIR%\\Sysnative\\WindowsPowerShell\\',
    '(?i)^[A-Za-z]:\\Windows\\System32\\WindowsPowerShell\\',
    '(?i)^[A-Za-z]:\\Windows\\SysWOW64\\WindowsPowerShell\\',
    '(?i)^[A-Za-z]:\\Windows\\Sysnative\\WindowsPowerShell\\',
    '^(?:[A-Za-z]:|%[A-Z0-9_]+%)\\?$'
)

$CanonicalEnvRoots = [ordered]@{
    'TEMP' = 'C:\Users\<USER>\AppData\Local\Temp'
    'TMP' = 'C:\Users\<USER>\AppData\Local\Temp'
    'LOCALAPPDATA' = 'C:\Users\<USER>\AppData\Local'
    'APPDATA' = 'C:\Users\<USER>\AppData\Roaming'
    'PUBLIC' = 'C:\Users\Public'
    'USERPROFILE' = 'C:\Users\<USER>'
    'PROGRAMDATA' = 'C:\ProgramData'
    'WINDIR' = 'C:\Windows'
    'SYSTEMROOT' = 'C:\Windows'
}

$CanonicalPathRoots = @(
    @{ Token = '%TEMP%'; Root = 'C:\Users\<USER>\AppData\Local\Temp' }
    @{ Token = '%LOCALAPPDATA%'; Root = 'C:\Users\<USER>\AppData\Local' }
    @{ Token = '%APPDATA%'; Root = 'C:\Users\<USER>\AppData\Roaming' }
    @{ Token = '%PUBLIC%'; Root = 'C:\Users\Public' }
    @{ Token = '%PROGRAMDATA%'; Root = 'C:\ProgramData' }
    @{ Token = '%USERPROFILE%'; Root = 'C:\Users\<USER>' }
    @{ Token = '%WINDIR%'; Root = 'C:\Windows' }
)

function Get-CanonicalEnvRoot {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $null
    }

    $key = $Name.ToUpperInvariant()
    if ($CanonicalEnvRoots.Contains($key)) {
        return $CanonicalEnvRoots[$key]
    }

    return $null
}

function Trim-PowerShellParameterTailFromPathCandidate {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $Value
    }

    if ($Value -notmatch '^(?i)(?:[A-Za-z]:\\|\$env:[a-z_]+\\|%[a-z0-9_]+%\\)') {
        return $Value
    }

    $tailMatch = [regex]::Match(
        $Value,
        '(?i)(?<=\.[a-z0-9]{1,6})(?<boundary>\s+)-(?<name>[A-Za-z][A-Za-z0-9-]*)(?=\s|$)'
    )

    if (-not $tailMatch.Success) {
        return $Value
    }

    return $Value.Substring(0, $tailMatch.Index).TrimEnd()
}

function Trim-PathCandidate {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $trimmed = $Value.Trim()
    $trimmed = $trimmed -replace "^[\s'`"(\[{,;]+", ''
    $trimmed = $trimmed -replace "[\s'`"\)\]},;]+$", ''
    $trimmed = $trimmed -replace "(?i)(?<=\.[a-z0-9]{1,6})['`"]\)?\s+-.*$", ''
    $trimmed = $trimmed -replace '(?i)(?<=\.[a-z0-9]{1,6})\)\s+-.*$', ''
    $trimmed = Trim-PowerShellParameterTailFromPathCandidate -Value $trimmed
    $trimmed = $trimmed -replace '\\{2,}', '\'

    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        return $null
    }

    return $trimmed
}

function Resolve-DotSegments {
    param([string]$Path)

    if ($Path -notmatch '^(?<root>[A-Za-z]:)(?<rest>\\.*)?$') {
        return $Path
    }

    $root = $Matches.root
    $rest = $Matches.rest
    $segments = [System.Collections.Generic.List[string]]::new()

    if (-not [string]::IsNullOrEmpty($rest)) {
        foreach ($segment in ($rest.TrimStart('\') -split '\\')) {
            if ([string]::IsNullOrWhiteSpace($segment) -or $segment -eq '.') {
                continue
            }

            if ($segment -eq '..') {
                if ($segments.Count -gt 0) {
                    $segments.RemoveAt($segments.Count - 1)
                }

                continue
            }

            $segments.Add($segment)
        }
    }

    if ($segments.Count -eq 0) {
        return "$root\"
    }

    return "$root\{0}" -f ($segments -join '\')
}

function Convert-ToCanonicalAbsolutePath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }

    $normalized = $Path -replace '/', '\'

    $normalized = [regex]::Replace(
        $normalized,
        '(?i)^\$env:([a-z_]+)',
        {
            param($match)
            $resolved = Get-CanonicalEnvRoot -Name $match.Groups[1].Value
            if ($resolved) { return $resolved }
            return $match.Value
        }
    )

    $normalized = [regex]::Replace(
        $normalized,
        '(?i)^%([a-z0-9_]+)%',
        {
            param($match)
            $resolved = Get-CanonicalEnvRoot -Name $match.Groups[1].Value
            if ($resolved) { return $resolved }
            return $match.Value
        }
    )

    if ($normalized -match '(?i)^[A-Za-z]:\\Users\\[^\\]+\\AppData\\Local\\Temp(?=\\|$)') {
        $normalized = $normalized -replace '(?i)^[A-Za-z]:\\Users\\[^\\]+\\AppData\\Local\\Temp(?=\\|$)', 'C:\Users\<USER>\AppData\Local\Temp'
    } elseif ($normalized -match '(?i)^[A-Za-z]:\\Users\\[^\\]+\\AppData\\Local(?=\\|$)') {
        $normalized = $normalized -replace '(?i)^[A-Za-z]:\\Users\\[^\\]+\\AppData\\Local(?=\\|$)', 'C:\Users\<USER>\AppData\Local'
    } elseif ($normalized -match '(?i)^[A-Za-z]:\\Users\\[^\\]+\\AppData\\Roaming(?=\\|$)') {
        $normalized = $normalized -replace '(?i)^[A-Za-z]:\\Users\\[^\\]+\\AppData\\Roaming(?=\\|$)', 'C:\Users\<USER>\AppData\Roaming'
    } elseif ($normalized -match '(?i)^[A-Za-z]:\\Users\\Public(?=\\|$)') {
        $normalized = $normalized -replace '(?i)^[A-Za-z]:\\Users\\Public(?=\\|$)', 'C:\Users\Public'
    } elseif ($normalized -match '(?i)^[A-Za-z]:\\ProgramData(?=\\|$)') {
        $normalized = $normalized -replace '(?i)^[A-Za-z]:\\ProgramData(?=\\|$)', 'C:\ProgramData'
    } elseif ($normalized -match '(?i)^[A-Za-z]:\\Windows(?=\\|$)') {
        $normalized = $normalized -replace '(?i)^[A-Za-z]:\\Windows(?=\\|$)', 'C:\Windows'
    } elseif ($normalized -match '(?i)^[A-Za-z]:\\Users\\[^\\]+(?=\\|$)') {
        $normalized = $normalized -replace '(?i)^[A-Za-z]:\\Users\\[^\\]+(?=\\|$)', 'C:\Users\<USER>'
    }

    return (Resolve-DotSegments -Path $normalized)
}

function Convert-ToFairPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }

    $normalized = Resolve-DotSegments -Path $Path

    foreach ($mapping in $CanonicalPathRoots) {
        $pattern = '^(?i){0}(?=\\|$)' -f [regex]::Escape($mapping.Root)
        if ($normalized -match $pattern) {
            $normalized = [regex]::Replace($normalized, $pattern, $mapping.Token)
            break
        }
    }

    return $normalized
}

function Test-RawSensitiveFilePath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or $Path.Length -lt 10) {
        return $false
    }

    foreach ($pattern in $RawExcludedPathPatterns) {
        if ($Path -match $pattern) {
            return $false
        }
    }

    if ($Path -match '^[A-Za-z]:\\[^\\]{1,2}$') {
        return $false
    }

    return $true
}

function Test-FairSensitiveFilePath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or $Path.Length -lt 8) {
        return $false
    }

    if ($Path -match '(?i)\$[a-z_][a-z0-9_]*') {
        return $false
    }

    if ($Path -notmatch '^(?:[A-Za-z]:|%[A-Z0-9_]+%)\\') {
        return $false
    }

    foreach ($pattern in $FairExcludedPathPatterns) {
        if ($Path -match $pattern) {
            return $false
        }
    }

    if ($Path -match '^(?:[A-Za-z]:|%[A-Z0-9_]+%)\\[^\\]{1,2}$') {
        return $false
    }

    return $true
}

function Remove-StringWrapper {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $Value
    }

    $text = $Value.Trim()

    while ($true) {
        $changed = $false

        if ($text -match '^\(\[string\](?<inner>.*)\)$') {
            $text = $Matches.inner.Trim()
            $changed = $true
        } elseif ($text -match '^\((?<inner>.*)\)$') {
            $inner = $Matches.inner.Trim()
            if ($inner -notmatch '^[a-z0-9_.-]+\s') {
                $text = $inner
                $changed = $true
            }
        }

        if (-not $changed) {
            break
        }
    }

    return $text
}

function Split-ConcatenationTerms {
    param([string]$Expression)

    $terms = [System.Collections.Generic.List[string]]::new()
    $current = [System.Text.StringBuilder]::new()
    $inSingleQuote = $false
    $inDoubleQuote = $false

    foreach ($char in $Expression.ToCharArray()) {
        switch ($char) {
            "'" {
                if (-not $inDoubleQuote) {
                    $inSingleQuote = -not $inSingleQuote
                }

                [void]$current.Append($char)
                continue
            }
            '"' {
                if (-not $inSingleQuote) {
                    $inDoubleQuote = -not $inDoubleQuote
                }

                [void]$current.Append($char)
                continue
            }
            '+' {
                if (-not $inSingleQuote -and -not $inDoubleQuote) {
                    $term = $current.ToString().Trim()
                    if ($term) {
                        $terms.Add($term)
                    }

                    [void]$current.Clear()
                    continue
                }
            }
        }

        [void]$current.Append($char)
    }

    $lastTerm = $current.ToString().Trim()
    if ($lastTerm) {
        $terms.Add($lastTerm)
    }

    return @($terms)
}

function Split-PseudoStatements {
    param([string]$Content)

    $statements = [System.Collections.Generic.List[string]]::new()
    $current = [System.Text.StringBuilder]::new()
    $inSingleQuote = $false
    $inDoubleQuote = $false

    foreach ($char in $Content.ToCharArray()) {
        switch ($char) {
            "'" {
                if (-not $inDoubleQuote) {
                    $inSingleQuote = -not $inSingleQuote
                }

                [void]$current.Append($char)
                continue
            }
            '"' {
                if (-not $inSingleQuote) {
                    $inDoubleQuote = -not $inDoubleQuote
                }

                [void]$current.Append($char)
                continue
            }
            ';' {
                if (-not $inSingleQuote -and -not $inDoubleQuote) {
                    $statement = $current.ToString().Trim()
                    if ($statement) {
                        $statements.Add($statement)
                    }

                    [void]$current.Clear()
                    continue
                }
            }
            "`n" {
                if (-not $inSingleQuote -and -not $inDoubleQuote) {
                    $statement = $current.ToString().Trim()
                    if ($statement) {
                        $statements.Add($statement)
                    }

                    [void]$current.Clear()
                    continue
                }
            }
            "`r" {
                continue
            }
        }

        [void]$current.Append($char)
    }

    $lastStatement = $current.ToString().Trim()
    if ($lastStatement) {
        $statements.Add($lastStatement)
    }

    return @($statements)
}

function Expand-InterpolatedToken {
    param(
        [string]$Text,
        [hashtable]$VariableMap
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $Text
    }

    $expanded = [regex]::Replace(
        $Text,
        '(?i)\$env:([a-z_]+)',
        {
            param($match)
            $resolved = Get-CanonicalEnvRoot -Name $match.Groups[1].Value
            if ($resolved) { return $resolved }
            return $match.Value
        }
    )

    $expanded = [regex]::Replace(
        $expanded,
        '(?i)\$([a-z_][a-z0-9_]*)',
        {
            param($match)
            $name = $match.Groups[1].Value.ToLowerInvariant()
            if ($VariableMap.ContainsKey($name)) {
                return $VariableMap[$name]
            }

            return $match.Value
        }
    )

    return $expanded
}

function Resolve-ExpressionToken {
    param(
        [string]$Token,
        [hashtable]$VariableMap
    )

    if ([string]::IsNullOrWhiteSpace($Token)) {
        return $null
    }

    $value = Remove-StringWrapper -Value $Token

    if ($value -match "^'(.*)'$") {
        return $Matches[1]
    }

    if ($value -match '^"(.*)"$') {
        return (Expand-InterpolatedToken -Text $Matches[1] -VariableMap $VariableMap)
    }

    if ($value -match '(?i)^\$env:([a-z_]+)$') {
        return (Get-CanonicalEnvRoot -Name $Matches[1])
    }

    if ($value -match '(?i)^\$([a-z_][a-z0-9_]*)$') {
        $name = $Matches[1].ToLowerInvariant()
        if ($VariableMap.ContainsKey($name)) {
            return $VariableMap[$name]
        }

        return $null
    }

    if ($value -match '(?i)^\$([a-z_][a-z0-9_]*)(\\.+)$') {
        $name = $Matches[1].ToLowerInvariant()
        if ($VariableMap.ContainsKey($name)) {
            return '{0}{1}' -f $VariableMap[$name], $Matches[2]
        }

        return $null
    }

    if ($value -match '^(?:[A-Za-z]:\\|%[A-Za-z0-9_]+%\\)') {
        return $value
    }

    return $null
}

function Resolve-ExpressionToString {
    param(
        [string]$Expression,
        [hashtable]$VariableMap
    )

    if ([string]::IsNullOrWhiteSpace($Expression)) {
        return $null
    }

    $expression = Remove-StringWrapper -Value $Expression

    if ($expression -match '(?i)^\$([a-z_][a-z0-9_]*)\s*\+\s*''(.*)''$') {
        $name = $Matches[1].ToLowerInvariant()
        if ($VariableMap.ContainsKey($name)) {
            return '{0}{1}' -f $VariableMap[$name], $Matches[2]
        }

        return $null
    }

    if ($expression -match '(?i)^\$([a-z_][a-z0-9_]*)\s*\+\s*"(.*)"$') {
        $name = $Matches[1].ToLowerInvariant()
        if ($VariableMap.ContainsKey($name)) {
            $suffix = Expand-InterpolatedToken -Text $Matches[2] -VariableMap $VariableMap
            return '{0}{1}' -f $VariableMap[$name], $suffix
        }

        return $null
    }

    $terms = Split-ConcatenationTerms -Expression $expression
    $pieces = [System.Collections.Generic.List[string]]::new()

    foreach ($term in $terms) {
        $piece = Resolve-ExpressionToken -Token $term -VariableMap $VariableMap
        if ($null -eq $piece) {
            return $null
        }

        $pieces.Add($piece)
    }

    if ($pieces.Count -eq 0) {
        return $null
    }

    return ($pieces -join '')
}

function Resolve-VariableAssignments {
    param([string]$Content)

    $variableMap = @{}
    $statements = Split-PseudoStatements -Content $Content

    for ($pass = 0; $pass -lt 4; $pass++) {
        $updated = $false

        foreach ($statement in $statements) {
            if ($statement -match '(?i)^\s*(?:[{}]\s*)*\$(?<name>[a-z_][a-z0-9_]*)\s*=\s*(?<expr>.+?)\s*$') {
                $name = $Matches.name.ToLowerInvariant()
                $resolved = Resolve-ExpressionToString -Expression $Matches.expr -VariableMap $variableMap

                if ($resolved -and (-not $variableMap.ContainsKey($name) -or $variableMap[$name] -ne $resolved)) {
                    $variableMap[$name] = $resolved
                    $updated = $true
                }
            }
        }

        if (-not $updated) {
            break
        }
    }

    return $variableMap
}

function Get-VariableDerivedPaths {
    param(
        [string]$Content,
        [hashtable]$VariableMap
    )

    $candidates = [System.Collections.Generic.List[string]]::new()

    foreach ($value in $VariableMap.Values) {
        if ($value) {
            $candidates.Add($value)
        }
    }

    foreach ($match in $VariablePathRegex.Matches($Content)) {
        $resolved = Resolve-ExpressionToken -Token $match.Value -VariableMap $VariableMap
        if ($resolved) {
            $candidates.Add($resolved)
        }
    }

    foreach ($match in [regex]::Matches($Content, '(?i)\$([a-z_][a-z0-9_]*)\s*\+\s*''([^'']+)''')) {
        $name = $match.Groups[1].Value.ToLowerInvariant()
        if ($VariableMap.ContainsKey($name)) {
            $candidates.Add(('{0}{1}' -f $VariableMap[$name], $match.Groups[2].Value))
        }
    }

    foreach ($match in [regex]::Matches($Content, '(?i)\$([a-z_][a-z0-9_]*)\s*\+\s*"([^"]+)"')) {
        $name = $match.Groups[1].Value.ToLowerInvariant()
        if ($VariableMap.ContainsKey($name)) {
            $suffix = Expand-InterpolatedToken -Text $match.Groups[2].Value -VariableMap $VariableMap
            $candidates.Add(('{0}{1}' -f $VariableMap[$name], $suffix))
        }
    }

    return @($candidates)
}

function Normalize-FairFilePath {
    param([string]$Path)

    $trimmed = Trim-PathCandidate -Value $Path
    if (-not $trimmed) {
        return $null
    }

    $canonicalAbsolute = Convert-ToCanonicalAbsolutePath -Path $trimmed
    if (-not $canonicalAbsolute) {
        return $null
    }

    if ($canonicalAbsolute -match '(?i)\$[a-z_][a-z0-9_]*') {
        return $null
    }

    return (Convert-ToFairPath -Path $canonicalAbsolute)
}

function Find-SensitiveData {
    param(
        [string]$Content,
        [string]$FilePath,
        [long]$FileSize
    )

    $result = @{
        FileName = Split-Path $FilePath -Leaf
        FileSize = $FileSize
        IP = @{ Total = 0; Unique = 0; Values = @() }
        URL = @{ Total = 0; Unique = 0; Values = @() }
        FilePath = @{ Total = 0; Unique = 0; Values = @() }
        FilePathRaw = @{ Total = 0; Unique = 0; Values = @() }
        RegKey = @{ Total = 0; Unique = 0; Values = @() }
    }

    $ipMatches = $IPRegex.Matches($Content)
    $filteredIPs = @($ipMatches | ForEach-Object { $_.Value } | Where-Object { Test-ValidIP $_ })
    $result.IP.Total = $filteredIPs.Count
    $result.IP.Values = $filteredIPs
    $result.IP.Unique = ($filteredIPs | Select-Object -Unique).Count

    $urlMatches = $URLRegex.Matches($Content)
    $result.URL.Total = $urlMatches.Count
    $result.URL.Values = @($urlMatches | ForEach-Object { $_.Value })
    $result.URL.Unique = ($result.URL.Values | Select-Object -Unique).Count

    $rawPathMatches = @(
        $FilePathRegex.Matches($Content) |
        ForEach-Object { Trim-PathCandidate -Value $_.Value } |
        Where-Object { $_ -and (Test-RawSensitiveFilePath $_) }
    )
    $result.FilePathRaw.Total = $rawPathMatches.Count
    $result.FilePathRaw.Values = $rawPathMatches
    $result.FilePathRaw.Unique = ($rawPathMatches | Select-Object -Unique).Count

    $variableMap = Resolve-VariableAssignments -Content $Content
    $derivedPathMatches = Get-VariableDerivedPaths -Content $Content -VariableMap $variableMap
    $fairCandidates = @($rawPathMatches + $derivedPathMatches)
    $fairFilePaths = @(
        $fairCandidates |
        ForEach-Object { Normalize-FairFilePath -Path $_ } |
        Where-Object { $_ -and (Test-FairSensitiveFilePath $_) }
    )
    $result.FilePath.Total = $fairFilePaths.Count
    $result.FilePath.Values = $fairFilePaths
    $result.FilePath.Unique = ($fairFilePaths | Select-Object -Unique).Count

    $regKeyMatches = $RegKeyRegex.Matches($Content)
    $filteredRegKeys = @($regKeyMatches | ForEach-Object { $_.Value } | Where-Object { Test-ValidRegKey $_ })
    $result.RegKey.Total = $filteredRegKeys.Count
    $result.RegKey.Values = $filteredRegKeys
    $result.RegKey.Unique = ($filteredRegKeys | Select-Object -Unique).Count

    return $result
}

function Test-ValidIP {
    param([string]$IP)

    if ($IP -eq '0.0.0.0' -or $IP -eq '255.255.255.255') {
        return $false
    }

    if ($IP -match '^[0-2]\.[0-9]\.[0-9]\.[0-9]$') {
        return $false
    }

    return $true
}

function Test-ValidRegKey {
    param([string]$RegKey)

    if ($RegKey -notmatch '\\[^\\]{2,}') {
        return $false
    }

    if ($RegKey.Length -lt 10) {
        return $false
    }

    return $true
}

function New-ScanChunkResult {
    return @{
        ProcessedFiles = 0
        FailedFiles = 0
        SkippedFiles = 0
        Summary = @{
            IP = @{ TotalOccurrences = 0; FilesContaining = 0 }
            URL = @{ TotalOccurrences = 0; FilesContaining = 0 }
            FilePath = @{ TotalOccurrences = 0; FilesContaining = 0 }
            FilePathRaw = @{ TotalOccurrences = 0; FilesContaining = 0 }
            RegKey = @{ TotalOccurrences = 0; FilesContaining = 0 }
        }
        FileDetails = @()
        Errors = @()
        CollectedValues = @{
            IP = @()
            URL = @()
            FilePath = @()
            FilePathRaw = @()
            RegKey = @()
        }
    }
}

function New-ScanResults {
    param([int]$TotalFiles)

    return @{
        AnalyzerVersion = $Script:AnalyzerVersion
        FilePathMode = 'fair_canonical_with_artifact_filter_and_light_variable_resolution'
        TotalFiles = $TotalFiles
        ProcessedFiles = 0
        FailedFiles = 0
        SkippedFiles = 0
        Summary = @{
            IP = @{ TotalOccurrences = 0; UniqueValues = 0; FilesContaining = 0 }
            URL = @{ TotalOccurrences = 0; UniqueValues = 0; FilesContaining = 0 }
            FilePath = @{ TotalOccurrences = 0; UniqueValues = 0; FilesContaining = 0 }
            FilePathRaw = @{ TotalOccurrences = 0; UniqueValues = 0; FilesContaining = 0 }
            RegKey = @{ TotalOccurrences = 0; UniqueValues = 0; FilesContaining = 0 }
        }
        FileDetails = @()
        Errors = @()
        CollectedValues = @{
            IP = @()
            URL = @()
            FilePath = @()
            FilePathRaw = @()
            RegKey = @()
        }
    }
}

function Add-FileResultToScanResult {
    param(
        $ScanResult,
        $FileResult
    )

    $ScanResult.FileDetails += $FileResult
    $ScanResult.ProcessedFiles++

    $ScanResult.Summary.IP.TotalOccurrences += $FileResult.IP.Total
    $ScanResult.Summary.URL.TotalOccurrences += $FileResult.URL.Total
    $ScanResult.Summary.FilePath.TotalOccurrences += $FileResult.FilePath.Total
    $ScanResult.Summary.FilePathRaw.TotalOccurrences += $FileResult.FilePathRaw.Total
    $ScanResult.Summary.RegKey.TotalOccurrences += $FileResult.RegKey.Total

    if ($FileResult.IP.Total -gt 0) { $ScanResult.Summary.IP.FilesContaining++ }
    if ($FileResult.URL.Total -gt 0) { $ScanResult.Summary.URL.FilesContaining++ }
    if ($FileResult.FilePath.Total -gt 0) { $ScanResult.Summary.FilePath.FilesContaining++ }
    if ($FileResult.FilePathRaw.Total -gt 0) { $ScanResult.Summary.FilePathRaw.FilesContaining++ }
    if ($FileResult.RegKey.Total -gt 0) { $ScanResult.Summary.RegKey.FilesContaining++ }

    $ScanResult.CollectedValues.IP += $FileResult.IP.Values
    $ScanResult.CollectedValues.URL += $FileResult.URL.Values
    $ScanResult.CollectedValues.FilePath += $FileResult.FilePath.Values
    $ScanResult.CollectedValues.FilePathRaw += $FileResult.FilePathRaw.Values
    $ScanResult.CollectedValues.RegKey += $FileResult.RegKey.Values
}

function Read-FileContentWithFallback {
    param([string]$Path)

    $encodings = @(
        [System.Text.Encoding]::UTF8,
        [System.Text.Encoding]::Unicode,
        [System.Text.Encoding]::ASCII,
        [System.Text.Encoding]::Default
    )

    foreach ($encoding in $encodings) {
        try {
            $content = [System.IO.File]::ReadAllText($Path, $encoding)
            if ($content) {
                return $content
            }
        } catch {
            continue
        }
    }

    return $null
}

function Scan-FileChunk {
    param(
        [object[]]$Files,
        [long]$MaxBytes,
        [int]$ChunkId = -1,
        [string]$ProgressPath
    )

    $chunkResult = New-ScanChunkResult

    foreach ($file in $Files) {
        try {
            Write-ChunkProgressEvent -Path $ProgressPath -EventType 'start' -FileName $file.Name -ChunkId $ChunkId -Status 'running'

            if ($file.Length -gt $MaxBytes) {
                $chunkResult.SkippedFiles++
                $chunkResult.Errors += @{
                    FileName = $file.Name
                    Error = "File too large ($([math]::Round($file.Length / 1MB, 2)) MB)"
                }
                Write-ChunkProgressEvent -Path $ProgressPath -EventType 'finish' -FileName $file.Name -ChunkId $ChunkId -Status 'skipped'
                continue
            }

            if ($file.Length -eq 0) {
                $chunkResult.SkippedFiles++
                Write-ChunkProgressEvent -Path $ProgressPath -EventType 'finish' -FileName $file.Name -ChunkId $ChunkId -Status 'skipped'
                continue
            }

            $content = Read-FileContentWithFallback -Path $file.FullName
            if (-not $content) {
                throw "Unable to read file content"
            }

            $fileResult = Find-SensitiveData -Content $content -FilePath $file.FullName -FileSize $file.Length
            Add-FileResultToScanResult -ScanResult $chunkResult -FileResult $fileResult
            Write-ChunkProgressEvent -Path $ProgressPath -EventType 'finish' -FileName $file.Name -ChunkId $ChunkId -Status 'ok'
        } catch {
            $chunkResult.FailedFiles++
            $chunkResult.Errors += @{
                FileName = $file.Name
                Error = $_.Exception.Message
            }
            Write-ChunkProgressEvent -Path $ProgressPath -EventType 'finish' -FileName $file.Name -ChunkId $ChunkId -Status 'failed'
        }
    }

    return $chunkResult
}

function Split-ScanChunks {
    param(
        [object[]]$Files,
        [int]$DesiredChunkCount
    )

    if (-not $Files -or $Files.Count -eq 0) {
        return @()
    }

    $chunkCount = [math]::Min([math]::Max(1, $DesiredChunkCount), $Files.Count)
    $chunkSize = [math]::Ceiling($Files.Count / $chunkCount)
    $chunks = [System.Collections.Generic.List[object]]::new()

    for ($start = 0; $start -lt $Files.Count; $start += $chunkSize) {
        $end = [math]::Min($start + $chunkSize - 1, $Files.Count - 1)
        $chunkFiles = @($Files[$start..$end])

        $chunks.Add([pscustomobject]@{
            ChunkId = $chunks.Count
            Files = $chunkFiles
            FileCount = $chunkFiles.Count
            Signature = Get-ChunkSignature -Files $chunkFiles
            PartialPath = $null
            ProgressPath = $null
        })
    }

    return @($chunks)
}

function Get-ChunkSignature {
    param([object[]]$Files)

    $builder = [System.Text.StringBuilder]::new()
    foreach ($file in $Files) {
        [void]$builder.Append([string]$file.FullName)
        [void]$builder.Append('|')
        [void]$builder.Append([string]$file.Length)
        [void]$builder.Append('|')
        [void]$builder.Append([string]$file.Extension)
        [void]$builder.Append("`n")
    }

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($builder.ToString())
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        return -join ($sha256.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') })
    } finally {
        $sha256.Dispose()
    }
}

function Get-ScanPartialResultDirectory {
    param([string]$OutputPath)

    $outputDir = Split-Path $OutputPath -Parent
    if ([string]::IsNullOrWhiteSpace($outputDir)) {
        $outputDir = (Get-Location).Path
    }

    $outputName = Split-Path $OutputPath -Leaf
    return (Join-Path $outputDir ($outputName + '.parts'))
}

function Get-ScanPartialResultPath {
    param(
        [Parameter(Mandatory)][string]$PartialDirectory,
        [Parameter(Mandatory)][int]$ChunkId
    )

    return (Join-Path $PartialDirectory ('chunk-{0:D4}.json' -f $ChunkId))
}

function Get-ScanChunkProgressPath {
    param(
        [Parameter(Mandatory)][string]$PartialDirectory,
        [Parameter(Mandatory)][int]$ChunkId
    )

    return (Join-Path $PartialDirectory ('chunk-{0:D4}.progress.jsonl' -f $ChunkId))
}

function Write-ChunkProgressEvent {
    param(
        [string]$Path,
        [Parameter(Mandatory)][string]$EventType,
        [Parameter(Mandatory)][string]$FileName,
        [int]$ChunkId = -1,
        [string]$Status = 'ok'
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return
    }

    $parent = Split-Path $Path -Parent
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $record = [ordered]@{
        EventType = $EventType
        FileName = $FileName
        ChunkId = $ChunkId
        Status = $Status
        Timestamp = Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fff'
    }

    [System.IO.File]::AppendAllText(
        $Path,
        (($record | ConvertTo-Json -Compress) + [Environment]::NewLine),
        [System.Text.UTF8Encoding]::new($false)
    )
}

function Read-NewChunkProgressEvents {
    param(
        [Parameter(Mandatory)][string]$Path,
        [int]$ProcessedLineCount = 0
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return @{
            Events = @()
            ProcessedLineCount = $ProcessedLineCount
        }
    }

    $lines = @(Get-Content -LiteralPath $Path)
    if ($lines.Count -le $ProcessedLineCount) {
        return @{
            Events = @()
            ProcessedLineCount = $ProcessedLineCount
        }
    }

    $events = [System.Collections.Generic.List[object]]::new()
    $updatedProcessedLineCount = $ProcessedLineCount

    for ($index = $ProcessedLineCount; $index -lt $lines.Count; $index++) {
        $line = $lines[$index]
        if ([string]::IsNullOrWhiteSpace($line)) {
            $updatedProcessedLineCount++
            continue
        }

        try {
            $events.Add(($line | ConvertFrom-Json))
            $updatedProcessedLineCount++
        } catch {
            break
        }
    }

    return @{
        Events = @($events)
        ProcessedLineCount = $updatedProcessedLineCount
    }
}

function Export-ScanPartialResult {
    param(
        [Parameter(Mandatory)]$Chunk,
        [Parameter(Mandatory)]$ChunkResult,
        [Parameter(Mandatory)][string]$Path
    )

    $parent = Split-Path $Path -Parent
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $record = [ordered]@{
        AnalyzerVersion = $Script:AnalyzerVersion
        ChunkId = [int]$Chunk.ChunkId
        ChunkSignature = [string]$Chunk.Signature
        FileCount = [int]$Chunk.FileCount
        ChunkResult = $ChunkResult
    }

    $record | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Import-ScanPartialResult {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    try {
        return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
    } catch {
        return $null
    }
}

function Test-CanReuseScanPartialResult {
    param(
        [Parameter(Mandatory)]$Chunk,
        [Parameter(Mandatory)][string]$Path
    )

    $existing = Import-ScanPartialResult -Path $Path
    if ($null -eq $existing) {
        return $false
    }

    if ([int]$existing.ChunkId -ne [int]$Chunk.ChunkId) {
        return $false
    }

    if ([string]$existing.AnalyzerVersion -ne $Script:AnalyzerVersion) {
        return $false
    }

    if ([string]$existing.ChunkSignature -ne [string]$Chunk.Signature) {
        return $false
    }

    return $true
}

function Get-ParallelWorkerFunctionMap {
    $functionNames = @(
        'Get-CanonicalEnvRoot',
        'Trim-PowerShellParameterTailFromPathCandidate',
        'Trim-PathCandidate',
        'Resolve-DotSegments',
        'Convert-ToCanonicalAbsolutePath',
        'Convert-ToFairPath',
        'Test-RawSensitiveFilePath',
        'Test-FairSensitiveFilePath',
        'Remove-StringWrapper',
        'Split-ConcatenationTerms',
        'Split-PseudoStatements',
        'Expand-InterpolatedToken',
        'Resolve-ExpressionToken',
        'Resolve-ExpressionToString',
        'Resolve-VariableAssignments',
        'Get-VariableDerivedPaths',
        'Normalize-FairFilePath',
        'Find-SensitiveData',
        'Test-ValidIP',
        'Test-ValidRegKey',
        'New-ScanChunkResult',
        'Add-FileResultToScanResult',
        'Export-ScanPartialResult',
        'Write-ChunkProgressEvent',
        'Read-FileContentWithFallback',
        'Scan-FileChunk'
    )

    $functionMap = @{}
    foreach ($name in $functionNames) {
        $functionMap[$name] = (Get-Command -Name $name -CommandType Function).ScriptBlock.ToString()
    }

    return $functionMap
}

function Merge-ScanChunkResult {
    param(
        $Results,
        $ChunkResult
    )

    $Results.ProcessedFiles += $ChunkResult.ProcessedFiles
    $Results.FailedFiles += $ChunkResult.FailedFiles
    $Results.SkippedFiles += $ChunkResult.SkippedFiles

    $Results.Summary.IP.TotalOccurrences += $ChunkResult.Summary.IP.TotalOccurrences
    $Results.Summary.URL.TotalOccurrences += $ChunkResult.Summary.URL.TotalOccurrences
    $Results.Summary.FilePath.TotalOccurrences += $ChunkResult.Summary.FilePath.TotalOccurrences
    $Results.Summary.FilePathRaw.TotalOccurrences += $ChunkResult.Summary.FilePathRaw.TotalOccurrences
    $Results.Summary.RegKey.TotalOccurrences += $ChunkResult.Summary.RegKey.TotalOccurrences

    $Results.Summary.IP.FilesContaining += $ChunkResult.Summary.IP.FilesContaining
    $Results.Summary.URL.FilesContaining += $ChunkResult.Summary.URL.FilesContaining
    $Results.Summary.FilePath.FilesContaining += $ChunkResult.Summary.FilePath.FilesContaining
    $Results.Summary.FilePathRaw.FilesContaining += $ChunkResult.Summary.FilePathRaw.FilesContaining
    $Results.Summary.RegKey.FilesContaining += $ChunkResult.Summary.RegKey.FilesContaining

    $Results.FileDetails += $ChunkResult.FileDetails
    $Results.Errors += $ChunkResult.Errors

    $Results.CollectedValues.IP += $ChunkResult.CollectedValues.IP
    $Results.CollectedValues.URL += $ChunkResult.CollectedValues.URL
    $Results.CollectedValues.FilePath += $ChunkResult.CollectedValues.FilePath
    $Results.CollectedValues.FilePathRaw += $ChunkResult.CollectedValues.FilePathRaw
    $Results.CollectedValues.RegKey += $ChunkResult.CollectedValues.RegKey
}

function Finalize-ScanResults {
    param($Results)

    $Results.Summary.IP.UniqueValues = ($Results.CollectedValues.IP | Select-Object -Unique).Count
    $Results.Summary.URL.UniqueValues = ($Results.CollectedValues.URL | Select-Object -Unique).Count
    $Results.Summary.FilePath.UniqueValues = ($Results.CollectedValues.FilePath | Select-Object -Unique).Count
    $Results.Summary.FilePathRaw.UniqueValues = ($Results.CollectedValues.FilePathRaw | Select-Object -Unique).Count
    $Results.Summary.RegKey.UniqueValues = ($Results.CollectedValues.RegKey | Select-Object -Unique).Count

    $Results.FileDetails = @($Results.FileDetails | Sort-Object FileName, FileSize)
    $Results.Errors = @($Results.Errors | Sort-Object FileName, Error)
    [void]$Results.Remove('CollectedValues')

    return $Results
}

function Scan-Dataset {
    param(
        [string]$DatasetPath,
        [string]$OutputDir,
        [int]$MaxFileSizeMB,
        [int]$ThrottleLimit,
        [int]$ChunkCount = 128,
        [switch]$ForceRescan,
        [int]$ProgressRefreshMs = 100
    )

    $maxBytes = $MaxFileSizeMB * 1MB

    Write-Host "Scanning dataset: $DatasetPath" -ForegroundColor Cyan

    $files = @(
        Get-ChildItem -Path $DatasetPath -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -eq '.ps1' -or $_.Extension -eq '' } |
        Sort-Object FullName |
        ForEach-Object {
            [pscustomobject]@{
                FullName = $_.FullName
                Name = $_.Name
                Length = $_.Length
                Extension = $_.Extension
            }
        }
    )
    $totalFiles = $files.Count

    Write-Host "Found $totalFiles files" -ForegroundColor Green

    $results = New-ScanResults -TotalFiles $totalFiles

    if ($totalFiles -eq 0) {
        Write-Host "`nScan complete." -ForegroundColor Green
        return (Finalize-ScanResults -Results $results)
    }

    $effectiveThrottle = [math]::Min([math]::Max(1, $ThrottleLimit), $totalFiles)

    if ($effectiveThrottle -le 1) {
        Write-Host "Using serial scan" -ForegroundColor Cyan
        $chunkResult = Scan-FileChunk -Files $files -MaxBytes $maxBytes
        Merge-ScanChunkResult -Results $results -ChunkResult $chunkResult
    } else {
        $startThreadJobCommand = Get-Command -Name Start-ThreadJob -ErrorAction SilentlyContinue

        if ($PSVersionTable.PSVersion.Major -lt 7 -or $null -eq $startThreadJobCommand) {
            Write-Warning "Parallel mode requires PowerShell 7+. Falling back to serial scan."
            $chunkResult = Scan-FileChunk -Files $files -MaxBytes $maxBytes
            Merge-ScanChunkResult -Results $results -ChunkResult $chunkResult
        } else {
            $desiredChunkCount = [math]::Min([math]::Max(1, $ChunkCount), $totalFiles)
            $chunks = Split-ScanChunks -Files $files -DesiredChunkCount $desiredChunkCount
            Write-Host "Using $effectiveThrottle parallel workers across $($chunks.Count) chunks" -ForegroundColor Cyan

            $partialDirectory = Get-ScanPartialResultDirectory -OutputPath $OutputDir
            if (-not (Test-Path -LiteralPath $partialDirectory)) {
                New-Item -ItemType Directory -Path $partialDirectory -Force | Out-Null
            }

            foreach ($chunk in $chunks) {
                $chunk.PartialPath = Get-ScanPartialResultPath -PartialDirectory $partialDirectory -ChunkId $chunk.ChunkId
                $chunk.ProgressPath = Get-ScanChunkProgressPath -PartialDirectory $partialDirectory -ChunkId $chunk.ChunkId
            }

            $reusedChunks = [System.Collections.Generic.List[object]]::new()
            $pendingChunks = [System.Collections.Generic.List[object]]::new()

            foreach ($chunk in $chunks) {
                if (-not $ForceRescan -and (Test-CanReuseScanPartialResult -Chunk $chunk -Path $chunk.PartialPath)) {
                    $reusedChunks.Add($chunk)
                    continue
                }

                $pendingChunks.Add($chunk)
            }

            if ($ForceRescan) {
                Write-Host "ForceRescan enabled. Existing chunk results will be ignored." -ForegroundColor Yellow
            } elseif ($reusedChunks.Count -gt 0) {
                $reusedFileCount = (($reusedChunks | Measure-Object -Property FileCount -Sum).Sum)
                Write-Host "Reused chunks: $($reusedChunks.Count)/$($chunks.Count), covering $reusedFileCount files" -ForegroundColor Green
            }

            Write-Host "Pending chunks: $($pendingChunks.Count)/$($chunks.Count)" -ForegroundColor Cyan

            $workerFunctions = Get-ParallelWorkerFunctionMap
            $regexPatterns = @{
                IP = $IPRegex.ToString()
                URL = $URLRegex.ToString()
                FilePath = $FilePathRegex.ToString()
                VariablePath = $VariablePathRegex.ToString()
                RegKey = $RegKeyRegex.ToString()
            }

            $jobs = @()
            foreach ($chunk in $pendingChunks) {
                if (Test-Path -LiteralPath $chunk.ProgressPath) {
                    Remove-Item -LiteralPath $chunk.ProgressPath -Force -ErrorAction SilentlyContinue
                }

                $jobs += Start-ThreadJob -Name ("scan-chunk-{0:D4}" -f $chunk.ChunkId) -ThrottleLimit $effectiveThrottle -ArgumentList @(
                    $chunk,
                    $maxBytes,
                    $workerFunctions,
                    $regexPatterns,
                    $RawExcludedPathPatterns,
                    $FairExcludedPathPatterns,
                    $CanonicalEnvRoots,
                    $CanonicalPathRoots
                ) -ScriptBlock {
                    param(
                        $Chunk,
                        $MaxBytes,
                        $FunctionMap,
                        $Patterns,
                        $RawExcludedPathPatterns,
                        $FairExcludedPathPatterns,
                        $CanonicalEnvRoots,
                        $CanonicalPathRoots
                    )

                    foreach ($entry in $FunctionMap.GetEnumerator()) {
                        New-Item -Path ("function:\{0}" -f $entry.Key) -Value ([scriptblock]::Create($entry.Value)) -Force | Out-Null
                    }

                    $IPRegex = [regex]::new($Patterns.IP, 'Compiled')
                    $URLRegex = [regex]::new($Patterns.URL, 'Compiled')
                    $FilePathRegex = [regex]::new($Patterns.FilePath, 'Compiled')
                    $VariablePathRegex = [regex]::new($Patterns.VariablePath, 'Compiled')
                    $RegKeyRegex = [regex]::new($Patterns.RegKey, 'Compiled')

                    try {
                        $chunkResult = Scan-FileChunk -Files $Chunk.Files -MaxBytes $MaxBytes -ChunkId $Chunk.ChunkId -ProgressPath $Chunk.ProgressPath
                        Export-ScanPartialResult -Chunk $Chunk -ChunkResult $chunkResult -Path $Chunk.PartialPath

                        [pscustomobject]@{
                            ChunkId = $Chunk.ChunkId
                            PartialPath = $Chunk.PartialPath
                            FileCount = $Chunk.FileCount
                        }
                    } catch {
                        if (Test-Path -LiteralPath $Chunk.PartialPath) {
                            Remove-Item -LiteralPath $Chunk.PartialPath -Force -ErrorAction SilentlyContinue
                        }

                        throw
                    }
                }
            }

            if ($jobs.Count -gt 0) {
                $startCounter = (($reusedChunks | Measure-Object -Property FileCount -Sum).Sum)
                if ($null -eq $startCounter) {
                    $startCounter = 0
                }

                $finishCounter = $startCounter
                $chunkProgressState = @{}
                foreach ($chunk in $pendingChunks) {
                    $chunkProgressState[$chunk.ProgressPath] = 0
                }

                do {
                    foreach ($chunk in $pendingChunks) {
                        $progressSnapshot = Read-NewChunkProgressEvents -Path $chunk.ProgressPath -ProcessedLineCount $chunkProgressState[$chunk.ProgressPath]
                        $chunkProgressState[$chunk.ProgressPath] = $progressSnapshot.ProcessedLineCount

                        foreach ($eventRecord in $progressSnapshot.Events) {
                            if ($eventRecord.EventType -eq 'start') {
                                $startCounter++
                                Write-Host ("start {0}/{1} {2}" -f $startCounter, $totalFiles, $eventRecord.FileName)
                                continue
                            }

                            if ($eventRecord.EventType -eq 'finish') {
                                $finishCounter++
                                $statusSuffix = ''
                                if ($eventRecord.Status -and $eventRecord.Status -notin @('ok', 'running')) {
                                    $statusSuffix = " [$($eventRecord.Status)]"
                                }

                                Write-Host ("finish {0}/{1} {2}{3}" -f $finishCounter, $totalFiles, $eventRecord.FileName, $statusSuffix)
                            }
                        }
                    }

                    $runningJobs = @($jobs | Where-Object { $_.State -eq 'Running' -or $_.State -eq 'NotStarted' }).Count
                    $doneChunkCount = @($chunks | Where-Object { Test-CanReuseScanPartialResult -Chunk $_ -Path $_.PartialPath }).Count

                    if ((@($jobs | Where-Object { $_.State -in @('Completed', 'Failed', 'Stopped') }).Count) -eq $jobs.Count) {
                        break
                    }

                    Start-Sleep -Milliseconds $ProgressRefreshMs
                } while ($true)

                foreach ($chunk in $pendingChunks) {
                    $progressSnapshot = Read-NewChunkProgressEvents -Path $chunk.ProgressPath -ProcessedLineCount $chunkProgressState[$chunk.ProgressPath]
                    $chunkProgressState[$chunk.ProgressPath] = $progressSnapshot.ProcessedLineCount

                    foreach ($eventRecord in $progressSnapshot.Events) {
                        if ($eventRecord.EventType -eq 'start') {
                            $startCounter++
                            Write-Host ("start {0}/{1} {2}" -f $startCounter, $totalFiles, $eventRecord.FileName)
                            continue
                        }

                        if ($eventRecord.EventType -eq 'finish') {
                            $finishCounter++
                            $statusSuffix = ''
                            if ($eventRecord.Status -and $eventRecord.Status -notin @('ok', 'running')) {
                                $statusSuffix = " [$($eventRecord.Status)]"
                            }

                            Write-Host ("finish {0}/{1} {2}{3}" -f $finishCounter, $totalFiles, $eventRecord.FileName, $statusSuffix)
                        }
                    }
                }
            }

            $jobFailures = [System.Collections.Generic.List[object]]::new()
            foreach ($job in $jobs) {
                try {
                    Receive-Job -Job $job -ErrorAction Stop | Out-Null
                } catch {
                    $reason = $null
                    if ($job.ChildJobs.Count -gt 0 -and $job.ChildJobs[0].JobStateInfo.Reason) {
                        $reason = $job.ChildJobs[0].JobStateInfo.Reason.Message
                    }

                    if ([string]::IsNullOrWhiteSpace($reason)) {
                        $reason = $_.Exception.Message
                    }

                    $jobFailures.Add([pscustomobject]@{
                        Name = $job.Name
                        Error = $reason
                    })
                }
            }

            if ($jobs.Count -gt 0) {
                Remove-Job -Job $jobs -Force -ErrorAction SilentlyContinue
            }

            if ($jobFailures.Count -gt 0) {
                foreach ($jobFailure in $jobFailures) {
                    Write-Warning ("Chunk failed: {0} - {1}" -f $jobFailure.Name, $jobFailure.Error)
                }

                throw ("{0} chunks failed. Successful partial results were preserved for resume." -f $jobFailures.Count)
            }

            foreach ($chunk in $chunks | Sort-Object ChunkId) {
                $partialRecord = Import-ScanPartialResult -Path $chunk.PartialPath
                if ($null -eq $partialRecord) {
                    throw ("Missing partial result: chunk {0} ({1})" -f $chunk.ChunkId, $chunk.PartialPath)
                }

                Merge-ScanChunkResult -Results $results -ChunkResult $partialRecord.ChunkResult
            }
        }
    }

    Write-Host "`nScan complete." -ForegroundColor Green
    Write-Host "Processed files: $($results.ProcessedFiles)" -ForegroundColor Cyan
    Write-Host "Failed: $($results.FailedFiles)" -ForegroundColor Yellow
    Write-Host "Skipped: $($results.SkippedFiles)" -ForegroundColor Yellow

    return (Finalize-ScanResults -Results $results)
}

function Export-ScanReport {
    param(
        [hashtable]$Results,
        [string]$OutputPath
    )

    $outputDir = Split-Path $OutputPath -Parent
    if ($outputDir -and -not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }

    $jsonPath = "$OutputPath.json"
    $Results | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonPath -Encoding UTF8
    Write-Host "JSON Report saved: $jsonPath" -ForegroundColor Green

    $mdPath = "$OutputPath.md"
    $md = @"
# Sensitive Data Scan Report

## Statistics

### IP Address
- **Total Occurrences**: $($Results.Summary.IP.TotalOccurrences)
- **Unique Values**: $($Results.Summary.IP.UniqueValues)
- **Files Containing**: $($Results.Summary.IP.FilesContaining)

### URL
- **Total Occurrences**: $($Results.Summary.URL.TotalOccurrences)
- **Unique Values**: $($Results.Summary.URL.UniqueValues)
- **Files Containing**: $($Results.Summary.URL.FilesContaining)

### File Path (Fair)
- **Total Occurrences**: $($Results.Summary.FilePath.TotalOccurrences)
- **Unique Values**: $($Results.Summary.FilePath.UniqueValues)
- **Files Containing**: $($Results.Summary.FilePath.FilesContaining)

### File Path (Raw Regex)
- **Total Occurrences**: $($Results.Summary.FilePathRaw.TotalOccurrences)
- **Unique Values**: $($Results.Summary.FilePathRaw.UniqueValues)
- **Files Containing**: $($Results.Summary.FilePathRaw.FilesContaining)

### Registry Key
- **Total Occurrences**: $($Results.Summary.RegKey.TotalOccurrences)
- **Unique Values**: $($Results.Summary.RegKey.UniqueValues)
- **Files Containing**: $($Results.Summary.RegKey.FilesContaining)

## Detailed Statistics

| Data Type | Total Occurrences | Unique Values | Files Containing |
|---------|-----------|-----------|-----------|
| IP | $($Results.Summary.IP.TotalOccurrences) | $($Results.Summary.IP.UniqueValues) | $($Results.Summary.IP.FilesContaining) |
| URL | $($Results.Summary.URL.TotalOccurrences) | $($Results.Summary.URL.UniqueValues) | $($Results.Summary.URL.FilesContaining) |
| File Path (Fair) | $($Results.Summary.FilePath.TotalOccurrences) | $($Results.Summary.FilePath.UniqueValues) | $($Results.Summary.FilePath.FilesContaining) |
| File Path (Raw Regex) | $($Results.Summary.FilePathRaw.TotalOccurrences) | $($Results.Summary.FilePathRaw.UniqueValues) | $($Results.Summary.FilePathRaw.FilesContaining) |
| Registry Key | $($Results.Summary.RegKey.TotalOccurrences) | $($Results.Summary.RegKey.UniqueValues) | $($Results.Summary.RegKey.FilesContaining) |

"@

    if ($Results.Errors.Count -gt 0) {
        $md += "`n## Error Log`n`n"
        foreach ($error in $Results.Errors) {
            $md += "- **$($error.FileName)**: $($error.Error)`n"
        }
    }

    $md | Set-Content -Path $mdPath -Encoding UTF8
    Write-Host "Markdown Report saved: $mdPath" -ForegroundColor Green
}

try {
    $scanResults = Scan-Dataset -DatasetPath $DatasetPath -OutputDir $OutputPath -MaxFileSizeMB $MaxFileSizeMB -ThrottleLimit $ThrottleLimit -ChunkCount $ChunkCount -ForceRescan:$ForceRescan -ProgressRefreshMs $ProgressRefreshMs
    Export-ScanReport -Results $scanResults -OutputPath $OutputPath

    Write-Host "`nScan completed!" -ForegroundColor Green
} catch {
    Write-Host "Error during scan: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
