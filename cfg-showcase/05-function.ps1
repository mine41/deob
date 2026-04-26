function Get-Greeting {
    param(
        [string]$Name
    )

    return "Hello, $Name"
}

$result = Get-Greeting -Name 'CFG'
Write-Output $result
