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

Describe 'Operator chat MIM proposal ingestion' {
    It 'returns a shaped MIM proposal in project status when a live listener request is available' {
        if (-not (Test-TodUiReachable)) {
            return
        }

        $payload = Invoke-TodJsonGet -Path '/api/project-status'
        if (-not $payload.PSObject.Properties['mim_proposal'] -or -not $payload.mim_proposal -or -not [bool]$payload.mim_proposal.available) {
            return
        }

        $payload.ok | Should Be $true
        [bool]$payload.mim_proposal.available | Should Be $true
        [string]$payload.mim_proposal.source | Should Be 'mim_listener_task_request'
        [string]$payload.mim_proposal.task_id | Should Not BeNullOrEmpty
        [string]$payload.mim_proposal.title | Should Not BeNullOrEmpty
        [int]$payload.mim_proposal.acceptance_criteria_count | Should BeGreaterThan -1
        [int]$payload.mim_proposal.constraints_count | Should BeGreaterThan -1
        $payload.PSObject.Properties['mim_proposal_conflict'] | Should Not BeNullOrEmpty
        $payload.mim_proposal_conflict.PSObject.Properties['status'] | Should Not BeNullOrEmpty
        $payload.mim_proposal_conflict.PSObject.Properties['summary'] | Should Not BeNullOrEmpty
        $allowedStatuses = @('aligned', 'objective_scope_mismatch', 'bridge_alignment_mismatch', 'canonical_export_mismatch', 'insufficient_scope', 'none')
        if ($allowedStatuses -notcontains ([string]$payload.mim_proposal_conflict.status)) {
            throw ("Unexpected mim_proposal_conflict status: {0}" -f [string]$payload.mim_proposal_conflict.status)
        }
        $payload.PSObject.Properties['mim_proposal_arbitration'] | Should Not BeNullOrEmpty
        $payload.mim_proposal_arbitration.PSObject.Properties['status'] | Should Not BeNullOrEmpty
        $payload.mim_proposal_arbitration.PSObject.Properties['winner'] | Should Not BeNullOrEmpty
        $payload.mim_proposal_arbitration.PSObject.Properties['summary'] | Should Not BeNullOrEmpty
        $allowedArbitrationStatuses = @('none', 'observe_first', 'revalidate_scope_first', 'revalidate_tod_priority', 'proceed_with_mim_context')
        if ($allowedArbitrationStatuses -notcontains ([string]$payload.mim_proposal_arbitration.status)) {
            throw ("Unexpected mim_proposal_arbitration status: {0}" -f [string]$payload.mim_proposal_arbitration.status)
        }
        $payload.PSObject.Properties['mim_proposal_merge_policy'] | Should Not BeNullOrEmpty
        $payload.mim_proposal_merge_policy.PSObject.Properties['status'] | Should Not BeNullOrEmpty
        $payload.mim_proposal_merge_policy.PSObject.Properties['mode'] | Should Not BeNullOrEmpty
        $payload.mim_proposal_merge_policy.PSObject.Properties['summary'] | Should Not BeNullOrEmpty
        $allowedMergeStatuses = @('none', 'observe_first', 'merge_ready', 'merge_deferred')
        if ($allowedMergeStatuses -notcontains ([string]$payload.mim_proposal_merge_policy.status)) {
            throw ("Unexpected mim_proposal_merge_policy status: {0}" -f [string]$payload.mim_proposal_merge_policy.status)
        }
        $payload.PSObject.Properties['mim_proposal_acknowledgment'] | Should Not BeNullOrEmpty
        $payload.mim_proposal_acknowledgment.PSObject.Properties['status'] | Should Not BeNullOrEmpty
        $payload.mim_proposal_acknowledgment.PSObject.Properties['disposition'] | Should Not BeNullOrEmpty
        $payload.mim_proposal_acknowledgment.PSObject.Properties['summary'] | Should Not BeNullOrEmpty
        $allowedAcknowledgmentStatuses = @('none', 'pending_review', 'acknowledged_context', 'deferred', 'rejected')
        if ($allowedAcknowledgmentStatuses -notcontains ([string]$payload.mim_proposal_acknowledgment.status)) {
            throw ("Unexpected mim_proposal_acknowledgment status: {0}" -f [string]$payload.mim_proposal_acknowledgment.status)
        }
        $payload.PSObject.Properties['mim_proposal_closure'] | Should Not BeNullOrEmpty
        $payload.mim_proposal_closure.PSObject.Properties['status'] | Should Not BeNullOrEmpty
        $payload.mim_proposal_closure.PSObject.Properties['disposition'] | Should Not BeNullOrEmpty
        $payload.mim_proposal_closure.PSObject.Properties['summary'] | Should Not BeNullOrEmpty
        $allowedClosureStatuses = @('none', 'open', 'fulfilled', 'abandoned', 'superseded', 'withdrawn')
        if ($allowedClosureStatuses -notcontains ([string]$payload.mim_proposal_closure.status)) {
            throw ("Unexpected mim_proposal_closure status: {0}" -f [string]$payload.mim_proposal_closure.status)
        }
    }

    It 'surfaces MIM proposal context in operator chat suggested actions when available' {
        if (-not (Test-TodUiReachable)) {
            return
        }

        $statusPayload = Invoke-TodJsonGet -Path '/api/project-status'
        if (-not $statusPayload.PSObject.Properties['mim_proposal'] -or -not $statusPayload.mim_proposal -or -not [bool]$statusPayload.mim_proposal.available) {
            return
        }

        $payload = Invoke-TodJsonPost -Path '/api/operator-chat' -Body @{
            query = 'What should I do next?'
            intent = 'suggest_next_action'
            window_minutes = 10
        }

        $payload.ok | Should Be $true
        $responseFlags = @($payload.response.flags | ForEach-Object { [string]$_ })
        if ($responseFlags -notcontains 'mim_proposal_ingested') {
            throw ("Expected operator chat flags to include mim_proposal_ingested. Actual flags: {0}" -f ($responseFlags -join ', '))
        }
        $proposalAction = @($payload.response.suggested_actions | Where-Object { [string]$_.proposal_source -eq 'mim' } | Select-Object -First 1)
        if (@($proposalAction).Count -gt 0) {
            [string]$proposalAction[0].proposal_id | Should Not BeNullOrEmpty
            [string]$proposalAction[0].proposal_title | Should Not BeNullOrEmpty
            [string]$proposalAction[0].proposal_conflict_status | Should Not BeNullOrEmpty
            [string]$proposalAction[0].proposal_arbitration_status | Should Not BeNullOrEmpty
            [string]$proposalAction[0].proposal_arbitration_winner | Should Not BeNullOrEmpty
            [string]$proposalAction[0].proposal_merge_policy_status | Should Not BeNullOrEmpty
            [string]$proposalAction[0].proposal_merge_policy_mode | Should Not BeNullOrEmpty
            [string]$proposalAction[0].proposal_acknowledgment_status | Should Not BeNullOrEmpty
            [string]$proposalAction[0].proposal_acknowledgment_disposition | Should Not BeNullOrEmpty
            [string]$proposalAction[0].proposal_closure_status | Should Not BeNullOrEmpty
            [string]$proposalAction[0].proposal_closure_disposition | Should Not BeNullOrEmpty
        }

        if ($responseFlags -notcontains 'mim_proposal_arbitrated') {
            throw ("Expected operator chat flags to include mim_proposal_arbitrated. Actual flags: {0}" -f ($responseFlags -join ', '))
        }
        if ($responseFlags -notcontains 'mim_proposal_merge_policy_available') {
            throw ("Expected operator chat flags to include mim_proposal_merge_policy_available. Actual flags: {0}" -f ($responseFlags -join ', '))
        }
        if ($responseFlags -notcontains 'mim_proposal_acknowledged') {
            throw ("Expected operator chat flags to include mim_proposal_acknowledged. Actual flags: {0}" -f ($responseFlags -join ', '))
        }
        if ($responseFlags -notcontains 'mim_proposal_closure_available') {
            throw ("Expected operator chat flags to include mim_proposal_closure_available. Actual flags: {0}" -f ($responseFlags -join ', '))
        }

        if ([bool]$statusPayload.mim_proposal_conflict.conflict_detected) {
            if ($responseFlags -notcontains 'mim_proposal_conflict_detected') {
                throw ("Expected operator chat flags to include mim_proposal_conflict_detected. Actual flags: {0}" -f ($responseFlags -join ', '))
            }
            if (@($proposalAction).Count -gt 0) {
                [bool]$proposalAction[0].proposal_conflict_detected | Should Be $true
            }
            if ($responseFlags -notcontains 'mim_proposal_tod_priority') {
                throw ("Expected operator chat flags to include mim_proposal_tod_priority. Actual flags: {0}" -f ($responseFlags -join ', '))
            }
        }
        else {
            if (@($proposalAction).Count -gt 0) {
                [bool]$proposalAction[0].proposal_conflict_detected | Should Be $false
            }
            if ([string]$statusPayload.mim_proposal_arbitration.winner -eq 'shared' -and $responseFlags -notcontains 'mim_proposal_shared_priority') {
                throw ("Expected operator chat flags to include mim_proposal_shared_priority. Actual flags: {0}" -f ($responseFlags -join ', '))
            }
        }

        if ([string]$statusPayload.mim_proposal_merge_policy.status -eq 'merge_ready' -and $responseFlags -notcontains 'mim_proposal_merge_ready') {
            throw ("Expected operator chat flags to include mim_proposal_merge_ready. Actual flags: {0}" -f ($responseFlags -join ', '))
        }
        if ([string]$statusPayload.mim_proposal_merge_policy.status -eq 'merge_deferred' -and $responseFlags -notcontains 'mim_proposal_merge_deferred') {
            throw ("Expected operator chat flags to include mim_proposal_merge_deferred. Actual flags: {0}" -f ($responseFlags -join ', '))
        }
        if ([string]$statusPayload.mim_proposal_acknowledgment.disposition -eq 'absorbed' -and $responseFlags -notcontains 'mim_proposal_absorbed') {
            throw ("Expected operator chat flags to include mim_proposal_absorbed. Actual flags: {0}" -f ($responseFlags -join ', '))
        }
        if ([string]$statusPayload.mim_proposal_acknowledgment.disposition -eq 'deferred' -and $responseFlags -notcontains 'mim_proposal_ack_deferred') {
            throw ("Expected operator chat flags to include mim_proposal_ack_deferred. Actual flags: {0}" -f ($responseFlags -join ', '))
        }
        if ([string]$statusPayload.mim_proposal_acknowledgment.disposition -eq 'rejected' -and $responseFlags -notcontains 'mim_proposal_rejected') {
            throw ("Expected operator chat flags to include mim_proposal_rejected. Actual flags: {0}" -f ($responseFlags -join ', '))
        }
        if ([string]$statusPayload.mim_proposal_closure.disposition -eq 'open' -and $responseFlags -notcontains 'mim_proposal_open') {
            throw ("Expected operator chat flags to include mim_proposal_open. Actual flags: {0}" -f ($responseFlags -join ', '))
        }
        if ([string]$statusPayload.mim_proposal_closure.disposition -eq 'fulfilled' -and $responseFlags -notcontains 'mim_proposal_fulfilled') {
            throw ("Expected operator chat flags to include mim_proposal_fulfilled. Actual flags: {0}" -f ($responseFlags -join ', '))
        }
        if ([string]$statusPayload.mim_proposal_closure.disposition -eq 'abandoned' -and $responseFlags -notcontains 'mim_proposal_abandoned') {
            throw ("Expected operator chat flags to include mim_proposal_abandoned. Actual flags: {0}" -f ($responseFlags -join ', '))
        }
        if ([string]$statusPayload.mim_proposal_closure.disposition -eq 'superseded' -and $responseFlags -notcontains 'mim_proposal_superseded') {
            throw ("Expected operator chat flags to include mim_proposal_superseded. Actual flags: {0}" -f ($responseFlags -join ', '))
        }
        if ([string]$statusPayload.mim_proposal_closure.disposition -eq 'withdrawn' -and $responseFlags -notcontains 'mim_proposal_withdrawn') {
            throw ("Expected operator chat flags to include mim_proposal_withdrawn. Actual flags: {0}" -f ($responseFlags -join ', '))
        }
    }

    It 'projects proposal lifecycle into governed action audit when a proposal-backed preview is created' {
        if (-not (Test-TodUiReachable)) {
            return
        }

        $statusPayload = Invoke-TodJsonGet -Path '/api/project-status'
        if (-not $statusPayload.PSObject.Properties['mim_proposal'] -or -not $statusPayload.mim_proposal -or -not [bool]$statusPayload.mim_proposal.available) {
            return
        }

        $chatPayload = Invoke-TodJsonPost -Path '/api/operator-chat' -Body @{
            query = 'What should I do next?'
            intent = 'suggest_next_action'
            window_minutes = 10
        }

        $proposalAction = @($chatPayload.response.suggested_actions | Where-Object { [string]$_.proposal_source -eq 'mim' } | Select-Object -First 1)
        if (@($proposalAction).Count -eq 0) {
            return
        }

        $previewPayload = Invoke-TodJsonPost -Path '/api/operator-chat-action' -Body @{
            phase = 'preview'
            action = [string]$proposalAction[0].action
            intent = 'suggest_next_action'
            objective_id = [string]$statusPayload.selected_objective_id
            query = 'What should I do next?'
            window_minutes = 10
            operator_id = 'pester-operator'
            suggested_reason = [string]$proposalAction[0].reason
            mode = [string]$proposalAction[0].mode
        }

        $previewId = [string]$previewPayload.preview_id
        $previewId | Should Not BeNullOrEmpty

        $auditPayload = Invoke-TodJsonGet -Path ("/api/operator-chat-action-audit?preview_id={0}&limit=1" -f [uri]::EscapeDataString($previewId))
        $auditPayload.ok | Should Be $true
        $auditPayload.entries | Should Not BeNullOrEmpty
        [string]$auditPayload.entries[0].proposal_id | Should Be ([string]$statusPayload.mim_proposal.task_id)
        (($auditPayload.PSObject.Properties.Name) -contains 'proposal_lifecycle') | Should Be $true
        $auditPayload.proposal_lifecycle | Should Not BeNullOrEmpty
    }
}