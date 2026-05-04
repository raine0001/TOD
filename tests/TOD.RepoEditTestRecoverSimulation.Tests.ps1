Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $repoRoot 'scripts/Invoke-TODRepoEditTestRecoverSimulation.ps1'

Describe 'TOD repo edit test recover simulation' {
    It 'produces a simulation report with stage coverage and artifacts' {
        $fixture = Join-Path $repoRoot ('tod/out/tests/repo-edit-test-recover-' + [guid]::NewGuid().ToString('N'))
        try {
            New-Item -ItemType Directory -Path $fixture -Force | Out-Null

            $payload = (& $scriptPath -OutputRoot $fixture -EmitJson) | ConvertFrom-Json

            [string]$payload.source | Should Be 'tod-repo-edit-test-recover-simulation-v1'
            [int]$payload.summary.scenario_count | Should BeGreaterThan 0
            [double]$payload.summary.average_stage_coverage | Should BeGreaterThan 0.6
            [int]$payload.summary.test_ready_count | Should BeGreaterThan 0
            [int]$payload.summary.recovery_ready_count | Should BeGreaterThan 0
            (Test-Path -Path (Join-Path $fixture 'tod_repo_edit_test_recover.latest.json')) | Should Be $true

            $firstScenario = @($payload.scenarios)[0]
            [bool]($null -ne $firstScenario.loop_contract) | Should Be $true
            [bool](@($firstScenario.stage_checklist).Count -ge 4) | Should Be $true
        }
        finally {
            if (Test-Path -Path $fixture) {
                Remove-Item -Path $fixture -Recurse -Force
            }
        }
    }
}