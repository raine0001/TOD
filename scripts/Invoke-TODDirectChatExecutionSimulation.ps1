param(
    [string]$OutputRoot,
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$todScript = Join-Path $PSScriptRoot 'TOD.ps1'

function Write-JsonNoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Payload
    )

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, ($Payload | ConvertTo-Json -Depth 30), $utf8NoBom)
}

function Read-JsonIfExists {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -Path $Path)) {
        return $null
    }

    return (Get-Content -Path $Path -Raw | ConvertFrom-Json)
}

function New-SimulationFixture {
    param([string]$Name)

    $root = if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
        Join-Path $repoRoot ('tod/out/tests/direct-chat-execution-simulation-' + [guid]::NewGuid().ToString('N'))
    }
    else {
        Join-Path ([System.IO.Path]::GetFullPath($OutputRoot)) $Name
    }

    New-Item -ItemType Directory -Path $root -Force | Out-Null
    $statePath = Join-Path $root 'state.json'
    $configPath = Join-Path $root 'tod-config.json'
    $readinessPath = Join-Path $root 'tod_execution_readiness.latest.json'
    $historyPath = Join-Path $root 'tod_execution_readiness_history.latest.json'
    $sharedA = Join-Path $root 'runtime/shared'
    $sharedB = Join-Path $root 'tmp_remote_mim/runtime/shared'
    $bridgePath = Join-Path $root 'listener/MIM_TOD_TASK_REQUEST.latest.json'
    $promptOut = Join-Path $root 'prompts'

    Write-JsonNoBom -Path $statePath -Payload ([pscustomobject]@{
            objectives = @()
            tasks = @()
            execution_results = @()
            review_decisions = @()
            journal = @()
            engine_performance = [pscustomobject]@{ records = @(); updated_at = '' }
            routing_decisions = [pscustomobject]@{ records = @(); updated_at = '' }
            routing_feedback = [pscustomobject]@{ learned_weights = [pscustomobject]@{}; sample_size = 0; version = 'feedback_v1'; updated_at = '' }
            sync_state = [pscustomobject]@{ expected_contract_version = ''; expected_schema_version = ''; local_repo_signature = ''; cached_manifest = $null; last_comparison = $null; last_sync_decision = ''; last_sync_code = ''; compared_at = '' }
        })

    Write-JsonNoBom -Path $readinessPath -Payload ([pscustomobject]@{
            generated_at = (Get-Date).ToUniversalTime().ToString('o')
            summary = [pscustomobject]@{ passed_all = $true; exit_code = 0 }
        })

    Write-JsonNoBom -Path $configPath -Payload ([pscustomobject]@{
            mode = 'local'
            fallback_to_local = $true
            timeout_seconds = 30
            engineering_loop = [pscustomobject]@{
                max_run_history = 150
                max_scorecard_history = 150
                max_cycle_records = 300
            }
            execution_engine = [pscustomobject]@{
                active = 'local'
                fallback = 'local'
                allow_fallback = $true
                readiness_policy = [pscustomobject]@{
                    enabled = $false
                    signal_path = $readinessPath
                    history_path = $historyPath
                    max_artifact_age_minutes = 30
                    display_max_artifact_age_minutes = 10
                    block_actions = @()
                    degrade_actions = @()
                    block_states = @()
                    degrade_states = @()
                    degrade_apply_plan = $false
                    history_max_entries = 50
                }
            }
        })

    foreach ($sharedRoot in @($sharedA, $sharedB)) {
        New-Item -ItemType Directory -Path $sharedRoot -Force | Out-Null
    }

    return [pscustomobject]@{
        Name = $Name
        Root = $root
        StatePath = $statePath
        ConfigPath = $configPath
        SharedRoots = @($sharedA, $sharedB)
        BridgePath = $bridgePath
        PromptOut = $promptOut
    }
}

