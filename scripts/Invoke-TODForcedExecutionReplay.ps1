[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ObjectiveId,
    [Parameter(Mandatory = $true)][string]$TaskId,
    [Parameter(Mandatory = $true)][string]$Reason,
    [switch]$Force,
    [string]$ListenerStageDir,
    [string]$RemoteRoot = "/home/testpilot/mim/runtime/shared",
    [string]$EnvFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RepoPath {
    if ($PSScriptRoot) {
        return (Split-Path -Parent $PSScriptRoot)
    }

    return (Get-Location).Path
}

function Ensure-Directory {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if (-not (Test-Path -Path $PathValue)) {
        New-Item -ItemType Directory -Path $PathValue -Force | Out-Null
    }

    return $PathValue
}

function Read-JsonFileIfExists {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if (-not (Test-Path -Path $PathValue)) {
        return $null
    }

    try {
        return (Get-Content -Path $PathValue -Raw | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)]$Payload,
        [int]$Depth = 20
    )

    $parent = Split-Path -Parent $PathValue
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        Ensure-Directory -PathValue $parent | Out-Null
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $json = ($Payload | ConvertTo-Json -Depth $Depth) -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($PathValue, $json, $utf8NoBom)
}

function Get-DotEnvValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if (-not (Test-Path -Path $Path)) {
        return ""
    }

    $line = Get-Content -Path $Path | Where-Object {
        $_ -match ("^\s*{0}\s*=" -f [regex]::Escape($Name))
    } | Select-Object -First 1

    if ([string]::IsNullOrWhiteSpace([string]$line)) {
        return ""
    }

    return ([string]($line -replace ("^\s*{0}\s*=\s*" -f [regex]::Escape($Name)), "")).Trim()
}

function Resolve-SshHostAlias {
    param([Parameter(Mandatory = $true)][string]$RemoteHost)

    if ($RemoteHost -match "^\d{1,3}(?:\.\d{1,3}){3}$" -or $RemoteHost -match "\.") {
        return $RemoteHost
    }

    $sshConfigPath = Join-Path $HOME ".ssh/config"
    if (-not (Test-Path -Path $sshConfigPath)) {
        return $RemoteHost
    }

    $matchedHost = $false
    foreach ($rawLine in Get-Content -Path $sshConfigPath) {
        $trim = ([string]$rawLine).Trim()
        if ([string]::IsNullOrWhiteSpace($trim) -or $trim.StartsWith('#')) {
            continue
        }

        if ($trim -match '^(?i)Host\s+(.+)$') {
            $matchedHost = $false
            foreach ($token in @($matches[1] -split '\s+')) {
                if ([string]::Equals([string]$token, $RemoteHost, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $matchedHost = $true
                    break
                }
            }
            continue
        }

        if ($matchedHost -and $trim -match '^(?i)HostName\s+(.+)$') {
            return [string]$matches[1]
        }
    }

    return $RemoteHost
}

function New-SshConnections {
    param(
        [Parameter(Mandatory = $true)][string]$HostAlias,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][int]$Port,
        [Parameter(Mandatory = $true)][string]$Password
    )

    if (-not (Get-Module -ListAvailable -Name Posh-SSH)) {
        throw "Posh-SSH is not installed. Install-Module -Name Posh-SSH -Scope CurrentUser"
    }

    Import-Module Posh-SSH -ErrorAction Stop | Out-Null
    $resolvedHost = Resolve-SshHostAlias -RemoteHost $HostAlias
    $securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential ($UserName, $securePassword)

    return [pscustomobject]@{
        ssh = New-SSHSession -ComputerName $resolvedHost -Port $Port -Credential $credential -AcceptKey -ConnectionTimeout 15000
        sftp = New-SFTPSession -ComputerName $resolvedHost -Port $Port -Credential $credential -AcceptKey -ConnectionTimeout 15000
    }
}

function Close-SshConnections {
    param($Connections)

    if ($null -eq $Connections) {
        return
    }

    try {
        if ($Connections.sftp) {
            Remove-SFTPSession -SessionId ([int]$Connections.sftp.SessionId) | Out-Null
        }
    }
    catch {
    }

    try {
        if ($Connections.ssh) {
            Remove-SSHSession -SessionId ([int]$Connections.ssh.SessionId) | Out-Null
        }
    }
    catch {
    }
}

