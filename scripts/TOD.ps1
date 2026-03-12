param(
    [Parameter(Mandatory = $true)]
    [ValidateSet(
        "init",
        "ping-mim",
        "compare-manifest",
        "sync-mim",
        "new-objective",
        "list-objectives",
        "add-task",
        "list-tasks",
        "package-task",
        "invoke-engine",
        "run-task",
        "run-task-report",
        "show-engine-performance",
        "show-routing-decisions",
        "show-routing-feedback",
        "show-failure-taxonomy",
        "show-reliability-dashboard",
        "get-reliability",
        "get-capabilities",
        "get-research",
        "get-resourcing",
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
        "get-state-bus",
        "get-version",
        "add-result",
        "review-task",
        "show-journal"
    )]
    [string]$Action,

    [string]$ObjectiveId,
    [string]$TaskId,
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
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$statePath = Join-Path $repoRoot "tod/data/state.json"
$configPath = if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    Join-Path $repoRoot "tod/config/tod-config.json"
}
else {
    $ConfigPath
}
$templatePath = Join-Path $repoRoot "tod/templates/codex-task-prompt.md"
$promptOutDir = Join-Path $repoRoot "tod/out/prompts"
$mimClientPath = Join-Path $repoRoot "client/mim_api_client.ps1"
$syncPolicyPath = Join-Path $repoRoot "tod/config/sync-policy.json"
$todEngineerPath = Join-Path $PSScriptRoot "TOD-Engineer.ps1"
$repoIndexPath = Join-Path $repoRoot "tod/data/repo-index.json"
$stateRepoIndexPath = Join-Path $repoRoot "tod/state/repo_index.json"
$engineeringMemoryPath = Join-Path $repoRoot "tod/data/engineering-memory.json"
$stateEngineeringMemoryPath = Join-Path $repoRoot "tod/state/engineering_memory.json"
$projectAccessPolicyScript = Join-Path $PSScriptRoot "Test-TODProjectAccessPolicy.ps1"
$projectPriorityPath = Join-Path $repoRoot "tod/config/project-priority.json"

if (Test-Path -Path $mimClientPath) {
    . $mimClientPath
}

