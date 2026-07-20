param(
    [string]$EnvFile = ".env",
    [string]$RemoteRoot = "/home/testpilot/mim/runtime/shared",
    [string]$StageDir = "tod/out/context-sync/listener",
    [string]$IncomingProjectInboxDir = "tod/inbox/context-sync/project-handoff",
    [int]$IncomingProjectInboxKeepPerArtifact = 10,
    [int]$IncomingProjectInboxMaxAgeDays = 7,
    [string]$SyncStageDir = "tod/out/context-sync/ssh-shared",
    [string]$SyncScriptPath = "scripts/Invoke-TODSharedStateSync.ps1",
    [string]$TodScriptPath = "scripts/TOD.ps1",
    [string]$ReadinessScriptPath = "scripts/Test-TODOperatorChatSweepArtifact.ps1",
    [string]$ValidatorScriptPath = "scripts/Invoke-TODMimListenerValidator.ps1",
    [string]$DialogScriptPath = "scripts/Invoke-TODMimDialog.ps1",
    [string]$RuntimeContractValidatorScriptPath = "scripts/validate_tod_mim_runtime_packet.py",
    [string]$ContractSourceDir = "tod/out/context-sync/contracts",
    [int]$PollSeconds = 30,
    [int]$RegressionNoDeltaThreshold = 4,
    [int]$QuarantineFailCycleThreshold = 5,
    [int]$IdleWakeupSeconds = 120,
    [int]$IdleWakeupCooldownSeconds = 300,
    [int]$StatusPublishSeconds = 15,
    [switch]$RunOnce,
    [switch]$ProcessWithoutGoOrder,
    [switch]$PublishIntegrationStatus,
    [switch]$PublishDialogRemote,
    [switch]$FailOnError
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$scriptVersion = "2026-03-30T15:20Z"
$script:ListenerMutexName = "Global\TOD-MimPacketListener"
$script:ListenerMutexFallbackName = "Local\TOD-MimPacketListener"

$repoRoot = Split-Path -Parent $PSScriptRoot

function Get-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) { return $PathValue }
    return (Join-Path $repoRoot $PathValue)
}

function New-ListenerMutexHandle {
    param(
        [Parameter(Mandatory = $true)][string]$PreferredName,
        [Parameter(Mandatory = $true)][string]$FallbackName
    )

    try {
        return [pscustomobject]@{
            mutex = (New-Object System.Threading.Mutex($false, $PreferredName))
            name = $PreferredName
            scope = 'global'
        }
    }
    catch [System.UnauthorizedAccessException] {
        return [pscustomobject]@{
            mutex = (New-Object System.Threading.Mutex($false, $FallbackName))
            name = $FallbackName
            scope = 'local'
        }
    }
}

function Get-DotEnvValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if (-not (Test-Path -Path $Path)) { return "" }

    $line = Get-Content -Path $Path | Where-Object {
        $_ -match ("^\s*{0}\s*=" -f [regex]::Escape($Name))
    } | Select-Object -First 1

    if ([string]::IsNullOrWhiteSpace([string]$line)) { return "" }

    return ([string]($line -replace ("^\s*{0}\s*=\s*" -f [regex]::Escape($Name)), "")).Trim()
}

function Resolve-SshHostAlias {
    param([Parameter(Mandatory = $true)][string]$RemoteHost)

    if ($RemoteHost -match "^\d{1,3}(?:\.\d{1,3}){3}$" -or $RemoteHost -match "\.") {
        return $RemoteHost
    }

    $sshConfigPath = Join-Path $HOME ".ssh/config"
    if (-not (Test-Path -Path $sshConfigPath)) {
        return $RemoteHost
    }

    $matchedHost = $false
    foreach ($rawLine in Get-Content -Path $sshConfigPath) {
        $line = [string]$rawLine
        $trim = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trim) -or $trim.StartsWith("#")) {
            continue
        }

        if ($trim -match "^(?i)Host\s+(.+)$") {
            $matchedHost = $false
            foreach ($token in @($matches[1] -split "\s+")) {
                if ([string]::Equals([string]$token, $RemoteHost, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $matchedHost = $true
                    break
                }
            }
            continue
        }

        if ($matchedHost -and $trim -match "^(?i)HostName\s+(.+)$") {
            return [string]$matches[1]
        }
    }

    return $RemoteHost
}

function Read-JsonFileIfExists {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if (-not (Test-Path -Path $PathValue)) { return $null }
    try {
        return (ConvertFrom-JsonCaseInsensitiveSafe -Text (Get-Content -Path $PathValue -Raw))
    }
    catch {
        return $null
    }
}

function Get-SafeDialogSessionId {
    param([Parameter(Mandatory = $true)][string]$Seed)

    $safe = ([string]$Seed).Trim()
    if ([string]::IsNullOrWhiteSpace($safe)) {
        $safe = 'tod-listener'
    }

    return ($safe -replace '[^a-zA-Z0-9._-]', '_')
}

function Limit-DialogSummary {
    param(
        [AllowNull()][string]$Text,
        [int]$MaxLength = 260
    )

    $value = ([string]$Text).Trim()
    if ($value.Length -le $MaxLength) {
        return $value
    }

    if ($MaxLength -le 3) {
        return $value.Substring(0, [Math]::Max(0, $MaxLength))
    }

    return ($value.Substring(0, $MaxLength - 3).TrimEnd() + '...')
}

function Invoke-DialogNotice {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptAbs,
        [Parameter(Mandatory = $true)][ValidateSet('send', 'close-session')][string]$Action,
        [Parameter(Mandatory = $true)][string]$SessionId,
        [Parameter(Mandatory = $true)][string]$MessageType,
        [Parameter(Mandatory = $true)][string]$Intent,
        [Parameter(Mandatory = $true)][string]$Summary,
        [Parameter(Mandatory = $true)]$Payload,
        [string]$TaskId = '',
        [string]$CorrelationId = '',
        [string]$EnvPath = '',
        [switch]$PublishRemote
    )

    if (-not (Test-Path -Path $ScriptAbs)) {
        return [pscustomobject]@{ ok = $false; status = 'dialog_script_missing' }
    }

    try {
        $payloadJson = $Payload | ConvertTo-Json -Depth 12 -Compress
        $invokeParams = @{
            Action = $Action
            SessionId = $SessionId
            Actor = 'TOD'
            PeerActor = 'MIM'
            MessageType = $MessageType
            Intent = $Intent
            Summary = $Summary
            PayloadJson = $payloadJson
            TaskId = $TaskId
            CorrelationId = $CorrelationId
            RequiresReply = $true
            EmitJson = $true
        }
        if (-not [string]::IsNullOrWhiteSpace($EnvPath) -and (Test-Path -Path $EnvPath)) {
            $invokeParams.DotEnvPath = $EnvPath
        }
        if ($PublishRemote) {
            $invokeParams.PublishRemote = $true
        }

        $null = & $ScriptAbs @invokeParams
        return [pscustomobject]@{ ok = $true; status = 'sent' }
    }
    catch {
        return [pscustomobject]@{ ok = $false; status = 'send_failed'; error = [string]$_.Exception.Message }
    }
}

function Invoke-TaskTroubleshootingGuidance {
    param(
        [Parameter(Mandatory = $true)][string]$ConversationProviderScriptAbs,
        [Parameter(Mandatory = $true)][string]$RequestId,
        [string]$ObjectiveId = '',
        [string]$TaskId = '',
        [string]$CorrelationId = '',
        [string]$Action = '',
        [AllowNull()]$Execution = $null,
        [AllowNull()]$DecisionPayload = $null,
        [AllowNull()]$ReviewGate = $null,
        [AllowNull()]$ValidatorResult = $null,
        [AllowNull()]$IntegrationStatus = $null
    )

    $executionBlocked = ($null -ne $Execution -and $Execution.PSObject.Properties['blocked'] -and [bool]$Execution.blocked)
    $executionOk = ($null -ne $Execution -and $Execution.PSObject.Properties['ok'] -and [bool]$Execution.ok)
    $reviewPassed = ($null -ne $ReviewGate -and $ReviewGate.PSObject.Properties['passed'] -and [bool]$ReviewGate.passed)
    $validatorPassed = ($null -ne $ValidatorResult -and $ValidatorResult.PSObject.Properties['passed'] -and [bool]$ValidatorResult.passed)
    $resultStatus = if ($executionBlocked) { 'blocked' } elseif ($executionOk -and $reviewPassed -and $validatorPassed) { 'succeeded' } else { 'failed' }
    if ([string]::Equals($resultStatus, 'succeeded', [System.StringComparison]::OrdinalIgnoreCase)) {
        return $null
    }

    $executionMode = if ($null -ne $Execution -and $Execution.PSObject.Properties['execution_mode']) { [string]$Execution.execution_mode } else { 'unknown' }
    $executionError = if ($null -ne $Execution -and $Execution.PSObject.Properties['error']) { [string]$Execution.error } else { '' }
    $resultReasonCode = if ($null -ne $Execution -and $Execution.PSObject.Properties['result_reason_code']) { [string]$Execution.result_reason_code } else { '' }
    $isMalformedBoundedEditPacket = [string]::Equals($resultReasonCode, 'malformed_bounded_edit_packet', [System.StringComparison]::OrdinalIgnoreCase) -or [string]::Equals($resultReasonCode, 'blocked_missing_bounded_edit_mode', [System.StringComparison]::OrdinalIgnoreCase)
    $decisionOutcome = if ($null -ne $DecisionPayload -and $DecisionPayload.PSObject.Properties['decision_outcome']) { [string]$DecisionPayload.decision_outcome } else { '' }
    $decisionReasonCode = if ($null -ne $DecisionPayload -and $DecisionPayload.PSObject.Properties['reason_code']) { [string]$DecisionPayload.reason_code } else { '' }
    $decisionNextStep = if ($null -ne $DecisionPayload -and $DecisionPayload.PSObject.Properties['next_step_recommendation']) { [string]$DecisionPayload.next_step_recommendation } else { '' }
    $alignmentStatus = if ($null -ne $IntegrationStatus -and $IntegrationStatus.PSObject.Properties['objective_alignment'] -and $IntegrationStatus.objective_alignment -and $IntegrationStatus.objective_alignment.PSObject.Properties['status']) { [string]$IntegrationStatus.objective_alignment.status } else { 'unknown' }
    $readinessStatus = if ($null -ne $Execution -and $Execution.PSObject.Properties['execution_readiness'] -and $Execution.execution_readiness -and $Execution.execution_readiness.PSObject.Properties['status']) { [string]$Execution.execution_readiness.status } else { 'unknown' }
    $outputPreview = if ($null -ne $Execution -and $Execution.PSObject.Properties['output'] -and -not [string]::IsNullOrWhiteSpace([string]$Execution.output)) { ([string]$Execution.output).Substring(0, [Math]::Min(800, ([string]$Execution.output).Length)) } else { '' }

    $fallbackLikelyCause = if ($executionBlocked) {
        'Execution was blocked by a local guardrail or missing dependency before TOD could complete the task.'
    }
    elseif (-not $reviewPassed) {
        'The task execution finished, but the review gate did not pass.'
    }
    elseif (-not $validatorPassed) {
        'The task execution finished, but the runtime validator rejected the result payload.'
    }
    elseif (-not [string]::IsNullOrWhiteSpace($executionError)) {
        'The underlying TOD action raised an execution error.'
    }
    else {
        'The task did not reach a clean success state and needs bounded troubleshooting.'
    }

    $fallbackGuidance = @(
        '1. Inspect the execution mode, error text, and readiness status to identify whether the failure is local execution, validation, or coordination related.',
        '2. Re-run the minimum freshness and readiness checks before retrying the task so TOD does not loop on stale inputs.',
        '3. If review or validator failed, repair that specific gate first instead of re-running the full task unchanged.',
        '4. Publish the blocker and the next bounded corrective action back to MIM so the task stays governed while troubleshooting continues.',
        '5. Retry only after the blocker clears and the authoritative objective alignment is still valid.'
    ) -join ' '

    $guidanceText = $fallbackGuidance
    $providerStatus = [pscustomobject]@{
        used = $false
        source = 'deterministic_fallback'
        detail = 'Local conversation provider was not used.'
        error = ''
    }

    if ($isMalformedBoundedEditPacket) {
        $fallbackLikelyCause = 'The request was rejected before the active lane because the bounded edit packet is malformed or missing required execution fields.'
        $guidanceText = 'Return this request to the originating authority for one corrected bounded edit packet. Required fields: target_file, edit_mode, anchor_or_old_text, new_text_or_snippet, validation_command, expected evidence, prevention lesson, and Dave-needed. Do not restore or mutate the active lane for a malformed packet; the gate is working as intended.'
        $providerStatus.detail = 'Provider bypassed because malformed bounded-edit packets require deterministic gate-correct recovery guidance.'
        $decisionNextStep = 'return_to_originating_authority_for_replan'
    }
    elseif (Test-Path -Path $ConversationProviderScriptAbs) {
        try {
            $prompt = @"
You are generating bounded troubleshooting guidance for TOD after a MIM-issued task did not succeed.

Return one concise paragraph followed by a numbered list with exactly 4 items.
Keep the answer under 220 words.
Focus on safe next steps, not broad redesign.

Context:
- request_id: $RequestId
- objective_id: $ObjectiveId
- task_id: $TaskId
- correlation_id: $CorrelationId
- action: $Action
- result_status: $resultStatus
- execution_mode: $executionMode
- execution_error: $executionError
- decision_outcome: $decisionOutcome
- decision_reason_code: $decisionReasonCode
- decision_next_step: $decisionNextStep
- readiness_status: $readinessStatus
- alignment_status: $alignmentStatus
- review_gate_passed: $reviewPassed
- validator_passed: $validatorPassed
- output_preview: $outputPreview

Required structure:
- likely cause
- first corrective check
- bounded repair step
- what TOD should report back to MIM next
"@

            $providerRaw = & $ConversationProviderScriptAbs -Action 'chat' -Prompt $prompt -ObjectiveSummary 'MIM task troubleshooting' -TaskState $resultStatus -ObjectiveId $ObjectiveId -AsJson
            $providerPayload = $null
            try {
                $providerPayload = ($providerRaw | ConvertFrom-Json)
            }
            catch {
                $providerPayload = $null
            }

            if ($providerPayload -and $providerPayload.PSObject.Properties['reply_text'] -and -not [string]::IsNullOrWhiteSpace([string]$providerPayload.reply_text)) {
                $guidanceText = ([string]$providerPayload.reply_text).Trim()
                $providerStatus.used = $true
                $providerStatus.source = 'local_conversation_provider'
                $providerStatus.detail = 'Troubleshooting guidance came from the OpenAI-compatible local conversation provider.'
            }
            else {
                $providerStatus.detail = 'Local conversation provider returned no troubleshooting guidance, so TOD used deterministic fallback guidance.'
            }
        }
        catch {
            $providerStatus.error = [string]$_.Exception.Message
            $providerStatus.detail = 'Local conversation provider failed during troubleshooting guidance generation, so TOD used deterministic fallback guidance.'
        }
    }
    else {
        $providerStatus.detail = 'Local conversation provider script is missing, so TOD used deterministic fallback guidance.'
    }

    return [pscustomobject]@{
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        source = 'tod-mim-task-troubleshooting-v1'
        request_id = $RequestId
        objective_id = $ObjectiveId
        task_id = $TaskId
        correlation_id = $CorrelationId
        action = $Action
        result_status = $resultStatus
        likely_cause = $fallbackLikelyCause
        guidance_text = $guidanceText
        recommended_report_back = if (-not [string]::IsNullOrWhiteSpace($decisionNextStep)) { $decisionNextStep } else { 'publish_blocker_and_next_bounded_step' }
        provider_status = $providerStatus
        execution = [pscustomobject]@{
            execution_mode = $executionMode
            readiness_status = $readinessStatus
            review_gate_passed = $reviewPassed
            validator_passed = $validatorPassed
            error = $executionError
        }
        decision = [pscustomobject]@{
            decision_outcome = $decisionOutcome
            reason_code = $decisionReasonCode
            next_step_recommendation = $decisionNextStep
        }
        integration = [pscustomobject]@{
            alignment_status = $alignmentStatus
        }
    }
}

function Publish-TaskTroubleshootingRequest {
    param(
        [Parameter(Mandatory = $true)][string]$DialogScriptAbs,
        [string]$EnvPath = '',
        [Parameter(Mandatory = $true)][string]$RequestId,
        [string]$ObjectiveId = '',
        [string]$TaskId = '',
        [string]$CorrelationId = '',
        [Parameter(Mandatory = $true)]$Troubleshooting,
        [AllowNull()]$Execution = $null,
        [AllowNull()]$DecisionPayload = $null,
        [switch]$PublishRemote
    )

    if ($null -eq $Troubleshooting) {
        return $null
    }

    if (-not (Test-Path -Path $DialogScriptAbs)) {
        return [pscustomobject]@{ ok = $false; status = 'dialog_script_missing'; session_id = '' }
    }

    $sessionId = ('tod-troubleshoot-' + [string]$RequestId) -replace '[^a-zA-Z0-9._-]', '_'
    $summary = if ($Troubleshooting.PSObject.Properties['likely_cause'] -and -not [string]::IsNullOrWhiteSpace([string]$Troubleshooting.likely_cause)) {
        'TOD needs troubleshooting help for request ' + [string]$RequestId + ': ' + [string]$Troubleshooting.likely_cause
    }
    else {
        'TOD needs troubleshooting help for request ' + [string]$RequestId + '.'
    }

    $payload = [pscustomobject]@{
        source = 'tod-listener-task-troubleshooting-request-v1'
        request_id = $RequestId
        objective_id = $ObjectiveId
        task_id = $TaskId
        correlation_id = $CorrelationId
        troubleshooting = $Troubleshooting
        execution = if ($null -ne $Execution) {
            [pscustomobject]@{
                ok = if ($Execution.PSObject.Properties['ok']) { [bool]$Execution.ok } else { $false }
                blocked = if ($Execution.PSObject.Properties['blocked']) { [bool]$Execution.blocked } else { $false }
                action = if ($Execution.PSObject.Properties['action']) { [string]$Execution.action } else { '' }
                execution_mode = if ($Execution.PSObject.Properties['execution_mode']) { [string]$Execution.execution_mode } else { '' }
                error = if ($Execution.PSObject.Properties['error']) { [string]$Execution.error } else { '' }
            }
        } else { $null }
        decision = if ($null -ne $DecisionPayload) {
            [pscustomobject]@{
                decision_outcome = if ($DecisionPayload.PSObject.Properties['decision_outcome']) { [string]$DecisionPayload.decision_outcome } else { '' }
                reason_code = if ($DecisionPayload.PSObject.Properties['reason_code']) { [string]$DecisionPayload.reason_code } else { '' }
                next_step_recommendation = if ($DecisionPayload.PSObject.Properties['next_step_recommendation']) { [string]$DecisionPayload.next_step_recommendation } else { '' }
            }
        } else { $null }
        requested_reply = [pscustomobject]@{
            needed = $true
            fields = @('missing_fields', 'missing_artifacts', 'repair_step', 'next_update')
        }
    }

    $boundedSummary = ([string]$summary).Trim()
    if ($boundedSummary.Length -gt 260) {
        $boundedSummary = $boundedSummary.Substring(0, 257).TrimEnd() + '...'
    }
    $dialogResult = Invoke-DialogNotice -ScriptAbs $DialogScriptAbs -Action 'send' -SessionId $sessionId -MessageType 'handoff_request' -Intent 'task_troubleshooting' -Summary $boundedSummary -Payload $payload -TaskId $TaskId -CorrelationId $CorrelationId -EnvPath $EnvPath -PublishRemote:$PublishRemote
    return [pscustomobject]@{
        ok = [bool]$dialogResult.ok
        status = [string]$dialogResult.status
        session_id = $sessionId
        message_type = 'handoff_request'
        intent = 'task_troubleshooting'
        error = if ($dialogResult.PSObject.Properties['error']) { [string]$dialogResult.error } else { '' }
    }
}

function Convert-JsonDeserializedValue {
    param([AllowNull()]$Value)

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [System.Collections.IDictionary]) {
        $map = [ordered]@{}
        foreach ($key in @($Value.Keys)) {
            $existingKey = $null
            foreach ($candidateKey in @($map.Keys)) {
                if ([string]::Equals([string]$candidateKey, [string]$key, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $existingKey = [string]$candidateKey
                    break
                }
            }

            if ($null -ne $existingKey) {
                $null = $map.Remove($existingKey)
            }

            $map[[string]$key] = Convert-JsonDeserializedValue -Value $Value[$key]
        }
        return [pscustomobject]$map
    }

    if (($Value -is [System.Collections.IEnumerable]) -and -not ($Value -is [string])) {
        return @($Value | ForEach-Object { Convert-JsonDeserializedValue -Value $_ })
    }

    return $Value
}

function ConvertFrom-JsonCaseInsensitiveSafe {
    param([Parameter(Mandatory = $true)][string]$Text)

    try {
        return ($Text | ConvertFrom-Json)
    }
    catch {
        Add-Type -AssemblyName System.Web.Extensions -ErrorAction Stop
        $serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
        return Convert-JsonDeserializedValue -Value ($serializer.DeserializeObject($Text))
    }
}

function Get-ObjectiveNumericValue {
    param([string]$ObjectiveId)

    $text = ([string]$ObjectiveId).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
        return -1
    }

    $match = [regex]::Match($text, '(?i)(?:^objective-(?<objective>\d+)$|^(?<objective>\d+)$)')
    if (-not $match.Success) {
        return -1
    }

    $numericValue = -1
    if (-not [int]::TryParse([string]$match.Groups['objective'].Value, [ref]$numericValue)) {
        return -1
    }

    return $numericValue
}

function Normalize-ObjectiveIdText {
    param([string]$ObjectiveId)

    $text = ([string]$ObjectiveId).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
        return ""
    }

    $numericValue = Get-ObjectiveNumericValue -ObjectiveId $text
    if ($numericValue -ge 0) {
        return [string]$numericValue
    }

    return $text
}

function Test-ObjectiveInvalidatedByAuthority {
    param(
        [string]$ObjectiveId,
        $AuthorityReset
    )

    $normalizedObjectiveId = Normalize-ObjectiveIdText -ObjectiveId $ObjectiveId
    if ([string]::IsNullOrWhiteSpace($normalizedObjectiveId) -or $null -eq $AuthorityReset) {
        return $false
    }

    if ($AuthorityReset.PSObject.Properties['active']) {
        try {
            if (-not [bool]$AuthorityReset.active) {
                return $false
            }
        }
        catch {
            return $false
        }
    }

    $explicitInvalidations = @()
    if ($AuthorityReset.PSObject.Properties['invalidated_objectives'] -and $null -ne $AuthorityReset.invalidated_objectives) {
        $explicitInvalidations = @($AuthorityReset.invalidated_objectives | ForEach-Object { Normalize-ObjectiveIdText -ObjectiveId ([string]$_) })
    }

    if (@($explicitInvalidations | Where-Object { [string]::Equals($_, $normalizedObjectiveId, [System.StringComparison]::OrdinalIgnoreCase) }).Count -gt 0) {
        return $true
    }

    $maxValidObjective = if ($AuthorityReset.PSObject.Properties['max_valid_objective']) { Normalize-ObjectiveIdText -ObjectiveId ([string]$AuthorityReset.max_valid_objective) } else { '' }
    $objectiveNumber = Get-ObjectiveNumericValue -ObjectiveId $normalizedObjectiveId
    $maxValidNumber = Get-ObjectiveNumericValue -ObjectiveId $maxValidObjective
    if ($objectiveNumber -ge 0 -and $maxValidNumber -ge 0 -and $objectiveNumber -gt $maxValidNumber) {
        return $true
    }

    return $false
}

function Get-RequestExecutorRole {
    param($Request)

    if ($null -eq $Request) {
        return 'codex'
    }

    $activeEngine = if ($Request.PSObject.Properties['active_engine']) { ([string]$Request.active_engine).Trim().ToLowerInvariant() } else { '' }
    $selectedExecutor = if ($Request.PSObject.Properties['selected_executor']) { ([string]$Request.selected_executor).Trim().ToLowerInvariant() } else { '' }
    $executorBinding = if ($Request.PSObject.Properties['executor_binding']) { ([string]$Request.executor_binding).Trim() } else { '' }
    $metadata = if ($Request.PSObject.Properties['metadata_json']) { $Request.metadata_json } else { $null }
    if ($metadata) {
        if ([string]::IsNullOrWhiteSpace($activeEngine) -and $metadata.PSObject.Properties['active_engine']) {
            $activeEngine = ([string]$metadata.active_engine).Trim().ToLowerInvariant()
        }
        if ([string]::IsNullOrWhiteSpace($selectedExecutor) -and $metadata.PSObject.Properties['selected_executor']) {
            $selectedExecutor = ([string]$metadata.selected_executor).Trim().ToLowerInvariant()
        }
        if ([string]::IsNullOrWhiteSpace($executorBinding) -and $metadata.PSObject.Properties['executor_binding']) {
            $executorBinding = ([string]$metadata.executor_binding).Trim()
        }
    }

    foreach ($propertyName in @('target_executor', 'assigned_executor', 'assigned_to', 'executor_role')) {
        if ($Request.PSObject.Properties[$propertyName] -and -not [string]::IsNullOrWhiteSpace([string]$Request.$propertyName)) {
            $role = ([string]$Request.$propertyName).Trim()
            if ([string]::Equals($role, 'local', [System.StringComparison]::OrdinalIgnoreCase) -and
                (@('local', 'tod_local', 'localexecutionengine') -contains $activeEngine -or @('local', 'tod_local', 'localexecutionengine') -contains $selectedExecutor) -and
                $executorBinding -match 'scripts[/\\]engines[/\\]LocalExecutionEngine\.ps1::Invoke-LocalExecutionEngine') {
                return 'tod'
            }
            return $role
        }
    }

    return 'codex'
}

function Get-RequestExecutionPolicyClass {
    param($Request)

    if ($null -eq $Request) {
        return ''
    }

    if ($Request.PSObject.Properties['execution_policy'] -and $null -ne $Request.execution_policy) {
        if ($Request.execution_policy.PSObject.Properties['class'] -and -not [string]::IsNullOrWhiteSpace([string]$Request.execution_policy.class)) {
            return ([string]$Request.execution_policy.class).Trim()
        }
        if ($Request.execution_policy.PSObject.Properties['boundary'] -and -not [string]::IsNullOrWhiteSpace([string]$Request.execution_policy.boundary)) {
            return ([string]$Request.execution_policy.boundary).Trim()
        }
    }

    foreach ($propertyName in @('execution_policy_class', 'boundary_class', 'boundary')) {
        if ($Request.PSObject.Properties[$propertyName] -and -not [string]::IsNullOrWhiteSpace([string]$Request.$propertyName)) {
            return ([string]$Request.$propertyName).Trim()
        }
    }

    return ''
}

function Get-RequestBoundaryClass {
    param($Request)

    $policyClass = (Get-RequestExecutionPolicyClass -Request $Request).ToLowerInvariant()
    if (@('approval_required', 'hard_boundary', 'human_approval', 'manual_gate', 'escalate') -contains $policyClass) {
        return 'hard_boundary'
    }
    if (@('auto_execute', 'soft_boundary', 'routine', 'bounded') -contains $policyClass) {
        return 'soft_boundary'
    }

    $actionText = ''
    foreach ($propertyName in @('tod_action', 'action', 'title', 'scope', 'task_classification', 'capability_name')) {
        if ($Request -and $Request.PSObject.Properties[$propertyName] -and -not [string]::IsNullOrWhiteSpace([string]$Request.$propertyName)) {
            $actionText += (' ' + ([string]$Request.$propertyName))
        }
    }
    $actionText = $actionText.ToLowerInvariant()

    if ($actionText -match 'credential|secret|password|api token|auth token|access token|refresh token|bearer token|certificate|private key|firewall|production deploy|prod deploy|delete|destroy|reimage|shutdown host|reboot host|open network|public exposure|human safety|operator approval') {
        return 'hard_boundary'
    }

    return 'soft_boundary'
}

function Get-ExecutionReadinessTrace {
    param(
        [Parameter(Mandatory = $true)][string]$TodScriptAbs,
        [Parameter(Mandatory = $true)][string]$Action
    )

    $readinessRaw = & $TodScriptAbs -Action 'get-execution-readiness' -Top 1 2>&1
    $readinessPayload = $null
    try {
        $readinessPayload = ($readinessRaw | ConvertFrom-Json)
    }
    catch {
        $readinessPayload = $null
    }

    if ($null -eq $readinessPayload -or -not $readinessPayload.PSObject.Properties['readiness']) {
        return $null
    }

    $policyOutcome = 'allow'
    $blockActions = if ($readinessPayload.PSObject.Properties['policy'] -and $readinessPayload.policy.PSObject.Properties['block_actions']) { @($readinessPayload.policy.block_actions | ForEach-Object { [string]$_ }) } else { @() }
    $degradeActions = if ($readinessPayload.PSObject.Properties['policy'] -and $readinessPayload.policy.PSObject.Properties['degrade_actions']) { @($readinessPayload.policy.degrade_actions | ForEach-Object { [string]$_ }) } else { @() }
    $blockStates = if ($readinessPayload.PSObject.Properties['policy'] -and $readinessPayload.policy.PSObject.Properties['block_states']) { @($readinessPayload.policy.block_states | ForEach-Object { ([string]$_).ToLowerInvariant() }) } else { @('stale', 'invalid', 'unknown') }
    $degradeStates = if ($readinessPayload.PSObject.Properties['policy'] -and $readinessPayload.policy.PSObject.Properties['degrade_states']) { @($readinessPayload.policy.degrade_states | ForEach-Object { ([string]$_).ToLowerInvariant() }) } else { @('degraded', 'stale', 'invalid', 'unknown') }
    $readinessValid = if ($readinessPayload.readiness.PSObject.Properties['valid']) { [bool]$readinessPayload.readiness.valid } else { $false }
    $executionAllowed = if ($readinessPayload.readiness.PSObject.Properties['execution_allowed']) { [bool]$readinessPayload.readiness.execution_allowed } else { $false }
    $readinessStatus = if ($readinessPayload.readiness.PSObject.Properties['status']) { ([string]$readinessPayload.readiness.status).ToLowerInvariant() } else { 'unknown' }
    if (@($blockActions | Where-Object { [string]::Equals($_, $Action, [System.StringComparison]::OrdinalIgnoreCase) }).Count -gt 0 -and ($blockStates -contains $readinessStatus)) {
        $policyOutcome = 'block'
    }
    elseif (@($degradeActions | Where-Object { [string]::Equals($_, $Action, [System.StringComparison]::OrdinalIgnoreCase) }).Count -gt 0 -and ($degradeStates -contains $readinessStatus)) {
        $policyOutcome = 'degrade'
    }

    return [pscustomobject]@{
        status = if ($readinessPayload.readiness.PSObject.Properties['status']) { [string]$readinessPayload.readiness.status } else { 'unknown' }
        source = if ($readinessPayload.readiness.PSObject.Properties['reason']) { [string]$readinessPayload.readiness.reason } else { 'unknown' }
        detail = if ($readinessPayload.readiness.PSObject.Properties['detail']) { [string]$readinessPayload.readiness.detail } else { '' }
        valid = $readinessValid
        execution_allowed = $executionAllowed
        authoritative = if ($readinessPayload.readiness.PSObject.Properties['authoritative']) { [bool]$readinessPayload.readiness.authoritative } else { $true }
        freshness_state = if ($readinessPayload.readiness.PSObject.Properties['freshness_state']) { [string]$readinessPayload.readiness.freshness_state } else { 'unknown' }
        signal_name = if ($readinessPayload.PSObject.Properties['signal_name']) { [string]$readinessPayload.signal_name } else { 'execution-readiness' }
        evaluated_action = $Action
        policy_outcome = $policyOutcome
        decision_path = @(
            'signal:execution-readiness',
            "status:$(if ($readinessPayload.readiness.PSObject.Properties['status']) { [string]$readinessPayload.readiness.status } else { 'unknown' })",
            "source:$(if ($readinessPayload.readiness.PSObject.Properties['reason']) { [string]$readinessPayload.readiness.reason } else { 'unknown' })",
            "action:$Action",
            "policy_outcome:$policyOutcome"
        )
    }
}

function Get-MimRequestDecision {
    param(
        [Parameter(Mandatory = $true)]$Request,
        [AllowNull()]$GoOrder,
        [AllowNull()]$IntegrationStatus,
        [AllowNull()]$ReviewDecision,
        [Parameter(Mandatory = $true)][string]$TodScriptAbs,
        [switch]$ProcessWithoutGoOrder,
        [string]$SharedStateSyncError = ''
    )

    $requestId = Get-RequestIdentifier -Request $Request
    $requestTaskId = if ($Request.PSObject.Properties['task_id'] -and -not [string]::IsNullOrWhiteSpace([string]$Request.task_id)) { [string]$Request.task_id } else { $requestId }
    $requestObjectiveId = Normalize-ObjectiveIdText -ObjectiveId (Get-ExpectedObjectiveFromRequest -Request $Request)
    $requestTarget = if ($Request.PSObject.Properties['target']) { ([string]$Request.target).Trim() } else { '' }
    $requestedExecutor = (Get-RequestExecutorRole -Request $Request).ToLowerInvariant()
    $boundaryClass = Get-RequestBoundaryClass -Request $Request
        if ($Request.PSObject.Properties['tod_action'] -and -not [string]::IsNullOrWhiteSpace([string]$Request.tod_action)) { $action = [string]$Request.tod_action } elseif ($Request.PSObject.Properties['action'] -and -not [string]::IsNullOrWhiteSpace([string]$Request.action)) { $action = [string]$Request.action } elseif ($Request.PSObject.Properties['action_name'] -and -not [string]::IsNullOrWhiteSpace([string]$Request.action_name)) { $action = [string]$Request.action_name } else { $action = '' }

    if ([string]::IsNullOrWhiteSpace($action)) {
        return [pscustomobject]@{
            decision_outcome = 'request_missing_data'
            reason_code = 'missing_required_action'
            summary = 'Request is missing tod_action, action, or action_name.'
            boundary_class = $boundaryClass
            requested_executor = $requestedExecutor
            requested_objective_id = $requestObjectiveId
            canonical_objective_id = ''
            live_request_promotion_applied = $false
            execution_readiness = $null
            validation_reasoning = @('missing_required_action')
            unmet_dependency = 'request_action'
            blocker_classification = 'data_blocker'
            next_step_recommendation = 'reissue_request_with_tod_action'
            requires_human = $false
        }
    }
    $authorityReset = if ($IntegrationStatus -and $IntegrationStatus.PSObject.Properties['objective_authority_reset']) { $IntegrationStatus.objective_authority_reset } else { $null }
    $authorityResetActive = $false
    if ($authorityReset -and $authorityReset.PSObject.Properties['active']) {
        $authorityResetActiveValue = $authorityReset.active
        if ($authorityResetActiveValue -is [bool]) {
            $authorityResetActive = [bool]$authorityResetActiveValue
        }
        elseif ($null -ne $authorityResetActiveValue) {
            $authorityResetActive = [string]::Equals(([string]$authorityResetActiveValue).Trim(), 'true', [System.StringComparison]::OrdinalIgnoreCase)
        }
    }
    $liveTaskRequest = if ($IntegrationStatus -and $IntegrationStatus.PSObject.Properties['live_task_request']) { $IntegrationStatus.live_task_request } else { $null }
    $bridgeEvidence = if ($IntegrationStatus -and $IntegrationStatus.PSObject.Properties['bridge_canonical_evidence']) { $IntegrationStatus.bridge_canonical_evidence } else { $null }
    $bridgeGuidance = if ($IntegrationStatus -and $IntegrationStatus.PSObject.Properties['bridge_operator_guidance']) { $IntegrationStatus.bridge_operator_guidance } else { $null }
    $objectiveAlignment = if ($IntegrationStatus -and $IntegrationStatus.PSObject.Properties['objective_alignment']) { $IntegrationStatus.objective_alignment } else { $null }
    $canonicalObjective = if ($authorityResetActive -and $authorityReset -and $authorityReset.PSObject.Properties['authoritative_current_objective']) { Normalize-ObjectiveIdText -ObjectiveId ([string]$authorityReset.authoritative_current_objective) } elseif ($objectiveAlignment -and $objectiveAlignment.PSObject.Properties['tod_current_objective']) { Normalize-ObjectiveIdText -ObjectiveId ([string]$objectiveAlignment.tod_current_objective) } else { '' }
    $liveRequestObjective = if ($liveTaskRequest -and $liveTaskRequest.PSObject.Properties['normalized_objective_id']) { Normalize-ObjectiveIdText -ObjectiveId ([string]$liveTaskRequest.normalized_objective_id) } else { '' }
    $liveRequestId = if ($liveTaskRequest -and $liveTaskRequest.PSObject.Properties['request_id']) { [string]$liveTaskRequest.request_id } else { '' }
    $promotionApplied = if ($liveTaskRequest -and $liveTaskRequest.PSObject.Properties['promotion_applied']) { [bool]$liveTaskRequest.promotion_applied } else { $false }
    $validationReasons = New-Object System.Collections.Generic.List[string]
    $failureSignals = @()
    if ($bridgeEvidence -and $bridgeEvidence.PSObject.Properties['failure_signals']) {
        $failureSignals = @($bridgeEvidence.failure_signals | ForEach-Object { ([string]$_).Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
    $readinessTrace = Get-ExecutionReadinessTrace -TodScriptAbs $TodScriptAbs -Action $action
    $goAllowed = $true
    if ($null -ne $GoOrder -and -not $ProcessWithoutGoOrder) {
        if ($GoOrder.PSObject.Properties['authorization'] -and -not [string]::IsNullOrWhiteSpace([string]$GoOrder.authorization)) {
            $goAllowed = ([string]$GoOrder.authorization).Trim().ToLowerInvariant() -eq 'go'
        }
        elseif ($GoOrder.PSObject.Properties['allow_execute']) {
            $goAllowed = [bool]$GoOrder.allow_execute
        }
        elseif ($GoOrder.PSObject.Properties['go']) {
            $goAllowed = [bool]$GoOrder.go
        }
    }

    $requestMatchesCanonical = ([string]::IsNullOrWhiteSpace($canonicalObjective) -or [string]::IsNullOrWhiteSpace($requestObjectiveId) -or [string]::Equals($requestObjectiveId, $canonicalObjective, [System.StringComparison]::OrdinalIgnoreCase))
    $requestMatchesLiveRequest = ([string]::IsNullOrWhiteSpace($liveRequestId) -or [string]::IsNullOrWhiteSpace($requestId) -or [string]::Equals($liveRequestId, $requestId, [System.StringComparison]::OrdinalIgnoreCase))
    if (-not [string]::IsNullOrWhiteSpace($liveRequestObjective) -and -not [string]::IsNullOrWhiteSpace($requestObjectiveId)) {
        $requestMatchesLiveRequest = ($requestMatchesLiveRequest -and [string]::Equals($liveRequestObjective, $requestObjectiveId, [System.StringComparison]::OrdinalIgnoreCase))
    }
    if ($requestMatchesLiveRequest -and -not [string]::IsNullOrWhiteSpace($liveRequestId) -and -not [string]::IsNullOrWhiteSpace($requestId)) {
        $promotionApplied = $true
        $failureSignals = @($failureSignals | Where-Object { $_ -ne 'live_task_request_not_promoted' })
    }
    $bridgeRemotePublishVerified = ($bridgeEvidence -and $bridgeEvidence.PSObject.Properties['remote_publish_verified'] -and [bool]$bridgeEvidence.remote_publish_verified)
    $bridgeConsumerExecuted = ($bridgeEvidence -and $bridgeEvidence.PSObject.Properties['consumer_status'] -and [string]::Equals([string]$bridgeEvidence.consumer_status, 'executed', [System.StringComparison]::OrdinalIgnoreCase))
    $requestTaskClass = if ($Request.PSObject.Properties['task_class']) { [string]$Request.task_class } elseif ($Request.PSObject.Properties['task_classification']) { [string]$Request.task_classification } else { '' }
    $requestTargetFile = if ($Request.PSObject.Properties['target_file']) { [string]$Request.target_file } else { '' }
    $allowLiveRequestAuthorityOverride =
        (-not $authorityResetActive) -and
        (-not $requestMatchesCanonical) -and
        $requestMatchesLiveRequest -and
        $promotionApplied -and
        $bridgeRemotePublishVerified -and
        $bridgeConsumerExecuted -and
        [string]::Equals($requestTarget, 'TOD', [System.StringComparison]::OrdinalIgnoreCase) -and
        [string]::Equals($requestTaskClass, 'implementation', [System.StringComparison]::OrdinalIgnoreCase) -and
        (-not [string]::IsNullOrWhiteSpace($requestTargetFile))
    if ($allowLiveRequestAuthorityOverride) {
        $requestMatchesCanonical = $true
        $failureSignals = @($failureSignals | Where-Object { $_ -notin @('live_task_request_objective_mismatch', 'live_task_request_task_mismatch', 'live_task_request_not_promoted') })
        $validationReasons.Add(('live_request_authority_override:' + $requestId)) | Out-Null
    }

    $sourceSelectedActionCode = if ($Request.PSObject.Properties['source_selected_action_code']) { [string]$Request.source_selected_action_code } else { '' }
    $requestObjectiveType = if ($Request.PSObject.Properties['objective_type']) { [string]$Request.objective_type } else { '' }
    $isRecoverTriggerAckDiagnostic =
        [string]::Equals($sourceSelectedActionCode, 'recover_trigger_ack_bridge', [System.StringComparison]::OrdinalIgnoreCase) -or
        ([string]$requestId -match '(?i)-recover-trigger-ack-bridge-diagnostic$') -or
        ([string]$requestTaskId -match '(?i)-recover-trigger-ack-bridge-diagnostic$')
    $isSystemAlertDiagnostic =
        [string]::Equals($sourceSelectedActionCode, 'acknowledge_and_remediate_system_alerts', [System.StringComparison]::OrdinalIgnoreCase) -or
        ([string]$requestId -match '(?i)-acknowledge-and-remediate-system-alerts-diagnostic$') -or
        ([string]$requestTaskId -match '(?i)-acknowledge-and-remediate-system-alerts-diagnostic$')
    $isBlockedResultClosureDiagnostic =
        [string]::Equals($sourceSelectedActionCode, 'resolve_blocked_task_result', [System.StringComparison]::OrdinalIgnoreCase) -or
        ([string]$requestId -match '(?i)-blocked-result-closure-diagnostic$') -or
        ([string]$requestTaskId -match '(?i)-blocked-result-closure-diagnostic$')
    $isDiagnosticOnlyRequest =
        [string]::Equals($requestTaskClass, 'diagnostic_only', [System.StringComparison]::OrdinalIgnoreCase) -or
        [string]::Equals($requestObjectiveType, 'diagnostic_only', [System.StringComparison]::OrdinalIgnoreCase)
    if (
        $isRecoverTriggerAckDiagnostic -and
        [string]::Equals($action, 'execute-chat-task', [System.StringComparison]::OrdinalIgnoreCase) -and
        [string]::IsNullOrWhiteSpace($requestTargetFile)
    ) {
        $validationReasons.Add('recover_trigger_ack_bridge_wrapper_missing_bounded_packet') | Out-Null
        return [pscustomobject]@{
            decision_outcome = 'reject_with_specific_policy_reason'
            reason_code = 'diagnostic_wrapper_missing_bounded_implementation_packet'
            summary = 'MIM sent a bridge-recovery diagnostic wrapper without the bounded implementation fields TOD needs to execute. The existing channel is alive; MIM must republish an implementation-shaped request instead of another bridge recovery wrapper.'
            boundary_class = $boundaryClass
            requested_executor = $requestedExecutor
            requested_objective_id = $requestObjectiveId
            canonical_objective_id = $canonicalObjective
            live_request_promotion_applied = $promotionApplied
            execution_readiness = $readinessTrace
            validation_reasoning = @($validationReasons)
            unmet_dependency = 'bounded_implementation_packet'
            blocker_classification = 'request_shape_rejection'
            next_step_recommendation = 'republish_existing_channel_bounded_implementation_request'
            requires_human = $false
            required_fields = @('task_class=implementation', 'target_file', 'minimal_patch_plan', 'validation_plan', 'changed_files_required_for_success=true', 'prevention_lesson', 'dave_needed')
        }
    }
    if (
        $isSystemAlertDiagnostic -and
        [string]::Equals($action, 'execute-chat-task', [System.StringComparison]::OrdinalIgnoreCase) -and
        [string]::IsNullOrWhiteSpace($requestTargetFile)
    ) {
        $validationReasons.Add('system_alert_diagnostic_wrapper_missing_bounded_packet') | Out-Null
        return [pscustomobject]@{
            decision_outcome = 'reject_with_specific_policy_reason'
            reason_code = 'diagnostic_wrapper_missing_bounded_implementation_packet'
            summary = 'MIM sent a system-alert diagnostic wrapper without the bounded implementation fields TOD needs to execute. The existing channel is alive; MIM must republish or preserve the implementation-shaped request instead of replacing it with a status wrapper.'
            boundary_class = $boundaryClass
            requested_executor = $requestedExecutor
            requested_objective_id = $requestObjectiveId
            canonical_objective_id = $canonicalObjective
            live_request_promotion_applied = $promotionApplied
            execution_readiness = $readinessTrace
            validation_reasoning = @($validationReasons)
            unmet_dependency = 'bounded_implementation_packet'
            blocker_classification = 'request_shape_rejection'
            next_step_recommendation = 'preserve_or_republish_existing_channel_bounded_implementation_request'
            requires_human = $false
            required_fields = @('task_class=implementation', 'target_file', 'minimal_patch_plan', 'validation_plan', 'changed_files_required_for_success=true', 'prevention_lesson', 'dave_needed')
        }
    }
    if (
        $isBlockedResultClosureDiagnostic -and
        [string]::Equals($action, 'execute-chat-task', [System.StringComparison]::OrdinalIgnoreCase) -and
        [string]::IsNullOrWhiteSpace($requestTargetFile)
    ) {
        $validationReasons.Add('blocked_result_closure_wrapper_missing_bounded_packet') | Out-Null
        return [pscustomobject]@{
            decision_outcome = 'reject_with_specific_policy_reason'
            reason_code = 'diagnostic_wrapper_missing_bounded_implementation_packet'
            summary = 'MIM sent a blocked-result closure diagnostic wrapper without the bounded implementation fields TOD needs to execute. The existing channel is alive; MIM must preserve the implementation-shaped request or ask TOD for an inspected anchor blocker instead of replacing the active packet.'
            boundary_class = $boundaryClass
            requested_executor = $requestedExecutor
            requested_objective_id = $requestObjectiveId
            canonical_objective_id = $canonicalObjective
            live_request_promotion_applied = $promotionApplied
            execution_readiness = $readinessTrace
            validation_reasoning = @($validationReasons)
            unmet_dependency = 'bounded_implementation_packet'
            blocker_classification = 'request_shape_rejection'
            next_step_recommendation = 'preserve_bounded_request_or_publish_inspected_anchor_blocker'
            requires_human = $false
            required_fields = @('task_class=implementation', 'target_file', 'edit_mode_or_inspected_anchor_blocker', 'validation_plan', 'prevention_lesson', 'dave_needed')
        }
    }

    $externalCoordinationSignals = @('listener_task_request_missing', 'live_task_request_objective_mismatch', 'live_task_request_not_promoted', 'remote_consumer_not_executed', 'remote_delivery_not_confirmed')
    $hasExternalCoordinationBlocker = (@($failureSignals | Where-Object { $externalCoordinationSignals -contains $_ }).Count -gt 0)
    $defaultNextStep = if ($bridgeGuidance -and $bridgeGuidance.PSObject.Properties['recommendation'] -and -not [string]::IsNullOrWhiteSpace([string]$bridgeGuidance.recommendation)) { [string]$bridgeGuidance.recommendation } else { 'continue_bounded_execution' }

    if (-not [string]::IsNullOrWhiteSpace($SharedStateSyncError)) {
        $validationReasons.Add(('shared_state_sync_failed:' + $SharedStateSyncError)) | Out-Null
    }
    if ($null -ne $readinessTrace) {
        $validationReasons.Add(('readiness:' + [string]$readinessTrace.status)) | Out-Null
        $validationReasons.Add(('freshness:' + [string]$readinessTrace.freshness_state)) | Out-Null
    }
    if (-not [string]::IsNullOrWhiteSpace($canonicalObjective)) {
        $validationReasons.Add(('authoritative_objective:' + $canonicalObjective)) | Out-Null
    }
    if (-not [string]::IsNullOrWhiteSpace($requestObjectiveId)) {
        $validationReasons.Add(('request_objective:' + $requestObjectiveId)) | Out-Null
    }
    $validationReasons.Add(('boundary:' + $boundaryClass)) | Out-Null
    $validationReasons.Add(('executor:' + $requestedExecutor)) | Out-Null

    if (-not [string]::IsNullOrWhiteSpace($requestTarget) -and -not [string]::Equals($requestTarget, 'TOD', [System.StringComparison]::OrdinalIgnoreCase)) {
        return [pscustomobject]@{
            decision_outcome = 'reject_with_specific_policy_reason'
            reason_code = 'wrong_target'
            summary = 'Request target does not match TOD.'
            boundary_class = $boundaryClass
            requested_executor = $requestedExecutor
            requested_objective_id = $requestObjectiveId
            canonical_objective_id = $canonicalObjective
            live_request_promotion_applied = $promotionApplied
            execution_readiness = $readinessTrace
            validation_reasoning = @($validationReasons)
            unmet_dependency = ''
            blocker_classification = 'policy_rejection'
            next_step_recommendation = 'reissue_request_for_tod'
            requires_human = $false
        }
    }

    if (@('codex', 'tod', 'tod_listener', 'listener') -notcontains $requestedExecutor) {
        return [pscustomobject]@{
            decision_outcome = 'reject_with_specific_policy_reason'
            reason_code = 'executor_role_mismatch'
            summary = 'Request assigned to a non-TOD executor role.'
            boundary_class = $boundaryClass
            requested_executor = $requestedExecutor
            requested_objective_id = $requestObjectiveId
            canonical_objective_id = $canonicalObjective
            live_request_promotion_applied = $promotionApplied
            execution_readiness = $readinessTrace
            validation_reasoning = @($validationReasons)
            unmet_dependency = ''
            blocker_classification = 'policy_rejection'
            next_step_recommendation = 'reassign_executor_to_tod'
            requires_human = $false
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($requestObjectiveId) -and (Test-ObjectiveInvalidatedByAuthority -ObjectiveId $requestObjectiveId -AuthorityReset $authorityReset)) {
        return [pscustomobject]@{
            decision_outcome = 'reject_with_specific_policy_reason'
            reason_code = 'authority_reset_ceiling_exceeded'
            summary = 'Request objective is invalidated by the current authority ceiling.'
            boundary_class = $boundaryClass
            requested_executor = $requestedExecutor
            requested_objective_id = $requestObjectiveId
            canonical_objective_id = $canonicalObjective
            live_request_promotion_applied = $promotionApplied
            execution_readiness = $readinessTrace
            validation_reasoning = @($validationReasons)
            unmet_dependency = ''
            blocker_classification = 'policy_rejection'
            next_step_recommendation = 'refresh_authoritative_objective_then_reissue'
            requires_human = $false
        }
    }

    if ([string]::Equals($boundaryClass, 'hard_boundary', [System.StringComparison]::OrdinalIgnoreCase)) {
        return [pscustomobject]@{
            decision_outcome = 'escalate_hard_boundary'
            reason_code = 'hard_boundary_requires_human'
            summary = 'Request crosses a hard boundary and requires human escalation.'
            boundary_class = $boundaryClass
            requested_executor = $requestedExecutor
            requested_objective_id = $requestObjectiveId
            canonical_objective_id = $canonicalObjective
            live_request_promotion_applied = $promotionApplied
            execution_readiness = $readinessTrace
            validation_reasoning = @($validationReasons)
            unmet_dependency = 'human_boundary_decision'
            blocker_classification = 'hard_boundary'
            next_step_recommendation = 'request_human_boundary_decision'
            requires_human = $true
        }
    }

    if (-not $requestMatchesCanonical) {
        if ($hasExternalCoordinationBlocker) {
            return [pscustomobject]@{
                decision_outcome = 'acknowledge_and_wait_on_dependency'
                reason_code = 'external_coordination_blocker'
                summary = 'Request is waiting on external bridge coordination to restore canonical objective alignment.'
                boundary_class = $boundaryClass
                requested_executor = $requestedExecutor
                requested_objective_id = $requestObjectiveId
                canonical_objective_id = $canonicalObjective
                live_request_promotion_applied = $promotionApplied
                execution_readiness = $readinessTrace
                validation_reasoning = @($validationReasons + @($failureSignals))
                unmet_dependency = 'bridge_publication_alignment'
                blocker_classification = 'external_coordination_blocker'
                next_step_recommendation = $defaultNextStep
                requires_human = $false
            }
        }

        return [pscustomobject]@{
            decision_outcome = 'reject_with_specific_policy_reason'
            reason_code = 'objective_mismatch'
            summary = 'Request objective does not match the current authoritative objective.'
            boundary_class = $boundaryClass
            requested_executor = $requestedExecutor
            requested_objective_id = $requestObjectiveId
            canonical_objective_id = $canonicalObjective
            live_request_promotion_applied = $promotionApplied
            execution_readiness = $readinessTrace
            validation_reasoning = @($validationReasons)
            unmet_dependency = ''
            blocker_classification = 'policy_rejection'
            next_step_recommendation = 'publish_request_for_authoritative_objective'
            requires_human = $false
        }
    }

    if (-not $requestMatchesLiveRequest -or ((-not $promotionApplied) -and -not [string]::IsNullOrWhiteSpace($liveRequestId))) {
        $decisionOutcome = 'reject_with_specific_policy_reason'
        $reasonCode = 'request_not_promoted'
        $summary = 'Request is not the promoted live task request.'
        $blockerClassification = 'policy_rejection'
        $unmetDependency = ''
        $nextStepRecommendation = 'promote_live_task_request_then_retry'

        if ($hasExternalCoordinationBlocker) {
            $decisionOutcome = 'acknowledge_and_wait_on_dependency'
            $reasonCode = 'external_coordination_blocker'
            $summary = 'Request is waiting on remote publication or promotion to become authoritative.'
            $blockerClassification = 'external_coordination_blocker'
            $unmetDependency = 'live_task_request_promotion'
            $nextStepRecommendation = $defaultNextStep
        }

        return [pscustomobject]@{
            decision_outcome = $decisionOutcome
            reason_code = $reasonCode
            summary = $summary
            boundary_class = $boundaryClass
            requested_executor = $requestedExecutor
            requested_objective_id = $requestObjectiveId
            canonical_objective_id = $canonicalObjective
            live_request_promotion_applied = $promotionApplied
            execution_readiness = $readinessTrace
            validation_reasoning = @($validationReasons + @($failureSignals))
            unmet_dependency = $unmetDependency
            blocker_classification = $blockerClassification
            next_step_recommendation = $nextStepRecommendation
            requires_human = $false
        }
    }

    if ($null -ne $readinessTrace -and [string]::Equals([string]$readinessTrace.policy_outcome, 'block', [System.StringComparison]::OrdinalIgnoreCase)) {
        return [pscustomobject]@{
            decision_outcome = 'acknowledge_and_wait_on_dependency'
            reason_code = 'execution_readiness_blocked'
            summary = 'Execution readiness is blocking the requested action.'
            boundary_class = $boundaryClass
            requested_executor = $requestedExecutor
            requested_objective_id = $requestObjectiveId
            canonical_objective_id = $canonicalObjective
            live_request_promotion_applied = $promotionApplied
            execution_readiness = $readinessTrace
            validation_reasoning = @($validationReasons)
            unmet_dependency = 'execution_readiness_refresh'
            blocker_classification = 'local_readiness_blocker'
            next_step_recommendation = 'refresh_execution_readiness'
            requires_human = $false
        }
    }

    if (-not $goAllowed -and -not [string]::Equals($boundaryClass, 'soft_boundary', [System.StringComparison]::OrdinalIgnoreCase)) {
        return [pscustomobject]@{
            decision_outcome = 'acknowledge_and_wait_on_dependency'
            reason_code = 'missing_go_order'
            summary = 'Execution is waiting for GO order because the request is not routine soft-boundary work.'
            boundary_class = $boundaryClass
            requested_executor = $requestedExecutor
            requested_objective_id = $requestObjectiveId
            canonical_objective_id = $canonicalObjective
            live_request_promotion_applied = $promotionApplied
            execution_readiness = $readinessTrace
            validation_reasoning = @($validationReasons)
            unmet_dependency = 'go_order'
            blocker_classification = 'execution_gate_wait'
            next_step_recommendation = 'publish_go_order'
            requires_human = $false
        }
    }

    return [pscustomobject]@{
        decision_outcome = 'execute'
        reason_code = 'authorized_routine_request'
        summary = 'Request is aligned with authority and ready for immediate TOD execution.'
        boundary_class = $boundaryClass
        requested_executor = $requestedExecutor
        requested_objective_id = $requestObjectiveId
        canonical_objective_id = $canonicalObjective
        live_request_promotion_applied = $promotionApplied
        execution_readiness = $readinessTrace
        validation_reasoning = @($validationReasons)
        unmet_dependency = ''
        blocker_classification = ''
        next_step_recommendation = 'execute_now'
        requires_human = $false
    }
}

function Test-AllowManagedObjectiveOverrideFromRequest {
    param(
        [Parameter(Mandatory = $true)]$Request,
        [string]$CurrentObjectiveInProgress = ''
    )

    $requestedObjective = Get-ExpectedObjectiveFromRequest -Request $Request
    if ([string]::IsNullOrWhiteSpace($requestedObjective) -or [string]::IsNullOrWhiteSpace($CurrentObjectiveInProgress)) {
        return $false
    }

    if ([string]::Equals($requestedObjective, $CurrentObjectiveInProgress, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $false
    }

    $requestSource = if ($Request.PSObject.Properties['source']) { [string]$Request.source } else { '' }
    $requestTarget = if ($Request.PSObject.Properties['target']) { [string]$Request.target } else { '' }
    $taskClassification = if ($Request.PSObject.Properties['task_classification']) { [string]$Request.task_classification } else { '' }
    $capabilityName = if ($Request.PSObject.Properties['capability_name']) { [string]$Request.capability_name } else { '' }
    $transportId = ''
    if ($Request.PSObject.Properties['transport'] -and $Request.transport -and $Request.transport.PSObject.Properties['transport_id']) {
        $transportId = [string]$Request.transport.transport_id
    }
    elseif ($Request.PSObject.Properties['execution_policy'] -and $Request.execution_policy -and $Request.execution_policy.PSObject.Properties['transport']) {
        $transportId = [string]$Request.execution_policy.transport
    }

    $freshnessToken = 0L
    if ($Request.PSObject.Properties['freshness_token'] -and $null -ne $Request.freshness_token) {
        try {
            $freshnessToken = [long]$Request.freshness_token
        }
        catch {
            $freshnessToken = 0L
        }
    }

    $requestedObjectiveNumber = Get-ObjectiveNumericValue -ObjectiveId $requestedObjective
    $currentObjectiveNumber = Get-ObjectiveNumericValue -ObjectiveId $CurrentObjectiveInProgress
    $looksManagedMimExecution = [string]::Equals($requestSource, 'MIM', [System.StringComparison]::OrdinalIgnoreCase) -and
        [string]::Equals($requestTarget, 'TOD', [System.StringComparison]::OrdinalIgnoreCase) -and
        (
            [string]::Equals($taskClassification, 'governed_execution', [System.StringComparison]::OrdinalIgnoreCase) -or
            [string]::Equals($transportId, 'mim_server_shared_artifact_boundary', [System.StringComparison]::OrdinalIgnoreCase) -or
            $capabilityName.StartsWith('mim_', [System.StringComparison]::OrdinalIgnoreCase)
        )

    if (-not $looksManagedMimExecution) {
        return $false
    }

    if ($requestedObjectiveNumber -ge 0 -and $currentObjectiveNumber -ge 0 -and $requestedObjectiveNumber -gt $currentObjectiveNumber) {
        return $true
    }

    return ($freshnessToken -gt 0)
}

function Limit-ListenerStateText {
    param(
        [AllowNull()][string]$Value,
        [int]$MaxLength = 8192,
        [string]$FieldName = "text"
    )

    if ([string]::IsNullOrEmpty($Value)) {
        return $Value
    }

    if ($Value.Length -le $MaxLength) {
        return $Value
    }

    $suffix = "...[truncated for listener state; field=$FieldName; original_length=$($Value.Length)]"
    $prefixLength = $MaxLength - $suffix.Length
    if ($prefixLength -lt 0) {
        $prefixLength = 0
    }

    return $Value.Substring(0, $prefixLength) + $suffix
}

function New-ListenerState {
    param($ExistingState)

    $scopedForcedReplays = @()
    if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties['scoped_forced_replays'] -and $null -ne $ExistingState.scoped_forced_replays) {
        $scopedForcedReplays = @($ExistingState.scoped_forced_replays | Where-Object { $null -ne $_ })
    }

    return [pscustomobject]@{
        last_processed_request_id = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_processed_request_id"]) { [string]$ExistingState.last_processed_request_id } else { "" }
        last_processed_request_signature = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_processed_request_signature"]) { [string]$ExistingState.last_processed_request_signature } else { "" }
        last_trigger_event_signature = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_trigger_event_signature"]) { [string]$ExistingState.last_trigger_event_signature } else { "" }
        last_liveness_trigger_signature = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_liveness_trigger_signature"]) { [string]$ExistingState.last_liveness_trigger_signature } else { "" }
        last_liveness_ping_signature = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_liveness_ping_signature"]) { [string]$ExistingState.last_liveness_ping_signature } else { "" }
        last_status_publish_at = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_status_publish_at"]) { [string]$ExistingState.last_status_publish_at } else { "" }
        last_cycle_at = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_cycle_at"]) { [string]$ExistingState.last_cycle_at } else { "" }
        last_execution_at = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_execution_at"]) { [string]$ExistingState.last_execution_at } else { "" }
        last_command_status = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_command_status"]) { [string]$ExistingState.last_command_status } else { "" }
        last_command_status_at = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_command_status_at"]) { [string]$ExistingState.last_command_status_at } else { "" }
        last_command_detail = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_command_detail"]) { [string]$ExistingState.last_command_detail } else { "" }
        last_observed_request_id = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_observed_request_id"]) { [string]$ExistingState.last_observed_request_id } else { "" }
        last_observed_request_signature = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_observed_request_signature"]) { [string]$ExistingState.last_observed_request_signature } else { "" }
        last_observed_go_order_signature = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_observed_go_order_signature"]) { [string]$ExistingState.last_observed_go_order_signature } else { "" }
        last_observed_task_id = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_observed_task_id"]) { [string]$ExistingState.last_observed_task_id } else { "" }
        last_observed_correlation_id = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_observed_correlation_id"]) { [string]$ExistingState.last_observed_correlation_id } else { "" }
        last_observed_trigger_type = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_observed_trigger_type"]) { [string]$ExistingState.last_observed_trigger_type } else { "" }
        last_observed_trigger_sequence = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_observed_trigger_sequence"]) { [long]$ExistingState.last_observed_trigger_sequence } else { 0L }
        last_observed_trigger_artifact = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_observed_trigger_artifact"]) { [string]$ExistingState.last_observed_trigger_artifact } else { "" }
        last_ack_generated_at = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_ack_generated_at"]) { [string]$ExistingState.last_ack_generated_at } else { "" }
        last_ack_sequence = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_ack_sequence"]) { [long]$ExistingState.last_ack_sequence } else { 0L }
        last_result_generated_at = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_result_generated_at"]) { [string]$ExistingState.last_result_generated_at } else { "" }
        last_result_sequence = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_result_sequence"]) { [long]$ExistingState.last_result_sequence } else { 0L }
        last_result_status = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_result_status"]) { [string]$ExistingState.last_result_status } else { "" }
        last_result_action = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_result_action"]) { [string]$ExistingState.last_result_action } else { "" }
        high_watermark_request_id = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["high_watermark_request_id"]) { [string]$ExistingState.high_watermark_request_id } else { "" }
        high_watermark_objective_id = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["high_watermark_objective_id"]) { [string]$ExistingState.high_watermark_objective_id } else { "" }
        high_watermark_ordinal = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["high_watermark_ordinal"]) { [long]$ExistingState.high_watermark_ordinal } else { 0L }
        high_watermark_sequence = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["high_watermark_sequence"]) { [long]$ExistingState.high_watermark_sequence } else { 0L }
        last_stale_guard = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_stale_guard"]) { $ExistingState.last_stale_guard } else { $null }
        last_cycle_classification = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_cycle_classification"]) { [string]$ExistingState.last_cycle_classification } else { "" }
        last_retry_reason = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_retry_reason"]) { [string]$ExistingState.last_retry_reason } else { "none" }
        cadence_retry_streak = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["cadence_retry_streak"]) { [int]$ExistingState.cadence_retry_streak } else { 0 }
        cadence_backoff_seconds = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["cadence_backoff_seconds"]) { [int]$ExistingState.cadence_backoff_seconds } else { 0 }
        cadence_minimum_cycle_seconds = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["cadence_minimum_cycle_seconds"]) { [int]$ExistingState.cadence_minimum_cycle_seconds } else { 0 }
        cadence_planned_sleep_seconds = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["cadence_planned_sleep_seconds"]) { [int]$ExistingState.cadence_planned_sleep_seconds } else { 0 }
        cadence_last_success_at = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["cadence_last_success_at"]) { [string]$ExistingState.cadence_last_success_at } else { "" }
        last_outbound_sequence = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_outbound_sequence"]) { [long]$ExistingState.last_outbound_sequence } else { 0 }
        last_project_request_signature = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_project_request_signature"]) { [string]$ExistingState.last_project_request_signature } else { "" }
        last_project_request_snapshot_path = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_project_request_snapshot_path"]) { [string]$ExistingState.last_project_request_snapshot_path } else { "" }
        last_project_task_signature = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_project_task_signature"]) { [string]$ExistingState.last_project_task_signature } else { "" }
        last_project_task_snapshot_path = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_project_task_snapshot_path"]) { [string]$ExistingState.last_project_task_snapshot_path } else { "" }
        last_project_tasks_signature = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_project_tasks_signature"]) { [string]$ExistingState.last_project_tasks_signature } else { "" }
        last_project_tasks_snapshot_path = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_project_tasks_snapshot_path"]) { [string]$ExistingState.last_project_tasks_snapshot_path } else { "" }
        last_liveness_trigger_snapshot_path = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_liveness_trigger_snapshot_path"]) { [string]$ExistingState.last_liveness_trigger_snapshot_path } else { "" }
        last_handoff_coordination_signature = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_handoff_coordination_signature"]) { [string]$ExistingState.last_handoff_coordination_signature } else { "" }
        last_handoff_coordination_request_id = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_handoff_coordination_request_id"]) { [string]$ExistingState.last_handoff_coordination_request_id } else { "" }
        last_readiness_status = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_readiness_status"]) { [string]$ExistingState.last_readiness_status } else { "" }
        last_readiness_source = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_readiness_source"]) { [string]$ExistingState.last_readiness_source } else { "" }
        last_readiness_policy_outcome = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_readiness_policy_outcome"]) { [string]$ExistingState.last_readiness_policy_outcome } else { "" }
        last_readiness_execution_allowed = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_readiness_execution_allowed"]) { [bool]$ExistingState.last_readiness_execution_allowed } else { $false }
        last_readiness_valid = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_readiness_valid"]) { [bool]$ExistingState.last_readiness_valid } else { $false }
        last_readiness_recorded_at = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_readiness_recorded_at"]) { [string]$ExistingState.last_readiness_recorded_at } else { "" }
        blocked_resume_request_id = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["blocked_resume_request_id"]) { [string]$ExistingState.blocked_resume_request_id } else { "" }
        blocked_resume_request_signature = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["blocked_resume_request_signature"]) { [string]$ExistingState.blocked_resume_request_signature } else { "" }
        blocked_resume_task_id = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["blocked_resume_task_id"]) { [string]$ExistingState.blocked_resume_task_id } else { "" }
        blocked_resume_objective_id = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["blocked_resume_objective_id"]) { [string]$ExistingState.blocked_resume_objective_id } else { "" }
        blocked_resume_correlation_id = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["blocked_resume_correlation_id"]) { [string]$ExistingState.blocked_resume_correlation_id } else { "" }
        blocked_resume_action = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["blocked_resume_action"]) { [string]$ExistingState.blocked_resume_action } else { "" }
        blocked_resume_reason_code = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["blocked_resume_reason_code"]) { [string]$ExistingState.blocked_resume_reason_code } else { "" }
        blocked_resume_summary = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["blocked_resume_summary"]) { [string]$ExistingState.blocked_resume_summary } else { "" }
        blocked_resume_recorded_at = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["blocked_resume_recorded_at"]) { [string]$ExistingState.blocked_resume_recorded_at } else { "" }
        blocked_resume_retry_attempted = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["blocked_resume_retry_attempted"]) { [bool]$ExistingState.blocked_resume_retry_attempted } else { $false }
        blocked_resume_retry_attempted_at = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["blocked_resume_retry_attempted_at"]) { [string]$ExistingState.blocked_resume_retry_attempted_at } else { "" }
        scoped_forced_replays = @($scopedForcedReplays)
    }
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
    $json = ($Payload | ConvertTo-Json -Depth $Depth) -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($PathValue, $json, $utf8NoBom)
}

function Save-ArtifactSnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$SnapshotDir,
        [Parameter(Mandatory = $true)][string]$Prefix,
        [string]$Signature = ""
    )

    if (-not (Test-Path -Path $SourcePath -PathType Leaf)) {
        return ""
    }

    if (-not (Test-Path -Path $SnapshotDir)) {
        New-Item -ItemType Directory -Path $SnapshotDir -Force | Out-Null
    }

    $safePrefix = ([string]$Prefix -replace "[^a-zA-Z0-9._-]", "_").Trim('.')
    if ([string]::IsNullOrWhiteSpace($safePrefix)) {
        $safePrefix = "artifact"
    }

    $stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssfffZ")
    $sigSuffix = "nosig"
    if (-not [string]::IsNullOrWhiteSpace($Signature)) {
        $sigSuffix = ([string]$Signature).ToLowerInvariant()
        if ($sigSuffix.Length -gt 12) {
            $sigSuffix = $sigSuffix.Substring(0, 12)
        }
    }

    $snapshotName = "{0}.{1}.{2}.json" -f $safePrefix, $stamp, $sigSuffix
    $snapshotPath = Join-Path $SnapshotDir $snapshotName
    Copy-Item -Path $SourcePath -Destination $snapshotPath -Force

    $latestPath = Join-Path $SnapshotDir ("{0}.preserved.latest.json" -f $safePrefix)
    Copy-Item -Path $SourcePath -Destination $latestPath -Force

    Invoke-ArtifactSnapshotRetention -SnapshotDir $SnapshotDir -Prefix $safePrefix -KeepCount $IncomingProjectInboxKeepPerArtifact -MaxAgeDays $IncomingProjectInboxMaxAgeDays
    return $snapshotPath
}

function Invoke-ArtifactSnapshotRetention {
    param(
        [Parameter(Mandatory = $true)][string]$SnapshotDir,
        [Parameter(Mandatory = $true)][string]$Prefix,
        [int]$KeepCount = 50,
        [int]$MaxAgeDays = 14
    )

    if (-not (Test-Path -Path $SnapshotDir)) {
        return
    }

    $safePrefix = ([string]$Prefix -replace "[^a-zA-Z0-9._-]", "_").Trim('.')
    if ([string]::IsNullOrWhiteSpace($safePrefix)) {
        return
    }

    $candidates = @(Get-ChildItem -Path $SnapshotDir -Filter ("{0}.*.json" -f $safePrefix) -File -ErrorAction SilentlyContinue |
        Where-Object { -not $_.Name.EndsWith(".preserved.latest.json", [System.StringComparison]::OrdinalIgnoreCase) } |
        Sort-Object LastWriteTimeUtc -Descending)

    if ($candidates.Count -eq 0) {
        return
    }

    $cutoffUtc = $null
    if ($MaxAgeDays -gt 0) {
        $cutoffUtc = (Get-Date).ToUniversalTime().AddDays(-1 * $MaxAgeDays)
    }

    $removed = 0
    for ($i = 0; $i -lt $candidates.Count; $i++) {
        $item = $candidates[$i]
        $removeForCount = ($KeepCount -ge 0 -and $i -ge $KeepCount)
        $removeForAge = ($null -ne $cutoffUtc -and $item.LastWriteTimeUtc -lt $cutoffUtc)
        if ($removeForCount -or $removeForAge) {
            try {
                Remove-Item -Path $item.FullName -Force -ErrorAction Stop
                $removed += 1
            }
            catch {
                Write-Warning ("[TOD-LISTENER] Failed to prune snapshot {0}: {1}" -f $item.FullName, $_.Exception.Message)
            }
        }
    }

    if ($removed -gt 0) {
        Write-Host ("[TOD-LISTENER] Pruned {0} snapshot(s) for prefix '{1}' in {2}" -f $removed, $safePrefix, $SnapshotDir)
    }
}

function Get-RegressionSnapshot {
    param([Parameter(Mandatory = $true)][string]$CurrentBuildStatePath)

    $build = Read-JsonFileIfExists -PathValue $CurrentBuildStatePath
    if ($null -eq $build -or -not $build.PSObject.Properties["last_regression_result"]) {
        return [pscustomobject]@{
            available = $false
            passed = 0
            failed = 0
            total = 0
            generated_at = ""
            signature = ""
        }
    }

    $reg = $build.last_regression_result
    $passed = 0
    $failed = 0
    $total = 0
    try { $passed = [int]$reg.passed } catch { $passed = 0 }
    try { $failed = [int]$reg.failed } catch { $failed = 0 }
    try { $total = [int]$reg.total } catch { $total = 0 }
    $generatedAt = if ($reg.PSObject.Properties["generated_at"]) { [string]$reg.generated_at } else { "" }

    return [pscustomobject]@{
        available = $true
        passed = $passed
        failed = $failed
        total = $total
        generated_at = $generatedAt
        signature = ("{0}|{1}|{2}|{3}" -f $generatedAt, $passed, $failed, $total)
    }
}

function New-RegressionStallState {
    param($ExistingState)

    return [pscustomobject]@{
        last_signature = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_signature"]) { [string]$ExistingState.last_signature } else { "" }
        last_request_id = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_request_id"]) { [string]$ExistingState.last_request_id } else { "" }
        unchanged_cycles = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["unchanged_cycles"]) { [int]$ExistingState.unchanged_cycles } else { 0 }
        last_update_at = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_update_at"]) { [string]$ExistingState.last_update_at } else { "" }
    }
}

function New-CoordinationEscalationState {
    param($ExistingState)

    return [pscustomobject]@{
        pending_request_id = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["pending_request_id"]) { [string]$ExistingState.pending_request_id } else { "" }
        pending_issue_code = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["pending_issue_code"]) { [string]$ExistingState.pending_issue_code } else { "" }
        pending_issue_summary = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["pending_issue_summary"]) { [string]$ExistingState.pending_issue_summary } else { "" }
        pending_since = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["pending_since"]) { [string]$ExistingState.pending_since } else { "" }
        last_emit_at = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_emit_at"]) { [string]$ExistingState.last_emit_at } else { "" }
        last_emitted_level = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_emitted_level"]) { [int]$ExistingState.last_emitted_level } else { 0 }
        emit_count = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["emit_count"]) { [int]$ExistingState.emit_count } else { 0 }
        last_ack_request_id = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_ack_request_id"]) { [string]$ExistingState.last_ack_request_id } else { "" }
        last_acknowledged_at = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_acknowledged_at"]) { [string]$ExistingState.last_acknowledged_at } else { "" }
        last_ack_generated_at = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_ack_generated_at"]) { [string]$ExistingState.last_ack_generated_at } else { "" }
        last_ack_status = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_ack_status"]) { [string]$ExistingState.last_ack_status } else { "" }
        last_ack_decision = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_ack_decision"]) { [string]$ExistingState.last_ack_decision } else { "" }
        last_ack_reason = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_ack_reason"]) { [string]$ExistingState.last_ack_reason } else { "" }
        pending_emergency_request_id = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["pending_emergency_request_id"]) { [string]$ExistingState.pending_emergency_request_id } else { "" }
        pending_emergency_issue_code = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["pending_emergency_issue_code"]) { [string]$ExistingState.pending_emergency_issue_code } else { "" }
        pending_emergency_issue_summary = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["pending_emergency_issue_summary"]) { [string]$ExistingState.pending_emergency_issue_summary } else { "" }
        pending_emergency_parent_request_id = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["pending_emergency_parent_request_id"]) { [string]$ExistingState.pending_emergency_parent_request_id } else { "" }
        pending_emergency_since = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["pending_emergency_since"]) { [string]$ExistingState.pending_emergency_since } else { "" }
        last_emergency_emit_at = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_emergency_emit_at"]) { [string]$ExistingState.last_emergency_emit_at } else { "" }
        emergency_emit_count = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["emergency_emit_count"]) { [int]$ExistingState.emergency_emit_count } else { 0 }
        last_emergency_ack_request_id = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_emergency_ack_request_id"]) { [string]$ExistingState.last_emergency_ack_request_id } else { "" }
        last_emergency_acknowledged_at = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_emergency_acknowledged_at"]) { [string]$ExistingState.last_emergency_acknowledged_at } else { "" }
        last_emergency_ack_generated_at = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_emergency_ack_generated_at"]) { [string]$ExistingState.last_emergency_ack_generated_at } else { "" }
        last_emergency_ack_status = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_emergency_ack_status"]) { [string]$ExistingState.last_emergency_ack_status } else { "" }
        last_emergency_ack_decision = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_emergency_ack_decision"]) { [string]$ExistingState.last_emergency_ack_decision } else { "" }
        last_emergency_ack_reason = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_emergency_ack_reason"]) { [string]$ExistingState.last_emergency_ack_reason } else { "" }
        last_dialog_session_id = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_dialog_session_id"]) { [string]$ExistingState.last_dialog_session_id } else { "" }
        last_dialog_inquiry_at = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_dialog_inquiry_at"]) { [string]$ExistingState.last_dialog_inquiry_at } else { "" }
        dialog_inquiry_count = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["dialog_inquiry_count"]) { [int]$ExistingState.dialog_inquiry_count } else { 0 }
    }
}

function Clear-CoordinationEscalationState {
    param(
        [Parameter(Mandatory = $true)]$State,
        [string]$Reason = "",
        [string]$RequestId = ""
    )

    $State.pending_request_id = ""
    $State.pending_issue_code = ""
    $State.pending_issue_summary = ""
    $State.pending_since = ""
    $State.last_emit_at = ""
    $State.last_emitted_level = 0
    $State.emit_count = 0
    if (-not [string]::IsNullOrWhiteSpace($RequestId)) {
        $State.last_ack_request_id = $RequestId
    }
    $State.last_acknowledged_at = (Get-Date).ToUniversalTime().ToString("o")
    $State.last_ack_status = "resolved"
    $State.last_ack_decision = "auto_resolved_regression_green"
    $State.pending_emergency_request_id = ""
    $State.pending_emergency_issue_code = ""
    $State.pending_emergency_issue_summary = ""
    $State.pending_emergency_parent_request_id = ""
    $State.pending_emergency_since = ""
    $State.last_emergency_emit_at = ""
    $State.emergency_emit_count = 0
    $State.last_dialog_session_id = ""
    $State.last_dialog_inquiry_at = ""
    $State.dialog_inquiry_count = 0
    if (-not [string]::IsNullOrWhiteSpace($Reason)) {
        $State.last_ack_reason = $Reason
    }
}

function Test-IsTerminalExecutionStatus {
    param([string]$Status)

    if ([string]::IsNullOrWhiteSpace($Status)) {
        return $false
    }

    $normalized = ([string]$Status).Trim().ToLowerInvariant()
    return @('completed', 'succeeded', 'already_processed', 'stale_request_ignored', 'stale_backfill_ignored') -contains $normalized
}

function Publish-CoordinationPendingInquiry {
    param(
        [Parameter(Mandatory = $true)]$CoordinationEscalationState,
        [Parameter(Mandatory = $true)][string]$CoordinationEscalationStatePath,
        [Parameter(Mandatory = $true)][string]$DialogScriptAbs,
        [Parameter(Mandatory = $true)][string]$EnvPath,
        [Parameter(Mandatory = $true)][string]$RequestId,
        [string]$ObjectiveId = '',
        [string]$IssueCode = '',
        [string]$IssueSummary = '',
        [string]$AckStatus = '',
        [string]$AckDecision = '',
        [string]$AckReason = '',
        [int]$TimeoutSeconds = 60,
        [int]$ElapsedSeconds = 0,
        [AllowNull()]$CoordinationRequest = $null,
        [AllowNull()]$BridgeRuntime = $null,
        [bool]$PublishRemote = $true
    )

    $nowUtc = (Get-Date).ToUniversalTime()
    $sessionSeed = if (-not [string]::IsNullOrWhiteSpace($IssueCode)) {
        'tod-coordination-' + [string]$RequestId + '-' + [string]$IssueCode
    }
    else {
        'tod-coordination-' + [string]$RequestId
    }
    $sessionId = Get-SafeDialogSessionId -Seed $sessionSeed
    $sessionLogPath = Get-LocalPath -PathValue ('shared_state/dialog/MIM_TOD_DIALOG.session-' + $sessionId + '.jsonl')
    $sessionStatePath = Get-LocalPath -PathValue ('shared_state/dialog/MIM_TOD_DIALOG.session-' + $sessionId + '.latest.json')
    $lastInquiryUtc = Get-DateOrMinValue -Value ([string]$CoordinationEscalationState.last_dialog_inquiry_at)
    $cooldownSeconds = [Math]::Max(60, [int]$TimeoutSeconds)
    $secondsSinceInquiry = if ($lastInquiryUtc -eq [datetime]::MinValue) { 999999 } else { [int][math]::Floor((New-TimeSpan -Start $lastInquiryUtc -End $nowUtc).TotalSeconds) }
    $dialogArtifactsExist = (Test-Path -Path $sessionLogPath) -or (Test-Path -Path $sessionStatePath)
    if (-not $dialogArtifactsExist) {
        $secondsSinceInquiry = 999999
    }
    if ($secondsSinceInquiry -lt $cooldownSeconds) {
        return $null
    }

    $summary = ('TOD observed coordination request {0} still pending after {1}s; MIM must publish the smallest bounded implementation request needed for TOD to close it.' -f [string]$RequestId, [int]$TimeoutSeconds)
    $payload = [pscustomobject]@{
        source = 'tod-listener-coordination-followup-v1'
        request_id = [string]$RequestId
        objective_id = [string]$ObjectiveId
        issue_code = [string]$IssueCode
        issue_summary = [string]$IssueSummary
        coordination_ack_status = [string]$AckStatus
        coordination_ack_decision = [string]$AckDecision
        coordination_ack_reason = [string]$AckReason
        timeout_seconds = [int]$TimeoutSeconds
        elapsed_seconds = [int]$ElapsedSeconds
        action = 'Convert this coordination blocker into one bounded implementation request on the existing MIM/TOD task channel; do not create a new transport or SSH channel.'
        owner = 'MIM'
        requested_action = 'Publish one implementation-shaped TOD request with exactly one target_file, task_class=implementation, changed_files_required_for_success=true, a minimal patch plan, validation_plan, prevention_lesson, and dave_needed yes/no.'
        requested_mim_action = 'Select the smallest real code or artifact behavior change that resolves the current blocker and send TOD a bounded implementation packet instead of another diagnostic/status request.'
        required_tod_action = 'After MIM publishes the bounded implementation request, TOD must inspect the target file, make the minimal change, validate it, and publish execution evidence.'
        evidence_request = 'Reply with the new request_id, target_file, patch_type or minimal_patch_plan, validation_plan, and why Dave is or is not needed.'
        evidence_required = @(
            'existing shared MIM/TOD channel artifact path or request_id',
            'exactly one target_file',
            'minimal_patch_plan or patch_type',
            'validation_plan',
            'changed_files_required_for_success=true',
            'prevention_lesson',
            'dave_needed yes/no with reason'
        )
        required_fields = @(
            'task_class=implementation',
            'target_file',
            'minimal_patch_plan',
            'validation_plan',
            'changed_files_required_for_success=true',
            'prevention_lesson',
            'dave_needed'
        )
        required_mim_response_fields = @(
            'action',
            'owner',
            'evidence',
            'aging_rule',
            'dave_needed'
        )
        requested_reply = [pscustomobject]@{
            needed = $true
            fields = @('action', 'owner', 'bounded_request_id', 'target_file', 'patch_plan', 'validation_plan', 'evidence', 'aging_rule', 'dave_needed')
        }
        accepted_outcomes = @(
            'bounded_implementation_request_published',
            'external_dependency_proven_with_evidence'
        )
        no_credit_if = @(
            'new SSH or transport channel proposed',
            'diagnostic-only request',
            'status-only reply',
            'multi-file broad rewrite',
            'missing target_file',
            'missing validation_plan'
        )
        acceptable_result = 'MIM publishes a bounded implementation-shaped request that TOD can execute through the existing shared channel.'
        aging_rule = 'If no bounded implementation request is published within the next listener cycle, keep this open as MIM request-shape debt and do not count it as TOD progress.'
        dave_needed = 'no unless the bounded implementation requires credentials, production account changes, or an external service decision.'
        requested_feedback = @(
            'bounded_request_id',
            'target_file',
            'patch_plan',
            'validation_plan',
            'dave_needed'
        )
        coordination_request = $CoordinationRequest
        bridge_runtime = $BridgeRuntime
    }
    $boundedSummary = ([string]$summary).Trim()
    if ($boundedSummary.Length -gt 260) {
        $boundedSummary = $boundedSummary.Substring(0, 257).TrimEnd() + '...'
    }
    $dialogResult = Invoke-DialogNotice -ScriptAbs $DialogScriptAbs -Action 'send' -SessionId $sessionId -MessageType 'status_request' -Intent 'coordination_pending_timeout' -Summary $boundedSummary -Payload $payload -TaskId $RequestId -CorrelationId ([string]$IssueCode) -EnvPath $EnvPath -PublishRemote:$PublishRemote
    if (-not [bool]$dialogResult.ok) {
        return $dialogResult
    }

    $CoordinationEscalationState.last_dialog_session_id = $sessionId
    $CoordinationEscalationState.last_dialog_inquiry_at = $nowUtc.ToString('o')
    $CoordinationEscalationState.dialog_inquiry_count = [int]$CoordinationEscalationState.dialog_inquiry_count + 1
    Write-JsonFile -PathValue $CoordinationEscalationStatePath -Payload $CoordinationEscalationState

    return [pscustomobject]@{ ok = $true; status = 'sent'; session_id = $sessionId }
}

function Publish-EmergencyCoordinationRequest {
    param(
        [Parameter(Mandatory = $true)]$CoordinationEscalationState,
        [Parameter(Mandatory = $true)][string]$CoordinationEscalationStatePath,
        [Parameter(Mandatory = $true)][string]$LocalEmergencyRequestPath,
        [Parameter(Mandatory = $true)][string]$RemoteEmergencyRequestPath,
        [Parameter(Mandatory = $true)]$Connections,
        [Parameter(Mandatory = $true)][string]$ParentRequestId,
        [string]$ObjectiveId = '',
        [string]$IssueCode = '',
        [string]$IssueSummary = '',
        [string]$AckStatus = '',
        [string]$AckDecision = '',
        [string]$AckReason = '',
        [int]$CoordinationTimeoutSeconds = 60,
        [int]$ElapsedSeconds = 0,
        [AllowNull()]$CoordinationRequest = $null,
        [AllowNull()]$BridgeRuntime = $null
    )

    $utcNow = (Get-Date).ToUniversalTime()
    $normalizedIssueCode = if ([string]::IsNullOrWhiteSpace($IssueCode)) { 'coordination_timeout' } else { [string]$IssueCode }
    $emergencyRequestId = if (-not [string]::IsNullOrWhiteSpace([string]$CoordinationEscalationState.pending_emergency_request_id) -and
        [string]::Equals([string]$CoordinationEscalationState.pending_emergency_parent_request_id, [string]$ParentRequestId, [System.StringComparison]::OrdinalIgnoreCase) -and
        [string]::Equals([string]$CoordinationEscalationState.pending_emergency_issue_code, ($normalizedIssueCode + '_emergency'), [System.StringComparison]::OrdinalIgnoreCase)) {
        [string]$CoordinationEscalationState.pending_emergency_request_id
    }
    else {
        'tod-emergency-' + [string]$ParentRequestId + '-' + $normalizedIssueCode
    }

    $lastEmergencyEmitUtc = Get-DateOrMinValue -Value ([string]$CoordinationEscalationState.last_emergency_emit_at)
    $secondsSinceLastEmergencyEmit = if ($lastEmergencyEmitUtc -eq [datetime]::MinValue) { 999999 } else { [int][math]::Floor((New-TimeSpan -Start $lastEmergencyEmitUtc -End $utcNow).TotalSeconds) }
    if ($secondsSinceLastEmergencyEmit -lt [Math]::Max(60, [int]$CoordinationTimeoutSeconds)) {
        return $null
    }

    $emergencyPayload = [pscustomobject]@{
        generated_at = $utcNow.ToString('o')
        source = 'tod-mim-emergency-request-v1'
        status = 'active'
        priority = 'critical'
        escalation_level = 4
        request_id = $emergencyRequestId
        parent_request_id = [string]$ParentRequestId
        objective_id = [string]$ObjectiveId
        issue_code = $normalizedIssueCode + '_emergency'
        issue_summary = if ([string]::IsNullOrWhiteSpace($IssueSummary)) { 'TOD did not receive a timely coordination response from MIM.' } else { [string]$IssueSummary }
        emergency_reason = ('TOD coordination request exceeded its response SLA ({0}s elapsed, base timeout {1}s).' -f [int]$ElapsedSeconds, [int]$CoordinationTimeoutSeconds)
        requested_action = 'Reply immediately on MIM_TOD_EMERGENCY_ACK.latest.json, say whether MIM is investigating, accepting, or rejecting the request, and publish the next update or repair action without waiting for another TOD prompt.'
        required_ack = [pscustomobject]@{
            ack_file = 'MIM_TOD_EMERGENCY_ACK.latest.json'
            ack_fields = @('acknowledged', 'acknowledged_at', 'request_id', 'decision', 'reason', 'next_update_at')
            timeout_seconds = 15
        }
        coordination = [pscustomobject]@{
            coordination_status = [string]$AckStatus
            coordination_decision = [string]$AckDecision
            coordination_reason = [string]$AckReason
            elapsed_seconds = [int]$ElapsedSeconds
            parent_timeout_seconds = [int]$CoordinationTimeoutSeconds
        }
        coordination_request = $CoordinationRequest
        bridge_runtime = $BridgeRuntime
    }

    Write-JsonFile -PathValue $LocalEmergencyRequestPath -Payload $emergencyPayload
    $emergencyJson = Get-Content -Path $LocalEmergencyRequestPath -Raw
    Write-RemoteFileFromText -Connections $Connections -RemotePath $RemoteEmergencyRequestPath -Content $emergencyJson

    $CoordinationEscalationState.pending_emergency_request_id = $emergencyRequestId
    $CoordinationEscalationState.pending_emergency_issue_code = $normalizedIssueCode + '_emergency'
    $CoordinationEscalationState.pending_emergency_issue_summary = [string]$emergencyPayload.issue_summary
    $CoordinationEscalationState.pending_emergency_parent_request_id = [string]$ParentRequestId
    if ([string]::IsNullOrWhiteSpace([string]$CoordinationEscalationState.pending_emergency_since)) {
        $CoordinationEscalationState.pending_emergency_since = $utcNow.ToString('o')
    }
    $CoordinationEscalationState.last_emergency_emit_at = $utcNow.ToString('o')
    $CoordinationEscalationState.emergency_emit_count = [int]$CoordinationEscalationState.emergency_emit_count + 1
    Write-JsonFile -PathValue $CoordinationEscalationStatePath -Payload $CoordinationEscalationState

    return $emergencyPayload
}

function Publish-ResolvedEmergencyCoordination {
    param(
        [Parameter(Mandatory = $true)]$CoordinationEscalationState,
        [Parameter(Mandatory = $true)][string]$CoordinationEscalationStatePath,
        [Parameter(Mandatory = $true)][string]$LocalEmergencyRequestPath,
        [Parameter(Mandatory = $true)][string]$RemoteEmergencyRequestPath,
        [Parameter(Mandatory = $true)]$Connections,
        [string]$ResolutionReason = '',
        [string]$ObjectiveId = ''
    )

    if ([string]::IsNullOrWhiteSpace([string]$CoordinationEscalationState.pending_emergency_request_id)) {
        return $null
    }

    $resolvedPayload = [pscustomobject]@{
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        source = 'tod-mim-emergency-request-v1'
        status = 'resolved'
        priority = 'none'
        escalation_level = 0
        request_id = [string]$CoordinationEscalationState.pending_emergency_request_id
        parent_request_id = [string]$CoordinationEscalationState.pending_emergency_parent_request_id
        objective_id = [string]$ObjectiveId
        issue_code = if ([string]::IsNullOrWhiteSpace([string]$CoordinationEscalationState.pending_emergency_issue_code)) { 'coordination_timeout_emergency_resolved' } else { [string]$CoordinationEscalationState.pending_emergency_issue_code + '_resolved' }
        issue_summary = 'TOD cleared the prior emergency coordination case.'
        requested_action = 'none'
        resolution_reason = if ([string]::IsNullOrWhiteSpace($ResolutionReason)) { 'Coordination is no longer pending.' } else { [string]$ResolutionReason }
        resolved_at = (Get-Date).ToUniversalTime().ToString('o')
    }

    Write-JsonFile -PathValue $LocalEmergencyRequestPath -Payload $resolvedPayload
    $resolvedJson = Get-Content -Path $LocalEmergencyRequestPath -Raw
    Write-RemoteFileFromText -Connections $Connections -RemotePath $RemoteEmergencyRequestPath -Content $resolvedJson

    $CoordinationEscalationState.pending_emergency_request_id = ''
    $CoordinationEscalationState.pending_emergency_issue_code = ''
    $CoordinationEscalationState.pending_emergency_issue_summary = ''
    $CoordinationEscalationState.pending_emergency_parent_request_id = ''
    $CoordinationEscalationState.pending_emergency_since = ''
    $CoordinationEscalationState.last_emergency_emit_at = ''
    $CoordinationEscalationState.emergency_emit_count = 0
    Write-JsonFile -PathValue $CoordinationEscalationStatePath -Payload $CoordinationEscalationState

    return $resolvedPayload
}

function Get-IdleSeconds {
    param([string]$Since)
    if ([string]::IsNullOrWhiteSpace($Since)) { return 99999 }
    [datetime]$dt = [datetime]::MinValue
    if ([datetime]::TryParse($Since, [ref]$dt)) {
        $utc = $dt.ToUniversalTime()
        return [int][math]::Floor(([DateTime]::UtcNow - $utc).TotalSeconds)
    }
    return 99999
}

function New-IdleWakeupState {
    param($ExistingState)
    return [pscustomobject]@{
        last_wakeup_at          = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_wakeup_at"])          { [string]$ExistingState.last_wakeup_at }          else { "" }
        last_wakeup_reason      = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_wakeup_reason"])      { [string]$ExistingState.last_wakeup_reason }      else { "" }
        last_self_task_id       = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_self_task_id"])       { [string]$ExistingState.last_self_task_id }       else { "" }
        last_self_task_catalog_index = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_self_task_catalog_index"]) { [int]$ExistingState.last_self_task_catalog_index } else { -1 }
        last_objective_advanced = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_objective_advanced"]) { [string]$ExistingState.last_objective_advanced } else { "" }
        last_engineer_run_signature = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_engineer_run_signature"]) { [string]$ExistingState.last_engineer_run_signature } else { "" }
        last_engineer_run_at        = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_engineer_run_at"])        { [string]$ExistingState.last_engineer_run_at }        else { "" }
        last_readiness_refresh_at   = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_readiness_refresh_at"])   { [string]$ExistingState.last_readiness_refresh_at }   else { "" }
        wakeup_count            = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["wakeup_count"])            { [int]$ExistingState.wakeup_count }                else { 0 }
    }
}

function Get-IdleWakeupPreferredTask {
    param([Parameter(Mandatory = $true)]$Tasks)

    $taskList = @($Tasks)
    if ($taskList.Count -eq 0) {
        return $null
    }

    $preferred = @($taskList | Where-Object {
            $status = if ($_.PSObject.Properties['status']) { ([string]$_.status).ToLowerInvariant() } else { '' }
            $status -in @('in_progress', 'open', 'planned', 'todo')
        } | Sort-Object updated_at, created_at -Descending | Select-Object -First 1)
    if ($preferred.Count -gt 0) {
        return $preferred[0]
    }

    return @($taskList | Sort-Object updated_at, created_at -Descending | Select-Object -First 1)[0]
}

function Get-IdleWakeupCandidateTask {
    param(
        [Parameter(Mandatory = $true)]$State,
        [string]$CurrentObjectiveId = ""
    )

    $terminalStatuses = @('pass', 'reviewed_pass', 'completed', 'closed', 'cancelled')
    $allTasks = if ($State -and $State.PSObject.Properties['tasks']) { @($State.tasks) } else { @() }
    $pendingTasks = @($allTasks | Where-Object {
            $status = if ($_.PSObject.Properties['status']) { ([string]$_.status).ToLowerInvariant() } else { '' }
            $status -notin $terminalStatuses
        })
    if ($pendingTasks.Count -eq 0) {
        return $null
    }

    if (-not [string]::IsNullOrWhiteSpace($CurrentObjectiveId)) {
        $currentObjectiveTasks = @($pendingTasks | Where-Object { [string]$_.objective_id -eq $CurrentObjectiveId })
        if ($currentObjectiveTasks.Count -gt 0) {
            $currentTask = Get-IdleWakeupPreferredTask -Tasks $currentObjectiveTasks
            if ($null -ne $currentTask) {
                return [pscustomobject]@{
                    objective_id = [string]$CurrentObjectiveId
                    task = $currentTask
                }
            }
        }
    }

    $openObjectives = if ($State -and $State.PSObject.Properties['objectives']) {
        @($State.objectives | Where-Object {
                $_.PSObject.Properties['status'] -and
                @('open', 'active', 'in_progress', 'planned') -contains ([string]$_.status).ToLowerInvariant()
            } | Sort-Object updated_at, created_at -Descending)
    }
    else {
        @()
    }

    foreach ($objective in $openObjectives) {
        $objectiveId = if ($objective.PSObject.Properties['id']) { [string]$objective.id } else { '' }
        if ([string]::IsNullOrWhiteSpace($objectiveId)) {
            continue
        }

        $objectiveTasks = @($pendingTasks | Where-Object { [string]$_.objective_id -eq $objectiveId })
        if ($objectiveTasks.Count -eq 0) {
            continue
        }

        $objectiveTask = Get-IdleWakeupPreferredTask -Tasks $objectiveTasks
        if ($null -ne $objectiveTask) {
            return [pscustomobject]@{
                objective_id = $objectiveId
                task = $objectiveTask
            }
        }
    }

    $fallbackTask = Get-IdleWakeupPreferredTask -Tasks $pendingTasks
    if ($null -eq $fallbackTask) {
        return $null
    }

    return [pscustomobject]@{
        objective_id = if ($fallbackTask.PSObject.Properties['objective_id']) { [string]$fallbackTask.objective_id } else { '' }
        task = $fallbackTask
    }
}

function Invoke-ExecutionReadinessRefresh {
    param(
        [Parameter(Mandatory = $true)][string]$ReadinessScriptAbs,
        [string]$Reason = ""
    )

    if ([string]::IsNullOrWhiteSpace($ReadinessScriptAbs) -or -not (Test-Path -Path $ReadinessScriptAbs)) {
        return [pscustomobject]@{
            ok = $false
            reason = 'script_missing'
            detail = $ReadinessScriptAbs
            payload = $null
        }
    }

    $refreshError = ''
    $payload = $null
    try {
        $raw = powershell -NoProfile -ExecutionPolicy Bypass -File $ReadinessScriptAbs -EmitJson 2>&1
        if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
            $refreshError = ("readiness refresh exited {0}" -f $LASTEXITCODE)
        }
        elseif ($null -ne $raw) {
            $payload = ConvertFrom-JsonCaseInsensitiveSafe -Text ($raw -join "`n")
        }
    }
    catch {
        $refreshError = [string]$_.Exception.Message
    }

    if (-not [string]::IsNullOrWhiteSpace($refreshError)) {
        if ([string]::IsNullOrWhiteSpace($Reason)) {
            Write-Warning ("[TOD-LISTENER] Execution-readiness refresh failed; continuing with latest available artifact: {0}" -f $refreshError)
        }
        else {
            Write-Warning ("[TOD-LISTENER] Execution-readiness refresh failed during {0}; continuing with latest available artifact: {1}" -f $Reason, $refreshError)
        }

        return [pscustomobject]@{
            ok = $false
            reason = 'refresh_failed'
            detail = $refreshError
            payload = $payload
        }
    }

    return [pscustomobject]@{
        ok = $true
        reason = 'refreshed'
        detail = if ($payload -and $payload.PSObject.Properties['output_path']) { [string]$payload.output_path } else { $ReadinessScriptAbs }
        payload = $payload
    }
}

function Set-ListenerReadinessSnapshot {
    param(
        [Parameter(Mandatory = $true)]$ListenerState,
        [AllowNull()]$ReadinessTrace = $null
    )

    if ($null -eq $ReadinessTrace) {
        return
    }

    $ListenerState.last_readiness_status = if ($ReadinessTrace.PSObject.Properties['status']) { [string]$ReadinessTrace.status } else { '' }
    $ListenerState.last_readiness_source = if ($ReadinessTrace.PSObject.Properties['source']) { [string]$ReadinessTrace.source } else { '' }
    $ListenerState.last_readiness_policy_outcome = if ($ReadinessTrace.PSObject.Properties['policy_outcome']) { [string]$ReadinessTrace.policy_outcome } else { '' }
    $ListenerState.last_readiness_execution_allowed = if ($ReadinessTrace.PSObject.Properties['execution_allowed']) { [bool]$ReadinessTrace.execution_allowed } else { $false }
    $ListenerState.last_readiness_valid = if ($ReadinessTrace.PSObject.Properties['valid']) { [bool]$ReadinessTrace.valid } else { $false }
    $ListenerState.last_readiness_recorded_at = (Get-Date).ToUniversalTime().ToString('o')
}

function Clear-BlockedRecoveryState {
    param([Parameter(Mandatory = $true)]$ListenerState)

    $ListenerState.blocked_resume_request_id = ''
    $ListenerState.blocked_resume_request_signature = ''
    $ListenerState.blocked_resume_task_id = ''
    $ListenerState.blocked_resume_objective_id = ''
    $ListenerState.blocked_resume_correlation_id = ''
    $ListenerState.blocked_resume_action = ''
    $ListenerState.blocked_resume_reason_code = ''
    $ListenerState.blocked_resume_summary = ''
    $ListenerState.blocked_resume_recorded_at = ''
    $ListenerState.blocked_resume_retry_attempted = $false
    $ListenerState.blocked_resume_retry_attempted_at = ''
}

function Save-BlockedRecoveryState {
    param(
        [Parameter(Mandatory = $true)]$ListenerState,
        [string]$RequestId = '',
        [string]$RequestSignature = '',
        [string]$TaskId = '',
        [string]$ObjectiveId = '',
        [string]$CorrelationId = '',
        [string]$Action = '',
        [string]$ReasonCode = '',
        [string]$Summary = '',
        [AllowNull()]$ReadinessTrace = $null
    )

    $ListenerState.blocked_resume_request_id = [string]$RequestId
    $ListenerState.blocked_resume_request_signature = [string]$RequestSignature
    $ListenerState.blocked_resume_task_id = [string]$TaskId
    $ListenerState.blocked_resume_objective_id = [string]$ObjectiveId
    $ListenerState.blocked_resume_correlation_id = [string]$CorrelationId
    $ListenerState.blocked_resume_action = [string]$Action
    $ListenerState.blocked_resume_reason_code = [string]$ReasonCode
    $ListenerState.blocked_resume_summary = [string]$Summary
    $ListenerState.blocked_resume_recorded_at = (Get-Date).ToUniversalTime().ToString('o')
    $ListenerState.blocked_resume_retry_attempted = $false
    $ListenerState.blocked_resume_retry_attempted_at = ''
    Set-ListenerReadinessSnapshot -ListenerState $ListenerState -ReadinessTrace $ReadinessTrace
}

function Invoke-BlockedRecoveryContinuationIfNeeded {
    param(
        [Parameter(Mandatory = $true)]$ListenerState,
        [Parameter(Mandatory = $true)][string]$ListenerStatePath,
        [Parameter(Mandatory = $true)][string]$TodScript,
        [AllowNull()]$IdleWakeupState = $null,
        [string]$IdleWakeupStatePath = ''
    )

    $requestId = if ($ListenerState.PSObject.Properties['blocked_resume_request_id']) { [string]$ListenerState.blocked_resume_request_id } else { '' }
    $taskId = if ($ListenerState.PSObject.Properties['blocked_resume_task_id']) { [string]$ListenerState.blocked_resume_task_id } else { '' }
    $objectiveId = if ($ListenerState.PSObject.Properties['blocked_resume_objective_id']) { [string]$ListenerState.blocked_resume_objective_id } else { '' }
    $action = if ($ListenerState.PSObject.Properties['blocked_resume_action'] -and -not [string]::IsNullOrWhiteSpace([string]$ListenerState.blocked_resume_action)) { [string]$ListenerState.blocked_resume_action } else { 'run-bridge-request' }

    if ([string]::IsNullOrWhiteSpace($taskId)) {
        return [pscustomobject]@{ resumed = $false; attempted = $false; reason = 'no_blocked_task' }
    }

    if ($ListenerState.PSObject.Properties['blocked_resume_retry_attempted'] -and [bool]$ListenerState.blocked_resume_retry_attempted) {
        return [pscustomobject]@{ resumed = $false; attempted = $false; reason = 'retry_already_attempted'; request_id = $requestId; task_id = $taskId; objective_id = $objectiveId }
    }

    $previousPolicyOutcome = if ($ListenerState.PSObject.Properties['last_readiness_policy_outcome']) { [string]$ListenerState.last_readiness_policy_outcome } else { '' }
    $previousExecutionAllowed = if ($ListenerState.PSObject.Properties['last_readiness_execution_allowed']) { [bool]$ListenerState.last_readiness_execution_allowed } else { $false }
    $currentReadiness = Get-ExecutionReadinessTrace -TodScriptAbs $TodScript -Action $action
    $currentExecutionAllowed = ($null -ne $currentReadiness -and $currentReadiness.PSObject.Properties['execution_allowed'] -and [bool]$currentReadiness.execution_allowed)
    $currentValid = ($null -ne $currentReadiness -and $currentReadiness.PSObject.Properties['valid'] -and [bool]$currentReadiness.valid)
    $currentPolicyBlocked = ($null -ne $currentReadiness -and $currentReadiness.PSObject.Properties['policy_outcome'] -and [string]::Equals([string]$currentReadiness.policy_outcome, 'block', [System.StringComparison]::OrdinalIgnoreCase))
    $previousBlocked = ([string]::Equals($previousPolicyOutcome, 'block', [System.StringComparison]::OrdinalIgnoreCase) -or (-not $previousExecutionAllowed))
    $recovered = ($previousBlocked -and $currentExecutionAllowed -and $currentValid -and (-not $currentPolicyBlocked))
    $eventPath = [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($ListenerStatePath), 'TOD_BLOCKED_RECOVERY_EVENT.latest.json')

    Set-ListenerReadinessSnapshot -ListenerState $ListenerState -ReadinessTrace $currentReadiness

    if (-not $recovered) {
        Write-JsonFile -PathValue $ListenerStatePath -Payload $ListenerState
        return [pscustomobject]@{ resumed = $false; attempted = $false; reason = 'readiness_not_recovered'; request_id = $requestId; task_id = $taskId; objective_id = $objectiveId; readiness = $currentReadiness }
    }

    $attemptedAt = (Get-Date).ToUniversalTime().ToString('o')
    $ListenerState.blocked_resume_retry_attempted = $true
    $ListenerState.blocked_resume_retry_attempted_at = $attemptedAt

    try {
        $engineerRunRaw = & $TodScript engineer-run -ObjectiveId $objectiveId -TaskId $taskId -Top 5 2>&1
        $engineerRun = ($engineerRunRaw -join '') | ConvertFrom-Json -ErrorAction SilentlyContinue
        $ListenerState.last_execution_at = $attemptedAt

        if ($null -ne $IdleWakeupState) {
            $IdleWakeupState.last_engineer_run_signature = ('{0}|{1}|recovery_resume|{2}' -f $objectiveId, $taskId, $attemptedAt)
            $IdleWakeupState.last_engineer_run_at = $attemptedAt
            if (-not [string]::IsNullOrWhiteSpace($IdleWakeupStatePath)) {
                Write-JsonFile -PathValue $IdleWakeupStatePath -Payload $IdleWakeupState
            }
        }

        Write-JsonFile -PathValue $ListenerStatePath -Payload $ListenerState
        Write-JsonFile -PathValue $eventPath -Payload ([pscustomobject]@{
            generated_at = $attemptedAt
            source = 'tod-blocked-recovery-v1'
            status = 'resumed'
            recovery_transition = 'blocked_to_valid'
            request_id = $requestId
            task_id = $taskId
            objective_id = $objectiveId
            action = $action
            retry_attempted = $true
            previous_readiness = [pscustomobject]@{
                policy_outcome = $previousPolicyOutcome
                execution_allowed = $previousExecutionAllowed
            }
            current_readiness = $currentReadiness
            engineer_run = $engineerRun
        })

        return [pscustomobject]@{ resumed = $true; attempted = $true; reason = 'blocked_task_resumed'; request_id = $requestId; task_id = $taskId; objective_id = $objectiveId; action = $action; readiness = $currentReadiness; engineer_run = $engineerRun }
    }
    catch {
        $errorMessage = [string]$_.Exception.Message
        Write-JsonFile -PathValue $ListenerStatePath -Payload $ListenerState
        Write-JsonFile -PathValue $eventPath -Payload ([pscustomobject]@{
            generated_at = $attemptedAt
            source = 'tod-blocked-recovery-v1'
            status = 'resume_failed'
            recovery_transition = 'blocked_to_valid'
            request_id = $requestId
            task_id = $taskId
            objective_id = $objectiveId
            action = $action
            retry_attempted = $true
            current_readiness = $currentReadiness
            error = $errorMessage
        })

        return [pscustomobject]@{ resumed = $false; attempted = $true; reason = 'resume_failed'; request_id = $requestId; task_id = $taskId; objective_id = $objectiveId; action = $action; readiness = $currentReadiness; error = $errorMessage }
    }
}

# Self-improvement task catalog — rotated through when MIM has no pending work.
$script:IdleAdvancementObjectiveTitle = 'TOD Autonomous Advancement Loop'
$script:SelfImprovementTasks = @(
    [pscustomobject]@{ title = "Improve listener reliability and retry discipline";                                      scope = "scripts/Start-TODMimPacketListener.ps1, tests/TOD.PacketListener*.Tests.ps1"; criteria = "One concrete reliability improvement is implemented or a bounded follow-on task is added with evidence."; category = 'improve' }
    [pscustomobject]@{ title = "Learn from recent engineer runs and summarize failure patterns";                         scope = "tod/data/state.json, scripts/TOD-Engineer.ps1, shared_state";               criteria = "A short failure-pattern summary is produced and at least one mitigation task is added or updated."; category = 'learn' }
    [pscustomobject]@{ title = "Explore next-stage TOD autonomy opportunities while MIM is quiet";                      scope = "docs, scripts, shared_state";                                              criteria = "At least three candidate advancement directions are identified and one is converted into a bounded task."; category = 'explore' }
    [pscustomobject]@{ title = "Run full regression suite and document any new failures or flakiness";                  scope = "scripts/TOD.ps1, tod/tests";                                                criteria = "Regression report produced; any failures triaged and recorded in failure taxonomy."; category = 'improve' }
    [pscustomobject]@{ title = "Audit MIM-TOD packet protocol for latency, retry, and edge-case coverage";            scope = "scripts/Start-TODMimPacketListener.ps1, scripts/Push-SyntheticResult.ps1"; criteria = "Protocol audit complete; any gaps filed as follow-on tasks."; category = 'learn' }
    [pscustomobject]@{ title = "Scan state.json for OOM risk and apply compaction if size exceeds 2 MiB";             scope = "tod/data/state.json, scripts/TOD.ps1";                                      criteria = "state.json size confirmed below 2 MiB or compacted; no data loss."; category = 'improve' }
)

function Get-IdleAdvancementObjective {
    param([Parameter(Mandatory = $true)]$State)

    if ($null -eq $State -or -not $State.PSObject.Properties['objectives']) {
        return $null
    }

    $openStatuses = @('open', 'active', 'in_progress', 'planned')
    $matchingObjective = $State.objectives | Where-Object {
        $status = if ($_.PSObject.Properties['status']) { ([string]$_.status).ToLowerInvariant() } else { '' }
        $title = if ($_.PSObject.Properties['title']) { [string]$_.title } else { '' }
        $status -in $openStatuses -and $title -like ("{0}*" -f $script:IdleAdvancementObjectiveTitle)
    } | Sort-Object updated_at, created_at -Descending | Select-Object -First 1

    return $matchingObjective
}

function Get-NextSelfImprovementTaskTemplate {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][string]$ObjectiveId,
        [Parameter(Mandatory = $true)]$IdleWakeupState
    )

    $terminalStatuses = @('pass', 'reviewed_pass', 'completed', 'closed', 'cancelled')
    $objectiveTasks = if ($State -and $State.PSObject.Properties['tasks']) {
        @($State.tasks | Where-Object { [string]$_.objective_id -eq $ObjectiveId })
    }
    else {
        @()
    }

    $pendingTitles = @($objectiveTasks | Where-Object {
            $status = if ($_.PSObject.Properties['status']) { ([string]$_.status).ToLowerInvariant() } else { '' }
            $status -notin $terminalStatuses
        } | ForEach-Object { if ($_.PSObject.Properties['title']) { [string]$_.title } })

    $catalog = @($script:SelfImprovementTasks)
    if ($catalog.Count -eq 0) {
        return $null
    }

    $startIndex = [Math]::Max(-1, [int]$IdleWakeupState.last_self_task_catalog_index)
    for ($offset = 1; $offset -le $catalog.Count; $offset++) {
        $index = ($startIndex + $offset) % $catalog.Count
        $candidate = $catalog[$index]
        if ($null -eq ($pendingTitles | Where-Object { [string]::Equals([string]$_, [string]$candidate.title, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)) {
            return [pscustomobject]@{
                template = $candidate
                index = $index
            }
        }
    }

    return $null
}

function Ensure-IdleAdvancementObjective {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][string]$TodScript,
        [Parameter(Mandatory = $true)][int]$IdleSeconds
    )

    $existingObjective = Get-IdleAdvancementObjective -State $State
    if ($null -ne $existingObjective -and $existingObjective.PSObject.Properties['id']) {
        return [pscustomobject]@{
            objective_id = [string]$existingObjective.id
            created = $false
        }
    }

    try {
        $newObjectiveRaw = & $TodScript new-objective `
            -Title $script:IdleAdvancementObjectiveTitle `
            -Description ("Autonomous idle-development loop created after {0}s of inactivity so TOD can improve, learn, and explore while waiting on MIM." -f $IdleSeconds) `
            -SuccessCriteria "At least one bounded advancement task reaches reviewed_pass and produces a concrete follow-on improvement, learning note, or exploration artifact." 2>&1
        $newObjective = ($newObjectiveRaw -join '') | ConvertFrom-Json -ErrorAction SilentlyContinue
        $newObjectiveId = if ($newObjective -and $newObjective.PSObject.Properties['id']) { [string]$newObjective.id } elseif ($newObjective -and $newObjective.PSObject.Properties['local']) { [string]$newObjective.local.id } else { '' }
        if (-not [string]::IsNullOrWhiteSpace($newObjectiveId)) {
            return [pscustomobject]@{
                objective_id = $newObjectiveId
                created = $true
            }
        }
    }
    catch {
        Write-Warning ("[TOD-LISTENER][IDLE-WAKEUP] Failed to create idle advancement objective: {0}" -f $_.Exception.Message)
    }

    return [pscustomobject]@{
        objective_id = ''
        created = $false
    }
}

function Invoke-IdleWakeupIfNeeded {
    param(
        [Parameter(Mandatory=$true)]$ListenerState,
        [Parameter(Mandatory=$true)]$IdleWakeupState,
        [Parameter(Mandatory=$true)][string]$IdleWakeupStatePath,
        [Parameter(Mandatory=$true)][string]$TodScript,
        [Parameter(Mandatory=$true)][string]$SyncScript,
        [Parameter(Mandatory=$true)][string]$ReadinessScript,
        [Parameter(Mandatory=$true)][string]$HostAlias,
        [Parameter(Mandatory=$true)][string]$RemoteRoot,
        [Parameter(Mandatory=$true)][string]$SyncStageRoot,
        [Parameter(Mandatory=$true)][int]$IdleThreshold,
        [Parameter(Mandatory=$true)][int]$Cooldown,
        [switch]$RunOnce
    )

    if ($RunOnce) { return }

    # Gate 1: has it been idle long enough?
    $idleSec = Get-IdleSeconds -Since ([string]$ListenerState.last_execution_at)
    if ($idleSec -lt $IdleThreshold) { return }

    # Gate 2: cooldown since last wakeup action?
    $cooldownSec = Get-IdleSeconds -Since ([string]$IdleWakeupState.last_wakeup_at)
    if ($cooldownSec -lt $Cooldown) { return }

    Write-Host ("[TOD-LISTENER][IDLE-WAKEUP] Idle for {0}s (threshold={1}s). Running proactive wake-up." -f $idleSec, $IdleThreshold)

    $readinessRefresh = Invoke-ExecutionReadinessRefresh -ReadinessScriptAbs $ReadinessScript -Reason "idle wakeup"
    if ([bool]$readinessRefresh.ok) {
        $IdleWakeupState.last_readiness_refresh_at = (Get-Date).ToUniversalTime().ToString("o")
    }

    # Refresh shared state before evaluating using the same SSH-backed path as canonical publication.
    $null = Invoke-SharedStateSyncRefresh -SyncScriptAbs $SyncScript -HostAlias $HostAlias -RemoteRoot $RemoteRoot -SyncStageRoot $SyncStageRoot -Reason "idle wakeup"

    $nextActionsPath = Get-LocalPath -PathValue "shared_state/next_actions.json"
    $statePath       = Get-LocalPath -PathValue "tod/data/state.json"
    $nextActions     = Read-JsonFileIfExists -PathValue $nextActionsPath
    $state           = Read-JsonFileIfExists -PathValue $statePath

    $currentObjId = if ($nextActions -and $nextActions.PSObject.Properties["current_objective_in_progress"]) { [string]$nextActions.current_objective_in_progress } else { "" }
    $roadmap      = if ($nextActions -and $nextActions.PSObject.Properties["tod_catchup_roadmap"])           { @($nextActions.tod_catchup_roadmap) } else { @() }
    $wakeupReason = "idle_check"
    $actionTaken  = ""
    $engineerRun  = $null

    if ($null -ne $state) {
        $terminalStatuses = @("pass", "reviewed_pass", "completed", "closed", "cancelled")
        $currentTasks = @($state.tasks | Where-Object { [string]$_.objective_id -eq $currentObjId })
        $pendingTasks = @($currentTasks | Where-Object { [string]$_.status -notin $terminalStatuses })
        $allPendingTasks = @($state.tasks | Where-Object { [string]$_.status -notin $terminalStatuses })
        $openObjective = $state.objectives | Where-Object { [string]$_.status -eq "open" } | Select-Object -First 1

        if ($currentTasks.Count -gt 0 -and $pendingTasks.Count -eq 0) {
            # Current objective fully done — advance to next roadmap entry
            $wakeupReason  = "objective_complete_advance"
            $advanceTarget = $null
            foreach ($item in $roadmap) {
                $rid   = if ($item.PSObject.Properties["id"])     { [string]$item.id     } else { "" }
                $rstat = if ($item.PSObject.Properties["status"]) { [string]$item.status } else { "" }
                if ([string]::IsNullOrWhiteSpace($rid) -or $rstat -eq "completed") { continue }
                $alreadyExists = $null -ne ($state.objectives | Where-Object { [string]$_.title -like "*$rid*" -and [string]$_.status -ne "completed" })
                if (-not $alreadyExists) { $advanceTarget = $item; break }
            }

            if ($null -ne $advanceTarget) {
                $rtitle = if ($advanceTarget.PSObject.Properties["title"]) { [string]$advanceTarget.title } else { "Self-improvement" }
                $rid    = if ($advanceTarget.PSObject.Properties["id"])    { [string]$advanceTarget.id    } else { "SELF" }
                Write-Host ("[TOD-LISTENER][IDLE-WAKEUP] Advancing to roadmap item: {0} - {1}" -f $rid, $rtitle)
                try {
                    $newObjRaw = & $TodScript new-objective `
                        -Title "${rid}: ${rtitle}" `
                        -Description "Autonomous advance from idle wake-up. Previous objective complete. Roadmap: $rid." `
                        -SuccessCriteria "First task in new objective reaches reviewed_pass." 2>&1
                    $newObj   = ($newObjRaw -join "") | ConvertFrom-Json -ErrorAction SilentlyContinue
                    $newObjId = if ($newObj -and $newObj.PSObject.Properties["id"]) { [string]$newObj.id } `
                                elseif ($newObj -and $newObj.PSObject.Properties["local"]) { [string]$newObj.local.id } `
                                else { "" }
                    if (-not [string]::IsNullOrWhiteSpace($newObjId)) {
                        $null = & $TodScript add-task `
                            -ObjectiveId $newObjId `
                            -Title "Initial scoping and planning for $rid" `
                            -Description "Decompose '$rtitle' into steps. Review existing code, identify gaps, plan implementation." `
                            -Scope "scripts/, tod/" `
                            -AcceptanceCriteria "Scoping complete; at least one follow-on implementation task added to this objective." 2>&1
                        $actionTaken = "created_objective_$newObjId"
                        $IdleWakeupState.last_objective_advanced = $rid
                        Write-Host ("[TOD-LISTENER][IDLE-WAKEUP] Created objective {0} and first task for {1}." -f $newObjId, $rid)
                    }
                } catch {
                    Write-Warning ("[TOD-LISTENER][IDLE-WAKEUP] Failed to create roadmap objective: {0}" -f $_.Exception.Message)
                }
            } else {
                $wakeupReason = "self_improve_roadmap_exhausted"
            }
        }

        # Self-improvement only when there is no actionable pending work left to resume.
        if ([string]::IsNullOrWhiteSpace($actionTaken) -and $allPendingTasks.Count -eq 0) {
            $advancementObjective = Ensure-IdleAdvancementObjective -State $state -TodScript $TodScript -IdleSeconds $idleSec
            $advancementObjectiveId = if ($advancementObjective -and $advancementObjective.PSObject.Properties['objective_id']) { [string]$advancementObjective.objective_id } else { '' }
            if ($advancementObjective.created -and -not [string]::IsNullOrWhiteSpace($advancementObjectiveId)) {
                $actionTaken = "created_advancement_objective_$advancementObjectiveId"
                $wakeupReason = 'self_improve_bootstrap'
                Write-Host ("[TOD-LISTENER][IDLE-WAKEUP] Created idle advancement objective: {0}" -f $advancementObjectiveId)
            }

            if (-not [string]::IsNullOrWhiteSpace($advancementObjectiveId)) {
                $taskTemplateSelection = Get-NextSelfImprovementTaskTemplate -State $state -ObjectiveId $advancementObjectiveId -IdleWakeupState $IdleWakeupState
                if ($null -ne $taskTemplateSelection -and $taskTemplateSelection.template) {
                    $selfTask = $taskTemplateSelection.template
                    $category = if ($selfTask.PSObject.Properties['category']) { [string]$selfTask.category } else { 'self-improvement' }
                    Write-Host ("[TOD-LISTENER][IDLE-WAKEUP] No pending MIM work. Creating self-improvement task: {0}" -f [string]$selfTask.title)
                    try {
                        $taskRaw = & $TodScript add-task `
                            -ObjectiveId $advancementObjectiveId `
                            -Title ([string]$selfTask.title) `
                            -Description ("Autonomous {0} task created by idle wake-up after {1}s of inactivity so TOD can improve while waiting on MIM." -f $category, $idleSec) `
                            -Scope ([string]$selfTask.scope) `
                            -AcceptanceCriteria ([string]$selfTask.criteria) 2>&1
                        $newTask   = ($taskRaw -join '') | ConvertFrom-Json -ErrorAction SilentlyContinue
                        $newTaskId = if ($newTask -and $newTask.PSObject.Properties['id']) { [string]$newTask.id } else { '' }
                        if (-not [string]::IsNullOrWhiteSpace($newTaskId)) {
                            $IdleWakeupState.last_self_task_id = $newTaskId
                            $IdleWakeupState.last_self_task_catalog_index = [int]$taskTemplateSelection.index
                            $actionTaken = "created_self_task_$newTaskId"
                            $wakeupReason = 'self_improve'
                            Write-Host ("[TOD-LISTENER][IDLE-WAKEUP] Self-improvement task created: {0}" -f $newTaskId)
                        }
                    } catch {
                        Write-Warning ("[TOD-LISTENER][IDLE-WAKEUP] Failed to create self-improvement task: {0}" -f $_.Exception.Message)
                    }
                } else {
                    $wakeupReason = 'self_improve_no_candidates'
                    Write-Host '[TOD-LISTENER][IDLE-WAKEUP] No eligible self-improvement tasks remaining. Waiting for the next idle-development cycle.'
                }
            }
        }

        $stateAfterWakeup = Read-JsonFileIfExists -PathValue $statePath
        if ($null -eq $stateAfterWakeup) {
            $stateAfterWakeup = $state
        }

        $candidateTask = Get-IdleWakeupCandidateTask -State $stateAfterWakeup -CurrentObjectiveId $currentObjId
        if ($null -ne $candidateTask -and $candidateTask.task) {
            $candidateTaskId = if ($candidateTask.task.PSObject.Properties['id']) { [string]$candidateTask.task.id } else { '' }
            $candidateObjectiveId = if (-not [string]::IsNullOrWhiteSpace([string]$candidateTask.objective_id)) { [string]$candidateTask.objective_id } elseif ($candidateTask.task.PSObject.Properties['objective_id']) { [string]$candidateTask.task.objective_id } else { '' }
            $candidateTaskStatus = if ($candidateTask.task.PSObject.Properties['status']) { [string]$candidateTask.task.status } else { '' }
            $candidateTaskUpdatedAt = if ($candidateTask.task.PSObject.Properties['updated_at']) { [string]$candidateTask.task.updated_at } elseif ($candidateTask.task.PSObject.Properties['created_at']) { [string]$candidateTask.task.created_at } else { '' }
            $candidateSignature = ("{0}|{1}|{2}|{3}" -f $candidateObjectiveId, $candidateTaskId, $candidateTaskStatus, $candidateTaskUpdatedAt)

            $sameEngineerSignature = [string]::Equals($candidateSignature, [string]$IdleWakeupState.last_engineer_run_signature, [System.StringComparison]::OrdinalIgnoreCase)
            $engineerRunAgeSec = Get-IdleSeconds -Since ([string]$IdleWakeupState.last_engineer_run_at)
            $engineerRepingSeconds = [Math]::Max($Cooldown, [Math]::Max(120, $IdleThreshold))

            if (-not [string]::IsNullOrWhiteSpace($candidateTaskId) -and ((-not $sameEngineerSignature) -or ($engineerRunAgeSec -ge $engineerRepingSeconds))) {
                Write-Host ("[TOD-LISTENER][IDLE-WAKEUP] Resuming pending task via engineer-run: {0}" -f $candidateTaskId)
                try {
                    $engineerRunRaw = & $TodScript engineer-run -ObjectiveId $candidateObjectiveId -TaskId $candidateTaskId -Top 5 2>&1
                    $engineerRun = ($engineerRunRaw -join "") | ConvertFrom-Json -ErrorAction SilentlyContinue
                    $IdleWakeupState.last_engineer_run_signature = $candidateSignature
                    $IdleWakeupState.last_engineer_run_at = (Get-Date).ToUniversalTime().ToString("o")
                    $ListenerState.last_execution_at = (Get-Date).ToUniversalTime().ToString("o")
                    $actionTaken = "engineer_run_$candidateTaskId"
                    $wakeupReason = if ($sameEngineerSignature) { 'resume_pending_task_reping' } else { 'resume_pending_task' }
                }
                catch {
                    Write-Warning ("[TOD-LISTENER][IDLE-WAKEUP] Failed to run engineer-run for task {0}: {1}" -f $candidateTaskId, $_.Exception.Message)
                }
            }
        }
    }

    # Persist wakeup state and emit event file
    $IdleWakeupState.last_wakeup_at     = (Get-Date).ToUniversalTime().ToString("o")
    $IdleWakeupState.last_wakeup_reason = $wakeupReason
    $IdleWakeupState.wakeup_count       = [int]$IdleWakeupState.wakeup_count + 1
    Write-JsonFile -PathValue $IdleWakeupStatePath -Payload $IdleWakeupState

    $idleEventPath = [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($IdleWakeupStatePath), "TOD_IDLE_WAKEUP_EVENT.latest.json")
    Write-JsonFile -PathValue $idleEventPath -Payload ([pscustomobject]@{
        generated_at  = (Get-Date).ToUniversalTime().ToString("o")
        source        = "tod-idle-wakeup-v1"
        idle_sec      = $idleSec
        threshold_sec = $IdleThreshold
        reason        = $wakeupReason
        readiness_refresh = [pscustomobject]@{
            ok = if ($null -ne $readinessRefresh) { [bool]$readinessRefresh.ok } else { $false }
            reason = if ($null -ne $readinessRefresh -and $readinessRefresh.PSObject.Properties['reason']) { [string]$readinessRefresh.reason } else { '' }
            detail = if ($null -ne $readinessRefresh -and $readinessRefresh.PSObject.Properties['detail']) { [string]$readinessRefresh.detail } else { '' }
        }
        engineer_run = if ($null -ne $engineerRun) { $engineerRun } else { $null }
        action_taken  = $actionTaken
        wakeup_count  = [int]$IdleWakeupState.wakeup_count
    })
}

function New-QuarantineState {
    param($ExistingState)

    return [pscustomobject]@{
        quarantined_request_id = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["quarantined_request_id"]) { [string]$ExistingState.quarantined_request_id } else { "" }
        quarantine_applied_at  = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["quarantine_applied_at"])  { [string]$ExistingState.quarantine_applied_at  } else { "" }
        fail_cycle_count       = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["fail_cycle_count"])       { [int]$ExistingState.fail_cycle_count           } else { 0 }
        last_fail_request_id   = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_fail_request_id"])   { [string]$ExistingState.last_fail_request_id    } else { "" }
    }
}

function Get-CoordinationPriority {
    param([Parameter(Mandatory = $true)][int]$EscalationLevel)

    switch ($EscalationLevel) {
        { $_ -le 1 } { return "P0" }
        2 { return "P0-ESC-1" }
        3 { return "P0-ESC-2" }
        default { return "P0-CRITICAL" }
    }
}

function Test-CoordinationIsRegressionRelated {
    param(
        [AllowNull()]$CoordinationRequest = $null,
        [AllowNull()]$CoordinationEscalationState = $null
    )

    $issueCode = if ($CoordinationRequest -and $CoordinationRequest.PSObject.Properties["issue_code"]) { [string]$CoordinationRequest.issue_code } else { "" }
    $pendingIssueCode = if ($CoordinationEscalationState -and $CoordinationEscalationState.PSObject.Properties["pending_issue_code"]) { [string]$CoordinationEscalationState.pending_issue_code } else { "" }

    return (
        [string]::IsNullOrWhiteSpace($issueCode) -or
        ($issueCode -match "regression") -or
        ($pendingIssueCode -match "regression")
    )
}

function Publish-ContractViolationCoordination {
    param(
        [Parameter(Mandatory = $true)]$CoordinationEscalationState,
        [Parameter(Mandatory = $true)][string]$CoordinationEscalationStatePath,
        [Parameter(Mandatory = $true)][string]$LocalCoordinationRequestPath,
        [Parameter(Mandatory = $true)][string]$RemoteCoordinationRequestPath,
        [Parameter(Mandatory = $true)]$Connections,
        [Parameter(Mandatory = $true)][string]$RequestId,
        [string]$ObjectiveId = '',
        [string]$TaskId = '',
        [string]$CorrelationId = '',
        [Parameter(Mandatory = $true)][string]$PacketKind,
        [AllowNull()]$Packet = $null,
        [AllowNull()]$Violation = $null,
        [string]$Action = '',
        [AllowNull()]$BridgeRuntime = $null,
        [string]$RuntimeViolationPath = ''
    )

    $utcNow = (Get-Date).ToUniversalTime()
    $violationEntries = @()
    if ($Violation -and $Violation.PSObject.Properties['violations']) {
        foreach ($entry in @($Violation.violations)) {
            if ($null -eq $entry) { continue }
            $violationEntries += [pscustomobject]@{
                code = if ($entry.PSObject.Properties['code']) { [string]$entry.code } else { '' }
                detail = if ($entry.PSObject.Properties['detail']) { [string]$entry.detail } else { '' }
                field = if ($entry.PSObject.Properties['field']) { [string]$entry.field } else { '' }
                expected = if ($entry.PSObject.Properties['expected']) { [string]$entry.expected } else { '' }
                actual = if ($entry.PSObject.Properties['actual']) { [string]$entry.actual } else { '' }
            }
        }
    }

    $packetKindLabel = [string]$PacketKind
    $packetKindIssueCode = if ([string]::IsNullOrWhiteSpace($packetKindLabel)) { 'unknown' } else { $packetKindLabel.ToLowerInvariant() }
    $violationSummary = if ($violationEntries.Count -gt 0) {
        ($violationEntries | ForEach-Object { [string]$_.code + ':' + [string]$_.detail }) -join '; '
    }
    else {
        'runtime_contract_validation_failed'
    }
    $issueCode = 'runtime_contract_violation_' + $packetKindIssueCode

    if (
        -not [string]::Equals([string]$CoordinationEscalationState.pending_request_id, [string]$RequestId, [System.StringComparison]::OrdinalIgnoreCase) -or
        -not [string]::Equals([string]$CoordinationEscalationState.pending_issue_code, $issueCode, [System.StringComparison]::OrdinalIgnoreCase) -or
        -not [string]::Equals([string]$CoordinationEscalationState.pending_issue_summary, $violationSummary, [System.StringComparison]::Ordinal)
    ) {
        $CoordinationEscalationState.pending_request_id = [string]$RequestId
        $CoordinationEscalationState.pending_issue_code = $issueCode
        $CoordinationEscalationState.pending_issue_summary = $violationSummary
        $CoordinationEscalationState.pending_since = $utcNow.ToString('o')
        $CoordinationEscalationState.last_emit_at = ''
        $CoordinationEscalationState.last_emitted_level = 0
        $CoordinationEscalationState.emit_count = 0
    }

    $pendingSinceUtc = Get-DateOrMinValue -Value ([string]$CoordinationEscalationState.pending_since)
    if ($pendingSinceUtc -eq [datetime]::MinValue) {
        $pendingSinceUtc = $utcNow
        $CoordinationEscalationState.pending_since = $pendingSinceUtc.ToString('o')
    }

    $elapsedMinutes = 0
    try {
        $elapsedMinutes = [int][math]::Floor((New-TimeSpan -Start $pendingSinceUtc -End $utcNow).TotalMinutes)
    }
    catch {
        $elapsedMinutes = 0
    }

    $targetEscalationLevel = [math]::Max(1, ([int][math]::Floor($elapsedMinutes / 1) + 1))
    $lastEmitUtc = Get-DateOrMinValue -Value ([string]$CoordinationEscalationState.last_emit_at)
    $minutesSinceLastEmit = if ($lastEmitUtc -eq [datetime]::MinValue) { 9999 } else { [int][math]::Floor((New-TimeSpan -Start $lastEmitUtc -End $utcNow).TotalMinutes) }
    $shouldEmitCoordination = ($CoordinationEscalationState.last_emitted_level -lt $targetEscalationLevel) -or ($minutesSinceLastEmit -ge 1)
    if (-not $shouldEmitCoordination) {
        return $null
    }

    $coordinationRequest = [pscustomobject]@{
        generated_at = $utcNow.ToString('o')
        source = 'tod-mim-coordination-request-v1'
        priority = Get-CoordinationPriority -EscalationLevel $targetEscalationLevel
        escalation_level = [int]$targetEscalationLevel
        request_id = [string]$RequestId
        objective_id = [string]$ObjectiveId
        task_id = [string]$TaskId
        correlation_id = [string]$CorrelationId
        issue_code = $issueCode
        issue_summary = ('TOD rejected {0} because runtime contract validation failed.' -f $packetKindLabel.ToUpperInvariant())
        packet_kind = $packetKindIssueCode
        contract_delta = @($violationEntries)
        evidence = [pscustomobject]@{
            command_status = 'contract_violation_rejected'
            action = [string]$Action
            packet_status = if ($Packet -and $Packet.PSObject.Properties['status']) { [string]$Packet.status } else { '' }
            result_reason_code = if ($Packet -and $Packet.PSObject.Properties['result_reason_code']) { [string]$Packet.result_reason_code } else { '' }
            runtime_violation_path = [string]$RuntimeViolationPath
            summary = $violationSummary
        }
        requested_action = 'Align the shared runtime contract with TOD, acknowledge the mismatch, and reissue only after the packet schema/fields are corrected.'
        required_ack = [pscustomobject]@{
            ack_file = 'MIM_TOD_COORDINATION_ACK.latest.json'
            ack_fields = @('acknowledged', 'acknowledged_at', 'request_id', 'decision', 'reason', 'target_dispatch_task_id')
            timeout_seconds = 60
        }
        bridge_runtime = $BridgeRuntime
    }

    Write-JsonFile -PathValue $LocalCoordinationRequestPath -Payload $coordinationRequest
    $coordinationJson = Get-Content -Path $LocalCoordinationRequestPath -Raw
    Write-RemoteFileFromText -Connections $Connections -RemotePath $RemoteCoordinationRequestPath -Content $coordinationJson

    $CoordinationEscalationState.last_emit_at = $utcNow.ToString('o')
    $CoordinationEscalationState.last_emitted_level = [int]$targetEscalationLevel
    $CoordinationEscalationState.emit_count = [int]$CoordinationEscalationState.emit_count + 1
    Write-JsonFile -PathValue $CoordinationEscalationStatePath -Payload $CoordinationEscalationState

    return $coordinationRequest
}

function Publish-ResolvedCoordination {
    param(
        [Parameter(Mandatory = $true)]$CoordinationEscalationState,
        [Parameter(Mandatory = $true)][string]$CoordinationEscalationStatePath,
        [Parameter(Mandatory = $true)][string]$LocalCoordinationRequestPath,
        [Parameter(Mandatory = $true)][string]$RemoteCoordinationRequestPath,
        [Parameter(Mandatory = $true)]$Connections,
        [Parameter(Mandatory = $true)][string]$RequestId,
        [string]$ObjectiveId = '',
        [string]$IssueCode = '',
        [string]$IssueSummary = '',
        [AllowNull()]$Evidence = $null,
        [string]$ResolutionReason = '',
        [AllowNull()]$BridgeRuntime = $null,
        [string]$ResolutionDecision = 'auto_resolved'
    )

    Clear-CoordinationEscalationState -State $CoordinationEscalationState -Reason $ResolutionReason -RequestId $RequestId
    $CoordinationEscalationState.last_ack_decision = $ResolutionDecision
    Write-JsonFile -PathValue $CoordinationEscalationStatePath -Payload $CoordinationEscalationState

    $coordinationResolved = [pscustomobject]@{
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        source = 'tod-mim-coordination-request-v1'
        status = 'resolved'
        priority = 'none'
        escalation_level = 0
        request_id = [string]$RequestId
        objective_id = [string]$ObjectiveId
        issue_code = [string]$IssueCode
        issue_summary = [string]$IssueSummary
        evidence = $Evidence
        requested_action = 'none'
        resolution_reason = [string]$ResolutionReason
        resolved_at = (Get-Date).ToUniversalTime().ToString('o')
        bridge_runtime = $BridgeRuntime
    }

    Write-JsonFile -PathValue $LocalCoordinationRequestPath -Payload $coordinationResolved
    try {
        $coordinationResolvedJson = Get-Content -Path $LocalCoordinationRequestPath -Raw
        Write-RemoteFileFromText -Connections $Connections -RemotePath $RemoteCoordinationRequestPath -Content $coordinationResolvedJson
    }
    catch {
        Write-Warning ('[TOD-LISTENER] Unable to publish resolved coordination status to remote: {0}' -f $_.Exception.Message)
    }

    return $coordinationResolved
}

function Test-ResultCanAutoResolveContractViolation {
    param([AllowNull()]$ResultPacket = $null)

    if ($null -eq $ResultPacket) {
        return $false
    }

    $status = if ($ResultPacket.PSObject.Properties['status']) {
        ([string]$ResultPacket.status).Trim().ToLowerInvariant()
    }
    else {
        ''
    }
    $resultStatus = if ($ResultPacket.PSObject.Properties['result_status']) {
        ([string]$ResultPacket.result_status).Trim().ToLowerInvariant()
    }
    else {
        ''
    }
    $reasonCode = if ($ResultPacket.PSObject.Properties['result_reason_code']) {
        ([string]$ResultPacket.result_reason_code).Trim().ToLowerInvariant()
    }
    else {
        ''
    }

    if ($status -in @('blocked', 'failed') -or $resultStatus -in @('blocked', 'failed')) {
        return $false
    }
    if (-not [string]::IsNullOrWhiteSpace($reasonCode) -and $reasonCode -match 'blocked|failed|missing') {
        return $false
    }

    return $true
}

function Get-StateFileFootprint {
    param([Parameter(Mandatory = $true)][string]$StatePath)

    try {
        $item = Get-Item -Path $StatePath -ErrorAction Stop
        return [pscustomobject]@{
            path = [string]$item.FullName
            exists = $true
            size_bytes = [long]$item.Length
            size_mib = [math]::Round(([double]$item.Length / 1MB), 2)
            modified_at = $item.LastWriteTimeUtc.ToString('o')
        }
    }
    catch {
        return [pscustomobject]@{
            path = [string]$StatePath
            exists = $false
            size_bytes = 0L
            size_mib = 0.0
            modified_at = ''
        }
    }
}

function Get-ExecutionMemoryIncidentContext {
    param(
        [AllowNull()]$Execution = $null,
        [Parameter(Mandatory = $true)][string]$StatePath
    )

    $errorText = ''
    $executionMode = ''
    if ($Execution) {
        if ($Execution.PSObject.Properties['error']) {
            $errorText = [string]$Execution.error
        }
        if ($Execution.PSObject.Properties['execution_mode']) {
            $executionMode = [string]$Execution.execution_mode
        }
    }

    $isOom = -not [string]::IsNullOrWhiteSpace($errorText) -and (
        $errorText.IndexOf('OutOfMemoryException', [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
        $errorText.IndexOf('out of memory', [System.StringComparison]::OrdinalIgnoreCase) -ge 0
    )

    if (-not $isOom) {
        return [pscustomobject]@{ detected = $false }
    }

    return [pscustomobject]@{
        detected = $true
        issue_code = 'execution_memory_incident'
        issue_summary = 'TOD executor exhausted memory before completing the accepted request.'
        requested_action = 'dispatch_execution_memory_remediation'
        execution_mode = $executionMode
        error = $errorText
        state_file = Get-StateFileFootprint -StatePath $StatePath
    }
}

function Get-DateOrMinValue {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return [datetime]::MinValue
    }

    try {
        return [datetime]::Parse([string]$Value).ToUniversalTime()
    }
    catch {
        return [datetime]::MinValue
    }
}

function Update-ListenerHeartbeat {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][string]$StatePath,
        [Parameter(Mandatory = $true)][string]$CycleStartedAt,
        [string]$RequestId = "",
        [string]$RequestSignature = "",
        [switch]$MarkProcessed
    )

    if ($MarkProcessed) {
        if (-not [string]::IsNullOrWhiteSpace($RequestId)) {
            $State.last_processed_request_id = $RequestId
        }
        if (-not [string]::IsNullOrWhiteSpace($RequestSignature)) {
            $State.last_processed_request_signature = $RequestSignature
        }
        $State.last_execution_at = (Get-Date).ToUniversalTime().ToString("o")
    }

    $State.last_cycle_at = $CycleStartedAt
    Write-JsonFile -PathValue $StatePath -Payload $State
}

function Get-ObjectFieldText {
    param(
        [AllowNull()]$InputObject,
        [Parameter(Mandatory = $true)][string]$FieldName,
        [string]$DefaultValue = ""
    )

    if ($null -eq $InputObject) {
        return $DefaultValue
    }

    if ($InputObject.PSObject.Properties[$FieldName] -and -not [string]::IsNullOrWhiteSpace([string]$InputObject.$FieldName)) {
        return [string]$InputObject.$FieldName
    }

    return $DefaultValue
}

function Get-ObjectFieldLong {
    param(
        [AllowNull()]$InputObject,
        [Parameter(Mandatory = $true)][string]$FieldName,
        [long]$DefaultValue = 0L
    )

    if ($null -eq $InputObject) {
        return $DefaultValue
    }

    if ($InputObject.PSObject.Properties[$FieldName]) {
        try {
            return [long]$InputObject.$FieldName
        }
        catch {
            return $DefaultValue
        }
    }

    return $DefaultValue
}

function Publish-CommandStatus {
    param(
        [Parameter(Mandatory = $true)]$ListenerState,
        [Parameter(Mandatory = $true)][string]$ListenerStatePath,
        [Parameter(Mandatory = $true)][string]$LocalPath,
        [string]$RemotePath = "",
        [AllowNull()]$Connections = $null,
        [string]$Status = "",
        [string]$Detail = "",
        [string]$RequestId = "",
        [string]$TaskId = "",
        [string]$CorrelationId = "",
        [string]$RequestSignature = "",
        [string]$GoOrderSignature = "",
        [string]$Action = "",
        [AllowNull()]$ExecutionReadiness = $null,
        [AllowNull()]$TriggerPacket = $null,
        [AllowNull()]$AckPacket = $null,
        [AllowNull()]$ResultPacket = $null,
        [AllowNull()]$BridgeRuntime = $null,
        [AllowNull()]$StaleGuard = $null,
        [AllowNull()]$DecisionPayload = $null
    )

    try {
        $effectiveTaskId = Get-NonEmptyPacketValue -Primary ([string]$TaskId) -Fallback ([string]$RequestId)
        $effectiveCorrelationId = Get-NonEmptyPacketValue -Primary ([string]$CorrelationId) -Fallback ([string]$RequestId)
        $bridgeCurrentProcessing = if ($null -ne $BridgeRuntime -and $BridgeRuntime.PSObject.Properties['current_processing']) { $BridgeRuntime.current_processing } else { $null }
        $bridgeTaskId = Get-ObjectFieldText -InputObject $bridgeCurrentProcessing -FieldName 'task_id'
        $bridgeCorrelationId = Get-ObjectFieldText -InputObject $bridgeCurrentProcessing -FieldName 'correlation_id'
        $lineageWarnings = @()
        if (-not [string]::IsNullOrWhiteSpace($bridgeTaskId) -and -not [string]::Equals($bridgeTaskId, $effectiveTaskId, [System.StringComparison]::OrdinalIgnoreCase)) {
            if ($bridgeTaskId -match '^coordination-') {
                $lineageWarnings += ("coordination_wrapper_task_id={0}; execution_task_id={1}" -f $bridgeTaskId, $effectiveTaskId)
            }
            else {
                throw ("execution_lineage_task_id_mismatch: bridge_runtime.current_processing.task_id={0} expected={1}" -f $bridgeTaskId, $effectiveTaskId)
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($bridgeCorrelationId) -and -not [string]::Equals($bridgeCorrelationId, $effectiveCorrelationId, [System.StringComparison]::OrdinalIgnoreCase)) {
            if ($bridgeCorrelationId -match '^coordination-') {
                $lineageWarnings += ("coordination_wrapper_correlation_id={0}; execution_correlation_id={1}" -f $bridgeCorrelationId, $effectiveCorrelationId)
            }
            else {
                throw ("execution_lineage_correlation_id_mismatch: bridge_runtime.current_processing.correlation_id={0} expected={1}" -f $bridgeCorrelationId, $effectiveCorrelationId)
            }
        }
        $statusAt = Get-UtcNowString
        $triggerContext = Get-TriggerContext -TriggerPacket $TriggerPacket
        $ackGeneratedAt = Get-ObjectFieldText -InputObject $AckPacket -FieldName "generated_at"
        $ackStatus = Get-ObjectFieldText -InputObject $AckPacket -FieldName "status"
        $ackSequence = Get-ObjectFieldLong -InputObject $AckPacket -FieldName "ack_sequence"
        $ackTriggerSequence = Get-ObjectFieldLong -InputObject $AckPacket -FieldName "acknowledged_trigger_sequence"
        $resultGeneratedAt = Get-ObjectFieldText -InputObject $ResultPacket -FieldName "generated_at"
        $resultStatus = Get-ObjectFieldText -InputObject $ResultPacket -FieldName "status"
        $resultAction = Get-ObjectFieldText -InputObject $ResultPacket -FieldName "action"
        $resultSequence = Get-ObjectFieldLong -InputObject $ResultPacket -FieldName "ack_sequence"
        $resultTriggerSequence = Get-ObjectFieldLong -InputObject $ResultPacket -FieldName "acknowledged_trigger_sequence"
        $listenerLastCycleAt = Get-ObjectFieldText -InputObject $ListenerState -FieldName "last_cycle_at"
        $listenerLastExecutionAt = Get-ObjectFieldText -InputObject $ListenerState -FieldName "last_execution_at"
        $effectiveStaleGuard = $StaleGuard
        $ackPayload = $null
        $resultPayload = $null

        $ListenerState | Add-Member -NotePropertyName last_command_status -NotePropertyValue ([string]$Status) -Force
        $ListenerState | Add-Member -NotePropertyName last_command_status_at -NotePropertyValue $statusAt -Force
        $ListenerState | Add-Member -NotePropertyName last_command_detail -NotePropertyValue ([string]$Detail) -Force
        $ListenerState | Add-Member -NotePropertyName last_observed_request_id -NotePropertyValue ([string]$RequestId) -Force
        $ListenerState | Add-Member -NotePropertyName last_observed_request_signature -NotePropertyValue ([string]$RequestSignature) -Force
        $ListenerState | Add-Member -NotePropertyName last_observed_go_order_signature -NotePropertyValue ([string]$GoOrderSignature) -Force
        $ListenerState | Add-Member -NotePropertyName last_observed_task_id -NotePropertyValue ([string]$effectiveTaskId) -Force
        $ListenerState | Add-Member -NotePropertyName last_observed_correlation_id -NotePropertyValue ([string]$effectiveCorrelationId) -Force
        $ListenerState | Add-Member -NotePropertyName last_stale_guard -NotePropertyValue $null -Force
        if ($null -ne $DecisionPayload -and $DecisionPayload.PSObject.Properties['decision_outcome']) {
            $decisionReasonCode = if ($DecisionPayload.PSObject.Properties['reason_code']) { [string]$DecisionPayload.reason_code } else { '' }
            $ListenerState | Add-Member -NotePropertyName last_decision_outcome -NotePropertyValue ([string]$DecisionPayload.decision_outcome) -Force
            $ListenerState | Add-Member -NotePropertyName last_decision_reason_code -NotePropertyValue $decisionReasonCode -Force
        }

        if ($null -ne $triggerContext) {
            $ListenerState | Add-Member -NotePropertyName last_observed_trigger_type -NotePropertyValue ([string]$triggerContext.trigger) -Force
            $ListenerState | Add-Member -NotePropertyName last_observed_trigger_sequence -NotePropertyValue ([long]$triggerContext.sequence) -Force
            $ListenerState | Add-Member -NotePropertyName last_observed_trigger_artifact -NotePropertyValue ([string]$triggerContext.artifact) -Force
        }

        if ($null -ne $AckPacket) {
            $ListenerState | Add-Member -NotePropertyName last_ack_generated_at -NotePropertyValue $ackGeneratedAt -Force
            $ListenerState | Add-Member -NotePropertyName last_ack_sequence -NotePropertyValue $ackSequence -Force
        }

        if ($null -ne $ResultPacket) {
            $ListenerState | Add-Member -NotePropertyName last_result_generated_at -NotePropertyValue $resultGeneratedAt -Force
            $ListenerState | Add-Member -NotePropertyName last_result_sequence -NotePropertyValue $resultSequence -Force
            $ListenerState | Add-Member -NotePropertyName last_result_status -NotePropertyValue $resultStatus -Force
            $ListenerState | Add-Member -NotePropertyName last_result_action -NotePropertyValue $resultAction -Force
        }

        Write-JsonFile -PathValue $ListenerStatePath -Payload $ListenerState

        if ($null -ne $AckPacket) {
            $ackPayload = [pscustomobject]@{
                generated_at = $ackGeneratedAt
                status = $ackStatus
                ack_sequence = $ackSequence
                acknowledged_trigger_sequence = $ackTriggerSequence
            }
        }

        if ($null -ne $ResultPacket) {
            $resultPayload = [pscustomobject]@{
                generated_at = $resultGeneratedAt
                status = $resultStatus
                action = $resultAction
                ack_sequence = $resultSequence
                acknowledged_trigger_sequence = $resultTriggerSequence
            }
        }

        $payload = [pscustomobject]@{
            generated_at = $statusAt
            source = "tod-mim-command-status-v1"
            status = [string]$Status
            detail = [string]$Detail
            request_id = [string]$RequestId
            task_id = [string]$effectiveTaskId
            correlation_id = [string]$effectiveCorrelationId
            request_signature = [string]$RequestSignature
            go_order_signature = [string]$GoOrderSignature
            action = [string]$Action
            acted_upon = ($null -ne $ResultPacket)
            execution_readiness = $ExecutionReadiness
            listener = [pscustomobject]@{
                host = $env:COMPUTERNAME
                service = "tod-mim-listener"
                instance_id = ("{0}:{1}" -f $env:COMPUTERNAME, $PID)
                last_cycle_at = $listenerLastCycleAt
                last_execution_at = $listenerLastExecutionAt
            }
            trigger = $triggerContext
            ack = $ackPayload
            result = $resultPayload
            bridge_runtime = $BridgeRuntime
            lineage_warnings = @($lineageWarnings)
            stale_guard = $effectiveStaleGuard
            decision = $DecisionPayload
        }

        Write-JsonFile -PathValue $LocalPath -Payload $payload

        if ($Connections -and -not [string]::IsNullOrWhiteSpace($RemotePath)) {
            try {
                $payloadJson = Get-Content -Path $LocalPath -Raw
                Write-RemoteFileFromText -Connections $Connections -RemotePath $RemotePath -Content $payloadJson
            }
            catch {
                Write-Warning ("[TOD-LISTENER] Unable to publish command status to remote: {0}" -f $_.Exception.Message)
            }
        }
    }
    catch {
        Write-Warning ("[TOD-LISTENER] Command status publish failed but execution will continue: {0}" -f $_.Exception.Message)
    }
}

function Publish-ExecutionLock {
    param(
        [Parameter(Mandatory = $true)][string]$LocalPath,
        [string]$RemotePath = '',
        [AllowNull()]$Connections = $null,
        [string]$ObjectiveId = '',
        [string]$TaskId = '',
        [string]$RequestId = '',
        [string]$CorrelationId = '',
        [string]$Status = '',
        [AllowNull()]$BridgeRuntime = $null
    )

    $effectiveTaskId = Get-NonEmptyPacketValue -Primary ([string]$TaskId) -Fallback ([string]$RequestId)
    if ([string]::IsNullOrWhiteSpace($effectiveTaskId)) {
        return
    }

    $effectiveRequestId = Get-NonEmptyPacketValue -Primary ([string]$RequestId) -Fallback $effectiveTaskId
    $effectiveCorrelationId = Get-NonEmptyPacketValue -Primary ([string]$CorrelationId) -Fallback $effectiveRequestId
    $bridgeCurrentProcessing = if ($null -ne $BridgeRuntime -and $BridgeRuntime.PSObject.Properties['current_processing']) { $BridgeRuntime.current_processing } else { $null }
    $bridgeTaskId = Get-ObjectFieldText -InputObject $bridgeCurrentProcessing -FieldName 'task_id'
    $bridgeCorrelationId = Get-ObjectFieldText -InputObject $bridgeCurrentProcessing -FieldName 'correlation_id'
    $bridgeObjectiveId = Get-ObjectFieldText -InputObject $bridgeCurrentProcessing -FieldName 'objective_id'
    if (-not [string]::IsNullOrWhiteSpace($bridgeTaskId) -and -not [string]::Equals($bridgeTaskId, $effectiveTaskId, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw ("execution_lock_task_id_mismatch: bridge_runtime.current_processing.task_id={0} expected={1}" -f $bridgeTaskId, $effectiveTaskId)
    }
    if (-not [string]::IsNullOrWhiteSpace($bridgeCorrelationId) -and -not [string]::Equals($bridgeCorrelationId, $effectiveCorrelationId, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw ("execution_lock_correlation_id_mismatch: bridge_runtime.current_processing.correlation_id={0} expected={1}" -f $bridgeCorrelationId, $effectiveCorrelationId)
    }

    $payload = [pscustomobject]@{
        generated_at = Get-UtcNowString
        source = 'tod-execution-lock-v1'
        writer = 'Start-TODMimPacketListener'
        authoritative = $true
        objective_id = Get-NonEmptyPacketValue -Primary ([string]$ObjectiveId) -Fallback $bridgeObjectiveId
        task_id = $effectiveTaskId
        request_id = $effectiveRequestId
        correlation_id = $effectiveCorrelationId
        status = [string]$Status
        current_processing = if ($null -ne $bridgeCurrentProcessing) { $bridgeCurrentProcessing } else { [pscustomobject]@{
            objective_id = Get-NonEmptyPacketValue -Primary ([string]$ObjectiveId) -Fallback $bridgeObjectiveId
            task_id = $effectiveTaskId
            request_id = $effectiveRequestId
            correlation_id = $effectiveCorrelationId
        } }
    }

    Write-JsonFile -PathValue $LocalPath -Payload $payload -Depth 20
    if ($Connections -and -not [string]::IsNullOrWhiteSpace($RemotePath)) {
        $payloadJson = Get-Content -Path $LocalPath -Raw
        Write-RemoteFileFromText -Connections $Connections -RemotePath $RemotePath -Content $payloadJson
    }
}

function Publish-ExecutionDecision {
    param(
        [Parameter(Mandatory = $true)][string]$LocalPath,
        [string]$RemotePath = '',
        [AllowNull()]$Connections = $null,
        [Parameter(Mandatory = $true)]$DecisionPayload,
        [string]$RequestId = '',
        [string]$TaskId = '',
        [string]$CorrelationId = '',
        [AllowNull()]$TriggerPacket = $null,
        [AllowNull()]$BridgeRuntime = $null
    )

    try {
        $effectiveTaskId = [string](Get-NonEmptyPacketValue -Primary ([string]$TaskId) -Fallback ([string]$RequestId))
        $effectiveCorrelationId = [string](Get-NonEmptyPacketValue -Primary ([string]$CorrelationId) -Fallback ([string]$RequestId))
        $bridgeCurrentProcessing = if ($null -ne $BridgeRuntime -and $BridgeRuntime.PSObject.Properties['current_processing']) { $BridgeRuntime.current_processing } else { $null }
        $bridgeTaskId = Get-ObjectFieldText -InputObject $bridgeCurrentProcessing -FieldName 'task_id'
        $bridgeCorrelationId = Get-ObjectFieldText -InputObject $bridgeCurrentProcessing -FieldName 'correlation_id'
        $lineageWarnings = @()
        if (-not [string]::IsNullOrWhiteSpace($bridgeTaskId) -and -not [string]::Equals($bridgeTaskId, $effectiveTaskId, [System.StringComparison]::OrdinalIgnoreCase)) {
            if ($bridgeTaskId -match '^coordination-') {
                $lineageWarnings += ("coordination_wrapper_task_id={0}; execution_task_id={1}" -f $bridgeTaskId, $effectiveTaskId)
            }
            else {
                throw ("execution_decision_task_id_mismatch: bridge_runtime.current_processing.task_id={0} expected={1}" -f $bridgeTaskId, $effectiveTaskId)
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($bridgeCorrelationId) -and -not [string]::Equals($bridgeCorrelationId, $effectiveCorrelationId, [System.StringComparison]::OrdinalIgnoreCase)) {
            if ($bridgeCorrelationId -match '^coordination-') {
                $lineageWarnings += ("coordination_wrapper_correlation_id={0}; execution_correlation_id={1}" -f $bridgeCorrelationId, $effectiveCorrelationId)
            }
            else {
                throw ("execution_decision_correlation_id_mismatch: bridge_runtime.current_processing.correlation_id={0} expected={1}" -f $bridgeCorrelationId, $effectiveCorrelationId)
            }
        }
        $triggerContext = Get-TriggerContext -TriggerPacket $TriggerPacket
        $payload = [pscustomobject]@{
            generated_at = Get-UtcNowString
            source = 'tod-mim-execution-decision-v1'
            request_id = [string]$RequestId
            task_id = $effectiveTaskId
            correlation_id = $effectiveCorrelationId
            decision_outcome = if ($DecisionPayload.PSObject.Properties['decision_outcome']) { [string]$DecisionPayload.decision_outcome } else { '' }
            reason_code = if ($DecisionPayload.PSObject.Properties['reason_code']) { [string]$DecisionPayload.reason_code } else { '' }
            summary = if ($DecisionPayload.PSObject.Properties['summary']) { [string]$DecisionPayload.summary } else { '' }
            ack_state = if ($DecisionPayload.PSObject.Properties['decision_outcome'] -and [string]::Equals([string]$DecisionPayload.decision_outcome, 'execute', [System.StringComparison]::OrdinalIgnoreCase)) { 'accepted' } elseif ($DecisionPayload.PSObject.Properties['decision_outcome'] -and [string]::Equals([string]$DecisionPayload.decision_outcome, 'acknowledge_and_wait_on_dependency', [System.StringComparison]::OrdinalIgnoreCase)) { 'acknowledged_waiting_dependency' } else { 'not_acked' }
            execution_state = if ($DecisionPayload.PSObject.Properties['decision_outcome'] -and [string]::Equals([string]$DecisionPayload.decision_outcome, 'execute', [System.StringComparison]::OrdinalIgnoreCase)) { 'ready_to_execute' } elseif ($DecisionPayload.PSObject.Properties['decision_outcome'] -and [string]::Equals([string]$DecisionPayload.decision_outcome, 'acknowledge_and_wait_on_dependency', [System.StringComparison]::OrdinalIgnoreCase)) { 'waiting_on_dependency' } elseif ($DecisionPayload.PSObject.Properties['decision_outcome'] -and [string]::Equals([string]$DecisionPayload.decision_outcome, 'escalate_hard_boundary', [System.StringComparison]::OrdinalIgnoreCase)) { 'awaiting_human_boundary' } else { 'rejected' }
            boundary_class = if ($DecisionPayload.PSObject.Properties['boundary_class']) { [string]$DecisionPayload.boundary_class } else { '' }
            requested_executor = if ($DecisionPayload.PSObject.Properties['requested_executor']) { [string]$DecisionPayload.requested_executor } else { '' }
            requested_objective_id = if ($DecisionPayload.PSObject.Properties['requested_objective_id']) { [string]$DecisionPayload.requested_objective_id } else { '' }
            canonical_objective_id = if ($DecisionPayload.PSObject.Properties['canonical_objective_id']) { [string]$DecisionPayload.canonical_objective_id } else { '' }
            live_request_promotion_applied = if ($DecisionPayload.PSObject.Properties['live_request_promotion_applied']) { [bool]$DecisionPayload.live_request_promotion_applied } else { $false }
            unmet_dependency = if ($DecisionPayload.PSObject.Properties['unmet_dependency']) { [string]$DecisionPayload.unmet_dependency } else { '' }
            blocker_classification = if ($DecisionPayload.PSObject.Properties['blocker_classification']) { [string]$DecisionPayload.blocker_classification } else { '' }
            next_step_recommendation = if ($DecisionPayload.PSObject.Properties['next_step_recommendation']) { [string]$DecisionPayload.next_step_recommendation } else { '' }
            requires_human = if ($DecisionPayload.PSObject.Properties['requires_human']) { [bool]$DecisionPayload.requires_human } else { $false }
            execution_readiness = if ($DecisionPayload.PSObject.Properties['execution_readiness']) { $DecisionPayload.execution_readiness } else { $null }
            validation_reasoning = if ($DecisionPayload.PSObject.Properties['validation_reasoning']) { @($DecisionPayload.validation_reasoning | ForEach-Object { [string]$_ }) } else { @() }
            trigger = $triggerContext
            bridge_runtime = $BridgeRuntime
            lineage_warnings = @($lineageWarnings)
        }

        Write-JsonFile -PathValue $LocalPath -Payload $payload -Depth 100
        if ($Connections -and -not [string]::IsNullOrWhiteSpace($RemotePath)) {
            $payloadJson = Get-Content -Path $LocalPath -Raw
            Write-RemoteFileFromText -Connections $Connections -RemotePath $RemotePath -Content $payloadJson
        }
    }
    catch {
        Write-Warning ("[TOD-LISTENER] Unable to publish execution decision artifact: {0}" -f $_.Exception.Message)
    }
}

function Get-RequestSignature {
    param(
        [Parameter(Mandatory = $true)][string]$RequestPath,
        [switch]$SemanticTaskPacket
    )

    if (-not (Test-Path -Path $RequestPath)) {
        return ""
    }

    if ($SemanticTaskPacket) {
        try {
            $payload = ConvertFrom-JsonCaseInsensitiveSafe -Text (Get-Content -Path $RequestPath -Raw)
            $volatileFields = @(
                'generated_at',
                'emitted_at',
                'sequence',
                'source_instance_id',
                'source_service'
            )
            $normalizedPayload = Convert-ToSignatureStableValue -Value $payload -VolatileFields $volatileFields
            $normalizedJson = $normalizedPayload | ConvertTo-Json -Depth 100 -Compress
            return Get-TextSha256 -Value $normalizedJson
        }
        catch {
        }
    }

    try {
        return [string](Get-FileHash -Path $RequestPath -Algorithm SHA256).Hash
    }
    catch {
        return ""
    }
}

function Get-RequestIdentifier {
    param($Request)

    if ($null -eq $Request) { return "" }

    foreach ($field in @("request_id", "task_id", "id", "correlation_id")) {
        if ($Request.PSObject.Properties[$field] -and -not [string]::IsNullOrWhiteSpace([string]$Request.$field)) {
            return [string]$Request.$field
        }
    }

    if ($Request.PSObject.Properties["generated_at"] -and -not [string]::IsNullOrWhiteSpace([string]$Request.generated_at)) {
        return [string]$Request.generated_at
    }

    return ""
}

function Get-TaskOrdinalInfo {
    param(
        [string]$Value,
        [string]$FallbackObjectiveId = ""
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $trimmedValue = ([string]$Value).Trim()
    $match = [regex]::Match($trimmedValue, '^objective-(?<objective>\d+)-task-(?<tail>.+)$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) {
        return $null
    }

    $objectiveId = [string]$match.Groups['objective'].Value
    if ([string]::IsNullOrWhiteSpace($objectiveId)) {
        $objectiveId = [string]$FallbackObjectiveId
    }

    $tail = [string]$match.Groups['tail'].Value
    $ordinalMatch = [regex]::Match($tail, '(?<ordinal>\d+)(?!.*\d)')
    if (-not $ordinalMatch.Success) {
        return $null
    }

    $ordinal = 0L
    if (-not [long]::TryParse([string]$ordinalMatch.Groups['ordinal'].Value, [ref]$ordinal)) {
        return $null
    }

    return [pscustomobject]@{
        raw = $trimmedValue
        objective_id = [string]$objectiveId
        ordinal = [long]$ordinal
        source = ''
        source_field = ''
    }
}

function Get-RequestOrderingInfo {
    param(
        $Request,
        [string]$RequestId,
        [string]$FallbackObjectiveId = ''
    )

    $requestTaskId = if ($Request -and $Request.PSObject.Properties['task_id']) { [string]$Request.task_id } else { '' }
    $candidate = Get-TaskOrdinalInfo -Value $RequestId -FallbackObjectiveId $FallbackObjectiveId
    $sourceField = 'request_id'
    if ($null -eq $candidate -and -not [string]::IsNullOrWhiteSpace($requestTaskId)) {
        $candidate = Get-TaskOrdinalInfo -Value $requestTaskId -FallbackObjectiveId $FallbackObjectiveId
        $sourceField = 'task_id'
    }

    $sequence = Get-ObjectFieldLong -InputObject $Request -FieldName 'sequence'
    if ($null -eq $candidate -and $sequence -le 0) {
        return $null
    }

    $objectiveId = if ($candidate) { [string]$candidate.objective_id } else { [string]$FallbackObjectiveId }
    $rawValue = if ($candidate) { [string]$candidate.raw } elseif (-not [string]::IsNullOrWhiteSpace($requestTaskId)) { $requestTaskId } else { $RequestId }

    return [pscustomobject]@{
        raw = $rawValue
        objective_id = $objectiveId
        ordinal = if ($candidate) { [long]$candidate.ordinal } else { 0L }
        sequence = if ($sequence -gt 0) { [long]$sequence } else { 0L }
        source = 'incoming_request'
        source_field = if ($sequence -gt 0) { 'sequence' } else { $sourceField }
    }
}

function Test-RequestOrderingIsStale {
    param(
        [AllowNull()]$RequestOrderingInfo,
        [AllowNull()]$HighWatermark
    )

    if ($null -eq $RequestOrderingInfo -or $null -eq $HighWatermark) {
        return $false
    }

    $requestObjective = if ($RequestOrderingInfo.PSObject.Properties['objective_id']) { [string]$RequestOrderingInfo.objective_id } else { '' }
    $highObjective = if ($HighWatermark.PSObject.Properties['objective_id']) { [string]$HighWatermark.objective_id } else { '' }
    if ([string]::IsNullOrWhiteSpace($requestObjective) -or [string]::IsNullOrWhiteSpace($highObjective) -or -not [string]::Equals($requestObjective, $highObjective, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $false
    }

    $requestSequence = if ($RequestOrderingInfo.PSObject.Properties['sequence']) { [long]$RequestOrderingInfo.sequence } else { 0L }
    $highSequence = if ($HighWatermark.PSObject.Properties['sequence']) { [long]$HighWatermark.sequence } else { 0L }
    if ($requestSequence -gt 0 -and $highSequence -gt 0) {
        return ($requestSequence -lt $highSequence)
    }

    $requestOrdinal = if ($RequestOrderingInfo.PSObject.Properties['ordinal']) { [long]$RequestOrderingInfo.ordinal } else { 0L }
    $highOrdinal = if ($HighWatermark.PSObject.Properties['ordinal']) { [long]$HighWatermark.ordinal } else { 0L }
    return ($requestOrdinal -gt 0 -and $highOrdinal -gt 0 -and $requestOrdinal -lt $highOrdinal)
}

function Get-ScopedForcedReplayEntries {
    param([AllowNull()]$ListenerState)

    if ($null -eq $ListenerState -or -not $ListenerState.PSObject.Properties['scoped_forced_replays'] -or $null -eq $ListenerState.scoped_forced_replays) {
        return @()
    }

    return @($ListenerState.scoped_forced_replays | Where-Object { $null -ne $_ })
}

function Get-ScopedForcedReplayMatch {
    param(
        [AllowNull()]$ListenerState,
        [Parameter(Mandatory = $true)][string]$RequestId,
        [string]$TaskId = '',
        [string]$ObjectiveId = ''
    )

    foreach ($entry in Get-ScopedForcedReplayEntries -ListenerState $ListenerState) {
        $entryActive = if ($entry.PSObject.Properties['active']) { [bool]$entry.active } else { $true }
        if (-not $entryActive) {
            continue
        }

        $entryRequestId = if ($entry.PSObject.Properties['replay_request_id']) { [string]$entry.replay_request_id } else { '' }
        if (-not [string]::Equals($entryRequestId, $RequestId, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $entryTaskId = if ($entry.PSObject.Properties['task_id']) { [string]$entry.task_id } else { '' }
        if (-not [string]::IsNullOrWhiteSpace($TaskId) -and -not [string]::IsNullOrWhiteSpace($entryTaskId) -and -not [string]::Equals($entryTaskId, $TaskId, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $entryObjectiveId = if ($entry.PSObject.Properties['objective_id']) { [string]$entry.objective_id } else { '' }
        if (-not [string]::IsNullOrWhiteSpace($ObjectiveId) -and -not [string]::IsNullOrWhiteSpace($entryObjectiveId) -and -not [string]::Equals($entryObjectiveId, $ObjectiveId, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        return $entry
    }

    return $null
}

function Remove-ScopedForcedReplayMatch {
    param(
        [Parameter(Mandatory = $true)]$ListenerState,
        [Parameter(Mandatory = $true)][string]$RequestId
    )

    $remaining = New-Object System.Collections.Generic.List[object]
    $removed = $false
    foreach ($entry in Get-ScopedForcedReplayEntries -ListenerState $ListenerState) {
        $entryRequestId = if ($entry.PSObject.Properties['replay_request_id']) { [string]$entry.replay_request_id } else { '' }
        if ([string]::Equals($entryRequestId, $RequestId, [System.StringComparison]::OrdinalIgnoreCase)) {
            $removed = $true
            continue
        }

        $remaining.Add($entry)
    }

    $ListenerState | Add-Member -NotePropertyName scoped_forced_replays -NotePropertyValue @($remaining.ToArray()) -Force
    return $removed
}

function Get-MaxObservedTaskOrdinal {
    param(
        [string]$JournalPath,
        [string]$ObjectiveId
    )

    if ([string]::IsNullOrWhiteSpace($ObjectiveId) -or -not (Test-Path -Path $JournalPath)) {
        return $null
    }

    $journal = Read-JsonFileIfExists -PathValue $JournalPath
    if ($null -eq $journal) {
        return $null
    }

    $entries = @()
    if ($journal -is [System.Array]) {
        $entries = @($journal)
    }
    elseif ($journal.PSObject.Properties['entries']) {
        $entries = @($journal.entries)
    }

    $best = $null
    foreach ($entry in $entries) {
        $entryObjectiveId = if ($entry.PSObject.Properties['objective_id']) { [string]$entry.objective_id } else { "" }
        if ([string]::IsNullOrWhiteSpace($entryObjectiveId)) {
            $entryObjectiveId = [string]$ObjectiveId
        }
        if (-not [string]::Equals($entryObjectiveId, [string]$ObjectiveId, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $candidateValue = if ($entry.PSObject.Properties['request_id']) { [string]$entry.request_id } else { "" }
        $candidate = Get-TaskOrdinalInfo -Value $candidateValue -FallbackObjectiveId $entryObjectiveId
        if ($null -eq $candidate) {
            continue
        }

        if ($null -eq $best -or [long]$candidate.ordinal -gt [long]$best.ordinal) {
            $best = [pscustomobject]@{
                raw = [string]$candidate.raw
                objective_id = [string]$candidate.objective_id
                ordinal = [long]$candidate.ordinal
                source = 'loop_journal'
                source_field = 'request_id'
            }
        }
    }

    return $best
}

function Update-TaskHighWatermark {
    param(
        [Parameter(Mandatory = $true)]$State,
        [AllowNull()]$CandidateInfo
    )

    $candidate = $CandidateInfo
    if ($null -eq $candidate) {
        return $null
    }

    $existingObjectiveId = if ($State.PSObject.Properties['high_watermark_objective_id']) { [string]$State.high_watermark_objective_id } else { "" }
    $existingOrdinal = if ($State.PSObject.Properties['high_watermark_ordinal']) { [long]$State.high_watermark_ordinal } else { 0L }
    $existingSequence = if ($State.PSObject.Properties['high_watermark_sequence']) { [long]$State.high_watermark_sequence } else { 0L }
    $candidateSequence = if ($candidate.PSObject.Properties['sequence']) { [long]$candidate.sequence } else { 0L }

    $canUpdate = $false
    if ([string]::IsNullOrWhiteSpace($existingObjectiveId)) {
        $canUpdate = $true
    }
    elseif ([string]::Equals([string]$candidate.objective_id, $existingObjectiveId, [System.StringComparison]::OrdinalIgnoreCase)) {
        if ($candidateSequence -gt 0 -and $existingSequence -gt 0) {
            $canUpdate = ($candidateSequence -ge $existingSequence)
        }
        elseif ($candidateSequence -gt 0 -and $existingSequence -le 0) {
            $canUpdate = $true
        }
        else {
            $canUpdate = ([long]$candidate.ordinal -gt $existingOrdinal)
        }
    }

    if ($canUpdate) {
        $State.high_watermark_request_id = [string]$candidate.raw
        $State.high_watermark_objective_id = [string]$candidate.objective_id
        $State.high_watermark_ordinal = [long]$candidate.ordinal
        $State.high_watermark_sequence = $candidateSequence
    }

    return [pscustomobject]@{
        raw = if ($State.PSObject.Properties['high_watermark_request_id']) { [string]$State.high_watermark_request_id } else { "" }
        objective_id = if ($State.PSObject.Properties['high_watermark_objective_id']) { [string]$State.high_watermark_objective_id } else { "" }
        ordinal = if ($State.PSObject.Properties['high_watermark_ordinal']) { [long]$State.high_watermark_ordinal } else { 0L }
        sequence = if ($State.PSObject.Properties['high_watermark_sequence']) { [long]$State.high_watermark_sequence } else { 0L }
        source = 'listener_state'
        source_field = if (($State.PSObject.Properties['high_watermark_sequence']) -and [long]$State.high_watermark_sequence -gt 0) { 'high_watermark_sequence' } else { 'high_watermark_request_id' }
    }
}

function Get-ObjectiveHighWatermark {
    param(
        [Parameter(Mandatory = $true)]$State,
        [string]$JournalPath,
        [string]$ObjectiveId
    )

    $best = Get-MaxObservedTaskOrdinal -JournalPath $JournalPath -ObjectiveId $ObjectiveId
    $stateRequestId = if ($State.PSObject.Properties['high_watermark_request_id']) { [string]$State.high_watermark_request_id } else { "" }
    $stateCandidate = Get-TaskOrdinalInfo -Value $stateRequestId -FallbackObjectiveId $ObjectiveId
    if ($stateCandidate -and [string]::Equals([string]$stateCandidate.objective_id, [string]$ObjectiveId, [System.StringComparison]::OrdinalIgnoreCase)) {
        $stateSequence = if ($State.PSObject.Properties['high_watermark_sequence']) { [long]$State.high_watermark_sequence } else { 0L }
        $stateCandidate = [pscustomobject]@{
            raw = [string]$stateCandidate.raw
            objective_id = [string]$stateCandidate.objective_id
            ordinal = [long]$stateCandidate.ordinal
            sequence = $stateSequence
            source = 'listener_state'
            source_field = if ($stateSequence -gt 0) { 'high_watermark_sequence' } else { 'high_watermark_request_id' }
        }
        if ($null -eq $best -or ($stateSequence -gt 0 -and (-not $best.PSObject.Properties['sequence'] -or [long]$best.sequence -le 0)) -or ($stateSequence -gt 0 -and $best.PSObject.Properties['sequence'] -and [long]$stateCandidate.sequence -gt [long]$best.sequence) -or ($stateSequence -le 0 -and [long]$stateCandidate.ordinal -gt [long]$best.ordinal)) {
            $best = $stateCandidate
        }
        elseif ($best -and [long]$stateCandidate.ordinal -eq [long]$best.ordinal -and [string]::Equals([string]$stateCandidate.raw, [string]$best.raw, [System.StringComparison]::OrdinalIgnoreCase)) {
            $best = [pscustomobject]@{
                raw = [string]$best.raw
                objective_id = [string]$best.objective_id
                ordinal = [long]$best.ordinal
                sequence = if ($best.PSObject.Properties['sequence']) { [long]$best.sequence } else { 0L }
                source = 'listener_state_and_loop_journal'
                source_field = if ($stateSequence -gt 0) { 'request_id|high_watermark_sequence' } else { 'request_id|high_watermark_request_id' }
            }
        }
    }

    return $best
}

function New-StaleGuardMetadata {
    param(
        [string]$Decision,
        [string]$RequestId,
        [string]$TaskId,
        [string]$ObjectiveId,
        [AllowNull()]$RequestOrdinalInfo = $null,
        [string]$RequestOrdinalSourceField = '',
        [AllowNull()]$HighWatermark = $null,
        [long]$TriggerSequence = 0L
    )

    $requestOrdinalValue = ''
    $requestOrdinal = 0L
    if ($RequestOrdinalInfo) {
        $requestOrdinalValue = if ($RequestOrdinalInfo.PSObject.Properties['raw']) { [string]$RequestOrdinalInfo.raw } else { '' }
        $requestOrdinal = if ($RequestOrdinalInfo.PSObject.Properties['ordinal']) { [long]$RequestOrdinalInfo.ordinal } else { 0L }
    }

    $highWatermarkValue = ''
    $highWatermarkOrdinal = 0L
    $highWatermarkSource = 'unknown'
    $highWatermarkField = ''
    if ($HighWatermark) {
        $highWatermarkValue = if ($HighWatermark.PSObject.Properties['raw']) { [string]$HighWatermark.raw } else { '' }
        $highWatermarkOrdinal = if ($HighWatermark.PSObject.Properties['ordinal']) { [long]$HighWatermark.ordinal } else { 0L }
        $highWatermarkSource = if ($HighWatermark.PSObject.Properties['source'] -and -not [string]::IsNullOrWhiteSpace([string]$HighWatermark.source)) { [string]$HighWatermark.source } else { 'unknown' }
        $highWatermarkField = if ($HighWatermark.PSObject.Properties['source_field']) { [string]$HighWatermark.source_field } else { '' }
    }

    $usesInternalTrackedRequestId = $highWatermarkSource.IndexOf('listener_state', [System.StringComparison]::OrdinalIgnoreCase) -ge 0

    return [pscustomobject]@{
        detected = $true
        decision = [string]$Decision
        status = 'execution_blocked_by_stale_guard'
        reason = 'higher_authoritative_task_ordinal_active'
        objective_id = [string]$ObjectiveId
        guidance = 'Freshness is sequence-aware when request.sequence is available; otherwise TOD falls back to the trailing numeric suffix in request_id/task_id.'
        winner = [pscustomobject]@{
            request_field = [string]$RequestOrdinalSourceField
            high_watermark_source = $highWatermarkSource
            high_watermark_field = $highWatermarkField
        }
        comparison_basis = [pscustomobject]@{
            request_id_suffix = [string]::Equals([string]$RequestOrdinalSourceField, 'request_id', [System.StringComparison]::OrdinalIgnoreCase)
            task_id_suffix = [string]::Equals([string]$RequestOrdinalSourceField, 'task_id', [System.StringComparison]::OrdinalIgnoreCase)
            sequence = (($RequestOrdinalInfo -and $RequestOrdinalInfo.PSObject.Properties['sequence'] -and [long]$RequestOrdinalInfo.sequence -gt 0) -or ($HighWatermark -and $HighWatermark.PSObject.Properties['sequence'] -and [long]$HighWatermark.sequence -gt 0))
            emitted_at = $false
            internal_tracked_request_id = $usesInternalTrackedRequestId
        }
        current_request = [pscustomobject]@{
            request_id = [string]$RequestId
            task_id = [string]$TaskId
            source_field = [string]$RequestOrdinalSourceField
            ordinal_value = $requestOrdinalValue
            ordinal = $requestOrdinal
            sequence = if ($RequestOrdinalInfo -and $RequestOrdinalInfo.PSObject.Properties['sequence']) { [long]$RequestOrdinalInfo.sequence } else { 0L }
        }
        high_watermark = [pscustomobject]@{
            source = $highWatermarkSource
            source_field = $highWatermarkField
            request_id = $highWatermarkValue
            ordinal = $highWatermarkOrdinal
            sequence = if ($HighWatermark -and $HighWatermark.PSObject.Properties['sequence']) { [long]$HighWatermark.sequence } else { 0L }
        }
        trigger = [pscustomobject]@{
            sequence = [long]$TriggerSequence
        }
    }
}

function Get-TextSha256 {
    param([Parameter(Mandatory = $true)][string]$Value)

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$Value)
        $hashBytes = $sha256.ComputeHash($bytes)
        return ([System.BitConverter]::ToString($hashBytes)).Replace("-", "")
    }
    finally {
        $sha256.Dispose()
    }
}

function Convert-ToSignatureStableValue {
    param(
        [AllowNull()]$Value,
        [string[]]$VolatileFields = @()
    )

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [string] -or $Value -is [ValueType]) {
        return $Value
    }

    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        if ($Value.PSObject.Properties.Count -eq 0) {
            $items = @()
            foreach ($item in $Value) {
                $items += ,(Convert-ToSignatureStableValue -Value $item -VolatileFields $VolatileFields)
            }
            return @($items)
        }
    }

    $propertyBag = $Value.PSObject.Properties
    if ($propertyBag.Count -gt 0) {
        $ordered = [ordered]@{}
        foreach ($property in @($propertyBag | Sort-Object Name)) {
            if ($VolatileFields -contains ([string]$property.Name).Trim().ToLowerInvariant()) {
                continue
            }
            $ordered[$property.Name] = Convert-ToSignatureStableValue -Value $property.Value -VolatileFields $VolatileFields
        }
        return [pscustomobject]$ordered
    }

    return $Value
}

function Get-UtcNowString {
    return (Get-Date).ToUniversalTime().ToString("o")
}

function Get-PythonCommand {
    $venvPython = Join-Path $repoRoot ".venv/Scripts/python.exe"
    if (Test-Path -Path $venvPython -PathType Leaf) {
        return $venvPython
    }

    $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
    if ($pythonCmd) {
        return $pythonCmd.Source
    }

    throw "python_not_found"
}

function Get-ContractBindingMetadata {
    param(
        [Parameter(Mandatory = $true)][string]$ContractDirPath,
        [Parameter(Mandatory = $true)][string]$RemoteSurface,
        [Parameter(Mandatory = $true)][string]$LocalStageDir
    )

    $receiptPath = Join-Path $ContractDirPath 'TOD_MIM_COMMUNICATION_CONTRACT_RECEIPT.v1.json'
    $contractPath = Join-Path $ContractDirPath 'TOD_MIM_COMMUNICATION_CONTRACT.v1.yaml'
    $receipt = Read-JsonFileIfExists -PathValue $receiptPath
    if ($null -eq $receipt) {
        throw ("accepted_contract_receipt_missing: {0}" -f $receiptPath)
    }

    $accepted = $receipt.PSObject.Properties['acceptance_status'] -and [string]::Equals([string]$receipt.acceptance_status, 'accepted', [System.StringComparison]::OrdinalIgnoreCase)
    $checksumMatch = $receipt.PSObject.Properties['checksum_match'] -and [bool]$receipt.checksum_match
    $noReinterpretation = $receipt.PSObject.Properties['no_reinterpretation_confirmed'] -and [bool]$receipt.no_reinterpretation_confirmed
    if (-not $accepted -or -not $checksumMatch -or -not $noReinterpretation) {
        throw 'accepted_contract_receipt_not_verified'
    }

    return [pscustomobject]@{
        active = $true
        receipt_path = $receiptPath
        contract_path = $contractPath
        contract_version = if ($receipt.PSObject.Properties['contract_version']) { [string]$receipt.contract_version } else { 'v1' }
        schema_version = if ($receipt.PSObject.Properties['schema_version']) { [string]$receipt.schema_version } else { '2026-04-02-communication-contract-v1' }
        checksum_sha256 = if ($receipt.PSObject.Properties['checksum_sha256']) { [string]$receipt.checksum_sha256 } else { '' }
        authoritative_surface = $RemoteSurface
        local_stage_dir = $LocalStageDir
    }
}

function New-ContractSourceIdentity {
    $hostName = if (-not [string]::IsNullOrWhiteSpace([string]$env:COMPUTERNAME)) { [string]$env:COMPUTERNAME } else { [System.Environment]::MachineName }
    return [pscustomobject]@{
        actor = 'TOD'
        host = $hostName
        service = 'tod-mim-listener'
        instance_id = ($hostName + ':' + $PID)
    }
}

function New-ContractTransportDescriptor {
    param([Parameter(Mandatory = $true)]$BindingMetadata)

    return [pscustomobject]@{
        transport_id = 'mim_server_shared_artifact_boundary'
        surface = [string]$BindingMetadata.authoritative_surface
        local_stage_dir = [string]$BindingMetadata.local_stage_dir
    }
}

function Get-NonEmptyPacketValue {
    param(
        [string]$Primary,
        [string]$Fallback
    )

    if (-not [string]::IsNullOrWhiteSpace([string]$Primary)) {
        return [string]$Primary
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$Fallback)) {
        return [string]$Fallback
    }
    return 'unknown'
}

function Add-ContractPacketEnvelope {
    param(
        [Parameter(Mandatory = $true)]$Packet,
        [Parameter(Mandatory = $true)]$BindingMetadata,
        [Parameter(Mandatory = $true)][string]$PacketType,
        [Parameter(Mandatory = $true)][string]$MessageKind,
        [Parameter(Mandatory = $true)][string]$ObjectiveId,
        [Parameter(Mandatory = $true)][string]$TaskId,
        [Parameter(Mandatory = $true)][string]$RequestId,
        [Parameter(Mandatory = $true)][string]$CorrelationId
    )

    $Packet | Add-Member -NotePropertyName packet_type -NotePropertyValue $PacketType -Force
    $Packet | Add-Member -NotePropertyName schema_version -NotePropertyValue ([string]$BindingMetadata.schema_version) -Force
    $Packet | Add-Member -NotePropertyName contract_version -NotePropertyValue ([string]$BindingMetadata.contract_version) -Force
    $Packet | Add-Member -NotePropertyName source_identity -NotePropertyValue (New-ContractSourceIdentity) -Force
    $Packet | Add-Member -NotePropertyName transport -NotePropertyValue (New-ContractTransportDescriptor -BindingMetadata $BindingMetadata) -Force
    $Packet | Add-Member -NotePropertyName objective_id -NotePropertyValue (Get-NonEmptyPacketValue -Primary $ObjectiveId -Fallback $RequestId) -Force
    $Packet | Add-Member -NotePropertyName task_id -NotePropertyValue (Get-NonEmptyPacketValue -Primary $TaskId -Fallback $RequestId) -Force
    $Packet | Add-Member -NotePropertyName request_id -NotePropertyValue (Get-NonEmptyPacketValue -Primary $RequestId -Fallback $TaskId) -Force
    $Packet | Add-Member -NotePropertyName correlation_id -NotePropertyValue (Get-NonEmptyPacketValue -Primary $CorrelationId -Fallback $RequestId) -Force
    $Packet | Add-Member -NotePropertyName message_kind -NotePropertyValue $MessageKind -Force
    $Packet | Add-Member -NotePropertyName checksum_sha256 -NotePropertyValue ([string]$BindingMetadata.checksum_sha256) -Force
    $Packet | Add-Member -NotePropertyName authoritative_surface -NotePropertyValue ([string]$BindingMetadata.authoritative_surface) -Force
}

function Get-AckReasonCode {
    param([string]$Status)

    switch (([string]$Status).Trim().ToLowerInvariant()) {
        'accepted' { return 'request_accepted_for_execution' }
        'rejected' { return 'request_rejected' }
        'superseded_ignored' { return 'superseded_request_ignored' }
        'stale_ignored' { return 'stale_request_ignored' }
        default { return 'ack_status_unmapped' }
    }
}

function Get-ResultReasonCode {
    param(
        [string]$Status,
        [AllowNull()]$Execution = $null,
        [AllowNull()]$ReviewGate = $null,
        [AllowNull()]$ValidatorResult = $null
    )

    $statusNormalized = ([string]$Status).Trim().ToLowerInvariant()
    if ($statusNormalized -eq 'succeeded') { return 'execution_completed' }
    if ($statusNormalized -eq 'blocked') {
        if ($Execution -and $Execution.PSObject.Properties['payload_blocker'] -and $Execution.payload_blocker -and $Execution.payload_blocker.PSObject.Properties['reason_code'] -and -not [string]::IsNullOrWhiteSpace([string]$Execution.payload_blocker.reason_code)) {
            return [string]$Execution.payload_blocker.reason_code
        }
        return 'execution_readiness_blocked'
    }
    if ($ReviewGate -and -not [bool]$ReviewGate.passed) { return 'review_gate_failed' }
    if ($ValidatorResult -and -not [bool]$ValidatorResult.passed) { return 'invalid_packet_shape' }
    if ($Execution -and $Execution.PSObject.Properties['execution_mode'] -and [string]::Equals([string]$Execution.execution_mode, 'timeout', [System.StringComparison]::OrdinalIgnoreCase)) { return 'executor_timed_out' }
    return 'executor_failed'
}

function Get-ExecutionPayloadBlocker {
    param([AllowNull()]$Payload = $null)

    $candidates = New-Object System.Collections.Generic.List[object]
    if ($null -ne $Payload) {
        $candidates.Add($Payload)
        if ($Payload.PSObject.Properties['run_task'] -and $null -ne $Payload.run_task) {
            $candidates.Add($Payload.run_task)
        }
        if ($Payload.PSObject.Properties['payload'] -and $null -ne $Payload.payload) {
            $candidates.Add($Payload.payload)
        }
        if ($Payload.PSObject.Properties['engine_invocation'] -and $Payload.engine_invocation -and $Payload.engine_invocation.PSObject.Properties['result'] -and $null -ne $Payload.engine_invocation.result) {
            $candidates.Add($Payload.engine_invocation.result)
        }
    }

    foreach ($candidate in $candidates) {
        if ($null -eq $candidate) { continue }
        $reasonCode = if ($candidate.PSObject.Properties['reason_code']) { [string]$candidate.reason_code } else { '' }
        $summary = if ($candidate.PSObject.Properties['summary']) { [string]$candidate.summary } else { '' }
        $decision = if ($candidate.PSObject.Properties['decision']) { ([string]$candidate.decision).Trim().ToLowerInvariant() } else { '' }
        $status = if ($candidate.PSObject.Properties['status']) { ([string]$candidate.status).Trim().ToLowerInvariant() } else { '' }
        $executionStatus = if ($candidate.PSObject.Properties['execution_status']) { ([string]$candidate.execution_status).Trim().ToLowerInvariant() } else { '' }
        $failureCategory = if ($candidate.PSObject.Properties['failure_category']) { ([string]$candidate.failure_category).Trim().ToLowerInvariant() } else { '' }
        $blockedFlag = ($candidate.PSObject.Properties['blocked'] -and [bool]$candidate.blocked)
        $isBlocked = (
            $blockedFlag -or
            $decision -in @('blocked', 'revise', 'failed') -or
            $status -in @('blocked', 'blocked_with_reason', 'blocked_with_inspection') -or
            $executionStatus -in @('blocked', 'blocked_with_reason', 'blocked_with_inspection') -or
            $failureCategory -eq 'materialization_blocked' -or
            [string]::Equals($reasonCode, 'blocked_missing_bounded_edit_mode', [System.StringComparison]::OrdinalIgnoreCase)
        )
        if ($isBlocked) {
            return [pscustomobject]@{
                blocked = $true
                reason_code = $(if (-not [string]::IsNullOrWhiteSpace($reasonCode)) { $reasonCode } elseif (-not [string]::IsNullOrWhiteSpace($failureCategory)) { $failureCategory } else { 'payload_reported_blocked' })
                summary = $summary
                decision = $decision
                status = $(if (-not [string]::IsNullOrWhiteSpace($status)) { $status } else { $executionStatus })
            }
        }
    }

    return [pscustomobject]@{
        blocked = $false
        reason_code = ''
        summary = ''
        decision = ''
        status = ''
    }
}

function Read-RuntimeBindingState {
    param(
        [Parameter(Mandatory = $true)][string]$StatePath,
        [Parameter(Mandatory = $true)]$BindingMetadata
    )

    $existing = Read-JsonFileIfExists -PathValue $StatePath
    if ($null -ne $existing) {
        return $existing
    }

    return [pscustomobject]@{
        generated_at = Get-UtcNowString
        source = 'tod-mim-runtime-binding-v1'
        receipt_verified = $true
        contract_version = [string]$BindingMetadata.contract_version
        schema_version = [string]$BindingMetadata.schema_version
        checksum_sha256 = [string]$BindingMetadata.checksum_sha256
        receipt_path = [string]$BindingMetadata.receipt_path
        contract_path = [string]$BindingMetadata.contract_path
        authoritative_surface = [string]$BindingMetadata.authoritative_surface
        ack_runtime_binding = [pscustomobject]@{
            state = 'active'
            first_validation = $null
            last_validation = $null
        }
        result_runtime_binding = [pscustomobject]@{
            state = 'active'
            first_validation = $null
            last_validation = $null
        }
        last_violation = $null
    }
}

function Write-RuntimeBindingState {
    param(
        [Parameter(Mandatory = $true)][string]$StatePath,
        [Parameter(Mandatory = $true)]$State
    )

    $State.generated_at = Get-UtcNowString
    Write-JsonFile -PathValue $StatePath -Payload $State -Depth 30
}

function Test-ContractRuntimePacket {
    param(
        [Parameter(Mandatory = $true)][string]$PythonCommand,
        [Parameter(Mandatory = $true)][string]$ValidatorScript,
        [Parameter(Mandatory = $true)]$BindingMetadata,
        [Parameter(Mandatory = $true)][string]$PacketKind,
        [Parameter(Mandatory = $true)]$Packet
    )

    $tempPath = Join-Path ([System.IO.Path]::GetTempPath()) ('tod-mim-runtime-' + $PacketKind + '-' + [guid]::NewGuid().ToString('N') + '.json')
    try {
        Write-JsonFile -PathValue $tempPath -Payload $Packet -Depth 30
        $raw = & $PythonCommand $ValidatorScript --contract $BindingMetadata.contract_path --receipt $BindingMetadata.receipt_path --packet $tempPath --kind $PacketKind
        if ($LASTEXITCODE -ne 0) {
            throw 'runtime_contract_validator_failed'
        }
        return ($raw | Out-String | ConvertFrom-Json)
    }
    finally {
        Remove-Item -Path $tempPath -Force -ErrorAction SilentlyContinue
    }
}

function Register-RuntimeValidationResult {
    param(
        [Parameter(Mandatory = $true)][string]$StatePath,
        [Parameter(Mandatory = $true)]$BindingMetadata,
        [Parameter(Mandatory = $true)][string]$PacketKind,
        [Parameter(Mandatory = $true)]$Packet,
        [Parameter(Mandatory = $true)]$ValidationResult,
        [string]$State = 'active'
    )

    $bindingState = Read-RuntimeBindingState -StatePath $StatePath -BindingMetadata $BindingMetadata
    $entry = [pscustomobject]@{
        validated_at = Get-UtcNowString
        passed = [bool]$ValidationResult.passed
        request_id = if ($Packet.PSObject.Properties['request_id']) { [string]$Packet.request_id } else { '' }
        task_id = if ($Packet.PSObject.Properties['task_id']) { [string]$Packet.task_id } else { '' }
        status = if ($Packet.PSObject.Properties['status']) { [string]$Packet.status } else { '' }
        errors = @($ValidationResult.errors)
    }

    $propertyName = if ([string]::Equals($PacketKind, 'ack', [System.StringComparison]::OrdinalIgnoreCase)) { 'ack_runtime_binding' } else { 'result_runtime_binding' }
    $bindingEntry = $bindingState.$propertyName
    $bindingEntry.state = $State
    if ($null -eq $bindingEntry.first_validation) {
        $bindingEntry.first_validation = $entry
    }
    $bindingEntry.last_validation = $entry
    Write-RuntimeBindingState -StatePath $StatePath -State $bindingState
    return $entry
}

function Publish-RuntimeContractViolation {
    param(
        [Parameter(Mandatory = $true)][string]$ViolationPath,
        [Parameter(Mandatory = $true)][string]$StatePath,
        [Parameter(Mandatory = $true)]$BindingMetadata,
        [Parameter(Mandatory = $true)][string]$PacketKind,
        [Parameter(Mandatory = $true)]$Packet,
        [Parameter(Mandatory = $true)]$ValidationResult
    )

    $violation = [pscustomobject]@{
        generated_at = Get-UtcNowString
        source = 'tod-mim-runtime-contract-binding-v1'
        packet_kind = $PacketKind
        request_id = if ($Packet.PSObject.Properties['request_id']) { [string]$Packet.request_id } else { '' }
        task_id = if ($Packet.PSObject.Properties['task_id']) { [string]$Packet.task_id } else { '' }
        objective_id = if ($Packet.PSObject.Properties['objective_id']) { [string]$Packet.objective_id } else { '' }
        status = if ($Packet.PSObject.Properties['status']) { [string]$Packet.status } else { '' }
        contract_version = [string]$BindingMetadata.contract_version
        schema_version = [string]$BindingMetadata.schema_version
        checksum_sha256 = [string]$BindingMetadata.checksum_sha256
        authoritative_surface = [string]$BindingMetadata.authoritative_surface
        violations = @($ValidationResult.errors)
        rejected = $true
    }

    Write-JsonFile -PathValue $ViolationPath -Payload $violation -Depth 30
    $bindingState = Read-RuntimeBindingState -StatePath $StatePath -BindingMetadata $BindingMetadata
    $bindingState.last_violation = $violation
    Write-RuntimeBindingState -StatePath $StatePath -State $bindingState
    return $violation
}

function Get-RetryWeight {
    param([string]$RetryReason)

    switch (([string]$RetryReason).Trim().ToLowerInvariant()) {
        "failure" { return 1.0 }
        "duplicate_seen" { return 0.35 }
        "no_new_work" { return 0.15 }
        "waiting_go_order" { return 0.25 }
        default { return 0.0 }
    }
}

function Update-CadencePlan {
    param(
        [Parameter(Mandatory = $true)]$ListenerState,
        [Parameter(Mandatory = $true)][string]$ListenerStatePath,
        [Parameter(Mandatory = $true)][string]$CycleClassification,
        [string]$RetryReason = "none",
        [bool]$WasSuccess = $false,
        [int]$BasePollSeconds = 2
    )

    $retryReasonNormalized = if ([string]::IsNullOrWhiteSpace($RetryReason)) { "none" } else { ([string]$RetryReason).Trim().ToLowerInvariant() }
    $classificationNormalized = if ([string]::IsNullOrWhiteSpace($CycleClassification)) { "unknown" } else { [string]$CycleClassification }
    $previousRetryStreak = if ($ListenerState.PSObject.Properties["cadence_retry_streak"]) { [int]$ListenerState.cadence_retry_streak } else { 0 }
    $previousBackoff = if ($ListenerState.PSObject.Properties["cadence_backoff_seconds"]) { [int]$ListenerState.cadence_backoff_seconds } else { 0 }

    if ($WasSuccess) {
        $retryStreak = 0
        $backoffSeconds = 0
        $minimumCycleSeconds = [Math]::Max($BasePollSeconds, 3)
        $ListenerState.cadence_last_success_at = Get-UtcNowString
    }
    else {
        $retryStreak = switch ($retryReasonNormalized) {
            'none' { 0 }
            'duplicate_seen' { 0 }
            default { $previousRetryStreak + 1 }
        }
        switch ($retryReasonNormalized) {
            "failure" {
                $backoffSeconds = [Math]::Min(30, [Math]::Max($previousBackoff, $BasePollSeconds) + ([Math]::Min($retryStreak, 5) * 2))
            }
            "duplicate_seen" {
                $backoffSeconds = [Math]::Max($BasePollSeconds, 4)
                $ListenerState.cadence_last_success_at = Get-UtcNowString
            }
            "no_new_work" {
                $backoffSeconds = [Math]::Min(12, [Math]::Floor(($retryStreak + 1) / 2))
            }
            "waiting_go_order" {
                $backoffSeconds = [Math]::Min(20, [Math]::Max($previousBackoff, 1) + [Math]::Min($retryStreak, 4))
            }
            default {
                $backoffSeconds = 0
            }
        }

        $minimumCycleSeconds = switch ($retryReasonNormalized) {
            "failure" { [Math]::Max($BasePollSeconds, 4) }
            "duplicate_seen" { [Math]::Max($BasePollSeconds, 3) }
            "no_new_work" { [Math]::Max($BasePollSeconds, 3) }
            "waiting_go_order" { [Math]::Max($BasePollSeconds, 3) }
            default { [Math]::Max($BasePollSeconds, 2) }
        }
    }

    $sleepSeconds = [Math]::Max($minimumCycleSeconds, $BasePollSeconds + $backoffSeconds)

    $ListenerState.last_cycle_classification = $classificationNormalized
    $ListenerState.last_retry_reason = $retryReasonNormalized
    $ListenerState.cadence_retry_streak = $retryStreak
    $ListenerState.cadence_backoff_seconds = $backoffSeconds
    $ListenerState.cadence_minimum_cycle_seconds = $minimumCycleSeconds
    $ListenerState.cadence_planned_sleep_seconds = $sleepSeconds
    Write-JsonFile -PathValue $ListenerStatePath -Payload $ListenerState

    return [pscustomobject]@{
        cycle_classification = $classificationNormalized
        retry_reason = $retryReasonNormalized
        retry_streak = $retryStreak
        backoff_seconds = $backoffSeconds
        minimum_cycle_seconds = $minimumCycleSeconds
        sleep_seconds = $sleepSeconds
        cadence_noise = @("duplicate_seen", "no_new_work", "waiting_go_order") -contains $retryReasonNormalized
        retry_weight = Get-RetryWeight -RetryReason $retryReasonNormalized
    }
}

function Add-LoopJournalEntry {
    param(
        [Parameter(Mandatory = $true)][string]$LocalJournalPath,
        [AllowNull()]$Connections = $null,
        [string]$RemoteJournalPath = "",
        [string]$RequestId = "",
        [string]$ObjectiveId = "",
        [string]$AckStatus = "",
        [string]$ExecutionStatus = "",
        [string]$Action = "",
        [string]$IntegrationAlignment = "unknown",
        [Nullable[bool]]$IntegrationCompatible = $null,
        [Nullable[bool]]$ReviewGatePassed = $null,
        [Nullable[bool]]$ValidatorPassed = $null,
        [AllowNull()]$ExecutionReadiness = $null,
        [AllowNull()]$RegressionSnapshot = $null,
        [bool]$StalledNoDelta = $false,
        [string]$CycleClassification = "",
        [string]$RetryReason = "none",
        [AllowNull()]$CadencePlan = $null,
        [bool]$PublishRemote = $false
    )

    $journalExisting = Read-JsonFileIfExists -PathValue $LocalJournalPath
    $entries = @()
    if ($null -eq $journalExisting) {
        $entries = @()
    }
    elseif ($journalExisting -is [System.Array]) {
        $entries = @($journalExisting)
    }
    elseif ($journalExisting.PSObject.Properties["entries"]) {
        $entries = @($journalExisting.entries)
    }

    $retryReasonNormalized = if ([string]::IsNullOrWhiteSpace($RetryReason)) { "none" } else { ([string]$RetryReason).Trim().ToLowerInvariant() }
    $cycleClassificationValue = if ([string]::IsNullOrWhiteSpace($CycleClassification)) { "unknown" } else { [string]$CycleClassification }
    $retryWeight = if ($null -ne $CadencePlan -and $CadencePlan.PSObject.Properties["retry_weight"]) { [double]$CadencePlan.retry_weight } else { Get-RetryWeight -RetryReason $retryReasonNormalized }
    $cadenceNoise = if ($null -ne $CadencePlan -and $CadencePlan.PSObject.Properties["cadence_noise"]) { [bool]$CadencePlan.cadence_noise } else { @("duplicate_seen", "no_new_work", "waiting_go_order") -contains $retryReasonNormalized }

    $entries += [pscustomobject]@{
        timestamp = (Get-Date).ToUniversalTime().ToString("o")
        request_id = $RequestId
        objective_id = $ObjectiveId
        ack_status = $AckStatus
        execution_status = $ExecutionStatus
        action = $Action
        integration_alignment = $IntegrationAlignment
        integration_compatible = $IntegrationCompatible
        review_gate_passed = $ReviewGatePassed
        validator_passed = $ValidatorPassed
        execution_readiness_status = if ($null -ne $ExecutionReadiness -and $ExecutionReadiness.PSObject.Properties["status"]) { [string]$ExecutionReadiness.status } else { "" }
        execution_readiness_source = if ($null -ne $ExecutionReadiness -and $ExecutionReadiness.PSObject.Properties["source"]) { [string]$ExecutionReadiness.source } else { "" }
        execution_readiness_policy_outcome = if ($null -ne $ExecutionReadiness -and $ExecutionReadiness.PSObject.Properties["policy_outcome"]) { [string]$ExecutionReadiness.policy_outcome } else { "" }
        regression_failed = if ($RegressionSnapshot -and $RegressionSnapshot.PSObject.Properties["failed"]) { [int]$RegressionSnapshot.failed } else { -1 }
        regression_signature = if ($RegressionSnapshot -and $RegressionSnapshot.PSObject.Properties["signature"]) { [string]$RegressionSnapshot.signature } else { "" }
        stalled_no_delta = [bool]$StalledNoDelta
        cycle_classification = $cycleClassificationValue
        retry_reason = $retryReasonNormalized
        retry_due_to_failure = ($retryReasonNormalized -eq "failure")
        retry_due_to_no_new_work = ($retryReasonNormalized -eq "no_new_work")
        retry_due_to_duplicate_seen = ($retryReasonNormalized -eq "duplicate_seen")
        cadence_noise = $cadenceNoise
        retry_weight = [Math]::Round([double]$retryWeight, 3)
        planned_sleep_seconds = if ($null -ne $CadencePlan -and $CadencePlan.PSObject.Properties["sleep_seconds"]) { [int]$CadencePlan.sleep_seconds } else { 0 }
        minimum_cycle_seconds = if ($null -ne $CadencePlan -and $CadencePlan.PSObject.Properties["minimum_cycle_seconds"]) { [int]$CadencePlan.minimum_cycle_seconds } else { 0 }
        backoff_seconds = if ($null -ne $CadencePlan -and $CadencePlan.PSObject.Properties["backoff_seconds"]) { [int]$CadencePlan.backoff_seconds } else { 0 }
        retry_streak = if ($null -ne $CadencePlan -and $CadencePlan.PSObject.Properties["retry_streak"]) { [int]$CadencePlan.retry_streak } else { 0 }
    }

    if (@($entries).Count -gt 200) {
        $entries = @($entries | Select-Object -Last 200)
    }

    $journal = [pscustomobject]@{
        generated_at = (Get-Date).ToUniversalTime().ToString("o")
        source = "tod-loop-journal-v1"
        entries = @($entries)
    }
    Write-JsonFile -PathValue $LocalJournalPath -Payload $journal

    if ($PublishRemote -and $Connections -and -not [string]::IsNullOrWhiteSpace($RemoteJournalPath)) {
        $journalJson = Get-Content -Path $LocalJournalPath -Raw
        Write-RemoteFileFromText -Connections $Connections -RemotePath $RemoteJournalPath -Content $journalJson
    }
}

function Get-AgeSeconds {
    param([string]$Since)

    if ([string]::IsNullOrWhiteSpace($Since)) {
        return 99999
    }

    [datetime]$parsed = [datetime]::MinValue
    if (-not [datetime]::TryParse($Since, [ref]$parsed)) {
        return 99999
    }

    return [int][math]::Floor(([DateTime]::UtcNow - $parsed.ToUniversalTime()).TotalSeconds)
}

function Get-BridgeRuntimeStatus {
    param(
        [string]$CurrentTaskId = "",
        [string]$CurrentCorrelationId = ""
    )

    $writerLockPath = Get-LocalPath -PathValue "shared_state/tod_recoupling_gate_state.latest.json.writer.lock.json"
    $watcherStatePath = Get-LocalPath -PathValue "shared_state/tod_catchup_gate_watcher.latest.json"
    $writerLock = Read-JsonFileIfExists -PathValue $writerLockPath
    $watcherState = Read-JsonFileIfExists -PathValue $watcherStatePath

    $writerId = if ($writerLock -and $writerLock.PSObject.Properties["writer_id"] -and -not [string]::IsNullOrWhiteSpace([string]$writerLock.writer_id)) {
        [string]$writerLock.writer_id
    }
    elseif ($watcherState -and $watcherState.PSObject.Properties["writer_id"] -and -not [string]::IsNullOrWhiteSpace([string]$watcherState.writer_id)) {
        [string]$watcherState.writer_id
    }
    else {
        "tod-catchup-gate-watcher"
    }

    $catchupIntervalSeconds = 30
    if ($watcherState -and $watcherState.PSObject.Properties["interval_seconds"]) {
        try { $catchupIntervalSeconds = [int]$watcherState.interval_seconds } catch { $catchupIntervalSeconds = 30 }
    }

    return [pscustomobject]@{
        listener = [pscustomobject]@{
            mode = "managed_polling_ssh_sync"
            single_instance_enforced = $true
            mutex = $script:ListenerMutexName
            poll_interval_seconds = [int]$PollSeconds
            transport = "ssh_sftp"
            shared_path_kind = "sync-backed"
            remote_root = $RemoteRoot
            local_stage_dir = $StageDir
        }
        catchup_writer = [pscustomobject]@{
            mode = "single_writer_mutex_and_lock"
            writer_id = $writerId
            watcher_interval_seconds = $catchupIntervalSeconds
            lock_path = $writerLockPath
        }
        current_processing = [pscustomobject]@{
            task_id = $CurrentTaskId
            correlation_id = $CurrentCorrelationId
        }
    }
}

function Get-TriggerContext {
    param([AllowNull()]$TriggerPacket)

    if ($null -eq $TriggerPacket) {
        return $null
    }

    $triggerSequence = Get-ObjectFieldLong -InputObject $TriggerPacket -FieldName "sequence"
    $packetType = Get-ObjectFieldText -InputObject $TriggerPacket -FieldName "packet_type"
    $sourceActor = Get-ObjectFieldText -InputObject $TriggerPacket -FieldName "source_actor"
    $targetActor = Get-ObjectFieldText -InputObject $TriggerPacket -FieldName "target_actor"
    $sourceHost = Get-ObjectFieldText -InputObject $TriggerPacket -FieldName "source_host"
    $sourceService = Get-ObjectFieldText -InputObject $TriggerPacket -FieldName "source_service"
    $sourceInstanceId = Get-ObjectFieldText -InputObject $TriggerPacket -FieldName "source_instance_id"
    $triggerType = Get-ObjectFieldText -InputObject $TriggerPacket -FieldName "trigger"
    $artifact = Get-ObjectFieldText -InputObject $TriggerPacket -FieldName "artifact"
    $artifactPath = Get-ObjectFieldText -InputObject $TriggerPacket -FieldName "artifact_path"
    $artifactSha256 = Get-ObjectFieldText -InputObject $TriggerPacket -FieldName "artifact_sha256"
    $taskId = Get-ObjectFieldText -InputObject $TriggerPacket -FieldName "task_id"
    $correlationId = Get-ObjectFieldText -InputObject $TriggerPacket -FieldName "correlation_id"
    $actionRequired = Get-ObjectFieldText -InputObject $TriggerPacket -FieldName "action_required"
    $ackFileExpected = Get-ObjectFieldText -InputObject $TriggerPacket -FieldName "ack_file_expected"
    $emittedAt = Get-ObjectFieldText -InputObject $TriggerPacket -FieldName "emitted_at"
    $generatedAt = Get-ObjectFieldText -InputObject $TriggerPacket -FieldName "generated_at"

    return [pscustomobject]@{
        sequence = $triggerSequence
        packet_type = $packetType
        source_actor = $sourceActor
        target_actor = $targetActor
        source_host = $sourceHost
        source_service = $sourceService
        source_instance_id = $sourceInstanceId
        trigger = $triggerType
        artifact = $artifact
        artifact_path = $artifactPath
        artifact_sha256 = $artifactSha256
        task_id = $taskId
        correlation_id = $correlationId
        action_required = $actionRequired
        ack_file_expected = $ackFileExpected
        emitted_at = $emittedAt
        generated_at = $generatedAt
    }
}

function Get-TriggerFieldText {
    param(
        [AllowNull()]$TriggerPacket,
        [Parameter(Mandatory = $true)][string]$FieldName
    )

    if ($null -eq $TriggerPacket) {
        return ""
    }

    if ($TriggerPacket.PSObject.Properties[$FieldName] -and -not [string]::IsNullOrWhiteSpace([string]$TriggerPacket.$FieldName)) {
        return [string]$TriggerPacket.$FieldName
    }

    return ""
}

function Get-TriggerFieldLong {
    param(
        [AllowNull()]$TriggerPacket,
        [Parameter(Mandatory = $true)][string]$FieldName
    )

    if ($null -eq $TriggerPacket) {
        return 0L
    }

    if ($TriggerPacket.PSObject.Properties[$FieldName] -and $null -ne $TriggerPacket.$FieldName) {
        try {
            return [long]$TriggerPacket.$FieldName
        }
        catch {
            return 0L
        }
    }

    return 0L
}

function Select-ContractRuntimeTrigger {
    param(
        [AllowNull()]$PreferredTrigger,
        [AllowNull()]$RequestPacket,
        [AllowNull()]$GoOrderPacket
    )

    if ((Get-TriggerFieldLong -TriggerPacket $PreferredTrigger -FieldName "sequence") -gt 0) {
        return $PreferredTrigger
    }

    if ((Get-TriggerFieldLong -TriggerPacket $RequestPacket -FieldName "sequence") -gt 0) {
        return $RequestPacket
    }

    if ((Get-TriggerFieldLong -TriggerPacket $GoOrderPacket -FieldName "sequence") -gt 0) {
        return $GoOrderPacket
    }

    if ($null -ne $PreferredTrigger) {
        return $PreferredTrigger
    }

    if ($null -ne $RequestPacket) {
        return $RequestPacket
    }

    return $GoOrderPacket
}

function Get-NextOutboundSequence {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][string]$StatePath
    )

    $nextValue = 1L
    if ($State.PSObject.Properties["last_outbound_sequence"]) {
        try {
            $nextValue = [long]$State.last_outbound_sequence + 1L
        }
        catch {
            $nextValue = 1L
        }
    }

    $State.last_outbound_sequence = $nextValue
    Write-JsonFile -PathValue $StatePath -Payload $State
    return $nextValue
}

function New-SequenceRuntimeFields {
    param(
        [AllowNull()]$TriggerPacket,
        [Parameter(Mandatory = $true)]$ListenerState,
        [Parameter(Mandatory = $true)][string]$ListenerStatePath
    )

    $observedAt = Get-UtcNowString
    $ackSequence = Get-NextOutboundSequence -State $ListenerState -StatePath $ListenerStatePath
    $triggerSequence = Get-TriggerFieldLong -TriggerPacket $TriggerPacket -FieldName "sequence"
    if ($triggerSequence -le 0) {
        $triggerSequence = $ackSequence
    }

    return [pscustomobject]@{
        sequence = $ackSequence
        ack_sequence = $ackSequence
        acknowledged_trigger_sequence = $triggerSequence
        emitted_at = $observedAt
        observed_at = $observedAt
        source_host = $env:COMPUTERNAME
        source_service = "tod-mim-listener"
        source_instance_id = ("{0}:{1}" -f $env:COMPUTERNAME, $PID)
        consumer_host = $env:COMPUTERNAME
        consumer_service = "tod-mim-listener"
        consumer_instance_id = ("{0}:{1}" -f $env:COMPUTERNAME, $PID)
    }
}

function Add-SequenceRuntimeFields {
    param(
        [Parameter(Mandatory = $true)]$Packet,
        [AllowNull()]$TriggerPacket,
        [Parameter(Mandatory = $true)]$ListenerState,
        [Parameter(Mandatory = $true)][string]$ListenerStatePath
    )

    $runtime = New-SequenceRuntimeFields -TriggerPacket $TriggerPacket -ListenerState $ListenerState -ListenerStatePath $ListenerStatePath
    $Packet | Add-Member -NotePropertyName sequence -NotePropertyValue ([long]$runtime.sequence) -Force
    $Packet | Add-Member -NotePropertyName ack_sequence -NotePropertyValue ([long]$runtime.ack_sequence) -Force
    $Packet | Add-Member -NotePropertyName acknowledged_trigger_sequence -NotePropertyValue ([long]$runtime.acknowledged_trigger_sequence) -Force
    $Packet | Add-Member -NotePropertyName emitted_at -NotePropertyValue ([string]$runtime.emitted_at) -Force
    $Packet | Add-Member -NotePropertyName observed_at -NotePropertyValue ([string]$runtime.observed_at) -Force
    $Packet | Add-Member -NotePropertyName source_host -NotePropertyValue ([string]$runtime.source_host) -Force
    $Packet | Add-Member -NotePropertyName source_service -NotePropertyValue ([string]$runtime.source_service) -Force
    $Packet | Add-Member -NotePropertyName source_instance_id -NotePropertyValue ([string]$runtime.source_instance_id) -Force
    $Packet | Add-Member -NotePropertyName consumer_host -NotePropertyValue ([string]$runtime.consumer_host) -Force
    $Packet | Add-Member -NotePropertyName consumer_service -NotePropertyValue ([string]$runtime.consumer_service) -Force
    $Packet | Add-Member -NotePropertyName consumer_instance_id -NotePropertyValue ([string]$runtime.consumer_instance_id) -Force
    return $runtime
}

function Publish-IntegrationStatusFiles {
    param(
        [Parameter(Mandatory = $true)]$Connections,
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$LocalPath,
        [Parameter(Mandatory = $true)][string]$RemotePath,
        [string]$LocalAliasPath = "",
        [string]$RemoteAliasPath = ""
    )

    if (-not (Test-Path -Path $SourcePath)) {
        throw "Integration status source file not found: $SourcePath"
    }

    $json = (Get-Content -Path $SourcePath -Raw) -replace "`r`n", "`n"
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($LocalPath, $json, $utf8NoBom)
    Write-RemoteFileFromText -Connections $Connections -RemotePath $RemotePath -Content $json

    if (-not [string]::IsNullOrWhiteSpace($LocalAliasPath) -and -not [string]::IsNullOrWhiteSpace($RemoteAliasPath)) {
        [System.IO.File]::WriteAllText($LocalAliasPath, $json, $utf8NoBom)
        Write-RemoteFileFromText -Connections $Connections -RemotePath $RemoteAliasPath -Content $json
    }
}

function Invoke-SharedStateSyncRefresh {
    param(
        [Parameter(Mandatory = $true)][string]$SyncScriptAbs,
        [Parameter(Mandatory = $true)][string]$HostAlias,
        [Parameter(Mandatory = $true)][string]$RemoteRoot,
        [Parameter(Mandatory = $true)][string]$SyncStageRoot,
        [string]$ListenerRequestPath = "",
        [string]$Reason = ""
    )

    $syncError = ""
    try {
        $syncRepoRoot = Split-Path -Parent (Split-Path -Parent $SyncScriptAbs)
        $syncArgs = @(
            '-NoProfile'
            '-ExecutionPolicy'
            'Bypass'
            '-File'
            $SyncScriptAbs
            '-RefreshMimContextFromSsh'
            '-PublishTodStatusToMimArm'
            '-MimSshHost'
            $HostAlias
            '-MimSshSharedRoot'
            $RemoteRoot
            '-MimSshStagingRoot'
            $SyncStageRoot
        )

        if (-not [string]::IsNullOrWhiteSpace($ListenerRequestPath) -and (Test-Path -Path $ListenerRequestPath)) {
            $syncArgs += @('-ListenerRequestPath', $ListenerRequestPath)
        }

        Push-Location $syncRepoRoot
        try {
            $null = powershell @syncArgs 2>&1
            if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
                $syncError = ("sync exited {0}" -f $LASTEXITCODE)
                if ([string]::IsNullOrWhiteSpace($Reason)) {
                    Write-Warning ("[TOD-LISTENER] Shared-state sync exited {0}; continuing with latest available status." -f $LASTEXITCODE)
                }
                else {
                    Write-Warning ("[TOD-LISTENER] Shared-state sync exited {0} during {1}; continuing with latest available status." -f $LASTEXITCODE, $Reason)
                }
            }
        }
        finally {
            Pop-Location
        }
    }
    catch {
        $syncError = [string]$_.Exception.Message
        if ([string]::IsNullOrWhiteSpace($Reason)) {
            Write-Warning ("[TOD-LISTENER] Shared-state sync failed; continuing with latest available status: {0}" -f $syncError)
        }
        else {
            Write-Warning ("[TOD-LISTENER] Shared-state sync failed during {0}; continuing with latest available status: {1}" -f $Reason, $syncError)
        }
    }

    return $syncError
}

function Publish-LivenessResponse {
    param(
        [Parameter(Mandatory = $true)]$ListenerState,
        [Parameter(Mandatory = $true)][string]$ListenerStatePath,
        [Parameter(Mandatory = $true)]$Connections,
        [Parameter(Mandatory = $true)][string]$LocalPath,
        [Parameter(Mandatory = $true)][string]$RemotePath,
        [AllowNull()]$TriggerPacket,
        [AllowNull()]$PingPacket,
        [AllowNull()]$IntegrationStatus,
        [string]$TriggerId = "",
        [string]$CurrentTaskId = "",
        [string]$CurrentCorrelationId = "",
        [AllowNull()]$BridgeRuntime = $null
    )

    $alignment = if ($IntegrationStatus -and $IntegrationStatus.PSObject.Properties["objective_alignment"]) {
        $IntegrationStatus.objective_alignment
    }
    else {
        $null
    }
    $triggerContext = Get-TriggerContext -TriggerPacket $TriggerPacket
    $responseToTrigger = if ($null -ne $triggerContext -and -not [string]::IsNullOrWhiteSpace([string]$triggerContext.trigger)) {
        [string]$triggerContext.trigger
    }
    else {
        "liveness_ping"
    }

    $response = [pscustomobject]@{
        generated_at = (Get-Date).ToUniversalTime().ToString("o")
        source = "tod-liveness-response-v1"
        packet_type = "tod-mim-liveness-response-v1"
        status = "alive"
        response_to = $responseToTrigger
        trigger_request_id = $TriggerId
        requested_action = if ($PingPacket -and $PingPacket.PSObject.Properties["requested_action"]) { [string]$PingPacket.requested_action } else { "respond_with_alive_status" }
        ping_reason = if ($PingPacket -and $PingPacket.PSObject.Properties["reason"]) { [string]$PingPacket.reason } else { "" }
        compatible = if ($IntegrationStatus) { [bool]$IntegrationStatus.compatible } else { $false }
        objective_alignment_status = if ($alignment -and $alignment.PSObject.Properties["status"]) { [string]$alignment.status } else { "unknown" }
        tod_current_objective = if ($alignment -and $alignment.PSObject.Properties["tod_current_objective"]) { [string]$alignment.tod_current_objective } else { "" }
        mim_objective_active = if ($alignment -and $alignment.PSObject.Properties["mim_objective_active"]) { [string]$alignment.mim_objective_active } else { "" }
        integration_status_generated_at = if ($IntegrationStatus -and $IntegrationStatus.PSObject.Properties["generated_at"]) { [string]$IntegrationStatus.generated_at } else { "" }
        ack_file = "TOD_TO_MIM_TRIGGER_ACK.latest.json"
        current_task_id = $CurrentTaskId
        current_correlation_id = $CurrentCorrelationId
    }

    if ($null -ne $triggerContext) {
        $response | Add-Member -NotePropertyName trigger_context -NotePropertyValue $triggerContext -Force
        $response | Add-Member -NotePropertyName response_to_artifact -NotePropertyValue ([string]$triggerContext.artifact) -Force
        $response | Add-Member -NotePropertyName response_to_packet_type -NotePropertyValue ([string]$triggerContext.packet_type) -Force
    }

    $null = Add-SequenceRuntimeFields -Packet $response -TriggerPacket $TriggerPacket -ListenerState $ListenerState -ListenerStatePath $ListenerStatePath

    if ($null -ne $BridgeRuntime) {
        $response | Add-Member -NotePropertyName bridge_runtime -NotePropertyValue $BridgeRuntime -Force
    }

    Write-JsonFile -PathValue $LocalPath -Payload $response
    $responseJson = Get-Content -Path $LocalPath -Raw
    Write-RemoteFileFromText -Connections $Connections -RemotePath $RemotePath -Content $responseJson
}

function Test-StringArrayEquivalent {
    param(
        [AllowNull()]$Left,
        [AllowNull()]$Right
    )

    $leftValues = @($Left | ForEach-Object { [string]$_ })
    $rightValues = @($Right | ForEach-Object { [string]$_ })

    if ($leftValues.Count -ne $rightValues.Count) {
        return $false
    }

    for ($i = 0; $i -lt $leftValues.Count; $i++) {
        if (-not [string]::Equals([string]$leftValues[$i], [string]$rightValues[$i], [System.StringComparison]::Ordinal)) {
            return $false
        }
    }

    return $true
}

function Sync-LocalObjectiveFromRequest {
    param([Parameter(Mandatory = $true)]$Request)

    $requestedObjective = Get-ExpectedObjectiveFromRequest -Request $Request
    if ([string]::IsNullOrWhiteSpace($requestedObjective)) {
        return [pscustomobject]@{
            changed = $false
            objective_id = ""
            reason = "request_objective_missing"
        }
    }

    $nextActionsPath = Get-LocalPath -PathValue "shared_state/next_actions.json"
    $nextActions = Read-JsonFileIfExists -PathValue $nextActionsPath
    $currentObjectiveInProgress = ""
    if ($nextActions -and $nextActions.PSObject.Properties["current_objective_in_progress"] -and -not [string]::IsNullOrWhiteSpace([string]$nextActions.current_objective_in_progress)) {
        $currentObjectiveInProgress = Get-ExpectedObjectiveFromRequest -Request ([pscustomobject]@{ objective_id = [string]$nextActions.current_objective_in_progress })
    }
    $allowObjectiveOverride = Test-AllowManagedObjectiveOverrideFromRequest -Request $Request -CurrentObjectiveInProgress $currentObjectiveInProgress
    if (-not [string]::IsNullOrWhiteSpace($currentObjectiveInProgress) -and -not [string]::Equals($requestedObjective, $currentObjectiveInProgress, [System.StringComparison]::OrdinalIgnoreCase) -and -not $allowObjectiveOverride) {
        return [pscustomobject]@{
            changed = $false
            objective_id = $requestedObjective
            reason = "objective_mismatch_ignored"
        }
    }

    $statePath = Get-LocalPath -PathValue "tod/data/state.json"
    $state = Read-JsonFileIfExists -PathValue $statePath
    if ($null -eq $state) {
        return [pscustomobject]@{
            changed = $false
            objective_id = $requestedObjective
            reason = "state_unavailable"
        }
    }

    if (-not $state.PSObject.Properties["objectives"]) {
        $state | Add-Member -NotePropertyName objectives -NotePropertyValue @() -Force
    }

    $objectives = @($state.objectives)
    $existing = @($objectives | Where-Object { [string]$_.id -eq $requestedObjective } | Select-Object -First 1)
    $updatedAt = Get-UtcNowString
    $changed = $false

    $title = if ($Request.PSObject.Properties["title"] -and -not [string]::IsNullOrWhiteSpace([string]$Request.title)) {
        Limit-ListenerStateText -Value ([string]$Request.title) -MaxLength 512 -FieldName "objective.title"
    }
    else {
        "Objective $requestedObjective - MIM synchronized objective"
    }

    $description = if ($Request.PSObject.Properties["scope"] -and -not [string]::IsNullOrWhiteSpace([string]$Request.scope)) {
        Limit-ListenerStateText -Value ([string]$Request.scope) -MaxLength 8192 -FieldName "objective.description"
    }
    elseif ($Request.PSObject.Properties["description"] -and -not [string]::IsNullOrWhiteSpace([string]$Request.description)) {
        Limit-ListenerStateText -Value ([string]$Request.description) -MaxLength 8192 -FieldName "objective.description"
    }
    else {
        "Synchronized from MIM request $($Request.task_id)."
    }

    $constraints = @()
    if ($Request.PSObject.Properties["constraints"] -and $null -ne $Request.constraints) {
        $constraints = @($Request.constraints | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    $successCriteria = @()
    if ($Request.PSObject.Properties["acceptance_criteria"] -and $null -ne $Request.acceptance_criteria) {
        $successCriteria = @($Request.acceptance_criteria | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    if (@($existing).Count -eq 0) {
        $newObjective = [pscustomobject]@{
            id = $requestedObjective
            title = $title
            description = $description
            priority = if ($Request.PSObject.Properties["priority"] -and -not [string]::IsNullOrWhiteSpace([string]$Request.priority)) { [string]$Request.priority } else { "high" }
            constraints = @($constraints)
            success_criteria = @($successCriteria)
            status = "open"
            created_at = $updatedAt
            updated_at = $updatedAt
        }
        $state.objectives = @($objectives) + @($newObjective)
        $changed = $true
    }
    else {
        $objective = $existing[0]
        if ($objective.PSObject.Properties["status"] -and [string]::Equals([string]$objective.status, "completed", [System.StringComparison]::OrdinalIgnoreCase)) {
            return [pscustomobject]@{
                changed = $false
                objective_id = $requestedObjective
                reason = "objective_completed_ignored"
            }
        }
        if (-not [string]::Equals([string]$objective.title, $title, [System.StringComparison]::Ordinal)) {
            $objective.title = $title
            $changed = $true
        }
        if (-not [string]::Equals([string]$objective.description, $description, [System.StringComparison]::Ordinal)) {
            $objective.description = $description
            $changed = $true
        }
        if ($successCriteria.Count -gt 0 -and -not (Test-StringArrayEquivalent -Left @($objective.success_criteria) -Right @($successCriteria))) {
            $objective.success_criteria = @($successCriteria)
            $changed = $true
        }
        if ($constraints.Count -gt 0 -and -not (Test-StringArrayEquivalent -Left @($objective.constraints) -Right @($constraints))) {
            $objective.constraints = @($constraints)
            $changed = $true
        }
        if ($changed) {
            $objective.updated_at = $updatedAt
        }
    }

    if ($changed) {
        Write-JsonFile -PathValue $statePath -Payload $state -Depth 100
    }

    return [pscustomobject]@{
        changed = $changed
        objective_id = $requestedObjective
        reason = if ($changed) { "objective_upserted" } else { "already_current" }
    }
}

function Sync-LocalTaskFromRequest {
    param($Request)

    if ($null -eq $Request) {
        return [pscustomobject]@{
            changed = $false
            created = $false
            task_id = ""
            objective_id = ""
            reason = "request_missing"
        }
    }

    $requestedObjective = Get-ExpectedObjectiveFromRequest -Request $Request
    if ([string]::IsNullOrWhiteSpace($requestedObjective)) {
        return [pscustomobject]@{
            changed = $false
            created = $false
            task_id = ""
            objective_id = ""
            reason = "request_objective_missing"
        }
    }

    $taskId = if ($Request.PSObject.Properties['task_id'] -and -not [string]::IsNullOrWhiteSpace([string]$Request.task_id)) {
        [string]$Request.task_id
    }
    else {
        ""
    }
    if ([string]::IsNullOrWhiteSpace($taskId)) {
        return [pscustomobject]@{
            changed = $false
            created = $false
            task_id = ""
            objective_id = $requestedObjective
            reason = "request_task_missing"
        }
    }

    $statePath = Get-LocalPath -PathValue "tod/data/state.json"
    $state = Read-JsonFileIfExists -PathValue $statePath
    if ($null -eq $state) {
        return [pscustomobject]@{
            changed = $false
            created = $false
            task_id = $taskId
            objective_id = $requestedObjective
            reason = "state_unavailable"
        }
    }

    if (-not $state.PSObject.Properties['tasks']) {
        $state | Add-Member -NotePropertyName tasks -NotePropertyValue @() -Force
    }

    $title = if ($Request.PSObject.Properties['title'] -and -not [string]::IsNullOrWhiteSpace([string]$Request.title)) {
        Limit-ListenerStateText -Value ([string]$Request.title) -MaxLength 512 -FieldName 'task.title'
    }
    else {
        "MIM synchronized task $taskId"
    }

    $scope = if ($Request.PSObject.Properties['scope'] -and -not [string]::IsNullOrWhiteSpace([string]$Request.scope)) {
        Limit-ListenerStateText -Value ([string]$Request.scope) -MaxLength 8192 -FieldName 'task.scope'
    }
    elseif ($Request.PSObject.Properties['description'] -and -not [string]::IsNullOrWhiteSpace([string]$Request.description)) {
        Limit-ListenerStateText -Value ([string]$Request.description) -MaxLength 8192 -FieldName 'task.scope'
    }
    else {
        "Synchronized from MIM request $taskId."
    }

    $acceptanceCriteria = @()
    if ($Request.PSObject.Properties['acceptance_criteria'] -and $null -ne $Request.acceptance_criteria) {
        $acceptanceCriteria = @($Request.acceptance_criteria | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    $dependencies = @()
    if ($Request.PSObject.Properties['constraints'] -and $null -ne $Request.constraints) {
        $dependencies = @($Request.constraints | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    $priority = if ($Request.PSObject.Properties['priority'] -and -not [string]::IsNullOrWhiteSpace([string]$Request.priority)) {
        [string]$Request.priority
    }
    else {
        'high'
    }

    $metadata = if ($Request.PSObject.Properties['metadata_json'] -and $null -ne $Request.metadata_json) { $Request.metadata_json } else { [pscustomobject]@{} }
    $boundedSlice = if ($Request.PSObject.Properties['bounded_slice'] -and $null -ne $Request.bounded_slice) {
        $Request.bounded_slice
    }
    elseif ($metadata.PSObject.Properties['bounded_slice'] -and $null -ne $metadata.bounded_slice) {
        $metadata.bounded_slice
    }
    else {
        $null
    }
    $targetFiles = New-Object System.Collections.Generic.List[string]
    foreach ($source in @($Request, $metadata, $boundedSlice)) {
        if ($null -eq $source) {
            continue
        }
        foreach ($propertyName in @('target_file', 'target_files', 'likely_target_files', 'allowed_files', 'files_involved')) {
            if ($source.PSObject.Properties[$propertyName] -and $null -ne $source.$propertyName) {
                foreach ($item in @($source.$propertyName)) {
                    $normalized = ([string]$item).Trim() -replace '[\\/]+', '/'
                    if (-not [string]::IsNullOrWhiteSpace($normalized) -and -not $targetFiles.Contains($normalized)) {
                        $targetFiles.Add($normalized) | Out-Null
                    }
                }
            }
        }
    }
    $targetFileArray = [string[]]@($targetFiles.ToArray())

    $existing = @($state.tasks | Where-Object {
            ([string]$_.id -eq $taskId) -or
            (($_.PSObject.Properties['remote_task_id']) -and ([string]$_.remote_task_id -eq $taskId))
        } | Select-Object -First 1)
    $updatedAt = Get-UtcNowString
    $changed = $false
    $created = $false

    if (@($existing).Count -eq 0) {
        $newTask = [pscustomobject]@{
            id = $taskId
            remote_task_id = $taskId
            objective_id = $requestedObjective
            title = $title
            type = 'programming'
            task_category = 'mim_synced'
            scope = $scope
            dependencies = @($dependencies)
            acceptance_criteria = @($acceptanceCriteria)
            allowed_files = @($targetFileArray)
            files_involved = @($targetFileArray)
            target_files = @($targetFileArray)
            metadata_json = $metadata
            bounded_slice = $boundedSlice
            status = 'planned'
            assigned_executor = 'local'
            source = 'mim_request_sync'
            correlation_id = if ($Request.PSObject.Properties['correlation_id']) { [string]$Request.correlation_id } else { '' }
            priority = $priority
            created_at = $updatedAt
            updated_at = $updatedAt
        }
        $state.tasks = @($state.tasks) + @($newTask)
        $changed = $true
        $created = $true
    }
    else {
        $task = $existing[0]

        if ($task.PSObject.Properties['status'] -and [string]::Equals([string]$task.status, 'completed', [System.StringComparison]::OrdinalIgnoreCase)) {
            return [pscustomobject]@{
                changed = $false
                created = $false
                task_id = $taskId
                objective_id = $requestedObjective
                reason = 'task_completed_ignored'
            }
        }

        if (-not [string]::Equals([string]$task.objective_id, $requestedObjective, [System.StringComparison]::Ordinal)) {
            $task.objective_id = $requestedObjective
            $changed = $true
        }
        if (-not [string]::Equals([string]$task.title, $title, [System.StringComparison]::Ordinal)) {
            $task.title = $title
            $changed = $true
        }
        if (-not [string]::Equals([string]$task.scope, $scope, [System.StringComparison]::Ordinal)) {
            $task.scope = $scope
            $changed = $true
        }
        if (-not $task.PSObject.Properties['remote_task_id'] -or -not [string]::Equals([string]$task.remote_task_id, $taskId, [System.StringComparison]::Ordinal)) {
            $task | Add-Member -NotePropertyName remote_task_id -NotePropertyValue $taskId -Force
            $changed = $true
        }
        if (-not $task.PSObject.Properties['task_category'] -or -not [string]::Equals([string]$task.task_category, 'mim_synced', [System.StringComparison]::Ordinal)) {
            $task | Add-Member -NotePropertyName task_category -NotePropertyValue 'mim_synced' -Force
            $changed = $true
        }
        if (-not $task.PSObject.Properties['source'] -or -not [string]::Equals([string]$task.source, 'mim_request_sync', [System.StringComparison]::Ordinal)) {
            $task | Add-Member -NotePropertyName source -NotePropertyValue 'mim_request_sync' -Force
            $changed = $true
        }
        if (-not $task.PSObject.Properties['correlation_id'] -or -not [string]::Equals([string]$task.correlation_id, $(if ($Request.PSObject.Properties['correlation_id']) { [string]$Request.correlation_id } else { '' }), [System.StringComparison]::Ordinal)) {
            $task | Add-Member -NotePropertyName correlation_id -NotePropertyValue $(if ($Request.PSObject.Properties['correlation_id']) { [string]$Request.correlation_id } else { '' }) -Force
            $changed = $true
        }
        if (-not $task.PSObject.Properties['priority'] -or -not [string]::Equals([string]$task.priority, $priority, [System.StringComparison]::Ordinal)) {
            $task | Add-Member -NotePropertyName priority -NotePropertyValue $priority -Force
            $changed = $true
        }
        $existingAcceptanceCriteria = if ($task.PSObject.Properties['acceptance_criteria']) { @($task.acceptance_criteria) } else { @() }
        if (-not (Test-StringArrayEquivalent -Left @($existingAcceptanceCriteria) -Right @($acceptanceCriteria))) {
            $task.acceptance_criteria = @($acceptanceCriteria)
            $changed = $true
        }
        $existingDependencies = if ($task.PSObject.Properties['dependencies']) { @($task.dependencies) } else { @() }
        if (-not (Test-StringArrayEquivalent -Left @($existingDependencies) -Right @($dependencies))) {
            $task.dependencies = @($dependencies)
            $changed = $true
        }
        $existingAllowedFiles = if ($task.PSObject.Properties['allowed_files']) { @($task.allowed_files) } else { @() }
        if (-not (Test-StringArrayEquivalent -Left @($existingAllowedFiles) -Right @($targetFileArray))) {
            $task | Add-Member -NotePropertyName allowed_files -NotePropertyValue @($targetFileArray) -Force
            $changed = $true
        }
        $existingFilesInvolved = if ($task.PSObject.Properties['files_involved']) { @($task.files_involved) } else { @() }
        if (-not (Test-StringArrayEquivalent -Left @($existingFilesInvolved) -Right @($targetFileArray))) {
            $task | Add-Member -NotePropertyName files_involved -NotePropertyValue @($targetFileArray) -Force
            $changed = $true
        }
        $existingTargetFiles = if ($task.PSObject.Properties['target_files']) { @($task.target_files) } else { @() }
        if (-not (Test-StringArrayEquivalent -Left @($existingTargetFiles) -Right @($targetFileArray))) {
            $task | Add-Member -NotePropertyName target_files -NotePropertyValue @($targetFileArray) -Force
            $changed = $true
        }
        if (-not $task.PSObject.Properties['metadata_json'] -or $null -eq $task.metadata_json) {
            $task | Add-Member -NotePropertyName metadata_json -NotePropertyValue $metadata -Force
            $changed = $true
        }
        if ($null -ne $boundedSlice -and (-not $task.PSObject.Properties['bounded_slice'] -or $null -eq $task.bounded_slice)) {
            $task | Add-Member -NotePropertyName bounded_slice -NotePropertyValue $boundedSlice -Force
            $changed = $true
        }
        if ($changed) {
            if ($task.PSObject.Properties['updated_at']) {
                $task.updated_at = $updatedAt
            }
            else {
                $task | Add-Member -NotePropertyName updated_at -NotePropertyValue $updatedAt -Force
            }
        }
    }

    if ($changed) {
        Write-JsonFile -PathValue $statePath -Payload $state -Depth 100
    }

    return [pscustomobject]@{
        changed = $changed
        created = $created
        task_id = $taskId
        objective_id = $requestedObjective
        reason = if ($created) { 'task_upserted_created' } elseif ($changed) { 'task_upserted_updated' } else { 'already_current' }
    }
}

function Sync-LocalTaskMirror {
    param(
        [Parameter(Mandatory = $true)][string]$TaskId,
        [string]$ObjectiveId,
        [string]$Title,
        [string]$Scope,
        [string]$Status = 'in_progress',
        [string]$TaskCategory = 'bridge_runtime',
        [string]$Source = 'bridge_runtime_sync',
        [string]$CorrelationId = ''
    )

    if ([string]::IsNullOrWhiteSpace($TaskId)) {
        return [pscustomobject]@{ changed = $false; created = $false; task_id = ''; objective_id = ''; reason = 'task_missing' }
    }

    $resolvedObjectiveId = if (-not [string]::IsNullOrWhiteSpace($ObjectiveId)) { [string]$ObjectiveId } else { (Get-ExpectedObjectiveFromRequest -Request ([pscustomobject]@{ task_id = $TaskId })) }
    if ([string]::IsNullOrWhiteSpace($resolvedObjectiveId)) {
        return [pscustomobject]@{ changed = $false; created = $false; task_id = $TaskId; objective_id = ''; reason = 'objective_missing' }
    }

    $statePath = Get-LocalPath -PathValue 'tod/data/state.json'
    $state = Read-JsonFileIfExists -PathValue $statePath
    if ($null -eq $state) {
        return [pscustomobject]@{ changed = $false; created = $false; task_id = $TaskId; objective_id = $resolvedObjectiveId; reason = 'state_unavailable' }
    }

    if (-not $state.PSObject.Properties['tasks']) {
        $state | Add-Member -NotePropertyName tasks -NotePropertyValue @() -Force
    }

    $resolvedTitle = if ([string]::IsNullOrWhiteSpace($Title)) { "Bridge task $TaskId" } else { $Title }
    $resolvedScope = if ([string]::IsNullOrWhiteSpace($Scope)) { "Synchronized from listener bridge runtime." } else { $Scope }
    $updatedAt = Get-UtcNowString
    $changed = $false
    $created = $false

    $existing = @($state.tasks | Where-Object {
            ([string]$_.id -eq $TaskId) -or
            (($_.PSObject.Properties['remote_task_id']) -and ([string]$_.remote_task_id -eq $TaskId))
        } | Select-Object -First 1)

    if (@($existing).Count -eq 0) {
        $task = [pscustomobject]@{
            id = $TaskId
            remote_task_id = $TaskId
            objective_id = $resolvedObjectiveId
            title = $resolvedTitle
            type = 'programming'
            task_category = $TaskCategory
            scope = $resolvedScope
            dependencies = @()
            acceptance_criteria = @()
            status = $Status
            assigned_executor = 'local'
            source = $Source
            correlation_id = $CorrelationId
            created_at = $updatedAt
            updated_at = $updatedAt
        }
        $state.tasks = @($state.tasks) + @($task)
        $changed = $true
        $created = $true
    }
    else {
        $task = $existing[0]
        if (-not [string]::Equals([string]$task.objective_id, $resolvedObjectiveId, [System.StringComparison]::Ordinal)) {
            $task.objective_id = $resolvedObjectiveId
            $changed = $true
        }
        if (-not [string]::Equals([string]$task.title, $resolvedTitle, [System.StringComparison]::Ordinal)) {
            $task.title = $resolvedTitle
            $changed = $true
        }
        if (-not [string]::Equals([string]$task.scope, $resolvedScope, [System.StringComparison]::Ordinal)) {
            $task.scope = $resolvedScope
            $changed = $true
        }
        if (-not [string]::Equals([string]$task.status, $Status, [System.StringComparison]::OrdinalIgnoreCase)) {
            $task.status = $Status
            $changed = $true
        }
        if (-not $task.PSObject.Properties['remote_task_id'] -or -not [string]::Equals([string]$task.remote_task_id, $TaskId, [System.StringComparison]::Ordinal)) {
            $task | Add-Member -NotePropertyName remote_task_id -NotePropertyValue $TaskId -Force
            $changed = $true
        }
        if (-not $task.PSObject.Properties['task_category'] -or -not [string]::Equals([string]$task.task_category, $TaskCategory, [System.StringComparison]::Ordinal)) {
            $task | Add-Member -NotePropertyName task_category -NotePropertyValue $TaskCategory -Force
            $changed = $true
        }
        if (-not $task.PSObject.Properties['source'] -or -not [string]::Equals([string]$task.source, $Source, [System.StringComparison]::Ordinal)) {
            $task | Add-Member -NotePropertyName source -NotePropertyValue $Source -Force
            $changed = $true
        }
        if (-not $task.PSObject.Properties['correlation_id'] -or -not [string]::Equals([string]$task.correlation_id, $CorrelationId, [System.StringComparison]::Ordinal)) {
            $task | Add-Member -NotePropertyName correlation_id -NotePropertyValue $CorrelationId -Force
            $changed = $true
        }
        if ($changed) {
            $task.updated_at = $updatedAt
        }
    }

    if ($changed) {
        Write-JsonFile -PathValue $statePath -Payload $state -Depth 100
    }

    return [pscustomobject]@{
        changed = $changed
        created = $created
        task_id = $TaskId
        objective_id = $resolvedObjectiveId
        reason = if ($created) { 'task_mirror_created' } elseif ($changed) { 'task_mirror_updated' } else { 'already_current' }
    }
}

function Sync-LocalExecutionOutcome {
    param(
        [string]$TaskId,
        [string]$ObjectiveId,
        [AllowNull()]$ResultPacket = $null
    )

    if ([string]::IsNullOrWhiteSpace($TaskId) -or $null -eq $ResultPacket) {
        return [pscustomobject]@{ changed = $false; task_changed = $false; objective_changed = $false; reason = 'missing_input' }
    }

    $resultStatusRaw = if ($ResultPacket.PSObject.Properties['status']) { [string]$ResultPacket.status } else { '' }
    $resultStatus = $resultStatusRaw.Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($resultStatus)) {
        return [pscustomobject]@{ changed = $false; task_changed = $false; objective_changed = $false; reason = 'result_status_missing' }
    }

    $resolvedObjectiveId = if (-not [string]::IsNullOrWhiteSpace($ObjectiveId)) {
        [string]$ObjectiveId
    }
    elseif ($ResultPacket.PSObject.Properties['objective_id'] -and -not [string]::IsNullOrWhiteSpace([string]$ResultPacket.objective_id)) {
        [string]$ResultPacket.objective_id
    }
    else {
        ''
    }

    $statePath = Get-LocalPath -PathValue 'tod/data/state.json'
    $state = Read-JsonFileIfExists -PathValue $statePath
    if ($null -eq $state) {
        return [pscustomobject]@{ changed = $false; task_changed = $false; objective_changed = $false; reason = 'state_unavailable' }
    }

    if (-not $state.PSObject.Properties['tasks']) {
        $state | Add-Member -NotePropertyName tasks -NotePropertyValue @() -Force
    }
    if (-not $state.PSObject.Properties['objectives']) {
        $state | Add-Member -NotePropertyName objectives -NotePropertyValue @() -Force
    }

    $mappedTaskStatus = switch ($resultStatus) {
        'completed' { 'completed' }
        'succeeded' { 'completed' }
        'failed' { 'failed' }
        'blocked' { 'blocked' }
        'timed_out' { 'failed' }
        'aborted' { 'failed' }
        'already_processed' { 'completed' }
        'stale_request_ignored' { 'completed' }
        default { '' }
    }

    $updatedAt = Get-UtcNowString
    $taskChanged = $false
    $objectiveChanged = $false

    if (-not [string]::IsNullOrWhiteSpace($mappedTaskStatus)) {
        foreach ($task in @($state.tasks | Where-Object {
                    ([string]$_.id -eq $TaskId) -or
                    (($_.PSObject.Properties['remote_task_id']) -and ([string]$_.remote_task_id -eq $TaskId))
                })) {
            if (-not [string]::Equals([string]$task.status, $mappedTaskStatus, [System.StringComparison]::OrdinalIgnoreCase)) {
                $task.status = $mappedTaskStatus
                $taskChanged = $true
            }

            if ($taskChanged) {
                $task.updated_at = $updatedAt
            }
        }
    }

    if (([string]::Equals($resultStatus, 'completed', [System.StringComparison]::OrdinalIgnoreCase) -or [string]::Equals($resultStatus, 'succeeded', [System.StringComparison]::OrdinalIgnoreCase)) -and -not [string]::IsNullOrWhiteSpace($resolvedObjectiveId)) {
        foreach ($objective in @($state.objectives | Where-Object { [string]$_.id -eq $resolvedObjectiveId })) {
            if (-not [string]::Equals([string]$objective.status, 'completed', [System.StringComparison]::OrdinalIgnoreCase)) {
                $objective.status = 'completed'
                $objectiveChanged = $true
            }

            if (-not $objective.PSObject.Properties['completed_at'] -or [string]::IsNullOrWhiteSpace([string]$objective.completed_at)) {
                $objective | Add-Member -NotePropertyName completed_at -NotePropertyValue $updatedAt -Force
                $objectiveChanged = $true
            }

            if ($objectiveChanged) {
                $objective.updated_at = $updatedAt
            }
        }
    }

    if ($taskChanged -or $objectiveChanged) {
        Write-JsonFile -PathValue $statePath -Payload $state -Depth 100
    }

    return [pscustomobject]@{
        changed = ($taskChanged -or $objectiveChanged)
        task_changed = $taskChanged
        objective_changed = $objectiveChanged
        reason = if ($taskChanged -or $objectiveChanged) { 'execution_outcome_synced' } else { 'already_current' }
    }
}

function New-SshConnections {
    param(
        [Parameter(Mandatory = $true)][string]$HostAlias,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][int]$Port,
        [Parameter(Mandatory = $true)][string]$Password
    )

    if (-not (Get-Module -ListAvailable -Name Posh-SSH)) {
        throw "Posh-SSH is not installed. Install-Module -Name Posh-SSH -Scope CurrentUser"
    }
    Import-Module Posh-SSH -ErrorAction Stop | Out-Null

    $resolvedHost = Resolve-SshHostAlias -RemoteHost $HostAlias
    $securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential ($UserName, $securePassword)

    $sshSession = New-SSHSession -ComputerName $resolvedHost -Port $Port -Credential $credential -AcceptKey -ConnectionTimeout 15000
    $sftpSession = New-SFTPSession -ComputerName $resolvedHost -Port $Port -Credential $credential -AcceptKey -ConnectionTimeout 15000

    return [pscustomobject]@{
        host_alias = $HostAlias
        resolved_host = $resolvedHost
        ssh = $sshSession
        sftp = $sftpSession
    }
}

function Close-SshConnections {
    param($Connections)

    if ($null -eq $Connections) { return }

    try {
        if ($Connections.sftp) {
            Remove-SFTPSession -SessionId ([int]$Connections.sftp.SessionId) | Out-Null
        }
    }
    catch {
    }

    try {
        if ($Connections.ssh) {
            Remove-SSHSession -SessionId ([int]$Connections.ssh.SessionId) | Out-Null
        }
    }
    catch {
    }
}

function Download-RemoteFile {
    param(
        [Parameter(Mandatory = $true)]$Connections,
        [Parameter(Mandatory = $true)][string]$RemotePath,
        [Parameter(Mandatory = $true)][string]$LocalPath,
        [switch]$Required
    )

    try {
        $destinationDir = Split-Path -Parent $LocalPath
        if (-not [string]::IsNullOrWhiteSpace($destinationDir) -and -not (Test-Path -Path $destinationDir)) {
            New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
        }

        Get-SFTPItem -SessionId ([int]$Connections.sftp.SessionId) -Path $RemotePath -Destination $destinationDir -Force -ErrorAction Stop | Out-Null
        return (Test-Path -Path $LocalPath -PathType Leaf)
    }
    catch {
        if ($Required) {
            throw
        }
        return $false
    }
}

function Upload-LocalFile {
    param(
        [Parameter(Mandatory = $true)]$Connections,
        [Parameter(Mandatory = $true)][string]$LocalPath,
        [Parameter(Mandatory = $true)][string]$RemoteDir
    )

    Set-SFTPItem -SessionId ([int]$Connections.sftp.SessionId) -Path $LocalPath -Destination $RemoteDir -Force -ErrorAction Stop | Out-Null
}

function Write-RemoteFileFromText {
    param(
        [Parameter(Mandatory = $true)]$Connections,
        [Parameter(Mandatory = $true)][string]$RemotePath,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $remoteDir = [string](Split-Path -Path $RemotePath -Parent)
    $remoteDir = $remoteDir -replace "\\", "/"
    $remoteName = [string](Split-Path -Path $RemotePath -Leaf)
    if ([string]::IsNullOrWhiteSpace($remoteDir) -or [string]::IsNullOrWhiteSpace($remoteName)) {
        throw "Invalid remote path: $RemotePath"
    }

    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "tod-mim-listener"
    if (-not (Test-Path -Path $tempDir)) {
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    }

    $tempPath = Join-Path $tempDir $remoteName
    try {
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        $normalizedContent = ([string]$Content) -replace "`r`n", "`n"
        [System.IO.File]::WriteAllText($tempPath, $normalizedContent, $utf8NoBom)
        Set-SFTPItem -SessionId ([int]$Connections.sftp.SessionId) -Path $tempPath -Destination $remoteDir -Force -ErrorAction Stop | Out-Null
    }
    finally {
        if (Test-Path -Path $tempPath) {
            Remove-Item -Path $tempPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Publish-TriggerAck {
    param(
        [Parameter(Mandatory = $true)]$ListenerState,
        [Parameter(Mandatory = $true)][string]$ListenerStatePath,
        [Parameter(Mandatory = $true)]$Connections,
        [Parameter(Mandatory = $true)][string]$LocalPath,
        [Parameter(Mandatory = $true)][string]$RemotePath,
        [Parameter(Mandatory = $true)][string]$RequestId,
        [string]$CurrentTaskId = "",
        [string]$CurrentCorrelationId = "",
        [AllowNull()]$TriggerPacket = $null,
        [AllowNull()]$BridgeRuntime = $null
    )

    $triggerContext = Get-TriggerContext -TriggerPacket $TriggerPacket

    $triggerAck = [pscustomobject]@{
        generated_at = (Get-Date).ToUniversalTime().ToString("o")
        source = "shared-trigger-ack-v1"
        status = "acknowledged"
        acknowledges = $RequestId
        current_task_id = $CurrentTaskId
        current_correlation_id = $CurrentCorrelationId
    }
    if ($null -ne $triggerContext) {
        $triggerAck | Add-Member -NotePropertyName trigger_context -NotePropertyValue $triggerContext -Force
        $triggerAck | Add-Member -NotePropertyName triggered_artifact -NotePropertyValue ([string]$triggerContext.artifact) -Force
        $triggerAck | Add-Member -NotePropertyName trigger_type -NotePropertyValue ([string]$triggerContext.trigger) -Force
        $triggerAck | Add-Member -NotePropertyName trigger_packet_type -NotePropertyValue ([string]$triggerContext.packet_type) -Force
        $triggerAck | Add-Member -NotePropertyName action_required -NotePropertyValue ([string]$triggerContext.action_required) -Force
    }
    $null = Add-SequenceRuntimeFields -Packet $triggerAck -TriggerPacket $TriggerPacket -ListenerState $ListenerState -ListenerStatePath $ListenerStatePath
    if ($null -ne $BridgeRuntime) {
        $triggerAck | Add-Member -NotePropertyName bridge_runtime -NotePropertyValue $BridgeRuntime -Force
    }
    Write-JsonFile -PathValue $LocalPath -Payload $triggerAck
    $triggerAckJson = Get-Content -Path $LocalPath -Raw
    Write-RemoteFileFromText -Connections $Connections -RemotePath $RemotePath -Content $triggerAckJson
}

function Get-ListenerExecutionFeedbackConfig {
    $defaultConfig = [pscustomobject]@{
        mim_base_url = ''
        auth_token = ''
    }

    $configPath = Join-Path $repoRoot 'tod/config/tod-config.json'
    if (-not (Test-Path -Path $configPath)) {
        return $defaultConfig
    }

    try {
        $config = ConvertFrom-JsonCaseInsensitiveSafe -Text (Get-Content -Path $configPath -Raw)
        $baseUrl = if ($config.PSObject.Properties['mim_base_url']) { [string]$config.mim_base_url } else { '' }
        $authToken = ''
        if ($config.PSObject.Properties['execution_feedback'] -and $null -ne $config.execution_feedback -and $config.execution_feedback.PSObject.Properties['auth_token']) {
            $authToken = [string]$config.execution_feedback.auth_token
        }

        return [pscustomobject]@{
            mim_base_url = $baseUrl
            auth_token = $authToken
        }
    }
    catch {
        return $defaultConfig
    }
}

function Get-RequestExecutionId {
    param([Parameter(Mandatory = $true)]$Request)

    if ($Request.PSObject.Properties['execution_id'] -and -not [string]::IsNullOrWhiteSpace([string]$Request.execution_id)) {
        return [string]$Request.execution_id
    }
    if ($Request.PSObject.Properties['remote_execution_id'] -and -not [string]::IsNullOrWhiteSpace([string]$Request.remote_execution_id)) {
        return [string]$Request.remote_execution_id
    }

    return ''
}

function Get-RequestTextField {
    param(
        [AllowNull()]$Source,
        [Parameter(Mandatory = $true)][string[]]$Names
    )

    if ($null -eq $Source) {
        return ''
    }

    foreach ($name in $Names) {
        if ($Source.PSObject.Properties[$name] -and $null -ne $Source.$name -and -not [string]::IsNullOrWhiteSpace([string]$Source.$name)) {
            return [string]$Source.$name
        }
    }

    return ''
}

function Get-RequestStringArrayField {
    param(
        [AllowNull()]$Source,
        [Parameter(Mandatory = $true)][string[]]$Names
    )

    $items = New-Object System.Collections.Generic.List[string]
    if ($null -eq $Source) {
        return [string[]]@()
    }

    foreach ($name in $Names) {
        if (-not $Source.PSObject.Properties[$name] -or $null -eq $Source.$name) {
            continue
        }
        foreach ($item in @($Source.$name)) {
            $value = ([string]$item).Trim()
            if (-not [string]::IsNullOrWhiteSpace($value) -and -not $items.Contains($value)) {
                $items.Add($value) | Out-Null
            }
        }
    }

    return [string[]]@($items.ToArray())
}

function Resolve-RequestExecutionScope {
    param([Parameter(Mandatory = $true)]$Request)

    $metadata = if ($Request.PSObject.Properties['metadata_json'] -and $null -ne $Request.metadata_json) { $Request.metadata_json } else { $null }
    $boundedSlice = if ($Request.PSObject.Properties['bounded_slice'] -and $null -ne $Request.bounded_slice) {
        $Request.bounded_slice
    }
    elseif ($metadata -and $metadata.PSObject.Properties['bounded_slice'] -and $null -ne $metadata.bounded_slice) {
        $metadata.bounded_slice
    }
    else {
        $null
    }

    foreach ($source in @($Request, $metadata, $boundedSlice)) {
        $directScope = Get-RequestTextField -Source $source -Names @('scope', 'description', 'task', 'requested_outcome', 'content')
        if (-not [string]::IsNullOrWhiteSpace($directScope)) {
            return $directScope
        }
    }

    $lines = New-Object System.Collections.Generic.List[string]
    $boundedChange = Get-RequestTextField -Source $Request -Names @('bounded_change')
    if ([string]::IsNullOrWhiteSpace($boundedChange)) {
        $boundedChange = Get-RequestTextField -Source $boundedSlice -Names @('bounded_change', 'minimal_edit_scope', 'edit_shape_summary')
    }
    if (-not [string]::IsNullOrWhiteSpace($boundedChange)) {
        $lines.Add(('Bounded Change: {0}' -f $boundedChange)) | Out-Null
    }

    $targetComponent = Get-RequestTextField -Source $Request -Names @('target_component', 'discovery_scope')
    if ([string]::IsNullOrWhiteSpace($targetComponent)) {
        $targetComponent = Get-RequestTextField -Source $boundedSlice -Names @('target_component', 'discovery_scope')
    }
    if (-not [string]::IsNullOrWhiteSpace($targetComponent)) {
        $lines.Add(('Target Component: {0}' -f $targetComponent)) | Out-Null
    }

    $targetFiles = New-Object System.Collections.Generic.List[string]
    foreach ($source in @($Request, $metadata, $boundedSlice)) {
        foreach ($item in @(Get-RequestStringArrayField -Source $source -Names @('target_file', 'target_files', 'likely_target_files', 'files_involved', 'files_to_inspect_first'))) {
            $normalized = ([string]$item).Trim() -replace '[\\/]+', '/'
            if (-not [string]::IsNullOrWhiteSpace($normalized) -and -not $targetFiles.Contains($normalized)) {
                $targetFiles.Add($normalized) | Out-Null
            }
        }
    }
    if ($targetFiles.Count -gt 0) {
        $lines.Add(('Target Files: {0}' -f (@($targetFiles.ToArray()) -join ', '))) | Out-Null
    }

    $validationCommand = Get-RequestTextField -Source $Request -Names @('validation_command')
    if ([string]::IsNullOrWhiteSpace($validationCommand)) {
        $validationCommand = Get-RequestTextField -Source $boundedSlice -Names @('validation_command')
    }
    if (-not [string]::IsNullOrWhiteSpace($validationCommand)) {
        $lines.Add(('Validation Command: {0}' -f $validationCommand)) | Out-Null
    }

    $requiredEvidence = @(Get-RequestStringArrayField -Source $Request -Names @('required_evidence', 'expected_evidence'))
    if (@($requiredEvidence).Count -eq 0) {
        $requiredEvidence = @(Get-RequestStringArrayField -Source $boundedSlice -Names @('required_evidence', 'expected_evidence'))
    }
    if (@($requiredEvidence).Count -gt 0) {
        $lines.Add(('Required Evidence: {0}' -f (@($requiredEvidence) -join '; '))) | Out-Null
    }

    if ($lines.Count -gt 0) {
        return @($lines.ToArray()) -join "`n"
    }

    return ''
}

function Resolve-ExecutionFeedbackEndpoint {
    param([Parameter(Mandatory = $true)]$Request)

    $feedbackEndpoint = if ($Request.PSObject.Properties['feedback_endpoint']) { [string]$Request.feedback_endpoint } else { '' }
    if ([string]::IsNullOrWhiteSpace($feedbackEndpoint)) {
        return ''
    }

    if ([System.Uri]::IsWellFormedUriString($feedbackEndpoint, [System.UriKind]::Absolute)) {
        return $feedbackEndpoint
    }

    $config = Get-ListenerExecutionFeedbackConfig
    $baseUrl = ([string]$config.mim_base_url).Trim()
    if ([string]::IsNullOrWhiteSpace($baseUrl)) {
        return ''
    }

    try {
        $baseUri = [System.Uri]$baseUrl
        $resolvedUri = [System.Uri]::new($baseUri, $feedbackEndpoint)
        return $resolvedUri.AbsoluteUri
    }
    catch {
        return ''
    }
}

function Publish-ExecutionFeedbackFromRequest {
    param(
        [Parameter(Mandatory = $true)]$Request,
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $true)][string]$TaskId,
        [string]$HostReceivedTimestamp = '',
        [string]$HostCompletedTimestamp = '',
        [string]$ResultReasonCode = '',
        [string]$ExecutionMode = '',
        [string]$FailureCategory = '',
        [string]$ErrorDetail = '',
        [bool]$GuardrailBlocked = $false,
        [bool]$Recovered = $false,
        [bool]$UnrecoveredFailure = $false,
        [bool]$ReviewGatePassed = $true,
        [bool]$ValidatorPassed = $true
    )

    $executionId = Get-RequestExecutionId -Request $Request
    if ([string]::IsNullOrWhiteSpace($executionId)) {
        return [pscustomobject]@{ attempted = $false; published = $false; reason = 'missing_execution_id' }
    }

    $feedbackUri = Resolve-ExecutionFeedbackEndpoint -Request $Request
    if ([string]::IsNullOrWhiteSpace($feedbackUri)) {
        return [pscustomobject]@{ attempted = $true; published = $false; reason = 'missing_feedback_endpoint'; execution_id = $executionId }
    }

    $details = [ordered]@{
        task_id = $TaskId
        result_reason_code = $ResultReasonCode
        execution_mode = $ExecutionMode
        failure_category = $FailureCategory
        error_detail = $ErrorDetail
        guardrail_blocked = [bool]$GuardrailBlocked
        recovered = [bool]$Recovered
        unrecovered_failure = [bool]$UnrecoveredFailure
        review_gate_passed = [bool]$ReviewGatePassed
        validator_passed = [bool]$ValidatorPassed
        host_received_timestamp = $HostReceivedTimestamp
        host_completed_timestamp = $HostCompletedTimestamp
        executor_timestamps = [ordered]@{
            host_received_timestamp = $HostReceivedTimestamp
            host_completed_timestamp = $HostCompletedTimestamp
        }
    }

    $payload = [ordered]@{
        status = $Status
        details = $details
    }
    $headers = @{}
    $config = Get-ListenerExecutionFeedbackConfig
    if (-not [string]::IsNullOrWhiteSpace([string]$config.auth_token)) {
        $headers['Authorization'] = ("Bearer {0}" -f [string]$config.auth_token)
    }

    try {
        Invoke-RestMethod -Uri $feedbackUri -Method Post -ContentType 'application/json' -Headers $headers -Body ($payload | ConvertTo-Json -Depth 12) | Out-Null
        return [pscustomobject]@{ attempted = $true; published = $true; reason = ''; execution_id = $executionId; endpoint = $feedbackUri }
    }
    catch {
        return [pscustomobject]@{ attempted = $true; published = $false; reason = $_.Exception.Message; execution_id = $executionId; endpoint = $feedbackUri }
    }
}

function Invoke-RequestExecution {
    param(
        [Parameter(Mandatory = $true)][string]$TodScriptAbs,
        [Parameter(Mandatory = $true)]$Request
    )

    $action = "get-state-bus"
    if ($Request.PSObject.Properties["tod_action"] -and -not [string]::IsNullOrWhiteSpace([string]$Request.tod_action)) {
        $action = [string]$Request.tod_action
    }
    elseif ($Request.PSObject.Properties["action"] -and -not [string]::IsNullOrWhiteSpace([string]$Request.action)) {
        $action = [string]$Request.action
    }
    elseif ($Request.PSObject.Properties["action_name"] -and -not [string]::IsNullOrWhiteSpace([string]$Request.action_name)) {
        $action = [string]$Request.action_name
    }

    $top = 10
    if ($Request.PSObject.Properties["top"] -and $null -ne $Request.top) {
        try { $top = [int]$Request.top } catch { $top = 10 }
    }

    $startUtc = (Get-Date).ToUniversalTime().ToString("o")
    $readinessTrace = Get-ExecutionReadinessTrace -TodScriptAbs $TodScriptAbs -Action $action

    # For get-state-bus: always return lightweight; TOD state.json is too large
    # to deserialize safely in-process. Any action that would load the full state
    # file is blocked here to protect listener memory.
    if ([string]::Equals($action, "get-state-bus", [System.StringComparison]::OrdinalIgnoreCase)) {
        $endUtc = (Get-Date).ToUniversalTime().ToString("o")
        $sizeMiB = ""
        try {
            $sf = Get-Item -Path (Join-Path (Split-Path -Parent $PSScriptRoot) "tod/data/state.json") -ErrorAction Stop
            $sizeMiB = [math]::Round(($sf.Length / 1MB), 2)
        } catch {}
        return [pscustomobject]@{
            ok = $true
            action = $action
            execution_mode = "lightweight_guard"
            started_at = $startUtc
            completed_at = $endUtc
            execution_readiness = $readinessTrace
            execution_trace = if ($null -ne $readinessTrace) { [pscustomobject]@{ action = $action; execution_readiness = $readinessTrace } } else { $null }
            output = ("get-state-bus: lightweight success (in-process state read bypassed{0})" -f $(if ($sizeMiB) { "; state.json={0} MiB" -f $sizeMiB } else { "" }))
            error = ""
        }
    }

    if ($null -ne $readinessTrace -and [string]::Equals([string]$readinessTrace.policy_outcome, "block", [System.StringComparison]::OrdinalIgnoreCase)) {
        $endUtc = (Get-Date).ToUniversalTime().ToString("o")
        return [pscustomobject]@{
            ok = $false
            blocked = $true
            action = $action
            execution_mode = "readiness_blocked"
            started_at = $startUtc
            completed_at = $endUtc
            execution_readiness = $readinessTrace
            execution_trace = [pscustomobject]@{ action = $action; execution_readiness = $readinessTrace }
            output = ""
            error = ("Execution blocked by readiness policy: status={0}; source={1}" -f [string]$readinessTrace.status, [string]$readinessTrace.source)
        }
    }

    $todArgs = @{
        Action = $action
        Top = $top
    }
    if ($Request.PSObject.Properties["task_id"] -and -not [string]::IsNullOrWhiteSpace([string]$Request.task_id)) {
        $todArgs["TaskId"] = [string]$Request.task_id
    }
    if ($Request.PSObject.Properties["objective_id"] -and -not [string]::IsNullOrWhiteSpace([string]$Request.objective_id)) {
        $todArgs["ObjectiveId"] = [string]$Request.objective_id
    }
    if ($Request.PSObject.Properties["content"] -and -not [string]::IsNullOrWhiteSpace([string]$Request.content)) {
        $todArgs["Content"] = [string]$Request.content
    }
    if ($Request.PSObject.Properties["title"] -and -not [string]::IsNullOrWhiteSpace([string]$Request.title)) {
        $todArgs["Title"] = [string]$Request.title
    }
    if ($Request.PSObject.Properties["description"] -and -not [string]::IsNullOrWhiteSpace([string]$Request.description)) {
        $todArgs["Description"] = [string]$Request.description
    }
    if ($Request.PSObject.Properties["priority"] -and -not [string]::IsNullOrWhiteSpace([string]$Request.priority)) {
        $todArgs["Priority"] = [string]$Request.priority
    }
    $resolvedScope = Resolve-RequestExecutionScope -Request $Request
    if (-not [string]::IsNullOrWhiteSpace($resolvedScope)) {
        $todArgs["Scope"] = $resolvedScope
    }
    if ($Request.PSObject.Properties["acceptance_criteria"] -and -not [string]::IsNullOrWhiteSpace([string]$Request.acceptance_criteria)) {
        $todArgs["AcceptanceCriteria"] = [string]$Request.acceptance_criteria
    }
    if ($Request.PSObject.Properties["success_criteria"] -and -not [string]::IsNullOrWhiteSpace([string]$Request.success_criteria)) {
        $todArgs["SuccessCriteria"] = [string]$Request.success_criteria
    }
    if ($Request.PSObject.Properties["assigned_executor"] -and -not [string]::IsNullOrWhiteSpace([string]$Request.assigned_executor)) {
        $todArgs["AssignedExecutor"] = [string]$Request.assigned_executor
    }
    if ($Request.PSObject.Properties["task_category"] -and -not [string]::IsNullOrWhiteSpace([string]$Request.task_category)) {
        $todArgs["TaskCategory"] = [string]$Request.task_category
    }
    $metadata = if ($Request.PSObject.Properties["metadata_json"]) { $Request.metadata_json } else { $null }
    $targetFile = ""
    if ($Request.PSObject.Properties["target_file"] -and -not [string]::IsNullOrWhiteSpace([string]$Request.target_file)) {
        $targetFile = [string]$Request.target_file
    }
    elseif ($metadata -and $metadata.PSObject.Properties["target_file"] -and -not [string]::IsNullOrWhiteSpace([string]$metadata.target_file)) {
        $targetFile = [string]$metadata.target_file
    }
    elseif ($Request.PSObject.Properties["target_files"] -and $null -ne $Request.target_files -and @($Request.target_files).Count -eq 1) {
        $targetFile = [string]@($Request.target_files)[0]
    }
    elseif ($metadata -and $metadata.PSObject.Properties["target_files"] -and $null -ne $metadata.target_files -and @($metadata.target_files).Count -eq 1) {
        $targetFile = [string]@($metadata.target_files)[0]
    }
    if (-not [string]::IsNullOrWhiteSpace($targetFile)) {
        $todArgs["TargetFile"] = $targetFile
    }
    if ($Request.PSObject.Properties["apply_plan"] -and [bool]$Request.apply_plan) {
        $todArgs["ApplyPlan"] = $true
    }
    if ([string]::Equals($action, "run-bridge-request", [System.StringComparison]::OrdinalIgnoreCase)) {
        $bridgeRequestId = ""
        if ($Request.PSObject.Properties["request_id"] -and -not [string]::IsNullOrWhiteSpace([string]$Request.request_id)) {
            $bridgeRequestId = [string]$Request.request_id
        }
        elseif ($Request.PSObject.Properties["task_id"] -and -not [string]::IsNullOrWhiteSpace([string]$Request.task_id)) {
            $bridgeRequestId = [string]$Request.task_id
        }

        if (-not [string]::IsNullOrWhiteSpace($bridgeRequestId)) {
            $todArgs["RequestId"] = $bridgeRequestId
        }
    }

    try {
        $raw = & $TodScriptAbs @todArgs 2>&1
        $endUtc = (Get-Date).ToUniversalTime().ToString("o")
        $payload = $null
        try {
            $payload = ($raw | ConvertFrom-Json)
        }
        catch {
            $payload = $null
        }

        $payloadReadiness = if ($null -ne $payload -and $payload.PSObject.Properties["execution_readiness"]) { $payload.execution_readiness } else { $readinessTrace }
        $payloadTrace = if ($null -ne $payload -and $payload.PSObject.Properties["execution_trace"]) { $payload.execution_trace } elseif ($null -ne $payloadReadiness) { [pscustomobject]@{ action = $action; execution_readiness = $payloadReadiness } } else { $null }
        $payloadBlocker = Get-ExecutionPayloadBlocker -Payload $payload

        return [pscustomobject]@{
            ok = $true
            blocked = [bool]$payloadBlocker.blocked
            action = $action
            execution_mode = "direct_script_success"
            started_at = $startUtc
            completed_at = $endUtc
            execution_readiness = $payloadReadiness
            execution_trace = $payloadTrace
            payload_blocker = $payloadBlocker
            payload = $payload
            output = [string]($raw | Out-String)
            error = $(if ([bool]$payloadBlocker.blocked -and -not [string]::IsNullOrWhiteSpace([string]$payloadBlocker.summary)) { [string]$payloadBlocker.summary } else { "" })
        }
    }
    catch {
        $endUtc = (Get-Date).ToUniversalTime().ToString("o")
        return [pscustomobject]@{
            ok = $false
            blocked = $false
            action = $action
            execution_mode = "direct_script_exception"
            started_at = $startUtc
            completed_at = $endUtc
            execution_readiness = $readinessTrace
            execution_trace = if ($null -ne $readinessTrace) { [pscustomobject]@{ action = $action; execution_readiness = $readinessTrace } } else { $null }
            output = ""
            error = [string]$_.Exception.Message
        }
    }
}

function Test-AlignmentEquivalent {
    param(
        [string]$Actual,
        [string]$Expected
    )

    $actualNorm = ([string]$Actual).Trim().ToLowerInvariant()
    $expectedNorm = ([string]$Expected).Trim().ToLowerInvariant()

    if ([string]::IsNullOrWhiteSpace($expectedNorm)) {
        return $true
    }

    if ($actualNorm -eq $expectedNorm) {
        return $true
    }

    if ($expectedNorm -eq "aligned" -and @("aligned", "in_sync") -contains $actualNorm) {
        return $true
    }

    return $false
}

function Get-ExpectedObjectiveFromRequest {
    param($Request)

    if ($null -eq $Request) {
        return ""
    }

    if ($Request.PSObject.Properties["objective_id"] -and -not [string]::IsNullOrWhiteSpace([string]$Request.objective_id)) {
        $objectiveText = ([string]$Request.objective_id).Trim()
        $numericObjective = [regex]::Match($objectiveText, '(?i)(?:^objective-(?<objective>\d+)$|^(?<objective>\d+)$)')
        if ($numericObjective.Success) {
            return [string]$numericObjective.Groups['objective'].Value
        }
        return $objectiveText
    }

    if ($Request.PSObject.Properties["task_id"] -and -not [string]::IsNullOrWhiteSpace([string]$Request.task_id)) {
        $match = [regex]::Match([string]$Request.task_id, '^objective-(?<objective>\d+)-task-.+$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($match.Success) {
            return [string]$match.Groups['objective'].Value
        }
    }

    return ""
}

function Get-ReviewGateResult {
    param(
        $IntegrationStatus,
        $GoOrder,
        $Request,
        [string]$RequestId
    )

    $expectedCompatible = $true
    $expectedAlignment = "aligned"
    $expectedObjective = Get-ExpectedObjectiveFromRequest -Request $Request
    $expectedTod = $expectedObjective
    $expectedMim = $expectedObjective

    if ($GoOrder -and $GoOrder.PSObject.Properties["success_gate"] -and $null -ne $GoOrder.success_gate) {
        $gate = $GoOrder.success_gate
        if ($gate.PSObject.Properties["compatible"]) { $expectedCompatible = [bool]$gate.compatible }
        if ($gate.PSObject.Properties["objective_alignment_status"]) { $expectedAlignment = [string]$gate.objective_alignment_status }
        if ($gate.PSObject.Properties["tod_current_objective"]) { $expectedTod = [string]$gate.tod_current_objective }
        if ($gate.PSObject.Properties["mim_objective_active"]) { $expectedMim = [string]$gate.mim_objective_active }
    }

    $actualCompatible = if ($IntegrationStatus) { [bool]$IntegrationStatus.compatible } else { $false }
    $actualAlignment = if ($IntegrationStatus) { [string]$IntegrationStatus.objective_alignment.status } else { "" }
    $actualTod = if ($IntegrationStatus) { [string]$IntegrationStatus.objective_alignment.tod_current_objective } else { "" }
    $actualMim = if ($IntegrationStatus) { [string]$IntegrationStatus.objective_alignment.mim_objective_active } else { "" }
    $refreshFailure = if ($IntegrationStatus -and $IntegrationStatus.PSObject.Properties["mim_refresh"] -and $IntegrationStatus.mim_refresh.PSObject.Properties["failure_reason"]) { [string]$IntegrationStatus.mim_refresh.failure_reason } else { "missing" }

    $checks = @(
        [pscustomobject]@{ name = "compatible"; expected = $expectedCompatible; actual = $actualCompatible; passed = ($actualCompatible -eq $expectedCompatible) },
        [pscustomobject]@{ name = "objective_alignment"; expected = $expectedAlignment; actual = $actualAlignment; passed = (Test-AlignmentEquivalent -Actual $actualAlignment -Expected $expectedAlignment) },
        [pscustomobject]@{ name = "tod_current_objective"; expected = $expectedTod; actual = $actualTod; passed = ([string]$actualTod -eq [string]$expectedTod) },
        [pscustomobject]@{ name = "mim_objective_active"; expected = $expectedMim; actual = $actualMim; passed = ([string]$actualMim -eq [string]$expectedMim) },
        [pscustomobject]@{ name = "mim_refresh_failure_reason_empty"; expected = ""; actual = $refreshFailure; passed = ([string]::IsNullOrWhiteSpace($refreshFailure)) }
    )

    $allPassed = (@($checks | Where-Object { -not [bool]$_.passed }).Count -eq 0)

    return [pscustomobject]@{
        request_id = $RequestId
        passed = $allPassed
        expected = [pscustomobject]@{
            compatible = $expectedCompatible
            objective_alignment_status = $expectedAlignment
            tod_current_objective = $expectedTod
            mim_objective_active = $expectedMim
            mim_refresh_failure_reason = ""
        }
        actual = [pscustomobject]@{
            compatible = $actualCompatible
            objective_alignment_status = $actualAlignment
            tod_current_objective = $actualTod
            mim_objective_active = $actualMim
            mim_refresh_failure_reason = $refreshFailure
        }
        checks = @($checks)
    }
}

function Get-RequestAlignedIntegrationStatus {
    param(
        [AllowNull()]$IntegrationStatus,
        [Parameter(Mandatory = $true)]$Request
    )

    if ($null -eq $IntegrationStatus) {
        return $IntegrationStatus
    }

    $expectedObjective = Get-ExpectedObjectiveFromRequest -Request $Request
    if ([string]::IsNullOrWhiteSpace($expectedObjective)) {
        return $IntegrationStatus
    }

    $liveTaskRequest = if ($IntegrationStatus.PSObject.Properties['live_task_request'] -and $null -ne $IntegrationStatus.live_task_request) { $IntegrationStatus.live_task_request } else { $null }
    $liveObjective = ''
    if ($liveTaskRequest -and $liveTaskRequest.PSObject.Properties['normalized_objective_id'] -and -not [string]::IsNullOrWhiteSpace([string]$liveTaskRequest.normalized_objective_id)) {
        $liveObjective = [string]$liveTaskRequest.normalized_objective_id
    }
    elseif ($liveTaskRequest -and $liveTaskRequest.PSObject.Properties['objective_id'] -and -not [string]::IsNullOrWhiteSpace([string]$liveTaskRequest.objective_id)) {
        $liveObjective = Normalize-ObjectiveIdText -ObjectiveId ([string]$liveTaskRequest.objective_id)
    }

    $requestTargetFile = if ($Request.PSObject.Properties['target_file']) { [string]$Request.target_file } else { '' }
    $requestTargetFiles = if ($Request.PSObject.Properties['target_files'] -and $null -ne $Request.target_files) { @($Request.target_files | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) } else { @() }
    $requestTaskClass = if ($Request.PSObject.Properties['task_class']) { [string]$Request.task_class } elseif ($Request.PSObject.Properties['objective_type']) { [string]$Request.objective_type } else { '' }
    $requestValidationOnly = if ($Request.PSObject.Properties['validation_only']) { [bool]$Request.validation_only } else { $false }
    $requestIsExecutableImplementation = (
        -not $requestValidationOnly -and
        -not [string]::Equals($requestTaskClass, 'diagnostic_only', [System.StringComparison]::OrdinalIgnoreCase) -and
        (-not [string]::IsNullOrWhiteSpace($requestTargetFile) -or @($requestTargetFiles).Count -gt 0)
    )

    if (-not [string]::Equals($liveObjective, $expectedObjective, [System.StringComparison]::OrdinalIgnoreCase) -and -not $requestIsExecutableImplementation) {
        return $IntegrationStatus
    }

    $copy = ($IntegrationStatus | ConvertTo-Json -Depth 30 | ConvertFrom-Json)
    if (-not $copy.PSObject.Properties['objective_alignment'] -or $null -eq $copy.objective_alignment) {
        $copy | Add-Member -NotePropertyName objective_alignment -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    $copy.objective_alignment | Add-Member -NotePropertyName status -NotePropertyValue 'aligned' -Force
    $copy.objective_alignment | Add-Member -NotePropertyName aligned -NotePropertyValue $true -Force
    $copy.objective_alignment | Add-Member -NotePropertyName tod_current_objective -NotePropertyValue $expectedObjective -Force
    $copy.objective_alignment | Add-Member -NotePropertyName mim_objective_active -NotePropertyValue $expectedObjective -Force
    $copy.objective_alignment | Add-Member -NotePropertyName source -NotePropertyValue 'live_task_request_override' -Force
    if ($copy.PSObject.Properties['bridge_canonical_evidence'] -and $null -ne $copy.bridge_canonical_evidence) {
        $originalSignals = @()
        if ($copy.bridge_canonical_evidence.PSObject.Properties['failure_signals'] -and $null -ne $copy.bridge_canonical_evidence.failure_signals) {
            $originalSignals = @($copy.bridge_canonical_evidence.failure_signals | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        }
        $remainingSignals = @($originalSignals | Where-Object { $_ -notin @('live_task_request_objective_mismatch', 'live_task_request_task_mismatch', 'live_task_request_not_promoted') })
        $copy.bridge_canonical_evidence | Add-Member -NotePropertyName failure_signals -NotePropertyValue @($remainingSignals) -Force
        $copy.bridge_canonical_evidence | Add-Member -NotePropertyName live_task_request_alignment_override_applied -NotePropertyValue $true -Force
        $copy.bridge_canonical_evidence | Add-Member -NotePropertyName live_task_request_alignment_override_reason -NotePropertyValue 'live_task_request_matches_executing_request' -Force
    }
    $copy | Add-Member -NotePropertyName listener_alignment_override -NotePropertyValue ([pscustomobject]@{
        applied = $true
        reason = if ([string]::Equals($liveObjective, $expectedObjective, [System.StringComparison]::OrdinalIgnoreCase)) { 'live_task_request_objective_matches_executing_request' } else { 'frozen_executable_request_objective_used_for_result_contract' }
        expected_objective = $expectedObjective
        live_task_request_objective = $liveObjective
        original_tod_current_objective = if ($IntegrationStatus.PSObject.Properties['objective_alignment'] -and $IntegrationStatus.objective_alignment.PSObject.Properties['tod_current_objective']) { [string]$IntegrationStatus.objective_alignment.tod_current_objective } else { '' }
        original_mim_objective_active = if ($IntegrationStatus.PSObject.Properties['objective_alignment'] -and $IntegrationStatus.objective_alignment.PSObject.Properties['mim_objective_active']) { [string]$IntegrationStatus.objective_alignment.mim_objective_active } else { '' }
    }) -Force

    return $copy
}

function Invoke-OptionalValidator {
    param(
        [string]$ValidatorAbs,
        [string]$RequestId,
        [string]$RequestPath,
        [string]$GoOrderPath,
        [string]$ReviewDecisionPath,
        [string]$IntegrationStatusPath,
        [string]$ResultPath
    )

    if ([string]::IsNullOrWhiteSpace($ValidatorAbs)) {
        return [pscustomobject]@{
            attempted = $false
            passed = $true
            message = "validator_not_configured"
            output = ""
        }
    }

    if (-not (Test-Path -Path $ValidatorAbs)) {
        return [pscustomobject]@{
            attempted = $true
            passed = $false
            message = "validator_script_not_found"
            output = $ValidatorAbs
        }
    }

    try {
        # Run validator out-of-process so any large-file read or exception inside
        # it cannot take down the listener or corrupt the main result packet.
        $raw = powershell -NoProfile -ExecutionPolicy Bypass -File $ValidatorAbs -RequestId $RequestId -RequestPath $RequestPath -GoOrderPath $GoOrderPath -ReviewDecisionPath $ReviewDecisionPath -IntegrationStatusPath $IntegrationStatusPath -ResultPath $ResultPath 2>&1
        $exitCode = $LASTEXITCODE
        if ($null -eq $exitCode) {
            $exitCode = 0
        }
        if ($exitCode -ne 0) {
            return [pscustomobject]@{
                attempted = $true
                passed = $false
                message = "validator_failed"
                output = [string]($raw | Out-String)
            }
        }
        return [pscustomobject]@{
            attempted = $true
            passed = $true
            message = "validator_passed"
            output = [string]($raw | Out-String)
        }
    }
    catch {
        return [pscustomobject]@{
            attempted = $true
            passed = $false
            message = "validator_failed"
            output = [string]$_.Exception.Message
        }
    }
}

function Invoke-LedgerObserveShadowWrite {
    param(
        [Parameter(Mandatory = $true)][string]$RequestId,
        [string]$TaskId = '',
        [string]$CorrelationId = '',
        [string]$SourceArtifact = 'MIM_TOD_TASK_REQUEST.latest.json',
        [string]$EventType = 'request_observed',
        [string]$MessageType = 'request',
        [string]$FromAgent = 'MIM',
        [string]$ToAgent = 'TOD',
        [string]$Status = 'observed',
        [Parameter(Mandatory = $true)][string]$PythonCommand,
        [Parameter(Mandatory = $true)][string]$LedgerScriptAbs,
        [Parameter(Mandatory = $true)][string]$LedgerDbAbs,
        [Parameter(Mandatory = $true)][string]$LedgerMigrationAbs,
        [Parameter(Mandatory = $true)][string]$LedgerStatusAbs
    )

    $observedAt = (Get-Date).ToUniversalTime().ToString('o')
    $safeRequestId = [string]$RequestId
    $safeEventType = if ([string]::IsNullOrWhiteSpace($EventType)) { 'request_observed' } else { ([string]$EventType).Trim().ToLowerInvariant() }
    $safeStatus = if ([string]::IsNullOrWhiteSpace($Status)) { 'observed' } else { [string]$Status }
    $messageId = ('obs-{0}-{1}' -f $safeEventType, $safeRequestId)
    $payloadPath = ''
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)

    try {
        $statusDir = Split-Path -Parent $LedgerStatusAbs
        if (-not [string]::IsNullOrWhiteSpace($statusDir) -and -not (Test-Path -Path $statusDir)) {
            New-Item -ItemType Directory -Path $statusDir -Force | Out-Null
        }

        $payloadPath = Join-Path $statusDir ('.ledger_obs_payload_' + ([guid]::NewGuid().ToString('N').Substring(0, 8)) + '.json')
        $payload = [ordered]@{
            message_id     = $messageId
            task_id        = $TaskId
            request_id     = $safeRequestId
            correlation_id = $CorrelationId
            from_agent     = [string]$FromAgent
            to_agent       = [string]$ToAgent
            event_type     = $safeEventType
            message_type   = [string]$MessageType
            status         = $safeStatus
            source_surface = $SourceArtifact
            observed_at    = $observedAt
            created_at     = $observedAt
        }
        [System.IO.File]::WriteAllText($payloadPath, ($payload | ConvertTo-Json -Depth 6), $utf8NoBom)

        $savedEAP = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $ledgerRaw = & $PythonCommand $LedgerScriptAbs `
            --db $LedgerDbAbs `
            --migration $LedgerMigrationAbs `
            --status-path $LedgerStatusAbs `
            --mode 'observe_only' `
            --operation 'append_message' `
            --payload-file $payloadPath 2>&1
        $ledgerExitCode = $LASTEXITCODE
        $ErrorActionPreference = $savedEAP
        # Normalise mixed stdout/ErrorRecord output to plain strings (avoids EAP=Stop escalation)
        $ledgerOutput = @($ledgerRaw | ForEach-Object { [string]$_ })

        try {
            $existingStatus = $null
            if (Test-Path -Path $LedgerStatusAbs) {
                $existingStatus = Get-Content -Path $LedgerStatusAbs -Raw | ConvertFrom-Json -ErrorAction SilentlyContinue
            }
            $lastSuccessAt = ''
            if ($ledgerExitCode -eq 0) {
                $lastSuccessAt = $observedAt
            } elseif ($null -ne $existingStatus -and $existingStatus.PSObject.Properties['last_success_at']) {
                $lastSuccessAt = [string]$existingStatus.last_success_at
            }
            $lastErrorText = if ($ledgerExitCode -ne 0) { ($ledgerOutput -join "`n").Trim() } else { '' }
            $lastEventType = $safeEventType
            if ($null -ne $existingStatus) {
                $existingStatus | Add-Member -NotePropertyName 'enabled'               -NotePropertyValue $true            -Force
                $existingStatus | Add-Member -NotePropertyName 'non_blocking'          -NotePropertyValue $true            -Force
                $existingStatus | Add-Member -NotePropertyName 'last_attempt_at'       -NotePropertyValue $observedAt      -Force
                $existingStatus | Add-Member -NotePropertyName 'last_success_at'       -NotePropertyValue $lastSuccessAt   -Force
                $existingStatus | Add-Member -NotePropertyName 'last_error'            -NotePropertyValue $lastErrorText   -Force
                $existingStatus | Add-Member -NotePropertyName 'last_observed_task_id' -NotePropertyValue $TaskId          -Force
                $existingStatus | Add-Member -NotePropertyName 'last_event_type'       -NotePropertyValue $lastEventType   -Force
                $existingStatus | Add-Member -NotePropertyName 'last_request_id'       -NotePropertyValue $safeRequestId   -Force
                [System.IO.File]::WriteAllText($LedgerStatusAbs, (($existingStatus | ConvertTo-Json -Depth 10) + "`n"), $utf8NoBom)
            } else {
                $fallbackStatus = [ordered]@{
                    enabled               = $true
                    non_blocking          = $true
                    last_attempt_at       = $observedAt
                    last_success_at       = $lastSuccessAt
                    last_error            = $lastErrorText
                    last_observed_task_id = $TaskId
                    last_event_type       = $lastEventType
                    last_request_id       = $safeRequestId
                }
                [System.IO.File]::WriteAllText($LedgerStatusAbs, (($fallbackStatus | ConvertTo-Json -Depth 6) + "`n"), $utf8NoBom)
            }
        } catch {
            # Status augmentation failure is non-fatal; swallow silently
        }

        if ($ledgerExitCode -ne 0) {
            Write-Warning ("[TOD-LISTENER-LEDGER] observe shadow write non-zero exit for request {0} event {1}: {2}" -f $safeRequestId, $safeEventType, ($ledgerOutput -join "`n").Trim())
        }
    } catch {
        try {
            $prevSuccessAt = ''
            if (Test-Path -Path $LedgerStatusAbs) {
                $prev = Get-Content -Path $LedgerStatusAbs -Raw | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($null -ne $prev -and $prev.PSObject.Properties['last_success_at']) {
                    $prevSuccessAt = [string]$prev.last_success_at
                }
            }
            $errStatus = [ordered]@{
                enabled               = $true
                non_blocking          = $true
                last_attempt_at       = $observedAt
                last_success_at       = $prevSuccessAt
                last_error            = [string]$_.Exception.Message
                last_observed_task_id = $TaskId
                last_event_type       = $safeEventType
                last_request_id       = $safeRequestId
            }
            [System.IO.File]::WriteAllText($LedgerStatusAbs, (($errStatus | ConvertTo-Json -Depth 6) + "`n"), $utf8NoBom)
        } catch {}
        Write-Warning ("[TOD-LISTENER-LEDGER] shadow write failed (non-fatal) for request {0} event {1}: {2}" -f $safeRequestId, $safeEventType, [string]$_.Exception.Message)
    } finally {
        if (-not [string]::IsNullOrWhiteSpace($payloadPath) -and (Test-Path -Path $payloadPath)) {
            try { Remove-Item -Path $payloadPath -Force -ErrorAction SilentlyContinue } catch {}
        }
    }
}

$envAbs = Get-LocalPath -PathValue $EnvFile
$dialogScriptAbs = Get-LocalPath -PathValue $DialogScriptPath
$conversationProviderScriptAbs = Join-Path $PSScriptRoot 'Invoke-TODConversationProvider.ps1'
$syncScriptAbs = Get-LocalPath -PathValue $SyncScriptPath
$todScriptAbs = Get-LocalPath -PathValue $TodScriptPath
$readinessScriptAbs = Get-LocalPath -PathValue $ReadinessScriptPath
$validatorAbs = if ([string]::IsNullOrWhiteSpace($ValidatorScriptPath)) { "" } else { Get-LocalPath -PathValue $ValidatorScriptPath }
$runtimeContractValidatorAbs = Get-LocalPath -PathValue $RuntimeContractValidatorScriptPath
$stageAbs = Get-LocalPath -PathValue $StageDir
$contractDirAbs = Get-LocalPath -PathValue $ContractSourceDir
$incomingProjectInboxAbs = Get-LocalPath -PathValue $IncomingProjectInboxDir
$syncStageAbs = Get-LocalPath -PathValue $SyncStageDir
$listenerStatePath = Join-Path $stageAbs "listener_state.json"
$todStatePath = Get-LocalPath -PathValue "tod/data/state.json"
$localRuntimeBindingStatePath = Join-Path $stageAbs "TOD_MIM_RUNTIME_BINDING_STATE.latest.json"
$localRuntimeViolationPath = Join-Path $stageAbs "TOD_MIM_RUNTIME_CONTRACT_VIOLATION.latest.json"

if (-not (Test-Path -Path $syncScriptAbs)) { throw "Sync script not found: $syncScriptAbs" }
if (-not (Test-Path -Path $todScriptAbs)) { throw "TOD script not found: $todScriptAbs" }
if (-not (Test-Path -Path $readinessScriptAbs)) { throw "Readiness script not found: $readinessScriptAbs" }
if (-not (Test-Path -Path $envAbs)) { throw "Env file not found: $envAbs" }
if (-not (Test-Path -Path $runtimeContractValidatorAbs)) { throw "Runtime contract validator not found: $runtimeContractValidatorAbs" }

New-Item -ItemType Directory -Path $stageAbs -Force | Out-Null
New-Item -ItemType Directory -Path $incomingProjectInboxAbs -Force | Out-Null
New-Item -ItemType Directory -Path $syncStageAbs -Force | Out-Null

$hostAlias = Get-DotEnvValue -Path $envAbs -Name "MIM_SSH_HOST"
if ([string]::IsNullOrWhiteSpace($hostAlias)) { $hostAlias = "mim" }
$userName = Get-DotEnvValue -Path $envAbs -Name "MIM_SSH_USER"
if ([string]::IsNullOrWhiteSpace($userName)) { $userName = "testpilot" }
$portText = Get-DotEnvValue -Path $envAbs -Name "MIM_SSH_PORT"
$port = 22
if (-not [string]::IsNullOrWhiteSpace($portText)) {
    $parsed = 0
    if ([int]::TryParse($portText, [ref]$parsed) -and $parsed -gt 0) {
        $port = $parsed
    }
}
$password = Get-DotEnvValue -Path $envAbs -Name "MIM_SSH_PASSWORD"
if ([string]::IsNullOrWhiteSpace($password) -or $password -eq "CHANGE_ME") {
    throw "Set MIM_SSH_PASSWORD in $envAbs"
}

$publishStatus = $true
if ($PSBoundParameters.ContainsKey("PublishIntegrationStatus")) {
    $publishStatus = [bool]$PublishIntegrationStatus
}

$localRequestPath = Join-Path $stageAbs "MIM_TOD_TASK_REQUEST.latest.json"
$localLegacyRequestPath = Join-Path $stageAbs "MIM_TOD_TASK_REQUEST.json"
$localGoOrderPath = Join-Path $stageAbs "MIM_TOD_GO_ORDER.latest.json"
$localReviewPath = Join-Path $stageAbs "MIM_TOD_REVIEW_DECISION.latest.json"
$localAckPath = Join-Path $stageAbs "TOD_MIM_TASK_ACK.latest.json"
$localResultPath = Join-Path $stageAbs "TOD_MIM_TASK_RESULT.latest.json"
$localTroubleshootingPath = Join-Path $stageAbs "TOD_MIM_TASK_TROUBLESHOOTING.latest.json"
$localCommandStatusPath = Join-Path $stageAbs "TOD_MIM_COMMAND_STATUS.latest.json"
$localDecisionPath = Join-Path $stageAbs "TOD_MIM_EXECUTION_DECISION.latest.json"
$localJournalPath = Join-Path $stageAbs "TOD_LOOP_JOURNAL.latest.json"
$localExecutionLockPath = Get-LocalPath -PathValue "runtime/shared/TOD_EXECUTION_LOCK.latest.json"
$localRemoteStatusFile = Join-Path $stageAbs "TOD_INTEGRATION_STATUS.latest.json"
$localRemoteStatusAliasFile = Join-Path $stageAbs "TOD_integration_status.latest.json"
$localTriggerAckPath = Join-Path $stageAbs "TOD_TO_MIM_TRIGGER_ACK.latest.json"
$localLivenessTriggerPath = Join-Path $stageAbs "MIM_TO_TOD_TRIGGER.latest.json"
$localLivenessTriggerAltPath = Join-Path $stageAbs "MIM-TO_TOD_TRIGGER.latest.json"
$localLivenessPingPath = Join-Path $stageAbs "MIM_TO_TOD_PING.latest.json"
$localLivenessResponsePath = Join-Path $stageAbs "TOD_TO_MIM_PING.latest.json"
$localRegressionStallPath = Join-Path $stageAbs "TOD_REGRESSION_STALL_STATE.latest.json"
$localStallAlertPath = Join-Path $stageAbs "TOD_MIM_STALL_ALERT.latest.json"
$localCoordinationRequestPath = Join-Path $stageAbs "TOD_MIM_COORDINATION_REQUEST.latest.json"
$localCoordinationAckPath = Join-Path $stageAbs "MIM_TOD_COORDINATION_ACK.latest.json"
$localEmergencyRequestPath = Join-Path $stageAbs "TOD_MIM_EMERGENCY_REQUEST.latest.json"
$localEmergencyAckPath = Join-Path $stageAbs "MIM_TOD_EMERGENCY_ACK.latest.json"
$localCoordinationEscalationStatePath = Join-Path $stageAbs "TOD_MIM_COORDINATION_ESCALATION_STATE.latest.json"
$localQuarantineStatePath = Join-Path $stageAbs "TOD_MIM_QUARANTINE_STATE.latest.json"
$localIdleWakeupStatePath  = Join-Path $stageAbs "TOD_IDLE_WAKEUP_STATE.latest.json"
$currentBuildStatePath = Get-LocalPath -PathValue "shared_state/current_build_state.json"

$remoteRequestPath = ("{0}/MIM_TOD_TASK_REQUEST.latest.json" -f $RemoteRoot.TrimEnd('/'))
$remoteLegacyRequestPath = ("{0}/MIM_TOD_TASK_REQUEST.json" -f $RemoteRoot.TrimEnd('/'))
$remoteGoOrderPath = ("{0}/MIM_TOD_GO_ORDER.latest.json" -f $RemoteRoot.TrimEnd('/'))
$remoteReviewPath = ("{0}/MIM_TOD_REVIEW_DECISION.latest.json" -f $RemoteRoot.TrimEnd('/'))
$remoteAckPath = ("{0}/TOD_MIM_TASK_ACK.latest.json" -f $RemoteRoot.TrimEnd('/'))
$remoteResultPath = ("{0}/TOD_MIM_TASK_RESULT.latest.json" -f $RemoteRoot.TrimEnd('/'))
$remoteTroubleshootingPath = ("{0}/TOD_MIM_TASK_TROUBLESHOOTING.latest.json" -f $RemoteRoot.TrimEnd('/'))
$remoteCommandStatusPath = ("{0}/TOD_MIM_COMMAND_STATUS.latest.json" -f $RemoteRoot.TrimEnd('/'))
$remoteDecisionPath = ("{0}/TOD_MIM_EXECUTION_DECISION.latest.json" -f $RemoteRoot.TrimEnd('/'))
$remoteStatusPath = ("{0}/TOD_INTEGRATION_STATUS.latest.json" -f $RemoteRoot.TrimEnd('/'))
$remoteStatusAliasPath = ("{0}/TOD_integration_status.latest.json" -f $RemoteRoot.TrimEnd('/'))
$remoteJournalPath = ("{0}/TOD_LOOP_JOURNAL.latest.json" -f $RemoteRoot.TrimEnd('/'))
$remoteExecutionLockPath = ("{0}/TOD_EXECUTION_LOCK.latest.json" -f $RemoteRoot.TrimEnd('/'))
$remoteTriggerAckPath = ("{0}/TOD_TO_MIM_TRIGGER_ACK.latest.json" -f $RemoteRoot.TrimEnd('/'))
$remoteLivenessTriggerPath = ("{0}/MIM_TO_TOD_TRIGGER.latest.json" -f $RemoteRoot.TrimEnd('/'))
$remoteLivenessTriggerAltPath = ("{0}/MIM-TO_TOD_TRIGGER.latest.json" -f $RemoteRoot.TrimEnd('/'))
$remoteLivenessPingPath = ("{0}/MIM_TO_TOD_PING.latest.json" -f $RemoteRoot.TrimEnd('/'))
$remoteLivenessResponsePath = ("{0}/TOD_TO_MIM_PING.latest.json" -f $RemoteRoot.TrimEnd('/'))
$remoteStallAlertPath = ("{0}/TOD_MIM_STALL_ALERT.latest.json" -f $RemoteRoot.TrimEnd('/'))
$remoteCoordinationRequestPath = ("{0}/TOD_MIM_COORDINATION_REQUEST.latest.json" -f $RemoteRoot.TrimEnd('/'))
$remoteCoordinationAckPath = ("{0}/MIM_TOD_COORDINATION_ACK.latest.json" -f $RemoteRoot.TrimEnd('/'))
$remoteEmergencyRequestPath = ("{0}/TOD_MIM_EMERGENCY_REQUEST.latest.json" -f $RemoteRoot.TrimEnd('/'))
$remoteEmergencyAckPath = ("{0}/MIM_TOD_EMERGENCY_ACK.latest.json" -f $RemoteRoot.TrimEnd('/'))

$listenerState = New-ListenerState -ExistingState (Read-JsonFileIfExists -PathValue $listenerStatePath)
$pythonCommand = Get-PythonCommand

$messageLedgerMode = ''
if ($null -ne $env:MESSAGE_LEDGER_MODE -and -not [string]::IsNullOrWhiteSpace($env:MESSAGE_LEDGER_MODE)) {
    $messageLedgerMode = ([string]$env:MESSAGE_LEDGER_MODE).Trim().ToLowerInvariant()
}
$messageLedgerEnabled = [string]::Equals($messageLedgerMode, 'observe_only', [System.StringComparison]::OrdinalIgnoreCase)
$ledgerScriptAbs = Join-Path $PSScriptRoot 'tod_mim_message_ledger.py'
$ledgerDbAbs = Get-LocalPath -PathValue 'runtime/shared/TOD_MIM_MESSAGE_LEDGER.sqlite3'
$ledgerMigrationAbs = Get-LocalPath -PathValue 'db/migrations/20260506_tod_mim_message_ledger_phase_a_observe_only.sql'
$ledgerStatusAbs = Get-LocalPath -PathValue 'runtime/shared/TOD_MIM_LEDGER_OBSERVE_STATUS.latest.json'

$contractBinding = Get-ContractBindingMetadata -ContractDirPath $contractDirAbs -RemoteSurface $RemoteRoot -LocalStageDir $stageAbs
Write-RuntimeBindingState -StatePath $localRuntimeBindingStatePath -State (Read-RuntimeBindingState -StatePath $localRuntimeBindingStatePath -BindingMetadata $contractBinding)
$regressionStallState = New-RegressionStallState -ExistingState (Read-JsonFileIfExists -PathValue $localRegressionStallPath)
$coordinationEscalationState = New-CoordinationEscalationState -ExistingState (Read-JsonFileIfExists -PathValue $localCoordinationEscalationStatePath)
$publishDialogRemoteByDefault = $true
if ($PSBoundParameters.ContainsKey('PublishDialogRemote')) {
    $publishDialogRemoteByDefault = [bool]$PublishDialogRemote
}
$quarantineState = New-QuarantineState -ExistingState (Read-JsonFileIfExists -PathValue $localQuarantineStatePath)
$idleWakeupState  = New-IdleWakeupState  -ExistingState (Read-JsonFileIfExists -PathValue $localIdleWakeupStatePath)

$listenerMutexHandle = New-ListenerMutexHandle -PreferredName $script:ListenerMutexName -FallbackName $script:ListenerMutexFallbackName
$listenerMutex = $listenerMutexHandle.mutex
$script:ListenerMutexName = [string]$listenerMutexHandle.name
$listenerHasHandle = $false

try {
    $listenerHasHandle = $listenerMutex.WaitOne(0)
    if (-not $listenerHasHandle) {
        $listenerState | Add-Member -NotePropertyName generated_at -NotePropertyValue (Get-UtcNowString) -Force
        $listenerState | Add-Member -NotePropertyName status -NotePropertyValue "skipped" -Force
        $listenerState | Add-Member -NotePropertyName reason -NotePropertyValue "instance_already_running" -Force
        $listenerState | Add-Member -NotePropertyName mutex -NotePropertyValue $script:ListenerMutexName -Force
        $listenerState | Add-Member -NotePropertyName pid -NotePropertyValue $PID -Force
        Write-JsonFile -PathValue $listenerStatePath -Payload $listenerState
        Write-Host ("[TOD-LISTENER] Another instance already owns {0}; exiting." -f $script:ListenerMutexName)
        return
    }

    Write-Host ("[TOD-LISTENER] Started. version={0} host={1} root={2} poll={3}s run_once={4}" -f $scriptVersion, $hostAlias, $RemoteRoot, $PollSeconds, [bool]$RunOnce)
    $lastSkipLogId = ""

    while ($true) {
    $cycleStartedAt = (Get-Date).ToUniversalTime().ToString("o")
    $connections = $null
    Update-ListenerHeartbeat -State $listenerState -StatePath $listenerStatePath -CycleStartedAt $cycleStartedAt

    try {
        $connections = New-SshConnections -HostAlias $hostAlias -UserName $userName -Port $port -Password $password

        $requestExists = Download-RemoteFile -Connections $connections -RemotePath $remoteRequestPath -LocalPath $localRequestPath
        $legacyRequestExists = Download-RemoteFile -Connections $connections -RemotePath $remoteLegacyRequestPath -LocalPath $localLegacyRequestPath

        if (-not $requestExists -and $legacyRequestExists) {
            Copy-Item -Path $localLegacyRequestPath -Destination $localRequestPath -Force
            $requestExists = $true
            Write-Host "[TOD-LISTENER] Canonical request hydrated from legacy alias MIM_TOD_TASK_REQUEST.json."
        }

        if ($legacyRequestExists) {
            $legacySignature = Get-RequestSignature -RequestPath $localLegacyRequestPath -SemanticTaskPacket
            if (-not [string]::IsNullOrWhiteSpace($legacySignature) -and
                -not [string]::Equals($legacySignature, [string]$listenerState.last_project_request_signature, [System.StringComparison]::OrdinalIgnoreCase)) {
                $snapshotPath = Save-ArtifactSnapshot -SourcePath $localLegacyRequestPath -SnapshotDir $incomingProjectInboxAbs -Prefix "MIM_TOD_TASK_REQUEST" -Signature $legacySignature
                $listenerState.last_project_request_signature = $legacySignature
                $listenerState.last_project_request_snapshot_path = $snapshotPath
                Write-Host ("[TOD-LISTENER] Preserved inbound legacy request snapshot: {0}" -f $snapshotPath)
            }
        }

        $null = Download-RemoteFile -Connections $connections -RemotePath $remoteGoOrderPath -LocalPath $localGoOrderPath
        $null = Download-RemoteFile -Connections $connections -RemotePath $remoteReviewPath -LocalPath $localReviewPath
        $livenessTriggerExists = Download-RemoteFile -Connections $connections -RemotePath $remoteLivenessTriggerPath -LocalPath $localLivenessTriggerPath
        $livenessTriggerAltExists = Download-RemoteFile -Connections $connections -RemotePath $remoteLivenessTriggerAltPath -LocalPath $localLivenessTriggerAltPath
        $livenessPingExists = Download-RemoteFile -Connections $connections -RemotePath $remoteLivenessPingPath -LocalPath $localLivenessPingPath
        $coordinationAckExists = Download-RemoteFile -Connections $connections -RemotePath $remoteCoordinationAckPath -LocalPath $localCoordinationAckPath
        $emergencyAckExists = Download-RemoteFile -Connections $connections -RemotePath $remoteEmergencyAckPath -LocalPath $localEmergencyAckPath

        if (-not $livenessTriggerExists -and $livenessTriggerAltExists) {
            Copy-Item -Path $localLivenessTriggerAltPath -Destination $localLivenessTriggerPath -Force
            $livenessTriggerExists = $true
            Write-Host "[TOD-LISTENER] Canonical trigger hydrated from alternate alias MIM-TO_TOD_TRIGGER.latest.json."
        }
        elseif ($livenessTriggerExists -and $livenessTriggerAltExists) {
            $primaryInfo = Get-Item -Path $localLivenessTriggerPath -ErrorAction SilentlyContinue
            $altInfo = Get-Item -Path $localLivenessTriggerAltPath -ErrorAction SilentlyContinue
            if ($null -ne $primaryInfo -and $null -ne $altInfo -and $altInfo.LastWriteTimeUtc -gt $primaryInfo.LastWriteTimeUtc) {
                Copy-Item -Path $localLivenessTriggerAltPath -Destination $localLivenessTriggerPath -Force
                Write-Host "[TOD-LISTENER] Alternate trigger alias superseded canonical trigger due to newer timestamp."
            }
        }

        $contextSyncTruthRepairScript = Join-Path $PSScriptRoot "Repair-ContextSyncLatestTruth.ps1"
        if (Test-Path -LiteralPath $contextSyncTruthRepairScript) {
            try {
                & powershell -NoProfile -ExecutionPolicy Bypass -File $contextSyncTruthRepairScript -NoBackup | Out-Null
            }
            catch {
                Write-Host ("[TOD-LISTENER] Context-sync latest truth repair failed: {0}" -f ([string]::Join(' ', @($_.Exception.Message -split '\s+'))))
            }
        }

        $integrationStatusPath = Get-LocalPath -PathValue "shared_state/integration_status.json"
        $integrationStatus = Read-JsonFileIfExists -PathValue $integrationStatusPath
        $statusPublishedThisCycle = $false

        $livenessTrigger = if ($livenessTriggerExists) { Read-JsonFileIfExists -PathValue $localLivenessTriggerPath } else { $null }
        $livenessPing = if ($livenessPingExists) { Read-JsonFileIfExists -PathValue $localLivenessPingPath } else { $null }
        $requestPreview = if ($requestExists) { Read-JsonFileIfExists -PathValue $localRequestPath } else { $null }
        $triggerTaskId = Get-TriggerFieldText -TriggerPacket $livenessTrigger -FieldName "task_id"
        $triggerCorrelationId = Get-TriggerFieldText -TriggerPacket $livenessTrigger -FieldName "correlation_id"
        $currentTaskId = if (-not [string]::IsNullOrWhiteSpace($triggerTaskId)) {
            $triggerTaskId
        }
        elseif ($requestPreview -and $requestPreview.PSObject.Properties["task_id"] -and -not [string]::IsNullOrWhiteSpace([string]$requestPreview.task_id)) {
            [string]$requestPreview.task_id
        }
        elseif ($requestPreview -and $requestPreview.PSObject.Properties["request_id"] -and -not [string]::IsNullOrWhiteSpace([string]$requestPreview.request_id)) {
            [string]$requestPreview.request_id
        }
        elseif (-not [string]::IsNullOrWhiteSpace([string]$listenerState.last_processed_request_id)) {
            [string]$listenerState.last_processed_request_id
        }
        else {
            ""
        }
        $currentCorrelationId = if (-not [string]::IsNullOrWhiteSpace($triggerCorrelationId)) {
            $triggerCorrelationId
        }
        elseif ($requestPreview -and $requestPreview.PSObject.Properties["correlation_id"] -and -not [string]::IsNullOrWhiteSpace([string]$requestPreview.correlation_id)) {
            [string]$requestPreview.correlation_id
        }
        else {
            ""
        }
        $bridgeRuntime = Get-BridgeRuntimeStatus -CurrentTaskId $currentTaskId -CurrentCorrelationId $currentCorrelationId
        $hasActiveCoordinationEscalation = -not [string]::IsNullOrWhiteSpace([string]$coordinationEscalationState.pending_request_id)
        $observedAliasArtifacts = @()
        if ($legacyRequestExists) {
            $observedAliasArtifacts += "MIM_TOD_TASK_REQUEST.json"
        }
        if ($livenessTriggerAltExists) {
            $observedAliasArtifacts += "MIM-TO_TOD_TRIGGER.latest.json"
        }
        if ($observedAliasArtifacts.Count -gt 0 -and -not $hasActiveCoordinationEscalation) {
            $handoffCoordinationObjectiveId = if ($requestPreview) { Get-ExpectedObjectiveFromRequest -Request $requestPreview } else { "" }
            $handoffCoordinationSignature = ((@(
                        ($observedAliasArtifacts -join ","),
                        [string]$currentTaskId,
                        [string]$currentCorrelationId
                    ) -join "|").ToLowerInvariant())

            if (-not [string]::Equals($handoffCoordinationSignature, [string]$listenerState.last_handoff_coordination_signature, [System.StringComparison]::OrdinalIgnoreCase)) {
                $handoffCoordinationRequestId = "handoff-alias-" + ([guid]::NewGuid().ToString("N").Substring(0, 12))
                $handoffCoordinationRequest = [pscustomobject]@{
                    generated_at = (Get-Date).ToUniversalTime().ToString("o")
                    source = "tod-mim-coordination-request-v1"
                    priority = "high"
                    escalation_level = 1
                    request_id = $handoffCoordinationRequestId
                    objective_id = [string]$handoffCoordinationObjectiveId
                    issue_code = "handoff_artifact_alias_detected"
                    issue_summary = "TOD detected non-canonical inbound handoff artifacts and enabled compatibility preservation to avoid overwrite loss. Coordinate future handoff directly through canonical TOD-MIM request and trigger artifact names."
                    evidence = [pscustomobject]@{
                        observed_alias_artifacts = $observedAliasArtifacts
                        canonical_artifacts = @("MIM_TOD_TASK_REQUEST.latest.json", "MIM_TO_TOD_TRIGGER.latest.json", "MIM_TOD_GO_ORDER.latest.json", "MIM_TOD_REVIEW_DECISION.latest.json")
                        legacy_request_snapshot_path = [string]$listenerState.last_project_request_snapshot_path
                        current_task_id = [string]$currentTaskId
                        current_correlation_id = [string]$currentCorrelationId
                    }
                    requested_action = "acknowledge_and_normalize_handoff_artifacts"
                    required_ack = [pscustomobject]@{
                        ack_file = "MIM_TOD_COORDINATION_ACK.latest.json"
                        ack_fields = @("acknowledged", "acknowledged_at", "request_id", "decision", "reason")
                        timeout_seconds = 300
                    }
                    bridge_runtime = $bridgeRuntime
                }
                Write-JsonFile -PathValue $localCoordinationRequestPath -Payload $handoffCoordinationRequest
                $handoffCoordinationJson = Get-Content -Path $localCoordinationRequestPath -Raw
                Write-RemoteFileFromText -Connections $connections -RemotePath $remoteCoordinationRequestPath -Content $handoffCoordinationJson

                Publish-CommandStatus -ListenerState $listenerState -ListenerStatePath $listenerStatePath -LocalPath $localCommandStatusPath -RemotePath $remoteCommandStatusPath -Connections $connections -Status "non_canonical_artifacts_observed" -Detail ("Observed non-canonical inbound artifacts: {0}. Canonical live handoff must use MIM_TOD_TASK_REQUEST.latest.json and MIM_TO_TOD_TRIGGER.latest.json." -f ($observedAliasArtifacts -join ", ")) -RequestId $currentTaskId -TaskId $currentTaskId -CorrelationId $currentCorrelationId -TriggerPacket $livenessTrigger -BridgeRuntime $bridgeRuntime

                $listenerState.last_handoff_coordination_signature = $handoffCoordinationSignature
                $listenerState.last_handoff_coordination_request_id = $handoffCoordinationRequestId
                Write-Host ("[TOD-LISTENER] Published TOD-MIM handoff coordination request: {0}" -f $handoffCoordinationRequestId)
            }
        }

        $livenessTriggerSignature = if ($livenessTriggerExists) { Get-RequestSignature -RequestPath $localLivenessTriggerPath } else { "" }
        $livenessPingSignature = if ($livenessPingExists) { Get-RequestSignature -RequestPath $localLivenessPingPath } else { "" }
        $livenessTriggerChanged = (-not [string]::IsNullOrWhiteSpace($livenessTriggerSignature)) -and (-not [string]::Equals($livenessTriggerSignature, [string]$listenerState.last_liveness_trigger_signature, [System.StringComparison]::OrdinalIgnoreCase))
        $livenessPingChanged = (-not [string]::IsNullOrWhiteSpace($livenessPingSignature)) -and (-not [string]::Equals($livenessPingSignature, [string]$listenerState.last_liveness_ping_signature, [System.StringComparison]::OrdinalIgnoreCase))
        $statusPublishDue = $publishStatus -and ((Get-AgeSeconds -Since ([string]$listenerState.last_status_publish_at)) -ge [int]$StatusPublishSeconds)

        if ($publishStatus -and ($statusPublishDue -or $livenessTriggerChanged -or $livenessPingChanged)) {
            try {
                $null = Invoke-SharedStateSyncRefresh -SyncScriptAbs $syncScriptAbs -HostAlias $hostAlias -RemoteRoot $RemoteRoot -SyncStageRoot $SyncStageDir -Reason "integration status publish"
                $integrationStatus = Read-JsonFileIfExists -PathValue $integrationStatusPath
                Publish-IntegrationStatusFiles -Connections $connections -SourcePath $integrationStatusPath -LocalPath $localRemoteStatusFile -RemotePath $remoteStatusPath -LocalAliasPath $localRemoteStatusAliasFile -RemoteAliasPath $remoteStatusAliasPath
                $listenerState.last_status_publish_at = Get-UtcNowString
                $statusPublishedThisCycle = $true
                $integrationStatus = Read-JsonFileIfExists -PathValue $integrationStatusPath
            }
            catch {
                Write-Warning ("[TOD-LISTENER] Unable to publish integration status heartbeat: {0}" -f $_.Exception.Message)
            }
        }

        if ($livenessTriggerChanged -or $livenessPingChanged) {
            if ($livenessTriggerChanged -and $livenessTriggerExists) {
                $triggerSnapshotPath = Save-ArtifactSnapshot -SourcePath $localLivenessTriggerPath -SnapshotDir $incomingProjectInboxAbs -Prefix "MIM_TO_TOD_TRIGGER" -Signature $livenessTriggerSignature
                $listenerState.last_liveness_trigger_snapshot_path = $triggerSnapshotPath
                Write-Host ("[TOD-LISTENER] Preserved inbound liveness trigger snapshot: {0}" -f $triggerSnapshotPath)
            }

            $triggerId = Get-RequestIdentifier -Request $livenessTrigger
            if ([string]::IsNullOrWhiteSpace($triggerId) -and $livenessTrigger -and $livenessTrigger.PSObject.Properties["trigger"] -and -not [string]::IsNullOrWhiteSpace([string]$livenessTrigger.trigger)) {
                $triggerId = [string]$livenessTrigger.trigger
            }
            if ([string]::IsNullOrWhiteSpace($triggerId)) {
                $triggerId = "liveness_ping"
            }

            Publish-TriggerAck -ListenerState $listenerState -ListenerStatePath $listenerStatePath -Connections $connections -LocalPath $localTriggerAckPath -RemotePath $remoteTriggerAckPath -RequestId $triggerId -CurrentTaskId $currentTaskId -CurrentCorrelationId $currentCorrelationId -TriggerPacket $livenessTrigger -BridgeRuntime $bridgeRuntime
            Publish-LivenessResponse -ListenerState $listenerState -ListenerStatePath $listenerStatePath -Connections $connections -LocalPath $localLivenessResponsePath -RemotePath $remoteLivenessResponsePath -TriggerPacket $livenessTrigger -PingPacket $livenessPing -IntegrationStatus $integrationStatus -TriggerId $triggerId -CurrentTaskId $currentTaskId -CurrentCorrelationId $currentCorrelationId -BridgeRuntime $bridgeRuntime

            if (-not [string]::IsNullOrWhiteSpace($livenessTriggerSignature)) {
                $listenerState.last_liveness_trigger_signature = $livenessTriggerSignature
            }
            if (-not [string]::IsNullOrWhiteSpace($livenessPingSignature)) {
                $listenerState.last_liveness_ping_signature = $livenessPingSignature
            }

            Update-ListenerHeartbeat -State $listenerState -StatePath $listenerStatePath -CycleStartedAt $cycleStartedAt
        }
        elseif ($statusPublishedThisCycle) {
            Update-ListenerHeartbeat -State $listenerState -StatePath $listenerStatePath -CycleStartedAt $cycleStartedAt
        }

        if ($coordinationAckExists) {
            $coordinationAck = Read-JsonFileIfExists -PathValue $localCoordinationAckPath
            if ($null -ne $coordinationAck) {
                $acknowledged = $false
                $ackStatus = ""
                $ackDecision = ""
                $ackReason = ""
                $ackGeneratedAt = if ($coordinationAck.PSObject.Properties["generated_at"]) { [string]$coordinationAck.generated_at } else { "" }
                if ($coordinationAck.PSObject.Properties["acknowledged"]) {
                    $acknowledged = [bool]$coordinationAck.acknowledged
                }
                $ackRequestId = if ($coordinationAck.PSObject.Properties["request_id"]) { [string]$coordinationAck.request_id } else { "" }

                if ($coordinationAck.PSObject.Properties["decision"] -and -not [string]::IsNullOrWhiteSpace([string]$coordinationAck.decision)) {
                    $ackDecision = [string]$coordinationAck.decision
                }
                if ($coordinationAck.PSObject.Properties["reason"] -and -not [string]::IsNullOrWhiteSpace([string]$coordinationAck.reason)) {
                    $ackReason = [string]$coordinationAck.reason
                }

                if ($coordinationAck.PSObject.Properties["coordination"] -and $coordinationAck.coordination) {
                    if ($coordinationAck.coordination.PSObject.Properties["status"] -and -not [string]::IsNullOrWhiteSpace([string]$coordinationAck.coordination.status)) {
                        $ackStatus = [string]$coordinationAck.coordination.status
                    }
                    if ([string]::IsNullOrWhiteSpace($ackDecision) -and $coordinationAck.coordination.PSObject.Properties["phase"] -and -not [string]::IsNullOrWhiteSpace([string]$coordinationAck.coordination.phase)) {
                        $ackDecision = [string]$coordinationAck.coordination.phase
                    }
                    if ([string]::IsNullOrWhiteSpace($ackReason) -and $coordinationAck.coordination.PSObject.Properties["detail"] -and -not [string]::IsNullOrWhiteSpace([string]$coordinationAck.coordination.detail)) {
                        $ackReason = [string]$coordinationAck.coordination.detail
                    }
                }

                if ([string]::IsNullOrWhiteSpace($ackRequestId) -and $coordinationAck.PSObject.Properties["task_id"] -and -not [string]::IsNullOrWhiteSpace([string]$coordinationAck.task_id)) {
                    $ackRequestId = [string]$coordinationAck.task_id
                }

                if (-not $acknowledged) {
                    if ([string]::Equals($ackStatus, "acknowledged", [System.StringComparison]::OrdinalIgnoreCase) -or
                        [string]::Equals($ackStatus, "accepted", [System.StringComparison]::OrdinalIgnoreCase) -or
                        [string]::Equals($ackDecision, "acknowledged", [System.StringComparison]::OrdinalIgnoreCase)) {
                        $acknowledged = $true
                    }
                }

                $coordinationEscalationState.last_ack_request_id = $ackRequestId
                $coordinationEscalationState.last_ack_generated_at = $ackGeneratedAt
                $coordinationEscalationState.last_ack_status = $ackStatus
                $coordinationEscalationState.last_ack_decision = $ackDecision
                $coordinationEscalationState.last_ack_reason = $ackReason

                $pendingRequestId = [string]$coordinationEscalationState.pending_request_id

                if ($acknowledged -and -not [string]::IsNullOrWhiteSpace($ackRequestId) -and
                    ([string]::IsNullOrWhiteSpace($pendingRequestId) -or [string]::Equals($ackRequestId, $pendingRequestId, [System.StringComparison]::OrdinalIgnoreCase))) {
                    $coordinationEscalationState.pending_request_id = ""
                    $coordinationEscalationState.pending_since = ""
                    $coordinationEscalationState.last_emit_at = ""
                    $coordinationEscalationState.last_emitted_level = 0
                    $coordinationEscalationState.emit_count = 0
                    $coordinationEscalationState.last_ack_request_id = $ackRequestId
                    $coordinationEscalationState.last_acknowledged_at = if ($coordinationAck.PSObject.Properties["acknowledged_at"]) { [string]$coordinationAck.acknowledged_at } else { (Get-Date).ToUniversalTime().ToString("o") }
                }

                Write-JsonFile -PathValue $localCoordinationEscalationStatePath -Payload $coordinationEscalationState
            }
        }

        if ($emergencyAckExists) {
            $emergencyAck = Read-JsonFileIfExists -PathValue $localEmergencyAckPath
            if ($null -ne $emergencyAck) {
                $emergencyAcknowledged = $false
                $emergencyAckRequestId = if ($emergencyAck.PSObject.Properties['request_id']) { [string]$emergencyAck.request_id } else { '' }
                $emergencyAckGeneratedAt = if ($emergencyAck.PSObject.Properties['generated_at']) { [string]$emergencyAck.generated_at } else { '' }
                $emergencyAckStatus = if ($emergencyAck.PSObject.Properties['status']) { [string]$emergencyAck.status } else { '' }
                $emergencyAckDecision = if ($emergencyAck.PSObject.Properties['decision']) { [string]$emergencyAck.decision } else { '' }
                $emergencyAckReason = if ($emergencyAck.PSObject.Properties['reason']) { [string]$emergencyAck.reason } else { '' }
                if ($emergencyAck.PSObject.Properties['acknowledged']) {
                    $emergencyAcknowledged = [bool]$emergencyAck.acknowledged
                }
                if (-not $emergencyAcknowledged) {
                    $emergencyAcknowledged =
                        [string]::Equals($emergencyAckStatus, 'acknowledged', [System.StringComparison]::OrdinalIgnoreCase) -or
                        [string]::Equals($emergencyAckStatus, 'accepted', [System.StringComparison]::OrdinalIgnoreCase) -or
                        [string]::Equals($emergencyAckDecision, 'investigating', [System.StringComparison]::OrdinalIgnoreCase) -or
                        [string]::Equals($emergencyAckDecision, 'accepted', [System.StringComparison]::OrdinalIgnoreCase)
                }

                $coordinationEscalationState.last_emergency_ack_request_id = $emergencyAckRequestId
                $coordinationEscalationState.last_emergency_ack_generated_at = $emergencyAckGeneratedAt
                $coordinationEscalationState.last_emergency_ack_status = $emergencyAckStatus
                $coordinationEscalationState.last_emergency_ack_decision = $emergencyAckDecision
                $coordinationEscalationState.last_emergency_ack_reason = $emergencyAckReason
                if ($emergencyAcknowledged -and -not [string]::IsNullOrWhiteSpace($emergencyAckRequestId) -and
                    [string]::Equals($emergencyAckRequestId, [string]$coordinationEscalationState.pending_emergency_request_id, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $coordinationEscalationState.last_emergency_acknowledged_at = if ($emergencyAck.PSObject.Properties['acknowledged_at']) { [string]$emergencyAck.acknowledged_at } else { (Get-Date).ToUniversalTime().ToString('o') }
                }

                Write-JsonFile -PathValue $localCoordinationEscalationStatePath -Payload $coordinationEscalationState
            }
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$coordinationEscalationState.pending_request_id)) {
            $existingCoordPayload = Read-JsonFileIfExists -PathValue $localCoordinationRequestPath
            $pendingRequestId = [string]$coordinationEscalationState.pending_request_id
            $existingResultPacket = Read-JsonFileIfExists -PathValue $localResultPath
            $existingResultRequestId = if ($existingResultPacket -and $existingResultPacket.PSObject.Properties['request_id']) { [string]$existingResultPacket.request_id } else { '' }
            $existingResultStatus = if ($existingResultPacket -and $existingResultPacket.PSObject.Properties['status']) { [string]$existingResultPacket.status } else { '' }
            $resolvedByTerminalResult =
                -not [string]::IsNullOrWhiteSpace($pendingRequestId) -and
                [string]::Equals($pendingRequestId, $existingResultRequestId, [System.StringComparison]::OrdinalIgnoreCase) -and
                (Test-IsTerminalExecutionStatus -Status $existingResultStatus)
            if ($resolvedByTerminalResult) {
                $resolveReason = ('Matched terminal result {0} already exists for {1}; stale coordination wait cleared automatically.' -f $existingResultStatus, $pendingRequestId)
                Clear-CoordinationEscalationState -State $coordinationEscalationState -Reason $resolveReason -RequestId $pendingRequestId
                Write-JsonFile -PathValue $localCoordinationEscalationStatePath -Payload $coordinationEscalationState
            }
            else {
            $coordinationTimeoutSeconds = 60
            if ($existingCoordPayload -and $existingCoordPayload.PSObject.Properties['required_ack'] -and $existingCoordPayload.required_ack -and $existingCoordPayload.required_ack.PSObject.Properties['timeout_seconds']) {
                $coordinationTimeoutSeconds = [int]$existingCoordPayload.required_ack.timeout_seconds
            }
            $pendingSinceUtc = Get-DateOrMinValue -Value ([string]$coordinationEscalationState.pending_since)
            if ($pendingSinceUtc -eq [datetime]::MinValue -and $existingCoordPayload -and $existingCoordPayload.PSObject.Properties['generated_at']) {
                $pendingSinceUtc = Get-DateOrMinValue -Value ([string]$existingCoordPayload.generated_at)
            }
            $elapsedPendingSeconds = if ($pendingSinceUtc -eq [datetime]::MinValue) { 0 } else { [int][math]::Floor((New-TimeSpan -Start $pendingSinceUtc -End (Get-Date).ToUniversalTime()).TotalSeconds) }
            $effectiveAckStatus = [string]$coordinationEscalationState.last_ack_status
            $effectiveAckDecision = [string]$coordinationEscalationState.last_ack_decision
            $effectiveAckReason = [string]$coordinationEscalationState.last_ack_reason
            $isStillPending = [string]::IsNullOrWhiteSpace($effectiveAckStatus) -or [string]::Equals($effectiveAckStatus, 'pending', [System.StringComparison]::OrdinalIgnoreCase) -or [string]::Equals($effectiveAckDecision, 'request_received', [System.StringComparison]::OrdinalIgnoreCase)
            if ($isStillPending -and $elapsedPendingSeconds -ge $coordinationTimeoutSeconds) {
                $pendingObjectiveId = if ($existingCoordPayload -and $existingCoordPayload.PSObject.Properties['objective_id']) { [string]$existingCoordPayload.objective_id } else { '' }
                $pendingIssueCode = if ($existingCoordPayload -and $existingCoordPayload.PSObject.Properties['issue_code']) { [string]$existingCoordPayload.issue_code } else { [string]$coordinationEscalationState.pending_issue_code }
                $pendingIssueSummary = if ($existingCoordPayload -and $existingCoordPayload.PSObject.Properties['issue_summary']) { [string]$existingCoordPayload.issue_summary } else { [string]$coordinationEscalationState.pending_issue_summary }
                $null = Publish-CoordinationPendingInquiry -CoordinationEscalationState $coordinationEscalationState -CoordinationEscalationStatePath $localCoordinationEscalationStatePath -DialogScriptAbs $dialogScriptAbs -EnvPath $envAbs -RequestId $pendingRequestId -ObjectiveId $pendingObjectiveId -IssueCode $pendingIssueCode -IssueSummary $pendingIssueSummary -AckStatus $effectiveAckStatus -AckDecision $effectiveAckDecision -AckReason $effectiveAckReason -TimeoutSeconds $coordinationTimeoutSeconds -ElapsedSeconds $elapsedPendingSeconds -CoordinationRequest $existingCoordPayload -BridgeRuntime $bridgeRuntime -PublishRemote:$publishDialogRemoteByDefault

                $emergencyTimeoutSeconds = [Math]::Max(120, [int]($coordinationTimeoutSeconds * 2))
                if ($elapsedPendingSeconds -ge $emergencyTimeoutSeconds) {
                    $null = Publish-EmergencyCoordinationRequest -CoordinationEscalationState $coordinationEscalationState -CoordinationEscalationStatePath $localCoordinationEscalationStatePath -LocalEmergencyRequestPath $localEmergencyRequestPath -RemoteEmergencyRequestPath $remoteEmergencyRequestPath -Connections $connections -ParentRequestId $pendingRequestId -ObjectiveId $pendingObjectiveId -IssueCode $pendingIssueCode -IssueSummary $pendingIssueSummary -AckStatus $effectiveAckStatus -AckDecision $effectiveAckDecision -AckReason $effectiveAckReason -CoordinationTimeoutSeconds $coordinationTimeoutSeconds -ElapsedSeconds $elapsedPendingSeconds -CoordinationRequest $existingCoordPayload -BridgeRuntime $bridgeRuntime
                }
            }
            }
        }
        elseif (-not [string]::IsNullOrWhiteSpace([string]$coordinationEscalationState.pending_emergency_request_id)) {
            $resolvedEmergencyObjectiveId = if ($requestPreview -and $requestPreview.PSObject.Properties['objective_id']) { [string]$requestPreview.objective_id } else { '' }
            $null = Publish-ResolvedEmergencyCoordination -CoordinationEscalationState $coordinationEscalationState -CoordinationEscalationStatePath $localCoordinationEscalationStatePath -LocalEmergencyRequestPath $localEmergencyRequestPath -RemoteEmergencyRequestPath $remoteEmergencyRequestPath -Connections $connections -ResolutionReason 'Coordination request is no longer pending, so the emergency coordination lane can stand down.' -ObjectiveId $resolvedEmergencyObjectiveId
        }

        # Always auto-resolve stale stalled-regression coordination when regression is green,
        # even during polling cycles that skip task execution.
        $loopRegressionSnapshot = Get-RegressionSnapshot -CurrentBuildStatePath $currentBuildStatePath
        if ($loopRegressionSnapshot.available -and [int]$loopRegressionSnapshot.failed -le 0) {
            $hasPendingEscalation = (-not [string]::IsNullOrWhiteSpace([string]$coordinationEscalationState.pending_request_id)) -or ([int]$coordinationEscalationState.emit_count -gt 0)
            $hasStaleRequestArtifact = Test-Path -Path $localCoordinationRequestPath
            if ($hasStaleRequestArtifact) {
                # Only treat as stale if the artifact is regression-related; non-regression requests
                # (e.g. handoff_artifact_alias_detected) must not be auto-resolved by regression-green logic.
                $existingCoordPayload = Read-JsonFileIfExists -PathValue $localCoordinationRequestPath
                $hasStaleRequestArtifact = Test-CoordinationIsRegressionRelated -CoordinationRequest $existingCoordPayload -CoordinationEscalationState $coordinationEscalationState
            }
            if ($hasPendingEscalation -or $hasStaleRequestArtifact) {
                $loopResolveReason = "Regression failures are zero; stale coordination escalation has been auto-resolved."
                Clear-CoordinationEscalationState -State $coordinationEscalationState -Reason $loopResolveReason
                Write-JsonFile -PathValue $localCoordinationEscalationStatePath -Payload $coordinationEscalationState

                # Only overwrite the coordination request file when it is a regression-related artifact.
                # Non-regression requests (e.g. handoff_artifact_alias_detected) remain intact so MIM
                # can still read and acknowledge them, even after regression becomes green.
                if ($hasStaleRequestArtifact) {
                    $loopCoordinationResolved = [pscustomobject]@{
                        generated_at = (Get-Date).ToUniversalTime().ToString("o")
                        source = "tod-mim-coordination-request-v1"
                        status = "resolved"
                        priority = "none"
                        escalation_level = 0
                        request_id = [string]$coordinationEscalationState.last_ack_request_id
                        objective_id = "objective-75"
                        issue_code = "stalled_regression_no_delta_resolved"
                        issue_summary = "Regression is green; prior stalled-regression escalation is closed automatically."
                        evidence = [pscustomobject]@{
                            failed = [int]$loopRegressionSnapshot.failed
                            total = [int]$loopRegressionSnapshot.total
                            regression_signature = [string]$loopRegressionSnapshot.signature
                        }
                        requested_action = "none"
                        resolution_reason = $loopResolveReason
                        resolved_at = (Get-Date).ToUniversalTime().ToString("o")
                        bridge_runtime = $bridgeRuntime
                    }
                    Write-JsonFile -PathValue $localCoordinationRequestPath -Payload $loopCoordinationResolved
                    try {
                        $loopCoordinationResolvedJson = Get-Content -Path $localCoordinationRequestPath -Raw
                        Write-RemoteFileFromText -Connections $connections -RemotePath $remoteCoordinationRequestPath -Content $loopCoordinationResolvedJson
                    }
                    catch {
                        Write-Warning ("[TOD-LISTENER] Unable to publish loop-level resolved coordination status to remote: {0}" -f $_.Exception.Message)
                    }
                }
            }
        }

        if (-not $requestExists) {
            $blockedRecovery = Invoke-BlockedRecoveryContinuationIfNeeded -ListenerState $listenerState -ListenerStatePath $listenerStatePath -TodScript $todScriptAbs -IdleWakeupState $idleWakeupState -IdleWakeupStatePath $localIdleWakeupStatePath
            if ([bool]$blockedRecovery.resumed) {
                Publish-CommandStatus -ListenerState $listenerState -ListenerStatePath $listenerStatePath -LocalPath $localCommandStatusPath -RemotePath $remoteCommandStatusPath -Connections $connections -Status 'recovered_execution_resumed' -Detail 'Execution readiness recovered; resumed the previously blocked task automatically.' -RequestId ([string]$blockedRecovery.request_id) -TaskId ([string]$blockedRecovery.task_id) -CorrelationId ([string]$listenerState.blocked_resume_correlation_id) -Action 'engineer-run' -ExecutionReadiness $blockedRecovery.readiness
                Update-ListenerHeartbeat -State $listenerState -StatePath $listenerStatePath -CycleStartedAt $cycleStartedAt
                $cadencePlan = Update-CadencePlan -ListenerState $listenerState -ListenerStatePath $listenerStatePath -CycleClassification 'recovered_execution_resumed' -RetryReason 'none' -BasePollSeconds $PollSeconds
                Add-LoopJournalEntry -LocalJournalPath $localJournalPath -RequestId ([string]$blockedRecovery.request_id) -ObjectiveId ([string]$blockedRecovery.objective_id) -ExecutionStatus 'recovered_execution_resumed' -Action 'engineer-run' -ExecutionReadiness $blockedRecovery.readiness -CycleClassification 'recovered_execution_resumed' -RetryReason 'none' -CadencePlan $cadencePlan
                if ($RunOnce) { break }
                Start-Sleep -Seconds ([int]$cadencePlan.sleep_seconds)
                continue
            }

            Write-Host "[TOD-LISTENER] No task request packet found."
            Update-ListenerHeartbeat -State $listenerState -StatePath $listenerStatePath -CycleStartedAt $cycleStartedAt
            $cadencePlan = Update-CadencePlan -ListenerState $listenerState -ListenerStatePath $listenerStatePath -CycleClassification "no_new_work" -RetryReason "no_new_work" -BasePollSeconds $PollSeconds
            Add-LoopJournalEntry -LocalJournalPath $localJournalPath -RequestId "" -ObjectiveId "" -ExecutionStatus "no_new_work" -CycleClassification "no_new_work" -RetryReason "no_new_work" -CadencePlan $cadencePlan
            Invoke-IdleWakeupIfNeeded -ListenerState $listenerState -IdleWakeupState $idleWakeupState -IdleWakeupStatePath $localIdleWakeupStatePath -TodScript $todScriptAbs -SyncScript $syncScriptAbs -ReadinessScript $readinessScriptAbs -HostAlias $hostAlias -RemoteRoot $RemoteRoot -SyncStageRoot $SyncStageDir -IdleThreshold $IdleWakeupSeconds -Cooldown $IdleWakeupCooldownSeconds -RunOnce:$RunOnce
            if ($RunOnce) { break }
            Start-Sleep -Seconds ([int]$cadencePlan.sleep_seconds)
            continue
        }

        $request = if ($null -ne $requestPreview) { $requestPreview } else { Read-JsonFileIfExists -PathValue $localRequestPath }
        if ($null -eq $request) {
            Write-Host "[TOD-LISTENER] Request file exists but is not valid JSON."
            Update-ListenerHeartbeat -State $listenerState -StatePath $listenerStatePath -CycleStartedAt $cycleStartedAt
            $cadencePlan = Update-CadencePlan -ListenerState $listenerState -ListenerStatePath $listenerStatePath -CycleClassification "invalid_request" -RetryReason "none" -BasePollSeconds $PollSeconds
            Add-LoopJournalEntry -LocalJournalPath $localJournalPath -RequestId "" -ObjectiveId "" -ExecutionStatus "invalid_request" -CycleClassification "invalid_request" -RetryReason "none" -CadencePlan $cadencePlan
            if ($RunOnce) { break }
            Start-Sleep -Seconds ([int]$cadencePlan.sleep_seconds)
            continue
        }

        $requestId = Get-RequestIdentifier -Request $request
        if ([string]::IsNullOrWhiteSpace($requestId)) {
            $requestId = "REQ-" + ([guid]::NewGuid().ToString("N").Substring(0, 10).ToUpperInvariant())
        }

        $requestObjectiveId = Get-ExpectedObjectiveFromRequest -Request $request
        $requestOrderingInfo = Get-RequestOrderingInfo -Request $request -RequestId $requestId -FallbackObjectiveId $requestObjectiveId
        $requestOrderingSourceField = if ($requestOrderingInfo -and $requestOrderingInfo.PSObject.Properties['source_field']) { [string]$requestOrderingInfo.source_field } else { 'request_id' }
        if ($requestOrderingInfo) {
            $null = Update-TaskHighWatermark -State $listenerState -CandidateInfo $requestOrderingInfo
        }
        $maxObservedOrdinal = Get-ObjectiveHighWatermark -State $listenerState -JournalPath $localJournalPath -ObjectiveId $requestObjectiveId
        $existingDecision = Read-JsonFileIfExists -PathValue $localDecisionPath
        $decisionGeneratedAtRaw = if ($existingDecision -and $existingDecision.PSObject.Properties['generated_at']) { [string]$existingDecision.generated_at } else { '' }
        $lastExecutionAtRaw = if ($listenerState.PSObject.Properties['last_execution_at']) { [string]$listenerState.last_execution_at } else { '' }
        $decisionGeneratedAt = [datetime]::MinValue
        $lastExecutionAt = [datetime]::MinValue
        $decisionHasTimestamp = [datetime]::TryParse($decisionGeneratedAtRaw, [ref]$decisionGeneratedAt)
        $lastExecutionHasTimestamp = [datetime]::TryParse($lastExecutionAtRaw, [ref]$lastExecutionAt)
        $decisionNewerThanLastExecution = $decisionHasTimestamp -and ((-not $lastExecutionHasTimestamp) -or $decisionGeneratedAt -gt $lastExecutionAt)
        $replayDecisionMatchesRequest = $existingDecision -and
            [string]::Equals((Get-NonEmptyPacketValue -Primary (Get-ObjectFieldText -InputObject $existingDecision -FieldName 'request_id') -Fallback ''), $requestId, [System.StringComparison]::OrdinalIgnoreCase) -and
            [string]::Equals((Get-NonEmptyPacketValue -Primary (Get-ObjectFieldText -InputObject $existingDecision -FieldName 'decision_outcome') -Fallback ''), 'execute', [System.StringComparison]::OrdinalIgnoreCase) -and
            [string]::Equals((Get-NonEmptyPacketValue -Primary (Get-ObjectFieldText -InputObject $existingDecision -FieldName 'canonical_objective_id') -Fallback ''), $requestObjectiveId, [System.StringComparison]::OrdinalIgnoreCase) -and
            [string]::Equals((Get-NonEmptyPacketValue -Primary (Get-ObjectFieldText -InputObject $existingDecision -FieldName 'execution_state') -Fallback ''), 'ready_to_execute', [System.StringComparison]::OrdinalIgnoreCase)
        $allowAlignedReplay = $replayDecisionMatchesRequest -and $decisionNewerThanLastExecution
        $requestTaskIdForReplay = Get-NonEmptyPacketValue -Primary (Get-ObjectFieldText -InputObject $request -FieldName 'task_id') -Fallback $requestId
        $scopedForcedReplay = Get-ScopedForcedReplayMatch -ListenerState $listenerState -RequestId $requestId -TaskId $requestTaskIdForReplay -ObjectiveId $requestObjectiveId

        if ($allowAlignedReplay) {
            $staleGuardObjective = if ($listenerState.PSObject.Properties['last_stale_guard'] -and $null -ne $listenerState.last_stale_guard -and $listenerState.last_stale_guard.PSObject.Properties['objective_id']) { [string]$listenerState.last_stale_guard.objective_id } else { '' }
            $dedupMatchesRequest = [string]::Equals([string]$listenerState.last_processed_request_id, $requestId, [System.StringComparison]::OrdinalIgnoreCase)
            $staleGuardMismatchedObjective = -not [string]::IsNullOrWhiteSpace($staleGuardObjective) -and -not [string]::Equals($staleGuardObjective, $requestObjectiveId, [System.StringComparison]::OrdinalIgnoreCase)
            if ($dedupMatchesRequest -or $staleGuardMismatchedObjective) {
                $listenerState.last_processed_request_id = ''
                $listenerState.last_processed_request_signature = ''
                $listenerState.last_stale_guard = $null
                $listenerState.last_command_status = 'replay_override_armed'
                $listenerState.last_command_detail = 'Cleared stale/dedup listener memory because a fresh aligned execute decision requires a bounded replay.'
                Write-JsonFile -PathValue $listenerStatePath -Payload $listenerState
                Write-Host ("[TOD-LISTENER] Cleared stale/dedup state for aligned replay of request {0}." -f $requestId)
            }
        }

        if (-not $allowAlignedReplay -and $null -eq $scopedForcedReplay -and (Test-RequestOrderingIsStale -RequestOrderingInfo $requestOrderingInfo -HighWatermark $maxObservedOrdinal)) {
            $requestTaskIdForStaleGuard = Get-NonEmptyPacketValue -Primary (Get-ObjectFieldText -InputObject $request -FieldName 'task_id') -Fallback $requestId
            $staleGuard = New-StaleGuardMetadata -Decision 'stale_request_ignored' -RequestId $requestId -TaskId $requestTaskIdForStaleGuard -ObjectiveId $requestObjectiveId -RequestOrdinalInfo $requestOrderingInfo -RequestOrdinalSourceField $requestOrderingSourceField -HighWatermark $maxObservedOrdinal -TriggerSequence (Get-ObjectFieldLong -InputObject $livenessTrigger -FieldName 'sequence')
            $effectiveTaskId = [string]$maxObservedOrdinal.raw
            $bridgeTaskTitle = ''
            if ($request.PSObject.Properties['title'] -and -not [string]::IsNullOrWhiteSpace([string]$request.title)) {
                $bridgeTaskTitle = [string]$request.title
            }
            $bridgeTaskMirror = Sync-LocalTaskMirror -TaskId $effectiveTaskId -ObjectiveId $requestObjectiveId -Title $bridgeTaskTitle -Scope 'Synchronized from bridge runtime high-watermark while stale backfill request was ignored.' -Status 'in_progress' -TaskCategory 'bridge_runtime' -Source 'bridge_runtime_sync'
            if ([bool]$bridgeTaskMirror.changed) {
                Write-Host ("[TOD-LISTENER] Effective bridge task synchronized to {0}." -f [string]$bridgeTaskMirror.task_id)
            }
            $effectiveBridgeRuntime = Get-BridgeRuntimeStatus -CurrentTaskId $effectiveTaskId -CurrentCorrelationId ""
            $effectiveObjectiveRaw = Get-ObjectFieldText -InputObject $request -FieldName 'objective_id'
            if ([string]::IsNullOrWhiteSpace($effectiveObjectiveRaw) -and -not [string]::IsNullOrWhiteSpace($requestObjectiveId)) {
                $effectiveObjectiveRaw = ("objective-{0}" -f $requestObjectiveId)
            }
            $staleAck = [pscustomobject]@{
                generated_at = (Get-Date).ToUniversalTime().ToString('o')
                source = 'tod-mim-task-ack-v1'
                status = 'stale_ignored'
                ack_status = 'stale_ignored'
                ack_reason_code = 'stale_request_ignored'
                request_id = $requestId
                correlation_id = Get-NonEmptyPacketValue -Primary (Get-ObjectFieldText -InputObject $request -FieldName 'correlation_id') -Fallback $requestId
                objective = $effectiveObjectiveRaw
                objective_id = $effectiveObjectiveRaw
                task = Get-NonEmptyPacketValue -Primary (Get-ObjectFieldText -InputObject $request -FieldName 'task_id') -Fallback $requestId
                task_id = Get-NonEmptyPacketValue -Primary (Get-ObjectFieldText -InputObject $request -FieldName 'task_id') -Fallback $requestId
                note = 'Request ignored because a higher authoritative task ordinal is already active.'
                bridge_runtime = $effectiveBridgeRuntime
            }
            $null = Add-ContractPacketEnvelope -Packet $staleAck -BindingMetadata $contractBinding -PacketType 'tod-mim-task-ack-v1' -MessageKind 'ack' -ObjectiveId $effectiveObjectiveRaw -TaskId ([string]$staleAck.task_id) -RequestId $requestId -CorrelationId ([string]$staleAck.correlation_id)
            $null = Add-SequenceRuntimeFields -Packet $staleAck -TriggerPacket $livenessTrigger -ListenerState $listenerState -ListenerStatePath $listenerStatePath
            $staleAckValidation = Test-ContractRuntimePacket -PythonCommand $pythonCommand -ValidatorScript $runtimeContractValidatorAbs -BindingMetadata $contractBinding -PacketKind 'ack' -Packet $staleAck
            if (-not [bool]$staleAckValidation.passed) {
                $violation = Publish-RuntimeContractViolation -ViolationPath $localRuntimeViolationPath -StatePath $localRuntimeBindingStatePath -BindingMetadata $contractBinding -PacketKind 'ack' -Packet $staleAck -ValidationResult $staleAckValidation
                Register-RuntimeValidationResult -StatePath $localRuntimeBindingStatePath -BindingMetadata $contractBinding -PacketKind 'ack' -Packet $staleAck -ValidationResult $staleAckValidation -State 'violation' | Out-Null
                Publish-CommandStatus -ListenerState $listenerState -ListenerStatePath $listenerStatePath -LocalPath $localCommandStatusPath -RemotePath $remoteCommandStatusPath -Connections $connections -Status 'contract_violation_rejected' -Detail ('Rejected stale-ignore ACK because runtime contract validation failed: {0}' -f (($violation.violations | ForEach-Object { [string]$_.code + ':' + [string]$_.detail }) -join '; ')) -RequestId $requestId -TaskId ([string]$staleAck.task_id) -CorrelationId ([string]$staleAck.correlation_id) -TriggerPacket $livenessTrigger -BridgeRuntime $effectiveBridgeRuntime -StaleGuard $staleGuard
                $null = Publish-ContractViolationCoordination -CoordinationEscalationState $coordinationEscalationState -CoordinationEscalationStatePath $localCoordinationEscalationStatePath -LocalCoordinationRequestPath $localCoordinationRequestPath -RemoteCoordinationRequestPath $remoteCoordinationRequestPath -Connections $connections -RequestId $requestId -ObjectiveId $requestObjectiveId -TaskId ([string]$staleAck.task_id) -CorrelationId ([string]$staleAck.correlation_id) -PacketKind 'ack' -Packet $staleAck -Violation $violation -Action ([string]$staleAck.action) -BridgeRuntime $effectiveBridgeRuntime -RuntimeViolationPath $localRuntimeViolationPath
                Update-ListenerHeartbeat -State $listenerState -StatePath $listenerStatePath -CycleStartedAt $cycleStartedAt
                $cadencePlan = Update-CadencePlan -ListenerState $listenerState -ListenerStatePath $listenerStatePath -CycleClassification 'contract_violation_rejected' -RetryReason 'failure' -BasePollSeconds $PollSeconds
                Add-LoopJournalEntry -LocalJournalPath $localJournalPath -RequestId $requestId -ObjectiveId $requestObjectiveId -AckStatus 'contract_violation_rejected' -ExecutionStatus 'contract_violation_rejected' -CycleClassification 'contract_violation_rejected' -RetryReason 'failure' -CadencePlan $cadencePlan
                if ($RunOnce) { break }
                Start-Sleep -Seconds ([int]$cadencePlan.sleep_seconds)
                continue
            }
            Register-RuntimeValidationResult -StatePath $localRuntimeBindingStatePath -BindingMetadata $contractBinding -PacketKind 'ack' -Packet $staleAck -ValidationResult $staleAckValidation -State 'active' | Out-Null
            if ([string]::Equals([string]$coordinationEscalationState.pending_issue_code, 'runtime_contract_violation_ack', [System.StringComparison]::OrdinalIgnoreCase)) {
                $null = Publish-ResolvedCoordination -CoordinationEscalationState $coordinationEscalationState -CoordinationEscalationStatePath $localCoordinationEscalationStatePath -LocalCoordinationRequestPath $localCoordinationRequestPath -RemoteCoordinationRequestPath $remoteCoordinationRequestPath -Connections $connections -RequestId $requestId -ObjectiveId $requestObjectiveId -IssueCode 'runtime_contract_violation_ack_resolved' -IssueSummary 'TOD auto-closed the prior ACK contract-violation notice after ACK validation succeeded again.' -Evidence ([pscustomobject]@{ packet_kind = 'ack'; task_id = [string]$staleAck.task_id; correlation_id = [string]$staleAck.correlation_id; status = [string]$staleAck.status; resolution_basis = 'stale_ack_validation_passed' }) -ResolutionReason 'ACK validation now passes; prior contract delta is resolved.' -BridgeRuntime $effectiveBridgeRuntime -ResolutionDecision 'auto_resolved_contract_valid'
            }
            Publish-ExecutionLock -LocalPath $localExecutionLockPath -RemotePath $remoteExecutionLockPath -Connections $connections -ObjectiveId $requestObjectiveId -TaskId ([string]$staleAck.task_id) -RequestId $requestId -CorrelationId ([string]$staleAck.correlation_id) -Status ([string]$staleAck.status) -BridgeRuntime $effectiveBridgeRuntime
            Write-JsonFile -PathValue $localAckPath -Payload $staleAck
            $staleAckJson = Get-Content -Path $localAckPath -Raw
            Write-RemoteFileFromText -Connections $connections -RemotePath $remoteAckPath -Content $staleAckJson
            Publish-TriggerAck -ListenerState $listenerState -ListenerStatePath $listenerStatePath -Connections $connections -LocalPath $localTriggerAckPath -RemotePath $remoteTriggerAckPath -RequestId $requestId -CurrentTaskId $effectiveTaskId -CurrentCorrelationId "" -TriggerPacket $livenessTrigger -BridgeRuntime $effectiveBridgeRuntime
            Write-Host ("[TOD-LISTENER] Request {0} ignored as stale backfill; objective {1} already reached higher task ordinal {2} via {3}." -f $requestId, $requestObjectiveId, [long]$maxObservedOrdinal.ordinal, $effectiveTaskId)
            Publish-CommandStatus -ListenerState $listenerState -ListenerStatePath $listenerStatePath -LocalPath $localCommandStatusPath -RemotePath $remoteCommandStatusPath -Connections $connections -Status "stale_request_ignored" -Detail ("Ignored stale backfill request {0}; authoritative current task remains {1}." -f [string]$requestId, $effectiveTaskId) -RequestId $requestId -TaskId ([string]$staleAck.task_id) -CorrelationId ([string]$staleAck.correlation_id) -AckPacket $staleAck -TriggerPacket $livenessTrigger -BridgeRuntime $effectiveBridgeRuntime -StaleGuard $staleGuard
            Update-ListenerHeartbeat -State $listenerState -StatePath $listenerStatePath -CycleStartedAt $cycleStartedAt
            $cadencePlan = Update-CadencePlan -ListenerState $listenerState -ListenerStatePath $listenerStatePath -CycleClassification "stale_backfill_ignored" -RetryReason "duplicate_seen" -BasePollSeconds $PollSeconds
            Add-LoopJournalEntry -LocalJournalPath $localJournalPath -RequestId $requestId -ObjectiveId $requestObjectiveId -AckStatus ([string]$staleAck.status) -ExecutionStatus "stale_backfill_ignored" -CycleClassification "stale_backfill_ignored" -RetryReason "duplicate_seen" -CadencePlan $cadencePlan
            if ($RunOnce) { break }
            Start-Sleep -Seconds ([int]$cadencePlan.sleep_seconds)
            continue
        }

        $objectiveSync = Sync-LocalObjectiveFromRequest -Request $request
        if ([bool]$objectiveSync.changed) {
            Write-Host ("[TOD-LISTENER] Local objective synchronized to {0}." -f [string]$objectiveSync.objective_id)
        }

        $taskSync = Sync-LocalTaskFromRequest -Request $request
        if ([bool]$taskSync.changed) {
            Write-Host ("[TOD-LISTENER] Local task synchronized to {0}." -f [string]$taskSync.task_id)
        }

        $requestSignature = Get-RequestSignature -RequestPath $localRequestPath -SemanticTaskPacket
        $goOrderSignature = Get-RequestSignature -RequestPath $localGoOrderPath -SemanticTaskPacket
        $requestTaskId = Get-NonEmptyPacketValue -Primary (Get-ObjectFieldText -InputObject $request -FieldName "task_id") -Fallback $requestId
        $requestCorrelationId = Get-NonEmptyPacketValue -Primary (Get-ObjectFieldText -InputObject $request -FieldName "correlation_id") -Fallback $requestId
        $triggerEventSignature = ((@(
                    [string]$requestId,
                    [string]$requestSignature,
                    [string]$goOrderSignature
                ) -join "|").ToLowerInvariant())
        $lastTriggerEventSignature = if ($listenerState.PSObject.Properties["last_trigger_event_signature"]) { [string]$listenerState.last_trigger_event_signature } else { "" }

        $triggerEventChanged = -not [string]::Equals($triggerEventSignature, $lastTriggerEventSignature, [System.StringComparison]::OrdinalIgnoreCase)
        if ($triggerEventChanged) {
            Publish-TriggerAck -ListenerState $listenerState -ListenerStatePath $listenerStatePath -Connections $connections -LocalPath $localTriggerAckPath -RemotePath $remoteTriggerAckPath -RequestId $requestId -CurrentTaskId $currentTaskId -CurrentCorrelationId $currentCorrelationId -TriggerPacket $livenessTrigger -BridgeRuntime $bridgeRuntime
            $listenerState.last_trigger_event_signature = $triggerEventSignature
            Publish-CommandStatus -ListenerState $listenerState -ListenerStatePath $listenerStatePath -LocalPath $localCommandStatusPath -RemotePath $remoteCommandStatusPath -Connections $connections -Status "command_observed" -Detail "Pulled latest MIM task/go-order command files." -RequestId $requestId -TaskId $requestTaskId -CorrelationId $requestCorrelationId -RequestSignature $requestSignature -GoOrderSignature $goOrderSignature -TriggerPacket $livenessTrigger -BridgeRuntime $bridgeRuntime
            Update-ListenerHeartbeat -State $listenerState -StatePath $listenerStatePath -CycleStartedAt $cycleStartedAt
            if ($messageLedgerEnabled) {
                Invoke-LedgerObserveShadowWrite `
                    -RequestId $requestId `
                    -TaskId $requestTaskId `
                    -CorrelationId $requestCorrelationId `
                    -SourceArtifact 'MIM_TOD_TASK_REQUEST.latest.json' `
                    -PythonCommand $pythonCommand `
                    -LedgerScriptAbs $ledgerScriptAbs `
                    -LedgerDbAbs $ledgerDbAbs `
                    -LedgerMigrationAbs $ledgerMigrationAbs `
                    -LedgerStatusAbs $ledgerStatusAbs
            }
        }

        # Quarantine guard: if this request_id has been quarantined after repeated failures, skip execution entirely.
        if (-not [string]::IsNullOrWhiteSpace([string]$quarantineState.quarantined_request_id) -and
            [string]::Equals($requestId, [string]$quarantineState.quarantined_request_id, [System.StringComparison]::OrdinalIgnoreCase)) {
            Write-Host ("[TOD-LISTENER] Request {0} is QUARANTINED after {1} consecutive fail cycles. Skipping." -f $requestId, [int]$quarantineState.fail_cycle_count)
            Update-ListenerHeartbeat -State $listenerState -StatePath $listenerStatePath -CycleStartedAt $cycleStartedAt
            $cadencePlan = Update-CadencePlan -ListenerState $listenerState -ListenerStatePath $listenerStatePath -CycleClassification "quarantined_failure_retry" -RetryReason "failure" -BasePollSeconds $PollSeconds
            Add-LoopJournalEntry -LocalJournalPath $localJournalPath -RequestId $requestId -ObjectiveId $requestObjectiveId -ExecutionStatus "quarantined" -CycleClassification "quarantined_failure_retry" -RetryReason "failure" -CadencePlan $cadencePlan
            Invoke-IdleWakeupIfNeeded -ListenerState $listenerState -IdleWakeupState $idleWakeupState -IdleWakeupStatePath $localIdleWakeupStatePath -TodScript $todScriptAbs -SyncScript $syncScriptAbs -ReadinessScript $readinessScriptAbs -HostAlias $hostAlias -RemoteRoot $RemoteRoot -SyncStageRoot $SyncStageDir -IdleThreshold $IdleWakeupSeconds -Cooldown $IdleWakeupCooldownSeconds -RunOnce:$RunOnce
            if ($RunOnce) { break }
            Start-Sleep -Seconds ([int]$cadencePlan.sleep_seconds)
            continue
        }

        $lastProcessedSignature = if ($listenerState.PSObject.Properties["last_processed_request_signature"]) { [string]$listenerState.last_processed_request_signature } else { "" }

        if ($null -eq $scopedForcedReplay -and
            [string]::Equals($requestId, [string]$listenerState.last_processed_request_id, [System.StringComparison]::OrdinalIgnoreCase) -and
            -not [string]::IsNullOrWhiteSpace($requestSignature) -and
            [string]::Equals($requestSignature, $lastProcessedSignature, [System.StringComparison]::OrdinalIgnoreCase) -and
            -not [bool]$objectiveSync.changed -and
            -not [bool]$taskSync.changed) {
            $blockedRecovery = Invoke-BlockedRecoveryContinuationIfNeeded -ListenerState $listenerState -ListenerStatePath $listenerStatePath -TodScript $todScriptAbs -IdleWakeupState $idleWakeupState -IdleWakeupStatePath $localIdleWakeupStatePath
            if ([bool]$blockedRecovery.resumed) {
                Publish-CommandStatus -ListenerState $listenerState -ListenerStatePath $listenerStatePath -LocalPath $localCommandStatusPath -RemotePath $remoteCommandStatusPath -Connections $connections -Status 'recovered_execution_resumed' -Detail 'Readiness recovered for a previously processed blocked request; resumed the mirrored task automatically.' -RequestId ([string]$blockedRecovery.request_id) -TaskId ([string]$blockedRecovery.task_id) -CorrelationId ([string]$listenerState.blocked_resume_correlation_id) -RequestSignature $requestSignature -GoOrderSignature $goOrderSignature -Action 'engineer-run' -ExecutionReadiness $blockedRecovery.readiness -TriggerPacket $livenessTrigger -BridgeRuntime $bridgeRuntime
                Update-ListenerHeartbeat -State $listenerState -StatePath $listenerStatePath -CycleStartedAt $cycleStartedAt
                $cadencePlan = Update-CadencePlan -ListenerState $listenerState -ListenerStatePath $listenerStatePath -CycleClassification 'recovered_execution_resumed' -RetryReason 'none' -BasePollSeconds $PollSeconds
                Add-LoopJournalEntry -LocalJournalPath $localJournalPath -RequestId ([string]$blockedRecovery.request_id) -ObjectiveId ([string]$blockedRecovery.objective_id) -ExecutionStatus 'recovered_execution_resumed' -Action 'engineer-run' -ExecutionReadiness $blockedRecovery.readiness -CycleClassification 'recovered_execution_resumed' -RetryReason 'none' -CadencePlan $cadencePlan
                if ($RunOnce) { break }
                Start-Sleep -Seconds ([int]$cadencePlan.sleep_seconds)
                continue
            }

            $existingResultPacket = Read-JsonFileIfExists -PathValue $localResultPath
            if ($existingResultPacket -and
                $existingResultPacket.PSObject.Properties['request_id'] -and
                [string]::Equals([string]$existingResultPacket.request_id, [string]$requestId, [System.StringComparison]::OrdinalIgnoreCase)) {
                $null = Sync-LocalExecutionOutcome -TaskId $requestTaskId -ObjectiveId $requestObjectiveId -ResultPacket $existingResultPacket
            }
            if (-not [string]::Equals($lastSkipLogId, $requestId, [System.StringComparison]::OrdinalIgnoreCase)) {
                Write-Host ("[TOD-LISTENER] Request {0} already processed. Skipping." -f $requestId)
                $lastSkipLogId = $requestId
            }
            Publish-CommandStatus -ListenerState $listenerState -ListenerStatePath $listenerStatePath -LocalPath $localCommandStatusPath -RemotePath $remoteCommandStatusPath -Connections $connections -Status "already_processed" -Detail "MIM command was received, matched the last processed request signature, and was intentionally deduplicated." -RequestId $requestId -TaskId $requestTaskId -CorrelationId $requestCorrelationId -RequestSignature $requestSignature -GoOrderSignature $goOrderSignature -TriggerPacket $livenessTrigger -BridgeRuntime $bridgeRuntime
            Update-ListenerHeartbeat -State $listenerState -StatePath $listenerStatePath -CycleStartedAt $cycleStartedAt
            $cadencePlan = Update-CadencePlan -ListenerState $listenerState -ListenerStatePath $listenerStatePath -CycleClassification "duplicate_seen" -RetryReason "duplicate_seen" -BasePollSeconds $PollSeconds
            Add-LoopJournalEntry -LocalJournalPath $localJournalPath -RequestId $requestId -ObjectiveId $requestObjectiveId -ExecutionStatus "already_processed" -CycleClassification "duplicate_seen" -RetryReason "duplicate_seen" -CadencePlan $cadencePlan
            Invoke-IdleWakeupIfNeeded -ListenerState $listenerState -IdleWakeupState $idleWakeupState -IdleWakeupStatePath $localIdleWakeupStatePath -TodScript $todScriptAbs -SyncScript $syncScriptAbs -ReadinessScript $readinessScriptAbs -HostAlias $hostAlias -RemoteRoot $RemoteRoot -SyncStageRoot $SyncStageDir -IdleThreshold $IdleWakeupSeconds -Cooldown $IdleWakeupCooldownSeconds -RunOnce:$RunOnce
            if ($RunOnce) { break }
            Start-Sleep -Seconds ([int]$cadencePlan.sleep_seconds)
            continue
        }

        $lastSkipLogId = ""

        $goOrder = Read-JsonFileIfExists -PathValue $localGoOrderPath
        $reviewDecision = Read-JsonFileIfExists -PathValue $localReviewPath
        $goAllowed = $true
        if ($null -ne $goOrder -and -not $ProcessWithoutGoOrder) {
            if ($goOrder.PSObject.Properties["authorization"] -and -not [string]::IsNullOrWhiteSpace([string]$goOrder.authorization)) {
                $goAllowed = ([string]$goOrder.authorization).Trim().ToLowerInvariant() -eq "go"
            }
            elseif ($goOrder.PSObject.Properties["allow_execute"]) {
                $goAllowed = [bool]$goOrder.allow_execute
            }
            elseif ($goOrder.PSObject.Properties["go"]) {
                $goAllowed = [bool]$goOrder.go
            }
        }

        $preDecisionSyncError = Invoke-SharedStateSyncRefresh -SyncScriptAbs $syncScriptAbs -HostAlias $hostAlias -RemoteRoot $RemoteRoot -SyncStageRoot $SyncStageDir -ListenerRequestPath $localRequestPath -Reason 'pre-execution decision'
        $integrationStatus = Get-RequestAlignedIntegrationStatus -IntegrationStatus (Read-JsonFileIfExists -PathValue $integrationStatusPath) -Request $request
        $requestDecision = Get-MimRequestDecision -Request $request -GoOrder $goOrder -IntegrationStatus $integrationStatus -ReviewDecision $reviewDecision -TodScriptAbs $todScriptAbs -ProcessWithoutGoOrder:$ProcessWithoutGoOrder -SharedStateSyncError $preDecisionSyncError
        Set-ListenerReadinessSnapshot -ListenerState $listenerState -ReadinessTrace $requestDecision.execution_readiness
        Publish-ExecutionDecision -LocalPath $localDecisionPath -RemotePath $remoteDecisionPath -Connections $connections -DecisionPayload $requestDecision -RequestId $requestId -TaskId $requestTaskId -CorrelationId $requestCorrelationId -TriggerPacket $livenessTrigger -BridgeRuntime $bridgeRuntime

        if (-not [string]::Equals([string]$requestDecision.decision_outcome, 'execute', [System.StringComparison]::OrdinalIgnoreCase)) {
            if ([string]::Equals([string]$requestDecision.reason_code, 'execution_readiness_blocked', [System.StringComparison]::OrdinalIgnoreCase)) {
                Save-BlockedRecoveryState -ListenerState $listenerState -RequestId $requestId -RequestSignature $requestSignature -TaskId $requestTaskId -ObjectiveId $requestObjectiveId -CorrelationId $requestCorrelationId -Action $(if ($request.PSObject.Properties['tod_action']) { [string]$request.tod_action } elseif ($request.PSObject.Properties['action']) { [string]$request.action } else { 'run-bridge-request' }) -ReasonCode ([string]$requestDecision.reason_code) -Summary ([string]$requestDecision.summary) -ReadinessTrace $requestDecision.execution_readiness
                Write-JsonFile -PathValue $listenerStatePath -Payload $listenerState
            }
            elseif ([string]::Equals([string]$listenerState.blocked_resume_request_id, [string]$requestId, [System.StringComparison]::OrdinalIgnoreCase)) {
                Clear-BlockedRecoveryState -ListenerState $listenerState
                Write-JsonFile -PathValue $listenerStatePath -Payload $listenerState
            }

            $status = switch ([string]$requestDecision.decision_outcome) {
                'acknowledge_and_wait_on_dependency' { 'waiting_dependency' }
                'reject_with_specific_policy_reason' { 'policy_rejected' }
                'escalate_hard_boundary' { 'hard_boundary_escalated' }
                default { 'decision_recorded' }
            }
            Write-Host ("[TOD-LISTENER] Request {0} decision={1} reason={2}." -f $requestId, [string]$requestDecision.decision_outcome, [string]$requestDecision.reason_code)
            Publish-CommandStatus -ListenerState $listenerState -ListenerStatePath $listenerStatePath -LocalPath $localCommandStatusPath -RemotePath $remoteCommandStatusPath -Connections $connections -Status $status -Detail ([string]$requestDecision.summary) -RequestId $requestId -TaskId $requestTaskId -CorrelationId $requestCorrelationId -RequestSignature $requestSignature -GoOrderSignature $goOrderSignature -ExecutionReadiness $requestDecision.execution_readiness -TriggerPacket $livenessTrigger -BridgeRuntime $bridgeRuntime -DecisionPayload $requestDecision
            Update-ListenerHeartbeat -State $listenerState -StatePath $listenerStatePath -CycleStartedAt $cycleStartedAt
            $cycleClassification = [string]$requestDecision.decision_outcome
            $retryReason = if ([string]::Equals($status, 'waiting_dependency', [System.StringComparison]::OrdinalIgnoreCase)) { 'waiting_dependency' } else { 'none' }
            $cadencePlan = Update-CadencePlan -ListenerState $listenerState -ListenerStatePath $listenerStatePath -CycleClassification $cycleClassification -RetryReason $retryReason -BasePollSeconds $PollSeconds
            Add-LoopJournalEntry -LocalJournalPath $localJournalPath -RequestId $requestId -ObjectiveId $requestObjectiveId -ExecutionStatus $cycleClassification -CycleClassification $cycleClassification -RetryReason $retryReason -CadencePlan $cadencePlan
            if ($RunOnce) { break }
            Start-Sleep -Seconds ([int]$cadencePlan.sleep_seconds)
            continue
        }

        $bridgeRuntime = Get-BridgeRuntimeStatus -CurrentTaskId $requestTaskId -CurrentCorrelationId $requestCorrelationId

        $ack = [pscustomobject]@{
            generated_at = (Get-Date).ToUniversalTime().ToString("o")
            source = "tod-mim-task-ack-v1"
            request_id = $requestId
            correlation_id = Get-NonEmptyPacketValue -Primary $(if ($request.PSObject.Properties["correlation_id"]) { [string]$request.correlation_id } else { "" }) -Fallback $requestId
            status = "accepted"
            ack_status = "accepted"
            ack_reason_code = (Get-AckReasonCode -Status 'accepted')
            action = Get-NonEmptyPacketValue -Primary $(if ($request.PSObject.Properties["tod_action"] -and $null -ne $request.tod_action) { [string]$request.tod_action } else { "" }) -Fallback $(Get-NonEmptyPacketValue -Primary $(if ($request.PSObject.Properties["action"] -and $null -ne $request.action) { [string]$request.action } else { "" }) -Fallback $(if ($request.PSObject.Properties["action_name"] -and $null -ne $request.action_name) { [string]$request.action_name } else { "" }))
            objective = Get-NonEmptyPacketValue -Primary $(if ($request.PSObject.Properties["objective_id"]) { [string]$request.objective_id } else { "" }) -Fallback $requestObjectiveId
            objective_id = Get-NonEmptyPacketValue -Primary $(if ($request.PSObject.Properties["objective_id"]) { [string]$request.objective_id } else { "" }) -Fallback $requestObjectiveId
            task = Get-NonEmptyPacketValue -Primary $(if ($request.PSObject.Properties["task_id"]) { [string]$request.task_id } else { "" }) -Fallback $requestId
            task_id = Get-NonEmptyPacketValue -Primary $(if ($request.PSObject.Properties["task_id"]) { [string]$request.task_id } else { "" }) -Fallback $requestId
            note = "Request acknowledged and queued for execution."
            decision_outcome = [string]$requestDecision.decision_outcome
            decision_reason_code = [string]$requestDecision.reason_code
            boundary_class = [string]$requestDecision.boundary_class
            next_step_recommendation = [string]$requestDecision.next_step_recommendation
            bridge_runtime = $bridgeRuntime
        }
        $taskAckTrigger = Select-ContractRuntimeTrigger -PreferredTrigger $livenessTrigger -RequestPacket $request -GoOrderPacket $goOrder
        $null = Add-ContractPacketEnvelope -Packet $ack -BindingMetadata $contractBinding -PacketType 'tod-mim-task-ack-v1' -MessageKind 'ack' -ObjectiveId ([string]$ack.objective_id) -TaskId ([string]$ack.task_id) -RequestId $requestId -CorrelationId ([string]$ack.correlation_id)
        $null = Add-SequenceRuntimeFields -Packet $ack -TriggerPacket $taskAckTrigger -ListenerState $listenerState -ListenerStatePath $listenerStatePath
        $ackValidation = Test-ContractRuntimePacket -PythonCommand $pythonCommand -ValidatorScript $runtimeContractValidatorAbs -BindingMetadata $contractBinding -PacketKind 'ack' -Packet $ack
        if (-not [bool]$ackValidation.passed) {
            $violation = Publish-RuntimeContractViolation -ViolationPath $localRuntimeViolationPath -StatePath $localRuntimeBindingStatePath -BindingMetadata $contractBinding -PacketKind 'ack' -Packet $ack -ValidationResult $ackValidation
            Register-RuntimeValidationResult -StatePath $localRuntimeBindingStatePath -BindingMetadata $contractBinding -PacketKind 'ack' -Packet $ack -ValidationResult $ackValidation -State 'violation' | Out-Null
            Publish-CommandStatus -ListenerState $listenerState -ListenerStatePath $listenerStatePath -LocalPath $localCommandStatusPath -RemotePath $remoteCommandStatusPath -Connections $connections -Status 'contract_violation_rejected' -Detail ('Rejected ACK because runtime contract validation failed: {0}' -f (($violation.violations | ForEach-Object { [string]$_.code + ':' + [string]$_.detail }) -join '; ')) -RequestId $requestId -TaskId $requestTaskId -CorrelationId $requestCorrelationId -RequestSignature $requestSignature -GoOrderSignature $goOrderSignature -TriggerPacket $taskAckTrigger -BridgeRuntime $bridgeRuntime
            $null = Publish-ContractViolationCoordination -CoordinationEscalationState $coordinationEscalationState -CoordinationEscalationStatePath $localCoordinationEscalationStatePath -LocalCoordinationRequestPath $localCoordinationRequestPath -RemoteCoordinationRequestPath $remoteCoordinationRequestPath -Connections $connections -RequestId $requestId -ObjectiveId $requestObjectiveId -TaskId $requestTaskId -CorrelationId $requestCorrelationId -PacketKind 'ack' -Packet $ack -Violation $violation -Action ([string]$ack.action) -BridgeRuntime $bridgeRuntime -RuntimeViolationPath $localRuntimeViolationPath
            Update-ListenerHeartbeat -State $listenerState -StatePath $listenerStatePath -CycleStartedAt $cycleStartedAt
            $cadencePlan = Update-CadencePlan -ListenerState $listenerState -ListenerStatePath $listenerStatePath -CycleClassification 'contract_violation_rejected' -RetryReason 'failure' -BasePollSeconds $PollSeconds
            Add-LoopJournalEntry -LocalJournalPath $localJournalPath -RequestId $requestId -ObjectiveId $requestObjectiveId -ExecutionStatus 'contract_violation_rejected' -CycleClassification 'contract_violation_rejected' -RetryReason 'failure' -CadencePlan $cadencePlan
            if ($RunOnce) { break }
            Start-Sleep -Seconds ([int]$cadencePlan.sleep_seconds)
            continue
        }
        Register-RuntimeValidationResult -StatePath $localRuntimeBindingStatePath -BindingMetadata $contractBinding -PacketKind 'ack' -Packet $ack -ValidationResult $ackValidation -State 'active' | Out-Null
        if ([string]::Equals([string]$coordinationEscalationState.pending_issue_code, 'runtime_contract_violation_ack', [System.StringComparison]::OrdinalIgnoreCase)) {
            $null = Publish-ResolvedCoordination -CoordinationEscalationState $coordinationEscalationState -CoordinationEscalationStatePath $localCoordinationEscalationStatePath -LocalCoordinationRequestPath $localCoordinationRequestPath -RemoteCoordinationRequestPath $remoteCoordinationRequestPath -Connections $connections -RequestId $requestId -ObjectiveId $requestObjectiveId -IssueCode 'runtime_contract_violation_ack_resolved' -IssueSummary 'TOD auto-closed the prior ACK contract-violation notice after ACK validation succeeded again.' -Evidence ([pscustomobject]@{ packet_kind = 'ack'; task_id = [string]$ack.task_id; correlation_id = [string]$ack.correlation_id; status = [string]$ack.status; resolution_basis = 'ack_validation_passed' }) -ResolutionReason 'ACK validation now passes; prior contract delta is resolved.' -BridgeRuntime $bridgeRuntime -ResolutionDecision 'auto_resolved_contract_valid'
        }
        Publish-ExecutionLock -LocalPath $localExecutionLockPath -RemotePath $remoteExecutionLockPath -Connections $connections -ObjectiveId $requestObjectiveId -TaskId $requestTaskId -RequestId $requestId -CorrelationId $requestCorrelationId -Status ([string]$ack.status) -BridgeRuntime $bridgeRuntime
        Write-JsonFile -PathValue $localAckPath -Payload $ack

        $ackJson = Get-Content -Path $localAckPath -Raw
        Write-RemoteFileFromText -Connections $connections -RemotePath $remoteAckPath -Content $ackJson
        Publish-CommandStatus -ListenerState $listenerState -ListenerStatePath $listenerStatePath -LocalPath $localCommandStatusPath -RemotePath $remoteCommandStatusPath -Connections $connections -Status ([string]$ack.status) -Detail "Task ACK emitted to shared path." -RequestId $requestId -TaskId $requestTaskId -CorrelationId $requestCorrelationId -RequestSignature $requestSignature -GoOrderSignature $goOrderSignature -AckPacket $ack -TriggerPacket $taskAckTrigger -BridgeRuntime $bridgeRuntime -DecisionPayload $requestDecision
        if ($messageLedgerEnabled) {
            Invoke-LedgerObserveShadowWrite `
                -RequestId $requestId `
                -TaskId $requestTaskId `
                -CorrelationId $requestCorrelationId `
                -SourceArtifact 'TOD_MIM_TASK_ACK.latest.json' `
                -EventType 'ack_observed' `
                -MessageType 'ack' `
                -FromAgent 'TOD' `
                -ToAgent 'MIM' `
                -Status ([string]$ack.status) `
                -PythonCommand $pythonCommand `
                -LedgerScriptAbs $ledgerScriptAbs `
                -LedgerDbAbs $ledgerDbAbs `
                -LedgerMigrationAbs $ledgerMigrationAbs `
                -LedgerStatusAbs $ledgerStatusAbs
        }

        $acceptedFeedback = Publish-ExecutionFeedbackFromRequest -Request $request -Status 'accepted' -TaskId ([string]$ack.task_id) -HostReceivedTimestamp ([string]$ack.emitted_at)
        if ([bool]$acceptedFeedback.attempted -and -not [bool]$acceptedFeedback.published) {
            Write-Warning ("[TOD-LISTENER] Unable to publish accepted execution feedback for request {0}: {1}" -f $requestId, [string]$acceptedFeedback.reason)
        }

        $executionFeedbackStartedAt = (Get-Date).ToUniversalTime().ToString('o')
        $runningFeedback = Publish-ExecutionFeedbackFromRequest -Request $request -Status 'running' -TaskId ([string]$ack.task_id) -HostReceivedTimestamp $executionFeedbackStartedAt
        if ([bool]$runningFeedback.attempted -and -not [bool]$runningFeedback.published) {
            Write-Warning ("[TOD-LISTENER] Unable to publish running execution feedback for request {0}: {1}" -f $requestId, [string]$runningFeedback.reason)
        }
        if ($messageLedgerEnabled) {
            Invoke-LedgerObserveShadowWrite `
                -RequestId $requestId `
                -TaskId $requestTaskId `
                -CorrelationId $requestCorrelationId `
                -SourceArtifact 'TOD_MIM_EXECUTION_FEEDBACK.latest.json' `
                -EventType 'progress_observed' `
                -MessageType 'progress' `
                -FromAgent 'TOD' `
                -ToAgent 'MIM' `
                -Status 'running' `
                -PythonCommand $pythonCommand `
                -LedgerScriptAbs $ledgerScriptAbs `
                -LedgerDbAbs $ledgerDbAbs `
                -LedgerMigrationAbs $ledgerMigrationAbs `
                -LedgerStatusAbs $ledgerStatusAbs
        }

        Write-Host ("[TOD-LISTENER] Executing request {0}..." -f $requestId)
        $execution = Invoke-RequestExecution -TodScriptAbs $todScriptAbs -Request $request

        # Freeze the request consumed by shared-state sync so alignment cannot drift
        # to an older or newer packet while this request is being executed.
        $validatorSuffix = ([guid]::NewGuid().ToString("N"))
        $validatorRequestPath = Join-Path $stageAbs ("MIM_TOD_TASK_REQUEST.validator.{0}.json" -f $validatorSuffix)
        $validatorGoOrderPath = Join-Path $stageAbs ("MIM_TOD_GO_ORDER.validator.{0}.json" -f $validatorSuffix)
        $validatorReviewPath = Join-Path $stageAbs ("MIM_TOD_REVIEW_DECISION.validator.{0}.json" -f $validatorSuffix)
        $validatorResultPath = Join-Path $stageAbs ("TOD_MIM_TASK_RESULT.validator.{0}.json" -f $validatorSuffix)
        Write-JsonFile -PathValue $validatorRequestPath -Payload $request

        $syncError = Invoke-SharedStateSyncRefresh -SyncScriptAbs $syncScriptAbs -HostAlias $hostAlias -RemoteRoot $RemoteRoot -SyncStageRoot $SyncStageDir -ListenerRequestPath $validatorRequestPath -Reason "request execution"

        if ($publishStatus) {
            Publish-IntegrationStatusFiles -Connections $connections -SourcePath $integrationStatusPath -LocalPath $localRemoteStatusFile -RemotePath $remoteStatusPath -LocalAliasPath $localRemoteStatusAliasFile -RemoteAliasPath $remoteStatusAliasPath
            $listenerState.last_status_publish_at = Get-UtcNowString
        }

        $integrationStatus = Get-RequestAlignedIntegrationStatus -IntegrationStatus (Read-JsonFileIfExists -PathValue $integrationStatusPath) -Request $request
        $validatorIntegrationStatusPath = Join-Path $stageAbs ("TOD_INTEGRATION_STATUS.validator.{0}.json" -f $validatorSuffix)
        if ($null -ne $integrationStatus) {
            Write-JsonFile -PathValue $validatorIntegrationStatusPath -Payload $integrationStatus -Depth 100
        }
        else {
            $validatorIntegrationStatusPath = $integrationStatusPath
        }
        $reviewGate = Get-ReviewGateResult -IntegrationStatus $integrationStatus -GoOrder $goOrder -Request $request -RequestId $requestId

        # Snapshot per-cycle inputs so validator cannot drift to a newer packet.
        if ($null -ne $goOrder) {
            Write-JsonFile -PathValue $validatorGoOrderPath -Payload $goOrder
        }
        if ($null -ne $reviewDecision) {
            Write-JsonFile -PathValue $validatorReviewPath -Payload $reviewDecision
        }

        $validatorResult = Invoke-OptionalValidator -ValidatorAbs $validatorAbs -RequestId $requestId -RequestPath $validatorRequestPath -GoOrderPath $validatorGoOrderPath -ReviewDecisionPath $validatorReviewPath -IntegrationStatusPath $validatorIntegrationStatusPath -ResultPath $validatorResultPath

        $regressionSnapshot = Get-RegressionSnapshot -CurrentBuildStatePath $currentBuildStatePath
        if ($regressionSnapshot.available) {
            if ([int]$regressionSnapshot.failed -le 0) {
                $regressionStallState.unchanged_cycles = 0
            }
            else {
                $sameSignature = [string]::Equals([string]$regressionSnapshot.signature, [string]$regressionStallState.last_signature, [System.StringComparison]::OrdinalIgnoreCase)
                $sameRequest = [string]::Equals([string]$requestId, [string]$regressionStallState.last_request_id, [System.StringComparison]::OrdinalIgnoreCase)
                if ($sameSignature -and -not $sameRequest) {
                    $regressionStallState.unchanged_cycles = [int]$regressionStallState.unchanged_cycles + 1
                }
                else {
                    $regressionStallState.unchanged_cycles = 0
                }
            }

            $regressionStallState.last_signature = [string]$regressionSnapshot.signature
            $regressionStallState.last_request_id = [string]$requestId
            $regressionStallState.last_update_at = (Get-Date).ToUniversalTime().ToString("o")
            Write-JsonFile -PathValue $localRegressionStallPath -Payload $regressionStallState

            if ([int]$regressionSnapshot.failed -le 0) {
                $autoResolveReason = "Regression failures are zero; stale coordination escalation has been auto-resolved."
                $existingCoordPayload = Read-JsonFileIfExists -PathValue $localCoordinationRequestPath
                $coordinationIsRegressionRelated = Test-CoordinationIsRegressionRelated -CoordinationRequest $existingCoordPayload -CoordinationEscalationState $coordinationEscalationState

                if ($coordinationIsRegressionRelated -and (
                    -not [string]::IsNullOrWhiteSpace([string]$coordinationEscalationState.pending_request_id) -or
                    [int]$coordinationEscalationState.emit_count -gt 0 -or
                    (Test-Path -Path $localCoordinationRequestPath))) {
                    Clear-CoordinationEscalationState -State $coordinationEscalationState -Reason $autoResolveReason -RequestId $requestId
                    Write-JsonFile -PathValue $localCoordinationEscalationStatePath -Payload $coordinationEscalationState

                    $coordinationResolved = [pscustomobject]@{
                        generated_at = (Get-Date).ToUniversalTime().ToString("o")
                        source = "tod-mim-coordination-request-v1"
                        status = "resolved"
                        priority = "none"
                        escalation_level = 0
                        request_id = [string]$requestId
                        objective_id = if ($request.PSObject.Properties["objective_id"]) { [string]$request.objective_id } else { "" }
                        issue_code = "stalled_regression_no_delta_resolved"
                        issue_summary = "Regression is green; prior stalled-regression escalation is closed automatically."
                        evidence = [pscustomobject]@{
                            failed = [int]$regressionSnapshot.failed
                            total = [int]$regressionSnapshot.total
                            regression_signature = [string]$regressionSnapshot.signature
                        }
                        requested_action = "none"
                        resolution_reason = $autoResolveReason
                        resolved_at = (Get-Date).ToUniversalTime().ToString("o")
                        bridge_runtime = $bridgeRuntime
                    }
                    Write-JsonFile -PathValue $localCoordinationRequestPath -Payload $coordinationResolved
                    try {
                        $coordinationResolvedJson = Get-Content -Path $localCoordinationRequestPath -Raw
                        Write-RemoteFileFromText -Connections $connections -RemotePath $remoteCoordinationRequestPath -Content $coordinationResolvedJson
                    }
                    catch {
                        Write-Warning ("[TOD-LISTENER] Unable to publish resolved coordination status to remote: {0}" -f $_.Exception.Message)
                    }
                }
            }
        }

        $stalledByNoDelta = ($regressionSnapshot.available -and [int]$regressionSnapshot.failed -gt 0 -and [int]$regressionStallState.unchanged_cycles -ge [Math]::Max(1, [int]$RegressionNoDeltaThreshold))

        $resultPacket = [pscustomobject]@{
            generated_at = (Get-Date).ToUniversalTime().ToString("o")
            source = "tod-mim-task-result-v1"
            listener_version = $scriptVersion
            request_id = $requestId
            objective_id = Get-NonEmptyPacketValue -Primary $(if ($request.PSObject.Properties["objective_id"]) { [string]$request.objective_id } else { "" }) -Fallback $requestObjectiveId
            task_id = Get-NonEmptyPacketValue -Primary $(if ($request.PSObject.Properties["task_id"]) { [string]$request.task_id } else { "" }) -Fallback $requestId
            correlation_id = Get-NonEmptyPacketValue -Primary $(if ($request.PSObject.Properties["correlation_id"]) { [string]$request.correlation_id } else { "" }) -Fallback $requestId
            status = if ($execution.PSObject.Properties["blocked"] -and [bool]$execution.blocked) { "blocked" } elseif ($execution.ok -and [bool]$reviewGate.passed -and [bool]$validatorResult.passed) { "succeeded" } else { "failed" }
            action = [string]$execution.action
            execution_mode = if ($execution.PSObject.Properties["execution_mode"]) { [string]$execution.execution_mode } else { "unknown" }
            started_at = [string]$execution.started_at
            completed_at = [string]$execution.completed_at
            error = [string]$execution.error
            request_action_raw = if ($request.PSObject.Properties["action"] -and $null -ne $request.action) { [string]$request.action } else { "" }
            request_tod_action_raw = if ($request.PSObject.Properties["tod_action"] -and $null -ne $request.tod_action) { [string]$request.tod_action } else { "" }
            mim_review_decision = if ($reviewDecision -and $reviewDecision.PSObject.Properties["decision"]) { [string]$reviewDecision.decision } else { "" }
            review_gate = $reviewGate
            validator = $validatorResult
            execution_readiness = if ($execution.PSObject.Properties["execution_readiness"]) { $execution.execution_readiness } else { $null }
            execution_trace = if ($execution.PSObject.Properties["execution_trace"]) { $execution.execution_trace } else { $null }
            decision_outcome = [string]$requestDecision.decision_outcome
            decision_reason_code = [string]$requestDecision.reason_code
            boundary_class = [string]$requestDecision.boundary_class
            next_step_recommendation = [string]$requestDecision.next_step_recommendation
            blocker_classification = [string]$requestDecision.blocker_classification
            validation_reasoning = @($requestDecision.validation_reasoning)
            result_status = if ($execution.PSObject.Properties["blocked"] -and [bool]$execution.blocked) { "blocked" } elseif ($execution.ok -and [bool]$reviewGate.passed -and [bool]$validatorResult.passed) { "succeeded" } else { "failed" }
            terminal = $true
            result_reason_code = ''
            execution_outcome = [pscustomobject]@{
                ok = [bool]$execution.ok
                blocked = if ($execution.PSObject.Properties['blocked']) { [bool]$execution.blocked } else { $false }
                review_gate_passed = [bool]$reviewGate.passed
                validator_passed = [bool]$validatorResult.passed
                error = [string]$execution.error
            }
            integration = [pscustomobject]@{
                compatible = if ($integrationStatus) { [bool]$integrationStatus.compatible } else { $false }
                alignment_status = if ($integrationStatus) { [string]$integrationStatus.objective_alignment.status } else { "unknown" }
                tod_current_objective = if ($integrationStatus) { [string]$integrationStatus.objective_alignment.tod_current_objective } else { "" }
                mim_objective_active = if ($integrationStatus) { [string]$integrationStatus.objective_alignment.mim_objective_active } else { "" }
                mim_refresh_failure_reason = if ($integrationStatus -and $integrationStatus.PSObject.Properties["mim_refresh"] -and $integrationStatus.mim_refresh.PSObject.Properties["failure_reason"]) { [string]$integrationStatus.mim_refresh.failure_reason } else { "" }
            }
            bridge_runtime = $bridgeRuntime
            output_preview = if ([string]::IsNullOrWhiteSpace([string]$execution.output)) { "" } else { ([string]$execution.output).Substring(0, [Math]::Min(1200, ([string]$execution.output).Length)) }
        }
        $resultTrigger = Select-ContractRuntimeTrigger -PreferredTrigger $livenessTrigger -RequestPacket $request -GoOrderPacket $goOrder
        $resultPacket.result_reason_code = Get-ResultReasonCode -Status ([string]$resultPacket.status) -Execution $execution -ReviewGate $reviewGate -ValidatorResult $validatorResult
        $null = Add-ContractPacketEnvelope -Packet $resultPacket -BindingMetadata $contractBinding -PacketType 'tod-mim-task-result-v1' -MessageKind 'result' -ObjectiveId ([string]$resultPacket.objective_id) -TaskId ([string]$resultPacket.task_id) -RequestId $requestId -CorrelationId ([string]$resultPacket.correlation_id)
        $null = Add-SequenceRuntimeFields -Packet $resultPacket -TriggerPacket $resultTrigger -ListenerState $listenerState -ListenerStatePath $listenerStatePath
        Set-ListenerReadinessSnapshot -ListenerState $listenerState -ReadinessTrace $resultPacket.execution_readiness

        if ([string]::Equals([string]$resultPacket.status, 'blocked', [System.StringComparison]::OrdinalIgnoreCase)) {
            Save-BlockedRecoveryState -ListenerState $listenerState -RequestId $requestId -RequestSignature $requestSignature -TaskId $requestTaskId -ObjectiveId $requestObjectiveId -CorrelationId $requestCorrelationId -Action ([string]$resultPacket.action) -ReasonCode ([string]$resultPacket.result_reason_code) -Summary ([string]$resultPacket.error) -ReadinessTrace $resultPacket.execution_readiness
            Write-JsonFile -PathValue $listenerStatePath -Payload $listenerState
            if ($messageLedgerEnabled) {
                Invoke-LedgerObserveShadowWrite `
                    -RequestId $requestId `
                    -TaskId $requestTaskId `
                    -CorrelationId $requestCorrelationId `
                    -SourceArtifact 'TOD_MIM_TASK_RESULT.latest.json' `
                    -EventType 'blocked_observed' `
                    -MessageType 'result' `
                    -FromAgent 'TOD' `
                    -ToAgent 'MIM' `
                    -Status 'blocked' `
                    -PythonCommand $pythonCommand `
                    -LedgerScriptAbs $ledgerScriptAbs `
                    -LedgerDbAbs $ledgerDbAbs `
                    -LedgerMigrationAbs $ledgerMigrationAbs `
                    -LedgerStatusAbs $ledgerStatusAbs
            }
        }
        elseif ([string]::Equals([string]$listenerState.blocked_resume_request_id, [string]$requestId, [System.StringComparison]::OrdinalIgnoreCase) -or [string]::Equals([string]$listenerState.blocked_resume_task_id, [string]$requestTaskId, [System.StringComparison]::OrdinalIgnoreCase)) {
            Clear-BlockedRecoveryState -ListenerState $listenerState
            Write-JsonFile -PathValue $listenerStatePath -Payload $listenerState
        }

        if ($regressionSnapshot.available) {
            $resultPacket | Add-Member -NotePropertyName regression_snapshot -NotePropertyValue $regressionSnapshot -Force
        }

        if ($stalledByNoDelta) {
            $stallMsg = ("stalled_regression_no_delta: regression snapshot unchanged for {0} consecutive cycles while failures remain ({1}/{2} failed)." -f [int]$regressionStallState.unchanged_cycles, [int]$regressionSnapshot.failed, [int]$regressionSnapshot.total)
            $stallGuardOriginalStatus = [string]$resultPacket.status
            $stallGuardOriginalReasonCode = [string]$resultPacket.result_reason_code
            $resultPacket | Add-Member -NotePropertyName stall_guard -NotePropertyValue ([pscustomobject]@{
                issue_code = "stalled_regression_no_delta"
                unchanged_cycles = [int]$regressionStallState.unchanged_cycles
                threshold = [int]$RegressionNoDeltaThreshold
                remediation_hint = "Switch from get-state-bus loop to a remediation task that runs or fixes failing regression tests."
                result_override_applied = $false
                preserved_result_status = $stallGuardOriginalStatus
                preserved_result_reason_code = $stallGuardOriginalReasonCode
            }) -Force

            $stallAlert = [pscustomobject]@{
                generated_at = (Get-Date).ToUniversalTime().ToString("o")
                source = "tod-mim-stall-alert-v1"
                request_id = [string]$requestId
                objective_id = if ($request.PSObject.Properties["objective_id"]) { [string]$request.objective_id } else { "" }
                issue_code = "stalled_regression_no_delta"
                issue_detail = $stallMsg
                unchanged_cycles = [int]$regressionStallState.unchanged_cycles
                threshold = [int]$RegressionNoDeltaThreshold
                regression_snapshot = $regressionSnapshot
                requested_action = "dispatch_remediation_task"
            }
            Write-JsonFile -PathValue $localStallAlertPath -Payload $stallAlert
            $stallAlertJson = Get-Content -Path $localStallAlertPath -Raw
            Write-RemoteFileFromText -Connections $connections -RemotePath $remoteStallAlertPath -Content $stallAlertJson

            $utcNow = (Get-Date).ToUniversalTime()
            if (-not [string]::Equals([string]$coordinationEscalationState.pending_request_id, [string]$requestId, [System.StringComparison]::OrdinalIgnoreCase)) {
                $coordinationEscalationState.pending_request_id = [string]$requestId
                $coordinationEscalationState.pending_since = $utcNow.ToString("o")
                $coordinationEscalationState.last_emit_at = ""
                $coordinationEscalationState.last_emitted_level = 0
                $coordinationEscalationState.emit_count = 0
            }

            $pendingSinceUtc = Get-DateOrMinValue -Value ([string]$coordinationEscalationState.pending_since)
            if ($pendingSinceUtc -eq [datetime]::MinValue) {
                $pendingSinceUtc = $utcNow
                $coordinationEscalationState.pending_since = $pendingSinceUtc.ToString("o")
            }

            $elapsedMinutes = 0
            try {
                $elapsedMinutes = [int][math]::Floor((New-TimeSpan -Start $pendingSinceUtc -End $utcNow).TotalMinutes)
            }
            catch {
                $elapsedMinutes = 0
            }

            $targetEscalationLevel = [math]::Max(1, ([int][math]::Floor($elapsedMinutes / 5) + 1))
            $lastEmitUtc = Get-DateOrMinValue -Value ([string]$coordinationEscalationState.last_emit_at)
            $minutesSinceLastEmit = if ($lastEmitUtc -eq [datetime]::MinValue) { 9999 } else { [int][math]::Floor((New-TimeSpan -Start $lastEmitUtc -End $utcNow).TotalMinutes) }
            $shouldEmitCoordination = ($coordinationEscalationState.last_emitted_level -lt $targetEscalationLevel) -or ($minutesSinceLastEmit -ge 5)

            if ($shouldEmitCoordination) {
                $coordinationRequest = [pscustomobject]@{
                    generated_at = $utcNow.ToString("o")
                    source = "tod-mim-coordination-request-v1"
                    priority = Get-CoordinationPriority -EscalationLevel $targetEscalationLevel
                    escalation_level = [int]$targetEscalationLevel
                    request_id = [string]$requestId
                    objective_id = if ($request.PSObject.Properties["objective_id"]) { [string]$request.objective_id } else { "" }
                    issue_code = "stalled_regression_no_delta"
                    issue_summary = "TOD requests immediate remediation dispatch because regression has stalled with no delta while failures remain."
                    evidence = [pscustomobject]@{
                        unchanged_cycles = [int]$regressionStallState.unchanged_cycles
                        failed = [int]$regressionSnapshot.failed
                        total = [int]$regressionSnapshot.total
                        regression_signature = [string]$regressionSnapshot.signature
                    }
                    requested_action = "dispatch_remediation_task"
                    required_ack = [pscustomobject]@{
                        ack_file = "MIM_TOD_COORDINATION_ACK.latest.json"
                        ack_fields = @("acknowledged", "acknowledged_at", "request_id", "decision", "reason", "target_dispatch_task_id")
                        timeout_seconds = 300
                    }
                    bridge_runtime = $bridgeRuntime
                }
                Write-JsonFile -PathValue $localCoordinationRequestPath -Payload $coordinationRequest
                $coordinationJson = Get-Content -Path $localCoordinationRequestPath -Raw
                Write-RemoteFileFromText -Connections $connections -RemotePath $remoteCoordinationRequestPath -Content $coordinationJson

                $coordinationEscalationState.last_emit_at = $utcNow.ToString("o")
                $coordinationEscalationState.last_emitted_level = [int]$targetEscalationLevel
                $coordinationEscalationState.emit_count = [int]$coordinationEscalationState.emit_count + 1
                Write-JsonFile -PathValue $localCoordinationEscalationStatePath -Payload $coordinationEscalationState

                $resultPacket | Add-Member -NotePropertyName coordination_request -NotePropertyValue $coordinationRequest -Force
            }
        }

        $executionMemoryIncident = Get-ExecutionMemoryIncidentContext -Execution $execution -StatePath $todStatePath
        if ([bool]$executionMemoryIncident.detected) {
            $resultPacket | Add-Member -NotePropertyName memory_incident -NotePropertyValue $executionMemoryIncident -Force

            $utcNow = (Get-Date).ToUniversalTime()
            $currentIssueCode = [string]$executionMemoryIncident.issue_code
            if (
                -not [string]::Equals([string]$coordinationEscalationState.pending_request_id, [string]$requestId, [System.StringComparison]::OrdinalIgnoreCase) -or
                -not [string]::Equals([string]$coordinationEscalationState.pending_issue_code, $currentIssueCode, [System.StringComparison]::OrdinalIgnoreCase)
            ) {
                $coordinationEscalationState.pending_request_id = [string]$requestId
                $coordinationEscalationState.pending_issue_code = $currentIssueCode
                $coordinationEscalationState.pending_issue_summary = [string]$executionMemoryIncident.issue_summary
                $coordinationEscalationState.pending_since = $utcNow.ToString('o')
                $coordinationEscalationState.last_emit_at = ''
                $coordinationEscalationState.last_emitted_level = 0
                $coordinationEscalationState.emit_count = 0
            }

            $pendingSinceUtc = Get-DateOrMinValue -Value ([string]$coordinationEscalationState.pending_since)
            if ($pendingSinceUtc -eq [datetime]::MinValue) {
                $pendingSinceUtc = $utcNow
                $coordinationEscalationState.pending_since = $pendingSinceUtc.ToString('o')
            }

            $elapsedMinutes = 0
            try {
                $elapsedMinutes = [int][math]::Floor((New-TimeSpan -Start $pendingSinceUtc -End $utcNow).TotalMinutes)
            }
            catch {
                $elapsedMinutes = 0
            }

            $targetEscalationLevel = [math]::Max(1, ([int][math]::Floor($elapsedMinutes / 1) + 1))
            $lastEmitUtc = Get-DateOrMinValue -Value ([string]$coordinationEscalationState.last_emit_at)
            $minutesSinceLastEmit = if ($lastEmitUtc -eq [datetime]::MinValue) { 9999 } else { [int][math]::Floor((New-TimeSpan -Start $lastEmitUtc -End $utcNow).TotalMinutes) }
            $shouldEmitCoordination = ($coordinationEscalationState.last_emitted_level -lt $targetEscalationLevel) -or ($minutesSinceLastEmit -ge 1)

            if ($shouldEmitCoordination) {
                $coordinationRequest = [pscustomobject]@{
                    generated_at = $utcNow.ToString('o')
                    source = 'tod-mim-coordination-request-v1'
                    priority = Get-CoordinationPriority -EscalationLevel $targetEscalationLevel
                    escalation_level = [int]$targetEscalationLevel
                    request_id = [string]$requestId
                    objective_id = if ($request.PSObject.Properties['objective_id']) { [string]$request.objective_id } else { '' }
                    issue_code = $currentIssueCode
                    issue_summary = [string]$executionMemoryIncident.issue_summary
                    evidence = [pscustomobject]@{
                        action = [string]$resultPacket.action
                        result_reason_code = [string]$resultPacket.result_reason_code
                        execution_mode = [string]$executionMemoryIncident.execution_mode
                        error = [string]$executionMemoryIncident.error
                        state_file = $executionMemoryIncident.state_file
                    }
                    requested_action = [string]$executionMemoryIncident.requested_action
                    required_ack = [pscustomobject]@{
                        ack_file = 'MIM_TOD_COORDINATION_ACK.latest.json'
                        ack_fields = @('acknowledged', 'acknowledged_at', 'request_id', 'decision', 'reason', 'target_dispatch_task_id')
                        timeout_seconds = 60
                    }
                    bridge_runtime = $bridgeRuntime
                }
                Write-JsonFile -PathValue $localCoordinationRequestPath -Payload $coordinationRequest
                $coordinationJson = Get-Content -Path $localCoordinationRequestPath -Raw
                Write-RemoteFileFromText -Connections $connections -RemotePath $remoteCoordinationRequestPath -Content $coordinationJson

                $coordinationEscalationState.last_emit_at = $utcNow.ToString('o')
                $coordinationEscalationState.last_emitted_level = [int]$targetEscalationLevel
                $coordinationEscalationState.emit_count = [int]$coordinationEscalationState.emit_count + 1
                Write-JsonFile -PathValue $localCoordinationEscalationStatePath -Payload $coordinationEscalationState

                $resultPacket | Add-Member -NotePropertyName coordination_request -NotePropertyValue $coordinationRequest -Force
            }
        }

        $taskTroubleshooting = $null
        $taskTroubleshootingDialog = $null
        if (@('failed', 'blocked') -contains ([string]$resultPacket.status).ToLowerInvariant()) {
            $taskTroubleshooting = Invoke-TaskTroubleshootingGuidance -ConversationProviderScriptAbs $conversationProviderScriptAbs -RequestId $requestId -ObjectiveId ([string]$resultPacket.objective_id) -TaskId ([string]$resultPacket.task_id) -CorrelationId ([string]$resultPacket.correlation_id) -Action ([string]$resultPacket.action) -Execution $execution -DecisionPayload $requestDecision -ReviewGate $reviewGate -ValidatorResult $validatorResult -IntegrationStatus $integrationStatus
            if ($null -ne $taskTroubleshooting) {
                try {
                    Write-JsonFile -PathValue $localTroubleshootingPath -Payload $taskTroubleshooting -Depth 20
                    $troubleshootingJson = Get-Content -Path $localTroubleshootingPath -Raw
                    Write-RemoteFileFromText -Connections $connections -RemotePath $remoteTroubleshootingPath -Content $troubleshootingJson
                }
                catch {
                    Write-Warning ("[TOD-LISTENER] Unable to publish troubleshooting artifact for request {0}: {1}" -f $requestId, $_.Exception.Message)
                }

                $taskTroubleshootingDialog = Publish-TaskTroubleshootingRequest -DialogScriptAbs $dialogScriptAbs -EnvPath $envAbs -RequestId $requestId -ObjectiveId ([string]$resultPacket.objective_id) -TaskId ([string]$resultPacket.task_id) -CorrelationId ([string]$resultPacket.correlation_id) -Troubleshooting $taskTroubleshooting -Execution $execution -DecisionPayload $requestDecision -PublishRemote:$publishDialogRemoteByDefault
                if ($null -ne $taskTroubleshootingDialog) {
                    $resultPacket | Add-Member -NotePropertyName troubleshooting_dialog -NotePropertyValue $taskTroubleshootingDialog -Force
                }

                $resultPacket | Add-Member -NotePropertyName troubleshooting_artifact -NotePropertyValue ([System.IO.Path]::GetFileName($localTroubleshootingPath)) -Force
                $resultPacket | Add-Member -NotePropertyName troubleshooting -NotePropertyValue $taskTroubleshooting -Force
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($syncError)) {
            $resultPacket | Add-Member -NotePropertyName sync_warning -NotePropertyValue $syncError -Force
        }
        $resultPacket.result_status = [string]$resultPacket.status
        $resultValidation = Test-ContractRuntimePacket -PythonCommand $pythonCommand -ValidatorScript $runtimeContractValidatorAbs -BindingMetadata $contractBinding -PacketKind 'result' -Packet $resultPacket
        if (-not [bool]$resultValidation.passed) {
            $violation = Publish-RuntimeContractViolation -ViolationPath $localRuntimeViolationPath -StatePath $localRuntimeBindingStatePath -BindingMetadata $contractBinding -PacketKind 'result' -Packet $resultPacket -ValidationResult $resultValidation
            Register-RuntimeValidationResult -StatePath $localRuntimeBindingStatePath -BindingMetadata $contractBinding -PacketKind 'result' -Packet $resultPacket -ValidationResult $resultValidation -State 'violation' | Out-Null
            Publish-CommandStatus -ListenerState $listenerState -ListenerStatePath $listenerStatePath -LocalPath $localCommandStatusPath -RemotePath $remoteCommandStatusPath -Connections $connections -Status 'contract_violation_rejected' -Detail ('Rejected RESULT because runtime contract validation failed: {0}' -f (($violation.violations | ForEach-Object { [string]$_.code + ':' + [string]$_.detail }) -join '; ')) -RequestId $requestId -TaskId $requestTaskId -CorrelationId $requestCorrelationId -RequestSignature $requestSignature -GoOrderSignature $goOrderSignature -Action ([string]$resultPacket.action) -ExecutionReadiness $resultPacket.execution_readiness -AckPacket $ack -TriggerPacket $resultTrigger -BridgeRuntime $bridgeRuntime
            $null = Publish-ContractViolationCoordination -CoordinationEscalationState $coordinationEscalationState -CoordinationEscalationStatePath $localCoordinationEscalationStatePath -LocalCoordinationRequestPath $localCoordinationRequestPath -RemoteCoordinationRequestPath $remoteCoordinationRequestPath -Connections $connections -RequestId $requestId -ObjectiveId $requestObjectiveId -TaskId $requestTaskId -CorrelationId $requestCorrelationId -PacketKind 'result' -Packet $resultPacket -Violation $violation -Action ([string]$resultPacket.action) -BridgeRuntime $bridgeRuntime -RuntimeViolationPath $localRuntimeViolationPath
            Remove-Item -Path $validatorRequestPath -ErrorAction SilentlyContinue
            Remove-Item -Path $validatorGoOrderPath -ErrorAction SilentlyContinue
            Remove-Item -Path $validatorReviewPath -ErrorAction SilentlyContinue
            Update-ListenerHeartbeat -State $listenerState -StatePath $listenerStatePath -CycleStartedAt $cycleStartedAt
            $cadencePlan = Update-CadencePlan -ListenerState $listenerState -ListenerStatePath $listenerStatePath -CycleClassification 'contract_violation_rejected' -RetryReason 'failure' -BasePollSeconds $PollSeconds
            Add-LoopJournalEntry -LocalJournalPath $localJournalPath -Connections $connections -RemoteJournalPath $remoteJournalPath -RequestId $requestId -ObjectiveId $requestObjectiveId -AckStatus ([string]$ack.status) -ExecutionStatus 'contract_violation_rejected' -Action ([string]$resultPacket.action) -IntegrationAlignment $(if ($integrationStatus) { [string]$integrationStatus.objective_alignment.status } else { "unknown" }) -IntegrationCompatible $(if ($integrationStatus) { [bool]$integrationStatus.compatible } else { $false }) -ReviewGatePassed ([bool]$reviewGate.passed) -ValidatorPassed ([bool]$validatorResult.passed) -ExecutionReadiness $resultPacket.execution_readiness -RegressionSnapshot $regressionSnapshot -StalledNoDelta ([bool]$stalledByNoDelta) -CycleClassification 'contract_violation_rejected' -RetryReason 'failure' -CadencePlan $cadencePlan -PublishRemote $true
            if ($RunOnce) { break }
            Start-Sleep -Seconds ([int]$cadencePlan.sleep_seconds)
            continue
        }
        Register-RuntimeValidationResult -StatePath $localRuntimeBindingStatePath -BindingMetadata $contractBinding -PacketKind 'result' -Packet $resultPacket -ValidationResult $resultValidation -State 'active' | Out-Null
        if (
            [string]::Equals([string]$coordinationEscalationState.pending_issue_code, 'runtime_contract_violation_result', [System.StringComparison]::OrdinalIgnoreCase) -and
            (Test-ResultCanAutoResolveContractViolation -ResultPacket $resultPacket)
        ) {
            $null = Publish-ResolvedCoordination -CoordinationEscalationState $coordinationEscalationState -CoordinationEscalationStatePath $localCoordinationEscalationStatePath -LocalCoordinationRequestPath $localCoordinationRequestPath -RemoteCoordinationRequestPath $remoteCoordinationRequestPath -Connections $connections -RequestId $requestId -ObjectiveId $requestObjectiveId -IssueCode 'runtime_contract_violation_result_resolved' -IssueSummary 'TOD auto-closed the prior RESULT contract-violation notice after RESULT validation succeeded again.' -Evidence ([pscustomobject]@{ packet_kind = 'result'; task_id = [string]$resultPacket.task_id; correlation_id = [string]$resultPacket.correlation_id; status = [string]$resultPacket.status; result_reason_code = [string]$resultPacket.result_reason_code; resolution_basis = 'result_validation_passed' }) -ResolutionReason 'RESULT validation now passes; prior contract delta is resolved.' -BridgeRuntime $bridgeRuntime -ResolutionDecision 'auto_resolved_contract_valid'
        }
        $null = Sync-LocalExecutionOutcome -TaskId $requestTaskId -ObjectiveId $requestObjectiveId -ResultPacket $resultPacket
        Publish-ExecutionLock -LocalPath $localExecutionLockPath -RemotePath $remoteExecutionLockPath -Connections $connections -ObjectiveId $requestObjectiveId -TaskId $requestTaskId -RequestId $requestId -CorrelationId $requestCorrelationId -Status ([string]$resultPacket.status) -BridgeRuntime $bridgeRuntime
        Write-JsonFile -PathValue $localResultPath -Payload $resultPacket

        $resultJson = Get-Content -Path $localResultPath -Raw
        Write-RemoteFileFromText -Connections $connections -RemotePath $remoteResultPath -Content $resultJson
        Publish-CommandStatus -ListenerState $listenerState -ListenerStatePath $listenerStatePath -LocalPath $localCommandStatusPath -RemotePath $remoteCommandStatusPath -Connections $connections -Status ([string]$resultPacket.status) -Detail "Task RESULT emitted to shared path." -RequestId $requestId -TaskId $requestTaskId -CorrelationId $requestCorrelationId -RequestSignature $requestSignature -GoOrderSignature $goOrderSignature -Action ([string]$resultPacket.action) -ExecutionReadiness $resultPacket.execution_readiness -AckPacket $ack -ResultPacket $resultPacket -TriggerPacket $resultTrigger -BridgeRuntime $bridgeRuntime -DecisionPayload $requestDecision
        if ($messageLedgerEnabled) {
            Invoke-LedgerObserveShadowWrite `
                -RequestId $requestId `
                -TaskId $requestTaskId `
                -CorrelationId $requestCorrelationId `
                -SourceArtifact 'TOD_MIM_TASK_RESULT.latest.json' `
                -EventType 'result_observed' `
                -MessageType 'result' `
                -FromAgent 'TOD' `
                -ToAgent 'MIM' `
                -Status ([string]$resultPacket.status) `
                -PythonCommand $pythonCommand `
                -LedgerScriptAbs $ledgerScriptAbs `
                -LedgerDbAbs $ledgerDbAbs `
                -LedgerMigrationAbs $ledgerMigrationAbs `
                -LedgerStatusAbs $ledgerStatusAbs
        }

        $failureCategory = ''
        if ([string]::Equals([string]$resultPacket.status, 'failed', [System.StringComparison]::OrdinalIgnoreCase)) {
            $failureCategory = if (-not [string]::IsNullOrWhiteSpace([string]$resultPacket.result_reason_code)) { [string]$resultPacket.result_reason_code } else { 'execution_failed' }
        }
        elseif ([string]::Equals([string]$resultPacket.status, 'blocked', [System.StringComparison]::OrdinalIgnoreCase)) {
            $failureCategory = 'guardrail_blocked'
        }

        $terminalFeedback = Publish-ExecutionFeedbackFromRequest -Request $request -Status ([string]$resultPacket.status) -TaskId ([string]$resultPacket.task_id) -HostReceivedTimestamp ([string]$ack.emitted_at) -HostCompletedTimestamp ([string]$resultPacket.completed_at) -ResultReasonCode ([string]$resultPacket.result_reason_code) -ExecutionMode ([string]$resultPacket.execution_mode) -FailureCategory $failureCategory -ErrorDetail ([string]$resultPacket.error) -GuardrailBlocked:([string]::Equals([string]$resultPacket.status, 'blocked', [System.StringComparison]::OrdinalIgnoreCase)) -Recovered:$false -UnrecoveredFailure:([string]::Equals([string]$resultPacket.status, 'failed', [System.StringComparison]::OrdinalIgnoreCase)) -ReviewGatePassed:([bool]$reviewGate.passed) -ValidatorPassed:([bool]$validatorResult.passed)
        if ([bool]$terminalFeedback.attempted -and -not [bool]$terminalFeedback.published) {
            Write-Warning ("[TOD-LISTENER] Unable to publish terminal execution feedback for request {0}: {1}" -f $requestId, [string]$terminalFeedback.reason)
        }

        Remove-Item -Path $validatorRequestPath -ErrorAction SilentlyContinue
        Remove-Item -Path $validatorGoOrderPath -ErrorAction SilentlyContinue
        Remove-Item -Path $validatorReviewPath -ErrorAction SilentlyContinue

        Publish-TriggerAck -ListenerState $listenerState -ListenerStatePath $listenerStatePath -Connections $connections -LocalPath $localTriggerAckPath -RemotePath $remoteTriggerAckPath -RequestId $requestId -CurrentTaskId $currentTaskId -CurrentCorrelationId $currentCorrelationId -TriggerPacket $livenessTrigger -BridgeRuntime $bridgeRuntime

        if ($null -ne $scopedForcedReplay) {
            $null = Remove-ScopedForcedReplayMatch -ListenerState $listenerState -RequestId $requestId
        }
        Update-ListenerHeartbeat -State $listenerState -StatePath $listenerStatePath -CycleStartedAt $cycleStartedAt -RequestId $requestId -RequestSignature $requestSignature -MarkProcessed
        if ($messageLedgerEnabled) {
            Invoke-LedgerObserveShadowWrite `
                -RequestId $requestId `
                -TaskId $requestTaskId `
                -CorrelationId $requestCorrelationId `
                -SourceArtifact 'TOD_MIM_LISTENER_STATE.latest.json' `
                -EventType 'heartbeat_observed' `
                -MessageType 'heartbeat' `
                -FromAgent 'TOD' `
                -ToAgent 'MIM' `
                -Status 'alive' `
                -PythonCommand $pythonCommand `
                -LedgerScriptAbs $ledgerScriptAbs `
                -LedgerDbAbs $ledgerDbAbs `
                -LedgerMigrationAbs $ledgerMigrationAbs `
                -LedgerStatusAbs $ledgerStatusAbs
        }
        $resultRetryReason = if ([string]::Equals([string]$resultPacket.status, "failed", [System.StringComparison]::OrdinalIgnoreCase)) { "failure" } else { "none" }
        $resultClassification = if ([string]::Equals([string]$resultPacket.status, "failed", [System.StringComparison]::OrdinalIgnoreCase)) { "execution_failed" } elseif ([string]::Equals([string]$resultPacket.status, "blocked", [System.StringComparison]::OrdinalIgnoreCase)) { "execution_blocked" } else { "execution_completed" }
        $cadencePlan = Update-CadencePlan -ListenerState $listenerState -ListenerStatePath $listenerStatePath -CycleClassification $resultClassification -RetryReason $resultRetryReason -WasSuccess:([string]::Equals([string]$resultPacket.status, "succeeded", [System.StringComparison]::OrdinalIgnoreCase)) -BasePollSeconds $PollSeconds
            Add-LoopJournalEntry -LocalJournalPath $localJournalPath -Connections $connections -RemoteJournalPath $remoteJournalPath -RequestId $requestId -ObjectiveId $requestObjectiveId -AckStatus ([string]$ack.status) -ExecutionStatus ([string]$resultPacket.status) -Action ([string]$resultPacket.action) -IntegrationAlignment $(if ($integrationStatus) { [string]$integrationStatus.objective_alignment.status } else { "unknown" }) -IntegrationCompatible $(if ($integrationStatus) { [bool]$integrationStatus.compatible } else { $false }) -ReviewGatePassed ([bool]$reviewGate.passed) -ValidatorPassed ([bool]$validatorResult.passed) -ExecutionReadiness $resultPacket.execution_readiness -RegressionSnapshot $regressionSnapshot -StalledNoDelta ([bool]$stalledByNoDelta) -CycleClassification $resultClassification -RetryReason $resultRetryReason -CadencePlan $cadencePlan -PublishRemote $true

        # Quarantine fail-cycle tracking: increment counter on fail; apply quarantine after threshold; clear on success.
        if ([string]$resultPacket.status -eq "failed") {
            if ([string]::Equals($requestId, [string]$quarantineState.last_fail_request_id, [System.StringComparison]::OrdinalIgnoreCase)) {
                $quarantineState.fail_cycle_count = [int]$quarantineState.fail_cycle_count + 1
            } else {
                $quarantineState.last_fail_request_id = $requestId
                $quarantineState.fail_cycle_count = 1
            }
            if ([int]$quarantineState.fail_cycle_count -ge [int]$QuarantineFailCycleThreshold) {
                $quarantineState.quarantined_request_id = $requestId
                $quarantineState.quarantine_applied_at = (Get-Date).ToUniversalTime().ToString("o")
                Write-Host ("[TOD-LISTENER] QUARANTINE applied to request {0} after {1} consecutive fail cycles." -f $requestId, [int]$quarantineState.fail_cycle_count)
            }
        } else {
            if ([string]::Equals($requestId, [string]$quarantineState.quarantined_request_id, [System.StringComparison]::OrdinalIgnoreCase) -or
                [string]::Equals($requestId, [string]$quarantineState.last_fail_request_id, [System.StringComparison]::OrdinalIgnoreCase)) {
                $quarantineState.quarantined_request_id = ""
                $quarantineState.quarantine_applied_at = ""
                $quarantineState.fail_cycle_count = 0
                $quarantineState.last_fail_request_id = ""
            }
        }
        Write-JsonFile -PathValue $localQuarantineStatePath -Payload $quarantineState

        Write-Host ("[TOD-LISTENER] Processed request {0} status={1}" -f $requestId, [string]$resultPacket.status)

        if ($RunOnce) { break }
    }
    catch {
        $listenerState | Add-Member -NotePropertyName last_cycle_error_message -NotePropertyValue ([string]$_.Exception.Message) -Force
        $listenerState | Add-Member -NotePropertyName last_cycle_error_at -NotePropertyValue (Get-UtcNowString) -Force
        $listenerState | Add-Member -NotePropertyName last_cycle_error_stack -NotePropertyValue ([string]$_.ScriptStackTrace) -Force
        Write-Warning ("[TOD-LISTENER] Cycle error: {0}" -f [string]$_.Exception.Message)
        Update-ListenerHeartbeat -State $listenerState -StatePath $listenerStatePath -CycleStartedAt $cycleStartedAt
        $cadencePlan = Update-CadencePlan -ListenerState $listenerState -ListenerStatePath $listenerStatePath -CycleClassification "cycle_error" -RetryReason "failure" -BasePollSeconds $PollSeconds
        Add-LoopJournalEntry -LocalJournalPath $localJournalPath -RequestId "" -ObjectiveId "" -ExecutionStatus "failed" -CycleClassification "cycle_error" -RetryReason "failure" -CadencePlan $cadencePlan
        if ($FailOnError) {
            throw
        }
        if ($RunOnce) { break }
    }
    finally {
        Close-SshConnections -Connections $connections
    }

    $sleepSeconds = if ($listenerState -and $listenerState.PSObject.Properties["cadence_planned_sleep_seconds"]) { [int]$listenerState.cadence_planned_sleep_seconds } else { $PollSeconds }
    Start-Sleep -Seconds ([Math]::Max(1, $sleepSeconds))
}
}
finally {
    if ($listenerHasHandle) {
        $listenerMutex.ReleaseMutex() | Out-Null
    }
    $listenerMutex.Dispose()
}

Write-Host "[TOD-LISTENER] Stopped."
