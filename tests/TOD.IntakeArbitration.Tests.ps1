Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$todScript = Join-Path $repoRoot 'scripts/TOD.ps1'
$intakeArtifactRelativePaths = @(
    'runtime/shared/TOD_ACTIVE_EXECUTION_LANE.latest.json',
    'runtime/shared/TOD_INTAKE_QUEUE.latest.json',
    'runtime/shared/TOD_INTAKE_ARBITRATION.latest.json',
    'runtime/shared/MIM_TOD_TASK_REQUEST.latest.json',
    'tmp_remote_mim/runtime/shared/TOD_ACTIVE_EXECUTION_LANE.latest.json',
    'tmp_remote_mim/runtime/shared/TOD_INTAKE_QUEUE.latest.json',
    'tmp_remote_mim/runtime/shared/TOD_INTAKE_ARBITRATION.latest.json',
    'tmp_remote_mim/runtime/shared/MIM_TOD_TASK_REQUEST.latest.json',
    'tod/out/context-sync/listener/MIM_TOD_TASK_REQUEST.latest.json'
)

function Write-JsonNoBom {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)]$Payload
    )

    $parent = Split-Path -Parent $PathValue
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $json = $Payload | ConvertTo-Json -Depth 20
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($PathValue, $json, $utf8NoBom)
}

function Backup-IntakeSharedArtifacts {
    $backups = @()
    foreach ($relativePath in @($intakeArtifactRelativePaths)) {
        $pathValue = Join-Path $repoRoot $relativePath
        $backups += [pscustomobject]@{
            path = $pathValue
            exists = (Test-Path -Path $pathValue -PathType Leaf)
            content = if (Test-Path -Path $pathValue -PathType Leaf) { [string](Get-Content -Path $pathValue -Raw) } else { '' }
        }
    }
    return @($backups)
}

function Restore-IntakeSharedArtifacts {
    param([Parameter(Mandatory = $true)]$Backups)

    foreach ($backup in @($Backups)) {
        if ([bool]$backup.exists) {
            $parent = Split-Path -Parent ([string]$backup.path)
            if (-not (Test-Path -Path $parent)) {
                New-Item -ItemType Directory -Path $parent -Force | Out-Null
            }

            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText([string]$backup.path, [string]$backup.content, $utf8NoBom)
        }
        elseif (Test-Path -Path ([string]$backup.path)) {
            Remove-Item -Path ([string]$backup.path) -Force
        }
    }
}

