$artifactDir = J`OiN-p`ATh $PSScriptRoot "artifacts\template"
if (-not (test-P`A`TH -LiteralPath $artifactDir)) {
    $null = N`ew-i`TEm -ItemType ('D'+'irector'+'y') -Path $artifactDir -Force
}

$template = @"
Welcome, {{Name}}.
Your workspace room is {{Room}}.
Report date: {{Date}}.
"@

$result = $template.
    Replace("{{Name}}", "Analyst Team").
    Replace("{{Room}}", "B-204").
    Replace("{{Date}}", (g`et-DAte -Format "yyyy-MM-dd"))

$outPath = j`OI`N-pATH $artifactDir "welcome-message.txt"
$result | sET`-C`onte`NT -Path $outPath -Encoding ('UT'+'F8')

W`R`Ite-Ou`TpUT "Rendered welcome template."
Wr`iTE-`oUTP`UT "Output path: $outPath"
