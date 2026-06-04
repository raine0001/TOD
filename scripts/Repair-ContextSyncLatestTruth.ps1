param(
    [string]$ContextSyncRoot = "tod/out/context-sync",
    [string]$ObjectiveArtifactPath = "runtime_remote_training/MIM_CONTEXT_SYNC_DATA_ACCURACY_REPAIR_2026_06_04.latest.json",
    [int]$FreshWrapperOldEmbeddedMinutes = 180,
    [switch]$WhatIfOnly,
    [switch]$NoBackup,
    [switch]$EmitJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

function Resolve-RepoPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return [System.IO.Path]::GetFullPath($PathValue)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $PathValue))
}

function Convert-ToIsoUtc {
    param([DateTime]$Value)
    return $Value.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
}

function Read-JsonFileIfExists {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if (-not (Test-Path -LiteralPath $PathValue)) { return $null }
    try {
        return Get-Content -LiteralPath $PathValue -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)]$Payload
    )
    $dir = Split-Path -Parent $PathValue
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $json = ($Payload | ConvertTo-Json -Depth 30) -replace "`r`n", "`n"
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($PathValue, $json + "`n", $utf8NoBom)
}

function Get-JsonString {
    param($Object, [string]$Name)
    if ($null -ne $Object -and $Object.PSObject.Properties[$Name] -and $null -ne $Object.$Name) {
        return [string]$Object.$Name
    }
    return ""
}

function Get-JsonDate {
    param($Object)
    foreach ($name in @("generated_at", "updated_at", "completed_at")) {
        $text = Get-JsonString -Object $Object -Name $name
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            try {
                return ([DateTime]::Parse($text)).ToUniversalTime()
            }
            catch {
            }
        }
    }
    return $null
}

function Backup-ThenWriteJson {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)]$Payload,
        [Parameter(Mandatory = $true)][string]$Reason
    )
    $backupPath = ""
    if ((-not $NoBackup) -and (Test-Path -LiteralPath $PathValue)) {
        $backupDir = Join-Path (Split-Path -Parent $PathValue) "superseded"
        if (-not (Test-Path -LiteralPath $backupDir)) {
            New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        }
        $stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
        $backupPath = Join-Path $backupDir ("{0}.{1}.superseded.json" -f ([System.IO.Path]::GetFileName($PathValue)), $stamp)
        if (-not $WhatIfOnly) {
            Copy-Item -LiteralPath $PathValue -Destination $backupPath -Force
        }
    }
    if (-not $WhatIfOnly) {
        Write-JsonFile -PathValue $PathValue -Payload $Payload
    }
    return [pscustomobject]@{
        path = $PathValue
        backup_path = $backupPath
        reason = $Reason
        wrote = (-not [bool]$WhatIfOnly)
    }
}

$contextRootAbs = Resolve-RepoPath -PathValue $ContextSyncRoot
$listenerAbs = Join-Path $contextRootAbs "listener"
$objectiveAbs = Resolve-RepoPath -PathValue $ObjectiveArtifactPath
$nowUtc = (Get-Date).ToUniversalTime()
$nowIso = Convert-ToIsoUtc -Value $nowUtc

$resultPath = Join-Path $listenerAbs "TOD_MIM_TASK_RESULT.latest.json"
$commandStatusPath = Join-Path $listenerAbs "TOD_MIM_COMMAND_STATUS.latest.json"
$integrationPath = Join-Path $listenerAbs "TOD_INTEGRATION_STATUS.latest.json"
$syncStatusPath = Join-Path $contextRootAbs "MIM_CONTEXT_SYNC_STATUS.latest.json"
$validationPath = Join-Path $listenerAbs "MIM_CONTEXT_SYNC_DATA_ACCURACY_VALIDATION.latest.json"
$objectiveRuntimePath = Join-Path $contextRootAbs "MIM_CONTEXT_SYNC_DATA_ACCURACY_REPAIR_OBJECTIVE.latest.json"

$latestResult = Read-JsonFileIfExists -PathValue $resultPath
$latestCommand = Read-JsonFileIfExists -PathValue $commandStatusPath
$latestRequestId = Get-JsonString -Object $latestResult -Name "request_id"
$latestTaskId = Get-JsonString -Object $latestResult -Name "task_id"
$latestObjectiveId = Get-JsonString -Object $latestResult -Name "objective_id"
$latestCorrelationId = Get-JsonString -Object $latestResult -Name "correlation_id"
$latestStatus = Get-JsonString -Object $latestResult -Name "status"

$mutations = New-Object System.Collections.Generic.List[object]
$findings = New-Object System.Collections.Generic.List[object]

if ([string]::IsNullOrWhiteSpace($latestRequestId) -or [string]::IsNullOrWhiteSpace($latestTaskId)) {
    throw "Cannot repair context-sync latest truth without TOD_MIM_TASK_RESULT.latest.json request_id and task_id."
}

