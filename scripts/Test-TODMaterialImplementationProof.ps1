param(
    [string]$InputPath = 'runtime/shared/TOD_EXECUTION_RESULT.latest.json',
    [string]$OutputPath = 'runtime/shared/TOD_MATERIAL_IMPLEMENTATION_PROOF_STATUS.latest.json',
    [int]$FreshMinutes = 90,
    [switch]$EmitJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot

function Resolve-RepoPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) { return [System.IO.Path]::GetFullPath($PathValue) }
    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $PathValue))
}

function Write-Utf8NoBomJson {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)]$Payload
    )
    $dir = Split-Path -Parent $PathValue
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $json = ($Payload | ConvertTo-Json -Depth 24) -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($PathValue, $json + "`n", [System.Text.UTF8Encoding]::new($false))
    return $json
}

function Read-JsonFileIfExists {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if (-not (Test-Path -LiteralPath $PathValue)) { return $null }
    try { return Get-Content -LiteralPath $PathValue -Raw | ConvertFrom-Json }
    catch { return $null }
}

function Get-StringArray {
    param([AllowNull()]$Value)
    if ($null -eq $Value) { return @() }
    return @($Value | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Test-WrapperOnlyPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    $normalized = ([string]$PathValue).Trim() -replace '\\', '/'
    $fileName = [System.IO.Path]::GetFileName($normalized)
    if ($normalized -match '^(runtime/shared|shared_state|tod/out/context-sync|tod/out/training|tod/out/logs)/') {
        if ($fileName -match '(STATUS|SUMMARY|REFLECTION|RESULT|TRUTH|ACTIVITY|ACTIVE|VALIDATION|LOCK|HEARTBEAT|STATE|LOG|MANIFEST)\.latest\.(json|md)$') {
            return $true
        }
        if ($fileName -match '^(TOD_|MIM_TOD_|MIM_OPERATOR_).*\.(latest\.)?(json|md)$' -and $fileName -notmatch '(POLICY|REGISTRY|OBJECTIVE_DECK|CONTINUITY_MEMORY|CANONICAL_AUTHORITY)') {
            return $true
        }
    }
    return $false
}

function Get-Prop {
    param($Object, [string]$Name)
    if ($null -ne $Object -and $Object.PSObject.Properties[$Name]) { return $Object.$Name }
    return $null
}

$inputAbs = Resolve-RepoPath -PathValue $InputPath
$outputAbs = Resolve-RepoPath -PathValue $OutputPath
$generatedAt = (Get-Date).ToUniversalTime().ToString('o')
$result = Read-JsonFileIfExists -PathValue $inputAbs
$inputItem = Get-Item -LiteralPath $inputAbs -ErrorAction SilentlyContinue

if ($null -eq $result) {
    $payload = [ordered]@{
        packet_type = 'tod-material-implementation-proof-status-v1'
        generated_at = $generatedAt
        source = 'Test-TODMaterialImplementationProof'
        input_path = $inputAbs
        status = 'blocked_with_evidence'
        reason_codes = @('input_result_missing_or_invalid')
        inspected_queue = $false
        material_diff_present = $false
        validation_evidence_present = $false
        allows_authoritative_completion = $false
    }
    $json = Write-Utf8NoBomJson -PathValue $outputAbs -Payload $payload
    if ($EmitJson) { $json | Write-Output }
    exit 2
}

$filesChanged = Get-StringArray -Value (Get-Prop -Object $result -Name 'files_changed')
if (@($filesChanged).Count -eq 0 -and $result.PSObject.Properties['execution_evidence']) {
    $filesChanged = Get-StringArray -Value (Get-Prop -Object $result.execution_evidence -Name 'files_changed')
}
$materialFiles = @($filesChanged | Where-Object { -not (Test-WrapperOnlyPath -PathValue ([string]$_)) })
$wrapperOnlyFiles = @($filesChanged | Where-Object { Test-WrapperOnlyPath -PathValue ([string]$_) })
$validationResults = Get-StringArray -Value (Get-Prop -Object $result -Name 'validation_results')
$commandsRun = Get-StringArray -Value (Get-Prop -Object $result -Name 'commands_run')
$diffSummary = [string](Get-Prop -Object $result -Name 'diff_summary')
$status = ([string](Get-Prop -Object $result -Name 'status')).ToLowerInvariant()
$executionState = ([string](Get-Prop -Object $result -Name 'execution_state')).ToLowerInvariant()
$reasonCode = [string](Get-Prop -Object $result -Name 'reason_code')
$noChangeRequired = $false
if ($result.PSObject.Properties['execution_evidence'] -and $result.execution_evidence.PSObject.Properties['no_change_required']) {
    $noChangeRequired = [bool]$result.execution_evidence.no_change_required
}
$completionLike = ($status -match 'completed|succeeded|done') -or ($executionState -match 'completed')
$blockedLike = ($status -match 'blocked|failed|error') -or ($executionState -match 'blocked|failed|error')
$fresh = $false
if ($inputItem) {
    $fresh = (((Get-Date) - $inputItem.LastWriteTime).TotalMinutes -le $FreshMinutes)
}
$validationEvidencePresent = (@($validationResults).Count -gt 0) -or (@($commandsRun).Count -gt 0) -or (-not [string]::IsNullOrWhiteSpace($diffSummary))
$materialDiffPresent = (@($materialFiles).Count -gt 0) -or (-not [string]::IsNullOrWhiteSpace($diffSummary) -and $diffSummary -match '\b(updated|patched|modified|applied|created|inserted|changed|validated)\b')
$wrapperOnlySuccess = ($completionLike -and @($filesChanged).Count -gt 0 -and @($materialFiles).Count -eq 0)

$reasonCodes = @()
if (-not $fresh) { $reasonCodes += 'result_not_fresh' }
if ($wrapperOnlySuccess) { $reasonCodes += 'wrapper_only_success_rejected' }
if ($completionLike -and -not $materialDiffPresent -and -not $noChangeRequired) { $reasonCodes += 'material_diff_missing' }
if ($completionLike -and -not $validationEvidencePresent) { $reasonCodes += 'validation_evidence_missing' }
if ($blockedLike -and -not [string]::IsNullOrWhiteSpace($reasonCode)) { $reasonCodes += $reasonCode }

$allowsCompletion = $completionLike -and $fresh -and -not $wrapperOnlySuccess -and $validationEvidencePresent -and ($materialDiffPresent -or $noChangeRequired)
$proofStatus = if ($allowsCompletion) { 'passed' } elseif ($blockedLike) { 'blocked_with_evidence' } elseif (-not $completionLike) { 'not_applicable' } else { 'blocked_with_evidence' }
if (@($reasonCodes).Count -eq 0 -and -not $allowsCompletion -and $completionLike) {
    $reasonCodes += 'material_implementation_not_proven'
}

$payload = [ordered]@{
    packet_type = 'tod-material-implementation-proof-status-v1'
    generated_at = $generatedAt
    source = 'Test-TODMaterialImplementationProof'
    input_path = $inputAbs
    input_last_write_utc = if ($inputItem) { $inputItem.LastWriteTimeUtc.ToString('o') } else { '' }
    fresh_minutes = $FreshMinutes
    fresh = $fresh
    status = $proofStatus
    result_status = $status
    execution_state = $executionState
    reason_codes = @($reasonCodes | Select-Object -Unique)
    files_changed = @($filesChanged)
    material_files_changed = @($materialFiles)
    wrapper_only_files_changed = @($wrapperOnlyFiles)
    material_diff_present = $materialDiffPresent
    validation_evidence_present = $validationEvidencePresent
    no_change_required = $noChangeRequired
    wrapper_only_success_rejected = $wrapperOnlySuccess
    allows_authoritative_completion = $allowsCompletion
    next_recovery_action = if ($allowsCompletion) { 'accept_result' } else { 'replay_with_material_diff_or_explicit_no_change_validation' }
}

$jsonOut = Write-Utf8NoBomJson -PathValue $outputAbs -Payload $payload
if ($EmitJson) {
    $jsonOut | Write-Output
}
if (-not $allowsCompletion -and $completionLike) {
    exit 2
}
