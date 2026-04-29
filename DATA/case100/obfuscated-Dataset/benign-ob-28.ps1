${arTIFaC`T`d`ir} = JoiN-p`A`Th ${p`SsCr`i`PtRoOt} "artifacts\build-steps"
${Nu`LL} = n`Ew-I`TEm -ItemType Directory -Path ${aRTI`F`A`ctDIR} -Force
${step`SP`Ath} = JoiN-p`A`Th ${A`RTifA`Ctd`IR} "build-steps.txt"
@("restore", "build", "test", "package", "publish") | s`et-cO`Nt`enT -Path ${S`TepS`Path} -Encoding UTF8
g`eT`-CoN`Tent -LiteralPath ${S`T`EpSPa`TH} | S`elEct-oB`Je`Ct -Last 2 | S`Et-cO`N`TEnT -Path ${STE`p`SpatH} -Encoding UTF8
w`RItE`-o`UTput "Kept latest 2 steps."
wRit`E-`oUT`pUt "Steps path: $stepsPath"
