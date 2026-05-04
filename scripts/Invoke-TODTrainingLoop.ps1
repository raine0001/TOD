param(
    [string]$ConfigPath,
    [string]$OutputDir,
    [string]$LibraryRoot = "E:\\",
    [int]$Top = 25,
    [switch]$SkipTests,
    [switch]$SkipSmoke,
    [switch]$SkipProjectDiscovery,
    [switch]$FailOnError
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$todScript = Join-Path $PSScriptRoot "TOD.ps1"
$testsScript = Join-Path $PSScriptRoot "Invoke-TODTests.ps1"
$smokeScript = Join-Path $PSScriptRoot "Invoke-TODSmoke.ps1"
$projectLibraryScript = Join-Path $PSScriptRoot "Update-TODProjectLibrary.ps1"
$lightweightStateBusScript = Join-Path $PSScriptRoot "Get-TODLightweightStateBus.ps1"
$reliabilityRecoveryDrillScript = Join-Path $PSScriptRoot "Invoke-TODReliabilityRecoveryDrill.ps1"
$runtimeSafeSubsetScript = Join-Path $PSScriptRoot "Invoke-TODRuntimeSafeValidationSubset.ps1"
$statePath = Join-Path $repoRoot "tod/data/state.json"
$maxStateReadBytes = 256MB

if (-not (Test-Path -Path $todScript)) {
    throw "Missing TOD script: $todScript"
}
if (-not (Test-Path -Path $testsScript)) {
    throw "Missing tests runner: $testsScript"
}
if (-not (Test-Path -Path $smokeScript)) {
    throw "Missing smoke runner: $smokeScript"
}
if (-not (Test-Path -Path $projectLibraryScript)) {
    throw "Missing project library script: $projectLibraryScript"
}
if (-not (Test-Path -Path $lightweightStateBusScript)) {
    throw "Missing lightweight state bus script: $lightweightStateBusScript"
}
if (-not (Test-Path -Path $reliabilityRecoveryDrillScript)) {
    throw "Missing reliability recovery drill script: $reliabilityRecoveryDrillScript"
}
if (-not (Test-Path -Path $runtimeSafeSubsetScript)) {
    throw "Missing runtime-safe subset script: $runtimeSafeSubsetScript"
}

$effectiveConfigPath = if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    Join-Path $repoRoot "tod/config/tod-config.json"
}
else {
    if ([System.IO.Path]::IsPathRooted($ConfigPath)) { $ConfigPath } else { Join-Path $repoRoot $ConfigPath }
}

if (-not (Test-Path -Path $effectiveConfigPath)) {
    throw "Config file not found: $effectiveConfigPath"
}

$effectiveOutputDir = if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    Join-Path $repoRoot "tod/out/training"
}
else {
    if ([System.IO.Path]::IsPathRooted($OutputDir)) { $OutputDir } else { Join-Path $repoRoot $OutputDir }
}

if (-not (Test-Path -Path $effectiveOutputDir)) {
    New-Item -ItemType Directory -Path $effectiveOutputDir -Force | Out-Null
}

$sharedStateDir = Join-Path $repoRoot 'shared_state'
$trainingStatusPath = Join-Path $sharedStateDir 'tod_training_status.latest.json'
$integrationStatusPath = Join-Path $sharedStateDir 'integration_status.json'
$trainingTracePath = Join-Path $effectiveOutputDir 'training-trace.log'
$trainingStartedAtUtc = (Get-Date).ToUniversalTime()
$trainingRunId = [guid]::NewGuid().ToString('N')

function New-DirectoryIfMissing {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if (-not (Test-Path -Path $PathValue)) {
        New-Item -ItemType Directory -Path $PathValue -Force | Out-Null
    }
}

function Write-Utf8NoBomJson {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)]$Payload,
        [int]$Depth = 20
    )

    $directory = Split-Path -Parent $PathValue
    if (-not [string]::IsNullOrWhiteSpace($directory)) {
        New-DirectoryIfMissing -PathValue $directory
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $json = ($Payload | ConvertTo-Json -Depth $Depth) -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($PathValue, $json, $utf8NoBom)
}

function Update-IntegrationTrainingStatus {
    param([Parameter(Mandatory = $true)]$TrainingStatus)

    try {
        if (-not (Test-Path -Path $integrationStatusPath)) {
            return
        }

        $integrationStatus = Get-Content -Path $integrationStatusPath -Raw | ConvertFrom-Json
        if ($null -eq $integrationStatus) {
            return
        }

        if ($integrationStatus.PSObject.Properties['training_status']) {
            $integrationStatus.training_status = $TrainingStatus
        }
        else {
            $integrationStatus | Add-Member -NotePropertyName training_status -NotePropertyValue $TrainingStatus
        }

        Write-Utf8NoBomJson -PathValue $integrationStatusPath -Payload $integrationStatus -Depth 20
    }
    catch {
    }
}

function Write-TrainingTrace {
    param([Parameter(Mandatory = $true)][string]$Message)

    try {
        $timestamp = (Get-Date).ToUniversalTime().ToString('o')
        Add-Content -Path $trainingTracePath -Value ("[{0}] {1}" -f $timestamp, $Message)
    }
    catch {
    }
}

$trainingStageState = [ordered]@{}
$trainingCurrentStageId = ''
$trainingLatestError = ''
$trainingLatestResolution = ''
$trainingLatestErrorAt = ''
$trainingLatestResolutionAt = ''
$errors = @()
$warnings = @()
$trainingRecentEvents = New-Object System.Collections.Generic.List[object]

