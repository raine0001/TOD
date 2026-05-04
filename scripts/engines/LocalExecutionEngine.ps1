Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. "$PSScriptRoot/ExecutionEngine.ps1"

$script:LocalEngineRepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

function Get-LocalExecutionModeSectionLines {
    return @(
        "## TOD Local Execution Mode",
        "",
        "TOD can execute bounded local objectives directly when `execution_engine.active` is set to `local` and the task scope stays inside the declared file boundaries.",
        "",
        "In local execution mode, TOD is responsible for:",
        "- inspecting the repo and identifying the bounded target file",
        "- applying the scoped change with rollback metadata and backup coverage",
        "- validating the result and recording execution evidence",
        "- publishing changed files, validation outcomes, and the next action without routing through Codex"
    )
}

function Get-LocalExecutionPromptText {
    param([Parameter(Mandatory = $true)]$Context)

    $promptPath = [string]$Context.prompt_path
    if ([string]::IsNullOrWhiteSpace($promptPath) -or -not (Test-Path -Path $promptPath)) {
        return ""
    }

    return [string](Get-Content -Path $promptPath -Raw)
}

function Test-LocalExecutionReadmeDryRunTask {
    param([Parameter(Mandatory = $true)]$Context)

    $promptText = Get-LocalExecutionPromptText -Context $Context
    $combined = @(
        [string]$Context.title,
        [string]$Context.scope,
        $promptText
    ) -join "`n"

    $normalized = $combined.ToLowerInvariant()
    return ($normalized -match 'readme\.md') -and ($normalized -match 'tod local execution mode')
}

function Test-LocalExecutionConfigBootstrapTask {
    param([Parameter(Mandatory = $true)]$Context)

    $promptText = Get-LocalExecutionPromptText -Context $Context
    $combined = @(
        [string]$Context.title,
        [string]$Context.scope,
        $promptText
    ) -join "`n"

    $normalized = $combined.ToLowerInvariant()
    $mentionsConfig = ($normalized -match 'tod-config\.json') -or ($normalized -match 'execution_engine\.active') -or ($normalized -match 'readiness_policy\.block_actions')
    $mentionsLocal = ($normalized -match 'local execution') -or ($normalized -match 'active.?=.*?local') -or ($normalized -match 'set .*local')
    return $mentionsConfig -and $mentionsLocal
}

function Invoke-LocalShellCapture {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory
    )

    $stdoutPath = [System.IO.Path]::GetTempFileName()
    $stderrPath = [System.IO.Path]::GetTempFileName()
    $started = Get-Date
    try {
        $process = Start-Process -FilePath "powershell.exe" -ArgumentList @("-NoProfile", "-Command", $Command) -WorkingDirectory $WorkingDirectory -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -Wait -PassThru -WindowStyle Hidden
        $completed = Get-Date
        [pscustomobject]@{
            command = $Command
            working_directory = $WorkingDirectory
            stdout = [string](Get-Content -Path $stdoutPath -Raw)
            stderr = [string](Get-Content -Path $stderrPath -Raw)
            exit_code = [int]$process.ExitCode
            duration_ms = [int][math]::Round(($completed - $started).TotalMilliseconds)
            started_at = $started.ToUniversalTime().ToString("o")
            completed_at = $completed.ToUniversalTime().ToString("o")
        }
    }
    finally {
        Remove-Item -Path $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue
    }
}

function Write-Utf8NoBomFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Set-StrictTextReplacement {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][string]$OldText,
        [Parameter(Mandatory = $true)][string]$NewText,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $normalizedOldText = $OldText -replace "`r`n", "`n"
    $candidateOldTexts = @(
        $OldText,
        $normalizedOldText,
        ($normalizedOldText -replace "`n", "`r`n")
    ) | Select-Object -Unique

    $matchedOldText = $null
    foreach ($candidate in $candidateOldTexts) {
        if ($Content.Contains($candidate)) {
            $matchedOldText = $candidate
            break
        }
    }

    $replacementText = if ($null -ne $matchedOldText -and $matchedOldText.Contains("`r`n")) {
        ($NewText -replace "`r`n", "`n") -replace "`n", "`r`n"
    }
    else {
        $NewText -replace "`r`n", "`n"
    }

    if ($null -eq $matchedOldText) {
        if ($Content.Contains($replacementText)) {
            return $Content
        }

        throw "LocalExecutionEngine could not find the expected $Label snippet to replace."
    }

    return $Content.Replace($matchedOldText, $replacementText)
}

