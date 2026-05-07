Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$simulationScript = Join-Path $repoRoot 'scripts/Invoke-TODDirectChatExecutionSimulation.ps1'

Describe 'TOD direct-chat execution simulation harness' {
    BeforeAll {
        $script:SimulationOutputRoot = Join-Path $repoRoot ('tod/out/tests/direct-chat-execution-pester-' + [guid]::NewGuid().ToString('N'))
        $raw = & $simulationScript -OutputRoot $script:SimulationOutputRoot -AsJson | Out-String
        $script:Simulation = $raw | ConvertFrom-Json
    }

    AfterAll {
        if (-not [string]::IsNullOrWhiteSpace($script:SimulationOutputRoot) -and (Test-Path -Path $script:SimulationOutputRoot)) {
            Remove-Item -Path $script:SimulationOutputRoot -Recurse -Force
        }
    }

    It 'passes all required direct-chat execution simulation cases in sandbox state' {
        [bool]$script:Simulation.passed | Should Be $true
        [int]$script:Simulation.scenario_count | Should Be 10
        [int]$script:Simulation.failed_count | Should Be 0
        [bool]$script:Simulation.shared_roots_sandboxed | Should Be $true
        [bool]$script:Simulation.production_shared_roots_modified | Should Be $false
    }

    It 'does not treat request publication as local execution start' {
        $publicationOnly = @($script:Simulation.scenarios | Where-Object { [string]$_.name -eq 'request publication without listener consumption' } | Select-Object -First 1)
        @($publicationOnly).Count | Should Be 1
        [bool]$publicationOnly[0].states.request_published | Should Be $true
        [bool]$publicationOnly[0].states.listener_consumed | Should Be $false
        [bool]$publicationOnly[0].states.local_execution_started | Should Be $false
    }

    It 'materializes and hands off a bounded validation-only direct-chat task' {
        $handoff = @($script:Simulation.scenarios | Where-Object { [string]$_.name -eq 'successful local execution handoff' } | Select-Object -First 1)
        @($handoff).Count | Should Be 1
        [bool]$handoff[0].states.slice_materialized | Should Be $true
        [bool]$handoff[0].states.local_execution_started | Should Be $true
        [bool]$handoff[0].states.local_execution_completed | Should Be $true
    }
}
