Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$gateScript = Join-Path $repoRoot "scripts/Check-TODRecouplingGate.ps1"

function New-RecouplingGateFixture {
    $id = [guid]::NewGuid().ToString("N")
    $base = Join-Path $repoRoot ("tod/out/tests/recoupling-gate-" + $id)
    $shared = Join-Path $base "shared_state"
    New-Item -ItemType Directory -Path $shared -Force | Out-Null

    $statePath = Join-Path $base "state.json"
    $integrationPath = Join-Path $shared "integration_status.json"
    $nextActionsPath = Join-Path $shared "next_actions.json"
    $outputPath = Join-Path $shared "tod_recoupling_gate_state.latest.json"

    $recentJournal = @(
        [pscustomobject]@{
            created_at = (Get-Date).ToUniversalTime().ToString("o")
            message = "recent activity"
        }
    )
    [pscustomobject]@{ journal = $recentJournal } | ConvertTo-Json -Depth 6 | Set-Content -Path $statePath
    [pscustomobject]@{ current_objective_in_progress = "75"; blockers = @() } | ConvertTo-Json -Depth 6 | Set-Content -Path $nextActionsPath

    return [pscustomobject]@{
        Base = $base
        SharedStateDir = $shared
        StatePath = $statePath
        IntegrationStatusPath = $integrationPath
        NextActionsPath = $nextActionsPath
        OutputPath = $outputPath
    }
}

function Invoke-RecouplingGate {
    param(
        [Parameter(Mandatory = $true)]$Fixture
    )

    $resultPath = Join-Path $Fixture.SharedStateDir "result.json"
    $command = @"
& '$($gateScript -replace "'", "''")' -SharedStateDir '$($Fixture.SharedStateDir -replace "'", "''")' -IntegrationStatusPath '$($Fixture.IntegrationStatusPath -replace "'", "''")' -NextActionsPath '$($Fixture.NextActionsPath -replace "'", "''")' -StatePath '$($Fixture.StatePath -replace "'", "''")' -OutputPath '$($Fixture.OutputPath -replace "'", "''")' -RequiredConsecutivePasses 1 | Set-Content -Path '$($resultPath -replace "'", "''")'
exit 0
"@
    & powershell -NoProfile -ExecutionPolicy Bypass -Command $command | Out-Null
    return ((Get-Content -Path $resultPath -Raw) | ConvertFrom-Json)
}

Describe "TOD Recoupling Gate" {
    It "fails when canonical refresh evidence is missing" {
        $fixture = New-RecouplingGateFixture
        $integration = [pscustomobject]@{
            compatible = $true
            mim_status = [pscustomobject]@{ objective_active = "75" }
            objective_alignment = [pscustomobject]@{ status = "in_sync"; tod_current_objective = "75"; mim_objective_active = "75" }
            mim_handshake = [pscustomobject]@{ available = $false }
            mim_refresh = [pscustomobject]@{
                attempted = $false
                copied_manifest = $false
                source_manifest = ""
                source_handshake_packet = ""
            }
        }
        $integration | ConvertTo-Json -Depth 8 | Set-Content -Path $fixture.IntegrationStatusPath

        $result = Invoke-RecouplingGate -Fixture $fixture
        $catchup = @($result.checks | Where-Object { [string]$_.name -eq "catchup_gate_pass" })[0]

        [string]$result.gate_status | Should Be "FAIL"
        [string]$catchup.status | Should Be "fail"
        @($catchup.refresh_evidence_failures).Count | Should BeGreaterThan 0
        ((@($catchup.refresh_evidence_failures) -contains "mim_refresh.attempted=false")) | Should Be $true
        ((@($catchup.refresh_evidence_failures) -contains "mim_handshake.available=false")) | Should Be $true
    }

    It "passes when canonical refresh evidence is present" {
        $fixture = New-RecouplingGateFixture
        $integration = [pscustomobject]@{
            compatible = $true
            mim_status = [pscustomobject]@{ objective_active = "75" }
            objective_alignment = [pscustomobject]@{ status = "in_sync"; tod_current_objective = "75"; mim_objective_active = "75" }
            mim_handshake = [pscustomobject]@{ available = $true }
            mim_refresh = [pscustomobject]@{
                attempted = $true
                copied_manifest = $true
                source_manifest = "E:/TOD/tod/out/context-sync/ssh-shared/MIM_MANIFEST.latest.json"
                source_handshake_packet = "E:/TOD/tod/out/context-sync/ssh-shared/MIM_TOD_HANDSHAKE_PACKET.latest.json"
            }
        }
        $integration | ConvertTo-Json -Depth 8 | Set-Content -Path $fixture.IntegrationStatusPath

        $result = Invoke-RecouplingGate -Fixture $fixture
        $catchup = @($result.checks | Where-Object { [string]$_.name -eq "catchup_gate_pass" })[0]

        [string]$result.gate_status | Should Be "PASS"
        [bool]$result.can_recoupple | Should Be $true
        [string]$catchup.status | Should Be "pass"
        @($catchup.refresh_evidence_failures).Count | Should Be 0
    }
}