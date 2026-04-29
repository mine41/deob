$ARTiFacTdir = JOin-P`A`TH $PsSCriPtRoot "artifacts\release-preview"
$NUll = New-Item -ItemType Directory -Path $artIfACtDir -Force
$NOTESPATh = Join-Path $ArTiFACTDIR "release-notes.txt"
$pREVIEWpATh = Join-Path $ARtifactDiR "release-preview.txt"
@("intro", "features", "fixes", "faq") | Set-Content -Path $nOtesPATh -Encoding UTF8
Get-Content -LiteralPath $noTEsPatH | Select-Object -First 3 | Set-Content -Path $PrEvIeWPATh -Encoding UTF8
Write-Output "Selected first 3 release notes."
Write-Output "Preview path: $previewPath"
