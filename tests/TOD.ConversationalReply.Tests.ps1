Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptUnderTest = Join-Path $repoRoot 'scripts/Invoke-TODConversationalReply.ps1'

function Write-JsonNoBom {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)]$Payload,
        [int]$Depth = 20
    )

    $directory = Split-Path -Parent $PathValue
    if (-not (Test-Path -Path $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($PathValue, ($Payload | ConvertTo-Json -Depth $Depth), $utf8NoBom)
}

function New-ConversationalReplyFixture {
    $base = Join-Path $repoRoot ('tod/out/tests/conversational-reply-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $base -Force | Out-Null

    return [pscustomobject]@{
        Base = $base
        BuildStatePath = Join-Path $base 'current_build_state.json'
        IntegrationStatusPath = Join-Path $base 'integration_status.json'
        ObjectivesPath = Join-Path $base 'objectives.json'
        MaintenancePath = Join-Path $base 'TOD_SELF_HEALTH_RUN.latest.json'
        WatchdogPath = Join-Path $base 'tod_recovery_watchdog.latest.json'
        MimWallStatePath = Join-Path $base 'mim_wall_state.latest.json'
        VoiceConfigPath = Join-Path $base 'voice-adapter.json'
        CommitmentPath = Join-Path $base 'tod_operator_chat_commitment.latest.json'
        ReasoningPath = Join-Path $base 'tod_operator_chat_reasoning.latest.json'
        ActionAuditPath = Join-Path $base 'tod_operator_chat_action_audit.latest.json'
        ListenerRequestPath = Join-Path $base 'MIM_TOD_TASK_REQUEST.latest.json'
        ListenerResultPath = Join-Path $base 'TOD_MIM_TASK_RESULT.latest.json'
        ListenerCommandStatusPath = Join-Path $base 'TOD_MIM_COMMAND_STATUS.latest.json'
        ListenerDecisionPath = Join-Path $base 'TOD_MIM_EXECUTION_DECISION.latest.json'
        TodConfigPath = Join-Path $base 'tod-config.json'
        TodStatePath = Join-Path $base 'tod-state.json'
        ExecutionReadinessPath = Join-Path $base 'tod_execution_readiness.latest.json'
        ExecutionReadinessHistoryPath = Join-Path $base 'tod_execution_readiness_history.latest.json'
    }
}

function Write-ExecutionReadyTodConfig {
    param(
        [Parameter(Mandatory = $true)]$Fixture,
        [string]$ActiveEngine = 'codex',
        [string]$FallbackEngine = 'local'
    )

    Write-JsonNoBom -PathValue $Fixture.ExecutionReadinessPath -Payload ([pscustomobject]@{
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        summary = [pscustomobject]@{
            passed_all = $true
            exit_code = 0
        }
    })

    Write-JsonNoBom -PathValue $Fixture.TodConfigPath -Payload ([pscustomobject]@{
        mode = 'local'
        fallback_to_local = $true
        timeout_seconds = 30
        engineering_loop = [pscustomobject]@{
            max_run_history = 150
            max_scorecard_history = 150
            max_cycle_records = 300
        }
        execution_engine = [pscustomobject]@{
            active = $ActiveEngine
            fallback = $FallbackEngine
            allow_fallback = $true
            readiness_policy = [pscustomobject]@{
                enabled = $true
                signal_path = $Fixture.ExecutionReadinessPath
                history_path = $Fixture.ExecutionReadinessHistoryPath
                max_artifact_age_minutes = 30
                display_max_artifact_age_minutes = 10
                block_actions = @('run-task')
                degrade_actions = @('engineer-run', 'codex_handoff')
                block_states = @('stale', 'invalid', 'unknown')
                degrade_states = @('degraded', 'stale', 'invalid', 'unknown')
                degrade_apply_plan = $true
                history_max_entries = 50
            }
        }
    })
}

function Backup-ChatDispatchArtifacts {
    $isolatedSharedRoot = Join-Path $repoRoot ('tod/out/tests/chat-dispatch-shared-' + [guid]::NewGuid().ToString('N'))
    $isolatedRuntimeRoot = Join-Path $isolatedSharedRoot 'runtime/shared'
    $isolatedRemoteRoot = Join-Path $isolatedSharedRoot 'tmp_remote_mim/runtime/shared'
    New-Item -ItemType Directory -Path $isolatedRuntimeRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $isolatedRemoteRoot -Force | Out-Null

    $paths = @(
        (Join-Path $repoRoot 'runtime/shared/MIM_TOD_TASK_REQUEST.latest.json'),
        (Join-Path $repoRoot 'runtime/shared/TOD_ACTIVITY_STREAM.latest.json'),
        (Join-Path $repoRoot 'runtime/shared/TOD_ACTIVE_EXECUTION_LANE.latest.json'),
        (Join-Path $repoRoot 'runtime/shared/TOD_INTAKE_QUEUE.latest.json'),
        (Join-Path $repoRoot 'runtime/shared/TOD_INTAKE_ARBITRATION.latest.json'),
        (Join-Path $repoRoot 'tmp_remote_mim/runtime/shared/MIM_TOD_TASK_REQUEST.latest.json'),
        (Join-Path $repoRoot 'tmp_remote_mim/runtime/shared/TOD_ACTIVITY_STREAM.latest.json'),
        (Join-Path $repoRoot 'tmp_remote_mim/runtime/shared/TOD_ACTIVE_EXECUTION_LANE.latest.json'),
        (Join-Path $repoRoot 'tmp_remote_mim/runtime/shared/TOD_INTAKE_QUEUE.latest.json'),
        (Join-Path $repoRoot 'tmp_remote_mim/runtime/shared/TOD_INTAKE_ARBITRATION.latest.json'),
        (Join-Path $repoRoot 'tod/out/context-sync/listener/MIM_TOD_TASK_REQUEST.latest.json'),
        (Join-Path $repoRoot 'tod/out/context-sync/listener/TOD_ACTIVE_EXECUTION_LANE.latest.json'),
        (Join-Path $repoRoot 'tod/out/context-sync/listener/TOD_INTAKE_QUEUE.latest.json'),
        (Join-Path $repoRoot 'tod/out/context-sync/listener/TOD_INTAKE_ARBITRATION.latest.json')
    )

    $records = @(
        [pscustomobject]@{
            path = '__ENV_TOD_EXECUTION_SHARED_ROOTS__'
            exists = $false
            content = [string]$env:TOD_EXECUTION_SHARED_ROOTS
            isolated_root = $isolatedSharedRoot
        }
    )
    $env:TOD_EXECUTION_SHARED_ROOTS = (($isolatedRuntimeRoot, $isolatedRemoteRoot) -join ';')

    foreach ($path in $paths) {
        $records += [pscustomobject]@{
            path = $path
            exists = (Test-Path -Path $path)
            content = if (Test-Path -Path $path) { [System.IO.File]::ReadAllText($path) } else { '' }
        }
    }

    return @($records)
}

function Restore-ChatDispatchArtifacts {
    param([object[]]$Records)

    foreach ($record in @($Records)) {
        if ([string]$record.path -eq '__ENV_TOD_EXECUTION_SHARED_ROOTS__') {
            if ([string]::IsNullOrWhiteSpace([string]$record.content)) {
                Remove-Item Env:\TOD_EXECUTION_SHARED_ROOTS -ErrorAction SilentlyContinue
            }
            else {
                $env:TOD_EXECUTION_SHARED_ROOTS = [string]$record.content
            }
            if ($record.PSObject.Properties['isolated_root'] -and -not [string]::IsNullOrWhiteSpace([string]$record.isolated_root) -and (Test-Path -Path ([string]$record.isolated_root))) {
                Remove-Item -Path ([string]$record.isolated_root) -Recurse -Force -ErrorAction SilentlyContinue
            }
            continue
        }
        if ([bool]$record.exists) {
            $directory = Split-Path -Parent ([string]$record.path)
            if (-not (Test-Path -Path $directory)) {
                New-Item -ItemType Directory -Path $directory -Force | Out-Null
            }
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText([string]$record.path, [string]$record.content, $utf8NoBom)
        }
        elseif (Test-Path -Path ([string]$record.path)) {
            Remove-Item -Path ([string]$record.path) -Force
        }
    }
}

function Get-TestExecutionSharedRoot {
    if (-not [string]::IsNullOrWhiteSpace([string]$env:TOD_EXECUTION_SHARED_ROOTS)) {
        $root = @(([string]$env:TOD_EXECUTION_SHARED_ROOTS) -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -First 1)
        if (@($root).Count -gt 0) {
            return [string]$root[0]
        }
    }

    return (Join-Path $repoRoot 'runtime/shared')
}

function Get-TestExecutionSharedArtifactPath {
    param([Parameter(Mandatory = $true)][string]$FileName)
    return (Join-Path (Get-TestExecutionSharedRoot) $FileName)
}

function Get-TaskActivityEvents {
    param([Parameter(Mandatory = $true)][string]$TaskId)

    $paths = @(
        (Get-TestExecutionSharedArtifactPath -FileName 'TOD_ACTIVITY_STREAM.latest.json'),
        (Join-Path $repoRoot 'tmp_remote_mim/runtime/shared/TOD_ACTIVITY_STREAM.latest.json')
    )

    foreach ($path in $paths) {
        if (-not (Test-Path -Path $path)) {
            continue
        }

        try {
            $payload = Get-Content -Path $path -Raw | ConvertFrom-Json
        }
        catch {
            continue
        }

        $events = @()
        if ($payload -and $payload.PSObject.Properties['events'] -and $null -ne $payload.events) {
            $events = @($payload.events | Where-Object { [string]$_.task_id -eq $TaskId })
        }
        if (@($events).Count -gt 0) {
            return @($events)
        }
    }

    return @()
}

function Wait-ForTaskActivityEvent {
    param(
        [Parameter(Mandatory = $true)][string]$TaskId,
        [Parameter(Mandatory = $true)][string[]]$EventTypes,
        [int]$TimeoutSeconds = 30
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $events = @(Get-TaskActivityEvents -TaskId $TaskId)
        $eventTypeValues = @($events | ForEach-Object { [string]$_.event_type })
        $allPresent = $true
        foreach ($eventType in @($EventTypes)) {
            if ($eventTypeValues -notcontains [string]$eventType) {
                $allPresent = $false
                break
            }
        }
        if ($allPresent) {
            return @($events)
        }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)

    return @()
}

function Wait-ForFilePattern {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [int]$TimeoutSeconds = 90
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        if (Test-Path -Path $Path) {
            $content = [string](Get-Content -Path $Path -Raw)
            if ($content -match $Pattern) {
                return $true
            }
        }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)

    return $false
}

function Wait-ForTaskTerminalState {
    param(
        [Parameter(Mandatory = $true)][string]$StatePath,
        [Parameter(Mandatory = $true)][string]$TaskId,
        [int]$TimeoutSeconds = 90
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        if (Test-Path -Path $StatePath) {
            try {
                $state = Get-Content -Path $StatePath -Raw | ConvertFrom-Json
                $task = @($state.tasks | Where-Object { [string]$_.id -eq $TaskId } | Select-Object -First 1)
                if (@($task).Count -gt 0 -and $task[0].PSObject.Properties['terminal_state'] -and $null -ne $task[0].terminal_state) {
                    return $task[0]
                }
            }
            catch {
            }
        }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)

    return $null
}

Describe 'TOD conversational reply' {
    It 'dispatches GOAL TASKS ACCEPTANCE prompts through the execution lane' {
        (Test-Path -Path $scriptUnderTest) | Should Be $true

        $fixture = New-ConversationalReplyFixture
        $artifactBackup = Backup-ChatDispatchArtifacts
        try {
            Write-JsonNoBom -PathValue $fixture.BuildStatePath -Payload ([pscustomobject]@{
                status = 'active'
                task = 'Direct chat dispatch'
            })
            Write-JsonNoBom -PathValue $fixture.ObjectivesPath -Payload ([pscustomobject]@{
                objectives = @()
            })
            Write-JsonNoBom -PathValue $fixture.MaintenancePath -Payload ([pscustomobject]@{
                overall_status = 'healthy'
                overall_severity = 'info'
            })
            Write-JsonNoBom -PathValue $fixture.WatchdogPath -Payload ([pscustomobject]@{
                state = 'healthy'
            })
            Write-JsonNoBom -PathValue $fixture.VoiceConfigPath -Payload ([pscustomobject]@{
                enabled = $true
            })
            Write-ExecutionReadyTodConfig -Fixture $fixture
            Write-JsonNoBom -PathValue $fixture.TodStatePath -Payload ([pscustomobject]@{
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

            $query = @'
GOAL: Make /api/tod-conversation return quickly after creating a task, while execution continues asynchronously and progress appears through /api/activity-stream.
TASKS: 1. Split direct-chat handling into request/ack path and background execution path.
ACCEPTANCE: /api/tod-conversation responds quickly and background execution continues through the activity stream.
'@

            $result = (& $scriptUnderTest -Query $query -CurrentBuildStatePath $fixture.BuildStatePath -ObjectivesPath $fixture.ObjectivesPath -MaintenancePath $fixture.MaintenancePath -WatchdogPath $fixture.WatchdogPath -ProviderConfigPath $fixture.VoiceConfigPath -TodConfigPath $fixture.TodConfigPath -TodStatePath $fixture.TodStatePath -SkipModel -AsJson | Out-String | ConvertFrom-Json)

            [bool]$result.ok | Should Be $true
            [string]$result.request_kind | Should Be 'implementation_request'
            [string]$result.intent.intent | Should Be 'COMMAND'
            [bool]$result.command_dispatch.attempted | Should Be $true
            [bool]$result.command_dispatch.created | Should Be $true
            [string]$result.command_dispatch.task_id | Should Not BeNullOrEmpty
        }
        finally {
            Restore-ChatDispatchArtifacts -Records $artifactBackup
            if ($fixture -and (Test-Path -Path $fixture.Base)) {
                Remove-Item -Path $fixture.Base -Recurse -Force
            }
        }
    }

    It 'classifies implementation requests and reports bounded steps with mim_wall status' {
        (Test-Path -Path $scriptUnderTest) | Should Be $true

        $fixture = New-ConversationalReplyFixture
        try {
            Write-JsonNoBom -PathValue $fixture.BuildStatePath -Payload ([pscustomobject]@{
                objective_id = 'objective-comm-1'
                status = 'active'
                task = 'Build TOD direct conversation lane'
            })
            Write-JsonNoBom -PathValue $fixture.ObjectivesPath -Payload ([pscustomobject]@{
                objectives = @(
                    [pscustomobject]@{ objective_id = 'objective-comm-1'; title = 'Conversation lane' },
                    [pscustomobject]@{ objective_id = 'objective-comm-2'; title = 'Voice lane' }
                )
            })
            Write-JsonNoBom -PathValue $fixture.MaintenancePath -Payload ([pscustomobject]@{
                overall_status = 'healthy_with_fallback'
                overall_severity = 'warning'
            })
            Write-JsonNoBom -PathValue $fixture.WatchdogPath -Payload ([pscustomobject]@{
                state = 'healthy'
            })
            Write-JsonNoBom -PathValue $fixture.MimWallStatePath -Payload ([pscustomobject]@{
                queue_count = 2
                projected_event_count = 5
                mode = 'read_only_phase'
                upstream_generated_at = '2026-04-14T01:02:03Z'
            })
            Write-JsonNoBom -PathValue $fixture.VoiceConfigPath -Payload ([pscustomobject]@{
                enabled = $true
            })
            Write-JsonNoBom -PathValue $fixture.CommitmentPath -Payload ([pscustomobject]@{
                objective_id = 'objective-comm-1'
                state = 'committed'
                action_label = 'Refresh Conversation Context'
                summary = 'Operator committed to refreshing TOD conversation context.'
                reasoning_bundle_id = 'bundle-123'
            })
            Write-JsonNoBom -PathValue $fixture.ReasoningPath -Payload ([pscustomobject]@{
                reasoning_bundle_id = 'bundle-123'
                operator_summary = 'TOD should refresh the direct conversation context before changing the active lane.'
                recommended_next_step = 'refresh-conversation-context'
                evidence_count = 4
                evidence_flags = @('operator_commitment_active', 'conversation_lane_ready')
            })
            Write-JsonNoBom -PathValue $fixture.ActionAuditPath -Payload ([pscustomobject]@{
                audit_id = 'audit-123'
                action_label = 'Refresh Conversation Context'
                outcome_status = 'approved'
                proposal_id = 'proposal-123'
                proposal_title = 'Refresh conversation context pack'
                evidence_flags = @('conversation_lane_ready')
            })

            $result = (& $scriptUnderTest -Query 'Set up TOD to be fully conversational and implement the path now.' -CurrentBuildStatePath $fixture.BuildStatePath -ObjectivesPath $fixture.ObjectivesPath -MaintenancePath $fixture.MaintenancePath -WatchdogPath $fixture.WatchdogPath -MimWallStatePath $fixture.MimWallStatePath -CommitmentPath $fixture.CommitmentPath -ReasoningPath $fixture.ReasoningPath -ActionAuditPath $fixture.ActionAuditPath -ProviderConfigPath $fixture.VoiceConfigPath -SkipModel -AsJson | Out-String | ConvertFrom-Json)

            [bool]$result.ok | Should Be $true
            [string]$result.request_kind | Should Be 'implementation_request'
            [string]$result.mim_wall_status.summary | Should Match 'mim_wall import is active'
            [int]@($result.communication_skills).Count | Should BeGreaterThan 4
            [int]@($result.bounded_steps).Count | Should Be 5
            [bool]$result.durable_memory.available | Should Be $true
            [string]$result.durable_memory.summary | Should Match 'Latest commitment is committed for Refresh Conversation Context'
            [string]$result.durable_memory.trust_chain_summary | Should Match 'Trust chain is available'
            [string]$result.reply_text | Should Match 'implementation request'
        }
        finally {
            if ($fixture -and (Test-Path -Path $fixture.Base)) {
                Remove-Item -Path $fixture.Base -Recurse -Force
            }
        }
    }

    It 'keeps evidence-only report contracts out of implementation scaffolding' {
        (Test-Path -Path $scriptUnderTest) | Should Be $true

        $fixture = New-ConversationalReplyFixture
        try {
            Write-JsonNoBom -PathValue $fixture.BuildStatePath -Payload ([pscustomobject]@{
                objective_id = 'objective-stale'
                status = 'active'
                task = 'Stale current work should not leak'
            })
            Write-JsonNoBom -PathValue $fixture.ObjectivesPath -Payload ([pscustomobject]@{
                objectives = @(
                    [pscustomobject]@{ objective_id = 'objective-stale'; title = 'Stale objective' }
                )
            })
            Write-JsonNoBom -PathValue $fixture.MaintenancePath -Payload ([pscustomobject]@{
                overall_status = 'needs_attention'
                overall_severity = 'critical'
            })
            Write-JsonNoBom -PathValue $fixture.WatchdogPath -Payload ([pscustomobject]@{
                state = 'error'
            })
            Write-JsonNoBom -PathValue $fixture.VoiceConfigPath -Payload ([pscustomobject]@{
                enabled = $true
            })
            Write-JsonNoBom -PathValue $fixture.CommitmentPath -Payload ([pscustomobject]@{
                objective_id = '170'
                state = 'abandoned'
                action_label = 'Refresh Governance Snapshot'
                summary = 'Operator abandoned the commitment for Refresh Governance Snapshot.'
                reasoning_bundle_id = 'bundle-170'
            })
            Write-JsonNoBom -PathValue $fixture.ReasoningPath -Payload ([pscustomobject]@{
                reasoning_bundle_id = 'bundle-170'
                operator_summary = 'Stale reasoning is still centered on objective 170.'
                recommended_next_step = 'refresh-governance-snapshot'
                evidence_count = 8
                evidence_flags = @('objective_170_stale')
            })
            Write-JsonNoBom -PathValue $fixture.ActionAuditPath -Payload ([pscustomobject]@{
                audit_id = 'audit-170'
                action_label = 'Refresh Governance Snapshot'
                outcome_status = 'previewed'
                evidence_flags = @('stale_context_present')
            })

            $query = @'
Evidence-only report drill. Use only this evidence:
file_changed=scripts/Start-TOD-Elevated.ps1
parse_validation=parse_ok
Answer only these fields:
what_was_applied:
evidence_used:
what_not_to_claim:
current_owner:
'@

            $result = (& $scriptUnderTest -Query $query -CurrentBuildStatePath $fixture.BuildStatePath -ObjectivesPath $fixture.ObjectivesPath -MaintenancePath $fixture.MaintenancePath -WatchdogPath $fixture.WatchdogPath -CommitmentPath $fixture.CommitmentPath -ReasoningPath $fixture.ReasoningPath -ActionAuditPath $fixture.ActionAuditPath -ProviderConfigPath $fixture.VoiceConfigPath -SkipModel -AsJson | Out-String | ConvertFrom-Json)

            [bool]$result.ok | Should Be $true
            [string]$result.request_kind | Should Be 'evidence_report'
            [string]$result.intent.intent | Should Be 'CONVERSATION'
            [string]$result.intent.action | Should Be 'evidence-only report'
            [string]$result.reply_text | Should Not Match 'Current Work:'
            [string]$result.reply_text | Should Not Match 'Communication Skills:'
            [string]$result.reply_text | Should Not Match 'Bounded Steps:'
            [string]$result.reply_text | Should Not Match 'Durable Memory:'
            [string]$result.reply_text | Should Not Match 'Refresh Governance Snapshot'
            [string]$result.reply_text | Should Not Match 'objective 170'
        }
        finally {
            if ($fixture -and (Test-Path -Path $fixture.Base)) {
                Remove-Item -Path $fixture.Base -Recurse -Force
            }
        }
    }

    It 'creates a task, writes the live request artifact, and emits activity for OBJECTIVE chat input' {
        (Test-Path -Path $scriptUnderTest) | Should Be $true

        $fixture = New-ConversationalReplyFixture
        $artifactBackup = Backup-ChatDispatchArtifacts
        try {
            Write-JsonNoBom -PathValue $fixture.BuildStatePath -Payload ([pscustomobject]@{
                status = 'active'
                task = 'Direct chat dispatch'
            })
            Write-JsonNoBom -PathValue $fixture.ObjectivesPath -Payload ([pscustomobject]@{
                objectives = @()
            })
            Write-JsonNoBom -PathValue $fixture.MaintenancePath -Payload ([pscustomobject]@{
                overall_status = 'healthy'
                overall_severity = 'info'
            })
            Write-JsonNoBom -PathValue $fixture.WatchdogPath -Payload ([pscustomobject]@{
                state = 'healthy'
            })
            Write-JsonNoBom -PathValue $fixture.VoiceConfigPath -Payload ([pscustomobject]@{
                enabled = $true
            })
            Write-ExecutionReadyTodConfig -Fixture $fixture
            Write-JsonNoBom -PathValue $fixture.TodStatePath -Payload ([pscustomobject]@{
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

            $query = @'
OBJECTIVE: TOD-DIRECT-ACTION-BINDING
Create a direct chat task that binds actionable operator requests to immediate TOD execution.
STOP CONDITION: TOD chat creates a task, writes the live request artifact, and emits activity.
'@

            $result = (& $scriptUnderTest -Query $query -CurrentBuildStatePath $fixture.BuildStatePath -ObjectivesPath $fixture.ObjectivesPath -MaintenancePath $fixture.MaintenancePath -WatchdogPath $fixture.WatchdogPath -ProviderConfigPath $fixture.VoiceConfigPath -TodConfigPath $fixture.TodConfigPath -TodStatePath $fixture.TodStatePath -SkipModel -AsJson | Out-String | ConvertFrom-Json)

            $requestArtifactPath = Get-TestExecutionSharedArtifactPath -FileName 'MIM_TOD_TASK_REQUEST.latest.json'
            $requestArtifact = Get-Content -Path $requestArtifactPath -Raw | ConvertFrom-Json
            $eventTypes = @($result.command_dispatch.payload.activity_event_types | ForEach-Object { [string]$_ })

            [bool]$result.ok | Should Be $true
            [string]$result.intent.intent | Should Be 'COMMAND'
            [bool]$result.command_dispatch.created | Should Be $true
            [string]$result.command_dispatch.task_id | Should Not BeNullOrEmpty
            [string]$result.command_dispatch.request_id | Should Not BeNullOrEmpty
            [string]$result.command_dispatch.objective_id | Should Not BeNullOrEmpty
            [string]$requestArtifact.task_id | Should Be ([string]$result.command_dispatch.task_id)
            [string]$requestArtifact.request_id | Should Be ([string]$result.command_dispatch.request_id)
            [string]$requestArtifact.objective_id | Should Be ([string]$result.command_dispatch.objective_id)
            ($eventTypes -contains 'task_created_from_chat') | Should Be $true
            ($eventTypes -contains 'task_claimed') | Should Be $true
            (($eventTypes -contains 'execution_started') -or ($eventTypes -contains 'blocked')) | Should Be $true
            [string]$result.reply_text | Should Match ([regex]::Escape("task_id: " + [string]$result.command_dispatch.task_id))
        }
        finally {
            Restore-ChatDispatchArtifacts -Records $artifactBackup
            if ($fixture -and (Test-Path -Path $fixture.Base)) {
                Remove-Item -Path $fixture.Base -Recurse -Force
            }
        }
    }

    It 'creates a fresh task lane for each distinct OBJECTIVE prompt and supersedes the stale chat claim' {
        (Test-Path -Path $scriptUnderTest) | Should Be $true

        $fixture = New-ConversationalReplyFixture
        $artifactBackup = Backup-ChatDispatchArtifacts
        try {
            Write-JsonNoBom -PathValue $fixture.BuildStatePath -Payload ([pscustomobject]@{
                objective_id = 'objective-14'
                status = 'active'
                task = 'Stale direct chat dispatch'
            })
            Write-JsonNoBom -PathValue $fixture.ObjectivesPath -Payload ([pscustomobject]@{
                objectives = @()
            })
            Write-JsonNoBom -PathValue $fixture.MaintenancePath -Payload ([pscustomobject]@{
                overall_status = 'healthy'
                overall_severity = 'info'
            })
            Write-JsonNoBom -PathValue $fixture.WatchdogPath -Payload ([pscustomobject]@{
                state = 'healthy'
            })
            Write-JsonNoBom -PathValue $fixture.VoiceConfigPath -Payload ([pscustomobject]@{
                enabled = $true
            })
            Write-ExecutionReadyTodConfig -Fixture $fixture
            Write-JsonNoBom -PathValue $fixture.TodStatePath -Payload ([pscustomobject]@{
                objectives = @(
                    [pscustomobject]@{
                        id = 'objective-14'
                        title = 'Legacy stale objective'
                        description = 'Legacy stale objective'
                        priority = 'high'
                        constraints = @()
                        success_criteria = @()
                        status = 'in_progress'
                        created_at = '2026-05-05T00:00:00Z'
                        updated_at = '2026-05-05T00:00:00Z'
                    }
                )
                tasks = @(
                    [pscustomobject]@{
                        id = 'objective-14-task-79'
                        objective_id = 'objective-14'
                        title = 'Legacy stale task'
                        type = 'implementation'
                        task_category = 'chat_execution'
                        scope = 'Legacy stale scope'
                        dependencies = @()
                        acceptance_criteria = @('Legacy acceptance')
                        status = 'in_progress'
                        assigned_executor = 'codex'
                        source = 'bridge_runtime_sync'
                        correlation_id = 'CORR-LEGACY'
                        created_at = '2026-05-05T00:00:00Z'
                        updated_at = '2026-05-05T00:00:00Z'
                    }
                )
                execution_results = @()
                review_decisions = @()
                journal = @()
                engine_performance = [pscustomobject]@{ records = @(); updated_at = '' }
                routing_decisions = [pscustomobject]@{ records = @(); updated_at = '' }
                routing_feedback = [pscustomobject]@{ learned_weights = [pscustomobject]@{}; sample_size = 0; version = 'feedback_v1'; updated_at = '' }
                sync_state = [pscustomobject]@{ expected_contract_version = ''; expected_schema_version = ''; local_repo_signature = ''; cached_manifest = $null; last_comparison = $null; last_sync_decision = ''; last_sync_code = ''; compared_at = '' }
            })

            $staleRequest = [pscustomobject]@{
                request_id = 'objective-14-task-79'
                task_id = 'objective-14-task-79'
                objective_id = 'objective-14'
                correlation_id = 'objective-14-task-79'
                target = 'TOD'
                tod_action = 'execute-chat-task'
                generated_at = '2026-05-05T00:00:00Z'
                title = 'Legacy stale task'
                scope = 'Legacy stale scope'
                summary = 'Legacy stale summary'
                requested_outcome = 'Legacy stale outcome'
                metadata_json = [pscustomobject]@{
                    objective_title = 'TOD-INITIATIVE-CORE'
                    task_title = 'Legacy stale task'
                    task_acceptance_criteria = 'Legacy acceptance'
                    source = 'direct_chat'
                }
            }

            Write-JsonNoBom -PathValue (Get-TestExecutionSharedArtifactPath -FileName 'MIM_TOD_TASK_REQUEST.latest.json') -Payload $staleRequest
            Write-JsonNoBom -PathValue (Join-Path $repoRoot 'tmp_remote_mim/runtime/shared/MIM_TOD_TASK_REQUEST.latest.json') -Payload $staleRequest
            Write-JsonNoBom -PathValue (Join-Path $repoRoot 'tod/out/context-sync/listener/MIM_TOD_TASK_REQUEST.latest.json') -Payload $staleRequest

            $queryA = @'
OBJECTIVE: TOD-LOCAL-EXECUTOR-BINDING
Fix the missing local executor binding for direct chat dispatch.
STOP CONDITION: TOD direct chat creates a fresh executable task lane.
'@
            $queryB = @'
OBJECTIVE: TOD-CODE-CHANGE-EXECUTOR-BINDING
Patch the code-change executor binding for direct chat task materialization.
STOP CONDITION: TOD direct chat creates a second fresh executable task lane.
'@

            $resultA = (& $scriptUnderTest -Query $queryA -CurrentBuildStatePath $fixture.BuildStatePath -ObjectivesPath $fixture.ObjectivesPath -MaintenancePath $fixture.MaintenancePath -WatchdogPath $fixture.WatchdogPath -ProviderConfigPath $fixture.VoiceConfigPath -TodConfigPath $fixture.TodConfigPath -TodStatePath $fixture.TodStatePath -SkipModel -AsJson | Out-String | ConvertFrom-Json)
            $resultB = (& $scriptUnderTest -Query $queryB -CurrentBuildStatePath $fixture.BuildStatePath -ObjectivesPath $fixture.ObjectivesPath -MaintenancePath $fixture.MaintenancePath -WatchdogPath $fixture.WatchdogPath -ProviderConfigPath $fixture.VoiceConfigPath -TodConfigPath $fixture.TodConfigPath -TodStatePath $fixture.TodStatePath -SkipModel -AsJson | Out-String | ConvertFrom-Json)

            $latestRequestArtifact = Get-Content -Path (Get-TestExecutionSharedArtifactPath -FileName 'MIM_TOD_TASK_REQUEST.latest.json') -Raw | ConvertFrom-Json
            $stateAfter = Get-Content -Path $fixture.TodStatePath -Raw | ConvertFrom-Json
            $legacyTask = @($stateAfter.tasks | Where-Object { [string]$_.id -eq 'objective-14-task-79' } | Select-Object -First 1)
            $taskA = @($stateAfter.tasks | Where-Object { [string]$_.id -eq [string]$resultA.command_dispatch.task_id } | Select-Object -First 1)
            $taskB = @($stateAfter.tasks | Where-Object { [string]$_.id -eq [string]$resultB.command_dispatch.task_id } | Select-Object -First 1)

            [string]$resultA.command_dispatch.task_id | Should Not Be 'objective-14-task-79'
            [string]$resultB.command_dispatch.task_id | Should Not Be 'objective-14-task-79'
            [string]$resultA.command_dispatch.task_id | Should Not Be ([string]$resultB.command_dispatch.task_id)
            [string]$resultA.command_dispatch.objective_id | Should Be 'objective-tod-local-executor-binding'
            [string]$resultB.command_dispatch.objective_id | Should Be 'objective-tod-code-change-executor-binding'
            (@($resultA.command_dispatch.payload.activity_event_types) -contains 'task_created_from_chat') | Should Be $true
            (@($resultB.command_dispatch.payload.activity_event_types) -contains 'task_created_from_chat') | Should Be $true
            [string]$resultA.reply_text | Should Match ([regex]::Escape("task_id: " + [string]$resultA.command_dispatch.task_id))
            [string]$resultB.reply_text | Should Match ([regex]::Escape("task_id: " + [string]$resultB.command_dispatch.task_id))
            [string]$latestRequestArtifact.task_id | Should Be ([string]$resultB.command_dispatch.task_id)
            [string]$latestRequestArtifact.request_id | Should Be ([string]$resultB.command_dispatch.request_id)
            [string]$latestRequestArtifact.objective_id | Should Be ([string]$resultB.command_dispatch.objective_id)
            [string]$resultA.command_dispatch.payload.superseded_claim.superseded_task_id | Should Be 'objective-14-task-79'
            [string]$resultB.command_dispatch.payload.superseded_claim.superseded_task_id | Should Be ([string]$resultA.command_dispatch.task_id)
            @($legacyTask).Count | Should Be 1
            [string]$legacyTask[0].status | Should Be 'superseded'
            @($taskA).Count | Should Be 1
            [string]$taskA[0].status | Should Be 'superseded'
            [string]$taskA[0].superseded_by_task_id | Should Be ([string]$resultB.command_dispatch.task_id)
            @($taskB).Count | Should Be 1
            [string]$taskB[0].status | Should Not Be 'superseded'
        }
        finally {
            Restore-ChatDispatchArtifacts -Records $artifactBackup
            if ($fixture -and (Test-Path -Path $fixture.Base)) {
                Remove-Item -Path $fixture.Base -Recurse -Force
            }
        }
    }

    It 'bypasses stale blocked state and materializes a fresh OBJECTIVE repair task' {
        (Test-Path -Path $scriptUnderTest) | Should Be $true

        $fixture = New-ConversationalReplyFixture
        $artifactBackup = Backup-ChatDispatchArtifacts
        try {
            Write-JsonNoBom -PathValue $fixture.BuildStatePath -Payload ([pscustomobject]@{
                objective_id = 'objective-14'
                status = 'blocked'
                task = 'TOD is blocked: waiting on scripts/engines/LocalExecutionEngine.ps1::Invoke-LocalExecutionEngine.'
                blocker = 'waiting on scripts/engines/LocalExecutionEngine.ps1::Invoke-LocalExecutionEngine'
            })
            Write-JsonNoBom -PathValue $fixture.ObjectivesPath -Payload ([pscustomobject]@{ objectives = @() })
            Write-JsonNoBom -PathValue $fixture.MaintenancePath -Payload ([pscustomobject]@{ overall_status = 'healthy'; overall_severity = 'info' })
            Write-JsonNoBom -PathValue $fixture.WatchdogPath -Payload ([pscustomobject]@{ state = 'healthy' })
            Write-JsonNoBom -PathValue $fixture.VoiceConfigPath -Payload ([pscustomobject]@{ enabled = $true })
            Write-ExecutionReadyTodConfig -Fixture $fixture
            Write-JsonNoBom -PathValue $fixture.TodStatePath -Payload ([pscustomobject]@{
                objectives = @(
                    [pscustomobject]@{ id = 'objective-14'; title = 'Legacy stale objective'; description = 'Legacy'; priority = 'high'; constraints = @(); success_criteria = @(); status = 'in_progress'; created_at = '2026-05-05T00:00:00Z'; updated_at = '2026-05-05T00:00:00Z' }
                )
                tasks = @(
                    [pscustomobject]@{ id = 'objective-14-task-79'; objective_id = 'objective-14'; title = 'Legacy LocalExecutionEngine blocker'; type = 'implementation'; task_category = 'chat_execution'; scope = 'TOD is blocked: waiting on scripts/engines/LocalExecutionEngine.ps1::Invoke-LocalExecutionEngine.'; dependencies = @(); acceptance_criteria = @('Legacy'); status = 'blocked'; assigned_executor = 'local'; source = 'bridge_runtime_sync'; created_at = '2026-05-05T00:00:00Z'; updated_at = '2026-05-05T00:00:00Z' }
                )
                execution_results = @()
                review_decisions = @()
                journal = @()
                engine_performance = [pscustomobject]@{ records = @(); updated_at = '' }
                routing_decisions = [pscustomobject]@{ records = @(); updated_at = '' }
                routing_feedback = [pscustomobject]@{ learned_weights = [pscustomobject]@{}; sample_size = 0; version = 'feedback_v1'; updated_at = '' }
                sync_state = [pscustomobject]@{ expected_contract_version = ''; expected_schema_version = ''; local_repo_signature = ''; cached_manifest = $null; last_comparison = $null; last_sync_decision = ''; last_sync_code = ''; compared_at = '' }
            })

            $query = 'OBJECTIVE: TOD-NEXT-SLICE-MATERIALIZATION'
            $result = (& $scriptUnderTest -Query $query -CurrentBuildStatePath $fixture.BuildStatePath -ObjectivesPath $fixture.ObjectivesPath -MaintenancePath $fixture.MaintenancePath -WatchdogPath $fixture.WatchdogPath -ProviderConfigPath $fixture.VoiceConfigPath -TodConfigPath $fixture.TodConfigPath -TodStatePath $fixture.TodStatePath -SkipModel -AsJson | Out-String | ConvertFrom-Json)
            $eventTypes = @($result.command_dispatch.payload.activity_event_types | ForEach-Object { [string]$_ })
            $stateAfter = Get-Content -Path $fixture.TodStatePath -Raw | ConvertFrom-Json
            $freshTask = @($stateAfter.tasks | Where-Object { [string]$_.id -eq [string]$result.command_dispatch.task_id } | Select-Object -First 1)

            [bool]$result.command_dispatch.created | Should Be $true
            [string]$result.command_dispatch.task_id | Should Match '^TSKCHAT-'
            [string]$result.command_dispatch.task_id | Should Not Be 'objective-14-task-79'
            [string]$result.command_dispatch.objective_id | Should Be 'objective-tod-next-slice-materialization'
            [string]$result.command_dispatch.task_category | Should Be 'diagnostic_implementation_repair'
            ($eventTypes -contains 'blocked_state_bypass_applied') | Should Be $true
            ($eventTypes -contains 'fresh_repair_task_created') | Should Be $true
            ($eventTypes -contains 'repair_task_materialization_started') | Should Be $true
            ($eventTypes -contains 'stale_blocker_ignored_for_new_objective') | Should Be $true
            (@($result.command_dispatch.payload.reason_codes) -contains 'fresh_objective_materialized_from_blocked_state') | Should Be $true
            [string]$result.command_dispatch.payload.selected_task.task_id | Should Be ([string]$result.command_dispatch.task_id)
            [string]$result.command_dispatch.payload.claimed_task.task_id | Should Be ([string]$result.command_dispatch.task_id)
            [string]$result.reply_text | Should Match 'blocked_state_bypass_applied'
            [string]$result.reply_text | Should Not Be 'TOD is blocked: waiting on scripts/engines/LocalExecutionEngine.ps1::Invoke-LocalExecutionEngine.'
            @($freshTask).Count | Should Be 1
            [string]$freshTask[0].id | Should Be ([string]$result.command_dispatch.task_id)
        }
        finally {
            Restore-ChatDispatchArtifacts -Records $artifactBackup
            if ($fixture -and (Test-Path -Path $fixture.Base)) {
                Remove-Item -Path $fixture.Base -Recurse -Force
            }
        }
    }

    It 'bypasses stale blocked state for ADMIN ACTION and creates a fresh task id' {
        (Test-Path -Path $scriptUnderTest) | Should Be $true

        $fixture = New-ConversationalReplyFixture
        $artifactBackup = Backup-ChatDispatchArtifacts
        try {
            Write-JsonNoBom -PathValue $fixture.BuildStatePath -Payload ([pscustomobject]@{
                objective_id = 'objective-14'
                status = 'blocked'
                blocker = 'waiting on scripts/engines/LocalExecutionEngine.ps1::Invoke-LocalExecutionEngine'
            })
            Write-JsonNoBom -PathValue $fixture.ObjectivesPath -Payload ([pscustomobject]@{ objectives = @() })
            Write-JsonNoBom -PathValue $fixture.MaintenancePath -Payload ([pscustomobject]@{ overall_status = 'healthy'; overall_severity = 'info' })
            Write-JsonNoBom -PathValue $fixture.WatchdogPath -Payload ([pscustomobject]@{ state = 'healthy' })
            Write-JsonNoBom -PathValue $fixture.VoiceConfigPath -Payload ([pscustomobject]@{ enabled = $true })
            Write-ExecutionReadyTodConfig -Fixture $fixture
            Write-JsonNoBom -PathValue $fixture.TodStatePath -Payload ([pscustomobject]@{
                objectives = @()
                tasks = @([pscustomobject]@{ id = 'objective-14-task-79'; objective_id = 'objective-14'; title = 'Legacy blocker'; type = 'implementation'; task_category = 'chat_execution'; scope = 'LocalExecutionEngine blocker'; dependencies = @(); acceptance_criteria = @('Legacy'); status = 'blocked'; assigned_executor = 'local'; created_at = '2026-05-05T00:00:00Z'; updated_at = '2026-05-05T00:00:00Z' })
                execution_results = @()
                review_decisions = @()
                journal = @()
                engine_performance = [pscustomobject]@{ records = @(); updated_at = '' }
                routing_decisions = [pscustomobject]@{ records = @(); updated_at = '' }
                routing_feedback = [pscustomobject]@{ learned_weights = [pscustomobject]@{}; sample_size = 0; version = 'feedback_v1'; updated_at = '' }
                sync_state = [pscustomobject]@{ expected_contract_version = ''; expected_schema_version = ''; local_repo_signature = ''; cached_manifest = $null; last_comparison = $null; last_sync_decision = ''; last_sync_code = ''; compared_at = '' }
            })

            $result = (& $scriptUnderTest -Query 'ADMIN ACTION: create a fresh direct-chat repair task for the blocked loop' -CurrentBuildStatePath $fixture.BuildStatePath -ObjectivesPath $fixture.ObjectivesPath -MaintenancePath $fixture.MaintenancePath -WatchdogPath $fixture.WatchdogPath -ProviderConfigPath $fixture.VoiceConfigPath -TodConfigPath $fixture.TodConfigPath -TodStatePath $fixture.TodStatePath -SkipModel -AsJson | Out-String | ConvertFrom-Json)
            $eventTypes = @($result.command_dispatch.payload.activity_event_types | ForEach-Object { [string]$_ })

            [string]$result.intent.intent | Should Be 'COMMAND'
            [bool]$result.command_dispatch.created | Should Be $true
            [string]$result.command_dispatch.task_id | Should Match '^TSKCHAT-'
            [string]$result.command_dispatch.task_id | Should Not Be 'objective-14-task-79'
            ($eventTypes -contains 'blocked_state_bypass_applied') | Should Be $true
            [string]$result.reply_text | Should Not Be 'TOD is blocked: waiting on scripts/engines/LocalExecutionEngine.ps1::Invoke-LocalExecutionEngine.'
        }
        finally {
            Restore-ChatDispatchArtifacts -Records $artifactBackup
            if ($fixture -and (Test-Path -Path $fixture.Base)) {
                Remove-Item -Path $fixture.Base -Recurse -Force
            }
        }
    }

    It 'routes bounded direct-chat code changes through LocalExecutionEngine and reports local activity events' {
        (Test-Path -Path $scriptUnderTest) | Should Be $true

        $fixture = New-ConversationalReplyFixture
        $artifactBackup = Backup-ChatDispatchArtifacts
        $relativePath = ('scripts/chat-local-dispatch-{0}.ps1' -f [guid]::NewGuid().ToString('N'))
        $absolutePath = Join-Path $repoRoot ($relativePath -replace '/', '\')
        try {
            Write-JsonNoBom -PathValue $fixture.BuildStatePath -Payload ([pscustomobject]@{
                status = 'active'
                task = 'Direct chat local execution dispatch'
            })
            Write-JsonNoBom -PathValue $fixture.ObjectivesPath -Payload ([pscustomobject]@{
                objectives = @()
            })
            Write-JsonNoBom -PathValue $fixture.MaintenancePath -Payload ([pscustomobject]@{
                overall_status = 'healthy'
                overall_severity = 'info'
            })
            Write-JsonNoBom -PathValue $fixture.WatchdogPath -Payload ([pscustomobject]@{
                state = 'healthy'
            })
            Write-JsonNoBom -PathValue $fixture.VoiceConfigPath -Payload ([pscustomobject]@{
                enabled = $true
            })
            Write-ExecutionReadyTodConfig -Fixture $fixture
            Write-JsonNoBom -PathValue $fixture.TodStatePath -Payload ([pscustomobject]@{
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

            [System.IO.File]::WriteAllText($absolutePath, "Write-Output 'OLD_SENTINEL'`n", (New-Object System.Text.UTF8Encoding($false)))

            $query = @"
OBJECTIVE: TOD-CHAT-LOCAL-EXECUTOR-DISPATCH
TASK: Patch bounded chat dispatch file
Update $relativePath.
Edit Mode: replace_text
Old Text: OLD_SENTINEL
New Text: NEW_SENTINEL
Validation Pattern: NEW_SENTINEL
STOP CONDITION: TOD direct chat routes the bounded task through LocalExecutionEngine and returns execution evidence.
"@

            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $result = (& $scriptUnderTest -Query $query -CurrentBuildStatePath $fixture.BuildStatePath -ObjectivesPath $fixture.ObjectivesPath -MaintenancePath $fixture.MaintenancePath -WatchdogPath $fixture.WatchdogPath -ProviderConfigPath $fixture.VoiceConfigPath -TodConfigPath $fixture.TodConfigPath -TodStatePath $fixture.TodStatePath -SkipModel -AsJson | Out-String | ConvertFrom-Json)
            $stopwatch.Stop()

            $eventTypes = @($result.command_dispatch.payload.activity_event_types | ForEach-Object { [string]$_ })
            $runTask = $result.command_dispatch.payload.run_task
            $backgroundApplied = $false
            $terminalTask = $null

            [bool]$result.ok | Should Be $true
            [string]$result.command_dispatch.task_category | Should Be 'code_change'
            [bool]$result.command_dispatch.codex_needed | Should Be $false
            [bool]$result.command_dispatch.accepted | Should Be $true
            [string]$result.command_dispatch.execution_status | Should Be 'queued'
            [string]$result.command_dispatch.activity_stream_url | Should Match ([regex]::Escape([string]$result.command_dispatch.task_id))
            (@($result.command_dispatch.payload.activity_event_types) -contains 'executor_classified') | Should Be $true
            [string]$result.command_dispatch.payload.executor_classification.selected_executor | Should Be 'local'
            [bool]$result.command_dispatch.payload.executor_classification.local_supported | Should Be $true
            [bool]$result.command_dispatch.payload.executor_classification.codex_allowed | Should Be $false
            [string]$runTask.engine_invocation.active_engine | Should Be 'local'
            [string]$runTask.decision | Should Be 'queued'
            [bool]$runTask.accepted | Should Be $true
            [bool]$runTask.engine_invocation.background_queued | Should Be $true
            [bool]$runTask.post_completion_tail_skipped | Should Be $true
            ($eventTypes -contains 'local_executor_invoked') | Should Be $true

            $backgroundApplied = Wait-ForFilePattern -Path $absolutePath -Pattern 'NEW_SENTINEL' -TimeoutSeconds 90
            $terminalTask = Wait-ForTaskTerminalState -StatePath $fixture.TodStatePath -TaskId ([string]$result.command_dispatch.task_id) -TimeoutSeconds 90

            [bool]$backgroundApplied | Should Be $true
            ([string](Get-Content -Path $absolutePath -Raw)) | Should Match 'NEW_SENTINEL'
            $null -ne $terminalTask | Should Be $true
            [string]$terminalTask.terminal_state.status | Should Be 'completed'
            [string]$terminalTask.terminal_state.event_type | Should Be 'local_executor_completed'
        }
        finally {
            Restore-ChatDispatchArtifacts -Records $artifactBackup
            if (Test-Path -Path $absolutePath) {
                Remove-Item -Path $absolutePath -Force
            }
            if ($fixture -and (Test-Path -Path $fixture.Base)) {
                Remove-Item -Path $fixture.Base -Recurse -Force
            }
        }
    }

    It 'persists a terminal bounded-edit blocker for abstract async direct-chat tasks' {
        (Test-Path -Path $scriptUnderTest) | Should Be $true

        $fixture = New-ConversationalReplyFixture
        $artifactBackup = Backup-ChatDispatchArtifacts
        try {
            Write-JsonNoBom -PathValue $fixture.BuildStatePath -Payload ([pscustomobject]@{ status = 'active'; task = 'Direct chat bounded-edit blocker' })
            Write-JsonNoBom -PathValue $fixture.ObjectivesPath -Payload ([pscustomobject]@{ objectives = @() })
            Write-JsonNoBom -PathValue $fixture.MaintenancePath -Payload ([pscustomobject]@{ overall_status = 'healthy'; overall_severity = 'info' })
            Write-JsonNoBom -PathValue $fixture.WatchdogPath -Payload ([pscustomobject]@{ state = 'healthy' })
            Write-JsonNoBom -PathValue $fixture.VoiceConfigPath -Payload ([pscustomobject]@{ enabled = $true })
            Write-ExecutionReadyTodConfig -Fixture $fixture
            Write-JsonNoBom -PathValue $fixture.TodStatePath -Payload ([pscustomobject]@{
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

            $query = @'
OBJECTIVE: TOD-ASYNC-BOUNDED-EDIT-BLOCKER
GOAL: Repair async direct chat execution for abstract implementation requests.
TASKS: Make queued tasks persist a readable terminal blocker instead of remaining queued forever.
ACCEPTANCE: An abstract async task reaches blocked_missing_bounded_edit_mode and surfaces through the activity stream.
'@

            $result = (& $scriptUnderTest -Query $query -CurrentBuildStatePath $fixture.BuildStatePath -ObjectivesPath $fixture.ObjectivesPath -MaintenancePath $fixture.MaintenancePath -WatchdogPath $fixture.WatchdogPath -ProviderConfigPath $fixture.VoiceConfigPath -TodConfigPath $fixture.TodConfigPath -TodStatePath $fixture.TodStatePath -SkipModel -AsJson | Out-String | ConvertFrom-Json)
            $terminalTask = Wait-ForTaskTerminalState -StatePath $fixture.TodStatePath -TaskId ([string]$result.command_dispatch.task_id) -TimeoutSeconds 90

            [bool]$result.ok | Should Be $true
            [string]$result.command_dispatch.execution_status | Should Be 'queued'
            $null -ne $terminalTask | Should Be $true
            [string]$terminalTask.terminal_state.status | Should Be 'blocked'
            [string]$terminalTask.terminal_state.event_type | Should Be 'bounded_edit_mode_missing'
            [string]$terminalTask.terminal_state.reason_code | Should Be 'blocked_missing_bounded_edit_mode'
        }
        finally {
            Restore-ChatDispatchArtifacts -Records $artifactBackup
            if ($fixture -and (Test-Path -Path $fixture.Base)) {
                Remove-Item -Path $fixture.Base -Recurse -Force
            }
        }
    }

    It 'persists a readable worker startup failure terminal state for async direct-chat tasks' {
        (Test-Path -Path $scriptUnderTest) | Should Be $true

        $fixture = New-ConversationalReplyFixture
        $artifactBackup = Backup-ChatDispatchArtifacts
        $env:TOD_FORCE_ASYNC_CHAT_WORKER_FAILURE = '1'
        try {
            Write-JsonNoBom -PathValue $fixture.BuildStatePath -Payload ([pscustomobject]@{ status = 'active'; task = 'Direct chat worker startup failure' })
            Write-JsonNoBom -PathValue $fixture.ObjectivesPath -Payload ([pscustomobject]@{ objectives = @() })
            Write-JsonNoBom -PathValue $fixture.MaintenancePath -Payload ([pscustomobject]@{ overall_status = 'healthy'; overall_severity = 'info' })
            Write-JsonNoBom -PathValue $fixture.WatchdogPath -Payload ([pscustomobject]@{ state = 'healthy' })
            Write-JsonNoBom -PathValue $fixture.VoiceConfigPath -Payload ([pscustomobject]@{ enabled = $true })
            Write-ExecutionReadyTodConfig -Fixture $fixture
            Write-JsonNoBom -PathValue $fixture.TodStatePath -Payload ([pscustomobject]@{
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

            $query = @'
OBJECTIVE: TOD-ASYNC-WORKER-STARTUP-FAILURE
TASK: Replace OLD_SENTINEL with NEW_SENTINEL in a bounded file and keep the task from hanging forever if the async worker crashes at startup.
Edit Mode: replace_text
Target File: scripts/Start-TOD-UI.ps1
Old Text: OLD_SENTINEL
New Text: NEW_SENTINEL
ACCEPTANCE: Persist a readable terminal blocker when async worker startup fails.
'@

            $result = (& $scriptUnderTest -Query $query -CurrentBuildStatePath $fixture.BuildStatePath -ObjectivesPath $fixture.ObjectivesPath -MaintenancePath $fixture.MaintenancePath -WatchdogPath $fixture.WatchdogPath -ProviderConfigPath $fixture.VoiceConfigPath -TodConfigPath $fixture.TodConfigPath -TodStatePath $fixture.TodStatePath -SkipModel -AsJson | Out-String | ConvertFrom-Json)
            $terminalTask = Wait-ForTaskTerminalState -StatePath $fixture.TodStatePath -TaskId ([string]$result.command_dispatch.task_id) -TimeoutSeconds 90

            [bool]$result.ok | Should Be $true
            [string]$result.command_dispatch.execution_status | Should Be 'queued'
            $null -ne $terminalTask | Should Be $true
            [string]$terminalTask.terminal_state.status | Should Be 'blocked'
            [string]$terminalTask.terminal_state.reason_code | Should Be 'worker_startup_failure'
            [string]$terminalTask.terminal_state.message | Should Match 'Async chat worker failed before TOD could persist a terminal result'
        }
        finally {
            $env:TOD_FORCE_ASYNC_CHAT_WORKER_FAILURE = $null
            Restore-ChatDispatchArtifacts -Records $artifactBackup
            if ($fixture -and (Test-Path -Path $fixture.Base)) {
                Remove-Item -Path $fixture.Base -Recurse -Force
            }
        }
    }

    It 'keeps bounded validation-only direct-chat objectives local-first without codex fallback' {
        (Test-Path -Path $scriptUnderTest) | Should Be $true

        $fixture = New-ConversationalReplyFixture
        $artifactBackup = Backup-ChatDispatchArtifacts
        try {
            Write-JsonNoBom -PathValue $fixture.BuildStatePath -Payload ([pscustomobject]@{
                status = 'active'
                task = 'Direct chat validation dispatch'
            })
            Write-JsonNoBom -PathValue $fixture.ObjectivesPath -Payload ([pscustomobject]@{
                objectives = @()
            })
            Write-JsonNoBom -PathValue $fixture.MaintenancePath -Payload ([pscustomobject]@{
                overall_status = 'healthy'
                overall_severity = 'info'
            })
            Write-JsonNoBom -PathValue $fixture.WatchdogPath -Payload ([pscustomobject]@{
                state = 'healthy'
            })
            Write-JsonNoBom -PathValue $fixture.VoiceConfigPath -Payload ([pscustomobject]@{
                enabled = $true
            })
            Write-ExecutionReadyTodConfig -Fixture $fixture
            Write-JsonNoBom -PathValue $fixture.TodStatePath -Payload ([pscustomobject]@{
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

            $query = @'
OBJECTIVE: TOD-LOCAL-FIRST-SMOKE
TASK: Inspect scripts/TOD.ps1 and publish validation only. Do not call Codex.
ACCEPTANCE: Route locally first, record executor classification, and return the bounded validation result without Codex fallback.
'@

            $result = (& $scriptUnderTest -Query $query -CurrentBuildStatePath $fixture.BuildStatePath -ObjectivesPath $fixture.ObjectivesPath -MaintenancePath $fixture.MaintenancePath -WatchdogPath $fixture.WatchdogPath -ProviderConfigPath $fixture.VoiceConfigPath -TodConfigPath $fixture.TodConfigPath -TodStatePath $fixture.TodStatePath -SkipModel -AsJson | Out-String | ConvertFrom-Json)

            $eventTypes = @($result.command_dispatch.payload.activity_event_types | ForEach-Object { [string]$_ })
            $runTask = $result.command_dispatch.payload.run_task
            $attemptedEngines = @($runTask.engine_invocation.attempted_engines | ForEach-Object { [string]$_ })

            [bool]$result.ok | Should Be $true
            [string]$result.command_dispatch.task_category | Should Be 'validation'
            [bool]$result.command_dispatch.codex_needed | Should Be $false
            [string]$result.command_dispatch.payload.executor_classification.selected_executor | Should Be 'local'
            [bool]$result.command_dispatch.payload.executor_classification.local_supported | Should Be $true
            [bool]$result.command_dispatch.payload.executor_classification.codex_allowed | Should Be $false
            ($eventTypes -contains 'executor_classified') | Should Be $true
            [string]$runTask.engine_invocation.active_engine | Should Be 'local'
            [int]@($attemptedEngines).Count | Should Be 1
            [string]$attemptedEngines[0] | Should Be 'local'
        }
        finally {
            Restore-ChatDispatchArtifacts -Records $artifactBackup
            if ($fixture -and (Test-Path -Path $fixture.Base)) {
                Remove-Item -Path $fixture.Base -Recurse -Force
            }
        }
    }

    It 'prefers canonical objective truth over stale durable memory during fallback' {
        (Test-Path -Path $scriptUnderTest) | Should Be $true

        $fixture = New-ConversationalReplyFixture
        try {
            Write-JsonNoBom -PathValue $fixture.BuildStatePath -Payload ([pscustomobject]@{
                status = 'active'
                task = ''
                objective_authority_reset = [pscustomobject]@{
                    authoritative_current_objective = '152'
                    invalidated_objectives = @('170')
                }
            })
            Write-JsonNoBom -PathValue $fixture.IntegrationStatusPath -Payload ([pscustomobject]@{
                live_task_request = [pscustomobject]@{
                    available = $true
                    objective_id = 'objective-152'
                    normalized_objective_id = '152'
                    task_id = 'objective-152-task-mim-arm-safe-home-20260408160030'
                    request_id = 'objective-152-task-mim-arm-safe-home-20260408160030'
                }
                objective_alignment = [pscustomobject]@{
                    tod_current_objective = '152'
                    mim_objective_active = '152'
                }
                bridge_canonical_evidence = [pscustomobject]@{
                    status = 'pass'
                }
                objective_authority_reset = [pscustomobject]@{
                    authoritative_current_objective = '152'
                    invalidated_objectives = @('170')
                }
            })
            Write-JsonNoBom -PathValue $fixture.ObjectivesPath -Payload ([pscustomobject]@{
                objectives = @(
                    [pscustomobject]@{ objective_id = '152'; title = 'Canonical objective' }
                )
            })
            Write-JsonNoBom -PathValue $fixture.MaintenancePath -Payload ([pscustomobject]@{
                overall_status = 'healthy'
                overall_severity = 'info'
            })
            Write-JsonNoBom -PathValue $fixture.WatchdogPath -Payload ([pscustomobject]@{
                state = 'error'
            })
            Write-JsonNoBom -PathValue $fixture.VoiceConfigPath -Payload ([pscustomobject]@{
                enabled = $true
            })
            Write-JsonNoBom -PathValue $fixture.CommitmentPath -Payload ([pscustomobject]@{
                objective_id = '170'
                state = 'abandoned'
                action_label = 'Refresh Governance Snapshot'
                summary = 'Operator abandoned the commitment for Refresh Governance Snapshot.'
                reasoning_bundle_id = 'bundle-170'
            })
            Write-JsonNoBom -PathValue $fixture.ReasoningPath -Payload ([pscustomobject]@{
                reasoning_bundle_id = 'bundle-170'
                operator_summary = 'Stale reasoning is still centered on objective 170.'
                recommended_next_step = 'refresh-governance-snapshot'
                evidence_count = 8
                evidence_flags = @('objective_170_stale')
            })
            Write-JsonNoBom -PathValue $fixture.ActionAuditPath -Payload ([pscustomobject]@{
                audit_id = 'audit-152'
                action_label = 'Refresh State Bus'
                outcome_status = 'invalid_request'
                proposal_id = 'objective-152-task-mim-arm-safe-home-20260408160030'
                proposal_title = 'Execute bounded safe home via TOD'
                evidence_flags = @('canonical_live_task')
            })

            $result = (& $scriptUnderTest -Query 'This is an implementation request. Add a stale_loop_detected artifact that triggers when the same bounded fallback intent repeats twice within 10 minutes.' -CurrentBuildStatePath $fixture.BuildStatePath -IntegrationStatusPath $fixture.IntegrationStatusPath -ObjectivesPath $fixture.ObjectivesPath -MaintenancePath $fixture.MaintenancePath -WatchdogPath $fixture.WatchdogPath -CommitmentPath $fixture.CommitmentPath -ReasoningPath $fixture.ReasoningPath -ActionAuditPath $fixture.ActionAuditPath -ProviderConfigPath $fixture.VoiceConfigPath -SkipModel -AsJson | Out-String | ConvertFrom-Json)

            [bool]$result.ok | Should Be $true
            [string]$result.current_work.objective_id | Should Be '152'
            [string]$result.initiative.objective_id | Should Be '152'
            [string]$result.current_work.active_task | Should Be 'Execute bounded safe home via TOD'
            [string]$result.initiative.active_task | Should Be 'Execute bounded safe home via TOD'
            [string]$result.reply_text | Should Match 'objective 152'
            [string]$result.reply_text | Should Match 'Execute bounded safe home via TOD'
            [string]$result.reply_text | Should Match 'stale'
            [string]$result.reply_text | Should Not Match 'under objective 170'
            [string]$result.reply_text | Should Not Match 'Refresh Governance Snapshot'
        }
        finally {
            if ($fixture -and (Test-Path -Path $fixture.Base)) {
                Remove-Item -Path $fixture.Base -Recurse -Force
            }
        }
    }

    It 'answers status requests from live listener runtime truth' {
        (Test-Path -Path $scriptUnderTest) | Should Be $true

        $fixture = New-ConversationalReplyFixture
        try {
            Write-JsonNoBom -PathValue $fixture.BuildStatePath -Payload ([pscustomobject]@{
                status = 'active'
                task = 'Bridge execution'
            })
            Write-JsonNoBom -PathValue $fixture.IntegrationStatusPath -Payload ([pscustomobject]@{
                bridge_canonical_evidence = [pscustomobject]@{
                    status = 'pass'
                }
                objective_authority_reset = [pscustomobject]@{
                    authoritative_current_objective = '205'
                }
            })
            Write-JsonNoBom -PathValue $fixture.ObjectivesPath -Payload ([pscustomobject]@{
                objectives = @(
                    [pscustomobject]@{ objective_id = '205'; title = 'MIM-first runtime truth' }
                )
            })
            Write-JsonNoBom -PathValue $fixture.MaintenancePath -Payload ([pscustomobject]@{
                overall_status = 'healthy'
                overall_severity = 'info'
            })
            Write-JsonNoBom -PathValue $fixture.WatchdogPath -Payload ([pscustomobject]@{
                state = 'healthy'
            })
            Write-JsonNoBom -PathValue $fixture.VoiceConfigPath -Payload ([pscustomobject]@{
                enabled = $true
            })
            Write-JsonNoBom -PathValue $fixture.ListenerRequestPath -Payload ([pscustomobject]@{
                request_id = 'objective-205-task-safe-001'
                task_id = 'objective-205-task-safe-001'
                objective_id = 'objective-205'
            })
            Write-JsonNoBom -PathValue $fixture.ListenerResultPath -Payload ([pscustomobject]@{
                request_id = 'objective-205-task-safe-001'
                objective_id = 'objective-205'
                status = 'succeeded'
                action = 'bridge_runtime_sync'
            })
            Write-JsonNoBom -PathValue $fixture.ListenerCommandStatusPath -Payload ([pscustomobject]@{
                request_id = 'objective-205-task-safe-001'
                status = 'succeeded'
                detail = 'Task RESULT emitted to shared path.'
            })
            Write-JsonNoBom -PathValue $fixture.ListenerDecisionPath -Payload ([pscustomobject]@{
                request_id = 'objective-205-task-safe-001'
                requested_objective_id = '205'
                decision_outcome = 'execute'
                summary = 'Request is aligned with authority and ready for immediate TOD execution.'
                next_step_recommendation = 'continue_bounded_execution'
                blocker_classification = ''
            })

            $result = (& $scriptUnderTest -Query 'status update' -CurrentBuildStatePath $fixture.BuildStatePath -IntegrationStatusPath $fixture.IntegrationStatusPath -ObjectivesPath $fixture.ObjectivesPath -MaintenancePath $fixture.MaintenancePath -WatchdogPath $fixture.WatchdogPath -ProviderConfigPath $fixture.VoiceConfigPath -ListenerRequestPath $fixture.ListenerRequestPath -ListenerResultPath $fixture.ListenerResultPath -ListenerCommandStatusPath $fixture.ListenerCommandStatusPath -ListenerDecisionPath $fixture.ListenerDecisionPath -SkipModel -AsJson | Out-String | ConvertFrom-Json)

            [bool]$result.ok | Should Be $true
            [bool]$result.listener_runtime.available | Should Be $true
            [string]$result.listener_runtime.active_request_id | Should Be 'objective-205-task-safe-001'
            [string]$result.listener_runtime.last_completed_action | Should Be 'bridge_runtime_sync'
            [string]$result.reply_text | Should Match 'objective-205-task-safe-001'
            [string]$result.reply_text | Should Match 'bridge status is succeeded'
            [string]$result.reply_text | Should Match 'last completed action is bridge_runtime_sync'
        }
        finally {
            if ($fixture -and (Test-Path -Path $fixture.Base)) {
                Remove-Item -Path $fixture.Base -Recurse -Force
            }
        }
    }
}
