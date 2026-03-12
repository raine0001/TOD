param(
    [string]$RegistryPath = "tod/config/project-registry.json",
    [string]$PriorityPath = "tod/config/project-priority.json",
    [string]$IndexPath = "tod/data/project-library-index.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

function Resolve-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) { return $PathValue }
    return (Join-Path $repoRoot $PathValue)
}

$resolvedRegistryPath = Resolve-LocalPath -PathValue $RegistryPath
$resolvedPriorityPath = Resolve-LocalPath -PathValue $PriorityPath
$resolvedIndexPath = Resolve-LocalPath -PathValue $IndexPath

if (-not (Test-Path -Path $resolvedRegistryPath)) { throw "Registry file not found: $resolvedRegistryPath" }
if (-not (Test-Path -Path $resolvedPriorityPath)) { throw "Priority file not found: $resolvedPriorityPath" }
if (-not (Test-Path -Path $resolvedIndexPath)) { throw "Project index file not found: $resolvedIndexPath" }

$registry = (Get-Content -Path $resolvedRegistryPath -Raw | ConvertFrom-Json)
$priority = (Get-Content -Path $resolvedPriorityPath -Raw | ConvertFrom-Json)
$index = (Get-Content -Path $resolvedIndexPath -Raw | ConvertFrom-Json)

$projects = if ($registry.PSObject.Properties["projects"]) { @($registry.projects) } else { @() }
$priorityItems = if ($priority.PSObject.Properties["execution_order"]) { @($priority.execution_order) } else { @() }
$indexedProjects = if ($index.PSObject.Properties["projects"]) { @($index.projects) } else { @() }

$queue = @()
foreach ($item in ($priorityItems | Sort-Object priority)) {
    $projectId = [string]$item.project_id
    $project = @($projects | Where-Object { [string]$_.id -eq $projectId }) | Select-Object -First 1
    $indexed = @($indexedProjects | Where-Object { [string]$_.id -eq $projectId }) | Select-Object -First 1

    if ($null -eq $project) {
        $queue += [pscustomobject]@{
            project_id = $projectId
            priority = [int]$item.priority
            mode = [string]$item.mode
            status = "missing-from-registry"
            exists = $false
            risk_level = "unknown"
            write_access = "unknown"
            notes = [string]$item.notes
        }
        continue
    }

    $exists = if ($null -ne $indexed -and $indexed.PSObject.Properties["exists"]) { [bool]$indexed.exists } else { $false }
    $status = if ($exists) { "ready" } else { "path-missing" }

    $queue += [pscustomobject]@{
        project_id = [string]$project.id
        project_name = [string]$project.name
        priority = [int]$item.priority
        mode = [string]$item.mode
        status = $status
        exists = $exists
        risk_level = [string]$project.risk_level
        write_access = [string]$project.write_access
        path = [string]$project.path
        notes = [string]$item.notes
    }
}

$result = [pscustomobject]@{
    ok = $true
    source = "tod-project-execution-queue-v1"
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    queue = @($queue)
}

$result | ConvertTo-Json -Depth 12 | Write-Output
