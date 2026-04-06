Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$baseUrl = 'http://localhost:8844'

function Invoke-TodJsonGet {
    param([Parameter(Mandatory = $true)][string]$Path)

    $response = Invoke-WebRequest -UseBasicParsing -Uri ("$baseUrl$Path") -TimeoutSec 30
    return ($response.Content | ConvertFrom-Json)
}

function Invoke-TodJsonPost {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Body
    )

    $json = $Body | ConvertTo-Json -Depth 8
    $response = Invoke-WebRequest -UseBasicParsing -Uri ("$baseUrl$Path") -Method Post -ContentType 'application/json' -Body $json -TimeoutSec 30
    return ($response.Content | ConvertFrom-Json)
}

function Test-TodUiReachable {
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri "$baseUrl/api/project-status" -TimeoutSec 5
        return $response.StatusCode -eq 200
    }
    catch {
        return $false
    }
}

function Get-TodCommittableSuggestedAction {
    param($SuggestedActions)

    foreach ($candidate in @($SuggestedActions)) {
        if ($null -eq $candidate) {
            continue
        }

        $mode = if ($candidate.PSObject.Properties['mode']) { [string]$candidate.mode } else { '' }
        if (-not [string]::Equals($mode, 'observe_only', [System.StringComparison]::OrdinalIgnoreCase)) {
            return $candidate
        }
    }

    return $null
}

function Get-TodIneffectiveValidationAction {
    param($SuggestedActions)

    $committable = @($SuggestedActions | Where-Object {
            $null -ne $_ -and
            -not [string]::Equals([string]$_.mode, 'observe_only', [System.StringComparison]::OrdinalIgnoreCase)
        })

    foreach ($candidate in $committable) {
        $sameIntentSatisfiedCount = if ($candidate.PSObject.Properties['history_same_intent_satisfied_count']) { [int]$candidate.history_same_intent_satisfied_count } else { 0 }
        $sameIntentAbandonedCount = if ($candidate.PSObject.Properties['history_same_intent_abandoned_count']) { [int]$candidate.history_same_intent_abandoned_count } else { 0 }
        if ($sameIntentSatisfiedCount -eq 0 -and $sameIntentAbandonedCount -eq 0) {
            return $candidate
        }
    }

    foreach ($candidate in $committable) {
        $sameIntentSatisfiedCount = if ($candidate.PSObject.Properties['history_same_intent_satisfied_count']) { [int]$candidate.history_same_intent_satisfied_count } else { 0 }
        if ($sameIntentSatisfiedCount -eq 0) {
            return $candidate
        }
    }

    return Get-TodCommittableSuggestedAction -SuggestedActions $SuggestedActions
}

