param(
    [string]$ConfigPath = 'tod/config/tod-config.json',
    [string]$OutputDir = 'tod/out/training',
    [string]$StatePath = 'tod/data/state.json',
    [int]$Port = 8844,
    [string]$ValidationHarness = 'multi_objective_compare',
    [string]$RecoveryArtifactPath,
    [switch]$EmitJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$reliabilityRecoveryDrillScript = Join-Path $PSScriptRoot 'Invoke-TODReliabilityRecoveryDrill.ps1'
$sweepScript = Join-Path $PSScriptRoot 'Invoke-TODOperatorChatSweep.ps1'

function Resolve-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return [System.IO.Path]::GetFullPath($PathValue)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $PathValue))
}

function Write-Utf8NoBomJson {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)]$Payload,
        [int]$Depth = 20
    )

    $dir = Split-Path -Parent $PathValue
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $json = ($Payload | ConvertTo-Json -Depth $Depth) -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($PathValue, $json, $utf8NoBom)
}

function Test-PathWritable {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if (-not (Test-Path -Path $PathValue)) {
        return $true
    }

    $stream = $null
    try {
        $stream = [System.IO.File]::Open($PathValue, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        return $true
    }
    catch {
        return $false
    }
    finally {
        if ($null -ne $stream) {
            $stream.Dispose()
        }
    }
}

function Try-ReadJson {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if (-not (Test-Path -Path $PathValue -PathType Leaf)) {
        return [pscustomobject]@{
            exists = $false
            parsed = $false
            payload = $null
            error = 'missing'
        }
    }

    try {
        return [pscustomobject]@{
            exists = $true
            parsed = $true
            payload = (Get-Content -Path $PathValue -Raw | ConvertFrom-Json)
            error = ''
        }
    }
    catch {
        return [pscustomobject]@{
            exists = $true
            parsed = $false
            payload = $null
            error = [string]$_.Exception.Message
        }
    }
}

function New-Check {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][bool]$Passed,
        [Parameter(Mandatory = $true)][string]$Detail
    )

    return [pscustomobject]@{
        name = $Name
        passed = $Passed
        detail = if ([string]::IsNullOrWhiteSpace($Detail)) { '(empty)' } else { $Detail }
    }
}

