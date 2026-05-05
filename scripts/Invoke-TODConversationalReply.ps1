param(
    [Parameter(Mandatory = $true)]
    [string]$Query,
    [string]$ObjectiveId = '',
    [string]$OperatorName = '',
    [string]$ConversationHistoryJson = '[]',
    [int]$WindowMinutes = 10,
    [string]$ProviderConfigPath = 'tod/config/voice-adapter.json',
    [string]$CurrentBuildStatePath = 'shared_state/current_build_state.json',
    [string]$IntegrationStatusPath = 'shared_state/integration_status.json',
    [string]$ObjectivesPath = 'shared_state/objectives.json',
    [string]$MaintenancePath = 'shared_state/TOD_SELF_HEALTH_RUN.latest.json',
    [string]$WatchdogPath = 'shared_state/tod_recovery_watchdog.latest.json',
    [string]$NextStepConsensusPath = 'shared_state/NEXT_STEP_CONSENSUS.latest.json',
    [string]$MimWallStatePath = 'shared_state/mim_wall_state.latest.json',
    [string]$CommitmentPath = 'shared_state/tod_operator_chat_commitment.latest.json',
    [string]$ReasoningPath = 'shared_state/tod_operator_chat_reasoning.latest.json',
    [string]$ActionAuditPath = 'shared_state/tod_operator_chat_action_audit.latest.json',
    [string]$ListenerRequestPath = 'shared_state/MIM_TOD_TASK_REQUEST.latest.json',
    [string]$ListenerResultPath = 'shared_state/TOD_MIM_TASK_RESULT.latest.json',
    [string]$ListenerCommandStatusPath = 'shared_state/TOD_MIM_COMMAND_STATUS.latest.json',
    [string]$ListenerDecisionPath = 'shared_state/TOD_MIM_EXECUTION_DECISION.latest.json',
    [string]$TodConfigPath = '',
    [string]$TodStatePath = '',
    [switch]$SkipModel,
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$conversationProviderScript = Join-Path $PSScriptRoot 'Invoke-TODConversationProvider.ps1'
$todScript = Join-Path $PSScriptRoot 'TOD.ps1'

function Resolve-RepoPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return $PathValue
    }
    return (Join-Path $repoRoot $PathValue)
}

function Read-JsonFileSafe {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if (-not (Test-Path -Path $PathValue)) {
        return $null
    }

    try {
        return (Get-Content -Path $PathValue -Raw -Encoding UTF8 | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Get-PropertyValue {
    param(
        [AllowNull()]$InputObject,
        [Parameter(Mandatory = $true)][string]$PropertyName,
        $Default = $null
    )

    if ($null -eq $InputObject) {
        return $Default
    }

    $property = $InputObject.PSObject.Properties[$PropertyName]
    if ($null -eq $property) {
        return $Default
    }

    return $property.Value
}

function ConvertFrom-JsonBestEffort {
    param([Parameter(Mandatory = $true)][string]$Text)

    $trimmed = $Text.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        throw 'JSON text is empty.'
    }

    try {
        return ($trimmed | ConvertFrom-Json)
    }
    catch {
        $jsonStart = -1
        $braceStart = $trimmed.IndexOf('{')
        $bracketStart = $trimmed.IndexOf('[')
        if ($braceStart -ge 0 -and $bracketStart -ge 0) {
            $jsonStart = [Math]::Min($braceStart, $bracketStart)
        }
        elseif ($braceStart -ge 0) {
            $jsonStart = $braceStart
        }
        elseif ($bracketStart -ge 0) {
            $jsonStart = $bracketStart
        }

        if ($jsonStart -lt 0) {
            throw
        }

        return ($trimmed.Substring($jsonStart) | ConvertFrom-Json)
    }
}

function Get-RequestKind {
    param([Parameter(Mandatory = $true)][string]$QueryText)

    $normalized = $QueryText.ToLowerInvariant()
    if ($normalized -match '(?m)^\s*(objective|task|stop condition|acceptance criteria)\s*:') {
        return 'implementation_request'
    }
    if ($normalized -match 'implement|implementation|build|wire|setup|set up|create|add|change|make|begin|start|ship|develop|conversation|communicat') {
        return 'implementation_request'
    }
    if ($normalized -match 'status|summary|what are you|current work|progress') {
        return 'status_request'
    }
    return 'general_request'
}

function Get-IntentTarget {
    param([Parameter(Mandatory = $true)][string]$QueryText)

    $normalized = $QueryText.ToLowerInvariant()
    if ($normalized -match 'mic|microphone|audio|speaker|mute|unmute|voice|listen') {
        return 'UI / audio'
    }
    if ($normalized -match 'training|runbook|campaign|learn') {
        return 'training'
    }
    if ($normalized -match 'service|listener|watchdog|bridge|health|runtime|process') {
        return 'runtime / services'
    }
    if ($normalized -match 'file|path|repo|workspace|folder|directory') {
        return 'files / workspace'
    }
    return 'general'
}

function Get-IntentRoute {
    param([Parameter(Mandatory = $true)][string]$QueryText)

    $normalized = $QueryText.Trim().ToLowerInvariant()
    $intent = 'CONVERSATION'
    $action = 'direct reply'
    $requestKind = Get-RequestKind -QueryText $QueryText
    $hasStructuredTaskRequest = ($normalized -match '(?m)^\s*(objective|task|stop condition|acceptance criteria)\s*:')

    if ($normalized -match '^(override|control|force|policy|priority|admin|elevat|restart tod|freeze|unfreeze|disable restriction)\b') {
        $intent = 'SYSTEM'
        $action = 'override / control'
        $requestKind = 'implementation_request'
    }
    elseif ($normalized -match '^(why|what|show|explain|diagnose|inspect|debug|status|summary|health|logs?|trace|where|which)\b') {
        $intent = 'DIAGNOSTIC'
        $action = 'explain system'
        $requestKind = 'status_request'
    }
    elseif ($normalized -match '^(fix|create|add|remove|update|run|start|setup|stop|restart|enable|disable|make|repair|sync|deploy|train|turn|open|close|package|dispatch)\b') {
        $intent = 'COMMAND'
        $action = 'create + dispatch task'
        $requestKind = 'implementation_request'
    }
    elseif ($hasStructuredTaskRequest) {
        $intent = 'COMMAND'
        $action = 'create + dispatch task'
        $requestKind = 'implementation_request'
    }

    [pscustomobject]@{
        intent = $intent
        target = (Get-IntentTarget -QueryText $QueryText)
        action = $action
        request_kind = $requestKind
        query = $QueryText
    }
}

function Test-ReplyUsesDisallowedRestrictionLanguage {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $false
    }

    return ($Text -match '(?i)\b(i cannot|i can''t|i can not|i do not have the ability|i don''t have the ability|i am unable to)\b')
}

function New-IntentAcceptanceCriteria {
    param(
        [Parameter(Mandatory = $true)][string]$IntentTarget,
        [Parameter(Mandatory = $true)][string]$QueryText
    )

    return @(
        ('A bounded task exists for the requested target area: {0}.' -f $IntentTarget),
        ('The task scope explicitly addresses the operator command: {0}' -f $QueryText),
        'Dispatch-ready task context is available for the assigned executor.'
    )
}

function Get-StructuredDirectiveValue {
    param(
        [Parameter(Mandatory = $true)][string]$QueryText,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $match = [regex]::Match($QueryText, ('(?im)^\s*{0}\s*:\s*(.+)$' -f [regex]::Escape($Label)))
    if ($match.Success) {
        return [string]$match.Groups[1].Value.Trim()
    }

    return ''
}

function Convert-ToObjectiveLabelSlug {
    param([string]$Text)

    $raw = [string]$Text
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return ''
    }

    $collapsed = (($raw.Trim().ToLowerInvariant() -replace '[^a-z0-9]+', '-') -replace '-{2,}', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($collapsed)) {
        return ''
    }

    return $collapsed
}

function Resolve-StructuredObjectiveDispatchId {
    param(
        [string]$ExistingObjectiveId,
        [Parameter(Mandatory = $true)][string]$QueryText
    )

    $objectiveDirective = Get-StructuredDirectiveValue -QueryText $QueryText -Label 'OBJECTIVE'
    if ([string]::IsNullOrWhiteSpace($objectiveDirective)) {
        return [string]$ExistingObjectiveId
    }

    $slug = Convert-ToObjectiveLabelSlug -Text $objectiveDirective
    if ([string]::IsNullOrWhiteSpace($slug)) {
        return [string]$ExistingObjectiveId
    }

    return ('objective-{0}' -f $slug)
}

function New-ConversationDispatchId {
    param([Parameter(Mandatory = $true)][string]$Prefix)

    return ('{0}-{1}' -f $Prefix.ToUpperInvariant(), ([guid]::NewGuid().ToString('N').Substring(0, 12).ToUpperInvariant()))
}

function Get-CommandDispatchClassification {
    param(
        $ExecutionPayload,
        [string]$DefaultTaskCategory
    )

    if ($ExecutionPayload -and $ExecutionPayload.PSObject.Properties['routing_decision_preinvoke'] -and $ExecutionPayload.routing_decision_preinvoke -and $ExecutionPayload.routing_decision_preinvoke.PSObject.Properties['selected_engine'] -and -not [string]::IsNullOrWhiteSpace([string]$ExecutionPayload.routing_decision_preinvoke.selected_engine)) {
        return ('engine:{0}' -f [string]$ExecutionPayload.routing_decision_preinvoke.selected_engine)
    }
    if ($ExecutionPayload -and $ExecutionPayload.PSObject.Properties['routing_decision'] -and $ExecutionPayload.routing_decision -and $ExecutionPayload.routing_decision.PSObject.Properties['selected_engine'] -and -not [string]::IsNullOrWhiteSpace([string]$ExecutionPayload.routing_decision.selected_engine)) {
        return ('engine:{0}' -f [string]$ExecutionPayload.routing_decision.selected_engine)
    }
    if (-not [string]::IsNullOrWhiteSpace($DefaultTaskCategory)) {
        return ('task_category:{0}' -f $DefaultTaskCategory)
    }

    return 'task_category:general'
}

function Get-CommandDispatchNextStep {
    param($ExecutionPayload)

    if ($ExecutionPayload -and $ExecutionPayload.PSObject.Properties['next_task_selection'] -and $ExecutionPayload.next_task_selection -and $ExecutionPayload.next_task_selection.PSObject.Properties['selected_task_id'] -and -not [string]::IsNullOrWhiteSpace([string]$ExecutionPayload.next_task_selection.selected_task_id)) {
        return ('next task selected: {0}' -f [string]$ExecutionPayload.next_task_selection.selected_task_id)
    }
    if ($ExecutionPayload -and $ExecutionPayload.PSObject.Properties['decision']) {
        if ([string]::Equals([string]$ExecutionPayload.decision, 'pass', [System.StringComparison]::OrdinalIgnoreCase)) {
            return 'review the bounded execution output and continue the selected lane'
        }

        return 'inspect the blocking execution output and replay the bounded task with fixes'
    }

    return 'await TOD execution results'
}

function Invoke-TodActionJson {
    param(
        [Parameter(Mandatory = $true)][string]$Action,
        [hashtable]$ExtraArguments = @{}
    )

    if (-not (Test-Path -Path $todScript)) {
        throw 'TOD action script is missing.'
    }

    $invokeArgs = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $todScript,
        '-Action', $Action
    )

    foreach ($key in $ExtraArguments.Keys) {
        if ($null -eq $ExtraArguments[$key]) {
            continue
        }
        $invokeArgs += ('-' + [string]$key)
        $invokeArgs += [string]$ExtraArguments[$key]
    }

    if (-not [string]::IsNullOrWhiteSpace($script:resolvedTodConfigPath)) {
        $invokeArgs += '-ConfigPath'
        $invokeArgs += [string]$script:resolvedTodConfigPath
    }
    if (-not [string]::IsNullOrWhiteSpace($script:resolvedTodStatePath)) {
        $invokeArgs += '-StatePath'
        $invokeArgs += [string]$script:resolvedTodStatePath
    }

    $output = powershell @invokeArgs 2>&1
    $exitCode = $LASTEXITCODE
    $outputText = [string]($output | Out-String)
    if ($exitCode -ne 0) {
        throw $outputText
    }

    return (ConvertFrom-JsonBestEffort -Text $outputText)
}