function Write-RemoteFileFromText {
    param(
        [Parameter(Mandatory = $true)]$Connections,
        [Parameter(Mandatory = $true)][string]$RemotePath,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $remoteDir = ([string](Split-Path -Path $RemotePath -Parent)) -replace '[\\/]+', '/'
    $remoteName = [string](Split-Path -Path $RemotePath -Leaf)
    if ([string]::IsNullOrWhiteSpace($remoteDir) -or [string]::IsNullOrWhiteSpace($remoteName)) {
        throw "Invalid remote path: $RemotePath"
    }

    $tempDir = Ensure-Directory -PathValue (Join-Path ([System.IO.Path]::GetTempPath()) 'tod-forced-replay')
    $tempPath = Join-Path $tempDir $remoteName
    try {
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($tempPath, (($Content -replace "`r`n", "`n")), $utf8NoBom)
        Set-SFTPItem -SessionId ([int]$Connections.sftp.SessionId) -Path $tempPath -Destination $remoteDir -Force -ErrorAction Stop | Out-Null
    }
    finally {
        if (Test-Path -Path $tempPath) {
            Remove-Item -Path $tempPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-NormalizedObjectiveId {
    param([Parameter(Mandatory = $true)][string]$Value)

    if ([string]$Value -match '^objective-\d+$') {
        return [string]$Value
    }

    if ([string]$Value -match '^(\d+)$') {
        return ('objective-{0}' -f $matches[1])
    }

    return [string]$Value
}

function Get-ReplayAttempt {
    param([AllowNull()]$Request)

    if ($null -eq $Request) {
        return 1
    }

    if ($Request.PSObject.Properties['replay_attempt']) {
        return ([int]$Request.replay_attempt + 1)
    }

    if ($Request.PSObject.Properties['lineage'] -and $null -ne $Request.lineage -and $Request.lineage.PSObject.Properties['replay_attempt']) {
        return ([int]$Request.lineage.replay_attempt + 1)
    }

    return 1
}

function Get-UnixEpochMilliseconds {
    return [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
}

function Copy-LiveArtifactToArchive {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$ArchiveDir
    )

    if (-not (Test-Path -Path $SourcePath -PathType Leaf)) {
        return $null
    }

    Ensure-Directory -PathValue $ArchiveDir | Out-Null
    $destinationPath = Join-Path $ArchiveDir (Split-Path -Path $SourcePath -Leaf)
    Copy-Item -Path $SourcePath -Destination $destinationPath -Force
    return $destinationPath
}

function Archive-ForcedReplayArtifacts {
    param(
        [Parameter(Mandatory = $true)][hashtable]$ArtifactPaths,
        [Parameter(Mandatory = $true)][string]$ArchiveDir
    )

    $archived = New-Object System.Collections.Generic.List[object]
    foreach ($entry in $ArtifactPaths.GetEnumerator()) {
        $archivedPath = Copy-LiveArtifactToArchive -SourcePath ([string]$entry.Value) -ArchiveDir $ArchiveDir
        if (-not [string]::IsNullOrWhiteSpace([string]$archivedPath)) {
            $archived.Add([pscustomobject]@{
                artifact = [string]$entry.Key
                source_path = [string]$entry.Value
                archived_path = [string]$archivedPath
            })
        }
    }

    return @($archived.ToArray())
}

function New-ForcedReplayRequest {
    param(
        [Parameter(Mandatory = $true)]$ExistingRequest,
        [Parameter(Mandatory = $true)][string]$ObjectiveId,
        [Parameter(Mandatory = $true)][string]$TaskId,
        [Parameter(Mandatory = $true)][string]$Reason
    )

    $normalizedObjectiveId = Get-NormalizedObjectiveId -Value $ObjectiveId
    $generatedAt = (Get-Date).ToUniversalTime().ToString('o')
    $replayAttempt = Get-ReplayAttempt -Request $ExistingRequest
    $nextSequence = 0L
    if ($ExistingRequest.PSObject.Properties['sequence']) {
        $nextSequence = [long]$ExistingRequest.sequence + 1
    }
    $sequence = [Math]::Max($nextSequence, [long](Get-UnixEpochMilliseconds))
    $requestStamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddHHmmssfff')
    $replayRequestId = ('{0}-replay-{1}-{2}' -f $TaskId, $replayAttempt, $requestStamp).ToLowerInvariant()
    $replayCorrelationId = ('{0}-replay-{1}' -f $TaskId, $replayAttempt).ToLowerInvariant()
    $rootRequestId = if ($ExistingRequest.PSObject.Properties['lineage'] -and $null -ne $ExistingRequest.lineage -and $ExistingRequest.lineage.PSObject.Properties['replay_chain_root_request_id']) {
        [string]$ExistingRequest.lineage.replay_chain_root_request_id
    }
    else {
        [string]$ExistingRequest.request_id
    }

    $requestMap = [ordered]@{}
    foreach ($property in $ExistingRequest.PSObject.Properties) {
        $requestMap[$property.Name] = $property.Value
    }

    $requestMap['request_id'] = $replayRequestId
    $requestMap['correlation_id'] = $replayCorrelationId
    $requestMap['objective_id'] = $normalizedObjectiveId
    $requestMap['task_id'] = $TaskId
    $requestMap['sequence'] = $sequence
    $requestMap['generated_at'] = $generatedAt
    $requestMap['emitted_at'] = $generatedAt
    $requestMap['dispatch_status'] = 'queued'
    $requestMap['request_status'] = 'queued_for_replay'
    $requestMap['result_status'] = 'pending'
    $requestMap['result_reason'] = 'Forced replay queued pending fresh execution evidence.'
    $requestMap['replay_attempt'] = $replayAttempt
    $requestMap['replay_reason'] = $Reason
    $requestMap['replay_generated_at'] = $generatedAt
    $requestMap['replay_requires_fresh_execution_evidence'] = $true
    $requestMap['replay_of_request_id'] = [string]$ExistingRequest.request_id
    $requestMap['replay_of_correlation_id'] = if ($ExistingRequest.PSObject.Properties['correlation_id']) { [string]$ExistingRequest.correlation_id } else { [string]$ExistingRequest.request_id }
    $requestMap['lineage'] = [pscustomobject]@{
        original_request_id = [string]$ExistingRequest.request_id
        original_correlation_id = if ($ExistingRequest.PSObject.Properties['correlation_id']) { [string]$ExistingRequest.correlation_id } else { [string]$ExistingRequest.request_id }
        original_objective_id = $normalizedObjectiveId
        original_task_id = $TaskId
        replay_attempt = $replayAttempt
        replay_request_id = $replayRequestId
        replay_correlation_id = $replayCorrelationId
        replay_chain_root_request_id = $rootRequestId
        replay_reason = $Reason
    }

    $existingIdempotency = if ($ExistingRequest.PSObject.Properties['idempotency'] -and $null -ne $ExistingRequest.idempotency) { $ExistingRequest.idempotency } else { $null }
    $requestMap['idempotency'] = [pscustomobject]@{
        key = $replayRequestId
        duplicate_execution_allowed = $false
        replay_of_key = if ($existingIdempotency -and $existingIdempotency.PSObject.Properties['key']) { [string]$existingIdempotency.key } else { [string]$ExistingRequest.request_id }
    }

    $existingExecutionRequirements = if ($ExistingRequest.PSObject.Properties['execution_requirements'] -and $null -ne $ExistingRequest.execution_requirements) { $ExistingRequest.execution_requirements } else { $null }
    $requestMap['execution_requirements'] = [pscustomobject]@{
        require_meaningful_evidence = $true
        prohibit_no_op_completion = $true
        replay_reason = $Reason
        prior_requirements = $existingExecutionRequirements
    }

    return [pscustomobject]$requestMap
}

function New-ForcedReplayTrigger {
    param(
        [Parameter(Mandatory = $true)]$ReplayRequest,
        [Parameter(Mandatory = $true)][string]$RemoteRoot
    )

    return [pscustomobject]@{
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        source = 'shared-trigger-v1'
        task_id = [string]$ReplayRequest.request_id
        correlation_id = [string]$ReplayRequest.correlation_id
        trigger = 'forced_execution_replay_posted'
        action_required = 'pull_latest_and_ack'
        artifact = 'MIM_TOD_TASK_REQUEST.latest.json'
        artifact_path = ((Join-Path $RemoteRoot 'MIM_TOD_TASK_REQUEST.latest.json') -replace '[\\/]+', '/')
        sequence = [long]$ReplayRequest.sequence
        source_actor = 'TOD'
        target_actor = 'TOD'
        replay_attempt = [int]$ReplayRequest.replay_attempt
        replay_reason = [string]$ReplayRequest.replay_reason
        replay_request_id = [string]$ReplayRequest.request_id
    }
}

function New-ForcedReplayCommandStatus {
    param(
        [Parameter(Mandatory = $true)]$ReplayRequest,
        [Parameter(Mandatory = $true)][string]$Reason
    )

    return [pscustomobject]@{
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        source = 'tod-mim-command-status-v1'
        status = 'forced_replay_staged'
        detail = 'Forced replay armed; listener should bypass stale/dedup only for this replay request.'
        request_id = [string]$ReplayRequest.request_id
        task_id = [string]$ReplayRequest.task_id
        correlation_id = [string]$ReplayRequest.correlation_id
        reason = $Reason
        replay_attempt = [int]$ReplayRequest.replay_attempt
        bridge_runtime = [pscustomobject]@{
            current_task_id = [string]$ReplayRequest.task_id
            current_correlation_id = [string]$ReplayRequest.correlation_id
            result_status = 'forced_replay_staged'
        }
    }
}

function Update-ListenerStateForForcedReplay {
    param(
        [Parameter(Mandatory = $true)]$ListenerState,
        [Parameter(Mandatory = $true)][string]$ObjectiveId,
        [Parameter(Mandatory = $true)][string]$TaskId,
        [Parameter(Mandatory = $true)][string]$OriginalRequestId,
        [Parameter(Mandatory = $true)][string]$ReplayRequestId,
        [Parameter(Mandatory = $true)][string]$ReplayCorrelationId,
        [Parameter(Mandatory = $true)][int]$ReplayAttempt,
        [Parameter(Mandatory = $true)][string]$Reason
    )

    $scopedOverrides = New-Object System.Collections.Generic.List[object]
    if ($ListenerState.PSObject.Properties['scoped_forced_replays'] -and $null -ne $ListenerState.scoped_forced_replays) {
        foreach ($entry in @($ListenerState.scoped_forced_replays)) {
            if ($null -eq $entry) {
                continue
            }

            $entryRequestId = if ($entry.PSObject.Properties['replay_request_id']) { [string]$entry.replay_request_id } else { '' }
            if ([string]::Equals($entryRequestId, $ReplayRequestId, [System.StringComparison]::OrdinalIgnoreCase)) {
                continue
            }

            $scopedOverrides.Add($entry)
        }
    }

    $scopedOverrides.Add([pscustomobject]@{
        active = $true
        armed_at = (Get-Date).ToUniversalTime().ToString('o')
        objective_id = $ObjectiveId
        task_id = $TaskId
        original_request_id = $OriginalRequestId
        replay_request_id = $ReplayRequestId
        replay_correlation_id = $ReplayCorrelationId
        replay_attempt = $ReplayAttempt
        replay_reason = $Reason
        require_fresh_execution_evidence = $true
    })

    $ListenerState | Add-Member -NotePropertyName scoped_forced_replays -NotePropertyValue @($scopedOverrides.ToArray()) -Force
    $lastProcessedRequestId = if ($ListenerState.PSObject.Properties['last_processed_request_id']) { [string]$ListenerState.last_processed_request_id } else { '' }
    if ([string]::Equals($lastProcessedRequestId, $OriginalRequestId, [System.StringComparison]::OrdinalIgnoreCase)) {
        $ListenerState | Add-Member -NotePropertyName last_processed_request_id -NotePropertyValue '' -Force
        $ListenerState | Add-Member -NotePropertyName last_processed_request_signature -NotePropertyValue '' -Force
    }
    elseif (-not $ListenerState.PSObject.Properties['last_processed_request_signature']) {
        $ListenerState | Add-Member -NotePropertyName last_processed_request_id -NotePropertyValue '' -Force
        $ListenerState | Add-Member -NotePropertyName last_processed_request_signature -NotePropertyValue '' -Force
    }

    if (-not $ListenerState.PSObject.Properties['last_processed_request_id']) {
        $ListenerState | Add-Member -NotePropertyName last_processed_request_id -NotePropertyValue '' -Force
    }
    $ListenerState | Add-Member -NotePropertyName last_command_status -NotePropertyValue 'forced_replay_staged' -Force
    $ListenerState | Add-Member -NotePropertyName last_command_detail -NotePropertyValue ('Forced replay armed for {0} because {1}.' -f $TaskId, $Reason) -Force
    return $ListenerState
}

function Publish-ForcedReplayRemoteArtifacts {
    param(
        [Parameter(Mandatory = $true)][string]$EnvFile,
        [Parameter(Mandatory = $true)][string]$RemoteRoot,
        [Parameter(Mandatory = $true)][hashtable]$LocalArtifacts
    )

    $hostAlias = Get-DotEnvValue -Path $EnvFile -Name 'MIM_SSH_HOST'
    $userName = Get-DotEnvValue -Path $EnvFile -Name 'MIM_SSH_USER'
    $portText = Get-DotEnvValue -Path $EnvFile -Name 'MIM_SSH_PORT'
    $password = Get-DotEnvValue -Path $EnvFile -Name 'MIM_SSH_PASSWORD'
    if ([string]::IsNullOrWhiteSpace($hostAlias) -or [string]::IsNullOrWhiteSpace($userName) -or [string]::IsNullOrWhiteSpace($password)) {
        return [pscustomobject]@{
            attempted = $false
            published = $false
            reason = 'missing_ssh_configuration'
        }
    }

    $port = 22
    if (-not [string]::IsNullOrWhiteSpace($portText)) {
        $port = [int]$portText
    }

    $connections = $null
    try {
        $connections = New-SshConnections -HostAlias $hostAlias -UserName $userName -Port $port -Password $password
        foreach ($artifact in $LocalArtifacts.GetEnumerator()) {
            $remotePath = ((Join-Path $RemoteRoot ([string]$artifact.Key)) -replace '[\\/]+', '/')
            Write-RemoteFileFromText -Connections $connections -RemotePath $remotePath -Content (Get-Content -Path ([string]$artifact.Value) -Raw)
        }

        return [pscustomobject]@{
            attempted = $true
            published = $true
            reason = 'ok'
        }
    }
    catch {
        return [pscustomobject]@{
            attempted = $true
            published = $false
            reason = [string]$_.Exception.Message
        }
    }
    finally {
        Close-SshConnections -Connections $connections
    }
}

function Invoke-ForcedExecutionReplayInternal {
    param(
        [Parameter(Mandatory = $true)][string]$ObjectiveId,
        [Parameter(Mandatory = $true)][string]$TaskId,
        [Parameter(Mandatory = $true)][string]$Reason,
        [switch]$Force,
        [Parameter(Mandatory = $true)][string]$ListenerStageDir,
        [Parameter(Mandatory = $true)][string]$RemoteRoot,
        [Parameter(Mandatory = $true)][string]$EnvFile
    )

    $normalizedObjectiveId = Get-NormalizedObjectiveId -Value $ObjectiveId
    $requestPath = Join-Path $ListenerStageDir 'MIM_TOD_TASK_REQUEST.latest.json'
    $triggerPath = Join-Path $ListenerStageDir 'MIM_TO_TOD_TRIGGER.latest.json'
    $statusPath = Join-Path $ListenerStageDir 'TOD_MIM_COMMAND_STATUS.latest.json'
    $listenerStatePath = Join-Path $ListenerStageDir 'listener_state.json'
    $decisionPath = Join-Path $ListenerStageDir 'TOD_MIM_EXECUTION_DECISION.latest.json'
    $resultPath = Join-Path $ListenerStageDir 'TOD_MIM_TASK_RESULT.latest.json'
    $goOrderPath = Join-Path $ListenerStageDir 'TOD_EXECUTION_REVIEW.latest.json'

    $existingRequest = Read-JsonFileIfExists -PathValue $requestPath
    if ($null -eq $existingRequest) {
        throw 'Cannot force replay because MIM_TOD_TASK_REQUEST.latest.json is missing or invalid.'
    }

    $requestObjectiveId = if ($existingRequest.PSObject.Properties['objective_id']) { [string]$existingRequest.objective_id } else { '' }
    $requestTaskId = if ($existingRequest.PSObject.Properties['task_id']) { [string]$existingRequest.task_id } else { '' }
    if (-not [string]::Equals($requestObjectiveId, $normalizedObjectiveId, [System.StringComparison]::OrdinalIgnoreCase) -or -not [string]::Equals($requestTaskId, $TaskId, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw ('Live request is {0}/{1}; refusing to replay {2}/{3}.' -f $requestObjectiveId, $requestTaskId, $normalizedObjectiveId, $TaskId)
    }

    if (-not $Force) {
        throw 'Forced replay requires -Force so the operator makes the replay explicit.'
    }

    $listenerState = Read-JsonFileIfExists -PathValue $listenerStatePath
    if ($null -eq $listenerState) {
        $listenerState = [pscustomobject]@{}
    }

    $archiveStamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddHHmmssfff')
    $archiveDir = Join-Path $ListenerStageDir (Join-Path 'archive\forced-execution-replay' ('{0}-{1}' -f $TaskId, $archiveStamp))
    $artifactPaths = @{
        'MIM_TOD_TASK_REQUEST.latest.json' = $requestPath
        'MIM_TO_TOD_TRIGGER.latest.json' = $triggerPath
        'TOD_MIM_COMMAND_STATUS.latest.json' = $statusPath
        'TOD_MIM_EXECUTION_DECISION.latest.json' = $decisionPath
        'TOD_MIM_TASK_RESULT.latest.json' = $resultPath
        'TOD_EXECUTION_REVIEW.latest.json' = $goOrderPath
        'listener_state.json' = $listenerStatePath
    }
    $archivedArtifacts = Archive-ForcedReplayArtifacts -ArtifactPaths $artifactPaths -ArchiveDir $archiveDir

    $replayRequest = New-ForcedReplayRequest -ExistingRequest $existingRequest -ObjectiveId $normalizedObjectiveId -TaskId $TaskId -Reason $Reason
    $replayTrigger = New-ForcedReplayTrigger -ReplayRequest $replayRequest -RemoteRoot $RemoteRoot
    $replayStatus = New-ForcedReplayCommandStatus -ReplayRequest $replayRequest -Reason $Reason
    $listenerState = Update-ListenerStateForForcedReplay -ListenerState $listenerState -ObjectiveId $normalizedObjectiveId -TaskId $TaskId -OriginalRequestId ([string]$existingRequest.request_id) -ReplayRequestId ([string]$replayRequest.request_id) -ReplayCorrelationId ([string]$replayRequest.correlation_id) -ReplayAttempt ([int]$replayRequest.replay_attempt) -Reason $Reason

    Write-JsonFile -PathValue $requestPath -Payload $replayRequest
    Write-JsonFile -PathValue $triggerPath -Payload $replayTrigger
    Write-JsonFile -PathValue $statusPath -Payload $replayStatus
    Write-JsonFile -PathValue $listenerStatePath -Payload $listenerState

    $remotePublish = Publish-ForcedReplayRemoteArtifacts -EnvFile $EnvFile -RemoteRoot $RemoteRoot -LocalArtifacts @{
        'MIM_TOD_TASK_REQUEST.latest.json' = $requestPath
        'MIM_TO_TOD_TRIGGER.latest.json' = $triggerPath
        'TOD_MIM_COMMAND_STATUS.latest.json' = $statusPath
        'listener_state.json' = $listenerStatePath
    }

    $report = [pscustomobject]@{
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        objective_id = $normalizedObjectiveId
        task_id = $TaskId
        replay_request_id = [string]$replayRequest.request_id
        replay_correlation_id = [string]$replayRequest.correlation_id
        replay_attempt = [int]$replayRequest.replay_attempt
        archived_artifacts = @($archivedArtifacts)
        archive_dir = $archiveDir
        remote_publish = $remotePublish
        replay_requires_fresh_execution_evidence = $true
        lineage = $replayRequest.lineage
    }
    $reportPath = Join-Path $archiveDir 'forced-execution-replay.report.json'
    Write-JsonFile -PathValue $reportPath -Payload $report

    return $report
}

$repoRoot = Get-RepoPath
if ([string]::IsNullOrWhiteSpace($ListenerStageDir)) {
    $ListenerStageDir = Join-Path $repoRoot 'tod\out\context-sync\listener'
}
if ([string]::IsNullOrWhiteSpace($EnvFile)) {
    $EnvFile = Join-Path $repoRoot '.env'
}

$result = Invoke-ForcedExecutionReplayInternal -ObjectiveId $ObjectiveId -TaskId $TaskId -Reason $Reason -Force:$Force -ListenerStageDir $ListenerStageDir -RemoteRoot $RemoteRoot -EnvFile $EnvFile
$result | ConvertTo-Json -Depth 20