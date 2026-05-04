Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$replayScript = Join-Path $repoRoot 'scripts/Invoke-TODForcedExecutionReplay.ps1'
$listenerScript = Join-Path $repoRoot 'scripts/Start-TODMimPacketListener.ps1'
$todScript = Join-Path $repoRoot 'scripts/TOD.ps1'

function Import-ScriptFunction {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$tokens, [ref]$errors)
    if (@($errors).Count -gt 0) {
        throw "Failed to parse $ScriptPath"
    }

    $fnAst = $ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name
    }, $true)

    if ($null -eq $fnAst) {
        throw "Function '$Name' not found in $ScriptPath"
    }

    $definition = $fnAst.Extent.Text -replace ("function\s+{0}\b" -f [regex]::Escape($Name)), ("function global:{0}" -f $Name)
    . ([scriptblock]::Create($definition))
}

function New-BaseReplayRequest {
    return [pscustomobject]@{
        request_id = 'objective-2913-task-7144-original'
        correlation_id = 'objective-2913-task-7144'
        objective_id = 'objective-2913'
        task_id = 'objective-2913-task-7144'
        sequence = 4641389
        title = 'Patch token extraction'
        scope = 'Patch token extraction so only the identifier value is captured.'
        command = [pscustomobject]@{
            name = 'run-task'
            args = [pscustomobject]@{
                objective_id = 2913
                task_id = 7144
            }
        }
        idempotency = [pscustomobject]@{
            key = 'objective-2913-task-7144-original'
            duplicate_execution_allowed = $false
        }
    }
}

