Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$uiScript = Join-Path $repoRoot 'scripts/Start-TOD-UI.ps1'

function Import-UiRouteFunction {
    param([Parameter(Mandatory = $true)][string]$Name)

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($uiScript, [ref]$tokens, [ref]$errors)
    if (@($errors).Count -gt 0) {
        throw "Failed to parse $uiScript"
    }

    $fnAst = $ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name
    }, $true)

    if ($null -eq $fnAst) {
        throw "Function '$Name' not found in $uiScript"
    }

    $definition = $fnAst.Extent.Text -replace ("function\s+{0}\b" -f [regex]::Escape($Name)), ("function global:{0}" -f $Name)
    . ([scriptblock]::Create($definition))
}

Describe 'TOD UI conversation route backend' {
    BeforeAll {
        Import-UiRouteFunction -Name 'Invoke-TodConversationReplyRequest'
        Import-UiRouteFunction -Name 'Read-JsonFileIfExists'
        Import-UiRouteFunction -Name 'Write-JsonArtifact'
        Import-UiRouteFunction -Name 'Get-ActivityTimestampText'
        Import-UiRouteFunction -Name 'Get-ActivityTimestampTicks'
        Import-UiRouteFunction -Name 'Get-FilteredActivityEvents'
        Import-UiRouteFunction -Name 'New-ActivityStreamCandidatePayload'
        Import-UiRouteFunction -Name 'Get-StateActivityFallbackPayload'
        Import-UiRouteFunction -Name 'Update-DirectChatActivityStream'
        Import-UiRouteFunction -Name 'Get-ActivityStreamPayload'
    }

    It 'requires a non-empty query' {
        { Invoke-TodConversationReplyRequest -Query '' } | Should Throw 'query is required'
    }

    It 'parses JSON returned by the conversation reply script' {
        $script:conversationReplyScript = Join-Path $repoRoot ('tod/out/tests/fake-conversation-' + [guid]::NewGuid().ToString('N') + '.ps1')
        @'
param(
    [string]$Query,
    [string]$ObjectiveId,
    [string]$OperatorName,
    [string]$ConversationHistoryJson,
    [int]$WindowMinutes,
    [switch]$AsJson
)

[pscustomobject]@{
    ok = $true
    reply_text = "reply for $Query"
    source = 'test'
    operator = [pscustomobject]@{ operator_name = $OperatorName; turn_count = 2 }
    initiative = [pscustomobject]@{ objective_id = '152'; active_task = 'simulate'; next_action = 'continue' ; blocker = '' }
    current_work = [pscustomobject]@{ objective_id = '152'; active_task = 'simulate'; next_action = 'continue'; blocker = '' }
    conversation_memory = [pscustomobject]@{ turn_count = 2 }
} | ConvertTo-Json -Depth 10
'@ | Set-Content -Path $script:conversationReplyScript

        $payload = Invoke-TodConversationReplyRequest -Query 'what now' -OperatorName 'Dave' -ConversationHistoryJson '[]' -WindowMinutes 10

        [bool]$payload.ok | Should Be $true
        [string]$payload.reply_text | Should Be 'reply for what now'
        [string]$payload.operator.operator_name | Should Be 'Dave'
    }

    It 'returns scoped direct-chat activity with local completion and published result events' {
        $artifactRoot = Join-Path $repoRoot ('tod/out/tests/ui-direct-chat-activity-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null

        try {
            $script:directChatActivityStreamPath = Join-Path $artifactRoot 'tod_direct_chat_activity_stream.latest.json'
            $script:activityStreamPrimaryPath = Join-Path $artifactRoot 'TOD_ACTIVITY_STREAM.latest.json'
            $script:activityStreamMirrorPath = Join-Path $artifactRoot 'TOD_ACTIVITY_STREAM.mirror.latest.json'
            $script:statePath = Join-Path $artifactRoot 'tod-state.json'
            $script:todActivityStreamBuildId = 'fresh-direct-chat-activity-v1'

            $replyPayload = [pscustomobject]@{
                generated_at = '2026-05-05T23:30:00Z'
                command_dispatch = [pscustomobject]@{
                    created = $true
                    task_id = 'TSKCHAT-SMOKE-PASS'
                    objective_id = 'objective-direct-chat-smoke'
                    request_id = 'REQ-SMOKE-PASS'
                    correlation_id = 'CORR-SMOKE-PASS'
                    title = 'Run direct-chat local executor smoke task'
                    detail = 'executor local'
                    payload = [pscustomobject]@{
                        activity_event_types = @('local_executor_invoked', 'local_executor_completed', 'result_published')
                        run_task = [pscustomobject]@{
                            decision = 'pass'
                            summary = 'Local smoke task completed and published bounded result evidence.'
                        }
                    }
                }
            }

            Update-DirectChatActivityStream -ReplyPayload $replyPayload | Out-Null
            $scoped = Get-ActivityStreamPayload -TaskId 'TSKCHAT-SMOKE-PASS' -Limit 20
            $events = @($scoped.events | ForEach-Object { [string]$_.event_type })

            [string]$scoped.task_id | Should Be 'TSKCHAT-SMOKE-PASS'
            [string]$scoped.source_path | Should Be $script:directChatActivityStreamPath
            [string]$scoped.tod_activity_stream_build_id | Should Be 'fresh-direct-chat-activity-v1'
            ($events -contains 'chat_task_created') | Should Be $true
            ($events -contains 'local_executor_invoked') | Should Be $true
            ($events -contains 'local_executor_completed') | Should Be $true
            ($events -contains 'validation_passed') | Should Be $true
            ($events -contains 'result_published') | Should Be $true
        }
        finally {
            if (Test-Path -Path $artifactRoot) {
                Remove-Item -Path $artifactRoot -Recurse -Force
            }
        }
    }
}