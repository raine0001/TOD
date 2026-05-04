param(
    [string]$ListenerStageDir = "tod/out/context-sync/listener",
    [string]$IntegrationStatusPath = "shared_state/integration_status.json",
    [string]$OutputPath = "shared_state/TOD_MIM_BRIDGE_SMOKE.latest.json",
    [int]$FreshnessSeconds = 300,
    [string]$DotEnvPath = ".env",
    [string]$RemoteProbeScriptPath = "probe_canonical_task_request.py",
    [string]$RemoteProbeArtifactPath = "shared_state/TOD_MIM_REMOTE_REQUEST_PROBE.latest.json",
    [string]$RemoteProbeJsonPath = "",
    [string]$RemoteRequestPath = "/home/testpilot/mim/runtime/shared/MIM_TOD_TASK_REQUEST.latest.json",
    [int]$RemoteProbeSamples = 1,
    [double]$RemoteProbeIntervalSeconds = 0,
    [string]$RemoteBoundaryDiagnosticScriptPath = "scripts/Invoke-TODMimRemoteBoundaryDiagnostics.ps1",
    [string]$RemoteBoundaryDiagnosticArtifactPath = "shared_state/TOD_MIM_REMOTE_BOUNDARY_DIAGNOSTIC.latest.json",
    [string]$RemoteBoundaryDiagnosticJsonPath = "",
    [switch]$SkipRemoteProbe
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$authoritativeCommunicationHost = '192.168.1.120'
$authoritativeCommunicationRoot = '/home/testpilot/mim/runtime/shared'

function Get-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) { return $PathValue }
    return (Join-Path $repoRoot $PathValue)
}

function Read-JsonFileIfExists {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    $resolved = Get-LocalPath -PathValue $PathValue
    if (-not (Test-Path -Path $resolved -PathType Leaf)) {
        return $null
    }

    try {
        return (Get-Content -Path $resolved -Raw | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)]$Payload,
        [int]$Depth = 12
    )

    $resolved = Get-LocalPath -PathValue $PathValue
    $dir = Split-Path -Parent $resolved
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $json = ($Payload | ConvertTo-Json -Depth $Depth)
    [System.IO.File]::WriteAllText($resolved, $json, $utf8NoBom)
}

function Get-AgeSeconds {
    param([string]$Timestamp)

    if ([string]::IsNullOrWhiteSpace($Timestamp)) {
        return 999999
    }

    [datetime]$parsed = [datetime]::MinValue
    if (-not [datetime]::TryParse($Timestamp, [ref]$parsed)) {
        return 999999
    }

    return [int][math]::Floor(([datetime]::UtcNow - $parsed.ToUniversalTime()).TotalSeconds)
}

function Get-StringField {
    param(
        [AllowNull()]$InputObject,
        [Parameter(Mandatory = $true)][string]$FieldName
    )

    if ($null -eq $InputObject -or -not $InputObject.PSObject.Properties[$FieldName]) {
        return ""
    }

    return [string]$InputObject.$FieldName
}

function Get-DotEnvMap {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    $resolved = Get-LocalPath -PathValue $PathValue
    $map = @{}
    if (-not (Test-Path -Path $resolved -PathType Leaf)) {
        return $map
    }

    foreach ($rawLine in Get-Content -Path $resolved) {
        $line = ([string]$rawLine).Trim()
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#') -or -not $line.Contains('=')) {
            continue
        }

        $parts = $line.Split('=', 2)
        if ($parts.Count -ne 2) {
            continue
        }

        $key = ([string]$parts[0]).Trim()
        $value = ([string]$parts[1]).Trim().Trim('"').Trim("'")
        if (-not [string]::IsNullOrWhiteSpace($key) -and -not $map.ContainsKey($key)) {
            $map[$key] = $value
        }
    }

    return $map
}

function Get-DotEnvValue {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Map,
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$Default = ""
    )

    if ($Map.ContainsKey($Name) -and -not [string]::IsNullOrWhiteSpace([string]$Map[$Name])) {
        return [string]$Map[$Name]
    }

    return $Default
}

function Get-PythonCommand {
    $venvPython = Join-Path $repoRoot ".venv/Scripts/python.exe"
    if (Test-Path -Path $venvPython -PathType Leaf) {
        return $venvPython
    }

    $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
    if ($pythonCmd) {
        return $pythonCmd.Source
    }

    return ""
}

function Get-FileSha256 {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $stream = [System.IO.File]::OpenRead($PathValue)
        try {
            $hashBytes = $sha256.ComputeHash($stream)
        }
        finally {
            $stream.Dispose()
        }
        return ([System.BitConverter]::ToString($hashBytes)).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha256.Dispose()
    }
}

