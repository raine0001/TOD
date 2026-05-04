param(
    [ValidateSet('all', 'accept_once', 'duplicate_request_dedup', 'stale_request_rejected', 'superseded_request_ignored', 'sequence_preferred_over_suffix', 'wrong_target_rejected', 'soft_boundary_execute_without_go_order')]
    [string]$Scenario = 'all',
    [string]$OutputRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot

function Get-ResolvedPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return $PathValue
    }

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return [System.IO.Path]::GetFullPath($PathValue)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $PathValue))
}

function Ensure-Directory {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if (-not (Test-Path -Path $PathValue)) {
        New-Item -ItemType Directory -Path $PathValue -Force | Out-Null
    }
}

function Write-Utf8NoBomJson {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)]$Payload,
        [int]$Depth = 20
    )

    $dir = Split-Path -Parent $PathValue
    if (-not [string]::IsNullOrWhiteSpace($dir)) {
        Ensure-Directory -PathValue $dir
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $json = ($Payload | ConvertTo-Json -Depth $Depth) -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($PathValue, $json, $utf8NoBom)
}

function New-SimulationRoot {
    $runId = 'tod-mim-exec-sim-' + (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ') + '-' + ([guid]::NewGuid().ToString('N').Substring(0, 8))
    $rootBase = if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
        Join-Path $repoRoot 'tod/out/tests/tod-mim-execution-simulations'
    }
    else {
        Get-ResolvedPath -PathValue $OutputRoot
    }

    Ensure-Directory -PathValue $rootBase
    $root = Join-Path $rootBase $runId
    Ensure-Directory -PathValue $root
    return $root
}

function Get-UtcNowString {
    return (Get-Date).ToUniversalTime().ToString('o')
}

