param(
    [string]$QueueScriptPath = "scripts/Get-TODProjectExecutionQueue.ps1",
    [string]$TodScriptPath = "scripts/TOD.ps1",
    [string]$RegistryPath = "tod/config/project-registry.json",
    [string]$ProjectId,
    [string]$RelativePath = "",
    [string]$Content,
    [int]$Top = 10,
    [switch]$ExecuteGuardedWrites,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

function Resolve-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) { return $PathValue }
    return (Join-Path $repoRoot $PathValue)
}

$queueScript = Resolve-LocalPath -PathValue $QueueScriptPath
$todScript = Resolve-LocalPath -PathValue $TodScriptPath
$resolvedRegistryPath = Resolve-LocalPath -PathValue $RegistryPath

if (-not (Test-Path -Path $queueScript)) { throw "Queue script not found: $queueScript" }
if (-not (Test-Path -Path $todScript)) { throw "TOD script not found: $todScript" }
if (-not (Test-Path -Path $resolvedRegistryPath)) { throw "Registry file not found: $resolvedRegistryPath" }

$registry = (Get-Content -Path $resolvedRegistryPath -Raw | ConvertFrom-Json)
$registryProjects = if ($registry -and $registry.PSObject.Properties["projects"]) { @($registry.projects) } else { @() }

function Resolve-ProjectRelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectId,
        [string]$RequestedPath
    )

    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        return (($RequestedPath -replace "\\", "/").TrimStart("/"))
    }

    $project = @($registryProjects | Where-Object { [string]$_.id -eq [string]$ProjectId } | Select-Object -First 1)
    if (@($project).Count -eq 0) {
        return "docs/queue-runner/probe.txt"
    }

    $allowed = if ($project[0].PSObject.Properties["boundaries"] -and $project[0].boundaries.PSObject.Properties["allowed_paths"]) { @($project[0].boundaries.allowed_paths) } else { @() }
    $allowed = @($allowed | ForEach-Object { ([string]$_ -replace "\\", "/").TrimStart("/") } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    if (@($allowed).Count -eq 0) {
        return "docs/queue-runner/probe.txt"
    }

    if (@($allowed | Where-Object { ([string]$_).ToLowerInvariant() -eq "docs" }).Count -gt 0) {
        return "docs/queue-runner/probe.txt"
    }
    if (@($allowed | Where-Object { ([string]$_).ToLowerInvariant() -eq "src" }).Count -gt 0) {
        return "src/queue-runner/probe.txt"
    }

    return ("{0}/queue-runner/probe.txt" -f [string]$allowed[0])
}

$defaultContent = @(
    "# TOD Queue Runner Artifact"
    ""
    "generated_at: $((Get-Date).ToUniversalTime().ToString('o'))"
    "relative_path: $RelativePath"
) -join [Environment]::NewLine

$effectiveContent = if ([string]::IsNullOrWhiteSpace($Content)) { $defaultContent } else { [string]$Content }

$queueRaw = & $queueScript
$queueResult = $queueRaw | ConvertFrom-Json
if (-not $queueResult -or -not $queueResult.PSObject.Properties["queue"]) {
    throw "Queue script returned invalid payload."
}

$items = @($queueResult.queue | Sort-Object priority)
if (-not [string]::IsNullOrWhiteSpace($ProjectId)) {
    $items = @($items | Where-Object { [string]$_.project_id -eq [string]$ProjectId })
}

$safeTop = if ($Top -lt 1) { 1 } elseif ($Top -gt 200) { 200 } else { $Top }
$items = @($items | Select-Object -First $safeTop)

$operations = @()
foreach ($item in $items) {
    $id = [string]$item.project_id
    $mode = ([string]$item.mode).ToLowerInvariant()
    $status = [string]$item.status
    $projectRelativePath = Resolve-ProjectRelativePath -ProjectId $id -RequestedPath $RelativePath
    $sandboxPath = "projects/{0}/{1}" -f $id, $projectRelativePath

    if ($status -ne "ready") {
        $operations += [pscustomobject]@{
            project_id = $id
            priority = [int]$item.priority
            mode = $mode
            status = $status
            action = "skip"
            ok = $false
            reason = "project_not_ready"
            sandbox_path = $sandboxPath
        }
        continue
    }

    $action = "sandbox-plan"
    $decision = "plan_only"
    if ($mode -eq "guarded-write" -and $ExecuteGuardedWrites) {
        $action = "sandbox-write"
        $decision = "guarded_write_execute"
    }
    elseif ($mode -eq "advisory-first") {
        $action = "sandbox-plan"
        $decision = "advisory_plan_only"
    }
    elseif ($mode -eq "review-only") {
        $action = "sandbox-plan"
        $decision = "review_plan_only"
    }

    if ($DryRun) {
        $operations += [pscustomobject]@{
            project_id = $id
            priority = [int]$item.priority
            mode = $mode
            status = $status
            action = $action
            ok = $true
            dry_run = $true
            decision = $decision
            sandbox_path = $sandboxPath
            command = ".\\scripts\\TOD.ps1 -Action $action -SandboxPath `"$sandboxPath`" -Content `"<content>`""
        }
        continue
    }

    try {
        $raw = & $todScript -Action $action -SandboxPath $sandboxPath -Content $effectiveContent
        $payload = $raw | ConvertFrom-Json
        $operations += [pscustomobject]@{
            project_id = $id
            priority = [int]$item.priority
            mode = $mode
            status = $status
            action = $action
            ok = $true
            dry_run = $false
            decision = $decision
            sandbox_path = $sandboxPath
            result_path = if ($payload -and $payload.PSObject.Properties["path"]) { [string]$payload.path } else { "" }
            artifact_path = if ($payload -and $payload.PSObject.Properties["artifact_path"]) { [string]$payload.artifact_path } else { "" }
        }
    }
    catch {
        $operations += [pscustomobject]@{
            project_id = $id
            priority = [int]$item.priority
            mode = $mode
            status = $status
            action = $action
            ok = $false
            dry_run = $false
            decision = $decision
            sandbox_path = $sandboxPath
            error = $_.Exception.Message
        }
    }
}

$okCount = [int]@($operations | Where-Object { [bool]$_.ok }).Count
$failCount = [int]@($operations | Where-Object { -not [bool]$_.ok }).Count

$result = [pscustomobject]@{
    ok = ($failCount -eq 0)
    source = "tod-project-queue-runner-v1"
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    dry_run = [bool]$DryRun
    execute_guarded_writes = [bool]$ExecuteGuardedWrites
    relative_path = if ([string]::IsNullOrWhiteSpace($RelativePath)) { "<auto>" } else { $RelativePath }
    selected_projects = @($items).Count
    successful = $okCount
    failed = $failCount
    operations = @($operations)
}

$result | ConvertTo-Json -Depth 16 | Write-Output

if (-not $result.ok) {
    exit 2
}