function Set-SimulationActiveLane {
    param(
        [Parameter(Mandatory = $true)]$Fixture,
        [Parameter(Mandatory = $true)][string]$TaskId,
        [Parameter(Mandatory = $true)][string]$ObjectiveId,
        [string]$RequestId = '',
        [string]$Status = 'active',
        [string]$Priority = 'operator_direct_objective',
        [string]$Source = 'operator_chat'
    )

    $lane = [pscustomobject]@{
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        packet_type = 'tod-active-execution-lane-v1'
        request_id = if ([string]::IsNullOrWhiteSpace($RequestId)) { 'REQ-' + $TaskId } else { $RequestId }
        task_id = $TaskId
        objective_id = $ObjectiveId
        source = $Source
        priority = $Priority
        status = $Status
        started_at = (Get-Date).ToUniversalTime().ToString('o')
        relation_to_previous_active = 'new'
        previous_active_task_id = ''
    }

    foreach ($sharedRoot in @($Fixture.SharedRoots)) {
        Write-JsonNoBom -Path (Join-Path $sharedRoot 'TOD_ACTIVE_EXECUTION_LANE.latest.json') -Payload $lane
    }
}

function Invoke-SimulatedDirectChat {
    param(
        [Parameter(Mandatory = $true)]$Fixture,
        [Parameter(Mandatory = $true)][string]$CaseId,
        [Parameter(Mandatory = $true)][string]$TaskId,
        [Parameter(Mandatory = $true)][string]$RequestId,
        [Parameter(Mandatory = $true)][string]$ObjectiveId,
        [Parameter(Mandatory = $true)][string]$Scope,
        [string]$Title = '',
        [string]$TaskCategory = 'chat_execution',
        [string]$ExecutionMode = 'sync'
    )

    $oldSharedRoots = $env:TOD_EXECUTION_SHARED_ROOTS
    $oldBridgePath = $env:TOD_BRIDGE_REQUEST_PACKET_PATH
    $oldPromptOut = $env:TOD_PROMPT_OUT_DIR
    try {
        $env:TOD_EXECUTION_SHARED_ROOTS = [string]::Join(';', @($Fixture.SharedRoots))
        $env:TOD_BRIDGE_REQUEST_PACKET_PATH = [string]$Fixture.BridgePath
        $env:TOD_PROMPT_OUT_DIR = [string]$Fixture.PromptOut
        $resolvedTitle = if ([string]::IsNullOrWhiteSpace($Title)) { $CaseId } else { $Title }
        $raw = & $todScript -Action execute-chat-task `
            -ConfigPath $Fixture.ConfigPath `
            -StatePath $Fixture.StatePath `
            -ObjectiveId $ObjectiveId `
            -TaskId $TaskId `
            -RequestId $RequestId `
            -CorrelationId $RequestId `
            -Title $resolvedTitle `
            -Description $Scope `
            -Scope $Scope `
            -AcceptanceCriteria 'Simulation request must publish exact execution state.' `
            -SuccessCriteria 'Simulation request must publish exact execution state.' `
            -AssignedExecutor local `
            -TaskCategory $TaskCategory `
            -ExecutionMode $ExecutionMode | Out-String

        return ($raw | ConvertFrom-Json)
    }
    finally {
        $env:TOD_EXECUTION_SHARED_ROOTS = $oldSharedRoots
        $env:TOD_BRIDGE_REQUEST_PACKET_PATH = $oldBridgePath
        $env:TOD_PROMPT_OUT_DIR = $oldPromptOut
    }
}

