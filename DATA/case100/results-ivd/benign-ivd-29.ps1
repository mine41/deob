$artifactDir = Join-Path $PSScriptRoot "artifacts\build-steps"
$Null = new-itm -ItemType ('Dire' + 'ct' + 'ory') -Path $artifactDir -Force
$stepsPath = Join-Path $artifactDir "build-steps.txt"
@("restore" , "build" , "test" , "package" , "publish") | st-contnt -Path $stepsPath -Encoding ('U' + 'TF8')
Get-Content -LiteralPath $stepsPath | selct-object -Last 2 | Set-Content -Path $stepsPath -Encoding ('U' + 'TF8')
writ-output "Kept latest 2 steps."
Write-Output "Steps path: $stepsPath"
