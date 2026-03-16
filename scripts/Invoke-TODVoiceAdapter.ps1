param(
    [ValidateSet("status", "describe-contract", "simulate-intent", "enqueue-intent")]
    [string]$Action = "status",
    [string]$ConfigPath = "tod/config/voice-adapter.json",
    [string]$SchemaPath = "tod/templates/voice/tod_voice_intent_event.schema.json",
    [string]$Transcript = "",
    [string]$Intent = "command.request",
    [double]$Confidence = 0.85,
    [string]$ObjectiveHint = "",
    [string]$SessionId = "",
    [string]$MetadataJson = "{}",
    [switch]$DryRun,
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

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

function Get-JsonIfExists {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -Path $Path)) { return $null }
    return (Get-Content -Path $Path -Raw | ConvertFrom-Json)
}

function Save-Json {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Path
    )

    Initialize-ParentDir -FilePath $Path
    $Object | ConvertTo-Json -Depth 30 | Set-Content -Path $Path -Encoding UTF8
}

function New-VoiceEvent {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][string]$InTranscript,
        [Parameter(Mandatory = $true)][string]$InIntent,
        [Parameter(Mandatory = $true)][double]$InConfidence,
        [string]$InObjectiveHint = "",
        [Parameter(Mandatory = $true)][string]$InSessionId,
        [Parameter(Mandatory = $true)]$InMetadata
    )

    $clampedConfidence = [Math]::Min(1.0, [Math]::Max(0.0, $InConfidence))
    $eventId = "voice-{0}" -f ([Guid]::NewGuid().ToString("N"))

    return [pscustomobject]@{
        event_type = "voice.intent"
        event_id = $eventId
        timestamp_utc = (Get-Date).ToUniversalTime().ToString("o")
        source = "tod-voice-adapter-v1"
        payload = [pscustomobject]@{
            transcript = [string]$InTranscript
            intent = [string]$InIntent
            confidence = [Math]::Round($clampedConfidence, 3)
            objective_hint = [string]$InObjectiveHint
            camera_used = $false
            metadata = [pscustomobject]@{
                session_id = [string]$InSessionId
                mode = if ($Config.PSObject.Properties["mode"]) { [string]$Config.mode } else { "dry_run" }
                capture_provider = if ($Config.capture -and $Config.capture.PSObject.Properties["provider"]) { [string]$Config.capture.provider } else { "none" }
                stt_provider = if ($Config.stt -and $Config.stt.PSObject.Properties["provider"]) { [string]$Config.stt.provider } else { "none" }
                user_metadata = $InMetadata
            }
        }
    }
}

function Write-VoiceStatus {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][string]$TelemetryPath,
        [Parameter(Mandatory = $true)]$LastEvent
    )

    $status = [pscustomobject]@{
        source = "tod-voice-adapter-v1"
        timestamp_utc = (Get-Date).ToUniversalTime().ToString("o")
        enabled = [bool]$Config.enabled
        allow_microphone = [bool]$Config.allow_microphone
        allow_camera = [bool]$Config.allow_camera
        mode = if ($Config.PSObject.Properties["mode"]) { [string]$Config.mode } else { "dry_run" }
        dry_run = $true
        last_event_id = if ($LastEvent) { [string]$LastEvent.event_id } else { "" }
        last_intent = if ($LastEvent) { [string]$LastEvent.payload.intent } else { "" }
        last_transcript = if ($LastEvent -and $LastEvent.payload.PSObject.Properties["transcript"]) { [string]$LastEvent.payload.transcript } else { "" }
    }

    Save-Json -Object $status -Path $TelemetryPath
    return $status
}

$cfgAbs = Get-LocalPath -PathValue $ConfigPath
$schemaAbs = Get-LocalPath -PathValue $SchemaPath

$config = Get-JsonIfExists -Path $cfgAbs
if ($null -eq $config) {
    throw "Voice adapter config not found: $cfgAbs"
}

$paths = if ($config.PSObject.Properties["paths"]) { $config.paths } else { $null }
$inboxRel = if ($paths -and $paths.PSObject.Properties["voice_inbox"]) { [string]$paths.voice_inbox } else { "tod/inbox/voice/events" }
$outRel = if ($paths -and $paths.PSObject.Properties["voice_out"]) { [string]$paths.voice_out } else { "tod/out/voice" }
$telemetryRel = if ($paths -and $paths.PSObject.Properties["telemetry"]) { [string]$paths.telemetry } else { "shared_state/voice_adapter_status.json" }
$inboxAbs = Get-LocalPath -PathValue $inboxRel
$outAbs = Get-LocalPath -PathValue $outRel
$telemetryAbs = Get-LocalPath -PathValue $telemetryRel

if (-not (Test-Path -Path $schemaAbs)) {
    throw "Voice event schema not found: $schemaAbs"
}

