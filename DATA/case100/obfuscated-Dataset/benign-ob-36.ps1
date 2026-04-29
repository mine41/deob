$artifactDir = JO`in-pA`TH $PSScriptRoot "artifacts\release-preview"
$null = neW-i`T`em -ItemType ('Di'+'recto'+'ry') -Path $artifactDir -Force
$notesPath = JOIN`-PA`TH $artifactDir "release-notes.txt"
$previewPath = J`oIn`-pATh $artifactDir "release-preview.txt"
@("intro", "features", "fixes", "faq") | S`et`-C`oNTEnt -Path $notesPath -Encoding ('UT'+'F8')
g`Et-Co`NtEnt -LiteralPath $notesPath | s`elecT-o`B`j`ecT -First 3 | seT-`C`oN`TenT -Path $previewPath -Encoding ('UTF'+'8')
W`RIte-OUTP`UT "Selected first 3 release notes."
wRite-`OUTP`Ut "Preview path: $previewPath"
