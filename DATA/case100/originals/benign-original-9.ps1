$artifactDir = Join-Path $PSScriptRoot "artifacts\template"
if (-not (Test-Path -LiteralPath $artifactDir)) {
    $null = New-Item -ItemType Directory -Path $artifactDir -Force
}

$template = @"
Welcome, {{Name}}.
Your workspace room is {{Room}}.
Report date: {{Date}}.
"@

$result = $template.
    Replace("{{Name}}", "Analyst Team").
    Replace("{{Room}}", "B-204").
    Replace("{{Date}}", (Get-Date -Format "yyyy-MM-dd"))

$outPath = Join-Path $artifactDir "welcome-message.txt"
$result | Set-Content -Path $outPath -Encoding UTF8

Write-Output "Rendered welcome template."
Write-Output "Output path: $outPath"
