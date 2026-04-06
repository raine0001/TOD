Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$validatorScript = Join-Path $repoRoot "scripts/Invoke-TODMimArmStateSummaryConsumptionValidation.ps1"
$consumerScript = Join-Path $repoRoot "scripts/mim_arm/tod_arm_state_consumer.py"
$pythonPath = Join-Path $repoRoot ".venv/Scripts/python.exe"

function New-MimArmStateFixture {
    $id = [guid]::NewGuid().ToString("N")
    $base = Join-Path $repoRoot ("tod/out/tests/mim-arm-state-" + $id)
    New-Item -ItemType Directory -Path $base -Force | Out-Null

    return [pscustomobject]@{
        Base = $base
        InputReceiptPath = Join-Path $base "serial_health_smoke.latest.json"
        SummaryPath = Join-Path $base "TOD_ARM_STATE_SUMMARY.latest.json"
        ValidationPath = Join-Path $base "arm_state_validation.json"
    }
}

Describe "TOD MIM ARM read-only state summary consumption" {
    It "accepts healthy arm state summaries for runtime awareness handoff" {
        (Test-Path -Path $validatorScript) | Should Be $true
        (Test-Path -Path $consumerScript) | Should Be $true
        (Test-Path -Path $pythonPath) | Should Be $true

        $fixture = New-MimArmStateFixture
        $receipt = [pscustomobject]@{
            captured_at_utc = "2026-03-30T01:43:25.244091+00:00"
            arm_state = [pscustomobject]@{
                status = "ok"
                app_alive = $true
                mode = "development"
                runtime = "sim"
                sim_enabled = $true
                camera = [pscustomobject]@{
                    status = "ok"
                    depthai_device_bound = $true
                    video_queue_ready = $true
                    detection_pipeline_enabled = $true
                    detection_stream_configured = $true
                    detections_queue_ready = $true
                    frame_counter = 12
                    last_frame_age_seconds = 0.11
                    detection_pipeline_error = $null
                }
                serial = [pscustomobject]@{
                    status = "ok"
                    serial_bound = $true
                    serial_ready = $true
                    controller_port = "/dev/ttyACM0"
                    controller_error = $null
                    last_serial_event = "ping_ok"
                    last_serial_event_at = "2026-03-30T01:43:25.702284+00:00"
                    last_serial_age_seconds = 0.12
                    serial_command_count = 3
                    serial_ack_count = 3
                    last_command_sent = "MOVE 0 115"
                    last_command_sent_at = "2026-03-30T01:42:20.100000+00:00"
                    last_command_ack_at = "2026-03-30T01:42:20.300000+00:00"
                }
                estop = [pscustomobject]@{
                    supported = $false
                    active = $null
                }
                current_pose = @(110, 62, 97, 90, 95, 91)
                last_error = $null
                last_command_result = [pscustomobject]@{
                    last_command_sent = "MOVE 0 115"
                    last_command_sent_at = "2026-03-30T01:42:20.100000+00:00"
                    last_command_ack_at = "2026-03-30T01:42:20.300000+00:00"
                    acks_total = 3
                    commands_total = 3
                }
            }
        }
        $receipt | ConvertTo-Json -Depth 20 | Set-Content -Path $fixture.InputReceiptPath

        $raw = & $validatorScript -RunConsumer -PythonPath $pythonPath -ConsumerScriptPath $consumerScript -InputReceiptPath $fixture.InputReceiptPath -SummaryPath $fixture.SummaryPath -OutputPath $fixture.ValidationPath
        $result = $raw | ConvertFrom-Json

        [bool]$result.state_summary_read.accepted | Should Be $true
        [bool]$result.state_summary_read.sha256_looks_valid | Should Be $true
        [bool]$result.contract_accepted.all | Should Be $true
        [bool]$result.current_state.app_alive | Should Be $true
        [bool]$result.current_state.serial_ready | Should Be $true
        [bool]$result.current_state.camera_ready | Should Be $true
        [bool]$result.mim_arm_interpretation_payload.ready_for_management | Should Be $true
        [string]$result.mim_arm_interpretation_payload.management_mode | Should Be "direct_runtime_awareness"
        [string]$result.mim_arm_interpretation_payload.update_payload.memory_key | Should Be "mim_arm.tod.read_state.latest"
    }

    It "keeps summaries observe-only when serial is not ready" {
        $fixture = New-MimArmStateFixture
        $receipt = [pscustomobject]@{
            captured_at_utc = "2026-03-30T01:43:25.244091+00:00"
            arm_state = [pscustomobject]@{
                status = "ok"
                app_alive = $true
                serial = [pscustomobject]@{
                    status = "ok"
                    serial_ready = $false
                }
            }
        }
        $receipt | ConvertTo-Json -Depth 20 | Set-Content -Path $fixture.InputReceiptPath

        $summary = [pscustomobject]@{
            generated_at = "2026-03-30T01:43:25.244091Z"
            source = "mim-arm-read-state-summary-v1"
            input_path = "tod/out/smoke/serial_health_smoke.latest.json"
            input_generated_at = "2026-03-30T01:43:25.244091+00:00"
            input_sha256 = ("a" * 64)
            app = [pscustomobject]@{ alive = $true; status = "ok" }
            runtime = [pscustomobject]@{ mode = "development"; runtime = "sim"; sim_enabled = $true }
            camera = [pscustomobject]@{
                status = "ok"
                depthai_device_bound = $true
                video_queue_ready = $true
                detection_pipeline_enabled = $true
                detection_stream_configured = $true
                detections_queue_ready = $true
                frame_counter = 0
                last_frame_age_seconds = $null
                detection_pipeline_error = $null
            }
            serial = [pscustomobject]@{
                status = "ok"
                serial_bound = $true
                serial_ready = $false
                controller_port = "/dev/ttyACM0"
                controller_error = "Serial unavailable"
                last_serial_event = "serial_not_ready"
                last_serial_event_at = "2026-03-30T01:43:25.702284+00:00"
                last_serial_age_seconds = 1.0
                serial_command_count = 0
                serial_ack_count = 0
                last_command_sent = $null
                last_command_sent_at = $null
                last_command_ack_at = $null
            }
            estop = [pscustomobject]@{ supported = $false; active = $null }
            pose = [pscustomobject]@{ available = $false; angles = @() }
            last_error = "Serial unavailable"
            last_command_result = [pscustomobject]@{
                last_command_sent = $null
                last_command_sent_at = $null
                last_command_ack_at = $null
                acks_total = 0
                commands_total = 0
            }
        }
        $summary | ConvertTo-Json -Depth 20 | Set-Content -Path $fixture.SummaryPath

        $raw = & $validatorScript -PythonPath $pythonPath -ConsumerScriptPath $consumerScript -InputReceiptPath $fixture.InputReceiptPath -SummaryPath $fixture.SummaryPath -OutputPath $fixture.ValidationPath
        $result = $raw | ConvertFrom-Json

        [bool]$result.contract_accepted.all | Should Be $true
        [bool]$result.current_state.serial_ready | Should Be $false
        [bool]$result.mim_arm_interpretation_payload.ready_for_management | Should Be $false
        [string]$result.mim_arm_interpretation_payload.management_mode | Should Be "observe_only"
    }
}