function New-IntentDispatchResult {
    return [ordered]@{
        attempted = $false
        created = $false
        dispatched = $false
        executed = $false
        blocked = $false
        action_name = ''
        action_kind = ''
        objective_id = ''
        task_id = ''
        request_id = ''
        correlation_id = ''
        title = ''
        task_category = ''
        classification = ''
        next_step = ''
        codex_needed = $false
        request_artifact_path = ''
        detail = ''
        payload = $null
    }
}

function Invoke-IntentCommandDispatch {
    param(
        [Parameter(Mandatory = $true)]$IntentRoute,
        [Parameter(Mandatory = $true)][string]$ResolvedObjectiveId,
        [Parameter(Mandatory = $true)][string]$QueryText
    )

    $result = New-IntentDispatchResult
    $result.objective_id = $ResolvedObjectiveId
    $taskCategory = (($IntentRoute.target -replace '[^A-Za-z0-9]+', '_').Trim('_')).ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($taskCategory)) {
        $taskCategory = 'general'
    }
    $objectiveDirective = Get-StructuredDirectiveValue -QueryText $QueryText -Label 'OBJECTIVE'
    $dispatchObjectiveId = Resolve-StructuredObjectiveDispatchId -ExistingObjectiveId $ResolvedObjectiveId -QueryText $QueryText
    if (-not [string]::IsNullOrWhiteSpace($dispatchObjectiveId)) {
        $result.objective_id = $dispatchObjectiveId
    }
    $taskDirective = Get-StructuredDirectiveValue -QueryText $QueryText -Label 'TASK'
    $stopConditionDirective = Get-StructuredDirectiveValue -QueryText $QueryText -Label 'STOP CONDITION'
    $acceptanceDirective = Get-StructuredDirectiveValue -QueryText $QueryText -Label 'ACCEPTANCE CRITERIA'
    $title = if (-not [string]::IsNullOrWhiteSpace($taskDirective)) {
        [string]$taskDirective
    }
    elseif (-not [string]::IsNullOrWhiteSpace($objectiveDirective)) {
        [string]$objectiveDirective
    }
    else {
        'UI command: ' + $QueryText.Trim()
    }
    $scope = 'Operator command routed from TOD direct conversation. Target: {0}. Requested action: {1}. Original query: {2}' -f $IntentRoute.target, $IntentRoute.action, $QueryText.Trim()
    $acceptanceCriteria = if (-not [string]::IsNullOrWhiteSpace($acceptanceDirective)) {
        [string]$acceptanceDirective
    }
    elseif (-not [string]::IsNullOrWhiteSpace($stopConditionDirective)) {
        [string]$stopConditionDirective
    }
    else {
        (New-IntentAcceptanceCriteria -IntentTarget ([string]$IntentRoute.target) -QueryText $QueryText) -join "`n"
    }
    $objectiveDescription = if (-not [string]::IsNullOrWhiteSpace($objectiveDirective)) {
        ('Objective created from TOD direct chat input: {0}' -f $objectiveDirective)
    }
    else {
        'Objective created from TOD direct chat task dispatch.'
    }
    $requestId = New-ConversationDispatchId -Prefix 'REQ'
    $correlationId = New-ConversationDispatchId -Prefix 'CORR'
    $taskId = New-ConversationDispatchId -Prefix 'TSKCHAT'

    try {
        $result.attempted = $true
        $result.action_name = 'execute-chat-task'
        $result.action_kind = 'task_dispatch'
        $result.request_id = $requestId
        $result.correlation_id = $correlationId
        $parsed = Invoke-TodActionJson -Action 'execute-chat-task' -ExtraArguments @{
            ObjectiveId = $dispatchObjectiveId
            TaskId = $taskId
            RequestId = $requestId
            CorrelationId = $correlationId
            Title = $title
            Description = $objectiveDescription
            Scope = $scope
            AcceptanceCriteria = $acceptanceCriteria
            SuccessCriteria = $acceptanceCriteria
            AssignedExecutor = 'codex'
            TaskCategory = $taskCategory
            Type = 'implementation'
        }
        $taskId = [string](Get-PropertyValue -InputObject $parsed -PropertyName 'task_id' -Default '')
        $result.objective_id = [string](Get-PropertyValue -InputObject $parsed -PropertyName 'objective_id' -Default $dispatchObjectiveId)
        $result.created = (-not [string]::IsNullOrWhiteSpace($taskId))
        $result.dispatched = $result.created
        $result.executed = $result.created
        $result.task_id = $taskId
        $result.title = $title
        $result.task_category = $taskCategory
        $result.classification = Get-CommandDispatchClassification -ExecutionPayload $(Get-PropertyValue -InputObject $parsed -PropertyName 'run_task' -Default $null) -DefaultTaskCategory $taskCategory
        $result.next_step = Get-CommandDispatchNextStep -ExecutionPayload $(Get-PropertyValue -InputObject $parsed -PropertyName 'run_task' -Default $null)
        $result.codex_needed = $true
        $result.request_artifact_path = [string](Get-PropertyValue -InputObject $parsed -PropertyName 'request_artifact_path' -Default '')
        $runTaskPayload = Get-PropertyValue -InputObject $parsed -PropertyName 'run_task' -Default $null
        if ($runTaskPayload -and $runTaskPayload.PSObject.Properties['decision']) {
            $result.blocked = (-not [string]::Equals([string]$runTaskPayload.decision, 'pass', [System.StringComparison]::OrdinalIgnoreCase))
        }
        $result.payload = $parsed
        $result.detail = if ($result.created) { 'Task created, request artifact written, and TOD execution started immediately.' } else { 'TOD ran execute-chat-task but did not receive a task id back.' }
        return [pscustomobject]$result
    }
    catch {
        $result.detail = [string]$_.Exception.Message
        $result.blocked = $true
        return [pscustomobject]$result
    }
}

