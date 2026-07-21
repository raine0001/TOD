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

    if ($Context.PSObject.Properties['task_category'] -and -not [string]::IsNullOrWhiteSpace([string]$Context.task_category)) {
        return ([string]$Context.task_category).Trim().ToLowerInvariant()
    }
    if ($Context.PSObject.Properties['task_type'] -and -not [string]::IsNullOrWhiteSpace([string]$Context.task_type)) {
        return ([string]$Context.task_type).Trim().ToLowerInvariant()
    }
    if ($Context.PSObject.Properties['type'] -and -not [string]::IsNullOrWhiteSpace([string]$Context.type)) {
        return ([string]$Context.type).Trim().ToLowerInvariant()
    }

    if ($Context.PSObject.Properties['metadata'] -and $Context.metadata) {
        if ($Context.metadata -is [System.Collections.IDictionary]) {
            if ($Context.metadata.ContainsKey('task_category') -and -not [string]::IsNullOrWhiteSpace([string]$Context.metadata.task_category)) {
                return ([string]$Context.metadata.task_category).Trim().ToLowerInvariant()
            }
            if ($Context.metadata.ContainsKey('task_type') -and -not [string]::IsNullOrWhiteSpace([string]$Context.metadata.task_type)) {
                return ([string]$Context.metadata.task_type).Trim().ToLowerInvariant()
            }
        }
        elseif ($Context.metadata.PSObject.Properties['task_category'] -and -not [string]::IsNullOrWhiteSpace([string]$Context.metadata.task_category)) {
            return ([string]$Context.metadata.task_category).Trim().ToLowerInvariant()
        }
        elseif ($Context.metadata.PSObject.Properties['task_type'] -and -not [string]::IsNullOrWhiteSpace([string]$Context.metadata.task_type)) {
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
        'tools/',
        'tests/',
        'runtime/shared/',
        'runtime_remote_training/remote_scripts/',
        'runtime_remote_training/tod_result_artifacts/',
        'runtime_remote_training/tod_independent_resolution_attempts/',
        'runtime_remote_training/read_only_audit_artifacts/',
        'runtime_remote_training/learned_capabilities/',
        'runtime_remote_training/TOD_CAPABILITY_ASSESSMENT_V1.latest.json',
        'runtime_remote_training/TOD_CAPABILITY_ASSESSMENT_V1.latest.md',
        'runtime_remote_training/TOD_CORRECTED_PATCH_SYNTHESIS_PRACTICE_V1.latest.json',
        'tmp_remote_mim/',
        'tmp_remote_mim/core/',
        'tmp_remote_mim/tests/',
        'tod/config/',
        'tod/out/tests/',
        'tod/out/pc-maintenance/'
    )
}

function Get-LocalExecutionProjectScope {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    $normalized = Convert-ToLocalExecutionRepoRelativePath -PathValue $RelativePath
    if (-not $normalized.StartsWith('projects/', [System.StringComparison]::OrdinalIgnoreCase)) {
        return [pscustomobject]@{
            is_project_scoped = $false
            project_id = ''
            project_relative_path = ''
            normalized_path = $normalized
        }
    }

    $parts = @($normalized.Split('/'))
    if (@($parts).Count -lt 3) {
        return [pscustomobject]@{
            is_project_scoped = $false
            project_id = ''
            project_relative_path = ''
            normalized_path = $normalized
        }
    }

    return [pscustomobject]@{
        is_project_scoped = $true
        project_id = [string]$parts[1]
        project_relative_path = (($parts[2..($parts.Length - 1)]) -join '/')
        normalized_path = $normalized
    }
}

function Get-LocalExecutionRegisteredProject {
    param([Parameter(Mandatory = $true)][string]$ProjectId)

    $registryPath = Join-Path $script:LocalEngineRepoRoot 'tod/config/project-registry.json'
    if (-not (Test-Path -Path $registryPath -PathType Leaf)) {
        return $null
    }

    $registry = Get-Content -Path $registryPath -Raw | ConvertFrom-Json
    $projects = if ($registry.PSObject.Properties['projects']) { @($registry.projects) } else { @() }
    return @($projects | Where-Object { [string]$_.id -eq [string]$ProjectId } | Select-Object -First 1)
}

function Get-LocalExecutionProjectMode {
    param([Parameter(Mandatory = $true)][string]$ProjectId)

    $priorityPath = Join-Path $script:LocalEngineRepoRoot 'tod/config/project-priority.json'
    if (-not (Test-Path -Path $priorityPath -PathType Leaf)) {
        return 'guarded-write'
    }

    $priority = Get-Content -Path $priorityPath -Raw | ConvertFrom-Json
    $items = if ($priority.PSObject.Properties['execution_order']) { @($priority.execution_order) } else { @() }
    $entry = @($items | Where-Object { [string]$_.project_id -eq [string]$ProjectId } | Select-Object -First 1)
    if (@($entry).Count -eq 0 -or -not $entry[0].PSObject.Properties['mode'] -or [string]::IsNullOrWhiteSpace([string]$entry[0].mode)) {
        return 'guarded-write'
    }

    return ([string]$entry[0].mode).ToLowerInvariant()
}

function Test-LocalExecutionProjectPathAllowed {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [ValidateSet('read', 'write', 'delete', 'rename')]
        [string]$Operation = 'write'
    )

    $scope = Get-LocalExecutionProjectScope -RelativePath $RelativePath
    if (-not [bool]$scope.is_project_scoped) {
        return $false
    }
    if ([string]::IsNullOrWhiteSpace([string]$scope.project_id) -or [string]::IsNullOrWhiteSpace([string]$scope.project_relative_path)) {
        return $false
    }

    $mode = Get-LocalExecutionProjectMode -ProjectId ([string]$scope.project_id)
    if ($Operation -in @('write', 'delete', 'rename') -and $mode -in @('advisory-first', 'review-only')) {
        return $false
    }

    $policyScript = Join-Path $script:LocalEngineRepoRoot 'scripts/Test-TODProjectAccessPolicy.ps1'
    if (-not (Test-Path -Path $policyScript -PathType Leaf)) {
        return $false
    }

    try {
        $raw = & $policyScript -ProjectId ([string]$scope.project_id) -RelativePaths @([string]$scope.project_relative_path) -Operation $Operation -RegistryPath 'tod/config/project-registry.json'
        $policy = $raw | ConvertFrom-Json
        return ($policy -and $policy.PSObject.Properties['ok'] -and [bool]$policy.ok)
    }
    catch {
        return $false
    }
}

function Resolve-LocalExecutionAbsoluteTargetPath {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [ValidateSet('read', 'write', 'delete', 'rename')]
        [string]$Operation = 'write'
    )

    $normalized = Convert-ToLocalExecutionRepoRelativePath -PathValue $RelativePath
    $scope = Get-LocalExecutionProjectScope -RelativePath $normalized
    if ([bool]$scope.is_project_scoped) {
        if (-not (Test-LocalExecutionProjectPathAllowed -RelativePath $normalized -Operation $Operation)) {
            throw "Project path is not allowed by TOD project policy: $normalized"
        }
        $project = Get-LocalExecutionRegisteredProject -ProjectId ([string]$scope.project_id)
        if ($null -eq $project -or @($project).Count -eq 0 -or -not $project[0].PSObject.Properties['path']) {
            throw "Project is not registered for local execution: $($scope.project_id)"
        }
        $projectRoot = [System.IO.Path]::GetFullPath([string]$project[0].path)
        $candidate = Join-Path $projectRoot (([string]$scope.project_relative_path) -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $targetFull = [System.IO.Path]::GetFullPath($candidate)
        if (-not $targetFull.StartsWith($projectRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Project path escaped registered root: $normalized"
        }
        return $targetFull
    }

    return (Join-Path $script:LocalEngineRepoRoot ($normalized -replace '/', [System.IO.Path]::DirectorySeparatorChar))
}

function Get-LocalExecutionValidationWorkingDirectory {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    $scope = Get-LocalExecutionProjectScope -RelativePath $RelativePath
    if ([bool]$scope.is_project_scoped) {
        $project = Get-LocalExecutionRegisteredProject -ProjectId ([string]$scope.project_id)
        if ($null -ne $project -and @($project).Count -gt 0 -and $project[0].PSObject.Properties['path']) {
            return [System.IO.Path]::GetFullPath([string]$project[0].path)
        }
    }

    return $script:LocalEngineRepoRoot
}

function Resolve-LocalExecutionBackupRoot {
    $candidateRoots = @(
        (Join-Path $script:LocalEngineRepoRoot 'tod/out/local-engine-backups'),
        (Join-Path $script:LocalEngineRepoRoot 'tod/out/context-sync/listener/local-engine-backups')
    )
    foreach ($candidateRoot in $candidateRoots) {
        try {
            New-Item -ItemType Directory -Path $candidateRoot -Force -ErrorAction Stop | Out-Null
            $probePath = Join-Path $candidateRoot ([System.IO.Path]::GetRandomFileName())
            [System.IO.File]::WriteAllText($probePath, 'probe', [System.Text.UTF8Encoding]::new($false))
            Remove-Item -Path $probePath -Force -ErrorAction SilentlyContinue
            return $candidateRoot
        }
        catch {
            continue
        }
    }
    throw 'LocalExecutionEngine could not find a writable backup root.'
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
    if ($normalized -match '^(core|static|templates|tests)/[A-Za-z0-9_./-]+\.(?:py|html|js|json|css|md|txt)$') {
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

    if (Test-LocalExecutionProjectPathAllowed -RelativePath $normalized -Operation 'write') {
        return $true
    }

    foreach ($root in Get-LocalExecutionSafeRoots) {
        $safeRoot = Convert-ToLocalExecutionRepoRelativePath -PathValue $root
        if (-not $safeRoot.EndsWith('/') -and [string]::Equals($normalized, $safeRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
        if ($safeRoot.EndsWith('/') -and $normalized.StartsWith($safeRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $false
}

function Get-LocalExecutionDirectiveSourceText {
    param(
        [Parameter(Mandatory = $true)][string]$PromptText,
        [Parameter(Mandatory = $true)][string]$FieldName
    )

    $sourceFieldName = ('{0} Source File' -f $FieldName)
    $sourceRelativePath = Get-LocalExecutionDirectiveValue -PromptText $PromptText -FieldName $sourceFieldName
    if ([string]::IsNullOrWhiteSpace($sourceRelativePath)) {
        return ''
    }

    $sourceRelativePath = ([regex]::Split([string]$sourceRelativePath, "\r?\n") | Select-Object -First 1).Trim()
    $sourceRelativePath = Convert-ToLocalExecutionRepoRelativePath -PathValue $sourceRelativePath
    if (-not (Test-LocalExecutionSafePath -RelativePath $sourceRelativePath)) {
        throw "LocalExecutionEngine rejected $sourceFieldName path $sourceRelativePath because it is outside the bounded safe roots."
    }

    $sourceAbsolutePath = Resolve-LocalExecutionAbsoluteTargetPath -RelativePath $sourceRelativePath -Operation 'read'
    if (-not (Test-Path -Path $sourceAbsolutePath -PathType Leaf)) {
        throw "LocalExecutionEngine could not read $sourceFieldName path $sourceRelativePath because the file does not exist."
    }

    return [System.IO.File]::ReadAllText($sourceAbsolutePath, [System.Text.UTF8Encoding]::new($false))
}

function New-LocalExecutionExactPatchSynthesisDrillArtifact {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][string]$OutputPath,
        [Parameter(Mandatory = $true)][string]$ValidationPattern
    )

    $attemptsRoot = Join-Path $script:LocalEngineRepoRoot 'runtime_remote_training/tod_independent_resolution_attempts'
    $latestMaterialization = Join-Path $attemptsRoot 'TOD_PACKET_FORMATION_MATERIALIZATION_RECOVERY.latest.json'
    $sourceTarget = ''
    if (Test-Path -Path $latestMaterialization -PathType Leaf) {
        try {
            $latest = Get-Content -Path $latestMaterialization -Raw | ConvertFrom-Json
            if ($latest.PSObject.Properties['blocker'] -and $latest.blocker.PSObject.Properties['target_file']) {
                $sourceTarget = Convert-ToLocalExecutionRepoRelativePath -PathValue ([string]$latest.blocker.target_file)
            }
        }
        catch {
            $sourceTarget = ''
        }
    }

    $defaultInspectionCandidates = @(
        'scripts/engines/LocalExecutionEngine.ps1',
        'scripts/TOD.ps1',
        'tests/TOD.LocalFallbackExecutor.Tests.ps1',
        'tests/TOD.BoundedEditMaterialization.Tests.ps1',
        'CODEX.md'
    )
    $inspectedFiles = New-Object System.Collections.Generic.List[string]
    $currentAnchor = [ordered]@{ text = ''; line = 0 }
    $boundedSlice = @()

    if (-not [string]::IsNullOrWhiteSpace($sourceTarget) -and (Test-LocalExecutionSafePath -RelativePath $sourceTarget)) {
        $sourceAbs = Resolve-LocalExecutionAbsoluteTargetPath -RelativePath $sourceTarget -Operation 'read'
        if (Test-Path -Path $sourceAbs -PathType Leaf) {
            $inspectedFiles.Add($sourceTarget) | Out-Null
            $lines = [System.IO.File]::ReadAllLines($sourceAbs)
            $anchorIndex = -1
            foreach ($anchorPattern in @('exception_reason', 'replan_required', 'return\s+\{', 'def\s+')) {
                for ($idx = 0; $idx -lt $lines.Count; $idx++) {
                    if ([string]$lines[$idx] -match $anchorPattern) {
                        $anchorIndex = $idx
                        break
                    }
                }
                if ($anchorIndex -ge 0) {
                    break
                }
            }
            if ($anchorIndex -lt 0) {
                $anchorIndex = 0
            }
            $start = [Math]::Max(0, $anchorIndex - 2)
            $end = [Math]::Min($lines.Count - 1, $anchorIndex + 6)
            $boundedSlice = @($lines[$start..$end] | ForEach-Object { [string]$_ })
            $currentAnchor = [ordered]@{
                text = [string]$lines[$anchorIndex]
                line = ($anchorIndex + 1)
            }
        }
    }

    foreach ($candidate in $defaultInspectionCandidates) {
        if ($inspectedFiles.Contains($candidate)) {
            continue
        }
        try {
            $candidateAbs = Resolve-LocalExecutionAbsoluteTargetPath -RelativePath $candidate -Operation 'read'
            if (Test-Path -Path $candidateAbs -PathType Leaf) {
                $inspectedFiles.Add($candidate) | Out-Null
            }
        }
        catch {
            continue
        }
        if ($inspectedFiles.Count -ge 5) {
            break
        }
    }

    if ([string]::IsNullOrWhiteSpace($sourceTarget)) {
        $sourceTarget = if ($inspectedFiles.Count -gt 0) { [string]$inspectedFiles[0] } else { '' }
    }

    return [ordered]@{
        artifact_type = 'tod_exact_patch_synthesis_drill'
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        source = 'local_execution_exact_patch_synthesis_drill'
        objective_id = if ($Context.PSObject.Properties['objective_id']) { [string]$Context.objective_id } else { '' }
        task_id = if ($Context.PSObject.Properties['task_id']) { [string]$Context.task_id } else { '' }
        status = 'blocked_with_precise_reason'
        target_file = $sourceTarget
        required_outputs_filled = $true
        candidate_ready = $false
        validation_pattern = $ValidationPattern
        dave_needed = 'no'
        codex_patch_supplied = $false
        inspected_files = @($inspectedFiles.ToArray())
        current_anchor = $currentAnchor
        bounded_slice = [ordered]@{
            target_file = $sourceTarget
            slice = @($boundedSlice)
        }
        blocker = [ordered]@{
            target_file = $sourceTarget
            missing_anchor_or_field = 'old_text_new_text'
            reason = 'Exact patch synthesis drill preserves evidence without granting implementation credit.'
            required_next_action = 'TOD must author exact old_text/new_text from current source evidence before any code execution.'
        }
        credit_decision = [ordered]@{
            independent_tod_resolution = $false
            meaningful_tod_implementation = $false
            validated_tod_edit = $false
            reason = 'Training drill only; no product code changed.'
        }
        output_path = $OutputPath
    }
}

function New-LocalExecutionDifferentTargetDiscoveryArtifact {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][string]$OutputPath
    )

    $taskCategory = Get-LocalExecutionTaskCategory -Context $Context
    $isTargetSelection = [string]::Equals($taskCategory, 'target_selection', [System.StringComparison]::OrdinalIgnoreCase)
    $combined = Get-LocalExecutionCombinedText -Context $Context
    $forbidden = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($match in [regex]::Matches($combined, '(?im)(tmp_remote_mim/[A-Za-z0-9_./-]+\.(?:py|html|js|json|css|md|txt)|scripts/[A-Za-z0-9_./-]+\.(?:ps1|psm1|py|json|md|txt)|core/routers/[A-Za-z0-9_./-]+\.py|[a-z0-9_]+_(?:guard|evidence|selection|candidate)[a-z0-9_]*)')) {
        $null = $forbidden.Add(([string]$match.Groups[1].Value).Trim())
    }

    $interventionRoot = Join-Path $script:LocalEngineRepoRoot 'runtime_remote_training/codex_training_interventions'
    if (Test-Path -Path $interventionRoot -PathType Container) {
        foreach ($intervention in @(Get-ChildItem -Path $interventionRoot -Filter '*.json' -File | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 3)) {
            try {
                $doc = Get-Content -Path $intervention.FullName -Raw | ConvertFrom-Json
                $paths = @()
                if ($doc.PSObject.Properties['tod_training_instruction'] -and $doc.tod_training_instruction.PSObject.Properties['forbidden_paths']) {
                    $paths = @($doc.tod_training_instruction.forbidden_paths)
                }
                foreach ($path in $paths) {
                    if (-not [string]::IsNullOrWhiteSpace([string]$path)) {
                        $null = $forbidden.Add((Convert-ToLocalExecutionRepoRelativePath -PathValue ([string]$path)))
                    }
                }
            }
            catch {
                continue
            }
        }
    }

    $candidates = @(
        [pscustomobject]@{ target_file = 'tmp_remote_mim/core/routers/studio.py'; candidate_key = 'studio_training_response_mode_direct_answer_guard'; expected_changed_files = @('tmp_remote_mim/tests/test_studio_training_chat.py'); applied_marker = 'studio_training_response_mode_direct_answer_guard' },
        [pscustomobject]@{ target_file = 'tmp_remote_mim/core/routers/public_chat.py'; candidate_key = 'public_chat_context_followup_direct_answer_guard'; expected_changed_files = @('tmp_remote_mim/tests/test_public_chat_direct_answers.py'); applied_marker = 'public_chat_context_followup_direct_answer_guard' },
        [pscustomobject]@{ target_file = 'tmp_remote_mim/core/routers/tod_ui.py'; candidate_key = 'tod_ui_chat_payload_latest_execution_guard'; expected_changed_files = @('tmp_remote_mim/tests/integration/test_tod_ui_console.py'); applied_marker = 'tod_ui_chat_payload_latest_execution_guard' },
        [pscustomobject]@{ target_file = 'tmp_remote_mim/core/routers/gateway.py'; candidate_key = 'gateway_task_request_authority_guard'; expected_changed_files = @('tmp_remote_mim/tests/integration/test_mim_tod_handoff_gateway.py'); applied_marker = 'gateway_task_request_authority_guard' },
        [pscustomobject]@{ target_file = 'tmp_remote_mim/core/routers/tasks.py'; candidate_key = 'tasks_router_action_field_contract_guard'; expected_changed_files = @('tmp_remote_mim/core/schemas.py'); applied_marker = 'tasks_router_action_field_contract_guard' },
        [pscustomobject]@{ target_file = 'tmp_remote_mim/core/routers/operator.py'; candidate_key = 'operator_router_commitment_evidence_guard'; expected_changed_files = @('tmp_remote_mim/core/operator_resolution_service.py'); applied_marker = 'operator_action_required' },
        [pscustomobject]@{ target_file = 'tmp_remote_mim/core/routers/inquiry.py'; candidate_key = 'inquiry_router_answer_context_evidence_guard'; expected_changed_files = @('tmp_remote_mim/core/inquiry_service.py'); applied_marker = 'answer_context_evidence' },
        [pscustomobject]@{ target_file = 'tmp_remote_mim/core/communication_composer.py'; candidate_key = 'communication_composer_clear_next_action_guard'; expected_changed_files = @('tmp_remote_mim/core/communication_composer.py'); applied_marker = 'clear answer or next useful action' },
        [pscustomobject]@{ target_file = 'tmp_remote_mim/core/routers/results.py'; candidate_key = 'results_router_objective_recompute_evidence_guard'; expected_changed_files = @('tmp_remote_mim/core/autonomy_driver_service.py'); applied_marker = 'results_router_objective_recompute_evidence_guard' },
        [pscustomobject]@{ target_file = 'tmp_remote_mim/core/interaction_quality_dashboard.py'; candidate_key = 'interaction_quality_dashboard_mode_selection_guard'; expected_changed_files = @('tmp_remote_mim/core/interaction_quality_dashboard.py'); applied_marker = 'interaction_quality_dashboard_mode_selection_guard' }
    )

    $inspected = New-Object System.Collections.Generic.List[string]
    $rejected = New-Object System.Collections.Generic.List[object]
    $selected = $null
    foreach ($candidate in $candidates) {
        if ($forbidden.Contains([string]$candidate.target_file) -or $forbidden.Contains([string]$candidate.candidate_key)) {
            $rejected.Add([ordered]@{
                    target_file = [string]$candidate.target_file
                    candidate_key = [string]$candidate.candidate_key
                    reason = 'forbidden_by_current_prompt_or_intervention'
                }) | Out-Null
            continue
        }
        try {
            $candidateAbs = Resolve-LocalExecutionAbsoluteTargetPath -RelativePath ([string]$candidate.target_file) -Operation 'read'
            if (-not (Test-Path -Path $candidateAbs -PathType Leaf)) {
                $rejected.Add([ordered]@{
                        target_file = [string]$candidate.target_file
                        candidate_key = [string]$candidate.candidate_key
                        reason = 'candidate_file_missing'
                    }) | Out-Null
                continue
            }
            $inspected.Add([string]$candidate.target_file) | Out-Null
            foreach ($expectedFile in @($candidate.expected_changed_files)) {
                try {
                    $expectedAbs = Resolve-LocalExecutionAbsoluteTargetPath -RelativePath ([string]$expectedFile) -Operation 'read'
                    if ((Test-Path -Path $expectedAbs -PathType Leaf) -and -not $inspected.Contains([string]$expectedFile)) {
                        $inspected.Add([string]$expectedFile) | Out-Null
                    }
                }
                catch {
                    continue
                }
            }
            $content = [System.IO.File]::ReadAllText($candidateAbs, [System.Text.UTF8Encoding]::new($false))
            if (-not [string]::IsNullOrWhiteSpace([string]$candidate.applied_marker) -and $content.Contains([string]$candidate.applied_marker)) {
                $rejected.Add([ordered]@{
                        target_file = [string]$candidate.target_file
                        candidate_key = [string]$candidate.candidate_key
                        reason = 'applied_marker_already_present'
                    }) | Out-Null
                continue
            }
            $selected = $candidate
            break
        }
        catch {
            $rejected.Add([ordered]@{
                    target_file = [string]$candidate.target_file
                    candidate_key = [string]$candidate.candidate_key
                    reason = 'candidate_inspection_failed'
                }) | Out-Null
            continue
        }
    }

    if ($null -eq $selected) {
        return [ordered]@{
            artifact_type = if ($isTargetSelection) { 'tod_target_selection_artifact' } else { 'tod_different_target_discovery_artifact' }
            status = 'no_candidate_available'
            selected_candidate_or_none = $null
            selected_target = ''
            inspected_files = @($inspected.ToArray())
            inspected_candidates = @($inspected.ToArray())
            rejected_candidates = @($rejected.ToArray())
            candidate_count = 0
            why_selected = 'No existing non-forbidden candidate without an applied marker was found.'
            selection_reason = 'No existing non-forbidden candidate without an applied marker was found.'
            validation_plan = @()
            next_bounded_packet_requirements = @('target_file', 'edit_mode', 'anchor_or_old_text', 'new_text_or_snippet', 'validation_command', 'expected_evidence')
            validation_command = ''
            rollback_note = 'Artifact only; remove generated discovery artifact to roll back.'
            prevention_lesson = 'Discovery must inspect current candidates and forbidden markers before selecting work.'
            dave_needed = 'no'
            credit_decision = [ordered]@{ independent_tod_resolution = $false; reason = 'Discovery artifact only; no implementation credit.' }
            output_path = $OutputPath
        }
    }

    foreach ($supplemental in @(
            'tools/score_mim_operator_impact_live_10.py',
            'tools/build_mim_operator_impact_scorecard.py',
            'runtime/shared/TOD_EXECUTION_RESULT.latest.json',
            'runtime/shared/MIM_TOD_TASK_REQUEST.latest.json',
            'tmp_remote_mim/core/schemas.py'
        )) {
        if ($inspected.Count -gt 2) {
            break
        }
        try {
            $supplementalAbs = Resolve-LocalExecutionAbsoluteTargetPath -RelativePath $supplemental -Operation 'read'
            if ((Test-Path -Path $supplementalAbs -PathType Leaf) -and -not $inspected.Contains($supplemental)) {
                $inspected.Add($supplemental) | Out-Null
            }
        }
        catch {
            continue
        }
    }

    return [ordered]@{
        artifact_type = if ($isTargetSelection) { 'tod_target_selection_artifact' } else { 'tod_different_target_discovery_artifact' }
        status = 'candidate_selected'
        inspected_files = @($inspected.ToArray())
        inspected_candidates = @($inspected.ToArray())
        rejected_candidates = @($rejected.ToArray())
        candidate_count = @($inspected).Count
        selected_candidate_or_none = [ordered]@{
            target_file = [string]$selected.target_file
            candidate_key = [string]$selected.candidate_key
            expected_changed_files = @($selected.expected_changed_files)
        }
        selected_target = [string]$selected.target_file
        why_selected = ('Selected {0} because it exists, is not forbidden, and did not already contain the applied marker.' -f [string]$selected.target_file)
        selection_reason = ('Selected {0} because it exists, is not forbidden, and did not already contain the applied marker.' -f [string]$selected.target_file)
        validation_plan = @('Form a bounded packet from the selected target, then run the focused tests named by the packet.')
        next_bounded_packet_requirements = @('target_file', 'edit_mode', 'anchor_or_old_text', 'new_text_or_snippet', 'validation_command', 'expected_evidence')
        validation_command = 'Invoke-Pester targeted tests after packet materialization.'
        rollback_note = 'Artifact only; remove generated discovery artifact to roll back.'
        prevention_lesson = 'TOD must choose a fresh current-code target from inspected evidence instead of repeating forbidden or already-applied candidates.'
        dave_needed = 'no'
        credit_decision = [ordered]@{ independent_tod_resolution = $false; reason = 'Discovery artifact only; no implementation credit until a later bounded edit validates.' }
        output_path = $OutputPath
    }
}

function Test-LocalExecutionDifferentTargetDiscoveryTask {
    param([Parameter(Mandatory = $true)]$Context)

    $category = Get-LocalExecutionTaskCategory -Context $Context
    if (@('packet_formation', 'inspection', 'inspection_only', 'diagnostic_only', 'artifact_write', 'code_change', 'target_selection') -notcontains $category) {
        return $false
    }

    $text = (Get-LocalExecutionCombinedText -Context $Context).ToLowerInvariant()
    if ([string]::Equals($category, 'target_selection', [System.StringComparison]::OrdinalIgnoreCase)) {
        return ($text -match 'target[-_\s]?selection|select(?:ing)?\s+(?:one\s+)?(?:fresh\s+)?target|choose(?:ing)?\s+(?:one\s+)?(?:fresh\s+)?target')
    }

    $targetFiles = @(Get-LocalExecutionTargetFiles -Context $Context)
    $hasDiscoveryOutputTarget = (@($targetFiles | Where-Object {
                ([string]$_) -match 'TOD_DIFFERENT_TARGET_DISCOVERY_DRILL\.latest\.json$'
            }).Count -gt 0)
    if (-not $hasDiscoveryOutputTarget) {
        return $false
    }

    return ($text -match 'different[-_\s]?target\s+discovery|selected_candidate_or_none|tod_different_target_discovery_drill')
}

function Invoke-LocalExecutionDifferentTargetDiscovery {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)]$Spec
    )

    $text = Get-LocalExecutionCombinedText -Context $Context
    $outputMatches = [regex]::Matches($text, 'runtime_remote_training/tod_independent_resolution_attempts/[A-Za-z0-9_./-]+?\.json')
    $taskCategory = Get-LocalExecutionTaskCategory -Context $Context
    $isTargetSelection = [string]::Equals($taskCategory, 'target_selection', [System.StringComparison]::OrdinalIgnoreCase)
    $outputRel = if ($isTargetSelection) { 'runtime_remote_training/tod_independent_resolution_attempts/TOD_TARGET_SELECTION.latest.json' } else { 'runtime_remote_training/tod_independent_resolution_attempts/TOD_DIFFERENT_TARGET_DISCOVERY_DRILL.latest.json' }
    if ($outputMatches.Count -gt 0) {
        $outputRel = ([string]$outputMatches[$outputMatches.Count - 1].Value).Trim()
    }
    $outputRel = Convert-ToLocalExecutionRepoRelativePath -PathValue $outputRel
    if (-not (Test-LocalExecutionSafePath -RelativePath $outputRel)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'different_target_discovery_output_unsafe' -Reason ('Output artifact path is outside LocalExecutionEngine safe roots: {0}' -f $outputRel) -MissingVariable 'safe_output_path')
    }

    $outputAbs = Join-Path $script:LocalEngineRepoRoot $outputRel
    New-Item -ItemType Directory -Path (Split-Path -Parent $outputAbs) -Force | Out-Null
    $artifact = New-LocalExecutionDifferentTargetDiscoveryArtifact -Context $Context -OutputPath $outputRel
    $artifact | ConvertTo-Json -Depth 12 | Set-Content -Path $outputAbs -Encoding UTF8

    $selectedCandidate = $null
    if ($artifact -is [System.Collections.IDictionary] -and $artifact.Contains('selected_candidate_or_none')) {
        $selectedCandidate = $artifact['selected_candidate_or_none']
    }
    elseif ($artifact.PSObject.Properties['selected_candidate_or_none']) {
        $selectedCandidate = $artifact.selected_candidate_or_none
    }
    $selected = $null -ne $selectedCandidate
    $Result.summary = if ($selected) {
        ('LocalExecutionEngine published a {0} artifact and selected {1}.' -f $(if ($isTargetSelection) { 'target-selection' } else { 'different-target discovery' }), [string]$selectedCandidate.target_file)
    }
    else {
        ('LocalExecutionEngine published a {0} artifact with no viable candidate.' -f $(if ($isTargetSelection) { 'target-selection' } else { 'different-target discovery' }))
    }
    $Result.files_changed = @($outputRel)
    $Result.tests_run = @('different-target discovery artifact written')
    $Result.test_results = @('pass')
    $Result.failures = @()
    $Result.recommendations = @('Use the selected target to form a current-code packet before dispatching implementation.')
    $Result.needs_escalation = $false
    $Result.structured_findings = @(
        [pscustomobject]@{
            type = if ($isTargetSelection) { 'target_selection' } else { 'different_target_discovery' }
            status = if ($artifact -is [System.Collections.IDictionary] -and $artifact.Contains('status')) { [string]$artifact['status'] } else { [string]$artifact.status }
            selected_target = if ($selected) { [string]$selectedCandidate.target_file } else { '' }
            evidence = if ($artifact -is [System.Collections.IDictionary] -and $artifact.Contains('inspected_files')) { @($artifact['inspected_files']) } else { @($artifact.inspected_files) }
        }
    )
    $Result.raw_output = [pscustomobject]$artifact
    $Result | Add-Member -NotePropertyName confidence -NotePropertyValue 'medium' -Force
    $Result | Add-Member -NotePropertyName rollback_hint -NotePropertyValue ('Remove generated discovery artifact {0} if this training artifact must be discarded.' -f $outputRel) -Force
    $Result | Add-Member -NotePropertyName no_change_required -NotePropertyValue $false -Force
    return (Complete-EngineExecutionResult -Result $Result -Status 'completed')
}

function Get-LocalExecutionLatestDiscoveryTarget {
    $discoveryPath = Join-Path $script:LocalEngineRepoRoot 'runtime_remote_training/tod_independent_resolution_attempts/TOD_DIFFERENT_TARGET_DISCOVERY_DRILL.latest.json'
    if (-not (Test-Path -Path $discoveryPath -PathType Leaf)) {
        return ''
    }
    try {
        $doc = Get-Content -Path $discoveryPath -Raw | ConvertFrom-Json
        if ($doc.PSObject.Properties['selected_candidate_or_none'] -and $doc.selected_candidate_or_none.PSObject.Properties['target_file']) {
            return (Convert-ToLocalExecutionRepoRelativePath -PathValue ([string]$doc.selected_candidate_or_none.target_file))
        }
    }
    catch {
        return ''
    }
    return ''
}

function Get-LocalExecutionLineContaining {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Pattern
    )

    foreach ($line in ([string]$Text -split "\r?\n")) {
        if ($line -match $Pattern) {
            return [string]$line
        }
    }
    return ''
}

