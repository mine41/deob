$artifactDir = Join-Path $PSScriptRoot "artifacts\template"
if (-not (Test-Path -LiteralPath $artifactDir)) {
    $null = New-Item -ItemType Directory -Path $artifactDir -Force
}

$template = @"
Welcome, {{Name}}.
Your workspace room is {{Room}}.
Report date: {{Date}}.
"@

$result = @'
Welcome, Analyst Team.
Your workspace room is B-204.
Report date: 2026-04-22.
'@

$outPath = Join-Path $artifactDir "welcome-message.txt"
@'
Welcome, Analyst Team.
Your workspace room is B-204.
Report date: 2026-04-22.
'@ | Set-Content -Path $outPath -Encoding UTF8

Write-Output "Rendered welcome template."
Write-Output "Output path: $outPath"

