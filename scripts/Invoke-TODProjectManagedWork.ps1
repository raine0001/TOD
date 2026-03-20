param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectId,
    [string]$ProjectRoot,
    [string]$RegistryPath = "tod/config/project-registry.json",
    [string]$PriorityPath = "tod/config/project-priority.json",
    [string]$OutputPath,
    [switch]$EmitJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

function Resolve-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return [System.IO.Path]::GetFullPath($PathValue)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $PathValue))
}

function To-Array {
    param($Value)

    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Array]) { return @($Value) }
    return @($Value)
}

function Normalize-RepoPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    return (($PathValue -replace '\\', '/') -replace '/+', '/').Trim('/').Trim()
}

function Find-ProjectRecord {
    param(
        [Parameter(Mandatory = $true)]$Projects,
        [Parameter(Mandatory = $true)][string]$RequestedProjectId
    )

    $needle = $RequestedProjectId.ToLowerInvariant()
    return @($Projects | Where-Object {
        ([string]$_.id).ToLowerInvariant() -eq $needle -or
        ([string]$_.name).ToLowerInvariant() -eq $needle
    }) | Select-Object -First 1
}

function Get-ExecutionMode {
    param(
        [Parameter(Mandatory = $true)]$PriorityConfig,
        [Parameter(Mandatory = $true)]$Project,
        [Parameter(Mandatory = $true)][string]$RequestedProjectId
    )

    $needle = $RequestedProjectId.ToLowerInvariant()
    $match = @($PriorityConfig.execution_order | Where-Object {
        ([string]$_.project_id).ToLowerInvariant() -eq $needle
    }) | Select-Object -First 1

    if ($null -ne $match -and $match.PSObject.Properties['mode']) {
        return [string]$match.mode
    }

    $writeAccess = if ($Project.PSObject.Properties['write_access']) { [string]$Project.write_access } else { '' }
    switch ($writeAccess.ToLowerInvariant()) {
        'review-only' { return 'review-only' }
        'guarded' { return 'guarded-write' }
        default { return 'advisory-first' }
    }
}

function Test-PathPrefixMatch {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)][string]$Prefix
    )

    $pathNorm = (Normalize-RepoPath -PathValue $PathValue).ToLowerInvariant()
    $prefixNorm = (Normalize-RepoPath -PathValue $Prefix).ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($prefixNorm)) { return $false }
    return ($pathNorm -eq $prefixNorm -or $pathNorm.StartsWith($prefixNorm + '/'))
}

function Get-GitChangeEntries {
    param([Parameter(Mandatory = $true)][string]$Root)

    try {
        $null = Get-Command git -ErrorAction Stop
    }
    catch {
        return [pscustomobject]@{ available = $false; entries = @() }
    }

    $statusLines = @()
    try {
        $statusLines = @(git -C $Root status --porcelain=1 --untracked-files=all 2>&1)
        if ($LASTEXITCODE -ne 0) {
            return [pscustomobject]@{ available = $true; entries = @() }
        }
    }
    catch {
        return [pscustomobject]@{ available = $true; entries = @() }
    }

    $entries = @()
    foreach ($line in $statusLines) {
        $text = [string]$line
        if ([string]::IsNullOrWhiteSpace($text) -or $text.Length -lt 4) { continue }

        $statusCode = $text.Substring(0, 2)
        $pathText = $text.Substring(3).Trim()
        if ($pathText -match ' -> ') {
            $pathText = ($pathText -split ' -> ')[-1]
        }

        $entries += [pscustomobject]@{
            status = if ($statusCode -eq '??') { 'untracked' } else { 'modified' }
            status_code = $statusCode
            path = (Normalize-RepoPath -PathValue ($pathText.Trim('"')))
        }
    }

    return [pscustomobject]@{ available = $true; entries = @($entries) }
}

