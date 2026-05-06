Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$todScript = Join-Path $repoRoot 'scripts/TOD.ps1'

function Import-ScriptFunction {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$tokens, [ref]$errors)
    if (@($errors).Count -gt 0) {
        throw "Failed to parse $ScriptPath"
    }

    $fnAst = $ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name
    }, $true)

    if ($null -eq $fnAst) {
        throw "Function '$Name' not found in $ScriptPath"
    }

    $definition = $fnAst.Extent.Text -replace ('function\s+{0}\b' -f [regex]::Escape($Name)), ('function global:{0}' -f $Name)
    . ([scriptblock]::Create($definition))
}

Describe 'TOD local-first routing policy' {
    BeforeAll {
        foreach ($name in @(
                'Get-DefaultRoutingWeights',
                'Normalize-RoutingWeights',
                'Get-SupportedExecutionEngines',
                'Resolve-TaskCategory',
                'Get-TaskRoutingText',
                'Get-TaskRoutingFileHints',
                'Get-LocalExecutionReuseSignal',
                'Resolve-LocalExecutionSuitability',
                'Resolve-ExecutionEngineConfig'
            )) {
            Import-ScriptFunction -ScriptPath $todScript -Name $name
        }
    }

    It 'classifies docs, config, inspection, and validation task categories from task text' {
        (Resolve-TaskCategory -Task ([pscustomobject]@{ title = 'Update README section'; scope = 'Edit docs/guide.md' })) | Should Be 'docs_change'
        (Resolve-TaskCategory -Task ([pscustomobject]@{ title = 'Patch config bootstrap'; scope = 'Update tod/config/tod-config.json' })) | Should Be 'config_change'
        (Resolve-TaskCategory -Task ([pscustomobject]@{ title = 'Inspect live routing status'; scope = 'Locate current engine selection state' })) | Should Be 'inspection'
        (Resolve-TaskCategory -Task ([pscustomobject]@{ title = 'Validate local routing'; scope = 'Run focused regression test slice' })) | Should Be 'validation'
    }

    It 'upgrades bounded code changes to local_supported when local execution memory matches the same file' {
        $state = [pscustomobject]@{
            engine_performance = [pscustomobject]@{
                records = @(
                    [pscustomobject]@{
                        id = 'ENGPERF-LOCAL-1'
                        engine = 'local'
                        success = $true
                        task_category = 'code_change'
                        files_involved = @('scripts/TOD.ps1')
                        created_at = (Get-Date).ToUniversalTime().ToString('o')
                    }
                )
            }
        }

        $task = [pscustomobject]@{
            title = 'Patch bounded local routing logic'
            scope = 'Update scripts/TOD.ps1 to prefer local execution first.'
        }

        $result = Resolve-LocalExecutionSuitability -Task $task -TaskCategoryHint 'code_change' -State $state

        [string]$result.classification | Should Be 'local_supported'
        [bool]$result.local_reuse.matched | Should Be $true
        [string]$result.local_reuse.strength | Should Be 'strong'
    }

    It 'selects local first for code_change tasks even when config defaults still point at codex' {
        $config = [pscustomobject]@{
            execution_engine = [pscustomobject]@{
                active = 'codex'
                fallback = 'local'
                allow_fallback = $true
                retry_policy = [pscustomobject]@{ enabled = $false }
                routing_policy = [pscustomobject]@{ enabled = $false }
            }
        }
        $task = [pscustomobject]@{
            title = 'Patch bounded routing file'
            scope = 'Update scripts/TOD.ps1 and keep the change bounded to one file.'
            task_category = 'code_change'
        }

        $engineConfig = Resolve-ExecutionEngineConfig -Config $config -State $null -TaskCategoryHint 'code_change' -Task $task

        [string]$engineConfig.active | Should Be 'local'
        [string]$engineConfig.fallback | Should Be 'codex'
        [string]$engineConfig.routing.reason | Should Be 'local_suitability_local_supported'
        [string]$engineConfig.routing.suitability.classification | Should Be 'local_supported'
    }

    It 'keeps codex primary for codex_required task families' {
        $config = [pscustomobject]@{
            execution_engine = [pscustomobject]@{
                active = 'local'
                fallback = 'codex'
                allow_fallback = $true
                retry_policy = [pscustomobject]@{ enabled = $false }
                routing_policy = [pscustomobject]@{ enabled = $false }
            }
        }
        $task = [pscustomobject]@{
            title = 'Generate test suite for uncovered modules'
            scope = 'Create new tests across the repo.'
            task_category = 'test_generation'
        }

        $engineConfig = Resolve-ExecutionEngineConfig -Config $config -State $null -TaskCategoryHint 'test_generation' -Task $task

        [string]$engineConfig.active | Should Be 'codex'
        [string]$engineConfig.routing.reason | Should Be 'local_suitability_codex_required'
    }
}