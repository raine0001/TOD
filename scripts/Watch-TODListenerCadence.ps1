param(
    [int]$IntervalSeconds = 30,
    [int]$MaxIterations = 0,
    [int]$SampleSize = 60,
    [int]$WarningCycleSec = 180,
    [int]$CriticalCycleSec = 300,
    [int]$WarningSyncDelta = 1,
    [int]$CriticalSyncDelta = 3,
    [double]$WarningRetryRate = 0.60,
    [switch]$JsonOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($IntervalSeconds -lt 1) {
    throw "IntervalSeconds must be >= 1"
}
if ($MaxIterations -lt 0) {
    throw "MaxIterations must be >= 0"
}
if ($SampleSize -lt 5) {
    throw "SampleSize must be >= 5"
}
if ($WarningCycleSec -lt 30 -or $CriticalCycleSec -lt $WarningCycleSec) {
    throw "Cycle thresholds invalid (require CriticalCycleSec >= WarningCycleSec >= 30)"
}
if ($WarningSyncDelta -lt 0 -or $CriticalSyncDelta -lt $WarningSyncDelta) {
    throw "Sync thresholds invalid (require CriticalSyncDelta >= WarningSyncDelta >= 0)"
}
if ($WarningRetryRate -lt 0 -or $WarningRetryRate -gt 1) {
    throw "WarningRetryRate must be between 0 and 1"
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$listenerRoot = Join-Path $repoRoot "tod/out/context-sync/listener"
$requestPath = Join-Path $listenerRoot "MIM_TOD_TASK_REQUEST.latest.json"
$resultPath = Join-Path $listenerRoot "TOD_MIM_TASK_RESULT.latest.json"
$journalPath = Join-Path $listenerRoot "TOD_LOOP_JOURNAL.latest.json"

function Read-JsonFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PathValue,
        [int]$Retries = 3,
        [int]$RetryMs = 150
    )

    if (-not (Test-Path -Path $PathValue)) {
        throw "Missing file: $PathValue"
    }

    $lastError = $null
    for ($attempt = 1; $attempt -le $Retries; $attempt += 1) {
        try {
            $raw = Get-Content -Path $PathValue -Raw
            if ([string]::IsNullOrWhiteSpace($raw)) {
                throw "Empty JSON payload: $PathValue"
            }
            return ($raw | ConvertFrom-Json)
        }
        catch {
            $lastError = $_
            if ($attempt -lt $Retries) {
                Start-Sleep -Milliseconds $RetryMs
            }
        }
    }

    throw $lastError
}

function Parse-TaskInfo {
    param([string]$TaskId)

    if ([string]::IsNullOrWhiteSpace($TaskId)) {
        return $null
    }

    $match = [regex]::Match($TaskId, 'objective-(\d+)-task-(\d+)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) {
        return $null
    }

    return [pscustomobject]@{
        objective = [int]$match.Groups[1].Value
        task = [int]$match.Groups[2].Value
        raw = $TaskId
    }
}

function Get-Percentile {
    param(
        [double[]]$Values,
        [double]$Percentile
    )

    if (-not $Values -or $Values.Count -eq 0) {
        return 0
    }

    $sorted = $Values | Sort-Object
    $idx = [math]::Floor(($Percentile / 100.0) * ($sorted.Count - 1))
    return [math]::Round([double]$sorted[$idx], 1)
}

function Get-Severity {
    param(
        [double]$LoopIdleSec,
        [int]$TaskDelta,
        [double]$RetryRate
    )

    $alerts = New-Object System.Collections.Generic.List[string]
    $severity = "ok"

    if ($LoopIdleSec -gt $CriticalCycleSec) {
        $alerts.Add("loop_idle>${CriticalCycleSec}s")
        $severity = "critical"
    }
    elseif ($LoopIdleSec -gt $WarningCycleSec) {
        $alerts.Add("loop_idle>${WarningCycleSec}s")
        if ($severity -ne "critical") { $severity = "warning" }
    }

    if ($TaskDelta -gt $CriticalSyncDelta) {
        $alerts.Add("sync_delta>${CriticalSyncDelta}")
        $severity = "critical"
    }
    elseif ($TaskDelta -gt $WarningSyncDelta) {
        $alerts.Add("sync_delta>${WarningSyncDelta}")
        if ($severity -ne "critical") { $severity = "warning" }
    }

    if ($RetryRate -gt $WarningRetryRate) {
        $alerts.Add("retry_rate>{0:p0}" -f $WarningRetryRate)
        if ($severity -eq "ok") { $severity = "warning" }
    }

    if ($alerts.Count -eq 0) {
        $alerts.Add("none")
    }

    return [pscustomobject]@{
        severity = $severity
        alerts = @($alerts)
    }
}

$iteration = 0
Write-Host ("[TOD-CADENCE-WATCH] started interval={0}s sample={1} warning={2}s critical={3}s" -f $IntervalSeconds, $SampleSize, $WarningCycleSec, $CriticalCycleSec)

