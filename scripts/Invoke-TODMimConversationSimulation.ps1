param(
    [ValidateSet('all', 'diagnostic_roundtrip', 'next_step_consensus_roundtrip', 'supersede_reissue_roundtrip')]
    [string]$Scenario = 'all',
    [string]$OutputRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$dialogScript = Join-Path $PSScriptRoot 'Invoke-TODMimDialog.ps1'
$resolveConsensusScript = Join-Path $PSScriptRoot 'Resolve-TODNextStepConsensus.ps1'

function Get-ResolvedPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return $PathValue
    }

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

function Get-DialogSessionLogPath {
    param(
        [Parameter(Mandatory = $true)][string]$DialogDir,
        [Parameter(Mandatory = $true)][string]$SessionId
    )

    $safeSessionId = ([string]$SessionId).Trim()
    if ([string]::IsNullOrWhiteSpace($safeSessionId)) {
        throw 'SessionId must not be empty.'
    }

    $safeSessionId = $safeSessionId -replace '[^a-zA-Z0-9._-]', '_'
    return (Join-Path $DialogDir ("MIM_TOD_DIALOG.session-{0}.jsonl" -f $safeSessionId))
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

function New-SimulationRoot {
    $runId = 'tod-mim-sim-' + (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ') + '-' + ([guid]::NewGuid().ToString('N').Substring(0, 8))
    $rootBase = if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
        Join-Path $repoRoot 'tod/out/tests/tod-mim-conversation-simulations'
    }
    else {
        Get-ResolvedPath -PathValue $OutputRoot
    }

    Ensure-Directory -PathValue $rootBase
    $root = Join-Path $rootBase $runId
    Ensure-Directory -PathValue $root
    Ensure-Directory -PathValue (Join-Path $root 'dialog')
    return $root
}

function Invoke-DialogJson {
    param(
        [Parameter(Mandatory = $true)][string]$DialogDir,
        [Parameter(Mandatory = $true)][hashtable]$Arguments
    )

    $splat = @{}
    foreach ($key in $Arguments.Keys) {
        $value = $Arguments[$key]
        if ($value -eq $false -or $null -eq $value) {
            continue
        }
        $splat[$key] = $value
    }
    $splat['DialogDir'] = $DialogDir
    $splat['EmitJson'] = $true

    $json = & $dialogScript @splat
    return ($json | ConvertFrom-Json)
}

function New-FindingsArtifact {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][string]$ObjectiveId,
        [Parameter(Mandatory = $true)][string]$TaskId
    )

    $payload = [pscustomobject]@{
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        source = 'simulation'
        contract_version = 'tod-codex-next-steps-v1'
        run_id = $RunId
        workspace = 'TOD'
        objective_id = $ObjectiveId
        task_id = $TaskId
        summary = 'Synthetic TOD/MIM next-step simulation.'
        findings = @(
            [pscustomobject]@{
                finding_id = "$TaskId-finding-001"
                type = 'validation_candidate'
                description = 'Run canonical-only validation pass'
                owner_workspace = 'TOD'
                action_type = 'validate'
                needs_remote_input = $true
                needs_cross_system_consensus = $true
                approval_required = $false
                confidence = 0.86
                risk = 'low'
                blocking_dependencies = @()
                recommended_executor = 'tod.local'
                source = 'simulation'
            },
            [pscustomobject]@{
                finding_id = "$TaskId-finding-002"
                type = 'cleanup_candidate'
                description = 'Retire remaining live aliases after validation'
                owner_workspace = 'TOD'
                action_type = 'cleanup'
                needs_remote_input = $true
                needs_cross_system_consensus = $true
                approval_required = $false
                confidence = 0.80
                risk = 'medium'
                blocking_dependencies = @("$TaskId-finding-001")
                recommended_executor = 'tod.local'
                source = 'simulation'
            }
        )
    }

    Write-Utf8NoBomJson -PathValue $PathValue -Payload $payload -Depth 20
}

