Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $repoRoot 'scripts/Invoke-TODManagedWork.ps1'

function Import-CleanupFunction {
    param([Parameter(Mandatory = $true)][string]$Name)

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
    if (@($errors).Count -gt 0) {
        throw 'Failed to parse ' + $scriptPath
    }

    $fnAst = $ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name
    }, $true)

    if ($null -eq $fnAst) {
        throw "Function '$Name' not found in $scriptPath"
    }

    $definition = $fnAst.Extent.Text -replace ('function\s+{0}\b' -f [regex]::Escape($Name)), ('function global:{0}' -f $Name)
    . ([scriptblock]::Create($definition))
}

Describe 'TOD managed work cleanup policy' {
    BeforeAll {
        Import-CleanupFunction -Name 'Resolve-LocalPath'
        Import-CleanupFunction -Name 'Get-TodManagedWorkPolicy'
    }

    It 'plans to archive and restore tracked blocked files while removing only untracked support artifacts' {
        $report = [pscustomobject]@{
            patch_scope = [pscustomobject]@{
                blocked_scope = @(
                    [pscustomobject]@{ path = 'tod/data/engineering-memory.json'; status = 'modified' },
                    [pscustomobject]@{ path = 'tod/knowledge/engineering-memory/engine_performance_memory.json'; status = 'modified' }
                )
                support_or_reference_artifacts = @(
                    [pscustomobject]@{ path = 'tmp_live_project_status.json'; status = 'untracked' },
                    [pscustomobject]@{ path = 'raw-sweep-b25.txt'; status = 'modified' }
                )
            }
        }

        $policy = Get-TodManagedWorkPolicy -ManagedWorkReport $report

        @($policy.cleanup_strategy.blocked_tracked_files).Count | Should Be 2
        @($policy.cleanup_strategy.support_cleanup_files).Count | Should Be 1
        [string]$policy.cleanup_strategy.support_cleanup_files[0].path | Should Be 'tmp_live_project_status.json'
    }
}