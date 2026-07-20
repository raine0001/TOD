Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$listenerScript = Join-Path $repoRoot 'scripts/Start-TODMimPacketListener.ps1'

function Import-FunctionFromFile {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($FilePath, [ref]$tokens, [ref]$errors)
    if (@($errors).Count -gt 0) {
        throw "Failed to parse $FilePath"
    }

    $fnAst = $ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name
    }, $true)

    if ($null -eq $fnAst) {
        throw "Function '$Name' not found in $FilePath"
    }

    $definition = $fnAst.Extent.Text -replace ("function\s+{0}\b" -f [regex]::Escape($Name)), ("function global:{0}" -f $Name)
    . ([scriptblock]::Create($definition))
}

function New-MockConversationProviderScript {
    param([Parameter(Mandatory = $true)][string]$ReplyText)

    $scriptPath = Join-Path $repoRoot ('tod/out/tests/mock-conversation-provider-' + [guid]::NewGuid().ToString('N') + '.ps1')
    $escapedReplyText = $ReplyText.Replace("'", "''")
    $scriptContent = @'
param(
    [string]$Action,
    [string]$Prompt,
    [string]$ObjectiveSummary,
    [string]$TaskState,
    [string]$ObjectiveId,
    [switch]$AsJson
)

@{
    ok = $true
    reply_text = '__REPLY_TEXT__'
} | ConvertTo-Json -Depth 5
'@
    $scriptContent = $scriptContent.Replace('__REPLY_TEXT__', $escapedReplyText)

    $dir = Split-Path -Parent $scriptPath
    if (-not (Test-Path -Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($scriptPath, ($scriptContent -replace "`r`n", "`n"), $utf8NoBom)
    return $scriptPath
}

Describe 'TOD MIM task troubleshooting' {
    BeforeAll {
        Import-FunctionFromFile -FilePath $listenerScript -Name 'Invoke-TaskTroubleshootingGuidance'
        Import-FunctionFromFile -FilePath $listenerScript -Name 'Publish-TaskTroubleshootingRequest'
    }

    It 'falls back to deterministic troubleshooting guidance when the provider is unavailable' {
        $guidance = Invoke-TaskTroubleshootingGuidance -ConversationProviderScriptAbs (Join-Path $repoRoot 'scripts/missing-provider.ps1') -RequestId 'objective-401-task-001' -ObjectiveId '401' -TaskId 'objective-401-task-001' -CorrelationId 'corr-401' -Action 'run-bridge-request' -Execution ([pscustomobject]@{
                ok = $false
                blocked = $false
                execution_mode = 'direct_script_exception'
                error = 'bridge dispatch failed'
                execution_readiness = [pscustomobject]@{ status = 'fresh' }
                output = 'exception output'
            }) -DecisionPayload ([pscustomobject]@{
                decision_outcome = 'execute'
                reason_code = 'authorized_routine_request'
                next_step_recommendation = 'execute_now'
            }) -ReviewGate ([pscustomobject]@{ passed = $true }) -ValidatorResult ([pscustomobject]@{ passed = $true }) -IntegrationStatus ([pscustomobject]@{
                objective_alignment = [pscustomobject]@{ status = 'aligned' }
            })

        [string]$guidance.result_status | Should Be 'failed'
        [bool]$guidance.provider_status.used | Should Be $false
        [string]$guidance.provider_status.source | Should Be 'deterministic_fallback'
        [string]$guidance.guidance_text | Should Match 'Inspect the execution mode'
        [string]$guidance.recommended_report_back | Should Be 'execute_now'
    }

    It 'uses the local conversation provider when troubleshooting guidance is available' {
        $providerScript = New-MockConversationProviderScript -ReplyText 'Likely cause: validator drift. 1. Re-check the validator input. 2. Repair the contract payload. 3. Re-run the bounded task. 4. Report the repaired validator state back to MIM.'
        try {
            $guidance = Invoke-TaskTroubleshootingGuidance -ConversationProviderScriptAbs $providerScript -RequestId 'objective-402-task-001' -ObjectiveId '402' -TaskId 'objective-402-task-001' -CorrelationId 'corr-402' -Action 'run-bridge-request' -Execution ([pscustomobject]@{
                    ok = $false
                    blocked = $true
                    execution_mode = 'readiness_blocked'
                    error = 'execution blocked'
                    execution_readiness = [pscustomobject]@{ status = 'stale' }
                    output = 'blocked output'
                }) -DecisionPayload ([pscustomobject]@{
                    decision_outcome = 'execute'
                    reason_code = 'authorized_routine_request'
                    next_step_recommendation = 'refresh_execution_readiness'
                }) -ReviewGate ([pscustomobject]@{ passed = $true }) -ValidatorResult ([pscustomobject]@{ passed = $true }) -IntegrationStatus ([pscustomobject]@{
                    objective_alignment = [pscustomobject]@{ status = 'aligned' }
                })

            [string]$guidance.result_status | Should Be 'blocked'
            [bool]$guidance.provider_status.used | Should Be $true
            [string]$guidance.provider_status.source | Should Be 'local_conversation_provider'
            [string]$guidance.guidance_text | Should Match 'validator drift'
            [string]$guidance.provider_status.detail | Should Match 'OpenAI-compatible local conversation provider'
        }
        finally {
            if (-not [string]::IsNullOrWhiteSpace($providerScript) -and (Test-Path -Path $providerScript)) {
                Remove-Item -Path $providerScript -Force
            }
        }
    }

    It 'bypasses provider guidance for malformed bounded edit packets' {
        $providerScript = New-MockConversationProviderScript -ReplyText 'Restore the task to the active lane and execute now.'
        try {
            $guidance = Invoke-TaskTroubleshootingGuidance -ConversationProviderScriptAbs $providerScript -RequestId 'objective-404-task-001' -ObjectiveId '404' -TaskId 'objective-404-task-001' -CorrelationId 'corr-404' -Action 'execute-chat-task' -Execution ([pscustomobject]@{
                    ok = $true
                    blocked = $true
                    execution_mode = 'direct_script_success'
                    error = 'TOD intake arbitration stored the request as rejected_before_active_lane; active task identity was preserved.'
                    result_reason_code = 'malformed_bounded_edit_packet'
                    execution_readiness = [pscustomobject]@{ status = 'stale' }
                    output = 'rejected_before_active_lane'
                }) -DecisionPayload ([pscustomobject]@{
                    decision_outcome = 'execute'
                    reason_code = 'authorized_routine_request'
                    next_step_recommendation = 'execute_now'
                }) -ReviewGate ([pscustomobject]@{ passed = $true }) -ValidatorResult ([pscustomobject]@{ passed = $true }) -IntegrationStatus ([pscustomobject]@{
                    objective_alignment = [pscustomobject]@{ status = 'aligned' }
                })

            [string]$guidance.result_status | Should Be 'blocked'
            [bool]$guidance.provider_status.used | Should Be $false
            [string]$guidance.provider_status.source | Should Be 'deterministic_fallback'
            [string]$guidance.provider_status.detail | Should Match 'Provider bypassed'
            [string]$guidance.guidance_text | Should Match 'corrected bounded edit packet'
            [string]$guidance.guidance_text | Should Not Match 'Restore the task'
            [string]$guidance.recommended_report_back | Should Be 'return_to_originating_authority_for_replan'
        }
        finally {
            if (-not [string]::IsNullOrWhiteSpace($providerScript) -and (Test-Path -Path $providerScript)) {
                Remove-Item -Path $providerScript -Force
            }
        }
    }

    It 'opens a troubleshooting handoff request for blocked or failed work' {
        $script:capturedDialogCall = $null
        function global:Invoke-DialogNotice {
            param(
                [string]$ScriptAbs,
                [string]$Action,
                [string]$SessionId,
                [string]$MessageType,
                [string]$Intent,
                [string]$Summary,
                $Payload,
                [string]$TaskId,
                [string]$CorrelationId,
                [string]$EnvPath,
                [switch]$PublishRemote
            )

            $script:capturedDialogCall = [pscustomobject]@{
                ScriptAbs = $ScriptAbs
                Action = $Action
                SessionId = $SessionId
                MessageType = $MessageType
                Intent = $Intent
                Summary = $Summary
                Payload = $Payload
                TaskId = $TaskId
                CorrelationId = $CorrelationId
                EnvPath = $EnvPath
                PublishRemote = [bool]$PublishRemote
            }

            return [pscustomobject]@{ ok = $true; status = 'sent' }
        }

        $request = Publish-TaskTroubleshootingRequest -DialogScriptAbs $listenerScript -EnvPath (Join-Path $repoRoot '.env') -RequestId 'objective-403-task-001' -ObjectiveId '403' -TaskId 'objective-403-task-001' -CorrelationId 'corr-403' -Troubleshooting ([pscustomobject]@{
                likely_cause = 'Validator rejected the result packet.'
                guidance_text = 'Repair the packet and re-run validation.'
            }) -Execution ([pscustomobject]@{
                ok = $false
                blocked = $false
                action = 'run-bridge-request'
                execution_mode = 'direct_script_exception'
                error = 'validator_failed'
            }) -DecisionPayload ([pscustomobject]@{
                decision_outcome = 'execute'
                reason_code = 'authorized_routine_request'
                next_step_recommendation = 'repair_validator_then_retry'
            }) -PublishRemote

        [bool]$request.ok | Should Be $true
        [string]$request.status | Should Be 'sent'
        [string]$request.message_type | Should Be 'handoff_request'
        [string]$request.intent | Should Be 'task_troubleshooting'
        [string]$request.session_id | Should Match 'tod-troubleshoot-objective-403-task-001'
        [string]$script:capturedDialogCall.MessageType | Should Be 'handoff_request'
        [string]$script:capturedDialogCall.Intent | Should Be 'task_troubleshooting'
        [string]$script:capturedDialogCall.TaskId | Should Be 'objective-403-task-001'
        [string]$script:capturedDialogCall.CorrelationId | Should Be 'corr-403'
        [bool]$script:capturedDialogCall.PublishRemote | Should Be $true
        [string]$script:capturedDialogCall.Payload.troubleshooting.guidance_text | Should Match 'Repair the packet'
    }
}
