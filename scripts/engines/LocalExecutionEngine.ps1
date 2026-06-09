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

function Get-LocalExecutionCombinedText {
    param([Parameter(Mandatory = $true)]$Context)

    return (@(
            [string]$Context.title,
            [string]$Context.scope,
            (Get-LocalExecutionPromptText -Context $Context)
        ) -join "`n")
}

function Get-LocalExecutionTaskCategory {
    param([Parameter(Mandatory = $true)]$Context)

    if ($Context.PSObject.Properties['metadata'] -and $Context.metadata) {
        if ($Context.metadata.ContainsKey('task_category') -and -not [string]::IsNullOrWhiteSpace([string]$Context.metadata.task_category)) {
            return ([string]$Context.metadata.task_category).Trim().ToLowerInvariant()
        }
        if ($Context.metadata.ContainsKey('task_type') -and -not [string]::IsNullOrWhiteSpace([string]$Context.metadata.task_type)) {
            return ([string]$Context.metadata.task_type).Trim().ToLowerInvariant()
        }
    }

    return ''
}

function Get-LocalExecutionSafeRoots {
    return @(
        'README.md',
        'docs/',
        'scripts/',
        'tests/',
        'runtime/shared/',
        'tmp_remote_mim/',
        'tmp_remote_mim/core/',
        'tmp_remote_mim/tests/',
        'tod/config/',
        'tod/out/tests/'
    )
}

function Convert-ToLocalExecutionRepoRelativePath {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    $normalized = ([string]$PathValue).Trim() -replace '[\\/]+', '/'
    $normalized = $normalized.TrimStart('.')
    $normalized = $normalized.TrimStart('/')
    if ($normalized -notmatch '/' -and $normalized -match '^[A-Za-z0-9_.-]+\.(?:py|html|js|json|css)$') {
        $mirrorCandidate = Join-Path $script:LocalEngineRepoRoot ('tmp_remote_mim/{0}' -f $normalized)
        if (Test-Path -Path $mirrorCandidate -PathType Leaf) {
            return ('tmp_remote_mim/{0}' -f $normalized)
        }
    }
    return $normalized
}

