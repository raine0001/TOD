param(
    [int]$DurationMinutes = 60,
    [int]$IntervalSeconds = 300,
    [ValidateSet("smoke", "expanded", "stress", "regression")]
    [string]$Stage = "expanded",
    [string]$OutputRoot = "shared_state/conversation_eval",
    [string[]]$FocusTags = @("low_relevance", "response_loop_risk", "missing_safety_boundary"),
    [int]$Seed = 9401,
    [int]$LiveDrillCount = 6,
    [double]$PrDropTolerance = 0.002,
    [int]$FailOnRegressingCycles = 0,
    [switch]$RunNightlyRegression,
    [switch]$UpdateBaselineAtEnd,
    [switch]$EmitJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($DurationMinutes -le 0) { throw "DurationMinutes must be > 0" }
if ($IntervalSeconds -le 0) { throw "IntervalSeconds must be > 0" }
if ($PrDropTolerance -lt 0) { throw "PrDropTolerance must be >= 0" }
if ($FailOnRegressingCycles -lt 0) { throw "FailOnRegressingCycles must be >= 0" }

$repoRoot = Split-Path -Parent $PSScriptRoot

function Resolve-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) { return $PathValue }
    return (Join-Path $repoRoot $PathValue)
}

function New-SnapshotName {
    param([int]$Cycle)
    return ("conversation_coach.cycle.{0:0000}.json" -f $Cycle)
}

function Copy-IfExists {
    param(
        [string]$Source,
        [string]$Destination
    )

    if ([string]::IsNullOrWhiteSpace($Source)) { return $false }
    if (-not (Test-Path -Path $Source)) { return $false }
    Copy-Item -Path $Source -Destination $Destination -Force
    return $true
}

$coachScript = Join-Path $PSScriptRoot "Invoke-TODConversationCoach.ps1"
if (-not (Test-Path -Path $coachScript)) {
    throw "Coach script not found: $coachScript"
}

$outputRootAbs = Resolve-LocalPath -PathValue $OutputRoot
if (-not (Test-Path -Path $outputRootAbs)) {
    New-Item -ItemType Directory -Path $outputRootAbs -Force | Out-Null
}

$soakRoot = Join-Path $outputRootAbs "soak"
if (-not (Test-Path -Path $soakRoot)) {
    New-Item -ItemType Directory -Path $soakRoot -Force | Out-Null
}

$runId = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
$runDir = Join-Path $soakRoot $runId
New-Item -ItemType Directory -Path $runDir -Force | Out-Null

$startedAt = Get-Date
$deadline = $startedAt.AddMinutes($DurationMinutes)
$expectedCycles = [Math]::Max(1, [int][Math]::Floor((($DurationMinutes * 60.0) / $IntervalSeconds)))
$cycle = 0
$snapshots = @()
$errors = @()
$regressionStreak = 0
$maxRegressionStreak = 0
$regressionFlag = $false

