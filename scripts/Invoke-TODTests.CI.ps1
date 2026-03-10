param(
    [string]$SummaryPath = "tod/out/results-v2/tod-tests-summary.json",
    [string]$TestPath = "tests/*.Tests.ps1",
    [string]$HistoryPath = "tod/out/results-v2/tod-tests-history.json",
    [string]$TrendPath = "tod/out/results-v2/tod-tests-trends.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$runnerPath = Join-Path $repoRoot "scripts/Invoke-TODTests.ps1"

if (-not (Test-Path -Path $runnerPath)) {
    throw "Missing test runner: $runnerPath"
}

function Get-SafeRate {
    param(
        [double]$Numerator,
        [double]$Denominator
    )

    if ($Denominator -le 0) { return 0.0 }
    return [math]::Round(($Numerator / $Denominator), 6)
}

function Get-StateMetricsSnapshot {
    param([Parameter(Mandatory = $true)][string]$RepoRoot)

    $stateFile = Join-Path $RepoRoot "tod/data/state.json"
    if (-not (Test-Path -Path $stateFile)) {
        return [pscustomobject]@{
            retry_rate = 0.0
            guardrail_block_rate = 0.0
            per_engine_failure_rate = @()
            recovery_quality = [pscustomobject]@{
                recovered_on_retry_rate = 0.0
                recovered_on_fallback_rate = 0.0
                unrecovered_failure_rate = 0.0
                degraded_success_rate = 0.0
                manual_intervention_required_rate = 0.0
            }
        }
    }

    $state = Get-Content $stateFile -Raw | ConvertFrom-Json
    $perf = if ($state.PSObject.Properties["engine_performance"] -and $state.engine_performance -and $state.engine_performance.PSObject.Properties["records"]) { @($state.engine_performance.records) } else { @() }
    $routing = if ($state.PSObject.Properties["routing_decisions"] -and $state.routing_decisions -and $state.routing_decisions.PSObject.Properties["records"]) { @($state.routing_decisions.records) } else { @() }

    $totalPerf = [double]@($perf).Count
    $retryCount = [double]@($perf | Where-Object { $_.PSObject.Properties["retry_inflated"] -and [bool]$_.retry_inflated }).Count
    $guardrailBlocks = [double]@($routing | Where-Object {
            $blockedByFlag = ($_.PSObject.Properties["routing"] -and $_.routing -and $_.routing.PSObject.Properties["blocked"] -and [bool]$_.routing.blocked)
            $fo = if ($_.PSObject.Properties["final_outcome"] -and $null -ne $_.final_outcome) { ([string]$_.final_outcome).ToLowerInvariant() } else { "" }
            $blockedByOutcome = ($fo -in @("blocked_pre_invocation", "escalated_pre_run"))
            ($blockedByFlag -or $blockedByOutcome)
        }).Count

    $engineRates = @(
        $perf | Group-Object -Property engine | ForEach-Object {
            $items = @($_.Group)
            $total = [double]@($items).Count
            $failures = [double]@($items | Where-Object { -not [bool]$_.success }).Count
            [pscustomobject]@{
                engine = [string]$_.Name
                runs = [int]$total
                failure_rate = Get-SafeRate -Numerator $failures -Denominator $total
            }
        }
    )

    $recoveredRetry = [double]@($perf | Where-Object { $_.PSObject.Properties["recovered_on_retry"] -and [bool]$_.recovered_on_retry }).Count
    $recoveredFallback = [double]@($perf | Where-Object { $_.PSObject.Properties["recovered_on_fallback"] -and [bool]$_.recovered_on_fallback }).Count
    $unrecovered = [double]@($perf | Where-Object { $_.PSObject.Properties["unrecovered_failure"] -and [bool]$_.unrecovered_failure }).Count
    $degradedSuccess = [double]@($perf | Where-Object { $_.PSObject.Properties["degraded_success"] -and [bool]$_.degraded_success }).Count
    $manualIntervention = [double]@($perf | Where-Object { $_.PSObject.Properties["manual_intervention_required"] -and [bool]$_.manual_intervention_required }).Count

    return [pscustomobject]@{
        retry_rate = Get-SafeRate -Numerator $retryCount -Denominator $totalPerf
        guardrail_block_rate = Get-SafeRate -Numerator $guardrailBlocks -Denominator ([double][math]::Max(1, @($routing).Count))
        per_engine_failure_rate = @($engineRates)
        recovery_quality = [pscustomobject]@{
            recovered_on_retry_rate = Get-SafeRate -Numerator $recoveredRetry -Denominator $totalPerf
            recovered_on_fallback_rate = Get-SafeRate -Numerator $recoveredFallback -Denominator $totalPerf
            unrecovered_failure_rate = Get-SafeRate -Numerator $unrecovered -Denominator $totalPerf
            degraded_success_rate = Get-SafeRate -Numerator $degradedSuccess -Denominator $totalPerf
            manual_intervention_required_rate = Get-SafeRate -Numerator $manualIntervention -Denominator $totalPerf
        }
    }
}

function Get-HistoryWindowTrend {
    param(
        [Parameter(Mandatory = $true)]$History,
        [int]$Take,
        [int]$Days
    )

    $items = @($History | Sort-Object -Property timestamp)
    if ($Take -gt 0 -and @($items).Count -gt $Take) {
        $items = @($items | Select-Object -Last $Take)
    }
    if ($Days -gt 0) {
        $cutoff = (Get-Date).ToUniversalTime().AddDays(-1 * $Days)
        $items = @($items | Where-Object { (Get-Date ([string]$_.timestamp)).ToUniversalTime() -ge $cutoff })
    }

    if (@($items).Count -eq 0) {
        return [pscustomobject]@{
            runs = 0
            pass_rate = 0.0
            retry_rate = 0.0
            guardrail_block_rate = 0.0
            per_engine_failure_rate = @()
        }
    }

    $runs = [double]@($items).Count
    $passes = [double]@($items | Where-Object { [bool]$_.summary.passed_all }).Count
    $retryAvg = [math]::Round((@($items | ForEach-Object { [double]$_.metrics.retry_rate } | Measure-Object -Average).Average), 6)
    $guardrailAvg = [math]::Round((@($items | ForEach-Object { [double]$_.metrics.guardrail_block_rate } | Measure-Object -Average).Average), 6)

    $enginePoints = @{}
    foreach ($item in $items) {
        foreach ($er in @($item.metrics.per_engine_failure_rate)) {
            $k = ([string]$er.engine).ToLowerInvariant()
            if (-not $enginePoints.ContainsKey($k)) { $enginePoints[$k] = @() }
            $enginePoints[$k] += [double]$er.failure_rate
        }
    }
    $engineTrend = @()
    foreach ($k in $enginePoints.Keys) {
        $vals = @($enginePoints[$k])
        $avg = [math]::Round((@($vals | Measure-Object -Average).Average), 6)
        $engineTrend += [pscustomobject]@{ engine = $k; failure_rate = $avg }
    }

    return [pscustomobject]@{
        runs = [int]$runs
        pass_rate = Get-SafeRate -Numerator $passes -Denominator $runs
        retry_rate = $retryAvg
        guardrail_block_rate = $guardrailAvg
        per_engine_failure_rate = @($engineTrend | Sort-Object -Property engine)
    }
}

$result = & $runnerPath -Path $TestPath -JsonOutputPath $SummaryPath -FailOnTestFailure
$summaryObj = $result | ConvertFrom-Json

$metrics = Get-StateMetricsSnapshot -RepoRoot $repoRoot

$historyAbsPath = if ([System.IO.Path]::IsPathRooted($HistoryPath)) { $HistoryPath } else { Join-Path $repoRoot $HistoryPath }
$trendAbsPath = if ([System.IO.Path]::IsPathRooted($TrendPath)) { $TrendPath } else { Join-Path $repoRoot $TrendPath }

$historyDir = Split-Path -Parent $historyAbsPath
if (-not [string]::IsNullOrWhiteSpace($historyDir) -and -not (Test-Path -Path $historyDir)) {
    New-Item -ItemType Directory -Path $historyDir -Force | Out-Null
}

$history = @()
if (Test-Path -Path $historyAbsPath) {
    try {
        $existing = Get-Content $historyAbsPath -Raw | ConvertFrom-Json
        $history = @($existing)
    }
    catch {
        $history = @()
    }
}

$entry = [pscustomobject]@{
    timestamp = (Get-Date).ToUniversalTime().ToString("o")
    summary = $summaryObj
    metrics = $metrics
}
$history += $entry
$history | ConvertTo-Json -Depth 20 | Set-Content -Path $historyAbsPath

$trends = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = "tod-tests-trends"
    history_path = $HistoryPath
    windows = [pscustomobject]@{
        last_20_runs = Get-HistoryWindowTrend -History $history -Take 20 -Days 0
        last_50_runs = Get-HistoryWindowTrend -History $history -Take 50 -Days 0
        last_7_days = Get-HistoryWindowTrend -History $history -Take 0 -Days 7
    }
}

$trendDir = Split-Path -Parent $trendAbsPath
if (-not [string]::IsNullOrWhiteSpace($trendDir) -and -not (Test-Path -Path $trendDir)) {
    New-Item -ItemType Directory -Path $trendDir -Force | Out-Null
}
$trends | ConvertTo-Json -Depth 20 | Set-Content -Path $trendAbsPath

# CI logs can grep this single line reliably.
Write-Host ("TOD_TEST_SUMMARY_PATH={0}" -f $SummaryPath)
Write-Host ("TOD_TEST_HISTORY_PATH={0}" -f $HistoryPath)
Write-Host ("TOD_TEST_TREND_PATH={0}" -f $TrendPath)

if (-not [bool]$summaryObj.passed_all) {
    throw ("TOD test suite failed. See summary: {0}" -f $SummaryPath)
}
