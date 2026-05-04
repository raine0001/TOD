param(
    [string]$ConfigPath = 'tod/config/tod-config.json',
    [string]$CampaignRoot = 'tod/out/training/autonomous-campaign',
    [string]$DialogDir = 'shared_state/dialog',
    [int]$Top = 20,
    [int]$IntervalSeconds = 300,
    [int]$IdleThresholdMinutes = 0,
    [int]$MimWaitMinutes = 5,
    [int]$SimulationCooldownMinutes = 0,
    [int]$SolicitationCooldownMinutes = 60,
    [int]$LongIdleProfileThresholdMinutes = 30,
    [int]$RecoveryCooldownMinutes = 30,
    [bool]$IgnoreCampaignCompletion = $true,
    [switch]$StartupHealthCheck,
    [switch]$RunOnce
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $repoRoot
$todScript = Join-Path $PSScriptRoot 'TOD.ps1'
$lightweightStateBusScript = Join-Path $PSScriptRoot 'Get-TODLightweightStateBus.ps1'
$dialogScript = Join-Path $PSScriptRoot 'Invoke-TODMimDialog.ps1'
$supervisedScript = Join-Path $PSScriptRoot 'Invoke-TODSupervisedExecution.ps1'
$trainingLoopScript = Join-Path $PSScriptRoot 'Invoke-TODTrainingLoop.ps1'
$simulationBundleScript = Join-Path $PSScriptRoot 'Invoke-TODAutonomousSimulationBundle.ps1'
$repoEditRecoverSimulationScript = Join-Path $PSScriptRoot 'Invoke-TODRepoEditTestRecoverSimulationDaily.ps1'
$statusScript = Join-Path $PSScriptRoot 'Write-TODCompletionStatus.ps1'
$todStatePath = Join-Path $repoRoot 'tod/data/state.json'
$maxStateReadBytes = 256MB

function Resolve-RepoPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return [System.IO.Path]::GetFullPath($PathValue)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $PathValue))
}

function New-DirectoryIfMissing {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if (-not (Test-Path -Path $PathValue)) {
        New-Item -ItemType Directory -Path $PathValue -Force | Out-Null
    }
}

