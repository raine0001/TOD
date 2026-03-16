#Requires -Version 5.1
<#
.SYNOPSIS
    TOD Voice Listener — wake-word + command recognition via Windows Speech Recognition (System.Speech).
.DESCRIPTION
    Listens for "tod <command>", "hey tod <command>", etc. using the built-in Windows
    System.Speech engine (no external install, no API key, no internet).
    On recognition, writes a voice.intent event JSON to the voice inbox so TOD can act on it.
    Safe to run alongside TOD's autonomous listener cadence — read-only to TOD's core loop files.
.PARAMETER ConfigPath
    Path to voice-adapter.json (relative to repo root or absolute).
.PARAMETER MinConfidence
    Minimum recognition confidence (0.0..1.0). Default: 0.60.
.PARAMETER Force
    Bypass enabled/allow_microphone safety gates in config.
.EXAMPLE
    # Start in a new terminal (background-safe):
    powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Start-TODVoiceListener.ps1
.EXAMPLE
    # Force-start even if config has enabled=false (for testing):
    powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Start-TODVoiceListener.ps1 -Force
#>
param(
    [string]$ConfigPath = "tod/config/voice-adapter.json",
    [double]$MinConfidence = 0.60,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Get-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) { return $PathValue }
    return (Join-Path $repoRoot $PathValue)
}

function Initialize-ParentDir {
    param([Parameter(Mandatory = $true)][string]$FilePath)
    $dir = Split-Path -Parent $FilePath
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

function Write-Log {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [string]$LogPath = "",
        [string]$Level = "INFO"
    )
    $ts  = (Get-Date).ToString("HH:mm:ss")
    $line = "[{0}] [{1}] {2}" -f $ts, $Level, $Message
    Write-Host $line
    if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
        try {
            Initialize-ParentDir -FilePath $LogPath
            Add-Content -Path $LogPath -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
        } catch { }
    }
}

function Escape-SsmlText {
    param([string]$Text)

    if ($null -eq $Text) { return "" }
    return [System.Security.SecurityElement]::Escape([string]$Text)
}

function Get-TodSpeechSegments {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return @()
    }

    return @(([regex]::Split($Text.Trim(), '(?<=[\.!\?])\s+') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }))
}

function Get-TodPreferredVoiceName {
    param(
        [Parameter(Mandatory = $true)]$SpeechSynth,
        [string]$PreferredVoice,
        [string]$PreferredCulture = "en-US"
    )

    $installed = @($SpeechSynth.GetInstalledVoices() | Where-Object { $_.Enabled } | ForEach-Object { $_.VoiceInfo })
    if ($installed.Count -eq 0) {
        return ""
    }

    if (-not [string]::IsNullOrWhiteSpace($PreferredVoice) -and $PreferredVoice -ne 'default') {
        $exact = $installed | Where-Object { $_.Name -eq $PreferredVoice } | Select-Object -First 1
        if ($exact) { return [string]$exact.Name }

        $partial = $installed | Where-Object { $_.Name -like "*$PreferredVoice*" } | Select-Object -First 1
        if ($partial) { return [string]$partial.Name }
    }

    $cultureMatches = @($installed | Where-Object { $_.Culture.Name -eq $PreferredCulture })
    if ($cultureMatches.Count -gt 0) {
        $zira = $cultureMatches | Where-Object { $_.Name -like '*Zira*' } | Select-Object -First 1
        if ($zira) { return [string]$zira.Name }

        $female = $cultureMatches | Where-Object { [string]$_.Gender -eq 'Female' } | Select-Object -First 1
        if ($female) { return [string]$female.Name }

        return [string]($cultureMatches | Select-Object -First 1).Name
    }

    return [string]($installed | Select-Object -First 1).Name
}

function Convert-ToTodReplySsml {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [string]$VoiceName = "",
        [string]$Culture = "en-US",
        [int]$Rate = -1,
        [string]$Pitch = "+0st",
        [int]$SentenceBreakMs = 220,
        [int]$Volume = 100
    )

    $segments = Get-TodSpeechSegments -Text $Text
    if ($segments.Count -eq 0) {
        $segments = @($Text)
    }

    $safeSegments = @($segments | ForEach-Object { Escape-SsmlText -Text $_ })
    $body = ($safeSegments -join (" <break time='{0}ms'/> " -f $SentenceBreakMs))
    $rateValue = if ($Rate -ge 0) { "+{0}%" -f ($Rate * 10) } else { "{0}%" -f ($Rate * 10) }
    $volumeValue = "{0}%" -f ([Math]::Max(0, [Math]::Min(100, $Volume)))
    $prosody = "<prosody rate='{0}' pitch='{1}' volume='{2}'>{3}</prosody>" -f $rateValue, $Pitch, $volumeValue, $body

    if (-not [string]::IsNullOrWhiteSpace($VoiceName)) {
        $prosody = "<voice name='{0}'>{1}</voice>" -f (Escape-SsmlText -Text $VoiceName), $prosody
    }

    return "<speak version='1.0' xml:lang='{0}'>{1}</speak>" -f $Culture, $prosody
}

function Invoke-TodSpeechReply {
    param(
        [Parameter(Mandatory = $true)]$SpeechSynth,
        [Parameter(Mandatory = $true)][string]$ReplyText,
        [Parameter(Mandatory = $true)][string]$LogPath,
        [string]$VoiceName = "",
        [string]$Culture = "en-US",
        [int]$Rate = -1,
        [string]$Pitch = "+0st",
        [int]$SentenceBreakMs = 220,
        [int]$Volume = 100,
        [bool]$UseSsml = $true
    )

    $SpeechSynth.SpeakAsyncCancelAll()

    if ($UseSsml) {
        $ssml = Convert-ToTodReplySsml -Text $ReplyText -VoiceName $VoiceName -Culture $Culture -Rate $Rate -Pitch $Pitch -SentenceBreakMs $SentenceBreakMs -Volume $Volume
        try {
            return $SpeechSynth.SpeakSsmlAsync($ssml)
        }
        catch {
            Write-Log -Message ("WARN: SSML speech failed, falling back to plain speech: {0}" -f $_.Exception.Message) -LogPath $LogPath -Level "WARN"
        }
    }

    return $SpeechSynth.SpeakAsync($ReplyText)
}

function Get-IntentFromCommand {
    param([Parameter(Mandatory = $true)][string]$Command)
    $c = $Command.Trim().ToLower()
    if ([string]::IsNullOrWhiteSpace($c)) {
        return "query.help"
    }

    if ($c -match "\b(status|check status|what are you working on|what is your status|status right now)\b") {
        return "query.status"
    }

    if ($c -match "\b(eta|time remaining|time left|how much longer|how much time|when will you be done|when will you finish|estimated time|left on this project|left on this task|time do you have left|time have you got left|time left on the current task|time left on the current project)\b") {
        return "query.eta"
    }

    if ($c -match "\b(where are you|current task|current project|project progress|progress)\b") {
        return "query.progress"
    }

    if ($c -match "\b(are you awake|are you there|you awake|health check|hello|hi|hey|how are you)\b") {
        return "query.health"
    }

    if ($c -match "\b(summary|summarize|quick summary|what is the summary)\b") {
        return "query.summary"
    }

    if ($c -match "\b(refresh|quick refresh|refresh now)\b") {
        return "command.refresh"
    }

    if ($c -match "\b(stop|pause|hold)\b") {
        return "command.stop"
    }

    if ($c -match "\b(resume|continue|carry on)\b") {
        return "command.resume"
    }

    if ($c -match "\b(help|what can you do)\b") {
        return "query.help"
    }

    return "command.request"
}