function Invoke-DiagnosticRoundtripScenario {
    param([Parameter(Mandatory = $true)][string]$Root)

    $dialogDir = Join-Path $Root 'dialog'
    $sessionId = 'simulation-diagnostic-roundtrip'

    $null = Invoke-DialogJson -DialogDir $dialogDir -Arguments @{
        Action = 'send'
        SessionId = $sessionId
        Actor = 'TOD'
        PeerActor = 'MIM'
        MessageType = 'diagnostic_query'
        Intent = 'simulation_probe'
        TaskId = 'simulation-diagnostic'
        Summary = 'TOD diagnostic roundtrip probe.'
        PayloadJson = '{"probe":"diagnostic_roundtrip"}'
        RequiresReply = $true
    }

    $mimInbox = Invoke-DialogJson -DialogDir $dialogDir -Arguments @{
        Action = 'read-inbox'
        Actor = 'MIM'
    }

    $null = Invoke-DialogJson -DialogDir $dialogDir -Arguments @{
        Action = 'send'
        SessionId = $sessionId
        Actor = 'MIM'
        PeerActor = 'TOD'
        MessageType = 'diagnostic_reply'
        Intent = 'simulation_probe'
        TaskId = 'simulation-diagnostic'
        Summary = 'MIM diagnostic reply for simulation.'
        PayloadJson = '{"result":"diagnostic_roundtrip_ok"}'
    }

    $null = Invoke-DialogJson -DialogDir $dialogDir -Arguments @{
        Action = 'close-session'
        SessionId = $sessionId
        Actor = 'TOD'
        PeerActor = 'MIM'
        TaskId = 'simulation-diagnostic'
        Intent = 'simulation_complete'
        Summary = 'Diagnostic roundtrip simulation complete.'
        PayloadJson = '{"resolution":"diagnostic_roundtrip_complete"}'
    }

    $status = Invoke-DialogJson -DialogDir $dialogDir -Arguments @{
        Action = 'get-session-status'
        SessionId = $sessionId
    }

    return [pscustomobject]@{
        scenario = 'diagnostic_roundtrip'
        ok = (@($mimInbox.open_sessions).Count -eq 1) -and ([string]$status.session_state.status -eq 'closed')
        session_id = $sessionId
        final_status = [string]$status.session_state.status
        inbox_count = @($mimInbox.open_sessions).Count
    }
}

function Invoke-NextStepConsensusRoundtripScenario {
    param([Parameter(Mandatory = $true)][string]$Root)

    $dialogDir = Join-Path $Root 'dialog'
    $findingsPath = Join-Path $Root 'tod_codex_next_steps.latest.json'
    $consensusPath = Join-Path $Root 'NEXT_STEP_CONSENSUS.latest.json'
    $parityArtifactPath = Join-Path $Root 'tod-mim-execution-parity.latest.json'
    $runId = 'simulation-run-1'
    $taskId = 'simulation-next-step'
    $objectiveId = 'SIM-01'

    New-FindingsArtifact -PathValue $findingsPath -RunId $runId -ObjectiveId $objectiveId -TaskId $taskId
    $firstPass = (& $resolveConsensusScript -FindingsPath $findingsPath -DialogDir $dialogDir -OutputPath $consensusPath -ParityArtifactPath $parityArtifactPath -WaitSeconds 0 -PollMilliseconds 10) | ConvertFrom-Json

    $sessionId = 'next-step-{0}-{1}' -f $taskId.ToLowerInvariant(), $runId.ToLowerInvariant().Replace(':', '-').Replace(' ', '-')
    $sessionPath = Get-DialogSessionLogPath -DialogDir $dialogDir -SessionId $sessionId
    $messages = @(Get-Content -Path $sessionPath | ForEach-Object { $_ | ConvertFrom-Json })
    $activeTurn = [int](@($messages | Where-Object { [string]$_.message_type -eq 'handoff_request' } | Select-Object -Last 1)[0].turn_id)

    $replyPayload = [pscustomobject]@{
        reply_to_turn = $activeTurn
        summary = 'MIM simulation approves validation and defers cleanup until validation completes.'
        finding_positions = @(
            [pscustomobject]@{ finding_id = "$taskId-finding-001"; decision = 'approve'; reason = 'Low-risk validation.'; confidence = 0.90; local_blockers = @() },
            [pscustomobject]@{ finding_id = "$taskId-finding-002"; decision = 'defer'; reason = 'Cleanup should wait for validation completion.'; confidence = 0.82; local_blockers = @() }
        )
    }

    $null = Invoke-DialogJson -DialogDir $dialogDir -Arguments @{
        Action = 'send'
        SessionId = $sessionId
        Actor = 'MIM'
        PeerActor = 'TOD'
        MessageType = 'handoff_response'
        Intent = 'next_step_consensus'
        TaskId = $taskId
        Summary = 'MIM simulation returned finding positions.'
        PayloadJson = ($replyPayload | ConvertTo-Json -Depth 10 -Compress)
    }

    $secondPass = (& $resolveConsensusScript -FindingsPath $findingsPath -DialogDir $dialogDir -OutputPath $consensusPath -ParityArtifactPath $parityArtifactPath -WaitSeconds 0 -PollMilliseconds 10) | ConvertFrom-Json
    $artifact = Get-Content -Path $consensusPath -Raw | ConvertFrom-Json

    return [pscustomobject]@{
        scenario = 'next_step_consensus_roundtrip'
        ok = ([string]$firstPass.status -eq 'pending_mim') -and ([string]$secondPass.status -eq 'consensus_ready') -and ([string]$artifact.consensus.selected_finding_id -eq "$taskId-finding-001")
        session_id = $sessionId
        first_status = [string]$firstPass.status
        second_status = [string]$secondPass.status
        selected_finding_id = [string]$artifact.consensus.selected_finding_id
        consensus_path = $consensusPath
    }
}

