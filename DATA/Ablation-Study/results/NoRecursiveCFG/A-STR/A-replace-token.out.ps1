$url = ('hxxps://example[.]org/api/v1/update.bin' -replace 'hxxps', 'https' -replace '\[\.]', '.')
Write-Output ([string]'https://example.org/api/v1/update.bin')

