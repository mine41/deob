powershell -NoProfile -Command {
    Try {
        [System.Management.Automation.Language.Parser]::ParseFile("Generate-CFG.ps1",[ref]$null,[ref]$null)
    } Catch {
        Write-Host "Parser error:" $_
    }
}
