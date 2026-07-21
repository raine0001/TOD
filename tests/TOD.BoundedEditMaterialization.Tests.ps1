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
        Import-TodFunction -Name 'Resolve-TodTaskMode'
        Import-TodFunction -Name 'Get-BoundedEditDirectiveValue'
        Import-TodFunction -Name 'Convert-ToCanonicalBoundedEditMode'
        Import-TodFunction -Name 'Get-BoundedEditSectionTitle'
        Import-TodFunction -Name 'Get-CanonicalBoundedTargetFileHints'
        Import-TodFunction -Name 'Get-InferredBoundedValidationCommand'
        Import-TodFunction -Name 'Get-InferredBoundedReplaceDirective'
        Import-TodFunction -Name 'Get-BoundedEditSourceFileText'
        Import-TodFunction -Name 'New-BoundedEditMaterializationBlockedPayload'
        Import-TodFunction -Name 'Resolve-TaskBoundedEditMaterialization'
        Import-TodFunction -Name 'Test-TaskAllowsLocalExecutionWithoutMaterialization'
        Import-TodFunction -Name 'Sync-CodexHandoffTaskMirror'
    }

    It 'allows inspection read-only audit artifact tasks to bypass bounded edit materialization' {
        $task = [pscustomobject]@{
            id = 'TSK-MAT-INSPECTION-AUDIT'
            title = 'Inspection read-only audit artifact'
            task_category = 'inspection'
            scope = @'
Input: runtime/shared/TOD_EXECUTION_RESULT.latest.json
Output artifact: runtime_remote_training/read_only_audit_artifacts/TOD_INSPECTION_AUDIT_TEST.latest.json
Audit Subject: latest execution result.
Use the read-only audit artifact lane.
No code changes.
'@
        }

        Test-TaskAllowsLocalExecutionWithoutMaterialization -Task $task -TaskCategory 'inspection' | Should Be $true
    }

    It 'allows source-anchor observation tasks to bypass bounded edit materialization' {
        $task = [pscustomobject]@{
            id = 'TSK-MAT-SOURCE-ANCHOR'
            title = 'Source anchor observation'
            task_category = 'source_anchor_observation'
            scope = @'
Source-anchor observation from current code.
Source File: scripts/TOD.ps1
Output: runtime_remote_training/read_only_audit_artifacts/TOD_SOURCE_ANCHOR_TEST.latest.json
Anchor Pattern: $resolvedTaskMode = Resolve-TodTaskMode -Task $taskModeProbe
No code changes.
'@
        }

        Test-TaskAllowsLocalExecutionWithoutMaterialization -Task $task -TaskCategory 'source_anchor_observation' | Should Be $true
    }

    It 'treats target-selection training as local observe-only work until a bounded edit target exists' {
        $task = [pscustomobject]@{
            id = 'TSK-TARGET-SELECTION-RUNG'
            title = 'TOD target selection mode rung'
            task_category = 'training'
            type = 'implementation'
            scope = @'
TOD must independently select one fresh harmless status or UI target.
Inspect candidate files, reject unsuitable candidates, choose one target, and publish a target-selection artifact.
Do not modify source code in this rung.
'@
        }

        Resolve-TodTaskMode -Task $task | Should Be 'target_selection'
        Test-TaskAllowsLocalExecutionWithoutMaterialization -Task $task -TaskCategory 'training' | Should Be $true

        $boundedTask = [pscustomobject]@{
            id = 'TSK-TARGET-SELECTION-WITH-EDIT'
            title = 'TOD target selection after packet formation'
            task_category = 'training'
            scope = @'
Target selection is complete.
Target File: scripts/TOD.ps1
Edit Mode: replace_text
Old Text: alpha
New Text: beta
'@
        }

        Test-TaskAllowsLocalExecutionWithoutMaterialization -Task $boundedTask -TaskCategory 'training' | Should Be $false
    }

    It 'allows report-only read-only audit tasks with stale blocked materialization to reach LocalExecutionEngine' {
        $task = [pscustomobject]@{
            id = 'TSK-MAT-STALE-AUDIT'
            title = 'Stale blocked report-only audit'
            task_category = 'report_only'
            scope = 'Input: runtime/shared/TOD_EXECUTION_RESULT.latest.json Output artifact: runtime_remote_training/read_only_audit_artifacts/TOD_STALE_AUDIT_TEST.latest.json'
        }
        $materialization = [pscustomobject]@{
            status = 'blocked'
            reason_code = 'blocked_missing_bounded_edit_mode'
            target_file_candidates = @(
                'runtime/shared/TOD_EXECUTION_RESULT.latest.json',
                'runtime_remote_training/read_only_audit_artifacts/TOD_STALE_AUDIT_TEST.latest.json'
            )
        }

        Test-TaskAllowsLocalExecutionWithoutMaterialization -Task $task -TaskCategory 'report_only' -TaskMaterialization $materialization | Should Be $true
    }

    It 'reads routing text from JSON-deserialized task properties' {
        $task = @'
{
  "id": "TSK-MAT-JSON-TEXT",
  "title": "JSON task title",
  "scope": "Input: runtime/shared/TOD_EXECUTION_RESULT.latest.json Output artifact: runtime_remote_training/read_only_audit_artifacts/TOD_JSON_TEXT_TEST.latest.json",
  "acceptance_criteria": "No code changes."
}
'@ | ConvertFrom-Json

        $text = Get-TaskRoutingText -Task $task

        [string]$text | Should Match 'JSON task title'
        [string]$text | Should Match 'TOD_EXECUTION_RESULT'
        [string]$text | Should Match 'No code changes'
    }

    It 'preserves bridge request packet fields when mirroring state' {
        $script:MirrorState = [pscustomobject]@{
            objectives = @()
            tasks = @()
        }
        function global:Test-TodEphemeralStateAccess { return $false }
        function global:Load-State { return $script:MirrorState }
        function global:Save-State {
            param($State)
            $script:MirrorState = $State
        }
        function global:Resolve-PreferredAssignedExecutor {
            param($TaskCategory, $State, $Task)
            return 'local'
        }
        function global:Get-UtcNow { return '2026-07-02T00:00:00Z' }

        try {
            $request = [pscustomobject]@{
                request_id = 'REQ-MIRROR-PACKET'
                task_id = 'TSK-MIRROR-PACKET'
                objective_id = 'OBJ-MIRROR'
                title = 'Mirror bounded packet'
                summary = 'Mirror bounded packet.'
                requested_outcome = 'Materialize exact bounded edit.'
                target_file = 'tmp_remote_mim/core/routers/observatory.py'
                bounded_edit_mode = $true
                edit_mode = 'replace_text'
                old_text = 'OLD_SENTINEL'
                new_text = 'NEW_SENTINEL'
                validation_command = 'python -m py_compile tmp_remote_mim/core/routers/observatory.py'
                metadata_json = [pscustomobject]@{
                    task_category = 'diagnostic_implementation_repair'
                    assigned_executor = 'local'
                }
            }

            $mirror = Sync-CodexHandoffTaskMirror -Request $request
            $mirroredTask = @($script:MirrorState.tasks | Where-Object { [string]$_.id -eq 'TSK-MIRROR-PACKET' } | Select-Object -First 1)[0]

            [string]$mirror.reason | Should Be 'task_mirror_created'
            [string]$mirroredTask.target_file | Should Be 'tmp_remote_mim/core/routers/observatory.py'
            [string]$mirroredTask.edit_mode | Should Be 'replace_text'
            [string]$mirroredTask.old_text | Should Be 'OLD_SENTINEL'
            [string]$mirroredTask.new_text | Should Be 'NEW_SENTINEL'
            [string]$mirroredTask.validation_command | Should Be 'python -m py_compile tmp_remote_mim/core/routers/observatory.py'

            $materialization = Resolve-TaskBoundedEditMaterialization -Task $mirroredTask
            [string]$materialization.status | Should Be 'materialized'
            [string]$materialization.edit_mode | Should Be 'replace_text'
        }
        finally {
            Remove-Item -Path function:\Test-TodEphemeralStateAccess -ErrorAction SilentlyContinue
            Remove-Item -Path function:\Load-State -ErrorAction SilentlyContinue
            Remove-Item -Path function:\Save-State -ErrorAction SilentlyContinue
            Remove-Item -Path function:\Resolve-PreferredAssignedExecutor -ErrorAction SilentlyContinue
            Remove-Item -Path function:\Get-UtcNow -ErrorAction SilentlyContinue
            Remove-Variable -Name MirrorState -Scope Script -ErrorAction SilentlyContinue
        }
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

    It 'preserves multiline replace_text directives for Python block patches' {
        $task = [pscustomobject]@{
            id = 'TSK-MAT-MULTILINE-PY'
            title = 'Recover Python scoreboard patch'
            scope = @'
Target File: scripts/generate_mim_tod_training_scoreboard.py
Edit Mode: replace_text
Old Text:
    durability_current_passed = (
        durability_v2.get("status") == "passed"
        and isinstance(durability_summary.get("case_count"), int)
        and int(durability_summary.get("case_count") or 0) > 0
        and durability_summary.get("failed") == 0
    )
    mim_visible_evaluation = mim_eval
New Text:
    durability_current_passed = (
        durability_v2.get("status") == "passed"
        and isinstance(durability_summary.get("case_count"), int)
        and int(durability_summary.get("case_count") or 0) > 0
        and durability_summary.get("failed") == 0
    )
    current_evidence_supersedes_stale_reflection = (
        reflection_says_not_improving
        and durability_current_passed
    )
    mim_visible_evaluation = mim_eval
Validation Pattern: current_evidence_supersedes_stale_reflection
'@
            task_category = 'code_change'
        }

        $materialization = Resolve-TaskBoundedEditMaterialization -Task $task

        [string]$materialization.status | Should Be 'materialized'
        [string]$materialization.edit_mode | Should Be 'replace_text'
        [string]@($materialization.target_files)[0] | Should Be 'scripts/generate_mim_tod_training_scoreboard.py'
        [string]$materialization.prompt_directives['Old Text'] | Should Match 'mim_visible_evaluation = mim_eval'
        [string]$materialization.prompt_directives['Old Text'] | Should Match 'durability_summary.get\("failed"\) == 0'
        [string]$materialization.prompt_directives['New Text'] | Should Match 'current_evidence_supersedes_stale_reflection'
        [string]$materialization.prompt_directives['New Text'] | Should Match 'mim_visible_evaluation = mim_eval'
    }

    It 'blocks replace_text materialization when old and new text are identical' {
        $task = [pscustomobject]@{
            id = 'TSK-MAT-NOOP-REPLACE'
            title = 'Reject no-op replacement'
            scope = @'
Target File: scripts/TOD.ps1
Edit Mode: replace_text
Old Text:
            $validationPlan.Add('inspect current target files before dispatch') | Out-Null
New Text:
            $validationPlan.Add('inspect current target files before dispatch') | Out-Null
Validation Pattern: inspect current target files before dispatch
'@
            task_category = 'code_change'
        }

        $materialization = Resolve-TaskBoundedEditMaterialization -Task $task

        [string]$materialization.status | Should Be 'blocked'
        [string]$materialization.reason_code | Should Be 'blocked_missing_bounded_edit_mode'
        (@($materialization.required_clarification) -contains 'new_text_differs_from_old_text') | Should Be $true
        [string]$materialization.why_local_executor_cannot_proceed | Should Match 'identical replacement text is a no-op candidate'
    }

    It 'refreshes stale cached replace_text materialization when multiline directives are richer' {
        $task = [pscustomobject]@{
            id = 'TSK-MAT-REFRESH-STALE'
            title = 'Refresh stale collapsed materialization'
            scope = @'
Target File: scripts/generate_mim_tod_training_scoreboard.py
Edit Mode: replace_text
Old Text:
    durability_current_passed = (
        durability_v2.get("status") == "passed"
    )
    mim_visible_evaluation = mim_eval
New Text:
    durability_current_passed = (
        durability_v2.get("status") == "passed"
    )
    current_evidence_supersedes_stale_reflection = True
    mim_visible_evaluation = mim_eval
Validation Pattern: current_evidence_supersedes_stale_reflection
'@
            task_category = 'code_change'
            materialization = [pscustomobject]@{
                status = 'materialized'
                edit_mode = 'replace_text'
                target_files = @('scripts/generate_mim_tod_training_scoreboard.py')
                prompt_directives = [pscustomobject]@{
                    'Target File' = 'scripts/generate_mim_tod_training_scoreboard.py'
                    'Edit Mode' = 'replace_text'
                    'Old Text' = 'durability_current_passed = ('
                    'New Text' = 'durability_current_passed = ('
                }
            }
        }

        $materialization = Resolve-TaskBoundedEditMaterialization -Task $task

        [string]$materialization.status | Should Be 'materialized'
        [string]$materialization.prompt_directives['Old Text'] | Should Match 'mim_visible_evaluation = mim_eval'
        [string]$materialization.prompt_directives['New Text'] | Should Match 'current_evidence_supersedes_stale_reflection'
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

    It 'materializes Studio training response-mode metadata repair from behavior request' {
        $task = [pscustomobject]@{
            id = 'TSK-MAT-STUDIO-RESPONSE-MODE'
            title = 'Repair Studio training response mode metadata'
            scope = @'
Inspect the Studio training API path and repair the response_mode metadata so recommendation-style training prompts such as next work, status dump regression, Validated TOD Edits, and auth blocker questions are not labeled as generic training_summary.
'@
            task_category = 'code_change'
            allowed_files = @('tmp_remote_mim/core/routers/studio.py')
        }

        $materialization = Resolve-TaskBoundedEditMaterialization -Task $task

        [string]$materialization.status | Should Be 'materialized'
        [string]@($materialization.target_files)[0] | Should Be 'tmp_remote_mim/core/routers/studio.py'
        if ([string]$materialization.edit_mode -eq 'replace_text') {
            [string]$materialization.edit_mode | Should Be 'replace_text'
            [string]$materialization.prompt_directives['New Text'] | Should Match 'anything you want to work on next'
            [string]$materialization.validation_plan.command | Should Be 'python -m py_compile tmp_remote_mim/core/routers/studio.py'
        }
        else {
            [string]$materialization.edit_mode | Should Be 'validation_only'
            [string]$materialization.prompt_directives['Validation Command'] | Should Be 'python -m py_compile .\tmp_remote_mim\core\routers\studio.py'
        }
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

    It 'uses Target File directive instead of validation command file paths as the bounded target' {
        $task = [pscustomobject]@{
            id = 'TSK-MAT-DIRECTIVE-TARGET'
            title = 'Repair canonical publisher gate freshness'
            scope = @'
Target File: scripts/TOD.ps1
Edit Mode: replace_exact_text
Old Text: $generatedAt = ''
New Text: $generatedAt = (Get-Date).ToUniversalTime().ToString('o')
Validation Pattern: Get-TodObjectValue -InputObject $Payload -Name 'updated_at'
Validation Command: powershell -NoProfile -ExecutionPolicy Bypass -File tests\TOD.CanonicalLanePublisherGate.Tests.ps1; powershell -NoProfile -Command "$null = [scriptblock]::Create((Get-Content -Raw 'scripts\TOD.ps1')); Write-Output 'TOD syntax ok'"
'@
            task_category = 'code_change'
        }

        $materialization = Resolve-TaskBoundedEditMaterialization -Task $task

        [string]$materialization.status | Should Be 'materialized'
        [string]@($materialization.target_files)[0] | Should Be 'scripts/TOD.ps1'
        @($materialization.target_file_candidates).Count | Should Be 1
        [string]$materialization.prompt_directives['Validation Command'] | Should Match 'TOD.CanonicalLanePublisherGate.Tests.ps1'
    }

    It 'tolerates noisy slash-bearing hints with path-illegal characters' {
        $hints = Get-CanonicalBoundedTargetFileHints -FileHints @(
            'runtime_remote_training/tod_result_artifacts/TOD_FIELD_PRESERVATION_SMOKE.latest.json',
            'Target File: runtime_remote_training/tod_result_artifacts/TOD_FIELD_PRESERVATION_SMOKE.latest.json New Text: {"smoke_marker":"before_field_preservation_fix"}'
        )

        @($hints).Count | Should Be 2
        (@($hints) -contains 'runtime_remote_training/tod_result_artifacts/TOD_FIELD_PRESERVATION_SMOKE.latest.json') | Should Be $true
    }

    It 'materializes escaped-newline artifact_write directives as one target' {
        $task = [pscustomobject]@{
            id = 'TSK-ESCAPED-NEWLINE-ARTIFACT'
            title = 'Seed TOD field preservation smoke artifact'
            scope = 'Target File: runtime_remote_training/tod_result_artifacts/TOD_FIELD_PRESERVATION_SMOKE.latest.json`nEdit Mode: artifact_write`nNew Text: {"smoke_marker":"before_field_preservation_fix","purpose":"bounded packet old/new smoke"}`nValidation Command: if (-not (Select-String -Path runtime_remote_training/tod_result_artifacts/TOD_FIELD_PRESERVATION_SMOKE.latest.json -Pattern "before_field_preservation_fix" -SimpleMatch -Quiet)) { throw "seed marker missing" }'
            task_category = 'diagnostic_implementation_repair'
        }

        $materialization = Resolve-TaskBoundedEditMaterialization -Task $task

        [string]$materialization.status | Should Be 'materialized'
        [string]$materialization.edit_mode | Should Be 'artifact_write'
        @($materialization.target_file_candidates).Count | Should Be 1
        [string]@($materialization.target_files)[0] | Should Be 'runtime_remote_training/tod_result_artifacts/TOD_FIELD_PRESERVATION_SMOKE.latest.json'
    }

    It 'uses nested bounded_slice likely_target_files when top-level target fields are absent' {
        $task = [pscustomobject]@{
            id = 'TSK-MAT-BOUNDED-SLICE-TARGET'
            title = 'Repair MIM handoff gateway'
            scope = @'
Edit Mode: validation_only
Validation Command: python -m unittest tests.integration.test_mim_tod_handoff_gateway.MimTodHandoffGatewayTest.test_implementation_objective_route_writes_current_tod_request
'@
            task_category = 'validation'
            bounded_slice = [pscustomobject]@{
                likely_target_files = @('core/routers/gateway.py')
            }
        }

        $materialization = Resolve-TaskBoundedEditMaterialization -Task $task

        [string]$materialization.status | Should Be 'materialized'
        [string]@($materialization.target_files)[0] | Should Be 'core/routers/gateway.py'
        @($materialization.target_file_candidates).Count | Should Be 1
    }

    It 'uses metadata_json bounded_slice likely_target_files when task fields are wrapped' {
        $task = [pscustomobject]@{
            id = 'TSK-MAT-METADATA-BOUNDED-SLICE-TARGET'
            title = 'Repair MIM handoff gateway'
            scope = @'
Edit Mode: validation_only
Validation Command: python -m unittest tests.integration.test_mim_tod_handoff_gateway.MimTodHandoffGatewayTest.test_implementation_objective_route_writes_current_tod_request
'@
            task_category = 'validation'
            metadata_json = [pscustomobject]@{
                bounded_slice = [pscustomobject]@{
                    likely_target_files = @('core/routers/gateway.py')
                }
            }
        }

        $materialization = Resolve-TaskBoundedEditMaterialization -Task $task

        [string]$materialization.status | Should Be 'materialized'
        [string]@($materialization.target_files)[0] | Should Be 'core/routers/gateway.py'
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

    It 'blocks behavior-changing code_change requests instead of downgrading them to validation_only' {
        $task = [pscustomobject]@{
            id = 'TSK-MAT-CODECHANGE-NO-DIRECTIVE'
            title = 'TOD independent split: gateway single-target materialization'
            scope = @'
Target File: tmp_remote_mim/core/routers/gateway.py
Validation Command: cd tmp_remote_mim; python -m unittest tests.integration.test_mim_tod_handoff_gateway.MimTodHandoffGatewayTest.test_implementation_objective_route_writes_current_tod_request
Validation Pattern: OK
Inspect the current gateway implementation. If a bounded behavior-changing edit is supported by current code, TOD must materialize exact old_text/new_text itself, apply it, validate, and publish evidence.
'@
            task_category = 'code_change'
        }

        $materialization = Resolve-TaskBoundedEditMaterialization -Task $task

        [string]$materialization.status | Should Be 'blocked'
        [string]$materialization.reason_code | Should Be 'blocked_missing_bounded_edit_mode'
        [string]$materialization.why_local_executor_cannot_proceed | Should Match 'cannot downgrade'
        @($materialization.required_clarification) -contains 'old_text_or_anchor' | Should Be $true
        @($materialization.required_clarification) -contains 'new_text_or_snippet' | Should Be $true
        [string]$materialization.recovery_contract.status | Should Be 'packet_required_before_local_execution'
        [string]$materialization.recovery_contract.target_file | Should Be 'tmp_remote_mim/core/routers/gateway.py'
        [string]$materialization.recovery_contract.validation_command | Should Match 'test_implementation_objective_route_writes_current_tod_request'
        @($materialization.recovery_contract.required_packet_fields) -contains 'exact_current_anchor_or_old_text' | Should Be $true
        @($materialization.recovery_contract.required_packet_fields) -contains 'different_new_text' | Should Be $true
    }

    It 'blocks MIM replan implementation packets with inferred validation checks instead of downgrading to validation_only' {
        $task = [pscustomobject]@{
            id = 'TSK-MAT-MIM-REPLAN-NO-DIRECTIVE'
            title = 'Replan bounded slice: Add or adjust one deterministic dispatch rule for this objective.'
            scope = 'Replan bounded slice: Add or adjust one deterministic dispatch rule for this objective.. Target component: MIM implementation objective dispatch. Validation/check: python -m unittest tests.integration.test_mim_tod_handoff_gateway.MimTodHandoffGatewayTest.test_implementation_objective_route_writes_current_tod_request. Inspect the target files or discovery scope first, then either apply the smallest safe patch with validation results or return blocked_with_reason with inspected_files.'
            task_category = 'code_change'
            target_file = 'core/routers/gateway.py'
            bounded_edit_mode = $true
            validation_only = $false
        }

        $materialization = Resolve-TaskBoundedEditMaterialization -Task $task

        [string]$materialization.status | Should Be 'blocked'
        [string]$materialization.reason_code | Should Be 'blocked_missing_bounded_edit_mode'
        [string]$materialization.why_local_executor_cannot_proceed | Should Match 'cannot downgrade'
        @($materialization.required_clarification) -contains 'old_text_or_anchor' | Should Be $true
        @($materialization.required_clarification) -contains 'new_text_or_snippet' | Should Be $true
        [string]$materialization.recovery_contract.status | Should Be 'packet_required_before_local_execution'
        [string]$materialization.recovery_contract.target_file | Should Be 'core/routers/gateway.py'
        @($materialization.recovery_contract.required_packet_fields) -contains 'closure_evidence' | Should Be $true
        [string]$materialization.recovery_contract.dave_needed | Should Be 'no'
    }

    It 'materializes corrected patch synthesis practice as artifact_write' {
        $task = [pscustomobject]@{
            id = 'TSK-MAT-PRACTICE-ARTIFACT'
            title = 'TOD corrected patch synthesis practice'
            scope = @'
Target File: runtime_remote_training/TOD_CORRECTED_PATCH_SYNTHESIS_PRACTICE_V1.latest.json
Practice-only task for TOD-CORRECTED-PATCH-SYNTHESIS-PRACTICE-V1.
Produce a result artifact that fills these required_output fields: inspected_target_file, current_anchor_line_or_hash, proposed_edit_mode.
Do not modify scripts/generate_mim_tod_training_scoreboard.py in this practice task.
'@
            task_category = 'code_change'
        }

        $materialization = Resolve-TaskBoundedEditMaterialization -Task $task

        [string]$materialization.status | Should Be 'materialized'
        [string]$materialization.edit_mode | Should Be 'artifact_write'
        [string]@($materialization.target_files)[0] | Should Be 'runtime_remote_training/TOD_CORRECTED_PATCH_SYNTHESIS_PRACTICE_V1.latest.json'
        [string]$materialization.prompt_directives['Edit Mode'] | Should Be 'artifact_write'
    }

    It 'materializes packet formation artifact output without explicit artifact wording' {
        $task = [pscustomobject]@{
            id = 'TSK-MAT-PACKET-FORMATION-ARTIFACT'
            title = 'Materialize packet artifact'
            task_category = 'packet_formation'
            target_file = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_PACKET.latest.json'
            scope = @'
Packet Source Target: tmp_remote_mim/core/routers/public_chat.py
Inspect current code and synthesize one harmless bounded edit packet with exact current anchor_or_old_text, new_text_or_snippet, validation_command, expected_evidence, closure_evidence, prevention_lesson, and dave_needed=no.
Do not apply the packet in this rung.
'@
        }

        $materialization = Resolve-TaskBoundedEditMaterialization -Task $task

        [string]$materialization.status | Should Be 'materialized'
        [string]$materialization.edit_mode | Should Be 'artifact_write'
        [string]@($materialization.target_files)[0] | Should Be 'runtime_remote_training/tod_independent_resolution_attempts/TOD_PACKET.latest.json'
        [string]$materialization.prompt_directives['Edit Mode'] | Should Be 'artifact_write'
        [string]$materialization.prompt_directives['Packet Source Target'] | Should Be 'tmp_remote_mim/core/routers/public_chat.py'
    }

    It 'allows read-only assessment tasks that mention multiple files without turning them into bounded edits' {
        $task = [pscustomobject]@{
            id = 'TSK-MAT-READONLY-MULTIFILE'
            title = 'Assess packet formation blocker'
            task_category = 'read_only_assessment'
            task_mode = 'read_only_assessment'
            scope = @'
Read-only assessment. Inspect the latest blocked result and the relevant materialization code path.
Compare runtime_remote_training/tod_independent_resolution_attempts/TOD_PACKET.latest.json with tmp_remote_mim/core/routers/public_chat.py.
Do not modify source.
'@
        }
        $materialization = [pscustomobject]@{
            status = 'blocked'
            reason_code = 'blocked_missing_bounded_edit_mode'
            target_file_candidates = @(
                'runtime_remote_training/tod_independent_resolution_attempts/TOD_PACKET.latest.json',
                'tmp_remote_mim/core/routers/public_chat.py'
            )
        }

        Resolve-TodTaskMode -Task $task | Should Be 'read_only_assessment'
        Test-TaskAllowsLocalExecutionWithoutMaterialization -Task $task -TaskCategory 'read_only_assessment' -TaskMaterialization $materialization | Should Be $true
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

    It 'does not treat forbidden target examples as bounded target candidates' {
        $task = [pscustomobject]@{
            id = 'TSK-MAT-FORBIDDEN-TARGETS'
            title = 'Select fresh target without reusing consumed anchors'
            scope = @'
Problem: choose a fresh target.
Forbidden repeated targets:
- scripts/run_mim_durability_smoke_v2.py
- tmp_remote_mim/core/routers/gateway.py
- scripts/TOD.ps1
Required behavior: inspect current code and choose one different live-path target file.
'@
            task_category = 'code_change'
        }

        $materialization = Resolve-TaskBoundedEditMaterialization -Task $task

        [string]$materialization.status | Should Be 'blocked'
        [string]$materialization.reason_code | Should Be 'blocked_missing_bounded_edit_mode'
        @($materialization.target_file_candidates).Count | Should Be 0
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

    It 'materializes apply-from-packet work from Packet Artifact without repeated old/new directives' {
        $fixture = New-MaterializationFixture
        try {
            $packetPath = Join-Path $fixture.Base 'packet.json'
            Write-JsonNoBom -PathValue $packetPath -Payload ([pscustomobject]@{
                packet_candidate_ready = $true
                packet = [pscustomobject]@{
                    target_file = 'tmp_remote_mim/core/routers/studio.py'
                    old_text = 'old from packet'
                    new_text = 'new from packet'
                    validation_command = 'python -m py_compile tmp_remote_mim/core/routers/studio.py'
                    validation_pattern = 'new from packet'
                }
            })

            $task = [pscustomobject]@{
                id = 'TSK-MAT-PACKET-ARTIFACT'
                title = 'Apply packet artifact'
                scope = @"
Task Class: implementation
Apply packet artifact from TOD packet formation.
Packet Artifact: $packetPath
Target File: tmp_remote_mim/core/routers/studio.py
Edit Mode: replace_exact_text
"@
                task_category = 'implementation'
                bounded_edit_mode = $true
            }

            $materialization = Resolve-TaskBoundedEditMaterialization -Task $task

            [string]$materialization.status | Should Be 'materialized'
            [string]$materialization.edit_mode | Should Be 'replace_text'
            [string]$materialization.prompt_directives.'Old Text' | Should Be 'old from packet'
            [string]$materialization.prompt_directives.'New Text' | Should Be 'new from packet'
            [string]$materialization.prompt_directives.'Validation Command' | Should Be 'python -m py_compile tmp_remote_mim/core/routers/studio.py'
            [string]$materialization.prompt_directives.'Validation Pattern' | Should Be 'new from packet'
        }
        finally {
            if ($fixture -and (Test-Path -Path $fixture.Base)) {
                Remove-Item -Path $fixture.Base -Recurse -Force
            }
        }
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
            [bool]$result.post_completion_tail_skipped | Should Be $true
            @($result.published_artifacts.artifact_paths | Where-Object { [System.IO.Path]::GetFileName([string]$_) -eq 'TOD_EXECUTION_RESULT.latest.json' }).Count | Should BeGreaterThan 0

            $executionResultPath = Join-Path $repoRoot 'runtime/shared/TOD_EXECUTION_RESULT.latest.json'
            (Test-Path -Path $executionResultPath) | Should Be $true
            $executionResult = Get-Content -Raw $executionResultPath | ConvertFrom-Json
            [string]$executionResult.task_id | Should Be 'TSK-MAT-RUN'
            [string]$executionResult.status | Should Be 'blocked'
            [string]$executionResult.reason_code | Should Be 'blocked_missing_bounded_edit_mode'

            $stateAfter = Get-Content -Raw $fixture.TodStatePath | ConvertFrom-Json
            $taskAfter = @($stateAfter.tasks | Where-Object { [string]$_.id -eq 'TSK-MAT-RUN' } | Select-Object -First 1)
            [string]$taskAfter.status | Should Be 'blocked'
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
