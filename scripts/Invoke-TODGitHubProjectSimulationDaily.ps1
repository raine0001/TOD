param(
    [switch]$UseAssist,
    [string]$OutputRoot = "shared_state/conversation_eval/github_project_simulation",
    [switch]$EmitJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$runner = Join-Path $PSScriptRoot "Invoke-TODGitHubProjectSimulation.ps1"
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
    discovery_success_count = [int]$result.summary.discovery_success_count
    publish_ready_count = [int]$result.summary.publish_ready_count
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
