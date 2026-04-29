$artifactDir = Join-Path $PSScriptRoot "artifacts\release-preview"
$null = New-Item -ItemType Directory -Path $artifactDir -Force
$notesPath = Join-Path $artifactDir "release-notes.txt"
$previewPath = Join-Path $artifactDir "release-preview.txt"
@("intro", "features", "fixes", "faq") | Set-Content -Path $notesPath -Encoding UTF8
Get-Content -LiteralPath $notesPath | Select-Object -First 3 | Set-Content -Path $previewPath -Encoding UTF8
Write-Output "Selected first 3 release notes."
Write-Output "Preview path: $previewPath"