function Get-CanonicalRequestFingerprint {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)]$Packet
    )

    $resolved = Get-LocalPath -PathValue $PathValue
    if (-not (Test-Path -Path $resolved -PathType Leaf)) {
        return $null
    }

    $item = Get-Item -Path $resolved -ErrorAction Stop
    $taskId = Get-StringField -InputObject $Packet -FieldName 'task_id'
    if ([string]::IsNullOrWhiteSpace($taskId)) {
        $taskId = Get-StringField -InputObject $Packet -FieldName 'request_id'
    }

    return [pscustomobject]@{
        hostname = if (-not [string]::IsNullOrWhiteSpace([string]$env:COMPUTERNAME)) { [string]$env:COMPUTERNAME } else { [System.Environment]::MachineName }
        whoami = if (-not [string]::IsNullOrWhiteSpace([string]$env:USERNAME)) { [string]$env:USERNAME } else { [System.Environment]::UserName }
        absolute_path = $item.FullName
        realpath = $item.FullName
        inode = if ($item.PSObject.Properties['Inode']) { [string]$item.Inode } else { '' }
        mtime = $item.LastWriteTimeUtc.ToString('o')
        size = [int64]$item.Length
        sha256 = Get-FileSha256 -PathValue $resolved
        objective_id = Get-StringField -InputObject $Packet -FieldName 'objective_id'
        task_id = $taskId
        sequence = if ($Packet -and $Packet.PSObject.Properties['sequence']) { [string]$Packet.sequence } else { '' }
    }
}

function Get-AuthoritySurfaceFingerprint {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)]$Packet
    )

    $resolved = Get-LocalPath -PathValue $PathValue
    if (-not (Test-Path -Path $resolved -PathType Leaf)) {
        return $null
    }

    $item = Get-Item -Path $resolved -ErrorAction Stop
    $requestId = Get-StringField -InputObject $Packet -FieldName 'request_id'
    $taskId = Get-StringField -InputObject $Packet -FieldName 'task_id'
    if ([string]::IsNullOrWhiteSpace($taskId)) {
        $taskId = $requestId
    }

    return [pscustomobject]@{
        hostname = if (-not [string]::IsNullOrWhiteSpace([string]$env:COMPUTERNAME)) { [string]$env:COMPUTERNAME } else { [System.Environment]::MachineName }
        whoami = if (-not [string]::IsNullOrWhiteSpace([string]$env:USERNAME)) { [string]$env:USERNAME } else { [System.Environment]::UserName }
        absolute_path = $item.FullName
        realpath = $item.FullName
        inode = if ($item.PSObject.Properties['Inode']) { [string]$item.Inode } else { '' }
        mtime = $item.LastWriteTimeUtc.ToString('o')
        size = [int64]$item.Length
        sha256 = Get-FileSha256 -PathValue $resolved
        request_id = $requestId
        task_id = $taskId
        objective_id = Get-StringField -InputObject $Packet -FieldName 'objective_id'
        status = Get-StringField -InputObject $Packet -FieldName 'status'
        sequence = if ($Packet -and $Packet.PSObject.Properties['sequence']) { [string]$Packet.sequence } else { '' }
        generated_at = Get-StringField -InputObject $Packet -FieldName 'generated_at'
    }
}

function Invoke-RemoteCanonicalProbe {
    param(
        [string]$ProbeJsonPath,
        [string]$ProbeScriptPathValue,
        [string]$RemotePathValue,
        [int]$SamplesValue,
        [double]$IntervalSecondsValue,
        [string]$DotEnvPathValue
    )

    if (-not [string]::IsNullOrWhiteSpace($ProbeJsonPath)) {
        $doc = Read-JsonFileIfExists -PathValue $ProbeJsonPath
        if ($doc) {
            $doc | Add-Member -NotePropertyName available -NotePropertyValue $true -Force
            return $doc
        }
        return [pscustomobject]@{ available = $false; error = 'remote_probe_json_missing' }
    }

    $probeScriptAbs = Get-LocalPath -PathValue $ProbeScriptPathValue
    if (-not (Test-Path -Path $probeScriptAbs -PathType Leaf)) {
        return [pscustomobject]@{ available = $false; error = 'probe_script_missing' }
    }

    $pythonCommand = Get-PythonCommand
    if ([string]::IsNullOrWhiteSpace($pythonCommand)) {
        return [pscustomobject]@{ available = $false; error = 'python_not_found' }
    }

    $envMap = Get-DotEnvMap -PathValue $DotEnvPathValue
    $remoteHost = Get-DotEnvValue -Map $envMap -Name 'MIM_SSH_HOST' -Default 'mim'
    $remoteUser = Get-DotEnvValue -Map $envMap -Name 'MIM_SSH_USER' -Default 'testpilot'
    $remotePortText = Get-DotEnvValue -Map $envMap -Name 'MIM_SSH_PORT' -Default '22'
    $remotePort = 22
    [void][int]::TryParse($remotePortText, [ref]$remotePort)

    try {
        $raw = & $pythonCommand $probeScriptAbs --host $remoteHost --user $remoteUser --port $remotePort --path $RemotePathValue --samples $SamplesValue --interval-seconds $IntervalSecondsValue
        if ($LASTEXITCODE -ne 0) {
            return [pscustomobject]@{ available = $false; error = (($raw | Out-String).Trim()) }
        }

        $doc = ($raw | Out-String | ConvertFrom-Json)
        $doc | Add-Member -NotePropertyName available -NotePropertyValue $true -Force
        Write-JsonFile -PathValue $RemoteProbeArtifactPath -Payload $doc -Depth 20
        return $doc
    }
    catch {
        return [pscustomobject]@{ available = $false; error = [string]$_.Exception.Message }
    }
}