function Test-LocalExecutionSafePath {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    $normalized = Convert-ToLocalExecutionRepoRelativePath -PathValue $RelativePath
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return $false
    }
    if ($normalized -match '^[A-Za-z]:/' -or $normalized.StartsWith('/') -or $normalized -match '(^|/)\.\.(/|$)') {
        return $false
    }

    foreach ($root in Get-LocalExecutionSafeRoots) {
        $safeRoot = Convert-ToLocalExecutionRepoRelativePath -PathValue $root
        if ($safeRoot -eq 'README.md' -and [string]::Equals($normalized, 'README.md', [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
        if ($safeRoot.EndsWith('/') -and $normalized.StartsWith($safeRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $false
}

function Get-LocalExecutionTargetFiles {
    param([Parameter(Mandatory = $true)]$Context)

    $paths = New-Object System.Collections.Generic.List[string]
    if ($Context.PSObject.Properties['metadata'] -and $Context.metadata) {
        if ($Context.metadata.ContainsKey('local_fallback_target_file')) {
            $rawValue = [string]$Context.metadata.local_fallback_target_file
            if (-not [string]::IsNullOrWhiteSpace($rawValue)) {
                $value = Convert-ToLocalExecutionRepoRelativePath -PathValue $rawValue
                if (-not [string]::IsNullOrWhiteSpace($value) -and -not $paths.Contains($value)) {
                    $paths.Add($value)
                }
            }
        }
        if ($Context.metadata.ContainsKey('local_fallback_target_files') -and $null -ne $Context.metadata.local_fallback_target_files) {
            foreach ($candidate in @($Context.metadata.local_fallback_target_files)) {
                $value = Convert-ToLocalExecutionRepoRelativePath -PathValue ([string]$candidate)
                if (-not [string]::IsNullOrWhiteSpace($value) -and -not $paths.Contains($value)) {
                    $paths.Add($value)
                }
            }
        }
    }
    foreach ($candidate in @($Context.allowed_files)) {
        $value = Convert-ToLocalExecutionRepoRelativePath -PathValue ([string]$candidate)
        if (-not [string]::IsNullOrWhiteSpace($value) -and -not $paths.Contains($value)) {
            $paths.Add($value)
        }
    }
    if ($paths.Count -gt 0) {
        return @($paths.ToArray())
    }

    $combined = Get-LocalExecutionCombinedText -Context $Context
    $matches = [regex]::Matches($combined, '(?im)(?<![A-Za-z0-9_./-])(README\.md|docs/[A-Za-z0-9_./-]+\.(?:md|txt)|scripts/[A-Za-z0-9_./-]+\.(?:ps1|psm1|py|json|md|txt)|tests/[A-Za-z0-9_./-]+\.(?:ps1|py|md|txt)|tmp_remote_mim/[A-Za-z0-9_./-]+\.(?:py|html|js|json|css|md|txt)|tod/config/[A-Za-z0-9_./-]+\.json|tod/out/tests/[A-Za-z0-9_./-]+\.txt)(?=$|[\s''""`,:;\.\!\?\)\]])')
    $paths = New-Object System.Collections.Generic.List[string]
    foreach ($match in $matches) {
        $value = Convert-ToLocalExecutionRepoRelativePath -PathValue ([string]$match.Groups[1].Value)
        if (-not [string]::IsNullOrWhiteSpace($value) -and -not $paths.Contains($value)) {
            $paths.Add($value)
        }
    }
    return @($paths.ToArray())
}

function Test-LocalExecutionGenericRisk {
    param([Parameter(Mandatory = $true)]$Context)

    $normalized = (Get-LocalExecutionCombinedText -Context $Context).ToLowerInvariant()
    return ($normalized -match 'credential|secret|password|private key|certificate|firewall|production deploy|prod deploy|public exposure|open network|reboot host|shutdown host|human safety|operator approval')
}

function Test-LocalExecutionLedgerCoverageTask {
    param([Parameter(Mandatory = $true)]$Context)

    $normalized = (Get-LocalExecutionCombinedText -Context $Context).ToLowerInvariant()
    $mentionsLedger = $normalized -match 'ledger'
    $mentionsCoverage = $normalized -match 'coverage|phase.?a|measure|observe.?only'
    return ($mentionsLedger -and $mentionsCoverage)
}

function Test-LocalExecutionMimArmWorkspaceSafetyTask {
    param([Parameter(Mandatory = $true)]$Context)

    $normalized = (Get-LocalExecutionCombinedText -Context $Context).ToLowerInvariant()
    if ($normalized -notmatch 'mim-arm-workspace-safety-calibration|workspace safety calibration|servo limit|table edge|dry_run|dry-run|no_motion') {
        return $false
    }

    $targets = @(Get-LocalExecutionTargetFiles -Context $Context)
    return (@($targets | Where-Object { [string]$_ -eq 'tmp_remote_mim/routes.py' }).Count -eq 1)
}

function Test-LocalExecutionUserAppPrototypeArtifactTask {
    param([Parameter(Mandatory = $true)]$Context)

    $normalized = (Get-LocalExecutionCombinedText -Context $Context).ToLowerInvariant()
    if ($normalized -notmatch 'user app|app build|workbench|prototype artifact|app foundation') {
        return $false
    }
    if ($normalized -notmatch 'prototype|artifact|foundation') {
        return $false
    }

    $targets = @(Get-LocalExecutionTargetFiles -Context $Context)
    return (@($targets | Where-Object { ([string]$_).ToLowerInvariant().StartsWith('runtime/shared/user_app_builds/') -and ([string]$_).ToLowerInvariant().EndsWith('.json') }).Count -eq 1)
}

function Test-LocalExecutionUserAppPublishedPreviewTask {
    param([Parameter(Mandatory = $true)]$Context)

    $normalized = (Get-LocalExecutionCombinedText -Context $Context).ToLowerInvariant()
    if ($normalized -notmatch 'publish|published preview|preview package|package manifest|workbench presentation') {
        return $false
    }

    $targets = @(Get-LocalExecutionTargetFiles -Context $Context)
    return (@($targets | Where-Object {
                $value = ([string]$_).ToLowerInvariant()
                $value.StartsWith('runtime/shared/user_app_published/') -and $value.EndsWith('/package.manifest.json')
            }).Count -eq 1)
}

function Get-LocalExecutionUserAppIntakePath {
    param([Parameter(Mandatory = $true)]$Context)

    if ($Context.PSObject.Properties['metadata'] -and $Context.metadata) {
        foreach ($key in @('intake_path', 'source_intake', 'app_intake_path')) {
            if ($Context.metadata.ContainsKey($key) -and -not [string]::IsNullOrWhiteSpace([string]$Context.metadata[$key])) {
                return (Convert-ToLocalExecutionRepoRelativePath -PathValue ([string]$Context.metadata[$key]))
            }
        }
    }

    $combined = Get-LocalExecutionCombinedText -Context $Context
    $match = [regex]::Match($combined, '(?im)(runtime/shared/[A-Za-z0-9_./-]+INTAKE[A-Za-z0-9_./-]*\.json|runtime_remote_training/[A-Za-z0-9_./-]+INTAKE[A-Za-z0-9_./-]*\.json)')
    if ($match.Success) {
        return (Convert-ToLocalExecutionRepoRelativePath -PathValue ([string]$match.Groups[1].Value))
    }

    $targets = @(Get-LocalExecutionTargetFiles -Context $Context)
    $target = [string](@($targets | Where-Object { ([string]$_).ToLowerInvariant().StartsWith('runtime/shared/user_app_builds/') -and ([string]$_).ToLowerInvariant().EndsWith('.json') })[0])
    $leaf = [System.IO.Path]::GetFileName($target)
    $prefix = ($leaf -replace '_PROTOTYPE\.latest\.json$', '')
    if (-not [string]::IsNullOrWhiteSpace($prefix)) {
        foreach ($candidate in @(
            ('runtime/shared/{0}_INTAKE_V1.latest.json' -f $prefix),
            ('runtime_remote_training/{0}_INTAKE_V1.latest.json' -f $prefix)
        )) {
            $absoluteCandidate = Join-Path $script:LocalEngineRepoRoot ($candidate -replace '/', [System.IO.Path]::DirectorySeparatorChar)
            if (Test-Path -Path $absoluteCandidate -PathType Leaf) {
                return $candidate
            }
        }
    }

    return ''
}

function Get-LocalExecutionUserAppPrototypePathForPublish {
    param([Parameter(Mandatory = $true)]$Context)

    if ($Context.PSObject.Properties['metadata'] -and $Context.metadata) {
        foreach ($key in @('prototype_path', 'source_prototype', 'app_prototype_path')) {
            if ($Context.metadata.ContainsKey($key) -and -not [string]::IsNullOrWhiteSpace([string]$Context.metadata[$key])) {
                return (Convert-ToLocalExecutionRepoRelativePath -PathValue ([string]$Context.metadata[$key]))
            }
        }
    }

    $combined = Get-LocalExecutionCombinedText -Context $Context
    $match = [regex]::Match($combined, '(?im)(runtime/shared/user_app_builds/[A-Za-z0-9_./-]+_PROTOTYPE\.latest\.json)')
    if ($match.Success) {
        return (Convert-ToLocalExecutionRepoRelativePath -PathValue ([string]$match.Groups[1].Value))
    }

    $targets = @(Get-LocalExecutionTargetFiles -Context $Context)
    $manifestTarget = [string](@($targets | Where-Object {
                $value = ([string]$_).ToLowerInvariant()
                $value.StartsWith('runtime/shared/user_app_published/') -and $value.EndsWith('/package.manifest.json')
            })[0])
    if ([string]::IsNullOrWhiteSpace($manifestTarget)) {
        return ''
    }
    $parts = $manifestTarget -split '/'
    if (@($parts).Count -lt 4) {
        return ''
    }
    $slug = [string]$parts[3]
    if ([string]::IsNullOrWhiteSpace($slug)) {
        return ''
    }
    $constant = $slug.ToUpperInvariant()
    $candidate = "runtime/shared/user_app_builds/$slug/${constant}_PROTOTYPE.latest.json"
    $absoluteCandidate = Join-Path $script:LocalEngineRepoRoot ($candidate -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    if (Test-Path -Path $absoluteCandidate -PathType Leaf) {
        return $candidate
    }
    return ''
}

function Invoke-LocalExecutionLedgerCoverage {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)]$Spec
    )

    $sharedDir = Join-Path $script:LocalEngineRepoRoot 'runtime\shared'
    $expectedEventTypes = @('request_observed', 'ack_observed', 'progress_observed', 'result_observed', 'blocked_observed', 'heartbeat_observed')

    $artifactMap = @{
        request_observed   = @('MIM_TOD_TASK_REQUEST.latest.json')
        ack_observed       = @('TOD_MIM_TASK_ACK.latest.json', 'TOD_TO_MIM_TRIGGER_ACK.latest.json', 'MIM_TO_TOD_TRIGGER.latest.json')
        progress_observed  = @('TOD_ACTIVE_TASK.latest.json', 'TOD_ACTIVITY_STREAM.latest.json')
        result_observed    = @('TOD_EXECUTION_RESULT.latest.json', 'TOD_MIM_TASK_RESULT.latest.json')
        blocked_observed   = @('TOD_EXECUTION_LOCK.latest.json')
        heartbeat_observed = @('TOD_MIM_LEDGER_OBSERVE_STATUS.latest.json')
    }

    $breakdown = [ordered]@{}
    $coveredTypes = [System.Collections.Generic.List[string]]::new()
    $missingTypes = [System.Collections.Generic.List[string]]::new()

    foreach ($eventType in $expectedEventTypes) {
        $candidateFiles = $artifactMap[$eventType]
        $matchedFile = $null
        $fileSize = 0
        $fileAge = $null
        foreach ($candidate in $candidateFiles) {
            $candidatePath = Join-Path $sharedDir $candidate
            if (Test-Path $candidatePath) {
                $info = Get-Item $candidatePath
                $matchedFile = $candidate
                $fileSize = [long]$info.Length
                $fileAge = $info.LastWriteTimeUtc.ToString('o')
                break
            }
        }
        $observed = $null -ne $matchedFile
        $breakdown[$eventType] = [pscustomobject]@{
            observed         = $observed
            artifact_file    = if ($observed) { $matchedFile } else { $null }
            artifact_size    = $fileSize
            artifact_age_utc = $fileAge
        }
        if ($observed) { $coveredTypes.Add($eventType) | Out-Null } else { $missingTypes.Add($eventType) | Out-Null }
    }

    $coveredCount = $coveredTypes.Count
    $totalCount   = $expectedEventTypes.Count
    $coveragePct  = [math]::Round(($coveredCount / $totalCount) * 100, 2)

    $outputFile = Join-Path $sharedDir 'TOD_MIM_LEDGER_PHASE_A_COVERAGE.latest.json'
    $reportId   = 'phase-a-coverage-{0}' -f ([guid]::NewGuid().ToString('N'))
    $report = [ordered]@{
        generated_at          = (Get-Date).ToUniversalTime().ToString('o')
        report_id             = $reportId
        objective             = [string]$Context.objective_id
        observe_only          = $true
        non_blocking_confirmed = $true
        runtime_impact        = 'none'
        expected = [ordered]@{
            lifecycle_event_types = $expectedEventTypes
            total = $totalCount
        }
        covered = [ordered]@{
            lifecycle_event_types = @($coveredTypes)
            total = $coveredCount
        }
        missing = [ordered]@{
            lifecycle_event_types = @($missingTypes)
            total = $missingTypes.Count
        }
        coverage_percent = $coveragePct
        breakdown = $breakdown
        source = 'LocalExecutionEngine::Invoke-LocalExecutionLedgerCoverage'
    }

    $reportJson = $report | ConvertTo-Json -Depth 10 -Compress:$false
    [System.IO.File]::WriteAllText($outputFile, $reportJson, [System.Text.Encoding]::UTF8)

    $relOutputFile = 'runtime/shared/TOD_MIM_LEDGER_PHASE_A_COVERAGE.latest.json'
    $summaryLine = ('Phase A message-ledger coverage: {0}/{1} event types observed ({2}%)' -f $coveredCount, $totalCount, $coveragePct)

    $Result.summary        = $summaryLine
    $Result.files_changed  = @($relOutputFile)
    $Result.tests_run      = @('ledger-coverage-artifact-scan', 'ledger-coverage-report-write')
    $Result.test_results   = @('passed', 'passed')
    $Result.failures       = @()
    $Result.recommendations = if ($missingTypes.Count -gt 0) {
        @(('Missing lifecycle coverage for: {0}. Ensure MIM publishes these event types to runtime/shared.' -f ($missingTypes -join ', ')))
    } else {
        @('Full Phase A lifecycle coverage confirmed. Advance to Phase B shadow-write instrumentation.')
    }
    $Result.needs_escalation = $false
    $Result.structured_findings = @(
        [pscustomobject]@{
            type             = 'coverage_report'
            report_id        = $reportId
            coverage_percent = $coveragePct
            covered_count    = $coveredCount
            total_count      = $totalCount
            missing_types    = @($missingTypes)
            output_file      = $relOutputFile
        }
    )
    $Result.raw_output = $report

    return (Complete-EngineExecutionResult -Result $Result -Status 'completed')
}

function Invoke-LocalExecutionMimArmWorkspaceSafety {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)]$Spec
    )

    $targetFile = 'tmp_remote_mim/routes.py'
    if (-not (Test-LocalExecutionSafePath -RelativePath $targetFile)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'local_fallback_path_not_allowed' -Reason 'LocalExecutionEngine rejected tmp_remote_mim/routes.py because it is outside the bounded safe roots.' -MissingVariable 'allowed_path')
    }

    $absoluteTargetPath = Join-Path $script:LocalEngineRepoRoot ($targetFile -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -Path $absoluteTargetPath -PathType Leaf)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'local_fallback_needs_target_or_scope' -Reason 'LocalExecutionEngine could not find the MIM workspace routes mirror at tmp_remote_mim/routes.py.' -MissingVariable 'existing_target_file')
    }

    $content = [string](Get-Content -Path $absoluteTargetPath -Raw)
    $checksBeforeCommand = @(
        [pscustomobject]@{ name = 'target_file_exists'; passed = $true },
        [pscustomobject]@{ name = 'servo_limit_helper_present'; passed = $content.Contains('def _workspace_servo_limit_for') },
        [pscustomobject]@{ name = 'servo_clamp_helper_present'; passed = $content.Contains('def _workspace_clamp_servo_angle') },
        [pscustomobject]@{ name = 'move_route_uses_clamped_angle'; passed = $content.Contains('angle, safety = _workspace_clamp_servo_angle(servo, requested_angle)') },
        [pscustomobject]@{ name = 'dry_run_no_motion_guard_present'; passed = ($content.Contains('dry_run = bool') -and $content.Contains('move_dry_run_validated')) },
        [pscustomobject]@{ name = 'move_response_includes_safety_metadata'; passed = $content.Contains('"safety": safety') },
        [pscustomobject]@{ name = 'table_edge_guard_declared'; passed = $content.Contains('"table_edge_guard": "servo_limit_clamp"') }
    )

    $venvPython = Join-Path $script:LocalEngineRepoRoot '.venv\Scripts\python.exe'
    $pythonCommand = if (Test-Path -Path $venvPython) {
        "& '$venvPython'"
    }
    else {
        'python'
    }
    $validationCommand = $pythonCommand + ' -m py_compile tmp_remote_mim/routes.py'
    $commandCapture = Invoke-LocalShellCapture -Command $validationCommand -WorkingDirectory $script:LocalEngineRepoRoot
    $validationChecks = @($checksBeforeCommand + [pscustomobject]@{ name = 'python_compile_passed'; passed = ([int]$commandCapture.exit_code -eq 0) })
    $allPassed = (@($validationChecks | Where-Object { -not [bool]$_.passed }).Count -eq 0)

    if (-not $allPassed) {
        $failedNames = @($validationChecks | Where-Object { -not [bool]$_.passed } | ForEach-Object { [string]$_.name })
        $reason = ('MIM ARM workspace safety calibration could not be validated; missing or failing checks: {0}.' -f (@($failedNames) -join ', '))
        $Result.summary = $reason
        $Result.files_changed = @()
        $Result.tests_run = @($validationChecks | ForEach-Object { [string]$_.name })
        $Result.test_results = @($validationChecks | ForEach-Object { if ([bool]$_.passed) { 'pass' } else { 'fail' } })
        $Result.failures = @($reason)
        $Result.recommendations = @('Keep the hardware path blocked until the workspace /move safety clamp, dry-run mode, and safety metadata are all present and py_compile passes.')
        $Result.needs_escalation = $false
        $Result.structured_findings = @(
            [pscustomobject]@{ type = 'validation'; checks = $validationChecks },
            [pscustomobject]@{ type = 'command'; capture = $commandCapture },
            [pscustomobject]@{ type = 'blocker'; reason_code = 'mim_arm_workspace_safety_validation_failed'; file = 'tmp_remote_mim/routes.py'; function = 'move_servo'; reason = $reason }
        )
        $Result.raw_output = [pscustomobject]@{
            engine = $Spec
            task_context = $Context
            action = 'mim_arm_workspace_safety_validation_failed'
            target_file = $targetFile
            validation_checks = $validationChecks
            command_capture = $commandCapture
            hardware_motion_invoked = $false
            generated_at = (Get-Date).ToUniversalTime().ToString('o')
        }
        $Result | Add-Member -NotePropertyName reason_code -NotePropertyValue 'mim_arm_workspace_safety_validation_failed' -Force
        $Result | Add-Member -NotePropertyName recovery_state -NotePropertyValue 'blocked_with_reason' -Force
        $Result | Add-Member -NotePropertyName commands_run -NotePropertyValue @([string]$commandCapture.command) -Force
        $Result | Add-Member -NotePropertyName validation_results -NotePropertyValue @($validationChecks) -Force
        $Result | Add-Member -NotePropertyName blockers -NotePropertyValue @($Result.structured_findings | Where-Object { $_.type -eq 'blocker' }) -Force
        $Result | Add-Member -NotePropertyName confidence -NotePropertyValue 'medium' -Force
        $Result | Add-Member -NotePropertyName rollback_hint -NotePropertyValue '' -Force
        return (Complete-EngineExecutionResult -Result $Result -Status 'failed')
    }

    $diffSummary = 'Validated MIM ARM workspace /move safety clamp, dry-run/no-motion validation mode, and response safety metadata in tmp_remote_mim/routes.py without invoking hardware.'
    $Result.summary = 'LocalExecutionEngine validated the MIM ARM workspace safety calibration route slice without moving hardware.'
    $Result.files_changed = @()
    $Result.tests_run = @($validationChecks | ForEach-Object { [string]$_.name })
    $Result.test_results = @($validationChecks | ForEach-Object { 'pass' })
    $Result.failures = @()
    $Result.recommendations = @('Deploy the validated routes.py safety slice to the MIM ARM workspace server before testing physical shoulder recovery.')
    $Result.needs_escalation = $false
    $Result.structured_findings = @(
        [pscustomobject]@{
            type = 'result_contract'
            understood_task = 'Validate the first MIM ARM workspace safety calibration slice for routes.py.'
            action_taken = $diffSummary
            changed_files = @()
            evidence = @($diffSummary)
            validation_result = 'passed'
            remaining_blocker = 'Validated in local MIM mirror only; deploy to the MIM ARM workspace server before live hardware use.'
            next_action = 'Deploy the safety route slice, then validate dry-run /move behavior before any real servo command.'
            confidence = 'medium-high'
            accepted = $true
            artifact_changed = $false
        },
        [pscustomobject]@{ type = 'command'; capture = $commandCapture },
        [pscustomobject]@{ type = 'validation'; checks = $validationChecks }
    )
    $Result.raw_output = [pscustomobject]@{
        engine = $Spec
        task_context = $Context
        action = 'mim_arm_workspace_safety_validated'
        target_file = $targetFile
        changed = $false
        diff_summary = $diffSummary
        validation_checks = $validationChecks
        command_capture = $commandCapture
        hardware_motion_invoked = $false
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
    }
    $Result | Add-Member -NotePropertyName diff_summary -NotePropertyValue $diffSummary -Force
    $Result | Add-Member -NotePropertyName commands_run -NotePropertyValue @([string]$commandCapture.command) -Force
    $Result | Add-Member -NotePropertyName validation_results -NotePropertyValue @($validationChecks) -Force
    $Result | Add-Member -NotePropertyName blockers -NotePropertyValue @() -Force
    $Result | Add-Member -NotePropertyName confidence -NotePropertyValue 'medium-high' -Force
    $Result | Add-Member -NotePropertyName rollback_hint -NotePropertyValue '' -Force
    $Result | Add-Member -NotePropertyName no_change_required -NotePropertyValue $true -Force
    return (Complete-EngineExecutionResult -Result $Result -Status 'completed')
}

