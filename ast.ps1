function Get-Ast {
    param (
        [object] $InputObject
    )

    $ast = switch ($InputObject) {
        {$_ -is [string]} {
            if (Test-Path -LiteralPath $_) {
                $path = Resolve-Path -Path $_
                [System.Management.Automation.Language.Parser]::ParseFile($path.ProviderPath, [ref]$null, [ref]$null)
            }
            else {
                [System.Management.Automation.Language.Parser]::ParseInput($_, [ref]$null, [ref]$null)
            }
            break
        }
        {$_ -is [System.Management.Automation.FunctionInfo] -or
            $_ -is [System.Management.Automation.ExternalScriptInfo]} {
            $InputObject.ScriptBlock.Ast
            break
        }
        {$_ -is [scriptblock]} {
            $_.Ast
            break
        }
        Default {
            throw 'InputObject type not recognised'
        }
    }

    # $ast.FindAll({ $true }, $true)
    $ast
}

$InputObject = ".\in.ps1"
$ast = Get-Ast -InputObject $InputObject
# $ast.EndBlock.Statements[1].Clauses[0].item1
$ast.EndBlock.Statements[1].Variable.Extent.Text
