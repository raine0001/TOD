param(
    [string]$ConfigPath,
    [string]$OutputDir,
    [string]$UiBaseUrl = 'http://127.0.0.1:8844',
    [double]$DurationHours = 6,
    [int]$WindowOneBoundedRuns = 1,
    [int]$WindowTwoBoundedRuns = 1,
    [int]$SupervisedTimeoutMinutes = 20,
    [int]$BoundedTimeoutMinutes = 45,
    [int]$MaxChildRetries = 2,
    [switch]$SkipProjectDiscovery,
    [switch]$NoWait,
    [switch]$FailOnStopCondition
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$trainingScript = Join-Path $PSScriptRoot 'Invoke-TODTrainingLoop.ps1'
$supervisedScript = Join-Path $PSScriptRoot 'Invoke-TODSupervisedExecution.ps1'

function Resolve-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return $PathValue
    }

    return (Join-Path $repoRoot $PathValue)
}

function Ensure-Directory {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if (-not (Test-Path -Path $PathValue)) {
        New-Item -ItemType Directory -Path $PathValue -Force | Out-Null
    }
}

function Get-DateOrMinValue {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return [datetime]::MinValue
    }

    try {
        return [datetime]::Parse($Value).ToUniversalTime()
    }
    catch {
        return [datetime]::MinValue
    }
}

function Write-RunbookTrace {
    param(
        [Parameter(Mandatory = $true)][string]$LogPath,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $line = '[{0}] {1}' -f ((Get-Date).ToUniversalTime().ToString('o')), $Message
    Add-Content -Path $LogPath -Value $line
    Write-Host $line
}

function ConvertFrom-JsonLoose {
    param([Parameter(Mandatory = $true)][string]$Text)

    $trimmed = $Text.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        return $null
    }

    try {
        return ($trimmed | ConvertFrom-Json)
    }
    catch {
    }

    $candidateIndexes = New-Object System.Collections.Generic.List[int]
    for ($index = 0; $index -lt $trimmed.Length; $index++) {
        $char = $trimmed[$index]
        if ($char -eq '{' -or $char -eq '[') {
            $candidateIndexes.Add($index)
        }
    }

    for ($index = $candidateIndexes.Count - 1; $index -ge 0; $index--) {
        $startIndex = $candidateIndexes[$index]
        $candidate = $trimmed.Substring($startIndex)
        try {
            return ($candidate | ConvertFrom-Json)
        }
        catch {
        }
    }

    throw 'Unable to recover JSON payload from mixed output.'
}

