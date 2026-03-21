[CmdletBinding()]
param(
    [string]$Preset = "tod/config/media-presets/gloria-cowell.json",
    [string]$AvatarPath = "",
    [string]$Script = "",
    [string]$BackgroundPrompt = "",
    [string]$StatusPath = "tod/out/runpod-studio/status.json",
    [string]$LogPath = "tod/out/runpod-studio/render.log"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$runner = Join-Path $PSScriptRoot "Invoke-TODSpokesperson-RunPod.ps1"
$resolvedStatusPath = if ([System.IO.Path]::IsPathRooted($StatusPath)) { $StatusPath } else { Join-Path $repoRoot $StatusPath }
$resolvedLogPath = if ([System.IO.Path]::IsPathRooted($LogPath)) { $LogPath } else { Join-Path $repoRoot $LogPath }
$outputDir = Join-Path $repoRoot "tod\out\spokesperson"

function Write-StudioStatus {
    param([hashtable]$Data)

    $statusDir = Split-Path -Parent $resolvedStatusPath
    if ($statusDir) {
        New-Item -ItemType Directory -Force -Path $statusDir | Out-Null
    }

    $Data | ConvertTo-Json -Depth 8 | Set-Content -Path $resolvedStatusPath -Encoding UTF8
}

function Append-Log {
    param([string]$Line)

    $logDir = Split-Path -Parent $resolvedLogPath
    if ($logDir) {
        New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    }

    Add-Content -Path $resolvedLogPath -Value $Line -Encoding UTF8
}

if (-not (Test-Path $runner)) {
    throw "Missing runner script: $runner"
}

$startedAt = (Get-Date).ToUniversalTime().ToString("o")
if (Test-Path $resolvedLogPath) {
    Remove-Item -Path $resolvedLogPath -Force
}

$initialStatus = @{
    state = "running"
    preset = $Preset
    avatar_path = $AvatarPath
    script = $Script
    background_prompt = $BackgroundPrompt
    started_at = $startedAt
    finished_at = $null
    pid = $PID
    output = $null
    error = $null
}
Write-StudioStatus $initialStatus
Append-Log ("[{0}] Starting RunPod render with preset {1}" -f $startedAt, $Preset)
if (-not [string]::IsNullOrWhiteSpace($AvatarPath)) {
    Append-Log ("[{0}] Avatar override: {1}" -f $startedAt, $AvatarPath)
}
if (-not [string]::IsNullOrWhiteSpace($Script)) {
    Append-Log ("[{0}] Speech override length: {1} chars" -f $startedAt, $Script.Length)
}
if (-not [string]::IsNullOrWhiteSpace($BackgroundPrompt)) {
    Append-Log ("[{0}] Background prompt override length: {1} chars" -f $startedAt, $BackgroundPrompt.Length)
}

try {
    $invokeParams = @{ Preset = $Preset }
    if (-not [string]::IsNullOrWhiteSpace($AvatarPath)) { $invokeParams.AvatarPath = $AvatarPath }
    if (-not [string]::IsNullOrWhiteSpace($Script)) { $invokeParams.Script = $Script }
    if (-not [string]::IsNullOrWhiteSpace($BackgroundPrompt)) { $invokeParams.BackgroundPrompt = $BackgroundPrompt }

    & $runner @invokeParams *>&1 | ForEach-Object {
        $line = [string]$_
        Append-Log $line
    }

    $latestOutput = Get-ChildItem -Path $outputDir -Filter "*.mp4" -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTimeUtc -ge ([datetime]$startedAt) } |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1

    $finalStatus = @{
        state = "completed"
        preset = $Preset
        avatar_path = $AvatarPath
        script = $Script
        background_prompt = $BackgroundPrompt
        started_at = $startedAt
        finished_at = (Get-Date).ToUniversalTime().ToString("o")
        pid = $PID
        output = if ($latestOutput) { $latestOutput.FullName } else { $null }
        error = $null
    }
    Write-StudioStatus $finalStatus
    Append-Log ("[{0}] Render completed" -f $finalStatus.finished_at)
}
catch {
    $message = [string]$_.Exception.Message
    Append-Log ("[ERROR] " + $message)
    $failedStatus = @{
        state = "failed"
        preset = $Preset
        avatar_path = $AvatarPath
        script = $Script
        background_prompt = $BackgroundPrompt
        started_at = $startedAt
        finished_at = (Get-Date).ToUniversalTime().ToString("o")
        pid = $PID
        output = $null
        error = $message
    }
    Write-StudioStatus $failedStatus
    throw
}