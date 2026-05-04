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

function Test-TcpPortListening {
    param(
        [Parameter(Mandatory = $true)][string]$HostName,
        [Parameter(Mandatory = $true)][int]$Port,
        [int]$TimeoutMilliseconds = 800
    )

    $client = $null
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $async = $client.BeginConnect($HostName, $Port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMilliseconds, $false)) {
            return $false
        }
        $client.EndConnect($async) | Out-Null
        return $true
    }
    catch {
        return $false
    }
    finally {
        if ($client) {
            $client.Dispose()
        }
    }
}

function Get-ConversationEndpointListenerProcessIds {
    param(
        [Parameter(Mandatory = $true)][string]$HostName,
        [Parameter(Mandatory = $true)][int]$Port
    )

    $addresses = @($HostName)
    if ([string]::Equals($HostName, 'localhost', [System.StringComparison]::OrdinalIgnoreCase)) {
        $addresses += '127.0.0.1'
        $addresses += '::1'
    }
    elseif ([string]::Equals($HostName, '127.0.0.1', [System.StringComparison]::OrdinalIgnoreCase)) {
        $addresses += 'localhost'
        $addresses += '::1'
    }

    try {
        $connections = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction Stop | Where-Object {
            $addresses -contains [string]$_.LocalAddress -or [string]$_.LocalAddress -eq '0.0.0.0' -or [string]$_.LocalAddress -eq '::'
        })
        return @($connections | ForEach-Object { [int]$_.OwningProcess } | Select-Object -Unique)
    }
    catch {
        return @()
    }
}

function Restart-LocalConversationEndpoint {
    param(
        [Parameter(Mandatory = $true)][string]$Endpoint,
        [Parameter(Mandatory = $true)]$LaunchSpec
    )

    $endpointUri = [System.Uri]$Endpoint
    $processIds = @(Get-ConversationEndpointListenerProcessIds -HostName $endpointUri.Host -Port $endpointUri.Port)
    foreach ($processId in $processIds) {
        try {
            Stop-Process -Id $processId -Force -ErrorAction Stop
        }
        catch {
        }
    }

    Start-Sleep -Milliseconds 800
    Start-Process -FilePath $LaunchSpec.server_exe -ArgumentList $LaunchSpec.args -WorkingDirectory $LaunchSpec.working_directory -WindowStyle Hidden | Out-Null
}

function Get-ConversationEndpointCandidates {
    param([Parameter(Mandatory = $true)][string]$Endpoint)

    $candidates = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($Endpoint)) {
        [void]$candidates.Add($Endpoint.Trim())
        if ($Endpoint -match '^http://localhost(?::|/)') {
            [void]$candidates.Add(($Endpoint -replace '^http://localhost', 'http://127.0.0.1'))
        }
        elseif ($Endpoint -match '^http://127\.0\.0\.1(?::|/)') {
            [void]$candidates.Add(($Endpoint -replace '^http://127\.0\.0\.1', 'http://localhost'))
        }
    }

    return @($candidates | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
}

function Invoke-ConversationRequest {
    param(
        [Parameter(Mandatory = $true)][string]$Endpoint,
        [Parameter(Mandatory = $true)]$BodyObject,
        [Parameter(Mandatory = $true)][int]$TimeoutSec,
        [string]$ApiKey
    )

    $headers = @{ 'Content-Type' = 'application/json' }
    if (-not [string]::IsNullOrWhiteSpace($ApiKey)) {
        $headers['Authorization'] = "Bearer $ApiKey"
    }

    return Invoke-RestMethod -Uri $Endpoint -Method Post -TimeoutSec $TimeoutSec -Headers $headers -Body ($BodyObject | ConvertTo-Json -Depth 10)
}