function Add-TrainingEvent {
    param(
        [Parameter(Mandatory = $true)][string]$Type,
        [Parameter(Mandatory = $true)][string]$Summary
    )

    $trainingRecentEvents.Add([pscustomobject]@{
            generated_at = (Get-Date).ToUniversalTime().ToString('o')
            type = $Type
            summary = $Summary
        }) | Out-Null

    while ($trainingRecentEvents.Count -gt 12) {
        $trainingRecentEvents.RemoveAt(0)
    }
}

function Publish-TrainingStatus {
    param(
        [Parameter(Mandatory = $true)][string]$State,
        [Parameter(Mandatory = $true)][string]$Phase,
        [string]$Summary = '',
        [string]$StateLabel = '',
        [string]$PhaseDetail = ''
    )

    $now = (Get-Date).ToUniversalTime()
    $elapsedSeconds = [int][math]::Max(0, [math]::Round(($now - $trainingStartedAtUtc).TotalSeconds))
    $stageValues = @()
    foreach ($stageKey in @($trainingStageState.Keys)) {
        $stageValues += $trainingStageState[[string]$stageKey]
    }

    $completedSteps = @($stageValues | Where-Object { [string]$_.status -eq 'completed' }).Count
    $failedSteps = @($stageValues | Where-Object { [string]$_.status -eq 'failed' }).Count
    $totalSteps = [math]::Max(1, @($stageValues).Count)
    $percentComplete = [int][math]::Max(0, [math]::Min(100, [math]::Round(($completedSteps / [double]$totalSteps) * 100)))

    if ([string]::Equals($State, 'completed', [System.StringComparison]::OrdinalIgnoreCase) -or [string]::Equals($State, 'completed_with_errors', [System.StringComparison]::OrdinalIgnoreCase)) {
        $percentComplete = 100
    }

    $etaSeconds = $null
    $expectedCompletionUtc = ''
    if ($percentComplete -gt 0 -and $percentComplete -lt 100) {
        $estimatedTotalSeconds = [int][math]::Round(($elapsedSeconds / [double]$percentComplete) * 100)
        $etaSeconds = [int][math]::Max(0, $estimatedTotalSeconds - $elapsedSeconds)
        $expectedCompletionUtc = $now.AddSeconds($etaSeconds).ToString('o')
    }

    $resolvedStateLabel = ''
    if ([string]::IsNullOrWhiteSpace($StateLabel)) {
        $resolvedStateLabel = (($State -replace '_', ' ').ToUpperInvariant())
    }
    else {
        $resolvedStateLabel = $StateLabel
    }

    $currentStep = ''
    if (-not [string]::IsNullOrWhiteSpace($trainingCurrentStageId)) {
        $currentStep = $trainingCurrentStageId
    }
    $activeState = [bool]([string]::Equals($State, 'running', [System.StringComparison]::OrdinalIgnoreCase))

    $resolutionSummaries = @()
    foreach ($event in $trainingRecentEvents) {
        if ([string]$event.type -eq 'resolution') {
            $resolutionSummaries += [string]$event.summary
        }
    }

    $recentEvents = @()
    foreach ($event in $trainingRecentEvents) {
        $recentEvents += $event
    }

    $payload = [ordered]@{}
    $payload.generated_at = $now.ToString('o')
    $payload.source = 'tod-training-status-v1'
    $payload.run_id = $trainingRunId
    $payload.state = $State
    $payload.state_label = $resolvedStateLabel
    $payload.active = $activeState
    $payload.started_at = $trainingStartedAtUtc.ToString('o')
    $payload.updated_at = $now.ToString('o')
    $payload.runtime_seconds = $elapsedSeconds
    $payload.percent_complete = $percentComplete
    $payload.completed_steps = $completedSteps
    $payload.failed_steps = $failedSteps
    $payload.total_steps = $totalSteps
    $payload.phase = $Phase
    $payload.phase_label = $Phase
    $payload.phase_detail = $PhaseDetail
    $payload.current_step = $currentStep
    $payload.eta_seconds = $etaSeconds
    $payload.expected_completion_utc = $expectedCompletionUtc
    $payload.summary = $Summary
    $payload.latest_error = $trainingLatestError
    $payload.latest_error_at = $trainingLatestErrorAt
    $payload.latest_resolution = $trainingLatestResolution
    $payload.latest_resolution_at = $trainingLatestResolutionAt
    $payload.warnings = @($warnings)
    $payload.errors = @($errors)
    $payload.resolutions = @($resolutionSummaries)
    $payload.recent_events = @($recentEvents)
    $payload.stages = @($stageValues)
    $payload.artifacts = [ordered]@{
        output_dir = $effectiveOutputDir
        trace_path = $trainingTracePath
    }

    Write-Utf8NoBomJson -PathValue $trainingStatusPath -Payload $payload -Depth 20
    Update-IntegrationTrainingStatus -TrainingStatus $payload
}

function Start-TrainingStage {
    param(
        [Parameter(Mandatory = $true)][string]$StageId,
        [Parameter(Mandatory = $true)][string]$Detail
    )

    if ($trainingStageState.Contains($StageId)) {
        $trainingStageState[$StageId].status = 'running'
        $trainingStageState[$StageId].started_at = (Get-Date).ToUniversalTime().ToString('o')
        $trainingStageState[$StageId].detail = $Detail
        $trainingCurrentStageId = $StageId
    }

    Add-TrainingEvent -Type 'stage' -Summary $Detail
    Publish-TrainingStatus -State 'running' -Phase $StageId -StateLabel 'TRAINING ACTIVE' -Summary $Detail -PhaseDetail $Detail
}