function Invoke-SweepArtifactValidation {
    param(
        [Parameter(Mandatory = $true)][string]$SweepScriptPath,
        [Parameter(Mandatory = $true)][string]$SweepOutputDir,
        [Parameter(Mandatory = $true)][int]$SweepPort,
        [Parameter(Mandatory = $true)][string]$Harness
    )

    $rawArtifactPath = Join-Path $SweepOutputDir 'runtime-safe-sweep-raw.latest.json'
    $ineffectiveSummaryPath = Join-Path $SweepOutputDir 'runtime-safe-sweep-ineffective-summary.latest.json'
    $validationArtifactPath = Join-Path $SweepOutputDir 'runtime-safe-sweep-validation.latest.json'
    $powershellExe = Join-Path $PSHOME 'powershell.exe'
    if (-not (Test-Path -Path $powershellExe)) {
        $powershellExe = 'powershell.exe'
    }

    $global:LASTEXITCODE = 0
    & $powershellExe -NoProfile -ExecutionPolicy Bypass -File $SweepScriptPath -ArtifactOnly -Port $SweepPort -ValidationHarness $Harness -RawArtifactPath $rawArtifactPath -IneffectiveSummaryPath $ineffectiveSummaryPath | Out-Null
    $exitCodeVar = Get-Variable -Name LASTEXITCODE -ErrorAction SilentlyContinue
    $exitCode = if ($null -ne $exitCodeVar) { [int]$exitCodeVar.Value } else { 0 }

    $rawRead = Try-ReadJson -PathValue $rawArtifactPath
    $summaryRead = Try-ReadJson -PathValue $ineffectiveSummaryPath
    $rawGeneratedAt = $null
    if ($rawRead.parsed -and $rawRead.payload -and $rawRead.payload.PSObject.Properties['generated_at']) {
        try {
            $rawGeneratedAt = ([DateTime]::Parse([string]$rawRead.payload.generated_at, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)).ToUniversalTime()
        }
        catch {
            $rawGeneratedAt = $null
        }
    }

    $artifactFresh = ($null -ne $rawGeneratedAt -and $rawGeneratedAt -ge ((Get-Date).ToUniversalTime().AddMinutes(-15)))
    $summaryPayload = if ($summaryRead.parsed) { $summaryRead.payload } else { $null }
    $checks = @(
        (New-Check -Name 'raw_artifact_exists' -Passed ([bool]$rawRead.exists) -Detail $rawArtifactPath),
        (New-Check -Name 'summary_artifact_exists' -Passed ([bool]$summaryRead.exists) -Detail $ineffectiveSummaryPath),
        (New-Check -Name 'raw_artifact_parses' -Passed ([bool]$rawRead.parsed) -Detail $(if ($rawRead.parsed) { 'Raw artifact parsed.' } else { [string]$rawRead.error })),
        (New-Check -Name 'summary_artifact_parses' -Passed ([bool]$summaryRead.parsed) -Detail $(if ($summaryRead.parsed) { 'Summary artifact parsed.' } else { [string]$summaryRead.error })),
        (New-Check -Name 'artifact_timestamp_fresh' -Passed ([bool]$artifactFresh) -Detail $(if ($artifactFresh) { [string]$rawGeneratedAt.ToString('o') } else { 'Raw artifact timestamp is missing or stale.' })),
        (New-Check -Name 'ineffective_smoke_ok' -Passed ($summaryPayload -and [bool]$summaryPayload.ineffective_smoke_ok) -Detail $(if ($summaryPayload) { [string]$summaryPayload.ineffective_smoke_ok } else { 'summary unavailable' })),
        (New-Check -Name 'stable_contract_ok' -Passed ($summaryPayload -and [bool]$summaryPayload.stable_contract_ok) -Detail $(if ($summaryPayload) { [string]$summaryPayload.stable_contract_ok } else { 'summary unavailable' })),
        (New-Check -Name 'ineffective_terminal_state' -Passed ($summaryPayload -and [string]$summaryPayload.ineffective_terminal_state -eq 'ineffective') -Detail $(if ($summaryPayload) { [string]$summaryPayload.ineffective_terminal_state } else { 'summary unavailable' })),
        (New-Check -Name 'ineffective_lifecycle_status' -Passed ($summaryPayload -and [string]$summaryPayload.ineffective_lifecycle_status -eq 'ineffective') -Detail $(if ($summaryPayload) { [string]$summaryPayload.ineffective_lifecycle_status } else { 'summary unavailable' })),
        (New-Check -Name 'ineffective_signal_seen' -Passed ($summaryPayload -and [bool]$summaryPayload.ineffective_signal_seen) -Detail $(if ($summaryPayload) { [string]$summaryPayload.ineffective_signal_seen } else { 'summary unavailable' })),
        (New-Check -Name 'ineffective_followup_action' -Passed ($summaryPayload -and [string]$summaryPayload.ineffective_followup_action -eq 'refresh-governance-snapshot') -Detail $(if ($summaryPayload) { [string]$summaryPayload.ineffective_followup_action } else { 'summary unavailable' })),
        (New-Check -Name 'ineffective_commitment_terminal_state' -Passed ($summaryPayload -and [string]$summaryPayload.ineffective_commitment_terminal_state -eq 'ineffective') -Detail $(if ($summaryPayload) { [string]$summaryPayload.ineffective_commitment_terminal_state } else { 'summary unavailable' }))
    )
    $passedAll = (@($checks | Where-Object { -not [bool]$_.passed }).Count -eq 0 -and $exitCode -eq 0)

    $validationArtifactPayload = [pscustomobject]@{
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        source = 'tod-runtime-safe-sweep-validation-v1'
        port = $SweepPort
        validation_harness = $Harness
        raw_artifact_path = $rawArtifactPath
        ineffective_summary_path = $ineffectiveSummaryPath
        sweep_exit_code = $exitCode
        artifact_generated_at = if ($null -ne $rawGeneratedAt) { $rawGeneratedAt.ToString('o') } else { '' }
        checks = @($checks)
        summary = [pscustomobject]@{
            total = @($checks).Count
            passed = @(@($checks | Where-Object { [bool]$_.passed })).Count
            failed = @(@($checks | Where-Object { -not [bool]$_.passed })).Count
            passed_all = $passedAll
            exit_code = $exitCode
        }
    }

    Write-Utf8NoBomJson -PathValue $validationArtifactPath -Payload $validationArtifactPayload -Depth 20

    return [pscustomobject]@{
        exit_code = $exitCode
        artifact_path = $validationArtifactPath
        raw_artifact_path = $rawArtifactPath
        ineffective_summary_path = $ineffectiveSummaryPath
        artifact = [pscustomobject]@{
            exists = $true
            parsed = $true
            payload = $validationArtifactPayload
            error = ''
        }
    }
}

