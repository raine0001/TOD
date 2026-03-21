param(
    [string]$SoakRoot = "shared_state/conversation_eval/soak",
    [string]$RunId = "latest",
    [int]$WindowCycles = 3,
    [string[]]$FocusTags = @("low_relevance", "missing_safety_boundary"),
    [switch]$EmitJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

function Resolve-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) { return $PathValue }
    return (Join-Path $repoRoot $PathValue)
}

function Get-RunDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Id
    )

    if ($Id -ne "latest") {
        $explicit = Join-Path $Root $Id
        if (-not (Test-Path -Path $explicit)) {
            throw "Soak run directory not found: $explicit"
        }
        return $explicit
    }

    $dirs = @(Get-ChildItem -Path $Root -Directory | Sort-Object Name -Descending)
    if (@($dirs).Count -eq 0) {
        throw "No soak runs found under $Root"
    }
    return $dirs[0].FullName
}

function Get-FailRows {
    param(
        [Parameter(Mandatory = $true)][object[]]$Snapshots,
        [Parameter(Mandatory = $true)][int[]]$CycleSet
    )

    $rows = @()
    foreach ($snap in @($Snapshots | Where-Object { @($CycleSet) -contains [int]$_.cycle })) {
        $tightPath = ""
        if ($snap.cycle_artifacts -and $snap.cycle_artifacts.ab_tightened) {
            $tightPath = [string]$snap.cycle_artifacts.ab_tightened
        }

        if ([string]::IsNullOrWhiteSpace($tightPath) -or -not (Test-Path -Path $tightPath)) {
            continue
        }

        $doc = Get-Content -Path $tightPath -Raw | ConvertFrom-Json
        foreach ($run in @($doc.runs | Where-Object { -not [bool]$_.passed })) {
            $rows += [pscustomobject]@{
                cycle = [int]$snap.cycle
                scenario_id = [string]$run.scenario_id
                bucket = [string]$run.bucket
                overall = [double]$run.scores.overall
                failure_tags = @($run.failure_tags)
            }
        }
    }

    return @($rows)
}

$soakRootAbs = Resolve-LocalPath -PathValue $SoakRoot
if (-not (Test-Path -Path $soakRootAbs)) {
    throw "Soak root not found: $soakRootAbs"
}

$runDir = Get-RunDirectory -Root $soakRootAbs -Id $RunId
$snapPaths = @(Get-ChildItem -Path $runDir -Filter "conversation_coach.cycle.*.json" | Sort-Object Name)
if (@($snapPaths).Count -lt 2) {
    throw "Need at least 2 cycle snapshots for drift analysis"
}

$snapshots = @($snapPaths | ForEach-Object { Get-Content -Path $_.FullName -Raw | ConvertFrom-Json })
$cycles = @($snapshots | ForEach-Object { [int]$_.cycle } | Sort-Object)

$window = [Math]::Max(1, [Math]::Min($WindowCycles, [Math]::Floor($cycles.Count / 2)))
$earlyCycles = @($cycles | Select-Object -First $window)
$lateCycles = @($cycles | Select-Object -Last $window)

$earlyRows = Get-FailRows -Snapshots $snapshots -CycleSet $earlyCycles
$lateRows = Get-FailRows -Snapshots $snapshots -CycleSet $lateCycles

$focus = @($FocusTags)

$earlyFocus = @($earlyRows | Where-Object {
        foreach ($t in @($_.failure_tags)) {
            if ($focus -contains [string]$t) { return $true }
        }
        return $false
    })
$lateFocus = @($lateRows | Where-Object {
        foreach ($t in @($_.failure_tags)) {
            if ($focus -contains [string]$t) { return $true }
        }
        return $false
    })

$earlyByScenario = @{}
foreach ($r in $earlyFocus) {
    if (-not $earlyByScenario.ContainsKey($r.scenario_id)) { $earlyByScenario[$r.scenario_id] = 0 }
    $earlyByScenario[$r.scenario_id] += 1
}

$lateByScenario = @{}
foreach ($r in $lateFocus) {
    if (-not $lateByScenario.ContainsKey($r.scenario_id)) { $lateByScenario[$r.scenario_id] = 0 }
    $lateByScenario[$r.scenario_id] += 1
}

$driftScenarios = @()
$allScenarioIds = @($earlyByScenario.Keys + $lateByScenario.Keys | Sort-Object -Unique)
foreach ($sid in $allScenarioIds) {
    $earlyCount = if ($earlyByScenario.ContainsKey($sid)) { [int]$earlyByScenario[$sid] } else { 0 }
    $lateCount = if ($lateByScenario.ContainsKey($sid)) { [int]$lateByScenario[$sid] } else { 0 }
    $delta = $lateCount - $earlyCount
    if ($delta -ne 0) {
        $driftScenarios += [pscustomobject]@{
            scenario_id = [string]$sid
            early_count = $earlyCount
            late_count = $lateCount
            delta = $delta
        }
    }
}
$driftScenarios = @($driftScenarios | Sort-Object -Property @{ Expression = 'delta'; Descending = $true }, @{ Expression = 'late_count'; Descending = $true })

$earlyTagCounts = @{}
$lateTagCounts = @{}
foreach ($r in $earlyRows) {
    foreach ($t in @($r.failure_tags)) {
        $k = [string]$t
        if (-not $earlyTagCounts.ContainsKey($k)) { $earlyTagCounts[$k] = 0 }
        $earlyTagCounts[$k] += 1
    }
}
foreach ($r in $lateRows) {
    foreach ($t in @($r.failure_tags)) {
        $k = [string]$t
        if (-not $lateTagCounts.ContainsKey($k)) { $lateTagCounts[$k] = 0 }
        $lateTagCounts[$k] += 1
    }
}

$tagDrift = @()
$allTags = @($earlyTagCounts.Keys + $lateTagCounts.Keys | Sort-Object -Unique)
foreach ($tag in $allTags) {
    $e = if ($earlyTagCounts.ContainsKey($tag)) { [int]$earlyTagCounts[$tag] } else { 0 }
    $l = if ($lateTagCounts.ContainsKey($tag)) { [int]$lateTagCounts[$tag] } else { 0 }
    $tagDrift += [pscustomobject]@{
        tag = [string]$tag
        early_count = $e
        late_count = $l
        delta = ($l - $e)
    }
}
$tagDrift = @($tagDrift | Sort-Object delta -Descending)

$report = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = "tod-conversation-drift-analysis-v1"
    run_dir = $runDir
    windows = [pscustomobject]@{
        early_cycles = @($earlyCycles)
        late_cycles = @($lateCycles)
        window_size = $window
    }
    summary = [pscustomobject]@{
        early_focus_failures = @($earlyFocus).Count
        late_focus_failures = @($lateFocus).Count
        focus_failure_delta = (@($lateFocus).Count - @($earlyFocus).Count)
    }
    tag_drift = @($tagDrift)
    scenario_drift = @($driftScenarios | Select-Object -First 30)
}

$outPath = Join-Path $runDir "conversation_coach.drift.latest.json"
$report | ConvertTo-Json -Depth 16 | Set-Content -Path $outPath

if ($EmitJson) {
    $report | ConvertTo-Json -Depth 12 | Write-Output
}
else {
    $report
}
