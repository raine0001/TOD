Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$todScript = Join-Path $repoRoot 'scripts/TOD.ps1'
$global:repoRoot = $repoRoot

function Import-TodFunction {
    param([Parameter(Mandatory = $true)][string]$Name)

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($todScript, [ref]$tokens, [ref]$errors)
    if (@($errors).Count -gt 0) {
        throw "Failed to parse $todScript"
    }

    $fnAst = $ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name
    }, $true)

    if ($null -eq $fnAst) {
        throw "Function '$Name' not found in $todScript"
    }

    $definition = $fnAst.Extent.Text -replace ("function\s+{0}\b" -f [regex]::Escape($Name)), ("function global:{0}" -f $Name)
    . ([scriptblock]::Create($definition))
}

function New-SelectionState {
    param(
        [object[]]$Objectives = @(),
        [object[]]$Tasks = @(),
        [object[]]$Reviews = @(),
        [object[]]$ExecutionResults = @()
    )

    return [pscustomobject]@{
        objectives = @($Objectives)
        tasks = @($Tasks)
        review_decisions = @($Reviews)
        execution_results = @($ExecutionResults)
        journal = @()
    }
}

function New-SelectionObjective {
    param(
        [string]$Id,
        [string]$Priority = 'medium',
        [string]$Status = 'open',
        [string]$Title = ''
    )

    return [pscustomobject]@{
        id = $Id
        title = $(if ([string]::IsNullOrWhiteSpace($Title)) { "Objective $Id" } else { $Title })
        description = 'Objective description'
        priority = $Priority
        status = $Status
        updated_at = '2026-05-04T21:00:00Z'
    }
}

function New-SelectionTask {
    param(
        [string]$Id,
        [string]$ObjectiveId,
        [string]$Status,
        [string]$Title = '',
        [string]$TaskCategory = 'code_change',
        [string]$SourceTaskId = ''
    )

    $task = [pscustomobject]@{
        id = $Id
        objective_id = $ObjectiveId
        title = $(if ([string]::IsNullOrWhiteSpace($Title)) { "Task $Id" } else { $Title })
        scope = 'Bounded scope'
        type = 'implementation'
        status = $Status
        task_category = $TaskCategory
        assigned_executor = 'codex'
        created_at = '2026-05-04T20:00:00Z'
        updated_at = '2026-05-04T21:00:00Z'
    }

    if (-not [string]::IsNullOrWhiteSpace($SourceTaskId)) {
        $task | Add-Member -NotePropertyName selection_source_task_id -NotePropertyValue $SourceTaskId -Force
    }

    return $task
}

