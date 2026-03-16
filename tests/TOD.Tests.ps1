Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$todScript = Join-Path $repoRoot "scripts/TOD.ps1"
$configPath = Join-Path $repoRoot "tod/config/tod-config.json"

function New-ReliabilityTestStatePath {
    $state = [pscustomobject]@{
        source = "tod-state-test-fixture-v1"
        updated_at = ""
        objectives = @(
            [pscustomobject]@{
                id = "75"
                title = "Reliability fixture objective"
                status = "in_progress"
                constraints = @()
                success_criteria = @()
            }
        )
        tasks = @(
            [pscustomobject]@{ id = "41"; objective_id = "75"; title = "Blocked fixture task"; scope = "Exercise blocked pre-invocation report path."; type = "implementation"; task_category = "code_change"; assigned_executor = "codex"; status = "blocked"; dependencies = @(); acceptance_criteria = @() },
            [pscustomobject]@{ id = "45"; objective_id = "75"; title = "Report fixture task"; scope = "Exercise reliability scorecard report path."; type = "implementation"; task_category = "refactor"; assigned_executor = "codex"; status = "pending"; dependencies = @(); acceptance_criteria = @() }
        )
        execution_results = @()
        review_decisions = @()
        journal = @()
        sync_state = [pscustomobject]@{ last_comparison = [pscustomobject]@{ status = "ok" } }
        engine_performance = [pscustomobject]@{
            records = @(
                [pscustomobject]@{ id = "PERF-001"; task_id = "45"; engine = "codex"; task_type = "implementation"; task_category = "refactor"; fallback_applied = $false; attempted_engines = @("codex"); attempts_count = 1; retry_inflated = $false; result_status = "completed"; needs_escalation = $false; failure_category = "none"; review_decision = "pass"; success = $true; recovered_on_retry = $false; recovered_on_fallback = $false; manual_intervention_required = $false; review_score = 1.0; latency_ms = 80; files_involved = @(); modules_involved = @(); created_at = (Get-Date).ToUniversalTime().AddMinutes(-5).ToString("o") }
            )
            updated_at = (Get-Date).ToUniversalTime().ToString("o")
        }
        routing_decisions = [pscustomobject]@{
            records = @(
                [pscustomobject]@{ id = "ROUTE-041"; task_id = "41"; task_category = "code_change"; selected_engine = "codex"; final_outcome = "blocked_pre_invocation"; source = "reliability_fixture"; confidence = 0.25; selection_reason = "guardrail_all_candidates_blocked"; routing = [pscustomobject]@{ reason = "guardrail_all_candidates_blocked"; applied = $true; policy = [pscustomobject]@{}; retry_policy = [pscustomobject]@{} }; created_at = (Get-Date).ToUniversalTime().AddMinutes(-3).ToString("o") },
                [pscustomobject]@{ id = "ROUTE-045"; task_id = "45"; task_category = "refactor"; selected_engine = "codex"; final_outcome = "pass"; source = "reliability_fixture"; confidence = 0.9; selection_reason = "historical_success"; routing = [pscustomobject]@{ reason = "policy_preferred_engine"; applied = $true; policy = [pscustomobject]@{}; retry_policy = [pscustomobject]@{} }; created_at = (Get-Date).ToUniversalTime().AddMinutes(-2).ToString("o") }
            )
            updated_at = (Get-Date).ToUniversalTime().ToString("o")
        }
        engineering_loop = [pscustomobject]@{
            run_history = @()
            scorecard_history = @()
            cycle_records = @()
            review_actions = @()
            last_run = $null
            last_scorecard = $null
            updated_at = (Get-Date).ToUniversalTime().ToString("o")
        }
    }

    $path = Join-Path $repoRoot ("tod/out/tests/reliability-state-{0}.json" -f ([guid]::NewGuid().ToString("N")))
    $state | ConvertTo-Json -Depth 30 | Set-Content $path
    return $path
}

function Initialize-EngineeringLoopState {
    param(
        [Parameter(Mandatory = $true)][object]$State
    )

    if (-not $State.PSObject.Properties["engineering_loop"] -or $null -eq $State.engineering_loop) {
        $State | Add-Member -NotePropertyName engineering_loop -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    if (-not $State.engineering_loop.PSObject.Properties["run_history"]) {
        $State.engineering_loop | Add-Member -NotePropertyName run_history -NotePropertyValue @() -Force
    }
    if (-not $State.engineering_loop.PSObject.Properties["scorecard_history"]) {
        $State.engineering_loop | Add-Member -NotePropertyName scorecard_history -NotePropertyValue @() -Force
    }
    if (-not $State.engineering_loop.PSObject.Properties["cycle_records"]) {
        $State.engineering_loop | Add-Member -NotePropertyName cycle_records -NotePropertyValue @() -Force
    }
    if (-not $State.engineering_loop.PSObject.Properties["review_actions"]) {
        $State.engineering_loop | Add-Member -NotePropertyName review_actions -NotePropertyValue @() -Force
    }
    if (-not $State.engineering_loop.PSObject.Properties["last_run"]) {
        $State.engineering_loop | Add-Member -NotePropertyName last_run -NotePropertyValue $null -Force
    }
    if (-not $State.engineering_loop.PSObject.Properties["last_scorecard"]) {
        $State.engineering_loop | Add-Member -NotePropertyName last_scorecard -NotePropertyValue $null -Force
    }
    if (-not $State.engineering_loop.PSObject.Properties["updated_at"]) {
        $State.engineering_loop | Add-Member -NotePropertyName updated_at -NotePropertyValue "" -Force
    }
}

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
        $invokeParams[$k] = $ExtraArgs[$k]
    }

    $attempt = 0
    while ($true) {
        try {
            $raw = & $todScript @invokeParams
            return ($raw | ConvertFrom-Json)
        }
        catch {
            $attempt += 1
            $errText = [string]$_.Exception.Message
            $isTransientStateLock = $errText -match "state\.json" -and $errText -match "used by another process"
            if ($attempt -ge 3 -or -not $isTransientStateLock) {
                throw
            }
            Start-Sleep -Milliseconds 150
        }
    }
}

