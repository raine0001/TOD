Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$todScript = Join-Path $repoRoot 'scripts/TOD.ps1'
$localEngineScript = Join-Path $repoRoot 'scripts/engines/LocalExecutionEngine.ps1'
$executionEngineScript = Join-Path $repoRoot 'scripts/engines/ExecutionEngine.ps1'

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

function Import-ScriptFunctionWithLiteralRoot {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$LiteralRoot
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
    $definition = $definition.Replace('$PSScriptRoot', ('''' + ($LiteralRoot -replace '''', '''''') + ''''))
    . ([scriptblock]::Create($definition))
}

function New-LocalFallbackPromptFile {
    param([Parameter(Mandatory = $true)][string]$Content)

    $dir = Join-Path $repoRoot ('tod/out/tests/local-fallback-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $path = Join-Path $dir 'task.md'
    [System.IO.File]::WriteAllText($path, $Content, (New-Object System.Text.UTF8Encoding($false)))
    return $path
}

function Set-LocalFallbackTestFileText {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content
    )

    if (Test-Path -Path $Path -PathType Leaf) {
        $item = Get-Item -Path $Path -Force
        if ($item.IsReadOnly) {
            $item.IsReadOnly = $false
        }
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($false)))
}

function New-LocalFallbackContext {
    param(
        [Parameter(Mandatory = $true)][string]$TaskId,
        [Parameter(Mandatory = $true)][string]$ObjectiveId,
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string]$Scope,
        [Parameter(Mandatory = $true)][string]$PromptPath,
        [hashtable]$Metadata = @{}
    )

    return [pscustomobject]@{
        task_id = $TaskId
        objective_id = $ObjectiveId
        title = $Title
        scope = $Scope
        prompt_path = $PromptPath
        allowed_files = @()
        validation_commands = @()
        metadata = $Metadata
    }
}

