param(
    [switch]$RunConsumer,
    [string]$PythonPath = ".venv/Scripts/python.exe",
    [string]$ConsumerScriptPath = "scripts/mim_arm/tod_authority_consumer.py",
    [string]$IntegrationStatusPath = "shared_state/integration_status.json",
    [string]$SummaryPath = "shared_state/TOD_AUTHORITY_SUMMARY.latest.json",
    [string]$OutputPath = "shared_state/mim_arm_authority_summary_consumption_validation.json"
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
$integrationAbs = Get-LocalPath -PathValue $IntegrationStatusPath
$summaryAbs = Get-LocalPath -PathValue $SummaryPath
$outputAbs = Get-LocalPath -PathValue $OutputPath

if (-not (Test-Path -Path $consumerAbs)) {
    throw "Authority consumer script not found: $consumerAbs"
}

if (-not (Test-Path -Path $integrationAbs)) {
    throw "Integration status not found: $integrationAbs"
}

if ($RunConsumer) {
    $summaryDir = Split-Path -Parent $summaryAbs
    if (-not [string]::IsNullOrWhiteSpace($summaryDir) -and -not (Test-Path -Path $summaryDir)) {
        New-Item -ItemType Directory -Path $summaryDir -Force | Out-Null
    }

    & $pythonAbs $consumerAbs --input $integrationAbs --output $summaryAbs | Out-Null
}

if (-not (Test-Path -Path $summaryAbs)) {
    throw "Authority summary not found: $summaryAbs"
}

$summaryDoc = Get-Content -Path $summaryAbs -Raw | ConvertFrom-Json

$rootAccepted = Test-HasProperties -Object $summaryDoc -PropertyNames @(
    "generated_at",
    "source",
    "input_path",
    "input_generated_at",
    "input_sha256",
    "authority",
    "objective",
    "mim_status"
)

$authorityAccepted = Test-HasProperties -Object $summaryDoc.authority -PropertyNames @(
    "status",
    "enabled",
    "uploaded_at",
    "compatible",
    "compatibility_reason"
)

$objectiveAccepted = Test-HasProperties -Object $summaryDoc.objective -PropertyNames @(
    "tod_current",
    "mim_current",
    "aligned",
    "alignment_status",
    "alignment_source",
    "live_request_id"
)

$mimStatusAccepted = Test-HasProperties -Object $summaryDoc.mim_status -PropertyNames @(
    "available",
    "phase",
    "is_stale",
    "generated_at"
)

$acceptedAll = ($rootAccepted -and $authorityAccepted -and $objectiveAccepted -and $mimStatusAccepted)

$shaLooksValid = $false
if ($summaryDoc.PSObject.Properties['input_sha256']) {
    $shaLooksValid = [string]$summaryDoc.input_sha256 -match '^[a-fA-F0-9]{64}$'
}

$readyForManagement = [bool](
    $acceptedAll -and
    $shaLooksValid -and
    [bool]$summaryDoc.authority.enabled -and
    [bool]$summaryDoc.authority.compatible -and
    [string]$summaryDoc.authority.status -eq 'uploaded' -and
    [bool]$summaryDoc.objective.aligned -and
    [bool]$summaryDoc.mim_status.available
)

$result = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = "tod-mim-arm-authority-summary-consumption-validation-v1"
    authority_summary_read = [pscustomobject]@{
        path = $SummaryPath
        accepted = [bool](Test-Path -Path $summaryAbs)
        sha256_looks_valid = $shaLooksValid
    }
    contract_accepted = [pscustomobject]@{
        root = $rootAccepted
        authority = $authorityAccepted
        objective = $objectiveAccepted
        mim_status = $mimStatusAccepted
        all = $acceptedAll
    }
    authority_state = [pscustomobject]@{
        status = if ($summaryDoc.authority) { [string]$summaryDoc.authority.status } else { "" }
        enabled = if ($summaryDoc.authority) { [bool]$summaryDoc.authority.enabled } else { $false }
        compatible = if ($summaryDoc.authority) { [bool]$summaryDoc.authority.compatible } else { $false }
        uploaded_at = if ($summaryDoc.authority) { [string]$summaryDoc.authority.uploaded_at } else { "" }
    }
    objective_state = [pscustomobject]@{
        tod_current = if ($summaryDoc.objective) { [string]$summaryDoc.objective.tod_current } else { "" }
        mim_current = if ($summaryDoc.objective) { [string]$summaryDoc.objective.mim_current } else { "" }
        aligned = if ($summaryDoc.objective) { [bool]$summaryDoc.objective.aligned } else { $false }
        alignment_status = if ($summaryDoc.objective) { [string]$summaryDoc.objective.alignment_status } else { "" }
        alignment_source = if ($summaryDoc.objective) { [string]$summaryDoc.objective.alignment_source } else { "" }
        live_request_id = if ($summaryDoc.objective) { [string]$summaryDoc.objective.live_request_id } else { "" }
    }
    mim_arm_interpretation_payload = [pscustomobject]@{
        source = "mim-arm-authority-consumer-v1"
        ready_for_management = $readyForManagement
        management_mode = if ($readyForManagement) { "direct_tod_authority" } else { "observe_only" }
        update_payload = [pscustomobject]@{
            memory_key = "mim_arm.tod.authority.latest"
            summary_path = $SummaryPath
            authority_status = if ($summaryDoc.authority) { [string]$summaryDoc.authority.status } else { "" }
            compatibility_reason = if ($summaryDoc.authority) { [string]$summaryDoc.authority.compatibility_reason } else { "" }
            alignment_status = if ($summaryDoc.objective) { [string]$summaryDoc.objective.alignment_status } else { "" }
            tod_current = if ($summaryDoc.objective) { [string]$summaryDoc.objective.tod_current } else { "" }
            mim_current = if ($summaryDoc.objective) { [string]$summaryDoc.objective.mim_current } else { "" }
            live_request_id = if ($summaryDoc.objective) { [string]$summaryDoc.objective.live_request_id } else { "" }
        }
    }
}

$outputDir = Split-Path -Parent $outputAbs
if (-not [string]::IsNullOrWhiteSpace($outputDir) -and -not (Test-Path -Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$result | ConvertTo-Json -Depth 20 | Set-Content -Path $outputAbs
$result | ConvertTo-Json -Depth 20 | Write-Output