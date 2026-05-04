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
}