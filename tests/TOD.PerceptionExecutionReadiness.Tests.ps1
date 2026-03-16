Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$adapterScript = Join-Path $repoRoot "scripts/Invoke-TODBusAdapter.ps1"
$sampleScriptPath = Join-Path $repoRoot "scripts/Invoke-TODPerceptionWorkspaceExecutionSample.ps1"
$sampleArtifactPath = Join-Path $repoRoot "shared_state/bus_perception_workspace_execution_sample.json"

function New-TestPaths {
    $id = [guid]::NewGuid().ToString("N")
    $base = Join-Path $repoRoot ("tod/out/tests/perception-readiness-" + $id)
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

Describe "TOD Perception Execution Readiness" {
    It "allowed workspace action is executed with perception context" {
        $paths = New-TestPaths

        $evt = @{
            event_id = "evt-p-allowed-001"
            event_type = "execution.requested"
            occurred_at = "2026-03-12T00:00:00Z"
            producer = @{ system = "MIM"; component = "perception"; role = "reasoning_runtime" }
            correlation = @{ trace_id = "trace-p-allowed"; execution_id = "exec-p-allowed"; source_domain = "workspace.perception"; source_context = "workspace/mainboard" }
            payload = @{ runtime_action = "get-engineering-loop-summary"; perception_context = @{ state = "clear"; safety = "safe"; context_id = "workspace/mainboard" } }
        } | ConvertTo-Json -Depth 12 -Compress

        $result = Invoke-Adapter -Paths $paths -AdapterAction "consume-event" -InputParams @{ EventJson = $evt }
        [bool]$result.ok | Should Be $true
        [string]$result.status | Should Be "accepted_executed"

        $streamEvents = Get-StreamEvents -StreamPath $paths.Stream
        $started = @($streamEvents | Where-Object { [string]$_.event_type -eq "execution.started" } | Select-Object -First 1)
        ($started.Count -gt 0) | Should Be $true
        [string]$started[0].correlation.source_domain | Should Be "workspace.perception"
        [string]$started[0].correlation.source_context | Should Be "workspace/mainboard"
        [string]$started[0].reasons[0].code | Should Be "perception_workspace_action_allowed"
    }

    It "uncertain perception context is constrained to dry-run" {
        $paths = New-TestPaths

        $evt = @{
            event_id = "evt-p-uncertain-001"
            event_type = "execution.requested"
            occurred_at = "2026-03-12T00:00:00Z"
            producer = @{ system = "MIM"; component = "perception"; role = "reasoning_runtime" }
            correlation = @{ trace_id = "trace-p-uncertain"; execution_id = "exec-p-uncertain"; source_domain = "workspace.perception"; source_context = "workspace/uncertain-zone" }
            payload = @{ runtime_action = "get-engineering-loop-summary"; perception_context = @{ state = "uncertain"; safety = "safe"; context_id = "workspace/uncertain-zone" } }
        } | ConvertTo-Json -Depth 12 -Compress

        $result = Invoke-Adapter -Paths $paths -AdapterAction "consume-event" -InputParams @{ EventJson = $evt }
        [bool]$result.ok | Should Be $true
        [string]$result.status | Should Be "accepted_dry_run"

        $streamEvents = Get-StreamEvents -StreamPath $paths.Stream
        $succeeded = @($streamEvents | Where-Object { [string]$_.event_type -eq "execution.succeeded" } | Select-Object -First 1)
        ($succeeded.Count -gt 0) | Should Be $true
        [string]$succeeded[0].reasons[0].code | Should Be "perception_context_uncertain_dry_run"
        [string]$succeeded[0].correlation.source_context | Should Be "workspace/uncertain-zone"
    }

    It "unsafe perception action is blocked" {
        $paths = New-TestPaths

        $evt = @{
            event_id = "evt-p-unsafe-001"
            event_type = "execution.requested"
            occurred_at = "2026-03-12T00:00:00Z"
            producer = @{ system = "MIM"; component = "perception"; role = "reasoning_runtime" }
            correlation = @{ trace_id = "trace-p-unsafe"; execution_id = "exec-p-unsafe"; source_domain = "workspace.perception"; source_context = "workspace/unsafe-zone" }
            payload = @{ runtime_action = "get-engineering-loop-summary"; perception_context = @{ state = "clear"; safety = "unsafe"; context_id = "workspace/unsafe-zone" } }
        } | ConvertTo-Json -Depth 12 -Compress

        $result = Invoke-Adapter -Paths $paths -AdapterAction "consume-event" -InputParams @{ EventJson = $evt }
        [bool]$result.ok | Should Be $false
        [string]$result.status | Should Be "rejected_domain_policy"

        $streamEvents = Get-StreamEvents -StreamPath $paths.Stream
        $blocked = @($streamEvents | Where-Object { [string]$_.event_type -eq "execution.guardrail_blocked" } | Select-Object -First 1)
        ($blocked.Count -gt 0) | Should Be $true
        [string]$blocked[0].reasons[0].code | Should Be "perception_unsafe_action_blocked"
        [string]$blocked[0].correlation.source_context | Should Be "workspace/unsafe-zone"
    }

    It "source context and reason codes are preserved in summary and handoff sample" {
        (Test-Path -Path $sampleScriptPath) | Should Be $true
        $null = & $sampleScriptPath -RunSampleLoop

        (Test-Path -Path $sampleArtifactPath) | Should Be $true
        $sample = Get-Content -Path $sampleArtifactPath -Raw | ConvertFrom-Json

        [string]$sample.type | Should Be "tod_perception_workspace_execution_sample"
        [string]$sample.bounded_execution_flow.source_domain | Should Be "workspace.perception"
        [string]$sample.bounded_execution_flow.source_context | Should Be "workspace/mainboard"
        ($null -ne $sample.bounded_execution_flow.summary_entry) | Should Be $true
        [string]$sample.bounded_execution_flow.summary_entry.source_domain | Should Be "workspace.perception"
        [string]$sample.bounded_execution_flow.summary_entry.source_context | Should Be "workspace/mainboard"
        (@($sample.bounded_execution_flow.lifecycle_reason_codes) -contains "perception_workspace_action_allowed") | Should Be $true
    }
}