function Get-ManagedWorkConfig {
    param([Parameter(Mandatory = $true)]$Project)

    $config = if ($Project.PSObject.Properties['managed_work']) { $Project.managed_work } else { $null }

    $qaPatterns = @('scripts/qa_', 'qa/', 'tools/qa_')
    $assetPatterns = @('static/images/', 'assets/', 'media/', 'images/', 'video/', 'audio/')
    $rootDocNames = @('README.md', 'TOD.md', 'AGENTS.md')

    if ($null -ne $config -and $config.PSObject.Properties['path_classification']) {
        $pathClass = $config.path_classification
        if ($pathClass.PSObject.Properties['qa_artifact_patterns']) {
            $qaPatterns = @($qaPatterns + (To-Array -Value $pathClass.qa_artifact_patterns))
        }
        if ($pathClass.PSObject.Properties['asset_candidate_patterns']) {
            $assetPatterns = @($assetPatterns + (To-Array -Value $pathClass.asset_candidate_patterns))
        }
        if ($pathClass.PSObject.Properties['root_doc_names']) {
            $rootDocNames = @($rootDocNames + (To-Array -Value $pathClass.root_doc_names))
        }
    }

    return [pscustomobject]@{
        qa_artifact_patterns = @($qaPatterns | Select-Object -Unique)
        asset_candidate_patterns = @($assetPatterns | Select-Object -Unique)
        root_doc_names = @($rootDocNames | Select-Object -Unique)
    }
}

function Classify-ChangeEntry {
    param(
        [Parameter(Mandatory = $true)]$Project,
        [Parameter(Mandatory = $true)]$ManagedWorkConfig,
        [Parameter(Mandatory = $true)]$Entry
    )

    $path = [string]$Entry.path
    $status = [string]$Entry.status
    $allowedPaths = if ($Project.boundaries.PSObject.Properties['allowed_paths']) { To-Array -Value $Project.boundaries.allowed_paths } else { @() }
    $blockedPaths = if ($Project.boundaries.PSObject.Properties['blocked_paths']) { To-Array -Value $Project.boundaries.blocked_paths } else { @() }

    $inAllowedScope = (@($allowedPaths).Count -eq 0)
    if (-not $inAllowedScope) {
        foreach ($allowedPrefix in $allowedPaths) {
            if (Test-PathPrefixMatch -PathValue $path -Prefix ([string]$allowedPrefix)) {
                $inAllowedScope = $true
                break
            }
        }
    }

    $inBlockedScope = $false
    foreach ($blockedPrefix in $blockedPaths) {
        if (Test-PathPrefixMatch -PathValue $path -Prefix ([string]$blockedPrefix)) {
            $inBlockedScope = $true
            break
        }
    }

    $fileName = [System.IO.Path]::GetFileName($path)
    $extension = [System.IO.Path]::GetExtension($path).ToLowerInvariant()
    $isRootDoc = @($ManagedWorkConfig.root_doc_names | Where-Object { ([string]$_).ToLowerInvariant() -eq $fileName.ToLowerInvariant() }).Count -gt 0

    $qaArtifact = $false
    foreach ($pattern in $ManagedWorkConfig.qa_artifact_patterns) {
        if (Test-PathPrefixMatch -PathValue $path -Prefix ([string]$pattern)) {
            $qaArtifact = $true
            break
        }
    }

    $assetCandidate = $false
    if ($status -eq 'untracked') {
        foreach ($pattern in $ManagedWorkConfig.asset_candidate_patterns) {
            if (Test-PathPrefixMatch -PathValue $path -Prefix ([string]$pattern)) {
                $assetCandidate = $true
                break
            }
        }
        if (-not $assetCandidate -and @('.png', '.jpg', '.jpeg', '.webp', '.gif', '.mp4', '.mov', '.wav', '.mp3').Contains($extension)) {
            $assetCandidate = $true
        }
    }

    $classification = 'manual_review'
    $reason = 'Path does not yet match a reusable managed-work rule.'
    $recommendedAction = 'Review manually before including the file in a TOD-managed loop.'

    if ($inBlockedScope) {
        $classification = 'blocked_scope_change'
        $reason = 'Path falls under a blocked project boundary.'
        $recommendedAction = 'Do not mutate automatically; escalate for human review.'
    }
    elseif ($qaArtifact) {
        $classification = 'qa_support_artifact'
        $reason = 'File matches a QA/support pattern used as non-blocking evidence.'
        $recommendedAction = 'Keep separate from the main product patch unless QA policy is being promoted.'
    }
    elseif ($assetCandidate) {
        $classification = 'asset_candidate'
        $reason = 'Untracked asset should be confirmed as shipped product content before inclusion.'
        $recommendedAction = 'Keep separate until the feature scope explicitly requires the asset.'
    }
    elseif ($inAllowedScope -or $isRootDoc) {
        $classification = 'managed_product_patch'
        $reason = 'File is inside project write scope or is a project-level handoff doc.'
        $recommendedAction = 'Treat as the active TOD-managed patch scope.'
    }

    return [pscustomobject]@{
        path = $path
        status = $status
        in_allowed_scope = $inAllowedScope
        in_blocked_scope = $inBlockedScope
        classification = $classification
        reason = $reason
        recommended_action = $recommendedAction
    }
}

