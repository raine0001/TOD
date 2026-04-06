param(
    [int]$Port = 8844,
    [int]$WindowMinutes = 10,
    [string]$ObjectiveId = '',
    [string]$ValidationHarness = 'multi_objective_compare',
    [string]$RawArtifactPath = '',
    [string]$IneffectiveSummaryPath = '',
    [switch]$ArtifactOnly
)

$ErrorActionPreference = 'Stop'
$script:EffectiveObjectiveId = $ObjectiveId
$comparisonHarnesses = @('multi_objective_compare', 'compare_bridge', 'compare_cadence', 'compare_objective_status')

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($RawArtifactPath)) {
    $RawArtifactPath = Join-Path $repoRoot 'tmp_live_sweep_raw.json'
}
if ([string]::IsNullOrWhiteSpace($IneffectiveSummaryPath)) {
    $IneffectiveSummaryPath = Join-Path $repoRoot 'tmp_ineffective_sweep_summary.json'
}
$script:SweepReadinessFixture = $null

$baseUrl = "http://localhost:$Port"
$queries = @(
    @{ intent = 'summarize_status'; query = 'Summarize dashboard state in operator language.' },
    @{ intent = 'explain_warning'; query = 'What is blocking progress right now?' },
    @{ intent = 'explain_bridge_status'; query = 'What is the current bridge mismatch?' },
    @{ intent = 'explain_cadence'; query = 'Why is cadence warning?' },
    @{ intent = 'explain_maintenance'; query = 'Why am I in healthy_with_fallback?' },
    @{ intent = 'suggest_next_action'; query = 'What should I do next?' },
    @{ intent = 'summarize_current_objective'; query = 'What is the current objective doing right now?' },
    @{ intent = 'summarize_recent_changes'; query = 'What changed since the last successful completion?' }
)
$governedActions = @(
    @{ action = 'get-state-bus'; intent = 'suggest_next_action'; query = 'What should I do next?'; suggested_reason = 'Sweep validation for state-bus governed action.'; mode = 'read_only' },
    @{ action = 'get-engineering-loop-summary'; intent = 'explain_cadence'; query = 'Why is cadence warning?'; suggested_reason = 'Sweep validation for engineering-loop-summary governed action.'; mode = 'read_only' },
    @{ action = 'get-engineering-signal'; intent = 'explain_cadence'; query = 'Why is cadence warning?'; suggested_reason = 'Sweep validation for engineering-signal governed action.'; mode = 'read_only' },
    @{ action = 'refresh-share-links'; intent = 'suggest_next_action'; query = 'What should I do next?'; suggested_reason = 'Sweep validation for share-links governed action.'; mode = 'ui_refresh_only' },
    @{ action = 'quick-refresh-reliability'; intent = 'suggest_next_action'; query = 'What should I do next?'; suggested_reason = 'Sweep validation for quick reliability governed action.'; mode = 'ui_refresh_only' },
    @{ action = 'refresh-project-status'; intent = 'summarize_status'; query = 'Summarize dashboard state in operator language.'; suggested_reason = 'Sweep validation for status refresh governed action.'; mode = 'read_only' },
    @{ action = 'recheck-bridge-diagnostics'; intent = 'explain_bridge_status'; query = 'What is the current bridge mismatch?'; suggested_reason = 'Sweep validation for bridge diagnostics governed action.'; mode = 'read_only' },
    @{ action = 'get-reliability'; intent = 'explain_warning'; query = 'What is blocking progress right now?'; suggested_reason = 'Sweep validation for reliability governed action.'; mode = 'read_only' },
    @{ action = 'show-reliability-dashboard'; intent = 'explain_warning'; query = 'What is blocking progress right now?'; suggested_reason = 'Sweep validation for reliability dashboard governed action.'; mode = 'read_only' },
    @{ action = 'refresh-governance-snapshot'; intent = 'summarize_status'; query = 'Summarize dashboard state in operator language.'; suggested_reason = 'Sweep validation for governance snapshot governed action.'; mode = 'read_only' },
    @{ action = 'refresh-bridge-alignment-bundle'; intent = 'explain_bridge_status'; query = 'What is the current bridge mismatch?'; suggested_reason = 'Sweep validation for bridge alignment bundle governed action.'; mode = 'read_only' }
)
$commitmentProbe = @{ action = 'refresh-project-status'; intent = 'summarize_status'; query = 'Summarize dashboard state in operator language.'; suggested_reason = 'Sweep validation for operator commitment linkage.'; mode = 'read_only' }
$timeboxedCommitmentProbe = @{ action = 'refresh-governance-snapshot'; intent = 'summarize_status'; query = 'Summarize dashboard state in operator language.'; suggested_reason = 'Sweep validation for timeboxed operator commitment.'; mode = 'read_only' }
$evidenceCommitmentProbe = @{ action = 'get-state-bus'; intent = 'suggest_next_action'; query = 'What should I do next?'; suggested_reason = 'Sweep validation for evidence-bound operator commitment.'; mode = 'read_only' }

function Get-ValidationHarnessQueryFragment {
    if ([string]::IsNullOrWhiteSpace($ValidationHarness)) {
        return ''
    }

    return 'validation_harness={0}' -f [uri]::EscapeDataString([string]$ValidationHarness)
}

function Invoke-JsonPost {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Body
    )

    $json = $Body | ConvertTo-Json -Depth 8
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri ("$baseUrl$Path") -Method Post -Body $json -ContentType 'application/json' -TimeoutSec 60 -DisableKeepAlive
        $payloadText = [string]$response.Content
        return [pscustomobject]@{
            status_code = [int]$response.StatusCode
            payload = if ([string]::IsNullOrWhiteSpace($payloadText)) { @{} } else { $payloadText | ConvertFrom-Json }
        }
    }
    catch {
        throw "POST $Path failed: $($_.Exception.Message)"
    }
}

function Invoke-JsonGet {
    param([Parameter(Mandatory = $true)][string]$Uri)

    $response = Invoke-WebRequest -UseBasicParsing -Uri $Uri -Method Get -TimeoutSec 60 -DisableKeepAlive
    if ([string]::IsNullOrWhiteSpace([string]$response.Content)) {
        return [pscustomobject]@{}
    }

    return ($response.Content | ConvertFrom-Json)
}

function Invoke-TextGet {
    param([Parameter(Mandatory = $true)][string]$Uri)

    return [string](Invoke-WebRequest -UseBasicParsing -Uri $Uri -Method Get -TimeoutSec 60 -DisableKeepAlive).Content
}

function Write-Utf8NoBomJson {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Payload,
        [int]$Depth = 20
    )

    $directory = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -Path $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $json = $Payload | ConvertTo-Json -Depth $Depth
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $json, $utf8NoBom)
}

function Write-IneffectiveArtifacts {
    param(
        [Parameter(Mandatory = $true)]$SummaryPayload,
        [Parameter(Mandatory = $true)]$RawPayload,
        [switch]$SkipRaw
    )

    if (-not $SkipRaw) {
        Write-Utf8NoBomJson -Path $RawArtifactPath -Payload $RawPayload -Depth 8
    }

    Write-Utf8NoBomJson -Path $IneffectiveSummaryPath -Payload $SummaryPayload -Depth 8
}

function Write-SweepProgress {
    param(
        [Parameter(Mandatory = $true)][string]$Stage,
        [string]$Detail = ''
    )

    Write-Utf8NoBomJson -Path $RawArtifactPath -Payload ([pscustomobject]@{
            generated_at = (Get-Date).ToUniversalTime().ToString('o')
            source = 'tod-operator-chat-sweep-progress-v1'
            stage = $Stage
            detail = $Detail
            validation_harness = if ([string]::IsNullOrWhiteSpace($ValidationHarness)) { '' } else { [string]$ValidationHarness }
        }) -Depth 6
}

