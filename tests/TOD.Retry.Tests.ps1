Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$todScript = Join-Path $repoRoot "scripts/TOD.ps1"
$baseConfigPath = Join-Path $repoRoot "tod/config/tod-config.json"

function New-RetryTestStatePath {
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
                title = "Retry fixture task"
                scope = "Validate retry fallback behavior for refactor task."
                type = "implementation"
                task_category = "refactor"
                assigned_executor = "codex"
                status = "pending"
                updated_at = ""
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

    $path = Join-Path $repoRoot ("tod/out/tests/retry-state-{0}.json" -f ([guid]::NewGuid().ToString("N")))
    $state | ConvertTo-Json -Depth 30 | Set-Content $path
    return $path
}

function New-RetryTestConfig {
    param(
        [Parameter(Mandatory = $true)][int]$RefactorMaxAttempts
    )

    $cfg = Get-Content $baseConfigPath -Raw | ConvertFrom-Json
    $cfg.mode = "local"
    $cfg.execution_engine.active = "local"
    $cfg.execution_engine.fallback = "codex"
    $cfg.execution_engine.allow_fallback = $true
    $cfg.execution_engine.retry_policy.enabled = $true
    $cfg.execution_engine.retry_policy.max_attempts_per_engine = 2
    $cfg.execution_engine.retry_policy.max_attempts_by_category.refactor = $RefactorMaxAttempts

    $tempPath = Join-Path $repoRoot ("tod/config/tod-config.test-retry-{0}.json" -f ([guid]::NewGuid().ToString("N")))
    $cfg | ConvertTo-Json -Depth 20 | Set-Content $tempPath
    return $tempPath
}

function Invoke-TodRunTaskJson {
    param(
        [Parameter(Mandatory = $true)][string]$ConfigPath,
        [Parameter(Mandatory = $true)][string]$TaskId,
        [Parameter(Mandatory = $true)][string]$StatePath
    )

    $raw = & $todScript -Action "run-task" -TaskId $TaskId -ConfigPath $ConfigPath -StatePath $StatePath -ForceConfiguredEngine
    return ($raw | ConvertFrom-Json)
}

Describe "TOD Retry Policy" {
    It "respects refactor retry cap upper bound of 2 for local not_implemented status" {
        $cfgPath = New-RetryTestConfig -RefactorMaxAttempts 2
        $testStatePath = New-RetryTestStatePath
        try {
            $result = Invoke-TodRunTaskJson -ConfigPath $cfgPath -TaskId "45" -StatePath $testStatePath
            $localAttempts = @($result.engine_invocation.attempts | Where-Object { [string]$_.engine -eq "local" })

            # Retry cap is an upper bound; fallback may complete before a second local retry is needed.
            ((@($localAttempts).Count -ge 1) -and (@($localAttempts).Count -le 2)) | Should Be $true
            ([string]$result.engine_invocation.active_engine -eq "codex") | Should Be $true
            ([bool]$result.engine_invocation.fallback_applied) | Should Be $true
        }
        finally {
            if (Test-Path $cfgPath) { Remove-Item $cfgPath -Force }
            if (Test-Path $testStatePath) { Remove-Item $testStatePath -Force }
        }
    }

    It "respects refactor retry cap of 1 for local not_implemented status" {
        $cfgPath = New-RetryTestConfig -RefactorMaxAttempts 1
        $testStatePath = New-RetryTestStatePath
        try {
            $result = Invoke-TodRunTaskJson -ConfigPath $cfgPath -TaskId "45" -StatePath $testStatePath
            $localAttempts = @($result.engine_invocation.attempts | Where-Object { [string]$_.engine -eq "local" })

            (@($localAttempts).Count -eq 1) | Should Be $true
            ([string]$result.engine_invocation.active_engine -eq "codex") | Should Be $true
            ([bool]$result.engine_invocation.fallback_applied) | Should Be $true
        }
        finally {
            if (Test-Path $cfgPath) { Remove-Item $cfgPath -Force }
            if (Test-Path $testStatePath) { Remove-Item $testStatePath -Force }
        }
    }
}
