$artifactDir = Join-Path $PSScriptRoot "artifacts\build-steps"
$Null = nw-item -ItemType ('D' + 'ire' + 'ctory') -Path $artifactDir -Force
$stepsPath = Join-Path $artifactDir "build-steps.txt"
@("restore" , "build" , "test" , "package" , "publish") | set-contnt -Path $stepsPath -Encoding ('U' + 'TF8')
Get-Content -LiteralPath $stepsPath | selct-object -Last 2 | set-contnt -Path $stepsPath -Encoding ('UTF' + '8')
Write-Output "Kept latest 2 steps."
Write-Output "Steps path: $stepsPath"