function Invoke-IntentSystemDispatch {
    param(
        [Parameter(Mandatory = $true)]$IntentRoute,
        [Parameter(Mandatory = $true)][string]$ResolvedObjectiveId,
        [Parameter(Mandatory = $true)][string]$QueryText
    )

    $result = New-IntentDispatchResult
    $result.objective_id = $ResolvedObjectiveId
    $normalized = $QueryText.Trim().ToLowerInvariant()

    try {
        if ($normalized -match 'start training|resume training|continue training|launch training') {
            $result.attempted = $true
            $result.executed = $true
            $result.action_name = 'start-training-runbook'
            $result.action_kind = 'tod_action'
            $payload = Invoke-TodActionJson -Action 'start-training-runbook'
            $result.payload = $payload
            $result.dispatched = $true
            $result.detail = 'Training runbook launch was dispatched through TOD.'
            return [pscustomobject]$result
        }

        if ($normalized -match 'state bus|statebus|bridge state|runtime state|show state') {
            $result.attempted = $true
            $result.executed = $true
            $result.action_name = 'get-state-bus'
            $result.action_kind = 'tod_action'
            $payload = Invoke-TodActionJson -Action 'get-state-bus'
            $result.payload = $payload
            $result.dispatched = $true
            $result.detail = 'State bus snapshot collected through TOD.'
            return [pscustomobject]$result
        }

        if ($normalized -match 'reliability dashboard|show reliability|reliability view') {
            $result.attempted = $true
            $result.executed = $true
            $result.action_name = 'show-reliability-dashboard'
            $result.action_kind = 'tod_action'
            $payload = Invoke-TodActionJson -Action 'show-reliability-dashboard'
            $result.payload = $payload
            $result.dispatched = $true
            $result.detail = 'Reliability dashboard payload collected through TOD.'
            return [pscustomobject]$result
        }

        $taskDispatch = Invoke-IntentCommandDispatch -IntentRoute $IntentRoute -ResolvedObjectiveId $ResolvedObjectiveId -QueryText ('System control: ' + $QueryText.Trim())
        $taskDispatch.action_name = 'add-task'
        $taskDispatch.action_kind = 'system_task_dispatch'
        if ([string]::IsNullOrWhiteSpace([string]$taskDispatch.detail)) {
            $taskDispatch.detail = 'System control was converted into a bounded task for codex.'
        }
        return $taskDispatch
    }
    catch {
        $result.attempted = $true
        $result.detail = [string]$_.Exception.Message
        return [pscustomobject]$result
    }
}

function New-CommunicationSkill {
    param(
        [string]$Name,
        [string]$Status,
        [string]$Summary,
        [string]$Surface
    )

    return [pscustomobject]@{
        name = $Name
        status = $Status
        summary = $Summary
        surface = $Surface
    }
}

function Get-ListCount {
    param($InputObject)

    if ($null -eq $InputObject) {
        return 0
    }

    if ($InputObject -is [System.Array]) {
        return @($InputObject).Count
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
        return @($InputObject).Count
    }

    return 1
}

function Get-DurableMemoryContext {
    param(
        $Commitment,
        $Reasoning,
        $ActionAudit
    )

    $commitmentState = [string](Get-PropertyValue -InputObject $Commitment -PropertyName 'state' -Default 'none')
    $commitmentAction = [string](Get-PropertyValue -InputObject $Commitment -PropertyName 'action_label' -Default (Get-PropertyValue -InputObject $Commitment -PropertyName 'action' -Default ''))
    $commitmentSummary = [string](Get-PropertyValue -InputObject $Commitment -PropertyName 'summary' -Default '')
    $commitmentBundleId = [string](Get-PropertyValue -InputObject $Commitment -PropertyName 'reasoning_bundle_id' -Default '')
    $commitmentObjectiveId = [string](Get-PropertyValue -InputObject $Commitment -PropertyName 'objective_id' -Default '')

    $reasoningBundleId = [string](Get-PropertyValue -InputObject $Reasoning -PropertyName 'reasoning_bundle_id' -Default '')
    $reasoningSummary = [string](Get-PropertyValue -InputObject $Reasoning -PropertyName 'operator_summary' -Default '')
    $reasoningNextStep = [string](Get-PropertyValue -InputObject $Reasoning -PropertyName 'recommended_next_step' -Default '')
    $reasoningEvidenceCount = [int](Get-PropertyValue -InputObject $Reasoning -PropertyName 'evidence_count' -Default 0)
    $reasoningFlagsCount = Get-ListCount -InputObject (Get-PropertyValue -InputObject $Reasoning -PropertyName 'evidence_flags' -Default @())

    $auditId = [string](Get-PropertyValue -InputObject $ActionAudit -PropertyName 'audit_id' -Default '')
    $auditAction = [string](Get-PropertyValue -InputObject $ActionAudit -PropertyName 'action_label' -Default (Get-PropertyValue -InputObject $ActionAudit -PropertyName 'action' -Default ''))
    $auditOutcome = [string](Get-PropertyValue -InputObject $ActionAudit -PropertyName 'outcome_status' -Default '')
    $auditProposalId = [string](Get-PropertyValue -InputObject $ActionAudit -PropertyName 'proposal_id' -Default '')
    $auditProposalTitle = [string](Get-PropertyValue -InputObject $ActionAudit -PropertyName 'proposal_title' -Default '')
    $auditFlagsCount = Get-ListCount -InputObject (Get-PropertyValue -InputObject $ActionAudit -PropertyName 'evidence_flags' -Default @())

    $summaryParts = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($commitmentAction)) {
        [void]$summaryParts.Add(("Latest commitment is {0} for {1}" -f $commitmentState, $commitmentAction))
    }
    if (-not [string]::IsNullOrWhiteSpace($reasoningNextStep)) {
        [void]$summaryParts.Add(("latest reasoning recommends {0}" -f $reasoningNextStep))
    }
    if (-not [string]::IsNullOrWhiteSpace($auditOutcome)) {
        [void]$summaryParts.Add(("latest audit outcome is {0}" -f $auditOutcome))
    }
    if (-not [string]::IsNullOrWhiteSpace($auditProposalTitle)) {
        [void]$summaryParts.Add(("proposal context is {0}" -f $auditProposalTitle))
    }

    $trustChainSummary = if (-not [string]::IsNullOrWhiteSpace($auditId) -or -not [string]::IsNullOrWhiteSpace($reasoningBundleId) -or -not [string]::IsNullOrWhiteSpace($commitmentBundleId)) {
        $auditIdText = if ([string]::IsNullOrWhiteSpace($auditId)) { '-' } else { $auditId }
        $reasoningBundleText = if ([string]::IsNullOrWhiteSpace($reasoningBundleId)) { '-' } else { $reasoningBundleId }
        $commitmentBundleText = if ([string]::IsNullOrWhiteSpace($commitmentBundleId)) { '-' } else { $commitmentBundleId }
        "Trust chain is available through audit {0}, bundle {1}, commitment bundle {2}, with {3} reasoning evidence row(s) and {4} audit flag(s)." -f $auditIdText, $reasoningBundleText, $commitmentBundleText, $reasoningEvidenceCount, $auditFlagsCount
    }
    else {
        'No trust-chain artifact is available yet.'
    }

    [pscustomobject]@{
        available = ($null -ne $Commitment -or $null -ne $Reasoning -or $null -ne $ActionAudit)
        summary = if (@($summaryParts).Count -gt 0) { (($summaryParts -join '; ') + '.') } else { 'No durable conversation memory artifact is available yet.' }
        trust_chain_summary = $trustChainSummary
        latest_commitment = [pscustomobject]@{
            objective_id = $commitmentObjectiveId
            action = $commitmentAction
            state = $commitmentState
            summary = $commitmentSummary
            reasoning_bundle_id = $commitmentBundleId
        }
        latest_reasoning = [pscustomobject]@{
            reasoning_bundle_id = $reasoningBundleId
            summary = $reasoningSummary
            recommended_next_step = $reasoningNextStep
            evidence_count = $reasoningEvidenceCount
            flag_count = $reasoningFlagsCount
        }
        latest_audit = [pscustomobject]@{
            audit_id = $auditId
            action = $auditAction
            outcome_status = $auditOutcome
            proposal_id = $auditProposalId
            proposal_title = $auditProposalTitle
            flag_count = $auditFlagsCount
        }
    }
}

