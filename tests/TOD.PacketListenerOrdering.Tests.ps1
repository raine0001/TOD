Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$listenerScript = Join-Path $repoRoot 'scripts/Start-TODMimPacketListener.ps1'

function Import-ListenerFunction {
    param([Parameter(Mandatory = $true)][string]$Name)

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($listenerScript, [ref]$tokens, [ref]$errors)
    if (@($errors).Count -gt 0) {
        throw "Failed to parse $listenerScript"
    }

    $fnAst = $ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name
    }, $true)

    if ($null -eq $fnAst) {
        throw "Function '$Name' not found in $listenerScript"
    }

    $definition = $fnAst.Extent.Text -replace ("function\s+{0}\b" -f [regex]::Escape($Name)), ("function global:{0}" -f $Name)
    . ([scriptblock]::Create($definition))
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)]$Payload,
        [int]$Depth = 20
    )

    $dir = Split-Path -Parent $PathValue
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($PathValue, (($Payload | ConvertTo-Json -Depth $Depth) -replace "`r`n", "`n"), $utf8NoBom)
}

function New-MockTodScript {
    param(
        [string]$ReadinessStatus = 'valid',
        [string]$ReadinessReason = 'artifact_valid',
        [bool]$ReadinessValid = $true,
        [bool]$ExecutionAllowed = $true,
        [string[]]$DegradeActions = @()
    )

    $scriptPath = Join-Path $repoRoot ('tod/out/tests/mock-tod-' + [guid]::NewGuid().ToString('N') + '.ps1')
    $degradeActionsLiteral = if ($DegradeActions.Count -gt 0) {
        '@(' + (($DegradeActions | ForEach-Object { "'{0}'" -f $_ }) -join ', ') + ')'
    }
    else {
        '@()'
    }
    $scriptContent = @'
param(
    [string]$Action,
    [string]$RequestId,
        [string]$ObjectiveId,
        [string]$TaskId,
        [string]$Title,
        [string]$Description,
        [string]$Priority,
        [string]$Scope,
        [string]$AcceptanceCriteria,
        [string]$SuccessCriteria,
        [string]$AssignedExecutor,
        [string]$TaskCategory,
        [string]$Content,
    [int]$Top = 0
)

if ($Action -eq 'get-execution-readiness') {
    @{
        signal_name = 'execution-readiness'
        readiness = @{
            status = '__READINESS_STATUS__'
            reason = '__READINESS_REASON__'
            detail = ''
            valid = __READINESS_VALID__
            execution_allowed = __EXECUTION_ALLOWED__
            authoritative = $true
            freshness_state = 'fresh'
        }
        policy = @{
            block_actions = @()
            degrade_actions = __DEGRADE_ACTIONS__
            block_states = @('stale', 'invalid', 'unknown')
            degrade_states = @('degraded', 'stale', 'invalid', 'unknown')
        }
    } | ConvertTo-Json -Depth 8
    return
}

if ($Action -eq 'run-bridge-request') {
    if ([string]::IsNullOrWhiteSpace($RequestId)) {
        throw '-RequestId is required'
    }

    @{
        ok = $true
        action = $Action
        request_id = $RequestId
        top = $Top
    } | ConvertTo-Json -Depth 8
    return
}

if ($Action -eq 'execute-chat-task') {
    @{
        ok = $true
        action = $Action
        objective_id = $ObjectiveId
        task_id = $TaskId
        title = $Title
        description = $Description
        priority = $Priority
        scope = $Scope
        acceptance_criteria = $AcceptanceCriteria
        success_criteria = $SuccessCriteria
        assigned_executor = $AssignedExecutor
        task_category = $TaskCategory
        content = $Content
    } | ConvertTo-Json -Depth 8
    return
}

throw ("Unexpected action: {0}" -f $Action)
'@
    $scriptContent = $scriptContent.Replace('__READINESS_STATUS__', $ReadinessStatus)
    $scriptContent = $scriptContent.Replace('__READINESS_REASON__', $ReadinessReason)
    $scriptContent = $scriptContent.Replace('__READINESS_VALID__', $(if ($ReadinessValid) { '$true' } else { '$false' }))
    $scriptContent = $scriptContent.Replace('__EXECUTION_ALLOWED__', $(if ($ExecutionAllowed) { '$true' } else { '$false' }))
    $scriptContent = $scriptContent.Replace('__DEGRADE_ACTIONS__', $degradeActionsLiteral)

    $dir = Split-Path -Parent $scriptPath
    if (-not (Test-Path -Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($scriptPath, ($scriptContent -replace "`r`n", "`n"), $utf8NoBom)
    return $scriptPath
}

Describe 'TOD packet listener ordering hardening' {
    BeforeAll {
        Import-ListenerFunction -Name 'Get-ObjectiveNumericValue'
        Import-ListenerFunction -Name 'Normalize-ObjectiveIdText'
        Import-ListenerFunction -Name 'Test-ObjectiveInvalidatedByAuthority'
        Import-ListenerFunction -Name 'Get-RequestIdentifier'
        Import-ListenerFunction -Name 'Get-ExpectedObjectiveFromRequest'
        Import-ListenerFunction -Name 'Get-RequestExecutorRole'
        Import-ListenerFunction -Name 'Get-RequestExecutionPolicyClass'
        Import-ListenerFunction -Name 'Get-RequestBoundaryClass'
        Import-ListenerFunction -Name 'Get-UtcNowString'
        Import-ListenerFunction -Name 'Get-ExecutionReadinessTrace'
        Import-ListenerFunction -Name 'Get-MimRequestDecision'
        Import-ListenerFunction -Name 'Convert-JsonDeserializedValue'
        Import-ListenerFunction -Name 'ConvertFrom-JsonCaseInsensitiveSafe'
        Import-ListenerFunction -Name 'Get-ObjectFieldLong'
        Import-ListenerFunction -Name 'Get-TaskOrdinalInfo'
        Import-ListenerFunction -Name 'Get-RequestOrderingInfo'
        Import-ListenerFunction -Name 'Test-RequestOrderingIsStale'
        Import-ListenerFunction -Name 'Update-TaskHighWatermark'
        Import-ListenerFunction -Name 'Get-RetryWeight'
        Import-ListenerFunction -Name 'Update-CadencePlan'
        Import-ListenerFunction -Name 'Get-ListenerExecutionFeedbackConfig'
        Import-ListenerFunction -Name 'Get-RequestExecutionId'
        Import-ListenerFunction -Name 'Resolve-ExecutionFeedbackEndpoint'
        Import-ListenerFunction -Name 'Publish-ExecutionFeedbackFromRequest'
        Import-ListenerFunction -Name 'Invoke-RequestExecution'
        Import-ListenerFunction -Name 'Get-ObjectFieldText'
        Import-ListenerFunction -Name 'Get-NonEmptyPacketValue'
        Import-ListenerFunction -Name 'Get-TriggerContext'
        Import-ListenerFunction -Name 'Publish-CommandStatus'
        Import-ListenerFunction -Name 'Publish-ExecutionLock'
    }

    It 'ignores inactive authority reset ceilings' {
        $inactiveReset = [pscustomobject]@{
            active = $false
            authoritative_current_objective = '216'
            max_valid_objective = '216'
            invalidated_objectives = @('720')
        }

        (Test-ObjectiveInvalidatedByAuthority -ObjectiveId 'objective-720' -AuthorityReset $inactiveReset) | Should Be $false
        (Test-ObjectiveInvalidatedByAuthority -ObjectiveId '720' -AuthorityReset $inactiveReset) | Should Be $false
    }

    It 'uses aligned objective when authority reset is inactive' {
        $mockTodScript = New-MockTodScript
        try {
            $request = [pscustomobject]@{
                request_id = 'objective-2005-task-5327-implement-bounded-work-for-handle-that-thing'
                task_id = 'objective-2005-task-5327'
                objective_id = 'objective-2005'
                assigned_executor = 'TOD'
                tod_action = 'run-bridge-request'
            }
            $integrationStatus = [pscustomobject]@{
                objective_authority_reset = [pscustomobject]@{
                    active = $false
                    authoritative_current_objective = '216'
                    max_valid_objective = '216'
                }
                objective_alignment = [pscustomobject]@{
                    tod_current_objective = '2005'
                }
                live_task_request = [pscustomobject]@{
                    request_id = 'objective-2005-task-5327-implement-bounded-work-for-handle-that-thing'
                    normalized_objective_id = '2005'
                    promotion_applied = $true
                }
                bridge_canonical_evidence = [pscustomobject]@{
                    failure_signals = @()
                }
                bridge_operator_guidance = [pscustomobject]@{
                    recommendation = 'continue_bounded_execution'
                }
            }

            $decision = Get-MimRequestDecision -Request $request -GoOrder $null -IntegrationStatus $integrationStatus -ReviewDecision $null -TodScriptAbs $mockTodScript

            [string]$decision.reason_code | Should Not Be 'objective_mismatch'
            [string]$decision.canonical_objective_id | Should Be '2005'
        }
        finally {
            if (-not [string]::IsNullOrWhiteSpace($mockTodScript) -and (Test-Path -Path $mockTodScript)) {
                Remove-Item -Path $mockTodScript -Force
            }
        }
    }

    It 'degrades codex handoff when readiness is invalid without blocking execution' {
        $mockTodScript = New-MockTodScript -ReadinessStatus 'invalid' -ReadinessReason 'artifact_failed' -ReadinessValid $false -ExecutionAllowed $false -DegradeActions @('codex_handoff')
        try {
            $request = [pscustomobject]@{
                request_id = 'objective-2007-task-5331-implement-bounded-work-for-handle-that-thing'
                task_id = 'objective-2007-task-5331'
                objective_id = 'objective-2007'
                assigned_executor = 'codex'
                action = 'codex_handoff'
            }
            $integrationStatus = [pscustomobject]@{
                objective_alignment = [pscustomobject]@{
                    tod_current_objective = '2007'
                }
                live_task_request = [pscustomobject]@{
                    request_id = 'objective-2007-task-5331-implement-bounded-work-for-handle-that-thing'
                    normalized_objective_id = '2007'
                    promotion_applied = $true
                }
                bridge_canonical_evidence = [pscustomobject]@{
                    failure_signals = @()
                }
                bridge_operator_guidance = [pscustomobject]@{
                    recommendation = 'continue_bounded_execution'
                }
            }

            $decision = Get-MimRequestDecision -Request $request -GoOrder $null -IntegrationStatus $integrationStatus -ReviewDecision $null -TodScriptAbs $mockTodScript

            [string]$decision.decision_outcome | Should Be 'execute'
            [string]$decision.reason_code | Should Be 'authorized_routine_request'
            [string]$decision.execution_readiness.status | Should Be 'invalid'
            [string]$decision.execution_readiness.source | Should Be 'artifact_failed'
            [string]$decision.execution_readiness.policy_outcome | Should Be 'degrade'
        }
        finally {
            if (-not [string]::IsNullOrWhiteSpace($mockTodScript) -and (Test-Path -Path $mockTodScript)) {
                Remove-Item -Path $mockTodScript -Force
            }
        }
    }

    It 'prefers explicit request sequence over request-id suffix ordering' {
        $state = [pscustomobject]@{
            high_watermark_request_id = ''
            high_watermark_objective_id = ''
            high_watermark_ordinal = 0L
            high_watermark_sequence = 0L
        }

        $olderBySuffix = [pscustomobject]@{
            request_id = 'objective-306-task-mim-arm-safe-home-20260403171131'
            task_id = 'objective-306-task-mim-arm-safe-home-20260403171131'
            sequence = 100
        }
        $newerBySequence = [pscustomobject]@{
            request_id = 'objective-306-task-mim-arm-scan-pose-1775330845'
            task_id = 'objective-306-task-mim-arm-scan-pose-1775330845'
            sequence = 200
        }

        $olderInfo = Get-RequestOrderingInfo -Request $olderBySuffix -RequestId $olderBySuffix.request_id -FallbackObjectiveId '306'
        $highWatermark = Update-TaskHighWatermark -State $state -CandidateInfo $olderInfo
        $newerInfo = Get-RequestOrderingInfo -Request $newerBySequence -RequestId $newerBySequence.request_id -FallbackObjectiveId '306'
        $highWatermark = Update-TaskHighWatermark -State $state -CandidateInfo $newerInfo

        [string]$highWatermark.raw | Should Be 'objective-306-task-mim-arm-scan-pose-1775330845'
        [long]$highWatermark.sequence | Should Be 200
        [string]$highWatermark.source_field | Should Be 'high_watermark_sequence'
        (Test-RequestOrderingIsStale -RequestOrderingInfo $olderInfo -HighWatermark $highWatermark) | Should Be $true
        (Test-RequestOrderingIsStale -RequestOrderingInfo $newerInfo -HighWatermark $highWatermark) | Should Be $false
    }

    It 'treats duplicate-seen cycles as cadence noise without inflating retry streaks' {
        $fixture = Join-Path $repoRoot ('tod/out/tests/packet-listener-ordering-' + [guid]::NewGuid().ToString('N'))
        $statePath = Join-Path $fixture 'listener_state.json'
        $state = [pscustomobject]@{
            cadence_retry_streak = 12
            cadence_backoff_seconds = 18
            cadence_last_success_at = ''
            last_cycle_classification = ''
            last_retry_reason = ''
            cadence_minimum_cycle_seconds = 0
            cadence_planned_sleep_seconds = 0
        }

        $plan = Update-CadencePlan -ListenerState $state -ListenerStatePath $statePath -CycleClassification 'duplicate_seen' -RetryReason 'duplicate_seen' -BasePollSeconds 2

        [int]$plan.retry_streak | Should Be 0
        [int]$plan.backoff_seconds | Should Be 4
        [bool]$plan.cadence_noise | Should Be $true
        [int]$state.cadence_retry_streak | Should Be 0
        [int]$state.cadence_backoff_seconds | Should Be 4
        [string]$state.last_retry_reason | Should Be 'duplicate_seen'
        [string]$state.last_cycle_classification | Should Be 'duplicate_seen'
        ([string]::IsNullOrWhiteSpace([string]$state.cadence_last_success_at)) | Should Be $false
        (Test-Path -Path $statePath) | Should Be $true
    }

    It 'forwards request_id when dispatching run-bridge-request' {
        $mockTodScript = New-MockTodScript
        try {
            $request = [pscustomobject]@{
                request_id = 'objective-110-task-mim-arm-capture-frame-20260406235459'
                objective_id = 'objective-110'
                tod_action = 'run-bridge-request'
                top = 3
            }

            $execution = Invoke-RequestExecution -TodScriptAbs $mockTodScript -Request $request

            [bool]$execution.ok | Should Be $true
            [string]$execution.action | Should Be 'run-bridge-request'
            [string]$execution.execution_mode | Should Be 'direct_script_success'
            [string]$execution.payload.request_id | Should Be 'objective-110-task-mim-arm-capture-frame-20260406235459'
            [int]$execution.payload.top | Should Be 3
        }
        finally {
            if (-not [string]::IsNullOrWhiteSpace($mockTodScript) -and (Test-Path -Path $mockTodScript)) {
                Remove-Item -Path $mockTodScript -Force
            }
        }
    }

    It 'forwards execute-chat-task metadata when dispatching bounded listener work' {
        $mockTodScript = New-MockTodScript
        try {
            $request = [pscustomobject]@{
                request_id = 'objective-111-task-implement-local-executor'
                task_id = 'objective-111-task-implement-local-executor'
                objective_id = 'objective-111'
                tod_action = 'execute-chat-task'
                title = 'Build TOD execution loop contract'
                description = 'Create and run the next bounded local execution slice.'
                priority = 'high'
                scope = 'Implement the execution loop contract in the local TOD surfaces.'
                acceptance_criteria = 'Execution loop contract is published and validated.'
                success_criteria = 'Execution loop contract is published and validated.'
                assigned_executor = 'codex'
                task_category = 'chat_execution'
                content = 'OBJECTIVE_ID: objective-111`nTITLE: Build TOD execution loop contract'
            }

            $execution = Invoke-RequestExecution -TodScriptAbs $mockTodScript -Request $request

            [bool]$execution.ok | Should Be $true
            [string]$execution.action | Should Be 'execute-chat-task'
            [string]$execution.execution_mode | Should Be 'direct_script_success'
            [string]$execution.payload.objective_id | Should Be 'objective-111'
            [string]$execution.payload.task_id | Should Be 'objective-111-task-implement-local-executor'
            [string]$execution.payload.title | Should Be 'Build TOD execution loop contract'
            [string]$execution.payload.scope | Should Be 'Implement the execution loop contract in the local TOD surfaces.'
            [string]$execution.payload.acceptance_criteria | Should Be 'Execution loop contract is published and validated.'
            [string]$execution.payload.task_category | Should Be 'chat_execution'
            [string]$execution.payload.assigned_executor | Should Be 'codex'
        }
        finally {
            if (-not [string]::IsNullOrWhiteSpace($mockTodScript) -and (Test-Path -Path $mockTodScript)) {
                Remove-Item -Path $mockTodScript -Force
            }
        }
    }

    It 'resolves relative feedback endpoint from TOD config and publishes executor timestamps' {
        $captured = [pscustomobject]@{
            Uri = ''
            Method = ''
            ContentType = ''
            Headers = $null
            Body = ''
        }

        function global:Invoke-RestMethod {
            param(
                [string]$Method,
                [string]$Uri,
                [string]$ContentType,
                $Headers,
                [string]$Body
            )

            $captured.Uri = $Uri
            $captured.Method = $Method
            $captured.ContentType = $ContentType
            $captured.Headers = $Headers
            $captured.Body = $Body
            return [pscustomobject]@{ ok = $true }
        }

        try {
            $request = [pscustomobject]@{
                request_id = 'objective-152-task-mim-arm-safe-home-20260408160030'
                task_id = 'objective-152-task-mim-arm-safe-home-20260408160030'
                objective_id = 'objective-152'
                action = 'safe_home'
                capability_name = 'mim_arm.execute_safe_home'
                execution_id = 777
                feedback_endpoint = '/gateway/capabilities/executions/777/feedback'
            }

            $result = Publish-ExecutionFeedbackFromRequest -Request $request -Status 'succeeded' -TaskId $request.task_id -HostReceivedTimestamp '2026-04-08T16:00:42Z' -HostCompletedTimestamp '2026-04-08T16:00:43Z' -ResultReasonCode 'execution_completed' -ExecutionMode 'direct_script_success'

            [bool]$result.attempted | Should Be $true
            [bool]$result.published | Should Be $true
            [string]$captured.Uri | Should Be 'http://192.168.1.120:8000/gateway/capabilities/executions/777/feedback'
            [string]$captured.Method | Should Be 'Post'
            [string]$captured.ContentType | Should Be 'application/json'

            $payload = ($captured.Body | ConvertFrom-Json)
            [string]$payload.status | Should Be 'succeeded'
            [string]$payload.details.host_received_timestamp | Should Be '2026-04-08T16:00:42Z'
            [string]$payload.details.host_completed_timestamp | Should Be '2026-04-08T16:00:43Z'
            [string]$payload.details.executor_timestamps.host_received_timestamp | Should Be '2026-04-08T16:00:42Z'
            [string]$payload.details.executor_timestamps.host_completed_timestamp | Should Be '2026-04-08T16:00:43Z'
            [string]$payload.details.result_reason_code | Should Be 'execution_completed'
        }
        finally {
            Remove-Item Function:\Invoke-RestMethod -ErrorAction SilentlyContinue
        }
    }

    It 'does not republish stale guard from listener state when no stale signal is provided' {
        $fixture = Join-Path $repoRoot ('tod/out/tests/packet-listener-stale-guard-' + [guid]::NewGuid().ToString('N'))
        $listenerStatePath = Join-Path $fixture 'listener_state.json'
        $commandStatusPath = Join-Path $fixture 'TOD_MIM_COMMAND_STATUS.latest.json'
        $listenerState = [pscustomobject]@{
            last_stale_guard = [pscustomobject]@{
                objective_id = 'objective-2913'
                task_id = 'objective-2913-task-1777951503'
            }
        }
        $bridgeRuntime = [pscustomobject]@{
            current_processing = [pscustomobject]@{
                task_id = 'objective-2913-task-7144'
                correlation_id = 'objective-2913-task-7144'
            }
        }

        try {
            1..3 | ForEach-Object {
                Publish-CommandStatus -ListenerState $listenerState -ListenerStatePath $listenerStatePath -LocalPath $commandStatusPath -Status 'accepted' -Detail 'Task ACK emitted to shared path.' -RequestId 'objective-2913-task-7144' -TaskId 'objective-2913-task-7144' -CorrelationId 'objective-2913-task-7144' -BridgeRuntime $bridgeRuntime
            }

            $status = Get-Content -Raw -Path $commandStatusPath | ConvertFrom-Json
            $state = Get-Content -Raw -Path $listenerStatePath | ConvertFrom-Json

            $status.stale_guard | Should Be $null
            $state.last_stale_guard | Should Be $null
        }
        finally {
            if (Test-Path -Path $fixture) {
                Remove-Item -Path $fixture -Recurse -Force
            }
        }
    }

    It 'publishes a listener-owned execution lock for the active task' {
        $fixture = Join-Path $repoRoot ('tod/out/tests/packet-listener-execution-lock-' + [guid]::NewGuid().ToString('N'))
        $executionLockPath = Join-Path $fixture 'TOD_EXECUTION_LOCK.latest.json'
        $bridgeRuntime = [pscustomobject]@{
            current_processing = [pscustomobject]@{
                objective_id = 'objective-2913'
                task_id = 'objective-2913-task-7144'
                request_id = 'objective-2913-task-7144'
                correlation_id = 'objective-2913-task-7144'
            }
        }

        try {
            Publish-ExecutionLock -LocalPath $executionLockPath -ObjectiveId 'objective-2913' -TaskId 'objective-2913-task-7144' -RequestId 'objective-2913-task-7144' -CorrelationId 'objective-2913-task-7144' -Status 'succeeded' -BridgeRuntime $bridgeRuntime

            $lock = Get-Content -Raw -Path $executionLockPath | ConvertFrom-Json

            [string]$lock.writer | Should Be 'Start-TODMimPacketListener'
            [string]$lock.task_id | Should Be 'objective-2913-task-7144'
            [string]$lock.request_id | Should Be 'objective-2913-task-7144'
            [string]$lock.current_processing.task_id | Should Be 'objective-2913-task-7144'
        }
        finally {
            if (Test-Path -Path $fixture) {
                Remove-Item -Path $fixture -Recurse -Force
            }
        }
    }

    It 'rejects command-status writes that introduce a mismatched task_id' {
        $fixture = Join-Path $repoRoot ('tod/out/tests/packet-listener-lineage-mismatch-' + [guid]::NewGuid().ToString('N'))
        $listenerStatePath = Join-Path $fixture 'listener_state.json'
        $commandStatusPath = Join-Path $fixture 'TOD_MIM_COMMAND_STATUS.latest.json'
        $listenerState = [pscustomobject]@{}
        $bridgeRuntime = [pscustomobject]@{
            current_processing = [pscustomobject]@{
                task_id = 'objective-2913-task-1777951503'
                correlation_id = 'objective-2913-task-7144'
            }
        }

        try {
            Publish-CommandStatus -ListenerState $listenerState -ListenerStatePath $listenerStatePath -LocalPath $commandStatusPath -Status 'accepted' -Detail 'Task ACK emitted to shared path.' -RequestId 'objective-2913-task-7144' -TaskId 'objective-2913-task-7144' -CorrelationId 'objective-2913-task-7144' -BridgeRuntime $bridgeRuntime

            (Test-Path -Path $commandStatusPath) | Should Be $false
        }
        finally {
            if (Test-Path -Path $fixture) {
                Remove-Item -Path $fixture -Recurse -Force
            }
        }
    }
}
