param(
    [string]$Label = "pre-rerun-dispatch",
    [string]$ListenerStageDir = "tod/out/context-sync/listener",
    [string]$OutputRoot = "shared_state/archive/tod-mim-execution-dispatch-baselines",
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

function Get-StringField {
    param(
        [AllowNull()]$InputObject,
        [Parameter(Mandatory = $true)][string]$FieldName
    )

    if ($null -eq $InputObject -or -not $InputObject.PSObject.Properties[$FieldName]) {
        return ''
    }

    return [string]$InputObject.$FieldName
}

function New-ExecutionDispatchSummary {
    param(
        [AllowNull()]$CommandStatus,
        [AllowNull()]$TaskAck,
        [AllowNull()]$TaskResult,
        [AllowNull()]$TaskRequest
    )

    $trigger = if ($CommandStatus -and $CommandStatus.PSObject.Properties['trigger']) { $CommandStatus.trigger } else { $null }
    $listener = if ($CommandStatus -and $CommandStatus.PSObject.Properties['listener']) { $CommandStatus.listener } else { $null }
    $bridgeRuntime = if ($CommandStatus -and $CommandStatus.PSObject.Properties['bridge_runtime']) { $CommandStatus.bridge_runtime } else { $null }
    $currentProcessing = if ($bridgeRuntime -and $bridgeRuntime.PSObject.Properties['current_processing']) { $bridgeRuntime.current_processing } else { $null }
    $commandReadiness = if ($CommandStatus -and $CommandStatus.PSObject.Properties['execution_readiness']) { $CommandStatus.execution_readiness } else { $null }
    $resultReadiness = if ($TaskResult -and $TaskResult.PSObject.Properties['execution_readiness']) { $TaskResult.execution_readiness } else { $null }

    return [pscustomobject]@{
        request_identity = [pscustomobject]@{
            request_task_id = Get-StringField -InputObject $TaskRequest -FieldName 'task_id'
            request_objective_id = Get-StringField -InputObject $TaskRequest -FieldName 'objective_id'
            request_correlation_id = Get-StringField -InputObject $TaskRequest -FieldName 'correlation_id'
            request_sequence = Get-StringField -InputObject $TaskRequest -FieldName 'sequence'
            command_status_request_id = Get-StringField -InputObject $CommandStatus -FieldName 'request_id'
            command_status_task_id = Get-StringField -InputObject $CommandStatus -FieldName 'task_id'
            trigger_task_id = Get-StringField -InputObject $trigger -FieldName 'task_id'
            current_processing_task_id = Get-StringField -InputObject $currentProcessing -FieldName 'task_id'
            ack_task_id = Get-StringField -InputObject $TaskAck -FieldName 'task_id'
            result_task_id = Get-StringField -InputObject $TaskResult -FieldName 'task_id'
        }
        command_status = [pscustomobject]@{
            status = Get-StringField -InputObject $CommandStatus -FieldName 'status'
            detail = Get-StringField -InputObject $CommandStatus -FieldName 'detail'
            action = Get-StringField -InputObject $CommandStatus -FieldName 'action'
            acted_upon = if ($CommandStatus -and $CommandStatus.PSObject.Properties['acted_upon']) { [bool]$CommandStatus.acted_upon } else { $false }
            generated_at = Get-StringField -InputObject $CommandStatus -FieldName 'generated_at'
        }
        execution_gating = [pscustomobject]@{
            command_readiness_status = Get-StringField -InputObject $commandReadiness -FieldName 'status'
            command_readiness_policy = Get-StringField -InputObject $commandReadiness -FieldName 'policy_outcome'
            result_status = Get-StringField -InputObject $TaskResult -FieldName 'status'
            result_execution_mode = Get-StringField -InputObject $TaskResult -FieldName 'execution_mode'
            result_readiness_status = Get-StringField -InputObject $resultReadiness -FieldName 'status'
            result_readiness_policy = Get-StringField -InputObject $resultReadiness -FieldName 'policy_outcome'
            ack_status = Get-StringField -InputObject $TaskAck -FieldName 'status'
        }
        dispatch_attribution = [pscustomobject]@{
            trigger_sequence = Get-StringField -InputObject $trigger -FieldName 'sequence'
            trigger_source_service = Get-StringField -InputObject $trigger -FieldName 'source_service'
            trigger_source_instance_id = Get-StringField -InputObject $trigger -FieldName 'source_instance_id'
            trigger_source_host = Get-StringField -InputObject $trigger -FieldName 'source_host'
            trigger_artifact_sha256 = Get-StringField -InputObject $trigger -FieldName 'artifact_sha256'
            listener_instance_id = Get-StringField -InputObject $listener -FieldName 'instance_id'
            ack_source_instance_id = Get-StringField -InputObject $TaskAck -FieldName 'source_instance_id'
            result_source_instance_id = Get-StringField -InputObject $TaskResult -FieldName 'source_instance_id'
        }
    }
}

$listenerStageAbs = Resolve-LocalPath -PathValue $ListenerStageDir
$outputRootAbs = Resolve-LocalPath -PathValue $OutputRoot
$timestamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ')
$safeLabel = ([regex]::Replace($Label.ToLowerInvariant(), '[^a-z0-9._-]+', '-')).Trim('-')
if ([string]::IsNullOrWhiteSpace($safeLabel)) {
    $safeLabel = 'baseline'
}

$snapshotDir = Join-Path $outputRootAbs ("{0}-{1}" -f $safeLabel, $timestamp)
if ((Test-Path -Path $snapshotDir) -and -not $Force) {
    throw ("Baseline directory already exists: {0}" -f $snapshotDir)
}

New-Item -ItemType Directory -Path $snapshotDir -Force | Out-Null

$artifactMap = [ordered]@{
    task_request = Join-Path $listenerStageAbs 'MIM_TOD_TASK_REQUEST.latest.json'
    command_status = Join-Path $listenerStageAbs 'TOD_MIM_COMMAND_STATUS.latest.json'
    task_ack = Join-Path $listenerStageAbs 'TOD_MIM_TASK_ACK.latest.json'
    task_result = Join-Path $listenerStageAbs 'TOD_MIM_TASK_RESULT.latest.json'
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

$taskRequest = Read-JsonFile -PathValue $copiedArtifacts.task_request
$commandStatus = Read-JsonFile -PathValue $copiedArtifacts.command_status
$taskAck = Read-JsonFile -PathValue $copiedArtifacts.task_ack
$taskResult = Read-JsonFile -PathValue $copiedArtifacts.task_result

$manifest = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    label = $Label
    baseline_id = ("{0}-{1}" -f $safeLabel, $timestamp)
    snapshot_dir = $snapshotDir
    artifacts = [pscustomobject]@{
        task_request = $copiedArtifacts.task_request
        command_status = $copiedArtifacts.command_status
        task_ack = $copiedArtifacts.task_ack
        task_result = $copiedArtifacts.task_result
    }
    summary = New-ExecutionDispatchSummary -CommandStatus $commandStatus -TaskAck $taskAck -TaskResult $taskResult -TaskRequest $taskRequest
}

$manifestPath = Join-Path $snapshotDir 'baseline_manifest.json'
Write-JsonFile -PathValue $manifestPath -Payload $manifest -Depth 20

$currentPointerPath = Join-Path (Resolve-LocalPath -PathValue 'shared_state') 'TOD_MIM_EXECUTION_DISPATCH_BASELINE.current.json'
Write-JsonFile -PathValue $currentPointerPath -Payload $manifest -Depth 20

$manifest | ConvertTo-Json -Depth 20 | Write-Output