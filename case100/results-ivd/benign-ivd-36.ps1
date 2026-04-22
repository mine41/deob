$artifactDir = Join-Path $PSScriptRoot "artifacts\release-preview"
$Null = new-itm -ItemType ('Di' + 'recto' + 'ry') -Path $artifactDir -Force
$notesPath = Join-Path $artifactDir "release-notes.txt"
$previewPath = Join-Path $artifactDir "release-preview.txt"
@("intro" , "features" , "fixes" , "faq") | st-content -Path $notesPath -Encoding ('UT' + 'F8')
Get-Content -LiteralPath $notesPath | slect-objct -First 3 | Set-Content -Path $previewPath -Encoding ('UTF' + '8')
Write-Output "Selected first 3 release notes."
Write-Output "Preview path: $previewPath"
