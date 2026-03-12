param(
    [string]$SharedStateDir = "shared_state",
    [string]$TodScriptPath = "scripts/TOD.ps1",
    [string]$TodConfigPath = "tod/config/tod-config.json",
    [string]$StatePath = "tod/data/state.json",
    [string]$TestSummaryPath = "tod/out/training/test-summary.json",
    [string]$SmokeSummaryPath = "tod/out/training/smoke-summary.json",
    [string]$QualityGatePath = "tod/out/training/quality-gate-summary.json",
    [string]$ApprovalReductionPath = "shared_state/approval_reduction_summary.json",
    [string]$ManifestPath = "tod/data/sample-manifest.json",
    [string]$MimContextExportPath = "tod/out/context-sync/MIM_CONTEXT_EXPORT.latest.json",
    [string]$MimManifestPath = "tod/out/context-sync/MIM_MANIFEST.latest.json",
    [string]$ContextSyncInboxPath = "tod/inbox/context-sync/updates",
    [double]$MimStatusStaleAfterHours = 6,
    [string]$ReleaseTagOverride,
    [string]$NextProposedObjective = "TOD-17"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

function Get-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) { return $PathValue }
    return (Join-Path $repoRoot $PathValue)
}

function New-DirectoryIfMissing {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if (-not (Test-Path -Path $PathValue)) {
        New-Item -ItemType Directory -Path $PathValue -Force | Out-Null
    }
}

function Get-JsonFileContent {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    $resolved = Get-LocalPath -PathValue $PathValue
    if (-not (Test-Path -Path $resolved)) { throw "File not found: $resolved" }
    return (Get-Content -Path $resolved -Raw | ConvertFrom-Json)
}

