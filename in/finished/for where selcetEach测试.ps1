# # ForEach-Object pipeline regression (execution + CFG traversal)



# # 1) Basic foreach-object
# process{
#     $numbers = 1..5
#     $r1 = $numbers | ForEach-Object { $_ * 2 }
# }


# $numbers = 1..5
# # 2) break should stop enumeration at $_ == 3
# $r2 = $numbers | ForEach-Object {
#     if ($_ -eq 3) { break }
#     $_
# }

# # 3) continue should skip $_ == 3
# $r3 = $numbers | ForEach-Object {
#     if ($_ -eq 3) { continue }
#     $_
# }

# # 4) foreach-object as middle pipeline element (needs to write back _pipe_ var)
# $r4 = $numbers | ForEach-Object { $_ * 2 } | ForEach-Object { $_ + 1 }

# # 5) nested foreach-object (tests $_ context isolation + stack restore)
# $r5 = 1..3 | ForEach-Object {
#     1..2 | ForEach-Object { $_ + 10 }
# }

# 8) Where-Object pipeline (FilterScript traversal + truthiness)
# $r8 = 1..5 | Where-Object { $_ -gt 2 }

# # Edge case: multiple $false outputs should still be truthy in PowerShell (non-empty output stream)
# $r9 = 1..3 | Where-Object { $false; $false }

# # Alias form: ? { ... }
# $r10 = 1..5 | ? { $_ -gt 2 }

# # Where-Object as middle pipeline element (needs to write back _pipe_ var)
# $r11 = 1..5 | Where-Object { $_ -gt 2 } | ForEach-Object { $_ + 100 }

# # Nested: Where-Object inside ForEach-Object scriptblock (tests $_ stack restore)
# $r12 = 10 | ForEach-Object {
#     1..3 | Where-Object { $_ -gt 1 } | ForEach-Object { $_ + 1000 }
# }

# # 6) begin/process/end form
# $r6 = 1..3 | ForEach-Object -Begin { $sum = 0 } -Process { $sum += $_ } -End { $sum }

# Write-Host "r1=$($r1.Count) r2=$($r2.Count) r3=$($r3.Count) r4=$($r4.Count) r5=$($r5.Count) r6=$r6"

# # 7) ForEach-Object inside a process block: inner scriptblock's $_ must NOT be replaced by outer process current
# end{
#     function Test-ProcessInnerForEach {
#         process {
#             $tmp = 1..2 | ForEach-Object { $_ }
#             $tmp
#         }
#     }

#     $r7 = 100 | Test-ProcessInnerForEach
# }

# # Select-Object pipeline regression (Property / Calculated / ExpandProperty)
# $obj1 = [pscustomobject]@{ A = 1; B = 2; Arr = @(1, 2); Str = 'ab'; Mixed = @($null, 1) }
# $obj2 = [pscustomobject]@{ A = 3; B = 4; Arr = @(3); Str = 'cd'; Mixed = @() }

# $r13 = @($obj1, $obj2) | Select-Object A, B
# $r14 = 1..3 | Select-Object @{ n = 'X'; e = { $_ + 1 } }
# $r15 = @($obj1) | Select-Object -ExpandProperty Arr
# $r16 = 1..10 | Select-Object -First 3 -Last 2 -Skip 2
# $r17 = 1..10 | Select-Object -Last 3 -Skip 2
# $r18 = 1..5 | Select-Object -Index 0, 10, 2