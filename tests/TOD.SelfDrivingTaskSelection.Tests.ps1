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

function Invoke-WithIsolatedPacketRepoRoot {
    param([Parameter(Mandatory = $true)][scriptblock]$ScriptBlock)

    $originalScriptRepoRoot = $script:repoRoot
    $originalRepoRoot = $global:repoRoot
    $tempRepoRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('tod-selection-isolated-' + [guid]::NewGuid().ToString('N'))
    try {
        $script:repoRoot = $tempRepoRoot
        $global:repoRoot = $tempRepoRoot
        New-Item -Path (Join-Path $tempRepoRoot 'runtime_remote_training/tod_independent_resolution_attempts') -ItemType Directory -Force | Out-Null
        & $ScriptBlock
    }
    finally {
        $script:repoRoot = $originalScriptRepoRoot
        $global:repoRoot = $originalRepoRoot
        if (Test-Path -Path $tempRepoRoot) {
            Remove-Item -Path $tempRepoRoot -Recurse -Force
        }
    }
}

function Set-TodSelectionTestFileText {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content
    )

    if (Test-Path -Path $Path -PathType Leaf) {
        $item = Get-Item -Path $Path -Force
        if ($item.IsReadOnly) {
            $item.IsReadOnly = $false
        }
    }
    New-Item -Path (Split-Path -Parent $Path) -ItemType Directory -Force | Out-Null
    [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($false)))
}

