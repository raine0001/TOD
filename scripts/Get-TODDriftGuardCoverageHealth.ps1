
param(
    [string]$SharedStateDir = "shared_state",
    [string[]]$TaskNames = @(
        "TOD-Watchdog-DriftGuard",
        "TOD-Watchdog-DriftGuard-Training",
        "TOD-Watchdog-DriftGuard-Overnight"
    ),
    [int]$ArtifactStaleThresholdMinutes = 35,
    [switch]$EmitJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

function Resolve-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return [System.IO.Path]::GetFullPath($PathValue)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $PathValue))
}

# ── resolve paths ────────────────────────────────────────────────────────────
$stateDir    = Resolve-LocalPath -PathValue $SharedStateDir
$latestPath  = Join-Path $stateDir "tod_watchdog_drift_guard.latest.json"
$logPath     = Join-Path $stateDir "tod_watchdog_drift_guard.log.jsonl"

$nowUtc   = [datetime]::UtcNow
$nowLocal = [datetime]::Now

# ── per-task status ───────────────────────────────────────────────────────────
$taskRows = @()
$unhealthyTasks = @()

foreach ($name in $TaskNames) {
    $row = [ordered]@{
        task_name        = $name
        registered       = $false
        state            = $null
        last_run_time    = $null
        last_task_result = $null
        next_run_time    = $null
        missed_runs      = $null
        health           = "unknown"
    }

    try {
        $info = Get-ScheduledTaskInfo -TaskName $name -ErrorAction Stop
        $task = Get-ScheduledTask  -TaskName $name -ErrorAction Stop

        $row.registered       = $true
        $row.state            = $task.State.ToString()
        $row.last_task_result = $info.LastTaskResult
        $row.missed_runs      = $info.NumberOfMissedRuns

        if ($info.LastRunTime -and $info.LastRunTime -gt [datetime]::MinValue) {
            $row.last_run_time = $info.LastRunTime.ToUniversalTime().ToString("o")
        }
        if ($info.NextRunTime -and $info.NextRunTime -gt [datetime]::MinValue) {
            $row.next_run_time = $info.NextRunTime.ToUniversalTime().ToString("o")
        }

        if ($task.State -ne "Ready" -and $task.State -ne "Running") {
            $row.health = "degraded"
            $unhealthyTasks += $name
        }
        elseif (-not [object]::ReferenceEquals($info.LastTaskResult, $null)) {
            if ($info.LastTaskResult -ne 0) {
                $row.health = "degraded"
                $unhealthyTasks += $name
            }
            else {
                $row.health = "healthy"
            }
        }
        else {
            $row.health = "healthy"
        }
    }
    catch {
        $row.health = "not_registered"
        $unhealthyTasks += $name
    }

    $taskRows += $row
}

# ── artifact freshness ────────────────────────────────────────────────────────
$artifactStatus = [ordered]@{
    path              = $latestPath
    exists            = $false
    generated_at      = $null
    age_minutes       = $null
    stale             = $true
    threshold_minutes = $ArtifactStaleThresholdMinutes
    last_reasons      = @()
    last_window_gate  = $null
    last_detected     = $null
}

if (Test-Path -Path $latestPath) {
    try {
        $artifact = Get-Content -Path $latestPath -Raw | ConvertFrom-Json
        $artifactStatus.exists      = $true
        $artifactStatus.generated_at = $artifact.generated_at

        if ($artifact.generated_at) {
            $genUtc = [datetime]::Parse($artifact.generated_at).ToUniversalTime()
            $ageMinutes = ($nowUtc - $genUtc).TotalMinutes
            $artifactStatus.age_minutes = [math]::Round($ageMinutes, 1)
            $artifactStatus.stale       = ($ageMinutes -gt $ArtifactStaleThresholdMinutes)
        }

        if ($artifact.PSObject.Properties['reasons']) {
            $artifactStatus.last_reasons = $artifact.reasons
        }
        if ($artifact.PSObject.Properties['window_gate']) {
            $artifactStatus.last_window_gate = $artifact.window_gate
        }
        if ($artifact.PSObject.Properties['detected']) {
            $artifactStatus.last_detected = $artifact.detected
        }
    }
    catch {
        $artifactStatus.exists = $true   # file present but unreadable
        $artifactStatus.stale  = $true
    }
}

# ── log file stats ────────────────────────────────────────────────────────────
$logStats = [ordered]@{
    path       = $logPath
    exists     = (Test-Path -Path $logPath)
    size_bytes = $null
}
if ($logStats.exists) {
    $logStats.size_bytes = (Get-Item -Path $logPath).Length
}

# ── overall health indicator ──────────────────────────────────────────────────
$overallHealth = "healthy"

if ($unhealthyTasks.Count -eq $TaskNames.Count) {
    $overallHealth = "offline"
}
elseif ($unhealthyTasks.Count -gt 0 -or $artifactStatus.stale) {
    $overallHealth = "degraded"
}

$coverageNotes = @()
if ($unhealthyTasks.Count -gt 0) {
    $coverageNotes += "unhealthy_tasks: $($unhealthyTasks -join ', ')"
}
if ($artifactStatus.stale -and $artifactStatus.exists) {
    $coverageNotes += "artifact_stale: age=$($artifactStatus.age_minutes)min threshold=$($ArtifactStaleThresholdMinutes)min"
}
if (-not $artifactStatus.exists) {
    $coverageNotes += "artifact_missing"
}

# ── build result ──────────────────────────────────────────────────────────────
$result = [ordered]@{
    generated_at        = $nowUtc.ToString("o")
    source              = "tod-drift-guard-coverage-health-v1"
    overall_health      = $overallHealth
    coverage_notes      = $coverageNotes
    tasks               = $taskRows
    artifact            = $artifactStatus
    log                 = $logStats
    checked_at_local    = $nowLocal.ToString("yyyy-MM-ddTHH:mm:ss")
}

if ($EmitJson) {
    $result | ConvertTo-Json -Depth 20
}
else {
    $result | ConvertTo-Json -Depth 20
}