while ((Get-Date) -lt $deadline) {
    $cycle += 1
    $cycleSeed = $Seed + $cycle
    $cycleStarted = (Get-Date).ToUniversalTime().ToString("o")
    $cyclePosition = if ($expectedCycles -le 1) {
        "mid"
    }
    else {
        $ratio = [double]$cycle / [double]$expectedCycles
        if ($ratio -le 0.33) { "early" }
        elseif ($ratio -ge 0.67) { "late" }
        else { "mid" }
    }

    try {
        $coach = & $coachScript -Stage $Stage -OutputRoot $OutputRoot -FocusTags $FocusTags -Seed $cycleSeed -CyclePosition $cyclePosition -CycleIndex $cycle -CycleCount $expectedCycles -LiveDrillCount $LiveDrillCount -RunNightlyRegression:$RunNightlyRegression -EmitJson | ConvertFrom-Json

        $cycleComparePath = ""
        $cycleBaselinePath = ""
        $cycleTightenedPath = ""
        $cyclePrPath = ""

        if ($coach.artifacts -and $coach.artifacts.ab_compare -and (Test-Path -Path ([string]$coach.artifacts.ab_compare))) {
            $cycleComparePath = Join-Path $runDir ("conversation_score_report.ab.compare.cycle.{0:0000}.json" -f $cycle)
            $null = Copy-IfExists -Source ([string]$coach.artifacts.ab_compare) -Destination $cycleComparePath

            try {
                $compareDoc = Get-Content -Path ([string]$coach.artifacts.ab_compare) -Raw | ConvertFrom-Json
                if ($compareDoc.artifacts -and $compareDoc.artifacts.baseline) {
                    $cycleBaselinePath = Join-Path $runDir ("conversation_score_report.ab.baseline.cycle.{0:0000}.json" -f $cycle)
                    $null = Copy-IfExists -Source ([string]$compareDoc.artifacts.baseline) -Destination $cycleBaselinePath
                }
                if ($compareDoc.artifacts -and $compareDoc.artifacts.tightened) {
                    $cycleTightenedPath = Join-Path $runDir ("conversation_score_report.ab.tightened.cycle.{0:0000}.json" -f $cycle)
                    $null = Copy-IfExists -Source ([string]$compareDoc.artifacts.tightened) -Destination $cycleTightenedPath
                }
            }
            catch {
                $errors += [pscustomobject]@{
                    cycle = $cycle
                    error = "cycle_artifact_parse_failed: $($_.Exception.Message)"
                }
            }
        }

        if ($coach.artifacts -and $coach.artifacts.pr -and (Test-Path -Path ([string]$coach.artifacts.pr))) {
            $cyclePrPath = Join-Path $runDir ("conversation_score_report.pr.cycle.{0:0000}.json" -f $cycle)
            $null = Copy-IfExists -Source ([string]$coach.artifacts.pr) -Destination $cyclePrPath
        }

        $snapshot = [pscustomobject]@{
            run_id = $runId
            cycle = $cycle
            cycle_started_at = $cycleStarted
            seed = $cycleSeed
            stage = $Stage
            cycle_position = $cyclePosition
            summary = $coach.summary
            top_failure_tags = $coach.top_failure_tags
            recommended_actions = $coach.recommended_actions
            provider_status = $coach.provider_status
            source_artifact = $coach.artifacts.coach_report
            cycle_artifacts = [pscustomobject]@{
                ab_compare = $cycleComparePath
                ab_baseline = $cycleBaselinePath
                ab_tightened = $cycleTightenedPath
                pr = $cyclePrPath
            }
        }

        $snapshotPath = Join-Path $runDir (New-SnapshotName -Cycle $cycle)
        $snapshot | ConvertTo-Json -Depth 12 | Set-Content -Path $snapshotPath
        $snapshots += $snapshot

        if (@($snapshots).Count -gt 1) {
            $prev = $snapshots[@($snapshots).Count - 2]
            $curr = $snapshots[@($snapshots).Count - 1]

            $prevPr = [double]$prev.summary.pr_overall
            $currPr = [double]$curr.summary.pr_overall
            $prevFail = [int]$prev.summary.tightened_failures
            $currFail = [int]$curr.summary.tightened_failures

            $prDropped = (($prevPr - $currPr) -gt $PrDropTolerance)
            $failIncreased = ($currFail -gt $prevFail)

            if ($prDropped -or $failIncreased) {
                $regressionStreak += 1
                if ($regressionStreak -gt $maxRegressionStreak) {
                    $maxRegressionStreak = $regressionStreak
                }
            }
            else {
                $regressionStreak = 0
            }

            if ($FailOnRegressingCycles -gt 0 -and $regressionStreak -ge $FailOnRegressingCycles) {
                $regressionFlag = $true
            }
        }

        if ($regressionFlag) {
            break
        }
    }
    catch {
        $errors += [pscustomobject]@{
            cycle = $cycle
            error = $_.Exception.Message
        }
    }

    if ((Get-Date).AddSeconds($IntervalSeconds) -lt $deadline) {
        Start-Sleep -Seconds $IntervalSeconds
    }
    else {
        break
    }
}

if ($UpdateBaselineAtEnd) {
    $nightlyScript = Join-Path $PSScriptRoot "Invoke-TODConversationEvalNightly.ps1"
    if (Test-Path -Path $nightlyScript) {
        try {
            $null = & $nightlyScript -OutputRoot $OutputRoot -UpdateBaseline -EmitJson | ConvertFrom-Json
        }
        catch {
            $errors += [pscustomobject]@{
                cycle = -1
                error = "baseline_update_failed: $($_.Exception.Message)"
            }
        }
    }
}

$finishedAt = Get-Date
$durationActualMinutes = [math]::Round(($finishedAt - $startedAt).TotalMinutes, 2)

$avgPr = if (@($snapshots).Count -gt 0) {
    [math]::Round(((@($snapshots | ForEach-Object { [double]$_.summary.pr_overall }) | Measure-Object -Average).Average), 4)
}
else { 0 }

$avgDelta = if (@($snapshots).Count -gt 0) {
    [math]::Round(((@($snapshots | ForEach-Object { [double]$_.summary.ab_delta_overall }) | Measure-Object -Average).Average), 4)
}
else { 0 }

$report = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = "tod-conversation-coach-soak-v1"
    run_id = $runId
    config = [pscustomobject]@{
        duration_minutes = $DurationMinutes
        interval_seconds = $IntervalSeconds
        stage = $Stage
        focus_tags = @($FocusTags)
        seed = $Seed
        live_drill_count = $LiveDrillCount
        nightly_each_cycle = [bool]$RunNightlyRegression
        update_baseline_at_end = [bool]$UpdateBaselineAtEnd
    }
    summary = [pscustomobject]@{
        cycles_completed = @($snapshots).Count
        errors = @($errors)
        started_at = $startedAt.ToUniversalTime().ToString("o")
        finished_at = $finishedAt.ToUniversalTime().ToString("o")
        duration_minutes_actual = $durationActualMinutes
        avg_pr_overall = $avgPr
        avg_ab_delta_overall = $avgDelta
        max_regression_streak = $maxRegressionStreak
        fail_on_regressing_cycles = $FailOnRegressingCycles
        regressed = [bool]$regressionFlag
    }
    artifacts = [pscustomobject]@{
        soak_run_dir = $runDir
        soak_latest = (Join-Path $soakRoot "conversation_coach.soak.latest.json")
    }
}

$latestPath = Join-Path $soakRoot "conversation_coach.soak.latest.json"
$report | ConvertTo-Json -Depth 20 | Set-Content -Path $latestPath

if ($EmitJson) {
    $report | ConvertTo-Json -Depth 12 | Write-Output
}
else {
    $report
}

if ($regressionFlag) {
    throw "Soak regressed for $regressionStreak consecutive cycle(s), threshold=$FailOnRegressingCycles"
}