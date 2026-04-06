param(
    [ValidateSet("publish-event", "consume-event", "consume-inbox", "status", "summarize-executions")][string]$Action = "status",
    [string]$EventType,
    [string]$EventJson,
    [string]$EventFile,
    [string]$EventId,
    [string]$TraceId,
    [string]$ExecutionId,
    [string]$GoalId,
    [string]$PlanId,
    [string]$ActionId,
    [string]$SourceDomain,
    [string]$SourceContext,
    [string[]]$ArtifactPaths = @(),
    [string]$EventStreamPath = "tod/out/bus/events.jsonl",
    [string]$InboundInboxPath = "tod/inbox/bus/events",
    [string]$ProcessedInboxPath = "tod/out/bus/processed",
    [string]$AdapterStatePath = "tod/out/bus/adapter-state.json",
    [string]$ConsumerLogPath = "tod/out/bus/consumer-log.jsonl",
    [string]$CorrelationLogPath = "shared_state/bus_correlation_links.jsonl",
    [string]$SchemaPath = "tod/templates/bus/tod_bus_adapter_event.schema.json",
    [string]$BusStatusPath = "shared_state/bus_adapter_status.json",
    [string]$ExecutionSummaryPath = "shared_state/bus_execution_summaries.json",
    [string]$ExecutionSummaryIndexPath = "shared_state/bus_execution_summaries.index.json",
    [string]$ExecutionSummaryContractPath = "tod/templates/bus/tod_bus_execution_summary_handoff.schema.json",
    [string]$ExecutionDomainPolicyPath = "tod/templates/bus/tod_cross_domain_execution_policy.json",
    [string]$PerceptionContextSchemaPath = "tod/templates/bus/tod_perception_context.schema.json",
    [string]$TodScriptPath = "scripts/TOD.ps1",
    [string]$TodConfigPath = "tod/config/tod-config.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

function Get-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) { return $PathValue }
    return (Join-Path $repoRoot $PathValue)
}

function Ensure-ParentDir {
    param([Parameter(Mandatory = $true)][string]$FilePath)
    $dir = Split-Path -Parent $FilePath
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

function Get-RepoRelativePath {
    param([Parameter(Mandatory = $true)][string]$AbsolutePath)

    $baseFull = [System.IO.Path]::GetFullPath($repoRoot)
    $targetFull = [System.IO.Path]::GetFullPath($AbsolutePath)

    if (-not $baseFull.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
        $baseFull = $baseFull + [System.IO.Path]::DirectorySeparatorChar
    }

    $baseUri = New-Object System.Uri($baseFull)
    $targetUri = New-Object System.Uri($targetFull)
    $relativeUri = $baseUri.MakeRelativeUri($targetUri)
    $relativePath = [System.Uri]::UnescapeDataString($relativeUri.ToString())
    return $relativePath.Replace("\\", "/")
}

function Append-JsonLine {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Object
    )

    Ensure-ParentDir -FilePath $Path
    ($Object | ConvertTo-Json -Depth 20 -Compress) + [Environment]::NewLine | Add-Content -Path $Path
}

function Load-JsonIfExists {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -Path $Path)) { return $null }
    return (Get-Content -Path $Path -Raw | ConvertFrom-Json)
}

function Get-AdapterState {
    param([Parameter(Mandatory = $true)][string]$StateFile)

    $state = Load-JsonIfExists -Path $StateFile
    if ($null -eq $state) {
        return [pscustomobject]@{
            source = "tod-bus-adapter-v1"
            updated_at = ""
            processed_event_ids = @()
            counters = [pscustomobject]@{
                inbound_accepted = 0
                inbound_rejected = 0
                inbound_ignored = 0
                inbound_duplicate = 0
                outbound_published = 0
                retries_scheduled = 0
                recoveries = 0
                drift_detected = 0
                fallback_applied = 0
                cancelled = 0
                guardrail_blocked = 0
                failed_runtime = 0
                successful_runtime = 0
                paused_pending_inquiry = 0
                resumed_after_inquiry = 0
                deferred_for_operator_clarification = 0
                cancelled_pending_inquiry_timeout = 0
                domain_policy_allowed = 0
                domain_policy_blocked = 0
                domain_policy_deferred = 0
                domain_policy_dry_run_only = 0
            }
            accepted_execution_ids = @()
            paused_execution_ids = @()
        }
    }

    if (-not $state.PSObject.Properties["processed_event_ids"] -or $null -eq $state.processed_event_ids) {
        $state | Add-Member -NotePropertyName processed_event_ids -NotePropertyValue @() -Force
    }
    if (-not $state.PSObject.Properties["counters"] -or $null -eq $state.counters) {
        $state | Add-Member -NotePropertyName counters -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    if (-not $state.PSObject.Properties["accepted_execution_ids"] -or $null -eq $state.accepted_execution_ids) {
        $state | Add-Member -NotePropertyName accepted_execution_ids -NotePropertyValue @() -Force
    }
    if (-not $state.PSObject.Properties["paused_execution_ids"] -or $null -eq $state.paused_execution_ids) {
        $state | Add-Member -NotePropertyName paused_execution_ids -NotePropertyValue @() -Force
    }

    foreach ($name in @(
            "inbound_accepted", "inbound_rejected", "inbound_ignored", "inbound_duplicate", "outbound_published",
            "retries_scheduled", "recoveries", "drift_detected", "fallback_applied", "cancelled",
            "guardrail_blocked", "failed_runtime", "successful_runtime", "paused_pending_inquiry",
            "resumed_after_inquiry", "deferred_for_operator_clarification", "cancelled_pending_inquiry_timeout",
            "domain_policy_allowed", "domain_policy_blocked", "domain_policy_deferred", "domain_policy_dry_run_only"
        )) {
        if (-not $state.counters.PSObject.Properties[$name]) {
            $state.counters | Add-Member -NotePropertyName $name -NotePropertyValue 0 -Force
        }
    }

    return $state
}

function Save-AdapterState {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][string]$StateFile
    )

    $State.updated_at = (Get-Date).ToUniversalTime().ToString("o")
    Ensure-ParentDir -FilePath $StateFile
    $State | ConvertTo-Json -Depth 20 | Set-Content -Path $StateFile
}

function Get-Schema {
    param([Parameter(Mandatory = $true)][string]$SchemaFile)
    $schema = Load-JsonIfExists -Path $SchemaFile
    if ($null -eq $schema) {
        throw "Schema file not found: $SchemaFile"
    }
    return $schema
}

function Get-TodConfigDocument {
    param([Parameter(Mandatory = $true)][string]$ConfigFile)

    return (Load-JsonIfExists -Path $ConfigFile)
}

function Get-InquiryPendingTimeoutSeconds {
    param($Config)

    if ($null -ne $Config -and
        $Config.PSObject.Properties["execution_engine"] -and
        $null -ne $Config.execution_engine -and
        $Config.execution_engine.PSObject.Properties["inquiry_control"] -and
        $null -ne $Config.execution_engine.inquiry_control -and
        $Config.execution_engine.inquiry_control.PSObject.Properties["pending_timeout_seconds"]) {
        try {
            return [int]$Config.execution_engine.inquiry_control.pending_timeout_seconds
        }
        catch {
        }
    }

    return 30
}

function Get-PerceptionContextSchema {
    param([Parameter(Mandatory = $true)][string]$SchemaFile)

    return (Load-JsonIfExists -Path $SchemaFile)
}

function Test-PerceptionContextPayload {
    param(
        $Payload,
        $Schema
    )

    $result = [pscustomobject]@{
        has_context = $false
        valid = $true
        reason_code = ""
        message = ""
    }

    if ($null -eq $Payload -or -not $Payload.PSObject.Properties["perception_context"] -or $null -eq $Payload.perception_context) {
        return $result
    }

    $result.has_context = $true
    $context = $Payload.perception_context
    if ($null -eq $Schema) {
        return $result
    }

    foreach ($field in @($Schema.required_fields)) {
        if (-not $context.PSObject.Properties[[string]$field] -or [string]::IsNullOrWhiteSpace([string]$context.([string]$field))) {
            $result.valid = $false
            $result.reason_code = "perception_context_invalid"
            $result.message = ("Perception context is missing required field '{0}'." -f [string]$field)
            return $result
        }
    }

    if ($Schema.PSObject.Properties["allowed_state_values"] -and @($Schema.allowed_state_values).Count -gt 0 -and @($Schema.allowed_state_values) -notcontains ([string]$context.state)) {
        $result.valid = $false
        $result.reason_code = "perception_context_invalid"
        $result.message = "Perception context state is not allowed by schema."
        return $result
    }

    if ($Schema.PSObject.Properties["allowed_safety_values"] -and @($Schema.allowed_safety_values).Count -gt 0 -and @($Schema.allowed_safety_values) -notcontains ([string]$context.safety)) {
        $result.valid = $false
        $result.reason_code = "perception_context_invalid"
        $result.message = "Perception context safety is not allowed by schema."
        return $result
    }

    return $result
}

function Get-ExecutionDomainPolicy {
    param([Parameter(Mandatory = $true)][string]$PolicyFile)

    $policy = Load-JsonIfExists -Path $PolicyFile
    if ($null -eq $policy) {
        throw "Execution domain policy file not found: $PolicyFile"
    }
    if (-not $policy.PSObject.Properties["domains"] -or $null -eq $policy.domains) {
        throw "Execution domain policy is missing domains"
    }
    return $policy
}

function Resolve-DomainPolicyDecision {
    param(
        [Parameter(Mandatory = $true)]$Policy,
        [Parameter(Mandatory = $true)][string]$SourceDomain,
        [Parameter(Mandatory = $true)][string]$RuntimeAction
    )

    $domainValue = if ([string]::IsNullOrWhiteSpace($SourceDomain)) { "legacy" } else { [string]$SourceDomain }
    $domainPolicy = @($Policy.domains | Where-Object { [string]$_.domain -ieq $domainValue } | Select-Object -First 1)
    if ($domainPolicy.Count -eq 0) {
        return [pscustomobject]@{ decision = "unsupported_domain"; source_domain = $domainValue; matched_domain = "" }
    }

    $matchedDomain = [string]$domainPolicy[0].domain
    if (@($domainPolicy[0].blocked_actions) -contains $RuntimeAction) {
        return [pscustomobject]@{ decision = "blocked"; source_domain = $domainValue; matched_domain = $matchedDomain }
    }
    if (@($domainPolicy[0].deferred_actions) -contains $RuntimeAction) {
        return [pscustomobject]@{ decision = "deferred"; source_domain = $domainValue; matched_domain = $matchedDomain }
    }
    if (@($domainPolicy[0].dry_run_only_actions) -contains $RuntimeAction) {
        return [pscustomobject]@{ decision = "dry_run_only"; source_domain = $domainValue; matched_domain = $matchedDomain }
    }
    if (@($domainPolicy[0].allowed_actions) -contains $RuntimeAction) {
        return [pscustomobject]@{ decision = "allowed"; source_domain = $domainValue; matched_domain = $matchedDomain }
    }

    return [pscustomobject]@{ decision = "blocked"; source_domain = $domainValue; matched_domain = $matchedDomain }
}

