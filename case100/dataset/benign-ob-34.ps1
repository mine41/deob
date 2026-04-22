$artifactDir = j`OIn-pa`TH $PSScriptRoot "artifacts\queue-preview"
$null = n`eW-It`EM -ItemType ('Director'+'y') -Path $artifactDir -Force
$queuePath = jO`In-`path $artifactDir "queue.txt"
$previewPath = J`OIN-Pa`Th $artifactDir "queue-preview.txt"
@("ingest", "review", "approve", "archive") | set-CO`NTe`NT -Path $queuePath -Encoding ('U'+'TF8')
get-con`T`ent -LiteralPath $queuePath | S`e`lECt-Ob`JEct -First 2 | s`eT`-conteNT -Path $previewPath -Encoding ('U'+'TF8')
Wr`iTe-O`UtpUT "Selected first 2 queue items."
Wri`TE-o`Ut`puT "Preview path: $previewPath"