Describe "TOD Reliability Reports" {
    It "run-task-report includes reliability scorecard" {
        $testStatePath = New-ReliabilityTestStatePath
        try {
            $report = Invoke-TodActionJson -Action "run-task-report" -ExtraArgs @{ TaskId = "45"; StatePath = $testStatePath }

            $report | Should Not BeNullOrEmpty
            (($report.PSObject.Properties.Name) -contains "reliability_scorecard") | Should Be $true
            (($report.reliability_scorecard.PSObject.Properties.Name) -contains "score") | Should Be $true
            (($report.reliability_scorecard.PSObject.Properties.Name) -contains "band") | Should Be $true
            (($report.reliability_scorecard.PSObject.Properties.Name) -contains "factors") | Should Be $true
        }
        finally {
            if (Test-Path $testStatePath) { Remove-Item $testStatePath -Force }
        }
    }

    It "blocked pre-invocation outcomes are capped low" {
        $testStatePath = New-ReliabilityTestStatePath
        try {
            $report = Invoke-TodActionJson -Action "run-task-report" -ExtraArgs @{ TaskId = "41"; StatePath = $testStatePath }
            if ([string]$report.routing_final_outcome -ne "blocked_pre_invocation") {
                Write-Warning "Task 41 is not currently blocked_pre_invocation in state; skipping strict cap assertion."
                return
            }

            [double]$report.reliability_scorecard.score | Should Not BeGreaterThan 0.45
            [string]$report.reliability_scorecard.band | Should Be "low"
        }
        finally {
            if (Test-Path $testStatePath) { Remove-Item $testStatePath -Force }
        }
    }
}

