$artifactDir = Join-Path $PSScriptRoot "artifacts\json"
$null = New-Item -ItemType Directory -Path $artifactDir -Force
$rulesPath = Join-Path $artifactDir "alert-rules.json"
[ordered]@{ Channel = "email"; Level = "info"; QuietHours = "22:00-07:00" } | ConvertTo-Json | Set-Content -Path $rulesPath -Encoding UTF8
$loaded = Get-Content -LiteralPath $rulesPath -Raw | ConvertFrom-Json
Write-Output "Saved alert rules."
Write-Output "Channel: $($loaded.Channel)"

