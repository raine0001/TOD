Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $repoRoot 'scripts/Invoke-TODProjectManagedWork.ps1'

function Import-ManagedWorkFunction {
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

Describe 'TOD project managed work classification' {
    BeforeAll {
        Import-ManagedWorkFunction -Name 'To-Array'
        Import-ManagedWorkFunction -Name 'Normalize-RepoPath'
        Import-ManagedWorkFunction -Name 'Test-PathPrefixMatch'
        Import-ManagedWorkFunction -Name 'Get-ManagedWorkConfig'
        Import-ManagedWorkFunction -Name 'Classify-ChangeEntry'
    }

    It 'classifies TOD engineering memory changes as blocked scope' {
        $project = [pscustomobject]@{
            boundaries = [pscustomobject]@{
                allowed_paths = @('scripts', 'tests', 'ui', 'docs', 'tod/config')
                blocked_paths = @('tod/data', 'tod/state', 'tod/out')
            }
            managed_work = [pscustomobject]@{
                path_classification = [pscustomobject]@{
                    blocked_scope_patterns = @('tod/knowledge/engineering-memory', 'tod/data/engineering-memory.json')
                }
            }
        }

        $config = Get-ManagedWorkConfig -Project $project
        $entry = [pscustomobject]@{
            path = 'tod/knowledge/engineering-memory/engine_performance_memory.json'
            status = 'modified'
        }

        $result = Classify-ChangeEntry -Project $project -ManagedWorkConfig $config -Entry $entry

        [string]$result.classification | Should Be 'blocked_scope_change'
    }

    It 'classifies TOD tmp artifacts as support artifacts instead of manual review' {
        $project = [pscustomobject]@{
            boundaries = [pscustomobject]@{
                allowed_paths = @('scripts', 'tests', 'ui', 'docs', 'tod/config')
                blocked_paths = @('tod/data', 'tod/state', 'tod/out')
            }
            managed_work = [pscustomobject]@{
                path_classification = [pscustomobject]@{
                    support_artifact_patterns = @('tmp_', 'raw-sweep')
                }
            }
        }

        $config = Get-ManagedWorkConfig -Project $project
        $entry = [pscustomobject]@{
            path = 'tmp_live_project_status.json'
            status = 'untracked'
        }

        $result = Classify-ChangeEntry -Project $project -ManagedWorkConfig $config -Entry $entry

        [string]$result.classification | Should Be 'qa_support_artifact'
    }
}