function Invoke-RemoteBoundaryDiagnostic {
    param(
        [string]$DiagnosticJsonPath,
        [string]$DiagnosticScriptPathValue,
        [string]$DiagnosticArtifactPathValue,
        [string]$ProbeArtifactPathValue
    )

    if (-not [string]::IsNullOrWhiteSpace($DiagnosticJsonPath)) {
        $doc = Read-JsonFileIfExists -PathValue $DiagnosticJsonPath
        if ($doc) {
            $doc | Add-Member -NotePropertyName available -NotePropertyValue $true -Force
            return $doc
        }

        return [pscustomobject]@{ available = $false; error = 'remote_boundary_diagnostic_json_missing' }
    }

    $diagnosticScriptAbs = Get-LocalPath -PathValue $DiagnosticScriptPathValue
    if (-not (Test-Path -Path $diagnosticScriptAbs -PathType Leaf)) {
        return [pscustomobject]@{ available = $false; error = 'remote_boundary_diagnostic_script_missing' }
    }

    try {
        $raw = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $diagnosticScriptAbs -DotEnvPath $DotEnvPath -ProbeScriptPath $RemoteProbeScriptPath -OutputPath $DiagnosticArtifactPathValue -ProbeOutputPath $ProbeArtifactPathValue
        if ($LASTEXITCODE -ne 0) {
            return [pscustomobject]@{ available = $false; error = (($raw | Out-String).Trim()) }
        }

        $doc = Read-JsonFileIfExists -PathValue $DiagnosticArtifactPathValue
        if ($doc) {
            $doc | Add-Member -NotePropertyName available -NotePropertyValue $true -Force
            return $doc
        }

        return [pscustomobject]@{ available = $false; error = 'remote_boundary_diagnostic_output_missing' }
    }
    catch {
        return [pscustomobject]@{ available = $false; error = [string]$_.Exception.Message }
    }
}

function Get-BoolField {
    param(
        [AllowNull()]$InputObject,
        [Parameter(Mandatory = $true)][string]$FieldName,
        [bool]$Default = $false
    )

    if ($null -eq $InputObject -or -not $InputObject.PSObject.Properties[$FieldName]) {
        return $Default
    }

    try {
        return [bool]$InputObject.$FieldName
    }
    catch {
        return $Default
    }
}

function Get-TaskRefInfo {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $match = [regex]::Match($Value, 'objective-(?<objective>\d+)-task-(?<suffix>.+)$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) {
        return $null
    }

    $taskNumberMatch = [regex]::Match([string]$match.Groups['suffix'].Value, '(?<task>\d+)(?!.*\d)')
    if (-not $taskNumberMatch.Success) {
        return $null
    }

    return [pscustomobject]@{
        objective = [string]$match.Groups['objective'].Value
        task_number = [long]$taskNumberMatch.Groups['task'].Value
    }
}

