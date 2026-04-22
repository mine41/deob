$artifactDir = jOIN-`p`AtH $PSScriptRoot "artifacts\build-steps"
$null = New-Item -ItemType ('Dire'+'ct'+'ory') -Path $artifactDir -Force
$stepsPath = Join-Path $artifactDir "build-steps.txt"
@("restore", "build", "test", "package", "publish") | Set-Content -Path $stepsPath -Encoding ('U'+'TF8')
Get-Content -LiteralPath $stepsPath | Select-Object -Last 2 | Set-Content -Path $stepsPath -Encoding ('U'+'TF8')
Write-Output "Kept latest 2 steps."
Write-Output "Steps path: $stepsPath"