function Get-JsonFileIfExists {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    $resolved = Get-LocalPath -PathValue $PathValue
    if (-not (Test-Path -Path $resolved)) { return $null }
    try {
        return (Get-Content -Path $resolved -Raw | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Get-TodPayload {
    param(
        [Parameter(Mandatory = $true)][string]$TodScript,
        [Parameter(Mandatory = $true)][string]$TodConfig,
        [Parameter(Mandatory = $true)][string]$ActionName
    )

    try {
        $raw = & $TodScript -Action $ActionName -ConfigPath $TodConfig -Top 10
        return ($raw | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Get-GitValue {
    param([Parameter(Mandatory = $true)][string]$CommandText)

    try {
        $value = Invoke-Expression $CommandText
        if ($null -eq $value) { return "" }
        return ([string]$value).Trim()
    }
    catch {
        return ""
    }
}

function Get-IdNumber {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return -1 }
    $digits = [regex]::Match($Value, "\d+")
    if (-not $digits.Success) { return -1 }
    return [int]$digits.Value
}

function Convert-ToStringList {
    param($Value)

    if ($null -eq $Value) { return @() }

    $items = @()
    if ($Value -is [System.Array]) {
        $items = @($Value)
    }
    elseif ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        $items = @($Value)
    }
    else {
        $items = @($Value)
    }

    $normalized = @()
    foreach ($item in $items) {
        $text = [string]$item
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            $normalized += $text
        }
    }

    return @($normalized)
}

function Convert-ToUtcDateOrNull {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    try {
        return ([datetime]$Value).ToUniversalTime()
    }
    catch {
        return $null
    }
}

function Resolve-ReliabilityAlertState {
    param(
        [string]$RawState,
        [string]$Trend,
        [int]$PendingApprovals,
        [bool]$RegressionPassed,
        [bool]$QualityGatePassed
    )

    $normalized = if ([string]::IsNullOrWhiteSpace($RawState)) { "" } else { $RawState.Trim().ToLowerInvariant() }
    if ($normalized -in @("stable", "warning", "degraded", "critical")) {
        return $normalized
    }

    $trendNorm = if ([string]::IsNullOrWhiteSpace($Trend)) { "unknown" } else { $Trend.Trim().ToLowerInvariant() }
    if (-not $RegressionPassed -and -not $QualityGatePassed) {
        return "critical"
    }
    if (-not $RegressionPassed -or $PendingApprovals -ge 100) {
        return "degraded"
    }
    if ($trendNorm -in @("declining", "watch", "warning") -or $PendingApprovals -gt 0) {
        return "warning"
    }

    return "stable"
}

function Get-ApprovalBacklogSnapshot {
    param(
        [Parameter(Mandatory = $true)]$State,
        [int]$StaleHours = 72
    )

    $records = @()
    if ($State.PSObject.Properties["engineering_loop"] -and $State.engineering_loop -and $State.engineering_loop.PSObject.Properties["cycle_records"]) {
        $records = @($State.engineering_loop.cycle_records)
    }

    $pending = @($records | Where-Object {
            ($_.PSObject.Properties["approval_pending"] -and [bool]$_.approval_pending) -or
            ($_.PSObject.Properties["approval_status"] -and ([string]$_.approval_status).ToLowerInvariant() -eq "pending_apply")
        })

    $now = (Get-Date).ToUniversalTime()
    $ageBuckets = [ordered]@{
        "lt_24h" = 0
        "h24_to_h72" = 0
        "gt_72h" = 0
        "unknown" = 0
    }

    $statusCounts = [ordered]@{}
    $sourceCounts = [ordered]@{}
    $promotable = @()
    $stale = @()
    $lowValue = @()

    foreach ($item in $pending) {
        $statusValue = if ($item.PSObject.Properties["approval_status"]) { [string]$item.approval_status } else { "pending_apply" }
        if ([string]::IsNullOrWhiteSpace($statusValue)) { $statusValue = "pending_apply" }
        $statusKey = $statusValue.Trim().ToLowerInvariant()
        if (-not $statusCounts.Contains($statusKey)) {
            $statusCounts[$statusKey] = 0
        }
        $statusCounts[$statusKey] = [int]$statusCounts[$statusKey] + 1

        $sourceKey = "engineering_loop"
        if ($item.PSObject.Properties["task_category"] -and -not [string]::IsNullOrWhiteSpace([string]$item.task_category)) {
            $sourceKey = "task_category:{0}" -f ([string]$item.task_category)
        }
        elseif ($item.PSObject.Properties["objective_id"] -and -not [string]::IsNullOrWhiteSpace([string]$item.objective_id)) {
            $sourceKey = "objective:{0}" -f ([string]$item.objective_id)
        }
        if (-not $sourceCounts.Contains($sourceKey)) {
            $sourceCounts[$sourceKey] = 0
        }
        $sourceCounts[$sourceKey] = [int]$sourceCounts[$sourceKey] + 1

        $createdAtRaw = if ($item.PSObject.Properties["created_at"]) { [string]$item.created_at } else { "" }
        $updatedAtRaw = if ($item.PSObject.Properties["updated_at"]) { [string]$item.updated_at } else { "" }
        $createdAtUtc = Convert-ToUtcDateOrNull -Value $createdAtRaw
        $updatedAtUtc = Convert-ToUtcDateOrNull -Value $updatedAtRaw
        $anchor = if ($null -ne $createdAtUtc) { $createdAtUtc } else { $updatedAtUtc }

        $ageHours = $null
        if ($null -eq $anchor) {
            $ageBuckets["unknown"] = [int]$ageBuckets["unknown"] + 1
        }
        else {
            $ageHours = [math]::Round(($now - $anchor).TotalHours, 2)
            if ($ageHours -lt 24) {
                $ageBuckets["lt_24h"] = [int]$ageBuckets["lt_24h"] + 1
            }
            elseif ($ageHours -le 72) {
                $ageBuckets["h24_to_h72"] = [int]$ageBuckets["h24_to_h72"] + 1
            }
            else {
                $ageBuckets["gt_72h"] = [int]$ageBuckets["gt_72h"] + 1
            }
        }

        $score = $null
        if ($item.PSObject.Properties["score_snapshot"] -and $item.score_snapshot -and $item.score_snapshot.PSObject.Properties["overall"] -and $item.score_snapshot.overall.PSObject.Properties["score"]) {
            $score = [double]$item.score_snapshot.overall.score
        }

        $maturityBand = if ($item.PSObject.Properties["maturity_band"]) { ([string]$item.maturity_band).ToLowerInvariant() } else { "" }
        $recordId = if ($item.PSObject.Properties["cycle_id"]) { [string]$item.cycle_id } elseif ($item.PSObject.Properties["run_id"]) { [string]$item.run_id } else { "unknown" }

        $summaryRow = [pscustomobject]@{
            id = $recordId
            objective_id = if ($item.PSObject.Properties["objective_id"]) { [string]$item.objective_id } else { "" }
            task_id = if ($item.PSObject.Properties["task_id"]) { [string]$item.task_id } else { "" }
            status = $statusKey
            source = $sourceKey
            age_hours = $ageHours
            maturity_band = $maturityBand
            score = if ($null -ne $score) { [math]::Round($score, 4) } else { $null }
        }

        if ($null -ne $ageHours -and $ageHours -ge $StaleHours) {
            $stale += $summaryRow
        }

        if ($maturityBand -in @("good", "strong") -and $null -ne $score -and $score -ge 0.65) {
            $promotable += $summaryRow
        }

        if ($maturityBand -in @("emerging", "early") -or ($null -ne $score -and $score -lt 0.45)) {
            $lowValue += $summaryRow
        }
    }

    return [pscustomobject]@{
        generated_at = $now.ToString("o")
        total_pending = @($pending).Count
        by_type = [pscustomobject]$statusCounts
        by_age = [pscustomobject]$ageBuckets
        by_source = [pscustomobject]$sourceCounts
        stale_count = @($stale).Count
        low_value_count = @($lowValue).Count
        promotable_count = @($promotable).Count
        stale = @($stale | Select-Object -First 10)
        low_value = @($lowValue | Select-Object -First 10)
        promotable = @($promotable | Select-Object -First 10)
    }
}

function Get-ObjectiveByStatusOrder {
    param(
        [Parameter(Mandatory = $true)]$Objectives,
        [Parameter(Mandatory = $true)][string[]]$Statuses
    )

    $statusSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($statusItem in @($Statuses)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$statusItem)) {
            [void]$statusSet.Add(([string]$statusItem).ToLowerInvariant())
        }
    }

    $objectiveHits = @()
    foreach ($objectiveItem in @($Objectives)) {
        $statusText = ""
        if ($objectiveItem.PSObject.Properties["status"]) {
            $statusText = ([string]$objectiveItem.status).ToLowerInvariant()
        }
        if ($statusSet.Contains($statusText)) {
            $objectiveHits += $objectiveItem
        }
    }

    if (@($objectiveHits).Count -eq 0) { return $null }

    $ordered = @($objectiveHits | Sort-Object @{ Expression = { Get-IdNumber -Value ([string]$_.id) }; Descending = $true })
    return $ordered[0]
}

function Get-MimSchemaVersionFromContextExport {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue
    )

    $doc = Get-JsonFileIfExists -PathValue $PathValue
    if ($null -eq $doc) { return "" }

    if ($doc.PSObject.Properties["schema_version"] -and -not [string]::IsNullOrWhiteSpace([string]$doc.schema_version)) {
        return [string]$doc.schema_version
    }

    if ($doc.PSObject.Properties["status"] -and $doc.status -and $doc.status.PSObject.Properties["schema_version"] -and -not [string]::IsNullOrWhiteSpace([string]$doc.status.schema_version)) {
        return [string]$doc.status.schema_version
    }

    if ($doc.PSObject.Properties["contract_version"] -and -not [string]::IsNullOrWhiteSpace([string]$doc.contract_version)) {
        return [string]$doc.contract_version
    }

    return ""
}