$listenerRoot = Get-LocalPath -PathValue $ListenerStageDir
$requestPath = Join-Path $listenerRoot "MIM_TOD_TASK_REQUEST.latest.json"
$requestPacket = Read-JsonFileIfExists -PathValue $requestPath
$ackPacket = Read-JsonFileIfExists -PathValue (Join-Path $listenerRoot "TOD_TO_MIM_TRIGGER_ACK.latest.json")
$taskAckPacket = Read-JsonFileIfExists -PathValue (Join-Path $listenerRoot "TOD_MIM_TASK_ACK.latest.json")
$resultPath = Join-Path $listenerRoot "TOD_MIM_TASK_RESULT.latest.json"
$resultPacket = Read-JsonFileIfExists -PathValue $resultPath
$listenerState = Read-JsonFileIfExists -PathValue (Join-Path $listenerRoot "listener_state.json")
$integration = Read-JsonFileIfExists -PathValue $IntegrationStatusPath
$localRequestFingerprint = if ($requestPacket) { Get-CanonicalRequestFingerprint -PathValue $requestPath -Packet $requestPacket } else { $null }
$localResultFingerprint = if ($resultPacket) { Get-AuthoritySurfaceFingerprint -PathValue $resultPath -Packet $resultPacket } else { $null }
$remoteRequestFingerprint = if ($SkipRemoteProbe) { [pscustomobject]@{ available = $false; error = 'remote_probe_skipped' } } else { Invoke-RemoteCanonicalProbe -ProbeJsonPath $RemoteProbeJsonPath -ProbeScriptPathValue $RemoteProbeScriptPath -RemotePathValue $RemoteRequestPath -SamplesValue $RemoteProbeSamples -IntervalSecondsValue $RemoteProbeIntervalSeconds -DotEnvPathValue $DotEnvPath }
$remoteBoundaryDiagnostic = Invoke-RemoteBoundaryDiagnostic -DiagnosticJsonPath $RemoteBoundaryDiagnosticJsonPath -DiagnosticScriptPathValue $RemoteBoundaryDiagnosticScriptPath -DiagnosticArtifactPathValue $RemoteBoundaryDiagnosticArtifactPath -ProbeArtifactPathValue $RemoteProbeArtifactPath

$requestAgeSeconds = if ($requestPacket -and $requestPacket.PSObject.Properties["generated_at"]) { Get-AgeSeconds -Timestamp ([string]$requestPacket.generated_at) } else { 999999 }
$ackAgeSeconds = if ($ackPacket -and $ackPacket.PSObject.Properties["generated_at"]) { Get-AgeSeconds -Timestamp ([string]$ackPacket.generated_at) } else { 999999 }
$taskAckAgeSeconds = if ($taskAckPacket -and $taskAckPacket.PSObject.Properties["generated_at"]) { Get-AgeSeconds -Timestamp ([string]$taskAckPacket.generated_at) } else { 999999 }
$resultAgeSeconds = if ($resultPacket -and $resultPacket.PSObject.Properties["generated_at"]) { Get-AgeSeconds -Timestamp ([string]$resultPacket.generated_at) } else { 999999 }
$listenerCycleAgeSeconds = if ($listenerState -and $listenerState.PSObject.Properties["last_cycle_at"]) { Get-AgeSeconds -Timestamp ([string]$listenerState.last_cycle_at) } else { 999999 }

$acknowledgedTriggerSequence = 0L
if ($ackPacket -and $ackPacket.PSObject.Properties["acknowledged_trigger_sequence"]) {
    try { $acknowledgedTriggerSequence = [long]$ackPacket.acknowledged_trigger_sequence } catch { $acknowledgedTriggerSequence = 0L }
}

$requestId = Get-StringField -InputObject $requestPacket -FieldName "task_id"
if ([string]::IsNullOrWhiteSpace($requestId)) {
    $requestId = Get-StringField -InputObject $requestPacket -FieldName "request_id"
}

$acknowledges = Get-StringField -InputObject $ackPacket -FieldName "acknowledges"
$taskAckRequestId = Get-StringField -InputObject $taskAckPacket -FieldName "request_id"
if ([string]::IsNullOrWhiteSpace($taskAckRequestId)) {
    $taskAckRequestId = Get-StringField -InputObject $taskAckPacket -FieldName "task_id"
}
$taskAckStatus = (Get-StringField -InputObject $taskAckPacket -FieldName "status").Trim().ToLowerInvariant()
$resultTaskId = Get-StringField -InputObject $resultPacket -FieldName "task_id"
$resultStatus = (Get-StringField -InputObject $resultPacket -FieldName "status").Trim().ToLowerInvariant()
$staleRequestId = ""
if ($resultPacket -and $resultPacket.PSObject.Properties['stale_request'] -and $resultPacket.stale_request) {
    $staleRequestId = Get-StringField -InputObject $resultPacket.stale_request -FieldName "task_id"
    if ([string]::IsNullOrWhiteSpace($staleRequestId)) {
        $staleRequestId = Get-StringField -InputObject $resultPacket.stale_request -FieldName "request_id"
    }
}
$requestRef = Get-TaskRefInfo -Value $requestId
$resultRef = Get-TaskRefInfo -Value $resultTaskId
$staleRequestRef = Get-TaskRefInfo -Value $staleRequestId
$highWatermarkTaskId = Get-StringField -InputObject $listenerState -FieldName 'high_watermark_request_id'
if ([string]::IsNullOrWhiteSpace($highWatermarkTaskId) -and $taskAckPacket -and $taskAckPacket.PSObject.Properties['bridge_runtime'] -and $taskAckPacket.bridge_runtime -and $taskAckPacket.bridge_runtime.PSObject.Properties['current_processing'] -and $taskAckPacket.bridge_runtime.current_processing) {
    $highWatermarkTaskId = Get-StringField -InputObject $taskAckPacket.bridge_runtime.current_processing -FieldName 'task_id'
}
$highWatermarkTaskRef = Get-TaskRefInfo -Value $highWatermarkTaskId
$staleBackfillSuperseded =
    (-not [string]::IsNullOrWhiteSpace($staleRequestId)) -and
    [string]::Equals($staleRequestId, $requestId, [System.StringComparison]::OrdinalIgnoreCase) -and
    $requestRef -and
    $resultRef -and
    $staleRequestRef -and
    [string]::Equals([string]$requestRef.objective, [string]$resultRef.objective, [System.StringComparison]::OrdinalIgnoreCase) -and
    [string]::Equals([string]$requestRef.objective, [string]$staleRequestRef.objective, [System.StringComparison]::OrdinalIgnoreCase) -and
    ([long]$resultRef.task_number -gt [long]$requestRef.task_number) -and
    @('completed', 'already_processed', 'stale_request_ignored') -contains $resultStatus
