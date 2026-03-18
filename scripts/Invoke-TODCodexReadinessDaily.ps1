param(
    [ValidateSet("review", "debug", "fixes", "plan", "operator")]
    [string]$Mode = "review",
    [string[]]$FilePaths = @(
        "scripts/Invoke-TODConversationEvalRunner.ps1",
        "scripts/Invoke-TODDriftLockSoak.ps1"
    ),
    [string]$OutputRoot = "shared_state/conversation_eval/codex_readiness",
    [string]$TestCommand = "",
    [switch]$EmitJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$runner = Join-Path $PSScriptRoot "Invoke-TODCodexReadinessRun.ps1"
if (-not (Test-Path -Path $runner)) {
    throw "Missing codex readiness runner: $runner"
}

$effectiveTestCommand = $TestCommand
if ([string]::IsNullOrWhiteSpace($effectiveTestCommand)) {
    $prGateScript = Join-Path $PSScriptRoot "Invoke-TODConversationEvalPR.ps1"
    $effectiveTestCommand = "& `"$prGateScript`" -EmitJson"
}

# Daily profile keeps hard quality gates without assuming clean worktrees.
$runnerArgs = @{
    Mode = $Mode
    FilePaths = $FilePaths
    OutputRoot = $OutputRoot
    MinAverageUtility = 0.74
    MaxAssistFailures = 0
    MaxChangedFiles = 4
    AllowedEditPaths = @("scripts/", "tod/", "shared_state/conversation_eval/")
    TestCommand = $effectiveTestCommand
    EmitJson = $true
}

$result = & $runner @runnerArgs | ConvertFrom-Json

if ($EmitJson) {
    $result | ConvertTo-Json -Depth 15 | Write-Output
}
else {
    [pscustomobject]@{
        run_id = $result.run_id
        gate_passed = [bool]$result.summary.gate_passed
        average_utility = [double]$result.summary.average_utility
        task_success_rate = [double]$result.summary.task_success_rate
        first_pass_success_rate = [double]$result.summary.first_pass_success_rate
        rework_rate = [double]$result.summary.rework_rate
        accept_without_edit_rate = [double]$result.summary.accept_without_edit_rate
        artifact = [string]$result.artifacts.latest_path
    }
}
