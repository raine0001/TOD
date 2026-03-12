Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$adapterScript = Join-Path $repoRoot "scripts/Invoke-TODBusAdapter.ps1"
$sampleScript = Join-Path $repoRoot "scripts/Invoke-TODInquiryPauseResumeSample.ps1"
$sampleArtifactPath = Join-Path $repoRoot "shared_state/bus_inquiry_pause_resume_sample.json"

function New-TestPaths {
    $id = [guid]::NewGuid().ToString("N")
    $base = Join-Path $repoRoot ("tod/out/tests/inquiry-control-" + $id)
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

function New-SeedState {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string[]]$Accepted = @(),
        [string[]]$Paused = @()
    )

    [pscustomobject]@{
        source = "tod-bus-adapter-v1"
        updated_at = ""
        processed_event_ids = @()
        accepted_execution_ids = @($Accepted)
        paused_execution_ids = @($Paused)
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
        }
    } | ConvertTo-Json -Depth 20 | Set-Content -Path $Path
}

Describe "TOD Inquiry Execution Control" {
    It "pause request transitions active execution to paused_pending_inquiry" {
        $paths = New-TestPaths
        New-SeedState -Path $paths.State -Accepted @("exec-pause") -Paused @()

        $evt = @{
            event_id = "evt-pause-001"
            event_type = "execution.pause_requested"
            occurred_at = "2026-03-12T00:00:00Z"
            producer = @{ system = "MIM"; component = "inquiry"; role = "reasoning_runtime" }
            correlation = @{ trace_id = "trace-pause"; execution_id = "exec-pause"; source_domain = "workspace.perception"; source_context = "workspace/mainboard" }
            payload = @{ note = "need clarification" }
        } | ConvertTo-Json -Depth 12 -Compress

        $result = Invoke-Adapter -Paths $paths -AdapterAction "consume-event" -InputParams @{ EventJson = $evt }
        [bool]$result.ok | Should Be $true
        [string]$result.status | Should Be "paused_pending_inquiry"

        $stream = Get-StreamEvents -StreamPath $paths.Stream
        $paused = @($stream | Where-Object { [string]$_.event_type -eq "execution.paused_pending_inquiry" } | Select-Object -First 1)
        ($paused.Count -gt 0) | Should Be $true
        [string]$paused[0].correlation.source_domain | Should Be "workspace.perception"
        [string]$paused[0].correlation.source_context | Should Be "workspace/mainboard"
        [string]$paused[0].reasons[0].code | Should Be "inquiry_pause_requested"
    }

    It "resume request transitions paused execution to resumed_after_inquiry" {
        $paths = New-TestPaths
        New-SeedState -Path $paths.State -Accepted @() -Paused @("exec-resume")

        $evt = @{
            event_id = "evt-resume-001"
            event_type = "execution.resume_requested"
            occurred_at = "2026-03-12T00:00:00Z"
            producer = @{ system = "MIM"; component = "inquiry"; role = "reasoning_runtime" }
            correlation = @{ trace_id = "trace-resume"; execution_id = "exec-resume"; source_domain = "workspace.perception"; source_context = "workspace/mainboard" }
            payload = @{ inquiry_resolved = $true }
        } | ConvertTo-Json -Depth 12 -Compress

        $result = Invoke-Adapter -Paths $paths -AdapterAction "consume-event" -InputParams @{ EventJson = $evt }
        [bool]$result.ok | Should Be $true
        [string]$result.status | Should Be "resumed_after_inquiry"

        $stream = Get-StreamEvents -StreamPath $paths.Stream
        $resumed = @($stream | Where-Object { [string]$_.event_type -eq "execution.resumed_after_inquiry" } | Select-Object -First 1)
        ($resumed.Count -gt 0) | Should Be $true
        [string]$resumed[0].reasons[0].code | Should Be "inquiry_resumed"
    }

    It "cancel request with inquiry timeout emits cancelled_pending_inquiry_timeout" {
        $paths = New-TestPaths
        New-SeedState -Path $paths.State -Accepted @() -Paused @("exec-timeout")

        $evt = @{
            event_id = "evt-cancel-timeout-001"
            event_type = "execution.cancel_requested"
            occurred_at = "2026-03-12T00:00:00Z"
            producer = @{ system = "MIM"; component = "inquiry"; role = "reasoning_runtime" }
            correlation = @{ trace_id = "trace-timeout"; execution_id = "exec-timeout"; source_domain = "workspace.perception"; source_context = "workspace/mainboard" }
            payload = @{ cancel_reason = "pending_inquiry_timeout" }
        } | ConvertTo-Json -Depth 12 -Compress

        $result = Invoke-Adapter -Paths $paths -AdapterAction "consume-event" -InputParams @{ EventJson = $evt }
        [bool]$result.ok | Should Be $true
        [string]$result.status | Should Be "accepted_cancelled_pending_inquiry_timeout"

        $stream = Get-StreamEvents -StreamPath $paths.Stream
        $cancelled = @($stream | Where-Object { [string]$_.event_type -eq "execution.cancelled_pending_inquiry_timeout" } | Select-Object -First 1)
        ($cancelled.Count -gt 0) | Should Be $true
        [string]$cancelled[0].reasons[0].code | Should Be "inquiry_timeout_cancelled"
    }

    It "invalid resume request is rejected safely" {
        $paths = New-TestPaths
        New-SeedState -Path $paths.State -Accepted @() -Paused @()

        $evt = @{
            event_id = "evt-resume-invalid-001"
            event_type = "execution.resume_requested"
            occurred_at = "2026-03-12T00:00:00Z"
            producer = @{ system = "MIM"; component = "inquiry"; role = "reasoning_runtime" }
            correlation = @{ trace_id = "trace-invalid"; execution_id = "exec-invalid"; source_domain = "workspace.perception"; source_context = "workspace/mainboard" }
            payload = @{ inquiry_resolved = $true }
        } | ConvertTo-Json -Depth 12 -Compress

        $result = Invoke-Adapter -Paths $paths -AdapterAction "consume-event" -InputParams @{ EventJson = $evt }
        [bool]$result.ok | Should Be $false
        [string]$result.status | Should Be "rejected_invalid_resume"

        $stream = Get-StreamEvents -StreamPath $paths.Stream
        @($stream | Where-Object { [string]$_.event_type -eq "execution.resumed_after_inquiry" }).Count | Should Be 0
    }

    It "summary preserves inquiry context and pause resume state" {
        $paths = New-TestPaths
        New-SeedState -Path $paths.State -Accepted @("exec-sum") -Paused @()

        $pauseEvt = @{
            event_id = "evt-sum-pause-001"
            event_type = "execution.pause_requested"
            occurred_at = "2026-03-12T00:00:00Z"
            producer = @{ system = "MIM"; component = "inquiry"; role = "reasoning_runtime" }
            correlation = @{ trace_id = "trace-sum"; execution_id = "exec-sum"; source_domain = "workspace.perception"; source_context = "workspace/mainboard" }
            payload = @{ note = "pause for inquiry" }
        } | ConvertTo-Json -Depth 12 -Compress
        $resumeEvt = @{
            event_id = "evt-sum-resume-001"
            event_type = "execution.resume_requested"
            occurred_at = "2026-03-12T00:00:30Z"
            producer = @{ system = "MIM"; component = "inquiry"; role = "reasoning_runtime" }
            correlation = @{ trace_id = "trace-sum"; execution_id = "exec-sum"; source_domain = "workspace.perception"; source_context = "workspace/mainboard" }
            payload = @{ inquiry_resolved = $true }
        } | ConvertTo-Json -Depth 12 -Compress

        $null = Invoke-Adapter -Paths $paths -AdapterAction "consume-event" -InputParams @{ EventJson = $pauseEvt }
        $null = Invoke-Adapter -Paths $paths -AdapterAction "consume-event" -InputParams @{ EventJson = $resumeEvt }
        $summaryResult = Invoke-Adapter -Paths $paths -AdapterAction "summarize-executions"

        [bool]$summaryResult.ok | Should Be $true
        $entry = @($summaryResult.summaries | Where-Object { [string]$_.trace_id -eq "trace-sum" -and [string]$_.execution_id -eq "exec-sum" } | Select-Object -First 1)
        ($entry.Count -gt 0) | Should Be $true
        [string]$entry[0].source_domain | Should Be "workspace.perception"
        [string]$entry[0].source_context | Should Be "workspace/mainboard"
        [int]$entry[0].paused_events | Should BeGreaterThan 0
        [int]$entry[0].resumed_events | Should BeGreaterThan 0
        [string]$entry[0].inquiry_state | Should Be "resumed_after_inquiry"
    }

    It "bounded inquiry sample is generated" {
        (Test-Path -Path $sampleScript) | Should Be $true
        $null = & $sampleScript
        (Test-Path -Path $sampleArtifactPath) | Should Be $true

        $sample = Get-Content -Path $sampleArtifactPath -Raw | ConvertFrom-Json
        [string]$sample.type | Should Be "tod_inquiry_pause_resume_sample"
        [string]$sample.context.source_domain | Should Be "workspace.perception"
        [string]$sample.context.source_context | Should Be "workspace/mainboard"
        [bool]$sample.summary.pause_resume_flow_ok | Should Be $true
    }
}
