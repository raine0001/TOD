param(
    [string]$StageDir = "tod/out/context-sync/listener",
    [int]$RefreshSeconds = 2
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

function Get-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) { return $PathValue }
    return (Join-Path $repoRoot $PathValue)
}

function Read-JsonIfExists {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if (-not (Test-Path -Path $PathValue)) { return $null }
    try {
        return (Get-Content -Path $PathValue -Raw | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Get-TextOrDefault {
    param(
        [AllowNull()]$Value,
        [string]$Default = ""
    )

    if ($null -eq $Value) {
        return $Default
    }

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $Default
    }

    return $text
}

$stageAbs = Get-LocalPath -PathValue $StageDir
$requestPath = Join-Path $stageAbs "MIM_TOD_TASK_REQUEST.latest.json"
$ackPath = Join-Path $stageAbs "TOD_MIM_TASK_ACK.latest.json"
$resultPath = Join-Path $stageAbs "TOD_MIM_TASK_RESULT.latest.json"
$journalPath = Join-Path $stageAbs "TOD_LOOP_JOURNAL.latest.json"
$statePath = Join-Path $stageAbs "listener_state.json"

if (-not (Test-Path -Path $stageAbs)) {
    throw "Stage directory not found: $stageAbs"
}

Write-Host "TOD MIM Live Watch started. Press Ctrl+C to stop."

while ($true) {
    Clear-Host

    $now = (Get-Date).ToUniversalTime().ToString("o")
    $request = Read-JsonIfExists -PathValue $requestPath
    $ack = Read-JsonIfExists -PathValue $ackPath
    $result = Read-JsonIfExists -PathValue $resultPath
    $journal = Read-JsonIfExists -PathValue $journalPath
    $state = Read-JsonIfExists -PathValue $statePath

    $lastEntry = $null
    if ($journal -and $journal.PSObject.Properties["entries"]) {
        $entries = @($journal.entries)
        if (@($entries).Count -gt 0) {
            $lastEntry = @($entries | Select-Object -Last 1)[0]
        }
    }

    $requestId = if ($request) { Get-TextOrDefault -Value $request.task_id -Default "(none)" } else { "(none)" }
    $requestGeneratedAt = if ($request) { Get-TextOrDefault -Value $request.generated_at } else { "" }
    $requestTitle = if ($request -and $request.PSObject.Properties["title"]) { Get-TextOrDefault -Value $request.title } else { "" }

    $lastProcessedRequest = if ($state) { Get-TextOrDefault -Value $state.last_processed_request_id } else { "" }
    $lastCycleAt = if ($state) { Get-TextOrDefault -Value $state.last_cycle_at } else { "" }

    $ackRequestId = if ($ack) { Get-TextOrDefault -Value $ack.request_id } else { "" }
    $ackStatus = if ($ack) { Get-TextOrDefault -Value $ack.status } else { "" }
    $ackGeneratedAt = if ($ack) { Get-TextOrDefault -Value $ack.generated_at } else { "" }

    $resultRequestId = if ($result) { Get-TextOrDefault -Value $result.request_id } else { "" }
    $resultStatus = if ($result) { Get-TextOrDefault -Value $result.status } else { "" }
    $resultAction = if ($result) { Get-TextOrDefault -Value $result.action } else { "" }
    $resultGeneratedAt = if ($result) { Get-TextOrDefault -Value $result.generated_at } else { "" }
    $reviewGatePassed = if ($result -and $result.PSObject.Properties["review_gate"]) { [string][bool]$result.review_gate.passed } else { "" }
    $validatorPassed = if ($result -and $result.PSObject.Properties["validator"]) { [string][bool]$result.validator.passed } else { "" }

    $journalRequestId = if ($lastEntry) { Get-TextOrDefault -Value $lastEntry.request_id } else { "" }
    $journalExecutionStatus = if ($lastEntry) { Get-TextOrDefault -Value $lastEntry.execution_status } else { "" }
    $journalTimestamp = if ($lastEntry) { Get-TextOrDefault -Value $lastEntry.timestamp } else { "" }

    Write-Host "=== TOD <-> MIM LIVE VIEW ==="
    Write-Host ("now_utc:                 {0}" -f $now)
    Write-Host ""
    Write-Host "-- Incoming Request --"
    Write-Host ("request_id:              {0}" -f $requestId)
    Write-Host ("request_generated_at:     {0}" -f $requestGeneratedAt)
    Write-Host ("request_title:            {0}" -f $requestTitle)

    Write-Host ""
    Write-Host "-- Listener State --"
    Write-Host ("last_processed_request:   {0}" -f $lastProcessedRequest)
    Write-Host ("last_cycle_at:            {0}" -f $lastCycleAt)

    Write-Host ""
    Write-Host "-- Latest ACK --"
    Write-Host ("ack_request_id:           {0}" -f $ackRequestId)
    Write-Host ("ack_status:               {0}" -f $ackStatus)
    Write-Host ("ack_generated_at:         {0}" -f $ackGeneratedAt)

    Write-Host ""
    Write-Host "-- Latest Result --"
    Write-Host ("result_request_id:        {0}" -f $resultRequestId)
    Write-Host ("result_status:            {0}" -f $resultStatus)
    Write-Host ("result_action:            {0}" -f $resultAction)
    Write-Host ("result_generated_at:      {0}" -f $resultGeneratedAt)
    Write-Host ("review_gate_passed:       {0}" -f $reviewGatePassed)
    Write-Host ("validator_passed:         {0}" -f $validatorPassed)

    Write-Host ""
    Write-Host "-- Journal Tail --"
    Write-Host ("journal_request_id:       {0}" -f $journalRequestId)
    Write-Host ("journal_execution_status: {0}" -f $journalExecutionStatus)
    Write-Host ("journal_timestamp:        {0}" -f $journalTimestamp)

    Start-Sleep -Seconds $RefreshSeconds
}