function Get-MimStatusSnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [double]$StaleAfterHours = 6
    )

    $doc = Get-JsonFileIfExists -PathValue $PathValue
    if ($null -eq $doc) {
        return [pscustomobject]@{
            available = $false
            source_path = $PathValue
            generated_at = ""
            age_hours = $null
            stale_after_hours = $StaleAfterHours
            is_stale = $true
            objective_active = ""
            phase = ""
            blockers = ""
        }
    }

    $generatedAt = ""
    if ($doc.PSObject.Properties["generated_at"]) {
        $generatedAt = [string]$doc.generated_at
    }

    $objectiveActive = ""
    $phase = ""
    $blockers = ""
    if ($doc.PSObject.Properties["status"] -and $doc.status) {
        if ($doc.status.PSObject.Properties["objective_active"]) { $objectiveActive = [string]$doc.status.objective_active }
        if ($doc.status.PSObject.Properties["phase"]) { $phase = [string]$doc.status.phase }
        if ($doc.status.PSObject.Properties["blockers"]) { $blockers = [string]$doc.status.blockers }
    }

    $ageHours = $null
    $isStale = $true
    $generatedUtc = Convert-ToUtcDateOrNull -Value $generatedAt
    if ($null -ne $generatedUtc) {
        $ageHours = [math]::Round(((Get-Date).ToUniversalTime() - $generatedUtc).TotalHours, 2)
        $isStale = ($ageHours -gt $StaleAfterHours)
    }

    return [pscustomobject]@{
        available = $true
        source_path = $PathValue
        generated_at = $generatedAt
        age_hours = $ageHours
        stale_after_hours = $StaleAfterHours
        is_stale = [bool]$isStale
        objective_active = $objectiveActive
        phase = $phase
        blockers = $blockers
    }
}

function Get-ObjectiveAlignment {
    param(
        [Parameter(Mandatory = $true)][string]$TodObjective,
        $MimStatus
    )

    $todNumber = Get-IdNumber -Value $TodObjective
    $mimObjectiveRaw = ""
    if ($null -ne $MimStatus -and $MimStatus.PSObject.Properties["objective_active"]) {
        $mimObjectiveRaw = [string]$MimStatus.objective_active
    }
    $mimNumber = Get-IdNumber -Value $mimObjectiveRaw

    $alignmentStatus = "unknown"
    $aligned = $false
    $delta = $null
    if ($todNumber -ge 0 -and $mimNumber -ge 0) {
        $aligned = ($todNumber -eq $mimNumber)
        $delta = ($todNumber - $mimNumber)
        $alignmentStatus = if ($aligned) { "in_sync" } else { "mismatch" }
    }

    return [pscustomobject]@{
        status = $alignmentStatus
        aligned = [bool]$aligned
        tod_current_objective = $TodObjective
        mim_objective_active = $mimObjectiveRaw
        delta = $delta
    }
}

$sharedDirAbs = Get-LocalPath -PathValue $SharedStateDir
New-DirectoryIfMissing -PathValue $sharedDirAbs

$currentBuildStatePath = Join-Path $sharedDirAbs "current_build_state.json"
$objectivesPath = Join-Path $sharedDirAbs "objectives.json"
$contractsPath = Join-Path $sharedDirAbs "contracts.json"
$nextActionsPath = Join-Path $sharedDirAbs "next_actions.json"
$devJournalPath = Join-Path $sharedDirAbs "dev_journal.jsonl"
$latestSummaryPath = Join-Path $sharedDirAbs "latest_summary.md"
$chatgptUpdatePath = Join-Path $sharedDirAbs "chatgpt_update.md"
$chatgptUpdateJsonPath = Join-Path $sharedDirAbs "chatgpt_update.json"
$sharedDevLogPlanPath = Join-Path $sharedDirAbs "shared_development_log_plan.json"
$integrationStatusPath = Join-Path $sharedDirAbs "integration_status.json"
$executionEvidencePath = Join-Path $sharedDirAbs "execution_evidence.json"
$objectiveRoadmapPath = Join-Path $sharedDirAbs "tod_objective_roadmap.json"

$todScriptAbs = Get-LocalPath -PathValue $TodScriptPath
$todConfigAbs = Get-LocalPath -PathValue $TodConfigPath
$stateAbs = Get-LocalPath -PathValue $StatePath

if (-not (Test-Path -Path $todScriptAbs)) { throw "TOD script not found: $todScriptAbs" }
if (-not (Test-Path -Path $todConfigAbs)) { throw "TOD config not found: $todConfigAbs" }
if (-not (Test-Path -Path $stateAbs)) { throw "TOD state not found: $stateAbs" }

$state = Get-JsonFileContent -PathValue $StatePath
$testSummary = Get-JsonFileIfExists -PathValue $TestSummaryPath
$smokeSummary = Get-JsonFileIfExists -PathValue $SmokeSummaryPath
$qualityGate = Get-JsonFileIfExists -PathValue $QualityGatePath
$approvalReduction = Get-JsonFileIfExists -PathValue $ApprovalReductionPath
$manifest = Get-JsonFileIfExists -PathValue $ManifestPath

$capabilities = Get-TodPayload -TodScript $todScriptAbs -TodConfig $todConfigAbs -ActionName "get-capabilities"
$engineeringSignal = Get-TodPayload -TodScript $todScriptAbs -TodConfig $todConfigAbs -ActionName "get-engineering-signal"
$reliabilityPayload = Get-TodPayload -TodScript $todScriptAbs -TodConfig $todConfigAbs -ActionName "get-reliability"
$reliabilityDashboard = Get-TodPayload -TodScript $todScriptAbs -TodConfig $todConfigAbs -ActionName "show-reliability-dashboard"

$branch = Get-GitValue -CommandText "git rev-parse --abbrev-ref HEAD"
$commitSha = Get-GitValue -CommandText "git rev-parse HEAD"
$releaseTag = if (-not [string]::IsNullOrWhiteSpace($ReleaseTagOverride)) { $ReleaseTagOverride } else { Get-GitValue -CommandText "git describe --tags --abbrev=0 2>$null" }

$objectives = if ($state.PSObject.Properties["objectives"]) { @($state.objectives) } else { @() }
$latestCompleted = Get-ObjectiveByStatusOrder -Objectives $objectives -Statuses @("completed", "closed", "done", "reviewed_pass")
$currentInProgress = Get-ObjectiveByStatusOrder -Objectives $objectives -Statuses @("in_progress", "open", "planned")

$latestCompletedObjective = if ($null -ne $latestCompleted) { [string]$latestCompleted.id } else { "none" }
$currentObjective = if ($null -ne $currentInProgress) { [string]$currentInProgress.id } else { "none" }