function Test-LocalExecutionGenericBoundedTask {
    param([Parameter(Mandatory = $true)]$Context)

    if (Test-LocalExecutionExecutionLoopContractTask -Context $Context) { return $false }
    if (Test-LocalExecutionConfigBootstrapTask -Context $Context) { return $false }
    if (Test-LocalExecutionReadmeDryRunTask -Context $Context) { return $false }
    if (Test-LocalExecutionGenericRisk -Context $Context) { return $false }

    $taskCategory = Get-LocalExecutionTaskCategory -Context $Context
    if (@('code_change', 'config_change', 'test_change', 'docs_change') -contains $taskCategory) {
        return $true
    }

    return (@(Get-LocalExecutionTargetFiles -Context $Context).Count -gt 0)
}

function Get-LocalExecutionDirectiveValue {
    param(
        [Parameter(Mandatory = $true)][string]$PromptText,
        [Parameter(Mandatory = $true)][string]$FieldName
    )

    $match = [regex]::Match($PromptText, ('(?im)^\s*{0}\s*:\s*([^\r\n]+)\s*$' -f [regex]::Escape($FieldName)))
    if ($match.Success) {
        return ([string]$match.Groups[1].Value).Trim()
    }

    return ''
}

function New-LocalExecutionPatternValidationCommand {
    param(
        [Parameter(Mandatory = $true)][string]$TargetFile,
        [Parameter(Mandatory = $true)][string]$Pattern
    )

    $safeTarget = $TargetFile -replace '/', '\'
    $safePattern = $Pattern.Replace("'", "''")
    return "if (-not (Get-Content -Path '.\$safeTarget' | Select-String -SimpleMatch '$safePattern')) { throw 'Validation pattern not found: $safePattern' } else { 'Validation pattern found: $safePattern' }"
}

function Convert-ToLocalExecutionEditMode {
    param([AllowEmptyString()][string]$Mode)

    $normalized = ([string]$Mode).Trim().ToLowerInvariant() -replace '[\s-]+', '_'
    switch ($normalized) {
        'replace_text' { return 'replace_text' }
        'replace_exact_text' { return 'replace_text' }
        'append_section' { return 'append_section' }
        'docs_append_section' { return 'append_section' }
        'insert_after' { return 'insert_after' }
        'insert_after_anchor' { return 'insert_after' }
        'append_marker' { return 'insert_after' }
        'add_small_function' { return 'insert_after' }
        'update_json_field' { return 'update_json_field' }
        'validation_only' { return 'validation_only' }
        default { return '' }
    }
}

function ConvertFrom-LocalExecutionJsonValue {
    param([AllowEmptyString()][string]$Text)

    if ([string]::IsNullOrWhiteSpace([string]$Text)) {
        return ''
    }

    $trimmed = ([string]$Text).Trim()
    try {
        return ($trimmed | ConvertFrom-Json)
    }
    catch {
        $boolValue = $false
        if ([bool]::TryParse($trimmed, [ref]$boolValue)) {
            return $boolValue
        }
        $intValue = 0
        if ([int]::TryParse($trimmed, [ref]$intValue)) {
            return $intValue
        }
        $doubleValue = 0.0
        if ([double]::TryParse($trimmed, [ref]$doubleValue)) {
            return $doubleValue
        }
        return $trimmed
    }
}

function Set-LocalExecutionJsonFieldValue {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value
    )

    $segments = @(([string]$Path).Split('.') | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if (@($segments).Count -eq 0) {
        throw 'Json field path is empty.'
    }

    $cursor = $Object
    for ($index = 0; $index -lt ($segments.Count - 1); $index++) {
        $segment = [string]$segments[$index]
        $next = $null
        if ($cursor -is [System.Collections.IDictionary]) {
            if (-not $cursor.Contains($segment) -or $null -eq $cursor[$segment]) {
                $cursor[$segment] = [ordered]@{}
            }
            $next = $cursor[$segment]
        }
        else {
            if (-not $cursor.PSObject.Properties[$segment] -or $null -eq $cursor.$segment) {
                $cursor | Add-Member -NotePropertyName $segment -NotePropertyValue ([pscustomobject]@{}) -Force
            }
            $next = $cursor.$segment
        }
        $cursor = $next
    }

    $leaf = [string]$segments[$segments.Count - 1]
    if ($cursor -is [System.Collections.IDictionary]) {
        $cursor[$leaf] = $Value
    }
    else {
        $cursor | Add-Member -NotePropertyName $leaf -NotePropertyValue $Value -Force
    }

    return $Object
}

function Get-LocalExecutionMarkdownSectionSpec {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][string]$PromptText,
        [Parameter(Mandatory = $true)][string]$TargetFile
    )

    $combined = Get-LocalExecutionCombinedText -Context $Context
    $explicitTitle = Get-LocalExecutionDirectiveValue -PromptText $PromptText -FieldName 'Section Title'
    $explicitBody = Get-LocalExecutionDirectiveValue -PromptText $PromptText -FieldName 'Section Body'
    $sectionTitle = $explicitTitle
    if ([string]::IsNullOrWhiteSpace($sectionTitle)) {
        $match = [regex]::Match($combined, '(?im)\b(?:with|add|insert|append)\s+(?:a\s+)?(?:short\s+)?(.+?)\s+section\b')
        if ($match.Success) {
            $sectionTitle = ([string]$match.Groups[1].Value).Trim(" .:-`"")
        }
    }
    if ([string]::IsNullOrWhiteSpace($sectionTitle)) {
        return $null
    }

    $normalizedTitle = ($sectionTitle -replace '\s+', ' ').Trim()
    $heading = if ($normalizedTitle.StartsWith('#')) { $normalizedTitle } else { '## ' + $normalizedTitle }
    $body = $explicitBody
    if ([string]::IsNullOrWhiteSpace($body)) {
        $body = @(
            ('TOD can use the local fallback executor for bounded tasks in {0} when Codex only returns wrapper output or no meaningful execution evidence.' -f $TargetFile),
            '',
            '- Eligibility stays inside bounded docs, code, config, or test changes under allowed paths.',
            '- Published evidence includes changed files, diff summary, command output, validation results, blockers, and rollback hints.',
            '- The executor fails closed when it cannot infer a safe target or bounded patch.'
        ) -join "`n"
    }

    return [pscustomobject]@{
        heading = $heading
        body = $body -replace "`r`n", "`n"
        title = $normalizedTitle
    }
}

function Get-LocalExecutionDiffSummary {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$BeforeContent,
        [Parameter(Mandatory = $true)][string]$AfterContent,
        [Parameter(Mandatory = $true)][string]$ActionSummary
    )

    $beforeLines = @([regex]::Split(($BeforeContent -replace "`r`n", "`n"), "`n"))
    $afterLines = @([regex]::Split(($AfterContent -replace "`r`n", "`n"), "`n"))
    $lineDelta = [math]::Abs($afterLines.Count - $beforeLines.Count)
    return ('{0} [{1}] line_count {2}->{3} delta={4}' -f $ActionSummary, $RelativePath, $beforeLines.Count, $afterLines.Count, $lineDelta)
}

function New-LocalExecutionBlockedResult {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)]$Spec,
        [Parameter(Mandatory = $true)][string]$ReasonCode,
        [Parameter(Mandatory = $true)][string]$Reason,
        [string]$MissingVariable = ''
    )

    $Result.summary = $Reason
    $Result.files_changed = @()
    $Result.tests_run = @('local-fallback eligibility')
    $Result.test_results = @('blocked')
    $Result.failures = @($Reason)
    $Result.recommendations = @('Keep the bounded task blocked until the missing target, scope, or safe patch directive is explicit.')
    $Result.needs_escalation = $false
    $Result.structured_findings = @(
        [pscustomobject]@{
            type = 'blocker'
            reason_code = $ReasonCode
            file = 'scripts/engines/LocalExecutionEngine.ps1'
            function = 'Invoke-LocalExecutionGenericBoundedTask'
            reason = $Reason
            missing_variable = $MissingVariable
            task_id = [string]$Context.task_id
            objective_id = [string]$Context.objective_id
        }
    )
    $Result.raw_output = [pscustomobject]@{
        engine = $Spec
        task_context = $Context
        action = 'generic_bounded_task_blocked'
        reason_code = $ReasonCode
        missing_variable = $MissingVariable
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
    }
    $Result | Add-Member -NotePropertyName reason_code -NotePropertyValue $ReasonCode -Force
    $Result | Add-Member -NotePropertyName recovery_state -NotePropertyValue 'blocked_with_reason' -Force
    $Result | Add-Member -NotePropertyName blockers -NotePropertyValue @($Result.structured_findings) -Force
    return (Complete-EngineExecutionResult -Result $Result -Status 'failed')
}

