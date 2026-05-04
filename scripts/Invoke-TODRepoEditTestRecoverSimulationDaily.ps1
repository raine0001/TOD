param(
    [switch]$UseAssist,
    [string]$OutputRoot = "shared_state/conversation_eval/repo_edit_test_recover",
    [switch]$EmitJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$runner = Join-Path $PSScriptRoot "Invoke-TODRepoEditTestRecoverSimulation.ps1"
if (-not (Test-Path -Path $runner)) {
    throw "Missing simulation runner: $runner"
}

$params = @{
    OutputRoot = $OutputRoot
    EmitJson = $true
}
if ($UseAssist) { $params.UseAssist = $true }

$result = & $runner @params | ConvertFrom-Json

$summary = [pscustomobject]@{
    run_id = $result.run_id
    scenario_count = [int]$result.summary.scenario_count
    pass_count = [int]$result.summary.pass_count
    test_ready_count = [int]$result.summary.test_ready_count
    recovery_ready_count = [int]$result.summary.recovery_ready_count
    average_stage_coverage = [double]$result.summary.average_stage_coverage
    average_assist_utility = [double]$result.summary.average_assist_utility
    github_account = [string]$result.summary.github_account
    artifact = [string]$result.artifacts.latest_path
}

if ($EmitJson) {
    $summary | ConvertTo-Json -Depth 10 | Write-Output
}
else {
    $summary
}