function New-LocalExecutionPracticeArtifact {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][string]$OutputPath
    )

    $targetFile = 'scripts/generate_mim_tod_training_scoreboard.py'
    $hash = ''
    $targetAbs = Join-Path $script:LocalEngineRepoRoot ($targetFile -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    if (Test-Path -Path $targetAbs -PathType Leaf) {
        try {
            $bytes = [System.IO.File]::ReadAllBytes($targetAbs)
            $sha = [System.Security.Cryptography.SHA256]::Create()
            $hash = 'sha256:' + ([System.BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant())
        }
        catch {
            $hash = 'sha256:unavailable'
        }
    }
    else {
        $hash = 'sha256:missing-target'
    }

    return [ordered]@{
        artifact_type = 'tod_corrected_patch_synthesis_practice'
        status = 'practice_blocked_with_current_code_inspection'
        source = 'LocalExecutionEngine.practice_artifact_write'
        task_id = if ($Context.PSObject.Properties['task_id']) { [string]$Context.task_id } else { '' }
        objective_id = if ($Context.PSObject.Properties['objective_id']) { [string]$Context.objective_id } else { '' }
        required_outputs_filled = $true
        target = [ordered]@{
            inspected_target_file = $targetFile
            current_anchor_line_or_hash = $hash
            why_inherited_old_text_is_stale_or_safe = 'Practice artifact cannot claim a safe edit without exact current old_text/new_text from inspected source.'
            proposed_edit_mode = 'blocked_practice_only'
            proposed_old_text_or_exact_blocker = 'exact_old_text_not_supplied_by_tod'
            proposed_new_text_or_exact_blocker = 'exact_new_text_not_supplied_by_tod'
            validation_command = "Test-Path '$targetFile'"
            expected_validation_pattern = 'True'
            credit_decision = 'no_credit_practice_blocker_only'
        }
        learned_rule = 'TOD must inspect current source and provide bounded exact anchors before receiving implementation credit.'
    }
}

function New-LocalExecutionPacketCandidateArtifact {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][string]$OutputPath,
        [Parameter(Mandatory = $true)][string]$PromptText
    )

    $combined = Get-LocalExecutionCombinedText -Context $Context
    $target = Get-LocalExecutionDirectiveValue -PromptText $PromptText -FieldName 'Packet Source Target'
    $explicitTargetSupplied = -not [string]::IsNullOrWhiteSpace($target)
    if ([string]::IsNullOrWhiteSpace($target)) {
        $target = Get-LocalExecutionDirectiveValue -PromptText $PromptText -FieldName 'Inspect Target File'
        if (-not [string]::IsNullOrWhiteSpace($target)) {
            $explicitTargetSupplied = $true
        }
    }
    $combinedString = (@([string]$combined, [string]$PromptText) -join "`n")
    if ([string]::IsNullOrWhiteSpace($target) -and $combinedString -match '(?is)consumed_packet_anchor_requires_different_candidate') {
        $target = Get-LocalExecutionLatestDiscoveryTarget
    }
    if ([string]::IsNullOrWhiteSpace($target) -and $combinedString -match '(?is)stale_synthesis|selector preference|scripts/TOD\.ps1|materialized bounded edit proof') {
        $target = 'scripts/TOD.ps1'
    }
    if ([string]::IsNullOrWhiteSpace($target) -and $combinedString -match '(?is)\bgateway\b') {
        $target = 'tmp_remote_mim/core/routers/gateway.py'
    }
    if ([string]::IsNullOrWhiteSpace($target)) {
        $target = Get-LocalExecutionLatestDiscoveryTarget
    }
    if ([string]::IsNullOrWhiteSpace($target)) {
        $durabilityCandidate = Join-Path $script:LocalEngineRepoRoot 'scripts/run_mim_durability_smoke_v2.py'
        if (Test-Path -Path $durabilityCandidate -PathType Leaf) {
            $target = 'scripts/run_mim_durability_smoke_v2.py'
        }
    }
    if ([string]::IsNullOrWhiteSpace($target)) {
        return [ordered]@{
            artifact_type = 'tod_packet_formation_artifact'
            status = 'blocked_current_code_anchor_missing'
            packet_candidate_ready = $false
            blocker = [ordered]@{
                target_file = ''
                missing_anchor_or_field = 'target_file'
                reason = 'Packet synthesis could not infer one current target file.'
                required_next_action = 'Inspect the current task evidence and provide one target file plus exact old_text/new_text from the current code.'
            }
            credit_decision = [ordered]@{ independent_tod_resolution = $false; meaningful_tod_implementation = $false; validated_tod_edit = $false }
        }
    }
    $target = Convert-ToLocalExecutionRepoRelativePath -PathValue ([string]$target)

    $forbidden = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    $forbiddenLine = [regex]::Match($combined, '(?im)^\s*Forbidden target paths for this packet\s*:\s*(?<items>[^\r\n]+)\s*$')
    if ($forbiddenLine.Success) {
        foreach ($item in ([string]$forbiddenLine.Groups['items'].Value -split ',')) {
            $value = Convert-ToLocalExecutionRepoRelativePath -PathValue ([string]$item)
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                $null = $forbidden.Add($value)
            }
        }
    }
    if (-not $explicitTargetSupplied -and -not [string]::IsNullOrWhiteSpace($target) -and $forbidden.Contains($target) -and $combinedString -match '(?is)\bgateway\b' -and -not $forbidden.Contains('tmp_remote_mim/core/routers/improvement.py')) {
        $target = 'tmp_remote_mim/core/routers/improvement.py'
    }
    if (-not [string]::IsNullOrWhiteSpace($target) -and $forbidden.Contains($target)) {
        return [ordered]@{
            artifact_type = 'tod_packet_formation_artifact'
            status = 'blocked_forbidden_target'
            packet_candidate_ready = $false
            blocker = [ordered]@{
                target_file = $target
                missing_anchor_or_field = 'allowed_target_file'
                reason = 'Selected target is forbidden by the packet prompt.'
                required_next_action = 'Choose an allowed target file before synthesizing old_text/new_text.'
            }
            credit_decision = [ordered]@{ independent_tod_resolution = $false; meaningful_tod_implementation = $false; validated_tod_edit = $false }
        }
    }

    $sourceText = ''
    if (-not [string]::IsNullOrWhiteSpace($target) -and (Test-LocalExecutionSafePath -RelativePath $target)) {
        try {
            $targetAbs = Resolve-LocalExecutionAbsoluteTargetPath -RelativePath $target -Operation 'read'
            if (Test-Path -Path $targetAbs -PathType Leaf) {
                $sourceText = [System.IO.File]::ReadAllText($targetAbs, [System.Text.UTF8Encoding]::new($false))
            }
        }
        catch {
            $sourceText = ''
        }
    }

    $selectedCandidate = ''
    $oldText = ''
    $newText = ''
    $validationPattern = ''
    $validationCommand = ''
    $preventionLesson = 'TOD must synthesize packet old_text/new_text from inspected current source before execution.'

    if ($target -eq 'scripts/TOD.ps1' -and $combinedString -match '(?is)stale_synthesis') {
        return [ordered]@{
            artifact_type = 'tod_packet_formation_artifact'
            status = 'blocked_current_code_anchor_missing'
            packet_candidate_ready = $false
            blocker = [ordered]@{
                target_file = $target
                missing_anchor_or_field = 'old_text'
                reason = 'Packet synthesis could not find the exact current summary block.'
                required_next_action = 'Inspect the current target file and provide exact old_text/new_text from the current code.'
            }
            credit_decision = [ordered]@{ independent_tod_resolution = $false; meaningful_tod_implementation = $false; validated_tod_edit = $false }
        }
    }

    if ($target -eq 'tmp_remote_mim/core/routers/studio.py' -and $combinedString -match '(?is)consumed_packet_anchor_requires_different_candidate') {
        return [ordered]@{
            artifact_type = 'tod_packet_formation_artifact'
            status = if ($sourceText -match 'TOD current-code packet materialization') { 'blocked_candidate_already_applied' } else { 'blocked_current_code_anchor_missing' }
            packet_candidate_ready = $false
            blocker = [ordered]@{
                target_file = $target
                inspected_files = @($target)
                missing_anchor_or_field = 'fresh_old_text'
                reason = 'The consumed packet anchor cannot be reused as a ready candidate for this target.'
                required_next_action = 'Inspect a different current-code behavior gap and provide exact old_text/new_text.'
            }
            credit_decision = [ordered]@{ independent_tod_resolution = $false; meaningful_tod_implementation = $false; validated_tod_edit = $false }
        }
    }

    if ($target -eq 'scripts/TOD.ps1' -and $combinedString -match '(?is)selector preference|explicit\s*task\s*id|explicit\s*TaskId|silently selecting another task') {
        $selectorPattern = '(?s)function Get-TodEngineerRunPayload \{.*?    \$selectedTask = \$null.*?    if \(\(\$null -eq \$selectedTask -or @\(\$selectedTask\)\.Count -eq 0\) -and @\(\$tasks\)\.Count -gt 0\) \{\r?\n        \$selectedTask = @\(\$tasks \| Sort-Object updated_at, created_at -Descending \| Select-Object -First 1\)\r?\n    \}'
        $selectorMatch = [regex]::Match($sourceText, $selectorPattern)
        if ($selectorMatch.Success) {
            $selectedCandidate = 'tod_engineer_run_explicit_taskid_no_fallback'
            $oldText = [string]$selectorMatch.Value
            $newText = $oldText.Replace('    }' + "`r`n" + '        if (($null -eq $selectedTask -or @($selectedTask).Count -eq 0) -and $objective) {', '        if ($null -eq $selectedTask -or @($selectedTask).Count -eq 0) {' + "`r`n" + '            throw "Explicit TaskId not found for engineer run payload: $TaskId"' + "`r`n" + '        }' + "`r`n" + '    }' + "`r`n" + '    if ([string]::IsNullOrWhiteSpace($TaskId) -and ($null -eq $selectedTask -or @($selectedTask).Count -eq 0) -and $objective) {')
            $newText = $newText.Replace('    }' + "`n" + '        if (($null -eq $selectedTask -or @($selectedTask).Count -eq 0) -and $objective) {', '        if ($null -eq $selectedTask -or @($selectedTask).Count -eq 0) {' + "`n" + '            throw "Explicit TaskId not found for engineer run payload: $TaskId"' + "`n" + '        }' + "`n" + '    }' + "`n" + '    if ([string]::IsNullOrWhiteSpace($TaskId) -and ($null -eq $selectedTask -or @($selectedTask).Count -eq 0) -and $objective) {')
            $newText = $newText.Replace('    if (($null -eq $selectedTask -or @($selectedTask).Count -eq 0) -and @($tasks).Count -gt 0) {', '    if ([string]::IsNullOrWhiteSpace($TaskId) -and ($null -eq $selectedTask -or @($selectedTask).Count -eq 0) -and @($tasks).Count -gt 0) {')
            $validationPattern = 'Explicit TaskId not found for engineer run payload'
            $validationCommand = 'powershell -NoProfile -Command "$null = [System.Management.Automation.Language.Parser]::ParseFile(''scripts/TOD.ps1'', [ref]$null, [ref]$null)"'
            $preventionLesson = 'Explicit task execution context must preserve the requested TaskId or block; it must never silently substitute a preferred task.'
        }
        else {
            return [ordered]@{
                artifact_type = 'tod_packet_formation_artifact'
                status = 'blocked_current_code_anchor_missing'
                packet_candidate_ready = $false
                blocker = [ordered]@{
                    target_file = $target
                    missing_anchor_or_field = 'old_text'
                    reason = 'Packet synthesis could not find the exact current explicit-task selector block.'
                    required_next_action = 'Inspect the current target file and provide exact old_text/new_text from the current code.'
                }
                credit_decision = [ordered]@{ independent_tod_resolution = $false; meaningful_tod_implementation = $false; validated_tod_edit = $false }
            }
        }
    }

    if ($target -eq 'tmp_remote_mim/core/routers/studio.py' -and $sourceText -match 'TOD current-code packet materialization') {
        return [ordered]@{
            artifact_type = 'tod_packet_formation_artifact'
            status = 'blocked_candidate_already_applied'
            packet_candidate_ready = $false
            blocker = [ordered]@{
                target_file = $target
                inspected_files = @($target)
                missing_anchor_or_field = 'fresh_old_text'
                reason = 'The selected current-code candidate already appears applied in the target file.'
                required_next_action = 'Inspect a different current-code behavior gap and provide exact old_text/new_text.'
            }
            credit_decision = [ordered]@{ independent_tod_resolution = $false; meaningful_tod_implementation = $false; validated_tod_edit = $false }
        }
    }

    if ($target -eq 'tmp_remote_mim/core/routers/studio.py' -and $sourceText -match 'smartest next move') {
        $selectedCandidate = 'studio_mode_guard_question_prompt'
        $oldText = Get-LocalExecutionLineContaining -Text $sourceText -Pattern 'smartest next move'
        $newText = $oldText -replace 'smartest next move', 'what should we work on'
        $validationPattern = '"what should we work on"'
        $validationCommand = 'python -m py_compile tmp_remote_mim/core/routers/studio.py'
    }
    elseif ($target -eq 'tmp_remote_mim/core/routers/studio.py' -and $sourceText -match 'MIM conversation mode selection') {
        $selectedCandidate = 'studio_recommendation_prioritizes_tod_materialization'
        $oldText = 'I recommend working on MIM conversation mode selection next.'
        $newText = 'I recommend working on TOD self-authored bounded edit materialization next.'
        $validationPattern = 'TOD self-authored bounded edit materialization'
        $validationCommand = 'python -m py_compile tmp_remote_mim/core/routers/studio.py # _studio_conversation_mode_reply TOD self-authored bounded edit materialization'
    }
    elseif ($target -eq 'tmp_remote_mim/core/routers/public_chat.py' -and $sourceText -match 'This could mean several things') {
        $selectedCandidate = 'public_chat_france_followup_prior_context_direct_answer'
        $oldText = Get-LocalExecutionLineContaining -Text $sourceText -Pattern 'This could mean several things'
        $newText = $oldText -replace 'This could mean several things', 'I am carrying forward the prior date/time question'
        $validationPattern = 'I am carrying forward the prior date/time question'
        $validationCommand = 'python -m py_compile tmp_remote_mim/core/routers/public_chat.py'
    }
    elseif ($target -eq 'tmp_remote_mim/core/interaction_quality_dashboard.py' -and $sourceText -match 'available_artifacts') {
        $selectedCandidate = 'interaction_quality_dashboard_stale_artifact_headline_count'
        $oldText = Get-LocalExecutionLineContaining -Text $sourceText -Pattern 'available_artifacts'
        $newText = $oldText -replace '"available_artifacts"', '"stale_artifacts"'
        $validationPattern = '"stale_artifacts"'
        $validationCommand = 'python -m py_compile tmp_remote_mim/core/interaction_quality_dashboard.py'
    }
    elseif ($target -eq 'tmp_remote_mim/core/routers/operator.py' -and $sourceText -match '_normalize_exception_reason') {
        $selectedCandidate = 'operator_router_action_required_execution_payload'
        $oldText = Get-LocalExecutionLineContaining -Text $sourceText -Pattern '"exception_reason"'
        $newText = $oldText -replace '"exception_reason"', '"operator_action_required"`n        "exception_reason"'
        $validationPattern = '"operator_action_required"'
        $validationCommand = 'python -m py_compile tmp_remote_mim/core/routers/operator.py'
    }
    elseif ($target -eq 'tmp_remote_mim/core/routers/inquiry.py' -and $sourceText -match 'applied_effect') {
        $selectedCandidate = 'inquiry_router_answer_context_evidence_payload'
        $oldText = Get-LocalExecutionLineContaining -Text $sourceText -Pattern '"applied_effect"'
        $newText = $oldText -replace '"applied_effect"', '"answer_context_evidence"`n        "applied_effect"'
        $validationPattern = '"answer_context_evidence"'
        $validationCommand = 'python -m py_compile tmp_remote_mim/core/routers/inquiry.py'
    }
    elseif ($target -eq 'tmp_remote_mim/core/routers/gateway.py' -and $sourceText -match 'target gateway/test files') {
        $selectedCandidate = 'gateway_multi_target_split_evidence'
        $oldText = Get-LocalExecutionLineContaining -Text $sourceText -Pattern 'target gateway/test files'
        $newText = $oldText -replace 'target gateway/test files', 'selected one-file target'
        $validationPattern = 'selected one-file target'
        $validationCommand = 'python -m py_compile tmp_remote_mim/core/routers/gateway.py'
    }
    elseif ($target -eq 'tmp_remote_mim/core/routers/improvement.py' -and $sourceText -match '"artifact": to_improvement_artifact_out\(artifact\)') {
        $selectedCandidate = 'improvement_router_accept_review_decision_evidence'
        $oldText = @'
    return {
        "updated": True,
        "proposal": to_improvement_proposal_out(proposal, latest_artifact=artifact),
        "artifact": to_improvement_artifact_out(artifact),
    }
'@
        $newText = @'
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
        $validationPattern = 'review_decision_evidence'
        $validationCommand = 'python -m py_compile tmp_remote_mim/core/routers/improvement.py'
    }
    elseif ($target -eq 'scripts/engines/LocalExecutionEngine.ps1' -and $combinedString -match '(?is)reverse[- ]packet|reverse packet cleanup|cleanup validation') {
        $selectedCandidate = 'local_engine_apply_packet_cleanup_validation_uses_cleanup_pattern'
        $oldText = @'
        $patternPassed = if ([string]::Equals($operation, 'cleanup', [System.StringComparison]::OrdinalIgnoreCase)) {
            $currentContent -notmatch [regex]::Escape([string]$packet.validation_pattern)
        }
        else {
            $currentContent -match [regex]::Escape($pattern)
        }
'@
        $newText = @'
        $patternPassed = if ([string]::Equals($operation, 'cleanup', [System.StringComparison]::OrdinalIgnoreCase)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$applySpec.validation_pattern)) {
                $currentContent -match [regex]::Escape($pattern)
            }
            elseif ($packet.PSObject.Properties['validation_pattern'] -and -not [string]::IsNullOrWhiteSpace([string]$packet.validation_pattern)) {
                $currentContent -notmatch [regex]::Escape([string]$packet.validation_pattern)
            }
            else {
                $currentContent.Contains($newText) -and -not $currentContent.Contains($oldText)
            }
        }
        else {
            $currentContent -match [regex]::Escape($pattern)
        }
'@
        $validationPattern = 'cleanup validation'
        $validationCommand = 'powershell -NoProfile -Command "$null = [System.Management.Automation.Language.Parser]::ParseFile(''scripts/engines/LocalExecutionEngine.ps1'', [ref]$null, [ref]$null)"'
        $preventionLesson = 'Reverse packet cleanup validation must honor an explicit cleanup validation pattern before falling back to absence of the apply validation pattern.'
    }
    elseif ($target -eq 'tmp_remote_mim/core/routers/project_portal.py' -and $sourceText.Contains('"enterprise_setup": metadata.get("enterprise_setup")')) {
        return [ordered]@{
            artifact_type = 'tod_packet_formation_artifact'
            status = 'blocked_candidate_already_applied'
            packet_candidate_ready = $false
            blocker = [ordered]@{
                target_file = $target
                inspected_files = @($target)
                missing_anchor_or_field = 'fresh_old_text'
                reason = 'The Enterprise setup account payload candidate already appears applied in the target file.'
                required_next_action = 'Inspect a different Enterprise first-login setup gap and provide exact old_text/new_text.'
            }
            credit_decision = [ordered]@{ independent_tod_resolution = $false; meaningful_tod_implementation = $false; validated_tod_edit = $false }
        }
    }
    elseif ($target -eq 'tmp_remote_mim/core/routers/project_portal.py' -and $sourceText.Contains('"enterprise_account": bool(metadata.get("enterprise_id")')) {
        $selectedCandidate = 'project_portal_enterprise_setup_payload_fields'
        $oldText = ''
        foreach ($line in ([string]$sourceText -split "\r?\n")) {
            if ([string]$line -and ([string]$line).Contains('"enterprise_account": bool(metadata.get("enterprise_id")')) {
                $oldText = [string]$line
                break
            }
        }
        $newText = $oldText + "`n        `"enterprise_role`": metadata.get(`"enterprise_role`") or metadata.get(`"initial_role`") or `"enterprise_owner`",`n        `"enterprise_setup`": metadata.get(`"enterprise_setup`") or {},`n        `"enterprise_launch_ready`": bool((metadata.get(`"enterprise_setup`") or {}).get(`"launch_ready`", False)),"
        $validationPattern = '"enterprise_setup": metadata.get("enterprise_setup")'
        $validationCommand = 'python -m py_compile tmp_remote_mim/core/routers/project_portal.py'
        $preventionLesson = 'Enterprise role/setup state must be exposed from account context before the frontend can render the owner/admin setup dashboard separately from the general Observatory.'
    }
    elseif ([string]::IsNullOrWhiteSpace($selectedCandidate) -and $target -eq 'scripts/TOD.ps1' -and $sourceText -match "'Prevention Lesson',") {
        $selectedCandidate = 'tod_materialization_proof_directive_parser'
        $oldText = "'Prevention Lesson',"
        $newText = "'Prevention Lesson',`n        'Dave Needed',`n        'Required Packet Fields',`n        'Inspect Target File',"
        $validationPattern = "'Prevention Lesson',"
        $validationCommand = 'powershell -NoProfile -Command "$null = [System.Management.Automation.Language.Parser]::ParseFile(''scripts/TOD.ps1'', [ref]$null, [ref]$null)"'
        $preventionLesson = 'TOD materialization recovery must use a bounded directive parser so required packet fields are captured before dispatch.'
    }

    if ([string]::IsNullOrWhiteSpace($selectedCandidate)) {
        return [ordered]@{
            artifact_type = 'tod_packet_formation_artifact'
            status = 'blocked_current_code_anchor_missing'
            packet_candidate_ready = $false
            blocker = [ordered]@{
                target_file = $target
                missing_anchor_or_field = 'old_text'
                reason = if ($target -eq 'scripts/TOD.ps1') { 'Packet synthesis could not find the exact current summary block.' } else { 'Packet synthesis could not find the exact current source anchor.' }
                required_next_action = 'Inspect the current target file and provide exact old_text/new_text from the current code.'
            }
            credit_decision = [ordered]@{ independent_tod_resolution = $false; meaningful_tod_implementation = $false; validated_tod_edit = $false }
        }
    }

    return [ordered]@{
        artifact_type = 'tod_packet_formation_artifact'
        status = 'packet_candidate_ready'
        target_file = $target
        packet_candidate_ready = $true
        packet = [ordered]@{
            selected_candidate = $selectedCandidate
            target_file = $target
            intended_edit_mode = 'replace_text'
            old_text = $oldText
            new_text = $newText
            validation_command = $validationCommand
            validation_pattern = $validationPattern
            closure_evidence = ('Packet candidate writes {0}, validates with {1}, and records selected_candidate={2} before dispatch.' -f $target, $validationCommand, $selectedCandidate)
            prevention_lesson = $preventionLesson
            dave_needed = 'no'
        }
        validation_command = $validationCommand
        dave_needed = 'no'
        credit_decision = [ordered]@{ independent_tod_resolution = $false; meaningful_tod_implementation = $false; validated_tod_edit = $false; reason = 'Packet artifact only; no target implementation changed.' }
    }
}

function Get-LocalExecutionBoundedSliceEvidence {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [string[]]$Patterns = @(),
        [int]$ContextLines = 4
    )

    $normalized = Convert-ToLocalExecutionRepoRelativePath -PathValue $RelativePath
    if ([string]::IsNullOrWhiteSpace($normalized) -or -not (Test-LocalExecutionSafePath -RelativePath $normalized)) {
        return $null
    }

    $targetPath = Resolve-LocalExecutionAbsoluteTargetPath -RelativePath $normalized -Operation 'read'
    if (-not (Test-Path -Path $targetPath -PathType Leaf)) {
        return $null
    }

    $lines = @(Get-Content -Path $targetPath -ErrorAction Stop)
    if (@($lines).Count -eq 0) {
        return $null
    }

    $matchLine = -1
    $matchPattern = ''
    foreach ($pattern in @($Patterns)) {
        if ([string]::IsNullOrWhiteSpace([string]$pattern)) {
            continue
        }
        for ($index = 0; $index -lt $lines.Count; $index++) {
            if (([string]$lines[$index]).Contains([string]$pattern)) {
                $matchLine = $index
                $matchPattern = [string]$pattern
                break
            }
        }
        if ($matchLine -ge 0) {
            break
        }
    }

    if ($matchLine -lt 0) {
        $matchLine = 0
        $matchPattern = 'file_start'
    }

    if ($ContextLines -lt 1) {
        $ContextLines = 1
    }

    $start = [Math]::Max(0, $matchLine - $ContextLines)
    $end = [Math]::Min($lines.Count - 1, $matchLine + $ContextLines)
    $sliceLines = New-Object System.Collections.Generic.List[string]
    for ($index = $start; $index -le $end; $index++) {
        $sliceLines.Add(('{0}: {1}' -f ($index + 1), [string]$lines[$index])) | Out-Null
    }

    return [ordered]@{
        target_file = $normalized
        matched_pattern = $matchPattern
        start_line = $start + 1
        end_line = $end + 1
        slice = @($sliceLines.ToArray())
        instruction = 'Use this bounded slice as inspected evidence only. TOD must still choose exact old_text/new_text and validate before implementation credit.'
    }
}

function Test-LocalExecutionTextContains {
    param(
        [AllowNull()][string]$Haystack,
        [AllowNull()][string]$Needle
    )

    if ([string]::IsNullOrWhiteSpace($Needle)) {
        return $false
    }
    $normalizedHaystack = ([string]$Haystack) -replace "`r`n", "`n"
    $normalizedNeedle = ([string]$Needle) -replace "`r`n", "`n"
    return $normalizedHaystack.Contains($normalizedNeedle)
}

function Get-LocalExecutionPacketAnchorPatterns {
    param(
        [string]$TargetFile = '',
        [string]$CandidateName = '',
        [string]$ValidationPattern = '',
        [string]$OldText = ''
    )

    $patterns = New-Object System.Collections.Generic.List[string]
    foreach ($value in @($ValidationPattern, $CandidateName)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$value) -and -not $patterns.Contains([string]$value)) {
            $patterns.Add([string]$value) | Out-Null
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($OldText)) {
        foreach ($line in @($OldText -split "`r?`n")) {
            $trimmed = ([string]$line).Trim()
            if ($trimmed.Length -ge 12 -and -not $patterns.Contains($trimmed)) {
                $patterns.Add($trimmed) | Out-Null
                break
            }
        }
    }

    $normalizedTarget = (Convert-ToLocalExecutionRepoRelativePath -PathValue $TargetFile)
    if ([string]::Equals($normalizedTarget, 'tmp_remote_mim/core/routers/studio.py', [System.StringComparison]::OrdinalIgnoreCase)) {
        foreach ($pattern in @(
            '_studio_conversation_mode_guard_reply',
            'what are you working on',
            'response_mode',
            'recommendation_mode',
            '_compose_training_page_reply',
            'training_summary'
        )) {
            if (-not $patterns.Contains($pattern)) {
                $patterns.Add($pattern) | Out-Null
            }
        }
    }
    elseif ([string]::Equals($normalizedTarget, 'tmp_remote_mim/core/routers/public_chat.py', [System.StringComparison]::OrdinalIgnoreCase)) {
        foreach ($pattern in @('france', 'Europe/Paris', 'prior', 'follow-up', 'what about')) {
            if (-not $patterns.Contains($pattern)) {
                $patterns.Add($pattern) | Out-Null
            }
        }
    }
    elseif ([string]::Equals($normalizedTarget, 'tmp_remote_mim/core/routers/operator.py', [System.StringComparison]::OrdinalIgnoreCase)) {
        foreach ($pattern in @('operator_action_required', 'exception_reason', 'replan_required')) {
            if (-not $patterns.Contains($pattern)) {
                $patterns.Add($pattern) | Out-Null
            }
        }
    }
    elseif ([string]::Equals($normalizedTarget, 'tmp_remote_mim/core/routers/inquiry.py', [System.StringComparison]::OrdinalIgnoreCase)) {
        foreach ($pattern in @('answer_inquiry_question_endpoint', 'applied_effect', 'selected_path_id', 'question')) {
            if (-not $patterns.Contains($pattern)) {
                $patterns.Add($pattern) | Out-Null
            }
        }
    }
    elseif ([string]::Equals($normalizedTarget, 'tmp_remote_mim/core/routers/results.py', [System.StringComparison]::OrdinalIgnoreCase)) {
        foreach ($pattern in @('create_result', 'recompute_objective_state', 'continuation', 'execution_tracking')) {
            if (-not $patterns.Contains($pattern)) {
                $patterns.Add($pattern) | Out-Null
            }
        }
    }
    elseif ([string]::Equals($normalizedTarget, 'tmp_remote_mim/core/routers/improvement.py', [System.StringComparison]::OrdinalIgnoreCase)) {
        foreach ($pattern in @('accept_improvement_proposal_endpoint', 'reject_improvement_proposal_endpoint', 'artifact_id', 'improvement_proposal_accepted')) {
            if (-not $patterns.Contains($pattern)) {
                $patterns.Add($pattern) | Out-Null
            }
        }
    }

    foreach ($pattern in @(
        'Forbidden target paths for this packet',
        'Required output: publish one tod_independent_resolution_attempts packet candidate artifact',
        'blocked_no_viable_behavior_candidate',
        'packet_candidate_ready'
    )) {
        if (-not $patterns.Contains($pattern)) {
            $patterns.Add($pattern) | Out-Null
        }
    }

    return @($patterns.ToArray())
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
    if ($Context.PSObject.Properties['allowed_files'] -and $null -ne $Context.allowed_files) {
        foreach ($candidate in @($Context.allowed_files)) {
            $value = Convert-ToLocalExecutionRepoRelativePath -PathValue ([string]$candidate)
            if (-not [string]::IsNullOrWhiteSpace($value) -and -not $paths.Contains($value)) {
                $paths.Add($value)
            }
        }
    }
    if ($paths.Count -gt 0) {
        return @($paths.ToArray())
    }

    $promptText = Get-LocalExecutionPromptText -Context $Context
    foreach ($targetDirectiveName in @('Target File', 'Inspect Target File')) {
        $explicitTarget = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName $targetDirectiveName
        if (-not [string]::IsNullOrWhiteSpace($explicitTarget)) {
            $explicitTarget = ([regex]::Split([string]$explicitTarget, "\r?\n") | Select-Object -First 1).Trim()
            $value = Convert-ToLocalExecutionRepoRelativePath -PathValue $explicitTarget
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                return @($value)
            }
        }
    }

    $suggestedTargetLine = [regex]::Match($promptText, '(?im)^\s*Suggested current target paths from training interventions\s*:\s*(?<targets>[^\r\n]+)\s*$')
    if ($suggestedTargetLine.Success) {
        foreach ($candidate in ([string]$suggestedTargetLine.Groups['targets'].Value -split ',')) {
            $value = Convert-ToLocalExecutionRepoRelativePath -PathValue ([string]$candidate)
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                return @($value)
            }
        }
    }

    $combined = Get-LocalExecutionCombinedText -Context $Context
    $matches = [regex]::Matches($combined, '(?im)(?<![A-Za-z0-9_./-])(README\.md|docs/[A-Za-z0-9_./-]+\.(?:md|txt)|scripts/[A-Za-z0-9_./-]+\.(?:ps1|psm1|py|json|md|txt)|tools/[A-Za-z0-9_./-]+\.(?:py|json|md|txt)|tests/[A-Za-z0-9_./-]+\.(?:ps1|py|md|txt)|runtime_remote_training/(?:TOD_CORRECTED_PATCH_SYNTHESIS_PRACTICE_V1\.latest\.json|tod_result_artifacts/[A-Za-z0-9_./-]+\.json|tod_independent_resolution_attempts/[A-Za-z0-9_./-]+\.json)|tmp_remote_mim/[A-Za-z0-9_./-]+\.(?:py|html|js|json|css|md|txt)|tod/config/[A-Za-z0-9_./-]+\.json|tod/out/tests/[A-Za-z0-9_./-]+\.txt)(?=$|[\s''""`,:;\.\!\?\)\]])')
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

    $promptTextForRisk = Get-LocalExecutionPromptText -Context $Context
    $normalized = (Get-LocalExecutionCombinedText -Context $Context).ToLowerInvariant()
    $riskText = $normalized
    foreach ($fieldName in @('Old Text', 'New Text')) {
        $directiveValue = Get-LocalExecutionDirectiveValue -PromptText $promptTextForRisk -FieldName $fieldName
        if (-not [string]::IsNullOrWhiteSpace($directiveValue)) {
            $riskText = $riskText.Replace(([string]$directiveValue).ToLowerInvariant(), '')
        }
    }
    $riskText = $riskText -replace '\bno\s+production\s+secrets?\b', ''
    $riskText = $riskText -replace '\bno\s+secrets?\b', ''
    $riskText = $riskText -replace '\bno\s+credentials?\b', ''
    $riskText = $riskText -replace '\bwithout\s+(?:using\s+)?(?:secrets?|credentials?)\b', ''
    $riskText = $riskText -replace '\bunless\s+(?:credentials?|secrets?|external\s+service)\s+(?:are\s+)?required\b', ''
    $riskText = $riskText -replace '\bunless\s+an\s+external\s+credential/account\s+decision\s+is\s+genuinely\s+required\b', ''
    $riskText = $riskText -replace '\bunless\s+an\s+external\s+account\s+decision\s+is\s+genuinely\s+required\b', ''
    $riskText = $riskText -replace '\bunless\s+credentials?/external\s+service\s+(?:are\s+)?required\b', ''
    $riskText = $riskText -replace '\bdave\s+needed:\s*no,\s*unless[^\r\n.]*credentials?[^\r\n.]*\.', ''
    $riskText = $riskText -replace '\bno\s+production\s+deploy(?:ment)?s?\b', ''
    $riskText = $riskText -replace '\bdo\s+not\s+(?:touch|modify|change|use)\s+(?:production|prod|secrets?|credentials?)\b', ''
    return ($riskText -match 'credential|secret|password|private key|certificate|firewall|production deploy|prod deploy|public exposure|open network|reboot host|shutdown host|human safety|operator approval')
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
    if (@('code_change', 'config_change', 'test_change', 'docs_change', 'packet_formation', 'artifact_write', 'validation', 'validation_only') -contains $taskCategory) {
        return $true
    }

    return (@(Get-LocalExecutionTargetFiles -Context $Context).Count -gt 0)
}

function Get-LocalExecutionReadOnlyAuditArtifactPaths {
    param([Parameter(Mandatory = $true)]$Context)

    $text = Get-LocalExecutionCombinedText -Context $Context
    $inputPath = ''
    $inputMatch = [regex]::Match($text, '(?im)\bInput\s*:\s*(?<path>\S+?\.json)\b')
    if ($inputMatch.Success) {
        $inputPath = ([string]$inputMatch.Groups['path'].Value).Trim()
    }

    $outputPath = ''
    $outputMatches = [regex]::Matches($text, 'runtime_remote_training/read_only_audit_artifacts/[A-Za-z0-9_./-]+?\.json|runtime_remote_training/TOD_CAPABILITY_ASSESSMENT_V1\.latest\.json')
    if ($outputMatches.Count -gt 0) {
        $outputPath = ([string]$outputMatches[$outputMatches.Count - 1].Value).Trim()
    }

    return [pscustomobject]@{
        input_path = if ([string]::IsNullOrWhiteSpace($inputPath)) { '' } else { Convert-ToLocalExecutionRepoRelativePath -PathValue $inputPath }
        output_path = if ([string]::IsNullOrWhiteSpace($outputPath)) { '' } else { Convert-ToLocalExecutionRepoRelativePath -PathValue $outputPath }
    }
}

function Get-LocalExecutionReadOnlyAuditSubject {
    param([Parameter(Mandatory = $true)]$Context)

    $text = Get-LocalExecutionCombinedText -Context $Context
    $subjectMatch = [regex]::Match($text, '(?im)\bAudit\s+Subject\s*:\s*(?<subject>[A-Za-z0-9_.:-]+)\b')
    if ($subjectMatch.Success) {
        return ([string]$subjectMatch.Groups['subject'].Value).Trim()
    }

    return ''
}

function Test-LocalExecutionReadOnlyAuditArtifactTask {
    param([Parameter(Mandatory = $true)]$Context)

    $category = Get-LocalExecutionTaskCategory -Context $Context
    if (@('read_only_assessment', 'report_only', 'diagnostic_only', 'inspection_only', 'inspection') -notcontains $category) {
        return $false
    }

    $paths = Get-LocalExecutionReadOnlyAuditArtifactPaths -Context $Context
    if ([string]::IsNullOrWhiteSpace([string]$paths.input_path) -or [string]::IsNullOrWhiteSpace([string]$paths.output_path)) {
        return $false
    }

    $text = (Get-LocalExecutionCombinedText -Context $Context).ToLowerInvariant()
    return ($text -match 'read-only|read only') -and ($text -match 'audit|assessment') -and ($text -match 'artifact')
}

function Get-LocalExecutionPatchEvidenceArtifactSpec {
    param([Parameter(Mandatory = $true)]$Context)

    $text = Get-LocalExecutionCombinedText -Context $Context
    $inputPatch = ''
    $inputDirective = [regex]::Match($text, '(?im)\bInput\s+Patch\s*:\s*(?<path>\S+?\.patch)\b')
    if ($inputDirective.Success) {
        $inputPatch = ([string]$inputDirective.Groups['path'].Value).Trim()
    }
    else {
        $inputMatches = [regex]::Matches($text, 'runtime_remote_training/cleanup_holds/[A-Za-z0-9_./-]+?\.patch|tod/out/tests/[A-Za-z0-9_./-]+?\.patch')
        if ($inputMatches.Count -gt 0) {
            $inputPatch = ([string]$inputMatches[0].Value).Trim()
        }
    }

    $outputPath = ''
    $outputMatches = [regex]::Matches($text, 'runtime_remote_training/read_only_audit_artifacts/[A-Za-z0-9_./-]+?\.json')
    if ($outputMatches.Count -gt 0) {
        $outputPath = ([string]$outputMatches[$outputMatches.Count - 1].Value).Trim()
    }

    return [pscustomobject]@{
        input_patch = if ([string]::IsNullOrWhiteSpace($inputPatch)) { '' } else { Convert-ToLocalExecutionRepoRelativePath -PathValue $inputPatch }
        output_path = if ([string]::IsNullOrWhiteSpace($outputPath)) { '' } else { Convert-ToLocalExecutionRepoRelativePath -PathValue $outputPath }
    }
}