function Invoke-LocalExecutionGenericBoundedTask {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)]$Spec
    )

    $promptText = Get-LocalExecutionPromptText -Context $Context
    $targets = @(Get-LocalExecutionTargetFiles -Context $Context)
    if (@($targets).Count -eq 0) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'local_fallback_needs_target_or_scope' -Reason 'LocalExecutionEngine could not infer a single bounded target file from the task prompt or scope.' -MissingVariable 'target_file')
    }
    if (@($targets).Count -gt 1) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'local_fallback_needs_target_or_scope' -Reason ('LocalExecutionEngine found multiple candidate target files ({0}) and will not guess which one to patch.' -f (@($targets) -join ', ')) -MissingVariable 'target_file')
    }

    $targetFile = [string]$targets[0]
    if (-not (Test-LocalExecutionSafePath -RelativePath $targetFile)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'local_fallback_path_not_allowed' -Reason ('LocalExecutionEngine rejected target path {0} because it is outside the bounded safe roots.' -f $targetFile) -MissingVariable 'allowed_path')
    }

    $absoluteTargetPath = Join-Path $script:LocalEngineRepoRoot ($targetFile -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -Path $absoluteTargetPath)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'local_fallback_needs_target_or_scope' -Reason ('LocalExecutionEngine requires an existing target file, but {0} was not found.' -f $targetFile) -MissingVariable 'existing_target_file')
    }
    if (Test-LocalExecutionGenericRisk -Context $Context) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'local_fallback_risk_blocked' -Reason 'LocalExecutionEngine rejected the bounded fallback because the task mentions a risky security, production, or safety surface.' -MissingVariable 'safe_scope')
    }

    $originalContent = [string](Get-Content -Path $absoluteTargetPath -Raw)
    $updatedContent = $originalContent
    $actionSummary = ''
    $validationCommand = ''
    $skipWriteBack = $false
    $mode = Convert-ToLocalExecutionEditMode -Mode (Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Edit Mode')
    if ([string]::IsNullOrWhiteSpace($mode) -and $targetFile.ToLowerInvariant().EndsWith('.md') -and (Get-LocalExecutionCombinedText -Context $Context).ToLowerInvariant() -match '\bsection\b') {
        $mode = 'append_section'
    }

    switch ($mode) {
        'append_section' {
            $sectionSpec = Get-LocalExecutionMarkdownSectionSpec -Context $Context -PromptText $promptText -TargetFile $targetFile
            if ($null -eq $sectionSpec) {
                return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'local_fallback_needs_target_or_scope' -Reason 'LocalExecutionEngine could not infer the markdown section title for the bounded docs change.' -MissingVariable 'section_title')
            }
            $newline = if ($originalContent.Contains("`r`n")) { "`r`n" } else { "`n" }
            $normalizedOriginal = $originalContent -replace "`r`n", "`n"
            $sectionBlock = ($sectionSpec.heading + "`n`n" + $sectionSpec.body.Trim()) -replace "`r`n", "`n"
            $sectionRegex = '(?ms)^' + [regex]::Escape($sectionSpec.heading) + '\s*$.*?(?=^##\s+|\z)'
            if ([regex]::IsMatch($normalizedOriginal, $sectionRegex)) {
                $updatedNormalized = [regex]::Replace($normalizedOriginal, $sectionRegex, $sectionBlock + "`n")
                $actionSummary = ('Updated markdown section {0}' -f $sectionSpec.title)
            }
            else {
                $trimmed = $normalizedOriginal.TrimEnd()
                $updatedNormalized = ($trimmed + "`n`n" + $sectionBlock + "`n")
                $actionSummary = ('Added markdown section {0}' -f $sectionSpec.title)
            }
            $updatedContent = if ($newline -eq "`r`n") { $updatedNormalized -replace "`n", "`r`n" } else { $updatedNormalized }
            $validationPattern = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Validation Pattern'
            if ([string]::IsNullOrWhiteSpace($validationPattern)) { $validationPattern = $sectionSpec.heading }
            $validationCommand = New-LocalExecutionPatternValidationCommand -TargetFile $targetFile -Pattern $validationPattern
        }
        'insert_after' {
            $anchor = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Anchor'
            $snippet = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Snippet'
            if ([string]::IsNullOrWhiteSpace($anchor)) {
                return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'local_fallback_needs_target_or_scope' -Reason 'LocalExecutionEngine requires an Anchor directive for insert_after mode.' -MissingVariable 'anchor')
            }
            if ([string]::IsNullOrWhiteSpace($snippet)) {
                return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'local_fallback_needs_target_or_scope' -Reason 'LocalExecutionEngine requires a Snippet directive for insert_after mode.' -MissingVariable 'snippet')
            }
            if (-not $originalContent.Contains($anchor)) {
                return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'local_fallback_needs_target_or_scope' -Reason ('LocalExecutionEngine could not find the requested anchor in {0}.' -f $targetFile) -MissingVariable 'anchor')
            }
            $newline = if ($originalContent.Contains("`r`n")) { "`r`n" } else { "`n" }
            if ($originalContent.Contains($snippet)) {
                $updatedContent = $originalContent
            }
            else {
                $updatedContent = $originalContent.Replace($anchor, ($anchor + $newline + $snippet))
            }
            $actionSummary = ('Inserted bounded snippet after anchor in {0}' -f $targetFile)
            $validationPattern = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Validation Pattern'
            if ([string]::IsNullOrWhiteSpace($validationPattern)) { $validationPattern = $snippet }
            $validationCommand = New-LocalExecutionPatternValidationCommand -TargetFile $targetFile -Pattern $validationPattern
        }
        'replace_text' {
            $oldText = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Old Text'
            $newText = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'New Text'
            if ([string]::IsNullOrWhiteSpace($oldText)) {
                return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'local_fallback_needs_target_or_scope' -Reason 'LocalExecutionEngine requires an Old Text directive for replace_text mode.' -MissingVariable 'old_text')
            }
            if ([string]::IsNullOrWhiteSpace($newText)) {
                return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'local_fallback_needs_target_or_scope' -Reason 'LocalExecutionEngine requires a New Text directive for replace_text mode.' -MissingVariable 'new_text')
            }
            $updatedContent = Set-StrictTextReplacement -Content $originalContent -OldText $oldText -NewText $newText -Label ('bounded replacement in ' + $targetFile)
            $actionSummary = ('Replaced bounded text in {0}' -f $targetFile)
            $validationPattern = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Validation Pattern'
            if ([string]::IsNullOrWhiteSpace($validationPattern)) { $validationPattern = $newText }
            $validationCommand = New-LocalExecutionPatternValidationCommand -TargetFile $targetFile -Pattern $validationPattern
        }
        'update_json_field' {
            $jsonField = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Json Field'
            $jsonValue = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Json Value'
            if ([string]::IsNullOrWhiteSpace($jsonField)) {
                return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'local_fallback_needs_target_or_scope' -Reason 'LocalExecutionEngine requires a Json Field directive for update_json_field mode.' -MissingVariable 'json_field')
            }
            if ([string]::IsNullOrWhiteSpace($jsonValue)) {
                return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'local_fallback_needs_target_or_scope' -Reason 'LocalExecutionEngine requires a Json Value directive for update_json_field mode.' -MissingVariable 'json_value')
            }
            $jsonObject = $originalContent | ConvertFrom-Json
            $typedJsonValue = ConvertFrom-LocalExecutionJsonValue -Text $jsonValue
            $jsonObject = Set-LocalExecutionJsonFieldValue -Object $jsonObject -Path $jsonField -Value $typedJsonValue
            $updatedContent = ($jsonObject | ConvertTo-Json -Depth 20)
            $actionSummary = ('Updated JSON field {0} in {1}' -f $jsonField, $targetFile)
            $validationPattern = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Validation Pattern'
            if ([string]::IsNullOrWhiteSpace($validationPattern)) { $validationPattern = $jsonField }
            $validationCommand = New-LocalExecutionPatternValidationCommand -TargetFile $targetFile -Pattern $validationPattern
        }
        'validation_only' {
            $actionSummary = ('Validated bounded target in {0}' -f $targetFile)
            $skipWriteBack = $true
            $validationCommand = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Validation Command'
            if ([string]::IsNullOrWhiteSpace($validationCommand)) {
                $validationPattern = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Validation Pattern'
                if (-not [string]::IsNullOrWhiteSpace($validationPattern)) {
                    $validationCommand = New-LocalExecutionPatternValidationCommand -TargetFile $targetFile -Pattern $validationPattern
                }
                else {
                    $validationCommand = "if (Test-Path -Path '.\\$($targetFile -replace '/', '\\')') { 'validated' } else { throw 'Target file missing.' }"
                }
            }
            $updatedContent = $originalContent
        }
        default {
            return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'local_fallback_needs_target_or_scope' -Reason 'LocalExecutionEngine requires an explicit bounded edit mode or an inferable markdown section update for this task.' -MissingVariable 'edit_mode')
        }
    }

    $backupRoot = Join-Path $script:LocalEngineRepoRoot 'tod/out/local-engine-backups'
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    $timestamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
    $fileLeaf = Split-Path -Path $absoluteTargetPath -Leaf
    $backupPath = Join-Path $backupRoot ('{0}.{1}.bak' -f $fileLeaf, $timestamp)
    $prePatchHash = [string](Get-FileHash -Path $absoluteTargetPath -Algorithm SHA256).Hash
    $changeApplied = ((-not $skipWriteBack) -and ($updatedContent -ne $originalContent))
    if (-not $skipWriteBack) {
        Copy-Item -Path $absoluteTargetPath -Destination $backupPath -Force
        Write-Utf8NoBomFile -Path $absoluteTargetPath -Content $updatedContent
    }

    $commandCapture = Invoke-LocalShellCapture -Command $validationCommand -WorkingDirectory $script:LocalEngineRepoRoot
    $validatedContent = [string](Get-Content -Path $absoluteTargetPath -Raw)
    $postPatchHash = [string](Get-FileHash -Path $absoluteTargetPath -Algorithm SHA256).Hash
    $passed = ([int]$commandCapture.exit_code -eq 0)
    $diffSummary = Get-LocalExecutionDiffSummary -RelativePath $targetFile -BeforeContent $originalContent -AfterContent $updatedContent -ActionSummary $actionSummary
    $rollbackState = [pscustomobject]@{
        available = (-not $skipWriteBack)
        backup_path = $(if ($skipWriteBack) { '' } else { $backupPath })
        target_path = $absoluteTargetPath
        pre_patch_hash = $prePatchHash
        post_patch_hash = $postPatchHash
        restore_command = $(if ($skipWriteBack) { '' } else { "Copy-Item -Path '$backupPath' -Destination '$absoluteTargetPath' -Force" })
    }
    $validationChecks = @(
        [pscustomobject]@{ name = 'target_file_exists'; passed = (Test-Path -Path $absoluteTargetPath) },
        [pscustomobject]@{ name = 'focused_validation_exit_zero'; passed = $passed },
        [pscustomobject]@{ name = 'change_or_requested_state_present'; passed = ($changeApplied -or ($validatedContent -eq $updatedContent)) }
    )

    if (-not $passed) {
        if (-not $skipWriteBack) {
            Copy-Item -Path $backupPath -Destination $absoluteTargetPath -Force
        }
        $Result.summary = ('LocalExecutionEngine rolled back the bounded local fallback for {0} because focused validation failed.' -f $targetFile)
        $Result.files_changed = [string[]]@()
        $Result.tests_run = @($validationChecks | ForEach-Object { [string]$_.name })
        $Result.test_results = @($validationChecks | ForEach-Object { if ([bool]$_.passed) { 'pass' } else { 'fail' } })
        $Result.failures = @('Focused validation failed after the local fallback patch, so the target file was restored from backup.')
        $Result.recommendations = @('Keep the task blocked until the bounded patch or validation target is more explicit.')
        $Result.needs_escalation = $false
        $Result.structured_findings = @(
            [pscustomobject]@{ type = 'rollback'; rollback = $rollbackState },
            [pscustomobject]@{ type = 'validation'; checks = $validationChecks },
            [pscustomobject]@{ type = 'command'; capture = $commandCapture },
            [pscustomobject]@{ type = 'blocker'; reason_code = 'local_fallback_validation_failed'; file = 'scripts/engines/LocalExecutionEngine.ps1'; function = 'Invoke-LocalExecutionGenericBoundedTask'; reason = 'Focused validation failed and the bounded patch was rolled back.' }
        )
        $Result.raw_output = [pscustomobject]@{
            engine = $Spec
            task_context = $Context
            action = 'generic_bounded_task_rolled_back'
            target_file = $targetFile
            diff_summary = $diffSummary
            validation_checks = $validationChecks
            command_capture = $commandCapture
            rollback = $rollbackState
            generated_at = (Get-Date).ToUniversalTime().ToString('o')
        }
        $Result | Add-Member -NotePropertyName reason_code -NotePropertyValue 'local_fallback_validation_failed' -Force
        $Result | Add-Member -NotePropertyName recovery_state -NotePropertyValue 'blocked_with_reason' -Force
        $Result | Add-Member -NotePropertyName diff_summary -NotePropertyValue $diffSummary -Force
        $Result | Add-Member -NotePropertyName commands_run -NotePropertyValue @([string]$commandCapture.command) -Force
        $Result | Add-Member -NotePropertyName validation_results -NotePropertyValue @($validationChecks) -Force
        $Result | Add-Member -NotePropertyName blockers -NotePropertyValue @($Result.structured_findings | Where-Object { $_.type -eq 'blocker' }) -Force
        $Result | Add-Member -NotePropertyName confidence -NotePropertyValue 'medium' -Force
        $Result | Add-Member -NotePropertyName rollback_hint -NotePropertyValue ([string]$rollbackState.restore_command) -Force
        return (Complete-EngineExecutionResult -Result $Result -Status 'failed')
    }

    $Result.summary = ('LocalExecutionEngine completed the bounded local fallback for {0} and published real execution evidence.' -f $targetFile)
    $Result.files_changed = [string[]]$(if ($changeApplied) { @($targetFile) } else { @() })
    $Result.tests_run = @($validationChecks | ForEach-Object { [string]$_.name })
    $Result.test_results = @($validationChecks | ForEach-Object { if ([bool]$_.passed) { 'pass' } else { 'fail' } })
    $Result.failures = @()
    $Result.recommendations = @('Publish the bounded local fallback evidence and continue only with the next bounded validation slice.')
    $Result.needs_escalation = $false
    $Result.structured_findings = @(
        [pscustomobject]@{
            type = 'result_contract'
            understood_task = ('Apply a bounded local fallback patch to {0}.' -f $targetFile)
            action_taken = $actionSummary
            changed_files = @($Result.files_changed)
            evidence = @($diffSummary)
            validation_result = 'passed'
            remaining_blocker = ''
            next_action = 'Publish the bounded local fallback evidence.'
            confidence = 'medium-high'
            accepted = $true
            artifact_changed = $changeApplied
        },
        [pscustomobject]@{ type = 'command'; capture = $commandCapture },
        [pscustomobject]@{ type = 'rollback'; rollback = $rollbackState },
        [pscustomobject]@{ type = 'validation'; checks = $validationChecks }
    )
    $Result.raw_output = [pscustomobject]@{
        engine = $Spec
        task_context = $Context
        action = 'generic_bounded_task_completed'
        target_file = $targetFile
        changed = $changeApplied
        diff_summary = $diffSummary
        validation_checks = $validationChecks
        command_capture = $commandCapture
        rollback = $rollbackState
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
    }
    $Result | Add-Member -NotePropertyName diff_summary -NotePropertyValue $diffSummary -Force
    $Result | Add-Member -NotePropertyName commands_run -NotePropertyValue @([string]$commandCapture.command) -Force
    $Result | Add-Member -NotePropertyName validation_results -NotePropertyValue @($validationChecks) -Force
    $Result | Add-Member -NotePropertyName blockers -NotePropertyValue @() -Force
    $Result | Add-Member -NotePropertyName confidence -NotePropertyValue 'medium-high' -Force
    $Result | Add-Member -NotePropertyName rollback_hint -NotePropertyValue ([string]$rollbackState.restore_command) -Force
    $Result | Add-Member -NotePropertyName command_output -NotePropertyValue ([string]$commandCapture.stdout) -Force
    $Result | Add-Member -NotePropertyName no_change_required -NotePropertyValue (-not $changeApplied) -Force
    $Result | Add-Member -NotePropertyName reason_code -NotePropertyValue '' -Force
    $Result | Add-Member -NotePropertyName recovery_state -NotePropertyValue 'not_needed' -Force
    return (Complete-EngineExecutionResult -Result $Result -Status 'completed')
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

