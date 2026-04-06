Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$baseUrl = 'http://localhost:8844'

function Invoke-TodJsonGet {
    param([Parameter(Mandatory = $true)][string]$Path)

    $response = Invoke-WebRequest -UseBasicParsing -Uri ("$baseUrl$Path") -TimeoutSec 90
    return ($response.Content | ConvertFrom-Json)
}

function Invoke-TodJsonPost {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Body
    )

    $json = $Body | ConvertTo-Json -Depth 8
    $response = Invoke-WebRequest -UseBasicParsing -Uri ("$baseUrl$Path") -Method Post -ContentType 'application/json' -Body $json -TimeoutSec 90
    return ($response.Content | ConvertFrom-Json)
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

function Test-TodUiReachable {
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri "$baseUrl/api/project-status" -TimeoutSec 5
        return $response.StatusCode -eq 200
    }
    catch {
        return $false
    }
}

Describe 'Operator chat trust-chain endpoint' {
    It 'returns comparison metadata that includes the active validation harness' {
        if (-not (Test-TodUiReachable)) {
            return
        }

        $auditPayload = Invoke-TodJsonGet -Path '/api/operator-chat-action-audit?limit=1'
        if (@($auditPayload.entries).Count -eq 0) {
            return
        }

        $auditId = [string]$auditPayload.entries[0].audit_id
        $payload = Invoke-TodJsonGet -Path ("/api/operator-chat-action-trust-chain?audit_id={0}&validation_harness=multi_objective_compare" -f [uri]::EscapeDataString($auditId))

        $payload.ok | Should Be $true
        $payload.comparison | Should Not BeNullOrEmpty
        [string]$payload.comparison.validation_harness | Should Be 'multi_objective_compare'
        [string]$payload.comparison.validation_harness_label | Should Not BeNullOrEmpty
        (($payload.PSObject.Properties.Name) -contains 'proposal_closure') | Should Be $true
    }

    It 'returns evidence delta fields for commitment-targeted trust-chain inspection when available' {
        if (-not (Test-TodUiReachable)) {
            return
        }

        $commitmentPayload = Invoke-TodJsonGet -Path '/api/operator-chat-commitments?limit=8&validation_harness=multi_objective_compare'
        $entry = @($commitmentPayload.entries | Where-Object { [string]$_.release_condition -eq 'evidence_change' } | Select-Object -First 1)
        if (@($entry).Count -eq 0) {
            return
        }

        $commitmentId = [string]$entry[0].commitment_id
        $payload = Invoke-TodJsonGet -Path ("/api/operator-chat-action-trust-chain?commitment_id={0}&validation_harness=multi_objective_compare" -f [uri]::EscapeDataString($commitmentId))

        $payload.ok | Should Be $true
        (($payload.PSObject.Properties.Name) -contains 'evidence_delta_count') | Should Be $true
        $payload.commitments | Should Not BeNullOrEmpty
        [int]$payload.evidence_delta_count | Should BeGreaterThan 0
        (($payload.commitments[0].PSObject.Properties.Name) -contains 'scope_kind') | Should Be $true
        (($payload.commitments[0].PSObject.Properties.Name) -contains 'current_scope_kind') | Should Be $true
        (($payload.commitments[0].PSObject.Properties.Name) -contains 'scope_conflict_resolution') | Should Be $true
        (($payload.commitments[0].PSObject.Properties.Name) -contains 'scope_influence_summary') | Should Be $true
        (($payload.commitments[0].PSObject.Properties.Name) -contains 'is_terminal') | Should Be $true
        (($payload.commitments[0].PSObject.Properties.Name) -contains 'terminal_state') | Should Be $true
        (($payload.commitments[0].PSObject.Properties.Name) -contains 'terminal_detail') | Should Be $true
        [string]$payload.commitments[0].scope_kind | Should Match 'proposal_specific|objective_wide'
        [string]$payload.commitments[0].scope_conflict_resolution | Should Match 'active|downgrade|block'
        [string]$payload.commitments[0].terminal_state | Should Match '^$|satisfied|abandoned|superseded|ineffective'
        [string]$payload.commitments[0].scope_influence_summary | Should Not BeNullOrEmpty
    }

    It 'projects ineffective terminal state through commitment-targeted trust-chain inspection' {
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
        $actionName = [string]$suggestedAction.action
        $actionReason = [string]$suggestedAction.reason
        $actionMode = [string]$suggestedAction.mode

        foreach ($cycle in @(1, 2)) {
            $previewPayload = Invoke-TodJsonPost -Path '/api/operator-chat-action' -Body @{
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

            $abandonedPayload = Invoke-TodJsonPost -Path '/api/operator-chat-commitment' -Body @{
                preview_id = $previewId
                objective_id = $objectiveId
                operator_id = 'pester-operator'
                state = 'abandoned'
                duration_minutes = 15
                validation_harness = 'multi_objective_compare'
            }

            $abandonedPayload.ok | Should Be $true
        }

        $commitmentPayload = Invoke-TodJsonGet -Path ("/api/operator-chat-commitments?limit=8&objective_id={0}&validation_harness=multi_objective_compare" -f [uri]::EscapeDataString($objectiveId))
        $ineffectiveEntry = @($commitmentPayload.entries | Where-Object { [string]$_.terminal_state -eq 'ineffective' } | Select-Object -First 1)
        @($ineffectiveEntry).Count | Should Be 1

        $payload = Invoke-TodJsonGet -Path ("/api/operator-chat-action-trust-chain?commitment_id={0}&validation_harness=multi_objective_compare" -f [uri]::EscapeDataString([string]$ineffectiveEntry[0].commitment_id))

        $payload.ok | Should Be $true
        $payload.commitments | Should Not BeNullOrEmpty
        [string]$payload.commitments[0].lifecycle_status | Should Be 'ineffective'
        [string]$payload.commitments[0].terminal_state | Should Be 'ineffective'
        [string]$payload.commitments[0].terminal_detail | Should Not BeNullOrEmpty
    }
}