function Get-SimulationStates {
    param(
        [Parameter(Mandatory = $true)]$Fixture,
        [Parameter(Mandatory = $true)]$Result,
        [bool]$ListenerConsumed = $false
    )

    $activity = @()
    if ($Result -and $Result.PSObject.Properties['activity_event_types']) {
        $activity = @($Result.activity_event_types | ForEach-Object { [string]$_ })
    }
    $requestPaths = if ($Result -and $Result.PSObject.Properties['request_artifact_paths']) { @($Result.request_artifact_paths) } else { @() }
    $runTask = if ($Result -and $Result.PSObject.Properties['run_task']) { $Result.run_task } else { $null }
    $engineInvocation = if ($runTask -and $runTask.PSObject.Properties['engine_invocation']) { $runTask.engine_invocation } else { $null }
    $engineResult = if ($engineInvocation -and $engineInvocation.PSObject.Properties['result']) { $engineInvocation.result } else { $null }
    $materialization = $null
    if ($engineResult -and $engineResult.PSObject.Properties['raw_output'] -and $engineResult.raw_output -and $engineResult.raw_output.PSObject.Properties['materialization']) {
        $materialization = $engineResult.raw_output.materialization
    }

    [pscustomobject]@{
        request_received = ($null -ne $Result -and -not [string]::IsNullOrWhiteSpace([string]$Result.request_id))
        request_claimed = ($activity -contains 'task_claimed')
        request_published = (@($requestPaths | Where-Object { Test-Path -Path ([string]$_) }).Count -gt 0)
        listener_consumed = [bool]$ListenerConsumed
        slice_materialized = ($activity -contains 'bounded_edit_materialized')
        local_execution_started = ($activity -contains 'local_executor_invoked')
        local_execution_completed = ($activity -contains 'local_executor_completed')
        local_execution_blocked_with_exact_reason = (($activity -contains 'bounded_edit_mode_missing') -or ($activity -contains 'blocked_missing_local_executor_result') -or ($engineResult -and $engineResult.PSObject.Properties['reason_code'] -and -not [string]::IsNullOrWhiteSpace([string]$engineResult.reason_code)))
        materialization = $materialization
        run_task_decision = if ($runTask -and $runTask.PSObject.Properties['decision']) { [string]$runTask.decision } else { '' }
        run_task_reason_code = if ($runTask -and $runTask.PSObject.Properties['reason_code']) { [string]$runTask.reason_code } elseif ($engineResult -and $engineResult.PSObject.Properties['reason_code']) { [string]$engineResult.reason_code } else { '' }
    }
}

function New-ScenarioResult {
    param(
        [string]$Name,
        [Parameter(Mandatory = $true)]$Fixture,
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)]$States,
        [hashtable]$Assertions
    )

    $failures = New-Object System.Collections.Generic.List[string]
    foreach ($key in @($Assertions.Keys)) {
        $actual = $States.$key
        if ($null -eq $actual -and $Result.PSObject.Properties[$key]) {
            $actual = $Result.$key
        }
        if ($actual -ne $Assertions[$key]) {
            [void]$failures.Add(('{0}: expected {1}, got {2}' -f $key, $Assertions[$key], $actual))
        }
    }

    [pscustomobject]@{
        name = $Name
        passed = (@($failures).Count -eq 0)
        failures = @($failures)
        fixture_root = [string]$Fixture.Root
        task_id = if ($Result.PSObject.Properties['task_id']) { [string]$Result.task_id } else { '' }
        decision = if ($Result.PSObject.Properties['intake_arbitration']) { [string]$Result.intake_arbitration.decision } else { '' }
        reason = if ($Result.PSObject.Properties['intake_arbitration']) { [string]$Result.intake_arbitration.reason } else { '' }
        activity_event_types = if ($Result.PSObject.Properties['activity_event_types']) { @($Result.activity_event_types) } else { @() }
        states = $States
        result = $Result
    }
}

$scenarios = New-Object System.Collections.Generic.List[object]

