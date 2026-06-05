Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$todScript = Join-Path $repoRoot 'scripts/TOD.ps1'

function Import-TodFunction {
    param([Parameter(Mandatory = $true)][string]$Name)

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($todScript, [ref]$tokens, [ref]$errors)
    if (@($errors).Count -gt 0) {
        throw "Failed to parse $todScript"
    }

    $fnAst = $ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name
    }, $true)

    if ($null -eq $fnAst) {
        throw "Function '$Name' not found in $todScript"
    }

    $definition = $fnAst.Extent.Text -replace ("function\s+{0}\b" -f [regex]::Escape($Name)), ("function global:{0}" -f $Name)
    . ([scriptblock]::Create($definition))
}

function Write-TestJson {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Payload
    )

    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -Path $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    [System.IO.File]::WriteAllText($Path, ($Payload | ConvertTo-Json -Depth 20), (New-Object System.Text.UTF8Encoding($false)))
}

function Read-TestJson {
    param([Parameter(Mandatory = $true)][string]$Path)

    return (Get-Content -Raw -Path $Path | ConvertFrom-Json)
}

function New-CanonicalSharedTruth {
    return [ordered]@{
        generated_at = '2026-05-05T02:14:44.123470Z'
        state = 'DISAGREEMENT'
        objective_id = '2913'
        task_id = 'objective-2913-task-7144'
        request_id = 'objective-2913-task-7144'
        canonical_lane_source = 'formal_program_truth'
        authoritative_next_action = 'preserve canonical MIM lane and clear stale non-matching TOD artifacts'
    }
}

function New-StaleSelectionPayload {
    return [ordered]@{
        generated_at = '2026-05-05T01:12:08.0248793Z'
        source = 'tod-next-task-selection-v1'
        source_objective = 'OBJ-0631'
        selected_task_id = 'TSK-0891'
        reason_selected = 'Selected stale task.'
        request_id = 'tod-next-task-selection-TSK-0891-20260505011208024'
        selected_task_title = 'Re-check execution readiness'
        selected_task_scope = 'Execution readiness artifact is older than policy allows.'
        selection_kind = 'same_objective_next_task'
        expected_evidence = @('meaningful_execution_evidence')
        validation_plan = @('codex-wrapper execution handoff')
    }
}

function New-CanonicalActiveTaskPayload {
    return [ordered]@{
        generated_at = '2026-05-05T02:15:00.0000000Z'
        source = 'canonical-fixture'
        request_id = 'objective-2913-task-7144'
        task_id = 'objective-2913-task-7144'
        objective_id = '2913'
        title = 'Canonical active task'
        status = 'active'
    }
}

function New-StaleExecutionTask {
    return [pscustomobject]@{
        id = 'TSK-0891'
        objective_id = 'OBJ-0631'
        title = 'Re-check execution readiness'
        scope = 'Execution readiness artifact is older than policy allows.'
        type = 'implementation'
        task_category = 'code_change'
    }
}

function New-StaleExecutionPayload {
    return [pscustomobject]@{
        summary = 'Codex wrapper only accepted the packaged prompt without executing it.'
        files_changed = @()
        tests_run = @('codex-wrapper package-path check')
        test_results = @('pass')
        failures = @()
        recommendations = @()
        structured_findings = @()
        needs_escalation = $false
    }
}