function Resolve-PerceptionContextDecision {
    param(
        [Parameter(Mandatory = $true)]$Policy,
        [Parameter(Mandatory = $true)][string]$SourceDomain,
        [Parameter(Mandatory = $true)][string]$RuntimeAction,
        $Payload
    )

    if (-not $Policy.PSObject.Properties["perception_context_rules"] -or $null -eq $Policy.perception_context_rules) {
        return $null
    }

    $contextState = ""
    $contextSafety = ""
    if ($null -ne $Payload -and $Payload.PSObject.Properties["perception_context"] -and $Payload.perception_context) {
        if ($Payload.perception_context.PSObject.Properties["state"] -and -not [string]::IsNullOrWhiteSpace([string]$Payload.perception_context.state)) {
            $contextState = [string]$Payload.perception_context.state
        }
        if ($Payload.perception_context.PSObject.Properties["safety"] -and -not [string]::IsNullOrWhiteSpace([string]$Payload.perception_context.safety)) {
            $contextSafety = [string]$Payload.perception_context.safety
        }
    }

    foreach ($rule in @($Policy.perception_context_rules)) {
        $domainMatches = [string]$rule.domain -ieq $SourceDomain
        if (-not $domainMatches) { continue }

        $actionMatches = (@($rule.runtime_actions).Count -eq 0) -or (@($rule.runtime_actions) -contains $RuntimeAction)
        if (-not $actionMatches) { continue }

        $stateMatches = (@($rule.context_states).Count -eq 0) -or (@($rule.context_states) -contains $contextState)
        if (-not $stateMatches) { continue }

        $safetyMatches = (@($rule.context_safety).Count -eq 0) -or (@($rule.context_safety) -contains $contextSafety)
        if (-not $safetyMatches) { continue }

        return [pscustomobject]@{
            decision = [string]$rule.decision
            reason_code = [string]$rule.reason_code
            message = [string]$rule.message
            context_state = $contextState
            context_safety = $contextSafety
        }
    }

    return $null
}

function New-Reason {
    param(
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][ValidateSet("info", "warning", "error", "critical")][string]$Severity,
        [Parameter(Mandatory = $true)][ValidateSet("execution", "guardrail", "retry", "drift", "recovery", "outcome")][string]$Category,
        [Parameter(Mandatory = $true)][string]$Message,
        $Evidence = $null
    )

    $reason = [ordered]@{
        code = $Code
        severity = $Severity
        category = $Category
        message = $Message
    }
    if ($null -ne $Evidence) {
        $reason["evidence"] = $Evidence
    }
    return [pscustomobject]$reason
}

function Test-MandatoryCorrelation {
    param(
        [Parameter(Mandatory = $true)]$Event,
        [Parameter(Mandatory = $true)]$Schema
    )

    if (-not $Event.PSObject.Properties["correlation"] -or $null -eq $Event.correlation) {
        return $false
    }

    foreach ($field in @($Schema.correlation_required_fields)) {
        if ($field -eq "event_id") {
            if (-not $Event.PSObject.Properties["event_id"] -or [string]::IsNullOrWhiteSpace([string]$Event.event_id)) { return $false }
        }
        else {
            if (-not $Event.correlation.PSObject.Properties[[string]$field] -or [string]::IsNullOrWhiteSpace([string]$Event.correlation.([string]$field))) { return $false }
        }
    }

    return $true
}

function New-CorrelationObject {
    $corr = [ordered]@{
        trace_id = $TraceId
        execution_id = $ExecutionId
    }
    if (-not [string]::IsNullOrWhiteSpace($GoalId)) { $corr.goal_id = $GoalId }
    if (-not [string]::IsNullOrWhiteSpace($PlanId)) { $corr.plan_id = $PlanId }
    if (-not [string]::IsNullOrWhiteSpace($ActionId)) { $corr.action_id = $ActionId }
    if (-not [string]::IsNullOrWhiteSpace($SourceDomain)) { $corr.source_domain = $SourceDomain }
    if (-not [string]::IsNullOrWhiteSpace($SourceContext)) { $corr.source_context = $SourceContext }
    return [pscustomobject]$corr
}

function Get-ParsedEvent {
    param(
        [string]$RawJson,
        [string]$FilePath
    )

    try {
        if (-not [string]::IsNullOrWhiteSpace($RawJson)) {
            return ($RawJson | ConvertFrom-Json)
        }
        if (-not [string]::IsNullOrWhiteSpace($FilePath)) {
            $resolved = Get-LocalPath -PathValue $FilePath
            return (Get-Content -Path $resolved -Raw | ConvertFrom-Json)
        }
        return $null
    }
    catch {
        return $null
    }
}

function Get-ExecutionIdFromEvent {
    param($Event)
    if ($null -eq $Event -or -not $Event.PSObject.Properties["correlation"] -or $null -eq $Event.correlation) { return "" }
    if (-not $Event.correlation.PSObject.Properties["execution_id"]) { return "" }
    return [string]$Event.correlation.execution_id
}

function Build-CorrelationFromEvent {
    param($Event)
    $corr = [ordered]@{
        trace_id = [string]$Event.correlation.trace_id
        execution_id = [string]$Event.correlation.execution_id
    }
    foreach ($name in @("goal_id", "plan_id", "action_id", "source_domain", "source_context")) {
        if ($Event.correlation.PSObject.Properties[$name] -and -not [string]::IsNullOrWhiteSpace([string]$Event.correlation.$name)) {
            $corr[$name] = [string]$Event.correlation.$name
        }
    }

    if (-not $corr.Contains("source_context") -and $Event.PSObject.Properties["payload"] -and $Event.payload -and $Event.payload.PSObject.Properties["perception_context"] -and $Event.payload.perception_context) {
        if ($Event.payload.perception_context.PSObject.Properties["context_id"] -and -not [string]::IsNullOrWhiteSpace([string]$Event.payload.perception_context.context_id)) {
            $corr["source_context"] = [string]$Event.payload.perception_context.context_id
        }
    }
    return [pscustomobject]$corr
}

function Get-LightweightEngineeringLoopSummary {
    $buildStatePath = Join-Path $repoRoot "shared_state/current_build_state.json"
    $summary = [ordered]@{
        runtime_action = "get-engineering-loop-summary"
        status = "ok"
        generated_at = (Get-Date).ToUniversalTime().ToString("o")
        source = "tod-bus-adapter-lightweight-summary-v1"
    }

    if (Test-Path -Path $buildStatePath) {
        try {
            $build = Get-Content -Path $buildStatePath -Raw | ConvertFrom-Json
            $summary["path"] = (Get-RepoRelativePath -AbsolutePath $buildStatePath)
            if ($build.PSObject.Properties["generated_at"] -and -not [string]::IsNullOrWhiteSpace([string]$build.generated_at)) {
                $summary["generated_at"] = [string]$build.generated_at
            }
            if ($build.PSObject.Properties["regression"] -and $build.regression) {
                $summary["regression"] = $build.regression
            }
        }
        catch {
            $summary["status"] = "warning"
            $summary["note"] = "current_build_state_unreadable"
        }
    }
    else {
        $summary["note"] = "current_build_state_missing"
    }

    return [pscustomobject]$summary
}

function Get-ReliabilitySignal {
    param(
        [Parameter(Mandatory = $true)][string]$FinalOutcome,
        [Parameter(Mandatory = $true)][int]$Retries,
        [Parameter(Mandatory = $true)][int]$Fallbacks,
        [Parameter(Mandatory = $true)][int]$DriftEvents,
        [Parameter(Mandatory = $true)][bool]$Recovered
    )

    if ($FinalOutcome -in @("failed", "cancelled", "guardrail_blocked", "cancelled_pending_inquiry_timeout")) {
        return "critical"
    }
    if ($DriftEvents -gt 0 -or $Fallbacks -gt 0) {
        return "warning"
    }
    if ($Retries -gt 0 -or $Recovered) {
        return "elevated"
    }
    return "stable"
}

function Get-RecommendedAttention {
    param([Parameter(Mandatory = $true)][string]$ReliabilitySignal)

    switch ($ReliabilitySignal) {
        "critical" { return "immediate_review" }
        "warning" { return "monitor_closely" }
        "elevated" { return "observe" }
        default { return "none" }
    }
}

function Get-ExecutionReliabilityScore {
    param(
        [Parameter(Mandatory = $true)][string]$ReliabilitySignal,
        [Parameter(Mandatory = $true)][int]$Retries,
        [Parameter(Mandatory = $true)][int]$Fallbacks,
        [Parameter(Mandatory = $true)][int]$DriftEvents,
        [Parameter(Mandatory = $true)][int]$GuardrailBlocks,
        [Parameter(Mandatory = $true)][int]$PausedEvents,
        [Parameter(Mandatory = $true)][int]$InquiryDeferrals,
        [Parameter(Mandatory = $true)][int]$InquiryTimeoutCancellations
    )

    $score = 1.0
    switch ($ReliabilitySignal) {
        "critical" { $score -= 0.45 }
        "warning" { $score -= 0.2 }
        "elevated" { $score -= 0.08 }
    }

    $score -= ([math]::Min($Retries, 3) * 0.05)
    $score -= ([math]::Min($Fallbacks, 2) * 0.08)
    $score -= ([math]::Min($DriftEvents, 2) * 0.08)
    $score -= ([math]::Min($GuardrailBlocks, 2) * 0.12)
    $score -= ([math]::Min($PausedEvents, 2) * 0.03)
    $score -= ([math]::Min($InquiryDeferrals, 2) * 0.04)
    $score -= ([math]::Min($InquiryTimeoutCancellations, 1) * 0.12)

    if ($score -lt 0.0) { $score = 0.0 }
    return [math]::Round($score, 3)
}

function Get-GuardrailTrend {
    param(
        [Parameter(Mandatory = $true)][int]$Accepted,
        [Parameter(Mandatory = $true)][int]$Blocked,
        [Parameter(Mandatory = $true)][int]$Deferred,
        [Parameter(Mandatory = $true)][int]$DryRunOnly
    )

    $evaluated = $Accepted + $Blocked + $Deferred + $DryRunOnly
    $blockedLike = $Blocked + $Deferred
    $rate = if ($evaluated -gt 0) { [math]::Round(($blockedLike / $evaluated), 3) } else { 0.0 }
    $direction = if ($rate -ge 0.35) { "elevated" } elseif ($rate -ge 0.15) { "watch" } else { "stable" }

    return [pscustomobject]@{
        evaluated = $evaluated
        blocked_like = $blockedLike
        rate = $rate
        direction = $direction
    }
}