$fixture1 = New-SimulationFixture -Name 'case-01-new-direct-chat-implementation-request'
$result1 = Invoke-SimulatedDirectChat -Fixture $fixture1 -CaseId 'case-01' -TaskId 'TSKCHAT-SIM-NEW-IMPLEMENTATION' -RequestId 'REQ-SIM-NEW-IMPLEMENTATION' -ObjectiveId 'OBJ-SIM-NEW-IMPLEMENTATION' -Scope "OBJECTIVE: Simulate a direct-chat implementation request that needs materialization`nTarget File: README.md"
$states1 = Get-SimulationStates -Fixture $fixture1 -Result $result1
[void]$scenarios.Add((New-ScenarioResult -Name 'new direct-chat implementation request' -Fixture $fixture1 -Result $result1 -States $states1 -Assertions @{ request_received = $true; request_published = $true; local_execution_started = $false; local_execution_blocked_with_exact_reason = $true }))

$fixture2 = New-SimulationFixture -Name 'case-02-duplicate-active-request'
Set-SimulationActiveLane -Fixture $fixture2 -TaskId 'TSKCHAT-SIM-DUP-ACTIVE' -ObjectiveId 'OBJ-SIM-DUP-ACTIVE' -RequestId 'REQ-SIM-DUP-ACTIVE'
$result2 = Invoke-SimulatedDirectChat -Fixture $fixture2 -CaseId 'case-02' -TaskId 'TSKCHAT-SIM-DUP-ACTIVE' -RequestId 'REQ-SIM-DUP-ACTIVE' -ObjectiveId 'OBJ-SIM-DUP-ACTIVE' -Scope 'OBJECTIVE: Duplicate active request'
$states2 = Get-SimulationStates -Fixture $fixture2 -Result $result2
[void]$scenarios.Add((New-ScenarioResult -Name 'duplicate active request' -Fixture $fixture2 -Result $result2 -States $states2 -Assertions @{ request_received = $true; request_published = $false }))

$fixture3 = New-SimulationFixture -Name 'case-03-duplicate-completed-request'
$scope3 = "OBJECTIVE: Duplicate completed request`nTarget File: README.md`nEdit Mode: validation_only`nValidation Pattern: TOD"
$first3 = Invoke-SimulatedDirectChat -Fixture $fixture3 -CaseId 'case-03' -TaskId 'TSKCHAT-SIM-DUP-COMPLETED' -RequestId 'REQ-SIM-DUP-COMPLETED' -ObjectiveId 'OBJ-SIM-DUP-COMPLETED' -Scope $scope3 -Title 'case-03 duplicate completed request'
Set-SimulationActiveLane -Fixture $fixture3 -TaskId 'TSKCHAT-SIM-DUP-COMPLETED' -ObjectiveId 'OBJ-SIM-DUP-COMPLETED' -RequestId 'REQ-SIM-DUP-COMPLETED' -Status 'completed'
$result3 = Invoke-SimulatedDirectChat -Fixture $fixture3 -CaseId 'case-03' -TaskId 'TSKCHAT-SIM-DUP-COMPLETED' -RequestId 'REQ-SIM-DUP-COMPLETED' -ObjectiveId 'OBJ-SIM-DUP-COMPLETED' -Scope $scope3 -Title 'case-03 duplicate completed request'
$states3 = Get-SimulationStates -Fixture $fixture3 -Result $result3
[void]$scenarios.Add((New-ScenarioResult -Name 'duplicate completed request' -Fixture $fixture3 -Result $result3 -States $states3 -Assertions @{ request_received = $true; request_published = $false }))

