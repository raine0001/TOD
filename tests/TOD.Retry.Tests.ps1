Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$todScript = Join-Path $repoRoot "scripts/TOD.ps1"
$baseConfigPath = Join-Path $repoRoot "tod/config/tod-config.json"

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
        [Parameter(Mandatory = $true)][string]$TaskId
    )

    $raw = & $todScript -Action "run-task" -TaskId $TaskId -ConfigPath $ConfigPath -ForceConfiguredEngine
    return ($raw | ConvertFrom-Json)
}

Describe "TOD Retry Policy" {
    It "respects refactor retry cap of 2 for local not_implemented status" {
        $cfgPath = New-RetryTestConfig -RefactorMaxAttempts 2
        try {
            $result = Invoke-TodRunTaskJson -ConfigPath $cfgPath -TaskId "45"
            $localAttempts = @($result.engine_invocation.attempts | Where-Object { [string]$_.engine -eq "local" })

            (@($localAttempts).Count -eq 2) | Should Be $true
            ([string]$result.engine_invocation.active_engine -eq "codex") | Should Be $true
            ([bool]$result.engine_invocation.fallback_applied) | Should Be $true
        }
        finally {
            if (Test-Path $cfgPath) { Remove-Item $cfgPath -Force }
        }
    }

    It "respects refactor retry cap of 1 for local not_implemented status" {
        $cfgPath = New-RetryTestConfig -RefactorMaxAttempts 1
        try {
            $result = Invoke-TodRunTaskJson -ConfigPath $cfgPath -TaskId "45"
            $localAttempts = @($result.engine_invocation.attempts | Where-Object { [string]$_.engine -eq "local" })

            (@($localAttempts).Count -eq 1) | Should Be $true
            ([string]$result.engine_invocation.active_engine -eq "codex") | Should Be $true
            ([bool]$result.engine_invocation.fallback_applied) | Should Be $true
        }
        finally {
            if (Test-Path $cfgPath) { Remove-Item $cfgPath -Force }
        }
    }
}
