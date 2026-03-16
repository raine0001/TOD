param(
    [string]$AckPath = "E:\TOD\tod\out\context-sync\listener\MIM_TOD_COORDINATION_ACK.latest.json",
    [string]$EscalationPath = "E:\TOD\tod\out\context-sync\listener\TOD_MIM_COORDINATION_ESCALATION_STATE.latest.json",
    [string]$BuildStatePath = "E:\TOD\shared_state\current_build_state.json",
    [string]$LogPath = "E:\TOD\tod\out\watchers\mim-ack-regression-watch.jsonl",
    [int]$PollSeconds = 15
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logDir = Split-Path -Parent $LogPath
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
if (-not (Test-Path $LogPath)) {
    New-Item -ItemType File -Path $LogPath -Force | Out-Null
}

function Write-WatcherEvent {
    param(
        [Parameter(Mandatory = $true)][string]$Type,
        [Parameter(Mandatory = $true)][hashtable]$Payload
    )

    $event = [ordered]@{
        timestamp = (Get-Date).ToUniversalTime().ToString("o")
        type = $Type
    }
    foreach ($key in $Payload.Keys) {
        $event[$key] = $Payload[$key]
    }

    ($event | ConvertTo-Json -Compress -Depth 20) | Add-Content -Path $LogPath
}

$lastAck = ""
$lastEscalation = ""
$lastRegressionTimestamp = ""
$heartbeatEveryLoops = [math]::Max(1, [int][math]::Ceiling(300.0 / [math]::Max(1, [double]$PollSeconds)))
$loopCount = 0

Write-WatcherEvent -Type "watcher_started" -Payload @{
    ack_path = $AckPath
    escalation_path = $EscalationPath
    build_state_path = $BuildStatePath
    poll_seconds = $PollSeconds
    log_path = $LogPath
}

while ($true) {
    try {
        if (Test-Path $AckPath) {
            $ackRaw = Get-Content -Path $AckPath -Raw
            if ($ackRaw -ne $lastAck) {
                $lastAck = $ackRaw
                Write-WatcherEvent -Type "ack_changed" -Payload @{ raw = $ackRaw }
            }
        }

        if (Test-Path $EscalationPath) {
            $escalationRaw = Get-Content -Path $EscalationPath -Raw
            if ($escalationRaw -ne $lastEscalation) {
                $lastEscalation = $escalationRaw
                Write-WatcherEvent -Type "escalation_state_changed" -Payload @{ raw = $escalationRaw }
            }
        }

        if (Test-Path $BuildStatePath) {
            $build = Get-Content -Path $BuildStatePath -Raw | ConvertFrom-Json
            $regressionTimestamp = ""
            $passed = $null
            $failed = $null
            $total = $null
            if ($build.PSObject.Properties.Name -contains "last_regression_result" -and $null -ne $build.last_regression_result) {
                $regressionTimestamp = [string]$build.last_regression_result.generated_at
                $passed = $build.last_regression_result.passed
                $failed = $build.last_regression_result.failed
                $total = $build.last_regression_result.total
            }

            if ($regressionTimestamp -ne $lastRegressionTimestamp) {
                $lastRegressionTimestamp = $regressionTimestamp
                Write-WatcherEvent -Type "regression_snapshot_changed" -Payload @{
                    generated_at = $regressionTimestamp
                    passed = $passed
                    failed = $failed
                    total = $total
                }
            }
        }

        $loopCount += 1
        if (($loopCount % $heartbeatEveryLoops) -eq 0) {
            Write-WatcherEvent -Type "watcher_heartbeat" -Payload @{
                poll_seconds = $PollSeconds
                loop_count = $loopCount
                last_regression_generated_at = $lastRegressionTimestamp
            }
        }
    }
    catch {
        Write-WatcherEvent -Type "watcher_error" -Payload @{ message = [string]$_.Exception.Message }
    }

    Start-Sleep -Seconds $PollSeconds
}