function Test-ProviderReplyUsable {
    param(
        [string]$ReplyText,
        [string]$RequestKind
    )

    if ([string]::IsNullOrWhiteSpace($ReplyText)) {
        return $false
    }

    if (Test-ReplyUsesDisallowedRestrictionLanguage -Text $ReplyText) {
        return $false
    }

    $normalized = $ReplyText.ToLowerInvariant()
    if ($normalized.Length -lt 160) {
        return $false
    }

    if ([string]::Equals($RequestKind, 'implementation_request', [System.StringComparison]::OrdinalIgnoreCase)) {
        $hasImplementation = ($normalized -match 'implementation request') -or ($normalized -match 'implement')
        $hasSkills = ($normalized -match 'communication skill') -or ($normalized -match 'communication stack') -or ($normalized -match 'communication lane')
        $hasSteps = ($normalized -match 'bounded step') -or ($normalized -match '1\.') -or ($normalized -match '1\)') -or ($normalized -match 'step 1')
        return ($hasImplementation -and $hasSkills -and $hasSteps)
    }

    return $true
}

function Get-CommunicationSkills {
    param($VoiceConfig)

    $skills = @(
        (New-CommunicationSkill -Name 'TOD Operator Chat' -Status 'active' -Summary 'Bounded operational summaries, evidence, governance, and next-step recommendations.' -Surface 'ui/index.html + /api/operator-chat'),
        (New-CommunicationSkill -Name 'MIM Command Panel' -Status 'active' -Summary 'Live human-to-MIM browser dialog lane with structured bounded replies.' -Surface 'ui/index.html + /api/mim-command'),
        (New-CommunicationSkill -Name 'TOD-MIM Dialog Channel' -Status 'active' -Summary 'Structured dialog session transport for coordination between TOD and MIM.' -Surface 'scripts/Invoke-TODMimDialog.ps1'),
        (New-CommunicationSkill -Name 'Local Conversation Provider' -Status $(if (Test-Path -Path $conversationProviderScript) { 'available' } else { 'missing' }) -Summary 'Local-first chat-model path for direct natural-language TOD replies.' -Surface 'scripts/Invoke-TODConversationProvider.ps1'),
        (New-CommunicationSkill -Name 'Voice Listener' -Status $(if ($VoiceConfig -and [bool](Get-PropertyValue -InputObject $VoiceConfig -PropertyName 'enabled' -Default $false)) { 'configured' } else { 'disabled_or_unavailable' }) -Summary 'Wake-word voice command recognition and spoken reply path.' -Surface 'scripts/Start-TODVoiceListener.ps1'),
        (New-CommunicationSkill -Name 'Conversation Evaluation Harness' -Status 'active' -Summary 'Conversation simulation, drift analysis, and regression gating.' -Surface 'scripts/Invoke-TODConversationEvalRunner.ps1')
    )

    return @($skills)
}

function Get-BoundedSteps {
    param([string]$RequestKind)

    $steps = @(
        [pscustomobject]@{ id = 1; title = 'Direct TOD conversation lane'; summary = 'Expose TOD as a first-class conversational partner in the browser instead of only status or MIM routing.' },
        [pscustomobject]@{ id = 2; title = 'Shared reply context pack'; summary = 'Ground TOD replies in current build, maintenance, watchdog, and integration artifacts so replies stay factual.' },
        [pscustomobject]@{ id = 3; title = 'Implementation request detection'; summary = 'Classify build/change/setup requests so TOD responds with development posture, bounded steps, and working-vs-blocked status.' },
        [pscustomobject]@{ id = 4; title = 'Memory and commitment merge'; summary = 'Unify direct conversation with commitments, reasoning, and durable conversation memory rather than keeping them as separate lanes.' },
        [pscustomobject]@{ id = 5; title = 'Conversation regression gate'; summary = 'Keep the direct TOD lane under focused regression tests and live sweeps so it does not degrade back into status-only output.' }
    )

    if ([string]::Equals($RequestKind, 'implementation_request', [System.StringComparison]::OrdinalIgnoreCase)) {
        return @($steps)
    }

    return @($steps | Select-Object -First 3)
}

function Get-ObjectiveSummaryText {
    param(
        $CurrentBuildState,
        $ObjectivesDoc,
        [string]$ResolvedObjectiveId
    )

    $summaryParts = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($ResolvedObjectiveId)) {
        [void]$summaryParts.Add("Objective: $ResolvedObjectiveId")
    }

    if ($CurrentBuildState) {
        $state = [string](Get-PropertyValue -InputObject $CurrentBuildState -PropertyName 'status' -Default '')
        $task = [string](Get-PropertyValue -InputObject $CurrentBuildState -PropertyName 'task' -Default '')
        if (-not [string]::IsNullOrWhiteSpace($state)) {
            [void]$summaryParts.Add("Build state: $state")
        }
        if (-not [string]::IsNullOrWhiteSpace($task)) {
            [void]$summaryParts.Add("Task: $task")
        }
    }

    $objectiveCount = 0
    if ($ObjectivesDoc) {
        $items = @()
        if ($ObjectivesDoc -is [System.Collections.IEnumerable] -and -not ($ObjectivesDoc -is [string])) {
            $items = @($ObjectivesDoc)
        }
        elseif ($ObjectivesDoc.PSObject.Properties['objectives']) {
            $items = @($ObjectivesDoc.objectives)
        }
        $objectiveCount = @($items).Count
    }
    if ($objectiveCount -gt 0) {
        [void]$summaryParts.Add("Known objectives: $objectiveCount")
    }

    if (@($summaryParts).Count -eq 0) {
        return 'No current objective summary was available from local artifacts.'
    }

    return ($summaryParts -join ' | ')
}

function Get-ConversationHistoryEntries {
    param([string]$HistoryJson)

    if ([string]::IsNullOrWhiteSpace($HistoryJson)) {
        return @()
    }

    try {
        $parsed = $HistoryJson | ConvertFrom-Json
        if ($parsed -is [System.Array]) {
            return @($parsed)
        }
        if ($parsed) {
            return @($parsed)
        }
    }
    catch {
    }

    return @()
}

function Get-ConversationMemoryContext {
    param(
        [string]$Operator,
        $HistoryEntries
    )

    $resolvedOperator = if ([string]::IsNullOrWhiteSpace($Operator)) { 'Operator' } else { $Operator.Trim() }
    $entries = @($HistoryEntries)
    $recentEntries = @($entries | Select-Object -Last 8)
    $recentUserEntries = @($recentEntries | Where-Object {
        $roleValue = [string](Get-PropertyValue -InputObject $_ -PropertyName 'role' -Default '')
        $roleValue -eq 'user'
    })
    $recentTopics = @($recentUserEntries | ForEach-Object {
        $textValue = [string](Get-PropertyValue -InputObject $_ -PropertyName 'text' -Default '')
        if ($textValue.Length -gt 72) { $textValue.Substring(0, 72).Trim() + '...' } else { $textValue.Trim() }
    } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Last 3)

    $lastUserEntry = if ($recentUserEntries.Count -gt 0) { @($recentUserEntries | Select-Object -Last 1)[0] } else { $null }
    $assistantEntries = @($recentEntries | Where-Object {
        $roleValue = [string](Get-PropertyValue -InputObject $_ -PropertyName 'role' -Default '')
        $roleValue -eq 'assistant'
    })
    $lastAssistantEntry = if ($assistantEntries.Count -gt 0) { @($assistantEntries | Select-Object -Last 1)[0] } else { $null }

    $summary = if ($entries.Count -gt 0) {
        $topicText = if ($recentTopics.Count -gt 0) { ' Recent topics: ' + ($recentTopics -join '; ') + '.' } else { '' }
        "I know I'm talking to $resolvedOperator and I have $($entries.Count) recent conversation turn(s) in memory.$topicText"
    }
    else {
        "I know I'm talking to $resolvedOperator, and this is the start of our current browser conversation."
    }

    [pscustomobject]@{
        operator_name = $resolvedOperator
        turn_count = $entries.Count
        summary = $summary
        recent_topics = @($recentTopics)
        last_user_message = if ($lastUserEntry) { [string](Get-PropertyValue -InputObject $lastUserEntry -PropertyName 'text' -Default '') } else { '' }
        last_tod_message = if ($lastAssistantEntry) { [string](Get-PropertyValue -InputObject $lastAssistantEntry -PropertyName 'text' -Default '') } else { '' }
    }
}

function Get-FirstNonEmptyValue {
    param([object[]]$Candidates)

    foreach ($candidate in $Candidates) {
        $text = [string]$candidate
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            return $text.Trim()
        }
    }

    return ''
}

