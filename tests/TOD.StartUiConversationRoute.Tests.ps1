Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$uiScript = Join-Path $repoRoot 'scripts/Start-TOD-UI.ps1'

function Import-UiRouteFunction {
    param([Parameter(Mandatory = $true)][string]$Name)

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($uiScript, [ref]$tokens, [ref]$errors)
    if (@($errors).Count -gt 0) {
        throw "Failed to parse $uiScript"
    }

    $fnAst = $ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name
    }, $true)

    if ($null -eq $fnAst) {
        throw "Function '$Name' not found in $uiScript"
    }

    $definition = $fnAst.Extent.Text -replace ("function\s+{0}\b" -f [regex]::Escape($Name)), ("function global:{0}" -f $Name)
    . ([scriptblock]::Create($definition))
}

Describe 'TOD UI conversation route backend' {
    BeforeAll {
        Import-UiRouteFunction -Name 'Get-TodConversationDirectiveValue'
        Import-UiRouteFunction -Name 'Convert-ToTodConversationSlug'
        Import-UiRouteFunction -Name 'New-TodConversationDispatchId'
        Import-UiRouteFunction -Name 'Resolve-TodConversationTaskCategory'
        Import-UiRouteFunction -Name 'Resolve-TodConversationPrimaryTargetFile'
        Import-UiRouteFunction -Name 'Start-TodConversationAsyncProcess'
        Import-UiRouteFunction -Name 'Invoke-TodUiActionJson'
        Import-UiRouteFunction -Name 'Try-StartAsyncTodConversationDispatch'
        Import-UiRouteFunction -Name 'Invoke-TodConversationReplyRequest'
        Import-UiRouteFunction -Name 'Read-JsonFileIfExists'
        Import-UiRouteFunction -Name 'Write-JsonArtifact'
        Import-UiRouteFunction -Name 'Get-ActivityTimestampText'
        Import-UiRouteFunction -Name 'Get-ActivityTimestampTicks'
        Import-UiRouteFunction -Name 'Test-IsTerminalActivityStatus'
        Import-UiRouteFunction -Name 'Get-ActivityCandidateTerminalRank'
        Import-UiRouteFunction -Name 'Get-FilteredActivityEvents'
        Import-UiRouteFunction -Name 'New-ActivityStreamCandidatePayload'
        Import-UiRouteFunction -Name 'Get-StateActivityFallbackPayload'
        Import-UiRouteFunction -Name 'Update-DirectChatActivityStream'
        Import-UiRouteFunction -Name 'Get-ActivityStreamPayload'
        Import-UiRouteFunction -Name 'Finalize-TodConversationReplyPayload'
    }

    It 'requires a non-empty query' {
        { Invoke-TodConversationReplyRequest -Query '' } | Should Throw 'query is required'
    }

    It 'parses JSON returned by the conversation reply script' {
        $script:conversationReplyScript = Join-Path $repoRoot ('tod/out/tests/fake-conversation-' + [guid]::NewGuid().ToString('N') + '.ps1')
        @'
param(
    [string]$Query,
    [string]$ObjectiveId,
    [string]$OperatorName,
    [string]$ConversationHistoryJson,
    [int]$WindowMinutes,
    [switch]$AsJson
)

[pscustomobject]@{
    ok = $true
    reply_text = "reply for $Query"
    source = 'test'
    operator = [pscustomobject]@{ operator_name = $OperatorName; turn_count = 2 }
    initiative = [pscustomobject]@{ objective_id = '152'; active_task = 'simulate'; next_action = 'continue' ; blocker = '' }
    current_work = [pscustomobject]@{ objective_id = '152'; active_task = 'simulate'; next_action = 'continue'; blocker = '' }
    conversation_memory = [pscustomobject]@{ turn_count = 2 }
} | ConvertTo-Json -Depth 10
'@ | Set-Content -Path $script:conversationReplyScript

        $payload = Invoke-TodConversationReplyRequest -Query 'what now' -OperatorName 'Dave' -ConversationHistoryJson '[]' -WindowMinutes 10

        [bool]$payload.ok | Should Be $true
        [string]$payload.reply_text | Should Be 'reply for what now'
        [string]$payload.operator.operator_name | Should Be 'Dave'
    }

    It 'queues structured TOD command requests immediately for background execution' {
        $script:configPath = Join-Path $repoRoot 'tod/config/tod-config.json'
        $script:statePath = Join-Path $repoRoot 'tod/data/state.json'
        $script:directChatActivityStreamPath = Join-Path $repoRoot ('tod/out/tests/ui-direct-chat-fast-ack-' + [guid]::NewGuid().ToString('N') + '.json')
        $script:activityStreamPrimaryPath = Join-Path $repoRoot ('tod/out/tests/ui-direct-chat-fast-ack-primary-' + [guid]::NewGuid().ToString('N') + '.json')
        $script:activityStreamMirrorPath = Join-Path $repoRoot ('tod/out/tests/ui-direct-chat-fast-ack-mirror-' + [guid]::NewGuid().ToString('N') + '.json')
        $script:todActivityStreamBuildId = 'fresh-direct-chat-activity-v1'
        $script:todScript = Join-Path $repoRoot ('tod/out/tests/fake-tod-' + [guid]::NewGuid().ToString('N') + '.ps1')

        @'
param(
    [string]$Action,
    [string]$TaskId,
    [string]$RequestId,
    [string]$ObjectiveId
)
[pscustomobject]@{
    ok = $true
    objective_id = $ObjectiveId
    task_id = $TaskId
    request_id = $RequestId
    activity_event_types = @('chat_task_created', 'task_claimed', 'execution_started', 'execution_queued')
    request_artifact_path = ''
    run_task = [pscustomobject]@{
        task_id = $TaskId
        decision = 'queued'
        accepted = $true
        blocked = $false
        execution_status = 'queued'
        summary = 'Task accepted and queued for background execution.'
        post_completion_tail_skipped = $true
        engine_invocation = [pscustomobject]@{
            active_engine = 'local'
            attempted_engines = @('local')
            background_queued = $true
            process_id = 4242
            stdout_path = 'stdout.log'
            stderr_path = 'stderr.log'
            launched_at = '2026-05-06T11:00:00Z'
        }
    }
} | ConvertTo-Json -Depth 10
'@ | Set-Content -Path $script:todScript

        try {
            $query = @'
OBJECTIVE: TOD-CONVERSATION-ASYNC-TASK-DISPATCH
GOAL: Make /api/tod-conversation return quickly after creating a task.
TASKS: Split direct-chat handling into request/ack path and background execution path.
ACCEPTANCE: Return task_id and queued state immediately.
'@

            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $replyPayload = Try-StartAsyncTodConversationDispatch -Query $query -ObjectiveId ''
            $stopwatch.Stop()
            $finalReply = Finalize-TodConversationReplyPayload -ReplyPayload $replyPayload

            [double]$stopwatch.Elapsed.TotalSeconds | Should BeLessThan 2
            [bool]$finalReply.accepted | Should Be $true
            [string]$finalReply.execution_status | Should Be 'queued'
            [string]$finalReply.task_id | Should Match '^TSKCHAT-'
            [string]$finalReply.activity_stream_url | Should Match ([regex]::Escape([string]$finalReply.task_id))
            [string]$finalReply.command_dispatch.payload.run_task.decision | Should Be 'queued'
            [bool]$finalReply.command_dispatch.payload.run_task.engine_invocation.background_queued | Should Be $true
            (@($finalReply.activity_stream.events | ForEach-Object { [string]$_.event_type }) -contains 'chat_task_created') | Should Be $true
            (@($finalReply.activity_stream.events | ForEach-Object { [string]$_.event_type }) -contains 'local_executor_invoked') | Should Be $true
            (@($finalReply.activity_stream.events | ForEach-Object { [string]$_.event_type }) -contains 'execution_queued') | Should Be $true
            (@($finalReply.activity_stream.events | ForEach-Object { [string]$_.event_type }) -contains 'validation_failed') | Should Be $false
            (@($finalReply.activity_stream.events | ForEach-Object { [string]$_.event_type }) -contains 'result_published') | Should Be $false
            [string]$finalReply.activity_stream.status | Should Be 'queued'
        }
        finally {
            foreach ($path in @($script:todScript, $script:directChatActivityStreamPath, $script:activityStreamPrimaryPath, $script:activityStreamMirrorPath)) {
                if ($path -and (Test-Path -Path $path)) {
                    Remove-Item -Path $path -Force
                }
            }
        }
    }

    It 'maps route-oriented objectives to the TOD UI script as the bounded target file' {
        $query = @'
OBJECTIVE: TOD-CONVERSATION-ASYNC-TASK-DISPATCH
GOAL: Make /api/tod-conversation return quickly after creating a task while progress appears through /api/activity-stream.
'@

        $targetFile = Resolve-TodConversationPrimaryTargetFile -QueryText $query

        [string]$targetFile | Should Be 'scripts/Start-TOD-UI.ps1'
    }

    It 'prefers a terminal state fallback over a stale queued direct-chat head for async blocker tasks' {
        $artifactRoot = Join-Path $repoRoot ('tod/out/tests/ui-direct-chat-async-terminal-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null

        try {
            $script:directChatActivityStreamPath = Join-Path $artifactRoot 'tod_direct_chat_activity_stream.latest.json'
            $script:activityStreamPrimaryPath = Join-Path $artifactRoot 'TOD_ACTIVITY_STREAM.latest.json'
            $script:activityStreamMirrorPath = Join-Path $artifactRoot 'TOD_ACTIVITY_STREAM.mirror.latest.json'
            $script:statePath = Join-Path $artifactRoot 'tod-state.json'
            $script:todActivityStreamBuildId = 'fresh-direct-chat-activity-v1'
            $script:maxStateReadBytes = 5MB

            $replyPayload = [pscustomobject]@{
                generated_at = '2026-05-06T11:00:00Z'
                command_dispatch = [pscustomobject]@{
                    created = $true
                    accepted = $true
                    execution_status = 'queued'
                    task_id = 'TSKCHAT-ASYNC-BLOCKED'
                    objective_id = 'objective-async-terminal'
                    request_id = 'REQ-ASYNC-BLOCKED'
                    correlation_id = 'CORR-ASYNC-BLOCKED'
                    title = 'Async abstract direct-chat blocker'
                    task_category = 'code_change'
                    detail = 'executor local'
                    payload = [pscustomobject]@{
                        activity_event_types = @('chat_task_created', 'executor_classified', 'local_executor_invoked', 'execution_queued')
                        executor_classification = [pscustomobject]@{
                            selected_executor = 'local'
                            classification_reason = 'structured_direct_chat_async_dispatch'
                            local_supported = $true
                            codex_allowed = $false
                        }
                        run_task = [pscustomobject]@{
                            decision = 'queued'
                            accepted = $true
                            blocked = $false
                            execution_status = 'queued'
                            summary = 'Task accepted and queued for background execution.'
                        }
                    }
                }
            }

            Update-DirectChatActivityStream -ReplyPayload $replyPayload | Out-Null
            $directPayload = Read-JsonFileIfExists -Path $script:directChatActivityStreamPath

            Write-JsonArtifact -Path $script:statePath -Payload ([pscustomobject]@{
                tasks = @(
                    [pscustomobject]@{
                        id = 'TSKCHAT-ASYNC-BLOCKED'
                        objective_id = 'objective-async-terminal'
                        title = 'Async abstract direct-chat blocker'
                        status = 'in_progress'
                        assigned_executor = 'local'
                        task_category = 'code_change'
                        source = 'direct_chat'
                        scope = 'Implement the initiative core for /api/tod-conversation in scripts/Start-TOD-UI.ps1.'
                        created_at = '2026-05-06T11:00:00Z'
                        updated_at = '2026-05-06T11:00:05Z'
                        materialization = [pscustomobject]@{
                            status = 'blocked'
                            reason_code = 'blocked_missing_bounded_edit_mode'
                            required_clarification = @('edit_mode')
                        }
                    }
                )
            })

            $scoped = Get-ActivityStreamPayload -TaskId 'TSKCHAT-ASYNC-BLOCKED' -Limit 20
            $events = @($scoped.events | ForEach-Object { [string]$_.event_type })
            $directEvents = @($directPayload.events | ForEach-Object { [string]$_.event_type })

            [string]$scoped.source_path | Should Be $script:statePath
            [string]$scoped.status | Should Be 'blocked'
            [string]$scoped.event | Should Be 'bounded_edit_mode_missing'
            ($directEvents -contains 'execution_queued') | Should Be $true
            ($events -contains 'bounded_edit_mode_missing') | Should Be $true
            [string]$scoped.latest_event.details.reason_code | Should Be 'blocked_missing_bounded_edit_mode'
        }
        finally {
            if (Test-Path -Path $artifactRoot) {
                Remove-Item -Path $artifactRoot -Recurse -Force
            }
        }
    }

    It 'returns scoped direct-chat activity with local completion and published result events' {
        $artifactRoot = Join-Path $repoRoot ('tod/out/tests/ui-direct-chat-activity-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null

        try {
            $script:directChatActivityStreamPath = Join-Path $artifactRoot 'tod_direct_chat_activity_stream.latest.json'
            $script:activityStreamPrimaryPath = Join-Path $artifactRoot 'TOD_ACTIVITY_STREAM.latest.json'
            $script:activityStreamMirrorPath = Join-Path $artifactRoot 'TOD_ACTIVITY_STREAM.mirror.latest.json'
            $script:statePath = Join-Path $artifactRoot 'tod-state.json'
            $script:todActivityStreamBuildId = 'fresh-direct-chat-activity-v1'

            $replyPayload = [pscustomobject]@{
                generated_at = '2026-05-05T23:30:00Z'
                command_dispatch = [pscustomobject]@{
                    created = $true
                    task_id = 'TSKCHAT-SMOKE-PASS'
                    objective_id = 'objective-direct-chat-smoke'
                    request_id = 'REQ-SMOKE-PASS'
                    correlation_id = 'CORR-SMOKE-PASS'
                    title = 'Run direct-chat local executor smoke task'
                    detail = 'executor local'
                    payload = [pscustomobject]@{
                        activity_event_types = @('executor_classified', 'local_executor_invoked', 'local_executor_completed', 'result_published')
                        executor_classification = [pscustomobject]@{
                            selected_executor = 'local'
                            classification_reason = 'validation_is_local_first'
                            local_supported = $true
                            codex_allowed = $false
                        }
                        run_task = [pscustomobject]@{
                            decision = 'pass'
                            summary = 'Local smoke task completed and published bounded result evidence.'
                        }
                    }
                }
            }

            Update-DirectChatActivityStream -ReplyPayload $replyPayload | Out-Null
            $scoped = Get-ActivityStreamPayload -TaskId 'TSKCHAT-SMOKE-PASS' -Limit 20
            $events = @($scoped.events | ForEach-Object { [string]$_.event_type })

            [string]$scoped.task_id | Should Be 'TSKCHAT-SMOKE-PASS'
            [string]$scoped.source_path | Should Be $script:directChatActivityStreamPath
            [string]$scoped.tod_activity_stream_build_id | Should Be 'fresh-direct-chat-activity-v1'
            ($events -contains 'chat_task_created') | Should Be $true
            ($events -contains 'executor_classified') | Should Be $true
            ($events -contains 'local_executor_invoked') | Should Be $true
            ($events -contains 'local_executor_completed') | Should Be $true
            ($events -contains 'validation_passed') | Should Be $true
            ($events -contains 'result_published') | Should Be $true

            $classificationEvent = @($scoped.events | Where-Object { [string]$_.event_type -eq 'executor_classified' } | Select-Object -Last 1)
            $classificationEvent = if (@($classificationEvent).Count -gt 0) { $classificationEvent[0] } else { $null }
            $null -ne $classificationEvent | Should Be $true
            [string]$classificationEvent.details.selected_executor | Should Be 'local'
            [bool]$classificationEvent.details.local_supported | Should Be $true
            [bool]$classificationEvent.details.codex_allowed | Should Be $false
        }
        finally {
            if (Test-Path -Path $artifactRoot) {
                Remove-Item -Path $artifactRoot -Recurse -Force
            }
        }
    }

    It 'preserves no_change_required end to end for idempotent direct-chat smoke reruns' {
        $artifactRoot = Join-Path $repoRoot ('tod/out/tests/ui-direct-chat-idempotent-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null

        try {
            $script:directChatActivityStreamPath = Join-Path $artifactRoot 'tod_direct_chat_activity_stream.latest.json'
            $script:activityStreamPrimaryPath = Join-Path $artifactRoot 'TOD_ACTIVITY_STREAM.latest.json'
            $script:activityStreamMirrorPath = Join-Path $artifactRoot 'TOD_ACTIVITY_STREAM.mirror.latest.json'
            $script:statePath = Join-Path $artifactRoot 'tod-state.json'
            $script:todActivityStreamBuildId = 'fresh-direct-chat-activity-v1'

            @'
{
  "tasks": [
    {
      "id": "TSKCHAT-SMOKE-NOOP",
      "objective_id": "objective-direct-chat-smoke",
      "title": "stale state fallback task",
      "status": "reviewed_pass",
      "assigned_executor": "local",
      "updated_at": "2026-05-05T23:31:00Z"
    }
  ]
}
'@ | Set-Content -Path $script:statePath

            $replyPayload = [pscustomobject]@{
                generated_at = '2026-05-05T23:32:00Z'
                command_dispatch = [pscustomobject]@{
                    created = $true
                    task_id = 'TSKCHAT-SMOKE-NOOP'
                    objective_id = 'objective-direct-chat-smoke'
                    request_id = 'REQ-SMOKE-NOOP'
                    correlation_id = 'CORR-SMOKE-NOOP'
                    title = 'Re-run direct-chat local executor smoke task'
                    detail = 'executor local'
                    payload = [pscustomobject]@{
                        activity_event_types = @('local_executor_invoked', 'local_executor_completed', 'result_published')
                        run_task = [pscustomobject]@{
                            decision = 'pass'
                            summary = 'Local smoke rerun completed without applying a new change.'
                            engine_invocation = [pscustomobject]@{
                                active_engine = 'local'
                                result = [pscustomobject]@{
                                    files_changed = @()
                                    no_change_required = $true
                                }
                            }
                        }
                    }
                }
            }

            $finalReply = Finalize-TodConversationReplyPayload -ReplyPayload $replyPayload
            $replyEvents = @($finalReply.activity_stream.events | ForEach-Object { [string]$_.event_type })
            $replyCompletion = @($finalReply.activity_stream.events | Where-Object { [string]$_.event_type -eq 'local_executor_completed' } | Select-Object -Last 1)
            $replyCompletion = if (@($replyCompletion).Count -gt 0) { $replyCompletion[0] } else { $null }
            $scoped = Get-ActivityStreamPayload -TaskId 'TSKCHAT-SMOKE-NOOP' -Limit 20
            $scopedCompletion = @($scoped.events | Where-Object { [string]$_.event_type -eq 'local_executor_completed' } | Select-Object -Last 1)
            $scopedCompletion = if (@($scopedCompletion).Count -gt 0) { $scopedCompletion[0] } else { $null }

            [string]$finalReply.activity_stream.task_id | Should Be 'TSKCHAT-SMOKE-NOOP'
            [string]$finalReply.activity_stream.source_path | Should Be $script:directChatActivityStreamPath
            ($replyEvents -contains 'validation_passed') | Should Be $true
            ($replyEvents -contains 'result_published') | Should Be $true
            [bool]$finalReply.command_dispatch.payload.run_task.engine_invocation.result.no_change_required | Should Be $true
            $null -ne $replyCompletion | Should Be $true
            [bool]$replyCompletion.details.no_change_required | Should Be $true
            $null -ne $scopedCompletion | Should Be $true
            [string]$scoped.source_path | Should Be $script:directChatActivityStreamPath
            [bool]$scopedCompletion.details.no_change_required | Should Be $true
        }
        finally {
            if (Test-Path -Path $artifactRoot) {
                Remove-Item -Path $artifactRoot -Recurse -Force
            }
        }
    }

    It 'prefers the fresh direct-chat task stream over stale state fallback for a new OBJECTIVE prompt' {
        $artifactRoot = Join-Path $repoRoot ('tod/out/tests/ui-direct-chat-stale-bypass-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null

        try {
            $script:directChatActivityStreamPath = Join-Path $artifactRoot 'tod_direct_chat_activity_stream.latest.json'
            $script:activityStreamPrimaryPath = Join-Path $artifactRoot 'TOD_ACTIVITY_STREAM.latest.json'
            $script:activityStreamMirrorPath = Join-Path $artifactRoot 'TOD_ACTIVITY_STREAM.mirror.latest.json'
            $script:statePath = Join-Path $artifactRoot 'tod-state.json'
            $script:todActivityStreamBuildId = 'fresh-direct-chat-activity-v1'

            @'
{
  "tasks": [
    {
      "id": "objective-14-task-79",
      "objective_id": "objective-14",
      "title": "Legacy stale task",
      "status": "in_progress",
      "assigned_executor": "codex",
      "updated_at": "2026-05-05T00:00:00Z"
    },
    {
      "id": "TSKCHAT-FRESH-001",
      "objective_id": "objective-tod-direct-chat-stale-claim-bypass",
      "title": "Fresh direct chat task",
      "status": "blocked",
      "assigned_executor": "local",
      "updated_at": "2026-05-06T00:40:00Z"
    }
  ]
}
'@ | Set-Content -Path $script:statePath

            $replyPayload = [pscustomobject]@{
                generated_at = '2026-05-06T00:40:00Z'
                command_dispatch = [pscustomobject]@{
                    created = $true
                    task_id = 'TSKCHAT-FRESH-001'
                    objective_id = 'objective-tod-direct-chat-stale-claim-bypass'
                    request_id = 'REQ-FRESH-001'
                    correlation_id = 'CORR-FRESH-001'
                    title = 'Fresh direct chat task'
                    detail = 'executor local'
                    payload = [pscustomobject]@{
                        activity_event_types = @('local_executor_invoked', 'result_published')
                        run_task = [pscustomobject]@{
                            decision = 'blocked'
                            summary = 'Fresh direct chat task is now the visible task lane.'
                        }
                    }
                }
            }

            $finalReply = Finalize-TodConversationReplyPayload -ReplyPayload $replyPayload
            $scoped = Get-ActivityStreamPayload -TaskId 'TSKCHAT-FRESH-001' -Limit 20

            [string]$finalReply.activity_stream.task_id | Should Be 'TSKCHAT-FRESH-001'
            [string]$finalReply.activity_stream.source_path | Should Be $script:directChatActivityStreamPath
            [string]$scoped.task_id | Should Be 'TSKCHAT-FRESH-001'
            [string]$scoped.source_path | Should Be $script:directChatActivityStreamPath
            [string]$scoped.title | Should Be 'Fresh direct chat task'
            [string]$scoped.task_id | Should Not Be 'objective-14-task-79'
            (@($scoped.events | ForEach-Object { [string]$_.event_type }) -contains 'chat_task_created') | Should Be $true
        }
        finally {
            if (Test-Path -Path $artifactRoot) {
                Remove-Item -Path $artifactRoot -Recurse -Force
            }
        }
    }

    It 'prefers the fresh direct-chat task stream even when the requested objective id is stale' {
        $artifactRoot = Join-Path $repoRoot ('tod/out/tests/ui-direct-chat-stale-objective-override-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null

        try {
            $script:directChatActivityStreamPath = Join-Path $artifactRoot 'tod_direct_chat_activity_stream.latest.json'
            $script:activityStreamPrimaryPath = Join-Path $artifactRoot 'TOD_ACTIVITY_STREAM.latest.json'
            $script:activityStreamMirrorPath = Join-Path $artifactRoot 'TOD_ACTIVITY_STREAM.mirror.latest.json'
            $script:statePath = Join-Path $artifactRoot 'tod-state.json'
            $script:todActivityStreamBuildId = 'fresh-direct-chat-activity-v1'

            @'
{
  "tasks": [
    {
      "id": "objective-14-task-79",
      "objective_id": "objective-14",
      "title": "Legacy stale task",
      "status": "blocked",
      "assigned_executor": "local",
      "updated_at": "2026-05-06T00:58:00Z",
      "scope": "/home/testpilot/mim/core/tod_execution_loop.py"
    }
  ]
}
'@ | Set-Content -Path $script:statePath

            $replyPayload = [pscustomobject]@{
                generated_at = '2026-05-06T01:10:00Z'
                command_dispatch = [pscustomobject]@{
                    created = $true
                    task_id = 'TSKCHAT-FRESH-LOCAL-002'
                    objective_id = 'objective-tod-local-first-smoke'
                    request_id = 'REQ-FRESH-LOCAL-002'
                    correlation_id = 'CORR-FRESH-LOCAL-002'
                    title = 'Fresh local-first direct chat task'
                    detail = 'executor local'
                    payload = [pscustomobject]@{
                        activity_event_types = @('executor_classified', 'local_executor_invoked', 'result_published')
                        executor_classification = [pscustomobject]@{
                            selected_executor = 'local'
                            classification_reason = 'validation_is_local_first'
                            local_supported = $true
                            codex_allowed = $false
                        }
                        run_task = [pscustomobject]@{
                            decision = 'blocked'
                            summary = 'Fresh local-first direct chat task is the authoritative visible lane.'
                        }
                    }
                }
            }

            $null = Finalize-TodConversationReplyPayload -ReplyPayload $replyPayload
            $scoped = Get-ActivityStreamPayload -ObjectiveId 'objective-14' -Limit 20

            [string]$scoped.source_path | Should Be $script:directChatActivityStreamPath
            [string]$scoped.task_id | Should Be 'TSKCHAT-FRESH-LOCAL-002'
            [string]$scoped.objective_id | Should Be 'objective-tod-local-first-smoke'
            [string]$scoped.task_id | Should Not Be 'objective-14-task-79'
            [string]$scoped.tod_activity_stream_build_id | Should Be 'fresh-direct-chat-activity-v1'
        }
        finally {
            if (Test-Path -Path $artifactRoot) {
                Remove-Item -Path $artifactRoot -Recurse -Force
            }
        }
    }
}