function Test-LocalExecutionExecutionLoopContractTask {
    param([Parameter(Mandatory = $true)]$Context)

    $promptText = Get-LocalExecutionPromptText -Context $Context
    $combined = @(
        [string]$Context.title,
        [string]$Context.scope,
        $promptText
    ) -join "`n"

    $normalized = $combined.ToLowerInvariant()
    $mentionsContract = $normalized -match 'execution loop contract'
    $mentionsImplementation = $normalized -match 'implement|build|phase.?1|bounded'
    return $mentionsContract -and $mentionsImplementation
}

function Set-ReadmeSectionContent {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string[]]$SectionLines
    )

    $newline = if ($Content.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = @([regex]::Split($Content, "`r?`n"))
    if ($lines.Count -eq 0) {
        $lines = @("")
    }

    $heading = "## TOD Local Execution Mode"
    $startIndex = -1
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ([string]::Equals([string]$lines[$index], $heading, [System.StringComparison]::Ordinal)) {
            $startIndex = $index
            break
        }
    }

    if ($startIndex -ge 0) {
        $endIndex = $lines.Count
        for ($index = $startIndex + 1; $index -lt $lines.Count; $index++) {
            if ([string]$lines[$index] -match '^##\s+') {
                if ([string]::Equals([string]$lines[$index], $heading, [System.StringComparison]::Ordinal)) {
                    continue
                }
                $endIndex = $index
                break
            }
        }
        $before = if ($startIndex -gt 0) { @($lines[0..($startIndex - 1)]) } else { @() }
        $after = if ($endIndex -lt $lines.Count) { @($lines[$endIndex..($lines.Count - 1)]) } else { @() }
        $merged = @($before + $SectionLines + @("") + $after)
        return (($merged -join $newline).TrimEnd() + $newline)
    }

    $insertIndex = -1
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ([string]$lines[$index] -match '^##\s+') {
            $insertIndex = $index
            break
        }
    }

    if ($insertIndex -lt 0) {
        $insertIndex = $lines.Count
    }

    $before = if ($insertIndex -gt 0) { @($lines[0..($insertIndex - 1)]) } else { @() }
    $after = if ($insertIndex -lt $lines.Count) { @($lines[$insertIndex..($lines.Count - 1)]) } else { @() }
    $merged = @($before)
    if ($merged.Count -gt 0 -and [string]::IsNullOrWhiteSpace([string]$merged[-1]) -eq $false) {
        $merged += ""
    }
    $merged += $SectionLines
    $merged += ""
    $merged += $after
    return (($merged -join $newline).TrimEnd() + $newline)
}

