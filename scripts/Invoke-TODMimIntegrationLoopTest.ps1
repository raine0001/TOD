param(
    [string]$TodScriptPath = "scripts/TOD.ps1",
    [string]$ContextScriptPath = "scripts/Invoke-TODContextExchange.ps1",
    [string]$TodConfigPath = "tod/config/tod-config.json",
    [int]$Top = 15,
    [string]$OutputPath = "shared_state/integration_loop_test.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

function Get-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) { return $PathValue }
    return (Join-Path $repoRoot $PathValue)
}

function Invoke-JsonScript {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][hashtable]$Params,
        [Parameter(Mandatory = $true)][string]$StepName
    )

    try {
        $raw = & $ScriptPath @Params
        $payload = $raw | ConvertFrom-Json
        return [pscustomobject]@{
            step = $StepName
            ok = $true
            payload = $payload
            error = ""
        }
    }
    catch {
        return [pscustomobject]@{
            step = $StepName
            ok = $false
            payload = $null
            error = $_.Exception.Message
        }
    }
}

$todScriptAbs = Get-LocalPath -PathValue $TodScriptPath
$contextScriptAbs = Get-LocalPath -PathValue $ContextScriptPath
$todConfigAbs = Get-LocalPath -PathValue $TodConfigPath
$outputAbs = Get-LocalPath -PathValue $OutputPath

if (-not (Test-Path -Path $todScriptAbs)) { throw "TOD script not found: $todScriptAbs" }
if (-not (Test-Path -Path $contextScriptAbs)) { throw "Context script not found: $contextScriptAbs" }
if (-not (Test-Path -Path $todConfigAbs)) { throw "TOD config not found: $todConfigAbs" }

$steps = @()
$goalId = "MIMGOAL-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 10).ToUpperInvariant())

$steps += Invoke-JsonScript -ScriptPath $todScriptAbs -Params @{ Action = "get-engineering-signal"; ConfigPath = $todConfigAbs; Top = $Top } -StepName "tod_signal_before"

$mockUpdate = [pscustomobject]@{
    source = "mim-strategy-engine"
    actor = "goal-strategy"
    channel = "execution-planning"
    update_type = "strategy_goal"
    project = "TOD"
    summary = "Execute loop validation for $goalId"
    details = [pscustomobject]@{
        goal_id = $goalId
        plan = @(
            "validate regression baseline",
            "execute one bounded TOD cycle",
            "emit reliability + shared-state feedback"
        )
    }
    created_at = (Get-Date).ToUniversalTime().ToString("o")
}

$inboxDir = Get-LocalPath -PathValue "tod/inbox/context-sync/updates"
if (-not (Test-Path -Path $inboxDir)) {
    New-Item -ItemType Directory -Path $inboxDir -Force | Out-Null
}
$mockFile = Join-Path $inboxDir ("integration-loop-{0}.json" -f ([guid]::NewGuid().ToString("N").Substring(0, 8).ToLowerInvariant()))
$mockUpdate | ConvertTo-Json -Depth 10 | Set-Content -Path $mockFile

$steps += Invoke-JsonScript -ScriptPath $contextScriptAbs -Params @{ Action = "ingest" } -StepName "context_ingest"
$steps += Invoke-JsonScript -ScriptPath $todScriptAbs -Params @{ Action = "engineer-cycle"; ConfigPath = $todConfigAbs; Cycles = 1; Top = $Top } -StepName "tod_execute"
$steps += Invoke-JsonScript -ScriptPath $todScriptAbs -Params @{ Action = "get-reliability"; ConfigPath = $todConfigAbs; Top = $Top } -StepName "tod_feedback"
$steps += Invoke-JsonScript -ScriptPath $contextScriptAbs -Params @{ Action = "export" } -StepName "context_export"
$steps += Invoke-JsonScript -ScriptPath $todScriptAbs -Params @{ Action = "get-engineering-signal"; ConfigPath = $todConfigAbs; Top = $Top } -StepName "tod_signal_after"

$failed = @($steps | Where-Object { -not [bool]$_.ok })
$signalAfter = @($steps | Where-Object { [string]$_.step -eq "tod_signal_after" } | Select-Object -First 1)
$reliability = @($steps | Where-Object { [string]$_.step -eq "tod_feedback" } | Select-Object -First 1)

$result = [pscustomobject]@{
    ok = (@($failed).Count -eq 0)
    source = "tod-mim-integration-loop-test-v1"
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    goal_id = $goalId
    steps = @($steps)
    summary = [pscustomobject]@{
        steps_total = [int]@($steps).Count
        steps_failed = [int]@($failed).Count
        pending_approvals_after = if ($signalAfter -and $signalAfter.payload -and $signalAfter.payload.PSObject.Properties["pending_approval_state"] -and $signalAfter.payload.pending_approval_state.PSObject.Properties["count"]) { [int]$signalAfter.payload.pending_approval_state.count } else { -1 }
        trend_after = if ($signalAfter -and $signalAfter.payload -and $signalAfter.payload.PSObject.Properties["trend_direction"]) { [string]$signalAfter.payload.trend_direction } else { "unknown" }
        reliability_alert_after = if ($reliability -and $reliability.payload -and $reliability.payload.PSObject.Properties["current_alert_state"]) { [string]$reliability.payload.current_alert_state } else { "unknown" }
    }
}

$outDir = Split-Path -Parent $outputAbs
if (-not [string]::IsNullOrWhiteSpace($outDir) -and -not (Test-Path -Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}
$result | ConvertTo-Json -Depth 20 | Set-Content -Path $outputAbs
$result | ConvertTo-Json -Depth 20 | Write-Output