$schemaVersion = if ($manifest -and $manifest.PSObject.Properties["schema_version"]) { [string]$manifest.schema_version } else { "unknown" }
$currentProdTestStatus = [pscustomobject]@{
    tests = [pscustomobject]@{
        available = ($null -ne $testSummary)
        passed_all = if ($testSummary -and $testSummary.PSObject.Properties["passed_all"]) { [bool]$testSummary.passed_all } else { $false }
        passed = if ($testSummary -and $testSummary.PSObject.Properties["passed"]) { [int]$testSummary.passed } else { 0 }
        failed = if ($testSummary -and $testSummary.PSObject.Properties["failed"]) { [int]$testSummary.failed } else { 0 }
        total = if ($testSummary -and $testSummary.PSObject.Properties["total"]) { [int]$testSummary.total } else { 0 }
        generated_at = if ($testSummary -and $testSummary.PSObject.Properties["generated_at"]) { [string]$testSummary.generated_at } else { "" }
    }
    smoke = [pscustomobject]@{
        available = ($null -ne $smokeSummary)
        passed_all = if ($smokeSummary -and $smokeSummary.PSObject.Properties["passed_all"]) { [bool]$smokeSummary.passed_all } else { $false }
        generated_at = if ($smokeSummary -and $smokeSummary.PSObject.Properties["generated_at"]) { [string]$smokeSummary.generated_at } else { "" }
    }
}

$activeCapabilities = @()
if ($capabilities) {
    if ($capabilities.PSObject.Properties["execution"] -and $capabilities.execution.PSObject.Properties["engines"]) {
        foreach ($e in @($capabilities.execution.engines)) {
            $activeCapabilities += "engine:$([string]$e)"
        }
    }
    if ($capabilities.PSObject.Properties["endpoints"]) {
        foreach ($ep in @($capabilities.endpoints)) {
            $activeCapabilities += "endpoint:$([string]$ep)"
        }
    }
}
$activeCapabilities = @($activeCapabilities | Sort-Object -Unique)

$lastRegressionResult = [pscustomobject]@{
    passed_all = if ($testSummary -and $testSummary.PSObject.Properties["passed_all"]) { [bool]$testSummary.passed_all } else { $false }
    passed = if ($testSummary -and $testSummary.PSObject.Properties["passed"]) { [int]$testSummary.passed } else { 0 }
    failed = if ($testSummary -and $testSummary.PSObject.Properties["failed"]) { [int]$testSummary.failed } else { 0 }
    total = if ($testSummary -and $testSummary.PSObject.Properties["total"]) { [int]$testSummary.total } else { 0 }
    generated_at = if ($testSummary -and $testSummary.PSObject.Properties["generated_at"]) { [string]$testSummary.generated_at } else { "" }
}

$lastPromotionResult = [pscustomobject]@{
    available = ($null -ne $qualityGate)
    gate_ok = if ($qualityGate -and $qualityGate.PSObject.Properties["ok"]) { [bool]$qualityGate.ok } else { $false }
    run_success_rate = if ($qualityGate -and $qualityGate.PSObject.Properties["summary"] -and $qualityGate.summary.PSObject.Properties["run_success_rate"]) { [double]$qualityGate.summary.run_success_rate } else { 0.0 }
    deterministic_failure_runs = if ($qualityGate -and $qualityGate.PSObject.Properties["summary"] -and $qualityGate.summary.PSObject.Properties["deterministic_failure_runs"]) { [int]$qualityGate.summary.deterministic_failure_runs } else { 0 }
    transient_lock_failure_runs = if ($qualityGate -and $qualityGate.PSObject.Properties["summary"] -and $qualityGate.summary.PSObject.Properties["transient_lock_failure_runs"]) { [int]$qualityGate.summary.transient_lock_failure_runs } else { 0 }
    generated_at = if ($qualityGate -and $qualityGate.PSObject.Properties["generated_at"]) { [string]$qualityGate.generated_at } else { "" }
}

$approvalBacklog = Get-ApprovalBacklogSnapshot -State $state
$reliabilityAlertRaw = if ($reliabilityPayload -and $reliabilityPayload.PSObject.Properties["current_alert_state"]) { [string]$reliabilityPayload.current_alert_state } else { "" }
$trendForNormalization = if ($engineeringSignal -and $engineeringSignal.PSObject.Properties["trend_direction"]) { [string]$engineeringSignal.trend_direction } else { "unknown" }
$reliabilityAlertNormalized = Resolve-ReliabilityAlertState -RawState $reliabilityAlertRaw -Trend $trendForNormalization -PendingApprovals ([int]$approvalBacklog.total_pending) -RegressionPassed ([bool]$lastRegressionResult.passed_all) -QualityGatePassed ([bool]$lastPromotionResult.gate_ok)

$knownLocalDrift = [pscustomobject]@{
    trend = if ($engineeringSignal -and $engineeringSignal.PSObject.Properties["trend_direction"]) { [string]$engineeringSignal.trend_direction } else { "unknown" }
    reliability_alert_state = $reliabilityAlertNormalized
    reliability_alert_state_raw = if ([string]::IsNullOrWhiteSpace($reliabilityAlertRaw)) { "unknown" } else { $reliabilityAlertRaw }
    pending_approvals = [int]$approvalBacklog.total_pending
}

$todCatchupRoadmap = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = "tod-catchup-roadmap-v1"
    anchor = [pscustomobject]@{
        current_objective = $currentObjective
        next_objective = $NextProposedObjective
    }
    objectives = @(
        [pscustomobject]@{ id = "TOD-17"; title = "Execution reliability stabilization"; status = if ($NextProposedObjective -eq "TOD-17") { "next" } else { "planned" } }
        [pscustomobject]@{ id = "TOD-18"; title = "Constraint evaluation integration"; status = "planned" }
        [pscustomobject]@{ id = "TOD-19"; title = "Autonomy boundary awareness"; status = "planned" }
        [pscustomobject]@{ id = "TOD-20"; title = "Cross-domain execution coordination"; status = "planned" }
        [pscustomobject]@{ id = "TOD-21"; title = "Perception event handling"; status = "planned" }
        [pscustomobject]@{ id = "TOD-22"; title = "Inquiry-driven execution pause/resume"; status = "planned" }
    )
}
$todCatchupRoadmap | ConvertTo-Json -Depth 12 | Set-Content -Path $objectiveRoadmapPath