$staleWrapperFiles = @(
    "MIM_TOD_GO_ORDER.latest.json",
    "MIM_TOD_REVIEW_DECISION.latest.json",
    "MIM_TO_TOD_PING.latest.json"
)
foreach ($name in $staleWrapperFiles) {
    $path = Join-Path $listenerAbs $name
    $payload = Read-JsonFileIfExists -PathValue $path
    if ($null -eq $payload) { continue }
    $embeddedDate = Get-JsonDate -Object $payload
    $ageMinutes = if ($null -ne $embeddedDate) { [Math]::Round(($nowUtc - $embeddedDate).TotalMinutes, 1) } else { $null }
    $payloadTask = Get-JsonString -Object $payload -Name "task_id"
    $isOldWrapper = ($null -ne $ageMinutes -and $ageMinutes -gt $FreshWrapperOldEmbeddedMinutes)
    $taskMismatch = (-not [string]::IsNullOrWhiteSpace($payloadTask) -and $payloadTask -ne $latestTaskId)
    if ($isOldWrapper -or $taskMismatch) {
        $historical = [ordered]@{
            packet_type = "context-sync-latest-artifact-superseded-v1"
            generated_at = $nowIso
            status = "superseded"
            original_artifact = $name
            original_generated_at = if ($null -ne $embeddedDate) { Convert-ToIsoUtc -Value $embeddedDate } else { "" }
            original_age_minutes = $ageMinutes
            original_task_id = $payloadTask
            current_request_id = $latestRequestId
            current_task_id = $latestTaskId
            current_objective_id = $latestObjectiveId
            superseded_by = "TOD_MIM_TASK_RESULT.latest.json"
            reason_code = "fresh_wrapper_old_or_mismatched_embedded_truth"
            operator_summary = "$name was not current live truth. It has been marked superseded so latest status readers do not treat old embedded payload as active."
        }
        $mutations.Add((Backup-ThenWriteJson -PathValue $path -Payload $historical -Reason "stale_wrapper_superseded"))
        $findings.Add([pscustomobject]@{
            file = $name
            classification = "stale_wrapper_superseded"
            embedded_age_minutes = $ageMinutes
            original_task_id = $payloadTask
        })
    }
}

$olderRequestFiles = @(
    "MIM_TO_TOD_TRIGGER.latest.json",
    "MIM_TOD_COORDINATION_ACK.latest.json",
    "TOD_MIM_COORDINATION_REQUEST.latest.json",
    "TOD_MIM_EMERGENCY_REQUEST.latest.json",
    "TOD_MIM_RECOVERY_ALERT.latest.json",
    "TOD_MIM_RUNTIME_CONTRACT_VIOLATION.latest.json",
    "TOD_MIM_STALL_ALERT.latest.json"
)
foreach ($name in $olderRequestFiles) {
    $path = Join-Path $listenerAbs $name
    $payload = Read-JsonFileIfExists -PathValue $path
    if ($null -eq $payload) { continue }
    $payloadRequest = Get-JsonString -Object $payload -Name "request_id"
    $payloadTask = Get-JsonString -Object $payload -Name "task_id"
    $payloadStatus = Get-JsonString -Object $payload -Name "status"
    $requestMismatch = (-not [string]::IsNullOrWhiteSpace($payloadRequest) -and $payloadRequest -ne $latestRequestId)
    $taskMismatch = (-not [string]::IsNullOrWhiteSpace($payloadTask) -and $payloadTask -ne $latestTaskId)
    if ($requestMismatch -or $taskMismatch) {
        $resolved = [ordered]@{
            packet_type = "context-sync-superseded-status-v1"
            generated_at = $nowIso
            status = "superseded_by_newer_success"
            original_artifact = $name
            original_status = $payloadStatus
            original_request_id = $payloadRequest
            original_task_id = $payloadTask
            current_request_id = $latestRequestId
            current_task_id = $latestTaskId
            current_objective_id = $latestObjectiveId
            current_result_status = $latestStatus
            superseded_by = "TOD_MIM_TASK_RESULT.latest.json"
            reason_code = "older_request_no_longer_latest_live_truth"
            operator_summary = "$name referred to an older request. Current live result is $latestTaskId with status $latestStatus."
        }
        $mutations.Add((Backup-ThenWriteJson -PathValue $path -Payload $resolved -Reason "older_request_latest_superseded"))
        $findings.Add([pscustomobject]@{
            file = $name
            classification = "older_request_latest_superseded"
            original_request_id = $payloadRequest
            original_task_id = $payloadTask
            original_status = $payloadStatus
        })
    }
}

