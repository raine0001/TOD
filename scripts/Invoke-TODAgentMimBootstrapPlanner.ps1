param(
    [string]$TaskQueuePath = "shared_state/agentmim/MIM_TOD_AGENT_TASK_QUEUE.latest.json",
    [string]$OutputPath = "shared_state/agentmim/MIM_TOD_ENV_BOOTSTRAP_TASKS.latest.json",
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

function To-Array {
    param($Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Array]) { return @($Value) }
    return @($Value)
}

function New-BootstrapPlan {
    param(
        [Parameter(Mandatory = $true)]$Task
    )

    $projectId = [string]$Task.project_id
    $sourceRoot = [string]$Task.local_copy_contract.source_root
    $id = $projectId.ToLowerInvariant()

    switch ($id) {
        "viasion" {
            return [pscustomobject]@{
                project_id = $projectId
                source_root = $sourceRoot
                bootstrap_steps = @(
                    "Set-Location '$sourceRoot'",
                    "npm install",
                    "npm run test:e2e -- --list"
                )
                goal = "Establish local Node/Playwright verification surface."
            }
        }
        "mim_pulz" {
            return [pscustomobject]@{
                project_id = $projectId
                source_root = $sourceRoot
                bootstrap_steps = @(
                    "Set-Location '$sourceRoot'",
                    "python -m venv .venv_todcheck",
                    ".\\.venv_todcheck\\Scripts\\python -m pip install -U pip pytest",
                    ".\\.venv_todcheck\\Scripts\\python -m pytest --collect-only"
                )
                goal = "Create isolated Python test-check environment and verify test discovery."
            }
        }
        "coachmim" {
            return [pscustomobject]@{
                project_id = $projectId
                source_root = $sourceRoot
                bootstrap_steps = @(
                    "Set-Location '$sourceRoot'",
                    "python -m venv .venv_todcheck",
                    ".\\.venv_todcheck\\Scripts\\python -m pip install -U pip pytest",
                    ".\\.venv_todcheck\\Scripts\\python -m pytest --collect-only"
                )
                goal = "Create isolated Python test-check environment and verify test discovery."
            }
        }
        "comm_app" {
            return [pscustomobject]@{
                project_id = $projectId
                source_root = $sourceRoot
                bootstrap_steps = @(
                    "Set-Location '$sourceRoot'",
                    "python -m venv .venv_todcheck",
                    ".\\.venv_todcheck\\Scripts\\python -m pip install -U pip pytest",
                    ".\\.venv_todcheck\\Scripts\\python -m pytest --collect-only"
                )
                goal = "Create isolated Python test-check environment and verify test discovery."
            }
        }
        "mim_arm" {
            return [pscustomobject]@{
                project_id = $projectId
                source_root = $sourceRoot
                bootstrap_steps = @(
                    "Set-Location '$sourceRoot'",
                    "python -m py_compile MIM_arm.py"
                )
                goal = "Validate script syntax as baseline local copy check."
            }
        }
        "mimrobots.com" {
            return [pscustomobject]@{
                project_id = $projectId
                source_root = $sourceRoot
                bootstrap_steps = @(
                    "Set-Location '$sourceRoot'",
                    "python -m py_compile run.py"
                )
                goal = "Validate app entrypoint syntax as baseline local copy check."
            }
        }
        default {
            return [pscustomobject]@{
                project_id = $projectId
                source_root = $sourceRoot
                bootstrap_steps = @(
                    "Set-Location '$sourceRoot'",
                    "python -m pytest --collect-only"
                )
                goal = "Generic local test-copy verification."
            }
        }
    }
}

$resolvedTaskQueuePath = Resolve-LocalPath -PathValue $TaskQueuePath
$resolvedOutputPath = Resolve-LocalPath -PathValue $OutputPath

if (-not (Test-Path -Path $resolvedTaskQueuePath)) {
    throw "Task queue not found: $resolvedTaskQueuePath"
}

$queueObj = Get-Content -Path $resolvedTaskQueuePath -Raw | ConvertFrom-Json
$localTasks = To-Array -Value $queueObj.task_queue | Where-Object { [string]$_.category -eq "local-verification" }

$plans = @()
foreach ($task in $localTasks) {
    $plans += New-BootstrapPlan -Task $task
}

$output = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = "tod-agentmim-bootstrap-planner-v1"
    plan_count = @($plans).Count
    plans = @($plans)
}

$outputDir = Split-Path -Parent $resolvedOutputPath
if (-not (Test-Path -Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$output | ConvertTo-Json -Depth 20 | Set-Content -Path $resolvedOutputPath

if ($EmitJson) {
    $output | ConvertTo-Json -Depth 12 | Write-Output
}
else {
    $output
}
