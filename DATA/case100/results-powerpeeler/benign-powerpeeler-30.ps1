$artifactDir = Jo`IN-p`Ath $PSScriptRoot "artifacts\build-steps"
$null = New-Item -ItemType ('D'+'ire'+'ctory') -Path $artifactDir -Force
$stepsPath = Join-Path $artifactDir "build-steps.txt"
@("restore", "build", "test", "package", "publish") | Set-Content -Path $stepsPath -Encoding ('U'+'TF8')
Get-Content -LiteralPath $stepsPath | Select-Object -Last 2 | Set-Content -Path $stepsPath -Encoding ('UTF'+'8')
Write-Output "Kept latest 2 steps."
Write-Output "Steps path: $stepsPath"
