param(
    [string]$ListenerStageDir = "tod/out/context-sync/listener",
    [string]$ContractDir = "tod/out/context-sync/contracts",
    [switch]$EmitJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

function Resolve-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return [System.IO.Path]::GetFullPath($PathValue)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $PathValue))
}

function Read-JsonIfExists {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if (-not (Test-Path -Path $PathValue -PathType Leaf)) {
        return $null
    }
    try {
        return (Get-Content -Path $PathValue -Raw | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Get-ValidationSummary {
    param($Entry)

    if ($null -eq $Entry) {
        return $null
    }

    return [pscustomobject]@{
        validated_at = if ($Entry.PSObject.Properties['validated_at']) { [string]$Entry.validated_at } else { '' }
        passed = if ($Entry.PSObject.Properties['passed']) { [bool]$Entry.passed } else { $false }
        request_id = if ($Entry.PSObject.Properties['request_id']) { [string]$Entry.request_id } else { '' }
        task_id = if ($Entry.PSObject.Properties['task_id']) { [string]$Entry.task_id } else { '' }
        status = if ($Entry.PSObject.Properties['status']) { [string]$Entry.status } else { '' }
        errors = if ($Entry.PSObject.Properties['errors']) { @($Entry.errors) } else { @() }
    }
}

$listenerStageAbs = Resolve-LocalPath -PathValue $ListenerStageDir
$contractDirAbs = Resolve-LocalPath -PathValue $ContractDir

$bindingStatePath = Join-Path $listenerStageAbs 'TOD_MIM_RUNTIME_BINDING_STATE.latest.json'
$violationPath = Join-Path $listenerStageAbs 'TOD_MIM_RUNTIME_CONTRACT_VIOLATION.latest.json'
$receiptPath = Join-Path $contractDirAbs 'TOD_MIM_COMMUNICATION_CONTRACT_RECEIPT.v1.json'

$bindingState = Read-JsonIfExists -PathValue $bindingStatePath
$violation = Read-JsonIfExists -PathValue $violationPath
$receipt = Read-JsonIfExists -PathValue $receiptPath

$ackState = if ($bindingState -and $bindingState.PSObject.Properties['ack_runtime_binding']) { $bindingState.ack_runtime_binding } else { $null }
$resultState = if ($bindingState -and $bindingState.PSObject.Properties['result_runtime_binding']) { $bindingState.result_runtime_binding } else { $null }

$candidateFirst = @()
foreach ($entry in @($ackState.first_validation, $resultState.first_validation)) {
    if ($null -ne $entry -and $entry.PSObject.Properties['validated_at'] -and -not [string]::IsNullOrWhiteSpace([string]$entry.validated_at)) {
        $candidateFirst += $entry
    }
}

$firstLiveValidation = $null
if (@($candidateFirst).Count -gt 0) {
    $firstLiveValidation = @($candidateFirst | Sort-Object { [datetime]::Parse([string]$_.validated_at) } | Select-Object -First 1)[0]
}

$violations = @()
if ($null -ne $violation) {
    $violations += [pscustomobject]@{
        packet_kind = if ($violation.PSObject.Properties['packet_kind']) { [string]$violation.packet_kind } else { '' }
        request_id = if ($violation.PSObject.Properties['request_id']) { [string]$violation.request_id } else { '' }
        violations = if ($violation.PSObject.Properties['violations']) { @($violation.violations) } else { @() }
        generated_at = if ($violation.PSObject.Properties['generated_at']) { [string]$violation.generated_at } else { '' }
    }
}

$ackBindingActive = [bool]($receipt -and $receipt.PSObject.Properties['acceptance_status'] -and [string]::Equals([string]$receipt.acceptance_status, 'accepted', [System.StringComparison]::OrdinalIgnoreCase) -and $ackState -and $ackState.PSObject.Properties['state'] -and [string]::Equals([string]$ackState.state, 'active', [System.StringComparison]::OrdinalIgnoreCase))
$resultBindingActive = [bool]($receipt -and $receipt.PSObject.Properties['acceptance_status'] -and [string]::Equals([string]$receipt.acceptance_status, 'accepted', [System.StringComparison]::OrdinalIgnoreCase) -and $resultState -and $resultState.PSObject.Properties['state'] -and [string]::Equals([string]$resultState.state, 'active', [System.StringComparison]::OrdinalIgnoreCase))

$cutoverReady = $ackBindingActive -and $resultBindingActive -and ($null -ne $ackState) -and ($null -ne $resultState) -and
    ($null -ne $ackState.first_validation) -and ($null -ne $resultState.first_validation) -and
    [bool]$ackState.first_validation.passed -and [bool]$resultState.first_validation.passed -and (@($violations).Count -eq 0)

$result = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    source = 'tod-mim-runtime-contract-binding-status-v1'
    receipt_verified = [bool]($receipt -and $receipt.PSObject.Properties['checksum_match'] -and [bool]$receipt.checksum_match)
    ack_runtime_binding_state = [pscustomobject]@{
        active = $ackBindingActive
        state = if ($ackState -and $ackState.PSObject.Properties['state']) { [string]$ackState.state } else { 'inactive' }
        first_validation = Get-ValidationSummary -Entry $(if ($ackState) { $ackState.first_validation } else { $null })
        last_validation = Get-ValidationSummary -Entry $(if ($ackState) { $ackState.last_validation } else { $null })
    }
    result_runtime_binding_state = [pscustomobject]@{
        active = $resultBindingActive
        state = if ($resultState -and $resultState.PSObject.Properties['state']) { [string]$resultState.state } else { 'inactive' }
        first_validation = Get-ValidationSummary -Entry $(if ($resultState) { $resultState.first_validation } else { $null })
        last_validation = Get-ValidationSummary -Entry $(if ($resultState) { $resultState.last_validation } else { $null })
    }
    first_live_validation_result = Get-ValidationSummary -Entry $firstLiveValidation
    any_contract_violations = @($violations)
    cutover_readiness_status = if ($cutoverReady) { 'ready' } else { 'not_ready' }
}

$json = $result | ConvertTo-Json -Depth 20
if ($EmitJson) {
    $json | Write-Output
}
else {
    $json | Write-Output
}