function Get-TextSha256 {
    param([Parameter(Mandatory = $true)][string]$Value)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
        $hash = $sha.ComputeHash($bytes)
        return ([System.BitConverter]::ToString($hash)).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-RequestIdentifier {
    param([Parameter(Mandatory = $true)]$Request)

    foreach ($field in @('request_id', 'task_id', 'id', 'correlation_id')) {
        if ($Request.PSObject.Properties[$field] -and -not [string]::IsNullOrWhiteSpace([string]$Request.$field)) {
            return [string]$Request.$field
        }
    }

    return ''
}

function Get-TaskOrdinalInfo {
    param(
        [string]$Value,
        [string]$FallbackObjectiveId = ''
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
    }
}

function Get-RequestOrderingInfo {
    param(
        [Parameter(Mandatory = $true)]$Request,
        [string]$FallbackObjectiveId = ''
    )

    $requestId = Get-RequestIdentifier -Request $Request
    $taskId = if ($Request.PSObject.Properties['task_id']) { [string]$Request.task_id } else { '' }
    $candidate = Get-TaskOrdinalInfo -Value $requestId -FallbackObjectiveId $FallbackObjectiveId
    if ($null -eq $candidate -and -not [string]::IsNullOrWhiteSpace($taskId)) {
        $candidate = Get-TaskOrdinalInfo -Value $taskId -FallbackObjectiveId $FallbackObjectiveId
    }

    $sequence = 0L
    if ($Request.PSObject.Properties['sequence'] -and $null -ne $Request.sequence) {
        try { $sequence = [long]$Request.sequence } catch { $sequence = 0L }
    }

    if ($null -eq $candidate -and $sequence -le 0) {
        return $null
    }

    return [pscustomobject]@{
        raw = if ($candidate) { [string]$candidate.raw } elseif (-not [string]::IsNullOrWhiteSpace($taskId)) { $taskId } else { $requestId }
        objective_id = if ($candidate) { [string]$candidate.objective_id } else { [string]$FallbackObjectiveId }
        ordinal = if ($candidate) { [long]$candidate.ordinal } else { 0L }
        sequence = $sequence
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

    if (-not [string]::Equals([string]$RequestOrderingInfo.objective_id, [string]$HighWatermark.objective_id, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $false
    }

    if ([long]$RequestOrderingInfo.sequence -gt 0 -and $HighWatermark.PSObject.Properties['sequence'] -and [long]$HighWatermark.sequence -gt 0) {
        return ([long]$RequestOrderingInfo.sequence -lt [long]$HighWatermark.sequence)
    }

    return ([long]$RequestOrderingInfo.ordinal -gt 0 -and [long]$HighWatermark.ordinal -gt 0 -and [long]$RequestOrderingInfo.ordinal -lt [long]$HighWatermark.ordinal)
}

function Get-SemanticRequestSignature {
    param([Parameter(Mandatory = $true)]$Request)

    $payload = [ordered]@{
        request_id = if ($Request.PSObject.Properties['request_id']) { [string]$Request.request_id } else { '' }
        task_id = if ($Request.PSObject.Properties['task_id']) { [string]$Request.task_id } else { '' }
        objective_id = if ($Request.PSObject.Properties['objective_id']) { [string]$Request.objective_id } else { '' }
        target = if ($Request.PSObject.Properties['target']) { [string]$Request.target } else { '' }
        tod_action = if ($Request.PSObject.Properties['tod_action']) { [string]$Request.tod_action } else { '' }
        action = if ($Request.PSObject.Properties['action']) { [string]$Request.action } else { '' }
        title = if ($Request.PSObject.Properties['title']) { [string]$Request.title } else { '' }
        acceptance_criteria = @($Request.acceptance_criteria | ForEach-Object { [string]$_ })
        constraints = @($Request.constraints | ForEach-Object { [string]$_ })
    }

    return Get-TextSha256 -Value (($payload | ConvertTo-Json -Depth 20 -Compress))
}

function Get-NextSequence {
    param([Parameter(Mandatory = $true)]$State)

    $State.last_outbound_sequence = [long]$State.last_outbound_sequence + 1L
    return [long]$State.last_outbound_sequence
}

function New-RuntimeFields {
    param(
        [Parameter(Mandatory = $true)]$State,
        [AllowNull()]$TriggerPacket
    )

    $sequence = Get-NextSequence -State $State
    $triggerSequence = 0L
    if ($null -ne $TriggerPacket -and $TriggerPacket.PSObject.Properties['sequence'] -and $null -ne $TriggerPacket.sequence) {
        try {
            $triggerSequence = [long]$TriggerPacket.sequence
        }
        catch {
            $triggerSequence = 0L
        }
    }

    $observedAt = Get-UtcNowString
    return [pscustomobject]@{
        sequence = $sequence
        ack_sequence = $sequence
        acknowledged_trigger_sequence = $triggerSequence
        emitted_at = $observedAt
        observed_at = $observedAt
        source_host = 'synthetic'
        source_service = 'tod-mim-execution-simulation'
        source_instance_id = 'synthetic-execution-gate'
        consumer_host = 'synthetic'
        consumer_service = 'tod-mim-execution-simulation'
        consumer_instance_id = 'synthetic-execution-gate'
    }
}

function Add-RuntimeFields {
    param(
        [Parameter(Mandatory = $true)]$Packet,
        [Parameter(Mandatory = $true)]$State,
        [AllowNull()]$TriggerPacket
    )

    $runtime = New-RuntimeFields -State $State -TriggerPacket $TriggerPacket
    foreach ($property in @('sequence', 'ack_sequence', 'acknowledged_trigger_sequence', 'emitted_at', 'observed_at', 'source_host', 'source_service', 'source_instance_id', 'consumer_host', 'consumer_service', 'consumer_instance_id')) {
        $Packet | Add-Member -NotePropertyName $property -NotePropertyValue $runtime.$property -Force
    }

    return $runtime
}

function New-State {
    return [ordered]@{
        last_outbound_sequence = 0L
        last_processed_request_id = ''
        last_processed_request_signature = ''
        last_command_status = ''
        last_command_detail = ''
        last_ack_sequence = 0L
        last_ack_generated_at = ''
        last_result_sequence = 0L
        last_result_generated_at = ''
        last_result_status = ''
        high_watermark_request_id = ''
        high_watermark_objective_id = ''
        high_watermark_ordinal = 0L
        high_watermark_sequence = 0L
        highWatermarkByObjective = @{}
        processed = @{}
        emitted = [ordered]@{
            trigger_ack = @()
            task_ack = @()
            result = @()
            command_status = @()
            decision = @()
        }
    }
}

function New-RequestPacket {
    param(
        [Parameter(Mandatory = $true)][string]$RequestId,
        [Parameter(Mandatory = $true)][string]$ObjectiveId,
        [long]$TriggerSequence,
        [string]$Target = 'TOD',
        [string]$TodAction = 'get-state-bus'
    )

    $now = Get-UtcNowString
    return [pscustomobject]@{
        version = '1.0'
        source = 'MIM'
        target = $Target
        generated_at = $now
        emitted_at = $now
        sequence = $TriggerSequence - 1
        source_host = 'MIM'
        source_service = 'synthetic-mim'
        source_instance_id = 'synthetic-mim-gate'
        correlation_id = ($RequestId + '-corr')
        request_id = $RequestId
        task_id = $RequestId
        objective_id = $ObjectiveId
        title = ('Synthetic execution request ' + $RequestId)
        tod_action = $TodAction
        acceptance_criteria = @('ACK once', 'RESULT once')
        constraints = @('synthetic-only')
    }
}

function New-TriggerPacket {
    param(
        [Parameter(Mandatory = $true)][string]$RequestId,
        [long]$TriggerSequence,
        [string]$Target = 'TOD'
    )

    $now = Get-UtcNowString
    return [pscustomobject]@{
        version = '1.0'
        source = 'MIM'
        target = $Target
        generated_at = $now
        emitted_at = $now
        sequence = $TriggerSequence
        trigger = 'execute_now'
        packet_type = 'mim-to-tod-trigger-v1'
        action_required = 'execute_request'
        request_id = $RequestId
        task_id = $RequestId
        correlation_id = ($RequestId + '-corr')
    }
}

function Write-StepArtifact {
    param(
        [Parameter(Mandatory = $true)][string]$ScenarioDir,
        [Parameter(Mandatory = $true)][int]$StepNumber,
        [Parameter(Mandatory = $true)][string]$FileName,
        [Parameter(Mandatory = $true)]$Payload
    )

    $stepsDir = Join-Path $ScenarioDir 'steps'
    $stepDir = Join-Path $stepsDir ('{0:d2}' -f $StepNumber)
    $latestDir = Join-Path $ScenarioDir 'listener'
    Ensure-Directory -PathValue $stepDir
    Ensure-Directory -PathValue $latestDir

    $stepPath = Join-Path $stepDir $FileName
    $latestPath = Join-Path $latestDir $FileName
    Write-Utf8NoBomJson -PathValue $stepPath -Payload $Payload
    Write-Utf8NoBomJson -PathValue $latestPath -Payload $Payload
    return [pscustomobject]@{
        step_path = $stepPath
        latest_path = $latestPath
    }
}

function Write-ListenerStateSnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$ScenarioDir,
        [Parameter(Mandatory = $true)][int]$StepNumber,
        [Parameter(Mandatory = $true)]$State
    )

    $snapshot = [pscustomobject]@{
        generated_at = Get-UtcNowString
        source = 'tod-mim-execution-simulation'
        last_processed_request_id = [string]$State.last_processed_request_id
        last_processed_request_signature = [string]$State.last_processed_request_signature
        last_command_status = [string]$State.last_command_status
        last_command_detail = [string]$State.last_command_detail
        last_ack_generated_at = [string]$State.last_ack_generated_at
        last_ack_sequence = [long]$State.last_ack_sequence
        last_result_generated_at = [string]$State.last_result_generated_at
        last_result_sequence = [long]$State.last_result_sequence
        last_result_status = [string]$State.last_result_status
        high_watermark_request_id = [string]$State.high_watermark_request_id
        high_watermark_objective_id = [string]$State.high_watermark_objective_id
        high_watermark_ordinal = [long]$State.high_watermark_ordinal
        high_watermark_sequence = [long]$State.high_watermark_sequence
        last_outbound_sequence = [long]$State.last_outbound_sequence
    }

    $null = Write-StepArtifact -ScenarioDir $ScenarioDir -StepNumber $StepNumber -FileName 'listener_state.json' -Payload $snapshot
}

function Add-EmissionRecord {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][string]$Bucket,
        [Parameter(Mandatory = $true)]$Payload,
        [Parameter(Mandatory = $true)][string]$StepName,
        [Parameter(Mandatory = $true)][int]$StepNumber,
        [Parameter(Mandatory = $true)][string]$LatestPath
    )

    $State.emitted[$Bucket] += [pscustomobject]@{
        step = $StepName
        step_number = $StepNumber
        latest_path = $LatestPath
        status = if ($Payload.PSObject.Properties['status']) { [string]$Payload.status } else { '' }
        request_id = if ($Payload.PSObject.Properties['request_id']) { [string]$Payload.request_id } elseif ($Payload.PSObject.Properties['acknowledges']) { [string]$Payload.acknowledges } else { '' }
    }
}

