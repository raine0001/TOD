param(
    [string]$ConfigPath = 'tod/config/tod-config.json',
    [string]$OutputDir = 'tod/out/training',
    [string]$StatePath = 'tod/data/state.json',
    [int]$Port = 8844,
    [switch]$EmitJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$todScript = Join-Path $PSScriptRoot 'TOD.ps1'
$lightweightStateBusScript = Join-Path $PSScriptRoot 'Get-TODLightweightStateBus.ps1'

function Resolve-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return [System.IO.Path]::GetFullPath($PathValue)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $PathValue))
}

function Write-Utf8NoBomJson {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)]$Payload,
        [int]$Depth = 20
    )

    $dir = Split-Path -Parent $PathValue
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $json = ($Payload | ConvertTo-Json -Depth $Depth) -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($PathValue, $json, $utf8NoBom)
}

function Test-PathWritable {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if (-not (Test-Path -Path $PathValue)) {
        return $true
    }

    $stream = $null
    try {
        $stream = [System.IO.File]::Open($PathValue, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        return $true
    }
    catch {
        return $false
    }
    finally {
        if ($null -ne $stream) {
            $stream.Dispose()
        }
    }
}

function Get-LightweightStateBusSnapshot {
    param([Parameter(Mandatory = $true)][string]$ScriptPath)

    if (-not (Test-Path -Path $ScriptPath)) {
        return $null
    }

    try {
        $raw = & $ScriptPath -AsJson
        return ($raw | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Invoke-JsonPost {
    param(
        [Parameter(Mandatory = $true)][string]$BaseUrl,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Body
    )

    $json = $Body | ConvertTo-Json -Depth 10
    $response = Invoke-WebRequest -UseBasicParsing -Uri ("$BaseUrl$Path") -Method Post -ContentType 'application/json' -Body $json -TimeoutSec 60
    if ([string]::IsNullOrWhiteSpace([string]$response.Content)) {
        return [pscustomobject]@{}
    }

    return ($response.Content | ConvertFrom-Json)
}

function Invoke-TodActionJson {
    param(
        [Parameter(Mandatory = $true)][string]$RequestedAction,
        [string]$TaskId = '',
        [int]$Top = 0,
        [string]$StatePath = '',
        [string]$ConfigPath = '',
        [switch]$ApplyPlan
    )

    $extraArgs = @{}
    if (-not [string]::IsNullOrWhiteSpace($TaskId)) {
        $extraArgs.TaskId = $TaskId
    }
    if ($Top -gt 0) {
        $extraArgs.Top = $Top.ToString()
    }
    if (-not [string]::IsNullOrWhiteSpace($StatePath)) {
        $extraArgs.StatePath = $StatePath
    }
    if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
        $extraArgs.ConfigPath = $ConfigPath
    }
    if ($ApplyPlan) {
        $extraArgs.ApplyPlan = $true
    }

    $raw = & $todScript -Action $RequestedAction @extraArgs
    return (($raw | Out-String) | ConvertFrom-Json)
}

function ConvertFrom-EmbeddedJsonRaw {
    param([Parameter(Mandatory = $true)][string]$Raw)

    $jsonStart = $Raw.IndexOf('{')
    if ($jsonStart -lt 0) {
        throw 'Embedded JSON payload was not found in wrapper response.'
    }

    return ($Raw.Substring($jsonStart) | ConvertFrom-Json)
}

function Set-RecoveryFixtureArtifact {
    param(
        [Parameter(Mandatory = $true)][string]$ArtifactPath,
        [Parameter(Mandatory = $true)][ValidateSet('stale', 'valid')][string]$Scenario
    )

    $artifactAgeMinutes = if ($Scenario -eq 'stale') { 45 } else { 0 }
    $generatedAt = (Get-Date).ToUniversalTime().AddMinutes(-1 * $artifactAgeMinutes).ToString('o')
    $artifact = [pscustomobject]@{
        source = 'tod-operator-chat-sweep-artifact-smoke-v1'
        generated_at = $generatedAt
        summary = [pscustomobject]@{
            total = 13
            passed = 13
            failed = 0
            passed_all = $true
            exit_code = 0
        }
    }

    Write-Utf8NoBomJson -PathValue $ArtifactPath -Payload $artifact -Depth 20
}

function New-RecoveryFixture {
    param([Parameter(Mandatory = $true)][string]$SourceConfigPath)

    $fixtureId = [guid]::NewGuid().ToString('N')
    $base = Join-Path $repoRoot (Join-Path 'tod/out/training' ('readiness-recovery-fixture-' + $fixtureId))
    $artifactPath = Join-Path $base 'tod_operator_chat_sweep_artifact_smoke.latest.json'
    $historyPath = Join-Path $base 'tod_execution_readiness_history.latest.json'
    $statePath = Join-Path $base 'state.json'
    $configPath = Join-Path $base 'tod-config.json'

    New-Item -ItemType Directory -Path $base -Force | Out-Null

    $state = [pscustomobject]@{
        source = 'tod-state-test-fixture-v1'
        updated_at = ''
        objectives = @(
            [pscustomobject]@{
                id = '75'
                title = 'Reliability recovery drill objective'
                status = 'in_progress'
                constraints = @()
                success_criteria = @()
            }
        )
        tasks = @(
            [pscustomobject]@{
                id = '45'
                objective_id = '75'
                title = 'Reliability recovery drill task'
                scope = 'Exercise wrapper recovery behavior under request-scoped readiness.'
                type = 'implementation'
                task_category = 'refactor'
                assigned_executor = 'codex'
                status = 'pending'
                dependencies = @()
                acceptance_criteria = @()
            }
        )
        execution_results = @()
        review_decisions = @()
        journal = @()
        sync_state = [pscustomobject]@{ last_comparison = [pscustomobject]@{ status = 'ok' } }
        engine_performance = [pscustomobject]@{ records = @(); updated_at = (Get-Date).ToUniversalTime().ToString('o') }
        routing_decisions = [pscustomobject]@{ records = @(); updated_at = (Get-Date).ToUniversalTime().ToString('o') }
        engineering_loop = [pscustomobject]@{
            run_history = @()
            scorecard_history = @()
            cycle_records = @()
            review_actions = @()
            last_run = $null
            last_scorecard = $null
            updated_at = (Get-Date).ToUniversalTime().ToString('o')
        }
    }
    Write-Utf8NoBomJson -PathValue $statePath -Payload $state -Depth 30

    $cfg = Get-Content -Path $SourceConfigPath -Raw | ConvertFrom-Json
    if (-not $cfg.execution_engine.PSObject.Properties['readiness_policy'] -or $null -eq $cfg.execution_engine.readiness_policy) {
        $cfg.execution_engine | Add-Member -NotePropertyName readiness_policy -NotePropertyValue ([pscustomobject]@{}) -Force
    }

    $cfg.execution_engine.readiness_policy = [pscustomobject]@{
        enabled = $true
        signal_path = $artifactPath
        history_path = $historyPath
        history_max_entries = 20
        max_artifact_age_minutes = 30
        display_max_artifact_age_minutes = 10
        block_actions = @('run-task')
        degrade_actions = @('engineer-run')
        block_states = @('stale', 'invalid', 'unknown')
        degrade_states = @('degraded', 'stale', 'invalid', 'unknown')
        degrade_apply_plan = $true
    }
    Write-Utf8NoBomJson -PathValue $configPath -Payload $cfg -Depth 40

    return [pscustomobject]@{
        Base = $base
        ArtifactPath = $artifactPath
        HistoryPath = $historyPath
        StatePath = $statePath
        ConfigPath = $configPath
    }
}

function Remove-RecoveryFixture {
    param($Fixture)

    if ($Fixture -and $Fixture.Base -and (Test-Path -Path $Fixture.Base)) {
        Remove-Item -Path $Fixture.Base -Recurse -Force
    }
}

$effectiveConfigPath = Resolve-LocalPath -PathValue $ConfigPath
$effectiveOutputDir = Resolve-LocalPath -PathValue $OutputDir
$effectiveStatePath = Resolve-LocalPath -PathValue $StatePath
$baseUrl = 'http://localhost:{0}' -f $Port
$artifactOutputPath = Join-Path $effectiveOutputDir 'readiness-recovery.latest.json'

if (-not (Test-Path -Path $effectiveOutputDir)) {
    New-Item -ItemType Directory -Path $effectiveOutputDir -Force | Out-Null
}

$lightweightSnapshot = Get-LightweightStateBusSnapshot -ScriptPath $lightweightStateBusScript
$fixture = $null

try {
    $fixture = New-RecoveryFixture -SourceConfigPath $effectiveConfigPath

    Set-RecoveryFixtureArtifact -ArtifactPath $fixture.ArtifactPath -Scenario 'stale'
    $staleReadiness = (& $todScript -Action 'get-execution-readiness' -ConfigPath $fixture.ConfigPath) | ConvertFrom-Json

    $blockedRun = Invoke-TodActionJson -RequestedAction 'run-task' -TaskId '45' -StatePath ([string]$fixture.StatePath) -ConfigPath ([string]$fixture.ConfigPath)

    $degradedRun = Invoke-TodActionJson -RequestedAction 'engineer-run' -Top 1 -StatePath ([string]$fixture.StatePath) -ConfigPath ([string]$fixture.ConfigPath) -ApplyPlan

    Set-RecoveryFixtureArtifact -ArtifactPath $fixture.ArtifactPath -Scenario 'valid'
    $recoveredReadiness = (& $todScript -Action 'get-execution-readiness' -ConfigPath $fixture.ConfigPath) | ConvertFrom-Json

    $recoveryTransition = $null
    foreach ($transition in @($recoveredReadiness.history.recent_transitions)) {
        if ([string]$transition.prior_status -eq 'stale' -and [string]$transition.new_status -eq 'valid') {
            $recoveryTransition = $transition
            break
        }
    }

    $summary = [pscustomobject]@{
        stale_status = [string]$staleReadiness.readiness.status
        blocked_enforced = [bool](
            [string]$blockedRun.decision -eq 'blocked' -and
            [string]$blockedRun.execution_readiness.policy_outcome -eq 'block'
        )
        degraded_enforced = [bool](
            $null -ne $degradedRun -and
            [string]$degradedRun.execution_trace.execution_readiness.policy_outcome -eq 'degrade' -and
            [bool]$degradedRun.execution_readiness_degraded
        )
        recovered = [bool](
            [string]$recoveredReadiness.readiness.status -eq 'valid' -and
            $null -ne $recoveryTransition
        )
        history_transition_observed = [bool]($null -ne $recoveryTransition)
        runtime_safe_validation = $true
        state_file_locked = (-not (Test-PathWritable -PathValue $effectiveStatePath))
    }

    $artifact = [pscustomobject]@{
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        source = 'tod-reliability-recovery-drill-v1'
        output_dir = $effectiveOutputDir
        config_path = $effectiveConfigPath
        port = $Port
        live_runtime = [pscustomobject]@{
            state_file_locked = (-not (Test-PathWritable -PathValue $effectiveStatePath))
            lightweight_state_bus = $lightweightSnapshot
        }
        artifacts = [pscustomobject]@{
            readiness_recovery = $artifactOutputPath
            readiness_history = [string]$fixture.HistoryPath
        }
        stale_readiness = [pscustomobject]@{
            status = [string]$staleReadiness.readiness.status
            reason = [string]$staleReadiness.readiness.reason
            execution_allowed = [bool]$staleReadiness.readiness.execution_allowed
            artifact_age_minutes = if ($staleReadiness.readiness.PSObject.Properties['artifact_age_minutes']) { [double]$staleReadiness.readiness.artifact_age_minutes } else { -1 }
        }
        blocked_run_task = [pscustomobject]@{
            decision = if ($blockedRun.PSObject.Properties['decision']) { [string]$blockedRun.decision } else { '' }
            blocked = if ($blockedRun.PSObject.Properties['blocked']) { [bool]$blockedRun.blocked } else { $false }
            policy_outcome = if ($blockedRun.PSObject.Properties['execution_readiness']) { [string]$blockedRun.execution_readiness.policy_outcome } else { '' }
            message = if ($blockedRun.PSObject.Properties['message']) { [string]$blockedRun.message } else { '' }
        }
        degraded_engineer_run = [pscustomobject]@{
            policy_outcome = if ($null -ne $degradedRun -and $degradedRun.PSObject.Properties['execution_trace']) { [string]$degradedRun.execution_trace.execution_readiness.policy_outcome } else { '' }
            degraded = if ($null -ne $degradedRun -and $degradedRun.PSObject.Properties['execution_readiness_degraded']) { [bool]$degradedRun.execution_readiness_degraded } else { $false }
            apply_plan_effective = if ($null -ne $degradedRun -and $degradedRun.PSObject.Properties['apply_plan_effective']) { [bool]$degradedRun.apply_plan_effective } else { $false }
            readiness_status = if ($null -ne $degradedRun -and $degradedRun.PSObject.Properties['execution_trace']) { [string]$degradedRun.execution_trace.execution_readiness.status } else { '' }
        }
        recovered_readiness = [pscustomobject]@{
            status = [string]$recoveredReadiness.readiness.status
            reason = [string]$recoveredReadiness.readiness.reason
            execution_allowed = [bool]$recoveredReadiness.readiness.execution_allowed
            transition = $recoveryTransition
        }
        summary = $summary
    }

    Write-Utf8NoBomJson -PathValue $artifactOutputPath -Payload $artifact -Depth 30

    if ($EmitJson) {
        $artifact | ConvertTo-Json -Depth 30 | Write-Output
    }
    else {
        $artifact | ConvertTo-Json -Depth 30 | Write-Output
    }
}
finally {
    Remove-RecoveryFixture -Fixture $fixture
}