function Read-JsonFileIfExists {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if (-not (Test-Path -Path $PathValue)) {
        return $null
    }

    try {
        return (Get-Content -Path $PathValue -Raw | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Write-Utf8NoBomJson {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)]$Payload,
        [int]$Depth = 30
    )

    $directory = Split-Path -Parent $PathValue
    if (-not [string]::IsNullOrWhiteSpace($directory)) {
        New-DirectoryIfMissing -PathValue $directory
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $json = ($Payload | ConvertTo-Json -Depth $Depth) -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($PathValue, $json, $utf8NoBom)
}

function ConvertFrom-JsonLoose {
    param([AllowNull()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }

    $trimmed = $Text.Trim()
    try {
        return ($trimmed | ConvertFrom-Json)
    }
    catch {
    }

    $firstBrace = $trimmed.IndexOf('{')
    $firstBracket = $trimmed.IndexOf('[')
    $startIndex = -1
    if ($firstBrace -ge 0 -and $firstBracket -ge 0) {
        $startIndex = [Math]::Min($firstBrace, $firstBracket)
    }
    elseif ($firstBrace -ge 0) {
        $startIndex = $firstBrace
    }
    elseif ($firstBracket -ge 0) {
        $startIndex = $firstBracket
    }

    if ($startIndex -lt 0) {
        return $null
    }

    try {
        return ($trimmed.Substring($startIndex) | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Invoke-JsonPowerShellScript {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [hashtable]$Arguments = @{}
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

    $rawOutput = & $powershellExe @invocationArgs 2>&1 | Out-String
    $exitCode = if ($LASTEXITCODE -is [int]) { [int]$LASTEXITCODE } else { 0 }
    if ($exitCode -ne 0) {
        throw ("Script failed with exit code {0}: {1}`n{2}" -f $exitCode, $ScriptPath, $rawOutput.Trim())
    }

    return (ConvertFrom-JsonLoose -Text $rawOutput)
}

function Invoke-JsonScriptInline {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [hashtable]$Arguments = @{}
    )

    $rawOutput = & $ScriptPath @Arguments 2>&1 | Out-String
    if ($LASTEXITCODE -is [int] -and [int]$LASTEXITCODE -ne 0) {
        throw ("Script failed with exit code {0}: {1}`n{2}" -f [int]$LASTEXITCODE, $ScriptPath, $rawOutput.Trim())
    }

    return (ConvertFrom-JsonLoose -Text $rawOutput)
}

$resolvedConfigPath = Resolve-RepoPath -PathValue $ConfigPath
$resolvedCampaignRoot = Resolve-RepoPath -PathValue $CampaignRoot
$resolvedDialogDir = Resolve-RepoPath -PathValue $DialogDir
$daemonRoot = Join-Path $resolvedCampaignRoot 'daemon'
$daemonStatePath = Join-Path $daemonRoot 'autonomous-training-daemon-state.json'
$daemonLogPath = Join-Path $daemonRoot 'autonomous-training-daemon.log'
$lockPath = Join-Path $daemonRoot 'autonomous-training-daemon.lock'
$campaignStatePath = Join-Path $resolvedCampaignRoot 'campaign-state.json'
$statusOutputPath = Join-Path $repoRoot 'shared_state/tod_autonomy_status.latest.json'
New-DirectoryIfMissing -PathValue $daemonRoot

function Write-DaemonLog {
    param([Parameter(Mandatory = $true)][string]$Message)

    $line = '[{0}] {1}' -f ((Get-Date).ToUniversalTime().ToString('o')), $Message
    Add-Content -Path $daemonLogPath -Value $line
    Write-Host $line
}

function Get-DaemonState {
    $existing = Read-JsonFileIfExists -PathValue $daemonStatePath
    if ($null -ne $existing) {
        return $existing
    }

    return [pscustomobject]@{
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        source = 'tod-autonomous-training-daemon-v1'
        idle_started_at_utc = ''
        pending_mim_session_id = ''
        pending_mim_requested_at_utc = ''
        pending_mim_task_id = ''
        last_mim_response_at_utc = ''
        last_mim_solicitation_utc = ''
        last_training_profile = ''
        last_training_reason = ''
        last_simulation_run_utc = ''
        last_recovery_run_utc = ''
        last_startup_health_check_utc = ''
        last_status = 'never'
        updated_at_utc = ''
    }
}

function Save-DaemonState {
    param([Parameter(Mandatory = $true)]$State)

    $State.updated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    Write-Utf8NoBomJson -PathValue $daemonStatePath -Payload $State -Depth 30
}

function Publish-CompletionStatus {
    param(
        [Parameter(Mandatory = $true)]$State,
        [string]$TodDidThis,
        [string]$TodNextAction,
        [string]$TodState = 'executing',
        [string]$MimState = 'unknown',
        [string[]]$Blockers = @()
    )

    try {
        & $statusScript -DaemonStatePath $daemonStatePath -OutputPath $statusOutputPath -TodGotThis 'TOD autonomous daemon owns continuity, reconciliation, and fallback training.' -TodDidThis $TodDidThis -TodNextAction $TodNextAction -MimNextAction 'Provide direction when responsive; TOD continues without waiting.' -CurrentTodState $TodState -CurrentMimState $MimState -Confidence 'confirmed' -Blockers $Blockers | Out-Null
    }
    catch {
        Write-DaemonLog ('failed to publish completion status: ' + [string]$_.Exception.Message)
    }
}

function Acquire-Lock {
    if (Test-Path -Path $lockPath) {
        return $false
    }

    Set-Content -Path $lockPath -Value ((Get-Date).ToUniversalTime().ToString('o'))
    return $true
}

function Release-Lock {
    if (Test-Path -Path $lockPath) {
        Remove-Item -Path $lockPath -Force -ErrorAction SilentlyContinue
    }
}

function Get-ElapsedMinutes {
    param([string]$WhenUtc)

    if ([string]::IsNullOrWhiteSpace($WhenUtc)) {
        return [double]::PositiveInfinity
    }

    try {
        return (((Get-Date).ToUniversalTime()) - ([datetime]::Parse($WhenUtc).ToUniversalTime())).TotalMinutes
    }
    catch {
        return [double]::PositiveInfinity
    }
}

function Get-StateBus {
    $useLightweight = $false
    if (-not (Test-Path -Path $todStatePath)) {
        $useLightweight = $true
    }
    else {
        try {
            $item = Get-Item -Path $todStatePath -ErrorAction Stop
            $useLightweight = ([int64]$item.Length -gt [int64]$maxStateReadBytes)
        }
        catch {
            $useLightweight = $true
        }
    }

    try {
        if ($useLightweight) {
            return (& $lightweightStateBusScript -AsJson | ConvertFrom-Json)
        }

        return (& $todScript -Action 'get-state-bus' -ConfigPath $resolvedConfigPath -Top $Top | ConvertFrom-Json)
    }
    catch {
        try {
            Write-DaemonLog 'state-bus fallback active (listener telemetry)'
            return (& $lightweightStateBusScript -AsJson | ConvertFrom-Json)
        }
        catch {
            Write-DaemonLog ('state-bus query failed: ' + [string]$_.Exception.Message)
            return $null
        }
    }
}

function Test-IsIdle {
    param($Bus)

    if ($null -eq $Bus -or -not $Bus.PSObject.Properties['system_posture']) {
        return $false
    }

    $posture = $Bus.system_posture
    $activeExecutions = if ($posture.PSObject.Properties['active_execution_count']) { [int]$posture.active_execution_count } else { 1 }
    $pendingConfirmations = if ($posture.PSObject.Properties['pending_confirmations']) { [int]$posture.pending_confirmations } else { 1 }
    $agentState = if ($posture.PSObject.Properties['agent_state']) { [string]$posture.agent_state } else { 'busy' }

    return ($activeExecutions -eq 0 -and $pendingConfirmations -eq 0 -and -not [string]::Equals($agentState, 'busy', [System.StringComparison]::OrdinalIgnoreCase))
}

function Test-IsCriticalState {
    param($Bus)

    if ($null -eq $Bus -or -not $Bus.PSObject.Properties['system_posture']) {
        return $false
    }

    $posture = $Bus.system_posture
    $alertState = if ($posture.PSObject.Properties['current_alert_state']) { [string]$posture.current_alert_state } else { '' }
    $executorHealth = if ($posture.PSObject.Properties['current_executor_health']) { [string]$posture.current_executor_health } else { '' }
    return ([string]::Equals($alertState, 'critical', [System.StringComparison]::OrdinalIgnoreCase) -or [string]::Equals($executorHealth, 'degraded', [System.StringComparison]::OrdinalIgnoreCase))
}

function Get-CampaignCompleted {
    $campaignState = Read-JsonFileIfExists -PathValue $campaignStatePath
    if ($null -eq $campaignState) {
        return $false
    }

    $completedDays = if ($campaignState.PSObject.Properties['completed_days']) { [int]$campaignState.completed_days } else { 0 }
    $totalDays = if ($campaignState.PSObject.Properties['total_days']) { [int]$campaignState.total_days } else { 0 }
    $status = if ($campaignState.PSObject.Properties['status']) { [string]$campaignState.status } else { '' }
    return ([string]::Equals($status, 'completed', [System.StringComparison]::OrdinalIgnoreCase) -or ($totalDays -gt 0 -and $completedDays -ge $totalDays))
}

function Test-MimReplyActionable {
    param([AllowNull()]$SessionDetail)

    if ($null -eq $SessionDetail -or -not $SessionDetail.PSObject.Properties['messages']) {
        return $false
    }

    $lastMessage = @($SessionDetail.messages | Select-Object -Last 1)
    if (@($lastMessage).Count -eq 0) {
        return $false
    }

    $message = $lastMessage[0]
    if (-not $message.PSObject.Properties['from'] -or -not [string]::Equals([string]$message.from, 'MIM', [System.StringComparison]::OrdinalIgnoreCase)) {
        return $false
    }

    if ($message.PSObject.Properties['task_id'] -and -not [string]::IsNullOrWhiteSpace([string]$message.task_id)) {
        return $true
    }

    if ($message.PSObject.Properties['payload'] -and $null -ne $message.payload) {
        if ($message.payload.PSObject.Properties['task_id'] -and -not [string]::IsNullOrWhiteSpace([string]$message.payload.task_id)) {
            return $true
        }
        if ($message.payload.PSObject.Properties['objective_id'] -and -not [string]::IsNullOrWhiteSpace([string]$message.payload.objective_id)) {
            return $true
        }
        if ($message.payload.PSObject.Properties['action'] -and -not [string]::IsNullOrWhiteSpace([string]$message.payload.action)) {
            return $true
        }
    }

    return $false
}

function Invoke-StartupHealthPass {
    param([Parameter(Mandatory = $true)]$State)

    $startupDir = Join-Path $daemonRoot 'startup-health'
    New-DirectoryIfMissing -PathValue $startupDir

    try {
        $health = Invoke-JsonPowerShellScript -ScriptPath $supervisedScript -Arguments @{
            ImplementationConfigPath = $resolvedConfigPath
            ImplementationOutputDir = $startupDir
            RefreshMimContextFromSsh = $true
            SkipTests = $true
            RunReportPath = (Join-Path $startupDir 'tod_supervised_execution.latest.json')
        }
        $State.last_startup_health_check_utc = (Get-Date).ToUniversalTime().ToString('o')

        if ($health -and $health.PSObject.Properties['needs_escalation'] -and [bool]$health.needs_escalation) {
            Write-DaemonLog ('startup health escalated; applying runtime-safe correction: ' + [string]$health.escalation_reason)
            $null = Invoke-JsonPowerShellScript -ScriptPath $trainingLoopScript -Arguments @{
                ConfigPath = $resolvedConfigPath
                OutputDir = (Join-Path $startupDir 'runtime-safe-correction')
                SkipTests = $true
                SkipSmoke = $true
            }
            $retry = Invoke-JsonPowerShellScript -ScriptPath $supervisedScript -Arguments @{
                ImplementationConfigPath = $resolvedConfigPath
                ImplementationOutputDir = (Join-Path $startupDir 'post-correction')
                RefreshMimContextFromSsh = $true
                SkipTests = $true
                RunReportPath = (Join-Path $startupDir 'post-correction/tod_supervised_execution.latest.json')
            }
            if ($retry -and $retry.PSObject.Properties['needs_escalation'] -and [bool]$retry.needs_escalation) {
                Write-DaemonLog ('startup health still degraded after correction: ' + [string]$retry.escalation_reason)
            }
        }
        else {
            Write-DaemonLog 'startup health check completed without escalation'
        }
    }
    catch {
        Write-DaemonLog ('startup health check failed: ' + [string]$_.Exception.Message)
    }
}

function Invoke-CriticalRecovery {
    param([Parameter(Mandatory = $true)]$State)

    $recoveryDir = Join-Path $daemonRoot ('critical-recovery-' + (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ'))
    New-DirectoryIfMissing -PathValue $recoveryDir
    try {
        Write-DaemonLog 'critical state detected; running runtime-safe correction cycle'
        $null = Invoke-JsonPowerShellScript -ScriptPath $trainingLoopScript -Arguments @{
            ConfigPath = $resolvedConfigPath
            OutputDir = $recoveryDir
            SkipTests = $true
            SkipSmoke = $true
        }
        $State.last_recovery_run_utc = (Get-Date).ToUniversalTime().ToString('o')
        $State.last_status = 'critical_recovery_ok'
    }
    catch {
        $State.last_recovery_run_utc = (Get-Date).ToUniversalTime().ToString('o')
        $State.last_status = 'critical_recovery_error'
        Write-DaemonLog ('critical recovery failed: ' + [string]$_.Exception.Message)
    }
}

function Start-MimSolicitation {
    param([Parameter(Mandatory = $true)]$State)

    $sessionId = 'autonomous-idle-' + (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ') + '-' + ([guid]::NewGuid().ToString('N').Substring(0, 8))
    $taskId = 'autonomous-idle-' + (Get-Date).ToUniversalTime().ToString('yyyyMMddHHmmss')
    $summary = 'TOD crossed its idle threshold. Publish the next objective/task now; TOD is already continuing under training fallback and will incorporate any new MIM direction when it arrives.'
    $payload = [pscustomobject]@{
        request_type = 'autonomous_idle_next_task'
        idle_threshold_minutes = $IdleThresholdMinutes
        auto_approve_on_timeout = $true
        simulation_fallback = $true
        requested_at = (Get-Date).ToUniversalTime().ToString('o')
    }

    try {
        $result = Invoke-JsonScriptInline -ScriptPath $dialogScript -Arguments @{
            Action = 'send'
            DialogDir = $resolvedDialogDir
            SessionId = $sessionId
            Actor = 'TOD'
            PeerActor = 'MIM'
            MessageType = 'status_request'
            Intent = 'autonomous_next_objective_request'
            TaskId = $taskId
            Summary = $summary
            PayloadJson = ($payload | ConvertTo-Json -Depth 12 -Compress)
            RequiresReply = $true
            PublishRemote = $true
            EmitJson = $true
        }

        $State.pending_mim_session_id = $sessionId
        $State.pending_mim_requested_at_utc = (Get-Date).ToUniversalTime().ToString('o')
        $State.pending_mim_task_id = $taskId
        $State.last_mim_solicitation_utc = $State.pending_mim_requested_at_utc
        $State.last_status = 'awaiting_mim_reply'
        Write-DaemonLog ('idle threshold reached; requested next task from MIM via session ' + $sessionId)
        Publish-CompletionStatus -State $State -TodDidThis 'opened_mim_direction_request' -TodNextAction 'Continue under fallback training while the MIM dialog stays open.' -TodState 'executing' -MimState 'waiting'
        return $result
    }
    catch {
        Write-DaemonLog ('failed to request next task from MIM: ' + [string]$_.Exception.Message)
        Publish-CompletionStatus -State $State -TodDidThis 'mim_direction_request_failed' -TodNextAction 'Continue under fallback training because MIM solicitation did not complete.' -TodState 'executing' -MimState 'unknown' -Blockers @([string]$_.Exception.Message)
        return $null
    }
}

function Get-IdleTrainingProfile {
    param(
        [double]$IdleMinutes = 0,
        [string]$Reason = 'no_mim_reply'
    )

    if ($IdleMinutes -ge $LongIdleProfileThresholdMinutes) {
        return [pscustomobject]@{
            id = 'repo_edit_test_recover'
            label = 'Repo edit / test / recover pack'
            reason = $Reason
            kind = 'long_idle'
        }
    }

    return [pscustomobject]@{
        id = 'runtime_safe_subset'
        label = 'Runtime-safe validation subset'
        reason = $Reason
        kind = 'short_idle'
    }
}

function Invoke-SimulationFallback {
    param(
        [Parameter(Mandatory = $true)]$State,
        [string]$Reason = 'no_mim_reply',
        [double]$IdleMinutes = 0
    )

    $simulationDir = Join-Path $daemonRoot ('idle-simulation-' + (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ'))
    New-DirectoryIfMissing -PathValue $simulationDir
    $profile = Get-IdleTrainingProfile -IdleMinutes $IdleMinutes -Reason $Reason

    try {
        Write-DaemonLog ('starting idle training fallback; profile=' + [string]$profile.id + ' idle=' + ('{0:n1}' -f $IdleMinutes) + 'm reason=' + $Reason)
        if ([string]$profile.id -eq 'repo_edit_test_recover') {
            $null = Invoke-JsonPowerShellScript -ScriptPath $repoEditRecoverSimulationScript -Arguments @{
                OutputRoot = $simulationDir
                EmitJson = $true
            }
        }
        else {
            $null = Invoke-JsonPowerShellScript -ScriptPath $trainingLoopScript -Arguments @{
                ConfigPath = $resolvedConfigPath
                OutputDir = $simulationDir
                SkipTests = $true
                SkipSmoke = $true
            }
        }
        $State.last_simulation_run_utc = (Get-Date).ToUniversalTime().ToString('o')
        $State.last_training_profile = [string]$profile.id
        $State.last_training_reason = $Reason
        $State.last_status = 'simulation_fallback_ok'
        Publish-CompletionStatus -State $State -TodDidThis ('idle_training_profile_started:' + [string]$profile.id + ':' + $Reason) -TodNextAction ('Keep training under the ' + [string]$profile.label + ' profile until higher-priority MIM work becomes actionable.') -TodState 'training' -MimState 'waiting'
    }
    catch {
        $State.last_simulation_run_utc = (Get-Date).ToUniversalTime().ToString('o')
        $State.last_training_profile = [string]$profile.id
        $State.last_training_reason = $Reason
        $State.last_status = 'simulation_fallback_error'
        Write-DaemonLog ('idle training fallback failed; profile=' + [string]$profile.id + ' error=' + [string]$_.Exception.Message)
        Publish-CompletionStatus -State $State -TodDidThis ('idle_training_profile_failed:' + [string]$profile.id + ':' + $Reason) -TodNextAction 'Run another reconciliation cycle and retry fallback training.' -TodState 'reconciling' -MimState 'unknown' -Blockers @([string]$_.Exception.Message)
    }
}

function Resolve-PendingMimRequest {
    param([Parameter(Mandatory = $true)]$State)

    if ([string]::IsNullOrWhiteSpace([string]$State.pending_mim_session_id)) {
        return
    }

    $sessionId = [string]$State.pending_mim_session_id
    try {
        $status = Invoke-JsonScriptInline -ScriptPath $dialogScript -Arguments @{
            Action = 'get-session-status'
            DialogDir = $resolvedDialogDir
            SessionId = $sessionId
            RefreshFromRemote = $true
            EmitJson = $true
        }

        $sessionState = if ($status -and $status.PSObject.Properties['session_state']) { $status.session_state } else { $null }
        $requestAgeMinutes = Get-ElapsedMinutes -WhenUtc ([string]$State.pending_mim_requested_at_utc)
        $timedOut = (($null -ne $sessionState -and $sessionState.PSObject.Properties['timed_out'] -and [bool]$sessionState.timed_out) -or ($requestAgeMinutes -ge $MimWaitMinutes))
        $resolved = ($null -ne $sessionState -and @('resolved', 'closed') -contains [string]$sessionState.status)

        if ($resolved) {
            $detail = Invoke-JsonScriptInline -ScriptPath $dialogScript -Arguments @{
                Action = 'read-session'
                DialogDir = $resolvedDialogDir
                SessionId = $sessionId
                RefreshFromRemote = $true
                EmitJson = $true
            }
            $actionable = Test-MimReplyActionable -SessionDetail $detail
            $State.last_mim_response_at_utc = (Get-Date).ToUniversalTime().ToString('o')
            $State.pending_mim_session_id = ''
            $State.pending_mim_requested_at_utc = ''
            $State.pending_mim_task_id = ''

            if ($actionable) {
                $State.last_status = 'mim_replied_actionable'
                Write-DaemonLog ('MIM replied with an actionable next-task response in session ' + $sessionId)
                Publish-CompletionStatus -State $State -TodDidThis 'mim_replied_actionable' -TodNextAction 'Execute the new MIM-directed work without waiting for a human relay.' -TodState 'executing' -MimState 'executing'
            }
            else {
                Write-DaemonLog ('MIM replied without an actionable task; switching to simulation fallback')
                Invoke-SimulationFallback -State $State -Reason 'mim_replied_without_task' -IdleMinutes $MimWaitMinutes
            }
            return
        }

        if ($timedOut) {
            try {
                $closePayload = [pscustomobject]@{
                    auto_approved = $true
                    fallback = 'simulation_training'
                    timeout_minutes = $MimWaitMinutes
                }
                $null = Invoke-JsonScriptInline -ScriptPath $dialogScript -Arguments @{
                    Action = 'close-session'
                    DialogDir = $resolvedDialogDir
                    SessionId = $sessionId
                    Actor = 'TOD'
                    PeerActor = 'MIM'
                    TaskId = [string]$State.pending_mim_task_id
                    Intent = 'auto_approved_simulation_fallback'
                    Summary = 'No MIM task arrived within the approved wait window, so TOD auto-approved simulation training and resumed autonomous work.'
                    PayloadJson = ($closePayload | ConvertTo-Json -Depth 12 -Compress)
                    PublishRemote = $true
                    EmitJson = $true
                }
            }
            catch {
                Write-DaemonLog ('failed to close timed-out MIM session cleanly: ' + [string]$_.Exception.Message)
            }

            $State.pending_mim_session_id = ''
            $State.pending_mim_requested_at_utc = ''
            $State.pending_mim_task_id = ''
            Invoke-SimulationFallback -State $State -Reason 'mim_timeout' -IdleMinutes $requestAgeMinutes
        }
    }
    catch {
        Write-DaemonLog ('failed to resolve pending MIM session ' + $sessionId + ': ' + [string]$_.Exception.Message)
    }
}

Write-DaemonLog ('autonomous training daemon started (interval=' + [string]$IntervalSeconds + 's idle_threshold=' + [string]$IdleThresholdMinutes + 'm mim_wait=' + [string]$MimWaitMinutes + 'm simulation_cooldown=' + [string]$SimulationCooldownMinutes + 'm solicitation_cooldown=' + [string]$SolicitationCooldownMinutes + 'm long_idle_profile_threshold=' + [string]$LongIdleProfileThresholdMinutes + 'm)')
Publish-CompletionStatus -State (Get-DaemonState) -TodDidThis 'autonomous_daemon_started' -TodNextAction 'Watch for idle, drift, and missed training windows.' -TodState 'executing' -MimState 'unknown'

try {
    $state = Get-DaemonState
    if ($StartupHealthCheck) {
        Invoke-StartupHealthPass -State $state
        Save-DaemonState -State $state
    }

    while ($true) {
        if ((-not $IgnoreCampaignCompletion) -and (Get-CampaignCompleted)) {
            Write-DaemonLog 'campaign completed; autonomous daemon exiting because continuous idle mode is disabled'
            break
        }

        if (-not (Acquire-Lock)) {
            Write-DaemonLog 'skipping cycle because another daemon instance holds the lock'
        }
        else {
            try {
                $state = Get-DaemonState
                $bus = Get-StateBus
                $isIdle = Test-IsIdle -Bus $bus

                if ($isIdle) {
                    if ([string]::IsNullOrWhiteSpace([string]$state.idle_started_at_utc)) {
                        $state.idle_started_at_utc = (Get-Date).ToUniversalTime().ToString('o')
                        Write-DaemonLog 'idle window opened'
                    }
                }
                else {
                    if (-not [string]::IsNullOrWhiteSpace([string]$state.idle_started_at_utc)) {
                        Write-DaemonLog 'idle window closed'
                    }
                    $state.idle_started_at_utc = ''
                    $state.pending_mim_session_id = ''
                    $state.pending_mim_requested_at_utc = ''
                    $state.pending_mim_task_id = ''
                }

                if (Test-IsCriticalState -Bus $bus) {
                    $minutesSinceRecovery = Get-ElapsedMinutes -WhenUtc ([string]$state.last_recovery_run_utc)
                    if ($minutesSinceRecovery -ge $RecoveryCooldownMinutes) {
                        Invoke-CriticalRecovery -State $state
                        Publish-CompletionStatus -State $state -TodDidThis 'critical_recovery_started' -TodNextAction 'Complete runtime-safe correction and return to active execution.' -TodState 'reconciling' -MimState 'unknown'
                    }
                }

                if (-not [string]::IsNullOrWhiteSpace([string]$state.pending_mim_session_id)) {
                    Resolve-PendingMimRequest -State $state
                }
                elseif ($isIdle) {
                    $idleMinutes = Get-ElapsedMinutes -WhenUtc ([string]$state.idle_started_at_utc)
                    $minutesSinceSimulation = Get-ElapsedMinutes -WhenUtc ([string]$state.last_simulation_run_utc)
                    $minutesSinceSolicitation = Get-ElapsedMinutes -WhenUtc ([string]$state.last_mim_solicitation_utc)
                    if ($idleMinutes -ge $IdleThresholdMinutes -and $minutesSinceSimulation -ge $SimulationCooldownMinutes) {
                        if ($minutesSinceSolicitation -ge $SolicitationCooldownMinutes) {
                            $null = Start-MimSolicitation -State $state
                        }
                        else {
                            Write-DaemonLog ('idle training continues without new MIM solicitation (idle=' + ('{0:n1}' -f $idleMinutes) + 'm, solicitation_cooldown=' + ('{0:n1}' -f $minutesSinceSolicitation) + 'm)')
                        }
                        Invoke-SimulationFallback -State $state -Reason 'idle_threshold_no_stall' -IdleMinutes $idleMinutes
                    }
                    else {
                        Write-DaemonLog ('idle but below solicitation threshold/cooldown (idle=' + ('{0:n1}' -f $idleMinutes) + 'm, simulation_cooldown=' + ('{0:n1}' -f $minutesSinceSimulation) + 'm)')
                        Publish-CompletionStatus -State $state -TodDidThis 'idle_detected_waiting_for_next_training_window' -TodNextAction 'Resume training on the next idle cycle unless a higher-priority task appears.' -TodState 'waiting' -MimState 'unknown'
                    }
                }
                else {
                    Write-DaemonLog 'runtime active; autonomous idle solicitation skipped this cycle'
                    Publish-CompletionStatus -State $state -TodDidThis 'runtime_active' -TodNextAction 'Keep executing the current objective and training fallback rules in reserve.' -TodState 'executing' -MimState 'unknown'
                }

                Save-DaemonState -State $state
            }
            finally {
                Release-Lock
            }
        }

        if ($RunOnce) {
            break
        }

        Start-Sleep -Seconds $IntervalSeconds
    }
}
finally {
    Release-Lock
    Write-DaemonLog 'autonomous training daemon stopped'
}