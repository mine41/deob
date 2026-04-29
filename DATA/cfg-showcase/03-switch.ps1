$kind = 'b'

switch ($kind) {
    'a' { Write-Output 'alpha' }
    'b' { Write-Output 'beta' }
    default { Write-Output 'other' }
}