$staleTerminalAckHealthy =
    (-not [string]::IsNullOrWhiteSpace($taskAckRequestId)) -and
    [string]::Equals($taskAckRequestId, $requestId, [System.StringComparison]::OrdinalIgnoreCase) -and
    @('stale_ignored', 'superseded_ignored') -contains $taskAckStatus -and
    ($taskAckAgeSeconds -lt $FreshnessSeconds) -and
    $requestRef -and
    $highWatermarkTaskRef -and
    [string]::Equals([string]$requestRef.objective, [string]$highWatermarkTaskRef.objective, [System.StringComparison]::OrdinalIgnoreCase) -and
    ([long]$highWatermarkTaskRef.task_number -gt [long]$requestRef.task_number)
$requestMatchesAck = (-not [string]::IsNullOrWhiteSpace($requestId)) -and [string]::Equals($requestId, $acknowledges, [System.StringComparison]::OrdinalIgnoreCase)
$resultMatchesRequest = (-not [string]::IsNullOrWhiteSpace($requestId)) -and [string]::Equals($requestId, $resultTaskId, [System.StringComparison]::OrdinalIgnoreCase)

if ($staleBackfillSuperseded -or $staleTerminalAckHealthy) {
    $requestMatchesAck = $true
    $resultMatchesRequest = $true
}

$reviewGatePassed = $false
if ($resultPacket -and $resultPacket.PSObject.Properties["review_gate"] -and $resultPacket.review_gate -and $resultPacket.review_gate.PSObject.Properties["passed"]) {
    try { $reviewGatePassed = [bool]$resultPacket.review_gate.passed } catch { $reviewGatePassed = $false }
}
elseif ($staleBackfillSuperseded -and [string]::Equals($resultStatus, 'completed', [System.StringComparison]::OrdinalIgnoreCase)) {
    $reviewGatePassed = $true
}
elseif ($staleTerminalAckHealthy) {
    $reviewGatePassed = $true
}

$recentBridgeMutation = ($ackAgeSeconds -lt $FreshnessSeconds) -or ($taskAckAgeSeconds -lt $FreshnessSeconds) -or ($resultAgeSeconds -lt $FreshnessSeconds) -or ($listenerCycleAgeSeconds -lt $FreshnessSeconds)
$localBridgeHealthy = $recentBridgeMutation -and ($acknowledgedTriggerSequence -gt 0) -and $requestMatchesAck -and $resultMatchesRequest -and $reviewGatePassed

$objectiveInSync = $false
if ($integration -and $integration.PSObject.Properties["objective_alignment"] -and $integration.objective_alignment -and $integration.objective_alignment.PSObject.Properties["status"]) {
    $objectiveInSync = ([string]$integration.objective_alignment.status -eq "in_sync")
}

$latestCompletedObjectiveId = ''
if ($integration -and $integration.PSObject.Properties['mim_handshake'] -and $integration.mim_handshake) {
    $candidateCompleted = Get-StringField -InputObject $integration.mim_handshake -FieldName 'latest_completed_objective'
    if (-not [string]::IsNullOrWhiteSpace($candidateCompleted) -and $candidateCompleted -notmatch '^(?i)objective-') {
        $latestCompletedObjectiveId = 'objective-' + $candidateCompleted
    }
    else {
        $latestCompletedObjectiveId = $candidateCompleted
    }
}

