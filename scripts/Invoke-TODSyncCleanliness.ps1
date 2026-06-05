param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [switch]$CleanGeneratedRuntime,
    [string]$OutputPath = "shared_state/tod_sync_cleanliness.latest.json"
)

$ErrorActionPreference = 'Stop'

$resolvedRepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
Set-Location $resolvedRepoRoot

function Convert-GitPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    return ($PathValue -replace '\\', '/').Trim()
}

function Test-GeneratedRuntimePath {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    $path = Convert-GitPath -PathValue $PathValue
    if ($path -match '^runtime_remote_training/.*\.latest\.(json|md)$') { return $true }
    if ($path -match '^shared_state/.+\.latest\.(json|md)$') { return $true }
    if ($path -eq 'shared_state/watchdog-repair/MIM_TOD_TASK_REQUEST.latest.json') { return $true }
    if ($path -eq 'tod/data/project-library-index.json') { return $true }
    if ($path -eq 'tod/data/engineering-memory.json') { return $true }
    if ($path -match '^tod/knowledge/engineering-memory/.+\.json$') { return $true }
    return $false
}

$rawStatus = @(& git -C $resolvedRepoRoot status --porcelain=v1 2>$null)
if ($LASTEXITCODE -ne 0) {
    throw 'git status failed.'
}

$items = @()
foreach ($line in $rawStatus) {
    if ([string]::IsNullOrWhiteSpace($line) -or $line.Length -lt 4) { continue }
    $statusCode = $line.Substring(0, 2)
    $pathText = $line.Substring(3).Trim()
    if ($pathText -match ' -> ') {
        $pathText = ($pathText -split ' -> ', 2)[1].Trim()
    }
    $normalizedPath = Convert-GitPath -PathValue $pathText
    $isGenerated = Test-GeneratedRuntimePath -PathValue $normalizedPath
    $items += [pscustomobject]@{
        path = $normalizedPath
        status = $statusCode.Trim()
        classification = if ($isGenerated) { 'generated_runtime_state' } else { 'review_required' }
        clean_action = if ($isGenerated) { 'skip_worktree_local_runtime_churn' } else { 'leave_dirty_for_review' }
    }
}

$generatedItems = @($items | Where-Object { $_.classification -eq 'generated_runtime_state' })
$reviewItems = @($items | Where-Object { $_.classification -ne 'generated_runtime_state' })
$cleanedPaths = @()
$failedCleanPaths = @()

if ($CleanGeneratedRuntime.IsPresent -and $generatedItems.Count -gt 0) {
    foreach ($item in $generatedItems) {
        if ($item.status -eq '??') {
            $candidatePath = Join-Path $resolvedRepoRoot $item.path
            try {
                $resolvedCandidateParent = (Resolve-Path -LiteralPath (Split-Path -Parent $candidatePath) -ErrorAction Stop).Path
                $fullCandidatePath = Join-Path $resolvedCandidateParent (Split-Path -Leaf $candidatePath)
                if (-not $fullCandidatePath.StartsWith($resolvedRepoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                    throw "Refusing to clean path outside repo: $($item.path)"
                }
                if (Test-Path -LiteralPath $fullCandidatePath -PathType Leaf) {
                    Remove-Item -LiteralPath $fullCandidatePath -Force
                    $cleanedPaths += $item.path
                }
            } catch {
                $failedCleanPaths += [pscustomobject]@{
                    path = $item.path
                    error = $_.Exception.Message
                }
            }
        } else {
            & git -C $resolvedRepoRoot update-index --skip-worktree -- $item.path 2>$null
            if ($LASTEXITCODE -eq 0) {
                $cleanedPaths += $item.path
            } else {
                $failedCleanPaths += [pscustomobject]@{
                    path = $item.path
                    error = "git update-index --skip-worktree failed with exit code $LASTEXITCODE"
                }
            }
        }
    }
}

$postStatus = @(& git -C $resolvedRepoRoot status --porcelain=v1 2>$null)
$payload = [ordered]@{
    ok = ($failedCleanPaths.Count -eq 0)
    packet_type = 'tod-sync-cleanliness-v1'
    generated_at = [DateTime]::UtcNow.ToString('o')
    repo_root = $resolvedRepoRoot
    clean_generated_runtime_requested = [bool]$CleanGeneratedRuntime.IsPresent
    dirty_count_before = $items.Count
    generated_runtime_dirty_count = $generatedItems.Count
    review_required_dirty_count = $reviewItems.Count
    cleaned_paths = $cleanedPaths
    failed_clean_paths = $failedCleanPaths
    remaining_dirty_count = $postStatus.Count
    remaining_dirty_paths = @(
        foreach ($line in $postStatus) {
            if ($line.Length -ge 4) { Convert-GitPath -PathValue ($line.Substring(3).Trim()) }
        }
    )
    items = $items
    policy = [ordered]@{
        generated_runtime_state = 'Generated latest telemetry/state should not keep the source tree dirty. Publish it to runtime/shared and history artifacts; do not treat it as code.'
        review_required = 'Code, docs, config, and operator-authored artifacts stay dirty until reviewed, committed, or intentionally reverted.'
        escalation = 'If review_required_dirty_count is greater than zero, MIM should create or update a Studio project/action item instead of silently cleaning it.'
    }
}

$resolvedOutputPath = Join-Path $resolvedRepoRoot $OutputPath
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $resolvedOutputPath) | Out-Null
$payload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resolvedOutputPath -Encoding UTF8

[pscustomobject]$payload

if ($failedCleanPaths.Count -gt 0) {
    exit 1
}
exit 0