function Get-UtcNow {
    return (Get-Date).ToUniversalTime().ToString("o")
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

function Load-State {
    Assert-Exists -Path $statePath -Name "State file"

    $maxAttempts = 6
    $baseDelayMs = 90
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        try {
            $raw = Get-Content -Path $statePath -Raw -ErrorAction Stop
            $state = $raw | ConvertFrom-Json
            Normalize-State -State $state
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
    param([Parameter(Mandatory = $true)]$State)
    Normalize-State -State $State
    $json = $State | ConvertTo-Json -Depth 12

    $maxAttempts = 6
    $baseDelayMs = 120
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
        if (-not $task.PSObject.Properties["task_category"] -or [string]::IsNullOrWhiteSpace([string]$task.task_category)) {
            $task | Add-Member -NotePropertyName task_category -NotePropertyValue "code_change" -Force
        }
    }

    foreach ($result in @($State.execution_results)) {
        $result.files_changed = Convert-ToStringArray -Value $result.files_changed
        $result.tests_run = Convert-ToStringArray -Value $result.tests_run
        $result.test_results = Convert-ToStringArray -Value $result.test_results
        $result.failures = Convert-ToStringArray -Value $result.failures
        $result.recommendations = Convert-ToStringArray -Value $result.recommendations
    }

    foreach ($review in @($State.review_decisions)) {
        $review.unresolved_issues = Convert-ToStringArray -Value $review.unresolved_issues
    }
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
    $history += $CycleRecord
    if (@($history).Count -gt $MaxEntries) {
        $history = @($history | Select-Object -Last $MaxEntries)
    }

    $State.engineering_loop.cycle_records = @($history)
    $State.engineering_loop.last_cycle = $CycleRecord
    $pending = @($history | Where-Object {
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
        [Parameter(Mandatory = $true)]$Items,
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

    $loop = if ($State.PSObject.Properties["engineering_loop"] -and $State.engineering_loop) { $State.engineering_loop } else { $null }
    $records = if ($loop -and $loop.PSObject.Properties["cycle_records"] -and $null -ne $loop.cycle_records) { @($loop.cycle_records) } else { @() }

    $pending = @($records | Where-Object {
            ($_.PSObject.Properties["approval_pending"] -and [bool]$_.approval_pending) -or
            ($_.PSObject.Properties["approval_status"] -and ([string]$_.approval_status).ToLowerInvariant() -eq "pending_apply")
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

    $loop = if ($State.PSObject.Properties["engineering_loop"]) { $State.engineering_loop } else { $null }
    $records = @()
    if ($HistoryKind -eq "scorecard_history") {
        $records = if ($loop -and $loop.PSObject.Properties["scorecard_history"]) { @($loop.scorecard_history | Sort-Object generated_at -Descending) } else { @() }
    }
    elseif ($HistoryKind -eq "cycle_records") {
        $records = if ($loop -and $loop.PSObject.Properties["cycle_records"]) { @($loop.cycle_records | Sort-Object created_at -Descending) } else { @() }
    }
    elseif ($HistoryKind -eq "review_actions") {
        $records = if ($loop -and $loop.PSObject.Properties["review_actions"]) { @($loop.review_actions | Sort-Object created_at -Descending) } else { @() }
    }
    else {
        $records = if ($loop -and $loop.PSObject.Properties["run_history"]) { @($loop.run_history | Sort-Object generated_at -Descending) } else { @() }
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
    $pendingApprovalCount = if ($State.PSObject.Properties["engineering_loop"] -and $State.engineering_loop.PSObject.Properties["cycle_records"]) {
        [int]@($State.engineering_loop.cycle_records | Where-Object {
                $_.PSObject.Properties["approval_status"] -and ([string]$_.approval_status).ToLowerInvariant() -eq "pending_apply"
            }).Count
    }
    else {
        0
    }
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
        $trend = if ($State.engineering_loop.PSObject.Properties["scorecard_history"] -and @($State.engineering_loop.scorecard_history).Count -ge 2) {
            $history = @($State.engineering_loop.scorecard_history | Sort-Object generated_at -Descending | Select-Object -First 2)
            $delta = [double]$history[0].score - [double]$history[1].score
            if ($delta -gt 0.03) { "improving" } elseif ($delta -lt -0.03) { "declining" } else { "flat" }
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

    $records = if ($State.PSObject.Properties["engineering_loop"] -and $State.engineering_loop.PSObject.Properties["cycle_records"]) { @($State.engineering_loop.cycle_records) } else { @() }
    $target = @($records | Where-Object { $_.PSObject.Properties["cycle_id"] -and [string]$_.cycle_id -eq [string]$CycleId } | Select-Object -First 1)
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
            $_.PSObject.Properties["approval_status"] -and
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

    $records = @($State.engine_performance.records)
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
                if ($null -ne $_.PSObject.Properties['task_category'] -and -not [string]::IsNullOrWhiteSpace([string]$_.task_category)) {
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
            engineering_memory_available = (Test-Path -Path $engineeringMemoryPath)
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
    if (Test-Path -Path $engineeringMemoryPath) {
        try {
            $memory = (Get-Content -Path $engineeringMemoryPath -Raw) | ConvertFrom-Json
        }
        catch {
            $memory = $null
        }
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
        $objectiveTasks = @($tasks | Where-Object { [string]$_.objective_id -eq [string]$objective.id })
        $preferred = @($objectiveTasks | Where-Object {
                $status = if ($_.PSObject.Properties["status"]) { ([string]$_.status).ToLowerInvariant() } else { "" }
                $status -in @("in_progress", "open", "planned", "todo")
            } | Sort-Object updated_at, created_at -Descending | Select-Object -First 1)
        if (@($preferred).Count -gt 0) {
            $selectedTask = $preferred
        }
        else {
            $selectedTask = @($objectiveTasks | Sort-Object updated_at, created_at -Descending | Select-Object -First 1)
        }
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
    $objectiveTasks = if ([string]::IsNullOrWhiteSpace($currentObjectiveId)) { @() } else { @($tasks | Where-Object { [string]$_.objective_id -eq $currentObjectiveId }) }

    $taskStatusCounts = @{}
    foreach ($task in $objectiveTasks) {
        $statusValue = if ($task.PSObject.Properties["status"] -and -not [string]::IsNullOrWhiteSpace([string]$task.status)) { [string]$task.status } else { "unknown" }
        $statusKey = $statusValue.Trim().ToLowerInvariant()
        if (-not $taskStatusCounts.ContainsKey($statusKey)) {
            $taskStatusCounts[$statusKey] = 0
        }
        $taskStatusCounts[$statusKey] = [int]$taskStatusCounts[$statusKey] + 1
    }

    $activeTask = @($tasks | Sort-Object updated_at -Descending | Where-Object {
            $_.PSObject.Properties["status"] -and
            ([string]$_.status).ToLowerInvariant() -eq "in_progress"
        } | Select-Object -First 1)
    if (@($activeTask).Count -eq 0) {
        $activeTask = @($tasks | Sort-Object updated_at -Descending | Select-Object -First 1)
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
    $runHistory = if ($engineeringLoop -and $engineeringLoop.PSObject.Properties["run_history"]) { @($engineeringLoop.run_history) } else { @() }
    $scorecardHistory = if ($engineeringLoop -and $engineeringLoop.PSObject.Properties["scorecard_history"]) { @($engineeringLoop.scorecard_history) } else { @() }
    $cycleRecords = if ($engineeringLoop -and $engineeringLoop.PSObject.Properties["cycle_records"]) { @($engineeringLoop.cycle_records) } else { @() }
    $reviewActions = if ($engineeringLoop -and $engineeringLoop.PSObject.Properties["review_actions"]) { @($engineeringLoop.review_actions) } else { @() }
    $recentRuns = @($runHistory | Sort-Object generated_at -Descending | Select-Object -First 5)
    $recentScorecards = @($scorecardHistory | Sort-Object generated_at -Descending | Select-Object -First 5)
    $recentCycles = @($cycleRecords | Sort-Object created_at -Descending | Select-Object -First 5)
    $recentReviews = @($reviewActions | Sort-Object created_at -Descending | Select-Object -First 5)
    $lastRun = if (@($recentRuns).Count -gt 0) { $recentRuns[0] } elseif ($engineeringLoop -and $engineeringLoop.PSObject.Properties["last_run"]) { $engineeringLoop.last_run } else { $null }
    $lastScorecard = if (@($recentScorecards).Count -gt 0) { $recentScorecards[0] } elseif ($engineeringLoop -and $engineeringLoop.PSObject.Properties["last_scorecard"]) { $engineeringLoop.last_scorecard } else { $null }
    $lastCycle = if (@($recentCycles).Count -gt 0) { $recentCycles[0] } elseif ($engineeringLoop -and $engineeringLoop.PSObject.Properties["last_cycle"]) { $engineeringLoop.last_cycle } else { $null }

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
            $_.PSObject.Properties["approval_status"] -and
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

    $targetMatch = @($State.routing_decisions.records | Where-Object { [string]$_.id -eq $RoutingDecisionId } | Select-Object -First 1)
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

    if (-not (Test-Path -Path $engineeringMemoryPath)) { return }

    try {
        $memory = (Get-Content -Path $engineeringMemoryPath -Raw) | ConvertFrom-Json
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
        $memory | ConvertTo-Json -Depth 20 | Set-Content -Path $engineeringMemoryPath
        if (Test-Path -Path $stateEngineeringMemoryPath) {
            $memory | ConvertTo-Json -Depth 20 | Set-Content -Path $stateEngineeringMemoryPath
        }
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

    $blob = (([string]$Task.title + " " + [string]$Task.scope)).ToLowerInvariant()
    if ($blob -match 'repo index|index-repo|indexing') { return "repo_index" }
    if ($blob -match 'module summary|summar') { return "module_summary" }
    if ($blob -match 'refactor') { return "refactor" }
    if ($blob -match 'test generation|generate test|tests?') { return "test_generation" }
    if ($blob -match 'review only|review') { return "review_only" }
    if ($blob -match 'sync|manifest|drift') { return "sync_check" }
    return "code_change"
}

function Sync-EnginePerformanceToEngineeringMemory {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)]$LatestRecord
    )

    if (-not (Test-Path -Path $engineeringMemoryPath)) { return }

    try {
        $memory = (Get-Content -Path $engineeringMemoryPath -Raw) | ConvertFrom-Json
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
        $memory | ConvertTo-Json -Depth 20 | Set-Content -Path $engineeringMemoryPath
        if (Test-Path -Path $stateEngineeringMemoryPath) {
            $memory | ConvertTo-Json -Depth 20 | Set-Content -Path $stateEngineeringMemoryPath
        }
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

    $latestResult = @($State.execution_results | Where-Object { $taskKeys -contains [string]$_.task_id } | Sort-Object -Property created_at -Descending | Select-Object -First 1)
    $latestReview = @($State.review_decisions | Where-Object { $taskKeys -contains [string]$_.task_id } | Sort-Object -Property created_at -Descending | Select-Object -First 1)
    $latestRouting = @($State.routing_decisions.records | Where-Object { $taskKeys -contains [string]$_.task_id } | Sort-Object -Property created_at -Descending | Select-Object -First 1)
    $latestRoutingRecord = if (@($latestRouting).Count -gt 0) { $latestRouting[0] } else { $null }

    $engineName = ""
    $fallbackApplied = $false
    $attempted = @()
    $performanceRecordId = ""
    $lastRunSource = "manual_or_unknown"

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
                active = "codex"
                fallback = "local"
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
                active = "codex"
                fallback = "local"
                allow_fallback = $true
            }) -Force
    }

    if ([string]::IsNullOrWhiteSpace([string]$cfg.execution_engine.active)) { $cfg.execution_engine.active = "codex" }
    if ([string]::IsNullOrWhiteSpace([string]$cfg.execution_engine.fallback)) { $cfg.execution_engine.fallback = "local" }
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
        [string]$TaskCategoryHint
    )

    $supported = @(Get-SupportedExecutionEngines)
    $active = ([string]$Config.execution_engine.active).ToLowerInvariant()
    $fallback = ([string]$Config.execution_engine.fallback).ToLowerInvariant()
    $allowFallback = [bool]$Config.execution_engine.allow_fallback
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
        $policyEnabled = [bool]$policy.enabled
        $minRuns = [int]$policy.min_runs
        $minSuccessRate = [double]$policy.min_success_rate
        $improvementMargin = [double]$policy.improvement_margin
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
        $perfSummary = Get-EnginePerformanceSummary -State $State -TaskCategoryFilter $TaskCategoryHint
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

        $activeDrift = Get-RoutingDriftSignal -State $State -RoutingPolicy $policySnapshot -EngineFilter $active -TaskCategoryFilter $TaskCategoryHint
        if ($allowFallback -and $fallback -ne $active) {
            $fallbackDrift = Get-RoutingDriftSignal -State $State -RoutingPolicy $policySnapshot -EngineFilter $fallback -TaskCategoryFilter $TaskCategoryHint
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
        $activeScore = [math]::Round(([double]$activeScore * (Get-HealthBandMultiplier -HealthRecord $activeHealth)), 6)
        $scoresByEngine[$active] = $activeScore
        $fallbackScore = $null
        if ($allowFallback -and $fallback -ne $active) {
            $fallbackScore = Get-WeightedEngineScore -EngineName $fallback -Metrics $fallbackMetrics -MinRuns $minRuns -LatencyMin $latencyMin -LatencyMax $latencyMax -Weights $effectiveWeights
            if ($fallbackDrift -and $fallbackDrift.PSObject.Properties["score_penalty"] -and $null -ne $fallbackDrift.score_penalty) {
                $fallbackScore = [math]::Max(0.0, ([double]$fallbackScore - [double]$fallbackDrift.score_penalty))
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

        if ($active -eq "local" -and $TaskCategoryHint -eq "code_change" -and (-not $allowPlaceholderForCodeChange)) {
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
            if ($active -eq "local" -and $TaskCategoryHint -eq "code_change" -and (-not $allowPlaceholderForCodeChange)) { $blockedEngines += $active }
            if ($fallback -eq "local" -and $TaskCategoryHint -eq "code_change" -and (-not $allowPlaceholderForCodeChange)) { $blockedEngines += $fallback }

            $recentCategoryRecords = @($State.engine_performance.records | Where-Object {
                    if ($null -eq $_.PSObject.Properties["task_category"]) { return $false }
                    ([string]$_.task_category).ToLowerInvariant() -eq ([string]$TaskCategoryHint).ToLowerInvariant()
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

            if ((-not $routingBlocked) -and $activeRuns -lt $minRuns -and $fallbackRuns -ge $minRuns) {
                $active = $fallback
                $routingApplied = $true
                $routingReason = "no_active_history_use_fallback"
                $selectionReason = "Fallback chosen because active engine has insufficient history in this category."
                $confidence = 0.68
            }
            elseif ((-not $routingBlocked) -and $activeRuns -ge $minRuns -and $activeSuccess -lt $minSuccessRate -and $fallbackRuns -ge 1 -and $fallbackSuccess -ge ($activeSuccess + ($improvementMargin / [math]::Max($historyWeightMultiplier, 0.15)))) {
                $active = $fallback
                $routingApplied = $true
                $routingReason = "performance_policy_switch"
                $selectionReason = "Fallback chosen due to stronger category performance and lower observed risk."
                $confidence = [math]::Round((0.62 + (0.18 * $historyWeightMultiplier)), 2)
            }

            if ((-not $routingBlocked) -and (-not $routingApplied) -and $null -ne $fallbackScore) {
                $requiredAdvantage = ($improvementMargin / 100.0) / [math]::Max($historyWeightMultiplier, 0.2)
                if (($fallbackScore - $activeScore) -ge $requiredAdvantage -and $fallbackRuns -ge 1) {
                    $active = $fallback
                    $routingApplied = $true
                    $routingReason = "weighted_history_score_switch"
                    $selectionReason = "Fallback chosen by weighted history score (success, failures, review corrections, latency) with health bands active=$activeHealthBand fallback=$fallbackHealthBand."
                    $confidence = [math]::Round([math]::Min(0.98, 0.5 + (0.45 * [double]$fallbackScore)), 2)
                }
            }

            if ((-not $routingBlocked) -and $preferStableOnSyncWarn -and $syncStatus -eq "warn") {
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
        retry_policy = $Config.execution_engine.retry_policy
        supported = @($supported)
        routing = [pscustomobject]@{
            applied = $routingApplied
            reason = $(if ($DisableAdaptiveRouting) { "forced_configured_engine" } else { $routingReason })
            disabled = [bool]$DisableAdaptiveRouting
            blocked = [bool]$routingBlocked
            task_category = $TaskCategoryHint
            source = $policySource
            confidence = [math]::Round($confidence, 4)
            selection_reason = $selectionReason
            candidate_engines = @($candidateEngines)
            sample_mode = $sampleMode
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
        needs_escalation = [bool]$EngineResult.needs_escalation
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
        needs_escalation = [bool]$EngineResult.needs_escalation
    }
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

    $context = New-EngineTaskContext `
        -TaskId $TaskId `
        -ObjectiveId ([string]$Task.objective_id) `
        -Title ([string]$Task.title) `
        -Scope ([string]$Task.scope) `
        -PromptPath $PackagePath `
        -AllowedFiles @() `
        -ValidationCommands @() `
        -Metadata @{ source = "tod.invoke-engine"; generated_at = (Get-UtcNow) }

    $attempted = @()
    $fallbackReason = ""
    $invocationStart = Get-Date
    $retryPolicy = if ($EngineConfig.PSObject.Properties["retry_policy"] -and $null -ne $EngineConfig.retry_policy) { $EngineConfig.retry_policy } else { $null }
    $retryEnabled = if ($retryPolicy -and $retryPolicy.PSObject.Properties["enabled"]) { [bool]$retryPolicy.enabled } else { $true }
    $maxAttemptsPerEngine = if ($retryPolicy -and $retryPolicy.PSObject.Properties["max_attempts_per_engine"] -and $null -ne $retryPolicy.max_attempts_per_engine) { [int]$retryPolicy.max_attempts_per_engine } else { 2 }
    $maxAttemptsByCategory = if ($retryPolicy -and $retryPolicy.PSObject.Properties["max_attempts_by_category"] -and $null -ne $retryPolicy.max_attempts_by_category) { $retryPolicy.max_attempts_by_category } else { $null }
    $resolvedTaskCategory = Resolve-TaskCategory -Task $Task
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
    if ($primaryAttempt.success) {
        $engineResult = $primaryAttempt.result
    }
    else {
        $mustFallbackByStatus = $true
        $fallbackReason = "active_engine_$([string]$primaryAttempt.terminal_reason)"
    }

    if ($mustFallbackByStatus) {
        $fallback = [string]$EngineConfig.fallback
        $canFallback = [bool]$EngineConfig.allow_fallback -and -not [string]::IsNullOrWhiteSpace($fallback) -and ($fallback -ne $selected)
        if ($canFallback) {
            $attempted += $fallback
            $fallbackAttempt = Invoke-OneEngineWithRetry -EngineName $fallback -Ctx $context
            $attemptDetails += @($fallbackAttempt.attempts)
            if ($fallbackAttempt.success) {
                $engineResult = $fallbackAttempt.result
                $selected = $fallback
            }
            else {
                throw "Fallback engine '$fallback' failed after retries. reason=$([string]$fallbackAttempt.terminal_reason)"
            }
        }
        elseif ($null -eq $engineResult) {
            throw "Execution engine '$selected' failed and fallback is unavailable. $fallbackReason"
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

function Save-JsonObject {
    param([Parameter(Mandatory = $true)]$Object, [Parameter(Mandatory = $true)][string]$Path)
    $Object | ConvertTo-Json -Depth 16 | Set-Content -Path $Path
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

    if (-not (Test-Path -Path $engineeringMemoryPath)) { return }

    $memory = (Get-Content -Path $engineeringMemoryPath -Raw) | ConvertFrom-Json
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
    Save-JsonObject -Object $memory -Path $engineeringMemoryPath
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
    if (-not (Use-Remote -Config $Config)) {
        return [pscustomobject]@{ attempted = $false; published = $false; reason = "remote_mode_disabled" }
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

$state = Load-State
$config = Load-TodConfig
if (Get-Command -Name Set-MimApiDebugLogging -ErrorAction SilentlyContinue) {
    $resolvedDebugPath = [string]$config.mim_debug.log_path
    if ([string]::IsNullOrWhiteSpace($resolvedDebugPath)) {
        $resolvedDebugPath = Join-Path $repoRoot "tod/out/mim-http.log"
    }
    Set-MimApiDebugLogging -Enabled ([bool]$config.mim_debug.enabled) -LogPath $resolvedDebugPath
}
$engineConfig = Resolve-ExecutionEngineConfig -Config $config -State $state -DisableAdaptiveRouting:$ForceConfiguredEngine
$capabilityGate = Apply-CapabilityDegrade -Config $config -State $state -ActionName $Action
Assert-ContractGate -ActionName $Action -State $state -AllowDrift:$AllowContractDrift

if ((Use-Remote -Config $config) -and -not (Get-Command -Name Get-MimHealth -ErrorAction SilentlyContinue)) {
    throw "MIM client functions are unavailable. Ensure client/mim_api_client.ps1 exists."
}

switch ($Action) {
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

        $id = New-Id -Prefix "OBJ" -Count $state.objectives.Count
        $obj = [pscustomobject]@{
            id = $id
            title = $Title
            description = $Description
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

        if (Use-Local -Config $config) {
            $objective = $state.objectives | Where-Object { $_.id -eq $ObjectiveId } | Select-Object -First 1
            if (-not $objective) { throw "Objective not found: $ObjectiveId" }
        }

        $id = New-Id -Prefix "TSK" -Count $state.tasks.Count
        $task = [pscustomobject]@{
            id = $id
            objective_id = $ObjectiveId
            title = $Title
            type = $Type
            task_category = $(if ([string]::IsNullOrWhiteSpace($TaskCategory)) { "" } else { $TaskCategory })
            scope = $Scope
            dependencies = [string[]](Split-List -Value $Dependencies)
            acceptance_criteria = [string[]](Split-List -Value $AcceptanceCriteria)
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
        $actionEngineConfig = Resolve-ExecutionEngineConfig -Config $config -State $state -DisableAdaptiveRouting:$ForceConfiguredEngine -TaskCategoryHint $taskCategoryResolved
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
        if (-not $task) { throw "Task not found in local state cache: $TaskId" }
        $feedbackConfig = Resolve-ExecutionFeedbackConfig -Config $config
        $resolvedExecutionId = Resolve-ExecutionIdForTask -ExplicitExecutionId $ExecutionId -Task $task
        $feedbackEvents = @()
        $taskCategoryResolved = Resolve-TaskCategory -Task $task
        $actionEngineConfig = Resolve-ExecutionEngineConfig -Config $config -State $state -DisableAdaptiveRouting:$ForceConfiguredEngine -TaskCategoryHint $taskCategoryResolved
        $routingPre = Add-RoutingDecisionRecord -State $state -TaskId $TaskId -ActionName "run_task" -EngineConfig $actionEngineConfig -TaskCategory $taskCategoryResolved -FinalOutcome "pre_invocation"
        $routingPre = @($routingPre | Select-Object -First 1)
        Save-State -State $state

        if ($actionEngineConfig.routing -and $actionEngineConfig.routing.PSObject.Properties["blocked"] -and [bool]$actionEngineConfig.routing.blocked) {
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
            Save-State -State $state

            [pscustomobject]@{
                task_id = [string]$TaskId
                execution_id = [string]$resolvedExecutionId
                task_category = $taskCategoryResolved
                decision = "escalate"
                blocked = $true
                execution_feedback = @($feedbackEvents)
                routing_decision_preinvoke = $routingPre[0]
                routing_decision = $routingFinalBlocked
                message = "run-task blocked by routing guardrail before engine invocation."
            } | ConvertTo-Json -Depth 12
            break
        }

        $packagePath = Resolve-TaskPackagePath -TaskId $TaskId -ExplicitPath $PackagePath
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

        $invokeResult = $null
        try {
            $invokeResult = Invoke-ExecutionEngine -Task $task -TaskId $TaskId -PackagePath $packagePath -EngineConfig $actionEngineConfig
        }
        catch {
            $failedFeedback = Try-PublishExecutionFeedback -Config $config -FeedbackConfig $feedbackConfig -ExecutionId $resolvedExecutionId -Status "failed" -TaskId $TaskId -Details ([pscustomobject]@{
                    reason = "executor_unavailable"
                    task_category = $taskCategoryResolved
                    error = [string]$_.Exception.Message
                })
            $feedbackEvents += @([pscustomobject]@{ status = "failed"; publish = $failedFeedback })
            throw
        }

        $resultPayload = $invokeResult.result
        $filesChangedCsv = (@($resultPayload.files_changed) | ForEach-Object { [string]$_ }) -join ","
        $testsRunCsv = (@($resultPayload.tests_run) | ForEach-Object { [string]$_ }) -join ","
        $testResultsCsv = (@($resultPayload.test_results) | ForEach-Object { [string]$_ }) -join ","
        $failuresCsv = (@($resultPayload.failures) | ForEach-Object { [string]$_ }) -join ","
        $recommendationsCsv = (@($resultPayload.recommendations) | ForEach-Object { [string]$_ }) -join ","

        $addResultResponse = (& $PSCommandPath -Action add-result -ConfigPath $configPath -TaskId $TaskId -Summary ([string]$resultPayload.summary) -FilesChanged $filesChangedCsv -TestsRun $testsRunCsv -TestResults $testResultsCsv -Failures $failuresCsv -Recommendations $recommendationsCsv) | ConvertFrom-Json

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

        $rationale = "run-task completed via invoke-engine and result persistence."
        if (@($precheckWarnings).Count -gt 0) {
            $rationale = "run-task completed with precheck warnings: $($precheckWarnings -join '; ')"
        }

        $unresolvedCsv = (@($resultPayload.failures) + @($precheckWarnings) | ForEach-Object { [string]$_ }) -join ","
        $reviewResponse = (& $PSCommandPath -Action review-task -ConfigPath $configPath -TaskId $TaskId -Decision $reviewDecision -Rationale $rationale -UnresolvedIssues $unresolvedCsv) | ConvertFrom-Json

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

        $stateAfter = Load-State
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
            })
        Save-State -State $stateAfter

        [pscustomobject]@{
            task_id = $TaskId
            execution_id = [string]$resolvedExecutionId
            package_path = $packagePath
            engine_invocation = $invokeResult
            add_result_response = $addResultResponse
            review_response = $reviewResponse
            decision = $reviewDecision
            execution_feedback = @($feedbackEvents)
            routing_decision_preinvoke = $routingPre[0]
            routing_decision = $routingRecord
            engine_performance_record = $perfRecord
        } | ConvertTo-Json -Depth 12
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
        $report = Build-FailureTaxonomyReport -State $state -Window $Top -CategoryFilter $Category -EngineFilter $Engine
        $report | ConvertTo-Json -Depth 16
    }

    "show-reliability-dashboard" {
        $dashboard = Build-ReliabilityDashboard -State $state -Config $config -Window $Top -CategoryFilter $Category -EngineFilter $Engine
        $dashboard | ConvertTo-Json -Depth 18
    }

    "get-reliability" {
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

    "engineer-run" {
        $payload = Get-TodEngineerRunPayload -State $state -Config $config -ObjectiveId $ObjectiveId -TaskId $TaskId -Body $Content -Append:$Append -ApplyPlan:$ApplyPlan -DangerousApproved:$DangerousApproved -Top $Top
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
        $payload = Get-TodEngineeringLoopSummaryPayload -State $state -Config $config -Top $Top
        $payload | ConvertTo-Json -Depth 18
    }

    "get-engineering-signal" {
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

    "get-state-bus" {
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
        if (Use-Local -Config $config) {
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
        if (Use-Remote -Config $config) {
            $remoteTaskId = Resolve-RemoteTaskId -TaskId $TaskId -State $state
            if ($null -ne $remoteTaskId) {
                $remoteCreated = Invoke-MimSafely -Config $config -Operation "POST /results" -ApiCall {
                    New-MimResult -BaseUrl $config.mim_base_url -TimeoutSeconds ([int]$config.timeout_seconds) -Result $result -RemoteTaskId $remoteTaskId
                }
            }
            elseif (([string]$config.mode).ToLowerInvariant() -eq "remote") {
                throw "Cannot submit result to MIM without a remote integer task ID for task '$TaskId'."
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

        if ((Use-Local -Config $config) -or ((([string]$config.mode).ToLowerInvariant() -eq "hybrid") -and $null -eq $remoteCreated -and [bool]$config.fallback_to_local)) {
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

        if (Use-Local -Config $config) {
            if ($remoteCreated) {
                [pscustomobject]@{
                    mode = $config.mode
                    local = $result
                    remote = $remoteCreated
                    engine_metadata = $result.engine_metadata
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
            $remoteCreated | ConvertTo-Json -Depth 12
        }
    }

    "review-task" {
        if ([string]::IsNullOrWhiteSpace($TaskId)) { throw "-TaskId is required" }
        if ([string]::IsNullOrWhiteSpace($Decision)) { throw "-Decision is required" }
        if ([string]::IsNullOrWhiteSpace($Rationale)) { throw "-Rationale is required" }

        $task = $null
        if (Use-Local -Config $config) {
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
        if (Use-Remote -Config $config) {
            $remoteTaskId = Resolve-RemoteTaskId -TaskId $TaskId -State $state
            if ($null -ne $remoteTaskId) {
                $remoteCreated = Invoke-MimSafely -Config $config -Operation "POST /reviews" -ApiCall {
                    New-MimReview -BaseUrl $config.mim_base_url -TimeoutSeconds ([int]$config.timeout_seconds) -Review $review -RemoteTaskId $remoteTaskId
                }
            }
            elseif (([string]$config.mode).ToLowerInvariant() -eq "remote") {
                throw "Cannot submit review to MIM without a remote integer task ID for task '$TaskId'."
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

        if ((Use-Local -Config $config) -or ((([string]$config.mode).ToLowerInvariant() -eq "hybrid") -and $null -eq $remoteCreated -and [bool]$config.fallback_to_local)) {
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

        if (Use-Local -Config $config) {
            if ($remoteCreated) {
                [pscustomobject]@{
                    mode = $config.mode
                    local = $review
                    remote = $remoteCreated
                } | ConvertTo-Json -Depth 12
            }
            else {
                $review | ConvertTo-Json -Depth 8
            }
        }
        else {
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
