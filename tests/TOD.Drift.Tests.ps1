Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$todScript = Join-Path $repoRoot "scripts/TOD.ps1"
$baseConfigPath = Join-Path $repoRoot "tod/config/tod-config.json"
$statePath = Join-Path $repoRoot "tod/data/state.json"

function New-DriftTestConfig {
    $cfg = Get-Content $baseConfigPath -Raw | ConvertFrom-Json
    $cfg.mode = "local"
    $cfg.execution_engine.active = "codex"
    $cfg.execution_engine.fallback = "codex"
    $cfg.execution_engine.allow_fallback = $true
    $cfg.execution_engine.routing_policy.enabled = $true
    $cfg.execution_engine.routing_policy.allow_placeholder_for_code_change = $true

    $cfg.execution_engine.routing_policy.drift_detection.enabled = $true
    $cfg.execution_engine.routing_policy.drift_detection.recent_window = 10
    $cfg.execution_engine.routing_policy.drift_detection.baseline_window = 20
    $cfg.execution_engine.routing_policy.drift_detection.minimum_baseline_records = 10
    $cfg.execution_engine.routing_policy.drift_detection.failure_rate_multiplier = 1.2
    $cfg.execution_engine.routing_policy.drift_detection.retry_rate_threshold = 0.25
    $cfg.execution_engine.routing_policy.drift_detection.fallback_rate_multiplier = 1.2
    $cfg.execution_engine.routing_policy.drift_detection.fallback_rate_threshold = 0.25
    $cfg.execution_engine.routing_policy.drift_detection.engine_score_drop_threshold = 0.1
    $cfg.execution_engine.routing_policy.drift_detection.decay_half_life_days = 7
    $cfg.execution_engine.routing_policy.drift_detection.decay_floor = 0.25

    $tempPath = Join-Path $repoRoot ("tod/config/tod-config.test-drift-{0}.json" -f ([guid]::NewGuid().ToString("N")))
    $cfg | ConvertTo-Json -Depth 30 | Set-Content $tempPath
    return $tempPath
}

function New-PerfRecord {
    param(
        [string]$TaskId,
        [string]$Engine,
        [string]$TaskCategory,
        [bool]$Success,
        [bool]$RetryInflated,
        [bool]$FallbackApplied,
        [string]$ReviewDecision,
        [int]$Index
    )

    return [pscustomobject]@{
        id = "DRIFT-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 8).ToUpperInvariant())
        task_id = $TaskId
        engine = $Engine
        task_type = "implementation"
        task_category = $TaskCategory
        fallback_applied = $FallbackApplied
        attempted_engines = @($Engine)
        attempts_count = if ($RetryInflated) { 2 } else { 1 }
        retry_inflated = $RetryInflated
        result_status = if ($Success) { "completed" } else { "failed" }
        needs_escalation = (-not $Success)
        failure_category = if ($Success) { "none" } else { "status" }
        review_decision = $ReviewDecision
        success = $Success
        recovered_on_retry = ($Success -and $RetryInflated -and (-not $FallbackApplied))
        recovered_on_fallback = ($Success -and $FallbackApplied)
        manual_intervention_required = (-not $Success)
        review_score = if ($Success) { 1.0 } else { 0.0 }
        latency_ms = 100
        files_involved = @()
        modules_involved = @()
        created_at = (Get-Date).ToUniversalTime().AddMinutes(-1 * $Index).ToString("o")
    }
}

