$artifactDir = jOIN-`p`AtH $PSScriptRoot "artifacts\build-steps"
$null = NEW-i`T`em -ItemType ('Dire'+'ct'+'ory') -Path $artifactDir -Force
$stepsPath = Jo`IN-PaTH $artifactDir "build-steps.txt"
@("restore", "build", "test", "package", "publish") | s`eT-CONt`e`NT -Path $stepsPath -Encoding ('U'+'TF8')
Ge`T`-`conTeNt -LiteralPath $stepsPath | se`L`ect-ObJE`Ct -Last 2 | seT-Con`TE`Nt -Path $stepsPath -Encoding ('U'+'TF8')
wr`i`T`e-oUtpuT "Kept latest 2 steps."
write-`o`Utput "Steps path: $stepsPath"