$bridgeEvidence = if ($integration -and $integration.PSObject.Properties["bridge_canonical_evidence"]) { $integration.bridge_canonical_evidence } else { $null }
$remotePublishVerified = Get-BoolField -InputObject $bridgeEvidence -FieldName "remote_publish_verified"
if (-not $remotePublishVerified -and $integration -and $integration.PSObject.Properties["tod_status_publish"]) {
    $publish = $integration.tod_status_publish
    $remotePublishVerified = ([string](Get-StringField -InputObject $publish -FieldName "status") -eq "uploaded") -and ([string](Get-StringField -InputObject $publish -FieldName "mim_mirror_status") -eq "mirrored") -and ([string](Get-StringField -InputObject $publish -FieldName "remote_access_status") -eq "full_access_granted") -and ([string](Get-StringField -InputObject $publish -FieldName "consumer_status") -eq "executed")
}

$failureModes = @()
$expectedObjectiveId = if ($integration -and $integration.PSObject.Properties['objective_alignment']) {
    $candidate = Get-StringField -InputObject $integration.objective_alignment -FieldName 'mim_objective_active'
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        $candidate = Get-StringField -InputObject $integration.objective_alignment -FieldName 'tod_current_objective'
    }
    if (-not [string]::IsNullOrWhiteSpace($candidate) -and $candidate -notmatch '^(?i)objective-') {
        'objective-' + $candidate
    }
    else {
        $candidate
    }
} else { '' }
$expectedTaskId = ''
if ($integration -and $integration.PSObject.Properties['mim_handshake'] -and $integration.mim_handshake -and $integration.mim_handshake.PSObject.Properties['source_of_truth'] -and $integration.mim_handshake.source_of_truth -and $integration.mim_handshake.source_of_truth.PSObject.Properties['formal_program_truth'] -and $integration.mim_handshake.source_of_truth.formal_program_truth) {
    $formalProgramTruth = $integration.mim_handshake.source_of_truth.formal_program_truth
    $formalTaskId = Get-StringField -InputObject $formalProgramTruth -FieldName 'task_id'
    if (-not [string]::IsNullOrWhiteSpace($formalTaskId)) {
        if ($formalTaskId -match '^(?i)objective-') {
            $expectedTaskId = $formalTaskId
        }
        elseif (-not [string]::IsNullOrWhiteSpace($expectedObjectiveId)) {
            $expectedTaskId = ('{0}-task-{1}' -f $expectedObjectiveId, $formalTaskId)
        }
    }
}

$remoteProbeAvailable = [bool]($remoteRequestFingerprint -and $remoteRequestFingerprint.PSObject.Properties['available'] -and [bool]$remoteRequestFingerprint.available)
$remoteBoundaryAvailable = [bool]($remoteBoundaryDiagnostic -and $remoteBoundaryDiagnostic.PSObject.Properties['available'] -and [bool]$remoteBoundaryDiagnostic.available)
$remoteBoundaryClassification = if ($remoteBoundaryAvailable -and $remoteBoundaryDiagnostic.PSObject.Properties['remote_boundary'] -and $remoteBoundaryDiagnostic.remote_boundary -and $remoteBoundaryDiagnostic.remote_boundary.PSObject.Properties['classification']) { [string]$remoteBoundaryDiagnostic.remote_boundary.classification } else { '' }
$noncanonicalRemoteSurface = [string]::Equals($remoteBoundaryClassification, 'noncanonical_remote_surface', [System.StringComparison]::OrdinalIgnoreCase)
$remoteObjectiveId = if ($remoteProbeAvailable -and $remoteRequestFingerprint.PSObject.Properties['objective_id']) { [string]$remoteRequestFingerprint.objective_id } else { '' }
$remoteTaskId = if ($remoteProbeAvailable -and $remoteRequestFingerprint.PSObject.Properties['task_id']) { [string]$remoteRequestFingerprint.task_id } else { '' }
$remoteSequence = if ($remoteProbeAvailable -and $remoteRequestFingerprint.PSObject.Properties['sequence']) { [string]$remoteRequestFingerprint.sequence } else { '' }
$canonicalRequestMismatch = $false
if ($remoteProbeAvailable -and $localRequestFingerprint) {
    $canonicalRequestMismatch = @(
        [string]$localRequestFingerprint.sha256 -ne [string]$remoteRequestFingerprint.sha256,
        [string]$localRequestFingerprint.objective_id -ne $remoteObjectiveId,
        [string]$localRequestFingerprint.task_id -ne $remoteTaskId,
        [string]$localRequestFingerprint.sequence -ne $remoteSequence
    ) -contains $true
}

