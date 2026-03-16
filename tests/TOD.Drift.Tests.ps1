Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$todScript = Join-Path $repoRoot "scripts/TOD.ps1"
$baseConfigPath = Join-Path $repoRoot "tod/config/tod-config.json"

function New-DriftTestStatePath {
    $state = [pscustomobject]@{
        source = "tod-state-test-fixture-v1"
        updated_at = ""
        objectives = @(
            [pscustomobject]@{
                id = "75"
                title = "Objective 75 test fixture"
                status = "in_progress"
                constraints = @()
                success_criteria = @()
            }
        )
        tasks = @(
            [pscustomobject]@{
                id = "45"
                objective_id = "75"
                title = "Drift fixture task"
                type = "implementation"
                task_category = "refactor"
                assigned_executor = "codex"
                status = "pending"
                dependencies = @()
                acceptance_criteria = @()
            }
        )
        execution_results = @()
        review_decisions = @()
        journal = @()
        sync_state = [pscustomobject]@{ last_comparison = [pscustomobject]@{ status = "ok" } }
        engine_performance = [pscustomobject]@{ records = @(); updated_at = "" }
        routing_decisions = [pscustomobject]@{ records = @(); updated_at = "" }
    }

    $path = Join-Path $repoRoot ("tod/out/tests/drift-state-{0}.json" -f ([guid]::NewGuid().ToString("N")))
    $state | ConvertTo-Json -Depth 30 | Set-Content $path
    return $path
}

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

function Get-DriftTrendSnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$ConfigPath,
        [Parameter(Mandatory = $true)][string]$StatePath
    )

    $reliabilityRaw = & $todScript -Action "get-reliability" -Top 20 -ConfigPath $ConfigPath -Engine "codex" -StatePath $StatePath
    $reliability = $reliabilityRaw | ConvertFrom-Json
    return @($reliability.retry_trend | Select-Object -First 1)
}

function Set-ScenarioState {
    param(
        [Parameter(Mandatory = $true)]$StateObject,
        [Parameter(Mandatory = $true)][hashtable[]]$Recent,
        [Parameter(Mandatory = $true)][hashtable[]]$Baseline
    )

    $task = @($StateObject.tasks | Where-Object { [string]$_.id -eq "45" } | Select-Object -First 1)
    if (@($task).Count -eq 0) {
        throw "Task 45 not found in state; cannot run transition sanity scenario."
    }
    $task[0].task_category = "refactor"
    $StateObject.sync_state.last_comparison = [pscustomobject]@{ status = "ok" }

    $records = @()
    $now = Get-Date
    $idx = 1
    foreach ($r in $Recent) {
        $records += (New-PerfRecord -TaskId "45" -Engine "codex" -TaskCategory "refactor" -Success ([bool]$r.success) -RetryInflated ([bool]$r.retry) -FallbackApplied ([bool]$r.fallback) -ReviewDecision ([string]$r.review) -Index $idx)
        $idx++
    }
    foreach ($b in $Baseline) {
        $rec = New-PerfRecord -TaskId "45" -Engine "codex" -TaskCategory "refactor" -Success ([bool]$b.success) -RetryInflated ([bool]$b.retry) -FallbackApplied ([bool]$b.fallback) -ReviewDecision ([string]$b.review) -Index ($idx + 20)
        $records += $rec
        $idx++
    }

    $StateObject.engine_performance.records = @($records)
    $StateObject.engine_performance.updated_at = $now.ToUniversalTime().ToString("o")
    $StateObject.routing_decisions.records = @()
    $StateObject.routing_decisions.updated_at = $now.ToUniversalTime().ToString("o")
}

