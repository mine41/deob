[CmdletBinding()]
param(
    [string]$OutputDir = (Join-Path $PSScriptRoot 'out')
)

$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $repoRoot 'Generate-CFG.ps1')
. (Join-Path $repoRoot 'Execute-CFG.ps1')

$null = New-Item -ItemType Directory -Path $OutputDir -Force

$samples = @(
    @{ Name = '01-if-elseif-else'; UseRuntimeExpansion = $false },
    @{ Name = '02-foreach'; UseRuntimeExpansion = $false },
    @{ Name = '03-switch'; UseRuntimeExpansion = $false },
    @{ Name = '04-try-catch-finally'; UseRuntimeExpansion = $false },
    @{ Name = '05-function'; UseRuntimeExpansion = $false },
    @{ Name = '06-iex'; UseRuntimeExpansion = $true }
)

foreach ($sample in $samples) {
    $scriptPath = Join-Path $PSScriptRoot ($sample.Name + '.ps1')
    $dotPath = Join-Path $OutputDir ($sample.Name + '.dot')

    Write-Host ("[CFG] {0}" -f $sample.Name) -ForegroundColor Cyan
    $cfg = Get-ScriptControlFlow -ScriptPath $scriptPath
    if ($null -eq $cfg) {
        throw "CFG generation failed: $scriptPath"
    }

    if ($sample.UseRuntimeExpansion) {
        $logPath = Join-Path $OutputDir ($sample.Name + '.execution.log')
        $session = New-CFGExecutionSession -CFG $cfg -LogPath $logPath -MaxIterations 200 -MaxTotalNodes 2000 -GlobalTimeBudgetMs 15000 -DynamicTimeBudgetMs 5000 -SafeMode $true
        try {
            $dynamicCreated = $false
            for ($i = 0; $i -lt 100 -and -not $session.IsCompleted; $i++) {
                $stepResult = Invoke-CFGStep -Session $session -StopAtUserNode:$false
                if ($session.Context.DynamicInvokeResults -and $session.Context.DynamicInvokeResults.Count -gt 0) {
                    $dynamicCreated = $true
                    break
                }
                if ($stepResult.Completed) {
                    break
                }
            }

            if (-not $dynamicCreated) {
                Write-Warning ("Dynamic subgraph was not created for {0}" -f $sample.Name)
            }
        }
        finally {
            Close-CFGExecutionSession -Session $session
        }
    }

    $pngPath = Export-CfgToDot -finalCFG $cfg -outputPath $dotPath
    if (-not $pngPath -or -not (Test-Path -LiteralPath $pngPath)) {
        throw "PNG generation failed: $dotPath"
    }
}

Write-Host ("Showcase PNGs written to: {0}" -f $OutputDir) -ForegroundColor Green
