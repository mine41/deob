${a`RTiF`Act`dIR} = J`O`In-Pa`Th ${pSSC`RIptR`oot} "artifacts\queue-preview"
${NU`ll} = N`Ew`-ItEM -ItemType Directory -Path ${ARTi`F`ACt`dIR} -Force
${Q`Ue`UEpA`Th} = jO`in-P`Ath ${Art`IfaCTd`ir} "queue.txt"
${PR`E`VI`eWpAth} = J`oiN`-PaTh ${AR`Ti`Factd`Ir} "queue-preview.txt"
@("ingest", "review", "approve", "archive") | se`T`-CoNTent -Path ${qu`e`U`EpATh} -Encoding UTF8
G`et-co`NtEnT -LiteralPath ${qU`eu`eP`ATH} | s`elEC`T-`oBjEct -First 2 | SEt-`CoNT`eNt -Path ${pr`e`VieWpaTh} -Encoding UTF8
wr`ITe-`OUTpUT "Selected first 2 queue items."
wr`iTe`-oU`TPuT "Preview path: $previewPath"
