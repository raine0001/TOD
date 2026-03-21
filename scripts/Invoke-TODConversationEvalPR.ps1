param(
    [string]$OutputRoot = "shared_state/conversation_eval",
    [string]$DriftLockSuitePath = "tod/conversation_eval/drift_lock_suite.json",
    [int]$Seed = 7501,
    [double]$MinOverallScore = 0.68,
    [double]$MinDriftLockConsistency = 0.72,
    [double]$MinDeveloperUtility = 0.70,
    [ValidateSet("auto", "early", "mid", "late")]
    [string]$CyclePosition = "auto",
    [int]$CycleIndex = 0,
    [int]$CycleCount = 0,
    [switch]$FailOnThreshold,
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

$runner = Join-Path $PSScriptRoot "Invoke-TODConversationEvalRunner.ps1"
if (-not (Test-Path -Path $runner)) {
    throw "Runner script not found: $runner"
}

$driftLockAbs = Resolve-LocalPath -PathValue $DriftLockSuitePath
if (-not (Test-Path -Path $driftLockAbs)) {
    throw "Drift lock suite not found: $driftLockAbs"
}

$driftLockDoc = Get-Content -Path $driftLockAbs -Raw | ConvertFrom-Json
$driftScenarioIds = @($driftLockDoc.invariants | ForEach-Object { [string]$_.scenario_id } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
if (@($driftScenarioIds).Count -eq 0) {
    throw "Drift lock suite contains no scenario ids: $driftLockAbs"
}

$outputRootAbs = Resolve-LocalPath -PathValue $OutputRoot
if (-not (Test-Path -Path $outputRootAbs)) {
    New-Item -ItemType Directory -Path $outputRootAbs -Force | Out-Null
}

$smokePath = Join-Path $outputRootAbs "conversation_score_report.smoke.latest.json"
$expandedPath = Join-Path $outputRootAbs "conversation_score_report.expanded.latest.json"
$driftLockPath = Join-Path $outputRootAbs "conversation_score_report.drift_lock.latest.json"
$combinedPath = Join-Path $outputRootAbs "conversation_score_report.pr.latest.json"
$markdownScript = Join-Path $PSScriptRoot "New-TODConversationMarkdownSummary.ps1"

$smoke = & $runner -Stage smoke -PolicyProfile tightened -CyclePosition $CyclePosition -CycleIndex $CycleIndex -CycleCount $CycleCount -OutputPath $smokePath -Seed $Seed -EmitJson | ConvertFrom-Json
$expanded = & $runner -Stage expanded -PolicyProfile tightened -CyclePosition $CyclePosition -CycleIndex $CycleIndex -CycleCount $CycleCount -OutputPath $expandedPath -Seed ($Seed + 1) -EmitJson | ConvertFrom-Json
$driftLock = & $runner -Stage smoke -PolicyProfile tightened -EnableDriftLock -DriftLockSuitePath $DriftLockSuitePath -CyclePosition $CyclePosition -CycleIndex $CycleIndex -CycleCount $CycleCount -IncludeScenarioIds $driftScenarioIds -ScenarioSweep -RunCountOverride ([Math]::Max(18, @($driftScenarioIds).Count * 3)) -OutputPath $driftLockPath -Seed ($Seed + 2) -EmitJson | ConvertFrom-Json

$overall = [math]::Round((([double]$smoke.summary.overall_score + [double]$expanded.summary.overall_score) / 2.0), 4)
$developerUtility = [math]::Round((([double]$smoke.summary.developer_utility_score + [double]$expanded.summary.developer_utility_score) / 2.0), 4)
$driftLockPassed = [bool](([int]$driftLock.summary.failure_count -eq 0) -and ([double]$driftLock.summary.consistency_over_time_score -ge $MinDriftLockConsistency))
$utilityPassed = [bool]($developerUtility -ge $MinDeveloperUtility)
$gatePassed = [bool](($overall -ge $MinOverallScore) -and $driftLockPassed -and $utilityPassed)

$report = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = "tod-conversation-eval-pr-v1"
    run_id = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
    summary = [pscustomobject]@{
        overall_score = $overall
        developer_utility = $developerUtility
        smoke_overall = [double]$smoke.summary.overall_score
        expanded_overall = [double]$expanded.summary.overall_score
        smoke_developer_utility = [double]$smoke.summary.developer_utility_score
        expanded_developer_utility = [double]$expanded.summary.developer_utility_score
        smoke_failures = [int]$smoke.summary.failure_count
        expanded_failures = [int]$expanded.summary.failure_count
        drift_lock_overall = [double]$driftLock.summary.overall_score
        drift_lock_consistency = [double]$driftLock.summary.consistency_over_time_score
        drift_lock_failures = [int]$driftLock.summary.failure_count
        drift_lock_passed = $driftLockPassed
        developer_utility_passed = $utilityPassed
        min_developer_utility = $MinDeveloperUtility
        min_drift_lock_consistency = $MinDriftLockConsistency
        min_overall_threshold = $MinOverallScore
        gate_passed = $gatePassed
    }
    artifacts = [pscustomobject]@{
        smoke = $smokePath
        expanded = $expandedPath
        drift_lock = $driftLockPath
        report_markdown = ""
    }
}

$report | ConvertTo-Json -Depth 12 | Set-Content -Path $combinedPath

if (Test-Path -Path $markdownScript) {
    try {
        $markdown = & $markdownScript -Kind pr -InputPath $combinedPath -EmitJson | ConvertFrom-Json
        $report.artifacts.report_markdown = [string]$markdown.output_path
        $report | ConvertTo-Json -Depth 12 | Set-Content -Path $combinedPath
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

if ($FailOnThreshold -and -not [bool]$report.summary.gate_passed) {
    throw ("Conversation PR gate failed: overall={0} threshold={1}, utility={2} threshold={3}, drift_lock_passed={4}" -f $overall, $MinOverallScore, $developerUtility, $MinDeveloperUtility, $driftLockPassed)
}