$artifactDir = JO`in-`PaTh $PSScriptRoot "artifacts\release-preview"
$null = NE`W-ITeM -ItemType ('Directo'+'r'+'y') -Path $artifactDir -Force
$notesPath = jOi`N`-pATH $artifactDir "release-notes.txt"
$previewPath = Join`-Pa`TH $artifactDir "release-preview.txt"
@("intro", "features", "fixes", "faq") | SEt-c`ONT`ent -Path $notesPath -Encoding ('UT'+'F8')
gET-coN`T`eNT -LiteralPath $notesPath | S`eLE`C`T-OBjeCt -First 3 | SEt-`coNTe`Nt -Path $previewPath -Encoding ('U'+'TF8')
wrI`Te-O`UTPut "Selected first 3 release notes."
WRIte`-ou`TPUt "Preview path: $previewPath"