function Invoke-LocalExecutionReadmeDryRun {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)]$Spec
    )

    $readmePath = Join-Path $script:LocalEngineRepoRoot "README.md"
    if (-not (Test-Path -Path $readmePath)) {
        throw "README.md was not found at $readmePath"
    }

    $backupRoot = Join-Path $script:LocalEngineRepoRoot "tod/out/local-engine-backups"
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
    $backupPath = Join-Path $backupRoot ("README.md.{0}.bak" -f $timestamp)

    $originalContent = [string](Get-Content -Path $readmePath -Raw)
    Copy-Item -Path $readmePath -Destination $backupPath -Force

    $sectionLines = Get-LocalExecutionModeSectionLines
    $updatedContent = Set-ReadmeSectionContent -Content $originalContent -SectionLines $sectionLines
    $changeApplied = $updatedContent -ne $originalContent
    Set-Content -Path $readmePath -Value $updatedContent -Encoding UTF8

    $validationCommand = "Get-Content -Path '.\\README.md' | Select-String -SimpleMatch '## TOD Local Execution Mode','execution_engine.active','rollback metadata'"
    $commandCapture = Invoke-LocalShellCapture -Command $validationCommand -WorkingDirectory $script:LocalEngineRepoRoot
    $validatedContent = [string](Get-Content -Path $readmePath -Raw)

    $validationChecks = @(
        [pscustomobject]@{ name = 'readme_exists'; passed = (Test-Path -Path $readmePath) },
        [pscustomobject]@{ name = 'section_present'; passed = ($validatedContent -match '(?m)^## TOD Local Execution Mode\s*$') },
        [pscustomobject]@{ name = 'section_occurs_once'; passed = (@([regex]::Matches($validatedContent, '(?m)^## TOD Local Execution Mode\s*$')).Count -eq 1) },
        [pscustomobject]@{ name = 'section_mentions_local_engine'; passed = ($validatedContent -match 'execution_engine\.active') },
        [pscustomobject]@{ name = 'section_mentions_rollback'; passed = ($validatedContent -match 'rollback metadata') },
        [pscustomobject]@{ name = 'validation_command_exit_zero'; passed = ([int]$commandCapture.exit_code -eq 0) }
    )

    $passed = -not (@($validationChecks | Where-Object { -not [bool]$_.passed }).Count)
    $rollbackState = [pscustomobject]@{
        available = $true
        backup_path = $backupPath
        target_path = $readmePath
        restore_command = "Copy-Item -Path '$backupPath' -Destination '$readmePath' -Force"
    }

    if (-not $passed) {
        Copy-Item -Path $backupPath -Destination $readmePath -Force
        $result.summary = "LocalExecutionEngine attempted the README dry run but rolled the change back after validation failed."
        $result.tests_run = @($validationChecks | ForEach-Object { [string]$_.name })
        $result.test_results = @($validationChecks | ForEach-Object { if ([bool]$_.passed) { 'pass' } else { 'fail' } })
        $result.failures = @('README dry-run validation failed and the affected file was restored from backup.')
        $result.recommendations = @(
            'Inspect the validation evidence and narrow the README update scope.',
            'Retry the dry run once the validation criteria are explicit.'
        )
        $result.needs_escalation = $true
        $result.structured_findings = @(
            [pscustomobject]@{ type = 'rollback'; rollback = $rollbackState },
            [pscustomobject]@{ type = 'validation'; checks = $validationChecks },
            [pscustomobject]@{ type = 'command'; capture = $commandCapture }
        )
        $result.raw_output = [pscustomobject]@{
            engine = $Spec
            task_context = $Context
            action = 'readme_dry_run_rolled_back'
            target_file = $readmePath
            backup_path = $backupPath
            changed = $changeApplied
            validation_checks = $validationChecks
            command_capture = $commandCapture
            generated_at = (Get-Date).ToUniversalTime().ToString('o')
        }
        return (Complete-EngineExecutionResult -Result $result -Status 'failed')
    }

    $result.summary = "LocalExecutionEngine completed the dry-run objective by updating README.md with the TOD Local Execution Mode section and validating the change locally."
    $result.files_changed = if ($changeApplied) { @('README.md') } else { @() }
    $result.tests_run = @($validationChecks | ForEach-Object { [string]$_.name })
    $result.test_results = @($validationChecks | ForEach-Object { if ([bool]$_.passed) { 'pass' } else { 'fail' } })
    $result.failures = @()
    $result.recommendations = @(
        'Publish the dry-run evidence through TOD result artifacts and operator surfaces.',
        'Extend the local engine from README dry runs to broader bounded repo changes.'
    )
    $result.structured_findings = @(
        [pscustomobject]@{
            type = 'result_contract'
            understood_task = 'Update README.md with a TOD Local Execution Mode section through the local engine.'
            action_taken = 'Patched README.md, captured rollback metadata, and validated the section content.'
            changed_files = @($result.files_changed)
            evidence = @('README.md updated', 'validation command captured', 'backup created')
            validation_result = 'passed'
            remaining_blocker = ''
            next_action = 'Publish the dry-run evidence and continue to the next bounded local executor slice.'
            confidence = 'medium-high'
        },
        [pscustomobject]@{ type = 'command'; capture = $commandCapture },
        [pscustomobject]@{ type = 'rollback'; rollback = $rollbackState },
        [pscustomobject]@{ type = 'validation'; checks = $validationChecks }
    )
    $result.raw_output = [pscustomobject]@{
        engine = $Spec
        task_context = $Context
        action = 'readme_dry_run_completed'
        target_file = $readmePath
        changed = $changeApplied
        files_changed = @($result.files_changed)
        rollback = $rollbackState
        validation_checks = $validationChecks
        command_capture = $commandCapture
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
    }
    return (Complete-EngineExecutionResult -Result $result -Status 'completed')
}

