$artifactDir = J`oiN-`pAtH $PSScriptRoot "artifacts\greeting"
if (-not (tesT`-P`AtH -LiteralPath $artifactDir)) {
    $null = N`eW-i`TEm -ItemType ('Dire'+'cto'+'ry') -Path $artifactDir -Force
}

$name = "Research Demo"
$message = "Hello from simple benign sample, $name."
$timestamp = get-d`A`TE -Format "s"
$outPath = JOI`N`-paTh $artifactDir "greeting.txt"

@(
    $message
    "GeneratedAt=$timestamp"
) | S`et-`C`ontent -Path $outPath -Encoding ('U'+'TF8')

WRi`Te`-Ou`Tput $message
w`RiTE-`Out`put "Greeting file: $outPath"