$mimSchemaVersion = Get-MimSchemaVersionFromContextExport -PathValue $MimContextExportPath
if ([string]::IsNullOrWhiteSpace($mimSchemaVersion)) {
    $mimSchemaVersion = Get-MimSchemaVersionFromContextExport -PathValue $MimManifestPath
}
$mimStatus = Get-MimStatusSnapshot -PathValue $MimContextExportPath -StaleAfterHours $MimStatusStaleAfterHours
$objectiveAlignment = Get-ObjectiveAlignment -TodObjective $currentObjective -MimStatus $mimStatus
$todContractVersion = if ($manifest -and $manifest.PSObject.Properties["schema_version"] -and -not [string]::IsNullOrWhiteSpace([string]$manifest.schema_version)) {
    [string]$manifest.schema_version
}
else {
    ""
}
$compatibility = (-not [string]::IsNullOrWhiteSpace($mimSchemaVersion)) -and (-not [string]::IsNullOrWhiteSpace($todContractVersion)) -and ($mimSchemaVersion -eq $todContractVersion)
$integrationStatus = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = "tod-integration-status-v1"
    mim_schema = if ([string]::IsNullOrWhiteSpace($mimSchemaVersion)) { "unknown" } else { $mimSchemaVersion }
    tod_contract = if ([string]::IsNullOrWhiteSpace($todContractVersion)) { "unknown" } else { $todContractVersion }
    compatible = [bool]$compatibility
    mim_status = $mimStatus
    objective_alignment = $objectiveAlignment
}
$integrationStatus | ConvertTo-Json -Depth 8 | Set-Content -Path $integrationStatusPath

$retryTrendRows = if ($reliabilityPayload -and $reliabilityPayload.PSObject.Properties["retry_trend"] -and $null -ne $reliabilityPayload.retry_trend) { @($reliabilityPayload.retry_trend) } else { @() }
$executionEvidence = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = "tod-execution-evidence-v1"
    execution_reliability = [pscustomobject]@{
        current_alert_state = if ($reliabilityPayload -and $reliabilityPayload.PSObject.Properties["current_alert_state"]) { [string]$reliabilityPayload.current_alert_state } else { "unknown" }
        reliability_alert_reasons = if ($reliabilityPayload -and $reliabilityPayload.PSObject.Properties["reliability_alert_reasons"]) { @($reliabilityPayload.reliability_alert_reasons) } else { @() }
        engine_reliability_score = if ($reliabilityPayload -and $reliabilityPayload.PSObject.Properties["engine_reliability_score"]) { $reliabilityPayload.engine_reliability_score } else { $null }
    }
    constraint_evaluation_outcomes = [pscustomobject]@{
        drift_warnings = if ($reliabilityPayload -and $reliabilityPayload.PSObject.Properties["drift_warnings"]) { @($reliabilityPayload.drift_warnings) } else { @() }
        guardrail_trend = if ($reliabilityPayload -and $reliabilityPayload.PSObject.Properties["guardrail_trend"]) { $reliabilityPayload.guardrail_trend } else { $null }
    }
    retry_fallback_metrics = @($retryTrendRows | ForEach-Object {
            [pscustomobject]@{
                engine = if ($_.PSObject.Properties["engine"]) { [string]$_.engine } else { "unknown" }
                recent_retry_rate = if ($_.PSObject.Properties["recent_retry_rate"]) { [double]$_.recent_retry_rate } else { 0.0 }
                baseline_retry_rate = if ($_.PSObject.Properties["baseline_retry_rate"]) { [double]$_.baseline_retry_rate } else { 0.0 }
                recent_fallback_rate = if ($_.PSObject.Properties["recent_fallback_rate"]) { [double]$_.recent_fallback_rate } else { 0.0 }
                baseline_fallback_rate = if ($_.PSObject.Properties["baseline_fallback_rate"]) { [double]$_.baseline_fallback_rate } else { 0.0 }
            }
        })
    performance_deltas = @($retryTrendRows | ForEach-Object {
            $recentScore = if ($_.PSObject.Properties["recent_engine_score"]) { [double]$_.recent_engine_score } else { 0.0 }
            $baselineScore = if ($_.PSObject.Properties["baseline_engine_score"]) { [double]$_.baseline_engine_score } else { 0.0 }
            [pscustomobject]@{
                engine = if ($_.PSObject.Properties["engine"]) { [string]$_.engine } else { "unknown" }
                engine_score_recent = $recentScore
                engine_score_baseline = $baselineScore
                engine_score_delta = ($recentScore - $baselineScore)
            }
        })
}
$executionEvidence | ConvertTo-Json -Depth 20 | Set-Content -Path $executionEvidencePath

$currentBuildState = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    machine = $env:COMPUTERNAME
    repo = [pscustomobject]@{
        name = "TOD"
        root = $repoRoot
        branch = $branch
        latest_commit_sha = $commitSha
    }
    latest_objective_completed = $latestCompletedObjective
    current_schema_version = $schemaVersion
    current_release_tag = $releaseTag
    current_prod_test_status = $currentProdTestStatus
    active_capabilities = @($activeCapabilities)
    known_local_drift = $knownLocalDrift
    last_regression_result = $lastRegressionResult
    last_promotion_result = $lastPromotionResult
}

$currentBuildState | ConvertTo-Json -Depth 20 | Set-Content -Path $currentBuildStatePath

$existingObjectives = @()
if (Test-Path -Path $objectivesPath) {
    try {
        $existingObjDoc = Get-Content -Path $objectivesPath -Raw | ConvertFrom-Json
        if ($existingObjDoc -and $existingObjDoc.PSObject.Properties["objectives"]) {
            $existingObjectives = @($existingObjDoc.objectives)
        }
    }
    catch {
        $existingObjectives = @()
    }
}

$existingMap = @{}
foreach ($eo in $existingObjectives) {
    if ($eo.PSObject.Properties["objective_id"]) {
        $existingMap[[string]$eo.objective_id] = $eo
    }
}