function New-TriggerAckPacket {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)]$Request,
        [Parameter(Mandatory = $true)]$Trigger
    )

    $packet = [pscustomobject]@{
        generated_at = Get-UtcNowString
        source = 'shared-trigger-ack-v1'
        status = 'acknowledged'
        acknowledges = (Get-RequestIdentifier -Request $Request)
        current_task_id = if ($Request.PSObject.Properties['task_id']) { [string]$Request.task_id } else { '' }
        current_correlation_id = if ($Request.PSObject.Properties['correlation_id']) { [string]$Request.correlation_id } else { '' }
        trigger_type = if ($Trigger.PSObject.Properties['trigger']) { [string]$Trigger.trigger } else { '' }
        trigger_packet_type = if ($Trigger.PSObject.Properties['packet_type']) { [string]$Trigger.packet_type } else { '' }
        triggered_artifact = 'MIM_TO_TOD_TRIGGER.latest.json'
    }
    $runtime = Add-RuntimeFields -Packet $packet -State $State -TriggerPacket $Trigger
    $State.last_ack_sequence = [long]$runtime.ack_sequence
    $State.last_ack_generated_at = [string]$packet.generated_at
    return $packet
}

function New-TaskAckPacket {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)]$Request,
        [Parameter(Mandatory = $true)]$Trigger
    )

    $packet = [pscustomobject]@{
        generated_at = Get-UtcNowString
        source = 'tod-mim-task-ack-v1'
        status = 'accepted'
        request_id = (Get-RequestIdentifier -Request $Request)
        objective_id = if ($Request.PSObject.Properties['objective_id']) { [string]$Request.objective_id } else { '' }
        task_id = if ($Request.PSObject.Properties['task_id']) { [string]$Request.task_id } else { '' }
        correlation_id = if ($Request.PSObject.Properties['correlation_id']) { [string]$Request.correlation_id } else { '' }
        action = if ($Request.PSObject.Properties['tod_action']) { [string]$Request.tod_action } else { '' }
        execution_mode = 'bounded'
    }
    $runtime = Add-RuntimeFields -Packet $packet -State $State -TriggerPacket $Trigger
    $State.last_ack_sequence = [long]$runtime.ack_sequence
    $State.last_ack_generated_at = [string]$packet.generated_at
    return $packet
}

function New-ResultPacket {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)]$Request,
        [Parameter(Mandatory = $true)]$Trigger,
        [Parameter(Mandatory = $true)][string]$Status,
        [string]$Action = '',
        [string]$ExecutionMode = 'bounded',
        [AllowNull()]$StaleRequest = $null,
        [string]$OutputPreview = ''
    )

    $packet = [pscustomobject]@{
        generated_at = Get-UtcNowString
        source = 'tod-mim-task-result-v1'
        request_id = (Get-RequestIdentifier -Request $Request)
        objective_id = if ($Request.PSObject.Properties['objective_id']) { [string]$Request.objective_id } else { '' }
        task_id = if ($Request.PSObject.Properties['task_id']) { [string]$Request.task_id } else { '' }
        correlation_id = if ($Request.PSObject.Properties['correlation_id']) { [string]$Request.correlation_id } else { '' }
        status = $Status
        action = $Action
        execution_mode = $ExecutionMode
        started_at = Get-UtcNowString
        completed_at = Get-UtcNowString
        error = ''
        output_preview = $OutputPreview
    }
    if ($null -ne $StaleRequest) {
        $packet | Add-Member -NotePropertyName stale_request -NotePropertyValue $StaleRequest -Force
    }
    $runtime = Add-RuntimeFields -Packet $packet -State $State -TriggerPacket $Trigger
    $State.last_result_sequence = [long]$runtime.ack_sequence
    $State.last_result_generated_at = [string]$packet.generated_at
    $State.last_result_status = [string]$packet.status
    return $packet
}

function New-CommandStatusPacket {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $true)][string]$Detail,
        [Parameter(Mandatory = $true)]$Request,
        [AllowNull()]$AckPacket = $null,
        [AllowNull()]$ResultPacket = $null
    )

    $packet = [pscustomobject]@{
        generated_at = Get-UtcNowString
        source = 'tod-mim-command-status-v1'
        status = $Status
        detail = $Detail
        request_id = (Get-RequestIdentifier -Request $Request)
        task_id = if ($Request.PSObject.Properties['task_id']) { [string]$Request.task_id } else { '' }
        correlation_id = if ($Request.PSObject.Properties['correlation_id']) { [string]$Request.correlation_id } else { '' }
        acted_upon = ($null -ne $ResultPacket)
        ack = if ($null -ne $AckPacket) {
            [pscustomobject]@{
                generated_at = [string]$AckPacket.generated_at
                status = [string]$AckPacket.status
                ack_sequence = [long]$AckPacket.ack_sequence
                acknowledged_trigger_sequence = [long]$AckPacket.acknowledged_trigger_sequence
            }
        } else { $null }
        result = if ($null -ne $ResultPacket) {
            [pscustomobject]@{
                generated_at = [string]$ResultPacket.generated_at
                status = [string]$ResultPacket.status
                action = [string]$ResultPacket.action
                ack_sequence = [long]$ResultPacket.ack_sequence
                acknowledged_trigger_sequence = [long]$ResultPacket.acknowledged_trigger_sequence
            }
        } else { $null }
    }

    $State.last_command_status = $Status
    $State.last_command_detail = $Detail
    return $packet
}

