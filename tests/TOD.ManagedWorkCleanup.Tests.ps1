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
        Import-CleanupFunction -Name 'Ensure-Directory'
        Import-CleanupFunction -Name 'Get-TodManagedWorkPolicy'
        Import-CleanupFunction -Name 'Remove-UntrackedSupportArtifacts'
    }

    It 'plans to archive and restore tracked blocked files while archiving untracked support artifacts before removal' {
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
        [string]$policy.cleanup_strategy.support_cleanup_files[0].action | Should Be 'archive_then_remove_untracked_support_artifact'
        [string]$policy.cleanup_strategy.support_cleanup_files[0].archive_path | Should Match 'managed-work-archives'
    }

    It 'reports archive evidence when removing untracked support artifacts' {
        $caseRoot = Join-Path $TestDrive 'repo'
        $supportFile = Join-Path $caseRoot 'runtime_remote_training/tod_training_scratch/proof.json'
        $archiveFile = Join-Path $caseRoot 'shared_state/agentmim/managed-work-archives/case/runtime_remote_training/tod_training_scratch/proof.json'
        New-Item -ItemType Directory -Path (Split-Path -Parent $supportFile) -Force | Out-Null
        Set-Content -Path $supportFile -Value '{"ok":true}' -Encoding utf8

        $removed = Remove-UntrackedSupportArtifacts -ProjectRootPath $caseRoot -SupportFiles @(
            [pscustomobject]@{
                path = 'runtime_remote_training/tod_training_scratch/proof.json'
                archive_path = $archiveFile
            }
        )

        Test-Path -Path $supportFile | Should Be $false
        Test-Path -Path $archiveFile | Should Be $true
        @($removed).Count | Should Be 1
        [string]$removed[0].path | Should Be 'runtime_remote_training/tod_training_scratch/proof.json'
        [string]$removed[0].archive_path | Should Be $archiveFile
    }
}