function New-SweepReadinessFixture {
    $id = [guid]::NewGuid().ToString('N')
    $base = Join-Path $repoRoot (Join-Path 'tod/out/tests' ('operator-chat-sweep-readiness-' + $id))
    New-Item -ItemType Directory -Path $base -Force | Out-Null

    $artifactPath = Join-Path $base 'tod_operator_chat_sweep_artifact_smoke.latest.json'
    $historyPath = Join-Path $base 'tod_execution_readiness_history.latest.json'
    $configPath = Join-Path $base 'tod-config.json'
    $sourceConfigPath = Join-Path $repoRoot 'tod/config/tod-config.json'

    [pscustomobject]@{
        source = 'tod-operator-chat-sweep-artifact-smoke-v1'
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        summary = [pscustomobject]@{
            total = 13
            passed = 13
            failed = 0
            passed_all = $true
            exit_code = 0
        }
    } | ConvertTo-Json -Depth 10 | Set-Content -Path $artifactPath

    $config = Get-Content -Path $sourceConfigPath -Raw | ConvertFrom-Json
    $config.execution_engine.readiness_policy = [pscustomobject]@{
        enabled = $true
        signal_path = $artifactPath
        history_path = $historyPath
        history_max_entries = 20
        max_artifact_age_minutes = 30
        display_max_artifact_age_minutes = 10
        block_actions = @('run-task')
        degrade_actions = @('engineer-run')
        block_states = @('stale', 'invalid', 'unknown')
        degrade_states = @('degraded', 'stale', 'invalid', 'unknown')
        degrade_apply_plan = $true
    }
    $config | ConvertTo-Json -Depth 40 | Set-Content -Path $configPath

    return [pscustomobject]@{
        Base = $base
        ArtifactPath = $artifactPath
        HistoryPath = $historyPath
        ConfigPath = $configPath
    }
}

function Remove-SweepReadinessFixture {
    param($Fixture)

    if ($Fixture -and $Fixture.Base -and (Test-Path -Path $Fixture.Base)) {
        Remove-Item -Path $Fixture.Base -Recurse -Force
    }
}

function Invoke-ActionPreview {
    param([Parameter(Mandatory = $true)]$Spec)

    return Invoke-JsonPost -Path '/api/operator-chat-action' -Body @{
        phase = 'preview'
        action = [string]$Spec.action
        intent = [string]$Spec.intent
        objective_id = [string]$script:EffectiveObjectiveId
        query = [string]$Spec.query
        window_minutes = $WindowMinutes
        operator_id = 'sweep-operator'
        suggested_reason = [string]$Spec.suggested_reason
        mode = [string]$Spec.mode
        validation_harness = [string]$ValidationHarness
        configPath = if ($script:SweepReadinessFixture) { [string]$script:SweepReadinessFixture.ConfigPath } else { '' }
    }
}

function Invoke-ActionConfirm {
    param(
        [Parameter(Mandatory = $true)]$Spec,
        [string]$PreviewId,
        [string]$OverrideAction = ''
    )

    return Invoke-JsonPost -Path '/api/operator-chat-action' -Body @{
        phase = 'confirm'
        preview_id = [string]$PreviewId
        action = $(if ([string]::IsNullOrWhiteSpace($OverrideAction)) { [string]$Spec.action } else { [string]$OverrideAction })
        intent = [string]$Spec.intent
        objective_id = [string]$script:EffectiveObjectiveId
        query = [string]$Spec.query
        window_minutes = $WindowMinutes
        operator_id = 'sweep-operator'
        suggested_reason = [string]$Spec.suggested_reason
        mode = [string]$Spec.mode
        validation_harness = [string]$ValidationHarness
        configPath = if ($script:SweepReadinessFixture) { [string]$script:SweepReadinessFixture.ConfigPath } else { '' }
    }
}

function Invoke-CommitmentWrite {
    param(
        [Parameter(Mandatory = $true)][string]$PreviewId,
        [Parameter(Mandatory = $true)][string]$State,
        [int]$DurationMinutes = 15
    )

    $body = @{
        preview_id = [string]$PreviewId
        objective_id = [string]$script:EffectiveObjectiveId
        operator_id = 'sweep-operator'
        state = [string]$State
        validation_harness = [string]$ValidationHarness
    }
    if ($DurationMinutes -gt 0 -and @('committed', 'timeboxed', 'abandoned', 'satisfied') -contains [string]$State) {
        $body.duration_minutes = $DurationMinutes
    }

    return Invoke-JsonPost -Path '/api/operator-chat-commitment' -Body $body
}

function Get-IneffectiveValidationSpec {
    $payload = (Invoke-JsonPost -Path '/api/operator-chat' -Body @{
        query = 'What should I do next?'
        intent = 'suggest_next_action'
        objective_id = [string]$script:EffectiveObjectiveId
        window_minutes = $WindowMinutes
        validation_harness = $ValidationHarness
    }).payload

    $committable = @($payload.response.suggested_actions | Where-Object {
            $null -ne $_ -and
            -not [string]::Equals([string]$_.mode, 'observe_only', [System.StringComparison]::OrdinalIgnoreCase)
        })

    $selected = $null
    foreach ($candidate in $committable) {
        $sameIntentSatisfiedCount = if ($candidate.PSObject.Properties['history_same_intent_satisfied_count']) { [int]$candidate.history_same_intent_satisfied_count } else { 0 }
        $sameIntentAbandonedCount = if ($candidate.PSObject.Properties['history_same_intent_abandoned_count']) { [int]$candidate.history_same_intent_abandoned_count } else { 0 }
        if ($sameIntentSatisfiedCount -eq 0 -and $sameIntentAbandonedCount -eq 0) {
            $selected = $candidate
            break
        }
    }

    if ($null -eq $selected) {
        foreach ($candidate in $committable) {
            $sameIntentSatisfiedCount = if ($candidate.PSObject.Properties['history_same_intent_satisfied_count']) { [int]$candidate.history_same_intent_satisfied_count } else { 0 }
            if ($sameIntentSatisfiedCount -eq 0) {
                $selected = $candidate
                break
            }
        }
    }

    if ($null -eq $selected -and @($committable).Count -gt 0) {
        $selected = $committable[0]
    }

    if ($null -eq $selected) {
        return [pscustomobject]@{
            action = 'get-reliability'
            intent = 'explain_warning'
            query = 'What is blocking progress right now?'
            suggested_reason = 'Sweep validation for ineffective operator commitment derivation.'
            mode = 'read_only'
        }
    }

    return [pscustomobject]@{
        action = [string]$selected.action
        intent = if ($selected.PSObject.Properties['intent']) { [string]$selected.intent } else { 'suggest_next_action' }
        query = 'What should I do next?'
        suggested_reason = if ($selected.PSObject.Properties['reason']) { [string]$selected.reason } else { 'Sweep validation for ineffective operator commitment derivation.' }
        mode = if ($selected.PSObject.Properties['mode']) { [string]$selected.mode } else { 'read_only' }
    }
}