function Normalize-ObjectiveId {
    param([string]$ObjectiveId)

    $text = [string]$ObjectiveId
    if ([string]::IsNullOrWhiteSpace($text)) {
        return ''
    }

    $trimmed = $text.Trim().ToLowerInvariant()
    if ($trimmed -match '^objective-(.+)$') {
        return [string]$matches[1]
    }

    return $trimmed
}

function Test-ObjectiveMismatch {
    param(
        [string]$LocalObjectiveId,
        [string]$CanonicalObjectiveId,
        [string[]]$InvalidatedObjectives = @()
    )

    $localNormalized = Normalize-ObjectiveId -ObjectiveId $LocalObjectiveId
    $canonicalNormalized = Normalize-ObjectiveId -ObjectiveId $CanonicalObjectiveId

    if ([string]::IsNullOrWhiteSpace($canonicalNormalized)) {
        return $false
    }

    if ([string]::IsNullOrWhiteSpace($localNormalized)) {
        return $true
    }

    if ($localNormalized -ne $canonicalNormalized) {
        return $true
    }

    foreach ($invalidated in @($InvalidatedObjectives)) {
        if ($localNormalized -eq (Normalize-ObjectiveId -ObjectiveId ([string]$invalidated))) {
            return $true
        }
    }

    return $false
}

function Get-CanonicalConversationContext {
    param(
        $CurrentBuildState,
        $IntegrationStatus,
        $ActionAudit
    )

    $authorityReset = Get-PropertyValue -InputObject $CurrentBuildState -PropertyName 'objective_authority_reset' -Default $null
    if ($null -eq $authorityReset) {
        $authorityReset = Get-PropertyValue -InputObject $IntegrationStatus -PropertyName 'objective_authority_reset' -Default $null
    }

    $liveTaskRequest = Get-PropertyValue -InputObject $IntegrationStatus -PropertyName 'live_task_request' -Default $null
    $objectiveAlignment = Get-PropertyValue -InputObject $IntegrationStatus -PropertyName 'objective_alignment' -Default $null

    $canonicalObjectiveId = Get-FirstNonEmptyValue @(
        (Get-PropertyValue -InputObject $authorityReset -PropertyName 'authoritative_current_objective' -Default ''),
        (Get-PropertyValue -InputObject $liveTaskRequest -PropertyName 'normalized_objective_id' -Default ''),
        (Get-PropertyValue -InputObject $liveTaskRequest -PropertyName 'objective_id' -Default ''),
        (Get-PropertyValue -InputObject $objectiveAlignment -PropertyName 'tod_current_objective' -Default ''),
        (Get-PropertyValue -InputObject $objectiveAlignment -PropertyName 'mim_objective_active' -Default '')
    )

    $liveTaskId = [string](Get-PropertyValue -InputObject $liveTaskRequest -PropertyName 'task_id' -Default '')
    $proposalId = [string](Get-PropertyValue -InputObject $ActionAudit -PropertyName 'proposal_id' -Default '')
    $proposalTitle = [string](Get-PropertyValue -InputObject $ActionAudit -PropertyName 'proposal_title' -Default '')
    $activeTask = if (-not [string]::IsNullOrWhiteSpace($liveTaskId) -and [string]::Equals($proposalId, $liveTaskId, [System.StringComparison]::OrdinalIgnoreCase) -and -not [string]::IsNullOrWhiteSpace($proposalTitle)) {
        $proposalTitle
    }
    else {
        Get-FirstNonEmptyValue @($proposalTitle, $liveTaskId)
    }

    $nextAction = Get-FirstNonEmptyValue @(
        $activeTask,
        (Get-PropertyValue -InputObject $liveTaskRequest -PropertyName 'request_id' -Default ''),
        'continue canonical live task execution'
    )

    [pscustomobject]@{
        available = (-not [string]::IsNullOrWhiteSpace($canonicalObjectiveId))
        objective_id = $canonicalObjectiveId
        live_task_id = $liveTaskId
        active_task = $activeTask
        next_action = $nextAction
        invalidated_objectives = @((Get-PropertyValue -InputObject $authorityReset -PropertyName 'invalidated_objectives' -Default @()) | ForEach-Object { [string]$_ })
        bridge_status = [string](Get-PropertyValue -InputObject (Get-PropertyValue -InputObject $IntegrationStatus -PropertyName 'bridge_canonical_evidence' -Default $null) -PropertyName 'status' -Default '')
    }
}

function Get-InitiativeContext {
    param(
        $CurrentBuildState,
        $NextStepConsensus,
        $DurableMemory,
        $CanonicalContext,
        [string]$ResolvedObjectiveId,
        [string]$MaintenanceStatus,
        [string]$MaintenanceSeverity,
        [string]$WatchdogState
    )

    $executionReadiness = Get-PropertyValue -InputObject $CurrentBuildState -PropertyName 'execution_readiness' -Default $null
    $readinessStatus = [string](Get-PropertyValue -InputObject $executionReadiness -PropertyName 'status' -Default '')
    $readinessReason = [string](Get-PropertyValue -InputObject $executionReadiness -PropertyName 'reason' -Default '')
    $readinessDetail = [string](Get-PropertyValue -InputObject $executionReadiness -PropertyName 'detail' -Default '')
    $currentTask = [string](Get-PropertyValue -InputObject $CurrentBuildState -PropertyName 'task' -Default '')
    $consensusStatus = [string](Get-PropertyValue -InputObject $NextStepConsensus -PropertyName 'status' -Default '')
    $consensusBlock = Get-PropertyValue -InputObject $NextStepConsensus -PropertyName 'consensus' -Default $null
    $consensusAction = [string](Get-PropertyValue -InputObject $consensusBlock -PropertyName 'action' -Default '')
    $consensusReason = [string](Get-PropertyValue -InputObject $consensusBlock -PropertyName 'reason' -Default '')
    $commitmentObjectiveId = [string](Get-PropertyValue -InputObject $DurableMemory.latest_commitment -PropertyName 'objective_id' -Default '')
    $consensusObjectiveId = [string](Get-PropertyValue -InputObject $NextStepConsensus -PropertyName 'objective_id' -Default '')
    $durableObjectiveId = Get-FirstNonEmptyValue @(
        $ResolvedObjectiveId,
        $commitmentObjectiveId,
        $consensusObjectiveId,
        (Get-PropertyValue -InputObject $CurrentBuildState -PropertyName 'latest_objective_completed' -Default '')
    )
    $durableActiveTask = Get-FirstNonEmptyValue @(
        $currentTask,
        (Get-PropertyValue -InputObject $DurableMemory.latest_commitment -PropertyName 'action' -Default ''),
        $consensusAction,
        (Get-PropertyValue -InputObject $DurableMemory.latest_reasoning -PropertyName 'recommended_next_step' -Default ''),
        'execution reliability stabilization'
    )
    $useCanonicalTruth = [bool](Get-PropertyValue -InputObject $CanonicalContext -PropertyName 'available' -Default $false) -and (
        (Test-ObjectiveMismatch -LocalObjectiveId $commitmentObjectiveId -CanonicalObjectiveId ([string](Get-PropertyValue -InputObject $CanonicalContext -PropertyName 'objective_id' -Default '')) -InvalidatedObjectives @((Get-PropertyValue -InputObject $CanonicalContext -PropertyName 'invalidated_objectives' -Default @()))) -or
        (Test-ObjectiveMismatch -LocalObjectiveId $consensusObjectiveId -CanonicalObjectiveId ([string](Get-PropertyValue -InputObject $CanonicalContext -PropertyName 'objective_id' -Default '')) -InvalidatedObjectives @((Get-PropertyValue -InputObject $CanonicalContext -PropertyName 'invalidated_objectives' -Default @()))) -or
        ($durableActiveTask -match 'Refresh Governance Snapshot')
    )
    $objectiveId = if ($useCanonicalTruth) { [string](Get-PropertyValue -InputObject $CanonicalContext -PropertyName 'objective_id' -Default '') } else { $durableObjectiveId }
    $activeTask = if ($useCanonicalTruth) {
        Get-FirstNonEmptyValue @(
            (Get-PropertyValue -InputObject $CanonicalContext -PropertyName 'active_task' -Default ''),
            $durableActiveTask
        )
    }
    else {
        $durableActiveTask
    }

    $blocker = ''
    $nextAction = ''
    $autonomyMode = 'active_execution'
    $plan = ''

    if ([string]::Equals($readinessStatus, 'stale', [System.StringComparison]::OrdinalIgnoreCase)) {
        $blocker = Get-FirstNonEmptyValue @($readinessDetail, $readinessReason, 'execution readiness is stale')
        $nextAction = Get-FirstNonEmptyValue @(
            (Get-PropertyValue -InputObject $CanonicalContext -PropertyName 'next_action' -Default ''),
            (Get-PropertyValue -InputObject $DurableMemory.latest_reasoning -PropertyName 'recommended_next_step' -Default ''),
            'refresh execution readiness and continue canonical work'
        )
        $activeTask = Get-FirstNonEmptyValue @($nextAction, $activeTask)
        $autonomyMode = 'recovery_forward'
        $plan = if ($useCanonicalTruth) { 'Refresh the stale execution artifact, then resume the canonical live task request instead of reviving superseded objective memory.' } else { 'Refresh the stale execution artifact, rerun execution readiness, and then continue with the best ready task instead of waiting in place.' }
    }
    elseif ($useCanonicalTruth) {
        $blocker = Get-FirstNonEmptyValue @(
            'local durable-memory or consensus context is stale relative to canonical bridge truth',
            $consensusReason
        )
        $nextAction = Get-FirstNonEmptyValue @(
            (Get-PropertyValue -InputObject $CanonicalContext -PropertyName 'next_action' -Default ''),
            $consensusAction,
            'continue canonical bounded execution'
        )
        $autonomyMode = 'canonical_forward'
        $plan = 'Honor canonical bridge truth, treat superseded objective memory as stale, and continue with the live bounded task instead of re-centering on objective 170.'
    }
    elseif ($consensusStatus -match 'pending') {
        $blocker = Get-FirstNonEmptyValue @($consensusReason, 'cross-system consensus is still pending')
        $nextAction = Get-FirstNonEmptyValue @($consensusAction, (Get-PropertyValue -InputObject $DurableMemory.latest_reasoning -PropertyName 'recommended_next_step' -Default ''), 'proceed with a provisional local decision')
        $autonomyMode = 'provisional_forward'
        $plan = 'If consensus stays pending past the local timeout, continue with a provisional local decision and mark the action provisional instead of stalling.'
    }
    else {
        $nextAction = Get-FirstNonEmptyValue @((Get-PropertyValue -InputObject $DurableMemory.latest_reasoning -PropertyName 'recommended_next_step' -Default ''), $consensusAction, $activeTask)
        $plan = 'Continue the active task, expose the next step clearly, and escalate only if a real blocker or human approval is required.'
    }

    if ([string]::Equals($MaintenanceSeverity, 'critical', [System.StringComparison]::OrdinalIgnoreCase) -or [string]::Equals($WatchdogState, 'error', [System.StringComparison]::OrdinalIgnoreCase)) {
        $autonomyMode = if ($autonomyMode -eq 'active_execution') { 'stabilization_forward' } else { $autonomyMode }
        if ([string]::IsNullOrWhiteSpace($blocker)) {
            $blocker = "system health is $MaintenanceStatus / $MaintenanceSeverity with watchdog $WatchdogState"
        }
    }

    $initiativeSummary = "Active task: $activeTask. Next action: $nextAction."
    if (-not [string]::IsNullOrWhiteSpace($blocker)) {
        $initiativeSummary += " Current blocker: $blocker."
    }
    $initiativeSummary += " Plan: $plan"

    [pscustomobject]@{
        objective_id = $objectiveId
        active_task = $activeTask
        next_action = $nextAction
        blocker = $blocker
        autonomy_mode = $autonomyMode
        summary = $initiativeSummary
        plan = $plan
    }
}