function Build-ExecutionSummaries {
    $events = @()
    if (Test-Path -Path $eventStreamAbs) {
        $events = @(
            Get-Content -Path $eventStreamAbs |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object {
                try { $_ | ConvertFrom-Json }
                catch { $null }
            } |
            Where-Object {
                $null -ne $_ -and
                $_.PSObject.Properties["correlation"] -and
                $_.correlation -and
                $_.correlation.PSObject.Properties["trace_id"] -and
                $_.correlation.PSObject.Properties["execution_id"] -and
                -not [string]::IsNullOrWhiteSpace([string]$_.correlation.trace_id) -and
                -not [string]::IsNullOrWhiteSpace([string]$_.correlation.execution_id)
            }
        )
    }

    $correlationLinks = @()
    if (Test-Path -Path $correlationLogAbs) {
        $correlationLinks = @(
            Get-Content -Path $correlationLogAbs |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object {
                try { $_ | ConvertFrom-Json }
                catch { $null }
            } |
            Where-Object {
                $null -ne $_ -and
                $_.PSObject.Properties["trace_id"] -and
                $_.PSObject.Properties["execution_id"] -and
                $_.PSObject.Properties["artifact_path"]
            }
        )
    }

    $groups = @{}
    foreach ($evt in $events) {
        $key = "{0}|{1}" -f ([string]$evt.correlation.trace_id), ([string]$evt.correlation.execution_id)
        if (-not $groups.ContainsKey($key)) {
            $groups[$key] = @()
        }
        $groups[$key] += $evt
    }

    $summaries = @()
    foreach ($key in $groups.Keys) {
        $groupEvents = @($groups[$key] | Sort-Object -Property occurred_at)
        if (@($groupEvents).Count -eq 0) { continue }

        $first = $groupEvents[0]
        $traceIdValue = [string]$first.correlation.trace_id
        $executionIdValue = [string]$first.correlation.execution_id
        $sourceDomainValue = ""
        $sourceContextValue = ""
        foreach ($evtWithDomain in @($groupEvents)) {
            if ($evtWithDomain.PSObject.Properties["correlation"] -and $evtWithDomain.correlation -and $evtWithDomain.correlation.PSObject.Properties["source_domain"] -and -not [string]::IsNullOrWhiteSpace([string]$evtWithDomain.correlation.source_domain)) {
                $sourceDomainValue = [string]$evtWithDomain.correlation.source_domain
            }
            if ($evtWithDomain.PSObject.Properties["correlation"] -and $evtWithDomain.correlation -and $evtWithDomain.correlation.PSObject.Properties["source_context"] -and -not [string]::IsNullOrWhiteSpace([string]$evtWithDomain.correlation.source_context)) {
                $sourceContextValue = [string]$evtWithDomain.correlation.source_context
            }
            if (-not [string]::IsNullOrWhiteSpace($sourceDomainValue) -and -not [string]::IsNullOrWhiteSpace($sourceContextValue)) {
                break
            }
        }

        $retries = [int]@($groupEvents | Where-Object { [string]$_.event_type -eq "execution.retry_scheduled" }).Count
        $fallbacks = [int]@($groupEvents | Where-Object { [string]$_.event_type -eq "execution.fallback_applied" }).Count
        $recovered = [bool](@($groupEvents | Where-Object { [string]$_.event_type -eq "execution.recovered" }).Count -gt 0)
        $driftEvents = [int]@($groupEvents | Where-Object { [string]$_.event_type -eq "execution.drift_detected" }).Count
        $cancelled = [int]@($groupEvents | Where-Object { [string]$_.event_type -eq "execution.cancelled" }).Count
        $pausedEvents = [int]@($groupEvents | Where-Object { [string]$_.event_type -eq "execution.paused_pending_inquiry" }).Count
        $resumedEvents = [int]@($groupEvents | Where-Object { [string]$_.event_type -eq "execution.resumed_after_inquiry" }).Count
        $inquiryDeferrals = [int]@($groupEvents | Where-Object { [string]$_.event_type -eq "execution.deferred_for_operator_clarification" }).Count
        $inquiryTimeoutCancellations = [int]@($groupEvents | Where-Object { [string]$_.event_type -eq "execution.cancelled_pending_inquiry_timeout" }).Count
        $guardrailBlocks = [int]@($groupEvents | Where-Object { [string]$_.event_type -eq "execution.guardrail_blocked" }).Count

        $finalOutcome = "in_progress"
        if ($inquiryTimeoutCancellations -gt 0) {
            $finalOutcome = "cancelled_pending_inquiry_timeout"
        }
        elseif (@($groupEvents | Where-Object { [string]$_.event_type -eq "execution.cancelled" }).Count -gt 0) {
            $finalOutcome = "cancelled"
        }
        elseif (@($groupEvents | Where-Object { [string]$_.event_type -eq "execution.guardrail_blocked" }).Count -gt 0) {
            $finalOutcome = "guardrail_blocked"
        }
        elseif (@($groupEvents | Where-Object { [string]$_.event_type -eq "execution.failed" }).Count -gt 0) {
            $finalOutcome = "failed"
        }
        elseif (@($groupEvents | Where-Object { [string]$_.event_type -eq "execution.succeeded" }).Count -gt 0) {
            $finalOutcome = "succeeded"
        }
        elseif ($resumedEvents -gt 0) {
            $finalOutcome = "resumed_after_inquiry"
        }
        elseif ($inquiryDeferrals -gt 0) {
            $finalOutcome = "deferred_for_operator_clarification"
        }
        elseif ($pausedEvents -gt 0) {
            $finalOutcome = "paused_pending_inquiry"
        }

        $inquiryState = "none"
        if ($inquiryTimeoutCancellations -gt 0) {
            $inquiryState = "cancelled_pending_inquiry_timeout"
        }
        elseif ($resumedEvents -gt 0) {
            $inquiryState = "resumed_after_inquiry"
        }
        elseif ($inquiryDeferrals -gt 0) {
            $inquiryState = "deferred_for_operator_clarification"
        }
        elseif ($pausedEvents -gt 0) {
            $inquiryState = "paused_pending_inquiry"
        }

        $reliabilitySignal = Get-ReliabilitySignal -FinalOutcome $finalOutcome -Retries $retries -Fallbacks $fallbacks -DriftEvents $driftEvents -Recovered $recovered
        $recommendedAttention = Get-RecommendedAttention -ReliabilitySignal $reliabilitySignal
        $reliabilityScore = Get-ExecutionReliabilityScore -ReliabilitySignal $reliabilitySignal -Retries $retries -Fallbacks $fallbacks -DriftEvents $driftEvents -GuardrailBlocks $guardrailBlocks -PausedEvents $pausedEvents -InquiryDeferrals $inquiryDeferrals -InquiryTimeoutCancellations $inquiryTimeoutCancellations

        $artifactFromEvents = @(
            $groupEvents |
            ForEach-Object {
                if ($_.PSObject.Properties["artifact_links"] -and $_.artifact_links) { @($_.artifact_links) } else { @() }
            }
        )
        $artifactFromCorrelationLog = @(
            $correlationLinks |
            Where-Object { [string]$_.trace_id -eq $traceIdValue -and [string]$_.execution_id -eq $executionIdValue } |
            ForEach-Object { [string]$_.artifact_path }
        )
        $artifactLinks = @($artifactFromEvents + $artifactFromCorrelationLog | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)

        $summaries += [pscustomobject]@{
            trace_id = $traceIdValue
            execution_id = $executionIdValue
            source_domain = $sourceDomainValue
            source_context = $sourceContextValue
            final_outcome = $finalOutcome
            retries = $retries
            fallbacks = $fallbacks
            recovered = $recovered
            drift_events = $driftEvents
            paused_events = $pausedEvents
            resumed_events = $resumedEvents
            inquiry_deferrals = $inquiryDeferrals
            inquiry_timeout_cancellations = $inquiryTimeoutCancellations
            inquiry_state = $inquiryState
            cancelled = $cancelled
            guardrail_blocks = $guardrailBlocks
            reliability_signal = $reliabilitySignal
            engine_reliability_score = $reliabilityScore
            recommended_attention = $recommendedAttention
            event_count = [int]@($groupEvents).Count
            artifact_links = $artifactLinks
            last_event_at = [string]$groupEvents[-1].occurred_at
        }
    }

    return @(
        $summaries | Sort-Object -Property @(
            @{ Expression = { [string]$_.last_event_at }; Descending = $true },
            @{ Expression = { [string]$_.trace_id }; Descending = $false },
            @{ Expression = { [string]$_.execution_id }; Descending = $false }
        )
    )
}

function Publish-EventInternal {
    param(
        [Parameter(Mandatory = $true)][string]$Type,
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)]$Correlation,
        [Parameter(Mandatory = $true)]$Payload,
        [Parameter(Mandatory = $true)]$Reasons,
        [string[]]$Artifacts = @()
    )

    if (@($schema.outbound_event_types) -notcontains $Type) {
        throw "Unsupported outbound event type: $Type"
    }

    $event = [pscustomobject]@{
        event_id = $Id
        event_type = $Type
        occurred_at = (Get-Date).ToUniversalTime().ToString("o")
        producer = [pscustomobject]@{
            system = "TOD"
            component = "bus_adapter"
            role = "execution_runtime"
        }
        correlation = $Correlation
        reasons = @($Reasons)
        payload = $Payload
    }

    if (@($Artifacts).Count -gt 0) {
        $event | Add-Member -NotePropertyName artifact_links -NotePropertyValue @($Artifacts) -Force
    }

    if (-not (Test-MandatoryCorrelation -Event $event -Schema $schema)) {
        throw "publish-event failed mandatory correlation validation"
    }

    Append-JsonLine -Path $eventStreamAbs -Object $event

    foreach ($artifactPath in @($Artifacts)) {
        if (-not [string]::IsNullOrWhiteSpace($artifactPath)) {
            Append-JsonLine -Path $correlationLogAbs -Object ([pscustomobject]@{
                    linked_at = (Get-Date).ToUniversalTime().ToString("o")
                    event_id = $event.event_id
                    trace_id = [string]$event.correlation.trace_id
                    execution_id = [string]$event.correlation.execution_id
                    artifact_path = [string]$artifactPath
                })
        }
    }

    $state.counters.outbound_published = [int]$state.counters.outbound_published + 1
    Save-AdapterState -State $state -StateFile $stateAbs
    return $event
}