function Get-LlamaRuntimeLaunchSpec {
    param([int]$Port)

    $runtimeConfigPath = Get-LocalPath -PathValue 'tod/config/llama-runtime.json'
    if (-not (Test-Path -Path $runtimeConfigPath)) {
        return $null
    }

    try {
        $runtimeConfig = Get-Content -Path $runtimeConfigPath -Raw | ConvertFrom-Json
    }
    catch {
        return $null
    }

    $serverExe = Get-LocalPath -PathValue ([string]$runtimeConfig.server_exe)
    $modelPath = Get-LocalPath -PathValue ([string]$runtimeConfig.default_model_path)
    if (-not (Test-Path -Path $serverExe) -or -not (Test-Path -Path $modelPath)) {
        return $null
    }

    $bindHost = if ($runtimeConfig.PSObject.Properties['host']) { [string]$runtimeConfig.host } else { '127.0.0.1' }
    $effectivePort = if ($Port -gt 0) { $Port } elseif ($runtimeConfig.PSObject.Properties['port']) { [int]$runtimeConfig.port } else { 8008 }
    $contextSize = if ($runtimeConfig.PSObject.Properties['context_size']) { [int]$runtimeConfig.context_size } else { 4096 }
    $gpuLayers = if ($runtimeConfig.PSObject.Properties['gpu_layers']) { [int]$runtimeConfig.gpu_layers } else { 20 }
    $threads = if ($runtimeConfig.PSObject.Properties['threads']) { [int]$runtimeConfig.threads } else { 8 }
    $chatFormat = if ($runtimeConfig.PSObject.Properties['chat_format']) { [string]$runtimeConfig.chat_format } else { 'chatml' }
    $extraArgs = if ($runtimeConfig.PSObject.Properties['extra_args']) { @($runtimeConfig.extra_args | ForEach-Object { [string]$_ }) } else { @() }

    $argList = @(
        '--host', $bindHost,
        '--port', [string]$effectivePort,
        '-m', $modelPath,
        '-c', [string]$contextSize,
        '-ngl', [string]$gpuLayers,
        '-t', [string]$threads,
        '--chat-template', $chatFormat
    )
    $argList += $extraArgs

    return [pscustomobject]@{
        server_exe = $serverExe
        working_directory = Split-Path -Parent $serverExe
        args = @($argList)
    }
}

function Test-LocalConversationEndpoint {
    param(
        [Parameter(Mandatory = $true)][string]$Endpoint,
        [Parameter(Mandatory = $true)][string]$Model,
        [Parameter(Mandatory = $true)][int]$TimeoutSec,
        [string]$ApiKey,
        [int]$Attempts = 2
    )

    $candidates = Get-ConversationEndpointCandidates -Endpoint $Endpoint
    $lastError = ''
    foreach ($candidate in $candidates) {
        for ($attempt = 1; $attempt -le [Math]::Max($Attempts, 1); $attempt++) {
            try {
                $probeBody = [ordered]@{
                    model = $Model
                    temperature = 0
                    max_tokens = 8
                    messages = @(
                        [ordered]@{ role = 'system'; content = 'Reply with the single word ok.' },
                        [ordered]@{ role = 'user'; content = 'ok' }
                    )
                }
                $response = Invoke-ConversationRequest -Endpoint $candidate -BodyObject $probeBody -TimeoutSec ([Math]::Max([Math]::Min($TimeoutSec, 8), 3)) -ApiKey $ApiKey
                $replyText = Get-ReplyTextFromResponse -Response $response
                if (-not [string]::IsNullOrWhiteSpace($replyText)) {
                    return [pscustomobject]@{
                        reachable = $true
                        endpoint = $candidate
                        error = ''
                    }
                }
                $lastError = 'Local conversation provider returned no reply text during health probe.'
            }
            catch {
                $lastError = $_.Exception.Message
            }
        }
    }

    return [pscustomobject]@{
        reachable = $false
        endpoint = if (@($candidates).Count -gt 0) { [string]$candidates[0] } else { [string]$Endpoint }
        error = $lastError
    }
}

