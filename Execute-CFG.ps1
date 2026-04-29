# Execute-CFG.ps1

. "$PSScriptRoot\ConvertTo-Expression-origin.ps1"

$script:BlockedPlaceholderMarker = "__BLOCKED_PLACEHOLDER__"

Add-Type -TypeDefinition @'
using System;
using System.Dynamic;
using System.Linq.Expressions;

public class BlockedCommandPlaceholder : DynamicObject
{
    public static readonly string Marker = "__BLOCKED_PLACEHOLDER__";

    public string BlockedCommand { get; set; }
    public string Reason { get; set; }
    public string PreservedText { get; set; }

    public BlockedCommandPlaceholder() { }
    public BlockedCommandPlaceholder(string command, string reason)
    {
        BlockedCommand = command;
        Reason = reason;
    }

    public BlockedCommandPlaceholder(string command, string reason, string preservedText)
    {
        BlockedCommand = command;
        Reason = reason;
        PreservedText = preservedText;
    }

    public override bool TryGetMember(GetMemberBinder binder, out object result)
    {
        result = this;
        return true;
    }

    public override bool TrySetMember(SetMemberBinder binder, object value)
    {
        return true;
    }

    public override bool TryInvokeMember(InvokeMemberBinder binder, object[] args, out object result)
    {
        result = this;
        return true;
    }

    public override bool TryGetIndex(GetIndexBinder binder, object[] indexes, out object result)
    {
        result = this;
        return true;
    }

    public override bool TrySetIndex(SetIndexBinder binder, object[] indexes, object value)
    {
        return true;
    }

    public override bool TryInvoke(InvokeBinder binder, object[] args, out object result)
    {
        result = this;
        return true;
    }

    public override bool TryConvert(ConvertBinder binder, out object result)
    {
        if (binder.Type == typeof(string))
        {
            result = Marker;
            return true;
        }
        if (binder.Type == typeof(bool))
        {
            result = false;
            return true;
        }
        if (binder.Type == typeof(int) || binder.Type == typeof(long) ||
            binder.Type == typeof(double) || binder.Type == typeof(float))
        {
            result = 0;
            return true;
        }
        result = null;
        return false;
    }

    public override string ToString()
    {
        return Marker;
    }

    public bool IsBlockedPlaceholder { get { return true; } }
}
'@ -ErrorAction SilentlyContinue

function New-BlockedPlaceholder {
    param(
        [string]$Command,
        [string]$Reason = "Forbidden command",
        [string]$PreservedText = $null
    )
    return [BlockedCommandPlaceholder]::new($Command, $Reason, $PreservedText)
}

function Get-PowerShellHostInfo {
    $processName = $null
    $exePath = $null

    try {
        $proc = Get-Process -Id $PID -ErrorAction Stop
        if ($proc) {
            $processName = [string]$proc.ProcessName
            if ($proc.Path) { $exePath = [string]$proc.Path }
        }
    } catch {
        $processName = $null
        $exePath = $null
    }

    $version = $null
    $major = $null
    if ($PSVersionTable -and $PSVersionTable.ContainsKey('PSVersion') -and $PSVersionTable.PSVersion) {
        $version = [string]$PSVersionTable.PSVersion
        $major = [int]$PSVersionTable.PSVersion.Major
    } elseif ($Host -and $Host.Version) {
        $version = [string]$Host.Version
    }

    $edition = if ($PSVersionTable -and $PSVersionTable.ContainsKey('PSEdition') -and $PSVersionTable.PSEdition) {
        [string]$PSVersionTable.PSEdition
    } else {
        'Desktop'
    }

    $hostName = if ($Host -and $Host.Name) { [string]$Host.Name } else { $null }
    $displayParts = @()
    if ($edition) { $displayParts += $edition }
    if ($version) { $displayParts += $version }
    $display = ($displayParts -join ' ').Trim()
    if ($processName) { $display = "$display [$processName]" }
    if ([string]::IsNullOrWhiteSpace($display)) { $display = 'UnknownHost' }

    return [PSCustomObject]@{
        Version        = $version
        Major          = $major
        Edition        = $edition
        HostName       = $hostName
        ProcessName    = $processName
        ExecutablePath = $exePath
        Display        = $display
    }
}

function Format-PowerShellHostInfo {
    param($HostInfo)

    if ($null -eq $HostInfo) { return 'UnknownHost' }

    if ($HostInfo.PSObject.Properties['Display'] -and -not [string]::IsNullOrWhiteSpace([string]$HostInfo.Display)) {
        return [string]$HostInfo.Display
    }

    $parts = @()
    if ($HostInfo.PSObject.Properties['Edition'] -and $HostInfo.Edition) { $parts += [string]$HostInfo.Edition }
    if ($HostInfo.PSObject.Properties['Version'] -and $HostInfo.Version) { $parts += [string]$HostInfo.Version }
    $text = ($parts -join ' ').Trim()
    if ($HostInfo.PSObject.Properties['ProcessName'] -and $HostInfo.ProcessName) {
        $text = "$text [$($HostInfo.ProcessName)]"
    }
    if ([string]::IsNullOrWhiteSpace($text)) { return 'UnknownHost' }
    return $text
}

function Resolve-ExecutionContextChildHostExecutable {
    param(
        [ValidateSet('powershell', 'pwsh', 'current')]
        [string]$PreferredHost = 'powershell'
    )

    if ($PreferredHost -eq 'current') {
        $currentHost = Get-PowerShellHostInfo
        if ($currentHost -and -not [string]::IsNullOrWhiteSpace([string]$currentHost.ExecutablePath) -and
            (Test-Path -LiteralPath ([string]$currentHost.ExecutablePath))) {
            return [string]$currentHost.ExecutablePath
        }
    }

    if ($PreferredHost -eq 'pwsh') {
        $pwshCommand = @(Get-Command pwsh.exe, pwsh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1)
        if ($pwshCommand.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$pwshCommand[0].Source)) {
            return [string]$pwshCommand[0].Source
        }
    }

    $powershellExe = (Get-Command powershell.exe -CommandType Application -ErrorAction SilentlyContinue).Source
    if (-not [string]::IsNullOrWhiteSpace([string]$powershellExe)) {
        return [string]$powershellExe
    }

    if ($PreferredHost -eq 'current') {
        $currentHost = Get-PowerShellHostInfo
        if ($currentHost -and -not [string]::IsNullOrWhiteSpace([string]$currentHost.ExecutablePath) -and
            (Test-Path -LiteralPath ([string]$currentHost.ExecutablePath))) {
            return [string]$currentHost.ExecutablePath
        }
    }

    return (Get-Command pwsh.exe -CommandType Application -ErrorAction Stop).Source
}

function Convert-ExecutionContextCodeToBase64 {
    param([AllowNull()][string]$Code)

    $text = if ($null -eq $Code) { '' } else { [string]$Code }
    return [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($text))
}

function New-ExecutionContext {
    param(
        [ValidateSet('Runspace', 'SubprocessReplay')]
        [string]$Backend = 'Runspace',
        [ValidateSet('powershell', 'pwsh', 'current')]
        [string]$ChildHost = 'powershell'
    )

    if ($Backend -eq 'SubprocessReplay') {
        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('psdissect_exec_' + [guid]::NewGuid().ToString('N'))
        $null = [System.IO.Directory]::CreateDirectory($tempRoot)

        return @{
            Runspace         = $null
            Backend          = 'SubprocessReplay'
            ChildHost        = $ChildHost
            ChildHostExe     = Resolve-ExecutionContextChildHostExecutable -PreferredHost $ChildHost
            TempRoot         = $tempRoot
            ReplayStatements = (New-Object 'System.Collections.Generic.List[string]')
        }
    }

    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.Open()

    return @{
        Runspace = $runspace
        Backend  = 'Runspace'
    }
}

function Get-ProcessDescendantIds {
    param([int]$RootProcessId)

    if ($RootProcessId -le 0) {
        return @()
    }

    $descendants = New-Object 'System.Collections.Generic.List[int]'
    $visited = New-Object 'System.Collections.Generic.HashSet[int]'
    $pending = New-Object 'System.Collections.Generic.Queue[int]'
    $pending.Enqueue($RootProcessId)
    $visited.Add($RootProcessId) | Out-Null

    while ($pending.Count -gt 0) {
        $currentPid = $pending.Dequeue()
        $children = @()
        try {
            $children = @(Get-CimInstance -ClassName Win32_Process -Filter ("ParentProcessId = {0}" -f $currentPid) -ErrorAction Stop | ForEach-Object {
                try { [int]$_.ProcessId } catch { $null }
            })
        } catch {
            $children = @()
        }

        foreach ($childPid in $children) {
            if ($null -eq $childPid) { continue }
            if ($visited.Add([int]$childPid)) {
                $descendants.Add([int]$childPid) | Out-Null
                $pending.Enqueue([int]$childPid)
            }
        }
    }

    return @($descendants.ToArray())
}

function Stop-ProcessTreeById {
    param(
        [int]$RootProcessId,
        [switch]$IncludeRoot
    )

    if ($RootProcessId -le 0) {
        return
    }

    $targets = New-Object 'System.Collections.Generic.List[int]'
    foreach ($childPid in @(Get-ProcessDescendantIds -RootProcessId $RootProcessId)) {
        $targets.Add([int]$childPid) | Out-Null
    }
    if ($IncludeRoot) {
        $targets.Add([int]$RootProcessId) | Out-Null
    }

    foreach ($targetPid in @($targets.ToArray() | Sort-Object -Descending -Unique)) {
        try {
            Stop-Process -Id $targetPid -Force -ErrorAction Stop
        } catch {
        }
    }
}

function Add-CFGVisitedNodeCount {
    param(
        [hashtable]$Context,
        [int]$NodeId
    )

    if ($null -eq $Context) { return 0 }
    if (-not $Context.ContainsKey('VisitedNodes') -or $null -eq $Context.VisitedNodes) {
        $Context.VisitedNodes = @{}
    }

    $current = 0
    if ($Context.VisitedNodes.ContainsKey($NodeId) -and $null -ne $Context.VisitedNodes[$NodeId]) {
        try { $current = [int]$Context.VisitedNodes[$NodeId] } catch { $current = 0 }
    }

    $current++
    $Context.VisitedNodes[$NodeId] = $current
    return $current
}
function Close-ExecutionContext {
    param([hashtable]$ExecContext)

    if ($null -eq $ExecContext) {
        return
    }

    if ($ExecContext.Runspace) {
        $ExecContext.Runspace.Close()
        $ExecContext.Runspace.Dispose()
    }

    if ($ExecContext.ContainsKey('TempRoot') -and -not [string]::IsNullOrWhiteSpace([string]$ExecContext.TempRoot)) {
        try {
            if (Test-Path -LiteralPath ([string]$ExecContext.TempRoot)) {
                Remove-Item -LiteralPath ([string]$ExecContext.TempRoot) -Recurse -Force -ErrorAction SilentlyContinue
            }
        } catch {
        }
    }
}

function Invoke-InSubprocessReplayContext {
    param(
        [Parameter(Mandatory)][hashtable]$ExecContext,
        [Parameter(Mandatory)][string]$Code,
        [int]$TimeoutMs = 5000,
        [bool]$PersistOnSuccess = $true
    )

    $childExe = if ($ExecContext.ContainsKey('ChildHostExe')) { [string]$ExecContext.ChildHostExe } else { $null }
    if ([string]::IsNullOrWhiteSpace($childExe)) {
        return @{
            Success = $false
            Error   = 'Subprocess host executable is unavailable'
            Result  = $null
            Timeout = $false
        }
    }

    $tempRoot = if ($ExecContext.ContainsKey('TempRoot')) { [string]$ExecContext.TempRoot } else { $null }
    if ([string]::IsNullOrWhiteSpace($tempRoot)) {
        return @{
            Success = $false
            Error   = 'Subprocess temp root is unavailable'
            Result  = $null
            Timeout = $false
        }
    }

    if (-not (Test-Path -LiteralPath $tempRoot)) {
        $null = [System.IO.Directory]::CreateDirectory($tempRoot)
    }

    if (-not $ExecContext.ContainsKey('ReplayStatements') -or $null -eq $ExecContext.ReplayStatements) {
        $ExecContext.ReplayStatements = (New-Object 'System.Collections.Generic.List[string]')
    }

    $invokeId = [guid]::NewGuid().ToString('N')
    $runnerPath = Join-Path $tempRoot ("invoke_${invokeId}.ps1")
    $resultPath = Join-Path $tempRoot ("invoke_${invokeId}.result.clixml")
    $errorPath = Join-Path $tempRoot ("invoke_${invokeId}.error.txt")

    $replayEncoded = @()
    foreach ($statement in @($ExecContext.ReplayStatements)) {
        $replayEncoded += ("'" + (Convert-ExecutionContextCodeToBase64 -Code ([string]$statement)) + "'")
    }
    $currentEncoded = Convert-ExecutionContextCodeToBase64 -Code $Code

    $runnerText = @"
`$ErrorActionPreference = 'Stop'
`$ProgressPreference = 'SilentlyContinue'

function Decode-ExecutionContextCode {
    param([AllowNull()][string]`$Encoded)

    if ([string]::IsNullOrWhiteSpace(`$Encoded)) {
        return ''
    }

    return [System.Text.Encoding]::Unicode.GetString([Convert]::FromBase64String(`$Encoded))
}

`$replayBlocks = @(
$(if ($replayEncoded.Count -gt 0) { $replayEncoded -join ",`r`n" } else { '' })
)
`$currentBlock = '$currentEncoded'

try {
    foreach (`$encoded in `$replayBlocks) {
        `$block = Decode-ExecutionContextCode -Encoded `$encoded
        if (-not [string]::IsNullOrWhiteSpace(`$block)) {
            `$null = @(& ([scriptblock]::Create(`$block)))
        }
    }

    `$currentCode = Decode-ExecutionContextCode -Encoded `$currentBlock
    `$result = @(& ([scriptblock]::Create(`$currentCode)))
    Export-Clixml -LiteralPath '$resultPath' -InputObject ([pscustomobject]@{
        Success = `$true
        Result  = @(`$result)
    })
    exit 0
} catch {
    `$detail = if (`$_.Exception -and -not [string]::IsNullOrWhiteSpace([string]`$_.Exception.Message)) {
        [string]`$_.Exception.Message
    } else {
        ([string]`$_)
    }
    Set-Content -LiteralPath '$errorPath' -Value `$detail -Encoding UTF8
    exit 1
}
"@

    [System.IO.File]::WriteAllText($runnerPath, $runnerText, [System.Text.Encoding]::UTF8)

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $childExe
    $psi.Arguments = ('-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}"' -f $runnerPath.Replace('"', '""'))
    $psi.WorkingDirectory = $tempRoot
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $process = $null
    try {
        $process = [System.Diagnostics.Process]::Start($psi)
        if ($null -eq $process) {
            return @{
                Success = $false
                Error   = 'Failed to start subprocess host'
                Result  = $null
                Timeout = $false
            }
        }

        $completed = $process.WaitForExit($TimeoutMs)
        if (-not $completed) {
            Stop-ProcessTreeById -RootProcessId $process.Id -IncludeRoot
            try { $null = $process.WaitForExit(5000) } catch { }
            return @{
                Success = $false
                Error   = "Execution timeout after ${TimeoutMs}ms"
                Result  = $null
                Timeout = $true
            }
        }

        if ($process.ExitCode -ne 0) {
            $errorText = $null
            if (Test-Path -LiteralPath $errorPath) {
                $errorText = [System.IO.File]::ReadAllText($errorPath, [System.Text.Encoding]::UTF8)
            }
            if ([string]::IsNullOrWhiteSpace($errorText)) {
                $errorText = "Subprocess exited with code $($process.ExitCode)"
            }
            return @{
                Success = $false
                Error   = ([string]$errorText).Trim()
                Result  = $null
                Timeout = $false
            }
        }

        if (-not (Test-Path -LiteralPath $resultPath)) {
            return @{
                Success = $false
                Error   = 'Subprocess completed without a result payload'
                Result  = $null
                Timeout = $false
            }
        }

        $payload = Import-Clixml -LiteralPath $resultPath
        $result = if ($payload -and $payload.PSObject.Properties['Result']) { $payload.Result } else { $null }

        if ($PersistOnSuccess) {
            $ExecContext.ReplayStatements.Add([string]$Code) | Out-Null
        }

        return @{
            Success = $true
            Error   = $null
            Result  = $result
            Timeout = $false
        }
    } catch {
        return @{
            Success = $false
            Error   = $_.Exception.Message
            Result  = $null
            Timeout = $false
        }
    } finally {
        if ($process) {
            try {
                if (-not $process.HasExited) {
                    Stop-ProcessTreeById -RootProcessId $process.Id -IncludeRoot
                    $null = $process.WaitForExit(2000)
                }
            } catch {
            }
            $process.Dispose()
        }

        foreach ($path in @($runnerPath, $resultPath, $errorPath)) {
            try {
                if (-not [string]::IsNullOrWhiteSpace([string]$path) -and (Test-Path -LiteralPath $path)) {
                    Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
                }
            } catch {
            }
        }
    }
}

function Get-ExecutionContextEffectiveTimeoutMs {
    param(
        [hashtable]$ExecContext,
        [int]$RequestedTimeoutMs
    )

    $effectiveTimeoutMs = $RequestedTimeoutMs
    if ($effectiveTimeoutMs -le 0) {
        $effectiveTimeoutMs = 0
    }

    if ($null -eq $ExecContext -or -not $ExecContext.ContainsKey('GlobalTimeBudgetMs') -or -not $ExecContext.ContainsKey('ExecutionStopwatch')) {
        if ($effectiveTimeoutMs -le 0) { return $null }
        return [Math]::Max(1, [int]$effectiveTimeoutMs)
    }

    $budgetMs = 0
    try { $budgetMs = [int]$ExecContext.GlobalTimeBudgetMs } catch { $budgetMs = 0 }
    $stopwatch = $ExecContext.ExecutionStopwatch
    if ($budgetMs -le 0 -or $null -eq $stopwatch) {
        if ($effectiveTimeoutMs -le 0) { return $null }
        return [Math]::Max(1, [int]$effectiveTimeoutMs)
    }

    $remainingMs = $budgetMs
    try {
        $remainingMs = [int]([Math]::Floor([double]$budgetMs - [double]$stopwatch.ElapsedMilliseconds))
    } catch {
        $remainingMs = $budgetMs
    }

    if ($remainingMs -le 0) {
        return 0
    }

    if ($effectiveTimeoutMs -le 0) {
        return [Math]::Max(1, $remainingMs)
    }

    return [Math]::Max(1, [Math]::Min([int]$effectiveTimeoutMs, [int]$remainingMs))
}

function Invoke-InContext {
    param(
        [hashtable]$ExecContext,
        [string]$Code,
        [int]$TimeoutMs = 5000,
        [bool]$PersistOnSuccess = $true
    )

    $backend = if ($ExecContext -and $ExecContext.ContainsKey('Backend') -and -not [string]::IsNullOrWhiteSpace([string]$ExecContext.Backend)) {
        [string]$ExecContext.Backend
    } else {
        'Runspace'
    }

    $effectiveTimeoutMs = Get-ExecutionContextEffectiveTimeoutMs -ExecContext $ExecContext -RequestedTimeoutMs $TimeoutMs
    if ($null -ne $effectiveTimeoutMs -and $effectiveTimeoutMs -le 0) {
        return @{
            Success    = $false
            Error      = 'Execution timeout after global budget exhausted'
            Result     = $null
            Timeout    = $true
            StopReason = 'GlobalTimeBudgetExceeded'
        }
    }

    if ($backend -eq 'SubprocessReplay') {
        return (Invoke-InSubprocessReplayContext -ExecContext $ExecContext -Code $Code -TimeoutMs $effectiveTimeoutMs -PersistOnSuccess:$PersistOnSuccess)
    }

    try {
        $ps = [powershell]::Create()
        $ps.Runspace = $ExecContext.Runspace
        $ps.AddScript($Code) | Out-Null

        $asyncResult = $ps.BeginInvoke()
        $completed = $asyncResult.AsyncWaitHandle.WaitOne($effectiveTimeoutMs)

        if (-not $completed) {
            $ps.Stop()
            return @{
                Success = $false
                Error   = "Execution timeout after ${effectiveTimeoutMs}ms"
                Result  = $null
                Timeout = $true
                StopReason = 'ExecutionTimeout'
            }
        }

        $result = $ps.EndInvoke($asyncResult)

        if ($ps.HadErrors) {
            $errorMsg = (($ps.Streams.Error | ForEach-Object { $_.ToString() }) -join "`n")
            return @{
                Success = $false
                Error   = $errorMsg
                Result  = $null
                Timeout = $false
            }
        }

        return @{
            Success = $true
            Error   = $null
            Result  = $result
            Timeout = $false
        }
    }
    catch {
        return @{
            Success = $false
            Error   = $_.Exception.Message
            Result  = $null
            Timeout = $false
        }
    }
    finally {
        if ($ps) { $ps.Dispose() }
    }
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

function Test-ExecutionResultSequenceContainer {
    param($Value)

    if ($null -eq $Value) { return $false }

    if ($Value -is [System.Collections.ObjectModel.Collection[System.Management.Automation.PSObject]]) {
        return $true
    }

    if ($Value -is [System.Management.Automation.PSDataCollection[System.Management.Automation.PSObject]]) {
        return $true
    }

    return $false
}

function Get-ExecutionResultItems {
    param(
        $Value,
        [switch]$TreatArraysAsSequence
    )

    if ($null -eq $Value) { return @() }

    $isSequence = (Test-ExecutionResultSequenceContainer -Value $Value) -or
        ($TreatArraysAsSequence -and $Value -is [array])

    if ($isSequence) {
        return @($Value)
    }

    return @($Value)
}

function Normalize-ExecutionResultValue {
    param(
        $Value,
        [switch]$TreatArraysAsSequence
    )

    if ($null -eq $Value) { return $null }

    $isSequence = (Test-ExecutionResultSequenceContainer -Value $Value) -or
        ($TreatArraysAsSequence -and $Value -is [array])

    if (-not $isSequence) {
        return $Value
    }

    $items = @($Value)
    if ($items.Count -eq 0) {
        Write-Output -NoEnumerate @()
        return
    }
    if ($items.Count -eq 1) {
        $singleItem = $items[0]
        if ($singleItem -is [array]) {
            Write-Output -NoEnumerate $singleItem
            return
        }
        return $singleItem
    }

    Write-Output -NoEnumerate @($items)
}

function Get-VariableFromContext {
    param(
        [hashtable]$ExecContext,
        [string]$Name
    )
    $envActualName = Get-CFGEnvironmentVariableActualName -Name $Name
    if (-not [string]::IsNullOrWhiteSpace($envActualName)) {
        $envName = Get-CFGEnvironmentVariableLeafName -Name $envActualName
        if ([string]::IsNullOrWhiteSpace($envName)) {
            return $null
        }

        $escapedEnvName = $envName.Replace("'", "''")
        $envResult = Invoke-InContext -ExecContext $ExecContext -Code "[System.Environment]::GetEnvironmentVariable('$escapedEnvName','Process')"
        if (-not $envResult.Success) {
            return $null
        }
        return $envResult.Result
    }

    $psVar = $ExecContext.Runspace.SessionStateProxy.PSVariable.Get($Name)
    if ($null -eq $psVar) {
        return $null
    }

    $value = $psVar.Value
    if ($value -is [array]) {
        Write-Output -NoEnumerate $value
        return
    }
    return $value
}

function Get-NodeVariableValues {
    param(
        [hashtable]$ExecContext,
        $Node
    )

    $result = @{
        Read    = @{}
        Written = @{}
    }

    foreach ($varInfo in (Get-CFGNodeVarInfos -Node $Node -PropertyName 'VarsRead')) {
        $varName = $varInfo.Name
        $value = Get-VariableFromContext -ExecContext $ExecContext -Name $varName
        $result.Read[$varName] = $value
    }

    foreach ($varInfo in (Get-CFGNodeVarInfos -Node $Node -PropertyName 'VarsWritten')) {
        $varName = $varInfo.Name
        $value = Get-VariableFromContext -ExecContext $ExecContext -Name $varName
        $result.Written[$varName] = $value
    }

    return $result
}

function Format-VariableValue {
    param(
        $Value,
        [int]$Depth = 0
    )

    function Get-TextPreview {
        param(
            [string]$Text,
            [int]$MaxLen = 120
        )
        if ($null -eq $Text) { return '' }
        $clean = $Text -replace "`r", '\r' -replace "`n", '\n'
        if ($clean.Length -gt $MaxLen) {
            return $clean.Substring(0, $MaxLen - 3) + '...'
        }
        return $clean
    }

    function Get-ShallowValueSummary {
        param(
            $Item,
            [int]$TextMaxLen = 80
        )

        if ($null -eq $Item) {
            return '$null'
        }
        if ($Item -is [BlockedCommandPlaceholder]) {
            return $script:BlockedPlaceholderMarker
        }
        if ($Item -is [string]) {
            return "`"$(Get-TextPreview -Text $Item -MaxLen $TextMaxLen)`""
        }
        if ($Item -is [ValueType]) {
            return "$Item"
        }
        if ($Item -is [char[]]) {
            return "[Char[]] Count=$($Item.Length)"
        }
        if ($Item -is [byte[]]) {
            return "[Byte[]] Count=$($Item.Length)"
        }
        return "[$($Item.GetType().Name)]"
    }

    if ($null -eq $Value) {
        return '$null'
    }

    if ($Value -is [BlockedCommandPlaceholder]) {
        return $script:BlockedPlaceholderMarker
    }

    if ($Depth -lt 3 -and $Value -is [string]) {
        return "`"$(Get-TextPreview -Text $Value -MaxLen 120)`""
    }

    if ($Depth -lt 3 -and $Value -is [ValueType]) {
        return "$Value"
    }

    if ($Value -is [char[]]) {
        $count = $Value.Length
        $text = -join $Value
        $preview = Get-TextPreview -Text $text -MaxLen 160
        return "[Char[]] Count=$count `"$preview`""
    }

    if ($Value -is [byte[]]) {
        $count = $Value.Length
        $max = [Math]::Min(24, $count)
        if ($max -le 0) {
            return "[Byte[]] Count=0"
        }
        $hex = for ($i = 0; $i -lt $max; $i++) { '{0:X2}' -f $Value[$i] }
        $suffix = if ($count -gt $max) { ' ...' } else { '' }
        return "[Byte[]] Count=$count Hex=$($hex -join ' ')$suffix"
    }

    $type = $Value.GetType().Name

    if ($Depth -ge 3) {
        if ($Value -is [string]) {
            return "`"$(Get-TextPreview -Text $Value -MaxLen 80)`""
        }

        if ($Value -is [System.Collections.IDictionary]) {
            $pairs = New-Object System.Collections.Generic.List[string]
            $maxPairs = 2
            foreach ($k in $Value.Keys) {
                if ($pairs.Count -ge $maxPairs) { break }
                $pairs.Add("$k=$(Get-ShallowValueSummary -Item $Value[$k])")
            }
            $suffix = if ($Value.Count -gt $maxPairs) { '; ...' } else { '' }
            return "[$type] @{ $($pairs -join '; ')$suffix }"
        }

        if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
            $items = New-Object System.Collections.Generic.List[string]
            $maxItems = 2
            $count = $null
            if ($Value -is [array]) {
                $count = $Value.Length
            } elseif ($Value -is [System.Collections.ICollection]) {
                try { $count = [int]$Value.Count } catch { $count = $null }
            }

            $idx = 0
            $hasMore = $false
            foreach ($item in $Value) {
                if ($idx -ge $maxItems) {
                    $hasMore = $true
                    break
                }
                $items.Add((Get-ShallowValueSummary -Item $item))
                $idx++
            }
            if (-not $hasMore -and $null -ne $count -and $count -gt $maxItems) {
                $hasMore = $true
            }

            $suffix = if ($hasMore) { ', ...' } else { '' }
            $itemsText = $items -join ', '
            if ($null -ne $count) {
                return "[$type] Count=$count @($itemsText$suffix)"
            }
            return "[$type] @($itemsText$suffix)"
        }

        $objText = [string]$Value
        if (-not [string]::IsNullOrWhiteSpace($objText) -and $objText -ne $type -and $objText -notmatch '^System\\.') {
            return "[$type] $(Get-TextPreview -Text $objText -MaxLen 80)"
        }
        return "[$type]"
    }

    if ($Value -is [System.Collections.IDictionary]) {
        $maxPairs = 6
        $pairs = New-Object System.Collections.Generic.List[string]
        $i = 0
        foreach ($k in $Value.Keys) {
            if ($i -ge $maxPairs) { break }
            $vText = Format-VariableValue -Value $Value[$k] -Depth ($Depth + 1)
            $pairs.Add("$k=$vText")
            $i++
        }
        $suffix = if ($Value.Count -gt $maxPairs) { '; ...' } else { '' }
        return "[$type] @{ $($pairs -join '; ')$suffix }"
    }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $maxPreviewItems = 8
        $knownCount = $null

        if ($Value -is [array]) {
            $knownCount = $Value.Length
        } elseif ($Value -is [System.Collections.ICollection]) {
            try { $knownCount = [int]$Value.Count } catch { $knownCount = $null }
        }

        $items = New-Object System.Collections.Generic.List[string]
        $idx = 0
        $hasMore = $false
        foreach ($item in $Value) {
            if ($idx -ge $maxPreviewItems) {
                $hasMore = $true
                break
            }
            $items.Add((Format-VariableValue -Value $item -Depth ($Depth + 1)))
            $idx++
        }

        if (-not $hasMore -and $null -ne $knownCount -and $knownCount -gt $maxPreviewItems) {
            $hasMore = $true
        }

        $suffix = if ($hasMore) { ', ...' } else { '' }
        $itemsText = $items -join ', '
        if ($null -ne $knownCount) {
            return "[$type] Count=$knownCount @($itemsText$suffix)"
        }
        return "[$type] @($itemsText$suffix)"
    }

    if ($Value -is [string]) {
        return "`"$(Get-TextPreview -Text $Value -MaxLen 120)`""
    }

    if ($Value -is [ValueType]) {
        return "$Value"
    }

    $objText = [string]$Value
    if (-not [string]::IsNullOrWhiteSpace($objText) -and $objText -ne $type -and $objText -notmatch '^System\.') {
        $preview = Get-TextPreview -Text $objText -MaxLen 120
        return "[$type] $preview"
    }
    return "[$type]"
}

function Get-ExecutionLogMessageText {
    param($Message)

    if ($Message -is [scriptblock]) {
        try {
            return [string](& $Message)
        } catch {
            return "[LogMessageEvalError] $($_.Exception.Message)"
        }
    }

    if ($null -eq $Message) {
        return ''
    }

    return [string]$Message
}

function Flush-ExecutionLogBuffer {
    param([hashtable]$Context)

    if ($null -eq $Context -or [string]::IsNullOrWhiteSpace($Context.LogPath)) {
        return
    }

    if (-not $Context.ContainsKey('LogBufferBuilder') -or $null -eq $Context.LogBufferBuilder) {
        return
    }

    if ($Context.LogBufferBuilder.Length -le 0) {
        return
    }

    $text = $Context.LogBufferBuilder.ToString()
    [System.IO.File]::AppendAllText($Context.LogPath, $text, [System.Text.UTF8Encoding]::new($false))
    $null = $Context.LogBufferBuilder.Clear()
    $Context.LogBufferedLines = 0
    $Context.LogBufferedBytes = 0
}

function Write-ExecutionLog {
    param(
        [hashtable]$Context,
        $Message
    )

    if ($null -eq $Context -or [string]::IsNullOrWhiteSpace($Context.LogPath)) {
        return
    }

    if (-not $Context.ContainsKey('LogBufferBuilder') -or $null -eq $Context.LogBufferBuilder) {
        $Context.LogBufferBuilder = [System.Text.StringBuilder]::new()
    }
    if (-not $Context.ContainsKey('LogBufferedLines')) {
        $Context.LogBufferedLines = 0
    }
    if (-not $Context.ContainsKey('LogBufferedBytes')) {
        $Context.LogBufferedBytes = 0
    }

    $lineThreshold = if ($Context.ContainsKey('LogFlushLineThreshold') -and [int]$Context.LogFlushLineThreshold -gt 0) {
        [int]$Context.LogFlushLineThreshold
    } else {
        10
    }
    $byteThreshold = if ($Context.ContainsKey('LogFlushByteThreshold') -and [int]$Context.LogFlushByteThreshold -gt 0) {
        [int]$Context.LogFlushByteThreshold
    } else {
        4096
    }

    $messageText = Get-ExecutionLogMessageText -Message $Message
    $timestamp = Get-Date -Format "HH:mm:ss.fff"
    $logLine = "[$timestamp] $messageText"
    $newline = [System.Environment]::NewLine

    $null = $Context.LogBufferBuilder.Append($logLine)
    $null = $Context.LogBufferBuilder.Append($newline)
    $Context.LogBufferedLines = [int]$Context.LogBufferedLines + 1
    $Context.LogBufferedBytes = [int]$Context.LogBufferedBytes + [System.Text.Encoding]::UTF8.GetByteCount($logLine + $newline)

    if ($Context.LogBufferedLines -ge $lineThreshold -or $Context.LogBufferedBytes -ge $byteThreshold) {
        Flush-ExecutionLogBuffer -Context $Context
    }

    # Write-Host $logLine
}

function Initialize-ExecutionLogFile {
    param([string]$LogPath)

    if ([string]::IsNullOrWhiteSpace($LogPath)) {
        return
    }

    $parent = Split-Path -Path $LogPath -Parent
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
        $null = New-Item -ItemType Directory -Path $parent -Force
    }

    [System.IO.File]::WriteAllText($LogPath, '', [System.Text.UTF8Encoding]::new($false))
}

function Test-ExecutionLogDetailEnabled {
    param(
        [hashtable]$Context,
        [string]$FlagName
    )

    if ([string]::IsNullOrWhiteSpace($FlagName)) { return $true }
    if ($null -eq $Context) { return $false }
    if (-not $Context.ContainsKey($FlagName)) { return $true }
    return [bool]$Context[$FlagName]
}

function Get-NodeTextParseInfo {
    param(
        $Node,
        [hashtable]$Context,
        [string]$SourceText = $null
    )

    if (-not $Context.TextParseCache) {
        $Context.TextParseCache = @{}
    }
    if (-not $Context.TextParseCacheKeyByNodeId) {
        $Context.TextParseCacheKeyByNodeId = @{}
    }

    $nodeId = [int]$Node.Id
    $text = if ($PSBoundParameters.ContainsKey('SourceText') -and $null -ne $SourceText) {
        [string]$SourceText
    } else {
        [string]$Node.Text
    }

    if ($Context.TextParseCacheKeyByNodeId.ContainsKey($nodeId)) {
        $recentKey = [string]$Context.TextParseCacheKeyByNodeId[$nodeId]
        if (-not [string]::IsNullOrWhiteSpace($recentKey) -and $Context.TextParseCache.ContainsKey($recentKey)) {
            $recentResult = $Context.TextParseCache[$recentKey]
            if ($recentResult -and $recentResult.PSObject.Properties['SourceText'] -and [string]$recentResult.SourceText -ceq $text) {
                return $recentResult
            }
        }
    }

    $cacheKey = "${nodeId}:$text"
    if ($Context.TextParseCache.ContainsKey($cacheKey)) {
        $Context.TextParseCacheKeyByNodeId[$nodeId] = $cacheKey
        return $Context.TextParseCache[$cacheKey]
    }

    if ([string]::IsNullOrWhiteSpace($text)) {
        $result = [PSCustomObject]@{
            Success    = $false
            Ast        = $null
            Tokens     = @()
            Errors     = @()
            Error      = "Node.Text is empty"
            SourceText = $text
        }
        $Context.TextParseCache[$cacheKey] = $result
        $Context.TextParseCacheKeyByNodeId[$nodeId] = $cacheKey
        return $result
    }

    $errors = $null
    $tokens = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$errors)

    $parseErrors = @($errors)
    $success = ($parseErrors.Count -eq 0)
    $errorText = if ($success) { $null } else { ($parseErrors | ForEach-Object { $_.Message }) -join "; " }

    $result = [PSCustomObject]@{
        Success    = $success
        Ast        = $ast
        Tokens     = @($tokens)
        Errors     = $parseErrors
        Error      = $errorText
        SourceText = $text
    }

    $Context.TextParseCache[$cacheKey] = $result
    $Context.TextParseCacheKeyByNodeId[$nodeId] = $cacheKey
    return $result
}

function Convert-CodeForCurrentScope {
    param(
        [string]$Code,
        [hashtable]$Context
    )

    if ($Context.CurrentScopePrefix -and $Context.ScopeStack.Count -gt 0) {
        $currentScope = $Context.ScopeStack[-1]
        if ($currentScope.LocalVars -and $currentScope.LocalVars.Count -gt 0) {
            return Convert-VariableNames -Code $Code -ScopePrefix $currentScope.ScopePrefix -LocalVarNames $currentScope.LocalVars
        }
    }
    return $Code
}

function Get-CFGEnvironmentVariableActualName {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) { return $null }

    $text = [string]$Name
    if ($text.StartsWith('$')) {
        $text = $text.Substring(1)
    }

    if ($text -match '^(?i)env:(.+)$') {
        $leafName = [string]$Matches[1]
        if ([string]::IsNullOrWhiteSpace($leafName)) { return $null }
        return ('env:' + $leafName)
    }

    return $null
}

function Get-CFGEnvironmentVariableLeafName {
    param([string]$Name)

    $actualName = Get-CFGEnvironmentVariableActualName -Name $Name
    if ([string]::IsNullOrWhiteSpace($actualName)) { return $null }
    return $actualName.Substring(4)
}

function Register-CFGTrackedEnvironmentVariable {
    param(
        [hashtable]$Context,
        [string]$ActualName
    )

    if ($null -eq $Context) { return }

    $envActualName = Get-CFGEnvironmentVariableActualName -Name $ActualName
    if ([string]::IsNullOrWhiteSpace($envActualName)) { return }

    if (-not $Context.ContainsKey('TrackedEnvironmentVariables') -or $null -eq $Context.TrackedEnvironmentVariables) {
        $Context.TrackedEnvironmentVariables = @{}
    }

    $Context.TrackedEnvironmentVariables[$envActualName] = $true
}

function ConvertTo-SingleQuotedHereStringLiteral {
    param([string]$Text)

    $content = if ($null -eq $Text) { '' } else { [string]$Text }
    $content = $content.TrimEnd("`r", "`n")
    return "@'`r`n$content`r`n'@"
}

function Get-BlockedPlaceholderPreservedText {
    param($Value)

    if ($null -eq $Value) { return $null }

    if ($Value -is [BlockedCommandPlaceholder]) {
        if ([string]::IsNullOrWhiteSpace([string]$Value.PreservedText)) { return $null }
        return [string]$Value.PreservedText
    }

    $base = Get-SafePSBaseObject -Value $Value
    if ($null -ne $base -and $base -is [BlockedCommandPlaceholder]) {
        if ([string]::IsNullOrWhiteSpace([string]$base.PreservedText)) { return $null }
        return [string]$base.PreservedText
    }

    return $null
}

function Get-RebuiltNodeTextSegment {
    param(
        $Node,
        [hashtable]$Context,
        [hashtable]$ResolvedValues = $null,
        $CommandInfo = $null,
        [int]$RangeStart = 0,
        [int]$RangeEnd = -1
    )

    if ($null -eq $Node -or [string]::IsNullOrWhiteSpace([string]$Node.Text)) {
        return $null
    }

    $nodeText = [string]$Node.Text
    if ($RangeEnd -lt 0 -or $RangeEnd -gt $nodeText.Length) {
        $RangeEnd = $nodeText.Length
    }
    if ($RangeStart -lt 0) { $RangeStart = 0 }
    if ($RangeStart -ge $RangeEnd) {
        return $nodeText
    }

    $segment = $nodeText.Substring($RangeStart, $RangeEnd - $RangeStart)
    $replacements = @()

    if ($ResolvedValues) {
        foreach ($entry in $ResolvedValues.GetEnumerator()) {
            $key = [string]$entry.Key
            if ($key -notmatch '^local:\d+:(\d+):(\d+)$') { continue }

            $start = [int]$Matches[1]
            $end = [int]$Matches[2]
            if ($start -lt $RangeStart -or $end -gt $RangeEnd -or $end -le $start) { continue }

            $valueText = [string]$entry.Value
            if ([string]::IsNullOrWhiteSpace($valueText) -or $valueText -eq $script:BlockedPlaceholderMarker) { continue }

            $replacements += [PSCustomObject]@{
                Start = $start
                End   = $end
                Text  = $valueText
                Span  = ($end - $start)
                Kind  = 'Resolved'
            }
        }
    }

    if ($CommandInfo -and $CommandInfo.HasCommand -and
        $CommandInfo.PSObject.Properties['ResolutionKind'] -and
        [string]$CommandInfo.ResolutionKind -ne 'Direct' -and
        $CommandInfo.PSObject.Properties['CommandElementAst'] -and
        $null -ne $CommandInfo.CommandElementAst) {
        $nameAst = $CommandInfo.CommandElementAst
        $start = [int]$nameAst.Extent.StartOffset
        $end = [int]$nameAst.Extent.EndOffset
        if ($start -ge $RangeStart -and $end -le $RangeEnd -and $end -gt $start) {
            $replacements += [PSCustomObject]@{
                Start = $start
                End   = $end
                Text  = [string]$CommandInfo.ResolvedName
                Span  = ($end - $start)
                Kind  = 'CommandName'
            }
        }
    }

    if ($replacements.Count -eq 0) {
        return $segment
    }

    $selected = New-Object System.Collections.Generic.List[object]
    foreach ($candidate in @($replacements | Sort-Object @{ Expression = { -$_.Span } }, Start, End)) {
        $overlap = $false
        foreach ($existing in $selected) {
            if ($candidate.Start -lt $existing.End -and $candidate.End -gt $existing.Start) {
                $overlap = $true
                break
            }
        }
        if (-not $overlap) {
            $selected.Add($candidate) | Out-Null
        }
    }

    $result = $segment
    foreach ($replacement in @($selected | Sort-Object Start -Descending)) {
        $localStart = $replacement.Start - $RangeStart
        $localEnd = $replacement.End - $RangeStart
        $result = $result.Substring(0, $localStart) + $replacement.Text + $result.Substring($localEnd)
    }

    return $result
}

function Get-BlockedPlaceholderPreservedValueText {
    param(
        $Node,
        [hashtable]$Context,
        [hashtable]$ResolvedValues = $null,
        $CommandInfo = $null
    )

    if ($null -eq $Node -or [string]::IsNullOrWhiteSpace([string]$Node.Text)) {
        return $null
    }

    $parseInfo = Get-NodeTextParseInfo -Node $Node -Context $Context
    if ($parseInfo.Success -and $parseInfo.Ast) {
        $statement = Get-FirstStatementFromScriptAst -ScriptAst $parseInfo.Ast
        if ($statement -is [System.Management.Automation.Language.AssignmentStatementAst] -and $statement.Right -and $statement.Right.Extent) {
            return Get-RebuiltNodeTextSegment -Node $Node -Context $Context -ResolvedValues $ResolvedValues -CommandInfo $CommandInfo -RangeStart $statement.Right.Extent.StartOffset -RangeEnd $statement.Right.Extent.EndOffset
        }
    }

    return (Get-RebuiltNodeTextSegment -Node $Node -Context $Context -ResolvedValues $ResolvedValues -CommandInfo $CommandInfo)
}

function Get-PreservedDynamicInvokeCommandText {
    param(
        $Node,
        [string]$ArgCode,
        [string]$DisplayArgCode,
        [string]$PreservedArgumentText
    )

    if ($null -eq $Node -or [string]::IsNullOrWhiteSpace([string]$Node.Text)) { return $null }
    if ([string]::IsNullOrWhiteSpace($PreservedArgumentText)) { return [string]$Node.Text }

    $nodeText = [string]$Node.Text
    foreach ($candidate in @($DisplayArgCode, $ArgCode)) {
        if ([string]::IsNullOrWhiteSpace([string]$candidate)) { continue }
        $idx = $nodeText.IndexOf([string]$candidate, [System.StringComparison]::Ordinal)
        if ($idx -lt 0) { continue }

        return $nodeText.Substring(0, $idx) + $PreservedArgumentText + $nodeText.Substring($idx + $candidate.Length)
    }

    return $nodeText
}

function Format-LiteralizedCommandValue {
    param($Value)

    if ($Value -is [string] -and $Value -match "[`r`n]") {
        return (ConvertTo-SingleQuotedHereStringLiteral -Text $Value)
    }

    return (Format-ResolvableValue $Value)
}

function Test-SafeLiteralizableAssignmentAst {
    param($StatementAst)

    if ($null -eq $StatementAst -or $StatementAst -isnot [System.Management.Automation.Language.AssignmentStatementAst]) {
        return $null
    }

    if ($StatementAst.Left -isnot [System.Management.Automation.Language.VariableExpressionAst]) {
        return $null
    }

    if ($null -eq $StatementAst.Right -or -not $StatementAst.Right.Extent) {
        return $null
    }

    $normalized = [regex]::Replace([string]$StatementAst.Right.Extent.Text, '\s+', ' ').Trim().ToLowerInvariant()
    $pattern = $null

    switch -Regex ($normalized) {
        '^whoami$' {
            $pattern = 'whoami'
            break
        }
        '^hostname$' {
            $pattern = 'hostname'
            break
        }
        '^ipconfig /all \| out-string$' {
            $pattern = 'ipconfig_all_out_string'
            break
        }
        '^(get-wmiobject|gwmi) -class win32_computersystem \| out-string$' {
            $pattern = 'wmi_computersystem_out_string'
            break
        }
    }

    if (-not $pattern) {
        return $null
    }

    return [PSCustomObject]@{
        Pattern      = $pattern
        VariableName = [string]$StatementAst.Left.VariablePath.UserPath
        StartOffset  = $StatementAst.Right.Extent.StartOffset
        EndOffset    = $StatementAst.Right.Extent.EndOffset
        OriginalText = [string]$StatementAst.Right.Extent.Text
    }
}

function Resolve-AssignmentActualVariableName {
    param(
        [hashtable]$Context,
        [string]$VariableName
    )

    if ($null -eq $VariableName) {
        return $VariableName
    }

    if ($Context.ScopeStack.Count -gt 0) {
        $currentScope = $Context.ScopeStack[-1]
        if ($currentScope -and $currentScope.LocalVars -and $VariableName -in $currentScope.LocalVars) {
            return $currentScope.ScopePrefix + $VariableName
        }
    }

    return $VariableName
}

function Test-CFGVariableNameAvailable {
    param([AllowNull()][string]$Name)

    return ($null -ne $Name)
}

function Resolve-VariableExpressionActualName {
    param(
        $VariableExpressionAst,
        [hashtable]$Context
    )

    if ($null -eq $VariableExpressionAst -or $null -eq $VariableExpressionAst.VariablePath) {
        return $null
    }

    $userPath = $VariableExpressionAst.VariablePath.UserPath
    if ($null -eq $userPath) {
        return $null
    }

    $actualName = $null
    if ($VariableExpressionAst.Extent) {
        $actualName = Get-CFGEnvironmentVariableActualName -Name ([string]$VariableExpressionAst.Extent.Text)
    }
    if (-not [string]::IsNullOrWhiteSpace($actualName)) {
        return $actualName
    }

    return (Resolve-AssignmentActualVariableName -Context $Context -VariableName ([string]$userPath))
}

function Ensure-CFGBlockedTaintMap {
    param([hashtable]$Context)

    if ($null -eq $Context) { return }
    if (-not $Context.ContainsKey('BlockedTaintedVariables') -or $null -eq $Context.BlockedTaintedVariables) {
        $Context.BlockedTaintedVariables = @{}
    }
}

function Set-CFGVariableBlockedTaint {
    param(
        [hashtable]$Context,
        [AllowNull()][string]$ActualName,
        [string]$Reason = 'blocked_dependency'
    )

    if ($null -eq $Context -or $null -eq $ActualName) { return }
    Ensure-CFGBlockedTaintMap -Context $Context
    $Context.BlockedTaintedVariables[[string]$ActualName] = $Reason
}

function Clear-CFGVariableBlockedTaint {
    param(
        [hashtable]$Context,
        [AllowNull()][string]$ActualName
    )

    if ($null -eq $Context -or $null -eq $ActualName) { return }
    Ensure-CFGBlockedTaintMap -Context $Context
    $null = $Context.BlockedTaintedVariables.Remove([string]$ActualName)
}

function Test-CFGVariableBlockedTaint {
    param(
        [hashtable]$Context,
        [AllowNull()][string]$ActualName
    )

    if ($null -eq $Context -or $null -eq $ActualName) { return $false }
    Ensure-CFGBlockedTaintMap -Context $Context
    return $Context.BlockedTaintedVariables.ContainsKey([string]$ActualName)
}

function Get-AstReferencedActualVariableNames {
    param(
        $Ast,
        [hashtable]$Context
    )

    if ($null -eq $Ast) { return @() }

    $names = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $varAsts = @($Ast.FindAll({
            param($n)
            $n -is [System.Management.Automation.Language.VariableExpressionAst]
        }, $true))

    foreach ($varAst in $varAsts) {
        $actualName = Resolve-VariableExpressionActualName -VariableExpressionAst $varAst -Context $Context
        if ($null -eq $actualName) { continue }
        if ($seen.Add([string]$actualName)) {
            $names.Add([string]$actualName) | Out-Null
        }
    }

    return @($names)
}

function Test-ValueContainsBlockedPlaceholder {
    param($Value)

    if ($null -eq $Value) { return $false }

    if (Test-ExecutionResultSequenceContainer -Value $Value) {
        $Value = Normalize-ExecutionResultValue -Value $Value
    }

    if ($Value -is [BlockedCommandPlaceholder]) { return $true }
    $baseObject = Get-SafePSBaseObject -Value $Value
    if ($null -ne $baseObject -and $baseObject -is [BlockedCommandPlaceholder]) {
        return $true
    }

    if ($Value -is [string]) {
        return ([string]$Value -eq $script:BlockedPlaceholderMarker)
    }

    if ($Value -is [array]) {
        foreach ($item in $Value) {
            if (Test-ValueContainsBlockedPlaceholder -Value $item) {
                return $true
            }
        }
    }

    return $false
}

function Test-AstDependsOnBlockedTaint {
    param(
        $Ast,
        [hashtable]$Context
    )

    if ($null -eq $Ast -or $null -eq $Context) { return $false }

    foreach ($actualName in @(Get-AstReferencedActualVariableNames -Ast $Ast -Context $Context)) {
        if (Test-CFGVariableBlockedTaint -Context $Context -ActualName $actualName) {
            return $true
        }
    }

    return $false
}

function Update-CFGAssignmentBlockedTaint {
    param(
        $Node,
        [hashtable]$Context
    )

    if ($null -eq $Node -or $null -eq $Context) { return }
    if ($Node.Ast -isnot [System.Management.Automation.Language.AssignmentStatementAst]) { return }
    if ($Node.Ast.Left -isnot [System.Management.Automation.Language.VariableExpressionAst]) { return }
    if ($null -eq $Node.Ast.Right) { return }

    $actualName = Resolve-VariableExpressionActualName -VariableExpressionAst $Node.Ast.Left -Context $Context
    if ($null -eq $actualName) { return }

    $isTainted = Test-AstDependsOnBlockedTaint -Ast $Node.Ast.Right -Context $Context
    $storedValue = Get-VariableFromContext -ExecContext $Context.ExecContext -Name $actualName
    if (-not $isTainted) {
        $isTainted = Test-ValueContainsBlockedPlaceholder -Value $storedValue
    }

    if ($isTainted) {
        Set-CFGVariableBlockedTaint -Context $Context -ActualName $actualName
    } else {
        Clear-CFGVariableBlockedTaint -Context $Context -ActualName $actualName
    }
}

function Test-ResolvableAstHasImplicitSideEffects {
    param($Ast)

    if ($null -eq $Ast -or -not $Ast.PSObject.Methods['FindAll']) {
        return $false
    }

    $sideEffectAst = @($Ast.FindAll({
                param($n)
                $n -is [System.Management.Automation.Language.AssignmentStatementAst]
            }, $true) | Select-Object -First 1)

    return ($sideEffectAst.Count -gt 0)
}

function Get-UnwrappedAssignmentExpressionAst {
    param($Ast)

    $current = $Ast
    while ($null -ne $current) {
        if ($current -is [System.Management.Automation.Language.ParenExpressionAst]) {
            $pipeline = $current.Pipeline
            if ($pipeline -and $pipeline.PipelineElements.Count -eq 1 -and
                $pipeline.PipelineElements[0] -is [System.Management.Automation.Language.CommandExpressionAst]) {
                $current = $pipeline.PipelineElements[0].Expression
                continue
            }
        }
        break
    }

    return $current
}

function Resolve-AssignmentScriptBlockMapping {
    param(
        $AssignmentAst,
        [hashtable]$Context
    )

    if ($null -eq $AssignmentAst -or $AssignmentAst -isnot [System.Management.Automation.Language.AssignmentStatementAst]) {
        return $null
    }
    if ($AssignmentAst.Left -isnot [System.Management.Automation.Language.VariableExpressionAst]) {
        return $null
    }

    $variableName = [string]$AssignmentAst.Left.VariablePath.UserPath
    if ([string]::IsNullOrWhiteSpace($variableName)) {
        return $null
    }

    $rightAst = Get-UnwrappedAssignmentExpressionAst -Ast $AssignmentAst.Right
    if ($null -eq $rightAst) {
        return [PSCustomObject]@{
            VariableName = $variableName
            BlockName    = $null
        }
    }

    $blockName = $null
    if ($rightAst -is [System.Management.Automation.Language.ScriptBlockExpressionAst] -or
        $rightAst -is [System.Management.Automation.Language.VariableExpressionAst]) {
        $blockName = Get-ScriptBlockNameFromAst -Ast $rightAst -Context $Context
    }

    return [PSCustomObject]@{
        VariableName = $variableName
        BlockName    = $blockName
    }
}

function Update-VariableScriptBlockMappingAfterNodeExecution {
    param(
        $Node,
        [hashtable]$Context
    )

    if ($null -eq $Node -or $null -eq $Context -or -not $Node.Ast) { return }

    $mapping = Resolve-AssignmentScriptBlockMapping -AssignmentAst $Node.Ast -Context $Context
    if ($null -eq $mapping -or [string]::IsNullOrWhiteSpace([string]$mapping.VariableName)) {
        return
    }

    $variableName = [string]$mapping.VariableName
    $blockName = if ([string]::IsNullOrWhiteSpace([string]$mapping.BlockName)) { $null } else { [string]$mapping.BlockName }

    if ($blockName) {
        $Context.VarToBlockMapping[$variableName] = $blockName
        Write-ExecutionLog -Context $Context -Message "  [MAPPING] `$$variableName -> $blockName"
        return
    }

    if ($Context.VarToBlockMapping -and $Context.VarToBlockMapping.ContainsKey($variableName)) {
        $null = $Context.VarToBlockMapping.Remove($variableName)
        Write-ExecutionLog -Context $Context -Message "  [MAPPING] Removed `$$variableName scriptblock mapping"
    }
}

function Record-LiteralizedCommandResult {
    param(
        $Node,
        [hashtable]$Context
    )

    if ($null -eq $Node -or $null -eq $Context -or $null -eq $Node.Ast) {
        return
    }

    if ($Node.PSObject.Properties['RuntimeGenerated'] -and [bool]$Node.RuntimeGenerated) {
        return
    }

    $info = Test-SafeLiteralizableAssignmentAst -StatementAst $Node.Ast
    if (-not $info) {
        return
    }

    $actualVarName = Resolve-AssignmentActualVariableName -Context $Context -VariableName $info.VariableName
    $value = Get-VariableFromContext -ExecContext $Context.ExecContext -Name $actualVarName
    if (Test-CFGVariableBlockedTaint -Context $Context -ActualName $actualVarName) {
        return
    }

    if (-not $Context.ContainsKey('LiteralizedCommandResults') -or $null -eq $Context.LiteralizedCommandResults) {
        $Context.LiteralizedCommandResults = @()
    }

    $Context.LiteralizedCommandResults += [PSCustomObject]@{
        NodeId           = $Node.Id
        VariableName     = $info.VariableName
        ActualVariable   = $actualVarName
        Pattern          = $info.Pattern
        StartOffset      = $info.StartOffset
        EndOffset        = $info.EndOffset
        OriginalText     = $info.OriginalText
        ReplacementText  = (Format-LiteralizedCommandValue -Value $value)
        Timestamp        = Get-Date
    }

    Write-ExecutionLog -Context $Context -Message "  [LITERALIZE] Safe command folded for `$${0}: {1}" -f $info.VariableName, $info.Pattern
}

function Test-SensitiveSinkText {
    param(
        [AllowNull()][string]$Text,
        [string]$SinkKind = 'Generic'
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $false
    }

    $trimmed = $Text.Trim()
    $isUrlLike = ($trimmed -match '^(?i)(?:https?|ftp)://') -or
        ($trimmed -match '^(?:(?:\d{1,3}\.){3}\d{1,3})(?::\d+)?(?:/.*)?$') -or
        ($trimmed -match '^(?i:[A-Za-z0-9.-]+\.[A-Za-z]{2,})(?:[:/].*)?$')
    $isProcessArgLike = $trimmed -match '(?i)(?:https?://|\.hta\b|-enc(?:odedcommand)?\b|-command\b|mshta(?:\.exe)?|powershell(?:\.exe)?|pwsh(?:\.exe)?|wscript(?:\.exe)?|cscript(?:\.exe)?|cmd(?:\.exe)?\s+/c)'
    $isRegistryLike = $trimmed -match '^(?i:(?:registry::)?(?:hkcu|hklm|hkcr|hku|hkcc):\\|hkey_(?:current_user|local_machine|classes_root|users|current_config)\\)'
    $isFilePathLike = ($trimmed -match '^(?i:[a-z]:\\)') -or
        ($trimmed -match '^\\\\[^\\]+\\[^\\]+') -or
        ($trimmed -match '^(?i)(?:\.{1,2}\\|~\\|\$env:[A-Za-z_][A-Za-z0-9_]*\\|%[A-Za-z_][A-Za-z0-9_]*%\\)') -or
        (($trimmed -match '[\\/]' -or $trimmed -match '(?i)^(?:temp|appdata|programdata|desktop|documents|downloads|startup|system32|syswow64)$') -and
            $trimmed -notmatch '^(?i)(?:https?|ftp)://')
    if ($trimmed -match '^[\\/]+[*?]') {
        $isFilePathLike = $false
    }
    $isCommandTextLike = ($trimmed -match '(?i)\b(?:invoke-expression|iex|start-process|invoke-webrequest|invoke-restmethod|downloadstring|downloadfile|set-itemproperty|new-itemproperty|reg\s+add|reg\s+query|reg\s+delete|cmd(?:\.exe)?|powershell(?:\.exe)?|pwsh(?:\.exe)?)\b')
    $isLauncherArgLike = $isProcessArgLike -or
        ($trimmed -match '(?i)(?:\s|^)(?:/c|/k|-command|-file|-f|-enc|-encodedcommand|javascript:|vbscript:|http://|https://|\\\\)')

    switch ($SinkKind) {
        'Url' { return $isUrlLike }
        'Host' { return ($trimmed -match '^(?:(?:\d{1,3}\.){3}\d{1,3}|[A-Za-z0-9.-]+\.[A-Za-z]{2,})$') }
        'StartProcessArgs' { return ($isProcessArgLike -or $isUrlLike) }
        'LauncherArgs' { return ($isLauncherArgLike -or $isUrlLike -or $isFilePathLike) }
        'CommandText' { return ($isCommandTextLike -or $isUrlLike -or $isFilePathLike -or $isRegistryLike) }
        'FilePath' { return $isFilePathLike }
        'DirectoryPath' { return $isFilePathLike }
        'RegKey' { return $isRegistryLike }
        default { return ($isUrlLike -or $isProcessArgLike -or $isFilePathLike) }
    }
}

function Get-SensitiveSinkValueText {
    param($Value)

    if ($null -eq $Value) { return $null }

    $materialized = Convert-DynamicInvocationValueToScriptText -Value $Value
    if ($materialized -and $materialized.Success -and -not [string]::IsNullOrWhiteSpace([string]$materialized.Text)) {
        return [string]$materialized.Text
    }

    try {
        $text = [string]$Value
    } catch {
        return $null
    }

    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    return $text
}

function Get-ResolvedCommandArgumentEntries {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [hashtable]$Context,
        [int]$CallerNodeId = -1
    )

    $entries = @()
    if (-not $CommandAst -or -not $CommandAst.CommandElements) {
        return @()
    }

    $positionalIndex = 0
    for ($i = 1; $i -lt $CommandAst.CommandElements.Count; $i++) {
        $elem = $CommandAst.CommandElements[$i]

        if ($elem -is [System.Management.Automation.Language.CommandParameterAst]) {
            $argAst = $elem.Argument
            if (-not $argAst -and ($i + 1) -lt $CommandAst.CommandElements.Count -and
                $CommandAst.CommandElements[$i + 1] -isnot [System.Management.Automation.Language.CommandParameterAst]) {
                $i++
                $argAst = $CommandAst.CommandElements[$i]
            }

            $resolved = Resolve-InvocationArgumentValue -ArgumentAst $argAst -Context $Context -CallerNodeId $CallerNodeId
            $entries += [PSCustomObject]@{
                Kind    = 'Named'
                Name    = [string]$elem.ParameterName
                Position = $null
                Ast     = $argAst
                Success = [bool]$resolved.Success
                Value   = $resolved.Value
            }
            continue
        }

        $resolved = Resolve-InvocationArgumentValue -ArgumentAst $elem -Context $Context -CallerNodeId $CallerNodeId
        $entries += [PSCustomObject]@{
            Kind    = 'Positional'
            Name    = $null
            Position = $positionalIndex
            Ast     = $elem
            Success = [bool]$resolved.Success
            Value   = $resolved.Value
        }
        $positionalIndex++
    }

    return @($entries)
}

function Get-SensitiveCommandReplacementRecord {
    param(
        $Node,
        [hashtable]$Context,
        $CommandInfo = $null
    )

    $commandAst = if ($CommandInfo -and $CommandInfo.PSObject.Properties['Ast'] -and $CommandInfo.Ast -is [System.Management.Automation.Language.CommandAst]) {
        $CommandInfo.Ast
    } elseif ($Node -and $Node.Ast -is [System.Management.Automation.Language.CommandAst]) {
        $Node.Ast
    } else {
        $null
    }
    if ($null -eq $commandAst) { return $null }

    $commandName = if ($CommandInfo -and $CommandInfo.PSObject.Properties['ResolvedName'] -and
        -not [string]::IsNullOrWhiteSpace([string]$CommandInfo.ResolvedName)) {
        [string]$CommandInfo.ResolvedName
    } else {
        Convert-DynamicCommandCandidateToName -Value $commandAst.GetCommandName()
    }
    if ([string]::IsNullOrWhiteSpace($commandName)) { return $null }

    $entries = @(Get-ResolvedCommandArgumentEntries -CommandAst $commandAst -Context $Context -CallerNodeId $Node.Id)
    if ($entries.Count -eq 0) { return $null }

    $getNamed = {
        param([string[]]$Names)
        foreach ($entry in @($entries)) {
            if ($entry.Kind -ne 'Named') { continue }
            foreach ($name in @($Names)) {
                if (-not [string]::IsNullOrWhiteSpace($name) -and $entry.Name -and $entry.Name.Equals($name, [System.StringComparison]::OrdinalIgnoreCase)) {
                    return $entry
                }
            }
        }
        return $null
    }
    $getPositional = {
        param([int]$Position)
        foreach ($entry in @($entries)) {
            if ($entry.Kind -eq 'Positional' -and [int]$entry.Position -eq $Position) {
                return $entry
            }
        }
        return $null
    }

    $targets = @()
    switch ($commandName.ToLowerInvariant()) {
        { $_ -in @('invoke-webrequest', 'iwr', 'curl', 'wget', 'invoke-restmethod', 'irm') } {
            $target = & $getNamed @('Uri', 'Url')
            if (-not $target) { $target = & $getPositional 0 }
            if ($target -and $target.Ast) {
                $targets += [PSCustomObject]@{ Entry = $target; SinkKind = 'Url'; SinkType = 'CommandWebRequest' }
            }

            $outFileTarget = & $getNamed @('OutFile')
            if ($outFileTarget -and $outFileTarget.Ast) {
                $targets += [PSCustomObject]@{ Entry = $outFileTarget; SinkKind = 'FilePath'; SinkType = 'CommandWebRequestOutFile' }
            }
        }
        'start-bitstransfer' {
            $target = & $getNamed @('Source')
            if ($target -and $target.Ast) {
                $targets += [PSCustomObject]@{ Entry = $target; SinkKind = 'Url'; SinkType = 'CommandBitsSource' }
            }

            $destinationTarget = & $getNamed @('Destination')
            if ($destinationTarget -and $destinationTarget.Ast) {
                $targets += [PSCustomObject]@{ Entry = $destinationTarget; SinkKind = 'FilePath'; SinkType = 'CommandBitsDestination' }
            }
        }
        { $_ -in @('start-process', 'start', 'saps') } {
            $filePathEntry = & $getNamed @('FilePath')
            if (-not $filePathEntry) { $filePathEntry = & $getPositional 0 }
            $argListEntry = & $getNamed @('ArgumentList')
            if (-not $argListEntry) { $argListEntry = & $getPositional 1 }
            $workingDirectoryEntry = & $getNamed @('WorkingDirectory')
            $filePathText = if ($filePathEntry) { Get-SensitiveSinkValueText -Value $filePathEntry.Value } else { $null }

            if ($filePathEntry -and $filePathEntry.Ast) {
                $targets += [PSCustomObject]@{ Entry = $filePathEntry; SinkKind = 'FilePath'; SinkType = 'CommandStartProcessFilePath' }
            }
            if ($workingDirectoryEntry -and $workingDirectoryEntry.Ast) {
                $targets += [PSCustomObject]@{ Entry = $workingDirectoryEntry; SinkKind = 'DirectoryPath'; SinkType = 'CommandStartProcessWorkingDirectory' }
            }
            if ($argListEntry -and $argListEntry.Ast -and
                $filePathText -match '^(?i)(?:mshta|powershell|pwsh|cmd|wscript|cscript)(?:\.exe)?$') {
                $targets += [PSCustomObject]@{ Entry = $argListEntry; SinkKind = 'LauncherArgs'; SinkType = 'CommandStartProcessArgs' }
            }
        }
        { $_ -in @('set-content', 'sc', 'add-content', 'ac', 'clear-content', 'clc', 'get-content', 'gc', 'type', 'cat', 'new-item', 'ni', 'remove-item', 'rm', 'ri', 'del', 'erase', 'rd', 'invoke-item', 'ii') } {
            $target = & $getNamed @('LiteralPath', 'Path', 'LP')
            if (-not $target) { $target = & $getPositional 0 }
            if ($target -and $target.Ast) {
                $targets += [PSCustomObject]@{ Entry = $target; SinkKind = 'FilePath'; SinkType = 'CommandPath' }
            }
        }
        'out-file' {
            $target = & $getNamed @('FilePath', 'LiteralPath', 'Path')
            if (-not $target) { $target = & $getPositional 0 }
            if ($target -and $target.Ast) {
                $targets += [PSCustomObject]@{ Entry = $target; SinkKind = 'FilePath'; SinkType = 'CommandOutFilePath' }
            }
        }
        { $_ -in @('copy-item', 'copy', 'cp', 'cpi', 'move-item', 'mv', 'mi') } {
            $sourceTarget = & $getNamed @('LiteralPath', 'Path', 'LP')
            if (-not $sourceTarget) { $sourceTarget = & $getPositional 0 }
            $destinationTarget = & $getNamed @('Destination', 'Dest')
            if (-not $destinationTarget) { $destinationTarget = & $getPositional 1 }

            if ($sourceTarget -and $sourceTarget.Ast) {
                $targets += [PSCustomObject]@{ Entry = $sourceTarget; SinkKind = 'FilePath'; SinkType = 'CommandSourcePath' }
            }
            if ($destinationTarget -and $destinationTarget.Ast) {
                $targets += [PSCustomObject]@{ Entry = $destinationTarget; SinkKind = 'FilePath'; SinkType = 'CommandDestinationPath' }
            }
        }
        { $_ -in @('set-itemproperty', 'new-itemproperty', 'remove-itemproperty') } {
            $target = & $getNamed @('LiteralPath', 'Path', 'LP')
            if (-not $target) { $target = & $getPositional 0 }
            if ($target -and $target.Ast) {
                $targets += [PSCustomObject]@{ Entry = $target; SinkKind = 'RegKey'; SinkType = 'CommandRegistryPath' }
            }
        }
        'nslookup' {
            $target = & $getPositional 0
            if ($target -and $target.Ast) {
                $targets += [PSCustomObject]@{ Entry = $target; SinkKind = 'Host'; SinkType = 'CommandNslookup' }
            }
        }
    }

    if ($targets.Count -eq 0) { return $null }

    $replacementText = [string]$commandAst.Extent.Text
    $localStart = [int]$commandAst.Extent.StartOffset
    $applied = @()
    foreach ($target in @($targets)) {
        $entry = $target.Entry
        if (-not $entry -or -not $entry.Ast -or -not $entry.Ast.Extent) { continue }

        $valueText = Get-SensitiveSinkValueText -Value $entry.Value
        if (-not (Test-SensitiveSinkText -Text $valueText -SinkKind ([string]$target.SinkKind))) {
            continue
        }

        $formatted = Format-LiteralizedCommandValue -Value ([string]$valueText)
        $entryStart = [int]$entry.Ast.Extent.StartOffset - $localStart
        $entryEnd = [int]$entry.Ast.Extent.EndOffset - $localStart
        if ($entryStart -lt 0 -or $entryEnd -le $entryStart -or $entryEnd -gt $replacementText.Length) {
            continue
        }

        $originalArg = $replacementText.Substring($entryStart, $entryEnd - $entryStart)
        if ($originalArg -eq $formatted) {
            continue
        }

        $applied += [PSCustomObject]@{
            Start    = $entryStart
            End      = $entryEnd
            Text     = $formatted
            SinkType = [string]$target.SinkType
        }
    }

    if ($applied.Count -eq 0) { return $null }

    foreach ($item in @($applied | Sort-Object Start -Descending)) {
        $replacementText = $replacementText.Substring(0, $item.Start) + $item.Text + $replacementText.Substring($item.End)
    }

    $globalExtent = Get-NodeAstGlobalExtent -Node $Node -Ast $commandAst
    if ($null -eq $globalExtent) { return $null }

    return [PSCustomObject]@{
        NodeId           = $Node.Id
        StartOffset      = [int]$globalExtent.StartOffset
        EndOffset        = [int]$globalExtent.EndOffset
        OriginalText     = [string]$commandAst.Extent.Text
        ReplacementText  = [string]$replacementText
        SinkType         = (($applied | ForEach-Object { [string]$_.SinkType } | Select-Object -Unique) -join ',')
        Executed         = $true
        Timestamp        = Get-Date
        UsedEmptyFallback = $false
    }
}

function Record-SensitiveSinkResult {
    param(
        $Node,
        [hashtable]$Context,
        $CommandInfo = $null
    )

    if ($null -eq $Node -or $null -eq $Context -or $null -eq $Node.Ast) {
        return
    }

    if (-not $Context.ContainsKey('SensitiveSinkResults') -or $null -eq $Context.SensitiveSinkResults) {
        $Context.SensitiveSinkResults = @()
    }

    $record = Get-SensitiveCommandReplacementRecord -Node $Node -Context $Context -CommandInfo $CommandInfo
    if ($null -eq $record -or [string]::IsNullOrWhiteSpace([string]$record.ReplacementText)) {
        return
    }

    $Context.SensitiveSinkResults += $record
    Write-ExecutionLog -Context $Context -Message "  [SINK] Literalized sensitive sink: $($record.SinkType)"
}

function Invoke-DynamicStopPostProcessRecovery {
    param([AllowNull()][string]$ScriptText)

    if ([string]::IsNullOrWhiteSpace($ScriptText)) {
        return $null
    }

    $hasPostProcess = ($null -ne (Get-Command Invoke-PostProcessDeobfuscatedScriptText -ErrorAction SilentlyContinue))
    $hasHostResolver = ($null -ne (Get-Command Resolve-WholeScriptHostPayloadInfo -ErrorAction SilentlyContinue))
    $hasMandatoryBase64Resolver = ($null -ne (Get-Command Try-Resolve-WholeScriptMandatoryBase64PayloadInfo -ErrorAction SilentlyContinue))
    $hasStaticResolver = ($null -ne (Get-Command Try-Resolve-WholeScriptStaticPayloadInfoSafe -ErrorAction SilentlyContinue))
    $hasRecoveredTextNormalizer = ($null -ne (Get-Command Try-NormalizeRecoveredScriptText -ErrorAction SilentlyContinue))

    if (-not ($hasPostProcess -or $hasHostResolver -or $hasMandatoryBase64Resolver -or $hasStaticResolver -or $hasRecoveredTextNormalizer)) {
        return $null
    }

    $getComparisonText = {
        param([AllowNull()][string]$Text)

        $candidateText = if ($null -eq $Text) { '' } else { [string]$Text }
        if (Get-Command Get-NormalizedScriptComparisonText -ErrorAction SilentlyContinue) {
            return (Get-NormalizedScriptComparisonText -ScriptText $candidateText)
        }

        return $candidateText
    }

    $working = [string]$ScriptText
    $adoptCandidate = {
        param([AllowNull()][string]$Candidate)

        if ([string]::IsNullOrWhiteSpace([string]$Candidate)) {
            return $false
        }

        $candidateText = [string]$Candidate
        if ((& $getComparisonText $candidateText) -eq (& $getComparisonText $working)) {
            return $false
        }

        $working = $candidateText
        return $true
    }

    if (Get-Command Remove-RecoveredTextTransportArtifacts -ErrorAction SilentlyContinue) {
        try {
            [void](& $adoptCandidate (Remove-RecoveredTextTransportArtifacts -Text $working))
        } catch {
        }
    }

    for ($round = 0; $round -lt 6; $round++) {
        $changed = $false

        if ($hasRecoveredTextNormalizer) {
            try {
                if (& $adoptCandidate (Try-NormalizeRecoveredScriptText -Text $working)) {
                    $changed = $true
                }
            } catch {
            }
        }

        foreach ($resolverName in @('Try-Resolve-WholeScriptMandatoryBase64PayloadInfo', 'Resolve-WholeScriptHostPayloadInfo', 'Try-Resolve-WholeScriptStaticPayloadInfoSafe')) {
            $payloadInfo = $null
            try {
                switch ($resolverName) {
                    'Try-Resolve-WholeScriptMandatoryBase64PayloadInfo' {
                        if ($hasMandatoryBase64Resolver) {
                            $payloadInfo = Try-Resolve-WholeScriptMandatoryBase64PayloadInfo -ScriptText $working
                        }
                    }
                    'Resolve-WholeScriptHostPayloadInfo' {
                        if ($hasHostResolver) {
                            $payloadInfo = Resolve-WholeScriptHostPayloadInfo -ScriptText $working
                        }
                    }
                    'Try-Resolve-WholeScriptStaticPayloadInfoSafe' {
                        if ($hasStaticResolver) {
                            $payloadInfo = Try-Resolve-WholeScriptStaticPayloadInfoSafe -ScriptText $working -WarningContext 'dynamic_stop_recovery'
                        }
                    }
                }
            } catch {
                $payloadInfo = $null
            }

            if (-not $payloadInfo -or -not $payloadInfo.PSObject.Properties['PayloadText'] -or
                [string]::IsNullOrWhiteSpace([string]$payloadInfo.PayloadText)) {
                continue
            }

            $payloadText = [string]$payloadInfo.PayloadText
            if (Get-Command Get-WholeScriptReplacementCandidateText -ErrorAction SilentlyContinue) {
                try {
                    $candidateText = Get-WholeScriptReplacementCandidateText -OriginalText $working -CandidateText $payloadText
                    if (-not [string]::IsNullOrWhiteSpace([string]$candidateText)) {
                        $payloadText = [string]$candidateText
                    }
                } catch {
                }
            }
            if (Get-Command Remove-RecoveredTextTransportArtifacts -ErrorAction SilentlyContinue) {
                try {
                    $payloadText = Remove-RecoveredTextTransportArtifacts -Text $payloadText
                } catch {
                }
            }

            if (& $adoptCandidate $payloadText) {
                $changed = $true
                break
            }
        }

        if ($hasPostProcess) {
            try {
                if (& $adoptCandidate (Invoke-PostProcessDeobfuscatedScriptText -ScriptText $working)) {
                    $changed = $true
                }
            } catch {
            }
        }

        if (-not $changed) {
            break
        }
    }

    if (Get-Command Invoke-NormalizePlainScriptText -ErrorAction SilentlyContinue) {
        try {
            [void](& $adoptCandidate (Invoke-NormalizePlainScriptText -ScriptText $working))
        } catch {
        }
    }

    if ((& $getComparisonText $working) -eq (& $getComparisonText $ScriptText)) {
        return $null
    }

    return [string]$working
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

function Ensure-ContextStopwatch {
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][string]$PropertyName,
        [switch]$Start
    )

    if (-not $Context.ContainsKey($PropertyName) -or $null -eq $Context[$PropertyName]) {
        $Context[$PropertyName] = [System.Diagnostics.Stopwatch]::new()
    }

    $stopwatch = $Context[$PropertyName]
    if ($Start -and -not $stopwatch.IsRunning) {
        $stopwatch.Start()
    }

    return $stopwatch
}

function Get-ContextBudgetStatus {
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][string]$BudgetPropertyName,
        [Parameter(Mandatory)][string]$StopwatchPropertyName,
        [Parameter(Mandatory)][string]$StopReason,
        [switch]$StartStopwatch
    )

    $budgetMs = 0
    if ($Context.ContainsKey($BudgetPropertyName) -and $null -ne $Context[$BudgetPropertyName]) {
        $budgetMs = [int]$Context[$BudgetPropertyName]
    }

    $stopwatch = Ensure-ContextStopwatch -Context $Context -PropertyName $StopwatchPropertyName -Start:$StartStopwatch
    $elapsedMs = if ($stopwatch) { [int64]$stopwatch.ElapsedMilliseconds } else { 0 }
    $remainingMs = if ($budgetMs -gt 0) { [int64]($budgetMs - $elapsedMs) } else { $null }

    return [PSCustomObject]@{
        Enabled     = ($budgetMs -gt 0)
        BudgetMs    = $budgetMs
        ElapsedMs   = $elapsedMs
        RemainingMs = $remainingMs
        Exceeded    = ($budgetMs -gt 0 -and $elapsedMs -ge $budgetMs)
        StopReason  = $StopReason
    }
}

function Get-StopwatchBudgetStatus {
    param(
        [int]$BudgetMs,
        [System.Diagnostics.Stopwatch]$Stopwatch,
        [Parameter(Mandatory)][string]$StopReason
    )

    $elapsedMs = if ($Stopwatch) { [int64]$Stopwatch.ElapsedMilliseconds } else { 0 }
    $remainingMs = if ($BudgetMs -gt 0) { [int64]($BudgetMs - $elapsedMs) } else { $null }

    return [PSCustomObject]@{
        Enabled     = ($BudgetMs -gt 0)
        BudgetMs    = $BudgetMs
        ElapsedMs   = $elapsedMs
        RemainingMs = $remainingMs
        Exceeded    = ($BudgetMs -gt 0 -and $elapsedMs -ge $BudgetMs)
        StopReason  = $StopReason
    }
}

function Get-PreExecutionGateThresholdScale {
    param(
        [ValidateSet('Disabled', 'Conservative', 'Balanced', 'Aggressive')]
        [string]$Mode = 'Balanced'
    )

    switch ($Mode) {
        'Conservative' { return 1.5 }
        'Aggressive'   { return 0.6 }
        default        { return 1.0 }
    }
}

function Get-PreExecutionGateScoreThresholds {
    param(
        [ValidateSet('Disabled', 'Conservative', 'Balanced', 'Aggressive')]
        [string]$Mode = 'Balanced'
    )

    switch ($Mode) {
        'Conservative' { return [PSCustomObject]@{ Shallow = 9; Stop = 16 } }
        'Aggressive'   { return [PSCustomObject]@{ Shallow = 5; Stop = 8 } }
        default        { return [PSCustomObject]@{ Shallow = 7; Stop = 14 } }
    }
}

function Add-PreExecutionGateReason {
    param(
        [System.Collections.Generic.List[string]]$ReasonList,
        [string]$Reason
    )

    if ($null -eq $ReasonList -or [string]::IsNullOrWhiteSpace($Reason)) {
        return
    }

    if (-not $ReasonList.Contains($Reason)) {
        $ReasonList.Add($Reason) | Out-Null
    }
}

function Get-PreExecutionGateTextMetrics {
    param(
        [string]$ScriptText,
        [AllowNull()]$ParseInfo = $null
    )

    $text = if ($null -eq $ScriptText) { '' } else { [string]$ScriptText }
    $lineCount = 0
    if ($text.Length -gt 0) {
        $lineCount = ([regex]::Matches($text, "`r`n|`n|`r")).Count + 1
    }

    $dynamicMatches = [regex]::Matches($text, '(?im)\b(?:Invoke-Expression|iex|ScriptBlock\s*::\s*Create|NewScriptBlock|powershell(?:\.exe)?|pwsh(?:\.exe)?)\b')
    $loaderMatches = [regex]::Matches($text, '(?im)\b(?:DeflateStream|ReadToEnd|ToInt16|FromBase64String|-bxor|\[char\]|ConvertTo-SecureString|PSCredential|GetNetworkCredential|SecureStringToGlobalAlloc|PtrToString|MemoryStream|GzipStream)\b')
    $functionMatches = [regex]::Matches($text, '(?im)^\s*function\b')
    $largeArrayCount = 0
    foreach ($m in @([regex]::Matches($text, '(?is)(?:0x[0-9a-f]{2}|\b\d{1,3}\b)\s*(?:,\s*(?:0x[0-9a-f]{2}|\b\d{1,3}\b)\s*)+'))) {
        $itemCount = [regex]::Matches([string]$m.Value, '(?i)0x[0-9a-f]{2}|\b\d{1,3}\b').Count
        if ($itemCount -gt $largeArrayCount) {
            $largeArrayCount = $itemCount
        }
    }

    $delayBombHit = $false
    $delayIndicators = New-Object 'System.Collections.Generic.List[string]'
    $delayPatterns = @(
        @{ Name = 'StartSleep'; Pattern = '(?im)\b(?:Start-Sleep|sleep)\b' },
        @{ Name = 'ThreadSleep'; Pattern = '(?im)\[(?:System\.)?Threading\.Thread\]\s*::\s*Sleep\s*\(' },
        @{ Name = 'PingDelay'; Pattern = '(?im)\bping\b\s+-n\b' },
        @{ Name = 'WhileTrue'; Pattern = '(?is)\bwhile\s*\(\s*(?:\$true|1|\(+\s*\[int(?:32|64)?\]\s*1\s*\)+)\s*\)' },
        @{ Name = 'ForEver'; Pattern = '(?is)\bfor\s*\(\s*;\s*;\s*\)' }
    )
    foreach ($entry in $delayPatterns) {
        if ($text -match $entry.Pattern) {
            $delayBombHit = $true
            $delayIndicators.Add([string]$entry.Name) | Out-Null
        }
    }

    $interactiveComHit = $false
    $interactiveComIndicators = New-Object 'System.Collections.Generic.List[string]'
    $interactiveComPatterns = @(
        @{ Name = 'WScriptShellPopup'; Pattern = '(?is)\bWScript\.Shell\b[\s\S]{0,160}?\.\s*Popup\s*\(' },
        @{ Name = 'ShellApplicationShellExecute'; Pattern = '(?is)\bShell\.Application\b[\s\S]{0,200}?\.\s*ShellExecute\s*\(' },
        @{ Name = 'ComShellExecute'; Pattern = '(?is)\bNew-Object\b[\s\S]{0,120}?(?<!\S)-(?:ComObject|Com)\b[\s\S]{0,200}?\.\s*ShellExecute\s*\(' },
        @{ Name = 'ComRunExec'; Pattern = '(?is)\bNew-Object\b[\s\S]{0,120}?(?<!\S)-(?:ComObject|Com)\b[\s\S]{0,200}?\.\s*(?:Run|Exec)\s*\(' },
        @{ Name = 'IEAutomation'; Pattern = '(?is)\bInternetExplorer\.Application\b|\.\s*Navigate2?\s*\(' }
    )
    foreach ($entry in $interactiveComPatterns) {
        if ($text -match $entry.Pattern) {
            $interactiveComHit = $true
            $interactiveComIndicators.Add([string]$entry.Name) | Out-Null
        }
    }

    $guiPayloadHit = $false
    $guiPayloadIndicators = New-Object 'System.Collections.Generic.List[string]'
    $guiPayloadPatterns = @(
        @{ Name = 'WinFormsNamespace'; Pattern = '(?im)\bSystem\.Windows\.Forms\b' },
        @{ Name = 'DrawingNamespace'; Pattern = '(?im)\bSystem\.Drawing\b' },
        @{ Name = 'WinFormsForm'; Pattern = '(?im)\bNew-Object\s+System\.Windows\.Forms\.Form\b' },
        @{ Name = 'GuiShowDialog'; Pattern = '(?im)\.\s*ShowDialog\s*\(' },
        @{ Name = 'GuiShow'; Pattern = '(?im)\.\s*Show\s*\(' },
        @{ Name = 'GuiEventHandler'; Pattern = '(?im)\bAdd_(?:Shown|Click|KeyDown)\b' }
    )
    foreach ($entry in $guiPayloadPatterns) {
        if ($text -match $entry.Pattern) {
            $guiPayloadHit = $true
            $guiPayloadIndicators.Add([string]$entry.Name) | Out-Null
        }
    }

    $archivePayloadHit = $false
    $archivePayloadIndicators = New-Object 'System.Collections.Generic.List[string]'
    $archivePayloadPatterns = @(
        @{ Name = 'ExpandArchive'; Pattern = '(?im)\bExpand-Archive\b' },
        @{ Name = 'ZipExtract'; Pattern = '(?im)\[(?:System\.)?IO\.Compression\.ZipFile\]\s*::\s*ExtractToDirectory\s*\(' },
        @{ Name = 'ShellCopyHere'; Pattern = '(?im)\.\s*CopyHere\s*\(' }
    )
    foreach ($entry in $archivePayloadPatterns) {
        if ($text -match $entry.Pattern) {
            $archivePayloadHit = $true
            $archivePayloadIndicators.Add([string]$entry.Name) | Out-Null
        }
    }

    $compressedLoaderHit = $false
    $compressedLoaderIndicators = New-Object 'System.Collections.Generic.List[string]'
    $hasIexToken = ($text -match '(?im)\b(?:Invoke-Expression|iex)\b')
    $hasBase64Token = ($text -match '(?im)\bFromBase64String\b')
    $hasCompressedStreamToken = ($text -match '(?im)\b(?:DeflateStream|GzipStream)\b')
    $hasMemoryStreamToken = ($text -match '(?im)\b(?:MemoryStream|StreamReader|ReadToEnd)\b')
    if ($hasIexToken) { $compressedLoaderIndicators.Add('InvokeExpression') | Out-Null }
    if ($hasBase64Token) { $compressedLoaderIndicators.Add('FromBase64String') | Out-Null }
    if ($hasCompressedStreamToken) { $compressedLoaderIndicators.Add('CompressedStream') | Out-Null }
    if ($hasMemoryStreamToken) { $compressedLoaderIndicators.Add('MemoryStreamReader') | Out-Null }
    if (($hasIexToken -and $hasBase64Token -and ($hasCompressedStreamToken -or $hasMemoryStreamToken)) -or
        ($hasCompressedStreamToken -and $hasBase64Token)) {
        $compressedLoaderHit = $true
    } elseif ($compressedLoaderIndicators.Count -eq 4) {
        $compressedLoaderHit = $true
    }
    if (-not $compressedLoaderHit) {
        $compressedLoaderIndicators.Clear()
    }

    return [PSCustomObject]@{
        TextLength            = $text.Length
        LineCount             = $lineCount
        DynamicTokenCount     = $dynamicMatches.Count
        LoaderTokenCount      = $loaderMatches.Count
        LargeArrayElementCount = $largeArrayCount
        DelayBombHit          = $delayBombHit
        DelayBombIndicators   = @($delayIndicators.ToArray())
        InteractiveComHit     = $interactiveComHit
        InteractiveComIndicators = @($interactiveComIndicators.ToArray())
        GuiPayloadHit         = $guiPayloadHit
        GuiPayloadIndicators  = @($guiPayloadIndicators.ToArray())
        ArchivePayloadHit     = $archivePayloadHit
        ArchivePayloadIndicators = @($archivePayloadIndicators.ToArray())
        CompressedLoaderHit   = $compressedLoaderHit
        CompressedLoaderIndicators = @($compressedLoaderIndicators.ToArray())
        FunctionKeywordCount  = $functionMatches.Count
        ParseProvided         = ($null -ne $ParseInfo)
    }
}

function Get-PreExecutionGateAstMetrics {
    param(
        [string]$ScriptText,
        [AllowNull()]$ParseInfo = $null
    )

    $parse = $ParseInfo
    if ($null -eq $parse) {
        try {
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseInput($ScriptText, [ref]$tokens, [ref]$errors)
            $parse = [PSCustomObject]@{
                Ast     = $ast
                Tokens   = $tokens
                Errors   = $errors
                IsValid  = (-not $errors -or $errors.Count -eq 0)
            }
        } catch {
            $parse = $null
        }
    }

    if ($null -eq $parse -or -not $parse.Ast) {
        return [PSCustomObject]@{
            ParseSucceeded          = $false
            AstNodeCount            = 0
            LoopCount               = 0
            PipelineMaxLen          = 0
            NestedDynamicInvokeCount = 0
            FunctionDefCount        = 0
        }
    }

    $ast = $parse.Ast
    $nodeCount = 0
    $loopCount = 0
    $pipelineMaxLen = 0
    $nestedDynamicInvokeCount = 0
    $functionDefCount = 0

    foreach ($n in @($ast.FindAll({ param($node) $true }, $true))) {
        $nodeCount++
        if ($n -is [System.Management.Automation.Language.WhileStatementAst] -or
            $n -is [System.Management.Automation.Language.DoWhileStatementAst] -or
            $n -is [System.Management.Automation.Language.DoUntilStatementAst] -or
            $n -is [System.Management.Automation.Language.ForStatementAst] -or
            $n -is [System.Management.Automation.Language.ForEachStatementAst]) {
            $loopCount++
        }
        if ($n -is [System.Management.Automation.Language.PipelineAst]) {
            $count = @($n.PipelineElements).Count
            if ($count -gt $pipelineMaxLen) {
                $pipelineMaxLen = $count
            }
        }
        if ($n -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
            $functionDefCount++
        }
        if ($n -is [System.Management.Automation.Language.CommandAst]) {
            $name = $n.GetCommandName()
            if ($name -match '(?i)^(Invoke-Expression|iex|powershell|powershell\.exe|pwsh|pwsh\.exe)$') {
                $parent = $n.Parent
                while ($parent) {
                    if ($parent -is [System.Management.Automation.Language.CommandAst]) {
                        $nestedDynamicInvokeCount++
                        break
                    }
                    $parent = $parent.Parent
                }
            }
        }
    }

    return [PSCustomObject]@{
        ParseSucceeded          = [bool]$parse.IsValid
        AstNodeCount            = $nodeCount
        LoopCount               = $loopCount
        PipelineMaxLen          = $pipelineMaxLen
        NestedDynamicInvokeCount = $nestedDynamicInvokeCount
        FunctionDefCount        = $functionDefCount
    }
}

function Resolve-PreExecutionGateDecision {
    param(
        [ValidateSet('Round', 'DynamicPayload', 'WholeScriptHelper', 'StaticExpr')]
        [string]$Scope,
        [string]$ScriptText,
        [AllowNull()]$ParseInfo = $null,
        [ValidateSet('Disabled', 'Conservative', 'Balanced', 'Aggressive')]
        [string]$Mode = 'Balanced',
        [bool]$SafeMode = $true
    )

    if ($Mode -eq 'Disabled') {
        return [PSCustomObject]@{
            Decision               = 'Full'
            Score                  = 0
            Reasons                = @()
            Metrics                = [PSCustomObject]@{}
            ReducedDynamicBudgetMs = $null
            ReducedMaxIterations   = $null
            ReducedMaxTotalNodes   = $null
            SkipWholeScriptDynamic = $false
            SkipStaticEval         = $false
            ParseSucceeded         = $true
            Scope                  = $Scope
            Mode                   = $Mode
        }
    }

    $scale = Get-PreExecutionGateThresholdScale -Mode $Mode
    $scoreThresholds = Get-PreExecutionGateScoreThresholds -Mode $Mode
    $reasons = New-Object 'System.Collections.Generic.List[string]'
    $textMetrics = Get-PreExecutionGateTextMetrics -ScriptText $ScriptText -ParseInfo $ParseInfo
    $score = 0

    if ($textMetrics.TextLength -gt [int](65536 * $scale)) { $score += 8; Add-PreExecutionGateReason -ReasonList $reasons -Reason 'HugeText' }
    elseif ($textMetrics.TextLength -gt [int](16384 * $scale)) { $score += 4; Add-PreExecutionGateReason -ReasonList $reasons -Reason 'LargeText' }
    elseif ($textMetrics.TextLength -gt [int](4096 * $scale)) { $score += 2; Add-PreExecutionGateReason -ReasonList $reasons -Reason 'MediumText' }

    if ($textMetrics.LineCount -gt [int](1000 * $scale)) { $score += 2; Add-PreExecutionGateReason -ReasonList $reasons -Reason 'ManyLines' }
    elseif ($textMetrics.LineCount -gt [int](200 * $scale)) { $score += 1; Add-PreExecutionGateReason -ReasonList $reasons -Reason 'SomewhatManyLines' }

    if ($textMetrics.DynamicTokenCount -gt [int](8 * $scale)) { $score += 4; Add-PreExecutionGateReason -ReasonList $reasons -Reason 'ManyDynamicTokens' }
    elseif ($textMetrics.DynamicTokenCount -gt [int](3 * $scale)) { $score += 2; Add-PreExecutionGateReason -ReasonList $reasons -Reason 'SeveralDynamicTokens' }

    if ($textMetrics.LoaderTokenCount -gt [int](128 * $scale)) { $score += 4; Add-PreExecutionGateReason -ReasonList $reasons -Reason 'HeavyLoaderTokens' }
    elseif ($textMetrics.LoaderTokenCount -gt [int](32 * $scale)) { $score += 2; Add-PreExecutionGateReason -ReasonList $reasons -Reason 'LoaderTokens' }

    if ($textMetrics.LargeArrayElementCount -gt [int](2048 * $scale)) { $score += 6; Add-PreExecutionGateReason -ReasonList $reasons -Reason 'HugeArrayLiteral' }
    elseif ($textMetrics.LargeArrayElementCount -gt [int](512 * $scale)) { $score += 3; Add-PreExecutionGateReason -ReasonList $reasons -Reason 'LargeArrayLiteral' }

    if ($textMetrics.DelayBombHit) {
        $score += 8
        Add-PreExecutionGateReason -ReasonList $reasons -Reason 'DelayBomb'
    }
    if ($textMetrics.InteractiveComHit) {
        $score += 10
        Add-PreExecutionGateReason -ReasonList $reasons -Reason 'InteractiveCom'
    }
    if ($textMetrics.GuiPayloadHit) {
        $score += 8
        Add-PreExecutionGateReason -ReasonList $reasons -Reason 'GuiPayload'
    }
    if ($textMetrics.ArchivePayloadHit) {
        $score += 6
        Add-PreExecutionGateReason -ReasonList $reasons -Reason 'ArchivePayload'
    }
    if ($textMetrics.CompressedLoaderHit) {
        $score += 7
        Add-PreExecutionGateReason -ReasonList $reasons -Reason 'CompressedLoader'
    }

    if ($textMetrics.FunctionKeywordCount -gt [int](30 * $scale)) { $score += 3; Add-PreExecutionGateReason -ReasonList $reasons -Reason 'ManyFunctions' }
    elseif ($textMetrics.FunctionKeywordCount -gt [int](10 * $scale)) { $score += 1; Add-PreExecutionGateReason -ReasonList $reasons -Reason 'SeveralFunctions' }

    $needAstMetrics = (
        $textMetrics.TextLength -gt [int](4096 * $scale) -or
        ($Scope -eq 'WholeScriptHelper' -and $textMetrics.TextLength -gt [int](2048 * $scale)) -or
        $textMetrics.FunctionKeywordCount -gt 0 -or
        $score -ge 4
    )
    $astMetrics = [PSCustomObject]@{
        ParseSucceeded          = $true
        AstNodeCount            = 0
        LoopCount               = 0
        PipelineMaxLen          = 0
        NestedDynamicInvokeCount = 0
        FunctionDefCount        = 0
    }
    if ($needAstMetrics) {
        $astMetrics = Get-PreExecutionGateAstMetrics -ScriptText $ScriptText -ParseInfo $ParseInfo
        if (-not $astMetrics.ParseSucceeded) {
            Add-PreExecutionGateReason -ReasonList $reasons -Reason 'GateParseFailed'
        }
        if ($astMetrics.AstNodeCount -gt [int](5000 * $scale)) { $score += 8; Add-PreExecutionGateReason -ReasonList $reasons -Reason 'HugeAst' }
        elseif ($astMetrics.AstNodeCount -gt [int](1200 * $scale)) { $score += 4; Add-PreExecutionGateReason -ReasonList $reasons -Reason 'LargeAst' }
        elseif ($astMetrics.AstNodeCount -gt [int](400 * $scale)) { $score += 2; Add-PreExecutionGateReason -ReasonList $reasons -Reason 'MediumAst' }

        if ($astMetrics.LoopCount -gt 3) { $score += 5; Add-PreExecutionGateReason -ReasonList $reasons -Reason 'ManyLoops' }
        elseif ($astMetrics.LoopCount -gt 0) { $score += 3; Add-PreExecutionGateReason -ReasonList $reasons -Reason 'LoopPresent' }

        if ($astMetrics.PipelineMaxLen -gt [int](10 * $scale)) { $score += 4; Add-PreExecutionGateReason -ReasonList $reasons -Reason 'LongPipeline' }
        elseif ($astMetrics.PipelineMaxLen -gt [int](4 * $scale)) { $score += 2; Add-PreExecutionGateReason -ReasonList $reasons -Reason 'PipelineChain' }

        if ($astMetrics.NestedDynamicInvokeCount -gt [int](5 * $scale)) { $score += 5; Add-PreExecutionGateReason -ReasonList $reasons -Reason 'NestedDynamicInvoke' }
        elseif ($astMetrics.NestedDynamicInvokeCount -gt [int](2 * $scale)) { $score += 2; Add-PreExecutionGateReason -ReasonList $reasons -Reason 'SomeNestedDynamicInvoke' }

        if ($astMetrics.FunctionDefCount -gt [int](15 * $scale)) { $score += 4; Add-PreExecutionGateReason -ReasonList $reasons -Reason 'ManyFunctionDefs' }
        elseif ($astMetrics.FunctionDefCount -gt [int](5 * $scale)) { $score += 2; Add-PreExecutionGateReason -ReasonList $reasons -Reason 'FunctionDefsPresent' }
    }

    $decision = 'Full'
    $skipWholeScriptDynamic = $false
    $skipStaticEval = $false
    $reducedDynamicBudgetMs = $null
    $reducedMaxIterations = $null
    $reducedMaxTotalNodes = $null

    switch ($Scope) {
        'Round' {
            if ($textMetrics.DelayBombHit -or
                $textMetrics.InteractiveComHit -or
                $textMetrics.GuiPayloadHit -or
                $textMetrics.ArchivePayloadHit -or
                $textMetrics.CompressedLoaderHit -or
                $textMetrics.TextLength -gt [int](65536 * $scale) -or
                $textMetrics.LargeArrayElementCount -gt [int](4096 * $scale) -or
                $astMetrics.AstNodeCount -gt [int](12000 * $scale) -or
                $score -ge $scoreThresholds.Stop) {
                $decision = 'Stop'
            } elseif ($textMetrics.TextLength -gt [int](16384 * $scale) -or
                $textMetrics.LargeArrayElementCount -gt [int](2048 * $scale) -or
                $astMetrics.AstNodeCount -gt [int](3500 * $scale) -or
                $score -ge $scoreThresholds.Shallow) {
                $decision = 'Shallow'
                $skipWholeScriptDynamic = $true
                $skipStaticEval = $true
                $reducedDynamicBudgetMs = 2000
                $reducedMaxIterations = 250
                $reducedMaxTotalNodes = 8000
            }
        }
        'DynamicPayload' {
            $shallowThreshold = if ($Mode -eq 'Conservative') { 8 } elseif ($Mode -eq 'Aggressive') { 4 } else { 6 }
            $stopThreshold = if ($Mode -eq 'Conservative') { 14 } elseif ($Mode -eq 'Aggressive') { 7 } else { 12 }
            if ($textMetrics.DelayBombHit -or
                $textMetrics.InteractiveComHit -or
                $textMetrics.GuiPayloadHit -or
                $textMetrics.ArchivePayloadHit -or
                $textMetrics.CompressedLoaderHit -or
                $textMetrics.TextLength -gt [int](24576 * $scale) -or
                $textMetrics.LargeArrayElementCount -gt [int](2048 * $scale) -or
                $astMetrics.AstNodeCount -gt [int](5000 * $scale) -or
                $score -ge $stopThreshold) {
                $decision = 'Stop'
            } elseif ($textMetrics.TextLength -gt [int](4096 * $scale) -or
                $astMetrics.AstNodeCount -gt [int](1200 * $scale) -or
                $score -ge $shallowThreshold) {
                $decision = 'Shallow'
                $reducedDynamicBudgetMs = 1000
            }
        }
        'WholeScriptHelper' {
            $threshold = if ($Mode -eq 'Conservative') { 9 } elseif ($Mode -eq 'Aggressive') { 4 } else { 6 }
            if ($textMetrics.InteractiveComHit -or
                $textMetrics.GuiPayloadHit -or
                $textMetrics.ArchivePayloadHit -or
                $textMetrics.CompressedLoaderHit -or
                $textMetrics.TextLength -gt [int](2048 * $scale) -or
                $score -ge $threshold -or
                $astMetrics.AstNodeCount -gt [int](400 * $scale) -or
                $astMetrics.LoopCount -gt 0 -or
                $astMetrics.FunctionDefCount -gt 0) {
                $decision = 'Stop'
            }
        }
        'StaticExpr' {
            if ($textMetrics.InteractiveComHit -or
                $textMetrics.GuiPayloadHit -or
                $textMetrics.ArchivePayloadHit -or
                $textMetrics.CompressedLoaderHit -or
                $textMetrics.TextLength -gt [int](1024 * $scale) -or
                $textMetrics.LargeArrayElementCount -gt [int](512 * $scale) -or
                $astMetrics.AstNodeCount -gt [int](250 * $scale) -or
                $astMetrics.LoopCount -gt 0 -or
                $astMetrics.NestedDynamicInvokeCount -gt 0) {
                $decision = 'Stop'
            }
        }
    }

    if ($SafeMode -and $Scope -in @('Round', 'DynamicPayload')) {
        if ($textMetrics.DelayBombHit -and $decision -ne 'Stop') {
            $decision = 'Stop'
        }
    }

    $metrics = [ordered]@{}
    foreach ($name in @(
        'TextLength', 'LineCount', 'DynamicTokenCount', 'LoaderTokenCount', 'LargeArrayElementCount',
        'DelayBombHit', 'DelayBombIndicators',
        'InteractiveComHit', 'InteractiveComIndicators',
        'GuiPayloadHit', 'GuiPayloadIndicators',
        'ArchivePayloadHit', 'ArchivePayloadIndicators',
        'CompressedLoaderHit', 'CompressedLoaderIndicators',
        'FunctionKeywordCount'
    )) {
        $metrics[$name] = $textMetrics.$name
    }
    foreach ($name in @('AstNodeCount', 'LoopCount', 'PipelineMaxLen', 'NestedDynamicInvokeCount', 'FunctionDefCount', 'ParseSucceeded')) {
        $metrics[$name] = $astMetrics.$name
    }

    return [PSCustomObject]@{
        Decision               = $decision
        Score                  = $score
        Reasons                = @($reasons.ToArray())
        Metrics                = [PSCustomObject]$metrics
        ReducedDynamicBudgetMs = $reducedDynamicBudgetMs
        ReducedMaxIterations   = $reducedMaxIterations
        ReducedMaxTotalNodes   = $reducedMaxTotalNodes
        SkipWholeScriptDynamic = $skipWholeScriptDynamic
        SkipStaticEval         = $skipStaticEval
        ParseSucceeded         = [bool]$astMetrics.ParseSucceeded
        Scope                  = $Scope
        Mode                   = $Mode
    }
}

function Get-PreExecutionGateDecision {
    param(
        [ValidateSet('Round', 'DynamicPayload', 'WholeScriptHelper', 'StaticExpr')]
        [string]$Scope,
        [string]$ScriptText,
        [AllowNull()]$ParseInfo = $null,
        [ValidateSet('Disabled', 'Conservative', 'Balanced', 'Aggressive')]
        [string]$Mode = 'Balanced',
        [bool]$SafeMode = $true,
        [hashtable]$Cache = $null
    )

    $normalized = if ($null -eq $ScriptText) { '' } else { [string]$ScriptText }
    $hash = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($normalized))
    $cacheKey = "{0}|{1}|{2}|{3}" -f $Scope, $Mode, $SafeMode, $hash

    if ($Cache -and $Cache.ContainsKey($cacheKey)) {
        return $Cache[$cacheKey]
    }

    $decision = Resolve-PreExecutionGateDecision -Scope $Scope -ScriptText $normalized -ParseInfo $ParseInfo -Mode $Mode -SafeMode:$SafeMode
    if ($Cache) {
        $Cache[$cacheKey] = $decision
    }
    return $decision
}

function Normalize-LoopConditionText {
    param([string]$ConditionText)

    if ([string]::IsNullOrWhiteSpace($ConditionText)) { return '' }

    $normalized = ($ConditionText -replace '\s+', '')
    while ($normalized.Length -ge 2 -and $normalized.StartsWith('(') -and $normalized.EndsWith(')')) {
        $normalized = $normalized.Substring(1, $normalized.Length - 2)
    }

    return $normalized
}

function Test-LoopConditionLiteral {
    param(
        [string]$ConditionText,
        [ValidateSet('True', 'False')][string]$Expected = 'True'
    )

    $normalized = Normalize-LoopConditionText -ConditionText $ConditionText
    if ([string]::IsNullOrWhiteSpace($normalized)) { return $false }

    $truthy = @('$true', '1', '[int]1', '[int32]1', '[uint32]1', '[long]1', '[int64]1', '[bool]1')
    $falsy = @('$false', '0', '[int]0', '[int32]0', '[uint32]0', '[long]0', '[int64]0', '[bool]0')

    if ($Expected -eq 'True') {
        return ($normalized -in $truthy)
    }

    return ($normalized -in $falsy)
}

function Get-DynamicPayloadTopLevelCommandAst {
    param($Statement)

    if ($null -eq $Statement) { return $null }

    if ($Statement -is [System.Management.Automation.Language.CommandAst]) {
        return $Statement
    }

    if ($Statement -is [System.Management.Automation.Language.PipelineAst] -and
        $Statement.PipelineElements -and
        $Statement.PipelineElements.Count -eq 1 -and
        $Statement.PipelineElements[0] -is [System.Management.Automation.Language.CommandAst]) {
        return $Statement.PipelineElements[0]
    }

    return $null
}

function Test-DynamicPayloadAliasDefinitionStatement {
    param($Statement)

    $cmdAst = Get-DynamicPayloadTopLevelCommandAst -Statement $Statement
    if ($null -eq $cmdAst) { return $false }

    $cmdName = $cmdAst.GetCommandName()
    if ([string]::IsNullOrWhiteSpace($cmdName)) { return $false }

    return ($cmdName -in @('Set-Alias', 'New-Alias', 'sal', 'nal'))
}

function Test-DynamicPayloadShouldStopRecursing {
    param(
        [Parameter(Mandatory)][string]$ScriptText,
        [bool]$SafeMode = $true,
        [ValidateSet('Disabled', 'Conservative', 'Balanced', 'Aggressive')]
        [string]$GateMode = 'Balanced',
        [ValidateSet('DynamicPayload', 'WholeScriptHelper')]
        [string]$GateScope = 'DynamicPayload',
        [hashtable]$GateCache = $null,
        [AllowNull()]$ParseInfo = $null
    )

    $gate = Get-PreExecutionGateDecision -Scope $GateScope -ScriptText $ScriptText -ParseInfo $ParseInfo -Mode $GateMode -SafeMode:$SafeMode -Cache $GateCache
    $features = New-Object 'System.Collections.Generic.List[string]'
    foreach ($reason in @($gate.Reasons)) {
        $features.Add([string]$reason) | Out-Null
    }
    foreach ($indicatorProperty in @(
        'DelayBombIndicators',
        'InteractiveComIndicators',
        'GuiPayloadIndicators',
        'ArchivePayloadIndicators',
        'CompressedLoaderIndicators'
    )) {
        if ($gate.Metrics -and $gate.Metrics.PSObject.Properties[$indicatorProperty]) {
            foreach ($indicator in @($gate.Metrics.$indicatorProperty)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$indicator)) {
                    $features.Add([string]$indicator) | Out-Null
                }
            }
        }
    }

    $result = [ordered]@{
        ShouldStop       = ($gate.Decision -eq 'Stop')
        Decision         = [string]$gate.Decision
        StopReason       = if ($gate.Decision -eq 'Stop') { "PreExecutionGate:$GateScope" } else { $null }
        Message          = if ($gate.Decision -eq 'Stop') { '动态脚本文本命中先审后执行门控，停止递归执行并保留当前层已恢复内容。' } else { $null }
        FeatureSummary   = if (@($features).Count -gt 0) { (@($features) -join ', ') } else { $null }
        Features         = @($features)
        ParseSucceeded   = [bool]$gate.ParseSucceeded
        AnalysisText     = $ScriptText
        GateScore        = [int]$gate.Score
        GateReasons      = @($gate.Reasons)
        GateMetrics      = $gate.Metrics
        ReducedDynamicBudgetMs = $gate.ReducedDynamicBudgetMs
    }

    return [PSCustomObject]$result
}

function Test-InteractiveComNode {
    param($Node)

    $result = [ordered]@{
        IsDangerous = $false
        Reason      = $null
        Detail      = $null
    }

    if ($null -eq $Node -or [string]::IsNullOrWhiteSpace([string]$Node.Text)) {
        return [PSCustomObject]$result
    }

    $text = [string]$Node.Text
    $hasPopupCall = ($text -match '(?i)\.\s*Popup\s*\(')
    $hasWScriptShell = ($text -match '(?i)\bWScript\.Shell\b')
    $hasShellApplication = ($text -match '(?i)\bShell\.Application\b')
    $hasShellExecute = ($text -match '(?i)\.\s*ShellExecute\s*\(')
    $hasRunOrExec = ($text -match '(?i)\.\s*(?:Run|Exec)\s*\(')
    $hasIeAutomation = ($text -match '(?i)\bInternetExplorer\.Application\b') -or ($text -match '(?i)\.\s*Navigate2?\s*\(')
    $hasComObject = ($text -match '(?i)\bNew-Object\b[\s\S]{0,120}?(?<!\S)-(?:ComObject|Com)\b')
    $hasBusyLoop = ($text -match '(?i)\bwhile\b[\s\S]{0,200}?\.\s*(?:Busy|ReadyState)\b')

    if (($hasComObject -or $hasShellApplication) -and $hasShellExecute) {
        $result.IsDangerous = $true
        $result.Reason = 'COM ShellExecute 调用已阻断'
        $result.Detail = 'Shell.Application.ShellExecute'
        return [PSCustomObject]$result
    }

    if (($hasComObject -or $hasWScriptShell) -and $hasRunOrExec) {
        $result.IsDangerous = $true
        $result.Reason = 'COM 进程启动调用已阻断'
        $result.Detail = 'WScript.Shell.Run/Exec'
        return [PSCustomObject]$result
    }

    if (($hasComObject -or $hasWScriptShell) -and $hasPopupCall) {
        $result.IsDangerous = $true
        $result.Reason = 'COM GUI 弹窗调用已阻断'
        $result.Detail = 'WScript.Shell.Popup'
        return [PSCustomObject]$result
    }

    if (($hasComObject -and $hasIeAutomation) -or $hasBusyLoop) {
        $result.IsDangerous = $true
        $result.Reason = 'COM 浏览器自动化已阻断'
        $result.Detail = 'InternetExplorer.Application'
        return [PSCustomObject]$result
    }

    return [PSCustomObject]$result
}

function Get-FirstStatementFromScriptAst {
    param($ScriptAst)

    if ($null -eq $ScriptAst) { return $null }

    $blocks = @()
    if ($ScriptAst.BeginBlock) { $blocks += $ScriptAst.BeginBlock }
    if ($ScriptAst.ProcessBlock) { $blocks += $ScriptAst.ProcessBlock }
    if ($ScriptAst.EndBlock) { $blocks += $ScriptAst.EndBlock }

    foreach ($block in $blocks) {
        if ($block.Statements -and $block.Statements.Count -gt 0) {
            return $block.Statements[0]
        }
    }

    return $null
}

function Get-PrimaryCommandAstFromScriptAst {
    param($ScriptAst)

    $statement = Get-FirstStatementFromScriptAst -ScriptAst $ScriptAst
    if ($null -eq $statement) { return $null }

    function Find-FirstCommandAst {
        param($AstRoot)

        if ($null -eq $AstRoot) { return $null }

        $cmds = @($AstRoot.FindAll({
            param($n)
            if (-not ($n -is [System.Management.Automation.Language.CommandAst])) { return $false }

            $ancestor = $n.Parent
            while ($null -ne $ancestor -and $ancestor -ne $AstRoot) {
                if ($ancestor -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
                    return $false
                }
                $ancestor = $ancestor.Parent
            }
            return $true
        }, $true))

        if ($cmds.Count -eq 0) { return $null }
        return @($cmds | Sort-Object { $_.Extent.StartOffset } | Select-Object -First 1)
    }

    if ($statement -is [System.Management.Automation.Language.AssignmentStatementAst]) {
        return Find-FirstCommandAst -AstRoot $statement.Right
    }

    if ($statement -is [System.Management.Automation.Language.PipelineAst] -and
        $statement.PipelineElements -and $statement.PipelineElements.Count -gt 0) {
        $directCommands = @()
        foreach ($elem in $statement.PipelineElements) {
            if ($elem -is [System.Management.Automation.Language.CommandAst]) {
                $directCommands += $elem
                }
        }
        if ($directCommands.Count -gt 0) {
            return $directCommands[$directCommands.Count - 1]
        }

        foreach ($elem in $statement.PipelineElements) {
            if ($elem -is [System.Management.Automation.Language.CommandExpressionAst]) {
                $cmd = Find-FirstCommandAst -AstRoot $elem.Expression
                if ($cmd) { return $cmd }
            }
        }
        return $null
    }

    if ($statement -is [System.Management.Automation.Language.CommandAst]) {
        return $statement
    }

    if ($statement -is [System.Management.Automation.Language.CommandExpressionAst]) {
        return Find-FirstCommandAst -AstRoot $statement.Expression
    }

    return Find-FirstCommandAst -AstRoot $statement
}

function Get-TopLevelCommandAstFromExpressionAst {
    param($ExpressionAst)

    if ($null -eq $ExpressionAst) { return $null }

    if ($ExpressionAst -is [System.Management.Automation.Language.CommandAst]) {
        return $ExpressionAst
    }

    if ($ExpressionAst -is [System.Management.Automation.Language.PipelineAst]) {
        if (-not $ExpressionAst.PipelineElements -or $ExpressionAst.PipelineElements.Count -ne 1) {
            return $null
        }

        $element = $ExpressionAst.PipelineElements[0]
        if ($element -is [System.Management.Automation.Language.CommandAst]) {
            return $element
        }
        if ($element -is [System.Management.Automation.Language.CommandExpressionAst]) {
            return Get-TopLevelCommandAstFromExpressionAst -ExpressionAst $element.Expression
        }

        return $null
    }

    if ($ExpressionAst -is [System.Management.Automation.Language.CommandExpressionAst]) {
        return Get-TopLevelCommandAstFromExpressionAst -ExpressionAst $ExpressionAst.Expression
    }

    if ($ExpressionAst -is [System.Management.Automation.Language.ParenExpressionAst]) {
        return Get-TopLevelCommandAstFromExpressionAst -ExpressionAst $ExpressionAst.Pipeline
    }

    if ($ExpressionAst -is [System.Management.Automation.Language.SubExpressionAst]) {
        $statements = @()
        if ($ExpressionAst.SubExpression -and $ExpressionAst.SubExpression.Statements) {
            $statements = @($ExpressionAst.SubExpression.Statements)
        }
        if ($statements.Count -ne 1) {
            return $null
        }

        return Get-TopLevelCommandAstFromStatementAst -StatementAst $statements[0]
    }

    return $null
}

function Get-TopLevelCommandAstFromStatementAst {
    param($StatementAst)

    if ($null -eq $StatementAst) { return $null }

    if ($StatementAst -is [System.Management.Automation.Language.AssignmentStatementAst]) {
        return Get-TopLevelCommandAstFromExpressionAst -ExpressionAst $StatementAst.Right
    }

    if ($StatementAst -is [System.Management.Automation.Language.PipelineAst]) {
        return Get-TopLevelCommandAstFromExpressionAst -ExpressionAst $StatementAst
    }

    if ($StatementAst -is [System.Management.Automation.Language.CommandAst]) {
        return $StatementAst
    }

    if ($StatementAst -is [System.Management.Automation.Language.CommandExpressionAst]) {
        return Get-TopLevelCommandAstFromExpressionAst -ExpressionAst $StatementAst.Expression
    }

    return $null
}

function Test-AstExtentEquals {
    param(
        $LeftAst,
        $RightAst
    )

    if ($null -eq $LeftAst -or $null -eq $RightAst) { return $false }
    if (-not $LeftAst.Extent -or -not $RightAst.Extent) { return $false }

    return (
        $LeftAst.Extent.StartOffset -eq $RightAst.Extent.StartOffset -and
        $LeftAst.Extent.EndOffset -eq $RightAst.Extent.EndOffset -and
        [string]$LeftAst.Extent.Text -ceq [string]$RightAst.Extent.Text
    )
}

function Get-AstSourceTextRange {
    param(
        $ParseInfo,
        $StartAst,
        $EndAst
    )

    if ($null -eq $ParseInfo -or -not $ParseInfo.PSObject.Properties['SourceText']) { return $null }
    if ($null -eq $StartAst -or $null -eq $EndAst -or -not $StartAst.Extent -or -not $EndAst.Extent) { return $null }

    $sourceText = [string]$ParseInfo.SourceText
    $startOffset = [int]$StartAst.Extent.StartOffset
    $endOffset = [int]$EndAst.Extent.EndOffset
    if ($startOffset -lt 0 -or $endOffset -le $startOffset -or $endOffset -gt $sourceText.Length) {
        return $null
    }

    return $sourceText.Substring($startOffset, $endOffset - $startOffset)
}

function Get-CommandArgumentText {
    param(
        $CommandAst,
        $ParseInfo,
        [int]$FirstArgumentIndex = 1
    )

    if ($null -eq $CommandAst -or -not $CommandAst.CommandElements -or $CommandAst.CommandElements.Count -le $FirstArgumentIndex) {
        return $null
    }

    $firstArgument = $CommandAst.CommandElements[$FirstArgumentIndex]
    $lastArgument = $CommandAst.CommandElements[$CommandAst.CommandElements.Count - 1]
    $argumentText = Get-AstSourceTextRange -ParseInfo $ParseInfo -StartAst $firstArgument -EndAst $lastArgument
    if (-not [string]::IsNullOrWhiteSpace($argumentText)) {
        return $argumentText
    }

    return [string]$firstArgument.Extent.Text
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

function Get-CommandAstWrappedDynamicInvocationInfo {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [hashtable]$Context
    )

    if ($null -eq $CommandAst -or -not $CommandAst.CommandElements -or $CommandAst.CommandElements.Count -lt 1) {
        return [PSCustomObject]@{
            Success            = $false
            EffectiveCommand   = $null
            DynamicType        = $null
            WrapperOperator    = $null
            ArgumentStartIndex = $null
        }
    }

    $wrapperOperator = $null
    $targetAst = $null
    $argumentStartIndex = $null

    switch ([string]$CommandAst.InvocationOperator) {
        'Ampersand' {
            $wrapperOperator = '&'
            $targetAst = $CommandAst.CommandElements[0]
            $argumentStartIndex = 1
        }
        'Dot' {
            $wrapperOperator = '.'
            $targetAst = $CommandAst.CommandElements[0]
            $argumentStartIndex = 1
        }
    }

    if (-not $wrapperOperator) {
        $headText = if ($CommandAst.CommandElements[0] -and $CommandAst.CommandElements[0].Extent) {
            [string]$CommandAst.CommandElements[0].Extent.Text
        } else {
            $null
        }
        if ($headText -in @('&', '.')) {
            if ($CommandAst.CommandElements.Count -lt 2) {
                return [PSCustomObject]@{
                    Success            = $false
                    EffectiveCommand   = $null
                    DynamicType        = $null
                    WrapperOperator    = $headText
                    ArgumentStartIndex = $null
                }
            }
            $wrapperOperator = $headText
            $targetAst = $CommandAst.CommandElements[1]
            $argumentStartIndex = 2
        }
    }

    if (-not $wrapperOperator) {
        return [PSCustomObject]@{
            Success            = $false
            EffectiveCommand   = $null
            DynamicType        = $null
            WrapperOperator    = $null
            ArgumentStartIndex = $null
        }
    }

    if ($null -eq $targetAst) {
        return [PSCustomObject]@{
            Success            = $false
            EffectiveCommand   = $null
            DynamicType        = $null
            WrapperOperator    = $wrapperOperator
            ArgumentStartIndex = $null
        }
    }

    $candidateName = $null
    if ($targetAst -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
        $candidateName = Convert-DynamicCommandCandidateToName -Value $targetAst.Value
    }

    if (-not $candidateName -and $Context) {
        $safeEval = Resolve-SafeCommandNameExpressionValue -Ast $targetAst -Context $Context
        if ($safeEval.Success) {
            $candidateName = Convert-DynamicCommandCandidateToName -Value $safeEval.Value
        }
    }

    if (-not $candidateName -and $Context -and $targetAst.Extent) {
        $nameCode = Convert-CodeForCurrentScope -Code $targetAst.Extent.Text -Context $Context
        $nameEval = Invoke-InContext -ExecContext $Context.ExecContext -Code $nameCode
        if ($nameEval.Success) {
            $candidateName = Convert-DynamicCommandCandidateToName -Value (Normalize-ExecutionResultValue -Value $nameEval.Result -TreatArraysAsSequence)
        }
    }

    if ([string]::IsNullOrWhiteSpace($candidateName)) {
        return [PSCustomObject]@{
            Success            = $false
            EffectiveCommand   = $null
            DynamicType        = $null
            WrapperOperator    = $wrapperOperator
            ArgumentStartIndex = $argumentStartIndex
        }
    }

    $dynamicType = $null
    if ($candidateName -in @('Invoke-Expression', 'iex')) {
        $dynamicType = 'IEX'
    } elseif ($candidateName -match '^\[(?:System\.Management\.Automation\.)?ScriptBlock\]::Create$') {
        $dynamicType = 'ScriptBlockCreate'
    }

    return [PSCustomObject]@{
        Success            = (-not [string]::IsNullOrWhiteSpace($dynamicType))
        EffectiveCommand   = $candidateName
        DynamicType        = $dynamicType
        WrapperOperator    = $wrapperOperator
        ArgumentStartIndex = $argumentStartIndex
    }
}

function Test-PowerShellTextCandidate {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return [PSCustomObject]@{ IsUseful = $false; Score = -1; IsValid = $false }
    }

    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$tokens, [ref]$errors)
    $isValid = (-not $errors -or $errors.Count -eq 0)
    $score = if ($isValid) { 100 } else { [Math]::Max(0, 60 - (@($errors).Count * 10)) }

    if ($Text -match '(?i)\b(function|param|if|foreach|for|while|switch|return|try|catch|Invoke-|New-Object|Write-|Set-)\b') {
        $score += 10
    }
    if ($Text -match '(?m)^\s*\$[A-Za-z_][\w:]*\s*=') {
        $score += 5
    }
    if ($Text -match "(?m)^\s*#|[`r`n;]") {
        $score += 3
    }

    return [PSCustomObject]@{
        IsUseful = ($score -gt 0)
        Score    = $score
        IsValid  = $isValid
    }
}

function Convert-ByteArrayToLikelyScriptText {
    param([byte[]]$Bytes)

    if ($null -eq $Bytes -or $Bytes.Length -eq 0) {
        return [PSCustomObject]@{ Success = $false; Text = $null; Kind = $null }
    }

    $encodings = @(
        @{ Name = 'UTF8'; Encoding = [System.Text.Encoding]::UTF8 },
        @{ Name = 'Unicode'; Encoding = [System.Text.Encoding]::Unicode },
        @{ Name = 'BigEndianUnicode'; Encoding = [System.Text.Encoding]::BigEndianUnicode },
        @{ Name = 'ASCII'; Encoding = [System.Text.Encoding]::ASCII }
    )

    $best = $null
    foreach ($item in $encodings) {
        try {
            $text = $item.Encoding.GetString($Bytes)
        } catch {
            continue
        }

        $test = Test-PowerShellTextCandidate -Text $text
        if (-not $test.IsUseful) { continue }

        if ($null -eq $best -or $test.Score -gt $best.Score) {
            $best = [PSCustomObject]@{
                Success = $true
                Text    = $text
                Kind    = "ByteArray:$($item.Name)"
                Score   = $test.Score
            }
        }
    }

    if ($best) { return $best }
    return [PSCustomObject]@{ Success = $false; Text = $null; Kind = $null }
}

function Convert-DynamicInvocationValueToScriptText {
    param($Value)

    if ($null -eq $Value) {
        return [PSCustomObject]@{ Success = $false; Text = $null; Kind = $null }
    }

    $baseObject = Get-SafePSBaseObject -Value $Value
    if ($null -ne $baseObject -and $baseObject -ne $Value) {
        return Convert-DynamicInvocationValueToScriptText -Value $baseObject
    }

    if ($Value -is [string]) {
        return [PSCustomObject]@{ Success = (-not [string]::IsNullOrWhiteSpace($Value)); Text = [string]$Value; Kind = 'String' }
    }

    if ($Value -is [System.Management.Automation.ScriptBlock]) {
        $text = [string]$Value.ToString()
        return [PSCustomObject]@{ Success = (-not [string]::IsNullOrWhiteSpace($text)); Text = $text; Kind = 'ScriptBlock' }
    }

    if ($Value -is [System.Security.SecureString]) {
        $bstr = [IntPtr]::Zero
        try {
            $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
            $text = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
            return [PSCustomObject]@{ Success = (-not [string]::IsNullOrWhiteSpace($text)); Text = $text; Kind = 'SecureString' }
        } catch {
            return [PSCustomObject]@{ Success = $false; Text = $null; Kind = $null }
        } finally {
            if ($bstr -ne [IntPtr]::Zero) {
                [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
            }
        }
    }

    if ($Value -is [char[]]) {
        return [PSCustomObject]@{ Success = ($Value.Length -gt 0); Text = (-join $Value); Kind = 'CharArray' }
    }

    if ($Value -is [byte[]]) {
        return Convert-ByteArrayToLikelyScriptText -Bytes $Value
    }

    if ((Test-ExecutionResultSequenceContainer -Value $Value) -or ($Value -is [array])) {
        $items = @($Value)
        if ($items.Count -eq 0) {
            return [PSCustomObject]@{ Success = $false; Text = $null; Kind = $null }
        }

        if ($items.Count -eq 1) {
            return Convert-DynamicInvocationValueToScriptText -Value $items[0]
        }

        $allChars = $true
        $allStrings = $true
        $singleCharStrings = $true
        foreach ($item in $items) {
            if ($item -is [char]) { continue }

            if ($item -is [string]) {
                if ($item.Length -ne 1) {
                    $singleCharStrings = $false
                }
                continue
            }

            if ($item -is [ValueType]) {
                try {
                    $null = [char][int]$item
                    $allStrings = $false
                    continue
                } catch {
                }
            }

            $allChars = $false
            $allStrings = $false
            $singleCharStrings = $false
            break
        }

        if ($allChars) {
            $chars = foreach ($item in $items) {
                if ($item -is [char]) { $item }
                elseif ($item -is [string]) { [char]$item }
                else { [char][int]$item }
            }
            return [PSCustomObject]@{ Success = ($chars.Count -gt 0); Text = (-join $chars); Kind = 'SequenceChars' }
        }

        if ($allStrings) {
            $joinEmpty = ($items | ForEach-Object { [string]$_ }) -join ''
            if ($singleCharStrings) {
                return [PSCustomObject]@{ Success = (-not [string]::IsNullOrWhiteSpace($joinEmpty)); Text = $joinEmpty; Kind = 'SequenceStrings' }
            }

            $joinNewLine = ($items | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
            $emptyScore = Test-PowerShellTextCandidate -Text $joinEmpty
            $newlineScore = Test-PowerShellTextCandidate -Text $joinNewLine
            if ($newlineScore.Score -gt $emptyScore.Score) {
                return [PSCustomObject]@{ Success = (-not [string]::IsNullOrWhiteSpace($joinNewLine)); Text = $joinNewLine; Kind = 'SequenceStrings:NewLine' }
            }
            return [PSCustomObject]@{ Success = (-not [string]::IsNullOrWhiteSpace($joinEmpty)); Text = $joinEmpty; Kind = 'SequenceStrings:EmptyJoin' }
        }
    }

    return [PSCustomObject]@{ Success = $false; Text = $null; Kind = $null }
}

function Get-NodeTextExecutionInfo {
    param(
        $Node,
        [hashtable]$Context,
        [string]$SourceText = $null
    )

    $parseInfo = if ($PSBoundParameters.ContainsKey('SourceText') -and -not [string]::IsNullOrEmpty($SourceText)) {
        Get-NodeTextParseInfo -Node $Node -Context $Context -SourceText $SourceText
    } else {
        Get-NodeTextParseInfo -Node $Node -Context $Context
    }
    if (-not $parseInfo.Success) {
        return [PSCustomObject]@{
            Success       = $false
            Error         = $parseInfo.Error
            ParseInfo     = $parseInfo
            Statement     = $null
            CommandAst    = $null
            TargetVarName = $null
        }
    }

    $statement = Get-FirstStatementFromScriptAst -ScriptAst $parseInfo.Ast
    $targetVarName = $null
    if ($statement -is [System.Management.Automation.Language.AssignmentStatementAst]) {
        $leftAst = $statement.Left
        if ($leftAst -is [System.Management.Automation.Language.VariableExpressionAst]) {
            $targetVarName = $leftAst.VariablePath.UserPath
        }
    }

    $primaryCommandAst = Get-PrimaryCommandAstFromScriptAst -ScriptAst $parseInfo.Ast
    $topLevelCommandAst = Get-TopLevelCommandAstFromStatementAst -StatementAst $statement

    return [PSCustomObject]@{
        Success       = $true
        Error         = $null
        ParseInfo     = $parseInfo
        Statement     = $statement
        CommandAst    = $primaryCommandAst
        TopLevelCommandAst = $topLevelCommandAst
        IsTopLevelCommandInvocation = (Test-AstExtentEquals `
            -LeftAst $primaryCommandAst `
            -RightAst $topLevelCommandAst)
        TargetVarName = $targetVarName
    }
}

function Get-NodeAstGlobalExtent {
    param(
        $Node,
        $Ast
    )

    if ($null -eq $Ast -or -not $Ast.Extent) { return $null }

    $startOffset = [int]$Ast.Extent.StartOffset
    $endOffset = [int]$Ast.Extent.EndOffset

    if ($Node -and $Node.PSObject.Properties['TextStartOffset'] -and $null -ne $Node.TextStartOffset) {
        $baseOffset = [int]$Node.TextStartOffset
        $startOffset = $baseOffset + $startOffset
        $endOffset = $baseOffset + $endOffset
    }

    return [PSCustomObject]@{
        StartOffset = $startOffset
        EndOffset   = $endOffset
        Text        = [string]$Ast.Extent.Text
    }
}

function Resolve-InvocationArgumentValue {
    param(
        $ArgumentAst,
        [hashtable]$Context,
        [int]$CallerNodeId = -1
    )

    if (-not $ArgumentAst) {
        return [PSCustomObject]@{
            Success = $true
            Value   = $true
        }
    }

    $argCode = $ArgumentAst.Extent.Text
    if ($ArgumentAst -and $Context.FunctionSubgraphs.Count -gt 0) {
        $argCode = Resolve-EmbeddedFunctionCalls -Code $argCode -Ast $ArgumentAst -Context $Context -NodeId $CallerNodeId
    }

    $argCode = Convert-CodeForCurrentScope -Code $argCode -Context $Context
    $argResult = Invoke-InContext -ExecContext $Context.ExecContext -Code $argCode
    if ($argResult.Success) {
        return [PSCustomObject]@{
            Success = $true
            Value   = (Normalize-ExecutionResultValue -Value $argResult.Result -TreatArraysAsSequence)
        }
    }

    return [PSCustomObject]@{
        Success = $false
        Value   = $null
    }
}

function Get-CommandInvocationBindings {
    param(
        $CommandAst,
        [hashtable]$Context,
        [int]$StartIndex = 1,
        [int]$CallerNodeId = -1
    )

    $positionalArguments = @()
    $namedArguments = [ordered]@{}
    $logEntries = @()

    if (-not $CommandAst -or -not $CommandAst.CommandElements) {
        return [PSCustomObject]@{
            PositionalArguments = @()
            NamedArguments      = [ordered]@{}
            LogEntries          = @()
        }
    }

    for ($i = $StartIndex; $i -lt $CommandAst.CommandElements.Count; $i++) {
        $elem = $CommandAst.CommandElements[$i]

        if ($elem -is [System.Management.Automation.Language.CommandParameterAst]) {
            $paramName = [string]$elem.ParameterName
            $argAst = $null
            if ($elem.Argument) {
                $argAst = $elem.Argument
            } elseif (($i + 1) -lt $CommandAst.CommandElements.Count -and
                $CommandAst.CommandElements[$i + 1] -isnot [System.Management.Automation.Language.CommandParameterAst]) {
                $i++
                $argAst = $CommandAst.CommandElements[$i]
            }

            $resolved = Resolve-InvocationArgumentValue -ArgumentAst $argAst -Context $Context -CallerNodeId $CallerNodeId
            $namedArguments[$paramName] = $resolved.Value
            $logEntries += [PSCustomObject]@{
                Kind    = 'Named'
                Name    = $paramName
                Display = "-$paramName"
                Success = [bool]$resolved.Success
                Value   = $resolved.Value
            }
            continue
        }

        $resolved = Resolve-InvocationArgumentValue -ArgumentAst $elem -Context $Context -CallerNodeId $CallerNodeId
        # Preserve array-valued arguments as a single positional argument.
        $positionalArguments += ,$resolved.Value
        $logEntries += [PSCustomObject]@{
            Kind    = 'Positional'
            Name    = $null
            Display = if ($elem.Extent) { [string]$elem.Extent.Text } else { $null }
            Success = [bool]$resolved.Success
            Value   = $resolved.Value
        }
    }

    return [PSCustomObject]@{
        PositionalArguments = @($positionalArguments)
        NamedArguments      = $namedArguments
        LogEntries          = @($logEntries)
    }
}

function Get-NodeTextExecutionInfoWithFallback {
    param(
        $Node,
        [hashtable]$Context,
        [AllowEmptyCollection()][string[]]$CandidateSourceTexts = @(),
        [switch]$AllowOriginalAstFallback
    )

    $sources = New-Object System.Collections.Generic.List[string]
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)

    foreach ($text in @($CandidateSourceTexts)) {
        if ($null -eq $text) { continue }
        $value = [string]$text
        if ([string]::IsNullOrWhiteSpace($value)) { continue }
        if ($seen.Add($value)) {
            $sources.Add($value) | Out-Null
        }
    }

    if ($sources.Count -eq 0 -and $Node) {
        $nodeText = [string]$Node.Text
        if (-not [string]::IsNullOrWhiteSpace($nodeText) -and $seen.Add($nodeText)) {
            $sources.Add($nodeText) | Out-Null
        }
    }

    if ($AllowOriginalAstFallback -and $Node -and $Node.Ast -and $Node.Ast.Extent) {
        $astText = [string]$Node.Ast.Extent.Text
        if (-not [string]::IsNullOrWhiteSpace($astText) -and $seen.Add($astText)) {
            $sources.Add($astText) | Out-Null
        }
    }

    if ($sources.Count -eq 0) {
        return [PSCustomObject]@{
            Success       = $false
            Error         = 'No available source text for parse fallback'
            ParseInfo     = $null
            Statement     = $null
            CommandAst    = $null
            TopLevelCommandAst = $null
            IsTopLevelCommandInvocation = $false
            TargetVarName = $null
            SourceTextUsed = $null
        }
    }

    $errors = New-Object System.Collections.Generic.List[string]
    foreach ($sourceText in $sources) {
        $execInfo = Get-NodeTextExecutionInfo -Node $Node -Context $Context -SourceText $sourceText
        if ($execInfo.Success) {
            $execInfo | Add-Member -NotePropertyName SourceTextUsed -NotePropertyValue $sourceText -Force
            return $execInfo
        }

        $sourceLabel = if ($Node -and $Node.Ast -and $Node.Ast.Extent -and ([string]$Node.Ast.Extent.Text -ceq $sourceText)) {
            'AstText'
        } elseif ($Node -and ([string]$Node.Text -ceq $sourceText)) {
            'NodeText'
        } else {
            'Override'
        }
        $errors.Add(("{0}: {1}" -f $sourceLabel, [string]$execInfo.Error)) | Out-Null
    }

    return [PSCustomObject]@{
        Success        = $false
        Error          = ($errors -join ' | ')
        ParseInfo      = $null
        Statement      = $null
        CommandAst     = $null
        TopLevelCommandAst = $null
        IsTopLevelCommandInvocation = $false
        TargetVarName  = $null
        SourceTextUsed = $null
    }
}

function Get-NodeTextScriptBlockArguments {
    param(
        $CallerNode,
        [string]$BlockName,
        [hashtable]$Context
    )

    $execInfo = Get-NodeTextExecutionInfo -Node $CallerNode -Context $Context
    if (-not $execInfo.Success) {
        return [PSCustomObject]@{
            Success   = $false
            Error     = $execInfo.Error
            Arguments = @()
        }
    }

    $arguments = @()
    $scriptAst = $execInfo.ParseInfo.Ast

    $invokeAst = $scriptAst.Find({
        param($n)
        if (-not ($n -is [System.Management.Automation.Language.InvokeMemberExpressionAst])) { return $false }
        if (-not ($n.Member -is [System.Management.Automation.Language.StringConstantExpressionAst])) { return $false }
        return $n.Member.Value -eq "Invoke"
    }, $true)

    if ($invokeAst -and $invokeAst.Arguments) {
        foreach ($argAst in $invokeAst.Arguments) {
            $argCode = Convert-CodeForCurrentScope -Code $argAst.Extent.Text -Context $Context
            $argResult = Invoke-InContext -ExecContext $Context.ExecContext -Code $argCode
            if ($argResult.Success) {
                $argValue = Normalize-ExecutionResultValue -Value $argResult.Result -TreatArraysAsSequence
                $arguments += ,$argValue
            } else {
                $arguments += ,$null
            }
        }

        return [PSCustomObject]@{
            Success   = $true
            Error     = $null
            Arguments = $arguments
        }
    }

    $cmdAst = $execInfo.CommandAst
    if (-not $cmdAst) {
        return [PSCustomObject]@{
            Success   = $true
            Error     = $null
            Arguments = @()
        }
    }

    $cmdName = $cmdAst.GetCommandName()
    if ($cmdName -in @('Invoke-Command', 'icm')) {
        $i = 1
        while ($i -lt $cmdAst.CommandElements.Count) {
            $elem = $cmdAst.CommandElements[$i]
            if ($elem -is [System.Management.Automation.Language.CommandParameterAst] -and
                $elem.ParameterName -in @('ArgumentList', 'Args')) {
                $argListAst = $null
                if ($elem.Argument) {
                    $argListAst = $elem.Argument
                } elseif ($i + 1 -lt $cmdAst.CommandElements.Count) {
                    $i++
                    $argListAst = $cmdAst.CommandElements[$i]
                }
                if ($argListAst) {
                    $arguments = Get-ArgumentListValues -Ast $argListAst -Context $Context
                    break
                }
            }
            $i++
        }

        return [PSCustomObject]@{
            Success   = $true
            Error     = $null
            Arguments = $arguments
        }
    }

    $startIndex = 1
    for ($i = 0; $i -lt $cmdAst.CommandElements.Count; $i++) {
        $elem = $cmdAst.CommandElements[$i]
        if ($elem -is [System.Management.Automation.Language.VariableExpressionAst]) {
            $varName = $elem.VariablePath.UserPath
            if ($varName -eq $BlockName) {
                $startIndex = $i + 1
                break
            }
        }
    }

    for ($i = $startIndex; $i -lt $cmdAst.CommandElements.Count; $i++) {
        $argAst = $cmdAst.CommandElements[$i]
        if ($argAst -is [System.Management.Automation.Language.CommandParameterAst]) {
            continue
        }

        $argCode = Convert-CodeForCurrentScope -Code $argAst.Extent.Text -Context $Context
        $argResult = Invoke-InContext -ExecContext $Context.ExecContext -Code $argCode
        if ($argResult.Success) {
            $argValue = Normalize-ExecutionResultValue -Value $argResult.Result -TreatArraysAsSequence
            $arguments += ,$argValue
        } else {
            $arguments += ,$null
        }
    }

    return [PSCustomObject]@{
        Success   = $true
        Error     = $null
        Arguments = $arguments
    }
}

function Get-NodeTextReturnExpression {
    param(
        $Node,
        [hashtable]$Context
    )

    $parseInfo = Get-NodeTextParseInfo -Node $Node -Context $Context
    if (-not $parseInfo.Success) {
        return [PSCustomObject]@{
            Success = $false
            Error   = $parseInfo.Error
            Code    = $null
        }
    }

    $returnAst = $parseInfo.Ast.Find({
        param($n)
        $n -is [System.Management.Automation.Language.ReturnStatementAst]
    }, $true)

    if ($returnAst -and $returnAst.Pipeline) {
        return [PSCustomObject]@{
            Success = $true
            Error   = $null
            Code    = $returnAst.Pipeline.Extent.Text
        }
    }

    return [PSCustomObject]@{
        Success = $true
        Error   = $null
        Code    = $null
    }
}

function Get-DynamicArgumentCodeFromNodeText {
    param(
        $Node,
        [hashtable]$Context,
        [string]$DynamicType,
        [string]$NodeTextOverride = $null,
        $CommandInfo = $null
    )

    $parseInfo = if (-not [string]::IsNullOrEmpty($NodeTextOverride)) {
        Get-NodeTextParseInfo -Node $Node -Context $Context -SourceText $NodeTextOverride
    } else {
        Get-NodeTextParseInfo -Node $Node -Context $Context
    }
    if (-not $parseInfo.Success) {
        return [PSCustomObject]@{
            Success = $false
            Error   = $parseInfo.Error
            Code    = $null
        }
    }

    $scriptAst = $parseInfo.Ast
    $argCode = $null
    $displayCode = $null
    $fromPipelineInput = $false
    $replacementStartOffset = $null
    $replacementEndOffset = $null
    $statement = Get-FirstStatementFromScriptAst -ScriptAst $scriptAst
    $topLevelCommandAst = Get-TopLevelCommandAstFromStatementAst -StatementAst $statement
    if ($statement -and $statement.Extent) {
        $replacementStartOffset = [int]$statement.Extent.StartOffset
        $replacementEndOffset = [int]$statement.Extent.EndOffset
    }

    function Get-PipelineInputExpressionText {
        param($StatementAst, $TargetCommandAst)

        if ($null -eq $StatementAst -or $null -eq $TargetCommandAst) { return $null }
        if ($StatementAst -isnot [System.Management.Automation.Language.PipelineAst]) { return $null }

        $elements = @($StatementAst.PipelineElements)
        for ($i = 0; $i -lt $elements.Count; $i++) {
            if ($elements[$i] -ne $TargetCommandAst) { continue }
            if ($i -le 0) { return $null }

            return (($elements[0..($i - 1)] | ForEach-Object { $_.Extent.Text }) -join ' | ')
        }

        return $null
    }

    if ($DynamicType -in @("ScriptBlockCreate", "NewScriptBlock")) {
        $invokeAsts = @($scriptAst.FindAll({
            param($n)
            $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst]
        }, $true))

        foreach ($invokeAst in $invokeAsts) {
            $memberName = $invokeAst.Member
            if ($memberName -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                $memberName = $memberName.Value
            }

            if ($DynamicType -eq "ScriptBlockCreate") {
                if ($invokeAst.Static -and $memberName -eq "Create" -and $invokeAst.Arguments -and $invokeAst.Arguments.Count -gt 0) {
                    $argCode = $invokeAst.Arguments[0].Extent.Text
                    $displayCode = $argCode
                    break
                }
            } elseif ($DynamicType -eq "NewScriptBlock") {
                if (-not $invokeAst.Static -and $memberName -eq "NewScriptBlock" -and $invokeAst.Arguments -and $invokeAst.Arguments.Count -gt 0) {
                    $argCode = $invokeAst.Arguments[0].Extent.Text
                    $displayCode = $argCode
                    break
                }
            }
        }
    }

    if (-not $argCode) {
        $cmdAst = Get-PrimaryCommandAstFromScriptAst -ScriptAst $scriptAst
        if ($cmdAst -and $cmdAst.CommandElements -and $cmdAst.CommandElements.Count -gt 1) {
            if ($DynamicType -in @("IEX", "PowerShellCommand") -and $cmdAst.Extent) {
                $replacementStartOffset = [int]$cmdAst.Extent.StartOffset
                $replacementEndOffset = [int]$cmdAst.Extent.EndOffset
            }

            $cmdName = $cmdAst.GetCommandName()
            if (($null -eq $cmdName -or [string]::IsNullOrWhiteSpace([string]$cmdName) -or [string]$cmdName -match '^[&\.]') -and
                $CommandInfo -and $CommandInfo.PSObject.Properties['ResolvedName']) {
                $cmdName = [string]$CommandInfo.ResolvedName
            }
            $wrappedDynamic = Get-CommandAstWrappedDynamicInvocationInfo -CommandAst $cmdAst -Context $Context
            $normalizedCmdName = Convert-DynamicCommandCandidateToName -Value $cmdName
            $isIex = $cmdName -in @("Invoke-Expression", "iex")
            if (-not $isIex -and $normalizedCmdName -in @('Invoke-Expression', 'iex')) {
                $isIex = $true
            }
            $isScriptBlockCreateCommand = $cmdName -match '^\[(?:System\.Management\.Automation\.)?ScriptBlock\]::Create$'
            if (-not $isScriptBlockCreateCommand -and $normalizedCmdName -match '^\[(?:System\.Management\.Automation\.)?ScriptBlock\]::Create$') {
                $isScriptBlockCreateCommand = $true
            }
            $hostDynamicInfo = Get-PowerShellHostDynamicInvocationInfo -CommandAst $cmdAst
            $wrappedDynamicType = [string](Get-CFGObjectPropertyValue -Object $wrappedDynamic -Name 'DynamicType' -Default $null)
            $hostDynamicType = [string](Get-CFGObjectPropertyValue -Object $hostDynamicInfo -Name 'DynamicType' -Default $null)
            if (($DynamicType -eq "IEX" -and $wrappedDynamic.Success -and $wrappedDynamicType -eq 'IEX') -or
                ($DynamicType -eq 'ScriptBlockCreate' -and $wrappedDynamic.Success -and $wrappedDynamicType -eq 'ScriptBlockCreate')) {
                $argCode = Get-CommandArgumentText -CommandAst $cmdAst -ParseInfo $parseInfo -FirstArgumentIndex $wrappedDynamic.ArgumentStartIndex
                if ([string]::IsNullOrWhiteSpace($argCode) -and $cmdAst.CommandElements.Count -gt $wrappedDynamic.ArgumentStartIndex) {
                    $argCode = $cmdAst.CommandElements[$wrappedDynamic.ArgumentStartIndex].Extent.Text
                }
                $displayCode = $argCode
            } elseif (($DynamicType -eq "IEX" -and $isIex) -or
                ($DynamicType -eq "ScriptBlockCreate" -and $isScriptBlockCreateCommand)) {
                $argCode = Get-CommandArgumentText -CommandAst $cmdAst -ParseInfo $parseInfo
                if ([string]::IsNullOrWhiteSpace($argCode)) {
                    $argCode = $cmdAst.CommandElements[1].Extent.Text
                }
                $displayCode = $argCode
            } elseif ($DynamicType -eq 'PowerShellCommand' -and $hostDynamicType -eq 'PowerShellCommand') {
                $argCode = $hostDynamicInfo.EvaluationCode
                $displayCode = $hostDynamicInfo.PayloadText
            }
        }

        if (-not $argCode -and $DynamicType -eq "IEX" -and $cmdAst) {
            $statement = Get-FirstStatementFromScriptAst -ScriptAst $scriptAst
            $pipelineInputCode = Get-PipelineInputExpressionText -StatementAst $statement -TargetCommandAst $cmdAst
            if (-not [string]::IsNullOrWhiteSpace($pipelineInputCode)) {
                $displayCode = $pipelineInputCode
                $fromPipelineInput = $true
            }
        }
    }

    if ($DynamicType -in @("IEX", "PowerShellCommand") -and $topLevelCommandAst -and $topLevelCommandAst.Extent) {
        $replacementStartOffset = [int]$topLevelCommandAst.Extent.StartOffset
        $replacementEndOffset = [int]$topLevelCommandAst.Extent.EndOffset
    }

    return [PSCustomObject]@{
        Success     = $true
        Error       = $null
        Code        = $argCode
        DisplayCode = $displayCode
        FromPipelineInput = $fromPipelineInput
        ReplacementStartOffset = $replacementStartOffset
        ReplacementEndOffset = $replacementEndOffset
    }
}

function Get-NodeTextResolvables {
    param(
        $Node,
        [hashtable]$Context
    )

    $parseInfo = Get-NodeTextParseInfo -Node $Node -Context $Context
    if (-not $parseInfo.Success) {
        return [PSCustomObject]@{
            Success = $false
            Error   = $parseInfo.Error
            Items   = @()
        }
    }

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

    $allExprs = @($parseInfo.Ast.FindAll({
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
        while ($null -ne $ancestor -and $ancestor -ne $parseInfo.Ast) {
            if ($ancestor -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
                return $false
            }
            $ancestor = $ancestor.Parent
        }
        return $true
    })

    $sortedExprs = @($allExprs | Sort-Object { $_.Extent.StartOffset })

    $originalQueues = @{}
    if ($Node.Resolvables) {
        foreach ($orig in $Node.Resolvables) {
            $qKey = "$($orig.Type)|$($orig.Text)"
            if (-not $originalQueues.ContainsKey($qKey)) {
                $originalQueues[$qKey] = [System.Collections.Generic.Queue[object]]::new()
            }
            $originalQueues[$qKey].Enqueue($orig)
        }
    }

    $items = @()
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
        while ($null -ne $ancestor -and $ancestor -ne $parseInfo.Ast) {
            if ($ancestor -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) { break }
            foreach ($t in $targetTypes) {
                if ($ancestor -is $t) { $depth++; break }
            }
            $ancestor = $ancestor.Parent
        }

        $mapped = $false
        $startOffset = $null
        $endOffset = $null
        $qKey = "$type|$($expr.Extent.Text)"
        if ($originalQueues.ContainsKey($qKey) -and $originalQueues[$qKey].Count -gt 0) {
            $orig = $originalQueues[$qKey].Dequeue()
            $mapped = $true
            $startOffset = $orig.StartOffset
            $endOffset = $orig.EndOffset
        }

        $items += [PSCustomObject]@{
            Type             = $type
            Ast              = $expr
            Text             = $expr.Extent.Text
            LocalStartOffset = $expr.Extent.StartOffset
            LocalEndOffset   = $expr.Extent.EndOffset
            Depth            = $depth
            Mapped           = $mapped
            StartOffset      = $startOffset
            EndOffset        = $endOffset
        }
    }

    return [PSCustomObject]@{
        Success = $true
        Error   = $null
        Items   = $items
    }
}

function Get-CFGExecutionIndexes {
    param([hashtable]$CFG)

    if ($null -eq $CFG) { return $null }

    if (-not $CFG.ContainsKey('__ExecIndexes') -or $null -eq $CFG['__ExecIndexes']) {
        $CFG['__ExecIndexes'] = @{
            NodeById         = @{}
            EdgesByFrom      = @{}
            EdgeLabelByPair  = @{}
            FirstNodeByType  = @{}
            IndexedNodeCount = -1
            IndexedEdgeCount = -1
            LastIndexedNodeCount = -1
            LastIndexedEdgeCount = -1
            Generation       = 0
            FallbackCount    = 0
            FallbackCountByGeneration = @{}
            IncrementalUpdateCount = 0
        }
    }

    $indexes = $CFG['__ExecIndexes']
    if (-not $indexes.ContainsKey('NodeById') -or $null -eq $indexes.NodeById) { $indexes.NodeById = @{} }
    if (-not $indexes.ContainsKey('EdgesByFrom') -or $null -eq $indexes.EdgesByFrom) { $indexes.EdgesByFrom = @{} }
    if (-not $indexes.ContainsKey('EdgeLabelByPair') -or $null -eq $indexes.EdgeLabelByPair) { $indexes.EdgeLabelByPair = @{} }
    if (-not $indexes.ContainsKey('FirstNodeByType') -or $null -eq $indexes.FirstNodeByType) { $indexes.FirstNodeByType = @{} }
    if (-not $indexes.ContainsKey('IndexedNodeCount')) { $indexes.IndexedNodeCount = -1 }
    if (-not $indexes.ContainsKey('IndexedEdgeCount')) { $indexes.IndexedEdgeCount = -1 }
    if (-not $indexes.ContainsKey('LastIndexedNodeCount')) { $indexes.LastIndexedNodeCount = [int]$indexes.IndexedNodeCount }
    if (-not $indexes.ContainsKey('LastIndexedEdgeCount')) { $indexes.LastIndexedEdgeCount = [int]$indexes.IndexedEdgeCount }
    if (-not $indexes.ContainsKey('Generation')) { $indexes.Generation = 0 }
    if (-not $indexes.ContainsKey('FallbackCount')) { $indexes.FallbackCount = 0 }
    if (-not $indexes.ContainsKey('FallbackCountByGeneration') -or $null -eq $indexes.FallbackCountByGeneration) { $indexes.FallbackCountByGeneration = @{} }
    if (-not $indexes.ContainsKey('IncrementalUpdateCount')) { $indexes.IncrementalUpdateCount = 0 }

    return $indexes
}

function Add-CFGExecutionIndexFallback {
    param(
        [hashtable]$Indexes,
        [int]$Count = 1
    )

    if ($null -eq $Indexes) { return }

    $countToAdd = if ($Count -gt 0) { [int]$Count } else { 1 }
    $Indexes.FallbackCount = [int]$Indexes.FallbackCount + $countToAdd

    $generation = [int]$Indexes.Generation
    if (-not $Indexes.FallbackCountByGeneration.ContainsKey($generation)) {
        $Indexes.FallbackCountByGeneration[$generation] = 0
    }
    $Indexes.FallbackCountByGeneration[$generation] = [int]$Indexes.FallbackCountByGeneration[$generation] + $countToAdd
}

function Add-CFGNodeToIndexes {
    param(
        [hashtable]$Indexes,
        $Node
    )

    if ($null -eq $Indexes -or $null -eq $Node) { return $false }

    $nodeId = [int]$Node.Id
    if ($Indexes.NodeById.ContainsKey($nodeId)) {
        if ([object]::ReferenceEquals($Indexes.NodeById[$nodeId], $Node)) {
            return $true
        }
        throw "CFG execution index conflict for NodeId $nodeId"
    }

    $Indexes.NodeById[$nodeId] = $Node
    $nodeType = [string]$Node.Type
    if (-not $Indexes.FirstNodeByType.ContainsKey($nodeType)) {
        $Indexes.FirstNodeByType[$nodeType] = $Node
    }
    return $true
}

function Add-CFGEdgeToIndexes {
    param(
        [hashtable]$Indexes,
        $Edge
    )

    if ($null -eq $Indexes -or $null -eq $Edge) { return $false }

    $fromId = [int]$Edge.From
    if (-not $Indexes.EdgesByFrom.ContainsKey($fromId) -or $null -eq $Indexes.EdgesByFrom[$fromId]) {
        $Indexes.EdgesByFrom[$fromId] = New-Object System.Collections.ArrayList
    }
    $null = $Indexes.EdgesByFrom[$fromId].Add($Edge)

    $pairKey = '{0}->{1}' -f [int]$Edge.From, [int]$Edge.To
    if (-not $Indexes.EdgeLabelByPair.ContainsKey($pairKey)) {
        $Indexes.EdgeLabelByPair[$pairKey] = [string]$Edge.Label
    }

    return $true
}

function Sync-CFGExecutionIndexesIncremental {
    param(
        [hashtable]$CFG,
        [object[]]$NewNodes = @(),
        [object[]]$NewEdges = @(),
        [switch]$ForceRebuild
    )

    $indexes = Get-CFGExecutionIndexes -CFG $CFG
    if ($null -eq $indexes) { return $null }

    if ($ForceRebuild) {
        return Ensure-CFGExecutionIndexes -CFG $CFG
    }

    $currentNodeCount = if ($null -ne $CFG.Nodes) { @($CFG.Nodes).Count } else { 0 }
    $currentEdgeCount = if ($null -ne $CFG.Edges) { @($CFG.Edges).Count } else { 0 }
    $newNodes = @($NewNodes | Where-Object { $null -ne $_ })
    $newEdges = @($NewEdges | Where-Object { $null -ne $_ })

    $canIncrementallySync = (
        $indexes.IndexedNodeCount -ge 0 -and
        $indexes.IndexedEdgeCount -ge 0 -and
        $null -ne $indexes.NodeById -and
        $null -ne $indexes.EdgesByFrom -and
        $null -ne $indexes.EdgeLabelByPair -and
        $null -ne $indexes.FirstNodeByType
    )

    $expectedNodeCount = [int]$indexes.IndexedNodeCount + $newNodes.Count
    $expectedEdgeCount = [int]$indexes.IndexedEdgeCount + $newEdges.Count

    if (-not $canIncrementallySync -or $expectedNodeCount -ne $currentNodeCount -or $expectedEdgeCount -ne $currentEdgeCount) {
        return Ensure-CFGExecutionIndexes -CFG $CFG
    }

    foreach ($node in $newNodes) {
        $null = Add-CFGNodeToIndexes -Indexes $indexes -Node $node
    }
    foreach ($edge in $newEdges) {
        $null = Add-CFGEdgeToIndexes -Indexes $indexes -Edge $edge
    }

    $indexes.IndexedNodeCount = $currentNodeCount
    $indexes.IndexedEdgeCount = $currentEdgeCount
    $indexes.LastIndexedNodeCount = $currentNodeCount
    $indexes.LastIndexedEdgeCount = $currentEdgeCount

    if ($newNodes.Count -gt 0 -or $newEdges.Count -gt 0) {
        $indexes.IncrementalUpdateCount = [int]$indexes.IncrementalUpdateCount + 1
    }
    if (-not $indexes.FallbackCountByGeneration.ContainsKey([int]$indexes.Generation)) {
        $indexes.FallbackCountByGeneration[[int]$indexes.Generation] = 0
    }

    return $indexes
}

function Ensure-CFGExecutionIndexes {
    param([hashtable]$CFG)

    $indexes = Get-CFGExecutionIndexes -CFG $CFG
    if ($null -eq $indexes) { return $null }

    $nodes = if ($null -ne $CFG.Nodes) { @($CFG.Nodes) } else { @() }
    $edges = if ($null -ne $CFG.Edges) { @($CFG.Edges) } else { @() }
    $nodeCount = $nodes.Count
    $edgeCount = $edges.Count

    $needsRebuild = (
        $indexes.IndexedNodeCount -ne $nodeCount -or
        $indexes.IndexedEdgeCount -ne $edgeCount -or
        $null -eq $indexes.NodeById -or
        $null -eq $indexes.EdgesByFrom -or
        $null -eq $indexes.EdgeLabelByPair -or
        $null -eq $indexes.FirstNodeByType
    )

    if (-not $needsRebuild) {
        return $indexes
    }

    $nodeById = @{}
    $edgesByFrom = @{}
    $edgeLabelByPair = @{}
    $firstNodeByType = @{}

    foreach ($node in $nodes) {
        if ($null -eq $node) { continue }
        $nodeId = [int]$node.Id
        $nodeById[$nodeId] = $node
        $nodeType = [string]$node.Type
        if (-not $firstNodeByType.ContainsKey($nodeType)) {
            $firstNodeByType[$nodeType] = $node
        }
    }

    foreach ($edge in $edges) {
        if ($null -eq $edge) { continue }
        $fromId = [int]$edge.From
        if (-not $edgesByFrom.ContainsKey($fromId)) {
            $edgesByFrom[$fromId] = New-Object System.Collections.ArrayList
        }
        $null = $edgesByFrom[$fromId].Add($edge)

        $pairKey = '{0}->{1}' -f [int]$edge.From, [int]$edge.To
        if (-not $edgeLabelByPair.ContainsKey($pairKey)) {
            $edgeLabelByPair[$pairKey] = [string]$edge.Label
        }
    }

    $indexes.NodeById = $nodeById
    $indexes.EdgesByFrom = $edgesByFrom
    $indexes.EdgeLabelByPair = $edgeLabelByPair
    $indexes.FirstNodeByType = $firstNodeByType
    $indexes.Generation = [int]$indexes.Generation + 1
    $indexes.IndexedNodeCount = $nodeCount
    $indexes.IndexedEdgeCount = $edgeCount
    $indexes.LastIndexedNodeCount = $nodeCount
    $indexes.LastIndexedEdgeCount = $edgeCount
    $indexes.FallbackCountByGeneration[[int]$indexes.Generation] = 0

    return $indexes
}

function Get-CFGOutgoingEdges {
    param(
        [hashtable]$CFG,
        [int]$FromNodeId
    )

    $indexes = Ensure-CFGExecutionIndexes -CFG $CFG
    if ($null -eq $indexes) { return @() }

    if ($indexes.EdgesByFrom.ContainsKey($FromNodeId)) {
        return @($indexes.EdgesByFrom[$FromNodeId])
    }

    $fallbackEdges = @($CFG.Edges | Where-Object { $_.From -eq $FromNodeId })
    Add-CFGExecutionIndexFallback -Indexes $indexes
    $indexes.EdgesByFrom[$FromNodeId] = $fallbackEdges
    return @($fallbackEdges)
}

function Get-CFGFirstNodeByType {
    param(
        [hashtable]$CFG,
        [string]$Type
    )

    $indexes = Ensure-CFGExecutionIndexes -CFG $CFG
    if ($null -eq $indexes) { return $null }

    if ($indexes.FirstNodeByType.ContainsKey($Type)) {
        return $indexes.FirstNodeByType[$Type]
    }

    $node = $CFG.Nodes | Where-Object { $_.Type -eq $Type } | Select-Object -First 1
    if ($node) {
        $indexes.FirstNodeByType[$Type] = $node
    }
    Add-CFGExecutionIndexFallback -Indexes $indexes
    return $node
}

function Get-NodeById {
    param(
        [hashtable]$CFG,
        [int]$Id
    )

    $indexes = Ensure-CFGExecutionIndexes -CFG $CFG
    if ($null -eq $indexes) { return $null }

    if ($indexes.NodeById.ContainsKey($Id)) {
        return $indexes.NodeById[$Id]
    }

    $node = $CFG.Nodes | Where-Object { $_.Id -eq $Id } | Select-Object -First 1
    if ($node) {
        $indexes.NodeById[$Id] = $node
    }
    Add-CFGExecutionIndexFallback -Indexes $indexes
    return $node
}

function Resolve-CFGNodeValue {
    param(
        [hashtable]$CFG,
        $Value
    )

    if ($null -eq $Value) { return $null }

    if ($Value -is [hashtable]) {
        if ($Value.ContainsKey('Id') -and $null -ne $Value['Id']) {
            Ensure-CFGNodeExecutionShape -Node $Value
            return $Value
        }
        if ($Value.ContainsKey('NodeId') -and $null -ne $Value['NodeId'] -and $CFG) {
            try {
                $node = Get-NodeById -CFG $CFG -Id ([int]$Value['NodeId'])
                if ($node) {
                    Ensure-CFGNodeExecutionShape -Node $node
                    return $node
                }
            } catch {
            }
        }
    } else {
        $idProp = $Value.PSObject.Properties['Id']
        if ($null -ne $idProp -and $null -ne $idProp.Value) {
            Ensure-CFGNodeExecutionShape -Node $Value
            return $Value
        }

        $nodeIdProp = $Value.PSObject.Properties['NodeId']
        if ($null -ne $nodeIdProp -and $null -ne $nodeIdProp.Value -and $CFG) {
            try {
                $node = Get-NodeById -CFG $CFG -Id ([int]$nodeIdProp.Value)
                if ($node) {
                    Ensure-CFGNodeExecutionShape -Node $node
                    return $node
                }
            } catch {
            }
        }
    }

    if ($CFG) {
        $candidateId = 0
        $hasCandidateId = $false

        if ($Value -is [int] -or $Value -is [long] -or $Value -is [short] -or $Value -is [byte]) {
            $candidateId = [int]$Value
            $hasCandidateId = $true
        } elseif ($Value -is [string]) {
            $parsedId = 0
            if ([int]::TryParse([string]$Value, [ref]$parsedId)) {
                $candidateId = $parsedId
                $hasCandidateId = $true
            }
        }

        if ($hasCandidateId) {
            $node = Get-NodeById -CFG $CFG -Id $candidateId
            if ($node) {
                Ensure-CFGNodeExecutionShape -Node $node
                return $node
            }
        }
    }

    $shouldEnumerate = ($Value -is [System.Array]) -or
        ($Value -is [System.Collections.IEnumerable] -and
         -not ($Value -is [string]) -and
         -not ($Value -is [hashtable]) -and
         $null -eq $Value.PSObject.Properties['Id'] -and
         $null -eq $Value.PSObject.Properties['NodeId'])

    if ($shouldEnumerate) {
        foreach ($item in @($Value)) {
            $resolvedItem = Resolve-CFGNodeValue -CFG $CFG -Value $item
            if ($null -ne $resolvedItem) {
                return $resolvedItem
            }
        }
    }

    return $null
}

function ConvertTo-CFGNodeArray {
    param(
        [hashtable]$CFG,
        $Value
    )

    $items = @()
    $pending = New-Object System.Collections.Generic.Queue[object]
    $pending.Enqueue($Value)

    while ($pending.Count -gt 0) {
        $item = $pending.Dequeue()
        if ($null -eq $item) { continue }

        $shouldEnumerate = ($item -is [System.Array]) -or
            ($item -is [System.Collections.IEnumerable] -and
             -not ($item -is [string]) -and
             -not ($item -is [hashtable]) -and
             $null -eq $item.PSObject.Properties['Id'] -and
             $null -eq $item.PSObject.Properties['NodeId'])

        if ($shouldEnumerate) {
            foreach ($nestedItem in @($item)) {
                if ($null -ne $nestedItem) {
                    $pending.Enqueue($nestedItem)
                }
            }
            continue
        }

        $resolvedNode = Resolve-CFGNodeValue -CFG $CFG -Value $item
        if ($resolvedNode) {
            $items += $resolvedNode
        }
    }

    return @($items)
}

function Get-NextNodes {
    param(
        [hashtable]$CFG,
        $Node,
        [hashtable]$Context
    )

    if ($null -eq $Node) {
        return @()
    }

    $edges = Get-CFGOutgoingEdges -CFG $CFG -FromNodeId $Node.Id

    switch ($Node.Type) {
        "If Condition" {
            $edge = $edges | Where-Object { $_.Label -eq "Condition" } | Select-Object -First 1
            if ($edge) { return (ConvertTo-CFGNodeArray -CFG $CFG -Value (Get-NodeById -CFG $CFG -Id $edge.To)) }
            return @()
        }

        "Condition" {
            if ($Context.LastConditionResult) {
                $edge = $edges | Where-Object { $_.Label -eq "True" } | Select-Object -First 1
            } else {
                $edge = $edges | Where-Object { $_.Label -eq "False" } | Select-Object -First 1
            }
            if ($edge) { return (ConvertTo-CFGNodeArray -CFG $CFG -Value (Get-NodeById -CFG $CFG -Id $edge.To)) }
            return @()
        }

        "ForEachCondition" {
            if ($Context.LastConditionResult) {
                $edge = $edges | Where-Object { $_.Label -eq "Has next" } | Select-Object -First 1
            } else {
                $edge = $edges | Where-Object { $_.Label -eq "No more items" } | Select-Object -First 1
            }
            if ($edge) { return (ConvertTo-CFGNodeArray -CFG $CFG -Value (Get-NodeById -CFG $CFG -Id $edge.To)) }
            return @()
        }
        "ProcessCondition" {
            if ($Context.LastConditionResult) {
                $edge = $edges | Where-Object { $_.Label -eq "Has next" } | Select-Object -First 1
            } else {
                $edge = $edges | Where-Object { $_.Label -eq "No more items" } | Select-Object -First 1
            }
            if ($edge) { return (ConvertTo-CFGNodeArray -CFG $CFG -Value (Get-NodeById -CFG $CFG -Id $edge.To)) }
            return @()
        }

        "SwitchCondition" {
            if ($Context.LastConditionResult) {
                $edge = $edges | Where-Object { $_.Label -eq "True" } | Select-Object -First 1
            } else {
                $edge = $edges | Where-Object { $_.Label -eq "False" } | Select-Object -First 1
            }
            if ($edge) { return (ConvertTo-CFGNodeArray -CFG $CFG -Value (Get-NodeById -CFG $CFG -Id $edge.To)) }
            return @()
        }

        "CaseCondition" {
            if ($Context.LastConditionResult) {
                $edge = $edges | Where-Object { $_.Label -eq "True" } | Select-Object -First 1
            } else {
                $edge = $edges | Where-Object { $_.Label -eq "False" } | Select-Object -First 1
            }
            if ($edge) { return (ConvertTo-CFGNodeArray -CFG $CFG -Value (Get-NodeById -CFG $CFG -Id $edge.To)) }
            return @()
        }

        "Return" {
            $edge = $edges | Where-Object { $_.Label -eq "Return" } | Select-Object -First 1
            if ($edge) { return (ConvertTo-CFGNodeArray -CFG $CFG -Value (Get-NodeById -CFG $CFG -Id $edge.To)) }
            return @()
        }
        "Exit" {
            $edge = $edges | Where-Object { $_.Label -eq "Exit" } | Select-Object -First 1
            if ($edge) { return (ConvertTo-CFGNodeArray -CFG $CFG -Value (Get-NodeById -CFG $CFG -Id $edge.To)) }
            return @()
        }
        "Break" {
            $edge = $edges | Where-Object { $_.Label -eq "Break" } | Select-Object -First 1
            if ($edge) { return (ConvertTo-CFGNodeArray -CFG $CFG -Value (Get-NodeById -CFG $CFG -Id $edge.To)) }
            return @()
        }
        "Continue" {
            $edge = $edges | Where-Object { $_.Label -eq "Continue" } | Select-Object -First 1
            if ($edge) { return (ConvertTo-CFGNodeArray -CFG $CFG -Value (Get-NodeById -CFG $CFG -Id $edge.To)) }
            return @()
        }
        "Throw" {
            return @()
        }

        default {
            $nextNodes = @()
            foreach ($edge in $edges) {
                if ($edge.Label -in @("True", "False", "Has next", "No more items", "Exception", "Uncaught Exception", "Not Match")) {
                    continue
                }
                $nextNode = Get-NodeById -CFG $CFG -Id $edge.To
                if ($nextNode) { $nextNodes += $nextNode }
            }
            return (ConvertTo-CFGNodeArray -CFG $CFG -Value $nextNodes)
        }
    }
}

function Format-ResolvableValue {
    param($Value)

    if ($null -eq $Value) { return '$null' }

    if ($Value -is [BlockedCommandPlaceholder]) {
        return $script:BlockedPlaceholderMarker
    }

    if (Test-ExecutionResultSequenceContainer -Value $Value) {
        $Value = Normalize-ExecutionResultValue -Value $Value
    }

    if ($Value -is [byte[]]) {
        return ConvertTo-Expression -Object $Value -Expand -1 -Strong
    }

    if ($Value -is [array]) {
        if ($Value.Count -gt 0) {
            $isByteSequence = $true
            foreach ($item in $Value) {
                if ($item -isnot [byte]) {
                    $isByteSequence = $false
                    break
                }
            }
            if ($isByteSequence) {
                return '[byte[]](' + (($Value | ForEach-Object { [string][byte]$_ }) -join ',') + ')'
            }
        }
        if ($Value.Count -eq 0) { return '$null' }
        if ($Value.Count -eq 1) {
            if ($Value[0] -is [BlockedCommandPlaceholder]) {
                return $script:BlockedPlaceholderMarker
            }
            return ConvertTo-Expression -Object $Value[0] -Expand -1
        }
        $items = $Value | ForEach-Object {
            if ($_ -is [BlockedCommandPlaceholder]) {
                $script:BlockedPlaceholderMarker
            } else {
                ConvertTo-Expression -Object $_ -Expand -1
            }
        }
        return '@(' + ($items -join ', ') + ')'
    }

    return ConvertTo-Expression -Object $Value -Expand -1
}

function Test-ResolvableValue {
    param($Value)

    if ($null -eq $Value) { return $true }

    if (Test-ExecutionResultSequenceContainer -Value $Value) {
        $Value = Normalize-ExecutionResultValue -Value $Value
    }

    if ($Value -is [array]) {
        if ($Value.Count -eq 0) { return $true }
        foreach ($item in $Value) {
            if (-not (Test-ResolvableValue $item)) { return $false }
        }
        return $true
    }

    if ($Value -is [string])    { return $true }
    if ($Value -is [char])      { return $true }
    if ($Value -is [bool])      { return $true }
    if ($Value -is [byte])      { return $true }
    if ($Value -is [sbyte])     { return $true }
    if ($Value -is [int16])     { return $true }
    if ($Value -is [uint16])    { return $true }
    if ($Value -is [int])       { return $true }
    if ($Value -is [uint32])    { return $true }
    if ($Value -is [int64])     { return $true }
    if ($Value -is [uint64])    { return $true }
    if ($Value -is [float])     { return $true }
    if ($Value -is [double])    { return $true }
    if ($Value -is [decimal])   { return $true }
    if ($Value -is [scriptblock]) { return $true }

    if ($Value -is [BlockedCommandPlaceholder]) { return $true }

    return $false
}

function Evaluate-NodeResolvables {
    param(
        $Node,
        [hashtable]$Context
    )

    $skipEvalTypes = @('Unary')

    $resolved = Get-NodeTextResolvables -Node $Node -Context $Context
    if (-not $resolved.Success) {
        Write-ExecutionLog -Context $Context -Message "  [RESOLVE] Parse Node.Text failed at Node $($Node.Id): $($resolved.Error)"
        return
    }

    foreach ($resolvable in $resolved.Items) {
        if ($resolvable.Type -in $skipEvalTypes) {
            continue
        }

        if ($resolvable.Type -eq 'Command') {
            continue
        }

        if ($resolvable.Ast -and (Test-ResolvableAstHasImplicitSideEffects -Ast $resolvable.Ast)) {
            continue
        }

        if ($resolvable.Ast -and (Test-AstDependsOnBlockedTaint -Ast $resolvable.Ast -Context $Context)) {
            continue
        }

        $code = $resolvable.Text

        $code = Convert-CodeForCurrentScope -Code $code -Context $Context

        $wrappedCode = ",($code)"

        $evalResult = Invoke-InContext -ExecContext $Context.ExecContext -Code $wrappedCode

        if ($evalResult.Success) {
            if (-not (Test-ResolvableValue $evalResult.Result)) {
                continue
            }

            $value = Format-ResolvableValue $evalResult.Result

            if (-not $resolvable.Mapped -or $null -eq $resolvable.StartOffset -or $null -eq $resolvable.EndOffset) {
                continue
            }

            $key = "$($Node.Id):$($resolvable.StartOffset):$($resolvable.EndOffset)"

            if (-not $Context.ResolvableResults.ContainsKey($key)) {
                $Context.ResolvableResults[$key] = @{
                    NodeId     = $Node.Id
                    Resolvable = $resolvable
                    Values     = @()
                }
            }
            $Context.ResolvableResults[$key].Values += $value
        }
    }
}

function Invoke-NodeDirect {
    param(
        $Node,
        [hashtable]$Context,
        [string]$CodeOverride = $null
    )

    $virtualTypes = @(
        'Start', 'End', 'MainStart', 'MainEnd',
        'FuncStart', 'FuncEnd', 'BlockStart', 'BlockEnd',
        'FuncParams', 'BlockParams',
        'LoopStart', 'LoopEnd', 'ProcessEnd', 'SwitchStart', 'SwitchEnd',
        'Break', 'Continue', 'Exit',
        'If Condition', 'Else', 'Merge', 'Default',
        'Try', 'Catch', 'Finally', 'FunctionDef'
    )

    if ($Node.Type -in $virtualTypes) {
        return @{
            Success  = $true
            Executed = $false
            Result   = $null
            Error    = $null
            Action   = "Skip"
        }
    }

    $code = if ($CodeOverride) { $CodeOverride } else { $Node.Text }
    if ([string]::IsNullOrWhiteSpace($code)) {
        return @{
            Success  = $false
            Executed = $true
            Result   = $null
            Error    = "Node.Text is empty"
            Action   = "Execute"
        }
    }

    if ($Context.FunctionSubgraphs.Count -gt 0) {
        $parseInfo = Get-NodeTextParseInfo -Node $Node -Context $Context
        if (-not $parseInfo.Success) {
            return @{
                Success  = $false
                Executed = $true
                Result   = $null
                Error    = "Parse Node.Text failed: $($parseInfo.Error)"
                Action   = "Execute"
            }
        }
        $code = Resolve-EmbeddedFunctionCalls -Code $code -Ast $parseInfo.Ast -Context $Context -NodeId $Node.Id
    }

    $code = Convert-CodeForCurrentScope -Code $code -Context $Context

    $execResult = Invoke-InContext -ExecContext $Context.ExecContext -Code $code

    if ($execResult.Success -and $Node.Type -eq 'PipelineElement') {
        foreach ($varInfo in (Get-CFGNodeVarInfos -Node $Node -PropertyName 'VarsWritten')) {
            if ($varInfo.Name -match '^_pipe_[a-f0-9]+$') {
                $pipeVarName = $varInfo.Name
                $Context.ExecContext.Runspace.SessionStateProxy.SetVariable($pipeVarName, $execResult.Result)
            }
        }
    }

    $conditionTypes = @('Condition', 'ForEachCondition', 'ProcessCondition', 'SwitchCondition', 'CaseCondition')
    if ($Node.Type -in $conditionTypes) {
        $conditionItems = [object[]]@(if ($execResult.Success) {
                Get-ExecutionResultItems -Value $execResult.Result -TreatArraysAsSequence
        } else {
            @()
        })

        if ($conditionItems.Count -gt 0) {
            $Context.LastConditionResult = [bool]$conditionItems[0]
        } else {
            $Context.LastConditionResult = $false
        }
    }

    return @{
        Success  = $execResult.Success
        Executed = $true
        Result   = $execResult.Result
        Error    = $execResult.Error
        Action   = "Execute"
        Timeout  = if ($execResult.PSObject.Properties['Timeout']) { [bool]$execResult.Timeout } else { $false }
        StopReason = if ($execResult.PSObject.Properties['StopReason']) { $execResult.StopReason } else { $null }
    }
}

function Invoke-NodeSafe {
    param(
        $Node,
        [hashtable]$Context
    )

    $virtualTypes = @(
        'Start', 'End', 'MainStart', 'MainEnd',
        'FuncStart', 'FuncEnd', 'BlockStart', 'BlockEnd',
        'FuncParams', 'BlockParams',
        'LoopStart', 'LoopEnd', 'ProcessEnd', 'SwitchStart', 'SwitchEnd',
        'If Condition', 'Else', 'Merge', 'Default',
        'Try', 'Catch', 'Finally', 'FunctionDef'
    )

    if ($Node.Type -in $virtualTypes) {
        return @{
            Success  = $true
            Executed = $false
            Result   = $null
            Error    = $null
            Action   = "Skip"
        }
    }

    if ($Node.Type -eq 'OutputCaptureStart') {
        Push-OutputCapture -Context $Context
        return @{
            Success  = $true
            Executed = $true
            Result   = $null
            Error    = $null
            Action   = 'CaptureStart'
        }
    }

    if ($Node.Type -eq 'OutputCaptureEnd') {
        $frame = Pop-OutputCapture -Context $Context
        $outputs = if ($frame -and $frame.Outputs) { @($frame.Outputs) } else { @() }
        $targetVarName = $null
        if ($Node.PSObject.Properties.Match('CaptureTargetVar').Count -gt 0) {
            $targetVarName = [string]$Node.CaptureTargetVar
        }
        if (-not [string]::IsNullOrWhiteSpace($targetVarName)) {
            $existingValue = Get-VariableFromContext -ExecContext $Context.ExecContext -Name $targetVarName
            $combinedOutputs = @()
            if ($null -ne $existingValue) { $combinedOutputs += @($existingValue) }
            if ($outputs.Count -gt 0) { $combinedOutputs += $outputs }
            $Context.ExecContext.Runspace.SessionStateProxy.SetVariable($targetVarName, $combinedOutputs)
        }
        return @{
            Success  = $true
            Executed = $true
            Result   = $null
            Error    = $null
            Action   = 'CaptureEnd'
        }
    }
    if ($Context.ScriptBlockSubgraphs.Count -gt 0 -and $Node.Ast) {
        $callInfo = Get-ScriptBlockCallInfo -Node $Node -Context $Context
        if ($callInfo -and $callInfo.BlockName -and $Context.ScriptBlockSubgraphs.ContainsKey($callInfo.BlockName)) {
            Write-ExecutionLog -Context $Context -Message "  [CALL] ScriptBlock: $($callInfo.BlockName) (via $($callInfo.CallType) detection)"
            return Invoke-ScriptBlockCall -BlockName $callInfo.BlockName -CallerNode $Node -Context $Context
        }
    }

    if ($Node.Invokes -and $Node.Invokes.ScriptBlocks -and $Node.Invokes.ScriptBlocks.Count -gt 0) {
        $blockName = $Node.Invokes.ScriptBlocks[0]
        if ($Context.ScriptBlockSubgraphs.ContainsKey($blockName)) {
            $isDefinitionNode = $false
            if ($Node.Ast -is [System.Management.Automation.Language.AssignmentStatementAst]) {
                $isDefinitionNode = $true
            }
            $nodeVarsWritten = @(Get-CFGNodeVarInfos -Node $Node -PropertyName 'VarsWritten')
            if ($nodeVarsWritten.Count -gt 0) {
                foreach ($varInfo in $nodeVarsWritten) {
                    if ($varInfo.Name -eq $blockName -or $varInfo.Name -match '^_block_') {
                        $isDefinitionNode = $true
                        break
                    }
                }
            }

            if (-not $isDefinitionNode) {
                $isCallForm = $false

                if ($Node.Ast -is [System.Management.Automation.Language.CommandAst]) {
                    if ($Node.Ast.InvocationOperator -in @(
                            [System.Management.Automation.Language.TokenKind]::Ampersand,
                            [System.Management.Automation.Language.TokenKind]::Dot)) {
                        $isCallForm = $true
                    }

                    $cmdName = $Node.Ast.GetCommandName()
                    if ($cmdName -and $cmdName -ieq $blockName) {
                        $isCallForm = $true
                    }
                }
                elseif ($Node.Text -match '^\s*[&\.]') {
                    $isCallForm = $true
                }

                if ($isCallForm) {
                    Write-ExecutionLog -Context $Context -Message "  [CALL] ScriptBlock: $blockName (via Invokes.ScriptBlocks fallback)"
                    return Invoke-ScriptBlockCall -BlockName $blockName -CallerNode $Node -Context $Context
                }
            }
        }
    }

    if ($Node.Type -eq 'PipelineElement' -and $Node.Invokes -and $Node.Invokes.Functions -and $Node.Invokes.Functions.Count -gt 0) {
        $funcNameFromTopLevel = $null
        $parseInfo = Get-NodeTextParseInfo -Node $Node -Context $Context
        if ($parseInfo.Success) {
            $statement = Get-FirstStatementFromScriptAst -ScriptAst $parseInfo.Ast
            if ($statement -is [System.Management.Automation.Language.PipelineAst]) {
                foreach ($elem in $statement.PipelineElements) {
                    if ($elem -is [System.Management.Automation.Language.CommandAst]) {
                        $name = $elem.GetCommandName()
                        if ($name -and $Context.FunctionSubgraphs.ContainsKey($name)) {
                            $funcNameFromTopLevel = $name
                        }
                    }
                }
            } elseif ($statement -is [System.Management.Automation.Language.CommandAst]) {
                $name = $statement.GetCommandName()
                if ($name -and $Context.FunctionSubgraphs.ContainsKey($name)) {
                    $funcNameFromTopLevel = $name
                }
            }
        }

        if ($funcNameFromTopLevel) {
            Write-ExecutionLog -Context $Context -Message "  [CALL] Function: $funcNameFromTopLevel (pipeline fallback)"
            return Invoke-FunctionCall -FuncName $funcNameFromTopLevel -CallerNode $Node -Context $Context
        }
    }

    if ($Node.DynamicInvoke) {
        $dynInfoList = if ($Node.DynamicInvoke -is [array]) { $Node.DynamicInvoke } else { @($Node.DynamicInvoke) }
        foreach ($dynInfo in $dynInfoList) {
            if ($dynInfo.Type -in @("ScriptBlockCreate", "NewScriptBlock")) {
                Write-ExecutionLog -Context $Context -Message "  [DYNAMIC] Dynamic invoke detected: $($dynInfo.Type)"
                return Handle-DynamicInvoke -Node $Node -Context $Context -DynamicInfo $dynInfo
            }
        }
    }

    $parseInfo = Get-NodeTextParseInfo -Node $Node -Context $Context
    if (-not $parseInfo.Success) {
        return @{
            Success  = $false
            Executed = $true
            Result   = $null
            Error    = "Parse Node.Text failed: $($parseInfo.Error)"
            Action   = "Execute"
        }
    }

    Test-SuspiciousVariables -Node $Node -Context $Context

    $methodCheck = Test-DangerousMethodCall -Node $Node -Context $Context
    if ($methodCheck.IsDangerous) {
        Write-ExecutionLog -Context $Context -Message "  [BLOCKED] Dangerous .NET method: $($methodCheck.Type)::$($methodCheck.Method)"
        Write-ExecutionLog -Context $Context -Message "  [BLOCKED] Full call: $($methodCheck.FullCall)"
        Write-ExecutionLog -Context $Context -Message "  [BLOCKED] Reason: $($methodCheck.Reason)"

        $preservedText = [string]$Node.Text
        $placeholder = New-BlockedPlaceholder -Command "$($methodCheck.Type).$($methodCheck.Method)" -Reason $methodCheck.Reason -PreservedText $preservedText

        $nodeVarsWritten = @(Get-CFGNodeVarInfos -Node $Node -PropertyName 'VarsWritten')
        if ($nodeVarsWritten.Count -gt 0) {
            foreach ($varInfo in $nodeVarsWritten) {
                $actualVarName = Resolve-AssignmentActualVariableName -Context $Context -VariableName ([string]$varInfo.Name)
                $Context.ExecContext.Runspace.SessionStateProxy.SetVariable($actualVarName, $placeholder)
                Set-CFGVariableBlockedTaint -Context $Context -ActualName $actualVarName -Reason $methodCheck.Reason
                Write-ExecutionLog -Context $Context -Message "  [BLOCKED] Set `$$($actualVarName) = [BlockedPlaceholder]"
            }
        }

        return @{
            Success   = $true
            Executed  = $false
            Result    = $placeholder
            Error     = $null
            Action    = "Blocked"
            Command   = "$($methodCheck.Type).$($methodCheck.Method)"
            Reason    = $methodCheck.Reason
        }
    }

    $comCheck = Test-InteractiveComNode -Node $Node
    if ($comCheck.IsDangerous) {
        Write-ExecutionLog -Context $Context -Message "  [BLOCKED] Interactive COM node: $($comCheck.Detail)"
        Write-ExecutionLog -Context $Context -Message "  [BLOCKED] Reason: $($comCheck.Reason)"

        $preservedText = [string]$Node.Text
        $placeholder = New-BlockedPlaceholder -Command $comCheck.Detail -Reason $comCheck.Reason -PreservedText $preservedText

        $nodeVarsWritten = @(Get-CFGNodeVarInfos -Node $Node -PropertyName 'VarsWritten')
        if ($nodeVarsWritten.Count -gt 0) {
            foreach ($varInfo in $nodeVarsWritten) {
                $actualVarName = Resolve-AssignmentActualVariableName -Context $Context -VariableName ([string]$varInfo.Name)
                $Context.ExecContext.Runspace.SessionStateProxy.SetVariable($actualVarName, $placeholder)
                Set-CFGVariableBlockedTaint -Context $Context -ActualName $actualVarName -Reason $comCheck.Reason
                Write-ExecutionLog -Context $Context -Message "  [BLOCKED] Set `$$($actualVarName) = [BlockedPlaceholder]"
            }
        }

        Evaluate-NodeResolvables -Node $Node -Context $Context

        return @{
            Success   = $true
            Executed  = $false
            Result    = $placeholder
            Error     = $null
            Action    = "Blocked"
            Command   = $comCheck.Detail
            Reason    = $comCheck.Reason
        }
    }

    $resolvedValues = Resolve-NonCommandExpressions -Node $Node -Context $Context

    $commandInfo = Get-ResolvedCommandInfo -Node $Node -Context $Context -ResolvedValues $resolvedValues

    $checkResult = Test-CommandSafety -CommandInfo $commandInfo -Context $Context

    if ($commandInfo.HasCommand -and
        $commandInfo.PSObject.Properties['ResolutionKind'] -and
        [string]$commandInfo.ResolutionKind -ne 'Direct' -and
        $commandInfo.PSObject.Properties['ResolutionConfidence'] -and
        [string]$commandInfo.ResolutionConfidence -eq 'High') {
        Record-CommandNameResolution -Node $Node -Context $Context -CommandInfo $commandInfo
    }

    if ($checkResult.IsForbidden) {
        Write-ExecutionLog -Context $Context -Message "  [BLOCKED] Forbidden command: $($commandInfo.ResolvedName) (original: $($commandInfo.OriginalName))"

        $preservedText = Get-BlockedPlaceholderPreservedValueText -Node $Node -Context $Context -ResolvedValues $resolvedValues -CommandInfo $commandInfo

        $placeholder = New-BlockedPlaceholder -Command $commandInfo.ResolvedName -Reason $checkResult.Reason -PreservedText $preservedText

        $nodeVarsWritten = @(Get-CFGNodeVarInfos -Node $Node -PropertyName 'VarsWritten')
        if ($nodeVarsWritten.Count -gt 0) {
            foreach ($varInfo in $nodeVarsWritten) {
                $actualVarName = Resolve-AssignmentActualVariableName -Context $Context -VariableName ([string]$varInfo.Name)
                $Context.ExecContext.Runspace.SessionStateProxy.SetVariable($actualVarName, $placeholder)
                Set-CFGVariableBlockedTaint -Context $Context -ActualName $actualVarName -Reason $checkResult.Reason
                Write-ExecutionLog -Context $Context -Message "  [BLOCKED] Set `$$($actualVarName) = [BlockedPlaceholder]"
            }
        }

        Evaluate-NodeResolvables -Node $Node -Context $Context

        return @{
            Success   = $true
            Executed  = $false
            Result    = $placeholder
            Error     = $null
            Action    = "Blocked"
            Command   = $commandInfo.ResolvedName
            Reason    = $checkResult.Reason
        }
    }

    switch ($checkResult.Action) {
        "Execute" {
            $codeOverride = if ($commandInfo -and $commandInfo.PSObject.Properties['ResolvedNodeText'] -and
                -not [string]::IsNullOrWhiteSpace([string]$commandInfo.ResolvedNodeText)) {
                [string]$commandInfo.ResolvedNodeText
            } else {
                $null
            }
            $result = Invoke-NodeDirect -Node $Node -Context $Context -CodeOverride $codeOverride

            if ($result.Success -or $result.Timeout) {
                Evaluate-NodeResolvables -Node $Node -Context $Context
            }
            if ($result.Success) {
                Record-LiteralizedCommandResult -Node $Node -Context $Context
                Record-SensitiveSinkResult -Node $Node -Context $Context -CommandInfo $commandInfo
            }

            return $result
        }
        "ForEachObject" {
            return Invoke-ForEachObjectCmdlet -Node $Node -Context $Context -CommandInfo $commandInfo
        }
        "WhereObject" {
            return Invoke-WhereObjectCmdlet -Node $Node -Context $Context -CommandInfo $commandInfo
        }
        "SelectObject" {
            return Invoke-SelectObjectCmdlet -Node $Node -Context $Context -CommandInfo $commandInfo
        }
        "CallFunction" {
            Write-ExecutionLog -Context $Context -Message "  [CALL] Function: $($checkResult.Target)"
            return Invoke-FunctionCall -FuncName $checkResult.Target -CallerNode $Node -Context $Context
        }
        "CallScriptBlock" {
            Write-ExecutionLog -Context $Context -Message "  [CALL] ScriptBlock: $($checkResult.Target)"
            return Invoke-ScriptBlockCall -BlockName $checkResult.Target -CallerNode $Node -Context $Context
        }
        "DynamicInvoke" {
            Write-ExecutionLog -Context $Context -Message "  [DYNAMIC] Dynamic invoke detected: $($checkResult.Target)"
            return Handle-DynamicInvoke -Node $Node -Context $Context -CommandInfo $commandInfo -DynamicTypeFromCommand (Get-CFGObjectPropertyValue -Object $checkResult -Name 'DynamicType' -Default $null)
        }
        default {
            $codeOverride = if ($commandInfo -and $commandInfo.PSObject.Properties['ResolvedNodeText'] -and
                -not [string]::IsNullOrWhiteSpace([string]$commandInfo.ResolvedNodeText)) {
                [string]$commandInfo.ResolvedNodeText
            } else {
                $null
            }
            $result = Invoke-NodeDirect -Node $Node -Context $Context -CodeOverride $codeOverride

            if ($result.Success -or $result.Timeout) {
                Evaluate-NodeResolvables -Node $Node -Context $Context
            }
            if ($result.Success) {
                Record-LiteralizedCommandResult -Node $Node -Context $Context
                Record-SensitiveSinkResult -Node $Node -Context $Context -CommandInfo $commandInfo
            }

            return $result
        }
    }
}


function Get-SubgraphEndNode {
    param(
        [hashtable]$CFG,
        [string]$StartType,
        [string]$Name
    )

    $endType = if ($StartType -eq "FuncStart") { "FuncEnd" } else { "BlockEnd" }
    $pattern = if ($StartType -eq "FuncStart") {
        "^End function $([regex]::Escape($Name))$"
    } else {
        "^End (ScriptBlock|DynamicBlock) $([regex]::Escape($Name))$"
    }

    foreach ($node in $CFG.Nodes) {
        if ($node.Type -eq $endType -and $node.Text -match $pattern) {
            return $node
        }
    }

    return $null
}

function Get-CallerPipelineInput {
    param(
        $CallerNode,
        [hashtable]$Context
    )

    $pipeVarNames = @()

    $callerNodeVarsRead = @(Get-CFGNodeVarInfos -Node $CallerNode -PropertyName 'VarsRead')
    if ($CallerNode -and $callerNodeVarsRead.Count -gt 0) {
        foreach ($varInfo in $callerNodeVarsRead) {
            if ($varInfo.Name -match '^_pipe_[a-f0-9]+$' -and $varInfo.Name -notin $pipeVarNames) {
                $pipeVarNames += $varInfo.Name
            }
        }
    }

    $callerNodeVarsWritten = @(Get-CFGNodeVarInfos -Node $CallerNode -PropertyName 'VarsWritten')
    if ($pipeVarNames.Count -eq 0 -and $CallerNode -and $callerNodeVarsWritten.Count -gt 0) {
        foreach ($varInfo in $callerNodeVarsWritten) {
            if ($varInfo.Name -match '^_pipe_[a-f0-9]+$' -and $varInfo.Name -notin $pipeVarNames) {
                $pipeVarNames += $varInfo.Name
            }
        }
    }

    if ($pipeVarNames.Count -eq 0) {
        return @{
            PipeVar = $null
            Items   = @()
        }
    }

    $pipeVar = $pipeVarNames[0]
    $value = Get-VariableFromContext -ExecContext $Context.ExecContext -Name $pipeVar
    $items = if ($null -eq $value) { @() } else { @($value) }

    return @{
        PipeVar = $pipeVar
        Items   = $items
    }
}

function Initialize-ProcessInputForCurrentScope {
    param(
        [hashtable]$Context,
        [array]$InputItems,
        [string]$SourcePipeVar = $null,
        [string]$InputVarName = "__proc_input"
    )

    if ($Context.ScopeStack.Count -eq 0) { return }

    $scope = $Context.ScopeStack[-1]
    if (-not $scope.LocalVars) {
        $scope.LocalVars = @()
    }
    if ($InputVarName -notin $scope.LocalVars) {
        $scope.LocalVars += $InputVarName
    }

    $actualVarName = $scope.ScopePrefix + $InputVarName
    $valueToSet = if ($null -eq $InputItems) { @() } else { @($InputItems) }
    $Context.ExecContext.Runspace.SessionStateProxy.SetVariable($actualVarName, $valueToSet)

    $sourceText = if ($SourcePipeVar) { "`$$SourcePipeVar" } else { "(empty)" }
    Write-ExecutionLog -Context $Context -Message "  [PROCESS] Set `$$actualVarName from $sourceText (Count=$($valueToSet.Count))"
}


function Push-PipelineCurrent {
    param(
        [hashtable]$Context,
        $Value
    )

    if (-not $Context.PipelineCurrentStack) {
        $Context.PipelineCurrentStack = @()
    }

    $frame = @{
        Underscore = Get-VariableFromContext -ExecContext $Context.ExecContext -Name "_"
        PSItem     = Get-VariableFromContext -ExecContext $Context.ExecContext -Name "PSItem"
    }

    $Context.PipelineCurrentStack = @($Context.PipelineCurrentStack) + @($frame)
    $Context.ExecContext.Runspace.SessionStateProxy.SetVariable("_", $Value)
    $Context.ExecContext.Runspace.SessionStateProxy.SetVariable("PSItem", $Value)
}

function Pop-PipelineCurrent {
    param([hashtable]$Context)

    if (-not $Context.PipelineCurrentStack -or $Context.PipelineCurrentStack.Count -eq 0) {
        return
    }

    $frame = $Context.PipelineCurrentStack[-1]
    if ($Context.PipelineCurrentStack.Count -eq 1) {
        $Context.PipelineCurrentStack = @()
    } else {
        $Context.PipelineCurrentStack = @($Context.PipelineCurrentStack[0..($Context.PipelineCurrentStack.Count - 2)])
    }

    $Context.ExecContext.Runspace.SessionStateProxy.SetVariable("_", $frame.Underscore)
    $Context.ExecContext.Runspace.SessionStateProxy.SetVariable("PSItem", $frame.PSItem)
}

function Push-OutputCapture {
    param([hashtable]$Context)
    if (-not $Context.OutputCaptureStack) {
        $Context.OutputCaptureStack = @()
    }
    $Context.OutputCaptureStack = @($Context.OutputCaptureStack) + @(@{ Outputs = @() })
}

function Pop-OutputCapture {
    param([hashtable]$Context)

    if (-not $Context.OutputCaptureStack -or $Context.OutputCaptureStack.Count -eq 0) {
        return @{ Outputs = @() }
    }

    $frame = $Context.OutputCaptureStack[-1]
    if ($Context.OutputCaptureStack.Count -eq 1) {
        $Context.OutputCaptureStack = @()
    } else {
        $Context.OutputCaptureStack = @($Context.OutputCaptureStack[0..($Context.OutputCaptureStack.Count - 2)])
    }

    return $frame
}

function Add-OutputsToCurrentCapture {
    param(
        [hashtable]$Context,
        $Result
    )

    if (-not $Context.OutputCaptureStack -or $Context.OutputCaptureStack.Count -eq 0) {
        return
    }

    if ($null -eq $Result) { return }

    $frame = $Context.OutputCaptureStack[-1]
    if (-not $frame.ContainsKey('Outputs') -or $null -eq $frame.Outputs) {
        $frame.Outputs = @()
    }

    $items = [object[]]@(Get-ExecutionResultItems -Value $Result -TreatArraysAsSequence)
    if ($items.Count -eq 0) {
        return
    }

    foreach ($item in $items) {
        if ($null -ne $item) { $frame.Outputs += $item }
    }
}

function Invoke-PipelineScriptBlockOnce {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BlockName,
        $CurrentValue,
        [array]$ProcessInputItems = @(),
        [hashtable]$Context
    )

    if ([string]::IsNullOrWhiteSpace($BlockName)) { return @() }

    Push-PipelineCurrent -Context $Context -Value $CurrentValue
    Push-OutputCapture -Context $Context

    try {
        $null = Invoke-ScriptBlockInline -BlockName $BlockName -Context $Context -Arguments @() -ProcessInputItems $ProcessInputItems
    }
    finally {
        $cap = Pop-OutputCapture -Context $Context
        Pop-PipelineCurrent -Context $Context
    }

    return @($cap.Outputs)
}

function Apply-AssignmentIfPresentFromValue {
    param(
        $Node,
        [hashtable]$Context,
        $ValueToAssign,
        [string]$TempVarPrefix = "_pipe_cmdlet_out_",
        [string]$ActionNameForErrors = "PipelineCmdlet"
    )

    $nodeExecInfo = Get-NodeTextExecutionInfo -Node $Node -Context $Context
    if (-not $nodeExecInfo.Success) {
        return @{
            Applied = $false
            Success = $true
            Error   = $null
        }
    }

    if (-not ($nodeExecInfo.Statement -is [System.Management.Automation.Language.AssignmentStatementAst])) {
        return @{
            Applied = $false
            Success = $true
            Error   = $null
        }
    }

    $assignAst = $nodeExecInfo.Statement
    $leftText = $assignAst.Left.Extent.Text
    $opText = switch ($assignAst.Operator) {
        "Equals"           { "=" }
        "PlusEquals"       { "+=" }
        "MinusEquals"      { "-=" }
        "MultiplyEquals"   { "*=" }
        "DivideEquals"     { "/=" }
        "RemainderEquals"  { "%=" }
        default            { "=" }
    }

    $tempVar = $TempVarPrefix + [guid]::NewGuid().ToString("N").Substring(0, 8)
    $Context.ExecContext.Runspace.SessionStateProxy.SetVariable($tempVar, $ValueToAssign)

    $assignCode = "$leftText $opText `$$tempVar"
    $assignCode = Convert-CodeForCurrentScope -Code $assignCode -Context $Context
    $assignResult = Invoke-InContext -ExecContext $Context.ExecContext -Code $assignCode

    try { $Context.ExecContext.Runspace.SessionStateProxy.PSVariable.Remove($tempVar) } catch { }

    if (-not $assignResult.Success) {
        return @{
            Applied = $true
            Success = $false
            Error   = "$ActionNameForErrors assignment failed: $($assignResult.Error)"
        }
    }

    return @{
        Applied = $true
        Success = $true
        Error   = $null
    }
}

function Get-SubgraphParamVars {
    param(
        [hashtable]$CFG,
        [int]$StartNodeId,
        [int]$EndNodeId
    )

    if (-not $CFG -or -not $CFG.Nodes -or -not $CFG.Edges) { return @() }

    $paramNames = @()
    $visited = @{}
    $queue = [System.Collections.Generic.Queue[int]]::new()
    $queue.Enqueue($StartNodeId)

    while ($queue.Count -gt 0) {
        $nodeId = $queue.Dequeue()
        if ($visited.ContainsKey($nodeId)) { continue }
        $visited[$nodeId] = $true

        if ($nodeId -eq $EndNodeId) { continue }

        $node = $CFG.Nodes | Where-Object { $_.Id -eq $nodeId } | Select-Object -First 1
        if (-not $node) { continue }

        if ($node.Type -in @('FuncParams', 'BlockParams') -and $node.Ast -and $node.Ast.Parameters) {
            foreach ($p in $node.Ast.Parameters) {
                $name = $p.Name.VariablePath.UserPath
                if (-not [string]::IsNullOrWhiteSpace($name)) {
                    $paramNames += $name
                }
            }
            break
        }

        $edges = $CFG.Edges | Where-Object { $_.From -eq $nodeId }
        foreach ($edge in $edges) {
            if (-not $visited.ContainsKey($edge.To)) {
                $queue.Enqueue($edge.To)
            }
        }
    }

    return @($paramNames | Select-Object -Unique)
}

function Invoke-ScriptBlockInline {
    param(
        [string]$BlockName,
        [hashtable]$Context,
        [array]$Arguments = @(),
        [array]$ProcessInputItems = $null
    )

    if ([string]::IsNullOrWhiteSpace($BlockName)) { return $null }
    if (-not $Context.ScriptBlockSubgraphs.ContainsKey($BlockName)) {
        Write-ExecutionLog -Context $Context -Message "  [FOREACH] ScriptBlock subgraph not found: $BlockName"
        return $null
    }

    $blockStartId = $Context.ScriptBlockSubgraphs[$BlockName]
    $blockStartNode = Get-NodeById -CFG $Context.CFG -Id $blockStartId
    if (-not $blockStartNode) {
        Write-ExecutionLog -Context $Context -Message "  [FOREACH] ScriptBlock start node not found: $BlockName ($blockStartId)"
        return $null
    }

    $blockEndNode = Get-SubgraphEndNode -CFG $Context.CFG -StartType "BlockStart" -Name $BlockName
    if (-not $blockEndNode) {
        Write-ExecutionLog -Context $Context -Message "  [FOREACH] ScriptBlock end node not found: $BlockName"
        return $null
    }
    $blockEndId = $blockEndNode.Id

    $paramVars = Get-SubgraphParamVars -CFG $Context.CFG -StartNodeId $blockStartId -EndNodeId $blockEndId

    Push-ExecutionScope -Context $Context -ScopeType "ScriptBlock" -ScopeName $BlockName -ReturnNodeId 0 -EndNodeId $blockEndId
    $scope = $Context.ScopeStack[-1]
    $scope.LocalVars = $paramVars
    $scope.Arguments = $Arguments
    $scope.TargetVarName = $null

    $hasProcessBlock = ($blockStartNode.PSObject.Properties['HasProcessBlock'] -and [bool]$blockStartNode.HasProcessBlock)
    $processInputVarName = if ($blockStartNode.PSObject.Properties['ProcessInputVar']) {
        [string]$blockStartNode.ProcessInputVar
    } else {
        "__proc_input"
    }
    if ($hasProcessBlock) {
        $itemsToSet = if ($null -eq $ProcessInputItems) { @() } else { @($ProcessInputItems) }
        Initialize-ProcessInputForCurrentScope -Context $Context -InputItems $itemsToSet -SourcePipeVar $null -InputVarName $processInputVarName
    }

    Write-ExecutionLog -Context $Context -Message "  [INLINE] Entering ScriptBlock '$BlockName'"
    Invoke-NodeTraverse -Node $blockStartNode -Context $Context

    $result = $Context.LastSubgraphResult
    $Context.LastSubgraphResult = $null
    Write-ExecutionLog -Context $Context -Message ({ "  [INLINE] Exited ScriptBlock '$BlockName' with result: $(Format-VariableValue $result)" }).GetNewClosure()
    return $result
}

function Get-ForEachObjectInvocationInfo {
    param(
        $Node,
        [hashtable]$Context,
        [string]$NodeTextOverride = $null,
        $CommandInfo = $null
    )

    $execInfo = Get-NodeTextExecutionInfoWithFallback -Node $Node -Context $Context -CandidateSourceTexts @($NodeTextOverride, [string]$Node.Text) -AllowOriginalAstFallback
    if (-not $execInfo.Success) {
        return @{
            Success = $false
            Error   = $execInfo.Error
        }
    }

    $cmdAst = $execInfo.CommandAst
    if (-not $cmdAst) {
        return @{
            Success = $false
            Error   = "No CommandAst in Node.Text"
        }
    }

    $cmdName = $cmdAst.GetCommandName()
    if (-not $cmdName -and $CommandInfo -and $CommandInfo.PSObject.Properties['ResolvedName']) {
        $cmdName = [string]$CommandInfo.ResolvedName
    }
    if ($cmdName -notin @('ForEach-Object', 'ForEach', '%')) {
        return @{
            Success = $false
            Error   = "Not a ForEach-Object command: $cmdName"
        }
    }

    $beginAst = $null
    $processAst = $null
    $endAst = $null
    $positional = @()

    for ($i = 1; $i -lt $cmdAst.CommandElements.Count; $i++) {
        $elem = $cmdAst.CommandElements[$i]

        if ($elem -is [System.Management.Automation.Language.CommandParameterAst]) {
            $pname = $elem.ParameterName
            if ($pname -in @('Begin', 'Process', 'End')) {
                $argAst = $elem.Argument
                if (-not $argAst -and ($i + 1 -lt $cmdAst.CommandElements.Count)) {
                    $i++
                    $argAst = $cmdAst.CommandElements[$i]
                }

                switch ($pname) {
                    'Begin'   { $beginAst = $argAst }
                    'Process' { $processAst = $argAst }
                    'End'     { $endAst = $argAst }
                }
            }
            continue
        }

        $positional += $elem
    }

    if (-not $beginAst -and -not $processAst -and -not $endAst) {
        $blocks = @()
        foreach ($e in $positional) {
            if ($e -is [System.Management.Automation.Language.VariableExpressionAst] -or
                $e -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
                $blocks += $e
            }
        }

        if ($blocks.Count -eq 1) {
            $processAst = $blocks[0]
        } elseif ($blocks.Count -eq 2) {
            $beginAst = $blocks[0]
            $processAst = $blocks[1]
        } elseif ($blocks.Count -ge 3) {
            $beginAst = $blocks[0]
            $processAst = $blocks[1]
            $endAst = $blocks[2]
        }
    }

    $beginName = if ($beginAst) { Get-ScriptBlockNameFromAst -Ast $beginAst -Context $Context } else { $null }
    $processName = if ($processAst) { Get-ScriptBlockNameFromAst -Ast $processAst -Context $Context } else { $null }
    $endName = if ($endAst) { Get-ScriptBlockNameFromAst -Ast $endAst -Context $Context } else { $null }

    if (-not $processName) {
        return @{
            Success = $false
            Error   = "Cannot resolve Process scriptblock for ForEach-Object"
        }
    }

    return @{
        Success          = $true
        Error            = $null
        CommandName      = $cmdName
        BeginBlockName   = $beginName
        ProcessBlockName = $processName
        EndBlockName     = $endName
    }
}

function Convert-AstIntegerLiteralValue {
    param($Ast)

    if ($null -eq $Ast) { return $null }

    if ($Ast -is [System.Management.Automation.Language.CommandExpressionAst]) {
        return Convert-AstIntegerLiteralValue -Ast $Ast.Expression
    }

    if ($Ast -is [System.Management.Automation.Language.ParenExpressionAst]) {
        if ($Ast.Pipeline -and $Ast.Pipeline.PipelineElements -and $Ast.Pipeline.PipelineElements.Count -eq 1) {
            $elem = $Ast.Pipeline.PipelineElements[0]
            if ($elem -is [System.Management.Automation.Language.CommandExpressionAst]) {
                return Convert-AstIntegerLiteralValue -Ast $elem.Expression
            }
            if ($elem.PSObject.Properties['Expression']) {
                return Convert-AstIntegerLiteralValue -Ast $elem.Expression
            }
        }
        return $null
    }

    if ($Ast -is [System.Management.Automation.Language.ConstantExpressionAst]) {
        if ($Ast.Value -is [int]) { return [int]$Ast.Value }
        if ($Ast.Value -is [long]) { return [int]$Ast.Value }
    }

    $text = [string]$Ast.Extent.Text
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    $text = $text.Trim()
    if (($text.StartsWith("'") -and $text.EndsWith("'")) -or ($text.StartsWith('"') -and $text.EndsWith('"'))) {
        if ($text.Length -ge 2) {
            $text = $text.Substring(1, $text.Length - 2)
        }
    }

    $parsed = 0
    if ($text -match '^(?i)0x([0-9a-f]+)$') {
        try { return [Convert]::ToInt32($Matches[1], 16) } catch { return $null }
    }
    if ([int]::TryParse($text, [ref]$parsed)) {
        return $parsed
    }

    return $null
}

function Get-ForEachObjectCommandBlockInfoFromCommandAst {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst
    )

    if ($null -eq $CommandAst) {
        return [PSCustomObject]@{
            Success         = $false
            Error           = 'CommandAst 为空'
            CommandName     = $null
            BeginBlockAst   = $null
            ProcessBlockAst = $null
            EndBlockAst     = $null
        }
    }

    $cmdName = $CommandAst.GetCommandName()
    if ($cmdName -notin @('ForEach-Object', 'ForEach', '%')) {
        return [PSCustomObject]@{
            Success         = $false
            Error           = "Not a ForEach-Object command: $cmdName"
            CommandName     = $cmdName
            BeginBlockAst   = $null
            ProcessBlockAst = $null
            EndBlockAst     = $null
        }
    }

    $beginAst = $null
    $processAst = $null
    $endAst = $null
    $positional = @()

    for ($i = 1; $i -lt $CommandAst.CommandElements.Count; $i++) {
        $elem = $CommandAst.CommandElements[$i]

        if ($elem -is [System.Management.Automation.Language.CommandParameterAst]) {
            $pname = [string]$elem.ParameterName
            if ($pname -in @('Begin', 'Process', 'End', 'b', 'p', 'e')) {
                $argAst = $elem.Argument
                if (-not $argAst -and ($i + 1 -lt $CommandAst.CommandElements.Count)) {
                    $i++
                    $argAst = $CommandAst.CommandElements[$i]
                }

                switch -Regex ($pname) {
                    '^(?i:Begin|b)$'   { $beginAst = $argAst }
                    '^(?i:Process|p)$' { $processAst = $argAst }
                    '^(?i:End|e)$'     { $endAst = $argAst }
                }
            }
            continue
        }

        $positional += $elem
    }

    if (-not $beginAst -and -not $processAst -and -not $endAst) {
        $blocks = @($positional | Where-Object { $_ -is [System.Management.Automation.Language.ScriptBlockExpressionAst] })
        if ($blocks.Count -eq 1) {
            $processAst = $blocks[0]
        } elseif ($blocks.Count -eq 2) {
            $beginAst = $blocks[0]
            $processAst = $blocks[1]
        } elseif ($blocks.Count -ge 3) {
            $beginAst = $blocks[0]
            $processAst = $blocks[1]
            $endAst = $blocks[2]
        }
    }

    foreach ($pair in @(
            @{ Name = 'Begin'; Ast = $beginAst },
            @{ Name = 'Process'; Ast = $processAst },
            @{ Name = 'End'; Ast = $endAst }
        )) {
        if ($null -eq $pair.Ast) { continue }
        if ($pair.Ast -isnot [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
            return [PSCustomObject]@{
                Success         = $false
                Error           = "$($pair.Name) block is not a literal scriptblock"
                CommandName     = $cmdName
                BeginBlockAst   = $beginAst
                ProcessBlockAst = $processAst
                EndBlockAst     = $endAst
            }
        }
    }

    if (-not $processAst) {
        return [PSCustomObject]@{
            Success         = $false
            Error           = 'Process block is missing'
            CommandName     = $cmdName
            BeginBlockAst   = $beginAst
            ProcessBlockAst = $null
            EndBlockAst     = $endAst
        }
    }

    return [PSCustomObject]@{
        Success         = $true
        Error           = $null
        CommandName     = $cmdName
        BeginBlockAst   = $beginAst
        ProcessBlockAst = $processAst
        EndBlockAst     = $endAst
    }
}

function Test-ScriptBlockExpressionAstHasExecutableStatements {
    param($ScriptBlockExpressionAst)

    if ($null -eq $ScriptBlockExpressionAst) { return $false }
    if ($ScriptBlockExpressionAst -isnot [System.Management.Automation.Language.ScriptBlockExpressionAst]) { return $true }

    $sb = $ScriptBlockExpressionAst.ScriptBlock
    if ($null -eq $sb) { return $false }

    foreach ($namedBlock in @($sb.BeginBlock, $sb.ProcessBlock, $sb.EndBlock, $sb.CleanBlock)) {
        if ($namedBlock -and $namedBlock.Statements -and $namedBlock.Statements.Count -gt 0) {
            return $true
        }
    }

    return $false
}

function Get-UnwrappedForEachProcessTransformAst {
    param($Ast)

    $current = $Ast
    $changed = $true
    while ($changed -and $null -ne $current) {
        $changed = $false

        if ($current -is [System.Management.Automation.Language.CommandExpressionAst]) {
            $current = $current.Expression
            $changed = $true
            continue
        }

        if ($current -is [System.Management.Automation.Language.ParenExpressionAst] -and
            $current.Pipeline -and $current.Pipeline.PipelineElements -and $current.Pipeline.PipelineElements.Count -eq 1) {
            $pipeElem = $current.Pipeline.PipelineElements[0]
            if ($pipeElem -is [System.Management.Automation.Language.CommandExpressionAst]) {
                $current = $pipeElem.Expression
                $changed = $true
                continue
            }
            if ($pipeElem.PSObject.Properties['Expression']) {
                $current = $pipeElem.Expression
                $changed = $true
                continue
            }
        }

        if ($current -is [System.Management.Automation.Language.ConvertExpressionAst]) {
            $typeName = if ($current.Type -and $current.Type.TypeName) { [string]$current.Type.TypeName.FullName } else { $null }
            if ($typeName -and $typeName -match '^(?i:int|int32)$') {
                $current = $current.Child
                $changed = $true
                continue
            }
        }
    }

    return $current
}

function Get-ForEachObjectProcessCharTransformInfoFromCommandAst {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst
    )

    $blockInfo = Get-ForEachObjectCommandBlockInfoFromCommandAst -CommandAst $CommandAst
    if (-not $blockInfo.Success -or -not $blockInfo.ProcessBlockAst) {
        return [PSCustomObject]@{
            Success      = $false
            Kind         = $null
            XorKey       = $null
            CommandInfo  = $blockInfo
        }
    }

    $processAst = $blockInfo.ProcessBlockAst
    $convertAst = $processAst.ScriptBlock.Find({
        param($n)
        $n -is [System.Management.Automation.Language.ConvertExpressionAst] -and
        [string]$n.Type.TypeName.FullName -match '^(?i:char)$'
    }, $true)
    if (-not $convertAst) {
        return [PSCustomObject]@{
            Success      = $false
            Kind         = $null
            XorKey       = $null
            CommandInfo  = $blockInfo
        }
    }

    $childAst = Get-UnwrappedForEachProcessTransformAst -Ast $convertAst.Child
    if ($null -eq $childAst) {
        return [PSCustomObject]@{
            Success      = $false
            Kind         = $null
            XorKey       = $null
            CommandInfo  = $blockInfo
        }
    }

    if ($childAst -is [System.Management.Automation.Language.VariableExpressionAst]) {
        $varName = [string]$childAst.VariablePath.UserPath
        if ($varName -in @('_', 'PSItem')) {
            return [PSCustomObject]@{
                Success      = $true
                Kind         = 'CharCast'
                XorKey       = $null
                CommandInfo  = $blockInfo
            }
        }
    }

    if ($childAst -isnot [System.Management.Automation.Language.BinaryExpressionAst] -or
        [string]$childAst.Operator -ne 'Bxor') {
        return [PSCustomObject]@{
            Success      = $false
            Kind         = $null
            XorKey       = $null
            CommandInfo  = $blockInfo
        }
    }

    $varSide = $null
    $constSide = $null
    if ($childAst.Left -is [System.Management.Automation.Language.VariableExpressionAst]) {
        $varSide = $childAst.Left
        $constSide = $childAst.Right
    } elseif ($childAst.Right -is [System.Management.Automation.Language.VariableExpressionAst]) {
        $varSide = $childAst.Right
        $constSide = $childAst.Left
    }
    if (-not $varSide -or -not $constSide) {
        return [PSCustomObject]@{
            Success      = $false
            Kind         = $null
            XorKey       = $null
            CommandInfo  = $blockInfo
        }
    }

    $varName = [string]$varSide.VariablePath.UserPath
    if ($varName -notin @('_', 'PSItem')) {
        return [PSCustomObject]@{
            Success      = $false
            Kind         = $null
            XorKey       = $null
            CommandInfo  = $blockInfo
        }
    }

    $xorKey = Convert-AstIntegerLiteralValue -Ast $constSide
    if ($null -eq $xorKey) {
        return [PSCustomObject]@{
            Success      = $false
            Kind         = $null
            XorKey       = $null
            CommandInfo  = $blockInfo
        }
    }

    return [PSCustomObject]@{
        Success      = $true
        Kind         = 'CharBxor'
        XorKey       = [int]$xorKey
        CommandInfo  = $blockInfo
    }
}

function Get-ForEachObjectProcessCharTransformInfo {
    param(
        $Node,
        [hashtable]$Context,
        [string]$NodeTextOverride = $null,
        $CommandInfo = $null
    )

    $execInfo = Get-NodeTextExecutionInfoWithFallback -Node $Node -Context $Context -CandidateSourceTexts @($NodeTextOverride, [string]$Node.Text) -AllowOriginalAstFallback
    if (-not $execInfo.Success -or -not $execInfo.CommandAst) {
        return [PSCustomObject]@{ Success = $false; Kind = $null; XorKey = $null }
    }

    return Get-ForEachObjectProcessCharTransformInfoFromCommandAst -CommandAst $execInfo.CommandAst
}

function Expand-ForEachNumericStringInputCoreIfNeeded {
    param(
        [array]$Items,
        $TransformInfo
    )

    $normalizedItems = @($Items)
    if ($normalizedItems.Count -ne 1) {
        return [PSCustomObject]@{ Changed = $false; Items = $normalizedItems; Reason = $null }
    }

    if (-not $TransformInfo -or -not $TransformInfo.Success -or $TransformInfo.Kind -notin @('CharBxor', 'CharCast')) {
        return [PSCustomObject]@{ Changed = $false; Items = $normalizedItems; Reason = $null }
    }

    $single = $normalizedItems[0]
    $single = Unwrap-SafePSBaseObject -Value $single
    if ($single -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$single)) {
        return [PSCustomObject]@{ Changed = $false; Items = $normalizedItems; Reason = $null }
    }

    $matches = [regex]::Matches([string]$single, '(?i)0x[0-9a-f]+|\d+')
    if ($matches.Count -lt 2) {
        return [PSCustomObject]@{ Changed = $false; Items = $normalizedItems; Reason = $null }
    }

    $expanded = New-Object System.Collections.Generic.List[object]
    foreach ($match in $matches) {
        $value = $match.Value
        $parsed = if ($value -match '^(?i)0x([0-9a-f]+)$') {
            try { [Convert]::ToInt32($Matches[1], 16) } catch { $null }
        } else {
            $tmp = 0
            if ([int]::TryParse($value, [ref]$tmp)) { $tmp } else { $null }
        }
        if ($null -ne $parsed) {
            [void]$expanded.Add([int]$parsed)
        }
    }

    if ($expanded.Count -lt 2) {
        return [PSCustomObject]@{ Changed = $false; Items = $normalizedItems; Reason = $null }
    }

    return [PSCustomObject]@{
        Changed = $true
        Items   = @($expanded.ToArray())
        Reason  = 'ExplodedNumericStringForCharTransform'
    }
}

function Expand-ForEachNumericStringInputIfNeeded {
    param(
        [array]$Items,
        $Node,
        [hashtable]$Context,
        [string]$NodeTextOverride = $null,
        $CommandInfo = $null
    )

    $normalizedItems = @($Items)
    if ($normalizedItems.Count -ne 1) {
        return [PSCustomObject]@{ Changed = $false; Items = $normalizedItems; Reason = $null }
    }

    $transformInfo = Get-ForEachObjectProcessCharTransformInfo -Node $Node -Context $Context -NodeTextOverride $NodeTextOverride -CommandInfo $CommandInfo
    return Expand-ForEachNumericStringInputCoreIfNeeded -Items $normalizedItems -TransformInfo $transformInfo
}

function Convert-ForEachItemToInt {
    param($Value)

    $Value = Unwrap-SafePSBaseObject -Value $Value

    if ($Value -is [byte] -or $Value -is [sbyte] -or $Value -is [int16] -or $Value -is [uint16] -or
        $Value -is [int] -or $Value -is [uint32] -or $Value -is [long]) {
        return [PSCustomObject]@{ Success = $true; Value = [int]$Value }
    }

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) {
        return [PSCustomObject]@{ Success = $false; Value = $null }
    }
    $text = $text.Trim()

    if ($text -match '^(?i)0x([0-9a-f]+)$') {
        try {
            return [PSCustomObject]@{ Success = $true; Value = [Convert]::ToInt32($Matches[1], 16) }
        } catch {
            return [PSCustomObject]@{ Success = $false; Value = $null }
        }
    }

    $parsed = 0
    if ([int]::TryParse($text, [ref]$parsed)) {
        return [PSCustomObject]@{ Success = $true; Value = $parsed }
    }

    return [PSCustomObject]@{ Success = $false; Value = $null }
}

function Try-Invoke-ForEachCharBxorFastPath {
    param(
        [array]$Items,
        $TransformInfo
    )

    $result = Try-Invoke-ForEachCharTransformFastPath -Items $Items -TransformInfo $TransformInfo
    if (-not $result.Success -or ($TransformInfo -and $TransformInfo.Kind -ne 'CharBxor')) {
        return [PSCustomObject]@{ Success = $false; Outputs = @(); Reason = $null }
    }
    return $result
}

function Convert-ForEachItemToChar {
    param($Value)

    $Value = Unwrap-SafePSBaseObject -Value $Value

    if ($Value -is [char]) {
        return [PSCustomObject]@{ Success = $true; Value = [char]$Value }
    }

    if ($Value -is [byte] -or $Value -is [sbyte] -or $Value -is [int16] -or $Value -is [uint16] -or
        $Value -is [int] -or $Value -is [uint32] -or $Value -is [long]) {
        try {
            return [PSCustomObject]@{ Success = $true; Value = [char][int]$Value }
        } catch {
            return [PSCustomObject]@{ Success = $false; Value = $null }
        }
    }

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) {
        return [PSCustomObject]@{ Success = $false; Outputs = @(); Reason = $null }
    }

    if ($text.Length -eq 1) {
        return [PSCustomObject]@{ Success = $true; Value = [char]$text[0] }
    }

    $intInfo = Convert-ForEachItemToInt -Value $text
    if (-not $intInfo.Success) {
        return [PSCustomObject]@{ Success = $false; Value = $null }
    }

    try {
        return [PSCustomObject]@{ Success = $true; Value = [char][int]$intInfo.Value }
    } catch {
        return [PSCustomObject]@{ Success = $false; Value = $null }
    }
}

function Try-Invoke-ForEachCharTransformFastPath {
    param(
        [array]$Items,
        $TransformInfo
    )

    if (-not $TransformInfo -or -not $TransformInfo.Success -or $TransformInfo.Kind -notin @('CharBxor', 'CharCast')) {
        return [PSCustomObject]@{ Success = $false; Outputs = @(); Reason = $null }
    }

    $outputs = New-Object System.Collections.Generic.List[object]
    foreach ($item in @($Items)) {
        if ($TransformInfo.Kind -eq 'CharBxor') {
            $intInfo = Convert-ForEachItemToInt -Value $item
            if (-not $intInfo.Success) {
                return [PSCustomObject]@{ Success = $false; Outputs = @(); Reason = 'NonNumericInput' }
            }
            try {
                [void]$outputs.Add([char]([int]$intInfo.Value -bxor [int]$TransformInfo.XorKey))
            } catch {
                return [PSCustomObject]@{ Success = $false; Outputs = @(); Reason = 'CharConvertFailed' }
            }
            continue
        }

        $charInfo = Convert-ForEachItemToChar -Value $item
        if (-not $charInfo.Success) {
            return [PSCustomObject]@{ Success = $false; Outputs = @(); Reason = 'NonCharInput' }
        }
        [void]$outputs.Add([char]$charInfo.Value)
    }

    return [PSCustomObject]@{
        Success = $true
        Outputs = @($outputs.ToArray())
        Reason  = if ($TransformInfo.Kind -eq 'CharBxor') { 'CharBxorFastPath' } else { 'CharCastFastPath' }
    }
}

function Invoke-ForEachObjectCmdlet {
    param(
        $Node,
        [hashtable]$Context,
        $CommandInfo = $null
    )

    $nodeTextOverride = if ($CommandInfo -and $CommandInfo.PSObject.Properties['ResolvedNodeText'] -and
        -not [string]::IsNullOrWhiteSpace([string]$CommandInfo.ResolvedNodeText)) {
        [string]$CommandInfo.ResolvedNodeText
    } else {
        $null
    }

    $info = Get-ForEachObjectInvocationInfo -Node $Node -Context $Context -NodeTextOverride $nodeTextOverride -CommandInfo $CommandInfo
    if (-not $info.Success) {
        Write-ExecutionLog -Context $Context -Message "  [FOREACH] Parse failed, fallback to direct execute: $($info.Error)"
        return Invoke-NodeDirect -Node $Node -Context $Context -CodeOverride $nodeTextOverride
    }

    $pipelineInput = Get-CallerPipelineInput -CallerNode $Node -Context $Context
    $items = @($pipelineInput.Items)
    $pipeVar = $pipelineInput.PipeVar
    $expandedInput = Expand-ForEachNumericStringInputIfNeeded -Items $items -Node $Node -Context $Context -NodeTextOverride $nodeTextOverride -CommandInfo $CommandInfo
    if ($expandedInput.Changed) {
        $items = @($expandedInput.Items)
        Write-ExecutionLog -Context $Context -Message "  [FOREACH] Expanded single numeric string input into $($items.Count) items ($($expandedInput.Reason))"
    }
    $transformInfo = Get-ForEachObjectProcessCharTransformInfo -Node $Node -Context $Context -NodeTextOverride $nodeTextOverride -CommandInfo $CommandInfo

    $allOutputs = @()
    $stopAll = $false

    # Begin
    if ($info.BeginBlockName) {
        $Context.LastPipelineFlowControl = $null
        $allOutputs += Invoke-PipelineScriptBlockOnce -BlockName $info.BeginBlockName -CurrentValue $null -ProcessInputItems @() -Context $Context
        if ($Context.LastPipelineFlowControl -eq "Break") {
            $stopAll = $true
        }
    }

    # Process per item
    if (-not $stopAll) {
        $fastPath = $null
        if (-not $info.BeginBlockName -and -not $info.EndBlockName) {
            $fastPath = Try-Invoke-ForEachCharTransformFastPath -Items $items -TransformInfo $transformInfo
        }

        if ($fastPath -and $fastPath.Success) {
            $allOutputs += @($fastPath.Outputs)
            Write-ExecutionLog -Context $Context -Message "  [FOREACH] Applied fast path: $($fastPath.Reason) (Count=$($fastPath.Outputs.Count))"
        } else {
            foreach ($item in $items) {
                $Context.LastPipelineFlowControl = $null
                $allOutputs += Invoke-PipelineScriptBlockOnce -BlockName $info.ProcessBlockName -CurrentValue $item -ProcessInputItems @($item) -Context $Context
                if ($Context.LastPipelineFlowControl -eq "Break") {
                    $stopAll = $true
                    break
                }
            }
        }
    }

    if (-not $stopAll -and $info.EndBlockName) {
        $Context.LastPipelineFlowControl = $null
        $allOutputs += Invoke-PipelineScriptBlockOnce -BlockName $info.EndBlockName -CurrentValue $null -ProcessInputItems @() -Context $Context
    }

    $writesPipeVar = $false
    $nodeVarsWritten = @(Get-CFGNodeVarInfos -Node $Node -PropertyName 'VarsWritten')
    if ($pipeVar -and $nodeVarsWritten.Count -gt 0) {
        foreach ($varInfo in $nodeVarsWritten) {
            if ($varInfo.Name -eq $pipeVar) {
                $writesPipeVar = $true
                break
            }
        }
    }

    $valueToStore = [System.Collections.ObjectModel.Collection[System.Management.Automation.PSObject]]::new()
    foreach ($o in $allOutputs) {
        if ($null -ne $o) {
            [void]$valueToStore.Add([System.Management.Automation.PSObject]$o)
        }
    }

    if ($writesPipeVar) {
        $Context.ExecContext.Runspace.SessionStateProxy.SetVariable($pipeVar, $valueToStore)
        Write-ExecutionLog -Context $Context -Message "  [FOREACH] Set `$$pipeVar (Count=$($valueToStore.Count))"
    }

    $assignApply = Apply-AssignmentIfPresentFromValue -Node $Node -Context $Context -ValueToAssign $valueToStore -TempVarPrefix "_foreach_out_" -ActionNameForErrors "ForEach-Object"
    if ($assignApply.Applied -and -not $assignApply.Success) {
        return @{
            Success  = $false
            Executed = $true
            Result   = $valueToStore
            Error    = $assignApply.Error
            Action   = "ForEachObject"
        }
    }

    return @{
        Success  = $true
        Executed = $true
        Result   = $valueToStore
        Error    = $null
        Action   = "ForEachObject"
    }
}

function Get-WhereObjectInvocationInfo {
    param(
        $Node,
        [hashtable]$Context,
        [string]$NodeTextOverride = $null,
        $CommandInfo = $null
    )

    $execInfo = Get-NodeTextExecutionInfoWithFallback -Node $Node -Context $Context -CandidateSourceTexts @($NodeTextOverride, [string]$Node.Text) -AllowOriginalAstFallback
    if (-not $execInfo.Success) {
        return @{
            Success = $false
            Error   = $execInfo.Error
        }
    }

    $cmdAst = $execInfo.CommandAst
    if (-not $cmdAst) {
        return @{
            Success = $false
            Error   = "No CommandAst in Node.Text"
        }
    }

    $cmdName = $cmdAst.GetCommandName()
    if (-not $cmdName -and $CommandInfo -and $CommandInfo.PSObject.Properties['ResolvedName']) {
        $cmdName = [string]$CommandInfo.ResolvedName
    }
    if ($cmdName -notin @('Where-Object', 'Where', '?')) {
        return @{
            Success = $false
            Error   = "Not a Where-Object command: $cmdName"
        }
    }

    $filterAst = $null
    $positional = @()

    for ($i = 1; $i -lt $cmdAst.CommandElements.Count; $i++) {
        $elem = $cmdAst.CommandElements[$i]

        if ($elem -is [System.Management.Automation.Language.CommandParameterAst]) {
            $pname = $elem.ParameterName
            if ($pname -in @('FilterScript', 'Filter')) {
                $argAst = $elem.Argument
                if (-not $argAst -and ($i + 1 -lt $cmdAst.CommandElements.Count)) {
                    $i++
                    $argAst = $cmdAst.CommandElements[$i]
                }
                $filterAst = $argAst
            }
            continue
        }

        $positional += $elem
    }

    if (-not $filterAst) {
        foreach ($e in $positional) {
            if ($e -is [System.Management.Automation.Language.VariableExpressionAst] -or
                $e -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
                $filterAst = $e
                break
            }
        }
    }

    $knownBlockNames = @()
    if ($Node.Invokes -and $Node.Invokes.ScriptBlocks) {
        $knownBlockNames = @($Node.Invokes.ScriptBlocks)
    }

    $filterName = if ($filterAst) { Get-ScriptBlockNameFromAst -Ast $filterAst -Context $Context -KnownBlockNames $knownBlockNames } else { $null }
    if (-not $filterName) {
        return @{
            Success = $false
            Error   = "Cannot resolve FilterScript scriptblock for Where-Object"
        }
    }

    return @{
        Success         = $true
        Error           = $null
        CommandName     = $cmdName
        FilterBlockName = $filterName
    }
}

function Invoke-WhereObjectCmdlet {
    param(
        $Node,
        [hashtable]$Context,
        $CommandInfo = $null
    )

    $nodeTextOverride = if ($CommandInfo -and $CommandInfo.PSObject.Properties['ResolvedNodeText'] -and
        -not [string]::IsNullOrWhiteSpace([string]$CommandInfo.ResolvedNodeText)) {
        [string]$CommandInfo.ResolvedNodeText
    } else {
        $null
    }

    $info = Get-WhereObjectInvocationInfo -Node $Node -Context $Context -NodeTextOverride $nodeTextOverride -CommandInfo $CommandInfo
    if (-not $info.Success) {
        Write-ExecutionLog -Context $Context -Message "  [WHERE] Parse failed, fallback to direct execute: $($info.Error)"
        return Invoke-NodeDirect -Node $Node -Context $Context -CodeOverride $nodeTextOverride
    }

    $pipelineInput = Get-CallerPipelineInput -CallerNode $Node -Context $Context
    $items = @($pipelineInput.Items)
    $pipeVar = $pipelineInput.PipeVar

    $kept = @()
    $stopAll = $false

    foreach ($item in $items) {
        $Context.LastPipelineFlowControl = $null
        $filterOutputs = Invoke-PipelineScriptBlockOnce -BlockName $info.FilterBlockName -CurrentValue $item -ProcessInputItems @($item) -Context $Context

        $match = [bool]@($filterOutputs)
        if ($match) {
            $kept += $item
        }

        if ($Context.LastPipelineFlowControl -eq "Break") {
            $stopAll = $true
            break
        }
    }

    $valueToStore = [System.Collections.ObjectModel.Collection[System.Management.Automation.PSObject]]::new()
    foreach ($o in $kept) {
        if ($null -ne $o) {
            [void]$valueToStore.Add([System.Management.Automation.PSObject]$o)
        }
    }

    $writesPipeVar = $false
    $nodeVarsWritten = @(Get-CFGNodeVarInfos -Node $Node -PropertyName 'VarsWritten')
    if ($pipeVar -and $nodeVarsWritten.Count -gt 0) {
        foreach ($varInfo in $nodeVarsWritten) {
            if ($varInfo.Name -eq $pipeVar) {
                $writesPipeVar = $true
                break
            }
        }
    }

    if ($writesPipeVar) {
        $Context.ExecContext.Runspace.SessionStateProxy.SetVariable($pipeVar, $valueToStore)
        Write-ExecutionLog -Context $Context -Message "  [WHERE] Set `$$pipeVar (Count=$($valueToStore.Count))"
    }

    $assignApply = Apply-AssignmentIfPresentFromValue -Node $Node -Context $Context -ValueToAssign $valueToStore -TempVarPrefix "_where_out_" -ActionNameForErrors "Where-Object"
    if ($assignApply.Applied -and -not $assignApply.Success) {
        return @{
            Success  = $false
            Executed = $true
            Result   = $valueToStore
            Error    = $assignApply.Error
            Action   = "WhereObject"
        }
    }

    return @{
        Success  = $true
        Executed = $true
        Result   = $valueToStore
        Error    = $null
        Action   = "WhereObject"
    }
}


function Get-HashtableKeyString {
    param($KeyAst)
    if ($null -eq $KeyAst) { return $null }
    if ($KeyAst -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
        return $KeyAst.Value
    }
    return [string]$KeyAst.Extent.Text
}

function Get-HashtableValueExpressionAst {
    param($StatementAst)

    if ($null -eq $StatementAst) { return $null }

    if ($StatementAst -is [System.Management.Automation.Language.PipelineAst] -and
        $StatementAst.PipelineElements -and
        $StatementAst.PipelineElements.Count -eq 1) {
        $pe = $StatementAst.PipelineElements[0]
        if ($pe -is [System.Management.Automation.Language.CommandExpressionAst]) {
            return $pe.Expression
        }
    }

    return $null
}

function Get-SelectObjectCalculatedPropertySpecFromHashtableAst {
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Language.HashtableAst]$HashtableAst,
        [hashtable]$Context,
        [array]$KnownBlockNames = @()
    )

    $name = $null
    $exprAst = $null

    foreach ($kv in $HashtableAst.KeyValuePairs) {
        $keyAst = $kv.Item1
        $valStmt = $kv.Item2

        $keyText = (Get-HashtableKeyString -KeyAst $keyAst)
        if ([string]::IsNullOrWhiteSpace($keyText)) { continue }
        $keyNorm = $keyText.Trim("'`"").ToLowerInvariant()

        $valExpr = Get-HashtableValueExpressionAst -StatementAst $valStmt

        if ($keyNorm -in @('n', 'name', 'label', 'l')) {
            if ($valExpr -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                $name = $valExpr.Value
            } elseif ($null -ne $valExpr) {
                $nameVal = Get-AstValue -Ast $valExpr -Context $Context
                if ($null -ne $nameVal) {
                    $name = [string]$nameVal
                }
            }
        }
        elseif ($keyNorm -in @('e', 'expression')) {
            if ($null -ne $valExpr) {
                $exprAst = $valExpr
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($name) -or $null -eq $exprAst) {
        return $null
    }

    $blockName = Get-ScriptBlockNameFromAst -Ast $exprAst -Context $Context -KnownBlockNames $KnownBlockNames
    if ([string]::IsNullOrWhiteSpace($blockName)) {
        return $null
    }

    return [PSCustomObject]@{
        Type      = "Calculated"
        Name      = $name
        BlockName = $blockName
        Text      = $HashtableAst.Extent.Text
    }
}

function Get-SelectObjectInvocationInfo {
    param(
        $Node,
        [hashtable]$Context,
        [string]$NodeTextOverride = $null,
        $CommandInfo = $null
    )

    $execInfo = Get-NodeTextExecutionInfoWithFallback -Node $Node -Context $Context -CandidateSourceTexts @($NodeTextOverride, [string]$Node.Text) -AllowOriginalAstFallback
    if (-not $execInfo.Success) {
        return @{
            Success = $false
            Error   = $execInfo.Error
        }
    }

    $cmdAst = $execInfo.CommandAst
    if (-not $cmdAst) {
        return @{
            Success = $false
            Error   = "No CommandAst in Node.Text"
        }
    }

    $cmdName = $cmdAst.GetCommandName()
    if (-not $cmdName -and $CommandInfo -and $CommandInfo.PSObject.Properties['ResolvedName']) {
        $cmdName = [string]$CommandInfo.ResolvedName
    }
    if ($cmdName -notin @('Select-Object', 'Select')) {
        return @{
            Success = $false
            Error   = "Not a Select-Object command: $cmdName"
        }
    }

    $propertyArgAsts = @()
    $excludeArgAsts = @()
    $expandArgAst = $null
    $firstAst = $null
    $lastAst = $null
    $skipAst = $null
    $skipLastAst = $null
    $indexAst = $null
    $unique = $false
    $positional = @()

    for ($i = 1; $i -lt $cmdAst.CommandElements.Count; $i++) {
        $elem = $cmdAst.CommandElements[$i]

        if ($elem -is [System.Management.Automation.Language.CommandParameterAst]) {
            $pname = $elem.ParameterName

            if ($pname -in @('Unique')) {
                $unique = $true
                continue
            }

            $argAst = $elem.Argument
            if (-not $argAst -and ($i + 1 -lt $cmdAst.CommandElements.Count)) {
                $i++
                $argAst = $cmdAst.CommandElements[$i]
            }

            switch ($pname) {
                'Property'        { if ($argAst) { $propertyArgAsts += $argAst } }
                'ExcludeProperty' { if ($argAst) { $excludeArgAsts += $argAst } }
                'ExpandProperty'  { if (-not $expandArgAst -and $argAst) { $expandArgAst = $argAst } }
                'First'           { if (-not $firstAst -and $argAst) { $firstAst = $argAst } }
                'Last'            { if (-not $lastAst -and $argAst) { $lastAst = $argAst } }
                'Skip'            { if (-not $skipAst -and $argAst) { $skipAst = $argAst } }
                'SkipLast'        { if (-not $skipLastAst -and $argAst) { $skipLastAst = $argAst } }
                'Index'           { if (-not $indexAst -and $argAst) { $indexAst = $argAst } }
                default { }
            }

            continue
        }

        $positional += $elem
    }

    if ($propertyArgAsts.Count -eq 0 -and $positional.Count -gt 0) {
        $propertyArgAsts = @($positional)
    }

    $knownBlockNames = @()
    if ($Node.Invokes -and $Node.Invokes.ScriptBlocks) {
        $knownBlockNames = @($Node.Invokes.ScriptBlocks)
    }

    function Add-PropertySpecAstsFromArg {
        param([ref]$List, $ArgAst)
        if ($null -eq $ArgAst) { return }

        if ($ArgAst -is [System.Management.Automation.Language.ArrayLiteralAst]) {
            foreach ($e in $ArgAst.Elements) {
                $List.Value += $e
            }
        } else {
            $List.Value += $ArgAst
        }
    }

    function Add-StringValuesFromArg {
        param([ref]$List, $ArgAst)
        if ($null -eq $ArgAst) { return }

        $work = @()
        if ($ArgAst -is [System.Management.Automation.Language.ArrayLiteralAst]) {
            $work = @($ArgAst.Elements)
        } else {
            $work = @($ArgAst)
        }

        foreach ($a in $work) {
            if ($a -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                $List.Value += $a.Value
            } else {
                $v = Get-AstValue -Ast $a -Context $Context
                if ($null -eq $v) { continue }
                if ($v -is [array]) {
                    foreach ($vv in $v) {
                        if ($null -ne $vv) { $List.Value += [string]$vv }
                    }
                } else {
                    $List.Value += [string]$v
                }
            }
        }
    }

    $propertySpecAsts = @()
    foreach ($a in $propertyArgAsts) {
        Add-PropertySpecAstsFromArg -List ([ref]$propertySpecAsts) -ArgAst $a
    }

    $propertySpecs = @()
    foreach ($specAst in $propertySpecAsts) {
        if ($specAst -is [System.Management.Automation.Language.HashtableAst]) {
            $calc = Get-SelectObjectCalculatedPropertySpecFromHashtableAst -HashtableAst $specAst -Context $Context -KnownBlockNames $knownBlockNames
            if (-not $calc) {
                return @{
                    Success = $false
                    Error   = "Unsupported calculated property: $($specAst.Extent.Text)"
                }
            }
            $propertySpecs += $calc
            continue
        }

        if ($specAst -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
            $propertySpecs += [PSCustomObject]@{
                Type    = "Name"
                Pattern = $specAst.Value
                Text    = $specAst.Extent.Text
            }
            continue
        }

        $v = Get-AstValue -Ast $specAst -Context $Context
        if ($null -eq $v) {
            return @{
                Success = $false
                Error   = "Cannot evaluate property spec: $($specAst.Extent.Text)"
            }
        }

        if ($v -is [array]) {
            foreach ($vv in $v) {
                if ($null -ne $vv) {
                    $propertySpecs += [PSCustomObject]@{
                        Type    = "Name"
                        Pattern = [string]$vv
                        Text    = $specAst.Extent.Text
                    }
                }
            }
        } else {
            $propertySpecs += [PSCustomObject]@{
                Type    = "Name"
                Pattern = [string]$v
                Text    = $specAst.Extent.Text
            }
        }
    }

    # ExcludeProperty
    $excludePatterns = @()
    foreach ($a in $excludeArgAsts) {
        Add-StringValuesFromArg -List ([ref]$excludePatterns) -ArgAst $a
    }

    # ExpandProperty
    $expandPropName = $null
    if ($expandArgAst) {
        if ($expandArgAst -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
            $expandPropName = $expandArgAst.Value
        } else {
            $v = Get-AstValue -Ast $expandArgAst -Context $Context
            if ($null -ne $v) { $expandPropName = [string]$v }
        }
    }

    function Get-IntArgOrNull {
        param($Ast)
        if ($null -eq $Ast) { return $null }
        $v = Get-AstValue -Ast $Ast -Context $Context
        if ($null -eq $v) { return $null }
        try { return [int]$v } catch { return $null }
    }

    function Get-IntListOrNull {
        param($Ast)
        if ($null -eq $Ast) { return $null }

        $list = @()
        if ($Ast -is [System.Management.Automation.Language.ArrayLiteralAst]) {
            foreach ($e in $Ast.Elements) {
                $iv = Get-IntArgOrNull -Ast $e
                if ($null -ne $iv) { $list += $iv }
            }
        } else {
            $iv = Get-IntArgOrNull -Ast $Ast
            if ($null -ne $iv) { $list += $iv }
        }

        if ($list.Count -eq 0) { return $null }
        return $list
    }

    $first = Get-IntArgOrNull -Ast $firstAst
    $last = Get-IntArgOrNull -Ast $lastAst
    $skip = Get-IntArgOrNull -Ast $skipAst
    $skipLast = Get-IntArgOrNull -Ast $skipLastAst
    $indexList = Get-IntListOrNull -Ast $indexAst

    return @{
        Success         = $true
        Error           = $null
        CommandName     = $cmdName
        PropertySpecs   = @($propertySpecs)
        ExcludePatterns = @($excludePatterns)
        ExpandProperty  = $expandPropName
        First           = $first
        Last            = $last
        Skip            = $skip
        SkipLast        = $skipLast
        Index           = $indexList
        Unique          = [bool]$unique
    }
}

function Invoke-SelectObjectCmdlet {
    param(
        $Node,
        [hashtable]$Context,
        $CommandInfo = $null
    )

    $nodeTextOverride = if ($CommandInfo -and $CommandInfo.PSObject.Properties['ResolvedNodeText'] -and
        -not [string]::IsNullOrWhiteSpace([string]$CommandInfo.ResolvedNodeText)) {
        [string]$CommandInfo.ResolvedNodeText
    } else {
        $null
    }

    $info = Get-SelectObjectInvocationInfo -Node $Node -Context $Context -NodeTextOverride $nodeTextOverride -CommandInfo $CommandInfo
    if (-not $info.Success) {
        Write-ExecutionLog -Context $Context -Message "  [SELECT] Parse failed, fallback to direct execute: $($info.Error)"
        return Invoke-NodeDirect -Node $Node -Context $Context -CodeOverride $nodeTextOverride
    }

    $pipelineInput = Get-CallerPipelineInput -CallerNode $Node -Context $Context
    $items = @($pipelineInput.Items)
    $pipeVar = $pipelineInput.PipeVar

    $baseItems = @($items)

    if ($null -ne $info.SkipLast) {
        if ($info.SkipLast -lt 0) {
            return @{
                Success  = $false
                Executed = $true
                Result   = $null
                Error    = "Select-Object: SkipLast must be non-negative"
                Action   = "SelectObject"
            }
        }

        if ($info.SkipLast -ge $baseItems.Count) {
            $baseItems = @()
        } else {
            $baseItems = @($baseItems[0..($baseItems.Count - $info.SkipLast - 1)])
        }
    }

    $count = $baseItems.Count
    $indices = @()

    $skip = if ($null -ne $info.Skip) { [int]$info.Skip } else { 0 }
    $first = $info.First
    $last = $info.Last

    if ($skip -lt 0) {
        return @{
            Success  = $false
            Executed = $true
            Result   = $null
            Error    = "Select-Object: Skip must be non-negative"
            Action   = "SelectObject"
        }
    }
    if ($null -ne $first -and $first -lt 0) {
        return @{
            Success  = $false
            Executed = $true
            Result   = $null
            Error    = "Select-Object: First must be non-negative"
            Action   = "SelectObject"
        }
    }
    if ($null -ne $last -and $last -lt 0) {
        return @{
            Success  = $false
            Executed = $true
            Result   = $null
            Error    = "Select-Object: Last must be non-negative"
            Action   = "SelectObject"
        }
    }

    if ($info.Index -and $info.Index.Count -gt 0) {
        foreach ($idx in $info.Index) {
            if ($idx -lt 0) {
                return @{
                    Success  = $false
                    Executed = $true
                    Result   = $null
                    Error    = "Select-Object: Index must be non-negative"
                    Action   = "SelectObject"
                }
            }
            if ($idx -lt $count) {
                $indices += $idx
            }
        }
    }
    else {
        if ($null -ne $first -and $null -ne $last) {
            $start = [Math]::Min($skip, $count)
            $endFirst = [Math]::Min($count, ($start + $first))
            for ($i = $start; $i -lt $endFirst; $i++) { $indices += $i }

            $startLast = [Math]::Max(0, ($count - $last))
            for ($i = $startLast; $i -lt $count; $i++) { $indices += $i }

            $indices = @($indices | Sort-Object -Unique)
        }
        elseif ($null -ne $first) {
            $start = [Math]::Min($skip, $count)
            $endFirst = [Math]::Min($count, ($start + $first))
            for ($i = $start; $i -lt $endFirst; $i++) { $indices += $i }
        }
        elseif ($null -ne $last) {
            $skipFromEnd = $skip
            $endExclusive = [Math]::Max(0, ($count - $skipFromEnd))
            $start = [Math]::Max(0, ($endExclusive - $last))
            for ($i = $start; $i -lt $endExclusive; $i++) { $indices += $i }
        }
        else {
            $start = [Math]::Min($skip, $count)
            for ($i = $start; $i -lt $count; $i++) { $indices += $i }
        }
    }

    $selectedItems = @()
    foreach ($i in $indices) {
        if ($i -ge 0 -and $i -lt $count) {
            $selectedItems += $baseItems[$i]
        }
    }

    function Test-NameMatchesAnyPattern {
        param(
            [string]$Name,
            [string[]]$Patterns
        )
        if ([string]::IsNullOrWhiteSpace($Name) -or -not $Patterns -or $Patterns.Count -eq 0) { return $false }
        foreach ($p in $Patterns) {
            if ([string]::IsNullOrWhiteSpace($p)) { continue }
            if ($Name -like $p) { return $true }
        }
        return $false
    }

    $outputs = @()
    $stopAll = $false

    # 2) ExpandProperty
    if (-not [string]::IsNullOrWhiteSpace($info.ExpandProperty)) {
        $propName = [string]$info.ExpandProperty

        foreach ($item in $selectedItems) {
            if ($null -eq $item) { continue }

            $prop = $item.PSObject.Properties[$propName]
            $v = if ($prop) { $prop.Value } else { $null }
            if ($null -eq $v) { continue }

            if ($v -is [string]) {
                $outputs += $v
                continue
            }

            if ($v -is [System.Collections.IEnumerable]) {
                foreach ($e in $v) {
                    if ($null -ne $e) { $outputs += $e }
                }
                continue
            }

            $outputs += $v
        }
    }
    elseif ($info.PropertySpecs -and $info.PropertySpecs.Count -gt 0) {
        foreach ($item in $selectedItems) {
            if ($null -eq $item) { continue }

            $outObj = New-Object PSObject

            foreach ($spec in $info.PropertySpecs) {
                if ($spec.Type -eq "Name") {
                    $pattern = [string]$spec.Pattern
                    if ([string]::IsNullOrWhiteSpace($pattern)) { continue }

                    $propNames = @($item.PSObject.Properties.Name)
                    $matched = @($propNames | Where-Object { $_ -like $pattern })

                    if ($matched.Count -gt 0) {
                        foreach ($pn in $matched) {
                            if (Test-NameMatchesAnyPattern -Name $pn -Patterns $info.ExcludePatterns) {
                                continue
                            }
                            $p = $item.PSObject.Properties[$pn]
                            $val = if ($p) { $p.Value } else { $null }
                            $outObj | Add-Member -NotePropertyName $pn -NotePropertyValue $val -Force
                        }
                    } else {
                        if (-not (Test-NameMatchesAnyPattern -Name $pattern -Patterns $info.ExcludePatterns)) {
                            $outObj | Add-Member -NotePropertyName $pattern -NotePropertyValue $null -Force
                        }
                    }
                }
                elseif ($spec.Type -eq "Calculated") {
                    $propName = [string]$spec.Name
                    $blockName = [string]$spec.BlockName

                    $Context.LastPipelineFlowControl = $null
                    $exprOutputs = Invoke-PipelineScriptBlockOnce -BlockName $blockName -CurrentValue $item -ProcessInputItems @($item) -Context $Context

                    $value = $null
                    if ($exprOutputs.Count -eq 1) {
                        $value = $exprOutputs[0]
                    } elseif ($exprOutputs.Count -gt 1) {
                        $value = @($exprOutputs)
                    }

                    if (-not (Test-NameMatchesAnyPattern -Name $propName -Patterns $info.ExcludePatterns)) {
                        $outObj | Add-Member -NotePropertyName $propName -NotePropertyValue $value -Force
                    }

                    if ($Context.LastPipelineFlowControl -eq "Break") {
                        $stopAll = $true
                        break
                    }
                }
            }

            $outputs += $outObj

            if ($stopAll) { break }
        }
    }
    else {
        $outputs = @($selectedItems)
    }

    if ($info.Unique) {
        $outputs = @($outputs | Select-Object -Unique)
    }

    $valueToStore = [System.Collections.ObjectModel.Collection[System.Management.Automation.PSObject]]::new()
    foreach ($o in $outputs) {
        if ($null -ne $o) {
            [void]$valueToStore.Add([System.Management.Automation.PSObject]$o)
        }
    }

    $writesPipeVar = $false
    $nodeVarsWritten = @(Get-CFGNodeVarInfos -Node $Node -PropertyName 'VarsWritten')
    if ($pipeVar -and $nodeVarsWritten.Count -gt 0) {
        foreach ($varInfo in $nodeVarsWritten) {
            if ($varInfo.Name -eq $pipeVar) {
                $writesPipeVar = $true
                break
            }
        }
    }

    if ($writesPipeVar) {
        $Context.ExecContext.Runspace.SessionStateProxy.SetVariable($pipeVar, $valueToStore)
        Write-ExecutionLog -Context $Context -Message "  [SELECT] Set `$$pipeVar (Count=$($valueToStore.Count))"
    }

    $assignApply = Apply-AssignmentIfPresentFromValue -Node $Node -Context $Context -ValueToAssign $valueToStore -TempVarPrefix "_select_out_" -ActionNameForErrors "Select-Object"
    if ($assignApply.Applied -and -not $assignApply.Success) {
        return @{
            Success  = $false
            Executed = $true
            Result   = $valueToStore
            Error    = $assignApply.Error
            Action   = "SelectObject"
        }
    }

    return @{
        Success  = $true
        Executed = $true
        Result   = $valueToStore
        Error    = $null
        Action   = "SelectObject"
    }
}

function Invoke-FunctionCall {
    param(
        [string]$FuncName,
        $CallerNode,
        [hashtable]$Context
    )

    if ([string]::IsNullOrWhiteSpace($FuncName)) {
        Write-ExecutionLog -Context $Context -Message "  [ERROR] Function name is null or empty"
        return @{
            Success  = $false
            Executed = $true
            Error    = "Function name is null or empty"
            Action   = "CallFunction"
            Target   = $FuncName
        }
    }

    if ($Context.CallStack.Count -ge $Context.MaxCallDepth) {
        Write-ExecutionLog -Context $Context -Message "  [ERROR] Max call depth ($($Context.MaxCallDepth)) exceeded"
        return @{
            Success  = $false
            Executed = $true
            Error    = "Max call depth exceeded"
            Action   = "CallFunction"
            Target   = $FuncName
        }
    }

    $funcStartId = $Context.FunctionSubgraphs[$FuncName]
    if (-not $funcStartId) {
        Write-ExecutionLog -Context $Context -Message "  [ERROR] Function not found: $FuncName"
        return @{
            Success  = $false
            Executed = $true
            Error    = "Function not found: $FuncName"
            Action   = "CallFunction"
            Target   = $FuncName
        }
    }

    $funcEndNode = Get-SubgraphEndNode -CFG $Context.CFG -StartType "FuncStart" -Name $FuncName
    if (-not $funcEndNode) {
        Write-ExecutionLog -Context $Context -Message "  [WARN] Function end node not found for: $FuncName"
    }
    $funcEndId = if ($funcEndNode) { $funcEndNode.Id } else { $null }

    $localVars = @()
    if ($funcEndId) {
        $localVars = Get-SubgraphLocalVars -CFG $Context.CFG -StartNodeId $funcStartId -EndNodeId $funcEndId
    }

    $nextNodes = @(Get-NextNodes -CFG $Context.CFG -Node $CallerNode -Context $Context)
    $returnNode = if ($nextNodes.Count -gt 0) { Resolve-CFGNodeValue -CFG $Context.CFG -Value $nextNodes[0] } else { $null }
    $returnNodeId = if ($returnNode) { $returnNode.Id } else { $null }

    $arguments = @()
    $namedArguments = [ordered]@{}
    $callerInfo = Get-NodeTextExecutionInfo -Node $CallerNode -Context $Context
    if (-not $callerInfo.Success) {
        return @{
            Success  = $false
            Executed = $true
            Error    = "Parse caller Node.Text failed: $($callerInfo.Error)"
            Action   = "CallFunction"
            Target   = $FuncName
        }
    }
    $funcStartNode = Get-NodeById -CFG $Context.CFG -Id $funcStartId
    if (-not $funcStartNode) {
        Write-ExecutionLog -Context $Context -Message "  [ERROR] Function start node not found: $FuncName ($funcStartId)"
        return @{
            Success  = $false
            Executed = $true
            Error    = "Function start node not found: $FuncName ($funcStartId)"
            Action   = "CallFunction"
            Target   = $FuncName
        }
    }
    $hasProcessBlock = ($funcStartNode.PSObject.Properties['HasProcessBlock'] -and [bool]$funcStartNode.HasProcessBlock)
    $processInputVarName = if ($funcStartNode.PSObject.Properties['ProcessInputVar']) {
        [string]$funcStartNode.ProcessInputVar
    } else {
        "__proc_input"
    }

    $cmdAst = if ($callerInfo.TopLevelCommandAst) { $callerInfo.TopLevelCommandAst } else { $callerInfo.CommandAst }
    if ($cmdAst -and $cmdAst.CommandElements -and $cmdAst.CommandElements.Count -gt 1) {
        $bindingInfo = Get-CommandInvocationBindings -CommandAst $cmdAst -Context $Context -StartIndex 1 -CallerNodeId $CallerNode.Id
        $arguments = @($bindingInfo.PositionalArguments)
        $namedArguments = $bindingInfo.NamedArguments

        if (Test-ExecutionLogDetailEnabled -Context $Context -FlagName 'LogArgumentDetailsEnabled') {
            $posIndex = 0
            foreach ($entry in @($bindingInfo.LogEntries)) {
                if ([string]$entry.Kind -eq 'Named') {
                    if ($entry.Success) {
                        Write-ExecutionLog -Context $Context -Message ({ "  [ARGS] Named -$($entry.Name) = $(Format-VariableValue $entry.Value)" }).GetNewClosure()
                    } else {
                        Write-ExecutionLog -Context $Context -Message "  [ARGS] Named -$($entry.Name) = (eval failed)"
                    }
                } else {
                    if ($entry.Success) {
                        Write-ExecutionLog -Context $Context -Message ({ "  [ARGS] Arg[$posIndex]: $($entry.Display) = $(Format-VariableValue $entry.Value)" }).GetNewClosure()
                    } else {
                        Write-ExecutionLog -Context $Context -Message "  [ARGS] Arg[$posIndex]: $($entry.Display) = (eval failed)"
                    }
                    $posIndex++
                }
            }
        }
    }

    $targetVarName = if ($callerInfo -and $callerInfo.Success) { $callerInfo.TargetVarName } else { $null }

    Push-ExecutionScope -Context $Context -ScopeType "Function" -ScopeName $FuncName -ReturnNodeId $returnNodeId -EndNodeId $funcEndId
    if ($Context.ScopeStack.Count -gt 0) {
        $Context.ScopeStack[-1].LocalVars = $localVars
        $Context.ScopeStack[-1].Arguments = $arguments
        $Context.ScopeStack[-1].NamedArguments = $namedArguments
        $Context.ScopeStack[-1].TargetVarName = $targetVarName
        $Context.ScopeStack[-1].CallerNodeId = $CallerNode.Id
        $cmdExtent = Get-NodeAstGlobalExtent -Node $CallerNode -Ast $cmdAst
        if ($cmdExtent) {
            $Context.ScopeStack[-1].InvocationStartOffset = [int]$cmdExtent.StartOffset
            $Context.ScopeStack[-1].InvocationEndOffset = [int]$cmdExtent.EndOffset
            $Context.ScopeStack[-1].InvocationText = [string]$cmdExtent.Text
        }

        if ($hasProcessBlock) {
            $pipelineInput = Get-CallerPipelineInput -CallerNode $CallerNode -Context $Context
            Initialize-ProcessInputForCurrentScope -Context $Context -InputItems $pipelineInput.Items -SourcePipeVar $pipelineInput.PipeVar -InputVarName $processInputVarName
        }
    }


    Write-ExecutionLog -Context $Context -Message "  [FUNC] Entering function '$FuncName' at Node $funcStartId"

    return @{
        Success       = $true
        Executed      = $false
        Action        = "CallFunction"
        Target        = $FuncName
        JumpToNode    = $funcStartNode
        LocalVars     = $localVars
        Arguments     = $arguments
    }
}

function Invoke-FunctionInline {
    param(
        [string]$FuncName,
        [array]$Arguments,
        [hashtable]$NamedArguments = $null,
        [hashtable]$Context
    )

    if ($Context.CallStack.Count -ge $Context.MaxCallDepth) {
        Write-ExecutionLog -Context $Context -Message "  [INLINE] Max call depth exceeded for '$FuncName'"
        return $null
    }

    $funcStartId = $Context.FunctionSubgraphs[$FuncName]
    if (-not $funcStartId) {
        Write-ExecutionLog -Context $Context -Message "  [INLINE] Function not found: $FuncName"
        return $null
    }
    $funcStartNode = Get-NodeById -CFG $Context.CFG -Id $funcStartId
    if (-not $funcStartNode) {
        Write-ExecutionLog -Context $Context -Message "  [INLINE] Function start node not found: $FuncName ($funcStartId)"
        return $null
    }
    $hasProcessBlock = ($funcStartNode.PSObject.Properties['HasProcessBlock'] -and [bool]$funcStartNode.HasProcessBlock)
    $processInputVarName = if ($funcStartNode.PSObject.Properties['ProcessInputVar']) {
        [string]$funcStartNode.ProcessInputVar
    } else {
        "__proc_input"
    }

    $funcEndNode = Get-SubgraphEndNode -CFG $Context.CFG -StartType "FuncStart" -Name $FuncName
    $funcEndId = if ($funcEndNode) { $funcEndNode.Id } else { $null }

    $localVars = @()
    if ($funcEndId) {
        $localVars = Get-SubgraphLocalVars -CFG $Context.CFG -StartNodeId $funcStartId -EndNodeId $funcEndId
    }

    $preferDirectFallback = Test-FunctionInlinePreferDirectFallback -FuncName $FuncName -Context $Context
    if ($preferDirectFallback) {
        $directResult = Invoke-FunctionInlineDirectFallback -FuncName $FuncName -Arguments $Arguments -NamedArguments $NamedArguments -Context $Context
        if ($null -ne $directResult) {
            Write-ExecutionLog -Context $Context -Message "  [INLINE] Using direct helper fallback for complex function '$FuncName'"
            return $directResult
        }
        Write-ExecutionLog -Context $Context -Message "  [INLINE] Direct helper fallback returned null for '$FuncName'; falling back to CFG traversal"
    }

    $baselineScopeDepth = $Context.ScopeStack.Count

    Push-ExecutionScope -Context $Context -ScopeType "Function" -ScopeName $FuncName `
        -ReturnNodeId 0 -EndNodeId $funcEndId
    $scope = $Context.ScopeStack[-1]
    $scope.LocalVars = $localVars
    $scope.Arguments = $Arguments
    $scope.NamedArguments = if ($NamedArguments) { $NamedArguments } else { @{} }
    $scope.TargetVarName = $null
    if ($hasProcessBlock) {
        Initialize-ProcessInputForCurrentScope -Context $Context -InputItems @() -SourcePipeVar $null -InputVarName $processInputVarName
    }

    Write-ExecutionLog -Context $Context -Message "  [INLINE] Entering function '$FuncName'"
    Invoke-NodeTraverse -Node $funcStartNode -Context $Context

    $scopeLeakDetected = ($Context.ScopeStack.Count -gt $baselineScopeDepth)
    if ($scopeLeakDetected) {
        Write-ExecutionLog -Context $Context -Message "  [INLINE] Scope leak detected after CFG inline traversal; unwinding leaked scopes and using direct helper fallback"
        while ($Context.ScopeStack.Count -gt $baselineScopeDepth) {
            $null = Pop-ExecutionScope -Context $Context
        }
    }

    $result = $Context.LastSubgraphResult
    $Context.LastSubgraphResult = $null

    if ($scopeLeakDetected) {
        $fallbackResult = Invoke-FunctionInlineDirectFallback -FuncName $FuncName -Arguments $Arguments -NamedArguments $NamedArguments -Context $Context
        if ($null -ne $fallbackResult) {
            $result = $fallbackResult
        }
    }

    Write-ExecutionLog -Context $Context -Message ({ "  [INLINE] Exited function '$FuncName' with result: $(Format-VariableValue $result)" }).GetNewClosure()
    return $result
}

function Invoke-FunctionInlineDirectFallback {
    param(
        [string]$FuncName,
        [array]$Arguments,
        [hashtable]$NamedArguments,
        [hashtable]$Context
    )

    if (-not $Context -or -not $Context.CFG -or -not $Context.CFG.ContainsKey('FunctionTexts')) {
        return $null
    }

    $functionTexts = $Context.CFG.FunctionTexts
    if (-not $functionTexts -or -not $functionTexts.ContainsKey($FuncName)) {
        return $null
    }

    $functionDefinitions = @($functionTexts.GetEnumerator() | Sort-Object Name | ForEach-Object { [string]$_.Value })
    if ($functionDefinitions.Count -eq 0) {
        return $null
    }

    $guidSuffix = [guid]::NewGuid().ToString('N').Substring(0, 8)
    $argVarName = "__inline_args_$guidSuffix"
    $namedVarName = "__inline_named_$guidSuffix"

    $Context.ExecContext.Runspace.SessionStateProxy.SetVariable($argVarName, @($Arguments))
    $Context.ExecContext.Runspace.SessionStateProxy.SetVariable($namedVarName, $(if ($NamedArguments) { $NamedArguments } else { @{} }))

    try {
        $wrapperCode = @"
& {
$(($functionDefinitions -join "`r`n`r`n"))
& $FuncName @$namedVarName @$argVarName
}
"@
        $evalResult = Invoke-InContext -ExecContext $Context.ExecContext -Code $wrapperCode
        if (-not $evalResult.Success) {
            Write-ExecutionLog -Context $Context -Message "  [INLINE-FALLBACK] Direct helper execution failed for '$FuncName': $($evalResult.Error)"
            return $null
        }

        $normalized = Normalize-ExecutionResultValue -Value $evalResult.Result -TreatArraysAsSequence
        Write-ExecutionLog -Context $Context -Message ({ "  [INLINE-FALLBACK] Direct helper result for '$FuncName': $(Format-VariableValue $normalized)" }).GetNewClosure()
        return $normalized
    } finally {
        foreach ($tempVarName in @($argVarName, $namedVarName)) {
            try {
                $Context.ExecContext.Runspace.SessionStateProxy.PSVariable.Remove($tempVarName)
            } catch {
            }
        }
    }
}

function Resolve-EmbeddedFunctionCalls {
    param(
        [string]$Code,
        $Ast,
        [hashtable]$Context,
        [int]$NodeId = -1
    )

    if (-not $Ast) { return $Code }
    if ($Context.FunctionSubgraphs.Count -eq 0) { return $Code }

    $funcCalls = @()
    $allCommands = $Ast.FindAll({
        param($ast)
        $ast -is [System.Management.Automation.Language.CommandAst]
    }, $true)

    foreach ($cmd in $allCommands) {
        $cmdName = $cmd.GetCommandName()
        if ($cmdName -and $Context.FunctionSubgraphs.ContainsKey($cmdName)) {
            $hasUserFunctionAncestor = $false
            $ancestor = $cmd.Parent
            while ($null -ne $ancestor -and $ancestor -ne $Ast) {
                if ($ancestor -is [System.Management.Automation.Language.CommandAst]) {
                    $ancestorName = $ancestor.GetCommandName()
                    if ($ancestorName -and $Context.FunctionSubgraphs.ContainsKey($ancestorName)) {
                        $hasUserFunctionAncestor = $true
                        break
                    }
                }
                $ancestor = $ancestor.Parent
            }

            if (-not $hasUserFunctionAncestor) {
                $funcCalls += [PSCustomObject]@{
                    Ast      = $cmd
                    FuncName = $cmdName
                    Start    = [int]$cmd.Extent.StartOffset
                    End      = [int]$cmd.Extent.EndOffset
                    Text     = [string]$cmd.Extent.Text
                }
            }
        }
    }

    if ($funcCalls.Count -eq 0) { return $Code }

    $funcCalls = @($funcCalls | Sort-Object -Property Start)

    $baseOffset = $Ast.Extent.StartOffset

    $replacements = New-Object System.Collections.Generic.List[object]
    foreach ($call in $funcCalls) {
        $args = @()
        $namedArgs = @{}
        $bindingInfo = Get-CommandInvocationBindings -CommandAst $call.Ast -Context $Context -StartIndex 1 -CallerNodeId $NodeId
        if ($bindingInfo) {
            $args = @($bindingInfo.PositionalArguments)
            $namedArgs = if ($bindingInfo.NamedArguments) { $bindingInfo.NamedArguments } else { @{} }
        }

        $logParts = New-Object System.Collections.Generic.List[string]
        foreach ($value in @($args)) {
            $logParts.Add((Format-VariableValue $value)) | Out-Null
        }
        foreach ($entry in @($namedArgs.GetEnumerator() | Sort-Object Name)) {
            $logParts.Add(("-{0} {1}" -f [string]$entry.Key, (Format-VariableValue $entry.Value))) | Out-Null
        }

        Write-ExecutionLog -Context $Context -Message ({ "  [INLINE] Resolving: $($call.Text) with args: $($logParts -join ', ')" }).GetNewClosure()

        $funcResult = Invoke-FunctionInline -FuncName $call.FuncName -Arguments $args -NamedArguments $namedArgs -Context $Context

        $tempVar = "_inline_" + [guid]::NewGuid().ToString("N").Substring(0,8)

        $Context.ExecContext.Runspace.SessionStateProxy.SetVariable($tempVar, $funcResult)

        if ($NodeId -ge 0 -and (Test-ResolvableValue $funcResult)) {
            $inlineKey = "$($NodeId):$($call.Start):$($call.End)"
            if (-not $Context.VariableReadResults.ContainsKey($inlineKey)) {
                $Context.VariableReadResults[$inlineKey] = @{
                    NodeId  = $NodeId
                    VarInfo = [PSCustomObject]@{
                        Name           = $tempVar
                        StartOffset    = $call.Start
                        EndOffset      = $call.End
                        Text           = $call.Text
                        IsInlineResult = $true
                    }
                    Values = @()
                }
            }
            $Context.VariableReadResults[$inlineKey].Values += (Format-ResolvableValue $funcResult)
        }

        Write-ExecutionLog -Context $Context -Message ({ "  [INLINE] Created temp var `$$tempVar = $(Format-VariableValue $funcResult)" }).GetNewClosure()
        $relStart = [int]($call.Start - $baseOffset)
        $relEnd = [int]($call.End - $baseOffset)
        if ($relStart -lt 0 -or $relEnd -lt $relStart -or $relEnd -gt $Code.Length) {
            throw "Inline replacement range out of bounds: start=$relStart end=$relEnd codeLength=$($Code.Length) text=$($call.Text)"
        }

        $replacements.Add([PSCustomObject]@{
            Start = $relStart
            End   = $relEnd
            Text  = "`$$tempVar"
        }) | Out-Null

        Write-ExecutionLog -Context $Context -Message ({ "  [INLINE] Result: $($call.FuncName) => $(Format-VariableValue $funcResult)" }).GetNewClosure()
    }

    $builder = New-Object System.Text.StringBuilder
    $cursor = 0
    foreach ($replacement in @($replacements | Sort-Object Start)) {
        if ($replacement.Start -lt $cursor) {
            continue
        }

        [void]$builder.Append($Code.Substring($cursor, $replacement.Start - $cursor))
        [void]$builder.Append([string]$replacement.Text)
        $cursor = [int]$replacement.End
    }

    if ($cursor -lt $Code.Length) {
        [void]$builder.Append($Code.Substring($cursor))
    }

    return $builder.ToString()
}

function Invoke-ScriptBlockCall {
    param(
        [string]$BlockName,
        $CallerNode,
        [hashtable]$Context,
        [array]$PreParsedArguments = $null
    )

    if ([string]::IsNullOrWhiteSpace($BlockName)) {
        Write-ExecutionLog -Context $Context -Message "  [ERROR] ScriptBlock name is null or empty"
        return @{
            Success  = $false
            Executed = $true
            Error    = "ScriptBlock name is null or empty"
            Action   = "CallScriptBlock"
            Target   = $BlockName
        }
    }

    if ($Context.ContainsKey('DynamicDepthLimit') -and $null -ne $Context.DynamicDepthLimit) {
        $runtimeDepth = 0
        if ($Context.ContainsKey('RuntimeSubgraphs') -and $Context.RuntimeSubgraphs -and $Context.RuntimeSubgraphs.ContainsKey($BlockName)) {
            $runtimeInfo = $Context.RuntimeSubgraphs[$BlockName]
            $cursor = if ($runtimeInfo -and $runtimeInfo.PSObject.Properties['ParentBlockName']) { [string]$runtimeInfo.ParentBlockName } else { $null }
            while (-not [string]::IsNullOrWhiteSpace($cursor)) {
                $runtimeDepth++
                if (-not $Context.RuntimeSubgraphs.ContainsKey($cursor)) { break }
                $parentInfo = $Context.RuntimeSubgraphs[$cursor]
                $cursor = if ($parentInfo -and $parentInfo.PSObject.Properties['ParentBlockName']) { [string]$parentInfo.ParentBlockName } else { $null }
            }
        }

        if ($runtimeDepth -ge [int]$Context.DynamicDepthLimit) {
            Write-ExecutionLog -Context $Context -Message "  [DYNAMIC-GATE] Runtime subgraph depth $runtimeDepth reached DynamicDepthLimit=$($Context.DynamicDepthLimit), stop entering nested subgraph $BlockName"
            return @{
                Success  = $true
                Executed = $true
                Result   = $null
                Error    = $null
                Action   = "CallScriptBlock"
                Target   = $BlockName
                StopReason = 'PreExecutionGate:DynamicDepthLimit'
            }
        }
    }

    if ($Context.CallStack.Count -ge $Context.MaxCallDepth) {
        Write-ExecutionLog -Context $Context -Message "  [ERROR] Max call depth ($($Context.MaxCallDepth)) exceeded"
        return @{
            Success  = $false
            Executed = $true
            Error    = "Max call depth exceeded"
            Action   = "CallScriptBlock"
            Target   = $BlockName
        }
    }

    $blockStartId = $Context.ScriptBlockSubgraphs[$BlockName]
    if (-not $blockStartId) {
        Write-ExecutionLog -Context $Context -Message "  [ERROR] ScriptBlock not found: $BlockName"
        return @{
            Success  = $false
            Executed = $true
            Error    = "ScriptBlock not found: $BlockName"
            Action   = "CallScriptBlock"
            Target   = $BlockName
        }
    }

    $blockEndNode = Get-SubgraphEndNode -CFG $Context.CFG -StartType "BlockStart" -Name $BlockName
    if (-not $blockEndNode) {
        Write-ExecutionLog -Context $Context -Message "  [WARN] ScriptBlock end node not found for: $BlockName"
    }
    $blockEndId = if ($blockEndNode) { $blockEndNode.Id } else { $null }

    $localVars = @()
    if ($blockEndId) {
        $localVars = Get-SubgraphLocalVars -CFG $Context.CFG -StartNodeId $blockStartId -EndNodeId $blockEndId
    }

    $nextNodes = @(Get-NextNodes -CFG $Context.CFG -Node $CallerNode -Context $Context)
    $returnNode = if ($nextNodes.Count -gt 0) { Resolve-CFGNodeValue -CFG $Context.CFG -Value $nextNodes[0] } else { $null }
    $returnNodeId = if ($returnNode) { $returnNode.Id } else { $null }

    $arguments = @()
    $callerInfo = Get-NodeTextExecutionInfo -Node $CallerNode -Context $Context
    if (-not $callerInfo.Success) {
        return @{
            Success  = $false
            Executed = $true
            Error    = "Parse caller Node.Text failed: $($callerInfo.Error)"
            Action   = "CallScriptBlock"
            Target   = $BlockName
        }
    }
    $blockStartNode = Get-NodeById -CFG $Context.CFG -Id $blockStartId
    if (-not $blockStartNode) {
        Write-ExecutionLog -Context $Context -Message "  [ERROR] ScriptBlock start node not found: $BlockName ($blockStartId)"
        return @{
            Success  = $false
            Executed = $true
            Error    = "ScriptBlock start node not found: $BlockName ($blockStartId)"
            Action   = "CallScriptBlock"
            Target   = $BlockName
        }
    }
    $hasProcessBlock = ($blockStartNode.PSObject.Properties['HasProcessBlock'] -and [bool]$blockStartNode.HasProcessBlock)
    $processInputVarName = if ($blockStartNode.PSObject.Properties['ProcessInputVar']) {
        [string]$blockStartNode.ProcessInputVar
    } else {
        "__proc_input"
    }

    if ($null -ne $PreParsedArguments) {
        $arguments = $PreParsedArguments
        for ($i = 0; $i -lt $arguments.Count; $i++) {
            if (Test-ExecutionLogDetailEnabled -Context $Context -FlagName 'LogArgumentDetailsEnabled') {
                Write-ExecutionLog -Context $Context -Message ({ "  [ARGS] Arg[$i]: (pre-parsed) = $(Format-VariableValue $arguments[$i])" }).GetNewClosure()
            }
        }
    }
    else {
        $argInfo = Get-NodeTextScriptBlockArguments -CallerNode $CallerNode -BlockName $BlockName -Context $Context
        if (-not $argInfo.Success) {
            return @{
                Success  = $false
                Executed = $true
                Error    = "Parse arguments from Node.Text failed: $($argInfo.Error)"
                Action   = "CallScriptBlock"
                Target   = $BlockName
            }
        } else {
            $arguments = @($argInfo.Arguments)
            for ($i = 0; $i -lt $arguments.Count; $i++) {
                if (Test-ExecutionLogDetailEnabled -Context $Context -FlagName 'LogArgumentDetailsEnabled') {
                    Write-ExecutionLog -Context $Context -Message ({ "  [ARGS] Arg[$i]: (text-parsed) = $(Format-VariableValue $arguments[$i])" }).GetNewClosure()
                }
            }
        }
    }

    $targetVarName = if ($callerInfo -and $callerInfo.Success) { $callerInfo.TargetVarName } else { $null }

    Push-ExecutionScope -Context $Context -ScopeType "ScriptBlock" -ScopeName $BlockName -ReturnNodeId $returnNodeId -EndNodeId $blockEndId
    if ($Context.ScopeStack.Count -gt 0) {
        $Context.ScopeStack[-1].LocalVars = $localVars
        $Context.ScopeStack[-1].Arguments = $arguments
        $Context.ScopeStack[-1].TargetVarName = $targetVarName

        if ($hasProcessBlock) {
            $pipelineInput = Get-CallerPipelineInput -CallerNode $CallerNode -Context $Context
            Initialize-ProcessInputForCurrentScope -Context $Context -InputItems $pipelineInput.Items -SourcePipeVar $pipelineInput.PipeVar -InputVarName $processInputVarName
        }
    }

    Write-ExecutionLog -Context $Context -Message "  [BLOCK] Entering ScriptBlock '$BlockName' at Node $blockStartId"

    return @{
        Success       = $true
        Executed      = $false
        Action        = "CallScriptBlock"
        Target        = $BlockName
        JumpToNode    = $blockStartNode
        LocalVars     = $localVars
    }
}

function Get-ForEachProcessMacroVariableMap {
    param(
        $Node,
        [hashtable]$Context
    )

    if (-not $Node -or $Node.Type -ne 'ProcessInit') { return $null }

    $ownerAst = $Node.OwnerAst
    $bindNode = @($Context.CFG.Nodes | Where-Object {
            $_.Type -eq 'ProcessBind' -and $_.OwnerAst -eq $ownerAst
        } | Select-Object -First 1)

    $map = [ordered]@{
        PipeVar    = $null
        InputVar   = $null
        IndexVar   = $null
        OutputVar  = $null
        CurrentVar = $null
    }

    foreach ($varInfo in (Get-CFGNodeVarInfos -Node $Node -PropertyName 'VarsRead')) {
        if ($varInfo.Name -match '^_pipe_[a-f0-9]+$') {
            $map.PipeVar = [string]$varInfo.Name
        }
    }
    foreach ($varInfo in (Get-CFGNodeVarInfos -Node $Node -PropertyName 'VarsWritten')) {
        switch -Regex ([string]$varInfo.Name) {
            '^__pfo_in_'      { $map.InputVar = [string]$varInfo.Name; break }
            '^__pfo_.*_idx$'  { $map.IndexVar = [string]$varInfo.Name; break }
            '^__pfo_.*_out$'  { $map.OutputVar = [string]$varInfo.Name; break }
        }
    }
    if ($bindNode.Count -gt 0) {
        foreach ($varInfo in (Get-CFGNodeVarInfos -Node $bindNode[0] -PropertyName 'VarsWritten')) {
            if ($varInfo.Name -match '^__pfo_.*_cur$') {
                $map.CurrentVar = [string]$varInfo.Name
                break
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($map.PipeVar) -or
        [string]::IsNullOrWhiteSpace($map.InputVar) -or
        [string]::IsNullOrWhiteSpace($map.IndexVar) -or
        [string]::IsNullOrWhiteSpace($map.OutputVar)) {
        return $null
    }

    return [PSCustomObject]$map
}

function Invoke-ForEachProcessMacroFastPath {
    param(
        $Node,
        [hashtable]$Context
    )

    if (-not $Node -or $Node.Type -ne 'ProcessInit') {
        return [PSCustomObject]@{ Applied = $false }
    }
    if ($Node.OwnerAst -isnot [System.Management.Automation.Language.CommandAst]) {
        return [PSCustomObject]@{ Applied = $false }
    }

    $commandAst = $Node.OwnerAst
    $transformInfo = Get-ForEachObjectProcessCharTransformInfoFromCommandAst -CommandAst $commandAst
    if (-not $transformInfo.Success) {
        return [PSCustomObject]@{ Applied = $false }
    }

    $commandBlocks = $transformInfo.CommandInfo
    if (-not $commandBlocks -or -not $commandBlocks.Success) {
        return [PSCustomObject]@{ Applied = $false }
    }
    if ((Test-ScriptBlockExpressionAstHasExecutableStatements -ScriptBlockExpressionAst $commandBlocks.BeginBlockAst) -or
        (Test-ScriptBlockExpressionAstHasExecutableStatements -ScriptBlockExpressionAst $commandBlocks.EndBlockAst)) {
        return [PSCustomObject]@{ Applied = $false }
    }

    $varMap = Get-ForEachProcessMacroVariableMap -Node $Node -Context $Context
    if (-not $varMap) {
        return [PSCustomObject]@{ Applied = $false }
    }

    $processEndNode = @($Context.CFG.Nodes | Where-Object {
            $_.Type -eq 'ProcessEnd' -and $_.OwnerAst -eq $commandAst
        } | Select-Object -First 1)
    if ($processEndNode.Count -eq 0) {
        return [PSCustomObject]@{ Applied = $false }
    }

    $inputValue = Get-VariableFromContext -ExecContext $Context.ExecContext -Name $varMap.PipeVar
    $items = @($inputValue)
    $expanded = Expand-ForEachNumericStringInputCoreIfNeeded -Items $items -TransformInfo $transformInfo
    if ($expanded.Changed) {
        $items = @($expanded.Items)
    }

    $fastPath = Try-Invoke-ForEachCharTransformFastPath -Items $items -TransformInfo $transformInfo
    if (-not $fastPath.Success) {
        return [PSCustomObject]@{ Applied = $false }
    }

    $inputCollection = [System.Collections.ObjectModel.Collection[System.Management.Automation.PSObject]]::new()
    foreach ($item in @($items)) {
        if ($null -ne $item) {
            [void]$inputCollection.Add([System.Management.Automation.PSObject]$item)
        }
    }

    $outputCollection = [System.Collections.ObjectModel.Collection[System.Management.Automation.PSObject]]::new()
    foreach ($o in @($fastPath.Outputs)) {
        if ($null -ne $o) {
            [void]$outputCollection.Add([System.Management.Automation.PSObject]$o)
        }
    }

    $Context.ExecContext.Runspace.SessionStateProxy.SetVariable($varMap.InputVar, $inputCollection)
    $Context.ExecContext.Runspace.SessionStateProxy.SetVariable($varMap.IndexVar, [int]$inputCollection.Count)
    $Context.ExecContext.Runspace.SessionStateProxy.SetVariable($varMap.OutputVar, $outputCollection)
    if (-not [string]::IsNullOrWhiteSpace($varMap.CurrentVar) -and $inputCollection.Count -gt 0) {
        $Context.ExecContext.Runspace.SessionStateProxy.SetVariable($varMap.CurrentVar, $inputCollection[$inputCollection.Count - 1])
    }

    return [PSCustomObject]@{
        Applied      = $true
        Success      = $true
        Action       = 'ProcessMacroFastPath'
        Reason       = $fastPath.Reason
        Expanded     = [bool]$expanded.Changed
        InputCount   = [int]$inputCollection.Count
        OutputCount  = [int]$outputCollection.Count
        NextNode     = $processEndNode[0]
    }
}

function Register-RuntimeSubgraph {
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][string]$BlockName,
        [Parameter(Mandatory)][int]$BlockStartId,
        [Parameter(Mandatory)][int]$BlockEndId,
        [int[]]$NewNodeIds = @(),
        $CallerNode,
        [string]$DynamicType,
        [string]$ArgumentCode,
        [string]$ArgumentValue
    )

    if (-not $Context.ContainsKey('RuntimeSubgraphs') -or $null -eq $Context.RuntimeSubgraphs) {
        $Context.RuntimeSubgraphs = @{}
    }
    if (-not $Context.ContainsKey('RuntimeSubgraphOrder') -or $null -eq $Context.RuntimeSubgraphOrder) {
        $Context.RuntimeSubgraphOrder = @()
    }

    $callerNodeId = if ($CallerNode) { [int]$CallerNode.Id } else { $null }
    $callerText = if ($CallerNode) { [string]$CallerNode.Text } else { $null }
    $callerStartOffset = if ($CallerNode -and $CallerNode.PSObject.Properties['TextStartOffset']) { $CallerNode.TextStartOffset } else { $null }
    $callerEndOffset = if ($CallerNode -and $CallerNode.PSObject.Properties['TextEndOffset']) { $CallerNode.TextEndOffset } else { $null }
    $parentBlockName = if ($CallerNode -and $CallerNode.PSObject.Properties['RuntimeBlockName']) { [string]$CallerNode.RuntimeBlockName } else { $null }
    $createdIndex = @($Context.RuntimeSubgraphOrder).Count + 1

    $info = [PSCustomObject]@{
        BlockName          = $BlockName
        BlockStartId       = $BlockStartId
        BlockEndId         = $BlockEndId
        CallerNodeId       = $callerNodeId
        CallerText         = $callerText
        CallerStartOffset  = $callerStartOffset
        CallerEndOffset    = $callerEndOffset
        ParentBlockName    = $parentBlockName
        DynamicType        = $DynamicType
        ArgumentCode       = $ArgumentCode
        ArgumentValue      = $ArgumentValue
        CreatedVisit       = if ($Context.ContainsKey('TotalVisits')) { [int]$Context.TotalVisits } else { 0 }
        CreatedIndex       = $createdIndex
        NewNodeIds         = @($NewNodeIds)
    }

    $Context.RuntimeSubgraphs[$BlockName] = $info
    $Context.RuntimeSubgraphOrder += @($BlockName)

    foreach ($nodeId in @($NewNodeIds)) {
        $runtimeNode = Get-NodeById -CFG $Context.CFG -Id $nodeId
        if (-not $runtimeNode) { continue }
        $runtimeNode | Add-Member -NotePropertyName 'RuntimeGenerated' -NotePropertyValue $true -Force
        $runtimeNode | Add-Member -NotePropertyName 'RuntimeBlockName' -NotePropertyValue $BlockName -Force
        $runtimeNode | Add-Member -NotePropertyName 'RuntimeCallerNodeId' -NotePropertyValue $callerNodeId -Force
        $runtimeNode | Add-Member -NotePropertyName 'RuntimeCallerText' -NotePropertyValue $callerText -Force
        $runtimeNode | Add-Member -NotePropertyName 'RuntimeCallerStartOffset' -NotePropertyValue $callerStartOffset -Force
        $runtimeNode | Add-Member -NotePropertyName 'RuntimeCallerEndOffset' -NotePropertyValue $callerEndOffset -Force
        $runtimeNode | Add-Member -NotePropertyName 'RuntimeDynamicType' -NotePropertyValue $DynamicType -Force
        $runtimeNode | Add-Member -NotePropertyName 'RuntimeParentBlockName' -NotePropertyValue $parentBlockName -Force
    }

    return $info
}

function Handle-DynamicInvoke {
    param(
        $Node,
        [hashtable]$Context,
        $CommandInfo = $null,
        $DynamicInfo = $null,
        $DynamicTypeFromCommand = $null
    )

    $argumentValue = $null
    $argCode = $null
    $dynType = $null
    $isScriptBlockCreateFromCommand = $false

    if ($DynamicInfo -and $DynamicInfo.Type -in @("ScriptBlockCreate", "NewScriptBlock", "PowerShellCommand")) {
        $dynType = $DynamicInfo.Type
    } elseif ($DynamicTypeFromCommand -eq "ScriptBlockCreate") {
        $dynType = "ScriptBlockCreate"
        $isScriptBlockCreateFromCommand = $true
    } elseif ($DynamicTypeFromCommand -eq 'PowerShellCommand') {
        $dynType = 'PowerShellCommand'
    } else {
        $dynType = "IEX"
    }

    $nodeTextOverride = if ($CommandInfo -and $CommandInfo.PSObject.Properties['ResolvedNodeText'] -and
        -not [string]::IsNullOrWhiteSpace([string]$CommandInfo.ResolvedNodeText)) {
        [string]$CommandInfo.ResolvedNodeText
    } else {
        $null
    }

    $argCodeInfo = Get-DynamicArgumentCodeFromNodeText -Node $Node -Context $Context -DynamicType $dynType -NodeTextOverride $nodeTextOverride -CommandInfo $CommandInfo
    if (-not $argCodeInfo.Success) {
        return @{
            Success       = $false
            Executed      = $true
            Result        = $null
            Error         = "Parse Node.Text failed: $($argCodeInfo.Error)"
            Action        = "DynamicInvoke"
            DynamicRecord = $null
        }
    }
    $argCode = $argCodeInfo.Code
    $displayArgCode = if ($argCodeInfo.PSObject.Properties['DisplayCode'] -and -not [string]::IsNullOrWhiteSpace([string]$argCodeInfo.DisplayCode)) {
        [string]$argCodeInfo.DisplayCode
    } else {
        $argCode
    }
    $fromPipelineInput = ($argCodeInfo.PSObject.Properties['FromPipelineInput'] -and [bool]$argCodeInfo.FromPipelineInput)

    if ($fromPipelineInput) {
        $pipeInput = Get-CallerPipelineInput -CallerNode $Node -Context $Context
        if ($pipeInput -and $pipeInput.Items -and @($pipeInput.Items).Count -gt 0) {
            $pipeItems = @($pipeInput.Items)
            if ($pipeItems.Count -eq 1) {
                $argumentValue = Normalize-ExecutionResultValue -Value $pipeItems[0] -TreatArraysAsSequence
            } else {
                $argumentValue = ($pipeItems | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
            }
        }

        if ([string]::IsNullOrWhiteSpace($displayArgCode) -and $pipeInput -and $pipeInput.PipeVar) {
            $displayArgCode = "`$$($pipeInput.PipeVar)"
        }
    } elseif ($argCode) {
        $evalCode = Convert-CodeForCurrentScope -Code $argCode -Context $Context
        $evalResult = Invoke-InContext -ExecContext $Context.ExecContext -Code $evalCode
        if ($evalResult.Success -and $null -ne $evalResult.Result) {
            $argumentValue = Normalize-ExecutionResultValue -Value $evalResult.Result -TreatArraysAsSequence
        }
    }

    $blockedArgumentPreservedText = Get-BlockedPlaceholderPreservedText -Value $argumentValue

    $dynamicRecord = @{
        NodeId        = $Node.Id
        Command       = $dynType
        ArgumentCode  = $displayArgCode
        ArgumentValue = $argumentValue
        ReplacementText = $null
        PreservedCommandText = $null
        ReplacementStartOffset = $null
        ReplacementEndOffset = $null
        Timestamp     = Get-Date
        RecursionStopped = $false
        StopReason    = $null
        StopMessage   = $null
        MaterializationKind = $null
    }

    $nodeBaseStartOffset = $null
    if ($Node -and $Node.PSObject.Properties['TextStartOffset'] -and $null -ne $Node.TextStartOffset) {
        $nodeBaseStartOffset = [int]$Node.TextStartOffset
    }
    if ($dynType -in @('IEX', 'PowerShellCommand') -and
        $Node -and
        $Node.PSObject.Properties['TextStartOffset'] -and $null -ne $Node.TextStartOffset -and
        $Node.PSObject.Properties['TextEndOffset'] -and $null -ne $Node.TextEndOffset) {
        $dynamicRecord.ReplacementStartOffset = [int]$Node.TextStartOffset
        $dynamicRecord.ReplacementEndOffset = [int]$Node.TextEndOffset
    } elseif ($null -ne $nodeBaseStartOffset -and
        $argCodeInfo.PSObject.Properties['ReplacementStartOffset'] -and $null -ne $argCodeInfo.ReplacementStartOffset -and
        $argCodeInfo.PSObject.Properties['ReplacementEndOffset'] -and $null -ne $argCodeInfo.ReplacementEndOffset) {
        $dynamicRecord.ReplacementStartOffset = $nodeBaseStartOffset + [int]$argCodeInfo.ReplacementStartOffset
        $dynamicRecord.ReplacementEndOffset = $nodeBaseStartOffset + [int]$argCodeInfo.ReplacementEndOffset
    }

    if ($fromPipelineInput -and $Node -and $Node.Ast -is [System.Management.Automation.Language.CommandAst] -and
        $Node.Ast.Parent -is [System.Management.Automation.Language.PipelineAst]) {
        $pipelineAsts = @($Node.Ast.Parent.PipelineElements)
        if ($pipelineAsts.Count -gt 1) {
            for ($i = 0; $i -lt $pipelineAsts.Count; $i++) {
                if ($pipelineAsts[$i] -ne $Node.Ast) { continue }
                if ($i -gt 0 -and $pipelineAsts[0].Extent -and $pipelineAsts[$i].Extent) {
                    $dynamicRecord.ReplacementStartOffset = [int]$pipelineAsts[0].Extent.StartOffset
                    $dynamicRecord.ReplacementEndOffset = [int]$pipelineAsts[$i].Extent.EndOffset
                }
                break
            }
        }
    }

    $Context.DynamicInvokeResults += $dynamicRecord

    Write-ExecutionLog -Context $Context -Message "  [DYNAMIC] Type: $dynType"

    $argumentBaseObject = Get-SafePSBaseObject -Value $argumentValue
    if ($argumentValue -is [BlockedCommandPlaceholder] -or ($null -ne $argumentBaseObject -and $argumentBaseObject -is [BlockedCommandPlaceholder])) {
        $preservedCommandText = Get-PreservedDynamicInvokeCommandText -Node $Node -ArgCode $argCode -DisplayArgCode $displayArgCode -PreservedArgumentText $blockedArgumentPreservedText
        $dynamicRecord.PreservedCommandText = $preservedCommandText
        $dynamicRecord.ReplacementText = $preservedCommandText
        $dynamicRecord.StopReason = 'DynamicArgumentBlocked'
        $dynamicRecord.StopMessage = '动态参数依赖被阻断命令，保留已解析命令文本但不执行。'
        Write-ExecutionLog -Context $Context -Message "  [DYNAMIC] $($dynamicRecord.StopMessage)"

        return @{
            Success       = $true
            Executed      = $false
            Result        = $argumentValue
            Error         = $null
            Action        = "DynamicInvoke"
            DynamicRecord = $dynamicRecord
            StopReason    = $dynamicRecord.StopReason
        }
    }

    $materializedArgument = Convert-DynamicInvocationValueToScriptText -Value $argumentValue
    if ($materializedArgument.Success -and -not [string]::IsNullOrWhiteSpace([string]$materializedArgument.Text)) {
        if (-not ($argumentValue -is [string]) -or ([string]$argumentValue -cne [string]$materializedArgument.Text)) {
            Write-ExecutionLog -Context $Context -Message "  [DYNAMIC] Materialized argument to script text via $($materializedArgument.Kind)"
        }
        $argumentValue = [string]$materializedArgument.Text
        $dynamicRecord.ArgumentValue = $argumentValue
        $dynamicRecord.MaterializationKind = $materializedArgument.Kind
    }

    if (-not ($argumentValue -is [string]) -or [string]::IsNullOrWhiteSpace($argumentValue)) {
        Write-ExecutionLog -Context $Context -Message "  [DYNAMIC] Cannot resolve argument to string, falling back to direct execution"
        $result = Invoke-NodeDirect -Node $Node -Context $Context
        if ($result.Success) {
            Evaluate-NodeResolvables -Node $Node -Context $Context
        }
        $result.Action = "DynamicInvoke"
        $result.DynamicRecord = $dynamicRecord
        return $result
    }

    $codePreview = if ($argumentValue.Length -gt 100) { $argumentValue.Substring(0, 100) + "..." } else { $argumentValue }
    Write-ExecutionLog -Context $Context -Message "  [DYNAMIC] Code to execute: $codePreview"

    $replacementText = $argumentValue
    if ($dynType -eq 'PowerShellCommand' -and $CommandInfo -and $CommandInfo.Ast -is [System.Management.Automation.Language.CommandAst]) {
        $canonicalHostCommand = ConvertTo-CanonicalPowerShellHostCommandText -CommandAst $CommandInfo.Ast -PayloadText $argumentValue
        if (-not [string]::IsNullOrWhiteSpace($canonicalHostCommand)) {
            $replacementText = $canonicalHostCommand
        }
    }
    $dynamicRecord.ReplacementText = $replacementText

    $dynamicInvocationStopwatch = if ($Context.DynamicTimeBudgetMs -gt 0) { [System.Diagnostics.Stopwatch]::StartNew() } else { $null }
    $dynamicBudgetStatus = Get-StopwatchBudgetStatus -BudgetMs $Context.DynamicTimeBudgetMs -Stopwatch $dynamicInvocationStopwatch -StopReason 'DynamicInvocationBudgetExceeded'
    if ($dynamicBudgetStatus.Exceeded) {
        $dynamicRecord.RecursionStopped = $true
        $dynamicRecord.StopReason = $dynamicBudgetStatus.StopReason
        $dynamicRecord.StopMessage = "单次动态展开预算已耗尽（Elapsed=${0}ms, Budget=${1}ms），停止继续深入，直接回写当前脚本内容。" -f $dynamicBudgetStatus.ElapsedMs, $dynamicBudgetStatus.BudgetMs
        $dynamicRecord.DynamicElapsedMs = $dynamicBudgetStatus.ElapsedMs
        $postStopRecovered = Invoke-DynamicStopPostProcessRecovery -ScriptText $argumentValue
        if (-not [string]::IsNullOrWhiteSpace($postStopRecovered)) {
            $dynamicRecord.ReplacementText = $postStopRecovered
            $dynamicRecord.PostStopRecovered = $true
        }
        Write-ExecutionLog -Context $Context -Message "  [DYNAMIC] $($dynamicRecord.StopMessage)"

        return @{
            Success       = $true
            Executed      = $true
            Result        = $argumentValue
            Error         = $null
            Action        = "DynamicInvoke"
            DynamicRecord = $dynamicRecord
            StopReason    = $dynamicRecord.StopReason
        }
    }

    $payloadStop = Test-DynamicPayloadShouldStopRecursing -ScriptText $argumentValue -SafeMode:([bool]$Context.SafeMode) -GateMode $(if ($Context.ContainsKey('PreExecutionGateMode') -and $Context.PreExecutionGateMode) { [string]$Context.PreExecutionGateMode } else { 'Balanced' }) -GateCache $(if ($Context.ContainsKey('PreExecutionGateCache')) { $Context.PreExecutionGateCache } else { $null })
    if ($payloadStop.ShouldStop) {
        $dynamicRecord.RecursionStopped = $true
        $dynamicRecord.StopReason = $payloadStop.StopReason
        $dynamicRecord.StopMessage = $payloadStop.Message
        $dynamicRecord.StopFeatures = @($payloadStop.Features)
        $dynamicRecord.StopFeatureSummary = $payloadStop.FeatureSummary
        if ($payloadStop.PSObject.Properties['GateScore']) { $dynamicRecord.GateScore = $payloadStop.GateScore }
        if ($payloadStop.PSObject.Properties['GateReasons']) { $dynamicRecord.GateReasons = @($payloadStop.GateReasons) }
        if ($payloadStop.PSObject.Properties['GateMetrics']) { $dynamicRecord.GateMetrics = $payloadStop.GateMetrics }
        $postStopRecovered = Invoke-DynamicStopPostProcessRecovery -ScriptText $argumentValue
        if (-not [string]::IsNullOrWhiteSpace($postStopRecovered)) {
            $dynamicRecord.ReplacementText = $postStopRecovered
            $dynamicRecord.PostStopRecovered = $true
        }
        Write-ExecutionLog -Context $Context -Message "  [DYNAMIC] $($payloadStop.Message)"
        if ($payloadStop.FeatureSummary) {
            Write-ExecutionLog -Context $Context -Message "  [DYNAMIC] Features: $($payloadStop.FeatureSummary)"
        }

        return @{
            Success       = $true
            Executed      = $true
            Result        = $argumentValue
            Error         = $null
            Action        = "DynamicInvoke"
            DynamicRecord = $dynamicRecord
            StopReason    = $dynamicRecord.StopReason
        }
    }

    if ($payloadStop -and $payloadStop.PSObject.Properties['Decision'] -and [string]$payloadStop.Decision -eq 'Shallow' -and
        $Context.ContainsKey('DynamicTimeBudgetMs') -and $null -ne $payloadStop.ReducedDynamicBudgetMs) {
        $Context.DynamicTimeBudgetMs = [Math]::Min([int]$Context.DynamicTimeBudgetMs, [int]$payloadStop.ReducedDynamicBudgetMs)
        $Context.DynamicDepthLimit = 1
        $dynamicRecord.StopFeatures = @($payloadStop.Features)
        $dynamicRecord.StopFeatureSummary = $payloadStop.FeatureSummary
        $dynamicRecord.GateScore = $payloadStop.GateScore
        $dynamicRecord.GateReasons = @($payloadStop.GateReasons)
        $dynamicRecord.GateMetrics = $payloadStop.GateMetrics
        Write-ExecutionLog -Context $Context -Message "  [DYNAMIC-GATE] Shallow gate applied: DynamicBudget=$($Context.DynamicTimeBudgetMs)ms, DynamicDepthLimit=$($Context.DynamicDepthLimit)"
    }

    $dynamicBudgetStatus = Get-StopwatchBudgetStatus -BudgetMs $Context.DynamicTimeBudgetMs -Stopwatch $dynamicInvocationStopwatch -StopReason 'DynamicInvocationBudgetExceeded'
    if ($dynamicBudgetStatus.Exceeded) {
        $dynamicRecord.RecursionStopped = $true
        $dynamicRecord.StopReason = $dynamicBudgetStatus.StopReason
        $dynamicRecord.StopMessage = "单次动态展开预算已耗尽（Elapsed=${0}ms, Budget=${1}ms），停止继续深入，直接回写当前脚本内容。" -f $dynamicBudgetStatus.ElapsedMs, $dynamicBudgetStatus.BudgetMs
        $dynamicRecord.DynamicElapsedMs = $dynamicBudgetStatus.ElapsedMs
        $postStopRecovered = Invoke-DynamicStopPostProcessRecovery -ScriptText $argumentValue
        if (-not [string]::IsNullOrWhiteSpace($postStopRecovered)) {
            $dynamicRecord.ReplacementText = $postStopRecovered
            $dynamicRecord.PostStopRecovered = $true
        }
        Write-ExecutionLog -Context $Context -Message "  [DYNAMIC] $($dynamicRecord.StopMessage)"

        return @{
            Success       = $true
            Executed      = $true
            Result        = $argumentValue
            Error         = $null
            Action        = "DynamicInvoke"
            DynamicRecord = $dynamicRecord
            StopReason    = $dynamicRecord.StopReason
        }
    }

    if (($DynamicInfo -and $DynamicInfo.Type -in @("ScriptBlockCreate", "NewScriptBlock")) -or $isScriptBlockCreateFromCommand) {

        $subgraphResult = New-RuntimeSubgraph -cfg $Context.CFG -Code $argumentValue

        if (-not $subgraphResult.Success) {
            Write-ExecutionLog -Context $Context -Message "  [DYNAMIC] Parse error: $($subgraphResult.Error), falling back to direct execution"
            $result = Invoke-NodeDirect -Node $Node -Context $Context
            if ($result.Success) {
                Evaluate-NodeResolvables -Node $Node -Context $Context
            }
            $result.Action = "DynamicInvoke"
            $result.DynamicRecord = $dynamicRecord
            return $result
        }

        $blockName = $subgraphResult.BlockName
        $blockVarRef = "`$$blockName"
        $scriptBlockLiteral = "{$argumentValue}"

        $Context.ScriptBlockSubgraphs[$blockName] = $subgraphResult.BlockStartId
        $runtimeInfo = Register-RuntimeSubgraph -Context $Context -BlockName $blockName -BlockStartId $subgraphResult.BlockStartId -BlockEndId $subgraphResult.BlockEndId -NewNodeIds $subgraphResult.NewNodeIds -CallerNode $Node -DynamicType $dynType -ArgumentCode $displayArgCode -ArgumentValue $argumentValue
        $dynamicRecord.BlockName = $blockName
        $dynamicRecord.BlockStartId = $subgraphResult.BlockStartId
        $dynamicRecord.BlockEndId = $subgraphResult.BlockEndId
        $dynamicRecord.ParentBlockName = $runtimeInfo.ParentBlockName
        Write-ExecutionLog -Context $Context -Message "  [DYNAMIC] Created subgraph: $blockName (Nodes $($subgraphResult.BlockStartId)-$($subgraphResult.BlockEndId))"

        $translationText = "$blockVarRef = $scriptBlockLiteral"
        $translationNode = Add-Node -cfg $Context.CFG -type "DynamicTranslation" -text $translationText -line $Node.Line -ast $null
        Write-ExecutionLog -Context $Context -Message "  [DYNAMIC] Created translation node: $translationText"

        foreach ($edge in $Context.CFG.Edges) {
            if ($edge.To -eq $Node.Id) {
                $edge.To = $translationNode.Id
            }
        }
        Add-Edge -cfg $Context.CFG -from $translationNode.Id -to $Node.Id
        $null = Sync-CFGExecutionIndexesIncremental -CFG $Context.CFG -ForceRebuild
        Write-ExecutionLog -Context $Context -Message "  [DYNAMIC] Inserted translation node before Node $($Node.Id)"

        $sbCode = "[ScriptBlock]::Create('$($argumentValue.Replace("'", "''"))')"
        $sbResult = Invoke-InContext -ExecContext $Context.ExecContext -Code $sbCode
        if ($sbResult.Success) {
            $blockValue = Normalize-ExecutionResultValue -Value $sbResult.Result -TreatArraysAsSequence
            $Context.ExecContext.Runspace.SessionStateProxy.SetVariable($blockName, $blockValue)
            Write-ExecutionLog -Context $Context -Message "  [DYNAMIC] Set `$$blockName = [ScriptBlock]"
        }

        Write-ExecutionLog -Context $Context -Message "--- Node $($translationNode.Id) [DynamicTranslation] ---"
        Write-ExecutionLog -Context $Context -Message "  Code: $translationText"
        Write-ExecutionLog -Context $Context -Message "  Status: OK (Dynamic)"
        Write-ExecutionLog -Context $Context -Message "  VarsWritten:"
        Write-ExecutionLog -Context $Context -Message "    `$$blockName = [ScriptBlock]"
        $Context.TotalVisits++

        if ($isScriptBlockCreateFromCommand) {
            $nodeOrigText = $Node.Text
            $cmdAst = $CommandInfo.Ast  # CommandAst

            $firstElement = $cmdAst.CommandElements[0]
            $lastElement = $cmdAst.CommandElements[$cmdAst.CommandElements.Count - 1]

            $startOffset = $firstElement.Extent.StartOffset
            $endOffset = $lastElement.Extent.EndOffset
            $sourceText = $cmdAst.Extent.StartScriptPosition.GetFullScript()
            $replaceText = $sourceText.Substring($startOffset, $endOffset - $startOffset)

            $newText = $nodeOrigText.Replace($replaceText, $blockVarRef)
            $Node.Text = $newText
            Write-ExecutionLog -Context $Context -Message "  [DYNAMIC] Original node text replaced: $newText"
        } elseif ($DynamicInfo -and $DynamicInfo.ArgAst) {
            $invokeAst = $DynamicInfo.ArgAst.Parent  # InvokeMemberExpressionAst
            if ($invokeAst) {
                $replaceText = $invokeAst.Extent.Text
                $nodeOrigText = $Node.Text

                $current = $invokeAst.Parent
                while ($current -and $current -ne $Node.Ast) {
                    if ($current -is [System.Management.Automation.Language.ParenExpressionAst]) {
                        $replaceText = $current.Extent.Text
                    }
                    if ($current -is [System.Management.Automation.Language.CommandAst]) {
                        break
                    }
                    $current = $current.Parent
                }

                $newText = $nodeOrigText.Replace($replaceText, $blockVarRef)
                $Node.Text = $newText
                Write-ExecutionLog -Context $Context -Message "  [DYNAMIC] Original node text replaced: $newText"
            }
        }

        $Node.DynamicInvoke = $null

        $nodeVarsWritten = @(Get-CFGNodeVarInfos -Node $Node -PropertyName 'VarsWritten')
        $isCallForm = $Node.Text -match '^[&\.]?\s*\$' -and ($nodeVarsWritten.Count -eq 0)

        if ($isCallForm) {
            if (-not $Node.Invokes) {
                $Node.Invokes = @{ ScriptBlocks = @() }
            }
            $Node.Invokes.ScriptBlocks = @($blockName)

            Write-ExecutionLog -Context $Context -Message "  [CALL] ScriptBlock: $blockName (via DynamicTranslation)"
            return Invoke-ScriptBlockCall -BlockName $blockName -CallerNode $Node -Context $Context
        }

        $execCode = $Node.Text
        if ($Context.ScopeStack.Count -gt 0) {
            $currentScope = $Context.ScopeStack[-1]
            if ($currentScope.LocalVars -and $currentScope.LocalVars.Count -gt 0) {
                $execCode = Convert-VariableNames -Code $execCode -ScopePrefix $currentScope.ScopePrefix -LocalVarNames $currentScope.LocalVars
            }
        }

        $execResult = Invoke-InContext -ExecContext $Context.ExecContext -Code $execCode

        if ($nodeVarsWritten.Count -gt 0) {
            foreach ($varInfo in $nodeVarsWritten) {
                $Context.VarToBlockMapping[$varInfo.Name] = $blockName
                Write-ExecutionLog -Context $Context -Message "  [MAPPING] `$$($varInfo.Name) -> $blockName"
            }
        }

        if ($nodeVarsWritten.Count -gt 0) {
            Write-ExecutionLog -Context $Context -Message "  VarsWritten:"
            foreach ($varInfo in $nodeVarsWritten) {
                $varValue = Get-VariableFromContext -ExecContext $Context.ExecContext -Name $varInfo.Name
                Write-ExecutionLog -Context $Context -Message ({ "    `$$($varInfo.Name) = $(Format-VariableValue $varValue)" }).GetNewClosure()
            }
        }

        Evaluate-NodeResolvables -Node $Node -Context $Context

        $result = @{
            Success     = $execResult.Success
            Executed    = $true
            Result      = $execResult.Result
            Error       = $execResult.Error
            Action      = "DynamicInvoke"
            DynamicRecord = $dynamicRecord
        }
        return $result
    } else {
        $subgraphResult = New-RuntimeSubgraph -cfg $Context.CFG -Code $argumentValue

        if (-not $subgraphResult.Success) {
            Write-ExecutionLog -Context $Context -Message "  [DYNAMIC] Parse error: $($subgraphResult.Error), falling back to direct execution"
            $result = Invoke-NodeDirect -Node $Node -Context $Context
            if ($result.Success) {
                Evaluate-NodeResolvables -Node $Node -Context $Context
            }
            $result.Action = "DynamicInvoke"
            $result.DynamicRecord = $dynamicRecord
            return $result
        }

        $blockName = $subgraphResult.BlockName
        $Context.ScriptBlockSubgraphs[$blockName] = $subgraphResult.BlockStartId
        $runtimeInfo = Register-RuntimeSubgraph -Context $Context -BlockName $blockName -BlockStartId $subgraphResult.BlockStartId -BlockEndId $subgraphResult.BlockEndId -NewNodeIds $subgraphResult.NewNodeIds -CallerNode $Node -DynamicType $dynType -ArgumentCode $displayArgCode -ArgumentValue $argumentValue
        $dynamicRecord.BlockName = $blockName
        $dynamicRecord.BlockStartId = $subgraphResult.BlockStartId
        $dynamicRecord.BlockEndId = $subgraphResult.BlockEndId
        $dynamicRecord.ParentBlockName = $runtimeInfo.ParentBlockName

        Write-ExecutionLog -Context $Context -Message "  [DYNAMIC] Created subgraph: $blockName (Nodes $($subgraphResult.BlockStartId)-$($subgraphResult.BlockEndId))"

        $blockVarRef = "`$$blockName"
        $Node.Text = "& $blockVarRef"
        Write-ExecutionLog -Context $Context -Message "  [DYNAMIC] Node text replaced: & $blockVarRef"

        $Node.Invokes.ScriptBlocks = @($blockName)
        $Node.DynamicInvoke = $null

        return Invoke-ScriptBlockCall -BlockName $blockName -CallerNode $Node -Context $Context
    }
}

function Invoke-NodeTraverse {
    param(
        $Node,
        [hashtable]$Context
    )

    $currentNode = $Node

    while ($null -ne $currentNode) {
        $globalBudgetStatus = Get-ContextBudgetStatus -Context $Context -BudgetPropertyName 'GlobalTimeBudgetMs' -StopwatchPropertyName 'ExecutionStopwatch' -StopReason 'GlobalTimeBudgetExceeded'
        if ($globalBudgetStatus.Exceeded) {
            Write-ExecutionLog -Context $Context -Message "!!! 执行总时长超限 ($($globalBudgetStatus.ElapsedMs)ms / $($globalBudgetStatus.BudgetMs)ms) !!!"
            $Context.StopReason = $globalBudgetStatus.StopReason
            break
        }

        if ($currentNode.Type -eq "End") {
            Write-ExecutionLog -Context $Context -Message "=== 执行结束 ==="
            break
        }

        if ($currentNode.Type -eq "FuncEnd" -or $currentNode.Type -eq "BlockEnd") {
            Write-ExecutionLog -Context $Context -Message "--- Node $($currentNode.Id) [$($currentNode.Type)] ---"
            Write-ExecutionLog -Context $Context -Message "  Code: $($currentNode.Text)"

            $returnValue = $Context.LastSubgraphResult

            $scope = Pop-ExecutionScope -Context $Context
            if ($scope) {
                if ($scope.ReturnNodeId) {
                    Add-FunctionInvokeResultRecord -Context $Context -Scope $scope -ReturnValue $returnValue
                    $Context.LastSubgraphResult = $null

                    if ($scope.TargetVarName -and $null -ne $returnValue) {
                        $actualVarName = $scope.TargetVarName
                        if ($Context.ScopeStack.Count -gt 0) {
                            $outerScope = $Context.ScopeStack[-1]
                            if ($outerScope.LocalVars -and $scope.TargetVarName -in $outerScope.LocalVars) {
                                $actualVarName = $outerScope.ScopePrefix + $scope.TargetVarName
                            }
                        }
                        $Context.ExecContext.Runspace.SessionStateProxy.SetVariable($actualVarName, $returnValue)
                        Write-ExecutionLog -Context $Context -Message ({ "  [RETURN] Set `$$actualVarName = $(Format-VariableValue $returnValue)" }).GetNewClosure()
                    }

                    Write-ExecutionLog -Context $Context -Message "  [RETURN] Returning from $($scope.ScopeType) '$($scope.ScopeName)' to Node $($scope.ReturnNodeId)"
                    $returnNode = Get-NodeById -CFG $Context.CFG -Id $scope.ReturnNodeId
                    $currentNode = $returnNode
                } else {
                    $Context.LastSubgraphResult = $returnValue
                    Write-ExecutionLog -Context $Context -Message ({ "  [RETURN] Inline call completed, preserving result: $(Format-VariableValue $returnValue)" }).GetNewClosure()
                    $currentNode = $null
                }
            } else {
                $currentNode = $null
            }
            continue
        }

        if ($currentNode.Type -eq "Return") {
            Write-ExecutionLog -Context $Context -Message "--- Node $($currentNode.Id) [Return] ---"
            Write-ExecutionLog -Context $Context -Message "  Code: $($currentNode.Text)"

            $null = Add-CFGVisitedNodeCount -Context $Context -NodeId $currentNode.Id
            $Context.TotalVisits++

            if ($Context.ScopeStack.Count -gt 0) {
                $currentScope = $Context.ScopeStack[-1]

                $returnValue = $null
                $retInfo = Get-NodeTextReturnExpression -Node $currentNode -Context $Context
                if (-not $retInfo.Success) {
                    Write-ExecutionLog -Context $Context -Message "  [RETURN] Parse Node.Text failed: $($retInfo.Error)"
                } elseif ($retInfo.Code) {
                    $returnCode = Convert-CodeForCurrentScope -Code $retInfo.Code -Context $Context
                    $evalResult = Invoke-InContext -ExecContext $Context.ExecContext -Code $returnCode
                    if ($evalResult.Success -and $null -ne $evalResult.Result) {
                        if ($Context.OutputCaptureStack -and $Context.OutputCaptureStack.Count -gt 0) {
                            Add-OutputsToCurrentCapture -Context $Context -Result $evalResult.Result
                        }

                        $returnValue = Normalize-ExecutionResultValue -Value $evalResult.Result -TreatArraysAsSequence
                        Write-ExecutionLog -Context $Context -Message ({ "  [RETURN] Expression value: $(Format-VariableValue $returnValue)" }).GetNewClosure()
                    }
                }

                $Context.LastSubgraphResult = $returnValue

                if ($currentScope.EndNodeId) {
                    Write-ExecutionLog -Context $Context -Message "  [RETURN] Jumping to EndNode $($currentScope.EndNodeId)"
                    $endNode = Get-NodeById -CFG $Context.CFG -Id $currentScope.EndNodeId
                    $currentNode = $endNode
                } else {
                    $currentNode = $null
                }
            } else {
                $nextNodes = @(Get-NextNodes -CFG $Context.CFG -Node $currentNode -Context $Context)
                $currentNode = if ($nextNodes.Count -gt 0) { $nextNodes[0] } else { $null }
            }
            continue
        }

        if ($Context.TotalVisits -ge $Context.MaxTotalNodes) {
            Write-ExecutionLog -Context $Context -Message "!!! 达到最大节点访问次数 ($($Context.MaxTotalNodes)) !!!"
            break
        }

        $nodeKey = $currentNode.Id
        if (-not $Context.VisitedNodes.ContainsKey($nodeKey)) {
            $Context.VisitedNodes[$nodeKey] = 0
        }
        if ($Context.VisitedNodes[$nodeKey] -ge $Context.MaxIterations) {
            Write-ExecutionLog -Context $Context -Message "!!! 节点 $nodeKey 达到最大迭代次数 ($($Context.MaxIterations)) !!!"
            break
        }

        $Context.VisitedNodes[$nodeKey]++
        $Context.TotalVisits++

        Write-ExecutionLog -Context $Context -Message "--- Node $($currentNode.Id) [$($currentNode.Type)] ---"
        Write-ExecutionLog -Context $Context -Message "  Code: $($currentNode.Text)"

        $processMacroResult = Invoke-ForEachProcessMacroFastPath -Node $currentNode -Context $Context
        if ($processMacroResult.Applied) {
            Write-ExecutionLog -Context $Context -Message "  Status: OK"
            Write-ExecutionLog -Context $Context -Message "  Action: $($processMacroResult.Action)"
            if ($processMacroResult.Reason) {
                Write-ExecutionLog -Context $Context -Message "  Reason: $($processMacroResult.Reason)"
            }
            Write-ExecutionLog -Context $Context -Message "  MacroInputCount: $($processMacroResult.InputCount)"
            Write-ExecutionLog -Context $Context -Message "  MacroOutputCount: $($processMacroResult.OutputCount)"
            if ($processMacroResult.Expanded) {
                Write-ExecutionLog -Context $Context -Message "  MacroExpandedNumericInput: True"
            }
            if ($processMacroResult.NextNode) {
                Write-ExecutionLog -Context $Context -Message "  [JUMP] Jumping to Node $($processMacroResult.NextNode.Id)"
                $currentNode = $processMacroResult.NextNode
                continue
            }
        }

        if ($currentNode.Type -in @('FuncParams', 'BlockParams') -and $Context.ScopeStack.Count -gt 0) {
            $currentScope = $Context.ScopeStack[-1]
            if (($currentScope.Arguments -and $currentScope.Arguments.Count -gt 0) -or
                ($currentScope.NamedArguments -and $currentScope.NamedArguments.Count -gt 0)) {
                $parameterAsts = @()
                if ($currentNode.Ast -and $currentNode.Ast.Parameters) {
                    $parameterAsts = @($currentNode.Ast.Parameters)
                } elseif ($currentNode.PSObject.Properties['ParameterAsts'] -and $currentNode.ParameterAsts) {
                    $parameterAsts = @($currentNode.ParameterAsts)
                }
                if ($parameterAsts.Count -gt 0) {
                    $paramNames = @()
                    foreach ($param in $parameterAsts) {
                        if ($param -and $param.Name -and $param.Name.VariablePath) {
                            $paramNames += $param.Name.VariablePath.UserPath
                        }
                    }

                    $namedLookup = @{}
                    foreach ($key in @($currentScope.NamedArguments.Keys)) {
                        $namedLookup[[string]$key] = $currentScope.NamedArguments[$key]
                    }

                    $posIndex = 0
                    foreach ($paramName in $paramNames) {
                        $hasValue = $false
                        $argValue = $null

                        foreach ($lookupKey in @($namedLookup.Keys)) {
                            if ($lookupKey -ieq $paramName) {
                                $argValue = $namedLookup[$lookupKey]
                                $hasValue = $true
                                break
                            }
                        }

                        if (-not $hasValue -and $posIndex -lt @($currentScope.Arguments).Count) {
                            $argValue = $currentScope.Arguments[$posIndex]
                            $posIndex++
                            $hasValue = $true
                        }

                        if ($hasValue) {
                            $prefixedName = $currentScope.ScopePrefix + $paramName
                            $Context.ExecContext.Runspace.SessionStateProxy.SetVariable($prefixedName, $argValue)
                            if (Test-ExecutionLogDetailEnabled -Context $Context -FlagName 'LogBindingDetailsEnabled') {
                                Write-ExecutionLog -Context $Context -Message ({ "  [BIND] `$$prefixedName = $(Format-VariableValue $argValue)" }).GetNewClosure()
                            }

                            if ($paramName -notin $currentScope.LocalVars) {
                                $currentScope.LocalVars += $paramName
                            }
                        }
                    }
                }
            }
        }

        Ensure-CFGNodeExecutionShape -Node $currentNode
        $currentNodeVarsRead = @(Get-CFGObjectPropertyValue -Object $currentNode -Name 'VarsRead' -Default @())
        $currentNodeVarsWritten = @(Get-CFGObjectPropertyValue -Object $currentNode -Name 'VarsWritten' -Default @())

        $varsBefore = @{}
        foreach ($varInfo in $currentNodeVarsRead) {
            if ($null -eq $varInfo -or [string]::IsNullOrWhiteSpace([string]$varInfo.Name)) {
                Write-ExecutionLog -Context $Context -Message "  [WARN] Skip VarsRead entry with null/empty Name"
                continue
            }
            $actualVarName = $varInfo.Name
            if ($Context.ScopeStack.Count -gt 0) {
                $currentScope = $Context.ScopeStack[-1]
                if ($currentScope.LocalVars -and $varInfo.Name -in $currentScope.LocalVars) {
                    $actualVarName = $currentScope.ScopePrefix + $varInfo.Name
                }
            }

            $value = Get-VariableFromContext -ExecContext $Context.ExecContext -Name $actualVarName
            $varsBefore[$varInfo.Name] = $value

            if ($null -ne $varInfo.StartOffset -and $null -ne $varInfo.EndOffset -and (Test-ResolvableValue $value) -and -not (Test-CFGVariableBlockedTaint -Context $Context -ActualName $actualVarName)) {
                $key = "$($currentNode.Id):$($varInfo.StartOffset):$($varInfo.EndOffset)"
                if (-not $Context.VariableReadResults.ContainsKey($key)) {
                    $Context.VariableReadResults[$key] = @{
                        NodeId  = $currentNode.Id
                        VarInfo = $varInfo
                        Values  = @()
                    }
                }
                $Context.VariableReadResults[$key].Values += (Format-ResolvableValue $value)
            }
        }

        $execResult = Invoke-NodeSafe -Node $currentNode -Context $Context

        if ($Context.OutputCaptureStack -and $Context.OutputCaptureStack.Count -gt 0) {
            $captureThis = $true

            $nonOutputTypes = @('Condition', 'ForEachCondition', 'ProcessCondition', 'SwitchCondition', 'CaseCondition', 'OutputCaptureStart', 'OutputCaptureEnd')
            if ($currentNode.Type -in $nonOutputTypes) {
                $captureThis = $false
            }

            if ($captureThis -and $currentNode.Type -eq 'PipelineElement' -and $currentNodeVarsWritten.Count -gt 0) {
                foreach ($v in $currentNodeVarsWritten) {
                    if ($v.Name -match '^_pipe_[a-f0-9]+$') {
                        $captureThis = $false
                        break
                    }
                }
            }

            if ($captureThis) {
                Add-OutputsToCurrentCapture -Context $Context -Result $execResult.Result
            }
        }

        if ($Context.OutputCaptureStack -and $Context.OutputCaptureStack.Count -gt 0 -and $currentNode.Type -in @('Break', 'Continue')) {
            $label = $currentNode.Type
            $edge = Get-CFGOutgoingEdges -CFG $Context.CFG -FromNodeId $currentNode.Id | Where-Object { $_.Label -eq $label } | Select-Object -First 1
            if ($edge) {
                $targetNode = Get-NodeById -CFG $Context.CFG -Id $edge.To
                if ($targetNode -and $targetNode.Type -in @('BlockEnd', 'FuncEnd', 'ProcessEnd', 'End', 'MainEnd')) {
                    $Context.LastPipelineFlowControl = $label
                }
            }
        }

        $varsAfter = @{}
        foreach ($varInfo in $currentNodeVarsWritten) {
            if ($null -eq $varInfo -or [string]::IsNullOrWhiteSpace([string]$varInfo.Name)) {
                Write-ExecutionLog -Context $Context -Message "  [WARN] Skip VarsWritten entry with null/empty Name"
                continue
            }
            $actualVarName = $varInfo.Name
            if ($Context.ScopeStack.Count -gt 0) {
                $currentScope = $Context.ScopeStack[-1]
                if ($currentScope.LocalVars -and $varInfo.Name -in $currentScope.LocalVars) {
                    $actualVarName = $currentScope.ScopePrefix + $varInfo.Name
                }
            }

            $value = Get-VariableFromContext -ExecContext $Context.ExecContext -Name $actualVarName
            $varsAfter[$varInfo.Name] = $value
        }

        Update-CFGAssignmentBlockedTaint -Node $currentNode -Context $Context
        Update-VariableScriptBlockMappingAfterNodeExecution -Node $currentNode -Context $Context

        $execAction = [string](Get-CFGExecutionResultValue -ExecutionResult $execResult -Name 'Action')
        $execTarget = Get-CFGExecutionResultValue -ExecutionResult $execResult -Name 'Target'
        $execReason = [string](Get-CFGExecutionResultValue -ExecutionResult $execResult -Name 'Reason')
        $execError = [string](Get-CFGExecutionResultValue -ExecutionResult $execResult -Name 'Error')
        $execOutput = Get-CFGExecutionResultValue -ExecutionResult $execResult -Name 'Result'
        $execExecuted = [bool](Get-CFGExecutionResultValue -ExecutionResult $execResult -Name 'Executed' -Default $false)
        $execSuccess = [bool](Get-CFGExecutionResultValue -ExecutionResult $execResult -Name 'Success' -Default $false)
        $execJumpToNode = Get-CFGExecutionResultValue -ExecutionResult $execResult -Name 'JumpToNode'

        $shortText = $currentNode.Text
        $status = if ($execAction -eq "Blocked") {
            "BLOCKED"
        } elseif (-not $execExecuted) {
            "SKIP"
        } elseif ($execSuccess) {
            "OK"
        } else {
            "ERR"
        }

        Write-ExecutionLog -Context $Context -Message "  Status: $status"

        if ($execAction -and $execAction -notin @("Execute", "Skip")) {
            Write-ExecutionLog -Context $Context -Message "  Action: $execAction"
            if ($null -ne $execTarget -and -not [string]::IsNullOrWhiteSpace([string]$execTarget)) {
                Write-ExecutionLog -Context $Context -Message "  Target: $execTarget"
            }
            if (-not [string]::IsNullOrWhiteSpace($execReason)) {
                Write-ExecutionLog -Context $Context -Message "  Reason: $execReason"
            }
        }

        if ($execExecuted) {
            if ((Test-ExecutionLogDetailEnabled -Context $Context -FlagName 'LogVariableDetailsEnabled') -and $varsBefore.Count -gt 0) {
                Write-ExecutionLog -Context $Context -Message "  VarsRead:"
                foreach ($kv in $varsBefore.GetEnumerator()) {
                    $formattedValue = Format-VariableValue $kv.Value
                    Write-ExecutionLog -Context $Context -Message "    `$$($kv.Key) = $formattedValue"
                }
            }

            if ((Test-ExecutionLogDetailEnabled -Context $Context -FlagName 'LogVariableDetailsEnabled') -and $varsAfter.Count -gt 0) {
                Write-ExecutionLog -Context $Context -Message "  VarsWritten:"
                foreach ($kv in $varsAfter.GetEnumerator()) {
                    $formattedValue = Format-VariableValue $kv.Value
                    Write-ExecutionLog -Context $Context -Message "    `$$($kv.Key) = $formattedValue"
                }
            }

            if ($null -ne $execOutput -and @($execOutput).Count -gt 0) {
                $formattedResult = $null
                if (Test-ExecutionLogDetailEnabled -Context $Context -FlagName 'LogResultDetailsEnabled') {
                    $formattedResult = Format-VariableValue $execOutput
                    Write-ExecutionLog -Context $Context -Message "  Result: $formattedResult"
                }

                if ($Context.ScopeStack.Count -gt 0) {
                    $Context.LastSubgraphResult = Normalize-ExecutionResultValue -Value $execOutput -TreatArraysAsSequence
                }
            }

            if (-not $execSuccess -and -not [string]::IsNullOrWhiteSpace($execError)) {
                Write-ExecutionLog -Context $Context -Message "  Error: $execError"
            }

            if ($currentNode.Type -in @('Condition', 'ForEachCondition', 'ProcessCondition', 'SwitchCondition', 'CaseCondition')) {
                Write-ExecutionLog -Context $Context -Message "  ConditionResult: $($Context.LastConditionResult)"
            }
        }

        if ($execAction -in @("CallFunction", "CallScriptBlock") -and $execJumpToNode) {
            $jumpNode = Resolve-CFGNodeValue -CFG $Context.CFG -Value $execJumpToNode
            if ($jumpNode) {
                Write-ExecutionLog -Context $Context -Message "  [JUMP] Jumping to Node $($jumpNode.Id)"
            }
            $currentNode = $jumpNode
            continue
        }

        $nextNodes = @(Get-NextNodes -CFG $Context.CFG -Node $currentNode -Context $Context)
        $currentNode = if ($nextNodes.Count -gt 0) { Resolve-CFGNodeValue -CFG $Context.CFG -Value $nextNodes[0] } else { $null }
    }
}


$script:AutoVariables = @(
    '_', 'args', 'input', 'this', 'PSItem', 'PSCmdlet',
    'MyInvocation', 'PSScriptRoot', 'PSCommandPath',
    'true', 'false', 'null', 'Error', 'Host', 'PID',
    'PWD', 'ShellId', 'StackTrace', 'switch', 'foreach',
    'Matches', 'LastExitCode', 'PSBoundParameters', 'PSDefaultParameterValues'
)

$script:DynamicInvokeCommands = @(
    'Invoke-Expression', 'iex'
)

function Push-ExecutionScope {
    param(
        [hashtable]$Context,
        [string]$ScopeType,          # "Function" | "ScriptBlock"
        [string]$ScopeName,
        [int]$ReturnNodeId,
        [int]$EndNodeId = 0
    )

    $guid = [guid]::NewGuid().ToString("N").Substring(0, 8)
    $prefix = "_sc_${guid}_"

    $scope = @{
        ScopeType    = $ScopeType
        ScopeName    = $ScopeName
        ScopePrefix  = $prefix
        ReturnNodeId = $ReturnNodeId
        EndNodeId    = $EndNodeId
        LocalVars    = @()
        Arguments    = @()
        NamedArguments = [ordered]@{}
        TargetVarName = $null
        CallerNodeId = $null
        InvocationStartOffset = $null
        InvocationEndOffset = $null
        InvocationText = $null
    }

    $Context.ScopeStack += $scope
    $Context.CurrentScopePrefix = $prefix

    $Context.CallStack += @{
        Type         = $ScopeType
        Name         = $ScopeName
        ReturnNodeId = $ReturnNodeId
    }

    Write-ExecutionLog -Context $Context -Message "  [SCOPE] Push: $ScopeType '$ScopeName' (prefix=$prefix, returnTo=$ReturnNodeId, endNode=$EndNodeId)"
}

function Add-FunctionInvokeResultRecord {
    param(
        [hashtable]$Context,
        $Scope,
        $ReturnValue
    )

    if (-not $Context -or -not $Scope) { return }
    if ([string]$Scope.ScopeType -ne 'Function') { return }
    if (-not $Scope.ReturnNodeId) { return }
    if ($null -eq $ReturnValue) { return }
    if (-not (Test-ResolvableValue $ReturnValue)) { return }
    if ($ReturnValue -isnot [string] -and
        $ReturnValue -isnot [char[]] -and
        $ReturnValue -isnot [System.Management.Automation.ScriptBlock]) { return }
    if ($null -eq $Scope.InvocationStartOffset -or $null -eq $Scope.InvocationEndOffset) { return }

    $replacement = Format-ResolvableValue $ReturnValue
    if ([string]::IsNullOrWhiteSpace([string]$replacement)) { return }

    $Context.FunctionInvokeResults += @{
        NodeId          = $Scope.CallerNodeId
        FunctionName    = $Scope.ScopeName
        StartOffset     = [int]$Scope.InvocationStartOffset
        EndOffset       = [int]$Scope.InvocationEndOffset
        OriginalText    = [string]$Scope.InvocationText
        ReplacementText = [string]$replacement
        ReturnValue     = $ReturnValue
        Timestamp       = Get-Date
    }
}

function Pop-ExecutionScope {
    param([hashtable]$Context)

    if ($Context.ScopeStack.Count -eq 0) {
        Write-ExecutionLog -Context $Context -Message "  [SCOPE] Warning: Scope stack is empty, cannot pop"
        return $null
    }

    $scope = $Context.ScopeStack[-1]

    if ($Context.ScopeStack.Count -eq 1) {
        $Context.ScopeStack = @()
    } else {
        $Context.ScopeStack = @($Context.ScopeStack[0..($Context.ScopeStack.Count - 2)])
    }

    foreach ($varName in $scope.LocalVars) {
        $fullName = $scope.ScopePrefix + $varName
        try {
            $Context.ExecContext.Runspace.SessionStateProxy.PSVariable.Remove($fullName)
        } catch {
        }
    }

    if ($Context.ScopeStack.Count -gt 0) {
        $Context.CurrentScopePrefix = $Context.ScopeStack[-1].ScopePrefix
    } else {
        $Context.CurrentScopePrefix = ""
    }

    if ($Context.CallStack.Count -gt 0) {
        if ($Context.CallStack.Count -eq 1) {
            $Context.CallStack = @()
        } else {
            $Context.CallStack = @($Context.CallStack[0..($Context.CallStack.Count - 2)])
        }
    }

    Write-ExecutionLog -Context $Context -Message "  [SCOPE] Pop: $($scope.ScopeType) '$($scope.ScopeName)' (returnTo=$($scope.ReturnNodeId))"
    return $scope
}

function Get-SubgraphLocalVars {
    param(
        [hashtable]$CFG,
        [int]$StartNodeId,
        [int]$EndNodeId
    )

    $localVars = @{}
    $visited = @{}
    $queue = [System.Collections.Generic.Queue[int]]::new()
    $queue.Enqueue($StartNodeId)

    while ($queue.Count -gt 0) {
        $nodeId = $queue.Dequeue()

        if ($visited.ContainsKey($nodeId)) { continue }
        $visited[$nodeId] = $true

        $node = $CFG.Nodes | Where-Object { $_.Id -eq $nodeId } | Select-Object -First 1
        if ($null -eq $node) { continue }
        if ($nodeId -eq $EndNodeId) { continue }

        $nodeVarsWritten = @(Get-CFGNodeVarInfos -Node $node -PropertyName 'VarsWritten')
        if ($nodeVarsWritten.Count -gt 0) {
            foreach ($varInfo in $nodeVarsWritten) {
                if ($varInfo.Scope -notin @('Global', 'Script')) {
                    $localVars[$varInfo.Name] = $true
                }
            }
        }

        $edges = $CFG.Edges | Where-Object { $_.From -eq $nodeId }
        foreach ($edge in $edges) {
            if (-not $visited.ContainsKey($edge.To)) {
                $queue.Enqueue($edge.To)
            }
        }
    }

    return @($localVars.Keys)
}

function Test-FunctionInlinePreferDirectFallback {
    param(
        [string]$FuncName,
        [hashtable]$Context
    )

    if ([string]::IsNullOrWhiteSpace($FuncName) -or -not $Context -or -not $Context.CFG -or -not $Context.FunctionSubgraphs) {
        return $false
    }
    if (-not $Context.FunctionSubgraphs.ContainsKey($FuncName)) {
        return $false
    }

    $funcStartId = [int]$Context.FunctionSubgraphs[$FuncName]
    $funcEndNode = Get-SubgraphEndNode -CFG $Context.CFG -StartType 'FuncStart' -Name $FuncName
    if (-not $funcEndNode) {
        return $false
    }

    $complexNodeTypes = @(
        'Condition', 'ForEachCondition', 'ProcessCondition', 'SwitchCondition', 'CaseCondition',
        'LoopStart', 'LoopEnd', 'ForInit', 'ForIter', 'Break', 'Continue',
        'Try', 'Catch', 'Finally'
    )

    $visited = @{}
    $queue = [System.Collections.Generic.Queue[int]]::new()
    $queue.Enqueue($funcStartId)

    while ($queue.Count -gt 0) {
        $nodeId = $queue.Dequeue()
        if ($visited.ContainsKey($nodeId)) { continue }
        $visited[$nodeId] = $true

        $node = Get-NodeById -CFG $Context.CFG -Id $nodeId
        if (-not $node) { continue }
        if ($node.Type -in $complexNodeTypes) {
            return $true
        }
        if ($node.Id -eq $funcEndNode.Id) {
            continue
        }

        foreach ($edge in @(Get-CFGOutgoingEdges -CFG $Context.CFG -FromNodeId $nodeId)) {
            if (-not $visited.ContainsKey([int]$edge.To)) {
                $queue.Enqueue([int]$edge.To)
            }
        }
    }

    return $false
}

function Convert-VariableNames {
    param(
        [string]$Code,
        [string]$ScopePrefix,
        [array]$LocalVarNames
    )

    if ([string]::IsNullOrEmpty($ScopePrefix) -or $LocalVarNames.Count -eq 0) {
        return $Code
    }

    $result = $Code

    foreach ($varName in $LocalVarNames) {
        if ($varName -in $script:AutoVariables) { continue }

        if ($varName -match '^_sc_[a-f0-9]{8}_') { continue }

        if ($varName -match '^_pipe_[a-f0-9]+$') { continue }

        $pattern = '\$' + [regex]::Escape($varName) + '(?![a-zA-Z0-9_])'
        $replacement = '$$' + $ScopePrefix + $varName
        $result = $result -replace $pattern, $replacement
    }

    return $result
}

function Test-SuspiciousVariables {
    param(
        $Node,
        [hashtable]$Context
    )

    $suspicious = @()

    $allVars = @()
    $allVars += @(Get-CFGNodeVarInfos -Node $Node -PropertyName 'VarsRead')
    $allVars += @(Get-CFGNodeVarInfos -Node $Node -PropertyName 'VarsWritten')

    foreach ($varInfo in $allVars) {
        if ($varInfo.Name -match '^_sc_[a-f0-9]{8}_') {
            $suspicious += $varInfo.Name
        }
    }

    if ($suspicious.Count -gt 0) {
        Write-ExecutionLog -Context $Context -Message "  [WARN] Suspicious variable names detected: $($suspicious -join ', ')"
    }
}


function Convert-ResolvedCommandCandidateToName {
    param($Value)

    if ($null -eq $Value) { return $null }

    if (($Value -is [System.Collections.IEnumerable]) -and -not ($Value -is [string])) {
        $parts = @()
        foreach ($item in $Value) {
            if ($null -eq $item) { continue }
            $parts += [string]$item
        }
        $text = ($parts -join '')
    } else {
        $text = [string]$Value
    }

    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    $text = $text.Trim()

    if ($text.Length -ge 2 -and $text.StartsWith("'") -and $text.EndsWith("'")) {
        return $text.Substring(1, $text.Length - 2).Replace("''", "'")
    }
    if ($text.Length -ge 2 -and $text.StartsWith('"') -and $text.EndsWith('"')) {
        return $text.Substring(1, $text.Length - 2).Replace('""', '"')
    }

    return $text
}

function Resolve-CompatibilityVariableNamePattern {
    param([string]$Pattern)

    if ([string]::IsNullOrWhiteSpace($Pattern)) { return $null }

    $names = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    try {
        foreach ($var in @(Get-Variable -ErrorAction SilentlyContinue)) {
            if ($var -and -not [string]::IsNullOrWhiteSpace([string]$var.Name)) {
                $null = $names.Add([string]$var.Name)
            }
        }
    } catch {
    }

    foreach ($compatName in @(
            'MaximumDriveCount',
            'ExecutionContext',
            'ErrorActionPreference',
            'VerbosePreference',
            'DebugPreference',
            'InformationPreference',
            'WarningPreference',
            'ConfirmPreference',
            'ProgressPreference',
            'PSHome',
            'PSEdition',
            'PSVersionTable',
            'PSCulture',
            'PSUICulture',
            'NestedPromptLevel',
            'MyInvocation',
            'ShellId',
            'Host',
            'PID',
            'HOME',
            'OFS'
        )) {
        $null = $names.Add($compatName)
    }

    $matches = @()
    foreach ($name in $names) {
        if ($name -like $Pattern) {
            $matches += $name
        }
    }

    if ($matches.Count -eq 0) { return $null }
    return @($matches | Sort-Object Length, @{ Expression = { $_ } })[0]
}

function Resolve-CompatibilityAliasName {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) { return $null }

    $map = @{
        'sc'   = 'Set-Content'
        'curl' = 'Invoke-WebRequest'
        'wget' = 'Invoke-WebRequest'
        'fc'   = 'Format-Custom'
    }

    $key = $Name.ToLowerInvariant()
    if ($map.ContainsKey($key)) {
        return [string]$map[$key]
    }

    return $null
}

function Resolve-SafeCommandNameExpressionValue {
    param(
        $Ast,
        [hashtable]$Context,
        [int]$Depth = 0
    )

    if ($null -eq $Ast -or $Depth -gt 24) {
        return [PSCustomObject]@{ Success = $false; Value = $null }
    }

    if ($Ast -is [System.Management.Automation.Language.CommandExpressionAst]) {
        return Resolve-SafeCommandNameExpressionValue -Ast $Ast.Expression -Context $Context -Depth ($Depth + 1)
    }

    if ($Ast -is [System.Management.Automation.Language.ParenExpressionAst]) {
        if ($Ast.Pipeline -and $Ast.Pipeline.PipelineElements -and $Ast.Pipeline.PipelineElements.Count -eq 1) {
            $elem = $Ast.Pipeline.PipelineElements[0]
            if ($elem -is [System.Management.Automation.Language.CommandAst]) {
                return Resolve-SafeCommandNameExpressionValue -Ast $elem -Context $Context -Depth ($Depth + 1)
            }
            if ($elem -is [System.Management.Automation.Language.CommandExpressionAst]) {
                return Resolve-SafeCommandNameExpressionValue -Ast $elem.Expression -Context $Context -Depth ($Depth + 1)
            }
            if ($elem.PSObject.Properties['Expression']) {
                return Resolve-SafeCommandNameExpressionValue -Ast $elem.Expression -Context $Context -Depth ($Depth + 1)
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

    if ($Ast -is [System.Management.Automation.Language.CommandAst]) {
        $cmdName = $Ast.GetCommandName()
        if ($cmdName -in @('Get-Variable', 'gv', 'Variable')) {
            $patternText = $null

            for ($i = 1; $i -lt $Ast.CommandElements.Count; $i++) {
                $elem = $Ast.CommandElements[$i]
                if ($elem -is [System.Management.Automation.Language.CommandParameterAst]) {
                    $paramName = [string]$elem.ParameterName
                    if ([string]::IsNullOrWhiteSpace($paramName)) { continue }
                    if (-not 'name'.StartsWith($paramName.ToLowerInvariant())) { continue }

                    $argAst = if ($elem.Argument) { $elem.Argument } elseif ($i + 1 -lt $Ast.CommandElements.Count) { $Ast.CommandElements[++$i] } else { $null }
                    if ($argAst) {
                        $argResult = Resolve-SafeCommandNameExpressionValue -Ast $argAst -Context $Context -Depth ($Depth + 1)
                        if ($argResult.Success) {
                            $patternText = [string]$argResult.Value
                            break
                        }
                    }
                    continue
                }

                $argResult = Resolve-SafeCommandNameExpressionValue -Ast $elem -Context $Context -Depth ($Depth + 1)
                if ($argResult.Success) {
                    $patternText = [string]$argResult.Value
                    break
                }
            }

            if ([string]::IsNullOrWhiteSpace($patternText)) {
                return [PSCustomObject]@{ Success = $false; Value = $null }
            }

            $resolvedName = Resolve-CompatibilityVariableNamePattern -Pattern $patternText
            if ([string]::IsNullOrWhiteSpace($resolvedName)) {
                return [PSCustomObject]@{ Success = $false; Value = $null }
            }

            $psVar = Get-Variable -Name $resolvedName -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($psVar) {
                return [PSCustomObject]@{ Success = $true; Value = $psVar }
            }

            return [PSCustomObject]@{
                Success = $true
                Value   = [PSCustomObject]@{
                    Name       = $resolvedName
                    Definition = $resolvedName
                    Value      = $null
                }
            }
        }

        return [PSCustomObject]@{ Success = $false; Value = $null }
    }

    if ($Ast -is [System.Management.Automation.Language.ArrayLiteralAst]) {
        $items = @()
        foreach ($elem in $Ast.Elements) {
            $itemResult = Resolve-SafeCommandNameExpressionValue -Ast $elem -Context $Context -Depth ($Depth + 1)
            if (-not $itemResult.Success) {
                return [PSCustomObject]@{ Success = $false; Value = $null }
            }
            $items += $itemResult.Value
        }
        return [PSCustomObject]@{ Success = $true; Value = @($items) }
    }

    if ($Ast -is [System.Management.Automation.Language.VariableExpressionAst]) {
        $varName = Resolve-VariableExpressionActualName -VariableExpressionAst $Ast -Context $Context
        if ($null -eq $varName) {
            return [PSCustomObject]@{ Success = $false; Value = $null }
        }

        $value = Get-VariableFromContext -ExecContext $Context.ExecContext -Name $varName
        if ($null -eq $value) {
            return [PSCustomObject]@{ Success = $false; Value = $null }
        }

        return [PSCustomObject]@{ Success = $true; Value = $value }
    }

    if ($Ast -is [System.Management.Automation.Language.IndexExpressionAst]) {
        $targetResult = Resolve-SafeCommandNameExpressionValue -Ast $Ast.Target -Context $Context -Depth ($Depth + 1)
        if (-not $targetResult.Success) {
            return [PSCustomObject]@{ Success = $false; Value = $null }
        }

        $indexAst = if ($Ast.Index -is [System.Management.Automation.Language.CommandExpressionAst]) {
            $Ast.Index.Expression
        } else {
            $Ast.Index
        }
        $indexResult = Resolve-SafeCommandNameExpressionValue -Ast $indexAst -Context $Context -Depth ($Depth + 1)
        if (-not $indexResult.Success) {
            return [PSCustomObject]@{ Success = $false; Value = $null }
        }

        $targetValue = $targetResult.Value
        $indexValue = $indexResult.Value
        $indexes = if ($indexValue -is [array]) { @($indexValue) } else { @($indexValue) }
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
        $op = [string]$Ast.Operator
        $leftResult = Resolve-SafeCommandNameExpressionValue -Ast $Ast.Left -Context $Context -Depth ($Depth + 1)
        $rightResult = Resolve-SafeCommandNameExpressionValue -Ast $Ast.Right -Context $Context -Depth ($Depth + 1)
        if (-not $leftResult.Success -or -not $rightResult.Success) {
            return [PSCustomObject]@{ Success = $false; Value = $null }
        }

        switch ($op) {
            'Plus' {
                $leftValue = $leftResult.Value
                $rightValue = $rightResult.Value
                if ($leftValue -is [array] -or $rightValue -is [array]) {
                    return [PSCustomObject]@{ Success = $true; Value = @(@($leftValue) + @($rightValue)) }
                }
                return [PSCustomObject]@{ Success = $true; Value = ([string]$leftValue + [string]$rightValue) }
            }
            'Join' {
                $separator = [string]$rightResult.Value
                $items = @($leftResult.Value)
                $joined = ($items | ForEach-Object { [string]$_ }) -join $separator
                return [PSCustomObject]@{ Success = $true; Value = $joined }
            }
            default {
                return [PSCustomObject]@{ Success = $false; Value = $null }
            }
        }
    }

    if ($Ast -is [System.Management.Automation.Language.ConvertExpressionAst]) {
        $childResult = Resolve-SafeCommandNameExpressionValue -Ast $Ast.Child -Context $Context -Depth ($Depth + 1)
        if (-not $childResult.Success) {
            return [PSCustomObject]@{ Success = $false; Value = $null }
        }

        $typeName = [string]$Ast.Type.TypeName.FullName
        try {
            switch ($typeName.ToLowerInvariant()) {
                'string' { return [PSCustomObject]@{ Success = $true; Value = [string]$childResult.Value } }
                'char'   { return [PSCustomObject]@{ Success = $true; Value = [char]$childResult.Value } }
                'int'    { return [PSCustomObject]@{ Success = $true; Value = [int]$childResult.Value } }
            }
        } catch {
            return [PSCustomObject]@{ Success = $false; Value = $null }
        }
    }

    if ($Ast -is [System.Management.Automation.Language.InvokeMemberExpressionAst]) {
        $targetResult = Resolve-SafeCommandNameExpressionValue -Ast $Ast.Expression -Context $Context -Depth ($Depth + 1)
        if (-not $targetResult.Success) {
            return [PSCustomObject]@{ Success = $false; Value = $null }
        }

        $memberName = if ($Ast.Member -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
            [string]$Ast.Member.Value
        } else {
            [string]$Ast.Member.Extent.Text
        }

        $argValues = @()
        $invokeArgs = if ($null -ne $Ast.Arguments) { @($Ast.Arguments) } else { @() }
        foreach ($argAst in $invokeArgs) {
            $argResult = Resolve-SafeCommandNameExpressionValue -Ast $argAst -Context $Context -Depth ($Depth + 1)
            if (-not $argResult.Success) {
                return [PSCustomObject]@{ Success = $false; Value = $null }
            }
            $argValues += $argResult.Value
        }

        $targetValue = $targetResult.Value

        try {
            switch -Regex ($memberName) {
                '^(?i:ToString)$' {
                    if ($argValues.Count -eq 0) {
                        return [PSCustomObject]@{ Success = $true; Value = [string]$targetValue.ToString() }
                    }
                }
                '^(?i:Substring)$' {
                    if ($targetValue -isnot [string]) { break }
                    if ($argValues.Count -eq 1) {
                        return [PSCustomObject]@{ Success = $true; Value = $targetValue.Substring([int]$argValues[0]) }
                    }
                    if ($argValues.Count -eq 2) {
                        return [PSCustomObject]@{ Success = $true; Value = $targetValue.Substring([int]$argValues[0], [int]$argValues[1]) }
                    }
                }
                '^(?i:Replace)$' {
                    if ($targetValue -isnot [string] -or $argValues.Count -ne 2) { break }
                    return [PSCustomObject]@{ Success = $true; Value = $targetValue.Replace([string]$argValues[0], [string]$argValues[1]) }
                }
                '^(?i:ToLower)$' {
                    if ($targetValue -isnot [string] -or $argValues.Count -ne 0) { break }
                    return [PSCustomObject]@{ Success = $true; Value = $targetValue.ToLowerInvariant() }
                }
                '^(?i:ToUpper)$' {
                    if ($targetValue -isnot [string] -or $argValues.Count -ne 0) { break }
                    return [PSCustomObject]@{ Success = $true; Value = $targetValue.ToUpperInvariant() }
                }
                '^(?i:Trim)$' {
                    if ($targetValue -isnot [string] -or $argValues.Count -ne 0) { break }
                    return [PSCustomObject]@{ Success = $true; Value = $targetValue.Trim() }
                }
            }
        } catch {
            return [PSCustomObject]@{ Success = $false; Value = $null }
        }
    }

    if ($Ast -is [System.Management.Automation.Language.MemberExpressionAst]) {
        $targetResult = Resolve-SafeCommandNameExpressionValue -Ast $Ast.Expression -Context $Context -Depth ($Depth + 1)
        if (-not $targetResult.Success) {
            return [PSCustomObject]@{ Success = $false; Value = $null }
        }

        $memberName = if ($Ast.Member -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
            [string]$Ast.Member.Value
        } else {
            [string]$Ast.Member.Extent.Text
        }
        if ([string]::IsNullOrWhiteSpace($memberName)) {
            return [PSCustomObject]@{ Success = $false; Value = $null }
        }

        $targetValue = $targetResult.Value
        try {
            switch -Regex ($memberName) {
                '^(?i:Name|Definition|Value)$' {
                    $prop = $targetValue.PSObject.Properties[$memberName]
                    if ($prop) {
                        return [PSCustomObject]@{ Success = $true; Value = $prop.Value }
                    }
                }
                '^(?i:Length|Count)$' {
                    if ($targetValue.PSObject.Properties[$memberName]) {
                        return [PSCustomObject]@{ Success = $true; Value = $targetValue.$memberName }
                    }
                }
            }
        } catch {
            return [PSCustomObject]@{ Success = $false; Value = $null }
        }
    }

    return [PSCustomObject]@{ Success = $false; Value = $null }
}

function Get-SafeCommandLookupResults {
    param(
        [string]$Name,
        [switch]$AllowWildcard
    )

    if ([string]::IsNullOrWhiteSpace($Name)) { return @() }

    $query = [string]$Name
    if (-not $AllowWildcard) {
        $query = [System.Management.Automation.WildcardPattern]::Escape($query)
    }

    try {
        return @(Get-Command -Name $query -ErrorAction SilentlyContinue)
    } catch [System.Management.Automation.WildcardPatternException] {
        return @()
    } catch {
        return @()
    }
}

function Test-TextCommandTokenLooksLiteral {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }

    $candidate = [string]$Text
    if ($candidate -in @('&', '.')) { return $false }
    if ($candidate.StartsWith('&')) { return $false }
    if ($candidate.StartsWith('.')) {
        if (-not ($candidate.StartsWith('.\') -or $candidate.StartsWith('./'))) {
            return $false
        }
    }

    foreach ($ch in @('$', '{', '}', '(', ')', '[', ']', '*', '?', '`', '"', "'")) {
        if ($candidate.Contains($ch)) {
            return $false
        }
    }

    return $true
}

function Test-CommandNameExistsInContext {
    param(
        [string]$CommandName,
        [hashtable]$Context
    )

    if ([string]::IsNullOrWhiteSpace($CommandName)) { return $false }

    $name = [string]$CommandName

    if ($Context -and $Context.CFG -and $Context.CFG.DefinedAliases -and $Context.CFG.DefinedAliases.ContainsKey($name)) {
        return $true
    }
    if ($Context -and $Context.FunctionSubgraphs -and $Context.FunctionSubgraphs.ContainsKey($name)) {
        return $true
    }
    if ($Context -and $Context.ScriptBlockSubgraphs -and $Context.ScriptBlockSubgraphs.ContainsKey($name)) {
        return $true
    }
    if ($name -in $script:DynamicInvokeCommands) {
        return $true
    }
    if ($name -match '^\[(?:System\.Management\.Automation\.)?ScriptBlock\]::Create$') {
        return $true
    }

    $compatAlias = Resolve-CompatibilityAliasName -Name $name
    if (-not [string]::IsNullOrWhiteSpace($compatAlias)) {
        return $true
    }

    return ($null -ne (@(Get-SafeCommandLookupResults -Name $name) | Select-Object -First 1))
}

function Get-ResolvedCommandHeadText {
    param(
        $CommandAst,
        [string]$ResolvedName
    )

    if ([string]::IsNullOrWhiteSpace($ResolvedName)) {
        return $ResolvedName
    }
    if ($null -eq $CommandAst) {
        return $ResolvedName
    }

    switch ([string]$CommandAst.InvocationOperator) {
        'Ampersand' { return "& $ResolvedName" }
        'Dot' { return ". $ResolvedName" }
        default { return $ResolvedName }
    }
}

function Get-CommandElementResolvedNodeText {
    param(
        [string]$NodeText,
        $CommandElementAst,
        [string]$ResolvedName,
        $CommandAst = $null
    )

    if ([string]::IsNullOrWhiteSpace($NodeText) -or $null -eq $CommandElementAst -or [string]::IsNullOrWhiteSpace($ResolvedName)) {
        return $null
    }
    if (-not $CommandElementAst.Extent) { return $null }

    $start = [int]$CommandElementAst.Extent.StartOffset
    $end = [int]$CommandElementAst.Extent.EndOffset
    if ($start -lt 0 -or $end -le $start -or $end -gt $NodeText.Length) {
        return $null
    }

    if ($null -ne $CommandAst -and $CommandAst.Extent -and $CommandAst.CommandElements -and $CommandAst.CommandElements.Count -gt 0 -and
        $CommandAst.CommandElements[0] -eq $CommandElementAst) {
        $commandStart = [int]$CommandAst.Extent.StartOffset
        if ($commandStart -ge 0 -and $commandStart -le $start -and $commandStart -le $NodeText.Length) {
            $resolvedHead = Get-ResolvedCommandHeadText -CommandAst $CommandAst -ResolvedName $ResolvedName
            return $NodeText.Substring(0, $commandStart) + $resolvedHead + $NodeText.Substring($end)
        }
    }

    return $NodeText.Substring(0, $start) + $ResolvedName + $NodeText.Substring($end)
}

function Get-CommandNamedParameterUsageInfo {
    param($CommandAst)

    $names = @()
    if ($null -eq $CommandAst -or -not $CommandAst.CommandElements) { return @() }

    for ($i = 1; $i -lt $CommandAst.CommandElements.Count; $i++) {
        $elem = $CommandAst.CommandElements[$i]
        if ($elem -is [System.Management.Automation.Language.CommandParameterAst] -and
            -not [string]::IsNullOrWhiteSpace([string]$elem.ParameterName)) {
            $names += [string]$elem.ParameterName
        }
    }

    return @($names | Select-Object -Unique)
}

function Resolve-CommandParameterNameForMetadata {
    param(
        [string]$ParameterName,
        $CandidateCommand
    )

    if ([string]::IsNullOrWhiteSpace($ParameterName) -or $null -eq $CandidateCommand -or -not $CandidateCommand.Parameters) {
        return $null
    }

    $actual = $ParameterName.ToLowerInvariant()
    $keys = @($CandidateCommand.Parameters.Keys)
    foreach ($key in $keys) {
        if ($key -ieq $actual) {
            return [string]$key
        }
    }

    $matches = @($keys | Where-Object {
            $candidate = [string]$_
            $candidate.ToLowerInvariant().StartsWith($actual)
        })
    if ($matches.Count -eq 1) {
        return [string]$matches[0]
    }

    return $null
}

function Test-CommandMetadataAcceptsPipelineInput {
    param($CandidateCommand)

    if ($null -eq $CandidateCommand -or -not $CandidateCommand.Parameters) { return $false }

    foreach ($paramMeta in $CandidateCommand.Parameters.Values) {
        foreach ($attr in @($paramMeta.Attributes)) {
            if ($attr -is [System.Management.Automation.ParameterAttribute] -and
                ($attr.ValueFromPipeline -or $attr.ValueFromPipelineByPropertyName)) {
                return $true
            }
        }
    }

    return $false
}

function Test-CommandMetadataSupportsScriptBlockArgument {
    param($CandidateCommand)

    if ($null -eq $CandidateCommand -or -not $CandidateCommand.Parameters) { return $false }

    foreach ($paramMeta in $CandidateCommand.Parameters.Values) {
        if ($paramMeta.ParameterType -eq [scriptblock] -or $paramMeta.ParameterType -eq [scriptblock[]]) {
            return $true
        }
    }

    return $false
}

function Get-WildcardPatternFitScore {
    param(
        [string]$Pattern,
        [string]$CommandName
    )

    if ([string]::IsNullOrWhiteSpace($Pattern) -or [string]::IsNullOrWhiteSpace($CommandName)) {
        return 0
    }

    $score = 0
    $patternText = $Pattern.ToLowerInvariant()
    $nameText = $CommandName.ToLowerInvariant()

    $literals = @($patternText -split '\*')
    $literalLength = 0
    foreach ($part in $literals) {
        if ($null -ne $part) {
            $literalLength += $part.Length
        }
    }

    if ($literals.Count -gt 0 -and -not [string]::IsNullOrEmpty($literals[0]) -and $nameText.StartsWith($literals[0])) {
        $score += 30
    }
    if ($literals.Count -gt 0 -and -not [string]::IsNullOrEmpty($literals[$literals.Count - 1]) -and $nameText.EndsWith($literals[$literals.Count - 1])) {
        $score += 30
    }

    $inserted = [Math]::Max(0, ($CommandName.Length - $literalLength))
    $score += [Math]::Max(0, (120 - ($inserted * 6)))
    $score += [Math]::Max(0, (60 - ($CommandName.Length * 2)))

    return [int]$score
}

function Get-CommandInvocationShapeInfo {
    param($CommandAst)

    $hasPipelineInput = $false
    if ($CommandAst -and $CommandAst.Parent -is [System.Management.Automation.Language.PipelineAst]) {
        $pipelineElements = @($CommandAst.Parent.PipelineElements)
        for ($i = 0; $i -lt $pipelineElements.Count; $i++) {
            if ($pipelineElements[$i] -eq $CommandAst) {
                $hasPipelineInput = ($i -gt 0)
                break
            }
        }
    }

    $hasScriptBlockArgument = $false
    if ($CommandAst -and $CommandAst.CommandElements) {
        for ($i = 1; $i -lt $CommandAst.CommandElements.Count; $i++) {
            if ($CommandAst.CommandElements[$i] -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
                $hasScriptBlockArgument = $true
                break
            }
        }
    }

    return [PSCustomObject]@{
        HasPipelineInput     = $hasPipelineInput
        HasScriptBlockArgument = $hasScriptBlockArgument
    }
}

function Get-GetCommandPipelinePatternInfo {
    param($FirstElementAst)

    if ($null -eq $FirstElementAst -or $FirstElementAst -isnot [System.Management.Automation.Language.ParenExpressionAst]) {
        return $null
    }
    if ($null -eq $FirstElementAst.Pipeline) { return $null }

    $pipeline = $FirstElementAst.Pipeline
    $commands = @($pipeline.PipelineElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandAst] })
    if ($commands.Count -eq 0) { return $null }

    $getCommandAst = $commands[0]
    $gcName = $getCommandAst.GetCommandName()
    if ($gcName -notin @('Get-Command', 'gcm')) {
        return $null
    }

    $patternAst = $null
    $positionals = @()
    for ($i = 1; $i -lt $getCommandAst.CommandElements.Count; $i++) {
        $elem = $getCommandAst.CommandElements[$i]
        if ($elem -is [System.Management.Automation.Language.CommandParameterAst]) {
            $paramName = [string]$elem.ParameterName
            if (-not [string]::IsNullOrWhiteSpace($paramName) -and 'name'.StartsWith($paramName.ToLowerInvariant())) {
                $argAst = $elem.Argument
                if (-not $argAst -and ($i + 1 -lt $getCommandAst.CommandElements.Count)) {
                    $i++
                    $argAst = $getCommandAst.CommandElements[$i]
                }
                $patternAst = $argAst
            }
            continue
        }

        $positionals += $elem
    }

    if (-not $patternAst -and $positionals.Count -gt 0) {
        $patternAst = $positionals[0]
    }
    if (-not $patternAst) { return $null }

    $patternText = $null
    if ($patternAst -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
        $patternText = [string]$patternAst.Value
    } elseif ($patternAst.PSObject.Properties['Value']) {
        $patternText = [string]$patternAst.Value
    }
    if ([string]::IsNullOrWhiteSpace($patternText)) {
        return [PSCustomObject]@{
            Recognized = $true
            Pattern    = $null
        }
    }

    if ($commands.Count -ge 2) {
        $selectAst = $commands[$commands.Count - 1]
        $selectName = $selectAst.GetCommandName()
        if ($selectName -notin @('Select-Object', 'select')) {
            return $null
        }

        $expandPropertyOk = $false
        for ($i = 1; $i -lt $selectAst.CommandElements.Count; $i++) {
            $elem = $selectAst.CommandElements[$i]
            if ($elem -isnot [System.Management.Automation.Language.CommandParameterAst]) { continue }

            $paramName = [string]$elem.ParameterName
            if ([string]::IsNullOrWhiteSpace($paramName)) { continue }
            if (-not 'expandproperty'.StartsWith($paramName.ToLowerInvariant())) { continue }

            $argAst = $elem.Argument
            if (-not $argAst -and ($i + 1 -lt $selectAst.CommandElements.Count)) {
                $i++
                $argAst = $selectAst.CommandElements[$i]
            }

            $argText = if ($argAst -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                [string]$argAst.Value
            } elseif ($argAst) {
                [string]$argAst.Extent.Text
            } else {
                $null
            }

            if ($argText -ieq 'Name') {
                $expandPropertyOk = $true
                break
            }
        }

        if (-not $expandPropertyOk) {
            return $null
        }
    }

    return [PSCustomObject]@{
        Recognized = $true
        Pattern    = $patternText
    }
}

function Resolve-CommandNameFromGetCommandExpression {
    param(
        $CommandAst,
        $FirstElementAst,
        [hashtable]$Context
    )

    $patternInfo = Get-GetCommandPipelinePatternInfo -FirstElementAst $FirstElementAst
    if (-not $patternInfo) {
        return [PSCustomObject]@{
            Success           = $false
            RecognizedPattern = $false
            ResolvedName      = $null
            Confidence        = 'None'
            ScoreGap          = 0
        }
    }

    if ([string]::IsNullOrWhiteSpace([string]$patternInfo.Pattern)) {
        return [PSCustomObject]@{
            Success           = $false
            RecognizedPattern = $true
            ResolvedName      = $null
            Confidence        = 'None'
            ScoreGap          = 0
        }
    }

    $pattern = [string]$patternInfo.Pattern
    $namedParams = @(Get-CommandNamedParameterUsageInfo -CommandAst $CommandAst)
    $shapeInfo = Get-CommandInvocationShapeInfo -CommandAst $CommandAst
    $rawCandidates = @(Get-SafeCommandLookupResults -Name $pattern -AllowWildcard)
    if ($rawCandidates.Count -eq 0) {
        return [PSCustomObject]@{
            Success           = $false
            RecognizedPattern = $true
            ResolvedName      = $null
            Confidence        = 'None'
            ScoreGap          = 0
        }
    }

    $scored = @()
    $seen = @{}

    foreach ($rawCandidate in $rawCandidates) {
        if ($null -eq $rawCandidate) { continue }

        $effectiveName = if ($rawCandidate.CommandType -eq [System.Management.Automation.CommandTypes]::Alias -and
            -not [string]::IsNullOrWhiteSpace([string]$rawCandidate.Definition)) {
            [string]$rawCandidate.Definition
        } else {
            [string]$rawCandidate.Name
        }

        if ([string]::IsNullOrWhiteSpace($effectiveName)) { continue }
        $dedupeKey = $effectiveName.ToLowerInvariant()
        if ($seen.ContainsKey($dedupeKey)) { continue }
        $seen[$dedupeKey] = $true

        $candidateCommand = @(Get-SafeCommandLookupResults -Name $effectiveName) | Select-Object -First 1
        if (-not $candidateCommand) { continue }

        $rejectReason = $null
        $score = 0

        foreach ($paramName in $namedParams) {
            $matchedParam = Resolve-CommandParameterNameForMetadata -ParameterName $paramName -CandidateCommand $candidateCommand
            if (-not $matchedParam) {
                $rejectReason = "missing_param:$paramName"
                break
            }
            $score += 120
        }

        if (-not $rejectReason -and $shapeInfo.HasPipelineInput) {
            if (-not (Test-CommandMetadataAcceptsPipelineInput -CandidateCommand $candidateCommand)) {
                $rejectReason = 'no_pipeline_input'
            } else {
                $score += 80
            }
        }

        if (-not $rejectReason -and $shapeInfo.HasScriptBlockArgument) {
            if (-not (Test-CommandMetadataSupportsScriptBlockArgument -CandidateCommand $candidateCommand)) {
                $rejectReason = 'no_scriptblock_param'
            } else {
                $score += 100
            }
        }

        if ($rejectReason) {
            continue
        }

        $score += Get-WildcardPatternFitScore -Pattern $pattern -CommandName $candidateCommand.Name
        if ($candidateCommand.CommandType -eq [System.Management.Automation.CommandTypes]::Cmdlet) {
            $score += 90
        } elseif ($candidateCommand.CommandType -eq [System.Management.Automation.CommandTypes]::Function) {
            $score += 15
        } else {
            $score += 10
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$candidateCommand.ModuleName) -and
            [string]$candidateCommand.ModuleName -like 'Microsoft.PowerShell.*') {
            $score += 70
        }
        if ($candidateCommand.Name -match '^[A-Za-z]+-[A-Za-z]+$') {
            $score += 20
        }

        $scored += [PSCustomObject]@{
            Name    = [string]$candidateCommand.Name
            Score   = [int]$score
            Module  = [string]$candidateCommand.ModuleName
            Type    = [string]$candidateCommand.CommandType
        }
    }

    if ($scored.Count -eq 0) {
        return [PSCustomObject]@{
            Success           = $false
            RecognizedPattern = $true
            ResolvedName      = $null
            Confidence        = 'None'
            ScoreGap          = 0
        }
    }

    $ordered = @($scored | Sort-Object @{ Expression = { -$_.Score } }, @{ Expression = { $_.Name.Length } }, Name)
    $best = $ordered[0]
    $secondScore = if ($ordered.Count -gt 1) { [int]$ordered[1].Score } else { -100000 }
    $gap = [int]($best.Score - $secondScore)
    $success = ($best.Score -ge 150 -and $gap -ge 20)

    return [PSCustomObject]@{
        Success           = $success
        RecognizedPattern = $true
        ResolvedName      = if ($success) { [string]$best.Name } else { $null }
        Confidence        = if ($success) { 'High' } else { 'Low' }
        ScoreGap          = $gap
        Pattern           = $pattern
    }
}

function Get-ResolvedCommandInfo {
    param(
        $Node,
        [hashtable]$Context,
        [hashtable]$ResolvedValues
    )

    $execInfo = Get-NodeTextExecutionInfoWithFallback -Node $Node -Context $Context -CandidateSourceTexts @([string]$Node.Text) -AllowOriginalAstFallback
    if (-not $execInfo.Success) {
        return [PSCustomObject]@{ HasCommand = $false }
    }

    $cmdAst = $execInfo.CommandAst
    if (-not $cmdAst) {
        return [PSCustomObject]@{ HasCommand = $false }
    }

    $isTopLevelInvocation = $false
    if ($execInfo.PSObject.Properties['IsTopLevelCommandInvocation']) {
        $isTopLevelInvocation = [bool]$execInfo.IsTopLevelCommandInvocation
    }

    $cmdName = $null
    $originalName = $null
    $commandElementAst = if ($cmdAst.CommandElements -and $cmdAst.CommandElements.Count -gt 0) {
        $cmdAst.CommandElements[0]
    } else {
        $null
    }
    $resolutionKind = 'Direct'
    $resolutionConfidence = 'High'
    $resolvedNodeText = $null
    $wildcardResolution = $null

    if ($cmdAst.GetCommandName) {
        $cmdName = $cmdAst.GetCommandName()
        $originalName = $cmdName
    }

    if (-not $cmdName -and $cmdAst.CommandElements -and $cmdAst.CommandElements.Count -gt 0) {
        $firstElement = $cmdAst.CommandElements[0]
        $originalName = [string]$firstElement.Extent.Text

        $safeEval = Resolve-SafeCommandNameExpressionValue -Ast $firstElement -Context $Context
        if ($safeEval.Success) {
            $candidateName = Convert-ResolvedCommandCandidateToName -Value $safeEval.Value
            if (Test-CommandNameExistsInContext -CommandName $candidateName -Context $Context) {
                $cmdName = $candidateName
                $resolutionKind = 'StaticExpression'
                $resolutionConfidence = 'High'
            }
        }

        $wildcardResolution = Resolve-CommandNameFromGetCommandExpression -CommandAst $cmdAst -FirstElementAst $firstElement -Context $Context
        $suppressExpressionFallback = ($wildcardResolution -and $wildcardResolution.RecognizedPattern)
        if ($wildcardResolution.Success) {
            $cmdName = [string]$wildcardResolution.ResolvedName
            $resolutionKind = 'WildcardPattern'
            $resolutionConfidence = [string]$wildcardResolution.Confidence
        }

        $localKey = "local:$($Node.Id):$($firstElement.Extent.StartOffset):$($firstElement.Extent.EndOffset)"
        if (-not $cmdName -and -not $suppressExpressionFallback -and $ResolvedValues -and $ResolvedValues.ContainsKey($localKey)) {
            $candidateName = Convert-ResolvedCommandCandidateToName -Value $ResolvedValues[$localKey]
            if (Test-CommandNameExistsInContext -CommandName $candidateName -Context $Context) {
                $cmdName = $candidateName
                $resolutionKind = 'EvaluatedExpression'
                $resolutionConfidence = 'High'
            }
        }

        if (-not $cmdName -and -not $suppressExpressionFallback) {
            $nameCode = Convert-CodeForCurrentScope -Code $firstElement.Extent.Text -Context $Context
            $nameEval = Invoke-InContext -ExecContext $Context.ExecContext -Code $nameCode
            if ($nameEval.Success) {
                $nameValue = Normalize-ExecutionResultValue -Value $nameEval.Result -TreatArraysAsSequence
                if ($null -ne $nameValue) {
                    $candidateName = Convert-ResolvedCommandCandidateToName -Value $nameValue
                    if (Test-CommandNameExistsInContext -CommandName $candidateName -Context $Context) {
                        $cmdName = $candidateName
                        $resolutionKind = 'EvaluatedExpression'
                        $resolutionConfidence = 'High'
                    }
                }
            }
        }

        if ($cmdName) {
            $resolvedNodeText = Get-CommandElementResolvedNodeText -NodeText ([string]$Node.Text) -CommandElementAst $firstElement -ResolvedName ([string]$cmdName) -CommandAst $cmdAst
        }
    }

    if (-not $cmdName -and $cmdAst.Extent -and $cmdAst.Extent.Text -match '^\s*([^\s\(]+)') {
        $textCandidate = [string]$Matches[1]
        if (Test-TextCommandTokenLooksLiteral -Text $textCandidate) {
            $cmdName = $textCandidate
            $originalName = $cmdName
        }
    }
    if (-not $cmdName -and $Node.Text -match '^\s*([^\s\(]+)') {
        $textCandidate = [string]$Matches[1]
        if (Test-TextCommandTokenLooksLiteral -Text $textCandidate) {
            $cmdName = $textCandidate
            $originalName = $cmdName
        }
    }

    if (-not $cmdName) {
        return [PSCustomObject]@{ HasCommand = $false }
    }

    $cmdName = [string]$cmdName

    $matchedResolvable = $null
    if ($Node.Resolvables) {
        $matchedResolvable = $Node.Resolvables |
            Where-Object { $_.Type -eq "Command" -and $_.Text -eq $cmdAst.Extent.Text } |
            Select-Object -First 1
    }

    $realName = $cmdName
    if ($Context.CFG.DefinedAliases -and $Context.CFG.DefinedAliases.ContainsKey($cmdName)) {
        $realName = $Context.CFG.DefinedAliases[$cmdName]
        return [PSCustomObject]@{
            HasCommand   = $true
            OriginalName = $cmdName
            ResolvedName = $realName
            IsAlias      = $true
            Ast          = $cmdAst
            IsTopLevelInvocation = $isTopLevelInvocation
            Resolvable   = $matchedResolvable
            ResolutionKind = 'Alias'
            ResolutionConfidence = 'High'
            CommandElementAst = $commandElementAst
            ResolvedNodeText = (Get-CommandElementResolvedNodeText -NodeText ([string]$Node.Text) -CommandElementAst $commandElementAst -ResolvedName $realName -CommandAst $cmdAst)
        }
    }

    $builtinAlias = @(Get-SafeCommandLookupResults -Name $cmdName) | Select-Object -First 1
    if ($builtinAlias -and $builtinAlias.CommandType -eq [System.Management.Automation.CommandTypes]::Alias -and
        -not [string]::IsNullOrWhiteSpace([string]$builtinAlias.Definition)) {
        $realName = [string]$builtinAlias.Definition
        return [PSCustomObject]@{
            HasCommand   = $true
            OriginalName = $cmdName
            ResolvedName = $realName
            IsAlias      = $true
            Ast          = $cmdAst
            IsTopLevelInvocation = $isTopLevelInvocation
            Resolvable   = $matchedResolvable
            ResolutionKind = 'BuiltinAlias'
            ResolutionConfidence = 'High'
            CommandElementAst = $commandElementAst
            ResolvedNodeText = (Get-CommandElementResolvedNodeText -NodeText ([string]$Node.Text) -CommandElementAst $commandElementAst -ResolvedName $realName -CommandAst $cmdAst)
        }
    }

    $compatAlias = Resolve-CompatibilityAliasName -Name $cmdName
    if (-not [string]::IsNullOrWhiteSpace($compatAlias)) {
        return [PSCustomObject]@{
            HasCommand   = $true
            OriginalName = $cmdName
            ResolvedName = $compatAlias
            IsAlias      = $true
            Ast          = $cmdAst
            IsTopLevelInvocation = $isTopLevelInvocation
            Resolvable   = $matchedResolvable
            ResolutionKind = 'CompatibilityAlias'
            ResolutionConfidence = 'High'
            CommandElementAst = $commandElementAst
            ResolvedNodeText = (Get-CommandElementResolvedNodeText -NodeText ([string]$Node.Text) -CommandElementAst $commandElementAst -ResolvedName $compatAlias -CommandAst $cmdAst)
        }
    }

    return [PSCustomObject]@{
        HasCommand   = $true
        OriginalName = if ($originalName) { $originalName } else { $cmdName }
        ResolvedName = $cmdName
        IsAlias      = $false
        Ast          = $cmdAst
        IsTopLevelInvocation = $isTopLevelInvocation
        Resolvable   = $matchedResolvable
        ResolutionKind = $resolutionKind
        ResolutionConfidence = $resolutionConfidence
        CommandElementAst = $commandElementAst
        ResolvedNodeText = $resolvedNodeText
        WildcardPatternRecognized = if ($wildcardResolution) { [bool]$wildcardResolution.RecognizedPattern } else { $false }
    }
}

function Test-CommandSafety {
    param(
        $CommandInfo,
        [hashtable]$Context
    )

    if (-not $CommandInfo.HasCommand) {
        return @{ Action = "Execute"; IsForbidden = $false }
    }

    $cmdName = $CommandInfo.ResolvedName
    $isTopLevelInvocation = $true
    if ($CommandInfo.PSObject.Properties['IsTopLevelInvocation']) {
        $isTopLevelInvocation = [bool]$CommandInfo.IsTopLevelInvocation
    }

    if ($cmdName -in $Context.ForbiddenCommands) {
        return @{
            Action      = "Block"
            IsForbidden = $true
            Reason      = "Forbidden command"
            Command     = $cmdName
        }
    }

    $hostDynamicInfo = $null
    if ($CommandInfo.Ast -is [System.Management.Automation.Language.CommandAst]) {
        $hostDynamicInfo = Get-PowerShellHostDynamicInvocationInfo -CommandAst $CommandInfo.Ast
    }

    if ($hostDynamicInfo -and (Get-CFGObjectPropertyValue -Object $hostDynamicInfo -Name 'DynamicType' -Default $null) -eq 'PowerShellCommand') {
        return @{
            Action      = "DynamicInvoke"
            IsForbidden = $false
            Target      = $cmdName
            DynamicType = 'PowerShellCommand'
        }
    }

    if ($CommandInfo.Ast -is [System.Management.Automation.Language.CommandAst]) {
        $commandText = [string]$CommandInfo.Ast.Extent.Text
        if ($cmdName -ieq 'New-Object' -and $commandText -match '(?i)(?<!\S)-(?:ComObject|Com)\b') {
            return @{
                Action      = "Block"
                IsForbidden = $true
                Reason      = "COM object blocked"
                Command     = $cmdName
            }
        }
    }

    if ($cmdName -match '\.(exe|com|bat|cmd|vbs|js|wsf|msi|hta)$') {
        return @{
            Action      = "Block"
            IsForbidden = $true
            Reason      = "External executable blocked"
            Command     = $cmdName
        }
    }

    if ($cmdName -in $script:DynamicInvokeCommands) {
        return @{
            Action      = "DynamicInvoke"
            IsForbidden = $false
            Target      = $cmdName
        }
    }

    if ($CommandInfo.Ast -is [System.Management.Automation.Language.CommandAst]) {
        $wrappedDynamic = Get-CommandAstWrappedDynamicInvocationInfo -CommandAst $CommandInfo.Ast -Context $Context
        if ($wrappedDynamic.Success) {
            return @{
                Action      = "DynamicInvoke"
                IsForbidden = $false
                Target      = $wrappedDynamic.EffectiveCommand
                DynamicType = (Get-CFGObjectPropertyValue -Object $wrappedDynamic -Name 'DynamicType' -Default $null)
            }
        }
    }

    if ($cmdName -match '^\[(?:System\.Management\.Automation\.)?ScriptBlock\]::Create$') {
        return @{
            Action      = "DynamicInvoke"
            IsForbidden = $false
            Target      = $cmdName
            DynamicType = "ScriptBlockCreate"
        }
    }

    if ($Context.FunctionSubgraphs.ContainsKey($cmdName)) {
        if (-not $isTopLevelInvocation) {
            return @{ Action = "Execute"; IsForbidden = $false }
        }
        return @{
            Action      = "CallFunction"
            IsForbidden = $false
            Target      = $cmdName
        }
    }

    if ($cmdName -in @('ForEach-Object', 'ForEach', '%')) {
        return @{
            Action      = "ForEachObject"
            IsForbidden = $false
            Target      = $cmdName
        }
    }

    if ($cmdName -in @('Where-Object', 'Where', '?')) {
        return @{
            Action      = "WhereObject"
            IsForbidden = $false
            Target      = $cmdName
        }
    }

    if ($cmdName -in @('Select-Object', 'Select')) {
        return @{
            Action      = "SelectObject"
            IsForbidden = $false
            Target      = $cmdName
        }
    }

    if ($cmdName -match '^_block_[a-f0-9]{8}$') {
        return @{
            Action      = "CallScriptBlock"
            IsForbidden = $false
            Target      = $cmdName
        }
    }

    if ($Context.ScriptBlockSubgraphs.ContainsKey($cmdName)) {
        return @{
            Action      = "CallScriptBlock"
            IsForbidden = $false
            Target      = $cmdName
        }
    }

    return @{ Action = "Execute"; IsForbidden = $false }
}

function Test-DangerousMethodCall {
    param(
        $Node,
        [hashtable]$Context
    )

    if (-not $Node.Ast) {
        return @{ IsDangerous = $false }
    }

    $dangerousPatterns = @(
        @{ Type = 'System.IO.File'; Methods = @('Delete') },
        @{ Type = 'System.IO.Directory'; Methods = @('Delete') },
        @{ Type = 'System.IO.FileInfo'; Methods = @('Delete') },
        @{ Type = 'System.IO.DirectoryInfo'; Methods = @('Delete') },

        @{ Type = 'System.IO.File'; Methods = @('Move') },
        @{ Type = 'System.IO.Directory'; Methods = @('Move') },
        @{ Type = 'System.IO.FileInfo'; Methods = @('MoveTo') },
        @{ Type = 'System.IO.DirectoryInfo'; Methods = @('MoveTo') },

        @{ Type = 'System.Net.WebClient'; Methods = @(
            'DownloadFile', 'DownloadFileAsync',
            'DownloadData', 'DownloadDataAsync',
            'DownloadString', 'DownloadStringAsync',
            'UploadFile', 'UploadFileAsync',
            'UploadData', 'UploadDataAsync',
            'UploadString', 'UploadStringAsync',
            'UploadValues', 'UploadValuesAsync',
            'OpenRead', 'OpenReadAsync',
            'OpenWrite', 'OpenWriteAsync'
        )},
        @{ Type = 'System.Net.HttpWebRequest'; Methods = @(
            'GetResponse', 'GetResponseAsync',
            'GetRequestStream', 'GetRequestStreamAsync'
        )},
        @{ Type = 'System.Net.HttpWebResponse'; Methods = @('GetResponseStream') },
        @{ Type = 'System.Net.Sockets.TcpClient'; Methods = @('Connect', 'ConnectAsync', 'GetStream') },
        @{ Type = 'System.Net.Sockets.TcpListener'; Methods = @(
            'Start', 'AcceptTcpClient', 'AcceptTcpClientAsync',
            'AcceptSocket', 'AcceptSocketAsync'
        )},
        @{ Type = 'System.Net.Sockets.Socket'; Methods = @(
            'Connect', 'ConnectAsync',
            'Send', 'SendAsync', 'SendTo', 'SendToAsync',
            'Receive', 'ReceiveAsync', 'ReceiveFrom', 'ReceiveFromAsync',
            'Bind', 'Listen', 'Accept', 'AcceptAsync'
        )},
        @{ Type = 'System.Net.Sockets.UdpClient'; Methods = @(
            'Connect', 'Send', 'SendAsync', 'Receive', 'ReceiveAsync'
        )},
        @{ Type = 'System.Net.Dns'; Methods = @(
            'GetHostEntry', 'GetHostEntryAsync',
            'GetHostAddresses', 'GetHostAddressesAsync'
        )},
        @{ Type = 'System.Net.Mail.SmtpClient'; Methods = @('Send', 'SendAsync') },

        @{ Type = 'System.Diagnostics.Process'; Methods = @('Start', 'WaitForExit', 'WaitForExitAsync') },

        @{ Type = 'System.IO.Compression.ZipFile'; Methods = @('ExtractToDirectory') },
        @{ Type = 'System.Windows.Forms.Form'; Methods = @('ShowDialog') },

        @{ Type = 'System.Threading.Thread'; Methods = @('Sleep', 'Join') },

        @{ Type = 'System.Threading.Tasks.Task'; Methods = @('Wait', 'WaitAll', 'WaitAny') }
    )

    $methodCalls = @($Node.Ast.FindAll({
        param($n)
        $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst]
    }, $true))

    foreach ($methodCall in $methodCalls) {
        $memberName = $null
        if ($methodCall.Member -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
            $memberName = $methodCall.Member.Value
        }

        if (-not $memberName) { continue }

        $isStaticMethodCall = ($methodCall.Expression -is [System.Management.Automation.Language.TypeExpressionAst])
        if ($isStaticMethodCall) {
            $typeName = $methodCall.Expression.TypeName.FullName

            foreach ($pattern in $dangerousPatterns) {
                if ($typeName -like "*$($pattern.Type)" -and $memberName -in $pattern.Methods) {
                    return @{
                        IsDangerous = $true
                        Reason = "Dangerous .NET static method call"
                        Type = $typeName
                        Method = $memberName
                        FullCall = $methodCall.Extent.Text
                    }
                }
            }

            continue
        }

        $dangerousInstanceMethods = @(
            'Delete', 'MoveTo',
            'DownloadFile', 'DownloadData', 'DownloadString',
            'UploadFile', 'UploadData', 'UploadString',
            'Connect', 'Send', 'Receive', 'GetStream',
            'Start', 'WaitForExit',
            'Sleep', 'Join', 'Wait',
            'ShellExecute', 'Popup', 'ShowDialog', 'ExtractToDirectory'
        )

        if ($memberName -in $dangerousInstanceMethods) {
            $objType = $null
            if ($methodCall.Expression -is [System.Management.Automation.Language.VariableExpressionAst]) {
                $varName = $methodCall.Expression.VariablePath.UserPath
                try {
                    $varValue = Get-VariableFromContext -ExecContext $Context.ExecContext -Name $varName
                    if ($null -ne $varValue) {
                        $objType = $varValue.GetType().FullName
                    }
                } catch {
                }
            }

            if ($objType) {
                foreach ($pattern in $dangerousPatterns) {
                    if ($objType -like "*$($pattern.Type)" -and $memberName -in $pattern.Methods) {
                        return @{
                            IsDangerous = $true
                            Reason = "Dangerous .NET instance method call"
                            Type = $objType
                            Method = $memberName
                            FullCall = $methodCall.Extent.Text
                        }
                    }
                }
            } else {
                return @{
                    IsDangerous = $true
                    Reason = "Potentially dangerous method call (type unknown)"
                    Type = "Unknown"
                    Method = $memberName
                    FullCall = $methodCall.Extent.Text
                }
            }
        }
    }

    return @{ IsDangerous = $false }
}

function Resolve-NonCommandExpressions {
    param(
        $Node,
        [hashtable]$Context
    )

    $resolvedValues = @{}

    $skipEvalTypes = @('Command', 'Unary')

    $resolved = Get-NodeTextResolvables -Node $Node -Context $Context
    if (-not $resolved.Success) {
        Write-ExecutionLog -Context $Context -Message "  [RESOLVE] Parse Node.Text failed at Node $($Node.Id): $($resolved.Error)"
        return $resolvedValues
    }

    foreach ($resolvable in $resolved.Items) {
        if ($resolvable.Type -in $skipEvalTypes) {
            continue
        }

        if ($resolvable.Ast -and (Test-ResolvableAstHasImplicitSideEffects -Ast $resolvable.Ast)) {
            continue
        }

        if ($resolvable.Ast -and (Test-AstDependsOnBlockedTaint -Ast $resolvable.Ast -Context $Context)) {
            continue
        }

        $code = $resolvable.Text

        $code = Convert-CodeForCurrentScope -Code $code -Context $Context

        $evalResult = Invoke-InContext -ExecContext $Context.ExecContext -Code $code

        if ($evalResult.Success) {
            if (-not (Test-ResolvableValue $evalResult.Result)) {
                continue
            }

            $value = Format-ResolvableValue $evalResult.Result

            $localKey = "local:$($Node.Id):$($resolvable.LocalStartOffset):$($resolvable.LocalEndOffset)"
            $resolvedValues[$localKey] = $value

            if ($resolvable.Mapped -and $null -ne $resolvable.StartOffset -and $null -ne $resolvable.EndOffset) {
                $key = "$($Node.Id):$($resolvable.StartOffset):$($resolvable.EndOffset)"
                if (-not $Context.ResolvableResults.ContainsKey($key)) {
                    $Context.ResolvableResults[$key] = @{
                        NodeId     = $Node.Id
                        Resolvable = $resolvable
                        Values     = @()
                    }
                }
                $Context.ResolvableResults[$key].Values += $value
                $resolvedValues[$key] = $value
            }
        }
    }

    return $resolvedValues
}

function Get-ScriptBlockCallInfo {
    param(
        $Node,
        [hashtable]$Context
    )

    $knownBlockNames = @()
    if ($Node.Invokes -and $Node.Invokes.ScriptBlocks) {
        $knownBlockNames = @($Node.Invokes.ScriptBlocks)
    }

    $invokeAst = $null
    if ($Node.Ast -is [System.Management.Automation.Language.CommandExpressionAst]) {
        $expr = $Node.Ast.Expression
        if ($expr -is [System.Management.Automation.Language.InvokeMemberExpressionAst]) {
            $invokeAst = $expr
        }
    } elseif ($Node.Ast -is [System.Management.Automation.Language.InvokeMemberExpressionAst]) {
        $invokeAst = $Node.Ast
    }
    if (-not $invokeAst -and $Node.Ast -is [System.Management.Automation.Language.AssignmentStatementAst]) {
        $pipeline = $Node.Ast.Right
        if ($pipeline -is [System.Management.Automation.Language.PipelineAst] -and $pipeline.PipelineElements.Count -gt 0) {
            $pipeElem = $pipeline.PipelineElements[0]
            if ($pipeElem -is [System.Management.Automation.Language.CommandExpressionAst] -and
                $pipeElem.Expression -is [System.Management.Automation.Language.InvokeMemberExpressionAst]) {
                $invokeAst = $pipeElem.Expression
            }
        }
    }

    if ($invokeAst -and $invokeAst.Member -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
        $invokeAst.Member.Value -eq 'Invoke') {
        return Get-InvokeMemberCallInfo -InvokeAst $invokeAst -Context $Context -KnownBlockNames $knownBlockNames
    }

    $cmdAst = $null
    if ($Node.Ast -is [System.Management.Automation.Language.AssignmentStatementAst]) {
        $pipeline = $Node.Ast.Right
        if ($pipeline -is [System.Management.Automation.Language.PipelineAst] -and $pipeline.PipelineElements.Count -gt 0) {
            $pipeElem = $pipeline.PipelineElements[0]
            if ($pipeElem -is [System.Management.Automation.Language.CommandAst]) {
                $cmdAst = $pipeElem
            }
        }
    } elseif ($Node.Ast -is [System.Management.Automation.Language.CommandAst]) {
        $cmdAst = $Node.Ast
    }

    if (-not $cmdAst) {
        return $null
    }

    $cmdName = $cmdAst.GetCommandName()
    if ($cmdName -in @('Invoke-Command', 'icm')) {
        return Get-InvokeCommandCallInfo -CmdAst $cmdAst -Context $Context -KnownBlockNames $knownBlockNames
    }

    if ($cmdAst.InvocationOperator -in @([System.Management.Automation.Language.TokenKind]::Ampersand,
                                          [System.Management.Automation.Language.TokenKind]::Dot)) {
        return Get-AmpersandDotCallInfo -CmdAst $cmdAst -Context $Context -KnownBlockNames $knownBlockNames
    }

    return $null
}

function Get-InvokeMemberCallInfo {
    param(
        $InvokeAst,
        [hashtable]$Context,
        [array]$KnownBlockNames = @()
    )

    $targetExpr = $InvokeAst.Expression
    $blockName = Get-ScriptBlockNameFromAst -Ast $targetExpr -Context $Context -KnownBlockNames $KnownBlockNames

    if (-not $blockName) {
        return $null
    }

    return @{
        BlockName = $blockName
        Arguments = $null
        CallType  = "InvokeMethod"
    }
}

function Get-InvokeCommandCallInfo {
    param(
        $CmdAst,
        [hashtable]$Context,
        [array]$KnownBlockNames = @()
    )

    $blockName = $null
    $arguments = $null

    $i = 1
    while ($i -lt $CmdAst.CommandElements.Count) {
        $elem = $CmdAst.CommandElements[$i]

        if ($elem -is [System.Management.Automation.Language.CommandParameterAst]) {
            $paramName = $elem.ParameterName

            if ($paramName -in @('ScriptBlock', 'sb')) {
                if ($elem.Argument) {
                    $blockName = Get-ScriptBlockNameFromAst -Ast $elem.Argument -Context $Context -KnownBlockNames $KnownBlockNames
                } elseif ($i + 1 -lt $CmdAst.CommandElements.Count) {
                    $i++
                    $blockName = Get-ScriptBlockNameFromAst -Ast $CmdAst.CommandElements[$i] -Context $Context -KnownBlockNames $KnownBlockNames
                }
            }
            elseif ($paramName -in @('ArgumentList', 'Args')) { }
        }
        $i++
    }

    if ($blockName) {
        return @{
            BlockName = $blockName
            Arguments = $arguments
            CallType  = "InvokeCommand"
        }
    }

    return $null
}

function Get-AmpersandDotCallInfo {
    param(
        $CmdAst,
        [hashtable]$Context,
        [array]$KnownBlockNames = @()
    )

    if (-not $CmdAst.CommandElements -or $CmdAst.CommandElements.Count -lt 1) {
        return $null
    }

    $firstElement = $CmdAst.CommandElements[0]
    $blockName = Get-ScriptBlockNameFromAst -Ast $firstElement -Context $Context -KnownBlockNames $KnownBlockNames

    if (-not $blockName) {
        return $null
    }

    $callType = if ($CmdAst.InvocationOperator -eq [System.Management.Automation.Language.TokenKind]::Dot) {
        "Dot"
    } else {
        "Ampersand"
    }

    return @{
        BlockName = $blockName
        Arguments = $null
        CallType  = $callType
    }
}

function Get-ScriptBlockNameFromAst {
    param(
        $Ast,
        [hashtable]$Context,
        [array]$KnownBlockNames = @()
    )

    if ($Ast -is [System.Management.Automation.Language.VariableExpressionAst]) {
        $varName = $Ast.VariablePath.UserPath

        if ($Context.ScriptBlockSubgraphs.ContainsKey($varName)) {
            return $varName
        }

        if ($Context.VarToBlockMapping -and $Context.VarToBlockMapping.ContainsKey($varName)) {
            return $Context.VarToBlockMapping[$varName]
        }

        $actualVarName = $varName
        if ($Context.ScopeStack.Count -gt 0) {
            $currentScope = $Context.ScopeStack[-1]
            if ($currentScope.LocalVars -and $varName -in $currentScope.LocalVars) {
                $actualVarName = $currentScope.ScopePrefix + $varName
            }
        }

        $varValue = Get-VariableFromContext -ExecContext $Context.ExecContext -Name $actualVarName
        if ($varValue -is [scriptblock]) {
            $sbText = $varValue.ToString().Trim()
            foreach ($blockName in $Context.ScriptBlockSubgraphs.Keys) {
                $blockStartId = $Context.ScriptBlockSubgraphs[$blockName]
                $blockStartNode = Get-NodeById -CFG $Context.CFG -Id $blockStartId
                if ($blockStartNode.ScriptBlockText) {
                    $blockText = $blockStartNode.ScriptBlockText.Trim()
                    if ($blockText.StartsWith('{') -and $blockText.EndsWith('}')) {
                        $blockText = $blockText.Substring(1, $blockText.Length - 2).Trim()
                    }
                    if ($sbText -eq $blockText) {
                        return $blockName
                    }
                }
            }
        }
    }
    elseif ($Ast -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
        if ($KnownBlockNames.Count -gt 0) {
            foreach ($name in $KnownBlockNames) {
                if ($Context.ScriptBlockSubgraphs.ContainsKey($name)) {
                    return $name
                }
            }
        }

        $sbText = $Ast.ScriptBlock.Extent.Text.Trim()
        foreach ($blockName in $Context.ScriptBlockSubgraphs.Keys) {
            $blockStartId = $Context.ScriptBlockSubgraphs[$blockName]
            $blockStartNode = Get-NodeById -CFG $Context.CFG -Id $blockStartId
            if ($blockStartNode.ScriptBlockText) {
                $blockText = $blockStartNode.ScriptBlockText.Trim()
                if ($sbText -eq $blockText) {
                    return $blockName
                }
            }
        }
    }

    return $null
}

function Get-ArgumentListValues {
    param(
        $Ast,
        [hashtable]$Context
    )

    $values = @()

    if ($Ast -is [System.Management.Automation.Language.ArrayLiteralAst]) {
        foreach ($elem in $Ast.Elements) {
            $values += Get-AstValue -Ast $elem -Context $Context
        }
    }
    elseif ($Ast -is [System.Management.Automation.Language.ArrayExpressionAst]) {
        if ($Ast.SubExpression -and $Ast.SubExpression.Statements) {
            foreach ($stmt in $Ast.SubExpression.Statements) {
                if ($stmt.PipelineElements -and $stmt.PipelineElements.Count -gt 0) {
                    $expr = $stmt.PipelineElements[0].Expression
                    if ($expr -is [System.Management.Automation.Language.ArrayLiteralAst]) {
                        foreach ($elem in $expr.Elements) {
                            $values += Get-AstValue -Ast $elem -Context $Context
                        }
                    } else {
                        $values += Get-AstValue -Ast $expr -Context $Context
                    }
                }
            }
        }
    }
    else {
        $values += Get-AstValue -Ast $Ast -Context $Context
    }

    return $values
}

function Get-AstValue {
    param(
        $Ast,
        [hashtable]$Context
    )

    $code = $Ast.Extent.Text

    if ($Context.ScopeStack.Count -gt 0) {
        $currentScope = $Context.ScopeStack[-1]
        if ($currentScope.LocalVars -and $currentScope.LocalVars.Count -gt 0) {
            $code = Convert-VariableNames -Code $code -ScopePrefix $currentScope.ScopePrefix -LocalVarNames $currentScope.LocalVars
        }
    }

    $evalResult = Invoke-InContext -ExecContext $Context.ExecContext -Code $code
    if ($evalResult.Success) {
        return (Normalize-ExecutionResultValue -Value $evalResult.Result -TreatArraysAsSequence)
    }

    return $null
}

function Record-CommandNameResolution {
    param(
        $Node,
        [hashtable]$Context,
        $CommandInfo
    )

    #

    $cmdNameElement = $null
    $manualStartOffset = $null
    $manualEndOffset = $null

    if ($CommandInfo.Resolvable -and $CommandInfo.Resolvable.Ast -and
        ($CommandInfo.Resolvable.Ast -is [System.Management.Automation.Language.CommandAst])) {
        $origCmdAst = $CommandInfo.Resolvable.Ast
        if ($origCmdAst.CommandElements -and $origCmdAst.CommandElements.Count -gt 0) {
            $cmdNameElement = $origCmdAst.CommandElements[0]
        }
    }

    if (-not $cmdNameElement -and $Node -and $Node.Ast) {
        $cmdAsts = @($Node.Ast.FindAll({
            param($n)
            if (-not ($n -is [System.Management.Automation.Language.CommandAst])) { return $false }

            $ancestor = $n.Parent
            while ($null -ne $ancestor -and $ancestor -ne $Node.Ast) {
                if ($ancestor -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
                    return $false
                }
                $ancestor = $ancestor.Parent
            }
            return $true
        }, $true))

        if ($cmdAsts.Count -gt 0) {
            $matched = @()
            foreach ($c in $cmdAsts) {
                $name = $c.GetCommandName()
                $firstText = if ($c.CommandElements -and $c.CommandElements.Count -gt 0 -and $c.CommandElements[0].Extent) {
                    [string]$c.CommandElements[0].Extent.Text
                } else {
                    $null
                }

                if (($name -and $name -eq $CommandInfo.OriginalName) -or
                    ((-not $name) -and -not [string]::IsNullOrWhiteSpace($firstText) -and $firstText -eq [string]$CommandInfo.OriginalName)) {
                    $matched += $c
                }
            }

            if ($matched.Count -gt 0) {
                $chosen = @($matched | Sort-Object { $_.Extent.StartOffset } | Select-Object -First 1)
                if ($chosen -and $chosen.CommandElements -and $chosen.CommandElements.Count -gt 0) {
                    $cmdNameElement = $chosen.CommandElements[0]
                }
            }
        }
    }

    if (-not $cmdNameElement -and $CommandInfo -and $CommandInfo.PSObject.Properties['CommandElementAst'] -and $CommandInfo.CommandElementAst -and $CommandInfo.CommandElementAst.Extent) {
        $cmdNameElement = $CommandInfo.CommandElementAst
        if ($Node -and $Node.PSObject.Properties['TextStartOffset'] -and $null -ne $Node.TextStartOffset) {
            $manualStartOffset = [int]$Node.TextStartOffset + [int]$CommandInfo.CommandElementAst.Extent.StartOffset
            $manualEndOffset = [int]$Node.TextStartOffset + [int]$CommandInfo.CommandElementAst.Extent.EndOffset
        }
    }

    if (-not $cmdNameElement -or -not $cmdNameElement.Extent) {
        Write-ExecutionLog -Context $Context -Message "  [ALIAS] Cannot record alias resolution: no original position info"
        return
    }

    $startOffset = if ($null -ne $manualStartOffset) { $manualStartOffset } else { $cmdNameElement.Extent.StartOffset }
    $endOffset = if ($null -ne $manualEndOffset) { $manualEndOffset } else { $cmdNameElement.Extent.EndOffset }

    $key = "$($Node.Id):${startOffset}:${endOffset}"

    $resolutionKind = if ($CommandInfo.PSObject.Properties['ResolutionKind']) {
        [string]$CommandInfo.ResolutionKind
    } else {
        if ($CommandInfo.IsAlias) { 'Alias' } else { 'CommandName' }
    }

    $commandResolvable = @{
        Type        = "CommandName"
        Text        = $CommandInfo.OriginalName
        StartOffset = $startOffset
        EndOffset   = $endOffset
        Depth       = 0
        Ast         = $cmdNameElement
        AliasName   = $CommandInfo.OriginalName
        TargetName  = $CommandInfo.ResolvedName
        ResolutionKind = $resolutionKind
    }

    if (-not $Context.ResolvableResults.ContainsKey($key)) {
        $Context.ResolvableResults[$key] = @{
            NodeId     = $Node.Id
            Resolvable = $commandResolvable
            Values     = @()
        }
    }

    $Context.ResolvableResults[$key].Values += $CommandInfo.ResolvedName

    Write-ExecutionLog -Context $Context -Message "  [CMDNAME] Recorded ($resolutionKind): $($CommandInfo.OriginalName) -> $($CommandInfo.ResolvedName)"
}

function Record-AliasResolution {
    param(
        $Node,
        [hashtable]$Context,
        $CommandInfo
    )

    Record-CommandNameResolution -Node $Node -Context $Context -CommandInfo $CommandInfo
}

function Initialize-SubgraphMappings {
    param(
        [hashtable]$CFG,
        [hashtable]$Context
    )

    foreach ($node in $CFG.Nodes) {
        if ($node.Type -eq "FuncStart") {
            if ($node.Text -match '^function\s+(.+)$') {
                $funcName = $Matches[1]
                $Context.FunctionSubgraphs[$funcName] = $node.Id
                Write-ExecutionLog -Context $Context -Message "  [INIT] Function subgraph: $funcName -> Node $($node.Id)"
            }
        }
        elseif ($node.Type -eq "BlockStart") {
            if ($node.Text -match '^ScriptBlock\s+(.+)$') {
                $blockName = $Matches[1]
                $Context.ScriptBlockSubgraphs[$blockName] = $node.Id
                Write-ExecutionLog -Context $Context -Message "  [INIT] ScriptBlock subgraph: $blockName -> Node $($node.Id)"
            }
        }
    }

    Write-ExecutionLog -Context $Context -Message "  [INIT] Total functions: $($Context.FunctionSubgraphs.Count), ScriptBlocks: $($Context.ScriptBlockSubgraphs.Count)"
}

function Invoke-CFGTraversal {
    param(
        [Parameter(Mandatory)]
        [hashtable]$CFG,
        [string]$LogPath = "execution.log",
        [int]$MaxIterations = 1000,
        [int]$MaxTotalNodes = 50000,
        [int]$GlobalTimeBudgetMs = 0,
        [int]$DynamicTimeBudgetMs = 60000,
        [bool]$SafeMode = $true
    )

    Initialize-ExecutionLogFile -LogPath $LogPath

    $execContext = New-ExecutionContext

    $context = @{
        CFG                 = $CFG
        ExecContext         = $execContext
        LogPath             = $LogPath
        HostInfo            = Get-PowerShellHostInfo
        VisitedNodes        = @{}
        MaxIterations       = $MaxIterations
        MaxTotalNodes       = $MaxTotalNodes
        GlobalTimeBudgetMs  = $GlobalTimeBudgetMs
        DynamicTimeBudgetMs = $DynamicTimeBudgetMs
        SafeMode            = $SafeMode
        PreExecutionGateMode = 'Balanced'
        PreExecutionGateCache = @{}
        DynamicDepthLimit    = $null
        TotalVisits         = 0
        StopReason          = $null
        LastConditionResult = $true
        ResolvableResults   = @{}  # Key: "NodeId:StartOffset:EndOffset", Value: @{ NodeId, Resolvable, Values }
        VariableReadResults = @{}  # Key: "StartOffset:EndOffset", Value: @{ VarInfo; Values }
        LiteralizedCommandResults = @()
        SensitiveSinkResults = @()
        BlockedTaintedVariables = @{}
        TrackedEnvironmentVariables = @{}

        ScopeStack            = @()
        CurrentScopePrefix    = ""
        ForbiddenCommands     = @(
            'Remove-Item', 'del', 'rm', 'rmdir', 'rd', 'ri', 'erase',
            'Clear-Content', 'clc',
            'Clear-ItemProperty', 'clp',
            'Remove-ItemProperty', 'rp',
            'Clear-RecycleBin',

            'Move-Item', 'move', 'mv', 'mi',
            'Rename-Item', 'ren', 'rni',

            'Invoke-WebRequest', 'iwr', 'curl', 'wget',
            'Invoke-RestMethod', 'irm',
            'Start-BitsTransfer',
            'Add-BitsFile',
            'Complete-BitsTransfer',
            'Test-NetConnection',
            'Test-Connection', 'ping',
            'Send-MailMessage',

            'Start-Process', 'start', 'saps',
            'Wait-Process',
            'Debug-Process',

            'Stop-Computer',
            'Restart-Computer',
            'Suspend-Computer',
            'Checkpoint-Computer',
            'Restore-Computer',

            'Invoke-Command', 'icm',
            'Enter-PSSession',
            'New-PSSession',
            'Enable-PSRemoting',
            'Disable-PSRemoting',
            'Enable-PSSessionConfiguration',
            'Register-PSSessionConfiguration',

            'Read-Host',
            'Get-Credential',
            'Out-GridView',

            'Wait-Event',
            'Wait-Job',

            'Format-Volume',
            'Clear-Disk',
            'Initialize-Disk',
            'Set-Disk',
            'Remove-Partition',
            'Optimize-Volume',
            'Expand-Archive',
            'Compress-Archive',

            'Out-Printer',
            'Start-Transcript',
            'Stop-Transcript'
        )
        FunctionSubgraphs     = @{}
        ScriptBlockSubgraphs  = @{}
        VarToBlockMapping     = @{}
        RuntimeSubgraphs      = @{}
        RuntimeSubgraphOrder  = @()
        CallStack             = @()
        MaxCallDepth          = 100
        DynamicInvokeResults  = @()
        FunctionInvokeResults = @()
        LastSubgraphResult    = $null
        PipelineCurrentStack  = @()
        OutputCaptureStack    = @()
        LastPipelineFlowControl = $null
        TextParseCache            = @{}
        TextParseCacheKeyByNodeId = @{}
        TextParseErrors           = @()
        LogArgumentDetailsEnabled = $true
        LogBindingDetailsEnabled  = $true
        LogVariableDetailsEnabled = $true
        LogResultDetailsEnabled   = $true
        LogBufferBuilder          = [System.Text.StringBuilder]::new()
        LogBufferedLines          = 0
        LogBufferedBytes          = 0
        LogFlushLineThreshold     = 100
        LogFlushByteThreshold     = 16384
        ExecutionStopwatch        = [System.Diagnostics.Stopwatch]::StartNew()
        DynamicBudgetStopwatch    = [System.Diagnostics.Stopwatch]::new()
    }
    $context.ExecContext.GlobalTimeBudgetMs = $GlobalTimeBudgetMs
    $context.ExecContext.ExecutionStopwatch = $context.ExecutionStopwatch

    Ensure-CFGExecutionNodeShapes -CFG $CFG
    Write-ExecutionLog -Context $context -Message "=== CFG 执行开始 ==="
    $hostDisplay = Format-PowerShellHostInfo -HostInfo $context.HostInfo
    Write-ExecutionLog -Context $context -Message "Host: $hostDisplay"
    if ($context.HostInfo -and $context.HostInfo.ExecutablePath) {
        Write-ExecutionLog -Context $context -Message "HostExe: $($context.HostInfo.ExecutablePath)"
    }
    Write-ExecutionLog -Context $context -Message "MaxIterations: $MaxIterations, MaxTotalNodes: $MaxTotalNodes"
    if ($GlobalTimeBudgetMs -gt 0 -or $DynamicTimeBudgetMs -gt 0) {
        Write-ExecutionLog -Context $context -Message "TimeBudget: Global=${GlobalTimeBudgetMs}ms, Dynamic=${DynamicTimeBudgetMs}ms"
    }
    Write-ExecutionLog -Context $context -Message "SafeMode: $SafeMode"
    Write-ExecutionLog -Context $context -Message ""

    Write-ExecutionLog -Context $context -Message "=== 初始化子图映射 ==="
    Initialize-SubgraphMappings -CFG $CFG -Context $context
    $null = Ensure-CFGExecutionIndexes -CFG $CFG
    Write-ExecutionLog -Context $context -Message ""

    try {
        $startNode = Get-CFGFirstNodeByType -CFG $CFG -Type "Start"

        if ($null -eq $startNode) {
            Write-ExecutionLog -Context $context -Message "!!! 未找到 Start 节点 !!!"
            return $context
        }

        Invoke-NodeTraverse -Node $startNode -Context $context
    }
    finally {
        Write-ExecutionLog -Context $context -Message ""
        Write-ExecutionLog -Context $context -Message "=== 执行统计 ==="
        Write-ExecutionLog -Context $context -Message "Total visits: $($context.TotalVisits)"
        Write-ExecutionLog -Context $context -Message "Unique nodes: $($context.VisitedNodes.Count)"
        if ($context.StopReason) {
            Write-ExecutionLog -Context $context -Message "StopReason: $($context.StopReason)"
        }
        Flush-ExecutionLogBuffer -Context $context

        Close-ExecutionContext -ExecContext $execContext
    }

    return $context
}


function New-CFGExecutionSession {
    param(
        [Parameter(Mandatory)]
        [hashtable]$CFG,
        [string]$LogPath = "execution.log",
        [int]$MaxIterations = 1000,
        [int]$MaxTotalNodes = 50000,
        [int]$GlobalTimeBudgetMs = 0,
        [int]$DynamicTimeBudgetMs = 60000,
        [bool]$SafeMode = $true
    )

    Initialize-ExecutionLogFile -LogPath $LogPath

    $execContext = New-ExecutionContext
    $context = @{
        CFG                 = $CFG
        ExecContext         = $execContext
        LogPath             = $LogPath
        HostInfo            = Get-PowerShellHostInfo
        VisitedNodes        = @{}
        MaxIterations       = $MaxIterations
        MaxTotalNodes       = $MaxTotalNodes
        GlobalTimeBudgetMs  = $GlobalTimeBudgetMs
        DynamicTimeBudgetMs = $DynamicTimeBudgetMs
        SafeMode            = $SafeMode
        PreExecutionGateMode = 'Balanced'
        PreExecutionGateCache = @{}
        DynamicDepthLimit    = $null
        TotalVisits         = 0
        StopReason          = $null
        LastConditionResult = $true
        ResolvableResults   = @{}
        VariableReadResults = @{}
        LiteralizedCommandResults = @()
        SensitiveSinkResults = @()
        BlockedTaintedVariables = @{}
        TrackedEnvironmentVariables = @{}

        ScopeStack            = @()
        CurrentScopePrefix    = ""
        ForbiddenCommands     = @(
            'Remove-Item', 'del', 'rm', 'rmdir', 'rd', 'ri', 'erase',
            'Clear-Content', 'clc',
            'Clear-ItemProperty', 'clp',
            'Remove-ItemProperty', 'rp',
            'Clear-RecycleBin',

            'Move-Item', 'move', 'mv', 'mi',
            'Rename-Item', 'ren', 'rni',

            'Invoke-WebRequest', 'iwr', 'curl', 'wget',
            'Invoke-RestMethod', 'irm',
            'Start-BitsTransfer',
            'Add-BitsFile',
            'Complete-BitsTransfer',
            'Test-NetConnection',
            'Test-Connection', 'ping',
            'Send-MailMessage',

            'Start-Process', 'start', 'saps',
            'Wait-Process',
            'Debug-Process',

            'Stop-Computer',
            'Restart-Computer',
            'Suspend-Computer',
            'Checkpoint-Computer',
            'Restore-Computer',

            'Invoke-Command', 'icm',
            'Enter-PSSession',
            'New-PSSession',
            'Enable-PSRemoting',
            'Disable-PSRemoting',
            'Enable-PSSessionConfiguration',
            'Register-PSSessionConfiguration',

            'Read-Host',
            'Get-Credential',
            'Out-GridView',

            'Wait-Event',
            'Wait-Job',

            'Format-Volume',
            'Clear-Disk',
            'Initialize-Disk',
            'Set-Disk',
            'Remove-Partition',
            'Optimize-Volume',
            'Expand-Archive',
            'Compress-Archive',

            'Out-Printer',
            'Start-Transcript',
            'Stop-Transcript'
        )
        FunctionSubgraphs      = @{}
        ScriptBlockSubgraphs   = @{}
        VarToBlockMapping      = @{}
        RuntimeSubgraphs       = @{}
        RuntimeSubgraphOrder   = @()
        CallStack              = @()
        MaxCallDepth           = 100
        DynamicInvokeResults   = @()
        FunctionInvokeResults  = @()
        LastSubgraphResult     = $null
        PipelineCurrentStack   = @()
        OutputCaptureStack     = @()
        LastPipelineFlowControl = $null
        TextParseCache            = @{}
        TextParseCacheKeyByNodeId = @{}
        TextParseErrors           = @()
        LogArgumentDetailsEnabled = $true
        LogBindingDetailsEnabled  = $true
        LogVariableDetailsEnabled = $true
        LogResultDetailsEnabled   = $true
        LogBufferBuilder          = [System.Text.StringBuilder]::new()
        LogBufferedLines          = 0
        LogBufferedBytes          = 0
        LogFlushLineThreshold     = 5
        LogFlushByteThreshold     = 2048
        ExecutionStopwatch        = [System.Diagnostics.Stopwatch]::StartNew()
        DynamicBudgetStopwatch    = [System.Diagnostics.Stopwatch]::new()
    }
    $context.ExecContext.GlobalTimeBudgetMs = $GlobalTimeBudgetMs
    $context.ExecContext.ExecutionStopwatch = $context.ExecutionStopwatch

    Ensure-CFGExecutionNodeShapes -CFG $CFG
    Write-ExecutionLog -Context $context -Message "=== CFG 调试会话开始 ==="
    $hostDisplay = Format-PowerShellHostInfo -HostInfo $context.HostInfo
    Write-ExecutionLog -Context $context -Message "Host: $hostDisplay"
    if ($context.HostInfo -and $context.HostInfo.ExecutablePath) {
        Write-ExecutionLog -Context $context -Message "HostExe: $($context.HostInfo.ExecutablePath)"
    }
    Write-ExecutionLog -Context $context -Message "MaxIterations: $MaxIterations, MaxTotalNodes: $MaxTotalNodes"
    if ($GlobalTimeBudgetMs -gt 0 -or $DynamicTimeBudgetMs -gt 0) {
        Write-ExecutionLog -Context $context -Message "TimeBudget: Global=${GlobalTimeBudgetMs}ms, Dynamic=${DynamicTimeBudgetMs}ms"
    }
    Write-ExecutionLog -Context $context -Message "SafeMode: $SafeMode"
    Write-ExecutionLog -Context $context -Message ""
    Write-ExecutionLog -Context $context -Message "=== 初始化子图映射 ==="
    Initialize-SubgraphMappings -CFG $CFG -Context $context
    $null = Ensure-CFGExecutionIndexes -CFG $CFG
    Write-ExecutionLog -Context $context -Message ""

    $startNode = Resolve-CFGNodeValue -CFG $CFG -Value (Get-CFGFirstNodeByType -CFG $CFG -Type "Start")
    $completed = $false
    $stopReason = $null
    if ($null -eq $startNode) {
        Write-ExecutionLog -Context $context -Message "!!! 未找到 Start 节点 !!!"
        Flush-ExecutionLogBuffer -Context $context
        $completed = $true
        $stopReason = 'NoStartNode'
    }

    return @{
        CFG           = $CFG
        Context       = $context
        CurrentNode   = $startNode
        IsCompleted   = $completed
        StopReason    = $stopReason
        StepCounter   = 0
        History       = New-Object System.Collections.ArrayList
        Failures      = New-Object System.Collections.ArrayList
        LastFailure   = $null
        SummaryLogged = $false
        Closed        = $false
    }
}

function Add-CFGExecutionFailure {
    param(
        [Parameter(Mandatory)][hashtable]$Session,
        [Parameter(Mandatory)]$Node,
        [int]$Step = -1,
        [string]$Status,
        [string]$Action,
        [string]$Reason,
        [string]$Error,
        $NextNode = $null,
        [string]$NextEdgeLabel = $null,
        [string]$Source = 'Runtime'
    )

    if ([string]::IsNullOrWhiteSpace($Error)) { return $null }

    $failure = [PSCustomObject]@{
        Index         = [int]$Session.Failures.Count + 1
        Time          = (Get-Date).ToString('HH:mm:ss.fff')
        Step          = $Step
        NodeId        = if ($Node) { $Node.Id } else { $null }
        NodeType      = if ($Node) { [string]$Node.Type } else { $null }
        Code          = if ($Node) { [string]$Node.Text } else { $null }
        Status        = $Status
        Action        = $Action
        Reason        = $Reason
        Error         = $Error
        Source        = $Source
        Continued     = [bool]($null -ne $NextNode)
        NextNodeId    = if ($NextNode) { $NextNode.Id } else { $null }
        NextEdgeLabel = $NextEdgeLabel
    }
    $null = $Session.Failures.Add($failure)
    $Session.LastFailure = $failure
    return $failure
}

function Get-CFGExecutionFailures {
    param([hashtable]$Session)

    if (-not $Session -or -not $Session.Failures) { return @() }
    return @($Session.Failures)
}

function Write-CFGExecutionSummary {
    param(
        [Parameter(Mandatory)][hashtable]$Session
    )

    if ($Session.SummaryLogged) { return }

    $context = $Session.Context
    Write-ExecutionLog -Context $context -Message ""
    Write-ExecutionLog -Context $context -Message "=== 执行统计 ==="
    Write-ExecutionLog -Context $context -Message "Total visits: $($context.TotalVisits)"
    Write-ExecutionLog -Context $context -Message "Unique nodes: $($context.VisitedNodes.Count)"
    if ($Session.StopReason) {
        Write-ExecutionLog -Context $context -Message "StopReason: $($Session.StopReason)"
    }
    $failureCount = @(Get-CFGExecutionFailures -Session $Session).Count
    Write-ExecutionLog -Context $context -Message "Failures: $failureCount"

    $Session.SummaryLogged = $true
}

function Close-CFGExecutionSession {
    param(
        [Parameter(Mandatory)][hashtable]$Session
    )

    if ($Session.Closed) { return }
    Write-CFGExecutionSummary -Session $Session
    Flush-ExecutionLogBuffer -Context $Session.Context
    if ($Session.Context -and $Session.Context.ExecContext) {
        Close-ExecutionContext -ExecContext $Session.Context.ExecContext
    }
    $Session.Closed = $true
}

function Test-CFGDebugAutoPassNodeType {
    param([string]$NodeType)
    $autoTypes = @(
        'Start', 'MainStart', 'MainEnd',
        'If Condition', 'Else', 'Merge', 'Default',
        'Try', 'Catch', 'Finally', 'FunctionDef',
        'LoopStart', 'LoopEnd', 'ProcessEnd', 'SwitchStart', 'SwitchEnd',
        'FuncStart', 'BlockStart', 'FuncParams', 'BlockParams',
        'FuncEnd', 'BlockEnd', 'Return', 'OutputCaptureStart', 'OutputCaptureEnd'
    )
    return ($NodeType -in $autoTypes)
}

function Get-CFGEdgeLabel {
    param(
        [Parameter(Mandatory)][hashtable]$CFG,
        [Parameter(Mandatory)][int]$FromNodeId,
        [Parameter(Mandatory)][int]$ToNodeId
    )

    $indexes = Ensure-CFGExecutionIndexes -CFG $CFG
    $pairKey = '{0}->{1}' -f $FromNodeId, $ToNodeId
    if ($indexes -and $indexes.EdgeLabelByPair.ContainsKey($pairKey)) {
        return [string]$indexes.EdgeLabelByPair[$pairKey]
    }

    $edge = Get-CFGOutgoingEdges -CFG $CFG -FromNodeId $FromNodeId | Where-Object { $_.To -eq $ToNodeId } | Select-Object -First 1
    if ($edge) {
        if ($indexes) {
            $indexes.EdgeLabelByPair[$pairKey] = [string]$edge.Label
        }
        return [string]$edge.Label
    }

    if ($indexes) {
        Add-CFGExecutionIndexFallback -Indexes $indexes
    }
    return $null
}

function Get-CFGConditionEdgeLabel {
    param(
        [Parameter(Mandatory)][string]$NodeType,
        [Parameter(Mandatory)][bool]$ConditionValue
    )

    switch ($NodeType) {
        'Condition'        { if ($ConditionValue) { return 'True' } else { return 'False' } }
        'SwitchCondition'  { if ($ConditionValue) { return 'True' } else { return 'False' } }
        'CaseCondition'    { if ($ConditionValue) { return 'True' } else { return 'False' } }
        'ForEachCondition' { if ($ConditionValue) { return 'Has next' } else { return 'No more items' } }
        'ProcessCondition' { if ($ConditionValue) { return 'Has next' } else { return 'No more items' } }
        default            { if ($ConditionValue) { return 'True' } else { return 'False' } }
    }
}

function Get-CFGExecutionResultValue {
    param(
        $ExecutionResult,
        [Parameter(Mandatory)][string]$Name,
        $Default = $null
    )

    if ($null -eq $ExecutionResult) { return $Default }

    if ($ExecutionResult -is [hashtable]) {
        if ($ExecutionResult.ContainsKey($Name)) {
            return $ExecutionResult[$Name]
        }
        return $Default
    }

    $prop = $ExecutionResult.PSObject.Properties[$Name]
    if ($null -ne $prop) {
        return $prop.Value
    }

    return $Default
}

function Get-CFGObjectPropertyValue {
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

function Set-CFGObjectDefaultProperty {
    param(
        $Object,
        [Parameter(Mandatory)][string]$Name,
        $Value
    )

    if ($null -eq $Object) { return }

    if ($Object -is [hashtable]) {
        if (-not $Object.ContainsKey($Name) -or $null -eq $Object[$Name]) {
            $Object[$Name] = $Value
        }
        return
    }

    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
        return
    }

    if ($null -eq $prop.Value) {
        try {
            $prop.Value = $Value
        } catch {
            $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
        }
    }
}

function Ensure-CFGNodeExecutionShape {
    param($Node)

    if ($null -eq $Node) { return }

    Set-CFGObjectDefaultProperty -Object $Node -Name 'Text' -Value ''
    Set-CFGObjectDefaultProperty -Object $Node -Name 'VarsRead' -Value @()
    Set-CFGObjectDefaultProperty -Object $Node -Name 'VarsWritten' -Value @()
    Set-CFGObjectDefaultProperty -Object $Node -Name 'Resolvables' -Value @()
    Set-CFGObjectDefaultProperty -Object $Node -Name 'AliasesUsed' -Value @()
    Set-CFGObjectDefaultProperty -Object $Node -Name 'DynamicInvoke' -Value $null
    Set-CFGObjectDefaultProperty -Object $Node -Name 'Invokes' -Value @{ Functions = @(); ScriptBlocks = @() }

    $invokes = Get-CFGObjectPropertyValue -Object $Node -Name 'Invokes' -Default $null
    if ($invokes -is [hashtable]) {
        if (-not $invokes.ContainsKey('Functions') -or $null -eq $invokes['Functions']) {
            $invokes['Functions'] = @()
        }
        if (-not $invokes.ContainsKey('ScriptBlocks') -or $null -eq $invokes['ScriptBlocks']) {
            $invokes['ScriptBlocks'] = @()
        }
    } elseif ($null -ne $invokes) {
        Set-CFGObjectDefaultProperty -Object $invokes -Name 'Functions' -Value @()
        Set-CFGObjectDefaultProperty -Object $invokes -Name 'ScriptBlocks' -Value @()
    }
}

function Ensure-CFGExecutionNodeShapes {
    param([hashtable]$CFG)

    if (-not $CFG -or -not $CFG.ContainsKey('Nodes') -or -not $CFG.Nodes) { return }
    foreach ($node in @($CFG.Nodes)) {
        Ensure-CFGNodeExecutionShape -Node $node
    }
}

function Get-CFGNodeVarInfos {
    param(
        $Node,
        [Parameter(Mandatory)][ValidateSet('VarsRead', 'VarsWritten')][string]$PropertyName
    )

    Ensure-CFGNodeExecutionShape -Node $Node
    return @(Get-CFGObjectPropertyValue -Object $Node -Name $PropertyName -Default @())
}

function Invoke-CFGStep {
    param(
        [Parameter(Mandatory)][hashtable]$Session,
        [switch]$StopAtUserNode = $true
    )

    if ($Session.IsCompleted) {
        Flush-ExecutionLogBuffer -Context $Session.Context
        return @{
            Completed   = $true
            StopReason  = $Session.StopReason
            Records     = @()
            LastRecord  = $null
            CurrentNode = $Session.CurrentNode
        }
    }

    $context = $Session.Context
    $records = New-Object System.Collections.ArrayList

    function Convert-VarMapToRecord {
        param([hashtable]$VarMap)
        $out = [ordered]@{}
        if ($null -eq $VarMap -or $VarMap.Count -eq 0) {
            return $out
        }
        if ($VarMap.Count -eq 1) {
            foreach ($entry in $VarMap.GetEnumerator()) {
                $out[[string]$entry.Key] = Format-VariableValue $entry.Value
            }
            return $out
        }
        foreach ($entry in @($VarMap.GetEnumerator() | Sort-Object Key)) {
            $out[[string]$entry.Key] = Format-VariableValue $entry.Value
        }
        return $out
    }

    function Add-Record {
        param($Record)
        if ($null -eq $Record.PSObject.Properties['RuntimeBlockName']) {
            $runtimeBlockName = $null
            if ($Record.PSObject.Properties['NodeId'] -and $null -ne $Record.NodeId) {
                $recordNode = Get-NodeById -CFG $context.CFG -Id ([int]$Record.NodeId)
                if ($recordNode -and $recordNode.PSObject.Properties['RuntimeBlockName']) {
                    $runtimeBlockName = [string]$recordNode.RuntimeBlockName
                }
            }
            $Record | Add-Member -NotePropertyName RuntimeBlockName -NotePropertyValue $runtimeBlockName -Force
        }
        if ($null -eq $Record.PSObject.Properties['Step']) {
            $Record | Add-Member -NotePropertyName Step -NotePropertyValue $Session.StepCounter -Force
        } else {
            $Record.Step = $Session.StepCounter
        }
        $Session.StepCounter++
        $null = $records.Add($Record)
        $null = $Session.History.Add($Record)
    }

    while (-not $Session.IsCompleted) {
        $currentNode = Resolve-CFGNodeValue -CFG $context.CFG -Value $Session.CurrentNode
        $Session.CurrentNode = $currentNode
        if ($null -eq $currentNode) {
            $Session.IsCompleted = $true
            if (-not $Session.StopReason) { $Session.StopReason = 'NoNextNode' }
            break
        }
        Ensure-CFGNodeExecutionShape -Node $currentNode

        $globalBudgetStatus = Get-ContextBudgetStatus -Context $context -BudgetPropertyName 'GlobalTimeBudgetMs' -StopwatchPropertyName 'ExecutionStopwatch' -StopReason 'GlobalTimeBudgetExceeded'
        if ($globalBudgetStatus.Exceeded) {
            Write-ExecutionLog -Context $context -Message "!!! 执行总时长超限 ($($globalBudgetStatus.ElapsedMs)ms / $($globalBudgetStatus.BudgetMs)ms) !!!"
            $Session.IsCompleted = $true
            $Session.StopReason = $globalBudgetStatus.StopReason
            $context.StopReason = $globalBudgetStatus.StopReason
            break
        }

        $isAutoPassCurrent = Test-CFGDebugAutoPassNodeType -NodeType $currentNode.Type
        if ($StopAtUserNode -and -not $isAutoPassCurrent -and $records.Count -gt 0) {
            break
        }

        if ($currentNode.Type -eq "End") {
            Write-ExecutionLog -Context $context -Message "=== 执行结束 ==="
            Add-Record ([PSCustomObject]@{
                Time             = (Get-Date).ToString('HH:mm:ss.fff')
                NodeId           = $currentNode.Id
                NodeType         = $currentNode.Type
                Code             = [string]$currentNode.Text
                Status           = 'END'
                Action           = 'End'
                Target           = $null
                Reason           = $null
                Error            = $null
                Result           = $null
                Executed         = $false
                Success          = $true
                ConditionResult  = $null
                VarsRead         = [ordered]@{}
                VarsWritten      = [ordered]@{}
                NextNodeId       = $null
                NextEdgeLabel    = $null
                AutoPassed       = $true
            })
            $Session.CurrentNode = $null
            $Session.IsCompleted = $true
            $Session.StopReason = 'EndNode'
            break
        }

        if ($currentNode.Type -eq "FuncEnd" -or $currentNode.Type -eq "BlockEnd") {
            Write-ExecutionLog -Context $context -Message "--- Node $($currentNode.Id) [$($currentNode.Type)] ---"
            Write-ExecutionLog -Context $context -Message "  Code: $($currentNode.Text)"

            $returnValue = $context.LastSubgraphResult
            $nextNode = $null

            $scope = Pop-ExecutionScope -Context $context
            if ($scope) {
                if ($scope.ReturnNodeId) {
                    Add-FunctionInvokeResultRecord -Context $context -Scope $scope -ReturnValue $returnValue
                    $context.LastSubgraphResult = $null

                    if ($scope.TargetVarName -and $null -ne $returnValue) {
                        $actualVarName = $scope.TargetVarName
                        if ($context.ScopeStack.Count -gt 0) {
                            $outerScope = $context.ScopeStack[-1]
                            if ($outerScope.LocalVars -and $scope.TargetVarName -in $outerScope.LocalVars) {
                                $actualVarName = $outerScope.ScopePrefix + $scope.TargetVarName
                            }
                        }
                        $context.ExecContext.Runspace.SessionStateProxy.SetVariable($actualVarName, $returnValue)
                        Write-ExecutionLog -Context $context -Message ({ "  [RETURN] Set `$$actualVarName = $(Format-VariableValue $returnValue)" }).GetNewClosure()
                    }

                    Write-ExecutionLog -Context $context -Message "  [RETURN] Returning from $($scope.ScopeType) '$($scope.ScopeName)' to Node $($scope.ReturnNodeId)"
                    $nextNode = Resolve-CFGNodeValue -CFG $context.CFG -Value (Get-NodeById -CFG $context.CFG -Id $scope.ReturnNodeId)
                } else {
                    $context.LastSubgraphResult = $returnValue
                    Write-ExecutionLog -Context $context -Message ({ "  [RETURN] Inline call completed, preserving result: $(Format-VariableValue $returnValue)" }).GetNewClosure()
                }
            }

            $edgeLabel = if ($nextNode) { Get-CFGEdgeLabel -CFG $context.CFG -FromNodeId $currentNode.Id -ToNodeId $nextNode.Id } else { $null }
            Add-Record ([PSCustomObject]@{
                Time             = (Get-Date).ToString('HH:mm:ss.fff')
                NodeId           = $currentNode.Id
                NodeType         = $currentNode.Type
                Code             = [string]$currentNode.Text
                Status           = 'OK'
                Action           = 'ReturnToCaller'
                Target           = if ($nextNode) { $nextNode.Id } else { $null }
                Reason           = $null
                Error            = $null
                Result           = if ($null -ne $returnValue) { Format-VariableValue $returnValue } else { $null }
                Executed         = $false
                Success          = $true
                ConditionResult  = $null
                VarsRead         = [ordered]@{}
                VarsWritten      = [ordered]@{}
                NextNodeId       = if ($nextNode) { $nextNode.Id } else { $null }
                NextEdgeLabel    = $edgeLabel
                AutoPassed       = $true
            })

            $nextNode = Resolve-CFGNodeValue -CFG $context.CFG -Value $nextNode
            $Session.CurrentNode = $nextNode
            if ($null -eq $nextNode) {
                $Session.IsCompleted = $true
                if (-not $Session.StopReason) { $Session.StopReason = 'NoNextNode' }
                break
            }
            continue
        }

        if ($currentNode.Type -eq "Return") {
            Write-ExecutionLog -Context $context -Message "--- Node $($currentNode.Id) [Return] ---"
            Write-ExecutionLog -Context $context -Message "  Code: $($currentNode.Text)"

            $null = Add-CFGVisitedNodeCount -Context $context -NodeId $currentNode.Id
            $context.TotalVisits++

            $returnValue = $null
            $nextNode = $null

            if ($context.ScopeStack.Count -gt 0) {
                $currentScope = $context.ScopeStack[-1]
                $retInfo = Get-NodeTextReturnExpression -Node $currentNode -Context $context
                if (-not $retInfo.Success) {
                    Write-ExecutionLog -Context $context -Message "  [RETURN] Parse Node.Text failed: $($retInfo.Error)"
                } elseif ($retInfo.Code) {
                    $returnCode = Convert-CodeForCurrentScope -Code $retInfo.Code -Context $context
                    $evalResult = Invoke-InContext -ExecContext $context.ExecContext -Code $returnCode
                    if ($evalResult.Success -and $null -ne $evalResult.Result) {
                        if ($context.OutputCaptureStack -and $context.OutputCaptureStack.Count -gt 0) {
                            Add-OutputsToCurrentCapture -Context $context -Result $evalResult.Result
                        }
                        $returnValue = Normalize-ExecutionResultValue -Value $evalResult.Result -TreatArraysAsSequence
                        Write-ExecutionLog -Context $context -Message ({ "  [RETURN] Expression value: $(Format-VariableValue $returnValue)" }).GetNewClosure()
                    }
                }

                $context.LastSubgraphResult = $returnValue
                if ($currentScope.EndNodeId) {
                    Write-ExecutionLog -Context $context -Message "  [RETURN] Jumping to EndNode $($currentScope.EndNodeId)"
                    $nextNode = Resolve-CFGNodeValue -CFG $context.CFG -Value (Get-NodeById -CFG $context.CFG -Id $currentScope.EndNodeId)
                }
            } else {
                $nextNodes = @(Get-NextNodes -CFG $context.CFG -Node $currentNode -Context $context)
                if ($nextNodes.Count -gt 0) { $nextNode = $nextNodes[0] }
            }

            $nextNode = Resolve-CFGNodeValue -CFG $context.CFG -Value $nextNode
            $edgeLabel = if ($nextNode) { Get-CFGEdgeLabel -CFG $context.CFG -FromNodeId $currentNode.Id -ToNodeId $nextNode.Id } else { $null }
            Add-Record ([PSCustomObject]@{
                Time             = (Get-Date).ToString('HH:mm:ss.fff')
                NodeId           = $currentNode.Id
                NodeType         = $currentNode.Type
                Code             = [string]$currentNode.Text
                Status           = 'OK'
                Action           = 'Return'
                Target           = if ($nextNode) { $nextNode.Id } else { $null }
                Reason           = $null
                Error            = $null
                Result           = if ($null -ne $returnValue) { Format-VariableValue $returnValue } else { $null }
                Executed         = $true
                Success          = $true
                ConditionResult  = $null
                VarsRead         = [ordered]@{}
                VarsWritten      = [ordered]@{}
                NextNodeId       = if ($nextNode) { $nextNode.Id } else { $null }
                NextEdgeLabel    = $edgeLabel
                AutoPassed       = $true
            })

            $Session.CurrentNode = $nextNode
            if ($null -eq $nextNode) {
                $Session.IsCompleted = $true
                if (-not $Session.StopReason) { $Session.StopReason = 'NoNextNode' }
                break
            }
            continue
        }

        if ($context.TotalVisits -ge $context.MaxTotalNodes) {
            Write-ExecutionLog -Context $context -Message "!!! 达到最大节点访问次数 ($($context.MaxTotalNodes)) !!!"
            $Session.IsCompleted = $true
            $Session.StopReason = 'MaxTotalNodes'
            break
        }

        $nodeKey = $currentNode.Id
        if (-not $context.VisitedNodes.ContainsKey($nodeKey)) {
            $context.VisitedNodes[$nodeKey] = 0
        }
        if ($context.VisitedNodes[$nodeKey] -ge $context.MaxIterations) {
            Write-ExecutionLog -Context $context -Message "!!! 节点 $nodeKey 达到最大迭代次数 ($($context.MaxIterations)) !!!"
            $Session.IsCompleted = $true
            $Session.StopReason = 'MaxIterations'
            break
        }

        $context.VisitedNodes[$nodeKey]++
        $context.TotalVisits++

        Write-ExecutionLog -Context $context -Message "--- Node $($currentNode.Id) [$($currentNode.Type)] ---"
        Write-ExecutionLog -Context $context -Message "  Code: $($currentNode.Text)"

        if ($currentNode.Type -in @('FuncParams', 'BlockParams') -and $context.ScopeStack.Count -gt 0) {
            $currentScope = $context.ScopeStack[-1]
            if (($currentScope.Arguments -and $currentScope.Arguments.Count -gt 0) -or
                ($currentScope.NamedArguments -and $currentScope.NamedArguments.Count -gt 0)) {
                $parameterAsts = @()
                if ($currentNode.Ast -and $currentNode.Ast.Parameters) {
                    $parameterAsts = @($currentNode.Ast.Parameters)
                } elseif ($currentNode.PSObject.Properties['ParameterAsts'] -and $currentNode.ParameterAsts) {
                    $parameterAsts = @($currentNode.ParameterAsts)
                }
                if ($parameterAsts.Count -gt 0) {
                    $paramNames = @()
                    foreach ($param in $parameterAsts) {
                        if ($param -and $param.Name -and $param.Name.VariablePath) {
                            $paramNames += $param.Name.VariablePath.UserPath
                        }
                    }

                    $namedLookup = @{}
                    foreach ($key in @($currentScope.NamedArguments.Keys)) {
                        $namedLookup[[string]$key] = $currentScope.NamedArguments[$key]
                    }

                    $posIndex = 0
                    foreach ($paramName in $paramNames) {
                        $hasValue = $false
                        $argValue = $null

                        foreach ($lookupKey in @($namedLookup.Keys)) {
                            if ($lookupKey -ieq $paramName) {
                                $argValue = $namedLookup[$lookupKey]
                                $hasValue = $true
                                break
                            }
                        }

                        if (-not $hasValue -and $posIndex -lt @($currentScope.Arguments).Count) {
                            $argValue = $currentScope.Arguments[$posIndex]
                            $posIndex++
                            $hasValue = $true
                        }

                        if ($hasValue) {
                            $prefixedName = $currentScope.ScopePrefix + $paramName
                            $context.ExecContext.Runspace.SessionStateProxy.SetVariable($prefixedName, $argValue)
                            if (Test-ExecutionLogDetailEnabled -Context $context -FlagName 'LogBindingDetailsEnabled') {
                                Write-ExecutionLog -Context $context -Message ({ "  [BIND] `$$prefixedName = $(Format-VariableValue $argValue)" }).GetNewClosure()
                            }
                            if ($paramName -notin $currentScope.LocalVars) {
                                $currentScope.LocalVars += $paramName
                            }
                        }
                    }
                }
            }
        }

        $currentNodeVarsRead = @(Get-CFGObjectPropertyValue -Object $currentNode -Name 'VarsRead' -Default @())
        $currentNodeVarsWritten = @(Get-CFGObjectPropertyValue -Object $currentNode -Name 'VarsWritten' -Default @())

        $varsBefore = @{}
        foreach ($varInfo in $currentNodeVarsRead) {
            if ($null -eq $varInfo -or [string]::IsNullOrWhiteSpace([string]$varInfo.Name)) {
                Write-ExecutionLog -Context $context -Message "  [WARN] Skip VarsRead entry with null/empty Name"
                continue
            }
            $actualVarName = $varInfo.Name
            if ($context.ScopeStack.Count -gt 0) {
                $currentScope = $context.ScopeStack[-1]
                if ($currentScope.LocalVars -and $varInfo.Name -in $currentScope.LocalVars) {
                    $actualVarName = $currentScope.ScopePrefix + $varInfo.Name
                }
            }
            $value = Get-VariableFromContext -ExecContext $context.ExecContext -Name $actualVarName
            $varsBefore[$varInfo.Name] = $value

            if ($null -ne $varInfo.StartOffset -and $null -ne $varInfo.EndOffset -and (Test-ResolvableValue $value) -and -not (Test-CFGVariableBlockedTaint -Context $context -ActualName $actualVarName)) {
                $key = "$($currentNode.Id):$($varInfo.StartOffset):$($varInfo.EndOffset)"
                if (-not $context.VariableReadResults.ContainsKey($key)) {
                    $context.VariableReadResults[$key] = @{
                        NodeId  = $currentNode.Id
                        VarInfo = $varInfo
                        Values  = @()
                    }
                }
                $context.VariableReadResults[$key].Values += (Format-ResolvableValue $value)
            }
        }

        $execResult = $null
        $varsAfter = @{}
        $status = 'ERR'
        $nextNode = $null
        $nextEdgeLabel = $null
        $autoPassed = Test-CFGDebugAutoPassNodeType -NodeType $currentNode.Type
        $failureSource = 'Runtime'
        $execAction = $null
        $execTarget = $null
        $execReason = $null
        $execError = $null
        $execOutput = $null
        $execExecuted = $false
        $execSuccess = $false
        $execJumpToNode = $null

        try {
            $execResult = Invoke-NodeSafe -Node $currentNode -Context $context

            if ($context.OutputCaptureStack -and $context.OutputCaptureStack.Count -gt 0) {
                $captureThis = $true
                $nonOutputTypes = @('Condition', 'ForEachCondition', 'ProcessCondition', 'SwitchCondition', 'CaseCondition', 'OutputCaptureStart', 'OutputCaptureEnd')
                if ($currentNode.Type -in $nonOutputTypes) { $captureThis = $false }
                if ($captureThis -and $currentNode.Type -eq 'PipelineElement' -and $currentNodeVarsWritten.Count -gt 0) {
                    foreach ($v in $currentNodeVarsWritten) {
                        if ($v.Name -match '^_pipe_[a-f0-9]+$') {
                            $captureThis = $false
                            break
                        }
                    }
                }
                if ($captureThis) {
                    Add-OutputsToCurrentCapture -Context $context -Result $execResult.Result
                }
            }

            if ($context.OutputCaptureStack -and $context.OutputCaptureStack.Count -gt 0 -and $currentNode.Type -in @('Break', 'Continue')) {
                $label = $currentNode.Type
                $edge = Get-CFGOutgoingEdges -CFG $context.CFG -FromNodeId $currentNode.Id | Where-Object { $_.Label -eq $label } | Select-Object -First 1
                if ($edge) {
                    $targetNode = Get-NodeById -CFG $context.CFG -Id $edge.To
                    if ($targetNode -and $targetNode.Type -in @('BlockEnd', 'FuncEnd', 'ProcessEnd', 'End', 'MainEnd')) {
                        $context.LastPipelineFlowControl = $label
                    }
                }
            }

            foreach ($varInfo in $currentNodeVarsWritten) {
                if ($null -eq $varInfo -or [string]::IsNullOrWhiteSpace([string]$varInfo.Name)) {
                    Write-ExecutionLog -Context $context -Message "  [WARN] Skip VarsWritten entry with null/empty Name"
                    continue
                }
                $actualVarName = $varInfo.Name
                if ($context.ScopeStack.Count -gt 0) {
                    $currentScope = $context.ScopeStack[-1]
                    if ($currentScope.LocalVars -and $varInfo.Name -in $currentScope.LocalVars) {
                        $actualVarName = $currentScope.ScopePrefix + $varInfo.Name
                    }
                }
                $value = Get-VariableFromContext -ExecContext $context.ExecContext -Name $actualVarName
                $varsAfter[$varInfo.Name] = $value
            }

            Update-CFGAssignmentBlockedTaint -Node $currentNode -Context $context
            Update-VariableScriptBlockMappingAfterNodeExecution -Node $currentNode -Context $context

            $execAction = [string](Get-CFGExecutionResultValue -ExecutionResult $execResult -Name 'Action')
            $execTarget = Get-CFGExecutionResultValue -ExecutionResult $execResult -Name 'Target'
            $execReason = [string](Get-CFGExecutionResultValue -ExecutionResult $execResult -Name 'Reason')
            $execError = [string](Get-CFGExecutionResultValue -ExecutionResult $execResult -Name 'Error')
            $execOutput = Get-CFGExecutionResultValue -ExecutionResult $execResult -Name 'Result'
            $execExecuted = [bool](Get-CFGExecutionResultValue -ExecutionResult $execResult -Name 'Executed' -Default $false)
            $execSuccess = [bool](Get-CFGExecutionResultValue -ExecutionResult $execResult -Name 'Success' -Default $false)
            $execJumpToNode = Get-CFGExecutionResultValue -ExecutionResult $execResult -Name 'JumpToNode'

            $status = if ($execAction -eq 'Blocked') {
                'BLOCKED'
            } elseif (-not $execExecuted) {
                'SKIP'
            } elseif ($execSuccess) {
                'OK'
            } else {
                'ERR'
            }

            Write-ExecutionLog -Context $context -Message "  Status: $status"
            if ($execAction -and $execAction -notin @('Execute', 'Skip')) {
                Write-ExecutionLog -Context $context -Message "  Action: $execAction"
                if ($null -ne $execTarget -and -not [string]::IsNullOrWhiteSpace([string]$execTarget)) { Write-ExecutionLog -Context $context -Message "  Target: $execTarget" }
                if (-not [string]::IsNullOrWhiteSpace($execReason)) { Write-ExecutionLog -Context $context -Message "  Reason: $execReason" }
            }

            if ($execExecuted) {
                if ((Test-ExecutionLogDetailEnabled -Context $Context -FlagName 'LogVariableDetailsEnabled') -and $varsBefore.Count -gt 0) {
                    Write-ExecutionLog -Context $context -Message '  VarsRead:'
                    foreach ($kv in $varsBefore.GetEnumerator()) {
                        Write-ExecutionLog -Context $context -Message ({ "    `$$($kv.Key) = $(Format-VariableValue $kv.Value)" }).GetNewClosure()
                    }
                }
                if ((Test-ExecutionLogDetailEnabled -Context $Context -FlagName 'LogVariableDetailsEnabled') -and $varsAfter.Count -gt 0) {
                    Write-ExecutionLog -Context $context -Message '  VarsWritten:'
                    foreach ($kv in $varsAfter.GetEnumerator()) {
                        Write-ExecutionLog -Context $context -Message ({ "    `$$($kv.Key) = $(Format-VariableValue $kv.Value)" }).GetNewClosure()
                    }
                }
                if ($null -ne $execOutput -and @($execOutput).Count -gt 0) {
                    if (Test-ExecutionLogDetailEnabled -Context $context -FlagName 'LogResultDetailsEnabled') {
                        Write-ExecutionLog -Context $context -Message ({ "  Result: $(Format-VariableValue $execOutput)" }).GetNewClosure()
                    }
                    if ($context.ScopeStack.Count -gt 0) {
                        $context.LastSubgraphResult = Normalize-ExecutionResultValue -Value $execOutput -TreatArraysAsSequence
                    }
                }
                if (-not $execSuccess -and -not [string]::IsNullOrWhiteSpace($execError)) {
                    Write-ExecutionLog -Context $context -Message "  Error: $execError"
                }
                if ($currentNode.Type -in @('Condition', 'ForEachCondition', 'ProcessCondition', 'SwitchCondition', 'CaseCondition')) {
                    Write-ExecutionLog -Context $context -Message "  ConditionResult: $($context.LastConditionResult)"
                }
            }

            if ($execAction -in @('CallFunction', 'CallScriptBlock') -and $execJumpToNode) {
                $nextNode = Resolve-CFGNodeValue -CFG $context.CFG -Value $execJumpToNode
                if ($nextNode) {
                    Write-ExecutionLog -Context $context -Message "  [JUMP] Jumping to Node $($nextNode.Id)"
                }
            } else {
                $nextNodes = @(Get-NextNodes -CFG $context.CFG -Node $currentNode -Context $context)
                if ($nextNodes.Count -gt 0) {
                    $nextNode = $nextNodes[0]
                }
            }

            $nextNode = Resolve-CFGNodeValue -CFG $context.CFG -Value $nextNode
            $nextEdgeLabel = if ($nextNode) { Get-CFGEdgeLabel -CFG $context.CFG -FromNodeId $currentNode.Id -ToNodeId $nextNode.Id } else { $null }
        }
        catch {
            $failureSource = 'Engine'
            $execResult = @{
                Success  = $false
                Executed = $true
                Result   = $null
                Error    = $_.Exception.Message
                Action   = 'InternalError'
                Target   = $null
                Reason   = $_.Exception.GetType().FullName
            }
            $status = 'ERR'
            $execAction = [string](Get-CFGExecutionResultValue -ExecutionResult $execResult -Name 'Action')
            $execTarget = Get-CFGExecutionResultValue -ExecutionResult $execResult -Name 'Target'
            $execReason = [string](Get-CFGExecutionResultValue -ExecutionResult $execResult -Name 'Reason')
            $execError = [string](Get-CFGExecutionResultValue -ExecutionResult $execResult -Name 'Error')
            $execOutput = Get-CFGExecutionResultValue -ExecutionResult $execResult -Name 'Result'
            $execExecuted = [bool](Get-CFGExecutionResultValue -ExecutionResult $execResult -Name 'Executed' -Default $false)
            $execSuccess = [bool](Get-CFGExecutionResultValue -ExecutionResult $execResult -Name 'Success' -Default $false)
            $execJumpToNode = Get-CFGExecutionResultValue -ExecutionResult $execResult -Name 'JumpToNode'
            Write-ExecutionLog -Context $context -Message '  Status: ERR'
            Write-ExecutionLog -Context $context -Message '  Action: InternalError'
            Write-ExecutionLog -Context $context -Message "  Reason: $execReason"
            Write-ExecutionLog -Context $context -Message "  Error: $execError"
            try {
                $nextNodes = @(Get-NextNodes -CFG $context.CFG -Node $currentNode -Context $context)
                if ($nextNodes.Count -gt 0) {
                    $nextNode = $nextNodes[0]
                }
            }
            catch {
                $nextNode = $null
            }
            $nextNode = Resolve-CFGNodeValue -CFG $context.CFG -Value $nextNode
            $nextEdgeLabel = if ($nextNode) { Get-CFGEdgeLabel -CFG $context.CFG -FromNodeId $currentNode.Id -ToNodeId $nextNode.Id } else { $null }
        }

        $failureRecord = $null
        if ($execExecuted -and -not $execSuccess -and -not [string]::IsNullOrWhiteSpace($execError)) {
            $failureRecord = Add-CFGExecutionFailure -Session $Session -Node $currentNode -Step $Session.StepCounter -Status $status -Action $execAction -Reason $execReason -Error $execError -NextNode $nextNode -NextEdgeLabel $nextEdgeLabel -Source $failureSource
            if ($failureRecord) {
                Write-ExecutionLog -Context $context -Message "  [CONTINUE] Failure recorded (#$($failureRecord.Index)); continuing to next node."
                Flush-ExecutionLogBuffer -Context $context
            }
        }

        Add-Record ([PSCustomObject]@{
            Time             = (Get-Date).ToString('HH:mm:ss.fff')
            NodeId           = $currentNode.Id
            NodeType         = $currentNode.Type
            Code             = [string]$currentNode.Text
            Status           = $status
            Action           = $execAction
            Target           = $execTarget
            Reason           = $execReason
            Error            = $execError
            Result           = if ($null -ne $execOutput) { Format-VariableValue $execOutput } else { $null }
            Executed         = $execExecuted
            Success          = $execSuccess
            ConditionResult  = if ($currentNode.Type -in @('Condition', 'ForEachCondition', 'ProcessCondition', 'SwitchCondition', 'CaseCondition')) { [bool]$context.LastConditionResult } else { $null }
            VarsRead         = Convert-VarMapToRecord -VarMap $varsBefore
            VarsWritten      = Convert-VarMapToRecord -VarMap $varsAfter
            NextNodeId       = if ($nextNode) { $nextNode.Id } else { $null }
            NextEdgeLabel    = $nextEdgeLabel
            FailureIndex     = if ($failureRecord) { [int]$failureRecord.Index } else { $null }
            FailureSource    = if ($failureRecord) { [string]$failureRecord.Source } else { $null }
            ContinuedOnError = if ($failureRecord) { [bool]$failureRecord.Continued } else { $null }
            AutoPassed       = $autoPassed
        })

        $nextNode = Resolve-CFGNodeValue -CFG $context.CFG -Value $nextNode
        $Session.CurrentNode = $nextNode
        if ($null -eq $nextNode) {
            $Session.IsCompleted = $true
            if (-not $Session.StopReason) { $Session.StopReason = 'NoNextNode' }
            break
        }

        if ($StopAtUserNode -and -not $autoPassed) {
            break
        }
    }

    if ($Session.IsCompleted) {
        Write-CFGExecutionSummary -Session $Session
    }

    Flush-ExecutionLogBuffer -Context $context
    return @{
        Completed   = $Session.IsCompleted
        StopReason  = $Session.StopReason
        Records     = @($records)
        LastRecord  = if ($records.Count -gt 0) { $records[$records.Count - 1] } else { $null }
        CurrentNode = $Session.CurrentNode
    }
}









function Test-CFGInternalVariableName {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) { return $true }
    if ($Name -in $script:AutoVariables) { return $true }
    if ($Name -match '^(_pipe_|_sc_[a-f0-9]{8}_|__|_fe_|_sw_|_foreach_|_where_|_select_|_proc_|_dyn_|_block_)') { return $true }
    if ($Name -in @('Error','Host','PID','PWD','ShellId','StackTrace','Matches','LastExitCode','PSBoundParameters','PSDefaultParameterValues','MyInvocation','PSScriptRoot','PSCommandPath')) { return $true }
    if ($Name -match '^PS[A-Z]') { return $true }
    return $false
}

function Get-CFGVariableStackShortId {
    param(
        [string]$Id,
        [int]$MaxLength = 8
    )

    if ([string]::IsNullOrWhiteSpace($Id)) { return '' }
    if ($Id.Length -le $MaxLength) { return $Id }
    return $Id.Substring(0, $MaxLength)
}

function Get-CFGVariableStackDescriptor {
    param([string]$ActualName)

    if ([string]::IsNullOrWhiteSpace($ActualName)) {
        return [PSCustomObject]@{
            Tier       = 'HiddenInternal'
            DisplayName = $ActualName
            SortBucket = 99
            ValueMode  = 'Default'
        }
    }

    if ($ActualName -eq '_') {
        return [PSCustomObject]@{
            Tier        = 'DefaultInternal'
            DisplayName = 'pipeline.current'
            SortBucket  = 10
            ValueMode   = 'Default'
        }
    }

    if ($ActualName -eq 'PSItem') {
        return [PSCustomObject]@{
            Tier        = 'HiddenInternal'
            DisplayName = 'PSItem'
            SortBucket  = 11
            ValueMode   = 'Default'
        }
    }

    $envActualName = Get-CFGEnvironmentVariableActualName -Name $ActualName
    if (-not [string]::IsNullOrWhiteSpace($envActualName)) {
        return [PSCustomObject]@{
            Tier        = 'User'
            DisplayName = ('$' + $envActualName)
            SortBucket  = 1
            ValueMode   = 'Default'
        }
    }

    if ($ActualName -eq '__proc_input') {
        return [PSCustomObject]@{
            Tier        = 'DefaultInternal'
            DisplayName = 'process.input'
            SortBucket  = 30
            ValueMode   = 'CollectionSummary'
        }
    }

    if ($ActualName -match '^_pipe_([a-f0-9]{8})$') {
        $shortId = Get-CFGVariableStackShortId -Id $Matches[1]
        return [PSCustomObject]@{
            Tier        = 'DefaultInternal'
            DisplayName = "pipe#$shortId"
            SortBucket  = 20
            ValueMode   = 'CollectionSummary'
        }
    }

    if ($ActualName -match '^__prc_([a-f0-9]{12})_idx$') {
        $shortId = Get-CFGVariableStackShortId -Id $Matches[1]
        return [PSCustomObject]@{
            Tier        = 'DefaultInternal'
            DisplayName = "process.index#$shortId"
            SortBucket  = 31
            ValueMode   = 'Default'
        }
    }

    if ($ActualName -match '^__prc_([a-f0-9]{12})_current$') {
        $shortId = Get-CFGVariableStackShortId -Id $Matches[1]
        return [PSCustomObject]@{
            Tier        = 'DefaultInternal'
            DisplayName = "process.current#$shortId"
            SortBucket  = 32
            ValueMode   = 'Default'
        }
    }

    if ($ActualName -match '^__prc_([a-f0-9]{12})$') {
        $shortId = Get-CFGVariableStackShortId -Id $Matches[1]
        return [PSCustomObject]@{
            Tier        = 'AdvancedInternal'
            DisplayName = "process.collection#$shortId"
            SortBucket  = 70
            ValueMode   = 'CollectionSummary'
        }
    }

    if ($ActualName -match '^__pfo_in_([a-f0-9]{12})$') {
        $shortId = Get-CFGVariableStackShortId -Id $Matches[1]
        return [PSCustomObject]@{
            Tier        = 'AdvancedInternal'
            DisplayName = "pfo.input#$shortId"
            SortBucket  = 71
            ValueMode   = 'CollectionSummary'
        }
    }

    if ($ActualName -match '^__pfo_([a-f0-9]{12})_idx$') {
        $shortId = Get-CFGVariableStackShortId -Id $Matches[1]
        return [PSCustomObject]@{
            Tier        = 'DefaultInternal'
            DisplayName = "pfo.index#$shortId"
            SortBucket  = 40
            ValueMode   = 'Default'
        }
    }

    if ($ActualName -match '^__pfo_([a-f0-9]{12})_cur$') {
        $shortId = Get-CFGVariableStackShortId -Id $Matches[1]
        return [PSCustomObject]@{
            Tier        = 'DefaultInternal'
            DisplayName = "pfo.current#$shortId"
            SortBucket  = 41
            ValueMode   = 'Default'
        }
    }

    if ($ActualName -match '^__pfo_([a-f0-9]{12})_out$') {
        $shortId = Get-CFGVariableStackShortId -Id $Matches[1]
        return [PSCustomObject]@{
            Tier        = 'AdvancedInternal'
            DisplayName = "pfo.output#$shortId"
            SortBucket  = 72
            ValueMode   = 'CollectionSummary'
        }
    }

    if ($ActualName -match '^__sw_([a-f0-9]{12})_idx$') {
        $shortId = Get-CFGVariableStackShortId -Id $Matches[1]
        return [PSCustomObject]@{
            Tier        = 'DefaultInternal'
            DisplayName = "switch.index#$shortId"
            SortBucket  = 50
            ValueMode   = 'Default'
        }
    }

    if ($ActualName -match '^__sw_([a-f0-9]{12})_current$') {
        $shortId = Get-CFGVariableStackShortId -Id $Matches[1]
        return [PSCustomObject]@{
            Tier        = 'DefaultInternal'
            DisplayName = "switch.current#$shortId"
            SortBucket  = 51
            ValueMode   = 'Default'
        }
    }

    if ($ActualName -match '^__sw_([a-f0-9]{12})$') {
        $shortId = Get-CFGVariableStackShortId -Id $Matches[1]
        return [PSCustomObject]@{
            Tier        = 'AdvancedInternal'
            DisplayName = "switch.collection#$shortId"
            SortBucket  = 73
            ValueMode   = 'CollectionSummary'
        }
    }

    if ($ActualName -match '^__fe_([a-f0-9]{12})_idx$') {
        $shortId = Get-CFGVariableStackShortId -Id $Matches[1]
        return [PSCustomObject]@{
            Tier        = 'DefaultInternal'
            DisplayName = "foreach.index#$shortId"
            SortBucket  = 60
            ValueMode   = 'Default'
        }
    }

    if ($ActualName -match '^__fe_([a-f0-9]{12})$') {
        $shortId = Get-CFGVariableStackShortId -Id $Matches[1]
        return [PSCustomObject]@{
            Tier        = 'AdvancedInternal'
            DisplayName = "foreach.collection#$shortId"
            SortBucket  = 74
            ValueMode   = 'CollectionSummary'
        }
    }

    if ($ActualName -match '^_sc_([a-f0-9]{8})_(.+)$') {
        $shortId = Get-CFGVariableStackShortId -Id $Matches[1]
        $logicalName = [string]$Matches[2]
        return [PSCustomObject]@{
            Tier        = 'AdvancedInternal'
            DisplayName = "`$$logicalName @scope#$shortId"
            SortBucket  = 80
            ValueMode   = 'Default'
        }
    }

    if (Test-CFGInternalVariableName -Name $ActualName) {
        return [PSCustomObject]@{
            Tier        = 'HiddenInternal'
            DisplayName = $ActualName
            SortBucket  = 90
            ValueMode   = 'Default'
        }
    }

    return [PSCustomObject]@{
        Tier        = 'User'
        DisplayName = $ActualName
        SortBucket  = 0
        ValueMode   = 'Default'
    }
}

function Format-CFGVariableStackValue {
    param(
        $Value,
        [string]$Mode = 'Default'
    )

    if ($Mode -ne 'CollectionSummary') {
        return Format-VariableValue $Value
    }

    if ($null -eq $Value) {
        return '$null'
    }

    if ($Value -is [string] -or $Value -isnot [System.Collections.IEnumerable]) {
        return Format-VariableValue $Value
    }

    $knownCount = $null
    if ($Value -is [array]) {
        $knownCount = $Value.Length
    } elseif ($Value -is [System.Collections.ICollection]) {
        try { $knownCount = [int]$Value.Count } catch { $knownCount = $null }
    }

    $items = New-Object System.Collections.Generic.List[string]
    $idx = 0
    $hasMore = $false
    foreach ($item in $Value) {
        if ($idx -ge 3) {
            $hasMore = $true
            break
        }
        $items.Add((Format-VariableValue -Value $item -Depth 1))
        $idx++
    }

    if (-not $hasMore -and $null -ne $knownCount -and $knownCount -gt $idx) {
        $hasMore = $true
    }

    $typeName = $Value.GetType().Name
    $itemsText = $items -join ', '
    $suffix = if ($hasMore) { ', ...' } else { '' }
    if ($null -ne $knownCount) {
        return "[$typeName] Count=$knownCount @($itemsText$suffix)"
    }
    return "[$typeName] @($itemsText$suffix)"
}
function Resolve-CFGVariableStackActualName {
    param(
        [hashtable]$Context,
        [string]$VariableName
    )

    if ($null -eq $VariableName) { return $VariableName }

    $name = [string]$VariableName
    if ($name.StartsWith('$')) {
        $name = $name.Substring(1)
    }

    if ($name -eq 'pipeline.current') {
        return '_'
    }

    if ($name -match '^_sc_[a-f0-9]{8}_') {
        return $name
    }

    if ($Context.ScopeStack.Count -gt 0) {
        $currentScope = $Context.ScopeStack[-1]
        if ($currentScope.LocalVars -and $name -in $currentScope.LocalVars) {
            return ($currentScope.ScopePrefix + $name)
        }
    }

    return $name
}

function Test-CFGVariableStackTierVisible {
    param(
        [string]$Tier,
        [switch]$IncludeInternal,
        [switch]$IncludeAdvancedInternal
    )

    if ($IncludeInternal) { return $true }
    if ($Tier -eq 'HiddenInternal') { return $false }
    if ($Tier -eq 'AdvancedInternal' -and -not $IncludeAdvancedInternal) { return $false }
    return $true
}

function Get-CFGVariableStackPlaceholderRows {
    param(
        [Parameter(Mandatory)][hashtable]$Session,
        [string[]]$ExistingActualNames = @(),
        [switch]$IncludeInternal,
        [switch]$IncludeAdvancedInternal
    )

    $context = $Session.Context
    $rows = New-Object System.Collections.Generic.List[object]
    $seenActualNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($name in @($ExistingActualNames)) {
        if ($null -ne $name) {
            $null = $seenActualNames.Add([string]$name)
        }
    }

    $addFromNode = {
        param($Node, [string]$Source)

        if (-not $Node) { return }
        $varInfos = @(Get-CFGNodeVarInfos -Node $Node -PropertyName 'VarsRead') + @(Get-CFGNodeVarInfos -Node $Node -PropertyName 'VarsWritten')
        foreach ($varInfo in @($varInfos)) {
            if ($null -eq $varInfo -or $null -eq $varInfo.Name) { continue }

            $actualName = Resolve-CFGVariableStackActualName -Context $context -VariableName ([string]$varInfo.Name)
            if ($null -eq $actualName) { continue }
            Register-CFGTrackedEnvironmentVariable -Context $context -ActualName $actualName
            if ($seenActualNames.Contains($actualName)) { continue }

            $descriptor = Get-CFGVariableStackDescriptor -ActualName $actualName
            if (-not (Test-CFGVariableStackTierVisible -Tier $descriptor.Tier -IncludeInternal:$IncludeInternal -IncludeAdvancedInternal:$IncludeAdvancedInternal)) {
                continue
            }

            $isInternal = Test-CFGInternalVariableName -Name $actualName
            $currentValue = $null
            $isPlaceholder = $true
            $placeholderValueText = '(missing; set manually)'
            if (-not [string]::IsNullOrWhiteSpace((Get-CFGEnvironmentVariableActualName -Name $actualName))) {
                $currentValue = Get-VariableFromContext -ExecContext $context.ExecContext -Name $actualName
                if ($null -ne $currentValue) {
                    $isPlaceholder = $false
                    $placeholderValueText = Format-CFGVariableStackValue -Value $currentValue -Mode $descriptor.ValueMode
                }
            }

            $rows.Add([PSCustomObject]@{
                DisplayName       = $descriptor.DisplayName
                ActualName        = $actualName
                IsInternal        = $isInternal
                DisplayTier       = $descriptor.Tier
                SortBucket        = [int]$descriptor.SortBucket
                Value             = $currentValue
                ValueText         = $placeholderValueText
                IsPlaceholder     = $isPlaceholder
                PlaceholderSource = $Source
            }) | Out-Null
            $null = $seenActualNames.Add($actualName)
        }
    }

    if ($Session.CurrentNode) {
        & $addFromNode $Session.CurrentNode 'CurrentNode'
    }

    if ($Session.History -and $Session.History.Count -gt 0) {
        $lastRecord = $Session.History[$Session.History.Count - 1]
        $hasFailure = $false
        if ($lastRecord) {
            if ($lastRecord.PSObject.Properties['Success'] -and -not [bool]$lastRecord.Success) {
                $hasFailure = $true
            }
            if (-not $hasFailure -and $lastRecord.PSObject.Properties['Error'] -and -not [string]::IsNullOrWhiteSpace([string]$lastRecord.Error)) {
                $hasFailure = $true
            }
        }
        if ($hasFailure -and $lastRecord.PSObject.Properties['NodeId']) {
            $lastNode = Get-NodeById -CFG $Session.CFG -Id ([int]$lastRecord.NodeId)
            if ($lastNode) {
                & $addFromNode $lastNode 'LastFailedNode'
            }
        }
    }

    return $rows.ToArray()
}

function Get-CFGVariableStack {
    param(
        [Parameter(Mandatory)][hashtable]$Session,
        [switch]$IncludeInternal,
        [switch]$IncludeAdvancedInternal
    )

    $context = $Session.Context
    $eval = Invoke-InContext -ExecContext $context.ExecContext -Code "Get-Variable | Select-Object Name, Value"
    if (-not $eval.Success -or $null -eq $eval.Result) { return @() }

    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($item in @($eval.Result)) {
        if ($null -eq $item -or -not $item.PSObject.Properties['Name']) { continue }
        $actualName = [string]$item.Name
        if ([string]::IsNullOrWhiteSpace($actualName)) { continue }

        $isInternal = Test-CFGInternalVariableName -Name $actualName
        $descriptor = Get-CFGVariableStackDescriptor -ActualName $actualName
        if (-not (Test-CFGVariableStackTierVisible -Tier $descriptor.Tier -IncludeInternal:$IncludeInternal -IncludeAdvancedInternal:$IncludeAdvancedInternal)) {
            continue
        }

        [void]$rows.Add([PSCustomObject]@{
            DisplayName       = $descriptor.DisplayName
            ActualName        = $actualName
            IsInternal        = $isInternal
            DisplayTier       = $descriptor.Tier
            SortBucket        = [int]$descriptor.SortBucket
            Value             = if ($item.PSObject.Properties['Value']) { $item.Value } else { $null }
            ValueText         = if ($item.PSObject.Properties['Value']) { Format-CFGVariableStackValue -Value $item.Value -Mode $descriptor.ValueMode } else { '$null' }
            IsPlaceholder     = $false
            PlaceholderSource = $null
        })
    }

    if ($context.ContainsKey('TrackedEnvironmentVariables') -and $context.TrackedEnvironmentVariables) {
        foreach ($trackedEnvName in @($context.TrackedEnvironmentVariables.Keys | Sort-Object)) {
            $actualName = [string]$trackedEnvName
            if ([string]::IsNullOrWhiteSpace($actualName)) { continue }

            $existing = @($rows | Where-Object { [string]$_.ActualName -ieq $actualName })
            if ($existing.Count -gt 0) { continue }

            $descriptor = Get-CFGVariableStackDescriptor -ActualName $actualName
            if (-not (Test-CFGVariableStackTierVisible -Tier $descriptor.Tier -IncludeInternal:$IncludeInternal -IncludeAdvancedInternal:$IncludeAdvancedInternal)) {
                continue
            }

            $value = Get-VariableFromContext -ExecContext $context.ExecContext -Name $actualName
            $isMissing = ($null -eq $value)
            [void]$rows.Add([PSCustomObject]@{
                DisplayName       = $descriptor.DisplayName
                ActualName        = $actualName
                IsInternal        = $false
                DisplayTier       = $descriptor.Tier
                SortBucket        = [int]$descriptor.SortBucket
                Value             = $value
                ValueText         = if ($isMissing) { '(missing; set manually)' } else { Format-CFGVariableStackValue -Value $value -Mode $descriptor.ValueMode }
                IsPlaceholder     = $isMissing
                PlaceholderSource = if ($isMissing) { 'TrackedEnvironment' } else { $null }
            })
        }
    }

    $existingActualNames = New-Object System.Collections.Generic.List[string]
    foreach ($row in $rows) {
        [void]$existingActualNames.Add([string]$row.ActualName)
    }
    foreach ($placeholder in @(Get-CFGVariableStackPlaceholderRows -Session $Session -ExistingActualNames $existingActualNames.ToArray() -IncludeInternal:$IncludeInternal -IncludeAdvancedInternal:$IncludeAdvancedInternal)) {
        [void]$rows.Add($placeholder)
    }

    $sortedRows = if ($rows.Count -le 1) {
        @($rows.ToArray())
    } else {
        @($rows.ToArray() | Sort-Object SortBucket, DisplayName, ActualName)
    }

    $uniqueRows = New-Object System.Collections.Generic.List[object]
    $seenKeys = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($row in $sortedRows) {
        $key = "{0}`0{1}" -f [string]$row.DisplayName, [string]$row.ActualName
        if ($seenKeys.Add($key)) {
            [void]$uniqueRows.Add($row)
        }
    }

    return $uniqueRows.ToArray()
}

function Set-CFGVariableValue {
    param(
        [Parameter(Mandatory)][hashtable]$Session,
        [Parameter(Mandatory)][string]$VariableName,
        [Parameter(Mandatory)][string]$ValueExpression
    )

    if ([string]::IsNullOrWhiteSpace($VariableName)) {
        throw "VariableName 不能为空。"
    }
    if ([string]::IsNullOrWhiteSpace($ValueExpression)) {
        throw "ValueExpression 不能为空。"
    }

    $context = $Session.Context
    $tokens = $null
    $errors = $null
    $exprAst = [System.Management.Automation.Language.Parser]::ParseInput($ValueExpression, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count -gt 0) {
        throw "变量值表达式解析失败: $($errors[0].Message)"
    }

    $cmdAsts = @($exprAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true))
    foreach ($cmdAst in $cmdAsts) {
        $cmdName = $cmdAst.GetCommandName()
        if ([string]::IsNullOrWhiteSpace($cmdName)) { continue }
        if ($context.ForbiddenCommands -contains $cmdName) {
            throw "变量值表达式包含禁用命令: $cmdName"
        }
    }

    $evalResult = Invoke-InContext -ExecContext $context.ExecContext -Code "($ValueExpression)"
    if (-not $evalResult.Success) {
        throw "变量值求值失败: $($evalResult.Error)"
    }

    $valueToSet = Normalize-ExecutionResultValue -Value $evalResult.Result -TreatArraysAsSequence

    $resolvedName = Resolve-CFGVariableStackActualName -Context $context -VariableName $VariableName
    $envActualName = Get-CFGEnvironmentVariableActualName -Name $resolvedName
    if (-not [string]::IsNullOrWhiteSpace($envActualName)) {
        Register-CFGTrackedEnvironmentVariable -Context $context -ActualName $envActualName

        $envLeafName = Get-CFGEnvironmentVariableLeafName -Name $envActualName
        $escapedEnvLeafName = $envLeafName.Replace("'", "''")
        $tempVarName = '__cfg_env_value_to_set'

        try {
            $context.ExecContext.Runspace.SessionStateProxy.SetVariable($tempVarName, $valueToSet)
            $setCode = if ($null -eq $valueToSet) {
                "[System.Environment]::SetEnvironmentVariable('$escapedEnvLeafName', \$null, 'Process') | Out-Null"
            } else {
                "[System.Environment]::SetEnvironmentVariable('$escapedEnvLeafName', [string]`$$tempVarName, 'Process') | Out-Null"
            }

            $setEnvResult = Invoke-InContext -ExecContext $context.ExecContext -Code $setCode
            if (-not $setEnvResult.Success) {
                throw "环境变量写入失败: $($setEnvResult.Error)"
            }
        } finally {
            try { $context.ExecContext.Runspace.SessionStateProxy.PSVariable.Remove($tempVarName) } catch { }
        }

        $storedValue = Get-VariableFromContext -ExecContext $context.ExecContext -Name $envActualName
        return [PSCustomObject]@{
            Name      = $envActualName
            Value     = $storedValue
            ValueText = if ($null -eq $storedValue) { '$null' } else { Format-VariableValue $storedValue }
        }
    }

    $targetNames = @($resolvedName)
    if ($VariableName -in @('_', 'PSItem', 'pipeline.current') -or $resolvedName -in @('_', 'PSItem')) {
        $targetNames = @('_', 'PSItem')
    }

    foreach ($targetName in $targetNames) {
        $context.ExecContext.Runspace.SessionStateProxy.SetVariable($targetName, $valueToSet)
    }

    return [PSCustomObject]@{
        Name      = ($targetNames -join ', ')
        Value     = $valueToSet
        ValueText = Format-VariableValue $valueToSet
    }
}

function Get-CFGNextEdgePreview {
    param(
        [Parameter(Mandatory)][hashtable]$Session
    )

    if ($Session.IsCompleted -or $null -eq $Session.CurrentNode) {
        return [PSCustomObject]@{
            HasPreview         = $false
            NodeId             = $null
            NodeType           = $null
            EdgeLabel          = $null
            ToNodeId           = $null
            PredictedCondition = $null
            Error              = $null
        }
    }

    $context = $Session.Context
    $node = Resolve-CFGNodeValue -CFG $context.CFG -Value $Session.CurrentNode
    if ($null -eq $node) {
        return [PSCustomObject]@{
            HasPreview         = $false
            NodeId             = $null
            NodeType           = $null
            EdgeLabel          = $null
            ToNodeId           = $null
            PredictedCondition = $null
            Error              = 'Current CFG node could not be resolved.'
        }
    }
    $Session.CurrentNode = $node
    $conditionTypes = @('Condition', 'ForEachCondition', 'ProcessCondition', 'SwitchCondition', 'CaseCondition')

    if ($node.Type -in $conditionTypes) {
        $code = Convert-CodeForCurrentScope -Code ([string]$node.Text) -Context $context
        $eval = Invoke-InContext -ExecContext $context.ExecContext -Code $code
        if (-not $eval.Success) {
            return [PSCustomObject]@{
                HasPreview         = $false
                NodeId             = $node.Id
                NodeType           = $node.Type
                EdgeLabel          = $null
                ToNodeId           = $null
                PredictedCondition = $null
                Error              = $eval.Error
            }
        }

        $pred = $false
        $predItems = [object[]]@(Get-ExecutionResultItems -Value $eval.Result -TreatArraysAsSequence)
        if ($predItems.Count -gt 0) {
            $pred = [bool]$predItems[0]
        }
        $label = Get-CFGConditionEdgeLabel -NodeType $node.Type -ConditionValue $pred
        $edge = Get-CFGOutgoingEdges -CFG $context.CFG -FromNodeId $node.Id | Where-Object { $_.Label -eq $label } | Select-Object -First 1
        $toNodeId = if ($edge) { [int]$edge.To } else { $null }

        return [PSCustomObject]@{
            HasPreview         = [bool]$edge
            NodeId             = $node.Id
            NodeType           = $node.Type
            EdgeLabel          = $label
            ToNodeId           = $toNodeId
            PredictedCondition = $pred
            Error              = $null
        }
    }

    $nextNodes = @(ConvertTo-CFGNodeArray -CFG $context.CFG -Value (Get-NextNodes -CFG $context.CFG -Node $node -Context $context))
    if ($nextNodes.Count -eq 0) {
        return [PSCustomObject]@{
            HasPreview         = $false
            NodeId             = $node.Id
            NodeType           = $node.Type
            EdgeLabel          = $null
            ToNodeId           = $null
            PredictedCondition = $null
            Error              = $null
        }
    }

    $nextNode = Resolve-CFGNodeValue -CFG $context.CFG -Value $nextNodes[0]
    if ($null -eq $nextNode) {
        return [PSCustomObject]@{
            HasPreview         = $false
            NodeId             = $node.Id
            NodeType           = $node.Type
            EdgeLabel          = $null
            ToNodeId           = $null
            PredictedCondition = $null
            Error              = 'Next CFG node could not be resolved.'
        }
    }
    $label = Get-CFGEdgeLabel -CFG $context.CFG -FromNodeId $node.Id -ToNodeId $nextNode.Id
    return [PSCustomObject]@{
        HasPreview         = $true
        NodeId             = $node.Id
        NodeType           = $node.Type
        EdgeLabel          = $label
        ToNodeId           = $nextNode.Id
        PredictedCondition = $null
        Error              = $null
    }
}