Describe "TOD Drift Penalties" {
    It "applies drift confidence penalty and emits warnings in reliability endpoint" {
        $originalState = Get-Content $statePath -Raw
        $cfgPath = New-DriftTestConfig
        try {
            $state = $originalState | ConvertFrom-Json
            $task = @($state.tasks | Where-Object { [string]$_.id -eq "45" } | Select-Object -First 1)
            if (@($task).Count -eq 0) {
                throw "Task 45 not found in state; cannot run drift test."
            }
            $task[0].task_category = "refactor"
            $state.sync_state.last_comparison = [pscustomobject]@{ status = "ok" }

            $records = @()
            for ($i = 1; $i -le 10; $i++) {
                $records += (New-PerfRecord -TaskId "45" -Engine "codex" -TaskCategory "refactor" -Success $false -RetryInflated $true -FallbackApplied $true -ReviewDecision "escalate" -Index $i)
            }
            for ($i = 11; $i -le 20; $i++) {
                $records += (New-PerfRecord -TaskId "45" -Engine "codex" -TaskCategory "refactor" -Success $true -RetryInflated $false -FallbackApplied $false -ReviewDecision "pass" -Index $i)
            }
            $state.engine_performance.records = @($records)
            $state.engine_performance.updated_at = (Get-Date).ToUniversalTime().ToString("o")
            $state.routing_decisions.records = @()
            $state.routing_decisions.updated_at = (Get-Date).ToUniversalTime().ToString("o")
            $state | ConvertTo-Json -Depth 30 | Set-Content $statePath

            $null = & $todScript -Action "run-task" -TaskId "45" -ConfigPath $cfgPath

            $reliabilityRaw = & $todScript -Action "get-reliability" -Top 20 -ConfigPath $cfgPath -Engine "codex"
            $reliability = $reliabilityRaw | ConvertFrom-Json
            @($reliability.drift_warnings).Count | Should BeGreaterThan 0
            $trend = @($reliability.retry_trend | Select-Object -First 1)
            @($trend).Count | Should BeGreaterThan 0
            [double]$trend[0].confidence_penalty | Should BeGreaterThan 0
            [double]$trend[0].score_penalty | Should BeGreaterThan 0
            [double]$trend[0].decay_factor | Should BeGreaterThan 0
            ([string]$trend[0].alert_state).Length | Should BeGreaterThan 0
        }
        finally {
            $originalState | Set-Content $statePath
            if (Test-Path $cfgPath) { Remove-Item $cfgPath -Force }
        }
    }

    It "decays penalties when drift signals are old" {
        $originalState = Get-Content $statePath -Raw
        $cfgPath = New-DriftTestConfig
        try {
            $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
            $cfg.execution_engine.routing_policy.drift_detection.decay_half_life_days = 1
            $cfg.execution_engine.routing_policy.drift_detection.decay_floor = 0.1
            $cfg | ConvertTo-Json -Depth 30 | Set-Content $cfgPath

            $state = $originalState | ConvertFrom-Json
            $task = @($state.tasks | Where-Object { [string]$_.id -eq "45" } | Select-Object -First 1)
            if (@($task).Count -eq 0) {
                throw "Task 45 not found in state; cannot run drift decay test."
            }
            $task[0].task_category = "refactor"
            $state.sync_state.last_comparison = [pscustomobject]@{ status = "ok" }

            $records = @()
            for ($i = 1; $i -le 10; $i++) {
                $r = New-PerfRecord -TaskId "45" -Engine "codex" -TaskCategory "refactor" -Success $false -RetryInflated $true -FallbackApplied $true -ReviewDecision "escalate" -Index $i
                $r.created_at = (Get-Date).ToUniversalTime().AddDays(-10).AddMinutes(-1 * $i).ToString("o")
                $records += $r
            }
            for ($i = 11; $i -le 20; $i++) {
                $r = New-PerfRecord -TaskId "45" -Engine "codex" -TaskCategory "refactor" -Success $true -RetryInflated $false -FallbackApplied $false -ReviewDecision "pass" -Index $i
                $r.created_at = (Get-Date).ToUniversalTime().AddDays(-10).AddMinutes(-1 * $i).ToString("o")
                $records += $r
            }

            $state.engine_performance.records = @($records)
            $state.engine_performance.updated_at = (Get-Date).ToUniversalTime().AddDays(-10).ToString("o")
            $state.routing_decisions.records = @()
            $state.routing_decisions.updated_at = (Get-Date).ToUniversalTime().AddDays(-10).ToString("o")
            $state | ConvertTo-Json -Depth 30 | Set-Content $statePath

            $reliabilityRaw = & $todScript -Action "get-reliability" -Top 20 -ConfigPath $cfgPath -Engine "codex"
            $reliability = $reliabilityRaw | ConvertFrom-Json
            $trend = @($reliability.retry_trend | Select-Object -First 1)

            @($trend).Count | Should BeGreaterThan 0
            [double]$trend[0].decay_factor | Should BeLessThan 1
            [double]$trend[0].signal_age_days | Should BeGreaterThan 1
            [double]$trend[0].confidence_penalty | Should BeGreaterThan 0
            [double]$trend[0].confidence_penalty | Should BeLessThan 0.6
        }
        finally {
            $originalState | Set-Content $statePath
            if (Test-Path $cfgPath) { Remove-Item $cfgPath -Force }
        }
    }

    It "reports critical drift alert state for severe degradation" {
        $originalState = Get-Content $statePath -Raw
        $cfgPath = New-DriftTestConfig
        try {
            $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
            $cfg.execution_engine.routing_policy.drift_detection.guardrail_rate_threshold = 0.05
            $cfg | ConvertTo-Json -Depth 30 | Set-Content $cfgPath

            $state = $originalState | ConvertFrom-Json
            $task = @($state.tasks | Where-Object { [string]$_.id -eq "45" } | Select-Object -First 1)
            if (@($task).Count -eq 0) {
                throw "Task 45 not found in state; cannot run drift quarantine test."
            }
            $task[0].task_category = "refactor"
            $state.sync_state.last_comparison = [pscustomobject]@{ status = "ok" }

            $records = @()
            for ($i = 1; $i -le 12; $i++) {
                $records += (New-PerfRecord -TaskId "45" -Engine "codex" -TaskCategory "refactor" -Success $false -RetryInflated $true -FallbackApplied $true -ReviewDecision "escalate" -Index $i)
            }
            for ($i = 13; $i -le 24; $i++) {
                $records += (New-PerfRecord -TaskId "45" -Engine "codex" -TaskCategory "refactor" -Success $true -RetryInflated $false -FallbackApplied $false -ReviewDecision "pass" -Index $i)
            }

            $state.engine_performance.records = @($records)
            $state.engine_performance.updated_at = (Get-Date).ToUniversalTime().ToString("o")
            $state.routing_decisions.records = @(
                [pscustomobject]@{ id = "R1"; task_id = "45"; task_category = "refactor"; selected_engine = "codex"; final_outcome = "blocked_pre_invocation"; created_at = (Get-Date).ToUniversalTime().AddMinutes(-1).ToString("o") },
                [pscustomobject]@{ id = "R2"; task_id = "45"; task_category = "refactor"; selected_engine = "codex"; final_outcome = "blocked_pre_invocation"; created_at = (Get-Date).ToUniversalTime().AddMinutes(-2).ToString("o") },
                [pscustomobject]@{ id = "R3"; task_id = "45"; task_category = "refactor"; selected_engine = "codex"; final_outcome = "pass"; created_at = (Get-Date).ToUniversalTime().AddMinutes(-20).ToString("o") }
            )
            $state.routing_decisions.updated_at = (Get-Date).ToUniversalTime().ToString("o")
            $state | ConvertTo-Json -Depth 30 | Set-Content $statePath

            $reliabilityRaw = & $todScript -Action "get-reliability" -Top 20 -ConfigPath $cfgPath -Engine "codex"
            $reliability = $reliabilityRaw | ConvertFrom-Json
            $trend = @($reliability.retry_trend | Select-Object -First 1)

            @($trend).Count | Should BeGreaterThan 0
            [string]$trend[0].alert_state | Should Be "critical"
        }
        finally {
            $originalState | Set-Content $statePath
            if (Test-Path $cfgPath) { Remove-Item $cfgPath -Force }
        }
    }
}