function Convert-SecondsToHumanText {
    param([double]$Seconds)

    if ($Seconds -lt 0) { return "unknown" }

    $total = [int][math]::Round($Seconds)
    $hours = [int]($total / 3600)
    $minutes = [int](($total % 3600) / 60)
    $secondsOnly = [int]($total % 60)

    if ($hours -gt 0) {
        if ($minutes -gt 0) {
            return ("{0} hour{1} {2} minute{3}" -f $hours, $(if ($hours -eq 1) { "" } else { "s" }), $minutes, $(if ($minutes -eq 1) { "" } else { "s" }))
        }
        return ("{0} hour{1}" -f $hours, $(if ($hours -eq 1) { "" } else { "s" }))
    }

    if ($minutes -gt 0) {
        if ($secondsOnly -gt 0 -and $minutes -lt 5) {
            return ("{0} minute{1} {2} second{3}" -f $minutes, $(if ($minutes -eq 1) { "" } else { "s" }), $secondsOnly, $(if ($secondsOnly -eq 1) { "" } else { "s" }))
        }
        return ("{0} minute{1}" -f $minutes, $(if ($minutes -eq 1) { "" } else { "s" }))
    }

    return ("{0} second{1}" -f $secondsOnly, $(if ($secondsOnly -eq 1) { "" } else { "s" }))
}

function Normalize-SpeechText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
    $v = $Text.ToLowerInvariant()
    $v = ($v -replace "[^a-z0-9\s]", " ")
    $v = ($v -replace "\s+", " ").Trim()
    return $v
}

function Normalize-CommandForIntent {
    param([string]$CommandText)
    $text = Normalize-SpeechText -Text $CommandText
    if ([string]::IsNullOrWhiteSpace($text)) { return "" }

    $text = ($text -replace "\b(please|just|like|um|uh|hmm|you know|kind of|sort of|right now)\b", " ")
    $text = ($text -replace "\b(can you|could you|would you|will you|tell me|show me|give me|let me know)\b", " ")
    $text = ($text -replace "\byou ve\b", "you have")
    $text = ($text -replace "\bi ve\b", "i have")
    $text = ($text -replace "\bwhat s\b", "what is")
    $text = ($text -replace "\bit s\b", "it is")
    $text = ($text -replace "\b(tod|todd|toad|hey tod|hi tod|hello tod|okay tod|hey todd|hi todd|hello todd|okay todd|taught|tod s)\b", " ")
    $text = ($text -replace "\s+", " ").Trim()

    return $text
}

function Test-DirectQueryIntent {
    param([Parameter(Mandatory = $true)][string]$Intent)

    return @(
        'query.status',
        'query.progress',
        'query.eta',
        'query.health',
        'query.summary',
        'query.help'
    ) -contains $Intent
}

function Get-IntentConfidenceThreshold {
    param(
        [Parameter(Mandatory = $true)][string]$Intent,
        [double]$DefaultThreshold,
        $ThresholdMap
    )

    if ($ThresholdMap -and $ThresholdMap.PSObject.Properties[$Intent]) {
        $value = [double]$ThresholdMap.PSObject.Properties[$Intent].Value
        if ($value -ge 0 -and $value -le 1) {
            return $value
        }
    }

    return $DefaultThreshold
}

function Test-UsefulOpenConversation {
    param(
        [Parameter(Mandatory = $true)][string]$CommandText,
        [switch]$HasWake
    )

    $normalized = Normalize-SpeechText -Text $CommandText
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return $false
    }

    $words = @($normalized.Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries))
    if ($HasWake) {
        return ($words.Count -ge 2)
    }

    if ($words.Count -lt 4) {
        return $false
    }

    if ($normalized -match '^(by one|the way he saw|boston s one|time|today|tod me|taught me)$') {
        return $false
    }

    return $true
}

function Get-ProjectPurposeSpeechText {
    param([string]$Purpose)

    $raw = [string]$Purpose
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return 'We are focused on the current objective.'
    }

    $trimmed = $raw.Trim().TrimEnd('.')

    if ($trimmed -match '^(?i:listener objective)\s+(\d+)$') {
        return "We are focused on listener objective $($Matches[1])."
    }

    if ($trimmed -match '^(?i:.+?)\s+and\s+.+?\s+are working on\s+(.+)$') {
        return "We are working on $($Matches[1].Trim())."
    }

    if ($trimmed -match '^(?i:.+?)\s+is working on\s+(.+)$') {
        return "We are working on $($Matches[1].Trim())."
    }

    if ($trimmed -match '^(?i:working on)\s+(.+)$') {
        return "We are working on $($Matches[1].Trim())."
    }

    return "We are focused on $trimmed."
}

function Split-WakeAndCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Transcript,
        [Parameter(Mandatory = $true)][string[]]$WakeVariants
    )

    $normalized = Normalize-SpeechText -Text $Transcript
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return [pscustomobject]@{
            is_wake = $false
            command = ""
            normalized = ""
        }
    }

    foreach ($wake in $WakeVariants) {
        $wakeNorm = Normalize-SpeechText -Text $wake
        if ([string]::IsNullOrWhiteSpace($wakeNorm)) { continue }

        if ($normalized -eq $wakeNorm) {
            return [pscustomobject]@{
                is_wake = $true
                command = ""
                normalized = $normalized
            }
        }

        $wakePrefix = "$wakeNorm "
        if ($normalized.StartsWith($wakePrefix)) {
            $cmd = $normalized.Substring($wakePrefix.Length).Trim()
            return [pscustomobject]@{
                is_wake = $true
                command = $cmd
                normalized = $normalized
            }
        }
    }

    return [pscustomobject]@{
        is_wake = $false
        command = ""
        normalized = $normalized
    }
}

function Emit-ConfirmationTone {
    param([string]$LogPath = "")
    try {
        [System.Media.SystemSounds]::Asterisk.Play()
        return
    } catch { }

    try {
        [console]::Beep(920, 90)
    } catch {
        if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
            Write-Log -Message ("WARN: Unable to play confirmation tone: {0}" -f $_.Exception.Message) -LogPath $LogPath -Level "WARN"
        }
    }
}

function Write-VoiceEvent {
    param(
        [Parameter(Mandatory = $true)][string]$Transcript,
        [Parameter(Mandatory = $true)][string]$Intent,
        [Parameter(Mandatory = $true)][double]$Confidence,
        [Parameter(Mandatory = $true)][string]$InboxPath,
        [Parameter(Mandatory = $true)][string]$TelemetryPath,
        [string]$LogPath = "",
        [string]$SessionId = ""
    )

    $eventId = "voice-{0}" -f ([Guid]::NewGuid().ToString("N"))
    $eventObject = [pscustomobject]@{
        event_type    = "voice.intent"
        event_id      = $eventId
        timestamp_utc = (Get-Date).ToUniversalTime().ToString("o")
        source        = "tod-voice-adapter-v1"
        payload       = [pscustomobject]@{
            transcript      = $Transcript
            intent          = $Intent
            confidence      = [Math]::Round($Confidence, 3)
            objective_hint  = ""
            camera_used     = $false
            metadata        = [pscustomobject]@{
                session_id       = $SessionId
                mode             = "live"
                capture_provider = "system.speech"
                stt_provider     = "system.speech"
            }
        }
    }

    $eventFile = Join-Path $InboxPath ("{0}.json" -f $eventId)
    Initialize-ParentDir -FilePath $eventFile
    $eventObject | ConvertTo-Json -Depth 20 | Set-Content -Path $eventFile -Encoding UTF8

    # Update telemetry so dashboard shows last recognition
    $telemetry = [pscustomobject]@{
        source           = "tod-voice-adapter-v1"
        timestamp_utc    = (Get-Date).ToUniversalTime().ToString("o")
        enabled          = $true
        allow_microphone = $true
        allow_camera     = $false
        mode             = "live"
        dry_run          = $false
        last_event_id    = $eventId
        last_intent      = $Intent
        last_transcript  = $Transcript
    }
    Initialize-ParentDir -FilePath $TelemetryPath
    $telemetry | ConvertTo-Json -Depth 10 | Set-Content -Path $TelemetryPath -Encoding UTF8

    Write-Log -Message ("Intent queued | intent:{0} | conf:{1} | transcript:`"{2}`" | id:{3}" -f `
        $Intent, [Math]::Round($Confidence, 2), $Transcript, $eventId) -LogPath $LogPath

    return $eventId
}