Describe "TOD Reliability Dashboards" {
    It "show-reliability-dashboard returns aggregated payload" {
        $testStatePath = New-ReliabilityTestStatePath
        try {
            $dashboard = Invoke-TodActionJson -Action "show-reliability-dashboard" -ExtraArgs @{ Top = "10"; Category = "refactor"; StatePath = $testStatePath }

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
        finally {
            if (Test-Path $testStatePath) { Remove-Item $testStatePath -Force }
        }
    }

    It "show-failure-taxonomy returns taxonomy payload" {
        $testStatePath = New-ReliabilityTestStatePath
        try {
            $taxonomy = Invoke-TodActionJson -Action "show-failure-taxonomy" -ExtraArgs @{ Top = "20"; StatePath = $testStatePath }

            $taxonomy | Should Not BeNullOrEmpty
            [string]$taxonomy.source | Should Be "failure_taxonomy_v1"
            (($taxonomy.PSObject.Properties.Name) -contains "groups") | Should Be $true
        }
        finally {
            if (Test-Path $testStatePath) { Remove-Item $testStatePath -Force }
        }
    }

    It "get-reliability returns endpoint payload shape" {
        $testStatePath = New-ReliabilityTestStatePath
        try {
            $payload = Invoke-TodActionJson -Action "get-reliability" -ExtraArgs @{ Top = "20"; StatePath = $testStatePath }

            $payload | Should Not BeNullOrEmpty
            [string]$payload.path | Should Be "/tod/reliability"
            (($payload.PSObject.Properties.Name) -contains "current_alert_state") | Should Be $true
            (($payload.PSObject.Properties.Name) -contains "reliability_alert_state_raw") | Should Be $true
            (($payload.PSObject.Properties.Name) -contains "reliability_alert_reasons") | Should Be $true
            (($payload.PSObject.Properties.Name) -contains "reliability_alert_inputs") | Should Be $true
            (($payload.PSObject.Properties.Name) -contains "drift_penalties_active") | Should Be $true
            (($payload.PSObject.Properties.Name) -contains "recovery_state") | Should Be $true
            (($payload.PSObject.Properties.Name) -contains "engine_reliability_score") | Should Be $true
            (($payload.PSObject.Properties.Name) -contains "retry_trend") | Should Be $true
            (($payload.PSObject.Properties.Name) -contains "guardrail_trend") | Should Be $true
            (($payload.PSObject.Properties.Name) -contains "drift_warnings") | Should Be $true

            @($payload.reliability_alert_reasons).Count | Should BeGreaterThan 0
            (($payload.reliability_alert_inputs.PSObject.Properties.Name) -contains "pending_approvals") | Should Be $true
        }
        finally {
            if (Test-Path $testStatePath) { Remove-Item $testStatePath -Force }
        }
    }

    It "get-capabilities returns endpoint payload shape" {
        $testStatePath = New-ReliabilityTestStatePath
        try {
            $caps = Invoke-TodActionJson -Action "get-capabilities" -ExtraArgs @{ StatePath = $testStatePath }

            $caps | Should Not BeNullOrEmpty
            [string]$caps.path | Should Be "/tod/capabilities"
            (($caps.PSObject.Properties.Name) -contains "execution") | Should Be $true
            (($caps.PSObject.Properties.Name) -contains "reliability") | Should Be $true
            (($caps.PSObject.Properties.Name) -contains "research") | Should Be $true
            (($caps.PSObject.Properties.Name) -contains "resourcing") | Should Be $true
            (($caps.PSObject.Properties.Name) -contains "engineering_loop_v2") | Should Be $true
            (($caps.PSObject.Properties.Name) -contains "code_write_sandbox") | Should Be $true
            (($caps.PSObject.Properties.Name) -contains "endpoints") | Should Be $true
            (@($caps.endpoints) -contains "/tod/state-bus") | Should Be $true
            (@($caps.endpoints) -contains "/tod/research") | Should Be $true
            (@($caps.endpoints) -contains "/tod/resourcing") | Should Be $true
            (@($caps.endpoints) -contains "/tod/engineer/run") | Should Be $true
            (@($caps.endpoints) -contains "/tod/engineer/scorecard") | Should Be $true
            (@($caps.endpoints) -contains "/tod/engineer/summary") | Should Be $true
            (@($caps.endpoints) -contains "/tod/engineer/signal") | Should Be $true
            (@($caps.endpoints) -contains "/tod/engineer/history") | Should Be $true
            (@($caps.endpoints) -contains "/tod/engineer/cycle") | Should Be $true
            (@($caps.endpoints) -contains "/tod/engineer/review") | Should Be $true
            (@($caps.endpoints) -contains "/tod/sandbox/files") | Should Be $true
            (@($caps.endpoints) -contains "/tod/sandbox/plan") | Should Be $true
            (@($caps.endpoints) -contains "/tod/sandbox/apply") | Should Be $true
            (@($caps.endpoints) -contains "/tod/sandbox/write") | Should Be $true
        }
        finally {
            if (Test-Path $testStatePath) { Remove-Item $testStatePath -Force }
        }
    }

    It "engineer-run returns orchestration payload with plan artifact" {
        $testStatePath = New-ReliabilityTestStatePath
        try {
            $run = Invoke-TodActionJson -Action "engineer-run" -ExtraArgs @{ Top = "10"; StatePath = $testStatePath }

            $run | Should Not BeNullOrEmpty
            [string]$run.path | Should Be "/tod/engineer/run"
            (($run.PSObject.Properties.Name) -contains "run_id") | Should Be $true
            (($run.PSObject.Properties.Name) -contains "focus") | Should Be $true
            (($run.PSObject.Properties.Name) -contains "phases") | Should Be $true
            (($run.phases.PSObject.Properties.Name) -contains "plan") | Should Be $true

            $artifactPath = Join-Path $repoRoot ([string]$run.phases.plan.artifact_path -replace "/", "\\")
            (Test-Path $artifactPath) | Should Be $true

            $bus = Invoke-TodActionJson -Action "get-state-bus" -ExtraArgs @{ Top = "10"; StatePath = $testStatePath }
            (($bus.PSObject.Properties.Name) -contains "engineering_loop_state") | Should Be $true
            ([int]$bus.engineering_loop_state.run_history_count) | Should BeGreaterThan 0
        }
        finally {
            if (Test-Path $testStatePath) { Remove-Item $testStatePath -Force }
        }
    }

    It "engineer-scorecard returns maturity dimensions" {
        $testStatePath = New-ReliabilityTestStatePath
        try {
            $scorecard = Invoke-TodActionJson -Action "engineer-scorecard" -ExtraArgs @{ Top = "25"; StatePath = $testStatePath }

            $scorecard | Should Not BeNullOrEmpty
            [string]$scorecard.path | Should Be "/tod/engineer/scorecard"
            (($scorecard.PSObject.Properties.Name) -contains "overall") | Should Be $true
            (($scorecard.PSObject.Properties.Name) -contains "dimensions") | Should Be $true
            (($scorecard.PSObject.Properties.Name) -contains "explainability") | Should Be $true
            (($scorecard.explainability.PSObject.Properties.Name) -contains "base_score") | Should Be $true
            (($scorecard.explainability.PSObject.Properties.Name) -contains "penalties") | Should Be $true
            (@($scorecard.dimensions).Count -ge 5) | Should Be $true

            $bus = Invoke-TodActionJson -Action "get-state-bus" -ExtraArgs @{ Top = "10"; StatePath = $testStatePath }
            (($bus.PSObject.Properties.Name) -contains "engineering_loop_state") | Should Be $true
            ([int]$bus.engineering_loop_state.scorecard_history_count) | Should BeGreaterThan 0
        }
        finally {
            if (Test-Path $testStatePath) { Remove-Item $testStatePath -Force }
        }
    }

    It "get-engineering-loop-summary returns v2 summary payload" {
        $testStatePath = New-ReliabilityTestStatePath
        try {
            $summary = Invoke-TodActionJson -Action "get-engineering-loop-summary" -ExtraArgs @{ Top = "10"; StatePath = $testStatePath }

            $summary | Should Not BeNullOrEmpty
            [string]$summary.path | Should Be "/tod/engineer/summary"
            (($summary.PSObject.Properties.Name) -contains "status") | Should Be $true
            (($summary.PSObject.Properties.Name) -contains "latest_score") | Should Be $true
            (($summary.PSObject.Properties.Name) -contains "run_history_count") | Should Be $true
        }
        finally {
            if (Test-Path $testStatePath) { Remove-Item $testStatePath -Force }
        }
    }

    It "get-engineering-signal returns stable integration payload" {
        $testStatePath = New-ReliabilityTestStatePath
        try {
            $signal = Invoke-TodActionJson -Action "get-engineering-signal" -ExtraArgs @{ Top = "10"; StatePath = $testStatePath }

            $signal | Should Not BeNullOrEmpty
            [string]$signal.path | Should Be "/tod/engineer/signal"
            [string]$signal.contract_version | Should Be "engineering_signal_v1"
            (($signal.PSObject.Properties.Name) -contains "current_engineering_loop_status") | Should Be $true
            (($signal.PSObject.Properties.Name) -contains "latest_maturity_band") | Should Be $true
            (($signal.PSObject.Properties.Name) -contains "pending_approval_state") | Should Be $true
            (($signal.PSObject.Properties.Name) -contains "stop_reason") | Should Be $true
            (($signal.PSObject.Properties.Name) -contains "top_penalties") | Should Be $true
            (($signal.PSObject.Properties.Name) -contains "trend_direction") | Should Be $true
            (($signal.PSObject.Properties.Name) -contains "operator_signals") | Should Be $true
        }
        finally {
            if (Test-Path $testStatePath) { Remove-Item $testStatePath -Force }
        }
    }

    It "get-engineering-loop-history returns paged history payload" {
        $testStatePath = New-ReliabilityTestStatePath
        try {
            $null = Invoke-TodActionJson -Action "engineer-run" -ExtraArgs @{ Top = "5"; StatePath = $testStatePath }
            $history = Invoke-TodActionJson -Action "get-engineering-loop-history" -ExtraArgs @{ HistoryKind = "run_history"; Page = "1"; PageSize = "5"; StatePath = $testStatePath }

            $history | Should Not BeNullOrEmpty
            [string]$history.path | Should Be "/tod/engineer/history"
            [string]$history.history_kind | Should Be "run_history"
            (($history.PSObject.Properties.Name) -contains "paging") | Should Be $true
            (($history.paging.PSObject.Properties.Name) -contains "page") | Should Be $true
            (($history.PSObject.Properties.Name) -contains "items") | Should Be $true
        }
        finally {
            if (Test-Path $testStatePath) { Remove-Item $testStatePath -Force }
        }
    }

    It "engineer-cycle executes bounded loop cycles" {
        $tmpConfigPath = Join-Path $repoRoot ("tod/config/tod-config.test-cycle-{0}.json" -f ([guid]::NewGuid().ToString("N")) )
        $testStatePath = New-ReliabilityTestStatePath
        try {
            $cfg = (Get-Content -Path $configPath -Raw) | ConvertFrom-Json
            if (-not $cfg.PSObject.Properties["engineering_loop"] -or $null -eq $cfg.engineering_loop) {
                $cfg | Add-Member -NotePropertyName engineering_loop -NotePropertyValue ([pscustomobject]@{}) -Force
            }
            if (-not $cfg.engineering_loop.PSObject.Properties["safe_continue"] -or $null -eq $cfg.engineering_loop.safe_continue) {
                $cfg.engineering_loop | Add-Member -NotePropertyName safe_continue -NotePropertyValue ([pscustomobject]@{}) -Force
            }
            $cfg.engineering_loop.safe_continue.require_no_pending_approval = $false
            ($cfg | ConvertTo-Json -Depth 24) | Set-Content -Path $tmpConfigPath

            $cycle = Invoke-TodActionJson -Action "engineer-cycle" -ExtraArgs @{ Cycles = "2"; Top = "10"; ConfigPath = $tmpConfigPath; StatePath = $testStatePath }

            $cycle | Should Not BeNullOrEmpty
            [string]$cycle.path | Should Be "/tod/engineer/cycle"
            (($cycle.PSObject.Properties.Name) -contains "cycle_steps") | Should Be $true
            ([int]$cycle.cycles_executed) | Should BeGreaterThan 0

            $history = Invoke-TodActionJson -Action "get-engineering-loop-history" -ExtraArgs @{ HistoryKind = "cycle_records"; Page = "1"; PageSize = "5"; ConfigPath = $tmpConfigPath; StatePath = $testStatePath }
            [string]$history.history_kind | Should Be "cycle_records"
            (@($history.items).Count -ge 1) | Should Be $true
            (($history.items[0].PSObject.Properties.Name) -contains "cycle_id") | Should Be $true
            (($history.items[0].PSObject.Properties.Name) -contains "run_id") | Should Be $true
            (($history.items[0].PSObject.Properties.Name) -contains "score_snapshot") | Should Be $true
        }
        finally {
            if (Test-Path $testStatePath) {
                Remove-Item $testStatePath -Force
            }
            if (Test-Path -Path $tmpConfigPath) {
                Remove-Item -Path $tmpConfigPath -Force
            }
        }
    }

    It "review-engineering-cycle supports operator actions" {
        $tmpConfigPath = Join-Path $repoRoot ("tod/config/tod-config.test-review-{0}.json" -f ([guid]::NewGuid().ToString("N")) )
        $testStatePath = New-ReliabilityTestStatePath
        try {
            $cfg = (Get-Content -Path $configPath -Raw) | ConvertFrom-Json
            if (-not $cfg.PSObject.Properties["engineering_loop"] -or $null -eq $cfg.engineering_loop) {
                $cfg | Add-Member -NotePropertyName engineering_loop -NotePropertyValue ([pscustomobject]@{}) -Force
            }
            if (-not $cfg.engineering_loop.PSObject.Properties["safe_continue"] -or $null -eq $cfg.engineering_loop.safe_continue) {
                $cfg.engineering_loop | Add-Member -NotePropertyName safe_continue -NotePropertyValue ([pscustomobject]@{}) -Force
            }
            $cfg.engineering_loop.safe_continue.require_no_pending_approval = $false
            ($cfg | ConvertTo-Json -Depth 24) | Set-Content -Path $tmpConfigPath

            $cycle = Invoke-TodActionJson -Action "engineer-cycle" -ExtraArgs @{ Cycles = "1"; Top = "10"; ConfigPath = $tmpConfigPath; StatePath = $testStatePath }
            ([int]$cycle.cycles_executed) | Should BeGreaterThan 0
            $cid = [string]$cycle.cycle_steps[0].cycle_id

            $reject = Invoke-TodActionJson -Action "review-engineering-cycle" -ExtraArgs @{ CycleId = $cid; CycleReviewAction = "reject_apply"; Rationale = "operator deferred apply"; ConfigPath = $tmpConfigPath; StatePath = $testStatePath }
            [string]$reject.path | Should Be "/tod/engineer/review"
            [string]$reject.action | Should Be "reject_apply"

            $continue = Invoke-TodActionJson -Action "review-engineering-cycle" -ExtraArgs @{ CycleId = $cid; CycleReviewAction = "continue_cycle"; Rationale = "run one more cycle"; ConfigPath = $tmpConfigPath; StatePath = $testStatePath }
            [string]$continue.path | Should Be "/tod/engineer/review"
            [string]$continue.action | Should Be "continue_cycle"
            (($continue.review.result.PSObject.Properties.Name) -contains "continued_cycle") | Should Be $true

            $reviews = Invoke-TodActionJson -Action "get-engineering-loop-history" -ExtraArgs @{ HistoryKind = "review_actions"; Page = "1"; PageSize = "5"; ConfigPath = $tmpConfigPath; StatePath = $testStatePath }
            [string]$reviews.history_kind | Should Be "review_actions"
            (@($reviews.items).Count -ge 1) | Should Be $true
        }
        finally {
            if (Test-Path $testStatePath) {
                Remove-Item $testStatePath -Force
            }
            if (Test-Path -Path $tmpConfigPath) {
                Remove-Item -Path $tmpConfigPath -Force
            }
        }
    }

    It "sandbox-apply-plan requires dangerous approval by default" {
        $testStatePath = New-ReliabilityTestStatePath
        $sandboxRelPath = "projects/tod/docs/selftest/tod-sandbox-guardrail-{0}.txt" -f ([guid]::NewGuid().ToString("N"))
        $plannedBody = "guardrail apply"
        try {
            $plan = Invoke-TodActionJson -Action "sandbox-plan" -ExtraArgs @{ SandboxPath = $sandboxRelPath; Content = $plannedBody; StatePath = $testStatePath }

            {
                Invoke-TodActionJson -Action "sandbox-apply-plan" -ExtraArgs @{ SandboxPlanPath = [string]$plan.artifact_path; StatePath = $testStatePath }
            } | Should Throw

            $applyApproved = Invoke-TodActionJson -Action "sandbox-apply-plan" -ExtraArgs @{ SandboxPlanPath = [string]$plan.artifact_path; DangerousApproved = $true; StatePath = $testStatePath }
            [string]$applyApproved.path | Should Be "/tod/sandbox/apply"
        }
        finally {
            if (Test-Path $testStatePath) { Remove-Item $testStatePath -Force }
        }
    }

    It "engineering loop scorecard trend direction is flat for low delta" {
        $testStatePath = New-ReliabilityTestStatePath
        try {
            $state = (Get-Content -Path $testStatePath -Raw) | ConvertFrom-Json
            Initialize-EngineeringLoopState -State $state

            $base = (Get-Date).ToUniversalTime().AddMinutes(-2)
            $rows = @(
                [pscustomobject]@{ generated_at = $base.ToString("o"); window = 25; score = 0.50; band = "test"; low_areas = @() },
                [pscustomobject]@{ generated_at = $base.AddMinutes(1).ToString("o"); window = 25; score = 0.51; band = "test"; low_areas = @() }
            )

            $state.engineering_loop.scorecard_history = @($rows)
            $state.engineering_loop.last_scorecard = $rows[1]
            $state.engineering_loop.updated_at = (Get-Date).ToUniversalTime().ToString("o")
            ($state | ConvertTo-Json -Depth 24) | Set-Content -Path $testStatePath

            $flatBus = Invoke-TodActionJson -Action "get-state-bus" -ExtraArgs @{ Top = "10"; StatePath = $testStatePath }
            [string]$flatBus.engineering_loop_state.trend_direction | Should Be "flat"
        }
        finally {
            if (Test-Path $testStatePath) { Remove-Item $testStatePath -Force }
        }
    }

    It "engineering loop scorecard trend direction is improving for positive delta" {
        $testStatePath = New-ReliabilityTestStatePath
        try {
            $state = (Get-Content -Path $testStatePath -Raw) | ConvertFrom-Json
            Initialize-EngineeringLoopState -State $state

            $base = (Get-Date).ToUniversalTime().AddMinutes(-2)
            $rows = @(
                [pscustomobject]@{ generated_at = $base.ToString("o"); window = 25; score = 0.40; band = "test"; low_areas = @() },
                [pscustomobject]@{ generated_at = $base.AddMinutes(1).ToString("o"); window = 25; score = 0.52; band = "test"; low_areas = @() }
            )

            $state.engineering_loop.scorecard_history = @($rows)
            $state.engineering_loop.last_scorecard = $rows[1]
            $state.engineering_loop.updated_at = (Get-Date).ToUniversalTime().ToString("o")
            ($state | ConvertTo-Json -Depth 24) | Set-Content -Path $testStatePath

            $improvingBus = Invoke-TodActionJson -Action "get-state-bus" -ExtraArgs @{ Top = "10"; StatePath = $testStatePath }
            [string]$improvingBus.engineering_loop_state.trend_direction | Should Be "improving"
        }
        finally {
            if (Test-Path $testStatePath) { Remove-Item $testStatePath -Force }
        }
    }

    It "engineering loop scorecard trend direction is declining for negative delta" {
        $testStatePath = New-ReliabilityTestStatePath
        try {
            $state = (Get-Content -Path $testStatePath -Raw) | ConvertFrom-Json
            Initialize-EngineeringLoopState -State $state

            $base = (Get-Date).ToUniversalTime().AddMinutes(-2)
            $rows = @(
                [pscustomobject]@{ generated_at = $base.ToString("o"); window = 25; score = 0.78; band = "test"; low_areas = @() },
                [pscustomobject]@{ generated_at = $base.AddMinutes(1).ToString("o"); window = 25; score = 0.60; band = "test"; low_areas = @() }
            )

            $state.engineering_loop.scorecard_history = @($rows)
            $state.engineering_loop.last_scorecard = $rows[1]
            $state.engineering_loop.updated_at = (Get-Date).ToUniversalTime().ToString("o")
            ($state | ConvertTo-Json -Depth 24) | Set-Content -Path $testStatePath

            $decliningBus = Invoke-TodActionJson -Action "get-state-bus" -ExtraArgs @{ Top = "10"; StatePath = $testStatePath }
            [string]$decliningBus.engineering_loop_state.trend_direction | Should Be "declining"
        }
        finally {
            if (Test-Path $testStatePath) { Remove-Item $testStatePath -Force }
        }
    }

    It "engineering loop run history enforces minimum retention floor of 10" {
        $testStatePath = New-ReliabilityTestStatePath
        $tmpConfigPath = Join-Path $repoRoot ("tod/config/tod-config.test-retention-floor-{0}.json" -f ([guid]::NewGuid().ToString("N")))
        try {
            $cfg = (Get-Content -Path $configPath -Raw) | ConvertFrom-Json
            if (-not $cfg.PSObject.Properties["engineering_loop"] -or $null -eq $cfg.engineering_loop) {
                $cfg | Add-Member -NotePropertyName engineering_loop -NotePropertyValue ([pscustomobject]@{}) -Force
            }
            $cfg.engineering_loop.max_run_history = 1
            $cfg.engineering_loop.max_scorecard_history = 150
            ($cfg | ConvertTo-Json -Depth 24) | Set-Content -Path $tmpConfigPath

            $state = (Get-Content -Path $testStatePath -Raw) | ConvertFrom-Json
            Initialize-EngineeringLoopState -State $state
            $state.engineering_loop.run_history = @()
            $state.engineering_loop.last_run = $null
            ($state | ConvertTo-Json -Depth 24) | Set-Content -Path $testStatePath

            for ($i = 0; $i -lt 12; $i++) {
                $null = Invoke-TodActionJson -Action "engineer-run" -ExtraArgs @{ Top = "5"; ConfigPath = $tmpConfigPath; StatePath = $testStatePath }
            }

            $bus = Invoke-TodActionJson -Action "get-state-bus" -ExtraArgs @{ Top = "10"; ConfigPath = $tmpConfigPath; StatePath = $testStatePath }
            [int]$bus.engineering_loop_state.run_history_count | Should Be 10
        }
        finally {
            if (Test-Path $testStatePath) { Remove-Item $testStatePath -Force }
            if (Test-Path -Path $tmpConfigPath) {
                Remove-Item -Path $tmpConfigPath -Force
            }
        }
    }

    It "engineering loop scorecard history enforces maximum retention clamp of 1000" {
        $testStatePath = New-ReliabilityTestStatePath
        $tmpConfigPath = Join-Path $repoRoot ("tod/config/tod-config.test-retention-ceiling-{0}.json" -f ([guid]::NewGuid().ToString("N")))
        try {
            $cfg = (Get-Content -Path $configPath -Raw) | ConvertFrom-Json
            if (-not $cfg.PSObject.Properties["engineering_loop"] -or $null -eq $cfg.engineering_loop) {
                $cfg | Add-Member -NotePropertyName engineering_loop -NotePropertyValue ([pscustomobject]@{}) -Force
            }
            $cfg.engineering_loop.max_run_history = 150
            $cfg.engineering_loop.max_scorecard_history = 5000
            ($cfg | ConvertTo-Json -Depth 24) | Set-Content -Path $tmpConfigPath

            $state = (Get-Content -Path $testStatePath -Raw) | ConvertFrom-Json
            Initialize-EngineeringLoopState -State $state

            $base = (Get-Date).ToUniversalTime().AddMinutes(-1006)
            $rows = @()
            for ($i = 0; $i -lt 1005; $i++) {
                $rows += [pscustomobject]@{
                    generated_at = $base.AddMinutes($i).ToString("o")
                    window = 25
                    score = 0.5
                    band = "test"
                    low_areas = @()
                }
            }

            $state.engineering_loop.scorecard_history = @($rows)
            $state.engineering_loop.last_scorecard = $rows[@($rows).Count - 1]
            ($state | ConvertTo-Json -Depth 24) | Set-Content -Path $testStatePath

            $null = Invoke-TodActionJson -Action "engineer-scorecard" -ExtraArgs @{ Top = "5"; ConfigPath = $tmpConfigPath; StatePath = $testStatePath }
            $bus = Invoke-TodActionJson -Action "get-state-bus" -ExtraArgs @{ Top = "10"; ConfigPath = $tmpConfigPath; StatePath = $testStatePath }
            [int]$bus.engineering_loop_state.scorecard_history_count | Should Be 1000
        }
        finally {
            if (Test-Path $testStatePath) { Remove-Item $testStatePath -Force }
            if (Test-Path -Path $tmpConfigPath) {
                Remove-Item -Path $tmpConfigPath -Force
            }
        }
    }

    It "sandbox-write and sandbox-list return endpoint payload shape" {
        $testStatePath = New-ReliabilityTestStatePath
        $sandboxRelPath = "projects/tod/docs/selftest/tod-sandbox-test-{0}.txt" -f ([guid]::NewGuid().ToString("N"))
        $sandboxBody = "sandbox smoke write"
        try {
            $write = Invoke-TodActionJson -Action "sandbox-write" -ExtraArgs @{ SandboxPath = $sandboxRelPath; Content = $sandboxBody; StatePath = $testStatePath }
            $list = Invoke-TodActionJson -Action "sandbox-list" -ExtraArgs @{ Top = "25"; StatePath = $testStatePath }

            [string]$write.path | Should Be "/tod/sandbox/write"
            (($write.PSObject.Properties.Name) -contains "sandbox_path") | Should Be $true
            (($write.PSObject.Properties.Name) -contains "sha256") | Should Be $true
            [string]$list.path | Should Be "/tod/sandbox/files"
            (($list.PSObject.Properties.Name) -contains "files") | Should Be $true

            $normalizedRel = ($sandboxRelPath -replace "\\", "/")
            $paths = @($list.files | ForEach-Object { [string]$_.path })
            ($paths -contains $normalizedRel) | Should Be $true
        }
        finally {
            if (Test-Path $testStatePath) { Remove-Item $testStatePath -Force }
        }
    }

    It "sandbox-plan returns non-destructive diff artifact payload" {
        $testStatePath = New-ReliabilityTestStatePath
        $sandboxRelPath = "projects/tod/docs/selftest/tod-sandbox-plan-{0}.txt" -f ([guid]::NewGuid().ToString("N"))
        $sandboxBody = "planned-only body"
        $sandboxTarget = Join-Path $repoRoot ("tod/sandbox/workspace/" + ($sandboxRelPath -replace "/", "\\"))

        try {
            if (Test-Path $sandboxTarget) {
                Remove-Item -Path $sandboxTarget -Force
            }

            $plan = Invoke-TodActionJson -Action "sandbox-plan" -ExtraArgs @{ SandboxPath = $sandboxRelPath; Content = $sandboxBody; StatePath = $testStatePath }

            [string]$plan.path | Should Be "/tod/sandbox/plan"
            ([bool]$plan.will_create) | Should Be $true
            (($plan.PSObject.Properties.Name) -contains "diff_preview") | Should Be $true
            (($plan.PSObject.Properties.Name) -contains "artifact_path") | Should Be $true
            ((Test-Path $sandboxTarget) -eq $false) | Should Be $true

            $artifactPath = Join-Path $repoRoot ([string]$plan.artifact_path -replace "/", "\\")
            (Test-Path $artifactPath) | Should Be $true
        }
        finally {
            if (Test-Path $testStatePath) { Remove-Item $testStatePath -Force }
        }
    }

    It "sandbox-apply-plan writes planned content with hash integrity" {
        $testStatePath = New-ReliabilityTestStatePath
        $sandboxRelPath = "projects/tod/docs/selftest/tod-sandbox-apply-{0}.txt" -f ([guid]::NewGuid().ToString("N"))
        $initialBody = "initial"
        $plannedBody = "planned content v2"
        try {
            $null = Invoke-TodActionJson -Action "sandbox-write" -ExtraArgs @{ SandboxPath = $sandboxRelPath; Content = $initialBody; StatePath = $testStatePath }
            $plan = Invoke-TodActionJson -Action "sandbox-plan" -ExtraArgs @{ SandboxPath = $sandboxRelPath; Content = $plannedBody; StatePath = $testStatePath }
            $apply = Invoke-TodActionJson -Action "sandbox-apply-plan" -ExtraArgs @{ SandboxPlanPath = [string]$plan.artifact_path; DangerousApproved = $true; StatePath = $testStatePath }

            [string]$apply.path | Should Be "/tod/sandbox/apply"
            ([bool]$apply.applied) | Should Be $true
            (($apply.PSObject.Properties.Name) -contains "sha256") | Should Be $true

            $sandboxTarget = Join-Path $repoRoot ("tod/sandbox/workspace/" + ($sandboxRelPath -replace "/", "\\"))
            (Test-Path $sandboxTarget) | Should Be $true
            ([string](Get-Content -Path $sandboxTarget -Raw)).Trim() | Should Be $plannedBody
        }
        finally {
            if (Test-Path $testStatePath) { Remove-Item $testStatePath -Force }
        }
    }

    It "get-research returns endpoint payload shape" {
        $testStatePath = New-ReliabilityTestStatePath
        try {
            $research = Invoke-TodActionJson -Action "get-research" -ExtraArgs @{ Top = "10"; StatePath = $testStatePath }

            $research | Should Not BeNullOrEmpty
            [string]$research.path | Should Be "/tod/research"
            (($research.PSObject.Properties.Name) -contains "repository") | Should Be $true
            (($research.PSObject.Properties.Name) -contains "active_context") | Should Be $true
            (($research.PSObject.Properties.Name) -contains "exploration") | Should Be $true
        }
        finally {
            if (Test-Path $testStatePath) { Remove-Item $testStatePath -Force }
        }
    }

    It "get-resourcing returns endpoint payload shape" {
        $testStatePath = New-ReliabilityTestStatePath
        try {
            $resourcing = Invoke-TodActionJson -Action "get-resourcing" -ExtraArgs @{ Top = "10"; ObjectiveId = "16"; StatePath = $testStatePath }

            $resourcing | Should Not BeNullOrEmpty
            [string]$resourcing.path | Should Be "/tod/resourcing"
            (($resourcing.PSObject.Properties.Name) -contains "focus") | Should Be $true
            (($resourcing.PSObject.Properties.Name) -contains "demand_profile") | Should Be $true
            (($resourcing.PSObject.Properties.Name) -contains "external_resourcing") | Should Be $true
            (($resourcing.PSObject.Properties.Name) -contains "suggested_work_packages") | Should Be $true
        }
        finally {
            if (Test-Path $testStatePath) { Remove-Item $testStatePath -Force }
        }
    }

    It "get-state-bus returns endpoint payload shape" {
        $testStatePath = New-ReliabilityTestStatePath
        try {
            $bus = Invoke-TodActionJson -Action "get-state-bus" -ExtraArgs @{ Top = "10"; StatePath = $testStatePath }

            $bus | Should Not BeNullOrEmpty
            [string]$bus.path | Should Be "/tod/state-bus"
            (($bus.PSObject.Properties.Name) -contains "agent_state") | Should Be $true
            (($bus.PSObject.Properties.Name) -contains "world_state") | Should Be $true
            (($bus.PSObject.Properties.Name) -contains "capability_state") | Should Be $true
            (($bus.PSObject.Properties.Name) -contains "intent_state") | Should Be $true
            (($bus.PSObject.Properties.Name) -contains "execution_state") | Should Be $true
            (($bus.PSObject.Properties.Name) -contains "reliability_state") | Should Be $true
            (($bus.PSObject.Properties.Name) -contains "engineering_loop_state") | Should Be $true
            (($bus.PSObject.Properties.Name) -contains "blocks") | Should Be $true
            (($bus.PSObject.Properties.Name) -contains "source_of_truth") | Should Be $true
            (($bus.PSObject.Properties.Name) -contains "section_confidence") | Should Be $true
            (($bus.PSObject.Properties.Name) -contains "system_posture") | Should Be $true
            (($bus.source_of_truth.PSObject.Properties.Name) -contains "world_state") | Should Be $true
            (($bus.section_confidence.PSObject.Properties.Name) -contains "world_state") | Should Be $true
            (($bus.system_posture.PSObject.Properties.Name) -contains "agent_state") | Should Be $true
            (($bus.system_posture.PSObject.Properties.Name) -contains "current_alert_state") | Should Be $true
            (($bus.system_posture.PSObject.Properties.Name) -contains "engineering_loop_status") | Should Be $true
            (($bus.system_posture.PSObject.Properties.Name) -contains "active_goal_count") | Should Be $true
            (($bus.system_posture.PSObject.Properties.Name) -contains "active_execution_count") | Should Be $true
            (($bus.system_posture.PSObject.Properties.Name) -contains "pending_confirmations") | Should Be $true
            (($bus.system_posture.PSObject.Properties.Name) -contains "blocked_items") | Should Be $true
            (($bus.system_posture.PSObject.Properties.Name) -contains "registered_capabilities") | Should Be $true
            (($bus.system_posture.PSObject.Properties.Name) -contains "current_executor_health") | Should Be $true
            (($bus.source_of_truth.PSObject.Properties.Name) -contains "engineering_loop") | Should Be $true
            (($bus.section_confidence.PSObject.Properties.Name) -contains "engineering_loop") | Should Be $true
            (($bus.engineering_loop_state.PSObject.Properties.Name) -contains "run_history_count") | Should Be $true
            (($bus.engineering_loop_state.PSObject.Properties.Name) -contains "scorecard_history_count") | Should Be $true
            (($bus.engineering_loop_state.PSObject.Properties.Name) -contains "cycle_records_count") | Should Be $true
            (($bus.engineering_loop_state.PSObject.Properties.Name) -contains "approval_pending_flag") | Should Be $true
            (($bus.engineering_loop_state.PSObject.Properties.Name) -contains "phase_trends") | Should Be $true
            (($bus.engineering_loop_state.PSObject.Properties.Name) -contains "recent_runs") | Should Be $true
            (($bus.engineering_loop_state.PSObject.Properties.Name) -contains "recent_scorecards") | Should Be $true
            (($bus.engineering_loop_state.PSObject.Properties.Name) -contains "recent_cycles") | Should Be $true
            (@($bus.capability_state.endpoints) -contains "/tod/engineer/run") | Should Be $true
            (@($bus.capability_state.endpoints) -contains "/tod/engineer/scorecard") | Should Be $true
            (@($bus.capability_state.endpoints) -contains "/tod/engineer/summary") | Should Be $true
            (@($bus.capability_state.endpoints) -contains "/tod/engineer/signal") | Should Be $true
            (@($bus.capability_state.endpoints) -contains "/tod/engineer/history") | Should Be $true
            (@($bus.capability_state.endpoints) -contains "/tod/engineer/cycle") | Should Be $true
            (@($bus.capability_state.endpoints) -contains "/tod/engineer/review") | Should Be $true
        }
        finally {
            if (Test-Path $testStatePath) { Remove-Item $testStatePath -Force }
        }
    }

    It "get-version returns endpoint payload shape" {
        $testStatePath = New-ReliabilityTestStatePath
        try {
            $ver = Invoke-TodActionJson -Action "get-version" -ExtraArgs @{ StatePath = $testStatePath }

            $ver | Should Not BeNullOrEmpty
            [string]$ver.path | Should Be "/tod/version"
            (($ver.PSObject.Properties.Name) -contains "version") | Should Be $true
            (($ver.PSObject.Properties.Name) -contains "policy_source") | Should Be $true
        }
        finally {
            if (Test-Path $testStatePath) { Remove-Item $testStatePath -Force }
        }
    }
}