Describe 'Operator chat commitments endpoint' {
    It 'returns a shaped commitments payload under the bounded compare harness' {
        if (-not (Test-TodUiReachable)) {
            return
        }

        $payload = Invoke-TodJsonGet -Path '/api/operator-chat-commitments?limit=4&validation_harness=multi_objective_compare'

        $payload.ok | Should Be $true
        $payload.entries | Should Not BeNullOrEmpty
        @($payload.entries).Count | Should BeGreaterThan -1

        if (@($payload.entries).Count -gt 0) {
            $first = @($payload.entries)[0]
            (($first.PSObject.Properties.Name) -contains 'lifecycle_status') | Should Be $true
            (($first.PSObject.Properties.Name) -contains 'release_condition') | Should Be $true
            (($first.PSObject.Properties.Name) -contains 'is_terminal') | Should Be $true
            (($first.PSObject.Properties.Name) -contains 'terminal_state') | Should Be $true
            (($first.PSObject.Properties.Name) -contains 'terminal_detail') | Should Be $true
            (($first.PSObject.Properties.Name) -contains 'terminal_successor_commitment_id') | Should Be $true
            (($first.PSObject.Properties.Name) -contains 'trust_chain_provenance_source') | Should Be $true
            (($first.PSObject.Properties.Name) -contains 'scope_in_scope') | Should Be $true
            (($first.PSObject.Properties.Name) -contains 'scope_status') | Should Be $true
            (($first.PSObject.Properties.Name) -contains 'scope_summary') | Should Be $true
            (($first.PSObject.Properties.Name) -contains 'scope_kind') | Should Be $true
            (($first.PSObject.Properties.Name) -contains 'current_scope_kind') | Should Be $true
            (($first.PSObject.Properties.Name) -contains 'scope_overlap_status') | Should Be $true
            (($first.PSObject.Properties.Name) -contains 'scope_conflict_reason') | Should Be $true
            (($first.PSObject.Properties.Name) -contains 'scope_conflict_resolution') | Should Be $true
            (($first.PSObject.Properties.Name) -contains 'scope_blocks_activation') | Should Be $true
            (($first.PSObject.Properties.Name) -contains 'scope_precedence_rank') | Should Be $true
            (($first.PSObject.Properties.Name) -contains 'scope_influence_summary') | Should Be $true
            (($first.PSObject.Properties.Name) -contains 'current_scope_validation_harness') | Should Be $true
            [string]$first.scope_status | Should Not BeNullOrEmpty
            [string]$first.scope_kind | Should Match 'proposal_specific|objective_wide'
            [string]$first.current_scope_kind | Should Match 'proposal_specific|objective_wide'
            [string]$first.scope_overlap_status | Should Match 'exact|nested_parent|none'
            [string]$first.scope_conflict_resolution | Should Match 'active|downgrade|block'
            [string]$first.terminal_state | Should Match '^$|satisfied|abandoned|superseded|ineffective'
            [int]$first.scope_precedence_rank | Should BeGreaterThan -1
            [string]$first.scope_influence_summary | Should Not BeNullOrEmpty
            [string]$first.current_scope_validation_harness | Should Be 'multi_objective_compare'
        }
    }

    It 'repairs evidence-bound commitment comparison fields when such entries exist' {
        if (-not (Test-TodUiReachable)) {
            return
        }

        $payload = Invoke-TodJsonGet -Path '/api/operator-chat-commitments?limit=8&validation_harness=multi_objective_compare'
        $entry = @($payload.entries | Where-Object { [string]$_.release_condition -eq 'evidence_change' } | Select-Object -First 1)
        if (@($entry).Count -eq 0) {
            return
        }

        $entry = $entry[0]
        (($entry.PSObject.Properties.Name) -contains 'current_evidence_snapshot') | Should Be $true
        (($entry.PSObject.Properties.Name) -contains 'current_evidence_fingerprint') | Should Be $true
        (($entry.PSObject.Properties.Name) -contains 'lifecycle_evaluator') | Should Be $true
        $entry.current_evidence_snapshot | Should Not BeNullOrEmpty
        [int]$entry.evidence_delta_count | Should BeGreaterThan 0
        [string]$entry.lifecycle_evaluator | Should Match 'compare|repaired'
    }

    It 'persists validation harness scope on newly recorded commitments' {
        if (-not (Test-TodUiReachable)) {
            return
        }

        $statusPayload = Invoke-TodJsonGet -Path '/api/project-status?validation_harness=multi_objective_compare'
        $objectiveId = [string]$statusPayload.selected_objective_id
        if ([string]::IsNullOrWhiteSpace($objectiveId)) {
            return
        }

        $chatPayload = Invoke-TodJsonPost -Path '/api/operator-chat' -Body @{
            query = 'What should I do next?'
            intent = 'suggest_next_action'
            window_minutes = 10
            objective_id = $objectiveId
            validation_harness = 'multi_objective_compare'
        }

        $suggestedAction = Get-TodIneffectiveValidationAction -SuggestedActions @($chatPayload.response.suggested_actions)
        if ($null -eq $suggestedAction) {
            return
        }
        $previewIntent = if ($suggestedAction.PSObject.Properties['intent']) { [string]$suggestedAction.intent } else { 'suggest_next_action' }

        $previewPayload = Invoke-TodJsonPost -Path '/api/operator-chat-action' -Body @{
            phase = 'preview'
            action = [string]$suggestedAction.action
            intent = $previewIntent
            objective_id = $objectiveId
            query = 'What should I do next?'
            window_minutes = 10
            operator_id = 'pester-operator'
            suggested_reason = [string]$suggestedAction.reason
            mode = [string]$suggestedAction.mode
        }

        $previewId = [string]$previewPayload.preview_id
        $previewId | Should Not BeNullOrEmpty

        $commitmentPayload = Invoke-TodJsonPost -Path '/api/operator-chat-commitment' -Body @{
            preview_id = $previewId
            objective_id = $objectiveId
            operator_id = 'pester-operator'
            state = 'committed'
            duration_minutes = 15
            validation_harness = 'multi_objective_compare'
        }

        $commitmentPayload.ok | Should Be $true
        [string]$commitmentPayload.commitment.validation_harness | Should Be 'multi_objective_compare'
        [string]$commitmentPayload.commitment.current_scope_validation_harness | Should Be 'multi_objective_compare'
        [string]$commitmentPayload.commitment.scope_status | Should Match 'in_scope|proposal_nested_match'
        [bool]$commitmentPayload.commitment.scope_in_scope | Should Be $true
        [string]$commitmentPayload.commitment.scope_kind | Should Match 'proposal_specific|objective_wide'
        [string]$commitmentPayload.commitment.current_scope_kind | Should Match 'proposal_specific|objective_wide'
        [string]$commitmentPayload.commitment.scope_conflict_resolution | Should Be 'active'
        [string]$commitmentPayload.commitment.scope_overlap_status | Should Match 'exact|nested_parent'
        [int]$commitmentPayload.commitment.scope_precedence_rank | Should BeGreaterThan 0
        [string]$commitmentPayload.commitment.scope_influence_summary | Should Not BeNullOrEmpty
        (($commitmentPayload.commitment.PSObject.Properties.Name) -contains 'scope_proposal_id') | Should Be $true
        (($commitmentPayload.commitment.PSObject.Properties.Name) -contains 'current_scope_proposal_id') | Should Be $true
        if ($statusPayload.PSObject.Properties['mim_proposal'] -and $statusPayload.mim_proposal -and [bool]$statusPayload.mim_proposal.available) {
            [string]$commitmentPayload.commitment.scope_proposal_id | Should Be ([string]$statusPayload.mim_proposal.task_id)
            [string]$commitmentPayload.commitment.current_scope_proposal_id | Should Be ([string]$statusPayload.mim_proposal.task_id)
            [string]$commitmentPayload.commitment.scope_kind | Should Be 'proposal_specific'
            [int]$commitmentPayload.commitment.scope_precedence_rank | Should Be 3
        }

        $clearPayload = Invoke-TodJsonPost -Path '/api/operator-chat-commitment' -Body @{
            preview_id = $previewId
            objective_id = $objectiveId
            operator_id = 'pester-operator'
            state = 'cleared'
            duration_minutes = 15
            validation_harness = 'multi_objective_compare'
        }

        $clearPayload.ok | Should Be $true
        [string]$clearPayload.commitment.validation_harness | Should Be 'multi_objective_compare'
    }

    It 'terminalizes earlier commitment rows once a newer decision resolves the same preview' {
        if (-not (Test-TodUiReachable)) {
            return
        }

        $statusPayload = Invoke-TodJsonGet -Path '/api/project-status?validation_harness=multi_objective_compare'
        $objectiveId = [string]$statusPayload.selected_objective_id
        if ([string]::IsNullOrWhiteSpace($objectiveId)) {
            return
        }

        $chatPayload = Invoke-TodJsonPost -Path '/api/operator-chat' -Body @{
            query = 'What should I do next?'
            intent = 'suggest_next_action'
            window_minutes = 10
            objective_id = $objectiveId
            validation_harness = 'multi_objective_compare'
        }

        $suggestedAction = Get-TodCommittableSuggestedAction -SuggestedActions @($chatPayload.response.suggested_actions)
        if ($null -eq $suggestedAction) {
            return
        }
        $previewIntent = if ($suggestedAction.PSObject.Properties['intent']) { [string]$suggestedAction.intent } else { 'suggest_next_action' }

        $previewPayload = Invoke-TodJsonPost -Path '/api/operator-chat-action' -Body @{
            phase = 'preview'
            action = [string]$suggestedAction.action
            intent = $previewIntent
            objective_id = $objectiveId
            query = 'What should I do next?'
            window_minutes = 10
            operator_id = 'pester-operator'
            suggested_reason = [string]$suggestedAction.reason
            mode = [string]$suggestedAction.mode
        }

        $previewId = [string]$previewPayload.preview_id
        $previewId | Should Not BeNullOrEmpty

        $committedPayload = Invoke-TodJsonPost -Path '/api/operator-chat-commitment' -Body @{
            preview_id = $previewId
            objective_id = $objectiveId
            operator_id = 'pester-operator'
            state = 'committed'
            duration_minutes = 15
            validation_harness = 'multi_objective_compare'
        }

        $committedPayload.ok | Should Be $true
        [bool]$committedPayload.commitment.is_terminal | Should Be $false

        $satisfiedPayload = Invoke-TodJsonPost -Path '/api/operator-chat-commitment' -Body @{
            preview_id = $previewId
            objective_id = $objectiveId
            operator_id = 'pester-operator'
            state = 'satisfied'
            duration_minutes = 15
            validation_harness = 'multi_objective_compare'
        }

        $satisfiedPayload.ok | Should Be $true
        [bool]$satisfiedPayload.commitment.is_terminal | Should Be $true
        [string]$satisfiedPayload.commitment.terminal_state | Should Be 'satisfied'
        [string]$satisfiedPayload.commitment.terminal_detail | Should Not BeNullOrEmpty

        $historyPayload = Invoke-TodJsonGet -Path ("/api/operator-chat-commitments?limit=6&preview_id={0}&validation_harness=multi_objective_compare" -f [uri]::EscapeDataString($previewId))
        $historyPayload.ok | Should Be $true
        @($historyPayload.entries).Count | Should BeGreaterThan 1

        $satisfiedEntry = @($historyPayload.entries | Where-Object { [string]$_.state -eq 'satisfied' } | Select-Object -First 1)
        $supersededEntry = @($historyPayload.entries | Where-Object { [string]$_.state -eq 'committed' } | Select-Object -First 1)
        @($satisfiedEntry).Count | Should Be 1
        @($supersededEntry).Count | Should Be 1

        [string]$satisfiedEntry[0].lifecycle_status | Should Be 'satisfied'
        [string]$satisfiedEntry[0].terminal_state | Should Be 'satisfied'
        [bool]$satisfiedEntry[0].is_terminal | Should Be $true
        [string]$supersededEntry[0].lifecycle_status | Should Be 'superseded'
        [string]$supersededEntry[0].terminal_state | Should Be 'superseded'
        [bool]$supersededEntry[0].is_terminal | Should Be $true
        [bool]$supersededEntry[0].active | Should Be $false
        [string]$supersededEntry[0].terminal_successor_commitment_id | Should Be ([string]$satisfiedPayload.commitment.commitment_id)
        [string]$supersededEntry[0].terminal_detail | Should Not BeNullOrEmpty

    }

    It 'derives ineffective after repeated abandoned outcomes for the same action pattern' {
        if (-not (Test-TodUiReachable)) {
            return
        }

        $statusPayload = Invoke-TodJsonGet -Path '/api/project-status?validation_harness=multi_objective_compare'
        $objectiveId = [string]$statusPayload.selected_objective_id
        if ([string]::IsNullOrWhiteSpace($objectiveId)) {
            return
        }

        $chatPayload = Invoke-TodJsonPost -Path '/api/operator-chat' -Body @{
            query = 'What should I do next?'
            intent = 'suggest_next_action'
            window_minutes = 10
            objective_id = $objectiveId
            validation_harness = 'multi_objective_compare'
        }

        $suggestedAction = Get-TodCommittableSuggestedAction -SuggestedActions @($chatPayload.response.suggested_actions)
        if ($null -eq $suggestedAction) {
            return
        }

        $previewIntent = if ($suggestedAction.PSObject.Properties['intent']) { [string]$suggestedAction.intent } else { 'suggest_next_action' }
        $actionName = [string]$suggestedAction.action
        $actionReason = [string]$suggestedAction.reason
        $actionMode = [string]$suggestedAction.mode

        $previewPayload1 = Invoke-TodJsonPost -Path '/api/operator-chat-action' -Body @{
            phase = 'preview'
            action = $actionName
            intent = $previewIntent
            objective_id = $objectiveId
            query = 'What should I do next?'
            window_minutes = 10
            operator_id = 'pester-operator'
            suggested_reason = $actionReason
            mode = $actionMode
        }

        $previewId1 = [string]$previewPayload1.preview_id
        $previewId1 | Should Not BeNullOrEmpty

        $committedPayload1 = Invoke-TodJsonPost -Path '/api/operator-chat-commitment' -Body @{
            preview_id = $previewId1
            objective_id = $objectiveId
            operator_id = 'pester-operator'
            state = 'committed'
            duration_minutes = 15
            validation_harness = 'multi_objective_compare'
        }

        $committedPayload1.ok | Should Be $true

        $abandonedPayload1 = Invoke-TodJsonPost -Path '/api/operator-chat-commitment' -Body @{
            preview_id = $previewId1
            objective_id = $objectiveId
            operator_id = 'pester-operator'
            state = 'abandoned'
            duration_minutes = 15
            validation_harness = 'multi_objective_compare'
        }

        $abandonedPayload1.ok | Should Be $true
        [string]$abandonedPayload1.commitment.terminal_state | Should Be 'abandoned'

        $previewPayload2 = Invoke-TodJsonPost -Path '/api/operator-chat-action' -Body @{
            phase = 'preview'
            action = $actionName
            intent = $previewIntent
            objective_id = $objectiveId
            query = 'What should I do next?'
            window_minutes = 10
            operator_id = 'pester-operator'
            suggested_reason = $actionReason
            mode = $actionMode
        }

        $previewId2 = [string]$previewPayload2.preview_id
        $previewId2 | Should Not BeNullOrEmpty

        $committedPayload2 = Invoke-TodJsonPost -Path '/api/operator-chat-commitment' -Body @{
            preview_id = $previewId2
            objective_id = $objectiveId
            operator_id = 'pester-operator'
            state = 'committed'
            duration_minutes = 15
            validation_harness = 'multi_objective_compare'
        }

        $committedPayload2.ok | Should Be $true

        $abandonedPayload2 = Invoke-TodJsonPost -Path '/api/operator-chat-commitment' -Body @{
            preview_id = $previewId2
            objective_id = $objectiveId
            operator_id = 'pester-operator'
            state = 'abandoned'
            duration_minutes = 15
            validation_harness = 'multi_objective_compare'
        }

        $abandonedPayload2.ok | Should Be $true
        [bool]$abandonedPayload2.commitment.is_terminal | Should Be $true
        [string]$abandonedPayload2.commitment.lifecycle_status | Should Be 'ineffective'
        [string]$abandonedPayload2.commitment.terminal_state | Should Be 'ineffective'
        [string]$abandonedPayload2.commitment.terminal_detail | Should Not BeNullOrEmpty
        (($abandonedPayload2.commitment.PSObject.Properties.Name) -contains 'terminal_history') | Should Be $true
        [bool]$abandonedPayload2.commitment.terminal_history.ineffective_signal | Should Be $true
        [string]$abandonedPayload2.commitment.terminal_history.recent_terminal_state | Should Be 'ineffective'

        $historyPayload = Invoke-TodJsonGet -Path ("/api/operator-chat-commitments?limit=6&preview_id={0}&validation_harness=multi_objective_compare" -f [uri]::EscapeDataString($previewId2))
        $historyPayload.ok | Should Be $true
        @($historyPayload.entries).Count | Should BeGreaterThan 1

        $ineffectiveEntry = @($historyPayload.entries | Where-Object { [string]$_.state -eq 'abandoned' } | Select-Object -First 1)
        @($ineffectiveEntry).Count | Should Be 1
        [string]$ineffectiveEntry[0].lifecycle_status | Should Be 'ineffective'
        [string]$ineffectiveEntry[0].terminal_state | Should Be 'ineffective'

        $followupChat = Invoke-TodJsonPost -Path '/api/operator-chat' -Body @{
            query = 'What should I do next?'
            intent = 'suggest_next_action'
            window_minutes = 10
            objective_id = $objectiveId
            validation_harness = 'multi_objective_compare'
        }

        [string]($followupChat.response.flags -join '|') | Should Match 'operator_commitment_ineffective'
        [string]$followupChat.response.suggested_actions[0].action | Should Be 'refresh-governance-snapshot'
    }
}