Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$validatorScript = Join-Path $repoRoot "scripts/Invoke-TODMimArmAuthoritySummaryConsumptionValidation.ps1"
$consumerScript = Join-Path $repoRoot "scripts/mim_arm/tod_authority_consumer.py"
$pythonPath = Join-Path $repoRoot ".venv/Scripts/python.exe"

function New-MimArmAuthorityFixture {
    $id = [guid]::NewGuid().ToString("N")
    $base = Join-Path $repoRoot ("tod/out/tests/mim-arm-authority-" + $id)
    New-Item -ItemType Directory -Path $base -Force | Out-Null

    return [pscustomobject]@{
        Base = $base
        IntegrationStatusPath = Join-Path $base "integration_status.json"
        SummaryPath = Join-Path $base "TOD_AUTHORITY_SUMMARY.latest.json"
        ValidationPath = Join-Path $base "authority_validation.json"
    }
}

Describe "TOD MIM ARM authority summary consumption" {
    It "accepts uploaded aligned authority summaries for management handoff" {
        (Test-Path -Path $validatorScript) | Should Be $true
        (Test-Path -Path $consumerScript) | Should Be $true
        (Test-Path -Path $pythonPath) | Should Be $true

        $fixture = New-MimArmAuthorityFixture
        $integration = [pscustomobject]@{
            generated_at = "2026-03-29T20:24:12.4849888Z"
            compatible = $true
            compatibility_reason = "contract_version_match"
            objective_alignment = [pscustomobject]@{
                tod_current_objective = "97"
                mim_objective_active = "97"
                aligned = $true
                status = "in_sync"
                mim_objective_source = "live_task_request"
            }
            tod_status_publish = [pscustomobject]@{
                status = "uploaded"
                enabled = $true
                uploaded_at = "2026-03-29T20:24:12.4849888Z"
            }
            mim_status = [pscustomobject]@{
                available = $true
                phase = "execution"
                is_stale = $false
                generated_at = "2026-03-29T20:24:10.0000000Z"
            }
            live_task_request = [pscustomobject]@{
                request_id = "objective-97-task-0001"
            }
        }
        $integration | ConvertTo-Json -Depth 20 | Set-Content -Path $fixture.IntegrationStatusPath

        $raw = & $validatorScript -RunConsumer -PythonPath $pythonPath -ConsumerScriptPath $consumerScript -IntegrationStatusPath $fixture.IntegrationStatusPath -SummaryPath $fixture.SummaryPath -OutputPath $fixture.ValidationPath
        $result = $raw | ConvertFrom-Json

        [bool]$result.authority_summary_read.accepted | Should Be $true
        [bool]$result.authority_summary_read.sha256_looks_valid | Should Be $true
        [bool]$result.contract_accepted.all | Should Be $true
        [string]$result.authority_state.status | Should Be "uploaded"
        [bool]$result.authority_state.enabled | Should Be $true
        [bool]$result.authority_state.compatible | Should Be $true
        [bool]$result.objective_state.aligned | Should Be $true
        [string]$result.objective_state.alignment_source | Should Be "live_task_request"
        [bool]$result.mim_arm_interpretation_payload.ready_for_management | Should Be $true
        [string]$result.mim_arm_interpretation_payload.management_mode | Should Be "direct_tod_authority"
        [string]$result.mim_arm_interpretation_payload.update_payload.memory_key | Should Be "mim_arm.tod.authority.latest"
        [string]$result.mim_arm_interpretation_payload.update_payload.live_request_id | Should Be "objective-97-task-0001"
    }

    It "keeps summaries observe-only when authority is not uploaded" {
        $fixture = New-MimArmAuthorityFixture
        $summary = [pscustomobject]@{
            generated_at = "2026-03-29T20:24:12.4849888Z"
            source = "mim-arm-tod-authority-summary-v1"
            input_path = "/home/testpilot/mim_arm/runtime/shared/TOD_INTEGRATION_STATUS.latest.json"
            input_generated_at = "2026-03-29T20:24:12.4849888Z"
            input_sha256 = ("a" * 64)
            authority = [pscustomobject]@{
                status = "pending"
                enabled = $true
                uploaded_at = ""
                compatible = $true
                compatibility_reason = "contract_version_match"
            }
            objective = [pscustomobject]@{
                tod_current = "97"
                mim_current = "97"
                aligned = $true
                alignment_status = "in_sync"
                alignment_source = "live_task_request"
                live_request_id = "objective-97-task-0002"
            }
            mim_status = [pscustomobject]@{
                available = $true
                phase = "execution"
                is_stale = $false
                generated_at = "2026-03-29T20:24:10.0000000Z"
            }
        }
        $summary | ConvertTo-Json -Depth 20 | Set-Content -Path $fixture.SummaryPath
        '{}' | Set-Content -Path $fixture.IntegrationStatusPath

        $raw = & $validatorScript -PythonPath $pythonPath -ConsumerScriptPath $consumerScript -IntegrationStatusPath $fixture.IntegrationStatusPath -SummaryPath $fixture.SummaryPath -OutputPath $fixture.ValidationPath
        $result = $raw | ConvertFrom-Json

        [bool]$result.contract_accepted.all | Should Be $true
        [string]$result.authority_state.status | Should Be "pending"
        [bool]$result.mim_arm_interpretation_payload.ready_for_management | Should Be $false
        [string]$result.mim_arm_interpretation_payload.management_mode | Should Be "observe_only"
    }
}