$objectiveRecords = @()
foreach ($obj in $objectives) {
    $oid = [string]$obj.id
    $prior = if ($existingMap.ContainsKey($oid)) { $existingMap[$oid] } else { $null }

    $priorDocsRaw = $null
    if ($prior -and $prior.PSObject.Properties["docs_paths"]) {
        $priorDocsRaw = $prior.docs_paths
    }
    $normalizedDocsPaths = @(Convert-ToStringList -Value $priorDocsRaw)

    $priorCapabilitiesRaw = $null
    if ($prior -and $prior.PSObject.Properties["notable_capabilities_added"]) {
        $priorCapabilitiesRaw = $prior.notable_capabilities_added
    }
    $normalizedNotableCapabilities = @(Convert-ToStringList -Value $priorCapabilitiesRaw)

    $objectiveRecords += [pscustomobject]@{
        objective_number = Get-IdNumber -Value $oid
        objective_id = $oid
        title = if ($obj.PSObject.Properties["title"]) { [string]$obj.title } else { "" }
        status = if ($obj.PSObject.Properties["status"]) { [string]$obj.status } else { "unknown" }
        focused_gate_result = if ($qualityGate -and $qualityGate.PSObject.Properties["ok"]) { if ([bool]$qualityGate.ok) { "pass" } else { "attention" } } else { "unknown" }
        full_regression_result = if ($testSummary -and $testSummary.PSObject.Properties["passed_all"]) { if ([bool]$testSummary.passed_all) { "pass" } else { "attention" } } else { "unknown" }
        promoted = if ($prior -and $prior.PSObject.Properties["promoted"]) { [bool]$prior.promoted } else { $false }
        prod_verified = if ($prior -and $prior.PSObject.Properties["prod_verified"]) { [bool]$prior.prod_verified } else { $false }
        docs_paths = @($normalizedDocsPaths)
        notable_capabilities_added = @($normalizedNotableCapabilities)
        machine_repo_primarily_affected = if ($prior -and $prior.PSObject.Properties["machine_repo_primarily_affected"]) { [string]$prior.machine_repo_primarily_affected } else { ("{0}:TOD" -f $env:COMPUTERNAME) }
        updated_at = (Get-Date).ToUniversalTime().ToString("o")
    }
}

$objectiveLedger = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = "tod-shared-state-sync-v1"
    objective_count = @($objectiveRecords).Count
    objectives = @($objectiveRecords | Sort-Object objective_number)
}
$objectiveLedger | ConvertTo-Json -Depth 20 | Set-Content -Path $objectivesPath

$contracts = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = "tod-shared-state-sync-v1"
    manifest_schema_versions = [pscustomobject]@{
        sample_manifest_contract_version = if ($manifest -and $manifest.PSObject.Properties["contract_version"]) { [string]$manifest.contract_version } else { "unknown" }
        sample_manifest_schema_version = if ($manifest -and $manifest.PSObject.Properties["schema_version"]) { [string]$manifest.schema_version } else { "unknown" }
        tod_mim_shared_contract_doc = "v1"
        execution_feedback_contract_doc = "v1"
        shared_development_log_contract_doc = "v1"
    }
    shared_development_log = [pscustomobject]@{
        contract_doc = "docs/tod-shared-development-log-contract-v1.md"
        plan_file = "shared_state/shared_development_log_plan.json"
    }
    exposed_capabilities = @($activeCapabilities)
    important_endpoints = if ($capabilities -and $capabilities.PSObject.Properties["endpoints"]) { @($capabilities.endpoints) } else { @() }
    shared_models = @("Objective", "Task", "Result", "Review", "JournalEntry", "Manifest")
    interoperability_expectations = @(
        "TOD plans and executes within policy boundaries.",
        "MIM persists shared operational memory and lifecycle feedback.",
        "Execution feedback uses execution_id correlation and terminal status mapping.",
        "Shared-state files in shared_state are canonical sync layer for parallel sessions."
    )
}
$contracts | ConvertTo-Json -Depth 20 | Set-Content -Path $contractsPath

$pendingInboxCount = 0
$contextInbox = Get-LocalPath -PathValue $ContextSyncInboxPath
if (Test-Path -Path $contextInbox) {
    $pendingInboxCount = @((Get-ChildItem -Path $contextInbox -File -Filter "*.json")).Count
}

$blockers = @()
if ($knownLocalDrift.pending_approvals -gt 0) {
    $blockers += ("pending approvals ({0})" -f $knownLocalDrift.pending_approvals)
}
if ($pendingInboxCount -gt 0) {
    $blockers += ("context updates pending ingest ({0})" -f $pendingInboxCount)
}
if ($mimStatus.is_stale) {
    $mimAgeForBlocker = "unknown"
    if ($null -ne $mimStatus.age_hours) {
        $mimAgeForBlocker = [string]$mimStatus.age_hours
    }
    $blockers += ("mim status stale ({0}h > {1}h)" -f $mimAgeForBlocker, [string]$mimStatus.stale_after_hours)
}
if ([string]$objectiveAlignment.status -eq "mismatch") {
    $blockers += ("objective mismatch tod={0} mim={1}" -f [string]$objectiveAlignment.tod_current_objective, [string]$objectiveAlignment.mim_objective_active)
}
if (@($blockers).Count -eq 0) {
    $blockers += "none"
}

$failedRegressionTestNames = @()
if ($testSummary -and $testSummary.PSObject.Properties["failed_tests"] -and $null -ne $testSummary.failed_tests) {
    $failedRegressionTestNames = @($testSummary.failed_tests | ForEach-Object {
            if ($_.PSObject.Properties["name"]) { [string]$_.name } else { "" }
        } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
}

$nextActions = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = "tod-shared-state-sync-v1"
    current_objective_in_progress = $currentObjective
    next_proposed_objective = $NextProposedObjective
    blockers = @($blockers)
    required_verification = @(
        "focused quality gate",
        "full regression suite",
        "smoke and health checks",
        "context exchange export + ingest status"
    )
    integration_work_pending_across_boxes = @(
        "MIM consumes latest shared_state/current_build_state.json",
        "Collaborators drop updates into tod/inbox/context-sync/updates",
        "TOD ingests updates and records them in context-updates-log"
    )
    failing_regression_tests = @($failedRegressionTestNames)
    approval_backlog_snapshot = $approvalBacklog
    integration_status = $integrationStatus
    tod_catchup_roadmap = @($todCatchupRoadmap.objectives)
    approval_reduction_summary = if ($approvalReduction) {
        [pscustomobject]@{
            generated_at = if ($approvalReduction.PSObject.Properties["generated_at"]) { [string]$approvalReduction.generated_at } else { "" }
            source = if ($approvalReduction.PSObject.Properties["source"]) { [string]$approvalReduction.source } else { "" }
            totals = if ($approvalReduction.PSObject.Properties["totals"]) { $approvalReduction.totals } else { $null }
            queue_sizes = if ($approvalReduction.PSObject.Properties["queues"] -and $approvalReduction.queues) {
                [pscustomobject]@{
                    promotable_first = if ($approvalReduction.queues.PSObject.Properties["promotable_first"]) { [int]@($approvalReduction.queues.promotable_first).Count } else { 0 }
                    low_value_review = if ($approvalReduction.queues.PSObject.Properties["low_value_review"]) { [int]@($approvalReduction.queues.low_value_review).Count } else { 0 }
                    duplicate_groups = if ($approvalReduction.queues.PSObject.Properties["duplicate_groups"]) { [int]@($approvalReduction.queues.duplicate_groups).Count } else { 0 }
                    duplicate_suppression_candidates = if ($approvalReduction.queues.PSObject.Properties["duplicate_suppression_candidates"]) { [int]@($approvalReduction.queues.duplicate_suppression_candidates).Count } else { 0 }
                }
            }
            else {
                $null
            }
        }
    }
    else {
        $null
    }
}
$nextActions | ConvertTo-Json -Depth 20 | Set-Content -Path $nextActionsPath