function New-IntakeStateFixture {
    $root = Join-Path $repoRoot ('tod/out/tests/intake-arbitration-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    $statePath = Join-Path $root 'state.json'
    $configPath = Join-Path $repoRoot 'tod/config/tod-config.json'

    Write-JsonNoBom -PathValue $statePath -Payload ([pscustomobject]@{
        objectives = @()
        tasks = @()
        execution_results = @()
        review_decisions = @()
        journal = @()
        engine_performance = [pscustomobject]@{ records = @(); updated_at = '' }
        routing_decisions = [pscustomobject]@{ records = @(); updated_at = '' }
        routing_feedback = [pscustomobject]@{ learned_weights = [pscustomobject]@{}; sample_size = 0; version = 'feedback_v1'; updated_at = '' }
        sync_state = [pscustomobject]@{ expected_contract_version = ''; expected_schema_version = ''; local_repo_signature = ''; cached_manifest = $null; last_comparison = $null; last_sync_decision = ''; last_sync_code = ''; compared_at = '' }
    })

    return [pscustomobject]@{
        Root = $root
        StatePath = $statePath
        ConfigPath = $configPath
    }
}

function Set-ActiveIntakeLane {
    param(
        [Parameter(Mandatory = $true)]$Fixture,
        [Parameter(Mandatory = $true)][string]$TaskId,
        [Parameter(Mandatory = $true)][string]$ObjectiveId,
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Priority,
        [string]$LaneStatus = 'active',
        [string]$TaskStatus = 'in_progress'
    )

    $state = Get-Content -Path $Fixture.StatePath -Raw | ConvertFrom-Json
    $state.objectives += [pscustomobject]@{
        id = $ObjectiveId
        title = $ObjectiveId
        description = $ObjectiveId
        priority = 'high'
        constraints = @()
        success_criteria = @()
        status = $TaskStatus
        created_at = (Get-Date).ToUniversalTime().ToString('o')
        updated_at = (Get-Date).ToUniversalTime().ToString('o')
    }
    $state.tasks += [pscustomobject]@{
        id = $TaskId
        objective_id = $ObjectiveId
        title = $TaskId
        type = 'implementation'
        task_category = 'chat_execution'
        scope = 'active intake fixture task'
        dependencies = @()
        acceptance_criteria = @('preserve active lane')
        status = 'in_progress'
        assigned_executor = 'local'
        created_at = (Get-Date).ToUniversalTime().ToString('o')
        updated_at = (Get-Date).ToUniversalTime().ToString('o')
    }
    Write-JsonNoBom -PathValue $Fixture.StatePath -Payload $state

    $lane = [pscustomobject]@{
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        packet_type = 'tod-active-execution-lane-v1'
        request_id = ('REQ-' + $TaskId)
        task_id = $TaskId
        objective_id = $ObjectiveId
        source = $Source
        priority = $Priority
        status = $LaneStatus
        started_at = (Get-Date).ToUniversalTime().ToString('o')
        relation_to_previous_active = 'new'
        previous_active_task_id = ''
    }

    foreach ($root in @('runtime/shared', 'tmp_remote_mim/runtime/shared')) {
        $rootPath = Join-Path $repoRoot $root
        Write-JsonNoBom -PathValue (Join-Path $rootPath 'TOD_ACTIVE_EXECUTION_LANE.latest.json') -Payload $lane
        Write-JsonNoBom -PathValue (Join-Path $rootPath 'TOD_INTAKE_QUEUE.latest.json') -Payload ([pscustomobject]@{
            generated_at = (Get-Date).ToUniversalTime().ToString('o')
            packet_type = 'tod-intake-queue-v1'
            active_task_id = $TaskId
            count = 0
            queued_count = 0
            next_task_after_current = $null
            items = @()
        })
        Write-JsonNoBom -PathValue (Join-Path $rootPath 'TOD_INTAKE_ARBITRATION.latest.json') -Payload ([pscustomobject]@{
            generated_at = (Get-Date).ToUniversalTime().ToString('o')
            packet_type = 'tod-intake-arbitration-v1'
            decision = ''
            reason = ''
            relation_to_active_task = ''
            incoming = $null
            active_lane = $lane
            priority_order = @()
            queue_path = ''
        })
    }
}

function Set-IntakeQueueItems {
    param(
        [Parameter(Mandatory = $true)][string]$ActiveTaskId,
        [object[]]$Items = @()
    )

    $queuedItems = @($Items | Where-Object { [string]$_.status -eq 'queued' })
    $nextTask = @($queuedItems | Sort-Object -Property @{ Expression = {
                switch ([string]$_.priority) {
                    'emergency_stop' { 700 }
                    'operator_cancel' { 700 }
                    'operator_admin_repair' { 600 }
                    'operator_direct_objective' { 500 }
                    'active_task_continuation' { 400 }
                    'mim_request' { 300 }
                    'watchdog_recovery' { 200 }
                    'scheduled_maintenance' { 100 }
                    'informational_chat' { 10 }
                    default { 0 }
                }
            }; Descending = $true }, @{ Expression = { [string]$_.received_at }; Descending = $false } | Select-Object -First 1)
    $payload = [pscustomobject]@{
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        packet_type = 'tod-intake-queue-v1'
        active_task_id = $ActiveTaskId
        count = @($Items).Count
        queued_count = @($queuedItems).Count
        next_task_after_current = if (@($nextTask).Count -gt 0) { $nextTask[0] } else { $null }
        items = @($Items)
    }

    foreach ($root in @('runtime/shared', 'tmp_remote_mim/runtime/shared')) {
        Write-JsonNoBom -PathValue (Join-Path $repoRoot (Join-Path $root 'TOD_INTAKE_QUEUE.latest.json')) -Payload $payload
    }
}

function New-QueuedIntakeItem {
    param(
        [string]$RequestId,
        [string]$TaskId,
        [string]$ObjectiveId,
        [string]$Source = 'operator_chat',
        [string]$Priority = 'operator_direct_objective',
        [string]$Status = 'queued',
        [string]$ReceivedAt = '2026-05-07T00:00:00Z'
    )

    [pscustomobject]@{
        request_id = $RequestId
        task_id = $TaskId
        objective_id = $ObjectiveId
        source = $Source
        priority = $Priority
        interrupt_policy = 'no_interrupt'
        status = $Status
        received_at = $ReceivedAt
        expires_at = '2026-05-08T00:00:00Z'
        relation_to_active_task = 'conflicts'
        title = $TaskId
        summary = $TaskId
        task_category = 'chat_execution'
    }
}

Describe 'TOD intake queue arbitration' {
    BeforeEach {
        $script:IntakeSharedArtifactBackups = Backup-IntakeSharedArtifacts
    }

    AfterEach {
        if ($script:IntakeSharedArtifactBackups) {
            Restore-IntakeSharedArtifacts -Backups $script:IntakeSharedArtifactBackups
        }
    }

    It 'queues a MIM request while an operator task is active' {
        $fixture = New-IntakeStateFixture
        $oldBridgePath = $env:TOD_BRIDGE_REQUEST_PACKET_PATH
        try {
            Set-ActiveIntakeLane -Fixture $fixture -TaskId 'TSKCHAT-ACTIVE-OPERATOR' -ObjectiveId 'objective-active-operator' -Source 'operator_chat' -Priority 'operator_direct_objective'
            $bridgePath = Join-Path $repoRoot 'tod/out/context-sync/listener/MIM_TOD_TASK_REQUEST.latest.json'
            Write-JsonNoBom -PathValue $bridgePath -Payload ([pscustomobject]@{
                request_id = 'REQ-MIM-WHILE-OPERATOR'
                task_id = 'TSK-MIM-WHILE-OPERATOR'
                objective_id = 'objective-mim-queued'
                tod_action = 'safe_home'
                title = 'MIM queued request'
                summary = 'MIM request should wait behind operator task.'
            })
            $env:TOD_BRIDGE_REQUEST_PACKET_PATH = $bridgePath

            $result = (& $todScript -Action run-bridge-request -RequestId 'REQ-MIM-WHILE-OPERATOR' -ConfigPath $fixture.ConfigPath -StatePath $fixture.StatePath | Out-String | ConvertFrom-Json)

            [string]$result.decision | Should Be 'queue'
            [bool]$result.active_task_preserved | Should Be $true
            [string]$result.intake_arbitration.active_lane.task_id | Should Be 'TSKCHAT-ACTIVE-OPERATOR'
            [string]$result.intake_queue.next_task_after_current.source | Should Be 'mim_request'
        }
        finally {
            $env:TOD_BRIDGE_REQUEST_PACKET_PATH = $oldBridgePath
            if ($fixture -and (Test-Path -Path $fixture.Root)) {
                Remove-Item -Path $fixture.Root -Recurse -Force
            }
        }
    }

    It 'promotes operator admin repair over an active MIM lane' {
        $fixture = New-IntakeStateFixture
        try {
            Set-ActiveIntakeLane -Fixture $fixture -TaskId 'TSK-MIM-ACTIVE' -ObjectiveId 'objective-mim-active' -Source 'mim_request' -Priority 'mim_request'

            $result = (& $todScript -Action execute-chat-task -ConfigPath $fixture.ConfigPath -StatePath $fixture.StatePath -ObjectiveId 'objective-admin-repair' -TaskId 'TSKCHAT-ADMIN-REPAIR' -RequestId 'REQ-ADMIN-REPAIR' -CorrelationId 'CORR-ADMIN-REPAIR' -Title 'ADMIN ACTION: repair active lane' -Description 'ADMIN ACTION: repair active lane' -Scope 'ADMIN ACTION: repair active lane' -AcceptanceCriteria 'Admin repair may supersede MIM.' -SuccessCriteria 'Admin repair may supersede MIM.' -AssignedExecutor local -TaskCategory diagnostic_implementation_repair -TargetFile 'scripts/TOD.ps1' -ExecutionMode async | Out-String | ConvertFrom-Json)

            [string]$result.intake_arbitration.decision | Should Be 'supersede_active'
            [string]$result.intake_arbitration.active_lane.task_id | Should Be 'TSKCHAT-ADMIN-REPAIR'
            [string]$result.intake_arbitration.active_lane.previous_active_task_id | Should Be 'TSK-MIM-ACTIVE'
        }
        finally {
            if ($fixture -and (Test-Path -Path $fixture.Root)) {
                Remove-Item -Path $fixture.Root -Recurse -Force
            }
        }
    }

    It 'blocks diagnostic repair dispatch when no bounded target file is supplied' {
        $fixture = New-IntakeStateFixture
        try {
            Set-ActiveIntakeLane -Fixture $fixture -TaskId 'TSK-MIM-ACTIVE' -ObjectiveId 'objective-mim-active' -Source 'mim_request' -Priority 'mim_request'

            $result = (& $todScript -Action execute-chat-task -ConfigPath $fixture.ConfigPath -StatePath $fixture.StatePath -ObjectiveId 'objective-admin-repair' -TaskId 'TSKCHAT-ADMIN-REPAIR-NO-TARGET' -RequestId 'REQ-ADMIN-REPAIR-NO-TARGET' -CorrelationId 'CORR-ADMIN-REPAIR-NO-TARGET' -Title 'ADMIN ACTION: repair active lane' -Description 'ADMIN ACTION: repair active lane' -Scope 'ADMIN ACTION: repair active lane' -AcceptanceCriteria 'Admin repair must preserve a bounded target.' -SuccessCriteria 'Admin repair must preserve a bounded target.' -AssignedExecutor local -TaskCategory diagnostic_implementation_repair -ExecutionMode async | Out-String | ConvertFrom-Json)

            [string]$result.intake_arbitration.decision | Should Be 'blocked_needs_bounded_target'
            [string]$result.run_task.reason_code | Should Be 'diagnostic_repair_missing_bounded_target'
            [bool]$result.run_task.accepted | Should Be $false
            [string]$result.selected_task.task_id | Should Be ''
            $stateAfter = Get-Content -Raw $fixture.StatePath | ConvertFrom-Json
            $activeTask = @($stateAfter.tasks | Where-Object { [string]$_.id -eq 'TSK-MIM-ACTIVE' } | Select-Object -First 1)
            [string]$activeTask.status | Should Be 'in_progress'
        }
        finally {
            if ($fixture -and (Test-Path -Path $fixture.Root)) {
                Remove-Item -Path $fixture.Root -Recurse -Force
            }
        }
    }

    It 'blocks blocked-result closure diagnostics when no bounded target file is supplied' {
        $fixture = New-IntakeStateFixture
        try {
            Set-ActiveIntakeLane -Fixture $fixture -TaskId 'TSK-MIM-ACTIVE' -ObjectiveId 'objective-mim-active' -Source 'mim_request' -Priority 'mim_request'

            $result = (& $todScript -Action execute-chat-task -ConfigPath $fixture.ConfigPath -StatePath $fixture.StatePath -ObjectiveId 'objective-project-continuity' -TaskId 'TSKCHAT-BLOCKED-RESULT-CLOSURE-DIAGNOSTIC' -RequestId 'REQ-BLOCKED-RESULT-CLOSURE-DIAGNOSTIC' -CorrelationId 'CORR-BLOCKED-RESULT-CLOSURE-DIAGNOSTIC' -Title 'Blocked result closure diagnostic' -Description 'Resolve blocked task result.' -Scope 'source_selected_action_code=resolve_blocked_task_result. TOD published a blocked result; close or repair the lane.' -AcceptanceCriteria 'Closure diagnostic must not displace bounded implementation without target.' -SuccessCriteria 'Closure diagnostic must not displace bounded implementation without target.' -AssignedExecutor local -TaskCategory chat_execution -ExecutionMode async | Out-String | ConvertFrom-Json)

            [string]$result.intake_arbitration.decision | Should Be 'blocked_needs_bounded_target'
            [string]$result.run_task.reason_code | Should Be 'diagnostic_repair_missing_bounded_target'
            [bool]$result.run_task.accepted | Should Be $false
            [string]$result.selected_task.task_id | Should Be ''
            $stateAfter = Get-Content -Raw $fixture.StatePath | ConvertFrom-Json
            $activeTask = @($stateAfter.tasks | Where-Object { [string]$_.id -eq 'TSK-MIM-ACTIVE' } | Select-Object -First 1)
            [string]$activeTask.status | Should Be 'in_progress'
        }
        finally {
            if ($fixture -and (Test-Path -Path $fixture.Root)) {
                Remove-Item -Path $fixture.Root -Recurse -Force
            }
        }
    }

    It 'accepts read-only assessment without a target file while preserving malformed edit rejection' {
        $fixture = New-IntakeStateFixture
        try {
            foreach ($relativePath in @($intakeArtifactRelativePaths)) {
                $pathValue = Join-Path $repoRoot $relativePath
                if (Test-Path -Path $pathValue -PathType Leaf) {
                    Remove-Item -Path $pathValue -Force
                }
            }

            $readOnlyScope = @"
Task mode: read_only_assessment
Input: runtime_remote_training/MIM_TOD_REAL_MOVEMENT_SCORECARD.latest.json
Output artifact: runtime_remote_training/TOD_CAPABILITY_ASSESSMENT_V1.latest.json
Audit Subject: TOD-CAPABILITY-ASSESSMENT-V1
Use the read-only assessment artifact lane.
No source code modifications.
"@
            $readOnly = (& $todScript -Action execute-chat-task -ConfigPath $fixture.ConfigPath -StatePath $fixture.StatePath -ObjectiveId 'TOD-CAPABILITY-ASSESSMENT-V1' -TaskId 'TSK-TOD-CAPABILITY-ASSESSMENT-V1' -RequestId 'REQ-TOD-CAPABILITY-ASSESSMENT-V1' -CorrelationId 'CORR-TOD-CAPABILITY-ASSESSMENT-V1' -Title 'TOD capability assessment V1' -Description 'Read-only evidence-based TOD capability assessment.' -Scope $readOnlyScope -AcceptanceCriteria 'No target_file required; no source code modified.' -SuccessCriteria 'Assessment artifacts published.' -AssignedExecutor local -TaskCategory read_only_assessment -ExecutionMode async | Out-String | ConvertFrom-Json)

            [string]$readOnly.intake_arbitration.decision | Should Be 'run_now'
            [string]$readOnly.intake_arbitration.pre_active_lane_gate.reason_code | Should Be 'canonical_read_only_task_mode_valid'
            [bool]$readOnly.intake_arbitration.pre_active_lane_gate.canonical_contract.target_file_required | Should Be $false
            [bool]$readOnly.intake_arbitration.pre_active_lane_gate.canonical_contract.source_code_modification_allowed | Should Be $false
            [string]$readOnly.intake_arbitration.pre_active_lane_gate.canonical_contract.bounded_edit_mode | Should Be 'False'

            $malformed = (& $todScript -Action execute-chat-task -ConfigPath $fixture.ConfigPath -StatePath $fixture.StatePath -ObjectiveId 'objective-malformed-edit' -TaskId 'TSK-MALFORMED-EDIT' -RequestId 'REQ-MALFORMED-EDIT' -CorrelationId 'CORR-MALFORMED-EDIT' -Title 'Malformed implementation' -Description 'Implementation without target should not pass the active-lane gate.' -Scope 'Implement a behavior change but no target file is supplied.' -AcceptanceCriteria 'Must reject missing target file.' -SuccessCriteria 'Must reject missing target file.' -AssignedExecutor local -TaskCategory code_change -ExecutionMode async | Out-String | ConvertFrom-Json)

            [string]$malformed.intake_arbitration.decision | Should Be 'rejected_before_active_lane'
            [string]$malformed.intake_arbitration.pre_active_lane_gate.reason_code | Should Be 'malformed_bounded_edit_packet'
            @($malformed.intake_arbitration.pre_active_lane_gate.missing_fields) -contains 'target_file' | Should Be $true
        }
        finally {
            if ($fixture -and (Test-Path -Path $fixture.Root)) {
                Remove-Item -Path $fixture.Root -Recurse -Force
            }
        }
    }

    It 'requires validation-only work to include a validation command before active-lane promotion' {
        $fixture = New-IntakeStateFixture
        try {
            foreach ($relativePath in @($intakeArtifactRelativePaths)) {
                $pathValue = Join-Path $repoRoot $relativePath
                if (Test-Path -Path $pathValue -PathType Leaf) {
                    Remove-Item -Path $pathValue -Force
                }
            }

            $missingValidationCommandScope = @"
Task mode: validation
Edit Mode: validation_only
Validate the live TOD status truth projection.
"@
            $missingValidationCommand = (& $todScript -Action execute-chat-task -ConfigPath $fixture.ConfigPath -StatePath $fixture.StatePath -ObjectiveId 'TOD-VALIDATION-LANE-REJECTION-V1' -TaskId 'TSK-VALIDATION-MISSING-COMMAND' -RequestId 'REQ-VALIDATION-MISSING-COMMAND' -CorrelationId 'CORR-VALIDATION-MISSING-COMMAND' -Title 'Malformed validation-only task' -Description 'Validation-only work must name its validation command before promotion.' -Scope $missingValidationCommandScope -AcceptanceCriteria 'Must reject missing validation command.' -SuccessCriteria 'Must reject missing validation command.' -AssignedExecutor local -TaskCategory validation -ExecutionMode async | Out-String | ConvertFrom-Json)

            [string]$missingValidationCommand.intake_arbitration.decision | Should Be 'rejected_before_active_lane'
            [string]$missingValidationCommand.intake_arbitration.pre_active_lane_gate.reason_code | Should Be 'malformed_validation_packet'
            @($missingValidationCommand.intake_arbitration.pre_active_lane_gate.missing_fields) -contains 'validation_command' | Should Be $true

            $validValidationScope = @"
Task mode: validation
Edit Mode: validation_only
Validation Command: git status --short
Validate the live TOD status truth projection.
"@
            $validValidation = (& $todScript -Action execute-chat-task -ConfigPath $fixture.ConfigPath -StatePath $fixture.StatePath -ObjectiveId 'TOD-VALIDATION-LANE-REJECTION-V1' -TaskId 'TSK-VALIDATION-WITH-COMMAND' -RequestId 'REQ-VALIDATION-WITH-COMMAND' -CorrelationId 'CORR-VALIDATION-WITH-COMMAND' -Title 'Valid validation-only task' -Description 'Validation-only work with command should be allowed without a target file.' -Scope $validValidationScope -AcceptanceCriteria 'Validation command present.' -SuccessCriteria 'Validation command present.' -AssignedExecutor local -TaskCategory validation -ExecutionMode async | Out-String | ConvertFrom-Json)

            [string]$validValidation.intake_arbitration.decision | Should Be 'run_now'
            [string]$validValidation.intake_arbitration.pre_active_lane_gate.reason_code | Should Be 'canonical_validation_task_mode_valid'
            [bool]$validValidation.intake_arbitration.pre_active_lane_gate.canonical_contract.target_file_required | Should Be $false
            [string]$validValidation.intake_arbitration.pre_active_lane_gate.canonical_contract.validation_command | Should Be 'git status --short'

            $validPromptPath = Join-Path $repoRoot 'tod/out/prompts/TSK-VALIDATION-WITH-COMMAND.md'
            Test-Path -Path $validPromptPath -PathType Leaf | Should Be $true
            $validPromptText = Get-Content -Path $validPromptPath -Raw
            $validPromptText | Should Match '(?m)^Edit Mode:\s*validation_only\s*$'
            $validPromptText | Should Match '(?m)^Validation Command:\s*git status --short\s*$'
        }
        finally {
            if ($fixture -and (Test-Path -Path $fixture.Root)) {
                Remove-Item -Path $fixture.Root -Recurse -Force
            }
        }
    }

    It 'accepts target-selection work without a target file before bounded edit materialization' {
        $fixture = New-IntakeStateFixture
        try {
            foreach ($relativePath in @($intakeArtifactRelativePaths)) {
                $pathValue = Join-Path $repoRoot $relativePath
                if (Test-Path -Path $pathValue -PathType Leaf) {
                    Remove-Item -Path $pathValue -Force
                }
            }

            $targetSelectionScope = @"
Task mode: target_selection
TOD must select one fresh harmless status/UI target.
Inspect candidate files, reject unsuitable candidates, choose one target, and publish a target-selection artifact.
No source code modifications in this rung.
"@
            $targetSelection = (& $todScript -Action execute-chat-task -ConfigPath $fixture.ConfigPath -StatePath $fixture.StatePath -ObjectiveId 'TOD-TARGET-SELECTION-MODE-RUNG-V1' -TaskId 'TSK-TARGET-SELECTION-MODE-RUNG-V1' -RequestId 'REQ-TARGET-SELECTION-MODE-RUNG-V1' -CorrelationId 'CORR-TARGET-SELECTION-MODE-RUNG-V1' -Title 'TOD target selection mode rung' -Description 'TOD selects the target before bounded edit packet materialization.' -Scope $targetSelectionScope -AcceptanceCriteria 'No target_file required until target selection finishes.' -SuccessCriteria 'Target-selection artifact published.' -AssignedExecutor local -TaskCategory training -ExecutionMode async | Out-String | ConvertFrom-Json)

            [string]$targetSelection.intake_arbitration.decision | Should Be 'run_now'
            [string]$targetSelection.intake_arbitration.pre_active_lane_gate.reason_code | Should Be 'canonical_target_selection_task_mode_valid'
            [bool]$targetSelection.intake_arbitration.pre_active_lane_gate.canonical_contract.target_file_required | Should Be $false
            [bool]$targetSelection.intake_arbitration.pre_active_lane_gate.canonical_contract.source_code_modification_allowed | Should Be $false
            [string]$targetSelection.intake_arbitration.pre_active_lane_gate.canonical_contract.task_mode | Should Be 'target_selection'
            @($targetSelection.intake_arbitration.pre_active_lane_gate.canonical_contract.expected_evidence) -contains 'target_selection_artifact' | Should Be $true
        }
        finally {
            if ($fixture -and (Test-Path -Path $fixture.Root)) {
                Remove-Item -Path $fixture.Root -Recurse -Force
            }
        }
    }

    It 'allows packet formation artifact writes to synthesize the packet body while preserving normal artifact-write content requirements' {
        $fixture = New-IntakeStateFixture
        try {
            foreach ($relativePath in @($intakeArtifactRelativePaths)) {
                $pathValue = Join-Path $repoRoot $relativePath
                if (Test-Path -Path $pathValue -PathType Leaf) {
                    Remove-Item -Path $pathValue -Force
                }
            }

            $packetScope = @"
Task Class: implementation
Task Category: packet_formation
Edit Mode: artifact_write
Target File: runtime_remote_training/tod_independent_resolution_attempts/ENT_001_ENTERPRISE_MODEL_IMPLEMENT_PACKET.latest.json
Inspect Target File: tmp_remote_mim/core/models.py
Source Evidence: runtime_remote_training/read_only_audit_artifacts/OBSERVATORY_ENTERPRISE_ACCOUNT_MODEL_ANCHOR_DISCOVERY.latest.json
Validation Command: .\.venv\Scripts\python.exe -m py_compile tmp_remote_mim\core\models.py
Validation Pattern: py_compile pass
Required output: synthesize one bounded implementation packet or publish a precise blocker.
"@
            $packetFormation = (& $todScript -Action execute-chat-task -ConfigPath $fixture.ConfigPath -StatePath $fixture.StatePath -ObjectiveId 'ENT-001-ENTERPRISE-DATABASE-FOUNDATION-V1' -TaskId 'TSK-ENT-001-MODEL-PACKET-TEST' -RequestId 'REQ-ENT-001-MODEL-PACKET-TEST' -CorrelationId 'CORR-ENT-001-MODEL-PACKET-TEST' -Title 'Form ENT-001 model packet' -Description 'Packet formation should reach active lane without pre-supplying New Text.' -Scope $packetScope -AcceptanceCriteria 'Packet formation can synthesize or block inside executor.' -SuccessCriteria 'Gate accepts packet formation artifact-write request.' -AssignedExecutor local -TaskCategory packet_formation -ExecutionMode async | Out-String | ConvertFrom-Json)

            [string]$packetFormation.intake_arbitration.decision | Should Be 'run_now'
            [string]$packetFormation.intake_arbitration.pre_active_lane_gate.reason_code | Should Be 'canonical_bounded_edit_packet_valid'
            [bool]$packetFormation.intake_arbitration.pre_active_lane_gate.accepted | Should Be $true

            $normalScope = @"
Task Class: implementation
Task Category: code_change
Edit Mode: artifact_write
Target File: runtime_remote_training/tod_independent_resolution_attempts/NORMAL_ARTIFACT_WRITE_TEST.latest.json
Validation Command: Select-String -Path runtime_remote_training/tod_independent_resolution_attempts/NORMAL_ARTIFACT_WRITE_TEST.latest.json -SimpleMatch ready
"@
            $normalArtifactWrite = (& $todScript -Action execute-chat-task -ConfigPath $fixture.ConfigPath -StatePath $fixture.StatePath -ObjectiveId 'objective-normal-artifact-write' -TaskId 'TSK-NORMAL-ARTIFACT-WRITE' -RequestId 'REQ-NORMAL-ARTIFACT-WRITE' -CorrelationId 'CORR-NORMAL-ARTIFACT-WRITE' -Title 'Normal artifact write missing body' -Description 'Normal artifact writes still require New Text.' -Scope $normalScope -AcceptanceCriteria 'Must reject missing artifact body.' -SuccessCriteria 'Must reject missing artifact body.' -AssignedExecutor local -TaskCategory code_change -ExecutionMode async | Out-String | ConvertFrom-Json)

            [string]$normalArtifactWrite.intake_arbitration.decision | Should Be 'rejected_before_active_lane'
            [string]$normalArtifactWrite.intake_arbitration.pre_active_lane_gate.reason_code | Should Be 'malformed_bounded_edit_packet'
            @($normalArtifactWrite.intake_arbitration.pre_active_lane_gate.missing_fields) -contains 'new_text_or_snippet' | Should Be $true
        }
        finally {
            if ($fixture -and (Test-Path -Path $fixture.Root)) {
                Remove-Item -Path $fixture.Root -Recurse -Force
            }
        }
    }

    It 'rejects a duplicate queued request and preserves the active lane' {
        $fixture = New-IntakeStateFixture
        try {
            Set-ActiveIntakeLane -Fixture $fixture -TaskId 'TSKCHAT-ACTIVE-DUP' -ObjectiveId 'objective-active-dup' -Source 'operator_chat' -Priority 'operator_direct_objective'

            $first = (& $todScript -Action execute-chat-task -ConfigPath $fixture.ConfigPath -StatePath $fixture.StatePath -ObjectiveId 'objective-dup' -TaskId 'TSKCHAT-DUPLICATE' -RequestId 'REQ-DUPLICATE' -CorrelationId 'CORR-DUPLICATE' -Title 'Duplicate queued task' -Description 'Duplicate queued task' -Scope 'OBJECTIVE: Duplicate queued task' -AcceptanceCriteria 'Queue once.' -SuccessCriteria 'Queue once.' -AssignedExecutor local -TaskCategory chat_execution -ExecutionMode async | Out-String | ConvertFrom-Json)
            $second = (& $todScript -Action execute-chat-task -ConfigPath $fixture.ConfigPath -StatePath $fixture.StatePath -ObjectiveId 'objective-dup' -TaskId 'TSKCHAT-DUPLICATE' -RequestId 'REQ-DUPLICATE' -CorrelationId 'CORR-DUPLICATE' -Title 'Duplicate queued task' -Description 'Duplicate queued task' -Scope 'OBJECTIVE: Duplicate queued task' -AcceptanceCriteria 'Queue once.' -SuccessCriteria 'Queue once.' -AssignedExecutor local -TaskCategory chat_execution -ExecutionMode async | Out-String | ConvertFrom-Json)

            [string]$first.intake_arbitration.decision | Should Be 'queue'
            [string]$second.intake_arbitration.decision | Should Be 'reject_duplicate'
            [string]$second.selected_task.task_id | Should Be 'TSKCHAT-ACTIVE-DUP'
        }
        finally {
            if ($fixture -and (Test-Path -Path $fixture.Root)) {
                Remove-Item -Path $fixture.Root -Recurse -Force
            }
        }
    }

    It 'reports queue state after refresh through get-intake-arbitration' {
        $fixture = New-IntakeStateFixture
        try {
            Set-ActiveIntakeLane -Fixture $fixture -TaskId 'TSKCHAT-ACTIVE-REFRESH' -ObjectiveId 'objective-active-refresh' -Source 'operator_chat' -Priority 'operator_direct_objective'
            $queued = (& $todScript -Action execute-chat-task -ConfigPath $fixture.ConfigPath -StatePath $fixture.StatePath -ObjectiveId 'objective-refresh-queued' -TaskId 'TSKCHAT-REFRESH-QUEUED' -RequestId 'REQ-REFRESH-QUEUED' -CorrelationId 'CORR-REFRESH-QUEUED' -Title 'Refresh queued task' -Description 'Refresh queued task' -Scope 'OBJECTIVE: Refresh queued task' -AcceptanceCriteria 'Survive reload.' -SuccessCriteria 'Survive reload.' -AssignedExecutor local -TaskCategory chat_execution -ExecutionMode async | Out-String | ConvertFrom-Json)
            $reported = (& $todScript -Action get-intake-arbitration -ConfigPath $fixture.ConfigPath -StatePath $fixture.StatePath | Out-String | ConvertFrom-Json)

            [string]$queued.intake_arbitration.decision | Should Be 'queue'
            [string]$reported.active_task.task_id | Should Be 'TSKCHAT-ACTIVE-REFRESH'
            [string]$reported.next_task_after_current.task_id | Should Be 'TSKCHAT-REFRESH-QUEUED'
            @($reported.queued_tasks).Count | Should BeGreaterThan 0
        }
        finally {
            if ($fixture -and (Test-Path -Path $fixture.Root)) {
                Remove-Item -Path $fixture.Root -Recurse -Force
            }
        }
    }

    It 'drains exactly one eligible queued task after active completion' {
        $fixture = New-IntakeStateFixture
        try {
            Set-ActiveIntakeLane -Fixture $fixture -TaskId 'TSKCHAT-DRAIN-ACTIVE' -ObjectiveId 'objective-drain-active' -Source 'operator_chat' -Priority 'operator_direct_objective' -LaneStatus 'completed' -TaskStatus 'completed'
            $low = New-QueuedIntakeItem -RequestId 'REQ-DRAIN-MIM' -TaskId 'TSK-DRAIN-MIM' -ObjectiveId 'objective-drain-mim' -Source 'mim_request' -Priority 'mim_request' -ReceivedAt '2026-05-07T00:00:00Z'
            $high = New-QueuedIntakeItem -RequestId 'REQ-DRAIN-REPAIR' -TaskId 'TSKCHAT-DRAIN-REPAIR' -ObjectiveId 'objective-drain-repair' -Source 'operator_chat' -Priority 'operator_admin_repair' -ReceivedAt '2026-05-07T00:01:00Z'
            Set-IntakeQueueItems -ActiveTaskId 'TSKCHAT-DRAIN-ACTIVE' -Items @($low, $high)

            $reported = (& $todScript -Action get-intake-arbitration -ConfigPath $fixture.ConfigPath -StatePath $fixture.StatePath | Out-String | ConvertFrom-Json)

            [bool]$reported.drain.drained | Should Be $true
            [string]$reported.arbitration.decision | Should Be 'dequeue_after_completion'
            [string]$reported.active_task.task_id | Should Be 'TSKCHAT-DRAIN-REPAIR'
            [string]$reported.arbitration.prior_active_task.task_id | Should Be 'TSKCHAT-DRAIN-ACTIVE'
            [int]$reported.arbitration.remaining_queue_count | Should Be 1
            [string]$reported.next_task_after_current.task_id | Should Be 'TSK-DRAIN-MIM'
        }
        finally {
            if ($fixture -and (Test-Path -Path $fixture.Root)) {
                Remove-Item -Path $fixture.Root -Recurse -Force
            }
        }
    }

    It 'does not promote expired accepted intake items during drain' {
        $fixture = New-IntakeStateFixture
        try {
            Set-ActiveIntakeLane -Fixture $fixture -TaskId 'TSKCHAT-DRAIN-EXPIRED-ACTIVE' -ObjectiveId 'objective-drain-expired-active' -Source 'operator_chat' -Priority 'operator_direct_objective' -LaneStatus 'completed' -TaskStatus 'completed'
            $expired = New-QueuedIntakeItem -RequestId 'REQ-DRAIN-EXPIRED' -TaskId 'TSKCHAT-DRAIN-EXPIRED' -ObjectiveId 'objective-drain-expired' -Source 'operator_chat' -Priority 'operator_admin_repair' -ReceivedAt '2026-05-07T00:00:00Z' -Status 'accepted'
            $fresh = New-QueuedIntakeItem -RequestId 'REQ-DRAIN-FRESH' -TaskId 'TSKCHAT-DRAIN-FRESH' -ObjectiveId 'objective-drain-fresh' -Source 'operator_chat' -Priority 'operator_direct_objective' -ReceivedAt '2026-07-19T19:00:00Z'
            $fresh.expires_at = '2026-07-20T19:00:00Z'
            Set-IntakeQueueItems -ActiveTaskId 'TSKCHAT-DRAIN-EXPIRED-ACTIVE' -Items @($expired, $fresh)

            $reported = (& $todScript -Action get-intake-arbitration -ConfigPath $fixture.ConfigPath -StatePath $fixture.StatePath | Out-String | ConvertFrom-Json)

            [bool]$reported.drain.drained | Should Be $true
            [string]$reported.active_task.task_id | Should Be 'TSKCHAT-DRAIN-FRESH'
            $queueItems = @($reported.queue.items)
            $expiredAfter = @($queueItems | Where-Object { [string]$_.task_id -eq 'TSKCHAT-DRAIN-EXPIRED' } | Select-Object -First 1)
            [string]$expiredAfter.status | Should Be 'expired'
            [string]$expiredAfter.blocked_reason_code | Should Be 'intake_item_expired_before_promotion'
        }
        finally {
            if ($fixture -and (Test-Path -Path $fixture.Root)) {
                Remove-Item -Path $fixture.Root -Recurse -Force
            }
        }
    }

    It 'does not drain before the active lane reaches terminal completion' {
        $fixture = New-IntakeStateFixture
        try {
            Set-ActiveIntakeLane -Fixture $fixture -TaskId 'TSKCHAT-NOT-TERMINAL' -ObjectiveId 'objective-not-terminal' -Source 'operator_chat' -Priority 'operator_direct_objective'
            $queued = New-QueuedIntakeItem -RequestId 'REQ-NOT-TERMINAL' -TaskId 'TSKCHAT-NOT-TERMINAL-QUEUED' -ObjectiveId 'objective-not-terminal-queued'
            Set-IntakeQueueItems -ActiveTaskId 'TSKCHAT-NOT-TERMINAL' -Items @($queued)

            $reported = (& $todScript -Action get-intake-arbitration -ConfigPath $fixture.ConfigPath -StatePath $fixture.StatePath | Out-String | ConvertFrom-Json)

            [bool]$reported.drain.drained | Should Be $false
            [string]$reported.active_task.task_id | Should Be 'TSKCHAT-NOT-TERMINAL'
            [string]$reported.next_task_after_current.task_id | Should Be 'TSKCHAT-NOT-TERMINAL-QUEUED'
        }
        finally {
            if ($fixture -and (Test-Path -Path $fixture.Root)) {
                Remove-Item -Path $fixture.Root -Recurse -Force
            }
        }
    }

    It 'drops duplicate queued work that already matches the terminal active lane' {
        $fixture = New-IntakeStateFixture
        try {
            Set-ActiveIntakeLane -Fixture $fixture -TaskId 'TSKCHAT-DUPLICATE-DONE' -ObjectiveId 'objective-duplicate-done' -Source 'operator_chat' -Priority 'operator_admin_repair' -LaneStatus 'completed' -TaskStatus 'completed'
            $duplicate = New-QueuedIntakeItem -RequestId 'REQ-TSKCHAT-DUPLICATE-DONE' -TaskId 'TSKCHAT-DUPLICATE-DONE' -ObjectiveId 'objective-duplicate-done' -Priority 'operator_admin_repair'
            Set-IntakeQueueItems -ActiveTaskId 'TSKCHAT-DUPLICATE-DONE' -Items @($duplicate)

            $reported = (& $todScript -Action get-intake-arbitration -ConfigPath $fixture.ConfigPath -StatePath $fixture.StatePath | Out-String | ConvertFrom-Json)

            [string]$reported.active_task.task_id | Should Be 'TSKCHAT-DUPLICATE-DONE'
            [string]$reported.active_task.status | Should Be 'completed'
            [int]$reported.queue.queued_count | Should Be 0
            @($reported.queue.items).Count | Should Be 0
        }
        finally {
            if ($fixture -and (Test-Path -Path $fixture.Root)) {
                Remove-Item -Path $fixture.Root -Recurse -Force
            }
        }
    }

    It 'skips blocked and invalid queued tasks with exact reason while draining an eligible task' {
        $fixture = New-IntakeStateFixture
        try {
            Set-ActiveIntakeLane -Fixture $fixture -TaskId 'TSKCHAT-DRAIN-SKIP-ACTIVE' -ObjectiveId 'objective-drain-skip-active' -Source 'operator_chat' -Priority 'operator_direct_objective' -LaneStatus 'completed' -TaskStatus 'completed'
            $blocked = New-QueuedIntakeItem -RequestId 'REQ-BLOCKED-QUEUED' -TaskId 'TSKCHAT-BLOCKED-QUEUED' -ObjectiveId 'objective-blocked-queued' -Status 'blocked'
            $invalid = New-QueuedIntakeItem -RequestId 'REQ-INVALID-QUEUED' -TaskId '' -ObjectiveId 'objective-invalid-queued'
            $eligible = New-QueuedIntakeItem -RequestId 'REQ-ELIGIBLE-QUEUED' -TaskId 'TSKCHAT-ELIGIBLE-QUEUED' -ObjectiveId 'objective-eligible-queued' -Priority 'mim_request'
            Set-IntakeQueueItems -ActiveTaskId 'TSKCHAT-DRAIN-SKIP-ACTIVE' -Items @($blocked, $invalid, $eligible)

            $reported = (& $todScript -Action get-intake-arbitration -ConfigPath $fixture.ConfigPath -StatePath $fixture.StatePath | Out-String | ConvertFrom-Json)
            $queueItems = @($reported.queue.items)
            $invalidAfter = @($queueItems | Where-Object { [string]$_.request_id -eq 'REQ-INVALID-QUEUED' } | Select-Object -First 1)
            $blockedAfter = @($queueItems | Where-Object { [string]$_.request_id -eq 'REQ-BLOCKED-QUEUED' } | Select-Object -First 1)

            [bool]$reported.drain.drained | Should Be $true
            [string]$reported.active_task.task_id | Should Be 'TSKCHAT-ELIGIBLE-QUEUED'
            [string]$invalidAfter[0].status | Should Be 'blocked'
            [string]$invalidAfter[0].blocked_reason_code | Should Be 'intake_item_missing_required_identity'
            [string]$blockedAfter[0].status | Should Be 'blocked'
            [string]$reported.active_task.task_id | Should Not Be 'objective-14-task-79'
        }
        finally {
            if ($fixture -and (Test-Path -Path $fixture.Root)) {
                Remove-Item -Path $fixture.Root -Recurse -Force
            }
        }
    }

    It 'keeps direct-chat idempotency conflicts blocked during the execution simulation' {
        $simulationScript = Join-Path $repoRoot 'scripts/Invoke-TODDirectChatExecutionSimulation.ps1'
        $outputRoot = Join-Path $repoRoot ('tod/out/tests/intake-idempotency-simulation-' + [guid]::NewGuid().ToString('N'))
        try {
            $raw = & $simulationScript -OutputRoot $outputRoot -AsJson | Out-String
            $simulation = $raw | ConvertFrom-Json
            $conflict = @($simulation.scenarios | Where-Object { [string]$_.name -eq 'same task_id with different payload' } | Select-Object -First 1)
            $completedReplay = @($simulation.scenarios | Where-Object { [string]$_.name -eq 'duplicate completed request' } | Select-Object -First 1)

            [bool]$simulation.production_shared_roots_modified | Should Be $false
            @($conflict).Count | Should Be 1
            [string]$conflict[0].decision | Should Be 'blocked_needs_operator'
            [string]$conflict[0].reason | Should Be 'idempotency_conflict'
            @($completedReplay).Count | Should Be 1
            [string]$completedReplay[0].decision | Should Be 'reject_duplicate'
            [string]$completedReplay[0].reason | Should Be 'duplicate_completed_replay_prior_result'
        }
        finally {
            if (Test-Path -Path $outputRoot) {
                Remove-Item -Path $outputRoot -Recurse -Force
            }
        }
    }
}