$resolvedRegistryPath = Resolve-LocalPath -PathValue $RegistryPath
$resolvedPriorityPath = Resolve-LocalPath -PathValue $PriorityPath

$registry = Get-Content -Path $resolvedRegistryPath -Raw | ConvertFrom-Json
$priority = Get-Content -Path $resolvedPriorityPath -Raw | ConvertFrom-Json
$project = Find-ProjectRecord -Projects (To-Array -Value $registry.projects) -RequestedProjectId $ProjectId
if ($null -eq $project) {
    throw "Project not found in registry: $ProjectId"
}

$effectiveProjectId = [string]$project.id
$resolvedProjectRoot = if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    Resolve-LocalPath -PathValue ([string]$project.path)
}
else {
    Resolve-LocalPath -PathValue $ProjectRoot
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = ("shared_state/agentmim/{0}_managed_work.latest.json" -f $effectiveProjectId)
}
$resolvedOutputPath = Resolve-LocalPath -PathValue $OutputPath

$executionMode = Get-ExecutionMode -PriorityConfig $priority -Project $project -RequestedProjectId $effectiveProjectId
$verificationCommands = if ($project.PSObject.Properties['test_commands']) { To-Array -Value $project.test_commands } else { @() }
$managedWorkConfig = Get-ManagedWorkConfig -Project $project
$gitState = Get-GitChangeEntries -Root $resolvedProjectRoot

$classifiedChanges = @()
foreach ($entry in @($gitState.entries)) {
    $classifiedChanges += Classify-ChangeEntry -Project $project -ManagedWorkConfig $managedWorkConfig -Entry $entry
}

$managedPatchFiles = @($classifiedChanges | Where-Object { [string]$_.classification -eq 'managed_product_patch' })
$supportArtifacts = @($classifiedChanges | Where-Object {
    ([string]$_.classification -eq 'qa_support_artifact') -or
    ([string]$_.classification -eq 'asset_candidate')
})
$blockedChanges = @($classifiedChanges | Where-Object { [string]$_.classification -eq 'blocked_scope_change' })
$manualReviewFiles = @($classifiedChanges | Where-Object { [string]$_.classification -eq 'manual_review' })

$controlState = 'verification_command_missing'
if (@($verificationCommands).Count -gt 0) {
    $controlState = 'clean_or_no_pending_changes'
    if (@($blockedChanges).Count -gt 0) {
        $controlState = 'blocked_scope_review_needed'
    }
    elseif (@($manualReviewFiles).Count -gt 0) {
        $controlState = 'manual_review_needed'
    }
    elseif ($executionMode -eq 'review-only' -and @($managedPatchFiles).Count -gt 0) {
        $controlState = 'review_only_plan_required'
    }
    elseif ($executionMode -eq 'advisory-first' -and @($managedPatchFiles).Count -gt 0 -and @($supportArtifacts).Count -gt 0) {
        $controlState = 'advisory_with_artifact_separation'
    }
    elseif ($executionMode -eq 'advisory-first' -and @($managedPatchFiles).Count -gt 0) {
        $controlState = 'advisory_plan_ready'
    }
    elseif (@($managedPatchFiles).Count -gt 0 -and @($supportArtifacts).Count -gt 0) {
        $controlState = 'ready_with_artifact_separation'
    }
    elseif (@($managedPatchFiles).Count -gt 0) {
        $controlState = 'ready_for_managed_patch'
    }
    elseif (@($supportArtifacts).Count -gt 0) {
        $controlState = 'qa_or_artifacts_only'
    }
}