Describe "TOD Drift Penalties" {
    It "applies drift confidence penalty and emits warnings in reliability endpoint" {
        $cfgPath = New-DriftTestConfig
        $testStatePath = New-DriftTestStatePath
        try {
            $state = Get-Content $testStatePath -Raw | ConvertFrom-Json
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
            $state | ConvertTo-Json -Depth 30 | Set-Content $testStatePath

            $reliabilityRaw = & $todScript -Action "get-reliability" -Top 20 -ConfigPath $cfgPath -Engine "codex" -StatePath $testStatePath
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
            if (Test-Path $cfgPath) { Remove-Item $cfgPath -Force }
            if (Test-Path $testStatePath) { Remove-Item $testStatePath -Force }
        }
    }

    It "decays penalties when drift signals are old" {
        $cfgPath = New-DriftTestConfig
        $testStatePath = New-DriftTestStatePath
        try {
            $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
            $cfg.execution_engine.routing_policy.drift_detection.decay_half_life_days = 1
            $cfg.execution_engine.routing_policy.drift_detection.decay_floor = 0.1
            $cfg | ConvertTo-Json -Depth 30 | Set-Content $cfgPath

            $state = Get-Content $testStatePath -Raw | ConvertFrom-Json
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
            $state | ConvertTo-Json -Depth 30 | Set-Content $testStatePath

            $reliabilityRaw = & $todScript -Action "get-reliability" -Top 20 -ConfigPath $cfgPath -Engine "codex" -StatePath $testStatePath
            $reliability = $reliabilityRaw | ConvertFrom-Json
            $trend = @($reliability.retry_trend | Select-Object -First 1)

            @($trend).Count | Should BeGreaterThan 0
            [double]$trend[0].decay_factor | Should BeLessThan 1
            [double]$trend[0].signal_age_days | Should BeGreaterThan 1
            [double]$trend[0].confidence_penalty | Should BeGreaterThan 0
            [double]$trend[0].confidence_penalty | Should BeLessThan 0.6
        }
        finally {
            if (Test-Path $cfgPath) { Remove-Item $cfgPath -Force }
            if (Test-Path $testStatePath) { Remove-Item $testStatePath -Force }
        }
    }

    It "reports critical drift alert state for severe degradation" {
        $cfgPath = New-DriftTestConfig
        $testStatePath = New-DriftTestStatePath
        try {
            $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
            $cfg.execution_engine.routing_policy.drift_detection.guardrail_rate_threshold = 0.05
            $cfg | ConvertTo-Json -Depth 30 | Set-Content $cfgPath

            $state = Get-Content $testStatePath -Raw | ConvertFrom-Json
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
            $state | ConvertTo-Json -Depth 30 | Set-Content $testStatePath

            $reliabilityRaw = & $todScript -Action "get-reliability" -Top 20 -ConfigPath $cfgPath -Engine "codex" -StatePath $testStatePath
            $reliability = $reliabilityRaw | ConvertFrom-Json
            $trend = @($reliability.retry_trend | Select-Object -First 1)

            @($trend).Count | Should BeGreaterThan 0
            [string]$trend[0].alert_state | Should Be "critical"
        }
        finally {
            if (Test-Path $cfgPath) { Remove-Item $cfgPath -Force }
            if (Test-Path $testStatePath) { Remove-Item $testStatePath -Force }
        }
    }

    It "manual sanity transition follows stable-warning-degraded-warning-stable" {
        $cfgPath = New-DriftTestConfig
        $testStatePath = New-DriftTestStatePath
        try {
            $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
            $cfg.execution_engine.routing_policy.drift_detection.quarantine_enabled = $false
            $cfg.execution_engine.routing_policy.drift_detection.retry_rate_threshold = 0.25
            $cfg.execution_engine.routing_policy.drift_detection.engine_score_drop_threshold = 0.3
            $cfg | ConvertTo-Json -Depth 30 | Set-Content $cfgPath

            $stable = 1..10 | ForEach-Object { @{ success = $true; retry = $false; fallback = $false; review = "pass" } }
            $warning = @(@{ success = $false; retry = $false; fallback = $false; review = "escalate" }) + (1..9 | ForEach-Object { @{ success = $true; retry = $false; fallback = $false; review = "pass" } })
            $degraded = @(@{ success = $false; retry = $true; fallback = $false; review = "escalate" }, @{ success = $false; retry = $true; fallback = $false; review = "escalate" }) + (1..8 | ForEach-Object { @{ success = $true; retry = $true; fallback = $false; review = "pass" } })
            $recoveryWarning = (1..3 | ForEach-Object { @{ success = $true; retry = $true; fallback = $false; review = "pass" } }) + (1..7 | ForEach-Object { @{ success = $true; retry = $false; fallback = $false; review = "pass" } })
            $recoveryStable = 1..10 | ForEach-Object { @{ success = $true; retry = $false; fallback = $false; review = "pass" } }

            $state = Get-Content $testStatePath -Raw | ConvertFrom-Json
            Set-ScenarioState -StateObject $state -Recent $stable -Baseline $stable
            $state | ConvertTo-Json -Depth 30 | Set-Content $testStatePath
            $stableTrend = Get-DriftTrendSnapshot -ConfigPath $cfgPath -StatePath $testStatePath

            $state = Get-Content $testStatePath -Raw | ConvertFrom-Json
            Set-ScenarioState -StateObject $state -Recent $warning -Baseline $stable
            $state | ConvertTo-Json -Depth 30 | Set-Content $testStatePath
            $warningTrend = Get-DriftTrendSnapshot -ConfigPath $cfgPath -StatePath $testStatePath

            $state = Get-Content $testStatePath -Raw | ConvertFrom-Json
            Set-ScenarioState -StateObject $state -Recent $degraded -Baseline $warning
            $state | ConvertTo-Json -Depth 30 | Set-Content $testStatePath
            $degradedTrend = Get-DriftTrendSnapshot -ConfigPath $cfgPath -StatePath $testStatePath

            $state = Get-Content $testStatePath -Raw | ConvertFrom-Json
            Set-ScenarioState -StateObject $state -Recent $recoveryWarning -Baseline $degraded
            $state | ConvertTo-Json -Depth 30 | Set-Content $testStatePath
            $recoveryWarningTrend = Get-DriftTrendSnapshot -ConfigPath $cfgPath -StatePath $testStatePath

            $state = Get-Content $testStatePath -Raw | ConvertFrom-Json
            Set-ScenarioState -StateObject $state -Recent $recoveryStable -Baseline $recoveryWarning
            $state | ConvertTo-Json -Depth 30 | Set-Content $testStatePath
            $recoveryStableTrend = Get-DriftTrendSnapshot -ConfigPath $cfgPath -StatePath $testStatePath

            [string]$stableTrend[0].alert_state | Should Be "stable"
            [string]$warningTrend[0].alert_state | Should Be "warning"
            [string]$degradedTrend[0].alert_state | Should Be "degraded"
            [string]$recoveryWarningTrend[0].alert_state | Should Be "warning"
            [string]$recoveryStableTrend[0].alert_state | Should Be "stable"

            [double]$warningTrend[0].confidence_penalty | Should BeGreaterThan 0
            [double]$degradedTrend[0].confidence_penalty | Should BeGreaterThan ([double]$warningTrend[0].confidence_penalty)
            [double]$recoveryWarningTrend[0].confidence_penalty | Should BeLessThan ([double]$degradedTrend[0].confidence_penalty)
            [double]$recoveryStableTrend[0].confidence_penalty | Should Be 0
        }
        finally {
            if (Test-Path $cfgPath) { Remove-Item $cfgPath -Force }
            if (Test-Path $testStatePath) { Remove-Item $testStatePath -Force }
        }
    }
}