function New-DecisionPacket {
    param(
        [Parameter(Mandatory = $true)][string]$DecisionOutcome,
        [Parameter(Mandatory = $true)][string]$ReasonCode,
        [Parameter(Mandatory = $true)][string]$Summary,
        [Parameter(Mandatory = $true)]$Request,
        [string]$BoundaryClass = 'soft_boundary',
        [string]$AckState = 'not_acked',
        [string]$ExecutionState = 'rejected'
    )

    return [pscustomobject]@{
        generated_at = Get-UtcNowString
        source = 'tod-mim-execution-decision-v1'
        request_id = (Get-RequestIdentifier -Request $Request)
        task_id = if ($Request.PSObject.Properties['task_id']) { [string]$Request.task_id } else { '' }
        correlation_id = if ($Request.PSObject.Properties['correlation_id']) { [string]$Request.correlation_id } else { '' }
        decision_outcome = $DecisionOutcome
        reason_code = $ReasonCode
        summary = $Summary
        boundary_class = $BoundaryClass
        ack_state = $AckState
        execution_state = $ExecutionState
    }
}

function Get-HighWatermark {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][string]$ObjectiveId
    )

    if ([string]::IsNullOrWhiteSpace($ObjectiveId)) {
        return $null
    }

    if ($State.highWatermarkByObjective.ContainsKey($ObjectiveId)) {
        return $State.highWatermarkByObjective[$ObjectiveId]
    }

    return $null
}

function Set-HighWatermark {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)]$OrderingInfo
    )

    $current = Get-HighWatermark -State $State -ObjectiveId ([string]$OrderingInfo.objective_id)
    $shouldUpdate = $false
    if ($null -eq $current) {
        $shouldUpdate = $true
    }
    elseif ([long]$OrderingInfo.sequence -gt 0 -and $current.PSObject.Properties['sequence'] -and [long]$current.sequence -gt 0) {
        $shouldUpdate = ([long]$OrderingInfo.sequence -ge [long]$current.sequence)
    }
    elseif ([long]$OrderingInfo.sequence -gt 0 -and (-not $current.PSObject.Properties['sequence'] -or [long]$current.sequence -le 0)) {
        $shouldUpdate = $true
    }
    else {
        $shouldUpdate = ([long]$OrderingInfo.ordinal -ge [long]$current.ordinal)
    }

    if ($shouldUpdate) {
        $State.highWatermarkByObjective[[string]$OrderingInfo.objective_id] = $OrderingInfo
        $State.high_watermark_request_id = [string]$OrderingInfo.raw
        $State.high_watermark_objective_id = [string]$OrderingInfo.objective_id
        $State.high_watermark_ordinal = [long]$OrderingInfo.ordinal
        $State.high_watermark_sequence = [long]$OrderingInfo.sequence
    }
}

