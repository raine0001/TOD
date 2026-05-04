param(
    [Parameter(Mandatory = $true)]
    [string]$PayloadPath,
    [string]$SnapshotPath = 'tod/out/context-sync/mim_wall/MIM_WALL_STATE_ADAPTER.latest.json',
    [string]$EnvelopePath = 'tod/out/context-sync/mim_wall/MIM_WALL_STATE_ADAPTER_ENVELOPE.latest.json',
    [string]$EventProjectionPath = 'shared_state/mim_wall_event_projection.latest.json',
    [string]$SummaryPath = 'shared_state/mim_wall_state.latest.json',
    [string]$ReceiptPath = 'shared_state/mim_wall_state_import.latest.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot

function Resolve-RepoPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return $PathValue
    }

    return (Join-Path $repoRoot $PathValue)
}

function Ensure-Directory {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if (-not (Test-Path -Path $PathValue)) {
        New-Item -ItemType Directory -Path $PathValue -Force | Out-Null
    }
}

function Write-JsonNoBom {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)]$Payload,
        [int]$Depth = 24
    )

    $directory = Split-Path -Parent $PathValue
    Ensure-Directory -PathValue $directory

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($PathValue, ($Payload | ConvertTo-Json -Depth $Depth), $utf8NoBom)
}

function Get-PropertyValue {
    param(
        [Parameter(Mandatory = $true)]$InputObject,
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

function Require-PropertyValue {
    param(
        [Parameter(Mandatory = $true)]$InputObject,
        [Parameter(Mandatory = $true)][string]$PropertyName
    )

    $value = Get-PropertyValue -InputObject $InputObject -PropertyName $PropertyName
    if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) {
        throw ("Missing required property: {0}" -f $PropertyName)
    }

    return $value
}

function Convert-ToIsoTimestamp {
    param(
        $Value,
        [string]$Fallback
    )

    if ($null -eq $Value) {
        return $Fallback
    }

    $raw = [string]$Value
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return $Fallback
    }

    $milliseconds = 0L
    if ([int64]::TryParse($raw, [ref]$milliseconds)) {
        try {
            return [DateTimeOffset]::FromUnixTimeMilliseconds($milliseconds).UtcDateTime.ToString('o')
        }
        catch {
            return $Fallback
        }
    }

    $dateValue = [datetime]::MinValue
    if ([datetime]::TryParse($raw, [ref]$dateValue)) {
        return $dateValue.ToUniversalTime().ToString('o')
    }

    return $Fallback
}

function Get-SanitizedToken {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return 'unknown'
    }

    return (($Value.ToLowerInvariant() -replace '[^a-z0-9]+', '_').Trim('_'))
}

function New-CanonicalEvent {
    param(
        [Parameter(Mandatory = $true)][string]$EventType,
        [Parameter(Mandatory = $true)][string]$OccurredAt,
        [Parameter(Mandatory = $true)]$Subject,
        [Parameter(Mandatory = $true)]$Payload,
        [string]$ThreadKey = '',
        [string]$StateStatus = '',
        [string]$StateSummary = ''
    )

    return [pscustomobject]@{
        event_id = ([guid]::NewGuid().ToString('N'))
        event_type = $EventType
        occurred_at = $OccurredAt
        project_id = 'mim_wall'
        adapter_id = 'mim_wall_state_adapter_v1'
        subject = $Subject
        channel = [pscustomobject]@{
            kind = 'phone'
            direction = 'inbound'
            thread_id = $ThreadKey
        }
        state = [pscustomobject]@{
            status = $StateStatus
            summary = $StateSummary
        }
        payload = $Payload
        correlation = [pscustomobject]@{
            thread_key = $ThreadKey
        }
        confidence = 1.0
        mutability = 'derived_projection'
        privacy = [pscustomobject]@{
            contains_pii = $true
            redaction_level = 'restricted'
        }
    }
}