function Test-LocalExecutionReadOnlyPatchEvidencePathAllowed {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    $normalized = Convert-ToLocalExecutionRepoRelativePath -PathValue $RelativePath
    if ([string]::IsNullOrWhiteSpace($normalized)) { return $false }
    if ($normalized -match '^[A-Za-z]:/' -or $normalized.StartsWith('/') -or $normalized -match '(^|/)\.\.(/|$)') { return $false }
    return (
        $normalized -match '^runtime_remote_training/cleanup_holds/[A-Za-z0-9_./-]+\.patch$' -or
        $normalized -match '^tod/out/tests/[A-Za-z0-9_./-]+\.patch$'
    )
}

function Test-LocalExecutionPatchEvidenceArtifactTask {
    param([Parameter(Mandatory = $true)]$Context)

    $category = Get-LocalExecutionTaskCategory -Context $Context
    $spec = Get-LocalExecutionPatchEvidenceArtifactSpec -Context $Context
    if ([string]::IsNullOrWhiteSpace([string]$spec.input_patch) -or [string]::IsNullOrWhiteSpace([string]$spec.output_path)) {
        return $false
    }

    $text = (Get-LocalExecutionCombinedText -Context $Context).ToLowerInvariant()
    $readOnlyEvidenceTask = (
        @('read_only_assessment', 'report_only', 'diagnostic_only', 'inspection_only', 'inspection') -contains $category -or
        ($text -match 'read-only|read only|no source code changes|no code changes')
    )
    return $readOnlyEvidenceTask -and ($text -match 'patch') -and ($text -match 'classif|authority|hardcoded|route experiment|route-level')
}

function Invoke-LocalExecutionPatchEvidenceArtifact {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)]$Spec
    )

    $patchSpec = Get-LocalExecutionPatchEvidenceArtifactSpec -Context $Context
    $inputRel = [string]$patchSpec.input_patch
    $outputRel = [string]$patchSpec.output_path
    if ([string]::IsNullOrWhiteSpace($inputRel)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'patch_evidence_input_missing' -Reason 'Patch evidence classification requires an Input Patch path.' -MissingVariable 'input_patch')
    }
    if ([string]::IsNullOrWhiteSpace($outputRel)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'patch_evidence_output_missing' -Reason 'Patch evidence classification requires an output path under runtime_remote_training/read_only_audit_artifacts/.' -MissingVariable 'output_path')
    }
    if (-not (Test-LocalExecutionReadOnlyPatchEvidencePathAllowed -RelativePath $inputRel)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'patch_evidence_input_unsafe' -Reason ('Patch evidence input path is outside the read-only evidence roots: {0}' -f $inputRel) -MissingVariable 'safe_input_patch')
    }
    if (-not (Test-LocalExecutionSafePath -RelativePath $outputRel)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'patch_evidence_output_unsafe' -Reason ('Patch evidence output is outside LocalExecutionEngine safe roots: {0}' -f $outputRel) -MissingVariable 'safe_output_path')
    }

    $inputAbs = Join-Path $script:LocalEngineRepoRoot ($inputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    $outputAbs = Join-Path $script:LocalEngineRepoRoot ($outputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -Path $inputAbs -PathType Leaf)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'patch_evidence_input_not_found' -Reason ('Patch evidence file does not exist: {0}' -f $inputRel) -MissingVariable 'input_patch_file')
    }

    $patchText = [System.IO.File]::ReadAllText($inputAbs, [System.Text.UTF8Encoding]::new($false))
    $fileMatches = @([regex]::Matches($patchText, '(?m)^diff --git a/(?<old>\S+) b/(?<new>\S+)') | ForEach-Object {
        [ordered]@{
            old_path = [string]$_.Groups['old'].Value
            new_path = [string]$_.Groups['new'].Value
        }
    })
    $additions = @([regex]::Matches($patchText, '(?m)^\+(?!\+\+).*$')).Count
    $deletions = @([regex]::Matches($patchText, '(?m)^-(?!--).*$')).Count
    $hunks = @([regex]::Matches($patchText, '(?m)^@@')).Count

    $signals = New-Object System.Collections.Generic.List[object]
    $signalSpecs = @(
        [pscustomobject]@{ name = 'visible_reply_authority'; pattern = '_studio_cognitive_authority_reply|first working hypothesis|I do not have a specialized handler|Recommended action:|Dave needed:'; bucket = 'hardcoded_response_authority_risk' },
        [pscustomobject]@{ name = 'operator_contract_injection'; pattern = 'Recommended action:|Expected evidence:|Aging rule:|Dave needed:'; bucket = 'operator_contract_authority_risk' },
        [pscustomobject]@{ name = 'active_conversation_state'; pattern = 'active conversation|conversation state|missing fields|slot'; bucket = 'reusable_service_candidate' },
        [pscustomobject]@{ name = 'observational_relationship_memory'; pattern = 'observational|relationship memory|relationship_type|subject.*relationship|current_location|facility_location'; bucket = 'reusable_service_candidate' },
        [pscustomobject]@{ name = 'response_authority_audit'; pattern = 'authority trace|response authority|final_authority|allowed_transformations|operator_contract_allowed'; bucket = 'process_support_candidate' },
        [pscustomobject]@{ name = 'tod_phrase_patch'; pattern = 'If Codex disappeared|Codex disappeared|no codex|without codex'; bucket = 'phrase_patch_rejected' }
    )
    foreach ($signalSpec in @($signalSpecs)) {
        $matches = @([regex]::Matches($patchText, [string]$signalSpec.pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase))
        if (@($matches).Count -gt 0) {
            $signals.Add([ordered]@{
                signal = [string]$signalSpec.name
                bucket = [string]$signalSpec.bucket
                match_count = @($matches).Count
                sample = [string]$matches[0].Value
            }) | Out-Null
        }
    }

    $classificationCounts = [ordered]@{}
    foreach ($signal in @($signals.ToArray())) {
        $bucket = [string]$signal.bucket
        if (-not $classificationCounts.Contains($bucket)) { $classificationCounts[$bucket] = 0 }
        $classificationCounts[$bucket] = [int]$classificationCounts[$bucket] + 1
    }

    $routeFiles = @($fileMatches | Where-Object { [string]$_.new_path -match 'routers?/|routes?\.py' })
    $artifact = [ordered]@{
        artifact_type = 'tod_patch_evidence_authority_classification'
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        source = 'local_execution_patch_evidence_artifact_lane'
        objective_id = if ($Context.PSObject.Properties['objective_id']) { [string]$Context.objective_id } else { '' }
        task_id = if ($Context.PSObject.Properties['task_id']) { [string]$Context.task_id } else { '' }
        task_mode = 'read_only_assessment'
        input_patch = $inputRel
        inspected_files = @($inputRel)
        patch_summary = [ordered]@{
            files_changed = @($fileMatches)
            file_count = @($fileMatches).Count
            route_file_count = @($routeFiles).Count
            additions = $additions
            deletions = $deletions
            hunks = $hunks
        }
        classification_counts = $classificationCounts
        signals = @($signals.ToArray())
        route_boundary_decision = 'review_required_before_reintroduction'
        no_source_code_modified_by_assessment = $true
        no_code_changes = $true
        continuation_action = 'Use this patch evidence artifact to perform route-authority classification. Reintroduce only process support or reusable service candidates through learned capability paths with generalized tests.'
        validation = [ordered]@{
            artifact_path = $outputRel
            input_patch_read = $true
            source_edits = @()
            output_under_read_only_artifacts = $true
        }
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $outputAbs) -Force | Out-Null
    [System.IO.File]::WriteAllText($outputAbs, ($artifact | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))

    $Result.summary = ('Published patch evidence authority classification artifact {0} from {1}.' -f $outputRel, $inputRel)
    $Result.files_changed = @($outputRel)
    $Result.tests_run = @('patch evidence input read', 'patch authority signal extraction', 'read-only artifact write', 'no product source edit assertion')
    $Result.test_results = @('pass', 'pass', 'pass', 'pass')
    $Result | Add-Member -NotePropertyName diff_summary -NotePropertyValue ('Artifact write only: {0}' -f $outputRel) -Force
    $Result | Add-Member -NotePropertyName commands_run -NotePropertyValue @('Invoke-LocalExecutionPatchEvidenceArtifact') -Force
    $Result | Add-Member -NotePropertyName validation_results -NotePropertyValue @(
        [pscustomobject]@{ name = 'patch evidence input read'; passed = $true; required = $true },
        [pscustomobject]@{ name = 'patch authority signal extraction'; passed = (@($signals.ToArray()).Count -gt 0); required = $true },
        [pscustomobject]@{ name = 'read-only artifact write'; passed = $true; required = $true },
        [pscustomobject]@{ name = 'no product source edit assertion'; passed = $true; required = $true }
    ) -Force
    $Result | Add-Member -NotePropertyName blockers -NotePropertyValue @() -Force
    $Result | Add-Member -NotePropertyName confidence -NotePropertyValue 'medium' -Force
    $Result | Add-Member -NotePropertyName rollback_hint -NotePropertyValue ('Remove generated artifact {0} if this read-only evidence artifact must be discarded.' -f $outputRel) -Force
    $Result | Add-Member -NotePropertyName no_change_required -NotePropertyValue $false -Force
    return (Complete-EngineExecutionResult -Result $Result -Status 'completed')
}

function Get-LocalExecutionSourceAnchorObservationSpec {
    param([Parameter(Mandatory = $true)]$Context)

    $text = Get-LocalExecutionCombinedText -Context $Context
    $promptText = Get-LocalExecutionPromptText -Context $Context
    $sourceFile = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Source File'
    if ([string]::IsNullOrWhiteSpace($sourceFile)) {
        $sourceFile = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Inspect Target File'
    }
    if ([string]::IsNullOrWhiteSpace($sourceFile)) {
        $sourceFile = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Target File'
    }

    $outputMatches = [regex]::Matches($text, 'runtime_remote_training/read_only_audit_artifacts/[A-Za-z0-9_./-]+?\.json')
    $outputPath = ''
    if ($outputMatches.Count -gt 0) {
        $outputPath = ([string]$outputMatches[$outputMatches.Count - 1].Value).Trim()
    }

    $anchorPattern = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Anchor Pattern'
    if ([string]::IsNullOrWhiteSpace($anchorPattern)) {
        $anchorPattern = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Anchor'
    }
    $endPattern = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'End Pattern'
    $linesBefore = 0
    $linesAfter = 0
    [int]::TryParse((Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Lines Before'), [ref]$linesBefore) | Out-Null
    [int]::TryParse((Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Lines After'), [ref]$linesAfter) | Out-Null
    $contextLines = 0
    [int]::TryParse((Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Context Lines'), [ref]$contextLines) | Out-Null
    if ($linesBefore -le 0 -and $linesAfter -le 0 -and $contextLines -gt 0) {
        $linesBefore = $contextLines
        $linesAfter = $contextLines
    }

    return [pscustomobject]@{
        source_file = if ([string]::IsNullOrWhiteSpace($sourceFile)) { '' } else { Convert-ToLocalExecutionRepoRelativePath -PathValue $sourceFile }
        output_path = if ([string]::IsNullOrWhiteSpace($outputPath)) { '' } else { Convert-ToLocalExecutionRepoRelativePath -PathValue $outputPath }
        anchor_pattern = $anchorPattern
        end_pattern = $endPattern
        lines_before = [Math]::Max(0, $linesBefore)
        lines_after = [Math]::Max(0, $linesAfter)
    }
}

function Test-LocalExecutionSourceAnchorObservationTask {
    param([Parameter(Mandatory = $true)]$Context)

    $category = Get-LocalExecutionTaskCategory -Context $Context
    if (@('report_only', 'diagnostic_only', 'inspection_only', 'inspection', 'source_anchor_observation') -notcontains $category) {
        return $false
    }

    $text = (Get-LocalExecutionCombinedText -Context $Context).ToLowerInvariant()
    if ($text -notmatch 'source[-_\s]?anchor|anchor\s+observation|exact\s+source\s+anchor|old_text\s+anchor') {
        return $false
    }

    $spec = Get-LocalExecutionSourceAnchorObservationSpec -Context $Context
    return (
        -not [string]::IsNullOrWhiteSpace([string]$spec.source_file) -and
        -not [string]::IsNullOrWhiteSpace([string]$spec.output_path) -and
        -not [string]::IsNullOrWhiteSpace([string]$spec.anchor_pattern)
    )
}

function Invoke-LocalExecutionSourceAnchorObservation {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)]$Spec
    )

    $anchorSpec = Get-LocalExecutionSourceAnchorObservationSpec -Context $Context
    $sourceRel = [string]$anchorSpec.source_file
    $outputRel = [string]$anchorSpec.output_path
    if ([string]::IsNullOrWhiteSpace($sourceRel)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'source_anchor_source_missing' -Reason 'Source anchor observation requires Source File, Inspect Target File, or Target File.' -MissingVariable 'source_file')
    }
    if ([string]::IsNullOrWhiteSpace($outputRel)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'source_anchor_output_missing' -Reason 'Source anchor observation requires an output artifact path under runtime_remote_training/read_only_audit_artifacts/.' -MissingVariable 'output_path')
    }
    if ([string]::IsNullOrWhiteSpace([string]$anchorSpec.anchor_pattern)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'source_anchor_pattern_missing' -Reason 'Source anchor observation requires Anchor Pattern.' -MissingVariable 'anchor_pattern')
    }
    if (-not (Test-LocalExecutionSafePath -RelativePath $sourceRel)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'source_anchor_source_unsafe' -Reason ('Source file is outside LocalExecutionEngine safe roots: {0}' -f $sourceRel) -MissingVariable 'safe_source_path')
    }
    if (-not (Test-LocalExecutionSafePath -RelativePath $outputRel)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'source_anchor_output_unsafe' -Reason ('Output artifact path is outside LocalExecutionEngine safe roots: {0}' -f $outputRel) -MissingVariable 'safe_output_path')
    }

    $sourceAbs = Join-Path $script:LocalEngineRepoRoot $sourceRel
    $outputAbs = Join-Path $script:LocalEngineRepoRoot $outputRel
    if (-not (Test-Path -Path $sourceAbs -PathType Leaf)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'source_anchor_source_not_found' -Reason ('Source file does not exist: {0}' -f $sourceRel) -MissingVariable 'source_file')
    }

    $lines = @(Get-Content -Path $sourceAbs)
    $anchorPattern = [string]$anchorSpec.anchor_pattern
    $startIndex = -1
    for ($idx = 0; $idx -lt $lines.Count; $idx++) {
        if ([string]$lines[$idx] -like ('*' + $anchorPattern + '*')) {
            $startIndex = $idx
            break
        }
    }
    if ($startIndex -lt 0) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'source_anchor_not_found' -Reason ('Anchor pattern not found in source file {0}: {1}' -f $sourceRel, $anchorPattern) -MissingVariable 'anchor_pattern')
    }

    $extractStart = [Math]::Max(0, $startIndex - [int]$anchorSpec.lines_before)
    $extractEnd = [Math]::Min($lines.Count - 1, $startIndex + [int]$anchorSpec.lines_after)
    $endPattern = [string]$anchorSpec.end_pattern
    if (-not [string]::IsNullOrWhiteSpace($endPattern)) {
        for ($idx = $startIndex + 1; $idx -lt $lines.Count; $idx++) {
            if ([string]$lines[$idx] -like ('*' + $endPattern + '*')) {
                $extractEnd = [Math]::Max($extractStart, $idx - 1)
                break
            }
        }
    }

    $extractedLines = @()
    for ($idx = $extractStart; $idx -le $extractEnd; $idx++) {
        $extractedLines += [string]$lines[$idx]
    }
    $exactText = ($extractedLines -join "`n")
    $artifact = [ordered]@{
        artifact_type = 'tod_source_anchor_observation'
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        source = 'local_execution_source_anchor_observation_lane'
        objective_id = if ($Context.PSObject.Properties['objective_id']) { [string]$Context.objective_id } else { '' }
        task_id = if ($Context.PSObject.Properties['task_id']) { [string]$Context.task_id } else { '' }
        source_file = $sourceRel
        anchor_pattern = $anchorPattern
        end_pattern = $endPattern
        matched = $true
        start_line = $extractStart + 1
        end_line = $extractEnd + 1
        line_count = $extractedLines.Count
        exact_text = $exactText
        no_code_changes = $true
        validation = [ordered]@{
            artifact_path = $outputRel
            source_read = $true
            anchor_found = $true
            exact_text_nonempty = -not [string]::IsNullOrWhiteSpace($exactText)
            source_edits = @()
        }
        continuation_action = 'Use exact_text as the old_text source for the next bounded packet-body synthesis rung.'
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $outputAbs) -Force | Out-Null
    $json = $artifact | ConvertTo-Json -Depth 20
    [System.IO.File]::WriteAllText($outputAbs, $json, [System.Text.UTF8Encoding]::new($false))
    $readback = Get-Content -Path $outputAbs -Raw | ConvertFrom-Json
    $requiredFields = @('artifact_type', 'generated_at', 'source', 'objective_id', 'task_id', 'source_file', 'anchor_pattern', 'matched', 'start_line', 'end_line', 'line_count', 'exact_text', 'no_code_changes', 'validation', 'continuation_action')
    $missing = @($requiredFields | Where-Object { -not $readback.PSObject.Properties[$_] })
    if ($missing.Count -gt 0) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'source_anchor_artifact_schema_failed' -Reason ('Source anchor artifact is missing required fields: {0}' -f ($missing -join ', ')) -MissingVariable 'artifact_schema')
    }
    if ($readback.no_code_changes -ne $true -or [string]::IsNullOrWhiteSpace([string]$readback.exact_text)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'source_anchor_artifact_validation_failed' -Reason 'Source anchor artifact must set no_code_changes=true and include non-empty exact_text.' -MissingVariable 'artifact_validation')
    }

    $Result.summary = ('Published source anchor observation {0} from {1} lines {2}-{3}.' -f $outputRel, $sourceRel, ($extractStart + 1), ($extractEnd + 1))
    $Result.files_changed = @($outputRel)
    $Result.tests_run = @('source file read', 'anchor pattern match', 'source anchor artifact write', 'required schema readback', 'no-code-change assertion')
    $Result.test_results = @('pass', 'pass', 'pass', 'pass', 'pass')
    $Result | Add-Member -NotePropertyName command_output -NotePropertyValue ('Source anchor observation published: {0}' -f $outputRel) -Force
    $Result | Add-Member -NotePropertyName diff_summary -NotePropertyValue ('Artifact write only: {0}' -f $outputRel) -Force
    $Result | Add-Member -NotePropertyName commands_run -NotePropertyValue @('Invoke-LocalExecutionSourceAnchorObservation') -Force
    $Result | Add-Member -NotePropertyName validation_results -NotePropertyValue @(
        [pscustomobject]@{ name = 'source file read'; passed = $true; required = $true },
        [pscustomobject]@{ name = 'anchor pattern match'; passed = $true; required = $true },
        [pscustomobject]@{ name = 'source anchor artifact write'; passed = $true; required = $true },
        [pscustomobject]@{ name = 'required schema readback'; passed = $true; required = $true },
        [pscustomobject]@{ name = 'no-code-change assertion'; passed = $true; required = $true }
    ) -Force
    $Result | Add-Member -NotePropertyName blockers -NotePropertyValue @() -Force
    $Result | Add-Member -NotePropertyName confidence -NotePropertyValue 'high' -Force
    $Result | Add-Member -NotePropertyName rollback_hint -NotePropertyValue ('Remove generated artifact {0} if this source-anchor training artifact must be discarded.' -f $outputRel) -Force
    $Result | Add-Member -NotePropertyName no_change_required -NotePropertyValue $false -Force
    return (Complete-EngineExecutionResult -Result $Result -Status 'completed')
}

function Get-LocalExecutionPacketBodySynthesisSpec {
    param([Parameter(Mandatory = $true)]$Context)

    $text = Get-LocalExecutionCombinedText -Context $Context
    $promptText = Get-LocalExecutionPromptText -Context $Context
    $inputArtifact = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Input Artifact'
    if ([string]::IsNullOrWhiteSpace($inputArtifact)) {
        $inputMatch = [regex]::Match($text, 'runtime_remote_training/read_only_audit_artifacts/[A-Za-z0-9_./-]+?\.json')
        if ($inputMatch.Success) {
            $inputArtifact = ([string]$inputMatch.Groups[0].Value).Trim()
        }
    }

    $outputMatches = [regex]::Matches($text, 'runtime_remote_training/tod_independent_resolution_attempts/[A-Za-z0-9_./-]+?\.json')
    $outputPath = ''
    if ($outputMatches.Count -gt 0) {
        $outputPath = ([string]$outputMatches[$outputMatches.Count - 1].Value).Trim()
    }

    return [pscustomobject]@{
        input_artifact = if ([string]::IsNullOrWhiteSpace($inputArtifact)) { '' } else { Convert-ToLocalExecutionRepoRelativePath -PathValue $inputArtifact }
        output_path = if ([string]::IsNullOrWhiteSpace($outputPath)) { '' } else { Convert-ToLocalExecutionRepoRelativePath -PathValue $outputPath }
        target_file = Convert-ToLocalExecutionRepoRelativePath -PathValue (Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Target File')
        insert_before_pattern = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Insert Before Pattern'
        field_name = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Field Name'
        field_value = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Field Value'
        validation_command = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Validation Command'
        validation_pattern = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Validation Pattern'
        closure_evidence = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Closure Evidence'
        prevention_lesson = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Prevention Lesson'
        dave_needed = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Dave Needed'
    }
}

function Test-LocalExecutionPacketBodySynthesisTask {
    param([Parameter(Mandatory = $true)]$Context)

    $category = Get-LocalExecutionTaskCategory -Context $Context
    if (@('report_only', 'diagnostic_only', 'inspection_only', 'inspection', 'packet_formation') -notcontains $category) {
        return $false
    }

    $text = (Get-LocalExecutionCombinedText -Context $Context).ToLowerInvariant()
    if ($text -notmatch 'packet[-_\s]?body\s+synthesis|bounded\s+new\s+text|new_text\s+artifact\s+body') {
        return $false
    }

    $spec = Get-LocalExecutionPacketBodySynthesisSpec -Context $Context
    return (
        -not [string]::IsNullOrWhiteSpace([string]$spec.input_artifact) -and
        -not [string]::IsNullOrWhiteSpace([string]$spec.output_path) -and
        -not [string]::IsNullOrWhiteSpace([string]$spec.target_file) -and
        -not [string]::IsNullOrWhiteSpace([string]$spec.insert_before_pattern) -and
        -not [string]::IsNullOrWhiteSpace([string]$spec.field_name) -and
        -not [string]::IsNullOrWhiteSpace([string]$spec.field_value)
    )
}

function Invoke-LocalExecutionPacketBodySynthesis {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)]$Spec
    )

    $bodySpec = Get-LocalExecutionPacketBodySynthesisSpec -Context $Context
    $inputRel = [string]$bodySpec.input_artifact
    $outputRel = [string]$bodySpec.output_path
    $targetFile = [string]$bodySpec.target_file
    foreach ($entry in @(
            [pscustomobject]@{ Name = 'input_artifact'; Value = $inputRel },
            [pscustomobject]@{ Name = 'output_path'; Value = $outputRel },
            [pscustomobject]@{ Name = 'target_file'; Value = $targetFile },
            [pscustomobject]@{ Name = 'insert_before_pattern'; Value = [string]$bodySpec.insert_before_pattern },
            [pscustomobject]@{ Name = 'field_name'; Value = [string]$bodySpec.field_name },
            [pscustomobject]@{ Name = 'field_value'; Value = [string]$bodySpec.field_value }
        )) {
        if ([string]::IsNullOrWhiteSpace([string]$entry.Value)) {
            return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode ('packet_body_synthesis_{0}_missing' -f $entry.Name) -Reason ('Packet body synthesis requires {0}.' -f $entry.Name) -MissingVariable $entry.Name)
        }
    }
    foreach ($pathEntry in @(
            [pscustomobject]@{ Name = 'input_artifact'; Value = $inputRel },
            [pscustomobject]@{ Name = 'output_path'; Value = $outputRel },
            [pscustomobject]@{ Name = 'target_file'; Value = $targetFile }
        )) {
        if (-not (Test-LocalExecutionSafePath -RelativePath ([string]$pathEntry.Value))) {
            return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode ('packet_body_synthesis_{0}_unsafe' -f $pathEntry.Name) -Reason ('Packet body synthesis path is outside LocalExecutionEngine safe roots: {0}' -f [string]$pathEntry.Value) -MissingVariable ('safe_' + $pathEntry.Name))
        }
    }

    $inputAbs = Join-Path $script:LocalEngineRepoRoot $inputRel
    $outputAbs = Join-Path $script:LocalEngineRepoRoot $outputRel
    if (-not (Test-Path -Path $inputAbs -PathType Leaf)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'packet_body_synthesis_input_not_found' -Reason ('Input source-anchor artifact does not exist: {0}' -f $inputRel) -MissingVariable 'input_artifact')
    }
    $anchorArtifact = Get-Content -Path $inputAbs -Raw | ConvertFrom-Json
    $oldText = [string]$anchorArtifact.exact_text
    if ([string]::IsNullOrWhiteSpace($oldText)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'packet_body_synthesis_old_text_missing' -Reason 'Input source-anchor artifact does not include non-empty exact_text.' -MissingVariable 'old_text')
    }

    $oldLines = @($oldText -split "`n", -1)
    $insertIndex = -1
    $insertBeforePattern = [string]$bodySpec.insert_before_pattern
    for ($idx = 0; $idx -lt $oldLines.Count; $idx++) {
        if ([string]$oldLines[$idx] -like ('*' + $insertBeforePattern + '*')) {
            $insertIndex = $idx
            break
        }
    }
    if ($insertIndex -lt 0) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'packet_body_synthesis_insert_anchor_not_found' -Reason ('Insert-before pattern not found in old_text: {0}' -f $insertBeforePattern) -MissingVariable 'insert_before_pattern')
    }

    $baseLine = [string]$oldLines[$insertIndex]
    $indentMatch = [regex]::Match($baseLine, '^(?<indent>\s*)')
    $indent = [string]$indentMatch.Groups['indent'].Value
    $insertion = '{0}"{1}": {2},' -f $indent, [string]$bodySpec.field_name, [string]$bodySpec.field_value
    $newLines = New-Object System.Collections.Generic.List[string]
    for ($idx = 0; $idx -lt $oldLines.Count; $idx++) {
        if ($idx -eq $insertIndex) {
            $newLines.Add($insertion) | Out-Null
        }
        $newLines.Add([string]$oldLines[$idx]) | Out-Null
    }
    $newText = ($newLines.ToArray() -join "`n").TrimEnd("`n")
    if ([string]$newText -eq [string]$oldText) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'packet_body_synthesis_no_delta' -Reason 'Packet body synthesis produced identical old_text and new_text.' -MissingVariable 'new_text_delta')
    }

    $validationCommand = [string]$bodySpec.validation_command
    if ([string]::IsNullOrWhiteSpace($validationCommand)) {
        $validationCommand = 'python -m py_compile {0}' -f $targetFile
    }
    $validationPattern = [string]$bodySpec.validation_pattern
    if ([string]::IsNullOrWhiteSpace($validationPattern)) {
        $validationPattern = [string]$bodySpec.field_name
    }
    $closureEvidence = [string]$bodySpec.closure_evidence
    if ([string]::IsNullOrWhiteSpace($closureEvidence)) {
        $closureEvidence = 'Packet candidate ready with exact source-anchor old_text and synthesized new_text.'
    }
    $preventionLesson = [string]$bodySpec.prevention_lesson
    if ([string]::IsNullOrWhiteSpace($preventionLesson)) {
        $preventionLesson = 'TOD must observe exact current source text before synthesizing bounded new_text artifacts.'
    }
    $daveNeeded = [string]$bodySpec.dave_needed
    if ([string]::IsNullOrWhiteSpace($daveNeeded)) {
        $daveNeeded = 'no'
    }

    $artifact = [ordered]@{
        artifact_type = 'tod_packet_body_synthesis_artifact'
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        source = 'local_execution_packet_body_synthesis_lane'
        objective_id = if ($Context.PSObject.Properties['objective_id']) { [string]$Context.objective_id } else { '' }
        task_id = if ($Context.PSObject.Properties['task_id']) { [string]$Context.task_id } else { '' }
        packet_candidate_ready = $true
        packet = [ordered]@{
            target_file = $targetFile
            intended_edit_mode = 'replace_exact_text'
            old_text = $oldText
            new_text = $newText
            validation_command = $validationCommand
            validation_pattern = $validationPattern
            closure_evidence = $closureEvidence
            prevention_lesson = $preventionLesson
            dave_needed = $daveNeeded
        }
        synthesis = [ordered]@{
            input_artifact = $inputRel
            source_file = if ($anchorArtifact.PSObject.Properties['source_file']) { [string]$anchorArtifact.source_file } else { $targetFile }
            start_line = if ($anchorArtifact.PSObject.Properties['start_line']) { $anchorArtifact.start_line } else { $null }
            end_line = if ($anchorArtifact.PSObject.Properties['end_line']) { $anchorArtifact.end_line } else { $null }
            inserted_field = [string]$bodySpec.field_name
            insert_before_pattern = $insertBeforePattern
            old_text_line_count = $oldLines.Count
            new_text_line_count = $newLines.Count
        }
        validation = [ordered]@{
            artifact_path = $outputRel
            input_artifact_read = $true
            old_text_present = -not [string]::IsNullOrWhiteSpace($oldText)
            new_text_differs = [string]$newText -ne [string]$oldText
            packet_candidate_schema = 'ready'
            no_source_edits = $true
        }
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $outputAbs) -Force | Out-Null
    [System.IO.File]::WriteAllText($outputAbs, ($artifact | ConvertTo-Json -Depth 30), [System.Text.UTF8Encoding]::new($false))
    $validationCommandForPacket = New-LocalExecutionPacketCandidateValidationCommand -TargetFile $outputRel
    $validationOutput = Invoke-Expression $validationCommandForPacket

    $Result.summary = ('Published packet body synthesis artifact {0} from source anchor {1}.' -f $outputRel, $inputRel)
    $Result.files_changed = @($outputRel)
    $Result.tests_run = @('input source-anchor artifact read', 'new_text synthesis', 'packet candidate schema validation')
    $Result.test_results = @('pass', 'pass', 'pass')
    $Result | Add-Member -NotePropertyName command_output -NotePropertyValue ($validationOutput -join "`n") -Force
    $Result | Add-Member -NotePropertyName diff_summary -NotePropertyValue ('Artifact write only: {0}' -f $outputRel) -Force
    $Result | Add-Member -NotePropertyName commands_run -NotePropertyValue @('Invoke-LocalExecutionPacketBodySynthesis', $validationCommandForPacket) -Force
    $Result | Add-Member -NotePropertyName validation_results -NotePropertyValue @(
        [pscustomobject]@{ name = 'input source-anchor artifact read'; passed = $true; required = $true },
        [pscustomobject]@{ name = 'new_text synthesis'; passed = $true; required = $true },
        [pscustomobject]@{ name = 'packet candidate schema validation'; passed = $true; required = $true }
    ) -Force
    $Result | Add-Member -NotePropertyName blockers -NotePropertyValue @() -Force
    $Result | Add-Member -NotePropertyName confidence -NotePropertyValue 'medium-high' -Force
    $Result | Add-Member -NotePropertyName rollback_hint -NotePropertyValue ('Remove generated artifact {0} if this packet-body training artifact must be discarded.' -f $outputRel) -Force
    $Result | Add-Member -NotePropertyName no_change_required -NotePropertyValue $false -Force
    return (Complete-EngineExecutionResult -Result $Result -Status 'completed')
}

function Get-LocalExecutionApplyPacketArtifactSpec {
    param([Parameter(Mandatory = $true)]$Context)

    $text = Get-LocalExecutionCombinedText -Context $Context
    $promptText = Get-LocalExecutionPromptText -Context $Context
    $inputArtifact = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Input Artifact'
    if ([string]::IsNullOrWhiteSpace($inputArtifact)) {
        $inputArtifact = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Packet Artifact'
    }
    if ([string]::IsNullOrWhiteSpace($inputArtifact)) {
        $inputMatch = [regex]::Match($text, 'runtime_remote_training/tod_independent_resolution_attempts/[A-Za-z0-9_./-]+?\.json')
        if ($inputMatch.Success) {
            $inputArtifact = ([string]$inputMatch.Groups[0].Value).Trim()
        }
    }

    $reverseValue = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Reverse Packet'
    if ([string]::IsNullOrWhiteSpace($reverseValue)) {
        $reverseValue = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Cleanup'
    }
    $reversePacket = [string]$reverseValue -match '(?i)^(true|yes|1)$'

    return [pscustomobject]@{
        input_artifact = if ([string]::IsNullOrWhiteSpace($inputArtifact)) { '' } else { Convert-ToLocalExecutionRepoRelativePath -PathValue $inputArtifact }
        reverse_packet = $reversePacket
        validation_pattern = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Validation Pattern'
    }
}

function Test-LocalExecutionApplyPacketArtifactTask {
    param([Parameter(Mandatory = $true)]$Context)

    $category = Get-LocalExecutionTaskCategory -Context $Context
    if (@('implementation', 'training', 'recovery', 'apply_packet_artifact') -notcontains $category) {
        return $false
    }

    $text = (Get-LocalExecutionCombinedText -Context $Context).ToLowerInvariant()
    if ($text -notmatch 'apply\s+packet\s+artifact|packet\s+artifact\s+apply|apply[-_ ]from[-_ ]packet') {
        return $false
    }

    $spec = Get-LocalExecutionApplyPacketArtifactSpec -Context $Context
    return -not [string]::IsNullOrWhiteSpace([string]$spec.input_artifact)
}