function Write-StatusArtifact {
    param(
        [string]$LastAction = "",
        [string]$LastStatus = "",
        [string]$LastEventId = ""
    )

    $streamExists = Test-Path -Path $eventStreamAbs
    $streamCount = 0
    if ($streamExists) {
        $streamCount = @((Get-Content -Path $eventStreamAbs | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })).Count
    }

    $statusReliabilitySignal = "stable"
    if ([int]$state.counters.failed_runtime -gt 0 -or [int]$state.counters.cancelled_pending_inquiry_timeout -gt 0 -or [int]$state.counters.guardrail_blocked -gt 0) {
        $statusReliabilitySignal = "critical"
    }
    elseif ([int]$state.counters.drift_detected -gt 0 -or [int]$state.counters.fallback_applied -gt 0) {
        $statusReliabilitySignal = "warning"
    }
    elseif ([int]$state.counters.retries_scheduled -gt 0 -or [int]$state.counters.recoveries -gt 0) {
        $statusReliabilitySignal = "elevated"
    }

    $statusObj = [pscustomobject]@{
        generated_at = (Get-Date).ToUniversalTime().ToString("o")
        source = "tod-bus-adapter-v1"
        type = "bus_adapter_status"
        last_action = $LastAction
        last_status = $LastStatus
        last_event_id = $LastEventId
        counters = $state.counters
        accepted_execution_ids_count = [int]@($state.accepted_execution_ids).Count
        stream_event_count = [int]$streamCount
        schema = [string]$schema.schema_name
        inbound_event_types = @($schema.inbound_event_types)
        outbound_event_types = @($schema.outbound_event_types)
        lifecycle_feedback = [pscustomobject]@{
            retries_scheduled = [int]$state.counters.retries_scheduled
            recoveries = [int]$state.counters.recoveries
            drift_detected = [int]$state.counters.drift_detected
            fallback_applied = [int]$state.counters.fallback_applied
            cancelled = [int]$state.counters.cancelled
            paused_pending_inquiry = [int]$state.counters.paused_pending_inquiry
            resumed_after_inquiry = [int]$state.counters.resumed_after_inquiry
            deferred_for_operator_clarification = [int]$state.counters.deferred_for_operator_clarification
            cancelled_pending_inquiry_timeout = [int]$state.counters.cancelled_pending_inquiry_timeout
            guardrail_blocked = [int]$state.counters.guardrail_blocked
            failed_runtime = [int]$state.counters.failed_runtime
            successful_runtime = [int]$state.counters.successful_runtime
        }
        policy_metrics = [pscustomobject]@{
            allowed = [int]$state.counters.domain_policy_allowed
            blocked = [int]$state.counters.domain_policy_blocked
            deferred = [int]$state.counters.domain_policy_deferred
            dry_run_only = [int]$state.counters.domain_policy_dry_run_only
        }
        reliability_metrics = [pscustomobject]@{
            engine_reliability_score = Get-ExecutionReliabilityScore -ReliabilitySignal $statusReliabilitySignal -Retries ([int]$state.counters.retries_scheduled) -Fallbacks ([int]$state.counters.fallback_applied) -DriftEvents ([int]$state.counters.drift_detected) -GuardrailBlocks ([int]$state.counters.guardrail_blocked) -PausedEvents ([int]$state.counters.paused_pending_inquiry) -InquiryDeferrals ([int]$state.counters.deferred_for_operator_clarification) -InquiryTimeoutCancellations ([int]$state.counters.cancelled_pending_inquiry_timeout)
            guardrail_trend = Get-GuardrailTrend -Accepted ([int]$state.counters.domain_policy_allowed) -Blocked ([int]$state.counters.domain_policy_blocked) -Deferred ([int]$state.counters.domain_policy_deferred) -DryRunOnly ([int]$state.counters.domain_policy_dry_run_only)
            drift_recovery_ready = ([int]$state.counters.recoveries -ge [int]$state.counters.drift_detected)
        }
        autonomy_boundary = [pscustomobject]@{
            tod_scope = "execution_runtime_only"
            external_owners = @("mim_reasoning", "perception_normalization", "operator_clarification")
            policy_path = $ExecutionDomainPolicyPath
            perception_schema_path = $PerceptionContextSchemaPath
            enforced = $true
        }
        inquiry_control = [pscustomobject]@{
            pending_timeout_seconds = Get-InquiryPendingTimeoutSeconds -Config $todConfig
        }
    }

    Ensure-ParentDir -FilePath $busStatusAbs
    $statusObj | ConvertTo-Json -Depth 20 | Set-Content -Path $busStatusAbs
}

$eventStreamAbs = Get-LocalPath -PathValue $EventStreamPath
$inboxAbs = Get-LocalPath -PathValue $InboundInboxPath
$processedAbs = Get-LocalPath -PathValue $ProcessedInboxPath
$stateAbs = Get-LocalPath -PathValue $AdapterStatePath
$consumerLogAbs = Get-LocalPath -PathValue $ConsumerLogPath
$correlationLogAbs = Get-LocalPath -PathValue $CorrelationLogPath
$schemaAbs = Get-LocalPath -PathValue $SchemaPath
$busStatusAbs = Get-LocalPath -PathValue $BusStatusPath
$executionSummaryAbs = Get-LocalPath -PathValue $ExecutionSummaryPath
$executionSummaryIndexAbs = Get-LocalPath -PathValue $ExecutionSummaryIndexPath
$executionSummaryContractAbs = Get-LocalPath -PathValue $ExecutionSummaryContractPath
$executionDomainPolicyAbs = Get-LocalPath -PathValue $ExecutionDomainPolicyPath
$perceptionContextSchemaAbs = Get-LocalPath -PathValue $PerceptionContextSchemaPath
$todScriptAbs = Get-LocalPath -PathValue $TodScriptPath
$todConfigAbs = Get-LocalPath -PathValue $TodConfigPath

$schema = Get-Schema -SchemaFile $schemaAbs
$executionDomainPolicy = Get-ExecutionDomainPolicy -PolicyFile $executionDomainPolicyAbs
$perceptionContextSchema = Get-PerceptionContextSchema -SchemaFile $perceptionContextSchemaAbs
$todConfig = Get-TodConfigDocument -ConfigFile $todConfigAbs
$state = Get-AdapterState -StateFile $stateAbs

