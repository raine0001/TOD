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
        Import-EngineerFunction -Name 'Get-NextStepContinuationTaskSpec'
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

    It 'builds a follow-on task spec from the selected next-step finding when local continuation is allowed' {
        $consensus = [pscustomobject]@{
            consensus = [pscustomobject]@{
                selected_finding_id = 'finding-123'
            }
            findings = @(
                [pscustomobject]@{
                    finding = [pscustomobject]@{
                        finding_id = 'finding-123'
                        description = 'Run canonical-only validation pass'
                    }
                    consensus_reason = 'TOD can continue locally after review.'
                }
            )
        }

        $spec = Get-NextStepContinuationTaskSpec -TaskId 'TSK-001' -ObjectiveId 'OBJ-123' -EffectiveLoopDecision 'proceed_with_local_decision' -NextStepConsensus $consensus

        $spec | Should Not BeNullOrEmpty
        [string]$spec.title | Should Be 'Follow through: Run canonical-only validation pass'
        [string]$spec.task_category | Should Be 'next_step_followthrough'
        [string]$spec.finding_id | Should Be 'finding-123'
        [string]$spec.scope | Should Match 'TSK-001'
    }

    It 'does not build a follow-on task spec when continuation is not allowed yet' {
        $consensus = [pscustomobject]@{
            consensus = [pscustomobject]@{
                selected_finding_id = 'finding-123'
            }
            findings = @(
                [pscustomobject]@{
                    finding = [pscustomobject]@{
                        finding_id = 'finding-123'
                        description = 'Run canonical-only validation pass'
                    }
                }
            )
        }

        $spec = Get-NextStepContinuationTaskSpec -TaskId 'TSK-001' -ObjectiveId 'OBJ-123' -EffectiveLoopDecision 'await_tod_mim_consensus' -NextStepConsensus $consensus

        $spec | Should Be $null
    }
}