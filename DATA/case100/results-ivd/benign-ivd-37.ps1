$artifactDir = Join-Path $PSScriptRoot "artifacts\release-preview"
$Null = New-Item -ItemType ('Directo' + 'r' + 'y') -Path $artifactDir -Force
$notesPath = Join-Path $artifactDir "release-notes.txt"
$previewPath = Join-Path $artifactDir "release-preview.txt"
@("intro" , "features" , "fixes" , "faq") | set-contnt -Path $notesPath -Encoding ('UT' + 'F8')
get-contnt -LiteralPath $notesPath | slect-object -First 3 | Set-Content -Path $previewPath -Encoding ('U' + 'TF8')
Write-Output "Selected first 3 release notes."
Write-Output "Preview path: $previewPath"
