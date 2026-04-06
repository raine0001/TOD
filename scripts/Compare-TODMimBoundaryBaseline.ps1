param(
    [string]$BaselineManifestPath = "shared_state/TOD_MIM_PRE_REPUBLISH_BASELINE.current.json",
    [string]$CurrentBridgeSmokePath = "shared_state/TOD_MIM_BRIDGE_SMOKE.latest.json",
    [string]$CurrentRemoteBoundaryPath = "shared_state/TOD_MIM_REMOTE_BOUNDARY_DIAGNOSTIC.latest.json",
    [string]$CurrentRemoteProbePath = "shared_state/TOD_MIM_REMOTE_REQUEST_PROBE.latest.json",
    [string]$OutputPath = "shared_state/TOD_MIM_BOUNDARY_DELTA.latest.json"
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

function Read-JsonFile {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    return (Get-Content -Path $PathValue -Raw | ConvertFrom-Json)
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

function Get-RequestField {
    param(
        [AllowNull()]$InputObject,
        [Parameter(Mandatory = $true)][string]$FieldName
    )

    if ($null -eq $InputObject -or -not $InputObject.PSObject.Properties[$FieldName]) {
        return ''
    }

    return [string]$InputObject.$FieldName
}

function New-ScalarDelta {
    param(
        [string]$Name,
        [string]$Before,
        [string]$After
    )

    return [pscustomobject]@{
        field = $Name
        before = $Before
        after = $After
        changed = -not [string]::Equals([string]$Before, [string]$After, [System.StringComparison]::Ordinal)
    }
}

$baselineManifestAbs = Resolve-LocalPath -PathValue $BaselineManifestPath
$currentBridgeSmokeAbs = Resolve-LocalPath -PathValue $CurrentBridgeSmokePath
$currentRemoteBoundaryAbs = Resolve-LocalPath -PathValue $CurrentRemoteBoundaryPath
$currentRemoteProbeAbs = Resolve-LocalPath -PathValue $CurrentRemoteProbePath
$outputAbs = Resolve-LocalPath -PathValue $OutputPath

$baseline = Read-JsonFile -PathValue $baselineManifestAbs
$bridgeSmoke = Read-JsonFile -PathValue $currentBridgeSmokeAbs
$remoteBoundary = Read-JsonFile -PathValue $currentRemoteBoundaryAbs
$remoteProbe = Read-JsonFile -PathValue $currentRemoteProbeAbs

$baselineIdentity = $baseline.summary.request_identity
$currentCanonical = $bridgeSmoke.canonical_request
$currentRemoteSurface = $currentCanonical.remote_surface

$requestIdentityDelta = @(
    New-ScalarDelta -Name 'expected_objective_id' -Before (Get-RequestField -InputObject $baselineIdentity -FieldName 'expected_objective_id') -After (Get-RequestField -InputObject $currentCanonical -FieldName 'expected_objective_id')
    New-ScalarDelta -Name 'remote_objective_id' -Before (Get-RequestField -InputObject $baselineIdentity -FieldName 'remote_objective_id') -After (Get-RequestField -InputObject $currentRemoteSurface -FieldName 'objective_id')
    New-ScalarDelta -Name 'remote_task_id' -Before (Get-RequestField -InputObject $baselineIdentity -FieldName 'remote_task_id') -After (Get-RequestField -InputObject $currentRemoteSurface -FieldName 'task_id')
    New-ScalarDelta -Name 'remote_sequence' -Before (Get-RequestField -InputObject $baselineIdentity -FieldName 'remote_sequence') -After (Get-RequestField -InputObject $currentRemoteSurface -FieldName 'sequence')
    New-ScalarDelta -Name 'remote_sha256' -Before (Get-RequestField -InputObject $baselineIdentity -FieldName 'remote_sha256') -After (Get-RequestField -InputObject $currentRemoteSurface -FieldName 'sha256')
    New-ScalarDelta -Name 'remote_inode' -Before (Get-RequestField -InputObject $baselineIdentity -FieldName 'remote_inode') -After $(if ($currentRemoteSurface.PSObject.Properties['ls_inode']) { [string]$currentRemoteSurface.ls_inode } elseif ($currentRemoteSurface.PSObject.Properties['inode']) { [string]$currentRemoteSurface.inode } else { '' })
)

$classificationDelta = @(
    New-ScalarDelta -Name 'smoke_classification' -Before (Get-RequestField -InputObject $baseline.summary -FieldName 'smoke_classification') -After (Get-RequestField -InputObject $bridgeSmoke -FieldName 'classification')
    New-ScalarDelta -Name 'boundary_classification' -Before (Get-RequestField -InputObject $baseline.summary -FieldName 'boundary_classification') -After $(if ($remoteBoundary.PSObject.Properties['remote_boundary']) { Get-RequestField -InputObject $remoteBoundary.remote_boundary -FieldName 'classification' } else { '' })
    New-ScalarDelta -Name 'boundary_recommendation' -Before (Get-RequestField -InputObject $baseline.summary -FieldName 'boundary_recommendation') -After $(if ($remoteBoundary.PSObject.Properties['remote_boundary']) { Get-RequestField -InputObject $remoteBoundary.remote_boundary -FieldName 'recommendation' } else { '' })
)

$delta = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    baseline_id = if ($baseline.PSObject.Properties['baseline_id']) { [string]$baseline.baseline_id } else { '' }
    baseline_manifest_path = $baselineManifestAbs
    current = [pscustomobject]@{
        bridge_smoke_path = $currentBridgeSmokeAbs
        remote_boundary_path = $currentRemoteBoundaryAbs
        remote_probe_path = $currentRemoteProbeAbs
    }
    summary = [pscustomobject]@{
        request_identity_changed = (@($requestIdentityDelta | Where-Object { [bool]$_.changed }).Count -gt 0)
        boundary_classification_changed = (@($classificationDelta | Where-Object { [bool]$_.changed }).Count -gt 0)
        current_smoke_classification = Get-RequestField -InputObject $bridgeSmoke -FieldName 'classification'
        current_boundary_classification = if ($remoteBoundary.PSObject.Properties['remote_boundary']) { Get-RequestField -InputObject $remoteBoundary.remote_boundary -FieldName 'classification' } else { '' }
        current_remote_probe_generated_at = Get-RequestField -InputObject $remoteProbe -FieldName 'emitted_at'
    }
    request_identity_delta = @($requestIdentityDelta)
    boundary_classification_delta = @($classificationDelta)
}

Write-JsonFile -PathValue $outputAbs -Payload $delta -Depth 20
$delta | ConvertTo-Json -Depth 20 | Write-Output