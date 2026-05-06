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
    }
}

function Backup-ChatDispatchArtifacts {
    $paths = @(
        (Join-Path $repoRoot 'runtime/shared/MIM_TOD_TASK_REQUEST.latest.json'),
        (Join-Path $repoRoot 'runtime/shared/TOD_ACTIVITY_STREAM.latest.json'),
        (Join-Path $repoRoot 'tmp_remote_mim/runtime/shared/MIM_TOD_TASK_REQUEST.latest.json'),
        (Join-Path $repoRoot 'tmp_remote_mim/runtime/shared/TOD_ACTIVITY_STREAM.latest.json'),
        (Join-Path $repoRoot 'tod/out/context-sync/listener/MIM_TOD_TASK_REQUEST.latest.json')
    )

    $records = @()
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

Describe 'TOD conversational reply' {
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

            $requestArtifactPath = Join-Path $repoRoot 'runtime/shared/MIM_TOD_TASK_REQUEST.latest.json'
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

            Write-JsonNoBom -PathValue (Join-Path $repoRoot 'runtime/shared/MIM_TOD_TASK_REQUEST.latest.json') -Payload $staleRequest
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

            $latestRequestArtifact = Get-Content -Path (Join-Path $repoRoot 'runtime/shared/MIM_TOD_TASK_REQUEST.latest.json') -Raw | ConvertFrom-Json
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
            Write-JsonNoBom -PathValue $fixture.TodConfigPath -Payload ([pscustomobject]@{
                mode = 'local'
                fallback_to_local = $true
                timeout_seconds = 30
                engineering_loop = [pscustomobject]@{
                    max_run_history = 150
                    max_scorecard_history = 150
                    max_cycle_records = 300
                }
                execution_engine = [pscustomobject]@{
                    active = 'codex'
                    fallback = 'local'
                    allow_fallback = $true
                }
            })
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

            $result = (& $scriptUnderTest -Query $query -CurrentBuildStatePath $fixture.BuildStatePath -ObjectivesPath $fixture.ObjectivesPath -MaintenancePath $fixture.MaintenancePath -WatchdogPath $fixture.WatchdogPath -ProviderConfigPath $fixture.VoiceConfigPath -TodConfigPath $fixture.TodConfigPath -TodStatePath $fixture.TodStatePath -SkipModel -AsJson | Out-String | ConvertFrom-Json)

            $eventTypes = @($result.command_dispatch.payload.activity_event_types | ForEach-Object { [string]$_ })
            $runTask = $result.command_dispatch.payload.run_task

            [bool]$result.ok | Should Be $true
            [string]$result.command_dispatch.task_category | Should Be 'code_change'
            [bool]$result.command_dispatch.codex_needed | Should Be $false
            [string]$runTask.engine_invocation.active_engine | Should Be 'local'
            [string]$runTask.decision | Should Be 'pass'
            [bool]$runTask.post_completion_tail_skipped | Should Be $true
            [bool]$runTask.engine_invocation.result.no_change_required | Should Be $false
            ($eventTypes -contains 'local_executor_invoked') | Should Be $true
            ($eventTypes -contains 'local_executor_completed') | Should Be $true
            ($eventTypes -contains 'result_published') | Should Be $true
            [string]@($runTask.engine_invocation.result.files_changed)[0] | Should Be $relativePath
            [string]$runTask.engine_invocation.result.diff_summary | Should Match 'Replaced bounded text'
            ([string](Get-Content -Path $absolutePath -Raw)) | Should Match 'NEW_SENTINEL'
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