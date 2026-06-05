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

function Write-JsonNoBom {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)]$Payload,
        [int]$Depth = 20
    )

    $directory = Split-Path -Parent $PathValue
    if (-not (Test-Path -Path $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($PathValue, ($Payload | ConvertTo-Json -Depth $Depth), $utf8NoBom)
}

function New-MaterializationFixture {
    $base = Join-Path $repoRoot ('tod/out/tests/bounded-materialization-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $base -Force | Out-Null

    return [pscustomobject]@{
        Base = $base
        TodConfigPath = Join-Path $base 'tod-config.json'
        TodStatePath = Join-Path $base 'tod-state.json'
        ExecutionReadinessPath = Join-Path $base 'tod_execution_readiness.latest.json'
        ExecutionReadinessHistoryPath = Join-Path $base 'tod_execution_readiness_history.latest.json'
        PromptPath = Join-Path $base 'task.md'
    }
}

function Write-ExecutionReadyTodConfig {
    param(
        [Parameter(Mandatory = $true)]$Fixture,
        [string]$ActiveEngine = 'local',
        [string]$FallbackEngine = 'local'
    )

    Write-JsonNoBom -PathValue $Fixture.ExecutionReadinessPath -Payload ([pscustomobject]@{
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        summary = [pscustomobject]@{
            passed_all = $true
            exit_code = 0
        }
    })

    Write-JsonNoBom -PathValue $Fixture.TodConfigPath -Payload ([pscustomobject]@{
        mode = 'local'
        fallback_to_local = $true
        timeout_seconds = 30
        engineering_loop = [pscustomobject]@{
            max_run_history = 150
            max_scorecard_history = 150
            max_cycle_records = 300
        }
        execution_engine = [pscustomobject]@{
            active = $ActiveEngine
            fallback = $FallbackEngine
            allow_fallback = $true
            readiness_policy = [pscustomobject]@{
                enabled = $true
                signal_path = $Fixture.ExecutionReadinessPath
                history_path = $Fixture.ExecutionReadinessHistoryPath
                max_artifact_age_minutes = 30
                display_max_artifact_age_minutes = 10
                block_actions = @('run-task')
                degrade_actions = @('engineer-run', 'codex_handoff')
                block_states = @('stale', 'invalid', 'unknown')
                degrade_states = @('degraded', 'stale', 'invalid', 'unknown')
                degrade_apply_plan = $true
                history_max_entries = 50
            }
        }
    })
}

Describe 'TOD bounded edit materialization' {
    BeforeAll {
        Import-TodFunction -Name 'Get-TaskRoutingText'
        Import-TodFunction -Name 'Get-TaskRoutingFileHints'
        Import-TodFunction -Name 'Get-TaskExplicitFieldValue'
        Import-TodFunction -Name 'Test-ExplicitBooleanTrue'
        Import-TodFunction -Name 'Resolve-TaskCategory'
        Import-TodFunction -Name 'Get-BoundedEditDirectiveValue'
        Import-TodFunction -Name 'Convert-ToCanonicalBoundedEditMode'
        Import-TodFunction -Name 'Get-BoundedEditSectionTitle'
        Import-TodFunction -Name 'New-BoundedEditMaterializationBlockedPayload'
        Import-TodFunction -Name 'Resolve-TaskBoundedEditMaterialization'
    }

    It 'materializes explicit replace_exact_text directives' {
        $task = [pscustomobject]@{
            id = 'TSK-MAT-REPLACE'
            title = 'Replace bounded text'
            scope = @'
Update scripts/example.ps1.
Edit Mode: replace_exact_text
Old Text: OLD_SENTINEL
New Text: NEW_SENTINEL
Validation Pattern: NEW_SENTINEL
'@
            task_category = 'code_change'
            allowed_files = @('scripts/example.ps1')
        }

        $materialization = Resolve-TaskBoundedEditMaterialization -Task $task

        [string]$materialization.status | Should Be 'materialized'
        [string]$materialization.edit_mode | Should Be 'replace_text'
        [string]@($materialization.target_files)[0] | Should Be 'scripts/example.ps1'
        [string]$materialization.prompt_directives['Old Text'] | Should Be 'OLD_SENTINEL'
        [string]$materialization.prompt_directives['New Text'] | Should Be 'NEW_SENTINEL'
    }

    It 'materializes docs append requests into append_section mode' {
        $task = [pscustomobject]@{
            id = 'TSK-MAT-DOCS'
            title = 'Append docs section'
            scope = @'
Update docs/materialization-test.md.
Edit Mode: docs_append_section
Section Title: Materializer Evidence
'@
            task_category = 'docs_change'
            allowed_files = @('docs/materialization-test.md')
        }

        $materialization = Resolve-TaskBoundedEditMaterialization -Task $task

        [string]$materialization.status | Should Be 'materialized'
        [string]$materialization.edit_mode | Should Be 'append_section'
        [string]$materialization.prompt_directives['Section Title'] | Should Be 'Materializer Evidence'
    }

    It 'keeps one explicit target authoritative when acceptance mentions an evidence artifact' {
        $task = [pscustomobject]@{
            id = 'TSK-MAT-DOCS-EVIDENCE'
            title = 'Append docs section with lane proof'
            scope = @'
Edit Mode: docs_append_section
Section Title: Active Lane Projection Evidence
Section Body: TOD active lane projection proof completed.
Validation Pattern: TSK-MAT-DOCS-EVIDENCE
'@
            acceptance_criteria = @('docs/tod-command-reference.md contains TSK-MAT-DOCS-EVIDENCE and TOD_ACTIVE_EXECUTION_LANE.latest.json reaches completed.')
            task_category = 'docs_change'
            allowed_files = @('docs/tod-command-reference.md')
        }

        $materialization = Resolve-TaskBoundedEditMaterialization -Task $task

        [string]$materialization.status | Should Be 'materialized'
        [string]@($materialization.target_files)[0] | Should Be 'docs/tod-command-reference.md'
        @($materialization.target_file_candidates).Count | Should Be 1
    }

    It 'materializes validation-only tasks without a patch directive' {
        $task = [pscustomobject]@{
            id = 'TSK-MAT-VALIDATE'
            title = 'Validate bounded target'
            scope = @'
Inspect scripts/TOD.ps1 and publish validation only. Do not call Codex.
Validation Pattern: function Invoke-ExecuteChatTaskRequest
'@
            task_category = 'validation'
            allowed_files = @('scripts/TOD.ps1')
        }

        $materialization = Resolve-TaskBoundedEditMaterialization -Task $task

        [string]$materialization.status | Should Be 'materialized'
        [string]$materialization.edit_mode | Should Be 'validation_only'
        [string]$materialization.prompt_directives['Validation Pattern'] | Should Match 'Invoke-ExecuteChatTaskRequest'
    }

    It 'blocks abstract code changes with blocked_missing_bounded_edit_mode' {
        $task = [pscustomobject]@{
            id = 'TSK-MAT-BLOCKED'
            title = 'Abstract implementation request'
            scope = 'Implement the initiative core for /api/tod-conversation in scripts/Start-TOD-UI.ps1.'
            task_category = 'code_change'
            allowed_files = @('scripts/Start-TOD-UI.ps1')
            source = 'direct_chat'
        }

        $materialization = Resolve-TaskBoundedEditMaterialization -Task $task

        [string]$materialization.status | Should Be 'blocked'
        [string]$materialization.reason_code | Should Be 'blocked_missing_bounded_edit_mode'
        (@($materialization.required_clarification) -contains 'edit_mode') | Should Be $true
        [string]@($materialization.target_file_candidates)[0] | Should Be 'scripts/Start-TOD-UI.ps1'
    }

    It 'blocks missing target_file with exact missing field' {
        $task = [pscustomobject]@{
            id = 'TSK-MAT-MISSING-TARGET'
            title = 'Repair bounded materialization'
            scope = 'Patch Resolve-TaskBoundedEditMaterialization.'
            task_category = 'code_change'
        }

        $materialization = Resolve-TaskBoundedEditMaterialization -Task $task

        [string]$materialization.status | Should Be 'blocked'
        [string]$materialization.reason_code | Should Be 'blocked_missing_bounded_edit_mode'
        (@($materialization.required_clarification) -contains 'target_file') | Should Be $true
        (@($materialization.missing_fields) -contains 'target_file') | Should Be $true
        [string]$materialization.why_local_executor_cannot_proceed | Should Match 'no target_file was provided'
    }

    It 'materializes exactly one explicit target_file for objective 2914 validation repair' {
        $task = [pscustomobject]@{
            id = 'objective-2914-bounded-edit-materialization-repair'
            objective_id = 'objective-2914'
            title = 'Repair bounded materialization'
            scope = 'Validate Resolve-TaskBoundedEditMaterialization after bounded target_file repair.'
            task_category = 'validation'
            target_file = 'scripts/TOD.ps1'
            bounded_edit_mode = $true
            validation_only = $true
            expected_function = 'Resolve-TaskBoundedEditMaterialization'
        }

        $materialization = Resolve-TaskBoundedEditMaterialization -Task $task

        [string]$materialization.status | Should Be 'materialized'
        [string]$materialization.edit_mode | Should Be 'validation_only'
        [string]@($materialization.target_files)[0] | Should Be 'scripts/TOD.ps1'
        [string]$materialization.prompt_directives['Target File'] | Should Be 'scripts/TOD.ps1'
    }

    It 'blocks multiple target_files with exact missing field' {
        $task = [pscustomobject]@{
            id = 'TSK-MAT-MULTI-TARGET'
            title = 'Ambiguous bounded materialization'
            scope = 'Validate one target only.'
            task_category = 'validation'
            target_files = @('scripts/TOD.ps1', 'scripts/Start-TOD-UI.ps1')
            validation_only = $true
        }

        $materialization = Resolve-TaskBoundedEditMaterialization -Task $task

        [string]$materialization.status | Should Be 'blocked'
        [string]$materialization.reason_code | Should Be 'blocked_missing_bounded_edit_mode'
        (@($materialization.required_clarification) -contains 'target_file_exactly_one') | Should Be $true
        (@($materialization.missing_fields) -contains 'target_file_exactly_one') | Should Be $true
        @($materialization.target_file_candidates).Count | Should Be 2
    }

    It 'allows no target_file only for explicit validation_only true' {
        $task = [pscustomobject]@{
            id = 'TSK-MAT-VALIDATION-NO-TARGET'
            title = 'Validation only without edit target'
            scope = 'Run validation-only materialization without changing a file.'
            task_category = 'validation'
            validation_only = $true
        }

        $materialization = Resolve-TaskBoundedEditMaterialization -Task $task

        [string]$materialization.status | Should Be 'materialized'
        [string]$materialization.edit_mode | Should Be 'validation_only'
        @($materialization.target_files).Count | Should Be 0
    }

    It 'does not invoke LocalExecutionEngine when edit_mode is missing' {
        $fixture = New-MaterializationFixture
        try {
            Write-ExecutionReadyTodConfig -Fixture $fixture -ActiveEngine 'local' -FallbackEngine 'local'
            [System.IO.File]::WriteAllText($fixture.PromptPath, 'Implement the initiative core for /api/tod-conversation in scripts/Start-TOD-UI.ps1.', (New-Object System.Text.UTF8Encoding($false)))
            Write-JsonNoBom -PathValue $fixture.TodStatePath -Payload ([pscustomobject]@{
                objectives = @(
                    [pscustomobject]@{
                        id = 'OBJ-MAT'
                        title = 'Materialization objective'
                        description = 'Bounded edit materialization integration test.'
                        priority = 'high'
                        constraints = @()
                        success_criteria = @('Block abstract tasks before LocalExecutionEngine.')
                        status = 'in_progress'
                        created_at = (Get-Date).ToUniversalTime().ToString('o')
                        updated_at = (Get-Date).ToUniversalTime().ToString('o')
                    }
                )
                tasks = @(
                    [pscustomobject]@{
                        id = 'TSK-MAT-RUN'
                        objective_id = 'OBJ-MAT'
                        title = 'Abstract implementation request'
                        type = 'implementation'
                        task_category = 'code_change'
                        scope = 'Implement the initiative core for /api/tod-conversation in scripts/Start-TOD-UI.ps1.'
                        dependencies = @()
                        acceptance_criteria = @('Return a clear bounded edit blocker.')
                        status = 'in_progress'
                        assigned_executor = 'local'
                        allowed_files = @('scripts/Start-TOD-UI.ps1')
                        files_involved = @('scripts/Start-TOD-UI.ps1')
                        source = 'direct_chat'
                        correlation_id = 'TSK-MAT-RUN'
                        created_at = (Get-Date).ToUniversalTime().ToString('o')
                        updated_at = (Get-Date).ToUniversalTime().ToString('o')
                    }
                )
                execution_results = @()
                review_decisions = @()
                journal = @()
                engine_performance = [pscustomobject]@{ records = @(); updated_at = '' }
                routing_decisions = [pscustomobject]@{ records = @(); updated_at = '' }
                routing_feedback = [pscustomobject]@{ learned_weights = [pscustomobject]@{}; sample_size = 0; version = 'feedback_v1'; updated_at = '' }
                sync_state = [pscustomobject]@{ expected_contract_version = ''; expected_schema_version = ''; local_repo_signature = ''; cached_manifest = $null; last_comparison = $null; last_sync_decision = ''; last_sync_code = ''; compared_at = '' }
            })

            $result = (& $todScript -Action run-task -TaskId 'TSK-MAT-RUN' -ConfigPath $fixture.TodConfigPath -StatePath $fixture.TodStatePath -PackagePath $fixture.PromptPath -SkipNextTaskSelectionLoop -SkipPostCompletionTail | Out-String | ConvertFrom-Json)

            @($result.engine_invocation.attempted_engines).Count | Should Be 0
            [string]$result.engine_invocation.result.reason_code | Should Be 'blocked_missing_bounded_edit_mode'
            [string]$result.engine_invocation.result.recovery_state | Should Be 'blocked_with_reason'
        }
        finally {
            if (Test-Path -Path $fixture.Base) {
                Remove-Item -Path $fixture.Base -Recurse -Force
            }
        }
    }

    It 'allows observe-only ledger coverage tasks to invoke LocalExecutionEngine without edit directives' {
        $fixture = New-MaterializationFixture
        try {
            Write-ExecutionReadyTodConfig -Fixture $fixture -ActiveEngine 'local' -FallbackEngine 'local'
            [System.IO.File]::WriteAllText($fixture.PromptPath, 'OBJECTIVE: TOD-MESSAGE-LEDGER-COVERAGE-REPORT GOAL: Measure Phase A observe-only message-ledger coverage.', (New-Object System.Text.UTF8Encoding($false)))
            Write-JsonNoBom -PathValue $fixture.TodStatePath -Payload ([pscustomobject]@{
                objectives = @(
                    [pscustomobject]@{
                        id = 'TOD-MESSAGE-LEDGER-COVERAGE-REPORT'
                        title = 'TOD message-ledger coverage report'
                        description = 'Observe-only coverage report objective.'
                        priority = 'high'
                        constraints = @()
                        success_criteria = @('Publish coverage report without mutating production surfaces.')
                        status = 'in_progress'
                        created_at = (Get-Date).ToUniversalTime().ToString('o')
                        updated_at = (Get-Date).ToUniversalTime().ToString('o')
                    }
                )
                tasks = @(
                    [pscustomobject]@{
                        id = 'TSK-LEDGER-NONEDIT'
                        objective_id = 'TOD-MESSAGE-LEDGER-COVERAGE-REPORT'
                        title = 'Measure Phase A observe-only message-ledger coverage'
                        type = 'implementation'
                        task_category = 'mim_synced'
                        scope = 'Measure Phase A observe-only message-ledger coverage across TOD/MIM communication paths.'
                        dependencies = @()
                        acceptance_criteria = @('execute_now')
                        status = 'in_progress'
                        assigned_executor = 'local'
                        allowed_files = @()
                        files_involved = @()
                        source = 'mim_request_sync'
                        correlation_id = 'TSK-LEDGER-NONEDIT'
                        created_at = (Get-Date).ToUniversalTime().ToString('o')
                        updated_at = (Get-Date).ToUniversalTime().ToString('o')
                    }
                )
                execution_results = @()
                review_decisions = @()
                journal = @()
                engine_performance = [pscustomobject]@{ records = @(); updated_at = '' }
                routing_decisions = [pscustomobject]@{ records = @(); updated_at = '' }
                routing_feedback = [pscustomobject]@{ learned_weights = [pscustomobject]@{}; sample_size = 0; version = 'feedback_v1'; updated_at = '' }
                sync_state = [pscustomobject]@{ expected_contract_version = ''; expected_schema_version = ''; local_repo_signature = ''; cached_manifest = $null; last_comparison = $null; last_sync_decision = ''; last_sync_code = ''; compared_at = '' }
            })

            $result = (& $todScript -Action run-task -TaskId 'TSK-LEDGER-NONEDIT' -ConfigPath $fixture.TodConfigPath -StatePath $fixture.TodStatePath -PackagePath $fixture.PromptPath -SkipNextTaskSelectionLoop -SkipPostCompletionTail | Out-String | ConvertFrom-Json)

            (@($result.engine_invocation.attempted_engines) -contains 'local') | Should Be $true
            [string]$result.engine_invocation.result.status | Should Be 'completed'
            [string]$result.engine_invocation.result.reason_code | Should Be ''
            [string]$result.engine_invocation.result.summary | Should Match 'Phase A message-ledger coverage'
        }
        finally {
            if (Test-Path -Path $fixture.Base) {
                Remove-Item -Path $fixture.Base -Recurse -Force
            }
        }
    }
}
