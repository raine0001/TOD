param(
    [string]$BaselineManifestPath = 'shared_state/TOD_MIM_EXECUTION_DISPATCH_BASELINE.current.json',
    [string]$ListenerStageDir = 'tod/out/context-sync/listener',
    [string]$OutputPath = 'shared_state/TOD_MIM_EXECUTION_DISPATCH_DELTA.latest.json'
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

function New-ScalarDelta {
    param(
        [string]$Field,
        [string]$Before,
        [string]$After
    )

    return [pscustomobject]@{
        field = $Field
        before = $Before
        after = $After
        changed = -not [string]::Equals([string]$Before, [string]$After, [System.StringComparison]::Ordinal)
    }
}

$baselineManifestAbs = Resolve-LocalPath -PathValue $BaselineManifestPath
$listenerStageAbs = Resolve-LocalPath -PathValue $ListenerStageDir
$outputAbs = Resolve-LocalPath -PathValue $OutputPath

$baseline = Read-JsonFile -PathValue $baselineManifestAbs
$baselineSummary = $baseline.summary
$taskRequest = Read-JsonFile -PathValue (Join-Path $listenerStageAbs 'MIM_TOD_TASK_REQUEST.latest.json')
$commandStatus = Read-JsonFile -PathValue (Join-Path $listenerStageAbs 'TOD_MIM_COMMAND_STATUS.latest.json')
$taskAck = Read-JsonFile -PathValue (Join-Path $listenerStageAbs 'TOD_MIM_TASK_ACK.latest.json')
$taskResult = Read-JsonFile -PathValue (Join-Path $listenerStageAbs 'TOD_MIM_TASK_RESULT.latest.json')

$currentSummary = [pscustomobject]@{
    request_identity = [pscustomobject]@{
        request_task_id = Get-StringField -InputObject $taskRequest -FieldName 'task_id'
        request_objective_id = Get-StringField -InputObject $taskRequest -FieldName 'objective_id'
        request_correlation_id = Get-StringField -InputObject $taskRequest -FieldName 'correlation_id'
        request_sequence = Get-StringField -InputObject $taskRequest -FieldName 'sequence'
        command_status_request_id = Get-StringField -InputObject $commandStatus -FieldName 'request_id'
        command_status_task_id = Get-StringField -InputObject $commandStatus -FieldName 'task_id'
        trigger_task_id = if ($commandStatus.PSObject.Properties['trigger']) { Get-StringField -InputObject $commandStatus.trigger -FieldName 'task_id' } else { '' }
        current_processing_task_id = if ($commandStatus.PSObject.Properties['bridge_runtime'] -and $commandStatus.bridge_runtime.PSObject.Properties['current_processing']) { Get-StringField -InputObject $commandStatus.bridge_runtime.current_processing -FieldName 'task_id' } else { '' }
        ack_task_id = Get-StringField -InputObject $taskAck -FieldName 'task_id'
        result_task_id = Get-StringField -InputObject $taskResult -FieldName 'task_id'
    }
    command_status = [pscustomobject]@{
        status = Get-StringField -InputObject $commandStatus -FieldName 'status'
        detail = Get-StringField -InputObject $commandStatus -FieldName 'detail'
        action = Get-StringField -InputObject $commandStatus -FieldName 'action'
        acted_upon = if ($commandStatus.PSObject.Properties['acted_upon']) { [string][bool]$commandStatus.acted_upon } else { 'False' }
        generated_at = Get-StringField -InputObject $commandStatus -FieldName 'generated_at'
    }
    execution_gating = [pscustomobject]@{
        command_readiness_status = if ($commandStatus.PSObject.Properties['execution_readiness']) { Get-StringField -InputObject $commandStatus.execution_readiness -FieldName 'status' } else { '' }
        command_readiness_policy = if ($commandStatus.PSObject.Properties['execution_readiness']) { Get-StringField -InputObject $commandStatus.execution_readiness -FieldName 'policy_outcome' } else { '' }
        result_status = Get-StringField -InputObject $taskResult -FieldName 'status'
        result_execution_mode = Get-StringField -InputObject $taskResult -FieldName 'execution_mode'
        result_readiness_status = if ($taskResult.PSObject.Properties['execution_readiness']) { Get-StringField -InputObject $taskResult.execution_readiness -FieldName 'status' } else { '' }
        result_readiness_policy = if ($taskResult.PSObject.Properties['execution_readiness']) { Get-StringField -InputObject $taskResult.execution_readiness -FieldName 'policy_outcome' } else { '' }
        ack_status = Get-StringField -InputObject $taskAck -FieldName 'status'
    }
    dispatch_attribution = [pscustomobject]@{
        trigger_sequence = if ($commandStatus.PSObject.Properties['trigger']) { Get-StringField -InputObject $commandStatus.trigger -FieldName 'sequence' } else { '' }
        trigger_source_service = if ($commandStatus.PSObject.Properties['trigger']) { Get-StringField -InputObject $commandStatus.trigger -FieldName 'source_service' } else { '' }
        trigger_source_instance_id = if ($commandStatus.PSObject.Properties['trigger']) { Get-StringField -InputObject $commandStatus.trigger -FieldName 'source_instance_id' } else { '' }
        trigger_source_host = if ($commandStatus.PSObject.Properties['trigger']) { Get-StringField -InputObject $commandStatus.trigger -FieldName 'source_host' } else { '' }
        trigger_artifact_sha256 = if ($commandStatus.PSObject.Properties['trigger']) { Get-StringField -InputObject $commandStatus.trigger -FieldName 'artifact_sha256' } else { '' }
        listener_instance_id = if ($commandStatus.PSObject.Properties['listener']) { Get-StringField -InputObject $commandStatus.listener -FieldName 'instance_id' } else { '' }
        ack_source_instance_id = Get-StringField -InputObject $taskAck -FieldName 'source_instance_id'
        result_source_instance_id = Get-StringField -InputObject $taskResult -FieldName 'source_instance_id'
    }
}

$requestIdentityDelta = @(
    New-ScalarDelta -Field 'request_task_id' -Before (Get-StringField -InputObject $baselineSummary.request_identity -FieldName 'request_task_id') -After (Get-StringField -InputObject $currentSummary.request_identity -FieldName 'request_task_id')
    New-ScalarDelta -Field 'request_sequence' -Before (Get-StringField -InputObject $baselineSummary.request_identity -FieldName 'request_sequence') -After (Get-StringField -InputObject $currentSummary.request_identity -FieldName 'request_sequence')
    New-ScalarDelta -Field 'command_status_request_id' -Before (Get-StringField -InputObject $baselineSummary.request_identity -FieldName 'command_status_request_id') -After (Get-StringField -InputObject $currentSummary.request_identity -FieldName 'command_status_request_id')
    New-ScalarDelta -Field 'command_status_task_id' -Before (Get-StringField -InputObject $baselineSummary.request_identity -FieldName 'command_status_task_id') -After (Get-StringField -InputObject $currentSummary.request_identity -FieldName 'command_status_task_id')
    New-ScalarDelta -Field 'trigger_task_id' -Before (Get-StringField -InputObject $baselineSummary.request_identity -FieldName 'trigger_task_id') -After (Get-StringField -InputObject $currentSummary.request_identity -FieldName 'trigger_task_id')
    New-ScalarDelta -Field 'current_processing_task_id' -Before (Get-StringField -InputObject $baselineSummary.request_identity -FieldName 'current_processing_task_id') -After (Get-StringField -InputObject $currentSummary.request_identity -FieldName 'current_processing_task_id')
)

$commandStatusDelta = @(
    New-ScalarDelta -Field 'command_status' -Before (Get-StringField -InputObject $baselineSummary.command_status -FieldName 'status') -After (Get-StringField -InputObject $currentSummary.command_status -FieldName 'status')
    New-ScalarDelta -Field 'command_detail' -Before (Get-StringField -InputObject $baselineSummary.command_status -FieldName 'detail') -After (Get-StringField -InputObject $currentSummary.command_status -FieldName 'detail')
    New-ScalarDelta -Field 'command_action' -Before (Get-StringField -InputObject $baselineSummary.command_status -FieldName 'action') -After (Get-StringField -InputObject $currentSummary.command_status -FieldName 'action')
    New-ScalarDelta -Field 'command_acted_upon' -Before (Get-StringField -InputObject $baselineSummary.command_status -FieldName 'acted_upon') -After (Get-StringField -InputObject $currentSummary.command_status -FieldName 'acted_upon')
)

$executionGatingDelta = @(
    New-ScalarDelta -Field 'command_readiness_status' -Before (Get-StringField -InputObject $baselineSummary.execution_gating -FieldName 'command_readiness_status') -After (Get-StringField -InputObject $currentSummary.execution_gating -FieldName 'command_readiness_status')
    New-ScalarDelta -Field 'command_readiness_policy' -Before (Get-StringField -InputObject $baselineSummary.execution_gating -FieldName 'command_readiness_policy') -After (Get-StringField -InputObject $currentSummary.execution_gating -FieldName 'command_readiness_policy')
    New-ScalarDelta -Field 'ack_status' -Before (Get-StringField -InputObject $baselineSummary.execution_gating -FieldName 'ack_status') -After (Get-StringField -InputObject $currentSummary.execution_gating -FieldName 'ack_status')
    New-ScalarDelta -Field 'result_status' -Before (Get-StringField -InputObject $baselineSummary.execution_gating -FieldName 'result_status') -After (Get-StringField -InputObject $currentSummary.execution_gating -FieldName 'result_status')
    New-ScalarDelta -Field 'result_execution_mode' -Before (Get-StringField -InputObject $baselineSummary.execution_gating -FieldName 'result_execution_mode') -After (Get-StringField -InputObject $currentSummary.execution_gating -FieldName 'result_execution_mode')
    New-ScalarDelta -Field 'result_readiness_status' -Before (Get-StringField -InputObject $baselineSummary.execution_gating -FieldName 'result_readiness_status') -After (Get-StringField -InputObject $currentSummary.execution_gating -FieldName 'result_readiness_status')
    New-ScalarDelta -Field 'result_readiness_policy' -Before (Get-StringField -InputObject $baselineSummary.execution_gating -FieldName 'result_readiness_policy') -After (Get-StringField -InputObject $currentSummary.execution_gating -FieldName 'result_readiness_policy')
)

$dispatchAttributionDelta = @(
    New-ScalarDelta -Field 'trigger_sequence' -Before (Get-StringField -InputObject $baselineSummary.dispatch_attribution -FieldName 'trigger_sequence') -After (Get-StringField -InputObject $currentSummary.dispatch_attribution -FieldName 'trigger_sequence')
    New-ScalarDelta -Field 'trigger_source_service' -Before (Get-StringField -InputObject $baselineSummary.dispatch_attribution -FieldName 'trigger_source_service') -After (Get-StringField -InputObject $currentSummary.dispatch_attribution -FieldName 'trigger_source_service')
    New-ScalarDelta -Field 'trigger_source_instance_id' -Before (Get-StringField -InputObject $baselineSummary.dispatch_attribution -FieldName 'trigger_source_instance_id') -After (Get-StringField -InputObject $currentSummary.dispatch_attribution -FieldName 'trigger_source_instance_id')
    New-ScalarDelta -Field 'trigger_artifact_sha256' -Before (Get-StringField -InputObject $baselineSummary.dispatch_attribution -FieldName 'trigger_artifact_sha256') -After (Get-StringField -InputObject $currentSummary.dispatch_attribution -FieldName 'trigger_artifact_sha256')
    New-ScalarDelta -Field 'listener_instance_id' -Before (Get-StringField -InputObject $baselineSummary.dispatch_attribution -FieldName 'listener_instance_id') -After (Get-StringField -InputObject $currentSummary.dispatch_attribution -FieldName 'listener_instance_id')
    New-ScalarDelta -Field 'ack_source_instance_id' -Before (Get-StringField -InputObject $baselineSummary.dispatch_attribution -FieldName 'ack_source_instance_id') -After (Get-StringField -InputObject $currentSummary.dispatch_attribution -FieldName 'ack_source_instance_id')
    New-ScalarDelta -Field 'result_source_instance_id' -Before (Get-StringField -InputObject $baselineSummary.dispatch_attribution -FieldName 'result_source_instance_id') -After (Get-StringField -InputObject $currentSummary.dispatch_attribution -FieldName 'result_source_instance_id')
)

$delta = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    baseline_id = Get-StringField -InputObject $baseline -FieldName 'baseline_id'
    baseline_manifest_path = $baselineManifestAbs
    summary = [pscustomobject]@{
        request_identity_changed = (@($requestIdentityDelta | Where-Object { [bool]$_.changed }).Count -gt 0)
        command_status_changed = (@($commandStatusDelta | Where-Object { [bool]$_.changed }).Count -gt 0)
        execution_gating_changed = (@($executionGatingDelta | Where-Object { [bool]$_.changed }).Count -gt 0)
        dispatch_attribution_changed = (@($dispatchAttributionDelta | Where-Object { [bool]$_.changed }).Count -gt 0)
        before_command_status = Get-StringField -InputObject $baselineSummary.command_status -FieldName 'status'
        after_command_status = Get-StringField -InputObject $currentSummary.command_status -FieldName 'status'
        before_trigger_task_id = Get-StringField -InputObject $baselineSummary.request_identity -FieldName 'trigger_task_id'
        after_trigger_task_id = Get-StringField -InputObject $currentSummary.request_identity -FieldName 'trigger_task_id'
    }
    current = $currentSummary
    request_identity_delta = @($requestIdentityDelta)
    command_status_delta = @($commandStatusDelta)
    execution_gating_delta = @($executionGatingDelta)
    dispatch_attribution_delta = @($dispatchAttributionDelta)
}

Write-JsonFile -PathValue $outputAbs -Payload $delta -Depth 20
$delta | ConvertTo-Json -Depth 20 | Write-Output