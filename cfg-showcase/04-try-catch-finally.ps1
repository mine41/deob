try {
    throw 'boom'
}
catch {
    Write-Output 'handled'
}
finally {
    Write-Output 'cleanup'
}
