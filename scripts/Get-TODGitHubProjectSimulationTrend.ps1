param(
    [string]$InputRoot = "shared_state/conversation_eval/github_project_simulation",
    [int]$Top = 7,
    [string]$OutputPath = "shared_state/conversation_eval/github_project_simulation/tod_github_project_simulation.trend.latest.json",
    [switch]$EmitJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
function Resolve-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) { return [System.IO.Path]::GetFullPath($PathValue) }
    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $PathValue))
}

$inputRootAbs = Resolve-LocalPath -PathValue $InputRoot
$outputAbs = Resolve-LocalPath -PathValue $OutputPath
if (-not (Test-Path -Path $inputRootAbs)) { throw "Simulation artifact root not found: $inputRootAbs" }

$files = Get-ChildItem -Path $inputRootAbs -Filter "tod_github_project_simulation.*.json" -File |
    Where-Object {
        $_.Name -ne "tod_github_project_simulation.latest.json" -and
        $_.Name -notlike "*.trend.*"
    } |
    Sort-Object Name -Descending |
    Select-Object -First $Top

$runs = @(
    $files | ForEach-Object {
        $run = Get-Content -Path $_.FullName -Raw | ConvertFrom-Json
        if ($run.PSObject.Properties.Name -contains 'scenarios') { $run }
    }
)
$scenarioMap = @{}
foreach ($run in $runs) {
    foreach ($scenario in @($run.scenarios)) {
        $projectId = [string]$scenario.project_id
        if (-not $scenarioMap.ContainsKey($projectId)) {
            $scenarioMap[$projectId] = @{ passes = 0; total = 0; publish_ready = 0; discovery = 0 }
        }
        $scenarioMap[$projectId].total += 1
        if ([bool]$scenario.passed) { $scenarioMap[$projectId].passes += 1 }
        if ([bool]$scenario.publish_ready) { $scenarioMap[$projectId].publish_ready += 1 }
        if ([bool]$scenario.discovery_passed) { $scenarioMap[$projectId].discovery += 1 }
    }
}

$projectTrend = @($scenarioMap.GetEnumerator() | Sort-Object Key | ForEach-Object {
    [pscustomobject]@{
        project_id = [string]$_.Key
        pass_rate = if ($_.Value.total -gt 0) { [math]::Round($_.Value.passes / $_.Value.total, 4) } else { 0.0 }
        publish_ready_rate = if ($_.Value.total -gt 0) { [math]::Round($_.Value.publish_ready / $_.Value.total, 4) } else { 0.0 }
        discovery_rate = if ($_.Value.total -gt 0) { [math]::Round($_.Value.discovery / $_.Value.total, 4) } else { 0.0 }
    }
})

$report = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = "tod-github-project-simulation-trend-v1"
    input_root = $InputRoot
    run_count = @($runs).Count
    summary = [pscustomobject]@{
        avg_pass_count = if (@($runs).Count -gt 0) { [math]::Round(((@($runs | ForEach-Object { [double]$_.summary.pass_count }) | Measure-Object -Average).Average), 4) } else { 0.0 }
        avg_publish_ready_count = if (@($runs).Count -gt 0) { [math]::Round(((@($runs | ForEach-Object { [double]$_.summary.publish_ready_count }) | Measure-Object -Average).Average), 4) } else { 0.0 }
        avg_assist_utility = if (@($runs).Count -gt 0) { [math]::Round(((@($runs | ForEach-Object { [double]$_.summary.average_assist_utility }) | Measure-Object -Average).Average), 4) } else { 0.0 }
        latest_run_id = if (@($runs).Count -gt 0) { [string]$runs[0].run_id } else { "" }
    }
    project_trend = @($projectTrend)
    recent_runs = @($runs | ForEach-Object {
        [pscustomobject]@{
            run_id = [string]$_.run_id
            generated_at = [string]$_.generated_at
            pass_count = [int]$_.summary.pass_count
            publish_ready_count = [int]$_.summary.publish_ready_count
            average_assist_utility = [double]$_.summary.average_assist_utility
        }
    })
}

$report | ConvertTo-Json -Depth 20 | Set-Content -Path $outputAbs
if ($EmitJson) { $report | ConvertTo-Json -Depth 12 | Write-Output } else { $report }