function Invoke-LocalExecutionConfigBootstrap {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)]$Spec
    )

    $configPath = Join-Path $script:LocalEngineRepoRoot "tod/config/tod-config.json"
    if (-not (Test-Path -Path $configPath)) {
        throw "tod-config.json was not found at $configPath"
    }

    $backupRoot = Join-Path $script:LocalEngineRepoRoot "tod/out/local-engine-backups"
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
    $backupPath = Join-Path $backupRoot ("tod-config.json.{0}.bak" -f $timestamp)

    $originalContent = [string](Get-Content -Path $configPath -Raw)
    Copy-Item -Path $configPath -Destination $backupPath -Force

    $config = $originalContent | ConvertFrom-Json
    $config.mode = 'local'
    $config.execution_engine.active = 'local'
    $config.execution_engine.fallback = 'local'
    $config.execution_engine.routing_policy.enabled = $false
    $config.execution_engine.readiness_policy.block_actions = @()

    $updatedContent = ($config | ConvertTo-Json -Depth 64)
    $changeApplied = $updatedContent -ne $originalContent
    Set-Content -Path $configPath -Value $updatedContent -Encoding UTF8

    $validationCommand = "`$cfg = Get-Content -Path '.\tod\config\tod-config.json' -Raw | ConvertFrom-Json; if (`$cfg.mode -eq 'local' -and `$cfg.execution_engine.active -eq 'local' -and `$cfg.execution_engine.fallback -eq 'local' -and -not [bool]`$cfg.execution_engine.routing_policy.enabled -and -not (@(`$cfg.execution_engine.readiness_policy.block_actions) -contains 'run-task')) { 'validated'; exit 0 } throw 'tod-config local bootstrap validation failed'"
    $commandCapture = Invoke-LocalShellCapture -Command $validationCommand -WorkingDirectory $script:LocalEngineRepoRoot
    $validatedConfig = (Get-Content -Path $configPath -Raw | ConvertFrom-Json)

    $validationChecks = @(
        [pscustomobject]@{ name = 'config_exists'; passed = (Test-Path -Path $configPath) },
        [pscustomobject]@{ name = 'mode_local'; passed = ([string]$validatedConfig.mode -eq 'local') },
        [pscustomobject]@{ name = 'active_engine_local'; passed = ([string]$validatedConfig.execution_engine.active -eq 'local') },
        [pscustomobject]@{ name = 'fallback_engine_local'; passed = ([string]$validatedConfig.execution_engine.fallback -eq 'local') },
        [pscustomobject]@{ name = 'routing_disabled'; passed = (-not [bool]$validatedConfig.execution_engine.routing_policy.enabled) },
        [pscustomobject]@{ name = 'run_task_unblocked'; passed = (-not (@($validatedConfig.execution_engine.readiness_policy.block_actions) -contains 'run-task')) },
        [pscustomobject]@{ name = 'validation_command_exit_zero'; passed = ([int]$commandCapture.exit_code -eq 0) }
    )

    $passed = -not (@($validationChecks | Where-Object { -not [bool]$_.passed }).Count)
    $rollbackState = [pscustomobject]@{
        available = $true
        backup_path = $backupPath
        target_path = $configPath
        restore_command = "Copy-Item -Path '$backupPath' -Destination '$configPath' -Force"
    }

    if (-not $passed) {
        Copy-Item -Path $backupPath -Destination $configPath -Force
        $result.summary = 'LocalExecutionEngine attempted the TOD config bootstrap but rolled the change back after validation failed.'
        $result.tests_run = @($validationChecks | ForEach-Object { [string]$_.name })
        $result.test_results = @($validationChecks | ForEach-Object { if ([bool]$_.passed) { 'pass' } else { 'fail' } })
        $result.failures = @('TOD config bootstrap validation failed and the affected file was restored from backup.')
        $result.recommendations = @(
            'Inspect the config bootstrap evidence and keep the local-engine activation slice narrow.',
            'Retry once the expected execution-engine defaults are explicit.'
        )
        $result.needs_escalation = $true
        $result.structured_findings = @(
            [pscustomobject]@{ type = 'rollback'; rollback = $rollbackState },
            [pscustomobject]@{ type = 'validation'; checks = $validationChecks },
            [pscustomobject]@{ type = 'command'; capture = $commandCapture }
        )
        $result.raw_output = [pscustomobject]@{
            engine = $Spec
            task_context = $Context
            action = 'config_bootstrap_rolled_back'
            target_file = $configPath
            backup_path = $backupPath
            changed = $changeApplied
            validation_checks = $validationChecks
            command_capture = $commandCapture
            generated_at = (Get-Date).ToUniversalTime().ToString('o')
        }
        return (Complete-EngineExecutionResult -Result $result -Status 'failed')
    }

    $result.summary = 'LocalExecutionEngine completed the TOD config bootstrap by switching the default execution lane to local mode and removing readiness blocking for run-task.'
    $result.files_changed = if ($changeApplied) { @('tod/config/tod-config.json') } else { @() }
    $result.tests_run = @($validationChecks | ForEach-Object { [string]$_.name })
    $result.test_results = @($validationChecks | ForEach-Object { if ([bool]$_.passed) { 'pass' } else { 'fail' } })
    $result.failures = @()
    $result.recommendations = @(
        'Run the next TOD task on the default config to confirm the local lane is live end to end.',
        'Extend the local engine with the next bounded repo-edit capability after the bootstrap path is stable.'
    )
    $result.structured_findings = @(
        [pscustomobject]@{
            type = 'result_contract'
            understood_task = 'Switch the default TOD execution lane to local mode through the local engine.'
            action_taken = 'Updated tod-config.json, disabled routing override, and removed readiness blocking for run-task.'
            changed_files = @($result.files_changed)
            evidence = @('tod-config.json updated', 'validation command captured', 'backup created')
            validation_result = 'passed'
            remaining_blocker = ''
            next_action = 'Run a normal TOD task on the default config and watch the live execution lane for progress.'
            confidence = 'medium-high'
        },
        [pscustomobject]@{ type = 'command'; capture = $commandCapture },
        [pscustomobject]@{ type = 'rollback'; rollback = $rollbackState },
        [pscustomobject]@{ type = 'validation'; checks = $validationChecks }
    )
    $result.raw_output = [pscustomobject]@{
        engine = $Spec
        task_context = $Context
        action = 'config_bootstrap_completed'
        target_file = $configPath
        changed = $changeApplied
        files_changed = @($result.files_changed)
        rollback = $rollbackState
        validation_checks = $validationChecks
        command_capture = $commandCapture
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
    }
    return (Complete-EngineExecutionResult -Result $result -Status 'completed')
}

