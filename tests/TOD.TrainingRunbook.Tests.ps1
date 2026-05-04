Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$runbookScript = Join-Path $repoRoot 'scripts/Invoke-TODTrainingRunbook6h.ps1'

function Import-RunbookFunction {
    param([Parameter(Mandatory = $true)][string]$Name)

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($runbookScript, [ref]$tokens, [ref]$errors)
    if (@($errors).Count -gt 0) {
        throw 'Failed to parse ' + $runbookScript
    }

    $fnAst = $ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name
    }, $true)

    if ($null -eq $fnAst) {
        throw "Function '$Name' not found in $runbookScript"
    }

    $definition = $fnAst.Extent.Text -replace ('function\s+{0}\b' -f [regex]::Escape($Name)), ('function global:{0}' -f $Name)
    . ([scriptblock]::Create($definition))
}

Describe 'TOD training runbook automation' {
    BeforeAll {
                Import-RunbookFunction -Name 'ConvertFrom-JsonLoose'
        Import-RunbookFunction -Name 'Get-BoundedTrainingAssessment'
        Import-RunbookFunction -Name 'Get-SupervisedCheckpointAssessment'
        Import-RunbookFunction -Name 'Test-RunbookStopConditions'
        Import-RunbookFunction -Name 'Get-RunbookOutcome'
    }

        It 'recovers the final JSON document from mixed stdout' {
                $mixed = @'
Using Pester 3.4.0
noise line
{
    "ok": true,
    "steps": {
        "receipt_check": {
            "ok": true
        }
    }
}
'@

                $parsed = ConvertFrom-JsonLoose -Text $mixed

                [bool]$parsed.ok | Should Be $true
                [bool]$parsed.steps.receipt_check.ok | Should Be $true
        }

    It 'treats bounded runtime-safe success plus recovery as healthy' {
        $report = [pscustomobject]@{
            run = [pscustomobject]@{
                runtime_safe_subset = [pscustomobject]@{ passed_all = $true }
                reliability_recovery = [pscustomobject]@{ recovered = $true }
                warnings = @('tests skipped under lock')
                errors = @()
            }
        }

        $assessment = Get-BoundedTrainingAssessment -TrainingReport $report

        [bool]$assessment.runtime_safe_passed | Should Be $true
        [bool]$assessment.recovery_ok | Should Be $true
        [bool]$assessment.healthy | Should Be $true
    }

    It 'marks supervised execution unhealthy when escalation or receipt failure is present' {
        $runReport = [pscustomobject]@{
            needs_escalation = $true
            escalation_reason = 'publish_failed'
            steps = [pscustomobject]@{
                receipt_check = [pscustomobject]@{ ok = $false }
                bridge_smoke = [pscustomobject]@{ ok = $true }
            }
        }

        $assessment = Get-SupervisedCheckpointAssessment -RunReport $runReport

        [bool]$assessment.escalated | Should Be $true
        [bool]$assessment.healthy | Should Be $false
        [string]$assessment.escalation_reason | Should Be 'publish_failed'
    }

    It 'triggers stop conditions for repeated bounded failure and repeated supervised escalation' {
        $stopEval = Test-RunbookStopConditions -RuntimeSafeFailureStreak 2 -RecoveryHealthy $false -UiHealthy $true -ReceiptHealthy $true -SupervisedEscalationReason 'publish_failed' -PriorSupervisedEscalationReason 'publish_failed' -PriorSupervisedEscalationCount 1

        [bool]$stopEval.triggered | Should Be $true
        (@($stopEval.reasons) -contains 'supervised_escalated') | Should Be $true
        (@($stopEval.reasons) -contains 'runtime_safe_subset_failed_twice') | Should Be $true
        (@($stopEval.reasons) -contains 'readiness_recovery_not_healthy') | Should Be $true
        (@($stopEval.reasons) -contains 'supervised_escalated_twice_same_reason') | Should Be $true
    }

    It 'classifies a clean run as stable bounded lane unless quiet-window promotion is requested' {
        (Get-RunbookOutcome -StopConditions @() -AllBoundedHealthy $true -AllSupervisedHealthy $true -QuietWindowRecommended $false) | Should Be 'stable_bounded_lane'
        (Get-RunbookOutcome -StopConditions @() -AllBoundedHealthy $true -AllSupervisedHealthy $true -QuietWindowRecommended $true) | Should Be 'ready_for_quiet_window_full_run'
        (Get-RunbookOutcome -StopConditions @('runtime_safe_subset_failed_twice') -AllBoundedHealthy $true -AllSupervisedHealthy $true -QuietWindowRecommended $true) | Should Be 'root_cause_investigation_required'
    }
}