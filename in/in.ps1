Get-Process | Where-Object { $_.CPU -gt 100 } | Select-Object Name, CPU | Sort-Object CPU -Descending | Format-Table -AutoSize

$a = Get-Process | Where-Object { $_.CPU -gt 100 } | Select-Object Name, CPU | Sort-Object CPU -Descending | Format-Table -AutoSize