function Get-ListenerRuntimeContext {
    param(
        $ListenerRequest,
        $ListenerResult,
        $ListenerCommandStatus,
        $ListenerDecision,
        $CanonicalContext,
        $Initiative
    )

    $activeRequestId = Get-FirstNonEmptyValue @(
        (Get-PropertyValue -InputObject $ListenerDecision -PropertyName 'request_id' -Default ''),
        (Get-PropertyValue -InputObject $ListenerCommandStatus -PropertyName 'request_id' -Default ''),
        (Get-PropertyValue -InputObject $ListenerRequest -PropertyName 'request_id' -Default ''),
        (Get-PropertyValue -InputObject $ListenerRequest -PropertyName 'task_id' -Default '')
    )
    $activeObjective = Get-FirstNonEmptyValue @(
        (Get-PropertyValue -InputObject $ListenerDecision -PropertyName 'requested_objective_id' -Default ''),
        (Get-PropertyValue -InputObject $ListenerResult -PropertyName 'objective_id' -Default ''),
        (Get-PropertyValue -InputObject $ListenerRequest -PropertyName 'objective_id' -Default ''),
        (Get-PropertyValue -InputObject $CanonicalContext -PropertyName 'objective_id' -Default '')
    )
    $decisionOutcome = [string](Get-PropertyValue -InputObject $ListenerDecision -PropertyName 'decision_outcome' -Default '')
    $bridgeStatus = Get-FirstNonEmptyValue @(
        (Get-PropertyValue -InputObject $ListenerCommandStatus -PropertyName 'status' -Default ''),
        (Get-PropertyValue -InputObject $CanonicalContext -PropertyName 'bridge_status' -Default '')
    )
    $lastCompletedAction = ''
    $resultStatus = [string](Get-PropertyValue -InputObject $ListenerResult -PropertyName 'status' -Default '')
    if (@('completed', 'succeeded') -contains $resultStatus.ToLowerInvariant()) {
        $lastCompletedAction = [string](Get-PropertyValue -InputObject $ListenerResult -PropertyName 'action' -Default '')
    }
    $blockerClassification = [string](Get-PropertyValue -InputObject $ListenerDecision -PropertyName 'blocker_classification' -Default '')
    $blocker = Get-FirstNonEmptyValue @(
        (Get-PropertyValue -InputObject $ListenerDecision -PropertyName 'summary' -Default ''),
        (Get-PropertyValue -InputObject $Initiative -PropertyName 'blocker' -Default '')
    )
    $nextAction = Get-FirstNonEmptyValue @(
        (Get-PropertyValue -InputObject $ListenerDecision -PropertyName 'next_step_recommendation' -Default ''),
        (Get-PropertyValue -InputObject $Initiative -PropertyName 'next_action' -Default ''),
        (Get-PropertyValue -InputObject $ListenerResult -PropertyName 'action' -Default '')
    )

    $summaryParts = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($activeRequestId)) {
        [void]$summaryParts.Add(("active request is {0}" -f $activeRequestId))
    }
    if (-not [string]::IsNullOrWhiteSpace($decisionOutcome)) {
        [void]$summaryParts.Add(("decision is {0}" -f $decisionOutcome))
    }
    if (-not [string]::IsNullOrWhiteSpace($bridgeStatus)) {
        [void]$summaryParts.Add(("bridge status is {0}" -f $bridgeStatus))
    }
    if (-not [string]::IsNullOrWhiteSpace($lastCompletedAction)) {
        [void]$summaryParts.Add(("last completed action is {0}" -f $lastCompletedAction))
    }
    if (-not [string]::IsNullOrWhiteSpace($nextAction)) {
        [void]$summaryParts.Add(("next action is {0}" -f $nextAction))
    }

    [pscustomobject]@{
        available = (-not [string]::IsNullOrWhiteSpace($activeRequestId) -or -not [string]::IsNullOrWhiteSpace($decisionOutcome) -or -not [string]::IsNullOrWhiteSpace($bridgeStatus))
        active_request_id = $activeRequestId
        active_objective_id = $activeObjective
        decision_outcome = $decisionOutcome
        bridge_status = $bridgeStatus
        blocker = $blocker
        blocker_classification = $blockerClassification
        last_completed_action = $lastCompletedAction
        next_action = $nextAction
        summary = if (@($summaryParts).Count -gt 0) { (($summaryParts -join '; ') + '.') } else { 'No live listener runtime artifact is available yet.' }
    }
}

$resolvedProviderConfigPath = Resolve-RepoPath -PathValue $ProviderConfigPath
$resolvedCurrentBuildStatePath = Resolve-RepoPath -PathValue $CurrentBuildStatePath
$resolvedIntegrationStatusPath = Resolve-RepoPath -PathValue $IntegrationStatusPath
$resolvedObjectivesPath = Resolve-RepoPath -PathValue $ObjectivesPath
$resolvedMaintenancePath = Resolve-RepoPath -PathValue $MaintenancePath
$resolvedWatchdogPath = Resolve-RepoPath -PathValue $WatchdogPath
$resolvedNextStepConsensusPath = Resolve-RepoPath -PathValue $NextStepConsensusPath
$resolvedMimWallStatePath = Resolve-RepoPath -PathValue $MimWallStatePath
$resolvedCommitmentPath = Resolve-RepoPath -PathValue $CommitmentPath
$resolvedReasoningPath = Resolve-RepoPath -PathValue $ReasoningPath
$resolvedActionAuditPath = Resolve-RepoPath -PathValue $ActionAuditPath
$resolvedListenerRequestPath = Resolve-RepoPath -PathValue $ListenerRequestPath
$resolvedListenerResultPath = Resolve-RepoPath -PathValue $ListenerResultPath
$resolvedListenerCommandStatusPath = Resolve-RepoPath -PathValue $ListenerCommandStatusPath
$resolvedListenerDecisionPath = Resolve-RepoPath -PathValue $ListenerDecisionPath
$script:resolvedTodConfigPath = if ([string]::IsNullOrWhiteSpace($TodConfigPath)) { '' } else { Resolve-RepoPath -PathValue $TodConfigPath }
$script:resolvedTodStatePath = if ([string]::IsNullOrWhiteSpace($TodStatePath)) { '' } else { Resolve-RepoPath -PathValue $TodStatePath }