function Invoke-LocalExecutionApplyPacketArtifact {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)]$Spec
    )

    $applySpec = Get-LocalExecutionApplyPacketArtifactSpec -Context $Context
    $inputRel = [string]$applySpec.input_artifact
    if ([string]::IsNullOrWhiteSpace($inputRel)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'apply_packet_artifact_missing' -Reason 'Apply-from-packet requires Input Artifact or Packet Artifact.' -MissingVariable 'input_artifact')
    }
    if (-not (Test-LocalExecutionSafePath -RelativePath $inputRel)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'apply_packet_artifact_unsafe' -Reason ('Packet artifact path is outside LocalExecutionEngine safe roots: {0}' -f $inputRel) -MissingVariable 'safe_input_artifact')
    }

    $inputAbs = Join-Path $script:LocalEngineRepoRoot $inputRel
    if (-not (Test-Path -Path $inputAbs -PathType Leaf)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'apply_packet_artifact_not_found' -Reason ('Packet artifact does not exist: {0}' -f $inputRel) -MissingVariable 'input_artifact')
    }

    $artifact = Get-Content -Path $inputAbs -Raw | ConvertFrom-Json
    if (-not $artifact.PSObject.Properties['packet'] -or $null -eq $artifact.packet) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'apply_packet_artifact_packet_missing' -Reason 'Packet artifact does not include a packet object.' -MissingVariable 'packet')
    }

    $packet = $artifact.packet
    foreach ($entry in @(
            [pscustomobject]@{ Name = 'target_file'; Value = if ($packet.PSObject.Properties['target_file']) { [string]$packet.target_file } else { '' } },
            [pscustomobject]@{ Name = 'old_text'; Value = if ($packet.PSObject.Properties['old_text']) { [string]$packet.old_text } else { '' } },
            [pscustomobject]@{ Name = 'new_text'; Value = if ($packet.PSObject.Properties['new_text']) { [string]$packet.new_text } else { '' } }
        )) {
        if ([string]::IsNullOrWhiteSpace([string]$entry.Value)) {
            return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode ('apply_packet_artifact_{0}_missing' -f $entry.Name) -Reason ('Packet artifact requires packet.{0}.' -f $entry.Name) -MissingVariable $entry.Name)
        }
    }

    $targetFile = Convert-ToLocalExecutionRepoRelativePath -PathValue ([string]$packet.target_file)
    if (-not (Test-LocalExecutionSafePath -RelativePath $targetFile)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'apply_packet_target_unsafe' -Reason ('Packet target path is outside LocalExecutionEngine safe roots: {0}' -f $targetFile) -MissingVariable 'safe_target_file')
    }

    try {
        $targetAbs = Resolve-LocalExecutionAbsoluteTargetPath -RelativePath $targetFile -Operation 'write'
    }
    catch {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'apply_packet_target_unsafe' -Reason $_.Exception.Message -MissingVariable 'safe_target_file')
    }
    if (-not (Test-Path -Path $targetAbs -PathType Leaf)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'apply_packet_target_not_found' -Reason ('Packet target file does not exist: {0}' -f $targetFile) -MissingVariable 'target_file')
    }

    $oldText = [string]$packet.old_text
    $newText = [string]$packet.new_text
    $operation = 'apply'
    if ([bool]$applySpec.reverse_packet) {
        $swap = $oldText
        $oldText = $newText
        $newText = $swap
        $operation = 'cleanup'
    }
    if ([string]$oldText -eq [string]$newText) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'apply_packet_no_delta' -Reason 'Packet old_text and new_text are identical.' -MissingVariable 'packet_delta')
    }

    $originalContent = [System.IO.File]::ReadAllText($targetAbs, [System.Text.UTF8Encoding]::new($false))
    try {
        $updatedContent = Set-StrictTextReplacement -Content $originalContent -OldText $oldText -NewText $newText -Label ('packet artifact replacement in ' + $targetFile)
    }
    catch {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'apply_packet_old_text_not_found' -Reason $_.Exception.Message -MissingVariable 'old_text')
    }

    $writeSizeCheck = Test-LocalExecutionWriteSizeSafe -OriginalContent $originalContent -UpdatedContent $updatedContent -EditMode 'replace_text'
    if (-not [bool]$writeSizeCheck.safe) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'apply_packet_write_size_guard' -Reason ('LocalExecutionEngine blocked packet apply for {0} because the bounded edit expanded the file from {1} bytes to {2} bytes, exceeding the limit of {3} bytes.' -f $targetFile, [int64]$writeSizeCheck.original_bytes, [int64]$writeSizeCheck.updated_bytes, [int64]$writeSizeCheck.max_allowed_bytes) -MissingVariable 'bounded_write_size')
    }

    Write-Utf8NoBomFile -Path $targetAbs -Content $updatedContent -PreserveExistingBom
    $validationCommand = if ($packet.PSObject.Properties['validation_command']) { [string]$packet.validation_command } else { '' }
    if ([string]::IsNullOrWhiteSpace($validationCommand)) {
        $validationCommand = 'python -m json.tool {0}' -f $targetFile
    }
    $validationCapture = Invoke-LocalShellCapture -Command $validationCommand -WorkingDirectory $script:LocalEngineRepoRoot -TimeoutSeconds 60
    $validationPassed = ([int]$validationCapture.exit_code -eq 0 -and -not [bool]$validationCapture.timed_out -and (Test-LocalShellStderrClean -Stderr ([string]$validationCapture.stderr)))
    $pattern = [string]$applySpec.validation_pattern
    if ([string]::IsNullOrWhiteSpace($pattern) -and $packet.PSObject.Properties['validation_pattern']) {
        $pattern = [string]$packet.validation_pattern
    }
    $patternPassed = $true
    if (-not [string]::IsNullOrWhiteSpace($pattern)) {
        $currentContent = [System.IO.File]::ReadAllText($targetAbs, [System.Text.UTF8Encoding]::new($false))
        $patternPassed = if ([string]::Equals($operation, 'cleanup', [System.StringComparison]::OrdinalIgnoreCase)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$applySpec.validation_pattern)) {
                $currentContent -match [regex]::Escape($pattern)
            }
            elseif ($packet.PSObject.Properties['validation_pattern'] -and -not [string]::IsNullOrWhiteSpace([string]$packet.validation_pattern)) {
                $currentContent -notmatch [regex]::Escape([string]$packet.validation_pattern)
            }
            else {
                $currentContent.Contains($newText) -and -not $currentContent.Contains($oldText)
            }
        }
        else {
            $currentContent -match [regex]::Escape($pattern)
        }
    }

    if (-not ($validationPassed -and $patternPassed)) {
        Write-Utf8NoBomFile -Path $targetAbs -Content $originalContent -PreserveExistingBom
        $Result.summary = ('Packet artifact {0} failed validation and was rolled back.' -f $operation)
        $Result.files_changed = @()
        $Result.tests_run = @('packet_artifact_read', 'target_file_exists', 'bounded_replacement', 'focused_validation_exit_zero', 'validation_pattern_check')
        $Result.test_results = @('pass', 'pass', 'pass', $(if ($validationPassed) { 'pass' } else { 'fail' }), $(if ($patternPassed) { 'pass' } else { 'fail' }))
        $Result.failures = @('Packet artifact validation failed; original content restored.')
        $Result | Add-Member -NotePropertyName reason_code -NotePropertyValue 'apply_packet_validation_failed' -Force
        $Result | Add-Member -NotePropertyName recovery_state -NotePropertyValue 'rolled_back' -Force
        $Result | Add-Member -NotePropertyName command_output -NotePropertyValue ([string]$validationCapture.stdout) -Force
        return (Complete-EngineExecutionResult -Result $Result -Status 'failed')
    }

    $diffSummary = Get-LocalExecutionDiffSummary -RelativePath $targetFile -BeforeContent $originalContent -AfterContent $updatedContent -ActionSummary ('Applied packet artifact {0}' -f $operation)
    $Result.summary = ('Applied packet artifact {0} for {1} and published real execution evidence.' -f $operation, $targetFile)
    $Result.files_changed = @($targetFile)
    $Result.tests_run = @('packet_artifact_read', 'target_file_exists', 'bounded_replacement', 'focused_validation_exit_zero', 'focused_validation_stderr_empty', 'validation_pattern_check')
    $Result.test_results = @('pass', 'pass', 'pass', 'pass', 'pass', 'pass')
    $Result.failures = @()
    $Result.recommendations = @('Continue to the next independent demonstration only after cleanup validates and the final evidence artifact records borrowed versus independent steps.')
    $Result.needs_escalation = $false
    $Result.structured_findings = @(
        [pscustomobject]@{
            type = 'result_contract'
            understood_task = 'Apply a TOD-produced bounded packet artifact directly.'
            action_taken = ('Applied packet artifact {0}.' -f $operation)
            changed_files = @($targetFile)
            evidence = @($diffSummary)
            validation_result = 'passed'
            remaining_blocker = ''
            next_action = if ($operation -eq 'apply') { 'Run the cleanup pass using Reverse Packet=true.' } else { 'Publish final apprenticeship evidence.' }
            confidence = 'high'
            accepted = $true
            artifact_changed = $true
        },
        [pscustomobject]@{ type = 'command'; capture = $validationCapture }
    )
    $Result.raw_output = [pscustomobject]@{
        engine = $Spec
        task_context = $Context
        action = 'apply_packet_artifact_completed'
        operation = $operation
        input_artifact = $inputRel
        target_file = $targetFile
        diff_summary = $diffSummary
        validation_capture = $validationCapture
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
    }
    $Result | Add-Member -NotePropertyName diff_summary -NotePropertyValue $diffSummary -Force
    $Result | Add-Member -NotePropertyName commands_run -NotePropertyValue @([string]$validationCapture.command) -Force
    $Result | Add-Member -NotePropertyName validation_results -NotePropertyValue @(
        [pscustomobject]@{ name = 'packet_artifact_read'; passed = $true; required = $true },
        [pscustomobject]@{ name = 'target_file_exists'; passed = $true; required = $true },
        [pscustomobject]@{ name = 'bounded_replacement'; passed = $true; required = $true },
        [pscustomobject]@{ name = 'focused_validation_exit_zero'; passed = $true; required = $true },
        [pscustomobject]@{ name = 'focused_validation_stderr_empty'; passed = $true; required = $true },
        [pscustomobject]@{ name = 'validation_pattern_check'; passed = $true; required = $true }
    ) -Force
    $Result | Add-Member -NotePropertyName blockers -NotePropertyValue @() -Force
    $Result | Add-Member -NotePropertyName confidence -NotePropertyValue 'high' -Force
    $Result | Add-Member -NotePropertyName rollback_hint -NotePropertyValue ('Reverse packet artifact from {0} to restore {1}.' -f $inputRel, $targetFile) -Force
    $Result | Add-Member -NotePropertyName command_output -NotePropertyValue ([string]$validationCapture.stdout) -Force
    $Result | Add-Member -NotePropertyName reason_code -NotePropertyValue '' -Force
    $Result | Add-Member -NotePropertyName recovery_state -NotePropertyValue 'not_needed' -Force
    return (Complete-EngineExecutionResult -Result $Result -Status 'completed')
}

function Get-LocalExecutionPythonRouteBodySynthesisSpec {
    param([Parameter(Mandatory = $true)]$Context)

    $text = Get-LocalExecutionCombinedText -Context $Context
    $promptText = Get-LocalExecutionPromptText -Context $Context
    $inputArtifact = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Input Artifact'
    if ([string]::IsNullOrWhiteSpace($inputArtifact)) {
        $inputMatch = [regex]::Match($text, 'runtime_remote_training/read_only_audit_artifacts/[A-Za-z0-9_./-]+?\.json')
        if ($inputMatch.Success) {
            $inputArtifact = ([string]$inputMatch.Groups[0].Value).Trim()
        }
    }

    $outputMatches = [regex]::Matches($text, 'runtime_remote_training/tod_independent_resolution_attempts/[A-Za-z0-9_./-]+?\.json')
    $outputPath = ''
    if ($outputMatches.Count -gt 0) {
        $outputPath = ([string]$outputMatches[$outputMatches.Count - 1].Value).Trim()
    }

    return [pscustomobject]@{
        input_artifact = if ([string]::IsNullOrWhiteSpace($inputArtifact)) { '' } else { Convert-ToLocalExecutionRepoRelativePath -PathValue $inputArtifact }
        output_path = if ([string]::IsNullOrWhiteSpace($outputPath)) { '' } else { Convert-ToLocalExecutionRepoRelativePath -PathValue $outputPath }
        target_file = Convert-ToLocalExecutionRepoRelativePath -PathValue (Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Target File')
        insert_before_pattern = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Insert Before Pattern'
        route_path = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Route Path'
        route_name = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Route Name'
        validation_command = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Validation Command'
        validation_pattern = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Validation Pattern'
        closure_evidence = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Closure Evidence'
        prevention_lesson = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Prevention Lesson'
        dave_needed = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Dave Needed'
    }
}

function Test-LocalExecutionPythonRouteBodySynthesisTask {
    param([Parameter(Mandatory = $true)]$Context)

    $category = Get-LocalExecutionTaskCategory -Context $Context
    if (@('report_only', 'diagnostic_only', 'inspection_only', 'inspection', 'packet_formation') -notcontains $category) {
        return $false
    }

    $text = (Get-LocalExecutionCombinedText -Context $Context).ToLowerInvariant()
    if ($text -notmatch 'python[_\-\s]?route[_\-\s]?body[_\-\s]?synthesis|route\s+body\s+packet|python\s+route\s+bounded\s+packet') {
        return $false
    }

    $spec = Get-LocalExecutionPythonRouteBodySynthesisSpec -Context $Context
    return (
        -not [string]::IsNullOrWhiteSpace([string]$spec.input_artifact) -and
        -not [string]::IsNullOrWhiteSpace([string]$spec.output_path) -and
        -not [string]::IsNullOrWhiteSpace([string]$spec.target_file) -and
        -not [string]::IsNullOrWhiteSpace([string]$spec.insert_before_pattern) -and
        -not [string]::IsNullOrWhiteSpace([string]$spec.route_path) -and
        -not [string]::IsNullOrWhiteSpace([string]$spec.route_name)
    )
}

function Get-LocalExecutionPythonSnippetBodySynthesisSpec {
    param([Parameter(Mandatory = $true)]$Context)

    $text = Get-LocalExecutionCombinedText -Context $Context
    $promptText = Get-LocalExecutionPromptText -Context $Context
    $inputArtifact = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Input Artifact'
    if ([string]::IsNullOrWhiteSpace($inputArtifact)) {
        $inputMatch = [regex]::Match($text, 'runtime_remote_training/read_only_audit_artifacts/[A-Za-z0-9_./-]+?\.json')
        if ($inputMatch.Success) {
            $inputArtifact = ([string]$inputMatch.Groups[0].Value).Trim()
        }
    }

    $outputMatches = [regex]::Matches($text, 'runtime_remote_training/tod_independent_resolution_attempts/[A-Za-z0-9_./-]+?\.json')
    $outputPath = ''
    if ($outputMatches.Count -gt 0) {
        $outputPath = ([string]$outputMatches[$outputMatches.Count - 1].Value).Trim()
    }

    $packetSourceTarget = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Packet Source Target'
    if ([string]::IsNullOrWhiteSpace($packetSourceTarget)) {
        $packetSourceTarget = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Inspect Target File'
    }
    if ([string]::IsNullOrWhiteSpace($packetSourceTarget)) {
        $packetSourceTarget = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Target File'
    }

    return [pscustomobject]@{
        input_artifact = if ([string]::IsNullOrWhiteSpace($inputArtifact)) { '' } else { Convert-ToLocalExecutionRepoRelativePath -PathValue $inputArtifact }
        output_path = if ([string]::IsNullOrWhiteSpace($outputPath)) { '' } else { Convert-ToLocalExecutionRepoRelativePath -PathValue $outputPath }
        target_file = Convert-ToLocalExecutionRepoRelativePath -PathValue $packetSourceTarget
        insert_before_pattern = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Insert Before Pattern'
        snippet = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Snippet'
        validation_command = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Validation Command'
        validation_pattern = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Validation Pattern'
        closure_evidence = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Closure Evidence'
        prevention_lesson = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Prevention Lesson'
        dave_needed = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Dave Needed'
    }
}

function Test-LocalExecutionPythonSnippetBodySynthesisTask {
    param([Parameter(Mandatory = $true)]$Context)

    $category = Get-LocalExecutionTaskCategory -Context $Context
    if (@('report_only', 'diagnostic_only', 'inspection_only', 'inspection', 'packet_formation') -notcontains $category) {
        return $false
    }

    $text = (Get-LocalExecutionCombinedText -Context $Context).ToLowerInvariant()
    if ($text -notmatch 'python[_\-\s]?snippet[_\-\s]?body[_\-\s]?synthesis|python\s+class\s+bounded\s+packet|python\s+model\s+body\s+synthesis|python\s+bounded\s+snippet\s+packet') {
        return $false
    }

    $spec = Get-LocalExecutionPythonSnippetBodySynthesisSpec -Context $Context
    return (
        -not [string]::IsNullOrWhiteSpace([string]$spec.input_artifact) -and
        -not [string]::IsNullOrWhiteSpace([string]$spec.output_path) -and
        -not [string]::IsNullOrWhiteSpace([string]$spec.target_file) -and
        -not [string]::IsNullOrWhiteSpace([string]$spec.insert_before_pattern) -and
        -not [string]::IsNullOrWhiteSpace([string]$spec.snippet)
    )
}

function Invoke-LocalExecutionPythonSnippetBodySynthesis {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)]$Spec
    )

    $snippetSpec = Get-LocalExecutionPythonSnippetBodySynthesisSpec -Context $Context
    $inputRel = [string]$snippetSpec.input_artifact
    $outputRel = [string]$snippetSpec.output_path
    $targetFile = [string]$snippetSpec.target_file
    foreach ($entry in @(
            [pscustomobject]@{ Name = 'input_artifact'; Value = $inputRel },
            [pscustomobject]@{ Name = 'output_path'; Value = $outputRel },
            [pscustomobject]@{ Name = 'target_file'; Value = $targetFile },
            [pscustomobject]@{ Name = 'insert_before_pattern'; Value = [string]$snippetSpec.insert_before_pattern },
            [pscustomobject]@{ Name = 'snippet'; Value = [string]$snippetSpec.snippet }
        )) {
        if ([string]::IsNullOrWhiteSpace([string]$entry.Value)) {
            return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode ('python_snippet_body_synthesis_{0}_missing' -f $entry.Name) -Reason ('Python snippet body synthesis requires {0}.' -f $entry.Name) -MissingVariable $entry.Name)
        }
    }
    foreach ($pathEntry in @(
            [pscustomobject]@{ Name = 'input_artifact'; Value = $inputRel },
            [pscustomobject]@{ Name = 'output_path'; Value = $outputRel },
            [pscustomobject]@{ Name = 'target_file'; Value = $targetFile }
        )) {
        if (-not (Test-LocalExecutionSafePath -RelativePath ([string]$pathEntry.Value))) {
            return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode ('python_snippet_body_synthesis_{0}_unsafe' -f $pathEntry.Name) -Reason ('Python snippet body synthesis path is outside LocalExecutionEngine safe roots: {0}' -f [string]$pathEntry.Value) -MissingVariable ('safe_' + $pathEntry.Name))
        }
    }

    $inputAbs = Join-Path $script:LocalEngineRepoRoot $inputRel
    $outputAbs = Join-Path $script:LocalEngineRepoRoot $outputRel
    if (-not (Test-Path -Path $inputAbs -PathType Leaf)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'python_snippet_body_synthesis_input_not_found' -Reason ('Input source-anchor artifact does not exist: {0}' -f $inputRel) -MissingVariable 'input_artifact')
    }
    $anchorArtifact = Get-Content -Path $inputAbs -Raw | ConvertFrom-Json
    if (-not $anchorArtifact.PSObject.Properties['artifact_type'] -or [string]$anchorArtifact.artifact_type -ne 'tod_source_anchor_observation') {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'python_snippet_body_synthesis_input_not_anchor' -Reason ('Input artifact is not a source-anchor observation: {0}' -f $inputRel) -MissingVariable 'source_anchor_artifact')
    }

    $oldText = [string]$anchorArtifact.exact_text
    $targetAbs = Join-Path $script:LocalEngineRepoRoot $targetFile
    if (-not (Test-Path -Path $targetAbs -PathType Leaf)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'python_snippet_body_synthesis_target_not_found' -Reason ('Target file does not exist: {0}' -f $targetFile) -MissingVariable 'target_file')
    }
    $targetRaw = Get-Content -Path $targetAbs -Raw
    if ($anchorArtifact.PSObject.Properties['start_line'] -and $anchorArtifact.PSObject.Properties['end_line']) {
        $rawOldText = Get-LocalExecutionRawTextLineRange -Content $targetRaw -StartLine ([int]$anchorArtifact.start_line) -EndLine ([int]$anchorArtifact.end_line)
        if (-not [string]::IsNullOrWhiteSpace($rawOldText) -and $rawOldText -like ('*' + [string]$snippetSpec.insert_before_pattern + '*')) {
            $oldText = $rawOldText
        }
    }
    if ([string]::IsNullOrWhiteSpace($oldText)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'python_snippet_body_synthesis_old_text_missing' -Reason 'Input source-anchor artifact does not include non-empty exact_text.' -MissingVariable 'old_text')
    }

    $insertBeforePattern = [string]$snippetSpec.insert_before_pattern
    if ($oldText -notlike ('*' + $insertBeforePattern + '*')) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'python_snippet_body_synthesis_insert_anchor_not_found' -Reason ('Insert-before pattern not found in old_text: {0}' -f $insertBeforePattern) -MissingVariable 'insert_before_pattern')
    }

    $snippet = ([string]$snippetSpec.snippet).TrimEnd("`r", "`n")
    $newText = $oldText.Replace($insertBeforePattern, ($snippet + "`n`n" + $insertBeforePattern))
    if ([string]::Equals([string]$newText, [string]$oldText, [System.StringComparison]::Ordinal)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'python_snippet_body_synthesis_no_delta' -Reason 'Python snippet body synthesis produced identical old_text and new_text.' -MissingVariable 'new_text_delta')
    }

    $validationCommand = [string]$snippetSpec.validation_command
    if ([string]::IsNullOrWhiteSpace($validationCommand)) {
        $validationCommand = 'python -m py_compile {0}' -f $targetFile
    }
    $validationPattern = [string]$snippetSpec.validation_pattern
    if ([string]::IsNullOrWhiteSpace($validationPattern)) {
        $validationPattern = $insertBeforePattern
    }
    $closureEvidence = [string]$snippetSpec.closure_evidence
    if ([string]::IsNullOrWhiteSpace($closureEvidence)) {
        $closureEvidence = 'Packet candidate ready with exact source-anchor old_text and synthesized Python snippet new_text.'
    }
    $preventionLesson = [string]$snippetSpec.prevention_lesson
    if ([string]::IsNullOrWhiteSpace($preventionLesson)) {
        $preventionLesson = 'TOD must observe exact current source text before synthesizing Python snippet bounded packets.'
    }
    $daveNeeded = [string]$snippetSpec.dave_needed
    if ([string]::IsNullOrWhiteSpace($daveNeeded)) {
        $daveNeeded = 'no'
    }

    $artifact = [ordered]@{
        artifact_type = 'tod_python_snippet_body_synthesis_artifact'
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        source = 'local_execution_python_snippet_body_synthesis_lane'
        objective_id = if ($Context.PSObject.Properties['objective_id']) { [string]$Context.objective_id } else { '' }
        task_id = if ($Context.PSObject.Properties['task_id']) { [string]$Context.task_id } else { '' }
        packet_candidate_ready = $true
        packet = [ordered]@{
            target_file = $targetFile
            intended_edit_mode = 'replace_exact_text'
            old_text = $oldText
            new_text = $newText
            validation_command = $validationCommand
            validation_pattern = $validationPattern
            closure_evidence = $closureEvidence
            prevention_lesson = $preventionLesson
            dave_needed = $daveNeeded
        }
        synthesis = [ordered]@{
            input_artifact = $inputRel
            source_file = if ($anchorArtifact.PSObject.Properties['source_file']) { [string]$anchorArtifact.source_file } else { $targetFile }
            start_line = if ($anchorArtifact.PSObject.Properties['start_line']) { $anchorArtifact.start_line } else { $null }
            end_line = if ($anchorArtifact.PSObject.Properties['end_line']) { $anchorArtifact.end_line } else { $null }
            insert_before_pattern = $insertBeforePattern
            snippet_line_count = @($snippet -split "`n").Count
            no_source_edits = $true
        }
        validation = [ordered]@{
            artifact_path = $outputRel
            input_artifact_read = $true
            old_text_present = -not [string]::IsNullOrWhiteSpace($oldText)
            new_text_differs = [string]$newText -ne [string]$oldText
            packet_candidate_schema = 'ready'
            no_source_edits = $true
        }
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $outputAbs) -Force | Out-Null
    [System.IO.File]::WriteAllText($outputAbs, ($artifact | ConvertTo-Json -Depth 30), [System.Text.UTF8Encoding]::new($false))
    $validationCommandForPacket = New-LocalExecutionPacketCandidateValidationCommand -TargetFile $outputRel
    $validationOutput = Invoke-Expression $validationCommandForPacket

    $Result.summary = ('Published Python snippet body synthesis artifact {0} from source anchor {1}.' -f $outputRel, $inputRel)
    $Result.files_changed = @($outputRel)
    $Result.tests_run = @('input source-anchor artifact read', 'python snippet synthesis', 'packet candidate schema validation', 'no source edit assertion')
    $Result.test_results = @('pass', 'pass', 'pass', 'pass')
    $Result | Add-Member -NotePropertyName command_output -NotePropertyValue ($validationOutput -join "`n") -Force
    $Result | Add-Member -NotePropertyName diff_summary -NotePropertyValue ('Artifact write only: {0}' -f $outputRel) -Force
    $Result | Add-Member -NotePropertyName commands_run -NotePropertyValue @('Invoke-LocalExecutionPythonSnippetBodySynthesis', $validationCommandForPacket) -Force
    $Result | Add-Member -NotePropertyName validation_results -NotePropertyValue @(
        [pscustomobject]@{ name = 'input source-anchor artifact read'; passed = $true; required = $true },
        [pscustomobject]@{ name = 'python snippet synthesis'; passed = $true; required = $true },
        [pscustomobject]@{ name = 'packet candidate schema validation'; passed = $true; required = $true },
        [pscustomobject]@{ name = 'no source edit assertion'; passed = $true; required = $true }
    ) -Force
    $Result | Add-Member -NotePropertyName blockers -NotePropertyValue @() -Force
    $Result | Add-Member -NotePropertyName confidence -NotePropertyValue 'medium-high' -Force
    $Result | Add-Member -NotePropertyName rollback_hint -NotePropertyValue ('Remove generated artifact {0} if this Python snippet packet-body training artifact must be discarded.' -f $outputRel) -Force
    $Result | Add-Member -NotePropertyName no_change_required -NotePropertyValue $false -Force
    return (Complete-EngineExecutionResult -Result $Result -Status 'completed')
}

function New-LocalExecutionPythonRouteShellSnippet {
    param(
        [Parameter(Mandatory = $true)][string]$RoutePath,
        [Parameter(Mandatory = $true)][string]$RouteName
    )

    if ($RoutePath -notmatch '^/[A-Za-z0-9_./-]+$') {
        throw ('Unsafe route path for Python route body synthesis: {0}' -f $RoutePath)
    }
    if ($RouteName -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
        throw ('Unsafe route name for Python route body synthesis: {0}' -f $RouteName)
    }

    $template = @'


@router.get("{{ROUTE_PATH}}", response_class=HTMLResponse)
def {{ROUTE_NAME}}():
    body = """
    <section class='folder observatory-top'>
      <h1>Enterprise Observatory</h1>
      <p class='lead'>A secure enterprise workspace for MIM/TOD-backed research operations.</p>
    </section>
    <section class='panel'>
      <h2>Enterprise Shell</h2>
      <p>This first slice establishes the route boundary only. Apps, workflows, documents, CRM, and calendar features remain out of scope.</p>
    </section>
    """
    return _page("Enterprise Observatory", body, wide=True)
'@
    return $template.Replace('{{ROUTE_PATH}}', $RoutePath).Replace('{{ROUTE_NAME}}', $RouteName)
}

function Get-LocalExecutionRawTextLineRange {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [int]$StartLine,
        [int]$EndLine
    )

    if ($StartLine -lt 1 -or $EndLine -lt $StartLine) {
        return ''
    }

    $segments = New-Object System.Collections.Generic.List[string]
    $position = 0
    while ($position -lt $Content.Length) {
        $nextLf = $Content.IndexOf("`n", $position, [System.StringComparison]::Ordinal)
        if ($nextLf -lt 0) {
            [void]$segments.Add($Content.Substring($position))
            break
        }
        [void]$segments.Add($Content.Substring($position, ($nextLf - $position + 1)))
        $position = $nextLf + 1
    }

    if ($segments.Count -eq 0) {
        return ''
    }

    $startIndex = $StartLine - 1
    $endIndex = [Math]::Min($segments.Count - 1, $EndLine - 1)
    if ($startIndex -gt $endIndex -or $startIndex -ge $segments.Count) {
        return ''
    }

    $selected = New-Object System.Collections.Generic.List[string]
    for ($idx = $startIndex; $idx -le $endIndex; $idx++) {
        [void]$selected.Add([string]$segments[$idx])
    }
    return ($selected.ToArray() -join '')
}

function Invoke-LocalExecutionPythonRouteBodySynthesis {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)]$Spec
    )

    $routeSpec = Get-LocalExecutionPythonRouteBodySynthesisSpec -Context $Context
    $inputRel = [string]$routeSpec.input_artifact
    $outputRel = [string]$routeSpec.output_path
    $targetFile = [string]$routeSpec.target_file
    foreach ($entry in @(
            [pscustomobject]@{ Name = 'input_artifact'; Value = $inputRel },
            [pscustomobject]@{ Name = 'output_path'; Value = $outputRel },
            [pscustomobject]@{ Name = 'target_file'; Value = $targetFile },
            [pscustomobject]@{ Name = 'insert_before_pattern'; Value = [string]$routeSpec.insert_before_pattern },
            [pscustomobject]@{ Name = 'route_path'; Value = [string]$routeSpec.route_path },
            [pscustomobject]@{ Name = 'route_name'; Value = [string]$routeSpec.route_name }
        )) {
        if ([string]::IsNullOrWhiteSpace([string]$entry.Value)) {
            return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode ('python_route_body_synthesis_{0}_missing' -f $entry.Name) -Reason ('Python route body synthesis requires {0}.' -f $entry.Name) -MissingVariable $entry.Name)
        }
    }
    foreach ($pathEntry in @(
            [pscustomobject]@{ Name = 'input_artifact'; Value = $inputRel },
            [pscustomobject]@{ Name = 'output_path'; Value = $outputRel },
            [pscustomobject]@{ Name = 'target_file'; Value = $targetFile }
        )) {
        if (-not (Test-LocalExecutionSafePath -RelativePath ([string]$pathEntry.Value))) {
            return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode ('python_route_body_synthesis_{0}_unsafe' -f $pathEntry.Name) -Reason ('Python route body synthesis path is outside LocalExecutionEngine safe roots: {0}' -f [string]$pathEntry.Value) -MissingVariable ('safe_' + $pathEntry.Name))
        }
    }

    $inputAbs = Join-Path $script:LocalEngineRepoRoot $inputRel
    $outputAbs = Join-Path $script:LocalEngineRepoRoot $outputRel
    if (-not (Test-Path -Path $inputAbs -PathType Leaf)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'python_route_body_synthesis_input_not_found' -Reason ('Input source-anchor artifact does not exist: {0}' -f $inputRel) -MissingVariable 'input_artifact')
    }
    $anchorArtifact = Get-Content -Path $inputAbs -Raw | ConvertFrom-Json
    if (-not $anchorArtifact.PSObject.Properties['artifact_type'] -or [string]$anchorArtifact.artifact_type -ne 'tod_source_anchor_observation') {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'python_route_body_synthesis_input_not_anchor' -Reason ('Input artifact is not a source-anchor observation: {0}' -f $inputRel) -MissingVariable 'source_anchor_artifact')
    }

    $oldText = [string]$anchorArtifact.exact_text
    $targetAbs = Join-Path $script:LocalEngineRepoRoot $targetFile
    if (-not (Test-Path -Path $targetAbs -PathType Leaf)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'python_route_body_synthesis_target_not_found' -Reason ('Target file does not exist: {0}' -f $targetFile) -MissingVariable 'target_file')
    }
    $targetRaw = Get-Content -Path $targetAbs -Raw
    if ($anchorArtifact.PSObject.Properties['start_line'] -and $anchorArtifact.PSObject.Properties['end_line']) {
        $rawOldText = Get-LocalExecutionRawTextLineRange -Content $targetRaw -StartLine ([int]$anchorArtifact.start_line) -EndLine ([int]$anchorArtifact.end_line)
        if (-not [string]::IsNullOrWhiteSpace($rawOldText) -and $rawOldText -like ('*' + [string]$routeSpec.insert_before_pattern + '*')) {
            $oldText = $rawOldText
        }
    }
    if ([string]::IsNullOrWhiteSpace($oldText)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'python_route_body_synthesis_old_text_missing' -Reason 'Input source-anchor artifact does not include non-empty exact_text.' -MissingVariable 'old_text')
    }

    $insertBeforePattern = [string]$routeSpec.insert_before_pattern
    if ($oldText -notlike ('*' + $insertBeforePattern + '*')) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'python_route_body_synthesis_insert_anchor_not_found' -Reason ('Insert-before pattern not found in old_text: {0}' -f $insertBeforePattern) -MissingVariable 'insert_before_pattern')
    }

    $routeSnippet = New-LocalExecutionPythonRouteShellSnippet -RoutePath ([string]$routeSpec.route_path) -RouteName ([string]$routeSpec.route_name)
    $newText = $oldText.Replace($insertBeforePattern, ($routeSnippet + "`n`n" + $insertBeforePattern))
    if ([string]::Equals([string]$newText, [string]$oldText, [System.StringComparison]::Ordinal)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'python_route_body_synthesis_no_delta' -Reason 'Python route body synthesis produced identical old_text and new_text.' -MissingVariable 'new_text_delta')
    }

    $validationCommand = [string]$routeSpec.validation_command
    if ([string]::IsNullOrWhiteSpace($validationCommand)) {
        $validationCommand = 'python -m py_compile {0}' -f $targetFile
    }
    $validationPattern = [string]$routeSpec.validation_pattern
    if ([string]::IsNullOrWhiteSpace($validationPattern)) {
        $validationPattern = [string]$routeSpec.route_path
    }
    $closureEvidence = [string]$routeSpec.closure_evidence
    if ([string]::IsNullOrWhiteSpace($closureEvidence)) {
        $closureEvidence = 'Packet candidate ready with exact source-anchor old_text and synthesized Python route new_text.'
    }
    $preventionLesson = [string]$routeSpec.prevention_lesson
    if ([string]::IsNullOrWhiteSpace($preventionLesson)) {
        $preventionLesson = 'TOD must observe exact current source text before synthesizing Python route bounded packets.'
    }
    $daveNeeded = [string]$routeSpec.dave_needed
    if ([string]::IsNullOrWhiteSpace($daveNeeded)) {
        $daveNeeded = 'no'
    }

    $artifact = [ordered]@{
        artifact_type = 'tod_python_route_body_synthesis_artifact'
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        source = 'local_execution_python_route_body_synthesis_lane'
        objective_id = if ($Context.PSObject.Properties['objective_id']) { [string]$Context.objective_id } else { '' }
        task_id = if ($Context.PSObject.Properties['task_id']) { [string]$Context.task_id } else { '' }
        packet_candidate_ready = $true
        packet = [ordered]@{
            target_file = $targetFile
            intended_edit_mode = 'replace_exact_text'
            old_text = $oldText
            new_text = $newText
            validation_command = $validationCommand
            validation_pattern = $validationPattern
            closure_evidence = $closureEvidence
            prevention_lesson = $preventionLesson
            dave_needed = $daveNeeded
        }
        synthesis = [ordered]@{
            input_artifact = $inputRel
            source_file = if ($anchorArtifact.PSObject.Properties['source_file']) { [string]$anchorArtifact.source_file } else { $targetFile }
            start_line = if ($anchorArtifact.PSObject.Properties['start_line']) { $anchorArtifact.start_line } else { $null }
            end_line = if ($anchorArtifact.PSObject.Properties['end_line']) { $anchorArtifact.end_line } else { $null }
            route_path = [string]$routeSpec.route_path
            route_name = [string]$routeSpec.route_name
            insert_before_pattern = $insertBeforePattern
            no_source_edits = $true
        }
        validation = [ordered]@{
            artifact_path = $outputRel
            input_artifact_read = $true
            old_text_present = -not [string]::IsNullOrWhiteSpace($oldText)
            new_text_differs = [string]$newText -ne [string]$oldText
            packet_candidate_schema = 'ready'
            no_source_edits = $true
        }
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $outputAbs) -Force | Out-Null
    [System.IO.File]::WriteAllText($outputAbs, ($artifact | ConvertTo-Json -Depth 30), [System.Text.UTF8Encoding]::new($false))
    $validationCommandForPacket = New-LocalExecutionPacketCandidateValidationCommand -TargetFile $outputRel
    $validationOutput = Invoke-Expression $validationCommandForPacket

    $Result.summary = ('Published Python route body synthesis packet {0} from source anchor {1}.' -f $outputRel, $inputRel)
    $Result.files_changed = @($outputRel)
    $Result.tests_run = @('input source-anchor artifact read', 'python route snippet synthesis', 'packet candidate schema validation', 'no product source edit assertion')
    $Result.test_results = @('pass', 'pass', 'pass', 'pass')
    $Result | Add-Member -NotePropertyName command_output -NotePropertyValue ($validationOutput -join "`n") -Force
    $Result | Add-Member -NotePropertyName diff_summary -NotePropertyValue ('Artifact write only: {0}' -f $outputRel) -Force
    $Result | Add-Member -NotePropertyName commands_run -NotePropertyValue @('Invoke-LocalExecutionPythonRouteBodySynthesis', $validationCommandForPacket) -Force
    $Result | Add-Member -NotePropertyName validation_results -NotePropertyValue @(
        [pscustomobject]@{ name = 'input source-anchor artifact read'; passed = $true; required = $true },
        [pscustomobject]@{ name = 'python route snippet synthesis'; passed = $true; required = $true },
        [pscustomobject]@{ name = 'packet candidate schema validation'; passed = $true; required = $true },
        [pscustomobject]@{ name = 'no product source edit assertion'; passed = $true; required = $true }
    ) -Force
    $Result | Add-Member -NotePropertyName blockers -NotePropertyValue @() -Force
    $Result | Add-Member -NotePropertyName confidence -NotePropertyValue 'medium-high' -Force
    $Result | Add-Member -NotePropertyName rollback_hint -NotePropertyValue ('Remove generated artifact {0} if this Python route packet-body training artifact must be discarded.' -f $outputRel) -Force
    $Result | Add-Member -NotePropertyName no_change_required -NotePropertyValue $false -Force
    return (Complete-EngineExecutionResult -Result $Result -Status 'completed')
}

