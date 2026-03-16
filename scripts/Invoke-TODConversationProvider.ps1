param(
    [ValidateSet('status', 'chat')]
    [string]$Action = 'status',
    [string]$ConfigPath = 'tod/config/voice-adapter.json',
    [string]$Prompt = '',
    [string]$ObjectiveSummary = '',
    [string]$TaskState = '',
    [string]$ObjectiveId = '',
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot

function Get-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) { return $PathValue }
    return (Join-Path $repoRoot $PathValue)
}

function Get-ReplyTextFromResponse {
    param($Response)

    if ($Response -and $Response.PSObject.Properties['choices'] -and @($Response.choices).Count -gt 0) {
        $choice = $Response.choices[0]
        if ($choice.message -and $choice.message.PSObject.Properties['content']) {
            if ($choice.message.content -is [string]) {
                return ([string]$choice.message.content).Trim()
            }
            if ($choice.message.content -is [System.Array]) {
                $parts = @()
                foreach ($part in $choice.message.content) {
                    if ($part -and $part.PSObject.Properties['text'] -and -not [string]::IsNullOrWhiteSpace([string]$part.text)) {
                        $parts += [string]$part.text
                    }
                }
                return (($parts -join ' ').Trim())
            }
        }
    }

    return ''
}

$cfgAbs = Get-LocalPath -PathValue $ConfigPath
if (-not (Test-Path -Path $cfgAbs)) {
    throw "Voice adapter config not found: $cfgAbs"
}

$config = Get-Content -Path $cfgAbs -Raw | ConvertFrom-Json
$conversation = if ($config.PSObject.Properties['conversation']) { $config.conversation } else { $null }

if ($null -eq $conversation) {
    throw 'conversation config not found in voice-adapter.json'
}

$provider = if ($conversation.PSObject.Properties['provider']) { [string]$conversation.provider } else { 'builtin' }
$local = if ($conversation.PSObject.Properties['local']) { $conversation.local } else { $null }
$helpersAllowed = if ($conversation.PSObject.Properties['allow_third_party_helpers']) { [bool]$conversation.allow_third_party_helpers } else { $false }
$fallback = if ($conversation.PSObject.Properties['fallback_to_builtin']) { [bool]$conversation.fallback_to_builtin } else { $true }

$endpoint = if ($local -and $local.PSObject.Properties['endpoint']) { [string]$local.endpoint } else { '' }
$model = if ($local -and $local.PSObject.Properties['model']) { [string]$local.model } else { '' }
$temperature = if ($local -and $local.PSObject.Properties['temperature']) { [double]$local.temperature } else { 0.35 }
$timeoutSec = if ($local -and $local.PSObject.Properties['timeout_sec']) { [int]$local.timeout_sec } else { 20 }
$maxTokens = if ($local -and $local.PSObject.Properties['max_tokens']) { [int]$local.max_tokens } else { 220 }
$apiKeyEnv = if ($local -and $local.PSObject.Properties['api_key_env']) { [string]$local.api_key_env } else { '' }
$apiKey = if ([string]::IsNullOrWhiteSpace($apiKeyEnv)) { '' } else { [Environment]::GetEnvironmentVariable($apiKeyEnv) }

switch ($Action) {
    'status' {
        $reachable = $false
        $errorText = ''
        if (-not [string]::IsNullOrWhiteSpace($endpoint)) {
            try {
                $probeBody = [ordered]@{
                    model = $model
                    temperature = 0
                    max_tokens = 8
                    messages = @(
                        [ordered]@{ role = 'system'; content = 'Reply with the single word ok.' },
                        [ordered]@{ role = 'user'; content = 'ok' }
                    )
                }
                $headers = @{ 'Content-Type' = 'application/json' }
                if (-not [string]::IsNullOrWhiteSpace($apiKey)) {
                    $headers['Authorization'] = "Bearer $apiKey"
                }
                $null = Invoke-RestMethod -Uri $endpoint -Method Post -TimeoutSec ([Math]::Min($timeoutSec, 6)) -Headers $headers -Body ($probeBody | ConvertTo-Json -Depth 8)
                $reachable = $true
            }
            catch {
                $errorText = $_.Exception.Message
            }
        }

        $payload = [pscustomobject]@{
            ok = $true
            provider = $provider
            local_enabled = ($null -ne $local) -and ((-not $local.PSObject.Properties['enabled']) -or [bool]$local.enabled)
            allow_third_party_helpers = $helpersAllowed
            fallback_to_builtin = $fallback
            endpoint = $endpoint
            model = $model
            reachable = $reachable
            error = $errorText
        }
        if ($AsJson) { $payload | ConvertTo-Json -Depth 8 } else { $payload }
        return
    }
    'chat' {
        if ([string]::IsNullOrWhiteSpace($Prompt)) {
            throw 'Prompt is required for chat action'
        }
        if ([string]::IsNullOrWhiteSpace($endpoint)) {
            throw 'Local conversation endpoint is not configured'
        }
        if ([string]::IsNullOrWhiteSpace($model)) {
            throw 'Local conversation model is not configured'
        }

        $systemPrompt = @"
You are TOD, a conversational coding assistant speaking directly with your operator.
Answer in natural first-person language.
When the question is about current work, use the supplied project context and speak as a collaborator.
Keep responses concise and useful.
"@
        $contextPrompt = @"
Current project context:
- Objective ID: $ObjectiveId
- Task state: $TaskState
- Summary: $ObjectiveSummary
"@

        $bodyObject = [ordered]@{
            model = $model
            temperature = $temperature
            max_tokens = $maxTokens
            messages = @(
                [ordered]@{ role = 'system'; content = $systemPrompt },
                [ordered]@{ role = 'system'; content = $contextPrompt },
                [ordered]@{ role = 'user'; content = [string]$Prompt }
            )
        }

        $headers = @{ 'Content-Type' = 'application/json' }
        if (-not [string]::IsNullOrWhiteSpace($apiKey)) {
            $headers['Authorization'] = "Bearer $apiKey"
        }
        $response = Invoke-RestMethod -Uri $endpoint -Method Post -TimeoutSec $timeoutSec -Headers $headers -Body ($bodyObject | ConvertTo-Json -Depth 10)
        $replyText = Get-ReplyTextFromResponse -Response $response
        if ([string]::IsNullOrWhiteSpace($replyText)) {
            throw 'Local conversation provider returned no reply text'
        }

        $payload = [pscustomobject]@{
            ok = $true
            provider = 'local'
            model = $model
            reply_text = $replyText
        }
        if ($AsJson) { $payload | ConvertTo-Json -Depth 8 } else { $payload }
        return
    }
}