function Test-LocalExecutionPromptTokenExtractionTask {
    param([Parameter(Mandatory = $true)]$Context)

    $normalized = (Get-LocalExecutionCombinedText -Context $Context).ToLowerInvariant()
    return ($normalized -match 'patch token extraction') -and ($normalized -match 'identifier value is captured')
}

function Get-LocalExecutionPromptTokenExtractionTargetFile {
    param([Parameter(Mandatory = $true)]$Context)

    if ($Context.PSObject.Properties['metadata'] -and $Context.metadata -and $Context.metadata.ContainsKey('local_fallback_target_file')) {
        $rawOverridePath = [string]$Context.metadata.local_fallback_target_file
        if (-not [string]::IsNullOrWhiteSpace($rawOverridePath)) {
            $overridePath = Convert-ToLocalExecutionRepoRelativePath -PathValue $rawOverridePath
            if (-not [string]::IsNullOrWhiteSpace($overridePath)) {
                return $overridePath
            }
        }
    }

    return 'tmp_remote_mim/core/routers/tod_ui.py'
}

function Get-LocalExecutionPromptTokenExtractionValidationCommand {
    param([Parameter(Mandatory = $true)]$Context)

    if ($Context.PSObject.Properties['metadata'] -and $Context.metadata -and $Context.metadata.ContainsKey('local_fallback_validation_command')) {
        return [string]$Context.metadata.local_fallback_validation_command
    }

    $venvPython = Join-Path $script:LocalEngineRepoRoot '.venv\Scripts\python.exe'
    $pythonCommand = if (Test-Path -Path $venvPython) {
        "& '$venvPython'"
    }
    else {
        'python'
    }

    return ($pythonCommand + ' -m unittest ' +
        'test_tmp_remote_mim_tod_ui_state.TodUiStateClassificationTests.test_extract_labeled_prompt_value_captures_only_identifier_token ' +
        'test_tmp_remote_mim_tod_ui_state.TodUiStateClassificationTests.test_extract_labeled_prompt_value_reads_markdown_heading_and_bullet_labels')
}

function Invoke-LocalExecutionPromptTokenExtractionTask {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)]$Spec
    )

    $targetFile = Get-LocalExecutionPromptTokenExtractionTargetFile -Context $Context
    if (-not (Test-LocalExecutionSafePath -RelativePath $targetFile)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'local_fallback_path_not_allowed' -Reason ('LocalExecutionEngine rejected target path {0} because it is outside the bounded safe roots.' -f $targetFile) -MissingVariable 'allowed_path')
    }

    $absoluteTargetPath = Join-Path $script:LocalEngineRepoRoot ($targetFile -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -Path $absoluteTargetPath)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'local_fallback_needs_target_or_scope' -Reason ('LocalExecutionEngine requires an existing target file, but {0} was not found.' -f $targetFile) -MissingVariable 'existing_target_file')
    }

    $originalContent = [string](Get-Content -Path $absoluteTargetPath -Raw)
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
    $newSnippet = @'
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

    $updatedContent = Set-StrictTextReplacement -Content $originalContent -OldText $oldSnippet -NewText $newSnippet -Label 'prompt token extraction helper'
    $backupRoot = Join-Path $script:LocalEngineRepoRoot 'tod/out/local-engine-backups'
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    $timestamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
    $fileLeaf = Split-Path -Path $absoluteTargetPath -Leaf
    $backupPath = Join-Path $backupRoot ('{0}.{1}.bak' -f $fileLeaf, $timestamp)
    Copy-Item -Path $absoluteTargetPath -Destination $backupPath -Force
    $prePatchHash = [string](Get-FileHash -Path $absoluteTargetPath -Algorithm SHA256).Hash
    $changeApplied = ($updatedContent -ne $originalContent)
    Write-Utf8NoBomFile -Path $absoluteTargetPath -Content $updatedContent

    $validationCommand = Get-LocalExecutionPromptTokenExtractionValidationCommand -Context $Context
    $commandCapture = Invoke-LocalShellCapture -Command $validationCommand -WorkingDirectory $script:LocalEngineRepoRoot
    $validatedContent = [string](Get-Content -Path $absoluteTargetPath -Raw)
    $postPatchHash = [string](Get-FileHash -Path $absoluteTargetPath -Algorithm SHA256).Hash
    $validationChecks = @(
        [pscustomobject]@{ name = 'target_file_exists'; passed = (Test-Path -Path $absoluteTargetPath) },
        [pscustomobject]@{ name = 'identifier_helper_present'; passed = ($validatedContent.Contains('def _extract_identifier_token(value: str) -> str:')) },
        [pscustomobject]@{ name = 'focused_validation_exit_zero'; passed = ([int]$commandCapture.exit_code -eq 0) }
    )
    $passed = -not (@($validationChecks | Where-Object { -not [bool]$_.passed }).Count)
    $diffSummary = Get-LocalExecutionDiffSummary -RelativePath $targetFile -BeforeContent $originalContent -AfterContent $updatedContent -ActionSummary 'Patched prompt label token extraction to capture only identifier values'
    $rollbackState = [pscustomobject]@{
        available = $true
        backup_path = $backupPath
        target_path = $absoluteTargetPath
        pre_patch_hash = $prePatchHash
        post_patch_hash = $postPatchHash
        restore_command = "Copy-Item -Path '$backupPath' -Destination '$absoluteTargetPath' -Force"
    }

    if (-not $passed) {
        Copy-Item -Path $backupPath -Destination $absoluteTargetPath -Force
        $Result.summary = ('LocalExecutionEngine rolled back the prompt token extraction patch for {0} because focused validation failed.' -f $targetFile)
        $Result.files_changed = @()
        $Result.tests_run = @($validationChecks | ForEach-Object { [string]$_.name })
        $Result.test_results = @($validationChecks | ForEach-Object { if ([bool]$_.passed) { 'pass' } else { 'fail' } })
        $Result.failures = @('Focused validation failed after the prompt token extraction patch, so the target file was restored from backup.')
        $Result.recommendations = @('Keep the task blocked until the bounded token-extraction patch or validation target is more explicit.')
        $Result.needs_escalation = $false
        $Result.structured_findings = @(
            [pscustomobject]@{ type = 'rollback'; rollback = $rollbackState },
            [pscustomobject]@{ type = 'validation'; checks = $validationChecks },
            [pscustomobject]@{ type = 'command'; capture = $commandCapture },
            [pscustomobject]@{ type = 'blocker'; reason_code = 'local_fallback_validation_failed'; file = 'scripts/engines/LocalExecutionEngine.ps1'; function = 'Invoke-LocalExecutionPromptTokenExtractionTask'; reason = 'Focused validation failed and the bounded patch was rolled back.' }
        )
        $Result.raw_output = [pscustomobject]@{
            engine = $Spec
            task_context = $Context
            action = 'prompt_token_extraction_rolled_back'
            target_file = $targetFile
            diff_summary = $diffSummary
            validation_checks = $validationChecks
            command_capture = $commandCapture
            rollback = $rollbackState
            generated_at = (Get-Date).ToUniversalTime().ToString('o')
        }
        $Result | Add-Member -NotePropertyName reason_code -NotePropertyValue 'local_fallback_validation_failed' -Force
        $Result | Add-Member -NotePropertyName recovery_state -NotePropertyValue 'blocked_with_reason' -Force
        $Result | Add-Member -NotePropertyName diff_summary -NotePropertyValue $diffSummary -Force
        $Result | Add-Member -NotePropertyName commands_run -NotePropertyValue @([string]$commandCapture.command) -Force
        $Result | Add-Member -NotePropertyName validation_results -NotePropertyValue @($validationChecks) -Force
        $Result | Add-Member -NotePropertyName blockers -NotePropertyValue @($Result.structured_findings | Where-Object { $_.type -eq 'blocker' }) -Force
        $Result | Add-Member -NotePropertyName confidence -NotePropertyValue 'medium' -Force
        $Result | Add-Member -NotePropertyName rollback_hint -NotePropertyValue ([string]$rollbackState.restore_command) -Force
        return (Complete-EngineExecutionResult -Result $Result -Status 'failed')
    }

    $Result.summary = ('LocalExecutionEngine patched prompt token extraction in {0} and published real execution evidence.' -f $targetFile)
    $Result.files_changed = if ($changeApplied) { @($targetFile) } else { @() }
    $Result.tests_run = @($validationChecks | ForEach-Object { [string]$_.name })
    $Result.test_results = @($validationChecks | ForEach-Object { if ([bool]$_.passed) { 'pass' } else { 'fail' } })
    $Result.failures = @()
    $Result.recommendations = @('Publish the bounded prompt token extraction evidence and continue only with the next focused validation slice.')
    $Result.needs_escalation = $false
    $Result.structured_findings = @(
        [pscustomobject]@{
            type = 'result_contract'
            understood_task = 'Patch prompt label token extraction so identifier fields capture only the declared token.'
            action_taken = 'Patched _extract_labeled_prompt_value in tmp_remote_mim/core/routers/tod_ui.py.'
            changed_files = @($Result.files_changed)
            evidence = @($diffSummary)
            validation_result = 'passed'
            remaining_blocker = ''
            next_action = 'Publish the bounded local fallback evidence.'
            confidence = 'medium-high'
            accepted = $true
            artifact_changed = $changeApplied
        },
        [pscustomobject]@{ type = 'command'; capture = $commandCapture },
        [pscustomobject]@{ type = 'rollback'; rollback = $rollbackState },
        [pscustomobject]@{ type = 'validation'; checks = $validationChecks }
    )
    $Result.raw_output = [pscustomobject]@{
        engine = $Spec
        task_context = $Context
        action = 'prompt_token_extraction_completed'
        target_file = $targetFile
        changed = $changeApplied
        diff_summary = $diffSummary
        validation_checks = $validationChecks
        command_capture = $commandCapture
        rollback = $rollbackState
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
    }
    $Result | Add-Member -NotePropertyName diff_summary -NotePropertyValue $diffSummary -Force
    $Result | Add-Member -NotePropertyName commands_run -NotePropertyValue @([string]$commandCapture.command) -Force
    $Result | Add-Member -NotePropertyName validation_results -NotePropertyValue @($validationChecks) -Force
    $Result | Add-Member -NotePropertyName blockers -NotePropertyValue @() -Force
    $Result | Add-Member -NotePropertyName confidence -NotePropertyValue 'medium-high' -Force
    $Result | Add-Member -NotePropertyName rollback_hint -NotePropertyValue ([string]$rollbackState.restore_command) -Force
    $Result | Add-Member -NotePropertyName command_output -NotePropertyValue ([string]$commandCapture.stdout) -Force
    $Result | Add-Member -NotePropertyName reason_code -NotePropertyValue '' -Force
    $Result | Add-Member -NotePropertyName recovery_state -NotePropertyValue 'not_needed' -Force
    return (Complete-EngineExecutionResult -Result $Result -Status 'completed')
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