function Invoke-LocalExecutionExecutionLoopContract {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)]$Spec
    )

    $contractPath = Join-Path $script:LocalEngineRepoRoot "tmp_remote_mim/core/tod_execution_loop.py"
    $testPath = Join-Path $script:LocalEngineRepoRoot "tmp_remote_mim/tests/integration/test_tod_ui_console.py"
    foreach ($path in @($contractPath, $testPath)) {
        if (-not (Test-Path -Path $path)) {
            throw "Execution-loop contract surface was not found at $path"
        }
    }

    $backupRoot = Join-Path $script:LocalEngineRepoRoot "tod/out/local-engine-backups"
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
    $contractBackupPath = Join-Path $backupRoot ("tod_execution_loop.py.{0}.bak" -f $timestamp)
    $testBackupPath = Join-Path $backupRoot ("test_tod_ui_console.py.{0}.bak" -f $timestamp)

    Copy-Item -Path $contractPath -Destination $contractBackupPath -Force
    Copy-Item -Path $testPath -Destination $testBackupPath -Force

    $originalContractContent = [string](Get-Content -Path $contractPath -Raw)
    $originalTestContent = [string](Get-Content -Path $testPath -Raw)

    $contractOld = @'
    bounded_step = {
        "step_id": "step-1-inspect-repo-slice",
        "title": "Inspect repo for smallest execution-loop slice",
        "status": "planned",
        "summary": "Inspect the current repo surfaces and identify the smallest implementation slice for the TOD execution loop contract.",
        "expected_outputs": [
            "task intake",
            "bounded step planner",
            "command runner",
            "patch writer",
            "validator",
            "result publisher",
        ],
    }