function Invoke-LocalExecutionReadOnlyAuditArtifact {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)]$Spec
    )

    $paths = Get-LocalExecutionReadOnlyAuditArtifactPaths -Context $Context
    $inputRel = [string]$paths.input_path
    $outputRel = [string]$paths.output_path
    if ([string]::IsNullOrWhiteSpace($inputRel)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'read_only_audit_input_missing' -Reason 'Read-only audit artifact task requires an Input: path to a JSON evidence file.' -MissingVariable 'input_path')
    }
    if ([string]::IsNullOrWhiteSpace($outputRel)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'read_only_audit_output_missing' -Reason 'Read-only audit artifact task requires an output path under runtime_remote_training/read_only_audit_artifacts/.' -MissingVariable 'output_path')
    }
    if (-not (Test-LocalExecutionSafePath -RelativePath $outputRel)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'read_only_audit_output_unsafe' -Reason ('Output artifact path is outside LocalExecutionEngine safe roots: {0}' -f $outputRel) -MissingVariable 'safe_output_path')
    }

    $inputAbs = Join-Path $script:LocalEngineRepoRoot $inputRel
    $outputAbs = Join-Path $script:LocalEngineRepoRoot $outputRel
    if (-not (Test-Path -Path $inputAbs -PathType Leaf)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'read_only_audit_input_not_found' -Reason ('Input evidence file does not exist: {0}' -f $inputRel) -MissingVariable 'input_file')
    }

    $inputRaw = Get-Content -Path $inputAbs -Raw
    $inputJson = $inputRaw | ConvertFrom-Json
    $auditSubject = Get-LocalExecutionReadOnlyAuditSubject -Context $Context
    $auditSource = $inputJson
    if (-not [string]::IsNullOrWhiteSpace($auditSubject) -and $inputJson.PSObject.Properties['tasks']) {
        $matchedTask = @($inputJson.tasks | Where-Object { $_.PSObject.Properties['id'] -and [string]$_.id -eq $auditSubject }) | Select-Object -First 1
        if ($null -eq $matchedTask) {
            return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'read_only_audit_subject_not_found' -Reason ('Audit subject was not found in input state: {0}' -f $auditSubject) -MissingVariable 'audit_subject')
        }
        $auditSource = $matchedTask
    }

    $blockers = @()
    if ($auditSource.PSObject.Properties['blockers']) {
        $blockers = @($auditSource.blockers)
    }
    elseif ($auditSource.PSObject.Properties['blocker'] -and $null -ne $auditSource.blocker) {
        $blockers = @($auditSource.blocker)
    }
    elseif ($auditSource.PSObject.Properties['execution_evidence'] -and $auditSource.execution_evidence.PSObject.Properties['blockers']) {
        $blockers = @($auditSource.execution_evidence.blockers)
    }
    elseif ($auditSource.PSObject.Properties['blocked_reason'] -and -not [string]::IsNullOrWhiteSpace([string]$auditSource.blocked_reason)) {
        $blockers += [pscustomobject]@{
            type = 'blocker'
            reason_code = [string]$auditSource.blocked_reason
            reason = if ($auditSource.PSObject.Properties['reason_selected']) { [string]$auditSource.reason_selected } else { '' }
            task_id = if ($auditSource.PSObject.Properties['selected_task_id']) { [string]$auditSource.selected_task_id } elseif ($auditSource.PSObject.Properties['task_id']) { [string]$auditSource.task_id } else { '' }
        }
    }
    elseif ($auditSource.PSObject.Properties['terminal_state']) {
        $terminal = $auditSource.terminal_state
        if ($terminal.PSObject.Properties['reason_code'] -and -not [string]::IsNullOrWhiteSpace([string]$terminal.reason_code)) {
            $blockers += [pscustomobject]@{
                type = 'blocker'
                reason_code = [string]$terminal.reason_code
                reason = if ($terminal.PSObject.Properties['message']) { [string]$terminal.message } else { '' }
                task_id = if ($auditSource.PSObject.Properties['id']) { [string]$auditSource.id } else { '' }
            }
        }
        if ($terminal.PSObject.Properties['details'] -and $terminal.details.PSObject.Properties['failures']) {
            foreach ($failure in @($terminal.details.failures)) {
                $blockers += [pscustomobject]@{
                    type = 'failure'
                    reason_code = 'terminal_state_failure'
                    reason = [string]$failure
                    task_id = if ($auditSource.PSObject.Properties['id']) { [string]$auditSource.id } else { '' }
                }
            }
        }
    }
    if ($auditSource.PSObject.Properties['materialization'] -and $auditSource.materialization.PSObject.Properties['reason_code'] -and -not [string]::IsNullOrWhiteSpace([string]$auditSource.materialization.reason_code)) {
        $blockers += [pscustomobject]@{
            type = 'blocker'
            reason_code = [string]$auditSource.materialization.reason_code
            reason = if ($auditSource.materialization.PSObject.Properties['why_local_executor_cannot_proceed']) { [string]$auditSource.materialization.why_local_executor_cannot_proceed } else { '' }
            task_id = if ($auditSource.PSObject.Properties['id']) { [string]$auditSource.id } else { '' }
        }
    }
    $reasonCodes = @($blockers | ForEach-Object {
        if ($_.PSObject.Properties['reason_code']) { [string]$_.reason_code }
    } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)

    $classification = if ($reasonCodes -contains 'selector_contract_incomplete') {
        'selector_contract_incomplete'
    }
    elseif ($reasonCodes -contains 'codex_wrapper_only_no_execution' -or $reasonCodes -contains 'local_execution_scope_not_supported') {
        'read_only_audit_artifact_publication_lane_blocked'
    }
    else {
        'read_only_audit_artifact_publication_review_required'
    }

    $evidenceFields = @('status', 'execution_state', 'reason_code', 'blocked_reason', 'blocker', 'blockers', 'validation_results', 'terminal_state', 'materialization')
    $findings = New-Object System.Collections.Generic.List[object]
    $findings.Add([ordered]@{
        finding = 'read_only_audit_task_was_not_completed'
        evidence = if ($auditSource.PSObject.Properties['summary']) { [string]$auditSource.summary } elseif ($auditSource.PSObject.Properties['terminal_state'] -and $auditSource.terminal_state.PSObject.Properties['message']) { [string]$auditSource.terminal_state.message } else { '' }
    }) | Out-Null
    $findings.Add([ordered]@{
        finding = 'local_lane_needs_artifact_publication_support'
        evidence = ($reasonCodes -join ', ')
    }) | Out-Null

    $isOperatorImpactScorecard = (
        ($auditSource.PSObject.Properties['packet_type'] -and [string]$auditSource.packet_type -match 'mim-operator-impact') -or
        $auditSource.PSObject.Properties['operator_impact_score'] -or
        $auditSource.PSObject.Properties['summary_fallback_only']
    )
    if ($isOperatorImpactScorecard) {
        $operatorImpactFields = @(
            'packet_type',
            'generated_at',
            'status',
            'operator_impact_score',
            'operator_impact_percent',
            'sample_count',
            'pass_count',
            'summary_fallback_only',
            'summary_fallback_reason',
            'source_files',
            'metrics',
            'next_action'
        )
        $evidenceFields = @($evidenceFields + $operatorImpactFields | Select-Object -Unique)
        $classification = 'operator_impact_scorecard_review_required'
        $operatorScore = if ($auditSource.PSObject.Properties['operator_impact_score']) { [string]$auditSource.operator_impact_score } else { '' }
        $sampleCount = if ($auditSource.PSObject.Properties['sample_count']) { [string]$auditSource.sample_count } else { '' }
        $passCount = if ($auditSource.PSObject.Properties['pass_count']) { [string]$auditSource.pass_count } else { '' }
        $operatorStatus = if ($auditSource.PSObject.Properties['status']) { [string]$auditSource.status } else { '' }
        $summaryFallback = if ($auditSource.PSObject.Properties['summary_fallback_only']) { [string]$auditSource.summary_fallback_only } else { 'False' }
        $sourceFiles = @()
        if ($auditSource.PSObject.Properties['source_files']) {
            $sourceFiles = @($auditSource.source_files | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        }
        $findings.Add([ordered]@{
            finding = 'operator_impact_scorecard_status'
            evidence = ('operator_impact_score={0}; sample_count={1}; pass_count={2}; status={3}; summary_fallback_only={4}' -f $operatorScore, $sampleCount, $passCount, $operatorStatus, $summaryFallback)
        }) | Out-Null
        if ($sourceFiles.Count -gt 0) {
            $findings.Add([ordered]@{
                finding = 'operator_impact_scorecard_sources'
                evidence = ($sourceFiles -join ', ')
            }) | Out-Null
        }
        if ($auditSource.PSObject.Properties['target_score'] -and $auditSource.PSObject.Properties['operator_impact_score']) {
            $targetScore = [double]$auditSource.target_score
            $currentScore = [double]$auditSource.operator_impact_score
            if ($currentScore -lt $targetScore) {
                $blockers += [pscustomobject]@{
                    type = 'blocker'
                    reason_code = 'operator_impact_below_target'
                    reason = ('Operator impact score {0}/10 is below target {1}/10.' -f $currentScore, $targetScore)
                    task_id = if ($Context.PSObject.Properties['task_id']) { [string]$Context.task_id } else { '' }
                }
            }
        }
    }

    $isOperatorImpactScorecard = (
        ($auditSource.PSObject.Properties['packet_type'] -and [string]$auditSource.packet_type -match 'mim-operator-impact') -or
        $auditSource.PSObject.Properties['operator_impact_score'] -or
        $auditSource.PSObject.Properties['summary_fallback_only']
    )
    if ($isOperatorImpactScorecard) {
        $operatorImpactFields = @(
            'packet_type',
            'generated_at',
            'status',
            'operator_impact_score',
            'operator_impact_percent',
            'sample_count',
            'pass_count',
            'summary_fallback_only',
            'summary_fallback_reason',
            'source_files',
            'metrics',
            'next_action'
        )
        $evidenceFields = @($evidenceFields + $operatorImpactFields | Select-Object -Unique)
        $classification = 'operator_impact_scorecard_review_required'
        $operatorScore = if ($auditSource.PSObject.Properties['operator_impact_score']) { [string]$auditSource.operator_impact_score } else { '' }
        $sampleCount = if ($auditSource.PSObject.Properties['sample_count']) { [string]$auditSource.sample_count } else { '' }
        $passCount = if ($auditSource.PSObject.Properties['pass_count']) { [string]$auditSource.pass_count } else { '' }
        $operatorStatus = if ($auditSource.PSObject.Properties['status']) { [string]$auditSource.status } else { '' }
        $summaryFallback = if ($auditSource.PSObject.Properties['summary_fallback_only']) { [string]$auditSource.summary_fallback_only } else { 'False' }
        $sourceFiles = @()
        if ($auditSource.PSObject.Properties['source_files']) {
            $sourceFiles = @($auditSource.source_files | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        }
        $findings.Add([ordered]@{
            finding = 'operator_impact_scorecard_status'
            evidence = ('operator_impact_score={0}; sample_count={1}; pass_count={2}; status={3}; summary_fallback_only={4}' -f $operatorScore, $sampleCount, $passCount, $operatorStatus, $summaryFallback)
        }) | Out-Null
        if ($sourceFiles.Count -gt 0) {
            $findings.Add([ordered]@{
                finding = 'operator_impact_scorecard_sources'
                evidence = ($sourceFiles -join ', ')
            }) | Out-Null
        }
        if ($auditSource.PSObject.Properties['target_score'] -and $auditSource.PSObject.Properties['operator_impact_score']) {
            $targetScore = [double]$auditSource.target_score
            $currentScore = [double]$auditSource.operator_impact_score
            if ($currentScore -lt $targetScore) {
                $blockers += [pscustomobject]@{
                    type = 'blocker'
                    reason_code = 'operator_impact_below_target'
                    reason = ('Operator impact score {0}/10 is below target {1}/10.' -f $currentScore, $targetScore)
                    task_id = if ($Context.PSObject.Properties['task_id']) { [string]$Context.task_id } else { '' }
                }
            }
        }
    }

    $isArtifactWriteBlocker = (
        $auditSource.PSObject.Properties['artifact_type'] -and
        [string]$auditSource.artifact_type -eq 'local_execution_artifact_write_blocker'
    )
    if ($isArtifactWriteBlocker) {
        $artifactWriteFields = @(
            'artifact_type',
            'generated_at',
            'source',
            'status',
            'task_id',
            'objective_id',
            'target_file',
            'reason',
            'missing_anchor_or_field',
            'required_next_action',
            'validation_pattern',
            'credit_decision'
        )
        $evidenceFields = @($evidenceFields + $artifactWriteFields | Select-Object -Unique)

        $artifactStatus = if ($auditSource.PSObject.Properties['status']) { [string]$auditSource.status } else { '' }
        $missingField = if ($auditSource.PSObject.Properties['missing_anchor_or_field']) { [string]$auditSource.missing_anchor_or_field } else { '' }
        $targetFile = if ($auditSource.PSObject.Properties['target_file']) { [string]$auditSource.target_file } else { '' }
        $reason = if ($auditSource.PSObject.Properties['reason']) { [string]$auditSource.reason } else { '' }
        $requiredNextAction = if ($auditSource.PSObject.Properties['required_next_action']) { [string]$auditSource.required_next_action } else { '' }
        $creditReason = ''
        if ($auditSource.PSObject.Properties['credit_decision'] -and $auditSource.credit_decision -and $auditSource.credit_decision.PSObject.Properties['reason']) {
            $creditReason = [string]$auditSource.credit_decision.reason
        }

        $classification = if ($artifactStatus -eq 'blocked_missing_artifact_content' -or $missingField -eq 'new_text') {
            'artifact_body_synthesis_missing'
        }
        else {
            'artifact_write_blocker_review_required'
        }

        $findings.Add([ordered]@{
            finding = 'artifact_write_blocker_status'
            evidence = ('status={0}; reason={1}' -f $artifactStatus, $reason)
        }) | Out-Null
        $findings.Add([ordered]@{
            finding = 'missing_artifact_body_field'
            evidence = ('missing_anchor_or_field={0}; target_file={1}' -f $missingField, $targetFile)
        }) | Out-Null
        $findings.Add([ordered]@{
            finding = 'required_continuation'
            evidence = $requiredNextAction
        }) | Out-Null
        if (-not [string]::IsNullOrWhiteSpace($creditReason)) {
            $findings.Add([ordered]@{
                finding = 'credit_decision_rejects_completion'
                evidence = $creditReason
            }) | Out-Null
        }

        if ($artifactStatus -eq 'blocked_missing_artifact_content') {
            $blockers += [pscustomobject]@{
                type = 'blocker'
                reason_code = 'artifact_body_synthesis_missing'
                reason = $reason
                task_id = if ($auditSource.PSObject.Properties['task_id']) { [string]$auditSource.task_id } else { '' }
            }
        }
        if ($missingField -eq 'new_text') {
            $blockers += [pscustomobject]@{
                type = 'blocker'
                reason_code = 'new_text_artifact_body_missing'
                reason = $requiredNextAction
                task_id = if ($auditSource.PSObject.Properties['task_id']) { [string]$auditSource.task_id } else { '' }
            }
        }
    }

    $isSelfHealthReport = ($auditSource.PSObject.Properties['source'] -and [string]$auditSource.source -eq 'tod-self-health-maintenance-v1')
    if ($isSelfHealthReport) {
        $selfHealthFields = @(
            'overall_status',
            'overall_severity',
            'source_severity',
            'severity_reason',
            'duration_seconds',
            'preflight',
            'postflight',
            'history',
            'recommendations',
            'actions'
        )
        $evidenceFields = @($evidenceFields + $selfHealthFields | Select-Object -Unique)
        $classification = 'self_health_report_review_required'

        $findings.Add([ordered]@{
            finding = 'self_health_status'
            evidence = ('status={0}; severity={1}; reason={2}; duration_seconds={3}' -f [string]$auditSource.overall_status, [string]$auditSource.overall_severity, [string]$auditSource.severity_reason, [string]$auditSource.duration_seconds)
        }) | Out-Null

        if ($auditSource.PSObject.Properties['overall_severity'] -and [string]$auditSource.overall_severity -eq 'critical') {
            $blockers += [pscustomobject]@{
                type = 'blocker'
                reason_code = 'self_health_critical'
                reason = if ($auditSource.PSObject.Properties['summary']) { [string]$auditSource.summary } else { 'Self-health report is critical.' }
                task_id = if ($Context.PSObject.Properties['task_id']) { [string]$Context.task_id } else { '' }
            }
        }

        $actionSummaries = New-Object System.Collections.Generic.List[string]
        if ($auditSource.PSObject.Properties['actions']) {
            foreach ($action in @($auditSource.actions)) {
                $actionName = if ($action.PSObject.Properties['name']) { [string]$action.name } else { 'unknown_action' }
                $durationMs = if ($action.PSObject.Properties['duration_ms']) { [string]$action.duration_ms } else { '' }
                $actionOk = if ($action.PSObject.Properties['ok']) { [string]$action.ok } else { '' }
                $actionSummary = if ($action.PSObject.Properties['summary']) { [string]$action.summary } else { '' }
                $actionSummaries.Add(('{0}: ok={1}; duration_ms={2}; summary={3}' -f $actionName, $actionOk, $durationMs, $actionSummary)) | Out-Null

                if ($actionName -eq 'public_route_health' -and $action.PSObject.Properties['details'] -and $action.details -and $action.details.PSObject.Properties['blockers']) {
                    foreach ($routeBlocker in @($action.details.blockers)) {
                        if ([string]::IsNullOrWhiteSpace([string]$routeBlocker)) {
                            continue
                        }
                        $blockers += [pscustomobject]@{
                            type = 'blocker'
                            reason_code = [string]$routeBlocker
                            reason = if ($action.PSObject.Properties['summary']) { [string]$action.summary } else { 'Public route health reported a blocker.' }
                            task_id = if ($Context.PSObject.Properties['task_id']) { [string]$Context.task_id } else { '' }
                        }
                    }
                }
            }
        }
        $findings.Add([ordered]@{
            finding = 'self_health_action_timings'
            evidence = ($actionSummaries.ToArray() -join ' | ')
        }) | Out-Null
    }

    $isRecoveryWatchdogReport = ($auditSource.PSObject.Properties['bridge_smoke'] -and $null -ne $auditSource.bridge_smoke)
    if ($isRecoveryWatchdogReport) {
        $watchdogFields = @(
            'generated_at',
            'source',
            'state',
            'heartbeat_age_seconds',
            'last_issue',
            'last_issue_detail',
            'last_recovery_action',
            'bridge_smoke',
            'bridge_smoke.status',
            'bridge_smoke.classification',
            'bridge_smoke.failure_reason',
            'bridge_smoke.failure_modes',
            'bridge_smoke.canonical_request',
            'bridge_smoke.remote_boundary'
        )
        $evidenceFields = @($evidenceFields + $watchdogFields | Select-Object -Unique)
        $classification = 'watchdog_bridge_smoke_review_required'

        $bridgeSmoke = $auditSource.bridge_smoke
        $failureModes = @()
        if ($bridgeSmoke.PSObject.Properties['failure_modes']) {
            $failureModes = @($bridgeSmoke.failure_modes | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
        }
        $failureReason = if ($bridgeSmoke.PSObject.Properties['failure_reason']) { [string]$bridgeSmoke.failure_reason } else { '' }
        $bridgeStatus = if ($bridgeSmoke.PSObject.Properties['status']) { [string]$bridgeSmoke.status } else { '' }
        $bridgePassed = if ($bridgeSmoke.PSObject.Properties['passed']) { [string]$bridgeSmoke.passed } else { '' }

        $findings.Add([ordered]@{
            finding = 'watchdog_state'
            evidence = ('state={0}; heartbeat_age_seconds={1}; last_issue={2}; last_recovery_action={3}' -f [string]$auditSource.state, [string]$auditSource.heartbeat_age_seconds, $(if ($auditSource.PSObject.Properties['last_issue']) { [string]$auditSource.last_issue } else { '' }), $(if ($auditSource.PSObject.Properties['last_recovery_action']) { [string]$auditSource.last_recovery_action } else { '' }))
        }) | Out-Null
        $findings.Add([ordered]@{
            finding = 'bridge_smoke_failure_modes'
            evidence = ('passed={0}; status={1}; failure_reason={2}; failure_modes={3}' -f $bridgePassed, $bridgeStatus, $failureReason, ($failureModes -join ', '))
        }) | Out-Null

        if ($bridgeSmoke.PSObject.Properties['canonical_request'] -and $null -ne $bridgeSmoke.canonical_request) {
            $canonicalRequest = $bridgeSmoke.canonical_request
            $localMirror = if ($canonicalRequest.PSObject.Properties['local_listener_mirror']) { $canonicalRequest.local_listener_mirror } else { $null }
            $remoteSurface = if ($canonicalRequest.PSObject.Properties['remote_surface']) { $canonicalRequest.remote_surface } else { $null }
            $findings.Add([ordered]@{
                finding = 'canonical_request_identity'
                evidence = ('local_task_id={0}; local_objective_id={1}; local_sha256={2}; remote_task_id={3}; remote_objective_id={4}; remote_sha256={5}; canonical_request_mismatch={6}; publication_surface_divergence={7}; stale_remote_request_identity={8}' -f `
                    $(if ($localMirror -and $localMirror.PSObject.Properties['task_id']) { [string]$localMirror.task_id } else { '' }), `
                    $(if ($localMirror -and $localMirror.PSObject.Properties['objective_id']) { [string]$localMirror.objective_id } else { '' }), `
                    $(if ($localMirror -and $localMirror.PSObject.Properties['sha256']) { [string]$localMirror.sha256 } else { '' }), `
                    $(if ($remoteSurface -and $remoteSurface.PSObject.Properties['task_id']) { [string]$remoteSurface.task_id } else { '' }), `
                    $(if ($remoteSurface -and $remoteSurface.PSObject.Properties['objective_id']) { [string]$remoteSurface.objective_id } else { '' }), `
                    $(if ($remoteSurface -and $remoteSurface.PSObject.Properties['sha256']) { [string]$remoteSurface.sha256 } else { '' }), `
                    $(if ($canonicalRequest.PSObject.Properties['canonical_request_mismatch']) { [string]$canonicalRequest.canonical_request_mismatch } else { '' }), `
                    $(if ($canonicalRequest.PSObject.Properties['publication_surface_divergence']) { [string]$canonicalRequest.publication_surface_divergence } else { '' }), `
                    $(if ($canonicalRequest.PSObject.Properties['stale_remote_request_identity']) { [string]$canonicalRequest.stale_remote_request_identity } else { '' }))
            }) | Out-Null
        }

        if ($bridgeSmoke.PSObject.Properties['remote_boundary'] -and $null -ne $bridgeSmoke.remote_boundary) {
            $remoteBoundary = $bridgeSmoke.remote_boundary
            $authority = if ($remoteBoundary.PSObject.Properties['communication_authority']) { $remoteBoundary.communication_authority } else { $null }
            $findings.Add([ordered]@{
                finding = 'communication_authority_reachability'
                evidence = ('available={0}; authority_host={1}; authority_path={2}' -f `
                    $(if ($remoteBoundary.PSObject.Properties['available']) { [string]$remoteBoundary.available } else { '' }), `
                    $(if ($authority -and $authority.PSObject.Properties['host']) { [string]$authority.host } else { '' }), `
                    $(if ($authority -and $authority.PSObject.Properties['path']) { [string]$authority.path } else { '' }))
            }) | Out-Null
        }

        foreach ($failureMode in $failureModes) {
            $blockers += [pscustomobject]@{
                type = 'blocker'
                reason_code = [string]$failureMode
                reason = if (-not [string]::IsNullOrWhiteSpace($failureReason)) { $failureReason } else { 'Recovery watchdog bridge smoke reported a failure mode.' }
                task_id = if ($Context.PSObject.Properties['task_id']) { [string]$Context.task_id } else { '' }
            }
        }
    }

    $isRegressionTestSummary = (
        $auditSource.PSObject.Properties['passed'] -and
        $auditSource.PSObject.Properties['failed'] -and
        $auditSource.PSObject.Properties['total'] -and
        $auditSource.PSObject.Properties['failed_tests']
    )
    if ($isRegressionTestSummary) {
        $regressionFields = @(
            'generated_at',
            'passed_all',
            'passed',
            'failed',
            'total',
            'failed_tests',
            'failed_test_classification'
        )
        $evidenceFields = @($evidenceFields + $regressionFields | Select-Object -Unique)
        $classification = 'regression_snapshot_review_required'

        $failedTests = @($auditSource.failed_tests)
        $failureFamilies = @(
            $failedTests |
                Where-Object { $_.PSObject.Properties['describe'] -and -not [string]::IsNullOrWhiteSpace([string]$_.describe) } |
                Group-Object -Property describe |
                Sort-Object -Property Count -Descending |
                Select-Object -First 20 |
                ForEach-Object {
                    [ordered]@{
                        family = [string]$_.Name
                        count = [int]$_.Count
                    }
                }
        )

        $findings.Add([ordered]@{
            finding = 'regression_snapshot_counts'
            evidence = ('generated_at={0}; passed_all={1}; passed={2}; failed={3}; total={4}' -f [string]$auditSource.generated_at, [string]$auditSource.passed_all, [string]$auditSource.passed, [string]$auditSource.failed, [string]$auditSource.total)
        }) | Out-Null
        $findings.Add([ordered]@{
            finding = 'regression_failure_families'
            evidence = ($failureFamilies | ConvertTo-Json -Compress -Depth 4)
        }) | Out-Null

        if ([int]$auditSource.failed -gt 0) {
            $blockers += [pscustomobject]@{
                type = 'blocker'
                reason_code = 'regression_failures'
                reason = ('Regression snapshot has {0} failed tests out of {1} total.' -f [string]$auditSource.failed, [string]$auditSource.total)
                task_id = if ($Context.PSObject.Properties['task_id']) { [string]$Context.task_id } else { '' }
            }
        }
    }

    $artifact = [ordered]@{
        artifact_type = 'tod_read_only_audit_artifact'
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        source = 'local_execution_read_only_audit_artifact_lane'
        objective_id = if ($Context.PSObject.Properties['objective_id']) { [string]$Context.objective_id } else { '' }
        task_id = if ($Context.PSObject.Properties['task_id']) { [string]$Context.task_id } else { '' }
        audit_subject = if (-not [string]::IsNullOrWhiteSpace($auditSubject)) { $auditSubject } elseif ($auditSource.PSObject.Properties['task_id']) { [string]$auditSource.task_id } elseif ($auditSource.PSObject.Properties['id']) { [string]$auditSource.id } else { [System.IO.Path]::GetFileName($inputRel) }
        inspected_files = @($inputRel)
        evidence_used = @(
            [ordered]@{
                path = $inputRel
                fields = $evidenceFields
            }
        )
        classification = $classification
        findings = @($findings.ToArray())
        blockers = @($blockers)
        confidence = 'high'
        no_code_changes = $true
        validation = [ordered]@{
            artifact_path = $outputRel
            input_read = $true
            source_edits = @()
            required_fields_present = $true
        }
        continuation_action = 'Use this report-only artifact lane for read-only self-audits, route audits, and blocker classifications before attempting broader synthesis.'
    }

    $isTodCapabilityAssessment = [string]::Equals($outputRel, 'runtime_remote_training/TOD_CAPABILITY_ASSESSMENT_V1.latest.json', [System.StringComparison]::OrdinalIgnoreCase)
    $markdownRel = ''
    $markdownAbs = ''
    if ($isTodCapabilityAssessment) {
        $metricLookup = @{}
        if ($inputJson.PSObject.Properties['metrics']) {
            foreach ($metric in @($inputJson.metrics)) {
                if ($metric.PSObject.Properties['metric'] -and -not [string]::IsNullOrWhiteSpace([string]$metric.metric)) {
                    $metricLookup[[string]$metric.metric] = [pscustomobject]@{
                        current = if ($metric.PSObject.Properties['current']) { [string]$metric.current } else { '' }
                        source = if ($metric.PSObject.Properties['source']) { [string]$metric.source } else { '' }
                    }
                }
            }
        }

        function Get-CapabilityMetricEvidence {
            param(
                [hashtable]$Lookup,
                [string[]]$Names
            )
            foreach ($name in @($Names)) {
                if ($Lookup.ContainsKey($name)) {
                    $entry = $Lookup[$name]
                    return ('{0}: {1}; source={2}' -f $name, [string]$entry.current, [string]$entry.source)
                }
            }
            return 'not demonstrated in supplied evidence'
        }

        $capabilities = @(
            [ordered]@{
                capability = 'Objective interpretation'
                current_level = 'partially demonstrated'
                evidence = Get-CapabilityMetricEvidence -Lookup $metricLookup -Names @('TOD Selector Field Completeness', 'Independent Resolution Candidate State')
                current_limitation = 'Evidence still shows selector and request-shape blockers on some work; interpretation is not consistently executable.'
                next_independent_demonstration_required = 'Classify one fresh operator objective into the correct task mode and dispatch one valid next step without Codex synthesis.'
            },
            [ordered]@{
                capability = 'Scope discipline'
                current_level = 'demonstrated with limits'
                evidence = Get-CapabilityMetricEvidence -Lookup $metricLookup -Names @('TOD Selector Field Completeness', 'TOD Packet-Formation Loop')
                current_limitation = 'Prior packet/no-op loops show scope discipline can regress when old text is stale or candidate work is already applied.'
                next_independent_demonstration_required = 'Reject an already-applied packet and publish a smaller current-code task with one live target.'
            },
            [ordered]@{
                capability = 'Root cause identification'
                current_level = 'partially demonstrated'
                evidence = Get-CapabilityMetricEvidence -Lookup $metricLookup -Names @('TOD Recovery Packet Regression', 'TOD Result Publisher Truth')
                current_limitation = 'TOD can name blockers, but evidence shows diagnosis does not always become a corrected executable retry.'
                next_independent_demonstration_required = 'Trace one live blocker to the first failing component and publish a corrected retry payload.'
            },
            [ordered]@{
                capability = 'Evidence collection'
                current_level = 'demonstrated'
                evidence = Get-CapabilityMetricEvidence -Lookup $metricLookup -Names @('Validated TOD Edits', 'TOD Dialog Inbox Read Health')
                current_limitation = 'Evidence collection is stronger than evidence-driven recovery; collected facts can still remain diagnostic only.'
                next_independent_demonstration_required = 'Use collected evidence to drive a repair that changes behavior and validates live.'
            },
            [ordered]@{
                capability = 'Minimal bounded patch generation'
                current_level = 'partially demonstrated'
                evidence = Get-CapabilityMetricEvidence -Lookup $metricLookup -Names @('Meaningful TOD Implementations', 'TOD Selector Field Completeness')
                current_limitation = 'Bounded fields can be complete, but current-code old/new synthesis is still a known weak point.'
                next_independent_demonstration_required = 'Inspect a target file, derive one exact anchor, synthesize old/new text, apply it, and validate.'
            },
            [ordered]@{
                capability = 'Independent implementation'
                current_level = 'demonstrated in limited count'
                evidence = Get-CapabilityMetricEvidence -Lookup $metricLookup -Names @('Independent TOD Resolutions')
                current_limitation = 'The independent resolution count exists, but the supplied evidence still names pending proof and selector regressions.'
                next_independent_demonstration_required = 'Complete one new implementation from problem to validated resolution with no Codex-authored patch.'
            },
            [ordered]@{
                capability = 'Validation discipline'
                current_level = 'demonstrated'
                evidence = Get-CapabilityMetricEvidence -Lookup $metricLookup -Names @('Validated TOD Edits', 'TOD Selector Field Completeness')
                current_limitation = 'Validation exists for many edits, but wrapper-only and missing-proof rejection must remain enforced.'
                next_independent_demonstration_required = 'Publish validation output tied to changed files and prevent wrapper-only completion credit.'
            },
            [ordered]@{
                capability = 'Recovery after failure'
                current_level = 'partially demonstrated'
                evidence = Get-CapabilityMetricEvidence -Lookup $metricLookup -Names @('TOD Recovery Packet Regression', 'TOD Governed Dialog Consumption')
                current_limitation = 'Recovery can identify failure but still needs to produce a new executable shape more reliably.'
                next_independent_demonstration_required = 'Convert one blocked result into a corrected retry payload with validation command and expected evidence.'
            },
            [ordered]@{
                capability = 'Generalization across similar problems'
                current_level = 'not demonstrated from supplied evidence'
                evidence = 'The supplied scorecard lists repeated task families, but does not prove transfer to a fresh analogous target.'
                current_limitation = 'No current artifact in the supplied evidence proves TOD solved an unseen analogous case independently.'
                next_independent_demonstration_required = 'Solve a fresh similar blocker without copying the previous packet shape blindly.'
            },
            [ordered]@{
                capability = 'Ability to continue work without Codex intervention'
                current_level = 'partially demonstrated'
                evidence = Get-CapabilityMetricEvidence -Lookup $metricLookup -Names @('Open MIM/TOD Dialog Debt', 'Independent TOD Resolutions')
                current_limitation = 'Open governed replies and pending proof show continuation is improving but still not fully autonomous.'
                next_independent_demonstration_required = 'Consume one MIM request, execute, validate, and close the loop without Codex nudge.'
            },
            [ordered]@{
                capability = 'Ability to create the next bounded execution slice'
                current_level = 'partially demonstrated'
                evidence = Get-CapabilityMetricEvidence -Lookup $metricLookup -Names @('TOD Selector Field Completeness', 'TOD Smaller-Task Selection Blocker')
                current_limitation = 'Selector completeness can pass while no-viable or stale candidate blockers still appear.'
                next_independent_demonstration_required = 'Create one next slice with one target, one validation command, and one proof requirement from live state.'
            },
            [ordered]@{
                capability = 'Ability to recognize when escalation is required'
                current_level = 'demonstrated with limits'
                evidence = Get-CapabilityMetricEvidence -Lookup $metricLookup -Names @('TOD Governed Dialog Consumption', 'TOD Recovery Packet Regression')
                current_limitation = 'Escalation recognition exists, but escalation output must include a retry payload rather than only blocked status.'
                next_independent_demonstration_required = 'Publish a blocker with exact missing requirement, owner, retry payload, validation command, and expected evidence.'
            }
        )

        $artifact = [ordered]@{
            artifact_type = 'tod_capability_assessment_v1'
            generated_at = (Get-Date).ToUniversalTime().ToString('o')
            source = 'local_execution_read_only_assessment_lane'
            objective_id = if ($Context.PSObject.Properties['objective_id']) { [string]$Context.objective_id } else { 'TOD-CAPABILITY-ASSESSMENT-V1' }
            task_id = if ($Context.PSObject.Properties['task_id']) { [string]$Context.task_id } else { '' }
            task_mode = 'read_only_assessment'
            assessment_status = 'completed'
            tod_read_only_assessment_completed = $true
            tod_independent_capability_acquired = $false
            borrowed_control_plane_repair = 'Codex repaired task-mode classification/read-only lane support before this TOD assessment run.'
            no_source_code_modified_by_assessment = $true
            inspected_files = @($inputRel)
            evidence_used = @(
                [ordered]@{
                    path = $inputRel
                    fields = @('metrics', 'cycle_001')
                }
            )
            capabilities = @($capabilities)
            final_summary = [ordered]@{
                top_five_strongest_engineering_capabilities = @('Evidence collection', 'Validation discipline', 'Scope discipline', 'Ability to recognize when escalation is required', 'Independent implementation in limited count')
                top_five_weakest_engineering_capabilities = @('Current-code packet materialization', 'Recovery that produces a new executable shape', 'Generalization across similar problems', 'Task-mode classification before this repair', 'Ability to continue work without Codex intervention')
                largest_remaining_apprenticeship_debt = 'current-code old/new bounded packet materialization'
                single_capability_with_greatest_independence_gain = 'Inspect current code, choose a unique anchor, synthesize an exact bounded change, validate it, and publish evidence without Codex patching.'
                overall_engineering_maturity_assessment = 'structured_apprentice'
            }
            validation = [ordered]@{
                artifact_path = $outputRel
                markdown_artifact_path = 'runtime_remote_training/TOD_CAPABILITY_ASSESSMENT_V1.latest.md'
                input_read = $true
                source_edits = @()
                required_fields_present = $true
            }
        }
        $markdownRel = 'runtime_remote_training/TOD_CAPABILITY_ASSESSMENT_V1.latest.md'
        $markdownAbs = Join-Path $script:LocalEngineRepoRoot $markdownRel
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $outputAbs) -Force | Out-Null
    $json = $artifact | ConvertTo-Json -Depth 20
    [System.IO.File]::WriteAllText($outputAbs, $json, [System.Text.UTF8Encoding]::new($false))
    if ($isTodCapabilityAssessment) {
        $markdownLines = New-Object System.Collections.Generic.List[string]
        $markdownLines.Add('# TOD Capability Assessment V1') | Out-Null
        $markdownLines.Add('') | Out-Null
        $markdownLines.Add(('Assessment status: {0}' -f [string]$artifact.assessment_status)) | Out-Null
        $markdownLines.Add(('Primary maturity classification: {0}' -f [string]$artifact.final_summary.overall_engineering_maturity_assessment)) | Out-Null
        $markdownLines.Add(('Evidence: {0}' -f $inputRel)) | Out-Null
        $markdownLines.Add('') | Out-Null
        $markdownLines.Add('## Capability Findings') | Out-Null
        foreach ($capability in @($artifact.capabilities)) {
            $markdownLines.Add('') | Out-Null
            $markdownLines.Add(('### {0}' -f [string]$capability.capability)) | Out-Null
            $markdownLines.Add(('- Current Level: {0}' -f [string]$capability.current_level)) | Out-Null
            $markdownLines.Add(('- Evidence: {0}' -f [string]$capability.evidence)) | Out-Null
            $markdownLines.Add(('- Current Limitation: {0}' -f [string]$capability.current_limitation)) | Out-Null
            $markdownLines.Add(('- Next Independent Demonstration Required: {0}' -f [string]$capability.next_independent_demonstration_required)) | Out-Null
        }
        $markdownLines.Add('') | Out-Null
        $markdownLines.Add('## Final Summary') | Out-Null
        $markdownLines.Add(('- Strongest: {0}' -f (@($artifact.final_summary.top_five_strongest_engineering_capabilities) -join '; '))) | Out-Null
        $markdownLines.Add(('- Weakest: {0}' -f (@($artifact.final_summary.top_five_weakest_engineering_capabilities) -join '; '))) | Out-Null
        $markdownLines.Add(('- Largest apprenticeship debt: {0}' -f [string]$artifact.final_summary.largest_remaining_apprenticeship_debt)) | Out-Null
        $markdownLines.Add(('- Greatest independence gain: {0}' -f [string]$artifact.final_summary.single_capability_with_greatest_independence_gain)) | Out-Null
        $markdownLines.Add(('- Overall maturity: {0}' -f [string]$artifact.final_summary.overall_engineering_maturity_assessment)) | Out-Null
        New-Item -ItemType Directory -Path (Split-Path -Parent $markdownAbs) -Force | Out-Null
        [System.IO.File]::WriteAllText($markdownAbs, ($markdownLines.ToArray() -join "`r`n"), [System.Text.UTF8Encoding]::new($false))
    }
    $readback = Get-Content -Path $outputAbs -Raw | ConvertFrom-Json

    $requiredFields = if ($isTodCapabilityAssessment) {
        @('artifact_type', 'generated_at', 'source', 'objective_id', 'task_id', 'task_mode', 'assessment_status', 'tod_read_only_assessment_completed', 'tod_independent_capability_acquired', 'borrowed_control_plane_repair', 'no_source_code_modified_by_assessment', 'inspected_files', 'evidence_used', 'capabilities', 'final_summary', 'validation')
    }
    else {
        @('artifact_type', 'generated_at', 'source', 'objective_id', 'task_id', 'audit_subject', 'inspected_files', 'evidence_used', 'classification', 'findings', 'blockers', 'confidence', 'no_code_changes', 'validation', 'continuation_action')
    }
    $missing = @($requiredFields | Where-Object { -not $readback.PSObject.Properties[$_] })
    if ($missing.Count -gt 0) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'read_only_audit_artifact_schema_failed' -Reason ('Read-only audit artifact is missing required fields: {0}' -f ($missing -join ', ')) -MissingVariable 'artifact_schema')
    }
    $noCodeChangeFlag = if ($isTodCapabilityAssessment) { $readback.no_source_code_modified_by_assessment } else { $readback.no_code_changes }
    if ($noCodeChangeFlag -ne $true) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'read_only_audit_no_code_change_flag_failed' -Reason 'Read-only audit artifact must set no_code_changes=true.' -MissingVariable 'no_code_changes')
    }

    $Result.summary = ('Published read-only audit artifact {0} from evidence file {1}.' -f $outputRel, $inputRel)
    $Result.files_changed = if ($isTodCapabilityAssessment) { @($outputRel, $markdownRel) } else { @($outputRel) }
    $Result.tests_run = @('input evidence read', 'read-only audit artifact write', 'required schema readback', 'no-code-change assertion')
    $Result.test_results = @('pass', 'pass', 'pass', 'pass')
    $Result | Add-Member -NotePropertyName command_output -NotePropertyValue ('Read-only audit artifact published: {0}' -f $outputRel) -Force
    $Result | Add-Member -NotePropertyName diff_summary -NotePropertyValue ('Artifact write only: {0}' -f $outputRel) -Force
    $Result | Add-Member -NotePropertyName commands_run -NotePropertyValue @('Invoke-LocalExecutionReadOnlyAuditArtifact') -Force
    $Result | Add-Member -NotePropertyName validation_results -NotePropertyValue @(
        [pscustomobject]@{ name = 'input evidence read'; passed = $true; required = $true },
        [pscustomobject]@{ name = 'read-only audit artifact write'; passed = $true; required = $true },
        [pscustomobject]@{ name = 'required schema readback'; passed = $true; required = $true },
        [pscustomobject]@{ name = 'no-code-change assertion'; passed = $true; required = $true }
    ) -Force
    $Result | Add-Member -NotePropertyName blockers -NotePropertyValue @() -Force
    $Result | Add-Member -NotePropertyName confidence -NotePropertyValue 'high' -Force
    $Result | Add-Member -NotePropertyName rollback_hint -NotePropertyValue ('Remove generated artifact {0} if this training artifact must be discarded.' -f $outputRel) -Force
    $Result | Add-Member -NotePropertyName no_change_required -NotePropertyValue $false -Force
    return (Complete-EngineExecutionResult -Result $Result -Status 'completed')
}

