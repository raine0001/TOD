param(
    [string]$FindingsPath = 'shared_state/tod_codex_next_steps.latest.json',
    [string]$OutputPath = 'shared_state/NEXT_STEP_CONSENSUS.latest.json',
    [string]$DialogDir = 'shared_state/dialog',
    [string]$ParityArtifactPath = 'tod/out/results-v2/tod-mim-execution-parity.latest.json',
    [string]$MimPositionJsonPath = '',
    [int]$WaitSeconds = 5,
    [int]$PollMilliseconds = 400
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$dialogScriptPath = Join-Path $PSScriptRoot 'Invoke-TODMimDialog.ps1'

function Get-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return [System.IO.Path]::GetFullPath($PathValue)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $PathValue))
}

function Ensure-ParentDirectoryForFile {
    param([Parameter(Mandatory = $true)][string]$FilePath)

    $dir = Split-Path -Parent $FilePath
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

function Write-Utf8NoBomJson {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)]$Payload,
        [int]$Depth = 20
    )

    Ensure-ParentDirectoryForFile -FilePath $PathValue
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $json = ($Payload | ConvertTo-Json -Depth $Depth) -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($PathValue, $json, $utf8NoBom)
}

function Read-JsonFile {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if (-not (Test-Path -Path $PathValue -PathType Leaf)) {
        return $null
    }

    try {
        return (Get-Content -Path $PathValue -Raw | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Convert-ToStringArray {
    param($Value)

    if ($null -eq $Value) { return @() }
    if ($Value -is [string]) {
        if ([string]::IsNullOrWhiteSpace($Value)) { return @() }
        return @([string]$Value)
    }

    return @($Value | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Get-ActionPriority {
    param([string]$ActionType)

    switch (([string]$ActionType).ToLowerInvariant()) {
        'validate' { return 100 }
        'observe' { return 90 }
        'refresh' { return 80 }
        'rebuild' { return 75 }
        'cleanup' { return 70 }
        'repair' { return 60 }
        'promote' { return 40 }
        default { return 50 }
    }
}

function Get-RiskScore {
    param([string]$Risk)

    switch (([string]$Risk).ToLowerInvariant()) {
        'low' { return 20 }
        'medium' { return 10 }
        default { return 0 }
    }
}

function Resolve-TodFindingPosition {
    param([Parameter(Mandatory = $true)]$Finding)

    $decision = 'approve'
    $reason = 'TOD accepts this finding for bounded next-step adjudication.'
    if ([bool]$Finding.approval_required) {
        $decision = 'approval_required'
        $reason = 'TOD marks this finding approval-required because it crosses a guarded execution boundary.'
    }
    elseif ([string]$Finding.owner_workspace -eq 'MIM') {
        $decision = 'defer'
        $reason = 'TOD defers primary ownership to MIM while still contributing local execution truth.'
    }

    [pscustomobject]@{
        finding_id = [string]$Finding.finding_id
        decision = $decision
        reason = $reason
        confidence = [math]::Round([double]$Finding.confidence, 2)
        local_blockers = @()
    }
}

function Normalize-MimPositions {
    param($Payload)

    if ($null -eq $Payload) {
        return [pscustomobject]@{
            available = $false
            source = 'none'
            summary = 'MIM position unavailable.'
            finding_positions = @()
        }
    }

    $positions = @()
    if ($Payload.PSObject.Properties['finding_positions']) {
        $positions = @($Payload.finding_positions)
    }
    elseif ($Payload.PSObject.Properties['positions']) {
        $positions = @($Payload.positions)
    }
    elseif ($Payload.PSObject.Properties['mim_position'] -and $Payload.mim_position -and $Payload.mim_position.PSObject.Properties['finding_positions']) {
        $positions = @($Payload.mim_position.finding_positions)
    }

    [pscustomobject]@{
        available = (@($positions).Count -gt 0)
        source = if ($Payload.PSObject.Properties['source']) { [string]$Payload.source } else { 'mim_reply' }
        summary = if ($Payload.PSObject.Properties['summary']) { [string]$Payload.summary } else { 'MIM position loaded.' }
        finding_positions = @($positions | ForEach-Object {
                [pscustomobject]@{
                    finding_id = if ($_.PSObject.Properties['finding_id']) { [string]$_.finding_id } else { '' }
                    decision = if ($_.PSObject.Properties['decision']) { [string]$_.decision } else { 'approve' }
                    reason = if ($_.PSObject.Properties['reason']) { [string]$_.reason } else { '' }
                    confidence = if ($_.PSObject.Properties['confidence']) { [double]$_.confidence } else { 0.6 }
                    local_blockers = @(Convert-ToStringArray -Value $(if ($_.PSObject.Properties['local_blockers']) { $_.local_blockers } else { @() }))
                }
            })
    }
}

function Get-ParityAuthority {
    param([Parameter(Mandatory = $true)][string]$ParityPathValue)

    $doc = Read-JsonFile -PathValue $ParityPathValue
    if ($null -eq $doc) {
        return [pscustomobject]@{
            active = $false
            source = 'parity_unavailable'
            summary = 'Execution parity artifact unavailable.'
            path = $ParityPathValue
        }
    }

    $compatible = if ($doc.PSObject.Properties['compatible']) { [bool]$doc.compatible } else { $false }
    $mismatchCount = if ($doc.PSObject.Properties['mismatch_count']) { [int]$doc.mismatch_count } else { 0 }
    $warningCount = if ($doc.PSObject.Properties['warning_count']) { [int]$doc.warning_count } else { 0 }
    $parityGreen = $compatible -and ($mismatchCount -eq 0) -and ($warningCount -eq 0)

    return [pscustomobject]@{
        active = $parityGreen
        source = if ($parityGreen) { 'tod_parity_green_local_authority' } else { 'parity_not_green' }
        summary = if ($parityGreen) { 'Execution parity is green, so TOD may select the next natural step locally without waiting for MIM.' } else { 'Execution parity is not green enough for TOD-only next-step authority.' }
        path = $ParityPathValue
        compatible = $compatible
        mismatch_count = $mismatchCount
        warning_count = $warningCount
    }
}

function Send-MimDecisionReminder {
    param(
        [Parameter(Mandatory = $true)]$Artifact,
        [Parameter(Mandatory = $true)][string]$DialogDirPath,
        [Parameter(Mandatory = $true)][string]$SessionId,
        [Parameter(Mandatory = $true)][string]$ReplyByUtc
    )

    if (-not (Test-Path -Path $dialogScriptPath)) {
        return [pscustomobject]@{
            sent = $false
            source = 'dialog_unavailable'
            summary = 'Dialog script not available for reminder.'
        }
    }

    $reminderPayload = [ordered]@{
        request_kind = 'next_step_consensus_reminder'
        decision_required = $true
        original_session_id = $SessionId
        original_request_kind = 'next_step_consensus'
        reminder_reason = 'decision_overdue'
        instruction = 'TOD still requires a MIM handoff_response on this session. Reply with summary plus finding_positions decision entries.'
        response_contract = [ordered]@{
            actor = 'MIM'
            message_type = 'handoff_response'
            intent = 'next_step_consensus'
            reply_by_utc = $ReplyByUtc
            required_fields = @(
                'summary',
                'finding_positions[].finding_id',
                'finding_positions[].decision',
                'finding_positions[].reason',
                'finding_positions[].confidence',
                'finding_positions[].local_blockers'
            )
        }
        objective_id = [string]$Artifact.objective_id
        task_id = [string]$Artifact.task_id
        run_id = [string]$Artifact.run_id
        findings = @($Artifact.findings | ForEach-Object {
                [pscustomobject]@{
                    finding_id = [string]$_.finding_id
                    description = [string]$_.description
                    action_type = [string]$_.action_type
                    risk = [string]$_.risk
                }
            })
    }

    try {
        $result = (& $dialogScriptPath -Action send -DialogDir $DialogDirPath -SessionId $SessionId -Actor TOD -PeerActor MIM -MessageType status_request -Intent next_step_consensus_reminder -TaskId ([string]$Artifact.task_id) -Summary ("TOD is still awaiting a MIM decision on this next-step consensus session for run {0}. Reply here with handoff_response finding_positions." -f [string]$Artifact.run_id) -PayloadJson ($reminderPayload | ConvertTo-Json -Depth 14 -Compress) -PublishRemote -EmitJson | ConvertFrom-Json)
        return [pscustomobject]@{
            sent = $true
            source = 'dialog_reminder'
            summary = 'TOD sent a next-step decision reminder to MIM on the open session.'
            message = $result.message
        }
    }
    catch {
        return [pscustomobject]@{
            sent = $false
            source = 'dialog_reminder_failed'
            summary = [string]$_.Exception.Message
        }
    }
}

function Get-MimPositionsFromDialog {
    param(
        [Parameter(Mandatory = $true)]$Artifact,
        [Parameter(Mandatory = $true)][string]$DialogDirPath
    )

    if (-not (Test-Path -Path $dialogScriptPath)) {
        return [pscustomobject]@{
            available = $false
            source = 'dialog_unavailable'
            summary = 'Dialog script not available.'
            finding_positions = @()
            session_id = ''
        }
    }

    $sessionId = 'next-step-{0}-{1}' -f ([string]$Artifact.task_id).ToLowerInvariant(), ([string]$Artifact.run_id).ToLowerInvariant().Replace(':', '-').Replace(' ', '-')
    $replyByUtc = (Get-Date).ToUniversalTime().AddSeconds($WaitSeconds).ToString('o')
    $requestPayload = [ordered]@{
        request_kind = 'next_step_consensus'
        decision_required = $true
        instruction = 'MIM must publish a per-finding decision response for next-step consensus. Reply with approve/defer/blocked/approval_required decisions plus reasons, confidence, and local health blockers.'
        run_id = [string]$Artifact.run_id
        workspace = [string]$Artifact.workspace
        objective_id = [string]$Artifact.objective_id
        task_id = [string]$Artifact.task_id
        response_contract = [ordered]@{
            actor = 'MIM'
            message_type = 'handoff_response'
            intent = 'next_step_consensus'
            reply_by_utc = $replyByUtc
            required_fields = @(
                'summary',
                'finding_positions[].finding_id',
                'finding_positions[].decision',
                'finding_positions[].reason',
                'finding_positions[].confidence',
                'finding_positions[].local_blockers'
            )
        }
        findings = @($Artifact.findings | ForEach-Object {
                [pscustomobject]@{
                    finding_id = [string]$_.finding_id
                    description = [string]$_.description
                    owner_workspace = [string]$_.owner_workspace
                    action_type = [string]$_.action_type
                    risk = [string]$_.risk
                    approval_required = [bool]$_.approval_required
                }
            })
        requested_fields = @('finding_positions', 'summary')
    }

    try {
        $existingSession = (& $dialogScriptPath -Action read-session -DialogDir $DialogDirPath -SessionId $sessionId -Tail 20 -EmitJson | ConvertFrom-Json)
        $existingReply = @($existingSession.messages | Where-Object {
                $_ -and
                $_.PSObject.Properties['from'] -and
                $_.PSObject.Properties['to'] -and
                [string]$_.from -eq 'MIM' -and
                [string]$_.to -eq 'TOD' -and
                $_.PSObject.Properties['message_type'] -and
                [string]$_.message_type -eq 'handoff_response'
            } | Select-Object -Last 1)
        if (@($existingReply).Count -gt 0) {
            $normalizedExisting = Normalize-MimPositions -Payload $(if ($existingReply[0].PSObject.Properties['payload']) { $existingReply[0].payload } else { $null })
            $normalizedExisting | Add-Member -NotePropertyName session_id -NotePropertyValue $sessionId -Force
            return $normalizedExisting
        }

        $sessionAwaitsMim = $false
        if ($existingSession.PSObject.Properties['session_state'] -and $existingSession.session_state -and $existingSession.session_state.PSObject.Properties['open_reply']) {
            $openReply = $existingSession.session_state.open_reply
            if ($openReply -and $openReply.PSObject.Properties['from'] -and $openReply.PSObject.Properties['to']) {
                $sessionAwaitsMim = [string]$openReply.from -eq 'TOD' -and [string]$openReply.to -eq 'MIM'
            }
        }
    }
    catch {
        $sessionAwaitsMim = $false
    }

    if (-not $sessionAwaitsMim) {
        try {
            $null = (& $dialogScriptPath -Action send -DialogDir $DialogDirPath -SessionId $sessionId -Actor TOD -PeerActor MIM -MessageType handoff_request -Intent next_step_consensus -TaskId ([string]$Artifact.task_id) -Summary ("TOD requires a MIM decision for next-step consensus on run {0}. Reply with handoff_response finding_positions." -f [string]$Artifact.run_id) -PayloadJson ($requestPayload | ConvertTo-Json -Depth 14 -Compress) -RequiresReply -PublishRemote -EmitJson | ConvertFrom-Json)
        }
        catch {
            $sendFailure = [string]$_.Exception.Message
            $openReplyAlreadyExists = $sendFailure -like '*already has an open reply expectation*' -or $sendFailure -like '*awaiting a reply from MIM to TOD*'
            if (-not $openReplyAlreadyExists) {
                return [pscustomobject]@{
                    available = $false
                    source = 'dialog_send_failed'
                    summary = $sendFailure
                    finding_positions = @()
                    session_id = $sessionId
                }
            }
        }
    }

    $deadline = (Get-Date).ToUniversalTime().AddSeconds($WaitSeconds)
    while ((Get-Date).ToUniversalTime() -lt $deadline) {
        try {
            $session = (& $dialogScriptPath -Action read-session -DialogDir $DialogDirPath -SessionId $sessionId -Tail 12 -RefreshFromRemote -EmitJson | ConvertFrom-Json)
            $reply = @($session.messages | Where-Object {
                    $_ -and
                    $_.PSObject.Properties['from'] -and
                    $_.PSObject.Properties['to'] -and
                    [string]$_.from -eq 'MIM' -and
                    [string]$_.to -eq 'TOD' -and
                    $_.PSObject.Properties['message_type'] -and
                    [string]$_.message_type -eq 'handoff_response'
                } | Select-Object -Last 1)
            if (@($reply).Count -gt 0) {
                $normalized = Normalize-MimPositions -Payload $(if ($reply[0].PSObject.Properties['payload']) { $reply[0].payload } else { $null })
                $normalized | Add-Member -NotePropertyName session_id -NotePropertyValue $sessionId -Force
                return $normalized
            }
        }
        catch {
            return [pscustomobject]@{
                available = $false
                source = 'dialog_read_failed'
                summary = [string]$_.Exception.Message
                finding_positions = @()
                session_id = $sessionId
            }
        }

        Start-Sleep -Milliseconds $PollMilliseconds
    }

    $reminder = Send-MimDecisionReminder -Artifact $Artifact -DialogDirPath $DialogDirPath -SessionId $sessionId -ReplyByUtc ((Get-Date).ToUniversalTime().AddSeconds($WaitSeconds).ToString('o'))

    return [pscustomobject]@{
        available = $false
        source = if ($reminder.sent) { 'dialog_timeout_reminder_sent' } else { 'dialog_timeout' }
        summary = if ($reminder.sent) { 'MIM did not publish a next-step position before the wait deadline. TOD sent a reminder on the open session.' } else { 'MIM did not publish a next-step position before the wait deadline.' }
        finding_positions = @()
        session_id = $sessionId
        reminder = $reminder
    }
}

function Get-UnmetDependencies {
    param(
        [Parameter(Mandatory = $true)]$Finding,
        [Parameter(Mandatory = $true)][string[]]$AvailableFindingIds
    )

    $unmet = @()
    foreach ($dependency in @(Convert-ToStringArray -Value $Finding.blocking_dependencies)) {
        if ($AvailableFindingIds -notcontains [string]$dependency) {
            $unmet += [string]$dependency
        }
    }
    return @($unmet)
}

function Get-ExecutionPolicyClass {
    param(
        [Parameter(Mandatory = $true)]$Finding,
        [Parameter(Mandatory = $true)][string]$ConsensusStatus
    )

    if ([string]$ConsensusStatus -eq 'blocked') { return 'blocked' }
    if ([string]$ConsensusStatus -eq 'pending_remote') { return 'pending_remote' }
    if ([bool]$Finding.approval_required) { return 'approval_required' }
    if (([string]$Finding.action_type -in @('validate', 'observe', 'refresh')) -and ([string]$Finding.risk -eq 'low') -and ([double]$Finding.confidence -ge 0.75)) {
        return 'auto_execute'
    }
    return 'propose_only'
}

$resolvedFindingsPath = Get-LocalPath -PathValue $FindingsPath
if (-not (Test-Path -Path $resolvedFindingsPath)) {
    throw "FindingsPath not found: $resolvedFindingsPath"
}

$artifact = Get-Content -Path $resolvedFindingsPath -Raw | ConvertFrom-Json
$resolvedParityArtifactPath = Get-LocalPath -PathValue $ParityArtifactPath
$parityAuthority = Get-ParityAuthority -ParityPathValue $resolvedParityArtifactPath
$allFindingIds = @($artifact.findings | ForEach-Object { [string]$_.finding_id })
$todFindingPositions = @($artifact.findings | ForEach-Object { Resolve-TodFindingPosition -Finding $_ })

$mimPositions = $null
if (-not [string]::IsNullOrWhiteSpace($MimPositionJsonPath)) {
    $resolvedMimPath = Get-LocalPath -PathValue $MimPositionJsonPath
    if (Test-Path -Path $resolvedMimPath) {
        $mimPayload = Get-Content -Path $resolvedMimPath -Raw | ConvertFrom-Json
        $mimPositions = Normalize-MimPositions -Payload $mimPayload
        $mimPositions | Add-Member -NotePropertyName session_id -NotePropertyValue '' -Force
    }
}

if (($null -eq $mimPositions) -and -not [bool]$parityAuthority.active) {
    $resolvedDialogDir = Get-LocalPath -PathValue $DialogDir
    $mimPositions = Get-MimPositionsFromDialog -Artifact $artifact -DialogDirPath $resolvedDialogDir
}

if (($null -eq $mimPositions) -and [bool]$parityAuthority.active) {
    $mimPositions = [pscustomobject]@{
        available = $false
        source = [string]$parityAuthority.source
        summary = [string]$parityAuthority.summary
        finding_positions = @()
        session_id = ''
    }
}

$mimPositionIndex = @{}
foreach ($position in @($mimPositions.finding_positions)) {
    if (-not [string]::IsNullOrWhiteSpace([string]$position.finding_id)) {
        $mimPositionIndex[[string]$position.finding_id] = $position
    }
}

$resolvedEntries = @()
foreach ($finding in @($artifact.findings)) {
    $todPosition = @($todFindingPositions | Where-Object { [string]$_.finding_id -eq [string]$finding.finding_id } | Select-Object -First 1)[0]
    $mimPosition = if ($mimPositionIndex.ContainsKey([string]$finding.finding_id)) { $mimPositionIndex[[string]$finding.finding_id] } else { $null }
    $unmetDependencies = Get-UnmetDependencies -Finding $finding -AvailableFindingIds $allFindingIds

    $consensusStatus = 'approved'
    $consensusReason = 'TOD and MIM approve the finding for recommendation-only progression.'
    if (@($unmetDependencies).Count -gt 0) {
        $consensusStatus = 'blocked'
        $consensusReason = 'Finding references missing blocking dependencies.'
    }
    elseif ([string]$todPosition.decision -eq 'approval_required' -or ($mimPosition -and [string]$mimPosition.decision -eq 'approval_required')) {
        $consensusStatus = 'approval_required'
        $consensusReason = 'A participating authority marked this finding approval-required.'
    }
    elseif ([string]$todPosition.decision -eq 'blocked' -or ($mimPosition -and [string]$mimPosition.decision -eq 'blocked')) {
        $consensusStatus = 'blocked'
        $consensusReason = 'One of the participating authorities blocked this finding.'
    }
    elseif ([bool]$finding.needs_cross_system_consensus -and -not ($mimPosition) -and -not [bool]$parityAuthority.active) {
        $consensusStatus = 'pending_remote'
        $consensusReason = 'TOD is waiting for the MIM position before selecting this finding.'
    }
    elseif ([bool]$finding.needs_cross_system_consensus -and -not ($mimPosition) -and [bool]$parityAuthority.active) {
        $consensusStatus = 'approved'
        $consensusReason = 'Execution parity is green, so TOD can select this next-step finding locally without waiting for MIM.'
    }
    elseif ([string]$todPosition.decision -eq 'defer' -or ($mimPosition -and [string]$mimPosition.decision -eq 'defer')) {
        $consensusStatus = 'deferred'
        $consensusReason = 'The finding remains valid, but ownership or timing was deferred.'
    }

    $executionClass = Get-ExecutionPolicyClass -Finding $finding -ConsensusStatus $consensusStatus
    $score = (Get-ActionPriority -ActionType ([string]$finding.action_type)) + (Get-RiskScore -Risk ([string]$finding.risk)) + ([math]::Round([double]$finding.confidence * 10, 0))
    if (@($unmetDependencies).Count -gt 0) {
        $score -= 100
    }

    $resolvedEntries += [pscustomobject]@{
        finding = $finding
        tod_position = $todPosition
        mim_position = $mimPosition
        consensus_status = $consensusStatus
        consensus_reason = $consensusReason
        unmet_dependencies = @($unmetDependencies)
        execution_policy = [pscustomobject]@{
            class = $executionClass
            applied = $false
            applied_reason = 'phase1_recommendation_only'
        }
        selection_score = [int]$score
    }
}

$approved = @($resolvedEntries | Where-Object { [string]$_.consensus_status -eq 'approved' } | Sort-Object selection_score -Descending)
$pendingRemote = @($resolvedEntries | Where-Object { [string]$_.consensus_status -eq 'pending_remote' } | Sort-Object selection_score -Descending)
$approvalRequired = @($resolvedEntries | Where-Object { [string]$_.consensus_status -eq 'approval_required' } | Sort-Object selection_score -Descending)
$blocked = @($resolvedEntries | Where-Object { [string]$_.consensus_status -eq 'blocked' } | Sort-Object selection_score -Descending)

$selectedEntry = $null
$overallStatus = 'no_action'
if (@($approved).Count -gt 0) {
    $selectedEntry = $approved[0]
    $overallStatus = 'consensus_ready'
}
elseif (@($pendingRemote).Count -gt 0) {
    $selectedEntry = $pendingRemote[0]
    $overallStatus = 'pending_mim'
}
elseif (@($approvalRequired).Count -gt 0) {
    $selectedEntry = $approvalRequired[0]
    $overallStatus = 'approval_required'
}
elseif (@($blocked).Count -gt 0) {
    $selectedEntry = $blocked[0]
    $overallStatus = 'blocked'
}

$resolvedOutputPath = Get-LocalPath -PathValue $OutputPath
$consensus = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    source = 'tod-next-step-consensus-v1'
    contract_version = 'tod-next-step-consensus-v1'
    source_run = [string]$artifact.run_id
    objective_id = [string]$artifact.objective_id
    task_id = [string]$artifact.task_id
    workspace_origin = [string]$artifact.workspace
    status = $overallStatus
    tod_position = [pscustomobject]@{
        decision = 'complete'
        summary = 'TOD published positions for all findings.'
        finding_positions = @($todFindingPositions)
    }
    mim_position = [pscustomobject]@{
        decision = if ([bool]$mimPositions.available) { 'complete' } elseif ([bool]$parityAuthority.active) { 'not_required' } else { 'pending' }
        summary = [string]$mimPositions.summary
        source = [string]$mimPositions.source
        session_id = if ($mimPositions.PSObject.Properties['session_id']) { [string]$mimPositions.session_id } else { '' }
        finding_positions = @($mimPositions.finding_positions)
        reminder = if ($mimPositions.PSObject.Properties['reminder']) { $mimPositions.reminder } else { $null }
    }
    parity_authority = $parityAuthority
    consensus = [pscustomobject]@{
        selected_finding_id = if ($selectedEntry) { [string]$selectedEntry.finding.finding_id } else { '' }
        action = if ($selectedEntry) { [string]$selectedEntry.finding.description } else { '' }
        owner = if ($selectedEntry) { [string]$selectedEntry.finding.owner_workspace } else { '' }
        cross_system_required = if ($selectedEntry) { [bool]$selectedEntry.finding.needs_cross_system_consensus } else { $false }
        approval_required = if ($selectedEntry) { [bool]$selectedEntry.finding.approval_required } else { $false }
        execution_policy = if ($selectedEntry) { $selectedEntry.execution_policy } else { [pscustomobject]@{ class = 'none'; applied = $false; applied_reason = 'no_selected_finding' } }
        reason = if ($selectedEntry) { [string]$selectedEntry.consensus_reason } else { 'No eligible next-step finding is available.' }
    }
    findings = @($resolvedEntries)
}

Write-Utf8NoBomJson -PathValue $resolvedOutputPath -Payload $consensus -Depth 24

[pscustomobject]@{
    ok = $true
    output_path = $resolvedOutputPath
    status = $overallStatus
    artifact = $consensus
} | ConvertTo-Json -Depth 24