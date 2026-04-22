$artifactDir = JO`in-pA`TH $PSScriptRoot "artifacts\release-preview"
$null = New-Item -ItemType ('Di'+'recto'+'ry') -Path $artifactDir -Force
$notesPath = Join-Path $artifactDir "release-notes.txt"
$previewPath = Join-Path $artifactDir "release-preview.txt"
@("intro", "features", "fixes", "faq") | Set-Content -Path $notesPath -Encoding ('UT'+'F8')
Get-Content -LiteralPath $notesPath | Select-Object -First 3 | Set-Content -Path $previewPath -Encoding ('UTF'+'8')
Write-Output "Selected first 3 release notes."
Write-Output "Preview path: $previewPath"
