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
    [string]$PackagePath
    ,[string]$Engine
    ,[string]$Category
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
    $raw = Get-Content -Path $statePath -Raw
    $state = $raw | ConvertFrom-Json
    Normalize-State -State $state
    return $state
}

function Save-State {
    param([Parameter(Mandatory = $true)]$State)
    Normalize-State -State $State
    $json = $State | ConvertTo-Json -Depth 12
    Set-Content -Path $statePath -Value $json
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
        recent_routing_decisions = @($recentRouting.records)
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
        if ($policy.PSObject.Properties["weights"] -and $null -ne $policy.weights) { $weights = $policy.weights }
    }

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
        weights = $weights
        effective_weights = $effectiveWeights
    }

    $activeMetrics = $null
    $fallbackMetrics = $null
    $activeHealth = $null
    $fallbackHealth = $null
    $activeHealthBand = "unknown"
    $fallbackHealthBand = "unknown"
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
        $activeScore = [math]::Round(([double]$activeScore * (Get-HealthBandMultiplier -HealthRecord $activeHealth)), 6)
        $scoresByEngine[$active] = $activeScore
        $fallbackScore = $null
        if ($allowFallback -and $fallback -ne $active) {
            $fallbackScore = Get-WeightedEngineScore -EngineName $fallback -Metrics $fallbackMetrics -MinRuns $minRuns -LatencyMin $latencyMin -LatencyMax $latencyMax -Weights $effectiveWeights
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
            Save-State -State $state

            [pscustomobject]@{
                task_id = [string]$TaskId
                task_category = $taskCategoryResolved
                decision = "escalate"
                blocked = $true
                routing_decision_preinvoke = $routingPre[0]
                routing_decision = $routingFinalBlocked
                message = "run-task blocked by routing guardrail before engine invocation."
            } | ConvertTo-Json -Depth 12
            break
        }

        $packagePath = Resolve-TaskPackagePath -TaskId $TaskId -ExplicitPath $PackagePath
        $invokeResult = Invoke-ExecutionEngine -Task $task -TaskId $TaskId -PackagePath $packagePath -EngineConfig $actionEngineConfig

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
            package_path = $packagePath
            engine_invocation = $invokeResult
            add_result_response = $addResultResponse
            review_response = $reviewResponse
            decision = $reviewDecision
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