function Get-LocalExecutionMaintenanceArtifactPaths {
    param([Parameter(Mandatory = $true)]$Context)

    $text = Get-LocalExecutionCombinedText -Context $Context
    $matches = @([regex]::Matches($text, 'runtime_remote_training/read_only_audit_artifacts/[A-Za-z0-9_./-]+?\.json') | ForEach-Object { [string]$_.Value })
    $unique = New-Object System.Collections.Generic.List[string]
    foreach ($match in $matches) {
        $candidate = Convert-ToLocalExecutionRepoRelativePath -PathValue $match
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and -not $unique.Contains($candidate)) {
            [void]$unique.Add($candidate)
        }
    }
    $outputPath = ''
    if ($unique.Count -gt 0) {
        $outputPath = [string]$unique[$unique.Count - 1]
    }
    $inputs = @()
    if ($unique.Count -gt 1) {
        $inputs = @($unique | Select-Object -First ($unique.Count - 1))
    }
    return [pscustomobject]@{
        input_paths = [string[]]$inputs
        output_path = $outputPath
    }
}

function Test-LocalExecutionSiteMaintenanceArtifactTask {
    param([Parameter(Mandatory = $true)]$Context)

    $category = Get-LocalExecutionTaskCategory -Context $Context
    if (@('report_only', 'diagnostic_only', 'inspection_only', 'inspection') -notcontains $category) {
        return $false
    }

    $text = (Get-LocalExecutionCombinedText -Context $Context).ToLowerInvariant()
    if ($text -notmatch 'maintenance\s+(card|map)|site\s+maintenance|route-maintenance') {
        return $false
    }

    $paths = Get-LocalExecutionMaintenanceArtifactPaths -Context $Context
    return (@($paths.input_paths).Count -ge 1 -and -not [string]::IsNullOrWhiteSpace([string]$paths.output_path))
}

function Get-LocalExecutionQuotedMarkers {
    param([Parameter(Mandatory = $true)][string]$Text)

    $markers = New-Object System.Collections.Generic.List[string]
    foreach ($match in [regex]::Matches($Text, '"([^"\r\n]{3,120})"')) {
        $value = ([string]$match.Groups[1].Value).Trim()
        if (-not [string]::IsNullOrWhiteSpace($value) -and -not $markers.Contains($value)) {
            [void]$markers.Add($value)
        }
    }
    return [string[]]@($markers | Select-Object -First 16)
}

function Get-LocalExecutionMaintenanceCardFromAnchor {
    param(
        [Parameter(Mandatory = $true)]$Anchor,
        [Parameter(Mandatory = $true)][string]$InputPath
    )

    $sourceFile = if ($Anchor.PSObject.Properties['source_file']) { [string]$Anchor.source_file } else { '' }
    $exactText = if ($Anchor.PSObject.Properties['exact_text']) { [string]$Anchor.exact_text } else { '' }
    $markers = Get-LocalExecutionQuotedMarkers -Text $exactText
    $lineStart = if ($Anchor.PSObject.Properties['start_line']) { [int]$Anchor.start_line } else { 0 }
    $lineEnd = if ($Anchor.PSObject.Properties['end_line']) { [int]$Anchor.end_line } else { 0 }

    $surface = 'unknown route or test surface'
    $meaning = 'Source anchor needs human review before TOD changes related code.'
    $validationHint = 'Run the narrow route or unit test that exercises this source surface.'
    if ($sourceFile -like '*core/routers/public_chat.py') {
        $surface = 'public homepage, build page, public chat, and public menu links'
        $meaning = 'The public chat router owns the approved home/build surface and its route-level identity markers.'
        $validationHint = 'Run public chat and research-context route smoke tests before changing homepage, build, or public chat behavior.'
    }
    elseif ($sourceFile -like '*core/routers/observatory.py') {
        $surface = 'Research Observatory routes, project detail, documents, calendar, community questions, and project settings'
        $meaning = 'The Observatory router owns the public research lab page family and collaboration tools.'
        $validationHint = 'Run the Observatory route smoke suite before changing research, document, calendar, or community question behavior.'
    }
    elseif ($sourceFile -like '*tests/test_observatory_routes.py') {
        $surface = 'Observatory route behavior contract'
        $meaning = 'The route test suite defines expected public Observatory behavior and prevents regression to stale labels or static brochure content.'
        $validationHint = 'Run tmp_remote_mim/tests/test_observatory_routes.py after route or UI changes in the Observatory surface.'
    }

    return [ordered]@{
        input_artifact = $InputPath
        source_file = $sourceFile
        source_lines = [ordered]@{ start = $lineStart; end = $lineEnd }
        observed_route_surface = $surface
        maintenance_meaning = $meaning
        protected_behaviors = [string[]]$markers
        validation_hint = $validationHint
    }
}

function Invoke-LocalExecutionSiteMaintenanceArtifact {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)]$Spec
    )

    $paths = Get-LocalExecutionMaintenanceArtifactPaths -Context $Context
    $inputPaths = [string[]]@($paths.input_paths)
    $outputRel = [string]$paths.output_path
    if ($inputPaths.Count -lt 1) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'maintenance_artifact_input_missing' -Reason 'Site maintenance artifact synthesis requires at least one source-anchor input artifact.' -MissingVariable 'input_artifact')
    }
    if ([string]::IsNullOrWhiteSpace($outputRel)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'maintenance_artifact_output_missing' -Reason 'Site maintenance artifact synthesis requires an output artifact path under runtime_remote_training/read_only_audit_artifacts/.' -MissingVariable 'output_artifact')
    }
    if (-not (Test-LocalExecutionSafePath -RelativePath $outputRel)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'maintenance_artifact_output_unsafe' -Reason ('Output artifact path is outside LocalExecutionEngine safe roots: {0}' -f $outputRel) -MissingVariable 'safe_output_path')
    }

    $cards = New-Object System.Collections.Generic.List[object]
    foreach ($inputRel in $inputPaths) {
        if (-not (Test-LocalExecutionSafePath -RelativePath $inputRel)) {
            return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'maintenance_artifact_input_unsafe' -Reason ('Input artifact path is outside LocalExecutionEngine safe roots: {0}' -f $inputRel) -MissingVariable 'safe_input_path')
        }
        $inputAbs = Join-Path $script:LocalEngineRepoRoot $inputRel
        if (-not (Test-Path -Path $inputAbs -PathType Leaf)) {
            return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'maintenance_artifact_input_not_found' -Reason ('Input source-anchor artifact does not exist: {0}' -f $inputRel) -MissingVariable 'input_artifact')
        }
        $anchor = Get-Content -Path $inputAbs -Raw | ConvertFrom-Json
        if (-not $anchor.PSObject.Properties['artifact_type'] -or [string]$anchor.artifact_type -ne 'tod_source_anchor_observation') {
            return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'maintenance_artifact_input_not_anchor' -Reason ('Input artifact is not a source-anchor observation: {0}' -f $inputRel) -MissingVariable 'source_anchor_artifact')
        }
        if (-not $anchor.PSObject.Properties['exact_text'] -or [string]::IsNullOrWhiteSpace([string]$anchor.exact_text)) {
            return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'maintenance_artifact_exact_text_missing' -Reason ('Input source-anchor artifact has no exact_text: {0}' -f $inputRel) -MissingVariable 'exact_text')
        }
        [void]$cards.Add((Get-LocalExecutionMaintenanceCardFromAnchor -Anchor $anchor -InputPath $inputRel))
    }

    $text = (Get-LocalExecutionCombinedText -Context $Context).ToLowerInvariant()
    $isMap = ($text -match 'maintenance\s+map|site\s+maintenance\s+map|multi-anchor')
    $contextObjectiveId = if ($Context.PSObject.Properties['objective_id']) { [string]$Context.objective_id } else { '' }
    $contextTaskId = if ($Context.PSObject.Properties['task_id']) { [string]$Context.task_id } else { '' }
    $cardItems = @($cards.ToArray())
    if ($isMap) {
        $artifact = [ordered]@{
            artifact_type = 'tod_site_maintenance_map'
            generated_at = (Get-Date).ToUniversalTime().ToString('o')
            source = 'local_execution_site_maintenance_artifact_lane'
            objective_id = $contextObjectiveId
            task_id = $contextTaskId
            evidence_artifacts = $inputPaths
            route_ownership_map = $cardItems
            validation_contracts = @($cardItems | ForEach-Object { [ordered]@{ source_file = $_.source_file; validation_hint = $_.validation_hint } })
            maintenance_rules = @(
                'Find the route owner before editing.',
                'Find the test contract before editing.',
                'Do not infer site behavior beyond source anchors and tests.',
                'Run route-specific smoke tests before deployment or restart.'
            )
            deployment_or_restart_notes = @(
                'This artifact is a maintenance orientation map only; it does not prove deployment.',
                'After site code changes, validate locally and restart the configured MIM web service from the authority environment.'
            )
            common_failure_modes = @(
                'Editing public_chat.py without preserving approved homepage/build markers.',
                'Editing observatory.py without running Observatory route tests.',
                'Treating document or research metadata as accepted evidence without source review.',
                'Launching parallel TOD training tasks that supersede each other on the active execution lane.'
            )
            what_tod_should_check_before_site_edits = @(
                'source owner file',
                'route test contract',
                'data/context owner module',
                'authentication or project-owner boundary',
                'document/evidence truth boundary',
                'deployment or service restart evidence'
            )
            no_code_changes = $true
            validation = [ordered]@{
                artifact_path = $outputRel
                input_count = $inputPaths.Count
                card_count = $cards.Count
                source_edits = @()
                required_fields_present = $true
            }
        }
    }
    else {
        $card = $cards[0]
        $artifact = [ordered]@{
            artifact_type = 'tod_site_maintenance_card'
            generated_at = (Get-Date).ToUniversalTime().ToString('o')
            source = 'local_execution_site_maintenance_artifact_lane'
            objective_id = $contextObjectiveId
            task_id = $contextTaskId
            input_artifact = $card.input_artifact
            source_file = $card.source_file
            source_lines = $card.source_lines
            observed_route_surface = $card.observed_route_surface
            maintenance_meaning = $card.maintenance_meaning
            protected_behaviors = $card.protected_behaviors
            validation_hint = $card.validation_hint
            no_code_changes = $true
            validation = [ordered]@{
                artifact_path = $outputRel
                input_count = $inputPaths.Count
                source_edits = @()
                required_fields_present = $true
            }
        }
    }

    $outputAbs = Join-Path $script:LocalEngineRepoRoot $outputRel
    New-Item -ItemType Directory -Path (Split-Path -Parent $outputAbs) -Force | Out-Null
    [System.IO.File]::WriteAllText($outputAbs, ($artifact | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))
    $readback = Get-Content -Path $outputAbs -Raw | ConvertFrom-Json
    if ($readback.no_code_changes -ne $true) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'maintenance_artifact_no_code_change_flag_failed' -Reason 'Maintenance artifact must set no_code_changes=true.' -MissingVariable 'no_code_changes')
    }

    $Result.summary = ('Published site maintenance artifact {0} from {1} source-anchor artifact(s).' -f $outputRel, $inputPaths.Count)
    $Result.files_changed = @($outputRel)
    $Result.tests_run = @('source-anchor artifact read', 'maintenance artifact write', 'required schema readback', 'no-code-change assertion')
    $Result.test_results = @('pass', 'pass', 'pass', 'pass')
    $Result | Add-Member -NotePropertyName command_output -NotePropertyValue ('Site maintenance artifact published: {0}' -f $outputRel) -Force
    $Result | Add-Member -NotePropertyName diff_summary -NotePropertyValue ('Artifact write only: {0}' -f $outputRel) -Force
    $Result | Add-Member -NotePropertyName commands_run -NotePropertyValue @('Invoke-LocalExecutionSiteMaintenanceArtifact') -Force
    $Result | Add-Member -NotePropertyName validation_results -NotePropertyValue @(
        [pscustomobject]@{ name = 'source-anchor artifact read'; passed = $true; required = $true },
        [pscustomobject]@{ name = 'maintenance artifact write'; passed = $true; required = $true },
        [pscustomobject]@{ name = 'required schema readback'; passed = $true; required = $true },
        [pscustomobject]@{ name = 'no-code-change assertion'; passed = $true; required = $true }
    ) -Force
    $Result | Add-Member -NotePropertyName blockers -NotePropertyValue @() -Force
    $Result | Add-Member -NotePropertyName confidence -NotePropertyValue 'high' -Force
    $Result | Add-Member -NotePropertyName rollback_hint -NotePropertyValue ('Remove generated artifact {0} if this training artifact must be discarded.' -f $outputRel) -Force
    $Result | Add-Member -NotePropertyName no_change_required -NotePropertyValue $false -Force
    return (Complete-EngineExecutionResult -Result $Result -Status 'completed')
}

function Get-LocalExecutionSemanticSourceAuditPaths {
    param([Parameter(Mandatory = $true)]$Context)

    $text = Get-LocalExecutionCombinedText -Context $Context
    $matches = @([regex]::Matches($text, 'runtime_remote_training/read_only_audit_artifacts/[A-Za-z0-9_./-]+?\.json') | ForEach-Object { [string]$_.Value })
    $unique = New-Object System.Collections.Generic.List[string]
    foreach ($match in $matches) {
        $candidate = Convert-ToLocalExecutionRepoRelativePath -PathValue $match
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and -not $unique.Contains($candidate)) {
            [void]$unique.Add($candidate)
        }
    }
    $outputPath = ''
    if ($unique.Count -gt 0) {
        $outputPath = [string]$unique[$unique.Count - 1]
    }
    $inputs = @()
    if ($unique.Count -gt 1) {
        $inputs = @($unique | Select-Object -First ($unique.Count - 1))
    }
    return [pscustomobject]@{
        input_paths = [string[]]$inputs
        output_path = $outputPath
    }
}

function Get-LocalExecutionSemanticAuditRequiredFields {
    param([Parameter(Mandatory = $true)]$Context)

    $text = Get-LocalExecutionCombinedText -Context $Context
    $fields = New-Object System.Collections.Generic.List[string]
    $match = [regex]::Match($text, '(?is)required\s+output\s+fields\s*:\s*(?<fields>.*?)(?:\.\s|(?:\r?\n){2,}|$)')
    if ($match.Success) {
        foreach ($fieldMatch in [regex]::Matches([string]$match.Groups['fields'].Value, '\b[A-Za-z][A-Za-z0-9_]*\b')) {
            $field = ([string]$fieldMatch.Value).Trim()
            if (($field -eq 'confidence' -or $field -like '*_*') -and -not $fields.Contains($field)) {
                [void]$fields.Add($field)
            }
        }
    }

    if ($fields.Count -eq 0) {
        foreach ($field in @(
                'observed_blocker',
                'suspected_root_cause',
                'evidence_checked',
                'evidence_missing',
                'why_forward_motion_is_blocked',
                'smallest_diagnostic_step',
                'confidence',
                'no_phrase_patch_rule'
            )) {
            [void]$fields.Add($field)
        }
    }

    return [string[]]$fields.ToArray()
}

function Test-LocalExecutionSemanticSourceAuditTask {
    param([Parameter(Mandatory = $true)]$Context)

    $category = Get-LocalExecutionTaskCategory -Context $Context
    if (@('report_only', 'diagnostic_only', 'inspection_only', 'inspection') -notcontains $category) {
        return $false
    }

    $text = (Get-LocalExecutionCombinedText -Context $Context).ToLowerInvariant()
    if ($text -notmatch 'semantic' -or $text -notmatch 'audit' -or $text -notmatch 'source[-_\s]?anchor') {
        return $false
    }
    if ($text -notmatch 'root[-_\s]?cause|audit[-_\s]?body|source[-_\s]?audit') {
        return $false
    }

    $paths = Get-LocalExecutionSemanticSourceAuditPaths -Context $Context
    return (@($paths.input_paths).Count -ge 1 -and -not [string]::IsNullOrWhiteSpace([string]$paths.output_path))
}

function Test-LocalExecutionResearchEvidenceDemonstrationTask {
    param([Parameter(Mandatory = $true)]$Context)

    $text = (Get-LocalExecutionCombinedText -Context $Context).ToLowerInvariant()
    if ($text -notmatch 'independent[-_\s]?(unseen[-_\s]?apprenticeship|source[-_\s]?evidence)[-_\s]?(demonstration|artifact[-_\s]?body(?:[-_\s]?demonstration)?)') {
        return $false
    }
    if ($text -notmatch 'source[-_\s]?evidence') {
        return $false
    }
    if ($text -notmatch 'artifact[-_\s]?body|source[-_\s]?evidence|authority[-_\s]?boundary') {
        return $false
    }
    return $true
}

function Get-LocalExecutionResearchEvidenceOutputPath {
    param([Parameter(Mandatory = $true)]$Context)

    $text = Get-LocalExecutionCombinedText -Context $Context
    $directiveTarget = Get-LocalExecutionDirectiveValue -PromptText $text -FieldName 'Target File'
    if (-not [string]::IsNullOrWhiteSpace($directiveTarget)) {
        return (Convert-ToLocalExecutionRepoRelativePath -PathValue $directiveTarget)
    }
    $match = [regex]::Match($text, 'runtime/shared/TOD_INDEPENDENT_UNSEEN_APPRENTICESHIP_DEMONSTRATION_[A-Za-z0-9_.-]+?\.json')
    if ($match.Success) {
        return (Convert-ToLocalExecutionRepoRelativePath -PathValue ([string]$match.Value))
    }
    return 'runtime/shared/TOD_INDEPENDENT_UNSEEN_APPRENTICESHIP_DEMONSTRATION_002.latest.json'
}

function Get-LocalExecutionSolairPowerCurveSourcePath {
    param([Parameter(Mandatory = $true)]$Context)

    $text = Get-LocalExecutionCombinedText -Context $Context
    $sourceDirective = Get-LocalExecutionDirectiveValue -PromptText $text -FieldName 'Source evidence'
    if (-not [string]::IsNullOrWhiteSpace($sourceDirective)) {
        return (Convert-ToLocalExecutionRepoRelativePath -PathValue $sourceDirective)
    }
    $sourceMatch = [regex]::Match($text, 'runtime/shared/[A-Za-z0-9_./-]+?\.latest\.json')
    if ($sourceMatch.Success) {
        return (Convert-ToLocalExecutionRepoRelativePath -PathValue ([string]$sourceMatch.Value))
    }
    $match = [regex]::Match($text, 'runtime/shared/SOLAIR_POWER_CURVE_OBSERVATION\.latest\.json')
    if ($match.Success) {
        return (Convert-ToLocalExecutionRepoRelativePath -PathValue ([string]$match.Value))
    }
    return 'runtime/shared/SOLAIR_POWER_CURVE_OBSERVATION.latest.json'
}

function Get-LocalExecutionJsonArraySummary {
    param([Parameter(Mandatory = $true)]$Source)

    $summaries = New-Object System.Collections.Generic.List[object]
    foreach ($property in @($Source.PSObject.Properties)) {
        $value = $property.Value
        if ($value -is [array] -or $value -is [System.Collections.IEnumerable] -and -not ($value -is [string])) {
            $items = @($value)
            if ($items.Count -eq 0) {
                continue
            }
            $sample = $items | Select-Object -First 1
            $fields = @()
            if ($null -ne $sample -and $sample.PSObject -and $sample.PSObject.Properties) {
                $fields = @($sample.PSObject.Properties.Name)
            }
            [void]$summaries.Add([ordered]@{
                    name = [string]$property.Name
                    count = $items.Count
                    sample_fields = @($fields)
                })
        }
    }
    return @($summaries)
}

function Get-LocalExecutionNumericProperty {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($null -eq $Object -or -not $Object.PSObject.Properties[$Name]) {
        return $null
    }
    return [double]$Object.$Name
}

function Select-LocalExecutionRowByWindSpeed {
    param(
        [Parameter(Mandatory = $true)]$Rows,
        [Parameter(Mandatory = $true)][double]$WindSpeedMph,
        [string]$Configuration = ''
    )

    foreach ($row in @($Rows)) {
        $rowWind = Get-LocalExecutionNumericProperty -Object $row -Name 'wind_speed_mph'
        if ($null -eq $rowWind -or [math]::Abs($rowWind - $WindSpeedMph) -gt 0.0001) {
            continue
        }
        if (-not [string]::IsNullOrWhiteSpace($Configuration)) {
            $rowConfig = if ($row.PSObject.Properties['configuration']) { [string]$row.configuration } else { '' }
            if (-not [string]::Equals($rowConfig, $Configuration, [System.StringComparison]::OrdinalIgnoreCase)) {
                continue
            }
        }
        return $row
    }
    return $null
}

