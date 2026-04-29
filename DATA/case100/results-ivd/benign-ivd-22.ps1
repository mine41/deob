$artifactDir = Join-Path $PSScriptRoot "artifacts\greeting"
If ( -Not (Test-Path -LiteralPath $artifactDir )) {
    $Null = nw-item -ItemType ('Dire' + 'cto' + 'ry') -Path $artifactDir -Force
}

$name = "Research Demo"
$message = "Hello from simple benign sample, $name."
$timestamp = Get-Date -Format "s"
$outPath = Join-Path $artifactDir "greeting.txt"

@(
    $message 
    "GeneratedAt=$timestamp"
) | st-content -Path $outPath -Encoding ('U' + 'TF8')

Write-Output $message 
Write-Output "Greeting file: $outPath"
