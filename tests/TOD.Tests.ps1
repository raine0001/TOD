Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$todScript = Join-Path $repoRoot "scripts/TOD.ps1"
$configPath = Join-Path $repoRoot "tod/config/tod-config.json"

function Invoke-TodActionJson {
    param(
        [Parameter(Mandatory = $true)][string]$Action,
        [hashtable]$ExtraArgs = @{}
    )

    $invokeParams = @{
        Action = $Action
        ConfigPath = $configPath
    }
    foreach ($k in $ExtraArgs.Keys) {
        $invokeParams[$k] = [string]$ExtraArgs[$k]
    }

    $raw = & $todScript @invokeParams
    return ($raw | ConvertFrom-Json)
}

Describe "TOD Reliability Reports" {
    It "run-task-report includes reliability scorecard" {
        $report = Invoke-TodActionJson -Action "run-task-report" -ExtraArgs @{ TaskId = "45" }

        $report | Should Not BeNullOrEmpty
        (($report.PSObject.Properties.Name) -contains "reliability_scorecard") | Should Be $true
        (($report.reliability_scorecard.PSObject.Properties.Name) -contains "score") | Should Be $true
        (($report.reliability_scorecard.PSObject.Properties.Name) -contains "band") | Should Be $true
        (($report.reliability_scorecard.PSObject.Properties.Name) -contains "factors") | Should Be $true
    }

    It "blocked pre-invocation outcomes are capped low" {
        $report = Invoke-TodActionJson -Action "run-task-report" -ExtraArgs @{ TaskId = "41" }
        if ([string]$report.routing_final_outcome -ne "blocked_pre_invocation") {
            Write-Warning "Task 41 is not currently blocked_pre_invocation in state; skipping strict cap assertion."
            return
        }

        [double]$report.reliability_scorecard.score | Should Not BeGreaterThan 0.45
        [string]$report.reliability_scorecard.band | Should Be "low"
    }
}

Describe "TOD Reliability Dashboards" {
    It "show-reliability-dashboard returns aggregated payload" {
        $dashboard = Invoke-TodActionJson -Action "show-reliability-dashboard" -ExtraArgs @{ Top = "10"; Category = "refactor" }

        $dashboard | Should Not BeNullOrEmpty
        [string]$dashboard.source | Should Be "reliability_dashboard_v1"
        (($dashboard.PSObject.Properties.Name) -contains "routing_feedback") | Should Be $true
        (($dashboard.PSObject.Properties.Name) -contains "failure_taxonomy") | Should Be $true
        (($dashboard.PSObject.Properties.Name) -contains "engine_reliability") | Should Be $true
        (($dashboard.PSObject.Properties.Name) -contains "retry_trend") | Should Be $true
        (($dashboard.PSObject.Properties.Name) -contains "guardrail_trend") | Should Be $true
        (($dashboard.PSObject.Properties.Name) -contains "drift_warnings") | Should Be $true
        (($dashboard.PSObject.Properties.Name) -contains "recent_routing_decisions") | Should Be $true

        $firstTrend = @($dashboard.retry_trend | Select-Object -First 1)
        if (@($firstTrend).Count -gt 0) {
            (($firstTrend[0].PSObject.Properties.Name) -contains "recent_fallback_rate") | Should Be $true
            (($firstTrend[0].PSObject.Properties.Name) -contains "recent_guardrail_block_rate") | Should Be $true
            (($firstTrend[0].PSObject.Properties.Name) -contains "recent_engine_score") | Should Be $true
            (($firstTrend[0].PSObject.Properties.Name) -contains "alert_state") | Should Be $true
            (($firstTrend[0].PSObject.Properties.Name) -contains "recovery_progress") | Should Be $true
            (($firstTrend[0].PSObject.Properties.Name) -contains "consecutive_stable_runs") | Should Be $true
            (($firstTrend[0].PSObject.Properties.Name) -contains "decay_factor") | Should Be $true
            (($firstTrend[0].PSObject.Properties.Name) -contains "signal_age_days") | Should Be $true
            (($firstTrend[0].PSObject.Properties.Name) -contains "score_penalty") | Should Be $true
        }
    }

    It "show-failure-taxonomy returns taxonomy payload" {
        $taxonomy = Invoke-TodActionJson -Action "show-failure-taxonomy" -ExtraArgs @{ Top = "20" }

        $taxonomy | Should Not BeNullOrEmpty
        [string]$taxonomy.source | Should Be "failure_taxonomy_v1"
        (($taxonomy.PSObject.Properties.Name) -contains "groups") | Should Be $true
    }

    It "get-reliability returns endpoint payload shape" {
        $payload = Invoke-TodActionJson -Action "get-reliability" -ExtraArgs @{ Top = "20" }

        $payload | Should Not BeNullOrEmpty
        [string]$payload.path | Should Be "/tod/reliability"
        (($payload.PSObject.Properties.Name) -contains "engine_reliability_score") | Should Be $true
        (($payload.PSObject.Properties.Name) -contains "retry_trend") | Should Be $true
        (($payload.PSObject.Properties.Name) -contains "guardrail_trend") | Should Be $true
        (($payload.PSObject.Properties.Name) -contains "drift_warnings") | Should Be $true
    }
}