$recommendedActions = @()
if (@($verificationCommands).Count -eq 0) {
    $recommendedActions += 'Add at least one verification command to the project registry before TOD attempts a managed loop.'
}
if (@($blockedChanges).Count -gt 0) {
    $recommendedActions += 'Remove blocked-scope files from automated mutation and escalate them for review.'
}
if (@($manualReviewFiles).Count -gt 0) {
    $recommendedActions += 'Resolve unclassified files before treating the repo delta as a clean TOD-managed patch set.'
}
if ($executionMode -eq 'review-only' -and @($managedPatchFiles).Count -gt 0) {
    $recommendedActions += 'Stay in review-only mode; TOD should summarize and plan but not patch directly.'
}
elseif ($executionMode -eq 'advisory-first' -and @($managedPatchFiles).Count -gt 0) {
    $recommendedActions += 'Use the managed patch set to build an implementation plan, but keep direct mutation blocked until the mode is elevated.'
}
elseif (@($managedPatchFiles).Count -gt 0) {
    $recommendedActions += 'Use the managed patch file set as the active TOD edit scope after the verification command passes.'
}
if (@($supportArtifacts).Count -gt 0) {
    $recommendedActions += 'Keep QA/support artifacts separate from the main product patch unless the current task explicitly promotes them.'
}
if (@($recommendedActions).Count -eq 0) {
    $recommendedActions += 'No pending managed work was identified; the project appears ready for the next TOD-directed task.'
}

$report = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    source = 'tod-project-managed-work-v1'
    project_id = $effectiveProjectId
    project_name = [string]$project.name
    project_root = $resolvedProjectRoot
    execution_mode = $executionMode
    write_access = if ($project.PSObject.Properties['write_access']) { [string]$project.write_access } else { '' }
    risk_level = if ($project.PSObject.Properties['risk_level']) { [string]$project.risk_level } else { '' }
    verification_commands = @($verificationCommands)
    control_state = $controlState
    policy = [pscustomobject]@{
        allowed_paths = if ($project.boundaries.PSObject.Properties['allowed_paths']) { To-Array -Value $project.boundaries.allowed_paths } else { @() }
        blocked_paths = if ($project.boundaries.PSObject.Properties['blocked_paths']) { To-Array -Value $project.boundaries.blocked_paths } else { @() }
        notes = if ($project.boundaries.PSObject.Properties['notes']) { [string]$project.boundaries.notes } else { '' }
    }
    patch_scope = [pscustomobject]@{
        managed_product_patch = @($managedPatchFiles)
        support_or_reference_artifacts = @($supportArtifacts)
        blocked_scope = @($blockedChanges)
        manual_review = @($manualReviewFiles)
    }
    facts = [pscustomobject]@{
        pending_changes = @($classifiedChanges).Count
        managed_product_patch_count = @($managedPatchFiles).Count
        support_or_reference_artifact_count = @($supportArtifacts).Count
        blocked_scope_count = @($blockedChanges).Count
        manual_review_count = @($manualReviewFiles).Count
    }
    recommended_actions = @($recommendedActions)
}

$outputDir = Split-Path -Parent $resolvedOutputPath
if (-not (Test-Path -Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$report | ConvertTo-Json -Depth 20 | Set-Content -Path $resolvedOutputPath

if ($EmitJson) {
    $report | ConvertTo-Json -Depth 12 | Write-Output
}
else {
    $report
}