Describe 'TOD self-driving next task selection' {
    BeforeAll {
        Import-TodFunction -Name 'Get-PreferredTaskSelection'
        Import-TodFunction -Name 'Get-TodPriorityWeight'
        Import-TodFunction -Name 'Test-TodTaskReadyStatus'
        Import-TodFunction -Name 'Get-TodExistingFollowOnTask'
        Import-TodFunction -Name 'Resolve-TodObjectiveIdFromState'
        Import-TodFunction -Name 'Get-TodReadyObjectiveCandidates'
        Import-TodFunction -Name 'Get-TaskFromState'
        Import-TodFunction -Name 'Test-TodExecutionSummaryLooksWrapperOnly'
        Import-TodFunction -Name 'Test-TodExecutionHasMeaningfulEvidence'
        Import-TodFunction -Name 'Get-TodTerminalTaskOutcome'
        Import-TodFunction -Name 'Get-TodRecoveryContractFromTerminalOutcome'
        Import-TodFunction -Name 'Get-TaskRoutingText'
        Import-TodFunction -Name 'Get-TaskRoutingFileHints'
        Import-TodFunction -Name 'Get-TaskExplicitFieldValue'
        Import-TodFunction -Name 'Test-ExplicitBooleanTrue'
        Import-TodFunction -Name 'Get-BoundedEditDirectiveValue'
        Import-TodFunction -Name 'Test-TodTextOccursInFile'
        Import-TodFunction -Name 'Convert-ToCanonicalBoundedEditMode'
        Import-TodFunction -Name 'Get-BoundedEditSectionTitle'
        Import-TodFunction -Name 'Resolve-TaskCategory'
        Import-TodFunction -Name 'Get-CanonicalBoundedTargetFileHints'
        Import-TodFunction -Name 'Get-InferredBoundedValidationCommand'
        Import-TodFunction -Name 'Get-InferredBoundedReplaceDirective'
        Import-TodFunction -Name 'New-BoundedEditMaterializationBlockedPayload'
        Import-TodFunction -Name 'Resolve-TaskBoundedEditMaterialization'
        Import-TodFunction -Name 'Get-LocalExecutionReuseSignal'
        Import-TodFunction -Name 'Test-TodLowImpactEvidenceTask'
        Import-TodFunction -Name 'Test-TodMeaningfulAutonomySelectionRequested'
        Import-TodFunction -Name 'Test-TodMeaningfulAutonomyCandidate'
        Import-TodFunction -Name 'Test-TodPacketFormationRecoveryCandidate'
        Import-TodFunction -Name 'Get-TodAutonomyCandidateMaterializationSummary'
        Import-TodFunction -Name 'Resolve-LocalExecutionSuitability'
        Import-TodFunction -Name 'Resolve-PreferredAssignedExecutor'
        Import-TodFunction -Name 'Read-TodJsonFileIfExists'
        Import-TodFunction -Name 'Get-TodPacketFieldValue'
        Import-TodFunction -Name 'Get-TodIndependentResolutionPacketFiles'
        Import-TodFunction -Name 'Get-TodIndependentResolutionPackets'
        Import-TodFunction -Name 'Get-TodLatestIndependentResolutionPacketArtifact'
        Import-TodFunction -Name 'Get-TodLatestIndependentResolutionPacket'
        Import-TodFunction -Name 'Test-TodPacketOldTextStillCurrent'
        Import-TodFunction -Name 'Test-TodPacketNewTextAlreadyPresent'
        Import-TodFunction -Name 'New-TodTaskSpecFromIndependentResolutionPacket'
        Import-TodFunction -Name 'Get-TodAcceptedResultArtifactTaskIds'
        Import-TodFunction -Name 'Test-TodTaskHasAcceptedResultArtifact'
        Import-TodFunction -Name 'Test-TodMaterializedReplacementStillApplicable'
        Import-TodFunction -Name 'New-TodIndependentResolutionSynthesisCandidates'
        Import-TodFunction -Name 'New-TodNextTaskSelectionPlan'
        Import-TodFunction -Name 'Get-TodTaskIdentity'
        Import-TodFunction -Name 'Get-NormalizedObjectiveToken'
        Import-TodFunction -Name 'Get-TodObjectValue'
        Import-TodFunction -Name 'Get-UtcNow'
        Import-TodFunction -Name 'Repair-TodMissingTaskFromActiveTaskArtifact'
        Import-TodFunction -Name 'Get-TodActivityStreamEventLimit'
        Import-TodFunction -Name 'Get-TodExecutionArtifactLane'
        Import-TodFunction -Name 'Get-TodCanonicalPublishContext'
        Import-TodFunction -Name 'New-TodActivityEventRecord'
        Import-TodFunction -Name 'Convert-TodActivityPayloadToStream'
        Import-TodFunction -Name 'Merge-TodActivityStreamPayload'
        Import-TodFunction -Name 'Test-TodLatestArtifactPublishGate'
        Import-TodFunction -Name 'Write-TodBlockedLatestArtifactRecord'
        Import-TodFunction -Name 'Read-TodExecutionJsonIfExists'
        Import-TodFunction -Name 'Write-TodExecutionJsonAtomically'
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

    It 'does not mix a requested task id with a latest execution artifact from another task' {
        $state = New-SelectionState -Objectives @(
            (New-SelectionObjective -Id 'OBJ-3159' -Priority 'high'),
            (New-SelectionObjective -Id 'OBJ-3156' -Priority 'high')
        ) -Tasks @(
            (New-SelectionTask -Id 'TSK-3159' -ObjectiveId 'OBJ-3159' -Status 'completed'),
            (New-SelectionTask -Id 'TSK-3156' -ObjectiveId 'OBJ-3156' -Status 'blocked')
        )
        $latestDifferentTaskResult = [pscustomobject]@{
            task_id = 'TSK-3156'
            objective_id = 'OBJ-3156'
            status = 'blocked'
            execution_state = 'blocked'
            reason_code = 'local_executor_validation_failed'
            summary = 'Wrong task result should not be copied into TSK-3159 outcome.'
            files_changed = @('scripts/generate_mim_tod_training_scoreboard.py')
            tests_run = @('python scripts/generate_mim_tod_training_scoreboard.py')
        }

        $outcome = Get-TodTerminalTaskOutcome -State $state -ActiveTaskArtifact $null -ExecutionResultArtifact $latestDifferentTaskResult -ExecutionTruthArtifact $null -TaskId 'TSK-3159'

        [string]$outcome.task_id | Should Be 'TSK-3159'
        [string]$outcome.objective_id | Should Be 'OBJ-3159'
        [string]$outcome.reason_code | Should Be 'terminal_outcome_artifact_unavailable_for_requested_task'
        [string]$outcome.summary | Should Not Match 'Wrong task result'
    }

    It 'prefers a newer matching execution result over stale completed state terminal data' {
        $task = New-SelectionTask -Id 'TSK-3160' -ObjectiveId 'OBJ-0192' -Status 'completed' -Title 'Validation-only maintenance task'
        $task | Add-Member -NotePropertyName terminal_state -NotePropertyValue ([pscustomobject]@{
                timestamp = '2026-06-13T20:12:24Z'
                status = 'completed'
                event_type = 'local_executor_completed'
                message = 'State terminal incorrectly still says completed.'
                details = [pscustomobject]@{
                    review_decision = 'pass'
                    files_changed = @()
                    tests_run = @('validation_only_no_file_change_expected')
                }
            }) -Force
        $state = New-SelectionState -Objectives @(
            (New-SelectionObjective -Id 'OBJ-0192' -Priority 'high')
        ) -Tasks @($task)
        $executionResult = [pscustomobject]@{
            task_id = 'TSK-3160'
            objective_id = 'OBJ-0192'
            generated_at = '2026-06-13T20:12:38Z'
            updated_at = '2026-06-13T20:12:38Z'
            status = 'blocked'
            execution_state = 'material_implementation_not_proven'
            reason_code = 'validation_only_no_material_change'
            summary = 'Newer execution result correctly blocks validation-only material proof.'
            files_changed = @()
            tests_run = @('validation_only_no_file_change_expected')
        }

        $outcome = Get-TodTerminalTaskOutcome -State $state -ActiveTaskArtifact $null -ExecutionResultArtifact $executionResult -ExecutionTruthArtifact $null -TaskId 'TSK-3160'

        [string]$outcome.task_id | Should Be 'TSK-3160'
        [string]$outcome.status | Should Be 'blocked'
        [string]$outcome.execution_state | Should Be 'material_implementation_not_proven'
        [string]$outcome.reason_code | Should Be 'validation_only_no_material_change'
        [string]$outcome.classification | Should Be 'failed_recoverable'
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

    It 'does not create same-task validation-only replans from docs-only autonomy failures' {
        $task = New-SelectionTask -Id 'TSK-DOCS-NOOP' -ObjectiveId 'OBJ-1' -Status 'completed' -Title 'Record TOD bounded dispatch prevention lesson'
        $task.task_category = 'docs_change'
        $task.scope = @'
Target File: docs/tod-command-reference.md
Edit Mode: docs_append_section
Section Title: Dave-Away Bounded Dispatch Lessons 2026-06-14
Validation Pattern: Dave-Away Bounded Dispatch Lessons 2026-06-14
'@
        $state = New-SelectionState -Objectives @(
            (New-SelectionObjective -Id 'OBJ-1' -Priority 'high' -Title 'TOD independent resolution movement')
        ) -Tasks @(
            $task
        )
        $terminalOutcome = [pscustomobject]@{
            classification = 'replay_required'
            task_id = 'TSK-DOCS-NOOP'
            objective_id = 'OBJ-1'
            summary = 'Docs task validated existing content and produced no changed files.'
            status = 'completed'
        }

        $plan = New-TodNextTaskSelectionPlan -State $state -TerminalOutcome $terminalOutcome -TriggerReason 'Dave-away independent TOD resolution movement'

        [string]$plan.selection_kind | Should Not Be 'same_task_replan_new'
        $plan.create_task | Should BeNullOrEmpty
        @(@($plan.rejected_candidates) | Where-Object {
            [string]$_.task_id -eq 'TSK-DOCS-NOOP' -and
            [string]$_.reason -eq 'same_task_replan_rejected_low_impact_source_for_autonomy'
        }).Count | Should Be 1
    }

    It 'does not treat packaged tasks with accepted result artifacts as ready backlog' {
        $tempRoot = Join-Path $repoRoot ('tod/out/tests/accepted-result-artifacts-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
        $global:TodResultArtifactRootsForTests = @($tempRoot)
        Remove-Variable -Name TodAcceptedResultTaskIdsCache -Scope Script -ErrorAction SilentlyContinue
        try {
            [pscustomobject]@{
                task_id = 'TSK-DONE-PACKAGED'
                status = 'completed_with_validation'
                counts_as_meaningful_tod_implementation = $true
            } | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $tempRoot 'TSK-DONE-PACKAGED.latest.json') -Encoding UTF8

            $task = New-SelectionTask -Id 'TSK-DONE-PACKAGED' -ObjectiveId 'OBJ-1' -Status 'packaged' -Title 'Already accepted package'

            [bool](Test-TodTaskReadyStatus -Task $task) | Should Be $false
        }
        finally {
            Remove-Variable -Name TodResultArtifactRootsForTests -Scope Global -ErrorAction SilentlyContinue
            Remove-Variable -Name TodAcceptedResultTaskIdsCache -Scope Script -ErrorAction SilentlyContinue
            Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'does not treat stale replace_text tasks as ready when old text is absent' {
        $targetRelative = 'tests/tod-stale-replacement-target-' + [guid]::NewGuid().ToString('N') + '.ps1'
        $targetPath = Join-Path $repoRoot ($targetRelative -replace '/', '\')
        Set-Content -Path $targetPath -Value "Write-Output 'new text already here'" -Encoding UTF8
        try {
            $task = New-SelectionTask -Id 'TSK-STALE-REPLACE' -ObjectiveId 'OBJ-1' -Status 'packaged' -Title 'Stale replace task'
            $task.scope = @(
                "Target File: $targetRelative",
                'Edit Mode: replace_text',
                'Old Text:',
                'old text no longer here',
                'New Text:',
                "Write-Output 'new text already here'",
                "Validation Pattern: Write-Output 'new text already here'"
            ) -join "`n"

            [bool](Test-TodTaskReadyStatus -Task $task) | Should Be $false
        }
        finally {
            Remove-Item -Path $targetPath -Force -ErrorAction SilentlyContinue
        }
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

    It 'uses tolerant task identity when selected backlog task only has task_id' {
        $bridgeTask = [pscustomobject]@{
            task_id = 'BRIDGE-TASK-2'
            objective_id = 'OBJ-2'
            status = 'planned'
            title = 'Bridge style backlog task'
            scope = 'Target File: scripts/TOD.ps1'
        }
        $state = New-SelectionState -Objectives @(
            (New-SelectionObjective -Id 'OBJ-1' -Priority 'high'),
            (New-SelectionObjective -Id 'OBJ-2' -Priority 'critical')
        ) -Tasks @(
            (New-SelectionTask -Id 'TSK-1' -ObjectiveId 'OBJ-1' -Status 'failed'),
            $bridgeTask
        )
        $terminalOutcome = [pscustomobject]@{ classification = 'failed_blocked'; task_id = 'TSK-1'; objective_id = 'OBJ-1' }

        $plan = New-TodNextTaskSelectionPlan -State $state -TerminalOutcome $terminalOutcome

        [string]$plan.selection_kind | Should Be 'backlog_ready_objective'
        [string]$plan.selected_task_id | Should Be 'BRIDGE-TASK-2'
    }

    It 'blocks vague backlog dispatch under wrapper recovery pressure until bounded edit proof exists' {
        $vagueBacklog = New-SelectionTask -Id 'TSK-VAGUE-BACKLOG' -ObjectiveId 'OBJ-2' -Status 'planned' -Title 'Vague MIM synced backlog task'
        $vagueBacklog.task_category = 'mim_synced'
        $vagueBacklog.scope = 'Synchronized from MIM request without a target file or bounded edit directives.'
        $state = New-SelectionState -Objectives @(
            (New-SelectionObjective -Id 'OBJ-1' -Priority 'high'),
            (New-SelectionObjective -Id 'OBJ-2' -Priority 'critical')
        ) -Tasks @(
            (New-SelectionTask -Id 'TSK-WRAPPER-BLOCKED' -ObjectiveId 'OBJ-1' -Status 'blocked' -Title 'Wrapper blocked source task'),
            $vagueBacklog
        )
        $terminalOutcome = [pscustomobject]@{
            classification = 'failed_recoverable'
            task_id = 'TSK-WRAPPER-BLOCKED'
            objective_id = 'OBJ-1'
            reason_code = 'codex_wrapper_only_no_execution'
            summary = 'Codex wrapper accepted the packaged prompt without executing it, and local fallback could not execute the task scope.'
        }

        $plan = New-TodNextTaskSelectionPlan -State $state -TerminalOutcome $terminalOutcome -TriggerReason 'automatic_terminal_outcome'

        [string]$plan.selection_kind | Should Be 'recovery_backlog_materialization_packet_formation'
        [string]$plan.dispatch_status | Should Be 'not_started'
        [string]$plan.selected_task_id | Should Be ''
        $plan.create_task | Should Not BeNullOrEmpty
        [string]$plan.create_task.task_category | Should Be 'packet_formation'
        [string]$plan.create_task.scope | Should Match 'materialized bounded edit proof'
        @(@($plan.rejected_candidates) | Where-Object {
            [string]$_.task_id -eq 'TSK-VAGUE-BACKLOG' -and
            [string]$_.reason -eq 'backlog_candidate_not_materialized_for_recovery_pressure'
        }).Count | Should Be 1
        (@($plan.validation_plan) -join ' ') | Should Match 'packet-formation task'
    }

    It 'does not dispatch vague backlog after an already-applied local fallback candidate' {
        $vagueBacklog = New-SelectionTask -Id 'TSK-VAGUE-MIM-REPLAN' -ObjectiveId 'OBJ-2' -Status 'planned' -Title 'MIM synchronized vague replan'
        $vagueBacklog.task_category = 'mim_synced'
        $vagueBacklog.scope = 'Synchronized from MIM request what-should-happen-before-we-add-another-feature.'
        $state = New-SelectionState -Objectives @(
            (New-SelectionObjective -Id 'OBJ-1' -Priority 'high'),
            (New-SelectionObjective -Id 'OBJ-2' -Priority 'critical')
        ) -Tasks @(
            (New-SelectionTask -Id 'TSK-ALREADY-APPLIED' -ObjectiveId 'OBJ-1' -Status 'blocked' -Title 'Already applied independent candidate'),
            $vagueBacklog
        )
        $terminalOutcome = [pscustomobject]@{
            classification = 'failed_recoverable'
            task_id = 'TSK-ALREADY-APPLIED'
            objective_id = 'OBJ-1'
            reason_code = 'local_fallback_already_applied'
            summary = 'LocalExecutionEngine rejected the bounded replacement because the requested new_text is already present; applying it again would duplicate an already-materialized patch.'
        }

        $plan = New-TodNextTaskSelectionPlan -State $state -TerminalOutcome $terminalOutcome -TriggerReason 'terminal_task_outcome'

        [string]$plan.selection_kind | Should Be 'recovery_backlog_materialization_packet_formation'
        [string]$plan.dispatch_status | Should Be 'not_started'
        [string]$plan.selected_task_id | Should Be ''
        $plan.create_task | Should Not BeNullOrEmpty
        [string]$plan.create_task.task_category | Should Be 'packet_formation'
        [string]$plan.create_task.scope | Should Match 'materialized bounded edit proof'
        @(@($plan.rejected_candidates) | Where-Object {
            [string]$_.task_id -eq 'TSK-VAGUE-MIM-REPLAN' -and
            [string]$_.reason -eq 'backlog_candidate_not_materialized_for_recovery_pressure'
        }).Count | Should Be 1
        (@($plan.validation_plan) -join ' ') | Should Match 'packet-formation task'
    }

    It 'recoverable blocked task selects a ready same-objective recovery task before backlog' {
        $state = New-SelectionState -Objectives @(
            (New-SelectionObjective -Id 'OBJ-1' -Priority 'high'),
            (New-SelectionObjective -Id 'OBJ-2' -Priority 'critical')
        ) -Tasks @(
            (New-SelectionTask -Id 'TSK-1' -ObjectiveId 'OBJ-1' -Status 'blocked'),
            (New-SelectionTask -Id 'TSK-2' -ObjectiveId 'OBJ-1' -Status 'planned' -Title 'Same objective recovery'),
            (New-SelectionTask -Id 'TSK-3' -ObjectiveId 'OBJ-2' -Status 'planned' -Title 'Unrelated backlog')
        )
        $terminalOutcome = [pscustomobject]@{ classification = 'failed_recoverable'; task_id = 'TSK-1'; objective_id = 'OBJ-1' }

        $plan = New-TodNextTaskSelectionPlan -State $state -TerminalOutcome $terminalOutcome

        [string]$plan.selection_kind | Should Be 'same_objective_recovery_after_blocker'
        [string]$plan.selected_task_id | Should Be 'TSK-2'
    }

    It 'blocks vague same-objective recovery tasks after bounded edit materialization failure' {
        $sourceTask = New-SelectionTask -Id 'TSK-MISSING-BOUNDED' -ObjectiveId 'OBJ-1' -Status 'blocked' -Title 'Missing bounded source'
        $vagueRecovery = New-SelectionTask -Id 'TSK-VAGUE-REPLAN' -ObjectiveId 'OBJ-1' -Status 'planned' -Title 'Vague same-objective replan'
        $vagueRecovery.scope = 'Synchronized from MIM request with no target file or bounded edit directives.'
        $state = New-SelectionState -Objectives @(
            (New-SelectionObjective -Id 'OBJ-1' -Priority 'high')
        ) -Tasks @(
            $sourceTask,
            $vagueRecovery
        )
        $terminalOutcome = [pscustomobject]@{
            classification = 'failed_recoverable'
            task_id = 'TSK-MISSING-BOUNDED'
            objective_id = 'OBJ-1'
            reason_code = 'blocked_missing_bounded_edit_mode'
            summary = 'TOD needs exactly one bounded target_file before LocalExecutionEngine can proceed.'
        }

        $plan = New-TodNextTaskSelectionPlan -State $state -TerminalOutcome $terminalOutcome -TriggerReason 'automatic_terminal_outcome'

        [string]$plan.selection_kind | Should Be 'same_objective_recovery_materialization_packet_formation'
        [string]$plan.dispatch_status | Should Be 'not_started'
        [string]$plan.selected_task_id | Should Be ''
        $plan.create_task | Should Not BeNullOrEmpty
        [string]$plan.create_task.task_category | Should Be 'packet_formation'
        [string]$plan.create_task.scope | Should Match 'same_objective_recovery_not_materialized_before_dispatch'
        @(@($plan.rejected_candidates) | Where-Object {
            [string]$_.task_id -eq 'TSK-VAGUE-REPLAN' -and
            [string]$_.reason -eq 'same_objective_recovery_not_materialized_before_dispatch'
        }).Count | Should Be 1
        (@($plan.validation_plan) -join ' ') | Should Match 'packet-formation task'
    }

    It 'does not create same-objective recovery packet formation when no-packet behavior selection is requested' {
        $sourceTask = New-SelectionTask -Id 'TSK-MISSING-BOUNDED' -ObjectiveId 'OBJ-1' -Status 'blocked' -Title 'Missing bounded source'
        $vagueRecovery = New-SelectionTask -Id 'TSK-VAGUE-REPLAN' -ObjectiveId 'OBJ-1' -Status 'planned' -Title 'Vague same-objective replan'
        $vagueRecovery.scope = 'Synchronized from MIM request with no target file or bounded edit directives.'
        $state = New-SelectionState -Objectives @(
            (New-SelectionObjective -Id 'OBJ-1' -Priority 'high')
        ) -Tasks @(
            $sourceTask,
            $vagueRecovery
        )
        $terminalOutcome = [pscustomobject]@{
            classification = 'failed_recoverable'
            task_id = 'TSK-MISSING-BOUNDED'
            objective_id = 'OBJ-1'
            reason_code = 'blocked_missing_bounded_edit_mode'
            summary = 'TOD needs exactly one bounded target_file before LocalExecutionEngine can proceed.'
        }

        $plan = New-TodNextTaskSelectionPlan -State $state -TerminalOutcome $terminalOutcome -TriggerReason 'no-packet; not packet formation; forbidden: packet_formation; choose a different behavior-changing candidate or publish blocked_no_viable_behavior_candidate'

        [string]$plan.selection_kind | Should Be 'blocked_no_viable_behavior_candidate'
        [string]$plan.dispatch_status | Should Be 'blocked_with_reason'
        [string]$plan.selected_task_id | Should Be ''
        $plan.create_task | Should BeNullOrEmpty
        [string]$plan.blocked_reason | Should Match 'packet formation is forbidden'
        [string]$plan.blocker.required_next_action | Should Match 'Inspect a different current-code target'
        (@($plan.expected_evidence) -join ' ') | Should Match 'same_objective_recovery_packet_formation_blocked'
        (@($plan.validation_plan) -join ' ') | Should Match 'packet formation is forbidden'
    }

    It 'creates focused recovery after a real material patch fails validation' {
        $failedTask = New-SelectionTask -Id 'TSK-FAILED-PATCH' -ObjectiveId 'OBJ-1' -Status 'blocked' -Title 'Patch scoreboard recovery gate'
        $failedTask.scope = @'
Target File: scripts/generate_mim_tod_training_scoreboard.py
Edit Mode: replace_text
Old Text:
    mim_visible_evaluation = mim_eval
New Text:
    mim_visible_evaluation = mim_eval
    current_evidence_supersedes_stale_reflection = True
Validation Command: python -m py_compile scripts/generate_mim_tod_training_scoreboard.py; python scripts/generate_mim_tod_training_scoreboard.py --base-url https://www.mimtod.com
'@
        $state = New-SelectionState -Objectives @(
            (New-SelectionObjective -Id 'OBJ-1' -Priority 'high'),
            (New-SelectionObjective -Id 'OBJ-2' -Priority 'critical')
        ) -Tasks @(
            $failedTask,
            (New-SelectionTask -Id 'TSK-BACKLOG' -ObjectiveId 'OBJ-2' -Status 'planned' -Title 'Unrelated backlog')
        )
        $terminalOutcome = [pscustomobject]@{
            classification = 'failed_recoverable'
            task_id = 'TSK-FAILED-PATCH'
            objective_id = 'OBJ-1'
            reason_code = 'local_fallback_validation_failed'
            summary = 'LocalExecutionEngine rolled back the bounded local fallback because focused validation failed.'
        }

        $plan = New-TodNextTaskSelectionPlan -State $state -TerminalOutcome $terminalOutcome -TriggerReason 'terminal_task_outcome: validation failed with UnboundLocalError for mim_visible_evaluation'

        [string]$plan.selection_kind | Should Be 'same_task_validation_recovery_new'
        $plan.create_task | Should Not BeNullOrEmpty
        [string]$plan.create_task.objective_mode | Should Be 'existing'
        [string]$plan.create_task.selection_source_task_id | Should Be 'TSK-FAILED-PATCH'
        [string]$plan.create_task.scope | Should Match 'UnboundLocalError'
        [string]$plan.create_task.scope | Should Match 'Recovery Mode: failed_material_patch'
        [string]$plan.create_task.scope | Should Not Match 'Edit Mode: recovery_from_failed_patch'
        [string]$plan.create_task.scope | Should Match 'Target File: scripts/generate_mim_tod_training_scoreboard.py'
        [string]$plan.create_task.scope | Should Match 'Original scope quoted for context'
        [string]$plan.create_task.scope | Should Not Match "(?m)^Edit Mode: replace_text"
        [string]$plan.create_task.scope | Should Match "(?m)^> Edit Mode: replace_text"
        [string]$plan.create_task.scope | Should Match 'Validation Command: python -m py_compile scripts/generate_mim_tod_training_scoreboard.py'
        [string]$plan.create_task.assigned_executor | Should Be 'local'
        [string]$plan.selected_task_id | Should Be ''
        (@($plan.validation_plan) -join ' ') | Should Match 'original focused validation command'
    }

    It 'keeps wrapper-noise recovery on the same failed patch when local validation evidence is present' {
        $failedTask = New-SelectionTask -Id 'TSK-WRAPPER-NOISE' -ObjectiveId 'OBJ-1' -Status 'blocked' -Title 'Recover wrapped local fallback failure'
        $failedTask.scope = @'
Target File: scripts/generate_mim_tod_training_scoreboard.py
Edit Mode: replace_text
Old Text:
    mim_visible_evaluation = mim_eval
New Text:
    mim_visible_evaluation = mim_eval
    current_evidence_supersedes_stale_reflection = True
Validation Command: python -m py_compile scripts/generate_mim_tod_training_scoreboard.py; python scripts/generate_mim_tod_training_scoreboard.py --base-url https://www.mimtod.com
'@
        $state = New-SelectionState -Objectives @(
            (New-SelectionObjective -Id 'OBJ-1' -Priority 'high'),
            (New-SelectionObjective -Id 'OBJ-2' -Priority 'critical')
        ) -Tasks @(
            $failedTask,
            (New-SelectionTask -Id 'TSK-BACKLOG' -ObjectiveId 'OBJ-2' -Status 'planned' -Title 'Unrelated independent backlog')
        )
        $terminalOutcome = [pscustomobject]@{
            classification = 'failed_recoverable'
            task_id = 'TSK-WRAPPER-NOISE'
            objective_id = 'OBJ-1'
            reason_code = 'codex_wrapper_only_no_execution'
            summary = 'Codex wrapper did not execute, but local fallback attempted a material patch, focused validation failed, and the target file was rolled back.'
        }

        $plan = New-TodNextTaskSelectionPlan -State $state -TerminalOutcome $terminalOutcome -TriggerReason 'terminal_task_outcome: local fallback preserved the full bounded edit but focused validation failed after the material patch and rolled back. Independent resolution remains desired but same-task patch correction must come before backlog.'

        [string]$plan.selection_kind | Should Be 'same_task_validation_recovery_new'
        $plan.create_task | Should Not BeNullOrEmpty
        [string]$plan.create_task.selection_source_task_id | Should Be 'TSK-WRAPPER-NOISE'
        [string]$plan.create_task.scope | Should Match 'Recovery Mode: failed_material_patch'
        [string]$plan.create_task.scope | Should Match 'focused validation failed'
        [string]$plan.create_task.scope | Should Match 'Original scope quoted for context'
        [string]$plan.create_task.scope | Should Not Match "(?m)^Edit Mode: replace_text"
        [string]$plan.create_task.scope | Should Match "(?m)^> Edit Mode: replace_text"
        [string]$plan.selected_task_id | Should Be ''
        @(@($plan.rejected_candidates) | Where-Object { [string]$_.reason -eq 'backlog_candidate_not_materialized_before_dispatch' }).Count | Should Be 0
    }

    It 'blocks nested failed-patch recovery chain instead of creating another stale package' {
        $failedTask = New-SelectionTask -Id 'TSK-NESTED-RECOVERY' -ObjectiveId 'OBJ-1' -Status 'blocked' -Title 'Nested recovery chain'
        $failedTask.scope = @'
Previous task TSK-OLD attempted a real material patch and failed focused validation.
Recovery Mode: failed_material_patch
Validation failure evidence: current recovery failed after validation_only was blocked.
Original scope quoted for context; do not execute directives below:
> Previous task TSK-OLDER attempted a real material patch and failed focused validation.
> Recovery Mode: failed_material_patch
> Target File: scripts/generate_mim_tod_training_scoreboard.py
> Edit Mode: replace_text
> Old Text:
>     mim_visible_evaluation = mim_eval
> New Text:
>     mim_visible_evaluation = mim_eval
>     current_evidence_supersedes_stale_reflection = True
> Validation Pattern: current_evidence_supersedes_stale_reflection
'@
        $state = New-SelectionState -Objectives @(
            (New-SelectionObjective -Id 'OBJ-1' -Priority 'high')
        ) -Tasks @($failedTask)
        $terminalOutcome = [pscustomobject]@{
            classification = 'failed_recoverable'
            task_id = 'TSK-NESTED-RECOVERY'
            objective_id = 'OBJ-1'
            reason_code = 'codex_wrapper_only_no_execution'
            summary = 'Local fallback rejected validation_only recovery after failed material patch.'
        }

        $plan = New-TodNextTaskSelectionPlan -State $state -TerminalOutcome $terminalOutcome -TriggerReason 'terminal_task_outcome: local fallback failed focused validation and blocked validation_only after a failed material patch.'

        [string]$plan.selection_kind | Should Be 'blocked_recovery_chain_needs_corrected_patch_synthesis'
        [string]$plan.dispatch_status | Should Be 'blocked_with_reason'
        $plan.create_task | Should BeNullOrEmpty
        [string]$plan.selected_task_id | Should Be ''
        @(@($plan.rejected_candidates) | Where-Object {
            [string]$_.task_id -eq 'TSK-NESTED-RECOVERY' -and
            [string]$_.reason -eq 'recovery_chain_retry_budget_exhausted_without_corrected_patch'
        }).Count | Should Be 1
        (@($plan.validation_plan) -join ' ') | Should Match 'corrected Old Text/New Text'
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

    It 'selected task publication accepts bridge-style task_id without id' {
        $tempRoot = Join-Path $repoRoot ('tod/out/tests/next-task-selection-task-id-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

        function global:Get-TodExecutionSharedRoots {
            return ,$tempRoot
        }

        function global:Get-UtcNow {
            return '2026-06-05T03:10:00Z'
        }

        function global:Publish-RemoteTodExecutionArtifacts {
            param([string[]]$LocalArtifactPaths)
            return [pscustomobject]@{ attempted = $false; published = $false; reason = 'stubbed' }
        }

        $selectionPayload = [pscustomobject]@{
            source_objective = 'OBJ-1'
            selection_kind = 'backlog_ready_objective'
            reason_selected = 'Selected a bridge-style ready task.'
            expected_evidence = @('bounded_execution_evidence')
            validation_plan = @('dispatch and validate progress')
        }
        $selectedTask = [pscustomobject]@{
            task_id = 'TSK-BRIDGE-2'
            objective_id = 'OBJ-1'
            title = 'Bridge style task'
            scope = 'Bounded bridge-style scope'
            status = 'planned'
        }

        $result = Publish-TodNextTaskSelectionArtifacts -SelectionPayload $selectionPayload -SelectedTask $selectedTask -RequestId 'selection-bridge-001'

        [string]$result.active_task.task_id | Should Be 'TSK-BRIDGE-2'
        [string]$result.activity.task_id | Should Be 'TSK-BRIDGE-2'

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

    It 'rejects validation-only tasks as meaningful autonomy candidates' {
        $task = New-SelectionTask -Id 'TSK-VALIDATE' -ObjectiveId 'OBJ-1' -Status 'planned' -Title 'Validate autonomy gate'
        $task.scope = @'
Target File: scripts/TOD.ps1
Edit Mode: validation_only
Validation Command: Select-String -Path scripts/TOD.ps1 -Pattern 'validation_only_no_material_change'
Required behavior: prove the selector gate still exists without changing behavior.
'@

        [bool](Test-TodMeaningfulAutonomyCandidate -Task $task) | Should Be $false
    }

    It 'rejects docs-only tasks as independent-resolution candidates' {
        $task = New-SelectionTask -Id 'TSK-DOCS-LESSON' -ObjectiveId 'OBJ-1' -Status 'planned' -Title 'Record bounded dispatch lesson'
        $task.task_category = 'docs_change'
        $task.scope = @'
Target File: docs/tod-command-reference.md
Edit Mode: docs_append_section
Section Title: Dave-Away Bounded Dispatch Lessons 2026-06-14
Validation Pattern: Dave-Away Bounded Dispatch Lessons 2026-06-14
'@

        [bool](Test-TodMeaningfulAutonomyCandidate -Task $task) | Should Be $false
    }

    It 'requires every synthesized independent-resolution candidate to carry the full selector field contract' {
        $candidates = @(New-TodIndependentResolutionSynthesisCandidates)
        $requiredSelectorFields = @(
            'Target File',
            'Target Function or Rule',
            'Behavior Delta',
            'Validation Command',
            'Expected Changed Files',
            'Rollback Note',
            'Prevention Lesson'
        )

        $candidates.Count | Should BeGreaterThan 0
        foreach ($candidate in $candidates) {
            foreach ($fieldName in $requiredSelectorFields) {
                [string]$candidate.scope | Should Match ('(?im)^\s*{0}\s*:' -f [regex]::Escape($fieldName))
            }
        }
    }

    It 'preserves independent-resolution pressure from terminal task context' {
        Invoke-WithIsolatedPacketRepoRoot {
            $sourceTask = New-SelectionTask -Id 'TSK-1' -ObjectiveId 'OBJ-1' -Status 'completed' -Title 'Independent TOD resolution movement'
            $sourceTask.scope = 'Continue without human interaction through to TOD performing its first independent resolution.'
            $state = New-SelectionState -Objectives @(
                (New-SelectionObjective -Id 'OBJ-1' -Priority 'high' -Title 'TOD independent resolution movement')
            ) -Tasks @(
                $sourceTask
            )
            $terminalOutcome = [pscustomobject]@{
                classification = 'completed_with_evidence'
                task_id = 'TSK-1'
                objective_id = 'OBJ-1'
                summary = 'Previous independent resolution training step completed with evidence.'
            }

            $plan = New-TodNextTaskSelectionPlan -State $state -TerminalOutcome $terminalOutcome -TriggerReason 'terminal_task_outcome'

            [string]$plan.selection_kind | Should Be 'independent_resolution_packet_formation_recovery_new'
            [string]$plan.dispatch_status | Should Be 'not_started'
            $plan.create_task | Should Not BeNullOrEmpty
            [string]$plan.create_task.task_category | Should Be 'packet_formation'
            [string]$plan.create_task.assigned_executor | Should Be 'local'
            [string]$plan.create_task.scope | Should Match 'Target File: runtime_remote_training/tod_independent_resolution_attempts/TOD_PACKET_FORMATION_INDEPENDENT_RECOVERY.latest.json'
            [string]$plan.create_task.scope | Should Match 'Edit Mode: artifact_write'
            [string]$plan.create_task.scope | Should Match 'exact old_text from current code'
            [string]$plan.create_task.scope | Should Match 'Do not count packet formation as an independent resolution'
            (@($plan.expected_evidence) -join ' ') | Should Match 'packet_formation_artifact'
            (@($plan.expected_evidence) -join ' ') | Should Match 'no_independent_resolution_credit'
            @(@($plan.rejected_candidates) | Where-Object {
                [string]$_.task_id -eq 'synthesized_independent_resolution_candidate:studio_training_explanation_mode' -and
                [string]$_.reason -eq 'synthesized_candidate_not_materialized_as_behavior_changing_edit'
            }).Count | Should Be 1
        }
    }

    It 'creates packet formation from a bounded edit recovery contract before generic recovery' {
        Invoke-WithIsolatedPacketRepoRoot {
            $sourceTask = New-SelectionTask -Id 'TSK-GATEWAY-BLOCKED' -ObjectiveId 'OBJ-GATEWAY' -Status 'blocked' -Title 'Align MIM implementation dispatch'
            $sourceTask.task_category = 'code_change'
            $sourceTask.scope = 'Replan bounded slice: Add or adjust one deterministic dispatch rule for this objective.'
            $state = New-SelectionState -Objectives @(
                (New-SelectionObjective -Id 'OBJ-GATEWAY' -Priority 'high' -Title 'MIM implementation dispatch recovery')
            ) -Tasks @(
                $sourceTask
            )
            $terminalOutcome = [pscustomobject]@{
                classification = 'failed_recoverable'
                task_id = 'TSK-GATEWAY-BLOCKED'
                objective_id = 'OBJ-GATEWAY'
                reason_code = 'blocked_missing_bounded_edit_mode'
                summary = 'TOD cannot downgrade a behavior-changing code_change request to validation_only.'
                blockers = @(
                    [pscustomobject]@{
                        reason_code = 'blocked_missing_bounded_edit_mode'
                        recovery_contract = [pscustomobject]@{
                            status = 'packet_required_before_local_execution'
                            target_file = 'core/routers/gateway.py'
                            validation_command = 'python -m unittest tests.integration.test_mim_tod_handoff_gateway.MimTodHandoffGatewayTest.test_implementation_objective_route_writes_current_tod_request'
                            required_packet_fields = @('target_file', 'edit_mode', 'exact_current_anchor_or_old_text', 'different_new_text', 'validation_command', 'closure_evidence', 'prevention_lesson', 'dave_needed')
                            dave_needed = 'no'
                        }
                    }
                )
            }

            $plan = New-TodNextTaskSelectionPlan -State $state -TerminalOutcome $terminalOutcome -TriggerReason 'terminal_task_outcome'

            [string]$plan.selection_kind | Should Be 'recovery_contract_packet_formation'
            [string]$plan.dispatch_status | Should Be 'not_started'
            $plan.create_task | Should Not BeNullOrEmpty
            [string]$plan.create_task.task_category | Should Be 'packet_formation'
            [string]$plan.create_task.assigned_executor | Should Be 'local'
            [string]$plan.create_task.scope | Should Match 'Inspect Target File: core/routers/gateway.py'
            [string]$plan.create_task.scope | Should Match 'exact_current_anchor_or_old_text'
            [string]$plan.create_task.scope | Should Match 'packet_candidate_ready'
            (@($plan.expected_evidence) -join ' ') | Should Match 'recovery_contract_packet_formation_artifact'
            (@($plan.validation_plan) -join ' ') | Should Match 'recovery-contract packet-formation'
        }
    }

    It 'blocks recovery-contract packet formation when no-packet behavior selection is requested' {
        Invoke-WithIsolatedPacketRepoRoot {
            $sourceTask = New-SelectionTask -Id 'TSK-GATEWAY-BLOCKED' -ObjectiveId 'OBJ-GATEWAY' -Status 'blocked' -Title 'Align MIM implementation dispatch'
            $sourceTask.task_category = 'code_change'
            $sourceTask.scope = 'Replan bounded slice: Add or adjust one deterministic dispatch rule for this objective.'
            $state = New-SelectionState -Objectives @(
                (New-SelectionObjective -Id 'OBJ-GATEWAY' -Priority 'high' -Title 'MIM implementation dispatch recovery')
            ) -Tasks @(
                $sourceTask
            )
            $terminalOutcome = [pscustomobject]@{
                classification = 'failed_recoverable'
                task_id = 'TSK-GATEWAY-BLOCKED'
                objective_id = 'OBJ-GATEWAY'
                reason_code = 'blocked_missing_bounded_edit_mode'
                summary = 'TOD cannot downgrade a behavior-changing code_change request to validation_only.'
                blockers = @(
                    [pscustomobject]@{
                        reason_code = 'blocked_missing_bounded_edit_mode'
                        recovery_contract = [pscustomobject]@{
                            status = 'packet_required_before_local_execution'
                            target_file = 'core/routers/gateway.py'
                            validation_command = 'python -m py_compile .\core\routers\gateway.py'
                            required_packet_fields = @('target_file', 'edit_mode', 'exact_current_anchor_or_old_text', 'different_new_text', 'validation_command', 'closure_evidence', 'prevention_lesson', 'dave_needed')
                            dave_needed = 'no'
                        }
                    }
                )
            }

            $plan = New-TodNextTaskSelectionPlan -State $state -TerminalOutcome $terminalOutcome -TriggerReason 'Forbidden: packet_formation. Acceptable outcomes only: ready behavior-changing selector or blocked_no_viable_behavior_candidate with inspected_files and reason.'

            [string]$plan.selection_kind | Should Be 'blocked_no_viable_behavior_candidate'
            [string]$plan.dispatch_status | Should Be 'blocked_with_reason'
            $plan.create_task | Should BeNullOrEmpty
            (@($plan.inspected_files) -join ' ') | Should Match 'core/routers/gateway.py'
            [string]$plan.blocked_reason | Should Match 'packet formation is forbidden'
            [string]$plan.blocker.required_next_action | Should Match 'Inspect a different current-code target'
            (@($plan.expected_evidence) -join ' ') | Should Match 'recovery_contract_packet_formation_blocked'
            (@($plan.validation_plan) -join ' ') | Should Match 'packet formation is forbidden'
        }
    }

    It 'skips consumed fresh synthesis and blocks with current-code packet guidance' {
        Invoke-WithIsolatedPacketRepoRoot {
            $state = New-SelectionState -Objectives @(
                (New-SelectionObjective -Id 'OBJ-1' -Priority 'high')
            ) -Tasks @(
                (New-SelectionTask -Id 'TSK-1' -ObjectiveId 'OBJ-1' -Status 'completed' -Title 'Completed source task')
            )
            $terminalOutcome = [pscustomobject]@{
                classification = 'completed_with_evidence'
                task_id = 'TSK-1'
                objective_id = 'OBJ-1'
                summary = 'Previous task completed with evidence.'
            }

            $plan = New-TodNextTaskSelectionPlan -State $state -TerminalOutcome $terminalOutcome -TriggerReason 'Dave-away independent TOD resolution movement from TOD_DIFFERENT_TARGET_DISCOVERY_DRILL discovery candidate'

            [string]$plan.selection_kind | Should Be 'independent_resolution_packet_formation_recovery_new'
            [string]$plan.dispatch_status | Should Be 'not_started'
            $plan.create_task | Should Not BeNullOrEmpty
            [string]$plan.create_task.task_category | Should Be 'packet_formation'
            [string]$plan.create_task.scope | Should Match 'Edit Mode: artifact_write'
            [string]$plan.create_task.scope | Should Match 'exact old_text from current code'
            @(@($plan.rejected_candidates) | Where-Object {
                [string]$_.task_id -eq 'synthesized_independent_resolution_candidate:studio_training_explanation_mode' -and
                [string]$_.reason -eq 'synthesized_candidate_not_materialized_as_behavior_changing_edit'
            }).Count | Should Be 1
            @(@($plan.rejected_candidates) | Where-Object {
                [string]$_.task_id -eq 'synthesized_independent_resolution_candidate:fresh_current_code_candidate_packet_requirement' -and
                [string]$_.reason -eq 'synthesized_candidate_not_materialized_as_behavior_changing_edit'
            }).Count | Should Be 1
            (@($plan.validation_plan) -join ' ') | Should Match 'current-code packet'
        }
    }

    It 'promotes different-target discovery candidates into packet formation before no-viable blocking' {
        Invoke-WithIsolatedPacketRepoRoot {
            $attemptRoot = Join-Path $global:repoRoot 'runtime_remote_training/tod_independent_resolution_attempts'
            New-Item -Path $attemptRoot -ItemType Directory -Force | Out-Null
            [pscustomobject]@{
                artifact_type = 'tod_different_target_discovery_drill'
                generated_at = '2026-06-16T17:39:48Z'
                status = 'candidate_selected'
                selected_candidate_or_none = [pscustomobject]@{
                    candidate_key = 'public_chat_context_followup_direct_answer_guard'
                    target_file = 'tmp_remote_mim/core/routers/public_chat.py'
                    target_function_or_rule = '_build_public_fallback_reply and public follow-up context routing'
                    behavior_delta_one_sentence = 'Keep public MIM follow-up questions grounded in the prior turn.'
                    validation_command = 'python -m py_compile tmp_remote_mim/core/routers/public_chat.py'
                    expected_changed_files = @('tmp_remote_mim/core/routers/public_chat.py')
                    rollback_note = 'Revert the public chat follow-up routing change.'
                    prevention_lesson = 'Discovery must pivot away from forbidden Studio candidates.'
                }
            } | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $attemptRoot 'TOD_DIFFERENT_TARGET_DISCOVERY_DRILL.latest.json') -Encoding UTF8

            $state = New-SelectionState -Objectives @(
                (New-SelectionObjective -Id 'OBJ-1' -Priority 'high')
            ) -Tasks @(
                (New-SelectionTask -Id 'TSK-LOOP' -ObjectiveId 'OBJ-1' -Status 'completed' -Title 'Form current-code packet for independent TOD resolution' -TaskCategory 'packet_formation')
            )
            $terminalOutcome = [pscustomobject]@{
                classification = 'completed_with_evidence'
                task_id = 'TSK-LOOP'
                objective_id = 'OBJ-1'
                summary = 'Packet formation completed with inspected blocker evidence.'
            }

            $plan = New-TodNextTaskSelectionPlan -State $state -TerminalOutcome $terminalOutcome -TriggerReason 'Dave-away independent TOD resolution movement'

            [string]$plan.selection_kind | Should Be 'different_target_discovery_packet_formation'
            [string]$plan.dispatch_status | Should Be 'not_started'
            $plan.create_task | Should Not BeNullOrEmpty
            [string]$plan.create_task.task_category | Should Be 'packet_formation'
            [string]$plan.create_task.scope | Should Match 'tmp_remote_mim/core/routers/public_chat.py'
            [string]$plan.create_task.scope | Should Match 'public_chat_context_followup_direct_answer_guard'
            [string]$plan.create_task.scope | Should Match 'exact old_text from current code'
            (@($plan.expected_evidence) -join ' ') | Should Match 'different_target_discovery_candidate'
            (@($plan.validation_plan) -join ' ') | Should Match 'discovery target'
        }
    }

    It 'rejects stale different-target discovery candidates forbidden by the current drill' {
        Invoke-WithIsolatedPacketRepoRoot {
            $attemptRoot = Join-Path $global:repoRoot 'runtime_remote_training/tod_independent_resolution_attempts'
            $interventionRoot = Join-Path $global:repoRoot 'runtime_remote_training/codex_training_interventions'
            New-Item -Path $attemptRoot -ItemType Directory -Force | Out-Null
            New-Item -Path $interventionRoot -ItemType Directory -Force | Out-Null

            [pscustomobject]@{
                artifact_type = 'tod_different_target_discovery_drill'
                generated_at = '2026-06-16T17:39:48Z'
                status = 'candidate_selected'
                selected_candidate_or_none = [pscustomobject]@{
                    candidate_key = 'public_chat_context_followup_direct_answer_guard'
                    target_file = 'tmp_remote_mim/core/routers/public_chat.py'
                    target_function_or_rule = '_build_public_fallback_reply and public follow-up context routing'
                    behavior_delta_one_sentence = 'Keep public MIM follow-up questions grounded in the prior turn.'
                    validation_command = 'python -m py_compile tmp_remote_mim/core/routers/public_chat.py'
                    expected_changed_files = @('tmp_remote_mim/core/routers/public_chat.py')
                    rollback_note = 'Revert the public chat follow-up routing change.'
                    prevention_lesson = 'Discovery must pivot away from forbidden Studio candidates.'
                }
            } | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $attemptRoot 'TOD_DIFFERENT_TARGET_DISCOVERY_DRILL.latest.json') -Encoding UTF8

            [pscustomobject]@{
                artifact_version = 'codex-training-intervention-v1'
                generated_at = '2026-06-16T20:10:00Z'
                status = 'training_instruction_issued'
                tod_training_instruction = [pscustomobject]@{
                    action = 'Inspect different current-code targets.'
                    forbidden_paths = @(
                        'tmp_remote_mim/core/routers/public_chat.py',
                        'runtime_remote_training/tod_independent_resolution_attempts/TOD_PACKET_FORMATION_MATERIALIZATION_RECOVERY.latest.json'
                    )
                }
            } | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $interventionRoot 'CODEX_TOD_DIFFERENT_TARGET_DISCOVERY_DRILL_20260616T2010Z.latest.json') -Encoding UTF8

            $state = New-SelectionState -Objectives @(
                (New-SelectionObjective -Id 'OBJ-1' -Priority 'high')
            ) -Tasks @(
                (New-SelectionTask -Id 'TSK-LOOP' -ObjectiveId 'OBJ-1' -Status 'completed' -Title 'Form current-code packet for independent TOD resolution' -TaskCategory 'packet_formation')
            )
            $terminalOutcome = [pscustomobject]@{
                classification = 'completed_with_evidence'
                task_id = 'TSK-LOOP'
                objective_id = 'OBJ-1'
                summary = 'Packet formation completed with inspected blocker evidence.'
            }

            $plan = New-TodNextTaskSelectionPlan -State $state -TerminalOutcome $terminalOutcome -TriggerReason 'Dave-away independent TOD resolution movement'

            @(@($plan.rejected_candidates) | Where-Object {
                [string]$_.reason -eq 'discovery_target_forbidden_by_current_drill' -and
                [string]$_.target_file -eq 'tmp_remote_mim/core/routers/public_chat.py'
            }).Count | Should Be 1
            [string]$plan.selection_kind | Should Not Be 'different_target_discovery_packet_formation'
            if ($plan.create_task) {
                [string]$plan.create_task.scope | Should Not Match 'Inspect Target File: tmp_remote_mim/core/routers/public_chat.py'
            }
            (@($plan.validation_plan) -join ' ') | Should Match 'forbidden by the current different-target drill'
        }
    }

    It 'refreshes different-target discovery when a stale gateway loop asks for discovery pressure' {
        Invoke-WithIsolatedPacketRepoRoot {
            $attemptRoot = Join-Path $global:repoRoot 'runtime_remote_training/tod_independent_resolution_attempts'
            $interventionRoot = Join-Path $global:repoRoot 'runtime_remote_training/codex_training_interventions'
            New-Item -Path $attemptRoot -ItemType Directory -Force | Out-Null
            New-Item -Path $interventionRoot -ItemType Directory -Force | Out-Null

            [pscustomobject]@{
                artifact_type = 'tod_different_target_discovery_drill'
                generated_at = '2026-06-17T05:22:56Z'
                status = 'candidate_selected'
                selected_candidate_or_none = [pscustomobject]@{
                    candidate_key = 'operator_router_exception_reason_actionability_guard'
                    target_file = 'tmp_remote_mim/core/routers/operator.py'
                    validation_command = 'python -m py_compile tmp_remote_mim/core/routers/operator.py'
                    rollback_note = 'Revert operator router change.'
                    prevention_lesson = 'Avoid consumed operator target.'
                }
            } | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $attemptRoot 'TOD_DIFFERENT_TARGET_DISCOVERY_DRILL.latest.json') -Encoding UTF8

            [pscustomobject]@{
                artifact_type = 'tod_packet_formation_artifact'
                generated_at = '2026-06-17T09:07:51Z'
                status = 'blocked_candidate_already_applied'
                task_id = 'TSK-3334'
                packet_candidate_ready = $false
                blocker = [pscustomobject]@{
                    target_file = 'tmp_remote_mim/core/routers/operator.py'
                    reason = 'The current target already contains operator_action_required, so this packet would be a no-op.'
                }
            } | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $attemptRoot 'TOD_PACKET_FORMATION_INDEPENDENT_RECOVERY.latest.json') -Encoding UTF8

            $state = New-SelectionState -Objectives @(
                (New-SelectionObjective -Id 'OBJ-1' -Priority 'high')
            ) -Tasks @(
                (New-SelectionTask -Id 'TSK-GATEWAY-REPLAN' -ObjectiveId 'OBJ-1' -Status 'completed' -Title 'Chat task gateway replan' -TaskCategory 'chat_execution')
            )
            $terminalOutcome = [pscustomobject]@{
                classification = 'completed_with_evidence'
                task_id = 'TSK-GATEWAY-REPLAN'
                objective_id = 'OBJ-1'
                summary = 'Old gateway replan completed without a fresh behavior target.'
            }

            $plan = New-TodNextTaskSelectionPlan -State $state -TerminalOutcome $terminalOutcome -TriggerReason 'Dave-away independent TOD resolutions different-target discovery: inspect another current-code target after operator.py was rejected.'

            [string]$plan.selection_kind | Should Be 'different_target_discovery_refresh'
            $plan.create_task | Should Not BeNullOrEmpty
            [string]$plan.create_task.task_category | Should Be 'packet_formation'
            [string]$plan.create_task.scope | Should Match 'TOD_DIFFERENT_TARGET_DISCOVERY_DRILL.latest.json'
            [string]$plan.create_task.scope | Should Match 'Validation Pattern: selected_candidate_or_none'
            [string]$plan.create_task.scope | Should Match 'tmp_remote_mim/core/routers/operator.py'
            [string]$plan.create_task.scope | Should Match 'selected_candidate_or_none'
            (@($plan.expected_evidence) -join ' ') | Should Match 'different_target_discovery_refresh'
        }
    }

    It 'refreshes different-target discovery when materialization blocker requires a different target' {
        Invoke-WithIsolatedPacketRepoRoot {
            $attemptRoot = Join-Path $global:repoRoot 'runtime_remote_training/tod_independent_resolution_attempts'
            New-Item -Path $attemptRoot -ItemType Directory -Force | Out-Null

            [pscustomobject]@{
                artifact_type = 'tod_different_target_discovery_drill'
                generated_at = '2026-06-17T10:01:33Z'
                status = 'candidate_selected'
                selected_candidate_or_none = [pscustomobject]@{
                    candidate_key = 'interaction_quality_dashboard_stale_artifact_context_guard'
                    target_file = 'tmp_remote_mim/core/interaction_quality_dashboard.py'
                    validation_command = 'python -m py_compile tmp_remote_mim/core/interaction_quality_dashboard.py'
                    rollback_note = 'Revert dashboard freshness change.'
                    prevention_lesson = 'Avoid already-applied dashboard target.'
                }
            } | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $attemptRoot 'TOD_DIFFERENT_TARGET_DISCOVERY_DRILL.latest.json') -Encoding UTF8

            [pscustomobject]@{
                artifact_type = 'tod_packet_formation_artifact'
                generated_at = '2026-06-17T10:53:55Z'
                status = 'blocked_candidate_already_applied'
                task_id = 'TSK-3342'
                packet_candidate_ready = $false
                blocker = [pscustomobject]@{
                    target_file = 'tmp_remote_mim/core/interaction_quality_dashboard.py'
                    reason = 'The current target already contains "stale_artifacts", so this packet would be a no-op.'
                    required_next_action = 'Choose a different current-code behavior gap before emitting another packet candidate.'
                }
            } | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $attemptRoot 'TOD_PACKET_FORMATION_MATERIALIZATION_RECOVERY.latest.json') -Encoding UTF8

            $state = New-SelectionState -Objectives @(
                (New-SelectionObjective -Id 'OBJ-1' -Priority 'high')
            ) -Tasks @(
                (New-SelectionTask -Id 'TSK-3342' -ObjectiveId 'OBJ-1' -Status 'completed' -Title 'Form materialized bounded edit proof after consumed packet anchor' -TaskCategory 'packet_formation')
            )
            $terminalOutcome = [pscustomobject]@{
                classification = 'completed_with_evidence'
                task_id = 'TSK-3342'
                objective_id = 'OBJ-1'
                summary = 'LocalExecutionEngine completed the bounded local fallback for TOD_PACKET_FORMATION_MATERIALIZATION_RECOVERY.latest.json and published real execution evidence.'
            }

            $plan = New-TodNextTaskSelectionPlan -State $state -TerminalOutcome $terminalOutcome -TriggerReason 'Dave-away independent TOD resolutions different-target discovery: choose a different current-code behavior gap after already-applied packet.'

            [string]$plan.selection_kind | Should Be 'different_target_discovery_refresh'
            $plan.create_task | Should Not BeNullOrEmpty
            [string]$plan.create_task.scope | Should Match 'Validation Pattern: selected_candidate_or_none'
            [string]$plan.create_task.scope | Should Match 'tmp_remote_mim/core/interaction_quality_dashboard.py'
            @(@($plan.rejected_candidates) | Where-Object {
                [string]$_.reason -eq 'discovery_target_forbidden_by_current_drill' -and
                [string]$_.target_file -eq 'tmp_remote_mim/core/interaction_quality_dashboard.py'
            }).Count | Should Be 1
            (@($plan.validation_plan) -join ' ') | Should Match 'forbidden by the current different-target drill'
        }
    }

    It 'refreshes stale discovery after an already-applied materialization blocker without magic trigger wording' {
        Invoke-WithIsolatedPacketRepoRoot {
            $attemptRoot = Join-Path $global:repoRoot 'runtime_remote_training/tod_independent_resolution_attempts'
            New-Item -Path $attemptRoot -ItemType Directory -Force | Out-Null

            [pscustomobject]@{
                artifact_type = 'tod_different_target_discovery_drill'
                generated_at = '2026-06-17T11:45:56Z'
                status = 'candidate_selected'
                selected_candidate_or_none = [pscustomobject]@{
                    candidate_key = 'communication_composer_working_on_answer_first_fallback'
                    target_file = 'tmp_remote_mim/core/communication_composer.py'
                    target_function_or_rule = '_contextual_answer_first_reply working-on prompt fallback'
                    behavior_delta_one_sentence = 'Answer working-on prompts even when active goal context is missing.'
                    validation_command = 'python -m py_compile tmp_remote_mim/core/communication_composer.py'
                    expected_changed_files = @('tmp_remote_mim/core/communication_composer.py')
                    rollback_note = 'Revert communication composer fallback.'
                    prevention_lesson = 'Discovery must not repeat a no-op packet target.'
                }
            } | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $attemptRoot 'TOD_DIFFERENT_TARGET_DISCOVERY_DRILL.latest.json') -Encoding UTF8

            [pscustomobject]@{
                artifact_type = 'tod_packet_formation_artifact'
                generated_at = '2026-06-17T13:28:06Z'
                status = 'blocked_candidate_already_applied'
                task_id = 'TSK-3353'
                packet_candidate_ready = $false
                blocker = [pscustomobject]@{
                    target_file = 'tmp_remote_mim/core/communication_composer.py'
                    reason = 'The current target already contains clear answer or next useful action, so this packet would be a no-op.'
                    inspected_files = @('runtime/shared/TOD_NEXT_TASK_SELECTION.latest.json', 'tmp_remote_mim/core/communication_composer.py')
                    required_next_action = 'Choose a different current-code behavior gap before emitting another packet candidate.'
                }
            } | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $attemptRoot 'TOD_PACKET_FORMATION_MATERIALIZATION_RECOVERY.latest.json') -Encoding UTF8

            $state = New-SelectionState -Objectives @(
                (New-SelectionObjective -Id 'OBJ-1' -Priority 'high')
            ) -Tasks @(
                (New-SelectionTask -Id 'TSK-3353' -ObjectiveId 'OBJ-1' -Status 'completed' -Title 'Form materialized bounded edit proof for recovery backlog' -TaskCategory 'packet_formation')
            )
            $terminalOutcome = [pscustomobject]@{
                classification = 'completed_with_evidence'
                task_id = 'TSK-3353'
                objective_id = 'OBJ-1'
                summary = 'Packet formation blocked because the candidate was already applied.'
            }

            $plan = New-TodNextTaskSelectionPlan -State $state -TerminalOutcome $terminalOutcome -TriggerReason 'Independent TOD resolution selector field contract repair before independent credit'

            [string]$plan.selection_kind | Should Be 'different_target_discovery_refresh'
            $plan.create_task | Should Not BeNullOrEmpty
            [string]$plan.create_task.scope | Should Match 'Forbidden target paths for this discovery'
            [string]$plan.create_task.scope | Should Match 'tmp_remote_mim/core/communication_composer.py'
            @(@($plan.rejected_candidates) | Where-Object {
                [string]$_.reason -eq 'discovery_target_forbidden_by_current_drill' -and
                [string]$_.target_file -eq 'tmp_remote_mim/core/communication_composer.py'
            }).Count | Should Be 1
            (@($plan.expected_evidence) -join ' ') | Should Match 'different_target_discovery_refresh'
        }
    }

    It 'reruns broadened different-target discovery after a no-viable discovery blocker' {
        Invoke-WithIsolatedPacketRepoRoot {
            $attemptRoot = Join-Path $global:repoRoot 'runtime_remote_training/tod_independent_resolution_attempts'
            New-Item -Path $attemptRoot -ItemType Directory -Force | Out-Null

            [pscustomobject]@{
                artifact_type = 'tod_different_target_discovery_drill'
                generated_at = '2026-06-17T11:25:47Z'
                status = 'blocked_no_viable_candidate'
                task_id = 'TSK-3346'
                objective_id = 'OBJ-1'
                selected_candidate_or_none = $null
                blocker = [pscustomobject]@{
                    reason_code = 'all_discovery_candidates_forbidden'
                    required_next_action = 'Broaden TOD discovery candidate definitions or inspect a new current-code surface outside the forbidden target set.'
                }
            } | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $attemptRoot 'TOD_DIFFERENT_TARGET_DISCOVERY_DRILL.latest.json') -Encoding UTF8

            $state = New-SelectionState -Objectives @(
                (New-SelectionObjective -Id 'OBJ-1' -Priority 'high')
            ) -Tasks @(
                (New-SelectionTask -Id 'TSK-3346' -ObjectiveId 'OBJ-1' -Status 'completed' -Title 'Run different-target discovery after stale discovery candidate' -TaskCategory 'packet_formation')
            )
            $terminalOutcome = [pscustomobject]@{
                classification = 'completed_with_evidence'
                task_id = 'TSK-3346'
                objective_id = 'OBJ-1'
                summary = 'LocalExecutionEngine completed the bounded local fallback for TOD_DIFFERENT_TARGET_DISCOVERY_DRILL.latest.json and published no viable evidence.'
            }

            $plan = New-TodNextTaskSelectionPlan -State $state -TerminalOutcome $terminalOutcome -TriggerReason 'Dave-away independent TOD resolution: broaden different-target discovery after no viable candidate.'

            [string]$plan.selection_kind | Should Be 'different_target_discovery_broaden_after_no_viable'
            $plan.create_task | Should Not BeNullOrEmpty
            [string]$plan.create_task.scope | Should Match 'Validation Pattern: selected_candidate_or_none'
            [string]$plan.create_task.scope | Should Match 'blocked_no_viable_candidate'
            (@($plan.expected_evidence) -join ' ') | Should Match 'different_target_discovery_broadened_after_no_viable'
        }
    }

    It 'blocks repeated packet formation when the latest packet blocker belongs to the terminal task' {
        $originalRepoRoot = $global:repoRoot
        $tempRepoRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('tod-selection-packet-loop-' + [guid]::NewGuid().ToString('N'))
        try {
            $global:repoRoot = $tempRepoRoot
            $attemptRoot = Join-Path $tempRepoRoot 'runtime_remote_training/tod_independent_resolution_attempts'
            New-Item -Path $attemptRoot -ItemType Directory -Force | Out-Null
            foreach ($packetStatus in @('blocked_current_code_anchor_missing', 'blocked_candidate_already_applied')) {
                $blockedPacket = [pscustomobject]@{
                    artifact_type = 'tod_packet_formation_artifact'
                    generated_at = '2026-06-14T12:23:09Z'
                    status = $packetStatus
                    task_id = 'TSK-LOOP'
                    packet_candidate_ready = $false
                    blocker = [pscustomobject]@{
                        target_file = 'scripts/run_mim_durability_smoke_v2.py'
                        reason = 'Packet formation could not produce a fresh bounded old_text/new_text edit.'
                    }
                }
                $blockedPacket | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $attemptRoot 'TOD_PACKET_FORMATION_INDEPENDENT_RECOVERY.latest.json') -Encoding UTF8
                [pscustomobject]@{
                    artifact_type = 'tod_packet_formation_artifact'
                    generated_at = '2026-06-14T12:23:59Z'
                    status = 'blocked_candidate_already_applied'
                    task_id = 'TSK-SELECTOR-PREFERENCE'
                    packet_candidate_ready = $false
                    blocker = [pscustomobject]@{
                        target_file = 'scripts/TOD.ps1'
                        reason = 'Selector preference packet recovery is already applied.'
                        required_next_action = 'Choose a different current-code behavior gap before emitting another packet candidate.'
                    }
                } | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $attemptRoot 'TOD_PACKET_FORMATION_SELECTOR_PREFERENCE_RECOVERY.latest.json') -Encoding UTF8
                Start-Sleep -Milliseconds 25
                [pscustomobject]@{
                    artifact_type = 'tod_packet_formation_artifact'
                    generated_at = '2026-06-14T12:24:09Z'
                    status = 'blocked_missing_actionable_fields'
                    task_id = 'TSK-AUX'
                    packet_candidate_ready = $false
                    missing_fields = @('target_file', 'old_text', 'new_text')
                } | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $attemptRoot 'TOD_PACKET_FORMATION_AUXILIARY_2026_06_14.latest.json') -Encoding UTF8

                $state = New-SelectionState -Objectives @(
                    (New-SelectionObjective -Id 'OBJ-1' -Priority 'high')
                ) -Tasks @(
                    (New-SelectionTask -Id 'TSK-LOOP' -ObjectiveId 'OBJ-1' -Status 'completed' -Title 'Form current-code packet for independent TOD resolution' -TaskCategory 'packet_formation')
                )
                $terminalOutcome = [pscustomobject]@{
                    classification = 'completed_with_evidence'
                    task_id = 'TSK-LOOP'
                    objective_id = 'OBJ-1'
                    summary = 'Packet formation completed with inspected blocker evidence.'
                }

                $plan = New-TodNextTaskSelectionPlan -State $state -TerminalOutcome $terminalOutcome -TriggerReason 'Dave-away independent TOD resolution movement'

                [string]$plan.selection_kind | Should Be 'blocked_no_viable_behavior_candidate'
                [string]$plan.dispatch_status | Should Be 'blocked_with_reason'
                $plan.create_task | Should BeNullOrEmpty
                (@($plan.inspected_files) -join ' ') | Should Match 'TOD_PACKET_FORMATION_INDEPENDENT_RECOVERY'
                (@($plan.inspected_files) -join ' ') | Should Match 'TOD_PACKET_FORMATION_SELECTOR_PREFERENCE_RECOVERY'
                (@($plan.inspected_files) -join ' ') | Should Match 'scripts/TOD.ps1'
                [string]$plan.blocked_reason | Should Match 'No viable fresh behavior-changing candidate'
                [string]$plan.blocker.required_next_action | Should Match 'Inspect a different current-code target'
                (@($plan.expected_evidence) -join ' ') | Should Match 'no_viable_behavior_candidate'
                (@($plan.expected_evidence) -join ' ') | Should Match 'packet_formation_terminal_blocker'
                (@($plan.expected_evidence) -join ' ') | Should Match 'behavior_changing_candidate_required'
                (@($plan.validation_plan) -join ' ') | Should Match 'no viable behavior-changing candidate'
            }
        }
        finally {
            $global:repoRoot = $originalRepoRoot
            if (Test-Path -Path $tempRepoRoot) {
                Remove-Item -Path $tempRepoRoot -Recurse -Force
            }
        }
    }

    It 'refreshes different-target discovery when selected candidate is already applied in current code' {
        Invoke-WithIsolatedPacketRepoRoot {
            $attemptRoot = Join-Path $global:repoRoot 'runtime_remote_training/tod_independent_resolution_attempts'
            $resultsPath = Join-Path $global:repoRoot 'tmp_remote_mim/core/routers/results.py'
            New-Item -Path (Split-Path -Parent $resultsPath) -ItemType Directory -Force | Out-Null
            Set-TodSelectionTestFileText -Path $resultsPath -Content @'
def create_result_response():
    return {
        "objective_recompute_evidence": {
            "continuation_source": "results_route",
        },
    }
'@

            [pscustomobject]@{
                artifact_type = 'tod_different_target_discovery_drill'
                generated_at = '2026-06-17T22:04:26Z'
                status = 'candidate_selected'
                task_id = 'TSK-DISCOVERY'
                objective_id = 'OBJ-1'
                selected_candidate_or_none = [pscustomobject]@{
                    candidate_key = 'results_router_objective_recompute_evidence_guard'
                    target_file = 'tmp_remote_mim/core/routers/results.py'
                    behavior_delta_one_sentence = 'Expose objective recompute evidence on result creation responses.'
                    validation_command = 'python -m py_compile tmp_remote_mim/core/routers/results.py'
                    rollback_note = 'Revert the result evidence payload.'
                    prevention_lesson = 'Do not dispatch stale discovery candidates that are already present in current code.'
                }
            } | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $attemptRoot 'TOD_DIFFERENT_TARGET_DISCOVERY_DRILL.latest.json') -Encoding UTF8

            $state = New-SelectionState -Objectives @(
                (New-SelectionObjective -Id 'OBJ-1' -Priority 'high')
            ) -Tasks @(
                (New-SelectionTask -Id 'TSK-PACKET' -ObjectiveId 'OBJ-1' -Status 'completed' -Title 'Form current-code packet from different-target discovery' -TaskCategory 'packet_formation')
            )
            $terminalOutcome = [pscustomobject]@{
                classification = 'completed_with_evidence'
                task_id = 'TSK-PACKET'
                objective_id = 'OBJ-1'
                summary = 'Packet formation blocked after current target appeared already applied.'
            }

            $plan = New-TodNextTaskSelectionPlan -State $state -TerminalOutcome $terminalOutcome -TriggerReason 'Dave-away independent TOD resolution: different-target discovery candidate may be already applied.'

            [string]$plan.selection_kind | Should Be 'different_target_discovery_refresh'
            $plan.create_task | Should Not BeNullOrEmpty
            [string]$plan.create_task.task_category | Should Be 'packet_formation'
            [string]$plan.create_task.scope | Should Match 'Validation Pattern: selected_candidate_or_none'
            (@($plan.expected_evidence) -join ' ') | Should Match 'different_target_discovery_already_applied_rejected'
            (@($plan.validation_plan) -join ' ') | Should Match 'objective_recompute_evidence'
            @(@($plan.rejected_candidates) | Where-Object {
                [string]$_.reason -eq 'discovery_target_already_contains_applied_marker' -and
                [string]$_.target_file -eq 'tmp_remote_mim/core/routers/results.py'
            }).Count | Should Be 1
        }
    }

    It 'selects same-objective packet formation before retrying independent synthesis' {
        Invoke-WithIsolatedPacketRepoRoot {
            $sourceTask = New-SelectionTask -Id 'TSK-1' -ObjectiveId 'OBJ-1' -Status 'completed' -Title 'Independent TOD resolution movement'
            $sourceTask.scope = 'Continue without human interaction through to TOD performing an independent resolution.'
            $packetTask = New-SelectionTask -Id 'TSK-PACKET' -ObjectiveId 'OBJ-1' -Status 'planned' -Title 'Form bounded runtime-code packet from blocker evidence'
            $packetTask.task_category = 'packet_formation'
            $packetTask.scope = @'
Use the latest independent-resolution blocker to form the next bounded runtime-code packet.
Expected output: publish a packet candidate artifact or a precise blocker.
'@
            $state = New-SelectionState -Objectives @(
                (New-SelectionObjective -Id 'OBJ-1' -Priority 'high' -Title 'TOD independent resolution movement')
            ) -Tasks @(
                $sourceTask,
                $packetTask
            )
            $terminalOutcome = [pscustomobject]@{
                classification = 'no_op_rejected'
                task_id = 'TSK-1'
                objective_id = 'OBJ-1'
                summary = 'Previous independent resolution attempt produced no materialized code candidate.'
            }

            $plan = New-TodNextTaskSelectionPlan -State $state -TerminalOutcome $terminalOutcome -TriggerReason 'Dave-away independent TOD resolution movement'

            [string]$plan.selection_kind | Should Be 'same_objective_packet_formation_recovery'
            [string]$plan.selected_task_id | Should Be 'TSK-PACKET'
            [string]$plan.dispatch_status | Should Be 'not_started'
            (@($plan.expected_evidence) -join ' ') | Should Match 'packet_formation_artifact'
            (@($plan.expected_evidence) -join ' ') | Should Match 'no_independent_resolution_credit'
            (@($plan.validation_plan) -join ' ') | Should Match 'bounded runtime-code packet'
        }
    }

    It 'turns an actionable independent-resolution packet into a bounded code-change task' {
        $packetRelativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_PACKET_FORMATION_TEST_ACTIONABLE.latest.json'
        $packetPath = Join-Path $repoRoot ($packetRelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $originalContent = if (Test-Path -Path $packetPath) { Get-Content -Path $packetPath -Raw } else { $null }
        $targetPath = Join-Path $repoRoot 'scripts/run_mim_durability_smoke_v2.py'
        $originalTargetContent = if (Test-Path -Path $targetPath) { Get-Content -Path $targetPath -Raw } else { $null }

        try {
            Set-TodSelectionTestFileText -Path $targetPath -Content @'
        "summary": {
            "case_count": len(cases),
            "passed": passed,
            "failed": len(cases) - passed,
            "pass_rate_percent": round((passed / len(cases)) * 100),
            "status_leakage_failures": sum(
                1 for case in cases if case.get("checks", {}).get("no_status_report_leakage") is False
            ),
            "status_leakage_failure_rate_percent": round(
                (
                    sum(1 for case in cases if case.get("checks", {}).get("no_status_report_leakage") is False)
                    / len(cases)
                )
                * 100
            ),
            "status_leakage_pass_rate_percent": round(
                100
                - (
                    (
                        sum(1 for case in cases if case.get("checks", {}).get("no_status_report_leakage") is False)
                        / len(cases)
                    )
                    * 100
                )
            ),
            "status_leakage_checked_cases": len(cases),
        },
'@

            $packetPayload = [ordered]@{
                artifact_type = 'tod_packet_formation_artifact'
                generated_at = (Get-Date).ToUniversalTime().ToString('o')
                status = 'packet_candidate_ready'
                packet_candidate_ready = $true
                packet = [ordered]@{
                    target_file = 'scripts/run_mim_durability_smoke_v2.py'
                    intended_edit_mode = 'replace_text'
                    old_text = @'
        "summary": {
            "case_count": len(cases),
            "passed": passed,
            "failed": len(cases) - passed,
            "pass_rate_percent": round((passed / len(cases)) * 100),
            "status_leakage_failures": sum(
                1 for case in cases if case.get("checks", {}).get("no_status_report_leakage") is False
            ),
            "status_leakage_failure_rate_percent": round(
                (
                    sum(1 for case in cases if case.get("checks", {}).get("no_status_report_leakage") is False)
                    / len(cases)
                )
                * 100
            ),
            "status_leakage_pass_rate_percent": round(
                100
                - (
                    (
                        sum(1 for case in cases if case.get("checks", {}).get("no_status_report_leakage") is False)
                        / len(cases)
                    )
                    * 100
                )
            ),
            "status_leakage_checked_cases": len(cases),
        },
'@
                    new_text = @'
        "summary": {
            "case_count": len(cases),
            "passed": passed,
            "failed": len(cases) - passed,
            "pass_rate_percent": round((passed / len(cases)) * 100),
            "status_leakage_failures": sum(
                1 for case in cases if case.get("checks", {}).get("no_status_report_leakage") is False
            ),
            "status_leakage_failure_rate_percent": round(
                (
                    sum(1 for case in cases if case.get("checks", {}).get("no_status_report_leakage") is False)
                    / len(cases)
                )
                * 100
            ),
            "status_leakage_pass_rate_percent": round(
                100
                - (
                    (
                        sum(1 for case in cases if case.get("checks", {}).get("no_status_report_leakage") is False)
                        / len(cases)
                    )
                    * 100
                )
            ),
            "status_leakage_checked_cases": len(cases),
            "packet_scan_regression_marker": False,
        },
'@
                    validation_command = 'python -m py_compile scripts\run_mim_durability_smoke_v2.py'
                    validation_pattern = 'status_leakage_failures'
                    closure_evidence = 'changed smoke summary, py_compile passed, and refreshed durability artifact includes status_leakage_failures'
                    prevention_lesson = 'Consume concrete current-code packets before synthesizing another vague candidate.'
                    dave_needed = 'no'
                }
            }
            $packetPayload | ConvertTo-Json -Depth 12 | Set-Content -Path $packetPath -Encoding UTF8
            (Get-Item -Path $packetPath).LastWriteTime = (Get-Date).AddMinutes(5)

            $state = New-SelectionState -Objectives @(
                (New-SelectionObjective -Id 'OBJ-1' -Priority 'high')
            ) -Tasks @(
                (New-SelectionTask -Id 'TSK-1' -ObjectiveId 'OBJ-1' -Status 'completed' -Title 'Completed source task')
            )
            $terminalOutcome = [pscustomobject]@{
                classification = 'completed_with_evidence'
                task_id = 'TSK-1'
                objective_id = 'OBJ-1'
                summary = 'Previous independent TOD resolution training step completed with evidence.'
            }

            $plan = New-TodNextTaskSelectionPlan -State $state -TerminalOutcome $terminalOutcome -TriggerReason 'Dave-away independent TOD resolution movement'

            [string]$plan.selection_kind | Should Be 'packet_candidate_code_task'
            [string]$plan.dispatch_status | Should Be 'not_started'
            $plan.create_task | Should Not BeNullOrEmpty
            [string]$plan.create_task.objective_mode | Should Be 'existing'
            [string]$plan.create_task.objective_id | Should Be 'OBJ-1'
            [string]$plan.create_task.task_category | Should Be 'code_change'
            [string]$plan.create_task.assigned_executor | Should Be 'local'
            [string]$plan.create_task.scope | Should Match 'Target File: scripts/run_mim_durability_smoke_v2.py'
            [string]$plan.create_task.scope | Should Match 'Validation Pattern: status_leakage_failures'
            (@($plan.expected_evidence) -join ' ') | Should Match 'packet_materialized_current_code_task'
        }
        finally {
            if ([string]::IsNullOrWhiteSpace($originalContent)) {
                if (Test-Path -Path $packetPath) { Remove-Item -Path $packetPath -Force }
            }
            else {
                [System.IO.File]::WriteAllText($packetPath, $originalContent, (New-Object System.Text.UTF8Encoding($false)))
            }
            if ([string]::IsNullOrWhiteSpace($originalTargetContent)) {
                if (Test-Path -Path $targetPath) { Remove-Item -Path $targetPath -Force }
            }
            else {
                Set-TodSelectionTestFileText -Path $targetPath -Content $originalTargetContent
            }
        }
    }

    It 'skips malformed latest packet and selects an older actionable current-code packet' {
        $badRelativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_PACKET_FORMATION_TEST_LATEST_MALFORMED.latest.json'
        $goodRelativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_PACKET_FORMATION_TEST_OLDER_ACTIONABLE.latest.json'
        $badPath = Join-Path $repoRoot ($badRelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $goodPath = Join-Path $repoRoot ($goodRelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $originalBad = if (Test-Path -Path $badPath) { Get-Content -Path $badPath -Raw } else { $null }
        $originalGood = if (Test-Path -Path $goodPath) { Get-Content -Path $goodPath -Raw } else { $null }
        $targetPath = Join-Path $repoRoot 'scripts/run_mim_durability_smoke_v2.py'
        $originalTargetContent = if (Test-Path -Path $targetPath) { Get-Content -Path $targetPath -Raw } else { $null }

        try {
            Set-TodSelectionTestFileText -Path $targetPath -Content @'
        "summary": {
            "case_count": len(cases),
            "passed": passed,
            "failed": len(cases) - passed,
            "pass_rate_percent": round((passed / len(cases)) * 100),
            "status_leakage_failures": sum(
                1 for case in cases if case.get("checks", {}).get("no_status_report_leakage") is False
            ),
            "status_leakage_failure_rate_percent": round(
                (
                    sum(1 for case in cases if case.get("checks", {}).get("no_status_report_leakage") is False)
                    / len(cases)
                )
                * 100
            ),
            "status_leakage_pass_rate_percent": round(
                100
                - (
                    (
                        sum(1 for case in cases if case.get("checks", {}).get("no_status_report_leakage") is False)
                        / len(cases)
                    )
                    * 100
                )
            ),
            "status_leakage_checked_cases": len(cases),
        },
'@

            $badPayload = [ordered]@{
                artifact_type = 'tod_packet_formation_artifact'
                generated_at = (Get-Date).ToUniversalTime().ToString('o')
                status = 'packet_candidate_ready'
                packet_candidate_ready = $true
                packet = [ordered]@{
                    target_file = 'pending_current_code_anchor_selection'
                    intended_edit_mode = 'non_validation_runtime_code_edit_required_next'
                    validation_command = 'python -m py_compile scripts\run_mim_durability_smoke_v2.py'
                    closure_evidence = 'malformed newest packet should not hide older actionable packets'
                    prevention_lesson = 'Selector must scan candidate packets before blocking.'
                }
            }
            $goodPayload = [ordered]@{
                artifact_type = 'tod_packet_formation_artifact'
                generated_at = (Get-Date).ToUniversalTime().AddSeconds(-5).ToString('o')
                status = 'packet_candidate_ready'
                packet_candidate_ready = $true
                packet = [ordered]@{
                    target_file = 'scripts/run_mim_durability_smoke_v2.py'
                    intended_edit_mode = 'replace_text'
                    old_text = @'
        "summary": {
            "case_count": len(cases),
            "passed": passed,
            "failed": len(cases) - passed,
            "pass_rate_percent": round((passed / len(cases)) * 100),
            "status_leakage_failures": sum(
                1 for case in cases if case.get("checks", {}).get("no_status_report_leakage") is False
            ),
            "status_leakage_failure_rate_percent": round(
                (
                    sum(1 for case in cases if case.get("checks", {}).get("no_status_report_leakage") is False)
                    / len(cases)
                )
                * 100
            ),
            "status_leakage_pass_rate_percent": round(
                100
                - (
                    (
                        sum(1 for case in cases if case.get("checks", {}).get("no_status_report_leakage") is False)
                        / len(cases)
                    )
                    * 100
                )
            ),
            "status_leakage_checked_cases": len(cases),
        },
'@
                    new_text = @'
        "summary": {
            "case_count": len(cases),
            "passed": passed,
            "failed": len(cases) - passed,
            "pass_rate_percent": round((passed / len(cases)) * 100),
            "status_leakage_failures": sum(
                1 for case in cases if case.get("checks", {}).get("no_status_report_leakage") is False
            ),
            "status_leakage_failure_rate_percent": round(
                (
                    sum(1 for case in cases if case.get("checks", {}).get("no_status_report_leakage") is False)
                    / len(cases)
                )
                * 100
            ),
            "status_leakage_pass_rate_percent": round(
                100
                - (
                    (
                        sum(1 for case in cases if case.get("checks", {}).get("no_status_report_leakage") is False)
                        / len(cases)
                    )
                    * 100
                )
            ),
            "status_leakage_checked_cases": len(cases),
            "packet_scan_regression_marker": False,
        },
'@
                    validation_command = 'python -m py_compile scripts\run_mim_durability_smoke_v2.py'
                    validation_pattern = 'status_leakage_failures'
                    closure_evidence = 'selector skipped malformed latest packet and selected older actionable packet'
                    prevention_lesson = 'Packet selection must reject malformed newest packets and continue scanning for current-code candidates.'
                    dave_needed = 'no'
                }
            }
            $badPayload | ConvertTo-Json -Depth 12 | Set-Content -Path $badPath -Encoding UTF8
            $goodPayload | ConvertTo-Json -Depth 12 | Set-Content -Path $goodPath -Encoding UTF8
            (Get-Item -Path $badPath).LastWriteTime = (Get-Date).AddMinutes(10)
            (Get-Item -Path $goodPath).LastWriteTime = (Get-Date).AddMinutes(9)

            $state = New-SelectionState -Objectives @(
                (New-SelectionObjective -Id 'OBJ-1' -Priority 'high')
            ) -Tasks @(
                (New-SelectionTask -Id 'TSK-1' -ObjectiveId 'OBJ-1' -Status 'completed' -Title 'Completed source task')
            )
            $terminalOutcome = [pscustomobject]@{
                classification = 'completed_with_evidence'
                task_id = 'TSK-1'
                objective_id = 'OBJ-1'
                summary = 'Previous independent TOD resolution training step completed with evidence.'
            }

            $plan = New-TodNextTaskSelectionPlan -State $state -TerminalOutcome $terminalOutcome -TriggerReason 'Dave-away independent TOD resolution movement'

            [string]$plan.selection_kind | Should Be 'packet_candidate_code_task'
            [string]$plan.create_task.scope | Should Match 'TOD_PACKET_FORMATION_TEST_OLDER_ACTIONABLE.latest.json'
            @(@($plan.rejected_candidates) | Where-Object {
                [string]$_.task_id -eq 'packet_candidate:TOD_PACKET_FORMATION_TEST_LATEST_MALFORMED.latest.json' -and
                [string]$_.reason -eq 'packet_candidate_missing_actionable_fields'
            }).Count | Should Be 1
        }
        finally {
            if ([string]::IsNullOrWhiteSpace($originalBad)) {
                if (Test-Path -Path $badPath) { Remove-Item -Path $badPath -Force }
            }
            else {
                [System.IO.File]::WriteAllText($badPath, $originalBad, (New-Object System.Text.UTF8Encoding($false)))
            }
            if ([string]::IsNullOrWhiteSpace($originalGood)) {
                if (Test-Path -Path $goodPath) { Remove-Item -Path $goodPath -Force }
            }
            else {
                [System.IO.File]::WriteAllText($goodPath, $originalGood, (New-Object System.Text.UTF8Encoding($false)))
            }
            if ([string]::IsNullOrWhiteSpace($originalTargetContent)) {
                if (Test-Path -Path $targetPath) { Remove-Item -Path $targetPath -Force }
            }
            else {
                Set-TodSelectionTestFileText -Path $targetPath -Content $originalTargetContent
            }
        }
    }

    It 'discovers Studio bounded packet artifacts as actionable independent-resolution packets' {
        $relativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_STUDIO_MODE_SELECTION_BOUNDED_PACKET.latest.json'
        $packetPath = Join-Path $repoRoot ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $originalContent = if (Test-Path -Path $packetPath) { Get-Content -Path $packetPath -Raw } else { $null }
        $studioPath = Join-Path $repoRoot 'tmp_remote_mim/core/routers/studio.py'
        $originalStudioContent = if (Test-Path -Path $studioPath) { Get-Content -Path $studioPath -Raw } else { $null }
        try {
            $currentStudioText = 'I recommend working on TOD self-authored bounded edit materialization next.'
            $nextStudioText = 'I recommend working on TOD packet-discovery verification next.'
            if (-not [string]::IsNullOrWhiteSpace($originalStudioContent)) {
                $seededStudioContent = [string]$originalStudioContent
                if (-not $seededStudioContent.Contains($currentStudioText)) {
                    $seededStudioContent = $seededStudioContent.Replace(
                        'I recommend working on TOD current-code packet materialization next.',
                        $currentStudioText
                    )
                    if (-not $seededStudioContent.Contains($currentStudioText)) {
                        $seededStudioContent = $seededStudioContent + "`n" + $currentStudioText + "`n"
                    }
                    [System.IO.File]::WriteAllText($studioPath, $seededStudioContent, (New-Object System.Text.UTF8Encoding($false)))
                }
            }
            $packetPayload = [ordered]@{
                artifact_type = 'tod_packet_formation_artifact'
                status = 'packet_candidate_ready'
                packet_candidate_ready = $true
                packet = [ordered]@{
                    selected_candidate = 'studio_recommendation_prioritizes_tod_materialization'
                    target_file = 'tmp_remote_mim/core/routers/studio.py'
                    intended_edit_mode = 'replace_text'
                    old_text = $currentStudioText
                    new_text = $nextStudioText
                    validation_command = 'python -m unittest tmp_remote_mim.tests.test_studio_training_chat'
                    validation_pattern = 'TOD packet-discovery verification'
                    closure_evidence = 'Studio recommendation branch changed and focused tests passed.'
                    prevention_lesson = 'Studio packet artifacts must be discoverable by the selector, not just written as isolated evidence.'
                    dave_needed = 'no'
                }
            }
            $packetPayload | ConvertTo-Json -Depth 12 | Set-Content -Path $packetPath -Encoding UTF8
            (Get-Item -Path $packetPath).LastWriteTime = (Get-Date).AddMinutes(6)

            $records = @(Get-TodIndependentResolutionPackets -RepoRoot $repoRoot)
            (@($records | Where-Object { [string]$_.name -eq 'TOD_STUDIO_MODE_SELECTION_BOUNDED_PACKET.latest.json' }).Count -gt 0) | Should Be $true

            $state = New-SelectionState -Objectives @(
                (New-SelectionObjective -Id 'OBJ-1' -Priority 'high')
            ) -Tasks @(
                (New-SelectionTask -Id 'TSK-1' -ObjectiveId 'OBJ-1' -Status 'completed' -Title 'Completed source task')
            )
            $terminalOutcome = [pscustomobject]@{
                classification = 'completed_with_evidence'
                task_id = 'TSK-1'
                objective_id = 'OBJ-1'
                summary = 'Previous independent TOD resolution training step completed with evidence.'
            }

            $plan = New-TodNextTaskSelectionPlan -State $state -TerminalOutcome $terminalOutcome -TriggerReason 'Dave-away independent TOD resolution movement'

            [string]$plan.selection_kind | Should Be 'packet_candidate_code_task'
            [string]$plan.dispatch_status | Should Be 'not_started'
            [string]$plan.create_task.scope | Should Match 'Target File: tmp_remote_mim/core/routers/studio.py'
            [string]$plan.create_task.scope | Should Match 'TOD packet-discovery verification'
        }
        finally {
            if ([string]::IsNullOrWhiteSpace($originalContent)) {
                if (Test-Path -Path $packetPath) { Remove-Item -Path $packetPath -Force }
            }
            else {
                [System.IO.File]::WriteAllText($packetPath, $originalContent, (New-Object System.Text.UTF8Encoding($false)))
            }
            if ($null -ne $originalStudioContent) {
                [System.IO.File]::WriteAllText($studioPath, $originalStudioContent, (New-Object System.Text.UTF8Encoding($false)))
            }
        }
    }

    It 'consumes a ready discovery-target packet before creating another discovery packet formation task' {
        Invoke-WithIsolatedPacketRepoRoot {
            $packetPath = Join-Path $global:repoRoot 'runtime_remote_training/tod_independent_resolution_attempts/TOD_PACKET_FORMATION_INDEPENDENT_RECOVERY.latest.json'
            $discoveryPath = Join-Path $global:repoRoot 'runtime_remote_training/tod_independent_resolution_attempts/TOD_DIFFERENT_TARGET_DISCOVERY_DRILL.latest.json'
            $targetPath = Join-Path $global:repoRoot 'tmp_remote_mim/core/routers/public_chat.py'
            New-Item -Path (Split-Path -Parent $targetPath) -ItemType Directory -Force | Out-Null
            $oldText = @'
        if any(token in recent_text for token in ("day", "date", "today", "time", "thursday", "friday", "saturday")):
            return (
                f"This could mean several things, but if you mean the day/date from the prior question, in France it is {temporal['current_date']} at about {temporal['current_time']} {temporal['timezone']}. "
                "The evidence is the prior turn plus the France timezone source. If you meant laws, travel, pricing, or something else about France, that is a different path. Next action: I will use the prior-turn date context unless you choose another France topic."
            )
'@
            $oldText | Set-Content -Path $targetPath -Encoding UTF8

            $discoveryPayload = [ordered]@{
                artifact_type = 'tod_different_target_discovery'
                status = 'candidate_selected'
                selected_candidate_or_none = [ordered]@{
                    candidate_key = 'public_chat_context_followup_direct_answer_guard'
                    target_file = 'tmp_remote_mim/core/routers/public_chat.py'
                    validation_command = 'python -m py_compile tmp_remote_mim/core/routers/public_chat.py'
                }
            }
            $discoveryPayload | ConvertTo-Json -Depth 12 | Set-Content -Path $discoveryPath -Encoding UTF8

            $packetPayload = [ordered]@{
                artifact_type = 'tod_packet_formation_artifact'
                status = 'packet_candidate_ready'
                packet_candidate_ready = $true
                packet = [ordered]@{
                    selected_candidate = 'public_chat_france_followup_prior_context_direct_answer'
                    target_file = 'tmp_remote_mim/core/routers/public_chat.py'
                    intended_edit_mode = 'replace_text'
                    old_text = $oldText
                    new_text = @'
        if any(token in recent_text for token in ("day", "date", "today", "time", "thursday", "friday", "saturday")):
            return (
                f"In France, it is {temporal['current_date']} at about {temporal['current_time']} {temporal['timezone']}. "
                "I am carrying forward the prior date/time question instead of asking you to restate it. If you meant laws, travel, pricing, or another France topic, say that topic and I will switch."
            )
'@
                    validation_command = 'python -m py_compile tmp_remote_mim/core/routers/public_chat.py'
                    validation_pattern = 'I am carrying forward the prior date/time question'
                    closure_evidence = 'Public chat France follow-up branch changed and py_compile passed.'
                    prevention_lesson = 'Ready discovery packets must be consumed before packet formation is repeated.'
                    dave_needed = 'no'
                }
            }
            $packetPayload | ConvertTo-Json -Depth 12 | Set-Content -Path $packetPath -Encoding UTF8

            $sourceTask = New-SelectionTask -Id 'TSK-PACKET-SOURCE' -ObjectiveId 'OBJ-1' -Status 'completed' -Title 'Form current-code packet from different-target discovery'
            $sourceTask.task_category = 'packet_formation'
            $sourceTask.scope = 'Target File: runtime_remote_training/tod_independent_resolution_attempts/TOD_PACKET_FORMATION_INDEPENDENT_RECOVERY.latest.json'
            $stalePacketTask = New-SelectionTask -Id 'TSK-STALE-PACKET-TASK' -ObjectiveId 'OBJ-1' -Status 'planned' -Title 'Form current-code packet from different-target discovery'
            $stalePacketTask.task_category = 'packet_formation'
            $stalePacketTask.scope = 'Target File: runtime_remote_training/tod_independent_resolution_attempts/TOD_PACKET_FORMATION_INDEPENDENT_RECOVERY.latest.json'
            $state = New-SelectionState -Objectives @(
                (New-SelectionObjective -Id 'OBJ-1' -Priority 'high')
            ) -Tasks @(
                $sourceTask,
                $stalePacketTask
            )
            $terminalOutcome = [pscustomobject]@{
                classification = 'completed_with_evidence'
                task_id = 'TSK-PACKET-SOURCE'
                objective_id = 'OBJ-1'
                summary = 'Packet candidate ready with complete structured fields.'
            }

            $plan = New-TodNextTaskSelectionPlan -State $state -TerminalOutcome $terminalOutcome -TriggerReason 'Dave-away independent TOD resolution movement from discovery-selected public_chat candidate'

            [string]$plan.selection_kind | Should Be 'packet_candidate_code_task'
            [string]$plan.dispatch_status | Should Be 'not_started'
            [string]$plan.reason_selected | Should Match 'actionable current-code packet'
            [string]$plan.create_task.task_category | Should Be 'code_change'
            [string]$plan.create_task.scope | Should Match 'Target File: tmp_remote_mim/core/routers/public_chat.py'
            [string]$plan.create_task.scope | Should Match 'I am carrying forward the prior date/time question'
            (@($plan.expected_evidence) -join ' ') | Should Match 'packet_materialized_current_code_task'
            (@($plan.expected_evidence) -join ' ') | Should Match 'different_target_discovery_packet_already_ready'
            @(@($plan.rejected_candidates) | Where-Object {
                [string]$_.task_id -eq 'TSK-STALE-PACKET-TASK' -and
                [string]$_.reason -eq 'packet_formation_rejected_ready_packet_exists'
            }).Count | Should Be 1
        }
    }

    It 'blocks older packet candidates when current blocker requires Studio old/new synthesis' {
        Invoke-WithIsolatedPacketRepoRoot {
            $targetPath = Join-Path $global:repoRoot 'tmp_remote_mim/core/routers/gateway.py'
            New-Item -Path (Split-Path -Parent $targetPath) -ItemType Directory -Force | Out-Null
            @'
def route_gateway():
    expected_evidence = [
        "fresh changed_files for the target gateway/test files or blocked_with_inspection",
        "focused validation command output",
    ]
'@ | Set-Content -Path $targetPath -Encoding UTF8

            $packetPath = Join-Path $global:repoRoot 'runtime_remote_training/tod_independent_resolution_attempts/TOD_PACKET_FORMATION_GATEWAY_SPLIT_TEST.latest.json'
            $packetPayload = [ordered]@{
                artifact_type = 'tod_packet_formation_artifact'
                generated_at = (Get-Date).ToUniversalTime().ToString('o')
                status = 'packet_candidate_ready'
                packet_candidate_ready = $true
                packet = [ordered]@{
                    target_file = 'tmp_remote_mim/core/routers/gateway.py'
                    intended_edit_mode = 'replace_text'
                    old_text = @'
    expected_evidence = [
        "fresh changed_files for the target gateway/test files or blocked_with_inspection",
        "focused validation command output",
    ]
'@
                    new_text = @'
    expected_evidence = [
        "fresh changed_files for the selected one-file target or blocked_with_inspection naming target_file_exactly_one",
        "focused validation command output",
    ]
'@
                    validation_command = 'python -m py_compile tmp_remote_mim/core/routers/gateway.py'
                    validation_pattern = 'selected one-file target'
                    closure_evidence = 'gateway packet is valid but not the current Studio blocker target'
                    prevention_lesson = 'Current blocker packets must match the blocker target before dispatch.'
                    dave_needed = 'no'
                }
            }
            $packetPayload | ConvertTo-Json -Depth 12 | Set-Content -Path $packetPath -Encoding UTF8

            $state = New-SelectionState -Objectives @(
                (New-SelectionObjective -Id 'TOD-INDEPENDENT-RESOLUTION-STUDIO-MODE-SELECTION-20260616' -Priority 'high')
            ) -Tasks @(
                (New-SelectionTask -Id 'TOD-STUDIO-MODE-BOUNDED-PACKET-20260616T0625Z' -ObjectiveId 'TOD-INDEPENDENT-RESOLUTION-STUDIO-MODE-SELECTION-20260616' -Status 'completed' -Title 'TOD packet formation: Studio mode-selection bounded edit')
            )
            $terminalOutcome = [pscustomobject]@{
                classification = 'completed_with_evidence'
                task_id = 'TOD-STUDIO-MODE-BOUNDED-PACKET-20260616T0625Z'
                objective_id = 'TOD-INDEPENDENT-RESOLUTION-STUDIO-MODE-SELECTION-20260616'
                summary = 'Current blocker status=blocked_requires_tod_synthesized_old_new; target=tmp_remote_mim/core/routers/studio.py; TOD must read the current _studio_conversation_mode_reply text and publish exact old_text/new_text.'
            }

            $plan = New-TodNextTaskSelectionPlan -State $state -TerminalOutcome $terminalOutcome -TriggerReason 'post_timeout_packet_blocker_requires_tod_synthesized_old_new; choose a TOD-owned current-code bounded edit candidate; no Codex patch supplied'

            [string]$plan.selection_kind | Should Be 'blocked_current_blocker_packet_target_required'
            [string]$plan.dispatch_status | Should Be 'blocked_with_reason'
            [string]$plan.selected_task_id | Should Be ''
            [string]$plan.reason_selected | Should Match 'tmp_remote_mim/core/routers/studio.py'
            $plan.blocker | Should Not BeNullOrEmpty
            [string]$plan.blocker.missing_anchor_or_field | Should Match 'old_text/new_text'
            @($plan.blocker.inspected_files) -contains 'tmp_remote_mim/core/routers/studio.py' | Should Be $true
            @(@($plan.rejected_candidates) | Where-Object {
                [string]$_.task_id -eq 'packet_candidate:TOD_PACKET_FORMATION_GATEWAY_SPLIT_TEST.latest.json' -and
                [string]$_.reason -eq 'packet_candidate_not_current_blocker_target'
            }).Count | Should Be 1
            (@($plan.validation_plan) -join ' ') | Should Match 'Studio old_text/new_text'
        }
    }

    It 'blocks meaningful autonomy requests instead of creating validation-only maintenance filler' {
        $state = New-SelectionState -Objectives @(
            (New-SelectionObjective -Id 'OBJ-1' -Priority 'high')
        ) -Tasks @(
            (New-SelectionTask -Id 'TSK-1' -ObjectiveId 'OBJ-1' -Status 'completed' -Title 'Completed source task')
        )
        $terminalOutcome = [pscustomobject]@{
            classification = 'completed_with_evidence'
            task_id = 'TSK-1'
            objective_id = 'OBJ-1'
            summary = 'Previous training step completed with evidence.'
        }

        $plan = New-TodNextTaskSelectionPlan -State $state -TerminalOutcome $terminalOutcome -TriggerReason 'Dave-away meaningful TOD implementation movement'

        [string]$plan.selection_kind | Should Be 'blocked_no_behavior_changing_autonomy_candidate'
        [string]$plan.dispatch_status | Should Be 'blocked_with_reason'
        $plan.create_task | Should BeNullOrEmpty
        (@($plan.expected_evidence) -join ' ') | Should Match 'behavior_changing_candidate_required'
        (@($plan.validation_plan) -join ' ') | Should Match 'non-validation edit mode'
    }

    It 'treats plural Independent TOD Resolutions metric language as independent-resolution pressure' {
        Invoke-WithIsolatedPacketRepoRoot {
            $state = New-SelectionState -Objectives @(
                (New-SelectionObjective -Id 'OBJ-1' -Priority 'high')
            ) -Tasks @(
                (New-SelectionTask -Id 'TSK-1' -ObjectiveId 'OBJ-1' -Status 'completed' -Title 'Completed source task')
            )
            $terminalOutcome = [pscustomobject]@{
                classification = 'completed_with_evidence'
                task_id = 'TSK-1'
                objective_id = 'OBJ-1'
                summary = 'Previous independent TOD resolution training step completed with evidence.'
            }

            $plan = New-TodNextTaskSelectionPlan -State $state -TerminalOutcome $terminalOutcome -TriggerReason 'Move Independent TOD Resolutions from 3 toward 5'

            [string]$plan.selection_kind | Should Be 'independent_resolution_packet_formation_recovery_new'
            [string]$plan.dispatch_status | Should Be 'not_started'
            $plan.create_task | Should Not BeNullOrEmpty
            [string]$plan.create_task.task_category | Should Be 'packet_formation'
            [string]$plan.create_task.scope | Should Match 'Validation Pattern: packet_candidate_ready'
            (@($plan.expected_evidence) -join ' ') | Should Match 'tod_selected_behavior_changing_task'
            (@($plan.validation_plan) -join ' ') | Should Match 'current-code packet'
        }
    }

    It 'rejects vague backlog candidates and blocks when synthesis is not applicable' {
        Invoke-WithIsolatedPacketRepoRoot {
            $sourceTask = New-SelectionTask -Id 'TSK-1' -ObjectiveId 'OBJ-1' -Status 'completed' -Title 'Completed source task'
            $malformedBacklog = New-SelectionTask -Id 'TSK-BAD-BACKLOG' -ObjectiveId 'OBJ-2' -Status 'planned' -Title 'Vague backlog implementation'
            $malformedBacklog.scope = 'Improve TOD autonomy with a useful implementation. No bounded target is declared.'
            $state = New-SelectionState -Objectives @(
                (New-SelectionObjective -Id 'OBJ-1' -Priority 'high'),
                (New-SelectionObjective -Id 'OBJ-2' -Priority 'critical')
            ) -Tasks @(
                $sourceTask,
                $malformedBacklog
            )
            $terminalOutcome = [pscustomobject]@{
                classification = 'completed_with_evidence'
                task_id = 'TSK-1'
                objective_id = 'OBJ-1'
                summary = 'Previous independent TOD resolution training step completed with evidence.'
            }

            $plan = New-TodNextTaskSelectionPlan -State $state -TerminalOutcome $terminalOutcome -TriggerReason 'Dave-away independent TOD resolution movement'

            [string]$plan.selection_kind | Should Be 'independent_resolution_packet_formation_recovery_new'
            [string]$plan.dispatch_status | Should Be 'not_started'
            [string]$plan.selected_task_id | Should Be ''
            $plan.create_task | Should Not BeNullOrEmpty
            [string]$plan.create_task.task_category | Should Be 'packet_formation'
            @(@($plan.rejected_candidates) | Where-Object {
                [string]$_.task_id -eq 'synthesized_independent_resolution_candidate:studio_training_explanation_mode' -and
                [string]$_.reason -eq 'synthesized_candidate_not_materialized_as_behavior_changing_edit'
            }).Count | Should Be 1
            (@($plan.validation_plan) -join ' ') | Should Match 'current-code packet'
        }
        $precedenceTask = New-SelectionTask -Id 'TSK-TARGET-PRECEDENCE' -ObjectiveId 'OBJ-1' -Status 'planned' -Title 'Target file precedence regression'
        $precedenceTask.scope = @(
            'Target File: scripts/TOD.ps1',
            'Edit Mode: replace_text',
            'Old Text:',
            '    $list = New-Object System.Collections.Generic.List[string]',
            'New Text:',
            '    $list = New-Object System.Collections.Generic.List[string]',
            '    $list.Add(''kept'') | Out-Null',
            'Validation Pattern: $list.Add(''kept'') | Out-Null'
        ) -join "`n"
        $precedenceMaterialization = Resolve-TaskBoundedEditMaterialization -Task $precedenceTask

        [string]$precedenceMaterialization.status | Should Be 'materialized'
        @($precedenceMaterialization.target_files).Count | Should Be 1
        [string]$precedenceMaterialization.target_files[0] | Should Be 'scripts/TOD.ps1'
        [string]$precedenceMaterialization.edit_mode | Should Be 'replace_text'
    }

    It 'blocks partially materialized backlog candidates with multiple target files under independent-resolution pressure' {
        Invoke-WithIsolatedPacketRepoRoot {
            $sourceTask = New-SelectionTask -Id 'TSK-1' -ObjectiveId 'OBJ-1' -Status 'completed' -Title 'Completed source task'
            $partialBacklog = New-SelectionTask -Id 'TSK-PARTIAL-BACKLOG' -ObjectiveId 'OBJ-2' -Status 'planned' -Title 'Ambiguous two-file implementation'
            $partialBacklog.task_category = 'code_change'
            $partialBacklog.scope = @'
Update the gateway handoff behavior in core/routers/gateway.py and add validation in tests/integration/test_mim_tod_handoff_gateway.py.
Required behavior: make the handoff safer with a behavior-changing implementation.
Validation Command: python -m py_compile tmp_remote_mim/core/routers/gateway.py
'@
            $state = New-SelectionState -Objectives @(
                (New-SelectionObjective -Id 'OBJ-1' -Priority 'high'),
                (New-SelectionObjective -Id 'OBJ-2' -Priority 'critical')
            ) -Tasks @(
                $sourceTask,
                $partialBacklog
            )
            $terminalOutcome = [pscustomobject]@{
                classification = 'completed_with_evidence'
                task_id = 'TSK-1'
                objective_id = 'OBJ-1'
                summary = 'Previous independent TOD resolution training step completed with evidence.'
            }

            $plan = New-TodNextTaskSelectionPlan -State $state -TerminalOutcome $terminalOutcome -TriggerReason 'Independent TOD Resolutions movement'

            [string]$plan.selection_kind | Should Be 'independent_resolution_packet_formation_recovery_new'
            [string]$plan.dispatch_status | Should Be 'not_started'
            [string]$plan.selected_task_id | Should Be ''
            $plan.create_task | Should Not BeNullOrEmpty
            [string]$plan.create_task.task_category | Should Be 'packet_formation'
            [string]$plan.create_task.scope | Should Match 'exact old_text from current code'
        }
    }

    It 'rehydrates a missing selected task only from a matching active task artifact' {
        $originalRepoRoot = $global:repoRoot
        $originalScriptRepoRoot = $script:repoRoot
        $tempRepoRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('tod-active-task-rehydrate-' + [guid]::NewGuid().ToString('N'))
        try {
            $global:repoRoot = $tempRepoRoot
            $script:repoRoot = $tempRepoRoot
            $sharedRoot = Join-Path $tempRepoRoot 'runtime/shared'
            New-Item -Path $sharedRoot -ItemType Directory -Force | Out-Null
            [pscustomobject]@{
                task_id = 'TSK-RECOVER'
                objective_id = 'OBJ-RECOVER'
                title = 'Recovered packet task'
                task_focus = 'Target File: runtime_remote_training/tod_independent_resolution_attempts/TOD_PACKET_FORMATION_INDEPENDENT_RECOVERY.latest.json'
                next_validation = 'packet_candidate_ready'
                execution_evidence = [pscustomobject]@{
                    selection_kind = 'recovery_contract_packet_formation'
                }
            } | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $sharedRoot 'TOD_ACTIVE_TASK.latest.json') -Encoding UTF8

            $state = New-SelectionState -Objectives @(
                (New-SelectionObjective -Id 'OBJ-RECOVER' -Priority 'high')
            )

            $wrongTask = Repair-TodMissingTaskFromActiveTaskArtifact -State $state -TaskId 'TSK-OTHER'
            $wrongTask | Should BeNullOrEmpty
            @($state.tasks).Count | Should Be 0

            $recoveredTask = Repair-TodMissingTaskFromActiveTaskArtifact -State $state -TaskId 'TSK-RECOVER'

            $recoveredTask | Should Not BeNullOrEmpty
            [string]$recoveredTask.id | Should Be 'TSK-RECOVER'
            [string]$recoveredTask.objective_id | Should Be 'OBJ-RECOVER'
            [string]$recoveredTask.status | Should Be 'packaged'
            [string]$recoveredTask.source | Should Be 'recovered_from_active_task_artifact'
            [string]$recoveredTask.selection_kind | Should Be 'recovery_contract_packet_formation'
            @($state.tasks).Count | Should Be 1
        }
        finally {
            $global:repoRoot = $originalRepoRoot
            $script:repoRoot = $originalScriptRepoRoot
            if (Test-Path -Path $tempRepoRoot) {
                Remove-Item -Path $tempRepoRoot -Recurse -Force
            }
        }
    }
}
