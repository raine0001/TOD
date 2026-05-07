param(
    [string]$RepoRoot = "",
    [string]$RuntimeSharedDir = "",
    [string]$OutputPath = "",
    [switch]$EmitJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-PathOrDefault {
    param(
        [string]$Value,
        [Parameter(Mandatory = $true)][string]$DefaultValue
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $DefaultValue
    }
    return $Value
}

function Read-JsonObject {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -Path $Path)) {
        return $null
    }

    try {
        $raw = Get-Content -Path $Path -Raw
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return $null
        }
        return ($raw | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function New-EventEvidenceMap {
    $eventTypes = @(
        'request_observed',
        'ack_observed',
        'progress_observed',
        'result_observed',
        'blocked_observed',
        'heartbeat_observed'
    )

    $map = [ordered]@{}
    foreach ($eventType in $eventTypes) {
        $map[$eventType] = [ordered]@{
            shadow_count = 0
            status_count = 0
            artifact_count = 0
            request_ids = @()
        }
    }
    return $map
}

function Add-RequestIdToEvent {
    param(
        [Parameter(Mandatory = $true)][hashtable]$EventMap,
        [Parameter(Mandatory = $true)][string]$EventType,
        [string]$RequestId
    )

    if ([string]::IsNullOrWhiteSpace($RequestId)) {
        return
    }

    if (-not $EventMap.ContainsKey($EventType)) {
        return
    }

    $existing = @($EventMap[$EventType].request_ids)
    if ($existing -notcontains $RequestId) {
        $EventMap[$EventType].request_ids = @($existing + $RequestId)
    }
}

function Parse-ObserveMessageId {
    param([string]$MessageId)

    if ([string]::IsNullOrWhiteSpace($MessageId)) {
        return $null
    }

    $prefix = 'obs-'
    if (-not $MessageId.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $null
    }

    $rest = $MessageId.Substring($prefix.Length)
    $dash = $rest.IndexOf('-')
    if ($dash -le 0) {
        return $null
    }

    $eventType = $rest.Substring(0, $dash)
    $requestId = $rest.Substring($dash + 1)
    return [pscustomobject]@{
        event_type = $eventType
        request_id = $requestId
    }
}

$resolvedRepoRoot = Resolve-PathOrDefault -Value $RepoRoot -DefaultValue (Split-Path -Parent $PSScriptRoot)
$resolvedRuntimeSharedDir = Resolve-PathOrDefault -Value $RuntimeSharedDir -DefaultValue (Join-Path $resolvedRepoRoot 'runtime/shared')
$resolvedOutputPath = Resolve-PathOrDefault -Value $OutputPath -DefaultValue (Join-Path $resolvedRuntimeSharedDir 'TOD_MIM_LEDGER_PHASE_A_COVERAGE.latest.json')

$statusPath = Join-Path $resolvedRuntimeSharedDir 'TOD_MIM_LEDGER_OBSERVE_STATUS.latest.json'
$dbPath = Join-Path $resolvedRuntimeSharedDir 'TOD_MIM_MESSAGE_LEDGER.sqlite3'

$eventEvidence = New-EventEvidenceMap
$expectedEventTypes = @($eventEvidence.Keys)

$requestArtifactPath = Join-Path $resolvedRuntimeSharedDir 'MIM_TOD_TASK_REQUEST.latest.json'
$ackArtifactPath = Join-Path $resolvedRuntimeSharedDir 'TOD_MIM_TASK_ACK.latest.json'
$progressArtifactPath = Join-Path $resolvedRuntimeSharedDir 'TOD_MIM_EXECUTION_FEEDBACK.latest.json'
$resultArtifactPath = Join-Path $resolvedRuntimeSharedDir 'TOD_MIM_TASK_RESULT.latest.json'
$heartbeatArtifactPath = Join-Path $resolvedRuntimeSharedDir 'TOD_MIM_LISTENER_STATE.latest.json'

$statusData = Read-JsonObject -Path $statusPath
$statusEvidenceUsed = $false
if ($null -ne $statusData) {
    $statusEventType = ''
    if ($statusData.PSObject.Properties['last_event_type']) {
        $statusEventType = [string]$statusData.last_event_type
    }
    $statusRequestId = ''
    if ($statusData.PSObject.Properties['last_request_id']) {
        $statusRequestId = [string]$statusData.last_request_id
    }

    if (-not [string]::IsNullOrWhiteSpace($statusEventType) -and $eventEvidence.Contains($statusEventType)) {
        $eventEvidence[$statusEventType].status_count = [int]$eventEvidence[$statusEventType].status_count + 1
        Add-RequestIdToEvent -EventMap $eventEvidence -EventType $statusEventType -RequestId $statusRequestId
        $statusEvidenceUsed = $true
    }
}

$shadowEvidenceUsed = $false
$shadowRowCount = 0
if (Test-Path -Path $dbPath) {
    try {
        Add-Type -AssemblyName System.Data.SQLite -ErrorAction SilentlyContinue | Out-Null
    }
    catch {
        # No-op: native provider may not be available via Add-Type, use python fallback below.
    }

    $pythonProbe = @'
import json
import sqlite3
import sys

db_path = sys.argv[1]
rows_out = []
conn = sqlite3.connect(db_path)
try:
    conn.row_factory = sqlite3.Row
    rows = conn.execute("select message_id, payload_json from agent_ledger_messages where message_id like 'obs-%'").fetchall()
    for row in rows:
        rows_out.append({"message_id": row["message_id"], "payload_json": row["payload_json"]})
finally:
    conn.close()

print(json.dumps(rows_out, ensure_ascii=True))
'@

    $pythonAvailable = $false
    foreach ($candidate in @('python', 'python3')) {
        try {
            $null = & $candidate --version 2>$null
            if ($LASTEXITCODE -eq 0) {
                $pythonCommand = $candidate
                $pythonAvailable = $true
                break
            }
        }
        catch {
            $pythonAvailable = $false
        }
    }

    if ($pythonAvailable) {
        try {
            $pythonRowsRaw = & $pythonCommand -c $pythonProbe $dbPath 2>$null
            if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace([string]$pythonRowsRaw)) {
                $pythonRows = $pythonRowsRaw | ConvertFrom-Json
                foreach ($row in @($pythonRows)) {
                    $parsed = Parse-ObserveMessageId -MessageId ([string]$row.message_id)
                    if ($null -eq $parsed) {
                        continue
                    }

                    $eventType = [string]$parsed.event_type
                    if (-not $eventEvidence.Contains($eventType)) {
                        continue
                    }

                    $shadowRowCount += 1
                    $eventEvidence[$eventType].shadow_count = [int]$eventEvidence[$eventType].shadow_count + 1

                    $requestId = [string]$parsed.request_id
                    if (-not [string]::IsNullOrWhiteSpace([string]$row.payload_json)) {
                        try {
                            $payload = ([string]$row.payload_json | ConvertFrom-Json)
                            if ($payload -and $payload.PSObject.Properties['request_id'] -and -not [string]::IsNullOrWhiteSpace([string]$payload.request_id)) {
                                $requestId = [string]$payload.request_id
                            }
                        }
                        catch {
                            # Keep parsed request id from message_id.
                        }
                    }

                    Add-RequestIdToEvent -EventMap $eventEvidence -EventType $eventType -RequestId $requestId
                }
                if ($shadowRowCount -gt 0) {
                    $shadowEvidenceUsed = $true
                }
            }
        }
        catch {
            $shadowEvidenceUsed = $false
        }
    }
}