function Invoke-RecoveryDrillArtifact {
    param(
        [Parameter(Mandatory = $true)][string]$RecoveryScriptPath,
        [Parameter(Mandatory = $true)][string]$ResolvedConfigPath,
        [Parameter(Mandatory = $true)][string]$ResolvedOutputDir,
        [Parameter(Mandatory = $true)][string]$ResolvedStatePath,
        [Parameter(Mandatory = $true)][int]$ResolvedPort
    )

    $powershellExe = Join-Path $PSHOME 'powershell.exe'
    if (-not (Test-Path -Path $powershellExe)) {
        $powershellExe = 'powershell.exe'
    }

    $recoveryArtifactPath = Join-Path $ResolvedOutputDir 'readiness-recovery.latest.json'
    $global:LASTEXITCODE = 0
    & $powershellExe -NoProfile -ExecutionPolicy Bypass -File $RecoveryScriptPath -ConfigPath $ResolvedConfigPath -OutputDir $ResolvedOutputDir -StatePath $ResolvedStatePath -Port $ResolvedPort -EmitJson | Out-Null
    $artifactRead = Try-ReadJson -PathValue $recoveryArtifactPath
    if (-not $artifactRead.parsed) {
        throw "Recovery artifact could not be parsed: $($artifactRead.error)"
    }

    return $artifactRead.payload
}

$effectiveConfigPath = Resolve-LocalPath -PathValue $ConfigPath
$effectiveOutputDir = Resolve-LocalPath -PathValue $OutputDir
$effectiveStatePath = Resolve-LocalPath -PathValue $StatePath
$effectiveRecoveryArtifactPath = if ([string]::IsNullOrWhiteSpace($RecoveryArtifactPath)) { '' } else { Resolve-LocalPath -PathValue $RecoveryArtifactPath }
$artifactOutputPath = Join-Path $effectiveOutputDir 'runtime-safe-validation-subset.latest.json'
$errors = @()

if (-not (Test-Path -Path $reliabilityRecoveryDrillScript)) {
    throw "Recovery drill script not found: $reliabilityRecoveryDrillScript"
}
if (-not (Test-Path -Path $sweepScript)) {
    throw "Sweep script not found: $sweepScript"
}
if (-not (Test-Path -Path $effectiveOutputDir)) {
    New-Item -ItemType Directory -Path $effectiveOutputDir -Force | Out-Null
}

$reliabilityRecovery = $null
$sweepValidation = $null

try {
    if (-not [string]::IsNullOrWhiteSpace($effectiveRecoveryArtifactPath)) {
        $recoveryRead = Try-ReadJson -PathValue $effectiveRecoveryArtifactPath
        if ($recoveryRead.parsed) {
            $reliabilityRecovery = $recoveryRead.payload
        }
        else {
            throw "Recovery artifact could not be parsed: $($recoveryRead.error)"
        }
    }
    else {
        $reliabilityRecovery = Invoke-RecoveryDrillArtifact -RecoveryScriptPath $reliabilityRecoveryDrillScript -ResolvedConfigPath $effectiveConfigPath -ResolvedOutputDir $effectiveOutputDir -ResolvedStatePath $effectiveStatePath -ResolvedPort $Port
        $effectiveRecoveryArtifactPath = Join-Path $effectiveOutputDir 'readiness-recovery.latest.json'
    }
}
catch {
    $errors += "reliability-recovery: $($_.Exception.Message)"
}