'@
    $contractNew = @'
    inspection_step = {
        "step_id": "step-1-inspect-repo-slice",
        "title": "Inspect repo for smallest execution-loop slice",
        "status": "planned",
        "summary": "Inspect the current repo surfaces and identify the smallest implementation slice for the TOD execution loop contract.",
        "expected_outputs": [
            "task intake",
            "bounded step planner",
            "command runner",
            "patch writer",
            "validator",
            "result publisher",
        ],
    }
    implementation_step = {
        "step_id": "step-2-prepare-bounded-patch",
        "title": "Prepare first bounded execution-loop patch",
        "status": "planned",
        "summary": "Prepare the first bounded patch for the inspected execution-loop surfaces and carry it through focused validation.",
        "expected_outputs": [
            "target file edits",
            "focused unittest command",
            "updated execution evidence",
        ],
    }
    planned_steps = [inspection_step, implementation_step]
'@
    $contractPlannerOld = @'
        "bounded_step_planner": {
            "status": "ready",
            "active_step": bounded_step,
            "next_validation": next_validation,
        },
'@
    $contractPlannerNew = @'
        "bounded_step_planner": {
            "status": "ready",
            "active_step": inspection_step,
            "planned_steps": planned_steps,
            "next_step_id": implementation_step["step_id"],
            "next_validation": next_validation,
        },
'@
    $testOld = @'
        self.assertEqual((execution_contract.get("bounded_step_planner") or {}).get("status"), "completed")
        self.assertEqual((((execution_contract.get("bounded_step_planner") or {}).get("active_step") or {}).get("step_id")), "step-1-inspect-repo-slice")
        self.assertEqual((execution_contract.get("command_runner") or {}).get("status"), "completed")
'@
    $testNew = @'
        self.assertEqual((execution_contract.get("bounded_step_planner") or {}).get("status"), "completed")
        self.assertEqual((((execution_contract.get("bounded_step_planner") or {}).get("active_step") or {}).get("step_id")), "step-1-inspect-repo-slice")
        planned_steps = (execution_contract.get("bounded_step_planner") or {}).get("planned_steps") or []
        self.assertEqual(len(planned_steps), 2)
        self.assertEqual((planned_steps[1] or {}).get("step_id"), "step-2-prepare-bounded-patch")
        self.assertEqual((execution_contract.get("bounded_step_planner") or {}).get("next_step_id"), "step-2-prepare-bounded-patch")
        self.assertEqual((execution_contract.get("command_runner") or {}).get("status"), "completed")
