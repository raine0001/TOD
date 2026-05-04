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
            [string]$result.reply_text | Should Match 'Last completed action: bridge_runtime_sync'
        }
        finally {
            if ($fixture -and (Test-Path -Path $fixture.Base)) {
                Remove-Item -Path $fixture.Base -Recurse -Force
            }
        }
    }
}