function Get-VoiceReplyText {
    param(
        [Parameter(Mandatory = $true)][string]$Intent,
        [string]$CommandText = "",
        $ProjectStatus
    )

    $hasLiveProjectStatus = ($null -ne $ProjectStatus) -and ($ProjectStatus.PSObject.Properties['selected_objective_id'] -or $ProjectStatus.PSObject.Properties['listener_activity'] -or $ProjectStatus.PSObject.Properties['progress'])

    function Get-RelativeAgeShort {
        param([string]$IsoText)

        if ([string]::IsNullOrWhiteSpace($IsoText)) { return "n/a" }
        try {
            $ts = [DateTimeOffset]::Parse($IsoText)
        }
        catch {
            return "n/a"
        }
        $ageSec = [math]::Max(0, [int][math]::Round(([DateTimeOffset]::UtcNow - $ts).TotalSeconds))
        if ($ageSec -lt 60) { return ("{0}s ago" -f $ageSec) }
        return ("{0}m ago" -f [int][math]::Round($ageSec / 60.0))
    }

    function Get-GeneralConversationReply {
        param([string]$InputText)

        $t = Normalize-SpeechText -Text $InputText
        if ([string]::IsNullOrWhiteSpace($t)) {
            return "I am here with you. Ask me about our current status, project progress, estimated timing, datasets, or quantum physics."
        }

        if ($t -match "(dataset|data set|data|parsing|parse|etl|pipeline|schema|csv|json)") {
            return "Great dataset idea. Start with schema profiling, missing value analysis, duplicates, outlier checks, and label quality. Then design a parsing pipeline with validation rules and an error bucket, and I can help draft the exact steps."
        }

        if ($t -match "(quantum|physics|qubit|entanglement|superposition|hamiltonian|wave function)") {
            return "Quantum physics is a great topic. A practical path is qubits, superposition, entanglement, then simple gates and measurement. If you want, I can give a beginner roadmap or go deeper into one concept now."
        }

        if ($t -match "(hello|hi|hey|how are you|what can you do)") {
            return "I am online and actively working with you. I can chat about technical ideas and report our live project status and ETA."
        }

        return "I can discuss that. If you want sharper answers, include a little context such as your goal, constraints, and timeframe."
    }

    function Invoke-ConversationModelReply {
        param(
            [string]$InputText,
            $StatusPayload,
            [string]$BuiltinReply
        )

        function Invoke-OpenAICompatibleConversation {
            param(
                [Parameter(Mandatory = $true)]$ProviderConfig,
                [Parameter(Mandatory = $true)][string]$ProviderName,
                [Parameter(Mandatory = $true)][string]$UserInput,
                [Parameter(Mandatory = $true)][string]$ObjectiveSummary,
                [Parameter(Mandatory = $true)][string]$TaskState,
                [Parameter(Mandatory = $true)][string]$ObjectiveId
            )

            $endpoint = if ($ProviderConfig.PSObject.Properties['endpoint'] -and -not [string]::IsNullOrWhiteSpace([string]$ProviderConfig.endpoint)) {
                [string]$ProviderConfig.endpoint
            }
            else {
                throw "$ProviderName endpoint is not configured."
            }
            $model = if ($ProviderConfig.PSObject.Properties['model'] -and -not [string]::IsNullOrWhiteSpace([string]$ProviderConfig.model)) {
                [string]$ProviderConfig.model
            }
            else {
                throw "$ProviderName model is not configured."
            }
            $temperature = if ($ProviderConfig.PSObject.Properties['temperature']) { [double]$ProviderConfig.temperature } else { 0.35 }
            $timeoutSec = if ($ProviderConfig.PSObject.Properties['timeout_sec']) { [int]$ProviderConfig.timeout_sec } else { 20 }
            $maxTokens = if ($ProviderConfig.PSObject.Properties['max_tokens']) { [int]$ProviderConfig.max_tokens } else { 220 }
            $apiKeyEnv = if ($ProviderConfig.PSObject.Properties['api_key_env'] -and -not [string]::IsNullOrWhiteSpace([string]$ProviderConfig.api_key_env)) {
                [string]$ProviderConfig.api_key_env
            }
            else {
                ''
            }
            $apiKey = if ([string]::IsNullOrWhiteSpace($apiKeyEnv)) { '' } else { [Environment]::GetEnvironmentVariable($apiKeyEnv) }

            $systemPrompt = @"
You are TOD, a conversational coding assistant speaking directly with your operator.
Answer in natural first-person language.
When the question is about current work, use the supplied project context and speak as a collaborator: use "I" and "we", not third-person report language.
When the question is general knowledge, answer directly and clearly.
Keep responses concise, typically 2 to 5 sentences.
Do not mention internal API fields, JSON, or raw telemetry unless explicitly asked.
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
                    [ordered]@{ role = 'user'; content = [string]$UserInput }
                )
            }

            $headers = @{ 'Content-Type' = 'application/json' }
            if (-not [string]::IsNullOrWhiteSpace($apiKey)) {
                $headers['Authorization'] = "Bearer $apiKey"
            }

            $response = Invoke-RestMethod -Uri $endpoint -Method Post -TimeoutSec $timeoutSec -Headers $headers -Body ($bodyObject | ConvertTo-Json -Depth 10)

            $replyText = ''
            if ($response -and $response.PSObject.Properties['choices'] -and @($response.choices).Count -gt 0) {
                $choice = $response.choices[0]
                if ($choice.message -and $choice.message.PSObject.Properties['content']) {
                    if ($choice.message.content -is [string]) {
                        $replyText = [string]$choice.message.content
                    }
                    elseif ($choice.message.content -is [System.Array]) {
                        $parts = @()
                        foreach ($part in $choice.message.content) {
                            if ($part -and $part.PSObject.Properties['text'] -and -not [string]::IsNullOrWhiteSpace([string]$part.text)) {
                                $parts += [string]$part.text
                            }
                        }
                        $replyText = ($parts -join ' ').Trim()
                    }
                }
            }

            if ([string]::IsNullOrWhiteSpace($replyText)) {
                throw "$ProviderName returned no reply text."
            }

            return (($replyText -replace '\s+', ' ').Trim())
        }

        $providerMode = if ([string]::IsNullOrWhiteSpace([string]$script:conversationProvider)) {
            'builtin'
        }
        else {
            [string]$script:conversationProvider
        }
        $providerMode = $providerMode.ToLowerInvariant()

        $openAiConfig = if ($script:conversationConfig -and $script:conversationConfig.PSObject.Properties['openai']) {
            $script:conversationConfig.openai
        }
        else {
            $null
        }

        $localConfig = if ($script:conversationConfig -and $script:conversationConfig.PSObject.Properties['local']) {
            $script:conversationConfig.local
        }
        else {
            $null
        }

        $helpersAllowed = if ($script:conversationConfig -and $script:conversationConfig.PSObject.Properties['allow_third_party_helpers']) {
            [bool]$script:conversationConfig.allow_third_party_helpers
        }
        else {
            $false
        }

        $localEnabled = ($null -ne $localConfig) -and ((-not $localConfig.PSObject.Properties['enabled']) -or [bool]$localConfig.enabled)
        $openAiEnabled = ($null -ne $openAiConfig) -and ((-not $openAiConfig.PSObject.Properties['enabled']) -or [bool]$openAiConfig.enabled)

        $openAiApiKeyEnv = if ($openAiConfig -and $openAiConfig.PSObject.Properties['api_key_env'] -and -not [string]::IsNullOrWhiteSpace([string]$openAiConfig.api_key_env)) {
            [string]$openAiConfig.api_key_env
        }
        else {
            'OPENAI_API_KEY'
        }
        $openAiApiKey = [Environment]::GetEnvironmentVariable($openAiApiKeyEnv)

        $resolvedProvider = $providerMode
        switch ($providerMode) {
            'auto' {
                if ($localEnabled) {
                    $resolvedProvider = 'local'
                }
                elseif ($helpersAllowed -and $openAiEnabled -and -not [string]::IsNullOrWhiteSpace($openAiApiKey)) {
                    $resolvedProvider = 'openai'
                }
                else {
                    $resolvedProvider = 'builtin'
                }
            }
            'local_first' {
                if ($localEnabled) {
                    $resolvedProvider = 'local'
                }
                elseif ($helpersAllowed -and $openAiEnabled -and -not [string]::IsNullOrWhiteSpace($openAiApiKey)) {
                    $resolvedProvider = 'openai'
                }
                else {
                    $resolvedProvider = 'builtin'
                }
            }
            'local_only' {
                $resolvedProvider = 'local'
            }
            'openai_only' {
                $resolvedProvider = 'openai'
            }
        }

        if ($resolvedProvider -eq 'builtin') {
            return $BuiltinReply
        }

        $objectiveSummary = Get-ObjectiveSummaryNarrative -StatusPayload $StatusPayload
        $taskState = if ($StatusPayload -and $StatusPayload.PSObject.Properties['task_state']) { [string]$StatusPayload.task_state } else { 'unknown' }
        $objectiveId = if ($StatusPayload -and $StatusPayload.PSObject.Properties['selected_objective_id']) { [string]$StatusPayload.selected_objective_id } else { '?' }

        try {
            switch ($resolvedProvider) {
                'local' {
                    if (-not $localEnabled) {
                        throw 'Local conversation provider is not configured.'
                    }
                    return (Invoke-OpenAICompatibleConversation -ProviderConfig $localConfig -ProviderName 'Local conversation provider' -UserInput $InputText -ObjectiveSummary $objectiveSummary -TaskState $taskState -ObjectiveId $objectiveId)
                }
                'openai' {
                    if (-not $helpersAllowed) {
                        throw 'Third-party conversation helpers are disabled by policy.'
                    }
                    if (-not $openAiEnabled) {
                        throw 'OpenAI helper is not configured.'
                    }
                    if ([string]::IsNullOrWhiteSpace($openAiApiKey)) {
                        throw ("{0} not set for OpenAI helper." -f $openAiApiKeyEnv)
                    }
                    return (Invoke-OpenAICompatibleConversation -ProviderConfig $openAiConfig -ProviderName 'OpenAI helper' -UserInput $InputText -ObjectiveSummary $objectiveSummary -TaskState $taskState -ObjectiveId $objectiveId)
                }
                default {
                    return $BuiltinReply
                }
            }
        }
        catch {
            $fallback = if ($script:conversationFallbackToBuiltin) { 'builtin fallback enabled' } else { 'no builtin fallback' }
            Write-Log -Message ("Conversation model call failed: {0} ({1})" -f $_.Exception.Message, $fallback) -LogPath $script:logAbs -Level 'WARN'
            if ($script:conversationFallbackToBuiltin) {
                return $BuiltinReply
            }
            return 'I could not reach my conversation model just now.'
        }
    }

    function Get-ObjectiveSummaryNarrative {
        param($StatusPayload)

        $objectiveId = if ($StatusPayload -and $StatusPayload.PSObject.Properties["selected_objective_id"]) { [string]$StatusPayload.selected_objective_id } else { "?" }
        $progressObj = if ($StatusPayload -and $StatusPayload.PSObject.Properties["progress"]) { $StatusPayload.progress } else { $null }
        $listenerObj = if ($StatusPayload -and $StatusPayload.PSObject.Properties["listener_activity"]) { $StatusPayload.listener_activity } else { $null }
        $syncObj = if ($listenerObj -and $listenerObj.PSObject.Properties["sync"]) { $listenerObj.sync } else { $null }
        $watchdogObj = if ($StatusPayload -and $StatusPayload.PSObject.Properties["recovery_watchdog"]) { $StatusPayload.recovery_watchdog } else { $null }
        $markerObj = if ($StatusPayload -and $StatusPayload.PSObject.Properties["marker"]) { $StatusPayload.marker } else { $null }

        $taskCount = if ($progressObj -and $progressObj.PSObject.Properties["task_count"]) { [int]$progressObj.task_count } else { 0 }
        $completedEq = if ($progressObj -and $progressObj.PSObject.Properties["completed_equivalent"]) { [double]$progressObj.completed_equivalent } else { 0 }
        $progressPct = if ($progressObj -and $progressObj.PSObject.Properties["percent"]) { [int]$progressObj.percent } else { -1 }

        $latestTask = if ($listenerObj -and $listenerObj.PSObject.Properties["request_task_id"] -and -not [string]::IsNullOrWhiteSpace([string]$listenerObj.request_task_id)) {
            [string]$listenerObj.request_task_id
        }
        elseif ($listenerObj -and $listenerObj.PSObject.Properties["latest_request_id"]) {
            [string]$listenerObj.latest_request_id
        }
        else {
            "objective-$objectiveId-task-unknown"
        }

        $latestTaskNumber = -1
        if ($latestTask -match "task-(\d+)") {
            $latestTaskNumber = [int]$Matches[1]
        }

        $baseComplete = $false
        if ($taskCount -gt 0) {
            $baseComplete = ($completedEq -ge $taskCount) -or ($progressPct -ge 100)
        }
        $liveCadenceActive = $baseComplete -and ($latestTaskNumber -gt $taskCount)

        $mimTimestamp = ""
        if ($listenerObj -and $listenerObj.PSObject.Properties["request_generated_at"]) {
            $mimTimestamp = [string]$listenerObj.request_generated_at
        }
        $todTimestamp = ""
        if ($listenerObj -and $listenerObj.PSObject.Properties["result_generated_at"]) {
            $todTimestamp = [string]$listenerObj.result_generated_at
        }
        $mimAge = Get-RelativeAgeShort -IsoText $mimTimestamp
        $todAge = Get-RelativeAgeShort -IsoText $todTimestamp

        $syncText = "MIM and TOD are aligned on the latest cadence task."
        if ($syncObj -and $syncObj.PSObject.Properties["is_mim_ahead"] -and [bool]$syncObj.is_mim_ahead) {
            $pending = if ($syncObj.PSObject.Properties["pending_request_count"]) { [int]$syncObj.pending_request_count } else { 1 }
            $syncText = "MIM is ahead by $pending request" + $(if ($pending -eq 1) { "" } else { "s" }) + "."
        }

        $purpose = if ($markerObj -and $markerObj.PSObject.Properties["title"] -and -not [string]::IsNullOrWhiteSpace([string]$markerObj.title)) {
            [string]$markerObj.title
        }
        else {
            "Listener Objective $objectiveId"
        }
        $purposeSpeech = Get-ProjectPurposeSpeechText -Purpose $purpose

        $watchdogState = if ($watchdogObj -and $watchdogObj.PSObject.Properties["state"]) { [string]$watchdogObj.state } else { "unknown" }
        $reliabilityText = if ($watchdogState -eq "healthy") {
            "No reliability issues are currently detected."
        }
        else {
            "Watchdog state is $watchdogState."
        }

        if ($liveCadenceActive) {
            return "We completed the base funnel for objective $objectiveId, and I am still actively working through autonomous listener cadence. I am currently on $latestTask. Last MIM request was $mimAge and last TOD result was $todAge. $syncText $purposeSpeech $reliabilityText"
        }

        if ($progressPct -ge 0) {
            return "For objective $objectiveId, I am at $progressPct percent and still actively working. Current task is $latestTask. $syncText $purposeSpeech $reliabilityText"
        }

        return "Objective $objectiveId is active and I am still working it. Current task is $latestTask. $syncText $purposeSpeech $reliabilityText"
    }

    switch ($Intent) {
        "query.status" {
            if (-not $hasLiveProjectStatus) {
                return "I am listening, but I cannot reach live project status right now."
            }
            return (Get-ObjectiveSummaryNarrative -StatusPayload $ProjectStatus)
        }
        "query.progress" {
            if (-not $hasLiveProjectStatus) {
                return "I am listening, but I cannot reach live project progress right now."
            }
            return (Get-ObjectiveSummaryNarrative -StatusPayload $ProjectStatus)
        }
        "query.eta" {
            if (-not $hasLiveProjectStatus) {
                return "I cannot estimate timing right now because the live project status endpoint is unavailable."
            }
            $progressObj = if ($ProjectStatus -and $ProjectStatus.PSObject.Properties["progress"]) { $ProjectStatus.progress } else { $null }
            $cadenceObj = if ($ProjectStatus -and $ProjectStatus.PSObject.Properties["cadence_health"] -and $ProjectStatus.cadence_health.PSObject.Properties["cadence"]) { $ProjectStatus.cadence_health.cadence } else { $null }
            $activityObj = if ($ProjectStatus -and $ProjectStatus.PSObject.Properties["listener_activity"]) { $ProjectStatus.listener_activity } else { $null }

            $taskCount = if ($progressObj -and $progressObj.PSObject.Properties["task_count"]) { [double]$progressObj.task_count } else { -1 }
            $doneUnits = if ($progressObj -and $progressObj.PSObject.Properties["completed_equivalent"]) { [double]$progressObj.completed_equivalent } else { -1 }
            $cycleSec = if ($cadenceObj -and $cadenceObj.PSObject.Properties["p50_sec"] -and [double]$cadenceObj.p50_sec -gt 0) { [double]$cadenceObj.p50_sec } elseif ($cadenceObj -and $cadenceObj.PSObject.Properties["avg_sec"] -and [double]$cadenceObj.avg_sec -gt 0) { [double]$cadenceObj.avg_sec } else { -1 }

            # Live task number from sync (may be > base funnel task_count)
            $liveTaskNum = -1
            if ($activityObj -and $activityObj.PSObject.Properties["sync"]) {
                $syncObj = $activityObj.sync
                if ($syncObj.PSObject.Properties["result_task_number"] -and [int]$syncObj.result_task_number -gt 0) {
                    $liveTaskNum = [int]$syncObj.result_task_number
                }
            }

            if ($taskCount -gt 0 -and $doneUnits -ge 0 -and $cycleSec -gt 0) {
                $remainingUnits = [math]::Max(0, $taskCount - $doneUnits)

                # Base funnel complete but live cadence is still running beyond it
                if ($remainingUnits -eq 0 -and $liveTaskNum -gt $taskCount) {
                    $extra = $liveTaskNum - [int]$taskCount
                    $cycleMin = [math]::Round($cycleSec / 60, 1)
                    return "My base funnel of $([int]$taskCount) tasks is fully complete. I am currently on task $liveTaskNum, which is $extra tasks into continuous autonomous cadence beyond the base funnel. I am running in live mode with no scheduled end. Each task is averaging about $cycleMin minutes."
                }

                $etaSec = [double]($remainingUnits * $cycleSec)
                $etaText = Convert-SecondsToHumanText -Seconds $etaSec
                return "Based on my current cadence, I estimate we have about $etaText remaining."
            }

            return "I can estimate more accurately once I have a few more cadence and progress samples."
        }
        "query.health" {
            if (-not $hasLiveProjectStatus) {
                return "Voice recognition is online, but I cannot reach live project health right now."
            }
            $cadence = if ($ProjectStatus -and $ProjectStatus.PSObject.Properties["cadence_health"] -and $ProjectStatus.cadence_health.PSObject.Properties["severity"]) { [string]$ProjectStatus.cadence_health.severity } else { "unknown" }
            $watchdog = if ($ProjectStatus -and $ProjectStatus.PSObject.Properties["recovery_watchdog"] -and $ProjectStatus.recovery_watchdog.PSObject.Properties["state"]) { [string]$ProjectStatus.recovery_watchdog.state } else { "unknown" }
            return "My current health looks $cadence on cadence and $watchdog on watchdog state."
        }
        "query.summary" {
            if (-not $hasLiveProjectStatus) {
                return "I am listening, but I cannot reach the live project summary right now."
            }
            return (Get-ObjectiveSummaryNarrative -StatusPayload $ProjectStatus)
        }
        "query.help" {
            return "Try commands like, tod status, tod summary, or tod are you awake."
        }
        default {
            $builtinReply = Get-GeneralConversationReply -InputText $CommandText
            return (Invoke-ConversationModelReply -InputText $CommandText -StatusPayload $ProjectStatus -BuiltinReply $builtinReply)
        }
    }
}

