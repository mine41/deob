[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BeforePath,
    [Parameter(Mandatory = $true)][string]$AfterPath
)

$before = [System.IO.File]::ReadAllText($BeforePath)
$after  = [System.IO.File]::ReadAllText($AfterPath)

# Parse tokens first so blank or comment-only scripts are treated as failed.
$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseInput($after, [ref]$tokens, [ref]$errors) | Out-Null

$meaningfulTokens = @(
    $tokens | Where-Object {
        $_.Kind -ne [System.Management.Automation.Language.TokenKind]::Comment -and
        $_.Kind -ne [System.Management.Automation.Language.TokenKind]::NewLine -and
        $_.Kind -ne [System.Management.Automation.Language.TokenKind]::LineContinuation -and
        $_.Kind -ne [System.Management.Automation.Language.TokenKind]::EndOfInput
    }
)

if ($meaningfulTokens.Count -eq 0) {
    Write-Output "FAILED: empty or comment-only script"
    exit 2
}

if ($errors.Count -gt 0) {
    Write-Output "INVALID: syntax error"
    exit 1
}

# Compare visible characters by removing all whitespace.
$beforeVisible = $before -replace '\s', ''
$afterVisible  = $after  -replace '\s', ''
if ($beforeVisible -eq $afterVisible) {
    Write-Output "INVALID: identical to original"
    exit 1
}

Write-Output "VALID"
exit 0
