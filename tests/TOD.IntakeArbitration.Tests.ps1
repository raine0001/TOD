Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$todScript = Join-Path $repoRoot 'scripts/TOD.ps1'

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
    It 'queues a MIM request while an operator task is active' {
        $fixture = New-IntakeStateFixture
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

            $result = (& $todScript -Action run-bridge-request -RequestId 'REQ-MIM-WHILE-OPERATOR' -ConfigPath $fixture.ConfigPath -StatePath $fixture.StatePath | Out-String | ConvertFrom-Json)

            [string]$result.decision | Should Be 'queue'
            [bool]$result.active_task_preserved | Should Be $true
            [string]$result.intake_arbitration.active_lane.task_id | Should Be 'TSKCHAT-ACTIVE-OPERATOR'
            [string]$result.intake_queue.next_task_after_current.source | Should Be 'mim_request'
        }
        finally {
            if ($fixture -and (Test-Path -Path $fixture.Root)) {
                Remove-Item -Path $fixture.Root -Recurse -Force
            }
        }
    }

    It 'promotes operator admin repair over an active MIM lane' {
        $fixture = New-IntakeStateFixture
        try {
            Set-ActiveIntakeLane -Fixture $fixture -TaskId 'TSK-MIM-ACTIVE' -ObjectiveId 'objective-mim-active' -Source 'mim_request' -Priority 'mim_request'

            $result = (& $todScript -Action execute-chat-task -ConfigPath $fixture.ConfigPath -StatePath $fixture.StatePath -ObjectiveId 'objective-admin-repair' -TaskId 'TSKCHAT-ADMIN-REPAIR' -RequestId 'REQ-ADMIN-REPAIR' -CorrelationId 'CORR-ADMIN-REPAIR' -Title 'ADMIN ACTION: repair active lane' -Description 'ADMIN ACTION: repair active lane' -Scope 'ADMIN ACTION: repair active lane' -AcceptanceCriteria 'Admin repair may supersede MIM.' -SuccessCriteria 'Admin repair may supersede MIM.' -AssignedExecutor local -TaskCategory diagnostic_implementation_repair -ExecutionMode async | Out-String | ConvertFrom-Json)

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

            [bool]$simulation.passed | Should Be $true
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
