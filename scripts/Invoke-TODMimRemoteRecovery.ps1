param(
    [string]$EnvPath = '.env',
    [string]$SharedStateSyncScriptPath = 'scripts/Invoke-TODSharedStateSync.ps1',
    [string]$PublicationSelfHealScriptPath = 'scripts/Invoke-TODPublicationSurfaceSelfHeal.ps1',
    [string]$WatchdogScriptPath = 'scripts/Start-TODRecoveryWatchdog.ps1',
    [string]$DialogScriptPath = 'scripts/Invoke-TODMimDialog.ps1',
    [string]$IntegrationStatusPath = 'shared_state/integration_status.json',
    [string]$ListenerStageDir = 'tod/out/context-sync/listener',
    [string]$DialogIndexPath = 'shared_state/dialog/MIM_TOD_DIALOG.sessions.latest.json',
    [string]$RecoveryDir = 'shared_state/remote-recovery',
    [switch]$PublishDialogRemote,
    [switch]$EmitJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot

function Get-RepoPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return [System.IO.Path]::GetFullPath($PathValue)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $PathValue))
}

function Import-WatchdogFunction {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$tokens, [ref]$errors)
    if (@($errors).Count -gt 0) {
        throw "Failed to parse watchdog script: $ScriptPath"
    }

    $fnAst = $ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name
    }, $true)

    if ($null -eq $fnAst) {
        throw "Function '$Name' not found in $ScriptPath"
    }

    $pattern = ('function\s+{0}\b' -f [regex]::Escape($Name))
    $replacement = ('function global:{0}' -f $Name)
    $definition = $fnAst.Extent.Text -replace $pattern, $replacement
    . ([scriptblock]::Create($definition))
}

function Convert-ToObjectiveLabelLocal {
    param([string]$Value)

    $normalized = Normalize-ObjectiveIdentity -Value ([string]$Value)
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return ''
    }

    return ('objective-{0}' -f $normalized)
}

function Get-StringProperty {
    param(
        $InputObject,
        [string]$Name
    )

    if ($null -eq $InputObject -or [string]::IsNullOrWhiteSpace($Name)) {
        return ''
    }

    if (-not $InputObject.PSObject.Properties[$Name]) {
        return ''
    }

    return [string]$InputObject.$Name
}