$publicationSurfaceDivergence = $false
$staleRemoteRequestIdentity = $false
if ($remoteProbeAvailable -and (
        (-not [string]::IsNullOrWhiteSpace($expectedObjectiveId) -and -not [string]::Equals($remoteObjectiveId, $expectedObjectiveId, [System.StringComparison]::OrdinalIgnoreCase)) -or
        (-not [string]::IsNullOrWhiteSpace($expectedTaskId) -and -not [string]::Equals($remoteTaskId, $expectedTaskId, [System.StringComparison]::OrdinalIgnoreCase))
    )) {
    $publicationSurfaceDivergence = $true
    $staleRemoteRequestIdentity = $true
}

$completedObjectiveResidue = $false
$localResultTerminal = @('completed', 'succeeded', 'failed', 'blocked', 'already_processed', 'stale_request_ignored') -contains $resultStatus
if (
    $publicationSurfaceDivergence -and
    [string]::IsNullOrWhiteSpace($expectedTaskId) -and
    $objectiveInSync -and
    $localResultTerminal -and
    -not [string]::IsNullOrWhiteSpace($resultTaskId) -and
    [string]::Equals($resultTaskId, $requestId, [System.StringComparison]::OrdinalIgnoreCase) -and
    -not [string]::IsNullOrWhiteSpace($latestCompletedObjectiveId) -and
    [string]::Equals($latestCompletedObjectiveId, $remoteObjectiveId, [System.StringComparison]::OrdinalIgnoreCase)
) {
    $completedObjectiveResidue = $true
    $publicationSurfaceDivergence = $false
    $staleRemoteRequestIdentity = $false
}

if ($completedObjectiveResidue) {
    $localBridgeHealthy = $true
}

if ($publicationSurfaceDivergence) {
    $failureModes += 'publication_surface_divergence'
}
if ($noncanonicalRemoteSurface) {
    $failureModes += 'noncanonical_remote_surface'
}
if ($staleRemoteRequestIdentity) {
    $failureModes += 'stale_remote_request_identity'
}
if ($canonicalRequestMismatch) {
    $failureModes += 'canonical_request_mismatch'
}
if (-not $remoteProbeAvailable) {
    $failureModes += 'noncanonical_remote_surface'
}
if ((-not $remotePublishVerified) -and -not $publicationSurfaceDivergence) {
    $failureModes += 'remote_publish_not_verified'
}
if ((-not $objectiveInSync) -and -not $publicationSurfaceDivergence) {
    $failureModes += 'objective_alignment_not_in_sync'
}
if ((-not $localBridgeHealthy) -and -not $publicationSurfaceDivergence) {
    $failureModes += 'listener_contract_stalled'
}

$classification = 'pass'
$failureReason = ''
if (@($failureModes).Count -gt 0) {
    if ($publicationSurfaceDivergence) {
        $classification = 'publication_surface_divergence'
        $failureReason = 'publication_surface_divergence'
    }
    elseif ($noncanonicalRemoteSurface) {
        $classification = 'noncanonical_remote_surface'
        $failureReason = 'noncanonical_remote_surface'
    }
    elseif ($canonicalRequestMismatch) {
        $classification = 'canonical_request_mismatch'
        $failureReason = 'canonical_request_mismatch'
    }
    elseif (-not $remoteProbeAvailable) {
        $classification = 'noncanonical_remote_surface'
        $failureReason = 'noncanonical_remote_surface'
    }
    elseif (@($failureModes) -contains 'listener_contract_stalled') {
        $classification = 'listener_contract_stalled'
        $failureReason = 'listener_contract_stalled'
    }
    else {
        $classification = [string]$failureModes[0]
        $failureReason = [string]$failureModes[0]
    }
}

$envMap = Get-DotEnvMap -PathValue $DotEnvPath
$configuredCommunicationHost = Get-DotEnvValue -Map $envMap -Name 'MIM_SSH_HOST' -Default 'mim'