switch ($Action) {
    "publish-event" {
        if ([string]::IsNullOrWhiteSpace($EventType)) {
            throw "-EventType is required for publish-event"
        }
        if (@($schema.outbound_event_types) -notcontains $EventType) {
            throw "Unsupported outbound event type: $EventType"
        }
        if ([string]::IsNullOrWhiteSpace($EventId) -or [string]::IsNullOrWhiteSpace($TraceId) -or [string]::IsNullOrWhiteSpace($ExecutionId)) {
            throw "publish-event requires -EventId, -TraceId, and -ExecutionId"
        }

        $payloadObject = [pscustomobject]@{}
        if (-not [string]::IsNullOrWhiteSpace($EventJson)) {
            try {
                $payloadObject = $EventJson | ConvertFrom-Json
            }
            catch {
                throw "publish-event received malformed -EventJson payload"
            }
        }

        $reason = New-Reason -Code "execution_started" -Severity "info" -Category "execution" -Message "Outbound execution event published."
        $event = Publish-EventInternal -Type $EventType -Id $EventId -Correlation (New-CorrelationObject) -Payload $payloadObject -Reasons @($reason) -Artifacts @($ArtifactPaths)
        Write-StatusArtifact -LastAction "publish-event" -LastStatus "published" -LastEventId ([string]$EventId)

        [pscustomobject]@{
            ok = $true
            action = "publish-event"
            status = "published"
            event = $event
            stream_path = $eventStreamAbs
        } | ConvertTo-Json -Depth 20 | Write-Output
        break
    }
    "consume-event" {
        $event = Get-ParsedEvent -RawJson $EventJson -FilePath $EventFile
        if ($null -eq $event) {
            $state.counters.inbound_rejected = [int]$state.counters.inbound_rejected + 1
            Save-AdapterState -State $state -StateFile $stateAbs
            Append-JsonLine -Path $consumerLogAbs -Object ([pscustomobject]@{
                    logged_at = (Get-Date).ToUniversalTime().ToString("o")
                    status = "rejected_malformed"
                    reason = "request_malformed"
                    input_file = if ([string]::IsNullOrWhiteSpace($EventFile)) { "" } else { $EventFile }
                })
            Write-StatusArtifact -LastAction "consume-event" -LastStatus "rejected_malformed"
            [pscustomobject]@{ ok = $false; action = "consume-event"; status = "rejected_malformed" } | ConvertTo-Json -Depth 10 | Write-Output
            break
        }

        if (-not (Test-MandatoryCorrelation -Event $event -Schema $schema)) {
            $malformedEventId = ""
            if ($event.PSObject.Properties["event_id"]) {
                $malformedEventId = [string]$event.event_id
            }
            $state.counters.inbound_rejected = [int]$state.counters.inbound_rejected + 1
            Save-AdapterState -State $state -StateFile $stateAbs
            Append-JsonLine -Path $consumerLogAbs -Object ([pscustomobject]@{
                    logged_at = (Get-Date).ToUniversalTime().ToString("o")
                    status = "rejected_malformed"
                    reason = "request_malformed"
                    event_id = $malformedEventId
                })
            Write-StatusArtifact -LastAction "consume-event" -LastStatus "rejected_malformed" -LastEventId $malformedEventId
            [pscustomobject]@{ ok = $false; action = "consume-event"; status = "rejected_malformed" } | ConvertTo-Json -Depth 10 | Write-Output
            break
        }

        $eventIdValue = [string]$event.event_id
        if (@($state.processed_event_ids) -contains $eventIdValue) {
            Append-JsonLine -Path $consumerLogAbs -Object ([pscustomobject]@{
                    logged_at = (Get-Date).ToUniversalTime().ToString("o")
                    status = "duplicate_ignored"
                    reason = "request_duplicate_ignored"
                    event_id = $eventIdValue
                    event_type = [string]$event.event_type
                })
            Write-StatusArtifact -LastAction "consume-event" -LastStatus "duplicate_ignored" -LastEventId $eventIdValue
            [pscustomobject]@{ ok = $true; action = "consume-event"; status = "duplicate_ignored"; event_id = $eventIdValue } | ConvertTo-Json -Depth 10 | Write-Output
            break
        }

        $inboundType = [string]$event.event_type
        if (@($schema.inbound_event_types) -contains $inboundType) {
            $executionIdValue = Get-ExecutionIdFromEvent -Event $event

            if ($inboundType -eq "execution.cancel_requested") {
                $isAccepted = (@($state.accepted_execution_ids) -contains $executionIdValue)
                $isPaused = (@($state.paused_execution_ids) -contains $executionIdValue)
                if ((-not $isAccepted) -and (-not $isPaused)) {
                    $state.counters.inbound_ignored = [int]$state.counters.inbound_ignored + 1
                    Save-AdapterState -State $state -StateFile $stateAbs
                    Append-JsonLine -Path $consumerLogAbs -Object ([pscustomobject]@{
                            logged_at = (Get-Date).ToUniversalTime().ToString("o")
                            status = "ignored_out_of_order"
                            reason = "request_out_of_order_ignored"
                            event_id = $eventIdValue
                            event_type = $inboundType
                            execution_id = $executionIdValue
                        })
                    Write-StatusArtifact -LastAction "consume-event" -LastStatus "ignored_out_of_order" -LastEventId $eventIdValue
                    [pscustomobject]@{ ok = $true; action = "consume-event"; status = "ignored_out_of_order"; event_id = $eventIdValue; event_type = $inboundType } | ConvertTo-Json -Depth 10 | Write-Output
                    break
                }

                $corrCancelled = Build-CorrelationFromEvent -Event $event
                $isInquiryTimeout = $false
                if ($event.PSObject.Properties["payload"] -and $event.payload) {
                    if ($event.payload.PSObject.Properties["cancel_reason"] -and [string]$event.payload.cancel_reason -eq "pending_inquiry_timeout") {
                        $isInquiryTimeout = $true
                    }
                    if ($event.payload.PSObject.Properties["reason_code"] -and [string]$event.payload.reason_code -eq "pending_inquiry_timeout") {
                        $isInquiryTimeout = $true
                    }
                    if ($event.payload.PSObject.Properties["pending_inquiry_timeout"] -and [bool]$event.payload.pending_inquiry_timeout) {
                        $isInquiryTimeout = $true
                    }
                }
                $cancelEventId = "evt-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 12))
                if ($isInquiryTimeout) {
                    $cancelReason = New-Reason -Code "inquiry_timeout_cancelled" -Severity "warning" -Category "execution" -Message "Execution cancelled after pending inquiry timeout." -Evidence ([pscustomobject]@{ execution_id = $executionIdValue })
                    $null = Publish-EventInternal -Type "execution.cancelled_pending_inquiry_timeout" -Id $cancelEventId -Correlation $corrCancelled -Payload ([pscustomobject]@{ state = "cancelled"; cause = "pending_inquiry_timeout" }) -Reasons @($cancelReason) -Artifacts @()
                    $state.counters.cancelled_pending_inquiry_timeout = [int]$state.counters.cancelled_pending_inquiry_timeout + 1
                }
                else {
                    $cancelReason = New-Reason -Code "execution_cancelled" -Severity "warning" -Category "execution" -Message "Cancellation request accepted for active execution." -Evidence ([pscustomobject]@{ execution_id = $executionIdValue })
                    $null = Publish-EventInternal -Type "execution.cancelled" -Id $cancelEventId -Correlation $corrCancelled -Payload ([pscustomobject]@{ state = "cancelled"; cause = "cancel_requested" }) -Reasons @($cancelReason) -Artifacts @()
                }

                $state.processed_event_ids = @($state.processed_event_ids) + @($eventIdValue)
                $state.accepted_execution_ids = @($state.accepted_execution_ids | Where-Object { [string]$_ -ne $executionIdValue })
                $state.paused_execution_ids = @($state.paused_execution_ids | Where-Object { [string]$_ -ne $executionIdValue })
                $state.counters.inbound_accepted = [int]$state.counters.inbound_accepted + 1
                $state.counters.cancelled = [int]$state.counters.cancelled + 1
                Save-AdapterState -State $state -StateFile $stateAbs
                $cancelStatus = "accepted_cancelled"
                if ($isInquiryTimeout) {
                    $cancelStatus = "accepted_cancelled_pending_inquiry_timeout"
                }
                Append-JsonLine -Path $consumerLogAbs -Object ([pscustomobject]@{
                        logged_at = (Get-Date).ToUniversalTime().ToString("o")
                        status = $cancelStatus
                        reason = "request_validated"
                        event_id = $eventIdValue
                        event_type = $inboundType
                        trace_id = [string]$event.correlation.trace_id
                        execution_id = $executionIdValue
                    })
                Write-StatusArtifact -LastAction "consume-event" -LastStatus $cancelStatus -LastEventId $eventIdValue
                [pscustomobject]@{ ok = $true; action = "consume-event"; status = $cancelStatus; event_id = $eventIdValue; event_type = $inboundType } | ConvertTo-Json -Depth 10 | Write-Output
                break
            }

            if ($inboundType -eq "execution.pause_requested") {
                $isAccepted = (@($state.accepted_execution_ids) -contains $executionIdValue)
                $isPaused = (@($state.paused_execution_ids) -contains $executionIdValue)
                if ((-not $isAccepted) -and (-not $isPaused)) {
                    $state.counters.inbound_ignored = [int]$state.counters.inbound_ignored + 1
                    Save-AdapterState -State $state -StateFile $stateAbs
                    Append-JsonLine -Path $consumerLogAbs -Object ([pscustomobject]@{
                            logged_at = (Get-Date).ToUniversalTime().ToString("o")
                            status = "ignored_out_of_order"
                            reason = "request_out_of_order_ignored"
                            event_id = $eventIdValue
                            event_type = $inboundType
                            execution_id = $executionIdValue
                        })
                    Write-StatusArtifact -LastAction "consume-event" -LastStatus "ignored_out_of_order" -LastEventId $eventIdValue
                    [pscustomobject]@{ ok = $true; action = "consume-event"; status = "ignored_out_of_order"; event_id = $eventIdValue; event_type = $inboundType } | ConvertTo-Json -Depth 10 | Write-Output
                    break
                }

                $deferForClarification = $false
                if ($event.PSObject.Properties["payload"] -and $event.payload -and $event.payload.PSObject.Properties["defer_for_operator_clarification"]) {
                    $deferForClarification = [bool]$event.payload.defer_for_operator_clarification
                }

                $corrPaused = Build-CorrelationFromEvent -Event $event
                $pauseEventId = "evt-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 12))
                if ($deferForClarification) {
                    $deferReason = New-Reason -Code "inquiry_deferred_for_operator_clarification" -Severity "warning" -Category "execution" -Message "Execution deferred for operator clarification." -Evidence ([pscustomobject]@{ execution_id = $executionIdValue })
                    $null = Publish-EventInternal -Type "execution.deferred_for_operator_clarification" -Id $pauseEventId -Correlation $corrPaused -Payload ([pscustomobject]@{ state = "deferred_for_operator_clarification"; cause = "inquiry_pending" }) -Reasons @($deferReason) -Artifacts @()
                    $state.counters.deferred_for_operator_clarification = [int]$state.counters.deferred_for_operator_clarification + 1
                }
                else {
                    $pauseReason = New-Reason -Code "inquiry_pause_requested" -Severity "warning" -Category "execution" -Message "Execution paused pending inquiry resolution." -Evidence ([pscustomobject]@{ execution_id = $executionIdValue })
                    $null = Publish-EventInternal -Type "execution.paused_pending_inquiry" -Id $pauseEventId -Correlation $corrPaused -Payload ([pscustomobject]@{ state = "paused_pending_inquiry"; cause = "pause_requested" }) -Reasons @($pauseReason) -Artifacts @()
                    $state.counters.paused_pending_inquiry = [int]$state.counters.paused_pending_inquiry + 1
                }

                $state.processed_event_ids = @($state.processed_event_ids) + @($eventIdValue)
                $state.accepted_execution_ids = @($state.accepted_execution_ids | Where-Object { [string]$_ -ne $executionIdValue })
                if (@($state.paused_execution_ids) -notcontains $executionIdValue) {
                    $state.paused_execution_ids = @($state.paused_execution_ids) + @($executionIdValue)
                }
                $state.counters.inbound_accepted = [int]$state.counters.inbound_accepted + 1
                Save-AdapterState -State $state -StateFile $stateAbs

                $pauseStatus = if ($deferForClarification) { "deferred_for_operator_clarification" } else { "paused_pending_inquiry" }
                Append-JsonLine -Path $consumerLogAbs -Object ([pscustomobject]@{
                        logged_at = (Get-Date).ToUniversalTime().ToString("o")
                        status = $pauseStatus
                        reason = "request_validated"
                        event_id = $eventIdValue
                        event_type = $inboundType
                        trace_id = [string]$event.correlation.trace_id
                        execution_id = $executionIdValue
                    })
                Write-StatusArtifact -LastAction "consume-event" -LastStatus $pauseStatus -LastEventId $eventIdValue
                [pscustomobject]@{ ok = $true; action = "consume-event"; status = $pauseStatus; event_id = $eventIdValue; event_type = $inboundType } | ConvertTo-Json -Depth 10 | Write-Output
                break
            }

            if ($inboundType -eq "execution.resume_requested") {
                if (@($state.paused_execution_ids) -notcontains $executionIdValue) {
                    $state.processed_event_ids = @($state.processed_event_ids) + @($eventIdValue)
                    $state.counters.inbound_rejected = [int]$state.counters.inbound_rejected + 1
                    Save-AdapterState -State $state -StateFile $stateAbs
                    Append-JsonLine -Path $consumerLogAbs -Object ([pscustomobject]@{
                            logged_at = (Get-Date).ToUniversalTime().ToString("o")
                            status = "rejected_invalid_resume"
                            reason = "inquiry_resume_invalid_state"
                            event_id = $eventIdValue
                            event_type = $inboundType
                            execution_id = $executionIdValue
                        })
                    Write-StatusArtifact -LastAction "consume-event" -LastStatus "rejected_invalid_resume" -LastEventId $eventIdValue
                    [pscustomobject]@{ ok = $false; action = "consume-event"; status = "rejected_invalid_resume"; event_id = $eventIdValue; event_type = $inboundType } | ConvertTo-Json -Depth 10 | Write-Output
                    break
                }

                $corrResumed = Build-CorrelationFromEvent -Event $event
                $resumeEventId = "evt-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 12))
                $resumeReason = New-Reason -Code "inquiry_resumed" -Severity "info" -Category "execution" -Message "Execution resumed after inquiry resolution." -Evidence ([pscustomobject]@{ execution_id = $executionIdValue })
                $null = Publish-EventInternal -Type "execution.resumed_after_inquiry" -Id $resumeEventId -Correlation $corrResumed -Payload ([pscustomobject]@{ state = "resumed_after_inquiry"; cause = "resume_requested" }) -Reasons @($resumeReason) -Artifacts @()

                $state.processed_event_ids = @($state.processed_event_ids) + @($eventIdValue)
                $state.paused_execution_ids = @($state.paused_execution_ids | Where-Object { [string]$_ -ne $executionIdValue })
                if (@($state.accepted_execution_ids) -notcontains $executionIdValue) {
                    $state.accepted_execution_ids = @($state.accepted_execution_ids) + @($executionIdValue)
                }
                $state.counters.inbound_accepted = [int]$state.counters.inbound_accepted + 1
                $state.counters.resumed_after_inquiry = [int]$state.counters.resumed_after_inquiry + 1
                Save-AdapterState -State $state -StateFile $stateAbs
                Append-JsonLine -Path $consumerLogAbs -Object ([pscustomobject]@{
                        logged_at = (Get-Date).ToUniversalTime().ToString("o")
                        status = "resumed_after_inquiry"
                        reason = "request_validated"
                        event_id = $eventIdValue
                        event_type = $inboundType
                        trace_id = [string]$event.correlation.trace_id
                        execution_id = $executionIdValue
                    })
                Write-StatusArtifact -LastAction "consume-event" -LastStatus "resumed_after_inquiry" -LastEventId $eventIdValue
                [pscustomobject]@{ ok = $true; action = "consume-event"; status = "resumed_after_inquiry"; event_id = $eventIdValue; event_type = $inboundType } | ConvertTo-Json -Depth 10 | Write-Output
                break
            }

            if ($inboundType -eq "execution.clarification_received") {
                if (@($state.paused_execution_ids) -notcontains $executionIdValue) {
                    $state.counters.inbound_ignored = [int]$state.counters.inbound_ignored + 1
                    Save-AdapterState -State $state -StateFile $stateAbs
                    Append-JsonLine -Path $consumerLogAbs -Object ([pscustomobject]@{
                            logged_at = (Get-Date).ToUniversalTime().ToString("o")
                            status = "ignored_out_of_order"
                            reason = "request_out_of_order_ignored"
                            event_id = $eventIdValue
                            event_type = $inboundType
                            execution_id = $executionIdValue
                        })
                    Write-StatusArtifact -LastAction "consume-event" -LastStatus "ignored_out_of_order" -LastEventId $eventIdValue
                    [pscustomobject]@{ ok = $true; action = "consume-event"; status = "ignored_out_of_order"; event_id = $eventIdValue; event_type = $inboundType } | ConvertTo-Json -Depth 10 | Write-Output
                    break
                }

                $corrClarified = Build-CorrelationFromEvent -Event $event
                $clarificationEventId = "evt-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 12))
                $clarificationReason = New-Reason -Code "clarification_received" -Severity "info" -Category "execution" -Message "Clarification received while execution remains paused/deferred." -Evidence ([pscustomobject]@{ execution_id = $executionIdValue })
                $null = Publish-EventInternal -Type "execution.deferred_for_operator_clarification" -Id $clarificationEventId -Correlation $corrClarified -Payload ([pscustomobject]@{ state = "deferred_for_operator_clarification"; cause = "clarification_received" }) -Reasons @($clarificationReason) -Artifacts @()

                $state.processed_event_ids = @($state.processed_event_ids) + @($eventIdValue)
                $state.counters.inbound_accepted = [int]$state.counters.inbound_accepted + 1
                $state.counters.deferred_for_operator_clarification = [int]$state.counters.deferred_for_operator_clarification + 1
                Save-AdapterState -State $state -StateFile $stateAbs
                Append-JsonLine -Path $consumerLogAbs -Object ([pscustomobject]@{
                        logged_at = (Get-Date).ToUniversalTime().ToString("o")
                        status = "deferred_for_operator_clarification"
                        reason = "request_validated"
                        event_id = $eventIdValue
                        event_type = $inboundType
                        trace_id = [string]$event.correlation.trace_id
                        execution_id = $executionIdValue
                    })
                Write-StatusArtifact -LastAction "consume-event" -LastStatus "deferred_for_operator_clarification" -LastEventId $eventIdValue
                [pscustomobject]@{ ok = $true; action = "consume-event"; status = "deferred_for_operator_clarification"; event_id = $eventIdValue; event_type = $inboundType } | ConvertTo-Json -Depth 10 | Write-Output
                break
            }

            if ($inboundType -eq "execution.priority_changed") {
                if (@($state.accepted_execution_ids) -notcontains $executionIdValue) {
                    $state.counters.inbound_ignored = [int]$state.counters.inbound_ignored + 1
                    Save-AdapterState -State $state -StateFile $stateAbs
                    Append-JsonLine -Path $consumerLogAbs -Object ([pscustomobject]@{
                            logged_at = (Get-Date).ToUniversalTime().ToString("o")
                            status = "ignored_out_of_order"
                            reason = "request_out_of_order_ignored"
                            event_id = $eventIdValue
                            event_type = $inboundType
                            execution_id = $executionIdValue
                        })
                    Write-StatusArtifact -LastAction "consume-event" -LastStatus "ignored_out_of_order" -LastEventId $eventIdValue
                    [pscustomobject]@{ ok = $true; action = "consume-event"; status = "ignored_out_of_order"; event_id = $eventIdValue; event_type = $inboundType } | ConvertTo-Json -Depth 10 | Write-Output
                    break
                }

                $state.processed_event_ids = @($state.processed_event_ids) + @($eventIdValue)
                $state.counters.inbound_accepted = [int]$state.counters.inbound_accepted + 1
                Save-AdapterState -State $state -StateFile $stateAbs
                Append-JsonLine -Path $consumerLogAbs -Object ([pscustomobject]@{
                        logged_at = (Get-Date).ToUniversalTime().ToString("o")
                        status = "accepted_control_signal"
                        reason = "request_validated"
                        event_id = $eventIdValue
                        event_type = $inboundType
                        trace_id = [string]$event.correlation.trace_id
                        execution_id = $executionIdValue
                    })
                Write-StatusArtifact -LastAction "consume-event" -LastStatus "accepted_control_signal" -LastEventId $eventIdValue
                [pscustomobject]@{ ok = $true; action = "consume-event"; status = "accepted_control_signal"; event_id = $eventIdValue; event_type = $inboundType } | ConvertTo-Json -Depth 10 | Write-Output
                break
            }

            $runtimeAction = ""
            if ($event.PSObject.Properties["payload"] -and $event.payload -and $event.payload.PSObject.Properties["runtime_action"]) {
                $runtimeAction = [string]$event.payload.runtime_action
            }

            if ([string]::IsNullOrWhiteSpace($runtimeAction)) {
                $state.counters.inbound_rejected = [int]$state.counters.inbound_rejected + 1
                Save-AdapterState -State $state -StateFile $stateAbs
                Append-JsonLine -Path $consumerLogAbs -Object ([pscustomobject]@{
                        logged_at = (Get-Date).ToUniversalTime().ToString("o")
                        status = "rejected_malformed"
                        reason = "request_malformed"
                        event_id = $eventIdValue
                        event_type = $inboundType
                    })
                Write-StatusArtifact -LastAction "consume-event" -LastStatus "rejected_malformed" -LastEventId $eventIdValue
                [pscustomobject]@{ ok = $false; action = "consume-event"; status = "rejected_malformed"; event_id = $eventIdValue; event_type = $inboundType } | ConvertTo-Json -Depth 10 | Write-Output
                break
            }

            $sourceDomainValue = "legacy"
            if ($event.PSObject.Properties["correlation"] -and $event.correlation -and $event.correlation.PSObject.Properties["source_domain"] -and -not [string]::IsNullOrWhiteSpace([string]$event.correlation.source_domain)) {
                $sourceDomainValue = [string]$event.correlation.source_domain
            }

            $domainPolicy = Resolve-DomainPolicyDecision -Policy $executionDomainPolicy -SourceDomain $sourceDomainValue -RuntimeAction $runtimeAction
            $payloadForPolicy = $null
            if ($event.PSObject.Properties["payload"]) {
                $payloadForPolicy = $event.payload
            }
            $perceptionValidation = Test-PerceptionContextPayload -Payload $payloadForPolicy -Schema $perceptionContextSchema
            if ($perceptionValidation.has_context -and -not [bool]$perceptionValidation.valid) {
                $corrPerceptionInvalid = Build-CorrelationFromEvent -Event $event
                $perceptionBlockedId = "evt-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 12))
                $null = Publish-EventInternal -Type "execution.guardrail_blocked" -Id $perceptionBlockedId -Correlation $corrPerceptionInvalid -Payload ([pscustomobject]@{ runtime_action = $runtimeAction; decision = "blocked"; source_domain = $sourceDomainValue; perception_schema_path = $PerceptionContextSchemaPath }) -Reasons @(
                    New-Reason -Code $perceptionValidation.reason_code -Severity "warning" -Category "guardrail" -Message $perceptionValidation.message -Evidence ([pscustomobject]@{ runtime_action = $runtimeAction; source_domain = $sourceDomainValue })
                ) -Artifacts @()

                $state.processed_event_ids = @($state.processed_event_ids) + @($eventIdValue)
                $state.counters.inbound_rejected = [int]$state.counters.inbound_rejected + 1
                $state.counters.guardrail_blocked = [int]$state.counters.guardrail_blocked + 1
                $state.counters.domain_policy_blocked = [int]$state.counters.domain_policy_blocked + 1
                Save-AdapterState -State $state -StateFile $stateAbs
                Append-JsonLine -Path $consumerLogAbs -Object ([pscustomobject]@{
                        logged_at = (Get-Date).ToUniversalTime().ToString("o")
                        status = "rejected_guardrail"
                        reason = $perceptionValidation.reason_code
                        event_id = $eventIdValue
                        event_type = $inboundType
                        runtime_action = $runtimeAction
                    })
                Write-StatusArtifact -LastAction "consume-event" -LastStatus "rejected_guardrail" -LastEventId $eventIdValue
                [pscustomobject]@{ ok = $false; action = "consume-event"; status = "rejected_guardrail"; event_id = $eventIdValue; event_type = $inboundType } | ConvertTo-Json -Depth 10 | Write-Output
                break
            }

            $perceptionDecision = Resolve-PerceptionContextDecision -Policy $executionDomainPolicy -SourceDomain $sourceDomainValue -RuntimeAction $runtimeAction -Payload $payloadForPolicy
            $domainDecisionCode = ""
            $domainDecisionMessage = ""
            if ($null -ne $perceptionDecision) {
                $domainPolicy = [pscustomobject]@{
                    decision = [string]$perceptionDecision.decision
                    source_domain = $sourceDomainValue
                    matched_domain = $sourceDomainValue
                }
                $domainDecisionCode = [string]$perceptionDecision.reason_code
                $domainDecisionMessage = [string]$perceptionDecision.message
            }
            if ([string]$domainPolicy.decision -eq "unsupported_domain") {
                $state.processed_event_ids = @($state.processed_event_ids) + @($eventIdValue)
                $state.counters.inbound_ignored = [int]$state.counters.inbound_ignored + 1
                Save-AdapterState -State $state -StateFile $stateAbs
                Append-JsonLine -Path $consumerLogAbs -Object ([pscustomobject]@{
                        logged_at = (Get-Date).ToUniversalTime().ToString("o")
                        status = "ignored_unsupported_domain"
                        reason = "request_unsupported_domain_ignored"
                        event_id = $eventIdValue
                        event_type = $inboundType
                        runtime_action = $runtimeAction
                        source_domain = $sourceDomainValue
                    })
                Write-StatusArtifact -LastAction "consume-event" -LastStatus "ignored_unsupported_domain" -LastEventId $eventIdValue
                [pscustomobject]@{ ok = $true; action = "consume-event"; status = "ignored_unsupported_domain"; event_id = $eventIdValue; event_type = $inboundType; source_domain = $sourceDomainValue; runtime_action = $runtimeAction } | ConvertTo-Json -Depth 12 | Write-Output
                break
            }

            if ([string]$domainPolicy.decision -in @("blocked", "deferred")) {
                $corrDomainBlocked = Build-CorrelationFromEvent -Event $event
                $domainBlockedId = "evt-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 12))
                $reasonCode = if (-not [string]::IsNullOrWhiteSpace($domainDecisionCode)) { $domainDecisionCode } elseif ([string]$domainPolicy.decision -eq "deferred") { "domain_policy_deferred" } else { "domain_policy_blocked" }
                $reasonMessage = if (-not [string]::IsNullOrWhiteSpace($domainDecisionMessage)) { $domainDecisionMessage } elseif ([string]$domainPolicy.decision -eq "deferred") { "Runtime action deferred by cross-domain execution policy." } else { "Runtime action blocked by cross-domain execution policy." }
                $null = Publish-EventInternal -Type "execution.guardrail_blocked" -Id $domainBlockedId -Correlation $corrDomainBlocked -Payload ([pscustomobject]@{ runtime_action = $runtimeAction; decision = [string]$domainPolicy.decision; source_domain = [string]$domainPolicy.source_domain; policy_path = $ExecutionDomainPolicyPath }) -Reasons @(
                    New-Reason -Code $reasonCode -Severity "warning" -Category "guardrail" -Message $reasonMessage -Evidence ([pscustomobject]@{ runtime_action = $runtimeAction; source_domain = [string]$domainPolicy.source_domain; matched_domain = [string]$domainPolicy.matched_domain })
                ) -Artifacts @()

                $state.processed_event_ids = @($state.processed_event_ids) + @($eventIdValue)
                $state.counters.inbound_rejected = [int]$state.counters.inbound_rejected + 1
                $state.counters.guardrail_blocked = [int]$state.counters.guardrail_blocked + 1
                if ([string]$domainPolicy.decision -eq "deferred") {
                    $state.counters.domain_policy_deferred = [int]$state.counters.domain_policy_deferred + 1
                }
                else {
                    $state.counters.domain_policy_blocked = [int]$state.counters.domain_policy_blocked + 1
                }
                Save-AdapterState -State $state -StateFile $stateAbs
                Append-JsonLine -Path $consumerLogAbs -Object ([pscustomobject]@{
                        logged_at = (Get-Date).ToUniversalTime().ToString("o")
                        status = if ([string]$domainPolicy.decision -eq "deferred") { "deferred_domain_policy" } else { "rejected_domain_policy" }
                        reason = $reasonCode
                        event_id = $eventIdValue
                        event_type = $inboundType
                        runtime_action = $runtimeAction
                        source_domain = [string]$domainPolicy.source_domain
                    })
                if ([string]$domainPolicy.decision -eq "deferred") {
                    Write-StatusArtifact -LastAction "consume-event" -LastStatus "deferred_domain_policy" -LastEventId $eventIdValue
                    [pscustomobject]@{ ok = $true; action = "consume-event"; status = "deferred_domain_policy"; event_id = $eventIdValue; event_type = $inboundType; source_domain = [string]$domainPolicy.source_domain; runtime_action = $runtimeAction } | ConvertTo-Json -Depth 12 | Write-Output
                }
                else {
                    Write-StatusArtifact -LastAction "consume-event" -LastStatus "rejected_domain_policy" -LastEventId $eventIdValue
                    [pscustomobject]@{ ok = $false; action = "consume-event"; status = "rejected_domain_policy"; event_id = $eventIdValue; event_type = $inboundType; source_domain = [string]$domainPolicy.source_domain; runtime_action = $runtimeAction } | ConvertTo-Json -Depth 12 | Write-Output
                }
                break
            }

            if ([string]$domainPolicy.decision -eq "dry_run_only") {
                $state.processed_event_ids = @($state.processed_event_ids) + @($eventIdValue)
                $state.counters.inbound_accepted = [int]$state.counters.inbound_accepted + 1
                $state.counters.domain_policy_dry_run_only = [int]$state.counters.domain_policy_dry_run_only + 1
                Save-AdapterState -State $state -StateFile $stateAbs
                Append-JsonLine -Path $consumerLogAbs -Object ([pscustomobject]@{
                        logged_at = (Get-Date).ToUniversalTime().ToString("o")
                        status = "accepted_dry_run"
                        reason = "domain_policy_dry_run_only"
                        event_id = $eventIdValue
                        event_type = $inboundType
                        trace_id = [string]$event.correlation.trace_id
                        execution_id = $executionIdValue
                        source_domain = [string]$domainPolicy.source_domain
                        runtime_action = $runtimeAction
                    })

                $corrDryRun = Build-CorrelationFromEvent -Event $event
                $dryRunStartId = "evt-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 12))
                $null = Publish-EventInternal -Type "execution.started" -Id $dryRunStartId -Correlation $corrDryRun -Payload ([pscustomobject]@{ runtime_action = $runtimeAction; state = "started"; dry_run = $true }) -Reasons @(
                    New-Reason -Code "execution_started" -Severity "info" -Category "execution" -Message "Execution request accepted in dry-run mode by domain policy." -Evidence ([pscustomobject]@{ runtime_action = $runtimeAction; source_domain = [string]$domainPolicy.source_domain })
                ) -Artifacts @()

                $dryRunSuccessId = "evt-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 12))
                $dryRunReasonCode = if (-not [string]::IsNullOrWhiteSpace($domainDecisionCode)) { $domainDecisionCode } else { "domain_policy_dry_run_only" }
                $dryRunReasonMessage = if (-not [string]::IsNullOrWhiteSpace($domainDecisionMessage)) { $domainDecisionMessage } else { "Domain policy limited execution to dry-run only." }
                $null = Publish-EventInternal -Type "execution.succeeded" -Id $dryRunSuccessId -Correlation $corrDryRun -Payload ([pscustomobject]@{ runtime_action = $runtimeAction; dry_run = $true; result = [pscustomobject]@{ status = "dry_run"; policy_reason = $dryRunReasonCode } }) -Reasons @(
                    New-Reason -Code $dryRunReasonCode -Severity "info" -Category "guardrail" -Message $dryRunReasonMessage -Evidence ([pscustomobject]@{ runtime_action = $runtimeAction; source_domain = [string]$domainPolicy.source_domain })
                ) -Artifacts @()

                Write-StatusArtifact -LastAction "consume-event" -LastStatus "accepted_dry_run" -LastEventId $eventIdValue
                [pscustomobject]@{ ok = $true; action = "consume-event"; status = "accepted_dry_run"; event_id = $eventIdValue; event_type = $inboundType; source_domain = [string]$domainPolicy.source_domain; runtime_action = $runtimeAction } | ConvertTo-Json -Depth 12 | Write-Output
                break
            }

            if (@($schema.runtime_allowed_actions) -notcontains $runtimeAction) {
                $corr = Build-CorrelationFromEvent -Event $event
                $blockedReason = New-Reason -Code "guardrail_action_not_allowed" -Severity "warning" -Category "guardrail" -Message "Requested runtime action is not allowed by bus adapter guardrail." -Evidence ([pscustomobject]@{ runtime_action = $runtimeAction })
                $blockedId = "evt-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 12))
                $null = Publish-EventInternal -Type "execution.guardrail_blocked" -Id $blockedId -Correlation $corr -Payload ([pscustomobject]@{ runtime_action = $runtimeAction; decision = "blocked" }) -Reasons @($blockedReason) -Artifacts @()

                $state.counters.inbound_rejected = [int]$state.counters.inbound_rejected + 1
                $state.counters.guardrail_blocked = [int]$state.counters.guardrail_blocked + 1
                Save-AdapterState -State $state -StateFile $stateAbs
                Append-JsonLine -Path $consumerLogAbs -Object ([pscustomobject]@{
                        logged_at = (Get-Date).ToUniversalTime().ToString("o")
                        status = "rejected_guardrail"
                        reason = "guardrail_action_not_allowed"
                        event_id = $eventIdValue
                        event_type = $inboundType
                        runtime_action = $runtimeAction
                    })
                Write-StatusArtifact -LastAction "consume-event" -LastStatus "rejected_guardrail" -LastEventId $eventIdValue
                [pscustomobject]@{ ok = $false; action = "consume-event"; status = "rejected_guardrail"; event_id = $eventIdValue; event_type = $inboundType } | ConvertTo-Json -Depth 10 | Write-Output
                break
            }

            $state.processed_event_ids = @($state.processed_event_ids) + @($eventIdValue)
            if (@($state.accepted_execution_ids) -notcontains $executionIdValue) {
                $state.accepted_execution_ids = @($state.accepted_execution_ids) + @($executionIdValue)
            }
            $state.counters.inbound_accepted = [int]$state.counters.inbound_accepted + 1
            $state.counters.domain_policy_allowed = [int]$state.counters.domain_policy_allowed + 1
            Save-AdapterState -State $state -StateFile $stateAbs

            Append-JsonLine -Path $consumerLogAbs -Object ([pscustomobject]@{
                    logged_at = (Get-Date).ToUniversalTime().ToString("o")
                    status = "accepted"
                    reason = "request_validated"
                    event_id = $eventIdValue
                    event_type = $inboundType
                    trace_id = [string]$event.correlation.trace_id
                    execution_id = $executionIdValue
                    runtime_action = $runtimeAction
                })

            $corrAccepted = Build-CorrelationFromEvent -Event $event
            $startEventId = "evt-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 12))
            $startReasonCode = if ([string]$sourceDomainValue -like "workspace.perception*") { "perception_workspace_action_allowed" } else { "execution_started" }
            $startReason = New-Reason -Code $startReasonCode -Severity "info" -Category "execution" -Message "Execution requested event accepted and runtime action started." -Evidence ([pscustomobject]@{ runtime_action = $runtimeAction; source_domain = $sourceDomainValue })
            $null = Publish-EventInternal -Type "execution.started" -Id $startEventId -Correlation $corrAccepted -Payload ([pscustomobject]@{ runtime_action = $runtimeAction; state = "started" }) -Reasons @($startReason) -Artifacts @()

            $runtimeOk = $false
            $runtimeSummary = [pscustomobject]@{ runtime_action = $runtimeAction }
            $runtimeError = ""
            $simulateRetryOnce = $false
            $simulateDrift = $false
            if ($event.PSObject.Properties["payload"] -and $event.payload) {
                if ($event.payload.PSObject.Properties["simulate_retry_once"]) {
                    $simulateRetryOnce = [bool]$event.payload.simulate_retry_once
                }
                if ($event.payload.PSObject.Properties["simulate_drift"]) {
                    $simulateDrift = [bool]$event.payload.simulate_drift
                }
                if ($event.payload.PSObject.Properties["reliability_hints"] -and $event.payload.reliability_hints) {
                    if ($event.payload.reliability_hints.PSObject.Properties["simulate_retry_once"]) {
                        $simulateRetryOnce = [bool]$event.payload.reliability_hints.simulate_retry_once
                    }
                    if ($event.payload.reliability_hints.PSObject.Properties["simulate_drift"]) {
                        $simulateDrift = [bool]$event.payload.reliability_hints.simulate_drift
                    }
                }
            }

            $attempt = 0
            $maxAttempts = if ($simulateRetryOnce) { 2 } else { 1 }
            while (($attempt -lt $maxAttempts) -and (-not $runtimeOk)) {
                $attempt = $attempt + 1
                try {
                    if ($simulateRetryOnce -and $attempt -eq 1) {
                        throw "Simulated transient failure before bounded retry"
                    }

                    $runtimePayload = $null
                    if ($runtimeAction -eq "get-engineering-loop-summary") {
                        $runtimePayload = Get-LightweightEngineeringLoopSummary
                    }
                    else {
                        if (-not (Test-Path -Path $todScriptAbs)) { throw "TOD runtime script not found" }
                        if (-not (Test-Path -Path $todConfigAbs)) { throw "TOD runtime config not found" }
                        $runtimeRaw = & $todScriptAbs -Action $runtimeAction -ConfigPath $todConfigAbs -Top 10
                        $runtimePayload = $runtimeRaw | ConvertFrom-Json
                    }

                    $runtimeOk = $true
                    if ($runtimePayload -and $runtimePayload.PSObject.Properties["path"]) {
                        $runtimeSummary | Add-Member -NotePropertyName path -NotePropertyValue ([string]$runtimePayload.path) -Force
                    }
                    if ($runtimePayload -and $runtimePayload.PSObject.Properties["status"]) {
                        $runtimeSummary | Add-Member -NotePropertyName status -NotePropertyValue ([string]$runtimePayload.status) -Force
                    }
                    if ($runtimePayload -and $runtimePayload.PSObject.Properties["generated_at"]) {
                        $runtimeSummary | Add-Member -NotePropertyName generated_at -NotePropertyValue ([string]$runtimePayload.generated_at) -Force
                    }
                }
                catch {
                    $runtimeOk = $false
                    $runtimeError = [string]$_.Exception.Message

                    if ($attempt -lt $maxAttempts) {
                        $retryId = "evt-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 12))
                        $retryReason = New-Reason -Code "retry_scheduled" -Severity "warning" -Category "retry" -Message "Transient runtime failure encountered; bounded retry scheduled." -Evidence ([pscustomobject]@{ runtime_action = $runtimeAction; attempt = $attempt; next_attempt = ($attempt + 1) })
                        $null = Publish-EventInternal -Type "execution.retry_scheduled" -Id $retryId -Correlation $corrAccepted -Payload ([pscustomobject]@{ runtime_action = $runtimeAction; current_attempt = $attempt; next_attempt = ($attempt + 1) }) -Reasons @($retryReason) -Artifacts @()
                        $state.counters.retries_scheduled = [int]$state.counters.retries_scheduled + 1
                        Save-AdapterState -State $state -StateFile $stateAbs
                    }
                }
            }

            if ($runtimeOk -and $attempt -gt 1) {
                $fallbackId = "evt-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 12))
                $fallbackReason = New-Reason -Code "fallback_applied" -Severity "warning" -Category "recovery" -Message "Fallback path applied via bounded retry execution." -Evidence ([pscustomobject]@{ runtime_action = $runtimeAction; attempts = $attempt })
                $null = Publish-EventInternal -Type "execution.fallback_applied" -Id $fallbackId -Correlation $corrAccepted -Payload ([pscustomobject]@{ runtime_action = $runtimeAction; strategy = "bounded_retry"; attempts = $attempt }) -Reasons @($fallbackReason) -Artifacts @()

                $recoverId = "evt-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 12))
                $recoverReason = New-Reason -Code "recovery_completed" -Severity "info" -Category "recovery" -Message "Execution recovered after bounded retry." -Evidence ([pscustomobject]@{ runtime_action = $runtimeAction; attempts = $attempt })
                $null = Publish-EventInternal -Type "execution.recovered" -Id $recoverId -Correlation $corrAccepted -Payload ([pscustomobject]@{ runtime_action = $runtimeAction; attempts = $attempt; state = "recovered" }) -Reasons @($recoverReason) -Artifacts @()

                $state.counters.fallback_applied = [int]$state.counters.fallback_applied + 1
                $state.counters.recoveries = [int]$state.counters.recoveries + 1
                Save-AdapterState -State $state -StateFile $stateAbs
            }

            $runtimeStatus = ""
            if ($runtimeSummary.PSObject.Properties["status"]) {
                $runtimeStatus = [string]$runtimeSummary.status
            }
            if ($runtimeOk -and ($simulateDrift -or ($runtimeStatus -in @("warning", "critical", "warming", "degraded")))) {
                $driftId = "evt-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 12))
                $driftReason = New-Reason -Code "drift_detected" -Severity "warning" -Category "drift" -Message "Runtime drift signal observed during bounded execution." -Evidence ([pscustomobject]@{ runtime_action = $runtimeAction; status = $runtimeStatus })
                $null = Publish-EventInternal -Type "execution.drift_detected" -Id $driftId -Correlation $corrAccepted -Payload ([pscustomobject]@{ runtime_action = $runtimeAction; drift_state = "warning"; status = $runtimeStatus }) -Reasons @($driftReason) -Artifacts @()
                $state.counters.drift_detected = [int]$state.counters.drift_detected + 1
                Save-AdapterState -State $state -StateFile $stateAbs
            }

            if ($runtimeOk) {
                $successEventId = "evt-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 12))
                $successReason = New-Reason -Code "execution_succeeded" -Severity "info" -Category "outcome" -Message "Requested runtime action completed successfully." -Evidence ([pscustomobject]@{ runtime_action = $runtimeAction })
                $artifactLinks = @("shared_state/next_actions.json", "shared_state/review_artifacts_index.json")
                $null = Publish-EventInternal -Type "execution.succeeded" -Id $successEventId -Correlation $corrAccepted -Payload ([pscustomobject]@{ runtime_action = $runtimeAction; result = $runtimeSummary }) -Reasons @($successReason) -Artifacts $artifactLinks

                $state.accepted_execution_ids = @($state.accepted_execution_ids | Where-Object { [string]$_ -ne $executionIdValue })
                $state.counters.successful_runtime = [int]$state.counters.successful_runtime + 1
                Save-AdapterState -State $state -StateFile $stateAbs
                Write-StatusArtifact -LastAction "consume-event" -LastStatus "accepted_executed" -LastEventId $eventIdValue
                [pscustomobject]@{ ok = $true; action = "consume-event"; status = "accepted_executed"; event_id = $eventIdValue; event_type = $inboundType; source_domain = $sourceDomainValue; runtime_action = $runtimeAction } | ConvertTo-Json -Depth 12 | Write-Output
                break
            }

            $failedEventId = "evt-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 12))
            $failedReason = New-Reason -Code "execution_failed" -Severity "error" -Category "execution" -Message "Requested runtime action failed." -Evidence ([pscustomobject]@{ runtime_action = $runtimeAction; error = $runtimeError })
            $null = Publish-EventInternal -Type "execution.failed" -Id $failedEventId -Correlation $corrAccepted -Payload ([pscustomobject]@{ runtime_action = $runtimeAction; error = $runtimeError }) -Reasons @($failedReason) -Artifacts @()

            $state.accepted_execution_ids = @($state.accepted_execution_ids | Where-Object { [string]$_ -ne $executionIdValue })
            $state.counters.failed_runtime = [int]$state.counters.failed_runtime + 1
            Save-AdapterState -State $state -StateFile $stateAbs
            Write-StatusArtifact -LastAction "consume-event" -LastStatus "accepted_failed" -LastEventId $eventIdValue
            [pscustomobject]@{ ok = $false; action = "consume-event"; status = "accepted_failed"; event_id = $eventIdValue; event_type = $inboundType; source_domain = $sourceDomainValue; runtime_action = $runtimeAction; error = $runtimeError } | ConvertTo-Json -Depth 12 | Write-Output
            break
        }

        $state.counters.inbound_ignored = [int]$state.counters.inbound_ignored + 1
        Save-AdapterState -State $state -StateFile $stateAbs
        Append-JsonLine -Path $consumerLogAbs -Object ([pscustomobject]@{
                logged_at = (Get-Date).ToUniversalTime().ToString("o")
                status = "ignored_unknown"
                reason = "request_unknown_type_ignored"
                event_id = $eventIdValue
                event_type = $inboundType
            })
        Write-StatusArtifact -LastAction "consume-event" -LastStatus "ignored_unknown" -LastEventId $eventIdValue
        [pscustomobject]@{ ok = $true; action = "consume-event"; status = "ignored_unknown"; event_id = $eventIdValue; event_type = $inboundType } | ConvertTo-Json -Depth 10 | Write-Output
        break
    }

    "consume-inbox" {
        if (-not (Test-Path -Path $inboxAbs)) {
            [pscustomobject]@{ ok = $true; action = "consume-inbox"; status = "no_inbox"; inbox_path = $inboxAbs; consumed = 0 } | ConvertTo-Json -Depth 10 | Write-Output
            break
        }

        if (-not (Test-Path -Path $processedAbs)) {
            New-Item -ItemType Directory -Path $processedAbs -Force | Out-Null
        }

        $files = @(Get-ChildItem -Path $inboxAbs -Filter "*.json" -File | Sort-Object LastWriteTimeUtc)
        $results = @()
        foreach ($file in $files) {
            $consumeRaw = & $PSCommandPath -Action "consume-event" -EventFile $file.FullName -EventStreamPath $EventStreamPath -InboundInboxPath $InboundInboxPath -ProcessedInboxPath $ProcessedInboxPath -AdapterStatePath $AdapterStatePath -ConsumerLogPath $ConsumerLogPath -CorrelationLogPath $CorrelationLogPath -SchemaPath $SchemaPath -BusStatusPath $BusStatusPath -ExecutionSummaryPath $ExecutionSummaryPath -ExecutionSummaryIndexPath $ExecutionSummaryIndexPath -ExecutionSummaryContractPath $ExecutionSummaryContractPath -ExecutionDomainPolicyPath $ExecutionDomainPolicyPath -TodScriptPath $TodScriptPath -TodConfigPath $TodConfigPath
            $consumeObj = $consumeRaw | ConvertFrom-Json
            $results += $consumeObj

            $dest = Join-Path $processedAbs $file.Name
            Move-Item -Path $file.FullName -Destination $dest -Force
        }

        [pscustomobject]@{
            ok = $true
            action = "consume-inbox"
            status = "processed"
            consumed = @($results).Count
            accepted = [int]@($results | Where-Object { [string]$_.status -in @("accepted", "accepted_executed", "accepted_control_signal", "accepted_cancelled", "accepted_cancelled_pending_inquiry_timeout", "paused_pending_inquiry", "resumed_after_inquiry", "deferred_for_operator_clarification") }).Count
            ignored = [int]@($results | Where-Object { [string]$_.status -eq "ignored_unknown" }).Count
            rejected = [int]@($results | Where-Object { [string]$_.status -eq "rejected_malformed" }).Count
            duplicate = [int]@($results | Where-Object { [string]$_.status -eq "duplicate_ignored" }).Count
        } | ConvertTo-Json -Depth 12 | Write-Output
        Write-StatusArtifact -LastAction "consume-inbox" -LastStatus "processed"
        break
    }

    "status" {
        Write-StatusArtifact -LastAction "status" -LastStatus "ok"

        $statusObj = Get-Content -Path $busStatusAbs -Raw | ConvertFrom-Json
        $statusObj | Add-Member -NotePropertyName ok -NotePropertyValue $true -Force
        $statusObj | Add-Member -NotePropertyName action -NotePropertyValue "status" -Force
        $statusObj | Add-Member -NotePropertyName state -NotePropertyValue $state -Force
        $statusObj | Add-Member -NotePropertyName paths -NotePropertyValue ([pscustomobject]@{
                stream = $eventStreamAbs
                inbox = $inboxAbs
                processed = $processedAbs
                state = $stateAbs
                consumer_log = $consumerLogAbs
                correlation_log = $correlationLogAbs
                schema = $schemaAbs
                execution_summary = $executionSummaryAbs
                execution_summary_index = $executionSummaryIndexAbs
                execution_summary_contract = $executionSummaryContractAbs
                execution_domain_policy = $executionDomainPolicyAbs
                perception_context_schema = $perceptionContextSchemaAbs
            }) -Force

        $statusObj | ConvertTo-Json -Depth 20 | Write-Output
        break
    }

    "summarize-executions" {
        $summaries = Build-ExecutionSummaries
        $summaryVersion = "1.0.0"
        $orderingNotes = "Summaries are sorted by last_event_at descending; ties are ordered by trace_id then execution_id ascending."
        $retentionNotes = "Artifact is regenerated and overwritten per summarize-executions run; long-term history remains in the bus event stream."
        $summaryPathRelative = Get-RepoRelativePath -AbsolutePath $executionSummaryAbs
        $summaryIndexPathRelative = Get-RepoRelativePath -AbsolutePath $executionSummaryIndexAbs
        $summaryContractPathRelative = Get-RepoRelativePath -AbsolutePath $executionSummaryContractAbs
        $domainPolicyPathRelative = Get-RepoRelativePath -AbsolutePath $executionDomainPolicyAbs

        $summaryObj = [pscustomobject]@{
            generated_at = (Get-Date).ToUniversalTime().ToString("o")
            summary_version = $summaryVersion
            source = "tod-bus-adapter-v1"
            type = "bus_execution_summaries"
            ordering_notes = $orderingNotes
            retention_notes = $retentionNotes
            discovery_pointer_path = $summaryIndexPathRelative
            contract_path = $summaryContractPathRelative
            execution_domain_policy_path = $domainPolicyPathRelative
            summary_count = [int]@($summaries).Count
            summaries = @($summaries)
        }

        $pointerObj = [pscustomobject]@{
            generated_at = $summaryObj.generated_at
            summary_version = $summaryVersion
            source = "tod-bus-adapter-v1"
            type = "bus_execution_summaries_pointer"
            latest_summary_path = $summaryPathRelative
            contract_path = $summaryContractPathRelative
            execution_domain_policy_path = $domainPolicyPathRelative
            ordering_notes = $orderingNotes
            retention_notes = $retentionNotes
        }

        Ensure-ParentDir -FilePath $executionSummaryAbs
        $summaryObj | ConvertTo-Json -Depth 20 | Set-Content -Path $executionSummaryAbs
        Ensure-ParentDir -FilePath $executionSummaryIndexAbs
        $pointerObj | ConvertTo-Json -Depth 20 | Set-Content -Path $executionSummaryIndexAbs
        Write-StatusArtifact -LastAction "summarize-executions" -LastStatus "ok"

        [pscustomobject]@{
            ok = $true
            action = "summarize-executions"
            status = "ok"
            summary_path = $summaryPathRelative
            summary_version = $summaryVersion
            ordering_notes = $orderingNotes
            retention_notes = $retentionNotes
            discovery_pointer_path = $summaryIndexPathRelative
            contract_path = $summaryContractPathRelative
            summary_count = [int]@($summaries).Count
            summaries = @($summaries)
        } | ConvertTo-Json -Depth 20 | Write-Output
        break
    }
}
