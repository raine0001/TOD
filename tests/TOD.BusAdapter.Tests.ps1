Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$adapterScript = Join-Path $repoRoot "scripts/Invoke-TODBusAdapter.ps1"

function New-TestPaths {
    $id = [guid]::NewGuid().ToString("N")
    $base = Join-Path $repoRoot ("tod/out/tests/bus-adapter-" + $id)
    $inbox = Join-Path $base "inbox"
    $processed = Join-Path $base "processed"
    New-Item -ItemType Directory -Path $inbox -Force | Out-Null
    New-Item -ItemType Directory -Path $processed -Force | Out-Null

    return [pscustomobject]@{
        Base = $base
        Stream = (Join-Path $base "events.jsonl")
        State = (Join-Path $base "adapter-state.json")
        ConsumerLog = (Join-Path $base "consumer-log.jsonl")
        CorrelationLog = (Join-Path $base "correlation-log.jsonl")
        Status = (Join-Path $base "bus-adapter-status.json")
        Summary = (Join-Path $base "bus-execution-summaries.json")
        SummaryIndex = (Join-Path $base "bus-execution-summaries.index.json")
        SummaryContract = (Join-Path $repoRoot "tod/templates/bus/tod_bus_execution_summary_handoff.schema.json")
        DomainPolicy = (Join-Path $repoRoot "tod/templates/bus/tod_cross_domain_execution_policy.json")
        Inbox = $inbox
        Processed = $processed
    }
}

function Get-RelativePathPortable {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$TargetPath
    )

    $baseFull = [System.IO.Path]::GetFullPath($BasePath)
    $targetFull = [System.IO.Path]::GetFullPath($TargetPath)
    if (-not $baseFull.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
        $baseFull = $baseFull + [System.IO.Path]::DirectorySeparatorChar
    }
    $baseUri = New-Object System.Uri($baseFull)
    $targetUri = New-Object System.Uri($targetFull)
    return ([System.Uri]::UnescapeDataString($baseUri.MakeRelativeUri($targetUri).ToString())).Replace("\\", "/")
}

function Invoke-Adapter {
    param(
        [Parameter(Mandatory = $true)][pscustomobject]$Paths,
        [Parameter(Mandatory = $true)][string]$AdapterAction,
        [hashtable]$InputParams = @{}
    )

    $invokeMap = @{
        Action = $AdapterAction
        EventStreamPath = $Paths.Stream
        InboundInboxPath = $Paths.Inbox
        ProcessedInboxPath = $Paths.Processed
        AdapterStatePath = $Paths.State
        ConsumerLogPath = $Paths.ConsumerLog
        CorrelationLogPath = $Paths.CorrelationLog
        BusStatusPath = $Paths.Status
        ExecutionSummaryPath = $Paths.Summary
        ExecutionSummaryIndexPath = $Paths.SummaryIndex
        ExecutionSummaryContractPath = $Paths.SummaryContract
        ExecutionDomainPolicyPath = $Paths.DomainPolicy
    }
    foreach ($k in $InputParams.Keys) {
        $invokeMap[$k] = $InputParams[$k]
    }

    $raw = & $adapterScript @invokeMap
    return ($raw | ConvertFrom-Json)
}

function Get-StreamEvents {
    param([Parameter(Mandatory = $true)][string]$StreamPath)
    if (-not (Test-Path -Path $StreamPath)) { return @() }
    return @((Get-Content -Path $StreamPath) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_ | ConvertFrom-Json })
}

