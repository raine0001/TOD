param(
    [string]$Label = "pre-republish",
    [string]$SharedStateDir = "shared_state",
    [string]$ListenerStageDir = "tod/out/context-sync/listener",
    [string]$OutputRoot = "shared_state/archive/tod-mim-boundary-baselines",
    [switch]$Force
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

function Write-JsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)]$Payload,
        [int]$Depth = 20
    )

    $dir = Split-Path -Parent $PathValue
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($PathValue, ($Payload | ConvertTo-Json -Depth $Depth), $utf8NoBom)
}

function Read-JsonFile {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    return (Get-Content -Path $PathValue -Raw | ConvertFrom-Json)
}

function Copy-Artifact {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$DestinationPath
    )

    $destDir = Split-Path -Parent $DestinationPath
    if (-not (Test-Path -Path $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    Copy-Item -Path $SourcePath -Destination $DestinationPath -Force
}

function Get-CanonicalRequestSummary {
    param([AllowNull()]$BridgeSmoke)

    if ($null -eq $BridgeSmoke -or -not $BridgeSmoke.PSObject.Properties['canonical_request']) {
        return $null
    }

    $request = $BridgeSmoke.canonical_request
    $remoteSurface = if ($request.PSObject.Properties['remote_surface']) { $request.remote_surface } else { $null }
    $localMirror = if ($request.PSObject.Properties['local_listener_mirror']) { $request.local_listener_mirror } else { $null }

    return [pscustomobject]@{
        expected_objective_id = if ($request.PSObject.Properties['expected_objective_id']) { [string]$request.expected_objective_id } else { '' }
        remote_objective_id = if ($remoteSurface -and $remoteSurface.PSObject.Properties['objective_id']) { [string]$remoteSurface.objective_id } else { '' }
        remote_task_id = if ($remoteSurface -and $remoteSurface.PSObject.Properties['task_id']) { [string]$remoteSurface.task_id } else { '' }
        remote_sequence = if ($remoteSurface -and $remoteSurface.PSObject.Properties['sequence']) { [string]$remoteSurface.sequence } else { '' }
        remote_sha256 = if ($remoteSurface -and $remoteSurface.PSObject.Properties['sha256']) { [string]$remoteSurface.sha256 } else { '' }
        remote_inode = if ($remoteSurface -and $remoteSurface.PSObject.Properties['ls_inode']) { [string]$remoteSurface.ls_inode } elseif ($remoteSurface -and $remoteSurface.PSObject.Properties['inode']) { [string]$remoteSurface.inode } else { '' }
        local_objective_id = if ($localMirror -and $localMirror.PSObject.Properties['objective_id']) { [string]$localMirror.objective_id } else { '' }
        local_task_id = if ($localMirror -and $localMirror.PSObject.Properties['task_id']) { [string]$localMirror.task_id } else { '' }
        local_sequence = if ($localMirror -and $localMirror.PSObject.Properties['sequence']) { [string]$localMirror.sequence } else { '' }
        local_sha256 = if ($localMirror -and $localMirror.PSObject.Properties['sha256']) { [string]$localMirror.sha256 } else { '' }
    }
}

$sharedStateAbs = Resolve-LocalPath -PathValue $SharedStateDir
$listenerStageAbs = Resolve-LocalPath -PathValue $ListenerStageDir
$outputRootAbs = Resolve-LocalPath -PathValue $OutputRoot

$timestamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssfffZ")
$safeLabel = ([regex]::Replace($Label.ToLowerInvariant(), "[^a-z0-9._-]+", "-")).Trim('-')
if ([string]::IsNullOrWhiteSpace($safeLabel)) {
    $safeLabel = "baseline"
}

$snapshotDir = Join-Path $outputRootAbs ("{0}-{1}" -f $safeLabel, $timestamp)
if ((Test-Path -Path $snapshotDir) -and -not $Force) {
    throw ("Baseline directory already exists: {0}" -f $snapshotDir)
}

New-Item -ItemType Directory -Path $snapshotDir -Force | Out-Null

$artifactMap = [ordered]@{
    bridge_smoke = Join-Path $sharedStateAbs "TOD_MIM_BRIDGE_SMOKE.latest.json"
    remote_boundary = Join-Path $sharedStateAbs "TOD_MIM_REMOTE_BOUNDARY_DIAGNOSTIC.latest.json"
    remote_probe = Join-Path $sharedStateAbs "TOD_MIM_REMOTE_REQUEST_PROBE.latest.json"
    local_listener_request = Join-Path $listenerStageAbs "MIM_TOD_TASK_REQUEST.latest.json"
}

$copiedArtifacts = @{}
foreach ($entry in $artifactMap.GetEnumerator()) {
    if (-not (Test-Path -Path $entry.Value -PathType Leaf)) {
        throw ("Required artifact missing: {0}" -f $entry.Value)
    }

    $destinationPath = Join-Path $snapshotDir (("{0}.json" -f $entry.Key))
    Copy-Artifact -SourcePath $entry.Value -DestinationPath $destinationPath
    $copiedArtifacts[$entry.Key] = $destinationPath
}

$bridgeSmoke = Read-JsonFile -PathValue $copiedArtifacts.bridge_smoke
$remoteBoundary = Read-JsonFile -PathValue $copiedArtifacts.remote_boundary
$remoteProbe = Read-JsonFile -PathValue $copiedArtifacts.remote_probe

$manifest = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    label = $Label
    baseline_id = ("{0}-{1}" -f $safeLabel, $timestamp)
    snapshot_dir = $snapshotDir
    artifacts = [pscustomobject]@{
        bridge_smoke = $copiedArtifacts.bridge_smoke
        remote_boundary = $copiedArtifacts.remote_boundary
        remote_probe = $copiedArtifacts.remote_probe
        local_listener_request = $copiedArtifacts.local_listener_request
    }
    summary = [pscustomobject]@{
        smoke_classification = if ($bridgeSmoke.PSObject.Properties['classification']) { [string]$bridgeSmoke.classification } else { '' }
        smoke_failure_modes = @($bridgeSmoke.failure_modes)
        boundary_classification = if ($remoteBoundary.PSObject.Properties['remote_boundary'] -and $remoteBoundary.remote_boundary.PSObject.Properties['classification']) { [string]$remoteBoundary.remote_boundary.classification } else { '' }
        boundary_recommendation = if ($remoteBoundary.PSObject.Properties['remote_boundary'] -and $remoteBoundary.remote_boundary.PSObject.Properties['recommendation']) { [string]$remoteBoundary.remote_boundary.recommendation } else { '' }
        request_identity = Get-CanonicalRequestSummary -BridgeSmoke $bridgeSmoke
        remote_probe_generated_at = if ($remoteProbe.PSObject.Properties['emitted_at']) { [string]$remoteProbe.emitted_at } else { '' }
    }
}

$manifestPath = Join-Path $snapshotDir 'baseline_manifest.json'
Write-JsonFile -PathValue $manifestPath -Payload $manifest -Depth 20

$currentPointerPath = Join-Path $sharedStateAbs 'TOD_MIM_PRE_REPUBLISH_BASELINE.current.json'
Write-JsonFile -PathValue $currentPointerPath -Payload $manifest -Depth 20

$manifest | ConvertTo-Json -Depth 20 | Write-Output