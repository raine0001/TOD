param(
    [switch]$RunConsumer,
    [string]$PythonPath = ".venv/Scripts/python.exe",
    [string]$ConsumerScriptPath = "scripts/mim_arm/tod_arm_state_consumer.py",
    [string]$InputReceiptPath = "tod/out/smoke/serial_health_smoke.latest.json",
    [string]$SummaryPath = "shared_state/TOD_ARM_STATE_SUMMARY.latest.json",
    [string]$OutputPath = "shared_state/mim_arm_state_summary_consumption_validation.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

function Get-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) { return $PathValue }
    return (Join-Path $repoRoot $PathValue)
}

function Test-HasProperties {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string[]]$PropertyNames
    )

    if ($null -eq $Object) {
        return $false
    }

    foreach ($name in $PropertyNames) {
        if (-not $Object.PSObject.Properties[$name]) {
            return $false
        }
    }

    return $true
}

function Resolve-PythonPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    $resolved = Get-LocalPath -PathValue $PathValue
    if (Test-Path -Path $resolved) {
        return $resolved
    }

    $command = Get-Command -Name $PathValue -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }

    throw "Python executable not found: $PathValue"
}

$pythonAbs = Resolve-PythonPath -PathValue $PythonPath
$consumerAbs = Get-LocalPath -PathValue $ConsumerScriptPath
$inputAbs = Get-LocalPath -PathValue $InputReceiptPath
$summaryAbs = Get-LocalPath -PathValue $SummaryPath
$outputAbs = Get-LocalPath -PathValue $OutputPath

if (-not (Test-Path -Path $consumerAbs)) {
    throw "Arm-state consumer script not found: $consumerAbs"
}

if (-not (Test-Path -Path $inputAbs)) {
    throw "Input receipt not found: $inputAbs"
}

if ($RunConsumer) {
    $summaryDir = Split-Path -Parent $summaryAbs
    if (-not [string]::IsNullOrWhiteSpace($summaryDir) -and -not (Test-Path -Path $summaryDir)) {
        New-Item -ItemType Directory -Path $summaryDir -Force | Out-Null
    }

    & $pythonAbs $consumerAbs --input $inputAbs --output $summaryAbs | Out-Null
}

if (-not (Test-Path -Path $summaryAbs)) {
    throw "Arm-state summary not found: $summaryAbs"
}

$summaryDoc = Get-Content -Path $summaryAbs -Raw | ConvertFrom-Json

$rootAccepted = Test-HasProperties -Object $summaryDoc -PropertyNames @(
    "generated_at",
    "source",
    "input_path",
    "input_generated_at",
    "input_sha256",
    "app",
    "runtime",
    "camera",
    "serial",
    "estop",
    "pose",
    "last_error",
    "last_command_result"
)

$appAccepted = Test-HasProperties -Object $summaryDoc.app -PropertyNames @("alive", "status")
$runtimeAccepted = Test-HasProperties -Object $summaryDoc.runtime -PropertyNames @("mode", "runtime", "sim_enabled")
$cameraAccepted = Test-HasProperties -Object $summaryDoc.camera -PropertyNames @(
    "status",
    "depthai_device_bound",
    "video_queue_ready",
    "detection_pipeline_enabled",
    "detection_stream_configured",
    "detections_queue_ready",
    "frame_counter",
    "last_frame_age_seconds",
    "detection_pipeline_error"
)
$serialAccepted = Test-HasProperties -Object $summaryDoc.serial -PropertyNames @(
    "status",
    "serial_bound",
    "serial_ready",
    "controller_port",
    "controller_error",
    "last_serial_event",
    "last_serial_event_at",
    "last_serial_age_seconds",
    "serial_command_count",
    "serial_ack_count",
    "last_command_sent",
    "last_command_sent_at",
    "last_command_ack_at"
)
$estopAccepted = Test-HasProperties -Object $summaryDoc.estop -PropertyNames @("supported", "active")
$poseAccepted = Test-HasProperties -Object $summaryDoc.pose -PropertyNames @("available", "angles")
$lastCommandAccepted = Test-HasProperties -Object $summaryDoc.last_command_result -PropertyNames @(
    "last_command_sent",
    "last_command_sent_at",
    "last_command_ack_at",
    "acks_total",
    "commands_total"
)

$acceptedAll = ($rootAccepted -and $appAccepted -and $runtimeAccepted -and $cameraAccepted -and $serialAccepted -and $estopAccepted -and $poseAccepted -and $lastCommandAccepted)

$shaLooksValid = $false
if ($summaryDoc.PSObject.Properties['input_sha256']) {
    $shaLooksValid = [string]$summaryDoc.input_sha256 -match '^[a-fA-F0-9]{64}$'
}

$readyForManagement = [bool](
    $acceptedAll -and
    $shaLooksValid -and
    [bool]$summaryDoc.app.alive -and
    [bool]$summaryDoc.serial.serial_ready -and
    [bool]$summaryDoc.camera.depthai_device_bound -and
    [bool]$summaryDoc.camera.video_queue_ready -and
    [string]::IsNullOrWhiteSpace([string]$summaryDoc.last_error)
)

$interpretation = [pscustomobject]@{
    source = "mim-arm-read-state-consumer-v1"
    ready_for_management = $readyForManagement
    management_mode = if ($readyForManagement) { "direct_runtime_awareness" } else { "observe_only" }
    update_payload = [pscustomobject]@{
        memory_key = "mim_arm.tod.read_state.latest"
        summary_path = $SummaryPath
        mode = [string]$summaryDoc.runtime.mode
        runtime = [string]$summaryDoc.runtime.runtime
        serial_ready = [bool]$summaryDoc.serial.serial_ready
        camera_ready = [bool]($summaryDoc.camera.depthai_device_bound -and $summaryDoc.camera.video_queue_ready)
        last_error = [string]$summaryDoc.last_error
    }
}

$result = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = "tod-mim-arm-state-summary-consumption-validation-v1"
    state_summary_read = [pscustomobject]@{
        path = $SummaryPath
        accepted = [bool](Test-Path -Path $summaryAbs)
        sha256_looks_valid = $shaLooksValid
    }
    contract_accepted = [pscustomobject]@{
        root = $rootAccepted
        app = $appAccepted
        runtime = $runtimeAccepted
        camera = $cameraAccepted
        serial = $serialAccepted
        estop = $estopAccepted
        pose = $poseAccepted
        last_command_result = $lastCommandAccepted
        all = $acceptedAll
    }
    current_state = [pscustomobject]@{
        app_alive = [bool]$summaryDoc.app.alive
        mode = [string]$summaryDoc.runtime.mode
        runtime = [string]$summaryDoc.runtime.runtime
        serial_ready = [bool]$summaryDoc.serial.serial_ready
        camera_ready = [bool]($summaryDoc.camera.depthai_device_bound -and $summaryDoc.camera.video_queue_ready)
        last_error = [string]$summaryDoc.last_error
    }
    mim_arm_interpretation_payload = $interpretation
}

$outputDir = Split-Path -Parent $outputAbs
if (-not [string]::IsNullOrWhiteSpace($outputDir) -and -not (Test-Path -Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$result | ConvertTo-Json -Depth 20 | Set-Content -Path $outputAbs
$result | ConvertTo-Json -Depth 20 | Write-Output