$requestArtifact = Read-JsonObject -Path $requestArtifactPath
if ($null -ne $requestArtifact) {
    $eventEvidence['request_observed'].artifact_count = [int]$eventEvidence['request_observed'].artifact_count + 1
    $requestId = ''
    if ($requestArtifact.PSObject.Properties['request_id']) {
        $requestId = [string]$requestArtifact.request_id
    }
    Add-RequestIdToEvent -EventMap $eventEvidence -EventType 'request_observed' -RequestId $requestId
}

$ackArtifact = Read-JsonObject -Path $ackArtifactPath
if ($null -ne $ackArtifact) {
    $eventEvidence['ack_observed'].artifact_count = [int]$eventEvidence['ack_observed'].artifact_count + 1
    $requestId = ''
    if ($ackArtifact.PSObject.Properties['request_id']) {
        $requestId = [string]$ackArtifact.request_id
    }
    Add-RequestIdToEvent -EventMap $eventEvidence -EventType 'ack_observed' -RequestId $requestId
}

$progressArtifact = Read-JsonObject -Path $progressArtifactPath
if ($null -ne $progressArtifact) {
    $eventEvidence['progress_observed'].artifact_count = [int]$eventEvidence['progress_observed'].artifact_count + 1
    $requestId = ''
    if ($progressArtifact.PSObject.Properties['request_id']) {
        $requestId = [string]$progressArtifact.request_id
    }
    Add-RequestIdToEvent -EventMap $eventEvidence -EventType 'progress_observed' -RequestId $requestId
}