function Invoke-SupersedeReissueRoundtripScenario {
    param([Parameter(Mandatory = $true)][string]$Root)

    $dialogDir = Join-Path $Root 'dialog'
    $sessionId = 'simulation-supersede-reissue'

    $null = Invoke-DialogJson -DialogDir $dialogDir -Arguments @{
        Action = 'send'
        SessionId = $sessionId
        Actor = 'TOD'
        PeerActor = 'MIM'
        MessageType = 'handoff_request'
        Intent = 'simulation_supersede'
        TaskId = 'simulation-supersede'
        Summary = 'Initial synthetic handoff request.'
        PayloadJson = '{"phase":"initial"}'
        RequiresReply = $true
    }

    $null = Invoke-DialogJson -DialogDir $dialogDir -Arguments @{
        Action = 'close-session'
        SessionId = $sessionId
        Actor = 'TOD'
        PeerActor = 'MIM'
        TaskId = 'simulation-supersede'
        Intent = 'simulation_superseded'
        Summary = 'Superseding initial synthetic request.'
        PayloadJson = '{"resolution":"superseded"}'
    }

    $null = Invoke-DialogJson -DialogDir $dialogDir -Arguments @{
        Action = 'send'
        SessionId = $sessionId
        Actor = 'TOD'
        PeerActor = 'MIM'
        MessageType = 'handoff_request'
        Intent = 'simulation_supersede'
        TaskId = 'simulation-supersede'
        Summary = 'Reissued synthetic handoff request.'
        PayloadJson = '{"phase":"reissued"}'
        RequiresReply = $true
    }

    $null = Invoke-DialogJson -DialogDir $dialogDir -Arguments @{
        Action = 'send'
        SessionId = $sessionId
        Actor = 'MIM'
        PeerActor = 'TOD'
        MessageType = 'handoff_response'
        Intent = 'simulation_supersede'
        TaskId = 'simulation-supersede'
        Summary = 'MIM answered the reissued request.'
        PayloadJson = '{"summary":"reissued_request_answered"}'
    }

    $status = Invoke-DialogJson -DialogDir $dialogDir -Arguments @{
        Action = 'get-session-status'
        SessionId = $sessionId
    }
    $messages = @(Get-Content -Path (Get-DialogSessionLogPath -DialogDir $dialogDir -SessionId $sessionId) | ForEach-Object { $_ | ConvertFrom-Json })
    $reissuedTurn = @($messages | Where-Object { [string]$_.summary -eq 'Reissued synthetic handoff request.' } | Select-Object -First 1)[0]

    return [pscustomobject]@{
        scenario = 'supersede_reissue_roundtrip'
        ok = ([string]$status.session_state.status -eq 'resolved') -and ($null -ne $reissuedTurn)
        session_id = $sessionId
        final_status = [string]$status.session_state.status
        reissued_turn = if ($reissuedTurn) { [int]$reissuedTurn.turn_id } else { 0 }
    }
}

$root = New-SimulationRoot
$results = @()

if ($Scenario -in @('all', 'diagnostic_roundtrip')) {
    $results += Invoke-DiagnosticRoundtripScenario -Root $root
}
if ($Scenario -in @('all', 'next_step_consensus_roundtrip')) {
    $results += Invoke-NextStepConsensusRoundtripScenario -Root $root
}
if ($Scenario -in @('all', 'supersede_reissue_roundtrip')) {
    $results += Invoke-SupersedeReissueRoundtripScenario -Root $root
}

$summary = [pscustomobject]@{
    ok = (-not (@($results | Where-Object { -not [bool]$_.ok }).Count))
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    root = $root
    scenario = $Scenario
    scenario_results = @($results)
}

$summaryPath = Join-Path $root 'simulation-summary.json'
$markdownPath = Join-Path $root 'simulation-summary.md'
Write-Utf8NoBomJson -PathValue $summaryPath -Payload $summary -Depth 20

$markdown = @(
    '# TOD-MIM Conversation Simulation Summary',
    '',
    ('Generated: {0}' -f $summary.generated_at),
    ('Root: {0}' -f $root),
    ('Overall: {0}' -f $(if ($summary.ok) { 'pass' } else { 'fail' })),
    '',
    '## Scenario Results'
)
foreach ($entry in @($results)) {
    $markdown += ('- {0}: {1}' -f [string]$entry.scenario, $(if ([bool]$entry.ok) { 'pass' } else { 'fail' }))
}
[System.IO.File]::WriteAllText($markdownPath, ($markdown -join "`n"), (New-Object System.Text.UTF8Encoding($false)))

$summary | ConvertTo-Json -Depth 20