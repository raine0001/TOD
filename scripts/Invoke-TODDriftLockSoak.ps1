param(
    [int]$Cycles = 120,
    [int]$RunCountPerCycle = 0,
    [string[]]$IncludeScenarioIds = @(),
    [string]$OutputRoot = "shared_state/conversation_eval",
    [string]$OutputPath = "",
    [string]$DriftLockSuitePath = "tod/conversation_eval/drift_lock_suite.json",
    [int]$Seed = 9801,
    [double]$PrDropTolerance = 0.002,
    [double]$UtilityDropTolerance = 0.002,
    [int]$FailOnRegressingCycles = 3,
    [double]$MinLateUtility = 0.73,
    [int]$MaxLateDriftLockViolations = 0,
    [switch]$EmitJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($Cycles -lt 1) { throw "Cycles must be >= 1" }
if ($RunCountPerCycle -lt 0) { throw "RunCountPerCycle must be >= 0 (0 = auto-size to scenario count)" }
if ($FailOnRegressingCycles -lt 0) { throw "FailOnRegressingCycles must be >= 0" }
if ($UtilityDropTolerance -lt 0) { throw "UtilityDropTolerance must be >= 0" }
if ($MaxLateDriftLockViolations -lt 0) { throw "MaxLateDriftLockViolations must be >= 0" }

$repoRoot = Split-Path -Parent $PSScriptRoot

function Resolve-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) { return [System.IO.Path]::GetFullPath($PathValue) }
    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $PathValue))
}

function Get-CyclePosition {
    param([int]$Index, [int]$Count)
    if ($Count -le 1) { return "mid" }
    $ratio = [double]$Index / [double]$Count
    if ($ratio -le 0.33) { return "early" }
    if ($ratio -ge 0.67) { return "late" }
    return "mid"
}

function Get-WindowSummary {
    param(
        [Parameter(Mandatory = $true)][object[]]$Rows,
        [Parameter(Mandatory = $true)][string]$Position
    )

    $windowRows = @($Rows | Where-Object { [string]$_.cycle_position -eq $Position })
    if (@($windowRows).Count -eq 0) {
        return [pscustomobject]@{
            cycle_position = $Position
            cycle_count = 0
            avg_overall = 0.0
            avg_consistency = 0.0
            avg_developer_utility = 0.0
            avg_failures = 0.0
            drift_lock_violation_count = 0
        }
    }

    return [pscustomobject]@{
        cycle_position = $Position
        cycle_count = @($windowRows).Count
        avg_overall = [math]::Round(((@($windowRows | ForEach-Object { [double]$_.overall }) | Measure-Object -Average).Average), 4)
        avg_consistency = [math]::Round(((@($windowRows | ForEach-Object { [double]$_.consistency }) | Measure-Object -Average).Average), 4)
        avg_developer_utility = [math]::Round(((@($windowRows | ForEach-Object { [double]$_.developer_utility }) | Measure-Object -Average).Average), 4)
        avg_failures = [math]::Round(((@($windowRows | ForEach-Object { [double]$_.failures }) | Measure-Object -Average).Average), 4)
        drift_lock_violation_count = [int]((@($windowRows | ForEach-Object { [int]$_.drift_lock_violations }) | Measure-Object -Sum).Sum)
    }
}

function Get-FamilyBreakdown {
    param(
        [Parameter(Mandatory = $true)][object[]]$Rows,
        [Parameter(Mandatory = $true)][string]$Position
    )
    $windowRows = @($Rows | Where-Object { [string]$_.cycle_position -eq $Position })
    $agg = @{}
    foreach ($wrow in $windowRows) {
        if ($null -eq $wrow.family_data) { continue }
        foreach ($fam in $wrow.family_data.Keys) {
            if (-not $agg.ContainsKey($fam)) {
                $agg[$fam] = @{ violations = 0; total = 0; failures = 0; utility_sum = 0.0 }
            }
            $agg[$fam].violations  += [int]$wrow.family_data[$fam].violations
            $agg[$fam].total       += [int]$wrow.family_data[$fam].total
            $agg[$fam].failures    += [int]$wrow.family_data[$fam].failures
            $agg[$fam].utility_sum += [double]$wrow.family_data[$fam].utility_sum
        }
    }
    $breakdown = [pscustomobject]@{}
    foreach ($fam in ($agg.Keys | Sort-Object)) {
        $d = $agg[$fam]
        $breakdown | Add-Member -NotePropertyName $fam -NotePropertyValue ([pscustomobject]@{
            violations        = [int]$d.violations
            total_runs        = [int]$d.total
            violation_density = if ($d.total -gt 0) { [math]::Round($d.violations / $d.total, 4) } else { 0.0 }
            failure_density   = if ($d.total -gt 0) { [math]::Round($d.failures   / $d.total, 4) } else { 0.0 }
            avg_utility       = if ($d.total -gt 0) { [math]::Round($d.utility_sum / $d.total, 4) } else { 0.0 }
        })
    }
    return $breakdown
}

