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
    [string]$ValidatorScriptPath = "scripts/Invoke-TODMimListenerValidator.ps1",
    [string]$RuntimeContractValidatorScriptPath = "scripts/validate_tod_mim_runtime_packet.py",
    [string]$ContractSourceDir = "tod/out/context-sync/contracts",
    [int]$PollSeconds = 2,
    [int]$RegressionNoDeltaThreshold = 4,
    [int]$QuarantineFailCycleThreshold = 5,
    [int]$IdleWakeupSeconds = 120,
    [int]$IdleWakeupCooldownSeconds = 300,
    [int]$StatusPublishSeconds = 15,
    [switch]$RunOnce,
    [switch]$ProcessWithoutGoOrder,
    [switch]$PublishIntegrationStatus,
    [switch]$FailOnError
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$scriptVersion = "2026-03-30T15:20Z"
$script:ListenerMutexName = "Global\TOD-MimPacketListener"

$repoRoot = Split-Path -Parent $PSScriptRoot

function Get-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) { return $PathValue }
    return (Join-Path $repoRoot $PathValue)
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
        return (Get-Content -Path $PathValue -Raw | ConvertFrom-Json)
    }
    catch {
        return $null
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
    if (-not [string]::IsNullOrWhiteSpace($Reason)) {
        $State.last_ack_reason = $Reason
    }
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
        last_objective_advanced = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["last_objective_advanced"]) { [string]$ExistingState.last_objective_advanced } else { "" }
        wakeup_count            = if ($null -ne $ExistingState -and $ExistingState.PSObject.Properties["wakeup_count"])            { [int]$ExistingState.wakeup_count }                else { 0 }
    }
}

# Self-improvement task catalog — rotated through when MIM has no pending work.
$script:SelfImprovementTasks = @(
    [pscustomobject]@{ title = "Run full regression suite and document any new failures or flakiness";                    scope = "scripts/TOD.ps1, tod/tests";                                              criteria = "Regression report produced; any failures triaged and recorded in failure taxonomy." }
    [pscustomobject]@{ title = "Review engineering loop history and identify top-3 reliability gaps";                    scope = "scripts/Start-TODMimPacketListener.ps1, tod/data/state.json";             criteria = "Gap analysis written to journal; at least one concrete improvement task proposed." }
    [pscustomobject]@{ title = "Audit MIM-TOD packet protocol for latency, retry, and edge-case coverage";              scope = "scripts/Start-TODMimPacketListener.ps1, scripts/Push-SyntheticResult.ps1"; criteria = "Protocol audit complete; any gaps filed as follow-on tasks." }
    [pscustomobject]@{ title = "Verify quarantine, cadence-reset, and idle-wakeup improvements end-to-end";             scope = "scripts/Start-TODMimPacketListener.ps1, scripts/Start-TOD-UI.ps1";        criteria = "All three mechanisms exercised and pass a manual smoke check." }
    [pscustomobject]@{ title = "Review failure taxonomy and propose routing-confidence penalty updates";                 scope = "scripts/TOD.ps1, tod/config/tod-config.json";                               criteria = "Taxonomy reviewed; penalty update either applied or documented as future work." }
    [pscustomobject]@{ title = "Scan state.json for OOM risk and apply compaction if size exceeds 2 MiB";               scope = "tod/data/state.json, scripts/TOD.ps1";                                      criteria = "state.json size confirmed below 2 MiB or compacted; no data loss." }
)

