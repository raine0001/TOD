Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$simulationScript = Join-Path $repoRoot 'scripts/Invoke-TODMimExecutionSimulation.ps1'

function New-TestArea {
    $id = [guid]::NewGuid().ToString('N')
    $base = Join-Path $repoRoot ('tod/out/tests/tod-mim-execution-simulation-test-' + $id)
    New-Item -ItemType Directory -Path $base -Force | Out-Null
    return $base
}

function Get-Scenario {
    param(
        [Parameter(Mandatory = $true)]$Payload,
        [Parameter(Mandatory = $true)][string]$ScenarioName
    )

    return @($Payload.scenario_results | Where-Object { [string]$_.scenario -eq $ScenarioName } | Select-Object -First 1)[0]
}

Describe 'TOD MIM execution simulation harness' {
    It 'runs all synthetic execution scenarios and emits a passing summary' {
        $base = New-TestArea
        $payload = (& $simulationScript -Scenario all -OutputRoot $base) | ConvertFrom-Json

        [bool]$payload.ok | Should Be $true
        @($payload.scenario_results).Count | Should Be 5
        (Test-Path -Path (Join-Path $payload.root 'simulation-summary.json')) | Should Be $true
        (Test-Path -Path (Join-Path $payload.root 'simulation-summary.md')) | Should Be $true
    }

    It 'accepts one bounded request with one trigger ACK one task ACK and one RESULT' {
        $base = New-TestArea
        $payload = (& $simulationScript -Scenario accept_once -OutputRoot $base) | ConvertFrom-Json
        $scenario = Get-Scenario -Payload $payload -ScenarioName 'accept_once'

        [bool]$scenario.ok | Should Be $true
        [string]$scenario.steps[0].status | Should Be 'completed'
        [int]$scenario.counts.trigger_ack | Should Be 1
        [int]$scenario.counts.task_ack | Should Be 1
        [int]$scenario.counts.result | Should Be 1
    }

    It 'deduplicates duplicate semantic requests without emitting a second ACK or RESULT' {
        $base = New-TestArea
        $payload = (& $simulationScript -Scenario duplicate_request_dedup -OutputRoot $base) | ConvertFrom-Json
        $scenario = Get-Scenario -Payload $payload -ScenarioName 'duplicate_request_dedup'

        [bool]$scenario.ok | Should Be $true
        [string]$scenario.steps[1].status | Should Be 'already_processed'
        [int]$scenario.steps[1].emitted.trigger_ack | Should Be 0
        [int]$scenario.steps[1].emitted.task_ack | Should Be 0
        [int]$scenario.steps[1].emitted.result | Should Be 0
        [int]$scenario.counts.trigger_ack | Should Be 1
        [int]$scenario.counts.task_ack | Should Be 1
        [int]$scenario.counts.result | Should Be 1
    }

    It 'rejects stale backfill without emitting a task ACK' {
        $base = New-TestArea
        $payload = (& $simulationScript -Scenario stale_request_rejected -OutputRoot $base) | ConvertFrom-Json
        $scenario = Get-Scenario -Payload $payload -ScenarioName 'stale_request_rejected'

        [bool]$scenario.ok | Should Be $true
        [string]$scenario.steps[1].status | Should Be 'stale_request_ignored'
        [string]$scenario.steps[1].superseded_by_request_id | Should Be 'objective-303-task-005'
        [int]$scenario.steps[1].emitted.task_ack | Should Be 0
        [int]$scenario.steps[1].emitted.result | Should Be 1
    }

    It 'marks superseded replays as ignored against the newer authoritative request' {
        $base = New-TestArea
        $payload = (& $simulationScript -Scenario superseded_request_ignored -OutputRoot $base) | ConvertFrom-Json
        $scenario = Get-Scenario -Payload $payload -ScenarioName 'superseded_request_ignored'

        [bool]$scenario.ok | Should Be $true
        [string]$scenario.steps[2].status | Should Be 'stale_request_ignored'
        [string]$scenario.steps[2].superseded_by_request_id | Should Be 'objective-304-task-007'
        [int]$scenario.steps[2].emitted.task_ack | Should Be 0
    }

    It 'rejects wrong-target requests cleanly without emitting execution artifacts' {
        $base = New-TestArea
        $payload = (& $simulationScript -Scenario wrong_target_rejected -OutputRoot $base) | ConvertFrom-Json
        $scenario = Get-Scenario -Payload $payload -ScenarioName 'wrong_target_rejected'

        [bool]$scenario.ok | Should Be $true
        [string]$scenario.steps[0].status | Should Be 'wrong_target_rejected'
        [int]$scenario.counts.trigger_ack | Should Be 0
        [int]$scenario.counts.task_ack | Should Be 0
        [int]$scenario.counts.result | Should Be 0
    }
}