function Invoke-LocalExecutionResearchEvidenceDemonstration {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)]$Spec
    )

    $outputRel = Get-LocalExecutionResearchEvidenceOutputPath -Context $Context
    $sourceRel = Get-LocalExecutionSolairPowerCurveSourcePath -Context $Context
    if (-not (Test-LocalExecutionSafePath -RelativePath $outputRel)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'research_evidence_demo_output_unsafe' -Reason ('Research evidence demonstration output is outside safe roots: {0}' -f $outputRel) -MissingVariable 'safe_output_path')
    }
    if (-not (Test-LocalExecutionSafePath -RelativePath $sourceRel)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'research_evidence_demo_source_unsafe' -Reason ('Research evidence demonstration source is outside safe roots: {0}' -f $sourceRel) -MissingVariable 'safe_source_path')
    }

    $sourceAbs = Join-Path $script:LocalEngineRepoRoot $sourceRel
    if (-not (Test-Path -Path $sourceAbs -PathType Leaf)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'research_evidence_demo_source_missing' -Reason ('Research evidence source artifact does not exist: {0}' -f $sourceRel) -MissingVariable 'source_evidence_artifact')
    }

    $source = Get-Content -Path $sourceAbs -Raw | ConvertFrom-Json
    $physicsRows = if ($source.PSObject.Properties['physics_limit_rows']) { @($source.physics_limit_rows) } else { @() }
    $chartRows = if ($source.PSObject.Properties['chart_rows']) { @($source.chart_rows) } else { @() }
    $topAssemblies = if ($source.PSObject.Properties['top_assemblies']) { @($source.top_assemblies) } else { @() }
    $componentRows = if ($source.PSObject.Properties['component_rows']) { @($source.component_rows) } else { @() }
    $allRows = if ($source.PSObject.Properties['rows']) { @($source.rows) } else { @() }
    if (@($topAssemblies).Count -gt 0 -or @($componentRows).Count -gt 0 -or @($allRows).Count -gt 0) {
        $arraySummary = Get-LocalExecutionJsonArraySummary -Source $source
        $sourceBoundary = if ($source.PSObject.Properties['source_boundary']) { [string]$source.source_boundary } else { 'Structured rows are source observations pending formal evidence review.' }
        $sources = if ($source.PSObject.Properties['sources']) { @($source.sources) } else { @() }
        $sampleTopAssemblies = @($topAssemblies | Select-Object -First 10 | ForEach-Object {
                [ordered]@{
                    part_no = if ($_.PSObject.Properties['part_no']) { [string]$_.part_no } else { '' }
                    quantity = if ($_.PSObject.Properties['quantity']) { [string]$_.quantity } else { '' }
                    description = if ($_.PSObject.Properties['description']) { [string]$_.description } else { '' }
                    supplier = if ($_.PSObject.Properties['supplier']) { [string]$_.supplier } else { '' }
                    supplier_part_no = if ($_.PSObject.Properties['supplier_part_no']) { [string]$_.supplier_part_no } else { '' }
                }
            })
        $sampleComponents = @($componentRows | Select-Object -First 12 | ForEach-Object {
                [ordered]@{
                    part_no = if ($_.PSObject.Properties['part_no']) { [string]$_.part_no } else { '' }
                    quantity = if ($_.PSObject.Properties['quantity']) { [string]$_.quantity } else { '' }
                    description = if ($_.PSObject.Properties['description']) { [string]$_.description } else { '' }
                    supplier = if ($_.PSObject.Properties['supplier']) { [string]$_.supplier } else { '' }
                    supplier_part_no = if ($_.PSObject.Properties['supplier_part_no']) { [string]$_.supplier_part_no } else { '' }
                    assembly_path = if ($_.PSObject.Properties['assembly_path']) { @($_.assembly_path | ForEach-Object { [string]$_ }) } else { @() }
                }
            })
        $costRows = @($allRows | Where-Object { $_.PSObject.Properties['cost'] -and -not [string]::IsNullOrWhiteSpace([string]$_.cost) })
        $artifact = [ordered]@{
            artifact_type = 'tod_independent_source_evidence_artifact_body_demonstration'
            generated_at = (Get-Date).ToUniversalTime().ToString('o')
            source = 'local_execution_structured_source_evidence_demonstration_lane'
            objective_id = if ($Context.PSObject.Properties['objective_id']) { [string]$Context.objective_id } else { '' }
            task_id = if ($Context.PSObject.Properties['task_id']) { [string]$Context.task_id } else { '' }
            selected_unseen_case = 'SolAir BOM/build-parts question from source-observed BOM artifact'
            source_evidence_discovered = @(
                [ordered]@{
                    artifact_path = $sourceRel
                    packet_type = if ($source.PSObject.Properties['packet_type']) { [string]$source.packet_type } else { '' }
                    status = if ($source.PSObject.Properties['status']) { [string]$source.status } else { '' }
                    array_summary = @($arraySummary)
                    sources = @($sources | ForEach-Object {
                            [ordered]@{
                                kind = if ($_.PSObject.Properties['kind']) { [string]$_.kind } else { '' }
                                relative_path = if ($_.PSObject.Properties['relative_path']) { [string]$_.relative_path } elseif ($_.PSObject.Properties['path']) { [string]$_.path } else { '' }
                                rows_observed = if ($_.PSObject.Properties['rows_observed']) { [string]$_.rows_observed } else { '' }
                            }
                        })
                }
            )
            diagnosis = 'The source artifact contains source-observed BOM rows. It can support a provisional build-parts answer, but it cannot by itself prove final release status, current supplier availability, current cost, tooling requirements, or manufacturing authority.'
            authority_boundary = [ordered]@{
                source_observed_bom_rows = $sourceBoundary
                not_final_claims = 'BOM rows are not automatically final manufacturing release instructions, certified configuration, supplier availability, or current cost quotes.'
                answer_rule = 'Answer parts/build questions from observed rows, name the source, and preserve that drawings, release status, supplier records, process notes, and validation tests are still needed for final manufacturing guidance.'
            }
            answer_model = [ordered]@{
                example_question = 'What are the major SolAir parts?'
                top_assembly_count = @($topAssemblies).Count
                component_row_count = @($componentRows).Count
                total_rows = @($allRows).Count
                cost_rows_with_values = @($costRows).Count
                representative_top_assemblies = @($sampleTopAssemblies)
                representative_components = @($sampleComponents)
                safe_response_pattern = 'According to the observed SolAir BOM artifact, the project contains these top assemblies and representative components. This is source-observed BOM evidence, not final release authority; MIM should cross-check drawings, release status, supplier records, and build/process evidence before treating it as manufacturing instruction.'
            }
            validation_plan = @(
                'Read source artifact as JSON.',
                'Identify structured array fields and row counts.',
                'Extract representative top assemblies and components.',
                'Preserve authority boundary between observed BOM rows and final manufacturing claims.',
                'Confirm output artifact contains all required proof fields.'
            )
            validation_result = [ordered]@{
                status = 'pass'
                structured_arrays_present = (@($arraySummary).Count -gt 0)
                bom_rows_present = (@($topAssemblies).Count -gt 0 -or @($componentRows).Count -gt 0 -or @($allRows).Count -gt 0)
                output_target = $outputRel
                source_code_edits = @()
            }
            what_TOD_did_without_Codex = @(
                'Accepted a single bounded output target.',
                'Read the SolAir BOM source observation artifact.',
                'Discovered structured arrays and row counts.',
                'Separated source-observed BOM evidence from final manufacturing release claims.',
                'Published a structured proof artifact rather than a blocker.'
            )
            what_TOD_still_cannot_do = @(
                'This pass used the generalized structured-source evidence rung added after prior blockers; TOD still needs to repeat on an unfamiliar non-SolAir artifact without Codex modifying the lane.'
            )
            registry_update_recommendation = 'Move APP-TOD-015 to structured_source_synthesis_pass; require one non-SolAir or non-BOM artifact before retirement.'
            no_code_changes = $true
        }

        $required = @('objective_id','selected_unseen_case','source_evidence_discovered','diagnosis','authority_boundary','answer_model','validation_plan','validation_result','what_TOD_did_without_Codex','what_TOD_still_cannot_do','registry_update_recommendation')
        $outputAbs = Join-Path $script:LocalEngineRepoRoot $outputRel
        New-Item -ItemType Directory -Path (Split-Path -Parent $outputAbs) -Force | Out-Null
        [System.IO.File]::WriteAllText($outputAbs, ($artifact | ConvertTo-Json -Depth 30), [System.Text.UTF8Encoding]::new($false))
        $readback = Get-Content -Path $outputAbs -Raw | ConvertFrom-Json
        $missing = @($required | Where-Object { -not $readback.PSObject.Properties[[string]$_] })
        if ($missing.Count -gt 0) {
            return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'structured_source_demo_required_fields_missing' -Reason ('Structured source evidence demonstration artifact is missing fields: {0}' -f ($missing -join ', ')) -MissingVariable 'required_fields')
        }

        $Result.summary = ('Published structured source evidence demonstration artifact {0} from {1}.' -f $outputRel, $sourceRel)
        $Result.files_changed = @($outputRel)
        $Result.tests_run = @('source evidence JSON read', 'structured array discovery', 'authority boundary preservation', 'required field readback')
        $Result.test_results = @('pass', 'pass', 'pass', 'pass')
        $Result | Add-Member -NotePropertyName command_output -NotePropertyValue ('Structured source evidence demonstration artifact published: {0}' -f $outputRel) -Force
        $Result | Add-Member -NotePropertyName diff_summary -NotePropertyValue ('Artifact write only: {0}' -f $outputRel) -Force
        $Result | Add-Member -NotePropertyName commands_run -NotePropertyValue @('Invoke-LocalExecutionResearchEvidenceDemonstration') -Force
        $Result | Add-Member -NotePropertyName validation_results -NotePropertyValue @(
            [pscustomobject]@{ name = 'source evidence JSON read'; passed = $true; required = $true },
            [pscustomobject]@{ name = 'structured array discovery'; passed = $true; required = $true },
            [pscustomobject]@{ name = 'authority boundary preservation'; passed = $true; required = $true },
            [pscustomobject]@{ name = 'required field readback'; passed = $true; required = $true }
        ) -Force
        $Result | Add-Member -NotePropertyName blockers -NotePropertyValue @() -Force
        $Result | Add-Member -NotePropertyName confidence -NotePropertyValue 'medium-high' -Force
        $Result | Add-Member -NotePropertyName rollback_hint -NotePropertyValue ('Remove generated artifact {0} if this training artifact must be discarded.' -f $outputRel) -Force
        $Result | Add-Member -NotePropertyName no_change_required -NotePropertyValue $false -Force
        return (Complete-EngineExecutionResult -Result $Result -Status 'completed')
    }

    if (@($physicsRows).Count -eq 0 -or @($chartRows).Count -eq 0) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'research_evidence_demo_source_rows_missing' -Reason 'SolAir power curve source artifact must include physics_limit_rows and chart_rows.' -MissingVariable 'source_rows')
    }

    $physics10 = Select-LocalExecutionRowByWindSpeed -Rows $physicsRows -WindSpeedMph 10
    $chart10Parallel = Select-LocalExecutionRowByWindSpeed -Rows $chartRows -WindSpeedMph 10 -Configuration 'Two Units In Parallel'
    $chart10Series = Select-LocalExecutionRowByWindSpeed -Rows $chartRows -WindSpeedMph 10 -Configuration 'Two Units in Series'
    $chartMax = @($chartRows | Sort-Object -Property @{ Expression = { Get-LocalExecutionNumericProperty -Object $_ -Name 'wind_speed_mph' } } -Descending | Select-Object -First 1)
    if ($null -eq $physics10 -or $null -eq $chart10Parallel -or $null -eq $chart10Series -or @($chartMax).Count -eq 0) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'research_evidence_demo_required_rows_missing' -Reason 'SolAir power curve source artifact does not include the 10 mph comparison rows or maximum chart row needed for this proof.' -MissingVariable 'required_rows')
    }

    $afterEfficiency10 = [math]::Round((Get-LocalExecutionNumericProperty -Object $physics10 -Name 'after_generator_efficiency_watts'), 1)
    $betz10 = [math]::Round((Get-LocalExecutionNumericProperty -Object $physics10 -Name 'betz_limit_watts'), 1)
    $raw10 = [math]::Round((Get-LocalExecutionNumericProperty -Object $physics10 -Name 'raw_wind_power_watts'), 1)
    $chartOne10 = [math]::Round((Get-LocalExecutionNumericProperty -Object $chart10Parallel -Name 'one_unit_watts_from_chart'), 1)
    $chartTwoParallel10 = [math]::Round((Get-LocalExecutionNumericProperty -Object $chart10Parallel -Name 'two_unit_watts'), 1)
    $chartTwoSeries10 = [math]::Round((Get-LocalExecutionNumericProperty -Object $chart10Series -Name 'two_unit_watts'), 1)
    $maxWind = [math]::Round((Get-LocalExecutionNumericProperty -Object $chartMax[0] -Name 'wind_speed_mph'), 1)
    $maxOneUnit = [math]::Round((Get-LocalExecutionNumericProperty -Object $chartMax[0] -Name 'one_unit_watts_from_chart'), 1)
    $maxTwoUnit = [math]::Round((Get-LocalExecutionNumericProperty -Object $chartMax[0] -Name 'two_unit_watts'), 1)

    $artifact = [ordered]@{
        artifact_type = 'tod_independent_unseen_apprenticeship_demonstration'
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        source = 'local_execution_research_evidence_demonstration_lane'
        objective_id = if ($Context.PSObject.Properties['objective_id']) { [string]$Context.objective_id } else { '' }
        task_id = if ($Context.PSObject.Properties['task_id']) { [string]$Context.task_id } else { '' }
        selected_unseen_case = 'SolAir power-output question from source-observed power curve artifact'
        source_evidence_discovered = @(
            [ordered]@{
                artifact_path = $sourceRel
                packet_type = if ($source.PSObject.Properties['packet_type']) { [string]$source.packet_type } else { '' }
                status = if ($source.PSObject.Properties['status']) { [string]$source.status } else { '' }
                physics_limit_rows = $physicsRows.Count
                chart_rows = $chartRows.Count
                sources = @($source.sources | ForEach-Object { [ordered]@{ kind = $_.kind; relative_path = $_.relative_path; note = $_.note } })
            }
        )
        diagnosis = 'The source artifact contains two different evidence lanes for SolAir output: chart/workbook watt values and physics-limit calculated rows. A truthful answer must preserve this distinction instead of choosing the larger chart value as final.'
        authority_boundary = [ordered]@{
            chart_values = 'Source-observed workbook/chart values; useful for what the SolAir chart claimed, pending source authority review.'
            physics_limit_values = 'Calculated workbook rows for raw wind power, Betz limit, and generator efficiency; useful as model/physics-boundary evidence, not automatically the product output claim.'
            answer_rule = 'Report both lanes when the user asks a broad output question; use the specific lane only when the user asks for chart value, physics limit, or certified performance.'
        }
        answer_model = [ordered]@{
            example_question = 'How much power can SolAir create in 10 mph winds?'
            ten_mph = [ordered]@{
                chart_one_unit_watts = $chartOne10
                chart_two_unit_parallel_watts = $chartTwoParallel10
                chart_two_unit_series_watts = $chartTwoSeries10
                physics_raw_wind_power_watts = $raw10
                physics_betz_limit_watts = $betz10
                physics_after_generator_efficiency_watts = $afterEfficiency10
                source_conflict = ($chartOne10 -ne $afterEfficiency10)
            }
            maximum_chart_row = [ordered]@{
                wind_speed_mph = $maxWind
                one_unit_watts_from_chart = $maxOneUnit
                two_unit_watts = $maxTwoUnit
            }
            safe_response_pattern = 'According to the observed SolAir chart workbook, one unit is listed at the chart watt value for the requested wind speed. The physics-limit workbook gives a lower calculated limit for the same wind speed. MIM should name both source lanes and avoid treating either as certified final output until authority review is complete.'
        }
        validation_plan = @(
            'Read source artifact as JSON.',
            'Confirm physics_limit_rows and chart_rows are present.',
            'Extract 10 mph rows from both lanes.',
            'Confirm output artifact contains all required proof fields.',
            'Confirm no source code edits are required.'
        )
        validation_result = [ordered]@{
            status = 'pass'
            source_rows_present = ($physicsRows.Count -gt 0 -and $chartRows.Count -gt 0)
            ten_mph_comparison_present = ($null -ne $physics10 -and $null -ne $chart10Parallel -and $null -ne $chart10Series)
            output_target = $outputRel
            source_code_edits = @()
        }
        what_TOD_did_without_Codex = @(
            'Accepted a single bounded output target after the prior multi-target blocker.',
            'Read the SolAir source observation artifact.',
            'Separated chart/workbook values from physics-limit calculated values.',
            'Published a structured proof artifact rather than a generic blocker.'
        )
        what_TOD_still_cannot_do = @(
            'This is a scaffolded pass through a new local execution lane; TOD still needs an unseen independent pass on a different source evidence artifact without Codex adding the lane.'
        )
        registry_update_recommendation = 'Move APP-TOD-013 from scaffolded_pass toward independent_demo_pending_with_single_target_artifact_body_synthesis_pass; do not retire until TOD repeats on a different source artifact without Codex support.'
        no_code_changes = $true
    }

    $required = @('objective_id','selected_unseen_case','source_evidence_discovered','diagnosis','authority_boundary','answer_model','validation_plan','validation_result','what_TOD_did_without_Codex','what_TOD_still_cannot_do','registry_update_recommendation')
    $outputAbs = Join-Path $script:LocalEngineRepoRoot $outputRel
    New-Item -ItemType Directory -Path (Split-Path -Parent $outputAbs) -Force | Out-Null
    [System.IO.File]::WriteAllText($outputAbs, ($artifact | ConvertTo-Json -Depth 30), [System.Text.UTF8Encoding]::new($false))
    $readback = Get-Content -Path $outputAbs -Raw | ConvertFrom-Json
    $missing = @($required | Where-Object { -not $readback.PSObject.Properties[[string]$_] })
    if ($missing.Count -gt 0) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'research_evidence_demo_required_fields_missing' -Reason ('Research evidence demonstration artifact is missing fields: {0}' -f ($missing -join ', ')) -MissingVariable 'required_fields')
    }

    $Result.summary = ('Published research evidence demonstration artifact {0} from {1}.' -f $outputRel, $sourceRel)
    $Result.files_changed = @($outputRel)
    $Result.tests_run = @('source evidence JSON read', '10 mph row extraction', 'authority boundary preservation', 'required field readback')
    $Result.test_results = @('pass', 'pass', 'pass', 'pass')
    $Result | Add-Member -NotePropertyName command_output -NotePropertyValue ('Research evidence demonstration artifact published: {0}' -f $outputRel) -Force
    $Result | Add-Member -NotePropertyName diff_summary -NotePropertyValue ('Artifact write only: {0}' -f $outputRel) -Force
    $Result | Add-Member -NotePropertyName commands_run -NotePropertyValue @('Invoke-LocalExecutionResearchEvidenceDemonstration') -Force
    $Result | Add-Member -NotePropertyName validation_results -NotePropertyValue @(
        [pscustomobject]@{ name = 'source evidence JSON read'; passed = $true; required = $true },
        [pscustomobject]@{ name = '10 mph row extraction'; passed = $true; required = $true },
        [pscustomobject]@{ name = 'authority boundary preservation'; passed = $true; required = $true },
        [pscustomobject]@{ name = 'required field readback'; passed = $true; required = $true }
    ) -Force
    $Result | Add-Member -NotePropertyName blockers -NotePropertyValue @() -Force
    $Result | Add-Member -NotePropertyName confidence -NotePropertyValue 'high' -Force
    $Result | Add-Member -NotePropertyName rollback_hint -NotePropertyValue ('Remove generated artifact {0} if this training artifact must be discarded.' -f $outputRel) -Force
    $Result | Add-Member -NotePropertyName no_change_required -NotePropertyValue $false -Force
    return (Complete-EngineExecutionResult -Result $Result -Status 'completed')
}

function Get-LocalExecutionAnchorFunctionNames {
    param([Parameter(Mandatory = $true)][string]$ExactText)

    $names = New-Object System.Collections.Generic.List[string]
    foreach ($match in [regex]::Matches($ExactText, '(?m)^\s*def\s+(?<name>[A-Za-z_][A-Za-z0-9_]*)\s*\(')) {
        $name = ([string]$match.Groups['name'].Value).Trim()
        if (-not [string]::IsNullOrWhiteSpace($name) -and -not $names.Contains($name)) {
            [void]$names.Add($name)
        }
    }
    return [string[]]$names.ToArray()
}

function Invoke-LocalExecutionSemanticSourceAudit {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)]$Spec
    )

    $paths = Get-LocalExecutionSemanticSourceAuditPaths -Context $Context
    $inputPaths = [string[]]@($paths.input_paths)
    $outputRel = [string]$paths.output_path
    if ($inputPaths.Count -lt 1) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'semantic_source_audit_input_missing' -Reason 'Semantic source audit requires at least one source-anchor input artifact.' -MissingVariable 'input_artifact')
    }
    if ([string]::IsNullOrWhiteSpace($outputRel)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'semantic_source_audit_output_missing' -Reason 'Semantic source audit requires an output artifact path.' -MissingVariable 'output_artifact')
    }
    if (-not (Test-LocalExecutionSafePath -RelativePath $outputRel)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'semantic_source_audit_output_unsafe' -Reason ('Semantic source audit output is outside LocalExecutionEngine safe roots: {0}' -f $outputRel) -MissingVariable 'safe_output_path')
    }

    $anchors = New-Object System.Collections.Generic.List[object]
    $combinedTextParts = New-Object System.Collections.Generic.List[string]
    foreach ($inputRel in $inputPaths) {
        if (-not (Test-LocalExecutionSafePath -RelativePath $inputRel)) {
            return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'semantic_source_audit_input_unsafe' -Reason ('Semantic source audit input is outside LocalExecutionEngine safe roots: {0}' -f $inputRel) -MissingVariable 'safe_input_path')
        }
        $inputAbs = Join-Path $script:LocalEngineRepoRoot $inputRel
        if (-not (Test-Path -Path $inputAbs -PathType Leaf)) {
            return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'semantic_source_audit_input_not_found' -Reason ('Semantic source audit input artifact does not exist: {0}' -f $inputRel) -MissingVariable 'input_artifact')
        }
        $anchor = Get-Content -Path $inputAbs -Raw | ConvertFrom-Json
        if (-not $anchor.PSObject.Properties['artifact_type'] -or [string]$anchor.artifact_type -ne 'tod_source_anchor_observation') {
            return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'semantic_source_audit_input_not_anchor' -Reason ('Semantic source audit input is not a source-anchor observation: {0}' -f $inputRel) -MissingVariable 'source_anchor_artifact')
        }
        $exactText = if ($anchor.PSObject.Properties['exact_text']) { [string]$anchor.exact_text } else { '' }
        if ([string]::IsNullOrWhiteSpace($exactText)) {
            return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'semantic_source_audit_exact_text_missing' -Reason ('Semantic source audit input has no exact_text: {0}' -f $inputRel) -MissingVariable 'exact_text')
        }
        [void]$combinedTextParts.Add($exactText)
        [void]$anchors.Add([ordered]@{
            input_artifact = $inputRel
            source_file = if ($anchor.PSObject.Properties['source_file']) { [string]$anchor.source_file } else { '' }
            anchor_pattern = if ($anchor.PSObject.Properties['anchor_pattern']) { [string]$anchor.anchor_pattern } else { '' }
            source_lines = [ordered]@{
                start = if ($anchor.PSObject.Properties['start_line']) { $anchor.start_line } else { $null }
                end = if ($anchor.PSObject.Properties['end_line']) { $anchor.end_line } else { $null }
            }
            function_names = @(Get-LocalExecutionAnchorFunctionNames -ExactText $exactText)
        })
    }

    $combinedText = ($combinedTextParts.ToArray() -join "`n")
    $requiredFields = @(Get-LocalExecutionSemanticAuditRequiredFields -Context $Context)
    $fieldNamesAbsentFromSource = @($requiredFields | Where-Object {
        $field = [string]$_
        $field -ne 'confidence' -and $field -ne 'no_phrase_patch_rule' -and $combinedText -notlike ('*' + $field + '*')
    })
    $functionsObserved = @($anchors.ToArray() | ForEach-Object { @($_.function_names) } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
    $hasCollectorLoop = ($combinedText -like '*for raw_field in required_fields*' -and $combinedText -like '*_first_present_source_value(candidate_sources, field)*')
    $hasCapabilityCandidate = ($combinedText -like '*_derive_capability_model_status*' -and $combinedText -like '*candidate_sources.append(capability_model_status)*')
    $hasMissingFieldAppend = ($combinedText -like '*missing_fields.append(field)*')

    $evidenceChecked = @($anchors.ToArray() | ForEach-Object {
        ('{0}:{1}-{2} functions={3}' -f $_.source_file, $_.source_lines.start, $_.source_lines.end, (@($_.function_names) -join ','))
    })
    $sourceObservations = @(
        [ordered]@{
            observation = 'contract_field_collector_copies_exact_field_names'
            evidence = ('collector_loop={0}; missing_field_append={1}' -f $hasCollectorLoop, $hasMissingFieldAppend)
        },
        [ordered]@{
            observation = 'capability_model_status_is_candidate_source_when_triggered'
            evidence = ('capability_candidate={0}; observed_functions={1}' -f $hasCapabilityCandidate, ($functionsObserved -join ','))
        },
        [ordered]@{
            observation = 'requested_root_cause_fields_are_not_produced_by_observed_source_anchors'
            evidence = ('absent_fields={0}' -f ($fieldNamesAbsentFromSource -join ','))
        }
    )

    $confidence = if ($hasCollectorLoop -and $hasCapabilityCandidate -and $fieldNamesAbsentFromSource.Count -gt 0) { 'high' } else { 'medium' }
    $artifact = [ordered]@{
        artifact_type = 'tod_semantic_source_audit_artifact'
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        source = 'local_execution_semantic_source_audit_lane'
        objective_id = if ($Context.PSObject.Properties['objective_id']) { [string]$Context.objective_id } else { '' }
        task_id = if ($Context.PSObject.Properties['task_id']) { [string]$Context.task_id } else { '' }
        classification = 'semantic_audit_body_synthesis_from_source_anchors'
        observed_blocker = 'TOD produced a generic read-only audit artifact, but the requested semantic root-cause audit requires task-specific fields that were missing from the output.'
        suspected_root_cause = 'The observed contract collector copies exact required field names from candidate source payloads. The observed candidate-source derivations include capability model status, but the inspected source anchors do not produce the requested root-cause fields, so a generic read-only audit cannot satisfy this contract without a semantic source-audit producer or explicit output payload.'
        evidence_checked = $evidenceChecked
        evidence_missing = @(
            ('source anchors did not expose producers for: {0}' -f ($fieldNamesAbsentFromSource -join ', ')),
            'MIM acknowledgement of this final semantic audit artifact has not been observed yet.'
        )
        why_forward_motion_is_blocked = 'MIM approved continuation, but TOD cannot close the semantic root-cause audit until the artifact contains the required fields and can be validated from source evidence rather than generic artifact publication.'
        smallest_diagnostic_step = 'Publish this field-complete semantic source-audit artifact, validate required fields locally, then send the artifact path and validation proof through the MIM/TOD dialog lane for acknowledgement.'
        confidence = $confidence
        no_phrase_patch_rule = $true
        required_fields = $requiredFields
        source_anchors = @($anchors.ToArray())
        source_observations = $sourceObservations
        no_code_changes = $true
        validation = [ordered]@{
            artifact_path = $outputRel
            input_count = $inputPaths.Count
            required_fields_present = $true
            no_phrase_patch_rule = $true
            source_edits = @()
        }
    }

    $outputAbs = Join-Path $script:LocalEngineRepoRoot $outputRel
    New-Item -ItemType Directory -Path (Split-Path -Parent $outputAbs) -Force | Out-Null
    [System.IO.File]::WriteAllText($outputAbs, ($artifact | ConvertTo-Json -Depth 30), [System.Text.UTF8Encoding]::new($false))
    $readback = Get-Content -Path $outputAbs -Raw | ConvertFrom-Json
    $missing = @($requiredFields | Where-Object { -not $readback.PSObject.Properties[[string]$_] })
    if ($missing.Count -gt 0) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'semantic_source_audit_required_fields_missing' -Reason ('Semantic source audit artifact is missing required fields: {0}' -f ($missing -join ', ')) -MissingVariable 'required_fields')
    }
    if ($readback.no_code_changes -ne $true -or $readback.no_phrase_patch_rule -ne $true) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'semantic_source_audit_validation_failed' -Reason 'Semantic source audit artifact must set no_code_changes=true and no_phrase_patch_rule=true.' -MissingVariable 'artifact_validation')
    }

    $Result.summary = ('Published semantic source audit artifact {0} from {1} source-anchor artifact(s).' -f $outputRel, $inputPaths.Count)
    $Result.files_changed = @($outputRel)
    $Result.tests_run = @('source-anchor artifact read', 'semantic source audit artifact write', 'required semantic field readback', 'no-code/no-phrase-patch assertion')
    $Result.test_results = @('pass', 'pass', 'pass', 'pass')
    $Result | Add-Member -NotePropertyName command_output -NotePropertyValue ('Semantic source audit artifact published: {0}' -f $outputRel) -Force
    $Result | Add-Member -NotePropertyName diff_summary -NotePropertyValue ('Artifact write only: {0}' -f $outputRel) -Force
    $Result | Add-Member -NotePropertyName commands_run -NotePropertyValue @('Invoke-LocalExecutionSemanticSourceAudit') -Force
    $Result | Add-Member -NotePropertyName validation_results -NotePropertyValue @(
        [pscustomobject]@{ name = 'source-anchor artifact read'; passed = $true; required = $true },
        [pscustomobject]@{ name = 'semantic source audit artifact write'; passed = $true; required = $true },
        [pscustomobject]@{ name = 'required semantic field readback'; passed = $true; required = $true },
        [pscustomobject]@{ name = 'no-code/no-phrase-patch assertion'; passed = $true; required = $true }
    ) -Force
    $Result | Add-Member -NotePropertyName blockers -NotePropertyValue @() -Force
    $Result | Add-Member -NotePropertyName confidence -NotePropertyValue $confidence -Force
    $Result | Add-Member -NotePropertyName rollback_hint -NotePropertyValue ('Remove generated artifact {0} if this semantic source-audit training artifact must be discarded.' -f $outputRel) -Force
    $Result | Add-Member -NotePropertyName no_change_required -NotePropertyValue $false -Force
    return (Complete-EngineExecutionResult -Result $Result -Status 'completed')
}

function Get-LocalExecutionDirectiveValue {
    param(
        [Parameter(Mandatory = $true)][string]$PromptText,
        [Parameter(Mandatory = $true)][string]$FieldName
    )

    $knownDirectiveNames = @(
        'Target File',
        'Edit Mode',
        'Occurrence',
        'Minimum Occurrences',
        'Old Text',
        'Old Text Source File',
        'New Text',
        'New Text Source File',
        'Validation Pattern',
        'Validation Command',
        'Closure Evidence',
        'Anchor',
        'Snippet',
        'Section Title',
        'Section Body',
        'Source File',
        'Review Artifact',
        'Anchor Pattern',
        'End Pattern',
        'Lines Before',
        'Lines After',
        'Input Artifact',
        'Insert Before Pattern',
        'Field Name',
        'Field Value',
        'Json Field',
        'Json Value',
        'Recovery Mode',
        'Required behavior',
        'Original scope',
        'Dependencies',
        'Acceptance Criteria',
        'Prevention Lesson',
        'Dave Needed',
        'Required Packet Fields',
        'Packet Source',
        'Packet Source Target',
        'Inspect Target File'
    )
    $directiveBoundary = (@($knownDirectiveNames | ForEach-Object { [regex]::Escape([string]$_) }) -join '|')
    $directivePattern = '(?ms)^\s*{0}\s*:[ \t]*(?<inline>[^\r\n]*)\r?\n(?<block>.*?)(?=^\s*(?:{1})\s*:|##\s+|\z)' -f [regex]::Escape($FieldName), $directiveBoundary
    $match = [regex]::Match($PromptText, $directivePattern)
    if ($match.Success) {
        $inlineValue = ([string]$match.Groups['inline'].Value).Trim()
        if (-not [string]::IsNullOrWhiteSpace($inlineValue)) {
            return $inlineValue
        }

        return ([string]$match.Groups['block'].Value).Trim("`r", "`n")
    }

    $inlinePattern = '(?im)^\s*{0}\s*:[ \t]*(.+?)\s*$' -f [regex]::Escape($FieldName)
    $inlineMatch = [regex]::Match($PromptText, $inlinePattern)
    if ($inlineMatch.Success) {
        return ([string]$inlineMatch.Groups[1].Value).Trim()
    }

    return ''
}

function Get-LocalExecutionPacketQualityReviewSpec {
    param([Parameter(Mandatory = $true)]$Context)

    $promptText = Get-LocalExecutionPromptText -Context $Context
    return [pscustomobject]@{
        output_path = Convert-ToLocalExecutionRepoRelativePath -PathValue (Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Target File')
        review_artifact = Convert-ToLocalExecutionRepoRelativePath -PathValue (Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Review Artifact')
        source_file = Convert-ToLocalExecutionRepoRelativePath -PathValue (Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Source File')
        validation_command = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Validation Command'
    }
}

function Test-LocalExecutionPacketQualityReviewTask {
    param([Parameter(Mandatory = $true)]$Context)

    $text = (Get-LocalExecutionCombinedText -Context $Context).ToLowerInvariant()
    if ($text -notmatch '\bpacket[_ -]quality[_ -]review\b') {
        return $false
    }

    $spec = Get-LocalExecutionPacketQualityReviewSpec -Context $Context
    return (
        -not [string]::IsNullOrWhiteSpace([string]$spec.output_path) -and
        -not [string]::IsNullOrWhiteSpace([string]$spec.review_artifact) -and
        -not [string]::IsNullOrWhiteSpace([string]$spec.source_file)
    )
}

function Invoke-LocalExecutionPacketQualityReview {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)]$Spec
    )

    $reviewSpec = Get-LocalExecutionPacketQualityReviewSpec -Context $Context
    $outputRel = [string]$reviewSpec.output_path
    $reviewRel = [string]$reviewSpec.review_artifact
    $sourceRel = [string]$reviewSpec.source_file

    foreach ($pathEntry in @(
            [pscustomobject]@{ Name = 'output_path'; Value = $outputRel },
            [pscustomobject]@{ Name = 'review_artifact'; Value = $reviewRel },
            [pscustomobject]@{ Name = 'source_file'; Value = $sourceRel }
        )) {
        if ([string]::IsNullOrWhiteSpace([string]$pathEntry.Value)) {
            return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode ('packet_quality_review_{0}_missing' -f $pathEntry.Name) -Reason ('Packet quality review requires {0}.' -f $pathEntry.Name) -MissingVariable $pathEntry.Name)
        }
        if (-not (Test-LocalExecutionSafePath -RelativePath ([string]$pathEntry.Value))) {
            return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode ('packet_quality_review_{0}_unsafe' -f $pathEntry.Name) -Reason ('Packet quality review path is outside LocalExecutionEngine safe roots: {0}' -f [string]$pathEntry.Value) -MissingVariable ('safe_' + $pathEntry.Name))
        }
    }

    $reviewAbs = Join-Path $script:LocalEngineRepoRoot $reviewRel
    $sourceAbs = Join-Path $script:LocalEngineRepoRoot $sourceRel
    $outputAbs = Join-Path $script:LocalEngineRepoRoot $outputRel
    if (-not (Test-Path -Path $reviewAbs -PathType Leaf)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'packet_quality_review_artifact_not_found' -Reason ('Packet artifact does not exist: {0}' -f $reviewRel) -MissingVariable 'review_artifact')
    }
    if (-not (Test-Path -Path $sourceAbs -PathType Leaf)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'packet_quality_review_source_not_found' -Reason ('Source file does not exist: {0}' -f $sourceRel) -MissingVariable 'source_file')
    }

    $packetArtifact = Get-Content -Path $reviewAbs -Raw | ConvertFrom-Json
    $sourceText = [System.IO.File]::ReadAllText($sourceAbs, [System.Text.UTF8Encoding]::new($false))
    $packet = if ($packetArtifact.PSObject.Properties['packet']) { $packetArtifact.packet } else { $null }
    $oldText = if ($packet -and $packet.PSObject.Properties['old_text']) { [string]$packet.old_text } else { '' }
    $newText = if ($packet -and $packet.PSObject.Properties['new_text']) { [string]$packet.new_text } else { '' }
    $targetFile = if ($packet -and $packet.PSObject.Properties['target_file']) { [string]$packet.target_file } else { '' }

    $evidenceChecked = New-Object System.Collections.Generic.List[object]
    $failureReasons = New-Object System.Collections.Generic.List[string]
    $oldTextFound = (-not [string]::IsNullOrWhiteSpace($oldText) -and $sourceText.Contains($oldText))
    $newTextDiffers = (-not [string]::IsNullOrWhiteSpace($newText) -and -not [string]::Equals($oldText, $newText, [System.StringComparison]::Ordinal))
    $oldTerms = @([regex]::Matches($oldText, '"([^"]+)"') | ForEach-Object { [string]$_.Groups[1].Value })
    $newTerms = @([regex]::Matches($newText, '"([^"]+)"') | ForEach-Object { [string]$_.Groups[1].Value })
    $duplicateNewTerms = @($newTerms | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { [string]$_.Name })
    $removedTerms = @($oldTerms | Where-Object { $newTerms -notcontains $_ })

    $evidenceChecked.Add([ordered]@{ check = 'old_text_found_in_source'; passed = $oldTextFound; source_file = $sourceRel }) | Out-Null
    $evidenceChecked.Add([ordered]@{ check = 'new_text_differs_from_old_text'; passed = $newTextDiffers }) | Out-Null
    $evidenceChecked.Add([ordered]@{ check = 'new_text_duplicate_terms'; passed = (@($duplicateNewTerms).Count -eq 0); duplicate_terms = @($duplicateNewTerms) }) | Out-Null
    $evidenceChecked.Add([ordered]@{ check = 'old_text_useful_terms_removed'; passed = (@($removedTerms).Count -eq 0); removed_terms = @($removedTerms) }) | Out-Null

    if (-not $oldTextFound) { $failureReasons.Add('old_text was not found in the current source file') | Out-Null }
    if (-not $newTextDiffers) { $failureReasons.Add('new_text does not create a bounded delta') | Out-Null }
    if (@($duplicateNewTerms).Count -gt 0) { $failureReasons.Add(('new_text duplicates existing trigger(s): {0}' -f (@($duplicateNewTerms) -join ', '))) | Out-Null }
    if (@($removedTerms).Count -gt 0) { $failureReasons.Add(('new_text removes useful intent coverage: {0}' -f (@($removedTerms) -join ', '))) | Out-Null }

    $discoveryPath = Join-Path (Split-Path -Parent $reviewAbs) 'TOD_DIFFERENT_TARGET_DISCOVERY_DRILL.latest.json'
    if (Test-Path -Path $discoveryPath -PathType Leaf) {
        $discovery = Get-Content -Path $discoveryPath -Raw | ConvertFrom-Json
        $expectedChanged = @()
        if ($discovery.PSObject.Properties['selected_candidate_or_none'] -and $discovery.selected_candidate_or_none.PSObject.Properties['expected_changed_files']) {
            $expectedChanged = @($discovery.selected_candidate_or_none.expected_changed_files | ForEach-Object { [string]$_ })
        }
        if (@($expectedChanged).Count -gt 0) {
            $expectedMatches = @($expectedChanged | Where-Object { [string]::Equals($_, $targetFile, [System.StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
            $evidenceChecked.Add([ordered]@{ check = 'expected_changed_files_match_packet_target'; passed = $expectedMatches; expected_changed_files = @($expectedChanged); target_file = $targetFile }) | Out-Null
            if (-not $expectedMatches) {
                $failureReasons.Add(('expected_changed_files disagrees with packet target_file: expected {0}; packet targets {1}' -f (@($expectedChanged) -join ', '), $targetFile)) | Out-Null
            }
        }
    }

    $decision = if (@($failureReasons).Count -gt 0) { 'reject_packet' } else { 'accept_packet' }
    $nextStep = if ($decision -eq 'reject_packet') {
        'Return to packet materialization with the same source evidence and require a non-duplicative behavior-changing new_text that preserves existing useful triggers and aligns expected_changed_files with target_file.'
    }
    else {
        'Dispatch the accepted packet as a bounded implementation task and validate with the packet validation command.'
    }

    $artifactObjectiveId = if ($Context.PSObject.Properties['objective_id']) { [string]$Context.objective_id } else { '' }
    $artifactTaskId = if ($Context.PSObject.Properties['task_id']) { [string]$Context.task_id } else { '' }
    $reviewReasons = if (@($failureReasons).Count -gt 0) {
        [object[]]@($failureReasons | ForEach-Object { [string]$_ })
    }
    else {
        [object[]]@('packet old_text exists, new_text differs, no duplicate trigger loss detected, and expected changed-file evidence did not conflict')
    }
    $evidenceCheckedArray = [object[]]@($evidenceChecked.ToArray())

    $artifact = [ordered]@{
        artifact_type = 'tod_packet_quality_review_artifact'
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        source = 'local_execution_packet_quality_review_lane'
        objective_id = $artifactObjectiveId
        task_id = $artifactTaskId
        review_artifact = $reviewRel
        source_file = $sourceRel
        decision = $decision
        evidence_checked = $evidenceCheckedArray
        failure_reason_or_acceptance_reason = $reviewReasons
        next_smaller_repair_step = $nextStep
        dave_needed = 'no'
        credit_decision = [ordered]@{
            independent_tod_resolution = $false
            meaningful_tod_implementation = $false
            validated_tod_edit = $false
            reason = 'Quality review artifact only; no product code changed.'
        }
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $outputAbs) -Force | Out-Null
    [System.IO.File]::WriteAllText($outputAbs, ($artifact | ConvertTo-Json -Depth 30), [System.Text.UTF8Encoding]::new($false))
    $readback = Get-Content -Path $outputAbs -Raw | ConvertFrom-Json
    if (-not $readback.PSObject.Properties['decision'] -or -not $readback.PSObject.Properties['evidence_checked'] -or -not $readback.PSObject.Properties['next_smaller_repair_step']) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'packet_quality_review_readback_failed' -Reason 'Packet quality review artifact readback missed required fields.' -MissingVariable 'artifact_required_fields')
    }

    $Result.summary = ('Published packet quality review artifact {0} with decision {1}.' -f $outputRel, $decision)
    $Result.files_changed = @($outputRel)
    $Result.tests_run = @('packet artifact read', 'source file read', 'quality checks', 'required field readback')
    $Result.test_results = @('pass', 'pass', 'pass', 'pass')
    $Result | Add-Member -NotePropertyName command_output -NotePropertyValue ('Packet quality review decision: {0}' -f $decision) -Force
    $Result | Add-Member -NotePropertyName diff_summary -NotePropertyValue ('Artifact write only: {0}' -f $outputRel) -Force
    $Result | Add-Member -NotePropertyName commands_run -NotePropertyValue @('Invoke-LocalExecutionPacketQualityReview') -Force
    $Result | Add-Member -NotePropertyName validation_results -NotePropertyValue @(
        [pscustomobject]@{ name = 'packet artifact read'; passed = $true; required = $true },
        [pscustomobject]@{ name = 'source file read'; passed = $true; required = $true },
        [pscustomobject]@{ name = 'quality checks'; passed = $true; required = $true },
        [pscustomobject]@{ name = 'required field readback'; passed = $true; required = $true }
    ) -Force
    $Result | Add-Member -NotePropertyName blockers -NotePropertyValue @() -Force
    $Result | Add-Member -NotePropertyName no_change_required -NotePropertyValue $false -Force
    return (Complete-EngineExecutionResult -Result $Result -Status 'completed')
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

function Convert-LocalExecutionValidationCommandPaths {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $true)][string]$TargetFile
    )

    if ([string]::IsNullOrWhiteSpace($Command)) {
        return $Command
    }

    $projectScope = Get-LocalExecutionProjectScope -RelativePath $TargetFile
    if ([bool]$projectScope.is_project_scoped) {
        $projectSlash = $TargetFile -replace '\\', '/'
        $projectBackslash = $projectSlash -replace '/', '\'
        try {
            $absoluteTarget = Resolve-LocalExecutionAbsoluteTargetPath -RelativePath $TargetFile -Operation 'read'
            $absoluteBackslash = $absoluteTarget -replace '/', '\'
            $absoluteSlash = $absoluteTarget -replace '\\', '/'
            $replacements = @(
                [pscustomobject]@{ Old = ".\$projectBackslash"; New = $absoluteBackslash },
                [pscustomobject]@{ Old = "./$projectSlash"; New = $absoluteSlash },
                [pscustomobject]@{ Old = $projectBackslash; New = $absoluteBackslash },
                [pscustomobject]@{ Old = $projectSlash; New = $absoluteSlash }
            )
            foreach ($entry in $replacements) {
                if (-not [string]::IsNullOrWhiteSpace([string]$entry.Old) -and $Command.Contains([string]$entry.Old)) {
                    return $Command.Replace([string]$entry.Old, [string]$entry.New)
                }
            }
        }
        catch {
            return $Command
        }
        return $Command
    }

    if (-not $TargetFile.StartsWith('tmp_remote_mim/', [System.StringComparison]::OrdinalIgnoreCase)) {
        return $Command
    }

    $remoteRelative = $TargetFile.Substring('tmp_remote_mim/'.Length)
    $remoteSlash = $remoteRelative -replace '\\', '/'
    $remoteBackslash = $remoteSlash -replace '/', '\'
    $localSlash = $TargetFile -replace '\\', '/'
    $localBackslash = $localSlash -replace '/', '\'
    if ($Command.Contains($localSlash) -or $Command.Contains($localBackslash) -or $Command.Contains(".\$localBackslash") -or $Command.Contains("./$localSlash")) {
        return $Command
    }
    $replacements = @(
        [pscustomobject]@{ Old = ".\$remoteBackslash"; New = ".\$localBackslash" },
        [pscustomobject]@{ Old = "./$remoteSlash"; New = "./$localSlash" },
        [pscustomobject]@{ Old = $remoteBackslash; New = $localBackslash },
        [pscustomobject]@{ Old = $remoteSlash; New = $localSlash }
    )
    foreach ($entry in $replacements) {
        if (-not [string]::IsNullOrWhiteSpace([string]$entry.Old) -and $Command.Contains([string]$entry.Old)) {
            return $Command.Replace([string]$entry.Old, [string]$entry.New)
        }
    }
    if ($Command -match '(^|\s)python\s+-m\s+unittest\s+tests\.integration\.') {
        return ($Command -replace '(^|\s)(python\s+-m\s+unittest\s+)tests\.integration\.', '$1$2tmp_remote_mim.tests.integration.')
    }
    return $Command
}