function Save-VoiceResponse {
    param(
        [Parameter(Mandatory = $true)][string]$OutDir,
        [Parameter(Mandatory = $true)]$Payload
    )

    $responseId = "voice-response-{0}" -f ((Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmssfff"))
    $target = Join-Path $OutDir ("{0}.json" -f $responseId)
    Initialize-ParentDir -FilePath $target
    $Payload | ConvertTo-Json -Depth 25 | Set-Content -Path $target -Encoding UTF8
    return $target
}

function Write-ConversationHealth {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Payload
    )

    Initialize-ParentDir -FilePath $Path
    $Payload | ConvertTo-Json -Depth 20 | Set-Content -Path $Path -Encoding UTF8
}

# ---------------------------------------------------------------------------
# Boot
# ---------------------------------------------------------------------------

$cfgAbs = Get-LocalPath -PathValue $ConfigPath
if (-not (Test-Path -Path $cfgAbs)) {
    throw "Voice adapter config not found: $cfgAbs"
}

$config = Get-Content -Path $cfgAbs -Raw | ConvertFrom-Json

if (-not $Force) {
    if (-not [bool]$config.enabled) {
        Write-Host "Voice adapter is disabled (config: enabled=false). Use -Force to override." -ForegroundColor Yellow
        exit 0
    }
    if (-not [bool]$config.allow_microphone) {
        Write-Host "Microphone access is disabled (config: allow_microphone=false). Use -Force to override." -ForegroundColor Yellow
        exit 0
    }
}

$paths    = if ($config.PSObject.Properties["paths"]) { $config.paths } else { $null }
$inboxRel = if ($paths -and $paths.PSObject.Properties["voice_inbox"]) { [string]$paths.voice_inbox } else { "tod/inbox/voice/events" }
$outRel   = if ($paths -and $paths.PSObject.Properties["voice_out"]) { [string]$paths.voice_out } else { "tod/out/voice" }
$telRel   = if ($paths -and $paths.PSObject.Properties["telemetry"]) { [string]$paths.telemetry } else { "shared_state/voice_adapter_status.json" }
$conversationHealthRel = if ($paths -and $paths.PSObject.Properties["conversation_health"]) { [string]$paths.conversation_health } else { "shared_state/voice_conversation_provider_status.json" }
$pidRel   = if ($config.PSObject.Properties["listener_pid_path"]) { [string]$config.listener_pid_path } else { "shared_state/voice_listener.pid" }
$logRel   = "tod/out/voice/voice-listener.log"

$autoExecute = if ($config.PSObject.Properties["auto_execute_queries"]) { [bool]$config.auto_execute_queries } else { $true }
$speakResponses = if ($config.PSObject.Properties["speak_responses"]) { [bool]$config.speak_responses } else { $true }
$quietMode = if ($config.PSObject.Properties["quiet_mode"]) { [bool]$config.quiet_mode } else { $false }
$speakEnabled = $speakResponses -and (-not $quietMode)
$statusApiUrl = if ($config.PSObject.Properties["status_api_url"] -and -not [string]::IsNullOrWhiteSpace([string]$config.status_api_url)) { [string]$config.status_api_url } else { "http://localhost:8844/api/project-status" }
$ttsConfig = if ($config.PSObject.Properties["tts"]) { $config.tts } else { $null }
$ttsPreferredVoice = if ($ttsConfig -and $ttsConfig.PSObject.Properties['voice']) { [string]$ttsConfig.voice } else { 'default' }
$ttsCulture = if ($ttsConfig -and $ttsConfig.PSObject.Properties['culture'] -and -not [string]::IsNullOrWhiteSpace([string]$ttsConfig.culture)) { [string]$ttsConfig.culture } else { 'en-US' }
$ttsRate = if ($ttsConfig -and $ttsConfig.PSObject.Properties['rate']) { [int]$ttsConfig.rate } else { -1 }
$ttsVolume = if ($ttsConfig -and $ttsConfig.PSObject.Properties['volume']) { [int]$ttsConfig.volume } else { 100 }
$ttsPitch = if ($ttsConfig -and $ttsConfig.PSObject.Properties['pitch'] -and -not [string]::IsNullOrWhiteSpace([string]$ttsConfig.pitch)) { [string]$ttsConfig.pitch } else { '+0st' }
$ttsSentenceBreakMs = if ($ttsConfig -and $ttsConfig.PSObject.Properties['sentence_break_ms']) { [int]$ttsConfig.sentence_break_ms } else { 220 }
$ttsUseSsml = if ($ttsConfig -and $ttsConfig.PSObject.Properties['use_ssml']) { [bool]$ttsConfig.use_ssml } else { $true }
$script:conversationConfig = if ($config.PSObject.Properties["conversation"]) { $config.conversation } else { $null }
$script:conversationProvider = if ($script:conversationConfig -and $script:conversationConfig.PSObject.Properties["provider"]) { [string]$script:conversationConfig.provider } else { "builtin" }
$script:conversationFallbackToBuiltin = if ($script:conversationConfig -and $script:conversationConfig.PSObject.Properties["fallback_to_builtin"]) { [bool]$script:conversationConfig.fallback_to_builtin } else { $true }
$intentThresholds = if ($config.PSObject.Properties["command_confidence_thresholds"]) { $config.command_confidence_thresholds } else { $null }
$followUpWindowSec = if ($config.PSObject.Properties["follow_up_window_sec"]) { [int]$config.follow_up_window_sec } else { 75 }
$followUpMinConfidence = if ($config.PSObject.Properties["follow_up_min_confidence"]) { [double]$config.follow_up_min_confidence } else { 0.52 }
$wakeMinConfidence = if ($config.PSObject.Properties["wake_min_confidence"]) { [double]$config.wake_min_confidence } else { 0.48 }
$directQueryMinConfidence = if ($config.PSObject.Properties["direct_query_min_confidence"]) { [double]$config.direct_query_min_confidence } else { 0.40 }

$inboxAbs    = Get-LocalPath -PathValue $inboxRel
$outAbs      = Get-LocalPath -PathValue $outRel
$telemetryAbs = Get-LocalPath -PathValue $telRel
$conversationHealthAbs = Get-LocalPath -PathValue $conversationHealthRel
$pidAbs      = Get-LocalPath -PathValue $pidRel
$logAbs      = Get-LocalPath -PathValue $logRel

$script:logAbs = $logAbs

$effectiveMinConf = if ($config.PSObject.Properties["min_confidence"]) { [double]$config.min_confidence } else { $MinConfidence }
$sessionId = "voice-session-{0}" -f ((Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmmss"))

# Write PID file so dashboard knows the listener is alive
Initialize-ParentDir -FilePath $pidAbs
[string]$PID | Set-Content -Path $pidAbs -Encoding UTF8

Write-Log -Message ("TOD Voice Listener starting | session:{0} | pid:{1} | min_conf:{2}" -f $sessionId, $PID, $effectiveMinConf) -LogPath $logAbs

try {
    $providerStatus = powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Invoke-TODConversationProvider.ps1') -Action status -ConfigPath $cfgAbs -AsJson | ConvertFrom-Json
    $healthPayload = [pscustomobject]@{
        source = 'tod-voice-listener'
        timestamp_utc = (Get-Date).ToUniversalTime().ToString('o')
        provider = if ($providerStatus.PSObject.Properties['provider']) { [string]$providerStatus.provider } else { 'unknown' }
        local_enabled = if ($providerStatus.PSObject.Properties['local_enabled']) { [bool]$providerStatus.local_enabled } else { $false }
        reachable = if ($providerStatus.PSObject.Properties['reachable']) { [bool]$providerStatus.reachable } else { $false }
        model = if ($providerStatus.PSObject.Properties['model']) { [string]$providerStatus.model } else { '' }
        endpoint = if ($providerStatus.PSObject.Properties['endpoint']) { [string]$providerStatus.endpoint } else { '' }
        error = if ($providerStatus.PSObject.Properties['error']) { [string]$providerStatus.error } else { '' }
    }
    Write-ConversationHealth -Path $conversationHealthAbs -Payload $healthPayload
    if ($healthPayload.reachable) {
        Write-Log -Message ("Conversation provider ready | provider:{0} | model:{1}" -f $healthPayload.provider, $healthPayload.model) -LogPath $logAbs
    }
    else {
        Write-Log -Message ("Conversation provider unavailable | provider:{0} | endpoint:{1} | error:{2}" -f $healthPayload.provider, $healthPayload.endpoint, $healthPayload.error) -LogPath $logAbs -Level 'WARN'
    }
}
catch {
    Write-Log -Message ("Conversation provider probe failed: {0}" -f $_.Exception.Message) -LogPath $logAbs -Level 'WARN'
}

# ---------------------------------------------------------------------------
# Load System.Speech (built-in on Windows, no install required)
# ---------------------------------------------------------------------------

try {
    Add-Type -AssemblyName System.Speech
} catch {
    Write-Log -Message "ERROR: System.Speech assembly not available: $($_.Exception.Message)" -LogPath $logAbs -Level "ERROR"
    if (Test-Path -Path $pidAbs) { Remove-Item -Path $pidAbs -Force -ErrorAction SilentlyContinue }
    throw
}

$speechSynth = $null
$selectedVoiceName = ''
if ($speakEnabled) {
    try {
        $speechSynth = New-Object System.Speech.Synthesis.SpeechSynthesizer
        $speechSynth.Rate = $ttsRate
        $speechSynth.Volume = $ttsVolume
        $selectedVoiceName = Get-TodPreferredVoiceName -SpeechSynth $speechSynth -PreferredVoice $ttsPreferredVoice -PreferredCulture $ttsCulture
        if (-not [string]::IsNullOrWhiteSpace($selectedVoiceName)) {
            $speechSynth.SelectVoice($selectedVoiceName)
        }
        Write-Log -Message ("Speech voice ready | voice:{0} | rate:{1} | volume:{2} | ssml:{3}" -f $(if ([string]::IsNullOrWhiteSpace($selectedVoiceName)) { 'default' } else { $selectedVoiceName }), $ttsRate, $ttsVolume, $ttsUseSsml) -LogPath $logAbs
    } catch {
        Write-Log -Message "WARN: Speech synthesis unavailable: $($_.Exception.Message)" -LogPath $logAbs -Level "WARN"
        $speechSynth = $null
    }
}

# ---------------------------------------------------------------------------
# Build grammar: "<wake> <command>"
# e.g. "tod status", "hey tod refresh", "hi tod are you awake", ...
# ---------------------------------------------------------------------------

$defaultWakeVariants = @("tod", "todd", "hey tod", "hi tod", "okay tod", "hello tod", "hey todd", "hi todd", "hello todd")
$wakeVariants = if ($config.PSObject.Properties["wake_variants"] -and @($config.wake_variants).Count -gt 0) {
    @($config.wake_variants | ForEach-Object { [string]$_ })
} else {
    $defaultWakeVariants
}

$defaultCommands = @(
    "status", "check status", "what are you working on",
    "what are you working on right now", "what is your status", "what's your status", "status right now",
    "are you awake", "hello", "how are you doing", "health check",
    "are you there", "you awake",
    "give me a summary", "summary", "summarize", "quick summary", "what is the summary", "what's the summary",
    "refresh", "quick refresh",
    "refresh now",
    "stop", "pause",
    "hold",
    "resume", "continue",
    "carry on",
    "help", "what can you do"
)
$commandList = if ($config.PSObject.Properties["grammar"] -and
                   $config.grammar.PSObject.Properties["commands"] -and
                   @($config.grammar.commands).Count -gt 0) {
    @($config.grammar.commands | ForEach-Object { [string]$_ })
} else {
    $defaultCommands
}

try {
    $wakeChoices = New-Object System.Speech.Recognition.Choices
    foreach ($w in $wakeVariants) { $wakeChoices.Add([string]$w) }

    $cmdChoices = New-Object System.Speech.Recognition.Choices
    foreach ($c in $commandList) { $cmdChoices.Add([string]$c) }

    $gb = New-Object System.Speech.Recognition.GrammarBuilder($wakeChoices)
    $gb.Append($cmdChoices)
    $grammar = New-Object System.Speech.Recognition.Grammar($gb)
    $grammar.Name = "TODWakeCommand"
} catch {
    Write-Log -Message "ERROR building grammar: $($_.Exception.Message)" -LogPath $logAbs -Level "ERROR"
    if (Test-Path -Path $pidAbs) { Remove-Item -Path $pidAbs -Force -ErrorAction SilentlyContinue }
    throw
}

# ---------------------------------------------------------------------------
# Initialize recognition engine
# ---------------------------------------------------------------------------

try {
    $srEngine = New-Object System.Speech.Recognition.SpeechRecognitionEngine([System.Globalization.CultureInfo]::CurrentCulture)
    $srEngine.SetInputToDefaultAudioDevice()
    $srEngine.LoadGrammar($grammar)
    $dictationGrammar = New-Object System.Speech.Recognition.DictationGrammar
    $dictationGrammar.Name = "TODDictation"
    $srEngine.LoadGrammar($dictationGrammar)
    $srEngine.InitialSilenceTimeout = [TimeSpan]::Zero  # no timeout; keep listening
    $srEngine.BabbleTimeout         = [TimeSpan]::Zero
    $srEngine.EndSilenceTimeout     = [TimeSpan]::FromSeconds(0.8)
} catch {
    Write-Log -Message "ERROR initializing speech engine (no microphone?): $($_.Exception.Message)" -LogPath $logAbs -Level "ERROR"
    if (Test-Path -Path $pidAbs) { Remove-Item -Path $pidAbs -Force -ErrorAction SilentlyContinue }
    throw
}

# Two-stage event pattern: fires events into PS event queue, main loop consumes them.
# This lets the main script call all helper functions with full scope.
Register-ObjectEvent -InputObject $srEngine -EventName "SpeechRecognized"         -SourceIdentifier "TOD_SpeechRecognized"  | Out-Null
Register-ObjectEvent -InputObject $srEngine -EventName "SpeechRecognitionRejected" -SourceIdentifier "TOD_SpeechRejected"    | Out-Null

$srEngine.RecognizeAsync([System.Speech.Recognition.RecognizeMode]::Multiple)

Write-Log -Message "Listening. Say one of: $(($wakeVariants -join '|')) + <command>" -LogPath $logAbs
Write-Log -Message "Commands: $($commandList -join ' | ')" -LogPath $logAbs
Write-Host ""
Write-Host "  Wake phrases : $($wakeVariants -join ', ')" -ForegroundColor Cyan
Write-Host "  Commands     : $($commandList -join ', ')" -ForegroundColor Cyan
Write-Host "  Min conf     : $effectiveMinConf" -ForegroundColor Cyan
Write-Host "  Inbox        : $inboxAbs" -ForegroundColor Cyan
Write-Host "  Auto execute : $autoExecute" -ForegroundColor Cyan
Write-Host "  Speak reply  : $speakEnabled" -ForegroundColor Cyan
Write-Host "  Quiet mode   : $quietMode" -ForegroundColor Cyan
Write-Host "  Conversation : $script:conversationProvider" -ForegroundColor Cyan
Write-Host ""
Write-Host "Say 'tod status', 'hey tod refresh', 'hi tod are you awake', etc." -ForegroundColor Green
Write-Host "Press Ctrl+C to stop." -ForegroundColor DarkGray
Write-Host ""

# ---------------------------------------------------------------------------
# Main event loop
# ---------------------------------------------------------------------------

$heartbeatSec  = 60
$lastHeartbeat = [datetime]::UtcNow
$recognitions  = 0
$lastWakeTimestamp = [datetime]::MinValue
$lastConversationTimestamp = [datetime]::MinValue

try {
    while ($true) {

        # Check for a recognised phrase
        $e = Wait-Event -SourceIdentifier "TOD_SpeechRecognized" -Timeout 1 -ErrorAction SilentlyContinue
        if ($null -ne $e) {
            $result     = $e.SourceEventArgs.Result
            $confidence = [double]$result.Confidence
            $transcript = [string]$result.Text
            Remove-Event -EventIdentifier $e.EventIdentifier -ErrorAction SilentlyContinue

            if ($confidence -ge $effectiveMinConf -or $confidence -ge $wakeMinConfidence -or $confidence -ge $followUpMinConfidence -or $confidence -ge $directQueryMinConfidence) {
                $wakeParse = Split-WakeAndCommand -Transcript $transcript -WakeVariants $wakeVariants
                $hasWake = [bool]$wakeParse.is_wake
                $withinFollowUpWindow = (-not $hasWake) -and (($lastConversationTimestamp -ne [datetime]::MinValue) -and ((([datetime]::UtcNow - $lastConversationTimestamp).TotalSeconds) -le $followUpWindowSec))
                $directIntent = Get-IntentFromCommand -Command (Normalize-CommandForIntent -CommandText $transcript)
                $isDirectQuery = (Test-DirectQueryIntent -Intent $directIntent)

                if (-not $hasWake -and -not $withinFollowUpWindow -and -not $isDirectQuery) {
                    continue
                }

                if ($hasWake -and $confidence -lt $wakeMinConfidence) {
                    Write-Log -Message ("Wake confidence too low (conf:{0} < min:{1}) transcript:`"{2}`"" -f [Math]::Round($confidence, 2), [Math]::Round($wakeMinConfidence, 2), $transcript) -LogPath $logAbs
                    continue
                }

                if ((-not $hasWake) -and $confidence -lt $followUpMinConfidence) {
                    if (-not $isDirectQuery -or $confidence -lt $directQueryMinConfidence) {
                        Write-Log -Message ("Follow-up confidence too low (conf:{0} < min:{1}) transcript:`"{2}`"" -f [Math]::Round($confidence, 2), [Math]::Round($followUpMinConfidence, 2), $transcript) -LogPath $logAbs
                        continue
                    }
                }

                if ($hasWake) {
                    $lastWakeTimestamp = [datetime]::UtcNow
                    $lastConversationTimestamp = $lastWakeTimestamp
                }

                $commandPartRaw = if ($hasWake) { [string]$wakeParse.command } else { [string]$wakeParse.normalized }
                $commandPart = Normalize-CommandForIntent -CommandText $commandPartRaw

                $intent = if ($hasWake -or $withinFollowUpWindow) { Get-IntentFromCommand -Command $commandPart } else { $directIntent }
                if ($intent -eq 'command.request' -and -not (Test-UsefulOpenConversation -CommandText $commandPart -HasWake:$hasWake)) {
                    Write-Log -Message ("Discarding low-signal open conversation fragment: `"{0}`"" -f $transcript) -LogPath $logAbs
                    continue
                }
                $intentMinConfidence = Get-IntentConfidenceThreshold -Intent $intent -DefaultThreshold $effectiveMinConf -ThresholdMap $intentThresholds
                if ($confidence -lt $intentMinConfidence) {
                    Write-Log -Message ("Confidence below threshold for {0} (conf:{1} < min:{2}) transcript:`"{3}`"" -f $intent, [Math]::Round($confidence, 2), [Math]::Round($intentMinConfidence, 2), $transcript) -LogPath $logAbs
                    continue
                }

                $eventId = Write-VoiceEvent -Transcript $transcript -Intent $intent -Confidence $confidence `
                    -InboxPath $inboxAbs -TelemetryPath $telemetryAbs `
                    -LogPath $logAbs -SessionId $sessionId
                $recognitions++
                $lastConversationTimestamp = [datetime]::UtcNow

                if ($autoExecute -and ($intent.StartsWith("query.") -or $intent -eq "command.request")) {
                    $projectStatus = $null
                    $statusApiAvailable = $false
                    try {
                        $projectStatus = Invoke-RestMethod -Uri $statusApiUrl -Method Get -TimeoutSec 8
                        $statusApiAvailable = $true
                    } catch {
                        Write-Log -Message ("Voice status API unavailable: {0}" -f $_.Exception.Message) -LogPath $logAbs -Level "WARN"
                    }

                    try {
                        $replyText = Get-VoiceReplyText -Intent $intent -CommandText $commandPart -ProjectStatus $projectStatus
                        $responsePayload = [pscustomobject]@{
                            source = "tod-voice-listener"
                            timestamp_utc = (Get-Date).ToUniversalTime().ToString("o")
                            event_id = $eventId
                            transcript = $transcript
                            command = $commandPart
                            intent = $intent
                            status_api_url = $statusApiUrl
                            status_api_available = $statusApiAvailable
                            reply_text = $replyText
                            project_status = $projectStatus
                        }
                        $saved = Save-VoiceResponse -OutDir $outAbs -Payload $responsePayload
                        Write-Log -Message ("Voice response saved | intent:{0} | file:{1}" -f $intent, $saved) -LogPath $logAbs

                        if ($null -ne $speechSynth -and -not [string]::IsNullOrWhiteSpace($replyText)) {
                            try {
                                Emit-ConfirmationTone -LogPath $logAbs
                                $null = Invoke-TodSpeechReply -SpeechSynth $speechSynth -ReplyText $replyText -LogPath $logAbs -VoiceName $selectedVoiceName -Culture $ttsCulture -Rate $ttsRate -Pitch $ttsPitch -SentenceBreakMs $ttsSentenceBreakMs -Volume $ttsVolume -UseSsml $ttsUseSsml
                            } catch {
                                Write-Log -Message ("WARN: Failed to speak response: {0}" -f $_.Exception.Message) -LogPath $logAbs -Level "WARN"
                            }
                        }
                    } catch {
                        Write-Log -Message ("Voice response execution failed: {0}" -f $_.Exception.Message) -LogPath $logAbs -Level "WARN"
                    }
                }
            } else {
                Write-Log -Message ("Low-confidence ignored (conf:{0}): `"{1}`"" -f [Math]::Round($confidence, 2), $transcript) -LogPath $logAbs
            }
        }

        # Drain rejected events silently
        $re = Wait-Event -SourceIdentifier "TOD_SpeechRejected" -Timeout 0 -ErrorAction SilentlyContinue
        if ($null -ne $re) {
            Remove-Event -EventIdentifier $re.EventIdentifier -ErrorAction SilentlyContinue
        }

        # Periodic heartbeat
        $nowUtc = [datetime]::UtcNow
        if (($nowUtc - $lastHeartbeat).TotalSeconds -ge $heartbeatSec) {
            Write-Log -Message ("Heartbeat | recognitions:{0} | listening..." -f $recognitions) -LogPath $logAbs
            $lastHeartbeat = $nowUtc
        }
    }
} finally {
    Write-Log -Message "Stopping voice listener (recognitions this session: $recognitions)..." -LogPath $logAbs

    try { $srEngine.RecognizeAsyncStop() } catch { }
    try { $srEngine.Dispose()            } catch { }
    try { if ($null -ne $speechSynth) { $speechSynth.Dispose() } } catch { }

    Unregister-Event -SourceIdentifier "TOD_SpeechRecognized"  -ErrorAction SilentlyContinue
    Unregister-Event -SourceIdentifier "TOD_SpeechRejected"    -ErrorAction SilentlyContinue

    if (Test-Path -Path $pidAbs) {
        Remove-Item -Path $pidAbs -Force -ErrorAction SilentlyContinue
    }

    Write-Log -Message "Voice listener stopped." -LogPath $logAbs
}