$effectiveDryRun = $true
if ($config.PSObject.Properties["mode"] -and [string]$config.mode -eq "dry_run") {
    $effectiveDryRun = $true
}
if ($DryRun) {
    $effectiveDryRun = $true
}

$metadata = @{}
if (-not [string]::IsNullOrWhiteSpace($MetadataJson)) {
    try {
        $metadata = $MetadataJson | ConvertFrom-Json
    }
    catch {
        throw "MetadataJson must be valid JSON object"
    }
}

if ([string]::IsNullOrWhiteSpace($SessionId)) {
    $SessionId = "voice-session-{0}" -f ((Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmmss"))
}

switch ($Action) {
    "status" {
        $payload = [pscustomobject]@{
            ok = $true
            source = "tod-voice-adapter-v1"
            action = "status"
            timestamp_utc = (Get-Date).ToUniversalTime().ToString("o")
            enabled = [bool]$config.enabled
            allow_microphone = [bool]$config.allow_microphone
            allow_camera = [bool]$config.allow_camera
            require_push_to_talk = [bool]$config.require_push_to_talk
            wake_phrase = if ($config.PSObject.Properties["wake_phrase"]) { [string]$config.wake_phrase } else { "tod" }
            mode = if ($config.PSObject.Properties["mode"]) { [string]$config.mode } else { "dry_run" }
            dry_run = $effectiveDryRun
            camera_active = $false
            microphone_active = $false
            paths = [pscustomobject]@{
                config = $cfgAbs
                schema = $schemaAbs
                voice_inbox = $inboxAbs
                voice_out = $outAbs
                telemetry = $telemetryAbs
            }
            note = "Scaffold only. No microphone or camera capture is enabled in this adapter."
        }

        if ($AsJson) {
            $payload | ConvertTo-Json -Depth 20
        }
        else {
            $payload
        }
        return
    }

    "describe-contract" {
        $schema = Get-Content -Path $schemaAbs -Raw | ConvertFrom-Json
        $payload = [pscustomobject]@{
            ok = $true
            source = "tod-voice-adapter-v1"
            action = "describe-contract"
            timestamp_utc = (Get-Date).ToUniversalTime().ToString("o")
            schema = $schema
            note = "Contract is for voice.intent events only; runtime capture remains disabled by design."
        }

        if ($AsJson) {
            $payload | ConvertTo-Json -Depth 30
        }
        else {
            $payload
        }
        return
    }

    "simulate-intent" {
        if ([string]::IsNullOrWhiteSpace($Transcript)) {
            throw "Transcript is required for simulate-intent"
        }

        $voiceEvent = New-VoiceEvent -Config $config -InTranscript $Transcript -InIntent $Intent -InConfidence $Confidence -InObjectiveHint $ObjectiveHint -InSessionId $SessionId -InMetadata $metadata
        $status = Write-VoiceStatus -Config $config -TelemetryPath $telemetryAbs -LastEvent $voiceEvent

        $payload = [pscustomobject]@{
            ok = $true
            source = "tod-voice-adapter-v1"
            action = "simulate-intent"
            timestamp_utc = (Get-Date).ToUniversalTime().ToString("o")
            dry_run = $true
            event = $voiceEvent
            adapter_status = $status
            note = "Simulation only. Event was not queued to inbox."
        }

        if ($AsJson) {
            $payload | ConvertTo-Json -Depth 30
        }
        else {
            $payload
        }
        return
    }

    "enqueue-intent" {
        if ([string]::IsNullOrWhiteSpace($Transcript)) {
            throw "Transcript is required for enqueue-intent"
        }

        $voiceEvent = New-VoiceEvent -Config $config -InTranscript $Transcript -InIntent $Intent -InConfidence $Confidence -InObjectiveHint $ObjectiveHint -InSessionId $SessionId -InMetadata $metadata

        $eventFile = Join-Path $inboxAbs ("{0}.json" -f $voiceEvent.event_id)
        Initialize-ParentDir -FilePath $eventFile
        Save-Json -Object $voiceEvent -Path $eventFile

        $status = Write-VoiceStatus -Config $config -TelemetryPath $telemetryAbs -LastEvent $voiceEvent

        $payload = [pscustomobject]@{
            ok = $true
            source = "tod-voice-adapter-v1"
            action = "enqueue-intent"
            timestamp_utc = (Get-Date).ToUniversalTime().ToString("o")
            dry_run = $effectiveDryRun
            queued_event_path = $eventFile
            event = $voiceEvent
            adapter_status = $status
            note = "Intent queued as file event only. No direct execution was triggered by this script."
        }

        if ($AsJson) {
            $payload | ConvertTo-Json -Depth 30
        }
        else {
            $payload
        }
        return
    }
}
