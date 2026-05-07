Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $repoRoot 'scripts/Invoke-TODMimLedgerPhaseACoverageReport.ps1'

Describe 'TOD-MIM Phase A coverage report' {
    It 'reports artifact-only request coverage when shadow evidence is absent' {
        $testRoot = Join-Path $repoRoot ('tod/out/tests/phase-a-coverage-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $runtimeShared = Join-Path $testRoot 'runtime/shared'
        New-Item -ItemType Directory -Path $runtimeShared -Force | Out-Null

        try {
            $requestArtifactPath = Join-Path $runtimeShared 'MIM_TOD_TASK_REQUEST.latest.json'
            $statusPath = Join-Path $runtimeShared 'TOD_MIM_LEDGER_OBSERVE_STATUS.latest.json'
            $reportPath = Join-Path $runtimeShared 'TOD_MIM_LEDGER_PHASE_A_COVERAGE.latest.json'

            @{
                request_id = 'REQ-TEST-001'
                task_id = 'objective-1-task-1'
            } | ConvertTo-Json -Depth 4 | Set-Content -Path $requestArtifactPath -Encoding utf8

            @{
                note = 'dry_run_only'
                ok = $true
            } | ConvertTo-Json -Depth 4 | Set-Content -Path $statusPath -Encoding utf8

            & $scriptPath -RuntimeSharedDir $runtimeShared -OutputPath $reportPath | Out-Null

            (Test-Path -Path $reportPath) | Should Be $true
            $report = Get-Content -Path $reportPath -Raw | ConvertFrom-Json

            [int]$report.expected.total | Should Be 6
            [int]$report.recorded.total | Should Be 1
            [double]$report.coverage_percent | Should Be 16.67
            $report.recorded.lifecycle_event_types | Should Contain 'request_observed'
            $report.recorded.missing_event_types | Should Contain 'ack_observed'
            $report.non_blocking_confirmed | Should Be $true
            $report.runtime_impact | Should Be 'none'
        }
        finally {
            Remove-Item -Path $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