function Invoke-ChildPowerShellJsonScript {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [hashtable]$Arguments = @{},
        [int]$TimeoutSeconds = 0
    )

    $powershellExe = Join-Path $PSHOME 'powershell.exe'
    if (-not (Test-Path -Path $powershellExe)) {
        $powershellExe = 'powershell.exe'
    }

    $invocationArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ScriptPath)
    foreach ($entry in ($Arguments.GetEnumerator() | Sort-Object Key)) {
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

    $stdoutPath = Join-Path $env:TEMP ('tod-runbook-' + [guid]::NewGuid().ToString('N') + '.stdout.log')
    $stderrPath = Join-Path $env:TEMP ('tod-runbook-' + [guid]::NewGuid().ToString('N') + '.stderr.log')

    try {
        $process = Start-Process -FilePath $powershellExe -ArgumentList $invocationArgs -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
        $deadlineUtc = $null
        if ($TimeoutSeconds -gt 0) {
            $deadlineUtc = (Get-Date).ToUniversalTime().AddSeconds($TimeoutSeconds)
        }

        while (-not $process.HasExited) {
            if ($null -ne $deadlineUtc -and (Get-Date).ToUniversalTime() -ge $deadlineUtc) {
                try {
                    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                }
                catch {
                }
                throw ('Child script timed out after {0}s: {1}' -f $TimeoutSeconds, $ScriptPath)
            }

            Start-Sleep -Seconds 5
            try {
                $process.Refresh()
            }
            catch {
            }
        }

        try {
            $process.WaitForExit()
        }
        catch {
        }

        $stdout = if (Test-Path -Path $stdoutPath) { [string](Get-Content -Path $stdoutPath -Raw) } else { '' }
        $stderr = if (Test-Path -Path $stderrPath) { [string](Get-Content -Path $stderrPath -Raw) } else { '' }
        $exitCode = 0
        if ($null -ne $process.ExitCode) {
            $exitCode = [int]$process.ExitCode
        }
        if ($exitCode -ne 0) {
            $detail = if (-not [string]::IsNullOrWhiteSpace($stderr)) { $stderr.Trim() } elseif (-not [string]::IsNullOrWhiteSpace($stdout)) { $stdout.Trim() } else { 'no child output captured' }
            throw ('Child script failed with exit code {0}: {1} :: {2}' -f $exitCode, $ScriptPath, $detail)
        }

        if ([string]::IsNullOrWhiteSpace($stdout)) {
            return $null
        }

        return (ConvertFrom-JsonLoose -Text $stdout)
    }
    finally {
        foreach ($tempPath in @($stdoutPath, $stderrPath)) {
            if (Test-Path -Path $tempPath) {
                Remove-Item -Path $tempPath -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

function Test-UiProjectStatusHealthy {
    param([Parameter(Mandatory = $true)][string]$BaseUrl)

    try {
        $null = Invoke-RestMethod -Uri (($BaseUrl.TrimEnd('/')) + '/api/project-status') -TimeoutSec 20
        return $true
    }
    catch {
        return $false
    }
}

function Get-BoundedTrainingAssessment {
    param([AllowNull()]$TrainingReport)

    if ($null -eq $TrainingReport) {
        return [pscustomobject]@{
            ok = $false
            runtime_safe_passed = $false
            recovery_ok = $false
            warnings = @('training_report_missing')
            errors = @('training_report_missing')
            healthy = $false
        }
    }

    $run = if ($TrainingReport.PSObject.Properties['run']) { $TrainingReport.run } else { $null }
    $runtimeSafe = if ($run -and $run.PSObject.Properties['runtime_safe_subset']) { $run.runtime_safe_subset } else { $null }
    $recovery = if ($run -and $run.PSObject.Properties['reliability_recovery']) { $run.reliability_recovery } else { $null }
    $warnings = if ($run -and $run.PSObject.Properties['warnings']) { @($run.warnings) } else { @() }
    $errors = if ($run -and $run.PSObject.Properties['errors']) { @($run.errors) } else { @() }

    $runtimeSafePassed = [bool]($runtimeSafe -and $runtimeSafe.PSObject.Properties['passed_all'] -and $runtimeSafe.passed_all)
    $recoveryOk = [bool](
        ($recovery -and $recovery.PSObject.Properties['recovered'] -and $recovery.recovered) -or
        ($recovery -and $recovery.PSObject.Properties['ok'] -and $recovery.ok)
    )

    return [pscustomobject]@{
        ok = (@($errors).Count -eq 0)
        runtime_safe_passed = $runtimeSafePassed
        recovery_ok = $recoveryOk
        warnings = @($warnings)
        errors = @($errors)
        healthy = ($runtimeSafePassed -and $recoveryOk -and (@($errors).Count -eq 0))
    }
}

function Get-SupervisedCheckpointAssessment {
    param([AllowNull()]$RunReport)

    if ($null -eq $RunReport) {
        return [pscustomobject]@{
            ok = $false
            escalated = $true
            escalation_reason = 'run_report_missing'
            receipt_ok = $false
            bridge_smoke_ok = $false
            healthy = $false
        }
    }

    $steps = if ($RunReport.PSObject.Properties['steps']) { $RunReport.steps } else { $null }
    $receiptOk = [bool]($steps -and $steps.PSObject.Properties['receipt_check'] -and $steps.receipt_check.PSObject.Properties['ok'] -and $steps.receipt_check.ok)
    $bridgeSmokeAttempted = [bool]($steps -and $steps.PSObject.Properties['bridge_smoke'] -and $steps.bridge_smoke.PSObject.Properties['attempted'] -and $steps.bridge_smoke.attempted)
    $bridgeSmokeOk = [bool]($steps -and $steps.PSObject.Properties['bridge_smoke'] -and $steps.bridge_smoke.PSObject.Properties['ok'] -and $steps.bridge_smoke.ok)
    $bridgeSmokeEffectiveOk = if ($bridgeSmokeAttempted) { $bridgeSmokeOk } else { $true }
    $escalated = [bool]($RunReport.PSObject.Properties['needs_escalation'] -and $RunReport.needs_escalation)
    $reason = if ($RunReport.PSObject.Properties['escalation_reason']) { [string]$RunReport.escalation_reason } else { '' }

    return [pscustomobject]@{
        ok = (-not $escalated)
        escalated = $escalated
        escalation_reason = $reason
        receipt_ok = $receiptOk
        bridge_smoke_ok = $bridgeSmokeEffectiveOk
        healthy = ((-not $escalated) -and $receiptOk -and $bridgeSmokeEffectiveOk)
    }
}

function Test-RunbookStopConditions {
    param(
        [int]$RuntimeSafeFailureStreak,
        [bool]$RecoveryHealthy,
        [bool]$UiHealthy,
        [bool]$ReceiptHealthy,
        [string]$SupervisedEscalationReason,
        [string]$PriorSupervisedEscalationReason,
        [int]$PriorSupervisedEscalationCount
    )

    $reasons = New-Object System.Collections.Generic.List[string]

    if (-not [string]::IsNullOrWhiteSpace($SupervisedEscalationReason)) {
        $reasons.Add('supervised_escalated')
    }
    if ($RuntimeSafeFailureStreak -ge 2) {
        $reasons.Add('runtime_safe_subset_failed_twice')
    }
    if (-not $RecoveryHealthy) {
        $reasons.Add('readiness_recovery_not_healthy')
    }
    if (-not $ReceiptHealthy) {
        $reasons.Add('receipt_or_bridge_smoke_not_healthy')
    }
    if (-not [string]::IsNullOrWhiteSpace($SupervisedEscalationReason) -and [string]::Equals($SupervisedEscalationReason, $PriorSupervisedEscalationReason, [System.StringComparison]::OrdinalIgnoreCase) -and $PriorSupervisedEscalationCount -ge 1) {
        $reasons.Add('supervised_escalated_twice_same_reason')
    }

    return [pscustomobject]@{
        triggered = (@($reasons).Count -gt 0)
        reasons = @($reasons)
    }
}

function Get-RunbookOutcome {
    param(
        [string[]]$StopConditions = @(),
        [bool]$AllBoundedHealthy,
        [bool]$AllSupervisedHealthy,
        [bool]$QuietWindowRecommended
    )

    if (@($StopConditions).Count -gt 0) {
        return 'root_cause_investigation_required'
    }
    if ($AllBoundedHealthy -and $AllSupervisedHealthy -and $QuietWindowRecommended) {
        return 'ready_for_quiet_window_full_run'
    }
    if ($AllBoundedHealthy -and $AllSupervisedHealthy) {
        return 'stable_bounded_lane'
    }
    return 'root_cause_investigation_required'
}

function Wait-UntilUtc {
    param(
        [datetime]$TargetUtc,
        [switch]$NoWait
    )

    if ($NoWait) {
        return
    }

    while ((Get-Date).ToUniversalTime() -lt $TargetUtc) {
        $remaining = [int][math]::Ceiling((New-TimeSpan -Start (Get-Date).ToUniversalTime() -End $TargetUtc).TotalSeconds)
        if ($remaining -le 0) {
            break
        }

        $sleepSeconds = [math]::Min($remaining, 30)
        Start-Sleep -Seconds $sleepSeconds
    }
}

if (-not (Test-Path -Path $trainingScript)) {
    throw 'Missing training script: ' + $trainingScript
}
if (-not (Test-Path -Path $supervisedScript)) {
    throw 'Missing supervised script: ' + $supervisedScript
}

$effectiveConfigPath = if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    Join-Path $repoRoot 'tod/config/tod-config.json'
}
else {
    Resolve-LocalPath -PathValue $ConfigPath
}

if (-not (Test-Path -Path $effectiveConfigPath)) {
    throw 'Config file not found: ' + $effectiveConfigPath
}

$runStamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
$effectiveOutputDir = if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    Join-Path $repoRoot ('tod/out/training/runbook-6h-' + $runStamp)
}
else {
    Resolve-LocalPath -PathValue $OutputDir
}

Ensure-Directory -PathValue $effectiveOutputDir

$tracePath = Join-Path $effectiveOutputDir 'runbook-trace.log'
$jsonReportPath = Join-Path $effectiveOutputDir 'runbook-report.json'
$mdReportPath = Join-Path $effectiveOutputDir 'runbook-report.md'
$startUtc = (Get-Date).ToUniversalTime()
$duration = [timespan]::FromHours([math]::Max($DurationHours, 0.01))
$endUtc = $startUtc.Add($duration)
$midpointUtc = $startUtc.AddHours([math]::Max($DurationHours / 2.0, 0.005))

$report = [ordered]@{
    generated_at = $startUtc.ToString('o')
    source = 'tod-training-runbook-6h-v1'
    config_path = $effectiveConfigPath
    output_dir = $effectiveOutputDir
    ui_base_url = $UiBaseUrl
    duration_hours = $DurationHours
    no_wait = [bool]$NoWait
    checkpoints = @()
    stop_conditions = @()
    outcome = 'running'
}

$runtimeSafeFailureStreak = 0
$priorSupervisedEscalationReason = ''
$priorSupervisedEscalationCount = 0
$boundedHealthFlags = New-Object System.Collections.Generic.List[bool]
$supervisedHealthFlags = New-Object System.Collections.Generic.List[bool]

function Add-Checkpoint {
    param([Parameter(Mandatory = $true)]$Checkpoint)
    $report.checkpoints += @($Checkpoint)
}

function Invoke-SupervisedCheckpoint {
    param([Parameter(Mandatory = $true)][string]$Name)

    $runReportPath = Join-Path $effectiveOutputDir ('supervised-' + $Name + '.json')
    $escalationPath = Join-Path $effectiveOutputDir ('supervised-' + $Name + '.escalation.json')
    Write-RunbookTrace -LogPath $tracePath -Message ('supervised-start ' + $Name)
    $runReport = $null
    $attempts = [math]::Max($MaxChildRetries, 1)
    for ($attempt = 1; $attempt -le $attempts; $attempt++) {
        try {
            $runReport = Invoke-ChildPowerShellJsonScript -ScriptPath $supervisedScript -Arguments @{
                ImplementationConfigPath = $effectiveConfigPath
                ImplementationOutputDir = $effectiveOutputDir
                RefreshMimContextFromSsh = $true
                SkipImplementation = $true
                SkipTests = $true
                SkipBridgeSmoke = $true
                RunReportPath = $runReportPath
                EscalationStatePath = $escalationPath
            } -TimeoutSeconds ($SupervisedTimeoutMinutes * 60)

            if ($null -ne $runReport -and (-not [bool]$runReport.needs_escalation)) {
                break
            }

            if ($attempt -lt $attempts) {
                Write-RunbookTrace -LogPath $tracePath -Message ('supervised-retry ' + $Name + ' attempt=' + [string]$attempt + ' reason=' + [string]$(if ($null -ne $runReport) { $runReport.escalation_reason } else { 'empty_report' }))
            }
        }
        catch {
            if ($attempt -ge $attempts) {
                throw
            }
            Write-RunbookTrace -LogPath $tracePath -Message ('supervised-restart ' + $Name + ' attempt=' + [string]$attempt + ' error=' + [string]$_.Exception.Message)
        }
    }

    $assessment = Get-SupervisedCheckpointAssessment -RunReport $runReport
    $uiHealthy = Test-UiProjectStatusHealthy -BaseUrl $UiBaseUrl
    $stopEval = Test-RunbookStopConditions -RuntimeSafeFailureStreak $runtimeSafeFailureStreak -RecoveryHealthy $true -UiHealthy $uiHealthy -ReceiptHealthy $assessment.receipt_ok -SupervisedEscalationReason $assessment.escalation_reason -PriorSupervisedEscalationReason $priorSupervisedEscalationReason -PriorSupervisedEscalationCount $priorSupervisedEscalationCount
    if ($assessment.escalated) {
        if ([string]::Equals($assessment.escalation_reason, $priorSupervisedEscalationReason, [System.StringComparison]::OrdinalIgnoreCase)) {
            $priorSupervisedEscalationCount += 1
        }
        else {
            $priorSupervisedEscalationReason = $assessment.escalation_reason
            $priorSupervisedEscalationCount = 1
        }
    }
    else {
        $priorSupervisedEscalationReason = ''
        $priorSupervisedEscalationCount = 0
    }
    $supervisedHealthFlags.Add([bool]$assessment.healthy) | Out-Null
    Add-Checkpoint ([pscustomobject]@{
        name = 'supervised-' + $Name
        kind = 'supervised'
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        report_path = $runReportPath
        ui_healthy = $uiHealthy
        assessment = $assessment
        stop_evaluation = $stopEval
    })
    Write-RunbookTrace -LogPath $tracePath -Message ('supervised-complete ' + $Name + ' healthy=' + [string]$assessment.healthy)
    return $stopEval
}

function Invoke-BoundedRun {
    param([Parameter(Mandatory = $true)][string]$Name)

    $boundedDir = Join-Path $effectiveOutputDir $Name
    Ensure-Directory -PathValue $boundedDir
    Write-RunbookTrace -LogPath $tracePath -Message ('bounded-start ' + $Name)
    $rawResult = $null
    $attemptUsed = 'strict'
    $attempts = [math]::Max($MaxChildRetries, 1)
    for ($attempt = 1; $attempt -le $attempts; $attempt++) {
        $trainingArgs = @{
            ConfigPath = $effectiveConfigPath
            OutputDir = $boundedDir
        }
        if ($SkipProjectDiscovery) {
            $trainingArgs.SkipProjectDiscovery = $true
        }
        if ($attempt -gt 1) {
            $trainingArgs.SkipTests = $true
            $trainingArgs.SkipSmoke = $true
            $attemptUsed = 'relaxed_runtime_safe'
        }

        try {
            $rawResult = Invoke-ChildPowerShellJsonScript -ScriptPath $trainingScript -Arguments $trainingArgs -TimeoutSeconds ($BoundedTimeoutMinutes * 60)
            if ($null -ne $rawResult -and [bool]$rawResult.ok) {
                break
            }

            if ($attempt -lt $attempts) {
                Write-RunbookTrace -LogPath $tracePath -Message ('bounded-retry ' + $Name + ' attempt=' + [string]$attempt + ' mode=' + $attemptUsed)
            }
        }
        catch {
            if ($attempt -ge $attempts) {
                throw
            }
            Write-RunbookTrace -LogPath $tracePath -Message ('bounded-restart ' + $Name + ' attempt=' + [string]$attempt + ' mode=' + $attemptUsed + ' error=' + [string]$_.Exception.Message)
        }
    }

    $trainingReportPath = Join-Path $boundedDir 'training-report.json'
    $trainingReport = if (Test-Path -Path $trainingReportPath) { Get-Content -Path $trainingReportPath -Raw | ConvertFrom-Json } else { $null }
    $assessment = Get-BoundedTrainingAssessment -TrainingReport $trainingReport
    if ($assessment.runtime_safe_passed) {
        $runtimeSafeFailureStreak = 0
    }
    else {
        $runtimeSafeFailureStreak += 1
    }
    $uiHealthy = Test-UiProjectStatusHealthy -BaseUrl $UiBaseUrl
    $stopEval = Test-RunbookStopConditions -RuntimeSafeFailureStreak $runtimeSafeFailureStreak -RecoveryHealthy $assessment.recovery_ok -UiHealthy $uiHealthy -ReceiptHealthy $true -SupervisedEscalationReason '' -PriorSupervisedEscalationReason $priorSupervisedEscalationReason -PriorSupervisedEscalationCount $priorSupervisedEscalationCount
    $boundedHealthFlags.Add([bool]$assessment.healthy) | Out-Null
    Add-Checkpoint ([pscustomobject]@{
        name = $Name
        kind = 'bounded'
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        output_dir = $boundedDir
        execution_mode = $attemptUsed
        result = $rawResult
        report_path = $trainingReportPath
        ui_healthy = $uiHealthy
        assessment = $assessment
        stop_evaluation = $stopEval
    })
    Write-RunbookTrace -LogPath $tracePath -Message ('bounded-complete ' + $Name + ' healthy=' + [string]$assessment.healthy)
    return $stopEval
}

try {
    $stop = Invoke-SupervisedCheckpoint -Name 'baseline'
    if ($stop.triggered) {
        $report.stop_conditions = @($stop.reasons)
    }

    if (@($report.stop_conditions).Count -eq 0) {
        $windowOneTarget = $startUtc.AddHours([math]::Max($DurationHours / 3.0, 0.01))
        for ($index = 1; $index -le $WindowOneBoundedRuns; $index++) {
            $stop = Invoke-BoundedRun -Name ('bounded-window1-run' + $index)
            if ($stop.triggered) {
                $report.stop_conditions = @($stop.reasons)
                break
            }
            if ($index -lt $WindowOneBoundedRuns) {
                $target = $startUtc.AddTicks([int64](($windowOneTarget.Ticks - $startUtc.Ticks) * ($index / [double]$WindowOneBoundedRuns)))
                Wait-UntilUtc -TargetUtc $target -NoWait:$NoWait
            }
        }
    }

    if (@($report.stop_conditions).Count -eq 0) {
        Wait-UntilUtc -TargetUtc $midpointUtc -NoWait:$NoWait
        $stop = Invoke-SupervisedCheckpoint -Name 'midpoint'
        if ($stop.triggered) {
            $report.stop_conditions = @($stop.reasons)
        }
    }

    if (@($report.stop_conditions).Count -eq 0) {
        $windowTwoStart = (Get-Date).ToUniversalTime()
        $windowTwoTarget = $startUtc.AddHours([math]::Max(($DurationHours * 5.0) / 6.0, 0.015))
        for ($index = 1; $index -le $WindowTwoBoundedRuns; $index++) {
            $stop = Invoke-BoundedRun -Name ('bounded-window2-run' + $index)
            if ($stop.triggered) {
                $report.stop_conditions = @($stop.reasons)
                break
            }
            if ($index -lt $WindowTwoBoundedRuns) {
                $target = $windowTwoStart.AddTicks([int64](($windowTwoTarget.Ticks - $windowTwoStart.Ticks) * ($index / [double]$WindowTwoBoundedRuns)))
                Wait-UntilUtc -TargetUtc $target -NoWait:$NoWait
            }
        }
    }

    if (@($report.stop_conditions).Count -eq 0) {
        Wait-UntilUtc -TargetUtc $endUtc -NoWait:$NoWait
        $stop = Invoke-SupervisedCheckpoint -Name 'final'
        if ($stop.triggered) {
            $report.stop_conditions = @($stop.reasons)
        }
    }
}
catch {
    $report.stop_conditions = @('runbook_exception')
    Add-Checkpoint ([pscustomobject]@{
        name = 'exception'
        kind = 'exception'
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        message = [string]$_.Exception.Message
    })
    Write-RunbookTrace -LogPath $tracePath -Message ('runbook-exception ' + [string]$_.Exception.Message)
}

$allBoundedHealthy = (@($boundedHealthFlags).Count -gt 0) -and (-not (@($boundedHealthFlags) -contains $false))
$allSupervisedHealthy = (@($supervisedHealthFlags).Count -gt 0) -and (-not (@($supervisedHealthFlags) -contains $false))
$quietWindowRecommended = ($allBoundedHealthy -and $allSupervisedHealthy -and -not $NoWait)
$report.outcome = Get-RunbookOutcome -StopConditions @($report.stop_conditions) -AllBoundedHealthy:$allBoundedHealthy -AllSupervisedHealthy:$allSupervisedHealthy -QuietWindowRecommended:$quietWindowRecommended

$report.completed_at = (Get-Date).ToUniversalTime().ToString('o')
$report.summary = [pscustomobject]@{
    bounded_runs = @($boundedHealthFlags).Count
    supervised_runs = @($supervisedHealthFlags).Count
    all_bounded_healthy = $allBoundedHealthy
    all_supervised_healthy = $allSupervisedHealthy
    stop_condition_count = @($report.stop_conditions).Count
}

$report | ConvertTo-Json -Depth 30 | Set-Content -Path $jsonReportPath

$md = @()
$md += '# TOD 3-Hour Training Runbook Execution'
$md += ''
$md += 'Generated: ' + [string]$report.generated_at
$md += 'Completed: ' + [string]$report.completed_at
$md += ''
$md += '## Outcome'
$md += '- Outcome: ' + [string]$report.outcome
$md += '- Bounded runs: ' + [string]$report.summary.bounded_runs
$md += '- Supervised runs: ' + [string]$report.summary.supervised_runs
$md += '- All bounded healthy: ' + [string]$report.summary.all_bounded_healthy
$md += '- All supervised healthy: ' + [string]$report.summary.all_supervised_healthy
$md += ''
$md += '## Stop Conditions'
if (@($report.stop_conditions).Count -gt 0) {
    foreach ($reason in @($report.stop_conditions)) {
        $md += '- ' + [string]$reason
    }
}
else {
    $md += '- none'
}
$md += ''
$md += '## Checkpoints'
foreach ($checkpoint in @($report.checkpoints)) {
    $md += '- ' + [string]$checkpoint.name + ': ' + [string]$checkpoint.kind
}

$md -join [Environment]::NewLine | Set-Content -Path $mdReportPath

$result = [pscustomobject]@{
    ok = (@($report.stop_conditions).Count -eq 0)
    source = 'tod-training-runbook-6h-v1'
    output_dir = $effectiveOutputDir
    report_json = $jsonReportPath
    report_markdown = $mdReportPath
    outcome = $report.outcome
    stop_conditions = @($report.stop_conditions)
}

$result | ConvertTo-Json -Depth 12 | Write-Output

if ($FailOnStopCondition -and @($report.stop_conditions).Count -gt 0) {
    throw ('Training runbook hit stop conditions: ' + (@($report.stop_conditions) -join ', '))
}