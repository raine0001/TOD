Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$todScript = Join-Path $repoRoot "scripts/TOD.ps1"
$configPath = Join-Path $repoRoot "tod/config/tod-config.json"
$statePath = Join-Path $repoRoot "tod/data/state.json"

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
        (($payload.PSObject.Properties.Name) -contains "current_alert_state") | Should Be $true
        (($payload.PSObject.Properties.Name) -contains "drift_penalties_active") | Should Be $true
        (($payload.PSObject.Properties.Name) -contains "recovery_state") | Should Be $true
        (($payload.PSObject.Properties.Name) -contains "engine_reliability_score") | Should Be $true
        (($payload.PSObject.Properties.Name) -contains "retry_trend") | Should Be $true
        (($payload.PSObject.Properties.Name) -contains "guardrail_trend") | Should Be $true
        (($payload.PSObject.Properties.Name) -contains "drift_warnings") | Should Be $true
    }

    It "get-capabilities returns endpoint payload shape" {
        $caps = Invoke-TodActionJson -Action "get-capabilities"

        $caps | Should Not BeNullOrEmpty
        [string]$caps.path | Should Be "/tod/capabilities"
        (($caps.PSObject.Properties.Name) -contains "execution") | Should Be $true
        (($caps.PSObject.Properties.Name) -contains "reliability") | Should Be $true
        (($caps.PSObject.Properties.Name) -contains "research") | Should Be $true
        (($caps.PSObject.Properties.Name) -contains "resourcing") | Should Be $true
        (($caps.PSObject.Properties.Name) -contains "code_write_sandbox") | Should Be $true
        (($caps.PSObject.Properties.Name) -contains "endpoints") | Should Be $true
        (@($caps.endpoints) -contains "/tod/state-bus") | Should Be $true
        (@($caps.endpoints) -contains "/tod/research") | Should Be $true
        (@($caps.endpoints) -contains "/tod/resourcing") | Should Be $true
        (@($caps.endpoints) -contains "/tod/engineer/run") | Should Be $true
        (@($caps.endpoints) -contains "/tod/engineer/scorecard") | Should Be $true
        (@($caps.endpoints) -contains "/tod/sandbox/files") | Should Be $true
        (@($caps.endpoints) -contains "/tod/sandbox/plan") | Should Be $true
        (@($caps.endpoints) -contains "/tod/sandbox/apply") | Should Be $true
        (@($caps.endpoints) -contains "/tod/sandbox/write") | Should Be $true
    }

    It "engineer-run returns orchestration payload with plan artifact" {
        $run = Invoke-TodActionJson -Action "engineer-run" -ExtraArgs @{ Top = "10" }

        $run | Should Not BeNullOrEmpty
        [string]$run.path | Should Be "/tod/engineer/run"
        (($run.PSObject.Properties.Name) -contains "run_id") | Should Be $true
        (($run.PSObject.Properties.Name) -contains "focus") | Should Be $true
        (($run.PSObject.Properties.Name) -contains "phases") | Should Be $true
        (($run.phases.PSObject.Properties.Name) -contains "plan") | Should Be $true

        $artifactPath = Join-Path $repoRoot ([string]$run.phases.plan.artifact_path -replace "/", "\\")
        (Test-Path $artifactPath) | Should Be $true

        $bus = Invoke-TodActionJson -Action "get-state-bus" -ExtraArgs @{ Top = "10" }
        (($bus.PSObject.Properties.Name) -contains "engineering_loop_state") | Should Be $true
        ([int]$bus.engineering_loop_state.run_history_count) | Should BeGreaterThan 0
    }

    It "engineer-scorecard returns maturity dimensions" {
        $scorecard = Invoke-TodActionJson -Action "engineer-scorecard" -ExtraArgs @{ Top = "25" }

        $scorecard | Should Not BeNullOrEmpty
        [string]$scorecard.path | Should Be "/tod/engineer/scorecard"
        (($scorecard.PSObject.Properties.Name) -contains "overall") | Should Be $true
        (($scorecard.PSObject.Properties.Name) -contains "dimensions") | Should Be $true
        (@($scorecard.dimensions).Count -ge 5) | Should Be $true

        $bus = Invoke-TodActionJson -Action "get-state-bus" -ExtraArgs @{ Top = "10" }
        (($bus.PSObject.Properties.Name) -contains "engineering_loop_state") | Should Be $true
        ([int]$bus.engineering_loop_state.scorecard_history_count) | Should BeGreaterThan 0
    }

    It "engineering loop scorecard trend direction is flat for low delta" {
        $originalStateRaw = Get-Content -Path $statePath -Raw
        try {
            $state = $originalStateRaw | ConvertFrom-Json

            if (-not $state.PSObject.Properties["engineering_loop"] -or $null -eq $state.engineering_loop) {
                $state | Add-Member -NotePropertyName engineering_loop -NotePropertyValue ([pscustomobject]@{
                        run_history = @()
                        scorecard_history = @()
                        last_run = $null
                        last_scorecard = $null
                        updated_at = ""
                    }) -Force
            }
            if (-not $state.engineering_loop.PSObject.Properties["run_history"]) {
                $state.engineering_loop | Add-Member -NotePropertyName run_history -NotePropertyValue @() -Force
            }
            if (-not $state.engineering_loop.PSObject.Properties["scorecard_history"]) {
                $state.engineering_loop | Add-Member -NotePropertyName scorecard_history -NotePropertyValue @() -Force
            }

            $base = (Get-Date).ToUniversalTime().AddMinutes(-2)
            $rows = @(
                [pscustomobject]@{ generated_at = $base.ToString("o"); window = 25; score = 0.50; band = "test"; low_areas = @() },
                [pscustomobject]@{ generated_at = $base.AddMinutes(1).ToString("o"); window = 25; score = 0.51; band = "test"; low_areas = @() }
            )

            $state.engineering_loop.scorecard_history = @($rows)
            $state.engineering_loop.last_scorecard = $rows[1]
            $state.engineering_loop.updated_at = (Get-Date).ToUniversalTime().ToString("o")
            ($state | ConvertTo-Json -Depth 24) | Set-Content -Path $statePath

            $flatBus = Invoke-TodActionJson -Action "get-state-bus" -ExtraArgs @{ Top = "10" }
            [string]$flatBus.engineering_loop_state.trend_direction | Should Be "flat"
        }
        finally {
            Set-Content -Path $statePath -Value $originalStateRaw
        }
    }

    It "engineering loop scorecard trend direction is improving for positive delta" {
        $originalStateRaw = Get-Content -Path $statePath -Raw
        try {
            $state = $originalStateRaw | ConvertFrom-Json

            if (-not $state.PSObject.Properties["engineering_loop"] -or $null -eq $state.engineering_loop) {
                $state | Add-Member -NotePropertyName engineering_loop -NotePropertyValue ([pscustomobject]@{
                        run_history = @()
                        scorecard_history = @()
                        last_run = $null
                        last_scorecard = $null
                        updated_at = ""
                    }) -Force
            }
            if (-not $state.engineering_loop.PSObject.Properties["run_history"]) {
                $state.engineering_loop | Add-Member -NotePropertyName run_history -NotePropertyValue @() -Force
            }
            if (-not $state.engineering_loop.PSObject.Properties["scorecard_history"]) {
                $state.engineering_loop | Add-Member -NotePropertyName scorecard_history -NotePropertyValue @() -Force
            }

            $base = (Get-Date).ToUniversalTime().AddMinutes(-2)
            $rows = @(
                [pscustomobject]@{ generated_at = $base.ToString("o"); window = 25; score = 0.40; band = "test"; low_areas = @() },
                [pscustomobject]@{ generated_at = $base.AddMinutes(1).ToString("o"); window = 25; score = 0.52; band = "test"; low_areas = @() }
            )

            $state.engineering_loop.scorecard_history = @($rows)
            $state.engineering_loop.last_scorecard = $rows[1]
            $state.engineering_loop.updated_at = (Get-Date).ToUniversalTime().ToString("o")
            ($state | ConvertTo-Json -Depth 24) | Set-Content -Path $statePath

            $improvingBus = Invoke-TodActionJson -Action "get-state-bus" -ExtraArgs @{ Top = "10" }
            [string]$improvingBus.engineering_loop_state.trend_direction | Should Be "improving"
        }
        finally {
            Set-Content -Path $statePath -Value $originalStateRaw
        }
    }

    It "engineering loop scorecard trend direction is declining for negative delta" {
        $originalStateRaw = Get-Content -Path $statePath -Raw
        try {
            $state = $originalStateRaw | ConvertFrom-Json

            if (-not $state.PSObject.Properties["engineering_loop"] -or $null -eq $state.engineering_loop) {
                $state | Add-Member -NotePropertyName engineering_loop -NotePropertyValue ([pscustomobject]@{
                        run_history = @()
                        scorecard_history = @()
                        last_run = $null
                        last_scorecard = $null
                        updated_at = ""
                    }) -Force
            }
            if (-not $state.engineering_loop.PSObject.Properties["run_history"]) {
                $state.engineering_loop | Add-Member -NotePropertyName run_history -NotePropertyValue @() -Force
            }
            if (-not $state.engineering_loop.PSObject.Properties["scorecard_history"]) {
                $state.engineering_loop | Add-Member -NotePropertyName scorecard_history -NotePropertyValue @() -Force
            }

            $base = (Get-Date).ToUniversalTime().AddMinutes(-2)
            $rows = @(
                [pscustomobject]@{ generated_at = $base.ToString("o"); window = 25; score = 0.78; band = "test"; low_areas = @() },
                [pscustomobject]@{ generated_at = $base.AddMinutes(1).ToString("o"); window = 25; score = 0.60; band = "test"; low_areas = @() }
            )

            $state.engineering_loop.scorecard_history = @($rows)
            $state.engineering_loop.last_scorecard = $rows[1]
            $state.engineering_loop.updated_at = (Get-Date).ToUniversalTime().ToString("o")
            ($state | ConvertTo-Json -Depth 24) | Set-Content -Path $statePath

            $decliningBus = Invoke-TodActionJson -Action "get-state-bus" -ExtraArgs @{ Top = "10" }
            [string]$decliningBus.engineering_loop_state.trend_direction | Should Be "declining"
        }
        finally {
            Set-Content -Path $statePath -Value $originalStateRaw
        }
    }

    It "engineering loop run history enforces minimum retention floor of 10" {
        $originalStateRaw = Get-Content -Path $statePath -Raw
        $tmpConfigPath = Join-Path $repoRoot ("tod/config/tod-config.test-retention-floor-{0}.json" -f ([guid]::NewGuid().ToString("N")))
        try {
            $cfg = (Get-Content -Path $configPath -Raw) | ConvertFrom-Json
            if (-not $cfg.PSObject.Properties["engineering_loop"] -or $null -eq $cfg.engineering_loop) {
                $cfg | Add-Member -NotePropertyName engineering_loop -NotePropertyValue ([pscustomobject]@{}) -Force
            }
            $cfg.engineering_loop.max_run_history = 1
            $cfg.engineering_loop.max_scorecard_history = 150
            ($cfg | ConvertTo-Json -Depth 24) | Set-Content -Path $tmpConfigPath

            $state = $originalStateRaw | ConvertFrom-Json
            if (-not $state.PSObject.Properties["engineering_loop"] -or $null -eq $state.engineering_loop) {
                $state | Add-Member -NotePropertyName engineering_loop -NotePropertyValue ([pscustomobject]@{
                        run_history = @()
                        scorecard_history = @()
                        last_run = $null
                        last_scorecard = $null
                        updated_at = ""
                    }) -Force
            }
            $state.engineering_loop.run_history = @()
            $state.engineering_loop.last_run = $null
            ($state | ConvertTo-Json -Depth 24) | Set-Content -Path $statePath

            for ($i = 0; $i -lt 12; $i++) {
                $null = Invoke-TodActionJson -Action "engineer-run" -ExtraArgs @{ Top = "5"; ConfigPath = $tmpConfigPath }
            }

            $bus = Invoke-TodActionJson -Action "get-state-bus" -ExtraArgs @{ Top = "10"; ConfigPath = $tmpConfigPath }
            [int]$bus.engineering_loop_state.run_history_count | Should Be 10
        }
        finally {
            Set-Content -Path $statePath -Value $originalStateRaw
            if (Test-Path -Path $tmpConfigPath) {
                Remove-Item -Path $tmpConfigPath -Force
            }
        }
    }

    It "engineering loop scorecard history enforces maximum retention clamp of 1000" {
        $originalStateRaw = Get-Content -Path $statePath -Raw
        $tmpConfigPath = Join-Path $repoRoot ("tod/config/tod-config.test-retention-ceiling-{0}.json" -f ([guid]::NewGuid().ToString("N")))
        try {
            $cfg = (Get-Content -Path $configPath -Raw) | ConvertFrom-Json
            if (-not $cfg.PSObject.Properties["engineering_loop"] -or $null -eq $cfg.engineering_loop) {
                $cfg | Add-Member -NotePropertyName engineering_loop -NotePropertyValue ([pscustomobject]@{}) -Force
            }
            $cfg.engineering_loop.max_run_history = 150
            $cfg.engineering_loop.max_scorecard_history = 5000
            ($cfg | ConvertTo-Json -Depth 24) | Set-Content -Path $tmpConfigPath

            $state = $originalStateRaw | ConvertFrom-Json
            if (-not $state.PSObject.Properties["engineering_loop"] -or $null -eq $state.engineering_loop) {
                $state | Add-Member -NotePropertyName engineering_loop -NotePropertyValue ([pscustomobject]@{
                        run_history = @()
                        scorecard_history = @()
                        last_run = $null
                        last_scorecard = $null
                        updated_at = ""
                    }) -Force
            }

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
            ($state | ConvertTo-Json -Depth 24) | Set-Content -Path $statePath

            $null = Invoke-TodActionJson -Action "engineer-scorecard" -ExtraArgs @{ Top = "5"; ConfigPath = $tmpConfigPath }
            $bus = Invoke-TodActionJson -Action "get-state-bus" -ExtraArgs @{ Top = "10"; ConfigPath = $tmpConfigPath }
            [int]$bus.engineering_loop_state.scorecard_history_count | Should Be 1000
        }
        finally {
            Set-Content -Path $statePath -Value $originalStateRaw
            if (Test-Path -Path $tmpConfigPath) {
                Remove-Item -Path $tmpConfigPath -Force
            }
        }
    }

    It "sandbox-write and sandbox-list return endpoint payload shape" {
        $sandboxRelPath = "selftest/tod-sandbox-test.txt"
        $sandboxBody = "sandbox smoke write"

        $write = Invoke-TodActionJson -Action "sandbox-write" -ExtraArgs @{ SandboxPath = $sandboxRelPath; Content = $sandboxBody }
        $list = Invoke-TodActionJson -Action "sandbox-list" -ExtraArgs @{ Top = "25" }

        [string]$write.path | Should Be "/tod/sandbox/write"
        (($write.PSObject.Properties.Name) -contains "sandbox_path") | Should Be $true
        (($write.PSObject.Properties.Name) -contains "sha256") | Should Be $true
        [string]$list.path | Should Be "/tod/sandbox/files"
        (($list.PSObject.Properties.Name) -contains "files") | Should Be $true

        $normalizedRel = ($sandboxRelPath -replace "\\", "/")
        $paths = @($list.files | ForEach-Object { [string]$_.path })
        ($paths -contains $normalizedRel) | Should Be $true
    }

    It "sandbox-plan returns non-destructive diff artifact payload" {
        $sandboxRelPath = "selftest/tod-sandbox-plan.txt"
        $sandboxBody = "planned-only body"
        $sandboxTarget = Join-Path $repoRoot ("tod/sandbox/workspace/" + ($sandboxRelPath -replace "/", "\\"))

        if (Test-Path $sandboxTarget) {
            Remove-Item -Path $sandboxTarget -Force
        }

        $plan = Invoke-TodActionJson -Action "sandbox-plan" -ExtraArgs @{ SandboxPath = $sandboxRelPath; Content = $sandboxBody }

        [string]$plan.path | Should Be "/tod/sandbox/plan"
        ([bool]$plan.will_create) | Should Be $true
        (($plan.PSObject.Properties.Name) -contains "diff_preview") | Should Be $true
        (($plan.PSObject.Properties.Name) -contains "artifact_path") | Should Be $true
        ((Test-Path $sandboxTarget) -eq $false) | Should Be $true

        $artifactPath = Join-Path $repoRoot ([string]$plan.artifact_path -replace "/", "\\")
        (Test-Path $artifactPath) | Should Be $true
    }

    It "sandbox-apply-plan writes planned content with hash integrity" {
        $sandboxRelPath = "selftest/tod-sandbox-apply.txt"
        $initialBody = "initial"
        $plannedBody = "planned content v2"

        $null = Invoke-TodActionJson -Action "sandbox-write" -ExtraArgs @{ SandboxPath = $sandboxRelPath; Content = $initialBody }
        $plan = Invoke-TodActionJson -Action "sandbox-plan" -ExtraArgs @{ SandboxPath = $sandboxRelPath; Content = $plannedBody }
        $apply = Invoke-TodActionJson -Action "sandbox-apply-plan" -ExtraArgs @{ SandboxPlanPath = [string]$plan.artifact_path }

        [string]$apply.path | Should Be "/tod/sandbox/apply"
        ([bool]$apply.applied) | Should Be $true
        (($apply.PSObject.Properties.Name) -contains "sha256") | Should Be $true

        $sandboxTarget = Join-Path $repoRoot ("tod/sandbox/workspace/" + ($sandboxRelPath -replace "/", "\\"))
        (Test-Path $sandboxTarget) | Should Be $true
        ([string](Get-Content -Path $sandboxTarget -Raw)).Trim() | Should Be $plannedBody
    }

    It "get-research returns endpoint payload shape" {
        $research = Invoke-TodActionJson -Action "get-research" -ExtraArgs @{ Top = "10" }

        $research | Should Not BeNullOrEmpty
        [string]$research.path | Should Be "/tod/research"
        (($research.PSObject.Properties.Name) -contains "repository") | Should Be $true
        (($research.PSObject.Properties.Name) -contains "active_context") | Should Be $true
        (($research.PSObject.Properties.Name) -contains "exploration") | Should Be $true
    }

    It "get-resourcing returns endpoint payload shape" {
        $resourcing = Invoke-TodActionJson -Action "get-resourcing" -ExtraArgs @{ Top = "10"; ObjectiveId = "16" }

        $resourcing | Should Not BeNullOrEmpty
        [string]$resourcing.path | Should Be "/tod/resourcing"
        (($resourcing.PSObject.Properties.Name) -contains "focus") | Should Be $true
        (($resourcing.PSObject.Properties.Name) -contains "demand_profile") | Should Be $true
        (($resourcing.PSObject.Properties.Name) -contains "external_resourcing") | Should Be $true
        (($resourcing.PSObject.Properties.Name) -contains "suggested_work_packages") | Should Be $true
    }

    It "get-state-bus returns endpoint payload shape" {
        $bus = Invoke-TodActionJson -Action "get-state-bus" -ExtraArgs @{ Top = "10" }

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
        (($bus.engineering_loop_state.PSObject.Properties.Name) -contains "recent_runs") | Should Be $true
        (($bus.engineering_loop_state.PSObject.Properties.Name) -contains "recent_scorecards") | Should Be $true
        (@($bus.capability_state.endpoints) -contains "/tod/engineer/run") | Should Be $true
        (@($bus.capability_state.endpoints) -contains "/tod/engineer/scorecard") | Should Be $true
    }

    It "get-version returns endpoint payload shape" {
        $ver = Invoke-TodActionJson -Action "get-version"

        $ver | Should Not BeNullOrEmpty
        [string]$ver.path | Should Be "/tod/version"
        (($ver.PSObject.Properties.Name) -contains "version") | Should Be $true
        (($ver.PSObject.Properties.Name) -contains "policy_source") | Should Be $true
    }
}
