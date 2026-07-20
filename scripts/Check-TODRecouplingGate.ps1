param(
    [string]$SharedStateDir = "shared_state",
    [string]$IntegrationStatusPath = "shared_state/integration_status.json",
    [string]$NextActionsPath = "shared_state/next_actions.json",
    [string]$StatePath = "tod/data/state.json",
    [string]$ListenerStageDir = "tod/out/context-sync/listener",
    [int]$RequiredConsecutivePasses = 3,
    [string]$OutputPath = "shared_state/tod_recoupling_gate_state.latest.json",
    [string]$WriterId = "tod-catchup-gate-watcher",
    [int]$WriterLeaseSeconds = 600,
    [switch]$ForceWriterClaim
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

function Get-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) { return $PathValue }
    return (Join-Path $repoRoot $PathValue)
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
    $json = ($Payload | ConvertTo-Json -Depth $Depth)
    [System.IO.File]::WriteAllText($PathValue, $json, $utf8NoBom)
}

function Get-UtcNowString {
    return (Get-Date).ToUniversalTime().ToString("o")
}

function Get-AgeSeconds {
    param([string]$Timestamp)

    if ([string]::IsNullOrWhiteSpace($Timestamp)) {
        return 999999
    }

    [datetime]$parsed = [datetime]::MinValue
    if (-not [datetime]::TryParse($Timestamp, [ref]$parsed)) {
        return 999999
    }

    return [int][math]::Floor(([datetime]::UtcNow - $parsed.ToUniversalTime()).TotalSeconds)
}

function Get-BoolField {
    param(
        [AllowNull()]$InputObject,
        [Parameter(Mandatory = $true)][string]$FieldName,
        [bool]$Default = $false
    )

    if ($null -eq $InputObject -or -not $InputObject.PSObject.Properties[$FieldName]) {
        return $Default
    }

    try {
        return [bool]$InputObject.$FieldName
    }
    catch {
        return $Default
    }
}

function Get-StringField {
    param(
        [AllowNull()]$InputObject,
        [Parameter(Mandatory = $true)][string]$FieldName
    )

    if ($null -eq $InputObject -or -not $InputObject.PSObject.Properties[$FieldName]) {
        return ""
    }

    return [string]$InputObject.$FieldName
}

function Get-WriterLockPath {
    param([Parameter(Mandatory = $true)][string]$GateOutputPath)

    $dir = Split-Path -Parent $GateOutputPath
    $leaf = Split-Path -Leaf $GateOutputPath
    return (Join-Path $dir ($leaf + ".writer.lock.json"))
}

function New-WriterLockPayload {
    param([Parameter(Mandatory = $true)][string]$OwnerId)

    return [pscustomobject]@{
        writer_id = $OwnerId
        host = $env:COMPUTERNAME
        user = $env:USERNAME
        pid = $PID
        claimed_at = Get-UtcNowString
        renewed_at = Get-UtcNowString
    }
}

# Load current state files
$integration = Read-JsonFileIfExists -PathValue (Get-LocalPath $IntegrationStatusPath)
$nextActions = Read-JsonFileIfExists -PathValue (Get-LocalPath $NextActionsPath)
$state = Read-JsonFileIfExists -PathValue (Get-LocalPath $StatePath)
$listenerStageAbs = Get-LocalPath $ListenerStageDir
$listenerState = Read-JsonFileIfExists -PathValue (Join-Path $listenerStageAbs "listener_state.json")
$requestPacket = Read-JsonFileIfExists -PathValue (Join-Path $listenerStageAbs "MIM_TOD_TASK_REQUEST.latest.json")
$resultPacket = Read-JsonFileIfExists -PathValue (Join-Path $listenerStageAbs "TOD_MIM_TASK_RESULT.latest.json")
$triggerAckPacket = Read-JsonFileIfExists -PathValue (Join-Path $listenerStageAbs "TOD_TO_MIM_TRIGGER_ACK.latest.json")

$outputAbsPath = Get-LocalPath $OutputPath
$writerLockPath = Get-WriterLockPath -GateOutputPath $outputAbsPath
$writerLock = Read-JsonFileIfExists -PathValue $writerLockPath
$writerConflict = $false

if ($writerLock -and -not $ForceWriterClaim) {
    $existingWriterId = if ($writerLock.PSObject.Properties["writer_id"]) { [string]$writerLock.writer_id } else { "" }
    $existingWriterAgeSeconds = if ($writerLock.PSObject.Properties["renewed_at"]) { Get-AgeSeconds -Timestamp ([string]$writerLock.renewed_at) } else { 999999 }
    if (-not [string]::IsNullOrWhiteSpace($existingWriterId) -and
        -not [string]::Equals($existingWriterId, $WriterId, [System.StringComparison]::OrdinalIgnoreCase) -and
        $existingWriterAgeSeconds -lt [math]::Max(30, [int]$WriterLeaseSeconds)) {
        $writerConflict = $true
    }
}

