param(
    [int]$CheckEverySeconds = 30,
    [int]$WriterLeaseSeconds = 600,
    [string]$WriterId = "tod-catchup-gate-watcher",
    [string]$SharedStateDir = "shared_state",
    [string]$GateScriptPath = "scripts/Check-TODRecouplingGate.ps1",
    [switch]$RunOnce
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$watcherId = "tod-catchup-gate-watcher-runner-v1"

function Get-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) { return $PathValue }
    return (Join-Path $repoRoot $PathValue)
}

function Read-JsonFileIfExists {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if (-not (Test-Path -Path $PathValue)) { return $null }
    try {
        return (Get-Content -Path $PathValue -Raw | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)]$Payload,
        [int]$Depth = 20
    )

    $dir = Split-Path -Parent $PathValue
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $json = ($Payload | ConvertTo-Json -Depth $Depth) -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($PathValue, $json, $utf8NoBom)
}

function Add-JsonLine {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)]$Payload
    )

    $dir = Split-Path -Parent $PathValue
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $line = (($Payload | ConvertTo-Json -Depth 20 -Compress) + "`n")
    [System.IO.File]::AppendAllText($PathValue, $line, $utf8NoBom)
}

$sharedAbs = Get-LocalPath -PathValue $SharedStateDir
$gateScriptAbs = Get-LocalPath -PathValue $GateScriptPath
$watcherStatePath = Join-Path $sharedAbs "tod_catchup_gate_watcher.latest.json"
$watcherLogPath = Join-Path $sharedAbs "tod_catchup_gate_watcher.log.jsonl"
$mutexName = "Global\TOD-CatchupGateWatcher"

if (-not (Test-Path -Path $sharedAbs)) {
    New-Item -ItemType Directory -Path $sharedAbs -Force | Out-Null
}

if (-not (Test-Path -Path $gateScriptAbs)) {
    throw "Missing gate script: $gateScriptAbs"
}

$mutex = New-Object System.Threading.Mutex($false, $mutexName)
$hasHandle = $false

try {
    $hasHandle = $mutex.WaitOne(0)
    if (-not $hasHandle) {
        $stateDoc = [pscustomobject]@{
            generated_at = (Get-Date).ToUniversalTime().ToString("o")
            source = $watcherId
            writer_id = $WriterId
            status = "skipped"
            reason = "instance_already_running"
            mutex = $mutexName
            pid = $PID
        }
        Write-JsonFile -PathValue $watcherStatePath -Payload $stateDoc
        $stateDoc | ConvertTo-Json -Depth 10 | Write-Output
        return
    }

    Write-Host ("[TOD-CATCHUP-WATCHER] Started. writer={0} interval={1}s run_once={2}" -f $WriterId, $CheckEverySeconds, [bool]$RunOnce)

    while ($true) {
        $startedAt = (Get-Date).ToUniversalTime().ToString("o")
        $exitCode = 0
        $gateResult = $null
        $errorText = ""

        try {
            & $gateScriptAbs -WriterId $WriterId -WriterLeaseSeconds $WriterLeaseSeconds 2>&1 | Tee-Object -Variable gateOutput | Out-Null
            $exitCode = if ($LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
            $gateText = [string]($gateOutput | Out-String)
            $gateResult = $gateText | ConvertFrom-Json -ErrorAction SilentlyContinue
        }
        catch {
            $exitCode = 99
            $errorText = [string]$_.Exception.Message
        }

        $stateDoc = [pscustomobject]@{
            generated_at = (Get-Date).ToUniversalTime().ToString("o")
            source = $watcherId
            writer_id = $WriterId
            pid = $PID
            mutex = $mutexName
            interval_seconds = $CheckEverySeconds
            run_once = [bool]$RunOnce
            status = if ($exitCode -eq 99) { "error" } elseif ($gateResult -and $gateResult.PSObject.Properties["write_skipped"] -and [bool]$gateResult.write_skipped) { "backoff" } else { "ok" }
            gate_exit_code = $exitCode
            gate_status = if ($gateResult -and $gateResult.PSObject.Properties["gate_status"]) { [string]$gateResult.gate_status } else { "" }
            can_recoupple = if ($gateResult -and $gateResult.PSObject.Properties["can_recoupple"]) { [bool]$gateResult.can_recoupple } else { $false }
            write_skipped = if ($gateResult -and $gateResult.PSObject.Properties["write_skipped"]) { [bool]$gateResult.write_skipped } else { $false }
            write_skip_reason = if ($gateResult -and $gateResult.PSObject.Properties["write_skip_reason"]) { [string]$gateResult.write_skip_reason } else { "" }
            active_writer = if ($gateResult -and $gateResult.PSObject.Properties["active_writer"]) { $gateResult.active_writer } else { $null }
            error = $errorText
            started_at = $startedAt
        }

        Write-JsonFile -PathValue $watcherStatePath -Payload $stateDoc
        Add-JsonLine -PathValue $watcherLogPath -Payload $stateDoc

        if ($RunOnce) {
            break
        }

        Start-Sleep -Seconds $CheckEverySeconds
    }
}
finally {
    if ($hasHandle) {
        $mutex.ReleaseMutex() | Out-Null
    }
    $mutex.Dispose()
}

Write-Host "[TOD-CATCHUP-WATCHER] Stopped."