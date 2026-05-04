Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$simulationScript = Join-Path $repoRoot 'scripts/Invoke-TODMimConversationSimulation.ps1'

function New-TestArea {
    $id = [guid]::NewGuid().ToString('N')
    $base = Join-Path $repoRoot ("tod/out/tests/tod-mim-conversation-simulation-test-" + $id)
    New-Item -ItemType Directory -Path $base -Force | Out-Null
    return $base
}

Describe 'TOD MIM conversation simulation harness' {
    It 'runs all synthetic scenarios and emits a passing summary' {
        $base = New-TestArea
        $payload = (& $simulationScript -Scenario all -OutputRoot $base) | ConvertFrom-Json

        [bool]$payload.ok | Should Be $true
        @($payload.scenario_results).Count | Should Be 7
        (Test-Path -Path (Join-Path $payload.root 'simulation-summary.json')) | Should Be $true
        (Test-Path -Path (Join-Path $payload.root 'simulation-summary.md')) | Should Be $true
    }

    It 'produces consensus_ready for the next-step consensus roundtrip' {
        $base = New-TestArea
        $payload = (& $simulationScript -Scenario next_step_consensus_roundtrip -OutputRoot $base) | ConvertFrom-Json
        $scenario = @($payload.scenario_results | Select-Object -First 1)[0]

        [bool]$payload.ok | Should Be $true
        [string]$scenario.first_status | Should Be 'pending_mim'
        [string]$scenario.second_status | Should Be 'consensus_ready'
        [string]$scenario.selected_finding_id | Should Be 'simulation-next-step-finding-001'
    }

    It 'acknowledges emergency assistance without leaving the session hanging' {
        $base = New-TestArea
        $payload = (& $simulationScript -Scenario emergency_assistance_roundtrip -OutputRoot $base) | ConvertFrom-Json
        $scenario = @($payload.scenario_results | Select-Object -First 1)[0]

        [bool]$payload.ok | Should Be $true
        [string]$scenario.scenario | Should Be 'emergency_assistance_roundtrip'
        [string]$scenario.final_status | Should Be 'closed'
        [int]$scenario.inbox_count | Should Be 1
    }
}