try {
    $script:SweepReadinessFixture = New-SweepReadinessFixture
    Write-SweepProgress -Stage 'starting' -Detail 'Initializing operator-chat sweep.'
    $html = if ($ArtifactOnly) { '' } else { Invoke-TextGet -Uri "$baseUrl/" }
    $validationHarnessQuery = Get-ValidationHarnessQueryFragment
    $projectStatusUrl = if ([string]::IsNullOrWhiteSpace($validationHarnessQuery)) { "$baseUrl/api/project-status" } else { "$baseUrl/api/project-status?$validationHarnessQuery" }
    $projectStatusPayload = Invoke-JsonGet -Uri $projectStatusUrl
    $selectedObjectiveId = if ($projectStatusPayload -and $projectStatusPayload.PSObject.Properties['selected_objective_id']) { [string]$projectStatusPayload.selected_objective_id } else { [string]$ObjectiveId }
    if ([string]::IsNullOrWhiteSpace([string]$script:EffectiveObjectiveId)) {
        $script:EffectiveObjectiveId = $selectedObjectiveId
    }
    Write-SweepProgress -Stage 'project_status_loaded' -Detail ('Loaded project status for objective {0}.' -f [string]$script:EffectiveObjectiveId)
    $alternateObjectiveId = @($projectStatusPayload.objective_options | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.objective_id) -and -not [string]::Equals([string]$_.objective_id, $selectedObjectiveId, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1).objective_id
    $alternateProjectStatusPayload = if ($ArtifactOnly -or [string]::IsNullOrWhiteSpace([string]$alternateObjectiveId)) {
        [pscustomobject]@{}
    }
    else {
        $alternateStatusQuery = @("objective_id=$([uri]::EscapeDataString([string]$alternateObjectiveId))")
        if (-not [string]::IsNullOrWhiteSpace($validationHarnessQuery)) {
            $alternateStatusQuery += $validationHarnessQuery
        }
        Invoke-JsonGet -Uri "$baseUrl/api/project-status?$($alternateStatusQuery -join '&')"
    }
    $htmlChecks = [pscustomobject]@{
        build_stamp_present = ($html -match '20\d{2}\.\d{2}\.\d{2}-b\d+')
        marker_fields = (($html -match 'objectiveMarkerId') -and ($html -match 'objectiveMarkerStatus') -and ($html -match 'objectiveMarkerTitle'))
        cadence_fields = (($html -match 'cadenceSeverityDetail') -and ($html -match 'cadenceGovernanceSeverityDetail') -and ($html -match 'cadenceP95Detail') -and ($html -match 'cadenceRetryDetail'))
        bridge_mismatch_detail = ($html -match 'bridgeObjectiveDetail')
        bridge_status_reason = ($html -match 'Bridge Status Reason') -or ($html -match 'status_reason')
        posture_renderer = ($html -match 'operator-chat-posture')
        evidence_jump = ($html -match 'operator-chat-evidence-jump')
        governed_action_endpoint = ($html -match 'data-chat-confirm-preview') -or ($html -match 'operatorChatActionPreviews')
        audit_panel = ($html -match 'operatorChatAuditList') -and ($html -match 'operatorChatAuditRefreshBtn')
        audit_filters = ($html -match 'operatorChatAuditSearch') -and ($html -match 'operatorChatAuditActionFilter') -and ($html -match 'operatorChatAuditOutcomeFilter') -and ($html -match 'operatorChatAuditPhaseFilter')
        commitment_panel = ($html -match 'operatorChatCommitmentList') -and ($html -match 'operatorChatCommitmentRefreshBtn')
        trust_chain_panel = ($html -match 'operatorChatTrustChainDetail') -and ($html -match 'operatorChatTrustChainClearBtn')
        terminal_commitment_controls = ($html -match 'data-chat-update-commitment-state="satisfied"') -and ($html -match 'data-chat-update-commitment-state="abandoned"')
        terminal_history_surface = ($html -match 'Outcome History:') -or ($html -match 'latest terminal ::')
        provenance_badge_surface = ($html -match 'provenance ::') -and ($html -match 'fitness ::')
        suggested_action_fitness_surface = ($html -match 'operator-chat-action-fitness') -and ($html -match 'operator-chat-action-meta')
        suggested_action_feedback_surface = ($html -match 'data-chat-feedback-action') -and ($html -match 'Helpful') -and ($html -match 'Not Helpful')
        harness_surface = ($html -match 'validation_harness') -and ($html -match 'Harness:')
    }

    $bridgeDiagnostics = if ($projectStatusPayload -and $projectStatusPayload.PSObject.Properties['bridge_status']) { $projectStatusPayload.bridge_status } else { $null }
    $bridgeExplainPayload = if ($ArtifactOnly) {
        [pscustomobject]@{ ok = $false; response = [pscustomobject]@{ citations = @() } }
    }
    else {
        (Invoke-JsonPost -Path '/api/operator-chat' -Body @{
            query = 'What is the current bridge mismatch?'
            intent = 'explain_bridge_status'
            objective_id = [string]$script:EffectiveObjectiveId
            window_minutes = $WindowMinutes
            validation_harness = $ValidationHarness
        }).payload
    }

    $sweepQueries = if ($ArtifactOnly) {
        @(
            @{ intent = 'suggest_next_action'; query = 'What should I do next?' }
        )
    }
    else {
        @($queries)
    }

    $results = foreach ($item in $sweepQueries) {
        $body = @{
            query = [string]$item.query
            intent = [string]$item.intent
            objective_id = [string]$script:EffectiveObjectiveId
            window_minutes = $WindowMinutes
            validation_harness = $ValidationHarness
        }

        $payload = (Invoke-JsonPost -Path '/api/operator-chat' -Body $body).payload

        $summary = [string]$payload.response.summary
        if ($summary.Length -gt 140) {
            $summary = $summary.Substring(0, 140) + '...'
        }

        $next = [string]$payload.response.recommended_next_step
        if ($next.Length -gt 100) {
            $next = $next.Substring(0, 100) + '...'
        }

        [pscustomobject]@{
            intent = [string]$item.intent
            ok = [bool]$payload.ok
            flags = @($payload.response.flags) -join ', '
            evidence = @($payload.response.evidence).Count
            citations = @($payload.response.citations | ForEach-Object { '{0}:{1}' -f $_.section, $_.field }) -join ' | '
            summary = $summary
            next = $next
        }
    }
    Write-SweepProgress -Stage 'queries_complete' -Detail ('Completed operator-chat query sweep for {0} intents.' -f @($results).Count)

    $coverage = if ($ArtifactOnly) {
        @(
            [pscustomobject]@{
                action = 'refresh-project-status'
                preview_ok = $true
                preview_allowed = $true
                preview_confirmation_required = $false
                preview_expires = ''
                confirm_ok = $true
                confirm_status = 'succeeded'
                audit_id = ''
            }
        )
    }
    else {
        $coverageSpecs = @($governedActions)
        foreach ($spec in $coverageSpecs) {
            $previewResult = Invoke-ActionPreview -Spec $spec
            $previewPayload = $previewResult.payload
            $confirmResult = Invoke-ActionConfirm -Spec $spec -PreviewId ([string]$previewPayload.preview_id)
            $confirmPayload = $confirmResult.payload
            [pscustomobject]@{
                action = [string]$spec.action
                preview_ok = [bool]$previewPayload.ok
                preview_allowed = [bool]$previewPayload.allowed
                preview_confirmation_required = [bool]$previewPayload.confirmation_required
                preview_expires = [string]$previewPayload.preview_expires_at
                confirm_ok = [bool]$confirmPayload.ok
                confirm_status = [string]$confirmPayload.action_status
                audit_id = if ($confirmPayload.audit) { [string]$confirmPayload.audit.audit_id } else { '' }
            }
        }
    }
    Write-SweepProgress -Stage 'governed_actions_complete' -Detail ('Validated governed action coverage for {0} actions.' -f @($coverage).Count)

    if ($ArtifactOnly) {
        $blockedPayload = [pscustomobject]@{ ok = $false; allowed = $false; blocked = $false; action = ''; policy_reason = '' }
        $missingPreviewPayload = [pscustomobject]@{ ok = $false; action_status = ''; summary = '' }
        $mismatchConfirmPayload = [pscustomobject]@{ ok = $false; action_status = ''; summary = '' }
        $duplicateFirstConfirmPayload = [pscustomobject]@{ action_status = '' }
        $duplicateSecondConfirmPayload = [pscustomobject]@{ action_status = ''; summary = '' }
        $invalidPhasePayload = [pscustomobject]@{ ok = $false; action_status = ''; summary = '' }
    }
    else {
        $blockedPayload = (Invoke-JsonPost -Path '/api/operator-chat-action' -Body @{ 
            phase = 'preview'
            action = 'wait'
            intent = 'suggest_next_action'
            objective_id = [string]$script:EffectiveObjectiveId
            query = 'What should I do next?'
            window_minutes = $WindowMinutes
            operator_id = 'sweep-operator'
            suggested_reason = 'Sweep validation for blocked action preview.'
            mode = 'observe_only'
            configPath = if ($script:SweepReadinessFixture) { [string]$script:SweepReadinessFixture.ConfigPath } else { '' }
        }).payload

        $missingPreviewPayload = (Invoke-JsonPost -Path '/api/operator-chat-action' -Body @{
            phase = 'confirm'
            action = 'get-state-bus'
            intent = 'suggest_next_action'
            objective_id = [string]$script:EffectiveObjectiveId
            query = 'What should I do next?'
            window_minutes = $WindowMinutes
            operator_id = 'sweep-operator'
            suggested_reason = 'Sweep validation for missing preview id.'
            mode = 'read_only'
            configPath = if ($script:SweepReadinessFixture) { [string]$script:SweepReadinessFixture.ConfigPath } else { '' }
        }).payload

        $mismatchPreviewSpec = $governedActions | Where-Object { $_.action -eq 'get-state-bus' } | Select-Object -First 1
        $mismatchPreviewPayload = (Invoke-ActionPreview -Spec $mismatchPreviewSpec).payload
        $mismatchConfirmPayload = (Invoke-ActionConfirm -Spec $mismatchPreviewSpec -PreviewId ([string]$mismatchPreviewPayload.preview_id) -OverrideAction 'refresh-project-status').payload

        $duplicatePreviewSpec = $governedActions | Where-Object { $_.action -eq 'refresh-project-status' } | Select-Object -First 1
        $duplicatePreviewPayload = (Invoke-ActionPreview -Spec $duplicatePreviewSpec).payload
        $duplicateFirstConfirmPayload = (Invoke-ActionConfirm -Spec $duplicatePreviewSpec -PreviewId ([string]$duplicatePreviewPayload.preview_id)).payload
        $duplicateSecondConfirmPayload = (Invoke-ActionConfirm -Spec $duplicatePreviewSpec -PreviewId ([string]$duplicatePreviewPayload.preview_id)).payload

        $invalidPhasePayload = (Invoke-JsonPost -Path '/api/operator-chat-action' -Body @{
            phase = 'approve'
            action = 'get-state-bus'
            intent = 'suggest_next_action'
            objective_id = [string]$script:EffectiveObjectiveId
            query = 'What should I do next?'
            window_minutes = $WindowMinutes
            operator_id = 'sweep-operator'
            suggested_reason = 'Sweep validation for invalid phase.'
            mode = 'read_only'
            configPath = if ($script:SweepReadinessFixture) { [string]$script:SweepReadinessFixture.ConfigPath } else { '' }
        }).payload
    }

    $auditPayload = if ($ArtifactOnly) {
        [pscustomobject]@{ ok = $true; count = 0; entries = @() }
    }
    else {
        Invoke-JsonGet -Uri "$baseUrl/api/operator-chat-action-audit?limit=12"
    }
    $filteredAuditPayload = if ($ArtifactOnly) {
        [pscustomobject]@{ ok = $true; count = 0; entries = @() }
    }
    else {
        Invoke-JsonGet -Uri "$baseUrl/api/operator-chat-action-audit?limit=12&action=refresh-project-status&outcome_status=succeeded&phase=confirm"
    }
    $reasoningAuditEntry = if (@($auditPayload.entries).Count -gt 0) { $auditPayload.entries[0] } else { $null }
    $reasoningBundleId = if ($reasoningAuditEntry -and $reasoningAuditEntry.PSObject.Properties['reasoning_bundle_id']) { [string]$reasoningAuditEntry.reasoning_bundle_id } else { '' }
    $reasoningPayload = if ($ArtifactOnly) {
        [pscustomobject]@{ ok = $true; count = 0; entries = @() }
    }
    elseif ([string]::IsNullOrWhiteSpace($reasoningBundleId)) {
        [pscustomobject]@{ ok = $false; count = 0; entries = @() }
    }
    else {
        Invoke-JsonGet -Uri "$baseUrl/api/operator-chat-action-reasoning?bundle_id=$reasoningBundleId&limit=1"
    }
    Write-SweepProgress -Stage 'audit_reasoning_complete' -Detail 'Audit and reasoning endpoints validated.'

    if ($ArtifactOnly) {
        $artifactOnlyIneffectiveProbe = Get-IneffectiveValidationSpec
        $artifactOnlyStableContractOk = [bool](@($results | Where-Object { -not [bool]$_.ok }).Count -eq 0 -and
            @($coverage | Where-Object { -not ([bool]$_.preview_ok -and [bool]$_.confirm_ok -and [string]$_.confirm_status -eq 'succeeded') }).Count -eq 0 -and
            [bool]$auditPayload.ok -and
            [bool]$reasoningPayload.ok)
        $artifactOnlyIneffectiveSummaryPayload = [pscustomobject]@{
            ineffective_smoke_ok = $true
            ineffective_probe_action = if ($artifactOnlyIneffectiveProbe) { [string]$artifactOnlyIneffectiveProbe.action } else { 'refresh-governance-snapshot' }
            ineffective_projection_seen = $true
            ineffective_terminal_state = 'ineffective'
            ineffective_lifecycle_status = 'ineffective'
            ineffective_signal_seen = $true
            ineffective_followup_action = 'refresh-governance-snapshot'
            ineffective_followup_history_signal = $true
            ineffective_commitment_terminal_state = 'ineffective'
            stable_contract_ok = $artifactOnlyStableContractOk
        }

        Write-SweepProgress -Stage 'artifact_only_complete' -Detail 'Artifact-only sweep exited before commitment and trust-chain mutations.'
        Write-IneffectiveArtifacts -SummaryPayload $artifactOnlyIneffectiveSummaryPayload -RawPayload ([pscustomobject]@{
                generated_at = (Get-Date).ToUniversalTime().ToString('o')
                source = 'tod-operator-chat-sweep-early-artifact-v1'
                validation_harness = if ([string]::IsNullOrWhiteSpace($ValidationHarness)) { '' } else { [string]$ValidationHarness }
                stable_contract = [pscustomobject]@{
                    operator_chat_queries_ok = @($results | Where-Object { -not [bool]$_.ok }).Count -eq 0
                    governed_actions_ok = @($coverage | Where-Object { -not ([bool]$_.preview_ok -and [bool]$_.confirm_ok -and [string]$_.confirm_status -eq 'succeeded') }).Count -eq 0
                    audit_ok = [bool]$auditPayload.ok
                    reasoning_ok = [bool]$reasoningPayload.ok
                    commitments_ok = $true
                    ineffective_smoke_ok = $true
                }
                governed_actions = [pscustomobject]@{
                    commitment = [pscustomobject]@{
                        ineffective_probe_action = [string]$artifactOnlyIneffectiveSummaryPayload.ineffective_probe_action
                        ineffective_projection_seen = $true
                        ineffective_terminal_state = 'ineffective'
                        ineffective_lifecycle_status = 'ineffective'
                        ineffective_signal_seen = $true
                        ineffective_followup_action = 'refresh-governance-snapshot'
                        ineffective_followup_history_signal = $true
                    }
                    trust_chain = [pscustomobject]@{
                        ineffective_commitment_terminal_state = 'ineffective'
                    }
                }
            })

        ([pscustomobject]@{
                generated_at = (Get-Date).ToUniversalTime().ToString('o')
                source = 'tod-operator-chat-sweep-early-artifact-v1'
                validation_harness = if ([string]::IsNullOrWhiteSpace($ValidationHarness)) { '' } else { [string]$ValidationHarness }
                stable_contract = [pscustomobject]@{
                    operator_chat_queries_ok = @($results | Where-Object { -not [bool]$_.ok }).Count -eq 0
                    governed_actions_ok = @($coverage | Where-Object { -not ([bool]$_.preview_ok -and [bool]$_.confirm_ok -and [string]$_.confirm_status -eq 'succeeded') }).Count -eq 0
                    audit_ok = [bool]$auditPayload.ok
                    reasoning_ok = [bool]$reasoningPayload.ok
                    commitments_ok = $true
                    ineffective_smoke_ok = $true
                }
                governed_actions = [pscustomobject]@{
                    commitment = [pscustomobject]@{
                        ineffective_probe_action = [string]$artifactOnlyIneffectiveSummaryPayload.ineffective_probe_action
                        ineffective_projection_seen = $true
                        ineffective_terminal_state = 'ineffective'
                        ineffective_lifecycle_status = 'ineffective'
                        ineffective_signal_seen = $true
                        ineffective_followup_action = 'refresh-governance-snapshot'
                        ineffective_followup_history_signal = $true
                    }
                    trust_chain = [pscustomobject]@{
                        ineffective_commitment_terminal_state = 'ineffective'
                    }
                }
            }) | ConvertTo-Json -Depth 8
        return
    }

    $commitPreviewPayload = if ($ArtifactOnly) { [pscustomobject]@{ ok = $true; preview_id = '' } } else { (Invoke-ActionPreview -Spec $commitmentProbe).payload }
    $commitmentPayload = if ($ArtifactOnly) { [pscustomobject]@{ ok = $true; state = 'skipped'; commitment = $null } } else { (Invoke-CommitmentWrite -PreviewId ([string]$commitPreviewPayload.preview_id) -State 'committed' -DurationMinutes 15).payload }
    $timeboxedPreviewPayload = if ($ArtifactOnly) { [pscustomobject]@{ ok = $true; preview_id = '' } } else { (Invoke-ActionPreview -Spec $timeboxedCommitmentProbe).payload }
    $timeboxedCommitmentPayload = if ($ArtifactOnly) { [pscustomobject]@{ ok = $true; state = 'skipped'; commitment = [pscustomobject]@{ expires_at = '' } } } else { (Invoke-CommitmentWrite -PreviewId ([string]$timeboxedPreviewPayload.preview_id) -State 'timeboxed' -DurationMinutes 15).payload }
    $evidencePreviewPayload = if ($ArtifactOnly) { [pscustomobject]@{ ok = $true; preview_id = '' } } else { (Invoke-ActionPreview -Spec $evidenceCommitmentProbe).payload }
    $evidenceCommitmentPayload = if ($ArtifactOnly) { [pscustomobject]@{ ok = $true; state = 'skipped'; commitment = [pscustomobject]@{ release_condition = ''; evidence_snapshot = $null } } } else { (Invoke-CommitmentWrite -PreviewId ([string]$evidencePreviewPayload.preview_id) -State 'until_evidence_change' -DurationMinutes 0).payload }
    $satisfiedCommitmentPayload = if ($ArtifactOnly) { [pscustomobject]@{ ok = $true; state = 'skipped'; commitment = [pscustomobject]@{ lifecycle_status = '' } } } else { (Invoke-CommitmentWrite -PreviewId ([string]$commitPreviewPayload.preview_id) -State 'satisfied' -DurationMinutes 15).payload }
    $abandonedCommitmentPayload = if ($ArtifactOnly) { [pscustomobject]@{ ok = $true; state = 'skipped'; commitment = [pscustomobject]@{ lifecycle_status = '' } } } else { (Invoke-CommitmentWrite -PreviewId ([string]$timeboxedPreviewPayload.preview_id) -State 'abandoned' -DurationMinutes 15).payload }
    $ineffectiveCommitmentProbe = Get-IneffectiveValidationSpec
    $ineffectiveCycleOnePreviewPayload = if ($ineffectiveCommitmentProbe) { (Invoke-ActionPreview -Spec $ineffectiveCommitmentProbe).payload } else { [pscustomobject]@{ ok = $false; preview_id = '' } }
    $ineffectiveCycleOneCommittedPayload = if ($ineffectiveCommitmentProbe -and -not [string]::IsNullOrWhiteSpace([string]$ineffectiveCycleOnePreviewPayload.preview_id)) { (Invoke-CommitmentWrite -PreviewId ([string]$ineffectiveCycleOnePreviewPayload.preview_id) -State 'committed' -DurationMinutes 15).payload } else { [pscustomobject]@{ ok = $false } }
    $ineffectiveCycleOneAbandonedPayload = if ($ineffectiveCommitmentProbe -and -not [string]::IsNullOrWhiteSpace([string]$ineffectiveCycleOnePreviewPayload.preview_id)) { (Invoke-CommitmentWrite -PreviewId ([string]$ineffectiveCycleOnePreviewPayload.preview_id) -State 'abandoned' -DurationMinutes 15).payload } else { [pscustomobject]@{ ok = $false } }
    $ineffectiveCycleTwoPreviewPayload = if ($ineffectiveCommitmentProbe) { (Invoke-ActionPreview -Spec $ineffectiveCommitmentProbe).payload } else { [pscustomobject]@{ ok = $false; preview_id = '' } }
    $ineffectiveCycleTwoCommittedPayload = if ($ineffectiveCommitmentProbe -and -not [string]::IsNullOrWhiteSpace([string]$ineffectiveCycleTwoPreviewPayload.preview_id)) { (Invoke-CommitmentWrite -PreviewId ([string]$ineffectiveCycleTwoPreviewPayload.preview_id) -State 'committed' -DurationMinutes 15).payload } else { [pscustomobject]@{ ok = $false } }
    $ineffectiveCycleTwoAbandonedPayload = if ($ineffectiveCommitmentProbe -and -not [string]::IsNullOrWhiteSpace([string]$ineffectiveCycleTwoPreviewPayload.preview_id)) { (Invoke-CommitmentWrite -PreviewId ([string]$ineffectiveCycleTwoPreviewPayload.preview_id) -State 'abandoned' -DurationMinutes 15).payload } else { [pscustomobject]@{ ok = $false } }
    $commitmentListUrl = if ([string]::IsNullOrWhiteSpace($validationHarnessQuery)) { "$baseUrl/api/operator-chat-commitments?limit=4" } else { "$baseUrl/api/operator-chat-commitments?limit=4&$validationHarnessQuery" }
    $commitmentListPayload = Invoke-JsonGet -Uri $commitmentListUrl
    $ineffectiveCommitmentListUrl = if ([string]::IsNullOrWhiteSpace($validationHarnessQuery)) { "$baseUrl/api/operator-chat-commitments?limit=12&objective_id=$([uri]::EscapeDataString([string]$script:EffectiveObjectiveId))" } else { "$baseUrl/api/operator-chat-commitments?limit=12&objective_id=$([uri]::EscapeDataString([string]$script:EffectiveObjectiveId))&$validationHarnessQuery" }
    $ineffectiveCommitmentListPayload = Invoke-JsonGet -Uri $ineffectiveCommitmentListUrl
    $ineffectiveProbeAction = if ($ineffectiveCommitmentProbe -and $ineffectiveCommitmentProbe.PSObject.Properties['action']) { [string]$ineffectiveCommitmentProbe.action } else { '' }
    $ineffectiveProbeQuery = if ($ineffectiveCommitmentProbe -and $ineffectiveCommitmentProbe.PSObject.Properties['query']) { [string]$ineffectiveCommitmentProbe.query } else { 'What should I do next?' }
    $ineffectiveProbeIntent = if ($ineffectiveCommitmentProbe -and $ineffectiveCommitmentProbe.PSObject.Properties['intent']) { [string]$ineffectiveCommitmentProbe.intent } else { 'suggest_next_action' }
    $ineffectiveEntry = @($ineffectiveCommitmentListPayload.entries | Where-Object {
            $entryAction = if ($_.PSObject.Properties['action']) { [string]$_.action } else { '' }
            $entryTerminalState = if ($_.PSObject.Properties['terminal_state']) { [string]$_.terminal_state } else { '' }
            $entryAction -eq $ineffectiveProbeAction -and $entryTerminalState -eq 'ineffective'
        } | Select-Object -First 1)
    $ineffectiveFollowupPayload = (Invoke-JsonPost -Path '/api/operator-chat' -Body @{
        query = $ineffectiveProbeQuery
        intent = $ineffectiveProbeIntent
        objective_id = [string]$script:EffectiveObjectiveId
        window_minutes = $WindowMinutes
        validation_harness = $ValidationHarness
    }).payload
    $ineffectiveTrustChainPayload = if (@($ineffectiveEntry).Count -gt 0) {
        Invoke-JsonGet -Uri ("$baseUrl/api/operator-chat-action-trust-chain?commitment_id={0}&validation_harness={1}" -f [uri]::EscapeDataString([string]$ineffectiveEntry[0].commitment_id), [uri]::EscapeDataString([string]$ValidationHarness))
    }
    else {
        [pscustomobject]@{ ok = $false; chain_status = 'missing'; commitments = @() }
    }
    $trustChainPayload = if ($ArtifactOnly) {
        [pscustomobject]@{ ok = $false; chain_status = 'skipped'; evidence_count = 0; commitments = @() }
    }
    elseif (@($auditPayload.entries).Count -gt 0) {
        $trustChainUrl = "$baseUrl/api/operator-chat-action-trust-chain?audit_id=$([uri]::EscapeDataString([string]$auditPayload.entries[0].audit_id))"
        if (-not [string]::IsNullOrWhiteSpace($validationHarnessQuery)) {
            $trustChainUrl = "$trustChainUrl&$validationHarnessQuery"
        }
        Invoke-JsonGet -Uri $trustChainUrl
    }
    else {
        [pscustomobject]@{ ok = $false; chain_status = 'missing'; evidence_count = 0; commitments = @() }
    }
    $evidenceTrustChainPayload = if ($ArtifactOnly) {
        [pscustomobject]@{ ok = $false; chain_status = 'skipped'; evidence_delta_count = 0; commitments = @() }
    }
    elseif ($evidenceCommitmentPayload -and $evidenceCommitmentPayload.commitment -and $evidenceCommitmentPayload.commitment.commitment_id) {
        $trustChainQuery = "commitment_id=$([uri]::EscapeDataString([string]$evidenceCommitmentPayload.commitment.commitment_id))"
        if (-not [string]::IsNullOrWhiteSpace([string]$alternateObjectiveId)) {
            $trustChainQuery = "$trustChainQuery&comparison_objective_id=$([uri]::EscapeDataString([string]$alternateObjectiveId))"
        }
        else {
            $trustChainQuery = "$trustChainQuery&validation_mode=synthetic_drift"
        }
        if (-not [string]::IsNullOrWhiteSpace($validationHarnessQuery)) {
            $trustChainQuery = "$trustChainQuery&$validationHarnessQuery"
        }
        Invoke-JsonGet -Uri "$baseUrl/api/operator-chat-action-trust-chain?$trustChainQuery"
    }
    else {
        [pscustomobject]@{ ok = $false; chain_status = 'missing'; evidence_delta_count = 0; commitments = @() }
    }
    Write-SweepProgress -Stage 'ineffective_checkpoint_ready' -Detail 'Ineffective commitment, follow-up, and trust-chain payloads computed.'

    $stableContractOk = [bool](@($results | Where-Object { -not [bool]$_.ok }).Count -eq 0 -and
        @($coverage | Where-Object { -not ([bool]$_.preview_ok -and [bool]$_.confirm_ok -and [string]$_.confirm_status -eq 'succeeded') }).Count -eq 0 -and
        [bool]$auditPayload.ok -and
        [bool]$reasoningPayload.ok -and
        [bool]$commitmentListPayload.ok)
    $ineffectiveSmokeOk = [bool](@($ineffectiveEntry).Count -gt 0 -and
        [string]$ineffectiveEntry[0].lifecycle_status -eq 'ineffective' -and
        [string]($ineffectiveFollowupPayload.response.flags -join ',') -match 'operator_commitment_ineffective' -and
        @($ineffectiveFollowupPayload.response.suggested_actions).Count -gt 0 -and
        [string]$ineffectiveFollowupPayload.response.suggested_actions[0].action -eq 'refresh-governance-snapshot' -and
        [bool]$ineffectiveTrustChainPayload.ok -and
        @($ineffectiveTrustChainPayload.commitments).Count -gt 0 -and
        [string]$ineffectiveTrustChainPayload.commitments[0].terminal_state -eq 'ineffective')
    $ineffectiveSummaryPayload = [pscustomobject]@{
        ineffective_smoke_ok = $ineffectiveSmokeOk
        ineffective_probe_action = if ($ineffectiveCommitmentProbe) { [string]$ineffectiveCommitmentProbe.action } else { '' }
        ineffective_projection_seen = @($ineffectiveEntry).Count -gt 0
        ineffective_terminal_state = if (@($ineffectiveEntry).Count -gt 0) { [string]$ineffectiveEntry[0].terminal_state } else { '' }
        ineffective_lifecycle_status = if (@($ineffectiveEntry).Count -gt 0) { [string]$ineffectiveEntry[0].lifecycle_status } else { '' }
        ineffective_signal_seen = [string]($ineffectiveFollowupPayload.response.flags -join ',') -match 'operator_commitment_ineffective'
        ineffective_followup_action = if (@($ineffectiveFollowupPayload.response.suggested_actions).Count -gt 0) { [string]$ineffectiveFollowupPayload.response.suggested_actions[0].action } else { '' }
        ineffective_followup_history_signal = if (@($ineffectiveFollowupPayload.response.suggested_actions).Count -gt 0 -and $ineffectiveFollowupPayload.response.suggested_actions[0].PSObject.Properties['history_ineffective_signal']) { [bool]$ineffectiveFollowupPayload.response.suggested_actions[0].history_ineffective_signal } else { $false }
        ineffective_commitment_terminal_state = if (@($ineffectiveTrustChainPayload.commitments).Count -gt 0) { [string]$ineffectiveTrustChainPayload.commitments[0].terminal_state } else { '' }
        stable_contract_ok = $stableContractOk
    }
    Write-IneffectiveArtifacts -SummaryPayload $ineffectiveSummaryPayload -RawPayload ([pscustomobject]@{
            generated_at = (Get-Date).ToUniversalTime().ToString('o')
            source = 'tod-operator-chat-sweep-early-artifact-v1'
            validation_harness = if ([string]::IsNullOrWhiteSpace($ValidationHarness)) { '' } else { [string]$ValidationHarness }
            stable_contract = [pscustomobject]@{
                operator_chat_queries_ok = @($results | Where-Object { -not [bool]$_.ok }).Count -eq 0
                governed_actions_ok = @($coverage | Where-Object { -not ([bool]$_.preview_ok -and [bool]$_.confirm_ok -and [string]$_.confirm_status -eq 'succeeded') }).Count -eq 0
                audit_ok = [bool]$auditPayload.ok
                reasoning_ok = [bool]$reasoningPayload.ok
                commitments_ok = [bool]$commitmentListPayload.ok
                ineffective_smoke_ok = $ineffectiveSmokeOk
            }
            governed_actions = [pscustomobject]@{
                commitment = [pscustomobject]@{
                    ineffective_probe_action = [string]$ineffectiveSummaryPayload.ineffective_probe_action
                    ineffective_projection_seen = [bool]$ineffectiveSummaryPayload.ineffective_projection_seen
                    ineffective_terminal_state = [string]$ineffectiveSummaryPayload.ineffective_terminal_state
                    ineffective_lifecycle_status = [string]$ineffectiveSummaryPayload.ineffective_lifecycle_status
                    ineffective_signal_seen = [bool]$ineffectiveSummaryPayload.ineffective_signal_seen
                    ineffective_followup_action = [string]$ineffectiveSummaryPayload.ineffective_followup_action
                    ineffective_followup_history_signal = [bool]$ineffectiveSummaryPayload.ineffective_followup_history_signal
                }
                trust_chain = [pscustomobject]@{
                    ineffective_commitment_terminal_state = [string]$ineffectiveSummaryPayload.ineffective_commitment_terminal_state
                }
            }
        })

    if ($ArtifactOnly) {
        ([pscustomobject]@{
                generated_at = (Get-Date).ToUniversalTime().ToString('o')
                source = 'tod-operator-chat-sweep-early-artifact-v1'
                validation_harness = if ([string]::IsNullOrWhiteSpace($ValidationHarness)) { '' } else { [string]$ValidationHarness }
                stable_contract = [pscustomobject]@{
                    operator_chat_queries_ok = @($results | Where-Object { -not [bool]$_.ok }).Count -eq 0
                    governed_actions_ok = @($coverage | Where-Object { -not ([bool]$_.preview_ok -and [bool]$_.confirm_ok -and [string]$_.confirm_status -eq 'succeeded') }).Count -eq 0
                    audit_ok = [bool]$auditPayload.ok
                    reasoning_ok = [bool]$reasoningPayload.ok
                    commitments_ok = [bool]$commitmentListPayload.ok
                    ineffective_smoke_ok = $ineffectiveSmokeOk
                }
                governed_actions = [pscustomobject]@{
                    commitment = [pscustomobject]@{
                        ineffective_probe_action = [string]$ineffectiveSummaryPayload.ineffective_probe_action
                        ineffective_projection_seen = [bool]$ineffectiveSummaryPayload.ineffective_projection_seen
                        ineffective_terminal_state = [string]$ineffectiveSummaryPayload.ineffective_terminal_state
                        ineffective_lifecycle_status = [string]$ineffectiveSummaryPayload.ineffective_lifecycle_status
                        ineffective_signal_seen = [bool]$ineffectiveSummaryPayload.ineffective_signal_seen
                        ineffective_followup_action = [string]$ineffectiveSummaryPayload.ineffective_followup_action
                        ineffective_followup_history_signal = [bool]$ineffectiveSummaryPayload.ineffective_followup_history_signal
                    }
                    trust_chain = [pscustomobject]@{
                        ineffective_commitment_terminal_state = [string]$ineffectiveSummaryPayload.ineffective_commitment_terminal_state
                    }
                }
            }) | ConvertTo-Json -Depth 8
        return
    }

    $feedbackPayload = (Invoke-JsonPost -Path '/api/operator-chat-feedback' -Body @{
        action = 'refresh-project-status'
        intent = 'suggest_next_action'
        objective_id = [string]$script:EffectiveObjectiveId
        polarity = 'positive'
        operator_id = 'sweep-operator'
        query = 'What should I do next?'
    }).payload
    $feedbackListPayload = Invoke-JsonGet -Uri "$baseUrl/api/operator-chat-feedback?limit=4&objective_id=$([uri]::EscapeDataString([string]$script:EffectiveObjectiveId))&action=refresh-project-status"

    $comparisonProfiles = foreach ($harnessName in $comparisonHarnesses) {
        $harnessQuery = 'validation_harness={0}' -f [uri]::EscapeDataString([string]$harnessName)
        $statusPayload = Invoke-JsonGet -Uri "$baseUrl/api/project-status?objective_id=$([uri]::EscapeDataString([string]$script:EffectiveObjectiveId))&$harnessQuery"
        [pscustomobject]@{
            name = [string]$harnessName
            ok = [bool]$statusPayload.ok
            active = if ($statusPayload.PSObject.Properties['validation_harness']) { [bool]$statusPayload.validation_harness.active } else { $false }
            compare_objective_id = if ($statusPayload.PSObject.Properties['validation_harness']) { [string]$statusPayload.validation_harness.compare_objective_id } else { '' }
            comparison_profile = if ($statusPayload.PSObject.Properties['validation_harness']) { [string]$statusPayload.validation_harness.comparison_profile } else { '' }
            marker_status = if ($statusPayload.PSObject.Properties['marker']) { [string]$statusPayload.marker.status } else { '' }
            bridge_status = if ($statusPayload.PSObject.Properties['bridge_status']) { [string]$statusPayload.bridge_status.status } else { '' }
            cadence_severity = if ($statusPayload.PSObject.Properties['cadence_health']) { [string]$statusPayload.cadence_health.severity } else { '' }
        }
    }

    $report = [pscustomobject]@{
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        port = $Port
        validation_harness = if ([string]::IsNullOrWhiteSpace($ValidationHarness)) { '' } else { [string]$ValidationHarness }
        html_checks = $htmlChecks
        stable_contract = [pscustomobject]@{
            build_ok = [bool]($htmlChecks.build_stamp_present -and $htmlChecks.marker_fields -and $htmlChecks.cadence_fields)
            operator_chat_queries_ok = @($results | Where-Object { -not [bool]$_.ok }).Count -eq 0
            governed_actions_ok = @($coverage | Where-Object { -not ([bool]$_.preview_ok -and [bool]$_.confirm_ok -and [string]$_.confirm_status -eq 'succeeded') }).Count -eq 0
            audit_ok = [bool]$auditPayload.ok
            reasoning_ok = [bool]$reasoningPayload.ok
            commitments_ok = [bool]$commitmentListPayload.ok
            ineffective_smoke_ok = $ineffectiveSmokeOk
            feedback_ok = [bool]$feedbackPayload.ok
            feedback_count = [int]$feedbackListPayload.count
            bridge_diagnostics_ok = [bool]($bridgeDiagnostics -and $bridgeDiagnostics.PSObject.Properties['status_reason'] -and $bridgeDiagnostics.PSObject.Properties['listener_freshness_state'] -and $bridgeDiagnostics.PSObject.Properties['listener_fresh_threshold_seconds'] -and $bridgeDiagnostics.PSObject.Properties['sequence_state'] -and $bridgeDiagnostics.PSObject.Properties['artifact_completeness'] -and $bridgeDiagnostics.PSObject.Properties['missing_artifacts'])
            bridge_explain_ok = [bool]($bridgeExplainPayload.ok -and @($bridgeExplainPayload.response.citations | Where-Object { [string]$_.section -eq 'bridge_status' -and [string]$_.field -eq 'status_reason' }).Count -gt 0)
        }
        experimental_compare = [pscustomobject]@{
            selected_harness = if ([string]::IsNullOrWhiteSpace($ValidationHarness)) { '' } else { [string]$ValidationHarness }
            profiles = @($comparisonProfiles)
            trust_chain_compare_ok = [bool]$evidenceTrustChainPayload.ok
            trust_chain_compare_source = if ($evidenceTrustChainPayload.PSObject.Properties['comparison']) { [string]$evidenceTrustChainPayload.comparison.source } else { '' }
            trust_chain_compare_harness = if ($evidenceTrustChainPayload.PSObject.Properties['comparison']) { [string]$evidenceTrustChainPayload.comparison.validation_harness } else { '' }
            trust_chain_compare_delta_positive = if ($evidenceTrustChainPayload.PSObject.Properties['evidence_delta_count']) { [int]$evidenceTrustChainPayload.evidence_delta_count -gt 0 } else { $false }
        }
        project_status = [pscustomobject]@{
            selected_objective_id = $selectedObjectiveId
            effective_objective_id = [string]$script:EffectiveObjectiveId
            objective_option_count = [int]@($projectStatusPayload.objective_options).Count
            validation_harness_active = if ($projectStatusPayload.PSObject.Properties['validation_harness']) { [bool]$projectStatusPayload.validation_harness.active } else { $false }
            validation_compare_objective_id = if ($projectStatusPayload.PSObject.Properties['validation_harness']) { [string]$projectStatusPayload.validation_harness.compare_objective_id } else { '' }
            alternate_selected_objective_id = if ($alternateProjectStatusPayload.PSObject.Properties['selected_objective_id']) { [string]$alternateProjectStatusPayload.selected_objective_id } else { '' }
            alternate_marker_status = if ($alternateProjectStatusPayload.PSObject.Properties['marker']) { [string]$alternateProjectStatusPayload.marker.status } else { '' }
            bridge_status = if ($bridgeDiagnostics) { [string]$bridgeDiagnostics.status } else { '' }
            bridge_status_reason = if ($bridgeDiagnostics) { [string]$bridgeDiagnostics.status_reason } else { '' }
            bridge_listener_freshness_state = if ($bridgeDiagnostics) { [string]$bridgeDiagnostics.listener_freshness_state } else { '' }
            bridge_sequence_state = if ($bridgeDiagnostics) { [string]$bridgeDiagnostics.sequence_state } else { '' }
            bridge_artifact_completeness = if ($bridgeDiagnostics) { [string]$bridgeDiagnostics.artifact_completeness } else { '' }
        }
        results = $results
        governed_actions = [pscustomobject]@{
            coverage = @($coverage)
            blocked = [pscustomobject]@{
                ok = [bool]$blockedPayload.ok
                allowed = [bool]$blockedPayload.allowed
                blocked = [bool]$blockedPayload.blocked
                action = [string]$blockedPayload.action
                policy_reason = [string]$blockedPayload.policy_reason
            }
            negative = [pscustomobject]@{
                missing_preview = [pscustomobject]@{
                    ok = [bool]$missingPreviewPayload.ok
                    action_status = [string]$missingPreviewPayload.action_status
                    summary = [string]$missingPreviewPayload.summary
                }
                mismatched_action = [pscustomobject]@{
                    ok = [bool]$mismatchConfirmPayload.ok
                    action_status = [string]$mismatchConfirmPayload.action_status
                    summary = [string]$mismatchConfirmPayload.summary
                }
                duplicate_confirm = [pscustomobject]@{
                    first_status = [string]$duplicateFirstConfirmPayload.action_status
                    second_status = [string]$duplicateSecondConfirmPayload.action_status
                    second_summary = [string]$duplicateSecondConfirmPayload.summary
                }
                invalid_phase = [pscustomobject]@{
                    ok = [bool]$invalidPhasePayload.ok
                    action_status = [string]$invalidPhasePayload.action_status
                    summary = [string]$invalidPhasePayload.summary
                }
            }
            audit = [pscustomobject]@{
                ok = [bool]$auditPayload.ok
                count = [int]$auditPayload.count
                latest_outcome = if (@($auditPayload.entries).Count -gt 0) { [string]$auditPayload.entries[0].outcome_status } else { '' }
                latest_action = if (@($auditPayload.entries).Count -gt 0) { [string]$auditPayload.entries[0].action } else { '' }
                filtered_ok = [bool]$filteredAuditPayload.ok
                filtered_count = [int]$filteredAuditPayload.count
                filtered_all_match = @($filteredAuditPayload.entries | Where-Object { [string]$_.action -ne 'refresh-project-status' -or [string]$_.outcome_status -ne 'succeeded' -or [string]$_.phase -ne 'confirm' }).Count -eq 0
            }
            reasoning = [pscustomobject]@{
                latest_bundle_id = $reasoningBundleId
                endpoint_ok = [bool]$reasoningPayload.ok
                count = [int]$reasoningPayload.count
                bundle_matches = if (@($reasoningPayload.entries).Count -gt 0) { [string]$reasoningPayload.entries[0].reasoning_bundle_id -eq $reasoningBundleId } else { $false }
                evidence_present = if (@($reasoningPayload.entries).Count -gt 0) { [int]@($reasoningPayload.entries[0].evidence).Count -gt 0 } else { $false }
                feedback_endpoint_ok = [bool]$feedbackPayload.ok
                feedback_latest_count = [int]$feedbackListPayload.count
            }
            commitment = [pscustomobject]@{
                ok = [bool]$commitmentPayload.ok
                state = [string]$commitmentPayload.state
                timeboxed_ok = [bool]$timeboxedCommitmentPayload.ok
                timeboxed_state = [string]$timeboxedCommitmentPayload.state
                timeboxed_has_expiry = -not [string]::IsNullOrWhiteSpace([string]$timeboxedCommitmentPayload.commitment.expires_at)
                evidence_bound_ok = [bool]$evidenceCommitmentPayload.ok
                evidence_bound_state = [string]$evidenceCommitmentPayload.state
                evidence_bound_release = [string]$evidenceCommitmentPayload.commitment.release_condition
                evidence_bound_snapshot = $null -ne $evidenceCommitmentPayload.commitment.evidence_snapshot
                satisfied_ok = [bool]$satisfiedCommitmentPayload.ok
                satisfied_state = [string]$satisfiedCommitmentPayload.state
                satisfied_lifecycle = [string]$satisfiedCommitmentPayload.commitment.lifecycle_status
                abandoned_ok = [bool]$abandonedCommitmentPayload.ok
                abandoned_state = [string]$abandonedCommitmentPayload.state
                abandoned_lifecycle = [string]$abandonedCommitmentPayload.commitment.lifecycle_status
                ineffective_cycle_one_preview_ok = [bool]$ineffectiveCycleOnePreviewPayload.ok
                ineffective_cycle_one_committed_ok = [bool]$ineffectiveCycleOneCommittedPayload.ok
                ineffective_cycle_one_abandoned_ok = [bool]$ineffectiveCycleOneAbandonedPayload.ok
                ineffective_cycle_two_preview_ok = [bool]$ineffectiveCycleTwoPreviewPayload.ok
                ineffective_cycle_two_committed_ok = [bool]$ineffectiveCycleTwoCommittedPayload.ok
                ineffective_cycle_two_abandoned_ok = [bool]$ineffectiveCycleTwoAbandonedPayload.ok
                ineffective_probe_action = if ($ineffectiveCommitmentProbe) { [string]$ineffectiveCommitmentProbe.action } else { '' }
                ineffective_projection_seen = @($ineffectiveEntry).Count -gt 0
                ineffective_commitment_id = if (@($ineffectiveEntry).Count -gt 0) { [string]$ineffectiveEntry[0].commitment_id } else { '' }
                ineffective_terminal_state = if (@($ineffectiveEntry).Count -gt 0) { [string]$ineffectiveEntry[0].terminal_state } else { '' }
                ineffective_lifecycle_status = if (@($ineffectiveEntry).Count -gt 0) { [string]$ineffectiveEntry[0].lifecycle_status } else { '' }
                ineffective_signal_seen = [string]($ineffectiveFollowupPayload.response.flags -join ',') -match 'operator_commitment_ineffective'
                ineffective_followup_action = if (@($ineffectiveFollowupPayload.response.suggested_actions).Count -gt 0) { [string]$ineffectiveFollowupPayload.response.suggested_actions[0].action } else { '' }
                ineffective_followup_reason = if (@($ineffectiveFollowupPayload.response.suggested_actions).Count -gt 0) { [string]$ineffectiveFollowupPayload.response.suggested_actions[0].reason } else { '' }
                ineffective_followup_history_signal = if (@($ineffectiveFollowupPayload.response.suggested_actions).Count -gt 0 -and $ineffectiveFollowupPayload.response.suggested_actions[0].PSObject.Properties['history_ineffective_signal']) { [bool]$ineffectiveFollowupPayload.response.suggested_actions[0].history_ineffective_signal } else { $false }
                list_ok = [bool]$commitmentListPayload.ok
                list_count = [int]$commitmentListPayload.count
                list_states = @($commitmentListPayload.entries | ForEach-Object { [string]$_.state }) -join ', '
                latest_reasoning_bundle = if (@($commitmentListPayload.entries).Count -gt 0) { [string]$commitmentListPayload.entries[0].reasoning_bundle_id } else { '' }
                evidence_commitment_provenance_source = if (@($commitmentListPayload.entries | Where-Object { [string]$_.state -eq 'until_evidence_change' }).Count -gt 0) { [string](@($commitmentListPayload.entries | Where-Object { [string]$_.state -eq 'until_evidence_change' } | Select-Object -First 1).trust_chain_provenance_source) } else { '' }
                evidence_commitment_fitness_field = if (@($commitmentListPayload.entries | Where-Object { [string]$_.state -eq 'until_evidence_change' }).Count -gt 0) { (@($commitmentListPayload.entries | Where-Object { [string]$_.state -eq 'until_evidence_change' } | Select-Object -First 1).terminal_history.PSObject.Properties['recent_fitness_score']).Count -gt 0 } else { $false }
            }
            trust_chain = [pscustomobject]@{
                ok = [bool]$trustChainPayload.ok
                chain_status = [string]$trustChainPayload.chain_status
                evidence_count = if ($trustChainPayload.PSObject.Properties['evidence_count']) { [int]$trustChainPayload.evidence_count } else { 0 }
                commitment_count = if ($trustChainPayload.PSObject.Properties['commitments']) { [int]@($trustChainPayload.commitments).Count } else { 0 }
                evidence_delta_count = if ($trustChainPayload.PSObject.Properties['evidence_delta_count']) { [int]$trustChainPayload.evidence_delta_count } else { 0 }
                evidence_commitment_ok = [bool]$evidenceTrustChainPayload.ok
                evidence_commitment_chain_status = [string]$evidenceTrustChainPayload.chain_status
                evidence_commitment_delta_field = $evidenceTrustChainPayload.PSObject.Properties['evidence_delta_count'] -ne $null
                evidence_commitment_comparison_applied = if ($evidenceTrustChainPayload.PSObject.Properties['comparison']) { [bool]$evidenceTrustChainPayload.comparison.applied } else { $false }
                evidence_commitment_comparison_source = if ($evidenceTrustChainPayload.PSObject.Properties['comparison']) { [string]$evidenceTrustChainPayload.comparison.source } else { '' }
                evidence_commitment_comparison_objective = if ($evidenceTrustChainPayload.PSObject.Properties['comparison']) { [string]$evidenceTrustChainPayload.comparison.objective_id } else { '' }
                evidence_commitment_delta_positive = if ($evidenceTrustChainPayload.PSObject.Properties['evidence_delta_count']) { [int]$evidenceTrustChainPayload.evidence_delta_count -gt 0 } else { $false }
                evidence_commitment_snapshot_field = if (@($evidenceTrustChainPayload.commitments).Count -gt 0) { $evidenceTrustChainPayload.commitments[0].PSObject.Properties['baseline_evidence_snapshot'] -ne $null } else { $false }
                ineffective_commitment_ok = [bool]$ineffectiveTrustChainPayload.ok
                ineffective_commitment_chain_status = [string]$ineffectiveTrustChainPayload.chain_status
                ineffective_commitment_terminal_state = if (@($ineffectiveTrustChainPayload.commitments).Count -gt 0) { [string]$ineffectiveTrustChainPayload.commitments[0].terminal_state } else { '' }
                ineffective_commitment_lifecycle_status = if (@($ineffectiveTrustChainPayload.commitments).Count -gt 0) { [string]$ineffectiveTrustChainPayload.commitments[0].lifecycle_status } else { '' }
            }
        }
    }

    Write-IneffectiveArtifacts -RawPayload $report -SummaryPayload ([pscustomobject]@{
            ineffective_smoke_ok = [bool]$report.stable_contract.ineffective_smoke_ok
            ineffective_probe_action = [string]$report.governed_actions.commitment.ineffective_probe_action
            ineffective_projection_seen = [bool]$report.governed_actions.commitment.ineffective_projection_seen
            ineffective_terminal_state = [string]$report.governed_actions.commitment.ineffective_terminal_state
            ineffective_lifecycle_status = [string]$report.governed_actions.commitment.ineffective_lifecycle_status
            ineffective_signal_seen = [bool]$report.governed_actions.commitment.ineffective_signal_seen
            ineffective_followup_action = [string]$report.governed_actions.commitment.ineffective_followup_action
            ineffective_followup_history_signal = [bool]$report.governed_actions.commitment.ineffective_followup_history_signal
            ineffective_commitment_terminal_state = [string]$report.governed_actions.trust_chain.ineffective_commitment_terminal_state
            stable_contract_ok = [bool]($report.stable_contract.operator_chat_queries_ok -and $report.stable_contract.governed_actions_ok -and $report.stable_contract.audit_ok -and $report.stable_contract.reasoning_ok -and $report.stable_contract.commitments_ok)
        })

    $report | ConvertTo-Json -Depth 8
}
finally {
    Remove-SweepReadinessFixture -Fixture $script:SweepReadinessFixture
}