Describe "TOD Bus Adapter" {
    It "valid execution request is accepted and executed" {
        $paths = New-TestPaths

        $evt = @{
            event_id = "evt-accept-001"
            event_type = "execution.requested"
            occurred_at = "2026-03-12T00:00:00Z"
            producer = @{ system = "MIM"; component = "ingestion"; role = "reasoning_runtime" }
            correlation = @{ trace_id = "trace-a"; execution_id = "exec-a"; source_domain = "mim" }
            payload = @{ runtime_action = "get-engineering-loop-summary" }
        } | ConvertTo-Json -Depth 8 -Compress

        $result = Invoke-Adapter -Paths $paths -AdapterAction "consume-event" -InputParams @{ EventJson = $evt }
        [bool]$result.ok | Should Be $true
        [string]$result.status | Should Be "accepted_executed"
        (Test-Path -Path $paths.Status) | Should Be $true

        $streamEvents = @((Get-Content -Path $paths.Stream) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_ | ConvertFrom-Json })
        @($streamEvents | Where-Object { [string]$_.event_type -eq "execution.started" }).Count | Should Be 1
        @($streamEvents | Where-Object { [string]$_.event_type -eq "execution.succeeded" }).Count | Should Be 1
        [string](@($streamEvents | Where-Object { [string]$_.event_type -eq "execution.started" } | Select-Object -First 1).correlation.source_domain) | Should Be "mim"
    }

    It "blocked action from policy-restricted domain is rejected safely" {
        $paths = New-TestPaths

        $evt = @{
            event_id = "evt-domain-blocked-001"
            event_type = "execution.requested"
            occurred_at = "2026-03-12T00:00:00Z"
            producer = @{ system = "OPS"; component = "operations"; role = "runtime_control" }
            correlation = @{ trace_id = "trace-domain-blocked"; execution_id = "exec-domain-blocked"; source_domain = "ops" }
            payload = @{ runtime_action = "get-engineering-loop-summary" }
        } | ConvertTo-Json -Depth 10 -Compress

        $result = Invoke-Adapter -Paths $paths -AdapterAction "consume-event" -InputParams @{ EventJson = $evt }
        [bool]$result.ok | Should Be $false
        [string]$result.status | Should Be "rejected_domain_policy"

        $streamEvents = Get-StreamEvents -StreamPath $paths.Stream
        $blocked = @($streamEvents | Where-Object { [string]$_.event_type -eq "execution.guardrail_blocked" } | Select-Object -Last 1)
        ($blocked.Count -gt 0) | Should Be $true
        [string]$blocked[0].correlation.source_domain | Should Be "ops"
        [string]$blocked[0].reasons[0].code | Should Be "domain_policy_blocked"
    }

    It "unsupported source domain is ignored safely" {
        $paths = New-TestPaths

        $evt = @{
            event_id = "evt-domain-unsupported-001"
            event_type = "execution.requested"
            occurred_at = "2026-03-12T00:00:00Z"
            producer = @{ system = "EXT"; component = "external"; role = "runtime_requester" }
            correlation = @{ trace_id = "trace-domain-unsupported"; execution_id = "exec-domain-unsupported"; source_domain = "external_unknown" }
            payload = @{ runtime_action = "get-engineering-loop-summary" }
        } | ConvertTo-Json -Depth 10 -Compress

        $result = Invoke-Adapter -Paths $paths -AdapterAction "consume-event" -InputParams @{ EventJson = $evt }
        [bool]$result.ok | Should Be $true
        [string]$result.status | Should Be "ignored_unsupported_domain"

        $streamEvents = Get-StreamEvents -StreamPath $paths.Stream
        @($streamEvents | Where-Object { [string]$_.event_type -eq "execution.started" }).Count | Should Be 0
        @($streamEvents | Where-Object { [string]$_.event_type -eq "execution.succeeded" }).Count | Should Be 0
    }

    It "malformed inbound event rejected" {
        $paths = New-TestPaths
        $result = Invoke-Adapter -Paths $paths -AdapterAction "consume-event" -InputParams @{ EventJson = "{ bad-json" }
        [bool]$result.ok | Should Be $false
        [string]$result.status | Should Be "rejected_malformed"
    }

    It "unknown inbound event ignored safely" {
        $paths = New-TestPaths

        $evt = @{
            event_id = "evt-unknown-001"
            event_type = "execution.unmapped"
            occurred_at = "2026-03-12T00:00:00Z"
            producer = @{ system = "MIM"; component = "ingestion"; role = "reasoning_runtime" }
            correlation = @{ trace_id = "trace-u"; execution_id = "exec-u" }
            payload = @{ note = "unknown" }
        } | ConvertTo-Json -Depth 8 -Compress

        $result = Invoke-Adapter -Paths $paths -AdapterAction "consume-event" -InputParams @{ EventJson = $evt }
        [bool]$result.ok | Should Be $true
        [string]$result.status | Should Be "ignored_unknown"
    }

    It "duplicate inbound event tolerated safely" {
        $paths = New-TestPaths

        $evt = @{
            event_id = "evt-dup-001"
            event_type = "execution.requested"
            occurred_at = "2026-03-12T00:00:00Z"
            producer = @{ system = "MIM"; component = "ingestion"; role = "reasoning_runtime" }
            correlation = @{ trace_id = "trace-d"; execution_id = "exec-d" }
            payload = @{ runtime_action = "get-engineering-loop-summary" }
        } | ConvertTo-Json -Depth 8 -Compress

        $first = Invoke-Adapter -Paths $paths -AdapterAction "consume-event" -InputParams @{ EventJson = $evt }
        $second = Invoke-Adapter -Paths $paths -AdapterAction "consume-event" -InputParams @{ EventJson = $evt }

        [string]$first.status | Should Be "accepted_executed"
        [string]$second.status | Should Be "duplicate_ignored"
    }

    It "out-of-order control signal is ignored safely" {
        $paths = New-TestPaths

        $evt = @{
            event_id = "evt-o3-001"
            event_type = "execution.cancel_requested"
            occurred_at = "2026-03-12T00:00:00Z"
            producer = @{ system = "MIM"; component = "ingestion"; role = "reasoning_runtime" }
            correlation = @{ trace_id = "trace-o3"; execution_id = "exec-o3" }
            payload = @{ reason = "user_cancelled" }
        } | ConvertTo-Json -Depth 8 -Compress

        $result = Invoke-Adapter -Paths $paths -AdapterAction "consume-event" -InputParams @{ EventJson = $evt }
        [bool]$result.ok | Should Be $true
        [string]$result.status | Should Be "ignored_out_of_order"
    }

    It "outbound events conform to schema and preserve correlation" {
        $paths = New-TestPaths

        $result = Invoke-Adapter -Paths $paths -AdapterAction "publish-event" -InputParams @{
            EventType = "execution.started"
            EventId = "evt-out-001"
            TraceId = "trace-o"
            ExecutionId = "exec-o"
            GoalId = "goal-o"
            PlanId = "plan-o"
            ActionId = "action-o"
            SourceDomain = "tod"
            EventJson = (@{ state = "started" } | ConvertTo-Json -Compress)
            ArtifactPaths = @("shared_state/next_actions.json")
        }

        [bool]$result.ok | Should Be $true
        [string]$result.status | Should Be "published"
        [string]$result.event.event_type | Should Be "execution.started"
        [string]$result.event.correlation.trace_id | Should Be "trace-o"
        [string]$result.event.correlation.execution_id | Should Be "exec-o"
        [string]$result.event.correlation.goal_id | Should Be "goal-o"
        [string]$result.event.correlation.plan_id | Should Be "plan-o"
        [string]$result.event.correlation.action_id | Should Be "action-o"
        [string]$result.event.correlation.source_domain | Should Be "tod"

        (Test-Path -Path $paths.CorrelationLog) | Should Be $true
    }

    It "retry, fallback, and recovered lifecycle events preserve correlation" {
        $paths = New-TestPaths

        $evt = @{
            event_id = "evt-rch-001"
            event_type = "execution.requested"
            occurred_at = "2026-03-12T00:00:00Z"
            producer = @{ system = "MIM"; component = "ingestion"; role = "reasoning_runtime" }
            correlation = @{ trace_id = "trace-rch"; execution_id = "exec-rch"; goal_id = "goal-rch"; source_domain = "mim" }
            payload = @{ runtime_action = "get-engineering-loop-summary"; reliability_hints = @{ simulate_retry_once = $true } }
        } | ConvertTo-Json -Depth 10 -Compress

        $result = Invoke-Adapter -Paths $paths -AdapterAction "consume-event" -InputParams @{ EventJson = $evt }
        [bool]$result.ok | Should Be $true
        [string]$result.status | Should Be "accepted_executed"

        $streamEvents = Get-StreamEvents -StreamPath $paths.Stream
        @($streamEvents | Where-Object { [string]$_.event_type -eq "execution.retry_scheduled" }).Count | Should Be 1
        @($streamEvents | Where-Object { [string]$_.event_type -eq "execution.fallback_applied" }).Count | Should Be 1
        @($streamEvents | Where-Object { [string]$_.event_type -eq "execution.recovered" }).Count | Should Be 1

        $enriched = @($streamEvents | Where-Object { [string]$_.event_type -in @("execution.retry_scheduled", "execution.fallback_applied", "execution.recovered") })
        foreach ($evtObj in $enriched) {
            [string]$evtObj.correlation.trace_id | Should Be "trace-rch"
            [string]$evtObj.correlation.execution_id | Should Be "exec-rch"
            [string]$evtObj.correlation.goal_id | Should Be "goal-rch"
            [string]$evtObj.correlation.source_domain | Should Be "mim"
        }

        $status = Get-Content -Path $paths.Status -Raw | ConvertFrom-Json
        [int]$status.lifecycle_feedback.retries_scheduled | Should BeGreaterThan 0
        [int]$status.lifecycle_feedback.recoveries | Should BeGreaterThan 0
        [int]$status.lifecycle_feedback.fallback_applied | Should BeGreaterThan 0
    }

    It "drift detection event is emitted and status snapshot increments" {
        $paths = New-TestPaths

        $evt = @{
            event_id = "evt-drift-001"
            event_type = "execution.requested"
            occurred_at = "2026-03-12T00:00:00Z"
            producer = @{ system = "MIM"; component = "ingestion"; role = "reasoning_runtime" }
            correlation = @{ trace_id = "trace-drift"; execution_id = "exec-drift" }
            payload = @{ runtime_action = "get-engineering-loop-summary"; reliability_hints = @{ simulate_drift = $true } }
        } | ConvertTo-Json -Depth 10 -Compress

        $result = Invoke-Adapter -Paths $paths -AdapterAction "consume-event" -InputParams @{ EventJson = $evt }
        [bool]$result.ok | Should Be $true

        $streamEvents = Get-StreamEvents -StreamPath $paths.Stream
        @($streamEvents | Where-Object { [string]$_.event_type -eq "execution.drift_detected" }).Count | Should BeGreaterThan 0

        $status = Get-Content -Path $paths.Status -Raw | ConvertFrom-Json
        [int]$status.lifecycle_feedback.drift_detected | Should BeGreaterThan 0
        [int]$status.lifecycle_feedback.successful_runtime | Should BeGreaterThan 0
    }

    It "active cancellation emits execution.cancelled" {
        $paths = New-TestPaths

        [pscustomobject]@{
            source = "tod-bus-adapter-v1"
            updated_at = ""
            processed_event_ids = @()
            accepted_execution_ids = @("exec-cancel")
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
            }
        } | ConvertTo-Json -Depth 12 | Set-Content -Path $paths.State

        $cancelEvt = @{
            event_id = "evt-cancel-001"
            event_type = "execution.cancel_requested"
            occurred_at = "2026-03-12T00:00:00Z"
            producer = @{ system = "MIM"; component = "ingestion"; role = "reasoning_runtime" }
            correlation = @{ trace_id = "trace-cancel"; execution_id = "exec-cancel" }
            payload = @{ reason = "operator_requested" }
        } | ConvertTo-Json -Depth 10 -Compress

        $result = Invoke-Adapter -Paths $paths -AdapterAction "consume-event" -InputParams @{ EventJson = $cancelEvt }
        [bool]$result.ok | Should Be $true
        [string]$result.status | Should Be "accepted_cancelled"

        $streamEvents = Get-StreamEvents -StreamPath $paths.Stream
        @($streamEvents | Where-Object { [string]$_.event_type -eq "execution.cancelled" }).Count | Should Be 1

        $status = Get-Content -Path $paths.Status -Raw | ConvertFrom-Json
        [int]$status.lifecycle_feedback.cancelled | Should BeGreaterThan 0
    }

    It "execution summary rollup is accurate for enriched lifecycle" {
        $paths = New-TestPaths

        $evt = @{
            event_id = "evt-sum-001"
            event_type = "execution.requested"
            occurred_at = "2026-03-12T00:00:00Z"
            producer = @{ system = "MIM"; component = "ingestion"; role = "reasoning_runtime" }
            correlation = @{ trace_id = "trace-sum"; execution_id = "exec-sum"; goal_id = "goal-sum"; source_domain = "mim" }
            payload = @{ runtime_action = "get-engineering-loop-summary"; reliability_hints = @{ simulate_retry_once = $true; simulate_drift = $true } }
        } | ConvertTo-Json -Depth 12 -Compress

        $consumeResult = Invoke-Adapter -Paths $paths -AdapterAction "consume-event" -InputParams @{ EventJson = $evt }
        [bool]$consumeResult.ok | Should Be $true

        $summaryResult = Invoke-Adapter -Paths $paths -AdapterAction "summarize-executions"
        [bool]$summaryResult.ok | Should Be $true
        (Test-Path -Path $paths.Summary) | Should Be $true

        $target = @($summaryResult.summaries | Where-Object { [string]$_.trace_id -eq "trace-sum" -and [string]$_.execution_id -eq "exec-sum" }) | Select-Object -First 1
        ($null -ne $target) | Should Be $true
        [string]$target.final_outcome | Should Be "succeeded"
        [int]$target.retries | Should BeGreaterThan 0
        [int]$target.fallbacks | Should BeGreaterThan 0
        [bool]$target.recovered | Should Be $true
        [int]$target.drift_events | Should BeGreaterThan 0
        [int]$target.cancelled | Should Be 0
        [int]$target.guardrail_blocks | Should Be 0
        [string]$target.reliability_signal | Should Be "warning"
        [string]$target.recommended_attention | Should Be "monitor_closely"
        [string]$target.source_domain | Should Be "mim"
        @($target.artifact_links).Count | Should BeGreaterThan 0
    }

    It "source_domain is preserved across lifecycle events and summary handoff artifacts" {
        $paths = New-TestPaths

        $evt = @{
            event_id = "evt-domain-preserve-001"
            event_type = "execution.requested"
            occurred_at = "2026-03-12T00:00:00Z"
            producer = @{ system = "MIM"; component = "ingestion"; role = "reasoning_runtime" }
            correlation = @{ trace_id = "trace-domain-preserve"; execution_id = "exec-domain-preserve"; source_domain = "mim" }
            payload = @{ runtime_action = "get-engineering-loop-summary" }
        } | ConvertTo-Json -Depth 10 -Compress

        $consumeResult = Invoke-Adapter -Paths $paths -AdapterAction "consume-event" -InputParams @{ EventJson = $evt }
        [bool]$consumeResult.ok | Should Be $true

        $summaryResult = Invoke-Adapter -Paths $paths -AdapterAction "summarize-executions"
        [bool]$summaryResult.ok | Should Be $true
        (Test-Path -Path $paths.Summary) | Should Be $true
        (Test-Path -Path $paths.SummaryIndex) | Should Be $true

        $streamEvents = Get-StreamEvents -StreamPath $paths.Stream
        foreach ($evtObj in @($streamEvents | Where-Object { [string]$_.event_type -in @("execution.started", "execution.succeeded") })) {
            [string]$evtObj.correlation.source_domain | Should Be "mim"
        }

        $summaryDoc = Get-Content -Path $paths.Summary -Raw | ConvertFrom-Json
        $summaryEntry = @($summaryDoc.summaries | Where-Object { [string]$_.trace_id -eq "trace-domain-preserve" -and [string]$_.execution_id -eq "exec-domain-preserve" } | Select-Object -First 1)
        ($summaryEntry.Count -gt 0) | Should Be $true
        [string]$summaryEntry[0].source_domain | Should Be "mim"
        [string]$summaryDoc.execution_domain_policy_path | Should Be "tod/templates/bus/tod_cross_domain_execution_policy.json"

        $pointerDoc = Get-Content -Path $paths.SummaryIndex -Raw | ConvertFrom-Json
        [string]$pointerDoc.execution_domain_policy_path | Should Be "tod/templates/bus/tod_cross_domain_execution_policy.json"
    }

    It "execution summary remains consistent with event stream counts" {
        $paths = New-TestPaths

        $evt = @{
            event_id = "evt-sum-002"
            event_type = "execution.requested"
            occurred_at = "2026-03-12T00:00:00Z"
            producer = @{ system = "MIM"; component = "ingestion"; role = "reasoning_runtime" }
            correlation = @{ trace_id = "trace-consistency"; execution_id = "exec-consistency" }
            payload = @{ runtime_action = "get-engineering-loop-summary"; reliability_hints = @{ simulate_retry_once = $true } }
        } | ConvertTo-Json -Depth 10 -Compress

        $null = Invoke-Adapter -Paths $paths -AdapterAction "consume-event" -InputParams @{ EventJson = $evt }
        $streamEvents = @(
            Get-StreamEvents -StreamPath $paths.Stream |
            Where-Object { [string]$_.correlation.trace_id -eq "trace-consistency" -and [string]$_.correlation.execution_id -eq "exec-consistency" }
        )

        $summaryResult = Invoke-Adapter -Paths $paths -AdapterAction "summarize-executions"
        $target = @($summaryResult.summaries | Where-Object { [string]$_.trace_id -eq "trace-consistency" -and [string]$_.execution_id -eq "exec-consistency" }) | Select-Object -First 1

        ($null -ne $target) | Should Be $true
        [int]$target.event_count | Should Be @($streamEvents).Count
        [int]$target.retries | Should Be @($streamEvents | Where-Object { [string]$_.event_type -eq "execution.retry_scheduled" }).Count
        [int]$target.fallbacks | Should Be @($streamEvents | Where-Object { [string]$_.event_type -eq "execution.fallback_applied" }).Count
        [int]$target.drift_events | Should Be @($streamEvents | Where-Object { [string]$_.event_type -eq "execution.drift_detected" }).Count
        [int]$target.cancelled | Should Be @($streamEvents | Where-Object { [string]$_.event_type -eq "execution.cancelled" }).Count
        [int]$target.guardrail_blocks | Should Be @($streamEvents | Where-Object { [string]$_.event_type -eq "execution.guardrail_blocked" }).Count
    }

    It "execution summary contract metadata and pointer are consistent" {
        $paths = New-TestPaths

        $evt = @{
            event_id = "evt-contract-001"
            event_type = "execution.requested"
            occurred_at = "2026-03-12T00:00:00Z"
            producer = @{ system = "MIM"; component = "ingestion"; role = "reasoning_runtime" }
            correlation = @{ trace_id = "trace-contract"; execution_id = "exec-contract" }
            payload = @{ runtime_action = "get-engineering-loop-summary" }
        } | ConvertTo-Json -Depth 10 -Compress
        $null = Invoke-Adapter -Paths $paths -AdapterAction "consume-event" -InputParams @{ EventJson = $evt }

        $summaryResult = Invoke-Adapter -Paths $paths -AdapterAction "summarize-executions"
        [bool]$summaryResult.ok | Should Be $true
        (Test-Path -Path $paths.Summary) | Should Be $true
        (Test-Path -Path $paths.SummaryIndex) | Should Be $true

        $summaryDoc = Get-Content -Path $paths.Summary -Raw | ConvertFrom-Json
        $pointerDoc = Get-Content -Path $paths.SummaryIndex -Raw | ConvertFrom-Json
        $contractDoc = Get-Content -Path $paths.SummaryContract -Raw | ConvertFrom-Json

        foreach ($field in @($contractDoc.required_metadata_fields)) {
            (($summaryDoc.PSObject.Properties.Name) -contains [string]$field) | Should Be $true
        }
        [string]$summaryDoc.summary_version | Should Be ([string]$contractDoc.summary_version)
        [string]$summaryDoc.type | Should Be ([string]$contractDoc.type)
        [string]$pointerDoc.type | Should Be "bus_execution_summaries_pointer"
        [string]$pointerDoc.latest_summary_path | Should Be (Get-RelativePathPortable -BasePath $repoRoot -TargetPath $paths.Summary)
        [string]$pointerDoc.contract_path | Should Be (Get-RelativePathPortable -BasePath $repoRoot -TargetPath $paths.SummaryContract)

        $firstSummary = @($summaryDoc.summaries | Select-Object -First 1)
        ($firstSummary.Count -gt 0) | Should Be $true
        foreach ($field in @($contractDoc.required_summary_fields)) {
            (($firstSummary[0].PSObject.Properties.Name) -contains [string]$field) | Should Be $true
        }
    }

    It "execution summaries are stably ordered" {
        $paths = New-TestPaths

        foreach ($suffix in @("b", "a")) {
            $evt = @{
                event_id = "evt-order-$suffix"
                event_type = "execution.requested"
                occurred_at = "2026-03-12T00:00:00Z"
                producer = @{ system = "MIM"; component = "ingestion"; role = "reasoning_runtime" }
                correlation = @{ trace_id = "trace-order-$suffix"; execution_id = "exec-order-$suffix" }
                payload = @{ runtime_action = "get-engineering-loop-summary" }
            } | ConvertTo-Json -Depth 10 -Compress
            $null = Invoke-Adapter -Paths $paths -AdapterAction "consume-event" -InputParams @{ EventJson = $evt }
        }

        $summaryResult = Invoke-Adapter -Paths $paths -AdapterAction "summarize-executions"
        $sorted = @($summaryResult.summaries)
        ($sorted.Count -ge 2) | Should Be $true

        for ($i = 1; $i -lt $sorted.Count; $i++) {
            $prev = $sorted[$i - 1]
            $curr = $sorted[$i]

            $prevTs = [datetime]::Parse([string]$prev.last_event_at)
            $currTs = [datetime]::Parse([string]$curr.last_event_at)
            ($prevTs -ge $currTs) | Should Be $true

            if ($prevTs -eq $currTs) {
                $prevTrace = [string]$prev.trace_id
                $currTrace = [string]$curr.trace_id
                if ($prevTrace -eq $currTrace) {
                    ([string]$prev.execution_id -le [string]$curr.execution_id) | Should Be $true
                }
                else {
                    ($prevTrace -le $currTrace) | Should Be $true
                }
            }
        }
    }
}