$smoke = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = "tod-mim-bridge-smoke-v1"
    freshness_seconds = $FreshnessSeconds
    passed = (@($failureModes).Count -eq 0)
    status = if (@($failureModes).Count -eq 0) { "pass" } else { "fail" }
    classification = $classification
    failure_reason = $failureReason
    failure_modes = @($failureModes)
    canonical_request = [pscustomobject]@{
        expected_objective_id = $expectedObjectiveId
        expected_task_id = $expectedTaskId
        local_listener_mirror = $localRequestFingerprint
        remote_surface = $remoteRequestFingerprint
        canonical_request_mismatch = [bool]$canonicalRequestMismatch
        publication_surface_divergence = [bool]$publicationSurfaceDivergence
        noncanonical_remote_surface = [bool]$noncanonicalRemoteSurface
        stale_remote_request_identity = [bool]$staleRemoteRequestIdentity
        completed_objective_residue = [bool]$completedObjectiveResidue
        latest_completed_objective_id = $latestCompletedObjectiveId
    }
    remote_boundary = $remoteBoundaryDiagnostic
    local_bridge = [pscustomobject]@{
        healthy = [bool]$localBridgeHealthy
        request_id = if ($staleBackfillSuperseded) { $resultTaskId } else { $requestId }
        raw_request_id = $requestId
        authoritative_result_request_id = if ($localResultFingerprint) { [string]$localResultFingerprint.request_id } else { '' }
        authoritative_result_task_id = if ($localResultFingerprint) { [string]$localResultFingerprint.task_id } else { '' }
        stale_backfill_superseded = [bool]$staleBackfillSuperseded
        stale_terminal_ack_healthy = [bool]$staleTerminalAckHealthy
        recent_bridge_mutation = [bool]$recentBridgeMutation
        request_age_seconds = $requestAgeSeconds
        ack_age_seconds = $ackAgeSeconds
        task_ack_age_seconds = $taskAckAgeSeconds
        task_ack_status = $taskAckStatus
        result_age_seconds = $resultAgeSeconds
        listener_cycle_age_seconds = $listenerCycleAgeSeconds
        acknowledged_trigger_sequence = $acknowledgedTriggerSequence
        request_matches_ack = [bool]$requestMatchesAck
        result_matches_request = [bool]$resultMatchesRequest
        review_gate_passed = [bool]$reviewGatePassed
        local_result_terminal = [bool]$localResultTerminal
        completed_objective_residue = [bool]$completedObjectiveResidue
    }
    authority_surfaces = [pscustomobject]@{
        communication = [pscustomobject]@{
            host = $authoritativeCommunicationHost
            path = $authoritativeCommunicationRoot
            role = 'communication_authority'
            configured_host = $configuredCommunicationHost
            configured_host_matches_policy = [string]::Equals($configuredCommunicationHost, $authoritativeCommunicationHost, [System.StringComparison]::OrdinalIgnoreCase)
            non_authoritative_surfaces = @(
                [pscustomobject]@{ host = '192.168.1.90'; path = '/home/testpilot/mim/runtime/shared'; role = 'arm-side runtime/telemetry'; authoritative_for_communication = $false },
                [pscustomobject]@{ host = '192.168.1.90'; path = '/home/testpilot/mim_arm/runtime/shared'; role = 'arm-side runtime/telemetry'; authoritative_for_communication = $false },
                [pscustomobject]@{ host = 'local'; path = 'tod/out/context-sync/*'; role = 'local mirrors'; authoritative_for_communication = $false }
            )
        }
        result = [pscustomobject]@{
            source = 'tod_listener_stage_result_latest'
            authoritative_for = 'result_match_and_reconciliation'
            local_path = $resultPath
            local_surface = $localResultFingerprint
            note = 'This TOD-synced listener-stage result surface is authoritative for result reconciliation only. Communication truth remains 192.168.1.120:/home/testpilot/mim/runtime/shared; arm-host surfaces and local mirrors are non-authoritative for communication truth.'
        }
    }
    remote_publish = [pscustomobject]@{
        verified = [bool]$remotePublishVerified
        canonical_evidence_source = Get-StringField -InputObject $bridgeEvidence -FieldName "evidence_source"
        status = if ($integration -and $integration.PSObject.Properties["tod_status_publish"]) { Get-StringField -InputObject $integration.tod_status_publish -FieldName "status" } else { "" }
        mim_mirror_status = if ($integration -and $integration.PSObject.Properties["tod_status_publish"]) { Get-StringField -InputObject $integration.tod_status_publish -FieldName "mim_mirror_status" } else { "" }
        remote_access_status = if ($integration -and $integration.PSObject.Properties["tod_status_publish"]) { Get-StringField -InputObject $integration.tod_status_publish -FieldName "remote_access_status" } else { "" }
        consumer_status = if ($integration -and $integration.PSObject.Properties["tod_status_publish"]) { Get-StringField -InputObject $integration.tod_status_publish -FieldName "consumer_status" } else { "" }
    }
    objective_alignment = [pscustomobject]@{
        in_sync = [bool]$objectiveInSync
        tod_current_objective = if ($integration -and $integration.PSObject.Properties["objective_alignment"]) { Get-StringField -InputObject $integration.objective_alignment -FieldName "tod_current_objective" } else { "" }
        mim_objective_active = if ($integration -and $integration.PSObject.Properties["objective_alignment"]) { Get-StringField -InputObject $integration.objective_alignment -FieldName "mim_objective_active" } else { "" }
    }
}

Write-JsonFile -PathValue $OutputPath -Payload $smoke -Depth 12
$smoke | ConvertTo-Json -Depth 12 | Write-Output

if (-not [bool]$smoke.passed) {
    throw ("Bridge smoke failed: {0}" -f ($failureModes -join ", "))
}