function Invoke-LocalExecutionUserAppPrototypeArtifact {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)]$Spec
    )

    $targets = @(Get-LocalExecutionTargetFiles -Context $Context)
    $targetFile = [string](@($targets | Where-Object { ([string]$_).ToLowerInvariant().StartsWith('runtime/shared/user_app_builds/') -and ([string]$_).ToLowerInvariant().EndsWith('.json') })[0])
    if ([string]::IsNullOrWhiteSpace($targetFile)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'app_prototype_needs_target_file' -Reason 'LocalExecutionEngine needs one runtime/shared/user_app_builds/... prototype JSON target file before it can generate an app artifact.' -MissingVariable 'target_file')
    }
    if (-not (Test-LocalExecutionSafePath -RelativePath $targetFile)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'app_prototype_target_not_allowed' -Reason ('LocalExecutionEngine rejected app prototype target path {0} because it is outside safe roots.' -f $targetFile) -MissingVariable 'allowed_path')
    }

    $intakePath = Get-LocalExecutionUserAppIntakePath -Context $Context
    if ([string]::IsNullOrWhiteSpace($intakePath)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'app_prototype_needs_intake' -Reason 'LocalExecutionEngine needs an intake JSON path before it can generate the app prototype artifact.' -MissingVariable 'intake_path')
    }
    $absoluteIntakePath = Join-Path $script:LocalEngineRepoRoot ($intakePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -Path $absoluteIntakePath -PathType Leaf)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'app_prototype_intake_missing' -Reason ('LocalExecutionEngine could not find the app intake artifact at {0}.' -f $intakePath) -MissingVariable 'intake_path')
    }

    $generatorPath = Join-Path $script:LocalEngineRepoRoot 'scripts\New-UserAppPrototypeArtifact.ps1'
    if (-not (Test-Path -Path $generatorPath -PathType Leaf)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'app_prototype_generator_missing' -Reason 'LocalExecutionEngine could not find scripts/New-UserAppPrototypeArtifact.ps1.' -MissingVariable 'generator')
    }

    $absoluteTargetPath = Join-Path $script:LocalEngineRepoRoot ($targetFile -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    $backupRoot = Join-Path $script:LocalEngineRepoRoot 'tod/out/local-engine-backups'
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    $timestamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
    $backupPath = ''
    $prePatchHash = ''
    if (Test-Path -Path $absoluteTargetPath -PathType Leaf) {
        $backupPath = Join-Path $backupRoot ('{0}.{1}.bak' -f (Split-Path -Path $absoluteTargetPath -Leaf), $timestamp)
        Copy-Item -Path $absoluteTargetPath -Destination $backupPath -Force
        $prePatchHash = [string](Get-FileHash -Path $absoluteTargetPath -Algorithm SHA256).Hash
    }

    $safeIntake = $intakePath.Replace("'", "''")
    $safeTarget = $targetFile.Replace("'", "''")
    $command = "& '.\scripts\New-UserAppPrototypeArtifact.ps1' -IntakePath '$safeIntake' -OutputPath '$safeTarget' -Source 'LocalExecutionEngine::Invoke-LocalExecutionUserAppPrototypeArtifact'"
    $commandCapture = Invoke-LocalShellCapture -Command $command -WorkingDirectory $script:LocalEngineRepoRoot
    $postPatchHash = if (Test-Path -Path $absoluteTargetPath -PathType Leaf) { [string](Get-FileHash -Path $absoluteTargetPath -Algorithm SHA256).Hash } else { '' }

    $artifact = $null
    $jsonRoundTrip = $false
    if (Test-Path -Path $absoluteTargetPath -PathType Leaf) {
        try {
            $artifact = Get-Content -Path $absoluteTargetPath -Raw | ConvertFrom-Json
            $jsonRoundTrip = ($null -ne $artifact -and [string]$artifact.artifact_type -eq 'user_app_workbench_prototype_v1')
        }
        catch {
            $jsonRoundTrip = $false
        }
    }

    $requiredFoundationScreens = @('front_page', 'login', 'dashboard', 'settings', 'help_support')
    $foundationScreenCount = 0
    if ($jsonRoundTrip) {
        $foundationScreenCount = @($artifact.screens | Where-Object { $requiredFoundationScreens -contains [string]$_.key }).Count
    }
    $acceptanceAndChangeLogPresent = ($jsonRoundTrip -and @($artifact.acceptance_checklist).Count -gt 0 -and @($artifact.change_log).Count -gt 0)

    $validationChecks = @(
        [pscustomobject]@{ name = 'generator_exit_zero'; passed = ([int]$commandCapture.exit_code -eq 0) },
        [pscustomobject]@{ name = 'target_file_exists'; passed = (Test-Path -Path $absoluteTargetPath -PathType Leaf) },
        [pscustomobject]@{ name = 'json_round_trip'; passed = $jsonRoundTrip },
        [pscustomobject]@{ name = 'foundation_screens_present'; passed = ($foundationScreenCount -ge 5) },
        [pscustomobject]@{ name = 'acceptance_and_change_log_present'; passed = $acceptanceAndChangeLogPresent }
    )
    $passed = -not (@($validationChecks | Where-Object { -not [bool]$_.passed }).Count)
    $rollbackState = [pscustomobject]@{
        available = (-not [string]::IsNullOrWhiteSpace($backupPath))
        backup_path = $backupPath
        target_path = $absoluteTargetPath
        pre_patch_hash = $prePatchHash
        post_patch_hash = $postPatchHash
        restore_command = $(if ([string]::IsNullOrWhiteSpace($backupPath)) { '' } else { "Copy-Item -Path '$backupPath' -Destination '$absoluteTargetPath' -Force" })
    }

    if (-not $passed) {
        if (-not [string]::IsNullOrWhiteSpace($backupPath) -and (Test-Path -Path $backupPath -PathType Leaf)) {
            Copy-Item -Path $backupPath -Destination $absoluteTargetPath -Force
        }
        $Result.summary = ('LocalExecutionEngine attempted to generate app prototype artifact {0} but validation failed.' -f $targetFile)
        $Result.files_changed = @()
        $Result.tests_run = @($validationChecks | ForEach-Object { [string]$_.name })
        $Result.test_results = @($validationChecks | ForEach-Object { if ([bool]$_.passed) { 'pass' } else { 'fail' } })
        $Result.failures = @('App prototype generation failed validation; target was restored if a backup existed.')
        $Result.recommendations = @('Inspect the generator output and keep the app artifact task bounded to one intake file and one prototype JSON output.')
        $Result.needs_escalation = $false
        $Result.structured_findings = @(
            [pscustomobject]@{ type = 'validation'; checks = $validationChecks },
            [pscustomobject]@{ type = 'command'; capture = $commandCapture },
            [pscustomobject]@{ type = 'rollback'; rollback = $rollbackState },
            [pscustomobject]@{ type = 'blocker'; reason_code = 'app_prototype_validation_failed'; file = 'scripts/New-UserAppPrototypeArtifact.ps1'; reason = 'Generated artifact did not satisfy prototype contract.' }
        )
        $Result.raw_output = [pscustomobject]@{
            engine = $Spec
            task_context = $Context
            action = 'user_app_prototype_artifact_failed'
            intake_path = $intakePath
            target_file = $targetFile
            validation_checks = $validationChecks
            command_capture = $commandCapture
            rollback = $rollbackState
            generated_at = (Get-Date).ToUniversalTime().ToString('o')
        }
        return (Complete-EngineExecutionResult -Result $Result -Status 'failed')
    }

    $Result.summary = ('LocalExecutionEngine generated a real Workbench app prototype artifact for {0} from intake and validated the app foundation contract.' -f [string]$artifact.app_name)
    $Result.files_changed = @($targetFile)
    $Result.tests_run = @($validationChecks | ForEach-Object { [string]$_.name })
    $Result.test_results = @($validationChecks | ForEach-Object { if ([bool]$_.passed) { 'pass' } else { 'fail' } })
    $Result.failures = @()
    $Result.recommendations = @('Render the generated prototype in Workbench and dispatch the first app-specific interactive workflow slice.')
    $Result.needs_escalation = $false
    $Result.structured_findings = @(
        [pscustomobject]@{
            type = 'result_contract'
            understood_task = 'Generate a reviewable app prototype artifact from an intake brief without Codex authoring the artifact.'
            action_taken = 'Ran scripts/New-UserAppPrototypeArtifact.ps1 and validated the output JSON, foundation screens, acceptance checklist, and change log.'
            changed_files = @($Result.files_changed)
            evidence = @('prototype JSON created or refreshed', 'json_round_trip passed', 'foundation screens present', 'acceptance/change log present')
            validation_result = 'passed'
            remaining_blocker = ''
            next_action = 'Render the artifact in Workbench and implement the first app-specific workflow.'
            confidence = 'medium-high'
        },
        [pscustomobject]@{ type = 'validation'; checks = $validationChecks },
        [pscustomobject]@{ type = 'command'; capture = $commandCapture },
        [pscustomobject]@{ type = 'rollback'; rollback = $rollbackState }
    )
    $Result.raw_output = [pscustomobject]@{
        engine = $Spec
        task_context = $Context
        action = 'user_app_prototype_artifact_completed'
        intake_path = $intakePath
        target_file = $targetFile
        app_name = [string]$artifact.app_name
        files_changed = @($Result.files_changed)
        validation_checks = $validationChecks
        command_capture = $commandCapture
        rollback = $rollbackState
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
    }
    return (Complete-EngineExecutionResult -Result $Result -Status 'completed')
}

