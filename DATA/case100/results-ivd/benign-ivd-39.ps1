$artifactDir = Join-Path $PSScriptRoot "artifacts\json"
$Null = New-Item -ItemType ('Di' + 'rector' + 'y') -Path $artifactDir -Force
$rulesPath = Join-Path $artifactDir "alert-rules.json"
[ordered]@{ channel = "email"; 
    level = "info"; 
    quiethours = "22:00-07:00" } | convrtto-json | Set-Content -Path $rulesPath -Encoding ('UT' + 'F8')
$loaded = Get-Content -LiteralPath $rulesPath -Raw | convrtfrom-json 
Write-Output "Saved alert rules."
Write-Output "Channel: $($loaded.Channel)"