$fixture4 = New-SimulationFixture -Name 'case-04-duplicate-queued-request'
Set-SimulationActiveLane -Fixture $fixture4 -TaskId 'TSKCHAT-SIM-ACTIVE-BLOCKING-QUEUE' -ObjectiveId 'OBJ-SIM-ACTIVE-BLOCKING-QUEUE'
$scope4 = 'OBJECTIVE: Duplicate queued request'
$first4 = Invoke-SimulatedDirectChat -Fixture $fixture4 -CaseId 'case-04' -TaskId 'TSKCHAT-SIM-DUP-QUEUED' -RequestId 'REQ-SIM-DUP-QUEUED' -ObjectiveId 'OBJ-SIM-DUP-QUEUED' -Scope $scope4 -Title 'case-04 duplicate queued request' -ExecutionMode async
$result4 = Invoke-SimulatedDirectChat -Fixture $fixture4 -CaseId 'case-04' -TaskId 'TSKCHAT-SIM-DUP-QUEUED' -RequestId 'REQ-SIM-DUP-QUEUED' -ObjectiveId 'OBJ-SIM-DUP-QUEUED' -Scope $scope4 -Title 'case-04 duplicate queued request' -ExecutionMode async
$states4 = Get-SimulationStates -Fixture $fixture4 -Result $result4
[void]$scenarios.Add((New-ScenarioResult -Name 'duplicate queued request' -Fixture $fixture4 -Result $result4 -States $states4 -Assertions @{ request_received = $true; request_published = $false }))

$fixture5 = New-SimulationFixture -Name 'case-05-same-task-id-different-payload'
Set-SimulationActiveLane -Fixture $fixture5 -TaskId 'TSKCHAT-SIM-ACTIVE-CONFLICT' -ObjectiveId 'OBJ-SIM-ACTIVE-CONFLICT'
$first5 = Invoke-SimulatedDirectChat -Fixture $fixture5 -CaseId 'case-05-first' -TaskId 'TSKCHAT-SIM-IDEMPOTENCY-CONFLICT' -RequestId 'REQ-SIM-IDEMPOTENCY-CONFLICT' -ObjectiveId 'OBJ-SIM-IDEMPOTENCY-CONFLICT' -Scope 'OBJECTIVE: First payload for idempotency conflict' -ExecutionMode async
$result5 = Invoke-SimulatedDirectChat -Fixture $fixture5 -CaseId 'case-05-second' -TaskId 'TSKCHAT-SIM-IDEMPOTENCY-CONFLICT' -RequestId 'REQ-SIM-IDEMPOTENCY-CONFLICT' -ObjectiveId 'OBJ-SIM-IDEMPOTENCY-CONFLICT' -Scope 'OBJECTIVE: Different payload for idempotency conflict' -ExecutionMode async
$states5 = Get-SimulationStates -Fixture $fixture5 -Result $result5
[void]$scenarios.Add((New-ScenarioResult -Name 'same task_id with different payload' -Fixture $fixture5 -Result $result5 -States $states5 -Assertions @{ request_received = $true; request_published = $false }))

$fixture6 = New-SimulationFixture -Name 'case-06-publication-without-listener-consumption'
$result6 = Invoke-SimulatedDirectChat -Fixture $fixture6 -CaseId 'case-06' -TaskId 'TSKCHAT-SIM-PUBLISH-NO-LISTENER' -RequestId 'REQ-SIM-PUBLISH-NO-LISTENER' -ObjectiveId 'OBJ-SIM-PUBLISH-NO-LISTENER' -Scope 'OBJECTIVE: Publication without listener consumption'
$states6 = Get-SimulationStates -Fixture $fixture6 -Result $result6 -ListenerConsumed:$false
[void]$scenarios.Add((New-ScenarioResult -Name 'request publication without listener consumption' -Fixture $fixture6 -Result $result6 -States $states6 -Assertions @{ request_published = $true; listener_consumed = $false; local_execution_started = $false }))

$fixture7 = New-SimulationFixture -Name 'case-07-listener-consumed-without-slice-materialization'
$result7 = Invoke-SimulatedDirectChat -Fixture $fixture7 -CaseId 'case-07' -TaskId 'TSKCHAT-SIM-LISTENER-NO-SLICE' -RequestId 'REQ-SIM-LISTENER-NO-SLICE' -ObjectiveId 'OBJ-SIM-LISTENER-NO-SLICE' -Scope "OBJECTIVE: Listener consumed but no slice materialized`nTarget File: README.md"
$states7 = Get-SimulationStates -Fixture $fixture7 -Result $result7 -ListenerConsumed:$true
[void]$scenarios.Add((New-ScenarioResult -Name 'listener consumption without slice materialization' -Fixture $fixture7 -Result $result7 -States $states7 -Assertions @{ listener_consumed = $true; slice_materialized = $false; local_execution_blocked_with_exact_reason = $true }))