Describe 'TOD forced execution replay' {
    BeforeAll {
        Import-ScriptFunction -ScriptPath $replayScript -Name 'Ensure-Directory'
        Import-ScriptFunction -ScriptPath $replayScript -Name 'Get-NormalizedObjectiveId'
        Import-ScriptFunction -ScriptPath $replayScript -Name 'Get-ReplayAttempt'
        Import-ScriptFunction -ScriptPath $replayScript -Name 'Get-UnixEpochMilliseconds'
        Import-ScriptFunction -ScriptPath $replayScript -Name 'Copy-LiveArtifactToArchive'
        Import-ScriptFunction -ScriptPath $replayScript -Name 'Archive-ForcedReplayArtifacts'
        Import-ScriptFunction -ScriptPath $replayScript -Name 'New-ForcedReplayRequest'
        Import-ScriptFunction -ScriptPath $replayScript -Name 'Update-ListenerStateForForcedReplay'

        Import-ScriptFunction -ScriptPath $listenerScript -Name 'Get-ScopedForcedReplayEntries'
        Import-ScriptFunction -ScriptPath $listenerScript -Name 'Get-ScopedForcedReplayMatch'

        Import-ScriptFunction -ScriptPath $todScript -Name 'Resolve-TaskCategory'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Get-LocalExecutionValidationChecks'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Get-LocalExecutionCommandCapture'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Get-LocalExecutionRollbackState'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Get-NormalizedObjectiveToken'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Resolve-LocalExecutionTaskClass'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Test-LocalExecutionPatchRequired'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Get-LocalExecutionNoOpAssessment'
    }

    It 'creates a fresh request_id for a forced replay' {
        $request = New-BaseReplayRequest

        $replayRequest = New-ForcedReplayRequest -ExistingRequest $request -ObjectiveId 'objective-2913' -TaskId 'objective-2913-task-7144' -Reason 'prior_no_op_execution'

        [string]$replayRequest.request_id | Should Not Be [string]$request.request_id
        [string]$replayRequest.request_id | Should Match 'objective-2913-task-7144-replay-1-'
        [string]$replayRequest.correlation_id | Should Be 'objective-2913-task-7144-replay-1'
        [int]$replayRequest.replay_attempt | Should Be 1
    }

    It 'archives prior live artifacts before overwrite' {
        $tempRoot = Join-Path $repoRoot ('tod/out/tests/forced-replay-' + [guid]::NewGuid().ToString('N'))
        $archiveRoot = Join-Path $tempRoot 'archive'
        New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
        Set-Content -Path (Join-Path $tempRoot 'MIM_TOD_TASK_REQUEST.latest.json') -Value '{"request_id":"old"}' -Encoding utf8
        Set-Content -Path (Join-Path $tempRoot 'listener_state.json') -Value '{"last_processed_request_id":"old"}' -Encoding utf8

        $archived = Archive-ForcedReplayArtifacts -ArtifactPaths @{
            request = (Join-Path $tempRoot 'MIM_TOD_TASK_REQUEST.latest.json')
            state = (Join-Path $tempRoot 'listener_state.json')
        } -ArchiveDir $archiveRoot

        @($archived).Count | Should Be 2
        (Test-Path -Path (Join-Path $archiveRoot 'MIM_TOD_TASK_REQUEST.latest.json')) | Should Be $true
        (Test-Path -Path (Join-Path $archiveRoot 'listener_state.json')) | Should Be $true

        Remove-Item -Path $tempRoot -Recurse -Force
    }

    It 'applies dedupe bypass only to the targeted replay request' {
        $state = [pscustomobject]@{
            last_processed_request_id = 'objective-2913-task-7144-original'
            last_processed_request_signature = 'sig-old'
            scoped_forced_replays = @()
        }

        $updated = Update-ListenerStateForForcedReplay -ListenerState $state -ObjectiveId 'objective-2913' -TaskId 'objective-2913-task-7144' -OriginalRequestId 'objective-2913-task-7144-original' -ReplayRequestId 'objective-2913-task-7144-replay-1-abc' -ReplayCorrelationId 'objective-2913-task-7144-replay-1' -ReplayAttempt 1 -Reason 'prior_no_op_execution'

        $targetMatch = Get-ScopedForcedReplayMatch -ListenerState $updated -RequestId 'objective-2913-task-7144-replay-1-abc' -TaskId 'objective-2913-task-7144' -ObjectiveId 'objective-2913'
        $otherMatch = Get-ScopedForcedReplayMatch -ListenerState $updated -RequestId 'objective-2914-task-8000-replay-1-abc' -TaskId 'objective-2914-task-8000' -ObjectiveId 'objective-2914'

        $null -ne $targetMatch | Should Be $true
        $null -eq $otherMatch | Should Be $true
        [string]$updated.last_processed_request_id | Should Be ''
        [string]$updated.last_processed_request_signature | Should Be ''
    }

    It 'keeps stale guard intact and scopes the replay override instead of globally clearing it' {
        $state = [pscustomobject]@{
            last_stale_guard = [pscustomobject]@{
                objective_id = 'objective-2900'
                task_id = 'objective-2900-task-7000'
            }
            scoped_forced_replays = @()
        }

        $updated = Update-ListenerStateForForcedReplay -ListenerState $state -ObjectiveId 'objective-2913' -TaskId 'objective-2913-task-7144' -OriginalRequestId 'objective-2913-task-7144-original' -ReplayRequestId 'objective-2913-task-7144-replay-1-abc' -ReplayCorrelationId 'objective-2913-task-7144-replay-1' -ReplayAttempt 1 -Reason 'prior_no_op_execution'

        [string]$updated.last_stale_guard.objective_id | Should Be 'objective-2900'
        @($updated.scoped_forced_replays).Count | Should Be 1
        [string]$updated.scoped_forced_replays[0].task_id | Should Be 'objective-2913-task-7144'
    }

    It 'requires fresh execution evidence before a replayed implementation task can complete' {
        $request = New-BaseReplayRequest
        $replayRequest = New-ForcedReplayRequest -ExistingRequest $request -ObjectiveId 'objective-2913' -TaskId 'objective-2913-task-7144' -Reason 'prior_no_op_execution'
        $task = [pscustomobject]@{
            id = 'objective-2913-task-7144'
            objective_id = 'objective-2913'
            title = 'Patch token extraction'
            scope = 'Patch token extraction so only the identifier value is captured.'
            type = 'implementation'
            task_category = 'code_change'
        }
        $result = [pscustomobject]@{
            summary = 'Replay wrapper completed without changing files.'
            files_changed = @()
            tests_run = @('contract-check')
            test_results = @('pass')
            failures = @()
            recommendations = @()
            structured_findings = @()
            needs_escalation = $false
        }

        $assessment = Get-LocalExecutionNoOpAssessment -Task $task -ResultPayload $result

        [bool]$replayRequest.replay_requires_fresh_execution_evidence | Should Be $true
        [bool]$replayRequest.execution_requirements.require_meaningful_evidence | Should Be $true
        [bool]$assessment.detected | Should Be $true
        [bool]$assessment.allows_authoritative_completion | Should Be $false
    }

    It 'preserves original lineage on the replay request' {
        $request = New-BaseReplayRequest

        $replayRequest = New-ForcedReplayRequest -ExistingRequest $request -ObjectiveId 'objective-2913' -TaskId 'objective-2913-task-7144' -Reason 'prior_no_op_execution'

        [string]$replayRequest.objective_id | Should Be 'objective-2913'
        [string]$replayRequest.task_id | Should Be 'objective-2913-task-7144'
        [string]$replayRequest.lineage.original_request_id | Should Be 'objective-2913-task-7144-original'
        [string]$replayRequest.lineage.original_correlation_id | Should Be 'objective-2913-task-7144'
        [string]$replayRequest.lineage.replay_chain_root_request_id | Should Be 'objective-2913-task-7144-original'
        [string]$replayRequest.replay_of_request_id | Should Be 'objective-2913-task-7144-original'
    }
}