$resultArtifact = Read-JsonObject -Path $resultArtifactPath
if ($null -ne $resultArtifact) {
    $resultStatus = ''
    if ($resultArtifact.PSObject.Properties['status']) {
        $resultStatus = ([string]$resultArtifact.status).Trim().ToLowerInvariant()
    }

    $requestId = ''
    if ($resultArtifact.PSObject.Properties['request_id']) {
        $requestId = [string]$resultArtifact.request_id
    }

    if ([string]::Equals($resultStatus, 'blocked', [System.StringComparison]::OrdinalIgnoreCase)) {
        $eventEvidence['blocked_observed'].artifact_count = [int]$eventEvidence['blocked_observed'].artifact_count + 1
        Add-RequestIdToEvent -EventMap $eventEvidence -EventType 'blocked_observed' -RequestId $requestId
    }
    else {
        $eventEvidence['result_observed'].artifact_count = [int]$eventEvidence['result_observed'].artifact_count + 1
        Add-RequestIdToEvent -EventMap $eventEvidence -EventType 'result_observed' -RequestId $requestId
    }
}

$heartbeatArtifact = Read-JsonObject -Path $heartbeatArtifactPath
if ($null -ne $heartbeatArtifact) {
    $eventEvidence['heartbeat_observed'].artifact_count = [int]$eventEvidence['heartbeat_observed'].artifact_count + 1
    $requestId = ''
    if ($heartbeatArtifact.PSObject.Properties['request_id']) {
        $requestId = [string]$heartbeatArtifact.request_id
    }
    Add-RequestIdToEvent -EventMap $eventEvidence -EventType 'heartbeat_observed' -RequestId $requestId
}

$recordedEventTypes = @()
foreach ($eventType in $expectedEventTypes) {
    $ev = $eventEvidence[$eventType]
    if (([int]$ev.shadow_count + [int]$ev.status_count + [int]$ev.artifact_count) -gt 0) {
        $recordedEventTypes += $eventType
    }
}

$missingEventTypes = @($expectedEventTypes | Where-Object { $recordedEventTypes -notcontains $_ })
$expectedTotal = [int]$expectedEventTypes.Count
$recordedTotal = [int]$recordedEventTypes.Count
$coveragePercent = if ($expectedTotal -gt 0) {
    [math]::Round((100.0 * $recordedTotal) / $expectedTotal, 2)
}
else {
    0.0
}

$errorText = ''
if (-not $shadowEvidenceUsed -and -not $statusEvidenceUsed) {
    $errorText = 'No local shadow-event evidence found in SQLite or status artifact; coverage is derived from lifecycle artifacts only.'
}

$eventBreakdown = [ordered]@{}
foreach ($eventType in $expectedEventTypes) {
    $ev = $eventEvidence[$eventType]
    $eventBreakdown[$eventType] = [ordered]@{
        shadow_count = [int]$ev.shadow_count
        status_count = [int]$ev.status_count
        artifact_count = [int]$ev.artifact_count
        observed_total = [int]$ev.shadow_count + [int]$ev.status_count + [int]$ev.artifact_count
        request_ids = @($ev.request_ids)
    }
}

$artifactExists = [ordered]@{
    request = (Test-Path -Path $requestArtifactPath)
    ack = (Test-Path -Path $ackArtifactPath)
    progress = (Test-Path -Path $progressArtifactPath)
    result = (Test-Path -Path $resultArtifactPath)
    heartbeat = (Test-Path -Path $heartbeatArtifactPath)
}

$report = [ordered]@{
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    report_id = ('phase-a-coverage-' + [guid]::NewGuid().ToString('N'))
    objective = 'TOD-MIM-LEDGER-PHASE-A-COVERAGE-REPORT'
    observe_only = $true
    non_blocking_confirmed = $true
    runtime_impact = 'none'
    expected = [ordered]@{
        lifecycle_event_types = @($expectedEventTypes)
        total = $expectedTotal
    }
    recorded = [ordered]@{
        lifecycle_event_types = @($recordedEventTypes)
        total = $recordedTotal
        event_breakdown = $eventBreakdown
        missing_event_types = @($missingEventTypes)
        request_ids_by_event = $eventBreakdown
    }
    coverage_percent = $coveragePercent
    evidence = [ordered]@{
        sqlite_db_path = $dbPath
        sqlite_db_exists = (Test-Path -Path $dbPath)
        sqlite_shadow_rows = $shadowRowCount
        status_path = $statusPath
        status_exists = (Test-Path -Path $statusPath)
        status_evidence_used = $statusEvidenceUsed
        artifact_exists = $artifactExists
    }
    error = $errorText
}

$outDir = Split-Path -Parent $resolvedOutputPath
if (-not (Test-Path -Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

$json = $report | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText($resolvedOutputPath, ($json + "`n"), (New-Object System.Text.UTF8Encoding($false)))

if ($EmitJson) {
    Write-Output $json
}
else {
    Write-Output ("Phase A coverage report written: {0}" -f $resolvedOutputPath)
    Write-Output ("Coverage: {0}% ({1}/{2})" -f $coveragePercent, $recordedTotal, $expectedTotal)
}