$voiceConfig = Read-JsonFileSafe -PathValue $resolvedProviderConfigPath
$currentBuildState = Read-JsonFileSafe -PathValue $resolvedCurrentBuildStatePath
$integrationStatus = Read-JsonFileSafe -PathValue $resolvedIntegrationStatusPath
$objectivesDoc = Read-JsonFileSafe -PathValue $resolvedObjectivesPath
$maintenance = Read-JsonFileSafe -PathValue $resolvedMaintenancePath
$watchdog = Read-JsonFileSafe -PathValue $resolvedWatchdogPath
$nextStepConsensus = Read-JsonFileSafe -PathValue $resolvedNextStepConsensusPath
$mimWallState = Read-JsonFileSafe -PathValue $resolvedMimWallStatePath
$latestCommitment = Read-JsonFileSafe -PathValue $resolvedCommitmentPath
$latestReasoning = Read-JsonFileSafe -PathValue $resolvedReasoningPath
$latestActionAudit = Read-JsonFileSafe -PathValue $resolvedActionAuditPath
$listenerRequest = Read-JsonFileSafe -PathValue $resolvedListenerRequestPath
$listenerResult = Read-JsonFileSafe -PathValue $resolvedListenerResultPath
$listenerCommandStatus = Read-JsonFileSafe -PathValue $resolvedListenerCommandStatusPath
$listenerDecision = Read-JsonFileSafe -PathValue $resolvedListenerDecisionPath

$intentRoute = Get-IntentRoute -QueryText $Query
$requestKind = [string]$intentRoute.request_kind
$resolvedObjectiveId = if (-not [string]::IsNullOrWhiteSpace($ObjectiveId)) { [string]$ObjectiveId } else { [string](Get-PropertyValue -InputObject $currentBuildState -PropertyName 'objective_id' -Default '') }
$conversationHistory = Get-ConversationHistoryEntries -HistoryJson $ConversationHistoryJson
$communicationSkills = Get-CommunicationSkills -VoiceConfig $voiceConfig
$boundedSteps = Get-BoundedSteps -RequestKind $requestKind
$durableMemory = Get-DurableMemoryContext -Commitment $latestCommitment -Reasoning $latestReasoning -ActionAudit $latestActionAudit
$canonicalContext = Get-CanonicalConversationContext -CurrentBuildState $currentBuildState -IntegrationStatus $integrationStatus -ActionAudit $latestActionAudit

if ([string]::IsNullOrWhiteSpace($resolvedObjectiveId) -and [bool]$canonicalContext.available) {
    $resolvedObjectiveId = [string]$canonicalContext.objective_id
}

$maintenanceStatus = [string](Get-PropertyValue -InputObject $maintenance -PropertyName 'overall_status' -Default 'unknown')
$maintenanceSeverity = [string](Get-PropertyValue -InputObject $maintenance -PropertyName 'overall_severity' -Default 'unknown')
$watchdogState = [string](Get-PropertyValue -InputObject $watchdog -PropertyName 'state' -Default 'unknown')
$conversationMemory = Get-ConversationMemoryContext -Operator $OperatorName -HistoryEntries $conversationHistory
$mimWallQueueCount = [int](Get-PropertyValue -InputObject $mimWallState -PropertyName 'queue_count' -Default 0)
$mimWallProjectedEventCount = [int](Get-PropertyValue -InputObject $mimWallState -PropertyName 'projected_event_count' -Default 0)

$mimWallStatus = [pscustomobject]@{
    available = ($null -ne $mimWallState)
    queue_count = $mimWallQueueCount
    projected_event_count = $mimWallProjectedEventCount
    mode = [string](Get-PropertyValue -InputObject $mimWallState -PropertyName 'mode' -Default '')
    upstream_generated_at = [string](Get-PropertyValue -InputObject $mimWallState -PropertyName 'upstream_generated_at' -Default '')
    summary = if ($null -ne $mimWallState) {
        "mim_wall import is active with $mimWallQueueCount queue item(s) and $mimWallProjectedEventCount projected event(s)."
    }
    else {
        'mim_wall import has been implemented, but no local summary artifact is available yet.'
    }
}

$objectiveSummary = Get-ObjectiveSummaryText -CurrentBuildState $currentBuildState -ObjectivesDoc $objectivesDoc -ResolvedObjectiveId $resolvedObjectiveId
$initiative = Get-InitiativeContext -CurrentBuildState $currentBuildState -NextStepConsensus $nextStepConsensus -DurableMemory $durableMemory -CanonicalContext $canonicalContext -ResolvedObjectiveId $resolvedObjectiveId -MaintenanceStatus $maintenanceStatus -MaintenanceSeverity $maintenanceSeverity -WatchdogState $watchdogState
$listenerRuntime = Get-ListenerRuntimeContext -ListenerRequest $listenerRequest -ListenerResult $listenerResult -ListenerCommandStatus $listenerCommandStatus -ListenerDecision $listenerDecision -CanonicalContext $canonicalContext -Initiative $initiative
$currentWork = [pscustomobject]@{
    objective_id = $resolvedObjectiveId
    objective_summary = $objectiveSummary
    operator_name = $conversationMemory.operator_name
    active_task = $initiative.active_task
    next_action = $initiative.next_action
    blocker = $initiative.blocker
    initiative_summary = $initiative.summary
    listener_runtime = $listenerRuntime
    maintenance_status = $maintenanceStatus
    maintenance_severity = $maintenanceSeverity
    watchdog_state = $watchdogState
    canonical_context = $canonicalContext
    durable_memory_summary = [string]$durableMemory.summary
    mim_wall = $mimWallStatus
}

$providerStatus = [pscustomobject]@{
    attempted = $false
    succeeded = $false
    source = 'bounded_fallback'
    detail = 'Conversation model was not attempted.'
}

$commandDispatch = [pscustomobject]@{
    attempted = $false
    created = $false
    dispatched = $false
    objective_id = $resolvedObjectiveId
    task_id = ''
    title = ''
    task_category = ''
    detail = ''
}

$systemDispatch = [pscustomobject]@{
    attempted = $false
    created = $false
    dispatched = $false
    executed = $false
    action_name = ''
    action_kind = ''
    objective_id = $resolvedObjectiveId
    task_id = ''
    title = ''
    task_category = ''
    detail = ''
    payload = $null
}

$replyText = ''
$limitations = New-Object System.Collections.Generic.List[string]
$useFastBoundedReply = [string]::Equals($requestKind, 'status_request', [System.StringComparison]::OrdinalIgnoreCase) -or [string]::Equals([string]$intentRoute.intent, 'COMMAND', [System.StringComparison]::OrdinalIgnoreCase) -or [string]::Equals([string]$intentRoute.intent, 'SYSTEM', [System.StringComparison]::OrdinalIgnoreCase)

if ([string]::Equals([string]$intentRoute.intent, 'COMMAND', [System.StringComparison]::OrdinalIgnoreCase)) {
    $commandDispatch = Invoke-IntentCommandDispatch -IntentRoute $intentRoute -ResolvedObjectiveId $resolvedObjectiveId -QueryText $Query
}
elseif ([string]::Equals([string]$intentRoute.intent, 'SYSTEM', [System.StringComparison]::OrdinalIgnoreCase)) {
    $systemDispatch = Invoke-IntentSystemDispatch -IntentRoute $intentRoute -ResolvedObjectiveId $resolvedObjectiveId -QueryText $Query
}