Describe 'TOD canonical lane publisher gate' {
    BeforeAll {
        Import-TodFunction -Name 'Resolve-TaskCategory'
        Import-TodFunction -Name 'Get-NormalizedObjectiveToken'
        Import-TodFunction -Name 'Get-TodObjectValue'
        Import-TodFunction -Name 'Get-TodActivityStreamEventLimit'
        Import-TodFunction -Name 'Get-TodTaskIdentity'
        Import-TodFunction -Name 'New-TodActivityEventRecord'
        Import-TodFunction -Name 'Convert-TodActivityPayloadToStream'
        Import-TodFunction -Name 'Merge-TodActivityStreamPayload'
        Import-TodFunction -Name 'Write-TodExecutionJsonAtomically'
        Import-TodFunction -Name 'Read-TodExecutionJsonIfExists'
        Import-TodFunction -Name 'Get-TodParsedUtcDateTime'
        Import-TodFunction -Name 'Get-TodExecutionArtifactLane'
        Import-TodFunction -Name 'Get-TodCanonicalPublishContext'
        Import-TodFunction -Name 'Test-TodCanonicalLaneTerminal'
        Import-TodFunction -Name 'Test-TodArtifactMatchesCanonicalLane'
        Import-TodFunction -Name 'Test-TodLatestArtifactPublishGate'
        Import-TodFunction -Name 'Write-TodBlockedLatestArtifactRecord'
        Import-TodFunction -Name 'Write-TodExecutionSharedJson'
        Import-TodFunction -Name 'Publish-TodNextTaskSelectionArtifacts'
        Import-TodFunction -Name 'Get-LocalExecutionValidationChecks'
        Import-TodFunction -Name 'Get-LocalExecutionCommandCapture'
        Import-TodFunction -Name 'Get-LocalExecutionRollbackState'
        Import-TodFunction -Name 'Resolve-LocalExecutionTaskClass'
        Import-TodFunction -Name 'Test-LocalExecutionPatchRequired'
        Import-TodFunction -Name 'Get-TodMaterialImplementationProofAssessment'
        Import-TodFunction -Name 'Get-LocalExecutionNoOpAssessment'
        Import-TodFunction -Name 'Publish-LocalExecutionArtifacts'

        function global:Publish-RemoteTodExecutionArtifacts {
            param([string[]]$LocalArtifactPaths)
            $script:RemotePublishCalls += ,@($LocalArtifactPaths)
            return [pscustomobject]@{ attempted = $true; published = $false; reason = 'stubbed_for_pester' }
        }
    }

    BeforeEach {
        $script:sharedRoot = Join-Path $repoRoot ('tod/out/tests/canonical-gate-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:sharedRoot -Force | Out-Null
        $script:RemotePublishCalls = @()

        function global:Get-TodExecutionSharedRoots {
            return ,$script:sharedRoot
        }

        function global:Get-UtcNow {
            return '2026-05-05T01:13:13.3904356Z'
        }

        Write-TestJson -Path (Join-Path $script:sharedRoot 'TOD_MIM_SHARED_TRUTH.latest.json') -Payload (New-CanonicalSharedTruth)
    }

    AfterEach {
        if (Test-Path -Path $script:sharedRoot) {
            Remove-Item -Path $script:sharedRoot -Recurse -Force
        }
        Remove-Item function:\Get-TodExecutionSharedRoots -ErrorAction SilentlyContinue
        Remove-Item function:\Get-UtcNow -ErrorAction SilentlyContinue
    }

    It 'blocks stale 0631 next-task publication when shared truth anchors to objective 2913' {
        Write-TestJson -Path (Join-Path $script:sharedRoot 'TOD_ACTIVE_TASK.latest.json') -Payload (New-CanonicalActiveTaskPayload)

        $selectionPayload = New-StaleSelectionPayload
        $selectedTask = [pscustomobject]@{
            id = 'TSK-0891'
            objective_id = 'OBJ-0631'
            title = 'Re-check execution readiness'
            scope = 'Execution readiness artifact is older than policy allows.'
        }

        $null = Publish-TodNextTaskSelectionArtifacts -SelectionPayload $selectionPayload -SelectedTask $selectedTask -RequestId 'tod-next-task-selection-TSK-0891-20260505011208024'

        $activeTask = Read-TestJson -Path (Join-Path $script:sharedRoot 'TOD_ACTIVE_TASK.latest.json')
        [string]$activeTask.objective_id | Should Be '2913'
        [string]$activeTask.task_id | Should Be 'objective-2913-task-7144'

        $blockedRecord = Read-TestJson -Path (Join-Path $script:sharedRoot 'superseded/TOD_ACTIVE_TASK.latest.json/latest.blocked.json')
        [string]$blockedRecord.reason_code | Should Be 'stale_publisher_noncanonical_lane'
        [string]$blockedRecord.outgoing_lane.objective_id | Should Be 'OBJ-0631'

        @($script:RemotePublishCalls).Count | Should Be 0
    }

    It 'allows matching canonical next-task publication' {
        function global:Get-UtcNow {
            return '2026-05-05T02:15:30.0000000Z'
        }

        $selectionPayload = [ordered]@{
            generated_at = '2026-05-05T02:15:30.0000000Z'
            source = 'tod-next-task-selection-v1'
            source_objective = '2913'
            selected_task_id = 'objective-2913-task-7144'
            reason_selected = 'Selected canonical task.'
            request_id = 'objective-2913-task-7144'
            selected_task_title = 'Canonical active task'
            selected_task_scope = 'Canonical scope'
            selection_kind = 'same_objective_next_task'
            expected_evidence = @('meaningful_execution_evidence')
            validation_plan = @('focused validation')
        }
        $selectedTask = [pscustomobject]@{
            id = 'objective-2913-task-7144'
            objective_id = '2913'
            title = 'Canonical active task'
            scope = 'Canonical scope'
        }

        $null = Publish-TodNextTaskSelectionArtifacts -SelectionPayload $selectionPayload -SelectedTask $selectedTask -RequestId 'objective-2913-task-7144'

        $activeTask = Read-TestJson -Path (Join-Path $script:sharedRoot 'TOD_ACTIVE_TASK.latest.json')
        [string]$activeTask.objective_id | Should Be '2913'
        [string]$activeTask.task_id | Should Be 'objective-2913-task-7144'
        (Test-Path -Path (Join-Path $script:sharedRoot 'superseded/TOD_ACTIVE_TASK.latest.json/latest.blocked.json')) | Should Be $false
        @($script:RemotePublishCalls).Count | Should Be 0
    }

    It 'allows newer explicit override publication only when the override marker is present' {
        $path = Join-Path $script:sharedRoot 'TOD_ACTIVE_TASK.latest.json'

        $blockedPayload = [ordered]@{
            generated_at = '2026-05-05T03:00:00.0000000Z'
            source = 'tod.local.run-task'
            request_id = 'override-without-marker'
            task_id = 'TSK-OVERRIDE-1'
            objective_id = 'OBJ-0631'
            title = 'Blocked override'
        }
        $blockedWrite = Write-TodExecutionSharedJson -Path $path -Payload $blockedPayload
        [bool]$blockedWrite.blocked | Should Be $true

        $allowedPayload = [ordered]@{
            generated_at = '2026-05-05T03:05:00.0000000Z'
            source = 'tod.local.run-task'
            request_id = 'override-with-marker'
            task_id = 'TSK-OVERRIDE-2'
            objective_id = 'OBJ-0631'
            title = 'Allowed override'
            publish_override_marker = 'operator-approved-canonical-shift'
        }
        $allowedWrite = Write-TodExecutionSharedJson -Path $path -Payload $allowedPayload
        [bool]$allowedWrite.written | Should Be $true

        $written = Read-TestJson -Path $path
        [string]$written.request_id | Should Be 'override-with-marker'
        [string]$written.publish_override_marker | Should Be 'operator-approved-canonical-shift'
    }

    It 'allows newer execution after the canonical lane is terminal' {
        $sharedTruth = New-CanonicalSharedTruth
        $sharedTruth.state = 'ACCEPTED_COMPLETE'
        $sharedTruth.execution_state = 'completed'
        Write-TestJson -Path (Join-Path $script:sharedRoot 'TOD_MIM_SHARED_TRUTH.latest.json') -Payload $sharedTruth

        $path = Join-Path $script:sharedRoot 'TOD_EXECUTION_RESULT.latest.json'
        $payload = [ordered]@{
            generated_at = '2026-05-05T03:10:00.0000000Z'
            source = 'tod.local.run-task'
            request_id = 'TSK-FRESH-1'
            task_id = 'TSK-FRESH-1'
            objective_id = 'TOD-SAFE-LOCAL-PATCH-APPLICATION-V1'
            title = 'Fresh successor execution'
            status = 'completed'
            execution_state = 'completed'
        }

        $writeResult = Write-TodExecutionSharedJson -Path $path -Payload $payload

        [bool]$writeResult.written | Should Be $true
        [bool]$writeResult.blocked | Should Be $false
        $written = Read-TestJson -Path $path
        [string]$written.task_id | Should Be 'TSK-FRESH-1'
        (Test-Path -Path (Join-Path $script:sharedRoot 'superseded/TOD_EXECUTION_RESULT.latest.json/latest.blocked.json')) | Should Be $false
    }

    It 'archives stale local execution publication and leaves shared truth unchanged' {
        Write-TestJson -Path (Join-Path $script:sharedRoot 'TOD_EXECUTION_RESULT.latest.json') -Payload ([ordered]@{
            generated_at = '2026-05-05T02:15:30.0000000Z'
            source = 'canonical-fixture'
            request_id = 'objective-2913-task-7144'
            task_id = 'objective-2913-task-7144'
            objective_id = '2913'
            status = 'completed'
        })
        $originalSharedTruth = Get-Content -Raw -Path (Join-Path $script:sharedRoot 'TOD_MIM_SHARED_TRUTH.latest.json')

        $task = New-StaleExecutionTask
        $result = New-StaleExecutionPayload
        $null = Publish-LocalExecutionArtifacts -Task $task -Objective $null -ResultPayload $result -ReviewDecision 'pass' -ExecutionId 'EXEC-0631' -PackagePath 'E:\TOD\tod\out\prompts\TSK-0891.md' -ExecutionReadiness ([pscustomobject]@{ status = 'valid' })

        $executionResult = Read-TestJson -Path (Join-Path $script:sharedRoot 'TOD_EXECUTION_RESULT.latest.json')
        [string]$executionResult.objective_id | Should Be '2913'
        [string]$executionResult.task_id | Should Be 'objective-2913-task-7144'

        $blockedRecord = Read-TestJson -Path (Join-Path $script:sharedRoot 'superseded/TOD_EXECUTION_RESULT.latest.json/latest.blocked.json')
        [string]$blockedRecord.reason_code | Should Be 'stale_publisher_noncanonical_lane'
        [string]$blockedRecord.outgoing_lane.objective_id | Should Be 'OBJ-0631'
        [string]$blockedRecord.outgoing_lane.task_id | Should Be 'TSK-0891'

        (Get-Content -Raw -Path (Join-Path $script:sharedRoot 'TOD_MIM_SHARED_TRUTH.latest.json')) | Should Be $originalSharedTruth
        @($script:RemotePublishCalls).Count | Should Be 0
    }
}
