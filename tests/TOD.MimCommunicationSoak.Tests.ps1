Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $repoRoot 'scripts/Invoke-TODMimCommunicationSimulationSoak.ps1'

function New-TestArea {
    $id = [guid]::NewGuid().ToString('N')
    $base = Join-Path $repoRoot ('tod/out/tests/tod-mim-communication-soak-test-' + $id)
    New-Item -ItemType Directory -Path $base -Force | Out-Null
    return $base
}

Describe 'TOD MIM communication simulation soak' {
    It 'runs repeated synthetic communication simulations with a perfect pass summary' {
        $base = New-TestArea
        $payload = (& $scriptPath -Iterations 5 -OutputRoot $base -FailOnFailure -EmitJson) | ConvertFrom-Json

        [bool]$payload.summary.strict_pass | Should Be $true
        [int]$payload.summary.iterations_completed | Should Be 5
        @($payload.scenario_success | Where-Object { -not [bool]$_.perfect }).Count | Should Be 0
        (Test-Path -Path (Join-Path $base 'tod-mim-communication-soak.latest.json')) | Should Be $true
        (Test-Path -Path (Join-Path $base 'tod-mim-communication-soak.latest.md')) | Should Be $true
    }
}