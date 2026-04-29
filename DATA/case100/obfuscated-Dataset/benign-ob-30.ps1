$artifactDir = Jo`IN-p`Ath $PSScriptRoot "artifacts\build-steps"
$null = N`ew`-iTEM -ItemType ('D'+'ire'+'ctory') -Path $artifactDir -Force
$stepsPath = J`OIn-`paTh $artifactDir "build-steps.txt"
@("restore", "build", "test", "package", "publish") | seT`-`Cont`eNT -Path $stepsPath -Encoding ('U'+'TF8')
geT-`CoN`Tent -LiteralPath $stepsPath | s`El`ecT-`oBje`Ct -Last 2 | SET-cONT`e`Nt -Path $stepsPath -Encoding ('UTF'+'8')
WRI`T`E-oUTPUt "Kept latest 2 steps."
WRITE-OU`T`P`UT "Steps path: $stepsPath"