$sharedDevLogPlan = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = "tod-shared-state-sync-v1"
    contract_version = "tod-shared-development-log-contract-v1"
    purpose = "Shared development logging and handoff protocol between TOD, MIM, and collaborators."
    ownership = [pscustomobject]@{
        tod = @(
            "Publish canonical build/objective state snapshots.",
            "Ingest collaborator updates from context inbox.",
            "Append objective-level sync events to dev journal."
        )
        mim = @(
            "Consume shared_state updates for planning and memory persistence.",
            "Publish structured planning/status updates to TOD context inbox.",
            "Correlate execution lifecycle feedback with objective state."
        )
        collaborators = @(
            "Submit structured updates with source, summary, and project scope.",
            "Use canonical shared_state files as source-of-truth during parallel work.",
            "Avoid direct edits to canonical state artifacts."
        )
    }
    cadence = [pscustomobject]@{
        event_driven = @(
            "after focused quality gate",
            "after full regression",
            "after context ingest/export cycle",
            "after objective transition"
        )
        periodic = [pscustomobject]@{
            minimum = "daily"
            recommended = "per active development session"
        }
    }
    channels = [pscustomobject]@{
        canonical_state_files = @(
            "shared_state/current_build_state.json",
            "shared_state/objectives.json",
            "shared_state/contracts.json",
            "shared_state/next_actions.json",
            "shared_state/shared_development_log_plan.json"
        )
        append_only_logs = @(
            "shared_state/dev_journal.jsonl",
            "tod/out/context-sync/context-updates-log.jsonl"
        )
        handoff_snapshots = @(
            "shared_state/chatgpt_update.md",
            "shared_state/chatgpt_update.json",
            "shared_state/latest_summary.md"
        )
        inbox = "tod/inbox/context-sync/updates"
        processed_updates = "tod/out/context-sync/processed"
    }
    merge_rules = @(
        "append-only for journal and context update logs",
        "use UTC ISO-8601 timestamps in all entries",
        "never overwrite canonical snapshot files manually",
        "prefer objective-scoped summaries over freeform notes",
        "ingested updates must preserve original payload in log record"
    )
}
$sharedDevLogPlan | ConvertTo-Json -Depth 20 | Set-Content -Path $sharedDevLogPlanPath

$journalEntry = [pscustomobject]@{
    timestamp = (Get-Date).ToUniversalTime().ToString("o")
    machine = $env:COMPUTERNAME
    repo = "TOD"
    objective = $currentObjective
    action = "shared_state_sync"
    summary = "Regenerated shared_state snapshots and contracts; objective ledger refreshed."
    commit_sha = $commitSha
    validation_result = [pscustomobject]@{
        regression_passed = [bool]$lastRegressionResult.passed_all
        quality_gate_ok = [bool]$lastPromotionResult.gate_ok
        smoke_passed = if ($smokeSummary -and $smokeSummary.PSObject.Properties["passed_all"]) { [bool]$smokeSummary.passed_all } else { $false }
    }
}
($journalEntry | ConvertTo-Json -Depth 12) + [Environment]::NewLine | Add-Content -Path $devJournalPath

$summaryLines = @()
$summaryLines += "# Shared State Summary"
$summaryLines += ""
$summaryLines += "Generated: $($currentBuildState.generated_at)"
$summaryLines += "Machine: $($env:COMPUTERNAME)"
$summaryLines += "Repo: TOD"
$summaryLines += "Branch: $branch"
$summaryLines += "Commit: $commitSha"
$summaryLines += "Release tag: $releaseTag"
$summaryLines += ""
$summaryLines += "## Build State"
$summaryLines += "- Latest objective completed: $latestCompletedObjective"
$summaryLines += "- Current objective in progress: $currentObjective"
$summaryLines += "- Test status: passed=$($lastRegressionResult.passed) failed=$($lastRegressionResult.failed) total=$($lastRegressionResult.total)"
$summaryLines += "- Quality gate ok: $([bool]$lastPromotionResult.gate_ok)"
$summaryLines += "- Drift trend: $($knownLocalDrift.trend)"
$summaryLines += ""
$summaryLines += "## Next Actions"
foreach ($item in @($nextActions.required_verification)) {
    $summaryLines += "- $item"
}
$summaryLines += ""
$summaryLines += "## Canonical Files"
$summaryLines += "- current_build_state.json"
$summaryLines += "- objectives.json"
$summaryLines += "- contracts.json"
$summaryLines += "- next_actions.json"
$summaryLines += "- shared_development_log_plan.json"
$summaryLines += "- dev_journal.jsonl"
$summaryLines += "- latest_summary.md"

$summaryLines -join [Environment]::NewLine | Set-Content -Path $latestSummaryPath