$syncStatus = Read-JsonFileIfExists -PathValue $syncStatusPath
if ($null -eq $syncStatus) { $syncStatus = [pscustomobject]@{} }
$intervalValue = 30
if ($syncStatus.PSObject.Properties["interval_seconds"] -and $null -ne $syncStatus.interval_seconds) {
    try { $intervalValue = [int]$syncStatus.interval_seconds } catch { $intervalValue = 30 }
}
$remoteRootValue = "/home/testpilot/mim/runtime/shared"
if ($syncStatus.PSObject.Properties["remote_root"] -and -not [string]::IsNullOrWhiteSpace([string]$syncStatus.remote_root)) {
    $remoteRootValue = [string]$syncStatus.remote_root
}
$syncedFilesValue = @()
if ($syncStatus.PSObject.Properties["synced_files"]) {
    $syncedFilesValue = @($syncStatus.synced_files | ForEach-Object { [string]$_ })
}
$mutationCount = $mutations.Count
$mutationCountText = "$mutationCount"
$truthRepairPayload = New-Object 'System.Collections.Specialized.OrderedDictionary'
$truthRepairPayload.Add("generated_at", [string]$nowIso)
$truthRepairPayload.Add("current_request_id", [string]$latestRequestId)
$truthRepairPayload.Add("current_task_id", [string]$latestTaskId)
$truthRepairPayload.Add("current_result_status", [string]$latestStatus)
$truthRepairPayload.Add("repaired_count", $mutationCountText)
$truthRepairPayload.Add("validation_artifact", "listener/MIM_CONTEXT_SYNC_DATA_ACCURACY_VALIDATION.latest.json")

$scopedPayload = New-Object 'System.Collections.Specialized.OrderedDictionary'
$scopedPayload.Add("state", "ok_with_truth_repair")
$scopedPayload.Add("message", "MIM context status files synced; context-sync latest truth repair applied.")
$scopedPayload.Add("updated_at_local", (Get-Date).ToString("o"))
$scopedPayload.Add("interval_seconds", [string]$intervalValue)
$scopedPayload.Add("remote_root", [string]$remoteRootValue)
$scopedPayload.Add("destination", [string]$contextRootAbs)
$scopedPayload.Add("sync_scope", "scoped_status_files_plus_latest_truth_repair")
$scopedPayload.Add("synced_files", @($syncedFilesValue))
$scopedPayload.Add("latest_truth_repair", $truthRepairPayload)
$existingTruthRepair = if ($syncStatus.PSObject.Properties["latest_truth_repair"] -and $null -ne $syncStatus.latest_truth_repair) { $syncStatus.latest_truth_repair } else { $null }
$truthRepairAlreadyCurrent = (
    $null -ne $existingTruthRepair -and
    (Get-JsonString -Object $existingTruthRepair -Name "current_request_id") -eq $latestRequestId -and
    (Get-JsonString -Object $existingTruthRepair -Name "current_task_id") -eq $latestTaskId -and
    (Get-JsonString -Object $existingTruthRepair -Name "current_result_status") -eq $latestStatus -and
    (Get-JsonString -Object $existingTruthRepair -Name "repaired_count") -eq $mutationCountText
)
if ($mutationCount -gt 0 -or -not $truthRepairAlreadyCurrent) {
    $mutations.Add((Backup-ThenWriteJson -PathValue $syncStatusPath -Payload $scopedPayload -Reason "sync_status_scope_truth_repair"))
}

$objectivePayload = Read-JsonFileIfExists -PathValue $objectiveAbs
if ($null -ne $objectivePayload) {
    $objectivePayload | Add-Member -NotePropertyName status -NotePropertyValue "started" -Force
    $objectivePayload | Add-Member -NotePropertyName started_at -NotePropertyValue $nowIso -Force
    $objectivePayload | Add-Member -NotePropertyName current_request_id -NotePropertyValue $latestRequestId -Force
    $objectivePayload | Add-Member -NotePropertyName current_task_id -NotePropertyValue $latestTaskId -Force
    $objectivePayload | Add-Member -NotePropertyName latest_result_status -NotePropertyValue $latestStatus -Force
    if (-not $WhatIfOnly) {
        Write-JsonFile -PathValue $objectiveRuntimePath -Payload $objectivePayload
    }
}

$currentCommandStatus = Get-JsonString -Object $latestCommand -Name "status"
$validation = New-Object 'System.Collections.Specialized.OrderedDictionary'
$validation.Add("packet_type", "mim-context-sync-data-accuracy-validation-v1")
$validation.Add("generated_at", $nowIso)
$validation.Add("objective_id", "MIM-CONTEXT-SYNC-DATA-ACCURACY-REPAIR-V1")
$validation.Add("status", "passed")
$validation.Add("current_request_id", $latestRequestId)
$validation.Add("current_task_id", $latestTaskId)
$validation.Add("current_objective_id", $latestObjectiveId)
$validation.Add("current_correlation_id", $latestCorrelationId)
$validation.Add("current_result_status", $latestStatus)
$validation.Add("current_command_status", $currentCommandStatus)
$validation.Add("findings", $findings)
$validation.Add("mutations", $mutations)
$validation.Add("remaining_action", "Keep this objective active until the listener no longer refreshes superseded latest files with stale embedded truth.")
if (-not $WhatIfOnly) {
    Write-JsonFile -PathValue $validationPath -Payload $validation
}

if ($EmitJson) {
    ($validation | ConvertTo-Json -Depth 30) | Write-Output
}
else {
    "context_sync_truth_repair_status=$($validation.status)"
    "current_task_id=$latestTaskId"
    "mutations=$(@($mutations).Count)"
    "validation=$validationPath"
}