function Invoke-LocalExecutionUserAppPublishedPreview {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)]$Spec
    )

    $targets = @(Get-LocalExecutionTargetFiles -Context $Context)
    $manifestFile = [string](@($targets | Where-Object {
                $value = ([string]$_).ToLowerInvariant()
                $value.StartsWith('runtime/shared/user_app_published/') -and $value.EndsWith('/package.manifest.json')
            })[0])
    if ([string]::IsNullOrWhiteSpace($manifestFile)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'app_publish_needs_manifest_target' -Reason 'LocalExecutionEngine needs one runtime/shared/user_app_published/.../package.manifest.json target file before it can publish an app preview package.' -MissingVariable 'target_file')
    }
    if (-not (Test-LocalExecutionSafePath -RelativePath $manifestFile)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'app_publish_target_not_allowed' -Reason ('LocalExecutionEngine rejected app publish target path {0} because it is outside safe roots.' -f $manifestFile) -MissingVariable 'allowed_path')
    }

    $prototypePath = Get-LocalExecutionUserAppPrototypePathForPublish -Context $Context
    if ([string]::IsNullOrWhiteSpace($prototypePath)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'app_publish_needs_prototype' -Reason 'LocalExecutionEngine could not find the source prototype artifact needed to publish a preview package.' -MissingVariable 'prototype_path')
    }
    $absolutePrototypePath = Join-Path $script:LocalEngineRepoRoot ($prototypePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -Path $absolutePrototypePath -PathType Leaf)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'app_publish_prototype_missing' -Reason ('LocalExecutionEngine could not find the app prototype artifact at {0}.' -f $prototypePath) -MissingVariable 'prototype_path')
    }

    $generatorPath = Join-Path $script:LocalEngineRepoRoot 'scripts\New-UserAppPublishedPreview.ps1'
    if (-not (Test-Path -Path $generatorPath -PathType Leaf)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'app_publish_generator_missing' -Reason 'LocalExecutionEngine could not find scripts/New-UserAppPublishedPreview.ps1.' -MissingVariable 'generator')
    }

    $absoluteManifestPath = Join-Path $script:LocalEngineRepoRoot ($manifestFile -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    $backupRoot = Join-Path $script:LocalEngineRepoRoot 'tod/out/local-engine-backups'
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    $timestamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
    $backupPath = ''
    $prePatchHash = ''
    if (Test-Path -Path $absoluteManifestPath -PathType Leaf) {
        $backupPath = Join-Path $backupRoot ('{0}.{1}.bak' -f (Split-Path -Path $absoluteManifestPath -Leaf), $timestamp)
        Copy-Item -Path $absoluteManifestPath -Destination $backupPath -Force
        $prePatchHash = [string](Get-FileHash -Path $absoluteManifestPath -Algorithm SHA256).Hash
    }

    $safePrototype = $prototypePath.Replace("'", "''")
    $safeManifest = $manifestFile.Replace("'", "''")
    $command = "& '.\scripts\New-UserAppPublishedPreview.ps1' -PrototypePath '$safePrototype' -OutputManifestPath '$safeManifest' -Source 'LocalExecutionEngine::Invoke-LocalExecutionUserAppPublishedPreview'"
    $commandCapture = Invoke-LocalShellCapture -Command $command -WorkingDirectory $script:LocalEngineRepoRoot
    $postPatchHash = if (Test-Path -Path $absoluteManifestPath -PathType Leaf) { [string](Get-FileHash -Path $absoluteManifestPath -Algorithm SHA256).Hash } else { '' }

    $manifest = $null
    $jsonRoundTrip = $false
    if (Test-Path -Path $absoluteManifestPath -PathType Leaf) {
        try {
            $manifest = Get-Content -Path $absoluteManifestPath -Raw | ConvertFrom-Json
            $jsonRoundTrip = ($null -ne $manifest -and [string]$manifest.artifact_type -eq 'user_app_published_preview_manifest_v1')
        }
        catch {
            $jsonRoundTrip = $false
        }
    }
    $previewPath = if ($manifest -and $manifest.PSObject.Properties['preview_path']) { [string]$manifest.preview_path } else { '' }
    $summaryPath = if ($manifest -and $manifest.PSObject.Properties['completion_summary_path']) { [string]$manifest.completion_summary_path } else { '' }
    $readmePath = if ($manifest -and $manifest.PSObject.Properties['readme_path']) { [string]$manifest.readme_path } else { '' }
    $pathExists = {
        param([string]$RelativePath)
        if ([string]::IsNullOrWhiteSpace($RelativePath)) { return $false }
        $absolute = Join-Path $script:LocalEngineRepoRoot ($RelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        return (Test-Path -Path $absolute -PathType Leaf)
    }

    $validationChecks = @(
        [pscustomobject]@{ name = 'publisher_exit_zero'; passed = ([int]$commandCapture.exit_code -eq 0) },
        [pscustomobject]@{ name = 'manifest_file_exists'; passed = (Test-Path -Path $absoluteManifestPath -PathType Leaf) },
        [pscustomobject]@{ name = 'manifest_json_round_trip'; passed = $jsonRoundTrip },
        [pscustomobject]@{ name = 'preview_html_exists'; passed = (& $pathExists $previewPath) },
        [pscustomobject]@{ name = 'completion_summary_exists'; passed = (& $pathExists $summaryPath) },
        [pscustomobject]@{ name = 'readme_exists'; passed = (& $pathExists $readmePath) }
    )
    $passed = -not (@($validationChecks | Where-Object { -not [bool]$_.passed }).Count)
    $rollbackState = [pscustomobject]@{
        available = (-not [string]::IsNullOrWhiteSpace($backupPath))
        backup_path = $backupPath
        target_path = $absoluteManifestPath
        pre_patch_hash = $prePatchHash
        post_patch_hash = $postPatchHash
        restore_command = $(if ([string]::IsNullOrWhiteSpace($backupPath)) { '' } else { "Copy-Item -Path '$backupPath' -Destination '$absoluteManifestPath' -Force" })
    }

    if (-not $passed) {
        if (-not [string]::IsNullOrWhiteSpace($backupPath) -and (Test-Path -Path $backupPath -PathType Leaf)) {
            Copy-Item -Path $backupPath -Destination $absoluteManifestPath -Force
        }
        $Result.summary = ('LocalExecutionEngine attempted to publish app preview package {0} but validation failed.' -f $manifestFile)
        $Result.files_changed = @()
        $Result.tests_run = @($validationChecks | ForEach-Object { [string]$_.name })
        $Result.test_results = @($validationChecks | ForEach-Object { if ([bool]$_.passed) { 'pass' } else { 'fail' } })
        $Result.failures = @('App publish preview generation failed validation; manifest was restored if a backup existed.')
        $Result.recommendations = @('Inspect the publisher output and keep the publish task bounded to one prototype artifact and one manifest output.')
        $Result.needs_escalation = $false
        $Result.structured_findings = @(
            [pscustomobject]@{ type = 'validation'; checks = $validationChecks },
            [pscustomobject]@{ type = 'command'; capture = $commandCapture },
            [pscustomobject]@{ type = 'rollback'; rollback = $rollbackState },
            [pscustomobject]@{ type = 'blocker'; reason_code = 'app_publish_preview_validation_failed'; file = 'scripts/New-UserAppPublishedPreview.ps1'; reason = 'Published preview package did not satisfy manifest contract.' }
        )
        $Result.raw_output = [pscustomobject]@{
            engine = $Spec
            task_context = $Context
            action = 'user_app_published_preview_failed'
            prototype_path = $prototypePath
            target_file = $manifestFile
            validation_checks = $validationChecks
            command_capture = $commandCapture
            rollback = $rollbackState
            generated_at = (Get-Date).ToUniversalTime().ToString('o')
        }
        return (Complete-EngineExecutionResult -Result $Result -Status 'failed')
    }

    $changedFiles = @($manifestFile, $previewPath, $summaryPath, $readmePath | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    $Result.summary = ('LocalExecutionEngine published a Workbench preview package for {0} with manifest, preview HTML, help/presentation evidence, and completion summary.' -f [string]$manifest.app_name)
    $Result.files_changed = @($changedFiles)
    $Result.tests_run = @($validationChecks | ForEach-Object { [string]$_.name })
    $Result.test_results = @($validationChecks | ForEach-Object { if ([bool]$_.passed) { 'pass' } else { 'fail' } })
    $Result.failures = @()
    $Result.recommendations = @('Open the published preview HTML, verify the walkthrough visually, then select a production deploy target or record the next app-specific interaction slice.')
    $Result.needs_escalation = $false
    $Result.structured_findings = @(
        [pscustomobject]@{
            type = 'result_contract'
            understood_task = 'Publish a reviewable app preview package from an existing TOD-generated prototype artifact.'
            action_taken = 'Ran scripts/New-UserAppPublishedPreview.ps1 and validated manifest, preview HTML, completion summary, and README.'
            changed_files = @($Result.files_changed)
            evidence = @('package manifest generated', 'preview HTML generated', 'completion summary generated', 'README generated')
            validation_result = 'passed'
            remaining_blocker = 'Production deploy target is not selected.'
            next_action = 'Review the preview and dispatch app-specific interactive/persistence slices.'
            confidence = 'medium-high'
        },
        [pscustomobject]@{ type = 'validation'; checks = $validationChecks },
        [pscustomobject]@{ type = 'command'; capture = $commandCapture },
        [pscustomobject]@{ type = 'rollback'; rollback = $rollbackState }
    )
    $Result.raw_output = [pscustomobject]@{
        engine = $Spec
        task_context = $Context
        action = 'user_app_published_preview_completed'
        prototype_path = $prototypePath
        target_file = $manifestFile
        app_name = [string]$manifest.app_name
        preview_path = $previewPath
        files_changed = @($Result.files_changed)
        validation_checks = $validationChecks
        command_capture = $commandCapture
        rollback = $rollbackState
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
    }
    return (Complete-EngineExecutionResult -Result $Result -Status 'completed')
}

function Test-LocalExecutionUserAppHeroMediaTask {
    param([Parameter(Mandatory = $true)]$Context)

    $targets = @(Get-LocalExecutionTargetFiles -Context $Context)
    $heroTarget = @($targets | Where-Object {
            $value = ([string]$_).ToLowerInvariant()
            $value.StartsWith('runtime/shared/user_app_published/') -and $value.EndsWith('/media/hero.png')
        } | Select-Object -First 1)
    if (@($heroTarget).Count -gt 0) { return $true }

    $scope = if ($Context.PSObject.Properties['scope']) { [string]$Context.scope } else { '' }
    return ($scope -match 'user_app_hero_media_generation|hero media asset|hero png|bitmap hero')
}

function Invoke-LocalExecutionUserAppHeroMedia {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)]$Spec
    )

    $targets = @(Get-LocalExecutionTargetFiles -Context $Context)
    $assetFile = [string](@($targets | Where-Object {
                $value = ([string]$_).ToLowerInvariant()
                $value.StartsWith('runtime/shared/user_app_published/') -and $value.EndsWith('/media/hero.png')
            } | Select-Object -First 1))
    if ([string]::IsNullOrWhiteSpace($assetFile)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'app_hero_media_needs_asset_target' -Reason 'LocalExecutionEngine needs one runtime/shared/user_app_published/.../media/hero.png target file before it can generate user-app hero media.' -MissingVariable 'target_file')
    }
    if (-not (Test-LocalExecutionSafePath -RelativePath $assetFile)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'app_hero_media_target_not_allowed' -Reason ('LocalExecutionEngine rejected app hero media target path {0} because it is outside safe roots.' -f $assetFile) -MissingVariable 'allowed_path')
    }

    $parts = $assetFile -split '/'
    $slug = if (@($parts).Count -ge 4) { [string]$parts[3] } else { '' }
    if ([string]::IsNullOrWhiteSpace($slug)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'app_hero_media_slug_missing' -Reason 'LocalExecutionEngine could not derive app slug from hero media target path.' -MissingVariable 'app_slug')
    }

    $generatorPath = Join-Path $script:LocalEngineRepoRoot 'scripts\New-UserAppHeroMediaAsset.ps1'
    if (-not (Test-Path -Path $generatorPath -PathType Leaf)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'app_hero_media_generator_missing' -Reason 'LocalExecutionEngine could not find scripts/New-UserAppHeroMediaAsset.ps1.' -MissingVariable 'generator')
    }

    $prompt = if ($Context.PSObject.Properties['scope'] -and -not [string]::IsNullOrWhiteSpace([string]$Context.scope)) { [string]$Context.scope } else { [string]$Context.title }
    $safeSlug = $slug.Replace("'", "''")
    $safePrompt = $prompt.Replace("'", "''")
    $command = "& '.\scripts\New-UserAppHeroMediaAsset.ps1' -AppSlug '$safeSlug' -Prompt '$safePrompt' -Source 'LocalExecutionEngine::Invoke-LocalExecutionUserAppHeroMedia'"
    $commandCapture = Invoke-LocalShellCapture -Command $command -WorkingDirectory $script:LocalEngineRepoRoot

    $absoluteAssetPath = Join-Path $script:LocalEngineRepoRoot ($assetFile -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    $manifestFile = "runtime/shared/user_app_published/$slug/package.manifest.json"
    $previewFile = "runtime/shared/user_app_published/$slug/preview.html"
    $mediaManifestFile = "runtime/shared/user_app_published/$slug/media/media.manifest.json"
    $absoluteManifestPath = Join-Path $script:LocalEngineRepoRoot ($manifestFile -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    $absolutePreviewPath = Join-Path $script:LocalEngineRepoRoot ($previewFile -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    $absoluteMediaManifestPath = Join-Path $script:LocalEngineRepoRoot ($mediaManifestFile -replace '/', [System.IO.Path]::DirectorySeparatorChar)

    $manifest = $null
    $previewHtml = ''
    $mediaManifest = $null
    try {
        if (Test-Path -Path $absoluteManifestPath -PathType Leaf) { $manifest = Get-Content -Path $absoluteManifestPath -Raw | ConvertFrom-Json }
        if (Test-Path -Path $absolutePreviewPath -PathType Leaf) { $previewHtml = Get-Content -Path $absolutePreviewPath -Raw }
        if (Test-Path -Path $absoluteMediaManifestPath -PathType Leaf) { $mediaManifest = Get-Content -Path $absoluteMediaManifestPath -Raw | ConvertFrom-Json }
    }
    catch {
        $manifest = $null
    }

    $assetSize = if (Test-Path -Path $absoluteAssetPath -PathType Leaf) { (Get-Item -Path $absoluteAssetPath).Length } else { 0 }
    $validationChecks = @(
        [pscustomobject]@{ name = 'hero_generator_exit_zero'; passed = ([int]$commandCapture.exit_code -eq 0) },
        [pscustomobject]@{ name = 'hero_png_exists'; passed = (Test-Path -Path $absoluteAssetPath -PathType Leaf) },
        [pscustomobject]@{ name = 'hero_png_nontrivial_size'; passed = ($assetSize -gt 20000) },
        [pscustomobject]@{ name = 'media_manifest_exists'; passed = (Test-Path -Path $absoluteMediaManifestPath -PathType Leaf) },
        [pscustomobject]@{ name = 'media_manifest_source'; passed = ($mediaManifest -and [string]$mediaManifest.source -eq 'LocalExecutionEngine::Invoke-LocalExecutionUserAppHeroMedia') },
        [pscustomobject]@{ name = 'preview_references_hero_png'; passed = ($previewHtml -match 'media/hero\.png' -and $previewHtml -match 'hero-media-img') },
        [pscustomobject]@{ name = 'manifest_records_hero_media'; passed = ($manifest -and $manifest.PSObject.Properties['hero_media_status'] -and [string]$manifest.hero_media_status -eq 'hero_png_attached') }
    )
    $passed = -not (@($validationChecks | Where-Object { -not [bool]$_.passed }).Count)

    if (-not $passed) {
        $Result.summary = ('LocalExecutionEngine attempted to generate hero media for {0} but validation failed.' -f $slug)
        $Result.files_changed = @()
        $Result.tests_run = @($validationChecks | ForEach-Object { [string]$_.name })
        $Result.test_results = @($validationChecks | ForEach-Object { if ([bool]$_.passed) { 'pass' } else { 'fail' } })
        $Result.failures = @('User-app hero media generation failed validation.')
        $Result.recommendations = @('Inspect scripts/New-UserAppHeroMediaAsset.ps1 output and keep the task bounded to one app media asset.')
        $Result.needs_escalation = $false
        $Result.structured_findings = @(
            [pscustomobject]@{ type = 'validation'; checks = $validationChecks },
            [pscustomobject]@{ type = 'command'; capture = $commandCapture }
        )
        $Result.raw_output = [pscustomobject]@{
            engine = $Spec
            task_context = $Context
            action = 'user_app_hero_media_failed'
            app_slug = $slug
            target_file = $assetFile
            validation_checks = $validationChecks
            command_capture = $commandCapture
            generated_at = (Get-Date).ToUniversalTime().ToString('o')
        }
        return (Complete-EngineExecutionResult -Result $Result -Status 'failed')
    }

    $Result.summary = ('LocalExecutionEngine generated and attached hero media PNG for {0}.' -f $slug)
    $Result.files_changed = @($assetFile, $mediaManifestFile, $previewFile, $manifestFile)
    $Result.tests_run = @($validationChecks | ForEach-Object { [string]$_.name })
    $Result.test_results = @($validationChecks | ForEach-Object { if ([bool]$_.passed) { 'pass' } else { 'fail' } })
    $Result.failures = @()
    $Result.recommendations = @('Open the published preview and verify the hero image supports the app design instead of replacing product UI clarity.')
    $Result.needs_escalation = $false
    $Result.structured_findings = @(
        [pscustomobject]@{
            type = 'result_contract'
            understood_task = 'Generate and attach a real PNG hero media asset for one user app preview.'
            action_taken = 'Ran scripts/New-UserAppHeroMediaAsset.ps1 and validated PNG, manifest, and preview HTML reference.'
            changed_files = @($Result.files_changed)
            evidence = @('hero PNG generated', 'media manifest generated', 'preview references media/hero.png', 'package manifest records hero_media_status')
            validation_result = 'passed'
            remaining_blocker = 'Visual QA still needs screenshot/browser confirmation when browser tooling is available.'
            next_action = 'Repeat media generation for remaining sample apps after the first app is visually accepted.'
            confidence = 'medium-high'
        },
        [pscustomobject]@{ type = 'validation'; checks = $validationChecks },
        [pscustomobject]@{ type = 'command'; capture = $commandCapture }
    )
    $Result.raw_output = [pscustomobject]@{
        engine = $Spec
        task_context = $Context
        action = 'user_app_hero_media_completed'
        app_slug = $slug
        target_file = $assetFile
        files_changed = @($Result.files_changed)
        validation_checks = $validationChecks
        command_capture = $commandCapture
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
    }
    return (Complete-EngineExecutionResult -Result $Result -Status 'completed')
}

function Get-LocalExecutionEngineSpec {
    [pscustomobject]@{
        name = "local"
        version = "0.5-local-fallback-bounded"
        lifecycle = @("prepare", "execute", "finalize")
        supports = @(
            "structured_result_output",
            "engine_metadata",
            "bounded_file_update",
            "rollback_metadata",
            "command_capture",
            "json_config_update",
            "python_source_patch",
            "focused_python_unittest",
            "generic_bounded_fallback",
            "mim_arm_workspace_safety_validation",
            "user_app_prototype_artifact_generation",
            "user_app_published_preview_generation",
            "user_app_hero_media_generation"
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
    elseif (Test-LocalExecutionPromptTokenExtractionTask -Context $Context) {
        $result = Invoke-LocalExecutionPromptTokenExtractionTask -Context $Context -Result $result -Spec $spec
    }
    elseif (Test-LocalExecutionConfigBootstrapTask -Context $Context) {
        $result = Invoke-LocalExecutionConfigBootstrap -Context $Context -Result $result -Spec $spec
    }
    elseif (Test-LocalExecutionReadmeDryRunTask -Context $Context) {
        $result = Invoke-LocalExecutionReadmeDryRun -Context $Context -Result $result -Spec $spec
    }
    elseif (Test-LocalExecutionLedgerCoverageTask -Context $Context) {
        $result = Invoke-LocalExecutionLedgerCoverage -Context $Context -Result $result -Spec $spec
    }
    elseif (Test-LocalExecutionMimArmWorkspaceSafetyTask -Context $Context) {
        $result = Invoke-LocalExecutionMimArmWorkspaceSafety -Context $Context -Result $result -Spec $spec
    }
    elseif (Test-LocalExecutionUserAppPrototypeArtifactTask -Context $Context) {
        $result = Invoke-LocalExecutionUserAppPrototypeArtifact -Context $Context -Result $result -Spec $spec
    }
    elseif (Test-LocalExecutionUserAppPublishedPreviewTask -Context $Context) {
        $result = Invoke-LocalExecutionUserAppPublishedPreview -Context $Context -Result $result -Spec $spec
    }
    elseif (Test-LocalExecutionUserAppHeroMediaTask -Context $Context) {
        $result = Invoke-LocalExecutionUserAppHeroMedia -Context $Context -Result $result -Spec $spec
    }
    elseif (Test-LocalExecutionGenericBoundedTask -Context $Context) {
        $result = Invoke-LocalExecutionGenericBoundedTask -Context $Context -Result $result -Spec $spec
    }
    else {
        $result.summary = "LocalExecutionEngine is implemented for bounded execution-loop, prompt token extraction, MIM ARM workspace safety validation, README, and TOD config bootstrap objectives, but this task did not match a supported scope."
        $result.tests_run = @("local-engine task scope match")
        $result.test_results = @("not-supported")
        $result.failures = @("Task did not match the current bounded local engine capability.")
        $result.recommendations = @(
            "Package a task that explicitly targets the execution loop contract, prompt token extraction in tmp_remote_mim/core/routers/tod_ui.py, MIM ARM workspace safety validation in tmp_remote_mim/routes.py, README.md with the 'TOD Local Execution Mode' section, or tod-config.json local-engine activation.",
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
        $result | Add-Member -NotePropertyName reason_code -NotePropertyValue 'blocked_missing_capability' -Force
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