if ($SkipModel) {
    [void]$limitations.Add('Local conversation provider was skipped intentionally for this run.')
}
elseif ($useFastBoundedReply) {
    [void]$limitations.Add('Local conversation provider was skipped for a fast status reply so TOD can answer current-work questions without timing out the UI lane.')
    $providerStatus.detail = 'Fast bounded status reply selected.'
}
elseif (-not (Test-Path -Path $conversationProviderScript)) {
    [void]$limitations.Add('Local conversation provider script is missing, so TOD used a bounded fallback reply.')
}
else {
    try {
        $providerStatus.attempted = $true
        $skillsSummary = @($communicationSkills | ForEach-Object { "- {0}: {1}. {2}" -f [string]$_.name, [string]$_.status, [string]$_.summary }) -join "`n"
        $stepsSummary = @($boundedSteps | ForEach-Object { "{0}. {1} - {2}" -f [int]$_.id, [string]$_.title, [string]$_.summary }) -join "`n"
        $providerPrompt = @"
You are TOD speaking directly to your operator.

Operator name: $($conversationMemory.operator_name)
Intent: $($intentRoute.intent)
Target: $($intentRoute.target)
Action route: $($intentRoute.action)
Operator request kind: $requestKind
Operator query: $Query

Use the supplied facts exactly.
If the request kind is implementation_request, explicitly say: This is an implementation request.
If the request kind is status_request or general_request, answer like a direct chat reply instead of a report.
Never say you cannot, you can't, you are unable, or that you do not have the ability.
Never end with only a problem statement. If TOD is blocked or unhealthy, include the action already being pursued next.
Then answer in four short parts:
1. Current work.
2. Initiative and next action.
3. Durable memory / who you are talking to.
4. Communication skills or bounded steps, whichever is more useful.

Do not omit the bounded steps.
Do not invent missing data.
Keep it concise but specific.
"@
        $providerObjectiveSummary = @"
    $($conversationMemory.summary)
$objectiveSummary
    Initiative: $($initiative.summary)
Maintenance: $maintenanceStatus ($maintenanceSeverity)
Watchdog: $watchdogState
mim_wall: $($mimWallStatus.summary)
Durable memory: $($durableMemory.summary)
Trust chain: $($durableMemory.trust_chain_summary)
Listener runtime: $($listenerRuntime.summary)
Communication skills:
$skillsSummary
Bounded steps:
$stepsSummary
"@
        $providerReply = & $conversationProviderScript -Action chat -Prompt $providerPrompt -ObjectiveSummary $providerObjectiveSummary -TaskState $requestKind -ObjectiveId $resolvedObjectiveId -AsJson | ConvertFrom-Json
        if ($providerReply -and [bool]$providerReply.ok -and (Test-ProviderReplyUsable -ReplyText ([string]$providerReply.reply_text) -RequestKind $requestKind)) {
            $replyText = [string]$providerReply.reply_text
            $providerStatus.succeeded = $true
            $providerStatus.source = 'local_conversation_provider'
            $providerStatus.detail = 'Direct TOD reply generated by the local conversation provider.'
        }
        else {
            $strictPrompt = @"
Rewrite the answer using these exact headings:
Current Work:
Communication Skills:
Durable Memory:
Bounded Steps:

Requirements:
- If this is an implementation_request, start with: This is an implementation request.
- Mention the latest commitment state, latest reasoning next step, and trust chain availability.
- Include the numbered bounded steps.
- Keep it under 220 words.
"@
            $strictReply = & $conversationProviderScript -Action chat -Prompt $strictPrompt -ObjectiveSummary $providerObjectiveSummary -TaskState $requestKind -ObjectiveId $resolvedObjectiveId -AsJson | ConvertFrom-Json
            if ($strictReply -and [bool]$strictReply.ok -and (Test-ProviderReplyUsable -ReplyText ([string]$strictReply.reply_text) -RequestKind $requestKind)) {
                $replyText = [string]$strictReply.reply_text
                $providerStatus.succeeded = $true
                $providerStatus.source = 'local_conversation_provider'
                $providerStatus.detail = 'Direct TOD reply generated by the local conversation provider after a stricter rewrite pass.'
            }
            else {
                [void]$limitations.Add('Local conversation provider replied, but the answer did not satisfy the direct TOD quality contract, so TOD used a bounded fallback reply.')
            }
        }
    }
    catch {
        [void]$limitations.Add(("Local conversation provider was unavailable, so TOD used a bounded fallback reply. {0}" -f $_.Exception.Message))
        $providerStatus.succeeded = $false
        $providerStatus.source = 'bounded_fallback'
        $providerStatus.detail = [string]$_.Exception.Message
    }
}

if ([string]::IsNullOrWhiteSpace($replyText)) {
    $stepSummary = @($boundedSteps | ForEach-Object { "{0}) {1}" -f [int]$_.id, [string]$_.title }) -join '; '
    $operatorLead = if ([string]::IsNullOrWhiteSpace($conversationMemory.operator_name)) { 'Operator' } else { $conversationMemory.operator_name }
    $blockerText = if ([string]::IsNullOrWhiteSpace($initiative.blocker)) { 'no hard blocker is active.' } else { "$($initiative.blocker)." }
    if ([string]::Equals([string]$intentRoute.intent, 'COMMAND', [System.StringComparison]::OrdinalIgnoreCase)) {
        $dispatchDetail = if ($commandDispatch.created) {
            ('task {0} created under {1}; classification {2}; next step {3}; codex_needed={4}' -f $commandDispatch.task_id, $commandDispatch.objective_id, $commandDispatch.classification, $commandDispatch.next_step, $commandDispatch.codex_needed.ToString().ToLowerInvariant())
        }
        else {
            [string]$commandDispatch.detail
        }
        $replyText = "intent: COMMAND`ntarget: $($intentRoute.target)`naction: $($intentRoute.action)`nobjective: $($commandDispatch.objective_id)`ntask_id: $($commandDispatch.task_id)`nrequest_id: $($commandDispatch.request_id)`nclassification: $($commandDispatch.classification)`nnext: $($commandDispatch.next_step)`ncodex_needed: $($commandDispatch.codex_needed.ToString().ToLowerInvariant())`ndispatch: $dispatchDetail"
    }
    elseif ([string]::Equals([string]$intentRoute.intent, 'DIAGNOSTIC', [System.StringComparison]::OrdinalIgnoreCase)) {
        $replyText = "intent: DIAGNOSTIC`ntarget: $($intentRoute.target)`naction: $($intentRoute.action)`nsummary: $($currentWork.initiative_summary)`nruntime: $($listenerRuntime.summary)"
    }
    elseif ([string]::Equals([string]$intentRoute.intent, 'SYSTEM', [System.StringComparison]::OrdinalIgnoreCase)) {
        $systemDetail = if ($systemDispatch.executed -or $systemDispatch.created) {
            if (-not [string]::IsNullOrWhiteSpace([string]$systemDispatch.task_id)) {
                'task ' + $systemDispatch.task_id + ' is in the system-control lane.'
            }
            else {
                [string]$systemDispatch.detail
            }
        }
        else {
            [string]$systemDispatch.detail
        }
        $replyText = "intent: SYSTEM`ntarget: $($intentRoute.target)`naction: $($intentRoute.action)`ncontrol: $systemDetail`nnext: $($initiative.next_action)`nplan: $($initiative.plan)"
    }
    elseif ([string]::Equals($requestKind, 'implementation_request', [System.StringComparison]::OrdinalIgnoreCase)) {
        $replyText = "This is an implementation request, $operatorLead. I am currently focused on $($initiative.active_task) under objective $($initiative.objective_id). My next forward action is $($initiative.next_action). If a blocker remains, I will not stop at the blocker state: $($initiative.plan) I know I am talking to $($conversationMemory.operator_name), and my recent browser memory is: $($conversationMemory.summary) The bounded path I am following is: $stepSummary."
    }
    else {
        if ([bool]$listenerRuntime.available) {
            $replyText = "$operatorLead, I'm currently working on $($initiative.active_task) under objective $($initiative.objective_id). The active request is $($listenerRuntime.active_request_id), bridge status is $($listenerRuntime.bridge_status), and my next step is $($listenerRuntime.next_action). Last completed action: $($listenerRuntime.last_completed_action). $($initiative.plan) I know I'm talking to $($conversationMemory.operator_name). $($conversationMemory.summary) Runtime truth says: $($listenerRuntime.summary) Key blocker context: $blockerText"
        }
        else {
            $replyText = "$operatorLead, I'm currently working on $($initiative.active_task) under objective $($initiative.objective_id). My next step is $($initiative.next_action). $($initiative.plan) I know I'm talking to $($conversationMemory.operator_name). $($conversationMemory.summary) Right now the key blocker context is: $blockerText"
        }
    }
}

$payload = [pscustomobject]@{
    ok = $true
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    intent = $intentRoute
    request_kind = $requestKind
    reply_text = $replyText
    source = [string]$providerStatus.source
    provider_status = $providerStatus
    command_dispatch = $commandDispatch
    system_dispatch = $systemDispatch
    operator = $conversationMemory
    current_work = $currentWork
    initiative = $initiative
    conversation_memory = $conversationMemory
    durable_memory = $durableMemory
    canonical_context = $canonicalContext
    listener_runtime = $listenerRuntime
    communication_skills = @($communicationSkills)
    bounded_steps = @($boundedSteps)
    mim_wall_status = $mimWallStatus
    limitations = @($limitations)
}

if ($AsJson) {
    $payload | ConvertTo-Json -Depth 20
}
else {
    $payload
}