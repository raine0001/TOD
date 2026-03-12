param(
    [string]$ConfigPath,
    [int]$Top = 15,
    [double]$DurationHours = 4,
    [int]$CycleDelaySeconds = 90,
    [int]$ValidationCadence = 12,
    [bool]$ConservativeMode = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$todScript = Join-Path $PSScriptRoot "TOD.ps1"
$sharedSyncScript = Join-Path $PSScriptRoot "Invoke-TODSharedStateSync.ps1"
$approvalReductionScript = Join-Path $PSScriptRoot "Invoke-TODApprovalReductionPass.ps1"
$testsScript = Join-Path $PSScriptRoot "Invoke-TODTests.ps1"
$smokeScript = Join-Path $PSScriptRoot "Invoke-TODSmoke.ps1"

$outDir = Join-Path $repoRoot "tod/out/training/simulation"
if (-not (Test-Path -Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

$journalPath = Join-Path $outDir "simulation-journal.jsonl"
$summaryPath = Join-Path $outDir "simulation-summary.json"
$layoutDigestPath = Join-Path $outDir "layout-digest.md"
$graphicsStoryboardPath = Join-Path $outDir "graphics-storyboard.md"

# Start each simulation run with a fresh NDJSON journal to keep summary parsing deterministic.
Set-Content -Path $journalPath -Value ""

$effectiveConfigPath = if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    Join-Path $repoRoot "tod/config/tod-config.json"
}
else {
    if ([System.IO.Path]::IsPathRooted($ConfigPath)) { $ConfigPath } else { Join-Path $repoRoot $ConfigPath }
}

if (-not (Test-Path -Path $todScript)) { throw "Missing TOD script: $todScript" }
if (-not (Test-Path -Path $sharedSyncScript)) { throw "Missing sync script: $sharedSyncScript" }
if (-not (Test-Path -Path $approvalReductionScript)) { throw "Missing approval reduction script: $approvalReductionScript" }
if (-not (Test-Path -Path $testsScript)) { throw "Missing tests script: $testsScript" }
if (-not (Test-Path -Path $smokeScript)) { throw "Missing smoke script: $smokeScript" }
if (-not (Test-Path -Path $effectiveConfigPath)) { throw "Missing config: $effectiveConfigPath" }

function Write-Journal {
    param(
        [Parameter(Mandatory = $true)][string]$Category,
        [Parameter(Mandatory = $true)][string]$Task,
        [Parameter(Mandatory = $true)][bool]$Ok,
        [string]$Detail = "",
        [string]$Validation = "none"
    )

    $entry = [pscustomobject]@{
        timestamp_utc = (Get-Date).ToUniversalTime().ToString("o")
        category = $Category
        task = $Task
        ok = $Ok
        detail = $Detail
        validation = $Validation
    }

    ($entry | ConvertTo-Json -Depth 10 -Compress) + [Environment]::NewLine | Add-Content -Path $journalPath
}

function Select-WeightedCategory {
    $roll = Get-Random -Minimum 1 -Maximum 101
    if ($roll -le 64) { return "programming" }
    if ($roll -le 91) { return "graphics" }
    return "layout"
}

function Invoke-TodJsonAction {
    param([Parameter(Mandatory = $true)][string]$Action)
    $raw = & $todScript -Action $Action -ConfigPath $effectiveConfigPath -Top $Top
    return ($raw | ConvertFrom-Json)
}

function Invoke-ProgrammingTask {
    param([int]$Iteration)

    $taskRoll = Get-Random -Minimum 1 -Maximum 10
    if ($taskRoll -eq 1) {
        $signal = Invoke-TodJsonAction -Action "get-engineering-signal"
        $trend = if ($signal.PSObject.Properties["trend_direction"]) { [string]$signal.trend_direction } else { "unknown" }
        $pending = 0
        if ($signal.PSObject.Properties["pending_approval_state"] -and $signal.pending_approval_state -and $signal.pending_approval_state.PSObject.Properties["count"]) {
            $pending = [int]$signal.pending_approval_state.count
        }
        Write-Journal -Category "programming" -Task "engineering-signal snapshot" -Ok $true -Detail ("trend={0};pending={1}" -f $trend, $pending) -Validation "tod:get-engineering-signal"
        return
    }

    if ($taskRoll -eq 2) {
        $reliability = Invoke-TodJsonAction -Action "get-reliability"
        $alert = if ($reliability.PSObject.Properties["current_alert_state"]) { [string]$reliability.current_alert_state } else { "unknown" }
        Write-Journal -Category "programming" -Task "reliability snapshot" -Ok $true -Detail ("alert={0}" -f $alert) -Validation "tod:get-reliability"
        return
    }

    if ($taskRoll -eq 3) {
        $syncRaw = & $sharedSyncScript
        $sync = $syncRaw | ConvertFrom-Json
        Write-Journal -Category "programming" -Task "shared-state refresh" -Ok ([bool]$sync.ok) -Detail "shared_state regenerated" -Validation "Invoke-TODSharedStateSync"
        return
    }

    if ($taskRoll -eq 4) {
        $reductionRaw = & $approvalReductionScript -Top $Top -WriteOutputs -AppendJournal
        $reduction = $reductionRaw | ConvertFrom-Json
        $pendingTotal = if ($reduction.PSObject.Properties["totals"] -and $reduction.totals.PSObject.Properties["pending"]) { [int]$reduction.totals.pending } else { 0 }
        $duplicates = if ($reduction.PSObject.Properties["totals"] -and $reduction.totals.PSObject.Properties["duplicate_suppression_candidates"]) { [int]$reduction.totals.duplicate_suppression_candidates } else { 0 }
        Write-Journal -Category "programming" -Task "approval backlog classification" -Ok ([bool]$reduction.ok) -Detail ("pending={0};duplicate_suppression_candidates={1}" -f $pendingTotal, $duplicates) -Validation "Invoke-TODApprovalReductionPass"
        return
    }

    if ($taskRoll -eq 5) {
        $integrationPath = Join-Path $repoRoot "shared_state/integration_status.json"
        $integration = Get-Content -Path $integrationPath -Raw | ConvertFrom-Json
        $detail = "compatible={0};mim_schema={1};tod_contract={2}" -f [bool]$integration.compatible, [string]$integration.mim_schema, [string]$integration.tod_contract
        Write-Journal -Category "programming" -Task "integration contract visibility" -Ok $true -Detail $detail -Validation "shared_state:integration_status"
        return
    }

    if ($taskRoll -eq 6) {
        $evidencePath = Join-Path $repoRoot "shared_state/execution_evidence.json"
        $evidence = Get-Content -Path $evidencePath -Raw | ConvertFrom-Json
        $alert = "unknown"
        $reasons = 0
        if ($evidence.PSObject.Properties["execution_reliability"] -and $evidence.execution_reliability) {
            if ($evidence.execution_reliability.PSObject.Properties["current_alert_state"]) { $alert = [string]$evidence.execution_reliability.current_alert_state }
            if ($evidence.execution_reliability.PSObject.Properties["reliability_alert_reasons"]) { $reasons = @($evidence.execution_reliability.reliability_alert_reasons).Count }
        }
        Write-Journal -Category "programming" -Task "execution evidence inspection" -Ok $true -Detail ("alert={0};reason_count={1}" -f $alert, $reasons) -Validation "shared_state:execution_evidence"
        return
    }

    if ($taskRoll -eq 7 -and ($Iteration % $ValidationCadence -eq 0)) {
        $testsRaw = & $testsScript -Path "tests/*.Tests.ps1"
        $tests = $testsRaw | ConvertFrom-Json
        Write-Journal -Category "programming" -Task "light regression validation" -Ok ([bool]$tests.passed_all) -Detail ("passed={0} failed={1} total={2}" -f [int]$tests.passed, [int]$tests.failed, [int]$tests.total) -Validation "Invoke-TODTests"
        return
    }

    if ($taskRoll -eq 8 -and ($Iteration % ($ValidationCadence * 2) -eq 0)) {
        $smokeRaw = & $smokeScript -Top $Top
        $smoke = $smokeRaw | ConvertFrom-Json
        Write-Journal -Category "programming" -Task "smoke validation" -Ok ([bool]$smoke.passed_all) -Detail ("checks={0}" -f [int]$smoke.total_checks) -Validation "Invoke-TODSmoke"
        return
    }

    $dashboard = Invoke-TodJsonAction -Action "show-reliability-dashboard"
    $retryRows = if ($dashboard.PSObject.Properties["retry_trend"]) { @($dashboard.retry_trend).Count } else { 0 }
    Write-Journal -Category "programming" -Task "reliability diagnostics" -Ok $true -Detail ("retry_rows={0}" -f $retryRows) -Validation "tod:show-reliability-dashboard"
}

function Invoke-GraphicsTask {
    $now = (Get-Date).ToUniversalTime().ToString("o")
    $mermaid = @()
    $mermaid += "# TOD Graphics Storyboard"
    $mermaid += ""
    $mermaid += "Generated: $now"
    $mermaid += ""
    $mermaid += '```mermaid'
    $mermaid += "flowchart LR"
    $mermaid += "  A[MIM Strategy Update] --> B[TOD Context Ingest]"
    $mermaid += "  B --> C[Engineer Cycle]"
    $mermaid += "  C --> D[Reliability Feedback]"
    $mermaid += "  D --> E[Shared State Sync]"
    $mermaid += "  E --> F[Integration Status]"
    $mermaid += '```'
    $mermaid += ""
    $mermaid += "This file is simulation-only and does not affect runtime behavior."
    $mermaid -join [Environment]::NewLine | Set-Content -Path $graphicsStoryboardPath

    Write-Journal -Category "graphics" -Task "diagram refresh" -Ok $true -Detail "updated mermaid storyboard" -Validation "file-write"
}

function Invoke-LayoutTask {
    $nextActionsPath = Join-Path $repoRoot "shared_state/next_actions.json"
    $integrationPath = Join-Path $repoRoot "shared_state/integration_status.json"

    $nextActions = $null
    $integration = $null

    if (Test-Path -Path $nextActionsPath) {
        $nextActions = Get-Content -Path $nextActionsPath -Raw | ConvertFrom-Json
    }
    if (Test-Path -Path $integrationPath) {
        $integration = Get-Content -Path $integrationPath -Raw | ConvertFrom-Json
    }

    $lines = @()
    $lines += "# TOD Layout Digest"
    $lines += ""
    $lines += "Generated: $((Get-Date).ToUniversalTime().ToString('o'))"
    $lines += ""
    $lines += "## Execution Snapshot"
    if ($null -ne $nextActions) {
        $lines += "- Current objective: $([string]$nextActions.current_objective_in_progress)"
        $lines += "- Next objective: $([string]$nextActions.next_proposed_objective)"
        $lines += "- Blockers: $((@($nextActions.blockers) -join ', '))"
        if ($nextActions.PSObject.Properties["approval_backlog_snapshot"]) {
            $lines += "- Pending approvals: $([int]$nextActions.approval_backlog_snapshot.total_pending)"
        }
    }
    else {
        $lines += "- Next actions snapshot unavailable"
    }

    $lines += ""
    $lines += "## Contract Snapshot"
    if ($null -ne $integration) {
        $lines += "- MIM schema: $([string]$integration.mim_schema)"
        $lines += "- TOD contract: $([string]$integration.tod_contract)"
        $lines += "- Compatible: $([bool]$integration.compatible)"
    }
    else {
        $lines += "- Integration status unavailable"
    }

    $lines -join [Environment]::NewLine | Set-Content -Path $layoutDigestPath

    Write-Journal -Category "layout" -Task "layout digest refresh" -Ok $true -Detail "updated markdown digest" -Validation "file-write"
}

$startedAt = (Get-Date).ToUniversalTime()
$endAt = $startedAt.AddHours($DurationHours)

$stats = [ordered]@{
    attempted = 0
    completed = 0
    failed = 0
    programming = 0
    graphics = 0
    layout = 0
}

while ((Get-Date).ToUniversalTime() -lt $endAt) {
    $stats.attempted = [int]$stats.attempted + 1
    $iteration = [int]$stats.attempted
    $category = Select-WeightedCategory

    try {
        if ($category -eq "programming") {
            $stats.programming = [int]$stats.programming + 1
            Invoke-ProgrammingTask -Iteration $iteration
        }
        elseif ($category -eq "graphics") {
            $stats.graphics = [int]$stats.graphics + 1
            Invoke-GraphicsTask
        }
        else {
            $stats.layout = [int]$stats.layout + 1
            Invoke-LayoutTask
        }

        $stats.completed = [int]$stats.completed + 1
    }
    catch {
        $stats.failed = [int]$stats.failed + 1
        Write-Journal -Category $category -Task "task-cancelled" -Ok $false -Detail $_.Exception.Message -Validation "cancelled-on-risk"
    }

    Start-Sleep -Seconds $CycleDelaySeconds
}

$summary = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = "tod-training-simulation-v1"
    mode = if ($ConservativeMode) { "conservative" } else { "standard" }
    duration_hours = $DurationHours
    cycle_delay_seconds = $CycleDelaySeconds
    distribution_target = [pscustomobject]@{
        programming = 64
        graphics = 27
        layout = 9
    }
    tasks_attempted = [int]$stats.attempted
    tasks_completed = [int]$stats.completed
    tasks_failed = [int]$stats.failed
    category_counts = [pscustomobject]@{
        programming = [int]$stats.programming
        graphics = [int]$stats.graphics
        layout = [int]$stats.layout
    }
    validations_performed = @()
    failures = @()
    artifacts = [pscustomobject]@{
        journal = $journalPath
        summary = $summaryPath
        layout_digest = $layoutDigestPath
        graphics_storyboard = $graphicsStoryboardPath
    }
    suggested_next_objective = "TOD-17"
}

if (Test-Path -Path $journalPath) {
    try {
        $entries = @(Get-Content -Path $journalPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $_.Trim().StartsWith("{") -and $_.Trim().EndsWith("}") } | ForEach-Object { $_ | ConvertFrom-Json })
        $summary.validations_performed = @($entries | ForEach-Object { [string]$_.validation } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
        $summary.failures = @($entries | Where-Object { -not [bool]$_.ok } | Select-Object -First 20)
    }
    catch {
        $summary.failures = @([pscustomobject]@{ task = "summary-derivation"; detail = $_.Exception.Message })
    }
}

$summary | ConvertTo-Json -Depth 12 | Set-Content -Path $summaryPath
$summary | ConvertTo-Json -Depth 12 | Write-Output