try {
    $sweepValidation = Invoke-SweepArtifactValidation -SweepScriptPath $sweepScript -SweepOutputDir $effectiveOutputDir -SweepPort $Port -Harness $ValidationHarness
}
catch {
    $errors += "sweep-artifact: $($_.Exception.Message)"
}

$recoveryOk = [bool](
    $null -ne $reliabilityRecovery -and
    $reliabilityRecovery.PSObject.Properties['summary'] -and
    [bool]$reliabilityRecovery.summary.blocked_enforced -and
    [bool]$reliabilityRecovery.summary.degraded_enforced -and
    [bool]$reliabilityRecovery.summary.recovered
)

$sweepOk = [bool](
    $null -ne $sweepValidation -and
    $sweepValidation.artifact.parsed -and
    $sweepValidation.artifact.payload -and
    $sweepValidation.artifact.payload.PSObject.Properties['summary'] -and
    [bool]$sweepValidation.artifact.payload.summary.passed_all -and
    [int]$sweepValidation.exit_code -eq 0
)

$artifact = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    source = 'tod-runtime-safe-validation-subset-v1'
    output_dir = $effectiveOutputDir
    config_path = $effectiveConfigPath
    port = $Port
    live_runtime = [pscustomobject]@{
        state_file_locked = (-not (Test-PathWritable -PathValue $effectiveStatePath))
    }
    artifacts = [pscustomobject]@{
        readiness_recovery = $effectiveRecoveryArtifactPath
        sweep_validation = if ($null -ne $sweepValidation) { [string]$sweepValidation.artifact_path } else { '' }
        sweep_raw = if ($null -ne $sweepValidation) { [string]$sweepValidation.raw_artifact_path } else { '' }
        sweep_ineffective_summary = if ($null -ne $sweepValidation) { [string]$sweepValidation.ineffective_summary_path } else { '' }
        runtime_safe_subset = $artifactOutputPath
    }
    readiness_recovery = if ($null -ne $reliabilityRecovery) { [pscustomobject]@{
            blocked_enforced = [bool]$reliabilityRecovery.summary.blocked_enforced
            degraded_enforced = [bool]$reliabilityRecovery.summary.degraded_enforced
            recovered = [bool]$reliabilityRecovery.summary.recovered
            history_transition_observed = [bool]$reliabilityRecovery.summary.history_transition_observed
        } } else { $null }
    sweep_validation = if ($null -ne $sweepValidation -and $sweepValidation.artifact.parsed) { [pscustomobject]@{
            exit_code = [int]$sweepValidation.exit_code
            passed_all = [bool]$sweepValidation.artifact.payload.summary.passed_all
            total = [int]$sweepValidation.artifact.payload.summary.total
            passed = [int]$sweepValidation.artifact.payload.summary.passed
            failed = [int]$sweepValidation.artifact.payload.summary.failed
        } } elseif ($null -ne $sweepValidation) { [pscustomobject]@{
            exit_code = [int]$sweepValidation.exit_code
            passed_all = $false
            total = 0
            passed = 0
            failed = 0
        } } else { $null }
    summary = [pscustomobject]@{
        recovery_ok = $recoveryOk
        sweep_artifact_ok = $sweepOk
        runtime_safe_validation = $true
        state_file_locked = (-not (Test-PathWritable -PathValue $effectiveStatePath))
        passed_all = ($recoveryOk -and $sweepOk -and @($errors).Count -eq 0)
        error_count = @($errors).Count
    }
    errors = @($errors)
}

Write-Utf8NoBomJson -PathValue $artifactOutputPath -Payload $artifact -Depth 30

if ($EmitJson) {
    $artifact | ConvertTo-Json -Depth 30 | Write-Output
}
else {
    $artifact | ConvertTo-Json -Depth 30 | Write-Output
}