function Invoke-IdleWakeupIfNeeded {
    param(
        [Parameter(Mandatory=$true)]$ListenerState,
        [Parameter(Mandatory=$true)]$IdleWakeupState,
        [Parameter(Mandatory=$true)][string]$IdleWakeupStatePath,
        [Parameter(Mandatory=$true)][string]$TodScript,
        [Parameter(Mandatory=$true)][string]$SyncScript,
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

    if ($null -ne $state) {
        $terminalStatuses = @("pass", "reviewed_pass", "completed", "closed", "cancelled")
        $currentTasks = @($state.tasks | Where-Object { [string]$_.objective_id -eq $currentObjId })
        $pendingTasks = @($currentTasks | Where-Object { [string]$_.status -notin $terminalStatuses })
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

        # Self-improvement when no MIM work is pending
        if ([string]::IsNullOrWhiteSpace($actionTaken) -and $null -ne $openObjective) {
            $existingTitles = @($state.tasks | Where-Object { [string]$_.objective_id -eq [string]$openObjective.id } | ForEach-Object { [string]$_.title })
            $selfTask = $script:SelfImprovementTasks | Where-Object {
                $t = [string]$_.title
                -not ($existingTitles | Where-Object { [string]$_ -like "*$($t.Substring(0, [math]::Min(40, $t.Length)))*" })
            } | Select-Object -First 1

            if ($null -ne $selfTask -and -not [string]::IsNullOrWhiteSpace([string]$IdleWakeupState.last_self_task_id)) {
                $lastCreatedTitle = ($state.tasks | Where-Object { [string]$_.id -eq [string]$IdleWakeupState.last_self_task_id } | Select-Object -ExpandProperty title -First 1)
                if ([string]::Equals([string]$selfTask.title, $lastCreatedTitle, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $selfTask = $null
                }
            }

            if ($null -ne $selfTask) {
                $wakeupReason = "self_improve"
                Write-Host ("[TOD-LISTENER][IDLE-WAKEUP] No pending MIM work. Creating self-improvement task: {0}" -f [string]$selfTask.title)
                try {
                    $taskRaw = & $TodScript add-task `
                        -ObjectiveId ([string]$openObjective.id) `
                        -Title ([string]$selfTask.title) `
                        -Description ("Autonomous self-improvement task created by idle wake-up after {0}s of inactivity." -f $idleSec) `
                        -Scope ([string]$selfTask.scope) `
                        -AcceptanceCriteria ([string]$selfTask.criteria) 2>&1
                    $newTask   = ($taskRaw -join "") | ConvertFrom-Json -ErrorAction SilentlyContinue
                    $newTaskId = if ($newTask -and $newTask.PSObject.Properties["id"]) { [string]$newTask.id } else { "" }
                    if (-not [string]::IsNullOrWhiteSpace($newTaskId)) {
                        $IdleWakeupState.last_self_task_id = $newTaskId
                        $actionTaken = "created_self_task_$newTaskId"
                        Write-Host ("[TOD-LISTENER][IDLE-WAKEUP] Self-improvement task created: {0}" -f $newTaskId)
                    }
                } catch {
                    Write-Warning ("[TOD-LISTENER][IDLE-WAKEUP] Failed to create self-improvement task: {0}" -f $_.Exception.Message)
                }
            } else {
                $wakeupReason = "self_improve_no_candidates"
                Write-Host "[TOD-LISTENER][IDLE-WAKEUP] No eligible self-improvement tasks remaining. Waiting for MIM."
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
        [AllowNull()]$StaleGuard = $null
    )

    try {
        $effectiveTaskId = Get-NonEmptyPacketValue -Primary ([string]$TaskId) -Fallback ([string]$RequestId)
        $effectiveCorrelationId = Get-NonEmptyPacketValue -Primary ([string]$CorrelationId) -Fallback ([string]$RequestId)
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
        if ($null -eq $effectiveStaleGuard -and $ListenerState.PSObject.Properties['last_stale_guard']) {
            $effectiveStaleGuard = $ListenerState.last_stale_guard
        }
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
        $ListenerState | Add-Member -NotePropertyName last_stale_guard -NotePropertyValue $effectiveStaleGuard -Force

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
            stale_guard = $effectiveStaleGuard
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
            $payload = Get-Content -Path $RequestPath -Raw | ConvertFrom-Json
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
        [string]$CandidateValue,
        [string]$FallbackObjectiveId = ""
    )

    $candidate = Get-TaskOrdinalInfo -Value $CandidateValue -FallbackObjectiveId $FallbackObjectiveId
    if ($null -eq $candidate) {
        return $null
    }

    $existingRequestId = if ($State.PSObject.Properties['high_watermark_request_id']) { [string]$State.high_watermark_request_id } else { "" }
    $existingObjectiveId = if ($State.PSObject.Properties['high_watermark_objective_id']) { [string]$State.high_watermark_objective_id } else { "" }
    $existingOrdinal = if ($State.PSObject.Properties['high_watermark_ordinal']) { [long]$State.high_watermark_ordinal } else { 0L }

    if ([string]::IsNullOrWhiteSpace($existingObjectiveId) -or
        [string]::Equals([string]$candidate.objective_id, $existingObjectiveId, [System.StringComparison]::OrdinalIgnoreCase) -and [long]$candidate.ordinal -gt $existingOrdinal) {
        $State.high_watermark_request_id = [string]$candidate.raw
        $State.high_watermark_objective_id = [string]$candidate.objective_id
        $State.high_watermark_ordinal = [long]$candidate.ordinal
    }

    return [pscustomobject]@{
        raw = if ($State.PSObject.Properties['high_watermark_request_id']) { [string]$State.high_watermark_request_id } else { "" }
        objective_id = if ($State.PSObject.Properties['high_watermark_objective_id']) { [string]$State.high_watermark_objective_id } else { "" }
        ordinal = if ($State.PSObject.Properties['high_watermark_ordinal']) { [long]$State.high_watermark_ordinal } else { 0L }
        source = 'listener_state'
        source_field = 'high_watermark_request_id'
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
        $stateCandidate = [pscustomobject]@{
            raw = [string]$stateCandidate.raw
            objective_id = [string]$stateCandidate.objective_id
            ordinal = [long]$stateCandidate.ordinal
            source = 'listener_state'
            source_field = 'high_watermark_request_id'
        }
        if ($null -eq $best -or [long]$stateCandidate.ordinal -gt [long]$best.ordinal) {
            $best = $stateCandidate
        }
        elseif ($best -and [long]$stateCandidate.ordinal -eq [long]$best.ordinal -and [string]::Equals([string]$stateCandidate.raw, [string]$best.raw, [System.StringComparison]::OrdinalIgnoreCase)) {
            $best = [pscustomobject]@{
                raw = [string]$best.raw
                objective_id = [string]$best.objective_id
                ordinal = [long]$best.ordinal
                source = 'listener_state_and_loop_journal'
                source_field = 'request_id|high_watermark_request_id'
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
        guidance = 'Freshness is currently inferred from the trailing numeric suffix in request_id/task_id. Replace this with an explicit monotonic field.'
        winner = [pscustomobject]@{
            request_field = [string]$RequestOrdinalSourceField
            high_watermark_source = $highWatermarkSource
            high_watermark_field = $highWatermarkField
        }
        comparison_basis = [pscustomobject]@{
            request_id_suffix = [string]::Equals([string]$RequestOrdinalSourceField, 'request_id', [System.StringComparison]::OrdinalIgnoreCase)
            task_id_suffix = [string]::Equals([string]$RequestOrdinalSourceField, 'task_id', [System.StringComparison]::OrdinalIgnoreCase)
            sequence = $false
            emitted_at = $false
            internal_tracked_request_id = $usesInternalTrackedRequestId
        }
        current_request = [pscustomobject]@{
            request_id = [string]$RequestId
            task_id = [string]$TaskId
            source_field = [string]$RequestOrdinalSourceField
            ordinal_value = $requestOrdinalValue
            ordinal = $requestOrdinal
        }
        high_watermark = [pscustomobject]@{
            source = $highWatermarkSource
            source_field = $highWatermarkField
            request_id = $highWatermarkValue
            ordinal = $highWatermarkOrdinal
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
    if ($statusNormalized -eq 'blocked') { return 'execution_readiness_blocked' }
    if ($ReviewGate -and -not [bool]$ReviewGate.passed) { return 'review_gate_failed' }
    if ($ValidatorResult -and -not [bool]$ValidatorResult.passed) { return 'invalid_packet_shape' }
    if ($Execution -and $Execution.PSObject.Properties['execution_mode'] -and [string]::Equals([string]$Execution.execution_mode, 'timeout', [System.StringComparison]::OrdinalIgnoreCase)) { return 'executor_timed_out' }
    return 'executor_failed'
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
        $retryStreak = if ($retryReasonNormalized -eq "none") { 0 } else { $previousRetryStreak + 1 }
        switch ($retryReasonNormalized) {
            "failure" {
                $backoffSeconds = [Math]::Min(30, [Math]::Max($previousBackoff, $BasePollSeconds) + ([Math]::Min($retryStreak, 5) * 2))
            }
            "duplicate_seen" {
                $backoffSeconds = [Math]::Min(18, [Math]::Max($previousBackoff, 0) + [Math]::Min($retryStreak, 4))
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
        [string]$Reason = ""
    )

    $syncError = ""
    try {
        $null = powershell -NoProfile -ExecutionPolicy Bypass -File $SyncScriptAbs -RefreshMimContextFromSsh -PublishTodStatusToMimArm -MimSshHost $HostAlias -MimSshSharedRoot $RemoteRoot -MimSshStagingRoot $SyncStageRoot 2>&1
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
            status = 'planned'
            assigned_executor = 'codex'
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
        if (-not (Test-StringArrayEquivalent -Left @($task.acceptance_criteria) -Right @($acceptanceCriteria))) {
            $task.acceptance_criteria = @($acceptanceCriteria)
            $changed = $true
        }
        if (-not (Test-StringArrayEquivalent -Left @($task.dependencies) -Right @($dependencies))) {
            $task.dependencies = @($dependencies)
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
            assigned_executor = 'codex'
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

    $top = 10
    if ($Request.PSObject.Properties["top"] -and $null -ne $Request.top) {
        try { $top = [int]$Request.top } catch { $top = 10 }
    }

    $startUtc = (Get-Date).ToUniversalTime().ToString("o")

    $readinessRaw = & $TodScriptAbs -Action "get-execution-readiness" -Top 1 2>&1
    $readinessPayload = $null
    try {
        $readinessPayload = ($readinessRaw | ConvertFrom-Json)
    }
    catch {
        $readinessPayload = $null
    }

    $readinessTrace = $null
    if ($null -ne $readinessPayload -and $readinessPayload.PSObject.Properties["readiness"]) {
        $policyOutcome = "allow"
        $blockActions = if ($readinessPayload.PSObject.Properties["policy"] -and $readinessPayload.policy.PSObject.Properties["block_actions"]) { @($readinessPayload.policy.block_actions | ForEach-Object { [string]$_ }) } else { @() }
        $degradeActions = if ($readinessPayload.PSObject.Properties["policy"] -and $readinessPayload.policy.PSObject.Properties["degrade_actions"]) { @($readinessPayload.policy.degrade_actions | ForEach-Object { [string]$_ }) } else { @() }
        $blockStates = if ($readinessPayload.PSObject.Properties["policy"] -and $readinessPayload.policy.PSObject.Properties["block_states"]) { @($readinessPayload.policy.block_states | ForEach-Object { ([string]$_).ToLowerInvariant() }) } else { @("stale", "invalid", "unknown") }
        $degradeStates = if ($readinessPayload.PSObject.Properties["policy"] -and $readinessPayload.policy.PSObject.Properties["degrade_states"]) { @($readinessPayload.policy.degrade_states | ForEach-Object { ([string]$_).ToLowerInvariant() }) } else { @("degraded", "stale", "invalid", "unknown") }
        $readinessValid = if ($readinessPayload.readiness.PSObject.Properties["valid"]) { [bool]$readinessPayload.readiness.valid } else { $false }
        $executionAllowed = if ($readinessPayload.readiness.PSObject.Properties["execution_allowed"]) { [bool]$readinessPayload.readiness.execution_allowed } else { $false }
        $readinessStatus = if ($readinessPayload.readiness.PSObject.Properties["status"]) { ([string]$readinessPayload.readiness.status).ToLowerInvariant() } else { "unknown" }
        if (@($blockActions | Where-Object { [string]::Equals($_, $action, [System.StringComparison]::OrdinalIgnoreCase) }).Count -gt 0 -and ($blockStates -contains $readinessStatus)) {
            $policyOutcome = "block"
        }
        elseif (@($degradeActions | Where-Object { [string]::Equals($_, $action, [System.StringComparison]::OrdinalIgnoreCase) }).Count -gt 0 -and ($degradeStates -contains $readinessStatus)) {
            $policyOutcome = "degrade"
        }

        $readinessTrace = [pscustomobject]@{
            status = if ($readinessPayload.readiness.PSObject.Properties["status"]) { [string]$readinessPayload.readiness.status } else { "unknown" }
            source = if ($readinessPayload.readiness.PSObject.Properties["reason"]) { [string]$readinessPayload.readiness.reason } else { "unknown" }
            detail = if ($readinessPayload.readiness.PSObject.Properties["detail"]) { [string]$readinessPayload.readiness.detail } else { "" }
            valid = $readinessValid
            execution_allowed = $executionAllowed
            authoritative = if ($readinessPayload.readiness.PSObject.Properties["authoritative"]) { [bool]$readinessPayload.readiness.authoritative } else { $true }
            freshness_state = if ($readinessPayload.readiness.PSObject.Properties["freshness_state"]) { [string]$readinessPayload.readiness.freshness_state } else { "unknown" }
            signal_name = if ($readinessPayload.PSObject.Properties["signal_name"]) { [string]$readinessPayload.signal_name } else { "execution-readiness" }
            evaluated_action = $action
            policy_outcome = $policyOutcome
            decision_path = @(
                "signal:execution-readiness",
                    "status:$(if ($readinessPayload.readiness.PSObject.Properties['status']) { [string]$readinessPayload.readiness.status } else { 'unknown' })",
                    "source:$(if ($readinessPayload.readiness.PSObject.Properties['reason']) { [string]$readinessPayload.readiness.reason } else { 'unknown' })",
                "action:$action",
                "policy_outcome:$policyOutcome"
            )
        }
    }

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
    if ($Request.PSObject.Properties["apply_plan"] -and [bool]$Request.apply_plan) {
        $todArgs["ApplyPlan"] = $true
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

        return [pscustomobject]@{
            ok = $true
            blocked = if ($null -ne $payload -and $payload.PSObject.Properties["blocked"]) { [bool]$payload.blocked } else { $false }
            action = $action
            execution_mode = "direct_script_success"
            started_at = $startUtc
            completed_at = $endUtc
            execution_readiness = $payloadReadiness
            execution_trace = $payloadTrace
            payload = $payload
            output = [string]($raw | Out-String)
            error = ""
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

$envAbs = Get-LocalPath -PathValue $EnvFile
$syncScriptAbs = Get-LocalPath -PathValue $SyncScriptPath
$todScriptAbs = Get-LocalPath -PathValue $TodScriptPath
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
$localCommandStatusPath = Join-Path $stageAbs "TOD_MIM_COMMAND_STATUS.latest.json"
$localJournalPath = Join-Path $stageAbs "TOD_LOOP_JOURNAL.latest.json"
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
$remoteCommandStatusPath = ("{0}/TOD_MIM_COMMAND_STATUS.latest.json" -f $RemoteRoot.TrimEnd('/'))
$remoteStatusPath = ("{0}/TOD_INTEGRATION_STATUS.latest.json" -f $RemoteRoot.TrimEnd('/'))
$remoteStatusAliasPath = ("{0}/TOD_integration_status.latest.json" -f $RemoteRoot.TrimEnd('/'))
$remoteJournalPath = ("{0}/TOD_LOOP_JOURNAL.latest.json" -f $RemoteRoot.TrimEnd('/'))
$remoteTriggerAckPath = ("{0}/TOD_TO_MIM_TRIGGER_ACK.latest.json" -f $RemoteRoot.TrimEnd('/'))
$remoteLivenessTriggerPath = ("{0}/MIM_TO_TOD_TRIGGER.latest.json" -f $RemoteRoot.TrimEnd('/'))
$remoteLivenessTriggerAltPath = ("{0}/MIM-TO_TOD_TRIGGER.latest.json" -f $RemoteRoot.TrimEnd('/'))
$remoteLivenessPingPath = ("{0}/MIM_TO_TOD_PING.latest.json" -f $RemoteRoot.TrimEnd('/'))
$remoteLivenessResponsePath = ("{0}/TOD_TO_MIM_PING.latest.json" -f $RemoteRoot.TrimEnd('/'))
$remoteStallAlertPath = ("{0}/TOD_MIM_STALL_ALERT.latest.json" -f $RemoteRoot.TrimEnd('/'))
$remoteCoordinationRequestPath = ("{0}/TOD_MIM_COORDINATION_REQUEST.latest.json" -f $RemoteRoot.TrimEnd('/'))
$remoteCoordinationAckPath = ("{0}/MIM_TOD_COORDINATION_ACK.latest.json" -f $RemoteRoot.TrimEnd('/'))

$listenerState = New-ListenerState -ExistingState (Read-JsonFileIfExists -PathValue $listenerStatePath)
$pythonCommand = Get-PythonCommand
$contractBinding = Get-ContractBindingMetadata -ContractDirPath $contractDirAbs -RemoteSurface $RemoteRoot -LocalStageDir $stageAbs
Write-RuntimeBindingState -StatePath $localRuntimeBindingStatePath -State (Read-RuntimeBindingState -StatePath $localRuntimeBindingStatePath -BindingMetadata $contractBinding)
$regressionStallState = New-RegressionStallState -ExistingState (Read-JsonFileIfExists -PathValue $localRegressionStallPath)
$coordinationEscalationState = New-CoordinationEscalationState -ExistingState (Read-JsonFileIfExists -PathValue $localCoordinationEscalationStatePath)
$quarantineState = New-QuarantineState -ExistingState (Read-JsonFileIfExists -PathValue $localQuarantineStatePath)
$idleWakeupState  = New-IdleWakeupState  -ExistingState (Read-JsonFileIfExists -PathValue $localIdleWakeupStatePath)

$listenerMutex = New-Object System.Threading.Mutex($false, $script:ListenerMutexName)
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
                $existingIssueCode = if ($existingCoordPayload -and $existingCoordPayload.PSObject.Properties["issue_code"]) { [string]$existingCoordPayload.issue_code } else { "" }
                $hasStaleRequestArtifact = [string]::IsNullOrWhiteSpace($existingIssueCode) -or ($existingIssueCode -match "regression")
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
            Write-Host "[TOD-LISTENER] No task request packet found."
            Update-ListenerHeartbeat -State $listenerState -StatePath $listenerStatePath -CycleStartedAt $cycleStartedAt
            $cadencePlan = Update-CadencePlan -ListenerState $listenerState -ListenerStatePath $listenerStatePath -CycleClassification "no_new_work" -RetryReason "no_new_work" -BasePollSeconds $PollSeconds
            Add-LoopJournalEntry -LocalJournalPath $localJournalPath -RequestId "" -ObjectiveId "" -ExecutionStatus "no_new_work" -CycleClassification "no_new_work" -RetryReason "no_new_work" -CadencePlan $cadencePlan
            Invoke-IdleWakeupIfNeeded -ListenerState $listenerState -IdleWakeupState $idleWakeupState -IdleWakeupStatePath $localIdleWakeupStatePath -TodScript $todScriptAbs -SyncScript $syncScriptAbs -HostAlias $hostAlias -RemoteRoot $RemoteRoot -SyncStageRoot $SyncStageDir -IdleThreshold $IdleWakeupSeconds -Cooldown $IdleWakeupCooldownSeconds -RunOnce:$RunOnce
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
        $requestOrdinalSourceField = 'request_id'
        $requestOrdinalInfo = Get-TaskOrdinalInfo -Value $requestId -FallbackObjectiveId $requestObjectiveId
        if ($null -eq $requestOrdinalInfo -and $request.PSObject.Properties['task_id']) {
            $requestOrdinalSourceField = 'task_id'
            $requestOrdinalInfo = Get-TaskOrdinalInfo -Value ([string]$request.task_id) -FallbackObjectiveId $requestObjectiveId
        }
        if ($requestOrdinalInfo) {
            $requestOrdinalInfo.source = 'incoming_request'
            $requestOrdinalInfo.source_field = $requestOrdinalSourceField
        }
        if ($requestOrdinalInfo) {
            $null = Update-TaskHighWatermark -State $listenerState -CandidateValue ([string]$requestOrdinalInfo.raw) -FallbackObjectiveId $requestObjectiveId
        }
        $maxObservedOrdinal = Get-ObjectiveHighWatermark -State $listenerState -JournalPath $localJournalPath -ObjectiveId $requestObjectiveId
        if ($null -ne $requestOrdinalInfo -and $null -ne $maxObservedOrdinal -and [long]$requestOrdinalInfo.ordinal -lt [long]$maxObservedOrdinal.ordinal) {
            $requestTaskIdForStaleGuard = Get-NonEmptyPacketValue -Primary (Get-ObjectFieldText -InputObject $request -FieldName 'task_id') -Fallback $requestId
            $staleGuard = New-StaleGuardMetadata -Decision 'stale_request_ignored' -RequestId $requestId -TaskId $requestTaskIdForStaleGuard -ObjectiveId $requestObjectiveId -RequestOrdinalInfo $requestOrdinalInfo -RequestOrdinalSourceField $requestOrdinalSourceField -HighWatermark $maxObservedOrdinal -TriggerSequence (Get-ObjectFieldLong -InputObject $livenessTrigger -FieldName 'sequence')
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
                Update-ListenerHeartbeat -State $listenerState -StatePath $listenerStatePath -CycleStartedAt $cycleStartedAt
                $cadencePlan = Update-CadencePlan -ListenerState $listenerState -ListenerStatePath $listenerStatePath -CycleClassification 'contract_violation_rejected' -RetryReason 'failure' -BasePollSeconds $PollSeconds
                Add-LoopJournalEntry -LocalJournalPath $localJournalPath -RequestId $requestId -ObjectiveId $requestObjectiveId -AckStatus 'contract_violation_rejected' -ExecutionStatus 'contract_violation_rejected' -CycleClassification 'contract_violation_rejected' -RetryReason 'failure' -CadencePlan $cadencePlan
                if ($RunOnce) { break }
                Start-Sleep -Seconds ([int]$cadencePlan.sleep_seconds)
                continue
            }
            Register-RuntimeValidationResult -StatePath $localRuntimeBindingStatePath -BindingMetadata $contractBinding -PacketKind 'ack' -Packet $staleAck -ValidationResult $staleAckValidation -State 'active' | Out-Null
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
        }

        # Quarantine guard: if this request_id has been quarantined after repeated failures, skip execution entirely.
        if (-not [string]::IsNullOrWhiteSpace([string]$quarantineState.quarantined_request_id) -and
            [string]::Equals($requestId, [string]$quarantineState.quarantined_request_id, [System.StringComparison]::OrdinalIgnoreCase)) {
            Write-Host ("[TOD-LISTENER] Request {0} is QUARANTINED after {1} consecutive fail cycles. Skipping." -f $requestId, [int]$quarantineState.fail_cycle_count)
            Update-ListenerHeartbeat -State $listenerState -StatePath $listenerStatePath -CycleStartedAt $cycleStartedAt
            $cadencePlan = Update-CadencePlan -ListenerState $listenerState -ListenerStatePath $listenerStatePath -CycleClassification "quarantined_failure_retry" -RetryReason "failure" -BasePollSeconds $PollSeconds
            Add-LoopJournalEntry -LocalJournalPath $localJournalPath -RequestId $requestId -ObjectiveId $requestObjectiveId -ExecutionStatus "quarantined" -CycleClassification "quarantined_failure_retry" -RetryReason "failure" -CadencePlan $cadencePlan
            Invoke-IdleWakeupIfNeeded -ListenerState $listenerState -IdleWakeupState $idleWakeupState -IdleWakeupStatePath $localIdleWakeupStatePath -TodScript $todScriptAbs -SyncScript $syncScriptAbs -HostAlias $hostAlias -RemoteRoot $RemoteRoot -SyncStageRoot $SyncStageDir -IdleThreshold $IdleWakeupSeconds -Cooldown $IdleWakeupCooldownSeconds -RunOnce:$RunOnce
            if ($RunOnce) { break }
            Start-Sleep -Seconds ([int]$cadencePlan.sleep_seconds)
            continue
        }

        $lastProcessedSignature = if ($listenerState.PSObject.Properties["last_processed_request_signature"]) { [string]$listenerState.last_processed_request_signature } else { "" }

        if ([string]::Equals($requestId, [string]$listenerState.last_processed_request_id, [System.StringComparison]::OrdinalIgnoreCase) -and
            -not [string]::IsNullOrWhiteSpace($requestSignature) -and
            [string]::Equals($requestSignature, $lastProcessedSignature, [System.StringComparison]::OrdinalIgnoreCase) -and
            -not [bool]$objectiveSync.changed -and
            -not [bool]$taskSync.changed) {
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
            Invoke-IdleWakeupIfNeeded -ListenerState $listenerState -IdleWakeupState $idleWakeupState -IdleWakeupStatePath $localIdleWakeupStatePath -TodScript $todScriptAbs -SyncScript $syncScriptAbs -HostAlias $hostAlias -RemoteRoot $RemoteRoot -SyncStageRoot $SyncStageDir -IdleThreshold $IdleWakeupSeconds -Cooldown $IdleWakeupCooldownSeconds -RunOnce:$RunOnce
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

        if (-not $goAllowed) {
            Write-Host ("[TOD-LISTENER] Request {0} observed; withholding task ACK until GO order is present." -f $requestId)
            Publish-CommandStatus -ListenerState $listenerState -ListenerStatePath $listenerStatePath -LocalPath $localCommandStatusPath -RemotePath $remoteCommandStatusPath -Connections $connections -Status "waiting_go_order" -Detail "Request observed but task ACK withheld until GO order is present so only contract-compliant ACKs are emitted." -RequestId $requestId -TaskId $requestTaskId -CorrelationId $requestCorrelationId -RequestSignature $requestSignature -GoOrderSignature $goOrderSignature -TriggerPacket $livenessTrigger -BridgeRuntime $bridgeRuntime
            Update-ListenerHeartbeat -State $listenerState -StatePath $listenerStatePath -CycleStartedAt $cycleStartedAt
            $cadencePlan = Update-CadencePlan -ListenerState $listenerState -ListenerStatePath $listenerStatePath -CycleClassification "waiting_go_order" -RetryReason "waiting_go_order" -BasePollSeconds $PollSeconds
            Add-LoopJournalEntry -LocalJournalPath $localJournalPath -RequestId $requestId -ObjectiveId $requestObjectiveId -ExecutionStatus "waiting_go_order" -CycleClassification "waiting_go_order" -RetryReason "waiting_go_order" -CadencePlan $cadencePlan
            if ($RunOnce) { break }
            Start-Sleep -Seconds ([int]$cadencePlan.sleep_seconds)
            continue
        }

        $ack = [pscustomobject]@{
            generated_at = (Get-Date).ToUniversalTime().ToString("o")
            source = "tod-mim-task-ack-v1"
            request_id = $requestId
            correlation_id = Get-NonEmptyPacketValue -Primary $(if ($request.PSObject.Properties["correlation_id"]) { [string]$request.correlation_id } else { "" }) -Fallback $requestId
            status = "accepted"
            ack_status = "accepted"
            ack_reason_code = (Get-AckReasonCode -Status 'accepted')
            objective = Get-NonEmptyPacketValue -Primary $(if ($request.PSObject.Properties["objective_id"]) { [string]$request.objective_id } else { "" }) -Fallback $requestObjectiveId
            objective_id = Get-NonEmptyPacketValue -Primary $(if ($request.PSObject.Properties["objective_id"]) { [string]$request.objective_id } else { "" }) -Fallback $requestObjectiveId
            task = Get-NonEmptyPacketValue -Primary $(if ($request.PSObject.Properties["task_id"]) { [string]$request.task_id } else { "" }) -Fallback $requestId
            task_id = Get-NonEmptyPacketValue -Primary $(if ($request.PSObject.Properties["task_id"]) { [string]$request.task_id } else { "" }) -Fallback $requestId
            note = "Request acknowledged and queued for execution."
            bridge_runtime = $bridgeRuntime
        }
        $taskAckTrigger = if ($null -ne $livenessTrigger) { $livenessTrigger } else { $goOrder }
        $null = Add-ContractPacketEnvelope -Packet $ack -BindingMetadata $contractBinding -PacketType 'tod-mim-task-ack-v1' -MessageKind 'ack' -ObjectiveId ([string]$ack.objective_id) -TaskId ([string]$ack.task_id) -RequestId $requestId -CorrelationId ([string]$ack.correlation_id)
        $null = Add-SequenceRuntimeFields -Packet $ack -TriggerPacket $taskAckTrigger -ListenerState $listenerState -ListenerStatePath $listenerStatePath
        $ackValidation = Test-ContractRuntimePacket -PythonCommand $pythonCommand -ValidatorScript $runtimeContractValidatorAbs -BindingMetadata $contractBinding -PacketKind 'ack' -Packet $ack
        if (-not [bool]$ackValidation.passed) {
            $violation = Publish-RuntimeContractViolation -ViolationPath $localRuntimeViolationPath -StatePath $localRuntimeBindingStatePath -BindingMetadata $contractBinding -PacketKind 'ack' -Packet $ack -ValidationResult $ackValidation
            Register-RuntimeValidationResult -StatePath $localRuntimeBindingStatePath -BindingMetadata $contractBinding -PacketKind 'ack' -Packet $ack -ValidationResult $ackValidation -State 'violation' | Out-Null
            Publish-CommandStatus -ListenerState $listenerState -ListenerStatePath $listenerStatePath -LocalPath $localCommandStatusPath -RemotePath $remoteCommandStatusPath -Connections $connections -Status 'contract_violation_rejected' -Detail ('Rejected ACK because runtime contract validation failed: {0}' -f (($violation.violations | ForEach-Object { [string]$_.code + ':' + [string]$_.detail }) -join '; ')) -RequestId $requestId -TaskId $requestTaskId -CorrelationId $requestCorrelationId -RequestSignature $requestSignature -GoOrderSignature $goOrderSignature -TriggerPacket $taskAckTrigger -BridgeRuntime $bridgeRuntime
            Update-ListenerHeartbeat -State $listenerState -StatePath $listenerStatePath -CycleStartedAt $cycleStartedAt
            $cadencePlan = Update-CadencePlan -ListenerState $listenerState -ListenerStatePath $listenerStatePath -CycleClassification 'contract_violation_rejected' -RetryReason 'failure' -BasePollSeconds $PollSeconds
            Add-LoopJournalEntry -LocalJournalPath $localJournalPath -RequestId $requestId -ObjectiveId $requestObjectiveId -ExecutionStatus 'contract_violation_rejected' -CycleClassification 'contract_violation_rejected' -RetryReason 'failure' -CadencePlan $cadencePlan
            if ($RunOnce) { break }
            Start-Sleep -Seconds ([int]$cadencePlan.sleep_seconds)
            continue
        }
        Register-RuntimeValidationResult -StatePath $localRuntimeBindingStatePath -BindingMetadata $contractBinding -PacketKind 'ack' -Packet $ack -ValidationResult $ackValidation -State 'active' | Out-Null
        Write-JsonFile -PathValue $localAckPath -Payload $ack

        $ackJson = Get-Content -Path $localAckPath -Raw
        Write-RemoteFileFromText -Connections $connections -RemotePath $remoteAckPath -Content $ackJson
        Publish-CommandStatus -ListenerState $listenerState -ListenerStatePath $listenerStatePath -LocalPath $localCommandStatusPath -RemotePath $remoteCommandStatusPath -Connections $connections -Status ([string]$ack.status) -Detail "Task ACK emitted to shared path." -RequestId $requestId -TaskId $requestTaskId -CorrelationId $requestCorrelationId -RequestSignature $requestSignature -GoOrderSignature $goOrderSignature -AckPacket $ack -TriggerPacket $taskAckTrigger -BridgeRuntime $bridgeRuntime

        Write-Host ("[TOD-LISTENER] Executing request {0}..." -f $requestId)
        $execution = Invoke-RequestExecution -TodScriptAbs $todScriptAbs -Request $request

        $syncError = Invoke-SharedStateSyncRefresh -SyncScriptAbs $syncScriptAbs -HostAlias $hostAlias -RemoteRoot $RemoteRoot -SyncStageRoot $SyncStageDir -Reason "request execution"

        if ($publishStatus) {
            Publish-IntegrationStatusFiles -Connections $connections -SourcePath $integrationStatusPath -LocalPath $localRemoteStatusFile -RemotePath $remoteStatusPath -LocalAliasPath $localRemoteStatusAliasFile -RemoteAliasPath $remoteStatusAliasPath
            $listenerState.last_status_publish_at = Get-UtcNowString
        }

        $integrationStatus = Read-JsonFileIfExists -PathValue $integrationStatusPath
        $reviewGate = Get-ReviewGateResult -IntegrationStatus $integrationStatus -GoOrder $goOrder -Request $request -RequestId $requestId

        # Snapshot per-cycle inputs so validator cannot drift to a newer packet.
        $validatorSuffix = ([guid]::NewGuid().ToString("N"))
        $validatorRequestPath = Join-Path $stageAbs ("MIM_TOD_TASK_REQUEST.validator.{0}.json" -f $validatorSuffix)
        $validatorGoOrderPath = Join-Path $stageAbs ("MIM_TOD_GO_ORDER.validator.{0}.json" -f $validatorSuffix)
        $validatorReviewPath = Join-Path $stageAbs ("MIM_TOD_REVIEW_DECISION.validator.{0}.json" -f $validatorSuffix)
        $validatorResultPath = Join-Path $stageAbs ("TOD_MIM_TASK_RESULT.validator.{0}.json" -f $validatorSuffix)
        Write-JsonFile -PathValue $validatorRequestPath -Payload $request
        if ($null -ne $goOrder) {
            Write-JsonFile -PathValue $validatorGoOrderPath -Payload $goOrder
        }
        if ($null -ne $reviewDecision) {
            Write-JsonFile -PathValue $validatorReviewPath -Payload $reviewDecision
        }

        $validatorResult = Invoke-OptionalValidator -ValidatorAbs $validatorAbs -RequestId $requestId -RequestPath $validatorRequestPath -GoOrderPath $validatorGoOrderPath -ReviewDecisionPath $validatorReviewPath -IntegrationStatusPath $integrationStatusPath -ResultPath $validatorResultPath

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

                if (-not [string]::IsNullOrWhiteSpace([string]$coordinationEscalationState.pending_request_id) -or
                    [int]$coordinationEscalationState.emit_count -gt 0 -or
                    (Test-Path -Path $localCoordinationRequestPath)) {
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
        $resultTrigger = if ($null -ne $livenessTrigger) { $livenessTrigger } else { $goOrder }
        $resultPacket.result_reason_code = Get-ResultReasonCode -Status ([string]$resultPacket.status) -Execution $execution -ReviewGate $reviewGate -ValidatorResult $validatorResult
        $null = Add-ContractPacketEnvelope -Packet $resultPacket -BindingMetadata $contractBinding -PacketType 'tod-mim-task-result-v1' -MessageKind 'result' -ObjectiveId ([string]$resultPacket.objective_id) -TaskId ([string]$resultPacket.task_id) -RequestId $requestId -CorrelationId ([string]$resultPacket.correlation_id)
        $null = Add-SequenceRuntimeFields -Packet $resultPacket -TriggerPacket $resultTrigger -ListenerState $listenerState -ListenerStatePath $listenerStatePath

        if ($regressionSnapshot.available) {
            $resultPacket | Add-Member -NotePropertyName regression_snapshot -NotePropertyValue $regressionSnapshot -Force
        }

        if ($stalledByNoDelta) {
            $stallMsg = ("stalled_regression_no_delta: regression snapshot unchanged for {0} consecutive cycles while failures remain ({1}/{2} failed)." -f [int]$regressionStallState.unchanged_cycles, [int]$regressionSnapshot.failed, [int]$regressionSnapshot.total)
            $resultPacket.status = "failed"
            $resultPacket.error = $stallMsg
            $resultPacket | Add-Member -NotePropertyName stall_guard -NotePropertyValue ([pscustomobject]@{
                issue_code = "stalled_regression_no_delta"
                unchanged_cycles = [int]$regressionStallState.unchanged_cycles
                threshold = [int]$RegressionNoDeltaThreshold
                remediation_hint = "Switch from get-state-bus loop to a remediation task that runs or fixes failing regression tests."
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

        if (-not [string]::IsNullOrWhiteSpace($syncError)) {
            $resultPacket | Add-Member -NotePropertyName sync_warning -NotePropertyValue $syncError -Force
        }
        $resultValidation = Test-ContractRuntimePacket -PythonCommand $pythonCommand -ValidatorScript $runtimeContractValidatorAbs -BindingMetadata $contractBinding -PacketKind 'result' -Packet $resultPacket
        if (-not [bool]$resultValidation.passed) {
            $violation = Publish-RuntimeContractViolation -ViolationPath $localRuntimeViolationPath -StatePath $localRuntimeBindingStatePath -BindingMetadata $contractBinding -PacketKind 'result' -Packet $resultPacket -ValidationResult $resultValidation
            Register-RuntimeValidationResult -StatePath $localRuntimeBindingStatePath -BindingMetadata $contractBinding -PacketKind 'result' -Packet $resultPacket -ValidationResult $resultValidation -State 'violation' | Out-Null
            Publish-CommandStatus -ListenerState $listenerState -ListenerStatePath $listenerStatePath -LocalPath $localCommandStatusPath -RemotePath $remoteCommandStatusPath -Connections $connections -Status 'contract_violation_rejected' -Detail ('Rejected RESULT because runtime contract validation failed: {0}' -f (($violation.violations | ForEach-Object { [string]$_.code + ':' + [string]$_.detail }) -join '; ')) -RequestId $requestId -TaskId $requestTaskId -CorrelationId $requestCorrelationId -RequestSignature $requestSignature -GoOrderSignature $goOrderSignature -Action ([string]$resultPacket.action) -ExecutionReadiness $resultPacket.execution_readiness -AckPacket $ack -TriggerPacket $resultTrigger -BridgeRuntime $bridgeRuntime
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
        $null = Sync-LocalExecutionOutcome -TaskId $requestTaskId -ObjectiveId $requestObjectiveId -ResultPacket $resultPacket
        Write-JsonFile -PathValue $localResultPath -Payload $resultPacket

        $resultJson = Get-Content -Path $localResultPath -Raw
        Write-RemoteFileFromText -Connections $connections -RemotePath $remoteResultPath -Content $resultJson
        Publish-CommandStatus -ListenerState $listenerState -ListenerStatePath $listenerStatePath -LocalPath $localCommandStatusPath -RemotePath $remoteCommandStatusPath -Connections $connections -Status ([string]$resultPacket.status) -Detail "Task RESULT emitted to shared path." -RequestId $requestId -TaskId $requestTaskId -CorrelationId $requestCorrelationId -RequestSignature $requestSignature -GoOrderSignature $goOrderSignature -Action ([string]$resultPacket.action) -ExecutionReadiness $resultPacket.execution_readiness -AckPacket $ack -ResultPacket $resultPacket -TriggerPacket $resultTrigger -BridgeRuntime $bridgeRuntime

        Remove-Item -Path $validatorRequestPath -ErrorAction SilentlyContinue
        Remove-Item -Path $validatorGoOrderPath -ErrorAction SilentlyContinue
        Remove-Item -Path $validatorReviewPath -ErrorAction SilentlyContinue

        Publish-TriggerAck -ListenerState $listenerState -ListenerStatePath $listenerStatePath -Connections $connections -LocalPath $localTriggerAckPath -RemotePath $remoteTriggerAckPath -RequestId $requestId -CurrentTaskId $currentTaskId -CurrentCorrelationId $currentCorrelationId -TriggerPacket $livenessTrigger -BridgeRuntime $bridgeRuntime

        Update-ListenerHeartbeat -State $listenerState -StatePath $listenerStatePath -CycleStartedAt $cycleStartedAt -RequestId $requestId -RequestSignature $requestSignature -MarkProcessed
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