function Invoke-SyntheticStep {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][string]$ScenarioDir,
        [Parameter(Mandatory = $true)][int]$StepNumber,
        [Parameter(Mandatory = $true)][string]$StepName,
        [Parameter(Mandatory = $true)]$Request,
        [Parameter(Mandatory = $true)]$Trigger
    )

    $stepSummary = [ordered]@{
        step = $StepName
        step_number = $StepNumber
        request_id = Get-RequestIdentifier -Request $Request
        task_id = if ($Request.PSObject.Properties['task_id']) { [string]$Request.task_id } else { '' }
        objective_id = if ($Request.PSObject.Properties['objective_id']) { [string]$Request.objective_id } else { '' }
        status = ''
        detail = ''
        emitted = [ordered]@{
            trigger_ack = 0
            task_ack = 0
            result = 0
            decision = 0
        }
        superseded_by_request_id = ''
        decision_outcome = ''
        artifact_paths = [ordered]@{}
    }

    $requestArtifact = Write-StepArtifact -ScenarioDir $ScenarioDir -StepNumber $StepNumber -FileName 'MIM_TOD_TASK_REQUEST.latest.json' -Payload $Request
    $triggerArtifact = Write-StepArtifact -ScenarioDir $ScenarioDir -StepNumber $StepNumber -FileName 'MIM_TO_TOD_TRIGGER.latest.json' -Payload $Trigger
    $stepSummary.artifact_paths.request = $requestArtifact.latest_path
    $stepSummary.artifact_paths.trigger = $triggerArtifact.latest_path

    $requestId = [string]$stepSummary.request_id
    $requestSignature = Get-SemanticRequestSignature -Request $Request
    $objectiveIdRaw = if ($Request.PSObject.Properties['objective_id']) { [string]$Request.objective_id } else { '' }
    $objectiveId = if ($objectiveIdRaw -match '^objective-(?<id>\d+)$') { [string]$matches['id'] } else { $objectiveIdRaw }
    $orderingInfo = Get-RequestOrderingInfo -Request $Request -FallbackObjectiveId $objectiveId
    $highWatermark = if ($null -ne $orderingInfo) { Get-HighWatermark -State $State -ObjectiveId ([string]$orderingInfo.objective_id) } else { $null }
    $wrongTarget = -not [string]::Equals(([string]$Request.target), 'TOD', [System.StringComparison]::OrdinalIgnoreCase)

    $triggerAck = $null
    $taskAck = $null
    $result = $null
    $decision = $null
    $boundaryClass = if ($Request.PSObject.Properties['execution_policy'] -and $Request.execution_policy -and $Request.execution_policy.PSObject.Properties['class'] -and [string]::Equals([string]$Request.execution_policy.class, 'approval_required', [System.StringComparison]::OrdinalIgnoreCase)) { 'hard_boundary' } else { 'soft_boundary' }

    if ($wrongTarget) {
        $stepSummary.status = 'wrong_target_rejected'
        $stepSummary.detail = ('Rejected request {0}; target must be TOD.' -f $requestId)
        $stepSummary.decision_outcome = 'reject_with_specific_policy_reason'
        $decision = New-DecisionPacket -DecisionOutcome 'reject_with_specific_policy_reason' -ReasonCode 'wrong_target' -Summary $stepSummary.detail -Request $Request -BoundaryClass $boundaryClass -AckState 'not_acked' -ExecutionState 'rejected'
    }
    elseif (Test-RequestOrderingIsStale -RequestOrderingInfo $orderingInfo -HighWatermark $highWatermark) {
        $triggerAck = New-TriggerAckPacket -State $State -Request $Request -Trigger $Trigger
        $triggerAckArtifact = Write-StepArtifact -ScenarioDir $ScenarioDir -StepNumber $StepNumber -FileName 'TOD_TO_MIM_TRIGGER_ACK.latest.json' -Payload $triggerAck
        Add-EmissionRecord -State $State -Bucket 'trigger_ack' -Payload $triggerAck -StepName $StepName -StepNumber $StepNumber -LatestPath $triggerAckArtifact.latest_path
        $stepSummary.emitted.trigger_ack = 1
        $stepSummary.artifact_paths.trigger_ack = $triggerAckArtifact.latest_path

        $stepSummary.status = 'stale_request_ignored'
        $stepSummary.detail = ('Ignored stale request {0}; higher-priority task {1} is authoritative.' -f $requestId, [string]$highWatermark.raw)
        $stepSummary.superseded_by_request_id = [string]$highWatermark.raw

        $staleRequest = [pscustomobject]@{
            request_id = $requestId
            task_id = if ($Request.PSObject.Properties['task_id']) { [string]$Request.task_id } else { '' }
            correlation_id = if ($Request.PSObject.Properties['correlation_id']) { [string]$Request.correlation_id } else { '' }
            generated_at = if ($Request.PSObject.Properties['generated_at']) { [string]$Request.generated_at } else { '' }
            reason = 'lower_ordinal_backfill_ignored'
            superseded_by_request_id = [string]$highWatermark.raw
        }

        $result = New-ResultPacket -State $State -Request $Request -Trigger $Trigger -Status 'stale_request_ignored' -Action 'bridge_runtime_sync' -ExecutionMode 'stale_backfill_suppressed' -StaleRequest $staleRequest -OutputPreview 'Synthetic listener preserved the higher-priority request and rejected stale backfill.'
        $resultArtifact = Write-StepArtifact -ScenarioDir $ScenarioDir -StepNumber $StepNumber -FileName 'TOD_MIM_TASK_RESULT.latest.json' -Payload $result
        Add-EmissionRecord -State $State -Bucket 'result' -Payload $result -StepName $StepName -StepNumber $StepNumber -LatestPath $resultArtifact.latest_path
        $stepSummary.emitted.result = 1
        $stepSummary.artifact_paths.result = $resultArtifact.latest_path
        $stepSummary.decision_outcome = 'reject_with_specific_policy_reason'
        $decision = New-DecisionPacket -DecisionOutcome 'reject_with_specific_policy_reason' -ReasonCode 'stale_request_ignored' -Summary $stepSummary.detail -Request $Request -BoundaryClass $boundaryClass -AckState 'not_acked' -ExecutionState 'rejected'
    }
    elseif ($State.processed.ContainsKey($requestId) -and [string]::Equals([string]$State.processed[$requestId], $requestSignature, [System.StringComparison]::OrdinalIgnoreCase)) {
        $stepSummary.status = 'already_processed'
        $stepSummary.detail = ('Deduplicated duplicate semantic request {0} without emitting a new ACK or RESULT.' -f $requestId)
        $stepSummary.decision_outcome = 'reject_with_specific_policy_reason'
        $decision = New-DecisionPacket -DecisionOutcome 'reject_with_specific_policy_reason' -ReasonCode 'already_processed' -Summary $stepSummary.detail -Request $Request -BoundaryClass $boundaryClass -AckState 'not_acked' -ExecutionState 'rejected'
    }
    else {
        $triggerAck = New-TriggerAckPacket -State $State -Request $Request -Trigger $Trigger
        $triggerAckArtifact = Write-StepArtifact -ScenarioDir $ScenarioDir -StepNumber $StepNumber -FileName 'TOD_TO_MIM_TRIGGER_ACK.latest.json' -Payload $triggerAck
        Add-EmissionRecord -State $State -Bucket 'trigger_ack' -Payload $triggerAck -StepName $StepName -StepNumber $StepNumber -LatestPath $triggerAckArtifact.latest_path
        $stepSummary.emitted.trigger_ack = 1
        $stepSummary.artifact_paths.trigger_ack = $triggerAckArtifact.latest_path

        $taskAck = New-TaskAckPacket -State $State -Request $Request -Trigger $Trigger
        $taskAckArtifact = Write-StepArtifact -ScenarioDir $ScenarioDir -StepNumber $StepNumber -FileName 'TOD_MIM_TASK_ACK.latest.json' -Payload $taskAck
        Add-EmissionRecord -State $State -Bucket 'task_ack' -Payload $taskAck -StepName $StepName -StepNumber $StepNumber -LatestPath $taskAckArtifact.latest_path
        $stepSummary.emitted.task_ack = 1
        $stepSummary.artifact_paths.task_ack = $taskAckArtifact.latest_path

        $result = New-ResultPacket -State $State -Request $Request -Trigger $Trigger -Status 'completed' -Action ([string]$Request.tod_action) -ExecutionMode 'bounded' -OutputPreview 'Synthetic execution gate completed the bounded request.'
        $resultArtifact = Write-StepArtifact -ScenarioDir $ScenarioDir -StepNumber $StepNumber -FileName 'TOD_MIM_TASK_RESULT.latest.json' -Payload $result
        Add-EmissionRecord -State $State -Bucket 'result' -Payload $result -StepName $StepName -StepNumber $StepNumber -LatestPath $resultArtifact.latest_path
        $stepSummary.emitted.result = 1
        $stepSummary.artifact_paths.result = $resultArtifact.latest_path

        $stepSummary.status = 'completed'
        $stepSummary.detail = ('Accepted request {0} and emitted one trigger ACK, one task ACK, and one terminal RESULT.' -f $requestId)
        $stepSummary.decision_outcome = 'execute'
        $decision = New-DecisionPacket -DecisionOutcome 'execute' -ReasonCode 'authorized_routine_request' -Summary 'Synthetic listener executed authorized soft-boundary work without waiting on human start confirmation.' -Request $Request -BoundaryClass $boundaryClass -AckState 'accepted' -ExecutionState 'completed'
        $State.processed[$requestId] = $requestSignature
        $State.last_processed_request_id = $requestId
        $State.last_processed_request_signature = $requestSignature
        if ($null -ne $orderingInfo) {
            Set-HighWatermark -State $State -OrderingInfo $orderingInfo
        }
    }

    if ($null -ne $decision) {
        $decisionArtifact = Write-StepArtifact -ScenarioDir $ScenarioDir -StepNumber $StepNumber -FileName 'TOD_MIM_EXECUTION_DECISION.latest.json' -Payload $decision
        Add-EmissionRecord -State $State -Bucket 'decision' -Payload $decision -StepName $StepName -StepNumber $StepNumber -LatestPath $decisionArtifact.latest_path
        $stepSummary.emitted.decision = 1
        $stepSummary.artifact_paths.decision = $decisionArtifact.latest_path
    }

    $commandStatus = New-CommandStatusPacket -State $State -Status ([string]$stepSummary.status) -Detail ([string]$stepSummary.detail) -Request $Request -AckPacket $taskAck -ResultPacket $result
    if ($null -ne $decision) {
        $commandStatus | Add-Member -NotePropertyName decision -NotePropertyValue $decision -Force
    }
    $commandStatusArtifact = Write-StepArtifact -ScenarioDir $ScenarioDir -StepNumber $StepNumber -FileName 'TOD_MIM_COMMAND_STATUS.latest.json' -Payload $commandStatus
    Add-EmissionRecord -State $State -Bucket 'command_status' -Payload $commandStatus -StepName $StepName -StepNumber $StepNumber -LatestPath $commandStatusArtifact.latest_path
    $stepSummary.artifact_paths.command_status = $commandStatusArtifact.latest_path

    Write-ListenerStateSnapshot -ScenarioDir $ScenarioDir -StepNumber $StepNumber -State $State
    return [pscustomobject]$stepSummary
}