function Ensure-LocalConversationEndpoint {
    param(
        [Parameter(Mandatory = $true)][string]$Endpoint,
        [Parameter(Mandatory = $true)][string]$Model,
        [Parameter(Mandatory = $true)][int]$TimeoutSec,
        [string]$ApiKey
    )

    $probe = Test-LocalConversationEndpoint -Endpoint $Endpoint -Model $Model -TimeoutSec $TimeoutSec -ApiKey $ApiKey -Attempts 1
    if ([bool]$probe.reachable) {
        return $probe
    }

    $endpointUri = [System.Uri]$Endpoint
    $listenerActive = Test-TcpPortListening -HostName $endpointUri.Host -Port $endpointUri.Port
    if (-not $listenerActive -and $endpointUri.Host -eq 'localhost') {
        $listenerActive = Test-TcpPortListening -HostName '127.0.0.1' -Port $endpointUri.Port
    }

    $launchSpec = Get-LlamaRuntimeLaunchSpec -Port $endpointUri.Port
    $timedOut = ([string]$probe.error -match 'timed out')

    if ($listenerActive -and $timedOut -and $null -ne $launchSpec) {
        Restart-LocalConversationEndpoint -Endpoint $Endpoint -LaunchSpec $launchSpec
        $deadline = (Get-Date).ToUniversalTime().AddSeconds(45)
        do {
            Start-Sleep -Milliseconds 1200
            $probe = Test-LocalConversationEndpoint -Endpoint $Endpoint -Model $Model -TimeoutSec $TimeoutSec -ApiKey $ApiKey -Attempts 1
            if ([bool]$probe.reachable) {
                return $probe
            }
        } while ((Get-Date).ToUniversalTime() -lt $deadline)
    }

    if (-not $listenerActive) {
        if ($null -ne $launchSpec) {
            Start-Process -FilePath $launchSpec.server_exe -ArgumentList $launchSpec.args -WorkingDirectory $launchSpec.working_directory -WindowStyle Hidden | Out-Null
            $deadline = (Get-Date).ToUniversalTime().AddSeconds(20)
            do {
                Start-Sleep -Milliseconds 800
                $probe = Test-LocalConversationEndpoint -Endpoint $Endpoint -Model $Model -TimeoutSec $TimeoutSec -ApiKey $ApiKey -Attempts 1
                if ([bool]$probe.reachable) {
                    return $probe
                }
            } while ((Get-Date).ToUniversalTime() -lt $deadline)
        }
    }

    return (Test-LocalConversationEndpoint -Endpoint $Endpoint -Model $Model -TimeoutSec $TimeoutSec -ApiKey $ApiKey -Attempts 2)
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
        $probe = if (-not [string]::IsNullOrWhiteSpace($endpoint) -and -not [string]::IsNullOrWhiteSpace($model)) {
            Ensure-LocalConversationEndpoint -Endpoint $endpoint -Model $model -TimeoutSec $timeoutSec -ApiKey $apiKey
        }
        else {
            [pscustomobject]@{
                reachable = $false
                endpoint = $endpoint
                error = 'Local conversation endpoint or model is not configured.'
            }
        }

        $payload = [pscustomobject]@{
            ok = $true
            provider = $provider
            local_enabled = ($null -ne $local) -and ((-not $local.PSObject.Properties['enabled']) -or [bool]$local.enabled)
            allow_third_party_helpers = $helpersAllowed
            fallback_to_builtin = $fallback
            endpoint = [string]$probe.endpoint
            model = $model
            reachable = [bool]$probe.reachable
            error = [string]$probe.error
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

        $probe = Ensure-LocalConversationEndpoint -Endpoint $endpoint -Model $model -TimeoutSec $timeoutSec -ApiKey $apiKey
        if (-not [bool]$probe.reachable) {
            throw ('Local conversation provider is not reachable. ' + [string]$probe.error)
        }

        $response = Invoke-ConversationRequest -Endpoint ([string]$probe.endpoint) -BodyObject $bodyObject -TimeoutSec $timeoutSec -ApiKey $apiKey
        $replyText = Get-ReplyTextFromResponse -Response $response
        if ([string]::IsNullOrWhiteSpace($replyText)) {
            throw 'Local conversation provider returned no reply text'
        }

        $payload = [pscustomobject]@{
            ok = $true
            provider = 'local'
            endpoint = [string]$probe.endpoint
            model = $model
            reply_text = $replyText
        }
        if ($AsJson) { $payload | ConvertTo-Json -Depth 8 } else { $payload }
        return
    }
}