Describe 'TOD local fallback executor' {
    BeforeAll {
        Import-ScriptFunction -ScriptPath $executionEngineScript -Name 'Get-ExecutionEngineInterfaceSpec'
        Import-ScriptFunction -ScriptPath $executionEngineScript -Name 'New-EngineTaskContext'
        Import-ScriptFunction -ScriptPath $executionEngineScript -Name 'New-EngineExecutionResult'
        Import-ScriptFunction -ScriptPath $executionEngineScript -Name 'Complete-EngineExecutionResult'
        Import-ScriptFunction -ScriptPath $executionEngineScript -Name 'Test-EngineContract'

        Import-ScriptFunction -ScriptPath $todScript -Name 'Get-UtcNow'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Get-NormalizedObjectiveToken'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Get-TaskRoutingText'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Get-TaskRoutingFileHints'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Resolve-TaskCategory'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Convert-EngineResultToNormalizedEnvelope'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Normalize-EngineResultPayload'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Test-EngineResultPrecheck'
        Import-ScriptFunction -ScriptPath $todScript -Name 'New-ExecutionEngineBlockedResult'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Get-LocalExecutionValidationChecks'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Get-LocalExecutionCommandCapture'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Get-LocalExecutionRollbackState'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Resolve-LocalExecutionTaskClass'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Test-LocalExecutionPatchRequired'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Get-LocalExecutionNoOpAssessment'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Test-TodWrapperOnlyChangedPath'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Get-TodMaterialImplementationProofAssessment'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Get-TodTaskIdentity'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Publish-LocalExecutionArtifacts'
        Import-ScriptFunctionWithLiteralRoot -ScriptPath $todScript -Name 'Invoke-ExecutionEngine' -LiteralRoot (Join-Path $repoRoot 'scripts')

        . $localEngineScript
    }

    It 'stops validation command directives before packaged prompt metadata bullets' {
        $promptText = @'
## Task

Validation Command: powershell -NoProfile -Command "Write-Output 'ok'"
- Dependencies:
- Acceptance Criteria: command should not include this line

## Change Boundaries
- Do not modify unrelated systems.
'@

        $command = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Validation Command'

        [string]$command | Should Be 'powershell -NoProfile -Command "Write-Output ''ok''"'
        [string]$command | Should Not Match 'Dependencies'
        [string]$command | Should Not Match 'Change Boundaries'
    }

    It 'patches a bounded docs file and records execution evidence' {
        $relativePath = ('docs/local-fallback-docs-{0}.md' -f [guid]::NewGuid().ToString('N'))
        $absolutePath = Join-Path $repoRoot ($relativePath -replace '/', '\\')
        $absoluteDir = Split-Path -Parent $absolutePath
        New-Item -ItemType Directory -Path $absoluteDir -Force | Out-Null
        [System.IO.File]::WriteAllText($absolutePath, "# Temp`n", (New-Object System.Text.UTF8Encoding($false)))

        $promptPath = New-LocalFallbackPromptFile -Content ("Update {0} with a short Local Fallback Executor section." -f $relativePath)
        $context = New-LocalFallbackContext -TaskId 'TSK-LF-DOCS' -ObjectiveId 'OBJ-LF' -Title 'Update fallback docs' -Scope ("Update {0} with a short Local Fallback Executor section." -f $relativePath) -PromptPath $promptPath -Metadata @{ task_category = 'docs_change' }

        $result = Invoke-LocalExecutionEngine -Context $context

        [string]$result.status | Should Be 'completed'
        @($result.files_changed).Count | Should Be 1
        [string]@($result.files_changed)[0] | Should Be $relativePath
        [string]$result.diff_summary | Should Match 'markdown section'
        @($result.validation_results).Count | Should BeGreaterThan 0
        @($result.commands_run).Count | Should Be 1
        [string]$result.confidence | Should Be 'medium-high'
        [string]$result.rollback_hint | Should Match 'Copy-Item'
        ([string](Get-Content -Path $absolutePath -Raw)) | Should Match '## Local Fallback Executor'

        Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        Remove-Item -Path $absolutePath -Force
    }

    It 'patches a bounded allowed source file for code_change tasks' {
        $relativePath = ('scripts/local-fallback-code-{0}.ps1' -f [guid]::NewGuid().ToString('N'))
        $absolutePath = Join-Path $repoRoot ($relativePath -replace '/', '\\')
        [System.IO.File]::WriteAllText($absolutePath, "Write-Output 'OLD_SENTINEL'`n", (New-Object System.Text.UTF8Encoding($false)))

        $promptText = @"
Update $relativePath.
Edit Mode: replace_text
Old Text: OLD_SENTINEL
New Text: NEW_SENTINEL
Validation Pattern: NEW_SENTINEL
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext -TaskId 'TSK-LF-CODE' -ObjectiveId 'OBJ-LF' -Title 'Patch allowed source file' -Scope ("Patch $relativePath with a bounded replace_text change.") -PromptPath $promptPath -Metadata @{ task_category = 'code_change' }

        $result = Invoke-LocalExecutionEngine -Context $context

        [string]$result.status | Should Be 'completed'
        [string]@($result.files_changed)[0] | Should Be $relativePath
        [string]$result.diff_summary | Should Match 'Replaced bounded text'
        @($result.validation_results | Where-Object { [string]$_.name -eq 'focused_validation_exit_zero' -and [bool]$_.passed }).Count | Should Be 1
        ([string](Get-Content -Path $absolutePath -Raw)) | Should Match 'NEW_SENTINEL'

        Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        Remove-Item -Path $absolutePath -Force
    }

    It 'blocks replace_text writeback when the bounded edit would unexpectedly inflate the file' {
        $relativePath = ('scripts/local-fallback-size-guard-{0}.ps1' -f [guid]::NewGuid().ToString('N'))
        $sourceRelativePath = ('tests/local-fallback-size-guard-new-text-{0}.txt' -f [guid]::NewGuid().ToString('N'))
        $absolutePath = Join-Path $repoRoot ($relativePath -replace '/', '\\')
        $sourcePath = Join-Path $repoRoot ($sourceRelativePath -replace '/', '\\')
        [System.IO.File]::WriteAllText($absolutePath, "Write-Output 'OLD_SENTINEL'`n", (New-Object System.Text.UTF8Encoding($false)))
        [System.IO.File]::WriteAllText($sourcePath, ("Write-Output '" + ("X" * 1200000) + "'`n"), (New-Object System.Text.UTF8Encoding($false)))

        $promptText = @"
Update $relativePath.
Edit Mode: replace_text
Old Text: OLD_SENTINEL
New Text Source File: $sourceRelativePath
Validation Pattern: X
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext -TaskId 'TSK-LF-SIZE-GUARD' -ObjectiveId 'OBJ-LF' -Title 'Block oversized bounded write' -Scope ("Patch $relativePath with a bounded replace_text change.") -PromptPath $promptPath -Metadata @{ task_category = 'code_change' }
        $context.allowed_files = @($relativePath)

        $result = Invoke-LocalExecutionEngine -Context $context
        $current = [string](Get-Content -Path $absolutePath -Raw)

        [string]$result.status | Should Be 'failed'
        [string]$result.reason_code | Should Be 'local_fallback_write_size_guard'
        [string]$result.blockers[0].missing_variable | Should Be 'bounded_write_size'
        $current | Should Match 'OLD_SENTINEL'
        $current | Should Not Match 'XXXXXXXXXX'

        Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        Remove-Item -Path $absolutePath -Force
        Remove-Item -Path $sourcePath -Force
    }

    It 'honors replace_text Occurrence last for self-editing prompt text' {
        $relativePath = ('scripts/local-fallback-occurrence-{0}.ps1' -f [guid]::NewGuid().ToString('N'))
        $absolutePath = Join-Path $repoRoot ($relativePath -replace '/', '\\')
        [System.IO.File]::WriteAllText($absolutePath, "Write-Output 'TARGET'`nWrite-Output 'TARGET'`n", (New-Object System.Text.UTF8Encoding($false)))

        $promptText = @"
Update $relativePath.
Edit Mode: replace_text
Occurrence: last
Minimum Occurrences: 2
Old Text: Write-Output 'TARGET'
New Text: Write-Output 'TARGET_LAST_REPLACED'
Validation Pattern: TARGET_LAST_REPLACED
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext -TaskId 'TSK-LF-OCCURRENCE-LAST' -ObjectiveId 'OBJ-LF' -Title 'Patch last occurrence' -Scope ("Patch $relativePath with a bounded replace_text change against the last occurrence.") -PromptPath $promptPath -Metadata @{ task_category = 'code_change' }

        $result = Invoke-LocalExecutionEngine -Context $context
        $updated = [string](Get-Content -Path $absolutePath -Raw)

        [string]$result.status | Should Be 'completed'
        [string]@($result.files_changed)[0] | Should Be $relativePath
        ($updated.IndexOf("Write-Output 'TARGET'") -lt $updated.IndexOf("Write-Output 'TARGET_LAST_REPLACED'")) | Should Be $true

        Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        Remove-Item -Path $absolutePath -Force
    }

    It 'parks stale recovery replace_text when validation pattern is already present' {
        $relativePath = ('scripts/local-fallback-stale-recovery-{0}.ps1' -f [guid]::NewGuid().ToString('N'))
        $absolutePath = Join-Path $repoRoot ($relativePath -replace '/', '\\')
        [System.IO.File]::WriteAllText($absolutePath, "Write-Output 'REQUESTED_STATE_PRESENT'`n", (New-Object System.Text.UTF8Encoding($false)))

        $promptText = @"
Target File: $relativePath
Recovery Mode: failed_material_patch
Required behavior: when a failed recovery task's old replace_text snippet is absent but its validation pattern is already present, park it as already_satisfied_with_evidence.
Edit Mode: replace_text
Old Text: OLD_STATE_THAT_IS_GONE
New Text: Write-Output 'REQUESTED_STATE_PRESENT'
Validation Pattern: REQUESTED_STATE_PRESENT
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext -TaskId 'TSK-LF-STALE-RECOVERY' -ObjectiveId 'OBJ-LF' -Title 'Park stale recovery' -Scope ("Recover stale failed-patch task for $relativePath.") -PromptPath $promptPath -Metadata @{ task_category = 'code_change'; local_fallback_target_file = $relativePath }

        $result = Invoke-LocalExecutionEngine -Context $context

        [string]$result.status | Should Be 'completed'
        [bool]$result.no_change_required | Should Be $true
        @($result.files_changed | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count | Should Be 0
        [string]$result.diff_summary | Should Match 'Parked stale recovery'
        @($result.validation_results | Where-Object { [string]$_.name -eq 'stale_recovery_already_satisfied_no_file_change_expected' -and [bool]$_.passed }).Count | Should Be 1
        ([string](Get-Content -Path $absolutePath -Raw)) | Should Match 'REQUESTED_STATE_PRESENT'

        Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        Remove-Item -Path $absolutePath -Force
    }

    It 'writes corrected patch synthesis practice evidence with inspected current-code anchors' {
        $originalRoot = $script:LocalEngineRepoRoot
        $tempRoot = Join-Path $repoRoot ('tod/out/tests/local-fallback-practice-' + [guid]::NewGuid().ToString('N'))
        $target = Join-Path $tempRoot 'runtime_remote_training/TOD_CORRECTED_PATCH_SYNTHESIS_PRACTICE_V1.latest.json'
        try {
            $script:LocalEngineRepoRoot = $tempRoot
            $inspectedTarget = Join-Path $tempRoot 'scripts/generate_mim_tod_training_scoreboard.py'
            New-Item -ItemType Directory -Path (Split-Path -Parent $inspectedTarget) -Force | Out-Null
            [System.IO.File]::WriteAllText($inspectedTarget, 'print("scoreboard")', (New-Object System.Text.UTF8Encoding($false)))

            $seed = [pscustomobject]@{
                status = 'ready_for_tod_attempt'
                exercise_id = 'practice-test'
                required_outputs = @('inspected_target_file', 'current_anchor_line_or_hash', 'credit_decision')
            } | ConvertTo-Json -Depth 5
            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            [System.IO.File]::WriteAllText($target, $seed, (New-Object System.Text.UTF8Encoding($false)))

            $promptPath = New-LocalFallbackPromptFile -Content @'
Target File: runtime_remote_training/TOD_CORRECTED_PATCH_SYNTHESIS_PRACTICE_V1.latest.json
Edit Mode: artifact_write
Practice-only task for TOD-CORRECTED-PATCH-SYNTHESIS-PRACTICE-V1.
Produce a result artifact that fills these required_output fields: inspected_target_file, current_anchor_line_or_hash, why_inherited_old_text_is_stale_or_safe, proposed_edit_mode, proposed_old_text_or_exact_blocker, proposed_new_text_or_exact_blocker, validation_command, expected_validation_pattern, credit_decision.
'@
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-PRACTICE-ARTIFACT' -ObjectiveId 'OBJ-LF' -Title 'Practice artifact write' -Scope 'Produce corrected patch synthesis practice evidence.' -PromptPath $promptPath -Metadata @{ task_category = 'code_change' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $updated = Get-Content -Path $target -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            (@($result.files_changed) -contains 'runtime_remote_training/TOD_CORRECTED_PATCH_SYNTHESIS_PRACTICE_V1.latest.json') | Should Be $true
            [string]$updated.status | Should Be 'practice_blocked_with_current_code_inspection'
            [bool]$updated.required_outputs_filled | Should Be $true
            [string]$updated.target.inspected_target_file | Should Be 'scripts/generate_mim_tod_training_scoreboard.py'
            [string]$updated.target.credit_decision | Should Be 'no_credit_practice_blocker_only'
            [string]$updated.target.current_anchor_line_or_hash | Should Match 'sha256:'

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            $script:LocalEngineRepoRoot = $originalRoot
            if (Test-Path -Path $tempRoot) { Remove-Item -Path $tempRoot -Recurse -Force }
        }
    }

    It 'writes different-target discovery evidence even when scope names forbidden paths' {
        $originalRoot = $script:LocalEngineRepoRoot
        $tempRoot = Join-Path $repoRoot ('tod/out/tests/local-fallback-discovery-' + [guid]::NewGuid().ToString('N'))
        $relativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_DIFFERENT_TARGET_DISCOVERY_DRILL.latest.json'
        $target = Join-Path $tempRoot ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        try {
            $script:LocalEngineRepoRoot = $tempRoot
            foreach ($fixturePath in @(
                'tmp_remote_mim/core/routers/studio.py',
                'tmp_remote_mim/tests/test_studio_training_chat.py',
                'tools/score_mim_operator_impact_live_10.py',
                'tools/build_mim_operator_impact_scorecard.py'
            )) {
                $absoluteFixture = Join-Path $tempRoot ($fixturePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
                New-Item -ItemType Directory -Path (Split-Path -Parent $absoluteFixture) -Force | Out-Null
                [System.IO.File]::WriteAllText($absoluteFixture, ('# fixture: ' + $fixturePath), (New-Object System.Text.UTF8Encoding($false)))
            }

            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            [System.IO.File]::WriteAllText($target, '{}', (New-Object System.Text.UTF8Encoding($false)))

            $promptPath = New-LocalFallbackPromptFile -Content @'
Target File: runtime_remote_training/tod_independent_resolution_attempts/TOD_DIFFERENT_TARGET_DISCOVERY_DRILL.latest.json
Edit Mode: artifact_write
Validation Pattern: selected_candidate_or_none
Forbidden repeated targets: scripts/run_mim_durability_smoke_v2.py, tmp_remote_mim/core/routers/gateway.py, core/routers/gateway.py
Required output fields: inspected_files, candidate_count, selected_candidate_or_none, why_selected, validation_command, rollback_note, prevention_lesson, dave_needed
'@
            $scope = 'Inspect at least three current-code files, but do not patch scripts/run_mim_durability_smoke_v2.py, tmp_remote_mim/core/routers/gateway.py, or core/routers/gateway.py.'
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-DIFFERENT-TARGET-DISCOVERY' -ObjectiveId 'OBJ-LF' -Title 'Different target discovery drill' -Scope $scope -PromptPath $promptPath -Metadata @{ task_category = 'artifact_write' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $updated = Get-Content -Path $target -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            (@($result.files_changed) -contains $relativePath) | Should Be $true
            [string]$updated.status | Should Be 'candidate_selected'
            @($updated.inspected_files).Count | Should BeGreaterThan 2
            [string]$updated.selected_candidate_or_none.target_file | Should Be 'tmp_remote_mim/core/routers/studio.py'
            @($updated.selected_candidate_or_none.expected_changed_files) -contains 'tmp_remote_mim/tests/test_studio_training_chat.py' | Should Be $true
            [string]$updated.credit_decision.reason | Should Match 'Discovery artifact only'

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            $script:LocalEngineRepoRoot = $originalRoot
            if (Test-Path -Path $tempRoot) { Remove-Item -Path $tempRoot -Recurse -Force }
        }
    }

    It 'pivots different-target discovery away from forbidden Studio candidates' {
        $originalRoot = $script:LocalEngineRepoRoot
        $tempRoot = Join-Path $repoRoot ('tod/out/tests/local-fallback-discovery-pivot-' + [guid]::NewGuid().ToString('N'))
        $relativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_DIFFERENT_TARGET_DISCOVERY_DRILL.latest.json'
        $target = Join-Path $tempRoot ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        try {
            $script:LocalEngineRepoRoot = $tempRoot
            foreach ($fixturePath in @(
                'tmp_remote_mim/core/routers/studio.py',
                'tmp_remote_mim/tests/test_studio_training_chat.py',
                'tmp_remote_mim/core/routers/public_chat.py',
                'tmp_remote_mim/tests/test_public_chat_direct_answers.py',
                'tools/run_public_mim_general_conversation_smoke.py'
            )) {
                $absoluteFixture = Join-Path $tempRoot ($fixturePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
                New-Item -ItemType Directory -Path (Split-Path -Parent $absoluteFixture) -Force | Out-Null
                [System.IO.File]::WriteAllText($absoluteFixture, ('# fixture: ' + $fixturePath), (New-Object System.Text.UTF8Encoding($false)))
            }

            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            [System.IO.File]::WriteAllText($target, '{}', (New-Object System.Text.UTF8Encoding($false)))

            $promptPath = New-LocalFallbackPromptFile -Content @'
Target File: runtime_remote_training/tod_independent_resolution_attempts/TOD_DIFFERENT_TARGET_DISCOVERY_DRILL.latest.json
Edit Mode: artifact_write
Validation Pattern: selected_candidate_or_none
Forbidden repeated targets: tmp_remote_mim/core/routers/studio.py, studio_training_live_mode_selection_response_guard
Required output fields: inspected_files, candidate_count, selected_candidate_or_none, why_selected, validation_command, rollback_note, prevention_lesson, dave_needed
'@
            $scope = 'Do not reuse Studio recommendation packet candidates. Inspect a different current-code live path and publish a candidate or blocker.'
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-DIFFERENT-TARGET-PIVOT' -ObjectiveId 'OBJ-LF' -Title 'Different target discovery pivot' -Scope $scope -PromptPath $promptPath -Metadata @{ task_category = 'artifact_write' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $updated = Get-Content -Path $target -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            [string]$updated.status | Should Be 'candidate_selected'
            [string]$updated.selected_candidate_or_none.target_file | Should Be 'tmp_remote_mim/core/routers/public_chat.py'
            [string]$updated.selected_candidate_or_none.candidate_key | Should Be 'public_chat_context_followup_direct_answer_guard'
            @($updated.inspected_files) -contains 'tmp_remote_mim/core/routers/public_chat.py' | Should Be $true
            [string]$updated.why_selected | Should Match 'not forbidden'
            [string]$updated.credit_decision.reason | Should Match 'Discovery artifact only'

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            $script:LocalEngineRepoRoot = $originalRoot
            if (Test-Path -Path $tempRoot) { Remove-Item -Path $tempRoot -Recurse -Force }
        }
    }

    It 'uses latest drill forbidden paths when choosing a different-target discovery candidate' {
        $originalRoot = $script:LocalEngineRepoRoot
        $tempRoot = Join-Path $repoRoot ('tod/out/tests/local-fallback-discovery-current-drill-' + [guid]::NewGuid().ToString('N'))
        $relativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_DIFFERENT_TARGET_DISCOVERY_DRILL.latest.json'
        $target = Join-Path $tempRoot ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        try {
            $script:LocalEngineRepoRoot = $tempRoot
            foreach ($fixturePath in @(
                'tmp_remote_mim/core/routers/studio.py',
                'tmp_remote_mim/tests/test_studio_training_chat.py',
                'tmp_remote_mim/core/routers/public_chat.py',
                'tmp_remote_mim/tests/test_public_chat_direct_answers.py',
                'tmp_remote_mim/core/routers/tod_ui.py',
                'tmp_remote_mim/tests/integration/test_tod_ui_console.py',
                'runtime/shared/TOD_EXECUTION_RESULT.latest.json'
            )) {
                $absoluteFixture = Join-Path $tempRoot ($fixturePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
                New-Item -ItemType Directory -Path (Split-Path -Parent $absoluteFixture) -Force | Out-Null
                [System.IO.File]::WriteAllText($absoluteFixture, ('# fixture: ' + $fixturePath), (New-Object System.Text.UTF8Encoding($false)))
            }

            $interventionPath = Join-Path $tempRoot 'runtime_remote_training/codex_training_interventions/CODEX_TOD_DIFFERENT_TARGET_DISCOVERY_DRILL_20260616T2010Z.latest.json'
            New-Item -ItemType Directory -Path (Split-Path -Parent $interventionPath) -Force | Out-Null
            [pscustomobject]@{
                artifact_version = 'codex-training-intervention-v1'
                generated_at = '2026-06-16T20:10:00Z'
                status = 'training_instruction_issued'
                tod_training_instruction = [pscustomobject]@{
                    forbidden_paths = @(
                        'tmp_remote_mim/core/routers/public_chat.py'
                    )
                }
            } | ConvertTo-Json -Depth 8 | Set-Content -Path $interventionPath -Encoding UTF8

            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            [System.IO.File]::WriteAllText($target, '{}', (New-Object System.Text.UTF8Encoding($false)))

            $promptPath = New-LocalFallbackPromptFile -Content @'
Target File: runtime_remote_training/tod_independent_resolution_attempts/TOD_DIFFERENT_TARGET_DISCOVERY_DRILL.latest.json
Edit Mode: artifact_write
Validation Pattern: selected_candidate_or_none
Forbidden repeated targets: tmp_remote_mim/core/routers/studio.py, studio_training_live_mode_selection_response_guard
Required output fields: inspected_files, candidate_count, selected_candidate_or_none, why_selected, validation_command, rollback_note, prevention_lesson, dave_needed
'@
            $scope = 'Do not reuse Studio candidates. Also honor current drill forbidden paths from codex_training_interventions before choosing a discovery target.'
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-DIFFERENT-TARGET-CURRENT-DRILL' -ObjectiveId 'OBJ-LF' -Title 'Different target discovery current drill pivot' -Scope $scope -PromptPath $promptPath -Metadata @{ task_category = 'artifact_write' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $updated = Get-Content -Path $target -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            [string]$updated.status | Should Be 'candidate_selected'
            [string]$updated.selected_candidate_or_none.target_file | Should Be 'tmp_remote_mim/core/routers/tod_ui.py'
            [string]$updated.selected_candidate_or_none.candidate_key | Should Be 'tod_ui_chat_payload_latest_execution_guard'
            @($updated.inspected_files) -contains 'tmp_remote_mim/core/routers/tod_ui.py' | Should Be $true
            [string]$updated.why_selected | Should Match 'not forbidden'

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            $script:LocalEngineRepoRoot = $originalRoot
            if (Test-Path -Path $tempRoot) { Remove-Item -Path $tempRoot -Recurse -Force }
        }
    }

    It 'broadens different-target discovery to inquiry router when prior router candidates are exhausted' {
        $originalRoot = $script:LocalEngineRepoRoot
        $tempRoot = Join-Path $repoRoot ('tod/out/tests/local-fallback-discovery-composer-' + [guid]::NewGuid().ToString('N'))
        $relativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_DIFFERENT_TARGET_DISCOVERY_DRILL.latest.json'
        $target = Join-Path $tempRoot ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        try {
            $script:LocalEngineRepoRoot = $tempRoot
            foreach ($fixturePath in @(
                'tmp_remote_mim/core/routers/studio.py',
                'tmp_remote_mim/tests/test_studio_training_chat.py',
                'tmp_remote_mim/core/routers/public_chat.py',
                'tmp_remote_mim/tests/test_public_chat_direct_answers.py',
                'tmp_remote_mim/core/routers/tod_ui.py',
                'tmp_remote_mim/tests/integration/test_tod_ui_console.py',
                'runtime/shared/TOD_EXECUTION_RESULT.latest.json',
                'tmp_remote_mim/core/routers/gateway.py',
                'tmp_remote_mim/tests/integration/test_mim_tod_handoff_gateway.py',
                'runtime/shared/MIM_TOD_TASK_REQUEST.latest.json',
                'tmp_remote_mim/core/routers/tasks.py',
                'tmp_remote_mim/core/schemas.py',
                'tmp_remote_mim/core/objective_lifecycle.py',
                'tmp_remote_mim/core/routers/operator.py',
                'tmp_remote_mim/core/operator_resolution_service.py',
                'tmp_remote_mim/core/operator_commitment_monitoring_service.py',
                'tmp_remote_mim/core/routers/inquiry.py',
                'tmp_remote_mim/core/inquiry_service.py',
                'tmp_remote_mim/core/schemas.py',
                'tmp_remote_mim/core/communication_composer.py',
                'tools/score_mim_operator_impact_live_10.py'
            )) {
                $absoluteFixture = Join-Path $tempRoot ($fixturePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
                New-Item -ItemType Directory -Path (Split-Path -Parent $absoluteFixture) -Force | Out-Null
                [System.IO.File]::WriteAllText($absoluteFixture, ('# fixture: ' + $fixturePath), (New-Object System.Text.UTF8Encoding($false)))
            }

            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            [System.IO.File]::WriteAllText($target, '{}', (New-Object System.Text.UTF8Encoding($false)))

            $promptPath = New-LocalFallbackPromptFile -Content @'
Target File: runtime_remote_training/tod_independent_resolution_attempts/TOD_DIFFERENT_TARGET_DISCOVERY_DRILL.latest.json
Edit Mode: artifact_write
Validation Pattern: selected_candidate_or_none
Forbidden repeated targets: tmp_remote_mim/core/routers/studio.py, tmp_remote_mim/core/routers/public_chat.py, tmp_remote_mim/core/routers/tod_ui.py, tmp_remote_mim/core/routers/gateway.py, tmp_remote_mim/core/routers/tasks.py, tmp_remote_mim/core/routers/operator.py, tmp_remote_mim/core/interaction_quality_dashboard.py
Required output fields: inspected_files, candidate_count, selected_candidate_or_none, why_selected, validation_command, rollback_note, prevention_lesson, dave_needed
'@
            $scope = 'Router discovery candidates are consumed or already applied. Inspect a different current-code live conversation surface.'
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-DIFFERENT-TARGET-COMPOSER' -ObjectiveId 'OBJ-LF' -Title 'Different target discovery composer pivot' -Scope $scope -PromptPath $promptPath -Metadata @{ task_category = 'artifact_write' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $updated = Get-Content -Path $target -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            [string]$updated.status | Should Be 'candidate_selected'
            [string]$updated.selected_candidate_or_none.target_file | Should Be 'tmp_remote_mim/core/routers/inquiry.py'
            [string]$updated.selected_candidate_or_none.candidate_key | Should Be 'inquiry_router_answer_context_evidence_guard'
            @($updated.inspected_files) -contains 'tmp_remote_mim/core/routers/inquiry.py' | Should Be $true

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            $script:LocalEngineRepoRoot = $originalRoot
            if (Test-Path -Path $tempRoot) { Remove-Item -Path $tempRoot -Recurse -Force }
        }
    }

    It 'skips different-target discovery candidates whose applied marker already exists' {
        $originalRoot = $script:LocalEngineRepoRoot
        $tempRoot = Join-Path $repoRoot ('tod/out/tests/local-fallback-discovery-fresh-marker-' + [guid]::NewGuid().ToString('N'))
        $relativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_DIFFERENT_TARGET_DISCOVERY_DRILL.latest.json'
        $target = Join-Path $tempRoot ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        try {
            $script:LocalEngineRepoRoot = $tempRoot
            $fixtures = @{
                'tmp_remote_mim/core/routers/studio.py' = '# forbidden studio fixture'
                'tmp_remote_mim/tests/test_studio_training_chat.py' = '# fixture'
                'tmp_remote_mim/core/routers/public_chat.py' = '# forbidden public chat fixture'
                'tmp_remote_mim/tests/test_public_chat_direct_answers.py' = '# fixture'
                'tmp_remote_mim/core/routers/tod_ui.py' = '# forbidden tod ui fixture'
                'tmp_remote_mim/tests/integration/test_tod_ui_console.py' = '# fixture'
                'runtime/shared/TOD_EXECUTION_RESULT.latest.json' = '{}'
                'tmp_remote_mim/core/routers/gateway.py' = '# forbidden gateway fixture'
                'tmp_remote_mim/tests/integration/test_mim_tod_handoff_gateway.py' = '# fixture'
                'runtime/shared/MIM_TOD_TASK_REQUEST.latest.json' = '{}'
                'tmp_remote_mim/core/routers/tasks.py' = '# forbidden tasks fixture'
                'tmp_remote_mim/core/schemas.py' = '# fixture'
                'tmp_remote_mim/core/objective_lifecycle.py' = '# fixture'
                'tmp_remote_mim/core/routers/inquiry.py' = 'answer_context_evidence = True'
                'tmp_remote_mim/core/inquiry_service.py' = '# fixture'
                'tmp_remote_mim/core/routers/results.py' = '# fresh results target'
                'tmp_remote_mim/core/autonomy_driver_service.py' = '# fixture'
                'tmp_remote_mim/core/routers/operator.py' = 'operator_action_required = True'
                'tmp_remote_mim/core/operator_resolution_service.py' = '# fixture'
                'tmp_remote_mim/core/operator_commitment_monitoring_service.py' = '# fixture'
                'tmp_remote_mim/core/communication_composer.py' = 'message = "clear answer or next useful action"'
                'tools/score_mim_operator_impact_live_10.py' = '# fixture'
                'tmp_remote_mim/core/interaction_quality_dashboard.py' = '# fresh dashboard target'
            }
            foreach ($fixturePath in $fixtures.Keys) {
                $absoluteFixture = Join-Path $tempRoot ($fixturePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
                New-Item -ItemType Directory -Path (Split-Path -Parent $absoluteFixture) -Force | Out-Null
                [System.IO.File]::WriteAllText($absoluteFixture, [string]$fixtures[$fixturePath], (New-Object System.Text.UTF8Encoding($false)))
            }

            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            [System.IO.File]::WriteAllText($target, '{}', (New-Object System.Text.UTF8Encoding($false)))

            $promptPath = New-LocalFallbackPromptFile -Content @'
Target File: runtime_remote_training/tod_independent_resolution_attempts/TOD_DIFFERENT_TARGET_DISCOVERY_DRILL.latest.json
Edit Mode: artifact_write
Validation Pattern: selected_candidate_or_none
Forbidden repeated targets: tmp_remote_mim/core/routers/studio.py, tmp_remote_mim/core/routers/public_chat.py, tmp_remote_mim/core/routers/tod_ui.py, tmp_remote_mim/core/routers/gateway.py, tmp_remote_mim/core/routers/tasks.py
Required output fields: inspected_files, candidate_count, selected_candidate_or_none, why_selected, validation_command, rollback_note, prevention_lesson, dave_needed
'@
            $scope = 'Operator and communication composer candidates are already applied. Discovery should select the next fresh live-path target instead of repeating no-op packet candidates.'
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-DIFFERENT-TARGET-FRESH-MARKER' -ObjectiveId 'OBJ-LF' -Title 'Different target discovery applied marker skip' -Scope $scope -PromptPath $promptPath -Metadata @{ task_category = 'artifact_write' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $updated = Get-Content -Path $target -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            [string]$updated.status | Should Be 'candidate_selected'
            [string]$updated.selected_candidate_or_none.target_file | Should Be 'tmp_remote_mim/core/routers/results.py'
            [string]$updated.selected_candidate_or_none.candidate_key | Should Be 'results_router_objective_recompute_evidence_guard'
            @($updated.inspected_files) -contains 'tmp_remote_mim/core/routers/results.py' | Should Be $true

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            $script:LocalEngineRepoRoot = $originalRoot
            if (Test-Path -Path $tempRoot) { Remove-Item -Path $tempRoot -Recurse -Force }
        }
    }

    It 'blocks generic packet formation when the current-code anchor is unavailable' {
        $originalRoot = $script:LocalEngineRepoRoot
        $tempRoot = Join-Path $repoRoot ('tod/out/tests/local-fallback-packet-' + [guid]::NewGuid().ToString('N'))
        $relativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_PACKET_FORMATION_EXPLICIT_ARTIFACT_WRITE_2026_06_14.latest.json'
        $target = Join-Path $tempRoot ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $durabilityPath = Join-Path $tempRoot 'scripts/run_mim_durability_smoke_v2.py'
        $durabilityFixture = @'
def no_status_report_leakage(reply):
    status_boilerplate = (
        "training is active, but outcome improvement is not proven yet",
        "training is active, but the useful question is whether it is changing behavior",
        "my current weakness is:",
        "my mode-selection score",
        "the outcome verdict is",
        "i default to status reporting",
        "not whether the scoreboard looks busy",
        "mim communication:",
        "mim/tod real movement:",
        "mim operator impact:",
    )
    return True
'@
        try {
            $script:LocalEngineRepoRoot = $tempRoot
            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            New-Item -ItemType Directory -Path (Split-Path -Parent $durabilityPath) -Force | Out-Null
            Set-LocalFallbackTestFileText -Path $durabilityPath -Content $durabilityFixture

            $promptPath = New-LocalFallbackPromptFile -Content @"
Target File: $relativePath
Edit Mode: artifact_write
Validation Pattern: packet_candidate_ready
Packet formation task for the next independent TOD resolution attempt.
"@
            $scope = 'Publish packet_candidate_ready evidence for a later independent runtime-code task. Dave-needed no unless credentials/external service are required.'
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-PACKET-ARTIFACT' -ObjectiveId 'OBJ-LF' -Title 'Packet formation artifact write' -Scope $scope -PromptPath $promptPath -Metadata @{ task_category = 'packet_formation' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $updated = Get-Content -Path $target -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            (@($result.files_changed) -contains $relativePath) | Should Be $true
            [string]$updated.status | Should Be 'blocked_current_code_anchor_missing'
            [bool]$updated.packet_candidate_ready | Should Be $false
            [bool]$updated.credit_decision.independent_tod_resolution | Should Be $false
            [string]$updated.blocker.target_file | Should Be 'scripts/run_mim_durability_smoke_v2.py'
            [string]$updated.blocker.missing_anchor_or_field | Should Be 'old_text'
            [string]$updated.blocker.required_next_action | Should Match 'exact old_text/new_text from the current code'

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            $script:LocalEngineRepoRoot = $originalRoot
            if (Test-Path -Path $tempRoot) { Remove-Item -Path $tempRoot -Recurse -Force }
        }
    }

    It 'forms an operator router packet candidate from the discovery-selected target' {
        $originalRoot = $script:LocalEngineRepoRoot
        $tempRoot = Join-Path $repoRoot ('tod/out/tests/local-fallback-operator-packet-' + [guid]::NewGuid().ToString('N'))
        $relativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_PACKET_FORMATION_OPERATOR_PACKET_TEST.latest.json'
        $target = Join-Path $tempRoot ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        try {
            $script:LocalEngineRepoRoot = $tempRoot
            $operatorRelativePath = 'tmp_remote_mim/core/routers/operator.py'
            $operatorPath = Join-Path $tempRoot ($operatorRelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
            $operatorFixture = @'
def _to_operator_execution(execution, resolution, event):
    feedback = execution.feedback_json if isinstance(execution.feedback_json, dict) else {}
    return {
        "execution_id": execution.id,
        "input_event_id": execution.input_event_id,
        "resolution_id": execution.resolution_id,
        "goal_id": execution.goal_id,
        "capability_name": execution.capability_name,
        "status": execution.status,
        "dispatch_decision": execution.dispatch_decision,
        "reason": execution.reason,
        "exception_reason": _normalize_exception_reason(execution, resolution, event),
        "requested_executor": execution.requested_executor,
        "safety_mode": execution.safety_mode,
        "trace_id": execution.trace_id,
        "managed_scope": execution.managed_scope,
        "arguments_json": execution.arguments_json,
        "feedback_json": feedback,
        "replan_required": bool(feedback.get("replan_required", False)),
        "latest_replan_outcome": str(feedback.get("latest_replan_outcome", "")),
    }
'@
            Set-LocalFallbackTestFileText -Path $operatorPath -Content $operatorFixture
            $todPath = Join-Path $tempRoot 'scripts/TOD.ps1'
            Set-LocalFallbackTestFileText -Path $todPath -Content @'
function Write-PacketProofParserFixture {
    $fields = @(
        'Validation Command',
        'Closure Evidence',
        'Prevention Lesson',
        'Dave Needed',
        'Required Packet Fields',
        'Inspect Target File',
        'Anchor'
    )
}
'@

            $attemptsDir = Join-Path $tempRoot 'runtime_remote_training/tod_independent_resolution_attempts'
            New-Item -ItemType Directory -Path $attemptsDir -Force | Out-Null
            $discoveryArtifact = [ordered]@{
                artifact_type = 'tod_different_target_discovery_drill'
                status = 'candidate_selected'
                selected_candidate_or_none = [ordered]@{
                    candidate_key = 'operator_router_exception_reason_actionability_guard'
                    target_file = $operatorRelativePath
                }
            }
            [System.IO.File]::WriteAllText(
                (Join-Path $attemptsDir 'TOD_DIFFERENT_TARGET_DISCOVERY_DRILL.latest.json'),
                ($discoveryArtifact | ConvertTo-Json -Depth 8),
                (New-Object System.Text.UTF8Encoding($false))
            )
            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            [System.IO.File]::WriteAllText($target, '{}', (New-Object System.Text.UTF8Encoding($false)))

            $promptPath = New-LocalFallbackPromptFile -Content @"
Target File: $relativePath
Edit Mode: artifact_write
Validation Pattern: packet_candidate_ready
Recovery Materialization Source: consumed_packet_anchor_requires_different_candidate
Focus: materialized bounded edit proof for TOD recovery. Include Prevention Lesson, Dave Needed, Required Packet Fields, and Inspect Target File parsing.
Use the fresh operator router discovery target and publish exact old_text/new_text. No implementation credit.
"@
            $scope = 'Publish inspected packet candidate for operator router execution evidence. No implementation credit. Dave-needed no.'
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-OPERATOR-PACKET' -ObjectiveId 'OBJ-LF' -Title 'Operator router packet candidate artifact write' -Scope $scope -PromptPath $promptPath -Metadata @{ task_category = 'packet_formation' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $updated = Get-Content -Path $target -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            (@($result.files_changed) -contains $relativePath) | Should Be $true
            [string]$updated.status | Should Be 'packet_candidate_ready'
            [bool]$updated.packet_candidate_ready | Should Be $true
            [string]$updated.packet.selected_candidate | Should Be 'operator_router_action_required_execution_payload'
            [string]$updated.packet.target_file | Should Be $operatorRelativePath
            [string]$updated.packet.old_text | Should Match '_normalize_exception_reason'
            [string]$updated.packet.new_text | Should Match 'operator_action_required'
            [string]$updated.packet.validation_command | Should Match 'operator.py'
            [string]$updated.packet.validation_pattern | Should Be '"operator_action_required"'
            [bool]$updated.credit_decision.independent_tod_resolution | Should Be $false
            [bool]$updated.credit_decision.meaningful_tod_implementation | Should Be $false

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            $script:LocalEngineRepoRoot = $originalRoot
            if (Test-Path -Path $tempRoot) { Remove-Item -Path $tempRoot -Recurse -Force }
        }
    }

    It 'forms an inquiry router packet candidate from the discovery-selected target' {
        $originalRoot = $script:LocalEngineRepoRoot
        $tempRoot = Join-Path $repoRoot ('tod/out/tests/local-fallback-inquiry-packet-' + [guid]::NewGuid().ToString('N'))
        $relativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_PACKET_FORMATION_INQUIRY_PACKET_TEST.latest.json'
        $target = Join-Path $tempRoot ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        try {
            $script:LocalEngineRepoRoot = $tempRoot
            $inquiryRelativePath = 'tmp_remote_mim/core/routers/inquiry.py'
            $inquiryPath = Join-Path $tempRoot ($inquiryRelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
            $inquiryFixture = @'
async def answer_inquiry_question_endpoint():
    return {
        "answered": True,
        "applied_effect": applied_effect,
        "question": to_inquiry_question_out(updated),
    }
'@
            Set-LocalFallbackTestFileText -Path $inquiryPath -Content $inquiryFixture

            $attemptsDir = Join-Path $tempRoot 'runtime_remote_training/tod_independent_resolution_attempts'
            New-Item -ItemType Directory -Path $attemptsDir -Force | Out-Null
            $discoveryArtifact = [ordered]@{
                artifact_type = 'tod_different_target_discovery_drill'
                status = 'candidate_selected'
                selected_candidate_or_none = [ordered]@{
                    candidate_key = 'inquiry_router_answer_context_evidence_guard'
                    target_file = $inquiryRelativePath
                }
            }
            [System.IO.File]::WriteAllText(
                (Join-Path $attemptsDir 'TOD_DIFFERENT_TARGET_DISCOVERY_DRILL.latest.json'),
                ($discoveryArtifact | ConvertTo-Json -Depth 8),
                (New-Object System.Text.UTF8Encoding($false))
            )
            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            [System.IO.File]::WriteAllText($target, '{}', (New-Object System.Text.UTF8Encoding($false)))

            $promptPath = New-LocalFallbackPromptFile -Content @"
Target File: $relativePath
Edit Mode: artifact_write
Validation Pattern: packet_candidate_ready
Recovery Materialization Source: different_target_discovery_candidate
Use the fresh inquiry router discovery target and publish exact old_text/new_text. No implementation credit.
"@
            $scope = 'Publish inspected packet candidate for inquiry answer response evidence. No implementation credit. Dave-needed no.'
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-INQUIRY-PACKET' -ObjectiveId 'OBJ-LF' -Title 'Inquiry router packet candidate artifact write' -Scope $scope -PromptPath $promptPath -Metadata @{ task_category = 'packet_formation' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $updated = Get-Content -Path $target -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            (@($result.files_changed) -contains $relativePath) | Should Be $true
            [string]$updated.status | Should Be 'packet_candidate_ready'
            [bool]$updated.packet_candidate_ready | Should Be $true
            [string]$updated.packet.selected_candidate | Should Be 'inquiry_router_answer_context_evidence_payload'
            [string]$updated.packet.target_file | Should Be $inquiryRelativePath
            [string]$updated.packet.old_text | Should Match 'applied_effect'
            [string]$updated.packet.new_text | Should Match 'answer_context_evidence'
            [string]$updated.packet.validation_command | Should Match 'inquiry.py'
            [string]$updated.packet.validation_pattern | Should Be '"answer_context_evidence"'
            [bool]$updated.credit_decision.independent_tod_resolution | Should Be $false
            [bool]$updated.credit_decision.meaningful_tod_implementation | Should Be $false

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            $script:LocalEngineRepoRoot = $originalRoot
            if (Test-Path -Path $tempRoot) { Remove-Item -Path $tempRoot -Recurse -Force }
        }
    }

    It 'blocks packet formation as already applied before reporting a stale old_text anchor' {
        $originalRoot = $script:LocalEngineRepoRoot
        $tempRoot = Join-Path $repoRoot ('tod/out/tests/local-fallback-already-applied-' + [guid]::NewGuid().ToString('N'))
        $relativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_PACKET_FORMATION_ALREADY_APPLIED_TEST.latest.json'
        $target = Join-Path $tempRoot ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $originalContent = if (Test-Path -Path $target) { Get-Content -Path $target -Raw } else { $null }
        $durabilityPath = Join-Path $tempRoot 'scripts/run_mim_durability_smoke_v2.py'
        $durabilityOriginalContent = if (Test-Path -Path $durabilityPath) { Get-Content -Path $durabilityPath -Raw } else { $null }
        $discoveryRelativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_DIFFERENT_TARGET_DISCOVERY_DRILL.latest.json'
        $discoveryTarget = Join-Path $tempRoot ($discoveryRelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $discoveryOriginalContent = if (Test-Path -Path $discoveryTarget) { Get-Content -Path $discoveryTarget -Raw } else { $null }
        $studioPath = Join-Path $tempRoot 'tmp_remote_mim/core/routers/studio.py'
        $studioOriginalContent = if (Test-Path -Path $studioPath) { Get-Content -Path $studioPath -Raw } else { $null }
        $todPath = Join-Path $tempRoot 'scripts/TOD.ps1'
        $todOriginalContent = if (Test-Path -Path $todPath) { Get-Content -Path $todPath -Raw } else { $null }

        try {
            $script:LocalEngineRepoRoot = $tempRoot
            $discoveryArtifact = [ordered]@{
                artifact_type = 'tod_different_target_discovery'
                status = 'candidate_selected'
                selected_candidate_or_none = [ordered]@{
                    target_file = 'tmp_remote_mim/core/routers/studio.py'
                    validation_command = 'python -m unittest tmp_remote_mim.tests.test_studio_training_chat'
                    expected_changed_files = @('tmp_remote_mim/core/routers/studio.py')
                }
            }
            New-Item -ItemType Directory -Path (Split-Path -Parent $discoveryTarget) -Force | Out-Null
            [System.IO.File]::WriteAllText($discoveryTarget, ($discoveryArtifact | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))
            New-Item -ItemType Directory -Path (Split-Path -Parent $studioPath) -Force | Out-Null
            [System.IO.File]::WriteAllText($studioPath, "# TOD current-code packet materialization`n", (New-Object System.Text.UTF8Encoding($false)))
            New-Item -ItemType Directory -Path (Split-Path -Parent $todPath) -Force | Out-Null
            if ($null -ne $todOriginalContent -and -not $todOriginalContent.Contains("'Prevention Lesson',")) {
                [System.IO.File]::WriteAllText($todPath, ($todOriginalContent.TrimEnd() + "`n        'Prevention Lesson',`n"), (New-Object System.Text.UTF8Encoding($false)))
            }
            if ($null -ne $studioOriginalContent -and -not $studioOriginalContent.Contains('TOD current-code packet materialization')) {
                [System.IO.File]::WriteAllText($studioPath, ($studioOriginalContent.TrimEnd() + "`n# TOD current-code packet materialization`n"), (New-Object System.Text.UTF8Encoding($false)))
            }

            $seededContent = @'
def no_status_report_leakage(reply):
    status_boilerplate = (
        "training is active, but outcome improvement is not proven yet",
        "training is active, but the useful question is whether it is changing behavior",
        "my current weakness is:",
        "my mode-selection score",
        "the outcome verdict is",
        "i default to status reporting",
        "not whether the scoreboard looks busy",
        "here are the current scorecard numbers",
        "mim communication:",
        "mim/tod real movement:",
        "mim operator impact:",
    )
    return True
'@
            Set-LocalFallbackTestFileText -Path $durabilityPath -Content $seededContent

            $promptPath = New-LocalFallbackPromptFile -Content @"
Target File: $relativePath
Edit Mode: artifact_write
Validation Pattern: packet_candidate_ready
Packet formation task for the next independent TOD resolution attempt.
"@
            $scope = 'Publish packet_candidate_ready evidence for a later independent runtime-code task. Dave-needed no unless credentials/external service are required.'
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-PACKET-ALREADY-APPLIED' -ObjectiveId 'OBJ-LF' -Title 'Packet formation already applied' -Scope $scope -PromptPath $promptPath -Metadata @{ task_category = 'packet_formation' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $updated = Get-Content -Path $target -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            [string]$updated.status | Should Be 'blocked_candidate_already_applied'
            [bool]$updated.packet_candidate_ready | Should Be $false
            (@($updated.blocker.inspected_files).Count -gt 0) | Should Be $true
            [string]$updated.blocker.missing_anchor_or_field | Should Be 'fresh_old_text'
            [string]$updated.blocker.required_next_action | Should Match 'different current-code behavior gap'

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            $script:LocalEngineRepoRoot = $originalRoot
            if ([string]::IsNullOrWhiteSpace($originalContent)) {
                if (Test-Path -Path $target) { Remove-Item -Path $target -Force }
            }
            else {
                [System.IO.File]::WriteAllText($target, $originalContent, (New-Object System.Text.UTF8Encoding($false)))
            }
            if ($null -ne $durabilityOriginalContent) {
                Set-LocalFallbackTestFileText -Path $durabilityPath -Content $durabilityOriginalContent
            }
            if ([string]::IsNullOrWhiteSpace($discoveryOriginalContent)) {
                if (Test-Path -Path $discoveryTarget) { Remove-Item -Path $discoveryTarget -Force }
            }
            else {
                [System.IO.File]::WriteAllText($discoveryTarget, $discoveryOriginalContent, (New-Object System.Text.UTF8Encoding($false)))
            }
            if ($null -ne $studioOriginalContent) {
                [System.IO.File]::WriteAllText($studioPath, $studioOriginalContent, (New-Object System.Text.UTF8Encoding($false)))
            }
            if ($null -ne $todOriginalContent) {
                [System.IO.File]::WriteAllText($todPath, $todOriginalContent, (New-Object System.Text.UTF8Encoding($false)))
            }
            if (Test-Path -Path $tempRoot) { Remove-Item -Path $tempRoot -Recurse -Force }
        }
    }

    It 'blocks stale synthesis packet formation with inspected current-code evidence' {
        $relativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_PACKET_FORMATION_SYNTHESIS_TEST.latest.json'
        $target = Join-Path $repoRoot ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $originalContent = if (Test-Path -Path $target) { Get-Content -Path $target -Raw } else { $null }

        try {
            $promptPath = New-LocalFallbackPromptFile -Content @"
Target File: $relativePath
Edit Mode: artifact_write
Validation Pattern: packet_candidate_ready
Use stale_synthesis_reason_specificity evidence to form the next bounded runtime-code packet from current repository code.
Required output: publish one tod_independent_resolution_attempts packet candidate artifact with packet_candidate_ready=true.
"@
            $scope = 'Repair synthesis candidate materialization from current code; include candidate_key in the next current-code packet fields.'
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-PACKET-SYNTHESIS' -ObjectiveId 'OBJ-LF' -Title 'Packet formation synthesis target' -Scope $scope -PromptPath $promptPath -Metadata @{ task_category = 'packet_formation' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $updated = Get-Content -Path $target -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            [string]$updated.status | Should Be 'blocked_current_code_anchor_missing'
            [bool]$updated.packet_candidate_ready | Should Be $false
            [string]$updated.blocker.target_file | Should Be 'scripts/TOD.ps1'
            [string]$updated.blocker.reason | Should Match 'could not find the exact current summary block'
            [string]$updated.blocker.required_next_action | Should Match 'Inspect the current target file'
            [string]$updated.blocker.missing_anchor_or_field | Should Be 'old_text'

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            if ([string]::IsNullOrWhiteSpace($originalContent)) {
                if (Test-Path -Path $target) { Remove-Item -Path $target -Force }
            }
            else {
                [System.IO.File]::WriteAllText($target, $originalContent, (New-Object System.Text.UTF8Encoding($false)))
            }
        }
    }

    It 'uses latest materialization blocker target for exact patch synthesis drills' {
        $originalRoot = $script:LocalEngineRepoRoot
        $tempRoot = Join-Path $repoRoot ('tod/out/tests/local-fallback-exact-drill-latest-' + [guid]::NewGuid().ToString('N'))
        $relativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_EXACT_PATCH_SYNTHESIS_DRILL_OPERATOR_TEST.latest.json'
        $target = Join-Path $tempRoot ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        try {
            $script:LocalEngineRepoRoot = $tempRoot
            $operatorRelativePath = 'tmp_remote_mim/core/routers/operator.py'
            $operatorPath = Join-Path $tempRoot ($operatorRelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
            New-Item -ItemType Directory -Path (Split-Path -Parent $operatorPath) -Force | Out-Null
            [System.IO.File]::WriteAllText(
                $operatorPath,
                "def _to_operator_execution(execution, resolution, event):`n    feedback = execution.feedback_json if isinstance(execution.feedback_json, dict) else {}`n    return {`n        `"exception_reason`": _normalize_exception_reason(execution, resolution, event),`n        `"replan_required`": bool(feedback.get(`"replan_required`", False)),`n    }`n",
                (New-Object System.Text.UTF8Encoding($false))
            )

            $attemptsDir = Join-Path $tempRoot 'runtime_remote_training/tod_independent_resolution_attempts'
            New-Item -ItemType Directory -Path $attemptsDir -Force | Out-Null
            $stalePacket = [ordered]@{
                artifact_type = 'tod_packet_formation_artifact'
                status = 'packet_candidate_ready'
                packet_candidate_ready = $true
                packet = [ordered]@{
                    selected_candidate = 'stale_tasks_packet'
                    target_file = 'tmp_remote_mim/core/routers/tasks.py'
                    old_text = 'old stale tasks text'
                    new_text = 'new stale tasks text'
                }
            }
            [System.IO.File]::WriteAllText(
                (Join-Path $attemptsDir 'TOD_PACKET_FORMATION_INDEPENDENT_RECOVERY.latest.json'),
                ($stalePacket | ConvertTo-Json -Depth 8),
                (New-Object System.Text.UTF8Encoding($false))
            )
            $freshBlocker = [ordered]@{
                artifact_type = 'tod_packet_formation_artifact'
                status = 'blocked_requires_tod_synthesized_old_new'
                packet_candidate_ready = $false
                blocker = [ordered]@{
                    target_file = $operatorRelativePath
                    reason = 'TOD must synthesize exact current old_text/new_text for operator.py.'
                    required_next_action = 'Inspect operator.py and publish exact old_text/new_text.'
                }
            }
            [System.IO.File]::WriteAllText(
                (Join-Path $attemptsDir 'TOD_PACKET_FORMATION_MATERIALIZATION_RECOVERY.latest.json'),
                ($freshBlocker | ConvertTo-Json -Depth 8),
                (New-Object System.Text.UTF8Encoding($false))
            )
            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            [System.IO.File]::WriteAllText($target, '{}', (New-Object System.Text.UTF8Encoding($false)))

            $promptPath = New-LocalFallbackPromptFile -Content @"
Target File: $relativePath
Edit Mode: artifact_write
Validation Pattern: exact_patch_synthesis_drill
Run exact patch synthesis drill from the latest materialization blocker.
"@
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-EXACT-DRILL-LATEST' -ObjectiveId 'OBJ-LF' -Title 'Exact patch latest blocker drill' -Scope 'Use latest materialization blocker target.' -PromptPath $promptPath -Metadata @{ task_category = 'packet_formation' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $updated = Get-Content -Path $target -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            [string]$updated.artifact_type | Should Be 'tod_exact_patch_synthesis_drill'
            [string]$updated.target_file | Should Be $operatorRelativePath
            [string]$updated.current_anchor.text | Should Match 'exception_reason'
            @($updated.bounded_slice.slice).Count | Should BeGreaterThan 0
            [string]($updated.bounded_slice.slice -join "`n") | Should Match 'replan_required'
            [bool]$updated.credit_decision.independent_tod_resolution | Should Be $false

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            $script:LocalEngineRepoRoot = $originalRoot
            if (Test-Path -Path $tempRoot) { Remove-Item -Path $tempRoot -Recurse -Force }
        }
    }

    It 'uses live Studio conversation anchors when packet formation cannot find current old_text' {
        $patterns = Get-LocalExecutionPacketAnchorPatterns `
            -TargetFile 'tmp_remote_mim/core/routers/studio.py' `
            -CandidateName 'studio_recommendation_prioritizes_exact_old_new_packet_materialization' `
            -ValidationPattern "TOD's next meaningful implementation loop" `
            -OldText 'stale Studio recommendation text that is no longer present'

        $slice = Get-LocalExecutionBoundedSliceEvidence -RelativePath 'tmp_remote_mim/core/routers/studio.py' -Patterns $patterns

        [string]$slice.matched_pattern | Should Not Be 'file_start'
        [int]$slice.start_line | Should BeGreaterThan 100
        [string]($slice.slice -join "`n") | Should Match '_studio_conversation_mode_guard_reply|what are you working on|response_mode|recommendation_mode'
    }

    It 'forms materialization recovery packets for TOD proof directives' {
        $relativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_PACKET_FORMATION_MATERIALIZATION_RECOVERY_TEST.latest.json'
        $target = Join-Path $repoRoot ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $originalContent = if (Test-Path -Path $target) { Get-Content -Path $target -Raw } else { $null }
        $todPath = Join-Path $repoRoot 'scripts/TOD.ps1'
        $todOriginalContent = if (Test-Path -Path $todPath) { Get-Content -Path $todPath -Raw } else { $null }
        $newDirectiveBlock = @'
        'Validation Command',
        'Closure Evidence',
        'Prevention Lesson',
        'Dave Needed',
        'Required Packet Fields',
        'Inspect Target File',
        'Anchor',
'@
        $oldDirectiveBlock = @'
        'Validation Command',
        'Closure Evidence',
        'Anchor',
'@

        try {
            if ($null -ne $todOriginalContent -and $todOriginalContent.Contains($newDirectiveBlock)) {
                [System.IO.File]::WriteAllText($todPath, $todOriginalContent.Replace($newDirectiveBlock, $oldDirectiveBlock), (New-Object System.Text.UTF8Encoding($false)))
            }

            $promptPath = New-LocalFallbackPromptFile -Content @"
Target File: $relativePath
Edit Mode: artifact_write
Validation Pattern: packet_candidate_ready
Recovery Materialization Source: same_objective_recovery_not_materialized_before_dispatch
Focus: materialized bounded edit proof for TOD recovery. Include Prevention Lesson, Dave Needed, Required Packet Fields, and Inspect Target File parsing.
"@
            $scope = 'Publish packet_candidate_ready evidence for materialized bounded edit proof. Dave-needed no.'
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-MATERIALIZATION-PACKET' -ObjectiveId 'OBJ-LF' -Title 'Materialization recovery packet formation' -Scope $scope -PromptPath $promptPath -Metadata @{ task_category = 'packet_formation' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $updated = Get-Content -Path $target -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            [string]$updated.status | Should Be 'packet_candidate_ready'
            [bool]$updated.packet_candidate_ready | Should Be $true
            [string]$updated.packet.selected_candidate | Should Be 'tod_materialization_proof_directive_parser'
            [string]$updated.packet.target_file | Should Be 'scripts/TOD.ps1'
            [string]$updated.packet.validation_pattern | Should Be "'Prevention Lesson',"
            [string]$updated.packet.new_text | Should Match 'Required Packet Fields'
            [string]$updated.packet.prevention_lesson | Should Match 'bounded directive parser'

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            if ([string]::IsNullOrWhiteSpace($originalContent)) {
                if (Test-Path -Path $target) { Remove-Item -Path $target -Force }
            }
            else {
                [System.IO.File]::WriteAllText($target, $originalContent, (New-Object System.Text.UTF8Encoding($false)))
            }
            if ($null -ne $todOriginalContent) {
                [System.IO.File]::WriteAllText($todPath, $todOriginalContent, (New-Object System.Text.UTF8Encoding($false)))
            }
        }
    }

    It 'blocks consumed materialization recovery packets when the discovery-selected Studio target is already applied' {
        $relativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_PACKET_FORMATION_MATERIALIZATION_PIVOT_TEST.latest.json'
        $target = Join-Path $repoRoot ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $originalContent = if (Test-Path -Path $target) { Get-Content -Path $target -Raw } else { $null }
        $durabilityPath = Join-Path $repoRoot 'scripts/run_mim_durability_smoke_v2.py'
        $durabilityOriginalContent = if (Test-Path -Path $durabilityPath) { Get-Content -Path $durabilityPath -Raw } else { $null }
        $discoveryRelativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_DIFFERENT_TARGET_DISCOVERY_DRILL.latest.json'
        $discoveryTarget = Join-Path $repoRoot ($discoveryRelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $discoveryOriginalContent = if (Test-Path -Path $discoveryTarget) { Get-Content -Path $discoveryTarget -Raw } else { $null }

        try {
            $discoveryArtifact = [ordered]@{
                artifact_type = 'tod_different_target_discovery'
                status = 'candidate_selected'
                selected_candidate_or_none = [ordered]@{
                    target_file = 'tmp_remote_mim/core/routers/studio.py'
                    validation_command = 'python -m unittest tmp_remote_mim.tests.test_studio_training_chat'
                    expected_changed_files = @('tmp_remote_mim/core/routers/studio.py')
                }
            }
            New-Item -ItemType Directory -Path (Split-Path -Parent $discoveryTarget) -Force | Out-Null
            [System.IO.File]::WriteAllText($discoveryTarget, ($discoveryArtifact | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))

            $seededContent = @'
def no_status_report_leakage(reply):
    status_boilerplate = (
        "training is active, but outcome improvement is not proven yet",
        "training is active, but the useful question is whether it is changing behavior",
        "my current weakness is:",
        "my mode-selection score",
        "the outcome verdict is",
        "i default to status reporting",
        "not whether the scoreboard looks busy",
        "here are the current scorecard numbers",
        "mim communication:",
        "mim/tod real movement:",
        "mim operator impact:",
    )
    return True
'@
            Set-LocalFallbackTestFileText -Path $durabilityPath -Content $seededContent

            $promptPath = New-LocalFallbackPromptFile -Content @"
Target File: $relativePath
Edit Mode: artifact_write
Validation Pattern: packet_candidate_ready
Recovery Materialization Source: consumed_packet_anchor_requires_different_candidate
Focus: materialized bounded edit proof for TOD recovery. Include Prevention Lesson, Dave Needed, Required Packet Fields, and Inspect Target File parsing.
"@
            $scope = 'Publish packet_candidate_ready evidence for materialized bounded edit proof. Dave-needed no.'
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-MATERIALIZATION-PIVOT-PACKET' -ObjectiveId 'OBJ-LF' -Title 'Materialization recovery packet formation pivot' -Scope $scope -PromptPath $promptPath -Metadata @{ task_category = 'packet_formation' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $updated = Get-Content -Path $target -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            @('blocked_candidate_already_applied', 'blocked_current_code_anchor_missing') -contains [string]$updated.status | Should Be $true
            [bool]$updated.packet_candidate_ready | Should Be $false
            [string]$updated.blocker.target_file | Should Be 'tmp_remote_mim/core/routers/studio.py'
            [string]$updated.blocker.target_file | Should Not Be 'scripts/run_mim_durability_smoke_v2.py'
            [string]$updated.blocker.required_next_action | Should Match 'current-code behavior gap|old_text/new_text'
            [bool]$updated.credit_decision.independent_tod_resolution | Should Be $false

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            if ([string]::IsNullOrWhiteSpace($originalContent)) {
                if (Test-Path -Path $target) { Remove-Item -Path $target -Force }
            }
            else {
                [System.IO.File]::WriteAllText($target, $originalContent, (New-Object System.Text.UTF8Encoding($false)))
            }
            if ($null -ne $durabilityOriginalContent) {
                Set-LocalFallbackTestFileText -Path $durabilityPath -Content $durabilityOriginalContent
            }
            if ([string]::IsNullOrWhiteSpace($discoveryOriginalContent)) {
                if (Test-Path -Path $discoveryTarget) { Remove-Item -Path $discoveryTarget -Force }
            }
            else {
                [System.IO.File]::WriteAllText($discoveryTarget, $discoveryOriginalContent, (New-Object System.Text.UTF8Encoding($false)))
            }
        }
    }

    It 'uses discovery-selected target instead of durability fallback after proof directive packet is consumed' {
        $relativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_PACKET_FORMATION_DISCOVERY_TARGET_TEST.latest.json'
        $target = Join-Path $repoRoot ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $originalContent = if (Test-Path -Path $target) { Get-Content -Path $target -Raw } else { $null }
        $discoveryRelativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_DIFFERENT_TARGET_DISCOVERY_DRILL.latest.json'
        $discoveryTarget = Join-Path $repoRoot ($discoveryRelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $discoveryOriginalContent = if (Test-Path -Path $discoveryTarget) { Get-Content -Path $discoveryTarget -Raw } else { $null }

        try {
            $discoveryArtifact = [ordered]@{
                artifact_type = 'tod_different_target_discovery'
                status = 'candidate_selected'
                selected_candidate_or_none = [ordered]@{
                    target_file = 'tmp_remote_mim/core/routers/studio.py'
                    validation_command = 'python -m unittest tmp_remote_mim.tests.test_studio_training_chat'
                    expected_changed_files = @('tmp_remote_mim/core/routers/studio.py')
                }
            }
            New-Item -ItemType Directory -Path (Split-Path -Parent $discoveryTarget) -Force | Out-Null
            [System.IO.File]::WriteAllText($discoveryTarget, ($discoveryArtifact | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))

            $promptPath = New-LocalFallbackPromptFile -Content @"
Target File: $relativePath
Edit Mode: artifact_write
Validation Pattern: packet_candidate_ready
Recovery Materialization Source: consumed_packet_anchor_requires_different_candidate
Focus: materialized bounded edit proof for TOD recovery. Include Prevention Lesson, Dave Needed, Required Packet Fields, and Inspect Target File parsing.
"@
            $scope = 'Use the fresh discovery-selected target and do not fall back to scripts/run_mim_durability_smoke_v2.py.'
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-MATERIALIZATION-DISCOVERY-TARGET' -ObjectiveId 'OBJ-LF' -Title 'Materialization recovery discovery target' -Scope $scope -PromptPath $promptPath -Metadata @{ task_category = 'packet_formation' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $updated = Get-Content -Path $target -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            @('blocked_candidate_already_applied', 'blocked_current_code_anchor_missing') -contains [string]$updated.status | Should Be $true
            [bool]$updated.packet_candidate_ready | Should Be $false
            [string]$updated.blocker.target_file | Should Be 'tmp_remote_mim/core/routers/studio.py'
            [string]$updated.blocker.target_file | Should Not Be 'scripts/run_mim_durability_smoke_v2.py'
            [string]$updated.blocker.required_next_action | Should Match 'current-code behavior gap|old_text/new_text'
            [bool]$updated.credit_decision.independent_tod_resolution | Should Be $false

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            if ([string]::IsNullOrWhiteSpace($originalContent)) {
                if (Test-Path -Path $target) { Remove-Item -Path $target -Force }
            }
            else {
                [System.IO.File]::WriteAllText($target, $originalContent, (New-Object System.Text.UTF8Encoding($false)))
            }
            if ([string]::IsNullOrWhiteSpace($discoveryOriginalContent)) {
                if (Test-Path -Path $discoveryTarget) { Remove-Item -Path $discoveryTarget -Force }
            }
            else {
                [System.IO.File]::WriteAllText($discoveryTarget, $discoveryOriginalContent, (New-Object System.Text.UTF8Encoding($false)))
            }
        }
    }

    It 'materializes a Studio mode guard packet for explicit inspect targets' {
        $originalRoot = $script:LocalEngineRepoRoot
        $tempRoot = Join-Path $repoRoot ('tod/out/tests/local-fallback-studio-mode-guard-packet-' + [guid]::NewGuid().ToString('N'))
        $relativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_PACKET_FORMATION_STUDIO_MODE_GUARD_TEST.latest.json'
        $target = Join-Path $tempRoot ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $studioRelativePath = 'tmp_remote_mim/core/routers/studio.py'
        $studioPath = Join-Path $tempRoot ($studioRelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)

        try {
            $script:LocalEngineRepoRoot = $tempRoot
            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            New-Item -ItemType Directory -Path (Split-Path -Parent $studioPath) -Force | Out-Null
            [System.IO.File]::WriteAllText($target, '{}', (New-Object System.Text.UTF8Encoding($false)))
            [System.IO.File]::WriteAllText($studioPath, @'
def _studio_conversation_mode_guard_reply(prompt, page_context):
    recommendation_terms = (
        "smartest next move",
        "work should be paused",
    )
'@, (New-Object System.Text.UTF8Encoding($false)))

            $promptPath = New-LocalFallbackPromptFile -Content @"
Target File: $relativePath
Edit Mode: artifact_write
Validation Pattern: packet_candidate_ready
Inspect Target File: $studioRelativePath
Required output: publish a current-code packet candidate with exact old_text/new_text.
"@
            $scope = 'Materialize a Studio packet for the explicit inspect target.'
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-STUDIO-MODE-GUARD-PACKET' -ObjectiveId 'OBJ-LF' -Title 'Studio mode guard packet formation' -Scope $scope -PromptPath $promptPath -Metadata @{ task_category = 'packet_formation' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $updated = Get-Content -Path $target -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            [string]$updated.status | Should Be 'packet_candidate_ready'
            [bool]$updated.packet_candidate_ready | Should Be $true
            [string]$updated.packet.target_file | Should Be $studioRelativePath
            [string]$updated.packet.old_text | Should Match 'smartest next move'
            [string]$updated.packet.new_text | Should Match 'what should we work on'
            [string]$updated.packet.validation_pattern | Should Be '"what should we work on"'

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            $script:LocalEngineRepoRoot = $originalRoot
            if (Test-Path -Path $tempRoot) {
                Remove-Item -Path $tempRoot -Recurse -Force
            }
        }
    }

    It 'materializes public chat discovery packets from exact current code' {
        $originalRoot = $script:LocalEngineRepoRoot
        $tempRoot = Join-Path $repoRoot ('tod/out/tests/local-fallback-public-chat-packet-' + [guid]::NewGuid().ToString('N'))
        $relativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_PACKET_FORMATION_PUBLIC_CHAT_TEST.latest.json'
        $target = Join-Path $tempRoot ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $discoveryRelativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_DIFFERENT_TARGET_DISCOVERY_DRILL.latest.json'
        $discoveryTarget = Join-Path $tempRoot ($discoveryRelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $todPath = Join-Path $tempRoot 'scripts/TOD.ps1'
        $publicChatPath = Join-Path $tempRoot 'tmp_remote_mim/core/routers/public_chat.py'
        $publicChatOldBlock = @'
        if any(token in recent_text for token in ("day", "date", "today", "time", "thursday", "friday", "saturday")):
            return (
                f"This could mean several things, but if you mean the day/date from the prior question, in France it is {temporal['current_date']} at about {temporal['current_time']} {temporal['timezone']}. "
                "The evidence is the prior turn plus the France timezone source. If you meant laws, travel, pricing, or something else about France, that is a different path. Next action: I will use the prior-turn date context unless you choose another France topic."
            )
'@

        try {
            $script:LocalEngineRepoRoot = $tempRoot
            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            New-Item -ItemType Directory -Path (Split-Path -Parent $todPath) -Force | Out-Null
            New-Item -ItemType Directory -Path (Split-Path -Parent $publicChatPath) -Force | Out-Null
            [System.IO.File]::WriteAllText($target, '{}', (New-Object System.Text.UTF8Encoding($false)))
            [System.IO.File]::WriteAllText($todPath, "        'Prevention Lesson',`n", (New-Object System.Text.UTF8Encoding($false)))
            [System.IO.File]::WriteAllText($publicChatPath, $publicChatOldBlock, (New-Object System.Text.UTF8Encoding($false)))

            $discoveryArtifact = [ordered]@{
                artifact_type = 'tod_different_target_discovery'
                status = 'candidate_selected'
                selected_candidate_or_none = [ordered]@{
                    candidate_key = 'public_chat_context_followup_direct_answer_guard'
                    target_file = 'tmp_remote_mim/core/routers/public_chat.py'
                    validation_command = 'python -m py_compile tmp_remote_mim/core/routers/public_chat.py'
                    expected_changed_files = @('tmp_remote_mim/core/routers/public_chat.py')
                }
            }
            [System.IO.File]::WriteAllText($discoveryTarget, ($discoveryArtifact | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))

            $promptPath = New-LocalFallbackPromptFile -Content @"
Target File: $relativePath
Edit Mode: artifact_write
Validation Pattern: packet_candidate_ready
Recovery Materialization Source: consumed_packet_anchor_requires_different_candidate
Focus: materialized bounded edit proof for TOD recovery. Include Prevention Lesson, Dave Needed, Required Packet Fields, and Inspect Target File parsing.
"@
            $scope = 'Use the fresh public-chat discovery-selected target and publish exact old_text/new_text. No implementation credit.'
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-PUBLIC-CHAT-PACKET' -ObjectiveId 'OBJ-LF' -Title 'Public chat packet formation' -Scope $scope -PromptPath $promptPath -Metadata @{ task_category = 'packet_formation' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $updated = Get-Content -Path $target -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            [string]$updated.status | Should Be 'packet_candidate_ready'
            [bool]$updated.packet_candidate_ready | Should Be $true
            [string]$updated.packet.selected_candidate | Should Be 'public_chat_france_followup_prior_context_direct_answer'
            [string]$updated.packet.target_file | Should Be 'tmp_remote_mim/core/routers/public_chat.py'
            [string]$updated.packet.old_text | Should Match 'This could mean several things'
            [string]$updated.packet.new_text | Should Match 'I am carrying forward the prior date/time question'
            [string]$updated.packet.validation_command | Should Match 'public_chat.py'
            [string]$updated.packet.validation_pattern | Should Be 'I am carrying forward the prior date/time question'
            [bool]$updated.credit_decision.independent_tod_resolution | Should Be $false
            [bool]$updated.credit_decision.meaningful_tod_implementation | Should Be $false

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            $script:LocalEngineRepoRoot = $originalRoot
            if (Test-Path -Path $tempRoot) { Remove-Item -Path $tempRoot -Recurse -Force }
        }
    }

    It 'materializes interaction quality dashboard discovery packets from exact current code' {
        $originalRoot = $script:LocalEngineRepoRoot
        $tempRoot = Join-Path $repoRoot ('tod/out/tests/local-fallback-dashboard-packet-' + [guid]::NewGuid().ToString('N'))
        $relativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_PACKET_FORMATION_DASHBOARD_TEST.latest.json'
        $target = Join-Path $tempRoot ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $discoveryRelativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_DIFFERENT_TARGET_DISCOVERY_DRILL.latest.json'
        $discoveryTarget = Join-Path $tempRoot ($discoveryRelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $todPath = Join-Path $tempRoot 'scripts/TOD.ps1'
        $dashboardPath = Join-Path $tempRoot 'tmp_remote_mim/core/interaction_quality_dashboard.py'
        $dashboardOldBlock = @'
        "headline": {
            "available_artifacts": sum(1 for item in artifacts if item.get("available")),
            "best_weighted_pass_rate": max(best_weighted) if best_weighted else None,
            "total_failure_examples": len(failure_analysis.get("examples") or []),
            "internal_jargon_failure_count": sum(
                int(item.get("internal_jargon_failure_count") or 0) for item in artifacts
            ),
        },
'@

        try {
            $script:LocalEngineRepoRoot = $tempRoot
            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            New-Item -ItemType Directory -Path (Split-Path -Parent $todPath) -Force | Out-Null
            New-Item -ItemType Directory -Path (Split-Path -Parent $dashboardPath) -Force | Out-Null
            [System.IO.File]::WriteAllText($target, '{}', (New-Object System.Text.UTF8Encoding($false)))
            [System.IO.File]::WriteAllText($todPath, "        'Prevention Lesson',`n", (New-Object System.Text.UTF8Encoding($false)))
            [System.IO.File]::WriteAllText($dashboardPath, $dashboardOldBlock, (New-Object System.Text.UTF8Encoding($false)))

            $discoveryArtifact = [ordered]@{
                artifact_type = 'tod_different_target_discovery'
                status = 'candidate_selected'
                selected_candidate_or_none = [ordered]@{
                    candidate_key = 'interaction_quality_dashboard_stale_artifact_context_guard'
                    target_file = 'tmp_remote_mim/core/interaction_quality_dashboard.py'
                    validation_command = 'python -m py_compile tmp_remote_mim/core/interaction_quality_dashboard.py'
                    expected_changed_files = @('tmp_remote_mim/core/interaction_quality_dashboard.py')
                }
            }
            [System.IO.File]::WriteAllText($discoveryTarget, ($discoveryArtifact | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))

            $promptPath = New-LocalFallbackPromptFile -Content @"
Target File: $relativePath
Edit Mode: artifact_write
Validation Pattern: packet_candidate_ready
Recovery Materialization Source: consumed_packet_anchor_requires_different_candidate
Focus: materialized bounded edit proof for TOD recovery. Include Prevention Lesson, Dave Needed, Required Packet Fields, and Inspect Target File parsing.
"@
            $scope = 'Use the fresh dashboard discovery-selected target and publish exact old_text/new_text. No implementation credit.'
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-DASHBOARD-PACKET' -ObjectiveId 'OBJ-LF' -Title 'Dashboard packet formation' -Scope $scope -PromptPath $promptPath -Metadata @{ task_category = 'packet_formation' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $updated = Get-Content -Path $target -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            [string]$updated.status | Should Be 'packet_candidate_ready'
            [bool]$updated.packet_candidate_ready | Should Be $true
            [string]$updated.packet.selected_candidate | Should Be 'interaction_quality_dashboard_stale_artifact_headline_count'
            [string]$updated.packet.target_file | Should Be 'tmp_remote_mim/core/interaction_quality_dashboard.py'
            [string]$updated.packet.old_text | Should Match 'available_artifacts'
            [string]$updated.packet.new_text | Should Match 'stale_artifacts'
            [string]$updated.packet.validation_command | Should Match 'interaction_quality_dashboard.py'
            [string]$updated.packet.validation_pattern | Should Be '"stale_artifacts"'
            [bool]$updated.credit_decision.independent_tod_resolution | Should Be $false
            [bool]$updated.credit_decision.meaningful_tod_implementation | Should Be $false

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            $script:LocalEngineRepoRoot = $originalRoot
            if (Test-Path -Path $tempRoot) { Remove-Item -Path $tempRoot -Recurse -Force }
        }
    }

    It 'keeps selector preference packet recovery on TOD selector code instead of durability smoke fallback' {
        $relativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_PACKET_FORMATION_SELECTOR_PREFERENCE_RECOVERY.latest.json'
        $target = Join-Path $repoRoot ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $originalContent = if (Test-Path -Path $target) { Get-Content -Path $target -Raw } else { $null }

        try {
            $promptPath = New-LocalFallbackPromptFile -Content @"
Target File: $relativePath
Edit Mode: artifact_write
Validation Pattern: packet_candidate_ready
Behavior Delta: materialize a current-code selector preference packet so recovery backlog packet formation cannot outrank the active Studio old_text/new_text blocker.
Required output: publish one current-code packet candidate for scripts/TOD.ps1 selector preference, or publish blocked_candidate_already_applied/current_code_anchor_missing.
"@
            $scope = 'Selector preference recovery must stay on scripts/TOD.ps1 and must not pivot to the durability smoke packet.'
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-SELECTOR-PREFERENCE-PACKET' -ObjectiveId 'OBJ-LF' -Title 'Selector preference packet recovery' -Scope $scope -PromptPath $promptPath -Metadata @{ task_category = 'packet_formation' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $updated = Get-Content -Path $target -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            [bool]$updated.packet_candidate_ready | Should Be $false
            [string]$updated.blocker.target_file | Should Be 'scripts/TOD.ps1'
            [string]$updated.blocker.target_file | Should Not Be 'scripts/run_mim_durability_smoke_v2.py'
            [string]$updated.credit_decision.independent_tod_resolution | Should Be 'False'

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            if ([string]::IsNullOrWhiteSpace($originalContent)) {
                if (Test-Path -Path $target) { Remove-Item -Path $target -Force }
            }
            else {
                [System.IO.File]::WriteAllText($target, $originalContent, (New-Object System.Text.UTF8Encoding($false)))
            }
        }
    }

    It 'validates blocked packet artifacts as blockers instead of ready string matches' {
        $relativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_PACKET_FORMATION_BLOCKED_VALIDATION_TEST.latest.json'
        $target = Join-Path $repoRoot ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $originalContent = if (Test-Path -Path $target) { Get-Content -Path $target -Raw } else { $null }

        try {
            $blockedPacket = [ordered]@{
                artifact_type = 'tod_packet_formation_artifact'
                generated_at = (Get-Date).ToUniversalTime().ToString('o')
                status = 'blocked_current_code_anchor_missing'
                packet_candidate_ready = $false
                blocker = [ordered]@{
                    target_file = 'scripts/run_mim_durability_smoke_v2.py'
                    reason = 'Packet formation could not find the exact current summary block.'
                    required_next_action = 'Inspect the current target file and form a packet with exact old_text/new_text from the current code.'
                }
            }
            [System.IO.File]::WriteAllText($target, ($blockedPacket | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))

            $command = New-LocalExecutionPacketCandidateValidationCommand -TargetFile $relativePath
            $capture = Invoke-LocalShellCapture -Command $command -WorkingDirectory $repoRoot

            [int]$capture.exit_code | Should Be 0
            [string]$capture.stdout | Should Match 'Packet candidate blocked with inspected evidence'
            [string]$capture.stdout | Should Match 'Next action'
            [string]$capture.stdout | Should Not Match 'Packet candidate ready'
        }
        finally {
            if ([string]::IsNullOrWhiteSpace($originalContent)) {
                if (Test-Path -Path $target) { Remove-Item -Path $target -Force }
            }
            else {
                [System.IO.File]::WriteAllText($target, $originalContent, (New-Object System.Text.UTF8Encoding($false)))
            }
        }
    }

    It 'rejects thin blocked packet artifacts without a required next action' {
        $relativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_PACKET_FORMATION_THIN_BLOCKER_VALIDATION_TEST.latest.json'
        $target = Join-Path $repoRoot ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $originalContent = if (Test-Path -Path $target) { Get-Content -Path $target -Raw } else { $null }

        try {
            $blockedPacket = [ordered]@{
                artifact_type = 'tod_packet_formation_artifact'
                generated_at = (Get-Date).ToUniversalTime().ToString('o')
                status = 'blocked_current_code_anchor_missing'
                packet_candidate_ready = $false
                blocker = [ordered]@{
                    target_file = 'scripts/run_mim_durability_smoke_v2.py'
                    reason = 'Packet formation could not find the exact current summary block.'
                }
            }
            [System.IO.File]::WriteAllText($target, ($blockedPacket | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))

            $command = New-LocalExecutionPacketCandidateValidationCommand -TargetFile $relativePath
            $capture = Invoke-LocalShellCapture -Command $command -WorkingDirectory $repoRoot

            [int]$capture.exit_code | Should Not Be 0
            [string]$capture.stderr | Should Match 'missing required blocker evidence'
        }
        finally {
            if ([string]::IsNullOrWhiteSpace($originalContent)) {
                if (Test-Path -Path $target) { Remove-Item -Path $target -Force }
            }
            else {
                [System.IO.File]::WriteAllText($target, $originalContent, (New-Object System.Text.UTF8Encoding($false)))
            }
        }
    }

    It 'writes exact patch synthesis drill blockers without implementation credit' {
        $relativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_EXACT_PATCH_SYNTHESIS_DRILL_TEST.latest.json'
        $target = Join-Path $repoRoot ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $originalContent = if (Test-Path -Path $target) { Get-Content -Path $target -Raw } else { $null }

        try {
            $promptPath = New-LocalFallbackPromptFile -Content @"
Target File: $relativePath
Edit Mode: artifact_write
Validation Pattern: exact_patch_synthesis_drill
Produce exact bounded-edit synthesis evidence before any code execution.
"@
            $scope = 'Training drill: produce exact bounded-edit synthesis evidence before any code execution. Credit rule: this drill is not a validated TOD edit, not a meaningful implementation, and not an independent resolution.'
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-EXACT-PATCH-DRILL' -ObjectiveId 'OBJ-LF' -Title 'Exact patch synthesis drill' -Scope $scope -PromptPath $promptPath -Metadata @{ task_category = 'packet_formation' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $updated = Get-Content -Path $target -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            (@($result.files_changed) -contains $relativePath) | Should Be $true
            [string]$updated.artifact_type | Should Be 'tod_exact_patch_synthesis_drill'
            [string]$updated.status | Should Be 'blocked_with_precise_reason'
            [bool]$updated.required_outputs_filled | Should Be $true
            [bool]$updated.candidate_ready | Should Be $false
            @($updated.inspected_files).Count | Should BeGreaterThan 3
            [string]$updated.validation_pattern | Should Be 'exact_patch_synthesis_drill'
            [string]$updated.dave_needed | Should Be 'no'
            [bool]$updated.codex_patch_supplied | Should Be $false
            [bool]$updated.credit_decision.independent_tod_resolution | Should Be $false
            [bool]$updated.credit_decision.meaningful_tod_implementation | Should Be $false
            [bool]$updated.credit_decision.validated_tod_edit | Should Be $false

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            if ([string]::IsNullOrWhiteSpace($originalContent)) {
                if (Test-Path -Path $target) { Remove-Item -Path $target -Force }
            }
            else {
                [System.IO.File]::WriteAllText($target, $originalContent, (New-Object System.Text.UTF8Encoding($false)))
            }
        }
    }

    It 'forms gateway packets from multi-target handoff blocker evidence' {
        $relativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_PACKET_FORMATION_GATEWAY_SPLIT_TEST.latest.json'
        $target = Join-Path $repoRoot ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $originalContent = if (Test-Path -Path $target) { Get-Content -Path $target -Raw } else { $null }
        $gatewayRelativePath = 'tmp_remote_mim/core/routers/gateway.py'
        $gatewayPath = Join-Path $repoRoot ($gatewayRelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $gatewayOriginalContent = if (Test-Path -Path $gatewayPath) { Get-Content -Path $gatewayPath -Raw } else { $null }
        $gatewayOldBlock = @'
    expected_evidence = [
        "fresh changed_files for the target gateway/test files or blocked_with_inspection",
        "focused validation command output",
    ]
'@
        $gatewayNewBlock = @'
    expected_evidence = [
        "fresh changed_files for the selected one-file target or blocked_with_inspection naming target_file_exactly_one",
        "focused validation command output",
    ]
'@

        try {
            if (-not [string]::IsNullOrWhiteSpace($gatewayOriginalContent) -and -not $gatewayOriginalContent.Contains($gatewayOldBlock)) {
                $seededGatewayContent = if ($gatewayOriginalContent.Contains($gatewayNewBlock)) {
                    $gatewayOriginalContent.Replace($gatewayNewBlock, $gatewayOldBlock)
                }
                else {
                    $gatewayOriginalContent.TrimEnd() + "`n" + $gatewayOldBlock + "`n"
                }
                $seededGatewayContent = $seededGatewayContent.Replace('selected one-file target', 'target gateway/test files')
                [System.IO.File]::WriteAllText($gatewayPath, $seededGatewayContent, (New-Object System.Text.UTF8Encoding($false)))
            }

            $promptPath = New-LocalFallbackPromptFile -Content @"
Target File: $relativePath
Edit Mode: artifact_write
Validation Pattern: packet_candidate_ready
Previous blocker: blocked_missing_bounded_edit_mode because the handoff named both the gateway implementation file and its test file.
Required behavior: create a packet for exactly one gateway target_file after target_file_exactly_one blocked the broad MIM synced handoff.
"@
            $scope = 'Publish packet_candidate_ready evidence for the MIM synced gateway multi-target split. Dave-needed no.'
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-GATEWAY-PACKET' -ObjectiveId 'OBJ-LF' -Title 'Gateway packet formation artifact write' -Scope $scope -PromptPath $promptPath -Metadata @{ task_category = 'packet_formation' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $updated = Get-Content -Path $target -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            (@($result.files_changed) -contains $relativePath) | Should Be $true
            [string]$updated.status | Should Be 'packet_candidate_ready'
            [bool]$updated.packet_candidate_ready | Should Be $true
            [string]$updated.packet.selected_candidate | Should Be 'gateway_multi_target_split_evidence'
            [string]$updated.packet.target_file | Should Be 'tmp_remote_mim/core/routers/gateway.py'
            [string]$updated.packet.new_text | Should Match 'selected one-file target'
            [string]$updated.packet.validation_command | Should Match 'tmp_remote_mim/core/routers/gateway.py'
            [string]$updated.packet.validation_pattern | Should Be 'selected one-file target'

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            if ([string]::IsNullOrWhiteSpace($originalContent)) {
                if (Test-Path -Path $target) { Remove-Item -Path $target -Force }
            }
            else {
                [System.IO.File]::WriteAllText($target, $originalContent, (New-Object System.Text.UTF8Encoding($false)))
            }
            if ($null -ne $gatewayOriginalContent) {
                [GC]::Collect()
                [GC]::WaitForPendingFinalizers()
                Start-Sleep -Milliseconds 100
                [System.IO.File]::WriteAllText($gatewayPath, $gatewayOriginalContent, (New-Object System.Text.UTF8Encoding($false)))
            }
        }
    }

    It 'blocks packet formation when the selected target is forbidden by the prompt' {
        $relativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_PACKET_FORMATION_FORBIDDEN_GATEWAY_TEST.latest.json'
        $target = Join-Path $repoRoot ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $originalContent = if (Test-Path -Path $target) { Get-Content -Path $target -Raw } else { $null }
        $gatewayRelativePath = 'tmp_remote_mim/core/routers/gateway.py'
        $gatewayPath = Join-Path $repoRoot ($gatewayRelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $gatewayOriginalContent = if (Test-Path -Path $gatewayPath) { Get-Content -Path $gatewayPath -Raw } else { $null }
        $gatewayOldBlock = @'
    expected_evidence = [
        "fresh changed_files for the target gateway/test files or blocked_with_inspection",
        "focused validation command output",
    ]
'@
        $gatewayNewBlock = @'
    expected_evidence = [
        "fresh changed_files for the selected one-file target or blocked_with_inspection naming target_file_exactly_one",
        "focused validation command output",
    ]
'@

        try {
            if (-not [string]::IsNullOrWhiteSpace($gatewayOriginalContent) -and -not $gatewayOriginalContent.Contains($gatewayOldBlock)) {
                $seededGatewayContent = if ($gatewayOriginalContent.Contains($gatewayNewBlock)) {
                    $gatewayOriginalContent.Replace($gatewayNewBlock, $gatewayOldBlock)
                }
                else {
                    $gatewayOriginalContent.TrimEnd() + "`n" + $gatewayOldBlock + "`n"
                }
                [System.IO.File]::WriteAllText($gatewayPath, $seededGatewayContent, (New-Object System.Text.UTF8Encoding($false)))
            }

            $promptPath = New-LocalFallbackPromptFile -Content @"
Target File: $relativePath
Edit Mode: artifact_write
Validation Pattern: packet_candidate_ready
Inspect Target File: tmp_remote_mim/core/routers/gateway.py
Previous blocker: blocked_missing_bounded_edit_mode because the handoff named both the gateway implementation file and its test file.
Required behavior: create a packet for exactly one gateway target_file after target_file_exactly_one blocked the broad MIM synced handoff.
Forbidden target paths for this packet: tmp_remote_mim/core/routers/gateway.py, scripts/run_mim_durability_smoke_v2.py
"@
            $scope = 'Publish packet_candidate_ready evidence for the MIM synced gateway multi-target split. Dave-needed no.'
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-FORBIDDEN-GATEWAY-PACKET' -ObjectiveId 'OBJ-LF' -Title 'Forbidden gateway packet formation artifact write' -Scope $scope -PromptPath $promptPath -Metadata @{ task_category = 'packet_formation' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $updated = Get-Content -Path $target -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            (@($result.files_changed) -contains $relativePath) | Should Be $true
            [string]$updated.status | Should Be 'blocked_forbidden_target'
            [bool]$updated.packet_candidate_ready | Should Be $false
            [string]$updated.blocker.target_file | Should Be 'tmp_remote_mim/core/routers/gateway.py'
            [string]$updated.blocker.missing_anchor_or_field | Should Be 'allowed_target_file'
            [bool]$updated.credit_decision.independent_tod_resolution | Should Be $false

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            if ([string]::IsNullOrWhiteSpace($originalContent)) {
                if (Test-Path -Path $target) { Remove-Item -Path $target -Force }
            }
            else {
                [System.IO.File]::WriteAllText($target, $originalContent, (New-Object System.Text.UTF8Encoding($false)))
            }
            if ($null -ne $gatewayOriginalContent) {
                [GC]::Collect()
                [GC]::WaitForPendingFinalizers()
                Start-Sleep -Milliseconds 100
                [System.IO.File]::WriteAllText($gatewayPath, $gatewayOriginalContent, (New-Object System.Text.UTF8Encoding($false)))
            }
        }
    }

    It 'pivots inferred forbidden gateway packet formation to an allowed governance target' {
        $relativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_PACKET_FORMATION_FORBIDDEN_GATEWAY_PIVOT_TEST.latest.json'
        $target = Join-Path $repoRoot ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $originalContent = if (Test-Path -Path $target) { Get-Content -Path $target -Raw } else { $null }
        $improvementRelativePath = 'tmp_remote_mim/core/routers/improvement.py'
        $improvementPath = Join-Path $repoRoot ($improvementRelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $improvementOriginalContent = if (Test-Path -Path $improvementPath) { Get-Content -Path $improvementPath -Raw } else { $null }
        $improvementOldBlock = @'
    return {
        "updated": True,
        "proposal": to_improvement_proposal_out(proposal, latest_artifact=artifact),
        "artifact": to_improvement_artifact_out(artifact),
    }
'@
        $improvementNewBlock = @'
    return {
        "updated": True,
        "proposal": to_improvement_proposal_out(proposal, latest_artifact=artifact),
        "artifact": to_improvement_artifact_out(artifact),
        "review_decision_evidence": {
            "decision": "accepted",
            "journal_action": "improvement_proposal_accepted",
            "artifact_id": artifact.id,
            "reason_recorded": bool(payload.reason),
        },
    }
'@

        try {
            if (-not [string]::IsNullOrWhiteSpace($improvementOriginalContent) -and -not $improvementOriginalContent.Contains($improvementOldBlock)) {
                $seededImprovementContent = if ($improvementOriginalContent.Contains($improvementNewBlock)) {
                    $improvementOriginalContent.Replace($improvementNewBlock, $improvementOldBlock)
                }
                else {
                    $improvementOriginalContent
                }
                [System.IO.File]::WriteAllText($improvementPath, $seededImprovementContent, (New-Object System.Text.UTF8Encoding($false)))
            }

            $promptPath = New-LocalFallbackPromptFile -Content @"
Target File: $relativePath
Edit Mode: artifact_write
Validation Pattern: packet_candidate_ready
Previous blocker: blocked_missing_bounded_edit_mode because the handoff named both the gateway implementation file and its test file.
Required behavior: create a packet for exactly one gateway target_file after target_file_exactly_one blocked the broad MIM synced handoff.
Forbidden target paths for this packet: tmp_remote_mim/core/routers/gateway.py, scripts/run_mim_durability_smoke_v2.py, tmp_remote_mim/core/routers/studio.py, scripts/TOD.ps1
"@
            $scope = 'Publish packet_candidate_ready evidence for the MIM synced gateway multi-target split. Dave-needed no.'
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-FORBIDDEN-GATEWAY-PIVOT-PACKET' -ObjectiveId 'OBJ-LF' -Title 'Forbidden gateway packet formation pivot' -Scope $scope -PromptPath $promptPath -Metadata @{ task_category = 'packet_formation' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $updated = Get-Content -Path $target -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            (@($result.files_changed) -contains $relativePath) | Should Be $true
            [string]$updated.status | Should Be 'packet_candidate_ready'
            [bool]$updated.packet_candidate_ready | Should Be $true
            [string]$updated.packet.target_file | Should Be 'tmp_remote_mim/core/routers/improvement.py'
            [string]$updated.packet.selected_candidate | Should Be 'improvement_router_accept_review_decision_evidence'
            [string]$updated.packet.new_text | Should Match 'review_decision_evidence'
            [string]$updated.packet.validation_command | Should Match 'tmp_remote_mim/core/routers/improvement.py'

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            if ([string]::IsNullOrWhiteSpace($originalContent)) {
                if (Test-Path -Path $target) { Remove-Item -Path $target -Force }
            }
            else {
                [System.IO.File]::WriteAllText($target, $originalContent, (New-Object System.Text.UTF8Encoding($false)))
            }
            if ($null -ne $improvementOriginalContent) {
                [GC]::Collect()
                [GC]::WaitForPendingFinalizers()
                Start-Sleep -Milliseconds 100
                [System.IO.File]::WriteAllText($improvementPath, $improvementOriginalContent, (New-Object System.Text.UTF8Encoding($false)))
            }
        }
    }

    It 'writes Studio mode-selection packet candidates without changing the target yet' {
        $originalRoot = $script:LocalEngineRepoRoot
        $tempRoot = Join-Path $repoRoot ('tod/out/tests/local-fallback-studio-mode-' + [guid]::NewGuid().ToString('N'))
        $relativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_STUDIO_MODE_SELECTION_BOUNDED_PACKET.latest.json'
        $target = Join-Path $tempRoot ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $originalContent = if (Test-Path -Path $target) { Get-Content -Path $target -Raw } else { $null }
        $studioRelativePath = 'tmp_remote_mim/core/routers/studio.py'
        $studioPath = Join-Path $tempRoot ($studioRelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $studioOriginalContent = if (Test-Path -Path $studioPath -PathType Leaf) { Get-Content -Path $studioPath -Raw } else { $null }
        $studioOldText = 'I recommend working on MIM conversation mode selection next.'
        $studioNewText = 'I recommend working on TOD self-authored bounded edit materialization next.'

        try {
            $script:LocalEngineRepoRoot = $tempRoot
            New-Item -ItemType Directory -Path (Split-Path -Parent $studioPath) -Force | Out-Null
            if ($null -eq $studioOriginalContent) {
                [System.IO.File]::WriteAllText($studioPath, ($studioOldText + "`n"), (New-Object System.Text.UTF8Encoding($false)))
                $studioOriginalContent = $studioOldText + "`n"
            }
            if ($null -ne $studioOriginalContent -and -not $studioOriginalContent.Contains($studioOldText)) {
                $seededStudioContent = if ($studioOriginalContent.Contains($studioNewText)) {
                    $studioOriginalContent.Replace($studioNewText, $studioOldText)
                }
                else {
                    $studioOriginalContent.TrimEnd() + "`n" + $studioOldText + "`n"
                }
                [System.IO.File]::WriteAllText($studioPath, $seededStudioContent, (New-Object System.Text.UTF8Encoding($false)))
            }
            $promptPath = New-LocalFallbackPromptFile -Content @"
Target File: $relativePath
Edit Mode: artifact_write
Validation Pattern: packet_candidate_ready
Packet Source Target: tmp_remote_mim/core/routers/studio.py
Observed blocker: blocked_missing_bounded_edit_mode because TOD did not provide edit_mode plus exact current old_text_or_anchor and new_text_or_snippet.
Required behavior: inspect the Studio mode-selection target and publish packet_candidate_ready with exact current old_text/new_text, or publish a precise blocker. Do not change the Studio target in this packet-formation step.
"@
            $scope = 'Publish inspected packet candidate for Studio mode-selection bounded edit. No implementation credit. Dave-needed no.'
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-STUDIO-MODE-PACKET' -ObjectiveId 'OBJ-LF' -Title 'Studio mode packet candidate artifact write' -Scope $scope -PromptPath $promptPath -Metadata @{ task_category = 'packet_formation' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $updated = Get-Content -Path $target -Raw | ConvertFrom-Json
            $studioAfterContent = if (Test-Path -Path $studioPath -PathType Leaf) { Get-Content -Path $studioPath -Raw } else { '' }

            [string]$result.status | Should Be 'completed'
            (@($result.files_changed) -contains $relativePath) | Should Be $true
            [string]$updated.artifact_type | Should Be 'tod_packet_formation_artifact'
            [string]$updated.status | Should Be 'packet_candidate_ready'
            [bool]$updated.packet_candidate_ready | Should Be $true
            [string]$updated.target_file | Should Be 'tmp_remote_mim/core/routers/studio.py'
            [string]$updated.packet.selected_candidate | Should Be 'studio_recommendation_prioritizes_tod_materialization'
            [string]$updated.packet.target_file | Should Be 'tmp_remote_mim/core/routers/studio.py'
            [string]$updated.packet.intended_edit_mode | Should Be 'replace_text'
            [string]$updated.packet.old_text | Should Match 'MIM conversation mode selection'
            [string]$updated.packet.new_text | Should Match 'TOD self-authored bounded edit materialization'
            [string]$updated.packet.validation_pattern | Should Match 'TOD self-authored bounded edit materialization'
            [string]$updated.validation_command | Should Match '_studio_conversation_mode_reply'
            [string]$updated.packet.validation_command | Should Match 'TOD self-authored bounded edit materialization'
            [string]$updated.dave_needed | Should Be 'no'
            [bool]$updated.credit_decision.independent_tod_resolution | Should Be $false
            [bool]$updated.credit_decision.meaningful_tod_implementation | Should Be $false
            [bool]$updated.credit_decision.validated_tod_edit | Should Be $false
            [string]$studioAfterContent | Should Match ([regex]::Escape($studioOldText))

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            $script:LocalEngineRepoRoot = $originalRoot
            if ([string]::IsNullOrWhiteSpace($originalContent)) {
                if (Test-Path -Path $target) { Remove-Item -Path $target -Force }
            }
            else {
                [System.IO.File]::WriteAllText($target, $originalContent, (New-Object System.Text.UTF8Encoding($false)))
            }
            if ($null -ne $studioOriginalContent) {
                [System.IO.File]::WriteAllText($studioPath, $studioOriginalContent, (New-Object System.Text.UTF8Encoding($false)))
            }
            if (Test-Path -Path $tempRoot) { Remove-Item -Path $tempRoot -Recurse -Force }
        }
    }

    It 'requires explicit validation pattern for append_section when supplied' {
        $relativePath = ('docs/local-fallback-validation-marker-{0}.md' -f [guid]::NewGuid().ToString('N'))
        $absolutePath = Join-Path $repoRoot ($relativePath -replace '/', '\\')
        [System.IO.File]::WriteAllText($absolutePath, "# Marker validation fixture`n", (New-Object System.Text.UTF8Encoding($false)))

        $promptText = @"
Update $relativePath.
Edit Mode: append_section
Section Title: Marker Validation Section
Section Body: This body intentionally omits the required proof marker.
Validation Pattern: REQUIRED_PROOF_MARKER_123
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext -TaskId 'TSK-LF-MARKER-STRICT' -ObjectiveId 'OBJ-LF' -Title 'Require explicit marker' -Scope ("Patch $relativePath with an append_section change.") -PromptPath $promptPath -Metadata @{ task_category = 'docs_change' }

        $result = Invoke-LocalExecutionEngine -Context $context

        [string]$result.status | Should Be 'failed'
        [string]$result.reason_code | Should Be 'local_fallback_validation_failed'
        ([string](Get-Content -Path $absolutePath -Raw)) | Should Not Match 'Marker Validation Section'

        Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        Remove-Item -Path $absolutePath -Force
    }

    It 'maps simple MIM workspace filenames into the tmp_remote_mim mirror safely' {
        $mirrorPath = Join-Path $repoRoot 'tmp_remote_mim/routes.py'
        $createdMirror = $false
        if (-not (Test-Path -Path $mirrorPath -PathType Leaf)) {
            New-Item -ItemType Directory -Path (Split-Path -Parent $mirrorPath) -Force | Out-Null
            [System.IO.File]::WriteAllText($mirrorPath, "# temporary MIM routes mirror`n", (New-Object System.Text.UTF8Encoding($false)))
            $createdMirror = $true
        }

        try {
            [string](Convert-ToLocalExecutionRepoRelativePath -PathValue 'routes.py') | Should Be 'tmp_remote_mim/routes.py'
            [bool](Test-LocalExecutionSafePath -RelativePath 'routes.py') | Should Be $true

            $promptPath = New-LocalFallbackPromptFile -Content @"
Update routes.py.
Edit Mode: validation_only
Validation Pattern: workspace
"@
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-MIM-ROUTES' -ObjectiveId 'OBJ-LF' -Title 'Validate MIM routes mirror' -Scope 'Validate routes.py through the local MIM workspace mirror.' -PromptPath $promptPath -Metadata @{ task_category = 'validation'; local_fallback_target_file = 'routes.py' }
            [string]@(Get-LocalExecutionTargetFiles -Context $context)[0] | Should Be 'tmp_remote_mim/routes.py'

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        } finally {
            if ($createdMirror -and (Test-Path -Path $mirrorPath -PathType Leaf)) {
                Remove-Item -Path $mirrorPath -Force
            }
        }
    }

    It 'maps MIM app-relative core paths into the tmp_remote_mim mirror safely' {
        $mirrorPath = Join-Path $repoRoot 'tmp_remote_mim/core/routers/gateway.py'
        if (-not (Test-Path -Path $mirrorPath -PathType Leaf)) {
            throw "Expected MIM gateway mirror at $mirrorPath"
        }

        [string](Convert-ToLocalExecutionRepoRelativePath -PathValue 'core/routers/gateway.py') | Should Be 'tmp_remote_mim/core/routers/gateway.py'
        [bool](Test-LocalExecutionSafePath -RelativePath 'core/routers/gateway.py') | Should Be $true

        $promptPath = New-LocalFallbackPromptFile -Content @"
Update gateway.py.
Target File: core/routers/gateway.py
Edit Mode: validation_only
Validation Pattern: gateway
"@
        try {
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-MIM-CORE-GATEWAY' -ObjectiveId 'OBJ-LF' -Title 'Validate MIM gateway mirror path mapping' -Scope 'Validate core/routers/gateway.py through the local MIM workspace mirror.' -PromptPath $promptPath -Metadata @{ task_category = 'validation'; local_fallback_target_file = 'core/routers/gateway.py' }
            [string]@(Get-LocalExecutionTargetFiles -Context $context)[0] | Should Be 'tmp_remote_mim/core/routers/gateway.py'
        }
        finally {
            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
    }

    It 'canonicalizes MIM app-relative validation commands into the tmp_remote_mim mirror' {
        $mirrorPath = Join-Path $repoRoot 'tmp_remote_mim/core/routers/gateway.py'
        if (-not (Test-Path -Path $mirrorPath -PathType Leaf)) {
            throw "Expected MIM gateway mirror at $mirrorPath"
        }

        [string](Convert-LocalExecutionValidationCommandPaths -Command 'python -m py_compile .\core\routers\gateway.py' -TargetFile 'tmp_remote_mim/core/routers/gateway.py') | Should Be 'python -m py_compile .\tmp_remote_mim\core\routers\gateway.py'
        [string](Convert-LocalExecutionValidationCommandPaths -Command 'python -m py_compile tmp_remote_mim/core/routers/gateway.py' -TargetFile 'tmp_remote_mim/core/routers/gateway.py') | Should Be 'python -m py_compile tmp_remote_mim/core/routers/gateway.py'

        $promptPath = New-LocalFallbackPromptFile -Content @'
Target File: core/routers/gateway.py
Edit Mode: validation_only
Validation Command: python -m py_compile .\core\routers\gateway.py
'@
        try {
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-MIM-CORE-GATEWAY-VALIDATION' -ObjectiveId 'OBJ-LF' -Title 'Validate MIM gateway mirror command mapping' -Scope 'Validate core/routers/gateway.py through the local MIM workspace mirror.' -PromptPath $promptPath -Metadata @{ task_category = 'validation'; local_fallback_target_file = 'core/routers/gateway.py' }
            $result = Invoke-LocalExecutionEngine -Context $context

            [string]$result.status | Should Be 'completed'
            [bool]$result.no_change_required | Should Be $true
            @($result.validation_results | Where-Object { [string]$_.name -eq 'validation_only_no_file_change_expected' -and [bool]$_.passed }).Count | Should Be 1
        }
        finally {
            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
    }

    It 'validates the MIM ARM workspace safety calibration slice without moving hardware' {
        $mirrorPath = Join-Path $repoRoot 'tmp_remote_mim/routes.py'
        $createdMirror = $false
        if (-not (Test-Path -Path $mirrorPath -PathType Leaf)) {
            New-Item -ItemType Directory -Path (Split-Path -Parent $mirrorPath) -Force | Out-Null
            $content = @"
from flask import jsonify, request

def _workspace_servo_limit_for(servo_index):
    return {"configured": False, "min": 0, "max": 180, "source": "default"}

def _workspace_clamp_servo_angle(servo_index, requested_angle):
    limit = _workspace_servo_limit_for(servo_index)
    clamped_angle = max(int(limit["min"]), min(int(limit["max"]), int(requested_angle)))
    return clamped_angle, {"table_edge_guard": "servo_limit_clamp"}

def move_servo():
    data = request.get_json()
    servo = int(data['servo'])
    angle = int(data['angle'])
    requested_angle = angle
    angle, safety = _workspace_clamp_servo_angle(servo, requested_angle)
    dry_run = bool(data.get("dry_run") or data.get("no_motion") or data.get("validate_only"))
    if dry_run:
        update_serial_runtime("move_dry_run_validated")
        return jsonify({"status": "ok", "safety": safety}), 200
"@
            [System.IO.File]::WriteAllText($mirrorPath, $content, (New-Object System.Text.UTF8Encoding($false)))
            $createdMirror = $true
        }

        try {
            $promptPath = New-LocalFallbackPromptFile -Content @"
OBJECTIVE: MIM-ARM-WORKSPACE-SAFETY-CALIBRATION-V1
TARGET FILE: routes.py
Validate the workspace safety calibration route, servo limit clamp, dry_run no-motion path, and table edge guard.
"@
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-MIM-ARM-SAFETY' -ObjectiveId 'mim-arm-workspace-safety-calibration-v1' -Title 'MIM ARM workspace safety calibration' -Scope 'Validate workspace safety calibration for routes.py without moving hardware.' -PromptPath $promptPath -Metadata @{ task_category = 'implementation_repair'; local_fallback_target_file = 'routes.py' }

            $result = Invoke-LocalExecutionEngine -Context $context

            [string]$result.status | Should Be 'completed'
            [bool]$result.no_change_required | Should Be $true
            @($result.files_changed).Count | Should Be 0
            [string]$result.diff_summary | Should Match 'without invoking hardware'
            @($result.validation_results | Where-Object { [string]$_.name -eq 'python_compile_passed' -and [bool]$_.passed }).Count | Should Be 1

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        } finally {
            if ($createdMirror -and (Test-Path -Path $mirrorPath -PathType Leaf)) {
                Remove-Item -Path $mirrorPath -Force
            }
        }
    }

    It 'rejects blocked traversal paths' {
        $promptText = @"
Update scripts/../../danger.ps1.
Edit Mode: replace_text
Old Text: OLD_SENTINEL
New Text: NEW_SENTINEL
Validation Pattern: NEW_SENTINEL
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext -TaskId 'TSK-LF-BLOCKED' -ObjectiveId 'OBJ-LF' -Title 'Patch blocked path' -Scope 'Patch scripts/../../danger.ps1 with a bounded replace_text change.' -PromptPath $promptPath -Metadata @{ task_category = 'code_change' }

        $result = Invoke-LocalExecutionEngine -Context $context

        [string]$result.status | Should Be 'failed'
        [string]$result.reason_code | Should Be 'local_fallback_path_not_allowed'
        [string]$result.blockers[0].missing_variable | Should Be 'allowed_path'

        Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
    }

    It 'allows learned capability artifact writes inside the bounded training artifact root' {
        $relativePath = 'runtime_remote_training/learned_capabilities/TOD_BOUNDED_PACKET_FIELD_PRESERVATION_TEST.latest.json'
        $targetPath = Join-Path $repoRoot ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        if (Test-Path -Path $targetPath -PathType Leaf) {
            Remove-Item -Path $targetPath -Force
        }
        $promptText = @"
Target File: $relativePath
Edit Mode: artifact_write
New Text: {"capability_name":"Bounded Packet Field Preservation Test","validation":"safe-root write allowed"}
Validation Command: if (-not (Select-String -Path $relativePath -Pattern 'Bounded Packet Field Preservation Test' -SimpleMatch -Quiet)) { throw 'learned capability test artifact missing' }
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext -TaskId 'TSK-LF-LEARNED-CAPABILITY' -ObjectiveId 'OBJ-LF' -Title 'Freeze learned capability' -Scope 'Write a learned capability artifact under the bounded training artifact root.' -PromptPath $promptPath -Metadata @{ task_category = 'artifact_write'; local_fallback_target_file = $relativePath }

        $result = Invoke-LocalExecutionEngine -Context $context

        [string]$result.status | Should Be 'completed'
        (@($result.files_changed) -contains $relativePath) | Should Be $true
        (Test-Path -Path $targetPath -PathType Leaf) | Should Be $true

        Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        if (Test-Path -Path $targetPath -PathType Leaf) {
            Remove-Item -Path $targetPath -Force
        }
    }

    It 'publishes regression snapshot counts and failure families from read-only audit input' {
        $inputRel = ('tod/out/tests/regression-summary-{0}.json' -f [guid]::NewGuid().ToString('N'))
        $outputRel = ('runtime_remote_training/read_only_audit_artifacts/TOD_REGRESSION_AUDIT_TEST_{0}.json' -f [guid]::NewGuid().ToString('N'))
        $inputPath = Join-Path $repoRoot ($inputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $outputPath = Join-Path $repoRoot ($outputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $summary = [ordered]@{
            generated_at = '2026-07-10T01:00:00Z'
            passed_all = $false
            passed = 410
            failed = 3
            total = 413
            failed_tests = @(
                [ordered]@{ describe = 'TOD local fallback executor'; name = 'first'; message = 'failed'; classification = 'deterministic' },
                [ordered]@{ describe = 'TOD local fallback executor'; name = 'second'; message = 'failed'; classification = 'deterministic' },
                [ordered]@{ describe = 'TOD self-driving next task selection'; name = 'third'; message = 'failed'; classification = 'deterministic' }
            )
        }
        New-Item -ItemType Directory -Path (Split-Path -Parent $inputPath) -Force | Out-Null
        [System.IO.File]::WriteAllText($inputPath, ($summary | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))

        $promptText = @"
Input: $inputRel
Output artifact: $outputRel
Audit Subject: TOD operations regression snapshot.
Use the read-only audit artifact lane.
No code changes.
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext -TaskId 'TSK-LF-REGRESSION-AUDIT' -ObjectiveId 'OBJ-LF' -Title 'Regression snapshot read-only audit artifact' -Scope $promptText -PromptPath $promptPath -Metadata @{ task_category = 'report_only' }

        $result = Invoke-LocalExecutionEngine -Context $context
        $artifact = Get-Content -Path $outputPath -Raw | ConvertFrom-Json

        [string]$result.status | Should Be 'completed'
        [string]$artifact.classification | Should Be 'regression_snapshot_review_required'
        @($artifact.evidence_used[0].fields) -contains 'failed_tests' | Should Be $true
        @($artifact.findings | Where-Object { [string]$_.finding -eq 'regression_snapshot_counts' -and [string]$_.evidence -match 'passed=410; failed=3; total=413' }).Count | Should Be 1
        @($artifact.findings | Where-Object { [string]$_.finding -eq 'regression_failure_families' -and [string]$_.evidence -match 'TOD local fallback executor' }).Count | Should Be 1
        @($artifact.blockers | Where-Object { [string]$_.reason_code -eq 'regression_failures' }).Count | Should Be 1
        [bool]$artifact.no_code_changes | Should Be $true

        Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        if (Test-Path -Path $inputPath -PathType Leaf) {
            Remove-Item -Path $inputPath -Force
        }
        if (Test-Path -Path $outputPath -PathType Leaf) {
            Remove-Item -Path $outputPath -Force
        }
    }

    It 'publishes semantic source audit fields from source-anchor artifacts' {
        $inputOneRel = ('runtime_remote_training/read_only_audit_artifacts/TOD_TEST_SEMANTIC_ANCHOR_ONE_{0}.json' -f [guid]::NewGuid().ToString('N'))
        $inputTwoRel = ('runtime_remote_training/read_only_audit_artifacts/TOD_TEST_SEMANTIC_ANCHOR_TWO_{0}.json' -f [guid]::NewGuid().ToString('N'))
        $outputRel = ('runtime_remote_training/read_only_audit_artifacts/TOD_TEST_SEMANTIC_AUDIT_{0}.json' -f [guid]::NewGuid().ToString('N'))
        $inputOnePath = Join-Path $repoRoot ($inputOneRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $inputTwoPath = Join-Path $repoRoot ($inputTwoRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $outputPath = Join-Path $repoRoot ($outputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $anchorOne = [ordered]@{
            artifact_type = 'tod_source_anchor_observation'
            source_file = 'tmp_remote_mim/core/next_step_dialog_service.py'
            anchor_pattern = 'def _derive_capability_model_status('
            start_line = 1
            end_line = 20
            exact_text = @'
def _derive_capability_model_status(*, item, metadata, shared_root):
    return {
        "artifact_type": "mim_capability_model_v1",
        "capability_name": "requested capability",
        "confidence": "medium",
    }
'@
        }
        $anchorTwo = [ordered]@{
            artifact_type = 'tod_source_anchor_observation'
            source_file = 'tmp_remote_mim/core/next_step_dialog_service.py'
            anchor_pattern = 'def _collect_contract_output_fields('
            start_line = 21
            end_line = 80
            exact_text = @'
def _collect_contract_output_fields(*, item, metadata, required_fields, shared_root):
    candidate_sources = _contract_candidate_sources(item=item, metadata=metadata, shared_root=shared_root)
    for raw_field in required_fields:
        field = str(raw_field or "").strip()
        value = _first_present_source_value(candidate_sources, field)
        if value is None:
            missing_fields.append(field)

def _contract_candidate_sources(*, item, metadata, shared_root):
    capability_model_status = _derive_capability_model_status(item=item, metadata=metadata, shared_root=shared_root)
    if capability_model_status:
        candidate_sources.append(capability_model_status)
'@
        }
        New-Item -ItemType Directory -Path (Split-Path -Parent $inputOnePath) -Force | Out-Null
        [System.IO.File]::WriteAllText($inputOnePath, ($anchorOne | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))
        [System.IO.File]::WriteAllText($inputTwoPath, ($anchorTwo | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))

        $promptText = @"
Semantic read-only audit-body synthesis from source-anchor evidence.
Input: $inputOneRel
Additional Evidence: $inputTwoRel
Output: $outputRel

Required output fields: observed_blocker, suspected_root_cause, evidence_checked, evidence_missing, why_forward_motion_is_blocked, smallest_diagnostic_step, confidence, no_phrase_patch_rule=true.
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext -TaskId 'TSK-LF-SEMANTIC-SOURCE-AUDIT' -ObjectiveId 'OBJ-LF' -Title 'Semantic source audit artifact' -Scope $promptText -PromptPath $promptPath -Metadata @{ task_category = 'inspection_only' }

        $result = Invoke-LocalExecutionEngine -Context $context
        $artifact = Get-Content -Path $outputPath -Raw | ConvertFrom-Json

        [string]$result.status | Should Be 'completed'
        [string]$artifact.artifact_type | Should Be 'tod_semantic_source_audit_artifact'
        [string]$artifact.classification | Should Be 'semantic_audit_body_synthesis_from_source_anchors'
        [string]$artifact.observed_blocker | Should Not BeNullOrEmpty
        [string]$artifact.suspected_root_cause | Should Match 'contract collector'
        @($artifact.evidence_checked).Count -ge 2 | Should Be $true
        [string]$artifact.why_forward_motion_is_blocked | Should Not BeNullOrEmpty
        [string]$artifact.smallest_diagnostic_step | Should Not BeNullOrEmpty
        [bool]$artifact.no_phrase_patch_rule | Should Be $true
        [bool]$artifact.no_code_changes | Should Be $true

        Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        foreach ($path in @($inputOnePath, $inputTwoPath, $outputPath)) {
            if (Test-Path -Path $path -PathType Leaf) {
                Remove-Item -Path $path -Force
            }
        }
    }

    It 'publishes SolAir research evidence demonstration from source evidence without new text' {
        $sourceRel = 'runtime/shared/SOLAIR_POWER_CURVE_OBSERVATION.latest.json'
        $outputRel = ('runtime/shared/TOD_TEST_INDEPENDENT_UNSEEN_DEMO_{0}.json' -f [guid]::NewGuid().ToString('N'))
        $sourcePath = Join-Path $repoRoot ($sourceRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $outputPath = Join-Path $repoRoot ($outputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path -Path $sourcePath -PathType Leaf)) {
            Set-ItResult -Skipped -Because 'SolAir power curve source artifact is not present in this checkout.'
            return
        }

        $promptText = @"
OBJECTIVE: TOD-INDEPENDENT-UNSEEN-APPRENTICESHIP-DEMONSTRATION-TEST

Goal: TOD independently demonstrates borrowed artifact-body synthesis on a fresh analogous case without Codex-provided final artifact body text.

Fresh case: SolAir power-output question. Read-only source evidence is the SolAir power curve observation artifact in the runtime shared folder.

Source evidence: $sourceRel
Target File: $outputRel
Edit Mode: artifact_write
Task Category: validation_only

Required proof fields:
- objective_id
- selected_unseen_case
- source_evidence_discovered
- diagnosis
- authority_boundary
- answer_model
- validation_plan
- validation_result
- what_TOD_did_without_Codex
- what_TOD_still_cannot_do
- registry_update_recommendation

Rules:
- No source code edits.
- No hardcoded answer snippets from Codex.
- No final completion claim unless the JSON artifact exists and all required fields are populated from source evidence.
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext -TaskId 'TSK-LF-SOLAIR-UNSEEN-DEMO' -ObjectiveId 'OBJ-LF' -Title 'SolAir unseen apprenticeship demonstration' -Scope $promptText -PromptPath $promptPath -Metadata @{ task_category = 'validation_only'; local_fallback_target_file = $outputRel }

        $result = Invoke-LocalExecutionEngine -Context $context
        $artifact = Get-Content -Path $outputPath -Raw | ConvertFrom-Json

        [string]$result.status | Should Be 'completed'
        [string]$artifact.artifact_type | Should Be 'tod_independent_unseen_apprenticeship_demonstration'
        [string]$artifact.selected_unseen_case | Should Match 'SolAir'
        @($artifact.source_evidence_discovered).Count | Should Be 1
        [int]$artifact.source_evidence_discovered[0].physics_limit_rows | Should BeGreaterThan 0
        [int]$artifact.source_evidence_discovered[0].chart_rows | Should BeGreaterThan 0
        [double]$artifact.answer_model.ten_mph.physics_after_generator_efficiency_watts | Should Be 52.7
        [double]$artifact.answer_model.ten_mph.chart_one_unit_watts | Should Be 175
        [bool]$artifact.answer_model.ten_mph.source_conflict | Should Be $true
        [string]$artifact.authority_boundary.answer_rule | Should Match 'Report both lanes'
        [bool]$artifact.no_code_changes | Should Be $true

        Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        if (Test-Path -Path $outputPath -PathType Leaf) {
            Remove-Item -Path $outputPath -Force
        }
    }

    It 'completes validation_only tasks without changing the target file' {
        $promptText = @"
Inspect scripts/TOD.ps1.
Edit Mode: validation_only
Validation Pattern: function Invoke-ExecuteChatTaskRequest
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext -TaskId 'TSK-LF-VALIDATE' -ObjectiveId 'OBJ-LF' -Title 'Validate TOD task route' -Scope 'Inspect scripts/TOD.ps1 and publish validation only.' -PromptPath $promptPath -Metadata @{ task_category = 'validation'; local_fallback_target_file = 'scripts/TOD.ps1' }

        $result = Invoke-LocalExecutionEngine -Context $context

        [string]$result.status | Should Be 'completed'
        [bool]$result.no_change_required | Should Be $true
        [string]$result.diff_summary | Should Match 'Validated bounded target'
        @($result.commands_run).Count | Should Be 1

        Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
    }

    It 'blocks validation_only when failed-patch recovery requires a behavior-changing edit' {
        $promptText = @"
Target File: scripts/TOD.ps1
Recovery Mode: failed_material_patch
Required behavior: inspect the failed target file and repair the smallest behavior-changing patch.
Closure Evidence: changed target file, passing validation command, prevention lesson, and no independent-resolution credit unless TOD performs the full fix/validate/close loop.
Edit Mode: validation_only
Validation Pattern: function Invoke-ExecuteChatTaskRequest
No validation-only completion.
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext -TaskId 'TSK-LF-RECOVERY-VALIDATION-ONLY' -ObjectiveId 'OBJ-LF' -Title 'Reject validation-only recovery' -Scope 'Recover failed material patch; no validation-only completion.' -PromptPath $promptPath -Metadata @{ task_category = 'code_change'; local_fallback_target_file = 'scripts/TOD.ps1' }

        $result = Invoke-LocalExecutionEngine -Context $context

        [string]$result.status | Should Be 'failed'
        [string]$result.reason_code | Should Be 'local_fallback_validation_only_forbidden'
        [string]$result.blockers[0].missing_variable | Should Be 'behavior_changing_edit'
        @($result.files_changed).Count | Should Be 0

        Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
    }

    It 'blocks missing target files with the exact missing variable' {
        $relativePath = ('docs/local-fallback-missing-{0}.md' -f [guid]::NewGuid().ToString('N'))
        $promptText = @"
Update $relativePath.
Edit Mode: append_section
Section Title: Missing Target
Section Body: This section should not be written.
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext -TaskId 'TSK-LF-MISSING' -ObjectiveId 'OBJ-LF' -Title 'Patch missing target' -Scope ("Update $relativePath with a Missing Target section.") -PromptPath $promptPath -Metadata @{ task_category = 'docs_change' }

        $result = Invoke-LocalExecutionEngine -Context $context

        [string]$result.status | Should Be 'failed'
        [string]$result.reason_code | Should Be 'local_fallback_needs_target_or_scope'
        [string]$result.blockers[0].missing_variable | Should Be 'existing_target_file'

        Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
    }

    It 'triggers local fallback when codex only returns wrapper output' {
        $relativePath = ('docs/local-fallback-wrapper-{0}.md' -f [guid]::NewGuid().ToString('N'))
        $absolutePath = Join-Path $repoRoot ($relativePath -replace '/', '\\')
        $absoluteDir = Split-Path -Parent $absolutePath
        New-Item -ItemType Directory -Path $absoluteDir -Force | Out-Null
        [System.IO.File]::WriteAllText($absolutePath, "# Wrapper Fallback`n", (New-Object System.Text.UTF8Encoding($false)))

        $promptPath = New-LocalFallbackPromptFile -Content ("Update {0} with a short Wrapper Evidence section." -f $relativePath)
        $task = [pscustomobject]@{
            id = 'TSK-LF-WRAPPER'
            objective_id = 'OBJ-LF'
            title = 'Update wrapper fallback docs'
            scope = ("Update {0} with a short Wrapper Evidence section." -f $relativePath)
            type = 'implementation'
            task_category = 'docs_change'
        }
        $engineConfig = [pscustomobject]@{
            active = 'codex'
            fallback = 'local'
            allow_fallback = $true
            retry_policy = [pscustomobject]@{
                enabled = $false
                max_attempts_per_engine = 1
                retry_on_status = @('failed', 'error', 'not_implemented')
            }
        }

        $invocation = Invoke-ExecutionEngine -Task $task -TaskId 'TSK-LF-WRAPPER' -PackagePath $promptPath -EngineConfig $engineConfig

        [bool]$invocation.fallback_applied | Should Be $true
        [string]$invocation.active_engine | Should Be 'local'
        [string]$invocation.result.status | Should Be 'completed'
        [string]@($invocation.result.files_changed)[0] | Should Be $relativePath
        [string]$invocation.result.command_output | Should Match 'Wrapper Evidence'
        [string]$invocation.result.diff_summary | Should Match $relativePath
        [string]@($invocation.result.commands_run)[0] | Should Match 'Select-String'
        @($invocation.result.validation_results).Count | Should BeGreaterThan 0
        [string]$invocation.result.confidence | Should Be 'medium-high'
        [string]$invocation.result.rollback_hint | Should Match 'Copy-Item'
        ([string](Get-Content -Path $absolutePath -Raw)) | Should Match '## Wrapper Evidence'

        Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        Remove-Item -Path $absolutePath -Force
    }

    It 'patches prompt token extraction with bounded local fallback evidence' {
        $originalRoot = $script:LocalEngineRepoRoot
        $tempRoot = Join-Path $repoRoot ('tod/out/tests/local-fallback-token-' + [guid]::NewGuid().ToString('N'))
        $targetRelativePath = 'tmp_remote_mim/core/routers/tod_ui.py'
        $targetAbsolutePath = Join-Path $tempRoot ($targetRelativePath -replace '/', '\\')
        $targetDir = Split-Path -Parent $targetAbsolutePath
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        Copy-Item -Path (Join-Path $repoRoot ($targetRelativePath -replace '/', '\\')) -Destination $targetAbsolutePath -Force

        $currentSnippet = @'
def _extract_identifier_token(value: str) -> str:
    text = str(value or "").strip()
    if not text:
        return ""
    match = re.search(r"[A-Za-z0-9][A-Za-z0-9._:-]*", text)
    if not match:
        return _compact_text(text, 220)
    return match.group(0).rstrip(".,;:)]}>")


def _extract_labeled_prompt_value(message: str, label: str) -> str:
    text = str(message or "")
    lines = text.splitlines()
    normalized_label = re.sub(r"[_\s-]+", r"[_\\s-]+", str(label or "").strip())
    label_pattern = re.compile(rf"^\s*(?:(?:[-*]|#{{1,6}})\s*)?{normalized_label}\s*:\s*(.*)$", re.IGNORECASE)
    next_label_pattern = re.compile(r"^\s*(?:(?:[-*]|#{1,6})\s*)?[A-Z][A-Za-z0-9_]*(?:[ _-][A-Z][A-Za-z0-9_]*)*\s*:\s*(.*)$")
    identifier_labels = {"initiative_id", "objective_id", "task_id", "request_id"}
    normalized_label_key = re.sub(r"[^a-z0-9]+", "_", str(label or "").strip().lower()).strip("_")
    for index, line in enumerate(lines):
        match = label_pattern.match(line)
        if not match:
            continue
        if normalized_label_key in identifier_labels:
            return _extract_identifier_token(match.group(1))
        collected = [str(match.group(1) or "").strip()]
        for next_line in lines[index + 1 :]:
            if next_label_pattern.match(next_line):
                break
            stripped = str(next_line or "").strip()
            if stripped:
                collected.append(stripped)
        return _compact_text(" ".join(item for item in collected if item), 220)
    pattern = re.compile(
        rf"(?:^|\b){normalized_label}\s*:\s*(.+?)(?=\s+(?:(?:[-*]|#{{1,6}})\s*)?[A-Z][A-Za-z0-9_]*(?:[ _-][A-Z][A-Za-z0-9_]*)*\s*:|$)",
        re.IGNORECASE | re.DOTALL,
    )
    match = pattern.search(text)
    if not match:
        return ""
    value = match.group(1)
    if normalized_label_key in identifier_labels:
        return _extract_identifier_token(value)
    return _compact_text(value, 220)
'@
        $oldSnippet = @'
def _extract_labeled_prompt_value(message: str, label: str) -> str:
    text = str(message or "")
    lines = text.splitlines()
    normalized_label = re.sub(r"[_\s-]+", r"[_\\s-]+", str(label or "").strip())
    label_pattern = re.compile(rf"^\s*(?:[-*]\s*)?{normalized_label}\s*:\s*(.*)$", re.IGNORECASE)
    next_label_pattern = re.compile(r"^\s*(?:[-*]\s*)?[A-Z][A-Za-z0-9_]*(?:[ _-][A-Z][A-Za-z0-9_]*)*\s*:\s*(.*)$")
    for index, line in enumerate(lines):
        match = label_pattern.match(line)
        if not match:
            continue
        collected = [str(match.group(1) or "").strip()]
        for next_line in lines[index + 1 :]:
            if next_label_pattern.match(next_line):
                break
            stripped = str(next_line or "").strip()
            if stripped:
                collected.append(stripped)
        return _compact_text(" ".join(item for item in collected if item), 220)
    pattern = re.compile(
        rf"(?:^|\b){normalized_label}\s*:\s*(.+?)(?=\s+(?:[-*]\s*)?[A-Z][A-Za-z0-9_]*(?:[ _-][A-Z][A-Za-z0-9_]*)*\s*:|$)",
        re.IGNORECASE | re.DOTALL,
    )
    match = pattern.search(text)
    if not match:
        return ""
    return _compact_text(match.group(1), 220)
'@
        $seededContent = [string](Get-Content -Path $targetAbsolutePath -Raw)
        [System.IO.File]::WriteAllText($targetAbsolutePath, $seededContent.Replace($currentSnippet, $oldSnippet), (New-Object System.Text.UTF8Encoding($false)))

        try {
            $script:LocalEngineRepoRoot = $tempRoot
            $promptPath = New-LocalFallbackPromptFile -Content '# TOD Task Execution Package`n- Objective Description: Patch token extraction so only the identifier value is captured.'
            $context = New-LocalFallbackContext -TaskId 'objective-2913-task-7144' -ObjectiveId 'objective-2913' -Title 'Patch token extraction' -Scope 'Patch token extraction so only the identifier value is captured.' -PromptPath $promptPath -Metadata @{
                task_category = 'code_change'
                local_fallback_target_file = $targetRelativePath
                local_fallback_validation_command = "Get-Content -Path '.\\tmp_remote_mim\\core\\routers\\tod_ui.py' | Select-String -SimpleMatch 'def _extract_identifier_token(value: str) -> str:','return _extract_identifier_token(match.group(1))'"
            }

            $result = Invoke-LocalExecutionEngine -Context $context

            [string]$result.status | Should Be 'completed'
            $nonEmptyFiles = @($result.files_changed | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
            if (@($nonEmptyFiles).Count -gt 0) {
                [string]@($nonEmptyFiles)[0] | Should Be $targetRelativePath
            }
            [string]$result.diff_summary | Should Match 'identifier values'
            @($result.validation_results | Where-Object { [string]$_.name -eq 'focused_validation_exit_zero' -and [bool]$_.passed }).Count | Should Be 1
            ([string](Get-Content -Path $targetAbsolutePath -Raw)) | Should Match 'def _extract_identifier_token'
            ([string](Get-Content -Path $targetAbsolutePath -Raw)) | Should Match 'return _extract_identifier_token\(match.group\(1\)\)'

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            $script:LocalEngineRepoRoot = $originalRoot
            if (Test-Path -Path $tempRoot) {
                Remove-Item -Path $tempRoot -Recurse -Force
            }
        }
    }

    It 'ignores an empty local_fallback_target_file and still infers the bounded docs target from prompt text' {
        $relativePath = ('docs/local-fallback-empty-target-{0}.md' -f [guid]::NewGuid().ToString('N'))
        $absolutePath = Join-Path $repoRoot ($relativePath -replace '/', '\\')
        $absoluteDir = Split-Path -Parent $absolutePath
        New-Item -ItemType Directory -Path $absoluteDir -Force | Out-Null
        [System.IO.File]::WriteAllText($absolutePath, "# Empty Target Override`n", (New-Object System.Text.UTF8Encoding($false)))

        $promptPath = New-LocalFallbackPromptFile -Content ("Update {0} with a short Async Dispatch section." -f $relativePath)
        $context = New-LocalFallbackContext -TaskId 'TSK-LF-EMPTY-TARGET' -ObjectiveId 'OBJ-LF' -Title 'Ignore empty target override' -Scope ("Update {0} with a short Async Dispatch section." -f $relativePath) -PromptPath $promptPath -Metadata @{
            task_category = 'docs_change'
            local_fallback_target_file = ''
        }

        try {
            $result = Invoke-LocalExecutionEngine -Context $context

            [string]$result.status | Should Be 'completed'
            (@($result.files_changed | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) -contains $relativePath) | Should Be $true
            ([string](Get-Content -Path $absolutePath -Raw)) | Should Match 'Async Dispatch'
        }
        finally {
            if (Test-Path -Path $promptPath) {
                Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
            }
            if (Test-Path -Path $absolutePath) {
                Remove-Item -Path $absolutePath -Force
            }
        }
    }

    It 'publishes diff summary, commands, validation results, confidence, and rollback hints in shared artifacts' {
        function global:Get-TodExecutionSharedRoots {
            return ,(Join-Path $repoRoot ('tod/out/tests/local-fallback-artifacts-' + [guid]::NewGuid().ToString('N')))
        }

        function global:Write-TodExecutionSharedJson {
            param(
                [Parameter(Mandatory = $true)][string]$Path,
                [Parameter(Mandatory = $true)]$Payload
            )

            $dir = Split-Path -Parent $Path
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            ($Payload | ConvertTo-Json -Depth 20) | Set-Content -Path $Path -Encoding utf8
        }

        function global:Publish-RemoteTodExecutionArtifacts {
            param([string[]]$LocalArtifactPaths)
            return [pscustomobject]@{ attempted = $false; published = $false; reason = 'stubbed' }
        }

        $relativePath = ('docs/local-fallback-publish-{0}.md' -f [guid]::NewGuid().ToString('N'))
        $absolutePath = Join-Path $repoRoot ($relativePath -replace '/', '\\')
        $absoluteDir = Split-Path -Parent $absolutePath
        New-Item -ItemType Directory -Path $absoluteDir -Force | Out-Null
        [System.IO.File]::WriteAllText($absolutePath, "# Publish Test`n", (New-Object System.Text.UTF8Encoding($false)))

        $promptPath = New-LocalFallbackPromptFile -Content ("Update {0} with a short Published Evidence section." -f $relativePath)
        $context = New-LocalFallbackContext -TaskId 'TSK-LF-PUBLISH' -ObjectiveId 'OBJ-LF' -Title 'Publish fallback evidence' -Scope ("Update {0} with a short Published Evidence section." -f $relativePath) -PromptPath $promptPath -Metadata @{ task_category = 'docs_change' }
        $result = Invoke-LocalExecutionEngine -Context $context
        $task = [pscustomobject]@{
            id = 'TSK-LF-PUBLISH'
            objective_id = 'OBJ-LF'
            title = 'Publish fallback evidence'
            scope = ("Update {0} with a short Published Evidence section." -f $relativePath)
            type = 'implementation'
            task_category = 'docs_change'
        }

        $published = Publish-LocalExecutionArtifacts -Task $task -Objective $null -ResultPayload $result -ReviewDecision 'pass' -ExecutionId ([string]$result.execution_id) -PackagePath $promptPath -ExecutionReadiness ([pscustomobject]@{ status = 'valid' })

        [string]$published.execution_result.execution_evidence.diff_summary | Should Match $relativePath
        [string]@($published.execution_result.execution_evidence.commands_run)[0] | Should Match 'Select-String'
        @($published.execution_result.execution_evidence.validation_results).Count | Should BeGreaterThan 0
        [string]$published.execution_result.execution_evidence.confidence | Should Be 'medium-high'
        [string]$published.execution_result.execution_evidence.rollback_hint | Should Match 'Copy-Item'

        Remove-Item function:\Get-TodExecutionSharedRoots -ErrorAction SilentlyContinue
        Remove-Item function:\Write-TodExecutionSharedJson -ErrorAction SilentlyContinue
        Remove-Item function:\Publish-RemoteTodExecutionArtifacts -ErrorAction SilentlyContinue
        Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        Remove-Item -Path $absolutePath -Force
    }
}
Describe 'TOD local ledger coverage handler' {
    BeforeAll {
        Import-ScriptFunction -ScriptPath $executionEngineScript -Name 'Get-ExecutionEngineInterfaceSpec'
        Import-ScriptFunction -ScriptPath $executionEngineScript -Name 'New-EngineTaskContext'
        Import-ScriptFunction -ScriptPath $executionEngineScript -Name 'New-EngineExecutionResult'
        Import-ScriptFunction -ScriptPath $executionEngineScript -Name 'Complete-EngineExecutionResult'
        Import-ScriptFunction -ScriptPath $executionEngineScript -Name 'Test-EngineContract'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Get-UtcNow'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Get-NormalizedObjectiveToken'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Get-TaskRoutingText'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Get-TaskRoutingFileHints'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Resolve-TaskCategory'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Convert-EngineResultToNormalizedEnvelope'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Normalize-EngineResultPayload'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Test-EngineResultPrecheck'
        Import-ScriptFunction -ScriptPath $todScript -Name 'New-ExecutionEngineBlockedResult'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Get-LocalExecutionValidationChecks'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Get-LocalExecutionCommandCapture'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Get-LocalExecutionRollbackState'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Resolve-LocalExecutionTaskClass'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Test-LocalExecutionPatchRequired'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Get-LocalExecutionNoOpAssessment'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Test-TodWrapperOnlyChangedPath'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Get-TodMaterialImplementationProofAssessment'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Publish-LocalExecutionArtifacts'
        Import-ScriptFunctionWithLiteralRoot -ScriptPath $todScript -Name 'Invoke-ExecutionEngine' -LiteralRoot (Join-Path $repoRoot 'scripts')

        . $localEngineScript
    }

    It 'Test-LocalExecutionLedgerCoverageTask matches a message-ledger coverage report objective' {
        $promptPath = New-LocalFallbackPromptFile -Content 'Measure Phase A observe-only message-ledger coverage across TOD/MIM communication paths.'
        $context = New-LocalFallbackContext `
            -TaskId 'TSK-LEDGER-COVERAGE' `
            -ObjectiveId 'TOD-MESSAGE-LEDGER-COVERAGE-REPORT' `
            -Title 'Measure Phase A observe-only message-ledger coverage' `
            -Scope 'Perform a non-mutating ledger coverage measurement and write the Phase A coverage report.' `
            -PromptPath $promptPath
        Test-LocalExecutionLedgerCoverageTask -Context $context | Should Be $true
        Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
    }

    It 'Test-LocalExecutionLedgerCoverageTask does not match an unrelated code_change task' {
        $promptPath = New-LocalFallbackPromptFile -Content 'Update scripts/TOD.ps1 to fix the boundary check.'
        $context = New-LocalFallbackContext `
            -TaskId 'TSK-UNRELATED' `
            -ObjectiveId 'OBJ-CODE-CHANGE' `
            -Title 'Fix boundary check in TOD.ps1' `
            -Scope 'Apply bounded patch to scripts/TOD.ps1.' `
            -PromptPath $promptPath `
            -Metadata @{ task_category = 'code_change' }
        Test-LocalExecutionLedgerCoverageTask -Context $context | Should Be $false
        Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
    }

    It 'Invoke-LocalExecutionEngine executes ledger coverage and writes coverage report' {
        $promptPath = New-LocalFallbackPromptFile -Content 'Measure Phase A observe-only message-ledger coverage across TOD/MIM communication paths.'
        $context = New-LocalFallbackContext `
            -TaskId 'TSK-LEDGER-COVERAGE' `
            -ObjectiveId 'TOD-MESSAGE-LEDGER-COVERAGE-REPORT' `
            -Title 'Measure Phase A observe-only message-ledger coverage' `
            -Scope 'Perform a non-mutating ledger coverage measurement and write the Phase A coverage report.' `
            -PromptPath $promptPath

        $result = Invoke-LocalExecutionEngine -Context $context

        [string]$result.status | Should Be 'completed'
        @($result.files_changed).Count | Should BeGreaterThan 0
        [string]@($result.files_changed)[0] | Should Match 'TOD_MIM_LEDGER_PHASE_A_COVERAGE'
        [string]$result.summary | Should Match 'coverage'
        @($result.failures).Count | Should Be 0
        [bool]$result.needs_escalation | Should Be $false

        $coverageFile = Join-Path $repoRoot 'runtime\shared\TOD_MIM_LEDGER_PHASE_A_COVERAGE.latest.json'
        Test-Path $coverageFile | Should Be $true
        $parsed = Get-Content $coverageFile -Raw | ConvertFrom-Json
        $parsed.observe_only | Should Be $true
        $parsed.coverage_percent | Should BeGreaterThan 0

        Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
    }
}