function Get-TimelineEventType {
    param(
        [string]$Category,
        [string]$Detail
    )

    $normalizedCategory = [string]$Category
    $normalizedDetail = [string]$Detail

    if ($normalizedDetail -match 'busy-call interception') {
        return 'communication.call.busy_intercepted'
    }

    switch ($normalizedCategory.ToLowerInvariant()) {
        'screening' { return 'communication.call.screened' }
        'live_call' { return 'communication.call.live_state_changed' }
        'sms_reply' { return 'communication.sms.reply_state_changed' }
        'sms_owner' { return 'communication.sms.owner_decision' }
        'follow_up' { return 'queue.item.follow_up_scheduled' }
        'action' { return 'queue.item.action_taken' }
        default { return ('mim_wall.timeline.{0}' -f (Get-SanitizedToken -Value $normalizedCategory)) }
    }
}

$resolvedPayloadPath = Resolve-RepoPath -PathValue $PayloadPath
$resolvedSnapshotPath = Resolve-RepoPath -PathValue $SnapshotPath
$resolvedEnvelopePath = Resolve-RepoPath -PathValue $EnvelopePath
$resolvedEventProjectionPath = Resolve-RepoPath -PathValue $EventProjectionPath
$resolvedSummaryPath = Resolve-RepoPath -PathValue $SummaryPath
$resolvedReceiptPath = Resolve-RepoPath -PathValue $ReceiptPath

if (-not (Test-Path -Path $resolvedPayloadPath)) {
    throw ("Payload path not found: {0}" -f $resolvedPayloadPath)
}

$rawPayload = Get-Content -Path $resolvedPayloadPath -Raw -Encoding UTF8
$envelope = $rawPayload | ConvertFrom-Json
$snapshotNode = Get-PropertyValue -InputObject $envelope -PropertyName 'snapshot' -Default $envelope

if ($snapshotNode -is [string]) {
    $snapshot = ([string]$snapshotNode | ConvertFrom-Json)
}
else {
    $snapshot = $snapshotNode
}

$projectId = [string](Require-PropertyValue -InputObject $snapshot -PropertyName 'project_id')
$adapterId = [string](Require-PropertyValue -InputObject $snapshot -PropertyName 'adapter_id')
$generatedAt = [string](Require-PropertyValue -InputObject $snapshot -PropertyName 'generated_at')

if ($projectId -ne 'mim_wall') {
    throw ("Unsupported project_id: {0}" -f $projectId)
}

if ($adapterId -ne 'mim_wall_state_adapter_v1') {
    throw ("Unsupported adapter_id: {0}" -f $adapterId)
}

$queueItems = @((Get-PropertyValue -InputObject $snapshot -PropertyName 'queue' -Default @()))
$timelineItems = @((Get-PropertyValue -InputObject $snapshot -PropertyName 'timeline' -Default @()))
$feedbackItems = @((Get-PropertyValue -InputObject $snapshot -PropertyName 'feedback' -Default @()))
$controlState = Get-PropertyValue -InputObject $snapshot -PropertyName 'control_state' -Default ([pscustomobject]@{})
$device = Get-PropertyValue -InputObject $snapshot -PropertyName 'device' -Default ([pscustomobject]@{})
$namespace = [string](Get-PropertyValue -InputObject $envelope -PropertyName 'namespace' -Default 'mim')
$source = [string](Get-PropertyValue -InputObject $envelope -PropertyName 'source' -Default 'mim-assist-mobile')
$ingestedAt = (Get-Date).ToUniversalTime().ToString('o')

$projectedEvents = New-Object System.Collections.ArrayList

foreach ($item in $queueItems) {
    $threadKey = [string](Get-PropertyValue -InputObject $item -PropertyName 'thread_key' -Default '')
    $occurredAt = Convert-ToIsoTimestamp -Value (Get-PropertyValue -InputObject $item -PropertyName 'timestamp_ms') -Fallback $generatedAt
    $subjectIdentity = if ([string]::IsNullOrWhiteSpace($threadKey)) { 'phone:unknown' } else { 'phone:' + $threadKey }
    [void]$projectedEvents.Add((New-CanonicalEvent -EventType 'queue.item.discovered' -OccurredAt $occurredAt -Subject ([pscustomobject]@{ identity_id = $subjectIdentity; role = 'caller' }) -Payload ([pscustomobject]@{ raw = $item }) -ThreadKey $threadKey -StateStatus ([string](Get-PropertyValue -InputObject $item -PropertyName 'status' -Default 'pending')) -StateSummary ([string](Get-PropertyValue -InputObject $item -PropertyName 'summary' -Default ''))))
}

