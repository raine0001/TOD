Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$todScript = Join-Path $repoRoot "scripts/TOD.ps1"
$baseConfigPath = Join-Path $repoRoot "tod/config/tod-config.json"

function New-GuardrailTestStatePath {
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
                title = "Guardrail fixture task"
                type = "implementation"
                task_category = "code_change"
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

    $path = Join-Path $repoRoot ("tod/out/tests/guardrails-state-{0}.json" -f ([guid]::NewGuid().ToString("N")))
    $state | ConvertTo-Json -Depth 30 | Set-Content $path
    return $path
}

function Invoke-TodRunTaskJson {
    param(
        [Parameter(Mandatory = $true)][string]$ConfigPath,
        [Parameter(Mandatory = $true)][string]$TaskId,
        [Parameter(Mandatory = $true)][string]$StatePath
    )

    $raw = & $todScript -Action "run-task" -TaskId $TaskId -ConfigPath $ConfigPath -StatePath $StatePath
    return ($raw | ConvertFrom-Json)
}

function New-GuardrailTestConfig {
    param(
        [Parameter(Mandatory = $true)][int]$RecentFailureThreshold
    )

    $cfg = Get-Content $baseConfigPath -Raw | ConvertFrom-Json
    $cfg.mode = "local"
    $cfg.execution_engine.active = "codex"
    $cfg.execution_engine.fallback = "local"
    $cfg.execution_engine.allow_fallback = $true
    $cfg.execution_engine.routing_policy.enabled = $true
    $cfg.execution_engine.routing_policy.allow_placeholder_for_code_change = $false
    $cfg.execution_engine.routing_policy.recent_failure_window = 5
    $cfg.execution_engine.routing_policy.recent_failure_threshold = $RecentFailureThreshold

    $tempPath = Join-Path $repoRoot ("tod/config/tod-config.test-guardrails-{0}.json" -f ([guid]::NewGuid().ToString("N")))
    $cfg | ConvertTo-Json -Depth 20 | Set-Content $tempPath
    return $tempPath
}

function New-PerfRecord {
    param(
        [string]$TaskId,
        [string]$Engine,
        [string]$TaskCategory,
        [bool]$Success
    )

    return [pscustomobject]@{
        id = "TEST-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 8).ToUpperInvariant())
        task_id = $TaskId
        engine = $Engine
        task_type = "implementation"
        task_category = $TaskCategory
        fallback_applied = $false
        attempted_engines = @($Engine)
        result_status = if ($Success) { "completed" } else { "failed" }
        needs_escalation = (-not $Success)
        failure_category = if ($Success) { "none" } else { "status" }
        review_decision = if ($Success) { "pass" } else { "escalate" }
        success = $Success
        review_score = if ($Success) { 1.0 } else { 0.0 }
        latency_ms = 50
        files_involved = @()
        modules_involved = @()
        created_at = (Get-Date).ToUniversalTime().ToString("o")
    }
}

Describe "TOD Guardrail Scenarios" {
    It "blocks run-task when sync status is breaking" {
        $cfgPath = New-GuardrailTestConfig -RecentFailureThreshold 2
        $testStatePath = New-GuardrailTestStatePath
        try {
            $state = Get-Content $testStatePath -Raw | ConvertFrom-Json
            if (-not $state.PSObject.Properties["sync_state"] -or $null -eq $state.sync_state) {
                $state | Add-Member -NotePropertyName sync_state -NotePropertyValue ([pscustomobject]@{}) -Force
            }
            $state.sync_state.last_comparison = [pscustomobject]@{ status = "breaking" }
            $state | ConvertTo-Json -Depth 20 | Set-Content $testStatePath

            $result = Invoke-TodRunTaskJson -ConfigPath $cfgPath -TaskId "45" -StatePath $testStatePath
            ([bool]$result.blocked) | Should Be $true
            ([string]$result.routing_decision.routing.reason -eq "contract_drift_breaking") | Should Be $true
        }
        finally {
            if (Test-Path $cfgPath) { Remove-Item $cfgPath -Force }
            if (Test-Path $testStatePath) { Remove-Item $testStatePath -Force }
        }
    }

    It "blocks run-task when all candidate engines are guardrail-blocked" {
        $cfgPath = New-GuardrailTestConfig -RecentFailureThreshold 1
        $testStatePath = New-GuardrailTestStatePath
        try {
            $state = Get-Content $testStatePath -Raw | ConvertFrom-Json
            $state.sync_state.last_comparison = [pscustomobject]@{ status = "ok" }

            $task = @($state.tasks | Where-Object { [string]$_.id -eq "45" } | Select-Object -First 1)
            if (@($task).Count -eq 0) {
                throw "Task 45 not found in state; cannot run guardrail scenario test."
            }
            $task[0].task_category = "code_change"

            $state.engine_performance.records = @(
                (New-PerfRecord -TaskId "45" -Engine "codex" -TaskCategory "code_change" -Success $false),
                (New-PerfRecord -TaskId "45" -Engine "local" -TaskCategory "code_change" -Success $false)
            )

            $state | ConvertTo-Json -Depth 20 | Set-Content $testStatePath

            $result = Invoke-TodRunTaskJson -ConfigPath $cfgPath -TaskId "45" -StatePath $testStatePath
            ([bool]$result.blocked) | Should Be $true
            ([string]$result.routing_decision.routing.reason -eq "guardrail_all_candidates_blocked") | Should Be $true
        }
        finally {
            if (Test-Path $cfgPath) { Remove-Item $cfgPath -Force }
            if (Test-Path $testStatePath) { Remove-Item $testStatePath -Force }
        }
    }
}