'@

    $contractAlreadyPatched =
        ($originalContractContent -match 'planned_steps = \[inspection_step, implementation_step\]') -and
        ($originalContractContent -match '"next_step_id": implementation_step\["step_id"\]') -and
        ($originalContractContent -match '"active_step": inspection_step')
    $testAlreadyPatched =
        ($originalTestContent -match 'step-2-prepare-bounded-patch') -and
        ($originalTestContent -match 'next_step_id')

    $updatedContractContent = if ($contractAlreadyPatched) {
        $originalContractContent
    }
    else {
        $contractContent = Set-StrictTextReplacement -Content $originalContractContent -OldText $contractOld -NewText $contractNew -Label 'execution-loop contract bounded step'
        Set-StrictTextReplacement -Content $contractContent -OldText $contractPlannerOld -NewText $contractPlannerNew -Label 'execution-loop contract planner'
    }

    $updatedTestContent = if ($testAlreadyPatched) {
        $originalTestContent
    }
    else {
        Set-StrictTextReplacement -Content $originalTestContent -OldText $testOld -NewText $testNew -Label 'execution-loop contract integration assertions'
    }

    $contractChanged = $updatedContractContent -ne $originalContractContent
    $testChanged = $updatedTestContent -ne $originalTestContent

    Write-Utf8NoBomFile -Path $contractPath -Content $updatedContractContent
    Write-Utf8NoBomFile -Path $testPath -Content $updatedTestContent

    $validationCommand = "& '.\.venv\Scripts\python.exe' -m unittest tmp_remote_mim.tests.integration.test_tod_ui_console.TodUiConsoleTest.test_publish_local_execution_ack_supports_deployed_runtime_layout"
    $commandCapture = Invoke-LocalShellCapture -Command $validationCommand -WorkingDirectory $script:LocalEngineRepoRoot
    $validatedContractContent = [string](Get-Content -Path $contractPath -Raw)
    $validatedTestContent = [string](Get-Content -Path $testPath -Raw)

    $validationChecks = @(
        [pscustomobject]@{ name = 'contract_file_exists'; passed = (Test-Path -Path $contractPath) },
        [pscustomobject]@{ name = 'planned_steps_added'; passed = ($validatedContractContent -match 'planned_steps = \[inspection_step, implementation_step\]') },
        [pscustomobject]@{ name = 'next_step_id_added'; passed = ($validatedContractContent -match '"next_step_id": implementation_step\["step_id"\]') },
        [pscustomobject]@{ name = 'integration_assertions_added'; passed = ($validatedTestContent -match 'step-2-prepare-bounded-patch') },
        [pscustomobject]@{ name = 'validation_command_exit_zero'; passed = ([int]$commandCapture.exit_code -eq 0) }
    )

    $passed = -not (@($validationChecks | Where-Object { -not [bool]$_.passed }).Count)
    $rollbackState = [pscustomobject]@{
        available = $true
        backup_paths = @($contractBackupPath, $testBackupPath)
        target_paths = @($contractPath, $testPath)
        restore_command = "Copy-Item -Path '$contractBackupPath' -Destination '$contractPath' -Force; Copy-Item -Path '$testBackupPath' -Destination '$testPath' -Force"
    }

    if (-not $passed) {
        Copy-Item -Path $contractBackupPath -Destination $contractPath -Force
        Copy-Item -Path $testBackupPath -Destination $testPath -Force
        $result.summary = 'LocalExecutionEngine attempted the execution-loop contract phase-1 slice but rolled the changes back after validation failed.'
        $result.tests_run = @($validationChecks | ForEach-Object { [string]$_.name })
        $result.test_results = @($validationChecks | ForEach-Object { if ([bool]$_.passed) { 'pass' } else { 'fail' } })
        $result.failures = @('Execution-loop contract validation failed and the affected Python files were restored from backup.')
        $result.recommendations = @(
            'Inspect the unittest output and keep the execution-loop phase-1 patch bounded to the contract artifact and its owning test.',
            'Retry once the contract and focused validation stay aligned.'
        )
        $result.needs_escalation = $true
        $result.structured_findings = @(
            [pscustomobject]@{ type = 'rollback'; rollback = $rollbackState },
            [pscustomobject]@{ type = 'validation'; checks = $validationChecks },
            [pscustomobject]@{ type = 'command'; capture = $commandCapture }
        )
        $result.raw_output = [pscustomobject]@{
            engine = $Spec
            task_context = $Context
            action = 'execution_loop_contract_rolled_back'
            target_files = @($contractPath, $testPath)
            changed = ($contractChanged -or $testChanged)
            validation_checks = $validationChecks
            command_capture = $commandCapture
            generated_at = (Get-Date).ToUniversalTime().ToString('o')
        }
        return (Complete-EngineExecutionResult -Result $result -Status 'failed')
    }

    $result.summary = 'LocalExecutionEngine completed the phase-1 execution-loop contract slice by adding the next bounded implementation step metadata and validating the contract through the focused TOD UI integration test.'
    $result.files_changed = @()
    if ($contractChanged) { $result.files_changed += 'tmp_remote_mim/core/tod_execution_loop.py' }
    if ($testChanged) { $result.files_changed += 'tmp_remote_mim/tests/integration/test_tod_ui_console.py' }
    $result.tests_run = @($validationChecks | ForEach-Object { [string]$_.name })
    $result.test_results = @($validationChecks | ForEach-Object { if ([bool]$_.passed) { 'pass' } else { 'fail' } })
    $result.failures = @()
    $result.recommendations = @(
        'Use the new next-step metadata to drive the next bounded execution-loop patch instead of stopping at inspection.',
        'Keep subsequent local-engine additions tied to one focused unittest per bounded slice.'
    )
    $result.structured_findings = @(
        [pscustomobject]@{
            type = 'result_contract'
            understood_task = 'Carry the execution-loop contract past pure inspection by implementing the next bounded phase-1 step in repo code and validating it.'
            action_taken = 'Patched the execution-loop contract artifact to publish the next bounded implementation step and extended the owning TOD UI integration assertions.'
            changed_files = @($result.files_changed)
            evidence = @('execution-loop contract updated', 'focused unittest passed', 'backups created')
            validation_result = 'passed'
            remaining_blocker = ''
            next_action = 'Apply the next bounded execution-loop patch slice and rerun the same focused validation path.'
            confidence = 'medium-high'
        },
        [pscustomobject]@{ type = 'command'; capture = $commandCapture },
        [pscustomobject]@{ type = 'rollback'; rollback = $rollbackState },
        [pscustomobject]@{ type = 'validation'; checks = $validationChecks }
    )
    $result.raw_output = [pscustomobject]@{
        engine = $Spec
        task_context = $Context
        action = 'execution_loop_contract_completed'
        target_files = @($contractPath, $testPath)
        changed = ($contractChanged -or $testChanged)
        files_changed = @($result.files_changed)
        rollback = $rollbackState
        validation_checks = $validationChecks
        command_capture = $commandCapture
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
    }
    return (Complete-EngineExecutionResult -Result $result -Status 'completed')
}

