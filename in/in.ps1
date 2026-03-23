Set-Alias -name input -val Invoke-WebRequest
Set-Alias -name output -val Invoke-Expression

$c = (input "xxx").Content
output $c
