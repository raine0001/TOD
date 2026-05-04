Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$engineerScript = Join-Path $repoRoot 'scripts/TOD-Engineer.ps1'

function Import-EngineerFunction {
    param([Parameter(Mandatory = $true)][string]$Name)

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($engineerScript, [ref]$tokens, [ref]$errors)
    if (@($errors).Count -gt 0) {
        throw "Failed to parse $engineerScript"
    }

    $fnAst = $ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name
    }, $true)

    if ($null -eq $fnAst) {
        throw "Function '$Name' not found in $engineerScript"
    }

    $definition = $fnAst.Extent.Text -replace ("function\s+{0}\b" -f [regex]::Escape($Name)), ("function global:{0}" -f $Name)
    . ([scriptblock]::Create($definition))
}

Describe 'TOD engineer next-step continuation' {
    BeforeAll {
        Import-EngineerFunction -Name 'Resolve-NextStepContinuation'
    }

    It 'fails closed when next-step policy is missing or errors' {
        $continuation = Resolve-NextStepContinuation -LoopDecision 'continue' -NextStepPolicy $null -NextStepsError 'consensus artifact missing'

        [string]$continuation.effective_loop_decision | Should Be 'continue'
        [bool]$continuation.operator_prompt_allowed | Should Be $false
        [string]$continuation.resolution_source | Should Be 'next_step_policy_error_fail_closed'
    }

    It 'uses the explicit continuation policy when present' {
        $policy = [pscustomobject]@{
            continuation = [pscustomobject]@{
                decision = 'await_tod_mim_consensus'
                operator_prompt_allowed = $false
            }
        }

        $continuation = Resolve-NextStepContinuation -LoopDecision 'continue' -NextStepPolicy $policy

        [string]$continuation.effective_loop_decision | Should Be 'await_tod_mim_consensus'
        [bool]$continuation.operator_prompt_allowed | Should Be $false
        [string]$continuation.resolution_source | Should Be 'next_step_policy'
    }
}