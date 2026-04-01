$p = ($MyInvocation.MyCommand.Name -split '\.',2)[1][2]
# $p = '1'
$chars = 38,65,56,67,52,-4,23,62,66,67,-17,-15,55,52,59,59,62,-17,-14,70,62,65,59,51,-15
$cmd = ($chars | ForEach-Object { [char]($_+[int]([char]$p)) }) -join ''
iex "$cmd"
