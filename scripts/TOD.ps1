param(
    [Parameter(Mandatory = $true)]
    [ValidateSet(
        "init",
        "ping-mim",
        "safe_home",
        "scan_pose",
        "capture_frame",
        "compare-manifest",
        "sync-mim",
        "new-objective",
        "list-objectives",
        "add-task",
        "list-tasks",
        "package-task",
        "invoke-engine",
        "codex_handoff",
        "execute-chat-task",
        "publish-activity-event",
        "run-task",
        "select-next-task-loop",
        "run-bridge-request",
        "run-task-report",
        "show-engine-performance",
        "show-routing-decisions",
        "show-routing-feedback",
        "show-failure-taxonomy",
        "show-reliability-dashboard",
        "get-reliability",
        "get-execution-readiness",
        "get-capabilities",
        "get-research",
        "get-resourcing",
        "start-training-runbook",
        "engineer-run",
        "engineer-scorecard",
        "get-engineering-loop-summary",
        "get-engineering-signal",
        "get-engineering-loop-history",
        "engineer-cycle",
        "review-engineering-cycle",
        "sandbox-list",
        "sandbox-plan",
        "sandbox-apply-plan",
        "sandbox-write",
        "repair-state",
        "rewrite-state-history",
        "get-state-bus",
        "get-intake-arbitration",
        "get-version",
        "add-result",
        "persist-task-terminal-state",
        "review-task",
        "show-journal"
    )]
    [string]$Action,

    [string]$ObjectiveId,
    [string]$TaskId,
    [string]$RequestId,
    [string]$CorrelationId,
    [string]$Title,
    [string]$Description,
    [ValidateSet("low", "medium", "high", "critical")]
    [string]$Priority = "medium",
    [string]$Constraints,
    [string]$SuccessCriteria,
    [string]$Type = "implementation",
    [string]$TaskCategory,
    [string]$Scope,
    [string]$Dependencies,
    [string]$AcceptanceCriteria,
    [string]$AssignedExecutor = "codex",
    [string]$Summary,
    [string]$FilesChanged,
    [string]$TestsRun,
    [string]$TestResults,
    [string]$Failures,
    [string]$Recommendations,
    [ValidateSet("pass", "revise", "escalate")]
    [string]$Decision,
    [string]$Rationale,
    [string]$UnresolvedIssues,
    [switch]$ScopeDrift,
    [switch]$AllowContractDrift,
    [switch]$ForceConfiguredEngine,
    [int]$Top = 25,
    [string]$ConfigPath,
    [string]$ManifestPath,
    [string]$PackagePath,
    [string]$ExecutionId,
    [string]$StatePath,
    [string]$SandboxPath,
    [string]$SandboxPlanPath,
    [string]$Content,
    [switch]$Append
    ,[switch]$ApplyPlan
    ,[string]$Engine
    ,[string]$Category
    ,[ValidateSet("run_history", "scorecard_history", "cycle_records", "review_actions")][string]$HistoryKind = "run_history"
    ,[int]$Page = 1
    ,[int]$PageSize = 25
    ,[int]$Cycles = 1
    ,[bool]$DangerousApproved = $false
    ,[string]$CycleId
    ,[ValidateSet("approve_apply", "reject_apply", "continue_cycle", "freeze_objective", "mark_complete")][string]$CycleReviewAction
    ,[switch]$SkipNextTaskSelectionLoop
    ,[switch]$SkipPostCompletionTail
    ,[string]$SelectionReason
    ,[string]$TargetFile
    ,[ValidateSet('sync', 'async')][string]$ExecutionMode = 'sync'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$statePath = if ([string]::IsNullOrWhiteSpace($StatePath)) {
    Join-Path $repoRoot "tod/data/state.json"
}
else {
    if ([System.IO.Path]::IsPathRooted($StatePath)) {
        $StatePath
    }
    else {
        Join-Path $repoRoot $StatePath
    }
}
$configPath = if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    Join-Path $repoRoot "tod/config/tod-config.json"
}
else {
    $ConfigPath
}
$templatePath = Join-Path $repoRoot "tod/templates/codex-task-prompt.md"
$promptOutDir = if (-not [string]::IsNullOrWhiteSpace($env:TOD_PROMPT_OUT_DIR)) {
    if ([System.IO.Path]::IsPathRooted($env:TOD_PROMPT_OUT_DIR)) {
        [string]$env:TOD_PROMPT_OUT_DIR
    }
    else {
        Join-Path $repoRoot ([string]$env:TOD_PROMPT_OUT_DIR)
    }
}
else {
    Join-Path $repoRoot "tod/out/prompts"
}
$mimClientPath = Join-Path $repoRoot "client/mim_api_client.ps1"
$syncPolicyPath = Join-Path $repoRoot "tod/config/sync-policy.json"
$todEngineerPath = Join-Path $PSScriptRoot "TOD-Engineer.ps1"
$lightweightStateBusScript = Join-Path $PSScriptRoot "Get-TODLightweightStateBus.ps1"
$repoIndexPath = Join-Path $repoRoot "tod/data/repo-index.json"
$stateRepoIndexPath = Join-Path $repoRoot "tod/state/repo_index.json"
$executionReadinessSignalPath = Join-Path $repoRoot "shared_state/tod_operator_chat_sweep_artifact_smoke.latest.json"
$engineeringMemoryPath = Join-Path $repoRoot "tod/data/engineering-memory.json"
$stateEngineeringMemoryPath = Join-Path $repoRoot "tod/state/engineering_memory.json"
$engineeringKnowledgeDir = Join-Path $repoRoot "tod/knowledge/engineering-memory"
$rewriteStateHistoryScript = Join-Path $PSScriptRoot "Rewrite-TODOperationalState.ps1"
$projectAccessPolicyScript = Join-Path $PSScriptRoot "Test-TODProjectAccessPolicy.ps1"
$projectPriorityPath = Join-Path $repoRoot "tod/config/project-priority.json"
$bridgeRequestPacketPath = if (-not [string]::IsNullOrWhiteSpace($env:TOD_BRIDGE_REQUEST_PACKET_PATH)) {
    if ([System.IO.Path]::IsPathRooted($env:TOD_BRIDGE_REQUEST_PACKET_PATH)) {
        [string]$env:TOD_BRIDGE_REQUEST_PACKET_PATH
    }
    else {
        Join-Path $repoRoot ([string]$env:TOD_BRIDGE_REQUEST_PACKET_PATH)
    }
}
else {
    Join-Path $repoRoot "tod/out/context-sync/listener/MIM_TOD_TASK_REQUEST.latest.json"
}
$todIntakeQueueFileName = 'TOD_INTAKE_QUEUE.latest.json'
$todActiveExecutionLaneFileName = 'TOD_ACTIVE_EXECUTION_LANE.latest.json'
$todIntakeArbitrationFileName = 'TOD_INTAKE_ARBITRATION.latest.json'
$defaultMaxStateReadBytes = 256MB

if (Test-Path -Path $mimClientPath) {
    . $mimClientPath
}

function Get-UtcNow {
    return (Get-Date).ToUniversalTime().ToString("o")
}

function Get-DotEnvValue {
    param(
        [string]$Path,
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($Name)) {
        return ""
    }

    if (-not (Test-Path -Path $Path)) {
        return ""
    }

    $line = Get-Content -Path $Path | Where-Object {
        $_ -match ("^\s*{0}\s*=" -f [regex]::Escape($Name))
    } | Select-Object -First 1

    if ([string]::IsNullOrWhiteSpace([string]$line)) {
        return ""
    }

    return ([string]($line -replace ("^\s*{0}\s*=\s*" -f [regex]::Escape($Name)), "")).Trim()
}

function Resolve-MimSshSettingValue {
    param(
        [string]$ExplicitValue,
        [string]$EnvVarName,
        [string]$DotEnvPathValue
    )

    if (-not [string]::IsNullOrWhiteSpace($ExplicitValue)) {
        return [string]$ExplicitValue
    }

    if (-not [string]::IsNullOrWhiteSpace($EnvVarName)) {
        $fromEnv = [string][Environment]::GetEnvironmentVariable($EnvVarName)
        if (-not [string]::IsNullOrWhiteSpace($fromEnv)) {
            return $fromEnv
        }

        $fromDotEnv = Get-DotEnvValue -Path $DotEnvPathValue -Name $EnvVarName
        if (-not [string]::IsNullOrWhiteSpace($fromDotEnv)) {
            return $fromDotEnv
        }
    }

    return ""
}

function Resolve-SshHostAlias {
    param([string]$RemoteHost)

    if ([string]::IsNullOrWhiteSpace($RemoteHost)) {
        return ""
    }

    if ($RemoteHost -match '^\d{1,3}(?:\.\d{1,3}){3}$' -or $RemoteHost -match '\.') {
        return $RemoteHost
    }

    $sshConfigPath = Join-Path $HOME ".ssh/config"
    if (-not (Test-Path -Path $sshConfigPath)) {
        return $RemoteHost
    }

    $matchedHost = $false
    foreach ($rawLine in (Get-Content -Path $sshConfigPath)) {
        $line = [string]$rawLine
        $trim = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trim) -or $trim.StartsWith('#')) {
            continue
        }

        if ($trim -match '^(?i)Host\s+(.+)$') {
            $matchedHost = $false
            foreach ($token in @($matches[1] -split '\s+')) {
                if ([string]::Equals([string]$token, $RemoteHost, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $matchedHost = $true
                    break
                }
            }
            continue
        }

        if ($matchedHost -and $trim -match '^(?i)HostName\s+(.+)$') {
            return [string]$matches[1]
        }
    }

    return $RemoteHost
}

function New-MimArmSshSession {
    param(
        [Parameter(Mandatory = $true)][string]$HostAlias,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][int]$Port,
        [Parameter(Mandatory = $true)][string]$Password
    )

    if (-not (Get-Module -ListAvailable -Name Posh-SSH)) {
        throw "Posh-SSH is not installed. Install-Module -Name Posh-SSH -Scope CurrentUser"
    }

    Import-Module Posh-SSH -ErrorAction Stop | Out-Null

    $resolvedHost = Resolve-SshHostAlias -RemoteHost $HostAlias
    $securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential ($UserName, $securePassword)
    $session = New-SSHSession -ComputerName $resolvedHost -Port $Port -Credential $credential -AcceptKey -ConnectionTimeout 15000

    return [pscustomobject]@{
        host_alias = $HostAlias
        resolved_host = $resolvedHost
        user_name = $UserName
        port = $Port
        ssh = $session
    }
}

function Close-MimArmSshSession {
    param($SessionInfo)

    if ($null -eq $SessionInfo) {
        return
    }

    try {
        if ($SessionInfo.ssh) {
            Remove-SSHSession -SessionId ([int]$SessionInfo.ssh.SessionId) | Out-Null
        }
    }
    catch {
    }
}

function Get-CommandOutputText {
    param($Result)

    if ($null -eq $Result) {
        return ""
    }

    if ($Result.PSObject.Properties['Output']) {
        return [string]((@($Result.Output) -join "`n")).Trim()
    }

    return ""
}

function Get-CommandErrorText {
    param($Result)

    if ($null -eq $Result) {
        return ""
    }

    if ($Result.PSObject.Properties['Error']) {
        return [string]((@($Result.Error) -join "`n")).Trim()
    }

    return ""
}

function ConvertFrom-JsonIfPossible {
    param([AllowNull()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }

    try {
        return ($Text | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Invoke-MimArmSafeHome {
    param(
        [Parameter(Mandatory = $true)][string]$DotEnvPathValue,
        [int]$TimeoutSeconds = 30
    )

    $resolvedHost = Resolve-MimSshSettingValue -ExplicitValue "" -EnvVarName "MIM_ARM_SSH_HOST" -DotEnvPathValue $DotEnvPathValue
    if ([string]::IsNullOrWhiteSpace($resolvedHost)) {
        $resolvedHost = Resolve-MimSshSettingValue -ExplicitValue "" -EnvVarName "MIM_SSH_HOST" -DotEnvPathValue $DotEnvPathValue
    }
    if ([string]::IsNullOrWhiteSpace($resolvedHost)) {
        throw "safe_home requires MIM_ARM_SSH_HOST or MIM_SSH_HOST in .env"
    }

    $resolvedUser = Resolve-MimSshSettingValue -ExplicitValue "" -EnvVarName "MIM_ARM_SSH_USER" -DotEnvPathValue $DotEnvPathValue
    if ([string]::IsNullOrWhiteSpace($resolvedUser)) {
        $resolvedUser = Resolve-MimSshSettingValue -ExplicitValue "" -EnvVarName "MIM_SSH_USER" -DotEnvPathValue $DotEnvPathValue
    }
    if ([string]::IsNullOrWhiteSpace($resolvedUser)) {
        $resolvedUser = "testpilot"
    }

    $resolvedPortText = Resolve-MimSshSettingValue -ExplicitValue "" -EnvVarName "MIM_ARM_SSH_PORT" -DotEnvPathValue $DotEnvPathValue
    if ([string]::IsNullOrWhiteSpace($resolvedPortText)) {
        $resolvedPortText = Resolve-MimSshSettingValue -ExplicitValue "" -EnvVarName "MIM_SSH_PORT" -DotEnvPathValue $DotEnvPathValue
    }
    $resolvedPort = 22
    if (-not [string]::IsNullOrWhiteSpace($resolvedPortText)) {
        $parsedPort = 0
        if ([int]::TryParse($resolvedPortText, [ref]$parsedPort) -and $parsedPort -gt 0) {
            $resolvedPort = $parsedPort
        }
    }

    $resolvedPassword = Resolve-MimSshSettingValue -ExplicitValue "" -EnvVarName "MIM_ARM_SSH_HOST_PASS" -DotEnvPathValue $DotEnvPathValue
    if ([string]::IsNullOrWhiteSpace($resolvedPassword)) {
        $resolvedPassword = Resolve-MimSshSettingValue -ExplicitValue "" -EnvVarName "MIM_SSH_PASSWORD" -DotEnvPathValue $DotEnvPathValue
    }
    if ([string]::IsNullOrWhiteSpace($resolvedPassword)) {
        throw "safe_home requires MIM_ARM_SSH_HOST_PASS or MIM_SSH_PASSWORD in .env"
    }

    $sessionInfo = $null
    try {
        $sessionInfo = New-MimArmSshSession -HostAlias $resolvedHost -UserName $resolvedUser -Port $resolvedPort -Password $resolvedPassword

        $armStateCommand = "curl -fsS http://127.0.0.1:5000/arm_state"
        $goSafeCommand = "curl -fsS -X POST http://127.0.0.1:5000/go_safe"

        $preflightResult = Invoke-SSHCommand -SessionId ([int]$sessionInfo.ssh.SessionId) -Command $armStateCommand -TimeOut $TimeoutSeconds
        if ($preflightResult.ExitStatus -ne 0) {
            $preflightError = Get-CommandErrorText -Result $preflightResult
            if ([string]::IsNullOrWhiteSpace($preflightError)) {
                $preflightError = Get-CommandOutputText -Result $preflightResult
            }
            throw ("safe_home preflight failed: {0}" -f $preflightError)
        }

        $preflightRaw = Get-CommandOutputText -Result $preflightResult
        $preflightState = ConvertFrom-JsonIfPossible -Text $preflightRaw
        $serialReady = $false
        if ($null -ne $preflightState) {
            if ($preflightState.PSObject.Properties['serial_ready']) {
                $serialReady = [bool]$preflightState.serial_ready
            }
            elseif ($preflightState.PSObject.Properties['serial'] -and $null -ne $preflightState.serial -and $preflightState.serial.PSObject.Properties['serial_ready']) {
                $serialReady = [bool]$preflightState.serial.serial_ready
            }
        }
        if (-not $serialReady) {
            throw "safe_home preflight blocked: MIM_ARM serial controller is not ready."
        }

        $goSafeResult = Invoke-SSHCommand -SessionId ([int]$sessionInfo.ssh.SessionId) -Command $goSafeCommand -TimeOut $TimeoutSeconds
        if ($goSafeResult.ExitStatus -ne 0) {
            $goSafeError = Get-CommandErrorText -Result $goSafeResult
            if ([string]::IsNullOrWhiteSpace($goSafeError)) {
                $goSafeError = Get-CommandOutputText -Result $goSafeResult
            }
            throw ("safe_home execution failed: {0}" -f $goSafeError)
        }

        $goSafeRaw = Get-CommandOutputText -Result $goSafeResult
        $goSafePayload = ConvertFrom-JsonIfPossible -Text $goSafeRaw
        if ($null -ne $goSafePayload -and $goSafePayload.PSObject.Properties['status']) {
            $responseStatus = ([string]$goSafePayload.status).Trim().ToLowerInvariant()
            if ($responseStatus -notin @('ok', 'success')) {
                throw ("safe_home execution returned non-success status '{0}'." -f [string]$goSafePayload.status)
            }
        }

        $postflightResult = Invoke-SSHCommand -SessionId ([int]$sessionInfo.ssh.SessionId) -Command $armStateCommand -TimeOut $TimeoutSeconds
        $postflightRaw = Get-CommandOutputText -Result $postflightResult
        $postflightState = if ($postflightResult.ExitStatus -eq 0) { ConvertFrom-JsonIfPossible -Text $postflightRaw } else { $null }

        return [pscustomobject]@{
            ok = $true
            action = 'safe_home'
            execution_mode = 'mim_arm_ssh_http'
            host_alias = [string]$sessionInfo.host_alias
            resolved_host = [string]$sessionInfo.resolved_host
            user_name = [string]$sessionInfo.user_name
            port = [int]$sessionInfo.port
            endpoint = 'http://127.0.0.1:5000/go_safe'
            preflight = if ($null -ne $preflightState) { $preflightState } else { $preflightRaw }
            response = if ($null -ne $goSafePayload) { $goSafePayload } else { $goSafeRaw }
            postflight = if ($null -ne $postflightState) { $postflightState } else { $postflightRaw }
            completed_at = Get-UtcNow
        }
    }
    finally {
        Close-MimArmSshSession -SessionInfo $sessionInfo
    }
}

function Invoke-MimArmNamedRoutine {
    param(
        [Parameter(Mandatory = $true)][string]$DotEnvPathValue,
        [Parameter(Mandatory = $true)][string]$RoutineName,
        [int]$TimeoutSeconds = 30
    )

    $resolvedHost = Resolve-MimSshSettingValue -ExplicitValue "" -EnvVarName "MIM_ARM_SSH_HOST" -DotEnvPathValue $DotEnvPathValue
    if ([string]::IsNullOrWhiteSpace($resolvedHost)) {
        $resolvedHost = Resolve-MimSshSettingValue -ExplicitValue "" -EnvVarName "MIM_SSH_HOST" -DotEnvPathValue $DotEnvPathValue
    }
    if ([string]::IsNullOrWhiteSpace($resolvedHost)) {
        throw ("{0} requires MIM_ARM_SSH_HOST or MIM_SSH_HOST in .env" -f $RoutineName)
    }

    $resolvedUser = Resolve-MimSshSettingValue -ExplicitValue "" -EnvVarName "MIM_ARM_SSH_USER" -DotEnvPathValue $DotEnvPathValue
    if ([string]::IsNullOrWhiteSpace($resolvedUser)) {
        $resolvedUser = Resolve-MimSshSettingValue -ExplicitValue "" -EnvVarName "MIM_SSH_USER" -DotEnvPathValue $DotEnvPathValue
    }
    if ([string]::IsNullOrWhiteSpace($resolvedUser)) {
        $resolvedUser = "testpilot"
    }

    $resolvedPortText = Resolve-MimSshSettingValue -ExplicitValue "" -EnvVarName "MIM_ARM_SSH_PORT" -DotEnvPathValue $DotEnvPathValue
    if ([string]::IsNullOrWhiteSpace($resolvedPortText)) {
        $resolvedPortText = Resolve-MimSshSettingValue -ExplicitValue "" -EnvVarName "MIM_SSH_PORT" -DotEnvPathValue $DotEnvPathValue
    }
    $resolvedPort = 22
    if (-not [string]::IsNullOrWhiteSpace($resolvedPortText)) {
        $parsedPort = 0
        if ([int]::TryParse($resolvedPortText, [ref]$parsedPort) -and $parsedPort -gt 0) {
            $resolvedPort = $parsedPort
        }
    }

    $resolvedPassword = Resolve-MimSshSettingValue -ExplicitValue "" -EnvVarName "MIM_ARM_SSH_HOST_PASS" -DotEnvPathValue $DotEnvPathValue
    if ([string]::IsNullOrWhiteSpace($resolvedPassword)) {
        $resolvedPassword = Resolve-MimSshSettingValue -ExplicitValue "" -EnvVarName "MIM_SSH_PASSWORD" -DotEnvPathValue $DotEnvPathValue
    }
    if ([string]::IsNullOrWhiteSpace($resolvedPassword)) {
        throw ("{0} requires MIM_ARM_SSH_HOST_PASS or MIM_SSH_PASSWORD in .env" -f $RoutineName)
    }

    $sessionInfo = $null
    try {
        $sessionInfo = New-MimArmSshSession -HostAlias $resolvedHost -UserName $resolvedUser -Port $resolvedPort -Password $resolvedPassword

        $armStateCommand = "curl -fsS http://127.0.0.1:5000/arm_state"
        $listRoutinesCommand = "curl -fsS http://127.0.0.1:5000/list_routines"
        $playRoutineCommand = ('curl -fsS -H ''Content-Type: application/json'' -X POST http://127.0.0.1:5000/play_routine -d ''{{"name":"{0}"}}''' -f $RoutineName)

        $preflightResult = Invoke-SSHCommand -SessionId ([int]$sessionInfo.ssh.SessionId) -Command $armStateCommand -TimeOut $TimeoutSeconds
        if ($preflightResult.ExitStatus -ne 0) {
            $preflightError = Get-CommandErrorText -Result $preflightResult
            if ([string]::IsNullOrWhiteSpace($preflightError)) {
                $preflightError = Get-CommandOutputText -Result $preflightResult
            }
            throw ("{0} preflight failed: {1}" -f $RoutineName, $preflightError)
        }

        $preflightRaw = Get-CommandOutputText -Result $preflightResult
        $preflightState = ConvertFrom-JsonIfPossible -Text $preflightRaw
        $serialReady = $false
        if ($null -ne $preflightState) {
            if ($preflightState.PSObject.Properties['serial_ready']) {
                $serialReady = [bool]$preflightState.serial_ready
            }
            elseif ($preflightState.PSObject.Properties['serial'] -and $null -ne $preflightState.serial -and $preflightState.serial.PSObject.Properties['serial_ready']) {
                $serialReady = [bool]$preflightState.serial.serial_ready
            }
        }
        if (-not $serialReady) {
            throw ("{0} preflight blocked: MIM_ARM serial controller is not ready." -f $RoutineName)
        }

        $listRoutinesResult = Invoke-SSHCommand -SessionId ([int]$sessionInfo.ssh.SessionId) -Command $listRoutinesCommand -TimeOut $TimeoutSeconds
        if ($listRoutinesResult.ExitStatus -ne 0) {
            $routineError = Get-CommandErrorText -Result $listRoutinesResult
            if ([string]::IsNullOrWhiteSpace($routineError)) {
                $routineError = Get-CommandOutputText -Result $listRoutinesResult
            }
            throw ("{0} routine discovery failed: {1}" -f $RoutineName, $routineError)
        }

        $routineListRaw = Get-CommandOutputText -Result $listRoutinesResult
        $routineList = ConvertFrom-JsonIfPossible -Text $routineListRaw
        $availableRoutines = @()
        if ($null -ne $routineList -and $routineList.PSObject.Properties['routines']) {
            $availableRoutines = @($routineList.routines)
        }
        $selectedRoutine = @($availableRoutines | Where-Object { [string]::Equals([string]$_.name, $RoutineName, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
        if (@($selectedRoutine).Count -eq 0) {
            $knownNames = @($availableRoutines | ForEach-Object { [string]$_.name } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            $knownText = if (@($knownNames).Count -gt 0) { ($knownNames -join ', ') } else { 'none' }
            throw ("{0} routine is not available on MIM. Available routines: {1}" -f $RoutineName, $knownText)
        }

        $playRoutineResult = Invoke-SSHCommand -SessionId ([int]$sessionInfo.ssh.SessionId) -Command $playRoutineCommand -TimeOut $TimeoutSeconds
        if ($playRoutineResult.ExitStatus -ne 0) {
            $playRoutineError = Get-CommandErrorText -Result $playRoutineResult
            if ([string]::IsNullOrWhiteSpace($playRoutineError)) {
                $playRoutineError = Get-CommandOutputText -Result $playRoutineResult
            }
            throw ("{0} execution failed: {1}" -f $RoutineName, $playRoutineError)
        }

        $playRoutineRaw = Get-CommandOutputText -Result $playRoutineResult
        $playRoutinePayload = ConvertFrom-JsonIfPossible -Text $playRoutineRaw
        if ($null -ne $playRoutinePayload -and $playRoutinePayload.PSObject.Properties['status']) {
            $responseStatus = ([string]$playRoutinePayload.status).Trim().ToLowerInvariant()
            if ($responseStatus -notin @('ok', 'success')) {
                throw ("{0} execution returned non-success status '{1}'." -f $RoutineName, [string]$playRoutinePayload.status)
            }
        }

        $postflightResult = Invoke-SSHCommand -SessionId ([int]$sessionInfo.ssh.SessionId) -Command $armStateCommand -TimeOut $TimeoutSeconds
        $postflightRaw = Get-CommandOutputText -Result $postflightResult
        $postflightState = if ($postflightResult.ExitStatus -eq 0) { ConvertFrom-JsonIfPossible -Text $postflightRaw } else { $null }

        return [pscustomobject]@{
            ok = $true
            action = $RoutineName
            execution_mode = 'mim_arm_ssh_http_routine'
            host_alias = [string]$sessionInfo.host_alias
            resolved_host = [string]$sessionInfo.resolved_host
            user_name = [string]$sessionInfo.user_name
            port = [int]$sessionInfo.port
            endpoint = 'http://127.0.0.1:5000/play_routine'
            routine = if (@($selectedRoutine).Count -gt 0) { $selectedRoutine[0] } else { $null }
            routine_catalog = if ($null -ne $routineList) { $routineList } else { $routineListRaw }
            preflight = if ($null -ne $preflightState) { $preflightState } else { $preflightRaw }
            response = if ($null -ne $playRoutinePayload) { $playRoutinePayload } else { $playRoutineRaw }
            postflight = if ($null -ne $postflightState) { $postflightState } else { $postflightRaw }
            completed_at = Get-UtcNow
        }
    }
    finally {
        Close-MimArmSshSession -SessionInfo $sessionInfo
    }
}

function Assert-Exists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if (-not (Test-Path -Path $Path)) {
        throw "$Name not found at $Path"
    }
}

function Get-MaxStateReadBytes {
    $rawValue = [string][Environment]::GetEnvironmentVariable("TOD_STATE_MAX_READ_BYTES")
    if (-not [string]::IsNullOrWhiteSpace($rawValue)) {
        $parsed = [int64]0
        if ([int64]::TryParse($rawValue, [ref]$parsed) -and $parsed -gt 0) {
            return $parsed
        }
    }

    return [int64]$defaultMaxStateReadBytes
}

function Get-ProcessMemorySnapshot {
    $process = [System.Diagnostics.Process]::GetCurrentProcess()
    return [pscustomobject]@{
        working_set_mb = [math]::Round(([double]$process.WorkingSet64 / 1MB), 2)
        private_memory_mb = [math]::Round(([double]$process.PrivateMemorySize64 / 1MB), 2)
        managed_heap_mb = [math]::Round(([double][System.GC]::GetTotalMemory($false) / 1MB), 2)
        sampled_at = Get-UtcNow
    }
}

function Get-StateLoadGuardInfo {
    param([string]$Path = $statePath)

    $thresholdBytes = Get-MaxStateReadBytes
    $exists = Test-Path -Path $Path
    $sizeBytes = [int64]0
    if ($exists) {
        try {
            $sizeBytes = [int64](Get-Item -Path $Path -ErrorAction Stop).Length
        }
        catch {
            $sizeBytes = [int64]0
        }
    }

    return [pscustomobject]@{
        path = $Path
        exists = [bool]$exists
        size_bytes = $sizeBytes
        threshold_bytes = [int64]$thresholdBytes
        size_mib = [math]::Round(([double]$sizeBytes / 1MB), 2)
        threshold_mib = [math]::Round(([double]$thresholdBytes / 1MB), 2)
        oversized = ([bool]$exists -and $sizeBytes -gt $thresholdBytes)
    }
}

function New-MinimalTodState {
    $state = [pscustomobject]@{
        source = "tod-oversized-state-ephemeral-v1"
        updated_at = ""
        objectives = @()
        tasks = @()
        execution_results = @()
        review_decisions = @()
        journal = @()
        sync_state = [pscustomobject]@{}
        engine_performance = [pscustomobject]@{}
        routing_decisions = [pscustomobject]@{}
        routing_feedback = [pscustomobject]@{}
        engineering_loop = [pscustomobject]@{}
    }

    Normalize-State -State $state
    return $state
}

function Test-ActionSupportsLightweightStateBus {
    param([Parameter(Mandatory = $true)][string]$ActionName)

    switch ($ActionName.ToLowerInvariant()) {
        "get-state-bus" { return $true }
        "get-reliability" { return $true }
        "show-reliability-dashboard" { return $true }
        "show-failure-taxonomy" { return $true }
        "get-engineering-loop-summary" { return $true }
        "get-engineering-signal" { return $true }
        default { return $false }
    }
}

function Invoke-LightweightStateBusPayload {
    if (-not (Test-Path -Path $lightweightStateBusScript)) {
        throw "Lightweight state bus script not found at $lightweightStateBusScript"
    }

    $raw = & $lightweightStateBusScript -AsJson -StatePath $statePath -MaxStateReadBytes (Get-MaxStateReadBytes)
    return ($raw | ConvertFrom-Json)
}

function Load-State {
    Assert-Exists -Path $statePath -Name "State file"

    $guardInfo = Get-StateLoadGuardInfo -Path $statePath
    if ([bool]$guardInfo.oversized) {
        throw ("State file too large for safe in-process load: {0} MiB exceeds threshold {1} MiB. Use lightweight state bus actions or remote-backed execution paths." -f $guardInfo.size_mib, $guardInfo.threshold_mib)
    }

    $maxAttempts = 6
    $baseDelayMs = 90
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        try {
            $raw = Get-Content -Path $statePath -Raw -ErrorAction Stop
            $state = $raw | ConvertFrom-Json
            Normalize-State -State $state
            Sync-ExecutionHistoryToState -State $state | Out-Null
            Sync-JournalHistoryToState -State $state | Out-Null
            Sync-ReliabilityHistoryToState -State $state | Out-Null
            Sync-EngineeringLoopHistoryToState -State $state | Out-Null
            return $state
        }
        catch {
            $message = [string]$_.Exception.Message
            $isLockContention = (
                ($message -match "used by another process") -or
                ($message -match "cannot access the file")
            )

            if (-not $isLockContention -or $attempt -ge $maxAttempts) {
                throw
            }

            Start-Sleep -Milliseconds ($baseDelayMs * $attempt)
        }
    }
}

function Save-State {
    param(
        [Parameter(Mandatory = $true)]$State,
        [AllowNull()]$Config = $null
    )
    Normalize-State -State $State

    $effectiveConfig = $Config
    if ($null -eq $effectiveConfig) {
        $configVar = Get-Variable -Name config -Scope Script -ErrorAction SilentlyContinue
        if ($null -ne $configVar) {
            $effectiveConfig = $configVar.Value
        }
    }

    Protect-StateForOperationalUse -State $State
    if ($null -ne $effectiveConfig) {
        Compress-StateForOperationalUse -State $State -Config $effectiveConfig | Out-Null
    }

    $historyLoop = if ($State.PSObject.Properties['engineering_loop']) { $State.engineering_loop } else { $null }
    if ($State.PSObject.Properties['journal']) {
        $null = Save-JournalHistoryStore -State $State
    }
    if ($State.PSObject.Properties['execution_results'] -or $State.PSObject.Properties['review_decisions']) {
        $null = Save-ExecutionHistoryStore -State $State
    }
    if ($State.PSObject.Properties['routing_decisions'] -or $State.PSObject.Properties['engine_performance']) {
        $null = Save-ReliabilityHistoryStore -State $State
    }
    if ($historyLoop) {
        $null = Save-EngineeringLoopHistoryStore -State $State
    }

    $savedJournal = if ($State.PSObject.Properties['journal']) { @($State.journal) } else { @() }
    $savedExecutionResults = if ($State.PSObject.Properties['execution_results']) { @($State.execution_results) } else { @() }
    $savedReviewDecisions = if ($State.PSObject.Properties['review_decisions']) { @($State.review_decisions) } else { @() }
    $savedRoutingDecisionRecords = if ($State.PSObject.Properties['routing_decisions'] -and $State.routing_decisions -and $State.routing_decisions.PSObject.Properties['records']) { @($State.routing_decisions.records) } else { @() }
    $savedEnginePerformanceRecords = if ($State.PSObject.Properties['engine_performance'] -and $State.engine_performance -and $State.engine_performance.PSObject.Properties['records']) { @($State.engine_performance.records) } else { @() }
    $savedRunHistory = if ($historyLoop -and $historyLoop.PSObject.Properties['run_history']) { @($historyLoop.run_history) } else { @() }
    $savedScorecardHistory = if ($historyLoop -and $historyLoop.PSObject.Properties['scorecard_history']) { @($historyLoop.scorecard_history) } else { @() }
    $savedCycleRecords = if ($historyLoop -and $historyLoop.PSObject.Properties['cycle_records']) { @($historyLoop.cycle_records) } else { @() }
    $savedReviewActions = if ($historyLoop -and $historyLoop.PSObject.Properties['review_actions']) { @($historyLoop.review_actions) } else { @() }

    if ($State.PSObject.Properties['journal']) {
        $State.journal = @()
    }
    if ($State.PSObject.Properties['execution_results']) {
        $State.execution_results = @()
    }
    if ($State.PSObject.Properties['review_decisions']) {
        $State.review_decisions = @()
    }
    if ($State.PSObject.Properties['routing_decisions'] -and $State.routing_decisions -and $State.routing_decisions.PSObject.Properties['records']) {
        $State.routing_decisions.records = @()
    }
    if ($State.PSObject.Properties['engine_performance'] -and $State.engine_performance -and $State.engine_performance.PSObject.Properties['records']) {
        $State.engine_performance.records = @()
    }
    if ($historyLoop) {
        $historyLoop.run_history = @()
        $historyLoop.scorecard_history = @()
        $historyLoop.cycle_records = @()
        $historyLoop.review_actions = @()
    }

    $json = $State | ConvertTo-Json -Depth 12

    $maxAttempts = 6
    $baseDelayMs = 120
    try {
        for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
            try {
                Set-Content -Path $statePath -Value $json -ErrorAction Stop
                return
            }
            catch {
                $message = [string]$_.Exception.Message
                $isLockContention = (
                    ($message -match "used by another process") -or
                    ($message -match "cannot access the file")
                )

                if (-not $isLockContention -or $attempt -ge $maxAttempts) {
                    throw
                }

                Start-Sleep -Milliseconds ($baseDelayMs * $attempt)
            }
        }
    }
    finally {
        if ($State.PSObject.Properties['journal']) {
            $State.journal = @($savedJournal)
        }
        if ($State.PSObject.Properties['execution_results']) {
            $State.execution_results = @($savedExecutionResults)
        }
        if ($State.PSObject.Properties['review_decisions']) {
            $State.review_decisions = @($savedReviewDecisions)
        }
        if ($State.PSObject.Properties['routing_decisions'] -and $State.routing_decisions) {
            $State.routing_decisions.records = @($savedRoutingDecisionRecords)
        }
        if ($State.PSObject.Properties['engine_performance'] -and $State.engine_performance) {
            $State.engine_performance.records = @($savedEnginePerformanceRecords)
        }
        if ($historyLoop) {
            $historyLoop.run_history = @($savedRunHistory)
            $historyLoop.scorecard_history = @($savedScorecardHistory)
            $historyLoop.cycle_records = @($savedCycleRecords)
            $historyLoop.review_actions = @($savedReviewActions)
        }
    }
}

function Resolve-JournalHistoryPath {
    param([string]$StateFilePath = "")

    $targetStatePath = if ([string]::IsNullOrWhiteSpace($StateFilePath)) { $statePath } else { $StateFilePath }
    return [System.IO.Path]::ChangeExtension($targetStatePath, 'journal-history.json')
}

function New-JournalHistoryStore {
    return [pscustomobject]@{
        journal = @()
        updated_at = ""
    }
}

function Get-JournalHistoryStateSnapshot {
    param([AllowNull()]$State = $null)

    $snapshot = New-JournalHistoryStore
    if ($null -eq $State -or -not $State.PSObject.Properties['journal']) {
        return $snapshot
    }

    $snapshot.journal = @($State.journal | Where-Object { $null -ne $_ })
    $snapshot.updated_at = Get-UtcNow
    return $snapshot
}

function Read-JournalHistoryStore {
    param(
        [AllowNull()]$State = $null,
        [switch]$PreferState
    )

    $stateSnapshot = Get-JournalHistoryStateSnapshot -State $State
    if ($PreferState -and @($stateSnapshot.journal).Count -gt 0) {
        return $stateSnapshot
    }

    $path = Resolve-JournalHistoryPath
    if (Test-Path -Path $path) {
        try {
            $raw = Get-Content -Path $path -Raw -ErrorAction Stop
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $parsed = $raw | ConvertFrom-Json
                $store = New-JournalHistoryStore
                if ($parsed -is [System.Array]) {
                    $store.journal = @($parsed | Where-Object { $null -ne $_ })
                }
                elseif ($parsed.PSObject.Properties['journal']) {
                    $store.journal = @($parsed.journal | Where-Object { $null -ne $_ })
                    $store.updated_at = if ($parsed.PSObject.Properties['updated_at']) { [string]$parsed.updated_at } else { "" }
                }
                return $store
            }
        }
        catch {
        }
    }

    return $stateSnapshot
}

function Sync-JournalHistoryToState {
    param(
        [Parameter(Mandatory = $true)]$State,
        [AllowNull()]$HistoryStore = $null
    )

    $store = if ($null -ne $HistoryStore) { $HistoryStore } else { Read-JournalHistoryStore -State $State }
    if (-not $State.PSObject.Properties['journal']) {
        $State | Add-Member -NotePropertyName journal -NotePropertyValue @() -Force
    }
    $State.journal = @($store.journal)
    return $State.journal
}

function Set-JsonFileWithRetry {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Json,
        [int]$MaxAttempts = 5,
        [int]$BaseDelayMs = 100
    )

    if ($MaxAttempts -lt 1) {
        $MaxAttempts = 1
    }

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            Set-Content -Path $Path -Value $Json -ErrorAction Stop
            return
        }
        catch [System.IO.IOException] {
            if ($attempt -ge $MaxAttempts) {
                throw
            }

            Start-Sleep -Milliseconds ($BaseDelayMs * $attempt)
        }
    }
}

function Save-JournalHistoryStore {
    param([Parameter(Mandatory = $true)]$State)

    $snapshot = Get-JournalHistoryStateSnapshot -State $State
    $path = Resolve-JournalHistoryPath
    $dir = Split-Path -Parent $path
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $json = $snapshot | ConvertTo-Json -Depth 20
    Set-JsonFileWithRetry -Path $path -Json $json
    return $path
}

function Resolve-ExecutionHistoryPath {
    param([string]$StateFilePath = "")

    $targetStatePath = if ([string]::IsNullOrWhiteSpace($StateFilePath)) { $statePath } else { $StateFilePath }
    return [System.IO.Path]::ChangeExtension($targetStatePath, 'execution-history.json')
}

function New-ExecutionHistoryStore {
    return [pscustomobject]@{
        execution_results = @()
        review_decisions = @()
    }
}

function Get-ExecutionHistoryStateSnapshot {
    param([AllowNull()]$State = $null)

    $snapshot = New-ExecutionHistoryStore
    if ($null -eq $State) {
        return $snapshot
    }

    $snapshot.execution_results = if ($State.PSObject.Properties['execution_results']) { @($State.execution_results | Where-Object { $null -ne $_ }) } else { @() }
    $snapshot.review_decisions = if ($State.PSObject.Properties['review_decisions']) { @($State.review_decisions | Where-Object { $null -ne $_ }) } else { @() }
    return $snapshot
}

function Read-ExecutionHistoryStore {
    param(
        [AllowNull()]$State = $null,
        [switch]$PreferState
    )

    $stateSnapshot = Get-ExecutionHistoryStateSnapshot -State $State
    $stateHasCollections = (
        @($stateSnapshot.execution_results).Count -gt 0 -or
        @($stateSnapshot.review_decisions).Count -gt 0
    )
    if ($PreferState -and $stateHasCollections) {
        return $stateSnapshot
    }

    $path = Resolve-ExecutionHistoryPath
    if (Test-Path -Path $path) {
        try {
            $raw = Get-Content -Path $path -Raw -ErrorAction Stop
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $parsed = $raw | ConvertFrom-Json
                $store = New-ExecutionHistoryStore
                $store.execution_results = if ($parsed.PSObject.Properties['execution_results']) { @($parsed.execution_results | Where-Object { $null -ne $_ }) } else { @() }
                $store.review_decisions = if ($parsed.PSObject.Properties['review_decisions']) { @($parsed.review_decisions | Where-Object { $null -ne $_ }) } else { @() }
                return $store
            }
        }
        catch {
        }
    }

    return $stateSnapshot
}

function Sync-ExecutionHistoryToState {
    param(
        [Parameter(Mandatory = $true)]$State,
        [AllowNull()]$HistoryStore = $null
    )

    $store = if ($null -ne $HistoryStore) { $HistoryStore } else { Read-ExecutionHistoryStore -State $State }
    if (-not $State.PSObject.Properties['execution_results']) {
        $State | Add-Member -NotePropertyName execution_results -NotePropertyValue @() -Force
    }
    if (-not $State.PSObject.Properties['review_decisions']) {
        $State | Add-Member -NotePropertyName review_decisions -NotePropertyValue @() -Force
    }
    $State.execution_results = @($store.execution_results)
    $State.review_decisions = @($store.review_decisions)
    return $State
}

function Save-ExecutionHistoryStore {
    param([Parameter(Mandatory = $true)]$State)

    $snapshot = Get-ExecutionHistoryStateSnapshot -State $State
    $path = Resolve-ExecutionHistoryPath
    $dir = Split-Path -Parent $path
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $json = $snapshot | ConvertTo-Json -Depth 20
    Set-JsonFileWithRetry -Path $path -Json $json
    return $path
}

function Resolve-ReliabilityHistoryPath {
    param([string]$StateFilePath = "")

    $targetStatePath = if ([string]::IsNullOrWhiteSpace($StateFilePath)) { $statePath } else { $StateFilePath }
    return [System.IO.Path]::ChangeExtension($targetStatePath, 'reliability-history.json')
}

function New-ReliabilityHistoryStore {
    return [pscustomobject]@{
        engine_performance = [pscustomobject]@{
            records = @()
            updated_at = ""
        }
        routing_decisions = [pscustomobject]@{
            records = @()
            updated_at = ""
        }
    }
}

function Get-ReliabilityHistoryStateSnapshot {
    param([AllowNull()]$State = $null)

    $snapshot = New-ReliabilityHistoryStore
    if ($null -eq $State) {
        return $snapshot
    }

    if ($State.PSObject.Properties['engine_performance'] -and $State.engine_performance) {
        $snapshot.engine_performance.records = if ($State.engine_performance.PSObject.Properties['records']) { @($State.engine_performance.records | Where-Object { $null -ne $_ }) } else { @() }
        $snapshot.engine_performance.updated_at = if ($State.engine_performance.PSObject.Properties['updated_at']) { [string]$State.engine_performance.updated_at } else { "" }
    }
    if ($State.PSObject.Properties['routing_decisions'] -and $State.routing_decisions) {
        $snapshot.routing_decisions.records = if ($State.routing_decisions.PSObject.Properties['records']) { @($State.routing_decisions.records | Where-Object { $null -ne $_ }) } else { @() }
        $snapshot.routing_decisions.updated_at = if ($State.routing_decisions.PSObject.Properties['updated_at']) { [string]$State.routing_decisions.updated_at } else { "" }
    }
    return $snapshot
}

function Read-ReliabilityHistoryStore {
    param(
        [AllowNull()]$State = $null,
        [switch]$PreferState
    )

    $stateSnapshot = Get-ReliabilityHistoryStateSnapshot -State $State
    $stateHasCollections = (
        @($stateSnapshot.engine_performance.records).Count -gt 0 -or
        @($stateSnapshot.routing_decisions.records).Count -gt 0
    )
    if ($PreferState -and $stateHasCollections) {
        return $stateSnapshot
    }

    $path = Resolve-ReliabilityHistoryPath
    if (Test-Path -Path $path) {
        try {
            $raw = Get-Content -Path $path -Raw -ErrorAction Stop
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $parsed = $raw | ConvertFrom-Json
                $store = New-ReliabilityHistoryStore
                if ($parsed.PSObject.Properties['engine_performance'] -and $parsed.engine_performance) {
                    $store.engine_performance.records = if ($parsed.engine_performance.PSObject.Properties['records']) { @($parsed.engine_performance.records | Where-Object { $null -ne $_ }) } else { @() }
                    $store.engine_performance.updated_at = if ($parsed.engine_performance.PSObject.Properties['updated_at']) { [string]$parsed.engine_performance.updated_at } else { "" }
                }
                if ($parsed.PSObject.Properties['routing_decisions'] -and $parsed.routing_decisions) {
                    $store.routing_decisions.records = if ($parsed.routing_decisions.PSObject.Properties['records']) { @($parsed.routing_decisions.records | Where-Object { $null -ne $_ }) } else { @() }
                    $store.routing_decisions.updated_at = if ($parsed.routing_decisions.PSObject.Properties['updated_at']) { [string]$parsed.routing_decisions.updated_at } else { "" }
                }
                return $store
            }
        }
        catch {
        }
    }

    return $stateSnapshot
}

function Sync-ReliabilityHistoryToState {
    param(
        [Parameter(Mandatory = $true)]$State,
        [AllowNull()]$HistoryStore = $null
    )

    $store = if ($null -ne $HistoryStore) { $HistoryStore } else { Read-ReliabilityHistoryStore -State $State }
    if (-not $State.PSObject.Properties['engine_performance'] -or $null -eq $State.engine_performance) {
        $State | Add-Member -NotePropertyName engine_performance -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    if (-not $State.PSObject.Properties['routing_decisions'] -or $null -eq $State.routing_decisions) {
        $State | Add-Member -NotePropertyName routing_decisions -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    $State.engine_performance | Add-Member -NotePropertyName records -NotePropertyValue @($store.engine_performance.records) -Force
    $State.engine_performance | Add-Member -NotePropertyName updated_at -NotePropertyValue ([string]$store.engine_performance.updated_at) -Force
    $State.routing_decisions | Add-Member -NotePropertyName records -NotePropertyValue @($store.routing_decisions.records) -Force
    $State.routing_decisions | Add-Member -NotePropertyName updated_at -NotePropertyValue ([string]$store.routing_decisions.updated_at) -Force
    return $State
}

function Save-ReliabilityHistoryStore {
    param([Parameter(Mandatory = $true)]$State)

    $snapshot = Get-ReliabilityHistoryStateSnapshot -State $State
    $path = Resolve-ReliabilityHistoryPath
    $dir = Split-Path -Parent $path
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $json = $snapshot | ConvertTo-Json -Depth 20
    Set-JsonFileWithRetry -Path $path -Json $json
    return $path
}

function Resolve-EngineeringLoopHistoryPath {
    param([string]$StateFilePath = "")

    $targetStatePath = if ([string]::IsNullOrWhiteSpace($StateFilePath)) { $statePath } else { $StateFilePath }
    return [System.IO.Path]::ChangeExtension($targetStatePath, 'engineering-loop-history.json')
}

function New-EngineeringLoopHistoryStore {
    return [pscustomobject]@{
        run_history = @()
        scorecard_history = @()
        cycle_records = @()
        review_actions = @()
        last_run = $null
        last_scorecard = $null
        last_cycle = $null
        pending_approval_count = 0
        updated_at = ""
    }
}

function Get-EngineeringLoopHistoryStateSnapshot {
    param([AllowNull()]$State = $null)

    $snapshot = New-EngineeringLoopHistoryStore
    if ($null -eq $State -or -not $State.PSObject.Properties['engineering_loop'] -or $null -eq $State.engineering_loop) {
        return $snapshot
    }

    $loop = $State.engineering_loop
    $snapshot.run_history = if ($loop.PSObject.Properties['run_history']) { @($loop.run_history | Where-Object { $null -ne $_ }) } else { @() }
    $snapshot.scorecard_history = if ($loop.PSObject.Properties['scorecard_history']) { @($loop.scorecard_history | Where-Object { $null -ne $_ }) } else { @() }
    $snapshot.cycle_records = if ($loop.PSObject.Properties['cycle_records']) { @($loop.cycle_records | Where-Object { $null -ne $_ }) } else { @() }
    $snapshot.review_actions = if ($loop.PSObject.Properties['review_actions']) { @($loop.review_actions | Where-Object { $null -ne $_ }) } else { @() }
    $snapshot.last_run = if ($loop.PSObject.Properties['last_run']) { $loop.last_run } else { $null }
    $snapshot.last_scorecard = if ($loop.PSObject.Properties['last_scorecard']) { $loop.last_scorecard } else { $null }
    $snapshot.last_cycle = if ($loop.PSObject.Properties['last_cycle']) { $loop.last_cycle } else { $null }
    $snapshot.pending_approval_count = if ($loop.PSObject.Properties['pending_approval_count']) { [int]$loop.pending_approval_count } else { [int]@($snapshot.cycle_records | Where-Object { $_.PSObject.Properties['approval_status'] -and ([string]$_.approval_status).ToLowerInvariant() -eq 'pending_apply' }).Count }
    $snapshot.updated_at = if ($loop.PSObject.Properties['updated_at']) { [string]$loop.updated_at } else { "" }
    return $snapshot
}

function Test-EngineeringLoopHistoryStoreHasData {
    param([AllowNull()]$HistoryStore)

    if ($null -eq $HistoryStore) {
        return $false
    }

    return (
        @($HistoryStore.run_history).Count -gt 0 -or
        @($HistoryStore.scorecard_history).Count -gt 0 -or
        @($HistoryStore.cycle_records).Count -gt 0 -or
        @($HistoryStore.review_actions).Count -gt 0 -or
        $null -ne $HistoryStore.last_run -or
        $null -ne $HistoryStore.last_scorecard -or
        $null -ne $HistoryStore.last_cycle
    )
}

function Read-EngineeringLoopHistoryStore {
    param(
        [AllowNull()]$State = $null,
        [switch]$PreferState
    )

    $stateSnapshot = Get-EngineeringLoopHistoryStateSnapshot -State $State
    $stateHasCollections = (
        @($stateSnapshot.run_history).Count -gt 0 -or
        @($stateSnapshot.scorecard_history).Count -gt 0 -or
        @($stateSnapshot.cycle_records).Count -gt 0 -or
        @($stateSnapshot.review_actions).Count -gt 0
    )
    $stateHasData = Test-EngineeringLoopHistoryStoreHasData -HistoryStore $stateSnapshot
    if ($PreferState -and $stateHasCollections) {
        return $stateSnapshot
    }

    $path = Resolve-EngineeringLoopHistoryPath
    if (Test-Path -Path $path) {
        try {
            $raw = Get-Content -Path $path -Raw -ErrorAction Stop
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $parsed = $raw | ConvertFrom-Json
                $store = New-EngineeringLoopHistoryStore
                $store.run_history = if ($parsed.PSObject.Properties['run_history']) { @($parsed.run_history | Where-Object { $null -ne $_ }) } else { @() }
                $store.scorecard_history = if ($parsed.PSObject.Properties['scorecard_history']) { @($parsed.scorecard_history | Where-Object { $null -ne $_ }) } else { @() }
                $store.cycle_records = if ($parsed.PSObject.Properties['cycle_records']) { @($parsed.cycle_records | Where-Object { $null -ne $_ }) } else { @() }
                $store.review_actions = if ($parsed.PSObject.Properties['review_actions']) { @($parsed.review_actions | Where-Object { $null -ne $_ }) } else { @() }
                $store.last_run = if ($parsed.PSObject.Properties['last_run']) { $parsed.last_run } else { $null }
                $store.last_scorecard = if ($parsed.PSObject.Properties['last_scorecard']) { $parsed.last_scorecard } else { $null }
                $store.last_cycle = if ($parsed.PSObject.Properties['last_cycle']) { $parsed.last_cycle } else { $null }
                $store.pending_approval_count = if ($parsed.PSObject.Properties['pending_approval_count']) { [int]$parsed.pending_approval_count } else { [int]@($store.cycle_records | Where-Object { $_.PSObject.Properties['approval_status'] -and ([string]$_.approval_status).ToLowerInvariant() -eq 'pending_apply' }).Count }
                $store.updated_at = if ($parsed.PSObject.Properties['updated_at']) { [string]$parsed.updated_at } else { "" }
                return $store
            }
        }
        catch {
        }
    }

    return $stateSnapshot
}

function Sync-EngineeringLoopHistoryToState {
    param(
        [Parameter(Mandatory = $true)]$State,
        [AllowNull()]$HistoryStore = $null
    )

    if (-not $State.PSObject.Properties['engineering_loop'] -or $null -eq $State.engineering_loop) {
        $State | Add-Member -NotePropertyName engineering_loop -NotePropertyValue ([pscustomobject]@{}) -Force
    }

    $loop = $State.engineering_loop
    $store = if ($null -ne $HistoryStore) { $HistoryStore } else { Read-EngineeringLoopHistoryStore -State $State }
    $loop | Add-Member -NotePropertyName run_history -NotePropertyValue @($store.run_history) -Force
    $loop | Add-Member -NotePropertyName scorecard_history -NotePropertyValue @($store.scorecard_history) -Force
    $loop | Add-Member -NotePropertyName cycle_records -NotePropertyValue @($store.cycle_records) -Force
    $loop | Add-Member -NotePropertyName review_actions -NotePropertyValue @($store.review_actions) -Force
    $loop | Add-Member -NotePropertyName last_run -NotePropertyValue $store.last_run -Force
    $loop | Add-Member -NotePropertyName last_scorecard -NotePropertyValue $store.last_scorecard -Force
    $loop | Add-Member -NotePropertyName last_cycle -NotePropertyValue $store.last_cycle -Force
    $loop | Add-Member -NotePropertyName pending_approval_count -NotePropertyValue ([int]$store.pending_approval_count) -Force
    $loop | Add-Member -NotePropertyName updated_at -NotePropertyValue ([string]$store.updated_at) -Force
    return $loop
}

function Save-EngineeringLoopHistoryStore {
    param([Parameter(Mandatory = $true)]$State)

    $snapshot = Get-EngineeringLoopHistoryStateSnapshot -State $State
    $path = Resolve-EngineeringLoopHistoryPath
    $dir = Split-Path -Parent $path
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $json = $snapshot | ConvertTo-Json -Depth 20
    Set-JsonFileWithRetry -Path $path -Json $json
    return $path
}

function Repair-OversizedStateStringLine {
    param(
        [AllowEmptyString()][string]$Line,
        [Parameter(Mandatory = $true)][string]$RepairTimestamp,
        [int]$MaxLineLength = 1048576
    )

    if ($Line.Length -le $MaxLineLength) {
        return $null
    }

    $propertyStart = $Line.IndexOf('"')
    if ($propertyStart -lt 0) {
        return $null
    }

    $propertyEnd = $Line.IndexOf('"', $propertyStart + 1)
    if ($propertyEnd -lt 0) {
        return $null
    }

    $colonIndex = $Line.IndexOf(':', $propertyEnd + 1)
    if ($colonIndex -lt 0) {
        return $null
    }

    $valueStart = $Line.IndexOf('"', $colonIndex + 1)
    if ($valueStart -lt 0) {
        return $null
    }

    $valueEnd = $Line.Length - 1
    while ($valueEnd -gt $valueStart -and [char]::IsWhiteSpace($Line[$valueEnd])) {
        $valueEnd--
    }
    if ($valueEnd -gt $valueStart -and $Line[$valueEnd] -eq ',') {
        $valueEnd--
        while ($valueEnd -gt $valueStart -and [char]::IsWhiteSpace($Line[$valueEnd])) {
            $valueEnd--
        }
    }
    if ($valueEnd -le $valueStart -or $Line[$valueEnd] -ne '"') {
        return $null
    }

    $propertyName = $Line.Substring($propertyStart + 1, $propertyEnd - $propertyStart - 1)
    $originalLength = $valueEnd - $valueStart - 1
    $replacementValue = "[truncated oversized state field; property=$propertyName; original_length=$originalLength; repaired_at=$RepairTimestamp]"
    $rewritten = $Line.Substring(0, $valueStart + 1) + $replacementValue + $Line.Substring($valueEnd)

    return [pscustomobject]@{
        property = $propertyName
        original_length = $originalLength
        line = $rewritten
    }
}

function Repair-StateFileOversizedStrings {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [int]$MaxLineLength = 1048576
    )

    Assert-Exists -Path $Path -Name "State file"

    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $fileTimestamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmmss")
    $tempPath = "$Path.repairing"
    $backupPath = Join-Path (Split-Path -Parent $Path) ("state.repair-{0}.json.bak" -f $fileTimestamp)
    $pendingPath = Join-Path (Split-Path -Parent $Path) ("state.repair-{0}.json.pending" -f $fileTimestamp)
    $originalBytes = (Get-Item -Path $Path).Length
    $changes = @()
    $reader = $null
    $writer = $null

    try {
        $reader = [System.IO.File]::OpenText($Path)
        $writer = New-Object System.IO.StreamWriter($tempPath, $false, ([System.Text.UTF8Encoding]::new($false)))
        $lineNumber = 0

        while (($line = $reader.ReadLine()) -ne $null) {
            $lineNumber++
            $rewritten = Repair-OversizedStateStringLine -Line $line -RepairTimestamp $timestamp -MaxLineLength $MaxLineLength
            if ($null -ne $rewritten) {
                $changes += [pscustomobject]@{
                    line = $lineNumber
                    property = [string]$rewritten.property
                    original_length = [int64]$rewritten.original_length
                }
                $writer.WriteLine([string]$rewritten.line)
            }
            else {
                $writer.WriteLine($line)
            }
        }
    }
    catch {
        if (Test-Path -Path $tempPath) {
            Remove-Item -Path $tempPath -Force -ErrorAction SilentlyContinue
        }
        throw
    }
    finally {
        if ($writer) { $writer.Dispose() }
        if ($reader) { $reader.Dispose() }
    }

    if (@($changes).Count -eq 0) {
        if (Test-Path -Path $tempPath) {
            Remove-Item -Path $tempPath -Force -ErrorAction SilentlyContinue
        }
        return [pscustomobject]@{
            changed = $false
            state_path = $Path
            backup_path = $null
            repaired_lines = @()
            original_bytes = [int64]$originalBytes
            repaired_bytes = [int64]$originalBytes
        }
    }

    $maxAttempts = 6
    $baseDelayMs = 120
    $replacementComplete = $false
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        try {
            Move-Item -Path $Path -Destination $backupPath -Force -ErrorAction Stop
            Move-Item -Path $tempPath -Destination $Path -Force -ErrorAction Stop
            $replacementComplete = $true
            break
        }
        catch {
            $message = [string]$_.Exception.Message
            $isLockContention = (
                ($message -match "used by another process") -or
                ($message -match "cannot access the file")
            )

            if (-not $isLockContention -or $attempt -ge $maxAttempts) {
                if ($isLockContention -and $attempt -ge $maxAttempts) {
                    Move-Item -Path $tempPath -Destination $pendingPath -Force -ErrorAction Stop
                    $pendingBytes = (Get-Item -Path $pendingPath).Length
                    return [pscustomobject]@{
                        changed = $true
                        state_path = $Path
                        backup_path = $null
                        pending_repaired_path = $pendingPath
                        swap_pending = $true
                        repaired_lines = @($changes)
                        original_bytes = [int64]$originalBytes
                        repaired_bytes = [int64]$pendingBytes
                    }
                }
                if (Test-Path -Path $tempPath) {
                    Remove-Item -Path $tempPath -Force -ErrorAction SilentlyContinue
                }
                throw
            }

            Start-Sleep -Milliseconds ($baseDelayMs * $attempt)
        }
    }

    if (-not $replacementComplete) {
        if (Test-Path -Path $tempPath) {
            Remove-Item -Path $tempPath -Force -ErrorAction SilentlyContinue
        }
        throw "State repair did not complete for $Path"
    }

    $repairedBytes = (Get-Item -Path $Path).Length

    return [pscustomobject]@{
        changed = $true
        state_path = $Path
        backup_path = $backupPath
        pending_repaired_path = $null
        swap_pending = $false
        repaired_lines = @($changes)
        original_bytes = [int64]$originalBytes
        repaired_bytes = [int64]$repairedBytes
    }
}

function Compress-StateForOperationalUse {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)]$Config
    )

    $summary = [ordered]@{}
    $applyWindow = {
        param([string]$Name, $Items, [int]$Limit)

        $before = @($Items).Count
        $afterItems = if ($before -gt $Limit) { @($Items | Select-Object -Last $Limit) } else { @($Items) }
        $summary[$Name] = [pscustomobject]@{
            before = [int]$before
            after = [int]@($afterItems).Count
            limit = [int]$Limit
        }
        return ,$afterItems
    }

    $runHistoryLimit = Resolve-EngineeringLoopHistoryLimit -Config $Config -Kind "run_history"
    $scorecardHistoryLimit = Resolve-EngineeringLoopHistoryLimit -Config $Config -Kind "scorecard_history"
    $cycleRecordLimit = Resolve-EngineeringCycleRecordLimit -Config $Config

    $State.engineering_loop.run_history = @((& $applyWindow "engineering_loop.run_history" @($State.engineering_loop.run_history) $runHistoryLimit))
    $State.engineering_loop.scorecard_history = @((& $applyWindow "engineering_loop.scorecard_history" @($State.engineering_loop.scorecard_history) $scorecardHistoryLimit))
    $State.engineering_loop.cycle_records = @((& $applyWindow "engineering_loop.cycle_records" @($State.engineering_loop.cycle_records) $cycleRecordLimit))
    $State.engineering_loop.review_actions = @((& $applyWindow "engineering_loop.review_actions" @($State.engineering_loop.review_actions) 400))

    $State.routing_decisions.records = @((& $applyWindow "routing_decisions.records" @($State.routing_decisions.records) 1000))
    $State.engine_performance.records = @((& $applyWindow "engine_performance.records" @($State.engine_performance.records) 1000))
    $State.journal = @((& $applyWindow "journal" @($State.journal) 1000))
    $State.execution_results = @((& $applyWindow "execution_results" @($State.execution_results) 500))
    $State.review_decisions = @((& $applyWindow "review_decisions" @($State.review_decisions) 500))

    return [pscustomobject]$summary
}

function Limit-StateTextField {
    param(
        [AllowNull()][string]$Value,
        [int]$MaxLength = 8192,
        [string]$FieldName = "text"
    )

    if ([string]::IsNullOrEmpty($Value)) {
        return $Value
    }

    if ($Value.Length -le $MaxLength) {
        return $Value
    }

    $suffix = "...[truncated for operational state; field=$FieldName; original_length=$($Value.Length)]"
    $prefixLength = $MaxLength - $suffix.Length
    if ($prefixLength -lt 0) {
        $prefixLength = 0
    }

    return $Value.Substring(0, $prefixLength) + $suffix
}

function Limit-StateTextArray {
    param(
        $Values,
        [int]$MaxItemLength = 2048,
        [string]$FieldName = "text_array"
    )

    return @(
        Convert-ToStringArray -Value $Values | ForEach-Object {
            Limit-StateTextField -Value ([string]$_) -MaxLength $MaxItemLength -FieldName $FieldName
        }
    )
}

function Protect-StateForOperationalUse {
    param([Parameter(Mandatory = $true)]$State)

    if ($State.PSObject.Properties["objectives"] -and $null -ne $State.objectives) {
        foreach ($objective in @($State.objectives)) {
            if ($null -eq $objective) {
                continue
            }

            if ($objective.PSObject.Properties["title"] -and $null -ne $objective.title) {
                $objective.title = Limit-StateTextField -Value ([string]$objective.title) -MaxLength 512 -FieldName "objective.title"
            }
            if ($objective.PSObject.Properties["description"] -and $null -ne $objective.description) {
                $objective.description = Limit-StateTextField -Value ([string]$objective.description) -MaxLength 8192 -FieldName "objective.description"
            }
            if ($objective.PSObject.Properties["constraints"]) {
                $objective.constraints = Limit-StateTextArray -Values $objective.constraints -MaxItemLength 2048 -FieldName "objective.constraints[]"
            }
            if ($objective.PSObject.Properties["success_criteria"]) {
                $objective.success_criteria = Limit-StateTextArray -Values $objective.success_criteria -MaxItemLength 2048 -FieldName "objective.success_criteria[]"
            }
        }
    }

    if ($State.PSObject.Properties["tasks"] -and $null -ne $State.tasks) {
        foreach ($task in @($State.tasks)) {
            if ($null -eq $task) {
                continue
            }

            if ($task.PSObject.Properties["title"] -and $null -ne $task.title) {
                $task.title = Limit-StateTextField -Value ([string]$task.title) -MaxLength 512 -FieldName "task.title"
            }
            if ($task.PSObject.Properties["scope"] -and $null -ne $task.scope) {
                $task.scope = Limit-StateTextField -Value ([string]$task.scope) -MaxLength 8192 -FieldName "task.scope"
            }
            if ($task.PSObject.Properties["description"] -and $null -ne $task.description) {
                $task.description = Limit-StateTextField -Value ([string]$task.description) -MaxLength 8192 -FieldName "task.description"
            }
            if ($task.PSObject.Properties["acceptance_criteria"]) {
                $task.acceptance_criteria = Limit-StateTextArray -Values $task.acceptance_criteria -MaxItemLength 2048 -FieldName "task.acceptance_criteria[]"
            }
        }
    }
}

function Test-ActionRequiresState {
    param([Parameter(Mandatory = $true)][string]$ActionName)

    switch ($ActionName.ToLowerInvariant()) {
        "codex_handoff" { return $false }
        "get-capabilities" { return $false }
        "get-execution-readiness" { return $false }
        "get-intake-arbitration" { return $false }
        "get-version" { return $false }
        "ping-mim" { return $false }
        "repair-state" { return $false }
        "rewrite-state-history" { return $false }
        "run-bridge-request" { return $false }
        "safe_home" { return $false }
        "scan_pose" { return $false }
        "capture_frame" { return $false }
        "start-training-runbook" { return $false }
        default { return $true }
    }
}

function Start-TodTrainingRunbookProcess {
    param(
        [string]$ResolvedConfigPath
    )

    $runbookPath = Join-Path $PSScriptRoot "Invoke-TODTrainingRunbook6h.ps1"
    if (-not (Test-Path -Path $runbookPath)) {
        throw "Training runbook script not found: $runbookPath"
    }

    $powershellExe = Join-Path $PSHOME 'powershell.exe'
    if (-not (Test-Path -Path $powershellExe)) {
        $powershellExe = 'powershell.exe'
    }

    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $runbookPath, '-NoWait')
    if (-not [string]::IsNullOrWhiteSpace($ResolvedConfigPath)) {
        $arguments += @('-ConfigPath', $ResolvedConfigPath)
    }

    $process = Start-Process -FilePath $powershellExe -ArgumentList $arguments -PassThru -WindowStyle Hidden
    return [pscustomobject]@{
        ok = $true
        action = 'start-training-runbook'
        source = 'tod-start-training-runbook-v1'
        pid = [int]$process.Id
        runner = $powershellExe
        script_path = $runbookPath
        no_wait = $true
        launched_at = Get-UtcNow
        command_preview = [string](($arguments | ForEach-Object {
                    if ([string]$_ -match '\s') { '"' + [string]$_ + '"' } else { [string]$_ }
                }) -join ' ')
    }
}

function Start-TodChatTaskProcess {
    param(
        [Parameter(Mandatory = $true)][string]$TaskId,
        [Parameter(Mandatory = $true)][string]$PackagePath,
        [string]$ResolvedConfigPath,
        [string]$ResolvedStatePath
    )

    $todScriptPath = Join-Path $PSScriptRoot 'TOD.ps1'
    if (-not (Test-Path -Path $todScriptPath)) {
        throw "TOD action script not found: $todScriptPath"
    }

    $powershellExe = Join-Path $PSHOME 'powershell.exe'
    if (-not (Test-Path -Path $powershellExe)) {
        $powershellExe = 'powershell.exe'
    }

    $logRoot = Join-Path $repoRoot 'tod/out/background-chat'
    New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
    $stdoutPath = Join-Path $logRoot ($TaskId + '.stdout.log')
    $stderrPath = Join-Path $logRoot ($TaskId + '.stderr.log')

    $invocationPayload = [ordered]@{
        Action = 'run-task'
        TaskId = $TaskId
        PackagePath = $PackagePath
        SkipNextTaskSelectionLoop = 'true'
        SkipPostCompletionTail = 'true'
    }
    if (-not [string]::IsNullOrWhiteSpace($ResolvedConfigPath)) {
        $invocationPayload['ConfigPath'] = $ResolvedConfigPath
    }
    if (-not [string]::IsNullOrWhiteSpace($ResolvedStatePath)) {
        $invocationPayload['StatePath'] = $ResolvedStatePath
    }

    $parameterJson = $invocationPayload | ConvertTo-Json -Compress -Depth 10
    $parameterJsonBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($parameterJson))
    $safeConfigPath = if ([string]::IsNullOrWhiteSpace($ResolvedConfigPath)) { '' } else { [string]$ResolvedConfigPath }
    $safeStatePath = if ([string]::IsNullOrWhiteSpace($ResolvedStatePath)) { '' } else { [string]$ResolvedStatePath }
    $encodedCommand = @"
`$ProgressPreference = 'SilentlyContinue'
`$ErrorActionPreference = 'Stop'
Set-Location -Path '$repoRoot'
`$parameterJson = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('$parameterJsonBase64'))
`$parameterObject = `$parameterJson | ConvertFrom-Json
`$invokeParams = @{}
`$parsedSwitch = `$false
foreach (`$property in `$parameterObject.PSObject.Properties) {
    if ([string]::Equals([string]`$property.Name, 'SkipNextTaskSelectionLoop', [System.StringComparison]::OrdinalIgnoreCase) -or [string]::Equals([string]`$property.Name, 'SkipPostCompletionTail', [System.StringComparison]::OrdinalIgnoreCase)) {
        if ([bool]::TryParse([string]`$property.Value, [ref]`$parsedSwitch) -and `$parsedSwitch) {
            `$invokeParams[`$property.Name] = `$true
        }
        continue
    }
    `$invokeParams[`$property.Name] = [string]`$property.Value
}
try {
    if ([string]::Equals([string]`$env:TOD_FORCE_ASYNC_CHAT_WORKER_FAILURE, '1', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Forced async chat worker failure for test.'
    }

    & '$todScriptPath' @invokeParams
}
catch {
    `$detailPayload = [ordered]@{
        error = [string]`$_.Exception.Message
        package_path = '$PackagePath'
        worker_runner = '$powershellExe'
        worker_script_path = '$todScriptPath'
        working_directory = '$repoRoot'
        stdout_path = '$stdoutPath'
        stderr_path = '$stderrPath'
    }
    if (-not [string]::IsNullOrWhiteSpace('$safeStatePath')) {
        & '$todScriptPath' -Action 'persist-task-terminal-state' -TaskId '$TaskId' -StatePath '$safeStatePath' -ConfigPath '$safeConfigPath' -Type 'blocked' -Summary 'Async chat worker failed before TOD could persist a terminal result.' -Description (([pscustomobject]`$detailPayload) | ConvertTo-Json -Compress -Depth 10) -AssignedExecutor 'worker_startup_failure' | Out-Null
    }
    throw
}
"@

    $arguments = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-EncodedCommand', [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($encodedCommand))
    )

    $process = Start-Process -FilePath $powershellExe -ArgumentList $arguments -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -WorkingDirectory $repoRoot
    return [pscustomobject]@{
        ok = $true
        pid = [int]$process.Id
        runner = $powershellExe
        script_path = $todScriptPath
        working_directory = $repoRoot
        stdout_path = $stdoutPath
        stderr_path = $stderrPath
        launched_at = Get-UtcNow
        command_preview = [string](($arguments | ForEach-Object {
                    if ([string]$_ -match '\s') { '"' + [string]$_ + '"' } else { [string]$_ }
                }) -join ' ')
    }
}

function Convert-ToStringArray {
    param($Value)

    if ($null -eq $Value) {
        return ,([string[]]@())
    }

    if ($Value -is [string]) {
        if ([string]::IsNullOrWhiteSpace($Value)) {
            return ,([string[]]@())
        }
        return ,([string[]]@($Value))
    }

    $items = @($Value | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    return ,([string[]]$items)
}

function Normalize-State {
    param([Parameter(Mandatory = $true)]$State)

    if (-not $State.PSObject.Properties["sync_state"]) {
        $State | Add-Member -NotePropertyName sync_state -NotePropertyValue ([pscustomobject]@{
                expected_contract_version = ""
                expected_schema_version = ""
                local_repo_signature = ""
                cached_manifest = $null
                last_comparison = $null
                last_sync_decision = ""
                last_sync_code = ""
                compared_at = ""
            }) -Force
    }
    if (-not $State.sync_state.PSObject.Properties["last_sync_decision"]) {
        $State.sync_state | Add-Member -NotePropertyName last_sync_decision -NotePropertyValue "" -Force
    }
    if (-not $State.sync_state.PSObject.Properties["last_sync_code"]) {
        $State.sync_state | Add-Member -NotePropertyName last_sync_code -NotePropertyValue "" -Force
    }

    if (-not $State.PSObject.Properties["engine_performance"]) {
        $State | Add-Member -NotePropertyName engine_performance -NotePropertyValue ([pscustomobject]@{
                records = @()
                updated_at = ""
            }) -Force
    }
    if (-not $State.engine_performance.PSObject.Properties["records"]) {
        $State.engine_performance | Add-Member -NotePropertyName records -NotePropertyValue @() -Force
    }
    if (-not $State.engine_performance.PSObject.Properties["updated_at"]) {
        $State.engine_performance | Add-Member -NotePropertyName updated_at -NotePropertyValue "" -Force
    }

    if (-not $State.PSObject.Properties["routing_decisions"]) {
        $State | Add-Member -NotePropertyName routing_decisions -NotePropertyValue ([pscustomobject]@{
                records = @()
                updated_at = ""
            }) -Force
    }
    if (-not $State.routing_decisions.PSObject.Properties["records"]) {
        $State.routing_decisions | Add-Member -NotePropertyName records -NotePropertyValue @() -Force
    }
    if (-not $State.routing_decisions.PSObject.Properties["updated_at"]) {
        $State.routing_decisions | Add-Member -NotePropertyName updated_at -NotePropertyValue "" -Force
    }

    if (-not $State.PSObject.Properties["routing_feedback"]) {
        $State | Add-Member -NotePropertyName routing_feedback -NotePropertyValue ([pscustomobject]@{
                learned_weights = (Get-DefaultRoutingWeights)
                sample_size = 0
                version = "feedback_v1"
                updated_at = ""
            }) -Force
    }
    if (-not $State.routing_feedback.PSObject.Properties["learned_weights"] -or $null -eq $State.routing_feedback.learned_weights) {
        $State.routing_feedback | Add-Member -NotePropertyName learned_weights -NotePropertyValue (Get-DefaultRoutingWeights) -Force
    }
    else {
        $State.routing_feedback.learned_weights = Normalize-RoutingWeights -Weights $State.routing_feedback.learned_weights
    }
    if (-not $State.routing_feedback.PSObject.Properties["sample_size"] -or $null -eq $State.routing_feedback.sample_size) {
        $State.routing_feedback | Add-Member -NotePropertyName sample_size -NotePropertyValue 0 -Force
    }
    if (-not $State.routing_feedback.PSObject.Properties["version"] -or [string]::IsNullOrWhiteSpace([string]$State.routing_feedback.version)) {
        $State.routing_feedback | Add-Member -NotePropertyName version -NotePropertyValue "feedback_v1" -Force
    }
    if (-not $State.routing_feedback.PSObject.Properties["updated_at"]) {
        $State.routing_feedback | Add-Member -NotePropertyName updated_at -NotePropertyValue "" -Force
    }

    if (-not $State.PSObject.Properties["engineering_loop"]) {
        $State | Add-Member -NotePropertyName engineering_loop -NotePropertyValue ([pscustomobject]@{
                run_history = @()
                scorecard_history = @()
                cycle_records = @()
                review_actions = @()
                last_run = $null
                last_scorecard = $null
                last_cycle = $null
                pending_approval_count = 0
                updated_at = ""
            }) -Force
    }
    if (-not $State.engineering_loop.PSObject.Properties["run_history"]) {
        $State.engineering_loop | Add-Member -NotePropertyName run_history -NotePropertyValue @() -Force
    }
    if (-not $State.engineering_loop.PSObject.Properties["scorecard_history"]) {
        $State.engineering_loop | Add-Member -NotePropertyName scorecard_history -NotePropertyValue @() -Force
    }
    if (-not $State.engineering_loop.PSObject.Properties["cycle_records"]) {
        $State.engineering_loop | Add-Member -NotePropertyName cycle_records -NotePropertyValue @() -Force
    }
    if (-not $State.engineering_loop.PSObject.Properties["review_actions"]) {
        $State.engineering_loop | Add-Member -NotePropertyName review_actions -NotePropertyValue @() -Force
    }
    if (-not $State.engineering_loop.PSObject.Properties["last_run"]) {
        $State.engineering_loop | Add-Member -NotePropertyName last_run -NotePropertyValue $null -Force
    }
    if (-not $State.engineering_loop.PSObject.Properties["last_scorecard"]) {
        $State.engineering_loop | Add-Member -NotePropertyName last_scorecard -NotePropertyValue $null -Force
    }
    if (-not $State.engineering_loop.PSObject.Properties["last_cycle"]) {
        $State.engineering_loop | Add-Member -NotePropertyName last_cycle -NotePropertyValue $null -Force
    }
    if (-not $State.engineering_loop.PSObject.Properties["pending_approval_count"]) {
        $State.engineering_loop | Add-Member -NotePropertyName pending_approval_count -NotePropertyValue 0 -Force
    }
    if (-not $State.engineering_loop.PSObject.Properties["updated_at"]) {
        $State.engineering_loop | Add-Member -NotePropertyName updated_at -NotePropertyValue "" -Force
    }

    foreach ($objective in @($State.objectives)) {
        $objective.constraints = Convert-ToStringArray -Value $objective.constraints
        $objective.success_criteria = Convert-ToStringArray -Value $objective.success_criteria
    }

    foreach ($task in @($State.tasks)) {
        $task.dependencies = Convert-ToStringArray -Value $task.dependencies
        $task.acceptance_criteria = Convert-ToStringArray -Value $task.acceptance_criteria
        if ($task.PSObject.Properties["title"] -and $null -ne $task.title) {
            $task.title = Limit-StateTextField -Value ([string]$task.title) -MaxLength 512 -FieldName "task.title"
        }
        if ($task.PSObject.Properties["scope"] -and $null -ne $task.scope) {
            $task.scope = Limit-StateTextField -Value ([string]$task.scope) -MaxLength 8192 -FieldName "task.scope"
        }
        if ($task.PSObject.Properties["description"] -and $null -ne $task.description) {
            $task.description = Limit-StateTextField -Value ([string]$task.description) -MaxLength 8192 -FieldName "task.description"
        }
        $task.acceptance_criteria = Limit-StateTextArray -Values $task.acceptance_criteria -MaxItemLength 2048 -FieldName "task.acceptance_criteria[]"
        if (-not $task.PSObject.Properties["task_category"] -or [string]::IsNullOrWhiteSpace([string]$task.task_category)) {
            $task | Add-Member -NotePropertyName task_category -NotePropertyValue "code_change" -Force
        }
        if (-not $task.PSObject.Properties["updated_at"]) {
            $task | Add-Member -NotePropertyName updated_at -NotePropertyValue "" -Force
        }
    }

    $normalizedExecutionResults = @()
    foreach ($result in @($State.execution_results)) {
        if ($null -eq $result) {
            continue
        }
        if (-not $result.PSObject.Properties["task_id"]) {
            $result | Add-Member -NotePropertyName task_id -NotePropertyValue "" -Force
        }
        if (-not $result.PSObject.Properties["files_changed"]) {
            $result | Add-Member -NotePropertyName files_changed -NotePropertyValue @() -Force
        }
        if (-not $result.PSObject.Properties["tests_run"]) {
            $result | Add-Member -NotePropertyName tests_run -NotePropertyValue @() -Force
        }
        if (-not $result.PSObject.Properties["test_results"]) {
            $result | Add-Member -NotePropertyName test_results -NotePropertyValue @() -Force
        }
        if (-not $result.PSObject.Properties["failures"]) {
            $result | Add-Member -NotePropertyName failures -NotePropertyValue @() -Force
        }
        if (-not $result.PSObject.Properties["recommendations"]) {
            $result | Add-Member -NotePropertyName recommendations -NotePropertyValue @() -Force
        }
        $result.files_changed = Convert-ToStringArray -Value $result.files_changed
        $result.tests_run = Convert-ToStringArray -Value $result.tests_run
        $result.test_results = Convert-ToStringArray -Value $result.test_results
        $result.failures = Convert-ToStringArray -Value $result.failures
        $result.recommendations = Convert-ToStringArray -Value $result.recommendations
        $normalizedExecutionResults += $result
    }
    $State.execution_results = @($normalizedExecutionResults)

    $normalizedReviewDecisions = @()
    foreach ($review in @($State.review_decisions)) {
        if ($null -eq $review) {
            continue
        }
        if (-not $review.PSObject.Properties["task_id"]) {
            $review | Add-Member -NotePropertyName task_id -NotePropertyValue "" -Force
        }
        if (-not $review.PSObject.Properties["unresolved_issues"]) {
            $review | Add-Member -NotePropertyName unresolved_issues -NotePropertyValue @() -Force
        }
        $review.unresolved_issues = Convert-ToStringArray -Value $review.unresolved_issues
        $normalizedReviewDecisions += $review
    }
    $State.review_decisions = @($normalizedReviewDecisions)
}

function New-Id {
    param(
        [Parameter(Mandatory = $true)][string]$Prefix,
        [Parameter(Mandatory = $true)][int]$Count
    )

    return "{0}-{1}" -f $Prefix, (($Count + 1).ToString("0000"))
}

function Add-Journal {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][string]$Actor,
        [Parameter(Mandatory = $true)][string]$ActionName,
        [Parameter(Mandatory = $true)][string]$EntityType,
        [Parameter(Mandatory = $true)][string]$EntityId,
        [Parameter(Mandatory = $true)]$Payload
    )

    $entryId = New-Id -Prefix "JRNL" -Count $State.journal.Count
    $entry = [pscustomobject]@{
        id = $entryId
        actor = $Actor
        action = $ActionName
        entity_type = $EntityType
        entity_id = $EntityId
        payload = $Payload
        created_at = Get-UtcNow
    }
    $State.journal += $entry
}

function Add-EnginePerformanceRecord {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][string]$TaskId,
        [Parameter(Mandatory = $true)]$InvokeResult,
        [Parameter(Mandatory = $true)][string]$ReviewDecision,
        [Parameter(Mandatory = $true)][string]$TaskType,
        [Parameter(Mandatory = $true)][string]$TaskCategory,
        [string[]]$FilesInvolved = @()
    )

    $engineName = [string]$InvokeResult.active_engine
    $attemptedEngines = @($InvokeResult.attempted_engines)
    $attemptDetails = if ($InvokeResult.PSObject.Properties["attempts"] -and $null -ne $InvokeResult.attempts) { @($InvokeResult.attempts) } else { @() }
    $attemptCount = if (@($attemptDetails).Count -gt 0) { [int]@($attemptDetails).Count } else { [int]@($attemptedEngines).Count }
    $uniqueEngineCount = [int]@($attemptedEngines | Select-Object -Unique).Count
    $wrapperOnlyEngines = @($attemptDetails | ForEach-Object {
            $attempt = $_
            if ($null -eq $attempt) { return $null }

            $attemptReason = ''
            if ($attempt.PSObject.Properties['result'] -and $attempt.result -and $attempt.result.PSObject.Properties['reason_code']) {
                $attemptReason = [string]$attempt.result.reason_code
            }
            elseif ($attempt.PSObject.Properties['reason_code']) {
                $attemptReason = [string]$attempt.reason_code
            }

            if ([string]::Equals($attemptReason, 'codex_wrapper_only_no_execution', [System.StringComparison]::OrdinalIgnoreCase)) {
                if ($attempt.PSObject.Properties['engine']) {
                    return ([string]$attempt.engine).ToLowerInvariant()
                }
                if ($attempt.PSObject.Properties['engine_name']) {
                    return ([string]$attempt.engine_name).ToLowerInvariant()
                }
                return 'codex'
            }

            return $null
        } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    $hadRetry = ($attemptCount -gt $uniqueEngineCount)
    $isSuccess = ([string]$ReviewDecision -eq "pass")
    $recoveredOnFallback = ([bool]$InvokeResult.fallback_applied -and $isSuccess)
    $recoveredOnRetry = ($hadRetry -and -not [bool]$InvokeResult.fallback_applied -and $isSuccess)
    $unrecoveredFailure = (([string]$ReviewDecision -eq "escalate") -or [bool]$InvokeResult.result.needs_escalation)
    $degradedSuccess = ($isSuccess -and ($recoveredOnFallback -or $recoveredOnRetry))
    $manualInterventionRequired = (-not $isSuccess)

    $record = [pscustomobject]@{
        id = "ENGPERF-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 8).ToUpperInvariant())
        task_id = [string]$TaskId
        engine = $engineName
        task_type = $TaskType
        task_category = $TaskCategory
        fallback_applied = [bool]$InvokeResult.fallback_applied
        attempted_engines = @($attemptedEngines)
        attempts_count = $attemptCount
        retry_inflated = $hadRetry
        result_status = [string]$InvokeResult.result.status
        needs_escalation = [bool]$InvokeResult.result.needs_escalation
        failure_category = if ($InvokeResult.PSObject.Properties["failure_category"] -and -not [string]::IsNullOrWhiteSpace([string]$InvokeResult.failure_category)) { [string]$InvokeResult.failure_category } else { "none" }
        review_decision = [string]$ReviewDecision
        success = $isSuccess
        recovered_on_retry = $recoveredOnRetry
        recovered_on_fallback = $recoveredOnFallback
        unrecovered_failure = $unrecoveredFailure
        degraded_success = $degradedSuccess
        manual_intervention_required = $manualInterventionRequired
        review_score = $(switch ([string]$ReviewDecision) { "pass" { 1.0 } "revise" { 0.5 } "escalate" { 0.0 } default { 0.0 } })
        latency_ms = if ($InvokeResult.PSObject.Properties["elapsed_ms"] -and $null -ne $InvokeResult.elapsed_ms) { [double]$InvokeResult.elapsed_ms } else { $null }
        files_involved = @($FilesInvolved | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        modules_involved = @(@($FilesInvolved | ForEach-Object { [string]$_ } | Where-Object { $_ } | ForEach-Object { (([string]$_ -replace '[\\/]+', '/').Split('/')[0]) } | Where-Object { $_ } | Select-Object -Unique))
        wrapper_only_engines = @($wrapperOnlyEngines)
        wrapper_only_codex_seen = (@($wrapperOnlyEngines | Where-Object { $_ -eq 'codex' }).Count -gt 0)
        created_at = Get-UtcNow
    }

    $State.engine_performance.records += $record
    $State.engine_performance.updated_at = Get-UtcNow
    Update-RoutingFeedbackModel -State $State
    Sync-EnginePerformanceToEngineeringMemory -State $State -LatestRecord $record
    return $record
}

function Add-EngineeringRunHistoryRecord {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)]$Payload,
        [int]$MaxEntries = 150
    )

    $focus = if ($Payload.PSObject.Properties["focus"]) { $Payload.focus } else { $null }
    $phases = if ($Payload.PSObject.Properties["phases"]) { $Payload.phases } else { $null }
    $plan = if ($phases -and $phases.PSObject.Properties["plan"]) { $phases.plan } else { $null }
    $implement = if ($phases -and $phases.PSObject.Properties["implement"]) { $phases.implement } else { $null }

    $entry = [pscustomobject]@{
        run_id = if ($Payload.PSObject.Properties["run_id"]) { [string]$Payload.run_id } else { "" }
        generated_at = if ($Payload.PSObject.Properties["generated_at"]) { [string]$Payload.generated_at } else { Get-UtcNow }
        objective_id = if ($focus -and $focus.PSObject.Properties["objective_id"]) { [string]$focus.objective_id } else { "" }
        task_id = if ($focus -and $focus.PSObject.Properties["task_id"]) { [string]$focus.task_id } else { "" }
        task_category = if ($focus -and $focus.PSObject.Properties["task_category"]) { [string]$focus.task_category } else { "" }
        plan_artifact_path = if ($plan -and $plan.PSObject.Properties["artifact_path"]) { [string]$plan.artifact_path } else { "" }
        sandbox_path = if ($plan -and $plan.PSObject.Properties["sandbox_path"]) { [string]$plan.sandbox_path } else { "" }
        implement_status = if ($implement -and $implement.PSObject.Properties["status"]) { [string]$implement.status } else { "" }
        apply_requested = if ($implement -and $implement.PSObject.Properties["apply_requested"]) { [bool]$implement.apply_requested } else { $false }
        source = if ($Payload.PSObject.Properties["source"]) { [string]$Payload.source } else { "" }
    }

    $history = @($State.engineering_loop.run_history)
    if (@($history).Count -eq 0) {
        $storedHistory = Read-EngineeringLoopHistoryStore -State $State
        $history = @($storedHistory.run_history)
    }
    $history += $entry
    if (@($history).Count -gt $MaxEntries) {
        $history = @($history | Select-Object -Last $MaxEntries)
    }

    $State.engineering_loop.run_history = @($history)
    $State.engineering_loop.last_run = $entry
    $State.engineering_loop.updated_at = Get-UtcNow
    return $entry
}

function Add-EngineeringScorecardHistoryRecord {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)]$Payload,
        [int]$MaxEntries = 150
    )

    $overall = if ($Payload.PSObject.Properties["overall"]) { $Payload.overall } else { $null }

    $entry = [pscustomobject]@{
        generated_at = if ($Payload.PSObject.Properties["generated_at"]) { [string]$Payload.generated_at } else { Get-UtcNow }
        window = if ($Payload.PSObject.Properties["window"] -and $null -ne $Payload.window) { [int]$Payload.window } else { 0 }
        score = if ($overall -and $overall.PSObject.Properties["score"] -and $null -ne $overall.score) { [double]$overall.score } else { 0.0 }
        band = if ($overall -and $overall.PSObject.Properties["band"]) { [string]$overall.band } else { "" }
        low_areas = if ($overall -and $overall.PSObject.Properties["low_areas"]) { @($overall.low_areas) } else { @() }
        dimensions = if ($Payload.PSObject.Properties["dimensions"]) { @($Payload.dimensions | ForEach-Object { [pscustomobject]@{ name = [string]$_.name; score = [double]$_.score } }) } else { @() }
        penalties = if ($Payload.PSObject.Properties["explainability"] -and $Payload.explainability -and $Payload.explainability.PSObject.Properties["penalties"]) { @($Payload.explainability.penalties) } else { @() }
    }

    $history = @($State.engineering_loop.scorecard_history)
    if (@($history).Count -eq 0) {
        $storedHistory = Read-EngineeringLoopHistoryStore -State $State
        $history = @($storedHistory.scorecard_history)
    }
    $history += $entry
    if (@($history).Count -gt $MaxEntries) {
        $history = @($history | Select-Object -Last $MaxEntries)
    }

    $State.engineering_loop.scorecard_history = @($history)
    $State.engineering_loop.last_scorecard = $entry
    $State.engineering_loop.updated_at = Get-UtcNow
    return $entry
}

function Add-EngineeringCycleRecord {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)]$CycleRecord,
        [int]$MaxEntries = 300
    )

    $history = @($State.engineering_loop.cycle_records)
    if (@($history).Count -eq 0) {
        $storedHistory = Read-EngineeringLoopHistoryStore -State $State
        $history = @($storedHistory.cycle_records)
    }
    $history += $CycleRecord
    if (@($history).Count -gt $MaxEntries) {
        $history = @($history | Select-Object -Last $MaxEntries)
    }

    $State.engineering_loop.cycle_records = @($history)
    $State.engineering_loop.last_cycle = $CycleRecord
    $pending = @($history | Where-Object {
            $null -ne $_ -and
            $_.PSObject.Properties["approval_status"] -and
            ([string]$_.approval_status).ToLowerInvariant() -eq "pending_apply"
        }).Count
    $State.engineering_loop.pending_approval_count = [int]$pending
    $State.engineering_loop.updated_at = Get-UtcNow
    return $CycleRecord
}

function Add-EngineeringReviewActionRecord {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)]$ReviewAction,
        [int]$MaxEntries = 400
    )

    $history = @($State.engineering_loop.review_actions)
    if (@($history).Count -eq 0) {
        $storedHistory = Read-EngineeringLoopHistoryStore -State $State
        $history = @($storedHistory.review_actions)
    }
    $history += $ReviewAction
    if (@($history).Count -gt $MaxEntries) {
        $history = @($history | Select-Object -Last $MaxEntries)
    }

    $State.engineering_loop.review_actions = @($history)
    $State.engineering_loop.updated_at = Get-UtcNow
    return $ReviewAction
}

function Resolve-EngineeringCycleRecordLimit {
    param([Parameter(Mandatory = $true)]$Config)

    $defaultLimit = 300
    if (-not $Config -or -not $Config.PSObject.Properties["engineering_loop"] -or $null -eq $Config.engineering_loop) {
        return $defaultLimit
    }

    if ($Config.engineering_loop.PSObject.Properties["max_cycle_records"] -and $null -ne $Config.engineering_loop.max_cycle_records) {
        $value = [int]$Config.engineering_loop.max_cycle_records
        if ($value -lt 25) { return 25 }
        if ($value -gt 2000) { return 2000 }
        return $value
    }

    return $defaultLimit
}

function Resolve-EngineeringLoopHistoryLimit {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [ValidateSet("run_history", "scorecard_history")][string]$Kind
    )

    $defaultLimit = 150
    if (-not $Config -or -not $Config.PSObject.Properties["engineering_loop"] -or $null -eq $Config.engineering_loop) {
        return $defaultLimit
    }

    $limits = $Config.engineering_loop
    $value = $null
    if ($Kind -eq "run_history") {
        if ($limits.PSObject.Properties["max_run_history"] -and $null -ne $limits.max_run_history) {
            $value = [int]$limits.max_run_history
        }
    }
    else {
        if ($limits.PSObject.Properties["max_scorecard_history"] -and $null -ne $limits.max_scorecard_history) {
            $value = [int]$limits.max_scorecard_history
        }
    }

    if ($null -eq $value -or $value -lt 10) {
        return $defaultLimit
    }
    if ($value -gt 1000) {
        return 1000
    }
    return $value
}

function Assert-DangerousActionApproved {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][string]$ActionName,
        [bool]$DangerousApproved = $false
    )

    $policy = $null
    if ($Config -and $Config.PSObject.Properties["engineering_loop"] -and $Config.engineering_loop -and $Config.engineering_loop.PSObject.Properties["guardrails"]) {
        $policy = $Config.engineering_loop.guardrails
    }

    $requireApply = $true
    $requireWrite = $false
    if ($policy) {
        if ($policy.PSObject.Properties["require_confirmation_for_apply"] -and $null -ne $policy.require_confirmation_for_apply) {
            $requireApply = [bool]$policy.require_confirmation_for_apply
        }
        if ($policy.PSObject.Properties["require_confirmation_for_write"] -and $null -ne $policy.require_confirmation_for_write) {
            $requireWrite = [bool]$policy.require_confirmation_for_write
        }
    }

    $action = ([string]$ActionName).ToLowerInvariant()
    if ($action -eq "sandbox-apply-plan" -and $requireApply -and -not $DangerousApproved) {
        throw "Action blocked by guardrail: sandbox-apply-plan requires explicit approval. Re-run with -DangerousApproved `$true."
    }
    if ($action -eq "sandbox-write" -and $requireWrite -and -not $DangerousApproved) {
        throw "Action blocked by guardrail: sandbox-write requires explicit approval. Re-run with -DangerousApproved `$true."
    }
}

function Convert-ToPagedEngineeringHistory {
    param(
        [AllowNull()]$Items = @(),
        [int]$Page = 1,
        [int]$PageSize = 25
    )

    $safePage = if ($Page -lt 1) { 1 } else { $Page }
    $safeSize = if ($PageSize -lt 1) { 1 } elseif ($PageSize -gt 200) { 200 } else { $PageSize }
    $all = @($Items)
    $total = @($all).Count
    $totalPages = if ($total -le 0) { 0 } else { [math]::Ceiling(([double]$total / [double]$safeSize)) }
    $offset = ($safePage - 1) * $safeSize
    if ($offset -ge $total) {
        return [pscustomobject]@{
            page = [int]$safePage
            page_size = [int]$safeSize
            total = [int]$total
            total_pages = [int]$totalPages
            has_more = $false
            items = @()
        }
    }

    $slice = @($all | Select-Object -Skip $offset -First $safeSize)
    return [pscustomobject]@{
        page = [int]$safePage
        page_size = [int]$safeSize
        total = [int]$total
        total_pages = [int]$totalPages
        has_more = (($offset + @($slice).Count) -lt $total)
        items = @($slice)
    }
}

function Get-PendingApprovalRuntimeSummary {
    param(
        [Parameter(Mandatory = $true)]$State,
        [int]$StaleHours = 72
    )

    $historyStore = Read-EngineeringLoopHistoryStore -State $State -PreferState
    $records = @($historyStore.cycle_records)

    $pending = @($records | Where-Object {
            $null -ne $_ -and ((
                $_.PSObject.Properties["approval_pending"] -and [bool]$_.approval_pending
            ) -or (
                $_.PSObject.Properties["approval_status"] -and ([string]$_.approval_status).ToLowerInvariant() -eq "pending_apply"
            ))
        })

    $now = (Get-Date).ToUniversalTime()
    $byType = [ordered]@{}
    $byAge = [ordered]@{
        lt_24h = 0
        h24_to_h72 = 0
        gt_72h = 0
        unknown = 0
    }
    $bySource = [ordered]@{}

    $stale = @()
    $lowValue = @()
    $promotable = @()

    foreach ($item in $pending) {
        $status = if ($item.PSObject.Properties["approval_status"] -and -not [string]::IsNullOrWhiteSpace([string]$item.approval_status)) {
            ([string]$item.approval_status).ToLowerInvariant()
        }
        else {
            "pending_apply"
        }
        if (-not $byType.Contains($status)) {
            $byType[$status] = 0
        }
        $byType[$status] = [int]$byType[$status] + 1

        $source = if ($item.PSObject.Properties["objective_id"] -and -not [string]::IsNullOrWhiteSpace([string]$item.objective_id)) {
            "objective:{0}" -f [string]$item.objective_id
        }
        elseif ($item.PSObject.Properties["task_category"] -and -not [string]::IsNullOrWhiteSpace([string]$item.task_category)) {
            "task_category:{0}" -f [string]$item.task_category
        }
        else {
            "engineering_loop"
        }
        if (-not $bySource.Contains($source)) {
            $bySource[$source] = 0
        }
        $bySource[$source] = [int]$bySource[$source] + 1

        $createdAt = $null
        if ($item.PSObject.Properties["created_at"] -and -not [string]::IsNullOrWhiteSpace([string]$item.created_at)) {
            try { $createdAt = ([datetime]$item.created_at).ToUniversalTime() } catch { $createdAt = $null }
        }
        $updatedAt = $null
        if ($item.PSObject.Properties["updated_at"] -and -not [string]::IsNullOrWhiteSpace([string]$item.updated_at)) {
            try { $updatedAt = ([datetime]$item.updated_at).ToUniversalTime() } catch { $updatedAt = $null }
        }
        $anchor = if ($null -ne $createdAt) { $createdAt } else { $updatedAt }

        $ageHours = $null
        if ($null -eq $anchor) {
            $byAge["unknown"] = [int]$byAge["unknown"] + 1
        }
        else {
            $ageHours = [math]::Round(($now - $anchor).TotalHours, 2)
            if ($ageHours -lt 24) {
                $byAge["lt_24h"] = [int]$byAge["lt_24h"] + 1
            }
            elseif ($ageHours -le 72) {
                $byAge["h24_to_h72"] = [int]$byAge["h24_to_h72"] + 1
            }
            else {
                $byAge["gt_72h"] = [int]$byAge["gt_72h"] + 1
            }
        }

        $score = $null
        if ($item.PSObject.Properties["score_snapshot"] -and $item.score_snapshot -and $item.score_snapshot.PSObject.Properties["overall"] -and $item.score_snapshot.overall.PSObject.Properties["score"] -and $null -ne $item.score_snapshot.overall.score) {
            $score = [double]$item.score_snapshot.overall.score
        }
        $band = if ($item.PSObject.Properties["maturity_band"]) { ([string]$item.maturity_band).ToLowerInvariant() } else { "" }

        $itemId = if ($item.PSObject.Properties["cycle_id"] -and -not [string]::IsNullOrWhiteSpace([string]$item.cycle_id)) {
            [string]$item.cycle_id
        }
        elseif ($item.PSObject.Properties["run_id"] -and -not [string]::IsNullOrWhiteSpace([string]$item.run_id)) {
            [string]$item.run_id
        }
        else {
            "unknown"
        }

        if ($null -ne $ageHours -and $ageHours -ge $StaleHours) {
            $stale += @($itemId)
        }
        if ($band -in @("good", "strong") -and $null -ne $score -and $score -ge 0.65) {
            $promotable += @($itemId)
        }
        if ($band -in @("emerging", "early") -or ($null -ne $score -and $score -lt 0.45)) {
            $lowValue += @($itemId)
        }
    }

    return [pscustomobject]@{
        pending_approvals_total = [int]@($pending).Count
        pending_approvals_by_type = [pscustomobject]$byType
        pending_approvals_by_age = [pscustomobject]$byAge
        pending_approvals_by_source = [pscustomobject]$bySource
        pending_approvals_stale_count = [int]@($stale).Count
        pending_approvals_low_value_count = [int]@($lowValue).Count
        pending_approvals_promotable_count = [int]@($promotable).Count
        top_promotable_ids = @($promotable | Select-Object -First 10)
        top_low_value_ids = @($lowValue | Select-Object -First 10)
    }
}

function Get-TodEngineeringLoopSummaryPayload {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)]$Config,
        [int]$Top = 10
    )

    $bus = Get-TodStateBusPayload -Config $Config -State $State -Top $Top
    $loop = if ($bus.PSObject.Properties["engineering_loop_state"]) { $bus.engineering_loop_state } else { [pscustomobject]@{} }
    $approvalSummary = Get-PendingApprovalRuntimeSummary -State $State

    return [pscustomobject]@{
        path = "/tod/engineer/summary"
        service = "tod"
        source = "engineering_loop_summary_v2"
        generated_at = Get-UtcNow
        status = if ($loop.PSObject.Properties["status"]) { [string]$loop.status } else { "idle" }
        latest_score = if ($loop.PSObject.Properties["latest_score"]) { $loop.latest_score } else { $null }
        trend_direction = if ($loop.PSObject.Properties["trend_direction"]) { [string]$loop.trend_direction } else { "flat" }
        trend_delta = if ($loop.PSObject.Properties["trend_delta"]) { [double]$loop.trend_delta } else { 0.0 }
        run_history_count = if ($loop.PSObject.Properties["run_history_count"]) { [int]$loop.run_history_count } else { 0 }
        scorecard_history_count = if ($loop.PSObject.Properties["scorecard_history_count"]) { [int]$loop.scorecard_history_count } else { 0 }
        last_run = if ($loop.PSObject.Properties["last_run"]) { $loop.last_run } else { $null }
        last_scorecard = if ($loop.PSObject.Properties["last_scorecard"]) { $loop.last_scorecard } else { $null }
        confidence = if ($bus.PSObject.Properties["section_confidence"] -and $bus.section_confidence.PSObject.Properties["engineering_loop"]) { [double]$bus.section_confidence.engineering_loop } else { 0.0 }
        pending_approvals_total = [int]$approvalSummary.pending_approvals_total
        pending_approvals_low_value = [int]$approvalSummary.pending_approvals_low_value_count
        pending_approvals_promotable = [int]$approvalSummary.pending_approvals_promotable_count
        pending_approvals_stale = [int]$approvalSummary.pending_approvals_stale_count
        approval_source_distribution = $approvalSummary.pending_approvals_by_source
        approval_age_distribution = $approvalSummary.pending_approvals_by_age
        pending_approvals_by_type = $approvalSummary.pending_approvals_by_type
        pending_approvals_by_age = $approvalSummary.pending_approvals_by_age
        pending_approvals_by_source = $approvalSummary.pending_approvals_by_source
        pending_approvals_stale_count = [int]$approvalSummary.pending_approvals_stale_count
        pending_approvals_low_value_count = [int]$approvalSummary.pending_approvals_low_value_count
        pending_approvals_promotable_count = [int]$approvalSummary.pending_approvals_promotable_count
        top_promotable_ids = @($approvalSummary.top_promotable_ids)
        top_low_value_ids = @($approvalSummary.top_low_value_ids)
    }
}

function Get-TodEngineeringSignalPayload {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)]$Config,
        [int]$Top = 10
    )

    $bus = Get-TodStateBusPayload -Config $Config -State $State -Top $Top
    $loop = if ($bus.PSObject.Properties["engineering_loop_state"]) { $bus.engineering_loop_state } else { [pscustomobject]@{} }

    $lastCycle = if ($loop.PSObject.Properties["last_cycle_result"]) { $loop.last_cycle_result } else { $null }
    $stopReason = if ($lastCycle -and $lastCycle.PSObject.Properties["stop_reason"] -and -not [string]::IsNullOrWhiteSpace([string]$lastCycle.stop_reason)) {
        [string]$lastCycle.stop_reason
    }
    else {
        ""
    }

    $phaseSnapshot = [ordered]@{}
    $phaseTrends = if ($loop.PSObject.Properties["phase_trends"] -and $null -ne $loop.phase_trends) { $loop.phase_trends } else { [pscustomobject]@{} }
    foreach ($phaseName in @("create", "plan", "implement", "test", "manage")) {
        $series = if ($phaseTrends.PSObject.Properties[$phaseName] -and $null -ne $phaseTrends.$phaseName) { @($phaseTrends.$phaseName) } else { @() }
        $latest = if (@($series).Count -gt 0) { [double]$series[@($series).Count - 1].score } else { $null }
        $direction = "flat"
        if (@($series).Count -ge 2) {
            $delta = [double]$series[@($series).Count - 1].score - [double]$series[@($series).Count - 2].score
            if ($delta -gt 0.03) { $direction = "improving" }
            elseif ($delta -lt -0.03) { $direction = "declining" }
        }

        $phaseSnapshot[$phaseName] = [pscustomobject]@{
            latest_score = if ($null -ne $latest) { [math]::Round($latest, 4) } else { $null }
            direction = $direction
        }
    }

    $implementStable = ($phaseSnapshot["implement"].latest_score -ne $null -and [double]$phaseSnapshot["implement"].latest_score -ge 0.70)
    $testLagging = ($phaseSnapshot["test"].latest_score -ne $null -and [double]$phaseSnapshot["test"].latest_score -lt 0.60)

    $operatorSignals = @()
    $pendingApprovalFlag = if ($loop.PSObject.Properties["approval_pending_flag"]) { [bool]$loop.approval_pending_flag } else { $false }
    if ($pendingApprovalFlag) {
        $operatorSignals += "engineering loop paused awaiting approval"
    }

    $trendDirection = if ($loop.PSObject.Properties["trend_direction"]) { [string]$loop.trend_direction } else { "flat" }
    if ($trendDirection -eq "declining") {
        $operatorSignals += "test maturity regressed"
    }

    if ($implementStable -and $testLagging) {
        $operatorSignals += "implementation stable, testing lagging"
    }

    $penalties = if ($loop.PSObject.Properties["top_penalties"] -and $null -ne $loop.top_penalties) {
        @($loop.top_penalties | Select-Object -First 3)
    }
    else {
        @()
    }

    return [pscustomobject]@{
        path = "/tod/engineer/signal"
        service = "tod"
        source = "engineering_signal_v1"
        generated_at = Get-UtcNow
        contract_version = "engineering_signal_v1"
        current_engineering_loop_status = if ($loop.PSObject.Properties["status"]) { [string]$loop.status } else { "idle" }
        latest_maturity_band = if ($loop.PSObject.Properties["maturity_band"]) { [string]$loop.maturity_band } else { "early" }
        pending_approval_state = [pscustomobject]@{
            pending = $pendingApprovalFlag
            count = if ($loop.PSObject.Properties["pending_approval_count"]) { [int]$loop.pending_approval_count } else { 0 }
        }
        stop_reason = $stopReason
        top_penalties = @($penalties)
        trend_direction = $trendDirection
        trend_delta = if ($loop.PSObject.Properties["trend_delta"]) { [double]$loop.trend_delta } else { 0.0 }
        phase_snapshot = [pscustomobject]$phaseSnapshot
        operator_signals = @($operatorSignals | Select-Object -Unique)
    }
}

function Get-TodEngineeringLoopHistoryPayload {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)]$Config,
        [ValidateSet("run_history", "scorecard_history", "cycle_records", "review_actions")][string]$HistoryKind = "run_history",
        [int]$Page = 1,
        [int]$PageSize = 25
    )

    $historyStore = Read-EngineeringLoopHistoryStore -State $State -PreferState
    $records = @()
    if ($HistoryKind -eq "scorecard_history") {
        $records = @($historyStore.scorecard_history | Sort-Object generated_at -Descending)
    }
    elseif ($HistoryKind -eq "cycle_records") {
        $records = @($historyStore.cycle_records | Sort-Object created_at -Descending)
    }
    elseif ($HistoryKind -eq "review_actions") {
        $records = @($historyStore.review_actions | Sort-Object created_at -Descending)
    }
    else {
        $records = @($historyStore.run_history | Sort-Object generated_at -Descending)
    }

    $paged = Convert-ToPagedEngineeringHistory -Items $records -Page $Page -PageSize $PageSize
    return [pscustomobject]@{
        path = "/tod/engineer/history"
        service = "tod"
        source = "engineering_loop_history_v2"
        generated_at = Get-UtcNow
        history_kind = $HistoryKind
        paging = [pscustomobject]@{
            page = [int]$paged.page
            page_size = [int]$paged.page_size
            total = [int]$paged.total
            total_pages = [int]$paged.total_pages
            has_more = [bool]$paged.has_more
        }
        items = @($paged.items)
    }
}

function Get-TodEngineerCyclePayload {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)]$Config,
        [int]$Cycles = 1,
        [int]$Top = 10,
        [bool]$DangerousApproved = $false,
        [bool]$BypassSafeContinue = $false
    )

    $autonomy = if ($Config.PSObject.Properties["engineering_loop"] -and $Config.engineering_loop -and $Config.engineering_loop.PSObject.Properties["autonomy"]) { $Config.engineering_loop.autonomy } else { $null }
    $maxCycles = if ($autonomy -and $autonomy.PSObject.Properties["max_cycles_per_run"] -and $null -ne $autonomy.max_cycles_per_run) { [int]$autonomy.max_cycles_per_run } else { 5 }
    if ($maxCycles -lt 1) { $maxCycles = 1 }
    if ($maxCycles -gt 20) { $maxCycles = 20 }
    $safeCycles = if ($Cycles -lt 1) { 1 } elseif ($Cycles -gt $maxCycles) { $maxCycles } else { $Cycles }
    $stopAtScore = if ($autonomy -and $autonomy.PSObject.Properties["stop_at_score"] -and $null -ne $autonomy.stop_at_score) { [double]$autonomy.stop_at_score } else { 0.85 }

    $safeContinue = if ($Config.PSObject.Properties["engineering_loop"] -and $Config.engineering_loop -and $Config.engineering_loop.PSObject.Properties["safe_continue"]) { $Config.engineering_loop.safe_continue } else { $null }
    $requireNoPendingApproval = if ($safeContinue -and $safeContinue.PSObject.Properties["require_no_pending_approval"] -and $null -ne $safeContinue.require_no_pending_approval) { [bool]$safeContinue.require_no_pending_approval } else { $true }
    $historyStore = Read-EngineeringLoopHistoryStore -State $State -PreferState
    $pendingApprovalCount = [int]@($historyStore.cycle_records | Where-Object {
                $null -ne $_ -and $_.PSObject.Properties["approval_status"] -and ([string]$_.approval_status).ToLowerInvariant() -eq "pending_apply"
            }).Count
    if (-not $BypassSafeContinue -and $requireNoPendingApproval -and $pendingApprovalCount -gt 0) {
        return [pscustomobject]@{
            path = "/tod/engineer/cycle"
            service = "tod"
            source = "engineer_cycle_v1"
            generated_at = Get-UtcNow
            cycles_requested = [int]$Cycles
            cycles_executed = 0
            max_cycles_allowed = [int]$maxCycles
            stop_at_score = [double]$stopAtScore
            stopped_early = $true
            stop_reason = "safe_continue_pending_approval"
            dangerous_approved = [bool]$DangerousApproved
            pending_approval_count = [int]$pendingApprovalCount
            cycle_steps = @()
            final = $null
        }
    }

    $cycleRecordLimit = Resolve-EngineeringCycleRecordLimit -Config $Config

    $steps = @()
    $stoppedEarly = $false
    $stopReason = "max_cycles_reached"

    for ($cycle = 1; $cycle -le $safeCycles; $cycle++) {
        $runPayload = Get-TodEngineerRunPayload -State $State -Config $Config -Top $Top -ApplyPlan:$false
        $runHistoryLimit = Resolve-EngineeringLoopHistoryLimit -Config $Config -Kind "run_history"
        $null = Add-EngineeringRunHistoryRecord -State $State -Payload $runPayload -MaxEntries $runHistoryLimit
        Add-Journal -State $State -Actor "tod" -ActionName "engineer_run_cycle" -EntityType "task" -EntityId $(if (-not [string]::IsNullOrWhiteSpace([string]$runPayload.focus.task_id)) { [string]$runPayload.focus.task_id } else { "none" }) -Payload ([pscustomobject]@{ cycle = $cycle; run_id = $runPayload.run_id })

        $scorePayload = Get-TodEngineerScorecardPayload -State $State -Config $Config -Top $Top
        $scoreHistoryLimit = Resolve-EngineeringLoopHistoryLimit -Config $Config -Kind "scorecard_history"
        $null = Add-EngineeringScorecardHistoryRecord -State $State -Payload $scorePayload -MaxEntries $scoreHistoryLimit

        $score = if ($scorePayload.PSObject.Properties["overall"] -and $scorePayload.overall.PSObject.Properties["score"]) { [double]$scorePayload.overall.score } else { 0.0 }
        $band = if ($scorePayload.PSObject.Properties["overall"] -and $scorePayload.overall.PSObject.Properties["band"]) { [string]$scorePayload.overall.band } else { "early" }
        $trend = if ($State.engineering_loop.PSObject.Properties["scorecard_history"]) {
            $history = @($State.engineering_loop.scorecard_history | Where-Object { $null -ne $_ -and $_.PSObject.Properties['generated_at'] } | Sort-Object generated_at -Descending | Select-Object -First 2)
            if (@($history).Count -lt 2) {
                "flat"
            }
            else {
            $delta = [double]$history[0].score - [double]$history[1].score
            if ($delta -gt 0.03) { "improving" } elseif ($delta -lt -0.03) { "declining" } else { "flat" }
            }
        }
        else {
            "flat"
        }

        $decision = if ($score -ge $stopAtScore) { "stop" } else { "continue" }
        $cycleId = "ENGCYC-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 10).ToUpperInvariant())
        $approvalStatus = "pending_apply"
        $approvalPending = $true
        $topPenalties = if ($scorePayload.PSObject.Properties["explainability"] -and $scorePayload.explainability -and $scorePayload.explainability.PSObject.Properties["penalties"]) {
            @($scorePayload.explainability.penalties | Select-Object -First 3)
        }
        else {
            @()
        }
        $thresholdState = if ($score -ge $stopAtScore) { "met" } else { "below_threshold" }

        $cycleRecord = [pscustomobject]@{
            cycle_id = $cycleId
            run_id = [string]$runPayload.run_id
            objective_id = if ($runPayload.PSObject.Properties["focus"] -and $runPayload.focus.PSObject.Properties["objective_id"]) { [string]$runPayload.focus.objective_id } else { "" }
            objective_title = if ($runPayload.PSObject.Properties["focus"] -and $runPayload.focus.PSObject.Properties["objective_title"]) { [string]$runPayload.focus.objective_title } else { "" }
            task_id = if ($runPayload.PSObject.Properties["focus"] -and $runPayload.focus.PSObject.Properties["task_id"]) { [string]$runPayload.focus.task_id } else { "" }
            task_title = if ($runPayload.PSObject.Properties["focus"] -and $runPayload.focus.PSObject.Properties["task_title"]) { [string]$runPayload.focus.task_title } else { "" }
            phase_outputs = if ($runPayload.PSObject.Properties["phases"]) { $runPayload.phases } else { $null }
            stop_reason = if ($decision -eq "stop") { "score_target_reached" } else { "continue_requested" }
            approval_status = $approvalStatus
            approval_pending = [bool]$approvalPending
            score_snapshot = [pscustomobject]@{
                overall = if ($scorePayload.PSObject.Properties["overall"]) { $scorePayload.overall } else { $null }
                dimensions = if ($scorePayload.PSObject.Properties["dimensions"]) { @($scorePayload.dimensions) } else { @() }
            }
            maturity_band = $band
            top_penalties = @($topPenalties)
            stop_threshold_state = $thresholdState
            created_at = Get-UtcNow
            updated_at = Get-UtcNow
        }
        $null = Add-EngineeringCycleRecord -State $State -CycleRecord $cycleRecord -MaxEntries $cycleRecordLimit

        $steps += [pscustomobject]@{
            cycle = [int]$cycle
            cycle_id = $cycleId
            run_id = [string]$runPayload.run_id
            score = [double]$score
            band = $band
            trend_direction = $trend
            decision = $decision
        }

        if ($decision -eq "stop") {
            $stoppedEarly = $true
            $stopReason = "score_target_reached"
            break
        }
    }

    return [pscustomobject]@{
        path = "/tod/engineer/cycle"
        service = "tod"
        source = "engineer_cycle_v1"
        generated_at = Get-UtcNow
        cycles_requested = [int]$Cycles
        cycles_executed = [int]@($steps).Count
        max_cycles_allowed = [int]$maxCycles
        stop_at_score = [double]$stopAtScore
        stopped_early = [bool]$stoppedEarly
        stop_reason = $stopReason
        dangerous_approved = [bool]$DangerousApproved
        pending_approval_count = if ($State.engineering_loop.PSObject.Properties["pending_approval_count"]) { [int]$State.engineering_loop.pending_approval_count } else { 0 }
        cycle_steps = @($steps)
        final = if (@($steps).Count -gt 0) { $steps[@($steps).Count - 1] } else { $null }
    }
}

function Invoke-TodEngineeringCycleReview {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][string]$CycleId,
        [Parameter(Mandatory = $true)][ValidateSet("approve_apply", "reject_apply", "continue_cycle", "freeze_objective", "mark_complete")][string]$CycleReviewAction,
        [string]$Rationale,
        [int]$Top = 10,
        [bool]$DangerousApproved = $false
    )

    $historyStore = Read-EngineeringLoopHistoryStore -State $State -PreferState
    $null = Sync-EngineeringLoopHistoryToState -State $State -HistoryStore $historyStore
    $records = @($State.engineering_loop.cycle_records)
    $target = @($records | Where-Object { $null -ne $_ -and $_.PSObject.Properties["cycle_id"] -and [string]$_.cycle_id -eq [string]$CycleId } | Select-Object -First 1)
    if (@($target).Count -eq 0) {
        throw "Cycle record not found: $CycleId"
    }

    $cycle = $target[0]
    $result = [pscustomobject]@{
        cycle_id = [string]$CycleId
        action = [string]$CycleReviewAction
        applied = $false
        objective_state = ""
        note = ""
    }

    switch ($CycleReviewAction) {
        "approve_apply" {
            Assert-DangerousActionApproved -Config $Config -ActionName "sandbox-apply-plan" -DangerousApproved:$DangerousApproved
            $artifactPath = if ($cycle.PSObject.Properties["phase_outputs"] -and $cycle.phase_outputs -and $cycle.phase_outputs.PSObject.Properties["plan"] -and $cycle.phase_outputs.plan.PSObject.Properties["artifact_path"]) { [string]$cycle.phase_outputs.plan.artifact_path } else { "" }
            if ([string]::IsNullOrWhiteSpace($artifactPath)) {
                throw "Cycle record does not have a plan artifact to apply."
            }

            $applyPayload = Invoke-TodSandboxApplyPlan -PlanPath $artifactPath
            $cycle.approval_status = "approved_apply"
            $cycle.approval_pending = $false
            $cycle.apply_result = $applyPayload
            $cycle.updated_at = Get-UtcNow
            $result.applied = $true
            $result.note = "Plan artifact applied."
        }

        "reject_apply" {
            $cycle.approval_status = "rejected_apply"
            $cycle.approval_pending = $false
            $cycle.updated_at = Get-UtcNow
            $result.note = "Apply rejected by operator."
        }

        "continue_cycle" {
            $continued = Get-TodEngineerCyclePayload -State $State -Config $Config -Cycles 1 -Top $Top -DangerousApproved:$DangerousApproved -BypassSafeContinue:$true
            $result | Add-Member -NotePropertyName continued_cycle -NotePropertyValue $continued -Force
            $result.note = "Triggered one additional bounded cycle."
        }

        "freeze_objective" {
            if ($cycle.PSObject.Properties["objective_id"] -and -not [string]::IsNullOrWhiteSpace([string]$cycle.objective_id)) {
                $objective = @($State.objectives | Where-Object { [string]$_.id -eq [string]$cycle.objective_id } | Select-Object -First 1)
                if (@($objective).Count -gt 0) {
                    $objective[0].status = "frozen"
                    $objective[0].updated_at = Get-UtcNow
                    $result.objective_state = "frozen"
                }
            }
            $result.note = "Objective freeze recorded."
        }

        "mark_complete" {
            if ($cycle.PSObject.Properties["objective_id"] -and -not [string]::IsNullOrWhiteSpace([string]$cycle.objective_id)) {
                $objective = @($State.objectives | Where-Object { [string]$_.id -eq [string]$cycle.objective_id } | Select-Object -First 1)
                if (@($objective).Count -gt 0) {
                    $objective[0].status = "completed"
                    $objective[0].updated_at = Get-UtcNow
                    $result.objective_state = "completed"
                }
            }
            if ($cycle.PSObject.Properties["task_id"] -and -not [string]::IsNullOrWhiteSpace([string]$cycle.task_id)) {
                $task = @($State.tasks | Where-Object { [string]$_.id -eq [string]$cycle.task_id } | Select-Object -First 1)
                if (@($task).Count -gt 0) {
                    $task[0].status = "completed"
                    $task[0].updated_at = Get-UtcNow
                }
            }
            $result.note = "Objective/task marked complete."
        }
    }

    $reviewRecord = [pscustomobject]@{
        review_id = "ENGREV-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 10).ToUpperInvariant())
        cycle_id = [string]$CycleId
        action = [string]$CycleReviewAction
        rationale = if ([string]::IsNullOrWhiteSpace([string]$Rationale)) { "" } else { [string]$Rationale }
        result = $result
        created_at = Get-UtcNow
    }
    $null = Add-EngineeringReviewActionRecord -State $State -ReviewAction $reviewRecord

    Add-Journal -State $State -Actor "operator" -ActionName "engineering_cycle_review" -EntityType "cycle" -EntityId ([string]$CycleId) -Payload $reviewRecord

        $pending = @($State.engineering_loop.cycle_records | Where-Object {
            $null -ne $_ -and $_.PSObject.Properties["approval_status"] -and
            ([string]$_.approval_status).ToLowerInvariant() -eq "pending_apply"
        }).Count
    $State.engineering_loop.pending_approval_count = [int]$pending
    $State.engineering_loop.updated_at = Get-UtcNow

    return [pscustomobject]@{
        path = "/tod/engineer/review"
        service = "tod"
        source = "engineering_cycle_review_v1"
        generated_at = Get-UtcNow
        cycle_id = [string]$CycleId
        action = [string]$CycleReviewAction
        review = $reviewRecord
        pending_approval_count = [int]$pending
    }
}

function Get-DefaultRoutingWeights {
    return [pscustomobject]@{
        availability = 0.25
        task_category_support = 0.2
        historical_success = 0.2
        recent_fallback = 0.1
        review_quality = 0.05
        failure_rate = 0.1
        review_corrections = 0.05
        latency = 0.05
    }
}

function Normalize-RoutingWeights {
    param($Weights)

    $defaults = Get-DefaultRoutingWeights
    $merged = [ordered]@{}
    foreach ($name in @("availability", "task_category_support", "historical_success", "recent_fallback", "review_quality", "failure_rate", "review_corrections", "latency")) {
        $value = $null
        if ($null -ne $Weights -and $Weights.PSObject.Properties[$name] -and $null -ne $Weights.$name) {
            $value = [double]$Weights.$name
        }
        else {
            $value = [double]$defaults.$name
        }

        if ($value -lt 0.0) { $value = 0.0 }
        $merged[$name] = $value
    }

    $sum = 0.0
    foreach ($kv in $merged.GetEnumerator()) { $sum += [double]$kv.Value }
    if ($sum -le 0.0) {
        return $defaults
    }

    return [pscustomobject]@{
        availability = [math]::Round(([double]$merged["availability"] / $sum), 6)
        task_category_support = [math]::Round(([double]$merged["task_category_support"] / $sum), 6)
        historical_success = [math]::Round(([double]$merged["historical_success"] / $sum), 6)
        recent_fallback = [math]::Round(([double]$merged["recent_fallback"] / $sum), 6)
        review_quality = [math]::Round(([double]$merged["review_quality"] / $sum), 6)
        failure_rate = [math]::Round(([double]$merged["failure_rate"] / $sum), 6)
        review_corrections = [math]::Round(([double]$merged["review_corrections"] / $sum), 6)
        latency = [math]::Round(([double]$merged["latency"] / $sum), 6)
    }
}

function Update-RoutingFeedbackModel {
    param([Parameter(Mandatory = $true)]$State)

    if (-not $State.PSObject.Properties["routing_feedback"] -or $null -eq $State.routing_feedback) {
        $State | Add-Member -NotePropertyName routing_feedback -NotePropertyValue ([pscustomobject]@{
                learned_weights = (Get-DefaultRoutingWeights)
                sample_size = 0
                version = "feedback_v1"
                updated_at = ""
            }) -Force
    }

    $records = @($State.engine_performance.records | Where-Object { $null -ne $_ })
    $sampleSize = @($records).Count
    if ($sampleSize -lt 5) {
        $State.routing_feedback.learned_weights = Normalize-RoutingWeights -Weights (Get-DefaultRoutingWeights)
        $State.routing_feedback.sample_size = $sampleSize
        $State.routing_feedback.version = "feedback_v1"
        $State.routing_feedback.updated_at = Get-UtcNow
        return
    }

    $window = @($records | Sort-Object -Property created_at -Descending | Select-Object -First 50)
    $total = [double]@($window).Count
    $passes = [double]@($window | Where-Object { [bool]$_.success }).Count
    $revises = [double]@($window | Where-Object { [string]$_.review_decision -eq "revise" }).Count
    $escalates = [double]@($window | Where-Object { [string]$_.review_decision -eq "escalate" -or [bool]$_.needs_escalation }).Count
    $fallbacks = [double]@($window | Where-Object { [bool]$_.fallback_applied }).Count
    $latencyValues = @($window | ForEach-Object {
            if ($_.PSObject.Properties["latency_ms"] -and $null -ne $_.latency_ms) { [double]$_.latency_ms } else { $null }
        } | Where-Object { $null -ne $_ -and $_ -gt 0 })

    $passRate = if ($total -gt 0) { $passes / $total } else { 0.0 }
    $reviseRate = if ($total -gt 0) { $revises / $total } else { 0.0 }
    $failureRate = if ($total -gt 0) { $escalates / $total } else { 0.0 }
    $fallbackRate = if ($total -gt 0) { $fallbacks / $total } else { 0.0 }
    $latencyCoverage = if ($total -gt 0) { [double]@($latencyValues).Count / $total } else { 0.0 }

    $learned = Get-DefaultRoutingWeights
    if ($failureRate -ge 0.2) {
        $learned.failure_rate = [double]$learned.failure_rate + 0.06
        $learned.review_corrections = [double]$learned.review_corrections + 0.03
        $learned.historical_success = [double]$learned.historical_success - 0.03
    }
    if ($reviseRate -ge 0.25) {
        $learned.review_corrections = [double]$learned.review_corrections + 0.04
        $learned.review_quality = [double]$learned.review_quality + 0.02
    }
    if ($fallbackRate -ge 0.3) {
        $learned.recent_fallback = [double]$learned.recent_fallback + 0.04
        $learned.availability = [double]$learned.availability + 0.03
    }
    if ($passRate -ge 0.85) {
        $learned.historical_success = [double]$learned.historical_success + 0.04
    }
    if ($latencyCoverage -ge 0.6) {
        $learned.latency = [double]$learned.latency + 0.04
    }

    $State.routing_feedback.learned_weights = Normalize-RoutingWeights -Weights $learned
    $State.routing_feedback.sample_size = $sampleSize
    $State.routing_feedback.version = "feedback_v1"
    $State.routing_feedback.updated_at = Get-UtcNow
}

function Get-EnginePerformanceSummary {
    param(
        [Parameter(Mandatory = $true)]$State,
        [string]$EngineFilter,
        [string]$TaskCategoryFilter
    )

    $records = @($State.engine_performance.records)
    if (-not [string]::IsNullOrWhiteSpace($EngineFilter)) {
        $records = @($records | Where-Object { ([string]$_.engine).ToLowerInvariant() -eq $EngineFilter.ToLowerInvariant() })
    }
    if (-not [string]::IsNullOrWhiteSpace($TaskCategoryFilter)) {
        $records = @($records | Where-Object {
                if ($null -ne $_ -and $null -ne $_.PSObject.Properties['task_category'] -and -not [string]::IsNullOrWhiteSpace([string]$_.task_category)) {
                    ([string]$_.task_category).ToLowerInvariant() -eq $TaskCategoryFilter.ToLowerInvariant()
                }
                else {
                    $false
                }
            })
    }
    $byEngine = @()

    foreach ($engineGroup in @($records | Group-Object -Property engine)) {
        $groupItems = @($engineGroup.Group)
        $total = @($groupItems).Count
        if ($total -le 0) { continue }

        $passes = @($groupItems | Where-Object { [bool]$_.success }).Count
        $revises = @($groupItems | Where-Object { [string]$_.review_decision -eq "revise" }).Count
        $fallbacks = @($groupItems | Where-Object { [bool]$_.fallback_applied }).Count
        $escalations = @($groupItems | Where-Object { [bool]$_.needs_escalation -or ([string]$_.review_decision -eq "escalate") }).Count
        $reviewScores = @(
            $groupItems | ForEach-Object {
                if ($null -ne $_.PSObject.Properties['review_score'] -and $null -ne $_.review_score) {
                    [double]$_.review_score
                }
                else {
                    switch ([string]$_.review_decision) {
                        "pass" { 1.0 }
                        "revise" { 0.5 }
                        "escalate" { 0.0 }
                        default { 0.0 }
                    }
                }
            }
        )
        $avgReviewScore = [math]::Round((@($reviewScores | Measure-Object -Average).Average), 3)

        $taskTypes = @($groupItems | Group-Object -Property task_type | ForEach-Object {
                [pscustomobject]@{ task_type = [string]$_.Name; count = [int]$_.Count }
            })
        $categoryBreakdown = @(
            $groupItems |
            Group-Object -Property {
                if ($null -ne $_.PSObject.Properties['task_category'] -and -not [string]::IsNullOrWhiteSpace([string]$_.task_category)) {
                    [string]$_.task_category
                }
                else {
                    "unknown"
                }
            } | ForEach-Object {
                $cg = @($_.Group)
                $ct = @($cg).Count
                $cp = @($cg | Where-Object { [bool]$_.success }).Count
                [pscustomobject]@{
                    task_category = [string]$_.Name
                    runs = [int]$ct
                    success_rate = [math]::Round((100.0 * $cp / $ct), 2)
                }
            }
        )
        $modules = @(
            $groupItems | ForEach-Object {
                if ($null -ne $_.PSObject.Properties['modules_involved'] -and $null -ne $_.modules_involved) {
                    @($_.modules_involved)
                }
                else {
                    @()
                }
            } | Where-Object { $_ } | Group-Object | Sort-Object Count -Descending | Select-Object -First 12 | ForEach-Object {
                [pscustomobject]@{ module = [string]$_.Name; count = [int]$_.Count }
            }
        )

        $latencyValues = @(
            $groupItems | ForEach-Object {
                if ($null -ne $_.PSObject.Properties['latency_ms'] -and $null -ne $_.latency_ms) {
                    [double]$_.latency_ms
                }
            } | Where-Object { $null -ne $_ -and $_ -gt 0 }
        )
        $avgLatencyMs = if (@($latencyValues).Count -gt 0) {
            [math]::Round((@($latencyValues | Measure-Object -Average).Average), 2)
        }
        else {
            $null
        }

        $recent = @($groupItems | Sort-Object -Property created_at -Descending | Select-Object -First 10)
        $windowRecent = @($recent | Select-Object -First 5)
        $windowPrior = if (@($recent).Count -gt 5) { @($recent | Select-Object -Skip 5 -First 5) } else { @() }
        $recentRate = if (@($windowRecent).Count -gt 0) { [math]::Round((100.0 * @($windowRecent | Where-Object { [bool]$_.success }).Count / @($windowRecent).Count), 2) } else { $null }
        $priorRate = if (@($windowPrior).Count -gt 0) { [math]::Round((100.0 * @($windowPrior | Where-Object { [bool]$_.success }).Count / @($windowPrior).Count), 2) } else { $null }
        $trend = "stable"
        if ($null -ne $recentRate -and $null -ne $priorRate) {
            if ($recentRate -gt $priorRate) { $trend = "up" }
            elseif ($recentRate -lt $priorRate) { $trend = "down" }
        }

        $byEngine += [pscustomobject]@{
            engine = [string]$engineGroup.Name
            total_runs = [int]$total
            pass_rate = [math]::Round((100.0 * $passes / $total), 2)
            revise_rate = [math]::Round((100.0 * $revises / $total), 2)
            fallback_frequency = [math]::Round((100.0 * $fallbacks / $total), 2)
            escalation_rate = [math]::Round((100.0 * $escalations / $total), 2)
            average_review_outcome = $avgReviewScore
            average_latency_ms = $avgLatencyMs
            task_types = @($taskTypes)
            category_breakdown = @($categoryBreakdown)
            modules_involved = @($modules)
            recent_trend = [pscustomobject]@{
                direction = $trend
                recent_success_rate = $recentRate
                prior_success_rate = $priorRate
            }
        }
    }

    return [pscustomobject]@{
        updated_at = [string]$State.engine_performance.updated_at
        total_records = @($records).Count
        by_engine = @($byEngine)
    }
}

function Get-EngineHealthSummary {
    param(
        [Parameter(Mandatory = $true)]$State,
        [int]$Window = 10
    )

    $records = @($State.engine_performance.records | Sort-Object -Property created_at -Descending)
    $byEngine = @()

    foreach ($engineGroup in @($records | Group-Object -Property engine)) {
        $windowItems = @($engineGroup.Group | Select-Object -First $Window)
        $total = @($windowItems).Count
        if ($total -le 0) { continue }

        $passes = @($windowItems | Where-Object { [bool]$_.success }).Count
        $revises = @($windowItems | Where-Object { [string]$_.review_decision -eq "revise" }).Count
        $escalates = @($windowItems | Where-Object { [string]$_.review_decision -eq "escalate" -or [bool]$_.needs_escalation }).Count
        $fallbacks = @($windowItems | Where-Object { [bool]$_.fallback_applied }).Count

        $passRate = 100.0 * $passes / $total
        $reviseRate = 100.0 * $revises / $total
        $escalationRate = 100.0 * $escalates / $total
        $fallbackRate = 100.0 * $fallbacks / $total

        $healthScore =
            (0.45 * ($passRate / 100.0)) +
            (0.25 * (1.0 - ($escalationRate / 100.0))) +
            (0.2 * (1.0 - ($reviseRate / 100.0))) +
            (0.1 * (1.0 - ($fallbackRate / 100.0)))

        $healthBand = "healthy"
        if ($healthScore -lt 0.45) { $healthBand = "critical" }
        elseif ($healthScore -lt 0.65) { $healthBand = "degraded" }
        elseif ($healthScore -lt 0.8) { $healthBand = "watch" }

        $byEngine += [pscustomobject]@{
            engine = [string]$engineGroup.Name
            window = [int]$Window
            runs_considered = [int]$total
            pass_rate = [math]::Round($passRate, 2)
            revise_rate = [math]::Round($reviseRate, 2)
            escalation_rate = [math]::Round($escalationRate, 2)
            fallback_rate = [math]::Round($fallbackRate, 2)
            health_score = [math]::Round($healthScore, 4)
            health_band = $healthBand
        }
    }

    return [pscustomobject]@{
        updated_at = [string]$State.engine_performance.updated_at
        window = [int]$Window
        by_engine = @($byEngine)
    }
}

function Build-RoutingFeedbackReport {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)]$Config,
        [int]$HealthWindow = 10
    )

    $configuredWeights = Normalize-RoutingWeights -Weights $Config.execution_engine.routing_policy.weights
    $learnedWeights = if ($State.PSObject.Properties["routing_feedback"] -and $State.routing_feedback -and $State.routing_feedback.PSObject.Properties["learned_weights"]) {
        Normalize-RoutingWeights -Weights $State.routing_feedback.learned_weights
    }
    else {
        Get-DefaultRoutingWeights
    }
    $sampleSize = if ($State.PSObject.Properties["routing_feedback"] -and $State.routing_feedback -and $State.routing_feedback.PSObject.Properties["sample_size"] -and $null -ne $State.routing_feedback.sample_size) {
        [int]$State.routing_feedback.sample_size
    }
    else {
        0
    }
    $learningFactor = [math]::Min(0.6, [math]::Max(0.0, ($sampleSize / 100.0)))

    $effectiveWeights = Normalize-RoutingWeights -Weights ([pscustomobject]@{
            availability = ((1.0 - $learningFactor) * [double]$configuredWeights.availability) + ($learningFactor * [double]$learnedWeights.availability)
            task_category_support = ((1.0 - $learningFactor) * [double]$configuredWeights.task_category_support) + ($learningFactor * [double]$learnedWeights.task_category_support)
            historical_success = ((1.0 - $learningFactor) * [double]$configuredWeights.historical_success) + ($learningFactor * [double]$learnedWeights.historical_success)
            recent_fallback = ((1.0 - $learningFactor) * [double]$configuredWeights.recent_fallback) + ($learningFactor * [double]$learnedWeights.recent_fallback)
            review_quality = ((1.0 - $learningFactor) * [double]$configuredWeights.review_quality) + ($learningFactor * [double]$learnedWeights.review_quality)
            failure_rate = ((1.0 - $learningFactor) * [double]$configuredWeights.failure_rate) + ($learningFactor * [double]$learnedWeights.failure_rate)
            review_corrections = ((1.0 - $learningFactor) * [double]$configuredWeights.review_corrections) + ($learningFactor * [double]$learnedWeights.review_corrections)
            latency = ((1.0 - $learningFactor) * [double]$configuredWeights.latency) + ($learningFactor * [double]$learnedWeights.latency)
        })

    $health = Get-EngineHealthSummary -State $State -Window $HealthWindow

    return [pscustomobject]@{
        generated_at = Get-UtcNow
        source = "routing_feedback_v1"
        configured_weights = $configuredWeights
        learned_weights = $learnedWeights
        effective_weights = $effectiveWeights
        learning = [pscustomobject]@{
            sample_size = $sampleSize
            learning_factor = [math]::Round($learningFactor, 4)
            version = if ($State.PSObject.Properties["routing_feedback"] -and $State.routing_feedback -and $State.routing_feedback.PSObject.Properties["version"]) { [string]$State.routing_feedback.version } else { "feedback_v1" }
            updated_at = if ($State.PSObject.Properties["routing_feedback"] -and $State.routing_feedback -and $State.routing_feedback.PSObject.Properties["updated_at"]) { [string]$State.routing_feedback.updated_at } else { "" }
        }
        policy_snapshot = [pscustomobject]@{
            routing_policy = $Config.execution_engine.routing_policy
            retry_policy = $Config.execution_engine.retry_policy
        }
        engine_health = $health
    }
}

function Build-FailureTaxonomyReport {
    param(
        [Parameter(Mandatory = $true)]$State,
        [int]$Window = 50,
        [string]$CategoryFilter,
        [string]$EngineFilter
    )

    $records = @($State.engine_performance.records | Sort-Object -Property created_at -Descending | Select-Object -First $Window)
    if (-not [string]::IsNullOrWhiteSpace($CategoryFilter)) {
        $records = @($records | Where-Object {
                $tc = if ($_.PSObject.Properties["task_category"] -and $null -ne $_.task_category) { ([string]$_.task_category).ToLowerInvariant() } else { "unknown" }
                $tc -eq $CategoryFilter.ToLowerInvariant()
            })
    }
    if (-not [string]::IsNullOrWhiteSpace($EngineFilter)) {
        $records = @($records | Where-Object {
                ([string]$_.engine).ToLowerInvariant() -eq $EngineFilter.ToLowerInvariant()
            })
    }

    $grouped = @(
        $records | Group-Object -Property {
            $engine = ([string]$_.engine).ToLowerInvariant()
            $category = if ($_.PSObject.Properties["task_category"] -and $null -ne $_.task_category) { ([string]$_.task_category).ToLowerInvariant() } else { "unknown" }
            $failure = if ($_.PSObject.Properties["failure_category"] -and -not [string]::IsNullOrWhiteSpace([string]$_.failure_category)) { ([string]$_.failure_category).ToLowerInvariant() } else { "none" }
            "$engine|$category|$failure"
        } | ForEach-Object {
            $items = @($_.Group)
            $parts = ([string]$_.Name).Split('|')
            [pscustomobject]@{
                engine = [string]$parts[0]
                task_category = [string]$parts[1]
                failure_category = [string]$parts[2]
                runs = [int]@($items).Count
                pass_count = [int]@($items | Where-Object { [bool]$_.success }).Count
                revise_count = [int]@($items | Where-Object { [string]$_.review_decision -eq "revise" }).Count
                escalate_count = [int]@($items | Where-Object { [string]$_.review_decision -eq "escalate" -or [bool]$_.needs_escalation }).Count
                fallback_count = [int]@($items | Where-Object { [bool]$_.fallback_applied }).Count
            }
        } | Sort-Object -Property runs -Descending
    )

    return [pscustomobject]@{
        generated_at = Get-UtcNow
        source = "failure_taxonomy_v1"
        window = [int]$Window
        category_filter = if ([string]::IsNullOrWhiteSpace($CategoryFilter)) { "" } else { $CategoryFilter }
        engine_filter = if ([string]::IsNullOrWhiteSpace($EngineFilter)) { "" } else { $EngineFilter }
        total_records = [int]@($records).Count
        groups = @($grouped)
    }
}

function Get-RoutingDriftSignal {
    param(
        [Parameter(Mandatory = $true)]$State,
        $RoutingPolicy,
        [string]$EngineFilter,
        [string]$TaskCategoryFilter
    )

    $driftCfg = if ($RoutingPolicy -and $RoutingPolicy.PSObject.Properties["drift_detection"] -and $null -ne $RoutingPolicy.drift_detection) {
        $RoutingPolicy.drift_detection
    }
    else {
        $null
    }

    $enabled = $true
    $recentWindow = 20
    $baselineWindow = 50
    $minBaselineRecords = 10
    $failureRateMultiplier = 1.5
    $retryRateThreshold = 0.35
    $fallbackRateMultiplier = 1.5
    $fallbackRateThreshold = 0.3
    $guardrailRateMultiplier = 1.8
    $guardrailRateThreshold = 0.15
    $engineScoreDropThreshold = 0.2
    $confidencePenaltyFailureDrift = 0.18
    $confidencePenaltyRetryHigh = 0.12
    $confidencePenaltyFallbackDrift = 0.09
    $confidencePenaltyGuardrailSpike = 0.1
    $confidencePenaltyScoreDrop = 0.12
    $scorePenaltyFailureDrift = 0.12
    $scorePenaltyRetryHigh = 0.08
    $scorePenaltyFallbackDrift = 0.08
    $scorePenaltyGuardrailSpike = 0.1
    $scorePenaltyScoreDrop = 0.12
    $decayHalfLifeDays = 7.0
    $decayFloor = 0.25
    $normalizationWindowRuns = 8
    $stableRunDecayFloor = 0.2

    if ($driftCfg) {
        if ($driftCfg.PSObject.Properties["enabled"] -and $null -ne $driftCfg.enabled) { $enabled = [bool]$driftCfg.enabled }
        if ($driftCfg.PSObject.Properties["recent_window"] -and $null -ne $driftCfg.recent_window) { $recentWindow = [int]$driftCfg.recent_window }
        if ($driftCfg.PSObject.Properties["baseline_window"] -and $null -ne $driftCfg.baseline_window) { $baselineWindow = [int]$driftCfg.baseline_window }
        if ($driftCfg.PSObject.Properties["minimum_baseline_records"] -and $null -ne $driftCfg.minimum_baseline_records) { $minBaselineRecords = [int]$driftCfg.minimum_baseline_records }
        if ($driftCfg.PSObject.Properties["failure_rate_multiplier"] -and $null -ne $driftCfg.failure_rate_multiplier) { $failureRateMultiplier = [double]$driftCfg.failure_rate_multiplier }
        if ($driftCfg.PSObject.Properties["retry_rate_threshold"] -and $null -ne $driftCfg.retry_rate_threshold) { $retryRateThreshold = [double]$driftCfg.retry_rate_threshold }
        if ($driftCfg.PSObject.Properties["fallback_rate_multiplier"] -and $null -ne $driftCfg.fallback_rate_multiplier) { $fallbackRateMultiplier = [double]$driftCfg.fallback_rate_multiplier }
        if ($driftCfg.PSObject.Properties["fallback_rate_threshold"] -and $null -ne $driftCfg.fallback_rate_threshold) { $fallbackRateThreshold = [double]$driftCfg.fallback_rate_threshold }
        if ($driftCfg.PSObject.Properties["guardrail_rate_multiplier"] -and $null -ne $driftCfg.guardrail_rate_multiplier) { $guardrailRateMultiplier = [double]$driftCfg.guardrail_rate_multiplier }
        if ($driftCfg.PSObject.Properties["guardrail_rate_threshold"] -and $null -ne $driftCfg.guardrail_rate_threshold) { $guardrailRateThreshold = [double]$driftCfg.guardrail_rate_threshold }
        if ($driftCfg.PSObject.Properties["engine_score_drop_threshold"] -and $null -ne $driftCfg.engine_score_drop_threshold) { $engineScoreDropThreshold = [double]$driftCfg.engine_score_drop_threshold }
        if ($driftCfg.PSObject.Properties["confidence_penalty_failure_drift"] -and $null -ne $driftCfg.confidence_penalty_failure_drift) { $confidencePenaltyFailureDrift = [double]$driftCfg.confidence_penalty_failure_drift }
        if ($driftCfg.PSObject.Properties["confidence_penalty_retry_high"] -and $null -ne $driftCfg.confidence_penalty_retry_high) { $confidencePenaltyRetryHigh = [double]$driftCfg.confidence_penalty_retry_high }
        if ($driftCfg.PSObject.Properties["confidence_penalty_fallback_drift"] -and $null -ne $driftCfg.confidence_penalty_fallback_drift) { $confidencePenaltyFallbackDrift = [double]$driftCfg.confidence_penalty_fallback_drift }
        if ($driftCfg.PSObject.Properties["confidence_penalty_guardrail_spike"] -and $null -ne $driftCfg.confidence_penalty_guardrail_spike) { $confidencePenaltyGuardrailSpike = [double]$driftCfg.confidence_penalty_guardrail_spike }
        if ($driftCfg.PSObject.Properties["confidence_penalty_score_drop"] -and $null -ne $driftCfg.confidence_penalty_score_drop) { $confidencePenaltyScoreDrop = [double]$driftCfg.confidence_penalty_score_drop }
        if ($driftCfg.PSObject.Properties["score_penalty_failure_drift"] -and $null -ne $driftCfg.score_penalty_failure_drift) { $scorePenaltyFailureDrift = [double]$driftCfg.score_penalty_failure_drift }
        if ($driftCfg.PSObject.Properties["score_penalty_retry_high"] -and $null -ne $driftCfg.score_penalty_retry_high) { $scorePenaltyRetryHigh = [double]$driftCfg.score_penalty_retry_high }
        if ($driftCfg.PSObject.Properties["score_penalty_fallback_drift"] -and $null -ne $driftCfg.score_penalty_fallback_drift) { $scorePenaltyFallbackDrift = [double]$driftCfg.score_penalty_fallback_drift }
        if ($driftCfg.PSObject.Properties["score_penalty_guardrail_spike"] -and $null -ne $driftCfg.score_penalty_guardrail_spike) { $scorePenaltyGuardrailSpike = [double]$driftCfg.score_penalty_guardrail_spike }
        if ($driftCfg.PSObject.Properties["score_penalty_score_drop"] -and $null -ne $driftCfg.score_penalty_score_drop) { $scorePenaltyScoreDrop = [double]$driftCfg.score_penalty_score_drop }
        if ($driftCfg.PSObject.Properties["decay_half_life_days"] -and $null -ne $driftCfg.decay_half_life_days) { $decayHalfLifeDays = [double]$driftCfg.decay_half_life_days }
        if ($driftCfg.PSObject.Properties["decay_floor"] -and $null -ne $driftCfg.decay_floor) { $decayFloor = [double]$driftCfg.decay_floor }
        if ($driftCfg.PSObject.Properties["normalization_window_runs"] -and $null -ne $driftCfg.normalization_window_runs) { $normalizationWindowRuns = [int]$driftCfg.normalization_window_runs }
        if ($driftCfg.PSObject.Properties["stable_run_decay_floor"] -and $null -ne $driftCfg.stable_run_decay_floor) { $stableRunDecayFloor = [double]$driftCfg.stable_run_decay_floor }
    }

    if ($recentWindow -lt 1) { $recentWindow = 20 }
    if ($baselineWindow -lt $recentWindow) { $baselineWindow = [math]::Max($recentWindow, 50) }
    if ($minBaselineRecords -lt 1) { $minBaselineRecords = 10 }
    if ($decayHalfLifeDays -le 0) { $decayHalfLifeDays = 7.0 }
    if ($decayFloor -lt 0.0) { $decayFloor = 0.0 }
    if ($decayFloor -gt 1.0) { $decayFloor = 1.0 }
    if ($normalizationWindowRuns -lt 1) { $normalizationWindowRuns = 8 }
    if ($stableRunDecayFloor -lt 0.0) { $stableRunDecayFloor = 0.0 }
    if ($stableRunDecayFloor -gt 1.0) { $stableRunDecayFloor = 1.0 }

    $records = @($State.engine_performance.records | Sort-Object -Property created_at -Descending)
    if (-not [string]::IsNullOrWhiteSpace($EngineFilter)) {
        $records = @($records | Where-Object { ([string]$_.engine).ToLowerInvariant() -eq $EngineFilter.ToLowerInvariant() })
    }
    if (-not [string]::IsNullOrWhiteSpace($TaskCategoryFilter)) {
        $records = @($records | Where-Object {
                if ($_.PSObject.Properties["task_category"] -and $null -ne $_.task_category) {
                    ([string]$_.task_category).ToLowerInvariant() -eq $TaskCategoryFilter.ToLowerInvariant()
                }
                else {
                    $false
                }
            })
    }

    $baselineRecords = @($records | Select-Object -First $baselineWindow)
    $recentRecords = @($records | Select-Object -First $recentWindow)
    $baselineTotal = [int]@($baselineRecords).Count
    $recentTotal = [int]@($recentRecords).Count

    $getFailureRate = {
        param($Items)
        $total = [double]@($Items).Count
        if ($total -le 0) { return 0.0 }
        $fails = [double]@($Items | Where-Object { (-not [bool]$_.success) -or [bool]$_.needs_escalation -or ([string]$_.review_decision -eq "escalate") }).Count
        return ($fails / $total)
    }
    $getRetryRate = {
        param($Items)
        $total = [double]@($Items).Count
        if ($total -le 0) { return 0.0 }
        $retries = [double]@($Items | Where-Object {
                if ($_.PSObject.Properties["retry_inflated"] -and $null -ne $_.retry_inflated) { [bool]$_.retry_inflated }
                elseif ($_.PSObject.Properties["attempts_count"] -and $null -ne $_.attempts_count) { [int]$_.attempts_count -gt 1 }
                else { $false }
            }).Count
        return ($retries / $total)
    }

    $baselineFailureRate = & $getFailureRate $baselineRecords
    $recentFailureRate = & $getFailureRate $recentRecords
    $baselineRetryRate = & $getRetryRate $baselineRecords
    $recentRetryRate = & $getRetryRate $recentRecords
    $getFallbackRate = {
        param($Items)
        $total = [double]@($Items).Count
        if ($total -le 0) { return 0.0 }
        $fallbacks = [double]@($Items | Where-Object {
                if ($_.PSObject.Properties["fallback_applied"] -and $null -ne $_.fallback_applied) { [bool]$_.fallback_applied } else { $false }
            }).Count
        return ($fallbacks / $total)
    }
    $baselineFallbackRate = & $getFallbackRate $baselineRecords
    $recentFallbackRate = & $getFallbackRate $recentRecords

    $routingRecords = @($State.routing_decisions.records | Sort-Object -Property created_at -Descending)
    if (-not [string]::IsNullOrWhiteSpace($EngineFilter)) {
        $routingRecords = @($routingRecords | Where-Object {
                $selected = ([string]$_.selected_engine).ToLowerInvariant()
                if ($selected -eq "local-placeholder") { $selected = "local" }
                $selected -eq $EngineFilter.ToLowerInvariant()
            })
    }
    if (-not [string]::IsNullOrWhiteSpace($TaskCategoryFilter)) {
        $routingRecords = @($routingRecords | Where-Object {
                if ($_.PSObject.Properties["task_category"] -and $null -ne $_.task_category) {
                    ([string]$_.task_category).ToLowerInvariant() -eq $TaskCategoryFilter.ToLowerInvariant()
                }
                else {
                    $false
                }
            })
    }
    $routingBaseline = @($routingRecords | Select-Object -First $baselineWindow)
    $routingRecent = @($routingRecords | Select-Object -First $recentWindow)
    $getGuardrailBlockRate = {
        param($Items)
        $total = [double]@($Items).Count
        if ($total -le 0) { return 0.0 }
        $blocks = [double]@($Items | Where-Object {
                $outcome = if ($_.PSObject.Properties["final_outcome"] -and $null -ne $_.final_outcome) { ([string]$_.final_outcome).ToLowerInvariant() } else { "" }
                $outcome -in @("blocked_pre_invocation", "escalated_pre_run")
            }).Count
        return ($blocks / $total)
    }
    $baselineGuardrailRate = & $getGuardrailBlockRate $routingBaseline
    $recentGuardrailRate = & $getGuardrailBlockRate $routingRecent

    $getRecoveryScore = {
        param($Items)
        $total = [double]@($Items).Count
        if ($total -le 0) { return 0.0 }
        $clean = [double]@($Items | Where-Object {
                $onRetry = if ($_.PSObject.Properties["recovered_on_retry"] -and $null -ne $_.recovered_on_retry) { [bool]$_.recovered_on_retry } else { $false }
                $onFallback = if ($_.PSObject.Properties["recovered_on_fallback"] -and $null -ne $_.recovered_on_fallback) { [bool]$_.recovered_on_fallback } else { $false }
                [bool]$_.success -and (-not $onRetry) -and (-not $onFallback)
            }).Count
        $retryRecovered = [double]@($Items | Where-Object {
                if ($_.PSObject.Properties["recovered_on_retry"] -and $null -ne $_.recovered_on_retry) { [bool]$_.recovered_on_retry } else { $false }
            }).Count
        $fallbackRecovered = [double]@($Items | Where-Object {
                if ($_.PSObject.Properties["recovered_on_fallback"] -and $null -ne $_.recovered_on_fallback) { [bool]$_.recovered_on_fallback } else { $false }
            }).Count
        $manual = [double]@($Items | Where-Object {
                if ($_.PSObject.Properties["manual_intervention_required"] -and $null -ne $_.manual_intervention_required) { [bool]$_.manual_intervention_required } else { -not [bool]$_.success }
            }).Count
        $failures = [double]@($Items | Where-Object {
                $manualRequired = if ($_.PSObject.Properties["manual_intervention_required"] -and $null -ne $_.manual_intervention_required) { [bool]$_.manual_intervention_required } else { $false }
                (-not [bool]$_.success) -and (-not $manualRequired)
            }).Count

        $score = (($clean * 1.0) + ($retryRecovered * 0.6) + ($fallbackRecovered * 0.4) + ($failures * -1.0) + ($manual * -1.0)) / $total
        return [math]::Max(-1.0, [math]::Min(1.0, [double]$score))
    }
    $baselineRecoveryScore = & $getRecoveryScore $baselineRecords
    $recentRecoveryScore = & $getRecoveryScore $recentRecords

    $failureDrift = $false
    if ($enabled -and $baselineTotal -ge $minBaselineRecords -and $recentTotal -ge [math]::Min(5, $recentWindow)) {
        if ($baselineFailureRate -gt 0.0) {
            $failureDrift = ($recentFailureRate -gt ($baselineFailureRate * $failureRateMultiplier))
        }
        else {
            $failureDrift = ($recentFailureRate -ge 0.2)
        }
    }

    $retryHigh = $false
    if ($enabled -and $recentTotal -ge [math]::Min(5, $recentWindow)) {
        $retryHigh = ($recentRetryRate -ge $retryRateThreshold)
    }
    $fallbackDrift = $false
    if ($enabled -and $baselineTotal -ge $minBaselineRecords -and $recentTotal -ge [math]::Min(5, $recentWindow)) {
        $fallbackDrift = ($recentFallbackRate -ge [math]::Max($fallbackRateThreshold, ($baselineFallbackRate * $fallbackRateMultiplier)))
    }
    $guardrailSpike = $false
    if ($enabled -and [int]@($routingBaseline).Count -ge $minBaselineRecords -and [int]@($routingRecent).Count -ge [math]::Min(5, $recentWindow)) {
        $guardrailSpike = ($recentGuardrailRate -ge [math]::Max($guardrailRateThreshold, ($baselineGuardrailRate * $guardrailRateMultiplier)))
    }
    $scoreDrop = $false
    if ($enabled -and $baselineTotal -ge $minBaselineRecords -and $recentTotal -ge [math]::Min(5, $recentWindow)) {
        $scoreDrop = (($baselineRecoveryScore - $recentRecoveryScore) -ge $engineScoreDropThreshold)
    }

    $warnings = @()
    if ($failureDrift) {
        $warnings += [pscustomobject]@{
            code = "failure_rate_drift"
            severity = "warn"
            message = "Failure rate drift detected in recent window."
            recent_failure_rate = [math]::Round($recentFailureRate, 4)
            baseline_failure_rate = [math]::Round($baselineFailureRate, 4)
            threshold = [math]::Round(($baselineFailureRate * $failureRateMultiplier), 4)
        }
    }
    if ($retryHigh) {
        $warnings += [pscustomobject]@{
            code = "retry_rate_high"
            severity = "warn"
            message = "Retry rate exceeded configured threshold."
            recent_retry_rate = [math]::Round($recentRetryRate, 4)
            threshold = [math]::Round($retryRateThreshold, 4)
        }
    }
    if ($fallbackDrift) {
        $warnings += [pscustomobject]@{
            code = "fallback_dependence_rising"
            severity = "warn"
            message = "Fallback dependence increased in recent window."
            recent_fallback_rate = [math]::Round($recentFallbackRate, 4)
            baseline_fallback_rate = [math]::Round($baselineFallbackRate, 4)
            threshold = [math]::Round([math]::Max($fallbackRateThreshold, ($baselineFallbackRate * $fallbackRateMultiplier)), 4)
        }
    }
    if ($guardrailSpike) {
        $warnings += [pscustomobject]@{
            code = "guardrail_block_spike"
            severity = "warn"
            message = "Guardrail-block rate spiked in recent routing decisions."
            recent_guardrail_block_rate = [math]::Round($recentGuardrailRate, 4)
            baseline_guardrail_block_rate = [math]::Round($baselineGuardrailRate, 4)
            threshold = [math]::Round([math]::Max($guardrailRateThreshold, ($baselineGuardrailRate * $guardrailRateMultiplier)), 4)
        }
    }
    if ($scoreDrop) {
        $warnings += [pscustomobject]@{
            code = "engine_reliability_score_drop"
            severity = "warn"
            message = "Engine recovery quality score dropped beyond threshold."
            recent_engine_score = [math]::Round($recentRecoveryScore, 4)
            baseline_engine_score = [math]::Round($baselineRecoveryScore, 4)
            drop = [math]::Round(($baselineRecoveryScore - $recentRecoveryScore), 4)
            threshold = [math]::Round($engineScoreDropThreshold, 4)
        }
    }

    $confidencePenalty = 0.0
    $scorePenalty = 0.0
    if ($failureDrift) {
        $confidencePenalty += $confidencePenaltyFailureDrift
        $scorePenalty += $scorePenaltyFailureDrift
    }
    if ($retryHigh) {
        $confidencePenalty += $confidencePenaltyRetryHigh
        $scorePenalty += $scorePenaltyRetryHigh
    }
    if ($fallbackDrift) {
        $confidencePenalty += $confidencePenaltyFallbackDrift
        $scorePenalty += $scorePenaltyFallbackDrift
    }
    if ($guardrailSpike) {
        $confidencePenalty += $confidencePenaltyGuardrailSpike
        $scorePenalty += $scorePenaltyGuardrailSpike
    }
    if ($scoreDrop) {
        $confidencePenalty += $confidencePenaltyScoreDrop
        $scorePenalty += $scorePenaltyScoreDrop
    }

    $consecutiveStableRuns = 0
    foreach ($r in @($records)) {
        $stableSuccess = [bool]$r.success
        $stableRetry = if ($r.PSObject.Properties["retry_inflated"] -and $null -ne $r.retry_inflated) { [bool]$r.retry_inflated } elseif ($r.PSObject.Properties["attempts_count"] -and $null -ne $r.attempts_count) { [int]$r.attempts_count -gt 1 } else { $false }
        $stableFallback = if ($r.PSObject.Properties["fallback_applied"] -and $null -ne $r.fallback_applied) { [bool]$r.fallback_applied } else { $false }
        $stableEscalation = if ($r.PSObject.Properties["needs_escalation"] -and $null -ne $r.needs_escalation) { [bool]$r.needs_escalation } else { ([string]$r.review_decision -eq "escalate") }
        if ($stableSuccess -and (-not $stableRetry) -and (-not $stableFallback) -and (-not $stableEscalation)) {
            $consecutiveStableRuns += 1
        }
        else {
            break
        }
    }
    $recoveryProgress = [math]::Min(1.0, ([double]$consecutiveStableRuns / [double]$normalizationWindowRuns))
    $stableRunDecayFactor = [math]::Max($stableRunDecayFloor, (1.0 - $recoveryProgress))

    $latestSignalAt = $null
    if (@($recentRecords).Count -gt 0) {
        $latestText = if ($recentRecords[0].PSObject.Properties["created_at"]) { [string]$recentRecords[0].created_at } else { "" }
        if (-not [string]::IsNullOrWhiteSpace($latestText)) {
            try {
                $latestSignalAt = [datetime]$latestText
            }
            catch {
                $latestSignalAt = $null
            }
        }
    }

    $signalAgeDays = 0.0
    if ($latestSignalAt) {
        $signalAgeDays = [math]::Max(0.0, ((Get-Date).ToUniversalTime() - $latestSignalAt.ToUniversalTime()).TotalDays)
    }
    $decayFactor = [math]::Max($decayFloor, [math]::Exp(-[math]::Log(2.0) * ($signalAgeDays / $decayHalfLifeDays)))
    $confidencePenalty = $confidencePenalty * $decayFactor * $stableRunDecayFactor
    $scorePenalty = $scorePenalty * $decayFactor * $stableRunDecayFactor

    $alertState = "stable"
    if ($guardrailSpike -or ($scoreDrop -and ($baselineRecoveryScore - $recentRecoveryScore) -ge ($engineScoreDropThreshold * 1.25)) -or $recentFailureRate -ge 0.5) {
        $alertState = "critical"
    }
    elseif (@($warnings).Count -ge 3 -or $recentFailureRate -ge 0.35 -or $confidencePenalty -ge 0.22) {
        $alertState = "degraded"
    }
    elseif (@($warnings).Count -gt 0) {
        $alertState = "warning"
    }

    return [pscustomobject]@{
        enabled = [bool]$enabled
        recent_window = [int]$recentWindow
        baseline_window = [int]$baselineWindow
        minimum_baseline_records = [int]$minBaselineRecords
        runs_considered = [pscustomobject]@{
            recent = [int]$recentTotal
            baseline = [int]$baselineTotal
        }
        rates = [pscustomobject]@{
            recent_failure = [math]::Round($recentFailureRate, 4)
            baseline_failure = [math]::Round($baselineFailureRate, 4)
            recent_retry = [math]::Round($recentRetryRate, 4)
            baseline_retry = [math]::Round($baselineRetryRate, 4)
            recent_fallback = [math]::Round($recentFallbackRate, 4)
            baseline_fallback = [math]::Round($baselineFallbackRate, 4)
            recent_guardrail_block = [math]::Round($recentGuardrailRate, 4)
            baseline_guardrail_block = [math]::Round($baselineGuardrailRate, 4)
        }
        engine_score = [pscustomobject]@{
            recent = [math]::Round($recentRecoveryScore, 4)
            baseline = [math]::Round($baselineRecoveryScore, 4)
            drop = [math]::Round(($baselineRecoveryScore - $recentRecoveryScore), 4)
        }
        warning = ([bool]$failureDrift -or [bool]$retryHigh -or [bool]$fallbackDrift -or [bool]$guardrailSpike -or [bool]$scoreDrop)
        alert_state = $alertState
        warning_count = [int]@($warnings).Count
        warnings = @($warnings)
        recovery = [pscustomobject]@{
            normalization_window_runs = [int]$normalizationWindowRuns
            consecutive_stable_runs = [int]$consecutiveStableRuns
            recovery_progress = [math]::Round($recoveryProgress, 4)
            stable_run_decay_floor = [math]::Round($stableRunDecayFloor, 4)
            stable_run_decay_factor = [math]::Round($stableRunDecayFactor, 4)
        }
        decay = [pscustomobject]@{
            half_life_days = [math]::Round($decayHalfLifeDays, 4)
            floor = [math]::Round($decayFloor, 4)
            factor = [math]::Round($decayFactor, 4)
            signal_age_days = [math]::Round($signalAgeDays, 4)
            latest_signal_at = if ($latestSignalAt) { $latestSignalAt.ToUniversalTime().ToString("o") } else { "" }
        }
        confidence_penalty = [math]::Round([math]::Min(0.6, $confidencePenalty), 4)
        score_penalty = [math]::Round([math]::Min(0.6, $scorePenalty), 4)
    }
}

function Get-RecoveryQualitySummary {
    param(
        [Parameter(Mandatory = $true)]$State,
        [int]$Window = 50,
        [string]$CategoryFilter,
        [string]$EngineFilter
    )

    $weights = [pscustomobject]@{
        clean_success = 1.0
        recovered_retry = 0.6
        recovered_fallback = 0.4
        guardrail_block = 0.2
        unrecovered_failure = -1.0
        manual_intervention = -1.0
    }

    $perf = @($State.engine_performance.records | Sort-Object -Property created_at -Descending | Select-Object -First $Window)
    if (-not [string]::IsNullOrWhiteSpace($CategoryFilter)) {
        $perf = @($perf | Where-Object {
                if ($_.PSObject.Properties["task_category"] -and $null -ne $_.task_category) {
                    ([string]$_.task_category).ToLowerInvariant() -eq $CategoryFilter.ToLowerInvariant()
                }
                else {
                    $false
                }
            })
    }
    if (-not [string]::IsNullOrWhiteSpace($EngineFilter)) {
        $perf = @($perf | Where-Object { ([string]$_.engine).ToLowerInvariant() -eq $EngineFilter.ToLowerInvariant() })
    }

    $routing = @($State.routing_decisions.records | Sort-Object -Property created_at -Descending | Select-Object -First $Window)
    if (-not [string]::IsNullOrWhiteSpace($CategoryFilter)) {
        $routing = @($routing | Where-Object {
                if ($_.PSObject.Properties["task_category"] -and $null -ne $_.task_category) {
                    ([string]$_.task_category).ToLowerInvariant() -eq $CategoryFilter.ToLowerInvariant()
                }
                else {
                    $false
                }
            })
    }
    if (-not [string]::IsNullOrWhiteSpace($EngineFilter)) {
        $routing = @($routing | Where-Object {
                ([string]$_.selected_engine).ToLowerInvariant() -eq (Convert-EngineAliasLabel -Engine $EngineFilter)
            })
    }

    $engines = @()
    $engines += @($perf | ForEach-Object { ([string]$_.engine).ToLowerInvariant() })
    $engines += @($routing | ForEach-Object {
            $selected = [string]$_.selected_engine
            if ($selected -eq "local-placeholder") { "local" } else { $selected.ToLowerInvariant() }
        })
    $engines = @($engines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)

    $byEngine = @()
    foreach ($engine in $engines) {
        $perfEngine = @($perf | Where-Object { ([string]$_.engine).ToLowerInvariant() -eq $engine })
        $routingEngine = @($routing | Where-Object {
                $selected = ([string]$_.selected_engine).ToLowerInvariant()
                if ($selected -eq "local-placeholder") { $selected = "local" }
                $selected -eq $engine
            })

        $cleanSuccess = [int]@($perfEngine | Where-Object {
                $onRetry = if ($_.PSObject.Properties["recovered_on_retry"] -and $null -ne $_.recovered_on_retry) { [bool]$_.recovered_on_retry } else { $false }
                $onFallback = if ($_.PSObject.Properties["recovered_on_fallback"] -and $null -ne $_.recovered_on_fallback) { [bool]$_.recovered_on_fallback } else { $false }
                [bool]$_.success -and (-not $onRetry) -and (-not $onFallback)
            }).Count
        $recoveredRetry = [int]@($perfEngine | Where-Object {
                if ($_.PSObject.Properties["recovered_on_retry"] -and $null -ne $_.recovered_on_retry) { [bool]$_.recovered_on_retry } else { $false }
            }).Count
        $recoveredFallback = [int]@($perfEngine | Where-Object {
                if ($_.PSObject.Properties["recovered_on_fallback"] -and $null -ne $_.recovered_on_fallback) { [bool]$_.recovered_on_fallback } else { $false }
            }).Count
        $manualIntervention = [int]@($perfEngine | Where-Object {
                if ($_.PSObject.Properties["manual_intervention_required"] -and $null -ne $_.manual_intervention_required) { [bool]$_.manual_intervention_required } else { -not [bool]$_.success }
            }).Count
        $unrecoveredFailure = [int]@($perfEngine | Where-Object {
                $manualRequired = if ($_.PSObject.Properties["manual_intervention_required"] -and $null -ne $_.manual_intervention_required) { [bool]$_.manual_intervention_required } else { $false }
                (-not [bool]$_.success) -and (-not $manualRequired)
            }).Count
        $guardrailBlock = [int]@($routingEngine | Where-Object {
                $outcome = ([string]$_.final_outcome).ToLowerInvariant()
                $outcome -in @("blocked_pre_invocation", "escalated_pre_run")
            }).Count

        $totalOutcomes = $cleanSuccess + $recoveredRetry + $recoveredFallback + $manualIntervention + $unrecoveredFailure + $guardrailBlock
        if ($totalOutcomes -le 0) { continue }

        $scoreNumerator =
            ($weights.clean_success * $cleanSuccess) +
            ($weights.recovered_retry * $recoveredRetry) +
            ($weights.recovered_fallback * $recoveredFallback) +
            ($weights.guardrail_block * $guardrailBlock) +
            ($weights.unrecovered_failure * $unrecoveredFailure) +
            ($weights.manual_intervention * $manualIntervention)
        $score = [double]$scoreNumerator / [double]$totalOutcomes
        $score = [math]::Round([math]::Max(-1.0, [math]::Min(1.0, $score)), 4)

        $band = "critical"
        if ($score -ge 0.75) { $band = "strong" }
        elseif ($score -ge 0.5) { $band = "stable" }
        elseif ($score -ge 0.25) { $band = "watch" }

        $byEngine += [pscustomobject]@{
            engine = $engine
            reliability_score = $score
            reliability_band = $band
            total_outcomes = [int]$totalOutcomes
            counts = [pscustomobject]@{
                clean_success = $cleanSuccess
                recovered_retry = $recoveredRetry
                recovered_fallback = $recoveredFallback
                guardrail_block = $guardrailBlock
                unrecovered_failure = $unrecoveredFailure
                manual_intervention = $manualIntervention
            }
        }
    }

    return [pscustomobject]@{
        generated_at = Get-UtcNow
        source = "recovery_quality_v1"
        window = [int]$Window
        scoring = $weights
        by_engine = @($byEngine | Sort-Object -Property reliability_score -Descending)
    }
}

function Get-GuardrailTrendSummary {
    param(
        [Parameter(Mandatory = $true)]$State,
        [int]$Window = 50,
        [string]$CategoryFilter,
        [string]$EngineFilter
    )

    $records = @($State.routing_decisions.records | Sort-Object -Property created_at -Descending | Select-Object -First ([math]::Max(10, ($Window * 2))))
    if (-not [string]::IsNullOrWhiteSpace($CategoryFilter)) {
        $records = @($records | Where-Object {
                if ($_.PSObject.Properties["task_category"] -and $null -ne $_.task_category) {
                    ([string]$_.task_category).ToLowerInvariant() -eq $CategoryFilter.ToLowerInvariant()
                }
                else {
                    $false
                }
            })
    }
    if (-not [string]::IsNullOrWhiteSpace($EngineFilter)) {
        $records = @($records | Where-Object { ([string]$_.selected_engine).ToLowerInvariant() -eq (Convert-EngineAliasLabel -Engine $EngineFilter) })
    }

    $recent = @($records | Select-Object -First $Window)
    $prior = @($records | Select-Object -Skip $Window -First $Window)

    $blockRate = {
        param($Items)
        $total = [double]@($Items).Count
        if ($total -le 0) { return $null }
        $blocked = [double]@($Items | Where-Object {
            $outcome = if ($_.PSObject.Properties["final_outcome"] -and $null -ne $_.final_outcome) { ([string]$_.final_outcome).ToLowerInvariant() } else { "" }
                $outcome -in @("blocked_pre_invocation", "escalated_pre_run")
            }).Count
        return [math]::Round(($blocked / $total), 4)
    }

    $recentRate = & $blockRate $recent
    $priorRate = & $blockRate $prior
    $direction = "stable"
    if ($null -ne $recentRate -and $null -ne $priorRate) {
        if ($recentRate -gt $priorRate) { $direction = "up" }
        elseif ($recentRate -lt $priorRate) { $direction = "down" }
    }

    return [pscustomobject]@{
        source = "guardrail_trend_v1"
        window = [int]$Window
        recent_block_rate = $recentRate
        prior_block_rate = $priorRate
        trend = $direction
        recent_total = [int]@($recent).Count
        prior_total = [int]@($prior).Count
    }
}

function Build-ReliabilityDashboard {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)]$Config,
        [int]$Window = 25,
        [string]$CategoryFilter,
        [string]$EngineFilter
    )

    $routingFeedback = Build-RoutingFeedbackReport -State $State -Config $Config -HealthWindow $Window
    $taxonomy = Build-FailureTaxonomyReport -State $State -Window $Window -CategoryFilter $CategoryFilter -EngineFilter $EngineFilter
    $recentRouting = Get-RoutingDecisionSummary -State $State -TaskFilter "" -Take 5
    $recoveryQuality = Get-RecoveryQualitySummary -State $State -Window $Window -CategoryFilter $CategoryFilter -EngineFilter $EngineFilter
    $guardrailTrend = Get-GuardrailTrendSummary -State $State -Window $Window -CategoryFilter $CategoryFilter -EngineFilter $EngineFilter

    $engineNames = @($State.engine_performance.records | ForEach-Object { ([string]$_.engine).ToLowerInvariant() } | Where-Object { $_ } | Select-Object -Unique)
    if (-not [string]::IsNullOrWhiteSpace($EngineFilter)) {
        $engineNames = @($engineNames | Where-Object { $_ -eq $EngineFilter.ToLowerInvariant() })
    }
    $retryTrend = @()
    $driftWarnings = @()
    foreach ($eng in $engineNames) {
        $drift = Get-RoutingDriftSignal -State $State -RoutingPolicy $Config.execution_engine.routing_policy -EngineFilter $eng -TaskCategoryFilter $CategoryFilter
        $retryTrend += [pscustomobject]@{
            engine = $eng
            recent_retry_rate = [double]$drift.rates.recent_retry
            baseline_retry_rate = [double]$drift.rates.baseline_retry
            recent_fallback_rate = [double]$drift.rates.recent_fallback
            baseline_fallback_rate = [double]$drift.rates.baseline_fallback
            recent_guardrail_block_rate = [double]$drift.rates.recent_guardrail_block
            baseline_guardrail_block_rate = [double]$drift.rates.baseline_guardrail_block
            recent_engine_score = [double]$drift.engine_score.recent
            baseline_engine_score = [double]$drift.engine_score.baseline
            alert_state = if ($drift.PSObject.Properties["alert_state"]) { [string]$drift.alert_state } else { "stable" }
            recovery_progress = if ($drift.PSObject.Properties["recovery"]) { [double]$drift.recovery.recovery_progress } else { 0.0 }
            consecutive_stable_runs = if ($drift.PSObject.Properties["recovery"]) { [int]$drift.recovery.consecutive_stable_runs } else { 0 }
            decay_factor = if ($drift.PSObject.Properties["decay"]) { [double]$drift.decay.factor } else { 1.0 }
            signal_age_days = if ($drift.PSObject.Properties["decay"]) { [double]$drift.decay.signal_age_days } else { 0.0 }
            confidence_penalty = [double]$drift.confidence_penalty
            score_penalty = [double]$drift.score_penalty
        }
        foreach ($warning in @($drift.warnings)) {
            $driftWarnings += [pscustomobject]@{
                engine = $eng
                code = [string]$warning.code
                severity = [string]$warning.severity
                message = [string]$warning.message
                details = $warning
            }
        }
    }

    return [pscustomobject]@{
        generated_at = Get-UtcNow
        source = "reliability_dashboard_v1"
        window = [int]$Window
        filters = [pscustomobject]@{
            category = if ([string]::IsNullOrWhiteSpace($CategoryFilter)) { "" } else { $CategoryFilter }
            engine = if ([string]::IsNullOrWhiteSpace($EngineFilter)) { "" } else { $EngineFilter }
        }
        policy_snapshot = [pscustomobject]@{
            routing_policy = $Config.execution_engine.routing_policy
            retry_policy = $Config.execution_engine.retry_policy
        }
        routing_feedback = $routingFeedback
        failure_taxonomy = $taxonomy
        engine_reliability = $recoveryQuality
        retry_trend = @($retryTrend)
        guardrail_trend = $guardrailTrend
        drift_warnings = @($driftWarnings)
        recent_routing_decisions = @($recentRouting.records)
    }
}

function Get-AlertSeverityRank {
    param([string]$State)

    switch (([string]$State).ToLowerInvariant()) {
        "critical" { return 3 }
        "degraded" { return 2 }
        "warning" { return 1 }
        default { return 0 }
    }
}

function Get-ReliabilityAlertExplainability {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)]$Dashboard,
        $RetryTrend,
        $DriftWarnings,
        $DriftPenaltyActive,
        [Parameter(Mandatory = $true)][string]$CurrentAlertState
    )

    $retryItems = if ($null -eq $RetryTrend) { @() } else { @($RetryTrend) }
    $warningItems = if ($null -eq $DriftWarnings) { @() } else { @($DriftWarnings) }
    $penaltyItems = if ($null -eq $DriftPenaltyActive) { @() } else { @($DriftPenaltyActive) }

    $reasons = @()
    $warningCounts = [ordered]@{}
    foreach ($warning in @($warningItems)) {
        $severity = if ($warning.PSObject.Properties["severity"] -and -not [string]::IsNullOrWhiteSpace([string]$warning.severity)) {
            ([string]$warning.severity).ToLowerInvariant()
        }
        else {
            "unknown"
        }
        if (-not $warningCounts.Contains($severity)) {
            $warningCounts[$severity] = 0
        }
        $warningCounts[$severity] = [int]$warningCounts[$severity] + 1
    }

    $dominantAlert = @($retryItems | Sort-Object @{ Expression = { Get-AlertSeverityRank -State ([string]$_.alert_state) }; Descending = $true } | Select-Object -First 1)
    if (@($dominantAlert).Count -gt 0) {
        $dom = $dominantAlert[0]
        $domAlert = if ($dom.PSObject.Properties["alert_state"]) { [string]$dom.alert_state } else { "stable" }
        if ((Get-AlertSeverityRank -State $domAlert) -gt 0) {
            $reasons += [pscustomobject]@{
                code = "retry_trend_alert"
                severity = $domAlert
                message = "Retry/fallback trend elevated reliability alert state."
                evidence = [pscustomobject]@{
                    engine = if ($dom.PSObject.Properties["engine"]) { [string]$dom.engine } else { "unknown" }
                    recent_retry_rate = if ($dom.PSObject.Properties["recent_retry_rate"]) { [double]$dom.recent_retry_rate } else { 0.0 }
                    baseline_retry_rate = if ($dom.PSObject.Properties["baseline_retry_rate"]) { [double]$dom.baseline_retry_rate } else { 0.0 }
                    recent_fallback_rate = if ($dom.PSObject.Properties["recent_fallback_rate"]) { [double]$dom.recent_fallback_rate } else { 0.0 }
                    baseline_fallback_rate = if ($dom.PSObject.Properties["baseline_fallback_rate"]) { [double]$dom.baseline_fallback_rate } else { 0.0 }
                }
            }
        }
    }

    if (@($penaltyItems).Count -gt 0) {
        $reasons += [pscustomobject]@{
            code = "drift_penalty_active"
            severity = if ([string]::IsNullOrWhiteSpace($CurrentAlertState)) { "warning" } else { $CurrentAlertState }
            message = "Drift penalties are currently active for one or more engines."
            evidence = [pscustomobject]@{
                engines = @($penaltyItems | ForEach-Object { [string]$_.engine } | Select-Object -Unique)
                count = [int]@($penaltyItems).Count
            }
        }
    }

    if (@($warningItems).Count -gt 0) {
        $reasons += [pscustomobject]@{
            code = "drift_warnings_present"
            severity = if ($warningCounts.Contains("critical")) { "critical" } elseif ($warningCounts.Contains("degraded")) { "degraded" } elseif ($warningCounts.Contains("warning")) { "warning" } else { "warning" }
            message = "Drift warning signals were emitted by the reliability dashboard."
            evidence = [pscustomobject]@{
                total = [int]@($warningItems).Count
                by_severity = [pscustomobject]$warningCounts
            }
        }
    }

    $approvalSummary = Get-PendingApprovalRuntimeSummary -State $State
    if ([int]$approvalSummary.pending_approvals_total -gt 0) {
        $reasons += [pscustomobject]@{
            code = "pending_approval_backlog"
            severity = if ([int]$approvalSummary.pending_approvals_total -ge 100) { "degraded" } else { "warning" }
            message = "Pending approval backlog is adding operational reliability pressure."
            evidence = [pscustomobject]@{
                total = [int]$approvalSummary.pending_approvals_total
                stale_count = [int]$approvalSummary.pending_approvals_stale_count
                low_value_count = [int]$approvalSummary.pending_approvals_low_value_count
                promotable_count = [int]$approvalSummary.pending_approvals_promotable_count
            }
        }
    }

    $guardrailTrend = if ($Dashboard.PSObject.Properties["guardrail_trend"] -and $Dashboard.guardrail_trend) { $Dashboard.guardrail_trend } else { $null }
    if ($guardrailTrend -and $guardrailTrend.PSObject.Properties["trend"] -and ([string]$guardrailTrend.trend).ToLowerInvariant() -eq "up") {
        $reasons += [pscustomobject]@{
            code = "guardrail_block_rate_increase"
            severity = "warning"
            message = "Guardrail block rate is trending upward in recent routing decisions."
            evidence = [pscustomobject]@{
                recent_block_rate = if ($guardrailTrend.PSObject.Properties["recent_block_rate"]) { $guardrailTrend.recent_block_rate } else { $null }
                prior_block_rate = if ($guardrailTrend.PSObject.Properties["prior_block_rate"]) { $guardrailTrend.prior_block_rate } else { $null }
                trend = [string]$guardrailTrend.trend
            }
        }
    }

    if (@($reasons).Count -eq 0) {
        $reasons += [pscustomobject]@{
            code = "stable_signal"
            severity = "stable"
            message = "No elevated reliability pressure detected from retry, drift, guardrail, or approval signals."
            evidence = [pscustomobject]@{}
        }
    }

    $inputs = [pscustomobject]@{
        alert_state_raw = if ([string]::IsNullOrWhiteSpace($CurrentAlertState)) { "stable" } else { $CurrentAlertState }
        retry_trend = [pscustomobject]@{
            engine_count = [int]@($retryItems).Count
            by_engine = @($retryItems | ForEach-Object {
                    [pscustomobject]@{
                        engine = if ($_.PSObject.Properties["engine"]) { [string]$_.engine } else { "unknown" }
                        alert_state = if ($_.PSObject.Properties["alert_state"]) { [string]$_.alert_state } else { "stable" }
                        recent_retry_rate = if ($_.PSObject.Properties["recent_retry_rate"]) { [double]$_.recent_retry_rate } else { 0.0 }
                        baseline_retry_rate = if ($_.PSObject.Properties["baseline_retry_rate"]) { [double]$_.baseline_retry_rate } else { 0.0 }
                        recent_fallback_rate = if ($_.PSObject.Properties["recent_fallback_rate"]) { [double]$_.recent_fallback_rate } else { 0.0 }
                        baseline_fallback_rate = if ($_.PSObject.Properties["baseline_fallback_rate"]) { [double]$_.baseline_fallback_rate } else { 0.0 }
                        confidence_penalty = if ($_.PSObject.Properties["confidence_penalty"]) { [double]$_.confidence_penalty } else { 0.0 }
                        score_penalty = if ($_.PSObject.Properties["score_penalty"]) { [double]$_.score_penalty } else { 0.0 }
                    }
                })
        }
        drift_warnings = [pscustomobject]@{
            total = [int]@($warningItems).Count
            by_severity = [pscustomobject]$warningCounts
        }
        drift_penalties = [pscustomobject]@{
            active = (@($penaltyItems).Count -gt 0)
            engines = @($penaltyItems | ForEach-Object { [string]$_.engine } | Select-Object -Unique)
            count = [int]@($penaltyItems).Count
        }
        guardrail_trend = if ($guardrailTrend) { $guardrailTrend } else { $null }
        pending_approvals = [pscustomobject]@{
            total = [int]$approvalSummary.pending_approvals_total
            by_type = $approvalSummary.pending_approvals_by_type
            by_age = $approvalSummary.pending_approvals_by_age
            by_source = $approvalSummary.pending_approvals_by_source
            stale_count = [int]$approvalSummary.pending_approvals_stale_count
            low_value_count = [int]$approvalSummary.pending_approvals_low_value_count
            promotable_count = [int]$approvalSummary.pending_approvals_promotable_count
        }
    }

    return [pscustomobject]@{
        reasons = @($reasons)
        inputs = $inputs
    }
}

function Get-TodVersionPayload {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)]$State
    )

    $scriptVersion = "tod-runtime-v1"
    $sourceVersion = if ($Config -and $Config.PSObject.Properties["execution_engine"] -and $Config.execution_engine -and $Config.execution_engine.PSObject.Properties["routing_policy"] -and $Config.execution_engine.routing_policy -and $Config.execution_engine.routing_policy.PSObject.Properties["source"] -and -not [string]::IsNullOrWhiteSpace([string]$Config.execution_engine.routing_policy.source)) {
        [string]$Config.execution_engine.routing_policy.source
    }
    else {
        "routing_policy_v1"
    }

    return [pscustomobject]@{
        path = "/tod/version"
        service = "tod"
        runtime = "powershell"
        version = $scriptVersion
        policy_source = $sourceVersion
        generated_at = Get-UtcNow
        state_updated_at = if ($State -and $State.PSObject.Properties["engine_performance"] -and $State.engine_performance -and $State.engine_performance.PSObject.Properties["updated_at"]) { [string]$State.engine_performance.updated_at } else { "" }
    }
}

function Get-TodCapabilitiesPayload {
    param([Parameter(Mandatory = $true)]$Config)

    $capabilityEndpoints = @(
        "/tod/reliability",
        "/tod/execution-readiness",
        "/tod/capabilities",
        "/tod/research",
        "/tod/resourcing",
        "/tod/engineer/run",
        "/tod/engineer/scorecard",
        "/tod/engineer/summary",
        "/tod/engineer/signal",
        "/tod/engineer/history",
        "/tod/engineer/cycle",
        "/tod/engineer/review",
        "/tod/sandbox/files",
        "/tod/sandbox/plan",
        "/tod/sandbox/apply",
        "/tod/sandbox/write",
        "/tod/state-bus",
        "/tod/version"
    )

    return [pscustomobject]@{
        path = "/tod/capabilities"
        service = "tod"
        generated_at = Get-UtcNow
        execution = [pscustomobject]@{
            engines = @("codex", "local")
            fallback_supported = [bool]$Config.execution_engine.allow_fallback
            readiness_policy = [pscustomobject]@{
                enabled = if ($Config.execution_engine.PSObject.Properties["readiness_policy"] -and $Config.execution_engine.readiness_policy -and $Config.execution_engine.readiness_policy.PSObject.Properties["enabled"]) { [bool]$Config.execution_engine.readiness_policy.enabled } else { $false }
                capability_name = "tod_sweep_certification"
                signal_name = "execution-readiness"
                signal_source = if ($Config.execution_engine.PSObject.Properties["readiness_policy"] -and $Config.execution_engine.readiness_policy -and $Config.execution_engine.readiness_policy.PSObject.Properties["signal_path"] -and -not [string]::IsNullOrWhiteSpace([string]$Config.execution_engine.readiness_policy.signal_path)) { [string]$Config.execution_engine.readiness_policy.signal_path } else { "shared_state/tod_operator_chat_sweep_artifact_smoke.latest.json" }
                authoritative_surface = "direct_artifact_smoke"
                non_authoritative_surfaces = @("wrapper_pester_output")
                signal_command = ".\\scripts\\TOD.ps1 -Action get-execution-readiness"
                display_max_artifact_age_minutes = if ($Config.execution_engine.PSObject.Properties["readiness_policy"] -and $Config.execution_engine.readiness_policy -and $Config.execution_engine.readiness_policy.PSObject.Properties["display_max_artifact_age_minutes"]) { [int]$Config.execution_engine.readiness_policy.display_max_artifact_age_minutes } else { 10 }
                block_actions = if ($Config.execution_engine.PSObject.Properties["readiness_policy"] -and $Config.execution_engine.readiness_policy -and $Config.execution_engine.readiness_policy.PSObject.Properties["block_actions"]) { @($Config.execution_engine.readiness_policy.block_actions | ForEach-Object { [string]$_ }) } else { @("run-task") }
                degrade_actions = if ($Config.execution_engine.PSObject.Properties["readiness_policy"] -and $Config.execution_engine.readiness_policy -and $Config.execution_engine.readiness_policy.PSObject.Properties["degrade_actions"]) { @($Config.execution_engine.readiness_policy.degrade_actions | ForEach-Object { [string]$_ }) } else { @("engineer-run", "codex_handoff") }
                block_states = if ($Config.execution_engine.PSObject.Properties["readiness_policy"] -and $Config.execution_engine.readiness_policy -and $Config.execution_engine.readiness_policy.PSObject.Properties["block_states"]) { @($Config.execution_engine.readiness_policy.block_states | ForEach-Object { [string]$_ }) } else { @("stale", "invalid", "unknown") }
                degrade_states = if ($Config.execution_engine.PSObject.Properties["readiness_policy"] -and $Config.execution_engine.readiness_policy -and $Config.execution_engine.readiness_policy.PSObject.Properties["degrade_states"]) { @($Config.execution_engine.readiness_policy.degrade_states | ForEach-Object { [string]$_ }) } else { @("degraded", "stale", "invalid", "unknown") }
                history_path = if ($Config.execution_engine.PSObject.Properties["readiness_policy"] -and $Config.execution_engine.readiness_policy -and $Config.execution_engine.readiness_policy.PSObject.Properties["history_path"] -and -not [string]::IsNullOrWhiteSpace([string]$Config.execution_engine.readiness_policy.history_path)) { [string]$Config.execution_engine.readiness_policy.history_path } else { "shared_state/tod_execution_readiness_history.latest.json" }
            }
            retry_policy = [pscustomobject]@{
                enabled = [bool]$Config.execution_engine.retry_policy.enabled
                categories = @($Config.execution_engine.retry_policy.max_attempts_by_category.PSObject.Properties.Name)
            }
        }
        reliability = [pscustomobject]@{
            drift_detection = $true
            trust_restoration = $true
            alert_states = @("stable", "warning", "degraded", "critical")
            quarantine_supported = if ($Config.execution_engine.routing_policy.PSObject.Properties["drift_detection"] -and $Config.execution_engine.routing_policy.drift_detection -and $Config.execution_engine.routing_policy.drift_detection.PSObject.Properties["quarantine_enabled"]) { [bool]$Config.execution_engine.routing_policy.drift_detection.quarantine_enabled } else { $false }
        }
        research = [pscustomobject]@{
            repository_index_available = (Test-Path -Path $repoIndexPath)
            engineering_memory_available = (Test-EngineeringMemoryAvailable)
            supports_related_file_exploration = $true
        }
        resourcing = [pscustomobject]@{
            supports_external_handoff_brief = $true
            supports_skill_gap_recommendations = $true
            procurement_automation = $false
        }
        engineering_loop_v2 = [pscustomobject]@{
            summary_endpoint = "/tod/engineer/summary"
            signal_endpoint = "/tod/engineer/signal"
            history_endpoint = "/tod/engineer/history"
            cycle_endpoint = "/tod/engineer/cycle"
            review_endpoint = "/tod/engineer/review"
            explainable_scorecard = $true
            cycle_runner = $true
        }
        code_write_sandbox = [pscustomobject]@{
            enabled = $true
            root = "tod/sandbox/workspace"
            supports_append = $true
            supports_plan = $true
            supports_apply_plan = $true
            path_guardrails = @("disallow_parent_traversal", "workspace_confined")
        }
        endpoints = @($capabilityEndpoints)
    }
}

function Resolve-ExecutionReadinessSignalPath {
    param([Parameter(Mandatory = $true)]$Config)

    $configuredPath = ""
    if ($Config -and $Config.PSObject.Properties["execution_engine"] -and $Config.execution_engine -and $Config.execution_engine.PSObject.Properties["readiness_policy"] -and $Config.execution_engine.readiness_policy -and $Config.execution_engine.readiness_policy.PSObject.Properties["signal_path"] -and -not [string]::IsNullOrWhiteSpace([string]$Config.execution_engine.readiness_policy.signal_path)) {
        $configuredPath = [string]$Config.execution_engine.readiness_policy.signal_path
    }

    if ([string]::IsNullOrWhiteSpace($configuredPath)) {
        return $executionReadinessSignalPath
    }

    if ([System.IO.Path]::IsPathRooted($configuredPath)) {
        return [System.IO.Path]::GetFullPath($configuredPath)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $configuredPath))
}

function Resolve-ExecutionReadinessHistoryPath {
    param([Parameter(Mandatory = $true)]$Config)

    $configuredPath = ""
    if ($Config -and $Config.PSObject.Properties["execution_engine"] -and $Config.execution_engine -and $Config.execution_engine.PSObject.Properties["readiness_policy"] -and $Config.execution_engine.readiness_policy -and $Config.execution_engine.readiness_policy.PSObject.Properties["history_path"] -and -not [string]::IsNullOrWhiteSpace([string]$Config.execution_engine.readiness_policy.history_path)) {
        $configuredPath = [string]$Config.execution_engine.readiness_policy.history_path
    }

    if ([string]::IsNullOrWhiteSpace($configuredPath)) {
        return [System.IO.Path]::GetFullPath((Join-Path $repoRoot "shared_state/tod_execution_readiness_history.latest.json"))
    }

    if ([System.IO.Path]::IsPathRooted($configuredPath)) {
        return [System.IO.Path]::GetFullPath($configuredPath)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $configuredPath))
}

function Update-ExecutionReadinessHistory {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)]$ReadinessPayload
    )

    $policy = if ($Config -and $Config.PSObject.Properties["execution_engine"] -and $Config.execution_engine -and $Config.execution_engine.PSObject.Properties["readiness_policy"]) { $Config.execution_engine.readiness_policy } else { $null }
    $historyPath = Resolve-ExecutionReadinessHistoryPath -Config $Config
    $historyMaxEntries = if ($policy -and $policy.PSObject.Properties["history_max_entries"] -and $null -ne $policy.history_max_entries) { [int]$policy.history_max_entries } else { 50 }
    $historyMaxEntries = [math]::Max(5, [math]::Min(500, $historyMaxEntries))

    $existing = $null
    if (Test-Path -Path $historyPath -PathType Leaf) {
        try {
            $existing = (Get-Content -Path $historyPath -Raw) | ConvertFrom-Json
        }
        catch {
            $existing = $null
        }
    }

    $previousState = if ($existing -and $existing.PSObject.Properties["current_state"] -and $existing.current_state) { $existing.current_state } else { $null }
    $recentTransitions = if ($existing -and $existing.PSObject.Properties["recent_transitions"] -and $existing.recent_transitions) { @($existing.recent_transitions) } else { @() }

    $currentStatus = if ($ReadinessPayload.PSObject.Properties["status"]) { [string]$ReadinessPayload.status } else { "unknown" }
    $currentReason = if ($ReadinessPayload.PSObject.Properties["reason"]) { [string]$ReadinessPayload.reason } else { "unknown" }
    $currentArtifactGeneratedAt = if ($ReadinessPayload.PSObject.Properties["artifact_generated_at"]) { [string]$ReadinessPayload.artifact_generated_at } else { "" }
    $currentArtifactAgeMinutes = if ($ReadinessPayload.PSObject.Properties["artifact_age_minutes"]) { $ReadinessPayload.artifact_age_minutes } else { $null }

    $shouldRecordTransition = $false
    $transitionKind = "initial"
    if ($null -eq $previousState) {
        $shouldRecordTransition = $true
    }
    else {
        $previousStatus = if ($previousState.PSObject.Properties["status"]) { [string]$previousState.status } else { "unknown" }
        $previousReason = if ($previousState.PSObject.Properties["reason"]) { [string]$previousState.reason } else { "unknown" }
        $previousArtifactGeneratedAt = if ($previousState.PSObject.Properties["artifact_generated_at"]) { [string]$previousState.artifact_generated_at } else { "" }
        $previousExecutionAllowed = if ($previousState.PSObject.Properties["execution_allowed"]) { [bool]$previousState.execution_allowed } else { $false }
        $currentExecutionAllowed = if ($ReadinessPayload.PSObject.Properties["execution_allowed"]) { [bool]$ReadinessPayload.execution_allowed } else { $false }

        if ($previousStatus -ne $currentStatus -or $previousReason -ne $currentReason -or $previousArtifactGeneratedAt -ne $currentArtifactGeneratedAt -or $previousExecutionAllowed -ne $currentExecutionAllowed) {
            $shouldRecordTransition = $true
            $transitionKind = "state_change"
        }
    }

    if ($shouldRecordTransition) {
        $recentTransitions = @(
            [pscustomobject]@{
                transition_at = Get-UtcNow
                transition_kind = $transitionKind
                prior_status = if ($previousState -and $previousState.PSObject.Properties["status"]) { [string]$previousState.status } else { "" }
                prior_reason = if ($previousState -and $previousState.PSObject.Properties["reason"]) { [string]$previousState.reason } else { "" }
                new_status = $currentStatus
                new_reason = $currentReason
                artifact_path = if ($ReadinessPayload.PSObject.Properties["artifact_path"]) { [string]$ReadinessPayload.artifact_path } else { "" }
                artifact_generated_at = $currentArtifactGeneratedAt
                artifact_age_minutes = $currentArtifactAgeMinutes
                authoritative = if ($ReadinessPayload.PSObject.Properties["authoritative"]) { [bool]$ReadinessPayload.authoritative } else { $true }
                freshness_state = if ($ReadinessPayload.PSObject.Properties["freshness_state"]) { [string]$ReadinessPayload.freshness_state } else { "unknown" }
                execution_allowed = if ($ReadinessPayload.PSObject.Properties["execution_allowed"]) { [bool]$ReadinessPayload.execution_allowed } else { $false }
                signal_name = "execution-readiness"
                host_name = $env:COMPUTERNAME
                user_name = $env:USERNAME
                process_id = $PID
                session_id = [System.Diagnostics.Process]::GetCurrentProcess().SessionId
            }
        ) + @($recentTransitions | Select-Object -First ($historyMaxEntries - 1))
    }

    $currentState = [pscustomobject]@{
        evaluated_at = Get-UtcNow
        status = $currentStatus
        reason = $currentReason
        detail = if ($ReadinessPayload.PSObject.Properties["detail"]) { [string]$ReadinessPayload.detail } else { "" }
        valid = if ($ReadinessPayload.PSObject.Properties["valid"]) { [bool]$ReadinessPayload.valid } else { $false }
        execution_allowed = if ($ReadinessPayload.PSObject.Properties["execution_allowed"]) { [bool]$ReadinessPayload.execution_allowed } else { $false }
        authoritative = if ($ReadinessPayload.PSObject.Properties["authoritative"]) { [bool]$ReadinessPayload.authoritative } else { $true }
        freshness_state = if ($ReadinessPayload.PSObject.Properties["freshness_state"]) { [string]$ReadinessPayload.freshness_state } else { "unknown" }
        artifact_path = if ($ReadinessPayload.PSObject.Properties["artifact_path"]) { [string]$ReadinessPayload.artifact_path } else { "" }
        artifact_generated_at = $currentArtifactGeneratedAt
        artifact_age_minutes = $currentArtifactAgeMinutes
        host_name = $env:COMPUTERNAME
        user_name = $env:USERNAME
        process_id = $PID
        session_id = [System.Diagnostics.Process]::GetCurrentProcess().SessionId
    }

    $historyDir = Split-Path -Parent $historyPath
    if (-not [string]::IsNullOrWhiteSpace($historyDir) -and -not (Test-Path -Path $historyDir)) {
        New-Item -ItemType Directory -Path $historyDir -Force | Out-Null
    }

    $historyPayload = [pscustomobject]@{
        path = "/tod/execution-readiness-history"
        source = "tod_sweep_certification_history_v1"
        generated_at = Get-UtcNow
        history_path = $historyPath
        transition_count = @($recentTransitions).Count
        max_entries = $historyMaxEntries
        current_state = $currentState
        recent_transitions = @($recentTransitions)
    }

    try {
        $historyPayload | ConvertTo-Json -Depth 20 | Set-Content -Path $historyPath -Encoding utf8 -ErrorAction Stop
    }
    catch [System.IO.IOException] {
    }
    return $historyPayload
}

function Get-TodExecutionReadinessPayload {
    param([Parameter(Mandatory = $true)]$Config)

    $policy = if ($Config -and $Config.PSObject.Properties["execution_engine"] -and $Config.execution_engine -and $Config.execution_engine.PSObject.Properties["readiness_policy"]) { $Config.execution_engine.readiness_policy } else { $null }
    $enabled = if ($policy -and $policy.PSObject.Properties["enabled"]) { [bool]$policy.enabled } else { $false }
    $signalPath = Resolve-ExecutionReadinessSignalPath -Config $Config
    $historyPath = Resolve-ExecutionReadinessHistoryPath -Config $Config
    $maxAgeMinutes = if ($policy -and $policy.PSObject.Properties["max_artifact_age_minutes"] -and $null -ne $policy.max_artifact_age_minutes) { [int]$policy.max_artifact_age_minutes } else { 30 }
    $displayMaxAgeMinutes = if ($policy -and $policy.PSObject.Properties["display_max_artifact_age_minutes"] -and $null -ne $policy.display_max_artifact_age_minutes) { [int]$policy.display_max_artifact_age_minutes } else { [math]::Min($maxAgeMinutes, 10) }
    $blockActions = if ($policy -and $policy.PSObject.Properties["block_actions"]) { @($policy.block_actions | ForEach-Object { ([string]$_).ToLowerInvariant() }) } else { @("run-task") }
    $degradeActions = if ($policy -and $policy.PSObject.Properties["degrade_actions"]) { @($policy.degrade_actions | ForEach-Object { ([string]$_).ToLowerInvariant() }) } else { @("engineer-run") }
    $blockStates = if ($policy -and $policy.PSObject.Properties["block_states"]) { @($policy.block_states | ForEach-Object { ([string]$_).ToLowerInvariant() }) } else { @("stale", "invalid", "unknown") }
    $degradeStates = if ($policy -and $policy.PSObject.Properties["degrade_states"]) { @($policy.degrade_states | ForEach-Object { ([string]$_).ToLowerInvariant() }) } else { @("degraded", "stale", "invalid", "unknown") }

    $status = "unknown"
    $valid = $false
    $executionAllowed = $false
    $reason = "policy_disabled"
    $detail = "Execution readiness policy is disabled."
    $freshnessState = "unknown"
    $artifact = $null
    $artifactGeneratedAt = ""
    $artifactAgeMinutes = $null

    if ($enabled) {
        $status = "unknown"
        $valid = $false
        $executionAllowed = $false
        $reason = "artifact_missing"
        $detail = "Execution readiness artifact is missing."

        if (Test-Path -Path $signalPath -PathType Leaf) {
            try {
                $artifact = (Get-Content -Path $signalPath -Raw) | ConvertFrom-Json
                $artifactGeneratedAt = if ($artifact.PSObject.Properties["generated_at"]) { [string]$artifact.generated_at } else { "" }

                $parsedGeneratedAt = $null
                if (-not [string]::IsNullOrWhiteSpace($artifactGeneratedAt)) {
                    try {
                        $parsedGeneratedAt = ([datetime]::Parse($artifactGeneratedAt, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)).ToUniversalTime()
                    }
                    catch {
                        $parsedGeneratedAt = $null
                    }
                }

                if ($null -ne $parsedGeneratedAt) {
                    $artifactAgeMinutes = [math]::Round(((Get-Date).ToUniversalTime() - $parsedGeneratedAt).TotalMinutes, 2)
                }

                $passedAll = if ($artifact.PSObject.Properties["summary"] -and $artifact.summary -and $artifact.summary.PSObject.Properties["passed_all"]) { [bool]$artifact.summary.passed_all } else { $false }
                $exitCode = if ($artifact.PSObject.Properties["summary"] -and $artifact.summary -and $artifact.summary.PSObject.Properties["exit_code"]) { [int]$artifact.summary.exit_code } else { 1 }
                $executionStale = ($null -eq $artifactAgeMinutes) -or ($artifactAgeMinutes -gt $maxAgeMinutes)
                $displayStale = ($null -eq $artifactAgeMinutes) -or ($artifactAgeMinutes -gt $displayMaxAgeMinutes)

                if ($executionStale) {
                    $status = "stale"
                    $valid = $false
                    $executionAllowed = $false
                    $reason = "artifact_stale"
                    $detail = "Execution readiness artifact is older than policy allows."
                    $freshnessState = "stale"
                }
                elseif ($passedAll -and $exitCode -eq 0) {
                    if ($displayStale) {
                        $status = "degraded"
                        $valid = $true
                        $executionAllowed = $true
                        $reason = "artifact_display_stale"
                        $detail = "Execution readiness artifact still permits execution, but its display freshness window has expired."
                        $freshnessState = "display_stale"
                    }
                    else {
                        $status = "valid"
                        $valid = $true
                        $executionAllowed = $true
                        $reason = "artifact_passed"
                        $detail = "Execution readiness artifact is current and passing."
                        $freshnessState = "fresh"
                    }
                }
                else {
                    $status = "invalid"
                    $valid = $false
                    $executionAllowed = $false
                    $reason = "artifact_failed"
                    $detail = "Execution readiness artifact exists but did not pass all checks."
                    $freshnessState = if ($displayStale) { "display_stale" } else { "fresh" }
                }
            }
            catch {
                $status = "unknown"
                $valid = $false
                $executionAllowed = $false
                $reason = "parse_failure"
                $detail = [string]$_.Exception.Message
                $freshnessState = "unknown"
            }
        }
    }

    if (-not $enabled) {
        $executionAllowed = $true
    }

    $readinessPayload = [pscustomobject]@{
        status = $status
        valid = $valid
        execution_allowed = $executionAllowed
        authoritative = $true
        reason = $reason
        detail = $detail
        freshness_state = $freshnessState
        artifact_path = $signalPath
        artifact_generated_at = $artifactGeneratedAt
        artifact_age_minutes = $artifactAgeMinutes
        execution_max_artifact_age_minutes = $maxAgeMinutes
        display_max_artifact_age_minutes = $displayMaxAgeMinutes
        checks_passed_all = if ($null -ne $artifact -and $artifact.PSObject.Properties["summary"] -and $null -ne $artifact.summary) { [bool]$artifact.summary.passed_all } else { $false }
        artifact_exit_code = if ($null -ne $artifact -and $artifact.PSObject.Properties["summary"] -and $null -ne $artifact.summary -and $artifact.summary.PSObject.Properties["exit_code"]) { [int]$artifact.summary.exit_code } else { $null }
    }
    $history = Update-ExecutionReadinessHistory -Config $Config -ReadinessPayload $readinessPayload

    return [pscustomobject]@{
        path = "/tod/execution-readiness"
        service = "tod"
        signal_name = "execution-readiness"
        capability_name = "TOD Sweep Certification Capability"
        source = "tod_sweep_certification_v2"
        authoritative_surface = "direct_artifact_smoke"
        non_authoritative_surfaces = @("wrapper_pester_output")
        generated_at = Get-UtcNow
        artifact_path = $signalPath
        history_path = $historyPath
        policy = [pscustomobject]@{
            enabled = $enabled
            max_artifact_age_minutes = $maxAgeMinutes
            display_max_artifact_age_minutes = $displayMaxAgeMinutes
            block_actions = @($blockActions)
            degrade_actions = @($degradeActions)
            block_states = @($blockStates)
            degrade_states = @($degradeStates)
            history_path = $historyPath
            degrade_apply_plan = if ($policy -and $policy.PSObject.Properties["degrade_apply_plan"]) { [bool]$policy.degrade_apply_plan } else { $true }
        }
        readiness = $readinessPayload
        history = $history
        certification = if ($null -ne $artifact) { $artifact } else { $null }
    }
}

function Get-TodResearchPayload {
    param(
        [Parameter(Mandatory = $true)]$State,
        [int]$Top = 10
    )

    $safeTop = if ($Top -lt 1) { 1 } elseif ($Top -gt 100) { 100 } else { $Top }
    $objectives = if ($State.PSObject.Properties["objectives"]) { @($State.objectives) } else { @() }
    $tasks = if ($State.PSObject.Properties["tasks"]) { @($State.tasks) } else { @() }

    $recentObjectives = @($objectives | Sort-Object updated_at, created_at -Descending | Select-Object -First $safeTop | ForEach-Object {
            [pscustomobject]@{
                objective_id = [string]$_.id
                title = [string]$_.title
                status = if ($_.PSObject.Properties["status"]) { [string]$_.status } else { "unknown" }
                priority = if ($_.PSObject.Properties["priority"]) { [string]$_.priority } else { "" }
            }
        })

    $recentTasks = @($tasks | Sort-Object updated_at, created_at -Descending | Select-Object -First $safeTop | ForEach-Object {
            [pscustomobject]@{
                task_id = [string]$_.id
                objective_id = if ($_.PSObject.Properties["objective_id"]) { [string]$_.objective_id } else { "" }
                title = if ($_.PSObject.Properties["title"]) { [string]$_.title } else { "" }
                status = if ($_.PSObject.Properties["status"]) { [string]$_.status } else { "unknown" }
                task_category = Resolve-TaskCategory -Task $_
            }
        })

    $repo = $null
    if (Test-Path -Path $repoIndexPath) {
        try {
            $repo = (Get-Content -Path $repoIndexPath -Raw) | ConvertFrom-Json
        }
        catch {
            $repo = $null
        }
    }

    $memory = $null
    if (Test-EngineeringMemoryAvailable) {
        $memory = Load-EngineeringMemory
    }

    $memoryTags = @()
    if ($memory) {
        foreach ($bucket in @("decision_memory", "failure_memory", "pattern_memory", "test_memory", "repo_memory", "architecture_memory")) {
            if ($memory.PSObject.Properties[$bucket] -and $memory.$bucket) {
                foreach ($entry in @($memory.$bucket)) {
                    if ($entry.PSObject.Properties["tags"] -and $entry.tags) {
                        $memoryTags += @($entry.tags | ForEach-Object { [string]$_ })
                    }
                }
            }
        }
    }

    $topTags = @($memoryTags | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Group-Object | Sort-Object Count -Descending | Select-Object -First 8 | ForEach-Object { [string]$_.Name })
    $researchPrompts = @(
        "Trace active objective dependencies and unresolved blockers",
        "Identify modules with highest recent churn risk",
        "Map reliability hotspots to task categories",
        "Generate external handoff summary for current objective"
    )

    return [pscustomobject]@{
        path = "/tod/research"
        service = "tod"
        source = "research_snapshot_v1"
        generated_at = Get-UtcNow
        repository = [pscustomobject]@{
            indexed = ($null -ne $repo)
            branch = if ($repo -and $repo.PSObject.Properties["repository"] -and $repo.repository.PSObject.Properties["branch"]) { [string]$repo.repository.branch } else { "unknown" }
            commit = if ($repo -and $repo.PSObject.Properties["repository"] -and $repo.repository.PSObject.Properties["commit"]) { [string]$repo.repository.commit } else { "unknown" }
            top_level_folders = if ($repo -and $repo.PSObject.Properties["top_level_folders"]) { @($repo.top_level_folders | Select-Object -First 12) } else { @() }
            important_files = if ($repo -and $repo.PSObject.Properties["important_files"]) { @($repo.important_files | Select-Object -First 20) } else { @() }
        }
        active_context = [pscustomobject]@{
            recent_objectives = @($recentObjectives)
            recent_tasks = @($recentTasks)
            frequent_memory_tags = @($topTags)
        }
        exploration = [pscustomobject]@{
            research_prompts = @($researchPrompts)
            suggested_actions = @("index-repo", "generate-module-summaries", "find-related-files", "show-impact-area")
            engineer_script = "scripts/TOD-Engineer.ps1"
        }
    }
}

function Get-TodResourcingPayload {
    param(
        [Parameter(Mandatory = $true)]$State,
        [string]$ObjectiveId,
        [string]$TaskId,
        [int]$Top = 10
    )

    $safeTop = if ($Top -lt 1) { 1 } elseif ($Top -gt 100) { 100 } else { $Top }
    $objectives = if ($State.PSObject.Properties["objectives"]) { @($State.objectives) } else { @() }
    $tasks = if ($State.PSObject.Properties["tasks"]) { @($State.tasks) } else { @() }

    $selectedObjective = $null
    if (-not [string]::IsNullOrWhiteSpace($ObjectiveId)) {
        $selectedObjective = @($objectives | Where-Object { [string]$_.id -eq [string]$ObjectiveId } | Select-Object -First 1)
    }
    if ($null -eq $selectedObjective -or @($selectedObjective).Count -eq 0) {
        $selectedObjective = @($objectives | Sort-Object updated_at, created_at -Descending | Select-Object -First 1)
    }
    $objective = if ($null -ne $selectedObjective -and @($selectedObjective).Count -gt 0) { @($selectedObjective)[0] } else { $null }

    $selectedTask = $null
    if (-not [string]::IsNullOrWhiteSpace($TaskId)) {
        $selectedTask = @($tasks | Where-Object { [string]$_.id -eq [string]$TaskId } | Select-Object -First 1)
    }
    $task = if ($null -ne $selectedTask -and @($selectedTask).Count -gt 0) { @($selectedTask)[0] } else { $null }

    $objectiveTasks = if ($objective -and $objective.PSObject.Properties["id"]) {
        @($tasks | Where-Object { [string]$_.objective_id -eq [string]$objective.id })
    }
    else {
        @($tasks | Select-Object -First $safeTop)
    }
    $bridgeRuntimeTasks = @($objectiveTasks | Where-Object { Test-IsBridgeRuntimeTask -Task $_ })

    $categoryCounts = @{}
    foreach ($t in $objectiveTasks) {
        $cat = Resolve-TaskCategory -Task $t
        if (-not $categoryCounts.ContainsKey($cat)) {
            $categoryCounts[$cat] = 0
        }
        $categoryCounts[$cat] = [int]$categoryCounts[$cat] + 1
    }

    $skills = @()
    if ($categoryCounts.ContainsKey("code_change") -or $categoryCounts.ContainsKey("refactor")) { $skills += "PowerShell development" }
    if ($categoryCounts.ContainsKey("test_generation")) { $skills += "Automated test authoring" }
    if ($categoryCounts.ContainsKey("sync_check")) { $skills += "Integration/API contract validation" }
    if (@($skills).Count -eq 0) { $skills = @("General software engineering") }

    $workPackages = @($objectiveTasks | Sort-Object updated_at, created_at -Descending | Select-Object -First $safeTop | ForEach-Object {
            [pscustomobject]@{
                task_id = [string]$_.id
                title = if ($_.PSObject.Properties["title"]) { [string]$_.title } else { "" }
                status = if ($_.PSObject.Properties["status"]) { [string]$_.status } else { "unknown" }
                category = Resolve-TaskCategory -Task $_
            }
        })

    return [pscustomobject]@{
        path = "/tod/resourcing"
        service = "tod"
        source = "resourcing_brief_v1"
        generated_at = Get-UtcNow
        focus = [pscustomobject]@{
            objective_id = if ($objective) { [string]$objective.id } else { "" }
            objective_title = if ($objective -and $objective.PSObject.Properties["title"]) { [string]$objective.title } else { "" }
            task_id = if ($task -and $task.PSObject.Properties["id"]) { [string]$task.id } else { "" }
            task_title = if ($task -and $task.PSObject.Properties["title"]) { [string]$task.title } else { "" }
        }
        demand_profile = [pscustomobject]@{
            task_count = @($objectiveTasks).Count
            bridge_runtime_count = @($bridgeRuntimeTasks).Count
            categories = [pscustomobject]$categoryCounts
            target_skills = @($skills)
        }
        external_resourcing = [pscustomobject]@{
            channels = @("specialist_contractor", "partner_delivery_team", "domain_reviewer")
            handoff_package_minimum = @("objective brief", "task list", "acceptance criteria", "validation commands", "repo access constraints")
            governance = @("NDA and access policy enforcement", "branch protection and PR review gates", "artifact traceability")
            procurement_automation = $false
        }
        suggested_work_packages = @($workPackages)
    }
}

function Get-TodSandboxRoot {
    $root = Join-Path $repoRoot "tod/sandbox/workspace"
    if (-not (Test-Path -Path $root)) {
        New-Item -ItemType Directory -Path $root -Force | Out-Null
    }
    return $root
}

function Get-TodEngineerRunPayload {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)]$Config,
        [string]$ObjectiveId,
        [string]$TaskId,
        [string]$Body,
        [switch]$Append,
        [switch]$ApplyPlan,
        [bool]$DangerousApproved = $false,
        [int]$Top = 10
    )

    $safeTop = if ($Top -lt 1) { 1 } elseif ($Top -gt 100) { 100 } else { $Top }
    $objectives = if ($State.PSObject.Properties["objectives"]) { @($State.objectives) } else { @() }
    $tasks = if ($State.PSObject.Properties["tasks"]) { @($State.tasks) } else { @() }

    $selectedObjective = $null
    if (-not [string]::IsNullOrWhiteSpace($ObjectiveId)) {
        $selectedObjective = @($objectives | Where-Object { [string]$_.id -eq [string]$ObjectiveId } | Select-Object -First 1)
    }
    if (($null -eq $selectedObjective -or @($selectedObjective).Count -eq 0) -and @($objectives).Count -gt 0) {
        $selectedObjective = @($objectives | Sort-Object updated_at, created_at -Descending | Select-Object -First 1)
    }
    $objective = if ($null -ne $selectedObjective -and @($selectedObjective).Count -gt 0) { @($selectedObjective)[0] } else { $null }

    $selectedTask = $null
    if (-not [string]::IsNullOrWhiteSpace($TaskId)) {
        $selectedTask = @($tasks | Where-Object { [string]$_.id -eq [string]$TaskId } | Select-Object -First 1)
    }
        if (($null -eq $selectedTask -or @($selectedTask).Count -eq 0) -and $objective) {
            $taskPartition = Get-ObjectiveTaskPartition -Tasks $tasks -ObjectiveId ([string]$objective.id)
            $selectionPool = if (@($taskPartition.canonical).Count -gt 0) { @($taskPartition.canonical) } else { @($taskPartition.all) }
            $selectedTask = Get-PreferredTaskSelection -Tasks $selectionPool
        }
    if (($null -eq $selectedTask -or @($selectedTask).Count -eq 0) -and @($tasks).Count -gt 0) {
        $selectedTask = @($tasks | Sort-Object updated_at, created_at -Descending | Select-Object -First 1)
    }
    $task = if ($null -ne $selectedTask -and @($selectedTask).Count -gt 0) { @($selectedTask)[0] } else { $null }

    $resolvedObjectiveId = if ($objective -and $objective.PSObject.Properties["id"]) { [string]$objective.id } else { "" }
    $resolvedTaskId = if ($task -and $task.PSObject.Properties["id"]) { [string]$task.id } else { "" }

    $research = Get-TodResearchPayload -State $State -Top $safeTop
    $resourcing = Get-TodResourcingPayload -State $State -ObjectiveId $resolvedObjectiveId -TaskId $resolvedTaskId -Top $safeTop

    $taskCategory = if ($task) { Resolve-TaskCategory -Task $task } else { "code_change" }
    $packagePath = ""
    $packageContent = ""
    if (-not [string]::IsNullOrWhiteSpace($resolvedTaskId)) {
        try {
            $packagePath = Resolve-TaskPackagePath -TaskId $resolvedTaskId -ExplicitPath ""
            if (Test-Path -Path $packagePath) {
                $packageContent = [string](Get-Content -Path $packagePath -Raw)
            }
        }
        catch {
            $packagePath = ""
            $packageContent = ""
        }
    }

    $timestampSlug = (Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmmss")
    $sandboxPath = if (-not [string]::IsNullOrWhiteSpace($resolvedTaskId)) {
        "projects/tod/docs/engineer-runs/{0}.md" -f $resolvedTaskId
    }
    else {
        "projects/tod/docs/engineer-runs/run-{0}.md" -f $timestampSlug
    }

    $effectiveBody = ""
    if (-not [string]::IsNullOrWhiteSpace([string]$Body)) {
        $effectiveBody = [string]$Body
    }
    elseif (-not [string]::IsNullOrWhiteSpace($packageContent)) {
        $effectiveBody = $packageContent
    }
    else {
        $effectiveBody = @(
            "# TOD Engineer Run Draft"
            ""
            "- generated_at: $(Get-UtcNow)"
            "- objective_id: $resolvedObjectiveId"
            "- task_id: $resolvedTaskId"
            "- task_category: $taskCategory"
            ""
            "## Work Plan"
            "1. Confirm acceptance criteria"
            "2. Implement scoped changes"
            "3. Run regression tests"
            "4. Prepare review summary"
        ) -join [Environment]::NewLine
    }

    $plan = Invoke-TodSandboxPlanWrite -RelativePath $sandboxPath -Body $effectiveBody -Append:$Append
    $applyResult = $null
    if ($ApplyPlan) {
        Assert-DangerousActionApproved -Config $Config -ActionName "sandbox-apply-plan" -DangerousApproved:$DangerousApproved
        $applyResult = Invoke-TodSandboxApplyPlan -PlanPath ([string]$plan.artifact_path)
    }

    $phaseCreate = if (($objective -ne $null) -or ($task -ne $null)) { "ready" } else { "missing_context" }
    $phaseImplement = if ($ApplyPlan) { "applied" } else { "planned_only" }

    return [pscustomobject]@{
        path = "/tod/engineer/run"
        service = "tod"
        source = "engineer_run_v1"
        generated_at = Get-UtcNow
        run_id = "ENGRUN-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 10).ToUpperInvariant())
        focus = [pscustomobject]@{
            objective_id = $resolvedObjectiveId
            objective_title = if ($objective -and $objective.PSObject.Properties["title"]) { [string]$objective.title } else { "" }
            task_id = $resolvedTaskId
            task_title = if ($task -and $task.PSObject.Properties["title"]) { [string]$task.title } else { "" }
            task_category = $taskCategory
        }
        phases = [pscustomobject]@{
            create = [pscustomobject]@{ status = $phaseCreate; evidence = @("objective_context", "task_context") }
            plan = [pscustomobject]@{ status = "planned"; artifact_path = [string]$plan.artifact_path; sandbox_path = [string]$plan.sandbox_path }
            implement = [pscustomobject]@{ status = $phaseImplement; apply_requested = [bool]$ApplyPlan; apply_result = $applyResult }
            test = [pscustomobject]@{ status = "pending_validation"; commands = @('powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-TODTests.ps1 -Path "tests/*.Tests.ps1"') }
            manage = [pscustomobject]@{ status = "recorded"; journal_action = "engineer_run" }
        }
        package = [pscustomobject]@{
            available = (-not [string]::IsNullOrWhiteSpace($packagePath))
            package_path = $packagePath
        }
        research_snapshot = [pscustomobject]@{
            repository_indexed = if ($research -and $research.PSObject.Properties["repository"] -and $research.repository.PSObject.Properties["indexed"]) { [bool]$research.repository.indexed } else { $false }
            top_prompts = if ($research -and $research.PSObject.Properties["exploration"] -and $research.exploration.PSObject.Properties["research_prompts"]) { @($research.exploration.research_prompts | Select-Object -First 3) } else { @() }
        }
        resourcing_snapshot = [pscustomobject]@{
            target_skills = if ($resourcing -and $resourcing.PSObject.Properties["demand_profile"] -and $resourcing.demand_profile.PSObject.Properties["target_skills"]) { @($resourcing.demand_profile.target_skills) } else { @() }
            channels = if ($resourcing -and $resourcing.PSObject.Properties["external_resourcing"] -and $resourcing.external_resourcing.PSObject.Properties["channels"]) { @($resourcing.external_resourcing.channels) } else { @() }
        }
    }
}

function Get-TodEngineerScorecardPayload {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)]$Config,
        [int]$Top = 25
    )

    $safeTop = if ($Top -lt 1) { 1 } elseif ($Top -gt 200) { 200 } else { $Top }
    $approvalSummary = Get-PendingApprovalRuntimeSummary -State $State
    $journal = if ($State.PSObject.Properties["journal"]) { @($State.journal | Sort-Object created_at -Descending | Select-Object -First $safeTop) } else { @() }
    $actions = @($journal | ForEach-Object {
            if ($_.PSObject.Properties["action"] -and -not [string]::IsNullOrWhiteSpace([string]$_.action)) {
                ([string]$_.action).ToLowerInvariant()
            }
        })

    $countMatches = {
        param([string[]]$Needles)
        return [int]@($actions | Where-Object { $Needles -contains $_ }).Count
    }

    $createCount = (& $countMatches @("new_objective", "new_objective_local", "new_objective_remote", "add_task", "add_task_local", "add_task_remote"))
    $planCount = (& $countMatches @("package_task", "sandbox_plan", "engineer_run"))
    $implementCount = (& $countMatches @("invoke_engine", "run_task", "sandbox_apply_plan", "sandbox_write", "engineer_run"))
    $testCount = (& $countMatches @("add_result", "review_task", "review_task_local", "review_task_remote"))
    $manageCount = (& $countMatches @("show_journal", "sync_mim", "compare_manifest", "engineer_run"))

    $scoreFrom = {
        param([int]$Count, [int]$Target)
        if ($Target -le 0) { return 0.0 }
        return [math]::Round([math]::Min(1.0, ([double]$Count / [double]$Target)), 4)
    }

    $createScore = (& $scoreFrom $createCount 3)
    $planScore = (& $scoreFrom $planCount 3)
    $implementScore = (& $scoreFrom $implementCount 3)
    $testScore = (& $scoreFrom $testCount 3)
    $manageScore = (& $scoreFrom $manageCount 3)

    $dimensionWeights = [ordered]@{
        create = 0.2
        plan = 0.2
        implement = 0.2
        test = 0.2
        manage = 0.2
    }

    $baseScore = [math]::Round((
            ($createScore * [double]$dimensionWeights.create) +
            ($planScore * [double]$dimensionWeights.plan) +
            ($implementScore * [double]$dimensionWeights.implement) +
            ($testScore * [double]$dimensionWeights.test) +
            ($manageScore * [double]$dimensionWeights.manage)
        ), 4)

    $reviewDecisions = if ($State.PSObject.Properties["review_decisions"]) { @($State.review_decisions | Sort-Object created_at -Descending | Select-Object -First $safeTop) } else { @() }
    $reviseOrEscalate = @($reviewDecisions | Where-Object {
            $_.PSObject.Properties["decision"] -and
            @("revise", "escalate") -contains ([string]$_.decision).ToLowerInvariant()
        })
    $decisionRate = if (@($reviewDecisions).Count -gt 0) { [double](@($reviseOrEscalate).Count) / [double](@($reviewDecisions).Count) } else { 0.0 }

    $driftWarnings = @()
    try {
        $dashboard = Build-ReliabilityDashboardReport -State $State -Config $Config -Window $safeTop -CategoryFilter "" -EngineFilter ""
        if ($dashboard -and $dashboard.PSObject.Properties["drift_warnings"]) {
            $driftWarnings = @($dashboard.drift_warnings)
        }
    }
    catch {
        $driftWarnings = @()
    }

    $penalties = @()
    $driftPenalty = [math]::Round([math]::Min(0.15, (@($driftWarnings).Count * 0.03)), 4)
    if ($driftPenalty -gt 0.0) {
        $penalties += [pscustomobject]@{ reason = "reliability_drift"; value = $driftPenalty; detail = "Active drift warnings in reliability dashboard." }
    }

    $reviewPenalty = 0.0
    if ($decisionRate -ge 0.4) {
        $reviewPenalty = 0.1
    }
    elseif ($decisionRate -ge 0.2) {
        $reviewPenalty = 0.05
    }
    if ($reviewPenalty -gt 0.0) {
        $penalties += [pscustomobject]@{ reason = "review_rework_rate"; value = $reviewPenalty; detail = "Recent review decisions include revise/escalate outcomes." }
    }

    $evidenceTotal = [int]($createCount + $planCount + $implementCount + $testCount + $manageCount)
    $evidencePenalty = if ($evidenceTotal -lt 5) { 0.05 } else { 0.0 }
    if ($evidencePenalty -gt 0.0) {
        $penalties += [pscustomobject]@{ reason = "sparse_evidence"; value = $evidencePenalty; detail = "Limited engineering loop evidence in selected window." }
    }

    $totalPenalty = [math]::Round((@($penalties | ForEach-Object { [double]$_.value } | Measure-Object -Sum).Sum), 4)
    $overall = [math]::Round([math]::Max(0.0, ($baseScore - $totalPenalty)), 4)
    $band = if ($overall -ge 0.8) { "strong" } elseif ($overall -ge 0.6) { "good" } elseif ($overall -ge 0.4) { "emerging" } else { "early" }

    $gaps = @()
    if ($createScore -lt 0.5) { $gaps += "create" }
    if ($planScore -lt 0.5) { $gaps += "plan" }
    if ($implementScore -lt 0.5) { $gaps += "implement" }
    if ($testScore -lt 0.5) { $gaps += "test" }
    if ($manageScore -lt 0.5) { $gaps += "manage" }

    return [pscustomobject]@{
        path = "/tod/engineer/scorecard"
        service = "tod"
        source = "engineer_scorecard_v1"
        generated_at = Get-UtcNow
        window = [int]$safeTop
        overall = [pscustomobject]@{
            score = $overall
            band = $band
            low_areas = @($gaps)
        }
        dimensions = @(
            [pscustomobject]@{ name = "create"; score = $createScore; evidence_count = [int]$createCount; target = 3 },
            [pscustomobject]@{ name = "plan"; score = $planScore; evidence_count = [int]$planCount; target = 3 },
            [pscustomobject]@{ name = "implement"; score = $implementScore; evidence_count = [int]$implementCount; target = 3 },
            [pscustomobject]@{ name = "test"; score = $testScore; evidence_count = [int]$testCount; target = 3 },
            [pscustomobject]@{ name = "manage"; score = $manageScore; evidence_count = [int]$manageCount; target = 3 }
        )
        explainability = [pscustomobject]@{
            model = "weighted_dimensions_with_penalties_v1"
            base_score = $baseScore
            total_penalty = $totalPenalty
            adjusted_score = $overall
            contributions = @(
                [pscustomobject]@{ dimension = "create"; weight = [double]$dimensionWeights.create; contribution = [math]::Round(($createScore * [double]$dimensionWeights.create), 4) },
                [pscustomobject]@{ dimension = "plan"; weight = [double]$dimensionWeights.plan; contribution = [math]::Round(($planScore * [double]$dimensionWeights.plan), 4) },
                [pscustomobject]@{ dimension = "implement"; weight = [double]$dimensionWeights.implement; contribution = [math]::Round(($implementScore * [double]$dimensionWeights.implement), 4) },
                [pscustomobject]@{ dimension = "test"; weight = [double]$dimensionWeights.test; contribution = [math]::Round(($testScore * [double]$dimensionWeights.test), 4) },
                [pscustomobject]@{ dimension = "manage"; weight = [double]$dimensionWeights.manage; contribution = [math]::Round(($manageScore * [double]$dimensionWeights.manage), 4) }
            )
            penalties = @($penalties)
            evidence_summary = [pscustomobject]@{
                evidence_total = $evidenceTotal
                review_decisions_window = [int]@($reviewDecisions).Count
                revise_or_escalate_rate = [math]::Round($decisionRate, 4)
                drift_warning_count = [int]@($driftWarnings).Count
            }
        }
        recommendations = @(
            "Run engineer-run to generate an implementation plan artifact.",
            "Apply plan in sandbox only after reviewing diff_preview.",
            "Run full tests and record outcomes with add-result/review-task."
        )
        recent_actions = @($actions | Select-Object -First 12)
        pending_approvals_total = [int]$approvalSummary.pending_approvals_total
        pending_approvals_low_value = [int]$approvalSummary.pending_approvals_low_value_count
        pending_approvals_promotable = [int]$approvalSummary.pending_approvals_promotable_count
        pending_approvals_stale = [int]$approvalSummary.pending_approvals_stale_count
        approval_source_distribution = $approvalSummary.pending_approvals_by_source
        approval_age_distribution = $approvalSummary.pending_approvals_by_age
        pending_approvals_by_type = $approvalSummary.pending_approvals_by_type
        pending_approvals_by_age = $approvalSummary.pending_approvals_by_age
        pending_approvals_by_source = $approvalSummary.pending_approvals_by_source
        pending_approvals_stale_count = [int]$approvalSummary.pending_approvals_stale_count
        pending_approvals_low_value_count = [int]$approvalSummary.pending_approvals_low_value_count
        pending_approvals_promotable_count = [int]$approvalSummary.pending_approvals_promotable_count
        top_promotable_ids = @($approvalSummary.top_promotable_ids)
        top_low_value_ids = @($approvalSummary.top_low_value_ids)
    }
}

function Resolve-TodSandboxTargetPath {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    if ([string]::IsNullOrWhiteSpace($RelativePath)) {
        throw "-SandboxPath is required"
    }

    $normalized = (($RelativePath -replace "\\", "/").Trim())
    while ($normalized.StartsWith("./")) {
        $normalized = $normalized.Substring(2)
    }

    if ([string]::IsNullOrWhiteSpace($normalized)) {
        throw "Sandbox path cannot be empty after normalization."
    }

    if ($normalized.Contains("..")) {
        throw "Sandbox path cannot contain parent traversal segments."
    }

    $root = Get-TodSandboxRoot
    $candidate = Join-Path $root $normalized
    $rootFull = [System.IO.Path]::GetFullPath($root)
    $targetFull = [System.IO.Path]::GetFullPath($candidate)

    if (-not $targetFull.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Sandbox path escaped allowed root."
    }

    return $targetFull
}

function Get-ProjectScopeFromSandboxPath {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    $normalized = (($RelativePath -replace "\\", "/").Trim())
    while ($normalized.StartsWith("./")) {
        $normalized = $normalized.Substring(2)
    }
    $normalized = $normalized.TrimStart("/")

    if (-not $normalized.StartsWith("projects/", [System.StringComparison]::OrdinalIgnoreCase)) {
        return [pscustomobject]@{
            is_project_scoped = $false
            project_id = ""
            project_relative_path = ""
            normalized_path = $normalized
        }
    }

    $parts = @($normalized.Split("/"))
    if (@($parts).Count -lt 3) {
        throw "Project-scoped sandbox paths must follow projects/<project_id>/<relative_path>."
    }

    $projectId = [string]$parts[1]
    $projectRelative = (($parts[2..($parts.Length - 1)]) -join "/")
    if ([string]::IsNullOrWhiteSpace($projectId) -or [string]::IsNullOrWhiteSpace($projectRelative)) {
        throw "Project-scoped sandbox path is missing project ID or relative path."
    }

    return [pscustomobject]@{
        is_project_scoped = $true
        project_id = $projectId
        project_relative_path = $projectRelative
        normalized_path = $normalized
    }
}

function Assert-ProjectAccessPolicyForSandboxPath {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [ValidateSet("read", "write", "delete", "rename")]
        [string]$Operation = "write",
        [bool]$EnforceExecutionMode = $true
    )

    $scope = Get-ProjectScopeFromSandboxPath -RelativePath $RelativePath
    if (-not [bool]$scope.is_project_scoped) {
        if ($Operation -in @("write", "delete", "rename")) {
            throw "Project-scoped path required for mutation. Use projects/<project_id>/<relative_path>."
        }

        return [pscustomobject]@{
            enforced = $false
            operation = $Operation
            project_id = ""
            project_relative_path = ""
            ok = $true
            reason = "non_project_scoped_path"
        }
    }

    if (-not (Test-Path -Path $projectAccessPolicyScript)) {
        throw "Missing project access policy script: $projectAccessPolicyScript"
    }

    $executionMode = "guarded-write"
    if (Test-Path -Path $projectPriorityPath) {
        try {
            $priority = (Get-Content -Path $projectPriorityPath -Raw | ConvertFrom-Json)
            if ($priority -and $priority.PSObject.Properties["execution_order"]) {
                $entry = @($priority.execution_order | Where-Object { [string]$_.project_id -eq [string]$scope.project_id } | Select-Object -First 1)
                if (@($entry).Count -gt 0 -and $entry[0].PSObject.Properties["mode"] -and -not [string]::IsNullOrWhiteSpace([string]$entry[0].mode)) {
                    $executionMode = ([string]$entry[0].mode).ToLowerInvariant()
                }
            }
        }
        catch {
            throw "Failed to load project priority config: $($_.Exception.Message)"
        }
    }

    if ($EnforceExecutionMode -and ($Operation -in @("write", "delete", "rename"))) {
        if ($executionMode -eq "review-only") {
            throw "Execution mode blocks mutation for project '$($scope.project_id)': mode=review-only."
        }
        if ($executionMode -eq "advisory-first") {
            throw "Execution mode blocks direct mutation for project '$($scope.project_id)': mode=advisory-first."
        }
    }

    $raw = & $projectAccessPolicyScript -ProjectId ([string]$scope.project_id) -RelativePaths @([string]$scope.project_relative_path) -Operation $Operation -RegistryPath "tod/config/project-registry.json"
    $policy = $raw | ConvertFrom-Json
    if (-not $policy -or -not $policy.PSObject.Properties["ok"] -or -not [bool]$policy.ok) {
        $blockedPath = [string]$scope.project_relative_path
        throw "Project access policy blocked operation '$Operation' for project '$($scope.project_id)' at '$blockedPath'."
    }

    return [pscustomobject]@{
        enforced = $true
        operation = $Operation
        project_id = [string]$scope.project_id
        project_relative_path = [string]$scope.project_relative_path
        ok = [bool]$policy.ok
        execution_mode = $executionMode
        write_access = if ($policy.PSObject.Properties["write_access"]) { [string]$policy.write_access } else { "" }
        risk_level = if ($policy.PSObject.Properties["risk_level"]) { [string]$policy.risk_level } else { "" }
    }
}

function Get-TodSandboxListPayload {
    param([int]$Top = 25)

    $safeTop = if ($Top -lt 1) { 1 } elseif ($Top -gt 200) { 200 } else { $Top }
    $root = Get-TodSandboxRoot
    $rootFull = [System.IO.Path]::GetFullPath($root)

    $files = @()
    if (Test-Path -Path $root) {
        $files = @(Get-ChildItem -Path $root -File -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First $safeTop)
    }

    $items = @($files | ForEach-Object {
            $full = [System.IO.Path]::GetFullPath([string]$_.FullName)
            $relative = $full.Substring($rootFull.Length).TrimStart([char[]]@([char]92, [char]47))
            [pscustomobject]@{
                path = ($relative -replace "\\", "/")
                bytes = [int64]$_.Length
                updated_at = ([datetime]$_.LastWriteTimeUtc).ToString("o")
            }
        })

    return [pscustomobject]@{
        path = "/tod/sandbox/files"
        service = "tod"
        source = "sandbox_files_v1"
        generated_at = Get-UtcNow
        root = "tod/sandbox/workspace"
        file_count = @($items).Count
        files = @($items)
    }
}

function Convert-ToSandboxRelativePath {
    param([Parameter(Mandatory = $true)][string]$FullPath)

    $root = Get-TodSandboxRoot
    $rootFull = [System.IO.Path]::GetFullPath($root)
    $pathFull = [System.IO.Path]::GetFullPath($FullPath)
    $relative = $pathFull.Substring($rootFull.Length).TrimStart([char[]]@([char]92, [char]47))
    return ($relative -replace "\\", "/")
}

function Get-StringSha256 {
    param([string]$Value)

    $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$Value)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash($bytes)
    }
    finally {
        $sha.Dispose()
    }

    return ([System.BitConverter]::ToString($hash).Replace("-", "").ToLowerInvariant())
}

function New-TodSandboxDiffPreview {
    param(
        [string]$Before,
        [string]$After,
        [int]$MaxLines = 120
    )

    [string[]]$beforeLines = if ([string]::IsNullOrEmpty($Before)) { @("") } else { @([regex]::Split($Before, "`r?`n")) }
    [string[]]$afterLines = if ([string]::IsNullOrEmpty($After)) { @("") } else { @([regex]::Split($After, "`r?`n")) }

    $rows = @(Compare-Object -ReferenceObject $beforeLines -DifferenceObject $afterLines)
    if (@($rows).Count -eq 0) {
        return @("~ no textual changes")
    }

    $lines = @()
    foreach ($row in $rows) {
        $symbol = if ([string]$row.SideIndicator -eq "=>") { "+" } else { "-" }
        $lines += ("{0} {1}" -f $symbol, [string]$row.InputObject)
    }

    if (@($lines).Count -gt $MaxLines) {
        $truncated = @($lines | Select-Object -First $MaxLines)
        $truncated += ("... ({0} additional diff lines omitted)" -f (@($lines).Count - $MaxLines))
        return $truncated
    }

    return $lines
}

function Invoke-TodSandboxPlanWrite {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$Body,
        [switch]$Append
    )

    $policyCheck = Assert-ProjectAccessPolicyForSandboxPath -RelativePath $RelativePath -Operation "write" -EnforceExecutionMode $false
    $target = Resolve-TodSandboxTargetPath -RelativePath $RelativePath
    $beforeExists = Test-Path -Path $target
    $beforeText = if ($beforeExists) { [string](Get-Content -Path $target -Raw) } else { "" }

    $afterText = if ($Append -and $beforeExists) {
        if ([string]::IsNullOrEmpty($beforeText)) { [string]$Body } else { $beforeText + [Environment]::NewLine + [string]$Body }
    }
    else {
        [string]$Body
    }

    $artifactRoot = Join-Path $repoRoot "tod/sandbox/artifacts"
    if (-not (Test-Path -Path $artifactRoot)) {
        New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null
    }

    $planId = "PLAN-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 10).ToUpperInvariant())
    $artifactFile = Join-Path $artifactRoot ("{0}.json" -f $planId)
    $targetRelative = Convert-ToSandboxRelativePath -FullPath $target

    $appendArg = if ($Append) { " -Append" } else { "" }

    $payload = [pscustomobject]@{
        path = "/tod/sandbox/plan"
        service = "tod"
        source = "sandbox_plan_v1"
        generated_at = Get-UtcNow
        plan_id = $planId
        sandbox_path = $targetRelative
        mode = if ($Append) { "append" } else { "overwrite" }
        will_create = (-not $beforeExists)
        current_bytes = [int]([System.Text.Encoding]::UTF8.GetByteCount($beforeText))
        planned_bytes = [int]([System.Text.Encoding]::UTF8.GetByteCount($afterText))
        current_sha256 = Get-StringSha256 -Value $beforeText
        planned_sha256 = Get-StringSha256 -Value $afterText
        diff_preview = @(New-TodSandboxDiffPreview -Before $beforeText -After $afterText -MaxLines 120)
        planned_content = $afterText
        artifact_path = ("tod/sandbox/artifacts/{0}.json" -f $planId)
        apply_command = (".\\scripts\\TOD.ps1 -Action sandbox-write -SandboxPath `"{0}`" -Content `"<content>`"{1}" -f $targetRelative, $appendArg)
        policy_check = $policyCheck
    }

    $payload | ConvertTo-Json -Depth 20 | Set-Content -Path $artifactFile
    return $payload
}

function Resolve-TodSandboxPlanArtifactPath {
    param([Parameter(Mandatory = $true)][string]$PlanPath)

    $artifactRoot = Join-Path $repoRoot "tod/sandbox/artifacts"
    if (-not (Test-Path -Path $artifactRoot)) {
        New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null
    }

    $clean = (($PlanPath -replace "\\", "/").Trim())
    while ($clean.StartsWith("./")) {
        $clean = $clean.Substring(2)
    }

    if ([string]::IsNullOrWhiteSpace($clean)) {
        throw "-SandboxPlanPath cannot be empty."
    }

    if ($clean.Contains("..")) {
        throw "Sandbox plan path cannot contain parent traversal segments."
    }

    $candidate = if ([System.IO.Path]::IsPathRooted($clean)) {
        $clean
    }
    else {
        if ($clean.StartsWith("tod/sandbox/artifacts/")) {
            Join-Path $repoRoot ($clean -replace "/", "\\")
        }
        elseif ($clean.StartsWith("PLAN-")) {
            Join-Path $artifactRoot ($clean + ".json")
        }
        else {
            Join-Path $artifactRoot ($clean -replace "/", "\\")
        }
    }

    $full = [System.IO.Path]::GetFullPath($candidate)
    $artifactRootFull = [System.IO.Path]::GetFullPath($artifactRoot)
    if (-not $full.StartsWith($artifactRootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Sandbox plan artifact path escaped allowed root."
    }

    if (-not $full.EndsWith(".json", [System.StringComparison]::OrdinalIgnoreCase)) {
        $full = $full + ".json"
    }

    return $full
}

function Invoke-TodSandboxApplyPlan {
    param([Parameter(Mandatory = $true)][string]$PlanPath)

    $artifactPath = Resolve-TodSandboxPlanArtifactPath -PlanPath $PlanPath
    if (-not (Test-Path -Path $artifactPath)) {
        throw "Sandbox plan artifact not found: $artifactPath"
    }

    $plan = (Get-Content -Path $artifactPath -Raw) | ConvertFrom-Json
    if (-not $plan -or -not $plan.PSObject.Properties["sandbox_path"]) {
        throw "Invalid sandbox plan artifact."
    }

    $policyCheck = Assert-ProjectAccessPolicyForSandboxPath -RelativePath ([string]$plan.sandbox_path) -Operation "write"
    $target = Resolve-TodSandboxTargetPath -RelativePath ([string]$plan.sandbox_path)
    $beforeExists = Test-Path -Path $target
    $beforeText = if ($beforeExists) { [string](Get-Content -Path $target -Raw) } else { "" }
    $beforeHash = Get-StringSha256 -Value $beforeText
    $expectedCurrent = if ($plan.PSObject.Properties["current_sha256"]) { [string]$plan.current_sha256 } else { "" }

    if (-not [string]::IsNullOrWhiteSpace($expectedCurrent) -and -not $beforeHash.Equals($expectedCurrent, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Sandbox plan apply rejected: current content hash does not match plan baseline."
    }

    if (-not $plan.PSObject.Properties["planned_content"]) {
        throw "Sandbox plan artifact missing planned_content."
    }

    $parent = Split-Path -Parent $target
    if (-not (Test-Path -Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $plannedText = [string]$plan.planned_content
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($target, $plannedText, $utf8NoBom)

    $afterText = [string](Get-Content -Path $target -Raw)
    $afterHash = Get-StringSha256 -Value $afterText
    $expectedPlanned = if ($plan.PSObject.Properties["planned_sha256"]) { [string]$plan.planned_sha256 } else { "" }
    if (-not [string]::IsNullOrWhiteSpace($expectedPlanned) -and -not $afterHash.Equals($expectedPlanned, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Sandbox plan apply failed: written content hash does not match planned hash."
    }

    return [pscustomobject]@{
        path = "/tod/sandbox/apply"
        service = "tod"
        source = "sandbox_apply_v1"
        generated_at = Get-UtcNow
        applied = $true
        plan_id = if ($plan.PSObject.Properties["plan_id"]) { [string]$plan.plan_id } else { "" }
        sandbox_path = Convert-ToSandboxRelativePath -FullPath $target
        artifact_path = (("tod/sandbox/artifacts/{0}" -f ([System.IO.Path]::GetFileName($artifactPath))) -replace "\\", "/")
        bytes = [int]([System.Text.Encoding]::UTF8.GetByteCount($afterText))
        sha256 = $afterHash
        policy_check = $policyCheck
    }
}

function Invoke-TodSandboxWrite {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$Body,
        [switch]$Append
    )

    $policyCheck = Assert-ProjectAccessPolicyForSandboxPath -RelativePath $RelativePath -Operation "write"
    $target = Resolve-TodSandboxTargetPath -RelativePath $RelativePath
    $parent = Split-Path -Parent $target
    if (-not (Test-Path -Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    if ($Append -and (Test-Path -Path $target)) {
        Add-Content -Path $target -Value $Body
    }
    else {
        Set-Content -Path $target -Value $Body
    }

    $hash = (Get-FileHash -Path $target -Algorithm SHA256).Hash.ToLowerInvariant()
    $root = Get-TodSandboxRoot
    $rootFull = [System.IO.Path]::GetFullPath($root)
    $relative = ([System.IO.Path]::GetFullPath($target)).Substring($rootFull.Length).TrimStart([char[]]@([char]92, [char]47))

    return [pscustomobject]@{
        path = "/tod/sandbox/write"
        service = "tod"
        source = "sandbox_write_v1"
        generated_at = Get-UtcNow
        sandbox_path = ($relative -replace "\\", "/")
        bytes = [int64](Get-Item -Path $target).Length
        sha256 = $hash
        append = [bool]$Append
        policy_check = $policyCheck
    }
}

function Get-TodStateBusPayload {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)]$State,
        [int]$Top = 10
    )

    $safeTop = if ($Top -lt 1) { 1 } elseif ($Top -gt 100) { 100 } else { $Top }

    $objectives = if ($State.PSObject.Properties["objectives"]) { @($State.objectives) } else { @() }
    $tasks = if ($State.PSObject.Properties["tasks"]) { @($State.tasks) } else { @() }
    $reviews = if ($State.PSObject.Properties["reviews"]) { @($State.reviews) } else { @() }
    $results = if ($State.PSObject.Properties["execution_results"]) { @($State.execution_results) } else { @() }
    $journal = if ($State.PSObject.Properties["journal"]) { @($State.journal) } else { @() }
    $routingRecords = if ($State.PSObject.Properties["routing_decisions"]) { @($State.routing_decisions) } else { @() }

    $sortedObjectives = @($objectives | Sort-Object created_at -Descending)
    $currentObjective = @($sortedObjectives | Select-Object -First 1)
    $currentObjectiveId = if (@($currentObjective).Count -gt 0) { [string]$currentObjective[0].id } else { "" }
    $taskPartition = if ([string]::IsNullOrWhiteSpace($currentObjectiveId)) {
        [pscustomobject]@{ all = @(); canonical = @(); bridge_runtime = @() }
    }
    else {
        Get-ObjectiveTaskPartition -Tasks $tasks -ObjectiveId $currentObjectiveId
    }
    $objectiveTasks = @($taskPartition.canonical)
    $bridgeRuntimeTasks = @($taskPartition.bridge_runtime)

    $taskStatusCounts = Get-TaskStatusBreakdown -Tasks $objectiveTasks
    $bridgeRuntimeStatusCounts = Get-TaskStatusBreakdown -Tasks $bridgeRuntimeTasks

    $activeTask = Get-PreferredTaskSelection -Tasks @($objectiveTasks | Where-Object {
            $_.PSObject.Properties['status'] -and
            ([string]$_.status).ToLowerInvariant() -eq 'in_progress'
        })
    if (@($activeTask).Count -eq 0) {
        $activeTask = Get-PreferredTaskSelection -Tasks @($bridgeRuntimeTasks | Where-Object {
                $_.PSObject.Properties['status'] -and
                ([string]$_.status).ToLowerInvariant() -eq 'in_progress'
            })
    }
    if (@($activeTask).Count -eq 0) {
        $activeTask = Get-PreferredTaskSelection -Tasks $objectiveTasks
    }
    if (@($activeTask).Count -eq 0) {
        $activeTask = Get-PreferredTaskSelection -Tasks $bridgeRuntimeTasks
    }
    if (@($activeTask).Count -eq 0) {
        $activeTask = Get-PreferredTaskSelection -Tasks $tasks
    }

    $pendingReviews = @($tasks | Where-Object {
            $_.PSObject.Properties["status"] -and
            (([string]$_.status).ToLowerInvariant() -eq "implemented")
        })

    $recentRouting = @($routingRecords | Sort-Object timestamp -Descending | Select-Object -First $safeTop)
    $recentJournal = @($journal | Sort-Object timestamp -Descending | Select-Object -First $safeTop)

    $currentAlertState = "stable"
    $driftWarnings = @()
    try {
        $dashboard = Build-ReliabilityDashboardReport -State $State -Config $Config -Window $safeTop -CategoryFilter "" -EngineFilter ""
        if ($dashboard -and $dashboard.PSObject.Properties["retry_trend"]) {
            $maxRank = 0
            foreach ($item in @($dashboard.retry_trend)) {
                $alert = if ($item.PSObject.Properties["alert_state"] -and -not [string]::IsNullOrWhiteSpace([string]$item.alert_state)) { [string]$item.alert_state } else { "stable" }
                $rank = Get-AlertSeverityRank -State $alert
                if ($rank -gt $maxRank) {
                    $maxRank = $rank
                    $currentAlertState = $alert
                }
            }
        }
        if ($dashboard -and $dashboard.PSObject.Properties["drift_warnings"]) {
            $driftWarnings = @($dashboard.drift_warnings)
        }
    }
    catch {
        $currentAlertState = "stable"
        $driftWarnings = @()
    }

    $candidateExecutions = @()
    foreach ($task in $tasks) {
        if ($task.PSObject.Properties["execution_id"] -and -not [string]::IsNullOrWhiteSpace([string]$task.execution_id)) {
            $candidateExecutions += [string]$task.execution_id
        }
        elseif ($task.PSObject.Properties["remote_execution_id"] -and -not [string]::IsNullOrWhiteSpace([string]$task.remote_execution_id)) {
            $candidateExecutions += [string]$task.remote_execution_id
        }
    }
    $executionIds = @($candidateExecutions | Select-Object -Unique)

    $activeGoals = @($objectives | Where-Object {
            $_.PSObject.Properties["status"] -and
            @("open", "active", "in_progress", "planned") -contains ([string]$_.status).ToLowerInvariant()
        })
    $activeGoalCount = @($activeGoals).Count

    $activeExecutionCount = @($executionIds).Count
    if ($activeExecutionCount -eq 0 -and @($activeTask).Count -gt 0) {
        $activeTaskStatus = if ($activeTask[0].PSObject.Properties["status"]) { ([string]$activeTask[0].status).ToLowerInvariant() } else { "" }
        if ($activeTaskStatus -eq "in_progress") {
            $activeExecutionCount = 1
        }
    }

    $resolvedMode = if ($Config.PSObject.Properties["mode"] -and -not [string]::IsNullOrWhiteSpace([string]$Config.mode)) { ([string]$Config.mode).ToLowerInvariant() } else { "local" }
    $isRemoteAuthority = ($resolvedMode -eq "remote" -or $resolvedMode -eq "hybrid")

    $contractDriftBlocking = if ($State -and $State.PSObject.Properties["sync_state"] -and $State.sync_state -and $State.sync_state.PSObject.Properties["last_comparison"] -and $State.sync_state.last_comparison) {
        $comparison = $State.sync_state.last_comparison
        ($comparison.PSObject.Properties["status"] -and ([string]$comparison.status).ToLowerInvariant() -eq "breaking")
    }
    else {
        $false
    }

    $guardrailBlockCandidates = @($recentRouting | Where-Object {
            $_.PSObject.Properties["final_outcome"] -and
            ([string]$_.final_outcome).ToLowerInvariant() -eq "blocked_pre_invocation"
        }).Count

    $engineeringLoop = if ($State.PSObject.Properties["engineering_loop"]) { $State.engineering_loop } else { $null }
    $engineeringHistory = Read-EngineeringLoopHistoryStore -State $State -PreferState
    $runHistory = @($engineeringHistory.run_history)
    $scorecardHistory = @($engineeringHistory.scorecard_history)
    $cycleRecords = @($engineeringHistory.cycle_records)
    $reviewActions = @($engineeringHistory.review_actions)
    $recentRuns = @($runHistory | Sort-Object generated_at -Descending | Select-Object -First 5)
    $recentScorecards = @($scorecardHistory | Sort-Object generated_at -Descending | Select-Object -First 5)
    $recentCycles = @($cycleRecords | Sort-Object created_at -Descending | Select-Object -First 5)
    $recentReviews = @($reviewActions | Sort-Object created_at -Descending | Select-Object -First 5)
    $lastRun = if (@($recentRuns).Count -gt 0) { $recentRuns[0] } elseif ($null -ne $engineeringHistory.last_run) { $engineeringHistory.last_run } elseif ($engineeringLoop -and $engineeringLoop.PSObject.Properties["last_run"]) { $engineeringLoop.last_run } else { $null }
    $lastScorecard = if (@($recentScorecards).Count -gt 0) { $recentScorecards[0] } elseif ($null -ne $engineeringHistory.last_scorecard) { $engineeringHistory.last_scorecard } elseif ($engineeringLoop -and $engineeringLoop.PSObject.Properties["last_scorecard"]) { $engineeringLoop.last_scorecard } else { $null }
    $lastCycle = if (@($recentCycles).Count -gt 0) { $recentCycles[0] } elseif ($null -ne $engineeringHistory.last_cycle) { $engineeringHistory.last_cycle } elseif ($engineeringLoop -and $engineeringLoop.PSObject.Properties["last_cycle"]) { $engineeringLoop.last_cycle } else { $null }

    $latestScore = if ($lastScorecard -and $lastScorecard.PSObject.Properties["score"] -and $null -ne $lastScorecard.score) { [double]$lastScorecard.score } else { $null }
    $trendDirection = "flat"
    $trendDelta = 0.0
    if (@($recentScorecards).Count -ge 2) {
        $oldestScore = [double]$recentScorecards[@($recentScorecards).Count - 1].score
        $newestScore = [double]$recentScorecards[0].score
        $trendDelta = [math]::Round(($newestScore - $oldestScore), 4)
        if ($trendDelta -gt 0.03) {
            $trendDirection = "improving"
        }
        elseif ($trendDelta -lt -0.03) {
            $trendDirection = "declining"
        }
    }

    $engineeringLoopStatus = if (@($runHistory).Count -eq 0) {
        "idle"
    }
    elseif ($latestScore -ne $null -and $latestScore -ge 0.8) {
        "strong"
    }
    elseif ($latestScore -ne $null -and $latestScore -ge 0.6) {
        "active"
    }
    else {
        "warming"
    }
        $pendingApprovalCount = [int]@($cycleRecords | Where-Object {
            $null -ne $_ -and $_.PSObject.Properties["approval_status"] -and
            ([string]$_.approval_status).ToLowerInvariant() -eq "pending_apply"
        }).Count

    $phaseTrendWindow = @($recentScorecards | Select-Object -First 12)
    $buildPhaseTrend = {
        param([string]$PhaseName)
        return @($phaseTrendWindow | Sort-Object generated_at | ForEach-Object {
                $dims = if ($_.PSObject.Properties["dimensions"] -and $null -ne $_.dimensions) { @($_.dimensions) } else { @() }
                $dim = @($dims | Where-Object { [string]$_.name -eq $PhaseName } | Select-Object -First 1)
                if (@($dim).Count -gt 0) {
                    [pscustomobject]@{
                        at = if ($_.PSObject.Properties["generated_at"]) { [string]$_.generated_at } else { "" }
                        score = [double]$dim[0].score
                    }
                }
            })
    }
    $phaseTrends = [pscustomobject]@{
        create = (& $buildPhaseTrend "create")
        plan = (& $buildPhaseTrend "plan")
        implement = (& $buildPhaseTrend "implement")
        test = (& $buildPhaseTrend "test")
        manage = (& $buildPhaseTrend "manage")
    }

    $topPenalties = if ($lastScorecard -and $lastScorecard.PSObject.Properties["penalties"]) {
        @($lastScorecard.penalties | Select-Object -First 3)
    }
    elseif ($lastCycle -and $lastCycle.PSObject.Properties["top_penalties"]) {
        @($lastCycle.top_penalties | Select-Object -First 3)
    }
    else {
        @()
    }

    $stopThreshold = if ($Config.PSObject.Properties["engineering_loop"] -and $Config.engineering_loop -and $Config.engineering_loop.PSObject.Properties["autonomy"] -and $Config.engineering_loop.autonomy -and $Config.engineering_loop.autonomy.PSObject.Properties["stop_at_score"]) {
        [double]$Config.engineering_loop.autonomy.stop_at_score
    }
    else {
        0.85
    }
    $thresholdState = if ($latestScore -ne $null -and [double]$latestScore -ge $stopThreshold) { "met" } else { "awaiting" }

    $worldConfidence = if (@($currentObjective).Count -gt 0) { 0.92 } else { 0.75 }
    if ($isRemoteAuthority) { $worldConfidence -= 0.08 }

    $intentConfidence = if (@($objectiveTasks).Count -gt 0) { 0.9 } else { 0.78 }
    if ($isRemoteAuthority) { $intentConfidence -= 0.05 }

    $executionConfidence = if (@($executionIds).Count -gt 0) { 0.86 } elseif (@($activeTask).Count -gt 0) { 0.8 } else { 0.72 }
    $reliabilityConfidence = if (@($driftWarnings).Count -gt 0) { 0.78 } else { 0.9 }
    $blocksConfidence = if ($contractDriftBlocking -or $guardrailBlockCandidates -gt 0) { 0.9 } else { 0.84 }
    $engineeringConfidence = if ((@($runHistory).Count -gt 0) -or (@($scorecardHistory).Count -gt 0)) { 0.93 } else { 0.76 }

    $agentAvailability = "idle"
    if ($currentAlertState -eq "critical" -or $currentAlertState -eq "degraded") {
        $agentAvailability = "degraded"
    }
    elseif ($activeExecutionCount -gt 0) {
        $agentAvailability = "busy"
    }
    elseif ((@($tasks).Count -gt 0) -or (@($objectives).Count -gt 0)) {
        $agentAvailability = "awake"
    }

    $executorHealth = switch ($currentAlertState) {
        "critical" { "critical" }
        "degraded" { "degraded" }
        "warning" { "watch" }
        default { "healthy" }
    }

    $pendingConfirmations = @($pendingReviews).Count
    $contractDriftBlockCount = 0
    if ($contractDriftBlocking) {
        $contractDriftBlockCount = 1
    }
    $blockedItems = [int]$guardrailBlockCandidates + [int]$contractDriftBlockCount
    $capabilityEndpoints = @(
        "/tod/reliability",
        "/tod/capabilities",
        "/tod/research",
        "/tod/resourcing",
        "/tod/engineer/run",
        "/tod/engineer/scorecard",
        "/tod/engineer/summary",
        "/tod/engineer/signal",
        "/tod/engineer/history",
        "/tod/engineer/cycle",
        "/tod/engineer/review",
        "/tod/sandbox/files",
        "/tod/sandbox/plan",
        "/tod/sandbox/apply",
        "/tod/sandbox/write",
        "/tod/state-bus",
        "/tod/version"
    )
    $registeredCapabilities = @($capabilityEndpoints).Count

    return [pscustomobject]@{
        path = "/tod/state-bus"
        service = "tod"
        generated_at = Get-UtcNow
        objective_id = $currentObjectiveId
        system_posture = [pscustomobject]@{
            agent_state = $agentAvailability
            current_alert_state = $currentAlertState
            engineering_loop_status = $engineeringLoopStatus
            active_goal_count = [int]$activeGoalCount
            active_execution_count = [int]$activeExecutionCount
            pending_confirmations = [int]$pendingConfirmations
            blocked_items = [int]$blockedItems
            cycle_records_total = [int]@($cycleRecords).Count
            pending_cycle_approvals = [int]$pendingApprovalCount
            engineer_runs_total = [int]@($runHistory).Count
            scorecard_samples_total = [int]@($scorecardHistory).Count
            registered_capabilities = [int]$registeredCapabilities
            current_executor_health = $executorHealth
            summary = "SYSTEM POSTURE | Agent: $agentAvailability | Alert: $currentAlertState | Loop: $engineeringLoopStatus | Executions: $activeExecutionCount active | Pending confirmations: $pendingConfirmations | Cycle approvals pending: $pendingApprovalCount | Blocked items: $blockedItems | Runs: $(@($runHistory).Count) | Scorecards: $(@($scorecardHistory).Count) | Capabilities: $registeredCapabilities registered | Reliability: $executorHealth"
        }
        source_of_truth = [pscustomobject]@{
            mode = $resolvedMode
            world_state = if ($isRemoteAuthority) { "mim_authoritative_with_local_cache" } else { "local_state" }
            intent_state = if ($isRemoteAuthority) { "mim_authoritative_with_local_projection" } else { "local_state" }
            execution_state = if ($isRemoteAuthority) { "hybrid_execution_telemetry" } else { "local_execution_telemetry" }
            reliability_state = "tod_local_derived"
            engineering_loop = "tod_local_history"
            capability_state = "tod_runtime_config"
            agent_state = "tod_runtime_config"
            blocks = "tod_local_guardrails"
        }
        section_confidence = [pscustomobject]@{
            agent_state = 0.98
            world_state = [math]::Round($worldConfidence, 2)
            capability_state = 0.97
            intent_state = [math]::Round($intentConfidence, 2)
            execution_state = [math]::Round($executionConfidence, 2)
            reliability_state = [math]::Round($reliabilityConfidence, 2)
            engineering_loop = [math]::Round($engineeringConfidence, 2)
            blocks = [math]::Round($blocksConfidence, 2)
        }
        agent_state = [pscustomobject]@{
            mode = $resolvedMode
            active_engine = if ($Config.PSObject.Properties["execution_engine"] -and $Config.execution_engine -and $Config.execution_engine.PSObject.Properties["active"]) { [string]$Config.execution_engine.active } else { "codex" }
            fallback_engine = if ($Config.PSObject.Properties["execution_engine"] -and $Config.execution_engine -and $Config.execution_engine.PSObject.Properties["fallback"]) { [string]$Config.execution_engine.fallback } else { "local" }
            current_alert_state = $currentAlertState
        }
        world_state = [pscustomobject]@{
                bridge_runtime = [pscustomobject]@{
                    total = @($bridgeRuntimeTasks).Count
                    by_status = [pscustomobject]$bridgeRuntimeStatusCounts
                }
            objective = if (@($currentObjective).Count -gt 0) { $currentObjective[0] } else { $null }
            objectives_total = @($objectives).Count
            tasks_total = @($tasks).Count
            reviews_total = @($reviews).Count
            results_total = @($results).Count
            journal_total = @($journal).Count
        }
        capability_state = [pscustomobject]@{
            endpoints = @($capabilityEndpoints)
            drift_detection_enabled = $true
            fallback_supported = if ($Config.PSObject.Properties["execution_engine"] -and $Config.execution_engine -and $Config.execution_engine.PSObject.Properties["allow_fallback"]) { [bool]$Config.execution_engine.allow_fallback } else { $false }
        }
        intent_state = [pscustomobject]@{
            objective_id = $currentObjectiveId
            objective_status = if (@($currentObjective).Count -gt 0 -and $currentObjective[0].PSObject.Properties["status"]) { [string]$currentObjective[0].status } else { "unknown" }
            objective_priority = if (@($currentObjective).Count -gt 0 -and $currentObjective[0].PSObject.Properties["priority"]) { [string]$currentObjective[0].priority } else { "" }
            task_funnel = [pscustomobject]@{
                total = @($objectiveTasks).Count
                by_status = [pscustomobject]$taskStatusCounts
                bridge_runtime = [pscustomobject]@{
                    total = @($bridgeRuntimeTasks).Count
                    by_status = [pscustomobject]$bridgeRuntimeStatusCounts
                }
            }
            pending_review_count = @($pendingReviews).Count
        }
        execution_state = [pscustomobject]@{
            active_task = if (@($activeTask).Count -gt 0) { $activeTask[0] } else { $null }
            execution_ids = @($executionIds)
            recent_routing = @($recentRouting)
            recent_journal = @($recentJournal)
        }
        reliability_state = [pscustomobject]@{
            current_alert_state = $currentAlertState
            drift_warning_count = @($driftWarnings).Count
            drift_warnings = @($driftWarnings)
        }
        engineering_loop_state = [pscustomobject]@{
            status = $engineeringLoopStatus
            run_history_count = [int]@($runHistory).Count
            scorecard_history_count = [int]@($scorecardHistory).Count
            cycle_records_count = [int]@($cycleRecords).Count
            review_actions_count = [int]@($reviewActions).Count
            latest_score = $latestScore
            trend_direction = $trendDirection
            trend_delta = $trendDelta
            last_run = $lastRun
            last_scorecard = $lastScorecard
            current_run = $lastRun
            last_cycle_result = $lastCycle
            stop_threshold = $stopThreshold
            stop_threshold_state = $thresholdState
            maturity_band = if ($lastScorecard -and $lastScorecard.PSObject.Properties["band"]) { [string]$lastScorecard.band } else { "early" }
            top_penalties = @($topPenalties)
            approval_pending_flag = ($pendingApprovalCount -gt 0)
            pending_approval_count = [int]$pendingApprovalCount
            phase_trends = $phaseTrends
            recent_runs = @($recentRuns)
            recent_scorecards = @($recentScorecards)
            recent_cycles = @($recentCycles)
            recent_reviews = @($recentReviews)
        }
        blocks = [pscustomobject]@{
            contract_drift_blocking = [bool]$contractDriftBlocking
            routing_guardrail_block_candidates = [int]$guardrailBlockCandidates
            uncertainties = if (@($driftWarnings).Count -gt 0) {
                @($driftWarnings | Select-Object -First 5 | ForEach-Object { [string]$_.message })
            }
            else {
                @()
            }
        }
    }
}

function Convert-EngineAliasLabel {
    param([string]$Engine)

    $normalized = ([string]$Engine).ToLowerInvariant()
    switch ($normalized) {
        "local" { return "local-placeholder" }
        default { return $normalized }
    }
}

function Add-RoutingDecisionRecord {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][string]$TaskId,
        [Parameter(Mandatory = $true)][string]$ActionName,
        [Parameter(Mandatory = $true)]$EngineConfig,
        [Parameter(Mandatory = $true)][string]$TaskCategory,
        [string]$FinalOutcome = "pre_invocation",
        $InvokeResult
    )

    $attempted = @()
    $selectedEngine = [string]$EngineConfig.active
    $fallbackApplied = $false

    if ($null -ne $InvokeResult) {
        if ($InvokeResult.PSObject.Properties["attempted_engines"]) {
            $attempted = @($InvokeResult.attempted_engines | ForEach-Object { [string]$_ })
        }
        if ($InvokeResult.PSObject.Properties["active_engine"] -and -not [string]::IsNullOrWhiteSpace([string]$InvokeResult.active_engine)) {
            $selectedEngine = [string]$InvokeResult.active_engine
        }
        if ($InvokeResult.PSObject.Properties["fallback_applied"]) {
            $fallbackApplied = [bool]$InvokeResult.fallback_applied
        }
    }

    $routingMeta = if ($EngineConfig.PSObject.Properties["routing"]) { $EngineConfig.routing } else { $null }
    $fallbackEngine = if ($EngineConfig.PSObject.Properties["fallback"]) { [string]$EngineConfig.fallback } else { "" }
    $candidateEngines = if ($routingMeta -and $routingMeta.PSObject.Properties["candidate_engines"]) { @($routingMeta.candidate_engines | ForEach-Object { [string]$_ }) } else { @($selectedEngine, $fallbackEngine) }
    $selectionReason = if ($routingMeta -and $routingMeta.PSObject.Properties["selection_reason"]) { [string]$routingMeta.selection_reason } else { "Selected by configured default routing policy." }
    $confidence = if ($routingMeta -and $routingMeta.PSObject.Properties["confidence"]) { [double]$routingMeta.confidence } else { 0.5 }
    $source = if ($routingMeta -and $routingMeta.PSObject.Properties["source"]) { [string]$routingMeta.source } else { "routing_policy_v1" }

    $record = [pscustomobject]@{
        id = "ROUTE-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 8).ToUpperInvariant())
        task_id = [string]$TaskId
        action = [string]$ActionName
        task_category = [string]$TaskCategory
        selected_engine = (Convert-EngineAliasLabel -Engine ([string]$selectedEngine))
        fallback_engine = (Convert-EngineAliasLabel -Engine ([string]$fallbackEngine))
        candidate_engines = @($candidateEngines | ForEach-Object { Convert-EngineAliasLabel -Engine ([string]$_) })
        selection_reason = $selectionReason
        confidence = [math]::Round($confidence, 4)
        source = $source
        attempted_engines = @($attempted)
        fallback_applied = [bool]$fallbackApplied
        final_outcome = [string]$FinalOutcome
        routing = [pscustomobject]@{
            applied = if ($routingMeta -and $routingMeta.PSObject.Properties["applied"]) { [bool]$routingMeta.applied } else { $false }
            reason = if ($routingMeta -and $routingMeta.PSObject.Properties["reason"]) { [string]$routingMeta.reason } else { "unknown" }
            disabled = if ($routingMeta -and $routingMeta.PSObject.Properties["disabled"]) { [bool]$routingMeta.disabled } else { $false }
            blocked = if ($routingMeta -and $routingMeta.PSObject.Properties["blocked"]) { [bool]$routingMeta.blocked } else { $false }
            task_category = [string]$TaskCategory
            policy = if ($routingMeta -and $routingMeta.PSObject.Properties["policy"]) { $routingMeta.policy } else { $null }
            retry_policy = if ($EngineConfig.PSObject.Properties["retry_policy"]) { $EngineConfig.retry_policy } else { $null }
            active_metrics = if ($routingMeta -and $routingMeta.PSObject.Properties["active_metrics"]) { $routingMeta.active_metrics } else { $null }
            fallback_metrics = if ($routingMeta -and $routingMeta.PSObject.Properties["fallback_metrics"]) { $routingMeta.fallback_metrics } else { $null }
        }
        created_at = Get-UtcNow
    }

    $State.routing_decisions.records += $record
    $State.routing_decisions.updated_at = Get-UtcNow
    Sync-RoutingDecisionToEngineeringMemory -State $State -DecisionRecord $record
    return $record
}

function Update-RoutingDecisionRecord {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][string]$RoutingDecisionId,
        [string]$FinalOutcome,
        $InvokeResult
    )

    $targetMatch = @($State.routing_decisions.records | Where-Object {
            $candidate = $_
            if ($null -eq $candidate) {
                return $false
            }

            $propertyNames = if ($candidate.PSObject) { @($candidate.PSObject.Properties.Name) } else { @() }
            if (-not (@($propertyNames) -contains 'id')) {
                return $false
            }

            [string]$candidate.id -eq $RoutingDecisionId
        } | Select-Object -First 1)
    if (@($targetMatch).Count -eq 0) { return $null }
    $target = $targetMatch[0]

    if (-not $target.PSObject.Properties["final_outcome"]) {
        $target | Add-Member -NotePropertyName final_outcome -NotePropertyValue "" -Force
    }
    if (-not $target.PSObject.Properties["selected_engine"]) {
        $target | Add-Member -NotePropertyName selected_engine -NotePropertyValue "" -Force
    }
    if (-not $target.PSObject.Properties["attempted_engines"]) {
        $target | Add-Member -NotePropertyName attempted_engines -NotePropertyValue @() -Force
    }
    if (-not $target.PSObject.Properties["fallback_applied"]) {
        $target | Add-Member -NotePropertyName fallback_applied -NotePropertyValue $false -Force
    }
    if (-not $target.PSObject.Properties["updated_at"]) {
        $target | Add-Member -NotePropertyName updated_at -NotePropertyValue "" -Force
    }

    if (-not [string]::IsNullOrWhiteSpace($FinalOutcome)) {
        $target.final_outcome = [string]$FinalOutcome
    }

    if ($null -ne $InvokeResult) {
        if ($InvokeResult.PSObject.Properties["active_engine"] -and -not [string]::IsNullOrWhiteSpace([string]$InvokeResult.active_engine)) {
            $target.selected_engine = (Convert-EngineAliasLabel -Engine ([string]$InvokeResult.active_engine))
        }
        if ($InvokeResult.PSObject.Properties["attempted_engines"]) {
            $target.attempted_engines = @($InvokeResult.attempted_engines | ForEach-Object { [string]$_ })
        }
        if ($InvokeResult.PSObject.Properties["fallback_applied"]) {
            $target.fallback_applied = [bool]$InvokeResult.fallback_applied
        }
    }

    $target.updated_at = Get-UtcNow
    $State.routing_decisions.updated_at = Get-UtcNow
    Sync-RoutingDecisionToEngineeringMemory -State $State -DecisionRecord $target
    return $target
}

function Sync-RoutingDecisionToEngineeringMemory {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)]$DecisionRecord
    )

    try {
        $memory = Load-EngineeringMemory
        if (-not $memory.PSObject.Properties["routing_decision_memory"]) {
            $memory | Add-Member -NotePropertyName routing_decision_memory -NotePropertyValue @() -Force
        }

        $entry = [pscustomobject]@{
            id = "MEM-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 8).ToUpperInvariant())
            title = "routing decision"
            note = "task=$([string]$DecisionRecord.task_id) engine=$([string]$DecisionRecord.selected_engine) reason=$([string]$DecisionRecord.selection_reason) outcome=$([string]$DecisionRecord.final_outcome)"
            tags = @("routing", "engine:$([string]$DecisionRecord.selected_engine)", "category:$([string]$DecisionRecord.task_category)", "outcome:$([string]$DecisionRecord.final_outcome)")
            decision = $DecisionRecord
            created_at = Get-UtcNow
        }

        $memory.routing_decision_memory += $entry
        Save-EngineeringMemory -Memory $memory | Out-Null
    }
    catch {
        Write-Warning "Failed to sync routing decision memory: $($_.Exception.Message)"
    }
}

function Get-RoutingDecisionSummary {
    param(
        [Parameter(Mandatory = $true)]$State,
        [string]$TaskFilter,
        [int]$Take = 25
    )

    $records = @($State.routing_decisions.records)
    if (-not [string]::IsNullOrWhiteSpace($TaskFilter)) {
        $records = @($records | Where-Object { [string]$_.task_id -eq $TaskFilter })
    }

    $ordered = @($records | Sort-Object -Property created_at -Descending | Select-Object -First $Take)
    return [pscustomobject]@{
        updated_at = [string]$State.routing_decisions.updated_at
        total_records = @($records).Count
        records = @($ordered)
    }
}

function Resolve-TaskCategory {
    param($Task)

    if ($Task -and $Task.PSObject.Properties["task_category"] -and -not [string]::IsNullOrWhiteSpace([string]$Task.task_category)) {
        return ([string]$Task.task_category).ToLowerInvariant()
    }

    $blob = (Get-TaskRoutingText -Task $Task).ToLowerInvariant()
    if ($blob -match 'repo index|index-repo|indexing') { return "repo_index" }
    if ($blob -match 'module summary|summar') { return "module_summary" }
    if ($blob -match 'refactor') { return "refactor" }
    if ($blob -match 'test generation|generate test') { return "test_generation" }
    if ($blob -match 'review only|review') { return "review_only" }
    if ($blob -match 'sync|manifest|drift') { return "sync_check" }
    if ($blob -match 'docs?|readme|markdown|\.md\b') { return "docs_change" }
    if ($blob -match 'config|settings|bootstrap|\.json\b|\.ya?ml\b|\.toml\b|\.ini\b') { return "config_change" }
    if ($blob -match 'validate|validation|verify|verification|regression|smoke test|unit test|integration test|lint|compile|typecheck') { return "validation" }
    if ($blob -match 'inspect|inspection|search|locate|find|scan|status|query|analy[sz]e|review evidence') { return "inspection" }
    return "code_change"
}

function Get-TaskRoutingText {
    param($Task)

    if ($null -eq $Task) {
        return ""
    }

    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($propertyName in @('title', 'scope', 'description', 'content')) {
        if ($Task.PSObject.Properties[$propertyName] -and -not [string]::IsNullOrWhiteSpace([string]$Task.$propertyName)) {
            $parts.Add([string]$Task.$propertyName) | Out-Null
        }
    }

    foreach ($propertyName in @('acceptance_criteria', 'allowed_files', 'files_involved')) {
        if ($Task.PSObject.Properties[$propertyName] -and $null -ne $Task.$propertyName) {
            foreach ($item in @($Task.$propertyName)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$item)) {
                    $parts.Add([string]$item) | Out-Null
                }
            }
        }
    }

    return [string]::Join(" `n", @($parts))
}

function Get-TaskRoutingFileHints {
    param($Task)

    $text = Get-TaskRoutingText -Task $Task
    if ([string]::IsNullOrWhiteSpace($text)) {
        return @()
    }

    $matches = [regex]::Matches($text, '(?im)(?:^|[\s''""`(\[])([A-Za-z0-9_./\\-]+\.[A-Za-z0-9]{1,8})(?=$|[\s''""`,:;\.\!\?\)\]])')
    $items = foreach ($match in $matches) {
        if ($match.Groups.Count -gt 1) {
            ([string]$match.Groups[1].Value) -replace '[\\/]+', '/'
        }
    }

    return @($items | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
}

function Get-BoundedEditDirectiveValue {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$FieldName
    )

    $match = [regex]::Match($Text, ('(?im)^\s*{0}\s*:\s*(.+?)\s*$' -f [regex]::Escape($FieldName)))
    if ($match.Success) {
        return ([string]$match.Groups[1].Value).Trim()
    }

    return ''
}

function Convert-ToCanonicalBoundedEditMode {
    param([AllowEmptyString()][string]$Mode)

    $normalized = ([string]$Mode).Trim().ToLowerInvariant() -replace '[\s-]+', '_'
    switch ($normalized) {
        'replace_text' { return 'replace_text' }
        'replace_exact_text' { return 'replace_text' }
        'append_section' { return 'append_section' }
        'docs_append_section' { return 'append_section' }
        'insert_after' { return 'insert_after' }
        'insert_after_anchor' { return 'insert_after' }
        'append_marker' { return 'insert_after' }
        'add_small_function' { return 'insert_after' }
        'update_json_field' { return 'update_json_field' }
        'validation_only' { return 'validation_only' }
        default { return '' }
    }
}

function Get-BoundedEditSectionTitle {
    param([Parameter(Mandatory = $true)][string]$Text)

    $explicitTitle = Get-BoundedEditDirectiveValue -Text $Text -FieldName 'Section Title'
    if (-not [string]::IsNullOrWhiteSpace($explicitTitle)) {
        return $explicitTitle
    }

    $match = [regex]::Match($Text, '(?im)\b(?:with|add|insert|append)\s+(?:a\s+)?(?:short\s+)?(.+?)\s+section\b')
    if ($match.Success) {
        $sectionTitle = [string]$match.Groups[1].Value
        return ($sectionTitle -replace '^[\s\.\:\-`"]+|[\s\.\:\-`"]+$', '')
    }

    return ''
}

function New-BoundedEditMaterializationBlockedPayload {
    param(
        [Parameter(Mandatory = $true)]$Task,
        [Parameter(Mandatory = $true)][string]$TaskCategory,
        [string[]]$TargetFileCandidates = @(),
        [string[]]$RequiredClarification = @(),
        [AllowEmptyString()][string]$Reason = ''
    )

    $why = if (-not [string]::IsNullOrWhiteSpace($Reason)) {
        [string]$Reason
    }
    else {
        'TOD could not derive a safe bounded edit mode and explicit directives for LocalExecutionEngine.'
    }

    $taskIdValue = ''
    if ($Task -and $Task.PSObject.Properties['id']) {
        $taskIdValue = [string]$Task.id
    }

    return [pscustomobject]@{
        status = 'blocked'
        blocked = $true
        reason_code = 'blocked_missing_bounded_edit_mode'
        missing_binding = [pscustomobject]@{
            file = 'scripts/TOD.ps1'
            function = 'Resolve-TaskBoundedEditMaterialization'
            required_binding = 'scripts/engines/LocalExecutionEngine.ps1::Invoke-LocalExecutionEngine'
            reason_code = 'blocked_missing_bounded_edit_mode'
        }
        task_category = [string]$TaskCategory
        task_id = $taskIdValue
        target_file_candidates = @($TargetFileCandidates | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
        required_clarification = @($RequiredClarification | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
        why_local_executor_cannot_proceed = $why
        supported_modes = @('append_marker', 'replace_exact_text', 'insert_after_anchor', 'update_json_field', 'add_small_function', 'docs_append_section', 'validation_only')
        prompt_directives = [ordered]@{}
    }
}

function Resolve-TaskBoundedEditMaterialization {
    param($Task)

    if ($null -eq $Task) {
        return (New-BoundedEditMaterializationBlockedPayload -Task $Task -TaskCategory 'code_change' -Reason 'TOD could not materialize a null task payload for local execution.' -RequiredClarification @('task_payload'))
    }

    if ($Task.PSObject.Properties['materialization'] -and $null -ne $Task.materialization -and $Task.materialization.PSObject.Properties['status']) {
        return $Task.materialization
    }

    $taskCategory = Resolve-TaskCategory -Task $Task
    $text = Get-TaskRoutingText -Task $Task
    $fileHints = @(Get-TaskRoutingFileHints -Task $Task)
    $requestedMode = Get-BoundedEditDirectiveValue -Text $text -FieldName 'Edit Mode'
    $engineMode = Convert-ToCanonicalBoundedEditMode -Mode $requestedMode
    $targetFile = if (@($fileHints).Count -eq 1) { [string]$fileHints[0] } else { '' }
    $validationPattern = Get-BoundedEditDirectiveValue -Text $text -FieldName 'Validation Pattern'
    $validationCommand = Get-BoundedEditDirectiveValue -Text $text -FieldName 'Validation Command'
    $oldText = Get-BoundedEditDirectiveValue -Text $text -FieldName 'Old Text'
    $newText = Get-BoundedEditDirectiveValue -Text $text -FieldName 'New Text'
    $anchor = Get-BoundedEditDirectiveValue -Text $text -FieldName 'Anchor'
    $snippet = Get-BoundedEditDirectiveValue -Text $text -FieldName 'Snippet'
    $sectionTitle = Get-BoundedEditSectionTitle -Text $text
    $sectionBody = Get-BoundedEditDirectiveValue -Text $text -FieldName 'Section Body'
    $jsonField = Get-BoundedEditDirectiveValue -Text $text -FieldName 'Json Field'
    $jsonValue = Get-BoundedEditDirectiveValue -Text $text -FieldName 'Json Value'
    $lowerText = ([string]$text).ToLowerInvariant()

    if ([string]::IsNullOrWhiteSpace($engineMode)) {
        if (-not [string]::IsNullOrWhiteSpace($oldText) -and -not [string]::IsNullOrWhiteSpace($newText)) {
            $engineMode = 'replace_text'
        }
        elseif (-not [string]::IsNullOrWhiteSpace($anchor) -and -not [string]::IsNullOrWhiteSpace($snippet)) {
            $engineMode = 'insert_after'
        }
        elseif (-not [string]::IsNullOrWhiteSpace($jsonField) -and -not [string]::IsNullOrWhiteSpace($jsonValue)) {
            $engineMode = 'update_json_field'
        }
        elseif (([string]$taskCategory -eq 'validation') -or ($lowerText -match 'validation[- ]only|publish validation only|validate only|do not call codex')) {
            $engineMode = 'validation_only'
        }
        elseif ((-not [string]::IsNullOrWhiteSpace($targetFile)) -and $targetFile.ToLowerInvariant().EndsWith('.md') -and -not [string]::IsNullOrWhiteSpace($sectionTitle)) {
            $engineMode = 'append_section'
        }
    }

    if (@($fileHints).Count -ne 1) {
        $blockedPayload = New-BoundedEditMaterializationBlockedPayload -Task $Task -TaskCategory $taskCategory -TargetFileCandidates @($fileHints) -RequiredClarification @('target_file') -Reason 'TOD needs exactly one bounded target file before LocalExecutionEngine can proceed.'
        return $blockedPayload
    }

    $promptDirectives = [ordered]@{
        'Target File' = $targetFile
    }
    $validationPlan = [ordered]@{}
    if (-not [string]::IsNullOrWhiteSpace($validationPattern)) {
        $validationPlan['pattern'] = $validationPattern
    }
    if (-not [string]::IsNullOrWhiteSpace($validationCommand)) {
        $validationPlan['command'] = $validationCommand
    }

    switch ($engineMode) {
        'replace_text' {
            if ([string]::IsNullOrWhiteSpace($oldText) -or [string]::IsNullOrWhiteSpace($newText)) {
                $blockedPayload = New-BoundedEditMaterializationBlockedPayload -Task $Task -TaskCategory $taskCategory -TargetFileCandidates @($fileHints) -RequiredClarification @('old_text', 'new_text') -Reason 'TOD requires explicit Old Text and New Text directives for bounded replace-text execution.'
                return $blockedPayload
            }
            $promptDirectives['Edit Mode'] = 'replace_text'
            $promptDirectives['Old Text'] = $oldText
            $promptDirectives['New Text'] = $newText
            if (-not [string]::IsNullOrWhiteSpace($validationPattern)) {
                $promptDirectives['Validation Pattern'] = $validationPattern
            }
            if (-not [string]::IsNullOrWhiteSpace($validationCommand)) {
                $promptDirectives['Validation Command'] = $validationCommand
            }
        }
        'append_section' {
            if ([string]::IsNullOrWhiteSpace($sectionTitle)) {
                $blockedPayload = New-BoundedEditMaterializationBlockedPayload -Task $Task -TaskCategory $taskCategory -TargetFileCandidates @($fileHints) -RequiredClarification @('section_title') -Reason 'TOD requires a section title before it can materialize a bounded docs append operation.'
                return $blockedPayload
            }
            $promptDirectives['Edit Mode'] = 'append_section'
            $promptDirectives['Section Title'] = $sectionTitle
            if (-not [string]::IsNullOrWhiteSpace($sectionBody)) {
                $promptDirectives['Section Body'] = $sectionBody
            }
            if (-not [string]::IsNullOrWhiteSpace($validationPattern)) {
                $promptDirectives['Validation Pattern'] = $validationPattern
            }
            if (-not [string]::IsNullOrWhiteSpace($validationCommand)) {
                $promptDirectives['Validation Command'] = $validationCommand
            }
        }
        'insert_after' {
            if ([string]::IsNullOrWhiteSpace($anchor) -or [string]::IsNullOrWhiteSpace($snippet)) {
                $blockedPayload = New-BoundedEditMaterializationBlockedPayload -Task $Task -TaskCategory $taskCategory -TargetFileCandidates @($fileHints) -RequiredClarification @('anchor', 'snippet') -Reason 'TOD requires explicit Anchor and Snippet directives for insert-after bounded execution.'
                return $blockedPayload
            }
            $promptDirectives['Edit Mode'] = 'insert_after'
            $promptDirectives['Anchor'] = $anchor
            $promptDirectives['Snippet'] = $snippet
            if (-not [string]::IsNullOrWhiteSpace($validationPattern)) {
                $promptDirectives['Validation Pattern'] = $validationPattern
            }
            if (-not [string]::IsNullOrWhiteSpace($validationCommand)) {
                $promptDirectives['Validation Command'] = $validationCommand
            }
        }
        'update_json_field' {
            if ([string]::IsNullOrWhiteSpace($jsonField) -or [string]::IsNullOrWhiteSpace($jsonValue)) {
                $blockedPayload = New-BoundedEditMaterializationBlockedPayload -Task $Task -TaskCategory $taskCategory -TargetFileCandidates @($fileHints) -RequiredClarification @('json_field', 'json_value') -Reason 'TOD requires explicit Json Field and Json Value directives for bounded JSON updates.'
                return $blockedPayload
            }
            $promptDirectives['Edit Mode'] = 'update_json_field'
            $promptDirectives['Json Field'] = $jsonField
            $promptDirectives['Json Value'] = $jsonValue
            if (-not [string]::IsNullOrWhiteSpace($validationPattern)) {
                $promptDirectives['Validation Pattern'] = $validationPattern
            }
            if (-not [string]::IsNullOrWhiteSpace($validationCommand)) {
                $promptDirectives['Validation Command'] = $validationCommand
            }
        }
        'validation_only' {
            $promptDirectives['Edit Mode'] = 'validation_only'
            if (-not [string]::IsNullOrWhiteSpace($validationPattern)) {
                $promptDirectives['Validation Pattern'] = $validationPattern
            }
            if (-not [string]::IsNullOrWhiteSpace($validationCommand)) {
                $promptDirectives['Validation Command'] = $validationCommand
            }
        }
        default {
            $blockedPayload = New-BoundedEditMaterializationBlockedPayload -Task $Task -TaskCategory $taskCategory -TargetFileCandidates @($fileHints) -RequiredClarification @('edit_mode') -Reason 'TOD could not derive a bounded edit mode from the direct-chat task. Add explicit directives or restate the request as validation-only.'
            return $blockedPayload
        }
    }

    $requestedSummary = ''
    if ($Task.PSObject.Properties['scope']) {
        $requestedSummary = [string]$Task.scope
    }

    return [pscustomobject]@{
        status = 'materialized'
        blocked = $false
        reason_code = ''
        task_category = [string]$taskCategory
        requested_mode = [string]$requestedMode
        edit_mode = [string]$engineMode
        target_files = @($targetFile)
        target_file_candidates = @($fileHints)
        required_clarification = @()
        why_local_executor_cannot_proceed = ''
        prompt_directives = $promptDirectives
        requested_change = [ordered]@{
            target_file = $targetFile
            edit_mode = [string]$engineMode
            summary = $requestedSummary
        }
        validation_plan = [pscustomobject]$validationPlan
        safety_scope = [pscustomobject]@{
            allowed_files = @($fileHints)
            task_category = [string]$taskCategory
            execution = 'local_bounded'
        }
        supported_modes = @('append_marker', 'replace_exact_text', 'insert_after_anchor', 'update_json_field', 'add_small_function', 'docs_append_section', 'validation_only')
    }
}

function Convert-BoundedEditMaterializationToPromptBlock {
    param($Materialization)

    if ($null -eq $Materialization) {
        return ''
    }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('## Bounded Edit Materialization') | Out-Null
    $lines.Add('') | Out-Null

    if ($Materialization.PSObject.Properties['status'] -and [string]::Equals([string]$Materialization.status, 'materialized', [System.StringComparison]::OrdinalIgnoreCase)) {
        foreach ($entry in $Materialization.prompt_directives.GetEnumerator()) {
            $lines.Add(('{0}: {1}' -f [string]$entry.Key, [string]$entry.Value)) | Out-Null
        }
    }
    else {
        $lines.Add('Materialization Status: blocked_missing_bounded_edit_mode') | Out-Null
        if ($Materialization.PSObject.Properties['target_file_candidates'] -and $null -ne $Materialization.target_file_candidates -and @($Materialization.target_file_candidates).Count -gt 0) {
            $lines.Add(('Target File Candidates: {0}' -f (@($Materialization.target_file_candidates) -join ', '))) | Out-Null
        }
        if ($Materialization.PSObject.Properties['required_clarification'] -and $null -ne $Materialization.required_clarification -and @($Materialization.required_clarification).Count -gt 0) {
            $lines.Add(('Required Clarification: {0}' -f (@($Materialization.required_clarification) -join ', '))) | Out-Null
        }
        if ($Materialization.PSObject.Properties['why_local_executor_cannot_proceed'] -and -not [string]::IsNullOrWhiteSpace([string]$Materialization.why_local_executor_cannot_proceed)) {
            $lines.Add(('Why Local Executor Cannot Proceed: {0}' -f [string]$Materialization.why_local_executor_cannot_proceed)) | Out-Null
        }
    }

    return (@($lines) -join "`n")
}

function New-RunTaskMaterializationBlockedResult {
    param(
        [Parameter(Mandatory = $true)]$Task,
        [Parameter(Mandatory = $true)]$Materialization,
        [Parameter(Mandatory = $true)][string]$TaskId,
        [Parameter(Mandatory = $true)]$ActionEngineConfig,
        [Parameter(Mandatory = $true)][string]$PackagePath
    )

    $summary = if ($Materialization.PSObject.Properties['why_local_executor_cannot_proceed']) { [string]$Materialization.why_local_executor_cannot_proceed } else { 'TOD could not derive a bounded edit mode.' }
    $materializationTaskCategory = ''
    if ($Materialization.PSObject.Properties['task_category']) {
        $materializationTaskCategory = [string]$Materialization.task_category
    }
    $materializationTargetFileCandidates = if ($Materialization.PSObject.Properties['target_file_candidates']) { @($Materialization.target_file_candidates) } else { @() }
    $materializationClarification = if ($Materialization.PSObject.Properties['required_clarification']) { @($Materialization.required_clarification) } else { @() }

    $resultPayload = [pscustomobject]@{
        engine_name = 'local'
        engine_version = 'materializer'
        execution_id = [string]$TaskId
        status = 'failed'
        task_id = [string]$TaskId
        summary = $summary
        files_changed = @()
        tests_run = @('bounded_edit_materialization')
        test_results = @('blocked')
        failures = @($summary)
        recommendations = @('Provide one explicit target file and bounded edit directives, or restate the request as validation-only.')
        structured_findings = @(
            [pscustomobject]@{
                type = 'blocker'
                reason_code = 'blocked_missing_bounded_edit_mode'
                file = 'scripts/TOD.ps1'
                function = 'Resolve-TaskBoundedEditMaterialization'
                required_binding = 'scripts/engines/LocalExecutionEngine.ps1::Invoke-LocalExecutionEngine'
                task_id = [string]$TaskId
                task_category = $materializationTaskCategory
                target_file_candidates = @($materializationTargetFileCandidates)
                required_clarification = @($materializationClarification)
            }
        )
        needs_escalation = $false
        started_at = (Get-Date).ToUniversalTime().ToString('o')
        completed_at = (Get-Date).ToUniversalTime().ToString('o')
        reason_code = 'blocked_missing_bounded_edit_mode'
        blockers = @()
        commands_run = @()
        validation_results = @()
        no_change_required = $true
        recovery_state = 'blocked_with_reason'
        raw_output = [pscustomobject]@{
            action = 'bounded_edit_materialization_blocked'
            package_path = $PackagePath
            engine = 'local'
            active_engine = [string]$ActionEngineConfig.active
            fallback_engine = [string]$ActionEngineConfig.fallback
            materialization = $Materialization
        }
    }
    $resultPayload.blockers = @($resultPayload.structured_findings)

    return [pscustomobject]@{
        task_id = [string]$TaskId
        package_path = $PackagePath
        attempted_engines = @()
        active_engine = [string]$ActionEngineConfig.active
        fallback_applied = $false
        failure_category = 'materialization_blocked'
        attempts = @()
        result = $resultPayload
    }
}

function Test-TaskAllowsLocalExecutionWithoutMaterialization {
    param(
        [Parameter(Mandatory = $true)]$Task,
        [string]$TaskCategory = '',
        $TaskMaterialization = $null
    )

    if ($null -eq $Task) {
        return $false
    }

    $materializationStatus = if ($null -ne $TaskMaterialization -and $TaskMaterialization.PSObject.Properties['status']) {
        ([string]$TaskMaterialization.status).ToLowerInvariant()
    }
    else {
        ''
    }
    if ($materializationStatus -eq 'materialized') {
        return $false
    }

    $objectiveId = if ($Task.PSObject.Properties['objective_id']) { ([string]$Task.objective_id).ToLowerInvariant() } else { '' }
    if ($objectiveId -match 'message-ledger-coverage-report') {
        return $true
    }

    $category = ([string]$TaskCategory).ToLowerInvariant()
    if (@('inspection', 'validation', 'mim_synced', 'chat_execution') -notcontains $category) {
        return $false
    }

    $blob = (Get-TaskRoutingText -Task $Task).ToLowerInvariant()
    $mentionsLedger = $blob -match 'message.?ledger|ledger'
    $mentionsCoverage = $blob -match 'coverage|phase.?a|observe.?only|measure'
    return ($mentionsLedger -and $mentionsCoverage)
}

function Set-PersistedTaskTerminalState {
    param(
        [Parameter(Mandatory = $true)]$Task,
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $true)][string]$EventType,
        [Parameter(Mandatory = $true)][string]$Message,
        [AllowEmptyString()][string]$ReasonCode = '',
        $Details = $null,
        [AllowEmptyString()][string]$TaskStatus = ''
    )

    $timestamp = Get-UtcNow
    $resolvedTaskStatus = if (-not [string]::IsNullOrWhiteSpace($TaskStatus)) {
        [string]$TaskStatus
    }
    elseif ([string]::Equals($Status, 'completed', [System.StringComparison]::OrdinalIgnoreCase)) {
        'completed'
    }
    else {
        'blocked'
    }

    $Task.status = $resolvedTaskStatus
    $Task.updated_at = $timestamp
    $Task | Add-Member -NotePropertyName terminal_state -NotePropertyValue ([pscustomobject]@{
            timestamp = $timestamp
            status = [string]$Status
            event_type = [string]$EventType
            message = [string]$Message
            reason_code = [string]$ReasonCode
            details = if ($null -ne $Details) { $Details } else { [pscustomobject]@{} }
        }) -Force
}

function Update-TaskTerminalStateInStore {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][string]$TaskId,
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $true)][string]$EventType,
        [Parameter(Mandatory = $true)][string]$Message,
        [AllowEmptyString()][string]$ReasonCode = '',
        $Details = $null,
        [AllowEmptyString()][string]$TaskStatus = ''
    )

    $taskRecord = @($State.tasks | Where-Object { [string]$_.id -eq [string]$TaskId } | Select-Object -First 1)
    if (@($taskRecord).Count -eq 0) {
        return $null
    }

    Set-PersistedTaskTerminalState -Task $taskRecord[0] -Status $Status -EventType $EventType -Message $Message -ReasonCode $ReasonCode -Details $Details -TaskStatus $TaskStatus
    return $taskRecord[0]
}

function Get-LocalExecutionReuseSignal {
    param(
        $State,
        [string]$TaskCategory,
        [string[]]$FileHints = @()
    )

    $empty = [pscustomobject]@{
        matched = $false
        strength = 'none'
        matched_files = @()
        matched_record_id = ''
    }

    if ($null -eq $State -or -not $State.PSObject.Properties['engine_performance'] -or $null -eq $State.engine_performance -or -not $State.engine_performance.PSObject.Properties['records']) {
        return $empty
    }

    $records = @($State.engine_performance.records | Where-Object {
            $null -ne $_ -and
            ([string]$_.engine).ToLowerInvariant() -eq 'local' -and
            [bool]$_.success
        } | Sort-Object -Property created_at -Descending | Select-Object -First 50)

    if (-not [string]::IsNullOrWhiteSpace($TaskCategory)) {
        $records = @($records | Where-Object {
                $_.PSObject.Properties['task_category'] -and ([string]$_.task_category).ToLowerInvariant() -eq $TaskCategory.ToLowerInvariant()
            })
    }

    foreach ($record in $records) {
        $recordFiles = if ($record.PSObject.Properties['files_involved'] -and $null -ne $record.files_involved) {
            @($record.files_involved | ForEach-Object { ([string]$_) -replace '[\\/]+', '/' } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        }
        else {
            @()
        }

        $matchedFiles = @($recordFiles | Where-Object { $FileHints -contains $_ } | Select-Object -Unique)
        if (@($matchedFiles).Count -gt 0) {
            return [pscustomobject]@{
                matched = $true
                strength = 'strong'
                matched_files = @($matchedFiles)
                matched_record_id = if ($record.PSObject.Properties['id']) { [string]$record.id } else { '' }
            }
        }
    }

    if (@($records).Count -gt 0) {
        $top = $records[0]
        return [pscustomobject]@{
            matched = $true
            strength = 'category'
            matched_files = @()
            matched_record_id = if ($top.PSObject.Properties['id']) { [string]$top.id } else { '' }
        }
    }

    return $empty
}

function Resolve-LocalExecutionSuitability {
    param(
        $Task,
        [string]$TaskCategoryHint,
        $State
    )

    $taskCategory = if (-not [string]::IsNullOrWhiteSpace($TaskCategoryHint)) { ([string]$TaskCategoryHint).ToLowerInvariant() } else { Resolve-TaskCategory -Task $Task }
    $text = (Get-TaskRoutingText -Task $Task).ToLowerInvariant()
    $fileHints = @(Get-TaskRoutingFileHints -Task $Task)
    $reuse = Get-LocalExecutionReuseSignal -State $State -TaskCategory $taskCategory -FileHints $fileHints
    $singleFileHint = (@($fileHints).Count -eq 1)
    $boundedEditHint = ($text -match 'update|patch|edit|replace|append|write|modify|inspect|validate|verify|check|search|locate|find')
    $highRiskHint = ($text -match 'deploy|push|remote host|ssh|service restart|systemctl|daemon|azure|kubernetes|database|migration|schema|provision|commit|branch|merge')
    $explicitCodexRequest = ($text -match '\b(use codex|codex only|route to codex|handoff to codex|send to codex)\b')
    $avoidCodexHint = ($text -match '\b(do not call codex|without codex|local[- ]first|local only|keep local)\b')

    $classification = 'codex_required'
    $reason = 'default_codex_required'
    $codexAllowed = $false
    $fallbackReasonCodes = @()
    $boundedLocalSlice = $false

    if ($highRiskHint) {
        $classification = 'codex_required'
        $reason = 'high_risk_or_remote_scope'
        $codexAllowed = $true
    }
    else {
        switch ($taskCategory) {
            'docs_change' {
                $classification = 'local_supported'
                $reason = 'bounded_docs_change'
                $boundedLocalSlice = $true
            }
            'config_change' {
                $classification = 'local_supported'
                $reason = 'bounded_config_change'
                $boundedLocalSlice = $true
            }
            'inspection' {
                $classification = 'local_supported'
                $reason = 'inspection_is_local_first'
                $boundedLocalSlice = $true
            }
            'validation' {
                $classification = 'local_supported'
                $reason = 'validation_is_local_first'
                $boundedLocalSlice = $true
            }
            'review_only' {
                $classification = 'local_supported'
                $reason = 'review_is_local_first'
                $boundedLocalSlice = $true
            }
            'sync_check' {
                $classification = 'local_supported'
                $reason = 'sync_checks_are_local_first'
                $boundedLocalSlice = $true
            }
            'code_change' {
                if ($singleFileHint -and $boundedEditHint) {
                    $classification = 'local_supported'
                    $reason = 'single_file_bounded_code_change'
                    $boundedLocalSlice = $true
                }
                else {
                    $classification = 'local_possible'
                    $reason = 'code_change_try_local_before_codex'
                }
            }
            'bridge_runtime' {
                $classification = 'local_possible'
                $reason = 'bridge_runtime_try_local_first'
            }
            'mim_synced' {
                $classification = 'local_possible'
                $reason = 'mirrored_task_try_local_first'
            }
            'chat_execution' {
                $classification = 'local_possible'
                $reason = 'chat_execution_try_local_first'
            }
        }
    }

    if ([bool]$reuse.matched -and $classification -eq 'local_possible') {
        $classification = 'local_supported'
        $reason = 'local_execution_memory_reuse'
        $boundedLocalSlice = $true
    }

    if ($explicitCodexRequest) {
        $codexAllowed = $true
    }
    elseif (-not $avoidCodexHint) {
        if ($classification -eq 'codex_required') {
            $codexAllowed = $true
        }
        elseif ($classification -eq 'local_possible' -and -not $boundedLocalSlice -and @($fileHints).Count -eq 0) {
            $codexAllowed = $true
        }
    }

    if ($codexAllowed -and $classification -ne 'codex_required') {
        $fallbackReasonCodes = @('blocked_missing_capability')
    }

    return [pscustomobject]@{
        classification = $classification
        task_category = $taskCategory
        reason = $reason
        file_hints = @($fileHints)
        local_reuse = $reuse
        local_supported = @('local_supported', 'local_possible') -contains $classification
        codex_allowed = [bool]$codexAllowed
        fallback_reason_codes = @($fallbackReasonCodes)
    }
}

function Resolve-PreferredAssignedExecutor {
    param(
        [string]$TaskCategory,
        $State,
        $Task
    )

    $suitability = Resolve-LocalExecutionSuitability -Task $Task -TaskCategoryHint $TaskCategory -State $State
    if ([string]$suitability.classification -eq 'codex_required') {
        return 'codex'
    }

    return 'local'
}

function Sync-EnginePerformanceToEngineeringMemory {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)]$LatestRecord
    )

    try {
        $memory = Load-EngineeringMemory
        if (-not $memory.PSObject.Properties["engine_performance_memory"]) {
            $memory | Add-Member -NotePropertyName engine_performance_memory -NotePropertyValue @() -Force
        }

        $summary = Get-EnginePerformanceSummary -State $State
        $engineSummary = @($summary.by_engine | Where-Object { ([string]$_.engine).ToLowerInvariant() -eq ([string]$LatestRecord.engine).ToLowerInvariant() } | Select-Object -First 1)

        $entry = [pscustomobject]@{
            id = "MEM-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 8).ToUpperInvariant())
            title = "engine performance update"
            note = "engine=$([string]$LatestRecord.engine) category=$([string]$LatestRecord.task_category) decision=$([string]$LatestRecord.review_decision)"
            tags = @("engine-performance", "engine:$([string]$LatestRecord.engine)", "category:$([string]$LatestRecord.task_category)", "decision:$([string]$LatestRecord.review_decision)")
            record = $LatestRecord
            aggregate = $engineSummary
            created_at = Get-UtcNow
        }

        $memory.engine_performance_memory += $entry
        Save-EngineeringMemory -Memory $memory | Out-Null
    }
    catch {
        Write-Warning "Failed to sync engine performance memory: $($_.Exception.Message)"
    }
}

function Get-EnginePerformanceDelta {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][string]$EngineName,
        [string]$RecordId
    )

    $all = @($State.engine_performance.records | Where-Object { ([string]$_.engine).ToLowerInvariant() -eq $EngineName.ToLowerInvariant() })
    if (@($all).Length -eq 0) {
        return [pscustomobject]@{ previous_success_rate = $null; current_success_rate = $null; delta = $null }
    }

    $ordered = @($all | Sort-Object -Property created_at)
    $targetIndex = -1
    if (-not [string]::IsNullOrWhiteSpace($RecordId)) {
        for ($i = 0; $i -lt @($ordered).Length; $i++) {
            if ([string]$ordered[$i].id -eq $RecordId) {
                $targetIndex = $i
                break
            }
        }
    }
    if ($targetIndex -lt 0) {
        $targetIndex = @($ordered).Length - 1
    }

    $currentSlice = @($ordered | Select-Object -First ($targetIndex + 1))
    $previousSlice = if ($targetIndex -gt 0) { @($ordered | Select-Object -First $targetIndex) } else { @() }

    $currentSuccess = @($currentSlice | Where-Object { [bool]$_.success }).Count
    $currentRate = [math]::Round((100.0 * $currentSuccess / @($currentSlice).Length), 2)

    $previousRate = $null
    if (@($previousSlice).Length -gt 0) {
        $previousSuccess = @($previousSlice | Where-Object { [bool]$_.success }).Count
        $previousRate = [math]::Round((100.0 * $previousSuccess / @($previousSlice).Length), 2)
    }

    $delta = $null
    if ($null -ne $previousRate) {
        $delta = [math]::Round(($currentRate - $previousRate), 2)
    }

    return [pscustomobject]@{
        previous_success_rate = $previousRate
        current_success_rate = $currentRate
        delta = $delta
    }
}

function Get-TaskReliabilityScorecard {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][string]$TaskCategory,
        [string]$EngineName,
        $PerformanceDelta,
        $LatestRoutingRecord,
        $LatestReview
    )

    $routingConfidence = if ($LatestRoutingRecord -and $LatestRoutingRecord.PSObject.Properties["confidence"] -and $null -ne $LatestRoutingRecord.confidence) {
        [double]$LatestRoutingRecord.confidence
    }
    else {
        0.5
    }

    $healthScore = 0.7
    if (-not [string]::IsNullOrWhiteSpace($EngineName)) {
        $health = Get-EngineHealthSummary -State $State -Window 10
        $engineHealth = @($health.by_engine | Where-Object { ([string]$_.engine).ToLowerInvariant() -eq $EngineName.ToLowerInvariant() } | Select-Object -First 1)
        if (@($engineHealth).Count -gt 0 -and $engineHealth[0].PSObject.Properties["health_score"] -and $null -ne $engineHealth[0].health_score) {
            $healthScore = [double]$engineHealth[0].health_score
        }
    }

    $categoryPassScore = 0.5
    if (-not [string]::IsNullOrWhiteSpace($EngineName) -and -not [string]::IsNullOrWhiteSpace($TaskCategory)) {
        $categoryRecords = @($State.engine_performance.records | Where-Object {
                ([string]$_.engine).ToLowerInvariant() -eq $EngineName.ToLowerInvariant() -and
                ($_.PSObject.Properties["task_category"] -and ([string]$_.task_category).ToLowerInvariant() -eq $TaskCategory.ToLowerInvariant())
            } | Sort-Object -Property created_at -Descending | Select-Object -First 10)
        if (@($categoryRecords).Count -gt 0) {
            $categoryPasses = @($categoryRecords | Where-Object { [bool]$_.success }).Count
            $categoryPassScore = [double]$categoryPasses / [double]@($categoryRecords).Count
        }
    }

    $deltaScore = 0.5
    if ($PerformanceDelta -and $PerformanceDelta.PSObject.Properties["delta"] -and $null -ne $PerformanceDelta.delta) {
        $deltaScore = [math]::Max(0.0, [math]::Min(1.0, (([double]$PerformanceDelta.delta + 20.0) / 40.0)))
    }

    $reviewScore = 0.5
    if ($LatestReview -and $LatestReview.PSObject.Properties["decision"]) {
        switch ([string]$LatestReview.decision) {
            "pass" { $reviewScore = 1.0 }
            "revise" { $reviewScore = 0.5 }
            "escalate" { $reviewScore = 0.0 }
            default { $reviewScore = 0.5 }
        }
    }

    $outcomeScore = 1.0
    if ($LatestRoutingRecord -and $LatestRoutingRecord.PSObject.Properties["final_outcome"] -and -not [string]::IsNullOrWhiteSpace([string]$LatestRoutingRecord.final_outcome)) {
        switch (([string]$LatestRoutingRecord.final_outcome).ToLowerInvariant()) {
            "pass" { $outcomeScore = 1.0 }
            "revise" { $outcomeScore = 0.45 }
            "escalate" { $outcomeScore = 0.25 }
            "blocked_pre_invocation" { $outcomeScore = 0.15 }
            "escalated_pre_run" { $outcomeScore = 0.15 }
            default { $outcomeScore = 0.6 }
        }
    }

    $score =
    (0.28 * $routingConfidence) +
    (0.22 * $healthScore) +
    (0.18 * $categoryPassScore) +
    (0.1 * $deltaScore) +
    (0.1 * $reviewScore) +
    (0.12 * $outcomeScore)

    $score = [math]::Round([math]::Max(0.0, [math]::Min(1.0, $score)), 4)

    $finalOutcome = ""
    if ($LatestRoutingRecord -and $LatestRoutingRecord.PSObject.Properties["final_outcome"] -and -not [string]::IsNullOrWhiteSpace([string]$LatestRoutingRecord.final_outcome)) {
        $finalOutcome = ([string]$LatestRoutingRecord.final_outcome).ToLowerInvariant()
    }

    if ($finalOutcome -in @("blocked_pre_invocation", "escalated_pre_run")) {
        $score = [math]::Min($score, 0.45)
    }

    $band = if ($score -ge 0.8) { "high" } elseif ($score -ge 0.6) { "medium" } else { "low" }

    return [pscustomobject]@{
        score = $score
        band = $band
        factors = [pscustomobject]@{
            routing_confidence = [math]::Round($routingConfidence, 4)
            engine_health = [math]::Round($healthScore, 4)
            category_pass = [math]::Round($categoryPassScore, 4)
            performance_delta = [math]::Round($deltaScore, 4)
            latest_review = [math]::Round($reviewScore, 4)
            routing_outcome = [math]::Round($outcomeScore, 4)
        }
    }
}

function Build-RunTaskReport {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][string]$TaskId
    )

    $task = Get-TaskFromState -State $State -TaskId $TaskId
    if (-not $task) { throw "Task not found in local state cache: $TaskId" }

    $taskKeys = @([string]$task.id)
    if ($task.PSObject.Properties["remote_task_id"] -and -not [string]::IsNullOrWhiteSpace([string]$task.remote_task_id)) {
        $taskKeys += [string]$task.remote_task_id
    }
    $taskKeys = @($taskKeys | Select-Object -Unique)

    $latestRunTaskJournal = @($State.journal | Where-Object {
            [string]$_.action -eq "run_task" -and $taskKeys -contains [string]$_.entity_id
        } | Sort-Object -Property created_at -Descending | Select-Object -First 1)
    $latestInvokeJournal = @($State.journal | Where-Object {
            [string]$_.action -eq "invoke_engine" -and $taskKeys -contains [string]$_.entity_id
        } | Sort-Object -Property created_at -Descending | Select-Object -First 1)

    $latestResult = @($State.execution_results | Where-Object { $null -ne $_ -and $_.PSObject.Properties['task_id'] -and $taskKeys -contains [string]$_.task_id } | Sort-Object -Property created_at -Descending | Select-Object -First 1)
    $latestReview = @($State.review_decisions | Where-Object { $null -ne $_ -and $_.PSObject.Properties['task_id'] -and $taskKeys -contains [string]$_.task_id } | Sort-Object -Property created_at -Descending | Select-Object -First 1)
    $latestRouting = @($State.routing_decisions.records | Where-Object { $null -ne $_ -and $_.PSObject.Properties['task_id'] -and $taskKeys -contains [string]$_.task_id } | Sort-Object -Property created_at -Descending | Select-Object -First 1)
    $latestRoutingRecord = if (@($latestRouting).Count -gt 0) { $latestRouting[0] } else { $null }

    $engineName = ""
    $fallbackApplied = $false
    $attempted = @()
    $performanceRecordId = ""
    $lastRunSource = "manual_or_unknown"
    $executionReadiness = $null
    $executionTrace = $null

    $journalPayload = $null
    if ($latestRunTaskJournal -and $latestRunTaskJournal.payload) {
        $journalPayload = $latestRunTaskJournal.payload
        $lastRunSource = "run_task"
    }
    elseif ($latestInvokeJournal -and $latestInvokeJournal.payload) {
        $journalPayload = $latestInvokeJournal.payload
        $lastRunSource = "invoke_engine"
    }

    if ($journalPayload) {
        if ($journalPayload.PSObject.Properties["attempted_engines"]) {
            $attempted = @($journalPayload.attempted_engines | ForEach-Object { [string]$_ })
            if ($attempted.Count -gt 0) {
                $engineName = [string]$attempted[-1]
            }
        }
        if ($journalPayload.PSObject.Properties["fallback_applied"]) {
            $fallbackApplied = [bool]$journalPayload.fallback_applied
        }
        if ($journalPayload.PSObject.Properties["engine_performance_record_id"]) {
            $performanceRecordId = [string]$journalPayload.engine_performance_record_id
        }
        if ($journalPayload.PSObject.Properties["execution_readiness"] -and $null -ne $journalPayload.execution_readiness) {
            $executionReadiness = $journalPayload.execution_readiness
            $executionTrace = [pscustomobject]@{
                action = "run-task"
                execution_readiness = $executionReadiness
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($engineName) -and $latestResult -and $latestResult.engine_metadata -and $latestResult.engine_metadata.PSObject.Properties["name"]) {
        $engineName = [string]$latestResult.engine_metadata.name
    }

    $taskCategoryResolved = (Resolve-TaskCategory -Task $task)
    $perfDelta = if (-not [string]::IsNullOrWhiteSpace($engineName)) {
        Get-EnginePerformanceDelta -State $State -EngineName $engineName -RecordId $performanceRecordId
    }
    else {
        [pscustomobject]@{ previous_success_rate = $null; current_success_rate = $null; delta = $null }
    }
    $scorecard = Get-TaskReliabilityScorecard -State $State -TaskCategory $taskCategoryResolved -EngineName $engineName -PerformanceDelta $perfDelta -LatestRoutingRecord $latestRoutingRecord -LatestReview $latestReview

    return [pscustomobject]@{
        task_id = [string]$TaskId
        run_at = Get-UtcNow
        last_run_source = $lastRunSource
        task_category = $taskCategoryResolved
        engine_path = @($attempted)
        active_engine = $engineName
        fallback_applied = $fallbackApplied
        result_id = if ($latestResult) { [string]$latestResult.id } else { "" }
        review_id = if ($latestReview) { [string]$latestReview.id } else { "" }
        review_decision = if ($latestReview) { [string]$latestReview.decision } else { "" }
        routing_decision_id = if ($latestRoutingRecord) { [string]$latestRoutingRecord.id } else { "" }
        routing_reason = if ($latestRoutingRecord -and $latestRoutingRecord.routing -and $latestRoutingRecord.routing.PSObject.Properties["reason"]) { [string]$latestRoutingRecord.routing.reason } else { "" }
        routing_applied = if ($latestRoutingRecord -and $latestRoutingRecord.routing -and $latestRoutingRecord.routing.PSObject.Properties["applied"]) { [bool]$latestRoutingRecord.routing.applied } else { $false }
        routing_selection_reason = if ($latestRoutingRecord -and $latestRoutingRecord.PSObject.Properties["selection_reason"]) { [string]$latestRoutingRecord.selection_reason } else { "" }
        routing_confidence = if ($latestRoutingRecord -and $latestRoutingRecord.PSObject.Properties["confidence"]) { [double]$latestRoutingRecord.confidence } else { $null }
        routing_source = if ($latestRoutingRecord -and $latestRoutingRecord.PSObject.Properties["source"]) { [string]$latestRoutingRecord.source } else { "" }
        routing_final_outcome = if ($latestRoutingRecord -and $latestRoutingRecord.PSObject.Properties["final_outcome"]) { [string]$latestRoutingRecord.final_outcome } else { "" }
        routing_policy_snapshot = if ($latestRoutingRecord -and $latestRoutingRecord.routing -and $latestRoutingRecord.routing.PSObject.Properties["policy"]) { $latestRoutingRecord.routing.policy } else { $null }
        retry_policy_snapshot = if ($latestRoutingRecord -and $latestRoutingRecord.routing -and $latestRoutingRecord.routing.PSObject.Properties["retry_policy"]) { $latestRoutingRecord.routing.retry_policy } else { $null }
        performance_delta = $perfDelta
        reliability_scorecard = $scorecard
        execution_readiness = $executionReadiness
        execution_trace = $executionTrace
    }
}

function Split-List {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ,([string[]]@())
    }

    $items = @($Value.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    return ,([string[]]$items)
}

function Load-TodConfig {
    if (-not (Test-Path -Path $configPath)) {
        return [pscustomobject]@{
            mim_base_url = "http://192.168.1.120:8000"
            mode = "hybrid"
            timeout_seconds = 15
            fallback_to_local = $true
            mim_debug = [pscustomobject]@{
                enabled = $false
                log_path = ""
            }
            execution_feedback = [pscustomobject]@{
                enabled = $false
                source = "tod"
                auth_token = ""
            }
            engineering_loop = [pscustomobject]@{
                max_run_history = 150
                max_scorecard_history = 150
                max_cycle_records = 300
                guardrails = [pscustomobject]@{
                    require_confirmation_for_apply = $true
                    require_confirmation_for_write = $false
                }
                autonomy = [pscustomobject]@{
                    max_cycles_per_run = 5
                    stop_at_score = 0.85
                }
                safe_continue = [pscustomobject]@{
                    require_no_pending_approval = $true
                }
            }
            execution_engine = [pscustomobject]@{
                active = "local"
                fallback = "codex"
                allow_fallback = $true
                retry_policy = [pscustomobject]@{
                    enabled = $true
                    max_attempts_per_engine = 2
                    max_attempts_by_category = [pscustomobject]@{
                        code_change = 1
                        review_only = 2
                        refactor = 2
                    }
                    backoff_ms = 200
                    retry_on_status = @("failed", "error", "not_implemented")
                    no_retry_failure_categories = @("auth", "capability")
                    backoff_by_failure_category = [pscustomobject]@{
                        timeout = 2
                        network = 2
                        rate_limit = 3
                    }
                }
                routing_policy = [pscustomobject]@{
                    enabled = $true
                    min_runs = 1
                    min_success_rate = 75
                    improvement_margin = 5
                    source = "routing_policy_v1"
                    allow_placeholder_for_code_change = $false
                    prefer_stable_on_sync_warn = $true
                    block_on_contract_drift = $true
                    recent_failure_window = 5
                    recent_failure_threshold = 2
                    min_category_records_light = 10
                    min_category_records_strong = 20
                    drift_detection = [pscustomobject]@{
                        enabled = $true
                        recent_window = 20
                        baseline_window = 50
                        minimum_baseline_records = 10
                        failure_rate_multiplier = 1.5
                        retry_rate_threshold = 0.35
                        fallback_rate_multiplier = 1.5
                        fallback_rate_threshold = 0.3
                        guardrail_rate_multiplier = 1.8
                        guardrail_rate_threshold = 0.15
                        engine_score_drop_threshold = 0.2
                        confidence_penalty_failure_drift = 0.18
                        confidence_penalty_retry_high = 0.12
                        confidence_penalty_fallback_drift = 0.09
                        confidence_penalty_guardrail_spike = 0.1
                        confidence_penalty_score_drop = 0.12
                        score_penalty_failure_drift = 0.12
                        score_penalty_retry_high = 0.08
                        score_penalty_fallback_drift = 0.08
                        score_penalty_guardrail_spike = 0.1
                        score_penalty_score_drop = 0.12
                    }
                    weights = (Get-DefaultRoutingWeights)
                }
            }
        }
    }

    $raw = Get-Content -Path $configPath -Raw
    $cfg = $raw | ConvertFrom-Json
    if ([string]::IsNullOrWhiteSpace($cfg.mode)) { $cfg.mode = "hybrid" }
    if (-not $cfg.timeout_seconds) { $cfg.timeout_seconds = 15 }
    if ($null -eq $cfg.fallback_to_local) { $cfg.fallback_to_local = $true }
    if (-not $cfg.PSObject.Properties["mim_debug"] -or $null -eq $cfg.mim_debug) {
        $cfg | Add-Member -NotePropertyName mim_debug -NotePropertyValue ([pscustomobject]@{
                enabled = $false
                log_path = ""
            }) -Force
    }
    if (-not $cfg.mim_debug.PSObject.Properties["enabled"] -or $null -eq $cfg.mim_debug.enabled) { $cfg.mim_debug.enabled = $false }
    if (-not $cfg.mim_debug.PSObject.Properties["log_path"] -or $null -eq $cfg.mim_debug.log_path) { $cfg.mim_debug.log_path = "" }
    if (-not $cfg.PSObject.Properties["execution_feedback"] -or $null -eq $cfg.execution_feedback) {
        $cfg | Add-Member -NotePropertyName execution_feedback -NotePropertyValue ([pscustomobject]@{
                enabled = $false
                source = "tod"
                auth_token = ""
            }) -Force
    }
    if (-not $cfg.execution_feedback.PSObject.Properties["enabled"] -or $null -eq $cfg.execution_feedback.enabled) { $cfg.execution_feedback.enabled = $false }
    if (-not $cfg.execution_feedback.PSObject.Properties["source"] -or [string]::IsNullOrWhiteSpace([string]$cfg.execution_feedback.source)) { $cfg.execution_feedback.source = "tod" }
    if (-not $cfg.execution_feedback.PSObject.Properties["auth_token"] -or $null -eq $cfg.execution_feedback.auth_token) { $cfg.execution_feedback.auth_token = "" }
    if (-not $cfg.PSObject.Properties["engineering_loop"] -or $null -eq $cfg.engineering_loop) {
        $cfg | Add-Member -NotePropertyName engineering_loop -NotePropertyValue ([pscustomobject]@{
                max_run_history = 150
                max_scorecard_history = 150
            }) -Force
    }
    if (-not $cfg.engineering_loop.PSObject.Properties["max_run_history"] -or $null -eq $cfg.engineering_loop.max_run_history) { $cfg.engineering_loop.max_run_history = 150 }
    if (-not $cfg.engineering_loop.PSObject.Properties["max_scorecard_history"] -or $null -eq $cfg.engineering_loop.max_scorecard_history) { $cfg.engineering_loop.max_scorecard_history = 150 }
    if (-not $cfg.engineering_loop.PSObject.Properties["max_cycle_records"] -or $null -eq $cfg.engineering_loop.max_cycle_records) { $cfg.engineering_loop.max_cycle_records = 300 }
    $cfg.engineering_loop.max_run_history = [math]::Max(10, [math]::Min(1000, [int]$cfg.engineering_loop.max_run_history))
    $cfg.engineering_loop.max_scorecard_history = [math]::Max(10, [math]::Min(1000, [int]$cfg.engineering_loop.max_scorecard_history))
    $cfg.engineering_loop.max_cycle_records = [math]::Max(25, [math]::Min(2000, [int]$cfg.engineering_loop.max_cycle_records))
    if (-not $cfg.engineering_loop.PSObject.Properties["guardrails"] -or $null -eq $cfg.engineering_loop.guardrails) {
        $cfg.engineering_loop | Add-Member -NotePropertyName guardrails -NotePropertyValue ([pscustomobject]@{
                require_confirmation_for_apply = $true
                require_confirmation_for_write = $false
            }) -Force
    }
    if (-not $cfg.engineering_loop.guardrails.PSObject.Properties["require_confirmation_for_apply"] -or $null -eq $cfg.engineering_loop.guardrails.require_confirmation_for_apply) {
        $cfg.engineering_loop.guardrails.require_confirmation_for_apply = $true
    }
    if (-not $cfg.engineering_loop.guardrails.PSObject.Properties["require_confirmation_for_write"] -or $null -eq $cfg.engineering_loop.guardrails.require_confirmation_for_write) {
        $cfg.engineering_loop.guardrails.require_confirmation_for_write = $false
    }

    if (-not $cfg.engineering_loop.PSObject.Properties["autonomy"] -or $null -eq $cfg.engineering_loop.autonomy) {
        $cfg.engineering_loop | Add-Member -NotePropertyName autonomy -NotePropertyValue ([pscustomobject]@{
                max_cycles_per_run = 5
                stop_at_score = 0.85
            }) -Force
    }
    if (-not $cfg.engineering_loop.autonomy.PSObject.Properties["max_cycles_per_run"] -or $null -eq $cfg.engineering_loop.autonomy.max_cycles_per_run) {
        $cfg.engineering_loop.autonomy.max_cycles_per_run = 5
    }
    if (-not $cfg.engineering_loop.autonomy.PSObject.Properties["stop_at_score"] -or $null -eq $cfg.engineering_loop.autonomy.stop_at_score) {
        $cfg.engineering_loop.autonomy.stop_at_score = 0.85
    }
    $cfg.engineering_loop.autonomy.max_cycles_per_run = [math]::Max(1, [math]::Min(20, [int]$cfg.engineering_loop.autonomy.max_cycles_per_run))
    $cfg.engineering_loop.autonomy.stop_at_score = [math]::Max(0.0, [math]::Min(1.0, [double]$cfg.engineering_loop.autonomy.stop_at_score))
    if (-not $cfg.engineering_loop.PSObject.Properties["safe_continue"] -or $null -eq $cfg.engineering_loop.safe_continue) {
        $cfg.engineering_loop | Add-Member -NotePropertyName safe_continue -NotePropertyValue ([pscustomobject]@{
                require_no_pending_approval = $true
            }) -Force
    }
    if (-not $cfg.engineering_loop.safe_continue.PSObject.Properties["require_no_pending_approval"] -or $null -eq $cfg.engineering_loop.safe_continue.require_no_pending_approval) {
        $cfg.engineering_loop.safe_continue.require_no_pending_approval = $true
    }

    if (-not $cfg.PSObject.Properties["execution_engine"] -or $null -eq $cfg.execution_engine) {
        $cfg | Add-Member -NotePropertyName execution_engine -NotePropertyValue ([pscustomobject]@{
                active = "local"
                fallback = "codex"
                allow_fallback = $true
            }) -Force
    }

    if ([string]::IsNullOrWhiteSpace([string]$cfg.execution_engine.active)) { $cfg.execution_engine.active = "local" }
    if ([string]::IsNullOrWhiteSpace([string]$cfg.execution_engine.fallback)) { $cfg.execution_engine.fallback = "codex" }
    if ($null -eq $cfg.execution_engine.allow_fallback) { $cfg.execution_engine.allow_fallback = $true }
    if (-not $cfg.execution_engine.PSObject.Properties["retry_policy"] -or $null -eq $cfg.execution_engine.retry_policy) {
        $cfg.execution_engine | Add-Member -NotePropertyName retry_policy -NotePropertyValue ([pscustomobject]@{
                enabled = $true
                max_attempts_per_engine = 2
                max_attempts_by_category = [pscustomobject]@{
                    code_change = 1
                    review_only = 2
                    refactor = 2
                }
                backoff_ms = 200
                retry_on_status = @("failed", "error", "not_implemented")
                no_retry_failure_categories = @("auth", "capability")
                backoff_by_failure_category = [pscustomobject]@{
                    timeout = 2
                    network = 2
                    rate_limit = 3
                }
            }) -Force
    }
    if (-not $cfg.execution_engine.retry_policy.PSObject.Properties["enabled"] -or $null -eq $cfg.execution_engine.retry_policy.enabled) { $cfg.execution_engine.retry_policy.enabled = $true }
    if (-not $cfg.execution_engine.retry_policy.PSObject.Properties["max_attempts_per_engine"] -or $null -eq $cfg.execution_engine.retry_policy.max_attempts_per_engine) { $cfg.execution_engine.retry_policy.max_attempts_per_engine = 2 }
    if (-not $cfg.execution_engine.retry_policy.PSObject.Properties["max_attempts_by_category"] -or $null -eq $cfg.execution_engine.retry_policy.max_attempts_by_category) {
        $cfg.execution_engine.retry_policy.max_attempts_by_category = [pscustomobject]@{
            code_change = 1
            review_only = 2
            refactor = 2
        }
    }
    if (-not $cfg.execution_engine.retry_policy.PSObject.Properties["backoff_ms"] -or $null -eq $cfg.execution_engine.retry_policy.backoff_ms) { $cfg.execution_engine.retry_policy.backoff_ms = 200 }
    if (-not $cfg.execution_engine.retry_policy.PSObject.Properties["retry_on_status"] -or $null -eq $cfg.execution_engine.retry_policy.retry_on_status) {
        $cfg.execution_engine.retry_policy.retry_on_status = @("failed", "error", "not_implemented")
    }
    if (-not $cfg.execution_engine.retry_policy.PSObject.Properties["no_retry_failure_categories"] -or $null -eq $cfg.execution_engine.retry_policy.no_retry_failure_categories) {
        $cfg.execution_engine.retry_policy.no_retry_failure_categories = @("auth", "capability")
    }
    if (-not $cfg.execution_engine.retry_policy.PSObject.Properties["backoff_by_failure_category"] -or $null -eq $cfg.execution_engine.retry_policy.backoff_by_failure_category) {
        $cfg.execution_engine.retry_policy.backoff_by_failure_category = [pscustomobject]@{
            timeout = 2
            network = 2
            rate_limit = 3
        }
    }
    $cfg.execution_engine.retry_policy.retry_on_status = @($cfg.execution_engine.retry_policy.retry_on_status | ForEach-Object { ([string]$_).ToLowerInvariant() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    $cfg.execution_engine.retry_policy.no_retry_failure_categories = @($cfg.execution_engine.retry_policy.no_retry_failure_categories | ForEach-Object { ([string]$_).ToLowerInvariant() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    if (-not $cfg.execution_engine.retry_policy.backoff_by_failure_category.PSObject.Properties["timeout"] -or $null -eq $cfg.execution_engine.retry_policy.backoff_by_failure_category.timeout) { $cfg.execution_engine.retry_policy.backoff_by_failure_category | Add-Member -NotePropertyName timeout -NotePropertyValue 2 -Force }
    if (-not $cfg.execution_engine.retry_policy.backoff_by_failure_category.PSObject.Properties["network"] -or $null -eq $cfg.execution_engine.retry_policy.backoff_by_failure_category.network) { $cfg.execution_engine.retry_policy.backoff_by_failure_category | Add-Member -NotePropertyName network -NotePropertyValue 2 -Force }
    if (-not $cfg.execution_engine.retry_policy.backoff_by_failure_category.PSObject.Properties["rate_limit"] -or $null -eq $cfg.execution_engine.retry_policy.backoff_by_failure_category.rate_limit) { $cfg.execution_engine.retry_policy.backoff_by_failure_category | Add-Member -NotePropertyName rate_limit -NotePropertyValue 3 -Force }
    if (-not $cfg.execution_engine.retry_policy.max_attempts_by_category.PSObject.Properties["code_change"] -or $null -eq $cfg.execution_engine.retry_policy.max_attempts_by_category.code_change) { $cfg.execution_engine.retry_policy.max_attempts_by_category | Add-Member -NotePropertyName code_change -NotePropertyValue 1 -Force }
    if (-not $cfg.execution_engine.retry_policy.max_attempts_by_category.PSObject.Properties["review_only"] -or $null -eq $cfg.execution_engine.retry_policy.max_attempts_by_category.review_only) { $cfg.execution_engine.retry_policy.max_attempts_by_category | Add-Member -NotePropertyName review_only -NotePropertyValue 2 -Force }
    if (-not $cfg.execution_engine.retry_policy.max_attempts_by_category.PSObject.Properties["refactor"] -or $null -eq $cfg.execution_engine.retry_policy.max_attempts_by_category.refactor) { $cfg.execution_engine.retry_policy.max_attempts_by_category | Add-Member -NotePropertyName refactor -NotePropertyValue 2 -Force }
    if (-not $cfg.execution_engine.PSObject.Properties["readiness_policy"] -or $null -eq $cfg.execution_engine.readiness_policy) {
        $cfg.execution_engine | Add-Member -NotePropertyName readiness_policy -NotePropertyValue ([pscustomobject]@{
                enabled = $true
                signal_path = "shared_state/tod_operator_chat_sweep_artifact_smoke.latest.json"
                max_artifact_age_minutes = 30
                display_max_artifact_age_minutes = 10
                block_actions = @("run-task")
                degrade_actions = @("engineer-run", "codex_handoff")
                block_states = @("stale", "invalid", "unknown")
                degrade_states = @("degraded", "stale", "invalid", "unknown")
                degrade_apply_plan = $true
                history_path = "shared_state/tod_execution_readiness_history.latest.json"
                history_max_entries = 50
            }) -Force
    }
    if (-not $cfg.execution_engine.readiness_policy.PSObject.Properties["enabled"] -or $null -eq $cfg.execution_engine.readiness_policy.enabled) { $cfg.execution_engine.readiness_policy.enabled = $true }
    if (-not $cfg.execution_engine.readiness_policy.PSObject.Properties["signal_path"] -or [string]::IsNullOrWhiteSpace([string]$cfg.execution_engine.readiness_policy.signal_path)) { $cfg.execution_engine.readiness_policy.signal_path = "shared_state/tod_operator_chat_sweep_artifact_smoke.latest.json" }
    if (-not $cfg.execution_engine.readiness_policy.PSObject.Properties["max_artifact_age_minutes"] -or $null -eq $cfg.execution_engine.readiness_policy.max_artifact_age_minutes) { $cfg.execution_engine.readiness_policy.max_artifact_age_minutes = 30 }
    if (-not $cfg.execution_engine.readiness_policy.PSObject.Properties["display_max_artifact_age_minutes"] -or $null -eq $cfg.execution_engine.readiness_policy.display_max_artifact_age_minutes) { $cfg.execution_engine.readiness_policy.display_max_artifact_age_minutes = [math]::Min([int]$cfg.execution_engine.readiness_policy.max_artifact_age_minutes, 10) }
    if (-not $cfg.execution_engine.readiness_policy.PSObject.Properties["block_actions"] -or $null -eq $cfg.execution_engine.readiness_policy.block_actions) { $cfg.execution_engine.readiness_policy.block_actions = @("run-task") }
    if (-not $cfg.execution_engine.readiness_policy.PSObject.Properties["degrade_actions"] -or $null -eq $cfg.execution_engine.readiness_policy.degrade_actions) { $cfg.execution_engine.readiness_policy.degrade_actions = @("engineer-run", "codex_handoff") }
    if (-not $cfg.execution_engine.readiness_policy.PSObject.Properties["block_states"] -or $null -eq $cfg.execution_engine.readiness_policy.block_states) { $cfg.execution_engine.readiness_policy.block_states = @("stale", "invalid", "unknown") }
    if (-not $cfg.execution_engine.readiness_policy.PSObject.Properties["degrade_states"] -or $null -eq $cfg.execution_engine.readiness_policy.degrade_states) { $cfg.execution_engine.readiness_policy.degrade_states = @("degraded", "stale", "invalid", "unknown") }
    if (-not $cfg.execution_engine.readiness_policy.PSObject.Properties["degrade_apply_plan"] -or $null -eq $cfg.execution_engine.readiness_policy.degrade_apply_plan) { $cfg.execution_engine.readiness_policy.degrade_apply_plan = $true }
    if (-not $cfg.execution_engine.readiness_policy.PSObject.Properties["history_path"] -or [string]::IsNullOrWhiteSpace([string]$cfg.execution_engine.readiness_policy.history_path)) { $cfg.execution_engine.readiness_policy.history_path = "shared_state/tod_execution_readiness_history.latest.json" }
    if (-not $cfg.execution_engine.readiness_policy.PSObject.Properties["history_max_entries"] -or $null -eq $cfg.execution_engine.readiness_policy.history_max_entries) { $cfg.execution_engine.readiness_policy.history_max_entries = 50 }
    $cfg.execution_engine.readiness_policy.block_actions = @($cfg.execution_engine.readiness_policy.block_actions | ForEach-Object { ([string]$_).ToLowerInvariant() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    $cfg.execution_engine.readiness_policy.degrade_actions = @($cfg.execution_engine.readiness_policy.degrade_actions | ForEach-Object { ([string]$_).ToLowerInvariant() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    $cfg.execution_engine.readiness_policy.block_states = @($cfg.execution_engine.readiness_policy.block_states | ForEach-Object { ([string]$_).ToLowerInvariant() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    $cfg.execution_engine.readiness_policy.degrade_states = @($cfg.execution_engine.readiness_policy.degrade_states | ForEach-Object { ([string]$_).ToLowerInvariant() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    $cfg.execution_engine.readiness_policy.max_artifact_age_minutes = [math]::Max(1, [math]::Min(1440, [int]$cfg.execution_engine.readiness_policy.max_artifact_age_minutes))
    $cfg.execution_engine.readiness_policy.display_max_artifact_age_minutes = [math]::Max(1, [math]::Min([int]$cfg.execution_engine.readiness_policy.max_artifact_age_minutes, [int]$cfg.execution_engine.readiness_policy.display_max_artifact_age_minutes))
    $cfg.execution_engine.readiness_policy.history_max_entries = [math]::Max(5, [math]::Min(500, [int]$cfg.execution_engine.readiness_policy.history_max_entries))

    if (-not $cfg.execution_engine.PSObject.Properties["routing_policy"] -or $null -eq $cfg.execution_engine.routing_policy) {
        $cfg.execution_engine | Add-Member -NotePropertyName routing_policy -NotePropertyValue ([pscustomobject]@{
                enabled = $true
                min_runs = 1
                min_success_rate = 75
                improvement_margin = 5
                source = "routing_policy_v1"
                allow_placeholder_for_code_change = $false
                prefer_stable_on_sync_warn = $true
                block_on_contract_drift = $true
                recent_failure_window = 5
                recent_failure_threshold = 2
                min_category_records_light = 10
                min_category_records_strong = 20
                drift_detection = [pscustomobject]@{
                    enabled = $true
                    recent_window = 20
                    baseline_window = 50
                    minimum_baseline_records = 10
                    failure_rate_multiplier = 1.5
                    retry_rate_threshold = 0.35
                    fallback_rate_multiplier = 1.5
                    fallback_rate_threshold = 0.3
                    guardrail_rate_multiplier = 1.8
                    guardrail_rate_threshold = 0.15
                    engine_score_drop_threshold = 0.2
                    confidence_penalty_failure_drift = 0.18
                    confidence_penalty_retry_high = 0.12
                    confidence_penalty_fallback_drift = 0.09
                    confidence_penalty_guardrail_spike = 0.1
                    confidence_penalty_score_drop = 0.12
                    score_penalty_failure_drift = 0.12
                    score_penalty_retry_high = 0.08
                    score_penalty_fallback_drift = 0.08
                    score_penalty_guardrail_spike = 0.1
                    score_penalty_score_drop = 0.12
                }
                weights = (Get-DefaultRoutingWeights)
            }) -Force
    }
    if ($null -eq $cfg.execution_engine.routing_policy.enabled) { $cfg.execution_engine.routing_policy.enabled = $true }
    if (-not $cfg.execution_engine.routing_policy.PSObject.Properties["min_runs"] -or $null -eq $cfg.execution_engine.routing_policy.min_runs) { $cfg.execution_engine.routing_policy.min_runs = 1 }
    if (-not $cfg.execution_engine.routing_policy.PSObject.Properties["min_success_rate"] -or $null -eq $cfg.execution_engine.routing_policy.min_success_rate) { $cfg.execution_engine.routing_policy.min_success_rate = 75 }
    if (-not $cfg.execution_engine.routing_policy.PSObject.Properties["improvement_margin"] -or $null -eq $cfg.execution_engine.routing_policy.improvement_margin) { $cfg.execution_engine.routing_policy.improvement_margin = 5 }
    if (-not $cfg.execution_engine.routing_policy.PSObject.Properties["source"] -or [string]::IsNullOrWhiteSpace([string]$cfg.execution_engine.routing_policy.source)) { $cfg.execution_engine.routing_policy.source = "routing_policy_v1" }
    if (-not $cfg.execution_engine.routing_policy.PSObject.Properties["allow_placeholder_for_code_change"] -or $null -eq $cfg.execution_engine.routing_policy.allow_placeholder_for_code_change) { $cfg.execution_engine.routing_policy.allow_placeholder_for_code_change = $false }
    if (-not $cfg.execution_engine.routing_policy.PSObject.Properties["prefer_stable_on_sync_warn"] -or $null -eq $cfg.execution_engine.routing_policy.prefer_stable_on_sync_warn) { $cfg.execution_engine.routing_policy.prefer_stable_on_sync_warn = $true }
    if (-not $cfg.execution_engine.routing_policy.PSObject.Properties["block_on_contract_drift"] -or $null -eq $cfg.execution_engine.routing_policy.block_on_contract_drift) { $cfg.execution_engine.routing_policy.block_on_contract_drift = $true }
    if (-not $cfg.execution_engine.routing_policy.PSObject.Properties["recent_failure_window"] -or $null -eq $cfg.execution_engine.routing_policy.recent_failure_window) { $cfg.execution_engine.routing_policy.recent_failure_window = 5 }
    if (-not $cfg.execution_engine.routing_policy.PSObject.Properties["recent_failure_threshold"] -or $null -eq $cfg.execution_engine.routing_policy.recent_failure_threshold) { $cfg.execution_engine.routing_policy.recent_failure_threshold = 2 }
    if (-not $cfg.execution_engine.routing_policy.PSObject.Properties["min_category_records_light"] -or $null -eq $cfg.execution_engine.routing_policy.min_category_records_light) { $cfg.execution_engine.routing_policy.min_category_records_light = 10 }
    if (-not $cfg.execution_engine.routing_policy.PSObject.Properties["min_category_records_strong"] -or $null -eq $cfg.execution_engine.routing_policy.min_category_records_strong) { $cfg.execution_engine.routing_policy.min_category_records_strong = 20 }
    if (-not $cfg.execution_engine.routing_policy.PSObject.Properties["drift_detection"] -or $null -eq $cfg.execution_engine.routing_policy.drift_detection) {
        $cfg.execution_engine.routing_policy | Add-Member -NotePropertyName drift_detection -NotePropertyValue ([pscustomobject]@{
                enabled = $true
                recent_window = 20
                baseline_window = 50
                minimum_baseline_records = 10
                failure_rate_multiplier = 1.5
                retry_rate_threshold = 0.35
                fallback_rate_multiplier = 1.5
                fallback_rate_threshold = 0.3
                guardrail_rate_multiplier = 1.8
                guardrail_rate_threshold = 0.15
                engine_score_drop_threshold = 0.2
                confidence_penalty_failure_drift = 0.18
                confidence_penalty_retry_high = 0.12
                confidence_penalty_fallback_drift = 0.09
                confidence_penalty_guardrail_spike = 0.1
                confidence_penalty_score_drop = 0.12
                score_penalty_failure_drift = 0.12
                score_penalty_retry_high = 0.08
                score_penalty_fallback_drift = 0.08
                score_penalty_guardrail_spike = 0.1
                score_penalty_score_drop = 0.12
            }) -Force
    }
    if (-not $cfg.execution_engine.routing_policy.drift_detection.PSObject.Properties["enabled"] -or $null -eq $cfg.execution_engine.routing_policy.drift_detection.enabled) { $cfg.execution_engine.routing_policy.drift_detection | Add-Member -NotePropertyName enabled -NotePropertyValue $true -Force }
    if (-not $cfg.execution_engine.routing_policy.drift_detection.PSObject.Properties["recent_window"] -or $null -eq $cfg.execution_engine.routing_policy.drift_detection.recent_window) { $cfg.execution_engine.routing_policy.drift_detection | Add-Member -NotePropertyName recent_window -NotePropertyValue 20 -Force }
    if (-not $cfg.execution_engine.routing_policy.drift_detection.PSObject.Properties["baseline_window"] -or $null -eq $cfg.execution_engine.routing_policy.drift_detection.baseline_window) { $cfg.execution_engine.routing_policy.drift_detection | Add-Member -NotePropertyName baseline_window -NotePropertyValue 50 -Force }
    if (-not $cfg.execution_engine.routing_policy.drift_detection.PSObject.Properties["minimum_baseline_records"] -or $null -eq $cfg.execution_engine.routing_policy.drift_detection.minimum_baseline_records) { $cfg.execution_engine.routing_policy.drift_detection | Add-Member -NotePropertyName minimum_baseline_records -NotePropertyValue 10 -Force }
    if (-not $cfg.execution_engine.routing_policy.drift_detection.PSObject.Properties["failure_rate_multiplier"] -or $null -eq $cfg.execution_engine.routing_policy.drift_detection.failure_rate_multiplier) { $cfg.execution_engine.routing_policy.drift_detection | Add-Member -NotePropertyName failure_rate_multiplier -NotePropertyValue 1.5 -Force }
    if (-not $cfg.execution_engine.routing_policy.drift_detection.PSObject.Properties["retry_rate_threshold"] -or $null -eq $cfg.execution_engine.routing_policy.drift_detection.retry_rate_threshold) { $cfg.execution_engine.routing_policy.drift_detection | Add-Member -NotePropertyName retry_rate_threshold -NotePropertyValue 0.35 -Force }
    if (-not $cfg.execution_engine.routing_policy.drift_detection.PSObject.Properties["fallback_rate_multiplier"] -or $null -eq $cfg.execution_engine.routing_policy.drift_detection.fallback_rate_multiplier) { $cfg.execution_engine.routing_policy.drift_detection | Add-Member -NotePropertyName fallback_rate_multiplier -NotePropertyValue 1.5 -Force }
    if (-not $cfg.execution_engine.routing_policy.drift_detection.PSObject.Properties["fallback_rate_threshold"] -or $null -eq $cfg.execution_engine.routing_policy.drift_detection.fallback_rate_threshold) { $cfg.execution_engine.routing_policy.drift_detection | Add-Member -NotePropertyName fallback_rate_threshold -NotePropertyValue 0.3 -Force }
    if (-not $cfg.execution_engine.routing_policy.drift_detection.PSObject.Properties["guardrail_rate_multiplier"] -or $null -eq $cfg.execution_engine.routing_policy.drift_detection.guardrail_rate_multiplier) { $cfg.execution_engine.routing_policy.drift_detection | Add-Member -NotePropertyName guardrail_rate_multiplier -NotePropertyValue 1.8 -Force }
    if (-not $cfg.execution_engine.routing_policy.drift_detection.PSObject.Properties["guardrail_rate_threshold"] -or $null -eq $cfg.execution_engine.routing_policy.drift_detection.guardrail_rate_threshold) { $cfg.execution_engine.routing_policy.drift_detection | Add-Member -NotePropertyName guardrail_rate_threshold -NotePropertyValue 0.15 -Force }
    if (-not $cfg.execution_engine.routing_policy.drift_detection.PSObject.Properties["engine_score_drop_threshold"] -or $null -eq $cfg.execution_engine.routing_policy.drift_detection.engine_score_drop_threshold) { $cfg.execution_engine.routing_policy.drift_detection | Add-Member -NotePropertyName engine_score_drop_threshold -NotePropertyValue 0.2 -Force }
    if (-not $cfg.execution_engine.routing_policy.drift_detection.PSObject.Properties["confidence_penalty_failure_drift"] -or $null -eq $cfg.execution_engine.routing_policy.drift_detection.confidence_penalty_failure_drift) { $cfg.execution_engine.routing_policy.drift_detection | Add-Member -NotePropertyName confidence_penalty_failure_drift -NotePropertyValue 0.18 -Force }
    if (-not $cfg.execution_engine.routing_policy.drift_detection.PSObject.Properties["confidence_penalty_retry_high"] -or $null -eq $cfg.execution_engine.routing_policy.drift_detection.confidence_penalty_retry_high) { $cfg.execution_engine.routing_policy.drift_detection | Add-Member -NotePropertyName confidence_penalty_retry_high -NotePropertyValue 0.12 -Force }
    if (-not $cfg.execution_engine.routing_policy.drift_detection.PSObject.Properties["confidence_penalty_fallback_drift"] -or $null -eq $cfg.execution_engine.routing_policy.drift_detection.confidence_penalty_fallback_drift) { $cfg.execution_engine.routing_policy.drift_detection | Add-Member -NotePropertyName confidence_penalty_fallback_drift -NotePropertyValue 0.09 -Force }
    if (-not $cfg.execution_engine.routing_policy.drift_detection.PSObject.Properties["confidence_penalty_guardrail_spike"] -or $null -eq $cfg.execution_engine.routing_policy.drift_detection.confidence_penalty_guardrail_spike) { $cfg.execution_engine.routing_policy.drift_detection | Add-Member -NotePropertyName confidence_penalty_guardrail_spike -NotePropertyValue 0.1 -Force }
    if (-not $cfg.execution_engine.routing_policy.drift_detection.PSObject.Properties["confidence_penalty_score_drop"] -or $null -eq $cfg.execution_engine.routing_policy.drift_detection.confidence_penalty_score_drop) { $cfg.execution_engine.routing_policy.drift_detection | Add-Member -NotePropertyName confidence_penalty_score_drop -NotePropertyValue 0.12 -Force }
    if (-not $cfg.execution_engine.routing_policy.drift_detection.PSObject.Properties["score_penalty_failure_drift"] -or $null -eq $cfg.execution_engine.routing_policy.drift_detection.score_penalty_failure_drift) { $cfg.execution_engine.routing_policy.drift_detection | Add-Member -NotePropertyName score_penalty_failure_drift -NotePropertyValue 0.12 -Force }
    if (-not $cfg.execution_engine.routing_policy.drift_detection.PSObject.Properties["score_penalty_retry_high"] -or $null -eq $cfg.execution_engine.routing_policy.drift_detection.score_penalty_retry_high) { $cfg.execution_engine.routing_policy.drift_detection | Add-Member -NotePropertyName score_penalty_retry_high -NotePropertyValue 0.08 -Force }
    if (-not $cfg.execution_engine.routing_policy.drift_detection.PSObject.Properties["score_penalty_fallback_drift"] -or $null -eq $cfg.execution_engine.routing_policy.drift_detection.score_penalty_fallback_drift) { $cfg.execution_engine.routing_policy.drift_detection | Add-Member -NotePropertyName score_penalty_fallback_drift -NotePropertyValue 0.08 -Force }
    if (-not $cfg.execution_engine.routing_policy.drift_detection.PSObject.Properties["score_penalty_guardrail_spike"] -or $null -eq $cfg.execution_engine.routing_policy.drift_detection.score_penalty_guardrail_spike) { $cfg.execution_engine.routing_policy.drift_detection | Add-Member -NotePropertyName score_penalty_guardrail_spike -NotePropertyValue 0.1 -Force }
    if (-not $cfg.execution_engine.routing_policy.drift_detection.PSObject.Properties["score_penalty_score_drop"] -or $null -eq $cfg.execution_engine.routing_policy.drift_detection.score_penalty_score_drop) { $cfg.execution_engine.routing_policy.drift_detection | Add-Member -NotePropertyName score_penalty_score_drop -NotePropertyValue 0.12 -Force }
    if (-not $cfg.execution_engine.routing_policy.PSObject.Properties["weights"] -or $null -eq $cfg.execution_engine.routing_policy.weights) {
        $cfg.execution_engine.routing_policy | Add-Member -NotePropertyName weights -NotePropertyValue (Get-DefaultRoutingWeights) -Force
    }
    $cfg.execution_engine.routing_policy.weights = Normalize-RoutingWeights -Weights $cfg.execution_engine.routing_policy.weights

    return $cfg
}

function Get-SupportedExecutionEngines {
    return @("codex", "local")
}

function Resolve-ExecutionEngineConfig {
    param(
        [Parameter(Mandatory = $true)]$Config,
        $State,
        [switch]$DisableAdaptiveRouting,
        [string]$TaskCategoryHint,
        $Task
    )

    $supported = @(Get-SupportedExecutionEngines)
    $active = ([string]$Config.execution_engine.active).ToLowerInvariant()
    $fallback = ([string]$Config.execution_engine.fallback).ToLowerInvariant()
    $allowFallback = [bool]$Config.execution_engine.allow_fallback
    $taskRouting = Resolve-LocalExecutionSuitability -Task $Task -TaskCategoryHint $TaskCategoryHint -State $State
    $resolvedTaskCategory = if ($taskRouting -and $taskRouting.PSObject.Properties['task_category']) { [string]$taskRouting.task_category } else { ([string]$TaskCategoryHint).ToLowerInvariant() }
    $policy = $Config.execution_engine.routing_policy
    $policyEnabled = $false
    $minRuns = 1
    $minSuccessRate = 75.0
    $improvementMargin = 5.0
    $policySource = "routing_policy_v1"
    $allowPlaceholderForCodeChange = $false
    $preferStableOnSyncWarn = $true
    $blockOnContractDrift = $true
    $recentFailureWindow = 5
    $recentFailureThreshold = 2
    $minCategoryRecordsLight = 10
    $minCategoryRecordsStrong = 20
    $driftDetectionPolicy = [pscustomobject]@{
        enabled = $true
        recent_window = 20
        baseline_window = 50
        minimum_baseline_records = 10
        failure_rate_multiplier = 1.5
        retry_rate_threshold = 0.35
        confidence_penalty_failure_drift = 0.18
        confidence_penalty_retry_high = 0.12
        score_penalty_failure_drift = 0.12
        score_penalty_retry_high = 0.08
    }
    $weights = Get-DefaultRoutingWeights
    $effectiveWeights = Normalize-RoutingWeights -Weights $weights

    if ($null -ne $policy) {
        if ($policy.PSObject.Properties["enabled"] -and $null -ne $policy.enabled) { $policyEnabled = [bool]$policy.enabled }
        if ($policy.PSObject.Properties["min_runs"] -and $null -ne $policy.min_runs) { $minRuns = [int]$policy.min_runs }
        if ($policy.PSObject.Properties["min_success_rate"] -and $null -ne $policy.min_success_rate) { $minSuccessRate = [double]$policy.min_success_rate }
        if ($policy.PSObject.Properties["improvement_margin"] -and $null -ne $policy.improvement_margin) { $improvementMargin = [double]$policy.improvement_margin }
        if ($policy.PSObject.Properties["source"] -and -not [string]::IsNullOrWhiteSpace([string]$policy.source)) { $policySource = [string]$policy.source }
        if ($policy.PSObject.Properties["allow_placeholder_for_code_change"] -and $null -ne $policy.allow_placeholder_for_code_change) { $allowPlaceholderForCodeChange = [bool]$policy.allow_placeholder_for_code_change }
        if ($policy.PSObject.Properties["prefer_stable_on_sync_warn"] -and $null -ne $policy.prefer_stable_on_sync_warn) { $preferStableOnSyncWarn = [bool]$policy.prefer_stable_on_sync_warn }
        if ($policy.PSObject.Properties["block_on_contract_drift"] -and $null -ne $policy.block_on_contract_drift) { $blockOnContractDrift = [bool]$policy.block_on_contract_drift }
        if ($policy.PSObject.Properties["recent_failure_window"] -and $null -ne $policy.recent_failure_window) { $recentFailureWindow = [int]$policy.recent_failure_window }
        if ($policy.PSObject.Properties["recent_failure_threshold"] -and $null -ne $policy.recent_failure_threshold) { $recentFailureThreshold = [int]$policy.recent_failure_threshold }
        if ($policy.PSObject.Properties["min_category_records_light"] -and $null -ne $policy.min_category_records_light) { $minCategoryRecordsLight = [int]$policy.min_category_records_light }
        if ($policy.PSObject.Properties["min_category_records_strong"] -and $null -ne $policy.min_category_records_strong) { $minCategoryRecordsStrong = [int]$policy.min_category_records_strong }
        if ($policy.PSObject.Properties["drift_detection"] -and $null -ne $policy.drift_detection) {
            $driftDetectionPolicy = $policy.drift_detection
        }
        if ($policy.PSObject.Properties["weights"] -and $null -ne $policy.weights) { $weights = $policy.weights }
    }

    if (-not $driftDetectionPolicy.PSObject.Properties["enabled"] -or $null -eq $driftDetectionPolicy.enabled) { $driftDetectionPolicy | Add-Member -NotePropertyName enabled -NotePropertyValue $true -Force }
    if (-not $driftDetectionPolicy.PSObject.Properties["recent_window"] -or $null -eq $driftDetectionPolicy.recent_window) { $driftDetectionPolicy | Add-Member -NotePropertyName recent_window -NotePropertyValue 20 -Force }
    if (-not $driftDetectionPolicy.PSObject.Properties["baseline_window"] -or $null -eq $driftDetectionPolicy.baseline_window) { $driftDetectionPolicy | Add-Member -NotePropertyName baseline_window -NotePropertyValue 50 -Force }
    if (-not $driftDetectionPolicy.PSObject.Properties["minimum_baseline_records"] -or $null -eq $driftDetectionPolicy.minimum_baseline_records) { $driftDetectionPolicy | Add-Member -NotePropertyName minimum_baseline_records -NotePropertyValue 10 -Force }
    if (-not $driftDetectionPolicy.PSObject.Properties["failure_rate_multiplier"] -or $null -eq $driftDetectionPolicy.failure_rate_multiplier) { $driftDetectionPolicy | Add-Member -NotePropertyName failure_rate_multiplier -NotePropertyValue 1.5 -Force }
    if (-not $driftDetectionPolicy.PSObject.Properties["retry_rate_threshold"] -or $null -eq $driftDetectionPolicy.retry_rate_threshold) { $driftDetectionPolicy | Add-Member -NotePropertyName retry_rate_threshold -NotePropertyValue 0.35 -Force }
    if (-not $driftDetectionPolicy.PSObject.Properties["fallback_rate_multiplier"] -or $null -eq $driftDetectionPolicy.fallback_rate_multiplier) { $driftDetectionPolicy | Add-Member -NotePropertyName fallback_rate_multiplier -NotePropertyValue 1.5 -Force }
    if (-not $driftDetectionPolicy.PSObject.Properties["fallback_rate_threshold"] -or $null -eq $driftDetectionPolicy.fallback_rate_threshold) { $driftDetectionPolicy | Add-Member -NotePropertyName fallback_rate_threshold -NotePropertyValue 0.3 -Force }
    if (-not $driftDetectionPolicy.PSObject.Properties["guardrail_rate_multiplier"] -or $null -eq $driftDetectionPolicy.guardrail_rate_multiplier) { $driftDetectionPolicy | Add-Member -NotePropertyName guardrail_rate_multiplier -NotePropertyValue 1.8 -Force }
    if (-not $driftDetectionPolicy.PSObject.Properties["guardrail_rate_threshold"] -or $null -eq $driftDetectionPolicy.guardrail_rate_threshold) { $driftDetectionPolicy | Add-Member -NotePropertyName guardrail_rate_threshold -NotePropertyValue 0.15 -Force }
    if (-not $driftDetectionPolicy.PSObject.Properties["engine_score_drop_threshold"] -or $null -eq $driftDetectionPolicy.engine_score_drop_threshold) { $driftDetectionPolicy | Add-Member -NotePropertyName engine_score_drop_threshold -NotePropertyValue 0.2 -Force }
    if (-not $driftDetectionPolicy.PSObject.Properties["confidence_penalty_failure_drift"] -or $null -eq $driftDetectionPolicy.confidence_penalty_failure_drift) { $driftDetectionPolicy | Add-Member -NotePropertyName confidence_penalty_failure_drift -NotePropertyValue 0.18 -Force }
    if (-not $driftDetectionPolicy.PSObject.Properties["confidence_penalty_retry_high"] -or $null -eq $driftDetectionPolicy.confidence_penalty_retry_high) { $driftDetectionPolicy | Add-Member -NotePropertyName confidence_penalty_retry_high -NotePropertyValue 0.12 -Force }
    if (-not $driftDetectionPolicy.PSObject.Properties["confidence_penalty_fallback_drift"] -or $null -eq $driftDetectionPolicy.confidence_penalty_fallback_drift) { $driftDetectionPolicy | Add-Member -NotePropertyName confidence_penalty_fallback_drift -NotePropertyValue 0.09 -Force }
    if (-not $driftDetectionPolicy.PSObject.Properties["confidence_penalty_guardrail_spike"] -or $null -eq $driftDetectionPolicy.confidence_penalty_guardrail_spike) { $driftDetectionPolicy | Add-Member -NotePropertyName confidence_penalty_guardrail_spike -NotePropertyValue 0.1 -Force }
    if (-not $driftDetectionPolicy.PSObject.Properties["confidence_penalty_score_drop"] -or $null -eq $driftDetectionPolicy.confidence_penalty_score_drop) { $driftDetectionPolicy | Add-Member -NotePropertyName confidence_penalty_score_drop -NotePropertyValue 0.12 -Force }
    if (-not $driftDetectionPolicy.PSObject.Properties["score_penalty_failure_drift"] -or $null -eq $driftDetectionPolicy.score_penalty_failure_drift) { $driftDetectionPolicy | Add-Member -NotePropertyName score_penalty_failure_drift -NotePropertyValue 0.12 -Force }
    if (-not $driftDetectionPolicy.PSObject.Properties["score_penalty_retry_high"] -or $null -eq $driftDetectionPolicy.score_penalty_retry_high) { $driftDetectionPolicy | Add-Member -NotePropertyName score_penalty_retry_high -NotePropertyValue 0.08 -Force }
    if (-not $driftDetectionPolicy.PSObject.Properties["score_penalty_fallback_drift"] -or $null -eq $driftDetectionPolicy.score_penalty_fallback_drift) { $driftDetectionPolicy | Add-Member -NotePropertyName score_penalty_fallback_drift -NotePropertyValue 0.08 -Force }
    if (-not $driftDetectionPolicy.PSObject.Properties["score_penalty_guardrail_spike"] -or $null -eq $driftDetectionPolicy.score_penalty_guardrail_spike) { $driftDetectionPolicy | Add-Member -NotePropertyName score_penalty_guardrail_spike -NotePropertyValue 0.1 -Force }
    if (-not $driftDetectionPolicy.PSObject.Properties["score_penalty_score_drop"] -or $null -eq $driftDetectionPolicy.score_penalty_score_drop) { $driftDetectionPolicy | Add-Member -NotePropertyName score_penalty_score_drop -NotePropertyValue 0.12 -Force }
    if (-not $driftDetectionPolicy.PSObject.Properties["normalization_window_runs"] -or $null -eq $driftDetectionPolicy.normalization_window_runs) { $driftDetectionPolicy | Add-Member -NotePropertyName normalization_window_runs -NotePropertyValue 8 -Force }
    if (-not $driftDetectionPolicy.PSObject.Properties["stable_run_decay_floor"] -or $null -eq $driftDetectionPolicy.stable_run_decay_floor) { $driftDetectionPolicy | Add-Member -NotePropertyName stable_run_decay_floor -NotePropertyValue 0.2 -Force }
    if (-not $driftDetectionPolicy.PSObject.Properties["quarantine_enabled"] -or $null -eq $driftDetectionPolicy.quarantine_enabled) { $driftDetectionPolicy | Add-Member -NotePropertyName quarantine_enabled -NotePropertyValue $true -Force }
    if (-not $driftDetectionPolicy.PSObject.Properties["quarantine_alert_state"] -or [string]::IsNullOrWhiteSpace([string]$driftDetectionPolicy.quarantine_alert_state)) { $driftDetectionPolicy | Add-Member -NotePropertyName quarantine_alert_state -NotePropertyValue "critical" -Force }

    $weights = Normalize-RoutingWeights -Weights $weights
    $effectiveWeights = $weights
    if ($null -ne $State -and $State.PSObject.Properties["routing_feedback"] -and $State.routing_feedback -and $State.routing_feedback.PSObject.Properties["learned_weights"]) {
        $learnedWeights = Normalize-RoutingWeights -Weights $State.routing_feedback.learned_weights
        $feedbackSample = if ($State.routing_feedback.PSObject.Properties["sample_size"] -and $null -ne $State.routing_feedback.sample_size) { [int]$State.routing_feedback.sample_size } else { 0 }
        $learningFactor = [math]::Min(0.6, [math]::Max(0.0, ($feedbackSample / 100.0)))
        $effectiveWeights = Normalize-RoutingWeights -Weights ([pscustomobject]@{
                availability = ((1.0 - $learningFactor) * [double]$weights.availability) + ($learningFactor * [double]$learnedWeights.availability)
                task_category_support = ((1.0 - $learningFactor) * [double]$weights.task_category_support) + ($learningFactor * [double]$learnedWeights.task_category_support)
                historical_success = ((1.0 - $learningFactor) * [double]$weights.historical_success) + ($learningFactor * [double]$learnedWeights.historical_success)
                recent_fallback = ((1.0 - $learningFactor) * [double]$weights.recent_fallback) + ($learningFactor * [double]$learnedWeights.recent_fallback)
                review_quality = ((1.0 - $learningFactor) * [double]$weights.review_quality) + ($learningFactor * [double]$learnedWeights.review_quality)
                failure_rate = ((1.0 - $learningFactor) * [double]$weights.failure_rate) + ($learningFactor * [double]$learnedWeights.failure_rate)
                review_corrections = ((1.0 - $learningFactor) * [double]$weights.review_corrections) + ($learningFactor * [double]$learnedWeights.review_corrections)
                latency = ((1.0 - $learningFactor) * [double]$weights.latency) + ($learningFactor * [double]$learnedWeights.latency)
            })
    }

    if ($supported -notcontains $active) {
        throw "Invalid execution_engine.active '$active'. Supported engines: $($supported -join ', ')."
    }

    if ($allowFallback -and $supported -notcontains $fallback) {
        throw "Invalid execution_engine.fallback '$fallback'. Supported engines: $($supported -join ', ')."
    }

    $routingApplied = $false
    $routingReason = "static_config"
    $routingBlocked = $false
    $selectionReason = "Selected configured default engine."
    $candidateEngines = @($active)
    if ($allowFallback -and -not [string]::IsNullOrWhiteSpace($fallback) -and $fallback -ne $active) { $candidateEngines += $fallback }
    $candidateEngines = @($candidateEngines | Select-Object -Unique)
    $confidence = 0.5
    $sampleMode = "none"
    $suitabilityLocked = $false

    if (-not $DisableAdaptiveRouting) {
        switch ([string]$taskRouting.classification) {
            'local_supported' {
                if ($supported -contains 'local') {
                    $previousPrimary = $active
                    $active = 'local'
                    if ($allowFallback -and $previousPrimary -ne 'local') {
                        $fallback = $previousPrimary
                    }
                    elseif ($supported -contains 'codex' -and $active -ne 'codex') {
                        $fallback = 'codex'
                    }
                    $allowFallback = [bool]$taskRouting.codex_allowed
                    $routingApplied = $true
                    $routingReason = 'local_suitability_local_supported'
                    $selectionReason = 'Task matched local_supported suitability, so local execution is selected before any Codex handoff.'
                    if ($taskRouting.local_reuse -and [bool]$taskRouting.local_reuse.matched) {
                        $selectionReason = "$selectionReason Recent local execution memory matched this category or file set."
                    }
                    $confidence = if ($taskRouting.local_reuse -and [bool]$taskRouting.local_reuse.matched) { 0.92 } else { 0.86 }
                    $sampleMode = 'suitability_locked'
                    $suitabilityLocked = $true
                }
            }
            'local_possible' {
                if ($supported -contains 'local') {
                    $previousPrimary = $active
                    $active = 'local'
                    if ($allowFallback -and $previousPrimary -ne 'local') {
                        $fallback = $previousPrimary
                    }
                    elseif ($supported -contains 'codex' -and $active -ne 'codex') {
                        $fallback = 'codex'
                    }
                    $allowFallback = [bool]$taskRouting.codex_allowed
                    $routingApplied = $true
                    $routingReason = 'local_suitability_local_possible'
                    $selectionReason = 'Task matched local_possible suitability, so TOD will try local execution before Codex fallback.'
                    if ($taskRouting.local_reuse -and [bool]$taskRouting.local_reuse.matched) {
                        $selectionReason = "$selectionReason Recent local execution memory increased confidence in the local-first attempt."
                    }
                    $confidence = if ($taskRouting.local_reuse -and [bool]$taskRouting.local_reuse.matched) { 0.82 } else { 0.74 }
                    $sampleMode = 'suitability_locked'
                    $suitabilityLocked = $true
                }
            }
            'codex_required' {
                if ($active -eq 'local' -and $supported -contains 'codex') {
                    $previousPrimary = $active
                    $active = 'codex'
                    if ($allowFallback -and $previousPrimary -ne 'codex') {
                        $fallback = $previousPrimary
                    }
                    $routingApplied = $true
                    $routingReason = 'local_suitability_codex_required'
                    $selectionReason = 'Task matched codex_required suitability, so Codex remains the primary executor.'
                    $confidence = 0.84
                    $sampleMode = 'suitability_locked'
                    $suitabilityLocked = $true
                }
            }
        }
    }

    $candidateEngines = @($active)
    if ($allowFallback -and -not [string]::IsNullOrWhiteSpace($fallback) -and $fallback -ne $active) { $candidateEngines += $fallback }
    $candidateEngines = @($candidateEngines | Select-Object -Unique)

    $syncStatus = ""
    if ($State -and $State.PSObject.Properties["sync_state"] -and $State.sync_state -and $State.sync_state.PSObject.Properties["last_comparison"] -and $State.sync_state.last_comparison) {
        $syncStatus = [string]$State.sync_state.last_comparison.status
    }

    if ($blockOnContractDrift -and $syncStatus -eq "breaking") {
        $routingBlocked = $true
        $routingReason = "contract_drift_breaking"
        $selectionReason = "Execution blocked: contract drift is breaking. Escalate instead of auto-running."
        $confidence = 1.0
    }

    $policySnapshot = [pscustomobject]@{
        enabled = $policyEnabled
        min_runs = $minRuns
        min_success_rate = $minSuccessRate
        improvement_margin = $improvementMargin
        source = $policySource
        allow_placeholder_for_code_change = $allowPlaceholderForCodeChange
        prefer_stable_on_sync_warn = $preferStableOnSyncWarn
        block_on_contract_drift = $blockOnContractDrift
        recent_failure_window = $recentFailureWindow
        recent_failure_threshold = $recentFailureThreshold
        min_category_records_light = $minCategoryRecordsLight
        min_category_records_strong = $minCategoryRecordsStrong
        drift_detection = $driftDetectionPolicy
        weights = $weights
        effective_weights = $effectiveWeights
    }

    $activeMetrics = $null
    $fallbackMetrics = $null
    $activeHealth = $null
    $fallbackHealth = $null
    $activeHealthBand = "unknown"
    $fallbackHealthBand = "unknown"
    $activeDrift = $null
    $fallbackDrift = $null
    $selectedDrift = $null
    if ((-not $routingBlocked) -and (-not $DisableAdaptiveRouting) -and $policyEnabled -and $null -ne $State -and $State.PSObject.Properties["engine_performance"] -and $State.engine_performance -and $State.engine_performance.PSObject.Properties["records"]) {
        $perfSummary = Get-EnginePerformanceSummary -State $State -TaskCategoryFilter $resolvedTaskCategory
        $activeMetrics = @($perfSummary.by_engine | Where-Object { ([string]$_.engine).ToLowerInvariant() -eq $active } | Select-Object -First 1)
        $fallbackMetrics = @($perfSummary.by_engine | Where-Object { ([string]$_.engine).ToLowerInvariant() -eq $fallback } | Select-Object -First 1)

        $categorySampleCount = [int]$perfSummary.total_records
        if ($categorySampleCount -lt $minCategoryRecordsLight) {
            $sampleMode = "advisory_default_dominant"
        }
        elseif ($categorySampleCount -lt $minCategoryRecordsStrong) {
            $sampleMode = "advisory_balanced"
        }
        else {
            $sampleMode = "history_weighted"
        }

        $historyWeightMultiplier = switch ($sampleMode) {
            "advisory_default_dominant" { 0.15 }
            "advisory_balanced" { 0.45 }
            default { 1.0 }
        }

        $activeRuns = if ($activeMetrics) { [int]$activeMetrics.total_runs } else { 0 }
        $activeSuccess = if ($activeMetrics) { [double]$activeMetrics.pass_rate } else { 0.0 }
        $fallbackRuns = if ($fallbackMetrics) { [int]$fallbackMetrics.total_runs } else { 0 }
        $fallbackSuccess = if ($fallbackMetrics) { [double]$fallbackMetrics.pass_rate } else { 0.0 }

        $activeDrift = Get-RoutingDriftSignal -State $State -RoutingPolicy $policySnapshot -EngineFilter $active -TaskCategoryFilter $resolvedTaskCategory
        if ($allowFallback -and $fallback -ne $active) {
            $fallbackDrift = Get-RoutingDriftSignal -State $State -RoutingPolicy $policySnapshot -EngineFilter $fallback -TaskCategoryFilter $resolvedTaskCategory
        }

        $recentCategoryRecordsForPenalty = @($State.engine_performance.records | Where-Object {
                $candidate = $_
                if ($null -eq $candidate) { return $false }
                if (-not $candidate.PSObject.Properties['task_category']) { return $false }
                ([string]$candidate.task_category).ToLowerInvariant() -eq $resolvedTaskCategory.ToLowerInvariant()
            } | Sort-Object -Property created_at -Descending | Select-Object -First $recentFailureWindow)
        $wrapperOnlyPenalties = @{}
        foreach ($record in $recentCategoryRecordsForPenalty) {
            $wrapperOnlyEngines = @()
            if ($record.PSObject.Properties['wrapper_only_engines'] -and $null -ne $record.wrapper_only_engines) {
                $wrapperOnlyEngines = @($record.wrapper_only_engines | ForEach-Object { ([string]$_).ToLowerInvariant() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
            }
            elseif ($record.PSObject.Properties['wrapper_only_codex_seen'] -and [bool]$record.wrapper_only_codex_seen) {
                $wrapperOnlyEngines = @('codex')
            }

            foreach ($engineName in $wrapperOnlyEngines) {
                if (-not $wrapperOnlyPenalties.ContainsKey($engineName)) {
                    $wrapperOnlyPenalties[$engineName] = 0
                }
                $wrapperOnlyPenalties[$engineName] = [int]$wrapperOnlyPenalties[$engineName] + 1
            }
        }

        function Get-DriftAlertRank {
            param([string]$State)
            switch (([string]$State).ToLowerInvariant()) {
                "critical" { return 3 }
                "degraded" { return 2 }
                "warning" { return 1 }
                default { return 0 }
            }
        }

        $quarantineEnabled = if ($driftDetectionPolicy.PSObject.Properties["quarantine_enabled"] -and $null -ne $driftDetectionPolicy.quarantine_enabled) { [bool]$driftDetectionPolicy.quarantine_enabled } else { $true }
        $quarantineState = if ($driftDetectionPolicy.PSObject.Properties["quarantine_alert_state"] -and -not [string]::IsNullOrWhiteSpace([string]$driftDetectionPolicy.quarantine_alert_state)) { ([string]$driftDetectionPolicy.quarantine_alert_state).ToLowerInvariant() } else { "critical" }

        if ((-not $routingBlocked) -and (-not $routingApplied) -and $quarantineEnabled -and $allowFallback -and $fallback -ne $active) {
            $activeAlert = if ($activeDrift -and $activeDrift.PSObject.Properties["alert_state"]) { [string]$activeDrift.alert_state } else { "stable" }
            $fallbackAlert = if ($fallbackDrift -and $fallbackDrift.PSObject.Properties["alert_state"]) { [string]$fallbackDrift.alert_state } else { "stable" }

            if ((Get-DriftAlertRank -State $activeAlert) -ge (Get-DriftAlertRank -State $quarantineState) -and (Get-DriftAlertRank -State $fallbackAlert) -lt (Get-DriftAlertRank -State $quarantineState)) {
                $active = $fallback
                $routingApplied = $true
                $routingReason = "drift_quarantine_active_deprefer"
                $selectionReason = "Active engine drift state '$activeAlert' triggered temporary de-preference/quarantine; switched to fallback engine with drift state '$fallbackAlert'."
                $confidence = 0.91
            }
        }

        $scoresByEngine = @{}
        $healthMap = @{}
        $healthSummary = Get-EngineHealthSummary -State $State -Window $recentFailureWindow
        foreach ($eh in @($healthSummary.by_engine)) {
            $ek = ([string]$eh.engine).ToLowerInvariant()
            $healthMap[$ek] = $eh
        }

        function Get-HealthBandMultiplier {
            param($HealthRecord)
            if ($null -eq $HealthRecord) { return 0.9 }

            switch ([string]$HealthRecord.health_band) {
                "healthy" { return 1.0 }
                "watch" { return 0.9 }
                "degraded" { return 0.75 }
                "critical" { return 0.55 }
                default { return 0.9 }
            }
        }

        $activeHealth = if ($healthMap.ContainsKey($active)) { $healthMap[$active] } else { $null }
        $fallbackHealth = if ($healthMap.ContainsKey($fallback)) { $healthMap[$fallback] } else { $null }
        $activeHealthBand = if ($activeHealth) { [string]$activeHealth.health_band } else { "unknown" }
        $fallbackHealthBand = if ($fallbackHealth) { [string]$fallbackHealth.health_band } else { "unknown" }

        $latencyCandidates = @()
        if ($activeMetrics -and $activeMetrics.PSObject.Properties["average_latency_ms"] -and $null -ne $activeMetrics.average_latency_ms) { $latencyCandidates += [double]$activeMetrics.average_latency_ms }
        if ($fallbackMetrics -and $fallbackMetrics.PSObject.Properties["average_latency_ms"] -and $null -ne $fallbackMetrics.average_latency_ms) { $latencyCandidates += [double]$fallbackMetrics.average_latency_ms }
        $latencyMin = if (@($latencyCandidates).Count -gt 0) { [double](@($latencyCandidates | Measure-Object -Minimum).Minimum) } else { $null }
        $latencyMax = if (@($latencyCandidates).Count -gt 0) { [double](@($latencyCandidates | Measure-Object -Maximum).Maximum) } else { $null }

        function Get-WeightedEngineScore {
            param(
                [string]$EngineName,
                $Metrics,
                [double]$MinRuns,
                [double]$LatencyMin,
                [double]$LatencyMax,
                $Weights
            )

            $availabilityScore = 1.0
            $taskSupportScore = if ($Metrics) { [math]::Min(1.0, ([double]$Metrics.total_runs / [math]::Max($MinRuns, 1.0))) } else { 0.15 }
            $successScore = if ($Metrics) { ([double]$Metrics.pass_rate / 100.0) } else { 0.0 }
            $fallbackSafetyScore = if ($Metrics) { 1.0 - ([double]$Metrics.fallback_frequency / 100.0) } else { 0.5 }
            $reviewQualityScore = if ($Metrics -and $Metrics.PSObject.Properties["average_review_outcome"] -and $null -ne $Metrics.average_review_outcome) { [double]$Metrics.average_review_outcome } else { 0.5 }
            $failureSafetyScore = if ($Metrics) { 1.0 - ([double]$Metrics.escalation_rate / 100.0) } else { 0.5 }
            $correctionSafetyScore = if ($Metrics) { 1.0 - ([double]$Metrics.revise_rate / 100.0) } else { 0.5 }

            $latencyScore = 0.5
            if ($Metrics -and $Metrics.PSObject.Properties["average_latency_ms"] -and $null -ne $Metrics.average_latency_ms -and $null -ne $LatencyMin -and $null -ne $LatencyMax) {
                $engineLatency = [double]$Metrics.average_latency_ms
                if ($LatencyMax -gt $LatencyMin) {
                    $latencyScore = 1.0 - (($engineLatency - $LatencyMin) / ($LatencyMax - $LatencyMin))
                }
                else {
                    $latencyScore = 0.5
                }
            }

            $raw =
            ([double]$Weights.availability * $availabilityScore) +
            ([double]$Weights.task_category_support * $taskSupportScore) +
            ([double]$Weights.historical_success * $successScore) +
            ([double]$Weights.recent_fallback * $fallbackSafetyScore) +
            ([double]$Weights.review_quality * $reviewQualityScore) +
            ([double]$Weights.failure_rate * $failureSafetyScore) +
            ([double]$Weights.review_corrections * $correctionSafetyScore) +
            ([double]$Weights.latency * $latencyScore)

            return [math]::Max(0.0, [math]::Min(1.0, [double]$raw))
        }

        $activeScore = Get-WeightedEngineScore -EngineName $active -Metrics $activeMetrics -MinRuns $minRuns -LatencyMin $latencyMin -LatencyMax $latencyMax -Weights $effectiveWeights
        if ($activeDrift -and $activeDrift.PSObject.Properties["score_penalty"] -and $null -ne $activeDrift.score_penalty) {
            $activeScore = [math]::Max(0.0, ([double]$activeScore - [double]$activeDrift.score_penalty))
        }
        if ($wrapperOnlyPenalties.ContainsKey($active)) {
            $activeScore = [math]::Max(0.0, ([double]$activeScore - (0.2 * ([math]::Min(1.0, ([double]$wrapperOnlyPenalties[$active] / [math]::Max(1.0, [double]$recentFailureWindow)))))))
        }
        $activeScore = [math]::Round(([double]$activeScore * (Get-HealthBandMultiplier -HealthRecord $activeHealth)), 6)
        $scoresByEngine[$active] = $activeScore
        $fallbackScore = $null
        if ($allowFallback -and $fallback -ne $active) {
            $fallbackScore = Get-WeightedEngineScore -EngineName $fallback -Metrics $fallbackMetrics -MinRuns $minRuns -LatencyMin $latencyMin -LatencyMax $latencyMax -Weights $effectiveWeights
            if ($fallbackDrift -and $fallbackDrift.PSObject.Properties["score_penalty"] -and $null -ne $fallbackDrift.score_penalty) {
                $fallbackScore = [math]::Max(0.0, ([double]$fallbackScore - [double]$fallbackDrift.score_penalty))
            }
            if ($wrapperOnlyPenalties.ContainsKey($fallback)) {
                $fallbackScore = [math]::Max(0.0, ([double]$fallbackScore - (0.2 * ([math]::Min(1.0, ([double]$wrapperOnlyPenalties[$fallback] / [math]::Max(1.0, [double]$recentFailureWindow)))))))
            }
            $fallbackScore = [math]::Round(([double]$fallbackScore * (Get-HealthBandMultiplier -HealthRecord $fallbackHealth)), 6)
            $scoresByEngine[$fallback] = $fallbackScore
        }

        if ((-not $routingBlocked) -and (-not $routingApplied) -and $allowFallback -and $fallback -ne $active) {
            $activeBand = if ($activeHealth) { [string]$activeHealth.health_band } else { "watch" }
            $fallbackBand = if ($fallbackHealth) { [string]$fallbackHealth.health_band } else { "watch" }
            if ($activeBand -eq "critical" -and $fallbackBand -ne "critical") {
                $active = $fallback
                $routingApplied = $true
                $routingReason = "health_band_prefer_non_critical"
                $selectionReason = "Active engine health is critical; switched to non-critical fallback engine."
                $confidence = 0.93
            }
        }

        if ((-not $suitabilityLocked) -and $active -eq "local" -and $resolvedTaskCategory -eq "code_change" -and (-not $allowPlaceholderForCodeChange)) {
            if ($allowFallback -and $fallback -ne $active) {
                $active = $fallback
                $routingApplied = $true
                $routingReason = "guardrail_placeholder_restricted_switch_fallback"
                $selectionReason = "Placeholder engine is restricted for code_change; switched to fallback engine."
                $confidence = 0.95
            }
            else {
                $routingBlocked = $true
                $routingReason = "guardrail_placeholder_restricted_block"
                $selectionReason = "Placeholder engine is restricted for code_change and no alternate engine is available."
                $confidence = 1.0
            }
        }

        if ((-not $routingBlocked) -and $allowFallback -and $fallback -ne $active) {
            $blockedEngines = @()
            if ((-not $suitabilityLocked) -and $active -eq "local" -and $resolvedTaskCategory -eq "code_change" -and (-not $allowPlaceholderForCodeChange)) { $blockedEngines += $active }
            if ((-not $suitabilityLocked) -and $fallback -eq "local" -and $resolvedTaskCategory -eq "code_change" -and (-not $allowPlaceholderForCodeChange)) { $blockedEngines += $fallback }

            $recentCategoryRecords = @($State.engine_performance.records | Where-Object {
                    $candidate = $_
                    if ($null -eq $candidate) { return $false }

                    $propertyNames = if ($candidate.PSObject) { @($candidate.PSObject.Properties.Name) } else { @() }
                    if (-not (@($propertyNames) -contains 'task_category')) { return $false }

                    ([string]$candidate.task_category).ToLowerInvariant() -eq $resolvedTaskCategory.ToLowerInvariant()
                } | Sort-Object -Property created_at -Descending | Select-Object -First $recentFailureWindow)
            $recentFailuresByEngine = @{}
            foreach ($rr in $recentCategoryRecords) {
                $rk = ([string]$rr.engine).ToLowerInvariant()
                if (-not $recentFailuresByEngine.ContainsKey($rk)) { $recentFailuresByEngine[$rk] = 0 }
                if (-not [bool]$rr.success) { $recentFailuresByEngine[$rk] = [int]$recentFailuresByEngine[$rk] + 1 }
            }

            if ($recentFailuresByEngine.ContainsKey($active) -and [int]$recentFailuresByEngine[$active] -ge $recentFailureThreshold) { $blockedEngines += $active }
            if ($recentFailuresByEngine.ContainsKey($fallback) -and [int]$recentFailuresByEngine[$fallback] -ge $recentFailureThreshold) { $blockedEngines += $fallback }
            $blockedEngines = @($blockedEngines | Select-Object -Unique)

            if ($blockedEngines -contains $active -and -not ($blockedEngines -contains $fallback)) {
                $active = $fallback
                $routingApplied = $true
                $routingReason = "guardrail_switch_blocked_active"
                $selectionReason = "Configured active engine was blocked by guardrails; fallback engine selected."
                $confidence = 0.9
            }
            elseif (($blockedEngines -contains $active) -and ($blockedEngines -contains $fallback)) {
                $routingBlocked = $true
                $routingReason = "guardrail_all_candidates_blocked"
                $selectionReason = "All candidate engines blocked by guardrails for this category; escalate instead of auto-running."
                $confidence = 1.0
            }

            if ((-not $routingBlocked) -and (-not $suitabilityLocked) -and $activeRuns -lt $minRuns -and $fallbackRuns -ge $minRuns) {
                $active = $fallback
                $routingApplied = $true
                $routingReason = "no_active_history_use_fallback"
                $selectionReason = "Fallback chosen because active engine has insufficient history in this category."
                $confidence = 0.68
            }
            elseif ((-not $routingBlocked) -and (-not $suitabilityLocked) -and $activeRuns -ge $minRuns -and $activeSuccess -lt $minSuccessRate -and $fallbackRuns -ge 1 -and $fallbackSuccess -ge ($activeSuccess + ($improvementMargin / [math]::Max($historyWeightMultiplier, 0.15)))) {
                $active = $fallback
                $routingApplied = $true
                $routingReason = "performance_policy_switch"
                $selectionReason = "Fallback chosen due to stronger category performance and lower observed risk."
                $confidence = [math]::Round((0.62 + (0.18 * $historyWeightMultiplier)), 2)
            }

            if ((-not $routingBlocked) -and (-not $routingApplied) -and (-not $suitabilityLocked) -and $null -ne $fallbackScore) {
                $requiredAdvantage = ($improvementMargin / 100.0) / [math]::Max($historyWeightMultiplier, 0.2)
                if (($fallbackScore - $activeScore) -ge $requiredAdvantage -and $fallbackRuns -ge 1) {
                    $active = $fallback
                    $routingApplied = $true
                    $routingReason = "weighted_history_score_switch"
                    $selectionReason = "Fallback chosen by weighted history score (success, failures, review corrections, latency) with health bands active=$activeHealthBand fallback=$fallbackHealthBand."
                    $confidence = [math]::Round([math]::Min(0.98, 0.5 + (0.45 * [double]$fallbackScore)), 2)
                }
            }

            if ((-not $routingBlocked) -and (-not $suitabilityLocked) -and $preferStableOnSyncWarn -and $syncStatus -eq "warn") {
                $activeFallbackRate = if ($activeMetrics) { [double]$activeMetrics.fallback_frequency } else { 100.0 }
                $fallbackFallbackRate = if ($fallbackMetrics) { [double]$fallbackMetrics.fallback_frequency } else { 100.0 }
                if ($fallbackFallbackRate + 5 -lt $activeFallbackRate) {
                    $active = $fallback
                    $routingApplied = $true
                    $routingReason = "sync_warn_prefer_stable_engine"
                    $selectionReason = "Sync status is warn; selected the more stable engine with lower fallback frequency."
                    $confidence = [math]::Round((0.7 + (0.1 * $historyWeightMultiplier)), 2)
                }
            }

            if ((-not $routingBlocked) -and -not $routingApplied) {
                $selectionReason = "Configured default engine retained; history considered advisory with current sample size and health band active=$activeHealthBand."
                $selectedScore = if ($scoresByEngine.ContainsKey($active)) { [double]$scoresByEngine[$active] } else { 0.5 }
                $confidenceFloor = if ($sampleMode -eq "history_weighted") { 0.58 } elseif ($sampleMode -eq "advisory_balanced") { 0.54 } else { 0.5 }
                $confidence = [math]::Round([math]::Min(0.98, [math]::Max($confidenceFloor, $confidenceFloor + (0.4 * $selectedScore * $historyWeightMultiplier))), 2)
            }
        }
    }

    if ($activeDrift -or $fallbackDrift) {
        $selectedDrift = $activeDrift
        if ($active -eq $fallback -and $fallbackDrift) {
            $selectedDrift = $fallbackDrift
        }

        if ((-not $routingBlocked) -and $selectedDrift -and $selectedDrift.PSObject.Properties["confidence_penalty"] -and $null -ne $selectedDrift.confidence_penalty) {
            $penalty = [double]$selectedDrift.confidence_penalty
            if ($penalty -gt 0) {
                $confidence = [math]::Max(0.2, [math]::Round(([double]$confidence - $penalty), 4))
                $selectionReason = "$selectionReason Drift-adjusted confidence applied (penalty=$([math]::Round($penalty, 3)))."
            }
        }
    }

    if ($DisableAdaptiveRouting -and -not $routingBlocked) {
        $selectionReason = "Configured engine forced by operator override."
        $confidence = 1.0
        $sampleMode = "forced"
    }

    return [pscustomobject]@{
        active = $active
        fallback = $fallback
        allow_fallback = $allowFallback
        fallback_reason_codes = @($taskRouting.fallback_reason_codes)
        retry_policy = $Config.execution_engine.retry_policy
        supported = @($supported)
        routing = [pscustomobject]@{
            applied = $routingApplied
            reason = $(if ($DisableAdaptiveRouting) { "forced_configured_engine" } else { $routingReason })
            disabled = [bool]$DisableAdaptiveRouting
            blocked = [bool]$routingBlocked
            task_category = $resolvedTaskCategory
            source = $policySource
            confidence = [math]::Round($confidence, 4)
            selection_reason = $selectionReason
            candidate_engines = @($candidateEngines)
            sample_mode = $sampleMode
            suitability = $taskRouting
            policy = $policySnapshot
            active_metrics = $activeMetrics
            fallback_metrics = $fallbackMetrics
            health = [pscustomobject]@{
                active = $activeHealth
                fallback = $fallbackHealth
            }
            drift = [pscustomobject]@{
                active = $activeDrift
                fallback = $fallbackDrift
                selected = $selectedDrift
            }
        }
    }
}

function Get-ActiveEngineMetadata {
    param([Parameter(Mandatory = $true)]$EngineConfig)

    [pscustomobject]@{
        name = [string]$EngineConfig.active
        version = "config-default"
        decision = "selected"
        selected_at = Get-UtcNow
    }
}

function Get-TaskFromState {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][string]$TaskId
    )

    return @($State.tasks | Where-Object {
            ([string]$_.id -eq $TaskId) -or
            (($_.PSObject.Properties["remote_task_id"]) -and ([string]$_.remote_task_id -eq $TaskId))
        } | Select-Object -First 1)
}

function Test-IsBridgeRuntimeTask {
    param($Task)

    if ($null -eq $Task) {
        return $false
    }

    $taskCategory = if ($Task.PSObject.Properties['task_category']) { [string]$Task.task_category } else { '' }
    if ([string]::Equals($taskCategory, 'bridge_runtime', [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    $source = if ($Task.PSObject.Properties['source']) { [string]$Task.source } else { '' }
    return [string]::Equals($source, 'bridge_runtime_sync', [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-ObjectiveTaskPartition {
    param(
        [Parameter(Mandatory = $true)]$Tasks,
        [string]$ObjectiveId
    )

    $objectiveTasks = if ([string]::IsNullOrWhiteSpace($ObjectiveId)) {
        @()
    }
    else {
        @($Tasks | Where-Object { [string]$_.objective_id -eq [string]$ObjectiveId })
    }

    $canonicalTasks = @($objectiveTasks | Where-Object { -not (Test-IsBridgeRuntimeTask -Task $_) })
    $bridgeRuntimeTasks = @($objectiveTasks | Where-Object { Test-IsBridgeRuntimeTask -Task $_ })

    return [pscustomobject]@{
        all = @($objectiveTasks)
        canonical = @($canonicalTasks)
        bridge_runtime = @($bridgeRuntimeTasks)
    }
}

function Get-TaskStatusBreakdown {
    param([Parameter(Mandatory = $true)]$Tasks)

    $statusCounts = @{}
    foreach ($task in @($Tasks)) {
        $statusValue = if ($task.PSObject.Properties['status'] -and -not [string]::IsNullOrWhiteSpace([string]$task.status)) { [string]$task.status } else { 'unknown' }
        $statusKey = $statusValue.Trim().ToLowerInvariant()
        if (-not $statusCounts.ContainsKey($statusKey)) {
            $statusCounts[$statusKey] = 0
        }
        $statusCounts[$statusKey] = [int]$statusCounts[$statusKey] + 1
    }

    return $statusCounts
}

function Get-PreferredTaskSelection {
    param([Parameter(Mandatory = $true)]$Tasks)

    if (@($Tasks).Count -eq 0) {
        return @()
    }

    $preferred = @($Tasks | Where-Object {
            $status = if ($_.PSObject.Properties['status']) { ([string]$_.status).ToLowerInvariant() } else { '' }
            $status -in @('in_progress', 'open', 'planned', 'todo')
        } | Sort-Object updated_at, created_at -Descending | Select-Object -First 1)
    if (@($preferred).Count -gt 0) {
        return $preferred
    }

    return @($Tasks | Sort-Object updated_at, created_at -Descending | Select-Object -First 1)
}

function Get-TodPriorityWeight {
    param([AllowEmptyString()][string]$Priority)

    switch (([string]$Priority).ToLowerInvariant()) {
        'critical' { return 4 }
        'high' { return 3 }
        'medium' { return 2 }
        'low' { return 1 }
        default { return 0 }
    }
}

function Test-TodTaskReadyStatus {
    param($Task)

    if ($null -eq $Task) {
        return $false
    }

    $status = if ($Task.PSObject.Properties['status']) { ([string]$Task.status).ToLowerInvariant() } else { '' }
    return @('open', 'planned', 'todo', 'packaged', 'in_progress') -contains $status
}

function Read-TodJsonFileIfExists {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -Path $Path)) {
        return $null
    }

    try {
        return (Get-Content -Path $Path -Raw -ErrorAction Stop | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Test-TodExecutionSummaryLooksWrapperOnly {
    param([AllowEmptyString()][string]$Summary)

    $text = ([string]$Summary).Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $false
    }

    return ($text -match 'accepted package and prepared normalized result from prompt path')
}

function Test-TodExecutionHasMeaningfulEvidence {
    param($ExecutionPayload)

    if ($null -eq $ExecutionPayload) {
        return $false
    }

    $executionEvidence = if ($ExecutionPayload.PSObject.Properties['execution_evidence'] -and $ExecutionPayload.execution_evidence) {
        $ExecutionPayload.execution_evidence
    }
    else {
        $null
    }

    $meaningfulEvidence = if ($executionEvidence -and $executionEvidence.PSObject.Properties['meaningful_evidence']) {
        @($executionEvidence.meaningful_evidence | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
    else {
        @()
    }

    if (@($meaningfulEvidence).Count -gt 0) {
        return $true
    }

    $filesChanged = @()
    if ($ExecutionPayload.PSObject.Properties['files_changed']) {
        $filesChanged = @($ExecutionPayload.files_changed | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
    elseif ($executionEvidence -and $executionEvidence.PSObject.Properties['files_changed']) {
        $filesChanged = @($executionEvidence.files_changed | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    if (@($filesChanged).Count -gt 0) {
        return $true
    }

    $matchedFiles = if ($executionEvidence -and $executionEvidence.PSObject.Properties['matched_files']) {
        @($executionEvidence.matched_files | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
    else {
        @()
    }
    if (@($matchedFiles).Count -gt 0) {
        return $true
    }

    $commandOutput = ''
    if ($ExecutionPayload.PSObject.Properties['command_output']) {
        $commandOutput = [string]$ExecutionPayload.command_output
    }
    elseif ($executionEvidence -and $executionEvidence.PSObject.Properties['command_output']) {
        $commandOutput = [string]$executionEvidence.command_output
    }

    if (-not [string]::IsNullOrWhiteSpace($commandOutput) -and -not (Test-TodExecutionSummaryLooksWrapperOnly -Summary $commandOutput)) {
        return $true
    }

    $summary = if ($ExecutionPayload.PSObject.Properties['summary']) { [string]$ExecutionPayload.summary } else { '' }
    return (-not [string]::IsNullOrWhiteSpace($summary) -and -not (Test-TodExecutionSummaryLooksWrapperOnly -Summary $summary) -and ($summary -match '\b(updated|patched|modified|applied|created|saved|published|migrated|synchronized|deleted|inserted|changed)\b'))
}

function Get-TodExistingFollowOnTask {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][string]$SourceTaskId
    )

    return @($State.tasks | Where-Object {
            $_.PSObject.Properties['selection_source_task_id'] -and
            [string]$_.selection_source_task_id -eq [string]$SourceTaskId
        })
}

function Resolve-TodObjectiveIdFromState {
    param(
        [Parameter(Mandatory = $true)]$State,
        [AllowEmptyString()][string]$ObjectiveId
    )

    if ([string]::IsNullOrWhiteSpace($ObjectiveId)) {
        return ''
    }

    $direct = @($State.objectives | Where-Object { [string]$_.id -eq [string]$ObjectiveId } | Select-Object -First 1)
    if (@($direct).Count -gt 0) {
        return [string]$direct[0].id
    }

    $normalizedObjectiveId = Get-NormalizedObjectiveToken -ObjectiveId $ObjectiveId
    $normalized = @($State.objectives | Where-Object {
            (Get-NormalizedObjectiveToken -ObjectiveId ([string]$_.id)) -eq $normalizedObjectiveId
        } | Select-Object -First 1)
    if (@($normalized).Count -gt 0) {
        return [string]$normalized[0].id
    }

    return [string]$ObjectiveId
}

function Get-TodReadyObjectiveCandidates {
    param(
        [Parameter(Mandatory = $true)]$State,
        [string]$ExcludeObjectiveId = '',
        [string]$ExcludeTaskId = ''
    )

    $candidates = @()
    foreach ($objective in @($State.objectives)) {
        if ($null -eq $objective -or -not $objective.PSObject.Properties['id']) {
            continue
        }

        $objectiveId = [string]$objective.id
        if (-not [string]::IsNullOrWhiteSpace($ExcludeObjectiveId) -and [string]::Equals($objectiveId, $ExcludeObjectiveId, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $objectiveStatus = if ($objective.PSObject.Properties['status']) { ([string]$objective.status).ToLowerInvariant() } else { '' }
        if (@('completed', 'closed', 'done', 'cancelled') -contains $objectiveStatus) {
            continue
        }

        $tasks = @($State.tasks | Where-Object {
                [string]$_.objective_id -eq $objectiveId -and
                (Test-TodTaskReadyStatus -Task $_) -and
                ([string]$_.id -ne [string]$ExcludeTaskId)
            })
        $preferredTask = @(Get-PreferredTaskSelection -Tasks $tasks)
        if (@($preferredTask).Count -eq 0) {
            continue
        }

        $selectedTask = $preferredTask[0]
        $candidates += [pscustomobject]@{
            objective = $objective
            task = $selectedTask
            priority_weight = Get-TodPriorityWeight -Priority $(if ($objective.PSObject.Properties['priority']) { [string]$objective.priority } else { '' })
            objective_updated_at = if ($objective.PSObject.Properties['updated_at']) { [string]$objective.updated_at } else { '' }
            task_updated_at = if ($selectedTask.PSObject.Properties['updated_at']) { [string]$selectedTask.updated_at } else { '' }
        }
    }

    return @($candidates | Sort-Object -Property @{ Expression = { [int]$_.priority_weight }; Descending = $true }, @{ Expression = { [string]$_.task_updated_at }; Descending = $true }, @{ Expression = { [string]$_.objective_updated_at }; Descending = $true })
}

function Get-TodTerminalTaskOutcome {
    param(
        [Parameter(Mandatory = $true)]$State,
        [AllowNull()]$ActiveTaskArtifact,
        [AllowNull()]$ExecutionResultArtifact,
        [AllowNull()]$ExecutionTruthArtifact,
        [string]$TaskId = ''
    )

    $recentTruth = if ($ExecutionTruthArtifact -and $ExecutionTruthArtifact.PSObject.Properties['recent_execution_truth']) {
        @($ExecutionTruthArtifact.recent_execution_truth | Select-Object -First 1)
    }
    else {
        @()
    }
    $recentTruth = if (@($recentTruth).Count -gt 0) { $recentTruth[0] } else { $null }

    $resolvedTaskId = if (-not [string]::IsNullOrWhiteSpace($TaskId)) { [string]$TaskId } elseif ($ExecutionResultArtifact -and $ExecutionResultArtifact.PSObject.Properties['task_id']) { [string]$ExecutionResultArtifact.task_id } elseif ($ActiveTaskArtifact -and $ActiveTaskArtifact.PSObject.Properties['task_id']) { [string]$ActiveTaskArtifact.task_id } elseif ($recentTruth -and $recentTruth.PSObject.Properties['task_id']) { [string]$recentTruth.task_id } else { '' }
    $resolvedObjectiveId = if ($ExecutionResultArtifact -and $ExecutionResultArtifact.PSObject.Properties['objective_id']) { [string]$ExecutionResultArtifact.objective_id } elseif ($ActiveTaskArtifact -and $ActiveTaskArtifact.PSObject.Properties['objective_id']) { [string]$ActiveTaskArtifact.objective_id } elseif ($recentTruth -and $recentTruth.PSObject.Properties['objective_id']) { [string]$recentTruth.objective_id } else { '' }
    $summary = if ($ExecutionResultArtifact -and $ExecutionResultArtifact.PSObject.Properties['summary']) { [string]$ExecutionResultArtifact.summary } elseif ($ActiveTaskArtifact -and $ActiveTaskArtifact.PSObject.Properties['summary']) { [string]$ActiveTaskArtifact.summary } elseif ($recentTruth -and $recentTruth.PSObject.Properties['summary']) { [string]$recentTruth.summary } else { '' }
    $status = if ($ExecutionResultArtifact -and $ExecutionResultArtifact.PSObject.Properties['status']) { ([string]$ExecutionResultArtifact.status).ToLowerInvariant() } elseif ($ActiveTaskArtifact -and $ActiveTaskArtifact.PSObject.Properties['status']) { ([string]$ActiveTaskArtifact.status).ToLowerInvariant() } elseif ($recentTruth -and $recentTruth.PSObject.Properties['status']) { ([string]$recentTruth.status).ToLowerInvariant() } else { '' }
    $executionState = if ($ExecutionResultArtifact -and $ExecutionResultArtifact.PSObject.Properties['execution_state']) { ([string]$ExecutionResultArtifact.execution_state).ToLowerInvariant() } elseif ($ActiveTaskArtifact -and $ActiveTaskArtifact.PSObject.Properties['execution_state']) { ([string]$ActiveTaskArtifact.execution_state).ToLowerInvariant() } elseif ($recentTruth -and $recentTruth.PSObject.Properties['execution_state']) { ([string]$recentTruth.execution_state).ToLowerInvariant() } else { '' }
    $reasonCode = if ($ExecutionResultArtifact -and $ExecutionResultArtifact.PSObject.Properties['reason_code']) { ([string]$ExecutionResultArtifact.reason_code).ToLowerInvariant() } elseif ($ActiveTaskArtifact -and $ActiveTaskArtifact.PSObject.Properties['reason_code']) { ([string]$ActiveTaskArtifact.reason_code).ToLowerInvariant() } elseif ($recentTruth -and $recentTruth.PSObject.Properties['reason_code']) { ([string]$recentTruth.reason_code).ToLowerInvariant() } else { '' }
    $recoveryState = if ($ExecutionResultArtifact -and $ExecutionResultArtifact.PSObject.Properties['recovery_state']) { ([string]$ExecutionResultArtifact.recovery_state).ToLowerInvariant() } elseif ($ActiveTaskArtifact -and $ActiveTaskArtifact.PSObject.Properties['recovery_state']) { ([string]$ActiveTaskArtifact.recovery_state).ToLowerInvariant() } elseif ($recentTruth -and $recentTruth.PSObject.Properties['recovery_state']) { ([string]$recentTruth.recovery_state).ToLowerInvariant() } else { '' }

    $meaningfulEvidence = Test-TodExecutionHasMeaningfulEvidence -ExecutionPayload $(if ($ExecutionResultArtifact) { $ExecutionResultArtifact } elseif ($ActiveTaskArtifact) { $ActiveTaskArtifact } else { $recentTruth })
    $latestReview = @($State.review_decisions | Where-Object { [string]$_.task_id -eq $resolvedTaskId } | Sort-Object created_at -Descending | Select-Object -First 1)
    $latestReview = if (@($latestReview).Count -gt 0) { $latestReview[0] } else { $null }
    $reviewDecision = if ($latestReview -and $latestReview.PSObject.Properties['decision']) { ([string]$latestReview.decision).ToLowerInvariant() } else { '' }

    $classification = 'unknown'
    if ($reasonCode -eq 'no_meaningful_execution_evidence' -or $executionState -eq 'no_op_rejected') {
        $classification = 'no_op_rejected'
    }
    elseif ($recoveryState -eq 'replay_or_replan_required') {
        $classification = 'replay_required'
    }
    elseif ($status -eq 'completed' -and $meaningfulEvidence) {
        $classification = 'completed_with_evidence'
    }
    elseif ($status -eq 'completed' -and -not $meaningfulEvidence) {
        $classification = 'replay_required'
    }
    elseif (($status -eq 'blocked' -or $executionState -eq 'blocked') -and $reviewDecision -eq 'escalate') {
        $classification = 'failed_blocked'
    }
    elseif ($status -eq 'blocked' -or $executionState -eq 'blocked') {
        $classification = 'failed_recoverable'
    }
    elseif ($status -eq 'waiting' -or $executionState -eq 'waiting') {
        $classification = 'stale_waiting'
    }

    return [pscustomobject]@{
        classification = $classification
        task_id = $resolvedTaskId
        objective_id = $resolvedObjectiveId
        summary = $summary
        status = $status
        execution_state = $executionState
        reason_code = $reasonCode
        recovery_state = $recoveryState
        review_decision = $reviewDecision
        meaningful_evidence = $meaningfulEvidence
        wrapper_only = (Test-TodExecutionSummaryLooksWrapperOnly -Summary $summary)
    }
}

function New-TodNextTaskSelectionPlan {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)]$TerminalOutcome,
        [bool]$StaleDetected = $false,
        [string]$StaleReason = ''
    )

    $rejectedCandidates = New-Object System.Collections.Generic.List[object]
    $expectedEvidence = New-Object System.Collections.Generic.List[string]
    $validationPlan = New-Object System.Collections.Generic.List[string]
    $selectedTask = $null
    $selectionKind = 'none'
    $reasonSelected = ''
    $createTaskSpec = $null
    $dispatchStatus = 'not_started'
    $sourceTask = if ($TerminalOutcome.PSObject.Properties['task_id']) {
        @($State.tasks | Where-Object { [string]$_.id -eq [string]$TerminalOutcome.task_id } | Select-Object -First 1)
    }
    else {
        @()
    }
    $sourceTask = if (@($sourceTask).Count -gt 0) { $sourceTask[0] } else { $null }
    $currentObjectiveId = Resolve-TodObjectiveIdFromState -State $State -ObjectiveId $(if ($sourceTask -and $sourceTask.PSObject.Properties['objective_id']) { [string]$sourceTask.objective_id } elseif ($TerminalOutcome.PSObject.Properties['objective_id']) { [string]$TerminalOutcome.objective_id } else { '' })
    $currentTaskId = if ($TerminalOutcome.PSObject.Properties['task_id']) { [string]$TerminalOutcome.task_id } else { '' }

    if (@('no_op_rejected', 'replay_required') -contains [string]$TerminalOutcome.classification) {
        $linkedFollowOn = @(Get-TodExistingFollowOnTask -State $State -SourceTaskId $currentTaskId)
        $readyFollowOn = @($linkedFollowOn | Where-Object { Test-TodTaskReadyStatus -Task $_ } | Sort-Object updated_at, created_at -Descending | Select-Object -First 1)
        if (@($readyFollowOn).Count -gt 0) {
            $selectedTask = $readyFollowOn[0]
            $selectionKind = 'same_task_replan_existing'
            $reasonSelected = 'Last terminal task ended without meaningful evidence, so TOD reused the existing same-objective replay/replan task.'
        }
        elseif (@($linkedFollowOn).Count -lt 2 -and -not [string]::IsNullOrWhiteSpace($currentObjectiveId) -and -not [string]::IsNullOrWhiteSpace($currentTaskId)) {
            $sourceTitle = if ($sourceTask -and $sourceTask.PSObject.Properties['title']) { [string]$sourceTask.title } else { $currentTaskId }
            $sourceScope = if ($sourceTask -and $sourceTask.PSObject.Properties['scope']) { [string]$sourceTask.scope } else { 'Re-execute the bounded task with state-changing evidence.' }
            $createTaskSpec = [pscustomobject]@{
                objective_mode = 'existing'
                objective_id = $currentObjectiveId
                title = ('Replan with evidence: ' + $sourceTitle)
                type = 'implementation'
                task_category = 'code_change'
                assigned_executor = (Resolve-PreferredAssignedExecutor -TaskCategory 'code_change' -State $State -Task ([pscustomobject]@{ title = ('Replan with evidence: ' + $sourceTitle); scope = ('Previous execution for {0} produced no meaningful evidence. Replan the bounded step so TOD performs a state-changing or artifact-producing action. Original scope: {1}' -f $currentTaskId, $sourceScope) }))
                scope = ('Previous execution for {0} produced no meaningful evidence. Replan the bounded step so TOD performs a state-changing or artifact-producing action. Original scope: {1}' -f $currentTaskId, $sourceScope)
                acceptance_criteria = 'Produce meaningful evidence through changed files or accepted result artifacts and rerun focused validation before completion'
                selection_source_task_id = $currentTaskId
            }
            $selectionKind = 'same_task_replan_new'
            $reasonSelected = 'Last terminal task ended without meaningful evidence, so TOD created a same-objective replay/replan task with an explicit evidence requirement.'
        }
        else {
            $rejectedCandidates.Add([pscustomobject]@{
                    task_id = $currentTaskId
                    reason = 'same_task_replay_budget_exhausted'
                }) | Out-Null
        }
        $expectedEvidence.Add('meaningful_execution_evidence') | Out-Null
        $expectedEvidence.Add('state_change_or_result_artifact') | Out-Null
        $validationPlan.Add('rerun the bounded task and reject completion unless concrete evidence is published') | Out-Null
    }

    if ($null -eq $selectedTask -and $null -eq $createTaskSpec -and [string]$TerminalOutcome.classification -eq 'completed_with_evidence') {
        $sameObjectiveTasks = @($State.tasks | Where-Object {
                [string]$_.objective_id -eq $currentObjectiveId -and
                [string]$_.id -ne $currentTaskId -and
                (Test-TodTaskReadyStatus -Task $_)
            })
        $preferredSameObjective = @(Get-PreferredTaskSelection -Tasks $sameObjectiveTasks)
        if (@($preferredSameObjective).Count -gt 0) {
            $selectedTask = $preferredSameObjective[0]
            $selectionKind = 'same_objective_next_task'
            $reasonSelected = 'The previous task completed with evidence, so TOD selected the next ready task from the same objective.'
            $expectedEvidence.Add('objective_progress_evidence') | Out-Null
            $validationPlan.Add('run the next ready task under the same objective and validate bounded progress') | Out-Null
        }
    }

    if ($null -eq $selectedTask -and $null -eq $createTaskSpec) {
        $backlogCandidates = @(Get-TodReadyObjectiveCandidates -State $State -ExcludeObjectiveId $currentObjectiveId -ExcludeTaskId $currentTaskId)
        if (@($backlogCandidates).Count -gt 0) {
            $selectedTask = $backlogCandidates[0].task
            $selectionKind = 'backlog_ready_objective'
            $reasonSelected = 'No ready same-objective task was available, so TOD selected the highest-priority ready task from the backlog.'
            $expectedEvidence.Add('bounded_execution_evidence') | Out-Null
            $validationPlan.Add('dispatch the selected backlog task and confirm fresh execution evidence updates the shared truth') | Out-Null
        }
    }

    if ($null -eq $selectedTask -and $null -eq $createTaskSpec) {
        $selectionKind = if ($StaleDetected) { 'stale_diagnostic' } else { 'maintenance_training' }
        $reasonSelected = if ($StaleDetected) { 'TOD is stale and no ready task exists, so TOD created a bounded diagnostic task that must publish concrete evidence.' } else { 'No ready task exists, so TOD created a bounded maintenance/training task from the current system weakness.' }
        $createTaskSpec = [pscustomobject]@{
            objective_mode = 'new'
            objective_title = if ($StaleDetected) { 'TOD self-driving recovery: stale selection diagnostics' } else { 'TOD self-driving recovery: maintenance continuation' }
            objective_description = if ($StaleDetected) { 'TOD detected stale autonomous progress and needs a bounded diagnostic loop that produces concrete evidence instead of another summary-only completion.' } else { 'TOD needs a bounded maintenance/training task that preserves autonomous forward progress when no ready objective task exists.' }
            objective_priority = 'high'
            objective_success_criteria = 'A bounded diagnostic or maintenance task is dispatched and publishes concrete evidence'
            title = if ($StaleDetected) { 'Capture evidence for stale self-driving task selection gap' } else { 'Run bounded maintenance to strengthen autonomous task continuation' }
            type = 'implementation'
            task_category = 'initiative_training'
            assigned_executor = (Resolve-PreferredAssignedExecutor -TaskCategory 'initiative_training' -State $State -Task ([pscustomobject]@{ title = if ($StaleDetected) { 'Capture evidence for stale self-driving task selection gap' } else { 'Run bounded maintenance to strengthen autonomous task continuation' }; scope = if ($StaleDetected) { ('Inspect the current stale condition and publish concrete evidence for why TOD stopped selecting valid work automatically. Reason: {0}' -f $(if ([string]::IsNullOrWhiteSpace($StaleReason)) { 'stale progress detected' } else { $StaleReason })) } else { 'Run a bounded maintenance/training slice that improves TOD autonomous continuation and publishes concrete evidence.' } }))
            scope = if ($StaleDetected) { ('Inspect the current stale condition and publish concrete evidence for why TOD stopped selecting valid work automatically. Reason: {0}' -f $(if ([string]::IsNullOrWhiteSpace($StaleReason)) { 'stale progress detected' } else { $StaleReason })) } else { 'Run a bounded maintenance/training slice that improves TOD autonomous continuation and publishes concrete evidence.' }
            acceptance_criteria = 'Publish a concrete artifact or changed file that explains the weakness and validates the maintenance response'
            selection_source_task_id = $currentTaskId
        }
        $expectedEvidence.Add('diagnostic_artifact_or_changed_file') | Out-Null
        $validationPlan.Add('publish concrete stale-diagnostic evidence instead of a summary-only result') | Out-Null
    }

    if ([string]$TerminalOutcome.classification -eq 'failed_blocked' -and $selectionKind -like 'same_task_replan*') {
        $rejectedCandidates.Add([pscustomobject]@{
                task_id = $currentTaskId
                reason = 'blocked_task_was_not_requeued'
            }) | Out-Null
        $selectedTask = $null
        $createTaskSpec = $null
        $selectionKind = 'blocked'
        $reasonSelected = 'The last task is blocked, and TOD refused to loop the same task indefinitely without a new bounded path.'
        $dispatchStatus = 'blocked_with_reason'
    }

    return [pscustomobject]@{
        selection_kind = $selectionKind
        selected_task_id = if ($selectedTask) { [string]$selectedTask.id } else { '' }
        source_objective = $currentObjectiveId
        reason_selected = $reasonSelected
        rejected_candidates = @($rejectedCandidates.ToArray())
        dispatch_status = $dispatchStatus
        expected_evidence = @($expectedEvidence.ToArray())
        validation_plan = @($validationPlan.ToArray())
        create_task = $createTaskSpec
    }
}

function Resolve-TodSelectionActionEntity {
    param($Payload)

    if ($null -eq $Payload) {
        return $null
    }

    if ($Payload.PSObject.Properties['local'] -and $null -ne $Payload.local) {
        return $Payload.local
    }

    return $Payload
}

function Resolve-TodNextTaskSelectionTask {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)]$Plan,
        [Parameter(Mandatory = $true)][string]$ResolvedConfigPath,
        [Parameter(Mandatory = $true)][string]$ResolvedStatePath
    )

    if (-not [string]::IsNullOrWhiteSpace([string]$Plan.selected_task_id)) {
        $existingTask = @(Get-TaskFromState -State $State -TaskId ([string]$Plan.selected_task_id))
        if (@($existingTask).Count -gt 0) {
            return $existingTask[0]
        }
    }

    if (-not $Plan.create_task) {
        return $null
    }

    $createSpec = $Plan.create_task
    $objectiveId = ''
    if ([string]$createSpec.objective_mode -eq 'new') {
        $newObjectiveAction = Invoke-TodSelfJsonAction -ActionName 'new-objective' -Arguments @{
            Title = [string]$createSpec.objective_title
            Description = [string]$createSpec.objective_description
            Priority = [string]$createSpec.objective_priority
            SuccessCriteria = [string]$createSpec.objective_success_criteria
            ConfigPath = $ResolvedConfigPath
            StatePath = $ResolvedStatePath
        }
        $newObjective = Resolve-TodSelectionActionEntity -Payload $newObjectiveAction.payload
        $objectiveId = if ($newObjective -and $newObjective.PSObject.Properties['id']) { [string]$newObjective.id } else { '' }
    }
    else {
        $objectiveId = [string]$createSpec.objective_id
    }

    if ([string]::IsNullOrWhiteSpace($objectiveId)) {
        throw 'Unable to resolve objective ID for next-task selection.'
    }

    $newTaskAction = Invoke-TodSelfJsonAction -ActionName 'add-task' -Arguments @{
        ObjectiveId = $objectiveId
        Title = [string]$createSpec.title
        Type = [string]$createSpec.type
        Scope = [string]$createSpec.scope
        AcceptanceCriteria = [string]$createSpec.acceptance_criteria
        AssignedExecutor = [string]$createSpec.assigned_executor
        TaskCategory = [string]$createSpec.task_category
        ConfigPath = $ResolvedConfigPath
        StatePath = $ResolvedStatePath
    }
    $createdTaskEntity = Resolve-TodSelectionActionEntity -Payload $newTaskAction.payload
    $createdTaskId = if ($createdTaskEntity -and $createdTaskEntity.PSObject.Properties['id']) { [string]$createdTaskEntity.id } else { '' }
    if ([string]::IsNullOrWhiteSpace($createdTaskId)) {
        throw 'Unable to resolve task ID for next-task selection.'
    }

    $stateAfterCreate = Load-State
    $createdTask = @($stateAfterCreate.tasks | Where-Object { [string]$_.id -eq $createdTaskId } | Select-Object -First 1)
    if (@($createdTask).Count -eq 0) {
        throw "Unable to locate created task '$createdTaskId' after next-task selection."
    }

    $createdTask[0] | Add-Member -NotePropertyName selection_source_task_id -NotePropertyValue ([string]$createSpec.selection_source_task_id) -Force
    $createdTask[0] | Add-Member -NotePropertyName selection_generated_at -NotePropertyValue (Get-UtcNow) -Force
    Save-State -State $stateAfterCreate
    return $createdTask[0]
}

function Publish-TodNextTaskSelectionArtifacts {
    param(
        [Parameter(Mandatory = $true)]$SelectionPayload,
        [AllowNull()]$SelectedTask,
        [Parameter(Mandatory = $true)][string]$RequestId
    )

    $generatedAt = Get-UtcNow
    $objectiveId = if ($SelectedTask -and $SelectedTask.PSObject.Properties['objective_id']) { [string]$SelectedTask.objective_id } else { [string]$SelectionPayload.source_objective }
    $normalizedObjectiveId = Get-NormalizedObjectiveToken -ObjectiveId $objectiveId
    $taskId = if ($SelectedTask -and $SelectedTask.PSObject.Properties['id']) { [string]$SelectedTask.id } else { '' }
    $taskTitle = if ($SelectedTask -and $SelectedTask.PSObject.Properties['title']) { [string]$SelectedTask.title } else { 'No task selected' }
    $taskScope = if ($SelectedTask -and $SelectedTask.PSObject.Properties['scope']) { [string]$SelectedTask.scope } else { '' }

    $activityPayload = [ordered]@{
        generated_at = $generatedAt
        updated_at = $generatedAt
        source = 'tod.next-task-selection'
        surface = 'tod-next-task-selection'
        session_key = 'tod-self-driving-selection'
        request_id = $RequestId
        task_id = $taskId
        objective_id = $objectiveId
        normalized_objective_id = $normalizedObjectiveId
        title = $taskTitle
        summary = [string]$SelectionPayload.reason_selected
        packet_type = 'tod-activity-stream-v1'
        event = 'next_task_selected'
        status = 'active'
        phase = 'selection_loop'
        execution_state = 'selected_for_dispatch'
        current_action = 'Selected the next bounded task for autonomous dispatch.'
        next_step = 'Dispatch the selected task through run-task and require meaningful evidence before completion.'
        next_validation = (@($SelectionPayload.validation_plan) -join '; ')
        execution_evidence = [ordered]@{
            selection_kind = [string]$SelectionPayload.selection_kind
            reason_selected = [string]$SelectionPayload.reason_selected
            expected_evidence = @($SelectionPayload.expected_evidence)
            validation_plan = @($SelectionPayload.validation_plan)
        }
        recovery_state = 'not_needed'
    }

    $activeTaskPayload = [ordered]@{
        generated_at = $generatedAt
        updated_at = $generatedAt
        source = 'tod.next-task-selection'
        surface = 'tod-next-task-selection'
        session_key = 'tod-self-driving-selection'
        request_id = $RequestId
        task_id = $taskId
        objective_id = $objectiveId
        normalized_objective_id = $normalizedObjectiveId
        title = $taskTitle
        task_focus = $taskScope
        summary = [string]$SelectionPayload.reason_selected
        packet_type = 'tod-active-task-v1'
        status = 'active'
        execution_state = 'selected_for_dispatch'
        current_action = 'Selected the next bounded task for autonomous dispatch.'
        next_step = 'Run the selected task and require meaningful evidence before completion.'
        next_validation = (@($SelectionPayload.validation_plan) -join '; ')
        wait_target = ''
        wait_target_label = ''
        wait_reason = ''
        execution_evidence = [ordered]@{
            selection_kind = [string]$SelectionPayload.selection_kind
            reason_selected = [string]$SelectionPayload.reason_selected
            expected_evidence = @($SelectionPayload.expected_evidence)
            validation_plan = @($SelectionPayload.validation_plan)
        }
        recovery_state = 'not_needed'
    }

    $writtenArtifactPaths = @()
    foreach ($sharedRoot in @(Get-TodExecutionSharedRoots)) {
        $selectionWrite = Write-TodExecutionSharedJson -Path (Join-Path $sharedRoot 'TOD_NEXT_TASK_SELECTION.latest.json') -Payload $SelectionPayload
        $activeTaskWrite = Write-TodExecutionSharedJson -Path (Join-Path $sharedRoot 'TOD_ACTIVE_TASK.latest.json') -Payload $activeTaskPayload
        $activityWrite = Write-TodExecutionSharedJson -Path (Join-Path $sharedRoot 'TOD_ACTIVITY_STREAM.latest.json') -Payload $activityPayload
        foreach ($writeResult in @($selectionWrite, $activeTaskWrite, $activityWrite)) {
            if ($writeResult -and $writeResult.PSObject.Properties['written'] -and [bool]$writeResult.written) {
                $writtenArtifactPaths += [string]$writeResult.path
            }
        }
    }

    $runtimeSharedRoot = [System.IO.Path]::GetFullPath((Join-Path $repoRoot 'runtime/shared'))
    $remotePublishPaths = @($writtenArtifactPaths | Where-Object {
        $fullPath = [System.IO.Path]::GetFullPath([string]$_)
        $fullPath.StartsWith($runtimeSharedRoot, [System.StringComparison]::OrdinalIgnoreCase)
    } | Select-Object -Unique)
    if ($remotePublishPaths.Length -gt 0) {
        Publish-RemoteTodExecutionArtifacts -LocalArtifactPaths $remotePublishPaths | Out-Null
    }

    $activityArtifactPath = @($writtenArtifactPaths | Where-Object { [System.IO.Path]::GetFileName([string]$_) -eq 'TOD_ACTIVITY_STREAM.latest.json' } | Select-Object -First 1)
    $activityArtifact = if (@($activityArtifactPath).Count -gt 0) { Read-TodExecutionJsonIfExists -Path ([string]$activityArtifactPath[0]) } else { $activityPayload }

    return [pscustomobject]@{
        selection = $SelectionPayload
        active_task = $activeTaskPayload
        activity = $activityArtifact
        artifact_paths = @($writtenArtifactPaths)
    }
}

function Invoke-TodNextTaskSelectionLoop {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][string]$ResolvedConfigPath,
        [Parameter(Mandatory = $true)][string]$ResolvedStatePath,
        [string]$SourceTaskId = '',
        [string]$TriggerReason = ''
    )

    $activeTaskArtifact = Read-TodJsonFileIfExists -Path (Join-Path $repoRoot 'runtime/shared/TOD_ACTIVE_TASK.latest.json')
    $executionResultArtifact = Read-TodJsonFileIfExists -Path (Join-Path $repoRoot 'runtime/shared/TOD_EXECUTION_RESULT.latest.json')
    $executionTruthArtifact = Read-TodJsonFileIfExists -Path (Join-Path $repoRoot 'runtime/shared/TOD_EXECUTION_TRUTH.latest.json')
    $integrationStatus = Read-TodJsonFileIfExists -Path (Join-Path $repoRoot 'shared_state/integration_status.json')
    $autonomyStatus = Read-TodJsonFileIfExists -Path (Join-Path $repoRoot 'shared_state/tod_autonomy_status.latest.json')

    $terminalOutcome = Get-TodTerminalTaskOutcome -State $State -ActiveTaskArtifact $activeTaskArtifact -ExecutionResultArtifact $executionResultArtifact -ExecutionTruthArtifact $executionTruthArtifact -TaskId $SourceTaskId
    $staleDetected = $false
    $staleReason = ''
    if ($autonomyStatus -and $autonomyStatus.PSObject.Properties['blockers'] -and @($autonomyStatus.blockers).Count -gt 0) {
        $staleReason = (@($autonomyStatus.blockers) -join '; ')
    }
    if ($terminalOutcome.classification -eq 'stale_waiting') {
        $staleDetected = $true
    }
    if ($integrationStatus -and $integrationStatus.PSObject.Properties['mim_status'] -and $integrationStatus.mim_status -and $integrationStatus.mim_status.PSObject.Properties['is_stale'] -and [bool]$integrationStatus.mim_status.is_stale) {
        $staleDetected = $true
    }

    $plan = New-TodNextTaskSelectionPlan -State $State -TerminalOutcome $terminalOutcome -StaleDetected:$staleDetected -StaleReason $staleReason
    $selectedTask = Resolve-TodNextTaskSelectionTask -State $State -Plan $plan -ResolvedConfigPath $ResolvedConfigPath -ResolvedStatePath $ResolvedStatePath

    $requestId = ('tod-next-task-selection-{0}-{1}' -f $(if ($selectedTask) { [string]$selectedTask.id } else { 'none' }), (Get-Date).ToUniversalTime().ToString('yyyyMMddHHmmssfff'))
    $selectionPayload = [ordered]@{
        generated_at = Get-UtcNow
        source = 'tod-next-task-selection-v1'
        trigger_reason = $(if (-not [string]::IsNullOrWhiteSpace($TriggerReason)) { [string]$TriggerReason } else { 'automatic_terminal_outcome' })
        last_terminal_outcome = $terminalOutcome
        selected_task_id = if ($selectedTask) { [string]$selectedTask.id } else { '' }
        source_objective = if ($selectedTask) { [string]$selectedTask.objective_id } else { [string]$plan.source_objective }
        reason_selected = [string]$plan.reason_selected
        rejected_candidates = @($plan.rejected_candidates)
        dispatch_status = if ($selectedTask) { 'dispatching' } else { 'blocked_with_reason' }
        expected_evidence = @($plan.expected_evidence)
        validation_plan = @($plan.validation_plan)
        next_check_time = (Get-Date).ToUniversalTime().AddMinutes(5).ToString('o')
        selection_kind = [string]$plan.selection_kind
        request_id = $requestId
        selected_task_title = if ($selectedTask -and $selectedTask.PSObject.Properties['title']) { [string]$selectedTask.title } else { '' }
        selected_task_scope = if ($selectedTask -and $selectedTask.PSObject.Properties['scope']) { [string]$selectedTask.scope } else { '' }
    }

    $null = Publish-TodNextTaskSelectionArtifacts -SelectionPayload $selectionPayload -SelectedTask $selectedTask -RequestId $requestId

    $dispatch = $null
    if ($selectedTask) {
        if (-not [string]::Equals(([string]$selectedTask.status), 'packaged', [System.StringComparison]::OrdinalIgnoreCase)) {
            $null = Invoke-TodSelfAction -ActionName 'package-task' -Arguments @{
                TaskId = [string]$selectedTask.id
                ConfigPath = $ResolvedConfigPath
                StatePath = $ResolvedStatePath
            }
            $stateAfterPackaging = Load-State
            $selectedTask = @($stateAfterPackaging.tasks | Where-Object { [string]$_.id -eq [string]$selectedTask.id } | Select-Object -First 1)
            $selectedTask = if (@($selectedTask).Count -gt 0) { $selectedTask[0] } else { $selectedTask }
        }

        $dispatchAction = Invoke-TodSelfJsonAction -ActionName 'run-task' -Arguments @{
            TaskId = [string]$selectedTask.id
            ObjectiveId = [string]$selectedTask.objective_id
            ConfigPath = $ResolvedConfigPath
            StatePath = $ResolvedStatePath
            SkipNextTaskSelectionLoop = $true
        }
        $dispatch = $dispatchAction.payload
        $selectionPayload.dispatch_status = if ($dispatch -and $dispatch.PSObject.Properties['blocked'] -and [bool]$dispatch.blocked) { 'blocked_with_reason' } elseif ($dispatch -and $dispatch.PSObject.Properties['decision'] -and [string]$dispatch.decision -eq 'revise') { 'blocked_with_reason' } elseif ($dispatch -and $dispatch.PSObject.Properties['decision'] -and [string]$dispatch.decision -eq 'pass') { 'completed' } else { 'dispatched' }
        $selectionPayload.dispatch_result = $dispatch
        $null = Publish-TodNextTaskSelectionArtifacts -SelectionPayload $selectionPayload -SelectedTask $selectedTask -RequestId $requestId
    }

    return [pscustomobject]$selectionPayload
}

function Resolve-TaskPackagePath {
    param(
        [Parameter(Mandatory = $true)][string]$TaskId,
        [string]$ExplicitPath
    )

    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        Assert-Exists -Path $ExplicitPath -Name "Task package"
        return $ExplicitPath
    }

    $v2Path = Join-Path $repoRoot ("tod/out/prompts-v2/{0}.md" -f $TaskId)
    if (Test-Path -Path $v2Path) { return $v2Path }

    $v1Path = Join-Path $repoRoot ("tod/out/prompts/{0}.md" -f $TaskId)
    if (Test-Path -Path $v1Path) { return $v1Path }

    throw "No packaged prompt found for task '$TaskId'. Expected one of: $v2Path or $v1Path."
}

function Convert-EngineResultToNormalizedEnvelope {
    param(
        [Parameter(Mandatory = $true)]$EngineResult,
        [Parameter(Mandatory = $true)]$EngineMetadata,
        [string]$FallbackReason = ""
    )

    $engineName = [string]$EngineResult.engine_name
    if ([string]::IsNullOrWhiteSpace($engineName)) { $engineName = [string]$EngineMetadata.name }

    $status = [string]$EngineResult.status
    if ([string]::IsNullOrWhiteSpace($status)) { $status = "completed" }

    return [pscustomobject]@{
        engine = $engineName
        status = $status
        summary = [string]$EngineResult.summary
        files_changed = @($EngineResult.files_changed | ForEach-Object { [string]$_ })
        tests_run = @($EngineResult.tests_run | ForEach-Object { [string]$_ })
        test_results = @($EngineResult.test_results | ForEach-Object { [string]$_ })
        failures = @($EngineResult.failures | ForEach-Object { [string]$_ })
        recommendations = @($EngineResult.recommendations | ForEach-Object { [string]$_ })
        structured_findings = @($EngineResult.structured_findings)
        needs_escalation = [bool]$EngineResult.needs_escalation
        reason_code = if ($EngineResult.PSObject.Properties['reason_code']) { [string]$EngineResult.reason_code } else { '' }
        recovery_state = if ($EngineResult.PSObject.Properties['recovery_state']) { [string]$EngineResult.recovery_state } else { '' }
        command_output = if ($EngineResult.PSObject.Properties['command_output']) { [string]$EngineResult.command_output } else { '' }
        diff_summary = if ($EngineResult.PSObject.Properties['diff_summary']) { [string]$EngineResult.diff_summary } else { '' }
        commands_run = if ($EngineResult.PSObject.Properties['commands_run'] -and $null -ne $EngineResult.commands_run) { @($EngineResult.commands_run) } else { @() }
        validation_results = if ($EngineResult.PSObject.Properties['validation_results'] -and $null -ne $EngineResult.validation_results) { @($EngineResult.validation_results) } else { @() }
        blockers = if ($EngineResult.PSObject.Properties['blockers'] -and $null -ne $EngineResult.blockers) { @($EngineResult.blockers) } else { @() }
        confidence = if ($EngineResult.PSObject.Properties['confidence']) { [string]$EngineResult.confidence } else { '' }
        rollback_hint = if ($EngineResult.PSObject.Properties['rollback_hint']) { [string]$EngineResult.rollback_hint } else { '' }
        no_change_required = if ($EngineResult.PSObject.Properties['no_change_required'] -and $null -ne $EngineResult.no_change_required) { [bool]$EngineResult.no_change_required } else { $false }
        execution_engine = [pscustomobject]@{
            name = [string]$engineName
            version = [string]$EngineResult.engine_version
            execution_id = [string]$EngineResult.execution_id
            status = $status
            selected_at = Get-UtcNow
            fallback_reason = [string]$FallbackReason
        }
        raw_output = $EngineResult.raw_output
    }
}

function Normalize-EngineResultPayload {
    param($EngineResult)

    $summary = [string]$EngineResult.summary
    if ([string]::IsNullOrWhiteSpace($summary)) {
        $summary = "Execution completed with no summary provided by engine."
    }

    $filesChanged = @($EngineResult.files_changed | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $testsRun = @($EngineResult.tests_run | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $testResults = @($EngineResult.test_results | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $failures = @($EngineResult.failures | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $recommendations = @($EngineResult.recommendations | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    if ($testResults.Length -eq 0) {
        $testResults = @("not_run")
    }

    return [pscustomobject]@{
        summary = $summary
        files_changed = @($filesChanged)
        tests_run = @($testsRun)
        test_results = @($testResults)
        failures = @($failures)
        recommendations = @($recommendations)
        structured_findings = @($EngineResult.structured_findings)
        needs_escalation = [bool]$EngineResult.needs_escalation
        reason_code = if ($EngineResult.PSObject.Properties['reason_code']) { [string]$EngineResult.reason_code } else { '' }
        recovery_state = if ($EngineResult.PSObject.Properties['recovery_state']) { [string]$EngineResult.recovery_state } else { '' }
        command_output = if ($EngineResult.PSObject.Properties['command_output']) { [string]$EngineResult.command_output } else { '' }
        diff_summary = if ($EngineResult.PSObject.Properties['diff_summary']) { [string]$EngineResult.diff_summary } else { '' }
        commands_run = if ($EngineResult.PSObject.Properties['commands_run'] -and $null -ne $EngineResult.commands_run) { @($EngineResult.commands_run) } else { @() }
        validation_results = if ($EngineResult.PSObject.Properties['validation_results'] -and $null -ne $EngineResult.validation_results) { @($EngineResult.validation_results) } else { @() }
        blockers = if ($EngineResult.PSObject.Properties['blockers'] -and $null -ne $EngineResult.blockers) { @($EngineResult.blockers) } else { @() }
        confidence = if ($EngineResult.PSObject.Properties['confidence']) { [string]$EngineResult.confidence } else { '' }
        rollback_hint = if ($EngineResult.PSObject.Properties['rollback_hint']) { [string]$EngineResult.rollback_hint } else { '' }
        no_change_required = if ($EngineResult.PSObject.Properties['no_change_required'] -and $null -ne $EngineResult.no_change_required) { [bool]$EngineResult.no_change_required } else { $false }
    }
}

function New-ExecutionEngineBlockedResult {
    param(
        [Parameter(Mandatory = $true)]$Task,
        [Parameter(Mandatory = $true)][string]$TaskId,
        [Parameter(Mandatory = $true)][string]$PackagePath,
        [AllowNull()]$PrimaryResult,
        [AllowNull()]$FallbackResult,
        [string[]]$AttemptedEngines = @(),
        [object[]]$AttemptDetails = @(),
        [string]$FallbackEngine = ''
    )

    $engineName = if ($PrimaryResult -and $PrimaryResult.PSObject.Properties['engine_name']) { [string]$PrimaryResult.engine_name } else { 'codex' }
    $engineVersion = if ($PrimaryResult -and $PrimaryResult.PSObject.Properties['engine_version']) { [string]$PrimaryResult.engine_version } else { 'unknown' }
    $executionId = if ($PrimaryResult -and $PrimaryResult.PSObject.Properties['execution_id']) { [string]$PrimaryResult.execution_id } else { '' }
    $result = New-EngineExecutionResult -EngineName $engineName -EngineVersion $engineVersion -TaskId $TaskId
    if (-not [string]::IsNullOrWhiteSpace($executionId)) {
        $result.execution_id = $executionId
    }

    $primaryFailures = if ($PrimaryResult -and $PrimaryResult.PSObject.Properties['failures']) { @($PrimaryResult.failures | ForEach-Object { [string]$_ }) } else { @() }
    $fallbackFailures = if ($FallbackResult -and $FallbackResult.PSObject.Properties['failures']) { @($FallbackResult.failures | ForEach-Object { [string]$_ }) } else { @() }
    $primaryRecommendations = if ($PrimaryResult -and $PrimaryResult.PSObject.Properties['recommendations']) { @($PrimaryResult.recommendations | ForEach-Object { [string]$_ }) } else { @() }
    $fallbackRecommendations = if ($FallbackResult -and $FallbackResult.PSObject.Properties['recommendations']) { @($FallbackResult.recommendations | ForEach-Object { [string]$_ }) } else { @() }
    $primaryTests = if ($PrimaryResult -and $PrimaryResult.PSObject.Properties['tests_run']) { @($PrimaryResult.tests_run | ForEach-Object { [string]$_ }) } else { @() }
    $primaryTestResults = if ($PrimaryResult -and $PrimaryResult.PSObject.Properties['test_results']) { @($PrimaryResult.test_results | ForEach-Object { [string]$_ }) } else { @() }
    $fallbackTests = if ($FallbackResult -and $FallbackResult.PSObject.Properties['tests_run']) { @($FallbackResult.tests_run | ForEach-Object { [string]$_ }) } else { @() }
    $fallbackTestResults = if ($FallbackResult -and $FallbackResult.PSObject.Properties['test_results']) { @($FallbackResult.test_results | ForEach-Object { [string]$_ }) } else { @() }

    $result.summary = if ($FallbackResult) {
        'Codex wrapper only accepted the packaged prompt without executing it, and the safe local fallback could not execute this task scope. TOD published an explicit blocker instead of counting wrapper output as progress.'
    }
    else {
        'Codex wrapper only accepted the packaged prompt without executing it, and no safe local fallback was available. TOD published an explicit blocker instead of counting wrapper output as progress.'
    }
    $result.files_changed = @()
    $result.tests_run = @($primaryTests + $fallbackTests)
    $result.test_results = @($primaryTestResults + $fallbackTestResults)
    $result.failures = @(
        @($primaryFailures) +
        @($fallbackFailures) +
        @('Wrapper-only codex output did not execute the bounded code-change task.')
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique
    $result.recommendations = @(
        @($primaryRecommendations) +
        @($fallbackRecommendations) +
        @('Keep the task blocked_with_reason until either a safe local executor supports this scope or the task is replanned with an explicitly supported bounded implementation target.')
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique
    $result.needs_escalation = $false
    $result.structured_findings = @(
        [pscustomobject]@{
            type = 'blocker'
            reason_code = 'codex_wrapper_only_no_execution'
            file = 'scripts/engines/CodexExecutionEngine.ps1'
            function = 'Invoke-CodexExecutionEngineWrapper'
            reason = 'The codex wrapper accepted the packaged prompt and returned a normalized envelope without executing task instructions or producing evidence.'
            task_id = $TaskId
            prompt_path = $PackagePath
        },
        [pscustomobject]@{
            type = 'blocker'
            reason_code = 'local_execution_scope_not_supported'
            file = 'scripts/engines/LocalExecutionEngine.ps1'
            function = 'Invoke-LocalExecutionEngine'
            reason = $(if ($FallbackResult -and $FallbackResult.PSObject.Properties['summary'] -and -not [string]::IsNullOrWhiteSpace([string]$FallbackResult.summary)) { [string]$FallbackResult.summary } else { 'No safe local execution capability matched this bounded task scope.' })
            task_id = $TaskId
            task_scope = if ($Task.PSObject.Properties['scope']) { [string]$Task.scope } else { '' }
            fallback_engine = $FallbackEngine
        }
    )
    $result.raw_output = [pscustomobject]@{
        engine = [pscustomobject]@{
            name = $engineName
            version = $engineVersion
        }
        task_context = [pscustomobject]@{
            task_id = $TaskId
            objective_id = if ($Task.PSObject.Properties['objective_id']) { [string]$Task.objective_id } else { '' }
            title = if ($Task.PSObject.Properties['title']) { [string]$Task.title } else { '' }
            scope = if ($Task.PSObject.Properties['scope']) { [string]$Task.scope } else { '' }
            prompt_path = $PackagePath
        }
        attempted_engines = @($AttemptedEngines)
        attempts = @($AttemptDetails)
        primary_result = if ($PrimaryResult) { $PrimaryResult.raw_output } else { $null }
        fallback_result = if ($FallbackResult) { $FallbackResult.raw_output } else { $null }
        blocker_reason = 'codex_wrapper_only_no_execution'
        generated_at = (Get-UtcNow)
    }
    $result | Add-Member -NotePropertyName reason_code -NotePropertyValue 'codex_wrapper_only_no_execution' -Force
    $result | Add-Member -NotePropertyName recovery_state -NotePropertyValue $(if ($FallbackResult) { 'replan_required_after_local_fallback' } else { 'local_fallback_or_replan_required' }) -Force
    return (Complete-EngineExecutionResult -Result $result -Status 'failed')
}

function Test-EngineResultPrecheck {
    param($NormalizedResult)

    $warnings = @()
    $isConsistent = $true

    if ([string]::IsNullOrWhiteSpace([string]$NormalizedResult.summary)) {
        $warnings += "summary_empty"
        $isConsistent = $false
    }

    if (@($NormalizedResult.test_results).Length -eq 0) {
        $warnings += "test_results_missing"
        $isConsistent = $false
    }

    if (@($NormalizedResult.failures).Length -gt 0 -and -not [bool]$NormalizedResult.needs_escalation) {
        $warnings += "failures_without_escalation"
    }

    if (@($NormalizedResult.tests_run).Length -gt 0 -and @($NormalizedResult.test_results).Length -eq 0) {
        $warnings += "tests_without_results"
        $isConsistent = $false
    }

    return [pscustomobject]@{
        is_consistent = $isConsistent
        warnings = @($warnings)
        checked_at = Get-UtcNow
    }
}

function Invoke-ExecutionEngine {
    param(
        [Parameter(Mandatory = $true)]$Task,
        [Parameter(Mandatory = $true)][string]$TaskId,
        [Parameter(Mandatory = $true)][string]$PackagePath,
        [Parameter(Mandatory = $true)]$EngineConfig
    )

    $engineDir = Join-Path $PSScriptRoot "engines"
    . (Join-Path $engineDir "ExecutionEngine.ps1")

    $resolvedTaskCategory = Resolve-TaskCategory -Task $Task
    $taskFileHints = @(Get-TaskRoutingFileHints -Task $Task)
    $context = New-EngineTaskContext `
        -TaskId $TaskId `
        -ObjectiveId ([string]$Task.objective_id) `
        -Title ([string]$Task.title) `
        -Scope ([string]$Task.scope) `
        -PromptPath $PackagePath `
        -AllowedFiles @($taskFileHints) `
        -ValidationCommands @() `
        -Metadata @{
            source = "tod.invoke-engine"
            generated_at = (Get-UtcNow)
            task_category = $resolvedTaskCategory
            task_type = if ($Task.PSObject.Properties['type']) { [string]$Task.type } else { '' }
            assigned_executor = if ($Task.PSObject.Properties['assigned_executor']) { [string]$Task.assigned_executor } else { '' }
            local_fallback_target_files = @($taskFileHints)
            local_fallback_target_file = if (@($taskFileHints).Count -eq 1) { [string]$taskFileHints[0] } else { '' }
        }

    $attempted = @()
    $fallbackReason = ""
    $invocationStart = Get-Date
    $retryPolicy = if ($EngineConfig.PSObject.Properties["retry_policy"] -and $null -ne $EngineConfig.retry_policy) { $EngineConfig.retry_policy } else { $null }
    $retryEnabled = if ($retryPolicy -and $retryPolicy.PSObject.Properties["enabled"]) { [bool]$retryPolicy.enabled } else { $true }
    $maxAttemptsPerEngine = if ($retryPolicy -and $retryPolicy.PSObject.Properties["max_attempts_per_engine"] -and $null -ne $retryPolicy.max_attempts_per_engine) { [int]$retryPolicy.max_attempts_per_engine } else { 2 }
    $maxAttemptsByCategory = if ($retryPolicy -and $retryPolicy.PSObject.Properties["max_attempts_by_category"] -and $null -ne $retryPolicy.max_attempts_by_category) { $retryPolicy.max_attempts_by_category } else { $null }
    if ($maxAttemptsByCategory -and $maxAttemptsByCategory.PSObject.Properties[$resolvedTaskCategory] -and $null -ne $maxAttemptsByCategory.$resolvedTaskCategory) {
        $maxAttemptsPerEngine = [int]$maxAttemptsByCategory.$resolvedTaskCategory
    }
    if ($maxAttemptsPerEngine -lt 1) { $maxAttemptsPerEngine = 1 }
    $backoffMs = if ($retryPolicy -and $retryPolicy.PSObject.Properties["backoff_ms"] -and $null -ne $retryPolicy.backoff_ms) { [int]$retryPolicy.backoff_ms } else { 200 }
    if ($backoffMs -lt 0) { $backoffMs = 0 }
    $noRetryCategories = if ($retryPolicy -and $retryPolicy.PSObject.Properties["no_retry_failure_categories"] -and $null -ne $retryPolicy.no_retry_failure_categories) {
        @($retryPolicy.no_retry_failure_categories | ForEach-Object { ([string]$_).ToLowerInvariant() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    }
    else {
        @("auth", "capability")
    }
    $backoffByCategory = if ($retryPolicy -and $retryPolicy.PSObject.Properties["backoff_by_failure_category"] -and $null -ne $retryPolicy.backoff_by_failure_category) {
        $retryPolicy.backoff_by_failure_category
    }
    else {
        [pscustomobject]@{ timeout = 2; network = 2; rate_limit = 3 }
    }
    $retryStatuses = if ($retryPolicy -and $retryPolicy.PSObject.Properties["retry_on_status"] -and $null -ne $retryPolicy.retry_on_status) {
        @($retryPolicy.retry_on_status | ForEach-Object { ([string]$_).ToLowerInvariant() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    }
    else {
        @("failed", "error", "not_implemented")
    }
    $attemptDetails = @()

    function Get-FailureCategory {
        param([string]$Message)

        $msg = ([string]$Message).ToLowerInvariant()
        if ($msg -match 'timeout|timed out|deadline') { return 'timeout' }
        if ($msg -match 'auth|unauthoriz|forbidden|permission|token|credential') { return 'auth' }
        if ($msg -match 'rate limit|429|throttle') { return 'rate_limit' }
        if ($msg -match 'network|dns|socket|connect|connection|tls|ssl') { return 'network' }
        if ($msg -match 'not implemented|unsupported|capability') { return 'capability' }
        return 'unknown'
    }

    function Invoke-OneEngine {
        param([string]$EngineName, $Ctx)

        switch ($EngineName) {
            "codex" {
                . (Join-Path $engineDir "CodexExecutionEngine.ps1")
                return (Invoke-CodexExecutionEngine -Context $Ctx)
            }
            "local" {
                . (Join-Path $engineDir "LocalExecutionEngine.ps1")
                return (Invoke-LocalExecutionEngine -Context $Ctx)
            }
            default {
                throw "Unsupported execution engine '$EngineName'."
            }
        }
    }

    $selected = [string]$EngineConfig.active
    $attempted += $selected

    function Invoke-OneEngineWithRetry {
        param([string]$EngineName, $Ctx)

        $localAttempts = @()
        $maxLocalAttempts = if ($retryEnabled) { $maxAttemptsPerEngine } else { 1 }
        for ($attempt = 1; $attempt -le $maxLocalAttempts; $attempt++) {
            try {
                $result = Invoke-OneEngine -EngineName $EngineName -Ctx $Ctx
                $status = ([string]$result.status).ToLowerInvariant()
                $retryableStatus = ($status -in $retryStatuses)
                $localAttempts += [pscustomobject]@{
                    engine = $EngineName
                    attempt = $attempt
                    status = if ([string]::IsNullOrWhiteSpace($status)) { "completed" } else { $status }
                    retryable = [bool]$retryableStatus
                    failure_category = if ($retryableStatus) { "status" } else { "none" }
                    message = ""
                    created_at = Get-UtcNow
                }

                if ($retryableStatus -and $attempt -lt $maxLocalAttempts) {
                    if ($backoffMs -gt 0) { Start-Sleep -Milliseconds $backoffMs }
                    continue
                }

                return [pscustomobject]@{
                    result = $result
                    success = (-not $retryableStatus)
                    terminal_reason = if ($retryableStatus) { "status:$status" } else { "success" }
                    attempts = @($localAttempts)
                    terminal_message = if ($retryableStatus) { [string]$status } else { '' }
                }
            }
            catch {
                $msg = [string]$_.Exception.Message
                $failureCategory = Get-FailureCategory -Message $msg
                $isRetryableCategory = -not ($noRetryCategories -contains $failureCategory)
                $localAttempts += [pscustomobject]@{
                    engine = $EngineName
                    attempt = $attempt
                    status = "exception"
                    retryable = [bool]$isRetryableCategory
                    failure_category = $failureCategory
                    message = $msg
                    created_at = Get-UtcNow
                }

                if ($isRetryableCategory -and $attempt -lt $maxLocalAttempts) {
                    $backoffMultiplier = 1
                    if ($backoffByCategory -and $backoffByCategory.PSObject.Properties[$failureCategory] -and $null -ne $backoffByCategory.$failureCategory) {
                        $backoffMultiplier = [int]$backoffByCategory.$failureCategory
                        if ($backoffMultiplier -lt 1) { $backoffMultiplier = 1 }
                    }

                    if ($backoffMs -gt 0) { Start-Sleep -Milliseconds ($backoffMs * $backoffMultiplier) }
                    continue
                }

                return [pscustomobject]@{
                    result = $null
                    success = $false
                    terminal_reason = "exception:$failureCategory"
                    attempts = @($localAttempts)
                    terminal_message = $msg
                }
            }
        }
    }

    $engineResult = $null
    $mustFallbackByStatus = $false
    $primaryAttempt = Invoke-OneEngineWithRetry -EngineName $selected -Ctx $context
    $attemptDetails += @($primaryAttempt.attempts)
    $primaryReasonCode = ''
    if ($primaryAttempt.result -and $primaryAttempt.result.PSObject.Properties['reason_code'] -and -not [string]::IsNullOrWhiteSpace([string]$primaryAttempt.result.reason_code)) {
        $primaryReasonCode = ([string]$primaryAttempt.result.reason_code).ToLowerInvariant()
    }
    if ($primaryAttempt.success) {
        $engineResult = $primaryAttempt.result
    }
    else {
        $mustFallbackByStatus = $true
        $fallbackReason = "active_engine_$([string]$primaryAttempt.terminal_reason)"
        if (-not [string]::IsNullOrWhiteSpace([string]$primaryAttempt.terminal_message)) {
            $fallbackReason = "$fallbackReason message=$([string]$primaryAttempt.terminal_message)"
        }
    }

    if ($mustFallbackByStatus) {
        $fallback = [string]$EngineConfig.fallback
        $fallbackReasonCodes = if ($EngineConfig.PSObject.Properties['fallback_reason_codes'] -and $null -ne $EngineConfig.fallback_reason_codes) {
            @($EngineConfig.fallback_reason_codes | ForEach-Object { ([string]$_).ToLowerInvariant() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
        }
        else {
            @()
        }
        $requiresFallbackReasonCode = @($fallbackReasonCodes).Count -gt 0
        $fallbackReasonAllowed = (-not $requiresFallbackReasonCode) -or ((-not [string]::IsNullOrWhiteSpace($primaryReasonCode)) -and ($fallbackReasonCodes -contains $primaryReasonCode))
        $canFallback = [bool]$EngineConfig.allow_fallback -and -not [string]::IsNullOrWhiteSpace($fallback) -and ($fallback -ne $selected) -and $fallbackReasonAllowed
        if ($canFallback) {
            $attempted += $fallback
            $fallbackAttempt = Invoke-OneEngineWithRetry -EngineName $fallback -Ctx $context
            $attemptDetails += @($fallbackAttempt.attempts)
            if ($fallbackAttempt.success) {
                $engineResult = $fallbackAttempt.result
                $selected = $fallback
            }
            else {
                if ($primaryAttempt.result -and $primaryAttempt.result.PSObject.Properties['reason_code'] -and [string]$primaryAttempt.result.reason_code -eq 'codex_wrapper_only_no_execution') {
                    $engineResult = New-ExecutionEngineBlockedResult -Task $Task -TaskId $TaskId -PackagePath $PackagePath -PrimaryResult $primaryAttempt.result -FallbackResult $fallbackAttempt.result -AttemptedEngines @($attempted) -AttemptDetails @($attemptDetails) -FallbackEngine $fallback
                }
                else {
                    throw "Fallback engine '$fallback' failed after retries. reason=$([string]$fallbackAttempt.terminal_reason)"
                }
            }
        }
        elseif ($null -eq $engineResult) {
            if ($primaryAttempt.result -and $primaryAttempt.result.PSObject.Properties['reason_code'] -and [string]$primaryAttempt.result.reason_code -eq 'codex_wrapper_only_no_execution') {
                $engineResult = New-ExecutionEngineBlockedResult -Task $Task -TaskId $TaskId -PackagePath $PackagePath -PrimaryResult $primaryAttempt.result -FallbackResult $null -AttemptedEngines @($attempted) -AttemptDetails @($attemptDetails)
            }
            elseif ($primaryAttempt.result) {
                $engineResult = $primaryAttempt.result
            }
            else {
                throw "Execution engine '$selected' failed and fallback is unavailable. $fallbackReason"
            }
        }
    }

    $envelope = Convert-EngineResultToNormalizedEnvelope -EngineResult $engineResult -EngineMetadata ([pscustomobject]@{ name = $selected }) -FallbackReason $fallbackReason
    $normalizedPayload = Normalize-EngineResultPayload -EngineResult $envelope
    $precheck = Test-EngineResultPrecheck -NormalizedResult $normalizedPayload

    $envelope.summary = [string]$normalizedPayload.summary
    $envelope.files_changed = @($normalizedPayload.files_changed)
    $envelope.tests_run = @($normalizedPayload.tests_run)
    $envelope.test_results = @($normalizedPayload.test_results)
    $envelope.failures = @($normalizedPayload.failures)
    $envelope.recommendations = @($normalizedPayload.recommendations)
    $envelope.needs_escalation = [bool]$normalizedPayload.needs_escalation
    $envelope | Add-Member -NotePropertyName review_precheck -NotePropertyValue $precheck -Force
    $elapsedMs = [int]((Get-Date) - $invocationStart).TotalMilliseconds
    $finalFailureCategory = "none"
    $lastFailureAttempt = @($attemptDetails | Where-Object { [string]$_.failure_category -ne "none" } | Select-Object -Last 1)
    if (@($lastFailureAttempt).Count -gt 0) {
        $finalFailureCategory = [string]$lastFailureAttempt[0].failure_category
    }

    return [pscustomobject]@{
        task_id = $TaskId
        package_path = $PackagePath
        attempted_engines = @($attempted)
        attempts = @($attemptDetails)
        failure_category = $finalFailureCategory
        active_engine = $selected
        fallback_applied = (@($attempted).Count -gt 1)
        elapsed_ms = $elapsedMs
        result = $envelope
    }
}

function Load-SyncPolicy {
    if (-not (Test-Path -Path $syncPolicyPath)) {
        return [pscustomobject]@{
            contract_version = "tod-mim-shared-contract-v1"
            schema_version = "2026-03-09-01"
            required_capabilities = @("health", "status", "manifest", "objectives", "tasks", "results", "reviews", "journal")
            signature_sources = @(
                "docs/tod-mim-shared-contract-v1.md",
                "docs/mim-manifest-contract-v1.md",
                "client/mim_api_client.ps1",
                "client/mim_api_helpers.ps1",
                "scripts/TOD.ps1",
                "tod/config/tod-config.json"
            )
        }
    }

    return (Get-Content -Path $syncPolicyPath -Raw) | ConvertFrom-Json
}

function Normalize-RepoPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
    return (($Path -replace '[\\/]+', '/').TrimStart('./')).Trim()
}

function Get-FileSha256 {
    param([string]$Path)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $stream = [System.IO.File]::OpenRead($Path)
        try {
            $hashBytes = $sha.ComputeHash($stream)
        }
        finally {
            $stream.Dispose()
        }
        return ([System.BitConverter]::ToString($hashBytes).Replace("-", "").ToLowerInvariant())
    }
    finally {
        $sha.Dispose()
    }
}

function Get-TextSha256 {
    param([string]$Text)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        $hashBytes = $sha.ComputeHash($bytes)
        return ([System.BitConverter]::ToString($hashBytes).Replace("-", "").ToLowerInvariant())
    }
    finally {
        $sha.Dispose()
    }
}

function Get-DeterministicRepoSignature {
    param([Parameter(Mandatory = $true)]$Policy)

    $sourceFiles = @($Policy.signature_sources | ForEach-Object { Normalize-RepoPath -Path ([string]$_) } | Where-Object { $_ }) | Select-Object -Unique
    $hashEntries = @()
    $missing = @()

    foreach ($src in $sourceFiles) {
        $fullPath = Join-Path $repoRoot ($src -replace '/', '\\')
        if (Test-Path -Path $fullPath -PathType Leaf) {
            $fileHash = Get-FileSha256 -Path $fullPath
            $hashEntries += "{0}:{1}" -f $src, $fileHash
        }
        else {
            $missing += $src
        }
    }

    $sortedEntries = @($hashEntries | Sort-Object)
    $aggregateInput = ($sortedEntries -join "`n")
    $aggregateHash = if ([string]::IsNullOrWhiteSpace($aggregateInput)) { Get-TextSha256 -Text "" } else { Get-TextSha256 -Text $aggregateInput }

    return [pscustomobject]@{
        algorithm = "sha256"
        signature = "sha256:$aggregateHash"
        hashed_files = @($sortedEntries)
        missing_files = @($missing | Sort-Object)
    }
}

function To-StringArray {
    param($Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [string]) {
        if ([string]::IsNullOrWhiteSpace($Value)) { return @() }
        return @([string]$Value)
    }
    return @($Value | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Compare-ManifestState {
    param(
        [Parameter(Mandatory = $true)]$LiveManifest,
        $CachedManifest,
        [Parameter(Mandatory = $true)]$Policy,
        [Parameter(Mandatory = $true)]$LocalSignature
    )

    $driftFindings = @()
    $recommendedActions = @()

    $liveContract = [string]$LiveManifest.contract_version
    $expectedContract = [string]$Policy.contract_version
    if (-not [string]::IsNullOrWhiteSpace($expectedContract) -and ($liveContract -ne $expectedContract)) {
        $driftFindings += [pscustomobject]@{
            field = "contract_version"
            severity = "breaking"
            expected = $expectedContract
            observed = $liveContract
            message = "Live manifest contract_version is incompatible with expected version."
        }
        $recommendedActions += "escalate-contract-incompatibility"
    }

    $liveSchema = [string]$LiveManifest.schema_version
    $expectedSchema = [string]$Policy.schema_version
    if (-not [string]::IsNullOrWhiteSpace($expectedSchema) -and ($liveSchema -ne $expectedSchema)) {
        $driftFindings += [pscustomobject]@{
            field = "schema_version"
            severity = "warn"
            expected = $expectedSchema
            observed = $liveSchema
            message = "Schema version differs from expected policy."
        }
    }

    $requiredCaps = @(To-StringArray -Value $Policy.required_capabilities | ForEach-Object { $_.ToLowerInvariant() })
    $liveCaps = @(To-StringArray -Value $LiveManifest.capabilities | ForEach-Object { $_.ToLowerInvariant() })
    $missingCaps = @($requiredCaps | Where-Object { $liveCaps -notcontains $_ })
    if (@($missingCaps).Count -gt 0) {
        $driftFindings += [pscustomobject]@{
            field = "capabilities"
            severity = "warn"
            expected = @($requiredCaps)
            observed = @($liveCaps)
            missing = @($missingCaps)
            message = "Live manifest is missing one or more required capabilities."
        }
    }

    $cachedRepoSig = if ($CachedManifest) { [string]$CachedManifest.repo_signature } else { "" }
    $liveRepoSig = [string]$LiveManifest.repo_signature
    if (-not [string]::IsNullOrWhiteSpace($cachedRepoSig) -and -not [string]::IsNullOrWhiteSpace($liveRepoSig) -and ($cachedRepoSig -ne $liveRepoSig)) {
        $driftFindings += [pscustomobject]@{
            field = "repo_signature"
            severity = "warn"
            expected = $cachedRepoSig
            observed = $liveRepoSig
            message = "Live repo signature changed since last cached manifest."
        }
        $recommendedActions += "trigger-reindex"
    }

    if (-not [string]::IsNullOrWhiteSpace($liveRepoSig) -and ($liveRepoSig -ne [string]$LocalSignature.signature)) {
        $driftFindings += [pscustomobject]@{
            field = "repo_signature_local"
            severity = "info"
            expected = [string]$LocalSignature.signature
            observed = $liveRepoSig
            message = "Live MIM repo signature differs from local TOD contract signature baseline."
        }
    }

    $cachedUpdatedAt = if ($CachedManifest) { [string]$CachedManifest.last_updated_at } else { "" }
    $liveUpdatedAt = [string]$LiveManifest.last_updated_at
    if (-not [string]::IsNullOrWhiteSpace($cachedUpdatedAt) -and -not [string]::IsNullOrWhiteSpace($liveUpdatedAt) -and ($cachedUpdatedAt -ne $liveUpdatedAt)) {
        $driftFindings += [pscustomobject]@{
            field = "last_updated_at"
            severity = "info"
            expected = $cachedUpdatedAt
            observed = $liveUpdatedAt
            message = "Manifest update timestamp changed."
        }
    }

    $status = if (@($driftFindings | Where-Object { $_.severity -eq "breaking" }).Count -gt 0) {
        "breaking"
    }
    elseif (@($driftFindings | Where-Object { $_.severity -eq "warn" }).Count -gt 0) {
        "warn"
    }
    else {
        "none"
    }

    $escalationCode = Get-SyncEscalationCode -Status $status -DriftFindings @($driftFindings)
    $reconciliationPlan = Get-SyncReconciliationPlan -Status $status -DriftFindings @($driftFindings) -RecommendedActions @($recommendedActions)

    return [pscustomobject]@{
        compared_at = Get-UtcNow
        status = $status
        escalation_code = $escalationCode
        drift_findings = @($driftFindings)
        recommended_actions = @($recommendedActions | Select-Object -Unique)
        reconciliation_plan = @($reconciliationPlan)
        expected = [pscustomobject]@{
            contract_version = $Policy.contract_version
            schema_version = $Policy.schema_version
            required_capabilities = @($requiredCaps)
            local_repo_signature = [string]$LocalSignature.signature
        }
        observed = [pscustomobject]@{
            contract_version = [string]$LiveManifest.contract_version
            schema_version = [string]$LiveManifest.schema_version
            repo_signature = [string]$LiveManifest.repo_signature
            capabilities = @(To-StringArray -Value $LiveManifest.capabilities)
            last_updated_at = [string]$LiveManifest.last_updated_at
        }
    }
}

function Get-SyncEscalationCode {
    param(
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $true)]$DriftFindings
    )

    if ($Status -eq "breaking") {
        $hasContract = @($DriftFindings | Where-Object { $_.field -eq "contract_version" }).Count -gt 0
        if ($hasContract) { return "SYNC_CONTRACT_INCOMPATIBLE" }
        return "SYNC_BREAKING_DRIFT"
    }

    if ($Status -eq "warn") {
        if (@($DriftFindings | Where-Object { $_.field -eq "repo_signature" }).Count -gt 0) { return "SYNC_REINDEX_REQUIRED" }
        if (@($DriftFindings | Where-Object { $_.field -eq "capabilities" }).Count -gt 0) { return "SYNC_CAPABILITY_WARN" }
        if (@($DriftFindings | Where-Object { $_.field -eq "schema_version" }).Count -gt 0) { return "SYNC_SCHEMA_WARN" }
        return "SYNC_WARN"
    }

    return "SYNC_OK"
}

function Get-SyncReconciliationPlan {
    param(
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $true)]$DriftFindings,
        [Parameter(Mandatory = $true)]$RecommendedActions
    )

    $plan = @()

    if (@($DriftFindings | Where-Object { $_.field -eq "contract_version" -and $_.severity -eq "breaking" }).Count -gt 0) {
        $plan += [pscustomobject]@{
            step_id = "contract_review"
            action = "require-user-review"
            reason = "Contract version mismatch is breaking and requires explicit compatibility decision."
            blocking = $true
            auto_executable = $false
            recommended_command = ".\\scripts\\TOD.ps1 -Action sync-mim"
        }
    }

    if (@($RecommendedActions | Where-Object { $_ -eq "trigger-reindex" }).Count -gt 0) {
        $plan += [pscustomobject]@{
            step_id = "repo_reindex"
            action = "reindex-repository"
            reason = "Manifest repo signature changed from cached state."
            blocking = $false
            auto_executable = $true
            recommended_command = ".\\scripts\\TOD-Engineer.ps1 -Action index-repo"
        }
    }

    if (@($DriftFindings | Where-Object { $_.field -eq "capabilities" }).Count -gt 0) {
        $plan += [pscustomobject]@{
            step_id = "capability_degrade"
            action = "degrade-remote-calls"
            reason = "Required capabilities are missing in manifest; avoid unavailable remote operations."
            blocking = $false
            auto_executable = $true
            recommended_command = "Use hybrid mode and fallback_to_local=true"
        }
    }

    if (($Status -eq "none") -or (@($plan).Count -eq 0)) {
        $plan += [pscustomobject]@{
            step_id = "continue"
            action = "continue-workflow"
            reason = "No blocking drift detected."
            blocking = $false
            auto_executable = $true
            recommended_command = ".\\scripts\\TOD.ps1 -Action sync-mim"
        }
    }

    return @($plan)
}

function Resolve-SyncDecision {
    param([Parameter(Mandatory = $true)][string]$Status)

    switch ($Status.ToLowerInvariant()) {
        "none" { return "ok" }
        "warn" { return "warn" }
        "breaking" { return "escalate" }
        default { return "warn" }
    }
}

function Resolve-SyncDecisionCode {
    param([Parameter(Mandatory = $true)][string]$Decision)

    switch ($Decision.ToLowerInvariant()) {
        "ok" { return "SYNC_DECISION_OK" }
        "warn" { return "SYNC_DECISION_WARN" }
        "escalate" { return "SYNC_DECISION_ESCALATE" }
        default { return "SYNC_DECISION_WARN" }
    }
}

function Get-ActionCapabilities {
    param([Parameter(Mandatory = $true)][string]$ActionName)

    switch ($ActionName) {
        "ping-mim" { return @("health", "status") }
        "new-objective" { return @("objectives") }
        "list-objectives" { return @("objectives") }
        "add-task" { return @("tasks") }
        "list-tasks" { return @("tasks") }
        "add-result" { return @("results") }
        "review-task" { return @("reviews") }
        "show-journal" { return @("journal") }
        default { return @() }
    }
}

function Get-RiskyActions {
    return @("new-objective", "add-task", "package-task", "add-result", "review-task")
}

function Get-SyncComparisonStatus {
    param($State)
    if ($State -and $State.PSObject.Properties["sync_state"] -and $State.sync_state -and $State.sync_state.PSObject.Properties["last_comparison"] -and $State.sync_state.last_comparison) {
        return [string]$State.sync_state.last_comparison.status
    }
    return ""
}

function Assert-ContractGate {
    param(
        [Parameter(Mandatory = $true)][string]$ActionName,
        [Parameter(Mandatory = $true)]$State,
        [switch]$AllowDrift
    )

    if ($AllowDrift) { return }
    if ((Get-RiskyActions) -notcontains $ActionName) { return }

    $status = (Get-SyncComparisonStatus -State $State)
    if ($status -eq "breaking") {
        throw "Blocked action '$ActionName' due to contract drift (status=breaking). Run sync-mim and review drift findings first, or rerun with -AllowContractDrift for explicit override."
    }
}

function Apply-CapabilityDegrade {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][string]$ActionName
    )

    if (-not (Use-Remote -Config $Config)) {
        return [pscustomobject]@{ degraded = $false; missing = @() }
    }

    $required = @(Get-ActionCapabilities -ActionName $ActionName | ForEach-Object { $_.ToLowerInvariant() })
    if (@($required).Count -eq 0) {
        return [pscustomobject]@{ degraded = $false; missing = @() }
    }

    $cachedManifest = $null
    if ($State -and $State.PSObject.Properties["sync_state"] -and $State.sync_state -and $State.sync_state.PSObject.Properties["cached_manifest"]) {
        $cachedManifest = $State.sync_state.cached_manifest
    }
    if (-not $cachedManifest) {
        return [pscustomobject]@{ degraded = $false; missing = @() }
    }

    $caps = @()
    if ($cachedManifest.PSObject.Properties["capabilities"]) {
        $caps = @($cachedManifest.capabilities | ForEach-Object { [string]$_ } | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() })
    }
    $missing = @($required | Where-Object { $caps -notcontains $_ })
    if (@($missing).Count -eq 0) {
        return [pscustomobject]@{ degraded = $false; missing = @() }
    }

    Write-Warning "Missing manifest capabilities for action '$ActionName': $($missing -join ', '). Remote calls will be degraded to local behavior when possible."
    if (([string]$Config.mode).ToLowerInvariant() -eq "remote") {
        $Config.mode = "hybrid"
        $Config.fallback_to_local = $true
    }

    return [pscustomobject]@{ degraded = $true; missing = @($missing) }
}

function Apply-ExecutionReadinessPolicy {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][string]$ActionName,
        [switch]$ApplyPlan
    )

    $signal = Get-TodExecutionReadinessPayload -Config $Config
    $effectiveApplyPlan = [bool]$ApplyPlan

    $actionNameLower = $ActionName.ToLowerInvariant()
    $blockActions = @($signal.policy.block_actions | ForEach-Object { ([string]$_).ToLowerInvariant() })
    $degradeActions = @($signal.policy.degrade_actions | ForEach-Object { ([string]$_).ToLowerInvariant() })
    $blockStates = if ($signal.policy.PSObject.Properties["block_states"]) { @($signal.policy.block_states | ForEach-Object { ([string]$_).ToLowerInvariant() }) } else { @("stale", "invalid", "unknown") }
    $degradeStates = if ($signal.policy.PSObject.Properties["degrade_states"]) { @($signal.policy.degrade_states | ForEach-Object { ([string]$_).ToLowerInvariant() }) } else { @("degraded", "stale", "invalid", "unknown") }
    $statusLower = if ($signal.readiness.PSObject.Properties["status"] -and -not [string]::IsNullOrWhiteSpace([string]$signal.readiness.status)) { ([string]$signal.readiness.status).ToLowerInvariant() } else { "unknown" }
    $blocked = $false
    $degraded = $false

    if ($signal.policy.enabled) {
        if (($blockActions -contains $actionNameLower) -and ($blockStates -contains $statusLower)) {
            $blocked = $true
        }
        elseif (($degradeActions -contains $actionNameLower) -and ($degradeStates -contains $statusLower)) {
            $degraded = $true
        }
    }

    if ($degraded -and $effectiveApplyPlan -and [bool]$signal.policy.degrade_apply_plan) {
        $effectiveApplyPlan = $false
    }

    if ($degraded) {
        Write-Warning "Execution readiness is $([string]$signal.readiness.status); action '$ActionName' is running in degraded mode."
    }

    $policyOutcome = if ($blocked) { "block" } elseif ($degraded) { "degrade" } else { "allow" }
    $decisionPath = @(
        "signal:execution-readiness",
        "status:$([string]$signal.readiness.status)",
        "source:$([string]$signal.readiness.reason)",
        "action:$ActionName",
        "policy_outcome:$policyOutcome"
    )
    if ($ApplyPlan.IsPresent) {
        $decisionPath += "apply_plan_requested:true"
        $decisionPath += "apply_plan_effective:$([bool]$effectiveApplyPlan)"
    }

    return [pscustomobject]@{
        blocked = $blocked
        degraded = $degraded
        effective_apply_plan = $effectiveApplyPlan
        signal = $signal
        trace = [pscustomobject]@{
            status = [string]$signal.readiness.status
            source = [string]$signal.readiness.reason
            detail = if ($signal.readiness.PSObject.Properties["detail"]) { [string]$signal.readiness.detail } else { "" }
            valid = [bool]$signal.readiness.valid
            execution_allowed = if ($signal.readiness.PSObject.Properties["execution_allowed"]) { [bool]$signal.readiness.execution_allowed } else { $false }
            authoritative = if ($signal.readiness.PSObject.Properties["authoritative"]) { [bool]$signal.readiness.authoritative } else { $true }
            freshness_state = if ($signal.readiness.PSObject.Properties["freshness_state"]) { [string]$signal.readiness.freshness_state } else { "unknown" }
            signal_name = if ($signal.PSObject.Properties["signal_name"]) { [string]$signal.signal_name } else { "execution-readiness" }
            evaluated_action = $ActionName
            policy_outcome = $policyOutcome
            effective_apply_plan = [bool]$effectiveApplyPlan
            decision_path = @($decisionPath)
        }
    }
}

function Save-JsonObject {
    param([Parameter(Mandatory = $true)]$Object, [Parameter(Mandatory = $true)][string]$Path)
    $Object | ConvertTo-Json -Depth 16 | Set-Content -Path $Path
}

function Get-EngineeringMemoryBuckets {
    return @(
        "architecture_memory",
        "repo_memory",
        "decision_memory",
        "failure_memory",
        "pattern_memory",
        "test_memory",
        "packaging_lessons",
        "engine_performance_memory",
        "routing_decision_memory"
    )
}

function New-EngineeringMemoryDocument {
    $document = [pscustomobject]@{}
    foreach ($bucket in @(Get-EngineeringMemoryBuckets)) {
        $document | Add-Member -NotePropertyName $bucket -NotePropertyValue @() -Force
    }
    return $document
}

function Resolve-EngineeringMemoryBucketPath {
    param([Parameter(Mandatory = $true)][string]$BucketName)

    return (Join-Path $engineeringKnowledgeDir ($BucketName + ".json"))
}

function Test-EngineeringMemoryAvailable {
    if (Test-Path -Path $engineeringMemoryPath) {
        return $true
    }

    foreach ($bucket in @(Get-EngineeringMemoryBuckets)) {
        if (Test-Path -Path (Resolve-EngineeringMemoryBucketPath -BucketName $bucket)) {
            return $true
        }
    }

    return $false
}

function Load-EngineeringMemory {
    $document = New-EngineeringMemoryDocument
    $loadedFromBuckets = $false

    foreach ($bucket in @(Get-EngineeringMemoryBuckets)) {
        $bucketPath = Resolve-EngineeringMemoryBucketPath -BucketName $bucket
        if (-not (Test-Path -Path $bucketPath)) {
            continue
        }

        try {
            $raw = Get-Content -Path $bucketPath -Raw -ErrorAction Stop
            if ([string]::IsNullOrWhiteSpace($raw)) {
                continue
            }

            $parsed = $raw | ConvertFrom-Json
            $document.$bucket = @($parsed | Where-Object { $null -ne $_ })
            $loadedFromBuckets = $true
        }
        catch {
        }
    }

    if ($loadedFromBuckets) {
        return $document
    }

    if (-not (Test-Path -Path $engineeringMemoryPath)) {
        return $document
    }

    try {
        $raw = Get-Content -Path $engineeringMemoryPath -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return $document
        }

        $parsed = $raw | ConvertFrom-Json
        foreach ($bucket in @(Get-EngineeringMemoryBuckets)) {
            if ($parsed.PSObject.Properties[$bucket]) {
                $document.$bucket = @($parsed.$bucket | Where-Object { $null -ne $_ })
            }
        }
    }
    catch {
    }

    return $document
}

function Save-EngineeringMemory {
    param([Parameter(Mandatory = $true)]$Memory)

    if (-not (Test-Path -Path $engineeringKnowledgeDir)) {
        New-Item -ItemType Directory -Path $engineeringKnowledgeDir -Force | Out-Null
    }

    $document = New-EngineeringMemoryDocument
    foreach ($bucket in @(Get-EngineeringMemoryBuckets)) {
        $values = @()
        if ($Memory -and $Memory.PSObject.Properties[$bucket]) {
            $values = @($Memory.$bucket | Where-Object { $null -ne $_ })
        }
        $document.$bucket = @($values)
        Save-JsonObject -Object @($values) -Path (Resolve-EngineeringMemoryBucketPath -BucketName $bucket)
    }

    Save-JsonObject -Object $document -Path $engineeringMemoryPath
    Save-JsonObject -Object $document -Path $stateEngineeringMemoryPath
    return $document
}

function Update-RepoIndexSyncState {
    param(
        [bool]$Stale,
        [string]$Reason,
        [string]$ManifestRepoSignature,
        [bool]$ReindexTriggered,
        [bool]$ReindexSucceeded
    )

    foreach ($path in @($repoIndexPath, $stateRepoIndexPath)) {
        if (-not (Test-Path -Path $path)) { continue }

        $index = (Get-Content -Path $path -Raw) | ConvertFrom-Json
        $index | Add-Member -NotePropertyName sync_status -NotePropertyValue ([pscustomobject]@{
                stale = $Stale
                stale_reason = $Reason
                manifest_repo_signature = $ManifestRepoSignature
                reindex_triggered = $ReindexTriggered
                reindex_succeeded = $ReindexSucceeded
                updated_at = Get-UtcNow
            }) -Force
        Save-JsonObject -Object $index -Path $path
    }
}

function Add-EngineeringMemorySyncNote {
    param(
        [string]$SyncDecision,
        [string]$Status,
        [string[]]$RecommendedActions,
        [string]$Summary
    )

    $memory = Load-EngineeringMemory
    if (-not $memory.PSObject.Properties["decision_memory"]) {
        $memory | Add-Member -NotePropertyName decision_memory -NotePropertyValue @() -Force
    }

    $entry = [pscustomobject]@{
        id = "MEM-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 8).ToUpperInvariant())
        title = "sync-mim $SyncDecision"
        note = $Summary
        tags = @("sync", "mim", "manifest", $SyncDecision, $Status)
        recommended_actions = @($RecommendedActions)
        created_at = Get-UtcNow
    }

    $memory.decision_memory += $entry
    Save-EngineeringMemory -Memory $memory | Out-Null
}

function Try-LogSyncToMimJournal {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)]$Payload
    )

    if (-not (Use-Remote -Config $Config)) { return $false }
    if (-not (Get-Command -Name New-MimJournalEntry -ErrorAction SilentlyContinue)) { return $false }

    try {
        $null = New-MimJournalEntry -BaseUrl $Config.mim_base_url -TimeoutSeconds ([int]$Config.timeout_seconds) -Entry $Payload
        return $true
    }
    catch {
        Write-Warning "MIM journal write unavailable for sync log: $($_.Exception.Message)"
        return $false
    }
}

function Use-Remote {
    param([Parameter(Mandatory = $true)]$Config)
    return @("remote", "hybrid") -contains ([string]$Config.mode).ToLowerInvariant()
}

function Use-Local {
    param([Parameter(Mandatory = $true)]$Config)
    return @("local", "hybrid") -contains ([string]$Config.mode).ToLowerInvariant()
}

function Invoke-MimSafely {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][scriptblock]$ApiCall,
        [string]$Operation = "MIM API call"
    )

    try {
        return & $ApiCall
    }
    catch {
        if (([string]$Config.mode).ToLowerInvariant() -eq "hybrid" -and [bool]$Config.fallback_to_local) {
            Write-Warning "$Operation failed against MIM, falling back to local state. Error: $($_.Exception.Message)"
            return $null
        }

        throw "$Operation failed against MIM. Error: $($_.Exception.Message)"
    }
}

function Try-ParseInt {
    param([string]$Value)

    $parsed = 0
    if ([int]::TryParse($Value, [ref]$parsed)) {
        return $parsed
    }
    return $null
}

function Resolve-RemoteObjectiveId {
    param(
        [string]$ObjectiveId,
        $State
    )

    $direct = Try-ParseInt -Value $ObjectiveId
    if ($null -ne $direct) { return $direct }

    if ($null -eq $State) { return $null }
    $objective = $State.objectives | Where-Object { $_.id -eq $ObjectiveId } | Select-Object -First 1
    if ($null -eq $objective) { return $null }

    if ($objective.PSObject.Properties["remote_objective_id"]) {
        return Try-ParseInt -Value ([string]$objective.remote_objective_id)
    }
    return $null
}

function Resolve-RemoteTaskId {
    param(
        [string]$TaskId,
        $State
    )

    $direct = Try-ParseInt -Value $TaskId
    if ($null -ne $direct) { return $direct }

    if ($null -eq $State) { return $null }
    $task = $State.tasks | Where-Object { $_.id -eq $TaskId } | Select-Object -First 1
    if ($null -eq $task) { return $null }

    if ($task.PSObject.Properties["remote_task_id"]) {
        return Try-ParseInt -Value ([string]$task.remote_task_id)
    }
    return $null
}

function Convert-RemoteTaskToTodTask {
    param([Parameter(Mandatory = $true)]$Task)

    $remoteTaskId = if ($Task.PSObject.Properties["task_id"]) { [string]$Task.task_id } else { "" }
    return [pscustomobject]@{
        id = if (-not [string]::IsNullOrWhiteSpace($remoteTaskId)) { $remoteTaskId } else { "" }
        remote_task_id = $remoteTaskId
        objective_id = if ($Task.PSObject.Properties["objective_id"]) { [string]$Task.objective_id } else { "" }
        title = if ($Task.PSObject.Properties["title"]) { [string]$Task.title } else { "" }
        scope = if ($Task.PSObject.Properties["scope"]) { [string]$Task.scope } else { "" }
        type = "implementation"
        task_category = ""
        assigned_executor = if ($Task.PSObject.Properties["assigned_to"]) { [string]$Task.assigned_to } elseif ($Task.PSObject.Properties["assigned_executor"]) { [string]$Task.assigned_executor } else { "codex" }
        status = if ($Task.PSObject.Properties["status"]) { [string]$Task.status } else { "pending" }
        dependencies = if ($Task.PSObject.Properties["dependencies"]) { @($Task.dependencies | ForEach-Object { [string]$_ }) } else { @() }
        acceptance_criteria = if ($Task.PSObject.Properties["acceptance_criteria"]) { @($Task.acceptance_criteria | ForEach-Object { [string]$_ }) } else { @() }
        updated_at = Get-UtcNow
    }
}

function Resolve-RemoteExecutionTask {
    param(
        [Parameter(Mandatory = $true)][string]$TaskId,
        [string]$ObjectiveId,
        [Parameter(Mandatory = $true)]$Config
    )

    if (-not (Use-Remote -Config $Config)) {
        return $null
    }
    if (-not (Get-Command -Name Get-MimTasks -ErrorAction SilentlyContinue)) {
        return $null
    }

    $remoteObjectiveId = if (-not [string]::IsNullOrWhiteSpace($ObjectiveId)) { Resolve-RemoteObjectiveId -ObjectiveId $ObjectiveId -State $null } else { $null }
    $remoteTasks = Invoke-MimSafely -Config $Config -Operation "GET /tasks" -ApiCall {
        Get-MimTasks -BaseUrl $Config.mim_base_url -ObjectiveId $(if ($null -ne $remoteObjectiveId) { [string]$remoteObjectiveId } else { "" }) -TimeoutSeconds ([int]$Config.timeout_seconds)
    }

    if ($null -eq $remoteTasks) {
        return $null
    }

    $resolved = @($remoteTasks | Where-Object { [string]$_.task_id -eq [string]$TaskId } | Select-Object -First 1)
    if (@($resolved).Count -eq 0) {
        return $null
    }

    return (Convert-RemoteTaskToTodTask -Task $resolved[0])
}

function Convert-JsonDeserializedValue {
    param([AllowNull()]$Value)

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [System.Collections.IDictionary]) {
        $map = [ordered]@{}
        foreach ($key in @($Value.Keys)) {
            $existingKey = $null
            foreach ($candidateKey in @($map.Keys)) {
                if ([string]::Equals([string]$candidateKey, [string]$key, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $existingKey = [string]$candidateKey
                    break
                }
            }

            if ($null -ne $existingKey) {
                $null = $map.Remove($existingKey)
            }

            $map[[string]$key] = Convert-JsonDeserializedValue -Value $Value[$key]
        }
        return [pscustomobject]$map
    }

    if (($Value -is [System.Collections.IEnumerable]) -and -not ($Value -is [string])) {
        return @($Value | ForEach-Object { Convert-JsonDeserializedValue -Value $_ })
    }

    return $Value
}

function ConvertFrom-JsonCaseInsensitiveSafe {
    param([Parameter(Mandatory = $true)][string]$Text)

    try {
        return ($Text | ConvertFrom-Json)
    }
    catch {
        Add-Type -AssemblyName System.Web.Extensions -ErrorAction Stop
        $serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
        return Convert-JsonDeserializedValue -Value ($serializer.DeserializeObject($Text))
    }
}

function Get-BridgeRequestPacket {
    if (-not (Test-Path -Path $bridgeRequestPacketPath -PathType Leaf)) {
        throw "Bridge request packet not found at $bridgeRequestPacketPath"
    }

    try {
        $payload = ConvertFrom-JsonCaseInsensitiveSafe -Text (Get-Content -Path $bridgeRequestPacketPath -Raw)
    }
    catch {
        throw "Bridge request packet at '$bridgeRequestPacketPath' is not valid JSON: $([string]$_.Exception.Message)"
    }

    return [pscustomobject]@{
        path = $bridgeRequestPacketPath
        payload = $payload
    }
}

function Resolve-BridgeRequestAction {
    param([Parameter(Mandatory = $true)]$Request)

    $actionName = ""
    if ($Request.PSObject.Properties["tod_action"] -and -not [string]::IsNullOrWhiteSpace([string]$Request.tod_action)) {
        $actionName = [string]$Request.tod_action
    }
    elseif ($Request.PSObject.Properties["action"] -and -not [string]::IsNullOrWhiteSpace([string]$Request.action)) {
        $actionName = [string]$Request.action
    }

    if ([string]::Equals($actionName, 'run-bridge-request', [System.StringComparison]::OrdinalIgnoreCase)) {
        $nestedAction = ''
        if ($Request.PSObject.Properties['tod_action_args'] -and $null -ne $Request.tod_action_args -and $Request.tod_action_args.PSObject.Properties['Action'] -and -not [string]::IsNullOrWhiteSpace([string]$Request.tod_action_args.Action)) {
            $nestedAction = [string]$Request.tod_action_args.Action
        }
        elseif ($Request.PSObject.Properties['tod_bridge_request'] -and $null -ne $Request.tod_bridge_request -and $Request.tod_bridge_request.PSObject.Properties['action'] -and -not [string]::IsNullOrWhiteSpace([string]$Request.tod_bridge_request.action)) {
            $nestedAction = [string]$Request.tod_bridge_request.action
        }
        elseif ($Request.PSObject.Properties['tod_bridge_request'] -and $null -ne $Request.tod_bridge_request -and $Request.tod_bridge_request.PSObject.Properties['Action'] -and -not [string]::IsNullOrWhiteSpace([string]$Request.tod_bridge_request.Action)) {
            $nestedAction = [string]$Request.tod_bridge_request.Action
        }
        elseif ($Request.PSObject.Properties['action'] -and -not [string]::IsNullOrWhiteSpace([string]$Request.action) -and -not [string]::Equals([string]$Request.action, 'run-bridge-request', [System.StringComparison]::OrdinalIgnoreCase)) {
            $nestedAction = [string]$Request.action
        }

        if (-not [string]::IsNullOrWhiteSpace($nestedAction)) {
            $actionName = $nestedAction
        }
    }

    if ([string]::IsNullOrWhiteSpace($actionName)) {
        throw "Bridge request is missing tod_action/action and cannot be executed."
    }

    return $actionName.Trim()
}

function Resolve-CodexHandoffRequest {
    param(
        [string]$RequestedRequestId,
        [string]$RequestedTaskId
    )

    $packet = Get-BridgeRequestPacket
    $request = $packet.payload
    $requestId = if ($request.PSObject.Properties['request_id']) { [string]$request.request_id } else { '' }
    $taskId = if ($request.PSObject.Properties['task_id']) { [string]$request.task_id } else { '' }
    $actionName = Resolve-BridgeRequestAction -Request $request

    if (-not [string]::Equals($actionName, 'codex_handoff', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Bridge request at '$([string]$packet.path)' resolves to TOD action '$actionName', not 'codex_handoff'."
    }
    if (-not [string]::IsNullOrWhiteSpace($RequestedRequestId)) {
        $requestMatches = [string]::Equals($requestId, $RequestedRequestId, [System.StringComparison]::Ordinal) -or [string]::Equals($taskId, $RequestedRequestId, [System.StringComparison]::Ordinal)
        if (-not $requestMatches) {
            throw "Latest codex handoff request '$requestId' at '$([string]$packet.path)' does not match requested request id '$RequestedRequestId'."
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($RequestedTaskId)) {
        $taskMatches = [string]::Equals($taskId, $RequestedTaskId, [System.StringComparison]::Ordinal) -or [string]::Equals($requestId, $RequestedTaskId, [System.StringComparison]::Ordinal)
        if (-not $taskMatches) {
            throw "Latest codex handoff task '$taskId' at '$([string]$packet.path)' does not match requested task id '$RequestedTaskId'."
        }
    }

    return [pscustomobject]@{
        path = [string]$packet.path
        payload = $request
        request_id = $requestId
        task_id = $taskId
        objective_id = if ($request.PSObject.Properties['objective_id']) { [string]$request.objective_id } else { '' }
        action = $actionName
    }
}

function Sync-CodexHandoffTaskMirror {
    param([Parameter(Mandatory = $true)]$Request)

    $resolvedTaskId = if ($Request.PSObject.Properties['task_id'] -and -not [string]::IsNullOrWhiteSpace([string]$Request.task_id)) {
        [string]$Request.task_id
    }
    elseif ($Request.PSObject.Properties['request_id'] -and -not [string]::IsNullOrWhiteSpace([string]$Request.request_id)) {
        [string]$Request.request_id
    }
    else {
        ''
    }

    if ([string]::IsNullOrWhiteSpace($resolvedTaskId)) {
        throw 'codex_handoff request is missing both task_id and request_id.'
    }

    $resolvedObjectiveId = if ($Request.PSObject.Properties['objective_id'] -and -not [string]::IsNullOrWhiteSpace([string]$Request.objective_id)) {
        [string]$Request.objective_id
    }
    else {
        ''
    }

    $resolvedTitle = ''
    if ($Request.PSObject.Properties['title'] -and -not [string]::IsNullOrWhiteSpace([string]$Request.title)) {
        $resolvedTitle = [string]$Request.title
    }
    elseif ($Request.PSObject.Properties['metadata_json'] -and $null -ne $Request.metadata_json -and $Request.metadata_json.PSObject.Properties['task_title'] -and -not [string]::IsNullOrWhiteSpace([string]$Request.metadata_json.task_title)) {
        $resolvedTitle = [string]$Request.metadata_json.task_title
    }
    if ([string]::IsNullOrWhiteSpace($resolvedTitle)) {
        $resolvedTitle = "Bridge task $resolvedTaskId"
    }

    $resolvedScope = ''
    if ($Request.PSObject.Properties['scope'] -and -not [string]::IsNullOrWhiteSpace([string]$Request.scope)) {
        $resolvedScope = [string]$Request.scope
    }
    elseif ($Request.PSObject.Properties['summary'] -and -not [string]::IsNullOrWhiteSpace([string]$Request.summary)) {
        $resolvedScope = [string]$Request.summary
    }
    elseif ($Request.PSObject.Properties['requested_outcome'] -and -not [string]::IsNullOrWhiteSpace([string]$Request.requested_outcome)) {
        $resolvedScope = [string]$Request.requested_outcome
    }
    if ([string]::IsNullOrWhiteSpace($resolvedScope)) {
        $resolvedScope = 'Synchronized from codex handoff bridge request.'
    }

    $acceptanceCriteria = @()
    if ($Request.PSObject.Properties['metadata_json'] -and $null -ne $Request.metadata_json -and $Request.metadata_json.PSObject.Properties['task_acceptance_criteria'] -and -not [string]::IsNullOrWhiteSpace([string]$Request.metadata_json.task_acceptance_criteria)) {
        $acceptanceCriteria = @([string]$Request.metadata_json.task_acceptance_criteria)
    }

    $updatedAt = Get-UtcNow
    $state = Load-State
    if (-not $state.PSObject.Properties['tasks']) {
        $state | Add-Member -NotePropertyName tasks -NotePropertyValue @() -Force
    }

    $existing = @($state.tasks | Where-Object {
            ([string]$_.id -eq $resolvedTaskId) -or
            (($_.PSObject.Properties['remote_task_id']) -and ([string]$_.remote_task_id -eq $resolvedTaskId))
        } | Select-Object -First 1)

    $changed = $false
    $created = $false
    if (@($existing).Count -eq 0) {
        $task = [pscustomobject]@{
            id = $resolvedTaskId
            remote_task_id = $resolvedTaskId
            objective_id = $resolvedObjectiveId
            title = $resolvedTitle
            type = 'programming'
            task_category = 'bridge_runtime'
            scope = $resolvedScope
            dependencies = @()
            acceptance_criteria = @($acceptanceCriteria)
            status = 'in_progress'
            assigned_executor = (Resolve-PreferredAssignedExecutor -TaskCategory 'bridge_runtime' -State $state -Task ([pscustomobject]@{ title = $resolvedTitle; scope = $resolvedScope }))
            source = 'bridge_runtime_sync'
            correlation_id = if ($Request.PSObject.Properties['correlation_id']) { [string]$Request.correlation_id } else { $resolvedTaskId }
            created_at = $updatedAt
            updated_at = $updatedAt
        }
        $state.tasks = @($state.tasks) + @($task)
        $changed = $true
        $created = $true
    }
    else {
        $task = $existing[0]
        if (-not [string]::Equals([string]$task.objective_id, $resolvedObjectiveId, [System.StringComparison]::Ordinal)) {
            $task.objective_id = $resolvedObjectiveId
            $changed = $true
        }
        if (-not [string]::Equals([string]$task.title, $resolvedTitle, [System.StringComparison]::Ordinal)) {
            $task.title = $resolvedTitle
            $changed = $true
        }
        if (-not [string]::Equals([string]$task.scope, $resolvedScope, [System.StringComparison]::Ordinal)) {
            $task.scope = $resolvedScope
            $changed = $true
        }
        if (-not [string]::Equals([string]$task.status, 'in_progress', [System.StringComparison]::OrdinalIgnoreCase)) {
            $task.status = 'in_progress'
            $changed = $true
        }
        if (-not $task.PSObject.Properties['remote_task_id'] -or -not [string]::Equals([string]$task.remote_task_id, $resolvedTaskId, [System.StringComparison]::Ordinal)) {
            $task | Add-Member -NotePropertyName remote_task_id -NotePropertyValue $resolvedTaskId -Force
            $changed = $true
        }
        if (-not $task.PSObject.Properties['task_category'] -or -not [string]::Equals([string]$task.task_category, 'bridge_runtime', [System.StringComparison]::Ordinal)) {
            $task | Add-Member -NotePropertyName task_category -NotePropertyValue 'bridge_runtime' -Force
            $changed = $true
        }
        if (-not $task.PSObject.Properties['source'] -or -not [string]::Equals([string]$task.source, 'bridge_runtime_sync', [System.StringComparison]::Ordinal)) {
            $task | Add-Member -NotePropertyName source -NotePropertyValue 'bridge_runtime_sync' -Force
            $changed = $true
        }
        $correlationId = if ($Request.PSObject.Properties['correlation_id']) { [string]$Request.correlation_id } else { $resolvedTaskId }
        if (-not $task.PSObject.Properties['correlation_id'] -or -not [string]::Equals([string]$task.correlation_id, $correlationId, [System.StringComparison]::Ordinal)) {
            $task | Add-Member -NotePropertyName correlation_id -NotePropertyValue $correlationId -Force
            $changed = $true
        }
        $task.acceptance_criteria = @($acceptanceCriteria)
        if ($changed) {
            $task.updated_at = $updatedAt
        }
    }

    if ($changed) {
        Save-State -State $state
    }

    return [pscustomobject]@{
        changed = $changed
        created = $created
        task_id = $resolvedTaskId
        objective_id = $resolvedObjectiveId
        reason = if ($created) { 'task_mirror_created' } elseif ($changed) { 'task_mirror_updated' } else { 'already_current' }
    }
}

function Write-CodexHandoffTaskPackage {
    param([Parameter(Mandatory = $true)]$Request)

    Assert-Exists -Path $templatePath -Name 'Prompt template'

    $taskId = if ($Request.PSObject.Properties['task_id'] -and -not [string]::IsNullOrWhiteSpace([string]$Request.task_id)) { [string]$Request.task_id } else { [string]$Request.request_id }
    if ([string]::IsNullOrWhiteSpace($taskId)) {
        throw 'codex_handoff request is missing both task_id and request_id for package generation.'
    }

    $objectiveId = if ($Request.PSObject.Properties['objective_id'] -and -not [string]::IsNullOrWhiteSpace([string]$Request.objective_id)) { [string]$Request.objective_id } else { '' }
    $objectiveTitle = if ($Request.PSObject.Properties['metadata_json'] -and $null -ne $Request.metadata_json -and $Request.metadata_json.PSObject.Properties['objective_title'] -and -not [string]::IsNullOrWhiteSpace([string]$Request.metadata_json.objective_title)) { [string]$Request.metadata_json.objective_title } else { $objectiveId }
    $taskTitle = if ($Request.PSObject.Properties['title'] -and -not [string]::IsNullOrWhiteSpace([string]$Request.title)) { [string]$Request.title } elseif ($Request.PSObject.Properties['metadata_json'] -and $null -ne $Request.metadata_json -and $Request.metadata_json.PSObject.Properties['task_title'] -and -not [string]::IsNullOrWhiteSpace([string]$Request.metadata_json.task_title)) { [string]$Request.metadata_json.task_title } else { "Bridge task $taskId" }
    $taskScope = if ($Request.PSObject.Properties['scope'] -and -not [string]::IsNullOrWhiteSpace([string]$Request.scope)) { [string]$Request.scope } elseif ($Request.PSObject.Properties['summary'] -and -not [string]::IsNullOrWhiteSpace([string]$Request.summary)) { [string]$Request.summary } elseif ($Request.PSObject.Properties['requested_outcome'] -and -not [string]::IsNullOrWhiteSpace([string]$Request.requested_outcome)) { [string]$Request.requested_outcome } else { 'Implement the synchronized codex handoff request.' }
    $acceptanceCriteria = if ($Request.PSObject.Properties['metadata_json'] -and $null -ne $Request.metadata_json -and $Request.metadata_json.PSObject.Properties['task_acceptance_criteria'] -and -not [string]::IsNullOrWhiteSpace([string]$Request.metadata_json.task_acceptance_criteria)) { [string]$Request.metadata_json.task_acceptance_criteria } else { '' }

    $template = Get-Content -Path $templatePath -Raw
    $rendered = $template
    $rendered = $rendered.Replace('{{OBJECTIVE_ID}}', $objectiveId)
    $rendered = $rendered.Replace('{{OBJECTIVE_TITLE}}', $objectiveTitle)
    $rendered = $rendered.Replace('{{OBJECTIVE_DESCRIPTION}}', $taskScope)
    $rendered = $rendered.Replace('{{OBJECTIVE_PRIORITY}}', 'high')
    $rendered = $rendered.Replace('{{OBJECTIVE_CONSTRAINTS}}', 'boundary_mode=soft, execution_scope=bounded_development')
    $rendered = $rendered.Replace('{{OBJECTIVE_SUCCESS_CRITERIA}}', $acceptanceCriteria)
    $rendered = $rendered.Replace('{{TASK_ID}}', $taskId)
    $rendered = $rendered.Replace('{{TASK_TITLE}}', $taskTitle)
    $rendered = $rendered.Replace('{{TASK_TYPE}}', 'programming')
    $rendered = $rendered.Replace('{{TASK_SCOPE}}', $taskScope)
    $rendered = $rendered.Replace('{{TASK_DEPENDENCIES}}', '')
    $rendered = $rendered.Replace('{{TASK_ACCEPTANCE_CRITERIA}}', $acceptanceCriteria)
    $taskAssignedExecutor = if ($Request.PSObject.Properties['metadata_json'] -and $null -ne $Request.metadata_json -and $Request.metadata_json.PSObject.Properties['assigned_executor'] -and -not [string]::IsNullOrWhiteSpace([string]$Request.metadata_json.assigned_executor)) { [string]$Request.metadata_json.assigned_executor } else { 'codex' }
    $rendered = $rendered.Replace('{{TASK_ASSIGNED_EXECUTOR}}', $taskAssignedExecutor)
    if ($Request.PSObject.Properties['metadata_json'] -and $null -ne $Request.metadata_json -and $Request.metadata_json.PSObject.Properties['materialization'] -and $null -ne $Request.metadata_json.materialization) {
        $materializationBlock = Convert-BoundedEditMaterializationToPromptBlock -Materialization $Request.metadata_json.materialization
        if (-not [string]::IsNullOrWhiteSpace($materializationBlock)) {
            $rendered = ($rendered.TrimEnd() + "`n`n" + $materializationBlock + "`n")
        }
    }

    if (-not (Test-Path -Path $promptOutDir)) {
        New-Item -ItemType Directory -Path $promptOutDir -Force | Out-Null
    }

    $outPath = Join-Path $promptOutDir ("{0}.md" -f $taskId)
    Set-Content -Path $outPath -Value $rendered
    return $outPath
}

function Ensure-ChatTaskObjectiveRecord {
    param(
        [string]$ObjectiveId,
        [string]$Title,
        [string]$Description,
        [string]$Priority,
        [string]$SuccessCriteria
    )

    $state = Load-State
    if (-not $state.PSObject.Properties['objectives']) {
        $state | Add-Member -NotePropertyName objectives -NotePropertyValue @() -Force
    }

    $resolvedObjectiveId = if (-not [string]::IsNullOrWhiteSpace($ObjectiveId)) { [string]$ObjectiveId } else { New-Id -Prefix 'OBJ' -Count $state.objectives.Count }
    $existing = @($state.objectives | Where-Object { [string]$_.id -eq $resolvedObjectiveId } | Select-Object -First 1)
    if (@($existing).Count -gt 0) {
        return $existing[0]
    }

    $now = Get-UtcNow
    $createdObjective = [pscustomobject]@{
        id = $resolvedObjectiveId
        title = if (-not [string]::IsNullOrWhiteSpace($Title)) { [string]$Title } else { "Chat objective $resolvedObjectiveId" }
        description = if (-not [string]::IsNullOrWhiteSpace($Description)) { [string]$Description } else { 'Objective created from TOD chat task dispatch.' }
        priority = if (-not [string]::IsNullOrWhiteSpace($Priority)) { [string]$Priority } else { 'high' }
        constraints = @('source=chat_task_request', 'execution_scope=bounded_local_execution')
        success_criteria = [string[]](Split-List -Value $(if (-not [string]::IsNullOrWhiteSpace($SuccessCriteria)) { $SuccessCriteria } else { 'Publish bounded execution evidence and validation output.' }))
        status = 'in_progress'
        created_at = $now
        updated_at = $now
    }

    $state.objectives += $createdObjective
    Add-Journal -State $state -Actor 'tod' -ActionName 'add_objective_chat_dispatch' -EntityType 'objective' -EntityId $resolvedObjectiveId -Payload $createdObjective
    Save-State -State $state
    return $createdObjective
}

function Invoke-TodSelfAction {
    param(
        [Parameter(Mandatory = $true)][string]$ActionName,
        [hashtable]$Arguments = @{}
    )

    $scriptPath = $PSCommandPath
    if ([string]::IsNullOrWhiteSpace($scriptPath)) {
        $scriptPath = $MyInvocation.MyCommand.Path
    }
    if ([string]::IsNullOrWhiteSpace($scriptPath)) {
        throw 'Unable to resolve TOD.ps1 path for nested action execution.'
    }

    $invokeArgs = @{ Action = $ActionName }
    foreach ($entry in $Arguments.GetEnumerator()) {
        if ($null -eq $entry.Value) {
            continue
        }
        if ($entry.Value -is [string] -and [string]::IsNullOrWhiteSpace([string]$entry.Value)) {
            continue
        }
        $invokeArgs[$entry.Key] = $entry.Value
    }

    $raw = & $scriptPath @invokeArgs 2>&1
    return [pscustomobject]@{
        action = $ActionName
        output = [string]($raw | Out-String)
    }
}

function Invoke-TodSelfJsonAction {
    param(
        [Parameter(Mandatory = $true)][string]$ActionName,
        [hashtable]$Arguments = @{}
    )

    $invocation = Invoke-TodSelfAction -ActionName $ActionName -Arguments $Arguments
    $payload = $null
    $rawText = [string]$invocation.output
    try {
        $payload = ($rawText | ConvertFrom-Json)
    }
    catch {
        $lines = @($rawText -split "`r?`n")
        for ($index = $lines.Length - 1; $index -ge 0; $index--) {
            if ($lines[$index].Trim() -ne '{') {
                continue
            }

            $candidate = (($lines[$index..($lines.Length - 1)]) -join [Environment]::NewLine).Trim()
            if ([string]::IsNullOrWhiteSpace($candidate)) {
                continue
            }

            try {
                $payload = ($candidate | ConvertFrom-Json)
                break
            }
            catch {
            }
        }
    }

    if ($null -eq $payload) {
        throw ("TOD nested action '{0}' did not return JSON. Output: {1}" -f $ActionName, $rawText)
    }

    return [pscustomobject]@{
        action = $ActionName
        payload = $payload
        output = $rawText
    }
}

function Get-DirectChatLiveRequestPaths {
    $paths = New-Object System.Collections.Generic.List[string]
    foreach ($sharedRoot in @(Get-TodExecutionSharedRoots)) {
        $candidatePath = Join-Path $sharedRoot 'MIM_TOD_TASK_REQUEST.latest.json'
        if (-not $paths.Contains($candidatePath)) {
            [void]$paths.Add($candidatePath)
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($bridgeRequestPacketPath) -and -not $paths.Contains($bridgeRequestPacketPath)) {
        [void]$paths.Add($bridgeRequestPacketPath)
    }

    return [string[]]@($paths)
}

function Read-JsonFileSafeLocal {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -Path $Path)) {
        return $null
    }

    try {
        return (Get-Content -Path $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Archive-SupersededDirectChatRequest {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Payload,
        [Parameter(Mandatory = $true)][string]$Reason,
        [string]$SupersededByTaskId,
        [string]$SupersededByRequestId,
        [string]$SupersededByObjectiveId
    )

    $directory = Split-Path -Parent $Path
    if ([string]::IsNullOrWhiteSpace($directory)) {
        return ''
    }

    $artifactName = [System.IO.Path]::GetFileName($Path)
    $supersededRoot = Join-Path $directory 'superseded'
    $artifactRoot = Join-Path $supersededRoot $artifactName
    if (-not (Test-Path -Path $artifactRoot)) {
        New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null
    }

    $stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ')
    $requestId = if ($Payload.PSObject.Properties['request_id']) { [string]$Payload.request_id } else { '' }
    $safeRequestId = if ([string]::IsNullOrWhiteSpace($requestId)) { 'unknown-request' } else { ($requestId -replace '[^A-Za-z0-9_.-]+', '-') }
    $record = [ordered]@{
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        reason_code = $Reason
        target_path = $Path
        superseded_by_task_id = $SupersededByTaskId
        superseded_by_request_id = $SupersededByRequestId
        superseded_by_objective_id = $SupersededByObjectiveId
        payload = $Payload
    }

    $recordPath = Join-Path $artifactRoot ('{0}-{1}.superseded.json' -f $stamp, $safeRequestId)
    Write-TodExecutionJsonAtomically -Path $recordPath -Payload $record
    return $recordPath
}

function Get-ActiveDirectChatLaneSnapshot {
    $requestPaths = @(Get-DirectChatLiveRequestPaths)
    $selectedPayload = $null
    $selectedRequestId = ''
    $matchedPaths = New-Object System.Collections.Generic.List[string]

    foreach ($candidatePath in $requestPaths) {
        $payload = Read-JsonFileSafeLocal -Path $candidatePath
        if ($null -eq $payload) {
            continue
        }
        $todAction = if ($payload.PSObject.Properties['tod_action']) { [string]$payload.tod_action } else { '' }
        if (-not [string]::Equals($todAction, 'execute-chat-task', [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $requestId = if ($payload.PSObject.Properties['request_id']) { [string]$payload.request_id } else { '' }
        if ($null -eq $selectedPayload) {
            $selectedPayload = $payload
            $selectedRequestId = $requestId
            [void]$matchedPaths.Add([string]$candidatePath)
            continue
        }

        if ([string]::Equals($selectedRequestId, $requestId, [System.StringComparison]::Ordinal)) {
            [void]$matchedPaths.Add([string]$candidatePath)
        }
    }

    if ($null -eq $selectedPayload) {
        return $null
    }

    return [pscustomobject]@{
        payload = $selectedPayload
        request_id = $selectedRequestId
        task_id = if ($selectedPayload.PSObject.Properties['task_id']) { [string]$selectedPayload.task_id } else { '' }
        objective_id = if ($selectedPayload.PSObject.Properties['objective_id']) { [string]$selectedPayload.objective_id } else { '' }
        request_paths = [string[]]@($matchedPaths)
    }
}

function Supersede-ActiveDirectChatLane {
    param(
        $ExistingLane,
        [Parameter(Mandatory = $true)][string]$NewObjectiveId,
        [Parameter(Mandatory = $true)][string]$NewTaskId,
        [Parameter(Mandatory = $true)][string]$NewRequestId,
        [Parameter(Mandatory = $true)][string]$NewCorrelationId
    )

    if ($null -eq $ExistingLane) {
        return $null
    }

    $existingRequestId = if ($ExistingLane.PSObject.Properties['request_id']) { [string]$ExistingLane.request_id } else { '' }
    $existingTaskId = if ($ExistingLane.PSObject.Properties['task_id']) { [string]$ExistingLane.task_id } else { '' }
    if ([string]::IsNullOrWhiteSpace($existingRequestId) -and [string]::IsNullOrWhiteSpace($existingTaskId)) {
        return $null
    }
    if ([string]::Equals($existingRequestId, $NewRequestId, [System.StringComparison]::OrdinalIgnoreCase) -or [string]::Equals($existingTaskId, $NewTaskId, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $null
    }

    $reason = 'superseded_by_operator_objective'
    $archivedPaths = New-Object System.Collections.Generic.List[string]
    foreach ($requestPath in @($ExistingLane.request_paths)) {
        if ([string]::IsNullOrWhiteSpace([string]$requestPath) -or -not (Test-Path -Path ([string]$requestPath))) {
            continue
        }

        $payload = Read-JsonFileSafeLocal -Path ([string]$requestPath)
        if ($null -eq $payload) {
            continue
        }
        $requestId = if ($payload.PSObject.Properties['request_id']) { [string]$payload.request_id } else { '' }
        if (-not [string]::Equals($requestId, $existingRequestId, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $archivedPath = Archive-SupersededDirectChatRequest -Path ([string]$requestPath) -Payload $payload -Reason $reason -SupersededByTaskId $NewTaskId -SupersededByRequestId $NewRequestId -SupersededByObjectiveId $NewObjectiveId
        if (-not [string]::IsNullOrWhiteSpace($archivedPath)) {
            [void]$archivedPaths.Add($archivedPath)
        }
    }

    $state = Load-State
    $journalAdded = $false
    $supersededTask = @($state.tasks | Where-Object { [string]$_.id -eq $existingTaskId } | Select-Object -First 1)
    if (@($supersededTask).Count -gt 0) {
        $supersededTask[0].status = 'superseded'
        $supersededTask[0] | Add-Member -NotePropertyName supersession_reason -NotePropertyValue $reason -Force
        $supersededTask[0] | Add-Member -NotePropertyName superseded_by_task_id -NotePropertyValue $NewTaskId -Force
        $supersededTask[0] | Add-Member -NotePropertyName superseded_by_request_id -NotePropertyValue $NewRequestId -Force
        $supersededTask[0] | Add-Member -NotePropertyName superseded_by_objective_id -NotePropertyValue $NewObjectiveId -Force
        $supersededTask[0] | Add-Member -NotePropertyName superseded_at -NotePropertyValue (Get-UtcNow) -Force
        $supersededTask[0].updated_at = Get-UtcNow
        Add-Journal -State $state -Actor 'tod' -ActionName 'supersede_direct_chat_task' -EntityType 'task' -EntityId $existingTaskId -Payload ([pscustomobject]@{
                reason = $reason
                superseded_by_task_id = $NewTaskId
                superseded_by_request_id = $NewRequestId
                superseded_by_objective_id = $NewObjectiveId
            })
        $journalAdded = $true
    }

    if ($journalAdded) {
        Save-State -State $state
    }

    return [pscustomobject]@{
        reason = $reason
        superseded_request_id = $existingRequestId
        superseded_task_id = $existingTaskId
        superseded_objective_id = if ($ExistingLane.PSObject.Properties['objective_id']) { [string]$ExistingLane.objective_id } else { '' }
        archived_paths = [string[]]@($archivedPaths)
    }
}

function Invoke-ExecuteChatTaskRequest {
    param(
        [string]$ObjectiveId,
        [string]$TaskId,
        [string]$RequestId,
        [string]$Title,
        [string]$Description,
        [string]$Priority,
        [string]$Scope,
        [string]$AcceptanceCriteria,
        [string]$SuccessCriteria,
        [string]$AssignedExecutor,
        [string]$TaskCategory,
        [string]$CorrelationId,
        [string]$TargetFile,
        [string]$ResolvedConfigPath,
        [string]$ResolvedStatePath,
        [ValidateSet('sync', 'async')][string]$ExecutionMode = 'sync'
    )

    if ([string]::IsNullOrWhiteSpace($TaskId)) { throw '-TaskId is required' }
    if ([string]::IsNullOrWhiteSpace($Scope)) { throw '-Scope is required' }

    $resolvedAcceptance = if (-not [string]::IsNullOrWhiteSpace($AcceptanceCriteria)) { [string]$AcceptanceCriteria } elseif (-not [string]::IsNullOrWhiteSpace($SuccessCriteria)) { [string]$SuccessCriteria } else { 'Publish bounded execution evidence and validation output.' }
    $resolvedDescription = if (-not [string]::IsNullOrWhiteSpace($Description)) { [string]$Description } else { [string]$Scope }
    $objective = Ensure-ChatTaskObjectiveRecord -ObjectiveId $ObjectiveId -Title $Title -Description $resolvedDescription -Priority $Priority -SuccessCriteria $SuccessCriteria
    $resolvedRequestId = if (-not [string]::IsNullOrWhiteSpace($RequestId)) { [string]$RequestId } else { [string]$TaskId }
    $resolvedCorrelationId = if (-not [string]::IsNullOrWhiteSpace($CorrelationId)) { [string]$CorrelationId } elseif (-not [string]::IsNullOrWhiteSpace($resolvedRequestId)) { [string]$resolvedRequestId } else { [string]$TaskId }
    $supersededLane = Supersede-ActiveDirectChatLane -ExistingLane (Get-ActiveDirectChatLaneSnapshot) -NewObjectiveId ([string]$objective.id) -NewTaskId ([string]$TaskId) -NewRequestId $resolvedRequestId -NewCorrelationId $resolvedCorrelationId

    $request = [pscustomobject]@{
        request_id = $resolvedRequestId
        task_id = [string]$TaskId
        objective_id = [string]$objective.id
        correlation_id = $resolvedCorrelationId
        target = 'TOD'
        tod_action = 'execute-chat-task'
        generated_at = Get-UtcNow
        title = if (-not [string]::IsNullOrWhiteSpace($Title)) { [string]$Title } else { "Chat task $TaskId" }
        scope = [string]$Scope
        summary = $resolvedDescription
        requested_outcome = if (-not [string]::IsNullOrWhiteSpace($SuccessCriteria)) { [string]$SuccessCriteria } else { $resolvedAcceptance }
        metadata_json = [pscustomobject]@{
            objective_title = [string]$objective.title
            task_title = if (-not [string]::IsNullOrWhiteSpace($Title)) { [string]$Title } else { "Chat task $TaskId" }
            task_acceptance_criteria = $resolvedAcceptance
            task_category = if (-not [string]::IsNullOrWhiteSpace($TaskCategory)) { [string]$TaskCategory } else { 'chat_execution' }
            assigned_executor = if (-not [string]::IsNullOrWhiteSpace($AssignedExecutor)) { [string]$AssignedExecutor } else { 'local' }
            source = 'direct_chat'
        }
    }

    $requestedTaskCategory = if (-not [string]::IsNullOrWhiteSpace($TaskCategory)) { [string]$TaskCategory } else { 'chat_execution' }
    $intakePriority = Resolve-TodIntakePriority -Source 'operator_chat' -TaskCategory $requestedTaskCategory -Text (($Title, $Scope, $Description) -join "`n")
    $intakeInterruptPolicy = if ($intakePriority -in @('emergency_stop', 'operator_cancel', 'operator_admin_repair')) { 'interrupt_safe' } else { 'no_interrupt' }
    $intakePayloadHash = Get-TodIntakePayloadHash -Payload ([pscustomobject]@{
            request_id = $resolvedRequestId
            task_id = [string]$TaskId
            objective_id = [string]$objective.id
            title = [string]$request.title
            scope = [string]$Scope
            summary = [string]$resolvedDescription
            requested_outcome = [string]$request.requested_outcome
            task_category = $requestedTaskCategory
            assigned_executor = if (-not [string]::IsNullOrWhiteSpace($AssignedExecutor)) { [string]$AssignedExecutor } else { 'local' }
        })
    $intakeItem = New-TodIntakeItem -RequestId $resolvedRequestId -TaskId ([string]$TaskId) -ObjectiveId ([string]$objective.id) -Source 'operator_chat' -Priority $intakePriority -InterruptPolicy $intakeInterruptPolicy -RelationToActiveTask 'new' -Title ([string]$request.title) -Summary ([string]$resolvedDescription) -TaskCategory $requestedTaskCategory -PayloadHash $intakePayloadHash
    $intakeArbitration = Register-TodIntakeItem -Item $intakeItem
    if ([string]$intakeArbitration.decision -in @('queue', 'defer', 'reject_duplicate', 'merge_with_active', 'blocked_needs_operator')) {
        $intakeEventType = if ([string]::Equals([string]$intakeArbitration.decision, 'reject_duplicate', [System.StringComparison]::OrdinalIgnoreCase)) { 'intake_rejected_duplicate' } else { 'intake_queued' }
        Publish-TodActivityEvent -EventType $intakeEventType -ObjectiveId ([string]$objective.id) -TaskId ([string]$TaskId) -RequestId $resolvedRequestId -CorrelationId $resolvedCorrelationId -Title ([string]$request.title) -Status ([string]$intakeArbitration.decision) -Message ('TOD intake arbitration decision: {0}. {1}' -f [string]$intakeArbitration.decision, [string]$intakeArbitration.reason) -Details ([ordered]@{
                decision = [string]$intakeArbitration.decision
                reason = [string]$intakeArbitration.reason
                relation_to_active_task = [string]$intakeArbitration.relation_to_active_task
                active_task_id = if ($intakeArbitration.active_lane -and $intakeArbitration.active_lane.PSObject.Properties['task_id']) { [string]$intakeArbitration.active_lane.task_id } else { '' }
            }) -Source 'tod.execute-chat-task' -Surface 'tod-chat' -Summary ([string]$resolvedDescription) -CurrentAction 'Recorded the operator request in TOD intake arbitration without overwriting the active execution lane.' | Out-Null

        $activityTypes = @($intakeEventType, 'intake_arbitrated')
        return [pscustomobject]@{
            request_id = $resolvedRequestId
            task_id = [string]$TaskId
            objective_id = [string]$objective.id
            correlation_id = $resolvedCorrelationId
            request_artifact_path = ''
            request_artifact_paths = @()
            activity_event_types = @($activityTypes)
            reason_codes = @('intake_arbitration_' + [string]$intakeArbitration.decision)
            selected_task = [pscustomobject]@{
                task_id = if ($intakeArbitration.active_lane -and $intakeArbitration.active_lane.PSObject.Properties['task_id']) { [string]$intakeArbitration.active_lane.task_id } else { '' }
                objective_id = if ($intakeArbitration.active_lane -and $intakeArbitration.active_lane.PSObject.Properties['objective_id']) { [string]$intakeArbitration.active_lane.objective_id } else { '' }
                reason_code = 'active_execution_lane_preserved'
            }
            claimed_task = [pscustomobject]@{
                task_id = if ($intakeArbitration.active_lane -and $intakeArbitration.active_lane.PSObject.Properties['task_id']) { [string]$intakeArbitration.active_lane.task_id } else { '' }
                objective_id = if ($intakeArbitration.active_lane -and $intakeArbitration.active_lane.PSObject.Properties['objective_id']) { [string]$intakeArbitration.active_lane.objective_id } else { '' }
                assigned_executor = if ($intakeArbitration.active_lane -and $intakeArbitration.active_lane.PSObject.Properties['source']) { [string]$intakeArbitration.active_lane.source } else { '' }
                reason_code = 'active_execution_lane_preserved'
            }
            intake_arbitration = $intakeArbitration.arbitration
            intake_queue = $intakeArbitration.queue
            executor_classification = $null
            superseded_claim = $null
            task_mirror = $null
            package_path = ''
            run_task = [pscustomobject]@{
                task_id = [string]$TaskId
                decision = [string]$intakeArbitration.decision
                blocked = [string]::Equals([string]$intakeArbitration.decision, 'blocked_needs_operator', [System.StringComparison]::OrdinalIgnoreCase)
                accepted = (-not ([string]$intakeArbitration.decision -in @('reject_duplicate', 'blocked_needs_operator')))
                execution_status = [string]$intakeArbitration.decision
                summary = ('TOD intake arbitration stored the request as {0}; active task identity was preserved.' -f [string]$intakeArbitration.decision)
                intake_arbitration = $intakeArbitration.arbitration
            }
            run_task_output = ''
            execution_mode = $ExecutionMode
        }
    }

    $requestArtifactPaths = New-Object System.Collections.Generic.List[string]
    $activityEvents = New-Object System.Collections.Generic.List[object]
    foreach ($sharedRoot in @(Get-TodExecutionSharedRoots)) {
        $requestPath = Join-Path $sharedRoot 'MIM_TOD_TASK_REQUEST.latest.json'
        Write-TodExecutionJsonAtomically -Path $requestPath -Payload $request
        [void]$requestArtifactPaths.Add($requestPath)
    }
    Write-TodExecutionJsonAtomically -Path $bridgeRequestPacketPath -Payload $request
    [void]$requestArtifactPaths.Add($bridgeRequestPacketPath)

    if ($null -ne $supersededLane) {
        $supersededEvent = Publish-TodActivityEvent -EventType 'task_superseded_by_operator_objective' -ObjectiveId ([string]$supersededLane.superseded_objective_id) -TaskId ([string]$supersededLane.superseded_task_id) -RequestId ([string]$supersededLane.superseded_request_id) -CorrelationId $resolvedCorrelationId -Title ([string]$(if (-not [string]::IsNullOrWhiteSpace([string]$Title)) { $Title } else { "Chat task $TaskId" })) -Status 'superseded' -Message 'Superseded the previous direct-chat claim because a newer operator objective was submitted.' -Details ([ordered]@{
                reason = [string]$supersededLane.reason
                superseded_by_task_id = [string]$TaskId
                superseded_by_request_id = $resolvedRequestId
                superseded_by_objective_id = [string]$objective.id
                archived_paths = @($supersededLane.archived_paths)
            }) -Source 'tod.execute-chat-task' -Surface 'tod-chat' -Summary ([string]$resolvedDescription) -CurrentAction 'Archived the stale direct-chat claim before dispatching the new task.'
        [void]$activityEvents.Add($supersededEvent)
    }

    $taskCreatedEvent = Publish-TodActivityEvent -EventType 'task_created_from_chat' -ObjectiveId ([string]$objective.id) -TaskId ([string]$TaskId) -RequestId $resolvedRequestId -CorrelationId $resolvedCorrelationId -Title ([string]$request.title) -Status 'created' -Message 'Created a fresh bounded task from TOD direct chat input.' -Details ([ordered]@{
            request_paths = @($requestArtifactPaths)
            task_category = $TaskCategory
            source = 'direct_chat'
        }) -Source 'tod.execute-chat-task' -Surface 'tod-chat' -Summary ([string]$resolvedDescription) -CurrentAction 'Recorded the operator request as a TOD task.'
    [void]$activityEvents.Add($taskCreatedEvent)

    $mirror = Sync-CodexHandoffTaskMirror -Request $request
    $state = Load-State
    $task = @($state.tasks | Where-Object { [string]$_.id -eq [string]$TaskId } | Select-Object -First 1)
    if (@($task).Count -eq 0) {
        throw "Unable to locate chat task '$TaskId' after mirroring it into local state."
    }

    $resolvedAssignedExecutor = if (-not [string]::IsNullOrWhiteSpace($AssignedExecutor)) { [string]$AssignedExecutor } else { 'local' }
    $resolvedTaskCategory = if (-not [string]::IsNullOrWhiteSpace($TaskCategory)) { [string]$TaskCategory } else { 'chat_execution' }
    $applyBlockedStateBypass = [string]::Equals($resolvedTaskCategory, 'diagnostic_implementation_repair', [System.StringComparison]::OrdinalIgnoreCase)
    $task[0].assigned_executor = $resolvedAssignedExecutor
    $task[0].task_category = $resolvedTaskCategory
    $task[0].type = 'implementation'
    $task[0] | Add-Member -NotePropertyName source -NotePropertyValue 'direct_chat' -Force
    $task[0].acceptance_criteria = [string[]](Split-List -Value $resolvedAcceptance)
    if (-not [string]::IsNullOrWhiteSpace($TargetFile)) {
        $normalizedTargetFile = ([string]$TargetFile) -replace '[\\/]+', '/'
        if ($task[0].PSObject.Properties['allowed_files']) {
            $task[0].allowed_files = [string[]]@($normalizedTargetFile)
        }
        else {
            $task[0] | Add-Member -NotePropertyName allowed_files -NotePropertyValue ([string[]]@($normalizedTargetFile)) -Force
        }
        if ($task[0].PSObject.Properties['files_involved']) {
            $task[0].files_involved = [string[]]@($normalizedTargetFile)
        }
        else {
            $task[0] | Add-Member -NotePropertyName files_involved -NotePropertyValue ([string[]]@($normalizedTargetFile)) -Force
        }
    }
    $task[0].scope = [string]$Scope
    $task[0].title = if (-not [string]::IsNullOrWhiteSpace($Title)) { [string]$Title } else { "Chat task $TaskId" }
    $materialization = Resolve-TaskBoundedEditMaterialization -Task $task[0]
    $task[0] | Add-Member -NotePropertyName materialization -NotePropertyValue $materialization -Force
    $request.metadata_json | Add-Member -NotePropertyName materialization -NotePropertyValue $materialization -Force
    $request.metadata_json | Add-Member -NotePropertyName task_source -NotePropertyValue 'direct_chat' -Force
    $task[0].updated_at = Get-UtcNow
    Save-State -State $state

    if ($applyBlockedStateBypass) {
        foreach ($bypassEventType in @('blocked_state_bypass_applied', 'fresh_repair_task_created', 'repair_task_materialization_started', 'stale_blocker_ignored_for_new_objective')) {
            $bypassEvent = Publish-TodActivityEvent -EventType $bypassEventType -ObjectiveId ([string]$objective.id) -TaskId ([string]$TaskId) -RequestId $resolvedRequestId -CorrelationId $resolvedCorrelationId -Title ([string]$task[0].title) -Status 'completed' -Message $(if ([string]::Equals($bypassEventType, 'blocked_state_bypass_applied', [System.StringComparison]::OrdinalIgnoreCase)) { 'Bypassed stale blocked-state rendering for a new direct-chat operator directive.' } elseif ([string]::Equals($bypassEventType, 'fresh_repair_task_created', [System.StringComparison]::OrdinalIgnoreCase)) { 'Created a fresh direct-chat repair task for the new operator directive.' } elseif ([string]::Equals($bypassEventType, 'repair_task_materialization_started', [System.StringComparison]::OrdinalIgnoreCase)) { 'Started materialization for the fresh direct-chat repair task.' } else { 'Ignored the stale blocker while accepting the new direct-chat objective.' }) -Details ([ordered]@{
                    reason_code = if ([string]::Equals($bypassEventType, 'blocked_state_bypass_applied', [System.StringComparison]::OrdinalIgnoreCase)) { 'blocked_state_bypass_applied' } elseif ([string]::Equals($bypassEventType, 'repair_task_materialization_started', [System.StringComparison]::OrdinalIgnoreCase)) { 'fresh_objective_materialized_from_blocked_state' } else { $bypassEventType }
                    task_category = $resolvedTaskCategory
                }) -Source 'tod.execute-chat-task' -Surface 'tod-chat' -Summary ([string]$resolvedDescription) -CurrentAction 'Routing a fresh direct-chat repair task instead of returning stale blocked state.'
            [void]$activityEvents.Add($bypassEvent)
        }
    }

    $taskClaimedEvent = Publish-TodActivityEvent -EventType 'task_claimed' -ObjectiveId ([string]$objective.id) -TaskId ([string]$TaskId) -RequestId $resolvedRequestId -CorrelationId $resolvedCorrelationId -Title ([string]$task[0].title) -Status 'in_progress' -Message ('Claimed the chat task for executor {0}.' -f $resolvedAssignedExecutor) -Details ([ordered]@{
            assigned_executor = $resolvedAssignedExecutor
            task_category = $resolvedTaskCategory
            task_mirror_reason = if ($mirror.PSObject.Properties['reason']) { [string]$mirror.reason } else { '' }
        }) -Source 'tod.execute-chat-task' -Surface 'tod-chat' -Summary ([string]$resolvedDescription) -CurrentAction 'Prepared the bounded task for execution routing.'
    [void]$activityEvents.Add($taskClaimedEvent)

    $packagePath = Write-CodexHandoffTaskPackage -Request $request

    $executionStartedEvent = Publish-TodActivityEvent -EventType 'execution_started' -ObjectiveId ([string]$objective.id) -TaskId ([string]$TaskId) -RequestId $resolvedRequestId -CorrelationId $resolvedCorrelationId -Title ([string]$task[0].title) -Status 'started' -Message 'Started immediate TOD execution routing for the chat task.' -Details ([ordered]@{
            assigned_executor = $resolvedAssignedExecutor
            package_path = $packagePath
        }) -Source 'tod.execute-chat-task' -Surface 'tod-chat' -Summary ([string]$resolvedDescription) -CurrentAction 'Invoked run-task immediately after chat task creation.'
    [void]$activityEvents.Add($executionStartedEvent)

    if ([string]::Equals($ExecutionMode, 'async', [System.StringComparison]::OrdinalIgnoreCase)) {
        try {
            $queuedProcess = Start-TodChatTaskProcess -TaskId ([string]$TaskId) -PackagePath $packagePath -ResolvedConfigPath $ResolvedConfigPath -ResolvedStatePath $ResolvedStatePath
            $task[0] | Add-Member -NotePropertyName async_worker -NotePropertyValue ([pscustomobject]@{
                    pid = [int]$queuedProcess.pid
                    runner = [string]$queuedProcess.runner
                    script_path = [string]$queuedProcess.script_path
                    working_directory = if ($queuedProcess.PSObject.Properties['working_directory']) { [string]$queuedProcess.working_directory } else { '' }
                    stdout_path = [string]$queuedProcess.stdout_path
                    stderr_path = [string]$queuedProcess.stderr_path
                    launched_at = [string]$queuedProcess.launched_at
                    command_preview = [string]$queuedProcess.command_preview
                }) -Force
            Save-State -State $state
            $queuedEvent = Publish-TodActivityEvent -EventType 'execution_queued' -ObjectiveId ([string]$objective.id) -TaskId ([string]$TaskId) -RequestId $resolvedRequestId -CorrelationId $resolvedCorrelationId -Title ([string]$task[0].title) -Status 'queued' -Message 'Queued background TOD execution for the chat task.' -Details ([ordered]@{
                    assigned_executor = $resolvedAssignedExecutor
                    package_path = $packagePath
                    pid = [int]$queuedProcess.pid
                    stdout_path = [string]$queuedProcess.stdout_path
                    stderr_path = [string]$queuedProcess.stderr_path
                    working_directory = if ($queuedProcess.PSObject.Properties['working_directory']) { [string]$queuedProcess.working_directory } else { '' }
                    command_preview = [string]$queuedProcess.command_preview
                }) -Source 'tod.execute-chat-task' -Surface 'tod-chat' -Summary ([string]$resolvedDescription) -CurrentAction 'Queued background run-task execution.'
            [void]$activityEvents.Add($queuedEvent)
            $runTask = [pscustomobject]@{
                payload = [pscustomobject]@{
                    task_id = [string]$TaskId
                    decision = 'queued'
                    blocked = $false
                    accepted = $true
                    execution_status = 'queued'
                    summary = 'Task accepted and queued for background execution.'
                    post_completion_tail_skipped = $true
                    engine_invocation = [pscustomobject]@{
                        active_engine = $resolvedAssignedExecutor
                        attempted_engines = @($resolvedAssignedExecutor)
                        background_queued = $true
                        process_id = [int]$queuedProcess.pid
                        stdout_path = [string]$queuedProcess.stdout_path
                        stderr_path = [string]$queuedProcess.stderr_path
                        launched_at = [string]$queuedProcess.launched_at
                    }
                }
                output = ''
            }
        }
        catch {
            Set-PersistedTaskTerminalState -Task $task[0] -Status 'blocked' -EventType 'blocked' -Message 'Background chat task execution could not be queued.' -ReasonCode 'worker_startup_failure' -Details ([pscustomobject]@{
                    error = [string]$_.Exception.Message
                    package_path = $packagePath
                }) -TaskStatus 'blocked'
            Save-State -State $state
            $blockedEvent = Publish-TodActivityEvent -EventType 'blocked' -ObjectiveId ([string]$objective.id) -TaskId ([string]$TaskId) -RequestId $resolvedRequestId -CorrelationId $resolvedCorrelationId -Title ([string]$task[0].title) -Status 'blocked' -Message 'Background chat task execution could not be queued.' -Details ([ordered]@{
                    reason_code = 'worker_startup_failure'
                    error = [string]$_.Exception.Message
                    package_path = $packagePath
                }) -Source 'tod.execute-chat-task' -Surface 'tod-chat' -Summary ([string]$resolvedDescription) -CurrentAction 'Recorded the blocking condition for background chat execution.' -RecoveryState 'required'
            [void]$activityEvents.Add($blockedEvent)
            $runTask = [pscustomobject]@{
                payload = [pscustomobject]@{
                    task_id = [string]$TaskId
                    decision = 'blocked'
                    blocked = $true
                    accepted = $false
                    execution_status = 'blocked'
                    reason_code = 'worker_startup_failure'
                    summary = [string]$_.Exception.Message
                }
                output = [string]$_.Exception.Message
            }
        }
    }
    else {
        try {
            $runTask = Invoke-TodSelfJsonAction -ActionName 'run-task' -Arguments @{
                TaskId = [string]$TaskId
                PackagePath = $packagePath
                ConfigPath = $ResolvedConfigPath
                StatePath = $ResolvedStatePath
                SkipNextTaskSelectionLoop = $true
                SkipPostCompletionTail = $true
            }
        }
        catch {
            $blockedEvent = Publish-TodActivityEvent -EventType 'blocked' -ObjectiveId ([string]$objective.id) -TaskId ([string]$TaskId) -RequestId $resolvedRequestId -CorrelationId $resolvedCorrelationId -Title ([string]$task[0].title) -Status 'blocked' -Message 'Immediate chat task execution was blocked before TOD could complete run-task.' -Details ([ordered]@{
                    error = [string]$_.Exception.Message
                    package_path = $packagePath
                }) -Source 'tod.execute-chat-task' -Surface 'tod-chat' -Summary ([string]$resolvedDescription) -CurrentAction 'Recorded the blocking condition for the chat task.' -RecoveryState 'required'
            [void]$activityEvents.Add($blockedEvent)
            $runTask = [pscustomobject]@{
                payload = [pscustomobject]@{
                    task_id = [string]$TaskId
                    decision = 'blocked'
                    blocked = $true
                    accepted = $false
                    execution_status = 'blocked'
                    summary = [string]$_.Exception.Message
                }
                output = [string]$_.Exception.Message
            }
        }
    }

    $primaryRequestArtifactPath = ''
    foreach ($candidatePath in @($requestArtifactPaths)) {
        if ([System.IO.Path]::GetFileName([string]$candidatePath) -eq 'MIM_TOD_TASK_REQUEST.latest.json') {
            $primaryRequestArtifactPath = [string]$candidatePath
            break
        }
    }
    $requestArtifactPathList = [string[]]@($requestArtifactPaths | ForEach-Object { [string]$_ })
    $activityEventTypeList = New-Object System.Collections.Generic.List[string]
    if ($null -ne $supersededLane) {
        [void]$activityEventTypeList.Add('task_superseded_by_operator_objective')
    }
    if ($applyBlockedStateBypass) {
        [void]$activityEventTypeList.Add('blocked_state_bypass_applied')
        [void]$activityEventTypeList.Add('fresh_repair_task_created')
        [void]$activityEventTypeList.Add('repair_task_materialization_started')
        [void]$activityEventTypeList.Add('stale_blocker_ignored_for_new_objective')
    }
    [void]$activityEventTypeList.Add('task_created_from_chat')
    [void]$activityEventTypeList.Add('task_claimed')
    [void]$activityEventTypeList.Add('execution_started')
    if ($materialization.PSObject.Properties['status'] -and [string]::Equals([string]$materialization.status, 'materialized', [System.StringComparison]::OrdinalIgnoreCase)) {
        [void]$activityEventTypeList.Add('bounded_edit_materialized')
        [void]$activityEventTypeList.Add('local_executor_ready')
    }
    elseif ($materialization.PSObject.Properties['reason_code'] -and [string]::Equals([string]$materialization.reason_code, 'blocked_missing_bounded_edit_mode', [System.StringComparison]::OrdinalIgnoreCase)) {
        [void]$activityEventTypeList.Add('bounded_edit_mode_missing')
    }
    if ($runTask -and $runTask.PSObject.Properties['payload'] -and $runTask.payload -and $runTask.payload.PSObject.Properties['execution_status'] -and [string]::Equals([string]$runTask.payload.execution_status, 'queued', [System.StringComparison]::OrdinalIgnoreCase)) {
        [void]$activityEventTypeList.Add('execution_queued')
    }
    $runTaskPayload = if ($runTask -and $runTask.PSObject.Properties['payload']) { $runTask.payload } else { $null }
    $engineInvocationPayload = if ($runTaskPayload -and $runTaskPayload.PSObject.Properties['engine_invocation']) { $runTaskPayload.engine_invocation } else { $null }
    $routingDecisionPayload = if ($runTaskPayload -and $runTaskPayload.PSObject.Properties['routing_decision_preinvoke'] -and $runTaskPayload.routing_decision_preinvoke) {
        $runTaskPayload.routing_decision_preinvoke
    }
    elseif ($runTaskPayload -and $runTaskPayload.PSObject.Properties['routing_decision'] -and $runTaskPayload.routing_decision) {
        $runTaskPayload.routing_decision
    }
    else {
        $null
    }
    $routingSuitabilityPayload = if ($routingDecisionPayload -and $routingDecisionPayload.PSObject.Properties['routing'] -and $routingDecisionPayload.routing -and $routingDecisionPayload.routing.PSObject.Properties['suitability']) {
        $routingDecisionPayload.routing.suitability
    }
    else {
        $null
    }
    $activeEngineName = if ($engineInvocationPayload -and $engineInvocationPayload.PSObject.Properties['active_engine']) { [string]$engineInvocationPayload.active_engine } else { '' }
    $engineResultPayload = if ($engineInvocationPayload -and $engineInvocationPayload.PSObject.Properties['result']) { $engineInvocationPayload.result } else { $null }
    $executorClassificationPayload = $null
    $selectedExecutorForEvent = if (-not [string]::IsNullOrWhiteSpace($activeEngineName)) {
        $activeEngineName
    }
    elseif ($routingDecisionPayload -and $routingDecisionPayload.PSObject.Properties['selected_engine'] -and -not [string]::IsNullOrWhiteSpace([string]$routingDecisionPayload.selected_engine)) {
        [string]$routingDecisionPayload.selected_engine
    }
    else {
        $resolvedAssignedExecutor
    }
    if (-not [string]::IsNullOrWhiteSpace($selectedExecutorForEvent)) {
        $executorClassificationPayload = [pscustomobject]@{
            selected_executor = $selectedExecutorForEvent
            classification_reason = if ($routingDecisionPayload -and $routingDecisionPayload.PSObject.Properties['selection_reason'] -and -not [string]::IsNullOrWhiteSpace([string]$routingDecisionPayload.selection_reason)) { [string]$routingDecisionPayload.selection_reason } elseif ($routingSuitabilityPayload -and $routingSuitabilityPayload.PSObject.Properties['reason']) { [string]$routingSuitabilityPayload.reason } else { '' }
            local_supported = if ($routingSuitabilityPayload -and $routingSuitabilityPayload.PSObject.Properties['local_supported']) { [bool]$routingSuitabilityPayload.local_supported } else { [string]::Equals($selectedExecutorForEvent, 'local', [System.StringComparison]::OrdinalIgnoreCase) }
            codex_allowed = if ($routingSuitabilityPayload -and $routingSuitabilityPayload.PSObject.Properties['codex_allowed']) { [bool]$routingSuitabilityPayload.codex_allowed } else { $false }
        }
    }
    $localAttempted = $false
    if ($engineInvocationPayload -and $engineInvocationPayload.PSObject.Properties['attempted_engines']) {
        $localAttempted = (@($engineInvocationPayload.attempted_engines | ForEach-Object { ([string]$_).ToLowerInvariant() }) -contains 'local')
    }
    $materializationBlockedBeforeLocalExecution = $false
    if ($runTaskPayload -and $runTaskPayload.PSObject.Properties['failure_category'] -and [string]::Equals([string]$runTaskPayload.failure_category, 'materialization_blocked', [System.StringComparison]::OrdinalIgnoreCase)) {
        $materializationBlockedBeforeLocalExecution = $true
    }
    if ($runTaskPayload -and $runTaskPayload.PSObject.Properties['reason_code'] -and [string]::Equals([string]$runTaskPayload.reason_code, 'blocked_missing_bounded_edit_mode', [System.StringComparison]::OrdinalIgnoreCase)) {
        $materializationBlockedBeforeLocalExecution = $true
    }
    if ($engineResultPayload -and $engineResultPayload.PSObject.Properties['reason_code'] -and [string]::Equals([string]$engineResultPayload.reason_code, 'blocked_missing_bounded_edit_mode', [System.StringComparison]::OrdinalIgnoreCase)) {
        $materializationBlockedBeforeLocalExecution = $true
    }
    if ($materializationBlockedBeforeLocalExecution) {
        $localAttempted = $false
        $activeEngineName = ''
    }
    if ($null -ne $executorClassificationPayload) {
        [void]$activityEventTypeList.Add('executor_classified')
    }
    if ([string]::Equals($activeEngineName, 'local', [System.StringComparison]::OrdinalIgnoreCase) -or $localAttempted) {
        [void]$activityEventTypeList.Add('local_executor_invoked')
        $localResultBlocked = $false
        if ($runTaskPayload -and $runTaskPayload.PSObject.Properties['decision'] -and -not [string]::Equals([string]$runTaskPayload.decision, 'pass', [System.StringComparison]::OrdinalIgnoreCase)) {
            $localResultBlocked = $true
        }
        if ($engineResultPayload -and $engineResultPayload.PSObject.Properties['reason_code'] -and -not [string]::IsNullOrWhiteSpace([string]$engineResultPayload.reason_code)) {
            $localResultBlocked = $true
        }
        if ($localResultBlocked) {
            [void]$activityEventTypeList.Add('blocked_missing_local_executor_result')
        }
        else {
            [void]$activityEventTypeList.Add('local_executor_completed')
        }
    }
    if ($runTaskPayload -and $runTaskPayload.PSObject.Properties['decision'] -and -not [string]::IsNullOrWhiteSpace([string]$runTaskPayload.decision)) {
        if ([string]::Equals([string]$runTaskPayload.decision, 'pass', [System.StringComparison]::OrdinalIgnoreCase)) {
            [void]$activityEventTypeList.Add('validation_passed')
        }
        else {
            [void]$activityEventTypeList.Add('validation_failed')
        }
        [void]$activityEventTypeList.Add('result_published')
    }
    if ($runTask -and $runTask.PSObject.Properties['payload'] -and $runTask.payload -and $runTask.payload.PSObject.Properties['decision'] -and [string]::Equals([string]$runTask.payload.decision, 'blocked', [System.StringComparison]::OrdinalIgnoreCase)) {
        [void]$activityEventTypeList.Add('blocked')
    }

    return [pscustomobject]@{
        request_id = $resolvedRequestId
        task_id = [string]$TaskId
        objective_id = [string]$objective.id
        correlation_id = $resolvedCorrelationId
        request_artifact_path = $primaryRequestArtifactPath
        request_artifact_paths = $requestArtifactPathList
        activity_event_types = @($activityEventTypeList)
        reason_codes = if ($applyBlockedStateBypass) { @('blocked_state_bypass_applied', 'fresh_objective_materialized_from_blocked_state') } else { @() }
        selected_task = [pscustomobject]@{
            task_id = [string]$TaskId
            objective_id = [string]$objective.id
            reason_code = if ($applyBlockedStateBypass) { 'fresh_objective_materialized_from_blocked_state' } else { 'direct_chat_task_created' }
        }
        claimed_task = [pscustomobject]@{
            task_id = [string]$TaskId
            objective_id = [string]$objective.id
            assigned_executor = $resolvedAssignedExecutor
            reason_code = if ($applyBlockedStateBypass) { 'fresh_objective_materialized_from_blocked_state' } else { 'direct_chat_task_claimed' }
        }
        intake_arbitration = $intakeArbitration.arbitration
        intake_queue = $intakeArbitration.queue
        executor_classification = $executorClassificationPayload
        superseded_claim = $supersededLane
        task_mirror = $mirror
        package_path = $packagePath
        run_task = $runTask.payload
        run_task_output = $runTask.output
        execution_mode = $ExecutionMode
    }
}

function Test-BridgeRequestSupportedAction {
    param([Parameter(Mandatory = $true)][string]$ActionName)

    switch ($ActionName.ToLowerInvariant()) {
        "get-capabilities" { return $true }
        "get-execution-readiness" { return $true }
        "get-state-bus" { return $true }
        "get-version" { return $true }
        "ping-mim" { return $true }
        "safe_home" { return $true }
        "scan_pose" { return $true }
        "capture_frame" { return $true }
        default { return $false }
    }
}

function Invoke-BridgeRequestExecution {
    param(
        [Parameter(Mandatory = $true)][string]$RequestId,
        [Parameter(Mandatory = $true)][string]$ResolvedConfigPath,
        [string]$ResolvedStatePath
    )

    $packet = Get-BridgeRequestPacket
    $request = $packet.payload
    $liveRequestId = if ($request.PSObject.Properties["request_id"] -and -not [string]::IsNullOrWhiteSpace([string]$request.request_id)) {
        [string]$request.request_id
    }
    else {
        ""
    }

    if ([string]::IsNullOrWhiteSpace($liveRequestId)) {
        throw "Bridge request packet at '$([string]$packet.path)' is missing request_id."
    }
    if (-not [string]::Equals($liveRequestId, $RequestId, [System.StringComparison]::Ordinal)) {
        throw "Latest bridge request_id '$liveRequestId' at '$([string]$packet.path)' does not match requested request_id '$RequestId'."
    }

    $bridgeAction = Resolve-BridgeRequestAction -Request $request
    if (-not (Test-BridgeRequestSupportedAction -ActionName $bridgeAction)) {
        throw "Bridge request '$RequestId' resolves to TOD action '$bridgeAction', which is not supported by run-bridge-request. Supported bridge actions: get-capabilities, get-execution-readiness, get-state-bus, get-version, ping-mim, safe_home, scan_pose, capture_frame."
    }

    $todArgs = @{
        Action = $bridgeAction
        ConfigPath = $ResolvedConfigPath
    }
    if (-not [string]::IsNullOrWhiteSpace($ResolvedStatePath)) {
        $todArgs["StatePath"] = $ResolvedStatePath
    }
    if ($request.PSObject.Properties["Top"] -and $null -ne $request.Top) {
        try {
            $todArgs["Top"] = [int]$request.Top
        }
        catch {
        }
    }
    elseif ($request.PSObject.Properties["top"] -and $null -ne $request.top) {
        try {
            $todArgs["Top"] = [int]$request.top
        }
        catch {
        }
    }

    $startUtc = Get-UtcNow
    try {
        $raw = & $PSCommandPath @todArgs 2>&1
        $payload = $null
        try {
            $payload = ($raw | ConvertFrom-Json)
        }
        catch {
            $payload = $null
        }

        return [pscustomobject]@{
            request_id = $liveRequestId
            task_id = if ($request.PSObject.Properties["task_id"]) { [string]$request.task_id } else { "" }
            objective_id = if ($request.PSObject.Properties["objective_id"]) { [string]$request.objective_id } else { "" }
            tod_action = $bridgeAction
            execution_lane = "bridge_request"
            validated_request_match = $true
            request_packet_path = [string]$packet.path
            mim_task_lookup_used = $false
            local_task_resolution_used = $false
            request = [pscustomobject]@{
                request_id = $liveRequestId
                task_id = if ($request.PSObject.Properties["task_id"]) { [string]$request.task_id } else { "" }
                objective_id = if ($request.PSObject.Properties["objective_id"]) { [string]$request.objective_id } else { "" }
                tod_action = $bridgeAction
                generated_at = if ($request.PSObject.Properties["generated_at"]) { [string]$request.generated_at } else { "" }
                target = if ($request.PSObject.Properties["target"]) { [string]$request.target } else { "" }
            }
            execution = [pscustomobject]@{
                ok = $true
                blocked = if ($null -ne $payload -and $payload.PSObject.Properties["blocked"]) { [bool]$payload.blocked } else { $false }
                action = $bridgeAction
                execution_mode = "direct_script_success"
                started_at = $startUtc
                completed_at = Get-UtcNow
                execution_readiness = if ($null -ne $payload -and $payload.PSObject.Properties["execution_readiness"]) { $payload.execution_readiness } else { $null }
                execution_trace = if ($null -ne $payload -and $payload.PSObject.Properties["execution_trace"]) { $payload.execution_trace } else { $null }
                payload = $payload
                output = [string]($raw | Out-String)
                error = ""
            }
        }
    }
    catch {
        return [pscustomobject]@{
            request_id = $liveRequestId
            task_id = if ($request.PSObject.Properties["task_id"]) { [string]$request.task_id } else { "" }
            objective_id = if ($request.PSObject.Properties["objective_id"]) { [string]$request.objective_id } else { "" }
            tod_action = $bridgeAction
            execution_lane = "bridge_request"
            validated_request_match = $true
            request_packet_path = [string]$packet.path
            mim_task_lookup_used = $false
            local_task_resolution_used = $false
            request = [pscustomobject]@{
                request_id = $liveRequestId
                task_id = if ($request.PSObject.Properties["task_id"]) { [string]$request.task_id } else { "" }
                objective_id = if ($request.PSObject.Properties["objective_id"]) { [string]$request.objective_id } else { "" }
                tod_action = $bridgeAction
                generated_at = if ($request.PSObject.Properties["generated_at"]) { [string]$request.generated_at } else { "" }
                target = if ($request.PSObject.Properties["target"]) { [string]$request.target } else { "" }
            }
            execution = [pscustomobject]@{
                ok = $false
                blocked = $false
                action = $bridgeAction
                execution_mode = "direct_script_exception"
                started_at = $startUtc
                completed_at = Get-UtcNow
                execution_readiness = $null
                execution_trace = $null
                payload = $null
                output = ""
                error = [string]$_.Exception.Message
            }
        }
    }
}

function Get-ListenerRequestBridgeHint {
    param([string]$TaskId)

    if ([string]::IsNullOrWhiteSpace($TaskId)) {
        return $null
    }

    $packetSpecs = @(
        [pscustomobject]@{ kind = "request"; path = $bridgeRequestPacketPath },
        [pscustomobject]@{ kind = "ack"; path = (Join-Path $repoRoot "tod/out/context-sync/listener/TOD_MIM_TASK_ACK.latest.json") },
        [pscustomobject]@{ kind = "result"; path = (Join-Path $repoRoot "tod/out/context-sync/listener/TOD_MIM_TASK_RESULT.latest.json") }
    )

    foreach ($packetSpec in $packetSpecs) {
        if (-not (Test-Path -Path $packetSpec.path -PathType Leaf)) {
            continue
        }

        try {
            $payload = Get-Content -Path $packetSpec.path -Raw | ConvertFrom-Json
        }
        catch {
            continue
        }

        $candidateTaskId = if ($payload.PSObject.Properties["task_id"]) { [string]$payload.task_id } else { "" }
        $candidateRequestId = if ($payload.PSObject.Properties["request_id"]) { [string]$payload.request_id } else { "" }
        if (([string]$candidateTaskId -ne [string]$TaskId) -and ([string]$candidateRequestId -ne [string]$TaskId)) {
            continue
        }

        return [pscustomobject]@{
            kind = [string]$packetSpec.kind
            path = [string]$packetSpec.path
            task_id = $candidateTaskId
            request_id = $candidateRequestId
            objective_id = if ($payload.PSObject.Properties["objective_id"]) { [string]$payload.objective_id } elseif ($payload.PSObject.Properties["objective"]) { [string]$payload.objective } else { "" }
            title = if ($payload.PSObject.Properties["title"]) { [string]$payload.title } else { "" }
            tod_action = if ($payload.PSObject.Properties["tod_action"]) { [string]$payload.tod_action } elseif ($payload.PSObject.Properties["action"]) { [string]$payload.action } else { "" }
            status = if ($payload.PSObject.Properties["status"]) { [string]$payload.status } else { "" }
            generated_at = if ($payload.PSObject.Properties["generated_at"]) { [string]$payload.generated_at } else { "" }
        }
    }

    return $null
}

function Get-RemoteTaskResolutionFailureMessage {
    param(
        [Parameter(Mandatory = $true)][string]$TaskId,
        $BridgeHint
    )

    if ($null -eq $BridgeHint) {
        return "Task not found in local state cache or remote task registry: $TaskId"
    }

    $objectiveText = if (-not [string]::IsNullOrWhiteSpace([string]$BridgeHint.objective_id)) { [string]$BridgeHint.objective_id } else { "unknown" }
    $actionText = if (-not [string]::IsNullOrWhiteSpace([string]$BridgeHint.tod_action)) { [string]$BridgeHint.tod_action } else { "unspecified" }
    $statusText = if (-not [string]::IsNullOrWhiteSpace([string]$BridgeHint.status)) { [string]$BridgeHint.status } else { [string]$BridgeHint.kind }

    return "Task '$TaskId' matches the live listener $([string]$BridgeHint.kind) packet at '$([string]$BridgeHint.path)'. This is a bridge request_id/task_id for objective '$objectiveText' and TOD action '$actionText' (status '$statusText'), not a numeric MIM /tasks record. Execute it with '.\\scripts\\TOD.ps1 -Action run-bridge-request -RequestId $TaskId' or use a resolvable MIM task ID."
}

function Resolve-ExecutionFeedbackConfig {
    param([Parameter(Mandatory = $true)]$Config)

    $cfg = if ($Config.PSObject.Properties["execution_feedback"] -and $null -ne $Config.execution_feedback) {
        $Config.execution_feedback
    }
    else {
        [pscustomobject]@{ enabled = $false; source = "tod"; auth_token = "" }
    }

    return [pscustomobject]@{
        enabled = [bool]$cfg.enabled
        source = if ([string]::IsNullOrWhiteSpace([string]$cfg.source)) { "tod" } else { [string]$cfg.source }
        auth_token = if ($cfg.PSObject.Properties["auth_token"]) { [string]$cfg.auth_token } else { "" }
    }
}

function Get-TodExecutionSharedRoots {
    $roots = @()
    if (-not [string]::IsNullOrWhiteSpace($env:TOD_EXECUTION_SHARED_ROOTS)) {
        $roots = @(([string]$env:TOD_EXECUTION_SHARED_ROOTS) -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    }
    else {
        $roots = @(
            (Join-Path $repoRoot "runtime/shared"),
            (Join-Path $repoRoot "tmp_remote_mim/runtime/shared")
        )
    }

    $seen = @{}
    $resolved = @()
    foreach ($root in $roots) {
        $fullPath = [System.IO.Path]::GetFullPath($root)
        if ($seen.ContainsKey($fullPath)) {
            continue
        }
        $seen[$fullPath] = $true
        $resolved += $fullPath
    }

    return @($resolved)
}

function Get-TodIntakePayloadHash {
    param([AllowNull()]$Payload)

    if ($null -eq $Payload) {
        return ''
    }

    $json = $Payload | ConvertTo-Json -Depth 20 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$json)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return [System.BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Write-TodExecutionJsonAtomically {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Payload
    )

    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -Path $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $tempPath = [System.IO.Path]::Combine($directory, ([System.IO.Path]::GetRandomFileName() + ".tmp"))
    $backupPath = [System.IO.Path]::Combine($directory, ([System.IO.Path]::GetRandomFileName() + ".bak"))
    try {
        $json = $Payload | ConvertTo-Json -Depth 20
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($tempPath, $json, $utf8NoBom)
        if (Test-Path -Path $Path) {
            [System.IO.File]::Replace($tempPath, $Path, $backupPath, $true)
            if (Test-Path -Path $backupPath) {
                Remove-Item -Path $backupPath -Force -ErrorAction SilentlyContinue
            }
        }
        else {
            Move-Item -Path $tempPath -Destination $Path -Force
        }
    }
    finally {
        if (Test-Path -Path $tempPath) {
            Remove-Item -Path $tempPath -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -Path $backupPath) {
            Remove-Item -Path $backupPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Read-TodExecutionJsonIfExists {
    param([AllowEmptyString()][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -Path $Path)) {
        return $null
    }

    try {
        return (Get-Content -Raw -Path $Path | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Get-TodIntakeArtifactPath {
    param([Parameter(Mandatory = $true)][string]$FileName)

    $roots = @(Get-TodExecutionSharedRoots)
    if (@($roots).Count -eq 0) {
        return (Join-Path $repoRoot (Join-Path 'runtime/shared' $FileName))
    }

    return (Join-Path ([string]$roots[0]) $FileName)
}

function Write-TodIntakeArtifact {
    param(
        [Parameter(Mandatory = $true)][string]$FileName,
        [Parameter(Mandatory = $true)]$Payload
    )

    $paths = New-Object System.Collections.Generic.List[string]
    foreach ($sharedRoot in @(Get-TodExecutionSharedRoots)) {
        $path = Join-Path $sharedRoot $FileName
        Write-TodExecutionJsonAtomically -Path $path -Payload $Payload
        [void]$paths.Add($path)
    }

    return [string[]]@($paths)
}

function Read-TodIntakeArtifact {
    param([Parameter(Mandatory = $true)][string]$FileName)

    return (Read-TodExecutionJsonIfExists -Path (Get-TodIntakeArtifactPath -FileName $FileName))
}

function Get-TodIntakePriorityRank {
    param([AllowEmptyString()][string]$Priority)

    switch (([string]$Priority).ToLowerInvariant()) {
        'emergency_stop' { return 700 }
        'operator_cancel' { return 700 }
        'operator_admin_repair' { return 600 }
        'operator_direct_objective' { return 500 }
        'active_task_continuation' { return 400 }
        'mim_request' { return 300 }
        'watchdog_recovery' { return 200 }
        'scheduled_maintenance' { return 100 }
        'informational_chat' { return 10 }
        default { return 0 }
    }
}

function Resolve-TodIntakePriority {
    param(
        [AllowEmptyString()][string]$Source,
        [AllowEmptyString()][string]$TaskCategory,
        [AllowEmptyString()][string]$Text
    )

    $normalizedSource = ([string]$Source).ToLowerInvariant()
    $normalizedCategory = ([string]$TaskCategory).ToLowerInvariant()
    $normalizedText = ([string]$Text).ToLowerInvariant()

    if ($normalizedText -match '\b(emergency stop|operator cancel|cancel active|pause active|stop active)\b') {
        return 'emergency_stop'
    }
    if ($normalizedSource -eq 'operator_chat' -and ($normalizedCategory -eq 'diagnostic_implementation_repair' -or $normalizedText -match '(?m)^\s*(admin action|repair|force|diagnostic)\s*:')) {
        return 'operator_admin_repair'
    }
    if ($normalizedSource -eq 'operator_chat') {
        return 'operator_direct_objective'
    }
    if ($normalizedSource -eq 'mim_request') {
        return 'mim_request'
    }
    if ($normalizedSource -eq 'watchdog') {
        return 'watchdog_recovery'
    }
    if ($normalizedSource -eq 'maintenance') {
        return 'scheduled_maintenance'
    }
    if ($normalizedSource -eq 'recovery') {
        return 'watchdog_recovery'
    }

    return 'informational_chat'
}

function Get-TodTaskStatusFromState {
    param([AllowEmptyString()][string]$TaskId)

    if ([string]::IsNullOrWhiteSpace($TaskId) -or -not (Test-Path -Path $statePath)) {
        return ''
    }

    try {
        $localState = Load-State
        $task = @($localState.tasks | Where-Object { [string]$_.id -eq [string]$TaskId } | Select-Object -First 1)
        if (@($task).Count -eq 0) {
            return ''
        }

        return [string]$task[0].status
    }
    catch {
        return ''
    }
}

function Test-TodIntakeLaneActive {
    param($Lane)

    if ($null -eq $Lane -or -not $Lane.PSObject.Properties['task_id'] -or [string]::IsNullOrWhiteSpace([string]$Lane.task_id)) {
        return $false
    }

    $laneStatus = if ($Lane.PSObject.Properties['status']) { ([string]$Lane.status).ToLowerInvariant() } else { '' }
    if ($laneStatus -in @('completed', 'blocked', 'failed', 'superseded', 'idle', 'cleared')) {
        return $false
    }

    $stateStatus = (Get-TodTaskStatusFromState -TaskId ([string]$Lane.task_id)).ToLowerInvariant()
    if ($stateStatus -in @('completed', 'blocked', 'failed', 'superseded')) {
        return $false
    }

    return $true
}

function Test-TodIntakeTerminalStatus {
    param([AllowEmptyString()][string]$Status)

    return (([string]$Status).Trim().ToLowerInvariant() -in @('completed', 'failed', 'cancelled', 'canceled', 'rejected', 'superseded'))
}

function Get-TodIntakeLaneTerminalStatus {
    param($Lane)

    if ($null -eq $Lane -or -not $Lane.PSObject.Properties['task_id'] -or [string]::IsNullOrWhiteSpace([string]$Lane.task_id)) {
        return ''
    }

    $laneStatus = if ($Lane.PSObject.Properties['status']) { [string]$Lane.status } else { '' }
    if (Test-TodIntakeTerminalStatus -Status $laneStatus) {
        return $laneStatus
    }

    $stateStatus = Get-TodTaskStatusFromState -TaskId ([string]$Lane.task_id)
    if (Test-TodIntakeTerminalStatus -Status $stateStatus) {
        return $stateStatus
    }

    return ''
}

function Get-TodActiveExecutionLane {
    $lane = Read-TodIntakeArtifact -FileName $todActiveExecutionLaneFileName
    if (Test-TodIntakeLaneActive -Lane $lane) {
        return $lane
    }

    return $null
}

function New-TodIntakeItem {
    param(
        [Parameter(Mandatory = $true)][string]$RequestId,
        [Parameter(Mandatory = $true)][string]$TaskId,
        [AllowEmptyString()][string]$ObjectiveId,
        [Parameter(Mandatory = $true)][string]$Source,
        [AllowEmptyString()][string]$Priority,
        [AllowEmptyString()][string]$InterruptPolicy,
        [AllowEmptyString()][string]$RelationToActiveTask,
        [AllowEmptyString()][string]$Title,
        [AllowEmptyString()][string]$Summary,
        [AllowEmptyString()][string]$TaskCategory,
        [AllowEmptyString()][string]$PayloadHash
    )

    $receivedAt = Get-UtcNow
    return [pscustomobject]@{
        request_id = [string]$RequestId
        task_id = [string]$TaskId
        objective_id = [string]$ObjectiveId
        source = [string]$Source
        priority = [string]$Priority
        interrupt_policy = [string]$InterruptPolicy
        status = 'received'
        received_at = $receivedAt
        expires_at = (Get-Date).ToUniversalTime().AddHours(6).ToString('o')
        relation_to_active_task = [string]$RelationToActiveTask
        title = [string]$Title
        summary = [string]$Summary
        task_category = [string]$TaskCategory
        payload_hash = [string]$PayloadHash
    }
}

function Get-MatchingTodIntakeItem {
    param(
        $IncomingItem,
        [object[]]$ExistingItems = @()
    )

    foreach ($existing in @($ExistingItems)) {
        if ([string]::Equals([string]$existing.request_id, [string]$IncomingItem.request_id, [System.StringComparison]::OrdinalIgnoreCase) -or [string]::Equals([string]$existing.task_id, [string]$IncomingItem.task_id, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $existing
        }
    }

    return $null
}

function Resolve-TodIntakeRelation {
    param(
        $IncomingItem,
        $ActiveLane,
        [object[]]$ExistingItems = @()
    )

    if ($null -ne (Get-MatchingTodIntakeItem -IncomingItem $IncomingItem -ExistingItems $ExistingItems)) {
        return 'duplicate'
    }
    if ($null -eq $ActiveLane -or [string]::IsNullOrWhiteSpace([string]$ActiveLane.task_id)) {
        return 'new'
    }
    if ([string]::Equals([string]$IncomingItem.task_id, [string]$ActiveLane.task_id, [System.StringComparison]::OrdinalIgnoreCase) -or [string]::Equals([string]$IncomingItem.request_id, [string]$ActiveLane.request_id, [System.StringComparison]::OrdinalIgnoreCase)) {
        return 'continuation'
    }
    if ([string]$IncomingItem.priority -match 'repair') {
        return 'repair'
    }
    if ([string]$IncomingItem.priority -match 'emergency|cancel') {
        return 'supersedes'
    }

    return 'conflicts'
}

function Resolve-TodIntakeDecision {
    param(
        $IncomingItem,
        $ActiveLane,
        [object[]]$ExistingItems = @()
    )

    $relation = Resolve-TodIntakeRelation -IncomingItem $IncomingItem -ActiveLane $ActiveLane -ExistingItems $ExistingItems
    $incomingRank = Get-TodIntakePriorityRank -Priority ([string]$IncomingItem.priority)
    $activePriority = if ($ActiveLane -and $ActiveLane.PSObject.Properties['priority']) { [string]$ActiveLane.priority } else { '' }
    $activeRank = Get-TodIntakePriorityRank -Priority $activePriority
    $interruptPolicy = ([string]$IncomingItem.interrupt_policy).ToLowerInvariant()

    if ($relation -eq 'duplicate') {
        $matching = Get-MatchingTodIntakeItem -IncomingItem $IncomingItem -ExistingItems $ExistingItems
        $incomingHash = if ($IncomingItem.PSObject.Properties['payload_hash']) { [string]$IncomingItem.payload_hash } else { '' }
        $existingHash = if ($matching -and $matching.PSObject.Properties['payload_hash']) { [string]$matching.payload_hash } else { '' }
        if (-not [string]::IsNullOrWhiteSpace($incomingHash) -and -not [string]::IsNullOrWhiteSpace($existingHash) -and -not [string]::Equals($incomingHash, $existingHash, [System.StringComparison]::OrdinalIgnoreCase)) {
            return [pscustomobject]@{ decision = 'blocked_needs_operator'; relation_to_active_task = 'conflicts'; reason = 'idempotency_conflict' }
        }
        $matchingStatus = if ($matching -and $matching.PSObject.Properties['status']) { ([string]$matching.status).Trim().ToLowerInvariant() } else { '' }
        if ($matchingStatus -in @('accepted', 'completed')) {
            return [pscustomobject]@{ decision = 'reject_duplicate'; relation_to_active_task = $relation; reason = 'duplicate_completed_replay_prior_result' }
        }
        return [pscustomobject]@{ decision = 'reject_duplicate'; relation_to_active_task = $relation; reason = 'request_or_task_id_already_present_in_intake_queue' }
    }
    if ($relation -eq 'continuation') {
        return [pscustomobject]@{ decision = 'merge_with_active'; relation_to_active_task = $relation; reason = 'incoming_request_matches_active_execution_lane' }
    }
    if ($null -eq $ActiveLane) {
        return [pscustomobject]@{ decision = 'run_now'; relation_to_active_task = $relation; reason = 'no_active_execution_lane' }
    }
    if ($incomingRank -gt $activeRank -and $interruptPolicy -in @('interrupt_safe', 'pause_active', 'supersede_active')) {
        $decision = if ($interruptPolicy -eq 'pause_active') { 'pause_active' } elseif ($interruptPolicy -eq 'supersede_active') { 'supersede_active' } else { 'supersede_active' }
        return [pscustomobject]@{ decision = $decision; relation_to_active_task = 'supersedes'; reason = 'incoming_request_outranks_active_lane_and_is_interrupt_safe' }
    }
    if ([string]$IncomingItem.priority -eq 'informational_chat') {
        return [pscustomobject]@{ decision = 'defer'; relation_to_active_task = $relation; reason = 'informational_chat_waits_for_active_execution' }
    }

    return [pscustomobject]@{ decision = 'queue'; relation_to_active_task = $relation; reason = 'active_execution_lane_is_protected' }
}

function Register-TodIntakeItem {
    param(
        [Parameter(Mandatory = $true)]$Item
    )

    $drainResult = Drain-TodIntakeQueueAfterTerminalActiveLane
    $queuePayload = Read-TodIntakeArtifact -FileName $todIntakeQueueFileName
    $existingItems = if ($queuePayload -and $queuePayload.PSObject.Properties['items'] -and $null -ne $queuePayload.items) { @($queuePayload.items) } else { @() }
    $activeLane = Get-TodActiveExecutionLane
    $decision = Resolve-TodIntakeDecision -IncomingItem $Item -ActiveLane $activeLane -ExistingItems $existingItems
    $Item.relation_to_active_task = [string]$decision.relation_to_active_task
    $Item.status = if ([string]::Equals([string]$decision.decision, 'run_now', [System.StringComparison]::OrdinalIgnoreCase) -or [string]::Equals([string]$decision.decision, 'supersede_active', [System.StringComparison]::OrdinalIgnoreCase) -or [string]::Equals([string]$decision.decision, 'pause_active', [System.StringComparison]::OrdinalIgnoreCase)) { 'accepted' } elseif ([string]::Equals([string]$decision.decision, 'reject_duplicate', [System.StringComparison]::OrdinalIgnoreCase)) { 'rejected' } elseif ([string]::Equals([string]$decision.decision, 'blocked_needs_operator', [System.StringComparison]::OrdinalIgnoreCase)) { 'blocked' } else { 'queued' }

    $updatedItems = @()
    if ([string]::Equals([string]$decision.decision, 'blocked_needs_operator', [System.StringComparison]::OrdinalIgnoreCase)) {
        $updatedItems = @($existingItems)
    }
    elseif (-not [string]::Equals([string]$decision.decision, 'reject_duplicate', [System.StringComparison]::OrdinalIgnoreCase)) {
        $updatedItems += @($existingItems | Where-Object { -not [string]::Equals([string]$_.request_id, [string]$Item.request_id, [System.StringComparison]::OrdinalIgnoreCase) -and -not [string]::Equals([string]$_.task_id, [string]$Item.task_id, [System.StringComparison]::OrdinalIgnoreCase) })
        $updatedItems += $Item
    }
    else {
        $updatedItems = @($existingItems)
    }

    $queuedItems = @($updatedItems | Where-Object { [string]$_.status -eq 'queued' })
    $nextTask = @($queuedItems | Sort-Object -Property @{ Expression = { Get-TodIntakePriorityRank -Priority ([string]$_.priority) }; Descending = $true }, @{ Expression = { [string]$_.received_at }; Descending = $false } | Select-Object -First 1)
    $queueOut = [pscustomobject]@{
        generated_at = Get-UtcNow
        packet_type = 'tod-intake-queue-v1'
        active_task_id = if ($activeLane -and $activeLane.PSObject.Properties['task_id']) { [string]$activeLane.task_id } else { '' }
        count = @($updatedItems).Count
        queued_count = @($queuedItems).Count
        next_task_after_current = if (@($nextTask).Count -gt 0) { $nextTask[0] } else { $null }
        items = @($updatedItems)
    }
    $queuePaths = Write-TodIntakeArtifact -FileName $todIntakeQueueFileName -Payload $queueOut

    $newActiveLane = $activeLane
    if ([string]$decision.decision -in @('run_now', 'supersede_active', 'pause_active')) {
        $newActiveLane = [pscustomobject]@{
            generated_at = Get-UtcNow
            packet_type = 'tod-active-execution-lane-v1'
            request_id = [string]$Item.request_id
            task_id = [string]$Item.task_id
            objective_id = [string]$Item.objective_id
            source = [string]$Item.source
            priority = [string]$Item.priority
            status = 'active'
            started_at = Get-UtcNow
            relation_to_previous_active = [string]$decision.relation_to_active_task
            previous_active_task_id = if ($activeLane -and $activeLane.PSObject.Properties['task_id']) { [string]$activeLane.task_id } else { '' }
        }
        Write-TodIntakeArtifact -FileName $todActiveExecutionLaneFileName -Payload $newActiveLane | Out-Null
    }
    elseif ($null -eq $newActiveLane) {
        $newActiveLane = [pscustomobject]@{
            generated_at = Get-UtcNow
            packet_type = 'tod-active-execution-lane-v1'
            request_id = ''
            task_id = ''
            objective_id = ''
            source = ''
            priority = ''
            status = 'idle'
            started_at = ''
            relation_to_previous_active = ''
            previous_active_task_id = ''
        }
        Write-TodIntakeArtifact -FileName $todActiveExecutionLaneFileName -Payload $newActiveLane | Out-Null
    }

    $arbitration = [pscustomobject]@{
        generated_at = Get-UtcNow
        packet_type = 'tod-intake-arbitration-v1'
        decision = [string]$decision.decision
        reason = [string]$decision.reason
        relation_to_active_task = [string]$decision.relation_to_active_task
        incoming = $Item
        active_lane = $newActiveLane
        pre_registration_drain = $drainResult
        priority_order = @('emergency_stop/operator_cancel', 'operator_admin_repair', 'operator_direct_objective', 'active_task_continuation', 'mim_request', 'watchdog_recovery', 'scheduled_maintenance', 'informational_chat')
        queue_path = if (@($queuePaths).Count -gt 0) { [string]$queuePaths[0] } else { '' }
    }
    Write-TodIntakeArtifact -FileName $todIntakeArbitrationFileName -Payload $arbitration | Out-Null

    return [pscustomobject]@{
        decision = [string]$decision.decision
        reason = [string]$decision.reason
        relation_to_active_task = [string]$decision.relation_to_active_task
        item = $Item
        active_lane = $newActiveLane
        queue = $queueOut
        arbitration = $arbitration
    }
}

function Drain-TodIntakeQueueAfterTerminalActiveLane {
    $activeLane = Read-TodIntakeArtifact -FileName $todActiveExecutionLaneFileName
    $terminalStatus = Get-TodIntakeLaneTerminalStatus -Lane $activeLane
    if ([string]::IsNullOrWhiteSpace($terminalStatus)) {
        return [pscustomobject]@{
            drained = $false
            decision = 'active_lane_not_terminal'
            reason = 'active execution lane has not reached a drainable terminal status'
            active_lane = $activeLane
            queue = Read-TodIntakeArtifact -FileName $todIntakeQueueFileName
            arbitration = Read-TodIntakeArtifact -FileName $todIntakeArbitrationFileName
        }
    }

    $queuePayload = Read-TodIntakeArtifact -FileName $todIntakeQueueFileName
    $existingItems = if ($queuePayload -and $queuePayload.PSObject.Properties['items'] -and $null -ne $queuePayload.items) { @($queuePayload.items) } else { @() }
    if (@($existingItems).Count -eq 0) {
        return [pscustomobject]@{
            drained = $false
            decision = 'queue_empty'
            reason = 'active lane is terminal but no queued intake items exist'
            active_lane = $activeLane
            queue = $queuePayload
            arbitration = Read-TodIntakeArtifact -FileName $todIntakeArbitrationFileName
        }
    }

    $eligibleItems = @()
    $retainedItems = New-Object System.Collections.Generic.List[object]
    foreach ($item in @($existingItems)) {
        $itemStatus = if ($item.PSObject.Properties['status']) { ([string]$item.status).Trim().ToLowerInvariant() } else { '' }
        $taskId = if ($item.PSObject.Properties['task_id']) { [string]$item.task_id } else { '' }
        $requestId = if ($item.PSObject.Properties['request_id']) { [string]$item.request_id } else { '' }
        $objectiveId = if ($item.PSObject.Properties['objective_id']) { [string]$item.objective_id } else { '' }

        if ([string]::IsNullOrWhiteSpace($taskId) -or [string]::IsNullOrWhiteSpace($requestId) -or [string]::IsNullOrWhiteSpace($objectiveId)) {
            $item | Add-Member -NotePropertyName status -NotePropertyValue 'blocked' -Force
            $item | Add-Member -NotePropertyName blocked_reason_code -NotePropertyValue 'intake_item_missing_required_identity' -Force
            $item | Add-Member -NotePropertyName blocked_at -NotePropertyValue (Get-UtcNow) -Force
            [void]$retainedItems.Add($item)
            Publish-TodActivityEvent -EventType 'queued_task_blocked_with_reason' -ObjectiveId $objectiveId -TaskId $taskId -RequestId $requestId -CorrelationId '' -Title $(if ($item.PSObject.Properties['title']) { [string]$item.title } else { '' }) -Status 'blocked' -Message 'Queued intake item could not be drained because it is missing required identity fields.' -Details ([ordered]@{
                    reason_code = 'intake_item_missing_required_identity'
                    request_id = $requestId
                    task_id = $taskId
                    objective_id = $objectiveId
                }) -Source 'tod.intake' -Surface 'tod-intake' -Summary 'Queued task blocked during intake drain.' -CurrentAction 'Skipped invalid queued intake item.' -RecoveryState 'required' | Out-Null
            continue
        }

        if ($itemStatus -in @('queued', 'deferred')) {
            $eligibleItems += $item
        }
        else {
            [void]$retainedItems.Add($item)
        }
    }

    $selectedItems = @($eligibleItems | Sort-Object -Property @{ Expression = { Get-TodIntakePriorityRank -Priority ([string]$_.priority) }; Descending = $true }, @{ Expression = { [string]$_.received_at }; Descending = $false } | Select-Object -First 1)
    if (@($selectedItems).Count -eq 0) {
        $remainingQueued = @($retainedItems.ToArray() | Where-Object { [string]$_.status -eq 'queued' })
        $queueOutNoSelection = [pscustomobject]@{
            generated_at = Get-UtcNow
            packet_type = 'tod-intake-queue-v1'
            active_task_id = if ($activeLane -and $activeLane.PSObject.Properties['task_id']) { [string]$activeLane.task_id } else { '' }
            count = @($retainedItems.ToArray()).Count
            queued_count = @($remainingQueued).Count
            next_task_after_current = $null
            items = @($retainedItems.ToArray())
        }
        Write-TodIntakeArtifact -FileName $todIntakeQueueFileName -Payload $queueOutNoSelection | Out-Null
        return [pscustomobject]@{
            drained = $false
            decision = 'no_eligible_queued_task'
            reason = 'no queued intake item was eligible for promotion'
            active_lane = $activeLane
            queue = $queueOutNoSelection
            arbitration = Read-TodIntakeArtifact -FileName $todIntakeArbitrationFileName
        }
    }

    $selected = $selectedItems[0]
    foreach ($item in @($eligibleItems)) {
        if ([string]::Equals([string]$item.task_id, [string]$selected.task_id, [System.StringComparison]::OrdinalIgnoreCase) -and [string]::Equals([string]$item.request_id, [string]$selected.request_id, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }
        [void]$retainedItems.Add($item)
    }

    $remainingQueuedItems = @($retainedItems.ToArray() | Where-Object { [string]$_.status -eq 'queued' })
    $nextTask = @($remainingQueuedItems | Sort-Object -Property @{ Expression = { Get-TodIntakePriorityRank -Priority ([string]$_.priority) }; Descending = $true }, @{ Expression = { [string]$_.received_at }; Descending = $false } | Select-Object -First 1)
    $newActiveLane = [pscustomobject]@{
        generated_at = Get-UtcNow
        packet_type = 'tod-active-execution-lane-v1'
        request_id = [string]$selected.request_id
        task_id = [string]$selected.task_id
        objective_id = [string]$selected.objective_id
        source = [string]$selected.source
        priority = [string]$selected.priority
        status = 'active'
        started_at = Get-UtcNow
        relation_to_previous_active = 'dequeue_after_completion'
        previous_active_task_id = if ($activeLane -and $activeLane.PSObject.Properties['task_id']) { [string]$activeLane.task_id } else { '' }
    }

    $queueOut = [pscustomobject]@{
        generated_at = Get-UtcNow
        packet_type = 'tod-intake-queue-v1'
        active_task_id = [string]$newActiveLane.task_id
        count = @($retainedItems.ToArray()).Count
        queued_count = @($remainingQueuedItems).Count
        next_task_after_current = if (@($nextTask).Count -gt 0) { $nextTask[0] } else { $null }
        items = @($retainedItems.ToArray())
    }

    $arbitration = [pscustomobject]@{
        generated_at = Get-UtcNow
        packet_type = 'tod-intake-arbitration-v1'
        decision = 'dequeue_after_completion'
        reason = 'prior_active_execution_lane_reached_terminal_status'
        relation_to_active_task = 'continuation'
        prior_active_task = $activeLane
        prior_active_terminal_status = $terminalStatus
        selected_task = $selected
        remaining_queue_count = @($remainingQueuedItems).Count
        active_lane = $newActiveLane
        queue_path = Get-TodIntakeArtifactPath -FileName $todIntakeQueueFileName
        priority_order = @('emergency_stop/operator_cancel', 'operator_admin_repair', 'operator_direct_objective', 'active_task_continuation', 'mim_request', 'watchdog_recovery', 'scheduled_maintenance', 'informational_chat')
    }

    Write-TodIntakeArtifact -FileName $todActiveExecutionLaneFileName -Payload $newActiveLane | Out-Null
    Write-TodIntakeArtifact -FileName $todIntakeQueueFileName -Payload $queueOut | Out-Null
    Write-TodIntakeArtifact -FileName $todIntakeArbitrationFileName -Payload $arbitration | Out-Null

    $priorTaskId = if ($activeLane -and $activeLane.PSObject.Properties['task_id']) { [string]$activeLane.task_id } else { '' }
    $priorObjectiveId = if ($activeLane -and $activeLane.PSObject.Properties['objective_id']) { [string]$activeLane.objective_id } else { '' }
    Publish-TodActivityEvent -EventType 'active_lane_completed' -ObjectiveId $priorObjectiveId -TaskId $priorTaskId -RequestId $(if ($activeLane -and $activeLane.PSObject.Properties['request_id']) { [string]$activeLane.request_id } else { '' }) -CorrelationId '' -Title 'TOD active execution lane completed' -Status $terminalStatus -Message 'TOD active execution lane reached a drainable terminal state.' -Details ([ordered]@{ prior_active_task = $activeLane; terminal_status = $terminalStatus }) -Source 'tod.intake' -Surface 'tod-intake' -Summary 'Active lane terminal state detected.' -CurrentAction 'Preparing to drain one queued intake task.' | Out-Null
    Publish-TodActivityEvent -EventType 'queued_task_selected' -ObjectiveId ([string]$selected.objective_id) -TaskId ([string]$selected.task_id) -RequestId ([string]$selected.request_id) -CorrelationId '' -Title ([string]$selected.title) -Status 'selected' -Message 'Selected the next eligible queued intake task after active completion.' -Details ([ordered]@{ selected_task = $selected; remaining_queue_count = @($remainingQueuedItems).Count }) -Source 'tod.intake' -Surface 'tod-intake' -Summary ([string]$selected.summary) -CurrentAction 'Selected queued task for active lane promotion.' | Out-Null
    Publish-TodActivityEvent -EventType 'queued_task_claimed' -ObjectiveId ([string]$selected.objective_id) -TaskId ([string]$selected.task_id) -RequestId ([string]$selected.request_id) -CorrelationId '' -Title ([string]$selected.title) -Status 'claimed' -Message 'Claimed the selected queued intake task.' -Details ([ordered]@{ selected_task = $selected }) -Source 'tod.intake' -Surface 'tod-intake' -Summary ([string]$selected.summary) -CurrentAction 'Claimed queued task for the single active execution lane.' | Out-Null
    Publish-TodActivityEvent -EventType 'queued_task_started' -ObjectiveId ([string]$selected.objective_id) -TaskId ([string]$selected.task_id) -RequestId ([string]$selected.request_id) -CorrelationId '' -Title ([string]$selected.title) -Status 'started' -Message 'Promoted the selected queued intake task into TOD_ACTIVE_EXECUTION_LANE.' -Details ([ordered]@{ selected_task = $selected; active_lane = $newActiveLane }) -Source 'tod.intake' -Surface 'tod-intake' -Summary ([string]$selected.summary) -CurrentAction 'Started queued task by promoting it to the active lane.' | Out-Null

    return [pscustomobject]@{
        drained = $true
        decision = 'dequeue_after_completion'
        reason = 'prior_active_execution_lane_reached_terminal_status'
        prior_active_task = $activeLane
        selected_task = $selected
        active_lane = $newActiveLane
        remaining_queue_count = @($remainingQueuedItems).Count
        queue = $queueOut
        arbitration = $arbitration
    }
}

function Get-TodParsedUtcDateTime {
    param([AllowEmptyString()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    [datetime]$parsed = [datetime]::MinValue
    if ([datetime]::TryParse($Value, [ref]$parsed)) {
        return $parsed.ToUniversalTime()
    }

    return $null
}

function Get-TodObjectValue {
    param(
        [AllowNull()]$InputObject,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) {
            return $InputObject[$Name]
        }
        return $null
    }

    if ($InputObject.PSObject.Properties[$Name]) {
        return $InputObject.$Name
    }

    return $null
}

function Get-TodExecutionArtifactLane {
    param([AllowNull()]$Payload)

    if ($null -eq $Payload) {
        return [pscustomobject]@{
            objective_id = ''
            normalized_objective_id = ''
            task_id = ''
            request_id = ''
            correlation_id = ''
            generated_at = ''
            override_marker = ''
        }
    }

    $summaryPayload = Get-TodObjectValue -InputObject $Payload -Name 'summary'
    $liveTaskPayload = Get-TodObjectValue -InputObject $Payload -Name 'live_task_request'
    $activeObjectivePayload = Get-TodObjectValue -InputObject $Payload -Name 'active_objective'
    $objectivePayload = Get-TodObjectValue -InputObject $Payload -Name 'objective'
    $activeTaskPayload = Get-TodObjectValue -InputObject $Payload -Name 'active_task'
    $taskPayload = Get-TodObjectValue -InputObject $Payload -Name 'task'
    $metadataPayload = Get-TodObjectValue -InputObject $Payload -Name 'metadata'

    $objectiveId = ''
    foreach ($candidate in @(
        $(if ($null -ne (Get-TodObjectValue -InputObject $Payload -Name 'objective_id')) { [string](Get-TodObjectValue -InputObject $Payload -Name 'objective_id') } else { '' }),
        $(if ($null -ne (Get-TodObjectValue -InputObject $Payload -Name 'source_objective')) { [string](Get-TodObjectValue -InputObject $Payload -Name 'source_objective') } else { '' }),
        $(if ($null -ne (Get-TodObjectValue -InputObject $activeObjectivePayload -Name 'id')) { [string](Get-TodObjectValue -InputObject $activeObjectivePayload -Name 'id') } else { '' }),
        $(if ($null -ne (Get-TodObjectValue -InputObject $objectivePayload -Name 'id')) { [string](Get-TodObjectValue -InputObject $objectivePayload -Name 'id') } else { '' }),
        $(if ($null -ne (Get-TodObjectValue -InputObject $summaryPayload -Name 'objective_id')) { [string](Get-TodObjectValue -InputObject $summaryPayload -Name 'objective_id') } else { '' }),
        $(if ($null -ne (Get-TodObjectValue -InputObject $liveTaskPayload -Name 'objective_id')) { [string](Get-TodObjectValue -InputObject $liveTaskPayload -Name 'objective_id') } else { '' })
    )) {
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            $objectiveId = $candidate
            break
        }
    }

    $taskId = ''
    foreach ($candidate in @(
        $(if ($null -ne (Get-TodObjectValue -InputObject $Payload -Name 'task_id')) { [string](Get-TodObjectValue -InputObject $Payload -Name 'task_id') } else { '' }),
        $(if ($null -ne (Get-TodObjectValue -InputObject $Payload -Name 'selected_task_id')) { [string](Get-TodObjectValue -InputObject $Payload -Name 'selected_task_id') } else { '' }),
        $(if ($null -ne (Get-TodObjectValue -InputObject $activeTaskPayload -Name 'id')) { [string](Get-TodObjectValue -InputObject $activeTaskPayload -Name 'id') } else { '' }),
        $(if ($null -ne (Get-TodObjectValue -InputObject $taskPayload -Name 'id')) { [string](Get-TodObjectValue -InputObject $taskPayload -Name 'id') } else { '' }),
        $(if ($null -ne (Get-TodObjectValue -InputObject $summaryPayload -Name 'task_id')) { [string](Get-TodObjectValue -InputObject $summaryPayload -Name 'task_id') } else { '' }),
        $(if ($null -ne (Get-TodObjectValue -InputObject $liveTaskPayload -Name 'task_id')) { [string](Get-TodObjectValue -InputObject $liveTaskPayload -Name 'task_id') } else { '' })
    )) {
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            $taskId = $candidate
            break
        }
    }

    $requestId = ''
    foreach ($candidate in @(
        $(if ($null -ne (Get-TodObjectValue -InputObject $Payload -Name 'request_id')) { [string](Get-TodObjectValue -InputObject $Payload -Name 'request_id') } else { '' }),
        $(if ($null -ne (Get-TodObjectValue -InputObject $summaryPayload -Name 'request_id')) { [string](Get-TodObjectValue -InputObject $summaryPayload -Name 'request_id') } else { '' }),
        $(if ($null -ne (Get-TodObjectValue -InputObject $liveTaskPayload -Name 'request_id')) { [string](Get-TodObjectValue -InputObject $liveTaskPayload -Name 'request_id') } else { '' })
    )) {
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            $requestId = $candidate
            break
        }
    }

    $correlationId = ''
    foreach ($candidate in @(
        $(if ($null -ne (Get-TodObjectValue -InputObject $Payload -Name 'correlation_id')) { [string](Get-TodObjectValue -InputObject $Payload -Name 'correlation_id') } else { '' }),
        $(if ($null -ne (Get-TodObjectValue -InputObject $summaryPayload -Name 'correlation_id')) { [string](Get-TodObjectValue -InputObject $summaryPayload -Name 'correlation_id') } else { '' }),
        $(if ($null -ne (Get-TodObjectValue -InputObject $liveTaskPayload -Name 'correlation_id')) { [string](Get-TodObjectValue -InputObject $liveTaskPayload -Name 'correlation_id') } else { '' })
    )) {
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            $correlationId = $candidate
            break
        }
    }

    $generatedAt = ''
    foreach ($candidate in @(
        $(if ($null -ne (Get-TodObjectValue -InputObject $Payload -Name 'generated_at')) { [string](Get-TodObjectValue -InputObject $Payload -Name 'generated_at') } else { '' }),
        $(if ($null -ne (Get-TodObjectValue -InputObject $Payload -Name 'timestamp')) { [string](Get-TodObjectValue -InputObject $Payload -Name 'timestamp') } else { '' }),
        $(if ($null -ne (Get-TodObjectValue -InputObject $summaryPayload -Name 'latest_execution_at')) { [string](Get-TodObjectValue -InputObject $summaryPayload -Name 'latest_execution_at') } else { '' }),
        $(if ($null -ne (Get-TodObjectValue -InputObject $summaryPayload -Name 'generated_at')) { [string](Get-TodObjectValue -InputObject $summaryPayload -Name 'generated_at') } else { '' }),
        $(if ($null -ne (Get-TodObjectValue -InputObject $liveTaskPayload -Name 'generated_at')) { [string](Get-TodObjectValue -InputObject $liveTaskPayload -Name 'generated_at') } else { '' })
    )) {
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            $generatedAt = $candidate
            break
        }
    }

    $overrideMarker = ''
    foreach ($candidate in @(
        $(if ($null -ne (Get-TodObjectValue -InputObject $Payload -Name 'publish_override_marker')) { [string](Get-TodObjectValue -InputObject $Payload -Name 'publish_override_marker') } else { '' }),
        $(if ($null -ne (Get-TodObjectValue -InputObject $Payload -Name 'override_marker')) { [string](Get-TodObjectValue -InputObject $Payload -Name 'override_marker') } else { '' }),
        $(if ($null -ne (Get-TodObjectValue -InputObject $metadataPayload -Name 'publish_override_marker')) { [string](Get-TodObjectValue -InputObject $metadataPayload -Name 'publish_override_marker') } else { '' }),
        $(if ($null -ne (Get-TodObjectValue -InputObject $metadataPayload -Name 'override_marker')) { [string](Get-TodObjectValue -InputObject $metadataPayload -Name 'override_marker') } else { '' })
    )) {
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            $overrideMarker = $candidate
            break
        }
    }

    return [pscustomobject]@{
        objective_id = $objectiveId
        normalized_objective_id = Get-NormalizedObjectiveToken -ObjectiveId $objectiveId
        task_id = $taskId
        request_id = $requestId
        correlation_id = $correlationId
        generated_at = $generatedAt
        override_marker = $overrideMarker
    }
}

function Get-TodCanonicalPublishContext {
    param([Parameter(Mandatory = $true)][string]$Path)

    $targetDir = Split-Path -Parent $Path
    $sharedTruthCandidatePaths = @(
        (Join-Path $targetDir 'TOD_MIM_SHARED_TRUTH.latest.json')
    )
    if (-not [string]::IsNullOrWhiteSpace($repoRoot)) {
        $targetFullPath = [System.IO.Path]::GetFullPath($Path)
        $repoRuntimeSharedRoot = [System.IO.Path]::GetFullPath((Join-Path $repoRoot 'runtime/shared'))
        $tmpRemoteRuntimeSharedRoot = [System.IO.Path]::GetFullPath((Join-Path $repoRoot 'tmp_remote_mim/runtime/shared'))
        $shouldUseRepoFallback = $targetFullPath.StartsWith($repoRuntimeSharedRoot, [System.StringComparison]::OrdinalIgnoreCase) -or $targetFullPath.StartsWith($tmpRemoteRuntimeSharedRoot, [System.StringComparison]::OrdinalIgnoreCase)
    }
    if (-not [string]::IsNullOrWhiteSpace($repoRoot) -and $shouldUseRepoFallback) {
        $sharedTruthCandidatePaths += (Join-Path $repoRoot 'runtime/shared/TOD_MIM_SHARED_TRUTH.latest.json')
    }

    $sharedTruthPayload = $null
    $sharedTruthPath = ''
    foreach ($candidatePath in @($sharedTruthCandidatePaths | Select-Object -Unique)) {
        $candidatePayload = Read-TodExecutionJsonIfExists -Path $candidatePath
        if ($null -ne $candidatePayload) {
            $sharedTruthPayload = $candidatePayload
            $sharedTruthPath = $candidatePath
            break
        }
    }

    $canonicalLane = Get-TodExecutionArtifactLane -Payload $sharedTruthPayload
    $canonicalAvailable = (-not [string]::IsNullOrWhiteSpace([string]$canonicalLane.normalized_objective_id)) -or (-not [string]::IsNullOrWhiteSpace([string]$canonicalLane.task_id)) -or (-not [string]::IsNullOrWhiteSpace([string]$canonicalLane.request_id))

    $integrationStatusPayload = $null
    if (-not [string]::IsNullOrWhiteSpace($repoRoot)) {
        $integrationStatusPayload = Read-TodExecutionJsonIfExists -Path (Join-Path $repoRoot 'shared_state/integration_status.json')
    }

    $liveTaskRequestPayload = if ($integrationStatusPayload -and $integrationStatusPayload.PSObject.Properties['live_task_request']) { $integrationStatusPayload.live_task_request } else { $null }
    $formalProgramTruthPayload = if ($integrationStatusPayload -and $integrationStatusPayload.PSObject.Properties['mim_handshake'] -and $integrationStatusPayload.mim_handshake -and $integrationStatusPayload.mim_handshake.PSObject.Properties['source_of_truth'] -and $integrationStatusPayload.mim_handshake.source_of_truth -and $integrationStatusPayload.mim_handshake.source_of_truth.PSObject.Properties['formal_program_truth']) { $integrationStatusPayload.mim_handshake.source_of_truth.formal_program_truth } else { $null }

    return [pscustomobject]@{
        available = $canonicalAvailable
        shared_truth_path = $sharedTruthPath
        canonical_lane_source = if ($sharedTruthPayload -and $sharedTruthPayload.PSObject.Properties['canonical_lane_source']) { [string]$sharedTruthPayload.canonical_lane_source } else { '' }
        canonical = $canonicalLane
        live_task_request = Get-TodExecutionArtifactLane -Payload $liveTaskRequestPayload
        formal_program_truth = Get-TodExecutionArtifactLane -Payload $formalProgramTruthPayload
    }
}

function Test-TodArtifactMatchesCanonicalLane {
    param(
        [Parameter(Mandatory = $true)]$Outgoing,
        [Parameter(Mandatory = $true)]$Canonical
    )

    if (-not [string]::IsNullOrWhiteSpace([string]$Canonical.request_id) -and -not [string]::IsNullOrWhiteSpace([string]$Outgoing.request_id) -and [string]$Canonical.request_id -eq [string]$Outgoing.request_id) {
        return $true
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$Canonical.correlation_id) -and -not [string]::IsNullOrWhiteSpace([string]$Outgoing.correlation_id) -and [string]$Canonical.correlation_id -eq [string]$Outgoing.correlation_id) {
        return $true
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$Canonical.task_id) -and -not [string]::IsNullOrWhiteSpace([string]$Outgoing.task_id) -and [string]$Canonical.task_id -eq [string]$Outgoing.task_id) {
        return $true
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$Canonical.normalized_objective_id) -and -not [string]::IsNullOrWhiteSpace([string]$Outgoing.normalized_objective_id) -and [string]$Canonical.normalized_objective_id -eq [string]$Outgoing.normalized_objective_id) {
        if ([string]::IsNullOrWhiteSpace([string]$Canonical.task_id) -or [string]::IsNullOrWhiteSpace([string]$Outgoing.task_id) -or [string]$Canonical.task_id -eq [string]$Outgoing.task_id) {
            return $true
        }
    }

    return $false
}

function Test-TodLatestArtifactPublishGate {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Payload
    )

    $artifactName = [System.IO.Path]::GetFileName($Path)
    $gatedArtifactNames = @(
        'TOD_ACTIVE_OBJECTIVE.latest.json',
        'TOD_ACTIVE_TASK.latest.json',
        'TOD_ACTIVITY_STREAM.latest.json',
        'TOD_NEXT_TASK_SELECTION.latest.json',
        'TOD_VALIDATION_RESULT.latest.json',
        'TOD_EXECUTION_RESULT.latest.json',
        'TOD_EXECUTION_TRUTH.latest.json'
    )

    $outgoingLane = Get-TodExecutionArtifactLane -Payload $Payload
    if ($gatedArtifactNames -notcontains $artifactName) {
        return [pscustomobject]@{ allow = $true; path = $Path; artifact_name = $artifactName; outgoing = $outgoingLane; reason = 'artifact_not_gated' }
    }

    $hasOutgoingLane = (-not [string]::IsNullOrWhiteSpace([string]$outgoingLane.normalized_objective_id)) -or (-not [string]::IsNullOrWhiteSpace([string]$outgoingLane.task_id)) -or (-not [string]::IsNullOrWhiteSpace([string]$outgoingLane.request_id)) -or (-not [string]::IsNullOrWhiteSpace([string]$outgoingLane.correlation_id))
    if (-not $hasOutgoingLane) {
        return [pscustomobject]@{ allow = $true; path = $Path; artifact_name = $artifactName; outgoing = $outgoingLane; reason = 'missing_outgoing_lane' }
    }

    $canonicalContext = Get-TodCanonicalPublishContext -Path $Path
    if (-not [bool]$canonicalContext.available) {
        return [pscustomobject]@{ allow = $true; path = $Path; artifact_name = $artifactName; outgoing = $outgoingLane; reason = 'missing_canonical_lane' }
    }

    if (Test-TodArtifactMatchesCanonicalLane -Outgoing $outgoingLane -Canonical $canonicalContext.canonical) {
        return [pscustomobject]@{ allow = $true; path = $Path; artifact_name = $artifactName; outgoing = $outgoingLane; canonical = $canonicalContext.canonical; reason = 'canonical_match' }
    }

    $outgoingGeneratedAt = Get-TodParsedUtcDateTime -Value ([string]$outgoingLane.generated_at)
    $canonicalGeneratedAt = Get-TodParsedUtcDateTime -Value ([string]$canonicalContext.canonical.generated_at)
    $overrideMarker = [string]$outgoingLane.override_marker
    if (-not [string]::IsNullOrWhiteSpace($overrideMarker)) {
        $overrideAllowed = $true
        if ($null -ne $canonicalGeneratedAt -and $null -ne $outgoingGeneratedAt) {
            $overrideAllowed = ($outgoingGeneratedAt -ge $canonicalGeneratedAt)
        }
        if ($overrideAllowed) {
            return [pscustomobject]@{ allow = $true; path = $Path; artifact_name = $artifactName; outgoing = $outgoingLane; canonical = $canonicalContext.canonical; reason = 'override_marker' }
        }
    }

    return [pscustomobject]@{
        allow = $false
        path = $Path
        artifact_name = $artifactName
        reason = 'noncanonical_lane'
        reason_code = 'stale_publisher_noncanonical_lane'
        outgoing = $outgoingLane
        canonical = $canonicalContext.canonical
        canonical_lane_source = [string]$canonicalContext.canonical_lane_source
        live_task_request = $canonicalContext.live_task_request
        formal_program_truth = $canonicalContext.formal_program_truth
    }
}

function Write-TodBlockedLatestArtifactRecord {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Payload,
        [Parameter(Mandatory = $true)]$GateDecision
    )

    $directory = Split-Path -Parent $Path
    $artifactName = [System.IO.Path]::GetFileName($Path)
    $supersededRoot = Join-Path $directory 'superseded'
    $artifactRoot = Join-Path $supersededRoot $artifactName
    if (-not (Test-Path -Path $artifactRoot)) {
        New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null
    }

    $stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ')
    $record = [ordered]@{
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        reason_code = if ($GateDecision.PSObject.Properties['reason_code']) { [string]$GateDecision.reason_code } else { 'stale_publisher_noncanonical_lane' }
        artifact_name = $artifactName
        target_path = $Path
        canonical_lane_source = if ($GateDecision.PSObject.Properties['canonical_lane_source']) { [string]$GateDecision.canonical_lane_source } else { '' }
        canonical_lane = if ($GateDecision.PSObject.Properties['canonical']) { $GateDecision.canonical } else { $null }
        live_task_request = if ($GateDecision.PSObject.Properties['live_task_request']) { $GateDecision.live_task_request } else { $null }
        formal_program_truth = if ($GateDecision.PSObject.Properties['formal_program_truth']) { $GateDecision.formal_program_truth } else { $null }
        outgoing_lane = if ($GateDecision.PSObject.Properties['outgoing']) { $GateDecision.outgoing } else { $null }
        attempted_payload = $Payload
    }

    $recordPath = Join-Path $artifactRoot ("{0}.blocked.json" -f $stamp)
    Write-TodExecutionJsonAtomically -Path $recordPath -Payload $record
    $latestBlockedPath = Join-Path $artifactRoot 'latest.blocked.json'
    Write-TodExecutionJsonAtomically -Path $latestBlockedPath -Payload $record

    return [pscustomobject]@{
        record_path = $recordPath
        latest_blocked_path = $latestBlockedPath
    }
}

function Get-TodActivityStreamEventLimit {
    return 80
}

function New-TodActivityEventRecord {
    param(
        [Parameter(Mandatory = $true)][string]$EventType,
        [AllowEmptyString()][string]$Timestamp,
        [AllowEmptyString()][string]$ObjectiveId,
        [AllowEmptyString()][string]$TaskId,
        [AllowEmptyString()][string]$Step,
        [AllowEmptyString()][string]$Status,
        [AllowEmptyString()][string]$Message,
        [AllowNull()]$Details,
        [AllowEmptyString()][string]$RequestId,
        [AllowEmptyString()][string]$ExecutionId,
        [AllowEmptyString()][string]$CorrelationId,
        [AllowEmptyString()][string]$Title,
        [AllowEmptyString()][string]$Source,
        [AllowEmptyString()][string]$Surface
    )

    $resolvedTimestamp = if ([string]::IsNullOrWhiteSpace($Timestamp)) { Get-UtcNow } else { [string]$Timestamp }
    $resolvedDetails = if ($null -eq $Details) { [pscustomobject]@{} } else { $Details }

    return [ordered]@{
        timestamp = $resolvedTimestamp
        event_type = [string]$EventType
        objective_id = [string]$ObjectiveId
        normalized_objective_id = Get-NormalizedObjectiveToken -ObjectiveId $ObjectiveId
        task_id = [string]$TaskId
        request_id = [string]$RequestId
        execution_id = [string]$ExecutionId
        correlation_id = [string]$CorrelationId
        title = [string]$Title
        step = [string]$(if ([string]::IsNullOrWhiteSpace($Step)) { 'activity' } else { $Step })
        status = [string]$(if ([string]::IsNullOrWhiteSpace($Status)) { 'active' } else { $Status })
        message = [string]$Message
        details = $resolvedDetails
        source = [string]$Source
        surface = [string]$Surface
    }
}

function Convert-TodActivityPayloadToStream {
    param([AllowNull()]$Payload)

    if ($null -eq $Payload) {
        return $null
    }

    $packetType = if ($null -ne (Get-TodObjectValue -InputObject $Payload -Name 'packet_type')) { [string](Get-TodObjectValue -InputObject $Payload -Name 'packet_type') } else { '' }
    $generatedAt = if ($null -ne (Get-TodObjectValue -InputObject $Payload -Name 'generated_at')) { [string](Get-TodObjectValue -InputObject $Payload -Name 'generated_at') } else { Get-UtcNow }
    $updatedAt = if ($null -ne (Get-TodObjectValue -InputObject $Payload -Name 'updated_at')) { [string](Get-TodObjectValue -InputObject $Payload -Name 'updated_at') } else { $generatedAt }
    $objectiveId = if ($null -ne (Get-TodObjectValue -InputObject $Payload -Name 'objective_id')) { [string](Get-TodObjectValue -InputObject $Payload -Name 'objective_id') } else { '' }
    $taskId = if ($null -ne (Get-TodObjectValue -InputObject $Payload -Name 'task_id')) { [string](Get-TodObjectValue -InputObject $Payload -Name 'task_id') } else { '' }
    $requestId = if ($null -ne (Get-TodObjectValue -InputObject $Payload -Name 'request_id')) { [string](Get-TodObjectValue -InputObject $Payload -Name 'request_id') } else { '' }
    $executionId = if ($null -ne (Get-TodObjectValue -InputObject $Payload -Name 'execution_id')) { [string](Get-TodObjectValue -InputObject $Payload -Name 'execution_id') } else { '' }
    $correlationId = if ($null -ne (Get-TodObjectValue -InputObject $Payload -Name 'correlation_id')) { [string](Get-TodObjectValue -InputObject $Payload -Name 'correlation_id') } else { '' }
    $title = if ($null -ne (Get-TodObjectValue -InputObject $Payload -Name 'title')) { [string](Get-TodObjectValue -InputObject $Payload -Name 'title') } else { '' }
    $source = if ($null -ne (Get-TodObjectValue -InputObject $Payload -Name 'source')) { [string](Get-TodObjectValue -InputObject $Payload -Name 'source') } else { '' }
    $surface = if ($null -ne (Get-TodObjectValue -InputObject $Payload -Name 'surface')) { [string](Get-TodObjectValue -InputObject $Payload -Name 'surface') } else { '' }
    $summary = if ($null -ne (Get-TodObjectValue -InputObject $Payload -Name 'summary')) { [string](Get-TodObjectValue -InputObject $Payload -Name 'summary') } else { '' }
    $events = @()

    $payloadEvents = Get-TodObjectValue -InputObject $Payload -Name 'events'
    if ($payloadEvents) {
        foreach ($eventItem in @($payloadEvents)) {
            if ($null -eq $eventItem) {
                continue
            }

            $eventType = if ($null -ne (Get-TodObjectValue -InputObject $eventItem -Name 'event_type')) { [string](Get-TodObjectValue -InputObject $eventItem -Name 'event_type') } else { [string](Get-TodObjectValue -InputObject $eventItem -Name 'event') }
            if ([string]::IsNullOrWhiteSpace($eventType)) {
                $eventType = 'activity'
            }

            $eventRecord = [pscustomobject](New-TodActivityEventRecord -EventType $eventType -Timestamp ([string]$(if ($null -ne (Get-TodObjectValue -InputObject $eventItem -Name 'timestamp')) { Get-TodObjectValue -InputObject $eventItem -Name 'timestamp' } else { $generatedAt })) -ObjectiveId ([string]$(if ($null -ne (Get-TodObjectValue -InputObject $eventItem -Name 'objective_id')) { Get-TodObjectValue -InputObject $eventItem -Name 'objective_id' } else { $objectiveId })) -TaskId ([string]$(if ($null -ne (Get-TodObjectValue -InputObject $eventItem -Name 'task_id')) { Get-TodObjectValue -InputObject $eventItem -Name 'task_id' } else { $taskId })) -Step ([string]$(if ($null -ne (Get-TodObjectValue -InputObject $eventItem -Name 'step')) { Get-TodObjectValue -InputObject $eventItem -Name 'step' } else { Get-TodObjectValue -InputObject $Payload -Name 'phase' })) -Status ([string]$(if ($null -ne (Get-TodObjectValue -InputObject $eventItem -Name 'status')) { Get-TodObjectValue -InputObject $eventItem -Name 'status' } else { Get-TodObjectValue -InputObject $Payload -Name 'status' })) -Message ([string]$(if ($null -ne (Get-TodObjectValue -InputObject $eventItem -Name 'message')) { Get-TodObjectValue -InputObject $eventItem -Name 'message' } else { $summary })) -Details (Get-TodObjectValue -InputObject $eventItem -Name 'details') -RequestId ([string]$(if ($null -ne (Get-TodObjectValue -InputObject $eventItem -Name 'request_id')) { Get-TodObjectValue -InputObject $eventItem -Name 'request_id' } else { $requestId })) -ExecutionId ([string]$(if ($null -ne (Get-TodObjectValue -InputObject $eventItem -Name 'execution_id')) { Get-TodObjectValue -InputObject $eventItem -Name 'execution_id' } else { $executionId })) -CorrelationId ([string]$(if ($null -ne (Get-TodObjectValue -InputObject $eventItem -Name 'correlation_id')) { Get-TodObjectValue -InputObject $eventItem -Name 'correlation_id' } else { $correlationId })) -Title ([string]$(if ($null -ne (Get-TodObjectValue -InputObject $eventItem -Name 'title')) { Get-TodObjectValue -InputObject $eventItem -Name 'title' } else { $title })) -Source ([string]$(if ($null -ne (Get-TodObjectValue -InputObject $eventItem -Name 'source')) { Get-TodObjectValue -InputObject $eventItem -Name 'source' } else { $source })) -Surface ([string]$(if ($null -ne (Get-TodObjectValue -InputObject $eventItem -Name 'surface')) { Get-TodObjectValue -InputObject $eventItem -Name 'surface' } else { $surface })))
            $events += ,$eventRecord
        }
    }

    if (@($events).Count -eq 0) {
        $legacyEventType = if ($null -ne (Get-TodObjectValue -InputObject $Payload -Name 'event')) { [string](Get-TodObjectValue -InputObject $Payload -Name 'event') } elseif ($null -ne (Get-TodObjectValue -InputObject $Payload -Name 'event_type')) { [string](Get-TodObjectValue -InputObject $Payload -Name 'event_type') } else { '' }
        if (-not [string]::IsNullOrWhiteSpace($legacyEventType)) {
            $legacyEvent = [pscustomobject](New-TodActivityEventRecord -EventType $legacyEventType -Timestamp $generatedAt -ObjectiveId $objectiveId -TaskId $taskId -Step ([string]$(if ($null -ne (Get-TodObjectValue -InputObject $Payload -Name 'phase')) { Get-TodObjectValue -InputObject $Payload -Name 'phase' } else { 'activity' })) -Status ([string]$(if ($null -ne (Get-TodObjectValue -InputObject $Payload -Name 'status')) { Get-TodObjectValue -InputObject $Payload -Name 'status' } else { 'active' })) -Message ([string]$(if (-not [string]::IsNullOrWhiteSpace([string](Get-TodObjectValue -InputObject $Payload -Name 'current_action'))) { Get-TodObjectValue -InputObject $Payload -Name 'current_action' } elseif (-not [string]::IsNullOrWhiteSpace($summary)) { $summary } else { $legacyEventType })) -Details ([ordered]@{
                summary = $summary
                next_step = [string](Get-TodObjectValue -InputObject $Payload -Name 'next_step')
                next_validation = [string](Get-TodObjectValue -InputObject $Payload -Name 'next_validation')
                execution_state = [string](Get-TodObjectValue -InputObject $Payload -Name 'execution_state')
                execution_evidence = Get-TodObjectValue -InputObject $Payload -Name 'execution_evidence'
                recovery_state = [string](Get-TodObjectValue -InputObject $Payload -Name 'recovery_state')
            }) -RequestId $requestId -ExecutionId $executionId -CorrelationId $correlationId -Title $title -Source $source -Surface $surface)
            $events = @($legacyEvent)
        }
    }

    $latestEvent = @($events | Select-Object -Last 1)
    $latestEvent = if (@($latestEvent).Count -gt 0) { $latestEvent[0] } else { $null }
    $resolvedPacketType = if ([string]::IsNullOrWhiteSpace($packetType)) { 'tod-activity-stream-v1' } else { $packetType }

    return [ordered]@{
        generated_at = $generatedAt
        updated_at = $updatedAt
        source = $source
        surface = $surface
        session_key = [string](Get-TodObjectValue -InputObject $Payload -Name 'session_key')
        request_id = $requestId
        task_id = $taskId
        execution_id = $executionId
        correlation_id = $correlationId
        objective_id = $objectiveId
        normalized_objective_id = Get-NormalizedObjectiveToken -ObjectiveId $objectiveId
        title = $title
        summary = $summary
        packet_type = $resolvedPacketType
        event = if ($latestEvent) { [string]$latestEvent.event_type } else { '' }
        status = if ($latestEvent) { [string]$latestEvent.status } else { [string](Get-TodObjectValue -InputObject $Payload -Name 'status') }
        phase = if ($latestEvent) { [string]$latestEvent.step } else { [string](Get-TodObjectValue -InputObject $Payload -Name 'phase') }
        current_action = [string](Get-TodObjectValue -InputObject $Payload -Name 'current_action')
        next_step = [string](Get-TodObjectValue -InputObject $Payload -Name 'next_step')
        next_validation = [string](Get-TodObjectValue -InputObject $Payload -Name 'next_validation')
        execution_state = [string](Get-TodObjectValue -InputObject $Payload -Name 'execution_state')
        execution_evidence = Get-TodObjectValue -InputObject $Payload -Name 'execution_evidence'
        recovery_state = [string](Get-TodObjectValue -InputObject $Payload -Name 'recovery_state')
        latest_event = $latestEvent
        events = @($events)
    }
}

function Merge-TodActivityStreamPayload {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Payload
    )

    $existingStream = Convert-TodActivityPayloadToStream -Payload (Read-TodExecutionJsonIfExists -Path $Path)
    $incomingStream = Convert-TodActivityPayloadToStream -Payload $Payload
    if ($null -eq $incomingStream) {
        return $Payload
    }

    $mergedEvents = @()
    if ($existingStream -and $existingStream.PSObject.Properties['events']) {
        $mergedEvents += @($existingStream.events)
    }
    if ($incomingStream.PSObject.Properties['events']) {
        $mergedEvents += @($incomingStream.events)
    }

    $eventLimit = Get-TodActivityStreamEventLimit
    if (@($mergedEvents).Count -gt $eventLimit) {
        $mergedEvents = @($mergedEvents | Select-Object -Last $eventLimit)
    }

    $latestEvent = @($mergedEvents | Select-Object -Last 1)
    $latestEvent = if (@($latestEvent).Count -gt 0) { $latestEvent[0] } else { $null }
    $summary = if (-not [string]::IsNullOrWhiteSpace([string]$incomingStream.summary)) { [string]$incomingStream.summary } elseif ($existingStream) { [string]$existingStream.summary } elseif ($latestEvent) { [string]$latestEvent.message } else { '' }
    $objectiveId = if ($latestEvent -and -not [string]::IsNullOrWhiteSpace([string]$latestEvent.objective_id)) { [string]$latestEvent.objective_id } elseif (-not [string]::IsNullOrWhiteSpace([string]$incomingStream.objective_id)) { [string]$incomingStream.objective_id } elseif ($existingStream) { [string]$existingStream.objective_id } else { '' }
    $taskId = if ($latestEvent -and -not [string]::IsNullOrWhiteSpace([string]$latestEvent.task_id)) { [string]$latestEvent.task_id } elseif (-not [string]::IsNullOrWhiteSpace([string]$incomingStream.task_id)) { [string]$incomingStream.task_id } elseif ($existingStream) { [string]$existingStream.task_id } else { '' }
    $requestId = if ($latestEvent -and -not [string]::IsNullOrWhiteSpace([string]$latestEvent.request_id)) { [string]$latestEvent.request_id } elseif (-not [string]::IsNullOrWhiteSpace([string]$incomingStream.request_id)) { [string]$incomingStream.request_id } elseif ($existingStream) { [string]$existingStream.request_id } else { '' }
    $executionId = if ($latestEvent -and -not [string]::IsNullOrWhiteSpace([string]$latestEvent.execution_id)) { [string]$latestEvent.execution_id } elseif (-not [string]::IsNullOrWhiteSpace([string]$incomingStream.execution_id)) { [string]$incomingStream.execution_id } elseif ($existingStream) { [string]$existingStream.execution_id } else { '' }
    $correlationId = if ($latestEvent -and -not [string]::IsNullOrWhiteSpace([string]$latestEvent.correlation_id)) { [string]$latestEvent.correlation_id } elseif (-not [string]::IsNullOrWhiteSpace([string]$incomingStream.correlation_id)) { [string]$incomingStream.correlation_id } elseif ($existingStream) { [string]$existingStream.correlation_id } else { '' }

    return [ordered]@{
        generated_at = if ($existingStream -and -not [string]::IsNullOrWhiteSpace([string]$existingStream.generated_at)) { [string]$existingStream.generated_at } else { [string]$incomingStream.generated_at }
        updated_at = if ($latestEvent) { [string]$latestEvent.timestamp } else { [string]$incomingStream.updated_at }
        source = if (-not [string]::IsNullOrWhiteSpace([string]$incomingStream.source)) { [string]$incomingStream.source } elseif ($existingStream) { [string]$existingStream.source } else { '' }
        surface = if (-not [string]::IsNullOrWhiteSpace([string]$incomingStream.surface)) { [string]$incomingStream.surface } elseif ($existingStream) { [string]$existingStream.surface } else { '' }
        session_key = if (-not [string]::IsNullOrWhiteSpace([string]$incomingStream.session_key)) { [string]$incomingStream.session_key } elseif ($existingStream) { [string]$existingStream.session_key } else { '' }
        request_id = $requestId
        task_id = $taskId
        execution_id = $executionId
        correlation_id = $correlationId
        objective_id = $objectiveId
        normalized_objective_id = Get-NormalizedObjectiveToken -ObjectiveId $objectiveId
        title = if ($latestEvent -and -not [string]::IsNullOrWhiteSpace([string]$latestEvent.title)) { [string]$latestEvent.title } elseif (-not [string]::IsNullOrWhiteSpace([string]$incomingStream.title)) { [string]$incomingStream.title } elseif ($existingStream) { [string]$existingStream.title } else { '' }
        summary = $summary
        packet_type = 'tod-activity-stream-v1'
        event = if ($latestEvent) { [string]$latestEvent.event_type } else { [string]$incomingStream.event }
        status = if ($latestEvent) { [string]$latestEvent.status } else { [string]$incomingStream.status }
        phase = if ($latestEvent) { [string]$latestEvent.step } else { [string]$incomingStream.phase }
        current_action = if (-not [string]::IsNullOrWhiteSpace([string]$incomingStream.current_action)) { [string]$incomingStream.current_action } elseif ($latestEvent) { [string]$latestEvent.message } elseif ($existingStream) { [string]$existingStream.current_action } else { '' }
        next_step = if (-not [string]::IsNullOrWhiteSpace([string]$incomingStream.next_step)) { [string]$incomingStream.next_step } elseif ($existingStream) { [string]$existingStream.next_step } else { '' }
        next_validation = if (-not [string]::IsNullOrWhiteSpace([string]$incomingStream.next_validation)) { [string]$incomingStream.next_validation } elseif ($existingStream) { [string]$existingStream.next_validation } else { '' }
        execution_state = if (-not [string]::IsNullOrWhiteSpace([string]$incomingStream.execution_state)) { [string]$incomingStream.execution_state } elseif ($existingStream) { [string]$existingStream.execution_state } else { '' }
        execution_evidence = if ($null -ne $incomingStream.execution_evidence) { $incomingStream.execution_evidence } elseif ($latestEvent) { $latestEvent.details } elseif ($existingStream) { $existingStream.execution_evidence } else { $null }
        recovery_state = if (-not [string]::IsNullOrWhiteSpace([string]$incomingStream.recovery_state)) { [string]$incomingStream.recovery_state } elseif ($existingStream) { [string]$existingStream.recovery_state } else { '' }
        latest_event = $latestEvent
        events = @($mergedEvents)
    }
}

function Publish-TodActivityEvent {
    param(
        [Parameter(Mandatory = $true)][string]$EventType,
        [AllowEmptyString()][string]$ObjectiveId,
        [AllowEmptyString()][string]$TaskId,
        [AllowEmptyString()][string]$RequestId,
        [AllowEmptyString()][string]$ExecutionId,
        [AllowEmptyString()][string]$CorrelationId,
        [AllowEmptyString()][string]$Title,
        [AllowEmptyString()][string]$Step,
        [AllowEmptyString()][string]$Status,
        [AllowEmptyString()][string]$Message,
        [AllowNull()]$Details,
        [AllowEmptyString()][string]$Source = 'tod.run-task',
        [AllowEmptyString()][string]$Surface = 'tod-run-task',
        [AllowEmptyString()][string]$Summary = '',
        [AllowEmptyString()][string]$CurrentAction = '',
        [AllowEmptyString()][string]$NextStep = '',
        [AllowEmptyString()][string]$NextValidation = '',
        [AllowEmptyString()][string]$ExecutionState = '',
        [AllowEmptyString()][string]$RecoveryState = ''
    )

    $eventRecord = [pscustomobject](New-TodActivityEventRecord -EventType $EventType -Timestamp (Get-UtcNow) -ObjectiveId $ObjectiveId -TaskId $TaskId -Step $Step -Status $Status -Message $Message -Details $Details -RequestId $RequestId -ExecutionId $ExecutionId -CorrelationId $CorrelationId -Title $Title -Source $Source -Surface $Surface)
    $payload = [ordered]@{
        generated_at = [string]$eventRecord.timestamp
        updated_at = [string]$eventRecord.timestamp
        source = $Source
        surface = $Surface
        session_key = 'tod-live-activity'
        request_id = [string]$RequestId
        task_id = [string]$TaskId
        execution_id = [string]$ExecutionId
        correlation_id = [string]$CorrelationId
        objective_id = [string]$ObjectiveId
        normalized_objective_id = Get-NormalizedObjectiveToken -ObjectiveId $ObjectiveId
        title = [string]$Title
        summary = if ([string]::IsNullOrWhiteSpace($Summary)) { [string]$Message } else { [string]$Summary }
        packet_type = 'tod-activity-stream-v1'
        event = [string]$EventType
        status = [string]$(if ([string]::IsNullOrWhiteSpace($Status)) { 'active' } else { $Status })
        phase = [string]$(if ([string]::IsNullOrWhiteSpace($Step)) { 'activity' } else { $Step })
        current_action = if ([string]::IsNullOrWhiteSpace($CurrentAction)) { [string]$Message } else { [string]$CurrentAction }
        next_step = [string]$NextStep
        next_validation = [string]$NextValidation
        execution_state = [string]$ExecutionState
        execution_evidence = $Details
        recovery_state = [string]$RecoveryState
        latest_event = $eventRecord
        events = @($eventRecord)
    }

    $writtenArtifactPaths = @()
    foreach ($sharedRoot in @(Get-TodExecutionSharedRoots)) {
        $writeResult = Write-TodExecutionSharedJson -Path (Join-Path $sharedRoot 'TOD_ACTIVITY_STREAM.latest.json') -Payload $payload
        if ($writeResult -and $writeResult.PSObject.Properties['written'] -and [bool]$writeResult.written) {
            $writtenArtifactPaths += [string]$writeResult.path
        }
    }

    $runtimeSharedRoot = [System.IO.Path]::GetFullPath((Join-Path $repoRoot 'runtime/shared'))
    $remotePublishPaths = @($writtenArtifactPaths | Where-Object {
        $fullPath = [System.IO.Path]::GetFullPath([string]$_)
        $fullPath.StartsWith($runtimeSharedRoot, [System.StringComparison]::OrdinalIgnoreCase)
    } | Select-Object -Unique)
    if ($remotePublishPaths.Length -gt 0) {
        Publish-RemoteTodExecutionArtifacts -LocalArtifactPaths $remotePublishPaths | Out-Null
    }

    return [pscustomobject]@{
        activity = $payload
        written_paths = @($writtenArtifactPaths)
    }
}

function Write-TodExecutionSharedJson {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Payload
    )

    $payloadToWrite = $Payload
    if ([System.IO.Path]::GetFileName($Path) -eq 'TOD_ACTIVITY_STREAM.latest.json') {
        $payloadToWrite = Merge-TodActivityStreamPayload -Path $Path -Payload $Payload
    }

    $gateDecision = Test-TodLatestArtifactPublishGate -Path $Path -Payload $payloadToWrite
    if (-not [bool]$gateDecision.allow) {
        $blockedRecord = Write-TodBlockedLatestArtifactRecord -Path $Path -Payload $payloadToWrite -GateDecision $gateDecision
        return [pscustomobject]@{
            written = $false
            blocked = $true
            path = $Path
            reason_code = [string]$gateDecision.reason_code
            blocked_record_path = [string]$blockedRecord.record_path
            latest_blocked_path = [string]$blockedRecord.latest_blocked_path
        }
    }

    Write-TodExecutionJsonAtomically -Path $Path -Payload $payloadToWrite
    return [pscustomobject]@{
        written = $true
        blocked = $false
        path = $Path
        reason_code = ''
        blocked_record_path = ''
        latest_blocked_path = ''
    }
}

function Get-NormalizedObjectiveToken {
    param([AllowEmptyString()][string]$ObjectiveId)

    if ([string]::IsNullOrWhiteSpace($ObjectiveId)) {
        return ""
    }

    $match = [regex]::Match($ObjectiveId, '(\d+)$')
    if ($match.Success) {
        return [string]$match.Groups[1].Value
    }

    return [string]$ObjectiveId
}

function Get-LocalExecutionValidationChecks {
    param([Parameter(Mandatory = $true)]$ResultPayload)

    foreach ($finding in @($ResultPayload.structured_findings)) {
        if ($null -ne $finding -and $finding.PSObject.Properties['type'] -and [string]$finding.type -eq 'validation' -and $finding.PSObject.Properties['checks'] -and $finding.checks) {
            return @($finding.checks)
        }
    }

    $checks = @()
    $testsRun = @($ResultPayload.tests_run)
    $testResults = @($ResultPayload.test_results)
    for ($index = 0; $index -lt $testsRun.Count; $index++) {
        $name = [string]$testsRun[$index]
        if ([string]::IsNullOrWhiteSpace($name)) {
            continue
        }
        $result = if ($index -lt $testResults.Count) { [string]$testResults[$index] } else { "" }
        $checks += [pscustomobject]@{
            name = $name
            passed = ($result -eq 'pass')
            required = $true
        }
    }
    return @($checks)
}

function Get-LocalExecutionCommandCapture {
    param([Parameter(Mandatory = $true)]$ResultPayload)

    foreach ($finding in @($ResultPayload.structured_findings)) {
        if ($null -ne $finding -and $finding.PSObject.Properties['type'] -and [string]$finding.type -eq 'command' -and $finding.PSObject.Properties['capture']) {
            return $finding.capture
        }
    }

    return $null
}

function Get-LocalExecutionRollbackState {
    param([Parameter(Mandatory = $true)]$ResultPayload)

    foreach ($finding in @($ResultPayload.structured_findings)) {
        if ($null -ne $finding -and $finding.PSObject.Properties['type'] -and [string]$finding.type -eq 'rollback' -and $finding.PSObject.Properties['rollback']) {
            return $finding.rollback
        }
    }

    return $null
}

function Resolve-LocalExecutionTaskClass {
    param([Parameter(Mandatory = $true)]$Task)

    $explicitValues = @()
    foreach ($fieldName in @('task_class', 'type', 'task_category')) {
        if ($Task.PSObject.Properties[$fieldName] -and -not [string]::IsNullOrWhiteSpace([string]$Task.$fieldName)) {
            $explicitValues += ([string]$Task.$fieldName).Trim().ToLowerInvariant()
        }
    }

    foreach ($value in $explicitValues) {
        switch ($value) {
            'inspection_only' { return 'inspection_only' }
            'report_only' { return 'report_only' }
            'diagnostic_only' { return 'diagnostic_only' }
            'inventory_only' { return 'inventory_only' }
        }
    }

    $blob = (Get-TaskRoutingText -Task $Task).ToLowerInvariant()
    if ($blob -match '\binspection[ _-]?only\b') { return 'inspection_only' }
    if ($blob -match '\breport[ _-]?only\b') { return 'report_only' }
    if ($blob -match '\bdiagnostic[ _-]?only\b') { return 'diagnostic_only' }
    if ($blob -match '\binventory[ _-]?only\b') { return 'inventory_only' }

    return 'implementation'
}

function Test-LocalExecutionPatchRequired {
    param(
        [Parameter(Mandatory = $true)]$Task,
        [string]$TaskClass = ''
    )

    $resolvedTaskClass = if ([string]::IsNullOrWhiteSpace($TaskClass)) { Resolve-LocalExecutionTaskClass -Task $Task } else { [string]$TaskClass }
    if (@('inspection_only', 'report_only', 'diagnostic_only', 'inventory_only') -contains $resolvedTaskClass) {
        return $false
    }

    $taskType = if ($Task.PSObject.Properties['type']) { ([string]$Task.type).ToLowerInvariant() } else { '' }
    $taskCategory = Resolve-TaskCategory -Task $Task
    if (@('code_change', 'refactor', 'test_generation', 'bridge_runtime') -contains $taskCategory) {
        return $true
    }
    if ($taskType -match 'implementation|patch|code_change|refactor|fix') {
        return $true
    }

    $blob = (Get-TaskRoutingText -Task $Task).ToLowerInvariant()
    return ($blob -match '\bpatch\b|\bimplement\b|\brefactor\b|\bmodify\b|\bupdate\b|\bchange\b|\bfix\b|\brewrite\b|\badd\b|\bremove\b')
}

function Get-LocalExecutionNoOpAssessment {
    param(
        [Parameter(Mandatory = $true)]$Task,
        [Parameter(Mandatory = $true)]$ResultPayload
    )

    $taskClass = Resolve-LocalExecutionTaskClass -Task $Task
    $isExempt = @('inspection_only', 'report_only', 'diagnostic_only', 'inventory_only') -contains $taskClass
    $patchRequired = Test-LocalExecutionPatchRequired -Task $Task -TaskClass $taskClass
    $filesChanged = @($ResultPayload.files_changed | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $validationChecks = @(Get-LocalExecutionValidationChecks -ResultPayload $ResultPayload)
    $commandCapture = Get-LocalExecutionCommandCapture -ResultPayload $ResultPayload
    $structuredFindings = @($ResultPayload.structured_findings)

    $captureTextParts = @()
    $commandExitCode = $null
    $commandIndicatesChange = $false
    if ($null -ne $commandCapture) {
        if ($commandCapture.PSObject.Properties['exit_code']) {
            try {
                $commandExitCode = [int]$commandCapture.exit_code
            }
            catch {
                $commandExitCode = $null
            }
        }

        foreach ($fieldName in @('stdout', 'stderr', 'summary', 'command')) {
            if ($commandCapture.PSObject.Properties[$fieldName]) {
                $value = $commandCapture.$fieldName
                if ($value -is [System.Collections.IEnumerable] -and -not ($value -is [string])) {
                    $captureTextParts += @($value | ForEach-Object { [string]$_ })
                }
                else {
                    $captureTextParts += [string]$value
                }
            }
        }

        foreach ($flagName in @('state_changed', 'artifact_changed', 'proves_change', 'meaningful_change', 'changed', 'applied', 'published', 'accepted')) {
            if ($commandCapture.PSObject.Properties[$flagName] -and [bool]$commandCapture.$flagName) {
                $commandIndicatesChange = $true
                break
            }
        }
    }

    $commandEvidenceText = (($captureTextParts | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ' ').Trim()
    $commandOutputProvesWork = (($null -eq $commandExitCode) -or $commandExitCode -eq 0) -and (
        $commandIndicatesChange -or
        ($commandEvidenceText -match '\b(updated|patched|modified|applied|created|wrote|saved|published|migrated|synchronized|deleted|inserted|changed)\b')
    )

    $validationArtifactChanged = $false
    foreach ($check in $validationChecks) {
        if ($null -eq $check) {
            continue
        }

        foreach ($flagName in @('state_changed', 'artifact_changed', 'proves_change', 'meaningful_change', 'changed')) {
            if ($check.PSObject.Properties[$flagName] -and [bool]$check.$flagName) {
                $validationArtifactChanged = $true
                break
            }
        }

        if ($validationArtifactChanged) {
            break
        }
    }

    $resultArtifactChanged = $false
    foreach ($finding in $structuredFindings) {
        if ($null -eq $finding -or -not $finding.PSObject.Properties['type']) {
            continue
        }

        $findingType = ([string]$finding.type).ToLowerInvariant()
        if (@('result_contract', 'result_artifact', 'external_result', 'artifact_result') -notcontains $findingType) {
            continue
        }

        $changedFiles = if ($finding.PSObject.Properties['changed_files']) { @($finding.changed_files | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) } else { @() }
        $evidenceText = ''
        foreach ($fieldName in @('evidence', 'action_taken', 'summary', 'artifact_path', 'validation_result')) {
            if ($finding.PSObject.Properties[$fieldName]) {
                $value = $finding.$fieldName
                if ($value -is [System.Collections.IEnumerable] -and -not ($value -is [string])) {
                    $evidenceText += ' ' + ((@($value | ForEach-Object { [string]$_ }) -join ' '))
                }
                else {
                    $evidenceText += ' ' + ([string]$value)
                }
            }
        }

        foreach ($flagName in @('accepted', 'published', 'persisted', 'artifact_changed', 'state_changed', 'proves_change', 'meaningful_change', 'changed', 'applied')) {
            if ($finding.PSObject.Properties[$flagName] -and [bool]$finding.$flagName) {
                $resultArtifactChanged = $true
                break
            }
        }

        if (-not $resultArtifactChanged -and @($changedFiles).Count -gt 0) {
            $resultArtifactChanged = $true
        }
        if (-not $resultArtifactChanged -and $evidenceText -match '\b(updated|patched|modified|applied|created|wrote|saved|published|migrated|synchronized|deleted|inserted|changed)\b') {
            $resultArtifactChanged = $true
        }

        if ($resultArtifactChanged) {
            break
        }
    }

    $meaningfulEvidence = @()
    if (@($filesChanged).Count -gt 0) { $meaningfulEvidence += 'files_changed' }
    if ($commandOutputProvesWork) { $meaningfulEvidence += 'command_output' }
    if ($validationArtifactChanged) { $meaningfulEvidence += 'validation_artifact' }
    if ($resultArtifactChanged) { $meaningfulEvidence += 'result_artifact' }
    $meaningfulEvidence = @($meaningfulEvidence)
    $hasAlternativeEvidence = $commandOutputProvesWork -or $validationArtifactChanged -or $resultArtifactChanged

    $patchWriterStatus = if (@($filesChanged).Count -gt 0) { 'completed' } elseif ($hasAlternativeEvidence) { 'evidence_only' } else { 'not_needed' }
    $patchWriterRejected = $patchRequired -and [string]::Equals($patchWriterStatus, 'not_needed', [System.StringComparison]::OrdinalIgnoreCase)
    $noMeaningfulEvidence = (@($meaningfulEvidence).Count -eq 0)
    $detected = (-not $isExempt) -and ($patchWriterRejected -or $noMeaningfulEvidence)
    $detail = if ($patchWriterRejected) {
        'Patch-required task produced no changed files, so patch_writer.status=not_needed is not valid completion evidence.'
    }
    elseif ($noMeaningfulEvidence) {
        'Execution produced no meaningful files, command evidence, validation change, or accepted result artifact.'
    }
    else {
        ''
    }

    return [pscustomobject]@{
        task_class = $taskClass
        exempt = $isExempt
        patch_required = $patchRequired
        patch_writer_status = $patchWriterStatus
        patch_writer_rejected = $patchWriterRejected
        files_changed_count = [int]@($filesChanged).Count
        command_output_proves_work = $commandOutputProvesWork
        validation_artifact_changed = $validationArtifactChanged
        result_artifact_changed = $resultArtifactChanged
        meaningful_evidence = @($meaningfulEvidence)
        detected = $detected
        reason_code = if ($detected) { 'no_meaningful_execution_evidence' } else { '' }
        detail = $detail
        recovery_state = if ($detected) { 'replay_or_replan_required' } else { 'not_needed' }
        allows_authoritative_completion = (-not $detected)
    }
}

function Publish-LocalExecutionArtifacts {
    param(
        [Parameter(Mandatory = $true)]$Task,
        [AllowNull()]$Objective,
        [Parameter(Mandatory = $true)]$ResultPayload,
        [Parameter(Mandatory = $true)][string]$ReviewDecision,
        [Parameter(Mandatory = $true)][string]$ExecutionId,
        [Parameter(Mandatory = $true)][string]$PackagePath,
        [Parameter(Mandatory = $true)]$ExecutionReadiness,
        [string]$Surface = 'tod-local-run-task'
    )

    $generatedAt = Get-UtcNow
    $objectiveId = if ($Task.PSObject.Properties['objective_id']) { [string]$Task.objective_id } else { '' }
    $normalizedObjectiveId = Get-NormalizedObjectiveToken -ObjectiveId $objectiveId
    $title = if ($Task.PSObject.Properties['title']) { [string]$Task.title } else { '' }
    $taskFocus = if ($Task.PSObject.Properties['scope']) { [string]$Task.scope } else { '' }
    $mission = if ($null -ne $Objective -and $Objective.PSObject.Properties['description']) { [string]$Objective.description } else { $taskFocus }
    $primaryOutcome = if ($null -ne $Objective -and $Objective.PSObject.Properties['success_criteria']) { ((@($Objective.success_criteria) | ForEach-Object { [string]$_ }) -join '; ') } else { '' }
    $summary = [string]$ResultPayload.summary
    $validationChecks = @(Get-LocalExecutionValidationChecks -ResultPayload $ResultPayload)
    $commandCapture = Get-LocalExecutionCommandCapture -ResultPayload $ResultPayload
    $rollback = Get-LocalExecutionRollbackState -ResultPayload $ResultPayload
    $filesChanged = @($ResultPayload.files_changed | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $noOpAssessment = if ($ResultPayload.PSObject.Properties['no_op_assessment'] -and $null -ne $ResultPayload.no_op_assessment) { $ResultPayload.no_op_assessment } else { Get-LocalExecutionNoOpAssessment -Task $Task -ResultPayload $ResultPayload }
    $explicitReasonCode = if ($ResultPayload.PSObject.Properties['reason_code']) { [string]$ResultPayload.reason_code } else { '' }
    $explicitRecoveryState = if ($ResultPayload.PSObject.Properties['recovery_state']) { [string]$ResultPayload.recovery_state } else { '' }
    $explicitBlockers = @($ResultPayload.structured_findings | Where-Object { $null -ne $_ -and $_.PSObject.Properties['type'] -and [string]$_.type -eq 'blocker' })
    $hasExplicitBlocker = -not [string]::IsNullOrWhiteSpace($explicitReasonCode)
    $diffSummary = if ($ResultPayload.PSObject.Properties['diff_summary']) { [string]$ResultPayload.diff_summary } else { '' }
    $commandsRun = if ($ResultPayload.PSObject.Properties['commands_run'] -and $null -ne $ResultPayload.commands_run) {
        @($ResultPayload.commands_run | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
    elseif ($null -ne $commandCapture -and $commandCapture.PSObject.Properties['command'] -and -not [string]::IsNullOrWhiteSpace([string]$commandCapture.command)) {
        @([string]$commandCapture.command)
    }
    else {
        @()
    }
    $validationResults = if ($ResultPayload.PSObject.Properties['validation_results'] -and $null -ne $ResultPayload.validation_results) { @($ResultPayload.validation_results) } else { @($validationChecks) }
    $artifactBlockers = if ($ResultPayload.PSObject.Properties['blockers'] -and $null -ne $ResultPayload.blockers) { @($ResultPayload.blockers) } else { @($explicitBlockers) }
    $confidence = if ($ResultPayload.PSObject.Properties['confidence']) { [string]$ResultPayload.confidence } elseif (@($filesChanged).Count -gt 0) { 'medium-high' } else { 'medium' }
    $strongestEvidence = if (@($filesChanged).Count -gt 0) { "Changed files: $($filesChanged -join ', ')" } elseif ($null -ne $commandCapture -and $commandCapture.PSObject.Properties['stdout'] -and -not [string]::IsNullOrWhiteSpace([string]$commandCapture.stdout)) { [string]$commandCapture.stdout } elseif ($null -ne $commandCapture -and $commandCapture.PSObject.Properties['stderr'] -and -not [string]::IsNullOrWhiteSpace([string]$commandCapture.stderr)) { [string]$commandCapture.stderr } else { $summary }
    $commandOutput = if ($null -ne $commandCapture -and $commandCapture.PSObject.Properties['stdout'] -and -not [string]::IsNullOrWhiteSpace([string]$commandCapture.stdout)) { [string]$commandCapture.stdout } elseif ($null -ne $commandCapture -and $commandCapture.PSObject.Properties['stderr'] -and -not [string]::IsNullOrWhiteSpace([string]$commandCapture.stderr)) { [string]$commandCapture.stderr } elseif ($null -ne $commandCapture -and $commandCapture.PSObject.Properties['command']) { [string]$commandCapture.command } else { '' }
    $commandRunnerStatus = if ($null -eq $commandCapture) { 'pending' } elseif ($commandCapture.PSObject.Properties['exit_code'] -and [int]$commandCapture.exit_code -eq 0) { 'completed' } else { 'blocked' }
    $commandRunnerSummary = if ($null -eq $commandCapture) { 'No validation command output was captured.' } elseif (-not [string]::IsNullOrWhiteSpace($commandOutput)) { $commandOutput } else { 'Validation command executed without captured output.' }
    $passed = ($ReviewDecision -eq 'pass') -and -not [bool]$noOpAssessment.detected -and -not $hasExplicitBlocker
    $status = if ($hasExplicitBlocker) { 'blocked' } elseif ([bool]$noOpAssessment.detected) { 'blocked' } elseif ($passed) { 'completed' } else { 'blocked' }
    $executionState = if ($hasExplicitBlocker) { 'blocked_with_reason' } elseif ([bool]$noOpAssessment.detected) { 'no_op_rejected' } elseif ($passed) { 'completed' } else { 'blocked' }
    $activityStatus = if ($hasExplicitBlocker) { 'blocked' } elseif ([bool]$noOpAssessment.detected) { 'blocked' } elseif ($passed) { 'completed' } else { 'blocked' }
    $currentAction = if ($hasExplicitBlocker) { 'Blocked execution on an explicit engine/runtime blocker and published the blocker evidence.' } elseif ([bool]$noOpAssessment.detected) { 'Rejected completion because the execution did not produce meaningful work evidence.' } elseif ($passed) { 'Completed the bounded local task and published local execution artifacts for TOD.' } else { 'Published the bounded local task outcome and marked the execution slice for review.' }
    $nextStep = if ($hasExplicitBlocker) { $(if (-not [string]::IsNullOrWhiteSpace($explicitRecoveryState)) { $explicitRecoveryState } else { 'local_fallback_or_replan_required' }) } elseif ([bool]$noOpAssessment.detected) { 'replay_or_replan_required' } elseif ($passed) { 'Continue with the next bounded local objective and its focused validation path.' } else { 'Review the failing checks, repair the bounded slice, and rerun the focused validation path.' }
    $nextValidation = if ($hasExplicitBlocker) { if (@($validationChecks).Count -gt 0) { [string]$validationChecks[0].name } else { 'explicit_blocker_review' } } elseif ([bool]$noOpAssessment.detected) { 'meaningful_execution_evidence_required' } elseif (@($validationChecks).Count -gt 0) { [string]$validationChecks[0].name } else { 'review_local_execution_artifacts' }
    $validationStatus = if ($hasExplicitBlocker) { 'blocked' } elseif ([bool]$noOpAssessment.detected) { 'blocked' } elseif ($passed) { 'passed' } else { 'blocked' }
    $rollbackState = if ($null -ne $rollback -and $rollback.PSObject.Properties['available'] -and [bool]$rollback.available) { 'available' } else { 'not_needed' }
    $rollbackHint = if ($ResultPayload.PSObject.Properties['rollback_hint']) { [string]$ResultPayload.rollback_hint } elseif ($null -ne $rollback -and $rollback.PSObject.Properties['restore_command']) { [string]$rollback.restore_command } else { '' }
    $reasonCode = if ($hasExplicitBlocker) { $explicitReasonCode } elseif ([bool]$noOpAssessment.detected) { [string]$noOpAssessment.reason_code } else { '' }
    $recoveryState = if ($hasExplicitBlocker) { $(if (-not [string]::IsNullOrWhiteSpace($explicitRecoveryState)) { $explicitRecoveryState } else { 'required' }) } elseif ([bool]$noOpAssessment.detected) { [string]$noOpAssessment.recovery_state } elseif ($passed) { 'not_needed' } else { 'required' }
    $requestId = [string]$Task.id
    $executionContract = [pscustomobject]@{
        contract_version = 'tod-execution-loop-v1'
        status = if ($passed) { 'completed' } else { 'blocked' }
        task_intake = [pscustomobject]@{
            status = 'accepted'
            task_focus = $taskFocus
            title = $title
            mission = $mission
            primary_outcome = $primaryOutcome
            strongest_evidence = $strongestEvidence
        }
        bounded_step_planner = [pscustomobject]@{
            status = if ($passed) { 'completed' } else { 'blocked' }
            active_step = [pscustomobject]@{
                step_id = 'step-1-local-run-task'
                title = 'Execute the bounded local task and publish results'
                status = if ($passed) { 'completed' } else { 'blocked' }
                summary = $summary
                observed_files = @($filesChanged)
            }
            next_validation = $nextValidation
        }
        command_runner = [pscustomobject]@{
            status = $commandRunnerStatus
            summary = $commandRunnerSummary
            mode = 'local_task_execution'
        }
        patch_writer = [pscustomobject]@{
            status = [string]$noOpAssessment.patch_writer_status
            summary = if (@($filesChanged).Count -gt 0) { 'The local executor updated the bounded target files.' } elseif ([string]$noOpAssessment.patch_writer_status -eq 'evidence_only') { 'The local executor completed without new file deltas on this rerun, and accepted validation or result-artifact evidence preserved the execution outcome.' } elseif ([bool]$noOpAssessment.patch_required) { 'Patch-required execution produced no changed files or accepted alternative evidence, so completion was rejected.' } else { 'The local executor completed without changing files.' }
        }
        validator = [pscustomobject]@{
            status = $validationStatus
            target = $nextValidation
            summary = if ([bool]$noOpAssessment.detected) { [string]$noOpAssessment.detail } else { $summary }
            checks = @($validationChecks)
        }
        result_publisher = [pscustomobject]@{
            status = 'completed'
            artifacts = @(
                'TOD_ACTIVE_OBJECTIVE.latest.json',
                'TOD_ACTIVE_TASK.latest.json',
                'TOD_ACTIVITY_STREAM.latest.json',
                'TOD_VALIDATION_RESULT.latest.json',
                'TOD_EXECUTION_RESULT.latest.json',
                'TOD_EXECUTION_TRUTH.latest.json'
            )
            latest_summary = $summary
        }
    }

    $basePayload = [ordered]@{
        generated_at = $generatedAt
        updated_at = $generatedAt
        source = 'tod.local.run-task'
        surface = $Surface
        session_key = 'tod-local-runtime'
        request_id = $requestId
        task_id = [string]$Task.id
        execution_id = $ExecutionId
        objective_id = $objectiveId
        normalized_objective_id = $normalizedObjectiveId
        title = $title
        summary = $summary
        package_path = $PackagePath
        execution_contract = $executionContract
        execution_readiness = $ExecutionReadiness
        reason_code = $reasonCode
        diff_summary = $diffSummary
        commands_run = @($commandsRun)
        validation_results = @($validationResults)
        blockers = @($artifactBlockers)
        confidence = $confidence
        rollback_hint = $rollbackHint
    }

    $executionEvidence = [ordered]@{
        source = 'tod.local.run-task'
        summary = $summary
        matched_files = @($filesChanged)
        files_changed = @($filesChanged)
        validation_checks = @($validationChecks)
        validation_passed = $passed
        command_output = $commandOutput
        rollback_state = $rollbackState
        recovery_state = $recoveryState
        package_path = $PackagePath
        review_decision = $ReviewDecision
        reason_code = $reasonCode
        no_op_detected = [bool]$noOpAssessment.detected
        task_class = [string]$noOpAssessment.task_class
        meaningful_evidence = @($noOpAssessment.meaningful_evidence)
        blockers = @($artifactBlockers)
        diff_summary = $diffSummary
        commands_run = @($commandsRun)
        validation_results = @($validationResults)
        confidence = $confidence
        rollback_hint = $rollbackHint
    }

    $activeObjectivePayload = [ordered]@{} + $basePayload + @{
        packet_type = 'tod-active-objective-v1'
        mission = $mission
        primary_outcome = $primaryOutcome
        status = if ($passed) { 'completed' } else { 'active' }
        execution_evidence = $executionEvidence
    }
    $activeTaskPayload = [ordered]@{} + $basePayload + @{
        packet_type = 'tod-active-task-v1'
        task_focus = $taskFocus
        status = if ($passed) { 'completed' } else { 'blocked' }
        execution_state = $executionState
        current_action = $currentAction
        next_step = $nextStep
        next_validation = $nextValidation
        wait_target = ''
        wait_target_label = ''
        wait_reason = ''
        execution_evidence = $executionEvidence
        recovery_state = $recoveryState
    }
    $activityPayload = [ordered]@{} + $basePayload + @{
        packet_type = 'tod-activity-stream-v1'
        event = if ([bool]$noOpAssessment.detected) { 'local_task_no_op_rejected' } elseif ($passed) { 'local_task_completed' } else { 'local_task_blocked' }
        status = $activityStatus
        phase = 'local_run_task'
        current_action = $currentAction
        next_step = $nextStep
        next_validation = $nextValidation
        execution_state = $executionState
        execution_evidence = $executionEvidence
        recovery_state = $recoveryState
    }
    $validationPayload = [ordered]@{} + $basePayload + @{
        packet_type = 'tod-validation-result-v1'
        status = $validationStatus
        phase = 'local_run_task'
        validation_target = $nextValidation
        checks = @($validationChecks)
        evidence = [ordered]@{
            matched_files = @($filesChanged)
            command_output = $commandOutput
        }
    }
    $executionResultPayload = [ordered]@{} + $basePayload + @{
        packet_type = 'tod-execution-result-v1'
        execution_state = $executionState
        status = $status
        phase = 'local_run_task'
        current_action = $currentAction
        next_step = $nextStep
        wait_target = ''
        wait_target_label = ''
        wait_reason = ''
        validation_summary = $summary
        command_output = $commandOutput
        files_changed = @($filesChanged)
        rollback_state = $rollbackState
        recovery_state = $recoveryState
        execution_evidence = $executionEvidence
    }
    $executionTruthPayload = [ordered]@{
        generated_at = $generatedAt
        source = 'tod.local.run-task'
        summary = [ordered]@{
            execution_count = 1
            latest_execution_at = $generatedAt
            objective_id = $objectiveId
            task_id = [string]$Task.id
            request_id = $requestId
            summary = $summary
            current_action = $currentAction
            next_step = $nextStep
            validation_passed = $passed
            reason_code = $reasonCode
        }
        recent_execution_truth = @(
            [ordered]@{
                generated_at = $generatedAt
                objective_id = $objectiveId
                task_id = [string]$Task.id
                execution_id = $ExecutionId
                request_id = $requestId
                execution_state = $executionState
                status = $status
                summary = $summary
                current_action = $currentAction
                next_step = $nextStep
                next_validation = $nextValidation
                validation_passed = $passed
                reason_code = $reasonCode
                recovery_state = $recoveryState
                execution_evidence = $executionEvidence
                execution_contract = $executionContract
            }
        )
    }

    $writtenArtifactPaths = @()
    foreach ($sharedRoot in @(Get-TodExecutionSharedRoots)) {
        $activeObjectiveWrite = Write-TodExecutionSharedJson -Path (Join-Path $sharedRoot 'TOD_ACTIVE_OBJECTIVE.latest.json') -Payload $activeObjectivePayload
        $activeTaskWrite = Write-TodExecutionSharedJson -Path (Join-Path $sharedRoot 'TOD_ACTIVE_TASK.latest.json') -Payload $activeTaskPayload
        $activityWrite = Write-TodExecutionSharedJson -Path (Join-Path $sharedRoot 'TOD_ACTIVITY_STREAM.latest.json') -Payload $activityPayload
        $validationWrite = Write-TodExecutionSharedJson -Path (Join-Path $sharedRoot 'TOD_VALIDATION_RESULT.latest.json') -Payload $validationPayload
        $executionResultWrite = Write-TodExecutionSharedJson -Path (Join-Path $sharedRoot 'TOD_EXECUTION_RESULT.latest.json') -Payload $executionResultPayload
        $executionTruthWrite = Write-TodExecutionSharedJson -Path (Join-Path $sharedRoot 'TOD_EXECUTION_TRUTH.latest.json') -Payload $executionTruthPayload
        foreach ($writeResult in @($activeObjectiveWrite, $activeTaskWrite, $activityWrite, $validationWrite, $executionResultWrite, $executionTruthWrite)) {
            if ($writeResult -and $writeResult.PSObject.Properties['written'] -and [bool]$writeResult.written) {
                $writtenArtifactPaths += [string]$writeResult.path
            }
        }
    }

    $runtimeSharedRoot = [System.IO.Path]::GetFullPath((Join-Path $repoRoot 'runtime/shared'))
    $remotePublishPaths = @($writtenArtifactPaths | Where-Object {
        $fullPath = [System.IO.Path]::GetFullPath([string]$_)
        $fullPath.StartsWith($runtimeSharedRoot, [System.StringComparison]::OrdinalIgnoreCase)
    } | Select-Object -Unique)
    if ($remotePublishPaths.Length -gt 0) {
        Publish-RemoteTodExecutionArtifacts -LocalArtifactPaths $remotePublishPaths | Out-Null
    }

    $activityArtifactPath = @($writtenArtifactPaths | Where-Object { [System.IO.Path]::GetFileName([string]$_) -eq 'TOD_ACTIVITY_STREAM.latest.json' } | Select-Object -First 1)
    $activityArtifact = if (@($activityArtifactPath).Count -gt 0) { Read-TodExecutionJsonIfExists -Path ([string]$activityArtifactPath[0]) } else { $activityPayload }

    return [pscustomobject]@{
        no_op_assessment = $noOpAssessment
        active_objective = $activeObjectivePayload
        active_task = $activeTaskPayload
        activity = $activityArtifact
        validation = $validationPayload
        execution_result = $executionResultPayload
        execution_truth = $executionTruthPayload
        artifact_paths = @($writtenArtifactPaths)
    }
}

function Publish-RemoteTodExecutionArtifacts {
    param(
        [Parameter(Mandatory = $true)][string[]]$LocalArtifactPaths,
        [string]$RemoteRoot = '/home/testpilot/mim/runtime/shared',
        [string]$DotEnvPath = (Join-Path $repoRoot '.env')
    )

    $existingPaths = @($LocalArtifactPaths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -Path $_) })
    if ($existingPaths.Count -eq 0) {
        return [pscustomobject]@{ attempted = $false; published = $false; reason = 'missing_local_artifacts' }
    }

    if (-not (Test-Path -Path $DotEnvPath)) {
        return [pscustomobject]@{ attempted = $false; published = $false; reason = 'missing_dotenv' }
    }

    $hostName = Get-DotEnvValue -Path $DotEnvPath -Name 'MIM_SSH_HOST'
    $userName = Get-DotEnvValue -Path $DotEnvPath -Name 'MIM_SSH_USER'
    $portText = Get-DotEnvValue -Path $DotEnvPath -Name 'MIM_SSH_PORT'
    $password = Get-DotEnvValue -Path $DotEnvPath -Name 'MIM_SSH_PASSWORD'
    if ([string]::IsNullOrWhiteSpace($hostName) -or [string]::IsNullOrWhiteSpace($userName) -or [string]::IsNullOrWhiteSpace($password)) {
        return [pscustomobject]@{ attempted = $false; published = $false; reason = 'missing_ssh_settings' }
    }

    if (-not (Get-Module -ListAvailable -Name Posh-SSH)) {
        return [pscustomobject]@{ attempted = $false; published = $false; reason = 'missing_posh_ssh' }
    }

    $port = 22
    if (-not [string]::IsNullOrWhiteSpace($portText)) {
        $parsedPort = 0
        if ([int]::TryParse($portText, [ref]$parsedPort) -and $parsedPort -gt 0) {
            $port = $parsedPort
        }
    }

    $session = $null
    try {
        Import-Module Posh-SSH -ErrorAction Stop | Out-Null
        $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential ($userName, $securePassword)
        $connectHost = Resolve-SshHostAlias -RemoteHost $hostName
        $session = New-SFTPSession -ComputerName $connectHost -Port $port -Credential $credential -AcceptKey -ConnectionTimeout 15000
        foreach ($path in $existingPaths) {
            Set-SFTPItem -SessionId ([int]$session.SessionId) -Path $path -Destination $RemoteRoot -Force -ErrorAction Stop | Out-Null
        }
        return [pscustomobject]@{ attempted = $true; published = $true; reason = 'ok'; remote_root = $RemoteRoot; count = $existingPaths.Count }
    }
    catch {
        return [pscustomobject]@{ attempted = $true; published = $false; reason = 'error'; error = [string]$_.Exception.Message }
    }
    finally {
        if ($session) {
            Remove-SFTPSession -SessionId ([int]$session.SessionId) | Out-Null
        }
    }
}

function Resolve-ExecutionIdForTask {
    param(
        [string]$ExplicitExecutionId,
        $Task
    )

    if (-not [string]::IsNullOrWhiteSpace($ExplicitExecutionId)) {
        return [string]$ExplicitExecutionId
    }

    if ($null -eq $Task) {
        return ""
    }

    if ($Task.PSObject.Properties["execution_id"] -and -not [string]::IsNullOrWhiteSpace([string]$Task.execution_id)) {
        return [string]$Task.execution_id
    }
    if ($Task.PSObject.Properties["remote_execution_id"] -and -not [string]::IsNullOrWhiteSpace([string]$Task.remote_execution_id)) {
        return [string]$Task.remote_execution_id
    }
    return ""
}

function Try-PublishExecutionFeedback {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)]$FeedbackConfig,
        [AllowEmptyString()][string]$ExecutionId,
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $true)][string]$TaskId,
        $Details
    )

    if (-not [bool]$FeedbackConfig.enabled) {
        return [pscustomobject]@{ attempted = $false; published = $false; reason = "disabled" }
    }
    if ([string]::IsNullOrWhiteSpace($ExecutionId)) {
        return [pscustomobject]@{ attempted = $false; published = $false; reason = "missing_execution_id" }
    }
    if (-not (Get-Command -Name New-MimExecutionFeedback -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{ attempted = $false; published = $false; reason = "mim_feedback_client_unavailable" }
    }

    try {
        $response = Invoke-MimSafely -Config $Config -Operation "POST /gateway/capabilities/executions/$ExecutionId/feedback" -ApiCall {
            New-MimExecutionFeedback -BaseUrl $Config.mim_base_url -ExecutionId $ExecutionId -Status $Status -Source $FeedbackConfig.source -TaskId $TaskId -Details $Details -AuthToken ([string]$FeedbackConfig.auth_token) -TimeoutSeconds ([int]$Config.timeout_seconds)
        }

        if ($null -eq $response) {
            return [pscustomobject]@{ attempted = $true; published = $false; reason = "mim_unavailable_fallback" }
        }

        return [pscustomobject]@{ attempted = $true; published = $true; reason = "ok"; response = $response }
    }
    catch {
        return [pscustomobject]@{ attempted = $true; published = $false; reason = "error"; error = [string]$_.Exception.Message }
    }
}

if ($Action -eq "init") {
    if (-not (Test-Path -Path (Split-Path -Parent $statePath))) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $statePath) -Force | Out-Null
    }
    if (-not (Test-Path -Path $statePath)) {
        @{
            objectives = @()
            tasks = @()
            execution_results = @()
            review_decisions = @()
            journal = @()
            engine_performance = @{
                records = @()
                updated_at = ""
            }
            routing_decisions = @{
                records = @()
                updated_at = ""
            }
            routing_feedback = @{
                learned_weights = (Get-DefaultRoutingWeights)
                sample_size = 0
                version = "feedback_v1"
                updated_at = ""
            }
            sync_state = @{
                expected_contract_version = ""
                expected_schema_version = ""
                local_repo_signature = ""
                cached_manifest = $null
                last_comparison = $null
                last_sync_decision = ""
                last_sync_code = ""
                compared_at = ""
            }
        } | ConvertTo-Json -Depth 6 | Set-Content -Path $statePath
    }
    if (-not (Test-Path -Path $promptOutDir)) {
        New-Item -ItemType Directory -Path $promptOutDir -Force | Out-Null
    }
    if (-not (Test-Path -Path (Split-Path -Parent $configPath))) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $configPath) -Force | Out-Null
    }
    if (-not (Test-Path -Path $configPath)) {
        @{
            mim_base_url = "http://192.168.1.120:8000"
            mode = "hybrid"
            timeout_seconds = 15
            fallback_to_local = $true
            execution_engine = @{
                active = "codex"
                fallback = "local"
                allow_fallback = $true
                retry_policy = @{
                    enabled = $true
                    max_attempts_per_engine = 2
                    max_attempts_by_category = @{
                        code_change = 1
                        review_only = 2
                        refactor = 2
                    }
                    backoff_ms = 200
                    retry_on_status = @("failed", "error", "not_implemented")
                    no_retry_failure_categories = @("auth", "capability")
                    backoff_by_failure_category = @{
                        timeout = 2
                        network = 2
                        rate_limit = 3
                    }
                }
                routing_policy = @{
                    enabled = $true
                    min_runs = 1
                    min_success_rate = 75
                    improvement_margin = 5
                    source = "routing_policy_v1"
                    allow_placeholder_for_code_change = $false
                    prefer_stable_on_sync_warn = $true
                    block_on_contract_drift = $true
                    recent_failure_window = 5
                    recent_failure_threshold = 2
                    min_category_records_light = 10
                    min_category_records_strong = 20
                    drift_detection = @{
                        enabled = $true
                        recent_window = 20
                        baseline_window = 50
                        minimum_baseline_records = 10
                        failure_rate_multiplier = 1.5
                        retry_rate_threshold = 0.35
                        fallback_rate_multiplier = 1.5
                        fallback_rate_threshold = 0.3
                        guardrail_rate_multiplier = 1.8
                        guardrail_rate_threshold = 0.15
                        engine_score_drop_threshold = 0.2
                        confidence_penalty_failure_drift = 0.18
                        confidence_penalty_retry_high = 0.12
                        confidence_penalty_fallback_drift = 0.09
                        confidence_penalty_guardrail_spike = 0.1
                        confidence_penalty_score_drop = 0.12
                        score_penalty_failure_drift = 0.12
                        score_penalty_retry_high = 0.08
                        score_penalty_fallback_drift = 0.08
                        score_penalty_guardrail_spike = 0.1
                        score_penalty_score_drop = 0.12
                    }
                    weights = (Get-DefaultRoutingWeights)
                }
            }
        } | ConvertTo-Json -Depth 6 | Set-Content -Path $configPath
    }
    if (-not (Test-Path -Path $syncPolicyPath)) {
        @{
            contract_version = "tod-mim-shared-contract-v1"
            schema_version = "2026-03-09-01"
            required_capabilities = @("health", "status", "manifest", "objectives", "tasks", "results", "reviews", "journal")
            signature_sources = @(
                "docs/tod-mim-shared-contract-v1.md",
                "docs/mim-manifest-contract-v1.md",
                "client/mim_api_client.ps1",
                "client/mim_api_helpers.ps1",
                "scripts/TOD.ps1",
                "tod/config/tod-config.json"
            )
        } | ConvertTo-Json -Depth 8 | Set-Content -Path $syncPolicyPath
    }
    Write-Host "TOD initialized." -ForegroundColor Green
    return
}

$config = Load-TodConfig
$state = [pscustomobject]@{}
$stateLoadGuard = Get-StateLoadGuardInfo -Path $statePath
$stateAccess = [pscustomobject]@{
    mode = "full"
    local_cache_enabled = $true
    oversized = [bool]$stateLoadGuard.oversized
    state_file = $stateLoadGuard
}
if (Test-ActionRequiresState -ActionName $Action) {
    if ([bool]$stateLoadGuard.oversized -and (Test-ActionSupportsLightweightStateBus -ActionName $Action)) {
        $stateAccess.mode = "lightweight_guard"
        $stateAccess.local_cache_enabled = $false
        $state = New-MinimalTodState
    }
    elseif ([bool]$stateLoadGuard.oversized -and @("run-task", "add-result", "review-task") -contains $Action -and (Use-Remote -Config $config)) {
        $stateAccess.mode = "remote_ephemeral"
        $stateAccess.local_cache_enabled = $false
        $state = New-MinimalTodState
    }
    else {
        $state = Load-State
    }
}
if (Get-Command -Name Set-MimApiDebugLogging -ErrorAction SilentlyContinue) {
    $resolvedDebugPath = [string]$config.mim_debug.log_path
    if ([string]::IsNullOrWhiteSpace($resolvedDebugPath)) {
        $resolvedDebugPath = Join-Path $repoRoot "tod/out/mim-http.log"
    }
    Set-MimApiDebugLogging -Enabled ([bool]$config.mim_debug.enabled) -LogPath $resolvedDebugPath
}
$engineConfig = Resolve-ExecutionEngineConfig -Config $config -State $state -DisableAdaptiveRouting:$ForceConfiguredEngine
$capabilityGate = Apply-CapabilityDegrade -Config $config -State $state -ActionName $Action
$executionReadinessGate = Apply-ExecutionReadinessPolicy -Config $config -ActionName $Action -ApplyPlan:$ApplyPlan
$ApplyPlan = [bool]$executionReadinessGate.effective_apply_plan
if ($executionReadinessGate.blocked -and $Action -notin @("run-task", "select-next-task-loop")) {
    throw "Blocked action '$Action' because execution-readiness is $([string]$executionReadinessGate.signal.readiness.status). Run .\\scripts\\Test-TODOperatorChatSweepArtifact.ps1 and restore a valid certification artifact before executing tasks."
}
Assert-ContractGate -ActionName $Action -State $state -AllowDrift:$AllowContractDrift

if ((Use-Remote -Config $config) -and -not (Get-Command -Name Get-MimHealth -ErrorAction SilentlyContinue)) {
    throw "MIM client functions are unavailable. Ensure client/mim_api_client.ps1 exists."
}

switch ($Action) {
    "codex_handoff" {
        $handoff = Resolve-CodexHandoffRequest -RequestedRequestId $RequestId -RequestedTaskId $TaskId
        $mirror = Sync-CodexHandoffTaskMirror -Request $handoff.payload
        $packagePath = Write-CodexHandoffTaskPackage -Request $handoff.payload

        $handoffTaskId = if (-not [string]::IsNullOrWhiteSpace([string]$handoff.task_id)) { [string]$handoff.task_id } else { [string]$handoff.request_id }
        $runTaskArgs = @{
            Action = 'run-task'
            ConfigPath = $configPath
            StatePath = $statePath
            TaskId = $handoffTaskId
            PackagePath = $packagePath
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$handoff.objective_id)) {
            $runTaskArgs['ObjectiveId'] = [string]$handoff.objective_id
        }
        if ($ForceConfiguredEngine) {
            $runTaskArgs['ForceConfiguredEngine'] = $true
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$ExecutionId)) {
            $runTaskArgs['ExecutionId'] = [string]$ExecutionId
        }

        $raw = & $PSCommandPath @runTaskArgs 2>&1
        $payload = $null
        try {
            $payload = ($raw | ConvertFrom-Json)
        }
        catch {
            $payload = $null
        }

        [pscustomobject]@{
            request_id = [string]$handoff.request_id
            task_id = $handoffTaskId
            objective_id = [string]$handoff.objective_id
            tod_action = 'codex_handoff'
            execution_lane = 'bridge_runtime_codex_handoff'
            request_packet_path = [string]$handoff.path
            task_mirror = $mirror
            package_path = $packagePath
            execution = if ($null -ne $payload) { $payload } else { [pscustomobject]@{ ok = $false; blocked = $false; action = 'run-task'; output = [string]($raw | Out-String) } }
        } | ConvertTo-Json -Depth 16
    }

    "execute-chat-task" {
        if ([string]::IsNullOrWhiteSpace($TaskId)) { throw '-TaskId is required' }

        $result = Invoke-ExecuteChatTaskRequest -ObjectiveId $ObjectiveId -TaskId $TaskId -RequestId $RequestId -Title $Title -Description $Description -Priority $Priority -Scope $Scope -AcceptanceCriteria $AcceptanceCriteria -SuccessCriteria $SuccessCriteria -AssignedExecutor $AssignedExecutor -TaskCategory $TaskCategory -CorrelationId $CorrelationId -TargetFile $TargetFile -ResolvedConfigPath $configPath -ResolvedStatePath $statePath -ExecutionMode $ExecutionMode
        $result | ConvertTo-Json -Depth 16
    }

    "persist-task-terminal-state" {
        if ([string]::IsNullOrWhiteSpace($TaskId)) { throw '-TaskId is required' }

        $detailPayload = $null
        if (-not [string]::IsNullOrWhiteSpace($Description)) {
            try {
                $detailPayload = ($Description | ConvertFrom-Json)
            }
            catch {
                $detailPayload = [pscustomobject]@{ description = [string]$Description }
            }
        }

        $terminalStateValue = if ([string]::Equals([string]$Type, 'completed', [System.StringComparison]::OrdinalIgnoreCase)) {
            'completed'
        }
        else {
            'blocked'
        }

        $terminalEventValue = if ([string]::IsNullOrWhiteSpace($Type)) {
            'blocked'
        }
        else {
            [string]$Type
        }

        $updatedTask = Update-TaskTerminalStateInStore -State $state -TaskId $TaskId -Status $terminalStateValue -EventType $terminalEventValue -Message $(if ([string]::IsNullOrWhiteSpace($Summary)) { 'Persisted terminal task state.' } else { [string]$Summary }) -ReasonCode $(if ([string]::Equals([string]$AssignedExecutor, 'worker_startup_failure', [System.StringComparison]::OrdinalIgnoreCase)) { 'worker_startup_failure' } else { '' }) -Details $detailPayload -TaskStatus $terminalStateValue
        if ($null -eq $updatedTask) {
            throw ("Task '{0}' not found while persisting terminal state." -f $TaskId)
        }

        Save-State -State $state
        [pscustomobject]@{
            ok = $true
            action = 'persist-task-terminal-state'
            task_id = [string]$TaskId
            terminal_state = $updatedTask.terminal_state
        } | ConvertTo-Json -Depth 12
    }

    "publish-activity-event" {
        if ([string]::IsNullOrWhiteSpace($Type)) { throw '-Type is required for publish-activity-event and is used as the event type.' }

        $detailPayload = $null
        if (-not [string]::IsNullOrWhiteSpace($Description)) {
            try {
                $detailPayload = ($Description | ConvertFrom-Json)
            }
            catch {
                $detailPayload = [ordered]@{ description = [string]$Description }
            }
        }

        $eventRecord = Publish-TodActivityEvent -EventType ([string]$Type) -ObjectiveId $ObjectiveId -TaskId $TaskId -RequestId $RequestId -CorrelationId $CorrelationId -Title $Title -Status $(if ([string]::IsNullOrWhiteSpace($Priority)) { 'info' } else { [string]$Priority }) -Message $Summary -Details $detailPayload -Source 'tod.manual-activity' -Surface 'tod-chat' -Summary $Scope -CurrentAction $AcceptanceCriteria -ExecutionState $SuccessCriteria -RecoveryState $AssignedExecutor
        $eventRecord | ConvertTo-Json -Depth 16
    }

    "ping-mim" {
        if (-not (Use-Remote -Config $config)) {
            throw "ping-mim requires mode 'remote' or 'hybrid' in tod/config/tod-config.json"
        }

        $start = Get-Date
        $health = Invoke-MimSafely -Config $config -Operation "GET /health" -ApiCall {
            Get-MimHealth -BaseUrl $config.mim_base_url -TimeoutSeconds ([int]$config.timeout_seconds)
        }
        $status = Invoke-MimSafely -Config $config -Operation "GET /status" -ApiCall {
            Get-MimStatus -BaseUrl $config.mim_base_url -TimeoutSeconds ([int]$config.timeout_seconds)
        }
        $elapsedMs = [int]((Get-Date) - $start).TotalMilliseconds

        if ($null -eq $health -or $null -eq $status) {
            throw "MIM is not reachable and fallback is not applicable for ping-mim."
        }

        [pscustomobject]@{
            base_url = $config.mim_base_url
            mode = $config.mode
            execution_engine = $engineConfig
            reachable = $true
            elapsed_ms = $elapsedMs
            health = $health
            status = $status
        } | ConvertTo-Json -Depth 10
    }

    "safe_home" {
        $dotEnvPath = Join-Path $repoRoot ".env"
        $safeHomeResult = Invoke-MimArmSafeHome -DotEnvPathValue $dotEnvPath -TimeoutSeconds ([int]$config.timeout_seconds)
        $safeHomeResult | ConvertTo-Json -Depth 12
    }

    "scan_pose" {
        $dotEnvPath = Join-Path $repoRoot ".env"
        $scanPoseResult = Invoke-MimArmNamedRoutine -DotEnvPathValue $dotEnvPath -RoutineName 'scan_pose' -TimeoutSeconds ([int]$config.timeout_seconds)
        $scanPoseResult | ConvertTo-Json -Depth 12
    }

    "capture_frame" {
        $dotEnvPath = Join-Path $repoRoot ".env"
        $captureFrameResult = Invoke-MimArmNamedRoutine -DotEnvPathValue $dotEnvPath -RoutineName 'capture_frame' -TimeoutSeconds ([int]$config.timeout_seconds)
        $captureFrameResult | ConvertTo-Json -Depth 12
    }

    "compare-manifest" {
        $policy = Load-SyncPolicy
        $localSignature = Get-DeterministicRepoSignature -Policy $policy

        $liveManifest = $null
        if (-not [string]::IsNullOrWhiteSpace($ManifestPath)) {
            Assert-Exists -Path $ManifestPath -Name "Manifest file"
            $liveManifest = (Get-Content -Path $ManifestPath -Raw) | ConvertFrom-Json
        }
        elseif (Use-Remote -Config $config) {
            $liveManifest = Invoke-MimSafely -Config $config -Operation "GET /manifest" -ApiCall {
                Get-MimManifest -BaseUrl $config.mim_base_url -TimeoutSeconds ([int]$config.timeout_seconds)
            }
        }

        if ($null -eq $liveManifest) {
            [pscustomobject]@{
                compared_at = Get-UtcNow
                status = "unavailable"
                message = "Manifest is not available yet. Use -ManifestPath with a sample manifest or enable /manifest in MIM."
                expected = [pscustomobject]@{
                    contract_version = [string]$policy.contract_version
                    schema_version = [string]$policy.schema_version
                    required_capabilities = @(To-StringArray -Value $policy.required_capabilities)
                    local_repo_signature = [string]$localSignature.signature
                }
                signature_details = $localSignature
            } | ConvertTo-Json -Depth 12
            break
        }

        $cachedManifest = $null
        if ($state.PSObject.Properties["sync_state"] -and $state.sync_state -and $state.sync_state.PSObject.Properties["cached_manifest"]) {
            $cachedManifest = $state.sync_state.cached_manifest
        }

        $comparison = Compare-ManifestState -LiveManifest $liveManifest -CachedManifest $cachedManifest -Policy $policy -LocalSignature $localSignature

        $priorSyncDecision = if ($state.sync_state.PSObject.Properties["last_sync_decision"]) { [string]$state.sync_state.last_sync_decision } else { "" }
        $priorSyncCode = if ($state.sync_state.PSObject.Properties["last_sync_code"]) { [string]$state.sync_state.last_sync_code } else { "" }

        $state.sync_state = [pscustomobject]@{
            expected_contract_version = [string]$policy.contract_version
            expected_schema_version = [string]$policy.schema_version
            local_repo_signature = [string]$localSignature.signature
            cached_manifest = $liveManifest
            last_comparison = $comparison
            last_sync_decision = $priorSyncDecision
            last_sync_code = $priorSyncCode
            compared_at = Get-UtcNow
        }

        Add-Journal -State $state -Actor "tod" -ActionName "compare_manifest" -EntityType "sync_state" -EntityId "sync_state" -Payload @{
            status = $comparison.status
            recommended_actions = @($comparison.recommended_actions)
        }
        Save-State -State $state

        [pscustomobject]@{
            comparison = $comparison
            signature_details = $localSignature
        } | ConvertTo-Json -Depth 12
    }

    "sync-mim" {
        $compareResult = $null
        if (-not [string]::IsNullOrWhiteSpace($ManifestPath)) {
            $compareResult = (& $PSCommandPath -Action compare-manifest -ConfigPath $configPath -ManifestPath $ManifestPath) | ConvertFrom-Json
        }
        else {
            $compareResult = (& $PSCommandPath -Action compare-manifest -ConfigPath $configPath) | ConvertFrom-Json
        }
        $status = [string]$compareResult.comparison.status
        $syncDecision = Resolve-SyncDecision -Status $status
        $syncDecisionCode = Resolve-SyncDecisionCode -Decision $syncDecision
        $recommended = @($compareResult.comparison.recommended_actions)
        $escalationCode = [string]$compareResult.comparison.escalation_code
        $reconciliationPlan = @($compareResult.comparison.reconciliation_plan)
        $infoFields = @($compareResult.comparison.drift_findings | Where-Object { $_.severity -eq "info" } | ForEach-Object { [string]$_.field } | Select-Object -Unique)
        $recentChangesOnly = (@($recommended).Count -eq 0) -and (@($infoFields | Where-Object { $_ -notin @("last_updated_at", "recent_changes", "repo_signature_local") }).Count -eq 0)

        $reindexTriggered = $false
        $reindexResult = $null
        $reindexSucceeded = $false
        if ($recommended -contains "trigger-reindex") {
            Update-RepoIndexSyncState -Stale $true -Reason "repo_signature_changed" -ManifestRepoSignature ([string]$compareResult.comparison.observed.repo_signature) -ReindexTriggered $true -ReindexSucceeded $false
            if (Test-Path -Path $todEngineerPath) {
                try {
                    $reindexResult = (& $todEngineerPath -Action index-repo) | ConvertFrom-Json
                    $reindexTriggered = $true
                    $reindexSucceeded = $true
                }
                catch {
                    $reindexResult = [pscustomobject]@{ error = $_.Exception.Message }
                }
            }
            else {
                $reindexResult = [pscustomobject]@{ error = "TOD-Engineer script not found for re-index trigger." }
            }

            if ($reindexSucceeded) {
                Update-RepoIndexSyncState -Stale $false -Reason "refreshed_after_repo_signature_change" -ManifestRepoSignature ([string]$compareResult.comparison.observed.repo_signature) -ReindexTriggered $true -ReindexSucceeded $true
            }
        }
        else {
            Update-RepoIndexSyncState -Stale $false -Reason "sync_current" -ManifestRepoSignature ([string]$compareResult.comparison.observed.repo_signature) -ReindexTriggered $false -ReindexSucceeded $false
        }

        $latestState = Load-State
        $latestState.sync_state.last_sync_decision = $syncDecision
        $latestState.sync_state.last_sync_code = $syncDecisionCode
        Add-Journal -State $latestState -Actor "tod" -ActionName "sync_mim" -EntityType "sync_state" -EntityId "sync_state" -Payload @{
            decision = $syncDecision
            decision_code = $syncDecisionCode
            status = $status
            escalation_code = $escalationCode
            recommended_actions = @($recommended)
            reconciliation_plan = @($reconciliationPlan)
            reindex_triggered = $reindexTriggered
            capability_degraded = [bool]$capabilityGate.degraded
            missing_capabilities = @($capabilityGate.missing)
        }
        Save-State -State $latestState

        $syncSummary = if ($recentChangesOnly) {
            "sync-mim recorded metadata update only (recent_changes/last_updated_at)."
        }
        else {
            "sync-mim decision=$syncDecision status=$status actions=$(@($recommended) -join ',')."
        }
        Add-EngineeringMemorySyncNote -SyncDecision $syncDecision -Status $status -RecommendedActions @($recommended) -Summary $syncSummary

        $remoteJournalLogged = Try-LogSyncToMimJournal -Config $config -Payload @{
            actor = "tod"
            action = "sync_mim"
            target_type = "sync_state"
            target_id = "sync_state"
            summary = $syncSummary
        }

        [pscustomobject]@{
            compared_at = Get-UtcNow
            decision = $syncDecision
            decision_code = $syncDecisionCode
            status = $status
            escalation_code = $escalationCode
            recommended_actions = @($recommended)
            reconciliation_plan = @($reconciliationPlan)
            reindex_triggered = $reindexTriggered
            reindex_result = $reindexResult
            recent_changes_only = $recentChangesOnly
            capability_degraded = [bool]$capabilityGate.degraded
            missing_capabilities = @($capabilityGate.missing)
            remote_journal_logged = $remoteJournalLogged
            comparison = $compareResult.comparison
        } | ConvertTo-Json -Depth 12
    }

    "new-objective" {
        if ([string]::IsNullOrWhiteSpace($Title)) { throw "-Title is required" }
        if ([string]::IsNullOrWhiteSpace($Description)) { throw "-Description is required" }
        if ([string]::IsNullOrWhiteSpace($SuccessCriteria)) { throw "-SuccessCriteria is required" }

        $safeTitle = Limit-StateTextField -Value ([string]$Title) -MaxLength 512 -FieldName "objective.title"
        $safeDescription = Limit-StateTextField -Value ([string]$Description) -MaxLength 8192 -FieldName "objective.description"

        $id = New-Id -Prefix "OBJ" -Count $state.objectives.Count
        $obj = [pscustomobject]@{
            id = $id
            title = $safeTitle
            description = $safeDescription
            priority = $Priority
            constraints = [string[]](Split-List -Value $Constraints)
            success_criteria = [string[]](Split-List -Value $SuccessCriteria)
            status = "open"
            created_at = Get-UtcNow
            updated_at = Get-UtcNow
        }

        $remoteCreated = $null
        if (Use-Remote -Config $config) {
            $remoteCreated = Invoke-MimSafely -Config $config -Operation "POST /objectives" -ApiCall {
                New-MimObjective -BaseUrl $config.mim_base_url -TimeoutSeconds ([int]$config.timeout_seconds) -Objective $obj
            }
        }

        if ($remoteCreated -and $remoteCreated.PSObject.Properties["objective_id"]) {
            $obj.id = [string]$remoteCreated.objective_id
            if ($remoteCreated.PSObject.Properties["status"]) {
                $obj.status = [string]$remoteCreated.status
            }
            if ($remoteCreated.PSObject.Properties["created_at"] -and -not [string]::IsNullOrWhiteSpace([string]$remoteCreated.created_at)) {
                $obj.created_at = [string]$remoteCreated.created_at
            }
            $obj.updated_at = Get-UtcNow
            $obj | Add-Member -NotePropertyName remote_objective_id -NotePropertyValue ([string]$remoteCreated.objective_id) -Force
        }

        $persistLocal = (Use-Local -Config $config)
        if ((([string]$config.mode).ToLowerInvariant() -eq "hybrid") -and $null -eq $remoteCreated -and -not [bool]$config.fallback_to_local) {
            throw "MIM objective creation failed and fallback_to_local=false."
        }

        if ($persistLocal) {
            $state.objectives += $obj
            $journalAction = if ($remoteCreated) { "create_objective_remote_cached" } else { "create_objective" }
            Add-Journal -State $state -Actor "user" -ActionName $journalAction -EntityType "objective" -EntityId ([string]$obj.id) -Payload $obj
            Save-State -State $state
        }

        if (Use-Local -Config $config) {
            if ($remoteCreated) {
                [pscustomobject]@{
                    mode = $config.mode
                    local = $obj
                    remote = $remoteCreated
                } | ConvertTo-Json -Depth 12
            }
            else {
                $obj | ConvertTo-Json -Depth 8
            }
        }
        else {
            $remoteCreated | ConvertTo-Json -Depth 12
        }
    }

    "list-objectives" {
        if (Use-Remote -Config $config) {
            $remoteObjectives = Invoke-MimSafely -Config $config -Operation "GET /objectives" -ApiCall {
                Get-MimObjectives -BaseUrl $config.mim_base_url -TimeoutSeconds ([int]$config.timeout_seconds)
            }

            if ($null -ne $remoteObjectives) {
                $remoteObjectives | ConvertTo-Json -Depth 12
                break
            }
        }

        $state.objectives | Select-Object id, title, priority, status, updated_at | Format-Table -AutoSize
    }

    "add-task" {
        if ([string]::IsNullOrWhiteSpace($ObjectiveId)) { throw "-ObjectiveId is required" }
        if ([string]::IsNullOrWhiteSpace($Title)) { throw "-Title is required" }
        if ([string]::IsNullOrWhiteSpace($Scope)) { throw "-Scope is required" }
        if ([string]::IsNullOrWhiteSpace($AcceptanceCriteria)) { throw "-AcceptanceCriteria is required" }

        $safeTitle = Limit-StateTextField -Value ([string]$Title) -MaxLength 512 -FieldName "task.title"
        $safeScope = Limit-StateTextField -Value ([string]$Scope) -MaxLength 8192 -FieldName "task.scope"
        $safeAcceptanceCriteria = Limit-StateTextArray -Values (Split-List -Value $AcceptanceCriteria) -MaxItemLength 2048 -FieldName "task.acceptance_criteria[]"

        if (Use-Local -Config $config) {
            $objective = $state.objectives | Where-Object { $_.id -eq $ObjectiveId } | Select-Object -First 1
            if (-not $objective) { throw "Objective not found: $ObjectiveId" }
        }

        $id = New-Id -Prefix "TSK" -Count $state.tasks.Count
        $task = [pscustomobject]@{
            id = $id
            objective_id = $ObjectiveId
            title = $safeTitle
            type = $Type
            task_category = $(if ([string]::IsNullOrWhiteSpace($TaskCategory)) { "" } else { $TaskCategory })
            scope = $safeScope
            dependencies = [string[]](Split-List -Value $Dependencies)
            acceptance_criteria = [string[]]$safeAcceptanceCriteria
            status = "planned"
            assigned_executor = $AssignedExecutor
            created_at = Get-UtcNow
            updated_at = Get-UtcNow
        }

        $remoteCreated = $null
        $remoteObjectiveId = $null
        if (Use-Remote -Config $config) {
            $remoteObjectiveId = Resolve-RemoteObjectiveId -ObjectiveId $ObjectiveId -State $state
            $remoteCreated = Invoke-MimSafely -Config $config -Operation "POST /tasks" -ApiCall {
                New-MimTask -BaseUrl $config.mim_base_url -TimeoutSeconds ([int]$config.timeout_seconds) -Task $task -RemoteObjectiveId $remoteObjectiveId
            }
        }

        if ($remoteCreated -and $remoteCreated.PSObject.Properties["task_id"]) {
            $task.id = [string]$remoteCreated.task_id
            if ($null -ne $remoteObjectiveId) {
                $task.objective_id = [string]$remoteObjectiveId
            }
            if ($remoteCreated.PSObject.Properties["status"]) {
                $task.status = [string]$remoteCreated.status
            }
            $task.updated_at = Get-UtcNow
            $task | Add-Member -NotePropertyName remote_task_id -NotePropertyValue ([string]$remoteCreated.task_id) -Force
        }

        if ((Use-Local -Config $config) -or ((([string]$config.mode).ToLowerInvariant() -eq "hybrid") -and $null -eq $remoteCreated -and [bool]$config.fallback_to_local)) {
            $state.tasks += $task
            $journalAction = if ($remoteCreated) { "add_task_remote_cached" } else { "add_task" }
            Add-Journal -State $state -Actor "tod" -ActionName $journalAction -EntityType "task" -EntityId ([string]$task.id) -Payload $task
            Save-State -State $state
        }

        if (Use-Local -Config $config) {
            if ($remoteCreated) {
                [pscustomobject]@{
                    mode = $config.mode
                    local = $task
                    remote = $remoteCreated
                } | ConvertTo-Json -Depth 12
            }
            else {
                $task | ConvertTo-Json -Depth 8
            }
        }
        else {
            $remoteCreated | ConvertTo-Json -Depth 12
        }
    }

    "list-tasks" {
        if (Use-Remote -Config $config) {
            $remoteTasks = Invoke-MimSafely -Config $config -Operation "GET /tasks" -ApiCall {
                Get-MimTasks -BaseUrl $config.mim_base_url -ObjectiveId $ObjectiveId -TimeoutSeconds ([int]$config.timeout_seconds)
            }

            if ($null -ne $remoteTasks) {
                $remoteTasks | ConvertTo-Json -Depth 12
                break
            }
        }

        $tasks = $state.tasks
        if (-not [string]::IsNullOrWhiteSpace($ObjectiveId)) {
            $tasks = $tasks | Where-Object { $_.objective_id -eq $ObjectiveId }
        }
        $tasks | Select-Object id, objective_id, title, type, status, assigned_executor, updated_at | Format-Table -AutoSize
    }

    "package-task" {
        if ([string]::IsNullOrWhiteSpace($TaskId)) { throw "-TaskId is required" }
        Assert-Exists -Path $templatePath -Name "Prompt template"

        $task = $state.tasks | Where-Object { $_.id -eq $TaskId } | Select-Object -First 1
        if (-not $task) { throw "Task not found: $TaskId" }

        $objective = $state.objectives | Where-Object { $_.id -eq $task.objective_id } | Select-Object -First 1
        if (-not $objective) { throw "Objective not found for task: $($task.objective_id)" }

        $template = Get-Content -Path $templatePath -Raw
        $rendered = $template
        $rendered = $rendered.Replace("{{OBJECTIVE_ID}}", [string]$objective.id)
        $rendered = $rendered.Replace("{{OBJECTIVE_TITLE}}", [string]$objective.title)
        $rendered = $rendered.Replace("{{OBJECTIVE_DESCRIPTION}}", [string]$objective.description)
        $rendered = $rendered.Replace("{{OBJECTIVE_PRIORITY}}", [string]$objective.priority)
        $rendered = $rendered.Replace("{{OBJECTIVE_CONSTRAINTS}}", (($objective.constraints) -join ", "))
        $rendered = $rendered.Replace("{{OBJECTIVE_SUCCESS_CRITERIA}}", (($objective.success_criteria) -join ", "))
        $rendered = $rendered.Replace("{{TASK_ID}}", [string]$task.id)
        $rendered = $rendered.Replace("{{TASK_TITLE}}", [string]$task.title)
        $rendered = $rendered.Replace("{{TASK_TYPE}}", [string]$task.type)
        $rendered = $rendered.Replace("{{TASK_SCOPE}}", [string]$task.scope)
        $rendered = $rendered.Replace("{{TASK_DEPENDENCIES}}", (($task.dependencies) -join ", "))
        $rendered = $rendered.Replace("{{TASK_ACCEPTANCE_CRITERIA}}", (($task.acceptance_criteria) -join ", "))
        $rendered = $rendered.Replace("{{TASK_ASSIGNED_EXECUTOR}}", [string]$task.assigned_executor)

        if (-not (Test-Path -Path $promptOutDir)) {
            New-Item -ItemType Directory -Path $promptOutDir -Force | Out-Null
        }

        $outPath = Join-Path $promptOutDir ("{0}.md" -f $TaskId)
        Set-Content -Path $outPath -Value $rendered

        $task.status = "packaged"
        $task.updated_at = Get-UtcNow
        Add-Journal -State $state -Actor "tod" -ActionName "package_task" -EntityType "task" -EntityId $TaskId -Payload @{ prompt_path = $outPath }
        Save-State -State $state
        Write-Host "Packaged task prompt: $outPath" -ForegroundColor Green
    }

    "invoke-engine" {
        if ([string]::IsNullOrWhiteSpace($TaskId)) { throw "-TaskId is required" }

        $task = Get-TaskFromState -State $state -TaskId $TaskId
        if (-not $task) { throw "Task not found in local state cache: $TaskId" }
        $taskCategoryResolved = Resolve-TaskCategory -Task $task
        $actionEngineConfig = Resolve-ExecutionEngineConfig -Config $config -State $state -DisableAdaptiveRouting:$ForceConfiguredEngine -TaskCategoryHint $taskCategoryResolved -Task $task
        $routingPre = Add-RoutingDecisionRecord -State $state -TaskId $TaskId -ActionName "invoke_engine" -EngineConfig $actionEngineConfig -TaskCategory $taskCategoryResolved -FinalOutcome "pre_invocation"
        $routingPre = @($routingPre | Select-Object -First 1)

        if ($actionEngineConfig.routing -and $actionEngineConfig.routing.PSObject.Properties["blocked"] -and [bool]$actionEngineConfig.routing.blocked) {
            $routingFinal = Update-RoutingDecisionRecord -State $state -RoutingDecisionId ([string]$routingPre[0].id) -FinalOutcome "blocked_pre_invocation"
            Add-Journal -State $state -Actor "tod" -ActionName "invoke_engine_blocked" -EntityType "task" -EntityId $TaskId -Payload ([pscustomobject]@{
                    task_category = $taskCategoryResolved
                    routing_decision_id = [string]$routingFinal.id
                    routing_decision = $routingFinal
                })
            Save-State -State $state

            [pscustomobject]@{
                task_id = [string]$TaskId
                task_category = $taskCategoryResolved
                blocked = $true
                routing_decision_preinvoke = $routingPre[0]
                routing_decision = $routingFinal
                message = "Routing guardrail blocked execution before engine invocation."
            } | ConvertTo-Json -Depth 12
            break
        }

        $packagePath = Resolve-TaskPackagePath -TaskId $TaskId -ExplicitPath $PackagePath
        $invokeResult = Invoke-ExecutionEngine -Task $task -TaskId $TaskId -PackagePath $packagePath -EngineConfig $actionEngineConfig
        $routingRecord = Update-RoutingDecisionRecord -State $state -RoutingDecisionId ([string]$routingPre[0].id) -FinalOutcome ([string]$invokeResult.result.status) -InvokeResult $invokeResult

        Add-Journal -State $state -Actor "tod" -ActionName "invoke_engine" -EntityType "task" -EntityId $TaskId -Payload ([pscustomobject]@{
                package_path = $packagePath
                attempted_engines = @($invokeResult.attempted_engines)
                active_engine = [string]$invokeResult.active_engine
                fallback_applied = [bool]$invokeResult.fallback_applied
                status = [string]$invokeResult.result.status
                routing_decision_id = [string]$routingRecord.id
                routing_decision = $routingRecord
            })
        Save-State -State $state

        [pscustomobject]@{
            task_id = [string]$invokeResult.task_id
            package_path = [string]$invokeResult.package_path
            attempted_engines = @($invokeResult.attempted_engines)
            active_engine = [string]$invokeResult.active_engine
            fallback_applied = [bool]$invokeResult.fallback_applied
            routing_decision_preinvoke = $routingPre[0]
            routing_decision = $routingRecord
            result = $invokeResult.result
        } | ConvertTo-Json -Depth 12
    }

    "run-task" {
        if ([string]::IsNullOrWhiteSpace($TaskId)) { throw "-TaskId is required" }

        $task = Get-TaskFromState -State $state -TaskId $TaskId
        if ((-not $task) -and [string]$stateAccess.mode -eq "remote_ephemeral") {
            $task = Resolve-RemoteExecutionTask -TaskId $TaskId -ObjectiveId $ObjectiveId -Config $config
            if ($task) {
                $state.tasks += $task
            }
        }
        if (-not $task) {
            $bridgeHint = Get-ListenerRequestBridgeHint -TaskId $TaskId
            throw (Get-RemoteTaskResolutionFailureMessage -TaskId $TaskId -BridgeHint $bridgeHint)
        }
        $feedbackConfig = Resolve-ExecutionFeedbackConfig -Config $config
        $resolvedExecutionId = Resolve-ExecutionIdForTask -ExplicitExecutionId $ExecutionId -Task $task
        $taskRequestId = [string]$TaskId
        $taskCorrelationId = if ($task.PSObject.Properties['correlation_id']) { [string]$task.correlation_id } else { '' }
        $taskTitle = if ($task.PSObject.Properties['title']) { [string]$task.title } else { '' }
        $feedbackEvents = @()
        $memoryProfile = [ordered]@{
            before_execution = Get-ProcessMemorySnapshot
            after_execution = $null
            after_result_persist = $null
            peak_private_memory_mb = $null
        }
        $taskCategoryResolved = Resolve-TaskCategory -Task $task
        $actionEngineConfig = Resolve-ExecutionEngineConfig -Config $config -State $state -DisableAdaptiveRouting:$ForceConfiguredEngine -TaskCategoryHint $taskCategoryResolved -Task $task
        $routingPre = Add-RoutingDecisionRecord -State $state -TaskId $TaskId -ActionName "run_task" -EngineConfig $actionEngineConfig -TaskCategory $taskCategoryResolved -FinalOutcome "pre_invocation"
        $routingPre = @($routingPre | Select-Object -First 1)
        $taskMaterialization = Resolve-TaskBoundedEditMaterialization -Task $task
        $task | Add-Member -NotePropertyName materialization -NotePropertyValue $taskMaterialization -Force
        Publish-TodActivityEvent -EventType 'task_start' -ObjectiveId ([string]$task.objective_id) -TaskId $TaskId -RequestId $taskRequestId -ExecutionId $resolvedExecutionId -CorrelationId $taskCorrelationId -Title $taskTitle -Step 'task_intake' -Status 'active' -Message 'Accepted bounded task for execution.' -Details ([ordered]@{
                task_category = $taskCategoryResolved
                assigned_executor = if ($task.PSObject.Properties['assigned_executor']) { [string]$task.assigned_executor } else { '' }
                routing_active_engine = [string]$actionEngineConfig.active
                fallback_engine = [string]$actionEngineConfig.fallback
                routing = if ($actionEngineConfig.PSObject.Properties['routing']) { $actionEngineConfig.routing } else { $null }
                execution_readiness = $executionReadinessGate.trace
            }) -Source 'tod.run-task' -Surface 'tod-run-task' -Summary ([string]$task.scope) -CurrentAction 'Accepted bounded task for execution.' | Out-Null
        if ([bool]$stateAccess.local_cache_enabled) {
            Save-State -State $state
        }

        if ($executionReadinessGate.blocked) {
            Publish-TodActivityEvent -EventType 'failure' -ObjectiveId ([string]$task.objective_id) -TaskId $TaskId -RequestId $taskRequestId -ExecutionId $resolvedExecutionId -CorrelationId $taskCorrelationId -Title $taskTitle -Step 'task_intake' -Status 'blocked' -Message 'Execution readiness policy blocked the task before engine invocation.' -Details ([ordered]@{
                    reason = 'execution_readiness_blocked'
                    task_category = $taskCategoryResolved
                    execution_readiness = $executionReadinessGate.trace
                }) -Source 'tod.run-task' -Surface 'tod-run-task' -Summary 'run-task blocked by execution-readiness policy.' -CurrentAction 'Blocked bounded task before engine invocation.' -RecoveryState 'required' | Out-Null
            $blockedFeedback = Try-PublishExecutionFeedback -Config $config -FeedbackConfig $feedbackConfig -ExecutionId $resolvedExecutionId -Status "blocked" -TaskId $TaskId -Details ([pscustomobject]@{
                    reason = "readiness_policy_blocked"
                    task_category = $taskCategoryResolved
                    execution_readiness = $executionReadinessGate.trace
                })
            $feedbackEvents += @([pscustomobject]@{ status = "blocked"; publish = $blockedFeedback })
            Add-Journal -State $state -Actor "tod" -ActionName "run_task_blocked" -EntityType "task" -EntityId $TaskId -Payload ([pscustomobject]@{
                    task_category = $taskCategoryResolved
                    reason = "execution_readiness_blocked"
                    execution_readiness = $executionReadinessGate.trace
                })
            if ([bool]$stateAccess.local_cache_enabled) {
                Save-State -State $state
            }

            [pscustomobject]@{
                task_id = [string]$TaskId
                execution_id = [string]$resolvedExecutionId
                task_category = $taskCategoryResolved
                decision = "blocked"
                blocked = $true
                execution_feedback = @($feedbackEvents)
                execution_readiness = $executionReadinessGate.trace
                execution_trace = [pscustomobject]@{
                    action = "run-task"
                    execution_readiness = $executionReadinessGate.trace
                }
                routing_decision_preinvoke = $routingPre[0]
                message = "run-task blocked by execution-readiness policy before engine invocation."
                state_access = $stateAccess
                memory_profile = [pscustomobject]$memoryProfile
            } | ConvertTo-Json -Depth 14
            break
        }

        if ($actionEngineConfig.routing -and $actionEngineConfig.routing.PSObject.Properties["blocked"] -and [bool]$actionEngineConfig.routing.blocked) {
            Publish-TodActivityEvent -EventType 'failure' -ObjectiveId ([string]$task.objective_id) -TaskId $TaskId -RequestId $taskRequestId -ExecutionId $resolvedExecutionId -CorrelationId $taskCorrelationId -Title $taskTitle -Step 'task_intake' -Status 'blocked' -Message 'Routing guardrail blocked the task before engine invocation.' -Details ([ordered]@{
                reason = 'guardrail_blocked'
                task_category = $taskCategoryResolved
                routing = $actionEngineConfig.routing
            }) -Source 'tod.run-task' -Surface 'tod-run-task' -Summary 'run-task blocked by routing guardrail.' -CurrentAction 'Blocked bounded task before engine invocation.' -RecoveryState 'required' | Out-Null
            $routingFinalBlocked = Update-RoutingDecisionRecord -State $state -RoutingDecisionId ([string]$routingPre[0].id) -FinalOutcome "escalated_pre_run"
            Add-Journal -State $state -Actor "tod" -ActionName "run_task_blocked" -EntityType "task" -EntityId $TaskId -Payload ([pscustomobject]@{
                    task_category = $taskCategoryResolved
                    routing_decision_id = [string]$routingFinalBlocked.id
                    routing_decision = $routingFinalBlocked
                })
            $blockedFeedback = Try-PublishExecutionFeedback -Config $config -FeedbackConfig $feedbackConfig -ExecutionId $resolvedExecutionId -Status "blocked" -TaskId $TaskId -Details ([pscustomobject]@{
                    reason = "guardrail_blocked"
                    routing_decision_id = [string]$routingFinalBlocked.id
                    task_category = $taskCategoryResolved
                })
            $feedbackEvents += @([pscustomobject]@{ status = "blocked"; publish = $blockedFeedback })
            if ([bool]$stateAccess.local_cache_enabled) {
                Save-State -State $state
            }

            [pscustomobject]@{
                task_id = [string]$TaskId
                execution_id = [string]$resolvedExecutionId
                task_category = $taskCategoryResolved
                decision = "escalate"
                blocked = $true
                execution_feedback = @($feedbackEvents)
                execution_readiness = $executionReadinessGate.trace
                execution_trace = [pscustomobject]@{
                    action = "run-task"
                    execution_readiness = $executionReadinessGate.trace
                }
                routing_decision_preinvoke = $routingPre[0]
                routing_decision = $routingFinalBlocked
                message = "run-task blocked by routing guardrail before engine invocation."
                state_access = $stateAccess
                memory_profile = [pscustomobject]$memoryProfile
            } | ConvertTo-Json -Depth 14
            break
        }

        $packagePath = Resolve-TaskPackagePath -TaskId $TaskId -ExplicitPath $PackagePath
        $invokeResult = $null
        $allowLocalExecutionWithoutMaterialization = $false
        if ([string]::Equals([string]$actionEngineConfig.active, 'local', [System.StringComparison]::OrdinalIgnoreCase)) {
            $allowLocalExecutionWithoutMaterialization = Test-TaskAllowsLocalExecutionWithoutMaterialization -Task $task -TaskCategory $taskCategoryResolved -TaskMaterialization $taskMaterialization
        }

        if ($taskMaterialization.PSObject.Properties['status'] -and [string]::Equals([string]$taskMaterialization.status, 'materialized', [System.StringComparison]::OrdinalIgnoreCase)) {
            Publish-TodActivityEvent -EventType 'bounded_edit_materialized' -ObjectiveId ([string]$task.objective_id) -TaskId $TaskId -RequestId $taskRequestId -ExecutionId $resolvedExecutionId -CorrelationId $taskCorrelationId -Title $taskTitle -Step 'task_intake' -Status 'completed' -Message 'TOD materialized the direct-chat task into explicit bounded edit directives.' -Details ([ordered]@{
                    edit_mode = [string]$taskMaterialization.edit_mode
                    target_files = if ($taskMaterialization.PSObject.Properties['target_files']) { @($taskMaterialization.target_files) } else { @() }
                    validation_plan = if ($taskMaterialization.PSObject.Properties['validation_plan']) { $taskMaterialization.validation_plan } else { $null }
                }) -Source 'tod.run-task' -Surface 'tod-run-task' -Summary ([string]$task.scope) -CurrentAction 'Prepared explicit bounded edit directives.' | Out-Null
            if ([string]::Equals([string]$actionEngineConfig.active, 'local', [System.StringComparison]::OrdinalIgnoreCase)) {
                Publish-TodActivityEvent -EventType 'local_executor_ready' -ObjectiveId ([string]$task.objective_id) -TaskId $TaskId -RequestId $taskRequestId -ExecutionId $resolvedExecutionId -CorrelationId $taskCorrelationId -Title $taskTitle -Step 'task_intake' -Status 'completed' -Message 'LocalExecutionEngine has an explicit bounded edit mode and target file.' -Details ([ordered]@{
                        edit_mode = [string]$taskMaterialization.edit_mode
                        target_files = if ($taskMaterialization.PSObject.Properties['target_files']) { @($taskMaterialization.target_files) } else { @() }
                    }) -Source 'tod.run-task' -Surface 'tod-run-task' -Summary ([string]$task.scope) -CurrentAction 'Prepared LocalExecutionEngine invocation.' | Out-Null
            }
        }
        elseif ([string]::Equals([string]$actionEngineConfig.active, 'local', [System.StringComparison]::OrdinalIgnoreCase) -and -not $allowLocalExecutionWithoutMaterialization) {
            Publish-TodActivityEvent -EventType 'bounded_edit_mode_missing' -ObjectiveId ([string]$task.objective_id) -TaskId $TaskId -RequestId $taskRequestId -ExecutionId $resolvedExecutionId -CorrelationId $taskCorrelationId -Title $taskTitle -Step 'task_intake' -Status 'blocked' -Message 'TOD could not derive a bounded edit mode for LocalExecutionEngine.' -Details ([ordered]@{
                    reason_code = if ($taskMaterialization.PSObject.Properties['reason_code']) { [string]$taskMaterialization.reason_code } else { 'blocked_missing_bounded_edit_mode' }
                    target_file_candidates = if ($taskMaterialization.PSObject.Properties['target_file_candidates']) { @($taskMaterialization.target_file_candidates) } else { @() }
                    required_clarification = if ($taskMaterialization.PSObject.Properties['required_clarification']) { @($taskMaterialization.required_clarification) } else { @() }
                    why_local_executor_cannot_proceed = if ($taskMaterialization.PSObject.Properties['why_local_executor_cannot_proceed']) { [string]$taskMaterialization.why_local_executor_cannot_proceed } else { '' }
                }) -Source 'tod.run-task' -Surface 'tod-run-task' -Summary ([string]$task.scope) -CurrentAction 'Blocked LocalExecutionEngine before invocation.' -RecoveryState 'required' | Out-Null
            Set-PersistedTaskTerminalState -Task $task -Status 'blocked' -EventType 'bounded_edit_mode_missing' -Message 'TOD could not derive a bounded edit mode for LocalExecutionEngine.' -ReasonCode $(if ($taskMaterialization.PSObject.Properties['reason_code']) { [string]$taskMaterialization.reason_code } else { 'blocked_missing_bounded_edit_mode' }) -Details ([pscustomobject]@{
                    target_file_candidates = if ($taskMaterialization.PSObject.Properties['target_file_candidates']) { @($taskMaterialization.target_file_candidates) } else { @() }
                    required_clarification = if ($taskMaterialization.PSObject.Properties['required_clarification']) { @($taskMaterialization.required_clarification) } else { @() }
                    why_local_executor_cannot_proceed = if ($taskMaterialization.PSObject.Properties['why_local_executor_cannot_proceed']) { [string]$taskMaterialization.why_local_executor_cannot_proceed } else { '' }
                }) -TaskStatus 'blocked'
            Save-State -State $state
            $invokeResult = New-RunTaskMaterializationBlockedResult -Task $task -Materialization $taskMaterialization -TaskId $TaskId -ActionEngineConfig $actionEngineConfig -PackagePath $packagePath
            $memoryProfile.after_execution = Get-ProcessMemorySnapshot
        }
        elseif ($allowLocalExecutionWithoutMaterialization) {
            Publish-TodActivityEvent -EventType 'local_executor_ready' -ObjectiveId ([string]$task.objective_id) -TaskId $TaskId -RequestId $taskRequestId -ExecutionId $resolvedExecutionId -CorrelationId $taskCorrelationId -Title $taskTitle -Step 'task_intake' -Status 'completed' -Message 'LocalExecutionEngine can execute this bounded observe-only task without edit directives.' -Details ([ordered]@{
                    task_category = $taskCategoryResolved
                    reason = 'local_non_edit_execution_allowed'
                }) -Source 'tod.run-task' -Surface 'tod-run-task' -Summary ([string]$task.scope) -CurrentAction 'Prepared LocalExecutionEngine invocation without edit directives.' | Out-Null
        }
        Publish-TodActivityEvent -EventType 'step_start' -ObjectiveId ([string]$task.objective_id) -TaskId $TaskId -RequestId $taskRequestId -ExecutionId $resolvedExecutionId -CorrelationId $taskCorrelationId -Title $taskTitle -Step 'engine_invocation' -Status 'active' -Message ('Starting execution with engine ' + [string]$actionEngineConfig.active + '.') -Details ([ordered]@{
                package_path = $packagePath
                task_category = $taskCategoryResolved
                active_engine = [string]$actionEngineConfig.active
                fallback_engine = [string]$actionEngineConfig.fallback
            }) -Source 'tod.run-task' -Surface 'tod-run-task' -Summary ([string]$task.scope) -CurrentAction 'Invoking the selected execution engine.' | Out-Null
        if ([string]::Equals([string]$actionEngineConfig.active, 'local', [System.StringComparison]::OrdinalIgnoreCase)) {
            Publish-TodActivityEvent -EventType 'local_executor_invoked' -ObjectiveId ([string]$task.objective_id) -TaskId $TaskId -RequestId $taskRequestId -ExecutionId $resolvedExecutionId -CorrelationId $taskCorrelationId -Title $taskTitle -Step 'engine_invocation' -Status 'active' -Message 'Dispatching the bounded task through LocalExecutionEngine.' -Details ([ordered]@{
                    package_path = $packagePath
                    task_category = $taskCategoryResolved
                    active_engine = [string]$actionEngineConfig.active
                    fallback_engine = [string]$actionEngineConfig.fallback
                }) -Source 'tod.run-task' -Surface 'tod-run-task' -Summary ([string]$task.scope) -CurrentAction 'Invoking LocalExecutionEngine.' | Out-Null
        }
        if ([string]::Equals([string]$actionEngineConfig.active, 'codex', [System.StringComparison]::OrdinalIgnoreCase)) {
            Publish-TodActivityEvent -EventType 'codex_handoff' -ObjectiveId ([string]$task.objective_id) -TaskId $TaskId -RequestId $taskRequestId -ExecutionId $resolvedExecutionId -CorrelationId $taskCorrelationId -Title $taskTitle -Step 'engine_invocation' -Status 'active' -Message 'Handing the bounded task to Codex.' -Details ([ordered]@{
                    package_path = $packagePath
                    routing = if ($actionEngineConfig.PSObject.Properties['routing']) { $actionEngineConfig.routing } else { $null }
                    fallback_engine = [string]$actionEngineConfig.fallback
                }) -Source 'tod.run-task' -Surface 'tod-run-task' -Summary 'Codex selected as the active execution engine.' -CurrentAction 'Handing the bounded task to Codex.' | Out-Null
        }
        $acceptedFeedback = Try-PublishExecutionFeedback -Config $config -FeedbackConfig $feedbackConfig -ExecutionId $resolvedExecutionId -Status "accepted" -TaskId $TaskId -Details ([pscustomobject]@{
                task_category = $taskCategoryResolved
                package_path = $packagePath
                assigned_executor = if ($task.PSObject.Properties["assigned_executor"]) { [string]$task.assigned_executor } else { "" }
            })
        $feedbackEvents += @([pscustomobject]@{ status = "accepted"; publish = $acceptedFeedback })

        $runningFeedback = Try-PublishExecutionFeedback -Config $config -FeedbackConfig $feedbackConfig -ExecutionId $resolvedExecutionId -Status "running" -TaskId $TaskId -Details ([pscustomobject]@{
                task_category = $taskCategoryResolved
                package_path = $packagePath
            })
        $feedbackEvents += @([pscustomobject]@{ status = "running"; publish = $runningFeedback })

        if ($null -eq $invokeResult) {
            try {
                $invokeResult = Invoke-ExecutionEngine -Task $task -TaskId $TaskId -PackagePath $packagePath -EngineConfig $actionEngineConfig
                $memoryProfile.after_execution = Get-ProcessMemorySnapshot
            }
            catch {
                $memoryProfile.after_execution = Get-ProcessMemorySnapshot
                Publish-TodActivityEvent -EventType 'failure' -ObjectiveId ([string]$task.objective_id) -TaskId $TaskId -RequestId $taskRequestId -ExecutionId $resolvedExecutionId -CorrelationId $taskCorrelationId -Title $taskTitle -Step 'engine_invocation' -Status 'failed' -Message 'Execution engine invocation threw before result normalization.' -Details ([ordered]@{
                        reason = 'executor_unavailable'
                        task_category = $taskCategoryResolved
                        error = [string]$_.Exception.Message
                        active_engine = [string]$actionEngineConfig.active
                    }) -Source 'tod.run-task' -Surface 'tod-run-task' -Summary 'Executor unavailable during run-task.' -CurrentAction 'Execution engine invocation failed.' -RecoveryState 'required' | Out-Null
                $failedFeedback = Try-PublishExecutionFeedback -Config $config -FeedbackConfig $feedbackConfig -ExecutionId $resolvedExecutionId -Status "failed" -TaskId $TaskId -Details ([pscustomobject]@{
                        reason = "executor_unavailable"
                        task_category = $taskCategoryResolved
                        error = [string]$_.Exception.Message
                    })
                $feedbackEvents += @([pscustomobject]@{ status = "failed"; publish = $failedFeedback })
                throw
            }
        }

        $resultPayload = $invokeResult.result
        foreach ($attempt in @($invokeResult.attempts)) {
            if ($null -eq $attempt) {
                continue
            }

            $attemptEngine = if ($attempt.PSObject.Properties['engine']) { [string]$attempt.engine } else { '' }
            $attemptStatus = if ($attempt.PSObject.Properties['status']) { [string]$attempt.status } else { 'unknown' }
            if ([string]::Equals($attemptEngine, 'codex', [System.StringComparison]::OrdinalIgnoreCase)) {
                Publish-TodActivityEvent -EventType 'codex_response' -ObjectiveId ([string]$task.objective_id) -TaskId $TaskId -RequestId $taskRequestId -ExecutionId $resolvedExecutionId -CorrelationId $taskCorrelationId -Title $taskTitle -Step 'engine_invocation' -Status $(if ([string]::Equals($attemptStatus, 'completed', [System.StringComparison]::OrdinalIgnoreCase)) { 'completed' } else { 'active' }) -Message ('Codex attempt ' + [string]$attempt.attempt + ' returned status ' + $attemptStatus + '.') -Details ([ordered]@{
                        engine = $attemptEngine
                        attempt = if ($attempt.PSObject.Properties['attempt']) { [int]$attempt.attempt } else { 1 }
                        retryable = if ($attempt.PSObject.Properties['retryable']) { [bool]$attempt.retryable } else { $false }
                        failure_category = if ($attempt.PSObject.Properties['failure_category']) { [string]$attempt.failure_category } else { '' }
                        message = if ($attempt.PSObject.Properties['message']) { [string]$attempt.message } else { '' }
                    }) -Source 'tod.run-task' -Surface 'tod-run-task' -Summary 'Codex execution attempt completed.' -CurrentAction 'Processed the Codex response.' | Out-Null
            }
            if ($attempt.PSObject.Properties['attempt'] -and [int]$attempt.attempt -gt 1) {
                Publish-TodActivityEvent -EventType 'retry' -ObjectiveId ([string]$task.objective_id) -TaskId $TaskId -RequestId $taskRequestId -ExecutionId $resolvedExecutionId -CorrelationId $taskCorrelationId -Title $taskTitle -Step 'engine_invocation' -Status 'active' -Message ('Retry attempt ' + [string]$attempt.attempt + ' executed on engine ' + $attemptEngine + '.') -Details ([ordered]@{
                        engine = $attemptEngine
                        attempt = [int]$attempt.attempt
                        status = $attemptStatus
                        retryable = if ($attempt.PSObject.Properties['retryable']) { [bool]$attempt.retryable } else { $false }
                        failure_category = if ($attempt.PSObject.Properties['failure_category']) { [string]$attempt.failure_category } else { '' }
                    }) -Source 'tod.run-task' -Surface 'tod-run-task' -Summary 'Retry executed during engine invocation.' -CurrentAction 'Retrying the bounded execution path.' | Out-Null
            }
        }
        $hasExplicitEngineBlocker = $resultPayload.PSObject.Properties['reason_code'] -and -not [string]::IsNullOrWhiteSpace([string]$resultPayload.reason_code)
        $noOpAssessment = Get-LocalExecutionNoOpAssessment -Task $task -ResultPayload $resultPayload
        $resultPayload | Add-Member -NotePropertyName no_op_assessment -NotePropertyValue $noOpAssessment -Force
        $localEngineAttempted = (@($invokeResult.attempted_engines | ForEach-Object { ([string]$_).ToLowerInvariant() }) -contains 'local')
        $localEngineActive = [string]::Equals([string]$invokeResult.active_engine, 'local', [System.StringComparison]::OrdinalIgnoreCase)
        Publish-TodActivityEvent -EventType 'step_complete' -ObjectiveId ([string]$task.objective_id) -TaskId $TaskId -RequestId $taskRequestId -ExecutionId $resolvedExecutionId -CorrelationId $taskCorrelationId -Title $taskTitle -Step 'engine_invocation' -Status $(if ($hasExplicitEngineBlocker -or [bool]$noOpAssessment.detected) { 'blocked' } else { 'completed' }) -Message 'Execution engine returned a normalized result envelope.' -Details ([ordered]@{
                attempted_engines = @($invokeResult.attempted_engines)
                fallback_applied = [bool]$invokeResult.fallback_applied
                failure_category = if ($invokeResult.PSObject.Properties['failure_category']) { [string]$invokeResult.failure_category } else { 'none' }
                reason_code = if ($resultPayload.PSObject.Properties['reason_code']) { [string]$resultPayload.reason_code } else { '' }
                no_op_detected = [bool]$noOpAssessment.detected
                summary = [string]$resultPayload.summary
            }) -Source 'tod.run-task' -Surface 'tod-run-task' -Summary ([string]$resultPayload.summary) -CurrentAction 'Normalized the engine result.' -ExecutionState ([string]$resultPayload.status) | Out-Null
        if ($localEngineAttempted -or $localEngineActive) {
            if ($hasExplicitEngineBlocker -or [bool]$noOpAssessment.detected) {
                Publish-TodActivityEvent -EventType 'blocked_missing_local_executor_result' -ObjectiveId ([string]$task.objective_id) -TaskId $TaskId -RequestId $taskRequestId -ExecutionId $resolvedExecutionId -CorrelationId $taskCorrelationId -Title $taskTitle -Step 'engine_invocation' -Status 'blocked' -Message 'LocalExecutionEngine returned a blocked or non-meaningful result for the bounded task.' -Details ([ordered]@{
                        active_engine = [string]$invokeResult.active_engine
                        attempted_engines = @($invokeResult.attempted_engines)
                        reason_code = if ($resultPayload.PSObject.Properties['reason_code']) { [string]$resultPayload.reason_code } else { '' }
                        no_op_detected = [bool]$noOpAssessment.detected
                        summary = [string]$resultPayload.summary
                    }) -Source 'tod.run-task' -Surface 'tod-run-task' -Summary ([string]$resultPayload.summary) -CurrentAction 'Captured the LocalExecutionEngine blocker.' -ExecutionState ([string]$resultPayload.status) -RecoveryState 'required' | Out-Null
            }
            else {
                Publish-TodActivityEvent -EventType 'local_executor_completed' -ObjectiveId ([string]$task.objective_id) -TaskId $TaskId -RequestId $taskRequestId -ExecutionId $resolvedExecutionId -CorrelationId $taskCorrelationId -Title $taskTitle -Step 'engine_invocation' -Status 'completed' -Message 'LocalExecutionEngine completed and returned bounded execution evidence.' -Details ([ordered]@{
                        active_engine = [string]$invokeResult.active_engine
                        attempted_engines = @($invokeResult.attempted_engines)
                        files_changed = @($resultPayload.files_changed)
                        commands_run = @($resultPayload.commands_run)
                        test_results = @($resultPayload.test_results)
                    }) -Source 'tod.run-task' -Surface 'tod-run-task' -Summary ([string]$resultPayload.summary) -CurrentAction 'Captured LocalExecutionEngine completion evidence.' -ExecutionState ([string]$resultPayload.status) | Out-Null
            }
        }
        if (@($resultPayload.files_changed).Count -gt 0) {
            Publish-TodActivityEvent -EventType 'patch_applied' -ObjectiveId ([string]$task.objective_id) -TaskId $TaskId -RequestId $taskRequestId -ExecutionId $resolvedExecutionId -CorrelationId $taskCorrelationId -Title $taskTitle -Step 'patch_writer' -Status 'completed' -Message ('Applied bounded changes to ' + [string]@(@($resultPayload.files_changed).Count) + ' file(s).') -Details ([ordered]@{
                    files_changed = @($resultPayload.files_changed)
                    diff_summary = if ($resultPayload.PSObject.Properties['diff_summary']) { [string]$resultPayload.diff_summary } else { '' }
                }) -Source 'tod.run-task' -Surface 'tod-run-task' -Summary ([string]$resultPayload.summary) -CurrentAction 'Applied a bounded patch set.' | Out-Null
            foreach ($changedFile in @($resultPayload.files_changed | Select-Object -First 12)) {
                Publish-TodActivityEvent -EventType 'file_write' -ObjectiveId ([string]$task.objective_id) -TaskId $TaskId -RequestId $taskRequestId -ExecutionId $resolvedExecutionId -CorrelationId $taskCorrelationId -Title $taskTitle -Step 'patch_writer' -Status 'completed' -Message ('Updated file ' + [string]$changedFile + '.') -Details ([ordered]@{ path = [string]$changedFile }) -Source 'tod.run-task' -Surface 'tod-run-task' -Summary ([string]$resultPayload.summary) -CurrentAction 'Recorded a changed file.' | Out-Null
            }
        }
        foreach ($commandName in @($resultPayload.commands_run | Select-Object -First 8)) {
            if ([string]::IsNullOrWhiteSpace([string]$commandName)) { continue }
            Publish-TodActivityEvent -EventType 'command_run' -ObjectiveId ([string]$task.objective_id) -TaskId $TaskId -RequestId $taskRequestId -ExecutionId $resolvedExecutionId -CorrelationId $taskCorrelationId -Title $taskTitle -Step 'command_runner' -Status 'completed' -Message ('Ran command ' + [string]$commandName + '.') -Details ([ordered]@{ command = [string]$commandName }) -Source 'tod.run-task' -Surface 'tod-run-task' -Summary ([string]$resultPayload.summary) -CurrentAction 'Captured command execution evidence.' | Out-Null
        }
        for ($testIndex = 0; $testIndex -lt @($resultPayload.tests_run).Count; $testIndex++) {
            $testName = [string]$resultPayload.tests_run[$testIndex]
            if ([string]::IsNullOrWhiteSpace($testName)) { continue }
            $testResult = if ($testIndex -lt @($resultPayload.test_results).Count) { [string]$resultPayload.test_results[$testIndex] } else { '' }
            Publish-TodActivityEvent -EventType 'test_run' -ObjectiveId ([string]$task.objective_id) -TaskId $TaskId -RequestId $taskRequestId -ExecutionId $resolvedExecutionId -CorrelationId $taskCorrelationId -Title $taskTitle -Step 'validator' -Status $(if ([string]::Equals($testResult, 'pass', [System.StringComparison]::OrdinalIgnoreCase)) { 'completed' } else { 'blocked' }) -Message ('Validation test ' + $testName + ' returned ' + $(if ([string]::IsNullOrWhiteSpace($testResult)) { 'unknown' } else { $testResult }) + '.') -Details ([ordered]@{ name = $testName; result = $testResult }) -Source 'tod.run-task' -Surface 'tod-run-task' -Summary ([string]$resultPayload.summary) -CurrentAction 'Captured focused test evidence.' | Out-Null
        }
        if ([bool]$noOpAssessment.detected -and -not $hasExplicitEngineBlocker) {
            $resultPayload.needs_escalation = $false
            $resultPayload.failures = @(@($resultPayload.failures) + @([string]$noOpAssessment.detail) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
            $resultPayload.recommendations = @(@($resultPayload.recommendations) + @('Trigger replay_or_replan_required and rerun only after a state-changing execution path is available.') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
        }
        $reviewDecision = "pass"
        if ([bool]$resultPayload.needs_escalation) {
            $reviewDecision = "escalate"
        }
        elseif (@($resultPayload.failures).Count -gt 0) {
            $reviewDecision = "revise"
        }

        $precheckWarnings = @()
        if ($resultPayload.PSObject.Properties["review_precheck"] -and $resultPayload.review_precheck -and $resultPayload.review_precheck.PSObject.Properties["warnings"]) {
            $precheckWarnings = @($resultPayload.review_precheck.warnings | ForEach-Object { [string]$_ })
            if (@($precheckWarnings).Count -gt 0 -and $reviewDecision -eq "pass") {
                $reviewDecision = "revise"
            }
        }
        if ($hasExplicitEngineBlocker) {
            $precheckWarnings = @($precheckWarnings + @([string]$resultPayload.reason_code) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
            if ($reviewDecision -eq 'pass') {
                $reviewDecision = 'revise'
            }
        }
        elseif ([bool]$noOpAssessment.detected) {
            $precheckWarnings = @($precheckWarnings + @([string]$noOpAssessment.reason_code) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
            if ($reviewDecision -eq 'pass') {
                $reviewDecision = 'revise'
            }
        }

        $rationale = "run-task completed via invoke-engine and result persistence."
        if (@($precheckWarnings).Count -gt 0) {
            $rationale = "run-task completed with precheck warnings: $($precheckWarnings -join '; ')"
        }
        if ($hasExplicitEngineBlocker) {
            $rationale = "run-task blocked with explicit engine reason: $([string]$resultPayload.reason_code)"
        }
        elseif ([bool]$noOpAssessment.detected) {
            $rationale = "run-task rejected as a no-op: $([string]$noOpAssessment.detail)"
        }

        $filesChangedCsv = (@($resultPayload.files_changed) | ForEach-Object { [string]$_ }) -join ","
        $testsRunCsv = (@($resultPayload.tests_run) | ForEach-Object { [string]$_ }) -join ","
        $testResultsCsv = (@($resultPayload.test_results) | ForEach-Object { [string]$_ }) -join ","
        $failuresCsv = (@($resultPayload.failures) | ForEach-Object { [string]$_ }) -join ","
        $recommendationsCsv = (@($resultPayload.recommendations) | ForEach-Object { [string]$_ }) -join ","
        $addResultResponse = $null
        $addResultError = ''
        try {
            $addResultResponse = (& $PSCommandPath -Action add-result -ConfigPath $configPath -StatePath $statePath -TaskId $TaskId -Summary ([string]$resultPayload.summary) -FilesChanged $filesChangedCsv -TestsRun $testsRunCsv -TestResults $testResultsCsv -Failures $failuresCsv -Recommendations $recommendationsCsv) | ConvertFrom-Json
        }
        catch {
            if (-not $SkipPostCompletionTail) {
                throw
            }

            $addResultError = [string]$_.Exception.Message
        }

        $unresolvedCsv = (@($resultPayload.failures) + @($precheckWarnings) | ForEach-Object { [string]$_ }) -join ","
        $reviewResponse = $null
        $reviewError = ''
        try {
            $reviewResponse = (& $PSCommandPath -Action review-task -ConfigPath $configPath -StatePath $statePath -TaskId $TaskId -Decision $reviewDecision -Rationale $rationale -UnresolvedIssues $unresolvedCsv) | ConvertFrom-Json
        }
        catch {
            if (-not $SkipPostCompletionTail) {
                throw
            }

            $reviewError = [string]$_.Exception.Message
        }
        $terminalEventType = if ([string]::Equals($reviewDecision, 'pass', [System.StringComparison]::OrdinalIgnoreCase)) {
            'local_executor_completed'
        }
        elseif ($resultPayload.PSObject.Properties['reason_code'] -and [string]::Equals([string]$resultPayload.reason_code, 'blocked_missing_bounded_edit_mode', [System.StringComparison]::OrdinalIgnoreCase)) {
            'bounded_edit_mode_missing'
        }
        else {
            'blocked'
        }
        $terminalStatusValue = if ([string]::Equals($reviewDecision, 'pass', [System.StringComparison]::OrdinalIgnoreCase)) { 'completed' } else { 'blocked' }
        $terminalReasonCode = if ($resultPayload.PSObject.Properties['reason_code']) { [string]$resultPayload.reason_code } else { '' }
        Set-PersistedTaskTerminalState -Task $task -Status $terminalStatusValue -EventType $terminalEventType -Message ([string]$resultPayload.summary) -ReasonCode $terminalReasonCode -Details ([pscustomobject]@{
                review_decision = $reviewDecision
                failures = @($resultPayload.failures)
                recommendations = @($resultPayload.recommendations)
                tests_run = @($resultPayload.tests_run)
                files_changed = @($resultPayload.files_changed)
                add_result_error = $addResultError
                review_error = $reviewError
            }) -TaskStatus $(if ([string]::Equals($reviewDecision, 'pass', [System.StringComparison]::OrdinalIgnoreCase)) { 'completed' } else { 'blocked' })
        Save-State -State $state
        Publish-TodActivityEvent -EventType 'validation' -ObjectiveId ([string]$task.objective_id) -TaskId $TaskId -RequestId $taskRequestId -ExecutionId $resolvedExecutionId -CorrelationId $taskCorrelationId -Title $taskTitle -Step 'validator' -Status $(if ([string]::Equals($reviewDecision, 'pass', [System.StringComparison]::OrdinalIgnoreCase)) { 'completed' } else { 'blocked' }) -Message ('Review decision resolved to ' + $reviewDecision + '.') -Details ([ordered]@{
                review_decision = $reviewDecision
                rationale = $rationale
                failures = @($resultPayload.failures)
                warnings = @($precheckWarnings)
            }) -Source 'tod.run-task' -Surface 'tod-run-task' -Summary ([string]$resultPayload.summary) -CurrentAction 'Validated the bounded execution outcome.' -ExecutionState $reviewDecision | Out-Null
        if ($SkipPostCompletionTail) {
            $memoryProfile.after_result_persist = Get-ProcessMemorySnapshot
            $memoryProfile.peak_private_memory_mb = [math]::Round((@(
                    [double]$memoryProfile.before_execution.private_memory_mb,
                    [double]$(if ($null -ne $memoryProfile.after_execution) { $memoryProfile.after_execution.private_memory_mb } else { 0.0 }),
                    [double]$(if ($null -ne $memoryProfile.after_result_persist) { $memoryProfile.after_result_persist.private_memory_mb } else { 0.0 })
                ) | Measure-Object -Maximum).Maximum, 2)

            [pscustomobject]@{
                task_id = $TaskId
                execution_id = [string]$resolvedExecutionId
                package_path = $packagePath
                engine_invocation = $invokeResult
                add_result_response = $addResultResponse
                add_result_error = $addResultError
                review_response = $reviewResponse
                review_error = $reviewError
                decision = $reviewDecision
                execution_feedback = @($feedbackEvents)
                execution_readiness = $executionReadinessGate.trace
                execution_trace = [pscustomobject]@{
                    action = 'run-task'
                    execution_readiness = $executionReadinessGate.trace
                }
                routing_decision_preinvoke = $routingPre[0]
                routing_decision = $null
                engine_performance_record = $null
                next_task_selection = $null
                next_task_selection_error = ''
                post_completion_tail_skipped = $true
                state_access = $stateAccess
                memory_profile = [pscustomobject]$memoryProfile
            } | ConvertTo-Json -Depth 14
            break
        }
    $memoryProfile.after_result_persist = Get-ProcessMemorySnapshot
    $memoryProfile.peak_private_memory_mb = [math]::Round((@(
            [double]$memoryProfile.before_execution.private_memory_mb,
            [double]$(if ($null -ne $memoryProfile.after_execution) { $memoryProfile.after_execution.private_memory_mb } else { 0.0 }),
            [double]$(if ($null -ne $memoryProfile.after_result_persist) { $memoryProfile.after_result_persist.private_memory_mb } else { 0.0 })
        ) | Measure-Object -Maximum).Maximum, 2)

        $attemptedEngines = @($invokeResult.attempted_engines)
        $attemptRecords = @($invokeResult.attempts)
        $uniqueEngineCount = @($attemptedEngines | Select-Object -Unique).Count
        $hadRetry = ($attemptRecords.Count -gt $uniqueEngineCount)
        $fallbackUsed = [bool]$invokeResult.fallback_applied
        $terminalStatus = if ($reviewDecision -eq "pass") { "succeeded" } else { "failed" }
        $recovered = ($terminalStatus -eq "succeeded" -and ($hadRetry -or $fallbackUsed))
        $terminalFeedback = Try-PublishExecutionFeedback -Config $config -FeedbackConfig $feedbackConfig -ExecutionId $resolvedExecutionId -Status $terminalStatus -TaskId $TaskId -Details ([pscustomobject]@{
                review_decision = $reviewDecision
                task_category = $taskCategoryResolved
                attempted_engines = @($attemptedEngines)
                fallback_used = $fallbackUsed
                retry_in_progress = $false
                recovered = $recovered
                unrecovered_failure = ($terminalStatus -eq "failed")
                failure_category = if ($invokeResult.PSObject.Properties["failure_category"]) { [string]$invokeResult.failure_category } else { "none" }
                guardrail_blocked = $false
                executor_unavailable = $false
            })
        $feedbackEvents += @([pscustomobject]@{ status = $terminalStatus; publish = $terminalFeedback })

        $stateAfter = if ([bool]$stateAccess.local_cache_enabled) { Load-State } else { $state }
        $objectiveForTask = @($stateAfter.objectives | Where-Object { [string]$_.id -eq [string]$task.objective_id } | Select-Object -First 1)
        $objectiveForTask = if (@($objectiveForTask).Count -gt 0) { $objectiveForTask[0] } else { $null }
        $publishedExecutionId = if ($resultPayload.PSObject.Properties['execution_engine'] -and $resultPayload.execution_engine -and $resultPayload.execution_engine.PSObject.Properties['execution_id'] -and -not [string]::IsNullOrWhiteSpace([string]$resultPayload.execution_engine.execution_id)) {
            [string]$resultPayload.execution_engine.execution_id
        }
        elseif (-not [string]::IsNullOrWhiteSpace([string]$resolvedExecutionId)) {
            [string]$resolvedExecutionId
        }
        else {
            [string]$TaskId
        }
        $publishedArtifacts = Publish-LocalExecutionArtifacts -Task $task -Objective $objectiveForTask -ResultPayload $resultPayload -ReviewDecision $reviewDecision -ExecutionId $publishedExecutionId -PackagePath $packagePath -ExecutionReadiness $executionReadinessGate.trace
        Publish-TodActivityEvent -EventType 'result_published' -ObjectiveId ([string]$task.objective_id) -TaskId $TaskId -RequestId $taskRequestId -ExecutionId $publishedExecutionId -CorrelationId $taskCorrelationId -Title $taskTitle -Step 'result_publisher' -Status $(if ([string]::Equals($reviewDecision, 'pass', [System.StringComparison]::OrdinalIgnoreCase)) { 'completed' } else { 'blocked' }) -Message 'Published the latest TOD execution artifacts.' -Details ([ordered]@{
                review_decision = $reviewDecision
                artifact_paths = if ($publishedArtifacts.PSObject.Properties['artifact_paths']) { @($publishedArtifacts.artifact_paths) } else { @() }
                no_op_detected = [bool]$noOpAssessment.detected
                reason_code = if ($resultPayload.PSObject.Properties['reason_code']) { [string]$resultPayload.reason_code } else { '' }
            }) -Source 'tod.run-task' -Surface 'tod-run-task' -Summary ([string]$resultPayload.summary) -CurrentAction 'Published bounded execution results.' -ExecutionState $reviewDecision -RecoveryState $(if ([string]::Equals($reviewDecision, 'pass', [System.StringComparison]::OrdinalIgnoreCase)) { 'not_needed' } else { 'required' }) | Out-Null
        if ($hasExplicitEngineBlocker -or [bool]$noOpAssessment.detected -or -not [string]::Equals($reviewDecision, 'pass', [System.StringComparison]::OrdinalIgnoreCase)) {
            Publish-TodActivityEvent -EventType 'failure' -ObjectiveId ([string]$task.objective_id) -TaskId $TaskId -RequestId $taskRequestId -ExecutionId $publishedExecutionId -CorrelationId $taskCorrelationId -Title $taskTitle -Step 'result_publisher' -Status 'blocked' -Message 'The bounded execution ended with unresolved blockers or required revision.' -Details ([ordered]@{
                    review_decision = $reviewDecision
                    reason_code = if ($resultPayload.PSObject.Properties['reason_code']) { [string]$resultPayload.reason_code } else { '' }
                    no_op_detected = [bool]$noOpAssessment.detected
                    unresolved_issues = @(@($resultPayload.failures) + @($precheckWarnings))
                }) -Source 'tod.run-task' -Surface 'tod-run-task' -Summary ([string]$resultPayload.summary) -CurrentAction 'Recorded the blocking outcome.' -ExecutionState $reviewDecision -RecoveryState 'required' | Out-Null
        }
        $routingRecord = Update-RoutingDecisionRecord -State $stateAfter -RoutingDecisionId ([string]$routingPre[0].id) -FinalOutcome ([string]$reviewDecision) -InvokeResult $invokeResult
        $taskType = if ($task.PSObject.Properties["type"]) { [string]$task.type } else { "implementation" }
        $perfRecord = Add-EnginePerformanceRecord -State $stateAfter -TaskId $TaskId -InvokeResult $invokeResult -ReviewDecision $reviewDecision -TaskType $taskType -TaskCategory $taskCategoryResolved -FilesInvolved @($resultPayload.files_changed)
        Add-Journal -State $stateAfter -Actor "tod" -ActionName "run_task" -EntityType "task" -EntityId $TaskId -Payload ([pscustomobject]@{
                package_path = $packagePath
                attempted_engines = @($invokeResult.attempted_engines)
                fallback_applied = [bool]$invokeResult.fallback_applied
                result_summary = [string]$resultPayload.summary
                review_decision = $reviewDecision
                engine_performance_record_id = [string]$perfRecord.id
                task_category = $taskCategoryResolved
                routing_decision_id = [string]$routingRecord.id
                routing_decision = $routingRecord
                execution_readiness = $executionReadinessGate.trace
            })
        if ([bool]$stateAccess.local_cache_enabled) {
            Save-State -State $stateAfter
        }

        $nextTaskSelection = $null
        $nextTaskSelectionError = ''
        if (-not $SkipNextTaskSelectionLoop) {
            try {
                $selectionAction = Invoke-TodSelfJsonAction -ActionName 'select-next-task-loop' -Arguments @{
                    TaskId = $TaskId
                    ObjectiveId = [string]$task.objective_id
                    ConfigPath = $configPath
                    StatePath = $statePath
                    SelectionReason = 'terminal_task_outcome'
                }
                $nextTaskSelection = $selectionAction.payload
            }
            catch {
                $nextTaskSelectionError = [string]$_.Exception.Message
            }
        }

        [pscustomobject]@{
            task_id = $TaskId
            execution_id = [string]$resolvedExecutionId
            package_path = $packagePath
            engine_invocation = $invokeResult
            add_result_response = $addResultResponse
            review_response = $reviewResponse
            decision = $reviewDecision
            execution_feedback = @($feedbackEvents)
            execution_readiness = $executionReadinessGate.trace
            execution_trace = [pscustomobject]@{
                action = "run-task"
                execution_readiness = $executionReadinessGate.trace
            }
            routing_decision_preinvoke = $routingPre[0]
            routing_decision = $routingRecord
            engine_performance_record = $perfRecord
            next_task_selection = $nextTaskSelection
            next_task_selection_error = $nextTaskSelectionError
            state_access = $stateAccess
            memory_profile = [pscustomobject]$memoryProfile
        } | ConvertTo-Json -Depth 14
    }

    "select-next-task-loop" {
        $payload = Invoke-TodNextTaskSelectionLoop -State $state -ResolvedConfigPath $configPath -ResolvedStatePath $statePath -SourceTaskId $TaskId -TriggerReason $SelectionReason
        if ([bool]$stateAccess.local_cache_enabled) {
            $state = Load-State
            Add-Journal -State $state -Actor 'tod' -ActionName 'select_next_task_loop' -EntityType 'task' -EntityId $(if ($payload.PSObject.Properties['selected_task_id'] -and -not [string]::IsNullOrWhiteSpace([string]$payload.selected_task_id)) { [string]$payload.selected_task_id } else { 'none' }) -Payload $payload
            Save-State -State $state
        }
        $payload | ConvertTo-Json -Depth 16
    }

    "run-bridge-request" {
        if ([string]::IsNullOrWhiteSpace($RequestId)) { throw "-RequestId is required" }

        $bridgePacket = Get-BridgeRequestPacket
        $bridgeRequest = $bridgePacket.payload
        $bridgeTaskId = if ($bridgeRequest.PSObject.Properties['task_id'] -and -not [string]::IsNullOrWhiteSpace([string]$bridgeRequest.task_id)) { [string]$bridgeRequest.task_id } else { [string]$RequestId }
        $bridgeObjectiveId = if ($bridgeRequest.PSObject.Properties['objective_id']) { [string]$bridgeRequest.objective_id } else { '' }
        $bridgeTitle = if ($bridgeRequest.PSObject.Properties['title']) { [string]$bridgeRequest.title } else { 'MIM task request ' + [string]$RequestId }
        $bridgeSummary = if ($bridgeRequest.PSObject.Properties['summary']) { [string]$bridgeRequest.summary } elseif ($bridgeRequest.PSObject.Properties['scope']) { [string]$bridgeRequest.scope } else { $bridgeTitle }
        $bridgeIntakeItem = New-TodIntakeItem -RequestId ([string]$RequestId) -TaskId $bridgeTaskId -ObjectiveId $bridgeObjectiveId -Source 'mim_request' -Priority (Resolve-TodIntakePriority -Source 'mim_request' -TaskCategory '' -Text $bridgeSummary) -InterruptPolicy 'no_interrupt' -RelationToActiveTask 'new' -Title $bridgeTitle -Summary $bridgeSummary -TaskCategory 'mim_request'
        $bridgeArbitration = Register-TodIntakeItem -Item $bridgeIntakeItem
        if ([string]$bridgeArbitration.decision -in @('queue', 'defer', 'reject_duplicate', 'merge_with_active', 'blocked_needs_operator')) {
            [pscustomobject]@{
                request_id = [string]$RequestId
                task_id = $bridgeTaskId
                objective_id = $bridgeObjectiveId
                tod_action = 'run-bridge-request'
                execution_lane = 'intake_arbitration'
                accepted = -not [string]::Equals([string]$bridgeArbitration.decision, 'reject_duplicate', [System.StringComparison]::OrdinalIgnoreCase)
                execution_status = [string]$bridgeArbitration.decision
                decision = [string]$bridgeArbitration.decision
                reason = [string]$bridgeArbitration.reason
                intake_arbitration = $bridgeArbitration.arbitration
                intake_queue = $bridgeArbitration.queue
                active_task_preserved = $true
            } | ConvertTo-Json -Depth 16
            break
        }

        $bridgeExecution = Invoke-BridgeRequestExecution -RequestId $RequestId -ResolvedConfigPath $configPath -ResolvedStatePath $statePath
        $bridgeExecution | Add-Member -NotePropertyName intake_arbitration -NotePropertyValue $bridgeArbitration.arbitration -Force
        $bridgeExecution | Add-Member -NotePropertyName intake_queue -NotePropertyValue $bridgeArbitration.queue -Force
        $bridgeExecution | ConvertTo-Json -Depth 14
    }

    "run-task-report" {
        if ([string]::IsNullOrWhiteSpace($TaskId)) { throw "-TaskId is required" }
        $report = Build-RunTaskReport -State $state -TaskId $TaskId
        $report | ConvertTo-Json -Depth 12
    }

    "show-engine-performance" {
        $summary = Get-EnginePerformanceSummary -State $state -EngineFilter $Engine -TaskCategoryFilter $Category
        $summary | ConvertTo-Json -Depth 16
    }

    "show-routing-decisions" {
        $routingSummary = Get-RoutingDecisionSummary -State $state -TaskFilter $TaskId -Take $Top
        $routingSummary | ConvertTo-Json -Depth 16
    }

    "show-routing-feedback" {
        $feedback = Build-RoutingFeedbackReport -State $state -Config $config -HealthWindow $Top
        $feedback | ConvertTo-Json -Depth 16
    }

    "show-failure-taxonomy" {
        if ([string]$stateAccess.mode -eq "lightweight_guard") {
            $payload = Invoke-LightweightStateBusPayload
            $result = if ($payload.PSObject.Properties["failure_taxonomy"]) { $payload.failure_taxonomy } else { $payload }
            $result | Add-Member -NotePropertyName state_access -NotePropertyValue $stateAccess -Force
            $result | ConvertTo-Json -Depth 16
            break
        }

        $report = Build-FailureTaxonomyReport -State $state -Window $Top -CategoryFilter $Category -EngineFilter $Engine
        $report | ConvertTo-Json -Depth 16
    }

    "show-reliability-dashboard" {
        if ([string]$stateAccess.mode -eq "lightweight_guard") {
            $payload = Invoke-LightweightStateBusPayload
            $result = if ($payload.PSObject.Properties["reliability_dashboard"]) { $payload.reliability_dashboard } else { $payload }
            $result | Add-Member -NotePropertyName state_access -NotePropertyValue $stateAccess -Force
            $result | ConvertTo-Json -Depth 18
            break
        }

        $dashboard = Build-ReliabilityDashboard -State $state -Config $config -Window $Top -CategoryFilter $Category -EngineFilter $Engine
        $dashboard | ConvertTo-Json -Depth 18
    }

    "get-reliability" {
        if ([string]$stateAccess.mode -eq "lightweight_guard") {
            $payload = Invoke-LightweightStateBusPayload
            $result = if ($payload.PSObject.Properties["reliability"]) { $payload.reliability } else { $payload }
            $result | Add-Member -NotePropertyName state_access -NotePropertyValue $stateAccess -Force
            $result | ConvertTo-Json -Depth 18
            break
        }

        $dashboard = Build-ReliabilityDashboard -State $state -Config $config -Window $Top -CategoryFilter $Category -EngineFilter $Engine
        $retryTrend = if ($dashboard.PSObject.Properties["retry_trend"] -and $null -ne $dashboard.retry_trend) { @($dashboard.retry_trend) } else { @() }
        $driftWarnings = if ($dashboard.PSObject.Properties["drift_warnings"] -and $null -ne $dashboard.drift_warnings) { @($dashboard.drift_warnings) } else { @() }

        $overallAlert = "stable"
        $maxRank = 0
        foreach ($item in @($retryTrend)) {
            $alert = if ($item.PSObject.Properties["alert_state"] -and -not [string]::IsNullOrWhiteSpace([string]$item.alert_state)) { [string]$item.alert_state } else { "stable" }
            $rank = Get-AlertSeverityRank -State $alert
            if ($rank -gt $maxRank) {
                $maxRank = $rank
                $overallAlert = $alert
            }
        }

        $driftPenaltyActive = @($retryTrend | Where-Object {
                (($_.PSObject.Properties["confidence_penalty"] -and $null -ne $_.confidence_penalty -and [double]$_.confidence_penalty -gt 0.0) -or
                 ($_.PSObject.Properties["score_penalty"] -and $null -ne $_.score_penalty -and [double]$_.score_penalty -gt 0.0))
            })
        $recoveryState = @($retryTrend | ForEach-Object {
                [pscustomobject]@{
                    engine = [string]$_.engine
                    alert_state = if ($_.PSObject.Properties["alert_state"]) { [string]$_.alert_state } else { "stable" }
                    recovery_progress = if ($_.PSObject.Properties["recovery_progress"] -and $null -ne $_.recovery_progress) { [double]$_.recovery_progress } else { 0.0 }
                    consecutive_stable_runs = if ($_.PSObject.Properties["consecutive_stable_runs"] -and $null -ne $_.consecutive_stable_runs) { [int]$_.consecutive_stable_runs } else { 0 }
                    confidence_penalty = if ($_.PSObject.Properties["confidence_penalty"] -and $null -ne $_.confidence_penalty) { [double]$_.confidence_penalty } else { 0.0 }
                    score_penalty = if ($_.PSObject.Properties["score_penalty"] -and $null -ne $_.score_penalty) { [double]$_.score_penalty } else { 0.0 }
                }
            })

        $explainability = Get-ReliabilityAlertExplainability -State $state -Dashboard $dashboard -RetryTrend $retryTrend -DriftWarnings $driftWarnings -DriftPenaltyActive $driftPenaltyActive -CurrentAlertState $overallAlert

        [pscustomobject]@{
            path = "/tod/reliability"
            generated_at = Get-UtcNow
            current_alert_state = $overallAlert
            reliability_alert_state_raw = $overallAlert
            reliability_alert_reasons = @($explainability.reasons)
            reliability_alert_inputs = $explainability.inputs
            drift_penalties_active = (@($driftPenaltyActive).Count -gt 0)
            drift_penalty_engines = @($driftPenaltyActive | ForEach-Object { [string]$_.engine })
            recovery_state = @($recoveryState)
            engine_reliability_score = if ($dashboard.PSObject.Properties["engine_reliability"]) { $dashboard.engine_reliability.by_engine } else { @() }
            retry_trend = @($retryTrend)
            guardrail_trend = if ($dashboard.PSObject.Properties["guardrail_trend"]) { $dashboard.guardrail_trend } else { $null }
            drift_warnings = @($driftWarnings)
        } | ConvertTo-Json -Depth 18
    }

    "get-execution-readiness" {
        $payload = Get-TodExecutionReadinessPayload -Config $config
        $payload | ConvertTo-Json -Depth 20
    }

    "get-capabilities" {
        $caps = Get-TodCapabilitiesPayload -Config $config
        $caps | ConvertTo-Json -Depth 18
    }

    "get-research" {
        $payload = Get-TodResearchPayload -State $state -Top $Top
        $payload | ConvertTo-Json -Depth 18
    }

    "get-resourcing" {
        $payload = Get-TodResourcingPayload -State $state -ObjectiveId $ObjectiveId -TaskId $TaskId -Top $Top
        $payload | ConvertTo-Json -Depth 18
    }

    "start-training-runbook" {
        $payload = Start-TodTrainingRunbookProcess -ResolvedConfigPath $configPath
        $payload | Add-Member -NotePropertyName execution_readiness -NotePropertyValue $executionReadinessGate.signal.readiness -Force
        $payload | Add-Member -NotePropertyName execution_trace -NotePropertyValue ([pscustomobject]@{
            action = 'start-training-runbook'
            execution_readiness = $executionReadinessGate.trace
            }) -Force
        $payload | ConvertTo-Json -Depth 12
    }

    "engineer-run" {
        $payload = Get-TodEngineerRunPayload -State $state -Config $config -ObjectiveId $ObjectiveId -TaskId $TaskId -Body $Content -Append:$Append -ApplyPlan:$ApplyPlan -DangerousApproved:$DangerousApproved -Top $Top
        $payload | Add-Member -NotePropertyName execution_readiness -NotePropertyValue $executionReadinessGate.signal.readiness -Force
        $payload | Add-Member -NotePropertyName execution_readiness_degraded -NotePropertyValue ([bool]$executionReadinessGate.degraded) -Force
        $payload | Add-Member -NotePropertyName apply_plan_effective -NotePropertyValue ([bool]$ApplyPlan) -Force
        $payload | Add-Member -NotePropertyName execution_trace -NotePropertyValue ([pscustomobject]@{
            action = "engineer-run"
            execution_readiness = $executionReadinessGate.trace
            }) -Force
        $runHistoryLimit = Resolve-EngineeringLoopHistoryLimit -Config $config -Kind "run_history"
        $null = Add-EngineeringRunHistoryRecord -State $state -Payload $payload -MaxEntries $runHistoryLimit
        Add-Journal -State $state -Actor "tod" -ActionName "engineer_run" -EntityType "task" -EntityId $(if (-not [string]::IsNullOrWhiteSpace([string]$payload.focus.task_id)) { [string]$payload.focus.task_id } else { "none" }) -Payload $payload
        Save-State -State $state
        $payload | ConvertTo-Json -Depth 18
    }

    "engineer-scorecard" {
        $payload = Get-TodEngineerScorecardPayload -State $state -Config $config -Top $Top
        $scorecardHistoryLimit = Resolve-EngineeringLoopHistoryLimit -Config $config -Kind "scorecard_history"
        $null = Add-EngineeringScorecardHistoryRecord -State $state -Payload $payload -MaxEntries $scorecardHistoryLimit
        Save-State -State $state
        $payload | ConvertTo-Json -Depth 18
    }

    "get-engineering-loop-summary" {
        if ([string]$stateAccess.mode -eq "lightweight_guard") {
            $payload = Invoke-LightweightStateBusPayload
            $result = if ($payload.PSObject.Properties["engineering_summary"]) { $payload.engineering_summary } else { $payload }
            $result | Add-Member -NotePropertyName state_access -NotePropertyValue $stateAccess -Force
            $result | ConvertTo-Json -Depth 18
            break
        }

        $payload = Get-TodEngineeringLoopSummaryPayload -State $state -Config $config -Top $Top
        $payload | ConvertTo-Json -Depth 18
    }

    "get-engineering-signal" {
        if ([string]$stateAccess.mode -eq "lightweight_guard") {
            $payload = Invoke-LightweightStateBusPayload
            $result = if ($payload.PSObject.Properties["engineering_signal"]) { $payload.engineering_signal } else { $payload }
            $result | Add-Member -NotePropertyName state_access -NotePropertyValue $stateAccess -Force
            $result | ConvertTo-Json -Depth 18
            break
        }

        $payload = Get-TodEngineeringSignalPayload -State $state -Config $config -Top $Top
        $payload | ConvertTo-Json -Depth 18
    }

    "get-engineering-loop-history" {
        $payload = Get-TodEngineeringLoopHistoryPayload -State $state -Config $config -HistoryKind $HistoryKind -Page $Page -PageSize $PageSize
        $payload | ConvertTo-Json -Depth 24
    }

    "engineer-cycle" {
        $payload = Get-TodEngineerCyclePayload -State $state -Config $config -Cycles $Cycles -Top $Top -DangerousApproved:$DangerousApproved
        Save-State -State $state
        $payload | ConvertTo-Json -Depth 24
    }

    "review-engineering-cycle" {
        if ([string]::IsNullOrWhiteSpace($CycleId)) { throw "-CycleId is required" }
        if ([string]::IsNullOrWhiteSpace($CycleReviewAction)) { throw "-CycleReviewAction is required" }

        $payload = Invoke-TodEngineeringCycleReview -State $state -Config $config -CycleId $CycleId -CycleReviewAction $CycleReviewAction -Rationale $Rationale -Top $Top -DangerousApproved:$DangerousApproved
        Save-State -State $state
        $payload | ConvertTo-Json -Depth 24
    }

    "sandbox-list" {
        $payload = Get-TodSandboxListPayload -Top $Top
        $payload | ConvertTo-Json -Depth 18
    }

    "sandbox-plan" {
        if ([string]::IsNullOrWhiteSpace($SandboxPath)) { throw "-SandboxPath is required" }
        if ($null -eq $Content) { throw "-Content is required" }

        $payload = Invoke-TodSandboxPlanWrite -RelativePath $SandboxPath -Body ([string]$Content) -Append:$Append
        Add-Journal -State $state -Actor "tod" -ActionName "sandbox_plan" -EntityType "sandbox_file" -EntityId ([string]$payload.sandbox_path) -Payload $payload
        Save-State -State $state
        $payload | ConvertTo-Json -Depth 18
    }

    "sandbox-apply-plan" {
        if ([string]::IsNullOrWhiteSpace($SandboxPlanPath)) { throw "-SandboxPlanPath is required" }
        Assert-DangerousActionApproved -Config $config -ActionName "sandbox-apply-plan" -DangerousApproved:$DangerousApproved

        $payload = Invoke-TodSandboxApplyPlan -PlanPath $SandboxPlanPath
        Add-Journal -State $state -Actor "tod" -ActionName "sandbox_apply_plan" -EntityType "sandbox_file" -EntityId ([string]$payload.sandbox_path) -Payload $payload
        Save-State -State $state
        $payload | ConvertTo-Json -Depth 18
    }

    "sandbox-write" {
        if ([string]::IsNullOrWhiteSpace($SandboxPath)) { throw "-SandboxPath is required" }
        if ($null -eq $Content) { throw "-Content is required" }
        Assert-DangerousActionApproved -Config $config -ActionName "sandbox-write" -DangerousApproved:$DangerousApproved

        $payload = Invoke-TodSandboxWrite -RelativePath $SandboxPath -Body ([string]$Content) -Append:$Append
        Add-Journal -State $state -Actor "tod" -ActionName "sandbox_write" -EntityType "sandbox_file" -EntityId ([string]$payload.sandbox_path) -Payload $payload
        Save-State -State $state
        $payload | ConvertTo-Json -Depth 18
    }

    "repair-state" {
        $repairReport = Repair-StateFileOversizedStrings -Path $statePath
        if ($repairReport.PSObject.Properties['swap_pending'] -and [bool]$repairReport.swap_pending) {
            $currentBytes = (Get-Item -Path $statePath).Length

            [pscustomobject]@{
                changed = [bool]$repairReport.changed
                state_path = [string]$repairReport.state_path
                backup_path = if ($repairReport.PSObject.Properties['backup_path']) { $repairReport.backup_path } else { $null }
                pending_repaired_path = if ($repairReport.PSObject.Properties['pending_repaired_path']) { $repairReport.pending_repaired_path } else { $null }
                swap_pending = if ($repairReport.PSObject.Properties['swap_pending']) { [bool]$repairReport.swap_pending } else { $false }
                repaired_lines = if ($repairReport.PSObject.Properties['repaired_lines']) { @($repairReport.repaired_lines) } else { @() }
                repaired = $repairReport
                compaction = $null
                final_state_bytes = [int64]$currentBytes
                state_access = $stateAccess
            } | ConvertTo-Json -Depth 12
            break
        }

        $repairedState = Load-State
        $compaction = Compress-StateForOperationalUse -State $repairedState -Config $config
        Save-State -State $repairedState
        $finalBytes = (Get-Item -Path $statePath).Length

        [pscustomobject]@{
            changed = [bool]$repairReport.changed
            state_path = [string]$repairReport.state_path
            backup_path = if ($repairReport.PSObject.Properties['backup_path']) { $repairReport.backup_path } else { $null }
            pending_repaired_path = if ($repairReport.PSObject.Properties['pending_repaired_path']) { $repairReport.pending_repaired_path } else { $null }
            swap_pending = if ($repairReport.PSObject.Properties['swap_pending']) { [bool]$repairReport.swap_pending } else { $false }
            repaired_lines = if ($repairReport.PSObject.Properties['repaired_lines']) { @($repairReport.repaired_lines) } else { @() }
            repaired = $repairReport
            compaction = $compaction
            final_state_bytes = [int64]$finalBytes
        } | ConvertTo-Json -Depth 12
    }

    "rewrite-state-history" {
        if (-not (Test-Path -Path $rewriteStateHistoryScript)) {
            throw "Rewrite state history script not found at $rewriteStateHistoryScript"
        }

        $payload = & $rewriteStateHistoryScript -StatePath $statePath
        $payload | ConvertTo-Json -Depth 12
    }

    "get-intake-arbitration" {
        $drainResult = Drain-TodIntakeQueueAfterTerminalActiveLane
        $queue = Read-TodIntakeArtifact -FileName $todIntakeQueueFileName
        $activeLane = Read-TodIntakeArtifact -FileName $todActiveExecutionLaneFileName
        $arbitration = Read-TodIntakeArtifact -FileName $todIntakeArbitrationFileName
        [pscustomobject]@{
            ok = $true
            generated_at = Get-UtcNow
            intake_sources = @('operator_chat', 'mim_request', 'watchdog', 'recovery', 'maintenance', 'listener_retry')
            drain = $drainResult
            active_task = $activeLane
            queued_tasks = if ($queue -and $queue.PSObject.Properties['items']) { @($queue.items | Where-Object { [string]$_.status -eq 'queued' }) } else { @() }
            queue = $queue
            arbitration = $arbitration
            next_task_after_current = if ($queue -and $queue.PSObject.Properties['next_task_after_current']) { $queue.next_task_after_current } else { $null }
            artifact_paths = [pscustomobject]@{
                intake_queue = Get-TodIntakeArtifactPath -FileName $todIntakeQueueFileName
                active_execution_lane = Get-TodIntakeArtifactPath -FileName $todActiveExecutionLaneFileName
                intake_arbitration = Get-TodIntakeArtifactPath -FileName $todIntakeArbitrationFileName
            }
        } | ConvertTo-Json -Depth 18
    }

    "get-state-bus" {
        if ([string]$stateAccess.mode -eq "lightweight_guard") {
            $payload = Invoke-LightweightStateBusPayload
            $payload | Add-Member -NotePropertyName state_access -NotePropertyValue $stateAccess -Force
            $payload | ConvertTo-Json -Depth 24
            break
        }

        $stateBus = Get-TodStateBusPayload -Config $config -State $state -Top $Top
        $stateBus | ConvertTo-Json -Depth 24
    }

    "get-version" {
        $versionPayload = Get-TodVersionPayload -Config $config -State $state
        $versionPayload | ConvertTo-Json -Depth 18
    }

    "add-result" {
        if ([string]::IsNullOrWhiteSpace($TaskId)) { throw "-TaskId is required" }
        if ([string]::IsNullOrWhiteSpace($Summary)) { throw "-Summary is required" }

        $task = $null
        if ((Use-Local -Config $config) -and [bool]$stateAccess.local_cache_enabled) {
            $task = $state.tasks | Where-Object { $_.id -eq $TaskId } | Select-Object -First 1
            if (-not $task) { throw "Task not found: $TaskId" }
        }

        $resultId = New-Id -Prefix "RES" -Count $state.execution_results.Count
        $result = [pscustomobject]@{
            id = $resultId
            task_id = $TaskId
            summary = $Summary
            files_changed = [string[]](Split-List -Value $FilesChanged)
            tests_run = [string[]](Split-List -Value $TestsRun)
            test_results = [string[]](Split-List -Value $TestResults)
            failures = [string[]](Split-List -Value $Failures)
            recommendations = [string[]](Split-List -Value $Recommendations)
            engine_metadata = Get-ActiveEngineMetadata -EngineConfig $engineConfig
            created_at = Get-UtcNow
        }

        $remoteCreated = $null
        $remoteTaskId = $null
        if (Use-Remote -Config $config) {
            $remoteTaskId = Resolve-RemoteTaskId -TaskId $TaskId -State $state
            if ($null -eq $remoteTaskId -and [string]$stateAccess.mode -eq "remote_ephemeral") {
                $remoteTask = Resolve-RemoteExecutionTask -TaskId $TaskId -ObjectiveId $ObjectiveId -Config $config
                if ($remoteTask) {
                    $remoteTaskId = Resolve-RemoteTaskId -TaskId ([string]$remoteTask.id) -State ([pscustomobject]@{ tasks = @($remoteTask) })
                    if ($null -eq $task) {
                        $task = $remoteTask
                    }
                }
            }
            if ($null -ne $remoteTaskId) {
                $remoteCreated = Invoke-MimSafely -Config $config -Operation "POST /results" -ApiCall {
                    New-MimResult -BaseUrl $config.mim_base_url -TimeoutSeconds ([int]$config.timeout_seconds) -Result $result -RemoteTaskId $remoteTaskId
                }
            }
            elseif (([string]$config.mode).ToLowerInvariant() -eq "remote") {
                throw "Cannot submit result to MIM without a remote integer task ID for task '$TaskId'."
            }
            elseif ([string]$stateAccess.mode -eq "remote_ephemeral") {
                $bridgeHint = Get-ListenerRequestBridgeHint -TaskId $TaskId
                throw ("Cannot safely fall back to local state for add-result because state.json is oversized and no remote task ID could be resolved for '$TaskId'. " + (Get-RemoteTaskResolutionFailureMessage -TaskId $TaskId -BridgeHint $bridgeHint))
            }
            else {
                Write-Warning "Skipping remote result submission because no remote task ID is available for task '$TaskId'."
            }
        }

        if ($remoteCreated -and $remoteCreated.PSObject.Properties["result_id"]) {
            $result.id = [string]$remoteCreated.result_id
            $result.task_id = [string]$remoteTaskId
            if ($remoteCreated.PSObject.Properties["created_at"] -and -not [string]::IsNullOrWhiteSpace([string]$remoteCreated.created_at)) {
                $result.created_at = [string]$remoteCreated.created_at
            }
            if ((-not $remoteCreated.PSObject.Properties["engine_metadata"]) -or $null -eq $remoteCreated.engine_metadata) {
                $remoteCreated | Add-Member -NotePropertyName engine_metadata -NotePropertyValue $result.engine_metadata -Force
            }
        }

        if ([bool]$stateAccess.local_cache_enabled -and ((Use-Local -Config $config) -or ((([string]$config.mode).ToLowerInvariant() -eq "hybrid") -and $null -eq $remoteCreated -and [bool]$config.fallback_to_local))) {
            $state.execution_results += $result
            if ($task) {
                if ($remoteCreated -and $remoteCreated.PSObject.Properties["task_id"]) {
                    $task.id = [string]$remoteCreated.task_id
                }
                $task.status = if ($remoteCreated -and $remoteCreated.PSObject.Properties["status"]) { [string]$remoteCreated.status } else { "implemented" }
                $task.updated_at = Get-UtcNow
            }
            $journalAction = if ($remoteCreated) { "add_result_remote_cached" } else { "add_result" }
            Add-Journal -State $state -Actor "codex" -ActionName $journalAction -EntityType "execution_result" -EntityId ([string]$result.id) -Payload ([pscustomobject]@{
                    result = $result
                    engine_metadata = $result.engine_metadata
                })
            Save-State -State $state
        }

        if ((Use-Local -Config $config) -and [bool]$stateAccess.local_cache_enabled) {
            if ($remoteCreated) {
                [pscustomobject]@{
                    mode = $config.mode
                    local = $result
                    remote = $remoteCreated
                    engine_metadata = $result.engine_metadata
                    state_access = $stateAccess
                } | ConvertTo-Json -Depth 12
            }
            else {
                $result | ConvertTo-Json -Depth 8
            }
        }
        else {
            if ($remoteCreated -and ((-not $remoteCreated.PSObject.Properties["engine_metadata"]) -or $null -eq $remoteCreated.engine_metadata)) {
                $remoteCreated | Add-Member -NotePropertyName engine_metadata -NotePropertyValue $result.engine_metadata -Force
            }
            if ($remoteCreated) {
                $remoteCreated | Add-Member -NotePropertyName state_access -NotePropertyValue $stateAccess -Force
            }
            $remoteCreated | ConvertTo-Json -Depth 12
        }
    }

    "review-task" {
        if ([string]::IsNullOrWhiteSpace($TaskId)) { throw "-TaskId is required" }
        if ([string]::IsNullOrWhiteSpace($Decision)) { throw "-Decision is required" }
        if ([string]::IsNullOrWhiteSpace($Rationale)) { throw "-Rationale is required" }

        $task = $null
        if ((Use-Local -Config $config) -and [bool]$stateAccess.local_cache_enabled) {
            $task = $state.tasks | Where-Object { $_.id -eq $TaskId } | Select-Object -First 1
            if (-not $task) { throw "Task not found: $TaskId" }
        }

        $reviewId = New-Id -Prefix "REV" -Count $state.review_decisions.Count
        $review = [pscustomobject]@{
            id = $reviewId
            task_id = $TaskId
            decision = $Decision
            rationale = $Rationale
            unresolved_issues = [string[]](Split-List -Value $UnresolvedIssues)
            scope_drift_detected = [bool]$ScopeDrift
            created_at = Get-UtcNow
        }

        $remoteCreated = $null
        $remoteTaskId = $null
        if (Use-Remote -Config $config) {
            $remoteTaskId = Resolve-RemoteTaskId -TaskId $TaskId -State $state
            if ($null -eq $remoteTaskId -and [string]$stateAccess.mode -eq "remote_ephemeral") {
                $remoteTask = Resolve-RemoteExecutionTask -TaskId $TaskId -ObjectiveId $ObjectiveId -Config $config
                if ($remoteTask) {
                    $remoteTaskId = Resolve-RemoteTaskId -TaskId ([string]$remoteTask.id) -State ([pscustomobject]@{ tasks = @($remoteTask) })
                    if ($null -eq $task) {
                        $task = $remoteTask
                    }
                }
            }
            if ($null -ne $remoteTaskId) {
                $remoteCreated = Invoke-MimSafely -Config $config -Operation "POST /reviews" -ApiCall {
                    New-MimReview -BaseUrl $config.mim_base_url -TimeoutSeconds ([int]$config.timeout_seconds) -Review $review -RemoteTaskId $remoteTaskId
                }
            }
            elseif (([string]$config.mode).ToLowerInvariant() -eq "remote") {
                throw "Cannot submit review to MIM without a remote integer task ID for task '$TaskId'."
            }
            elseif ([string]$stateAccess.mode -eq "remote_ephemeral") {
                $bridgeHint = Get-ListenerRequestBridgeHint -TaskId $TaskId
                throw ("Cannot safely fall back to local state for review-task because state.json is oversized and no remote task ID could be resolved for '$TaskId'. " + (Get-RemoteTaskResolutionFailureMessage -TaskId $TaskId -BridgeHint $bridgeHint))
            }
            else {
                Write-Warning "Skipping remote review submission because no remote task ID is available for task '$TaskId'."
            }
        }

        if ($remoteCreated -and $remoteCreated.PSObject.Properties["review_id"]) {
            $review.id = [string]$remoteCreated.review_id
            $review.task_id = [string]$remoteTaskId
            if ($remoteCreated.PSObject.Properties["created_at"] -and -not [string]::IsNullOrWhiteSpace([string]$remoteCreated.created_at)) {
                $review.created_at = [string]$remoteCreated.created_at
            }
        }

        if ([bool]$stateAccess.local_cache_enabled -and ((Use-Local -Config $config) -or ((([string]$config.mode).ToLowerInvariant() -eq "hybrid") -and $null -eq $remoteCreated -and [bool]$config.fallback_to_local))) {
            if ($task) {
                $task.status = if ($remoteCreated -and $remoteCreated.PSObject.Properties["decision"]) { [string]$remoteCreated.decision } else {
                    switch ($Decision) {
                        "pass" { "reviewed_pass" }
                        "revise" { "needs_revision" }
                        "escalate" { "escalated" }
                    }
                }
                $task.updated_at = Get-UtcNow
            }

            $state.review_decisions += $review
            $journalAction = if ($remoteCreated) { "review_task_remote_cached" } else { "review_task" }
            Add-Journal -State $state -Actor "tod" -ActionName $journalAction -EntityType "review_decision" -EntityId ([string]$review.id) -Payload $review
            Save-State -State $state
        }

        if ((Use-Local -Config $config) -and [bool]$stateAccess.local_cache_enabled) {
            if ($remoteCreated) {
                [pscustomobject]@{
                    mode = $config.mode
                    local = $review
                    remote = $remoteCreated
                    state_access = $stateAccess
                } | ConvertTo-Json -Depth 12
            }
            else {
                $review | ConvertTo-Json -Depth 8
            }
        }
        else {
            if ($remoteCreated) {
                $remoteCreated | Add-Member -NotePropertyName state_access -NotePropertyValue $stateAccess -Force
            }
            $remoteCreated | ConvertTo-Json -Depth 12
        }
    }

    "show-journal" {
        if (Use-Remote -Config $config) {
            $remoteJournal = Invoke-MimSafely -Config $config -Operation "GET /journal" -ApiCall {
                Get-MimJournal -BaseUrl $config.mim_base_url -Top $Top -TimeoutSeconds ([int]$config.timeout_seconds)
            }

            if ($null -ne $remoteJournal) {
                $remoteJournal | ConvertTo-Json -Depth 12
                break
            }
        }

        $state.journal |
            Sort-Object -Property created_at -Descending |
            Select-Object -First $Top id, created_at, actor, action, entity_type, entity_id |
            Format-Table -AutoSize
    }

    default {
        throw "Unsupported action: $Action"
    }
}