function Get-LocalExecutionEngineSpec {
    [pscustomobject]@{
        name = "local"
        version = "0.4-execution-loop-phase1"
        lifecycle = @("prepare", "execute", "finalize")
        supports = @(
            "structured_result_output",
            "engine_metadata",
            "bounded_file_update",
            "rollback_metadata",
            "command_capture",
            "json_config_update",
            "python_source_patch",
            "focused_python_unittest"
        )
        mode = "bounded_local_executor"
    }
}

function Invoke-LocalExecutionEngine {
    param(
        [Parameter(Mandatory = $true)]$Context
    )

    $spec = Get-LocalExecutionEngineSpec
    $result = New-EngineExecutionResult -EngineName $spec.name -EngineVersion $spec.version -TaskId ([string]$Context.task_id)
    $result.execution_id = "LOCAL-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 10).ToUpperInvariant())
    if (Test-LocalExecutionExecutionLoopContractTask -Context $Context) {
        $result = Invoke-LocalExecutionExecutionLoopContract -Context $Context -Result $result -Spec $spec
    }
    elseif (Test-LocalExecutionConfigBootstrapTask -Context $Context) {
        $result = Invoke-LocalExecutionConfigBootstrap -Context $Context -Result $result -Spec $spec
    }
    elseif (Test-LocalExecutionReadmeDryRunTask -Context $Context) {
        $result = Invoke-LocalExecutionReadmeDryRun -Context $Context -Result $result -Spec $spec
    }
    else {
        $result.summary = "LocalExecutionEngine is implemented for bounded execution-loop, README, and TOD config bootstrap objectives, but this task did not match a supported scope."
        $result.tests_run = @("local-engine task scope match")
        $result.test_results = @("not-supported")
        $result.failures = @("Task did not match the current bounded local engine capability.")
        $result.recommendations = @(
            "Package a task that explicitly targets the execution loop contract, README.md with the 'TOD Local Execution Mode' section, or tod-config.json local-engine activation.",
            "Extend LocalExecutionEngine with the next bounded action capability before retrying broader tasks."
        )
        $result.needs_escalation = $true
        $result.raw_output = [pscustomobject]@{
            engine = $spec
            task_context = [pscustomobject]@{
                task_id = [string]$Context.task_id
                objective_id = [string]$Context.objective_id
                title = [string]$Context.title
                scope = [string]$Context.scope
                prompt_path = [string]$Context.prompt_path
            }
            message = "bounded_local_scope_not_matched"
            generated_at = (Get-Date).ToUniversalTime().ToString("o")
        }
        $result = Complete-EngineExecutionResult -Result $result -Status "not_implemented"
    }

    $validation = Test-EngineContract -Context $Context -Result $result
    if (-not [bool]$validation.is_valid) {
        throw "LocalExecutionEngine output failed interface validation."
    }

    return $result
}

function Convert-LocalEngineResultToTodResult {
    param(
        [Parameter(Mandatory = $true)]$EngineResult
    )

    [pscustomobject]@{
        task_id = [string]$EngineResult.task_id
        summary = [string]$EngineResult.summary
        files_changed = @($EngineResult.files_changed)
        tests_run = @($EngineResult.tests_run)
        test_results = @($EngineResult.test_results)
        failures = @($EngineResult.failures)
        recommendations = @($EngineResult.recommendations)
        structured_findings = @($EngineResult.structured_findings)
        needs_escalation = [bool]$EngineResult.needs_escalation
        engine = [pscustomobject]@{
            name = [string]$EngineResult.engine_name
            version = [string]$EngineResult.engine_version
            execution_id = [string]$EngineResult.execution_id
            status = [string]$EngineResult.status
        }
    }
}
