Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot

function Write-TestJson {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Payload
    )
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $json = ($Payload | ConvertTo-Json -Depth 20) -replace "`r`n", "`n"
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $json + "`n", $utf8NoBom)
}

Describe 'Context sync truth repair' {
    It 'reports pending_result when latest request is newer than latest result' {
        $fixture = Join-Path $repoRoot ('tod/out/tests/context-sync-truth-repair-' + [guid]::NewGuid().ToString('N'))
        $listener = Join-Path $fixture 'listener'
        $requestPath = Join-Path $listener 'MIM_TOD_TASK_REQUEST.latest.json'
        $resultPath = Join-Path $listener 'TOD_MIM_TASK_RESULT.latest.json'
        $validationPath = Join-Path $listener 'MIM_CONTEXT_SYNC_DATA_ACCURACY_VALIDATION.latest.json'
        $syncStatusPath = Join-Path $fixture 'MIM_CONTEXT_SYNC_STATUS.latest.json'

        try {
            Write-TestJson -Path $requestPath -Payload ([pscustomobject]@{
                request_id = 'new-request'
                task_id = 'new-task'
                objective_id = 'new-objective'
                generated_at = '2026-07-14T02:52:00Z'
            })
            Write-TestJson -Path $resultPath -Payload ([pscustomobject]@{
                request_id = 'old-request'
                task_id = 'old-task'
                objective_id = 'old-objective'
                status = 'succeeded'
                generated_at = '2026-07-14T02:50:00Z'
            })

            & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'scripts/Repair-ContextSyncLatestTruth.ps1') -ContextSyncRoot $fixture -NoBackup | Out-Null

            $validation = Get-Content -Raw -LiteralPath $validationPath | ConvertFrom-Json
            $syncStatus = Get-Content -Raw -LiteralPath $syncStatusPath | ConvertFrom-Json

            [string]$validation.current_request_id | Should Be 'new-request'
            [string]$validation.current_task_id | Should Be 'new-task'
            [string]$validation.current_result_status | Should Be 'pending_result'
            [string]$validation.current_result_reason_code | Should Be 'latest_request_awaiting_terminal_result'
            [string]$validation.current_result_source | Should Be 'listener/MIM_TOD_TASK_REQUEST.latest.json'
            [bool]$validation.live_request_newer_than_result | Should Be $true
            [string]$validation.latest_result_request_id | Should Be 'old-request'
            [string]$syncStatus.latest_truth_repair.current_result_status | Should Be 'pending_result'
        }
        finally {
            if (Test-Path -LiteralPath $fixture) {
                Remove-Item -LiteralPath $fixture -Recurse -Force
            }
        }
    }

    It 'prefers matching runtime execution truth over stale listener task result status' {
        $fixture = Join-Path $repoRoot ('tod/out/tests/context-sync-truth-repair-' + [guid]::NewGuid().ToString('N'))
        $runtime = Join-Path $repoRoot ('tod/out/tests/context-sync-truth-runtime-' + [guid]::NewGuid().ToString('N'))
        $listener = Join-Path $fixture 'listener'
        $resultPath = Join-Path $listener 'TOD_MIM_TASK_RESULT.latest.json'
        $runtimeResultPath = Join-Path $runtime 'TOD_EXECUTION_RESULT.latest.json'
        $validationPath = Join-Path $listener 'MIM_CONTEXT_SYNC_DATA_ACCURACY_VALIDATION.latest.json'
        $syncStatusPath = Join-Path $fixture 'MIM_CONTEXT_SYNC_STATUS.latest.json'

        try {
            Write-TestJson -Path $resultPath -Payload ([pscustomobject]@{
                request_id = 'current-request'
                task_id = 'current-task'
                objective_id = 'current-objective'
                correlation_id = 'current-request'
                status = 'succeeded'
                generated_at = '2026-07-14T01:30:00Z'
            })
            Write-TestJson -Path $runtimeResultPath -Payload ([pscustomobject]@{
                request_id = 'current-request'
                task_id = 'current-task'
                objective_id = 'current-objective'
                status = 'blocked'
                reason_code = 'blocked_missing_bounded_edit_mode'
                generated_at = '2026-07-14T01:31:00Z'
            })

            & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'scripts/Repair-ContextSyncLatestTruth.ps1') -ContextSyncRoot $fixture -RuntimeSharedRoot $runtime -NoBackup | Out-Null

            $validation = Get-Content -Raw -LiteralPath $validationPath | ConvertFrom-Json
            $syncStatus = Get-Content -Raw -LiteralPath $syncStatusPath | ConvertFrom-Json

            [string]$validation.current_result_status | Should Be 'blocked'
            [string]$validation.current_result_reason_code | Should Be 'blocked_missing_bounded_edit_mode'
            [string]$validation.current_result_source | Should Be 'runtime/shared/TOD_EXECUTION_RESULT.latest.json'
            [bool]$validation.runtime_truth_conflict_detected | Should Be $true
            [string]$syncStatus.latest_truth_repair.current_result_status | Should Be 'blocked'
            [string]$syncStatus.latest_truth_repair.current_result_reason_code | Should Be 'blocked_missing_bounded_edit_mode'
        }
        finally {
            foreach ($path in @($fixture, $runtime)) {
                if (Test-Path -LiteralPath $path) {
                    Remove-Item -LiteralPath $path -Recurse -Force
                }
            }
        }
    }

    It 'does not overwrite canonical MIM_TO_TOD_TRIGGER latest files with status packets' {
        $fixture = Join-Path $repoRoot ('tod/out/tests/context-sync-truth-repair-' + [guid]::NewGuid().ToString('N'))
        $listener = Join-Path $fixture 'listener'
        $resultPath = Join-Path $listener 'TOD_MIM_TASK_RESULT.latest.json'
        $triggerPath = Join-Path $listener 'MIM_TO_TOD_TRIGGER.latest.json'
        $validationPath = Join-Path $listener 'MIM_CONTEXT_SYNC_DATA_ACCURACY_VALIDATION.latest.json'

        try {
            Write-TestJson -Path $resultPath -Payload ([pscustomobject]@{
                request_id = 'current-request'
                task_id = 'current-task'
                objective_id = 'current-objective'
                correlation_id = 'current-request'
                status = 'succeeded'
                generated_at = '2026-07-14T01:30:00Z'
            })
            Write-TestJson -Path $triggerPath -Payload ([pscustomobject]@{
                request_id = 'older-request'
                task_id = 'older-task'
                objective_id = 'older-objective'
                target = 'TOD'
                generated_at = '2026-07-14T01:00:00Z'
                source = 'mim'
            })

            & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'scripts/Repair-ContextSyncLatestTruth.ps1') -ContextSyncRoot $fixture -NoBackup | Out-Null

            $trigger = Get-Content -Raw -LiteralPath $triggerPath | ConvertFrom-Json
            $validation = Get-Content -Raw -LiteralPath $validationPath | ConvertFrom-Json
            $finding = @($validation.findings | Where-Object { [string]$_.file -eq 'MIM_TO_TOD_TRIGGER.latest.json' })[0]

            [string]$trigger.request_id | Should Be 'older-request'
            [string]$trigger.task_id | Should Be 'older-task'
            ($trigger.PSObject.Properties['packet_type'] -eq $null) | Should Be $true
            [string]$finding.classification | Should Be 'protected_control_plane_file_stale'
            [string]$finding.repair_action | Should Be 'finding_only'
        }
        finally {
            if (Test-Path -LiteralPath $fixture) {
                Remove-Item -LiteralPath $fixture -Recurse -Force
            }
        }
    }
}
