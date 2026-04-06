param(
    [string]$ImplementationScript = "scripts/Invoke-TODTrainingLoop.ps1",
    [string]$ImplementationConfigPath = "tod/config/tod-config.json",
    [string]$ImplementationOutputDir = "tod/out/training/supervised-default",
    [switch]$SkipImplementation,
    [switch]$SkipTests,
    [switch]$SkipPublish,
    [switch]$SkipReceiptCheck,
    [switch]$SkipBridgeSmoke,
    [switch]$RefreshMimContextFromSsh,
    [string]$EscalationStatePath = "tod/out/context-sync/listener/TOD_MIM_COORDINATION_ESCALATION_STATE.latest.json",
    [string]$RunReportPath = "shared_state/tod_supervised_execution.latest.json",
    [switch]$FailOnEscalation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

function Resolve-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) { return $PathValue }
    return (Join-Path $repoRoot $PathValue)
}

function Ensure-ParentDir {
    param([Parameter(Mandatory = $true)][string]$FilePath)
    $dir = Split-Path -Parent $FilePath
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

function Parse-Json {
    param([string]$Raw)
    if ([string]::IsNullOrWhiteSpace($Raw)) { return $null }
    try {
        return ($Raw | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

$runReportAbs = Resolve-LocalPath -PathValue $RunReportPath
$escalationAbs = Resolve-LocalPath -PathValue $EscalationStatePath
$testsScriptAbs = Resolve-LocalPath -PathValue "scripts/Invoke-TODTests.ps1"
$syncScriptAbs = Resolve-LocalPath -PathValue "scripts/Invoke-TODSharedStateSync.ps1"
$bridgeSmokeScriptAbs = Resolve-LocalPath -PathValue "scripts/Invoke-TODMimBridgeSmoke.ps1"
$implementationAbs = Resolve-LocalPath -PathValue $ImplementationScript

if (-not (Test-Path -Path $testsScriptAbs)) { throw "Missing tests script: $testsScriptAbs" }
if (-not (Test-Path -Path $syncScriptAbs)) { throw "Missing shared-state sync script: $syncScriptAbs" }
if (-not (Test-Path -Path $bridgeSmokeScriptAbs)) { throw "Missing bridge smoke script: $bridgeSmokeScriptAbs" }
if (-not $SkipImplementation -and -not (Test-Path -Path $implementationAbs)) { throw "Missing implementation script: $implementationAbs" }

$result = [ordered]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = "tod-supervised-execution-v1"
    mode = "strict_default"
    steps = [ordered]@{
        implementation = [ordered]@{ attempted = (-not [bool]$SkipImplementation); ok = $false; error = ""; output = $null }
        tests = [ordered]@{ attempted = (-not [bool]$SkipTests); ok = $false; error = ""; output = $null }
        publish = [ordered]@{ attempted = (-not [bool]$SkipPublish); ok = $false; error = ""; output = $null }
        receipt_check = [ordered]@{ attempted = (-not [bool]$SkipReceiptCheck); ok = $false; error = ""; output = $null }
        bridge_smoke = [ordered]@{ attempted = (-not [bool]$SkipBridgeSmoke); ok = $false; error = ""; output = $null }
    }
    needs_escalation = $false
    escalation_reason = ""
    escalation_state_path = $EscalationStatePath
    run_report_path = $RunReportPath
}

try {
    if (-not $SkipImplementation) {
        $implRaw = & $implementationAbs -ConfigPath $ImplementationConfigPath -OutputDir $ImplementationOutputDir -SkipProjectDiscovery
        $implObj = Parse-Json -Raw ($implRaw | Out-String)
        $result.steps.implementation.output = $implObj
        $result.steps.implementation.ok = $true
    }

    if (-not $SkipTests) {
        $testsRaw = & $testsScriptAbs
        $testsObj = Parse-Json -Raw ($testsRaw | Out-String)
        $result.steps.tests.output = $testsObj
        $result.steps.tests.ok = [bool]($testsObj -and $testsObj.passed_all)
        if (-not [bool]$result.steps.tests.ok) {
            throw "tests_failed"
        }
    }

    if (-not $SkipPublish) {
        $syncArgs = @{ PublishTodStatusToMimArm = $true }
        if ($RefreshMimContextFromSsh) {
            $syncArgs.RefreshMimContextFromSsh = $true
        }

        $syncRaw = & $syncScriptAbs @syncArgs
        $syncObj = Parse-Json -Raw ($syncRaw | Out-String)
        $result.steps.publish.output = $syncObj
        $result.steps.publish.ok = [bool]($syncObj -and $syncObj.ok)
        if (-not [bool]$result.steps.publish.ok) {
            throw "publish_failed"
        }
    }

    if (-not $SkipReceiptCheck) {
        $receiptPath = Resolve-LocalPath -PathValue "shared_state/TOD_MIM_ARM_STATUS_UPLOAD_RECEIPT.latest.json"
        if (-not (Test-Path -Path $receiptPath)) {
            throw "receipt_missing"
        }

        $receipt = Get-Content -Path $receiptPath -Raw | ConvertFrom-Json
        $receiptOk = (
            ([string]$receipt.status -eq "uploaded") -and
            ([string]$receipt.consumer_status -eq "executed") -and
            ([string]$receipt.remote_access_status -eq "full_access_granted")
        )

        $result.steps.receipt_check.output = $receipt
        $result.steps.receipt_check.ok = [bool]$receiptOk

        if (-not $receiptOk) {
            throw "receipt_check_failed"
        }
    }

    if (-not $SkipBridgeSmoke) {
        $bridgeSmokeRaw = & $bridgeSmokeScriptAbs
        $bridgeSmokeObj = Parse-Json -Raw ($bridgeSmokeRaw | Out-String)
        $result.steps.bridge_smoke.output = $bridgeSmokeObj
        $result.steps.bridge_smoke.ok = [bool]($bridgeSmokeObj -and $bridgeSmokeObj.passed)
        if (-not [bool]$result.steps.bridge_smoke.ok) {
            throw "bridge_smoke_failed"
        }
    }
}
catch {
    $msg = [string]$_.Exception.Message
    $result.needs_escalation = $true
    $result.escalation_reason = $msg

    if (-not $SkipImplementation -and -not [bool]$result.steps.implementation.ok -and [string]::IsNullOrWhiteSpace([string]$result.steps.implementation.error)) {
        $result.steps.implementation.error = $msg
    }
    elseif (-not $SkipTests -and -not [bool]$result.steps.tests.ok -and [string]::IsNullOrWhiteSpace([string]$result.steps.tests.error)) {
        $result.steps.tests.error = $msg
    }
    elseif (-not $SkipPublish -and -not [bool]$result.steps.publish.ok -and [string]::IsNullOrWhiteSpace([string]$result.steps.publish.error)) {
        $result.steps.publish.error = $msg
    }
    elseif (-not $SkipReceiptCheck -and -not [bool]$result.steps.receipt_check.ok -and [string]::IsNullOrWhiteSpace([string]$result.steps.receipt_check.error)) {
        $result.steps.receipt_check.error = $msg
    }
    elseif (-not $SkipBridgeSmoke -and -not [bool]$result.steps.bridge_smoke.ok -and [string]::IsNullOrWhiteSpace([string]$result.steps.bridge_smoke.error)) {
        $result.steps.bridge_smoke.error = $msg
    }
}

if ([bool]$result.needs_escalation) {
    Ensure-ParentDir -FilePath $escalationAbs
    $existing = $null
    if (Test-Path -Path $escalationAbs) {
        try { $existing = Get-Content -Path $escalationAbs -Raw | ConvertFrom-Json } catch { $existing = $null }
    }

    $emitCount = 1
    if ($existing -and $existing.PSObject.Properties["emit_count"]) {
        $emitCount = [int]$existing.emit_count + 1
    }

    $escalationState = [ordered]@{
        pending_request_id = "tod-supervised-execution"
        pending_since = (Get-Date).ToUniversalTime().ToString("o")
        last_emit_at = (Get-Date).ToUniversalTime().ToString("o")
        last_emitted_level = 3
        emit_count = $emitCount
        last_ack_request_id = if ($existing -and $existing.PSObject.Properties["last_ack_request_id"]) { [string]$existing.last_ack_request_id } else { "" }
        last_acknowledged_at = if ($existing -and $existing.PSObject.Properties["last_acknowledged_at"]) { [string]$existing.last_acknowledged_at } else { "" }
        last_ack_generated_at = if ($existing -and $existing.PSObject.Properties["last_ack_generated_at"]) { [string]$existing.last_ack_generated_at } else { "" }
        last_ack_status = if ($existing -and $existing.PSObject.Properties["last_ack_status"]) { [string]$existing.last_ack_status } else { "" }
        last_ack_decision = if ($existing -and $existing.PSObject.Properties["last_ack_decision"]) { [string]$existing.last_ack_decision } else { "" }
        last_ack_reason = [string]$result.escalation_reason
        source = "tod-supervised-execution"
    }

    $escalationJson = $escalationState | ConvertTo-Json -Depth 10
    Set-Content -Path $escalationAbs -Value $escalationJson
}

Ensure-ParentDir -FilePath $runReportAbs
$finalJson = ($result | ConvertTo-Json -Depth 20)
Set-Content -Path $runReportAbs -Value $finalJson
Write-Output $finalJson

if ($FailOnEscalation -and [bool]$result.needs_escalation) {
    throw ("supervised_execution_escalated: {0}" -f [string]$result.escalation_reason)
}