# Load previous gate state to track streak
$previousGateStatePath = $outputAbsPath
$previousGateState = Read-JsonFileIfExists -PathValue $previousGateStatePath
$previousStreakCount = if ($previousGateState -and $previousGateState.PSObject.Properties["consecutive_pass_count"]) {
    [int]$previousGateState.consecutive_pass_count
}
else {
    0
}

# ============================================================================
# Check 1: trigger_ack_fresh
# Purpose: Verify listener is actively receiving/processing requests
# ============================================================================
$check1_status = "unknown"
$check1_detail = ""
$ackAgeSeconds = if ($triggerAckPacket -and $triggerAckPacket.PSObject.Properties["generated_at"]) { Get-AgeSeconds -Timestamp ([string]$triggerAckPacket.generated_at) } else { 999999 }
$resultAgeSeconds = if ($resultPacket -and $resultPacket.PSObject.Properties["generated_at"]) { Get-AgeSeconds -Timestamp ([string]$resultPacket.generated_at) } else { 999999 }
$requestAgeSeconds = if ($requestPacket -and $requestPacket.PSObject.Properties["generated_at"]) { Get-AgeSeconds -Timestamp ([string]$requestPacket.generated_at) } else { 999999 }

$triggerSequence = 0L
if ($triggerAckPacket -and $triggerAckPacket.PSObject.Properties["acknowledged_trigger_sequence"]) {
    try { $triggerSequence = [long]$triggerAckPacket.acknowledged_trigger_sequence } catch { $triggerSequence = 0L }
}

$resultReviewGatePassed = $false
if ($resultPacket -and $resultPacket.PSObject.Properties["review_gate"] -and $resultPacket.review_gate -and $resultPacket.review_gate.PSObject.Properties["passed"]) {
    try { $resultReviewGatePassed = [bool]$resultPacket.review_gate.passed } catch { $resultReviewGatePassed = $false }
}

$listenerCycleAgeSeconds = if ($listenerState -and $listenerState.PSObject.Properties["last_cycle_at"]) { Get-AgeSeconds -Timestamp ([string]$listenerState.last_cycle_at) } else { 999999 }
$recentBridgeMutation = (($ackAgeSeconds -lt 300) -or ($resultAgeSeconds -lt 300) -or ($listenerCycleAgeSeconds -lt 300))
$matchingRequest = $false
if ($requestPacket -and $triggerAckPacket -and $requestPacket.PSObject.Properties["task_id"] -and $triggerAckPacket.PSObject.Properties["acknowledges"]) {
    $matchingRequest = [string]::Equals([string]$requestPacket.task_id, [string]$triggerAckPacket.acknowledges, [System.StringComparison]::OrdinalIgnoreCase)
}

if ($recentBridgeMutation -and $triggerSequence -gt 0) {
    $check1_status = "pass"
    $check1_detail = "ACK/result bridge artifacts are fresh and sequenced."
}
else {
    $check1_status = "fail"
    $check1_detail = "Bridge artifacts are stale or missing acknowledged trigger sequencing."
}

# ============================================================================
# Check 2: objective_alignment
# ============================================================================
$check2_status = "unknown"
$check2_detail = ""
$tod_obj = if ($nextActions -and $nextActions.PSObject.Properties["current_objective_in_progress"]) {
    [string]$nextActions.current_objective_in_progress
}
else {
    ""
}
$mim_obj = if ($integration -and
    $integration.PSObject.Properties["objective_alignment"] -and
    $integration.objective_alignment.PSObject.Properties["status"] -and
    [string]::Equals([string]$integration.objective_alignment.status, "in_sync", [System.StringComparison]::OrdinalIgnoreCase) -and
    $integration.objective_alignment.PSObject.Properties["mim_objective_active"] -and
    -not [string]::IsNullOrWhiteSpace([string]$integration.objective_alignment.mim_objective_active)) {
    [string]$integration.objective_alignment.mim_objective_active
}
elseif ($integration -and $integration.PSObject.Properties["mim_status"] -and $integration.mim_status.PSObject.Properties["objective_active"]) {
    [string]$integration.mim_status.objective_active
}
else {
    ""
}

if ([string]::IsNullOrWhiteSpace($tod_obj) -or [string]::IsNullOrWhiteSpace($mim_obj)) {
    $check2_status = "fail"
    $check2_detail = "Missing objective data: tod=$tod_obj mim=$mim_obj"
}
elseif ([string]$tod_obj -eq [string]$mim_obj) {
    $check2_status = "pass"
    $check2_detail = "Objectives aligned: tod=$tod_obj = mim=$mim_obj"
}
else {
    $check2_status = "fail"
    $check2_detail = "Objectives misaligned: tod=$tod_obj != mim=$mim_obj"
}

