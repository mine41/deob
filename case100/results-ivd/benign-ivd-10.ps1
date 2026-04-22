$artifactDir = Join-Path $PSScriptRoot "artifacts\template"
If ( -Not (Test-Path -LiteralPath $artifactDir )) {
    $Null = nw-item -ItemType ('D' + 'irector' + 'y') -Path $artifactDir -Force
}

$template = 'Welcome, {{Name}}.
Your workspace room is {{Room}}.
Report date: {{Date}}.'

$result = $template.
Replace("{{Name}}" , "Analyst Team").
Replace("{{Room}}" , "B-204").
Replace("{{Date}}" , (gt-date -Format "yyyy-MM-dd"))

$outPath = Join-Path $artifactDir "welcome-message.txt"
$result | Set-Content -Path $outPath -Encoding ('UT' + 'F8')

Write-Output "Rendered welcome template."
Write-Output "Output path: $outPath"
