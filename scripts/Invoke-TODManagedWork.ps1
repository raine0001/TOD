param(
    [string]$ProjectRoot = 'E:/TOD',
    [string]$OutputPath = 'shared_state/agentmim/tod_managed_work.latest.json',
    [string]$CleanupOutputPath = 'shared_state/agentmim/tod_managed_work_cleanup.latest.json',
    [switch]$ApplyCleanup,
    [switch]$EmitJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot

function Resolve-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return [System.IO.Path]::GetFullPath($PathValue)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $PathValue))
}

function Ensure-Directory {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if (-not (Test-Path -Path $PathValue)) {
        New-Item -ItemType Directory -Path $PathValue -Force | Out-Null
    }
}

function Write-Utf8NoBomJson {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)]$Payload,
        [int]$Depth = 20
    )

    $dir = Split-Path -Parent $PathValue
    if (-not [string]::IsNullOrWhiteSpace($dir)) {
        Ensure-Directory -PathValue $dir
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $json = ($Payload | ConvertTo-Json -Depth $Depth) -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($PathValue, $json, $utf8NoBom)
}

function Get-JsonReport {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)]$ArgumentMap
    )

    $jsonText = (& $ScriptPath @ArgumentMap | Out-String)
    return ($jsonText | ConvertFrom-Json)
}

function Get-TodManagedWorkPolicy {
    param([Parameter(Mandatory = $true)]$ManagedWorkReport)

    $timestamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
    $archiveRoot = Resolve-LocalPath -PathValue ('shared_state/agentmim/managed-work-archives/' + $timestamp)

    $blockedTrackedFiles = @()
    foreach ($entry in @($ManagedWorkReport.patch_scope.blocked_scope)) {
        if ([string]$entry.status -ne 'untracked') {
            $blockedTrackedFiles += [pscustomobject]@{
                path = [string]$entry.path
                action = 'archive_then_restore_head'
                archive_path = Join-Path $archiveRoot ([string]$entry.path -replace '/', [System.IO.Path]::DirectorySeparatorChar)
            }
        }
    }

    $supportCleanupFiles = @()
    foreach ($entry in @($ManagedWorkReport.patch_scope.support_or_reference_artifacts)) {
        if ([string]$entry.status -eq 'untracked') {
            $supportCleanupFiles += [pscustomobject]@{
                path = [string]$entry.path
                action = 'remove_untracked_support_artifact'
            }
        }
    }

    return [pscustomobject]@{
        source = 'tod-managed-work-policy-v1'
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        cleanup_strategy = [pscustomobject]@{
            archive_root = $archiveRoot
            blocked_tracked_files = @($blockedTrackedFiles)
            support_cleanup_files = @($supportCleanupFiles)
        }
        policy = [pscustomobject]@{
            objective = 'Keep TOD product edits in the managed patch scope while preserving tracked runtime memory as archived evidence and restoring those tracked state files to HEAD before the next write loop.'
            steps = @(
                'Generate the managed-work classification report.',
                'Archive each tracked blocked-scope engineering-memory file before cleanup.',
                'Restore archived blocked-scope files to the git HEAD version.',
                'Delete only untracked support artifacts that match TOD cleanup policy.',
                'Re-run managed-work classification and treat the updated report as the next TOD work boundary.'
            )
        }
    }
}

function Save-BlockedFileArchives {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRootPath,
        [Parameter(Mandatory = $true)]$BlockedFiles
    )

    $archived = @()
    foreach ($entry in @($BlockedFiles)) {
        $sourcePath = Join-Path $ProjectRootPath ([string]$entry.path -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $archivePath = [string]$entry.archive_path
        $archiveDir = Split-Path -Parent $archivePath
        Ensure-Directory -PathValue $archiveDir
        Copy-Item -Path $sourcePath -Destination $archivePath -Force
        $archived += [pscustomobject]@{
            path = [string]$entry.path
            archive_path = $archivePath
        }
    }

    return @($archived)
}

function Restore-TrackedFilesFromHead {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRootPath,
        [Parameter(Mandatory = $true)]$BlockedFiles
    )

    $paths = @($BlockedFiles | ForEach-Object { [string]$_.path })
    if (@($paths).Count -eq 0) {
        return
    }

    & git -C $ProjectRootPath restore --source=HEAD -- @paths
    if ($LASTEXITCODE -ne 0) {
        throw 'git_restore_failed_for_blocked_scope_files'
    }
}

function Remove-UntrackedSupportArtifacts {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRootPath,
        [Parameter(Mandatory = $true)]$SupportFiles
    )

    $removed = @()
    foreach ($entry in @($SupportFiles)) {
        $targetPath = Join-Path $ProjectRootPath ([string]$entry.path -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        if (Test-Path -Path $targetPath) {
            Remove-Item -Path $targetPath -Force -Recurse
            $removed += [string]$entry.path
        }
    }

    return @($removed)
}

$delegateScript = Join-Path $PSScriptRoot 'Invoke-TODProjectManagedWork.ps1'
if (-not (Test-Path -Path $delegateScript -PathType Leaf)) {
    throw ('Missing managed-work delegate script: {0}' -f $delegateScript)
}

$resolvedProjectRoot = Resolve-LocalPath -PathValue $ProjectRoot
$resolvedOutputPath = Resolve-LocalPath -PathValue $OutputPath
$resolvedCleanupOutputPath = Resolve-LocalPath -PathValue $CleanupOutputPath

$args = @{
    ProjectId = 'tod'
    ProjectRoot = $resolvedProjectRoot
    OutputPath = $resolvedOutputPath
    EmitJson = $true
}
$managedWorkReport = Get-JsonReport -ScriptPath $delegateScript -ArgumentMap $args
$policy = Get-TodManagedWorkPolicy -ManagedWorkReport $managedWorkReport

$cleanupReport = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    source = 'tod-managed-work-cleanup-v1'
    policy = $policy
    action = [pscustomobject]@{
        requested = [bool]$ApplyCleanup
        applied = $false
        archived_blocked_files = @()
        restored_blocked_files = @()
        removed_support_artifacts = @()
    }
    before = $managedWorkReport
    after = $null
}

if ($ApplyCleanup) {
    $archivedFiles = Save-BlockedFileArchives -ProjectRootPath $resolvedProjectRoot -BlockedFiles $policy.cleanup_strategy.blocked_tracked_files
    Restore-TrackedFilesFromHead -ProjectRootPath $resolvedProjectRoot -BlockedFiles $policy.cleanup_strategy.blocked_tracked_files
    $removedSupportArtifacts = Remove-UntrackedSupportArtifacts -ProjectRootPath $resolvedProjectRoot -SupportFiles $policy.cleanup_strategy.support_cleanup_files

    $cleanupReport.action.applied = $true
    $cleanupReport.action.archived_blocked_files = @($archivedFiles)
    $cleanupReport.action.restored_blocked_files = @($policy.cleanup_strategy.blocked_tracked_files | ForEach-Object { [string]$_.path })
    $cleanupReport.action.removed_support_artifacts = @($removedSupportArtifacts)

    $managedWorkReport = Get-JsonReport -ScriptPath $delegateScript -ArgumentMap $args
    $cleanupReport.after = $managedWorkReport
}

Write-Utf8NoBomJson -PathValue $resolvedCleanupOutputPath -Payload $cleanupReport -Depth 30

if ($EmitJson) {
    $managedWorkReport | ConvertTo-Json -Depth 20 | Write-Output
}
else {
    $managedWorkReport
}