function New-ScenarioResult {
    param(
        [Parameter(Mandatory = $true)][string]$ScenarioName,
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][object[]]$Steps,
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][scriptblock]$Assertion
    )

    $scenarioDir = Join-Path $Root $ScenarioName
    $counts = [pscustomobject]@{
        trigger_ack = @($State.emitted.trigger_ack).Count
        task_ack = @($State.emitted.task_ack).Count
        result = @($State.emitted.result).Count
        command_status = @($State.emitted.command_status).Count
    }
    $ok = & $Assertion $Steps $counts

    return [pscustomobject]@{
        scenario = $ScenarioName
        ok = [bool]$ok
        root = $scenarioDir
        steps = @($Steps)
        counts = $counts
        latest_listener_state = (Join-Path $scenarioDir 'listener/listener_state.json')
        latest_command_status = (Join-Path $scenarioDir 'listener/TOD_MIM_COMMAND_STATUS.latest.json')
        latest_trigger_ack = if ($counts.trigger_ack -gt 0) { (Join-Path $scenarioDir 'listener/TOD_TO_MIM_TRIGGER_ACK.latest.json') } else { '' }
        latest_task_ack = if ($counts.task_ack -gt 0) { (Join-Path $scenarioDir 'listener/TOD_MIM_TASK_ACK.latest.json') } else { '' }
        latest_result = if ($counts.result -gt 0) { (Join-Path $scenarioDir 'listener/TOD_MIM_TASK_RESULT.latest.json') } else { '' }
    }
}

function Invoke-AcceptOnceScenario {
    param([Parameter(Mandatory = $true)][string]$Root)

    $scenarioDir = Join-Path $Root 'accept_once'
    Ensure-Directory -PathValue $scenarioDir
    $state = New-State
    $request = New-RequestPacket -RequestId 'objective-301-task-001' -ObjectiveId 'objective-301' -TriggerSequence 9001
    $trigger = New-TriggerPacket -RequestId 'objective-301-task-001' -TriggerSequence 9001
    $steps = @(Invoke-SyntheticStep -State $state -ScenarioDir $scenarioDir -StepNumber 1 -StepName 'accept-request' -Request $request -Trigger $trigger)

    return New-ScenarioResult -ScenarioName 'accept_once' -Root $Root -Steps $steps -State $state -Assertion {
        param($scenarioSteps, $counts)
        return ([string]$scenarioSteps[0].status -eq 'completed') -and ($counts.trigger_ack -eq 1) -and ($counts.task_ack -eq 1) -and ($counts.result -eq 1)
    }
}