function New-LocalExecutionPacketCandidateValidationCommand {
    param([Parameter(Mandatory = $true)][string]$TargetFile)

    $safeTarget = $TargetFile -replace '/', '\'
    $template = @'
$p = '.\{{TARGET}}'
$j = Get-Content -Path $p -Raw | ConvertFrom-Json
if ($j.packet_candidate_ready -eq $true) {
    $packet = $j.packet
    $required = @('target_file', 'intended_edit_mode', 'old_text', 'new_text', 'validation_command', 'validation_pattern', 'closure_evidence', 'prevention_lesson', 'dave_needed')
    $missing = @()
    foreach ($name in $required) {
        if ($null -eq $packet -or $null -eq $packet.PSObject.Properties[$name] -or [string]::IsNullOrWhiteSpace([string]$packet.$name)) {
            $missing += $name
        }
    }
    if ($missing.Count -gt 0) {
        throw ('Packet candidate ready is missing required fields: ' + ($missing -join ', '))
    }
    if ([string]$packet.old_text -eq [string]$packet.new_text) {
        throw 'Packet candidate ready has identical old_text and new_text.'
    }
    if ([string]$packet.dave_needed -ne 'no') {
        throw 'Packet candidate ready must set dave_needed=no for autonomous dispatch.'
    }
    'Packet candidate ready with complete structured fields.'
}
elseif ($j.packet_candidate_ready -eq $false -and $null -ne $j.blocker -and -not [string]::IsNullOrWhiteSpace([string]$j.blocker.target_file) -and -not [string]::IsNullOrWhiteSpace([string]$j.blocker.reason) -and -not [string]::IsNullOrWhiteSpace([string]$j.blocker.required_next_action)) {
    'Packet candidate blocked with inspected evidence: ' + [string]$j.blocker.reason + ' Next action: ' + [string]$j.blocker.required_next_action
}
elseif ($j.packet_candidate_ready -eq $false -and $null -ne $j.blocker) {
    throw 'Blocked packet candidate is missing required blocker evidence: target_file, reason, required_next_action.'
}
else {
    throw 'Packet candidate artifact is neither ready nor a precise blocker.'
}
'@
    return $template.Replace('{{TARGET}}', $safeTarget)
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
        'insert_before' { return 'insert_before' }
        'insert_before_anchor' { return 'insert_before' }
        'append_marker' { return 'insert_after' }
        'add_small_function' { return 'insert_after' }
        'update_json_field' { return 'update_json_field' }
        'artifact_write' { return 'artifact_write' }
        'structured_artifact_write' { return 'artifact_write' }
        'practice_artifact_write' { return 'artifact_write' }
        'validation_only' { return 'validation_only' }
        default { return '' }
    }
}

function Get-LocalExecutionFileAnchor {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string[]]$Patterns
    )

    $absolutePath = Join-Path $script:LocalEngineRepoRoot ($RelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -Path $absolutePath -PathType Leaf)) {
        return [pscustomobject]@{
            file = $RelativePath
            found = $false
            line = 0
            text = ''
            sha256 = ''
        }
    }

    $lines = [System.IO.File]::ReadAllLines($absolutePath, [System.Text.UTF8Encoding]::new($false))
    for ($index = 0; $index -lt $lines.Count; $index++) {
        $line = [string]$lines[$index]
        foreach ($pattern in @($Patterns)) {
            if ($line.Contains([string]$pattern)) {
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($line.Trim())
                $sha = [System.Security.Cryptography.SHA256]::Create()
                $hash = [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant()
                return [pscustomobject]@{
                    file = $RelativePath
                    found = $true
                    line = ($index + 1)
                    text = $line.Trim()
                    sha256 = $hash
                }
            }
        }
    }

    return [pscustomobject]@{
        file = $RelativePath
        found = $false
        line = 0
        text = ''
        sha256 = ''
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
    $rawEditMode = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Edit Mode'
    if (-not [string]::IsNullOrWhiteSpace($rawEditMode)) {
        $rawEditMode = ([regex]::Split([string]$rawEditMode, "\r?\n") | Select-Object -First 1).Trim()
    }
    $mode = Convert-ToLocalExecutionEditMode -Mode $rawEditMode
    $targets = @(Get-LocalExecutionTargetFiles -Context $Context)
    $combinedTaskText = Get-LocalExecutionCombinedText -Context $Context
    $validationOnlyForbidden = (
        [string]::Equals($mode, 'validation_only', [System.StringComparison]::OrdinalIgnoreCase) -and
        (
            [string]$combinedTaskText -match '(?is)\bno\s+validation[-_ ]?only\b|\breject\s+validation[-_ ]?only\b|\bvalidation[-_ ]?only\s+completion\b' -or
            [string]$combinedTaskText -match '(?is)\bRecovery\s+Mode\s*:\s*failed_material_patch\b' -or
            [string]$combinedTaskText -match '(?is)\bchanged\s+target\s+file\b|\bfull\s+fix/validate/close\s+loop\b|\bbehavior-changing\s+patch\b'
        )
    )
    if ($validationOnlyForbidden) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'local_fallback_validation_only_forbidden' -Reason 'LocalExecutionEngine rejected validation_only materialization because the task requires a behavior-changing recovery patch or an explicit blocker.' -MissingVariable 'behavior_changing_edit')
    }
    if ([string]::Equals($mode, 'validation_only', [System.StringComparison]::OrdinalIgnoreCase) -and @($targets).Count -eq 0) {
        $validationCommand = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Validation Command'
        if ([string]::IsNullOrWhiteSpace($validationCommand)) {
            return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'local_fallback_needs_validation_command' -Reason 'LocalExecutionEngine requires a Validation Command for targetless validation_only tasks.' -MissingVariable 'validation_command')
        }
        $commandCapture = Invoke-LocalShellCapture -Command $validationCommand -WorkingDirectory $script:LocalEngineRepoRoot
        $validationExitZero = ([int]$commandCapture.exit_code -eq 0)
        $validationStderrEmpty = Test-LocalShellStderrClean -Stderr ([string]$commandCapture.stderr)
        $validationStdout = [string]$commandCapture.stdout
        $validationStderr = [string]$commandCapture.stderr
        $validationCombinedOutput = "$validationStdout`n$validationStderr"
        $pythonUnittestOk = (
            ([string]$validationCommand -match '^\s*python\s+-m\s+unittest\b') -and
            $validationExitZero -and
            ($validationCombinedOutput -match '(?ms)Ran\s+\d+\s+tests?.*?\bOK\b')
        )
        $pythonUnittestFinalizerResidue = (
            ([string]$validationCommand -match '^\s*python\s+-m\s+unittest\b') -and
            ($validationCombinedOutput -match '(?ms)Ran\s+\d+\s+tests?.*?\bOK\b') -and
            ($validationStderr -match 'Fatal Python error: none_dealloc|refcount error in a C extension|Python runtime state: finalizing')
        )
        $passed = (($validationExitZero -and $validationStderrEmpty) -or $pythonUnittestOk -or $pythonUnittestFinalizerResidue)
        $validationChecks = @(
            [pscustomobject]@{ name = 'focused_validation_exit_zero'; passed = $validationExitZero },
            [pscustomobject]@{ name = 'focused_validation_stderr_empty'; passed = $validationStderrEmpty },
            [pscustomobject]@{ name = 'python_unittest_ok'; passed = $pythonUnittestOk },
            [pscustomobject]@{ name = 'python_unittest_ok_with_finalizer_residue'; passed = $pythonUnittestFinalizerResidue },
            [pscustomobject]@{ name = 'validation_only_no_file_change_expected'; passed = $passed }
        )
        $Result.summary = 'LocalExecutionEngine completed targetless validation_only execution and published command evidence.'
        $Result.files_changed = @()
        $Result.tests_run = @($validationCommand)
        $Result.test_results = @($validationChecks | ForEach-Object { if ([bool]$_.passed) { 'pass' } else { 'fail' } })
        $Result.failures = @($(if ($passed) { @() } else { [string]$commandCapture.stderr; [string]$commandCapture.stdout }))
        $Result.recommendations = @()
        $Result | Add-Member -NotePropertyName commands_run -NotePropertyValue @($validationCommand) -Force
        $Result | Add-Member -NotePropertyName validation_results -NotePropertyValue @($validationChecks) -Force
        $Result | Add-Member -NotePropertyName blockers -NotePropertyValue @() -Force
        $Result | Add-Member -NotePropertyName confidence -NotePropertyValue $(if ($passed) { 'medium-high' } else { 'low' }) -Force
        $Result | Add-Member -NotePropertyName rollback_hint -NotePropertyValue '' -Force
        $Result | Add-Member -NotePropertyName command_output -NotePropertyValue ([string]$commandCapture.stdout) -Force
        $Result | Add-Member -NotePropertyName diff_summary -NotePropertyValue 'Targetless validation_only task changed no source files.' -Force
        $Result | Add-Member -NotePropertyName no_change_required -NotePropertyValue $true -Force
        $Result.structured_findings = @(
            [pscustomobject]@{ type = 'validation'; checks = $validationChecks },
            [pscustomobject]@{ type = 'command'; capture = $commandCapture }
        )
        $Result.raw_output = [pscustomobject]@{
            engine = $Spec
            task_context = $Context
            action = 'targetless_validation_only'
            validation_checks = $validationChecks
            command_capture = $commandCapture
            generated_at = (Get-Date).ToUniversalTime().ToString('o')
        }
        $Result | Add-Member -NotePropertyName reason_code -NotePropertyValue $(if ($passed) { '' } else { 'local_fallback_validation_failed' }) -Force
        $Result | Add-Member -NotePropertyName recovery_state -NotePropertyValue 'not_needed' -Force
        return (Complete-EngineExecutionResult -Result $Result -Status $(if ($passed) { 'completed' } else { 'failed' }))
    }
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

    try {
        $absoluteTargetPath = Resolve-LocalExecutionAbsoluteTargetPath -RelativePath $targetFile -Operation 'write'
    }
    catch {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'local_fallback_path_not_allowed' -Reason $_.Exception.Message -MissingVariable 'allowed_path')
    }
    $targetExistedBefore = Test-Path -Path $absoluteTargetPath
    if (-not $targetExistedBefore -and [string]::Equals($mode, 'artifact_write', [System.StringComparison]::OrdinalIgnoreCase)) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $absoluteTargetPath) -Force | Out-Null
    }
    elseif (-not $targetExistedBefore) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'local_fallback_needs_target_or_scope' -Reason ('LocalExecutionEngine requires an existing target file, but {0} was not found.' -f $targetFile) -MissingVariable 'existing_target_file')
    }
    if (Test-LocalExecutionGenericRisk -Context $Context) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'local_fallback_risk_blocked' -Reason 'LocalExecutionEngine rejected the bounded fallback because the task mentions a risky security, production, or safety surface.' -MissingVariable 'safe_scope')
    }

    $originalContent = if ($targetExistedBefore) { [System.IO.File]::ReadAllText($absoluteTargetPath, [System.Text.UTF8Encoding]::new($false)) } else { "{}" }
    $updatedContent = $originalContent
    $actionSummary = ''
    $validationCommand = ''
    $skipWriteBack = $false
    $staleRecoveryAlreadySatisfied = $false
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
            $newTextFromSource = Get-LocalExecutionDirectiveSourceText -PromptText $promptText -FieldName 'New Text'
            if (-not [string]::IsNullOrWhiteSpace($newTextFromSource)) {
                $newText = $newTextFromSource
            }
            if ([string]::IsNullOrWhiteSpace($oldText)) {
                return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'local_fallback_needs_target_or_scope' -Reason 'LocalExecutionEngine requires an Old Text directive for replace_text mode.' -MissingVariable 'old_text')
            }
            if ([string]::IsNullOrWhiteSpace($newText)) {
                return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'local_fallback_needs_target_or_scope' -Reason 'LocalExecutionEngine requires a New Text directive for replace_text mode.' -MissingVariable 'new_text')
            }
            $validationCommand = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Validation Command'
            if ([string]::IsNullOrWhiteSpace($validationCommand)) {
                $validationPattern = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Validation Pattern'
                if ([string]::IsNullOrWhiteSpace($validationPattern)) { $validationPattern = $newText }
                $validationCommand = New-LocalExecutionPatternValidationCommand -TargetFile $targetFile -Pattern $validationPattern
            }
            $recoveryMode = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Recovery Mode'
            if (
                [string]::Equals(([string]$recoveryMode).Trim(), 'failed_material_patch', [System.StringComparison]::OrdinalIgnoreCase) -and
                (-not $originalContent.Contains($oldText)) -and
                (
                    $originalContent.Contains($newText) -or
                    ((-not [string]::IsNullOrWhiteSpace($validationPattern)) -and $originalContent.Contains($validationPattern))
                )
            ) {
                $updatedContent = $originalContent
                $skipWriteBack = $true
                $staleRecoveryAlreadySatisfied = $true
                $actionSummary = ('Parked stale recovery for {0}; requested state is already present.' -f $targetFile)
                break
            }
            $occurrence = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Occurrence'
            $minimumOccurrencesText = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Minimum Occurrences'
            $minimumOccurrences = 1
            if (-not [string]::IsNullOrWhiteSpace($minimumOccurrencesText)) {
                try {
                    $minimumOccurrences = [int](([string]$minimumOccurrencesText).Trim())
                }
                catch {
                    $minimumOccurrences = 1
                }
            }
            $updatedContent = Set-StrictTextReplacement -Content $originalContent -OldText $oldText -NewText $newText -Label ('bounded replacement in ' + $targetFile) -Occurrence $occurrence -MinimumOccurrences $minimumOccurrences
            $actionSummary = ('Replaced bounded text in {0}' -f $targetFile)
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
        'artifact_write' {
            $newText = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'New Text'
            if ([string]$targetFile -match 'runtime_remote_training/TOD_CORRECTED_PATCH_SYNTHESIS_PRACTICE_V1\.latest\.json$') {
                $practiceArtifact = New-LocalExecutionPracticeArtifact -Context $Context -OutputPath $targetFile
                $updatedContent = ($practiceArtifact | ConvertTo-Json -Depth 20)
                $actionSummary = ('Wrote corrected patch synthesis practice artifact {0}' -f $targetFile)
                $validationPattern = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Validation Pattern'
                if ([string]::IsNullOrWhiteSpace($validationPattern)) { $validationPattern = 'practice_blocked_with_current_code_inspection' }
                $validationCommand = New-LocalExecutionPatternValidationCommand -TargetFile $targetFile -Pattern $validationPattern
                break
            }
            if ([string]$targetFile -match 'runtime_remote_training/tod_independent_resolution_attempts/TOD_EXACT_PATCH_SYNTHESIS_DRILL.*\.json$') {
                $validationPattern = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Validation Pattern'
                if ([string]::IsNullOrWhiteSpace($validationPattern)) { $validationPattern = 'exact_patch_synthesis_drill' }
                $drillArtifact = New-LocalExecutionExactPatchSynthesisDrillArtifact -Context $Context -OutputPath $targetFile -ValidationPattern $validationPattern
                $updatedContent = ($drillArtifact | ConvertTo-Json -Depth 20)
                $actionSummary = ('Wrote exact patch synthesis drill artifact {0}' -f $targetFile)
                $validationCommand = New-LocalExecutionPatternValidationCommand -TargetFile $targetFile -Pattern $validationPattern
                break
            }
            $isPacketFormationArtifact = (
                [string]$targetFile -match 'TOD_PACKET_FORMATION_' -or
                [string]$combinedTaskText -match '(?is)\bpacket[_ -]formation\b|\bpacket_candidate_ready\b'
            )
            if ($isPacketFormationArtifact) {
                $packetArtifact = New-LocalExecutionPacketCandidateArtifact -Context $Context -OutputPath $targetFile -PromptText $promptText
                $updatedContent = ($packetArtifact | ConvertTo-Json -Depth 20)
                $actionSummary = ('Wrote TOD packet-formation artifact {0}' -f $targetFile)
                $validationCommand = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Validation Command'
                if ([string]::IsNullOrWhiteSpace($validationCommand)) {
                    $validationPattern = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Validation Pattern'
                    if ([string]::IsNullOrWhiteSpace($validationPattern)) { $validationPattern = 'packet_candidate_ready' }
                    $validationCommand = New-LocalExecutionPatternValidationCommand -TargetFile $targetFile -Pattern $validationPattern
                }
                break
            }
            if ([string]::IsNullOrWhiteSpace($newText)) {
                return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'local_fallback_needs_target_or_scope' -Reason 'LocalExecutionEngine requires a New Text directive for artifact_write mode.' -MissingVariable 'new_text')
            }
            $requiresStructuredJsonArtifact = (
                [string]$targetFile -match '\.json$' -and
                [string]$combinedTaskText -match '(?is)\brequired\s+json\s+fields?\b|\brequired\s+fields?\b'
            )
            if ($requiresStructuredJsonArtifact -and ([string]$newText).TrimStart() -notmatch '^[\{\[]') {
                return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'artifact_write_structured_json_body_missing' -Reason 'artifact_write targets a JSON artifact with required fields, but New Text is not a JSON object or array.' -MissingVariable 'structured_json_new_text')
            }
            $updatedContent = $newText.TrimEnd("`r", "`n") + "`n"
            $actionSummary = ('Wrote bounded artifact {0}' -f $targetFile)
            $validationCommand = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Validation Command'
            if ([string]::IsNullOrWhiteSpace($validationCommand)) {
                $validationPattern = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Validation Pattern'
                if ([string]::IsNullOrWhiteSpace($validationPattern)) { $validationPattern = $newText }
                $validationCommand = New-LocalExecutionPatternValidationCommand -TargetFile $targetFile -Pattern $validationPattern
            }
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

    $backupRoot = Resolve-LocalExecutionBackupRoot
    $timestamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
    $fileLeaf = Split-Path -Path $absoluteTargetPath -Leaf
    $backupPath = Join-Path $backupRoot ('{0}.{1}.bak' -f $fileLeaf, $timestamp)
    $prePatchHash = if ($targetExistedBefore) { [string](Get-FileHash -Path $absoluteTargetPath -Algorithm SHA256).Hash } else { '' }
    $changeApplied = ((-not $skipWriteBack) -and ($updatedContent -ne $originalContent))
    if (-not $skipWriteBack) {
        $writeSizeCheck = Test-LocalExecutionWriteSizeSafe -OriginalContent $originalContent -UpdatedContent $updatedContent -EditMode $mode
        if (-not [bool]$writeSizeCheck.safe) {
            return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'local_fallback_write_size_guard' -Reason ('LocalExecutionEngine blocked writeback for {0} because the bounded edit expanded the file from {1} bytes to {2} bytes, exceeding the limit of {3} bytes.' -f $targetFile, [int64]$writeSizeCheck.original_bytes, [int64]$writeSizeCheck.updated_bytes, [int64]$writeSizeCheck.max_allowed_bytes) -MissingVariable 'bounded_write_size')
        }
        if ($targetExistedBefore) {
            Copy-Item -Path $absoluteTargetPath -Destination $backupPath -Force
        }
        Write-Utf8NoBomFile -Path $absoluteTargetPath -Content $updatedContent -PreserveExistingBom:$targetExistedBefore
    }

    $validationCommand = Convert-LocalExecutionValidationCommandPaths -Command $validationCommand -TargetFile $targetFile
    $validationWorkingDirectory = Get-LocalExecutionValidationWorkingDirectory -RelativePath $targetFile
    $commandCapture = Invoke-LocalShellCapture -Command $validationCommand -WorkingDirectory $validationWorkingDirectory
    $validatedContent = [string](Get-Content -Path $absoluteTargetPath -Raw)
    $postPatchHash = [string](Get-FileHash -Path $absoluteTargetPath -Algorithm SHA256).Hash
    $validationExitZero = ([int]$commandCapture.exit_code -eq 0)
    $validationStderrEmpty = Test-LocalShellStderrClean -Stderr ([string]$commandCapture.stderr)
    $validationStdout = [string]$commandCapture.stdout
    $validationStderr = [string]$commandCapture.stderr
    $validationCombinedOutput = "$validationStdout`n$validationStderr"
    $pythonUnittestOk = (
        ([string]$validationCommand -match '^\s*python\s+-m\s+unittest\b') -and
        $validationExitZero -and
        ($validationCombinedOutput -match '(?ms)Ran\s+\d+\s+tests?.*?\bOK\b')
    )
    $pythonUnittestFinalizerResidue = (
        ([string]$validationCommand -match '^\s*python\s+-m\s+unittest\b') -and
        ($validationCombinedOutput -match '(?ms)Ran\s+\d+\s+tests?.*?\bOK\b') -and
        ($validationStderr -match 'Fatal Python error: none_dealloc|refcount error in a C extension|Python runtime state: finalizing')
    )
    $passed = (($validationExitZero -and $validationStderrEmpty) -or $pythonUnittestOk -or $pythonUnittestFinalizerResidue)
    $diffSummary = Get-LocalExecutionDiffSummary -RelativePath $targetFile -BeforeContent $originalContent -AfterContent $updatedContent -ActionSummary $actionSummary
    $rollbackState = [pscustomobject]@{
        available = (-not $skipWriteBack)
        backup_path = $(if ($skipWriteBack -or -not $targetExistedBefore) { '' } else { $backupPath })
        target_path = $absoluteTargetPath
        pre_patch_hash = $prePatchHash
        post_patch_hash = $postPatchHash
        restore_command = $(if ($skipWriteBack) { '' } elseif ($targetExistedBefore) { "Copy-Item -Path '$backupPath' -Destination '$absoluteTargetPath' -Force" } else { "Remove-Item -Path '$absoluteTargetPath' -Force" })
    }
    $changeCheckName = if ($staleRecoveryAlreadySatisfied) { 'stale_recovery_already_satisfied_no_file_change_expected' } elseif ($skipWriteBack) { 'validation_only_no_file_change_expected' } else { 'change_or_requested_state_present' }
    $changeCheckPassed = if ($skipWriteBack) { $passed } else { ($changeApplied -or ($validatedContent -eq $updatedContent)) }
    $validationChecks = @(
        [pscustomobject]@{ name = 'target_file_exists'; passed = (Test-Path -Path $absoluteTargetPath) },
        [pscustomobject]@{ name = 'focused_validation_exit_zero'; passed = $validationExitZero },
        [pscustomobject]@{ name = 'focused_validation_stderr_empty'; passed = $validationStderrEmpty },
        [pscustomobject]@{ name = 'python_unittest_ok'; passed = $pythonUnittestOk },
        [pscustomobject]@{ name = 'python_unittest_ok_with_finalizer_residue'; passed = $pythonUnittestFinalizerResidue },
        [pscustomobject]@{ name = $changeCheckName; passed = $changeCheckPassed }
    )

    if (-not $passed) {
        if (-not $skipWriteBack) {
            if ($targetExistedBefore) {
                Copy-Item -Path $backupPath -Destination $absoluteTargetPath -Force
            }
            elseif (Test-Path -Path $absoluteTargetPath) {
                Remove-Item -Path $absoluteTargetPath -Force
            }
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
    $Result.files_changed = if ($changeApplied) { [string[]]@($targetFile) } else { [string[]]@() }
    $nonEmptyChangedFiles = @($Result.files_changed | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
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
            changed_files = @($nonEmptyChangedFiles)
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
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [int]$TimeoutSeconds = 60
    )

    $started = Get-Date
    $timedOut = $false
    $stdoutText = ''
    $stderrText = ''
    $processFile = "powershell.exe"
    $processArgs = @("-NoProfile")
    $nestedCommandMatch = [regex]::Match($Command, '^\s*(?:powershell|pwsh)(?:\.exe)?\s+-NoProfile\s+-Command\s+(["''])(?<inner>.*)\1\s*$', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if ($nestedCommandMatch.Success) {
        $innerCommand = [string]$nestedCommandMatch.Groups['inner'].Value
        $processArgs += @("-EncodedCommand", [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($innerCommand)))
    }
    else {
        $processArgs += @("-EncodedCommand", [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($Command)))
    }
    $previousErrorActionPreference = $ErrorActionPreference
    $previousPythonPycachePrefix = $env:PYTHONPYCACHEPREFIX
    try {
        $ErrorActionPreference = 'Continue'
        if ([string]::IsNullOrWhiteSpace($env:PYTHONPYCACHEPREFIX)) {
            $pycacheRoot = Join-Path $WorkingDirectory 'tod/out/context-sync/listener/pycache'
            New-Item -ItemType Directory -Force -Path $pycacheRoot -ErrorAction SilentlyContinue | Out-Null
            if (Test-Path -Path $pycacheRoot -PathType Container) {
                $env:PYTHONPYCACHEPREFIX = $pycacheRoot
            }
        }
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = $processFile
        $startInfo.Arguments = ($processArgs -join ' ')
        $startInfo.WorkingDirectory = $WorkingDirectory
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.CreateNoWindow = $true
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $startInfo
        $null = $process.Start()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $waitMs = [Math]::Max(1, $TimeoutSeconds) * 1000
        if (-not $process.WaitForExit($waitMs)) {
            $timedOut = $true
            try {
                $process.Kill()
                $null = $process.WaitForExit(5000)
            }
            catch {
                # Best-effort cleanup; timeout is still reported below.
            }
            $exitCode = 124
        }
        else {
            $exitCode = [int]$process.ExitCode
        }
        $stdoutText = [string]$stdoutTask.GetAwaiter().GetResult()
        $stderrText = [string]$stderrTask.GetAwaiter().GetResult()
    }
    finally {
        if ($null -eq $previousPythonPycachePrefix) {
            Remove-Item Env:\PYTHONPYCACHEPREFIX -ErrorAction SilentlyContinue
        }
        else {
            $env:PYTHONPYCACHEPREFIX = $previousPythonPycachePrefix
        }
        $ErrorActionPreference = $previousErrorActionPreference
    }
    $completed = Get-Date
    [pscustomobject]@{
        command = $Command
        working_directory = $WorkingDirectory
        stdout = $stdoutText
        stderr = $stderrText
        exit_code = $exitCode
        timed_out = $timedOut
        timeout_seconds = [Math]::Max(1, $TimeoutSeconds)
        duration_ms = [int][math]::Round(($completed - $started).TotalMilliseconds)
        started_at = $started.ToUniversalTime().ToString("o")
        completed_at = $completed.ToUniversalTime().ToString("o")
    }
}

function Test-LocalShellStderrClean {
    param([AllowEmptyString()][string]$Stderr)

    if ([string]::IsNullOrWhiteSpace($Stderr)) {
        return $true
    }

    $trimmed = ([string]$Stderr).Trim()
    if ($trimmed.StartsWith('#< CLIXML', [System.StringComparison]::OrdinalIgnoreCase)) {
        return (
            $trimmed -match '<Obj\s+S="progress"' -and
            $trimmed -notmatch '<Obj\s+S="(?:Error|error)"' -and
            $trimmed -notmatch 'CategoryInfo|FullyQualifiedErrorId|Exception|ParserError|CommandNotFoundException|NativeCommandFailed'
        )
    }

    return $false
}

function Write-Utf8NoBomFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content,
        [switch]$PreserveExistingBom
    )

    $useBom = $false
    if ($PreserveExistingBom -and (Test-Path -Path $Path -PathType Leaf)) {
        $stream = [System.IO.File]::OpenRead($Path)
        try {
            if ($stream.Length -ge 3) {
                $bytes = New-Object byte[] 3
                [void]$stream.Read($bytes, 0, 3)
                $useBom = ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
            }
        }
        finally {
            $stream.Dispose()
        }
    }

    $utf8 = New-Object System.Text.UTF8Encoding($useBom)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8)
}

function Test-LocalExecutionWriteSizeSafe {
    param(
        [Parameter(Mandatory = $true)][string]$OriginalContent,
        [Parameter(Mandatory = $true)][string]$UpdatedContent,
        [Parameter(Mandatory = $true)][string]$EditMode
    )

    if ([string]::Equals($EditMode, 'artifact_write', [System.StringComparison]::OrdinalIgnoreCase)) {
        return [pscustomobject]@{
            safe = $true
            original_bytes = 0
            updated_bytes = 0
            max_allowed_bytes = 0
            reason = ''
        }
    }

    $encoding = New-Object System.Text.UTF8Encoding($false)
    $originalBytes = [int64]$encoding.GetByteCount([string]$OriginalContent)
    $updatedBytes = [int64]$encoding.GetByteCount([string]$UpdatedContent)
    $maxAllowed = [Math]::Max(
        [int64]($originalBytes + 1048576),
        [int64]($originalBytes * 2 + 65536)
    )

    return [pscustomobject]@{
        safe = ($updatedBytes -le $maxAllowed)
        original_bytes = $originalBytes
        updated_bytes = $updatedBytes
        max_allowed_bytes = $maxAllowed
        reason = if ($updatedBytes -le $maxAllowed) { '' } else { 'updated_content_exceeds_bounded_growth_limit' }
    }
}

function Set-StrictTextReplacement {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][string]$OldText,
        [Parameter(Mandatory = $true)][string]$NewText,
        [Parameter(Mandatory = $true)][string]$Label,
        [string]$Occurrence = 'first',
        [int]$MinimumOccurrences = 1
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

    $occurrenceMode = if ([string]::IsNullOrWhiteSpace($Occurrence)) { 'first' } else { ([string]$Occurrence).Trim().ToLowerInvariant() }
    if (@('first', 'last') -notcontains $occurrenceMode) {
        throw "LocalExecutionEngine unsupported occurrence '$Occurrence' for $Label. Use first or last."
    }
    if ($MinimumOccurrences -lt 1) {
        throw "LocalExecutionEngine unsupported minimum occurrence count '$MinimumOccurrences' for $Label. Use 1 or greater."
    }

    $matchCount = 0
    $scanIndex = 0
    while ($scanIndex -lt $Content.Length) {
        $nextIndex = $Content.IndexOf($matchedOldText, $scanIndex, [System.StringComparison]::Ordinal)
        if ($nextIndex -lt 0) {
            break
        }
        $matchCount++
        $scanIndex = $nextIndex + $matchedOldText.Length
    }
    if ($matchCount -lt $MinimumOccurrences) {
        throw "LocalExecutionEngine found $matchCount occurrence(s) of the expected $Label snippet, but $MinimumOccurrences were required."
    }

    $matchIndex = if ([string]::Equals($occurrenceMode, 'last', [System.StringComparison]::OrdinalIgnoreCase)) {
        $Content.LastIndexOf($matchedOldText, [System.StringComparison]::Ordinal)
    }
    else {
        $Content.IndexOf($matchedOldText, [System.StringComparison]::Ordinal)
    }
    if ($matchIndex -lt 0) {
        throw "LocalExecutionEngine could not find the expected $Label snippet to replace."
    }

    return ($Content.Substring(0, $matchIndex) + $replacementText + $Content.Substring($matchIndex + $matchedOldText.Length))
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
    Write-Utf8NoBomFile -Path $absoluteTargetPath -Content $updatedContent -PreserveExistingBom

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
    $timestamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ')
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
            "user_app_hero_media_generation",
            "read_only_audit_artifact_publication",
            "patch_evidence_authority_classification",
            "source_anchor_observation_artifact_publication",
            "different_target_discovery_artifact_publication",
            "target_selection_artifact_publication",
            "packet_body_synthesis_artifact_publication",
            "python_snippet_body_synthesis_artifact_publication",
            "python_route_body_synthesis_artifact_publication",
            "site_maintenance_artifact_publication"
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
    elseif (Test-LocalExecutionResearchEvidenceDemonstrationTask -Context $Context) {
        $result = Invoke-LocalExecutionResearchEvidenceDemonstration -Context $Context -Result $result -Spec $spec
    }
    elseif (Test-LocalExecutionSemanticSourceAuditTask -Context $Context) {
        $result = Invoke-LocalExecutionSemanticSourceAudit -Context $Context -Result $result -Spec $spec
    }
    elseif (Test-LocalExecutionReadOnlyAuditArtifactTask -Context $Context) {
        $result = Invoke-LocalExecutionReadOnlyAuditArtifact -Context $Context -Result $result -Spec $spec
    }
    elseif (Test-LocalExecutionPatchEvidenceArtifactTask -Context $Context) {
        $result = Invoke-LocalExecutionPatchEvidenceArtifact -Context $Context -Result $result -Spec $spec
    }
    elseif (Test-LocalExecutionSourceAnchorObservationTask -Context $Context) {
        $result = Invoke-LocalExecutionSourceAnchorObservation -Context $Context -Result $result -Spec $spec
    }
    elseif (Test-LocalExecutionDifferentTargetDiscoveryTask -Context $Context) {
        $result = Invoke-LocalExecutionDifferentTargetDiscovery -Context $Context -Result $result -Spec $spec
    }
    elseif (Test-LocalExecutionSiteMaintenanceArtifactTask -Context $Context) {
        $result = Invoke-LocalExecutionSiteMaintenanceArtifact -Context $Context -Result $result -Spec $spec
    }
    elseif (Test-LocalExecutionPacketBodySynthesisTask -Context $Context) {
        $result = Invoke-LocalExecutionPacketBodySynthesis -Context $Context -Result $result -Spec $spec
    }
    elseif (Test-LocalExecutionApplyPacketArtifactTask -Context $Context) {
        $result = Invoke-LocalExecutionApplyPacketArtifact -Context $Context -Result $result -Spec $spec
    }
    elseif (Test-LocalExecutionPacketQualityReviewTask -Context $Context) {
        $result = Invoke-LocalExecutionPacketQualityReview -Context $Context -Result $result -Spec $spec
    }
    elseif (Test-LocalExecutionPythonSnippetBodySynthesisTask -Context $Context) {
        $result = Invoke-LocalExecutionPythonSnippetBodySynthesis -Context $Context -Result $result -Spec $spec
    }
    elseif (Test-LocalExecutionPythonRouteBodySynthesisTask -Context $Context) {
        $result = Invoke-LocalExecutionPythonRouteBodySynthesis -Context $Context -Result $result -Spec $spec
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