$chatgptSnapshot = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = "tod-shared-state-sync-v1"
    objective = [pscustomobject]@{
        current_in_progress = $currentObjective
        latest_completed = $latestCompletedObjective
        next_proposed = $NextProposedObjective
        objective_count = @($objectiveRecords).Count
    }
    repo = [pscustomobject]@{
        root = $repoRoot
        branch = $branch
        commit = $commitSha
        release_tag = $releaseTag
    }
    validation = [pscustomobject]@{
        regression = $lastRegressionResult
        quality_gate = $lastPromotionResult
        smoke = $currentProdTestStatus.smoke
    }
    drift = $knownLocalDrift
    blockers = @($blockers)
    capabilities = @($activeCapabilities)
    important_files = [pscustomobject]@{
        current_build_state = $currentBuildStatePath
        objectives = $objectivesPath
        contracts = $contractsPath
        next_actions = $nextActionsPath
        integration_status = $integrationStatusPath
        execution_evidence = $executionEvidencePath
        tod_objective_roadmap = $objectiveRoadmapPath
        approval_reduction_summary = if ($approvalReduction) { (Get-LocalPath -PathValue $ApprovalReductionPath) } else { "" }
        shared_development_log_plan = $sharedDevLogPlanPath
        dev_journal = $devJournalPath
        latest_summary = $latestSummaryPath
        chatgpt_update = $chatgptUpdatePath
        chatgpt_update_json = $chatgptUpdateJsonPath
    }
}

$chatgptSnapshot | ConvertTo-Json -Depth 20 | Set-Content -Path $chatgptUpdateJsonPath

$chatgptLines = @()
$chatgptLines += "# TOD ChatGPT Development Update"
$chatgptLines += ""
$chatgptLines += "Generated: $($chatgptSnapshot.generated_at)"
$chatgptLines += ""
$chatgptLines += "## Objective Status"
$chatgptLines += "- Current objective in progress: $currentObjective"
$chatgptLines += "- Latest completed objective: $latestCompletedObjective"
$chatgptLines += "- Next proposed objective: $NextProposedObjective"
$chatgptLines += "- Total objectives tracked: $(@($objectiveRecords).Count)"
$chatgptLines += ""
$chatgptLines += "## Build + Repo"
$chatgptLines += "- Branch: $branch"
$chatgptLines += "- Commit: $commitSha"
$chatgptLines += "- Release tag: $releaseTag"
$chatgptLines += ""
$chatgptLines += "## Validation"
$chatgptLines += "- Regression passed: $([bool]$lastRegressionResult.passed_all) (passed=$($lastRegressionResult.passed), failed=$($lastRegressionResult.failed), total=$($lastRegressionResult.total))"
$chatgptLines += "- Quality gate ok: $([bool]$lastPromotionResult.gate_ok)"
$chatgptLines += "- Smoke passed: $([bool]$currentProdTestStatus.smoke.passed_all)"
$chatgptLines += ""
$chatgptLines += "## Drift + Blockers"
$chatgptLines += "- Trend: $($knownLocalDrift.trend)"
$chatgptLines += "- Reliability alert: $($knownLocalDrift.reliability_alert_state)"
$chatgptLines += "- Pending approvals: $($knownLocalDrift.pending_approvals)"
foreach ($item in @($blockers)) {
    $chatgptLines += "- Blocker: $item"
}
$chatgptLines += "- Approval triage by type: $(($approvalBacklog.by_type | ConvertTo-Json -Compress))"
$chatgptLines += "- Approval triage by age: $(($approvalBacklog.by_age | ConvertTo-Json -Compress))"
$chatgptLines += "- Approval triage by source: $(($approvalBacklog.by_source | ConvertTo-Json -Compress))"
$chatgptLines += "- Approval triage counts: stale=$($approvalBacklog.stale_count) low_value=$($approvalBacklog.low_value_count) promotable=$($approvalBacklog.promotable_count)"
$chatgptLines += "- Integration status: mim_schema=$($integrationStatus.mim_schema) tod_contract=$($integrationStatus.tod_contract) compatible=$([bool]$integrationStatus.compatible)"
$chatgptLines += "- MIM freshness: available=$([bool]$integrationStatus.mim_status.available) stale=$([bool]$integrationStatus.mim_status.is_stale) age_hours=$($integrationStatus.mim_status.age_hours)"
$chatgptLines += "- Objective alignment: status=$($integrationStatus.objective_alignment.status) tod=$($integrationStatus.objective_alignment.tod_current_objective) mim=$($integrationStatus.objective_alignment.mim_objective_active)"
$chatgptLines += "- Catch-up roadmap: $(($todCatchupRoadmap.objectives | ForEach-Object { [string]$_.id }) -join ', ')"
$chatgptLines += "- Approval reduction snapshot present: $(if ($approvalReduction) { 'true' } else { 'false' })"
if ($approvalReduction -and $approvalReduction.PSObject.Properties["totals"]) {
    $chatgptLines += "- Approval reduction totals: $(($approvalReduction.totals | ConvertTo-Json -Compress))"
}
$chatgptLines += "- Failing regression tests: $(if (@($failedRegressionTestNames).Count -gt 0) { (@($failedRegressionTestNames) -join '; ') } else { 'none' })"
$chatgptLines += ""
$chatgptLines += "## Canonical Shared State Files"
$chatgptLines += "- $currentBuildStatePath"
$chatgptLines += "- $objectivesPath"
$chatgptLines += "- $contractsPath"
$chatgptLines += "- $nextActionsPath"
$chatgptLines += "- $sharedDevLogPlanPath"
$chatgptLines += "- $devJournalPath"
$chatgptLines += "- $latestSummaryPath"
$chatgptLines += "- $chatgptUpdateJsonPath"

$chatgptLines -join [Environment]::NewLine | Set-Content -Path $chatgptUpdatePath

$result = [pscustomobject]@{
    ok = $true
    source = "tod-shared-state-sync-v1"
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    output_dir = $sharedDirAbs
    files = [pscustomobject]@{
        current_build_state = $currentBuildStatePath
        objectives = $objectivesPath
        contracts = $contractsPath
        next_actions = $nextActionsPath
        integration_status = $integrationStatusPath
        execution_evidence = $executionEvidencePath
        tod_objective_roadmap = $objectiveRoadmapPath
        shared_development_log_plan = $sharedDevLogPlanPath
        dev_journal = $devJournalPath
        latest_summary = $latestSummaryPath
        chatgpt_update = $chatgptUpdatePath
        chatgpt_update_json = $chatgptUpdateJsonPath
    }
    quick_status = [pscustomobject]@{
        branch = $branch
        commit = $commitSha
        current_objective_in_progress = $currentObjective
        regression_passed = [bool]$lastRegressionResult.passed_all
        quality_gate_ok = [bool]$lastPromotionResult.gate_ok
    }
}

$result | ConvertTo-Json -Depth 12 | Write-Output
