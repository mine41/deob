$artifactDir = J`oiN-`pAtH $PSScriptRoot "artifacts\greeting"
if (-not (Test-Path -LiteralPath $artifactDir)) {
    $null = N`eW-i`TEm -ItemType ('Dire'+'cto'+'ry') -Path $artifactDir -Force
}
$name = "Research Demo"
$message = "Hello from simple benign sample, $name."
$timestamp = Get-Date -Format "s"
$outPath = Join-Path $artifactDir "greeting.txt"
@(
    $message
    "GeneratedAt=$timestamp"
) | Set-Content -Path $outPath -Encoding ('U'+'TF8')
Write-Output $message
Write-Output "Greeting file: $outPath"