$runner = Join-Path $PSScriptRoot "Invoke-TODConversationEvalRunner.ps1"
if (-not (Test-Path -Path $runner)) {
    throw "Runner script not found: $runner"
}

$outputRootAbs = Resolve-LocalPath -PathValue $OutputRoot
if (-not (Test-Path -Path $outputRootAbs)) {
    New-Item -ItemType Directory -Path $outputRootAbs -Force | Out-Null
}

$driftAbs = Resolve-LocalPath -PathValue $DriftLockSuitePath
if (-not (Test-Path -Path $driftAbs)) {
    throw "Drift lock suite not found: $driftAbs"
}

$driftDoc = Get-Content -Path $driftAbs -Raw | ConvertFrom-Json
$suiteIds = @($driftDoc.invariants | ForEach-Object { [string]$_.scenario_id } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
if (@($suiteIds).Count -eq 0) {
    throw "No scenario ids found in drift lock suite"
}

# When IncludeScenarioIds are provided, use them directly (allows non-suite scenarios such as ENG-*).
# When not provided, default to the full drift-lock suite.
if (@($IncludeScenarioIds).Count -gt 0) {
    $scenarioIds = @($IncludeScenarioIds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    if (@($scenarioIds).Count -eq 0) {
        throw "No scenario IDs matched after filtering; check -IncludeScenarioIds values"
    }
    # Only enable drift-lock invariant checking for IDs that exist in the suite.
    $driftLockActive = @($scenarioIds | Where-Object { $suiteIds -contains $_ }).Count -gt 0
}
else {
    $scenarioIds = $suiteIds
    $driftLockActive = $true
}

# Default RunCountPerCycle to scenario count so each scenario gets exactly one run per cycle.
$resolvedRunCount = if ($RunCountPerCycle -gt 0) { $RunCountPerCycle } else { @($scenarioIds).Count }

$soakRoot = Join-Path $outputRootAbs "drift_lock_soak"
if (-not (Test-Path -Path $soakRoot)) {
    New-Item -ItemType Directory -Path $soakRoot -Force | Out-Null
}

$runId = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
$runDir = Join-Path $soakRoot $runId
New-Item -ItemType Directory -Path $runDir -Force | Out-Null

$startedAt = Get-Date
$rows = @()
$errors = @()
$regressionStreak = 0
$maxRegressionStreak = 0
$regressed = $false

for ($cycle = 1; $cycle -le $Cycles; $cycle += 1) {
    $pos = Get-CyclePosition -Index $cycle -Count $Cycles
    $cycleSeed = $Seed + $cycle
    $cyclePath = Join-Path $runDir ("drift_lock.cycle.{0:0000}.json" -f $cycle)

    try {
        if ($driftLockActive) {
            $result = & $runner -Stage smoke -PolicyProfile tightened -EnableDriftLock -DriftLockSuitePath $DriftLockSuitePath -IncludeScenarioIds $scenarioIds -ScenarioSweep -RunCountOverride $resolvedRunCount -CyclePosition $pos -CycleIndex $cycle -CycleCount $Cycles -Seed $cycleSeed -OutputPath $cyclePath -EmitJson | ConvertFrom-Json
        }
        else {
            $result = & $runner -Stage smoke -PolicyProfile tightened -DriftLockSuitePath $DriftLockSuitePath -IncludeScenarioIds $scenarioIds -ScenarioSweep -RunCountOverride $resolvedRunCount -CyclePosition $pos -CycleIndex $cycle -CycleCount $Cycles -Seed $cycleSeed -OutputPath $cyclePath -EmitJson | ConvertFrom-Json
        }

        $row = [pscustomobject]@{
            cycle = $cycle
            cycle_position = $pos
            overall = [double]$result.summary.overall_score
            consistency = [double]$result.summary.consistency_over_time_score
            developer_utility = if ($result.summary.PSObject.Properties['developer_utility_score']) { [double]$result.summary.developer_utility_score } else { 0.0 }
            failures = [int]$result.summary.failure_count
            top_failure_tags = @($result.summary.top_failure_tags)
            drift_lock_violations = [int]@(@($result.runs | ForEach-Object { @($_.failure_tags) } | Where-Object { [string]$_ -like 'drift_lock_*_violation' })).Count
            path = $cyclePath
        }

        $familyData = @{}
        foreach ($famRun in @($result.runs)) {
            $famKey = [string]$famRun.bucket
            if (-not $familyData.ContainsKey($famKey)) {
                $familyData[$famKey] = @{ violations = 0; total = 0; failures = 0; utility_sum = 0.0 }
            }
            $familyData[$famKey].total += 1
            if ($famRun.drift_lock -and [bool]($famRun.drift_lock.passed) -eq $false) { $familyData[$famKey].violations += 1 }
            if (@($famRun.failure_tags).Count -gt 0) { $familyData[$famKey].failures += 1 }
            $familyData[$famKey].utility_sum += [double]$famRun.scores.developer_utility
        }
        $row | Add-Member -NotePropertyName family_data -NotePropertyValue $familyData
        $rows += $row

        if (@($rows).Count -gt 1) {
            $prev = $rows[@($rows).Count - 2]
            $curr = $rows[@($rows).Count - 1]
            $prDropped = (([double]$prev.overall - [double]$curr.overall) -gt $PrDropTolerance)
            $utilityDropped = (([double]$prev.developer_utility - [double]$curr.developer_utility) -gt $UtilityDropTolerance)
            $failIncreased = ([int]$curr.failures -gt [int]$prev.failures)
            $meaningfulRegression = ($failIncreased -or ($prDropped -and $utilityDropped))

            if ($meaningfulRegression) {
                $regressionStreak += 1
                if ($regressionStreak -gt $maxRegressionStreak) {
                    $maxRegressionStreak = $regressionStreak
                }
            }
            else {
                $regressionStreak = 0
            }

            if ($FailOnRegressingCycles -gt 0 -and $regressionStreak -ge $FailOnRegressingCycles) {
                $regressed = $true
                break
            }
        }
    }
    catch {
        $errors += [pscustomobject]@{
            cycle = $cycle
            error = $_.Exception.Message
        }
    }
}

$finishedAt = Get-Date
$avgOverall = if (@($rows).Count -gt 0) { [math]::Round(((@($rows | ForEach-Object { [double]$_.overall }) | Measure-Object -Average).Average), 4) } else { 0 }
$avgConsistency = if (@($rows).Count -gt 0) { [math]::Round(((@($rows | ForEach-Object { [double]$_.consistency }) | Measure-Object -Average).Average), 4) } else { 0 }
$avgDeveloperUtility = if (@($rows).Count -gt 0) { [math]::Round(((@($rows | ForEach-Object { [double]$_.developer_utility }) | Measure-Object -Average).Average), 4) } else { 0 }

$earlyWindow = Get-WindowSummary -Rows $rows -Position "early"
$midWindow = Get-WindowSummary -Rows $rows -Position "mid"
$lateWindow = Get-WindowSummary -Rows $rows -Position "late"
$earlyWindow | Add-Member -NotePropertyName family_breakdown -NotePropertyValue (Get-FamilyBreakdown -Rows $rows -Position "early")
$midWindow   | Add-Member -NotePropertyName family_breakdown -NotePropertyValue (Get-FamilyBreakdown -Rows $rows -Position "mid")
$lateWindow  | Add-Member -NotePropertyName family_breakdown -NotePropertyValue (Get-FamilyBreakdown -Rows $rows -Position "late")

$failureClusterMap = @{}
foreach ($row in @($rows)) {
    foreach ($tagEntry in @($row.top_failure_tags)) {
        $tag = [string]$tagEntry.tag
        if ([string]::IsNullOrWhiteSpace($tag)) { continue }
        if (-not $failureClusterMap.ContainsKey($tag)) {
            $failureClusterMap[$tag] = 0
        }
        $failureClusterMap[$tag] += [int]$tagEntry.count
    }
}
$topFailureClusters = @($failureClusterMap.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 10 | ForEach-Object {
        [pscustomobject]@{
            tag = [string]$_.Key
            count = [int]$_.Value
        }
    })

$lateUtilityNonDegrading = [bool]([double]$lateWindow.avg_developer_utility -ge [double]$earlyWindow.avg_developer_utility)
$lateUtilityFloorPassed = [bool]([double]$lateWindow.avg_developer_utility -ge $MinLateUtility)
$lateConsistencyNonDegrading = [bool]([double]$lateWindow.avg_consistency -ge [double]$earlyWindow.avg_consistency)
$lateFailureSpikeAbsent = [bool]([double]$lateWindow.avg_failures -le [double]$earlyWindow.avg_failures)
$lateDriftLockViolationsPassed = [bool]([int]$lateWindow.drift_lock_violation_count -le $MaxLateDriftLockViolations)
$promotionGatePassed = [bool]($lateUtilityNonDegrading -and $lateUtilityFloorPassed -and $lateConsistencyNonDegrading -and $lateFailureSpikeAbsent -and $lateDriftLockViolationsPassed)

$recommendedNextStep = if ($promotionGatePassed) {
    "Promotion-ready under governed pressure; keep nightly monitoring and expand operator-friction coverage."
}
elseif (-not $lateDriftLockViolationsPassed) {
    "Replay the late-window violating scenarios and tighten their boundary/relevance handling before promotion."
}
elseif (-not $lateUtilityFloorPassed -or -not $lateUtilityNonDegrading) {
    "Raise late-cycle usefulness before promotion; prioritize direct actionable output under messy pressure."
}
else {
    "Reduce late failure density and rerun the governed soak before baseline changes."
}

$report = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = "tod-drift-lock-soak-v1"
    run_id = $runId
    config = [pscustomobject]@{
        cycles = $Cycles
        run_count_per_cycle = $resolvedRunCount
        scenario_ids = $scenarioIds
        fail_on_regressing_cycles = $FailOnRegressingCycles
        pr_drop_tolerance = $PrDropTolerance
        utility_drop_tolerance = $UtilityDropTolerance
        drift_lock_suite = $DriftLockSuitePath
        min_late_utility = $MinLateUtility
        max_late_drift_lock_violations = $MaxLateDriftLockViolations
    }
    summary = [pscustomobject]@{
        cycles_completed = @($rows).Count
        regressed = [bool]$regressed
        max_regression_streak = $maxRegressionStreak
        avg_overall = $avgOverall
        avg_consistency = $avgConsistency
        avg_developer_utility = $avgDeveloperUtility
        final_failures = if (@($rows).Count -gt 0) { [int]$rows[-1].failures } else { $null }
        windows = [pscustomobject]@{
            early = $earlyWindow
            mid = $midWindow
            late = $lateWindow
        }
        utility_delta_early_to_late = [math]::Round(([double]$lateWindow.avg_developer_utility - [double]$earlyWindow.avg_developer_utility), 4)
        overall_delta_early_to_late = [math]::Round(([double]$lateWindow.avg_overall - [double]$earlyWindow.avg_overall), 4)
        top_failure_clusters = @($topFailureClusters)
        promotion_gates = [pscustomobject]@{
            late_utility_floor_passed = $lateUtilityFloorPassed
            utility_slope_non_negative = $lateUtilityNonDegrading
            late_consistency_non_negative = $lateConsistencyNonDegrading
            no_late_failure_spike = $lateFailureSpikeAbsent
            late_drift_lock_violations_bounded = $lateDriftLockViolationsPassed
            promotion_gate_passed = $promotionGatePassed
        }
        recommended_next_step = $recommendedNextStep
        errors = @($errors)
        started_at = $startedAt.ToUniversalTime().ToString("o")
        finished_at = $finishedAt.ToUniversalTime().ToString("o")
    }
    artifacts = [pscustomobject]@{
        run_dir = $runDir
        latest = (Join-Path $soakRoot "drift_lock_soak.latest.json")
        output_path = ""
        report_markdown = ""
        output_markdown = ""
    }
}

$latestPath = Join-Path $soakRoot "drift_lock_soak.latest.json"
$report | ConvertTo-Json -Depth 16 | Set-Content -Path $latestPath

if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $resolvedOutputPath = Resolve-LocalPath -PathValue $OutputPath
    $outputDir = Split-Path -Parent $resolvedOutputPath
    if (-not [string]::IsNullOrWhiteSpace($outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }
    $report | ConvertTo-Json -Depth 16 | Set-Content -Path $resolvedOutputPath
    $report.artifacts.output_path = $resolvedOutputPath
}

$markdownScript = Join-Path $PSScriptRoot "New-TODConversationMarkdownSummary.ps1"
if (Test-Path -Path $markdownScript) {
    try {
        $markdown = & $markdownScript -Kind drift-lock-soak -InputPath $latestPath -OutputPath (Join-Path $soakRoot "drift_lock_soak.latest.md") -EmitJson | ConvertFrom-Json
        $report.artifacts.report_markdown = [string]$markdown.output_path

        if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
            $resolvedOutputMarkdownPath = [System.IO.Path]::ChangeExtension($report.artifacts.output_path, ".md")
            $outputMarkdown = & $markdownScript -Kind drift-lock-soak -InputPath $latestPath -OutputPath $resolvedOutputMarkdownPath -EmitJson | ConvertFrom-Json
            $report.artifacts.output_markdown = [string]$outputMarkdown.output_path
        }

        $report | ConvertTo-Json -Depth 16 | Set-Content -Path $latestPath
        if (-not [string]::IsNullOrWhiteSpace($report.artifacts.output_path)) {
            $report | ConvertTo-Json -Depth 16 | Set-Content -Path $report.artifacts.output_path
        }
    }
    catch {
    }
}

if ($EmitJson) {
    $report | ConvertTo-Json -Depth 12 | Write-Output
}
else {
    $report
}

if ($regressed) {
    throw "Drift lock soak regressed for $regressionStreak consecutive cycle(s), threshold=$FailOnRegressingCycles"
}