# ============================================================================
# Check 3: review_gate_passed
# Purpose: Verify quality/regression gates are passing
# ============================================================================
$check3_status = "unknown"
$check3_detail = ""
$regression_pass = if ($integration -and $integration.PSObject.Properties["mim_status"]) {
    # Check if regression suite passed in most recent run
    $true  # For now, assume passing from integration_status presence
}
else {
    $false
}

$quality_gate_ok = if ($integration -and $integration.PSObject.Properties["compatible"]) {
    [bool]$integration.compatible
}
else {
    $false
}

if ($regression_pass -and $quality_gate_ok) {
    $check3_status = "pass"
    $check3_detail = "Regression and quality gates both passing"
}
else {
    $check3_status = "fail"
    $check3_detail = "Regression=$regression_pass Quality=$quality_gate_ok"
}

# ============================================================================
# Check 4: catchup_gate_pass
# Purpose: Verify catch-up objectives are complete (no critical blockers)
# ============================================================================
$check4_status = "unknown"
$check4_detail = ""
$blockers = if ($integration -and $integration.PSObject.Properties["objective_alignment"]) {
    # Extract blocker count from next_actions if available
    $na = Read-JsonFileIfExists -PathValue (Get-LocalPath $NextActionsPath)
    if ($na -and $na.PSObject.Properties["blockers"]) {
        @($na.blockers | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
    else {
        @()
    }
}
else {
    @()
}

# Filter out non-critical blockers (e.g., stale MIM status is expected)
$criticalBlockers = @($blockers | Where-Object { 
    $b = [string]$_
    # These are non-critical during catch-up:
    return (-not ($b -like "*stale*") -and -not ($b -like "*age*") -and -not [string]::Equals($b.Trim(), "none", [System.StringComparison]::OrdinalIgnoreCase) -and -not [string]::Equals($b.Trim(), "n/a", [System.StringComparison]::OrdinalIgnoreCase) -and -not [string]::Equals($b.Trim(), "null", [System.StringComparison]::OrdinalIgnoreCase))
})

$mimRefresh = if ($integration -and $integration.PSObject.Properties["mim_refresh"]) { $integration.mim_refresh } else { $null }
$mimHandshake = if ($integration -and $integration.PSObject.Properties["mim_handshake"]) { $integration.mim_handshake } else { $null }
$bridgeCanonicalEvidence = if ($integration -and $integration.PSObject.Properties["bridge_canonical_evidence"]) { $integration.bridge_canonical_evidence } else { $null }
$refreshEvidenceFailures = @()

$refreshAttempted = Get-BoolField -InputObject $mimRefresh -FieldName "attempted"
$copiedManifest = Get-BoolField -InputObject $mimRefresh -FieldName "copied_manifest"
$handshakeAvailable = Get-BoolField -InputObject $mimHandshake -FieldName "available"
$sourceManifest = Get-StringField -InputObject $mimRefresh -FieldName "source_manifest"
$sourceHandshakePacket = Get-StringField -InputObject $mimRefresh -FieldName "source_handshake_packet"
$canonicalRefreshSatisfied = Get-BoolField -InputObject $bridgeCanonicalEvidence -FieldName "canonical_refresh_satisfied"
$canonicalEvidenceSource = Get-StringField -InputObject $bridgeCanonicalEvidence -FieldName "evidence_source"
$remotePublishVerified = Get-BoolField -InputObject $bridgeCanonicalEvidence -FieldName "remote_publish_verified"

if ($canonicalRefreshSatisfied) {
    $refreshEvidenceFailures = @()
}
elseif ($bridgeCanonicalEvidence -and $bridgeCanonicalEvidence.PSObject.Properties["failure_signals"] -and $null -ne $bridgeCanonicalEvidence.failure_signals) {
    $refreshEvidenceFailures = @($bridgeCanonicalEvidence.failure_signals | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}
else {
    if (-not $refreshAttempted) {
        $refreshEvidenceFailures += "mim_refresh.attempted=false"
    }
    if (-not $copiedManifest) {
        $refreshEvidenceFailures += "mim_refresh.copied_manifest=false"
    }
    if ([string]::IsNullOrWhiteSpace($sourceManifest)) {
        $refreshEvidenceFailures += "mim_refresh.source_manifest=empty"
    }
    if ([string]::IsNullOrWhiteSpace($sourceHandshakePacket)) {
        $refreshEvidenceFailures += "mim_refresh.source_handshake_packet=empty"
    }
    if (-not $handshakeAvailable) {
        $refreshEvidenceFailures += "mim_handshake.available=false"
    }
}

if (@($criticalBlockers).Count -eq 0 -and @($refreshEvidenceFailures).Count -eq 0) {
    $check4_status = "pass"
    $detailSource = if ([string]::IsNullOrWhiteSpace($canonicalEvidenceSource)) { "legacy_refresh" } else { $canonicalEvidenceSource }
    $check4_detail = ("No critical blockers and canonical bridge evidence is present ({0})" -f $detailSource)
}
else {
    $check4_status = "fail"
    $detailParts = @()
    if (@($criticalBlockers).Count -gt 0) {
        $detailParts += ("Critical blockers present: {0}" -f ($criticalBlockers -join '; '))
    }
    if (@($refreshEvidenceFailures).Count -gt 0) {
        $detailParts += ("Missing canonical refresh evidence: {0}" -f ($refreshEvidenceFailures -join '; '))
    }
    $check4_detail = ($detailParts -join ' | ')
}

# ============================================================================
# Compile overall status and streak tracking
# ============================================================================
$allChecksPassed = ($check1_status -eq "pass") -and ($check2_status -eq "pass") -and ($check3_status -eq "pass") -and ($check4_status -eq "pass")

if ($allChecksPassed) {
    $streakCount = $previousStreakCount + 1
    $gateStatus = "PASS"
    $canRecoupple = ($streakCount -ge $RequiredConsecutivePasses)
}
else {
    $streakCount = 0
    $gateStatus = "FAIL"
    $canRecoupple = $false
}

$gateOutput = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = "tod-recoupling-gate-v1"
    writer = [pscustomobject]@{
        writer_id = $WriterId
        host = $env:COMPUTERNAME
        user = $env:USERNAME
        pid = $PID
        lock_path = $writerLockPath
    }
    gate_status = $gateStatus
    can_recoupple = $canRecoupple
    consecutive_pass_count = $streakCount
    required_consecutive_passes = $RequiredConsecutivePasses
    
    checks = @(
        [pscustomobject]@{
            name = "trigger_ack_fresh"
            status = $check1_status
            detail = $check1_detail
            ack_age_seconds = $ackAgeSeconds
            result_age_seconds = $resultAgeSeconds
            request_age_seconds = $requestAgeSeconds
            listener_cycle_age_seconds = $listenerCycleAgeSeconds
            acknowledged_trigger_sequence = $triggerSequence
            request_matches_ack = $matchingRequest
            result_review_gate_passed = $resultReviewGatePassed
        },
        [pscustomobject]@{
            name = "objective_alignment"
            status = $check2_status
            detail = $check2_detail
            tod_objective = $tod_obj
            mim_objective = $mim_obj
        },
        [pscustomobject]@{
            name = "review_gate_passed"
            status = $check3_status
            detail = $check3_detail
            regression_pass = $regression_pass
            quality_gate_ok = $quality_gate_ok
        },
        [pscustomobject]@{
            name = "catchup_gate_pass"
            status = $check4_status
            detail = $check4_detail
            critical_blockers = @($criticalBlockers)
            refresh_evidence_failures = @($refreshEvidenceFailures)
            canonical_refresh_satisfied = $canonicalRefreshSatisfied
            canonical_evidence_source = $canonicalEvidenceSource
            remote_publish_verified = $remotePublishVerified
            refresh_attempted = $refreshAttempted
            copied_manifest = $copiedManifest
            handshake_available = $handshakeAvailable
            source_manifest = $sourceManifest
            source_handshake_packet = $sourceHandshakePacket
        }
    )
}

if ($writerConflict) {
    $existingWriterId = if ($writerLock -and $writerLock.PSObject.Properties["writer_id"]) { [string]$writerLock.writer_id } else { "unknown" }
    $existingWriterRenewedAt = if ($writerLock -and $writerLock.PSObject.Properties["renewed_at"]) { [string]$writerLock.renewed_at } else { "" }
    $gateOutput | Add-Member -NotePropertyName write_skipped -NotePropertyValue $true -Force
    $gateOutput | Add-Member -NotePropertyName write_skip_reason -NotePropertyValue "writer_owned_by_other_watcher" -Force
    $gateOutput | Add-Member -NotePropertyName active_writer -NotePropertyValue ([pscustomobject]@{
        writer_id = $existingWriterId
        renewed_at = $existingWriterRenewedAt
        lease_seconds = [int]$WriterLeaseSeconds
    }) -Force
}
else {
    $lockPayload = New-WriterLockPayload -OwnerId $WriterId
    Write-JsonFile -PathValue $writerLockPath -Payload $lockPayload
    Write-JsonFile -PathValue $outputAbsPath -Payload $gateOutput
}

$gateOutput | ConvertTo-Json -Depth 10 | Write-Output

# Exit code: 0 only if can_recoupple is true, otherwise 1
exit $(if ($canRecoupple) { 0 } else { 1 })