$fixture8 = New-SimulationFixture -Name 'case-08-missing-local-execution-binding'
$result8 = Invoke-SimulatedDirectChat -Fixture $fixture8 -CaseId 'case-08' -TaskId 'TSKCHAT-SIM-MISSING-BINDING' -RequestId 'REQ-SIM-MISSING-BINDING' -ObjectiveId 'OBJ-SIM-MISSING-BINDING' -Scope 'OBJECTIVE: Missing LocalExecutionEngine binding evidence'
$states8 = Get-SimulationStates -Fixture $fixture8 -Result $result8
[void]$scenarios.Add((New-ScenarioResult -Name 'missing LocalExecutionEngine binding' -Fixture $fixture8 -Result $result8 -States $states8 -Assertions @{ local_execution_blocked_with_exact_reason = $true; local_execution_started = $false }))

$fixture9 = New-SimulationFixture -Name 'case-09-successful-slice-materialization'
$scope9 = "OBJECTIVE: Successful slice materialization`nTarget File: README.md`nEdit Mode: validation_only`nValidation Pattern: TOD"
$result9 = Invoke-SimulatedDirectChat -Fixture $fixture9 -CaseId 'case-09' -TaskId 'TSKCHAT-SIM-SLICE-MATERIALIZED' -RequestId 'REQ-SIM-SLICE-MATERIALIZED' -ObjectiveId 'OBJ-SIM-SLICE-MATERIALIZED' -Scope $scope9
$states9 = Get-SimulationStates -Fixture $fixture9 -Result $result9
[void]$scenarios.Add((New-ScenarioResult -Name 'successful slice materialization' -Fixture $fixture9 -Result $result9 -States $states9 -Assertions @{ slice_materialized = $true; request_published = $true }))

$fixture10 = New-SimulationFixture -Name 'case-10-successful-local-execution-handoff'
$scope10 = "OBJECTIVE: Successful local execution handoff`nTarget File: README.md`nEdit Mode: validation_only`nValidation Pattern: TOD"
$result10 = Invoke-SimulatedDirectChat -Fixture $fixture10 -CaseId 'case-10' -TaskId 'TSKCHAT-SIM-LOCAL-HANDOFF' -RequestId 'REQ-SIM-LOCAL-HANDOFF' -ObjectiveId 'OBJ-SIM-LOCAL-HANDOFF' -Scope $scope10
$states10 = Get-SimulationStates -Fixture $fixture10 -Result $result10
[void]$scenarios.Add((New-ScenarioResult -Name 'successful local execution handoff' -Fixture $fixture10 -Result $result10 -States $states10 -Assertions @{ slice_materialized = $true; local_execution_started = $true; local_execution_completed = $true }))

$failed = @($scenarios.ToArray() | Where-Object { -not [bool]$_.passed })
$summary = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    passed = (@($failed).Count -eq 0)
    scenario_count = @($scenarios.ToArray()).Count
    failed_count = @($failed).Count
    output_root = if ([string]::IsNullOrWhiteSpace($OutputRoot)) { '' } else { [System.IO.Path]::GetFullPath($OutputRoot) }
    shared_roots_sandboxed = $true
    production_shared_roots_modified = $false
    scenarios = @($scenarios.ToArray())
}

if ($AsJson) {
    $summary | ConvertTo-Json -Depth 40
}
else {
    $summary
}

if (-not [bool]$summary.passed) {
    exit 1
}