function Complete-TrainingStage {
    param(
        [Parameter(Mandatory = $true)][string]$StageId,
        [Parameter(Mandatory = $true)][string]$Resolution
    )

    if ($trainingStageState.Contains($StageId)) {
        $trainingStageState[$StageId].status = 'completed'
        $trainingStageState[$StageId].completed_at = (Get-Date).ToUniversalTime().ToString('o')
        $trainingStageState[$StageId].detail = $Resolution
    }

    $trainingLatestResolution = $Resolution
    $trainingLatestResolutionAt = (Get-Date).ToUniversalTime().ToString('o')
    Add-TrainingEvent -Type 'resolution' -Summary $Resolution
    Publish-TrainingStatus -State 'running' -Phase $StageId -StateLabel 'TRAINING ACTIVE' -Summary $Resolution -PhaseDetail $Resolution
}

function Fail-TrainingStage {
    param(
        [Parameter(Mandatory = $true)][string]$StageId,
        [Parameter(Mandatory = $true)][string]$ErrorText,
        [Parameter(Mandatory = $true)][string]$Resolution
    )

    if ($trainingStageState.Contains($StageId)) {
        $trainingStageState[$StageId].status = 'failed'
        $trainingStageState[$StageId].completed_at = (Get-Date).ToUniversalTime().ToString('o')
        $trainingStageState[$StageId].detail = $ErrorText
    }

    $trainingLatestError = $ErrorText
    $trainingLatestErrorAt = (Get-Date).ToUniversalTime().ToString('o')
    $trainingLatestResolution = $Resolution
    $trainingLatestResolutionAt = (Get-Date).ToUniversalTime().ToString('o')
    Add-TrainingEvent -Type 'error' -Summary $ErrorText
    Add-TrainingEvent -Type 'resolution' -Summary $Resolution
    Publish-TrainingStatus -State 'running' -Phase $StageId -StateLabel 'TRAINING ACTIVE' -Summary $ErrorText -PhaseDetail $Resolution
}

Write-TrainingTrace -Message 'training-loop-started'
Add-TrainingEvent -Type 'lifecycle' -Summary 'Training loop started.'
Publish-TrainingStatus -State 'running' -Phase 'startup' -StateLabel 'TRAINING ACTIVE' -Summary 'Training loop started.' -PhaseDetail 'Initializing bounded training run.'

function Invoke-TodJsonAction {
    param(
        [Parameter(Mandatory = $true)][string]$Action,
        [hashtable]$ExtraArgs = @{}
    )

    $params = @{
        Action = $Action
        ConfigPath = $effectiveConfigPath
        Top = $Top
    }

    foreach ($key in $ExtraArgs.Keys) {
        $params[$key] = $ExtraArgs[$key]
    }

    $raw = & $todScript @params
    return ($raw | ConvertFrom-Json)
}

function Get-ResourceFileInfo {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -Path $Path)) {
        return $null
    }

    $item = Get-Item -Path $Path
    return [pscustomobject]@{
        path = $Path.Substring($repoRoot.Length).TrimStart([char[]]@([char]92, [char]47)) -replace "\\", "/"
        bytes = [int64]$item.Length
        updated_at = [string]$item.LastWriteTimeUtc.ToString("o")
    }
}