foreach ($item in $timelineItems) {
    $occurredAt = Convert-ToIsoTimestamp -Value (Get-PropertyValue -InputObject $item -PropertyName 'timestamp_ms') -Fallback $generatedAt
    $category = [string](Get-PropertyValue -InputObject $item -PropertyName 'category' -Default '')
    $detail = [string](Get-PropertyValue -InputObject $item -PropertyName 'detail' -Default '')
    [void]$projectedEvents.Add((New-CanonicalEvent -EventType (Get-TimelineEventType -Category $category -Detail $detail) -OccurredAt $occurredAt -Subject ([pscustomobject]@{ identity_id = 'mim_wall:timeline'; role = 'system' }) -Payload ([pscustomobject]@{ raw = $item }) -StateStatus $category -StateSummary $detail))
}

foreach ($item in $feedbackItems) {
    $occurredAt = Convert-ToIsoTimestamp -Value (Get-PropertyValue -InputObject $item -PropertyName 'timestamp_ms') -Fallback $generatedAt
    $label = [string](Get-PropertyValue -InputObject $item -PropertyName 'label' -Default 'unlabeled')
    [void]$projectedEvents.Add((New-CanonicalEvent -EventType 'feedback.user.labeled' -OccurredAt $occurredAt -Subject ([pscustomobject]@{ identity_id = 'mim_wall:feedback'; role = 'operator' }) -Payload ([pscustomobject]@{ raw = $item }) -StateStatus $label -StateSummary ([string](Get-PropertyValue -InputObject $item -PropertyName 'note' -Default ''))))
}

$eventProjection = [pscustomobject]@{
    generated_at = $ingestedAt
    source = 'tod-mim-wall-state-import-v1'
    project_id = $projectId
    adapter_id = $adapterId
    namespace = $namespace
    event_count = @($projectedEvents).Count
    events = @($projectedEvents)
}

$summary = [pscustomobject]@{
    generated_at = $ingestedAt
    source = 'tod-mim-wall-state-import-v1'
    project_id = $projectId
    adapter_id = $adapterId
    namespace = $namespace
    upstream_source = $source
    upstream_generated_at = $generatedAt
    mim_enabled = [bool](Get-PropertyValue -InputObject $controlState -PropertyName 'mim_enabled' -Default $false)
    mode = [string](Get-PropertyValue -InputObject $controlState -PropertyName 'mode' -Default '')
    device_id = [string](Get-PropertyValue -InputObject $device -PropertyName 'device_id' -Default '')
    queue_count = @($queueItems).Count
    timeline_count = @($timelineItems).Count
    feedback_count = @($feedbackItems).Count
    projected_event_count = @($projectedEvents).Count
    latest_queue_thread_key = if (@($queueItems).Count -gt 0) { [string](Get-PropertyValue -InputObject $queueItems[0] -PropertyName 'thread_key' -Default '') } else { '' }
    snapshot_path = $resolvedSnapshotPath
    envelope_path = $resolvedEnvelopePath
    event_projection_path = $resolvedEventProjectionPath
}

$receipt = [pscustomobject]@{
    ok = $true
    generated_at = $ingestedAt
    source = 'tod-mim-wall-state-import-v1'
    project_id = $projectId
    adapter_id = $adapterId
    namespace = $namespace
    snapshot_path = $resolvedSnapshotPath
    envelope_path = $resolvedEnvelopePath
    event_projection_path = $resolvedEventProjectionPath
    summary_path = $resolvedSummaryPath
    payload_path = $resolvedPayloadPath
    queue_count = @($queueItems).Count
    timeline_count = @($timelineItems).Count
    feedback_count = @($feedbackItems).Count
    projected_event_count = @($projectedEvents).Count
}

Write-JsonNoBom -PathValue $resolvedSnapshotPath -Payload $snapshot
Write-JsonNoBom -PathValue $resolvedEnvelopePath -Payload $envelope
Write-JsonNoBom -PathValue $resolvedEventProjectionPath -Payload $eventProjection
Write-JsonNoBom -PathValue $resolvedSummaryPath -Payload $summary
Write-JsonNoBom -PathValue $resolvedReceiptPath -Payload $receipt

$receipt | ConvertTo-Json -Depth 12 | Write-Output