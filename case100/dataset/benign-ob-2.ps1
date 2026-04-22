$artifactDir = JOin`-pa`TH $PSScriptRoot "artifacts\tasks"
if (-not (TE`sT`-paTH -LiteralPath $artifactDir)) {
    $null = Ne`w`-itEM -ItemType ('D'+'irecto'+'ry') -Path $artifactDir -Force
}

$planned = @("draft", "review", "publish", "archive")
$completed = @("draft", "review", "archive", "notify")

$pending = $planned | wh`ERe-o`Bj`ect { $_ -notin $completed }
$unexpected = $completed | W`hERE-`objeCt { $_ -notin $planned }
$reportPath = J`oIn-PatH $artifactDir "task-comparison.txt"

@(
    "Pending Tasks: $($pending -join ', ')"
    "Unexpected Tasks: $($unexpected -join ', ')"
) | s`Et-`cOnt`enT -Path $reportPath -Encoding ('UT'+'F8')

w`R`ITE-`OUTPut "Compared task lists."
wr`i`T`e-oUtpUt "Report path: $reportPath"
