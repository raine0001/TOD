param(
    [string]$OutputRoot = "shared_state/agentmim",
    [switch]$EmitJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

function Resolve-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) { return $PathValue }
    return (Join-Path $repoRoot $PathValue)
}

$resolvedOutputRoot = Resolve-LocalPath -PathValue $OutputRoot
if (-not (Test-Path -Path $resolvedOutputRoot)) {
    New-Item -ItemType Directory -Path $resolvedOutputRoot -Force | Out-Null
}

$starter = & (Join-Path $PSScriptRoot "Invoke-TODAgentMimStarterPack.ps1") -EmitJson | ConvertFrom-Json
$verify = & (Join-Path $PSScriptRoot "Invoke-TODAgentMimLocalVerification.ps1") -EmitJson | ConvertFrom-Json
$bootstrap = & (Join-Path $PSScriptRoot "Invoke-TODAgentMimBootstrapPlanner.ps1") -EmitJson | ConvertFrom-Json

$strictReady = [bool]$verify.summary.strict_live_update_ready
$degradedReady = [bool]$verify.summary.degraded_live_update_ready

$status = "blocked"
if ($strictReady) {
    $status = "ready_strict"
}
elseif ($degradedReady) {
    $status = "ready_degraded"
}

# Build strict blockers list from verification results
$strictBlockers = @()
if ($verify.PSObject.Properties['results']) {
    $verifyResults = if ($verify.results -is [System.Array]) { @($verify.results) } else { @($verify.results) }
    foreach ($r in $verifyResults) {
        if (-not [bool]$r.pass_required_gate) {
            $checks = $r.required_checks
            $blocking = @()
            if (-not [bool]$checks.path_exists)                     { $blocking += "path_exists" }
            if (-not [bool]$checks.critical_docs_present)           { $blocking += "critical_docs_present" }
            if (-not [bool]$checks.verification_command_identified) { $blocking += "verification_command_identified" }
            if (-not [bool]$checks.suggested_command_available)     { $blocking += "suggested_command_available" }
            $strictBlockers += [pscustomobject]@{
                project_id   = [string]$r.project_id
                project_name = [string]$r.project_name
                blocking_checks = @($blocking)
                pass_degraded_gate = [bool]$r.pass_degraded_gate
                next_action = if (@($blocking).Count -gt 0) { ("resolve: " + (@($blocking) -join ", ")) } else { "investigate" }
            }
        }
    }
}

$strictBlockersPath = Join-Path $resolvedOutputRoot "MIM_TOD_STRICT_BLOCKERS.latest.json"
$strictBlockersPayload = [pscustomobject]@{
    generated_at    = (Get-Date).ToUniversalTime().ToString("o")
    source          = "tod-agentmim-readiness-cycle-v1"
    blocker_count   = @($strictBlockers).Count
    strict_ready    = $strictReady
    blockers        = @($strictBlockers)
}
$strictBlockersPayload | ConvertTo-Json -Depth 10 | Set-Content -Path $strictBlockersPath

$readiness = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = "tod-agentmim-readiness-cycle-v1"
    status = $status
    summary = [pscustomobject]@{
        queue_tasks = [int]$starter.task_count
        total_projects = [int]$verify.summary.total_projects
        strict_gate_passed = [int]$verify.summary.strict_gate_passed
        strict_gate_failed = [int]$verify.summary.strict_gate_failed
        degraded_gate_passed = [int]$verify.summary.degraded_gate_passed
        degraded_gate_failed = [int]$verify.summary.degraded_gate_failed
        strict_live_update_ready = $strictReady
        degraded_live_update_ready = $degradedReady
        live_update_ready = $strictReady
        required_gate_passed = [int]$verify.summary.strict_gate_passed
        required_gate_failed = [int]$verify.summary.strict_gate_failed
        bootstrap_plan_count = [int]$bootstrap.plan_count
        strict_blocker_count = @($strictBlockers).Count
    }
    artifacts = [pscustomobject]@{
        task_queue = "shared_state/agentmim/MIM_TOD_AGENT_TASK_QUEUE.latest.json"
        local_test_gate = "shared_state/agentmim/MIM_TOD_LOCAL_TEST_GATE.latest.json"
        verification_results = "shared_state/agentmim/MIM_TOD_LOCAL_VERIFICATION_RESULTS.latest.json"
        bootstrap_tasks = "shared_state/agentmim/MIM_TOD_ENV_BOOTSTRAP_TASKS.latest.json"
        strict_blockers = "shared_state/agentmim/MIM_TOD_STRICT_BLOCKERS.latest.json"
    }
}

$readinessPath = Join-Path $resolvedOutputRoot "MIM_TOD_AGENTMIM_READINESS.latest.json"
$readiness | ConvertTo-Json -Depth 20 | Set-Content -Path $readinessPath

if ($EmitJson) {
    $readiness | ConvertTo-Json -Depth 12 | Write-Output
}
else {
    $readiness
}