function Get-ArrayStrings {
    param($InputValue)

    if ($null -eq $InputValue) {
        return @()
    }

    return @($InputValue | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Invoke-SharedStateRefresh {
    param([string]$ScriptAbs)

    if (-not (Test-Path -Path $ScriptAbs)) {
        return [pscustomobject]@{
            attempted = $false
            ok = $false
            reason = 'shared_state_sync_script_missing'
        }
    }

    try {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ScriptAbs -RefreshMimContextFromSsh -PublishTodStatusToMimArm | Out-Null
        return [pscustomobject]@{
            attempted = $true
            ok = $true
            reason = 'ok'
        }
    }
    catch {
        return [pscustomobject]@{
            attempted = $true
            ok = $false
            reason = [string]$_.Exception.Message
        }
    }
}

function Invoke-PublicationSelfHealWrapper {
    param(
        [string]$ScriptAbs,
        [string]$EnvAbs,
        [string]$IntegrationStatusAbs,
        [string]$RepairPacketAbs
    )

    if (-not (Test-Path -Path $ScriptAbs)) {
        return [pscustomobject]@{
            attempted = $false
            repaired = $false
            reason = 'publication_self_heal_script_missing'
        }
    }

    try {
        $json = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ScriptAbs -EnvPath $EnvAbs -IntegrationStatusPath $IntegrationStatusAbs -LocalRepairPacketPath $RepairPacketAbs
        $parsed = $json | ConvertFrom-Json
        return $parsed
    }
    catch {
        return [pscustomobject]@{
            attempted = $true
            repaired = $false
            reason = [string]$_.Exception.Message
        }
    }
}

function Get-RecoveryStateSnapshot {
    param(
        [string]$IntegrationStatusAbs,
        [string]$ListenerStageAbs,
        [string]$DialogIndexAbs
    )

    $integrationStatus = Read-JsonFileIfExists -PathValue $IntegrationStatusAbs
    $coordinationRequestPath = Join-Path $ListenerStageAbs 'TOD_MIM_COORDINATION_REQUEST.latest.json'
    $coordinationAckPath = Join-Path $ListenerStageAbs 'MIM_TOD_COORDINATION_ACK.latest.json'
    $coordinationEscalationPath = Join-Path $ListenerStageAbs 'TOD_MIM_COORDINATION_ESCALATION_STATE.latest.json'
    $liveTaskRequestPath = Join-Path $ListenerStageAbs 'MIM_TOD_TASK_REQUEST.latest.json'
    $decisionPath = Join-Path $ListenerStageAbs 'TOD_MIM_EXECUTION_DECISION.latest.json'
    $dialogIndex = Read-JsonFileIfExists -PathValue $DialogIndexAbs
    $coordinationRequest = Read-JsonFileIfExists -PathValue $coordinationRequestPath
    $coordinationAck = Read-JsonFileIfExists -PathValue $coordinationAckPath
    $coordinationEscalation = Read-JsonFileIfExists -PathValue $coordinationEscalationPath
    $liveTaskRequest = Read-JsonFileIfExists -PathValue $liveTaskRequestPath
    $listenerDecision = Read-JsonFileIfExists -PathValue $decisionPath

    $canonicalObjective = Normalize-ObjectiveIdentity -Value (
        (Get-StringProperty -InputObject $integrationStatus.objective_alignment -Name 'tod_current_objective')
    )
    if ([string]::IsNullOrWhiteSpace($canonicalObjective)) {
        $canonicalObjective = Normalize-ObjectiveIdentity -Value (Get-StringProperty -InputObject $integrationStatus.mim_handshake -Name 'objective_active')
    }

    $liveObjective = Normalize-ObjectiveIdentity -Value (
        (Get-StringProperty -InputObject $integrationStatus.live_task_request -Name 'normalized_objective_id')
    )
    if ([string]::IsNullOrWhiteSpace($liveObjective)) {
        $liveObjective = Normalize-ObjectiveIdentity -Value (Get-StringProperty -InputObject $liveTaskRequest -Name 'objective_id')
    }

    $bridgeEvidence = if ($integrationStatus -and $integrationStatus.PSObject.Properties['bridge_canonical_evidence']) { $integrationStatus.bridge_canonical_evidence } else { $null }
    $failureSignals = @()
    if ($null -ne $bridgeEvidence -and $bridgeEvidence.PSObject.Properties['failure_signals']) {
        $failureSignals = Get-ArrayStrings -InputValue $bridgeEvidence.failure_signals
    }

    $decisionOutcome = Get-StringProperty -InputObject $integrationStatus.listener_decision -Name 'decision_outcome'
    $reasonCode = Get-StringProperty -InputObject $integrationStatus.listener_decision -Name 'reason_code'
    $waitingOnMim =
        [string]::Equals($decisionOutcome, 'acknowledge_and_wait_on_dependency', [System.StringComparison]::OrdinalIgnoreCase) -or
        [string]::Equals($reasonCode, 'external_coordination_blocker', [System.StringComparison]::OrdinalIgnoreCase) -or
        ($failureSignals -contains 'live_task_request_objective_mismatch') -or
        ($failureSignals -contains 'live_task_request_not_promoted')

    return [pscustomobject]@{
        integration_status = $integrationStatus
        bridge_evidence = $bridgeEvidence
        failure_signals = @($failureSignals)
        live_task_request = $liveTaskRequest
        live_task_request_path = $liveTaskRequestPath
        listener_decision = $listenerDecision
        coordination_request = $coordinationRequest
        coordination_request_path = $coordinationRequestPath
        coordination_ack = $coordinationAck
        coordination_ack_path = $coordinationAckPath
        coordination_escalation = $coordinationEscalation
        coordination_escalation_path = $coordinationEscalationPath
        dialog_index = $dialogIndex
        canonical_objective = $canonicalObjective
        live_objective = $liveObjective
        current_request_id = if ($integrationStatus -and $integrationStatus.live_task_request) { Get-StringProperty -InputObject $integrationStatus.live_task_request -Name 'request_id' } else { Get-StringProperty -InputObject $liveTaskRequest -Name 'request_id' }
        current_task_id = if ($integrationStatus -and $integrationStatus.live_task_request) { Get-StringProperty -InputObject $integrationStatus.live_task_request -Name 'task_id' } else { Get-StringProperty -InputObject $liveTaskRequest -Name 'task_id' }
        current_correlation_id = if ($integrationStatus -and $integrationStatus.live_task_request) { Get-StringProperty -InputObject $integrationStatus.live_task_request -Name 'correlation_id' } else { Get-StringProperty -InputObject $liveTaskRequest -Name 'correlation_id' }
        waiting_on_mim = [bool]$waitingOnMim
    }
}

function Get-OpenRecoverySessions {
    param(
        $DialogIndex,
        [string]$IssueCode
    )

    if ($null -eq $DialogIndex -or -not $DialogIndex.PSObject.Properties['sessions']) {
        return @()
    }

    return @(
        $DialogIndex.sessions | Where-Object {
            $status = [string]$_.status
            $summary = ''
            if ($_.last_message -and $_.last_message.PSObject.Properties['summary']) {
                $summary = [string]$_.last_message.summary
            }

            (-not [string]::Equals($status, 'closed', [System.StringComparison]::OrdinalIgnoreCase)) -and
            (-not [string]::Equals($status, 'replied', [System.StringComparison]::OrdinalIgnoreCase)) -and
            ($summary -match [regex]::Escape($IssueCode))
        }
    )
}

function Close-RecoveryDialogSessions {
    param(
        [string]$DialogScriptAbs,
        [string]$EnvAbs,
        [object[]]$Sessions
    )

    $closed = New-Object System.Collections.Generic.List[string]
    foreach ($session in @($Sessions)) {
        $sessionId = [string]$session.session_id
        if ([string]::IsNullOrWhiteSpace($sessionId)) {
            continue
        }

        try {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $DialogScriptAbs -Action close-session -SessionId $sessionId -Actor TOD -PeerActor MIM -MessageType resolution_notice -Intent recovery_session_superseded -Summary 'TOD remote recovery superseded this stale coordination handoff.' -PayloadJson '{"source":"tod-remote-recovery-v1","status":"superseded"}' -DotEnvPath $EnvAbs -EmitJson | Out-Null
            $closed.Add($sessionId)
        }
        catch {
        }
    }

    return @($closed)
}

function Publish-RecoveryDialogHandoff {
    param(
        [string]$DialogScriptAbs,
        [string]$EnvAbs,
        [string]$SessionId,
        [string]$TaskId,
        [string]$CorrelationId,
        [string]$Summary,
        [string]$PayloadJson,
        [switch]$PublishRemoteSwitch
    )

    try {
        $args = @(
            '-NoProfile',
            '-ExecutionPolicy', 'Bypass',
            '-File', $DialogScriptAbs,
            '-Action', 'send',
            '-SessionId', $SessionId,
            '-Actor', 'TOD',
            '-PeerActor', 'MIM',
            '-MessageType', 'handoff_request',
            '-Intent', 'publication_surface_divergence_ack_required',
            '-TaskId', $TaskId,
            '-CorrelationId', $CorrelationId,
            '-Summary', $Summary,
            '-PayloadJson', $PayloadJson,
            '-RequiresReply',
            '-DotEnvPath', $EnvAbs,
            '-EmitJson'
        )
        if ($PublishRemoteSwitch) {
            $args += '-PublishRemote'
        }

        $result = & powershell.exe @args | ConvertFrom-Json
        return [pscustomobject]@{
            published = $true
            result = $result
        }
    }
    catch {
        return [pscustomobject]@{
            published = $false
            reason = [string]$_.Exception.Message
        }
    }
}

function New-RecoveryCoordinationRequest {
    param(
        $PreState,
        $PostState,
        [string]$CorrelationId,
        [string]$SupersededRequestId
    )

    $canonicalObjectiveLabel = Convert-ToObjectiveLabelLocal -Value $PostState.canonical_objective
    $currentTaskId = [string]$PostState.current_task_id
    if ([string]::IsNullOrWhiteSpace($currentTaskId)) {
        $currentTaskId = [string]$PreState.current_task_id
    }

    $requestIdSeed = if (-not [string]::IsNullOrWhiteSpace($currentTaskId)) {
        $currentTaskId
    }
    elseif (-not [string]::IsNullOrWhiteSpace($PostState.canonical_objective)) {
        ('objective-{0}-task-current' -f [string]$PostState.canonical_objective)
    }
    else {
        'unknown-task'
    }

    $requestId = ('coordination-{0}-publication_surface_divergence' -f $requestIdSeed)
    return [pscustomobject]@{
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        source = 'tod-mim-coordination-request-v1'
        status = 'active'
        priority = 'urgent'
        escalation_level = 2
        request_id = $requestId
        objective_id = $canonicalObjectiveLabel
        task_id = $currentTaskId
        correlation_id = $CorrelationId
        issue_code = 'publication_surface_divergence'
        issue_summary = 'TOD remote recovery detected publication-surface divergence and replaced stale coordination metadata with current authoritative identifiers.'
        requested_action = 'Acknowledge the current publication-surface recovery packet and verify the canonical live task-request boundary now matches the active objective.'
        required_ack = [pscustomobject]@{
            ack_file = 'MIM_TOD_COORDINATION_ACK.latest.json'
            ack_fields = @('acknowledged', 'acknowledged_at', 'request_id', 'decision', 'reason', 'target_dispatch_task_id')
            timeout_seconds = 60
        }
        recovery_assist = [pscustomobject]@{
            source = 'tod-recovery-assist-v1'
            supersedes_request_id = $SupersededRequestId
            pre_repair_live_objective = Convert-ToObjectiveLabelLocal -Value $PreState.live_objective
            post_repair_live_objective = Convert-ToObjectiveLabelLocal -Value $PostState.live_objective
            canonical_objective_id = $canonicalObjectiveLabel
        }
        evidence = [pscustomobject]@{
            canonical_expected_objective_id = $canonicalObjectiveLabel
            pre_repair_live_task_request_id = [string]$PreState.current_request_id
            pre_repair_live_task_request_objective_id = Convert-ToObjectiveLabelLocal -Value $PreState.live_objective
            post_repair_live_task_request_id = [string]$PostState.current_request_id
            post_repair_live_task_request_objective_id = Convert-ToObjectiveLabelLocal -Value $PostState.live_objective
            pre_failure_signals = @($PreState.failure_signals)
            post_failure_signals = @($PostState.failure_signals)
            bridge_status = if ($PostState.bridge_evidence) { Get-StringProperty -InputObject $PostState.bridge_evidence -Name 'status' } else { '' }
            remote_publish_verified = if ($PostState.bridge_evidence) { [bool]$PostState.bridge_evidence.remote_publish_verified } else { $false }
        }
    }
}

function New-RecoveryAssistAck {
    param(
        $CoordinationRequest,
        $PostState,
        [string]$Reason
    )

    $canonicalObjectiveLabel = Convert-ToObjectiveLabelLocal -Value $PostState.canonical_objective
    return [pscustomobject]@{
        version = '1.0'
        source = 'TOD'
        target = 'TOD'
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        emitted_at = (Get-Date).ToUniversalTime().ToString('o')
        source_host = 'TOD'
        source_service = 'tod_remote_recovery_assist'
        source_instance_id = ('Invoke-TODMimRemoteRecovery:{0}' -f $PID)
        schema_version = 'tod-recovery-assist-ack-v1'
        objective_id = [string]$CoordinationRequest.objective_id
        task_id = [string]$CoordinationRequest.request_id
        request_id = [string]$CoordinationRequest.request_id
        correlation_id = [string]$CoordinationRequest.correlation_id
        acknowledged = $true
        acknowledged_at = (Get-Date).ToUniversalTime().ToString('o')
        ack_status = 'acknowledged'
        status = 'acknowledged'
        decision = 'accepted'
        reason = $Reason
        detail = 'TOD recovery assist generated a coordination ACK from authoritative bridge evidence only. This does not claim MIM execution completion.'
        target_dispatch_task_id = [string]$PostState.current_task_id
        coordination = [pscustomobject]@{
            status = 'acknowledged'
            phase = 'tod_recovery_assist'
            detail = 'authoritative_publication_surface_repair_validated'
            request_issue_code = 'publication_surface_divergence'
            requested_action = 'verify_current_live_boundary'
            target_dispatch_task_id = [string]$PostState.current_task_id
        }
        recovery_assist = [pscustomobject]@{
            source = 'tod-recovery-assist-v1'
            canonical_objective_id = $canonicalObjectiveLabel
            live_request_id = [string]$PostState.current_request_id
            live_request_objective_id = Convert-ToObjectiveLabelLocal -Value $PostState.live_objective
            does_not_claim_mim_execution_completion = $true
        }
    }
}

function Test-SafeAssistAck {
    param($PostState)

    $failureSignals = @($PostState.failure_signals)
    $canonicalObjective = Normalize-ObjectiveIdentity -Value $PostState.canonical_objective
    $liveObjective = Normalize-ObjectiveIdentity -Value $PostState.live_objective

    return (
        -not [string]::IsNullOrWhiteSpace($canonicalObjective) -and
        [string]::Equals($canonicalObjective, $liveObjective, [System.StringComparison]::OrdinalIgnoreCase) -and
        ($failureSignals -notcontains 'live_task_request_objective_mismatch') -and
        ($failureSignals -notcontains 'live_task_request_not_promoted') -and
        ($null -ne $PostState.bridge_evidence) -and
        [bool]$PostState.bridge_evidence.remote_publish_verified
    )
}

$envAbs = Get-RepoPath -PathValue $EnvPath
$sharedStateSyncAbs = Get-RepoPath -PathValue $SharedStateSyncScriptPath
$publicationSelfHealAbs = Get-RepoPath -PathValue $PublicationSelfHealScriptPath
$watchdogScriptAbs = Get-RepoPath -PathValue $WatchdogScriptPath
$dialogScriptAbs = Get-RepoPath -PathValue $DialogScriptPath
$integrationStatusAbs = Get-RepoPath -PathValue $IntegrationStatusPath
$listenerStageAbs = Get-RepoPath -PathValue $ListenerStageDir
$dialogIndexAbs = Get-RepoPath -PathValue $DialogIndexPath
$recoveryDirAbs = Get-RepoPath -PathValue $RecoveryDir

@(
    'Read-JsonFileIfExists',
    'Write-JsonFile',
    'Get-DotEnvValue',
    'Resolve-SshHostAlias',
    'Normalize-ObjectiveIdentity',
    'Convert-ToObjectiveLabel',
    'Get-CanonicalObjectiveForSelfHeal',
    'New-CanonicalRepublishTaskRequest',
    'Invoke-PublicationSurfaceSelfHeal',
    'Publish-PacketToMim'
) | ForEach-Object {
    Import-WatchdogFunction -ScriptPath $watchdogScriptAbs -Name $_
}

if (-not (Test-Path -Path $recoveryDirAbs)) {
    New-Item -ItemType Directory -Path $recoveryDirAbs -Force | Out-Null
}

$localRepairPacketAbs = Join-Path $recoveryDirAbs 'MIM_TOD_TASK_REQUEST.recovery.latest.json'
$reportPath = Join-Path $recoveryDirAbs 'TOD_MIM_REMOTE_RECOVERY.latest.json'
$localCoordinationRequestPath = Join-Path $listenerStageAbs 'TOD_MIM_COORDINATION_REQUEST.latest.json'
$localCoordinationAckPath = Join-Path $listenerStageAbs 'MIM_TOD_COORDINATION_ACK.latest.json'

$refreshBefore = Invoke-SharedStateRefresh -ScriptAbs $sharedStateSyncAbs
$preState = Get-RecoveryStateSnapshot -IntegrationStatusAbs $integrationStatusAbs -ListenerStageAbs $listenerStageAbs -DialogIndexAbs $dialogIndexAbs

$existingCoordinationIssueCode = if ($preState.coordination_request) { Get-StringProperty -InputObject $preState.coordination_request -Name 'issue_code' } else { '' }
$existingCoordinationAckStatus = if ($preState.coordination_ack) { Get-StringProperty -InputObject $preState.coordination_ack -Name 'status' } else { '' }
$existingCoordinationAckDecision = if ($preState.coordination_ack) { Get-StringProperty -InputObject $preState.coordination_ack -Name 'decision' } else { '' }

$issueDetected = [bool](
    $preState.waiting_on_mim -or
    ($preState.failure_signals -contains 'live_task_request_objective_mismatch') -or
    ($preState.failure_signals -contains 'live_task_request_not_promoted') -or
    (
        [string]::Equals($existingCoordinationIssueCode, 'publication_surface_divergence', [System.StringComparison]::OrdinalIgnoreCase) -and
        -not [string]::Equals($existingCoordinationAckStatus, 'acknowledged', [System.StringComparison]::OrdinalIgnoreCase) -and
        -not [string]::Equals($existingCoordinationAckStatus, 'accepted', [System.StringComparison]::OrdinalIgnoreCase)
    ) -or
    (
        [string]::Equals((Get-StringProperty -InputObject $preState.integration_status.listener_decision -Name 'reason_code'), 'objective_mismatch', [System.StringComparison]::OrdinalIgnoreCase) -and
        [string]::Equals($existingCoordinationIssueCode, 'publication_surface_divergence', [System.StringComparison]::OrdinalIgnoreCase)
    ) -or
    (
        [string]::Equals($existingCoordinationAckDecision, 'request_received', [System.StringComparison]::OrdinalIgnoreCase) -and
        [string]::Equals($existingCoordinationIssueCode, 'publication_surface_divergence', [System.StringComparison]::OrdinalIgnoreCase)
    )
)

$supersededRequestId = if ($preState.coordination_request) { Get-StringProperty -InputObject $preState.coordination_request -Name 'request_id' } else { '' }
$supersededDialogSessions = @()

$selfHealResult = if ($issueDetected) {
    Invoke-PublicationSelfHealWrapper -ScriptAbs $publicationSelfHealAbs -EnvAbs $envAbs -IntegrationStatusAbs $integrationStatusAbs -RepairPacketAbs $localRepairPacketAbs
}
else {
    [pscustomobject]@{
        attempted = $false
        repaired = $false
        reason = 'no_publication_divergence_detected'
    }
}

$refreshAfterRepair = Invoke-SharedStateRefresh -ScriptAbs $sharedStateSyncAbs
$postState = Get-RecoveryStateSnapshot -IntegrationStatusAbs $integrationStatusAbs -ListenerStageAbs $listenerStageAbs -DialogIndexAbs $dialogIndexAbs

$repairChanged =
    [bool]($selfHealResult -and $selfHealResult.PSObject.Properties['repaired'] -and $selfHealResult.repaired) -or
    (-not [string]::Equals([string]$preState.current_request_id, [string]$postState.current_request_id, [System.StringComparison]::OrdinalIgnoreCase)) -or
    (-not [string]::Equals([string]$preState.live_objective, [string]$postState.live_objective, [System.StringComparison]::OrdinalIgnoreCase))

$currentCorrelationId = if (-not [string]::IsNullOrWhiteSpace([string]$postState.current_correlation_id)) {
    [string]$postState.current_correlation_id
}
else {
    ('publication_surface_divergence|{0}|{1}' -f [string]$postState.current_task_id, [string]$postState.canonical_objective)
}

$coordinationRequest = $null
$coordinationPublish = [pscustomobject]@{ uploaded = $false; reason = 'not_attempted' }
$assistAck = $null
$assistAckPublish = [pscustomobject]@{ uploaded = $false; reason = 'not_attempted' }
$dialogPublish = $null

if ($issueDetected) {
    $coordinationRequest = New-RecoveryCoordinationRequest -PreState $preState -PostState $postState -CorrelationId $currentCorrelationId -SupersededRequestId $supersededRequestId
    $coordinationPublish = Publish-PacketToMim -Payload $coordinationRequest -LocalPacketPath $localCoordinationRequestPath -EnvPath $envAbs

    $staleSessions = Get-OpenRecoverySessions -DialogIndex $preState.dialog_index -IssueCode 'publication_surface_divergence'
    if (@($staleSessions).Count -gt 0 -and (Test-Path -Path $dialogScriptAbs)) {
        $supersededDialogSessions = Close-RecoveryDialogSessions -DialogScriptAbs $dialogScriptAbs -EnvAbs $envAbs -Sessions $staleSessions
    }

    if (Test-SafeAssistAck -PostState $postState) {
        $assistAck = New-RecoveryAssistAck -CoordinationRequest $coordinationRequest -PostState $postState -Reason 'TOD recovery assist republished the authoritative live task-request surface and validated canonical objective alignment. This ACK is coordination-only.'
        $assistAckPublish = Publish-PacketToMim -Payload $assistAck -LocalPacketPath $localCoordinationAckPath -EnvPath $envAbs
    }
    else {
        $handoffSessionId = ('tod-remote-recovery-{0}' -f ([string]$coordinationRequest.request_id -replace '[^a-zA-Z0-9._-]', '_'))
        $handoffPayload = [pscustomobject]@{
            source = 'tod-remote-recovery-v1'
            urgency = 'current'
            issue_code = 'publication_surface_divergence'
            request_id = [string]$coordinationRequest.request_id
            task_id = [string]$coordinationRequest.task_id
            objective_id = [string]$coordinationRequest.objective_id
            correlation_id = [string]$coordinationRequest.correlation_id
            supersedes_request_id = $supersededRequestId
            required_echo_fields = @('request_id', 'objective_id', 'task_id', 'correlation_id', 'decision', 'reason', 'target_dispatch_task_id')
            required_ack_path = 'MIM_TOD_COORDINATION_ACK.latest.json'
            reason = 'TOD could not safely forge a coordination ACK because publication alignment is not yet validated. MIM must echo the exact current identifiers above.'
        }
        $dialogPublish = Publish-RecoveryDialogHandoff -DialogScriptAbs $dialogScriptAbs -EnvAbs $envAbs -SessionId $handoffSessionId -TaskId ([string]$coordinationRequest.request_id) -CorrelationId ([string]$coordinationRequest.correlation_id) -Summary 'TOD remote recovery requires a current MIM coordination ACK for publication_surface_divergence using the exact current identifiers.' -PayloadJson ($handoffPayload | ConvertTo-Json -Depth 12 -Compress) -PublishRemoteSwitch:$PublishDialogRemote
    }
}

$refreshAfterPublish = Invoke-SharedStateRefresh -ScriptAbs $sharedStateSyncAbs
$finalState = Get-RecoveryStateSnapshot -IntegrationStatusAbs $integrationStatusAbs -ListenerStageAbs $listenerStageAbs -DialogIndexAbs $dialogIndexAbs

$finalFailureSignals = @($finalState.failure_signals)
$listenerOutcome = Get-StringProperty -InputObject $finalState.integration_status.listener_decision -Name 'decision_outcome'
$listenerReasonCode = Get-StringProperty -InputObject $finalState.integration_status.listener_decision -Name 'reason_code'
$listenerWaiting = [string]::Equals($listenerOutcome, 'acknowledge_and_wait_on_dependency', [System.StringComparison]::OrdinalIgnoreCase)
$mismatchCleared =
    [string]::Equals([string]$finalState.canonical_objective, [string]$finalState.live_objective, [System.StringComparison]::OrdinalIgnoreCase) -and
    ($finalFailureSignals -notcontains 'live_task_request_objective_mismatch') -and
    ($finalFailureSignals -notcontains 'live_task_request_not_promoted')
$remotePublishVerified = [bool]($finalState.bridge_evidence -and $finalState.bridge_evidence.PSObject.Properties['remote_publish_verified'] -and $finalState.bridge_evidence.remote_publish_verified)

$coordinationPacketConsistent = $true
if ($null -ne $coordinationRequest) {
    $coordinationPacketConsistent =
        [string]::Equals([string]$coordinationRequest.objective_id, (Convert-ToObjectiveLabelLocal -Value $finalState.canonical_objective), [System.StringComparison]::OrdinalIgnoreCase) -and
        [string]::Equals([string]$coordinationRequest.task_id, [string]$finalState.current_task_id, [System.StringComparison]::OrdinalIgnoreCase)
}

$assistAckConsistent = $true
if ($null -ne $assistAck) {
    $assistAckConsistent =
        [string]::Equals([string]$assistAck.request_id, [string]$coordinationRequest.request_id, [System.StringComparison]::OrdinalIgnoreCase) -and
        [string]::Equals([string]$assistAck.target_dispatch_task_id, [string]$finalState.current_task_id, [System.StringComparison]::OrdinalIgnoreCase) -and
        [string]::Equals([string]$assistAck.objective_id, [string]$coordinationRequest.objective_id, [System.StringComparison]::OrdinalIgnoreCase)
}

$validationPassed = [bool]($repairChanged -and $remotePublishVerified -and $coordinationPacketConsistent -and $assistAckConsistent)
$clearedWaitingOnMim = [bool]($validationPassed -and $mismatchCleared -and -not $listenerWaiting -and -not [string]::Equals($listenerReasonCode, 'objective_mismatch', [System.StringComparison]::OrdinalIgnoreCase))

$blockingArtifact = ''
if (-not $clearedWaitingOnMim) {
    if (-not $mismatchCleared) {
        $blockingArtifact = $finalState.live_task_request_path
    }
    elseif (-not $remotePublishVerified) {
        $blockingArtifact = $integrationStatusAbs
    }
    elseif ($null -ne $assistAck -and -not [bool]$assistAckPublish.uploaded) {
        $blockingArtifact = $localCoordinationAckPath
    }
    elseif ($listenerWaiting -or [string]::Equals($listenerReasonCode, 'objective_mismatch', [System.StringComparison]::OrdinalIgnoreCase)) {
        $blockingArtifact = (Join-Path $listenerStageAbs 'TOD_MIM_EXECUTION_DECISION.latest.json')
    }
    else {
        $blockingArtifact = $localCoordinationRequestPath
    }
}

$result = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    source = 'tod-remote-recovery-v1'
    objective_id = Convert-ToObjectiveLabelLocal -Value $finalState.canonical_objective
    issue_summary = if ($issueDetected) { 'TOD remote recovery attempted publication-surface coordination repair.' } else { 'No publication-surface divergence requiring remote recovery was detected.' }
    canonical_objective = [pscustomobject]@{
        before = Convert-ToObjectiveLabelLocal -Value $preState.canonical_objective
        after = Convert-ToObjectiveLabelLocal -Value $finalState.canonical_objective
    }
    live_request_objective = [pscustomobject]@{
        before = Convert-ToObjectiveLabelLocal -Value $preState.live_objective
        after = Convert-ToObjectiveLabelLocal -Value $finalState.live_objective
        request_id_before = [string]$preState.current_request_id
        request_id_after = [string]$finalState.current_request_id
    }
    waiting_coordination_request = [pscustomobject]@{
        previous_request_id = $supersededRequestId
        current_request_id = if ($coordinationRequest) { [string]$coordinationRequest.request_id } else { '' }
        task_id = if ($coordinationRequest) { [string]$coordinationRequest.task_id } else { [string]$finalState.current_task_id }
        correlation_id = if ($coordinationRequest) { [string]$coordinationRequest.correlation_id } else { [string]$currentCorrelationId }
        ack_status_before = if ($preState.coordination_ack) { Get-StringProperty -InputObject $preState.coordination_ack -Name 'status' } else { '' }
        ack_status_after = if ($assistAck) { 'acknowledged' } elseif ($finalState.coordination_ack) { Get-StringProperty -InputObject $finalState.coordination_ack -Name 'status' } else { '' }
    }
    artifact_written = [pscustomobject]@{
        self_heal_repair_packet = if (Test-Path -Path $localRepairPacketAbs) { $localRepairPacketAbs } else { '' }
        coordination_request = if ([bool]$coordinationPublish.uploaded) { $localCoordinationRequestPath } else { '' }
        coordination_ack = if ([bool]$assistAckPublish.uploaded) { $localCoordinationAckPath } else { '' }
        dialog_handoff_published = if ($dialogPublish -and [bool]$dialogPublish.published) { $true } else { $false }
        superseded_dialog_sessions = @($supersededDialogSessions)
    }
    validation = [pscustomobject]@{
        shared_state_refresh_before = $refreshBefore
        publication_self_heal = $selfHealResult
        shared_state_refresh_after_repair = $refreshAfterRepair
        shared_state_refresh_after_publish = $refreshAfterPublish
        repair_changed = [bool]$repairChanged
        mismatch_cleared = [bool]$mismatchCleared
        remote_publish_verified = [bool]$remotePublishVerified
        coordination_packet_consistent = [bool]$coordinationPacketConsistent
        assist_ack_consistent = [bool]$assistAckConsistent
        listener_decision_outcome = $listenerOutcome
        listener_reason_code = $listenerReasonCode
        bridge_failure_signals = @($finalFailureSignals)
        passed = [bool]$validationPassed
    }
    status = if ($clearedWaitingOnMim) { 'recovered' } elseif ($validationPassed) { 'repaired_pending_listener_acceptance' } else { 'blocked' }
    operator_intervention_required = [bool](-not $clearedWaitingOnMim)
    exact_blocking_artifact = $blockingArtifact
    next_verification_command = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-TODMimRemoteRecovery.ps1 -EmitJson'
}

Write-JsonFile -PathValue $reportPath -Payload $result

if ($EmitJson) {
    $result | ConvertTo-Json -Depth 20
    return
}

Write-Host ('Issue summary: {0}' -f [string]$result.issue_summary)
Write-Host ('Canonical objective: {0} -> {1}' -f [string]$result.canonical_objective.before, [string]$result.canonical_objective.after)
Write-Host ('Live request objective: {0} -> {1}' -f [string]$result.live_request_objective.before, [string]$result.live_request_objective.after)
Write-Host ('Current waiting coordination request: {0}' -f [string]$result.waiting_coordination_request.current_request_id)
Write-Host ('Artifact written: coordination_request={0} coordination_ack={1} report={2}' -f [string]$result.artifact_written.coordination_request, [string]$result.artifact_written.coordination_ack, $reportPath)
Write-Host ('Next verification command: {0}' -f [string]$result.next_verification_command)
Write-Host ('Operator intervention required: {0}' -f [string]$result.operator_intervention_required)
if (-not [string]::IsNullOrWhiteSpace([string]$result.exact_blocking_artifact)) {
    Write-Warning ('Blocking artifact: {0}' -f [string]$result.exact_blocking_artifact)
}