Describe 'TOD self-driving next task selection' {
    BeforeAll {
        Import-TodFunction -Name 'Get-PreferredTaskSelection'
        Import-TodFunction -Name 'Get-TodPriorityWeight'
        Import-TodFunction -Name 'Test-TodTaskReadyStatus'
        Import-TodFunction -Name 'Get-TodExistingFollowOnTask'
        Import-TodFunction -Name 'Resolve-TodObjectiveIdFromState'
        Import-TodFunction -Name 'Get-TodReadyObjectiveCandidates'
        Import-TodFunction -Name 'Test-TodExecutionSummaryLooksWrapperOnly'
        Import-TodFunction -Name 'Test-TodExecutionHasMeaningfulEvidence'
        Import-TodFunction -Name 'Get-TodTerminalTaskOutcome'
        Import-TodFunction -Name 'Resolve-PreferredAssignedExecutor'
        Import-TodFunction -Name 'New-TodNextTaskSelectionPlan'
        Import-TodFunction -Name 'Get-NormalizedObjectiveToken'
        Import-TodFunction -Name 'Get-TodObjectValue'
        Import-TodFunction -Name 'Get-TodActivityStreamEventLimit'
        Import-TodFunction -Name 'New-TodActivityEventRecord'
        Import-TodFunction -Name 'Convert-TodActivityPayloadToStream'
        Import-TodFunction -Name 'Merge-TodActivityStreamPayload'
        Import-TodFunction -Name 'Test-TodLatestArtifactPublishGate'
        Import-TodFunction -Name 'Write-TodBlockedLatestArtifactRecord'
        Import-TodFunction -Name 'Write-TodExecutionSharedJson'
        Import-TodFunction -Name 'Publish-TodNextTaskSelectionArtifacts'
    }

    It 'classifies a wrapper-only completed execution as replay_required' {
        $state = New-SelectionState -Reviews @(
            [pscustomobject]@{ task_id = 'TSK-1'; decision = 'pass'; created_at = '2026-05-04T21:00:00Z' }
        )
        $executionResult = [pscustomobject]@{
            task_id = 'TSK-1'
            objective_id = 'OBJ-1'
            status = 'completed'
            execution_state = 'completed'
            summary = 'CodexExecutionEngine wrapper accepted package and prepared normalized result from prompt path: E:\TOD\tod\out\prompts\TSK-1.md'
            files_changed = @()
            command_output = ''
            execution_evidence = [pscustomobject]@{
                files_changed = @()
                matched_files = @()
                command_output = ''
            }
        }

        $outcome = Get-TodTerminalTaskOutcome -State $state -ActiveTaskArtifact $null -ExecutionResultArtifact $executionResult -ExecutionTruthArtifact $null -TaskId 'TSK-1'

        [string]$outcome.classification | Should Be 'replay_required'
        [bool]$outcome.meaningful_evidence | Should Be $false
    }

    It 'completed task selects the next ready task from the same objective' {
        $state = New-SelectionState -Objectives @(
            (New-SelectionObjective -Id 'OBJ-1' -Priority 'high'),
            (New-SelectionObjective -Id 'OBJ-2' -Priority 'medium')
        ) -Tasks @(
            (New-SelectionTask -Id 'TSK-1' -ObjectiveId 'OBJ-1' -Status 'completed'),
            (New-SelectionTask -Id 'TSK-2' -ObjectiveId 'OBJ-1' -Status 'planned'),
            (New-SelectionTask -Id 'TSK-3' -ObjectiveId 'OBJ-2' -Status 'planned')
        )
        $terminalOutcome = [pscustomobject]@{ classification = 'completed_with_evidence'; task_id = 'TSK-1'; objective_id = 'OBJ-1' }

        $plan = New-TodNextTaskSelectionPlan -State $state -TerminalOutcome $terminalOutcome

        [string]$plan.selection_kind | Should Be 'same_objective_next_task'
        [string]$plan.selected_task_id | Should Be 'TSK-2'
    }

    It 'no-op rejected task triggers replay or replan of the same task with evidence requirements' {
        $state = New-SelectionState -Objectives @(
            (New-SelectionObjective -Id 'OBJ-1' -Priority 'high')
        ) -Tasks @(
            (New-SelectionTask -Id 'TSK-1' -ObjectiveId 'OBJ-1' -Status 'completed' -Title 'Patch token extraction')
        )
        $terminalOutcome = [pscustomobject]@{ classification = 'no_op_rejected'; task_id = 'TSK-1'; objective_id = 'OBJ-1' }

        $plan = New-TodNextTaskSelectionPlan -State $state -TerminalOutcome $terminalOutcome

        [string]$plan.selection_kind | Should Be 'same_task_replan_new'
        $plan.create_task | Should Not BeNullOrEmpty
        [string]$plan.create_task.objective_mode | Should Be 'existing'
        [string]$plan.create_task.selection_source_task_id | Should Be 'TSK-1'
        (@($plan.expected_evidence) -contains 'meaningful_execution_evidence') | Should Be $true
    }

    It 'stale state with no ready task generates a bounded diagnostic task' {
        $state = New-SelectionState -Objectives @(
            (New-SelectionObjective -Id 'OBJ-1' -Priority 'high' -Status 'open')
        ) -Tasks @(
            (New-SelectionTask -Id 'TSK-1' -ObjectiveId 'OBJ-1' -Status 'completed')
        )
        $terminalOutcome = [pscustomobject]@{ classification = 'stale_waiting'; task_id = 'TSK-1'; objective_id = 'OBJ-1' }

        $plan = New-TodNextTaskSelectionPlan -State $state -TerminalOutcome $terminalOutcome -StaleDetected:$true -StaleReason 'no real progress'

        [string]$plan.selection_kind | Should Be 'stale_diagnostic'
        [string]$plan.create_task.objective_mode | Should Be 'new'
        [string]$plan.create_task.title | Should Match 'stale'
    }

    It 'blocked task does not loop forever and instead falls back to a ready backlog task' {
        $state = New-SelectionState -Objectives @(
            (New-SelectionObjective -Id 'OBJ-1' -Priority 'high'),
            (New-SelectionObjective -Id 'OBJ-2' -Priority 'critical')
        ) -Tasks @(
            (New-SelectionTask -Id 'TSK-1' -ObjectiveId 'OBJ-1' -Status 'failed'),
            (New-SelectionTask -Id 'TSK-2' -ObjectiveId 'OBJ-2' -Status 'planned')
        )
        $terminalOutcome = [pscustomobject]@{ classification = 'failed_blocked'; task_id = 'TSK-1'; objective_id = 'OBJ-1' }

        $plan = New-TodNextTaskSelectionPlan -State $state -TerminalOutcome $terminalOutcome

        [string]$plan.selection_kind | Should Be 'backlog_ready_objective'
        [string]$plan.selected_task_id | Should Be 'TSK-2'
    }

    It 'selected task publication writes the activity stream and selection artifact' {
        $tempRoot = Join-Path $repoRoot ('tod/out/tests/next-task-selection-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

        function global:Get-TodExecutionSharedRoots {
            return ,$tempRoot
        }

        function global:Get-UtcNow {
            return '2026-05-04T22:00:00Z'
        }

        function global:Publish-RemoteTodExecutionArtifacts {
            param([string[]]$LocalArtifactPaths)
            return [pscustomobject]@{ attempted = $false; published = $false; reason = 'stubbed' }
        }

        $selectionPayload = [pscustomobject]@{
            source_objective = 'OBJ-1'
            selection_kind = 'backlog_ready_objective'
            reason_selected = 'Selected a ready backlog task.'
            expected_evidence = @('bounded_execution_evidence')
            validation_plan = @('dispatch and validate progress')
        }
        $selectedTask = New-SelectionTask -Id 'TSK-2' -ObjectiveId 'OBJ-1' -Status 'planned' -Title 'Implement next bounded slice'

        $result = Publish-TodNextTaskSelectionArtifacts -SelectionPayload $selectionPayload -SelectedTask $selectedTask -RequestId 'selection-001'

        (Test-Path -Path (Join-Path $tempRoot 'TOD_NEXT_TASK_SELECTION.latest.json')) | Should Be $true
        (Test-Path -Path (Join-Path $tempRoot 'TOD_ACTIVITY_STREAM.latest.json')) | Should Be $true
        [string]$result.activity.event | Should Be 'next_task_selected'

        Remove-Item function:\Get-TodExecutionSharedRoots -ErrorAction SilentlyContinue
        Remove-Item function:\Get-UtcNow -ErrorAction SilentlyContinue
        Remove-Item function:\Publish-RemoteTodExecutionArtifacts -ErrorAction SilentlyContinue
        Remove-Item -Path $tempRoot -Recurse -Force
    }

    It 'selected task requires evidence before completion' {
        $state = New-SelectionState -Objectives @(
            (New-SelectionObjective -Id 'OBJ-1' -Priority 'high')
        ) -Tasks @(
            (New-SelectionTask -Id 'TSK-1' -ObjectiveId 'OBJ-1' -Status 'completed' -Title 'Patch token extraction')
        )
        $terminalOutcome = [pscustomobject]@{ classification = 'replay_required'; task_id = 'TSK-1'; objective_id = 'OBJ-1' }

        $plan = New-TodNextTaskSelectionPlan -State $state -TerminalOutcome $terminalOutcome

        [string]$plan.create_task.acceptance_criteria | Should Match 'evidence'
        (@($plan.validation_plan) -join ' ') | Should Match 'reject completion'
    }
}