while ($true) {
    $iteration += 1
    $now = [DateTimeOffset]::UtcNow

    try {
        $request = Read-JsonFile -PathValue $requestPath
        $result = Read-JsonFile -PathValue $resultPath
        $journalObj = Read-JsonFile -PathValue $journalPath
        $entries = if ($journalObj.PSObject.Properties['entries']) { @($journalObj.entries) } else { @($journalObj) }

        $recent = $entries |
            Where-Object { $_.timestamp -and $_.request_id } |
            Sort-Object { [DateTimeOffset]::Parse($_.timestamp) } |
            Select-Object -Last $SampleSize

        $times = @($recent | ForEach-Object { [DateTimeOffset]::Parse($_.timestamp) })
        $intervals = New-Object System.Collections.Generic.List[double]
        for ($i = 1; $i -lt $times.Count; $i += 1) {
            $intervals.Add(($times[$i] - $times[$i - 1]).TotalSeconds)
        }

        $requestInfo = Parse-TaskInfo -TaskId ([string]$request.task_id)
        $resultInfo = Parse-TaskInfo -TaskId ([string]$result.request_id)
        $taskDelta = 0
        if ($requestInfo -and $resultInfo) {
            $taskDelta = [math]::Abs($requestInfo.task - $resultInfo.task)
        }

        $requestTs = [DateTimeOffset]::Parse([string]$request.generated_at)
        $resultTs = [DateTimeOffset]::Parse([string]$result.generated_at)
        $lastJournalTs = if ($times.Count -gt 0) { $times[$times.Count - 1] } else { $resultTs }

        $requestAgeSec = [math]::Round(($now - $requestTs).TotalSeconds, 1)
        $resultAgeSec = [math]::Round(($now - $resultTs).TotalSeconds, 1)
        $loopIdleSec = [math]::Round(($now - $lastJournalTs).TotalSeconds, 1)

        $requestIds = @($recent | ForEach-Object { [string]$_.request_id })
        $uniqueRequestCount = (@($requestIds | Sort-Object -Unique)).Count
        $retryRate = if ($requestIds.Count -gt 0) {
            [math]::Round((($requestIds.Count - $uniqueRequestCount) / [double]$requestIds.Count), 3)
        }
        else {
            0
        }

        $avgSec = if ($intervals.Count -gt 0) { [math]::Round((($intervals | Measure-Object -Average).Average), 1) } else { 0 }
        $p50Sec = Get-Percentile -Values ([double[]]$intervals.ToArray()) -Percentile 50
        $p95Sec = Get-Percentile -Values ([double[]]$intervals.ToArray()) -Percentile 95

        $sev = Get-Severity -LoopIdleSec $loopIdleSec -TaskDelta $taskDelta -RetryRate $retryRate
        $aligned = ($taskDelta -eq 0)

        $snapshot = [pscustomobject]@{
            timestamp_utc = $now.ToString("o")
            iteration = $iteration
            severity = $sev.severity
            alerts = $sev.alerts
            stream = [pscustomobject]@{
                aligned = $aligned
                task_delta = $taskDelta
                request_task = [string]$request.task_id
                result_task = [string]$result.request_id
                result_status = [string]$result.status
                request_age_sec = $requestAgeSec
                result_age_sec = $resultAgeSec
                loop_idle_sec = $loopIdleSec
            }
            cadence = [pscustomobject]@{
                sample_size = $intervals.Count
                avg_sec = $avgSec
                p50_sec = $p50Sec
                p95_sec = $p95Sec
                retry_rate = $retryRate
            }
        }

        if (-not $JsonOnly) {
            Write-Host (
                "[{0}] sev={1} req={2} res={3} status={4} idle={5}s avg={6}s p95={7}s retry={8:p0} alerts={9}" -f
                (Get-Date -Format "HH:mm:ss"),
                $snapshot.severity,
                $snapshot.stream.request_task,
                $snapshot.stream.result_task,
                $snapshot.stream.result_status,
                $snapshot.stream.loop_idle_sec,
                $snapshot.cadence.avg_sec,
                $snapshot.cadence.p95_sec,
                $snapshot.cadence.retry_rate,
                (($snapshot.alerts -join ","))
            )
        }

        $snapshot | ConvertTo-Json -Depth 6 -Compress
    }
    catch {
        $errorPayload = [pscustomobject]@{
            timestamp_utc = [DateTimeOffset]::UtcNow.ToString("o")
            iteration = $iteration
            severity = "critical"
            alerts = @("watch_exception")
            error = $_.Exception.Message
        }

        if (-not $JsonOnly) {
            Write-Host ("[{0}] sev=critical watch_exception={1}" -f (Get-Date -Format "HH:mm:ss"), $_.Exception.Message)
        }
        $errorPayload | ConvertTo-Json -Depth 4 -Compress
    }

    if ($MaxIterations -gt 0 -and $iteration -ge $MaxIterations) {
        break
    }

    Start-Sleep -Seconds $IntervalSeconds
}