function Invoke-DuplicateRequestDedupScenario {
    param([Parameter(Mandatory = $true)][string]$Root)

    $scenarioDir = Join-Path $Root 'duplicate_request_dedup'
    Ensure-Directory -PathValue $scenarioDir
    $state = New-State
    $request = New-RequestPacket -RequestId 'objective-302-task-004' -ObjectiveId 'objective-302' -TriggerSequence 9010
    $trigger = New-TriggerPacket -RequestId 'objective-302-task-004' -TriggerSequence 9010
    $steps = @(
        Invoke-SyntheticStep -State $state -ScenarioDir $scenarioDir -StepNumber 1 -StepName 'first-delivery' -Request $request -Trigger $trigger
        Invoke-SyntheticStep -State $state -ScenarioDir $scenarioDir -StepNumber 2 -StepName 'duplicate-delivery' -Request $request -Trigger $trigger
    )

    return New-ScenarioResult -ScenarioName 'duplicate_request_dedup' -Root $Root -Steps $steps -State $state -Assertion {
        param($scenarioSteps, $counts)
        return ([string]$scenarioSteps[0].status -eq 'completed') -and ([string]$scenarioSteps[1].status -eq 'already_processed') -and ($counts.trigger_ack -eq 1) -and ($counts.task_ack -eq 1) -and ($counts.result -eq 1)
    }
}

function Invoke-StaleRequestRejectedScenario {
    param([Parameter(Mandatory = $true)][string]$Root)

    $scenarioDir = Join-Path $Root 'stale_request_rejected'
    Ensure-Directory -PathValue $scenarioDir
    $state = New-State
    $currentRequest = New-RequestPacket -RequestId 'objective-303-task-005' -ObjectiveId 'objective-303' -TriggerSequence 9020
    $currentTrigger = New-TriggerPacket -RequestId 'objective-303-task-005' -TriggerSequence 9020
    $staleRequest = New-RequestPacket -RequestId 'objective-303-task-003' -ObjectiveId 'objective-303' -TriggerSequence 9021
    $staleTrigger = New-TriggerPacket -RequestId 'objective-303-task-003' -TriggerSequence 9021
    $currentRequest.sequence = 200
    $staleRequest.sequence = 100
    $steps = @(
        Invoke-SyntheticStep -State $state -ScenarioDir $scenarioDir -StepNumber 1 -StepName 'accept-current' -Request $currentRequest -Trigger $currentTrigger
        Invoke-SyntheticStep -State $state -ScenarioDir $scenarioDir -StepNumber 2 -StepName 'reject-stale' -Request $staleRequest -Trigger $staleTrigger
    )

    return New-ScenarioResult -ScenarioName 'stale_request_rejected' -Root $Root -Steps $steps -State $state -Assertion {
        param($scenarioSteps, $counts)
        return ([string]$scenarioSteps[1].status -eq 'stale_request_ignored') -and ($scenarioSteps[1].emitted.task_ack -eq 0) -and ([string]$scenarioSteps[1].superseded_by_request_id -eq 'objective-303-task-005')
    }
}

function Invoke-SupersededRequestIgnoredScenario {
    param([Parameter(Mandatory = $true)][string]$Root)

    $scenarioDir = Join-Path $Root 'superseded_request_ignored'
    Ensure-Directory -PathValue $scenarioDir
    $state = New-State
    $oldRequest = New-RequestPacket -RequestId 'objective-304-task-006' -ObjectiveId 'objective-304' -TriggerSequence 9030
    $oldTrigger = New-TriggerPacket -RequestId 'objective-304-task-006' -TriggerSequence 9030
    $newRequest = New-RequestPacket -RequestId 'objective-304-task-007' -ObjectiveId 'objective-304' -TriggerSequence 9031
    $newTrigger = New-TriggerPacket -RequestId 'objective-304-task-007' -TriggerSequence 9031
    $steps = @(
        Invoke-SyntheticStep -State $state -ScenarioDir $scenarioDir -StepNumber 1 -StepName 'accept-original' -Request $oldRequest -Trigger $oldTrigger
        Invoke-SyntheticStep -State $state -ScenarioDir $scenarioDir -StepNumber 2 -StepName 'accept-superseding' -Request $newRequest -Trigger $newTrigger
        Invoke-SyntheticStep -State $state -ScenarioDir $scenarioDir -StepNumber 3 -StepName 'ignore-superseded-replay' -Request $oldRequest -Trigger $oldTrigger
    )

    return New-ScenarioResult -ScenarioName 'superseded_request_ignored' -Root $Root -Steps $steps -State $state -Assertion {
        param($scenarioSteps, $counts)
        return ([string]$scenarioSteps[2].status -eq 'stale_request_ignored') -and ([string]$scenarioSteps[2].superseded_by_request_id -eq 'objective-304-task-007') -and ($scenarioSteps[2].emitted.task_ack -eq 0)
    }
}

function Invoke-SequencePreferredOverSuffixScenario {
    param([Parameter(Mandatory = $true)][string]$Root)

    $scenarioDir = Join-Path $Root 'sequence_preferred_over_suffix'
    Ensure-Directory -PathValue $scenarioDir
    $state = New-State

    $olderBySuffix = New-RequestPacket -RequestId 'objective-306-task-mim-arm-safe-home-20260403171131' -ObjectiveId 'objective-306' -TriggerSequence 9045
    $olderBySuffix.sequence = 100
    $olderTrigger = New-TriggerPacket -RequestId 'objective-306-task-mim-arm-safe-home-20260403171131' -TriggerSequence 9045

    $newerBySequence = New-RequestPacket -RequestId 'objective-306-task-mim-arm-scan-pose-1775330845' -ObjectiveId 'objective-306' -TriggerSequence 9046
    $newerBySequence.sequence = 200
    $newerTrigger = New-TriggerPacket -RequestId 'objective-306-task-mim-arm-scan-pose-1775330845' -TriggerSequence 9046

    $steps = @(
        Invoke-SyntheticStep -State $state -ScenarioDir $scenarioDir -StepNumber 1 -StepName 'accept-sequence-100' -Request $olderBySuffix -Trigger $olderTrigger
        Invoke-SyntheticStep -State $state -ScenarioDir $scenarioDir -StepNumber 2 -StepName 'accept-sequence-200' -Request $newerBySequence -Trigger $newerTrigger
        Invoke-SyntheticStep -State $state -ScenarioDir $scenarioDir -StepNumber 3 -StepName 'reject-sequence-100-replay' -Request $olderBySuffix -Trigger $olderTrigger
    )

    return New-ScenarioResult -ScenarioName 'sequence_preferred_over_suffix' -Root $Root -Steps $steps -State $state -Assertion {
        param($scenarioSteps, $counts)
        return ([string]$scenarioSteps[1].status -eq 'completed') -and ([string]$scenarioSteps[2].status -eq 'stale_request_ignored') -and ([string]$scenarioSteps[2].superseded_by_request_id -eq 'objective-306-task-mim-arm-scan-pose-1775330845') -and ($counts.result -eq 3)
    }
}