function Test-StateFileWritable {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -Path $Path)) {
        return $true
    }

    $stream = $null
    try {
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
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

function Test-ShouldUseLightweightStateBus {
    if (-not (Test-Path -Path $statePath)) {
        return $true
    }

    try {
        $item = Get-Item -Path $statePath -ErrorAction Stop
        return ([int64]$item.Length -gt [int64]$maxStateReadBytes)
    }
    catch {
        return $true
    }
}

function Get-LightweightStateBus {
    $raw = & $lightweightStateBusScript -AsJson
    return ($raw | ConvertFrom-Json)
}

function Read-JsonFileIfExists {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -Path $Path)) {
        return $null
    }

    try {
        return (Get-Content -Path $Path -Raw | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Invoke-ChildPowerShellJsonScript {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [hashtable]$Arguments = @{}
    )

    $powershellExe = Join-Path $PSHOME 'powershell.exe'
    if (-not (Test-Path -Path $powershellExe)) {
        $powershellExe = 'powershell.exe'
    }

    $invocationArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ScriptPath)
    foreach ($entry in $Arguments.GetEnumerator() | Sort-Object Key) {
        $name = [string]$entry.Key
        $value = $entry.Value

        if ($value -is [System.Management.Automation.SwitchParameter]) {
            if ([bool]$value.IsPresent) {
                $invocationArgs += ('-' + $name)
            }
            continue
        }

        if ($value -is [bool]) {
            if ([bool]$value) {
                $invocationArgs += ('-' + $name)
            }
            continue
        }

        if ($null -eq $value) {
            continue
        }

        $invocationArgs += ('-' + $name)
        $invocationArgs += [string]$value
    }

    $stdoutPath = Join-Path $env:TEMP ("tod-child-" + [guid]::NewGuid().ToString('N') + ".stdout.log")
    $stderrPath = Join-Path $env:TEMP ("tod-child-" + [guid]::NewGuid().ToString('N') + ".stderr.log")

    try {
        $process = Start-Process -FilePath $powershellExe -ArgumentList $invocationArgs -PassThru -Wait -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
        $stdout = if (Test-Path -Path $stdoutPath) { [string](Get-Content -Path $stdoutPath -Raw) } else { '' }
        $stderr = if (Test-Path -Path $stderrPath) { [string](Get-Content -Path $stderrPath -Raw) } else { '' }
        if ($process.ExitCode -ne 0) {
            $detail = if (-not [string]::IsNullOrWhiteSpace($stderr)) { $stderr.Trim() } elseif (-not [string]::IsNullOrWhiteSpace($stdout)) { $stdout.Trim() } else { 'no child output captured' }
            throw "Child script failed with exit code $($process.ExitCode): $ScriptPath :: $detail"
        }

        return $stdout
    }
    finally {
        foreach ($tempPath in @($stdoutPath, $stderrPath)) {
            if (Test-Path -Path $tempPath) {
                Remove-Item -Path $tempPath -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

$testSummary = $null
$smokeSummary = $null
$projectLibrary = $null
$reliabilityRecovery = $null
$runtimeSafeSubset = $null
$errors = @()
$warnings = @()
$stateFileWritable = $true
$preferBoundedRuntimeSubset = $false

try {
    $preferBoundedRuntimeSubset = (Test-ShouldUseLightweightStateBus)
}
catch {
    $preferBoundedRuntimeSubset = $false
}

$trainingStages = @(
    [pscustomobject]@{ id = 'tests'; label = 'Regression tests'; enabled = (-not $SkipTests) },
    [pscustomobject]@{ id = 'smoke'; label = 'Smoke checks'; enabled = (-not $SkipSmoke) },
    [pscustomobject]@{ id = 'reliability_recovery'; label = 'Reliability recovery'; enabled = (-not $preferBoundedRuntimeSubset) },
    [pscustomobject]@{ id = 'runtime_safe_subset'; label = 'Runtime-safe subset'; enabled = $true },
    [pscustomobject]@{ id = 'project_discovery'; label = 'Project discovery'; enabled = (-not $SkipProjectDiscovery) },
    [pscustomobject]@{ id = 'report'; label = 'Report publish'; enabled = $true }
)
foreach ($stage in @($trainingStages | Where-Object { [bool]$_.enabled })) {
    $trainingStageState[$stage.id] = [pscustomobject]@{
        id = [string]$stage.id
        label = [string]$stage.label
        status = 'pending'
        started_at = ''
        completed_at = ''
        detail = ''
    }
}

if (-not $SkipTests) {
    try {
        $statePath = Join-Path $repoRoot "tod/data/state.json"
        $stateFileWritable = (Test-StateFileWritable -Path $statePath)
        if ($preferBoundedRuntimeSubset) {
            $warnings += "tests: skipped because lightweight-state-bus mode prefers bounded under-lock runtime-safe validation"
            $SkipTests = $true
        }
        elseif (-not $stateFileWritable) {
            $warnings += "tests: skipped because tod/data/state.json is locked during active runtime"
            $SkipTests = $true
        }
    }
    catch {
        $errors += "tests precheck: $($_.Exception.Message)"
    }
}

if (-not $SkipSmoke -and ($preferBoundedRuntimeSubset -or -not $stateFileWritable)) {
    $warnings += "smoke: skipped because bounded under-lock runtime-safe subset is preferred during lightweight-state-bus or locked-state execution"
    $SkipSmoke = $true
}

if (-not $SkipTests) {
    try {
        Start-TrainingStage -StageId 'tests' -Detail 'Running regression tests.'
        Write-TrainingTrace -Message 'tests-start'
        $testsOut = Join-Path $effectiveOutputDir "test-summary.json"
        $testsRaw = Invoke-ChildPowerShellJsonScript -ScriptPath $testsScript -Arguments @{
            Path = 'tests/*.Tests.ps1'
            JsonOutputPath = $testsOut
        }
        $testSummary = Read-JsonFileIfExists -Path $testsOut
        if ($null -eq $testSummary) {
            $testSummary = $testsRaw | ConvertFrom-Json
        }
        Write-TrainingTrace -Message 'tests-complete'
        Complete-TrainingStage -StageId 'tests' -Resolution ('Regression tests completed. Passed={0} Failed={1}.' -f $(if ($testSummary -and $testSummary.PSObject.Properties['passed']) { [string]$testSummary.passed } else { '?' }), $(if ($testSummary -and $testSummary.PSObject.Properties['failed']) { [string]$testSummary.failed } else { '?' }))
    }
    catch {
        Write-TrainingTrace -Message ("tests-error: {0}" -f $_.Exception.Message)
        $errors += "tests: $($_.Exception.Message)"
        Fail-TrainingStage -StageId 'tests' -ErrorText ('Regression tests failed: {0}' -f $_.Exception.Message) -Resolution 'Continue with bounded training, capture the failure in the live status feed, and rely on downstream runtime-safe validation.'
    }
}

if (-not $SkipSmoke) {
    try {
        Start-TrainingStage -StageId 'smoke' -Detail 'Running smoke checks.'
        Write-TrainingTrace -Message 'smoke-start'
        $smokeOut = Join-Path $effectiveOutputDir "smoke-summary.json"
        $smokeRaw = (& $smokeScript -Top $Top -JsonOutputPath $smokeOut -SkipSharedStateSync | Out-String)
        $smokeSummary = Read-JsonFileIfExists -Path $smokeOut
        if ($null -eq $smokeSummary) {
            $smokeSummary = $smokeRaw | ConvertFrom-Json
            $smokeSummary | ConvertTo-Json -Depth 12 | Set-Content -Path $smokeOut
        }
        Write-TrainingTrace -Message 'smoke-complete'
        Complete-TrainingStage -StageId 'smoke' -Resolution ('Smoke checks completed. PassedAll={0}.' -f $(if ($smokeSummary -and $smokeSummary.PSObject.Properties['passed_all']) { [string][bool]$smokeSummary.passed_all } else { '?' }))
    }
    catch {
        Write-TrainingTrace -Message ("smoke-error: {0}" -f $_.Exception.Message)
        $errors += "smoke: $($_.Exception.Message)"
        Fail-TrainingStage -StageId 'smoke' -ErrorText ('Smoke checks failed: {0}' -f $_.Exception.Message) -Resolution 'Keep training moving, record the smoke failure, and continue into bounded runtime-safe validation.'
    }
}

if ($preferBoundedRuntimeSubset) {
    Write-TrainingTrace -Message 'reliability-recovery-deferred-to-subset'
}
else {
    try {
        Start-TrainingStage -StageId 'reliability_recovery' -Detail 'Running reliability recovery drill.'
        Write-TrainingTrace -Message 'reliability-recovery-start'
        $recoveryRaw = Invoke-ChildPowerShellJsonScript -ScriptPath $reliabilityRecoveryDrillScript -Arguments @{
            ConfigPath = $effectiveConfigPath
            OutputDir = $effectiveOutputDir
            StatePath = $statePath
            Port = 8844
            EmitJson = $true
        }
        $reliabilityRecovery = Read-JsonFileIfExists -Path (Join-Path $effectiveOutputDir 'readiness-recovery.latest.json')
        if ($null -eq $reliabilityRecovery -and -not [string]::IsNullOrWhiteSpace($recoveryRaw)) {
            $reliabilityRecovery = $recoveryRaw | ConvertFrom-Json
        }
        if ($null -eq $reliabilityRecovery) {
            throw 'Reliability recovery artifact was not produced.'
        }
        if ($SkipTests -and $reliabilityRecovery.PSObject.Properties['summary'] -and [bool]$reliabilityRecovery.summary.runtime_safe_validation) {
            $warnings += "reliability-drill: executed runtime-safe readiness recovery validation while full tests were skipped"
        }
        Write-TrainingTrace -Message 'reliability-recovery-complete'
        Complete-TrainingStage -StageId 'reliability_recovery' -Resolution ('Reliability recovery completed. Recovered={0}.' -f $(if ($reliabilityRecovery -and $reliabilityRecovery.PSObject.Properties['summary'] -and $reliabilityRecovery.summary.PSObject.Properties['recovered']) { [string][bool]$reliabilityRecovery.summary.recovered } else { '?' }))
    }
    catch {
        Write-TrainingTrace -Message ("reliability-recovery-error: {0}" -f $_.Exception.Message)
        $errors += "reliability-recovery: $($_.Exception.Message)"
        Fail-TrainingStage -StageId 'reliability_recovery' -ErrorText ('Reliability recovery failed: {0}' -f $_.Exception.Message) -Resolution 'Capture the failure and continue into runtime-safe subset validation for bounded recovery evidence.'
    }
}

try {
    Start-TrainingStage -StageId 'runtime_safe_subset' -Detail 'Running runtime-safe validation subset.'
    Write-TrainingTrace -Message 'runtime-safe-subset-start'
    $runtimeSafeSubsetArgs = @{
        ConfigPath = $effectiveConfigPath
        OutputDir = $effectiveOutputDir
        StatePath = $statePath
        Port = 8844
        EmitJson = $true
    }
    if ($null -ne $reliabilityRecovery) {
        $runtimeSafeSubsetArgs['RecoveryArtifactPath'] = (Join-Path $effectiveOutputDir 'readiness-recovery.latest.json')
    }
    $runtimeSafeSubsetRaw = Invoke-ChildPowerShellJsonScript -ScriptPath $runtimeSafeSubsetScript -Arguments $runtimeSafeSubsetArgs
    $runtimeSafeSubset = Read-JsonFileIfExists -Path (Join-Path $effectiveOutputDir 'runtime-safe-validation-subset.latest.json')
    if ($null -eq $runtimeSafeSubset -and -not [string]::IsNullOrWhiteSpace($runtimeSafeSubsetRaw)) {
        $runtimeSafeSubset = $runtimeSafeSubsetRaw | ConvertFrom-Json
    }
    if ($null -eq $runtimeSafeSubset) {
        throw 'Runtime-safe validation subset artifact was not produced.'
    }
    if ($null -eq $reliabilityRecovery -and $runtimeSafeSubset.PSObject.Properties['artifacts'] -and $runtimeSafeSubset.artifacts.PSObject.Properties['readiness_recovery'] -and -not [string]::IsNullOrWhiteSpace([string]$runtimeSafeSubset.artifacts.readiness_recovery)) {
        $reliabilityRecovery = Read-JsonFileIfExists -Path ([string]$runtimeSafeSubset.artifacts.readiness_recovery)
    }
    if ($null -ne $reliabilityRecovery -and $SkipTests -and $reliabilityRecovery.PSObject.Properties['summary'] -and [bool]$reliabilityRecovery.summary.runtime_safe_validation) {
        $warnings += "reliability-drill: executed runtime-safe readiness recovery validation while full tests were skipped"
    }
    if ($SkipTests -and $runtimeSafeSubset.PSObject.Properties['summary'] -and [bool]$runtimeSafeSubset.summary.runtime_safe_validation) {
        $warnings += "runtime-safe-subset: executed bounded under-lock validation while full tests were skipped"
    }
    Write-TrainingTrace -Message 'runtime-safe-subset-complete'
    Complete-TrainingStage -StageId 'runtime_safe_subset' -Resolution ('Runtime-safe validation completed. PassedAll={0} RecoveryOk={1}.' -f $(if ($runtimeSafeSubset -and $runtimeSafeSubset.PSObject.Properties['summary'] -and $runtimeSafeSubset.summary.PSObject.Properties['passed_all']) { [string][bool]$runtimeSafeSubset.summary.passed_all } else { '?' }), $(if ($runtimeSafeSubset -and $runtimeSafeSubset.PSObject.Properties['summary'] -and $runtimeSafeSubset.summary.PSObject.Properties['recovery_ok']) { [string][bool]$runtimeSafeSubset.summary.recovery_ok } else { '?' }))
}
catch {
    Write-TrainingTrace -Message ("runtime-safe-subset-error: {0}" -f $_.Exception.Message)
    $errors += "runtime-safe-subset: $($_.Exception.Message)"
    Fail-TrainingStage -StageId 'runtime_safe_subset' -ErrorText ('Runtime-safe validation failed: {0}' -f $_.Exception.Message) -Resolution 'Record the bounded validation failure and keep producing the training report so the UI shows the exact fault.'
}

if (-not $SkipProjectDiscovery) {
    try {
        Start-TrainingStage -StageId 'project_discovery' -Detail 'Refreshing project discovery index.'
        Write-TrainingTrace -Message 'project-discovery-start'
        $projectLibraryRaw = & $projectLibraryScript -RootPath $LibraryRoot -RegistryPath 'tod/config/project-registry.json' -OutputPath 'tod/data/project-library-index.json'
        $projectLibrary = $projectLibraryRaw | ConvertFrom-Json
        Write-TrainingTrace -Message 'project-discovery-complete'
        Complete-TrainingStage -StageId 'project_discovery' -Resolution ('Project discovery completed. Projects={0}.' -f $(if ($projectLibrary -and $projectLibrary.PSObject.Properties['projects']) { [string]@($projectLibrary.projects).Count } else { '?' }))
    }
    catch {
        Write-TrainingTrace -Message ("project-discovery-error: {0}" -f $_.Exception.Message)
        $errors += "project-discovery: $($_.Exception.Message)"
        Fail-TrainingStage -StageId 'project_discovery' -ErrorText ('Project discovery failed: {0}' -f $_.Exception.Message) -Resolution 'Leave project discovery degraded for this run and finish the report with the captured failure context.'
    }
}

$stateBus = $null
$reliability = $null
$dashboard = $null
$taxonomy = $null
$loopSummary = $null
$signal = $null
$history = $null
$lightweightEvidence = $null

$useLightweightEvidence = Test-ShouldUseLightweightStateBus

if ($useLightweightEvidence) {
    try {
        $lightweightEvidence = Get-LightweightStateBus
        $stateBus = $lightweightEvidence
        $reliability = if ($lightweightEvidence.PSObject.Properties['reliability']) { $lightweightEvidence.reliability } else { $null }
        $dashboard = if ($lightweightEvidence.PSObject.Properties['reliability_dashboard']) { $lightweightEvidence.reliability_dashboard } else { $null }
        $taxonomy = if ($lightweightEvidence.PSObject.Properties['failure_taxonomy']) { $lightweightEvidence.failure_taxonomy } else { $null }
        $loopSummary = if ($lightweightEvidence.PSObject.Properties['engineering_summary']) { $lightweightEvidence.engineering_summary } else { $null }
        $signal = if ($lightweightEvidence.PSObject.Properties['engineering_signal']) { $lightweightEvidence.engineering_signal } else { $null }
        $history = if ($lightweightEvidence.PSObject.Properties['scorecard_history']) { $lightweightEvidence.scorecard_history } else { $null }
    }
    catch {
        $errors += "lightweight-telemetry: $($_.Exception.Message)"
    }
}

if (-not $useLightweightEvidence) {
    try {
        $stateBus = Invoke-TodJsonAction -Action "get-state-bus"
    }
    catch {
        try {
            $lightweightEvidence = Get-LightweightStateBus
            $stateBus = $lightweightEvidence
            $reliability = $lightweightEvidence.reliability
            $dashboard = $lightweightEvidence.reliability_dashboard
            $taxonomy = $lightweightEvidence.failure_taxonomy
            $loopSummary = $lightweightEvidence.engineering_summary
            $signal = $lightweightEvidence.engineering_signal
            $history = $lightweightEvidence.scorecard_history
            $useLightweightEvidence = $true
        }
        catch {
            $errors += "state-bus: $($_.Exception.Message)"
        }
    }
}

if (-not $useLightweightEvidence) {
    try { $reliability = Invoke-TodJsonAction -Action "get-reliability" } catch { $errors += "reliability: $($_.Exception.Message)" }
    try { $dashboard = Invoke-TodJsonAction -Action "show-reliability-dashboard" } catch { $errors += "dashboard: $($_.Exception.Message)" }
    try { $taxonomy = Invoke-TodJsonAction -Action "show-failure-taxonomy" } catch { $errors += "taxonomy: $($_.Exception.Message)" }
    try { $loopSummary = Invoke-TodJsonAction -Action "get-engineering-loop-summary" } catch { $errors += "loop-summary: $($_.Exception.Message)" }
    try { $signal = Invoke-TodJsonAction -Action "get-engineering-signal" } catch { $errors += "signal: $($_.Exception.Message)" }
    try { $history = Invoke-TodJsonAction -Action "get-engineering-loop-history" -ExtraArgs @{ HistoryKind = "scorecard_history"; Page = 1; PageSize = 25 } } catch { $errors += "history: $($_.Exception.Message)" }
}

$resources = @()
$seedFiles = @(
    "tod/data/engineering-memory.json",
    "tod/data/repo-index.json",
    "tod/data/module-summaries.json",
    "tod/config/project-registry.json",
    "tod/config/project-priority.json",
    "tod/config/media-pipeline-profiles.json",
    "tod/config/media-runtime.json",
    "tod/config/context-exchange.json",
    "tod/data/project-library-index.json",
    "scripts/Test-TODProjectAccessPolicy.ps1",
    "scripts/Get-TODProjectExecutionQueue.ps1",
    "scripts/Invoke-TODProjectQueueRunner.ps1",
    "scripts/Invoke-TODMediaPipeline.ps1",
    "scripts/Invoke-TODContextExchange.ps1",
    "tod/data/sample-codex-result.json",
    "tod/data/sample-journal-post.json",
    "tod/config/tod-config.json",
    "docs/tod-command-reference.md",
    "docs/tod-state-bus-contract-v1.md",
    "docs/tod-mim-shared-contract-v1.md",
    "docs/tod-mim-context-exchange-v1.md",
    "docs/mim-tod-execution-feedback-contract-v1.md",
    "docs/codex-result-format-v1.md"
)

foreach ($rel in $seedFiles) {
    $full = Join-Path $repoRoot $rel
    $info = Get-ResourceFileInfo -Path $full
    if ($null -ne $info) { $resources += $info }
}

$docsDir = Join-Path $repoRoot "docs"
if (Test-Path -Path $docsDir) {
    $docs = @(Get-ChildItem -Path $docsDir -Filter "*.md" | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 10)
    foreach ($doc in $docs) {
        $entry = [pscustomobject]@{
            path = $doc.FullName.Substring($repoRoot.Length).TrimStart([char[]]@([char]92, [char]47)) -replace "\\", "/"
            bytes = [int64]$doc.Length
            updated_at = [string]$doc.LastWriteTimeUtc.ToString("o")
        }
        $resources += $entry
    }
}

$resources = @($resources | Sort-Object path -Unique)

$governanceScore = 0
if ($stateBus -and $stateBus.PSObject.Properties["blocks"] -and $stateBus.blocks) { $governanceScore += 1 }
if ($signal -and $signal.PSObject.Properties["pending_approval_state"]) { $governanceScore += 1 }
if ($history -and $history.PSObject.Properties["items"]) { $governanceScore += 1 }
if ($signal -and $signal.PSObject.Properties["stop_reason"]) { $governanceScore += 1 }
if ($stateBus -and $stateBus.PSObject.Properties["engineering_loop_state"]) { $governanceScore += 1 }

$reliabilityScore = 0
if ($reliability -and $reliability.PSObject.Properties["current_alert_state"]) { $reliabilityScore += 2 }
if ($dashboard -and $dashboard.PSObject.Properties["retry_trend"]) { $reliabilityScore += 1 }
if ($dashboard -and $dashboard.PSObject.Properties["drift_warnings"]) { $reliabilityScore += 1 }
if ($taxonomy -and $taxonomy.PSObject.Properties["groups"]) { $reliabilityScore += 1 }

$workflowScore = 0
if ($loopSummary -and $loopSummary.PSObject.Properties["latest_score"]) { $workflowScore += 1 }
if ($signal -and $signal.PSObject.Properties["trend_direction"]) { $workflowScore += 1 }
if ($signal -and $signal.PSObject.Properties["phase_snapshot"]) { $workflowScore += 1 }
if ($stateBus -and $stateBus.PSObject.Properties["system_posture"]) { $workflowScore += 1 }
if ($history -and $history.PSObject.Properties["paging"]) { $workflowScore += 1 }

$runtimeScore = 0
if ($smokeSummary -and $smokeSummary.PSObject.Properties["passed_all"] -and [bool]$smokeSummary.passed_all) {
    $runtimeScore += 3
}
elseif ($runtimeSafeSubset -and $runtimeSafeSubset.PSObject.Properties['summary'] -and [bool]$runtimeSafeSubset.summary.passed_all) {
    $runtimeScore += 3
}
if ($testSummary -and $testSummary.PSObject.Properties["passed_all"] -and [bool]$testSummary.passed_all) { $runtimeScore += 2 }
if ($reliabilityRecovery -and $reliabilityRecovery.PSObject.Properties['summary'] -and [bool]$reliabilityRecovery.summary.recovered) { $runtimeScore += 1 }

$competency = [pscustomobject]@{
    governance_and_control = [Math]::Min($governanceScore, 5)
    reliability_awareness = [Math]::Min($reliabilityScore, 5)
    workflow_structure = [Math]::Min($workflowScore, 5)
    runtime_interaction = [Math]::Min($runtimeScore, 5)
}

$nextDrills = @(
    [pscustomobject]@{
        id = "drill-root-cause"
        title = "Root cause over patching"
        objective = "Fix one failing behavior with minimal surface area and explicit root-cause notes."
        evidence = @("tests/*.Tests.ps1", "show-failure-taxonomy", "recent journal entries")
    },
    [pscustomobject]@{
        id = "drill-multi-file"
        title = "Cross-module feature slice"
        objective = "Ship one feature requiring coordinated runtime + UI + tests + docs updates."
        evidence = @("get-state-bus", "get-engineering-signal", "Invoke-TODTests")
    },
    [pscustomobject]@{
        id = "drill-reliability"
        title = "Reliability regression recovery"
        objective = "Induce and recover from a degraded alert state while keeping guardrails intact."
        evidence = @("get-reliability", "show-reliability-dashboard", "Invoke-TODSmoke")
    },
    [pscustomobject]@{
        id = "drill-project-discovery"
        title = "Cross-project architecture mapping"
        objective = "Refresh project registry, verify boundaries, and summarize risky zones before implementation work."
        evidence = @("tod/config/project-registry.json", "tod/data/project-library-index.json", "Update-TODProjectLibrary")
    },
    [pscustomobject]@{
        id = "drill-policy-enforcement"
        title = "Policy-gated implementation"
        objective = "Validate proposed edits against allowed/blocked path boundaries before patching."
        evidence = @("scripts/Test-TODProjectAccessPolicy.ps1", "tod/config/project-registry.json")
    },
    [pscustomobject]@{
        id = "drill-media-pipeline"
        title = "Media generation workflow"
        objective = "Route content generation tasks through project media profiles with artifact manifests."
        evidence = @("tod/config/media-pipeline-profiles.json", "tod/config/project-priority.json", "scripts/Get-TODProjectExecutionQueue.ps1")
    }
)

$report = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = "tod-training-loop-v1"
    config_path = $effectiveConfigPath
    output_dir = $effectiveOutputDir
    run = [pscustomobject]@{
        tests = if ($null -ne $testSummary) { $testSummary } else { [pscustomobject]@{ skipped = [bool]$SkipTests } }
        smoke = if ($null -ne $smokeSummary) { $smokeSummary } else { [pscustomobject]@{ skipped = [bool]$SkipSmoke } }
        reliability_recovery = if ($null -ne $reliabilityRecovery) { $reliabilityRecovery.summary } else { [pscustomobject]@{ skipped = $false; ok = $false } }
        runtime_safe_subset = if ($null -ne $runtimeSafeSubset) { $runtimeSafeSubset.summary } else { [pscustomobject]@{ skipped = $false; ok = $false } }
        project_discovery = if ($null -ne $projectLibrary) { [pscustomobject]@{ skipped = $false; projects = @($projectLibrary.projects).Count; unregistered = @($projectLibrary.unregistered_top_level_directories).Count } } else { [pscustomobject]@{ skipped = [bool]$SkipProjectDiscovery } }
        warnings = @($warnings)
        errors = @($errors)
    }
    resources = [pscustomobject]@{
        total = @($resources).Count
        files = @($resources)
    }
    evidence = [pscustomobject]@{
        engineering_signal = $signal
        engineering_summary = $loopSummary
        state_bus = $stateBus
        reliability = $reliability
        reliability_dashboard = $dashboard
        reliability_recovery = $reliabilityRecovery
        runtime_safe_subset = $runtimeSafeSubset
        failure_taxonomy = $taxonomy
        scorecard_history = $history
        project_library = $projectLibrary
    }
    competency_snapshot = $competency
    next_drills = @($nextDrills)
}

$jsonPath = Join-Path $effectiveOutputDir "training-report.json"
$mdPath = Join-Path $effectiveOutputDir "training-report.md"
Start-TrainingStage -StageId 'report' -Detail 'Publishing training report artifacts.'
Write-TrainingTrace -Message 'report-write-start'
$report | ConvertTo-Json -Depth 30 | Set-Content -Path $jsonPath

$md = @()
$md += "# TOD Training Report"
Complete-TrainingStage -StageId 'report' -Resolution 'Training report artifacts were written.'
$md += ""
$md += "Generated: $($report.generated_at)"
$md += ""
$md += "## Competency Snapshot"
$md += "- Governance and control: $($report.competency_snapshot.governance_and_control)/5"
$md += "- Reliability awareness: $($report.competency_snapshot.reliability_awareness)/5"
$md += "- Workflow structure: $($report.competency_snapshot.workflow_structure)/5"
$md += "- Runtime interaction: $($report.competency_snapshot.runtime_interaction)/5"
$md += ""
$md += "## Existing Consumable Resources"
$md += "- Total files: $($report.resources.total)"
foreach ($file in @($report.resources.files | Select-Object -First 20)) {
    $md += "- $($file.path)"
}
$md += ""
$md += "## Run Summary"
if ($null -ne $testSummary) {
    $md += "- Tests: passed=$($testSummary.passed) failed=$($testSummary.failed)"
} else {
    $md += "- Tests: skipped"
}
if ($null -ne $smokeSummary) {
    $md += "- Smoke checks passed: $([bool]$smokeSummary.passed_all)"
} else {
    $md += "- Smoke checks: skipped"
}
if ($null -ne $reliabilityRecovery) {
    $md += "- Reliability recovery drill: recovered=$([bool]$reliabilityRecovery.summary.recovered) blocked=$([bool]$reliabilityRecovery.summary.blocked_enforced) degraded=$([bool]$reliabilityRecovery.summary.degraded_enforced)"
} else {
    $md += "- Reliability recovery drill: unavailable"
}
if ($null -ne $runtimeSafeSubset) {
    $md += "- Runtime-safe validation subset: passed=$([bool]$runtimeSafeSubset.summary.passed_all) recovery_ok=$([bool]$runtimeSafeSubset.summary.recovery_ok) sweep_ok=$([bool]$runtimeSafeSubset.summary.sweep_artifact_ok)"
} else {
    $md += "- Runtime-safe validation subset: unavailable"
}
if ($null -ne $projectLibrary) {
    $md += "- Project discovery: projects=$(@($projectLibrary.projects).Count) unregistered_top_level=$(@($projectLibrary.unregistered_top_level_directories).Count)"
} else {
    $md += "- Project discovery: skipped"
}
if (@($warnings).Count -gt 0) {
    $md += "- Warnings:"
    foreach ($w in $warnings) {
        $md += "  - $w"
    }
}
if (@($errors).Count -gt 0) {
    $md += "- Errors:"
    foreach ($e in $errors) {
        $md += "  - $e"
    }
}
$md += ""
$md += "## Next Drills"
foreach ($drill in $nextDrills) {
    $md += "- [$($drill.id)] $($drill.title): $($drill.objective)"
}

$md -join [Environment]::NewLine | Set-Content -Path $mdPath
Write-TrainingTrace -Message 'report-write-complete'

$result = [pscustomobject]@{
    ok = (@($errors).Count -eq 0)
    path = "/tod/training/report"
    source = "tod-training-loop-v1"
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    report_json = $jsonPath
    report_markdown = $mdPath
    competency_snapshot = $competency
    resources_count = @($resources).Count
    warnings = @($warnings)
    errors = @($errors)
    training_status = $trainingStatusPath
}

Add-TrainingEvent -Type 'lifecycle' -Summary 'Training loop finished.'
Publish-TrainingStatus -State $(if (@($errors).Count -gt 0) { 'completed_with_errors' } else { 'completed' }) -Phase 'complete' -StateLabel $(if (@($errors).Count -gt 0) { 'TRAINING COMPLETE WITH ERRORS' } else { 'TRAINING COMPLETE' }) -Summary $(if (@($errors).Count -gt 0) { 'Training completed with captured errors.' } else { 'Training completed successfully.' }) -PhaseDetail 'Final report and artifacts are available.'

$result | ConvertTo-Json -Depth 10 | Write-Output
Write-TrainingTrace -Message 'training-loop-complete'

if ($FailOnError -and @($errors).Count -gt 0) {
    throw "Training loop completed with errors."
}
