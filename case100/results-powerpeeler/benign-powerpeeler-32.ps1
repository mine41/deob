$artifactDir = j`oiN-PA`Th $PSScriptRoot "artifacts\log-lines"
$null = New-Item -ItemType ('Direc'+'tor'+'y') -Path $artifactDir -Force
$logPath = Join-Path $artifactDir "recent.log"
@("alpha", "beta", "gamma", "delta", "epsilon") | Set-Content -Path $logPath -Encoding ('UT'+'F8')
Get-Content -LiteralPath $logPath | Select-Object -Last 3 | Set-Content -Path $logPath -Encoding ('UTF'+'8')
Write-Output "Kept latest 3 lines."
Write-Output "Log path: $logPath"
