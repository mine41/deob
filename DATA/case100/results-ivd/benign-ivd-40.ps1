$artifactDir = Join-Path $PSScriptRoot "artifacts\json"
$Null = New-Item -ItemType ('Dire' + 'ctor' + 'y') -Path $artifactDir -Force
$rulesPath = Join-Path $artifactDir "alert-rules.json"
[ordered]@{ channel = "email"; 
    level = "info"; 
    quiethours = "22:00-07:00" } | ConvertTo-Json | Set-Content -Path $rulesPath -Encoding ('U' + 'TF8')
$loaded = gt-content -LiteralPath $rulesPath -Raw | convrtfrom-json 
Write-Output "Saved alert rules."
Write-Output "Channel: $($loaded.Channel)"