function Invoke-WrongTargetRejectedScenario {
    param([Parameter(Mandatory = $true)][string]$Root)

    $scenarioDir = Join-Path $Root 'wrong_target_rejected'
    Ensure-Directory -PathValue $scenarioDir
    $state = New-State
    $request = New-RequestPacket -RequestId 'objective-305-task-002' -ObjectiveId 'objective-305' -TriggerSequence 9040 -Target 'OPS'
    $trigger = New-TriggerPacket -RequestId 'objective-305-task-002' -TriggerSequence 9040 -Target 'OPS'
    $steps = @(Invoke-SyntheticStep -State $state -ScenarioDir $scenarioDir -StepNumber 1 -StepName 'reject-wrong-target' -Request $request -Trigger $trigger)

    return New-ScenarioResult -ScenarioName 'wrong_target_rejected' -Root $Root -Steps $steps -State $state -Assertion {
        param($scenarioSteps, $counts)
        return ([string]$scenarioSteps[0].status -eq 'wrong_target_rejected') -and ($counts.trigger_ack -eq 0) -and ($counts.task_ack -eq 0) -and ($counts.result -eq 0)
    }
}

function Invoke-SoftBoundaryExecuteWithoutGoOrderScenario {
    param([Parameter(Mandatory = $true)][string]$Root)

    $scenarioDir = Join-Path $Root 'soft_boundary_execute_without_go_order'
    Ensure-Directory -PathValue $scenarioDir
    $state = New-State
    $request = New-RequestPacket -RequestId 'objective-307-task-soft-boundary-001' -ObjectiveId 'objective-307' -TriggerSequence 8001 -TodAction 'get-state-bus'
    $request | Add-Member -NotePropertyName execution_policy -NotePropertyValue ([pscustomobject]@{ class = 'auto_execute' }) -Force
    $request | Add-Member -NotePropertyName assigned_executor -NotePropertyValue 'codex' -Force
    $steps = @(
        (Invoke-SyntheticStep -ScenarioDir $scenarioDir -State $state -StepNumber 1 -StepName 'soft boundary execute without go order' -Request $request -Trigger (New-TriggerPacket -RequestId 'objective-307-task-soft-boundary-001' -TriggerSequence 8001))
    )

    return New-ScenarioResult -ScenarioName 'soft_boundary_execute_without_go_order' -Root $Root -Steps $steps -State $state -Assertion {
        param($scenarioSteps, $counts)
        return ([string]$scenarioSteps[0].status -eq 'completed') -and ([string]$scenarioSteps[0].decision_outcome -eq 'execute') -and ($counts.trigger_ack -eq 1) -and ($counts.task_ack -eq 1) -and ($counts.result -eq 1)
    }
}

$root = New-SimulationRoot
$results = @()

if ($Scenario -in @('all', 'accept_once')) {
    $results += Invoke-AcceptOnceScenario -Root $root
}

if ($Scenario -in @('all', 'soft_boundary_execute_without_go_order')) {
    $results += Invoke-SoftBoundaryExecuteWithoutGoOrderScenario -Root $root
}
if ($Scenario -in @('all', 'duplicate_request_dedup')) {
    $results += Invoke-DuplicateRequestDedupScenario -Root $root
}
if ($Scenario -in @('all', 'stale_request_rejected')) {
    $results += Invoke-StaleRequestRejectedScenario -Root $root
}
if ($Scenario -in @('all', 'superseded_request_ignored')) {
    $results += Invoke-SupersededRequestIgnoredScenario -Root $root
}
if ($Scenario -in @('all', 'sequence_preferred_over_suffix')) {
    $results += Invoke-SequencePreferredOverSuffixScenario -Root $root
}
if ($Scenario -in @('all', 'wrong_target_rejected')) {
    $results += Invoke-WrongTargetRejectedScenario -Root $root
}

$summary = [pscustomobject]@{
    ok = (@($results | Where-Object { -not [bool]$_.ok }).Count -eq 0)
    generated_at = Get-UtcNowString
    root = $root
    scenario = $Scenario
    scenario_results = @($results)
}

$summaryPath = Join-Path $root 'simulation-summary.json'
$markdownPath = Join-Path $root 'simulation-summary.md'
Write-Utf8NoBomJson -PathValue $summaryPath -Payload $summary -Depth 20

$markdown = @(
    '# TOD-MIM Execution Simulation Summary',
    '',
    ('Generated: {0}' -f $summary.generated_at),
    ('Root: {0}' -f $root),
    ('Overall: {0}' -f $(if ($summary.ok) { 'pass' } else { 'fail' })),
    '',
    '## Scenario Results'
)
foreach ($entry in @($results)) {
    $markdown += ('- {0}: {1}' -f [string]$entry.scenario, $(if ([bool]$entry.ok) { 'pass' } else { 'fail' }))
}
[System.IO.File]::WriteAllText($markdownPath, ($markdown -join "`n") + "`n", (New-Object System.Text.UTF8Encoding($false)))

$summary | ConvertTo-Json -Depth 20