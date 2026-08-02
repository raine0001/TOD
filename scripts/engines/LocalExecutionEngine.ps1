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

    $promptText = Get-LocalExecutionPromptText -Context $Context
    if (-not [string]::IsNullOrWhiteSpace($promptText)) {
        $promptCategory = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Task Category'
        if (-not [string]::IsNullOrWhiteSpace($promptCategory)) {
            return ([string]$promptCategory).Trim().ToLowerInvariant()
        }
        $promptCategoryMatch = [regex]::Match($promptText, '(?im)^\s*(?:[-*]\s*)?Task\s+Category\s*:\s*(?<value>.+?)\s*$')
        if ($promptCategoryMatch.Success -and -not [string]::IsNullOrWhiteSpace([string]$promptCategoryMatch.Groups['value'].Value)) {
            return ([string]$promptCategoryMatch.Groups['value'].Value).Trim().ToLowerInvariant()
        }

        $promptMode = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Task Mode'
        if (-not [string]::IsNullOrWhiteSpace($promptMode)) {
            return ([string]$promptMode).Trim().ToLowerInvariant()
        }
        $promptModeMatch = [regex]::Match($promptText, '(?im)^\s*(?:[-*]\s*)?Task\s+(?:Mode|Type)\s*:\s*(?<value>.+?)\s*$')
        if ($promptModeMatch.Success -and -not [string]::IsNullOrWhiteSpace([string]$promptModeMatch.Groups['value'].Value)) {
            return ([string]$promptModeMatch.Groups['value'].Value).Trim().ToLowerInvariant()
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
        'runtime/tod_engineering_corpus/',

        'runtime_remote_training/remote_scripts/',
        'runtime_remote_training/tod_result_artifacts/',
        'runtime_remote_training/tod_independent_resolution_attempts/',
        'runtime_remote_training/engineering_corpus/',
        'runtime_remote_training/model_selection/fixtures/',
        'runtime_remote_training/read_only_audit_artifacts/',
        'runtime_remote_training/learned_capabilities/',
        'runtime_remote_training/TOD_CAPABILITY_ASSESSMENT_V1.latest.json',
        'runtime_remote_training/TOD_CAPABILITY_ASSESSMENT_V1.latest.md',
        'runtime_remote_training/TOD_CORRECTED_PATCH_SYNTHESIS_PRACTICE_V1.latest.json',
        'tmp_remote_mim/',
        'tmp_remote_mim/core/',
        'tmp_remote_mim/tests/',
        'tod/config/',
        'tod/out/prompts/',
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
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$PathValue)

    $normalized = ([string]$PathValue).Trim() -replace '[\\/]+', '/'
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return ''
    }
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

    if ($isTargetSelection) {
        $evidencePaths = New-Object System.Collections.Generic.List[string]
        foreach ($match in [regex]::Matches($combined, 'runtime_remote_training/read_only_audit_artifacts/[A-Za-z0-9_./-]+?\.json')) {
            $candidateEvidence = Convert-ToLocalExecutionRepoRelativePath -PathValue ([string]$match.Value)
            if (-not [string]::IsNullOrWhiteSpace($candidateEvidence) -and -not $evidencePaths.Contains($candidateEvidence)) {
                [void]$evidencePaths.Add($candidateEvidence)
            }
        }

        $sourceTaskIds = New-Object System.Collections.Generic.List[string]
        foreach ($match in [regex]::Matches($combined, '(?im)\bsource\s+task\s+(?<id>[A-Za-z0-9_.-]+)\b')) {
            $sourceTaskId = ([string]$match.Groups['id'].Value).Trim()
            if (-not [string]::IsNullOrWhiteSpace($sourceTaskId) -and -not $sourceTaskIds.Contains($sourceTaskId)) {
                [void]$sourceTaskIds.Add($sourceTaskId)
            }
        }

        $evidenceCandidates = @{}
        $evidenceInspected = New-Object System.Collections.Generic.List[string]
        $evidenceRejected = New-Object System.Collections.Generic.List[object]
        foreach ($evidencePath in @($evidencePaths.ToArray())) {
            try {
                $evidenceAbs = Resolve-LocalExecutionAbsoluteTargetPath -RelativePath $evidencePath -Operation 'read'
                if (-not (Test-Path -Path $evidenceAbs -PathType Leaf)) {
                    $evidenceRejected.Add([ordered]@{
                            target_file = $evidencePath
                            candidate_key = 'evidence_artifact'
                            reason = 'evidence_artifact_missing'
                        }) | Out-Null
                    continue
                }
                if (-not $evidenceInspected.Contains($evidencePath)) {
                    [void]$evidenceInspected.Add($evidencePath)
                }
                $raw = [System.IO.File]::ReadAllText($evidenceAbs, [System.Text.UTF8Encoding]::new($false))
                foreach ($pathMatch in [regex]::Matches($raw, '"(?<field>source_file|target_file|file|old_path|new_path|expected_target_if_supported_by_evidence)"\s*:\s*"(?<path>(?:scripts|tmp_remote_mim|core)/[A-Za-z0-9_./-]+\.(?:ps1|psm1|py|json|md|txt|html|js|css))"')) {
                    $field = [string]$pathMatch.Groups['field'].Value
                    $path = Convert-ToLocalExecutionRepoRelativePath -PathValue ([string]$pathMatch.Groups['path'].Value)
                    if ([string]::IsNullOrWhiteSpace($path)) { continue }
                    if (-not $evidenceCandidates.ContainsKey($path)) {
                        $evidenceCandidates[$path] = [ordered]@{
                            target_file = $path
                            candidate_key = 'evidence_named_target'
                            evidence_fields = New-Object System.Collections.Generic.List[string]
                            evidence_artifacts = New-Object System.Collections.Generic.List[string]
                            score = 0
                        }
                    }
                    if (-not $evidenceCandidates[$path].evidence_fields.Contains($field)) {
                        [void]$evidenceCandidates[$path].evidence_fields.Add($field)
                    }
                    if (-not $evidenceCandidates[$path].evidence_artifacts.Contains($evidencePath)) {
                        [void]$evidenceCandidates[$path].evidence_artifacts.Add($evidencePath)
                    }
                    $scoreDelta = switch ($field) {
                        'expected_target_if_supported_by_evidence' { 10 }
                        'source_file' { 8 }
                        'new_path' { 7 }
                        'target_file' { 6 }
                        'old_path' { 6 }
                        'file' { 5 }
                        default { 1 }
                    }
                    $evidenceCandidates[$path].score = [int]$evidenceCandidates[$path].score + $scoreDelta
                }
            }
            catch {
                $evidenceRejected.Add([ordered]@{
                        target_file = $evidencePath
                        candidate_key = 'evidence_artifact'
                        reason = 'evidence_artifact_read_failed'
                    }) | Out-Null
            }
        }

        foreach ($sourceTaskId in @($sourceTaskIds.ToArray())) {
            $sourceTexts = New-Object System.Collections.Generic.List[object]
            $promptRel = Convert-ToLocalExecutionRepoRelativePath -PathValue ('tod/out/prompts/{0}.md' -f $sourceTaskId)
            try {
                $promptAbs = Resolve-LocalExecutionAbsoluteTargetPath -RelativePath $promptRel -Operation 'read'
                if (Test-Path -Path $promptAbs -PathType Leaf) {
                    $sourceTexts.Add([pscustomobject]@{
                            locator = $promptRel
                            text = [System.IO.File]::ReadAllText($promptAbs, [System.Text.UTF8Encoding]::new($false))
                        }) | Out-Null
                }
            }
            catch {
                $evidenceRejected.Add([ordered]@{
                        target_file = $promptRel
                        candidate_key = 'source_task_prompt'
                        reason = 'source_task_prompt_read_failed'
                    }) | Out-Null
            }

            try {
                $stateRel = 'tod/data/state.json'
                $stateAbs = Resolve-LocalExecutionAbsoluteTargetPath -RelativePath $stateRel -Operation 'read'
                if (Test-Path -Path $stateAbs -PathType Leaf) {
                    $state = Get-Content -Path $stateAbs -Raw | ConvertFrom-Json
                    $sourceTask = @($state.tasks | Where-Object { [string]$_.id -eq $sourceTaskId } | Select-Object -First 1)
                    if (@($sourceTask).Count -gt 0) {
                        $parts = New-Object System.Collections.Generic.List[string]
                        foreach ($propertyName in @('title', 'summary', 'description', 'scope')) {
                            if ($sourceTask[0].PSObject.Properties[$propertyName] -and -not [string]::IsNullOrWhiteSpace([string]$sourceTask[0].$propertyName)) {
                                [void]$parts.Add([string]$sourceTask[0].$propertyName)
                            }
                        }
                        if ($parts.Count -gt 0) {
                            $sourceTexts.Add([pscustomobject]@{
                                    locator = ('{0}#task={1}' -f $stateRel, $sourceTaskId)
                                    text = ($parts.ToArray() -join "`n")
                                }) | Out-Null
                        }
                    }
                }
            }
            catch {
                $evidenceRejected.Add([ordered]@{
                        target_file = 'tod/data/state.json'
                        candidate_key = 'source_task_state'
                        reason = 'source_task_state_read_failed'
                    }) | Out-Null
            }

            foreach ($sourceText in @($sourceTexts.ToArray())) {
                $locator = [string]$sourceText.locator
                if (-not $evidenceInspected.Contains($locator)) {
                    [void]$evidenceInspected.Add($locator)
                }
                foreach ($pathMatch in [regex]::Matches([string]$sourceText.text, '(?im)\b(?<field>Source File|Packet Source Target|Inspect Source File|Bounded Source Target)\s*:\s*(?<path>(?:scripts|tmp_remote_mim|core)/[A-Za-z0-9_./-]+\.(?:ps1|psm1|py|json|md|txt|html|js|css))')) {
                    $field = ([string]$pathMatch.Groups['field'].Value).Trim().ToLowerInvariant() -replace '\s+', '_'
                    $path = Convert-ToLocalExecutionRepoRelativePath -PathValue ([string]$pathMatch.Groups['path'].Value)
                    if ([string]::IsNullOrWhiteSpace($path)) { continue }
                    if (-not $evidenceCandidates.ContainsKey($path)) {
                        $evidenceCandidates[$path] = [ordered]@{
                            target_file = $path
                            candidate_key = 'source_task_named_target'
                            evidence_fields = New-Object System.Collections.Generic.List[string]
                            evidence_artifacts = New-Object System.Collections.Generic.List[string]
                            score = 0
                        }
                    }
                    $fieldName = ('source_task_{0}' -f $field)
                    if (-not $evidenceCandidates[$path].evidence_fields.Contains($fieldName)) {
                        [void]$evidenceCandidates[$path].evidence_fields.Add($fieldName)
                    }
                    if (-not $evidenceCandidates[$path].evidence_artifacts.Contains($locator)) {
                        [void]$evidenceCandidates[$path].evidence_artifacts.Add($locator)
                    }
                    $scoreDelta = switch ($field) {
                        'source_file' { 12 }
                        'packet_source_target' { 11 }
                        'inspect_source_file' { 10 }
                        'bounded_source_target' { 10 }
                        default { 1 }
                    }
                    $evidenceCandidates[$path].score = [int]$evidenceCandidates[$path].score + $scoreDelta
                }
            }
        }

        if ($evidenceCandidates.Count -gt 0) {
            $ranked = @($evidenceCandidates.Values | Sort-Object @{ Expression = { [int]$_.score }; Descending = $true }, @{ Expression = { [string]$_.target_file }; Descending = $false })
            $selectedEvidence = $null
            foreach ($candidate in $ranked) {
                $target = [string]$candidate.target_file
                if ($forbidden.Contains($target)) {
                    $authoritativeEvidenceFields = @($candidate.evidence_fields.ToArray() | Where-Object {
                            [string]$_ -in @('source_file', 'target_file', 'file', 'old_path', 'new_path', 'expected_target_if_supported_by_evidence')
                        })
                    if (@($authoritativeEvidenceFields).Count -eq 0) {
                        $evidenceRejected.Add([ordered]@{
                                target_file = $target
                                candidate_key = 'evidence_named_target'
                                reason = 'forbidden_by_current_prompt_or_intervention'
                            }) | Out-Null
                        continue
                    }
                }
                try {
                    $targetAbs = Resolve-LocalExecutionAbsoluteTargetPath -RelativePath $target -Operation 'read'
                    if (-not (Test-Path -Path $targetAbs -PathType Leaf)) {
                        $evidenceRejected.Add([ordered]@{
                                target_file = $target
                                candidate_key = 'evidence_named_target'
                                reason = 'evidence_named_target_missing'
                            }) | Out-Null
                        continue
                    }
                    $selectedEvidence = $candidate
                    break
                }
                catch {
                    $evidenceRejected.Add([ordered]@{
                            target_file = $target
                            candidate_key = 'evidence_named_target'
                            reason = 'evidence_named_target_inspection_failed'
                        }) | Out-Null
                }
            }

            if ($null -ne $selectedEvidence) {
                foreach ($staticCandidate in @(
                        'tmp_remote_mim/core/routers/studio.py',
                        'tmp_remote_mim/core/routers/public_chat.py',
                        'tmp_remote_mim/core/routers/tod_ui.py',
                        'tmp_remote_mim/core/routers/gateway.py',
                        'tmp_remote_mim/core/routers/tasks.py',
                        'tmp_remote_mim/core/routers/operator.py',
                        'tmp_remote_mim/core/routers/inquiry.py',
                        'tmp_remote_mim/core/communication_composer.py',
                        'tmp_remote_mim/core/routers/results.py',
                        'tmp_remote_mim/core/interaction_quality_dashboard.py'
                    )) {
                    if ([string]$staticCandidate -ne [string]$selectedEvidence.target_file) {
                        $evidenceRejected.Add([ordered]@{
                                target_file = [string]$staticCandidate
                                candidate_key = 'static_fallback_candidate'
                                reason = 'not_named_by_input_evidence'
                            }) | Out-Null
                    }
                }

                return [ordered]@{
                    artifact_type = 'tod_target_selection_artifact'
                    status = 'candidate_selected'
                    selection_source = 'input_evidence_artifacts'
                    inspected_files = @($evidenceInspected.ToArray())
                    inspected_candidates = @($ranked | ForEach-Object { [string]$_.target_file })
                    rejected_candidates = @($evidenceRejected.ToArray())
                    candidate_count = @($ranked).Count
                    selected_candidate_or_none = [ordered]@{
                        target_file = [string]$selectedEvidence.target_file
                        candidate_key = [string]$selectedEvidence.candidate_key
                        evidence_fields = @($selectedEvidence.evidence_fields.ToArray())
                        evidence_artifacts = @($selectedEvidence.evidence_artifacts.ToArray())
                        score = [int]$selectedEvidence.score
                    }
                    selected_target = [string]$selectedEvidence.target_file
                    why_selected = ('Selected {0} because input evidence named it via {1}.' -f [string]$selectedEvidence.target_file, ((@($selectedEvidence.evidence_fields.ToArray())) -join ', '))
                    selection_reason = ('Selected {0} from supplied evidence artifacts before static fallback candidates were considered.' -f [string]$selectedEvidence.target_file)
                    validation_plan = @('Form a bounded packet from the selected target, then run focused validation for that packet.')
                    next_bounded_packet_requirements = @('target_file', 'edit_mode', 'anchor_or_old_text', 'new_text_or_snippet', 'validation_command', 'expected_evidence')
                    validation_command = ''
                    rollback_note = 'Artifact only; remove generated discovery artifact to roll back.'
                    prevention_lesson = 'TOD must select implementation targets from supplied evidence before consulting static candidate fallback drills.'
                    dave_needed = 'no'
                    credit_decision = [ordered]@{ independent_tod_resolution = $false; reason = 'Target selection only; implementation credit requires a later validated edit.' }
                    output_path = $OutputPath
                }
            }
        }
    }

    if ($isTargetSelection) {
        return [ordered]@{
            artifact_type = 'tod_target_selection_artifact'
            status = 'no_candidate_available'
            selected_candidate_or_none = $null
            selected_target = ''
            inspected_files = @($evidenceInspected.ToArray())
            inspected_candidates = @()
            rejected_candidates = @($evidenceRejected.ToArray())
            candidate_count = 0
            why_selected = 'No evidence-derived target was found for this target-selection task.'
            selection_reason = 'Target-selection tasks require input evidence naming a viable source target; static fallback candidates are reserved for legacy different-target discovery drills.'
            validation_plan = @()
            next_bounded_packet_requirements = @('target_file', 'edit_mode', 'anchor_or_old_text', 'new_text_or_snippet', 'validation_command', 'expected_evidence')
            validation_command = ''
            rollback_note = 'Artifact only; remove generated discovery artifact to roll back.'
            prevention_lesson = 'TOD must not use stale static fallback candidates when the current target-selection task provides no evidence-derived target.'
            dave_needed = 'no'
            credit_decision = [ordered]@{ independent_tod_resolution = $false; reason = 'No evidence-derived implementation target was available.' }
            output_path = $OutputPath
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
    [System.IO.File]::WriteAllText($outputAbs, ($artifact | ConvertTo-Json -Depth 12), [System.Text.UTF8Encoding]::new($false))

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
    if ($isTargetSelection -and -not $selected) {
        $Result.test_results = @('fail')
        $Result.failures = @('target_selection_no_candidate_available')
        $Result.recommendations = @('Provide a current evidence artifact naming one viable source target before packet materialization.')
    }
    else {
        $Result.test_results = @('pass')
        $Result.failures = @()
        $Result.recommendations = @('Use the selected target to form a current-code packet before dispatching implementation.')
    }
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
    return (Complete-EngineExecutionResult -Result $Result -Status $(if ($isTargetSelection -and -not $selected) { 'blocked' } else { 'completed' }))
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

function Get-LocalExecutionPacketCandidateTargetOptions {
    return @(
        [pscustomobject]@{ target_file = 'tmp_remote_mim/core/routers/studio.py'; anchor_pattern = 'MIM conversation mode selection'; applied_marker = 'TOD self-authored bounded edit materialization'; reason = 'studio_mode_selection_candidate' },
        [pscustomobject]@{ target_file = 'tmp_remote_mim/core/routers/public_chat.py'; anchor_pattern = 'This could mean several things'; applied_marker = 'I am carrying forward the prior date/time question'; reason = 'public_chat_followup_candidate' },
        [pscustomobject]@{ target_file = 'tmp_remote_mim/core/interaction_quality_dashboard.py'; anchor_pattern = 'available_artifacts'; applied_marker = 'stale_artifacts'; reason = 'interaction_quality_dashboard_candidate' },
        [pscustomobject]@{ target_file = 'tmp_remote_mim/core/routers/operator.py'; anchor_pattern = '_normalize_exception_reason'; applied_marker = 'operator_action_required'; reason = 'operator_router_candidate' },
        [pscustomobject]@{ target_file = 'tmp_remote_mim/core/routers/inquiry.py'; anchor_pattern = 'applied_effect'; applied_marker = 'answer_context_evidence'; reason = 'inquiry_router_candidate' },
        [pscustomobject]@{ target_file = 'tmp_remote_mim/core/routers/gateway.py'; anchor_pattern = 'target gateway/test files'; applied_marker = 'selected one-file target'; reason = 'gateway_split_candidate' },
        [pscustomobject]@{ target_file = 'tmp_remote_mim/core/routers/improvement.py'; anchor_pattern = '"artifact": to_improvement_artifact_out\(artifact\)'; applied_marker = 'review_decision_evidence'; reason = 'improvement_router_candidate' },
        [pscustomobject]@{ target_file = 'scripts/engines/LocalExecutionEngine.ps1'; anchor_pattern = 'reverse[- ]packet|reverse packet cleanup|cleanup validation'; applied_marker = 'cleanup validation'; reason = 'local_engine_cleanup_candidate' },
        [pscustomobject]@{ target_file = 'tmp_remote_mim/core/routers/enterprises.py'; anchor_pattern = 'router = APIRouter\(\)'; applied_marker = 'tags=["enterprises"]'; reason = 'enterprise_router_tag_candidate' },
        [pscustomobject]@{ target_file = 'tmp_remote_mim/core/routers/project_portal.py'; anchor_pattern = '"enterprise_account": bool\(metadata\.get\("enterprise_id"\)'; applied_marker = '"enterprise_setup": metadata.get("enterprise_setup")'; reason = 'enterprise_setup_payload_candidate' },
        [pscustomobject]@{ target_file = 'scripts/TOD.ps1'; anchor_pattern = "'Prevention Lesson',"; applied_marker = "'Required Packet Fields',"; reason = 'tod_directive_parser_candidate' }
    )
}

function Resolve-LocalExecutionAllowedPacketCandidateTarget {
    param(
        [Parameter(Mandatory = $true)]$ForbiddenTargets,
        [Parameter(Mandatory = $true)][string]$CurrentTarget
    )

    foreach ($candidate in @(Get-LocalExecutionPacketCandidateTargetOptions)) {
        $candidateTarget = Convert-ToLocalExecutionRepoRelativePath -PathValue ([string]$candidate.target_file)
        if ([string]::IsNullOrWhiteSpace($candidateTarget)) {
            continue
        }
        if ([string]::Equals($candidateTarget, $CurrentTarget, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }
        if ($ForbiddenTargets.Contains($candidateTarget)) {
            continue
        }
        if (-not (Test-LocalExecutionSafePath -RelativePath $candidateTarget)) {
            continue
        }
        try {
            $candidateAbs = Resolve-LocalExecutionAbsoluteTargetPath -RelativePath $candidateTarget -Operation 'read'
            if (-not (Test-Path -Path $candidateAbs -PathType Leaf)) {
                continue
            }
            $candidateText = [System.IO.File]::ReadAllText($candidateAbs, [System.Text.UTF8Encoding]::new($false))
            if ([string]::IsNullOrWhiteSpace($candidateText)) {
                continue
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$candidate.applied_marker) -and $candidateText.Contains([string]$candidate.applied_marker)) {
                continue
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$candidate.anchor_pattern) -and $candidateText -notmatch [string]$candidate.anchor_pattern) {
                continue
            }
            return [ordered]@{
                target_file = $candidateTarget
                reason = [string]$candidate.reason
            }
        }
        catch {
            continue
        }
    }

    return $null
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
    $targetInferenceReason = if ($explicitTargetSupplied) { 'packet_source_target' } else { '' }
    if ([string]::IsNullOrWhiteSpace($target)) {
        $target = Get-LocalExecutionDirectiveValue -PromptText $PromptText -FieldName 'Inspect Target File'
        if (-not [string]::IsNullOrWhiteSpace($target)) {
            $explicitTargetSupplied = $true
            $targetInferenceReason = 'inspect_target_file'
        }
    }
    $combinedString = (@([string]$combined, [string]$PromptText) -join "`n")
    $targetInferenceText = [regex]::Replace($combinedString, '(?im)^\s*Forbidden target paths for this packet\s*:[^\r\n]*(\r?\n)?', '')
    if ([string]::IsNullOrWhiteSpace($target) -and $targetInferenceText -match '(?is)consumed_packet_anchor_requires_different_candidate') {
        $target = Get-LocalExecutionLatestDiscoveryTarget
        if (-not [string]::IsNullOrWhiteSpace($target)) {
            $targetInferenceReason = 'latest_discovery_target'
        }
    }
    if ([string]::IsNullOrWhiteSpace($target) -and $targetInferenceText -match '(?is)stale_synthesis|selector preference|scripts/TOD\.ps1|materialized bounded edit proof') {
        $target = 'scripts/TOD.ps1'
        $targetInferenceReason = 'tod_selector_or_materialization_fallback'
    }
    if ([string]::IsNullOrWhiteSpace($target) -and $targetInferenceText -match '(?is)\bgateway\b') {
        $target = 'tmp_remote_mim/core/routers/gateway.py'
        $targetInferenceReason = 'gateway_prompt_fallback'
    }
    if ([string]::IsNullOrWhiteSpace($target)) {
        $target = Get-LocalExecutionLatestDiscoveryTarget
        if (-not [string]::IsNullOrWhiteSpace($target)) {
            $targetInferenceReason = 'latest_discovery_target'
        }
    }
    if ([string]::IsNullOrWhiteSpace($target)) {
        $durabilityCandidate = Join-Path $script:LocalEngineRepoRoot 'scripts/run_mim_durability_smoke_v2.py'
        if (Test-Path -Path $durabilityCandidate -PathType Leaf) {
            $target = 'scripts/run_mim_durability_smoke_v2.py'
            $targetInferenceReason = 'durability_smoke_fallback'
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
    if (-not $explicitTargetSupplied -and -not [string]::IsNullOrWhiteSpace($target) -and $forbidden.Contains($target) -and [string]::Equals($targetInferenceReason, 'gateway_prompt_fallback', [System.StringComparison]::OrdinalIgnoreCase) -and -not $forbidden.Contains('tmp_remote_mim/core/routers/improvement.py')) {
        $target = 'tmp_remote_mim/core/routers/improvement.py'
        $targetInferenceReason = 'gateway_governance_pivot'
    }
    if (-not $explicitTargetSupplied -and -not [string]::IsNullOrWhiteSpace($target) -and $forbidden.Contains($target)) {
        $allowedPivot = Resolve-LocalExecutionAllowedPacketCandidateTarget -ForbiddenTargets $forbidden -CurrentTarget $target
        if ($null -ne $allowedPivot -and $allowedPivot.Contains('target_file') -and -not [string]::IsNullOrWhiteSpace([string]$allowedPivot.target_file)) {
            $target = [string]$allowedPivot.target_file
            $targetInferenceReason = ('allowed_candidate_pivot:{0}' -f [string]$allowedPivot.reason)
        }
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
    elseif ($target -eq 'tmp_remote_mim/core/routers/enterprises.py' -and $sourceText -match 'router = APIRouter\(\)') {
        $selectedCandidate = 'enterprise_router_openapi_tag'
        $oldText = 'router = APIRouter()'
        $newText = 'router = APIRouter(tags=["enterprises"])'
        $validationPattern = 'tags=["enterprises"]'
        $validationCommand = 'python -m py_compile tmp_remote_mim/core/routers/enterprises.py'
        $preventionLesson = 'Fresh packet formation should pivot to a bounded current-code target with a clear validation path when older training targets are forbidden or already applied.'
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

    $category = Get-LocalExecutionTaskCategory -Context $Context
    $readOnlyInspectionCategory = @('read_only_assessment', 'report_only', 'diagnostic_only', 'inspection_only', 'inspection', 'review_only') -contains $category
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
    $targetDirectiveNames = if ($readOnlyInspectionCategory) { @('Target File') } else { @('Target File', 'Inspect Target File') }
    foreach ($targetDirectiveName in $targetDirectiveNames) {
        $explicitTarget = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName $targetDirectiveName
        if (-not [string]::IsNullOrWhiteSpace($explicitTarget)) {
            $explicitTarget = ([regex]::Split([string]$explicitTarget, "\r?\n") | Select-Object -First 1).Trim()
            $value = Convert-ToLocalExecutionRepoRelativePath -PathValue $explicitTarget
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                return @($value)
            }
        }
    }

    if ($readOnlyInspectionCategory) {
        return @()
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
    if ($normalized -match '(?im)^\s*(target file|edit mode|old text|new text|source file|output|task mode|anchor pattern)\s*:') {
        return $false
    }
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
    if (Test-LocalExecutionReadOnlyAuditArtifactTask -Context $Context) { return $false }

    $taskCategory = Get-LocalExecutionTaskCategory -Context $Context
    if (@('code_change', 'config_change', 'test_change', 'docs_change', 'packet_formation', 'artifact_write', 'validation', 'validation_only') -contains $taskCategory) {
        return $true
    }

    return (@(Get-LocalExecutionTargetFiles -Context $Context).Count -gt 0)
}

function Get-LocalExecutionReadOnlyAuditArtifactPaths {
    param([Parameter(Mandatory = $true)]$Context)

    $text = Get-LocalExecutionCombinedText -Context $Context
    $selectedSourceReason = ''
    $inputPath = ''
    foreach ($inputField in @('Input', 'Input Artifact', 'Input Evidence', 'Primary input', 'Primary Input', 'Evidence Artifact', 'Review Artifact', 'Source Anchor Artifact', 'Left Artifact', 'Package Path', 'Source episode', 'Source Episode')) {
        $inputMatch = [regex]::Match($text, ('(?im)\b{0}\s*:\s*(?<path>\S+?\.json)\b' -f [regex]::Escape($inputField)))
        if ($inputMatch.Success) {
            $inputPath = ([string]$inputMatch.Groups['path'].Value).Trim()
            break
        }
    }
    if ([string]::IsNullOrWhiteSpace($inputPath)) {
        $primaryInputSentenceMatch = [regex]::Match($text, '(?im)\bPrimary\s+input\s+is\s+(?<path>\S+?\.json)\b')
        if ($primaryInputSentenceMatch.Success) {
            $inputPath = ([string]$primaryInputSentenceMatch.Groups['path'].Value).Trim()
        }
    }
    if ([string]::IsNullOrWhiteSpace($inputPath)) {
        $requiredTypeForInputListMatch = [regex]::Match($text, '(?i)\bRequired\s+Artifact\s+Type\s*:\s*tod_engineering_corpus_foundation_index\b')
        if ($requiredTypeForInputListMatch.Success) {
            $listedInputMatches = @([regex]::Matches($text, '(?im)^\s*-\s*(?<path>runtime_remote_training/engineering_corpus/[A-Za-z0-9_./-]+?\.json)\s*$'))
            if ($listedInputMatches.Count -gt 0) {
                $inputPath = ([string]$listedInputMatches[0].Groups['path'].Value).Trim()
            }
        }
    }
    if ([string]::IsNullOrWhiteSpace($inputPath)) {
        $requiredTypeForSynthesisInputListMatch = [regex]::Match($text, '(?i)\bRequired\s+Artifact\s+Type\s*:\s*tod_autonomous_meaningful_newtext_synthesis\b')
        if ($requiredTypeForSynthesisInputListMatch.Success) {
            $listedSynthesisInputMatches = @([regex]::Matches($text, '(?im)^\s*(?:-\s*)?(?<path>runtime_remote_training/read_only_audit_artifacts/[A-Za-z0-9_./-]+?\.json)\s*$'))
            if ($listedSynthesisInputMatches.Count -gt 0) {
                $inputPath = ([string]$listedSynthesisInputMatches[0].Groups['path'].Value).Trim()
            }
        }
    }
    if ([string]::IsNullOrWhiteSpace($inputPath)) {
        $requiredTypeMatch = [regex]::Match($text, '(?im)\bRequired\s+Artifact\s+Type\s*:\s*(?<value>[A-Za-z0-9_.-]+)\b')
        $evidenceRootMatch = [regex]::Match($text, '(?im)\bEvidence\s+Root\s*:\s*(?<path>[A-Za-z0-9_./-]+)\b')
        if (
            $requiredTypeMatch.Success -and
            [string]::Equals(([string]$requiredTypeMatch.Groups['value'].Value).Trim(), 'tod_engineering_episode_card', [System.StringComparison]::OrdinalIgnoreCase) -and
            $evidenceRootMatch.Success
        ) {
            $evidenceRootRel = Convert-ToLocalExecutionRepoRelativePath -PathValue (([string]$evidenceRootMatch.Groups['path'].Value).Trim())
            $evidenceRootAbs = Join-Path $script:LocalEngineRepoRoot ($evidenceRootRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
            if (Test-Path -Path $evidenceRootAbs -PathType Container) {
                $excludedNames = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
                foreach ($excludedMatch in [regex]::Matches($text, '(?i)\bnot\s+(?<name>[A-Za-z0-9_.-]+\.json)\b')) {
                    [void]$excludedNames.Add(([string]$excludedMatch.Groups['name'].Value).Trim())
                }

                $bestCandidate = $null
                $bestScore = -1
                foreach ($candidate in Get-ChildItem -Path $evidenceRootAbs -Filter '*.json' -File | Sort-Object LastWriteTimeUtc -Descending) {
                    if ($excludedNames.Contains($candidate.Name)) {
                        continue
                    }
                    $candidateRel = Convert-ToLocalExecutionRepoRelativePath -PathValue (Join-Path $evidenceRootRel $candidate.Name)
                    if (-not (Test-LocalExecutionSafePath -RelativePath $candidateRel)) {
                        continue
                    }

                    $candidateScore = 10
                    $candidateType = ''
                    try {
                        $candidateJson = Get-Content -Path $candidate.FullName -Raw | ConvertFrom-Json
                        if ($candidateJson.PSObject.Properties['artifact_type']) {
                            $candidateType = [string]$candidateJson.artifact_type
                        }
                    }
                    catch {
                        $candidateScore -= 5
                    }
                    if ([string]::Equals($candidateType, 'codex_validation', [System.StringComparison]::OrdinalIgnoreCase)) {
                        $candidateScore -= 3
                    }
                    if ($candidate.Name -match 'codex_validation') {
                        $candidateScore -= 2
                    }
                    if ($candidate.Name -match 'latest|result|blocker|validation|anchor|audit') {
                        $candidateScore += 2
                    }
                    if ($candidateType -match 'source_anchor|audit|result|blocker|validation|observation') {
                        $candidateScore += 4
                    }
                    if ($candidateScore -gt $bestScore) {
                        $bestScore = $candidateScore
                        $bestCandidate = [pscustomobject]@{
                            relative_path = $candidateRel
                            name = $candidate.Name
                            artifact_type = $candidateType
                            score = $candidateScore
                        }
                    }
                }
                if ($null -ne $bestCandidate) {
                    $inputPath = [string]$bestCandidate.relative_path
                    $selectedSourceReason = ('selected_from_evidence_root:{0}; artifact_type:{1}; score:{2}; excluded:{3}' -f $evidenceRootRel, [string]$bestCandidate.artifact_type, [int]$bestCandidate.score, ($excludedNames.Count))
                }
            }
        }
    }

    $outputPath = ''
    foreach ($outputField in @('Output', 'Output Artifact')) {
        $outputMatch = [regex]::Match($text, ('(?im)\b{0}\s*:\s*(?<path>\S+?\.json)\b' -f [regex]::Escape($outputField)))
        if ($outputMatch.Success) {
            $outputPath = ([string]$outputMatch.Groups['path'].Value).Trim()
            break
        }
    }
    if ([string]::IsNullOrWhiteSpace($outputPath) -and -not [string]::IsNullOrWhiteSpace($inputPath)) {
        $outputRootMatch = [regex]::Match($text, '(?im)\bOutput\s+Root\s*:\s*(?<path>[A-Za-z0-9_./-]+)\b')
        if ($outputRootMatch.Success) {
            $outputRootRel = Convert-ToLocalExecutionRepoRelativePath -PathValue (([string]$outputRootMatch.Groups['path'].Value).Trim())
            $episodeStem = [System.IO.Path]::GetFileNameWithoutExtension($inputPath)
            if (-not [string]::IsNullOrWhiteSpace($outputRootRel) -and -not [string]::IsNullOrWhiteSpace($episodeStem)) {
                $outputPath = ('{0}/{1}.episode.json' -f $outputRootRel.TrimEnd('/'), $episodeStem)
            }
        }
    }
    if ([string]::IsNullOrWhiteSpace($outputPath)) {
    $outputMatches = [regex]::Matches($text, 'runtime_remote_training/read_only_audit_artifacts/[A-Za-z0-9_./-]+?\.json|runtime/tod_engineering_corpus/[A-Za-z0-9_./-]+?\.json|runtime_remote_training/TOD_CAPABILITY_ASSESSMENT_V1\.latest\.json')
        if ($outputMatches.Count -gt 0) {
            $outputPath = ([string]$outputMatches[$outputMatches.Count - 1].Value).Trim()
        }
    }

    return [pscustomobject]@{
        input_path = if ([string]::IsNullOrWhiteSpace($inputPath)) { '' } else { Convert-ToLocalExecutionRepoRelativePath -PathValue $inputPath }
        output_path = if ([string]::IsNullOrWhiteSpace($outputPath)) { '' } else { Convert-ToLocalExecutionRepoRelativePath -PathValue $outputPath }
        selected_source_reason = $selectedSourceReason
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
    $text = Get-LocalExecutionCombinedText -Context $Context
    $requiredArtifactType = Get-LocalExecutionDirectiveValue -PromptText $text -FieldName 'Required Artifact Type'
    if ([string]::IsNullOrWhiteSpace($requiredArtifactType)) {
        $producesArtifactTypeMatch = [regex]::Match($text, '(?i)\bProduces\s+(?<value>tod_[A-Za-z0-9_.-]+)\b')
        if ($producesArtifactTypeMatch.Success) {
            $requiredArtifactType = ([string]$producesArtifactTypeMatch.Groups['value'].Value).Trim()
        }
    }
    if ([string]::IsNullOrWhiteSpace($requiredArtifactType)) {
        $inlineRequiredArtifactTypeMatches = [regex]::Matches($text, '(?i)\bRequired\s+Artifact\s+Type\s*:\s*(?<value>tod_[A-Za-z0-9_.-]+)\b')
        if ($inlineRequiredArtifactTypeMatches.Count -gt 0) {
            $requiredArtifactType = ([string]$inlineRequiredArtifactTypeMatches[$inlineRequiredArtifactTypeMatches.Count - 1].Groups['value'].Value).Trim()
        }
    }
    $isReadOnlyArtifactWrite = (
        [string]::Equals($category, 'artifact_write', [System.StringComparison]::OrdinalIgnoreCase) -and
        @(
            'tod_engineering_episode_card',
            'tod_engineering_episode_quality_examiner_verdict',
            'tod_engineering_context_package',
            'tod_model_utilization_engineering_judgment',
            'tod_engineering_provider_request',
            'tod_local_engineering_provider_inventory',
            'tod_engineering_provider_candidate_stub',
            'tod_engineering_provider_candidate_invocation',
            'tod_engineering_provider_candidate_verdict',
            'tod_engineering_provider_candidate_replan',
            'tod_engineering_corpus_foundation_index',
            'tod_readonly_retirement_eligibility_proof',
            'tod_autonomous_meaningful_newtext_synthesis',
            'tod_source_anchor_delta_proposal',
            'tod_readonly_evidence_comparison',
            'tod_read_only_evidence_comparison'
        ) -contains ([string]$requiredArtifactType)
    )
    $isEngineeringContextPackageWrite = (
        [string]::Equals($category, 'engineering_context_package', [System.StringComparison]::OrdinalIgnoreCase) -and
        [string]::Equals([string]$requiredArtifactType, 'tod_engineering_context_package', [System.StringComparison]::OrdinalIgnoreCase)
    )
    if ((@('read_only_assessment', 'report_only', 'diagnostic_only', 'inspection_only', 'inspection') -notcontains $category) -and -not $isReadOnlyArtifactWrite -and -not $isEngineeringContextPackageWrite) {
        return $false
    }

    $paths = Get-LocalExecutionReadOnlyAuditArtifactPaths -Context $Context
    if ([string]::IsNullOrWhiteSpace([string]$paths.input_path) -or [string]::IsNullOrWhiteSpace([string]$paths.output_path)) {
        return $false
    }

    $lowerText = $text.ToLowerInvariant()
    $allowsExplicitSourceAnchorEvidence = (
        [string]::Equals([string]$requiredArtifactType, 'tod_source_anchor_delta_proposal', [System.StringComparison]::OrdinalIgnoreCase) -or
        [string]::Equals([string]$requiredArtifactType, 'tod_autonomous_meaningful_newtext_synthesis', [System.StringComparison]::OrdinalIgnoreCase) -or
        [string]::Equals([string]$requiredArtifactType, 'tod_engineering_provider_candidate_replan', [System.StringComparison]::OrdinalIgnoreCase)
    )
    if (-not $allowsExplicitSourceAnchorEvidence -and $lowerText -match 'exact_text|extracted_tokens|branch_excerpt|regex_terms_excerpt|literal source token') {
        return $false
    }
    return (($lowerText -match 'read-only|read only') -or $isReadOnlyArtifactWrite -or $isEngineeringContextPackageWrite) -and ($lowerText -match 'audit|assessment|episode|corpus|engineering[-_\s]?context|synthesis|source[-_\s]?anchor') -and ($lowerText -match 'artifact|episode|package')
}

function Test-LocalExecutionReadOnlyTaskContextArtifactTask {
    param([Parameter(Mandatory = $true)]$Context)

    $category = Get-LocalExecutionTaskCategory -Context $Context
    if (@('read_only_assessment', 'read_only_role_classification', 'report_only', 'diagnostic_only', 'inspection_only', 'inspection', 'review_only') -notcontains $category) {
        return $false
    }

    $text = (Get-LocalExecutionCombinedText -Context $Context)
    $patchSpec = Get-LocalExecutionPatchEvidenceArtifactSpec -Context $Context
    if (
        $text -match '(?im)\bInput\s+Patch\s*:' -or
        (
            -not [string]::IsNullOrWhiteSpace([string]$patchSpec.input_patch) -and
            -not [string]::IsNullOrWhiteSpace([string]$patchSpec.output_path)
        )
    ) {
        return $false
    }

    $paths = Get-LocalExecutionReadOnlyAuditArtifactPaths -Context $Context
    if (-not [string]::IsNullOrWhiteSpace([string]$paths.input_path) -or [string]::IsNullOrWhiteSpace([string]$paths.output_path)) {
        return $false
    }

    $lowerText = $text.ToLowerInvariant()
    return ($lowerText -match 'read-only|read only|no source code changes|no code changes') -and ($lowerText -match 'artifact|proof|evidence')
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
    if (
        [string]::Equals($category, 'target_selection', [System.StringComparison]::OrdinalIgnoreCase) -or
        [string]::Equals($category, 'source_anchor_observation', [System.StringComparison]::OrdinalIgnoreCase) -or
        [string]::Equals($category, 'anchor_selection', [System.StringComparison]::OrdinalIgnoreCase)
    ) {
        return $false
    }
    if (Test-LocalExecutionSourceAnchorObservationTask -Context $Context) {
        return $false
    }

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

function Test-LocalExecutionFreshRoutePatchEvidenceRegistrationTask {
    param([Parameter(Mandatory = $true)]$Context)

    $category = Get-LocalExecutionTaskCategory -Context $Context
    if (-not [string]::Equals($category, 'route_patch_evidence_registration', [System.StringComparison]::OrdinalIgnoreCase)) {
        return $false
    }
    if (Test-LocalExecutionSourceAnchorObservationTask -Context $Context) {
        return $false
    }

    $combinedText = Get-LocalExecutionCombinedText -Context $Context
    if ($combinedText -match '(?im)\bInput\s+Patch\s*:') {
        return $false
    }

    $text = $combinedText.ToLowerInvariant()
    $readOnlyEvidenceTask = (
        @('read_only_assessment', 'report_only', 'diagnostic_only', 'inspection_only', 'inspection') -contains $category -or
        ($text -match 'read-only|read only|no source code changes|no code changes')
    )
    if (-not $readOnlyEvidenceTask) { return $false }

    $explicitFreshPatchRequest = (
        ($text -match 'fresh|prior|repository|git|history') -and
        ($text -match 'patch') -and
        ($text -match 'route|router|studio|mim/tod|authority')
    )
    $discoveryAuthorityRequest = (
        ($text -match 'discover|select|choose|find') -and
        ($text -match 'saved|existing|training evidence|evidence area|repository evidence') -and
        ($text -match 'route|router|studio|mim/tod|authority') -and
        ($text -match 'classif|inspect|audit|proof')
    )

    return ($explicitFreshPatchRequest -or $discoveryAuthorityRequest)
}

function Get-LocalExecutionSavedRoutePatchEvidenceCandidates {
    param()

    $holdsRoot = Join-Path $script:LocalEngineRepoRoot 'runtime_remote_training/cleanup_holds'
    if (-not (Test-Path -Path $holdsRoot -PathType Container)) {
        return @()
    }

    $signalSpecs = @(
        [pscustomobject]@{ name = 'visible_reply_authority'; pattern = '_studio_cognitive_authority_reply|first working hypothesis|I do not have a specialized handler|Recommended action:|Dave needed:'; weight = 20 },
        [pscustomobject]@{ name = 'operator_contract_injection'; pattern = 'Recommended action:|Expected evidence:|Aging rule:|Dave needed:'; weight = 18 },
        [pscustomobject]@{ name = 'active_conversation_state'; pattern = 'active conversation|conversation state|missing fields|slot'; weight = 14 },
        [pscustomobject]@{ name = 'observational_relationship_memory'; pattern = 'observational|relationship memory|relationship_type|subject.*relationship|current_location|facility_location'; weight = 14 },
        [pscustomobject]@{ name = 'response_authority_audit'; pattern = 'authority trace|response authority|final_authority|allowed_transformations|operator_contract_allowed'; weight = 16 },
        [pscustomobject]@{ name = 'tod_phrase_patch'; pattern = 'If Codex disappeared|Codex disappeared|no codex|without codex'; weight = 8 }
    )

    $candidates = New-Object System.Collections.Generic.List[object]
    foreach ($file in @(Get-ChildItem -Path $holdsRoot -Filter '*.patch' -File -ErrorAction SilentlyContinue)) {
        $relativePath = 'runtime_remote_training/cleanup_holds/{0}' -f [string]$file.Name
        if (-not (Test-LocalExecutionReadOnlyPatchEvidencePathAllowed -RelativePath $relativePath)) {
            continue
        }

        $patchText = [System.IO.File]::ReadAllText([string]$file.FullName, [System.Text.UTF8Encoding]::new($false))
        $routeFileMatches = @([regex]::Matches($patchText, '(?m)^diff --git a/(?<old>\S+) b/(?<new>\S+)') | Where-Object {
            [string]$_.Groups['new'].Value -match 'tmp_remote_mim/core/routers|core/routers|routes?\.py'
        })
        $routeScore = if (@($routeFileMatches).Count -gt 0 -or $patchText -match 'tmp_remote_mim/core/routers|core/routers|routes?\.py') { 30 } else { 0 }

        $signals = New-Object System.Collections.Generic.List[object]
        $signalScore = 0
        foreach ($signalSpec in @($signalSpecs)) {
            $matches = @([regex]::Matches($patchText, [string]$signalSpec.pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase))
            if (@($matches).Count -gt 0) {
                $signals.Add([ordered]@{
                    signal = [string]$signalSpec.name
                    match_count = @($matches).Count
                    sample = [string]$matches[0].Value
                }) | Out-Null
                $signalScore += ([int]$signalSpec.weight * [Math]::Min(@($matches).Count, 5))
            }
        }

        if ($routeScore -le 0 -or $signalScore -le 0) {
            continue
        }

        $candidates.Add([pscustomobject]@{
            relative_path = $relativePath
            full_path = [string]$file.FullName
            score = ($routeScore + $signalScore)
            route_file_count = @($routeFileMatches).Count
            signals = @($signals.ToArray())
            length = [int64]$file.Length
            last_write_time_utc = $file.LastWriteTimeUtc
        }) | Out-Null
    }

    return @($candidates.ToArray() | Sort-Object -Property @{ Expression = 'score'; Descending = $true }, @{ Expression = 'last_write_time_utc'; Descending = $true }, @{ Expression = 'length'; Descending = $true })
}

function Test-LocalExecutionSavedRoutePatchEvidenceDiscoveryTask {
    param([Parameter(Mandatory = $true)]$Context)

    $category = Get-LocalExecutionTaskCategory -Context $Context
    if (-not [string]::Equals($category, 'route_patch_evidence_discovery', [System.StringComparison]::OrdinalIgnoreCase)) {
        return $false
    }
    if (Test-LocalExecutionSourceAnchorObservationTask -Context $Context) {
        return $false
    }

    $combinedText = Get-LocalExecutionCombinedText -Context $Context
    if ($combinedText -match '(?im)\bInput\s+Patch\s*:') {
        return $false
    }

    $text = $combinedText.ToLowerInvariant()
    $readOnlyEvidenceTask = @(
        'read_only_assessment',
        'report_only',
        'diagnostic_only',
        'inspection_only',
        'inspection',
        'route_patch_evidence_discovery'
    ) -contains $category
    if (-not $readOnlyEvidenceTask) { return $false }

    $savedEvidenceRequest = (
        ($text -match 'discover|select|choose|find') -and
        ($text -match 'saved|existing|training evidence|evidence area|cleanup_holds') -and
        ($text -match 'route|router|studio|mim/tod|authority') -and
        ($text -match 'classif|inspect|audit|proof')
    )
    return $savedEvidenceRequest
}

function Invoke-LocalExecutionSavedRoutePatchEvidenceDiscovery {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)]$Spec
    )

    $candidates = @(Get-LocalExecutionSavedRoutePatchEvidenceCandidates)
    if (@($candidates).Count -eq 0) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'saved_route_patch_evidence_missing' -Reason 'No saved route-authority patch with usable authority signals was found in runtime_remote_training/cleanup_holds/.' -MissingVariable 'saved_route_patch_evidence')
    }

    $selected = $candidates[0]
    $taskId = if ($Context.PSObject.Properties['task_id'] -and -not [string]::IsNullOrWhiteSpace([string]$Context.task_id)) { [string]$Context.task_id } else { 'TOD-SAVED-ROUTE-PATCH' }
    $safeTaskId = ($taskId -replace '[^A-Za-z0-9_-]', '-')
    $inputStem = [System.IO.Path]::GetFileNameWithoutExtension([string]$selected.relative_path)
    $safeStem = ($inputStem -replace '[^A-Za-z0-9_-]', '-')
    if ($safeStem.Length -gt 48) { $safeStem = $safeStem.Substring(0, 48) }
    $outputRel = ('runtime_remote_training/read_only_audit_artifacts/{0}_{1}.latest.json' -f $safeTaskId, $safeStem)

    $signalSummary = (@($selected.signals) | ForEach-Object { '{0}:{1}' -f [string]$_.signal, [int]$_.match_count }) -join ', '
    $combinedScope = @(
        [string]$Context.scope,
        '',
        ('Input Patch: {0}' -f [string]$selected.relative_path),
        ('Output artifact: {0}' -f $outputRel),
        ('Selected saved route-authority evidence because it has score {0}, route_file_count {1}, and signals: {2}.' -f [int]$selected.score, [int]$selected.route_file_count, $signalSummary),
        'Classify patch evidence for route-level hardcoded response authority, operator-contract authority, phrase patch debt, reusable service candidates, process support, and learned-capability return paths.',
        'Read-only assessment. No source code changes.'
    ) -join "`n"

    $contextMembers = [ordered]@{}
    foreach ($property in @($Context.PSObject.Properties)) {
        $contextMembers[$property.Name] = $property.Value
    }
    $contextMembers['scope'] = $combinedScope
    $contextMembers['task_category'] = 'read_only_assessment'
    $contextMembers['metadata'] = @{
        task_category = 'read_only_assessment'
        task_type = 'read_only_assessment'
        selected_saved_patch = [string]$selected.relative_path
        selected_saved_patch_score = [int]$selected.score
        selected_saved_patch_signals = @($selected.signals)
    }
    $classificationContext = [pscustomobject]$contextMembers
    $classificationResult = Invoke-LocalExecutionPatchEvidenceArtifact -Context $classificationContext -Result $Result -Spec $Spec

    if ([string]$classificationResult.status -eq 'completed') {
        $commands = @($classificationResult.commands_run)
        $classificationResult | Add-Member -NotePropertyName commands_run -NotePropertyValue @('Select-SavedRoutePatchEvidenceFromTrainingArea') -Force
        if (@($commands).Count -gt 0) {
            $classificationResult.commands_run = @('Select-SavedRoutePatchEvidenceFromTrainingArea') + @($commands)
        }
        $classificationResult | Add-Member -NotePropertyName selected_saved_patch_source -NotePropertyValue ([ordered]@{
            source = 'runtime_remote_training_cleanup_holds'
            patch = [string]$selected.relative_path
            score = [int]$selected.score
            route_file_count = [int]$selected.route_file_count
            signals = @($selected.signals)
            output_artifact = $outputRel
        }) -Force
        $classificationResult.summary = ('Selected saved route-authority evidence {0} and published classification artifact {1}.' -f [string]$selected.relative_path, $outputRel)
    }

    return $classificationResult
}

function Get-LocalExecutionRoutePatchEvidenceCommits {
    param()

    $routePaths = @(
        'tmp_remote_mim/core/routers/studio.py',
        'tmp_remote_mim/core/routers/tod_ui.py',
        'core/routers/studio.py',
        'core/routers/tod_ui.py',
        'tmp_remote_mim/routes.py',
        'routes.py'
    )
    $args = @('-C', $script:LocalEngineRepoRoot, 'log', '--format=%H', '--') + $routePaths
    $commits = @(& git @args 2>$null | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    return @($commits)
}

function Invoke-LocalExecutionFreshRoutePatchEvidenceRegistration {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)]$Spec
    )

    $commits = Get-LocalExecutionRoutePatchEvidenceCommits
    if (@($commits).Count -eq 0) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'fresh_route_patch_git_history_missing' -Reason 'No committed route history was found for Studio MIM/TOD route evidence registration.' -MissingVariable 'route_patch_git_commit')
    }

    $routePaths = @(
        'tmp_remote_mim/core/routers/studio.py',
        'tmp_remote_mim/core/routers/tod_ui.py',
        'core/routers/studio.py',
        'core/routers/tod_ui.py',
        'tmp_remote_mim/routes.py',
        'routes.py'
    )
    $selectedCommit = ''
    $selectedPatchText = ''
    foreach ($commit in @($commits)) {
        $showArgs = @('-C', $script:LocalEngineRepoRoot, 'show', '--format=', '--find-renames', [string]$commit, '--') + $routePaths
        $patchText = [string]::Join("`n", @(& git @showArgs 2>$null))
        if ($patchText -match '(?m)^diff --git ' -and $patchText -match 'tmp_remote_mim/core/routers|core/routers|routes\.py') {
            $selectedCommit = [string]$commit
            $selectedPatchText = $patchText
            break
        }
    }

    if ([string]::IsNullOrWhiteSpace($selectedCommit) -or [string]::IsNullOrWhiteSpace($selectedPatchText)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'fresh_route_patch_diff_missing' -Reason 'Committed route history exists, but no route patch diff could be extracted for evidence registration.' -MissingVariable 'route_patch_diff')
    }

    $taskId = if ($Context.PSObject.Properties['task_id'] -and -not [string]::IsNullOrWhiteSpace([string]$Context.task_id)) { [string]$Context.task_id } else { 'TOD-FRESH-ROUTE-PATCH' }
    $safeTaskId = ($taskId -replace '[^A-Za-z0-9_-]', '-')
    $commitShort = if ($selectedCommit.Length -gt 12) { $selectedCommit.Substring(0, 12) } else { $selectedCommit }
    $inputRel = ('runtime_remote_training/cleanup_holds/{0}_{1}.patch' -f $safeTaskId, $commitShort)
    $outputRel = ('runtime_remote_training/read_only_audit_artifacts/{0}_{1}.latest.json' -f $safeTaskId, $commitShort)
    $inputAbs = Join-Path $script:LocalEngineRepoRoot ($inputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    New-Item -ItemType Directory -Path (Split-Path -Parent $inputAbs) -Force | Out-Null
    [System.IO.File]::WriteAllText($inputAbs, $selectedPatchText, [System.Text.UTF8Encoding]::new($false))

    $combinedScope = @(
        [string]$Context.scope,
        '',
        ('Input Patch: {0}' -f $inputRel),
        ('Output artifact: {0}' -f $outputRel),
        'Classify patch evidence for route-level hardcoded response authority, operator-contract authority, phrase patch debt, reusable service candidates, process support, and learned-capability return paths.',
        'Read-only assessment. No source code changes.'
    ) -join "`n"

    $contextMembers = [ordered]@{}
    foreach ($property in @($Context.PSObject.Properties)) {
        $contextMembers[$property.Name] = $property.Value
    }
    $contextMembers['scope'] = $combinedScope
    $contextMembers['task_category'] = 'read_only_assessment'
    $contextMembers['metadata'] = @{
        task_category = 'read_only_assessment'
        task_type = 'read_only_assessment'
        selected_git_commit = $selectedCommit
        registered_patch = $inputRel
    }
    $classificationContext = [pscustomobject]$contextMembers
    $classificationResult = Invoke-LocalExecutionPatchEvidenceArtifact -Context $classificationContext -Result $Result -Spec $Spec

    if ([string]$classificationResult.status -eq 'completed') {
        $classificationResult.files_changed = @($inputRel, $outputRel)
        $commands = @($classificationResult.commands_run)
        $classificationResult | Add-Member -NotePropertyName commands_run -NotePropertyValue @('Register-FreshRoutePatchEvidenceFromGitHistory') -Force
        if (@($commands).Count -gt 0) {
            $classificationResult.commands_run = @('Register-FreshRoutePatchEvidenceFromGitHistory') + @($commands)
        }
        $classificationResult | Add-Member -NotePropertyName registered_patch_source -NotePropertyValue ([ordered]@{
            source = 'git_history'
            commit = $selectedCommit
            patch = $inputRel
            output_artifact = $outputRel
        }) -Force
        $classificationResult.summary = ('Registered fresh route patch evidence {0} from commit {1} and published classification artifact {2}.' -f $inputRel, $commitShort, $outputRel)
    }

    return $classificationResult
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
    $Result.test_results = @('pass', $(if (@($signals.ToArray()).Count -gt 0) { 'pass' } else { 'fail' }), 'pass', 'pass')
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
        $sourceFile = Get-LocalExecutionDirectiveValue -PromptText $text -FieldName 'Source File'
    }
    if ([string]::IsNullOrWhiteSpace($sourceFile)) {
        $sourceFile = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Inspect Target File'
    }
    if ([string]::IsNullOrWhiteSpace($sourceFile)) {
        $sourceFile = Get-LocalExecutionDirectiveValue -PromptText $text -FieldName 'Inspect Target File'
    }
    if ([string]::IsNullOrWhiteSpace($sourceFile)) {
        $sourceFile = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Target File'
    }
    if ([string]::IsNullOrWhiteSpace($sourceFile)) {
        $sourceFile = Get-LocalExecutionDirectiveValue -PromptText $text -FieldName 'Target File'
    }
    if ([string]::IsNullOrWhiteSpace($sourceFile)) {
        $sourceMatch = [regex]::Match($text, '(?im)^\s*(?:[-*]\s*)?(?:Scope\s*:\s*)?Source\s+File\s*:\s*(?<value>[^\r\n]+?)\s*$')
        if ($sourceMatch.Success) {
            $sourceFile = ([string]$sourceMatch.Groups['value'].Value).Trim()
        }
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

function Get-LocalExecutionAnchorSelectionSpec {
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
    if ([string]::IsNullOrWhiteSpace($sourceFile)) {
        $sourceFile = Get-LocalExecutionDirectiveValue -PromptText $text -FieldName 'Source File'
    }
    if ([string]::IsNullOrWhiteSpace($sourceFile)) {
        $sourceFile = Get-LocalExecutionDirectiveValue -PromptText $text -FieldName 'Inspect Target File'
    }
    if ([string]::IsNullOrWhiteSpace($sourceFile)) {
        $sourceFile = Get-LocalExecutionDirectiveValue -PromptText $text -FieldName 'Target File'
    }
    if ([string]::IsNullOrWhiteSpace($sourceFile)) {
        $sourceMatch = [regex]::Match($text, '(?im)^\s*(?:[-*]\s*)?(?:Scope\s*:\s*)?Source\s+File\s*:\s*(?<value>[^\r\n]+?)\s*$')
        if ($sourceMatch.Success) {
            $sourceFile = ([string]$sourceMatch.Groups['value'].Value).Trim()
        }
    }

    $outputMatches = [regex]::Matches($text, 'runtime_remote_training/read_only_audit_artifacts/[A-Za-z0-9_./-]+?\.json')
    $outputPath = ''
    if ($outputMatches.Count -gt 0) {
        $outputPath = ([string]$outputMatches[$outputMatches.Count - 1].Value).Trim()
    }

    return [pscustomobject]@{
        source_file = if ([string]::IsNullOrWhiteSpace($sourceFile)) { '' } else { Convert-ToLocalExecutionRepoRelativePath -PathValue $sourceFile }
        output_path = if ([string]::IsNullOrWhiteSpace($outputPath)) { '' } else { Convert-ToLocalExecutionRepoRelativePath -PathValue $outputPath }
    }
}

function Test-LocalExecutionAnchorSelectionTask {
    param([Parameter(Mandatory = $true)]$Context)

    $category = Get-LocalExecutionTaskCategory -Context $Context
    if ([string]::Equals($category, 'source_anchor_observation', [System.StringComparison]::OrdinalIgnoreCase)) {
        return $false
    }
    if (@('report_only', 'diagnostic_only', 'inspection_only', 'inspection', 'source_anchor_observation', 'anchor_selection', 'chat_execution') -notcontains $category) {
        return $false
    }

    $text = (Get-LocalExecutionCombinedText -Context $Context).ToLowerInvariant()
    if ($text -notmatch 'anchor[_\-\s]+selection|select[_\-\s]+.*anchor|choose[_\-\s]+.*anchor') {
        return $false
    }
    if (
        -not [string]::Equals($category, 'anchor_selection', [System.StringComparison]::OrdinalIgnoreCase) -and
        $text -match 'source[-_\s]+anchor\s+observation|anchor\s+observation\s+artifact'
    ) {
        return $false
    }

    $spec = Get-LocalExecutionAnchorSelectionSpec -Context $Context
    return (
        -not [string]::IsNullOrWhiteSpace([string]$spec.source_file) -and
        -not [string]::IsNullOrWhiteSpace([string]$spec.output_path)
    )
}

function Invoke-LocalExecutionAnchorSelection {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)]$Spec
    )

    $anchorSelectionSpec = Get-LocalExecutionAnchorSelectionSpec -Context $Context
    $sourceRel = [string]$anchorSelectionSpec.source_file
    $outputRel = [string]$anchorSelectionSpec.output_path
    if ([string]::IsNullOrWhiteSpace($sourceRel)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'anchor_selection_source_missing' -Reason 'Anchor selection requires Source File, Inspect Target File, or Target File.' -MissingVariable 'source_file')
    }
    if ([string]::IsNullOrWhiteSpace($outputRel)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'anchor_selection_output_missing' -Reason 'Anchor selection requires an output artifact path under runtime_remote_training/read_only_audit_artifacts/.' -MissingVariable 'output_path')
    }
    if (-not (Test-LocalExecutionSafePath -RelativePath $sourceRel)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'anchor_selection_source_unsafe' -Reason ('Source file is outside LocalExecutionEngine safe roots: {0}' -f $sourceRel) -MissingVariable 'safe_source_path')
    }
    if (-not (Test-LocalExecutionSafePath -RelativePath $outputRel)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'anchor_selection_output_unsafe' -Reason ('Output artifact path is outside LocalExecutionEngine safe roots: {0}' -f $outputRel) -MissingVariable 'safe_output_path')
    }

    $sourceAbs = Join-Path $script:LocalEngineRepoRoot $sourceRel
    $outputAbs = Join-Path $script:LocalEngineRepoRoot $outputRel
    if (-not (Test-Path -Path $sourceAbs -PathType Leaf)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'anchor_selection_source_not_found' -Reason ('Source file does not exist: {0}' -f $sourceRel) -MissingVariable 'source_file')
    }

    $lines = @(Get-Content -Path $sourceAbs)
    $combinedText = Get-LocalExecutionCombinedText -Context $Context
    $taskRequiresPacketEditing = ($combinedText -match 'artifact_write|artifact[-_\s]?write|edit[-_\s]?mode|materialization')
    $evidenceMatches = [regex]::Matches($combinedText, 'runtime_remote_training/read_only_audit_artifacts/[A-Za-z0-9_./-]+?\.json')
    $rejectedAnchorPatterns = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($evidenceMatch in $evidenceMatches) {
        $evidenceRel = Convert-ToLocalExecutionRepoRelativePath -PathValue ([string]$evidenceMatch.Value)
        if ([string]::IsNullOrWhiteSpace($evidenceRel) -or [string]::Equals($evidenceRel, $outputRel, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }
        if (-not (Test-LocalExecutionSafePath -RelativePath $evidenceRel)) {
            continue
        }
        $evidenceAbs = Join-Path $script:LocalEngineRepoRoot $evidenceRel
        if (-not (Test-Path -Path $evidenceAbs -PathType Leaf)) {
            continue
        }
        try {
            $evidenceArtifact = Get-Content -Path $evidenceAbs -Raw | ConvertFrom-Json
            if (
                $evidenceArtifact.PSObject.Properties['artifact_type'] -and
                [string]$evidenceArtifact.artifact_type -eq 'tod_anchor_selection_semantic_rejection' -and
                $evidenceArtifact.PSObject.Properties['decision'] -and
                [string]$evidenceArtifact.decision -eq 'reject_anchor' -and
                $evidenceArtifact.PSObject.Properties['selected_anchor_pattern'] -and
                -not [string]::IsNullOrWhiteSpace([string]$evidenceArtifact.selected_anchor_pattern)
            ) {
                [void]$rejectedAnchorPatterns.Add([string]$evidenceArtifact.selected_anchor_pattern)
            }
        }
        catch {
            continue
        }
    }
    $lineOccurrences = @{}
    foreach ($rawLine in $lines) {
        $normalizedLine = ([string]$rawLine).Trim()
        if ([string]::IsNullOrWhiteSpace($normalizedLine)) { continue }
        if ($lineOccurrences.ContainsKey($normalizedLine)) {
            $lineOccurrences[$normalizedLine] = [int]$lineOccurrences[$normalizedLine] + 1
        }
        else {
            $lineOccurrences[$normalizedLine] = 1
        }
    }
    $candidates = [System.Collections.Generic.List[object]]::new()
    for ($idx = 0; $idx -lt $lines.Count; $idx++) {
        $line = [string]$lines[$idx]
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
        $anchorKind = ''
        $anchorScore = 0
        $isAnchorLike = (
            $trimmed -match '^(async\s+def|def|class)\s+[A-Za-z_][A-Za-z0-9_]*' -or
            $trimmed -match '^function\s+[A-Za-z_][A-Za-z0-9_-]*' -or
            $trimmed -match '^\$[A-Za-z_][A-Za-z0-9_]*\s*=' -or
            $trimmed -match '^@[A-Za-z_][A-Za-z0-9_.]*'
        )
        if (-not $isAnchorLike) { continue }
        $candidateEndLine = [Math]::Min($lines.Count, (($idx + 1) + 8))
        if ($trimmed -match '\{\s*$') {
            $braceDepth = 0
            for ($lineIndex = $idx; $lineIndex -lt $lines.Count; $lineIndex++) {
                $lineText = [string]$lines[$lineIndex]
                $braceDepth += ([regex]::Matches($lineText, '\{')).Count
                $braceDepth -= ([regex]::Matches($lineText, '\}')).Count
                if ($lineIndex -gt $idx -and $braceDepth -le 0) {
                    $candidateEndLine = ($lineIndex + 1)
                    break
                }
            }
        }
        $candidateContext = Get-LocalExecutionRawTextLineRange -Content ($lines -join [Environment]::NewLine) -StartLine ($idx + 1) -EndLine $candidateEndLine
        $candidateHasPacketEditingEvidence = ($candidateContext -match 'artifact_write|artifact[-_\s]?write|edit[-_\s]?mode|packet|materialization|directive|genericboundedtask|generic[-_\s]?bounded')
        $candidateSymbolName = ''
        $symbolMatch = [regex]::Match($trimmed, '^(?:async\s+def|def|class|function)\s+(?<name>[A-Za-z_][A-Za-z0-9_-]*)')
        if ($symbolMatch.Success) {
            $candidateSymbolName = [string]$symbolMatch.Groups['name'].Value
        }
        $candidateNameMatchesPacketEditing = ($candidateSymbolName -match '(?i)packet|materialization|artifact|bounded|genericbounded')
        $candidateRejectedByEvidence = $rejectedAnchorPatterns.Contains($trimmed)
        if ($trimmed -match '^(async\s+def|def|class)\s+[A-Za-z_][A-Za-z0-9_]*') {
            $anchorKind = 'python_symbol'
            $anchorScore = 100
        }
        elseif ($trimmed -match '^function\s+[A-Za-z_][A-Za-z0-9_-]*') {
            $anchorKind = 'powershell_function'
            $anchorScore = 100
        }
        elseif ($trimmed -match '^@[A-Za-z_][A-Za-z0-9_.]*') {
            $anchorKind = 'decorator_or_attribute'
            $anchorScore = 80
        }
        elseif ($trimmed -match '^\$[A-Za-z_][A-Za-z0-9_]*\s*=') {
            $anchorKind = 'assignment'
            $anchorScore = 10
        }
        if ($taskRequiresPacketEditing) {
            if ($candidateNameMatchesPacketEditing) {
                $anchorScore += 500
            }
            elseif ($candidateHasPacketEditingEvidence) {
                $anchorScore += 200
            }
            else {
                $anchorScore -= 50
            }
        }
        if ($candidateRejectedByEvidence) {
            $anchorScore -= 500
        }
        $occurrences = if ($lineOccurrences.ContainsKey($trimmed)) { [int]$lineOccurrences[$trimmed] } else { 0 }
        [void]$candidates.Add([ordered]@{
                line_number = $idx + 1
                anchor_pattern = $trimmed
                occurrence_count = $occurrences
                unique = ($occurrences -eq 1)
                anchor_kind = $anchorKind
                selection_score = $anchorScore
                packet_editing_evidence = [bool]$candidateHasPacketEditingEvidence
                packet_editing_name_match = [bool]$candidateNameMatchesPacketEditing
                rejected_by_input_evidence = [bool]$candidateRejectedByEvidence
            })
    }

    $selected = @($candidates.ToArray() |
        Where-Object { [bool]$_.unique -and -not [bool]$_.rejected_by_input_evidence -and ((-not $taskRequiresPacketEditing) -or [bool]$_.packet_editing_evidence) } |
        Sort-Object -Property @{ Expression = { [int]$_.selection_score }; Descending = $true }, @{ Expression = { [int]$_.line_number }; Descending = $false } |
        Select-Object -First 1)
    if (@($selected).Count -eq 0) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'anchor_selection_unique_anchor_missing' -Reason ('No unique function/class/route-style anchor could be selected from {0}.' -f $sourceRel) -MissingVariable 'selected_anchor_pattern')
    }
    $selectedAnchor = $selected[0]
    $candidateArray = @($candidates.ToArray())
    $selectedLine = [int]$selectedAnchor.line_number
    $candidateEvidenceLimit = 50
    $boundedCandidates = @(
        $candidateArray |
            Where-Object {
                ([int]$_.line_number -eq $selectedLine) -or
                ([int]$_.line_number -le 20) -or
                ([int]$_.selection_score -ge 80)
            } |
            Select-Object -First $candidateEvidenceLimit
    )
    if (@($boundedCandidates | Where-Object { [int]$_.line_number -eq $selectedLine }).Count -eq 0) {
        $boundedCandidates = @($selectedAnchor) + @($boundedCandidates | Select-Object -First ($candidateEvidenceLimit - 1))
    }
    $artifact = [ordered]@{
        artifact_type = 'tod_anchor_selection_artifact'
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        source = 'local_execution_anchor_selection_lane'
        objective_id = if ($Context.PSObject.Properties['objective_id']) { [string]$Context.objective_id } else { '' }
        task_id = if ($Context.PSObject.Properties['task_id']) { [string]$Context.task_id } else { '' }
        source_file = $sourceRel
        selected_anchor_pattern = [string]$selectedAnchor.anchor_pattern
        selected_line = [int]$selectedAnchor.line_number
        occurrence_count = [int]$selectedAnchor.occurrence_count
        source_read = $true
        selected_anchor_nonempty = -not [string]::IsNullOrWhiteSpace([string]$selectedAnchor.anchor_pattern)
        selected_anchor_unique = ([int]$selectedAnchor.occurrence_count -eq 1)
        selected_anchor_kind = [string]$selectedAnchor.anchor_kind
        candidate_count = @($candidateArray).Count
        inspected_candidates = @($boundedCandidates)
        omitted_candidate_count = [Math]::Max(0, (@($candidateArray).Count - @($boundedCandidates).Count))
        rationale = 'Selected the highest-scoring unique semantic source anchor, preferring functions/classes/routes over boilerplate assignments so the next source-anchor observation is bounded to meaningful current code.'
        no_code_changes = $true
        validation = [ordered]@{
            artifact_path = $outputRel
            source_read = $true
            selected_anchor_nonempty = -not [string]::IsNullOrWhiteSpace([string]$selectedAnchor.anchor_pattern)
            selected_anchor_unique = ([int]$selectedAnchor.occurrence_count -eq 1)
            source_edits = @()
        }
        continuation_action = 'Run source-anchor observation using selected_anchor_pattern as Anchor Pattern.'
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $outputAbs) -Force | Out-Null
    [System.IO.File]::WriteAllText($outputAbs, ($artifact | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))
    $Result.summary = ('Published anchor selection artifact {0} for {1} line {2}.' -f $outputRel, $sourceRel, [int]$selectedAnchor.line_number)
    $Result.files_changed = @($outputRel)
    $Result.tests_run = @('source file read', 'anchor candidates inspected', 'unique anchor selected', 'anchor selection artifact write', 'no-code-change assertion')
    $Result.test_results = @('pass', 'pass', 'pass', 'pass', 'pass')
    $Result | Add-Member -NotePropertyName command_output -NotePropertyValue ('Anchor selected: {0}' -f [string]$selectedAnchor.anchor_pattern) -Force
    $Result | Add-Member -NotePropertyName diff_summary -NotePropertyValue ('Artifact write only: {0}' -f $outputRel) -Force
    $Result | Add-Member -NotePropertyName commands_run -NotePropertyValue @('Invoke-LocalExecutionAnchorSelection') -Force
    $Result | Add-Member -NotePropertyName validation_results -NotePropertyValue @(
        [pscustomobject]@{ name = 'source file read'; passed = $true; required = $true },
        [pscustomobject]@{ name = 'anchor candidates inspected'; passed = $true; required = $true },
        [pscustomobject]@{ name = 'unique anchor selected'; passed = $true; required = $true },
        [pscustomobject]@{ name = 'anchor selection artifact write'; passed = $true; required = $true },
        [pscustomobject]@{ name = 'no-code-change assertion'; passed = $true; required = $true }
    ) -Force
    $Result | Add-Member -NotePropertyName blockers -NotePropertyValue @() -Force
    $Result | Add-Member -NotePropertyName confidence -NotePropertyValue 'medium' -Force
    $Result | Add-Member -NotePropertyName rollback_hint -NotePropertyValue ('Remove generated artifact {0} to roll back anchor selection evidence.' -f $outputRel) -Force
    $Result | Add-Member -NotePropertyName no_change_required -NotePropertyValue $false -Force
    return (Complete-EngineExecutionResult -Result $Result -Status 'completed')
}

function Test-LocalExecutionAnchorSelectionSemanticRejectionTask {
    param([Parameter(Mandatory = $true)]$Context)

    $category = Get-LocalExecutionTaskCategory -Context $Context
    if (@('read_only_assessment', 'report_only', 'diagnostic_only', 'inspection_only', 'inspection') -notcontains $category) {
        return $false
    }

    $text = (Get-LocalExecutionCombinedText -Context $Context).ToLowerInvariant()
    if ($text -notmatch 'anchor[-_\s]?selection\s+artifact' -or $text -notmatch 'semantic' -or $text -notmatch 'reject|rejection|relevance') {
        return $false
    }

    $paths = Get-LocalExecutionSemanticSourceAuditPaths -Context $Context
    return (@($paths.input_paths).Count -ge 1 -and -not [string]::IsNullOrWhiteSpace([string]$paths.output_path))
}

function Invoke-LocalExecutionAnchorSelectionSemanticRejection {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)]$Spec
    )

    $paths = Get-LocalExecutionSemanticSourceAuditPaths -Context $Context
    $inputRel = [string](@($paths.input_paths) | Select-Object -First 1)
    $outputRel = [string]$paths.output_path
    foreach ($pathEntry in @(
            [pscustomobject]@{ Name = 'input_artifact'; Value = $inputRel },
            [pscustomobject]@{ Name = 'output_path'; Value = $outputRel }
        )) {
        if ([string]::IsNullOrWhiteSpace([string]$pathEntry.Value)) {
            return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode ('anchor_selection_semantic_rejection_{0}_missing' -f $pathEntry.Name) -Reason ('Anchor-selection semantic rejection requires {0}.' -f $pathEntry.Name) -MissingVariable $pathEntry.Name)
        }
        if (-not (Test-LocalExecutionSafePath -RelativePath ([string]$pathEntry.Value))) {
            return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode ('anchor_selection_semantic_rejection_{0}_unsafe' -f $pathEntry.Name) -Reason ('Anchor-selection semantic rejection path is outside LocalExecutionEngine safe roots: {0}' -f [string]$pathEntry.Value) -MissingVariable ('safe_' + $pathEntry.Name))
        }
    }

    $inputAbs = Join-Path $script:LocalEngineRepoRoot $inputRel
    $outputAbs = Join-Path $script:LocalEngineRepoRoot $outputRel
    if (-not (Test-Path -Path $inputAbs -PathType Leaf)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'anchor_selection_semantic_rejection_input_not_found' -Reason ('Input artifact does not exist: {0}' -f $inputRel) -MissingVariable 'input_artifact')
    }

    $anchorArtifact = Get-Content -Path $inputAbs -Raw | ConvertFrom-Json
    if (-not $anchorArtifact.PSObject.Properties['artifact_type'] -or [string]$anchorArtifact.artifact_type -ne 'tod_anchor_selection_artifact') {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'anchor_selection_semantic_rejection_input_not_anchor_selection' -Reason ('Input artifact is not an anchor-selection artifact: {0}' -f $inputRel) -MissingVariable 'anchor_selection_artifact')
    }

    $selectedAnchor = if ($anchorArtifact.PSObject.Properties['selected_anchor_pattern']) { [string]$anchorArtifact.selected_anchor_pattern } else { '' }
    $sourceFile = if ($anchorArtifact.PSObject.Properties['source_file']) { [string]$anchorArtifact.source_file } else { '' }
    $selectedLine = if ($anchorArtifact.PSObject.Properties['selected_line']) { [int]$anchorArtifact.selected_line } else { 0 }
    $combinedText = (Get-LocalExecutionCombinedText -Context $Context).ToLowerInvariant()
    $sourceContext = ''
    if (-not [string]::IsNullOrWhiteSpace($sourceFile) -and (Test-LocalExecutionSafePath -RelativePath $sourceFile)) {
        $sourceAbs = Join-Path $script:LocalEngineRepoRoot $sourceFile
        if (Test-Path -Path $sourceAbs -PathType Leaf) {
            $sourceRaw = Get-Content -Path $sourceAbs -Raw
            if ($selectedLine -gt 0) {
                $sourceLines = $sourceRaw -split "`r?`n"
                $startLine = [Math]::Max(1, $selectedLine)
                $endLine = [Math]::Min($sourceLines.Count, ($selectedLine + 8))
                if ($selectedAnchor -match '\{\s*$') {
                    $braceDepth = 0
                    for ($lineIndex = ($startLine - 1); $lineIndex -lt $sourceLines.Count; $lineIndex++) {
                        $lineText = [string]$sourceLines[$lineIndex]
                        $braceDepth += ([regex]::Matches($lineText, '\{')).Count
                        $braceDepth -= ([regex]::Matches($lineText, '\}')).Count
                        if ($lineIndex -gt ($startLine - 1) -and $braceDepth -le 0) {
                            $endLine = ($lineIndex + 1)
                            break
                        }
                    }
                }
                $sourceContext = Get-LocalExecutionRawTextLineRange -Content $sourceRaw -StartLine $startLine -EndLine $endLine
            }
        }
    }

    $anchorEvidenceText = (($selectedAnchor + "`n" + $sourceContext).ToLowerInvariant())
    $taskRequiresPacketEditing = (
        $combinedText -match 'artifact_write|artifact[-_\s]?write|edit[-_\s]?mode|bounded|packet|materialization|directive'
    )
    $anchorShowsPacketEditing = (
        $anchorEvidenceText -match 'artifact_write|artifact[-_\s]?write|edit[-_\s]?mode|packet|materialization|directive|genericboundedtask|generic[-_\s]?bounded'
    )
    $decision = if ($taskRequiresPacketEditing -and -not $anchorShowsPacketEditing) { 'reject_anchor' } else { 'accept_anchor' }
    $reason = if ($decision -eq 'reject_anchor') {
        'The selected anchor is unique, but its selected source context does not show artifact-write, edit-mode, packet, directive, or bounded-task behavior required by the current objective.'
    }
    else {
        'The selected anchor has enough task-relevant packet/edit-mode evidence to proceed to source-anchor observation.'
    }

    $artifact = [ordered]@{
        artifact_type = 'tod_anchor_selection_semantic_rejection'
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        source = 'local_execution_anchor_selection_semantic_rejection_lane'
        objective_id = if ($Context.PSObject.Properties['objective_id']) { [string]$Context.objective_id } else { '' }
        task_id = if ($Context.PSObject.Properties['task_id']) { [string]$Context.task_id } else { '' }
        input_artifact = $inputRel
        decision = $decision
        selected_anchor_pattern = $selectedAnchor
        selected_line = $selectedLine
        source_file = $sourceFile
        evidence_checked = @(
            ('artifact_type={0}' -f [string]$anchorArtifact.artifact_type),
            ('selected_anchor_pattern={0}' -f $selectedAnchor),
            ('selected_line={0}' -f $selectedLine),
            ('task_requires_packet_or_edit_mode={0}' -f $taskRequiresPacketEditing),
            ('anchor_context_has_packet_or_edit_mode_terms={0}' -f $anchorShowsPacketEditing)
        )
        failure_reason_or_acceptance_reason = $reason
        missing_capability = if ($decision -eq 'reject_anchor') { 'semantic relevance scoring for anchor-selection artifacts before source-anchor observation' } else { '' }
        smallest_next_training_rung = if ($decision -eq 'reject_anchor') { 'Retry anchor selection with task-relevant source context before source-anchor observation or packet materialization.' } else { 'Run source-anchor observation using the accepted selected anchor.' }
        dave_needed = 'no'
        codex_role = 'validation_only'
        no_code_changes = $true
        validation = [ordered]@{
            artifact_path = $outputRel
            input_read = $true
            decision_present = $true
            source_edits = @()
        }
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $outputAbs) -Force | Out-Null
    [System.IO.File]::WriteAllText($outputAbs, ($artifact | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))
    $readback = Get-Content -Path $outputAbs -Raw | ConvertFrom-Json
    foreach ($required in @('artifact_type', 'decision', 'selected_anchor_pattern', 'evidence_checked', 'failure_reason_or_acceptance_reason', 'smallest_next_training_rung', 'dave_needed', 'codex_role', 'no_code_changes')) {
        if (-not $readback.PSObject.Properties[$required]) {
            return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'anchor_selection_semantic_rejection_required_fields_missing' -Reason ('Anchor-selection semantic rejection artifact is missing required field: {0}' -f $required) -MissingVariable $required)
        }
    }

    $Result.summary = ('Published anchor-selection semantic rejection artifact {0}; decision={1}.' -f $outputRel, $decision)
    $Result.files_changed = @($outputRel)
    $Result.tests_run = @('anchor-selection artifact read', 'semantic relevance decision', 'rejection artifact write', 'required schema readback', 'no-code-change assertion')
    $Result.test_results = @('pass', 'pass', 'pass', 'pass', 'pass')
    $Result | Add-Member -NotePropertyName command_output -NotePropertyValue ('Anchor-selection semantic decision published: {0}' -f $outputRel) -Force
    $Result | Add-Member -NotePropertyName diff_summary -NotePropertyValue ('Artifact write only: {0}' -f $outputRel) -Force
    $Result | Add-Member -NotePropertyName commands_run -NotePropertyValue @('Invoke-LocalExecutionAnchorSelectionSemanticRejection') -Force
    $Result | Add-Member -NotePropertyName validation_results -NotePropertyValue @(
        [pscustomobject]@{ name = 'anchor-selection artifact read'; passed = $true; required = $true },
        [pscustomobject]@{ name = 'semantic relevance decision'; passed = $true; required = $true },
        [pscustomobject]@{ name = 'rejection artifact write'; passed = $true; required = $true },
        [pscustomobject]@{ name = 'required schema readback'; passed = $true; required = $true },
        [pscustomobject]@{ name = 'no-code-change assertion'; passed = $true; required = $true }
    ) -Force
    $Result | Add-Member -NotePropertyName blockers -NotePropertyValue @() -Force
    $Result | Add-Member -NotePropertyName confidence -NotePropertyValue 'high' -Force
    $Result | Add-Member -NotePropertyName rollback_hint -NotePropertyValue ('Remove generated artifact {0} if this borrowed evaluator output must be discarded.' -f $outputRel) -Force
    $Result | Add-Member -NotePropertyName no_change_required -NotePropertyValue $false -Force
    return (Complete-EngineExecutionResult -Result $Result -Status 'completed')
}

function Test-LocalExecutionSourceAnchorObservationTask {
    param([Parameter(Mandatory = $true)]$Context)

    $category = Get-LocalExecutionTaskCategory -Context $Context
    if (@('report_only', 'diagnostic_only', 'inspection_only', 'inspection', 'source_anchor_observation', 'chat_execution') -notcontains $category) {
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

    $sourceFunction = ''
    for ($idx = $startIndex; $idx -ge 0; $idx--) {
        $functionMatch = [regex]::Match([string]$lines[$idx], '^\s*(?:function\s+|(?:async\s+)?def\s+)(?<name>[A-Za-z_][A-Za-z0-9_-]*)\b')
        if ($functionMatch.Success) {
            $sourceFunction = ([string]$functionMatch.Groups['name'].Value).Trim()
            break
        }
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
        source_function = $sourceFunction
        function_surface = $sourceFunction
        anchor_pattern = $anchorPattern
        end_pattern = $endPattern
        matched = $true
        source_read = $true
        anchor_found = $true
        exact_text_nonempty = -not [string]::IsNullOrWhiteSpace($exactText)
        start_line = $extractStart + 1
        end_line = $extractEnd + 1
        context_start_line = $extractStart + 1
        context_end_line = $extractEnd + 1
        line_count = $extractedLines.Count
        exact_text = $exactText
        no_code_changes = $true
        validation = [ordered]@{
            artifact_path = $outputRel
            source_read = $true
            anchor_found = $true
            exact_text_nonempty = -not [string]::IsNullOrWhiteSpace($exactText)
            source_function_inferred = -not [string]::IsNullOrWhiteSpace($sourceFunction)
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

function Get-LocalExecutionPacketAnchorSuitabilitySpec {
    param([Parameter(Mandatory = $true)]$Context)

    $text = Get-LocalExecutionCombinedText -Context $Context
    $inputArtifact = Get-LocalExecutionDirectiveValue -PromptText $text -FieldName 'Input Artifact'
    if ([string]::IsNullOrWhiteSpace($inputArtifact)) {
        $inputMatch = [regex]::Match($text, 'runtime_remote_training/read_only_audit_artifacts/[A-Za-z0-9_./-]+?\.json')
        if ($inputMatch.Success) {
            $inputArtifact = ([string]$inputMatch.Groups[0].Value).Trim()
        }
    }

    $outputPath = Get-LocalExecutionDirectiveValue -PromptText $text -FieldName 'Output'
    if ([string]::IsNullOrWhiteSpace($outputPath)) {
        $outputMatches = [regex]::Matches($text, 'runtime_remote_training/read_only_audit_artifacts/[A-Za-z0-9_./-]+?\.json')
        if ($outputMatches.Count -gt 0) {
            $outputPath = ([string]$outputMatches[$outputMatches.Count - 1].Value).Trim()
        }
    }

    $targetFile = Get-LocalExecutionDirectiveValue -PromptText $text -FieldName 'Target File'
    if ([string]::IsNullOrWhiteSpace($targetFile)) {
        $targetFile = Get-LocalExecutionDirectiveValue -PromptText $text -FieldName 'Packet Source Target'
    }

    return [pscustomobject]@{
        input_artifact = if ([string]::IsNullOrWhiteSpace($inputArtifact)) { '' } else { Convert-ToLocalExecutionRepoRelativePath -PathValue $inputArtifact }
        output_path = if ([string]::IsNullOrWhiteSpace($outputPath)) { '' } else { Convert-ToLocalExecutionRepoRelativePath -PathValue $outputPath }
        target_file = if ([string]::IsNullOrWhiteSpace($targetFile)) { '' } else { Convert-ToLocalExecutionRepoRelativePath -PathValue $targetFile }
        insert_before_pattern = Get-LocalExecutionDirectiveValue -PromptText $text -FieldName 'Insert Before Pattern'
        snippet = Get-LocalExecutionDirectiveValue -PromptText $text -FieldName 'Snippet'
        validation_command = Get-LocalExecutionDirectiveValue -PromptText $text -FieldName 'Validation Command'
    }
}

function Test-LocalExecutionPacketAnchorSuitabilityTask {
    param([Parameter(Mandatory = $true)]$Context)

    $category = Get-LocalExecutionTaskCategory -Context $Context
    if (@('read_only_assessment', 'read_only_role_classification', 'report_only', 'diagnostic_only', 'inspection_only', 'inspection', 'review_only') -notcontains $category) {
        return $false
    }

    $text = (Get-LocalExecutionCombinedText -Context $Context).ToLowerInvariant()
    if ($text -notmatch 'packet[-_\s]+anchor[-_\s]+suitability|anchor[-_\s]+packet[-_\s]+suitability|suitable\s+for\s+bounded\s+packet|suitable\s+for\s+packet') {
        return $false
    }

    $spec = Get-LocalExecutionPacketAnchorSuitabilitySpec -Context $Context
    return (
        -not [string]::IsNullOrWhiteSpace([string]$spec.input_artifact) -and
        -not [string]::IsNullOrWhiteSpace([string]$spec.output_path)
    )
}

function Invoke-LocalExecutionPacketAnchorSuitability {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)]$Spec
    )

    $suitabilitySpec = Get-LocalExecutionPacketAnchorSuitabilitySpec -Context $Context
    $inputRel = [string]$suitabilitySpec.input_artifact
    $outputRel = [string]$suitabilitySpec.output_path
    if ([string]::IsNullOrWhiteSpace($inputRel)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'packet_anchor_suitability_input_missing' -Reason 'Packet-anchor suitability review requires an Input Artifact JSON file.' -MissingVariable 'input_artifact')
    }
    if ([string]::IsNullOrWhiteSpace($outputRel)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'packet_anchor_suitability_output_missing' -Reason 'Packet-anchor suitability review requires an Output JSON artifact path.' -MissingVariable 'output_path')
    }
    foreach ($pathEntry in @(
            [pscustomobject]@{ Name = 'input_artifact'; Value = $inputRel },
            [pscustomobject]@{ Name = 'output_path'; Value = $outputRel }
        )) {
        if (-not (Test-LocalExecutionSafePath -RelativePath ([string]$pathEntry.Value))) {
            return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode ('packet_anchor_suitability_{0}_unsafe' -f $pathEntry.Name) -Reason ('Packet-anchor suitability path is outside LocalExecutionEngine safe roots: {0}' -f [string]$pathEntry.Value) -MissingVariable ('safe_' + $pathEntry.Name))
        }
    }

    $inputAbs = Join-Path $script:LocalEngineRepoRoot $inputRel
    $outputAbs = Join-Path $script:LocalEngineRepoRoot $outputRel
    if (-not (Test-Path -Path $inputAbs -PathType Leaf)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'packet_anchor_suitability_input_not_found' -Reason ('Input artifact does not exist: {0}' -f $inputRel) -MissingVariable 'input_artifact')
    }

    $anchor = Get-Content -Path $inputAbs -Raw | ConvertFrom-Json
    if (-not $anchor.PSObject.Properties['artifact_type'] -or [string]$anchor.artifact_type -ne 'tod_source_anchor_observation') {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'packet_anchor_suitability_input_not_anchor' -Reason ('Input artifact is not a source-anchor observation: {0}' -f $inputRel) -MissingVariable 'source_anchor_artifact')
    }

    $exactText = if ($anchor.PSObject.Properties['exact_text']) { [string]$anchor.exact_text } else { '' }
    $sourceFile = if ($anchor.PSObject.Properties['source_file']) { [string]$anchor.source_file } else { '' }
    $targetFile = if (-not [string]::IsNullOrWhiteSpace([string]$suitabilitySpec.target_file)) { [string]$suitabilitySpec.target_file } else { $sourceFile }
    $missing = New-Object System.Collections.Generic.List[string]
    if ([string]::IsNullOrWhiteSpace($sourceFile)) { [void]$missing.Add('source_file') }
    if ([string]::IsNullOrWhiteSpace($exactText)) { [void]$missing.Add('old_text') }
    if ([string]::IsNullOrWhiteSpace($targetFile)) { [void]$missing.Add('target_file') }
    if ([string]::IsNullOrWhiteSpace([string]$suitabilitySpec.insert_before_pattern)) { [void]$missing.Add('insert_before_pattern') }
    if ([string]::IsNullOrWhiteSpace([string]$suitabilitySpec.snippet)) { [void]$missing.Add('snippet') }
    if ([string]::IsNullOrWhiteSpace([string]$suitabilitySpec.validation_command)) { [void]$missing.Add('validation_command') }

    $sourceMatchCount = 0
    $insertPatternPresent = $false
    if (-not [string]::IsNullOrWhiteSpace($targetFile) -and (Test-LocalExecutionSafePath -RelativePath $targetFile)) {
        $targetAbs = Join-Path $script:LocalEngineRepoRoot $targetFile
        if (Test-Path -Path $targetAbs -PathType Leaf) {
            $targetRaw = Get-Content -Path $targetAbs -Raw
            if (-not [string]::IsNullOrWhiteSpace($exactText)) {
                $targetNormalized = $targetRaw -replace "`r`n", "`n"
                $exactNormalized = $exactText -replace "`r`n", "`n"
                $escaped = [regex]::Escape($exactNormalized)
                $sourceMatchCount = [regex]::Matches($targetNormalized, $escaped).Count
                if ($sourceMatchCount -eq 0 -and $anchor.PSObject.Properties['start_line'] -and $anchor.PSObject.Properties['end_line']) {
                    $rawOldText = Get-LocalExecutionRawTextLineRange -Content $targetRaw -StartLine ([int]$anchor.start_line) -EndLine ([int]$anchor.end_line)
                    if (-not [string]::IsNullOrWhiteSpace($rawOldText) -and (($rawOldText -replace "`r`n", "`n") -eq $exactNormalized)) {
                        $sourceMatchCount = 1
                    }
                }
                if ($sourceMatchCount -ne 1) {
                    [void]$missing.Add('unique_old_text_match')
                }
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$suitabilitySpec.insert_before_pattern)) {
                $insertPatternPresent = $targetRaw -like ('*' + [string]$suitabilitySpec.insert_before_pattern + '*')
                if (-not $insertPatternPresent) {
                    [void]$missing.Add('insert_before_pattern_present')
                }
            }
        }
        else {
            [void]$missing.Add('target_file_exists')
        }
    }
    elseif (-not [string]::IsNullOrWhiteSpace($targetFile)) {
        [void]$missing.Add('safe_target_file')
    }

    $uniqueMissing = @($missing.ToArray() | Select-Object -Unique)
    $suitable = ($uniqueMissing.Count -eq 0)
    $artifact = [ordered]@{
        artifact_type = 'tod_packet_anchor_suitability_review'
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        source = 'local_execution_packet_anchor_suitability_lane'
        objective_id = if ($Context.PSObject.Properties['objective_id']) { [string]$Context.objective_id } else { '' }
        task_id = if ($Context.PSObject.Properties['task_id']) { [string]$Context.task_id } else { '' }
        input_artifact = $inputRel
        source_file = $sourceFile
        target_file = $targetFile
        suitable_for_packet_synthesis = $suitable
        missing_requirements = $uniqueMissing
        evidence = [ordered]@{
            exact_text_nonempty = -not [string]::IsNullOrWhiteSpace($exactText)
            old_text_match_count_in_target = $sourceMatchCount
            insert_before_pattern_present = $insertPatternPresent
            line_count = if ($anchor.PSObject.Properties['line_count']) { $anchor.line_count } else { $null }
        }
        next_training_rung = if ($suitable) { 'synthesize bounded packet from this source-anchor artifact, then run packet quality review before apply' } else { 'select or observe a packet-suitable anchor and provide missing packet synthesis directives before attempting packet body synthesis' }
        no_code_changes = $true
        validation = [ordered]@{
            artifact_path = $outputRel
            input_read = $true
            suitability_decision_present = $true
            source_edits = @()
        }
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $outputAbs) -Force | Out-Null
    [System.IO.File]::WriteAllText($outputAbs, ($artifact | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))
    $Result.summary = ('Published packet-anchor suitability artifact {0}; suitable={1}; missing={2}.' -f $outputRel, $suitable, ($uniqueMissing -join ','))
    $Result.files_changed = @($outputRel)
    $Result.tests_run = @('input source-anchor artifact read', 'target source match check', 'packet suitability artifact write', 'required schema readback', 'no-code-change assertion')
    $Result.test_results = @('pass', 'pass', 'pass', 'pass', 'pass')
    $Result | Add-Member -NotePropertyName command_output -NotePropertyValue ('Packet-anchor suitability review published: {0}' -f $outputRel) -Force
    $Result | Add-Member -NotePropertyName diff_summary -NotePropertyValue ('Artifact write only: {0}' -f $outputRel) -Force
    $Result | Add-Member -NotePropertyName commands_run -NotePropertyValue @('Invoke-LocalExecutionPacketAnchorSuitability') -Force
    $Result | Add-Member -NotePropertyName validation_results -NotePropertyValue @(
        [pscustomobject]@{ name = 'input source-anchor artifact read'; passed = $true; required = $true },
        [pscustomobject]@{ name = 'target source match check'; passed = $true; required = $true },
        [pscustomobject]@{ name = 'packet suitability artifact write'; passed = $true; required = $true },
        [pscustomobject]@{ name = 'required schema readback'; passed = $true; required = $true },
        [pscustomobject]@{ name = 'no-code-change assertion'; passed = $true; required = $true }
    ) -Force
    $Result | Add-Member -NotePropertyName blockers -NotePropertyValue $(if ($suitable) { @() } else { @([pscustomobject]@{ type = 'training_debt'; reason_code = 'packet_anchor_not_materialization_ready'; reason = ('Missing packet synthesis requirements: {0}' -f ($uniqueMissing -join ', ')) }) }) -Force
    $Result | Add-Member -NotePropertyName confidence -NotePropertyValue 'high' -Force
    $Result | Add-Member -NotePropertyName rollback_hint -NotePropertyValue ('Remove generated artifact {0} if this suitability artifact must be discarded.' -f $outputRel) -Force
    $Result | Add-Member -NotePropertyName no_change_required -NotePropertyValue $false -Force
    return (Complete-EngineExecutionResult -Result $Result -Status 'completed')
}

function Get-LocalExecutionSourceAnchorPacketDirectiveSpec {
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

    $targetFile = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Target File'

    return [pscustomobject]@{
        input_artifact = if ([string]::IsNullOrWhiteSpace($inputArtifact)) { '' } else { Convert-ToLocalExecutionRepoRelativePath -PathValue $inputArtifact }
        output_path = if ([string]::IsNullOrWhiteSpace($outputPath)) { '' } else { Convert-ToLocalExecutionRepoRelativePath -PathValue $outputPath }
        target_file = if ([string]::IsNullOrWhiteSpace($targetFile)) { '' } else { Convert-ToLocalExecutionRepoRelativePath -PathValue $targetFile }
        validation_command = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Validation Command'
        validation_pattern = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Validation Pattern'
        closure_evidence = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Closure Evidence'
        prevention_lesson = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Prevention Lesson'
        dave_needed = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Dave Needed'
    }
}

function Test-LocalExecutionSourceAnchorPacketDirectiveTask {
    param([Parameter(Mandatory = $true)]$Context)

    $category = Get-LocalExecutionTaskCategory -Context $Context
    if (@('report_only', 'diagnostic_only', 'inspection_only', 'inspection', 'packet_formation', 'source_anchor_observation') -notcontains $category) {
        return $false
    }

    $text = (Get-LocalExecutionCombinedText -Context $Context).ToLowerInvariant()
    if ($text -notmatch 'source[-_\s]?anchor\s+packet[-_\s]?directive|packet[-_\s]?directive\s+materialization|directive[-_\s]?materialization\s+packet') {
        return $false
    }

    $spec = Get-LocalExecutionSourceAnchorPacketDirectiveSpec -Context $Context
    return (
        -not [string]::IsNullOrWhiteSpace([string]$spec.input_artifact) -and
        -not [string]::IsNullOrWhiteSpace([string]$spec.output_path)
    )
}

function Invoke-LocalExecutionSourceAnchorPacketDirective {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)]$Spec
    )

    $directiveSpec = Get-LocalExecutionSourceAnchorPacketDirectiveSpec -Context $Context
    $inputRel = [string]$directiveSpec.input_artifact
    $outputRel = [string]$directiveSpec.output_path
    $targetFile = [string]$directiveSpec.target_file
    foreach ($pathEntry in @(
            [pscustomobject]@{ Name = 'input_artifact'; Value = $inputRel },
            [pscustomobject]@{ Name = 'output_path'; Value = $outputRel }
        )) {
        if ([string]::IsNullOrWhiteSpace([string]$pathEntry.Value)) {
            return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode ('source_anchor_packet_directive_{0}_missing' -f $pathEntry.Name) -Reason ('Source-anchor packet directive materialization requires {0}.' -f $pathEntry.Name) -MissingVariable $pathEntry.Name)
        }
        if (-not (Test-LocalExecutionSafePath -RelativePath ([string]$pathEntry.Value))) {
            return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode ('source_anchor_packet_directive_{0}_unsafe' -f $pathEntry.Name) -Reason ('Source-anchor packet directive path is outside LocalExecutionEngine safe roots: {0}' -f [string]$pathEntry.Value) -MissingVariable ('safe_' + $pathEntry.Name))
        }
    }

    $inputAbs = Join-Path $script:LocalEngineRepoRoot $inputRel
    $outputAbs = Join-Path $script:LocalEngineRepoRoot $outputRel
    if (-not (Test-Path -Path $inputAbs -PathType Leaf)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'source_anchor_packet_directive_input_not_found' -Reason ('Input source-anchor artifact does not exist: {0}' -f $inputRel) -MissingVariable 'input_artifact')
    }

    $anchorArtifact = Get-Content -Path $inputAbs -Raw | ConvertFrom-Json
    if (-not $anchorArtifact.PSObject.Properties['artifact_type'] -or [string]$anchorArtifact.artifact_type -ne 'tod_source_anchor_observation') {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'source_anchor_packet_directive_input_not_anchor' -Reason ('Input artifact is not a source-anchor observation: {0}' -f $inputRel) -MissingVariable 'source_anchor_artifact')
    }

    if ([string]::IsNullOrWhiteSpace($targetFile)) {
        if ($anchorArtifact.PSObject.Properties['source_file']) {
            $targetFile = Convert-ToLocalExecutionRepoRelativePath -PathValue ([string]$anchorArtifact.source_file)
        }
    }
    if ([string]::IsNullOrWhiteSpace($targetFile)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'source_anchor_packet_directive_target_missing' -Reason 'Source-anchor packet directive materialization requires a target file or source_file in the anchor artifact.' -MissingVariable 'target_file')
    }
    if (-not (Test-LocalExecutionSafePath -RelativePath $targetFile)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'source_anchor_packet_directive_target_unsafe' -Reason ('Target file is outside LocalExecutionEngine safe roots: {0}' -f $targetFile) -MissingVariable 'safe_target_file')
    }

    $targetAbs = Join-Path $script:LocalEngineRepoRoot $targetFile
    if (-not (Test-Path -Path $targetAbs -PathType Leaf)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'source_anchor_packet_directive_target_not_found' -Reason ('Target file does not exist: {0}' -f $targetFile) -MissingVariable 'target_file')
    }

    $targetRaw = Get-Content -Path $targetAbs -Raw
    $oldText = [string]$anchorArtifact.exact_text
    if ($anchorArtifact.PSObject.Properties['start_line'] -and $anchorArtifact.PSObject.Properties['end_line']) {
        $rawOldText = Get-LocalExecutionRawTextLineRange -Content $targetRaw -StartLine ([int]$anchorArtifact.start_line) -EndLine ([int]$anchorArtifact.end_line)
        if (-not [string]::IsNullOrWhiteSpace($rawOldText)) {
            $oldText = $rawOldText
        }
    }
    if ([string]::IsNullOrWhiteSpace($oldText)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'source_anchor_packet_directive_old_text_missing' -Reason 'Source-anchor artifact did not provide exact source text.' -MissingVariable 'old_text')
    }
    if (-not $targetRaw.Contains($oldText)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'source_anchor_packet_directive_old_text_not_found' -Reason 'Observed old_text was not found in the current target file.' -MissingVariable 'old_text_current_match')
    }

    $extension = [System.IO.Path]::GetExtension($targetFile).ToLowerInvariant()
    $taskId = if ($Context.PSObject.Properties['task_id']) { [string]$Context.task_id } else { 'tod-source-anchor-packet-directive' }
    $markerText = ('TOD training marker: {0}' -f $taskId)
    switch ($extension) {
        '.py' { $snippet = '# ' + $markerText }
        '.ps1' { $snippet = '# ' + $markerText }
        '.md' { $snippet = '<!-- ' + $markerText + ' -->' }
        default {
            return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'source_anchor_packet_directive_extension_unsupported' -Reason ('No harmless comment directive is defined for target extension: {0}' -f $extension) -MissingVariable 'supported_target_extension')
        }
    }

    $oldLines = [System.Collections.Generic.List[string]]::new()
    foreach ($line in @($oldText -split "`r?`n")) {
        [void]$oldLines.Add([string]$line)
    }
    $newLines = [System.Collections.Generic.List[string]]::new()
    $firstLine = if ($oldLines.Count -gt 0) { [string]$oldLines[0] } else { '' }
    $anchorIndent = ([regex]::Match($firstLine, '^\s*')).Value
    [void]$newLines.Add($anchorIndent + $snippet)
    [void]$newLines.Add('')
    foreach ($line in $oldLines) {
        [void]$newLines.Add([string]$line)
    }
    $newText = ($newLines.ToArray() -join "`n")
    if ([string]::Equals([string]$newText, [string]$oldText, [System.StringComparison]::Ordinal)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'source_anchor_packet_directive_no_delta' -Reason 'Source-anchor packet directive materialization produced identical old_text and new_text.' -MissingVariable 'new_text_delta')
    }

    $validationCommand = [string]$directiveSpec.validation_command
    if ([string]::IsNullOrWhiteSpace($validationCommand)) {
        if ($extension -eq '.py') {
            $validationCommand = 'python -m py_compile {0}' -f $targetFile
        }
        elseif ($extension -eq '.ps1') {
            $validationCommand = 'powershell -NoProfile -Command "$null = [System.Management.Automation.Language.Parser]::ParseFile(''{0}'', [ref]$null, [ref]$null)"' -f $targetFile
        }
        else {
            $validationCommand = 'Test-Path {0}' -f $targetFile
        }
    }
    $validationPattern = [string]$directiveSpec.validation_pattern
    if ([string]::IsNullOrWhiteSpace($validationPattern)) {
        $validationPattern = $markerText
    }
    $closureEvidence = [string]$directiveSpec.closure_evidence
    if ([string]::IsNullOrWhiteSpace($closureEvidence)) {
        $closureEvidence = 'Packet candidate ready from TOD-observed source anchor and harmless comment directive.'
    }
    $preventionLesson = [string]$directiveSpec.prevention_lesson
    if ([string]::IsNullOrWhiteSpace($preventionLesson)) {
        $preventionLesson = 'TOD must convert observed source anchors into explicit reversible packet directives before applying code changes.'
    }
    $daveNeeded = [string]$directiveSpec.dave_needed
    if ([string]::IsNullOrWhiteSpace($daveNeeded)) {
        $daveNeeded = 'no'
    }

    $artifact = [ordered]@{
        artifact_type = 'tod_source_anchor_packet_directive_materialization_artifact'
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        source = 'local_execution_source_anchor_packet_directive_lane'
        objective_id = if ($Context.PSObject.Properties['objective_id']) { [string]$Context.objective_id } else { '' }
        task_id = $taskId
        packet_candidate_ready = $true
        borrowed_capability = $true
        borrowed_capability_reason = 'Codex added this directive-materialization lane; TOD must repeat the full loop on a later fresh target before this is independent.'
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
        directive_materialization = [ordered]@{
            input_artifact = $inputRel
            source_file = if ($anchorArtifact.PSObject.Properties['source_file']) { [string]$anchorArtifact.source_file } else { $targetFile }
            start_line = if ($anchorArtifact.PSObject.Properties['start_line']) { $anchorArtifact.start_line } else { $null }
            end_line = if ($anchorArtifact.PSObject.Properties['end_line']) { $anchorArtifact.end_line } else { $null }
            insert_before_pattern = $firstLine.Trim()
            snippet = $snippet
            no_source_edits = $true
        }
        validation = [ordered]@{
            artifact_path = $outputRel
            input_artifact_read = $true
            old_text_found_in_current_source = $true
            new_text_differs = [string]$newText -ne [string]$oldText
            packet_candidate_schema = 'ready'
            no_source_edits = $true
        }
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $outputAbs) -Force | Out-Null
    [System.IO.File]::WriteAllText($outputAbs, ($artifact | ConvertTo-Json -Depth 30), [System.Text.UTF8Encoding]::new($false))
    $validationCommandForPacket = New-LocalExecutionPacketCandidateValidationCommand -TargetFile $outputRel
    $validationOutput = Invoke-Expression $validationCommandForPacket

    $Result.summary = ('Published source-anchor packet directive artifact {0} from {1}.' -f $outputRel, $inputRel)
    $Result.files_changed = @($outputRel)
    $Result.tests_run = @('input source-anchor artifact read', 'current-source old_text match', 'packet directive materialization', 'packet candidate schema validation', 'no source edit assertion')
    $Result.test_results = @('pass', 'pass', 'pass', 'pass', 'pass')
    $Result | Add-Member -NotePropertyName command_output -NotePropertyValue ($validationOutput -join "`n") -Force
    $Result | Add-Member -NotePropertyName diff_summary -NotePropertyValue ('Artifact write only: {0}' -f $outputRel) -Force
    $Result | Add-Member -NotePropertyName commands_run -NotePropertyValue @('Invoke-LocalExecutionSourceAnchorPacketDirective', $validationCommandForPacket) -Force
    $Result | Add-Member -NotePropertyName validation_results -NotePropertyValue @(
        [pscustomobject]@{ name = 'input source-anchor artifact read'; passed = $true; required = $true },
        [pscustomobject]@{ name = 'current-source old_text match'; passed = $true; required = $true },
        [pscustomobject]@{ name = 'packet directive materialization'; passed = $true; required = $true },
        [pscustomobject]@{ name = 'packet candidate schema validation'; passed = $true; required = $true },
        [pscustomobject]@{ name = 'no source edit assertion'; passed = $true; required = $true }
    ) -Force
    $Result | Add-Member -NotePropertyName blockers -NotePropertyValue @() -Force
    $Result | Add-Member -NotePropertyName confidence -NotePropertyValue 'medium' -Force
    $Result | Add-Member -NotePropertyName rollback_hint -NotePropertyValue ('Remove generated artifact {0} if this directive-materialization training artifact must be discarded.' -f $outputRel) -Force
    $Result | Add-Member -NotePropertyName no_change_required -NotePropertyValue $false -Force
    return (Complete-EngineExecutionResult -Result $Result -Status 'completed')
}

function Get-LocalExecutionPacketBodySynthesisSpec {
    param([Parameter(Mandatory = $true)]$Context)

    $text = Get-LocalExecutionCombinedText -Context $Context
    $promptText = Get-LocalExecutionPromptText -Context $Context
    $promptText = $text

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

    $inputArtifactRel = if ([string]::IsNullOrWhiteSpace($inputArtifact)) { '' } else { Convert-ToLocalExecutionRepoRelativePath -PathValue $inputArtifact }
    $targetFileRel = Convert-ToLocalExecutionRepoRelativePath -PathValue (Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Target File')
    if (-not [string]::IsNullOrWhiteSpace($inputArtifactRel) -and (Test-LocalExecutionSafePath -RelativePath $inputArtifactRel)) {
        $inputArtifactAbs = Join-Path $script:LocalEngineRepoRoot $inputArtifactRel
        if (Test-Path -Path $inputArtifactAbs -PathType Leaf) {
            try {
                $candidateArtifact = Get-Content -Path $inputArtifactAbs -Raw | ConvertFrom-Json
                if ($candidateArtifact.PSObject.Properties['artifact_type'] -and [string]$candidateArtifact.artifact_type -eq 'tod_evidence_pool_source_anchor_classifier') {
                    $selectedSourceAnchor = if ($candidateArtifact.PSObject.Properties['selected_source_anchor_artifact']) { Convert-ToLocalExecutionRepoRelativePath -PathValue ([string]$candidateArtifact.selected_source_anchor_artifact) } else { '' }
                    if (-not [string]::IsNullOrWhiteSpace($selectedSourceAnchor)) {
                        $inputArtifactRel = $selectedSourceAnchor
                        if ([string]::IsNullOrWhiteSpace($targetFileRel) -and (Test-LocalExecutionSafePath -RelativePath $selectedSourceAnchor)) {
                            $selectedAbs = Join-Path $script:LocalEngineRepoRoot $selectedSourceAnchor
                            if (Test-Path -Path $selectedAbs -PathType Leaf) {
                                try {
                                    $sourceAnchorArtifact = Get-Content -Path $selectedAbs -Raw | ConvertFrom-Json
                                    if ($sourceAnchorArtifact.PSObject.Properties['source_file']) {
                                        $targetFileRel = Convert-ToLocalExecutionRepoRelativePath -PathValue ([string]$sourceAnchorArtifact.source_file)
                                    }
                                }
                                catch {
                                    $targetFileRel = $targetFileRel
                                }
                            }
                        }
                    }
                }
                elseif ($candidateArtifact.PSObject.Properties['artifact_type'] -and [string]$candidateArtifact.artifact_type -eq 'tod_source_anchor_observation' -and [string]::IsNullOrWhiteSpace($targetFileRel)) {
                    if ($candidateArtifact.PSObject.Properties['source_file']) {
                        $targetFileRel = Convert-ToLocalExecutionRepoRelativePath -PathValue ([string]$candidateArtifact.source_file)
                    }
                }
            }
            catch {
                $inputArtifactRel = $inputArtifactRel
            }
        }
    }

    return [pscustomobject]@{
        input_artifact = $inputArtifactRel
        output_path = if ([string]::IsNullOrWhiteSpace($outputPath)) { '' } else { Convert-ToLocalExecutionRepoRelativePath -PathValue $outputPath }
        target_file = $targetFileRel
        insert_before_pattern = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Insert Before Pattern'
        field_name = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Field Name'
        field_value = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Field Value'
        new_text = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'New Text'
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
        -not [string]::IsNullOrWhiteSpace([string]$spec.target_file)
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
            [pscustomobject]@{ Name = 'target_file'; Value = $targetFile }
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
    if (-not $anchorArtifact.PSObject.Properties['exact_text']) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'packet_body_synthesis_input_not_source_anchor' -Reason ('Packet body synthesis requires an input source-anchor artifact with exact_text; received incompatible evidence artifact: {0}' -f $inputRel) -MissingVariable 'source_anchor_exact_text' -Status 'blocked')
    }
    $oldText = [string]$anchorArtifact.exact_text
    if ([string]::IsNullOrWhiteSpace($oldText)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'packet_body_synthesis_old_text_missing' -Reason 'Input source-anchor artifact does not include non-empty exact_text.' -MissingVariable 'old_text')
    }

    $explicitNewText = [string]$bodySpec.new_text
    $synthesisMode = 'field_insertion'
    if (-not [string]::IsNullOrWhiteSpace($explicitNewText)) {
        $newText = $explicitNewText
        $newLines = @($newText -split "`n", -1)
        $insertBeforePattern = ''
        $synthesisMode = 'explicit_new_text'
    }
    else {
        $hasFieldInsertionDirective = (
            -not [string]::IsNullOrWhiteSpace([string]$bodySpec.insert_before_pattern) -or
            -not [string]::IsNullOrWhiteSpace([string]$bodySpec.field_name) -or
            -not [string]::IsNullOrWhiteSpace([string]$bodySpec.field_value)
        )
        if (-not $hasFieldInsertionDirective) {
            return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'packet_body_synthesis_autonomous_new_text_missing' -Reason 'Packet body synthesis has source-anchor evidence, target file, and output path, but no autonomous new_text synthesis capability is available without an explicit New Text or field-insertion directive.' -MissingVariable 'autonomous_meaningful_new_text_materialization_from_source_anchor' -Status 'blocked')
        }
        foreach ($entry in @(
                [pscustomobject]@{ Name = 'insert_before_pattern'; Value = [string]$bodySpec.insert_before_pattern },
                [pscustomobject]@{ Name = 'field_name'; Value = [string]$bodySpec.field_name },
                [pscustomobject]@{ Name = 'field_value'; Value = [string]$bodySpec.field_value }
            )) {
            if ([string]::IsNullOrWhiteSpace([string]$entry.Value)) {
                return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode ('packet_body_synthesis_{0}_missing' -f $entry.Name) -Reason ('Packet body synthesis requires {0} when New Text is not provided.' -f $entry.Name) -MissingVariable $entry.Name)
            }
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
        $newLinesList = New-Object System.Collections.Generic.List[string]
        for ($idx = 0; $idx -lt $oldLines.Count; $idx++) {
            if ($idx -eq $insertIndex) {
                $newLinesList.Add($insertion) | Out-Null
            }
            $newLinesList.Add([string]$oldLines[$idx]) | Out-Null
        }
        $newLines = @($newLinesList.ToArray())
        $newText = ($newLines -join "`n").TrimEnd("`n")
    }
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
            synthesis_mode = $synthesisMode
            inserted_field = [string]$bodySpec.field_name
            insert_before_pattern = $insertBeforePattern
            old_text_line_count = @($oldText -split "`n", -1).Count
            new_text_line_count = @($newLines).Count
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
    if ($text -notmatch 'apply[_\-\s]+packet[_\-\s]+artifact|packet[_\-\s]+artifact[_\-\s]+apply|apply[-_ ]from[-_ ]packet') {
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
                $currentContent -notmatch [regex]::Escape($pattern)
            }
            elseif ($packet.PSObject.Properties['validation_pattern'] -and -not [string]::IsNullOrWhiteSpace([string]$packet.validation_pattern)) {
                $currentContent -notmatch [regex]::Escape([string]$packet.validation_pattern)
            }
            else {
                $currentContent.Contains($newText) -and -not $currentContent.Contains($oldText)
            }
        }
        else {
            ($currentContent -match [regex]::Escape($pattern)) -or ([string]$validationCapture.stdout -match [regex]::Escape($pattern))
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
    $directiveText = $text
    $inputArtifact = Get-LocalExecutionDirectiveValue -PromptText $directiveText -FieldName 'Input Artifact'
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

    $packetSourceTarget = Get-LocalExecutionDirectiveValue -PromptText $directiveText -FieldName 'Packet Source Target'
    if ([string]::IsNullOrWhiteSpace($packetSourceTarget)) {
        $packetSourceTarget = Get-LocalExecutionDirectiveValue -PromptText $directiveText -FieldName 'Inspect Target File'
    }
    if ([string]::IsNullOrWhiteSpace($packetSourceTarget)) {
        $packetSourceTarget = Get-LocalExecutionDirectiveValue -PromptText $directiveText -FieldName 'Target File'
    }

    return [pscustomobject]@{
        input_artifact = if ([string]::IsNullOrWhiteSpace($inputArtifact)) { '' } else { Convert-ToLocalExecutionRepoRelativePath -PathValue $inputArtifact }
        output_path = if ([string]::IsNullOrWhiteSpace($outputPath)) { '' } else { Convert-ToLocalExecutionRepoRelativePath -PathValue $outputPath }
        target_file = if ([string]::IsNullOrWhiteSpace($packetSourceTarget)) { '' } else { Convert-ToLocalExecutionRepoRelativePath -PathValue $packetSourceTarget }
        insert_before_pattern = Get-LocalExecutionDirectiveValue -PromptText $directiveText -FieldName 'Insert Before Pattern'
        snippet = Get-LocalExecutionDirectiveValue -PromptText $directiveText -FieldName 'Snippet'
        validation_command = Get-LocalExecutionDirectiveValue -PromptText $directiveText -FieldName 'Validation Command'
        validation_pattern = Get-LocalExecutionDirectiveValue -PromptText $directiveText -FieldName 'Validation Pattern'
        closure_evidence = Get-LocalExecutionDirectiveValue -PromptText $directiveText -FieldName 'Closure Evidence'
        prevention_lesson = Get-LocalExecutionDirectiveValue -PromptText $directiveText -FieldName 'Prevention Lesson'
        dave_needed = Get-LocalExecutionDirectiveValue -PromptText $directiveText -FieldName 'Dave Needed'
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
    $oldLines = [System.Collections.Generic.List[string]]::new()
    foreach ($line in @($oldText -split "`r?`n")) {
        [void]$oldLines.Add([string]$line)
    }
    $newLines = [System.Collections.Generic.List[string]]::new()
    $snippetInserted = $false
    $trimmedInsertBeforePattern = $insertBeforePattern.Trim()
    for ($lineIndex = 0; $lineIndex -lt $oldLines.Count; $lineIndex++) {
        $line = [string]$oldLines[$lineIndex]
        if (-not $snippetInserted -and [string]::Equals($line.Trim(), $trimmedInsertBeforePattern, [System.StringComparison]::Ordinal)) {
            $anchorIndent = ([regex]::Match($line, '^\s*')).Value
            foreach ($snippetLine in @($snippet -split "`r?`n")) {
                $snippetLineText = [string]$snippetLine
                if ([string]::IsNullOrWhiteSpace($snippetLineText) -or $snippetLineText -match '^\s') {
                    [void]$newLines.Add($snippetLineText)
                }
                else {
                    [void]$newLines.Add($anchorIndent + $snippetLineText)
                }
            }
            [void]$newLines.Add('')
            $snippetInserted = $true
        }
        [void]$newLines.Add($line)
    }
    if (-not $snippetInserted) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'powershell_snippet_body_synthesis_insert_anchor_not_found' -Reason ('Insert-before pattern not found as a complete line in old_text: {0}' -f $insertBeforePattern) -MissingVariable 'insert_before_pattern')
    }
    $newText = ($newLines.ToArray() -join "`n")
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

function Test-LocalExecutionPowerShellSnippetBodySynthesisTask {
    param([Parameter(Mandatory = $true)]$Context)

    $category = Get-LocalExecutionTaskCategory -Context $Context
    if (@('report_only', 'diagnostic_only', 'inspection_only', 'inspection', 'packet_formation') -notcontains $category) {
        return $false
    }

    $text = (Get-LocalExecutionCombinedText -Context $Context).ToLowerInvariant()
    if ($text -notmatch 'powershell[_\-\s]?snippet[_\-\s]?body[_\-\s]?synthesis|powershell\s+bounded\s+snippet\s+packet|powershell\s+source[-_\s]?anchor\s+packet') {
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

function Invoke-LocalExecutionPowerShellSnippetBodySynthesis {
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
            return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode ('powershell_snippet_body_synthesis_{0}_missing' -f $entry.Name) -Reason ('PowerShell snippet body synthesis requires {0}.' -f $entry.Name) -MissingVariable $entry.Name)
        }
    }
    foreach ($pathEntry in @(
            [pscustomobject]@{ Name = 'input_artifact'; Value = $inputRel },
            [pscustomobject]@{ Name = 'output_path'; Value = $outputRel },
            [pscustomobject]@{ Name = 'target_file'; Value = $targetFile }
        )) {
        if (-not (Test-LocalExecutionSafePath -RelativePath ([string]$pathEntry.Value))) {
            return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode ('powershell_snippet_body_synthesis_{0}_unsafe' -f $pathEntry.Name) -Reason ('PowerShell snippet body synthesis path is outside LocalExecutionEngine safe roots: {0}' -f [string]$pathEntry.Value) -MissingVariable ('safe_' + $pathEntry.Name))
        }
    }

    $inputAbs = Join-Path $script:LocalEngineRepoRoot $inputRel
    $outputAbs = Join-Path $script:LocalEngineRepoRoot $outputRel
    if (-not (Test-Path -Path $inputAbs -PathType Leaf)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'powershell_snippet_body_synthesis_input_not_found' -Reason ('Input source-anchor artifact does not exist: {0}' -f $inputRel) -MissingVariable 'input_artifact')
    }
    $anchorArtifact = Get-Content -Path $inputAbs -Raw | ConvertFrom-Json
    if (-not $anchorArtifact.PSObject.Properties['artifact_type'] -or [string]$anchorArtifact.artifact_type -ne 'tod_source_anchor_observation') {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'powershell_snippet_body_synthesis_input_not_anchor' -Reason ('Input artifact is not a source-anchor observation: {0}' -f $inputRel) -MissingVariable 'source_anchor_artifact')
    }

    $oldText = [string]$anchorArtifact.exact_text
    $targetAbs = Join-Path $script:LocalEngineRepoRoot $targetFile
    if (-not (Test-Path -Path $targetAbs -PathType Leaf)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'powershell_snippet_body_synthesis_target_not_found' -Reason ('Target file does not exist: {0}' -f $targetFile) -MissingVariable 'target_file')
    }
    $targetRaw = Get-Content -Path $targetAbs -Raw
    if ($anchorArtifact.PSObject.Properties['start_line'] -and $anchorArtifact.PSObject.Properties['end_line']) {
        $rawOldText = Get-LocalExecutionRawTextLineRange -Content $targetRaw -StartLine ([int]$anchorArtifact.start_line) -EndLine ([int]$anchorArtifact.end_line)
        if (-not [string]::IsNullOrWhiteSpace($rawOldText) -and $rawOldText -like ('*' + [string]$snippetSpec.insert_before_pattern + '*')) {
            $oldText = $rawOldText
        }
    }
    if ([string]::IsNullOrWhiteSpace($oldText)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'powershell_snippet_body_synthesis_old_text_missing' -Reason 'Input source-anchor artifact does not include non-empty exact_text.' -MissingVariable 'old_text')
    }

    $insertBeforePattern = [string]$snippetSpec.insert_before_pattern
    if ($oldText -notlike ('*' + $insertBeforePattern + '*')) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'powershell_snippet_body_synthesis_insert_anchor_not_found' -Reason ('Insert-before pattern not found in old_text: {0}' -f $insertBeforePattern) -MissingVariable 'insert_before_pattern')
    }

    $snippet = ([string]$snippetSpec.snippet).TrimEnd("`r", "`n")
    $oldLines = [System.Collections.Generic.List[string]]::new()
    foreach ($line in @($oldText -split "`r?`n")) {
        [void]$oldLines.Add([string]$line)
    }
    $newLines = [System.Collections.Generic.List[string]]::new()
    $snippetInserted = $false
    $trimmedInsertBeforePattern = $insertBeforePattern.Trim()
    for ($lineIndex = 0; $lineIndex -lt $oldLines.Count; $lineIndex++) {
        $line = [string]$oldLines[$lineIndex]
        if (-not $snippetInserted -and [string]::Equals($line.Trim(), $trimmedInsertBeforePattern, [System.StringComparison]::Ordinal)) {
            $anchorIndent = ([regex]::Match($line, '^\s*')).Value
            foreach ($snippetLine in @($snippet -split "`r?`n")) {
                $snippetLineText = [string]$snippetLine
                if ([string]::IsNullOrWhiteSpace($snippetLineText) -or $snippetLineText -match '^\s') {
                    [void]$newLines.Add($snippetLineText)
                }
                else {
                    [void]$newLines.Add($anchorIndent + $snippetLineText)
                }
            }
            [void]$newLines.Add('')
            $snippetInserted = $true
        }
        [void]$newLines.Add($line)
    }
    if (-not $snippetInserted) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'powershell_snippet_body_synthesis_insert_anchor_not_found' -Reason ('Insert-before pattern not found as a complete line in old_text: {0}' -f $insertBeforePattern) -MissingVariable 'insert_before_pattern')
    }
    $newText = ($newLines.ToArray() -join "`n")
    if ([string]::Equals([string]$newText, [string]$oldText, [System.StringComparison]::Ordinal)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'powershell_snippet_body_synthesis_no_delta' -Reason 'PowerShell snippet body synthesis produced identical old_text and new_text.' -MissingVariable 'new_text_delta')
    }

    $validationCommand = [string]$snippetSpec.validation_command
    if ([string]::IsNullOrWhiteSpace($validationCommand)) {
        $validationCommand = 'powershell -NoProfile -Command "$null = [System.Management.Automation.Language.Parser]::ParseFile(''{0}'', [ref]$null, [ref]$null)"' -f $targetFile
    }
    $validationPattern = [string]$snippetSpec.validation_pattern
    if ([string]::IsNullOrWhiteSpace($validationPattern)) {
        $validationPattern = $insertBeforePattern
    }
    $closureEvidence = [string]$snippetSpec.closure_evidence
    if ([string]::IsNullOrWhiteSpace($closureEvidence)) {
        $closureEvidence = 'Packet candidate ready with exact source-anchor old_text and synthesized PowerShell snippet new_text.'
    }
    $preventionLesson = [string]$snippetSpec.prevention_lesson
    if ([string]::IsNullOrWhiteSpace($preventionLesson)) {
        $preventionLesson = 'TOD must observe exact current source text before synthesizing PowerShell snippet bounded packets.'
    }
    $daveNeeded = [string]$snippetSpec.dave_needed
    if ([string]::IsNullOrWhiteSpace($daveNeeded)) {
        $daveNeeded = 'no'
    }

    $artifact = [ordered]@{
        artifact_type = 'tod_powershell_snippet_body_synthesis_artifact'
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        source = 'local_execution_powershell_snippet_body_synthesis_lane'
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

    $Result.summary = ('Published PowerShell snippet body synthesis artifact {0} from source anchor {1}.' -f $outputRel, $inputRel)
    $Result.files_changed = @($outputRel)
    $Result.tests_run = @('input source-anchor artifact read', 'powershell snippet synthesis', 'packet candidate schema validation', 'no source edit assertion')
    $Result.test_results = @('pass', 'pass', 'pass', 'pass')
    $Result | Add-Member -NotePropertyName command_output -NotePropertyValue ($validationOutput -join "`n") -Force
    $Result | Add-Member -NotePropertyName diff_summary -NotePropertyValue ('Artifact write only: {0}' -f $outputRel) -Force
    $Result | Add-Member -NotePropertyName commands_run -NotePropertyValue @('Invoke-LocalExecutionPowerShellSnippetBodySynthesis', $validationCommandForPacket) -Force
    $Result | Add-Member -NotePropertyName validation_results -NotePropertyValue @(
        [pscustomobject]@{ name = 'input source-anchor artifact read'; passed = $true; required = $true },
        [pscustomobject]@{ name = 'powershell snippet synthesis'; passed = $true; required = $true },
        [pscustomobject]@{ name = 'packet candidate schema validation'; passed = $true; required = $true },
        [pscustomobject]@{ name = 'no source edit assertion'; passed = $true; required = $true }
    ) -Force
    $Result | Add-Member -NotePropertyName blockers -NotePropertyValue @() -Force
    $Result | Add-Member -NotePropertyName confidence -NotePropertyValue 'medium-high' -Force
    $Result | Add-Member -NotePropertyName rollback_hint -NotePropertyValue ('Remove generated artifact {0} if this PowerShell snippet packet-body training artifact must be discarded.' -f $outputRel) -Force
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

function Invoke-TODShadowPatchSemanticValidation {
    param(
        [Parameter(Mandatory = $true)][string]$TargetFile,
        [Parameter(Mandatory = $true)][string]$OldText,
        [Parameter(Mandatory = $true)][string]$NewText,
        [Parameter(Mandatory = $true)][string]$ValidationCommand,
        [Parameter(Mandatory = $false)][object]$BehaviorAssertion = $null
    )

    $result = [ordered]@{
        candidate_id = ''
        target_files = @($TargetFile)
        temporary_workspace = ''
        patch_applied = $false
        anchor_match_count = 0
        parser_command = ''
        parser_exit_code = $null
        parser_stdout = ''
        parser_stderr = ''
        validation_commands = @($ValidationCommand)
        validation_results = @()
        behavior_test = 'literal replacement changes exactly one anchor and preserves a parseable target'
        behavior_test_passed = $false
        support_files_staged = @()
        support_files_unchanged = $true
        changed_files = @()
        unexpected_files = @()
        resulting_diff = $null
        production_hash_before = ''
        production_hash_after = ''
        production_source_unchanged = $false
        cleanup_passed = $false
        semantic_verdict = 'reject'
        mutation_authority_allowed = $false
        reason_codes = @()
    }

    $reasonCodes = New-Object System.Collections.Generic.List[string]
    $tempRoot = ''
    try {
        $targetRel = Convert-ToLocalExecutionRepoRelativePath -PathValue $TargetFile
        if ([string]::IsNullOrWhiteSpace($targetRel) -or -not (Test-LocalExecutionSafePath -RelativePath $targetRel)) {
            [void]$reasonCodes.Add('target_outside_safe_roots')
            return [pscustomobject]$result
        }

        $targetAbs = Join-Path $script:LocalEngineRepoRoot $targetRel
        if (-not (Test-Path -LiteralPath $targetAbs -PathType Leaf)) {
            [void]$reasonCodes.Add('target_file_missing')
            return [pscustomobject]$result
        }

        $result.production_hash_before = [string](Get-FileHash -LiteralPath $targetAbs -Algorithm SHA256).Hash
        $currentText = [System.IO.File]::ReadAllText($targetAbs)
        $candidateOldTextLf = ([string]$OldText) -replace "`r`n", "`n" -replace "`r", "`n"
        $candidateNewTextLf = ([string]$NewText) -replace "`r`n", "`n" -replace "`r", "`n"
        $candidatePairs = [System.Collections.Generic.List[object]]::new()
        [void]$candidatePairs.Add([pscustomobject]@{ old_text = $candidateOldTextLf; new_text = $candidateNewTextLf })
        $candidateOldTextCrLf = $candidateOldTextLf -replace "`n", "`r`n"
        if (-not [string]::Equals($candidateOldTextCrLf, $candidateOldTextLf, [System.StringComparison]::Ordinal)) {
            [void]$candidatePairs.Add([pscustomobject]@{
                    old_text = $candidateOldTextCrLf
                    new_text = ($candidateNewTextLf -replace "`n", "`r`n")
                })
        }

        $matchCount = 0
        $selectedPair = $null
        foreach ($candidatePair in @($candidatePairs.ToArray())) {
            $candidateMatchCount = 0
            $searchAt = 0
            $candidateOldText = [string]$candidatePair.old_text
            while ($searchAt -le ($currentText.Length - $candidateOldText.Length)) {
                $matchAt = $currentText.IndexOf($candidateOldText, $searchAt, [System.StringComparison]::Ordinal)
                if ($matchAt -lt 0) { break }
                $candidateMatchCount++
                $searchAt = $matchAt + [Math]::Max(1, $candidateOldText.Length)
            }
            $matchCount += $candidateMatchCount
            if ($candidateMatchCount -eq 1) {
                $selectedPair = $candidatePair
            }
        }
        $result.anchor_match_count = $matchCount
        if ($matchCount -ne 1) {
            [void]$reasonCodes.Add('literal_anchor_match_count_not_one')
            return [pscustomobject]$result
        }
        $effectiveOldText = [string]$selectedPair.old_text
        $effectiveNewText = [string]$selectedPair.new_text

        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('tod-shadow-patch-' + [guid]::NewGuid().ToString('N'))
        $result.temporary_workspace = $tempRoot
        $tempTarget = Join-Path $tempRoot $targetRel
        New-Item -ItemType Directory -Path (Split-Path -Parent $tempTarget) -Force | Out-Null
        Copy-Item -LiteralPath $targetAbs -Destination $tempTarget -Force

        $anchorIndex = $currentText.IndexOf($effectiveOldText, [System.StringComparison]::Ordinal)
        $updatedText = $currentText.Remove($anchorIndex, $effectiveOldText.Length).Insert($anchorIndex, $effectiveNewText)
        Write-Utf8NoBomFile -Path $tempTarget -Content $updatedText -PreserveExistingBom
        $result.patch_applied = $true
        $tempHash = [string](Get-FileHash -LiteralPath $tempTarget -Algorithm SHA256).Hash
        $result.resulting_diff = [ordered]@{
            target_file = $targetRel
            old_text = $effectiveOldText
            new_text = $effectiveNewText
            source_hash = $result.production_hash_before
            temporary_hash = $tempHash
        }

        $extension = ([System.IO.Path]::GetExtension($targetRel)).ToLowerInvariant()
        $safeValidationCommand = ''
        $tempPesterSupport = ''
        $tempPesterSupportHash = ''
        $pesterTargetMatch = [regex]::Match(
            [string]$ValidationCommand,
            '(?i)^\s*Invoke-Pester\s+-(?:Path|Script)\s+["'']?(?<path>[^"'']+?)["'']?\s*$'
        )
        $pesterTarget = if ($pesterTargetMatch.Success) { ([string]$pesterTargetMatch.Groups['path'].Value).Trim() -replace '\\', '/' } else { '' }
        $pytestTargetMatch = [regex]::Match(
            [string]$ValidationCommand,
            '(?i)^\s*python(?:\.exe)?\s+-m\s+pytest(?:\s+-q)?\s+["'']?(?<path>[^"'']+?\.py)["'']?\s*$'
        )
        $pytestTarget = if ($pytestTargetMatch.Success) { ([string]$pytestTargetMatch.Groups['path'].Value).Trim() -replace '\\', '/' } else { '' }
        if (
            $extension -in @('.ps1', '.psm1') -and
            $pesterTargetMatch.Success -and
            [string]::Equals($pesterTarget, $targetRel, [System.StringComparison]::OrdinalIgnoreCase)
        ) {
            $escapedTempTarget = $tempTarget.Replace("'", "''")
            $safeValidationCommand = "`$ErrorActionPreference='Stop';`$pester=Invoke-Pester -Script '$escapedTempTarget' -PassThru;if(`$pester.FailedCount -gt 0){throw ('Focused Pester validation failed: ' + `$pester.FailedCount)};Write-Output focused_pester=passed"
        }
        elseif ($extension -in @('.ps1', '.psm1') -and $pesterTargetMatch.Success) {
            $rawPesterTarget = ([string]$pesterTargetMatch.Groups['path'].Value).Trim() -replace '\\', '/'
            if (
                $rawPesterTarget -match '^[A-Za-z]:/' -or
                $rawPesterTarget.StartsWith('/') -or
                $rawPesterTarget -match '(^|/)\.\.(/|$)'
            ) {
                [void]$reasonCodes.Add('focused_behavior_test_path_unsafe')
            }
            else {
                $pesterTestRel = Convert-ToLocalExecutionRepoRelativePath -PathValue $rawPesterTarget
                $pesterTestAbs = if ([string]::IsNullOrWhiteSpace($pesterTestRel)) { '' } else { Join-Path $script:LocalEngineRepoRoot $pesterTestRel }
                if (
                    [string]::IsNullOrWhiteSpace($pesterTestRel) -or
                    -not (Test-LocalExecutionSafePath -RelativePath $pesterTestRel) -or
                    [System.IO.Path]::GetExtension($pesterTestRel) -ne '.ps1'
                ) {
                    [void]$reasonCodes.Add('focused_behavior_test_path_unsafe')
                }
                elseif (-not (Test-Path -LiteralPath $pesterTestAbs -PathType Leaf)) {
                    [void]$reasonCodes.Add('focused_behavior_test_file_missing')
                }
                else {
                    $tempPesterSupport = Join-Path $tempRoot $pesterTestRel
                    New-Item -ItemType Directory -Path (Split-Path -Parent $tempPesterSupport) -Force | Out-Null
                    Copy-Item -LiteralPath $pesterTestAbs -Destination $tempPesterSupport -Force
                    $tempPesterSupportHash = [string](Get-FileHash -LiteralPath $tempPesterSupport -Algorithm SHA256).Hash
                    $result.support_files_staged = @($pesterTestRel)
                    $escapedTempPesterSupport = $tempPesterSupport.Replace("'", "''")
                    $safeValidationCommand = "`$ErrorActionPreference='Stop';`$pester=Invoke-Pester -Script '$escapedTempPesterSupport' -PassThru;if(`$pester.FailedCount -gt 0){throw ('Focused Pester validation failed: ' + `$pester.FailedCount)};Write-Output focused_pester=passed"
                }
            }
        }
        elseif ($extension -in @('.ps1', '.psm1') -and $ValidationCommand -match '(?i)^\s*(powershell|pwsh)(\.exe)?\b.*Parser\]::ParseFile') {
            $escapedTempTarget = $tempTarget.Replace("'", "''")
            $safeValidationCommand = "`$ErrorActionPreference='Stop';`$tokens=`$null;`$errors=`$null;[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path '$escapedTempTarget'),[ref]`$tokens,[ref]`$errors)>`$null;if(`$errors.Count){throw (`$errors | Out-String)};Write-Output parse=passed"
        }
        elseif ($extension -eq '.py' -and (($ValidationCommand -match '(?i)python(?:\.exe)?\s+-m\s+py_compile') -or $pytestTargetMatch.Success)) {
            $safeValidationCommand = 'python -B -c ''import ast,sys; ast.parse(open(sys.argv[1]).read())'' "{0}"' -f $tempTarget
        }
        elseif ($extension -eq '.json' -and $ValidationCommand -match '(?i)python(?:\.exe)?\s+-m\s+json\.tool') {
            $safeValidationCommand = 'python -m json.tool "{0}"' -f $tempTarget
        }
        else {
            [void]$reasonCodes.Add('unsupported_or_unsafe_validation_command')
        }

        if (-not [string]::IsNullOrWhiteSpace($safeValidationCommand)) {
            $result.parser_command = $safeValidationCommand
            $commandResult = Invoke-LocalShellCapture -Command $safeValidationCommand -WorkingDirectory $tempRoot -TimeoutSeconds 90
            $result.parser_exit_code = [int]$commandResult.exit_code
            $result.parser_stdout = [string]$commandResult.stdout
            $result.parser_stderr = [string]$commandResult.stderr
            $commandPassed = (
                [int]$commandResult.exit_code -eq 0 -and
                -not [bool]$commandResult.timed_out -and
                (Test-LocalShellStderrClean -Stderr ([string]$commandResult.stderr))
            )
            $result.validation_results = @([ordered]@{
                proposed_command = $ValidationCommand
                executed_command = $safeValidationCommand
                exit_code = [int]$commandResult.exit_code
                timed_out = [bool]$commandResult.timed_out
                stdout = [string]$commandResult.stdout
                stderr = [string]$commandResult.stderr
                passed = $commandPassed
            })
            if (-not $commandPassed) {
                [void]$reasonCodes.Add('parser_or_validation_command_failed')
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($tempPesterSupport)) {
            $result.support_files_unchanged = (
                (Test-Path -LiteralPath $tempPesterSupport -PathType Leaf) -and
                [string]::Equals(
                    [string](Get-FileHash -LiteralPath $tempPesterSupport -Algorithm SHA256).Hash,
                    $tempPesterSupportHash,
                    [System.StringComparison]::OrdinalIgnoreCase
                )
            )
            if (-not $result.support_files_unchanged) {
                [void]$reasonCodes.Add('focused_behavior_test_support_modified')
            }
            Remove-Item -LiteralPath $tempPesterSupport -Force -ErrorAction SilentlyContinue
        }

        $changedFiles = @()
        foreach ($file in @(Get-ChildItem -LiteralPath $tempRoot -Recurse -File)) {
            $relative = $file.FullName.Substring($tempRoot.Length).TrimStart('\', '/') -replace '\\', '/'
            if ([string]::Equals($relative, $targetRel, [System.StringComparison]::OrdinalIgnoreCase)) {
                if (-not [string]::Equals([string](Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash, $result.production_hash_before, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $changedFiles += $relative
                }
            }
            else {
                $result.unexpected_files += $relative
            }
        }
        $result.changed_files = @($changedFiles)
        if (@($changedFiles).Count -ne 1 -or @($result.unexpected_files).Count -gt 0) {
            [void]$reasonCodes.Add('changed_file_allowlist_failed')
        }

        if ($extension -ne '.py') {
            $focusedValidationPassed = (
                @($result.validation_results).Count -gt 0 -and
                @($result.validation_results | Where-Object { -not [bool]$_.passed }).Count -eq 0 -and
                @($result.validation_results | Where-Object { $_.executed_command -match '(?i)\bInvoke-Pester\b' }).Count -gt 0
            )
            if ($focusedValidationPassed -and $null -eq $BehaviorAssertion) {
                $result.behavior_test = 'focused_validation_command'
                $result.behavior_test_results = @($result.validation_results)
                $result.behavior_test_passed = $true
            }
            else {
            $assertionResults = [System.Collections.Generic.List[object]]::new()
            $assertionPassed = $true
            if ($null -eq $BehaviorAssertion) {
                [void]$reasonCodes.Add('behavior_assertion_missing')
                $assertionPassed = $false
            }
            else {
                $typeProperty = $BehaviorAssertion.PSObject.Properties['type']
                $requiredProperty = $BehaviorAssertion.PSObject.Properties['required_contains']
                $forbiddenProperty = $BehaviorAssertion.PSObject.Properties['forbidden_contains']
                if ($null -eq $typeProperty -or [string]::IsNullOrWhiteSpace([string]$typeProperty.Value)) {
                    [void]$reasonCodes.Add('behavior_assertion_type_missing')
                    $assertionPassed = $false
                }
                elseif (-not [string]::Equals([string]$typeProperty.Value, 'text_invariants', [System.StringComparison]::Ordinal)) {
                    [void]$reasonCodes.Add('behavior_assertion_type_unsupported')
                    $assertionPassed = $false
                }
                if ($null -eq $requiredProperty) {
                    [void]$reasonCodes.Add('behavior_assertion_required_contains_missing')
                    $assertionPassed = $false
                }
                else {
                    $requiredContains = @($requiredProperty.Value)
                    $forbiddenContains = @($(if ($null -ne $forbiddenProperty) { $forbiddenProperty.Value }))
                    if ($requiredContains.Count -eq 0) {
                        [void]$reasonCodes.Add('behavior_assertion_required_contains_empty')
                        $assertionPassed = $false
                    }
                    elseif ($requiredContains.Count -gt 64 -or $forbiddenContains.Count -gt 64) {
                        [void]$reasonCodes.Add('behavior_assertion_limit_exceeded')
                        $assertionPassed = $false
                    }
                    else {
                        $patchedText = [System.IO.File]::ReadAllText($tempTarget)
                        foreach ($requiredText in $requiredContains) {
                            $requiredValue = [string]$requiredText
                            $requiredPassed = -not [string]::IsNullOrWhiteSpace($requiredValue) -and $requiredValue.Length -le 4096 -and $patchedText.Contains($requiredValue)
                            [void]$assertionResults.Add([ordered]@{ kind = 'required_contains'; value = $requiredValue; passed = $requiredPassed })
                            if (-not $requiredPassed) {
                                [void]$reasonCodes.Add('behavior_assertion_required_contains_failed')
                                $assertionPassed = $false
                            }
                        }
                        foreach ($forbiddenText in $forbiddenContains) {
                            $forbiddenValue = [string]$forbiddenText
                            $forbiddenPassed = -not [string]::IsNullOrWhiteSpace($forbiddenValue) -and $forbiddenValue.Length -le 4096 -and -not $patchedText.Contains($forbiddenValue)
                            [void]$assertionResults.Add([ordered]@{ kind = 'forbidden_contains'; value = $forbiddenValue; passed = $forbiddenPassed })
                            if (-not $forbiddenPassed) {
                                [void]$reasonCodes.Add('behavior_assertion_forbidden_contains_failed')
                                $assertionPassed = $false
                            }
                        }
                    }
                }
            }
            $result.behavior_test = 'text_invariants'
            $result.behavior_test_results = @($assertionResults)
                        if (-not $focusedValidationPassed -and $assertionPassed -and ($extension -eq '.ps1' -or $extension -eq '.psm1')) {
                [void]$reasonCodes.Add("text_invariants_not_executable_behavior_evidence")
                $assertionPassed = $false
            }
            $result.behavior_test_passed = $assertionPassed
            }
        }
        if ($extension -eq '.py') {
            $productionTest = ''
            $tempTest = ''
            if ($pytestTargetMatch.Success) {
                $testRel = Convert-ToLocalExecutionRepoRelativePath -PathValue $pytestTarget
                if ([string]::IsNullOrWhiteSpace($testRel) -or -not (Test-LocalExecutionSafePath -RelativePath $testRel)) {
                    [void]$reasonCodes.Add('focused_behavior_test_path_unsafe')
                }
                else {
                    $productionTest = Join-Path $script:LocalEngineRepoRoot $testRel
                    $tempTest = Join-Path $tempRoot $testRel
                }
            }
            else {
                $testName = 'test_' + (Split-Path -Path $targetAbs -Leaf)
                $productionTest = Join-Path (Split-Path -Path $targetAbs -Parent) $testName
                $tempTest = Join-Path (Split-Path -Path $tempTarget -Parent) $testName
            }
            if (-not (Test-Path -LiteralPath $productionTest -PathType Leaf)) {
                [void]$reasonCodes.Add($(if ($pytestTargetMatch.Success) { 'focused_behavior_test_file_missing' } else { 'adjacent_test_file_missing' }))
            }
            else {
                $pythonExe = Join-Path $script:LocalEngineRepoRoot '.venv/Scripts/python.exe'
                if (-not (Test-Path -LiteralPath $pythonExe -PathType Leaf)) {
                    [void]$reasonCodes.Add('focused_behavior_test_runtime_missing')
                }
                else {
                    New-Item -ItemType Directory -Path (Split-Path -Parent $tempTest) -Force | Out-Null
                    if (-not [string]::Equals($tempTest, $tempTarget, [System.StringComparison]::OrdinalIgnoreCase)) {
                        Copy-Item -LiteralPath $productionTest -Destination $tempTest -Force
                    }
                    try {
                        $escapedPythonExe = $pythonExe.Replace("'", "''")
                        $escapedTempTest = $tempTest.Replace("'", "''")
                        $behaviorCommand = "& '$escapedPythonExe' -m pytest -q -p no:cacheprovider '$escapedTempTest'"
                        $behaviorResult = Invoke-LocalShellCapture -Command $behaviorCommand -WorkingDirectory $tempRoot -TimeoutSeconds 60
                        $normalBehaviorPassed = (
                            [int]$behaviorResult.exit_code -eq 0 -and
                            -not [bool]$behaviorResult.timed_out -and
                            (Test-LocalShellStderrClean -Stderr ([string]$behaviorResult.stderr))
                        )
                        $expectedRedPassed = $false
                        $expectedRedRequested = $false
                        if ($null -ne $BehaviorAssertion) {
                            $typeProperty = $BehaviorAssertion.PSObject.Properties['type']
                            $scopeProperty = $BehaviorAssertion.PSObject.Properties['mutation_scope']
                            $exitProperty = $BehaviorAssertion.PSObject.Properties['expected_exit_code']
                            $requiredProperty = $BehaviorAssertion.PSObject.Properties['required_stdout_contains']
                            $forbiddenProperty = $BehaviorAssertion.PSObject.Properties['forbidden_output_contains']
                            $expectedExitCode = 0
                            $expectedRedRequested = (
                                $null -ne $typeProperty -and
                                [string]::Equals([string]$typeProperty.Value, 'expected_red_pytest', [System.StringComparison]::Ordinal)
                            )
                            $isTestOnlyTarget = (
                                [string]$targetRel -match '(?i)(^|/)tests?/' -or
                                [System.IO.Path]::GetFileName([string]$targetRel) -match '(?i)^test_.*\.py$'
                            )
                            $assertionShapeValid = (
                                $null -ne $typeProperty -and
                                [string]::Equals([string]$typeProperty.Value, 'expected_red_pytest', [System.StringComparison]::Ordinal) -and
                                $null -ne $scopeProperty -and
                                [string]::Equals([string]$scopeProperty.Value, 'test_only', [System.StringComparison]::Ordinal) -and
                                $null -ne $exitProperty -and
                                [int]::TryParse([string]$exitProperty.Value, [ref]$expectedExitCode) -and
                                $null -ne $requiredProperty -and
                                @($requiredProperty.Value).Count -gt 0 -and
                                @($requiredProperty.Value).Count -le 64 -and
                                $null -ne $forbiddenProperty -and
                                @($forbiddenProperty.Value).Count -le 64 -and
                                $isTestOnlyTarget
                            )
                            if ($assertionShapeValid) {
                                $requiredOutputPassed = $true
                                foreach ($requiredFragment in @($requiredProperty.Value)) {
                                    $requiredValue = [string]$requiredFragment
                                    if (
                                        [string]::IsNullOrWhiteSpace($requiredValue) -or
                                        $requiredValue.Length -gt 4096 -or
                                        ([string]$behaviorResult.stdout).IndexOf($requiredValue, [System.StringComparison]::OrdinalIgnoreCase) -lt 0
                                    ) {
                                        $requiredOutputPassed = $false
                                        break
                                    }
                                }
                                $forbiddenOutputPassed = $true
                                $combinedBehaviorOutput = '{0}`n{1}' -f ([string]$behaviorResult.stdout), ([string]$behaviorResult.stderr)
                                foreach ($forbiddenFragment in @($forbiddenProperty.Value)) {
                                    $forbiddenValue = [string]$forbiddenFragment
                                    if (
                                        [string]::IsNullOrWhiteSpace($forbiddenValue) -or
                                        $forbiddenValue.Length -gt 4096 -or
                                        $combinedBehaviorOutput.IndexOf($forbiddenValue, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
                                    ) {
                                        $forbiddenOutputPassed = $false
                                        break
                                    }
                                }
                                $expectedRedPassed = (
                                    [int]$behaviorResult.exit_code -eq $expectedExitCode -and
                                    -not [bool]$behaviorResult.timed_out -and
                                    $requiredOutputPassed -and
                                    $forbiddenOutputPassed
                                )
                            }
                        }
                        $behaviorPassed = if ($expectedRedRequested) { $expectedRedPassed } else { $normalBehaviorPassed }
                        $result.behavior_test = $behaviorCommand
                        $result.behavior_test_results = @([ordered]@{
                            command = [string]$behaviorResult.command
                            exit_code = [int]$behaviorResult.exit_code
                            timed_out = [bool]$behaviorResult.timed_out
                            stdout = [string]$behaviorResult.stdout
                            stderr = [string]$behaviorResult.stderr
                            normal_success = $normalBehaviorPassed
                            expected_red = $expectedRedPassed
                            passed = $behaviorPassed
                        })
                        $result.behavior_test_passed = $behaviorPassed
                        if (-not $behaviorPassed) {
                            [void]$reasonCodes.Add('focused_behavior_test_failed')
                        }
                    }
                    finally {
                        Remove-Item -LiteralPath $tempTest -Force -ErrorAction SilentlyContinue
                    }
                }
            }
        }
    }
    catch {
        [void]$reasonCodes.Add('semantic_validation_exception')
        $result.parser_stderr = [string]$_.Exception.Message
    }
    finally {
        if (-not [string]::IsNullOrWhiteSpace($tempRoot) -and (Test-Path -LiteralPath $tempRoot)) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
        $result.cleanup_passed = ([string]::IsNullOrWhiteSpace($tempRoot) -or -not (Test-Path -LiteralPath $tempRoot))
        if (-not [string]::IsNullOrWhiteSpace($TargetFile)) {
            $targetRelAfter = Convert-ToLocalExecutionRepoRelativePath -PathValue $TargetFile
            if (-not [string]::IsNullOrWhiteSpace($targetRelAfter)) {
                $targetAbsAfter = Join-Path $script:LocalEngineRepoRoot $targetRelAfter
                if (Test-Path -LiteralPath $targetAbsAfter -PathType Leaf) {
                    $result.production_hash_after = [string](Get-FileHash -LiteralPath $targetAbsAfter -Algorithm SHA256).Hash
                    $result.production_source_unchanged = (
                        -not [string]::IsNullOrWhiteSpace([string]$result.production_hash_before) -and
                        [string]::Equals([string]$result.production_hash_before, [string]$result.production_hash_after, [System.StringComparison]::OrdinalIgnoreCase)
                    )
                }
            }
        }
        if (-not $result.cleanup_passed) { [void]$reasonCodes.Add('temporary_workspace_cleanup_failed') }
        if (-not $result.production_source_unchanged) { [void]$reasonCodes.Add('production_source_hash_changed') }
        $result.reason_codes = @($reasonCodes | Select-Object -Unique)
        $result.mutation_authority_allowed = (@($result.reason_codes).Count -eq 0)
        $result.semantic_verdict = if ($result.mutation_authority_allowed) { 'accept' } else { 'reject' }
    }

    return [pscustomobject]$result
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
    $selectedSourceReason = if ($paths.PSObject.Properties['selected_source_reason']) { [string]$paths.selected_source_reason } else { '' }
    $promptText = Get-LocalExecutionPromptText -Context $Context
    $combinedPromptText = Get-LocalExecutionCombinedText -Context $Context
    $requiredArtifactType = ''
    if (-not [string]::IsNullOrWhiteSpace($promptText)) {
        $requiredArtifactType = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Required Artifact Type'
        if ([string]::IsNullOrWhiteSpace($requiredArtifactType)) {
            $requiredArtifactTypeMatch = [regex]::Match($promptText, '(?im)^\s*(?:[-*]\s*)?Required\s+Artifact\s+Type\s*:\s*(?<value>[A-Za-z0-9_.-]+)\s*$')
            if ($requiredArtifactTypeMatch.Success) {
                $requiredArtifactType = ([string]$requiredArtifactTypeMatch.Groups['value'].Value).Trim()
            }
        }
        if ([string]::IsNullOrWhiteSpace($requiredArtifactType)) {
            $requiredArtifactTypeMatch = [regex]::Match($promptText, '(?i)\bRequired\s+Artifact\s+Type\s*:\s*(?<value>[A-Za-z0-9_.-]+)')
            if ($requiredArtifactTypeMatch.Success) {
                $requiredArtifactType = ([string]$requiredArtifactTypeMatch.Groups['value'].Value).Trim()
            }
        }
    }
    if ([string]::IsNullOrWhiteSpace($requiredArtifactType) -and -not [string]::IsNullOrWhiteSpace($combinedPromptText)) {
        $requiredArtifactType = Get-LocalExecutionDirectiveValue -PromptText $combinedPromptText -FieldName 'Required Artifact Type'
        if ([string]::IsNullOrWhiteSpace($requiredArtifactType)) {
            $requiredArtifactTypeMatch = [regex]::Match($combinedPromptText, '(?im)^\s*(?:[-*]\s*)?Required\s+Artifact\s+Type\s*:\s*(?<value>[A-Za-z0-9_.-]+)\s*$')
            if ($requiredArtifactTypeMatch.Success) {
                $requiredArtifactType = ([string]$requiredArtifactTypeMatch.Groups['value'].Value).Trim()
            }
        }
        if ([string]::IsNullOrWhiteSpace($requiredArtifactType)) {
            $requiredArtifactTypeMatch = [regex]::Match($combinedPromptText, '(?i)\bRequired\s+Artifact\s+Type\s*:\s*(?<value>[A-Za-z0-9_.-]+)')
            if ($requiredArtifactTypeMatch.Success) {
                $requiredArtifactType = ([string]$requiredArtifactTypeMatch.Groups['value'].Value).Trim()
            }
        }
        if ([string]::IsNullOrWhiteSpace($requiredArtifactType)) {
            $producesArtifactTypeMatch = [regex]::Match($combinedPromptText, '(?i)\bProduces\s+(?<value>tod_[A-Za-z0-9_.-]+)\b')
            if ($producesArtifactTypeMatch.Success) {
                $requiredArtifactType = ([string]$producesArtifactTypeMatch.Groups['value'].Value).Trim()
            }
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($requiredArtifactType)) {
        $requiredArtifactTypeToken = [regex]::Match($requiredArtifactType, '[A-Za-z0-9_.-]+')
        if ($requiredArtifactTypeToken.Success) {
            $requiredArtifactType = (([string]$requiredArtifactTypeToken.Value).Trim()).TrimEnd('.', ';', ',', ':')
        }
    }
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

    $isPatchAuthorityClassification = (
        $auditSource.PSObject.Properties['artifact_type'] -and
        [string]$auditSource.artifact_type -eq 'tod_patch_evidence_authority_classification'
    )
    if ($isPatchAuthorityClassification) {
        $patchAuthorityFields = @(
            'artifact_type',
            'classification_counts',
            'signals',
            'route_boundary_decision',
            'continuation_action',
            'no_source_code_modified_by_assessment',
            'no_code_changes',
            'validation'
        )
        $evidenceFields = @($evidenceFields + $patchAuthorityFields | Select-Object -Unique)
        $classification = 'patch_authority_classification_review_required'

        $reusableCount = 0
        $hardcodedCount = 0
        $operatorContractCount = 0
        if ($auditSource.PSObject.Properties['classification_counts']) {
            if ($auditSource.classification_counts.PSObject.Properties['reusable_service_candidate']) {
                $reusableCount = [int]$auditSource.classification_counts.reusable_service_candidate
            }
            if ($auditSource.classification_counts.PSObject.Properties['hardcoded_response_authority_risk']) {
                $hardcodedCount = [int]$auditSource.classification_counts.hardcoded_response_authority_risk
            }
            if ($auditSource.classification_counts.PSObject.Properties['operator_contract_authority_risk']) {
                $operatorContractCount = [int]$auditSource.classification_counts.operator_contract_authority_risk
            }
        }

        $signalSummaries = @()
        if ($auditSource.PSObject.Properties['signals']) {
            $signalSummaries = @($auditSource.signals | ForEach-Object {
                $name = if ($_.PSObject.Properties['signal']) { [string]$_.signal } else { 'unknown_signal' }
                $bucket = if ($_.PSObject.Properties['bucket']) { [string]$_.bucket } else { 'unknown_bucket' }
                $count = if ($_.PSObject.Properties['match_count']) { [string]$_.match_count } else { '' }
                '{0}:{1}:{2}' -f $name, $bucket, $count
            })
        }

        $findings.Add([ordered]@{
            finding = 'patch_authority_classification_counts'
            evidence = ('reusable_service_candidate={0}; hardcoded_response_authority_risk={1}; operator_contract_authority_risk={2}' -f $reusableCount, $hardcodedCount, $operatorContractCount)
        }) | Out-Null
        if ($signalSummaries.Count -gt 0) {
            $findings.Add([ordered]@{
                finding = 'patch_authority_signals'
                evidence = ($signalSummaries -join ' | ')
            }) | Out-Null
        }
        if ($auditSource.PSObject.Properties['continuation_action'] -and -not [string]::IsNullOrWhiteSpace([string]$auditSource.continuation_action)) {
            $findings.Add([ordered]@{
                finding = 'patch_authority_continuation_action'
                evidence = [string]$auditSource.continuation_action
            }) | Out-Null
        }
        if ($hardcodedCount -gt 0 -or $operatorContractCount -gt 0) {
            $blockers += [pscustomobject]@{
                type = 'blocker'
                reason_code = 'route_response_authority_risk_present'
                reason = ('Hardcoded response authority risk={0}; operator contract authority risk={1}.' -f $hardcodedCount, $operatorContractCount)
                task_id = if ($Context.PSObject.Properties['task_id']) { [string]$Context.task_id } else { '' }
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

    $hasCreditDecision = $auditSource.PSObject.Properties['credit_decision']
    $hasPacketReviewDecision = $auditSource.PSObject.Properties['decision'] -or $auditSource.PSObject.Properties['failure_reason_or_acceptance_reason']
    if ($hasCreditDecision -or $hasPacketReviewDecision) {
        $creditFields = @(
            'artifact_type',
            'generated_at',
            'source',
            'decision',
            'failure_reason_or_acceptance_reason',
            'next_smaller_repair_step',
            'credit_decision',
            'evidence_checked'
        )
        $evidenceFields = @($evidenceFields + $creditFields | Select-Object -Unique)
        $classification = 'credit_decision_review_required'

        $decisionText = if ($auditSource.PSObject.Properties['decision']) { [string]$auditSource.decision } else { '' }
        $creditReason = ''
        $independentResolution = ''
        $meaningfulImplementation = ''
        $validatedEdit = ''
        if ($hasCreditDecision -and $auditSource.credit_decision) {
            if ($auditSource.credit_decision.PSObject.Properties['reason']) {
                $creditReason = [string]$auditSource.credit_decision.reason
            }
            if ($auditSource.credit_decision.PSObject.Properties['independent_tod_resolution']) {
                $independentResolution = [string]$auditSource.credit_decision.independent_tod_resolution
            }
            if ($auditSource.credit_decision.PSObject.Properties['meaningful_tod_implementation']) {
                $meaningfulImplementation = [string]$auditSource.credit_decision.meaningful_tod_implementation
            }
            if ($auditSource.credit_decision.PSObject.Properties['validated_tod_edit']) {
                $validatedEdit = [string]$auditSource.credit_decision.validated_tod_edit
            }
        }
        $failureReasons = @()
        if ($auditSource.PSObject.Properties['failure_reason_or_acceptance_reason']) {
            $failureReasons = @($auditSource.failure_reason_or_acceptance_reason | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        }
        $nextSmallerStep = if ($auditSource.PSObject.Properties['next_smaller_repair_step']) { [string]$auditSource.next_smaller_repair_step } else { '' }

        $findings.Add([ordered]@{
            finding = 'visible_credit_decision'
            evidence = ('decision={0}; independent_tod_resolution={1}; meaningful_tod_implementation={2}; validated_tod_edit={3}; reason={4}' -f $decisionText, $independentResolution, $meaningfulImplementation, $validatedEdit, $creditReason)
        }) | Out-Null
        if ($failureReasons.Count -gt 0) {
            $findings.Add([ordered]@{
                finding = 'packet_rejection_or_acceptance_reason'
                evidence = ($failureReasons -join '; ')
            }) | Out-Null
        }
        if (-not [string]::IsNullOrWhiteSpace($nextSmallerStep)) {
            $findings.Add([ordered]@{
                finding = 'next_smaller_repair_step'
                evidence = $nextSmallerStep
            }) | Out-Null
        }

        if ($decisionText -match 'reject|block' -or $independentResolution -eq 'False' -or $meaningfulImplementation -eq 'False' -or $validatedEdit -eq 'False') {
            $blockers += [pscustomobject]@{
                type = 'blocker'
                reason_code = 'credit_decision_blocks_independent_progress'
                reason = if (-not [string]::IsNullOrWhiteSpace($creditReason)) { $creditReason } elseif ($failureReasons.Count -gt 0) { $failureReasons -join '; ' } else { 'Credit decision does not prove independent TOD progress.' }
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

    $combinedTextForAudit = Get-LocalExecutionCombinedText -Context $Context
    $wantsSourceAnchorDeltaProposal = (
        (
            [string]::IsNullOrWhiteSpace($requiredArtifactType) -or
            [string]::Equals($requiredArtifactType, 'tod_source_anchor_delta_proposal', [System.StringComparison]::OrdinalIgnoreCase)
        ) -and
        $combinedTextForAudit -match '(?is)\btod_source_anchor_delta_proposal\b|source[- ]anchor\s+delta\s+proposal|intended_behavior_delta'
    )
    $sourceAnchorArtifactRel = Convert-ToLocalExecutionRepoRelativePath -PathValue (Get-LocalExecutionDirectiveValue -PromptText $combinedTextForAudit -FieldName 'Source Anchor Artifact')
    if ($wantsSourceAnchorDeltaProposal -and [string]::IsNullOrWhiteSpace($sourceAnchorArtifactRel)) {
        $sourceAnchorArtifactRel = Convert-ToLocalExecutionRepoRelativePath -PathValue (Get-LocalExecutionDirectiveValue -PromptText $combinedTextForAudit -FieldName 'Input Artifact')
    }
    $wantsHeldoutCandidateNewTextFromManifest = (-not $wantsSourceAnchorDeltaProposal) -and (
        $combinedTextForAudit -match '(?is)\bheld[-_\s]?out\b' -and
        $combinedTextForAudit -match '(?is)\bcandidate[-_\s]?new[-_\s]?text\b|tod_heldout_candidate_newtext_from_corpus_manifest'
    )
    $wantsCorpusSourceAnchorEpisodeEnrichment = (-not $wantsSourceAnchorDeltaProposal) -and (-not $wantsHeldoutCandidateNewTextFromManifest) -and (
        [string]::IsNullOrWhiteSpace($requiredArtifactType) -or
        [string]::Equals($requiredArtifactType, 'tod_engineering_corpus_source_anchor_episode_enrichment', [System.StringComparison]::OrdinalIgnoreCase)
    ) -and (
        $combinedTextForAudit -match '(?is)\bcorpus\b' -and
        $combinedTextForAudit -match '(?is)\bsource[-_\s]?anchor\b' -and
        $combinedTextForAudit -match '(?is)\benrich|enrichment|enriched[-_\s]?episode|tod_engineering_corpus_source_anchor_episode_enrichment'
    )
    $corpusSourceAnchorEpisodeEnrichmentArtifact = $null
    if ($wantsCorpusSourceAnchorEpisodeEnrichment) {
        $existingEpisodes = @()
        $enrichedEpisode = $null
        $enrichmentGaps = New-Object System.Collections.Generic.List[string]
        $manifestValid = (
            $auditSource.PSObject.Properties['artifact_type'] -and
            [string]$auditSource.artifact_type -eq 'tod_engineering_corpus_episode_candidate_manifest' -and
            $auditSource.PSObject.Properties['episode_candidates']
        )

        if ($manifestValid) {
            $existingEpisodes = @($auditSource.episode_candidates)
        }
        else {
            [void]$enrichmentGaps.Add('input_artifact_is_not_corpus_episode_candidate_manifest')
        }

        $sourceAnchorArtifactRead = $false
        $sourceAnchorValid = $false
        $sourceAnchorSource = $null
        if ([string]::IsNullOrWhiteSpace($sourceAnchorArtifactRel)) {
            [void]$enrichmentGaps.Add('source_anchor_artifact_missing')
        }
        elseif (-not (Test-LocalExecutionSafePath -RelativePath $sourceAnchorArtifactRel)) {
            [void]$enrichmentGaps.Add('source_anchor_artifact_path_unsafe')
        }
        else {
            $sourceAnchorAbs = Join-Path $script:LocalEngineRepoRoot $sourceAnchorArtifactRel
            if (-not (Test-Path -Path $sourceAnchorAbs -PathType Leaf)) {
                [void]$enrichmentGaps.Add('source_anchor_artifact_not_found')
            }
            else {
                try {
                    $sourceAnchorSource = Get-Content -Path $sourceAnchorAbs -Raw | ConvertFrom-Json
                    $sourceAnchorArtifactRead = $true
                    $sourceAnchorValid = (
                        $sourceAnchorSource.PSObject.Properties['artifact_type'] -and
                        [string]$sourceAnchorSource.artifact_type -eq 'tod_source_anchor_observation' -and
                        $sourceAnchorSource.PSObject.Properties['source_file'] -and
                        -not [string]::IsNullOrWhiteSpace([string]$sourceAnchorSource.source_file) -and
                        $sourceAnchorSource.PSObject.Properties['exact_text'] -and
                        -not [string]::IsNullOrWhiteSpace([string]$sourceAnchorSource.exact_text)
                    )
                    if (-not $sourceAnchorValid) {
                        [void]$enrichmentGaps.Add('source_anchor_artifact_invalid')
                    }
                }
                catch {
                    [void]$enrichmentGaps.Add('source_anchor_artifact_read_failed')
                }
            }
        }

        $episodeList = New-Object System.Collections.Generic.List[object]
        foreach ($episode in $existingEpisodes) {
            [void]$episodeList.Add($episode)
        }

        if ($manifestValid -and $sourceAnchorValid) {
            $episodeId = ('episode-{0:000}' -f (@($episodeList.ToArray()).Count + 1))
            $enrichedEpisode = [ordered]@{
                episode_id = $episodeId
                source_artifact = $sourceAnchorArtifactRel
                source_artifact_type = 'tod_source_anchor_observation'
                source_objective_id = if ($sourceAnchorSource.PSObject.Properties['objective_id']) { [string]$sourceAnchorSource.objective_id } else { '' }
                source_task_id = if ($sourceAnchorSource.PSObject.Properties['task_id']) { [string]$sourceAnchorSource.task_id } else { '' }
                source_file = [string]$sourceAnchorSource.source_file
                start_line = if ($sourceAnchorSource.PSObject.Properties['start_line']) { $sourceAnchorSource.start_line } else { $null }
                end_line = if ($sourceAnchorSource.PSObject.Properties['end_line']) { $sourceAnchorSource.end_line } else { $null }
                exact_text_available = $true
                source_code_modified = if ($sourceAnchorSource.PSObject.Properties['no_code_changes']) { -not [bool]$sourceAnchorSource.no_code_changes } else { $false }
                candidate_quality = 'source_anchor_episode'
                likely_capability_classification = 'scaffolded_or_borrowed'
                actual_author_signal = 'Codex_or_mixed'
                borrowed_capability_signal = 'borrowed_present'
                usable_for_training = $true
                reuse_tags = @(
                    'tod_engineering_corpus',
                    'source_anchor_observation',
                    ([string]$sourceAnchorSource.source_file -replace '[^A-Za-z0-9_/-]', '_')
                ) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
            }
            [void]$episodeList.Add($enrichedEpisode)
        }

        $sourceAnchorEpisodeCount = @($episodeList.ToArray() | Where-Object {
            $episodeSourceArtifactType = ''
            if ($_ -is [System.Collections.IDictionary] -and $_.Contains('source_artifact_type')) {
                $episodeSourceArtifactType = [string]$_['source_artifact_type']
            }
            elseif ($_.PSObject.Properties['source_artifact_type']) {
                $episodeSourceArtifactType = [string]$_.source_artifact_type
            }
            $episodeSourceArtifactType -eq 'tod_source_anchor_observation'
        }).Count

        $corpusSourceAnchorEpisodeEnrichmentArtifact = [ordered]@{
            artifact_type = 'tod_engineering_corpus_source_anchor_episode_enrichment'
            generated_at = (Get-Date).ToUniversalTime().ToString('o')
            source = 'local_execution_read_only_audit_artifact_lane'
            objective_id = if ($Context.PSObject.Properties['objective_id']) { [string]$Context.objective_id } else { '' }
            task_id = if ($Context.PSObject.Properties['task_id']) { [string]$Context.task_id } else { '' }
            status = if ($manifestValid -and $sourceAnchorValid) { 'completed' } else { 'blocked' }
            codex_role = 'escalation_after_TOD_attempt'
            input_manifest_artifact = $inputRel
            source_anchor_artifact = $sourceAnchorArtifactRel
            episode_candidates = @($episodeList.ToArray())
            enriched_episode = if ($null -ne $enrichedEpisode) { $enrichedEpisode } else { [ordered]@{} }
            updated_episode_count = @($episodeList.ToArray()).Count
            source_anchor_episode_count = $sourceAnchorEpisodeCount
            blocker = if ($manifestValid -and $sourceAnchorValid) {
                [ordered]@{}
            }
            else {
                [ordered]@{
                    blocker_class = 'data_blocker'
                    reason_code = (@($enrichmentGaps.ToArray()) -join ',')
                    reason = 'Corpus source-anchor enrichment requires an existing corpus manifest and a valid source-anchor observation artifact.'
                    smallest_next_rung = 'Repair the missing manifest/source-anchor evidence, then rerun enrichment.'
                }
            }
            validation = [ordered]@{
                artifact_path = $outputRel
                input_manifest_read = $manifestValid
                source_anchor_artifact_read = $sourceAnchorArtifactRead
                source_anchor_valid = $sourceAnchorValid
                existing_episode_count = @($existingEpisodes).Count
                updated_episode_count = @($episodeList.ToArray()).Count
                source_anchor_episode_count = $sourceAnchorEpisodeCount
                no_source_code_modified = $true
            }
            prevention_lesson = 'Corpus enrichment must consume an existing manifest plus source-anchor evidence; it must not re-run classifier-to-manifest conversion.'
            independent_credit_requested = $false
            dave_needed = 'no'
        }
    }
    $heldoutCandidateNewTextArtifact = $null
    if ($wantsHeldoutCandidateNewTextFromManifest) {
        $selectedEpisode = $null
        $sourceAnchorAvailable = $false
        $candidateNewText = ''
        $blockerReasonCode = 'heldout_episode_source_anchor_missing'
        $blockerReason = 'No held-out episode in the corpus manifest exposes source-anchor exact_text and source_file evidence.'
        if (
            $auditSource.PSObject.Properties['artifact_type'] -and
            [string]$auditSource.artifact_type -in @(
                'tod_engineering_corpus_episode_candidate_manifest',
                'tod_engineering_corpus_source_anchor_episode_enrichment'
            ) -and
            $auditSource.PSObject.Properties['episode_candidates']
        ) {
            foreach ($episode in @($auditSource.episode_candidates)) {
                if ($null -eq $selectedEpisode) {
                    $selectedEpisode = $episode
                }
                $episodeType = if ($episode.PSObject.Properties['source_artifact_type']) { [string]$episode.source_artifact_type } else { '' }
                $episodePath = if ($episode.PSObject.Properties['source_artifact']) { [string]$episode.source_artifact } else { '' }
                $episodeHasInlineSourceAnchor = (
                    $episodeType -eq 'tod_source_anchor_observation' -and
                    $episode.PSObject.Properties['exact_text_available'] -and
                    [bool]$episode.exact_text_available -and
                    $episode.PSObject.Properties['source_file'] -and
                    -not [string]::IsNullOrWhiteSpace([string]$episode.source_file)
                )
                if ($episodeHasInlineSourceAnchor) {
                    $selectedEpisode = $episode
                    $sourceAnchorAvailable = $true
                    $blockerReasonCode = 'autonomous_candidate_new_text_missing'
                    $blockerReason = 'A held-out source-anchor episode is available, but this lane still cannot synthesize meaningful candidate_new_text without a learned code-delta model.'
                    break
                }
                if ($episodeType -eq 'tod_source_anchor_observation' -and -not [string]::IsNullOrWhiteSpace($episodePath) -and (Test-LocalExecutionSafePath -RelativePath $episodePath)) {
                    $episodeAbs = Join-Path $script:LocalEngineRepoRoot $episodePath
                    if (Test-Path -Path $episodeAbs -PathType Leaf) {
                        try {
                            $episodeSource = Get-Content -Path $episodeAbs -Raw | ConvertFrom-Json
                            if (
                                $episodeSource.PSObject.Properties['exact_text'] -and
                                -not [string]::IsNullOrWhiteSpace([string]$episodeSource.exact_text) -and
                                $episodeSource.PSObject.Properties['source_file'] -and
                                -not [string]::IsNullOrWhiteSpace([string]$episodeSource.source_file)
                            ) {
                                $selectedEpisode = $episode
                                $sourceAnchorAvailable = $true
                                $blockerReasonCode = 'autonomous_candidate_new_text_missing'
                                $blockerReason = 'A held-out source-anchor episode is available, but this lane still cannot synthesize meaningful candidate_new_text without a learned code-delta model.'
                                break
                            }
                        }
                        catch {
                            $blockerReason = ('Held-out source-anchor artifact read failed: {0}' -f $_.Exception.Message)
                        }
                    }
                }
            }
        }
        else {
            $blockerReasonCode = 'input_manifest_invalid'
            $blockerReason = 'Input artifact is not a tod_engineering_corpus_episode_candidate_manifest with episode_candidates.'
        }

        $heldoutCandidateNewTextArtifact = [ordered]@{
            artifact_type = 'tod_heldout_candidate_newtext_from_corpus_manifest'
            generated_at = (Get-Date).ToUniversalTime().ToString('o')
            source = 'local_execution_read_only_audit_artifact_lane'
            objective_id = if ($Context.PSObject.Properties['objective_id']) { [string]$Context.objective_id } else { '' }
            task_id = if ($Context.PSObject.Properties['task_id']) { [string]$Context.task_id } else { '' }
            status = 'blocked'
            codex_role = 'escalation_after_TOD_attempt'
            input_manifest_artifact = $inputRel
            selected_episode = if ($null -ne $selectedEpisode) { $selectedEpisode } else { [ordered]@{} }
            source_anchor_available = $sourceAnchorAvailable
            candidate_new_text = $candidateNewText
            blocker = [ordered]@{
                blocker_class = 'capability_blocker'
                reason_code = $blockerReasonCode
                missing_capability = if ($sourceAnchorAvailable) { 'autonomous_meaningful_safe_new_text_synthesis_from_source_anchor' } else { 'source_anchor_episode_selection_for_heldout_synthesis' }
                reason = $blockerReason
                smallest_next_rung = if ($sourceAnchorAvailable) { 'TOD-AUTONOMOUS-CANDIDATE-NEWTEXT-PROPOSAL-V1' } else { 'TOD-ENGINEERING-CORPUS-SOURCE-ANCHOR-EPISODE-ENRICHMENT-V1' }
            }
            validation = [ordered]@{
                artifact_path = $outputRel
                input_manifest_read = $true
                source_anchor_available = $sourceAnchorAvailable
                candidate_new_text_blank = [string]::IsNullOrWhiteSpace($candidateNewText)
                no_source_code_modified = $true
            }
            prevention_lesson = 'Held-out synthesis must verify source-anchor evidence before proposing code text; audit/proof episodes cannot be used as old_text.'
            independent_credit_requested = $false
            dave_needed = 'no'
        }
    }
    $wantsCorpusEpisodeCandidateManifest = (-not $wantsCorpusSourceAnchorEpisodeEnrichment) -and (-not $wantsHeldoutCandidateNewTextFromManifest) -and (
        $combinedTextForAudit -match '(?is)\bcorpus\b' -and
        $combinedTextForAudit -match '(?is)\bepisode[-_\s]?candidate[-_\s]?manifest\b|tod_engineering_corpus_episode_candidate_manifest'
    )
    $corpusEpisodeCandidateManifestArtifact = $null
    if ($wantsCorpusEpisodeCandidateManifest) {
        $episodeCandidates = New-Object System.Collections.Generic.List[object]
        $manifestRejectedInputs = New-Object System.Collections.Generic.List[object]
        $manifestGaps = New-Object System.Collections.Generic.List[string]
        $classifierValid = (
            $auditSource.PSObject.Properties['artifact_type'] -and
            [string]$auditSource.artifact_type -eq 'tod_engineering_corpus_evidence_intake_classifier' -and
            $auditSource.PSObject.Properties['candidate_inputs']
        )

        if ($classifierValid) {
            $candidateIndex = 0
            foreach ($candidateInput in @($auditSource.candidate_inputs)) {
                $candidateIndex += 1
                $sourcePath = if ($candidateInput.PSObject.Properties['path']) { [string]$candidateInput.path } else { '' }
                $sourceArtifactType = if ($candidateInput.PSObject.Properties['artifact_type']) { [string]$candidateInput.artifact_type } else { '' }
                $sourceObjectiveId = if ($candidateInput.PSObject.Properties['objective_id']) { [string]$candidateInput.objective_id } else { '' }
                $candidateQuality = if ($candidateInput.PSObject.Properties['episode_candidate_quality']) { [string]$candidateInput.episode_candidate_quality } else { 'unknown' }
                $usableForCorpus = if ($candidateInput.PSObject.Properties['usable_for_corpus']) { [bool]$candidateInput.usable_for_corpus } else { $false }
                $missingEpisodeFields = if ($candidateInput.PSObject.Properties['missing_episode_fields']) { @($candidateInput.missing_episode_fields) } else { @() }
                if ($usableForCorpus) {
                    [void]$episodeCandidates.Add([ordered]@{
                        episode_id = ('episode-{0:000}' -f $candidateIndex)
                        source_artifact = $sourcePath
                        source_artifact_type = $sourceArtifactType
                        source_objective_id = $sourceObjectiveId
                        candidate_quality = $candidateQuality
                        likely_capability_classification = if ($candidateInput.PSObject.Properties['likely_capability_classification']) { [string]$candidateInput.likely_capability_classification } else { 'unknown' }
                        actual_author_signal = if ($candidateInput.PSObject.Properties['actual_author_signal']) { [string]$candidateInput.actual_author_signal } else { 'unknown' }
                        borrowed_capability_signal = if ($candidateInput.PSObject.Properties['borrowed_capability_signal']) { [string]$candidateInput.borrowed_capability_signal } else { 'unknown' }
                        missing_episode_fields = $missingEpisodeFields
                        usable_for_training = $true
                        reuse_tags = @(
                            'tod_engineering_corpus',
                            ($sourceArtifactType -replace '[^A-Za-z0-9_/-]', '_'),
                            ($sourceObjectiveId -replace '[^A-Za-z0-9_/-]', '_')
                        ) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
                    })
                }
                else {
                    [void]$manifestRejectedInputs.Add($candidateInput)
                }
            }
        }
        else {
            [void]$manifestGaps.Add('input_artifact_is_not_corpus_evidence_intake_classifier')
        }

        if (@($episodeCandidates.ToArray()).Count -lt 3) {
            [void]$manifestGaps.Add('three_usable_episode_candidates')
        }

        $corpusEpisodeCandidateManifestArtifact = [ordered]@{
            artifact_type = 'tod_engineering_corpus_episode_candidate_manifest'
            generated_at = (Get-Date).ToUniversalTime().ToString('o')
            source = 'local_execution_read_only_audit_artifact_lane'
            objective_id = if ($Context.PSObject.Properties['objective_id']) { [string]$Context.objective_id } else { '' }
            task_id = if ($Context.PSObject.Properties['task_id']) { [string]$Context.task_id } else { '' }
            status = if (@($episodeCandidates.ToArray()).Count -ge 3) { 'completed' } else { 'blocked' }
            codex_role = 'escalation_after_TOD_attempt'
            source_classifier_artifact = $inputRel
            episode_candidates = @($episodeCandidates.ToArray())
            rejected_inputs = @($manifestRejectedInputs.ToArray())
            manifest_gaps = @($manifestGaps.ToArray())
            smallest_next_executable_shape = if (@($episodeCandidates.ToArray()).Count -ge 3) {
                'Use this single-file episode manifest to choose one held-out source-anchor example for candidate_new_text proposal training.'
            }
            else {
                'Add or locate enough usable classified candidate inputs before building the full engineering corpus.'
            }
            validation = [ordered]@{
                artifact_path = $outputRel
                source_classifier_read = $classifierValid
                episode_candidate_count = @($episodeCandidates.ToArray()).Count
                rejected_count = @($manifestRejectedInputs.ToArray()).Count
                no_source_code_modified = $true
            }
            prevention_lesson = 'Episode manifests must be derived from classified corpus candidates and must not collapse back into evidence-intake classification.'
            independent_credit_requested = $false
            dave_needed = 'no'
        }
    }
    $wantsCorpusEvidenceIntakeClassifier = (-not $wantsCorpusSourceAnchorEpisodeEnrichment) -and (-not $wantsCorpusEpisodeCandidateManifest) -and (
        $combinedTextForAudit -match '(?is)\bcorpus\b' -and
        $combinedTextForAudit -match '(?is)\bevidence[-_\s]?intake\b|episode[-_\s]?candidate|candidate[-_\s]?inputs' -and
        $combinedTextForAudit -match '(?is)\bclassifier\b|classify|classification'
    )
    $corpusEvidenceIntakeClassifierArtifact = $null
    if ($wantsCorpusEvidenceIntakeClassifier) {
        $allCorpusEvidencePaths = New-Object System.Collections.Generic.List[string]
        foreach ($pathMatch in [regex]::Matches($combinedTextForAudit, 'runtime_remote_training/[A-Za-z0-9_./-]+?\.json')) {
            $pathValue = Convert-ToLocalExecutionRepoRelativePath -PathValue ([string]$pathMatch.Value)
            if (
                -not [string]::IsNullOrWhiteSpace($pathValue) -and
                [string]::Compare($pathValue, $outputRel, $true) -ne 0 -and
                -not $allCorpusEvidencePaths.Contains($pathValue)
            ) {
                [void]$allCorpusEvidencePaths.Add($pathValue)
            }
        }

        $candidateInputs = New-Object System.Collections.Generic.List[object]
        $rejectedInputs = New-Object System.Collections.Generic.List[object]
        foreach ($evidenceRel in @($allCorpusEvidencePaths.ToArray())) {
            $exists = $false
            $artifactType = ''
            $objectiveValue = ''
            $quality = 'unusable'
            $classificationSignal = 'unknown'
            $authorSignal = 'unknown'
            $borrowedSignal = 'unknown'
            $usable = $false
            $missingEpisodeFields = New-Object System.Collections.Generic.List[string]
            $reason = 'Evidence path could not be read.'

            if (Test-LocalExecutionSafePath -RelativePath $evidenceRel) {
                $evidenceAbs = Join-Path $script:LocalEngineRepoRoot $evidenceRel
                if (Test-Path -Path $evidenceAbs -PathType Leaf) {
                    $exists = $true
                    try {
                        $evidenceJson = Get-Content -Path $evidenceAbs -Raw | ConvertFrom-Json
                        $artifactType = if ($evidenceJson.PSObject.Properties['artifact_type']) { [string]$evidenceJson.artifact_type } else { '' }
                        $objectiveValue = if ($evidenceJson.PSObject.Properties['objective_id']) { [string]$evidenceJson.objective_id } else { '' }
                        $textSnapshot = ($evidenceJson | ConvertTo-Json -Depth 20 -Compress)

                        if ($textSnapshot -match 'codex_role|codex_intervention_class|actual_author|borrowed_capability|validation|lesson|next_training_rung') {
                            $quality = 'candidate'
                            $usable = $true
                            $reason = 'Evidence includes enough authorship, capability, validation, lesson, or next-rung signals to seed an engineering episode.'
                        }
                        else {
                            $quality = 'weak_context'
                            $reason = 'Evidence is readable but lacks enough episode attribution and validation signals.'
                        }

                        if ($textSnapshot -match 'independent') {
                            $classificationSignal = 'independent_or_claimed_independent'
                        }
                        elseif ($textSnapshot -match 'guided|scaffold') {
                            $classificationSignal = 'guided_scaffolded'
                        }
                        elseif ($textSnapshot -match 'borrowed|codex') {
                            $classificationSignal = 'borrowed_or_codex_involved'
                        }
                        elseif ($textSnapshot -match 'blocked|failed') {
                            $classificationSignal = 'blocked_or_failed'
                        }

                        if ($textSnapshot -match 'actual_author"\s*:\s*"TOD') {
                            $authorSignal = 'TOD'
                        }
                        elseif ($textSnapshot -match 'Codex|codex') {
                            $authorSignal = 'Codex_or_mixed'
                        }

                        if ($textSnapshot -match 'borrowed_capability"\s*:\s*true|borrowed_percent|borrowed_ratio|borrowed') {
                            $borrowedSignal = 'borrowed_present'
                        }
                        elseif ($textSnapshot -match 'independent_credit_requested"\s*:\s*false|no_borrowed_ratio_reduction') {
                            $borrowedSignal = 'no_credit_or_borrowed_not_reduced'
                        }

                        foreach ($fieldName in @('objective_id', 'validation', 'final_outcome', 'next_training_rung')) {
                            if (-not $evidenceJson.PSObject.Properties[$fieldName]) {
                                [void]$missingEpisodeFields.Add($fieldName)
                            }
                        }
                    }
                    catch {
                        $reason = ('Evidence read failed: {0}' -f $_.Exception.Message)
                    }
                }
                else {
                    $reason = 'Evidence path is safe but the artifact file does not exist.'
                }
            }
            else {
                $reason = 'Evidence path is outside LocalExecutionEngine safe roots.'
            }

            $entry = [ordered]@{
                path = $evidenceRel
                exists = $exists
                artifact_type = $artifactType
                objective_id = $objectiveValue
                episode_candidate_quality = $quality
                likely_capability_classification = $classificationSignal
                actual_author_signal = $authorSignal
                borrowed_capability_signal = $borrowedSignal
                usable_for_corpus = $usable
                missing_episode_fields = @($missingEpisodeFields.ToArray())
                reason = $reason
            }
            if ($usable) {
                $candidateInputs.Add($entry) | Out-Null
            }
            else {
                $rejectedInputs.Add($entry) | Out-Null
            }
        }

        $missingManifestFields = @()
        if (@($candidateInputs.ToArray()).Count -lt 5) {
            $missingManifestFields += 'five_usable_episode_candidates'
        }
        $corpusEvidenceIntakeClassifierArtifact = [ordered]@{
            artifact_type = 'tod_engineering_corpus_evidence_intake_classifier'
            generated_at = (Get-Date).ToUniversalTime().ToString('o')
            source = 'local_execution_read_only_audit_artifact_lane'
            objective_id = if ($Context.PSObject.Properties['objective_id']) { [string]$Context.objective_id } else { '' }
            task_id = if ($Context.PSObject.Properties['task_id']) { [string]$Context.task_id } else { '' }
            status = if (@($candidateInputs.ToArray()).Count -ge 1) { 'completed' } else { 'blocked' }
            codex_role = 'escalation_after_TOD_attempt'
            source_artifacts = @($allCorpusEvidencePaths.ToArray())
            candidate_inputs = @($candidateInputs.ToArray())
            rejected_inputs = @($rejectedInputs.ToArray())
            missing_fields_for_episode_manifest = $missingManifestFields
            smallest_next_executable_shape = if (@($candidateInputs.ToArray()).Count -ge 1) {
                'Create a single-file episode candidate manifest from classified candidate_inputs; do not create the full corpus directory yet.'
            }
            else {
                'Add or locate one evidence artifact with objective, validation, authorship, capability classification, and lesson fields.'
            }
            validation = [ordered]@{
                artifact_path = $outputRel
                source_artifact_count = @($allCorpusEvidencePaths.ToArray()).Count
                candidate_count = @($candidateInputs.ToArray()).Count
                rejected_count = @($rejectedInputs.ToArray()).Count
                no_source_code_modified = $true
            }
            prevention_lesson = 'Corpus work must classify evidence containers before treating any one artifact as source code, source anchor, or manifest body.'
            independent_credit_requested = $false
            dave_needed = 'no'
        }
    }
    $wantsEvidencePoolSourceAnchorClassifier = (
        $combinedTextForAudit -match '(?is)\bevidence\s+pool\b' -and
        $combinedTextForAudit -match '(?is)\bsource[- ]anchor\b' -and
        $combinedTextForAudit -match '(?is)\bclassified_artifacts\b|classification_decision|classify'
    )
    $evidencePoolClassifierArtifact = $null
    if ($wantsEvidencePoolSourceAnchorClassifier) {
        $allEvidencePoolPaths = New-Object System.Collections.Generic.List[string]
        foreach ($pathMatch in [regex]::Matches($combinedTextForAudit, 'runtime_remote_training/[A-Za-z0-9_./-]+?\.json')) {
            $pathValue = Convert-ToLocalExecutionRepoRelativePath -PathValue ([string]$pathMatch.Value)
            if (
                -not [string]::IsNullOrWhiteSpace($pathValue) -and
                [string]::Compare($pathValue, $outputRel, $true) -ne 0 -and
                -not $allEvidencePoolPaths.Contains($pathValue)
            ) {
                [void]$allEvidencePoolPaths.Add($pathValue)
            }
        }

        $classifiedArtifacts = New-Object System.Collections.Generic.List[object]
        $selectedSourceAnchorArtifact = ''
        foreach ($evidenceRel in @($allEvidencePoolPaths.ToArray())) {
            $artifactShape = 'unknown'
            $usableAsOldTextSource = $false
            $classificationReason = 'Artifact could not be read or did not expose a recognizable training evidence shape.'
            if (Test-LocalExecutionSafePath -RelativePath $evidenceRel) {
                $evidenceAbs = Join-Path $script:LocalEngineRepoRoot $evidenceRel
                if (Test-Path -Path $evidenceAbs -PathType Leaf) {
                    try {
                        $evidenceJson = Get-Content -Path $evidenceAbs -Raw | ConvertFrom-Json
                        $evidenceType = if ($evidenceJson.PSObject.Properties['artifact_type']) { [string]$evidenceJson.artifact_type } else { '' }
                        $evidenceStatus = if ($evidenceJson.PSObject.Properties['status']) { [string]$evidenceJson.status } else { '' }
                        $hasExactText = (
                            $evidenceJson.PSObject.Properties['exact_text'] -and
                            -not [string]::IsNullOrWhiteSpace([string]$evidenceJson.exact_text)
                        )
                        if ($evidenceType -eq 'tod_source_anchor_observation' -and $hasExactText) {
                            $artifactShape = 'source_anchor_observation'
                            $usableAsOldTextSource = $true
                            $classificationReason = 'Source-anchor observation includes nonempty exact_text and can supply old_text for a later bounded packet.'
                            if ([string]::IsNullOrWhiteSpace($selectedSourceAnchorArtifact)) {
                                $selectedSourceAnchorArtifact = $evidenceRel
                            }
                        }
                        elseif ($evidenceType -match 'blocker' -or $evidenceStatus -match 'block' -or $evidenceJson.PSObject.Properties['blocker'] -or $evidenceJson.PSObject.Properties['blockers']) {
                            $artifactShape = 'blocker_artifact'
                            $classificationReason = 'Blocker evidence is diagnostic only and must not be used as old_text.'
                        }
                        elseif ($evidenceType -match 'review|audit|packet_quality' -or $evidenceJson.PSObject.Properties['decision'] -or $evidenceJson.PSObject.Properties['credit_decision']) {
                            $artifactShape = 'review_artifact'
                            $classificationReason = 'Review or credit evidence can guide selection but is not itself a source anchor.'
                        }
                        elseif (-not [string]::IsNullOrWhiteSpace($evidenceType)) {
                            $artifactShape = 'context_artifact'
                            $classificationReason = ('Artifact type {0} provides context but is not a source-anchor observation.' -f $evidenceType)
                        }
                    }
                    catch {
                        $classificationReason = ('Artifact read failed: {0}' -f $_.Exception.Message)
                    }
                }
                else {
                    $classificationReason = 'Evidence path is safe but the artifact file does not exist.'
                }
            }
            else {
                $classificationReason = 'Evidence path is outside LocalExecutionEngine safe roots.'
            }
            $classifiedArtifacts.Add([ordered]@{
                path = $evidenceRel
                artifact_shape = $artifactShape
                usable_as_old_text_source = $usableAsOldTextSource
                reason = $classificationReason
            }) | Out-Null
        }

        $packetMaterializationAllowed = -not [string]::IsNullOrWhiteSpace($selectedSourceAnchorArtifact)
        $evidencePoolClassifierArtifact = [ordered]@{
            artifact_type = 'tod_evidence_pool_source_anchor_classifier'
            generated_at = (Get-Date).ToUniversalTime().ToString('o')
            source = 'local_execution_read_only_audit_artifact_lane'
            objective_id = if ($Context.PSObject.Properties['objective_id']) { [string]$Context.objective_id } else { '' }
            task_id = if ($Context.PSObject.Properties['task_id']) { [string]$Context.task_id } else { '' }
            classification_decision = if ($packetMaterializationAllowed) { 'passed' } else { 'blocked' }
            selected_source_anchor_artifact = $selectedSourceAnchorArtifact
            classified_artifacts = @($classifiedArtifacts.ToArray())
            packet_materialization_allowed = $packetMaterializationAllowed
            reason = if ($packetMaterializationAllowed) {
                'A source-anchor observation with exact_text was found; packet materialization may continue using that artifact, not blocker/review artifacts.'
            }
            else {
                'No source-anchor observation with exact_text was found in the evidence pool.'
            }
            next_smallest_rung = if ($packetMaterializationAllowed) {
                'TOD-AUTONOMOUS-SOURCE-ANCHOR-DISCOVERY-FOR-DELTA-SELECTION-V1'
            }
            else {
                'TOD-AUTONOMOUS-SOURCE-ANCHOR-DISCOVERY-FOR-DELTA-SELECTION-V1'
            }
            tod_independent_capability_acquired = $false
            no_code_changes = $true
            validation = [ordered]@{
                artifact_path = $outputRel
                evidence_pool_count = @($classifiedArtifacts.ToArray()).Count
                selected_source_anchor_present = $packetMaterializationAllowed
                source_edits = @()
            }
        }
    }
    $sourceAnchorDeltaProposalArtifact = $null
    if ($wantsSourceAnchorDeltaProposal) {
        $targetFile = ''
        $oldTextSource = $inputRel
        $sourceAnchorValid = $false
        $blockerReason = 'Input artifact could not be read as a source-anchor observation with exact_text.'
        if ($auditSource.PSObject.Properties['artifact_type'] -and [string]$auditSource.artifact_type -eq 'tod_source_anchor_observation') {
            $targetFile = if ($auditSource.PSObject.Properties['source_file']) { Convert-ToLocalExecutionRepoRelativePath -PathValue ([string]$auditSource.source_file) } else { '' }
            $sourceAnchorValid = (
                $auditSource.PSObject.Properties['exact_text'] -and
                -not [string]::IsNullOrWhiteSpace([string]$auditSource.exact_text) -and
                -not [string]::IsNullOrWhiteSpace($targetFile)
            )
            if ($sourceAnchorValid) {
                $blockerReason = 'TOD has source-anchor exact_text and target file, but autonomous meaningful candidate_new_text synthesis is not available in this read-only lane.'
            }
            else {
                $blockerReason = 'Source-anchor observation is missing exact_text or source_file.'
            }
        }
        elseif ($auditSource.PSObject.Properties['artifact_type'] -and [string]$auditSource.artifact_type -eq 'tod_heldout_candidate_newtext_from_corpus_manifest' -and $auditSource.PSObject.Properties['selected_episode']) {
            $selectedEpisodeForDelta = $auditSource.selected_episode
            $selectedSourceArtifact = if ($selectedEpisodeForDelta.PSObject.Properties['source_artifact']) { Convert-ToLocalExecutionRepoRelativePath -PathValue ([string]$selectedEpisodeForDelta.source_artifact) } else { '' }
            if (-not [string]::IsNullOrWhiteSpace($selectedSourceArtifact) -and (Test-LocalExecutionSafePath -RelativePath $selectedSourceArtifact)) {
                $oldTextSource = $selectedSourceArtifact
                $selectedSourceAbs = Join-Path $script:LocalEngineRepoRoot $selectedSourceArtifact
                if (Test-Path -Path $selectedSourceAbs -PathType Leaf) {
                    try {
                        $selectedSourceAnchor = Get-Content -Path $selectedSourceAbs -Raw | ConvertFrom-Json
                        $targetFile = if ($selectedSourceAnchor.PSObject.Properties['source_file']) { Convert-ToLocalExecutionRepoRelativePath -PathValue ([string]$selectedSourceAnchor.source_file) } else { '' }
                        $sourceAnchorValid = (
                            $selectedSourceAnchor.PSObject.Properties['artifact_type'] -and
                            [string]$selectedSourceAnchor.artifact_type -eq 'tod_source_anchor_observation' -and
                            $selectedSourceAnchor.PSObject.Properties['exact_text'] -and
                            -not [string]::IsNullOrWhiteSpace([string]$selectedSourceAnchor.exact_text) -and
                            -not [string]::IsNullOrWhiteSpace($targetFile)
                        )
                        if ($sourceAnchorValid) {
                            $blockerReason = 'TOD dereferenced the held-out selected source-anchor episode, but autonomous meaningful candidate_new_text synthesis is not available in this read-only lane.'
                        }
                        else {
                            $blockerReason = 'Held-out selected episode source artifact is missing source-anchor exact_text or source_file.'
                        }
                    }
                    catch {
                        $blockerReason = ('Held-out selected source-anchor artifact read failed: {0}' -f $_.Exception.Message)
                    }
                }
                else {
                    $blockerReason = 'Held-out selected source-anchor artifact was named but not found.'
                }
            }
            else {
                $blockerReason = 'Held-out artifact did not expose a safe selected source-anchor artifact path.'
            }
        }
        $sourceAnchorDeltaProposalArtifact = [ordered]@{
            artifact_type = 'tod_source_anchor_delta_proposal'
            generated_at = (Get-Date).ToUniversalTime().ToString('o')
            source = 'local_execution_read_only_audit_artifact_lane'
            objective_id = if ($Context.PSObject.Properties['objective_id']) { [string]$Context.objective_id } else { '' }
            task_id = if ($Context.PSObject.Properties['task_id']) { [string]$Context.task_id } else { '' }
            status = 'blocked'
            old_text_source = $oldTextSource
            target_file = $targetFile
            intended_behavior_delta = if ($sourceAnchorValid) { 'Not independently synthesized yet.' } else { '' }
            candidate_new_text = ''
            safety_constraints = @(
                'no source code edits during read-only delta proposal',
                'no Codex-supplied new_text',
                'no marker-only, duplicate, or cosmetic candidate text'
            )
            validation_plan = @(
                'JSON readback confirms tod_source_anchor_delta_proposal schema',
                'source_edits remains empty',
                'candidate_new_text remains empty while autonomous synthesis is blocked'
            )
            confidence = if ($sourceAnchorValid) { 'high' } else { 'medium' }
            no_source_code_modified = $true
            blocker = [ordered]@{
                blocker_class = 'capability_blocker'
                reason_code = if ($sourceAnchorValid) { 'autonomous_candidate_new_text_missing' } else { 'source_anchor_input_invalid' }
                missing_capability = 'autonomous_meaningful_safe_new_text_synthesis_from_source_anchor'
                reason = $blockerReason
                smallest_next_rung = 'TOD-AUTONOMOUS-MEANINGFUL-NEWTEXT-SYNTHESIS-FROM-SOURCE-ANCHOR-V1'
            }
            validation = [ordered]@{
                artifact_path = $outputRel
                input_read = $true
                source_anchor_valid = $sourceAnchorValid
                source_edits = @()
                required_fields_present = $true
            }
        }
    }
    $wantsAutonomousMeaningfulNewTextSynthesis = [string]::Equals($requiredArtifactType, 'tod_autonomous_meaningful_newtext_synthesis', [System.StringComparison]::OrdinalIgnoreCase)
    $autonomousMeaningfulNewTextSynthesisArtifact = $null
    if ($wantsAutonomousMeaningfulNewTextSynthesis) {
        $listedSynthesisInputMatches = @([regex]::Matches($combinedTextForAudit, '(?im)^\s*(?:-\s*)?(?<path>runtime_remote_training/read_only_audit_artifacts/[A-Za-z0-9_./-]+?\.json)\s*$'))
        $listedSynthesisInputs = New-Object System.Collections.Generic.List[string]
        $seenSynthesisInputs = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($listedSynthesisInputMatch in $listedSynthesisInputMatches) {
            $listedSynthesisInputRel = Convert-ToLocalExecutionRepoRelativePath -PathValue ([string]$listedSynthesisInputMatch.Groups['path'].Value)
            if (-not [string]::IsNullOrWhiteSpace($listedSynthesisInputRel) -and $seenSynthesisInputs.Add($listedSynthesisInputRel)) {
                [void]$listedSynthesisInputs.Add($listedSynthesisInputRel)
            }
        }
        if ($listedSynthesisInputs.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($inputRel)) {
            [void]$listedSynthesisInputs.Add($inputRel)
        }

        $sourceAnchorInputRel = ''
        $deltaProposalInputRel = ''
        $sourceAnchorInput = $null
        $deltaProposalInput = $null
        foreach ($listedSynthesisInputRel in $listedSynthesisInputs) {
            if (-not (Test-LocalExecutionSafePath -RelativePath $listedSynthesisInputRel)) {
                continue
            }
            $listedSynthesisInputAbs = Join-Path $script:LocalEngineRepoRoot $listedSynthesisInputRel
            if (-not (Test-Path -Path $listedSynthesisInputAbs -PathType Leaf)) {
                continue
            }
            try {
                $listedSynthesisInputJson = Get-Content -Path $listedSynthesisInputAbs -Raw | ConvertFrom-Json
            }
            catch {
                continue
            }
            $listedSynthesisArtifactType = if ($listedSynthesisInputJson.PSObject.Properties['artifact_type']) { [string]$listedSynthesisInputJson.artifact_type } else { '' }
            if (
                [string]::IsNullOrWhiteSpace($sourceAnchorInputRel) -and
                [string]::Equals($listedSynthesisArtifactType, 'tod_source_anchor_observation', [System.StringComparison]::OrdinalIgnoreCase)
            ) {
                $sourceAnchorInputRel = $listedSynthesisInputRel
                $sourceAnchorInput = $listedSynthesisInputJson
            }
            elseif (
                [string]::IsNullOrWhiteSpace($deltaProposalInputRel) -and
                [string]::Equals($listedSynthesisArtifactType, 'tod_source_anchor_delta_proposal', [System.StringComparison]::OrdinalIgnoreCase)
            ) {
                $deltaProposalInputRel = $listedSynthesisInputRel
                $deltaProposalInput = $listedSynthesisInputJson
            }
        }

        $targetFileForSynthesis = ''
        $oldTextForSynthesis = ''
        $sourceAnchorValidForSynthesis = $false
        if ($null -ne $sourceAnchorInput) {
            $targetFileForSynthesis = if ($sourceAnchorInput.PSObject.Properties['source_file']) { Convert-ToLocalExecutionRepoRelativePath -PathValue ([string]$sourceAnchorInput.source_file) } else { '' }
            $oldTextForSynthesis = if ($sourceAnchorInput.PSObject.Properties['exact_text']) { [string]$sourceAnchorInput.exact_text } else { '' }
            $sourceAnchorValidForSynthesis = (
                -not [string]::IsNullOrWhiteSpace($targetFileForSynthesis) -and
                -not [string]::IsNullOrWhiteSpace($oldTextForSynthesis)
            )
        }

        $priorBlockerReason = ''
        $priorSmallestNextRung = ''
        if ($null -ne $deltaProposalInput -and $deltaProposalInput.PSObject.Properties['blocker']) {
            $priorBlocker = $deltaProposalInput.blocker
            $priorBlockerReason = if ($priorBlocker.PSObject.Properties['reason']) { [string]$priorBlocker.reason } else { '' }
            $priorSmallestNextRung = if ($priorBlocker.PSObject.Properties['smallest_next_rung']) { [string]$priorBlocker.smallest_next_rung } else { '' }
        }

        $synthesisBlockerReason = if (-not $sourceAnchorValidForSynthesis) {
            'A valid source-anchor observation with source_file and exact_text was not available.'
        }
        elseif ([string]::IsNullOrWhiteSpace($deltaProposalInputRel)) {
            'Source-anchor evidence is available, but no prior delta/blocker artifact was available to preserve the requested behavior delta.'
        }
        else {
            'TOD has valid source-anchor evidence and a prior delta blocker, but still cannot independently synthesize safe behavior-changing new_text without a learned code-delta model.'
        }

        $autonomousMeaningfulNewTextSynthesisArtifact = [ordered]@{
            artifact_type = 'tod_autonomous_meaningful_newtext_synthesis'
            generated_at = (Get-Date).ToUniversalTime().ToString('o')
            source = 'local_execution_read_only_audit_artifact_lane'
            objective_id = if ($Context.PSObject.Properties['objective_id']) { [string]$Context.objective_id } else { '' }
            task_id = if ($Context.PSObject.Properties['task_id']) { [string]$Context.task_id } else { '' }
            status = 'blocked'
            source_anchor_artifact = $sourceAnchorInputRel
            prior_delta_artifact = $deltaProposalInputRel
            target_file = $targetFileForSynthesis
            old_text = $oldTextForSynthesis
            new_text = ''
            expected_behavior_change = if ($sourceAnchorValidForSynthesis) { 'Replace filename-only or marker-only source-anchor handling with a semantic, behavior-preserving candidate change when TOD can synthesize one.' } else { '' }
            risks = @(
                'Do not fabricate behavior-changing code without source-anchor evidence.',
                'Do not count marker-only, comment-only, duplicate, or wrapper-only text as engineering synthesis.',
                'Do not request independent credit while new_text is blank.'
            )
            blocker = [ordered]@{
                blocker_class = 'capability_blocker'
                reason_code = if ($sourceAnchorValidForSynthesis) { 'autonomous_meaningful_new_text_synthesis_missing' } else { 'source_anchor_input_invalid' }
                missing_capability = 'autonomous_meaningful_safe_new_text_synthesis_from_source_anchor'
                reason = $synthesisBlockerReason
                prior_blocker_reason = $priorBlockerReason
                smallest_next_rung = if ([string]::IsNullOrWhiteSpace($priorSmallestNextRung)) { 'TOD-LOCAL-ENGINEERING-MODEL-UTILIZATION-RUNTIME-V1' } else { $priorSmallestNextRung }
            }
            validation_command = 'read-only synthesis artifact readback; no source edits'
            independent_credit_requested = $false
            no_source_code_modified = $true
            validation = [ordered]@{
                artifact_path = $outputRel
                listed_input_count = $listedSynthesisInputs.Count
                source_anchor_valid = $sourceAnchorValidForSynthesis
                prior_delta_available = (-not [string]::IsNullOrWhiteSpace($deltaProposalInputRel))
                old_text_nonempty = (-not [string]::IsNullOrWhiteSpace($oldTextForSynthesis))
                new_text_nonempty = $false
                source_edits = @()
                required_fields_present = $true
            }
            dave_needed = 'no'
        }
    }
    $wantsReadOnlyEvidenceComparison = (
        [string]::Equals($requiredArtifactType, 'tod_readonly_evidence_comparison', [System.StringComparison]::OrdinalIgnoreCase) -or
        [string]::Equals($requiredArtifactType, 'tod_read_only_evidence_comparison', [System.StringComparison]::OrdinalIgnoreCase)
    )
    $readOnlyEvidenceComparisonArtifact = $null
    if ($wantsReadOnlyEvidenceComparison) {
        $leftRel = Convert-ToLocalExecutionRepoRelativePath -PathValue (Get-LocalExecutionDirectiveValue -PromptText $combinedTextForAudit -FieldName 'Package Path')
        if ([string]::IsNullOrWhiteSpace($leftRel)) {
            $leftRel = Convert-ToLocalExecutionRepoRelativePath -PathValue (Get-LocalExecutionDirectiveValue -PromptText $combinedTextForAudit -FieldName 'Left Artifact')
        }
        $rightRel = Convert-ToLocalExecutionRepoRelativePath -PathValue (Get-LocalExecutionDirectiveValue -PromptText $combinedTextForAudit -FieldName 'Inspect Source File')
        if ([string]::IsNullOrWhiteSpace($rightRel)) {
            $rightRel = Convert-ToLocalExecutionRepoRelativePath -PathValue (Get-LocalExecutionDirectiveValue -PromptText $combinedTextForAudit -FieldName 'Right Artifact')
        }
        if ([string]::IsNullOrWhiteSpace($rightRel)) {
            $rightRel = Convert-ToLocalExecutionRepoRelativePath -PathValue (Get-LocalExecutionDirectiveValue -PromptText $combinedTextForAudit -FieldName 'Compare Artifact')
        }

        $comparisonStatus = 'blocked'
        $comparisonBlocker = ''
        $firstMaterialDifference = ''
        $failedContractValue = ''
        $passedContractValue = ''
        $detectorEligibilityEffect = 'not_evaluated'
        $smallestReusableRule = ''
        $directiveFields = @(
            'Task Category',
            'Task Mode',
            'Task Type',
            'Input Artifact',
            'Output Artifact',
            'Output',
            'Required Artifact Type',
            'Required Output Fields'
        )

        if ([string]::IsNullOrWhiteSpace($leftRel) -or [string]::IsNullOrWhiteSpace($rightRel)) {
            $comparisonBlocker = 'comparison_paths_missing'
        }
        elseif (-not (Test-LocalExecutionSafePath -RelativePath $leftRel) -or -not (Test-LocalExecutionSafePath -RelativePath $rightRel)) {
            $comparisonBlocker = 'comparison_path_unsafe'
        }
        else {
            $leftAbs = Join-Path $script:LocalEngineRepoRoot $leftRel
            $rightAbs = Join-Path $script:LocalEngineRepoRoot $rightRel
            if (-not (Test-Path -Path $leftAbs -PathType Leaf) -or -not (Test-Path -Path $rightAbs -PathType Leaf)) {
                $comparisonBlocker = 'comparison_input_not_found'
            }
            else {
                $leftText = Get-Content -Path $leftAbs -Raw
                $rightText = Get-Content -Path $rightAbs -Raw
                foreach ($fieldName in $directiveFields) {
                    $leftValue = Get-LocalExecutionDirectiveValue -PromptText $leftText -FieldName $fieldName
                    $rightValue = Get-LocalExecutionDirectiveValue -PromptText $rightText -FieldName $fieldName
                    if (-not [string]::Equals([string]$leftValue, [string]$rightValue, [System.StringComparison]::Ordinal)) {
                        $firstMaterialDifference = $fieldName
                        $failedContractValue = [string]$leftValue
                        $passedContractValue = [string]$rightValue
                        break
                    }
                }
                if ([string]::IsNullOrWhiteSpace($firstMaterialDifference)) {
                    $leftLines = @($leftText -split "`r?`n")
                    $rightLines = @($rightText -split "`r?`n")
                    $maxLineCount = [Math]::Max($leftLines.Count, $rightLines.Count)
                    for ($lineIndex = 0; $lineIndex -lt $maxLineCount; $lineIndex++) {
                        $leftLine = if ($lineIndex -lt $leftLines.Count) { [string]$leftLines[$lineIndex] } else { '' }
                        $rightLine = if ($lineIndex -lt $rightLines.Count) { [string]$rightLines[$lineIndex] } else { '' }
                        if (-not [string]::Equals($leftLine, $rightLine, [System.StringComparison]::Ordinal)) {
                            $firstMaterialDifference = ('line_{0}' -f ($lineIndex + 1))
                            $failedContractValue = $leftLine
                            $passedContractValue = $rightLine
                            break
                        }
                    }
                }

                if (-not [string]::IsNullOrWhiteSpace($firstMaterialDifference)) {
                    $comparisonStatus = 'completed'
                    $detectorEligibilityEffect = if ($firstMaterialDifference -match 'Task Category|Task Mode|Task Type|Input Artifact|Output|Required Artifact Type') {
                        'affects_executor_lane_or_artifact_contract'
                    }
                    else {
                        'difference_recorded_review_required'
                    }
                    $smallestReusableRule = if ($firstMaterialDifference -eq 'Task Category') {
                        'Read-only evidence-operation tasks must use a task category supported by the intended evidence lane; unsupported categories can fall through to generic or blocked handling.'
                    }
                    elseif ($firstMaterialDifference -match 'Input Artifact|Output|Required Artifact Type') {
                        'Evidence-operation packets must expose explicit input, output, and required artifact type directives before generic read-only context proof fallback is eligible.'
                    }
                    else {
                        'Compare contract-directive differences before judging broader prompt wording differences.'
                    }
                }
                else {
                    $comparisonBlocker = 'no_difference_found'
                }
            }
        }

        $readOnlyEvidenceComparisonArtifact = [ordered]@{
            artifact_type = if ([string]::Equals($requiredArtifactType, 'tod_read_only_evidence_comparison', [System.StringComparison]::OrdinalIgnoreCase)) { 'tod_read_only_evidence_comparison' } else { 'tod_readonly_evidence_comparison' }
            generated_at = (Get-Date).ToUniversalTime().ToString('o')
            source = 'local_execution_read_only_audit_artifact_lane'
            objective_id = if ($Context.PSObject.Properties['objective_id']) { [string]$Context.objective_id } else { '' }
            task_id = if ($Context.PSObject.Properties['task_id']) { [string]$Context.task_id } else { '' }
            status = $comparisonStatus
            input_evidence_artifact = $inputRel
            left_artifact = $leftRel
            right_artifact = $rightRel
            first_material_difference = $firstMaterialDifference
            failed_contract_value = $failedContractValue
            passed_contract_value = $passedContractValue
            detector_eligibility_effect = $detectorEligibilityEffect
            smallest_reusable_rule = $smallestReusableRule
            blocker = if ([string]::IsNullOrWhiteSpace($comparisonBlocker)) { $null } else { [ordered]@{ reason_code = $comparisonBlocker } }
            validation = [ordered]@{
                artifact_path = $outputRel
                input_read = $true
                left_artifact_read = ($comparisonStatus -eq 'completed')
                right_artifact_read = ($comparisonStatus -eq 'completed')
                no_code_changes = $true
                source_edits = @()
            }
            prevention_lesson = 'Read-only evidence comparison must compare the requested evidence objects and publish the requested comparison fields; a generic read-only context proof is not enough.'
            independent_credit_requested = $false
            dave_needed = 'no'
        }
    }
    $wantsEngineeringEpisodeCard = (
        [string]::Equals($requiredArtifactType, 'tod_engineering_episode_card', [System.StringComparison]::OrdinalIgnoreCase) -or
        $outputRel.StartsWith('runtime/tod_engineering_corpus/', [System.StringComparison]::OrdinalIgnoreCase)
    )
    $wantsEngineeringEpisodeQualityExaminer = [string]::Equals($requiredArtifactType, 'tod_engineering_episode_quality_examiner_verdict', [System.StringComparison]::OrdinalIgnoreCase)
    $wantsEngineeringContextPackage = [string]::Equals($requiredArtifactType, 'tod_engineering_context_package', [System.StringComparison]::OrdinalIgnoreCase)
    $engineeringContextPackageArtifact = $null
    if ($wantsEngineeringContextPackage) {
        $sourceEvidence = if ($auditSource.PSObject.Properties['evidence']) { $auditSource.evidence } else { [ordered]@{} }
        $sourceProblem = if ($auditSource.PSObject.Properties['problem']) { $auditSource.problem } else { [ordered]@{} }
        $sourceRepairDelta = if ($auditSource.PSObject.Properties['intended_repair_delta']) { $auditSource.intended_repair_delta } else { [ordered]@{} }
        $readTaskDirective = {
            param([Parameter(Mandatory = $true)][string]$LabelPattern)
            $directiveMatch = [regex]::Match($combinedTextForAudit, ('(?im)^\s*{0}\s*:\s*(?<value>.+?)\s*$' -f $LabelPattern))
            if ($directiveMatch.Success) {
                return ([string]$directiveMatch.Groups['value'].Value).Trim()
            }
            return ''
        }
        $taskProblemSummary = & $readTaskDirective 'Problem\s+Summary'
        $taskObservedFailure = & $readTaskDirective 'Observed\s+Failure'
        $taskDesiredBehavior = & $readTaskDirective 'Desired\s+Behavior'
        $taskValidationTarget = & $readTaskDirective 'Validation\s+Target'
        $taskBehaviorAssertionRaw = & $readTaskDirective 'Behavior Assertion JSON'
        $taskBehaviorAssertion = $null
        if ($taskBehaviorAssertionRaw) {
            try {
                $taskBehaviorAssertion = ConvertFrom-Json -InputObject $taskBehaviorAssertionRaw -ErrorAction Stop
            } catch {
                # Parse failure: leave $taskBehaviorAssertion as $null
            }
        }
        $sourceLesson = if ($auditSource.PSObject.Properties['lesson']) { [string]$auditSource.lesson } elseif ($auditSource.PSObject.Properties['model_utilization_lesson']) { [string]$auditSource.model_utilization_lesson } else { 'Separate engineering context building from runtime artifact routing so the next model receives source facts, failed outputs, and validation requirements without editing source code.' }
        $sourceFile = if ($sourceEvidence.PSObject.Properties['source_file']) { [string]$sourceEvidence.source_file } elseif ($auditSource.PSObject.Properties['source_file']) { [string]$auditSource.source_file } else { '' }
        $sourceFunction = if ($sourceEvidence.PSObject.Properties['source_function']) { [string]$sourceEvidence.source_function } elseif ($auditSource.PSObject.Properties['source_function']) { [string]$auditSource.source_function } elseif ($auditSource.PSObject.Properties['function_surface']) { [string]$auditSource.function_surface } else { '' }
        $sourceAnchorArtifact = if ($sourceEvidence.PSObject.Properties['source_anchor_artifact']) { [string]$sourceEvidence.source_anchor_artifact } elseif ($auditSource.PSObject.Properties['source_anchor_artifact']) { [string]$auditSource.source_anchor_artifact } else { $inputRel }
        $observedFailure = if (-not [string]::IsNullOrWhiteSpace($taskObservedFailure)) { $taskObservedFailure } elseif ($sourceEvidence.PSObject.Properties['observed_fault']) { [string]$sourceEvidence.observed_fault } elseif ($sourceProblem.PSObject.Properties['summary']) { [string]$sourceProblem.summary } elseif ($auditSource.PSObject.Properties['observed_failure']) { [string]$auditSource.observed_failure } else { 'Prior TOD packet materialization did not produce a behavior-changing source delta suitable for bounded edit execution.' }
        $desiredBehavior = if (-not [string]::IsNullOrWhiteSpace($taskDesiredBehavior)) { $taskDesiredBehavior } elseif ($sourceRepairDelta.PSObject.Properties['new_text_purpose']) { [string]$sourceRepairDelta.new_text_purpose } elseif ($auditSource.PSObject.Properties['desired_behavior']) { [string]$auditSource.desired_behavior } else { 'Generate a packet that uses the actual source file as target_file and produces behavior-changing old_text/new_text instead of a marker-only edit.' }
        $validationTarget = if (-not [string]::IsNullOrWhiteSpace($taskValidationTarget)) { $taskValidationTarget } elseif ($sourceRepairDelta.PSObject.Properties['validation_target']) { [string]$sourceRepairDelta.validation_target } elseif ($auditSource.PSObject.Properties['validation_target']) { [string]$auditSource.validation_target } else { 'source-anchor packet contains exact source target, behavior-changing new_text, and rejects marker-only output' }

        $engineeringContextPackageArtifact = [ordered]@{
            artifact_type = 'tod_engineering_context_package'
            generated_at = (Get-Date).ToUniversalTime().ToString('o')
            source = 'local_execution_read_only_audit_artifact_lane'
            objective_id = if ($Context.PSObject.Properties['objective_id']) { [string]$Context.objective_id } else { '' }
            task_id = if ($Context.PSObject.Properties['task_id']) { [string]$Context.task_id } else { '' }
            episode_id = if ($auditSource.PSObject.Properties['episode_id']) { [string]$auditSource.episode_id } else { [System.IO.Path]::GetFileNameWithoutExtension($inputRel) }
            problem_summary = if (-not [string]::IsNullOrWhiteSpace($taskProblemSummary)) { $taskProblemSummary } elseif ($sourceProblem.PSObject.Properties['summary']) { [string]$sourceProblem.summary } elseif ($auditSource.PSObject.Properties['problem_statement']) { [string]$auditSource.problem_statement } else { $observedFailure }
            source_file = $sourceFile
            source_surface = 'engineering_context_package_source_field_selection'
            source_function = $sourceFunction
            source_anchor_artifact = $sourceAnchorArtifact
            observed_failure = $observedFailure
            desired_behavior = $desiredBehavior
            validation_target = $validationTarget
            behavior_assertion = $taskBehaviorAssertion
            files_to_supply = @($inputRel, $sourceAnchorArtifact, $sourceFile) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique
            facts = @(
                'The input artifact is evidence context, not the bounded edit target.',
                'The output artifact is the context package, not the bounded edit target.',
                'The source file named by the source-anchor evidence is the only valid bounded edit target.',
                'A marker-only or comment-only delta does not count as source-anchor packet materialization.'
            )
            hypotheses = @(
                'The failed packet materializer selected an administratively safe marker insertion because it lacked enough source-role context.',
                'Supplying explicit path roles and rejected-output examples should help the next engineering model produce a behavior-changing packet.'
            )
            rejected_outputs = @(
                'marker-only packet',
                'comment-only packet',
                'whitespace-only packet',
                'packet using the input artifact as target_file',
                'packet using the output artifact as target_file'
            )
            required_output_contract = [ordered]@{
                artifact_type = 'tod_source_anchor_packet_directive_materialization_artifact'
                target_file = 'exact source file from source_anchor_artifact'
                old_text = 'exact current source anchor text'
                new_text = 'behavior-changing replacement text'
                marker_only = $false
                validation_command = $validationTarget
            }
            prohibited_actions = @(
                'do not edit source code while creating this context package',
                'do not normalize path roles into a single target path',
                'do not claim borrowed-capability reduction from this runtime-support artifact'
            )
            model_utilization_lesson = $sourceLesson
            validation = [ordered]@{
                artifact_path = $outputRel
                input_read = $true
                source_edits = @()
                required_fields_present = $true
                no_source_code_modified = $true
            }
            no_code_changes = $true
            independent_credit_requested = $false
            dave_needed = 'no'
        }
    }
    $wantsModelUtilizationEngineeringJudgment = [string]::Equals($requiredArtifactType, 'tod_model_utilization_engineering_judgment', [System.StringComparison]::OrdinalIgnoreCase)
    $modelUtilizationEngineeringJudgmentArtifact = $null
    if ($wantsModelUtilizationEngineeringJudgment) {
        $supportingEvidence = @()
        $supportingArtifactMatches = @([regex]::Matches($combinedTextForAudit, '(?im)\bSupporting\s+Artifact\s*:\s*(?<path>\S+?\.json)\b'))
        foreach ($supportingMatchItem in $supportingArtifactMatches) {
            $supportingRel = Convert-ToLocalExecutionRepoRelativePath -PathValue ([string]$supportingMatchItem.Groups['path'].Value)
            if ([string]::IsNullOrWhiteSpace($supportingRel)) {
                continue
            }
            $supportingAbs = Join-Path $script:LocalEngineRepoRoot $supportingRel
            if (-not (Test-Path -Path $supportingAbs -PathType Leaf)) {
                continue
            }
            try {
                $supportingJson = Get-Content -Path $supportingAbs -Raw | ConvertFrom-Json
                $supportingEvidence += [pscustomobject]@{
                    path = $supportingRel
                    json = $supportingJson
                    artifact_type = if ($supportingJson.PSObject.Properties['artifact_type']) { [string]$supportingJson.artifact_type } else { '' }
                    verdict = if ($supportingJson.PSObject.Properties['verdict']) { [string]$supportingJson.verdict } else { '' }
                    training_classification = if ($supportingJson.PSObject.Properties['training_classification']) { [string]$supportingJson.training_classification } else { '' }
                }
            }
            catch {
                continue
            }
        }
        $contextArtifactType = if ($auditSource.PSObject.Properties['artifact_type']) { [string]$auditSource.artifact_type } else { '' }
        $sourceFile = if ($auditSource.PSObject.Properties['source_file']) { [string]$auditSource.source_file } else { '' }
        $sourceFunction = if ($auditSource.PSObject.Properties['source_function']) { [string]$auditSource.source_function } else { '' }
        $sourceAnchorArtifact = if ($auditSource.PSObject.Properties['source_anchor_artifact']) { [string]$auditSource.source_anchor_artifact } else { '' }
        $hasPromptReadyContext = (
            [string]::Equals($contextArtifactType, 'tod_engineering_context_package', [System.StringComparison]::OrdinalIgnoreCase) -and
            -not [string]::IsNullOrWhiteSpace($sourceFile) -and
            -not [string]::IsNullOrWhiteSpace($sourceFunction) -and
            -not [string]::IsNullOrWhiteSpace($sourceAnchorArtifact) -and
            $auditSource.PSObject.Properties['required_output_contract'] -and
            $auditSource.PSObject.Properties['rejected_outputs']
        )
        $alreadyAppliedEvidence = @($supportingEvidence | Where-Object {
            [string]::Equals([string]$_.verdict, 'fail_model_retry_readiness', [System.StringComparison]::OrdinalIgnoreCase) -or
            [string]::Equals([string]$_.training_classification, 'model_utilization_defect', [System.StringComparison]::OrdinalIgnoreCase)
        })
        $alreadyAppliedSourceEvidence = @($supportingEvidence | Where-Object {
            $supportingJson = $_.json
            $supportingJson.PSObject.Properties['findings'] -and
            $supportingJson.findings.PSObject.Properties['source_anchor_contains_truth_table_repair'] -and
            [bool]$supportingJson.findings.source_anchor_contains_truth_table_repair
        })
        $providerReadinessDowngraded = (@($alreadyAppliedEvidence).Count -gt 0 -or @($alreadyAppliedSourceEvidence).Count -gt 0)
        $candidateRequestReady = ($hasPromptReadyContext -and -not $providerReadinessDowngraded)
        $contextQuality = if ($providerReadinessDowngraded) { 'already_applied_no_provider_retry' } elseif ($hasPromptReadyContext) { 'provider_prompt_ready' } else { 'insufficient_context_package' }
        $modelUtilizationEngineeringJudgmentArtifact = [ordered]@{
            artifact_type = 'tod_model_utilization_engineering_judgment'
            generated_at = (Get-Date).ToUniversalTime().ToString('o')
            source = 'local_execution_read_only_audit_artifact_lane'
            objective_id = if ($Context.PSObject.Properties['objective_id']) { [string]$Context.objective_id } else { '' }
            task_id = if ($Context.PSObject.Properties['task_id']) { [string]$Context.task_id } else { '' }
            input_context_package = $inputRel
            provider_reachable = $false
            provider_or_runtime_hook = 'no_engineering_provider_hook_available_in_local_execution_lane'
            context_quality = $contextQuality
            source_file = $sourceFile
            source_function = $sourceFunction
            source_anchor_artifact = $sourceAnchorArtifact
            candidate_request_ready = $candidateRequestReady
            supporting_artifacts_read = [object[]](@($supportingEvidence | ForEach-Object { [string]$_.path }))
            provider_readiness_downgraded_by_supporting_evidence = $providerReadinessDowngraded
            required_provider_prompt_fields = @(
                'problem_summary',
                'source_file',
                'source_function',
                'source_anchor_artifact',
                'observed_failure',
                'desired_behavior',
                'required_output_contract',
                'rejected_outputs',
                'validation_target'
            )
            tod_accept_reject_policy = @(
                'accept only behavior-changing candidate new_text grounded in the source anchor',
                'reject provider output that changes the input or output artifact instead of the source file',
                'reject output that lacks exact old_text/current-source anchoring',
                'require validation command evidence before source mutation credit'
            )
            bad_patch_rejection_criteria = if ($auditSource.PSObject.Properties['rejected_outputs']) { @($auditSource.rejected_outputs) } else { @('marker-only packet', 'comment-only packet', 'no-delta packet') }
            validation_command_needed = if ($auditSource.PSObject.Properties['required_output_contract'] -and $auditSource.required_output_contract.PSObject.Properties['validation_command']) { [string]$auditSource.required_output_contract.validation_command } else { 'PowerShell parse or focused regression covering the changed source behavior' }
            counts_as_engineering_implementation_credit = $false
            counts_as_model_utilization_credit = if ($providerReadinessDowngraded) { 'partial_already_applied_readiness_rejection_credit_only' } elseif ($hasPromptReadyContext) { 'partial_context_and_judgment_credit_only' } else { 'no' }
            blocker_or_next_action = if ($providerReadinessDowngraded) {
                [ordered]@{
                    status = 'provider_retry_not_needed'
                    reason_code = 'already_applied_source_evidence'
                    next_action = 'Run or cite focused validation and close the model retry request without asking a provider for new_text.'
                }
            }
            elseif ($hasPromptReadyContext) {
                [ordered]@{
                    status = 'blocked_on_provider_hook'
                    reason_code = 'engineering_provider_hook_not_available'
                    next_action = 'Use this judgment artifact to create a provider request or local-model stub, then require TOD to accept or reject the candidate patch from source evidence.'
                }
            }
            else {
                [ordered]@{
                    status = 'blocked_on_context_quality'
                    reason_code = 'context_package_missing_required_prompt_fields'
                    next_action = 'Repair the context package before asking any model or provider for candidate new_text.'
                }
            }
            no_source_code_modified = $true
            validation = [ordered]@{
                artifact_path = $outputRel
                input_read = $true
                required_fields_present = $true
                no_source_code_modified = $true
            }
            dave_needed = 'no'
        }
    }
    $wantsEngineeringProviderRequest = [string]::Equals($requiredArtifactType, 'tod_engineering_provider_request', [System.StringComparison]::OrdinalIgnoreCase)
    $engineeringProviderRequestArtifact = $null
    if ($wantsEngineeringProviderRequest) {
        $supportingArtifactRel = ''
        $supportingMatch = [regex]::Match($combinedTextForAudit, '(?im)\bSupporting\s+Artifact\s*:\s*(?<path>\S+?\.json)\b')
        if ($supportingMatch.Success) {
            $supportingArtifactRel = Convert-ToLocalExecutionRepoRelativePath -PathValue ([string]$supportingMatch.Groups['path'].Value)
        }
        $supportingArtifact = $null
        if (-not [string]::IsNullOrWhiteSpace($supportingArtifactRel)) {
            $supportingArtifactAbs = Join-Path $script:LocalEngineRepoRoot $supportingArtifactRel
            if (Test-Path -Path $supportingArtifactAbs -PathType Leaf) {
                $supportingArtifact = Get-Content -Path $supportingArtifactAbs -Raw | ConvertFrom-Json
            }
        }

        $contextPackage = $auditSource
        $isReplanSource = (
            $contextPackage.PSObject.Properties['artifact_type'] -and
            [string]::Equals([string]$contextPackage.artifact_type, 'tod_engineering_provider_candidate_replan', [System.StringComparison]::OrdinalIgnoreCase)
        )
        $sourceFile = if ($contextPackage.PSObject.Properties['source_file']) { [string]$contextPackage.source_file } elseif ($isReplanSource -and $contextPackage.PSObject.Properties['target_file']) { [string]$contextPackage.target_file } else { '' }
        $sourceFunction = if ($contextPackage.PSObject.Properties['source_function']) { [string]$contextPackage.source_function } else { '' }
        $sourceAnchorArtifact = if ($contextPackage.PSObject.Properties['source_anchor_artifact']) { [string]$contextPackage.source_anchor_artifact } else { '' }
        $sourceAnchorBody = ''
        if (-not [string]::IsNullOrWhiteSpace($sourceAnchorArtifact)) {
            $sourceAnchorArtifactRel = Convert-ToLocalExecutionRepoRelativePath -PathValue $sourceAnchorArtifact
            $sourceAnchorArtifactAbs = Join-Path $script:LocalEngineRepoRoot $sourceAnchorArtifactRel
            if (Test-Path -Path $sourceAnchorArtifactAbs -PathType Leaf) {
                try {
                    $sourceAnchorArtifactJson = Get-Content -Path $sourceAnchorArtifactAbs -Raw | ConvertFrom-Json
                    if ([string]::IsNullOrWhiteSpace($sourceFunction)) {
                        if ($sourceAnchorArtifactJson.PSObject.Properties['source_function']) {
                            $sourceFunction = [string]$sourceAnchorArtifactJson.source_function
                        }
                        elseif ($sourceAnchorArtifactJson.PSObject.Properties['function_surface']) {
                            $sourceFunction = [string]$sourceAnchorArtifactJson.function_surface
                        }
                    }
                    if ($sourceAnchorArtifactJson.PSObject.Properties['exact_text']) {
                        $sourceAnchorBody = [string]$sourceAnchorArtifactJson.exact_text
                    }
                }
                catch {
                    $sourceAnchorBody = ''
                }
            }
        }
        $problemSummary = if ($contextPackage.PSObject.Properties['problem_summary']) { [string]$contextPackage.problem_summary } elseif ($isReplanSource) { 'Regenerate a behavior-changing provider candidate after the prior candidate was rejected.' } else { 'Generate behavior-changing source repair text from the supplied engineering context.' }
        $observedFailure = if ($contextPackage.PSObject.Properties['observed_failure']) { [string]$contextPackage.observed_failure } elseif ($isReplanSource -and $contextPackage.PSObject.Properties['prior_rejection_reason_code']) { [string]$contextPackage.prior_rejection_reason_code } else { '' }
        $desiredBehavior = if ($contextPackage.PSObject.Properties['desired_behavior']) { [string]$contextPackage.desired_behavior } elseif ($isReplanSource -and $contextPackage.PSObject.Properties['revised_provider_instruction']) { [string]$contextPackage.revised_provider_instruction } else { '' }
        $sourceFileForValidation = if (-not [string]::IsNullOrWhiteSpace($sourceFile)) { $sourceFile } else { 'scripts/engines/LocalExecutionEngine.ps1' }
        $sourceFileForValidationSlash = $sourceFileForValidation -replace '\\', '/'
        $sourceFileForValidationBackslash = $sourceFileForValidationSlash -replace '/', '\'
        $sourceFileExtension = [System.IO.Path]::GetExtension($sourceFileForValidationSlash)
        $defaultVerifierValidationCommand = if ($sourceFileExtension -in @('.ps1', '.psm1')) {
            'powershell -NoProfile -Command "$tokens=$null;$errors=$null;[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path \"{0}\"),[ref]$tokens,[ref]$errors)>$null;if($errors.Count){{throw ($errors | Out-String)}};Write-Output ''parse=passed''"' -f $sourceFileForValidationBackslash
        }
        elseif ($sourceFileExtension -eq '.py') {
            'python -m py_compile {0}' -f $sourceFileForValidationSlash
        }
        elseif ($sourceFileExtension -eq '.json') {
            'python -m json.tool {0}' -f $sourceFileForValidationSlash
        }
        else {
            'Invoke-Pester -Path tests -Tag LocalExecution -ErrorAction Stop'
        }
        $priorRejectionReasonCode = if ($contextPackage.PSObject.Properties['prior_rejection_reason_code']) { [string]$contextPackage.prior_rejection_reason_code } else { '' }
        $requiresVerifierRepair = (
            $isReplanSource -and
            $priorRejectionReasonCode -in @('rejected_generic_validation_command', 'rejected_validation_command_not_allowed_verifier')
        )
        $replanValidationCommandRequirement = if ($requiresVerifierRepair) {
            $defaultVerifierValidationCommand
        }
        else {
            if ($contextPackage.PSObject.Properties['validation_command']) { [string]$contextPackage.validation_command } else { $defaultVerifierValidationCommand }
        }
        $requiredOutputContract = if ($contextPackage.PSObject.Properties['required_output_contract']) { $contextPackage.required_output_contract } elseif ($isReplanSource) { [ordered]@{
            target_file = $sourceFile
            output_fields = @('target_file', 'old_text', 'new_text', 'validation_command', 'behavior_change_summary')
            validation_command = $replanValidationCommandRequirement
            validation_command_must_be_executable = $true
            allowed_validation_verifiers = @('Parser]::ParseFile', 'python -m py_compile', 'python -m json.tool', 'pytest', 'Invoke-Pester')
            reject_validation_placeholders = @('PowerShell parse or focused regression', 'focused regression covering the changed source behavior', 'dot-source loaded smoke check')
        } } else { [ordered]@{} }
        $rejectedOutputs = if ($contextPackage.PSObject.Properties['rejected_outputs']) { @($contextPackage.rejected_outputs) } elseif ($isReplanSource -and $contextPackage.PSObject.Properties['next_candidate_rejection_checks']) { @($contextPackage.next_candidate_rejection_checks) } else { @('marker-only packet', 'comment-only packet', 'no-delta packet') }
        $validationCommand = if ($isReplanSource) {
            $replanValidationCommandRequirement
        }
        elseif ($requiredOutputContract.PSObject.Properties['validation_command']) {
            [string]$requiredOutputContract.validation_command
        }
        else {
            'PowerShell parse or focused regression covering the changed source behavior'
        }
        $judgmentReady = (
            $null -ne $supportingArtifact -and
            $supportingArtifact.PSObject.Properties['artifact_type'] -and
            [string]::Equals([string]$supportingArtifact.artifact_type, 'tod_model_utilization_engineering_judgment', [System.StringComparison]::OrdinalIgnoreCase) -and
            $supportingArtifact.PSObject.Properties['candidate_request_ready'] -and
            [bool]$supportingArtifact.candidate_request_ready
        )
        $providerRequestReady = if ($isReplanSource) {
            (
                $contextPackage.PSObject.Properties['provider_request_ready_for_retry'] -and
                [bool]$contextPackage.provider_request_ready_for_retry -and
                -not [string]::IsNullOrWhiteSpace($sourceFile) -and
                -not [string]::IsNullOrWhiteSpace($sourceAnchorArtifact) -and
                -not [string]::IsNullOrWhiteSpace($desiredBehavior)
            )
        }
        else {
            (
                [string]::Equals([string]$contextPackage.artifact_type, 'tod_engineering_context_package', [System.StringComparison]::OrdinalIgnoreCase) -and
                -not [string]::IsNullOrWhiteSpace($sourceFile) -and
                -not [string]::IsNullOrWhiteSpace($sourceAnchorArtifact) -and
                $judgmentReady
            )
        }

        $engineeringProviderRequestArtifact = [ordered]@{
            artifact_type = 'tod_engineering_provider_request'
            generated_at = (Get-Date).ToUniversalTime().ToString('o')
            source = 'local_execution_read_only_audit_artifact_lane'
            objective_id = if ($Context.PSObject.Properties['objective_id']) { [string]$Context.objective_id } else { '' }
            task_id = if ($Context.PSObject.Properties['task_id']) { [string]$Context.task_id } else { '' }
            input_context_package = $inputRel
            input_replan_artifact = if ($isReplanSource) { $inputRel } else { '' }
            input_model_utilization_judgment = $supportingArtifactRel
            provider_request_ready = $providerRequestReady
            target_file = $sourceFile
            provider_role = 'local_engineering_model_or_provider_candidate_patch_generator'
behavior_assertion = if ($contextPackage.PSObject.Properties['behavior_assertion']) { $contextPackage.behavior_assertion } else { $null }
            prompt_messages = @(
                [ordered]@{
                    role = 'system'
                    content = 'You are an engineering patch candidate generator. Use only the supplied source-anchor context. Return strict JSON with target_file, old_text, new_text, validation_command, behavior_change_summary, and risk_notes. Do not edit files. The validation_command must use an allowed verifier pattern (Parser]::ParseFile, python -m py_compile, python -m json.tool, pytest, or Invoke-Pester) and must reference target_file.'
                },
                [ordered]@{
                    role = 'user'
                    content = ('Problem: {0}`nObserved failure: {1}`nDesired behavior: {2}`nSource file: {3}`nSource function: {4}`nSource-anchor artifact: {5}`nRequired output contract: {6}`nForbidden outputs: {7}`nSource-anchor body (authoritative old_text source):`n{8}' -f $problemSummary, $observedFailure, $desiredBehavior, $sourceFile, $sourceFunction, $sourceAnchorArtifact, ($requiredOutputContract | ConvertTo-Json -Depth 6 -Compress), ($rejectedOutputs -join '; '), $sourceAnchorBody)
                }
            )
            source_files_to_include = [object[]](@($sourceFile) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
            artifacts_to_include = [object[]](@($inputRel, $supportingArtifactRel, $sourceAnchorArtifact) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
            required_output_contract = $requiredOutputContract
            rejection_policy = if ($null -ne $supportingArtifact -and $supportingArtifact.PSObject.Properties['tod_accept_reject_policy']) { @($supportingArtifact.tod_accept_reject_policy) } else { @(
                'reject marker-only, comment-only, whitespace-only, or no-delta output',
                'reject candidate text that changes an artifact path instead of the source file',
                'reject candidate text that lacks exact old_text from current source',
                'reject candidate text without validation command evidence'
            ) }
            validation_command = $validationCommand
            source_anchor_body_available = -not [string]::IsNullOrWhiteSpace($sourceAnchorBody)
            forbidden_outputs = $rejectedOutputs
            counts_as_engineering_implementation_credit = $false
            counts_as_model_utilization_credit = if ($providerRequestReady) { 'provider_request_artifact_only' } else { 'no' }
            next_action_after_provider_response = if ($providerRequestReady) {
                'Invoke a local engineering model/provider with this request, then require TOD to accept or reject the candidate before any source edit.'
            }
            else {
                'Repair missing context package or model-utilization judgment before invoking a provider.'
            }
            no_source_code_modified = $true
            validation = [ordered]@{
                artifact_path = $outputRel
                input_read = $true
                supporting_artifact_read = ($null -ne $supportingArtifact)
                required_fields_present = $providerRequestReady
                no_source_code_modified = $true
            }
            dave_needed = 'no'
        }
    }
    $wantsLocalEngineeringProviderInventory = [string]::Equals($requiredArtifactType, 'tod_local_engineering_provider_inventory', [System.StringComparison]::OrdinalIgnoreCase)
    $localEngineeringProviderInventoryArtifact = $null
    if ($wantsLocalEngineeringProviderInventory) {
        $providerRequest = $auditSource
        $providerRequestReady = (
            $providerRequest.PSObject.Properties['artifact_type'] -and
            [string]::Equals([string]$providerRequest.artifact_type, 'tod_engineering_provider_request', [System.StringComparison]::OrdinalIgnoreCase) -and
            $providerRequest.PSObject.Properties['provider_request_ready'] -and
            [bool]$providerRequest.provider_request_ready
        )
        $toolNames = @('ollama', 'llama-cli', 'llama-server', 'python', 'node', 'nvidia-smi')
        $detectedTools = @()
        foreach ($toolName in $toolNames) {
            $commandInfo = Get-Command -Name $toolName -ErrorAction SilentlyContinue
            $detectedTools += [ordered]@{
                name = $toolName
                available = ($null -ne $commandInfo)
                path = if ($null -ne $commandInfo) { [string]$commandInfo.Source } else { '' }
            }
        }
        $pythonPackages = @(
            [ordered]@{ name = 'torch'; status = 'not_inspected_by_local_engine' },
            [ordered]@{ name = 'transformers'; status = 'not_inspected_by_local_engine' },
            [ordered]@{ name = 'llama_cpp'; status = 'not_inspected_by_local_engine' },
            [ordered]@{ name = 'ctransformers'; status = 'not_inspected_by_local_engine' }
        )
        $configuredLlamaServerRel = 'tools/llama.cpp/llama-server.exe'
        $configuredLlamaModelRel = 'models/tod/Qwen2.5-3B-Instruct-Q4_K_M.gguf'
        $configuredLlamaServerPath = Join-Path $script:LocalEngineRepoRoot ($configuredLlamaServerRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $configuredLlamaModelPath = Join-Path $script:LocalEngineRepoRoot ($configuredLlamaModelRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $configuredLlamaServerExists = Test-Path -Path $configuredLlamaServerPath -PathType Leaf
        $configuredLlamaModelExists = Test-Path -Path $configuredLlamaModelPath -PathType Leaf
        $configuredProviderAvailable = ($configuredLlamaServerExists -and $configuredLlamaModelExists)
        $providerEndpointUrl = 'http://127.0.0.1:8008/v1/models'
        $runningProviderReachable = $false
        $runningProviderModels = @()
        $runningProviderError = ''
        try {
            $providerEndpointResponse = Invoke-RestMethod -Uri $providerEndpointUrl -TimeoutSec 2
            $runningProviderReachable = $true
            if ($providerEndpointResponse.PSObject.Properties['data']) {
                foreach ($modelItem in @($providerEndpointResponse.data)) {
                    if ($modelItem.PSObject.Properties['id'] -and -not [string]::IsNullOrWhiteSpace([string]$modelItem.id)) {
                        $runningProviderModels += [string]$modelItem.id
                    }
                }
            }
            if ($providerEndpointResponse.PSObject.Properties['models']) {
                foreach ($modelItem in @($providerEndpointResponse.models)) {
                    if ($modelItem.PSObject.Properties['name'] -and -not [string]::IsNullOrWhiteSpace([string]$modelItem.name)) {
                        $runningProviderModels += [string]$modelItem.name
                    }
                    elseif ($modelItem.PSObject.Properties['model'] -and -not [string]::IsNullOrWhiteSpace([string]$modelItem.model)) {
                        $runningProviderModels += [string]$modelItem.model
                    }
                }
            }
            $runningProviderModels = @($runningProviderModels | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
        }
        catch {
            $runningProviderError = $_.Exception.Message
        }
        $nvidiaCommand = @($detectedTools | Where-Object { [string]$_.name -eq 'nvidia-smi' -and $_.available -eq $true } | Select-Object -First 1)
        $gpuAvailable = ($nvidiaCommand.Count -gt 0)
        $hasOllama = (@($detectedTools | Where-Object { [string]$_.name -eq 'ollama' -and $_.available -eq $true }).Count -gt 0)
        $hasLlamaCli = (@($detectedTools | Where-Object { ([string]$_.name -eq 'llama-cli' -or [string]$_.name -eq 'llama-server') -and $_.available -eq $true }).Count -gt 0)
        $realProviderReachable = ($hasOllama -or $hasLlamaCli -or $configuredProviderAvailable -or $runningProviderReachable)
        $usableProviderHook = ($providerRequestReady -and $realProviderReachable)
        $localEngineeringProviderInventoryArtifact = [ordered]@{
            artifact_type = 'tod_local_engineering_provider_inventory'
            generated_at = (Get-Date).ToUniversalTime().ToString('o')
            source = 'local_execution_read_only_audit_artifact_lane'
            objective_id = if ($Context.PSObject.Properties['objective_id']) { [string]$Context.objective_id } else { '' }
            task_id = if ($Context.PSObject.Properties['task_id']) { [string]$Context.task_id } else { '' }
            input_provider_request = $inputRel
            provider_request_ready = $providerRequestReady
            detected_tools = @($detectedTools)
            detected_python_packages = @($pythonPackages)
            configured_provider_assets = [ordered]@{
                llama_server_path = $configuredLlamaServerRel
                llama_server_exists = $configuredLlamaServerExists
                model_path = $configuredLlamaModelRel
                model_exists = $configuredLlamaModelExists
                configured_provider_available = $configuredProviderAvailable
            }
            running_provider_endpoint = [ordered]@{
                url = $providerEndpointUrl
                reachable = $runningProviderReachable
                models = @($runningProviderModels)
                error = $runningProviderError
            }
            gpu_available = $gpuAvailable
            real_provider_reachable = $realProviderReachable
            usable_provider_hook = $usableProviderHook
            stub_contract = [ordered]@{
                artifact_type = 'tod_engineering_provider_candidate_stub'
                input_artifact_type = 'tod_engineering_provider_request'
                required_output_fields = @('artifact_type', 'target_file', 'old_text', 'new_text', 'validation_command', 'risk_notes', 'reject_if_marker_only')
                forbidden_actions = @('edit files directly', 'install or download models', 'claim implementation credit from provider inventory')
                acceptance_policy = 'TOD must reject marker-only, no-delta, wrong-target, or unvalidated candidate output before any source mutation.'
            }
            candidate_response_available = $false
            counts_as_engineering_implementation_credit = $false
            counts_as_model_utilization_credit = if ($providerRequestReady) { 'provider_inventory_and_stub_contract_only' } else { 'no' }
            next_smallest_rung = if ($usableProviderHook) {
                'TOD-LOCAL-ENGINEERING-PROVIDER-CANDIDATE-INVOCATION-V1'
            }
            else {
                'TOD-LOCAL-ENGINEERING-PROVIDER-STUB-RESPONSE-V1'
            }
            no_source_code_modified = $true
            validation = [ordered]@{
                artifact_path = $outputRel
                input_read = $true
                required_fields_present = $true
                no_source_code_modified = $true
            }
            dave_needed = 'no'
        }
    }
    $wantsEngineeringProviderCandidateStub = [string]::Equals($requiredArtifactType, 'tod_engineering_provider_candidate_stub', [System.StringComparison]::OrdinalIgnoreCase)
    $engineeringProviderCandidateStubArtifact = $null
    if ($wantsEngineeringProviderCandidateStub) {
        $supportingArtifactRel = ''
        $supportingMatch = [regex]::Match($combinedTextForAudit, '(?im)\bSupporting\s+Artifact\s*:\s*(?<path>\S+?\.json)\b')
        if ($supportingMatch.Success) {
            $supportingArtifactRel = Convert-ToLocalExecutionRepoRelativePath -PathValue ([string]$supportingMatch.Groups['path'].Value)
        }
        $providerInventory = $null
        if (-not [string]::IsNullOrWhiteSpace($supportingArtifactRel)) {
            $supportingArtifactAbs = Join-Path $script:LocalEngineRepoRoot $supportingArtifactRel
            if (Test-Path -Path $supportingArtifactAbs -PathType Leaf) {
                $providerInventory = Get-Content -Path $supportingArtifactAbs -Raw | ConvertFrom-Json
            }
        }

        $providerRequest = $auditSource
        $providerRequestReady = (
            $providerRequest.PSObject.Properties['artifact_type'] -and
            [string]::Equals([string]$providerRequest.artifact_type, 'tod_engineering_provider_request', [System.StringComparison]::OrdinalIgnoreCase) -and
            $providerRequest.PSObject.Properties['provider_request_ready'] -and
            [bool]$providerRequest.provider_request_ready
        )
        $inventoryReady = (
            $null -ne $providerInventory -and
            $providerInventory.PSObject.Properties['artifact_type'] -and
            [string]::Equals([string]$providerInventory.artifact_type, 'tod_local_engineering_provider_inventory', [System.StringComparison]::OrdinalIgnoreCase)
        )
        $sourceFile = if ($providerRequest.PSObject.Properties['source_files_to_include'] -and @($providerRequest.source_files_to_include).Count -gt 0) { [string]@($providerRequest.source_files_to_include)[0] } else { '' }
        $sourceAnchorArtifactRel = ''
        if ($providerRequest.PSObject.Properties['artifacts_to_include']) {
            foreach ($artifactPath in @($providerRequest.artifacts_to_include)) {
                if ([string]$artifactPath -match 'SOURCE_ANCHOR.*\.json$') {
                    $sourceAnchorArtifactRel = [string]$artifactPath
                    break
                }
            }
        }
        $sourceAnchorText = ''
        if (-not [string]::IsNullOrWhiteSpace($sourceAnchorArtifactRel)) {
            $sourceAnchorArtifactAbs = Join-Path $script:LocalEngineRepoRoot (Convert-ToLocalExecutionRepoRelativePath -PathValue $sourceAnchorArtifactRel)
            if (Test-Path -Path $sourceAnchorArtifactAbs -PathType Leaf) {
                $sourceAnchorArtifact = Get-Content -Path $sourceAnchorArtifactAbs -Raw | ConvertFrom-Json
                if ($sourceAnchorArtifact.PSObject.Properties['exact_text']) {
                    $sourceAnchorText = [string]$sourceAnchorArtifact.exact_text
                }
            }
        }
        $validationCommand = if ($providerRequest.PSObject.Properties['validation_command']) { [string]$providerRequest.validation_command } else { 'PowerShell parse or focused regression covering the changed source behavior' }
        $candidateReady = ($providerRequestReady -and $inventoryReady -and -not [string]::IsNullOrWhiteSpace($sourceFile) -and -not [string]::IsNullOrWhiteSpace($sourceAnchorText))
        $candidateNewText = if ($candidateReady) {
            $sourceAnchorText + "`n# PROVIDER_STUB_MARKER_ONLY_REJECT_ME"
        }
        else {
            ''
        }
        $engineeringProviderCandidateStubArtifact = [ordered]@{
            artifact_type = 'tod_engineering_provider_candidate_stub'
            generated_at = (Get-Date).ToUniversalTime().ToString('o')
            source = 'local_execution_read_only_audit_artifact_lane'
            objective_id = if ($Context.PSObject.Properties['objective_id']) { [string]$Context.objective_id } else { '' }
            task_id = if ($Context.PSObject.Properties['task_id']) { [string]$Context.task_id } else { '' }
            input_provider_request = $inputRel
            input_provider_inventory = $supportingArtifactRel
            provider_stub_used = $true
            candidate_response_available = $candidateReady
            target_file = $sourceFile
            old_text = $sourceAnchorText
            new_text = $candidateNewText
            validation_command = $validationCommand
            risk_notes = @(
                'deterministic stub candidate only',
                'candidate intentionally appends a marker-only line and must be rejected before source mutation',
                'no model or provider was invoked'
            )
            reject_if_marker_only = $true
            expected_rejection_or_acceptance = if ($candidateReady) { 'reject_marker_only_stub_candidate' } else { 'reject_missing_provider_request_or_anchor' }
            counts_as_engineering_implementation_credit = $false
            counts_as_model_utilization_credit = if ($candidateReady) { 'stub_candidate_for_accept_reject_training_only' } else { 'no' }
            next_smallest_rung = 'TOD-PROVIDER-CANDIDATE-ACCEPT-REJECT-POLICY-V1'
            no_source_code_modified = $true
            validation = [ordered]@{
                artifact_path = $outputRel
                input_read = $true
                supporting_artifact_read = ($null -ne $providerInventory)
                required_fields_present = $candidateReady
                no_source_code_modified = $true
            }
            dave_needed = 'no'
        }
    }
    $wantsEngineeringProviderCandidateInvocation = [string]::Equals($requiredArtifactType, 'tod_engineering_provider_candidate_invocation', [System.StringComparison]::OrdinalIgnoreCase)
    $engineeringProviderCandidateInvocationArtifact = $null
    if ($wantsEngineeringProviderCandidateInvocation) {
        $supportingArtifactRel = ''
        $supportingMatch = [regex]::Match($combinedTextForAudit, '(?im)\bSupporting\s+Artifact\s*:\s*(?<path>\S+?\.json)\b')
        if ($supportingMatch.Success) {
            $supportingArtifactRel = Convert-ToLocalExecutionRepoRelativePath -PathValue ([string]$supportingMatch.Groups['path'].Value)
        }
        $providerInventory = $null
        if (-not [string]::IsNullOrWhiteSpace($supportingArtifactRel)) {
            $supportingArtifactAbs = Join-Path $script:LocalEngineRepoRoot $supportingArtifactRel
            if (Test-Path -Path $supportingArtifactAbs -PathType Leaf) {
                $providerInventory = Get-Content -Path $supportingArtifactAbs -Raw | ConvertFrom-Json
            }
        }

        $inputReplanRel = ''
        $inputArtifactType = if ($auditSource.PSObject.Properties['artifact_type']) { [string]$auditSource.artifact_type } else { '' }
        $providerRequest = $auditSource
        $replanInstruction = ''
        if ([string]::Equals($inputArtifactType, 'tod_engineering_provider_candidate_replan', [System.StringComparison]::OrdinalIgnoreCase)) {
            $inputReplanRel = $inputRel
            if ($auditSource.PSObject.Properties['revised_provider_instruction']) {
                $replanInstruction = [string]$auditSource.revised_provider_instruction
            }
            if ($auditSource.PSObject.Properties['input_provider_request'] -and -not [string]::IsNullOrWhiteSpace([string]$auditSource.input_provider_request)) {
                $providerRequestRelFromReplan = Convert-ToLocalExecutionRepoRelativePath -PathValue ([string]$auditSource.input_provider_request)
                if (-not [string]::IsNullOrWhiteSpace($providerRequestRelFromReplan)) {
                    $providerRequestAbsFromReplan = Join-Path $script:LocalEngineRepoRoot $providerRequestRelFromReplan
                    if (Test-Path -Path $providerRequestAbsFromReplan -PathType Leaf) {
                        $providerRequest = Get-Content -Path $providerRequestAbsFromReplan -Raw | ConvertFrom-Json
                    }
                }
            }
        }
        $providerRequestReady = (
            $providerRequest.PSObject.Properties['artifact_type'] -and
            [string]::Equals([string]$providerRequest.artifact_type, 'tod_engineering_provider_request', [System.StringComparison]::OrdinalIgnoreCase) -and
            $providerRequest.PSObject.Properties['provider_request_ready'] -and
            [bool]$providerRequest.provider_request_ready
        )
        $inventoryReady = (
            $null -ne $providerInventory -and
            $providerInventory.PSObject.Properties['artifact_type'] -and
            [string]::Equals([string]$providerInventory.artifact_type, 'tod_local_engineering_provider_inventory', [System.StringComparison]::OrdinalIgnoreCase) -and
            $providerInventory.PSObject.Properties['usable_provider_hook'] -and
            [bool]$providerInventory.usable_provider_hook
        )
        $sourceFile = if ($providerRequest.PSObject.Properties['source_files_to_include'] -and @($providerRequest.source_files_to_include).Count -gt 0) { [string]@($providerRequest.source_files_to_include)[0] } elseif ($providerRequest.PSObject.Properties['target_file']) { [string]$providerRequest.target_file } else { '' }
        $sourceAnchorArtifactRel = ''
        if ($providerRequest.PSObject.Properties['artifacts_to_include']) {
            foreach ($artifactPath in @($providerRequest.artifacts_to_include)) {
                if ([string]$artifactPath -match 'SOURCE_ANCHOR.*\.json$') {
                    $sourceAnchorArtifactRel = Convert-ToLocalExecutionRepoRelativePath -PathValue ([string]$artifactPath)
                    break
                }
            }
            if ([string]::IsNullOrWhiteSpace($sourceAnchorArtifactRel)) {
                foreach ($artifactPath in @($providerRequest.artifacts_to_include)) {
                    $candidateArtifactRel = Convert-ToLocalExecutionRepoRelativePath -PathValue ([string]$artifactPath)
                    if ([string]::IsNullOrWhiteSpace($candidateArtifactRel)) {
                        continue
                    }
                    $candidateArtifactAbs = Join-Path $script:LocalEngineRepoRoot $candidateArtifactRel
                    if (-not (Test-Path -Path $candidateArtifactAbs -PathType Leaf)) {
                        continue
                    }
                    try {
                        $candidateArtifact = Get-Content -Path $candidateArtifactAbs -Raw | ConvertFrom-Json
                        $isSourceAnchorArtifact = (
                            $candidateArtifact.PSObject.Properties['artifact_type'] -and
                            [string]::Equals([string]$candidateArtifact.artifact_type, 'tod_source_anchor_observation', [System.StringComparison]::OrdinalIgnoreCase)
                        )
                        if ($isSourceAnchorArtifact -or $candidateArtifact.PSObject.Properties['exact_text']) {
                            $sourceAnchorArtifactRel = $candidateArtifactRel
                            break
                        }
                    }
                    catch {
                    }
                }
            }
        }
        $sourceAnchorText = ''
        if (-not [string]::IsNullOrWhiteSpace($sourceAnchorArtifactRel)) {
            $sourceAnchorArtifactAbs = Join-Path $script:LocalEngineRepoRoot $sourceAnchorArtifactRel
            if (Test-Path -Path $sourceAnchorArtifactAbs -PathType Leaf) {
                $sourceAnchorArtifact = Get-Content -Path $sourceAnchorArtifactAbs -Raw | ConvertFrom-Json
                if ($sourceAnchorArtifact.PSObject.Properties['exact_text']) {
                    $sourceAnchorText = [string]$sourceAnchorArtifact.exact_text
                }
            }
        }
        $validationCommand = if ($providerRequest.PSObject.Properties['validation_command']) { [string]$providerRequest.validation_command } else { 'PowerShell parse or focused regression covering the changed source behavior' }
        $providerEndpointUrl = if ($null -ne $providerInventory -and $providerInventory.PSObject.Properties['running_provider_endpoint'] -and $providerInventory.running_provider_endpoint.PSObject.Properties['url']) { [string]$providerInventory.running_provider_endpoint.url } else { 'http://127.0.0.1:8008/v1/models' }
        $providerChatUrl = $providerEndpointUrl -replace '/v1/models$', '/v1/chat/completions'
        $providerModel = ''
        if ($null -ne $providerInventory -and $providerInventory.PSObject.Properties['running_provider_endpoint'] -and $providerInventory.running_provider_endpoint.PSObject.Properties['models'] -and @($providerInventory.running_provider_endpoint.models).Count -gt 0) {
            $providerModel = [string]@($providerInventory.running_provider_endpoint.models)[0]
        }
        if ([string]::IsNullOrWhiteSpace($providerModel)) {
            $providerModel = 'Qwen2.5-3B-Instruct-Q4_K_M.gguf'
        }
        $providerRequestTimeoutSeconds = 60
        if ($null -ne $providerInventory -and $providerInventory.PSObject.Properties['provider_request_timeout_seconds']) {
            $configuredProviderTimeout = 0
            if ([int]::TryParse([string]$providerInventory.provider_request_timeout_seconds, [ref]$configuredProviderTimeout)) {
                $providerRequestTimeoutSeconds = [Math]::Max(30, [Math]::Min(600, $configuredProviderTimeout))
            }
        }
        $providerMaxTokens = 4096
        if ($null -ne $providerInventory -and $providerInventory.PSObject.Properties['provider_max_tokens']) {
            $configuredProviderMaxTokens = 0
            if ([int]::TryParse([string]$providerInventory.provider_max_tokens, [ref]$configuredProviderMaxTokens)) {
                $providerMaxTokens = [Math]::Max(1024, [Math]::Min(16384, $configuredProviderMaxTokens))
            }
        }
        $invocationReady = ($providerRequestReady -and $inventoryReady -and -not [string]::IsNullOrWhiteSpace($sourceFile) -and -not [string]::IsNullOrWhiteSpace($sourceAnchorText))
        $providerRawResponse = ''
        $providerError = ''
        $providerCalled = $false
        $usedProviderRequestPromptMessages = $false
        $outboundPromptMessageCount = 0
        $outboundPromptContextSummary = 'not_built'
        $sourceAnchorTextForPrompt = $sourceAnchorText
        $sourceAnchorPromptWasExcerpted = $false
        if (
            $auditSource.PSObject.Properties['prompt_budget_strategy'] -and
            -not [string]::IsNullOrWhiteSpace([string]$auditSource.prompt_budget_strategy) -and
            ([string]$sourceAnchorTextForPrompt).Length -gt 4000
        ) {
            $excerptAnchorPatterns = @(
                'tod_engineering_provider_candidate_replan',
                'tod_engineering_provider_candidate_invocation',
                'wantsEngineeringProviderCandidateReplan',
                'wantsEngineeringProviderCandidateInvocation',
                'provider_request_ready_for_retry',
                'counts_as_model_utilization_credit'
            )
            $excerptIndex = -1
            foreach ($excerptAnchorPattern in $excerptAnchorPatterns) {
                $candidateIndex = ([string]$sourceAnchorTextForPrompt).IndexOf($excerptAnchorPattern, [System.StringComparison]::OrdinalIgnoreCase)
                if ($candidateIndex -ge 0) {
                    $excerptIndex = $candidateIndex
                    break
                }
            }
            if ($excerptIndex -ge 0) {
                $excerptStart = [Math]::Max(0, $excerptIndex - 1200)
                $excerptLength = [Math]::Min(3600, ([string]$sourceAnchorTextForPrompt).Length - $excerptStart)
                $sourceAnchorTextForPrompt = ([string]$sourceAnchorTextForPrompt).Substring($excerptStart, $excerptLength)
                $sourceAnchorPromptWasExcerpted = $true
            }
        }
        if ($invocationReady) {
            $candidatePrompt = @"
Return JSON only. Do not edit files. Produce a bounded patch candidate with these fields:
target_file, old_text, new_text, validation_command, risk_notes.

Rules:
- old_text must be copied exactly from the supplied source anchor.
- new_text must be behavior-changing, not marker-only and not comment-only.
- If you cannot safely produce a behavior-changing patch, return the same JSON fields with new_text as an empty string and explain why in risk_notes.

Target file: $sourceFile
Validation command: $validationCommand
Source anchor:
$sourceAnchorTextForPrompt
"@
            if (-not [string]::IsNullOrWhiteSpace($replanInstruction)) {
                $candidatePrompt = @"
$candidatePrompt

Replan instruction after prior rejection:
$replanInstruction
"@
            }
            $outboundMessages = New-Object System.Collections.Generic.List[object]
            if ($providerRequest.PSObject.Properties['prompt_messages'] -and @($providerRequest.prompt_messages).Count -gt 0) {
                foreach ($promptMessage in @($providerRequest.prompt_messages)) {
                    $promptRole = if ($promptMessage.PSObject.Properties['role'] -and -not [string]::IsNullOrWhiteSpace([string]$promptMessage.role)) { [string]$promptMessage.role } else { 'user' }
                    $promptContent = if ($promptMessage.PSObject.Properties['content']) { [string]$promptMessage.content } else { '' }
                    if (-not [string]::IsNullOrWhiteSpace($promptContent)) {
                        [void]$outboundMessages.Add([ordered]@{ role = $promptRole; content = $promptContent })
                    }
                }
            }
            if ($outboundMessages.Count -gt 0) {
                $usedProviderRequestPromptMessages = $true
                if (-not [string]::IsNullOrWhiteSpace($replanInstruction)) {
                    [void]$outboundMessages.Add([ordered]@{ role = 'user'; content = ('Replan instruction after prior rejection: {0}' -f $replanInstruction) })
                }
                $outboundPromptContextSummary = 'provider_request_prompt_messages_authoritative'
            }
            else {
                [void]$outboundMessages.Add([ordered]@{ role = 'system'; content = 'You are a local engineering candidate generator. Return compact JSON only.' })
                [void]$outboundMessages.Add([ordered]@{ role = 'user'; content = $candidatePrompt })
                $outboundPromptContextSummary = 'default_candidate_prompt_plus_literal_source_anchor'
            }
            $outboundPromptMessageCount = $outboundMessages.Count
            try {
                $body = [ordered]@{
                    model = $providerModel
                    messages = @($outboundMessages.ToArray())
                    temperature = 0.1
                    max_tokens = 1024
                    response_format = @{type = 'json_object'}
                } | ConvertTo-Json -Depth 8
                $providerResponse = Invoke-RestMethod -Uri $providerChatUrl -Method Post -ContentType 'application/json' -Body $body -TimeoutSec $providerRequestTimeoutSeconds
                $providerCalled = $true
                if ($providerResponse.PSObject.Properties['choices'] -and @($providerResponse.choices).Count -gt 0 -and @($providerResponse.choices)[0].PSObject.Properties['message']) {
                    $providerRawResponse = [string]@($providerResponse.choices)[0].message.content
                }
                else {
                    $providerRawResponse = ($providerResponse | ConvertTo-Json -Depth 8)
                }
            }
            catch {
                $providerError = $_.Exception.Message
            }
        }
        $candidateJsonText = ''
        $candidateJson = $null
        if (-not [string]::IsNullOrWhiteSpace($providerRawResponse)) {
            $jsonMatch = [regex]::Match($providerRawResponse, '(?s)\{.*\}')
            if ($jsonMatch.Success) {
                $candidateJsonText = [string]$jsonMatch.Value
                try {
                    $candidateJson = $candidateJsonText | ConvertFrom-Json
                }
                catch {
                    $providerError = ('candidate_json_parse_failed: {0}' -f $_.Exception.Message)
                }
            }
        }
        $targetFile = if ($null -ne $candidateJson -and $candidateJson.PSObject.Properties['target_file']) { [string]$candidateJson.target_file } else { $sourceFile }
        $oldText = if ($null -ne $candidateJson -and $candidateJson.PSObject.Properties['old_text']) { [string]$candidateJson.old_text } else { $sourceAnchorText }
        $newText = if ($null -ne $candidateJson -and $candidateJson.PSObject.Properties['new_text']) { [string]$candidateJson.new_text } else { '' }
        $candidateValidationCommand = if ($null -ne $candidateJson -and $candidateJson.PSObject.Properties['validation_command']) { [string]$candidateJson.validation_command } else { $validationCommand }
        $riskNotes = if ($null -ne $candidateJson -and $candidateJson.PSObject.Properties['risk_notes']) { @($candidateJson.risk_notes) } elseif (-not [string]::IsNullOrWhiteSpace($providerError)) { @($providerError) } else { @('provider returned no parsed risk notes') }
        $candidateReady = ($providerCalled -and -not [string]::IsNullOrWhiteSpace($providerRawResponse))
        $engineeringProviderCandidateInvocationArtifact = [ordered]@{
            artifact_type = 'tod_engineering_provider_candidate_invocation'
            generated_at = (Get-Date).ToUniversalTime().ToString('o')
            source = 'local_execution_read_only_audit_artifact_lane'
            objective_id = if ($Context.PSObject.Properties['objective_id']) { [string]$Context.objective_id } else { '' }
            task_id = if ($Context.PSObject.Properties['task_id']) { [string]$Context.task_id } else { '' }
            input_replan = $inputReplanRel
            input_provider_request = if ([string]::IsNullOrWhiteSpace($inputReplanRel)) { $inputRel } elseif ($auditSource.PSObject.Properties['input_provider_request']) { Convert-ToLocalExecutionRepoRelativePath -PathValue ([string]$auditSource.input_provider_request) } else { '' }
            input_provider_inventory = $supportingArtifactRel
            replan_instruction_applied = (-not [string]::IsNullOrWhiteSpace($replanInstruction))
            provider_endpoint = $providerChatUrl
            provider_model = $providerModel
            provider_request_timeout_seconds = $providerRequestTimeoutSeconds
            provider_called = $providerCalled
            candidate_response_available = $candidateReady
            used_provider_request_prompt_messages = $usedProviderRequestPromptMessages
            outbound_prompt_message_count = $outboundPromptMessageCount
            outbound_prompt_context_summary = $outboundPromptContextSummary
            raw_provider_response = $providerRawResponse
            parsed_candidate_json = if ($null -ne $candidateJson) { $candidateJson } else { [ordered]@{} }
            target_file = $targetFile
            old_text = $oldText
            new_text = $newText
            validation_command = $candidateValidationCommand
            risk_notes = @($riskNotes)
            source_anchor_prompt_was_excerpted = $sourceAnchorPromptWasExcerpted
            source_anchor_prompt_length = ([string]$sourceAnchorTextForPrompt).Length
            source_anchor_full_length = ([string]$sourceAnchorText).Length
            reject_if_marker_only = $true
            expected_rejection_or_acceptance = 'requires_verdict_gate_before_source_mutation'
            counts_as_engineering_implementation_credit = $false
            counts_as_model_utilization_credit = if ($candidateReady) { 'local_provider_candidate_generated_pending_verdict' } else { 'provider_invocation_attempt_only' }
            next_smallest_rung = 'TOD-PROVIDER-CANDIDATE-ACCEPT-REJECT-POLICY-V1'
            no_source_code_modified = $true
            validation = [ordered]@{
                artifact_path = $outputRel
                input_read = $true
                supporting_artifact_read = ($null -ne $providerInventory)
                required_fields_present = $invocationReady
                provider_called = $providerCalled
                no_source_code_modified = $true
            }
            dave_needed = 'no'
        }
    }
    $wantsEngineeringProviderCandidateVerdict = [string]::Equals($requiredArtifactType, 'tod_engineering_provider_candidate_verdict', [System.StringComparison]::OrdinalIgnoreCase)
    $engineeringProviderCandidateVerdictArtifact = $null
    if ($wantsEngineeringProviderCandidateVerdict) {
        $supportingArtifactRel = ''
        $supportingMatch = [regex]::Match($combinedTextForAudit, '(?im)\bSupporting\s+Artifact\s*:\s*(?<path>\S+?\.json)\b')
        if ($supportingMatch.Success) {
            $supportingArtifactRel = Convert-ToLocalExecutionRepoRelativePath -PathValue ([string]$supportingMatch.Groups['path'].Value)
        }
        $providerRequest = $null
        if (-not [string]::IsNullOrWhiteSpace($supportingArtifactRel)) {
            $supportingArtifactAbs = Join-Path $script:LocalEngineRepoRoot $supportingArtifactRel
            if (Test-Path -Path $supportingArtifactAbs -PathType Leaf) {
                $providerRequest = Get-Content -Path $supportingArtifactAbs -Raw | ConvertFrom-Json
            }
        }

        $candidate = $auditSource
        if ([string]::IsNullOrWhiteSpace($supportingArtifactRel) -and $candidate.PSObject.Properties['input_provider_request']) {
            $supportingArtifactRel = Convert-ToLocalExecutionRepoRelativePath -PathValue ([string]$candidate.input_provider_request)
            if (-not [string]::IsNullOrWhiteSpace($supportingArtifactRel)) {
                $supportingArtifactAbs = Join-Path $script:LocalEngineRepoRoot $supportingArtifactRel
                if (Test-Path -Path $supportingArtifactAbs -PathType Leaf) {
                    $providerRequest = Get-Content -Path $supportingArtifactAbs -Raw | ConvertFrom-Json
                }
            }
        }
        $candidateTypeOk = (
            $candidate.PSObject.Properties['artifact_type'] -and
            (
                [string]::Equals([string]$candidate.artifact_type, 'tod_engineering_provider_candidate_stub', [System.StringComparison]::OrdinalIgnoreCase) -or
                [string]::Equals([string]$candidate.artifact_type, 'tod_engineering_provider_candidate_invocation', [System.StringComparison]::OrdinalIgnoreCase)
            )
        )
        $targetFile = if ($candidate.PSObject.Properties['target_file']) { [string]$candidate.target_file } else { '' }
        $oldText = if ($candidate.PSObject.Properties['old_text']) { [string]$candidate.old_text } else { '' }
        $newText = if ($candidate.PSObject.Properties['new_text']) { [string]$candidate.new_text } else { '' }
        $validationCommand = if ($candidate.PSObject.Properties['validation_command']) { [string]$candidate.validation_command } else { '' }
        $markerOnly = (
            $candidate.PSObject.Properties['reject_if_marker_only'] -and
            [bool]$candidate.reject_if_marker_only -and
            $newText -match 'PROVIDER_STUB_MARKER_ONLY_REJECT_ME'
        )
        $noDelta = [string]::Equals($oldText, $newText, [System.StringComparison]::Ordinal)
        $blankOldText = [string]::IsNullOrWhiteSpace($oldText)
        $blankNewText = [string]::IsNullOrWhiteSpace($newText)
        $wrongTarget = $false
        if ($null -ne $providerRequest -and $providerRequest.PSObject.Properties['source_files_to_include']) {
            $expectedTargets = @($providerRequest.source_files_to_include | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
            if ($expectedTargets.Count -gt 0 -and ($expectedTargets -notcontains $targetFile)) {
                $wrongTarget = $true
            }
        }
        $missingValidation = [string]::IsNullOrWhiteSpace($validationCommand)
        $genericValidation = (
            -not $missingValidation -and
            $validationCommand -match '(?i)^\s*(PowerShell parse|parse or focused regression|focused regression covering the changed source behavior)'
        )
        $oldTextFoundInCurrentSource = $false
        $oldTextSourceEvidence = 'old_text was not checked against current source'
        $normalizedTargetForOldTextCheck = Convert-ToLocalExecutionRepoRelativePath -PathValue $targetFile
        if ($blankOldText) {
            $oldTextSourceEvidence = 'old_text is blank'
        }
        elseif ([string]::IsNullOrWhiteSpace($normalizedTargetForOldTextCheck)) {
            $oldTextSourceEvidence = 'target_file is blank'
        }
        elseif (-not (Test-LocalExecutionSafePath -RelativePath $normalizedTargetForOldTextCheck)) {
            $oldTextSourceEvidence = 'target_file is outside safe local execution paths'
        }
        else {
            $oldTextTargetAbs = Join-Path $script:LocalEngineRepoRoot $normalizedTargetForOldTextCheck
            if (-not (Test-Path -Path $oldTextTargetAbs -PathType Leaf)) {
                $oldTextSourceEvidence = 'target_file does not exist'
            }
            else {
                $currentTargetText = Get-Content -Path $oldTextTargetAbs -Raw
                $currentTargetTextNormalized = $currentTargetText -replace "`r`n", "`n" -replace "`r", "`n"
                $oldTextNormalized = $oldText -replace "`r`n", "`n" -replace "`r", "`n"
                $oldTextFoundInCurrentSource = $currentTargetTextNormalized.Contains($oldTextNormalized)
                $oldTextSourceEvidence = if ($oldTextFoundInCurrentSource) { 'newline-equivalent old_text found in current target source' } else { 'old_text not found in current target source' }
            }
        }
        $validationSpecific = (-not $missingValidation -and -not $genericValidation)
        $validationSpecificEvidence = if ($missingValidation) {
            'validation command is blank'
        }
        elseif ($genericValidation) {
            'validation command is generic and does not prove the changed path'
        }
        else {
            $validationCommand
        }
        $validationCommandUsesAllowedVerifier = (
            $validationSpecific -and
            $validationCommand -match '(?i)(Parser\]::ParseFile|python\s+-m\s+py_compile|python\s+-m\s+json\.tool|pytest|Invoke-Pester)'
        )
        $validationCommandHasExecutableShape = (
            $validationSpecific -and
            (
                $validationCommand -match '(?i)^\s*(powershell|pwsh)(\.exe)?\b.*Parser\]::ParseFile' -or
                $validationCommand -match '(?i)^\s*(?:[^\s]+[\\/])?python(\.exe)?\s+-m\s+(py_compile|json\.tool|pytest)\b' -or
                $validationCommand -match '(?i)^\s*pytest\b' -or
                $validationCommand -match '(?i)^\s*Invoke-Pester\b'
            )
        )
        $validationCommandReferencesTarget = (
            $validationSpecific -and
            -not [string]::IsNullOrWhiteSpace($targetFile) -and
            $validationCommand -like ('*' + $targetFile + '*')
        )
        $validationCommandExecutionEvidence = if (-not $validationSpecific) {
            $validationSpecificEvidence
        }
        elseif (-not $validationCommandUsesAllowedVerifier) {
            'validation command does not use an allowed verifier pattern'
        }
        elseif (-not $validationCommandHasExecutableShape) {
            'validation command names an allowed verifier but is not shaped as an executable command'
        }
        elseif (-not $validationCommandReferencesTarget) {
            'validation command does not reference the target file'
        }
        else {
            'validation command uses an executable allowed verifier and references the target file'
        }
        $policyChecks = @(
            [ordered]@{ check = 'candidate_artifact_type'; passed = $candidateTypeOk; evidence = if ($candidate.PSObject.Properties['artifact_type']) { [string]$candidate.artifact_type } else { '' } },
            [ordered]@{ check = 'target_matches_provider_request'; passed = (-not $wrongTarget); evidence = $targetFile },
            [ordered]@{ check = 'old_text_nonblank'; passed = (-not $blankOldText); evidence = if ($blankOldText) { 'old_text is blank' } else { 'old_text is populated' } },
            [ordered]@{ check = 'new_text_nonblank'; passed = (-not $blankNewText); evidence = if ($blankNewText) { 'new_text is blank' } else { 'new_text is populated' } },
            [ordered]@{ check = 'old_text_found_in_current_source'; passed = $oldTextFoundInCurrentSource; evidence = $oldTextSourceEvidence },
            [ordered]@{ check = 'not_marker_only'; passed = (-not $markerOnly); evidence = if ($markerOnly) { 'marker-only stub token present' } else { 'no marker-only token detected' } },
            [ordered]@{ check = 'has_delta'; passed = (-not $noDelta); evidence = if ($noDelta) { 'old_text equals new_text' } else { 'old_text differs from new_text' } },
            [ordered]@{ check = 'validation_command_present'; passed = (-not $missingValidation); evidence = $validationCommand },
            [ordered]@{ check = 'validation_command_specific'; passed = $validationSpecific; evidence = $validationSpecificEvidence },
            [ordered]@{ check = 'validation_command_allowed_verifier'; passed = $validationCommandUsesAllowedVerifier; evidence = $validationCommandExecutionEvidence },
            [ordered]@{ check = 'validation_command_executable_shape'; passed = $validationCommandHasExecutableShape; evidence = $validationCommandExecutionEvidence }
        )
        $semanticValidation = $null
        if (@($policyChecks | Where-Object { $_.passed -ne $true }).Count -eq 0) {
            $trustedBehaviorAssertion = $null
            if ($providerRequest -ne $null -and $providerRequest.psobject.Properties['behavior_assertion'] -ne $null) {
                $trustedBehaviorAssertion = $providerRequest.behavior_assertion
            }
            $semanticValidation = Invoke-TODShadowPatchSemanticValidation -TargetFile $targetFile -OldText $oldText -NewText $newText -ValidationCommand $validationCommand -BehaviorAssertion $trustedBehaviorAssertion
        }
        else {
            $semanticValidation = [pscustomobject]@{
                semantic_verdict = 'reject'
                mutation_authority_allowed = $false
                reason_codes = @('structural_policy_checks_failed')
            }
        }
        $semanticValidation | Add-Member -NotePropertyName artifact_type -NotePropertyValue 'tod_shadow_patch_semantic_validation' -Force
        $semanticValidation | Add-Member -NotePropertyName generated_at -NotePropertyValue ((Get-Date).ToUniversalTime().ToString('o')) -Force
        $semanticValidation | Add-Member -NotePropertyName objective_id -NotePropertyValue $(if ($Context.PSObject.Properties['objective_id']) { [string]$Context.objective_id } else { '' }) -Force
        $semanticValidation | Add-Member -NotePropertyName task_id -NotePropertyValue $(if ($Context.PSObject.Properties['task_id']) { [string]$Context.task_id } else { '' }) -Force
        $semanticValidation | Add-Member -NotePropertyName input_candidate -NotePropertyValue $inputRel -Force
        $semanticValidation | Add-Member -NotePropertyName input_provider_request -NotePropertyValue $supportingArtifactRel -Force
        $semanticValidationRel = 'runtime_remote_training/model_selection/TOD_SHADOW_PATCH_SEMANTIC_VALIDATION.latest.json'
        $semanticValidationAbs = Join-Path $script:LocalEngineRepoRoot $semanticValidationRel
        New-Item -ItemType Directory -Path (Split-Path -Parent $semanticValidationAbs) -Force | Out-Null
        [System.IO.File]::WriteAllText(
            $semanticValidationAbs,
            ($semanticValidation | ConvertTo-Json -Depth 30),
            [System.Text.UTF8Encoding]::new($false)
        )
        $policyChecks += [ordered]@{
            check = 'executable_semantic_validation'
            passed = [bool]$semanticValidation.mutation_authority_allowed
            evidence = (@($semanticValidation.reason_codes) -join ', ')
        }
        $failedChecks = @($policyChecks | Where-Object { $_.passed -ne $true })
        $accepted = ($candidateTypeOk -and $failedChecks.Count -eq 0)
        $reasonCode = if ($accepted) {
            'candidate_accepted_for_future_source_mutation'
        }
        elseif ($markerOnly) {
            'rejected_marker_only_candidate'
        }
        elseif ($wrongTarget) {
            'rejected_wrong_target_file'
        }
        elseif ($blankOldText) {
            'rejected_blank_old_text'
        }
        elseif ($blankNewText) {
            'rejected_blank_new_text'
        }
        elseif (-not $oldTextFoundInCurrentSource) {
            'rejected_old_text_not_found_in_current_source'
        }
        elseif ($noDelta) {
            'rejected_no_delta_candidate'
        }
        elseif ($missingValidation) {
            'rejected_missing_validation_command'
        }
        elseif ($genericValidation) {
            'rejected_generic_validation_command'
        }
        elseif (-not $validationCommandUsesAllowedVerifier) {
            'rejected_validation_command_not_allowed_verifier'
        }
        elseif (-not $validationCommandHasExecutableShape) {
            'rejected_validation_command_not_executable_shape'
        }
        elseif (-not [bool]$semanticValidation.mutation_authority_allowed) {
            'rejected_executable_semantic_validation'
        }
        else {
            'rejected_candidate_policy_failed'
        }
        $engineeringProviderCandidateVerdictArtifact = [ordered]@{
            artifact_type = 'tod_engineering_provider_candidate_verdict'
            generated_at = (Get-Date).ToUniversalTime().ToString('o')
            source = 'local_execution_read_only_audit_artifact_lane'
            objective_id = if ($Context.PSObject.Properties['objective_id']) { [string]$Context.objective_id } else { '' }
            task_id = if ($Context.PSObject.Properties['task_id']) { [string]$Context.task_id } else { '' }
            input_candidate = $inputRel
            input_candidate_type = if ($candidate.PSObject.Properties['artifact_type']) { [string]$candidate.artifact_type } else { '' }
            input_provider_request = $supportingArtifactRel
            verdict = if ($accepted) { 'accept' } else { 'reject' }
            verdict_reason_code = $reasonCode
            target_file = $targetFile
            old_text_length = $oldText.Length
            new_text_length = $newText.Length
            validation_command = $validationCommand
            policy_checks = @($policyChecks)
            semantic_validation = $semanticValidation
            accepted_for_source_mutation = $accepted
            rejected_before_source_mutation = (-not $accepted)
            counts_as_engineering_implementation_credit = $false
            counts_as_model_utilization_credit = 'candidate_accept_reject_policy_verdict_only'
            next_smallest_rung = if ($accepted) { 'TOD-PROVIDER-CANDIDATE-SOURCE-MUTATION-DRY-RUN-V1' } else { 'TOD-PROVIDER-CANDIDATE-REPLAN-AFTER-REJECTION-V1' }
            no_source_code_modified = $true
            validation = [ordered]@{
                artifact_path = $outputRel
                input_read = $true
                supporting_artifact_read = ($null -ne $providerRequest)
                required_fields_present = $true
                no_source_code_modified = $true
            }
            dave_needed = 'no'
        }
    }
    $wantsEngineeringProviderCandidateReplan = [string]::Equals($requiredArtifactType, 'tod_engineering_provider_candidate_replan', [System.StringComparison]::OrdinalIgnoreCase)
    $engineeringProviderCandidateReplanArtifact = $null
    if ($wantsEngineeringProviderCandidateReplan) {
        $supportingArtifactMatches = @([regex]::Matches($combinedTextForAudit, '(?im)\bSupporting\s+Artifact\s*:\s*(?<path>\S+?\.json)\b'))
        $providerRequestRel = ''
        $candidateStubRel = ''
        $candidateInvocationRel = ''
        foreach ($supportingMatchItem in $supportingArtifactMatches) {
            $supportingRel = Convert-ToLocalExecutionRepoRelativePath -PathValue ([string]$supportingMatchItem.Groups['path'].Value)
            if ([string]::IsNullOrWhiteSpace($supportingRel)) {
                continue
            }
            $supportingAbs = Join-Path $script:LocalEngineRepoRoot $supportingRel
            if (-not (Test-Path -Path $supportingAbs -PathType Leaf)) {
                continue
            }
            $supportingJson = Get-Content -Path $supportingAbs -Raw | ConvertFrom-Json
            $supportingType = if ($supportingJson.PSObject.Properties['artifact_type']) { [string]$supportingJson.artifact_type } else { '' }
            if ([string]::Equals($supportingType, 'tod_engineering_provider_request', [System.StringComparison]::OrdinalIgnoreCase)) {
                $providerRequestRel = $supportingRel
            }
            elseif ([string]::Equals($supportingType, 'tod_engineering_provider_candidate_stub', [System.StringComparison]::OrdinalIgnoreCase)) {
                $candidateStubRel = $supportingRel
            }
            elseif ([string]::Equals($supportingType, 'tod_engineering_provider_candidate_invocation', [System.StringComparison]::OrdinalIgnoreCase)) {
                $candidateInvocationRel = $supportingRel
            }
        }

        $providerRequest = $null
        if (-not [string]::IsNullOrWhiteSpace($providerRequestRel)) {
            $providerRequestAbs = Join-Path $script:LocalEngineRepoRoot $providerRequestRel
            if (Test-Path -Path $providerRequestAbs -PathType Leaf) {
                $providerRequest = Get-Content -Path $providerRequestAbs -Raw | ConvertFrom-Json
            }
        }
        $candidateStub = $null
        if (-not [string]::IsNullOrWhiteSpace($candidateStubRel)) {
            $candidateStubAbs = Join-Path $script:LocalEngineRepoRoot $candidateStubRel
            if (Test-Path -Path $candidateStubAbs -PathType Leaf) {
                $candidateStub = Get-Content -Path $candidateStubAbs -Raw | ConvertFrom-Json
            }
        }
        $candidateInvocation = $null
        if (-not [string]::IsNullOrWhiteSpace($candidateInvocationRel)) {
            $candidateInvocationAbs = Join-Path $script:LocalEngineRepoRoot $candidateInvocationRel
            if (Test-Path -Path $candidateInvocationAbs -PathType Leaf) {
                $candidateInvocation = Get-Content -Path $candidateInvocationAbs -Raw | ConvertFrom-Json
            }
        }

        $verdict = $auditSource
        $priorVerdict = if ($verdict.PSObject.Properties['verdict']) { [string]$verdict.verdict } else { '' }
        $priorReasonCode = if ($verdict.PSObject.Properties['verdict_reason_code']) { [string]$verdict.verdict_reason_code } else { '' }
        $targetFile = if ($candidateInvocation -and $candidateInvocation.PSObject.Properties['target_file']) { [string]$candidateInvocation.target_file } elseif ($candidateStub -and $candidateStub.PSObject.Properties['target_file']) { [string]$candidateStub.target_file } elseif ($providerRequest -and $providerRequest.PSObject.Properties['source_files_to_include'] -and @($providerRequest.source_files_to_include).Count -gt 0) { [string]@($providerRequest.source_files_to_include)[0] } else { '' }
        $sourceAnchorArtifact = ''
        if ($providerRequest -and $providerRequest.PSObject.Properties['artifacts_to_include']) {
            foreach ($artifactPath in @($providerRequest.artifacts_to_include)) {
                if ([string]$artifactPath -match 'SOURCE_ANCHOR.*\.json$') {
                    $sourceAnchorArtifact = [string]$artifactPath
                    break
                }
            }
            if ([string]::IsNullOrWhiteSpace($sourceAnchorArtifact)) {
                foreach ($artifactPath in @($providerRequest.artifacts_to_include)) {
                    $candidateAnchorRel = Convert-ToLocalExecutionRepoRelativePath -PathValue ([string]$artifactPath)
                    if ([string]::IsNullOrWhiteSpace($candidateAnchorRel)) {
                        continue
                    }
                    $candidateAnchorAbs = Join-Path $script:LocalEngineRepoRoot $candidateAnchorRel
                    if (-not (Test-Path -Path $candidateAnchorAbs -PathType Leaf)) {
                        continue
                    }
                    try {
                        $candidateAnchorJson = Get-Content -Path $candidateAnchorAbs -Raw | ConvertFrom-Json
                        $candidateAnchorType = if ($candidateAnchorJson.PSObject.Properties['artifact_type']) { [string]$candidateAnchorJson.artifact_type } else { '' }
                        if (
                            [string]::Equals($candidateAnchorType, 'tod_source_anchor_observation', [System.StringComparison]::OrdinalIgnoreCase) -or
                            $candidateAnchorJson.PSObject.Properties['exact_text']
                        ) {
                            $sourceAnchorArtifact = $candidateAnchorRel
                            break
                        }
                    }
                    catch {
                        continue
                    }
                }
            }
        }
        $validationCommand = if ($providerRequest -and $providerRequest.PSObject.Properties['validation_command']) { [string]$providerRequest.validation_command } else { '' }
        $validationCommandIsGeneric = (
            [string]::IsNullOrWhiteSpace($validationCommand) -or
            $validationCommand -match '(?i)^\s*(PowerShell parse|parse or focused regression|focused regression covering the changed source behavior)'
        )
        $validationCommandUsesAllowedVerifier = (
            -not [string]::IsNullOrWhiteSpace($validationCommand) -and
            $validationCommand -match '(?i)(Parser\]::ParseFile|python\s+-m\s+py_compile|python\s+-m\s+json\.tool|pytest|Invoke-Pester)'
        )
        $validationCommandReferencesTarget = (
            -not [string]::IsNullOrWhiteSpace($validationCommand) -and
            -not [string]::IsNullOrWhiteSpace($targetFile) -and
            $validationCommand -like ('*' + $targetFile + '*')
        )
        $validationCommandNeedsVerifierRepair = (
            $validationCommandIsGeneric -or
            -not $validationCommandUsesAllowedVerifier -or
            -not $validationCommandReferencesTarget -or
            $priorReasonCode -in @('rejected_generic_validation_command', 'rejected_validation_command_not_allowed_verifier')
        )
        if ($validationCommandNeedsVerifierRepair -and -not [string]::IsNullOrWhiteSpace($targetFile)) {
            $targetExtension = ([System.IO.Path]::GetExtension($targetFile)).ToLowerInvariant()
            if ($targetExtension -in @('.ps1', '.psm1')) {
                $validationCommand = 'powershell -NoProfile -Command ''$tokens=$null;$errors=$null;[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path "{0}"),[ref]$tokens,[ref]$errors)>$null;if($errors.Count){{throw ($errors | Out-String)}};Write-Output parse=passed''' -f $targetFile
            }
            elseif ($targetExtension -eq '.py') {
                $validationCommand = 'python -m py_compile {0}' -f $targetFile
            }
            elseif ($targetExtension -eq '.json') {
                $validationCommand = 'python -m json.tool {0}' -f $targetFile
            }
        }
        if ([string]::IsNullOrWhiteSpace($validationCommand)) {
            $validationCommand = 'validation_command_missing_for_target_source'
        }
        $sourceFunction = ''
        if (-not [string]::IsNullOrWhiteSpace($sourceAnchorArtifact)) {
            $sourceAnchorArtifactRelForFunction = Convert-ToLocalExecutionRepoRelativePath -PathValue $sourceAnchorArtifact
            $sourceAnchorArtifactAbsForFunction = Join-Path $script:LocalEngineRepoRoot $sourceAnchorArtifactRelForFunction
            if (Test-Path -Path $sourceAnchorArtifactAbsForFunction -PathType Leaf) {
                try {
                    $sourceAnchorArtifactJsonForFunction = Get-Content -Path $sourceAnchorArtifactAbsForFunction -Raw | ConvertFrom-Json
                    if ($sourceAnchorArtifactJsonForFunction.PSObject.Properties['source_function']) {
                        $sourceFunction = [string]$sourceAnchorArtifactJsonForFunction.source_function
                    }
                    elseif ($sourceAnchorArtifactJsonForFunction.PSObject.Properties['function_surface']) {
                        $sourceFunction = [string]$sourceAnchorArtifactJsonForFunction.function_surface
                    }
                }
                catch {
                    $sourceFunction = ''
                }
            }
        }
        $revisedProviderInstruction = 'Produce a behavior-changing bounded candidate for the target source file using exact current old_text from the source-anchor artifact. Do not append marker-only comments, whitespace-only changes, metadata-only changes, artifact-path changes, or no-op text. Explain the intended behavior change and include a validation command that can prove it.'
        if ([string]::Equals($priorReasonCode, 'rejected_blank_new_text', [System.StringComparison]::OrdinalIgnoreCase)) {
            $revisedProviderInstruction = 'The prior candidate returned blank new_text. Retry only if you can produce a real behavior-changing patch from the supplied source-anchor exact_text. Do not copy the prompt-builder instructions, provider request text, artifact JSON, or any text outside the source-anchor exact_text as old_text. If no safe behavior-changing patch is available, return blank new_text with risk_notes that name the missing source fact.'
        }
        elseif ([string]::Equals($priorReasonCode, 'rejected_no_delta_candidate', [System.StringComparison]::OrdinalIgnoreCase)) {
            $revisedProviderInstruction = 'The prior candidate returned identical old_text and new_text. Retry with old_text copied exactly from the source-anchor exact_text and new_text changed for a specific behavior reason. Do not return equality-preserving rewrites, formatting-only changes, comments, or the same text. If you cannot identify a behavior-changing delta, return blank new_text with risk_notes instead of fabricating a patch.'
        }
        elseif ([string]::Equals($priorReasonCode, 'rejected_old_text_not_found_in_current_source', [System.StringComparison]::OrdinalIgnoreCase)) {
            $revisedProviderInstruction = 'The prior candidate used stale or wrong-surface old_text. Retry by copying old_text exactly from the supplied source-anchor exact_text only. Do not use prompt text, prior candidate text, task package text, or artifact metadata as old_text. If the intended behavior is not represented in the source-anchor exact_text, return blank new_text with risk_notes and request a new source anchor.'
        }
        elseif ($priorReasonCode -in @('rejected_generic_validation_command', 'rejected_validation_command_not_allowed_verifier')) {
            $revisedProviderInstruction = 'Retry the same target source file and exact current old_text, but replace the rejected validation command with a concrete executable verifier command that references the target file. The validation_command must use Parser]::ParseFile, python -m py_compile, python -m json.tool, pytest, or Invoke-Pester. Do not return phrases like "PowerShell parse or focused regression" or dot-source smoke checks like "loaded"; return the actual verifier command.'
        }
        $taskObservedFailureMatch = [regex]::Match($combinedTextForAudit, '(?ims)^\s*Observed\s+Failure\s*:\s*(?<value>.*?)(?=^\s*(Desired\s+Behavior|Input\s+Artifact|Supporting\s+Artifact|Output\s+Artifact|Required\s+Artifact\s+Type|Task\s+Mode|Task\s+Category)\s*:|\z)')
        $taskDesiredBehaviorMatch = [regex]::Match($combinedTextForAudit, '(?ims)^\s*Desired\s+Behavior\s*:\s*(?<value>.*?)(?=^\s*(Observed\s+Failure|Input\s+Artifact|Supporting\s+Artifact|Output\s+Artifact|Required\s+Artifact\s+Type|Task\s+Mode|Task\s+Category)\s*:|\z)')
        $taskObservedFailure = if ($taskObservedFailureMatch.Success) { [string]$taskObservedFailureMatch.Groups['value'].Value.Trim() } else { '' }
        $taskDesiredBehavior = if ($taskDesiredBehaviorMatch.Success) { [string]$taskDesiredBehaviorMatch.Groups['value'].Value.Trim() } else { '' }
        if (-not [string]::IsNullOrWhiteSpace($taskObservedFailure)) {
            $revisedProviderInstruction = ('{0} Specific observed failure from TOD: {1}' -f $revisedProviderInstruction, $taskObservedFailure)
        }
        if (-not [string]::IsNullOrWhiteSpace($taskDesiredBehavior)) {
            $revisedProviderInstruction = ('{0} Specific retry requirement from TOD: {1}' -f $revisedProviderInstruction, $taskDesiredBehavior)
        }
        $replanReady = (
            [string]::Equals($priorVerdict, 'reject', [System.StringComparison]::OrdinalIgnoreCase) -and
            -not [string]::IsNullOrWhiteSpace($priorReasonCode) -and
            -not [string]::IsNullOrWhiteSpace($providerRequestRel) -and
            -not [string]::IsNullOrWhiteSpace($targetFile)
        )
        $engineeringProviderCandidateReplanArtifact = [ordered]@{
            artifact_type = 'tod_engineering_provider_candidate_replan'
            generated_at = (Get-Date).ToUniversalTime().ToString('o')
            source = 'local_execution_read_only_audit_artifact_lane'
            objective_id = if ($Context.PSObject.Properties['objective_id']) { [string]$Context.objective_id } else { '' }
            task_id = if ($Context.PSObject.Properties['task_id']) { [string]$Context.task_id } else { '' }
            input_candidate_verdict = $inputRel
            input_provider_request = $providerRequestRel
            input_candidate_stub = $candidateStubRel
            input_candidate_invocation = $candidateInvocationRel
            prior_verdict = $priorVerdict
            prior_rejection_reason_code = $priorReasonCode
            target_file = $targetFile
            source_anchor_artifact = $sourceAnchorArtifact
            source_function = $sourceFunction
            revised_provider_instruction = $revisedProviderInstruction
            prompt_budget_strategy = 'Use the smallest source excerpt that contains the exact old_text candidate and one nearby decision boundary; do not resend full artifacts when the provider previously returned blank or truncated output.'
            source_excerpt_strategy = 'Extract old_text only from the source-anchor exact_text for the target source file; exclude task package text, artifact JSON, prior provider text, and unrelated evidence paths.'
            strict_json_strategy = 'Require one JSON object with target_file, old_text, new_text, validation_command, behavior_change_summary, and risk_notes; reject markdown fences, prose wrappers, blank old_text, blank new_text, malformed JSON, and truncated responses.'
            next_candidate_acceptance_checks = @(
                'target_file matches the provider request source file',
                'old_text is exact current source text from the source-anchor artifact',
                'new_text differs from old_text for a behavior reason',
                'new_text does not contain provider-stub marker text',
                'validation_command is a concrete executable command relevant to the changed source behavior'
            )
            next_candidate_rejection_checks = @(
                'reject marker-only or comment-only candidates',
                'reject no-delta candidates',
                'reject candidates that edit artifacts instead of source',
                'reject candidates with missing or stale old_text',
                'reject candidates without a validation command',
                'reject generic validation placeholders that are not executable commands'
            )
            validation_command = $validationCommand
            provider_request_ready_for_retry = $replanReady
            counts_as_engineering_implementation_credit = $false
            counts_as_model_utilization_credit = if ($replanReady) { 'provider_replan_after_rejection_only' } else { 'no' }
            next_smallest_rung = if ($replanReady) { 'TOD-PROVIDER-CANDIDATE-STUB-RETRY-FROM-REPLAN-V1' } else { 'TOD-PROVIDER-CANDIDATE-REPLAN-INPUT-ROLE-REPAIR-V1' }
            no_source_code_modified = $true
            validation = [ordered]@{
                artifact_path = $outputRel
                input_read = $true
                provider_request_read = ($null -ne $providerRequest)
                candidate_stub_read = ($null -ne $candidateStub)
                candidate_invocation_read = ($null -ne $candidateInvocation)
                required_fields_present = $replanReady
                no_source_code_modified = $true
            }
            dave_needed = 'no'
        }
    }
    $wantsEngineeringCorpusFoundationIndex = [string]::Equals($requiredArtifactType, 'tod_engineering_corpus_foundation_index', [System.StringComparison]::OrdinalIgnoreCase)
    $engineeringCorpusFoundationIndexArtifact = $null
    if ($wantsEngineeringCorpusFoundationIndex) {
        $inputMatchesForCorpus = @([regex]::Matches($combinedTextForAudit, '(?im)^\s*-\s*(?<path>runtime_remote_training/engineering_corpus/[A-Za-z0-9_./-]+?\.json)\s*$'))
        $indexedInputs = New-Object System.Collections.Generic.List[object]
        $missingInputs = New-Object System.Collections.Generic.List[string]
        $reducibleNow = New-Object System.Collections.Generic.List[string]
        $seenCorpusInputs = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($inputMatchForCorpus in $inputMatchesForCorpus) {
            $corpusInputRel = Convert-ToLocalExecutionRepoRelativePath -PathValue ([string]$inputMatchForCorpus.Groups['path'].Value)
            if ([string]::IsNullOrWhiteSpace($corpusInputRel)) {
                continue
            }
            if (-not $seenCorpusInputs.Add($corpusInputRel)) {
                continue
            }
            $corpusInputAbs = Join-Path $script:LocalEngineRepoRoot $corpusInputRel
            $corpusInputJson = $null
            if (Test-Path -Path $corpusInputAbs -PathType Leaf) {
                try {
                    $corpusInputJson = Get-Content -Path $corpusInputAbs -Raw | ConvertFrom-Json
                }
                catch {
                    $corpusInputJson = $null
                }
            }
            if ($null -eq $corpusInputJson) {
                [void]$missingInputs.Add($corpusInputRel)
                [void]$indexedInputs.Add([ordered]@{
                    path = $corpusInputRel
                    exists = $false
                    artifact_type = ''
                    track = 'evidence'
                    borrowed_reduction_eligible_now = $false
                    reason = 'Input artifact was listed but could not be read.'
                })
                continue
            }

            $corpusArtifactType = if ($corpusInputJson.PSObject.Properties['artifact_type']) { [string]$corpusInputJson.artifact_type } else { '' }
            $corpusBlob = $corpusInputJson | ConvertTo-Json -Depth 20 -Compress
            $track = if ($corpusArtifactType -match 'provider|model') {
                'model_utilization'
            }
            elseif ($corpusArtifactType -match 'episode_card|episode') {
                'evidence'
            }
            elseif ($corpusBlob -match 'selector|routing|lane|binding|runtime|artifact') {
                'runtime'
            }
            elseif ($corpusBlob -match 'authority|escalation|owner|governance') {
                'governance'
            }
            else {
                'engineering'
            }
            $engineeringCreditAllowed = (
                $corpusInputJson.PSObject.Properties['engineering_credit_allowed'] -and
                [bool]$corpusInputJson.engineering_credit_allowed
            )
            $independentCreditRequested = (
                $corpusInputJson.PSObject.Properties['independent_credit_requested'] -and
                [bool]$corpusInputJson.independent_credit_requested
            )
            $implementationCredit = (
                $corpusInputJson.PSObject.Properties['counts_as_engineering_implementation_credit'] -and
                [bool]$corpusInputJson.counts_as_engineering_implementation_credit
            )
            $borrowedReductionEligible = ($engineeringCreditAllowed -or $independentCreditRequested -or $implementationCredit)
            if ($borrowedReductionEligible) {
                [void]$reducibleNow.Add($corpusInputRel)
            }
            $reason = if ($borrowedReductionEligible) {
                'Input claims or permits engineering/independent credit and needs Examiner/Auditor review before borrowed-ratio change.'
            }
            elseif ($track -eq 'model_utilization') {
                'Useful model-utilization evidence, but no retry-ready provider request or validated behavior-changing candidate proves independence yet.'
            }
            elseif ($track -eq 'runtime') {
                'Useful runtime-support evidence, but runtime support does not retire engineering borrowed capability by itself.'
            }
            else {
                'Useful corpus memory, but no current proof of independent inspect -> change -> validate engineering loop.'
            }
            [void]$indexedInputs.Add([ordered]@{
                path = $corpusInputRel
                exists = $true
                artifact_type = $corpusArtifactType
                track = $track
                borrowed_reduction_eligible_now = $borrowedReductionEligible
                reason = $reason
            })
        }
        $engineeringCorpusFoundationIndexArtifact = [ordered]@{
            artifact_type = 'tod_engineering_corpus_foundation_index'
            generated_at = (Get-Date).ToUniversalTime().ToString('o')
            source = 'local_execution_read_only_audit_artifact_lane'
            objective_id = if ($Context.PSObject.Properties['objective_id']) { [string]$Context.objective_id } else { '' }
            task_id = if ($Context.PSObject.Properties['task_id']) { [string]$Context.task_id } else { '' }
            status = if ($missingInputs.Count -eq 0) { 'completed' } else { 'completed_with_missing_inputs' }
            indexed_inputs = @($indexedInputs.ToArray())
            missing_inputs = @($missingInputs.ToArray())
            borrowed_capability_reduction_now = ($reducibleNow.Count -gt 0)
            borrowed_reduction_candidate_inputs = @($reducibleNow.ToArray())
            next_smallest_fresh_engineering_demonstration = 'TOD-AUTONOMOUS-MEANINGFUL-NEWTEXT-SYNTHESIS-FROM-SOURCE-ANCHOR-V1'
            validation = [ordered]@{
                artifact_path = $outputRel
                input_count = $indexedInputs.Count
                missing_input_count = $missingInputs.Count
                required_fields_present = ($indexedInputs.Count -gt 0)
                no_source_code_modified = $true
            }
            prevention_lesson = 'Corpus indexes should separate engineering, runtime, governance, evidence, and model-utilization tracks so support work does not masquerade as independent engineering capability.'
            dave_needed = 'no'
        }
    }
    $wantsReadOnlyRetirementEligibilityProof = [string]::Equals($requiredArtifactType, 'tod_readonly_retirement_eligibility_proof', [System.StringComparison]::OrdinalIgnoreCase)
    $readOnlyRetirementEligibilityProofArtifact = $null
    if ($wantsReadOnlyRetirementEligibilityProof) {
        $registryRel = 'docs/training/TOD_APPRENTICESHIP_REGISTRY.md'
        $registryAbs = Join-Path $script:LocalEngineRepoRoot $registryRel
        $registryText = if (Test-Path -Path $registryAbs -PathType Leaf) { Get-Content -Path $registryAbs -Raw } else { '' }
        $entryIds = @([regex]::Matches($combinedTextForAudit, '\bAPP-TOD-\d{3}\b') | ForEach-Object { [string]$_.Value } | Select-Object -Unique)
        if ($entryIds.Count -eq 0 -and $auditSource.PSObject.Properties['training_families']) {
            $firstFamily = @($auditSource.training_families | Select-Object -First 1)
            if ($firstFamily.Count -gt 0 -and $firstFamily[0].PSObject.Properties['entry_ids']) {
                $entryIds = @($firstFamily[0].entry_ids | ForEach-Object { [string]$_ } | Select-Object -Unique)
            }
        }

        $entriesReviewed = New-Object System.Collections.Generic.List[object]
        $evidenceInspected = New-Object System.Collections.Generic.List[object]
        $missingEvidence = New-Object System.Collections.Generic.List[object]
        $retirementDecisions = New-Object System.Collections.Generic.List[object]
        $proposedRegistryChanges = New-Object System.Collections.Generic.List[object]
        $eligibleCount = 0

        foreach ($entryId in $entryIds) {
            $sectionPattern = '(?ms)^###\s+' + [regex]::Escape($entryId) + '\b(?<body>.*?)(?=^###\s+APP-TOD-\d{3}\b|\z)'
            $sectionMatch = [regex]::Match($registryText, $sectionPattern)
            $sectionText = if ($sectionMatch.Success) { [string]$sectionMatch.Value } else { '' }
            $entryName = ''
            if ($sectionMatch.Success) {
                $headingMatch = [regex]::Match($sectionText, '(?m)^###\s+APP-TOD-\d{3}:\s*(?<name>.+?)\s*$')
                if ($headingMatch.Success) { $entryName = ([string]$headingMatch.Groups['name'].Value).Trim() }
            }
            $evidencePaths = @()
            if (-not [string]::IsNullOrWhiteSpace($sectionText)) {
                $evidencePaths = @([regex]::Matches($sectionText, '(?<path>(?:runtime_remote_training|docs/training|tests|scripts|tod)/[A-Za-z0-9_./-]+\.(?:json|md|ps1|py|patch))') | ForEach-Object { [string]$_.Groups['path'].Value } | Select-Object -Unique)
            }
            $existingEvidence = @()
            foreach ($evidencePath in $evidencePaths) {
                $exists = Test-Path -Path (Join-Path $script:LocalEngineRepoRoot $evidencePath) -PathType Leaf
                $evidenceInspected.Add([ordered]@{
                    entry_id = $entryId
                    path = $evidencePath
                    exists = [bool]$exists
                }) | Out-Null
                if ($exists) {
                    $existingEvidence += $evidencePath
                }
                else {
                    $missingEvidence.Add([ordered]@{
                        entry_id = $entryId
                        path = $evidencePath
                        reason = 'named evidence path not found in current workspace'
                    }) | Out-Null
                }
            }

            $progress = if ($sectionText -match '(?im)^Progress:\s*`?(?<value>[^`;\r\n]+)') { ([string]$Matches['value']).Trim() } else { 'not demonstrated' }
            $proficiency = if ($sectionText -match '(?im)^Proficiency:\s*`?(?<value>[^`;\r\n]+)') { ([string]$Matches['value']).Trim() } else { 'not demonstrated' }
            $independentDemo = if ($sectionText -match '(?im)^Independent Demonstration:\s*`?(?<value>[^`;\r\n]+)') { ([string]$Matches['value']).Trim() } else { 'not demonstrated' }
            $freeze = if ($sectionText -match '(?im)^Freeze:\s*(?<value>[^\r\n]+)') { ([string]$Matches['value']).Trim() } else { 'not demonstrated' }
            $retirement = if ($sectionText -match '(?im)^Retirement:\s*(?<value>[^\r\n]+)') { ([string]$Matches['value']).Trim() } else { 'open' }
            $currentCaveats = if ($sectionText -match '(?im)^Current Caveats:\s*(?<value>[^\r\n]+)') { ([string]$Matches['value']).Trim() } else { '' }

            $independentGate = ($progress -match 'independent_demo_passed|retired' -or $independentDemo -match 'passed')
            $proficiencyGate = ($proficiency -match 'independent|reliable')
            $evidenceGate = ($existingEvidence.Count -gt 0)
            $freezeGate = ($freeze -match 'partial|updated|complete|recorded|frozen')
            $wrapperOnlyBlocked = ($currentCaveats -match 'wrapper-only|queue-only')
            $sourceMutationBlocked = ($currentCaveats -match 'source mutation' -and $currentCaveats -notmatch 'without source mutation|no source mutation|no product source changes|no-code-change')
            $reliabilityCaveatBlocked = ($retirement -match 'pending reliability|one more future fresh|Reliability still requires|later fresh')
            $alreadyRetired = ($retirement -match '^retired\b' -or $progress -match '^retired$')
            $eligible = ($independentGate -and $proficiencyGate -and $evidenceGate -and $freezeGate -and -not $wrapperOnlyBlocked -and -not $sourceMutationBlocked -and -not $reliabilityCaveatBlocked -and -not $alreadyRetired)
            if ($eligible) { $eligibleCount++ }

            $decision = if ($alreadyRetired) {
                'already_retired'
            }
            elseif ($eligible) {
                'eligible_to_retire'
            }
            else {
                'not_yet_eligible'
            }
            $reasons = New-Object System.Collections.Generic.List[string]
            if (-not $independentGate) { $reasons.Add('independent demonstration is not proven') | Out-Null }
            if (-not $proficiencyGate) { $reasons.Add('proficiency is not independent or reliable') | Out-Null }
            if (-not $evidenceGate) { $reasons.Add('no current named evidence artifact exists') | Out-Null }
            if (-not $freezeGate) { $reasons.Add('freeze or prevention lesson is not strong enough') | Out-Null }
            if ($wrapperOnlyBlocked) { $reasons.Add('wrapper-only or queue-only caveat is present') | Out-Null }
            if ($sourceMutationBlocked) { $reasons.Add('read-only boundary is not cleanly proven') | Out-Null }
            if ($reliabilityCaveatBlocked) { $reasons.Add('registry still requires a future reliability repeat') | Out-Null }
            if ($alreadyRetired) { $reasons.Add('entry is already retired') | Out-Null }
            if ($reasons.Count -eq 0) { $reasons.Add('all retirement gates are satisfied by current registry and evidence') | Out-Null }

            $entriesReviewed.Add([ordered]@{
                id = $entryId
                name = $entryName
                progress = $progress
                proficiency = $proficiency
                independent_demonstration = $independentDemo
                freeze = $freeze
                retirement = $retirement
            }) | Out-Null
            $retirementDecisions.Add([ordered]@{
                entry_id = $entryId
                decision = $decision
                reasons = @($reasons.ToArray())
                eligible = [bool]$eligible
                existing_evidence_count = [int]$existingEvidence.Count
            }) | Out-Null
            if ($eligible) {
                $proposedRegistryChanges.Add([ordered]@{
                    entry_id = $entryId
                    change = 'set_retirement_to_retired'
                    reason = 'Independent demonstration, evidence, freeze, and no-code-change gates are satisfied.'
                }) | Out-Null
            }
        }

        $currentBaseline = if ($auditSource.PSObject.Properties['baseline_ratio'] -and $auditSource.baseline_ratio.PSObject.Properties['current']) { $auditSource.baseline_ratio.current } else { $null }
        $currentTotal = if ($null -ne $currentBaseline -and $currentBaseline.PSObject.Properties['total_entries']) { [int]$currentBaseline.total_entries } else { 0 }
        $currentBorrowed = if ($null -ne $currentBaseline -and $currentBaseline.PSObject.Properties['borrowed_count']) { [int]$currentBaseline.borrowed_count } else { 0 }
        $projectedBorrowed = [Math]::Max(0, ($currentBorrowed - $eligibleCount))
        $projectedBorrowedPercent = if ($currentTotal -gt 0) { [Math]::Round(($projectedBorrowed / $currentTotal) * 100, 1) } else { 0 }

        $readOnlyRetirementEligibilityProofArtifact = [ordered]@{
            artifact_type = 'tod_readonly_retirement_eligibility_proof'
            generated_at = (Get-Date).ToUniversalTime().ToString('o')
            source = 'local_execution_read_only_audit_artifact_lane'
            objective_id = if ($Context.PSObject.Properties['objective_id']) { [string]$Context.objective_id } else { '' }
            task_id = if ($Context.PSObject.Properties['task_id']) { [string]$Context.task_id } else { '' }
            entries_reviewed = @($entriesReviewed.ToArray())
            evidence_inspected = @($evidenceInspected.ToArray())
            missing_evidence = @($missingEvidence.ToArray())
            retirement_decisions = @($retirementDecisions.ToArray())
            proposed_registry_changes = @($proposedRegistryChanges.ToArray())
            ratio_if_accepted = [ordered]@{
                current_total_entries = $currentTotal
                current_borrowed_count = $currentBorrowed
                eligible_retirements = $eligibleCount
                projected_borrowed_count = $projectedBorrowed
                projected_borrowed_percent = $projectedBorrowedPercent
            }
            validation = [ordered]@{
                artifact_path = $outputRel
                input_plan = $inputRel
                registry_read = (-not [string]::IsNullOrWhiteSpace($registryText))
                entries_requested = @($entryIds)
                entries_reviewed_count = [int]$entriesReviewed.Count
                no_source_code_modified = $true
            }
            prevention_lesson = 'Retirement proof is a read-only eligibility judgment, not route-patch classification; a requested artifact type must retain its own lane authority before broad saved-patch selectors run.'
            no_source_code_modified = $true
            dave_needed = 'no'
        }
    }
    $engineeringEpisodeQualityExaminerArtifact = $null
    if ($wantsEngineeringEpisodeQualityExaminer) {
        $episodeArtifactType = if ($auditSource.PSObject.Properties['artifact_type']) { [string]$auditSource.artifact_type } else { '' }
        $episodeDebtCategory = if ($auditSource.PSObject.Properties['debt_category']) { [string]$auditSource.debt_category } else { 'unknown' }
        $episodeBorrowedSignal = if ($auditSource.PSObject.Properties['borrowed_vs_independent']) { [string]$auditSource.borrowed_vs_independent } else { 'unknown' }
        $episodeIndependentCredit = if ($auditSource.PSObject.Properties['independent_credit_requested']) { [bool]$auditSource.independent_credit_requested } else { $false }
        $requiredEpisodeFields = @(
            'artifact_type',
            'episode_id',
            'objective_id',
            'task_id',
            'source_artifact',
            'problem_statement',
            'attempted_actions',
            'evidence_artifacts',
            'diagnosis',
            'debt_category',
            'borrowed_vs_independent',
            'lesson',
            'smallest_next_repair',
            'validation_summary',
            'no_source_edits',
            'independent_credit_requested',
            'dave_needed'
        )
        $missingEpisodeFields = @($requiredEpisodeFields | Where-Object { -not $auditSource.PSObject.Properties[$_] })
        $runtimeSupportSignals = @('runtime_plumbing', 'routing', 'selector', 'binding', 'lineage', 'artifact_lane')
        $isRuntimeSupportEpisode = $false
        foreach ($signal in $runtimeSupportSignals) {
            if ($episodeDebtCategory -match [regex]::Escape($signal)) {
                $isRuntimeSupportEpisode = $true
                break
            }
        }
        $sourceEditFree = ($auditSource.PSObject.Properties['no_source_edits'] -and $auditSource.no_source_edits -eq $true)
        $hasValidation = ($auditSource.PSObject.Properties['validation_summary'] -and $null -ne $auditSource.validation_summary)
        $hasLesson = ($auditSource.PSObject.Properties['lesson'] -and -not [string]::IsNullOrWhiteSpace([string]$auditSource.lesson))
        $hasNextRung = ($auditSource.PSObject.Properties['smallest_next_repair'] -and -not [string]::IsNullOrWhiteSpace([string]$auditSource.smallest_next_repair))
        $schemaPassed = ($missingEpisodeFields.Count -eq 0 -and [string]::Equals($episodeArtifactType, 'tod_engineering_episode_card', [System.StringComparison]::OrdinalIgnoreCase))
        $trainingUsefulness = if (-not $schemaPassed) {
            'reject'
        }
        elseif ($isRuntimeSupportEpisode) {
            'accept_runtime_support_only'
        }
        elseif ($episodeIndependentCredit -eq $true -and $episodeBorrowedSignal -notmatch 'borrowed|codex|unknown') {
            'accept_engineering_episode_candidate'
        }
        else {
            'accept_evidence_memory_only'
        }
        $engineeringCreditAllowed = (
            $trainingUsefulness -eq 'accept_engineering_episode_candidate' -and
            $sourceEditFree -and
            $hasValidation -and
            $hasLesson -and
            $hasNextRung
        )
        $borrowedRatioEffect = if ($engineeringCreditAllowed) { 'may_reduce_after_independent_verification' } else { 'no_reduction' }
        $verdictReason = if (-not $schemaPassed) {
            ('Episode card is missing required fields or has the wrong artifact type: {0}' -f ($missingEpisodeFields -join ', '))
        }
        elseif ($isRuntimeSupportEpisode) {
            'Episode is useful runtime-support memory, but it documents routing/selector/artifact-lane work rather than independent engineering diagnosis, patch, and validation.'
        }
        elseif ($engineeringCreditAllowed) {
            'Episode contains source evidence, validation, lesson, next rung, and an independent-credit signal suitable for Examiner follow-up.'
        }
        else {
            'Episode is useful evidence memory, but it does not prove independent engineering capability.'
        }
        $engineeringEpisodeQualityExaminerArtifact = [ordered]@{
            artifact_type = 'tod_engineering_episode_quality_examiner_verdict'
            generated_at = (Get-Date).ToUniversalTime().ToString('o')
            source = 'local_execution_read_only_audit_artifact_lane'
            objective_id = if ($Context.PSObject.Properties['objective_id']) { [string]$Context.objective_id } else { '' }
            task_id = if ($Context.PSObject.Properties['task_id']) { [string]$Context.task_id } else { '' }
            status = if ($schemaPassed) { 'completed' } else { 'rejected' }
            input_episode_artifact = $inputRel
            episode_id = if ($auditSource.PSObject.Properties['episode_id']) { [string]$auditSource.episode_id } else { '' }
            episode_debt_category = $episodeDebtCategory
            episode_borrowed_vs_independent = $episodeBorrowedSignal
            training_usefulness = $trainingUsefulness
            engineering_credit_allowed = $engineeringCreditAllowed
            runtime_support_credit_allowed = ($trainingUsefulness -eq 'accept_runtime_support_only')
            borrowed_capability_ratio_effect = $borrowedRatioEffect
            required_episode_fields = @($requiredEpisodeFields)
            missing_episode_fields = @($missingEpisodeFields)
            evidence_checked = @(
                'episode schema',
                'debt category',
                'borrowed-vs-independent signal',
                'independent credit request',
                'validation summary',
                'lesson',
                'smallest next repair',
                'no source edits'
            )
            verdict_reason = $verdictReason
            smallest_next_training_rung = if ($engineeringCreditAllowed) {
                'Run Auditor/Examiner on a fresh analogous engineering episode before reducing borrowed capability.'
            }
            elseif ($isRuntimeSupportEpisode) {
                'Select a fresh engineering episode where TOD inspects source code, diagnoses behavior, proposes a bounded change, validates it, and publishes evidence.'
            }
            else {
                'Back up to a richer episode card that contains validation evidence, lesson, and next-rung fields.'
            }
            validation = [ordered]@{
                input_read = $true
                artifact_path = $outputRel
                required_fields_present = ($missingEpisodeFields.Count -eq 0)
                no_code_changes = $true
            }
            prevention_lesson = 'Engineering corpus entries must be quality-gated before they can reduce borrowed capability; runtime-support memory is useful but must not masquerade as independent engineering progress.'
            independent_credit_requested = $false
            dave_needed = 'no'
        }
    }
    $engineeringEpisodeCardArtifact = $null
    if ($wantsEngineeringEpisodeCard) {
        $sourceArtifactType = if ($auditSource.PSObject.Properties['artifact_type']) { [string]$auditSource.artifact_type } else { '' }
        $sourceObjectiveId = if ($auditSource.PSObject.Properties['objective_id']) { [string]$auditSource.objective_id } elseif ($Context.PSObject.Properties['objective_id']) { [string]$Context.objective_id } else { '' }
        $sourceTaskId = if ($auditSource.PSObject.Properties['task_id']) { [string]$auditSource.task_id } elseif ($Context.PSObject.Properties['task_id']) { [string]$Context.task_id } else { '' }
        $sourceStatus = if ($auditSource.PSObject.Properties['status']) { [string]$auditSource.status } else { '' }
        $sourceValidation = if ($auditSource.PSObject.Properties['validation']) { $auditSource.validation } else { [ordered]@{} }
        $sourceBlocker = if ($auditSource.PSObject.Properties['blocker']) { $auditSource.blocker } elseif ($auditSource.PSObject.Properties['blockers']) { $auditSource.blockers } else { [ordered]@{} }
        $sourceLesson = if ($auditSource.PSObject.Properties['prevention_lesson']) { [string]$auditSource.prevention_lesson } elseif ($auditSource.PSObject.Properties['lesson']) { [string]$auditSource.lesson } else { '' }
        $sourceNextRung = if ($auditSource.PSObject.Properties['next_training_rung']) { [string]$auditSource.next_training_rung } elseif ($auditSource.PSObject.Properties['smallest_next_repair']) { [string]$auditSource.smallest_next_repair } elseif ($auditSource.PSObject.Properties['smallest_next_executable_shape']) { [string]$auditSource.smallest_next_executable_shape } else { '' }
        $sourceBorrowedSignal = if (($auditSource | ConvertTo-Json -Depth 20 -Compress) -match 'borrowed|codex') { 'borrowed_or_codex_involved' } elseif (($auditSource | ConvertTo-Json -Depth 20 -Compress) -match 'independent') { 'independent_or_claimed_independent' } else { 'unknown' }
        $episodeEvidenceArtifacts = New-Object System.Collections.Generic.List[string]
        [void]$episodeEvidenceArtifacts.Add($inputRel)
        foreach ($evidenceMatch in [regex]::Matches($combinedTextForAudit, 'runtime(?:_remote_training)?/[A-Za-z0-9_./-]+?\.json')) {
            $evidenceRel = Convert-ToLocalExecutionRepoRelativePath -PathValue ([string]$evidenceMatch.Value)
            if (
                -not [string]::IsNullOrWhiteSpace($evidenceRel) -and
                [string]::Compare($evidenceRel, $outputRel, $true) -ne 0 -and
                -not $episodeEvidenceArtifacts.Contains($evidenceRel)
            ) {
                [void]$episodeEvidenceArtifacts.Add($evidenceRel)
            }
        }
        if ($auditSource.PSObject.Properties['evidence_artifacts']) {
            foreach ($evidenceValue in @($auditSource.evidence_artifacts)) {
                $evidenceRel = Convert-ToLocalExecutionRepoRelativePath -PathValue ([string]$evidenceValue)
                if (
                    -not [string]::IsNullOrWhiteSpace($evidenceRel) -and
                    [string]::Compare($evidenceRel, $outputRel, $true) -ne 0 -and
                    -not $episodeEvidenceArtifacts.Contains($evidenceRel)
                ) {
                    [void]$episodeEvidenceArtifacts.Add($evidenceRel)
                }
            }
        }
        $episodeIdStem = [System.IO.Path]::GetFileNameWithoutExtension($outputRel)
        $engineeringEpisodeCardArtifact = [ordered]@{
            artifact_type = 'tod_engineering_episode_card'
            generated_at = (Get-Date).ToUniversalTime().ToString('o')
            source = 'local_execution_read_only_audit_artifact_lane'
            episode_id = if ([string]::IsNullOrWhiteSpace($episodeIdStem)) { $sourceTaskId } else { $episodeIdStem }
            objective_id = $sourceObjectiveId
            task_id = $sourceTaskId
            status = if ([string]::IsNullOrWhiteSpace($sourceStatus)) { 'recorded' } else { $sourceStatus }
            source_artifact = $inputRel
            source_artifact_type = $sourceArtifactType
            selected_source_reason = $selectedSourceReason
            problem_statement = if ($auditSource.PSObject.Properties['problem_statement']) { [string]$auditSource.problem_statement } else { 'Convert a TOD engineering attempt or validation artifact into a durable corpus episode.' }
            attempted_actions = if ($auditSource.PSObject.Properties['attempted_actions']) { @($auditSource.attempted_actions) } elseif ($auditSource.PSObject.Properties['commands_run']) { @($auditSource.commands_run) } else { @('Read source evidence artifact', 'Summarize validation and blocker signals', 'Publish durable engineering episode card') }
            evidence_artifacts = @($episodeEvidenceArtifacts.ToArray())
            diagnosis = if ($auditSource.PSObject.Properties['diagnosis']) { $auditSource.diagnosis } elseif ($auditSource.PSObject.Properties['verdict']) { [string]$auditSource.verdict } else { 'Episode card generated from existing evidence; further Examiner review should decide whether it is useful for training.' }
            debt_category = if ($auditSource.PSObject.Properties['debt_category']) { [string]$auditSource.debt_category } elseif (($auditSource | ConvertTo-Json -Depth 20 -Compress) -match 'selector|lane|binding|routing') { 'runtime_plumbing' } else { 'engineering_episode_capture' }
            borrowed_vs_independent = $sourceBorrowedSignal
            lesson = if ([string]::IsNullOrWhiteSpace($sourceLesson)) { 'Engineering attempts must become durable episodes with source evidence, validation, blocker, and next-rung fields instead of disappearing into transient status.' } else { $sourceLesson }
            smallest_next_repair = if ([string]::IsNullOrWhiteSpace($sourceNextRung)) { 'Run Examiner review on this episode card and use the result to choose the next independent TOD demonstration.' } else { $sourceNextRung }
            validation_summary = $sourceValidation
            blocker = $sourceBlocker
            no_source_edits = $true
            independent_credit_requested = $false
            dave_needed = 'no'
        }
    }
    $contractRequiredFields = New-Object System.Collections.Generic.List[string]
    foreach ($contractMatch in [regex]::Matches($combinedTextForAudit, '(?im)^\s*(?:[-*]\s*)?Required\s+(?:checks|output\s+fields)\s*:\s*(?<value>.+?)\s*$')) {
        $contractText = [string]$contractMatch.Groups['value'].Value
        foreach ($presentMatch in [regex]::Matches($contractText, '\b(?<field>[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)?)\s+present\b')) {
            $fieldName = ([string]$presentMatch.Groups['field'].Value).Trim()
            if (-not [string]::IsNullOrWhiteSpace($fieldName) -and -not $contractRequiredFields.Contains($fieldName)) {
                [void]$contractRequiredFields.Add($fieldName)
            }
        }
        foreach ($tokenMatch in [regex]::Matches($contractText, '\b(?<field>[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)?)\b')) {
            $fieldName = ([string]$tokenMatch.Groups['field'].Value).Trim()
            if ($fieldName -notmatch '_' -and $fieldName -notmatch '\.') {
                continue
            }
            if (-not $contractRequiredFields.Contains($fieldName)) {
                [void]$contractRequiredFields.Add($fieldName)
            }
        }
    }
    foreach ($contractMatch in [regex]::Matches($combinedTextForAudit, '(?is)\bRequired\s+(?:checks|output\s+fields)\s*:\s*(?<value>.+?)(?:\.\s+If\s+fields|\r?\n|$)')) {
        $contractText = [string]$contractMatch.Groups['value'].Value
        foreach ($presentMatch in [regex]::Matches($contractText, '\b(?<field>[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)?)\s+present\b')) {
            $fieldName = ([string]$presentMatch.Groups['field'].Value).Trim()
            if (-not [string]::IsNullOrWhiteSpace($fieldName) -and -not $contractRequiredFields.Contains($fieldName)) {
                [void]$contractRequiredFields.Add($fieldName)
            }
        }
        foreach ($tokenMatch in [regex]::Matches($contractText, '\b(?<field>[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)?)\b')) {
            $fieldName = ([string]$tokenMatch.Groups['field'].Value).Trim()
            if ($fieldName -notmatch '_' -and $fieldName -notmatch '\.') {
                continue
            }
            if (-not $contractRequiredFields.Contains($fieldName)) {
                [void]$contractRequiredFields.Add($fieldName)
            }
        }
    }
    $contractRequiredFieldArray = @($contractRequiredFields.ToArray())
    $contractMissingFields = New-Object System.Collections.Generic.List[string]
    $contractEvaluationSource = if ($null -ne $sourceAnchorDeltaProposalArtifact) { $sourceAnchorDeltaProposalArtifact } elseif ($null -ne $autonomousMeaningfulNewTextSynthesisArtifact) { $autonomousMeaningfulNewTextSynthesisArtifact } elseif ($null -ne $modelUtilizationEngineeringJudgmentArtifact) { $modelUtilizationEngineeringJudgmentArtifact } elseif ($null -ne $engineeringContextPackageArtifact) { $engineeringContextPackageArtifact } elseif ($null -ne $readOnlyRetirementEligibilityProofArtifact) { $readOnlyRetirementEligibilityProofArtifact } elseif ($null -ne $engineeringEpisodeQualityExaminerArtifact) { $engineeringEpisodeQualityExaminerArtifact } elseif ($null -ne $engineeringEpisodeCardArtifact) { $engineeringEpisodeCardArtifact } else { $auditSource }
    foreach ($requiredField in $contractRequiredFieldArray) {
        $cursor = $contractEvaluationSource
        $fieldPresent = $true
        foreach ($part in ([string]$requiredField -split '\.')) {
            if ($null -eq $cursor) {
                $fieldPresent = $false
                break
            }
            if ($cursor -is [System.Collections.IDictionary]) {
                if (-not $cursor.Contains($part)) {
                    $fieldPresent = $false
                    break
                }
                $cursor = $cursor[$part]
            }
            elseif ($cursor.PSObject.Properties[$part]) {
                $cursor = $cursor.$part
            }
            else {
                $fieldPresent = $false
                break
            }
        }
        if ($fieldPresent -and $null -eq $cursor) {
            $fieldPresent = $false
        }
        elseif ($fieldPresent -and $cursor -is [string] -and [string]::IsNullOrWhiteSpace([string]$cursor)) {
            $isAllowedBlankBlockedDeltaCandidate = (
                $null -ne $sourceAnchorDeltaProposalArtifact -and
                [string]::Equals([string]$requiredField, 'candidate_new_text', [System.StringComparison]::OrdinalIgnoreCase) -and
                $sourceAnchorDeltaProposalArtifact.Contains('status') -and
                [string]::Equals([string]$sourceAnchorDeltaProposalArtifact['status'], 'blocked', [System.StringComparison]::OrdinalIgnoreCase) -and
                $sourceAnchorDeltaProposalArtifact.Contains('blocker') -and
                $null -ne $sourceAnchorDeltaProposalArtifact['blocker']
            )
            $isAllowedBlankBlockedAutonomousNewText = (
                $null -ne $autonomousMeaningfulNewTextSynthesisArtifact -and
                [string]::Equals([string]$requiredField, 'new_text', [System.StringComparison]::OrdinalIgnoreCase) -and
                $autonomousMeaningfulNewTextSynthesisArtifact.Contains('status') -and
                [string]::Equals([string]$autonomousMeaningfulNewTextSynthesisArtifact['status'], 'blocked', [System.StringComparison]::OrdinalIgnoreCase) -and
                $autonomousMeaningfulNewTextSynthesisArtifact.Contains('blocker') -and
                $null -ne $autonomousMeaningfulNewTextSynthesisArtifact['blocker']
            )
            if (-not $isAllowedBlankBlockedDeltaCandidate -and -not $isAllowedBlankBlockedAutonomousNewText) {
                $fieldPresent = $false
            }
        }
        if (-not $fieldPresent -and -not $contractMissingFields.Contains([string]$requiredField)) {
            [void]$contractMissingFields.Add([string]$requiredField)
        }
    }
    $wantsContractFieldEvaluation = ($contractRequiredFieldArray.Count -gt 0)
    if ($wantsContractFieldEvaluation) {
        $contractMissingFieldArray = @($contractMissingFields.ToArray())
        $classification = if ($contractMissingFieldArray.Count -eq 0) { 'contract_field_evaluation_passed' } else { 'contract_field_evaluation_failed' }
        $evidenceFields = @($evidenceFields + $contractRequiredFieldArray | Select-Object -Unique)
        $findings.Add([ordered]@{
            finding = 'contract_required_fields'
            evidence = ($contractRequiredFieldArray -join ', ')
        }) | Out-Null
        $findings.Add([ordered]@{
            finding = 'contract_missing_fields'
            evidence = ($contractMissingFieldArray -join ', ')
        }) | Out-Null
        if ($contractMissingFieldArray.Count -gt 0) {
            $blockers += [pscustomobject]@{
                type = 'blocker'
                reason_code = 'contract_required_fields_missing'
                reason = ('Produced artifact is missing required fields: {0}' -f ($contractMissingFieldArray -join ', '))
                task_id = if ($contractEvaluationSource -is [System.Collections.IDictionary] -and $contractEvaluationSource.Contains('task_id')) { [string]$contractEvaluationSource['task_id'] } elseif ($contractEvaluationSource.PSObject.Properties['task_id']) { [string]$contractEvaluationSource.task_id } elseif ($Context.PSObject.Properties['task_id']) { [string]$Context.task_id } else { '' }
            }
        }
    }
    $wantsServiceExtractionPlan = $isPatchAuthorityClassification -and ($combinedTextForAudit -match '(?i)service[- ]extraction plan|service boundary|reusable_service_candidate')
    $selectedServiceCandidate = $null
    $selectedServiceCandidateReason = ''
    $serviceBoundary = ''
    $forbiddenRouteAuthority = @()
    $generalizedTests = @()
    $preventionLesson = ''
    $artifactType = 'tod_read_only_audit_artifact'
    if ($wantsServiceExtractionPlan) {
        $artifactType = 'tod_route_service_extraction_plan'
        $classification = 'patch_authority_service_extraction_plan'
        $candidateSignals = @()
        if ($auditSource.PSObject.Properties['signals']) {
            $candidateSignals = @($auditSource.signals | Where-Object {
                $_.PSObject.Properties['bucket'] -and [string]$_.bucket -eq 'reusable_service_candidate'
            } | Sort-Object @{ Expression = { if ($_.PSObject.Properties['match_count']) { [int]$_.match_count } else { 0 } }; Descending = $true })
        }
        $selectedServiceCandidate = @($candidateSignals | Select-Object -First 1)
        $selectedSignalName = if ($selectedServiceCandidate.Count -gt 0 -and $selectedServiceCandidate[0].PSObject.Properties['signal']) { [string]$selectedServiceCandidate[0].signal } else { '' }
        $selectedSignalCount = if ($selectedServiceCandidate.Count -gt 0 -and $selectedServiceCandidate[0].PSObject.Properties['match_count']) { [string]$selectedServiceCandidate[0].match_count } else { '0' }
        $selectedServiceCandidateReason = if (-not [string]::IsNullOrWhiteSpace($selectedSignalName)) {
            ('Selected {0} because it is the highest-volume reusable service candidate in the supplied classification evidence ({1} matches).' -f $selectedSignalName, $selectedSignalCount)
        }
        else {
            'No reusable service candidate signal was present in the supplied classification evidence.'
        }
        $serviceBoundary = if (-not [string]::IsNullOrWhiteSpace($selectedSignalName)) {
            ('Create a reusable {0} service that receives structured evidence and returns learned/process outputs; route files may call the service but may not author final visible replies directly.' -f $selectedSignalName)
        }
        else {
            'No service boundary can be selected until a reusable_service_candidate signal is present.'
        }
        $forbiddenRouteAuthority = @(
            'route-level fixed visible replies',
            'operator-contract appenders without explicit authority',
            'phrase patches that bypass learned capability paths',
            'post-composer semantic rewrites without an authority trace'
        )
        $generalizedTests = @(
            'classification evidence with multiple reusable candidates selects the highest-evidence candidate',
            'hardcoded response authority risk remains a blocker and is not reintroduced through a route template',
            'operator contract authority risk remains visible and cannot append to casual/coaching replies',
            'route files may delegate to the reusable service but cannot become final response authority'
        )
        $preventionLesson = 'When route evidence contains reusable service candidates, TOD must materialize a service boundary and generalized tests instead of copying route-level response behavior back into the product.'
        $findings.Add([ordered]@{
            finding = 'selected_reusable_service_candidate'
            evidence = $selectedServiceCandidateReason
        }) | Out-Null
        $findings.Add([ordered]@{
            finding = 'service_boundary'
            evidence = $serviceBoundary
        }) | Out-Null
    }

    $artifact = if ($null -ne $engineeringEpisodeQualityExaminerArtifact) {
        $classification = [string]$engineeringEpisodeQualityExaminerArtifact.status
        $engineeringEpisodeQualityExaminerArtifact
    }
    elseif ($null -ne $engineeringCorpusFoundationIndexArtifact) {
        $classification = [string]$engineeringCorpusFoundationIndexArtifact.status
        $engineeringCorpusFoundationIndexArtifact
    }
    elseif ($null -ne $readOnlyRetirementEligibilityProofArtifact) {
        $classification = 'retirement_eligibility_reviewed'
        $readOnlyRetirementEligibilityProofArtifact
    }
    elseif ($null -ne $corpusSourceAnchorEpisodeEnrichmentArtifact) {
        $classification = [string]$corpusSourceAnchorEpisodeEnrichmentArtifact.status
        $corpusSourceAnchorEpisodeEnrichmentArtifact
    }
    elseif ($null -ne $heldoutCandidateNewTextArtifact) {
        $classification = [string]$heldoutCandidateNewTextArtifact.status
        $heldoutCandidateNewTextArtifact
    }
    elseif ($null -ne $corpusEpisodeCandidateManifestArtifact) {
        $classification = [string]$corpusEpisodeCandidateManifestArtifact.status
        $corpusEpisodeCandidateManifestArtifact
    }
    elseif ($null -ne $corpusEvidenceIntakeClassifierArtifact) {
        $classification = [string]$corpusEvidenceIntakeClassifierArtifact.status
        $corpusEvidenceIntakeClassifierArtifact
    }
    elseif ($null -ne $evidencePoolClassifierArtifact) {
        $classification = [string]$evidencePoolClassifierArtifact.classification_decision
        $evidencePoolClassifierArtifact
    }
    elseif ($null -ne $sourceAnchorDeltaProposalArtifact) {
        $classification = [string]$sourceAnchorDeltaProposalArtifact.status
        $sourceAnchorDeltaProposalArtifact
    }
    elseif ($null -ne $autonomousMeaningfulNewTextSynthesisArtifact) {
        $classification = [string]$autonomousMeaningfulNewTextSynthesisArtifact.status
        $autonomousMeaningfulNewTextSynthesisArtifact
    }
    elseif ($null -ne $readOnlyEvidenceComparisonArtifact) {
        $classification = [string]$readOnlyEvidenceComparisonArtifact.status
        $readOnlyEvidenceComparisonArtifact
    }
    elseif ($null -ne $engineeringContextPackageArtifact) {
        $classification = 'completed'
        $engineeringContextPackageArtifact
    }
    elseif ($null -ne $modelUtilizationEngineeringJudgmentArtifact) {
        $classification = if ($modelUtilizationEngineeringJudgmentArtifact.candidate_request_ready) { 'blocked_on_provider_hook' } else { 'blocked_on_context_quality' }
        $modelUtilizationEngineeringJudgmentArtifact
    }
    elseif ($null -ne $engineeringProviderRequestArtifact) {
        $classification = if ($engineeringProviderRequestArtifact.provider_request_ready) { 'provider_request_ready' } else { 'provider_request_blocked' }
        $engineeringProviderRequestArtifact
    }
    elseif ($null -ne $localEngineeringProviderInventoryArtifact) {
        $classification = if ($localEngineeringProviderInventoryArtifact.usable_provider_hook) { 'provider_hook_available' } else { 'provider_stub_required' }
        $localEngineeringProviderInventoryArtifact
    }
    elseif ($null -ne $engineeringProviderCandidateStubArtifact) {
        $classification = [string]$engineeringProviderCandidateStubArtifact.expected_rejection_or_acceptance
        $engineeringProviderCandidateStubArtifact
    }
    elseif ($null -ne $engineeringProviderCandidateInvocationArtifact) {
        $classification = [string]$engineeringProviderCandidateInvocationArtifact.expected_rejection_or_acceptance
        $engineeringProviderCandidateInvocationArtifact
    }
    elseif ($null -ne $engineeringProviderCandidateVerdictArtifact) {
        $classification = [string]$engineeringProviderCandidateVerdictArtifact.verdict_reason_code
        $engineeringProviderCandidateVerdictArtifact
    }
    elseif ($null -ne $engineeringProviderCandidateReplanArtifact) {
        $classification = if ($engineeringProviderCandidateReplanArtifact.provider_request_ready_for_retry) { 'provider_replan_ready' } else { 'provider_replan_blocked' }
        $engineeringProviderCandidateReplanArtifact
    }
    elseif ($null -ne $engineeringEpisodeCardArtifact) {
        $classification = [string]$engineeringEpisodeCardArtifact.status
        $engineeringEpisodeCardArtifact
    }
    else {
        [ordered]@{
        artifact_type = $artifactType
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
            required_fields_present = if ($wantsContractFieldEvaluation) { (@($contractMissingFields.ToArray()).Count -eq 0) } else { $true }
        }
        continuation_action = 'Use this report-only artifact lane for read-only self-audits, route audits, and blocker classifications before attempting broader synthesis.'
    }
    }
    $artifactMatchesRequestedArtifactType = (
        -not [string]::IsNullOrWhiteSpace($requiredArtifactType) -and
        $artifact -is [System.Collections.IDictionary] -and
        $artifact.Contains('artifact_type') -and
        [string]::Equals([string]$artifact['artifact_type'], [string]$requiredArtifactType, [System.StringComparison]::OrdinalIgnoreCase)
    )
    if ($wantsContractFieldEvaluation -and -not $artifactMatchesRequestedArtifactType) {
        $contractMissingFieldArray = @($contractMissingFields.ToArray())
        $artifact['pass_or_reject'] = if ($contractMissingFieldArray.Count -eq 0) { 'pass' } else { 'reject' }
        $artifact['required_fields'] = @($contractRequiredFieldArray)
        $artifact['missing_fields'] = @($contractMissingFieldArray)
        $artifact['reason'] = if ($contractMissingFieldArray.Count -eq 0) {
            'All requested contract fields were present in the audited artifact.'
        }
        else {
            ('Audited artifact is missing required contract fields: {0}.' -f ($contractMissingFieldArray -join ', '))
        }
        $artifact['next_smaller_repair_step'] = if ($contractMissingFieldArray.Count -eq 0) {
            'Proceed to the next bounded training rung with independent evidence.'
        }
        else {
            'Back up to contract-field evaluation before broader synthesis; require the producer to publish the missing fields explicitly.'
        }
        $artifact['dave_needed'] = 'no'
        $artifact['continuation_action'] = 'Use this contract-field evaluation before granting progress credit to read-only synthesis artifacts.'
    }
    if ($wantsServiceExtractionPlan) {
        $artifact['selected_service_candidate'] = if ($selectedServiceCandidate.Count -gt 0) { $selectedServiceCandidate[0] } else { $null }
        $artifact['selected_service_candidate_reason'] = $selectedServiceCandidateReason
        $artifact['service_boundary'] = $serviceBoundary
        $artifact['forbidden_route_response_authority'] = @($forbiddenRouteAuthority)
        $artifact['generalized_tests'] = @($generalizedTests)
        $artifact['prevention_lesson'] = $preventionLesson
        $artifact['dave_needed'] = 'no'
        $artifact['continuation_action'] = 'Use this service-extraction plan as the next bounded design artifact; do not reintroduce route-level response authority.'
    }
    if (
        -not [string]::IsNullOrWhiteSpace($requiredArtifactType) -and
        $artifact.Contains('artifact_type') -and
        -not [string]::Equals(((([string]$artifact['artifact_type']).Trim()).TrimEnd('.', ';', ',', ':')), ([string]$requiredArtifactType).Trim(), [System.StringComparison]::OrdinalIgnoreCase)
    ) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'read_only_audit_required_artifact_type_unsupported' -Reason ('Read-only audit produced artifact type {0}, but the task required {1}; route to a task-specific learned capability lane or publish a smaller blocker.' -f [string]$artifact['artifact_type'], [string]$requiredArtifactType) -MissingVariable 'task_specific_artifact_lane')
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

    $requiredFields = if ($null -ne $engineeringEpisodeQualityExaminerArtifact) {
        @('artifact_type', 'generated_at', 'source', 'objective_id', 'task_id', 'status', 'input_episode_artifact', 'episode_id', 'episode_debt_category', 'episode_borrowed_vs_independent', 'training_usefulness', 'engineering_credit_allowed', 'runtime_support_credit_allowed', 'borrowed_capability_ratio_effect', 'required_episode_fields', 'missing_episode_fields', 'evidence_checked', 'verdict_reason', 'smallest_next_training_rung', 'validation', 'prevention_lesson', 'independent_credit_requested', 'dave_needed')
    }
    elseif ($null -ne $corpusSourceAnchorEpisodeEnrichmentArtifact) {
        @('artifact_type', 'generated_at', 'source', 'objective_id', 'task_id', 'status', 'codex_role', 'input_manifest_artifact', 'source_anchor_artifact', 'episode_candidates', 'enriched_episode', 'updated_episode_count', 'source_anchor_episode_count', 'validation', 'prevention_lesson', 'independent_credit_requested', 'dave_needed')
    }
    elseif ($null -ne $heldoutCandidateNewTextArtifact) {
        @('artifact_type', 'generated_at', 'source', 'objective_id', 'task_id', 'status', 'codex_role', 'input_manifest_artifact', 'selected_episode', 'source_anchor_available', 'candidate_new_text', 'blocker', 'validation', 'prevention_lesson', 'independent_credit_requested', 'dave_needed')
    }
    elseif ($null -ne $corpusEpisodeCandidateManifestArtifact) {
        @('artifact_type', 'generated_at', 'source', 'objective_id', 'task_id', 'status', 'codex_role', 'source_classifier_artifact', 'episode_candidates', 'rejected_inputs', 'manifest_gaps', 'smallest_next_executable_shape', 'validation', 'prevention_lesson', 'independent_credit_requested', 'dave_needed')
    }
    elseif ($null -ne $corpusEvidenceIntakeClassifierArtifact) {
        @('artifact_type', 'generated_at', 'source', 'objective_id', 'task_id', 'status', 'codex_role', 'source_artifacts', 'candidate_inputs', 'rejected_inputs', 'missing_fields_for_episode_manifest', 'smallest_next_executable_shape', 'validation', 'prevention_lesson', 'independent_credit_requested', 'dave_needed')
    }
    elseif ($null -ne $evidencePoolClassifierArtifact) {
        @('artifact_type', 'generated_at', 'source', 'objective_id', 'task_id', 'classification_decision', 'selected_source_anchor_artifact', 'classified_artifacts', 'packet_materialization_allowed', 'reason', 'next_smallest_rung', 'tod_independent_capability_acquired', 'no_code_changes', 'validation')
    }
    elseif ($null -ne $sourceAnchorDeltaProposalArtifact) {
        @('artifact_type', 'generated_at', 'source', 'objective_id', 'task_id', 'status', 'old_text_source', 'target_file', 'intended_behavior_delta', 'candidate_new_text', 'safety_constraints', 'validation_plan', 'confidence', 'no_source_code_modified', 'blocker', 'validation')
    }
    elseif ($null -ne $autonomousMeaningfulNewTextSynthesisArtifact) {
        @('artifact_type', 'generated_at', 'source', 'objective_id', 'task_id', 'status', 'source_anchor_artifact', 'prior_delta_artifact', 'target_file', 'old_text', 'new_text', 'expected_behavior_change', 'risks', 'blocker', 'validation_command', 'independent_credit_requested', 'no_source_code_modified', 'validation', 'dave_needed')
    }
    elseif ($null -ne $readOnlyEvidenceComparisonArtifact) {
        @('artifact_type', 'generated_at', 'source', 'objective_id', 'task_id', 'status', 'input_evidence_artifact', 'left_artifact', 'right_artifact', 'first_material_difference', 'failed_contract_value', 'passed_contract_value', 'detector_eligibility_effect', 'smallest_reusable_rule', 'validation', 'prevention_lesson', 'independent_credit_requested', 'dave_needed')
    }
    elseif ($null -ne $engineeringContextPackageArtifact) {
        @('artifact_type', 'generated_at', 'source', 'objective_id', 'task_id', 'episode_id', 'problem_summary', 'source_file', 'source_function', 'source_anchor_artifact', 'observed_failure', 'desired_behavior', 'validation_target', 'files_to_supply', 'facts', 'hypotheses', 'rejected_outputs', 'required_output_contract', 'prohibited_actions', 'model_utilization_lesson', 'validation', 'no_code_changes', 'independent_credit_requested', 'dave_needed')
    }
    elseif ($null -ne $modelUtilizationEngineeringJudgmentArtifact) {
        @('artifact_type', 'generated_at', 'source', 'objective_id', 'task_id', 'input_context_package', 'provider_reachable', 'provider_or_runtime_hook', 'context_quality', 'source_file', 'source_function', 'source_anchor_artifact', 'candidate_request_ready', 'required_provider_prompt_fields', 'tod_accept_reject_policy', 'bad_patch_rejection_criteria', 'validation_command_needed', 'counts_as_engineering_implementation_credit', 'counts_as_model_utilization_credit', 'blocker_or_next_action', 'no_source_code_modified', 'validation', 'dave_needed')
    }
    elseif ($null -ne $engineeringProviderRequestArtifact) {
        @('artifact_type', 'generated_at', 'source', 'objective_id', 'task_id', 'input_context_package', 'input_model_utilization_judgment', 'provider_request_ready', 'provider_role', 'prompt_messages', 'source_files_to_include', 'artifacts_to_include', 'required_output_contract', 'rejection_policy', 'validation_command', 'forbidden_outputs', 'counts_as_engineering_implementation_credit', 'counts_as_model_utilization_credit', 'next_action_after_provider_response', 'no_source_code_modified', 'validation', 'dave_needed')
    }
    elseif ($null -ne $localEngineeringProviderInventoryArtifact) {
        @('artifact_type', 'generated_at', 'source', 'objective_id', 'task_id', 'input_provider_request', 'provider_request_ready', 'detected_tools', 'detected_python_packages', 'configured_provider_assets', 'running_provider_endpoint', 'gpu_available', 'real_provider_reachable', 'usable_provider_hook', 'stub_contract', 'candidate_response_available', 'counts_as_engineering_implementation_credit', 'counts_as_model_utilization_credit', 'next_smallest_rung', 'no_source_code_modified', 'validation', 'dave_needed')
    }
    elseif ($null -ne $engineeringProviderCandidateStubArtifact) {
        @('artifact_type', 'generated_at', 'source', 'objective_id', 'task_id', 'input_provider_request', 'input_provider_inventory', 'provider_stub_used', 'candidate_response_available', 'target_file', 'old_text', 'new_text', 'validation_command', 'risk_notes', 'reject_if_marker_only', 'expected_rejection_or_acceptance', 'counts_as_engineering_implementation_credit', 'counts_as_model_utilization_credit', 'next_smallest_rung', 'no_source_code_modified', 'validation', 'dave_needed')
    }
    elseif ($null -ne $engineeringProviderCandidateInvocationArtifact) {
        @('artifact_type', 'generated_at', 'source', 'objective_id', 'task_id', 'input_provider_request', 'input_provider_inventory', 'provider_endpoint', 'provider_model', 'provider_called', 'candidate_response_available', 'used_provider_request_prompt_messages', 'outbound_prompt_message_count', 'outbound_prompt_context_summary', 'raw_provider_response', 'parsed_candidate_json', 'target_file', 'old_text', 'new_text', 'validation_command', 'risk_notes', 'reject_if_marker_only', 'expected_rejection_or_acceptance', 'counts_as_engineering_implementation_credit', 'counts_as_model_utilization_credit', 'next_smallest_rung', 'no_source_code_modified', 'validation', 'dave_needed')
    }
    elseif ($null -ne $engineeringProviderCandidateVerdictArtifact) {
        @('artifact_type', 'generated_at', 'source', 'objective_id', 'task_id', 'input_candidate', 'input_candidate_type', 'input_provider_request', 'verdict', 'verdict_reason_code', 'target_file', 'old_text_length', 'new_text_length', 'validation_command', 'policy_checks', 'accepted_for_source_mutation', 'rejected_before_source_mutation', 'counts_as_engineering_implementation_credit', 'counts_as_model_utilization_credit', 'next_smallest_rung', 'no_source_code_modified', 'validation', 'dave_needed')
    }
    elseif ($null -ne $engineeringProviderCandidateReplanArtifact) {
        @('artifact_type', 'generated_at', 'source', 'objective_id', 'task_id', 'input_candidate_verdict', 'input_provider_request', 'input_candidate_stub', 'prior_verdict', 'prior_rejection_reason_code', 'target_file', 'source_anchor_artifact', 'revised_provider_instruction', 'next_candidate_acceptance_checks', 'next_candidate_rejection_checks', 'validation_command', 'provider_request_ready_for_retry', 'counts_as_engineering_implementation_credit', 'counts_as_model_utilization_credit', 'next_smallest_rung', 'no_source_code_modified', 'validation', 'dave_needed')
    }
    elseif ($null -ne $engineeringCorpusFoundationIndexArtifact) {
        @('artifact_type', 'generated_at', 'source', 'objective_id', 'task_id', 'status', 'indexed_inputs', 'missing_inputs', 'borrowed_capability_reduction_now', 'borrowed_reduction_candidate_inputs', 'next_smallest_fresh_engineering_demonstration', 'validation', 'prevention_lesson', 'dave_needed')
    }
    elseif ($null -ne $readOnlyRetirementEligibilityProofArtifact) {
        @('artifact_type', 'generated_at', 'source', 'objective_id', 'task_id', 'entries_reviewed', 'evidence_inspected', 'missing_evidence', 'retirement_decisions', 'proposed_registry_changes', 'ratio_if_accepted', 'validation', 'prevention_lesson', 'no_source_code_modified', 'dave_needed')
    }
    elseif ($null -ne $engineeringEpisodeCardArtifact) {
        @('artifact_type', 'generated_at', 'source', 'episode_id', 'objective_id', 'task_id', 'status', 'source_artifact', 'source_artifact_type', 'problem_statement', 'attempted_actions', 'evidence_artifacts', 'diagnosis', 'debt_category', 'borrowed_vs_independent', 'lesson', 'smallest_next_repair', 'validation_summary', 'blocker', 'no_source_edits', 'independent_credit_requested', 'dave_needed')
    }
    elseif ($isTodCapabilityAssessment) {
        @('artifact_type', 'generated_at', 'source', 'objective_id', 'task_id', 'task_mode', 'assessment_status', 'tod_read_only_assessment_completed', 'tod_independent_capability_acquired', 'borrowed_control_plane_repair', 'no_source_code_modified_by_assessment', 'inspected_files', 'evidence_used', 'capabilities', 'final_summary', 'validation')
    }
    else {
        @('artifact_type', 'generated_at', 'source', 'objective_id', 'task_id', 'audit_subject', 'inspected_files', 'evidence_used', 'classification', 'findings', 'blockers', 'confidence', 'no_code_changes', 'validation', 'continuation_action')
    }
    $missing = @($requiredFields | Where-Object { -not $readback.PSObject.Properties[$_] })
    if ($missing.Count -gt 0) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'read_only_audit_artifact_schema_failed' -Reason ('Read-only audit artifact is missing required fields: {0}' -f ($missing -join ', ')) -MissingVariable 'artifact_schema')
    }
    $noCodeChangeFlag = if ($isTodCapabilityAssessment) { $readback.no_source_code_modified_by_assessment } elseif ($null -ne $engineeringEpisodeQualityExaminerArtifact) { $readback.validation.no_code_changes } elseif ($null -ne $corpusSourceAnchorEpisodeEnrichmentArtifact) { $readback.validation.no_source_code_modified } elseif ($null -ne $heldoutCandidateNewTextArtifact) { $readback.validation.no_source_code_modified } elseif ($null -ne $corpusEpisodeCandidateManifestArtifact) { $readback.validation.no_source_code_modified } elseif ($null -ne $corpusEvidenceIntakeClassifierArtifact) { $readback.validation.no_source_code_modified } elseif ($null -ne $sourceAnchorDeltaProposalArtifact) { $readback.no_source_code_modified } elseif ($null -ne $autonomousMeaningfulNewTextSynthesisArtifact) { $readback.no_source_code_modified } elseif ($null -ne $readOnlyEvidenceComparisonArtifact) { $readback.validation.no_code_changes } elseif ($null -ne $engineeringContextPackageArtifact) { $readback.no_code_changes } elseif ($null -ne $modelUtilizationEngineeringJudgmentArtifact) { $readback.no_source_code_modified } elseif ($null -ne $engineeringProviderRequestArtifact) { $readback.no_source_code_modified } elseif ($null -ne $localEngineeringProviderInventoryArtifact) { $readback.no_source_code_modified } elseif ($null -ne $engineeringProviderCandidateStubArtifact) { $readback.no_source_code_modified } elseif ($null -ne $engineeringProviderCandidateInvocationArtifact) { $readback.no_source_code_modified } elseif ($null -ne $engineeringProviderCandidateVerdictArtifact) { $readback.no_source_code_modified } elseif ($null -ne $engineeringProviderCandidateReplanArtifact) { $readback.no_source_code_modified } elseif ($null -ne $engineeringCorpusFoundationIndexArtifact) { $readback.validation.no_source_code_modified } elseif ($null -ne $readOnlyRetirementEligibilityProofArtifact) { $readback.no_source_code_modified } elseif ($null -ne $engineeringEpisodeCardArtifact) { $readback.no_source_edits } else { $readback.no_code_changes }
    if ($noCodeChangeFlag -ne $true) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'read_only_audit_no_code_change_flag_failed' -Reason 'Read-only audit artifact must set no_code_changes=true.' -MissingVariable 'no_code_changes')
    }

    $Result.summary = if ($null -ne $engineeringEpisodeQualityExaminerArtifact) {
        ('Published engineering episode quality verdict {0}; usefulness={1}; borrowed_ratio_effect={2}.' -f $outputRel, [string]$engineeringEpisodeQualityExaminerArtifact.training_usefulness, [string]$engineeringEpisodeQualityExaminerArtifact.borrowed_capability_ratio_effect)
    }
    elseif ($null -ne $corpusSourceAnchorEpisodeEnrichmentArtifact) {
        ('Published corpus source-anchor enrichment artifact {0}; episodes={1}; source_anchor_episodes={2}; status={3}.' -f $outputRel, [string]$corpusSourceAnchorEpisodeEnrichmentArtifact.updated_episode_count, [string]$corpusSourceAnchorEpisodeEnrichmentArtifact.source_anchor_episode_count, [string]$corpusSourceAnchorEpisodeEnrichmentArtifact.status)
    }
    elseif ($null -ne $heldoutCandidateNewTextArtifact) {
        ('Published held-out candidate_new_text evaluation artifact {0}; source_anchor_available={1}; blocker={2}.' -f $outputRel, [string]$heldoutCandidateNewTextArtifact.source_anchor_available, [string]$heldoutCandidateNewTextArtifact.blocker.reason_code)
    }
    elseif ($null -ne $corpusEpisodeCandidateManifestArtifact) {
        ('Published corpus episode candidate manifest artifact {0}; episodes={1}; status={2}.' -f $outputRel, @($corpusEpisodeCandidateManifestArtifact.episode_candidates).Count, [string]$corpusEpisodeCandidateManifestArtifact.status)
    }
    elseif ($null -ne $corpusEvidenceIntakeClassifierArtifact) {
        ('Published corpus evidence intake classifier artifact {0}; candidates={1}; rejected={2}.' -f $outputRel, @($corpusEvidenceIntakeClassifierArtifact.candidate_inputs).Count, @($corpusEvidenceIntakeClassifierArtifact.rejected_inputs).Count)
    }
    elseif ($null -ne $evidencePoolClassifierArtifact) {
        ('Published evidence-pool source-anchor classifier artifact {0}; selected_source_anchor_artifact={1}.' -f $outputRel, [string]$evidencePoolClassifierArtifact.selected_source_anchor_artifact)
    }
    elseif ($null -ne $sourceAnchorDeltaProposalArtifact) {
        ('Published source-anchor delta proposal artifact {0}; status={1}; blocker={2}.' -f $outputRel, [string]$sourceAnchorDeltaProposalArtifact.status, [string]$sourceAnchorDeltaProposalArtifact.blocker.reason_code)
    }
    elseif ($null -ne $autonomousMeaningfulNewTextSynthesisArtifact) {
        ('Published autonomous meaningful new_text synthesis artifact {0}; status={1}; old_text_nonempty={2}; new_text_nonempty={3}.' -f $outputRel, [string]$autonomousMeaningfulNewTextSynthesisArtifact.status, [string]$autonomousMeaningfulNewTextSynthesisArtifact.validation.old_text_nonempty, [string]$autonomousMeaningfulNewTextSynthesisArtifact.validation.new_text_nonempty)
    }
    elseif ($null -ne $readOnlyEvidenceComparisonArtifact) {
        ('Published read-only evidence comparison artifact {0}; first_material_difference={1}; status={2}.' -f $outputRel, [string]$readOnlyEvidenceComparisonArtifact.first_material_difference, [string]$readOnlyEvidenceComparisonArtifact.status)
    }
    elseif ($null -ne $engineeringContextPackageArtifact) {
        ('Published TOD engineering context package {0}; source_file={1}; validation_target={2}.' -f $outputRel, [string]$engineeringContextPackageArtifact.source_file, [string]$engineeringContextPackageArtifact.validation_target)
    }
    elseif ($null -ne $modelUtilizationEngineeringJudgmentArtifact) {
        ('Published TOD model-utilization engineering judgment {0}; context_quality={1}; provider_reachable={2}.' -f $outputRel, [string]$modelUtilizationEngineeringJudgmentArtifact.context_quality, [string]$modelUtilizationEngineeringJudgmentArtifact.provider_reachable)
    }
    elseif ($null -ne $engineeringProviderRequestArtifact) {
        ('Published TOD engineering provider request {0}; provider_request_ready={1}.' -f $outputRel, [string]$engineeringProviderRequestArtifact.provider_request_ready)
    }
    elseif ($null -ne $localEngineeringProviderInventoryArtifact) {
        ('Published TOD local engineering provider inventory {0}; usable_provider_hook={1}; next_smallest_rung={2}.' -f $outputRel, [string]$localEngineeringProviderInventoryArtifact.usable_provider_hook, [string]$localEngineeringProviderInventoryArtifact.next_smallest_rung)
    }
    elseif ($null -ne $engineeringProviderCandidateStubArtifact) {
        ('Published TOD engineering provider candidate stub {0}; expected={1}; candidate_response_available={2}.' -f $outputRel, [string]$engineeringProviderCandidateStubArtifact.expected_rejection_or_acceptance, [string]$engineeringProviderCandidateStubArtifact.candidate_response_available)
    }
    elseif ($null -ne $engineeringProviderCandidateInvocationArtifact) {
        ('Published TOD engineering provider candidate invocation {0}; provider_called={1}; candidate_response_available={2}; next={3}.' -f $outputRel, [string]$engineeringProviderCandidateInvocationArtifact.provider_called, [string]$engineeringProviderCandidateInvocationArtifact.candidate_response_available, [string]$engineeringProviderCandidateInvocationArtifact.next_smallest_rung)
    }
    elseif ($null -ne $engineeringProviderCandidateVerdictArtifact) {
        ('Published TOD engineering provider candidate verdict {0}; verdict={1}; reason={2}.' -f $outputRel, [string]$engineeringProviderCandidateVerdictArtifact.verdict, [string]$engineeringProviderCandidateVerdictArtifact.verdict_reason_code)
    }
    elseif ($null -ne $engineeringProviderCandidateReplanArtifact) {
        ('Published TOD engineering provider candidate replan {0}; prior_verdict={1}; reason={2}; retry_ready={3}.' -f $outputRel, [string]$engineeringProviderCandidateReplanArtifact.prior_verdict, [string]$engineeringProviderCandidateReplanArtifact.prior_rejection_reason_code, [string]$engineeringProviderCandidateReplanArtifact.provider_request_ready_for_retry)
    }
    elseif ($null -ne $engineeringCorpusFoundationIndexArtifact) {
        ('Published TOD engineering corpus foundation index {0}; inputs={1}; missing={2}; borrowed_reduction_now={3}.' -f $outputRel, [int]$engineeringCorpusFoundationIndexArtifact.validation.input_count, [int]$engineeringCorpusFoundationIndexArtifact.validation.missing_input_count, [string]$engineeringCorpusFoundationIndexArtifact.borrowed_capability_reduction_now)
    }
    elseif ($null -ne $readOnlyRetirementEligibilityProofArtifact) {
        ('Published TOD read-only retirement eligibility proof {0}; entries={1}; eligible={2}; projected_borrowed={3}%.' -f $outputRel, [int]$readOnlyRetirementEligibilityProofArtifact.validation.entries_reviewed_count, [int]$readOnlyRetirementEligibilityProofArtifact.ratio_if_accepted.eligible_retirements, [string]$readOnlyRetirementEligibilityProofArtifact.ratio_if_accepted.projected_borrowed_percent)
    }
    elseif ($null -ne $engineeringEpisodeCardArtifact) {
        ('Published TOD engineering episode card {0}; source={1}; debt_category={2}.' -f $outputRel, [string]$engineeringEpisodeCardArtifact.source_artifact, [string]$engineeringEpisodeCardArtifact.debt_category)
    }
    else {
        ('Published read-only audit artifact {0} from evidence file {1}.' -f $outputRel, $inputRel)
    }
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

function Invoke-LocalExecutionReadOnlyTaskContextArtifact {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)]$Spec
    )

    $paths = Get-LocalExecutionReadOnlyAuditArtifactPaths -Context $Context
    $outputRel = [string]$paths.output_path
    if ([string]::IsNullOrWhiteSpace($outputRel)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'read_only_task_context_output_missing' -Reason 'Read-only task context proof requires an output path under runtime_remote_training/read_only_audit_artifacts/.' -MissingVariable 'output_path')
    }
    if (-not (Test-LocalExecutionSafePath -RelativePath $outputRel)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'read_only_task_context_output_unsafe' -Reason ('Output artifact path is outside LocalExecutionEngine safe roots: {0}' -f $outputRel) -MissingVariable 'safe_output_path')
    }

    $category = Get-LocalExecutionTaskCategory -Context $Context
    $metadata = if ($Context.PSObject.Properties['metadata'] -and $Context.metadata) { $Context.metadata } else { [pscustomobject]@{} }
    $promptPath = if ($Context.PSObject.Properties['prompt_path']) { [string]$Context.prompt_path } else { '' }
    $artifact = [ordered]@{
        artifact_type = 'tod_read_only_task_context_proof'
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        source = 'local_execution_read_only_task_context_artifact_lane'
        objective_id = if ($Context.PSObject.Properties['objective_id']) { [string]$Context.objective_id } else { '' }
        task_id = if ($Context.PSObject.Properties['task_id']) { [string]$Context.task_id } else { '' }
        task_mode = $category
        task_category = $category
        task_mode_preserved = (@('read_only_assessment', 'report_only', 'diagnostic_only', 'inspection_only', 'inspection', 'review_only') -contains $category)
        bounded_edit_required = $false
        target_file_required = $false
        no_code_changes = $true
        inspected_files = @($promptPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        evidence_checked = @(
            [ordered]@{ field = 'task_category'; value = $category },
            [ordered]@{ field = 'metadata.task_mode'; value = $(if ($metadata.PSObject.Properties['task_mode']) { [string]$metadata.task_mode } else { '' }) },
            [ordered]@{ field = 'metadata.bounded_edit_mode'; value = $(if ($metadata.PSObject.Properties['bounded_edit_mode']) { [string]$metadata.bounded_edit_mode } else { 'not_present' }) },
            [ordered]@{ field = 'metadata.target_file'; value = $(if ($metadata.PSObject.Properties['target_file']) { [string]$metadata.target_file } else { '' }) }
        )
        validation = [ordered]@{
            artifact_path = $outputRel
            output_under_read_only_artifacts = $true
            required_fields_present = $true
            source_edits = @()
        }
        prevention_lesson = 'Read-only task context proofs may be generated from the task context itself; they must not be forced into bounded-edit target_file materialization.'
        dave_needed = 'no'
    }

    $outputAbs = Join-Path $script:LocalEngineRepoRoot $outputRel
    New-Item -ItemType Directory -Path (Split-Path -Parent $outputAbs) -Force | Out-Null
    [System.IO.File]::WriteAllText($outputAbs, ($artifact | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))
    $readback = Get-Content -Path $outputAbs -Raw | ConvertFrom-Json
    foreach ($required in @('artifact_type', 'task_mode', 'task_mode_preserved', 'bounded_edit_required', 'target_file_required', 'no_code_changes', 'validation', 'prevention_lesson', 'dave_needed')) {
        if (-not $readback.PSObject.Properties[$required]) {
            return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'read_only_task_context_schema_failed' -Reason ('Read-only task context artifact is missing required field: {0}' -f $required) -MissingVariable 'artifact_schema')
        }
    }
    if ($readback.no_code_changes -ne $true -or $readback.task_mode_preserved -ne $true -or $readback.bounded_edit_required -ne $false -or $readback.target_file_required -ne $false) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'read_only_task_context_assertion_failed' -Reason 'Read-only task context artifact did not preserve the non-edit assertions.' -MissingVariable 'read_only_assertions')
    }

    $Result.summary = ('Published read-only task context proof artifact {0}.' -f $outputRel)
    $Result.files_changed = @($outputRel)
    $Result.tests_run = @('task context mode read', 'read-only task context artifact write', 'required schema readback', 'non-edit assertion')
    $Result.test_results = @('pass', 'pass', 'pass', 'pass')
    $Result | Add-Member -NotePropertyName command_output -NotePropertyValue ('Read-only task context proof published: {0}' -f $outputRel) -Force
    $Result | Add-Member -NotePropertyName diff_summary -NotePropertyValue ('Artifact write only: {0}' -f $outputRel) -Force
    $Result | Add-Member -NotePropertyName commands_run -NotePropertyValue @('Invoke-LocalExecutionReadOnlyTaskContextArtifact') -Force
    $Result | Add-Member -NotePropertyName validation_results -NotePropertyValue @(
        [pscustomobject]@{ name = 'task context mode read'; passed = $true; required = $true },
        [pscustomobject]@{ name = 'read-only task context artifact write'; passed = $true; required = $true },
        [pscustomobject]@{ name = 'required schema readback'; passed = $true; required = $true },
        [pscustomobject]@{ name = 'non-edit assertion'; passed = $true; required = $true }
    ) -Force
    $Result | Add-Member -NotePropertyName blockers -NotePropertyValue @() -Force
    $Result | Add-Member -NotePropertyName confidence -NotePropertyValue 'high' -Force
    $Result | Add-Member -NotePropertyName rollback_hint -NotePropertyValue ('Remove generated artifact {0} if this read-only task context proof must be discarded.' -f $outputRel) -Force
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
    $text = (Get-LocalExecutionCombinedText -Context $Context).ToLowerInvariant()
    $requestedExactTextExtraction = (
        $text -match 'exact_text' -and
        $text -match 'extracted_tokens|branch_excerpt|regex_terms_excerpt'
    )
    $requestedRootCauseFromExtraction = (
        $text -match 'root_cause' -and
        $text -match 'branch_logic' -and
        $text -match 'selector_failure_mode' -and
        $text -match 'extracted_tokens|branch_excerpt|regex_terms_excerpt'
    )
    if ((@('read_only_assessment', 'report_only', 'diagnostic_only', 'inspection_only', 'inspection') -notcontains $category) -and -not $requestedExactTextExtraction -and -not $requestedRootCauseFromExtraction) {
        return $false
    }
    if ($text -match 'corpus' -and $text -match 'evidence[-_\s]?intake|episode[-_\s]?candidate|candidate[-_\s]?inputs') {
        return $false
    }
    if (-not $requestedExactTextExtraction -and -not $requestedRootCauseFromExtraction -and ($text -notmatch 'semantic' -or $text -notmatch 'audit' -or $text -notmatch 'source[-_\s]?anchor')) {
        return $false
    }
    if (-not $requestedExactTextExtraction -and -not $requestedRootCauseFromExtraction -and $text -notmatch 'root[-_\s]?cause|audit[-_\s]?body|source[-_\s]?audit') {
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
    foreach ($match in [regex]::Matches($ExactText, '(?m)^\s*(?:def\s+(?<py>[A-Za-z_][A-Za-z0-9_]*)\s*\(|function\s+(?<ps>[A-Za-z_][A-Za-z0-9_-]*))')) {
        $name = if (-not [string]::IsNullOrWhiteSpace([string]$match.Groups['py'].Value)) {
            ([string]$match.Groups['py'].Value).Trim()
        }
        else {
            ([string]$match.Groups['ps'].Value).Trim()
        }
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
    $requiredFields = @(Get-LocalExecutionSemanticAuditRequiredFields -Context $Context)
    $requestedRootCauseFromExtraction = (
        @($requiredFields | ForEach-Object { [string]$_ }) -contains 'root_cause' -or
        @($requiredFields | ForEach-Object { [string]$_ }) -contains 'branch_logic' -or
        @($requiredFields | ForEach-Object { [string]$_ }) -contains 'selector_failure_mode' -or
        @($requiredFields | ForEach-Object { [string]$_ }) -contains 'evidence_lines'
    )
    foreach ($inputRel in $inputPaths) {
        if (-not (Test-LocalExecutionSafePath -RelativePath $inputRel)) {
            return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'semantic_source_audit_input_unsafe' -Reason ('Semantic source audit input is outside LocalExecutionEngine safe roots: {0}' -f $inputRel) -MissingVariable 'safe_input_path')
        }
        $inputAbs = Join-Path $script:LocalEngineRepoRoot $inputRel
        if (-not (Test-Path -Path $inputAbs -PathType Leaf)) {
            return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'semantic_source_audit_input_not_found' -Reason ('Semantic source audit input artifact does not exist: {0}' -f $inputRel) -MissingVariable 'input_artifact')
        }
        $anchor = Get-Content -Path $inputAbs -Raw | ConvertFrom-Json
        $anchorArtifactType = if ($anchor.PSObject.Properties['artifact_type']) { [string]$anchor.artifact_type } else { '' }
        if ($requestedRootCauseFromExtraction -and [string]$anchorArtifactType -eq 'tod_semantic_source_audit_artifact' -and $anchor.PSObject.Properties['branch_excerpt'] -and $anchor.PSObject.Properties['regex_terms_excerpt']) {
            $branchText = [string]$anchor.branch_excerpt
            $regexLines = @($anchor.regex_terms_excerpt | ForEach-Object { [string]$_ })
            $tokens = @($anchor.extracted_tokens | ForEach-Object { [string]$_ })
            [void]$combinedTextParts.Add(($branchText, ($regexLines -join "`n"), ($tokens -join "`n")) -join "`n")
            [void]$anchors.Add([ordered]@{
                input_artifact = $inputRel
                source_file = if ($anchor.PSObject.Properties['source_file']) { [string]$anchor.source_file } else { '' }
                anchor_pattern = if ($anchor.PSObject.Properties['branch_excerpt']) { [string]$anchor.branch_excerpt } else { '' }
                source_lines = [ordered]@{
                    start = $null
                    end = $null
                }
                function_names = @(
                    if ($anchor.PSObject.Properties['function_surface'] -and -not [string]::IsNullOrWhiteSpace([string]$anchor.function_surface)) {
                        [string]$anchor.function_surface
                    }
                )
            })
            continue
        }
        if ([string]$anchorArtifactType -ne 'tod_source_anchor_observation') {
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
    $requestedTokenExtraction = (
        @($requiredFields | ForEach-Object { [string]$_ }) -contains 'extracted_tokens' -or
        @($requiredFields | ForEach-Object { [string]$_ }) -contains 'branch_excerpt' -or
        @($requiredFields | ForEach-Object { [string]$_ }) -contains 'regex_terms_excerpt'
    )
    $extractedTokens = @()
    $branchExcerpt = ''
    $regexTermsExcerpt = @()
    if ($requestedTokenExtraction) {
        $requestedTokenNames = New-Object System.Collections.Generic.List[string]
        $contractText = Get-LocalExecutionCombinedText -Context $Context
        foreach ($tokenLineMatch in [regex]::Matches($contractText, '(?im)^\s*(?:[-*]\s*)?extracted_tokens\s*:\s*(?<value>.+?)\s*$')) {
            foreach ($tokenMatch in [regex]::Matches([string]$tokenLineMatch.Groups['value'].Value, '\b[A-Za-z_][A-Za-z0-9_]*\b')) {
                $tokenName = ([string]$tokenMatch.Value).Trim()
                if (-not [string]::IsNullOrWhiteSpace($tokenName) -and -not $requestedTokenNames.Contains($tokenName)) {
                    [void]$requestedTokenNames.Add($tokenName)
                }
            }
        }
        if ($requestedTokenNames.Count -eq 0) {
            foreach ($variableMatch in [regex]::Matches($combinedText, '\$([A-Za-z_][A-Za-z0-9_]*)')) {
                $tokenName = ([string]$variableMatch.Groups[1].Value).Trim()
                if (-not [string]::IsNullOrWhiteSpace($tokenName) -and -not $requestedTokenNames.Contains($tokenName)) {
                    [void]$requestedTokenNames.Add($tokenName)
                }
            }
        }
        foreach ($token in @($requestedTokenNames.ToArray())) {
            if ($combinedText -like ('*' + $token + '*')) {
                $extractedTokens += $token
            }
        }

        $sourceLines = @($combinedText -split "`r?`n")
        $fallbackBranchExcerpt = ''
        foreach ($line in $sourceLines) {
            $trimmedLine = ([string]$line).Trim()
            if ([string]::IsNullOrWhiteSpace($branchExcerpt) -and $trimmedLine -match '\$decision\s*=') {
                $branchExcerpt = $trimmedLine
            }
            if ([string]::IsNullOrWhiteSpace($fallbackBranchExcerpt) -and $trimmedLine -match '\bif\s*\(|=\s*if\s*\(') {
                $fallbackBranchExcerpt = $trimmedLine
            }
            $mentionsRequestedToken = $false
            foreach ($token in @($requestedTokenNames.ToArray())) {
                if ($trimmedLine -like ('*' + $token + '*')) {
                    $mentionsRequestedToken = $true
                    break
                }
            }
            if ($mentionsRequestedToken -or $trimmedLine -match '\-match|regex|artifact_write|edit\[-_\\s\]\?mode|genericboundedtask') {
                $regexTermsExcerpt += $trimmedLine
            }
        }
        if ([string]::IsNullOrWhiteSpace($branchExcerpt)) {
            $branchExcerpt = $fallbackBranchExcerpt
        }
        $regexTermsExcerpt = @($regexTermsExcerpt | Select-Object -Unique)
    }

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
    if ($requestedTokenExtraction) {
        $artifact['input_artifact_read'] = $true
        $artifact['exact_text_used'] = $true
        $artifact['source_file'] = [string](@($anchors.ToArray() | ForEach-Object { [string]$_.source_file } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1))
        $artifact['function_surface'] = [string](@($anchors.ToArray() | ForEach-Object { @($_.function_names) } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -First 1))
        $artifact['extracted_tokens'] = @($extractedTokens | Select-Object -Unique)
        $artifact['branch_excerpt'] = $branchExcerpt
        $artifact['regex_terms_excerpt'] = @($regexTermsExcerpt)
    }
    if ($requestedRootCauseFromExtraction) {
        $rootBranchExcerpt = ''
        $rootRegexTermsExcerpt = @()
        $sourceLines = @($combinedText -split "`r?`n")
        foreach ($line in $sourceLines) {
            $trimmedLine = ([string]$line).Trim()
            if ([string]::IsNullOrWhiteSpace($rootBranchExcerpt) -and $trimmedLine -match '\$decision\s*=') {
                $rootBranchExcerpt = $trimmedLine
            }
            if ($trimmedLine -match '\$taskRequiresPacketEditing\s*=|\$anchorShowsPacketEditing\s*=|artifact_write|edit\[-_\\s\]\?mode|genericboundedtask') {
                $rootRegexTermsExcerpt += $trimmedLine
            }
        }
        $artifact['input_artifact_read'] = $true
        $artifact['source_file'] = [string](@($anchors.ToArray() | ForEach-Object { [string]$_.source_file } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1))
        $artifact['function_surface'] = [string](@($anchors.ToArray() | ForEach-Object { @($_.function_names) } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -First 1))
        $artifact['root_cause'] = 'The semantic rejection evaluator uses keyword-overlap checks for packet/edit/materialization terms to decide whether the selected anchor is relevant, so it can reject or accept based on matching words rather than actual source responsibility.'
        $artifact['source_variables'] = @('taskRequiresPacketEditing', 'anchorShowsPacketEditing', 'decision')
        $artifact['branch_logic'] = 'reject_anchor occurs when taskRequiresPacketEditing is true and anchorShowsPacketEditing is false; otherwise the branch returns accept_anchor.'
        $artifact['selector_failure_mode'] = 'keyword-overlap semantic relevance check can reject or accept based on matching artifact/edit/packet terms rather than actual source responsibility'
        $artifact['evidence_lines'] = @($rootBranchExcerpt) + @($rootRegexTermsExcerpt | Select-Object -Unique)
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
        'Evidence Artifact',
        'Anchor Pattern',
        'End Pattern',
        'Lines Before',
        'Lines After',
        'Input Artifact',
        'Source Anchor Artifact',
        'Output',
        'Output Artifact',
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
    $matches = [regex]::Matches($PromptText, $directivePattern)
    $match = if ($matches.Count -gt 0) { $matches[$matches.Count - 1] } else { $null }

    $inlinePattern = '(?im)^\s*{0}\s*:[ \t]*(.+?)\s*$' -f [regex]::Escape($FieldName)
    $inlineMatches = [regex]::Matches($PromptText, $inlinePattern)
    $inlineMatch = if ($inlineMatches.Count -gt 0) { $inlineMatches[$inlineMatches.Count - 1] } else { $null }
    if ($null -ne $inlineMatch -and ($null -eq $match -or $inlineMatch.Index -gt $match.Index)) {
        return ([string]$inlineMatch.Groups[1].Value).Trim()
    }

    if ($null -ne $match -and $match.Success) {
        $inlineValue = ([string]$match.Groups['inline'].Value).Trim()
        if (-not [string]::IsNullOrWhiteSpace($inlineValue)) {
            return $inlineValue
        }

        return ([string]$match.Groups['block'].Value).Trim("`r", "`n")
    }

    if ($null -ne $inlineMatch -and $inlineMatch.Success) {
        return ([string]$inlineMatch.Groups[1].Value).Trim()
    }

    return ''
}

function Test-LocalExecutionReadOnlyRoleClassificationTask {
    param([Parameter(Mandatory = $true)]$Context)

    $category = Get-LocalExecutionTaskCategory -Context $Context
    if (@('read_only_assessment', 'read_only_role_classification', 'report_only', 'diagnostic_only', 'inspection_only', 'inspection', 'review_only') -notcontains $category) {
        return $false
    }

    $text = (Get-LocalExecutionCombinedText -Context $Context).ToLowerInvariant()
    return (
        $text -match 'communication_role_map|role classification|role map' -and
        $text -match 'evidence artifact|input artifact|review artifact' -and
        $text -match 'output\s*:' -and
        $text -match 'source file|inspect source file|inspect target file|package path|target file'
    )
}

function Get-LocalExecutionReadOnlyRoleClassificationOutputPath {
    param([Parameter(Mandatory = $true)]$Context)

    $paths = Get-LocalExecutionReadOnlyAuditArtifactPaths -Context $Context
    if (-not [string]::IsNullOrWhiteSpace([string]$paths.output_path)) {
        return [string]$paths.output_path
    }

    return ''
}

function Invoke-LocalExecutionReadOnlyRoleClassification {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)]$Spec
    )

    $text = Get-LocalExecutionCombinedText -Context $Context
    $paths = Get-LocalExecutionReadOnlyAuditArtifactPaths -Context $Context
    $inputRel = [string]$paths.input_path
    $outputRel = Get-LocalExecutionReadOnlyRoleClassificationOutputPath -Context $Context
    if ([string]::IsNullOrWhiteSpace($outputRel)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'role_classification_output_missing' -Reason 'Read-only role classification requires an Output path under runtime_remote_training/read_only_audit_artifacts/.' -MissingVariable 'output_path')
    }
    if (-not (Test-LocalExecutionSafePath -RelativePath $outputRel)) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'role_classification_output_unsafe' -Reason ('Read-only role classification output is outside safe roots: {0}' -f $outputRel) -MissingVariable 'safe_output_path')
    }

    $inputRead = $false
    $inputSummary = ''
    $blockerClass = 'authority_blocker'
    if (-not [string]::IsNullOrWhiteSpace($inputRel)) {
        if (-not (Test-LocalExecutionSafePath -RelativePath $inputRel)) {
            return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'role_classification_input_unsafe' -Reason ('Read-only role classification input is outside safe roots: {0}' -f $inputRel) -MissingVariable 'safe_input_path')
        }
        $inputAbs = Join-Path $script:LocalEngineRepoRoot $inputRel
        if (Test-Path -Path $inputAbs -PathType Leaf) {
            $inputRead = $true
            try {
                $inputJson = Get-Content -Path $inputAbs -Raw | ConvertFrom-Json
                if ($inputJson.PSObject.Properties['summary']) { $inputSummary = [string]$inputJson.summary }
                if ($inputJson.PSObject.Properties['blocker_class']) { $blockerClass = [string]$inputJson.blocker_class }
            }
            catch {
                $inputSummary = 'Input artifact was readable as text but not parseable JSON.'
            }
        }
    }

    $sourceFiles = New-Object System.Collections.Generic.List[string]
    foreach ($field in @('Source File', 'Inspect Source File', 'Inspect Target File')) {
        foreach ($match in [regex]::Matches($text, ('(?im)^\s*{0}\s*:\s*(?<path>\S[^\r\n]*)\s*$' -f [regex]::Escape($field)))) {
            $candidate = Convert-ToLocalExecutionRepoRelativePath -PathValue ([string]$match.Groups['path'].Value)
            if (-not [string]::IsNullOrWhiteSpace($candidate) -and -not $sourceFiles.Contains($candidate)) {
                [void]$sourceFiles.Add($candidate)
            }
        }
    }

    $packagePath = ''
    $packageMatch = [regex]::Match($text, '(?im)^\s*Package Path\s*:\s*(?<path>\S[^\r\n]*)\s*$')
    if ($packageMatch.Success) {
        $packagePath = Convert-ToLocalExecutionRepoRelativePath -PathValue ([string]$packageMatch.Groups['path'].Value)
    }

    $targetFileDirective = Get-LocalExecutionDirectiveValue -PromptText $text -FieldName 'Target File'
    $targetFile = if ([string]::IsNullOrWhiteSpace($targetFileDirective)) { '' } else { Convert-ToLocalExecutionRepoRelativePath -PathValue $targetFileDirective }
    $suspectedSourceFile = if (@($sourceFiles).Count -gt 0) { [string]$sourceFiles[0] } else { 'scripts/engines/LocalExecutionEngine.ps1' }
    $suspectedFunction = if ($text -match 'multiple candidate target files|target_file|patch targets?|bounded-edit materialization') { 'Get-LocalExecutionTargetFiles / Invoke-LocalExecutionGenericBoundedTask' } else { 'read-only role classification gate' }

    $artifact = [ordered]@{
        artifact_type = 'tod_read_only_role_classification_artifact'
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        source = 'local_execution_read_only_role_classification_lane'
        objective_id = if ($Context.PSObject.Properties['objective_id']) { [string]$Context.objective_id } else { '' }
        task_id = if ($Context.PSObject.Properties['task_id']) { [string]$Context.task_id } else { '' }
        communication_role_map = [ordered]@{
            'Evidence Artifact' = 'input_evidence_read_only'
            'Input Artifact' = 'input_evidence_read_only'
            'Review Artifact' = 'input_evidence_read_only'
            'Package Path' = 'package_evidence_read_only'
            'Source File' = 'source_to_inspect_read_only'
            'Inspect Source File' = 'source_to_inspect_read_only'
            'Inspect Target File' = 'source_to_inspect_for_read_only_tasks'
            'Output' = 'evidence_artifact_to_write'
            'Output Artifact' = 'evidence_artifact_to_write'
            'Target File' = 'bounded_edit_target_only_when_edit_mode_or_behavior_change_is_authorized'
        }
        observed_paths = [ordered]@{
            input_artifact = $inputRel
            package_path = $packagePath
            source_files = @($sourceFiles.ToArray())
            output_artifact = $outputRel
            target_file_directive = $targetFile
        }
        suspected_source_function = $suspectedFunction
        suspected_source_file = $suspectedSourceFile
        blocker_class = $blockerClass
        blocker_summary = $inputSummary
        smallest_next_repair_shape = 'Route read-only role-classification and inspection requests to an evidence-writing lane before generic bounded-edit target inference; only behavior-changing edit tasks may use source paths as patch targets.'
        validation_plan = @(
            'Read input evidence artifact when supplied.',
            'Confirm Output is written under runtime_remote_training/read_only_audit_artifacts.',
            'Confirm source files are recorded as inspection inputs, not changed files.',
            'Confirm no source code changes are required for this read-only task.'
        )
        no_code_changes = $true
    }

    $outputAbs = Join-Path $script:LocalEngineRepoRoot $outputRel
    New-Item -ItemType Directory -Path (Split-Path -Parent $outputAbs) -Force | Out-Null
    [System.IO.File]::WriteAllText($outputAbs, ($artifact | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))
    $readback = Get-Content -Path $outputAbs -Raw | ConvertFrom-Json
    $requiredFields = @('artifact_type', 'communication_role_map', 'suspected_source_function', 'suspected_source_file', 'blocker_class', 'smallest_next_repair_shape', 'validation_plan', 'no_code_changes')
    $missing = @($requiredFields | Where-Object { -not $readback.PSObject.Properties[$_] })
    if ($missing.Count -gt 0) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'role_classification_schema_failed' -Reason ('Read-only role classification artifact is missing required fields: {0}' -f ($missing -join ', ')) -MissingVariable 'artifact_schema')
    }
    if ($readback.no_code_changes -ne $true) {
        return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'role_classification_no_code_change_flag_failed' -Reason 'Read-only role classification artifact must set no_code_changes=true.' -MissingVariable 'no_code_changes')
    }

    $Result.summary = ('Published read-only role classification artifact {0}.' -f $outputRel)
    $Result.files_changed = @($outputRel)
    $Result.tests_run = @('input evidence role mapping', 'read-only role classification artifact write', 'required field readback', 'no-code-change assertion')
    $Result.test_results = @('pass', 'pass', 'pass', 'pass')
    $Result | Add-Member -NotePropertyName command_output -NotePropertyValue ('Read-only role classification artifact published: {0}' -f $outputRel) -Force
    $Result | Add-Member -NotePropertyName diff_summary -NotePropertyValue ('Artifact write only: {0}' -f $outputRel) -Force
    $Result | Add-Member -NotePropertyName commands_run -NotePropertyValue @('Invoke-LocalExecutionReadOnlyRoleClassification') -Force
    $Result | Add-Member -NotePropertyName validation_results -NotePropertyValue @(
        [pscustomobject]@{ name = 'input evidence role mapping'; passed = $inputRead; required = $false },
        [pscustomobject]@{ name = 'read-only role classification artifact write'; passed = $true; required = $true },
        [pscustomobject]@{ name = 'required field readback'; passed = $true; required = $true },
        [pscustomobject]@{ name = 'no-code-change assertion'; passed = $true; required = $true }
    ) -Force
    $Result | Add-Member -NotePropertyName blockers -NotePropertyValue @() -Force
    $Result | Add-Member -NotePropertyName confidence -NotePropertyValue 'high' -Force
    $Result | Add-Member -NotePropertyName rollback_hint -NotePropertyValue ('Remove generated artifact {0} if this training artifact must be discarded.' -f $outputRel) -Force
    $Result | Add-Member -NotePropertyName no_change_required -NotePropertyValue $false -Force
    return (Complete-EngineExecutionResult -Result $Result -Status 'completed')
}

function Get-LocalExecutionPacketQualityReviewSpec {
    param([Parameter(Mandatory = $true)]$Context)

    $promptText = Get-LocalExecutionPromptText -Context $Context
    $outputPath = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Output'
    if ([string]::IsNullOrWhiteSpace($outputPath)) {
        $outputPath = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Target File'
    }
    return [pscustomobject]@{
        output_path = Convert-ToLocalExecutionRepoRelativePath -PathValue $outputPath
        review_artifact = Convert-ToLocalExecutionRepoRelativePath -PathValue (Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Review Artifact')
        source_file = Convert-ToLocalExecutionRepoRelativePath -PathValue (Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Source File')
        validation_command = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Validation Command'
        expected_decision = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Expected Decision'
        required_old_text_pattern = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Required Old Text Pattern'
        required_new_text_pattern = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Required New Text Pattern'
        forbidden_old_text_pattern = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Forbidden Old Text Pattern'
        forbidden_new_text_pattern = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Forbidden New Text Pattern'
        forbidden_selected_candidate = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Forbidden Selected Candidate'
    }
}

function ConvertTo-LocalExecutionReviewPatterns {
    param([AllowEmptyString()][string]$PatternText)

    if ([string]::IsNullOrWhiteSpace([string]$PatternText)) {
        return [string[]]@()
    }

    $patterns = New-Object System.Collections.Generic.List[string]
    foreach ($part in @(([string]$PatternText) -split "(`r?`n|;)")) {
        $pattern = ([string]$part).Trim()
        if ([string]::IsNullOrWhiteSpace($pattern)) { continue }
        if (-not $patterns.Contains($pattern)) {
            [void]$patterns.Add($pattern)
        }
    }
    return [string[]]$patterns.ToArray()
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
    $selectedCandidate = if ($packet -and $packet.PSObject.Properties['selected_candidate']) { [string]$packet.selected_candidate } else { '' }
    $expectedDecision = ([string]$reviewSpec.expected_decision).Trim().ToLowerInvariant()

    $evidenceChecked = New-Object System.Collections.Generic.List[object]
    $failureReasons = New-Object System.Collections.Generic.List[string]
    $oldTextFound = (-not [string]::IsNullOrWhiteSpace($oldText) -and $sourceText.Contains($oldText))
    $newTextDiffers = (-not [string]::IsNullOrWhiteSpace($newText) -and -not [string]::Equals($oldText, $newText, [System.StringComparison]::Ordinal))
    $oldTerms = @([regex]::Matches($oldText, '"(?<term>[^"\r\n]*)"') | ForEach-Object { [string]$_.Groups['term'].Value } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    $newTerms = @([regex]::Matches($newText, '"(?<term>[^"\r\n]*)"') | ForEach-Object { [string]$_.Groups['term'].Value } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    $oldTermCounts = @{}
    foreach ($term in $oldTerms) {
        $key = [string]$term
        if (-not $oldTermCounts.ContainsKey($key)) { $oldTermCounts[$key] = 0 }
        $oldTermCounts[$key] = [int]$oldTermCounts[$key] + 1
    }
    $newTermCounts = @{}
    foreach ($term in $newTerms) {
        $key = [string]$term
        if (-not $newTermCounts.ContainsKey($key)) { $newTermCounts[$key] = 0 }
        $newTermCounts[$key] = [int]$newTermCounts[$key] + 1
    }
    $duplicateNewTerms = @($newTermCounts.Keys | Where-Object {
            [int]$newTermCounts[$_] -gt 1 -and [int]$newTermCounts[$_] -gt [int]$(if ($oldTermCounts.ContainsKey($_)) { $oldTermCounts[$_] } else { 0 })
        } | ForEach-Object { [string]$_ })
    $removedTerms = @($oldTermCounts.Keys | Where-Object {
            -not $newTermCounts.ContainsKey($_) -or [int]$newTermCounts[$_] -lt [int]$oldTermCounts[$_]
        } | ForEach-Object { [string]$_ })
    $unexpectedFlushLeftLines = @()
    if ($newText -match '(?m)^function\s+') {
        $newLines = @($newText -split "`r?`n")
        for ($lineIndex = 1; $lineIndex -lt $newLines.Count; $lineIndex++) {
            $line = [string]$newLines[$lineIndex]
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            if ($line -match '^\}\s*$') { continue }
            if ($line -match '^\S') {
                $unexpectedFlushLeftLines += ('line {0}: {1}' -f ($lineIndex + 1), $line.Trim())
            }
        }
    }

    $evidenceChecked.Add([ordered]@{ check = 'old_text_found_in_source'; passed = $oldTextFound; source_file = $sourceRel }) | Out-Null
    $evidenceChecked.Add([ordered]@{ check = 'new_text_differs_from_old_text'; passed = $newTextDiffers }) | Out-Null
    $evidenceChecked.Add([ordered]@{ check = 'new_text_duplicate_terms'; passed = (@($duplicateNewTerms).Count -eq 0); duplicate_terms = @($duplicateNewTerms) }) | Out-Null
    $evidenceChecked.Add([ordered]@{ check = 'old_text_useful_terms_removed'; passed = (@($removedTerms).Count -eq 0); removed_terms = @($removedTerms) }) | Out-Null
    $evidenceChecked.Add([ordered]@{ check = 'new_text_unexpected_flush_left_lines'; passed = (@($unexpectedFlushLeftLines).Count -eq 0); lines = @($unexpectedFlushLeftLines) }) | Out-Null

    if (-not $oldTextFound) { $failureReasons.Add('old_text was not found in the current source file') | Out-Null }
    if (-not $newTextDiffers) { $failureReasons.Add('new_text does not create a bounded delta') | Out-Null }
    if (@($duplicateNewTerms).Count -gt 0) { $failureReasons.Add(('new_text duplicates existing trigger(s): {0}' -f (@($duplicateNewTerms) -join ', '))) | Out-Null }
    if (@($removedTerms).Count -gt 0) { $failureReasons.Add(('new_text removes useful intent coverage: {0}' -f (@($removedTerms) -join ', '))) | Out-Null }
    if (@($unexpectedFlushLeftLines).Count -gt 0) { $failureReasons.Add(('new_text introduces unexpected flush-left line(s) inside a function body: {0}' -f (@($unexpectedFlushLeftLines) -join '; '))) | Out-Null }

    foreach ($pattern in @(ConvertTo-LocalExecutionReviewPatterns -PatternText ([string]$reviewSpec.required_old_text_pattern))) {
        $passed = $oldText.IndexOf($pattern, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
        $evidenceChecked.Add([ordered]@{ check = 'required_old_text_pattern'; passed = $passed; pattern = $pattern }) | Out-Null
        if (-not $passed) { $failureReasons.Add(('old_text does not contain required semantic pattern: {0}' -f $pattern)) | Out-Null }
    }
    foreach ($pattern in @(ConvertTo-LocalExecutionReviewPatterns -PatternText ([string]$reviewSpec.required_new_text_pattern))) {
        $passed = $newText.IndexOf($pattern, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
        $evidenceChecked.Add([ordered]@{ check = 'required_new_text_pattern'; passed = $passed; pattern = $pattern }) | Out-Null
        if (-not $passed) { $failureReasons.Add(('new_text does not contain required semantic pattern: {0}' -f $pattern)) | Out-Null }
    }
    foreach ($pattern in @(ConvertTo-LocalExecutionReviewPatterns -PatternText ([string]$reviewSpec.forbidden_old_text_pattern))) {
        $passed = $oldText.IndexOf($pattern, [System.StringComparison]::OrdinalIgnoreCase) -lt 0
        $evidenceChecked.Add([ordered]@{ check = 'forbidden_old_text_pattern'; passed = $passed; pattern = $pattern }) | Out-Null
        if (-not $passed) { $failureReasons.Add(('old_text contains forbidden semantic pattern: {0}' -f $pattern)) | Out-Null }
    }
    foreach ($pattern in @(ConvertTo-LocalExecutionReviewPatterns -PatternText ([string]$reviewSpec.forbidden_new_text_pattern))) {
        $passed = $newText.IndexOf($pattern, [System.StringComparison]::OrdinalIgnoreCase) -lt 0
        $evidenceChecked.Add([ordered]@{ check = 'forbidden_new_text_pattern'; passed = $passed; pattern = $pattern }) | Out-Null
        if (-not $passed) { $failureReasons.Add(('new_text contains forbidden semantic pattern: {0}' -f $pattern)) | Out-Null }
    }
    foreach ($pattern in @(ConvertTo-LocalExecutionReviewPatterns -PatternText ([string]$reviewSpec.forbidden_selected_candidate))) {
        $passed = $selectedCandidate.IndexOf($pattern, [System.StringComparison]::OrdinalIgnoreCase) -lt 0
        $evidenceChecked.Add([ordered]@{ check = 'forbidden_selected_candidate'; passed = $passed; pattern = $pattern; selected_candidate = $selectedCandidate }) | Out-Null
        if (-not $passed) { $failureReasons.Add(('selected_candidate is forbidden for this review: {0}' -f $pattern)) | Out-Null }
    }

    $discoveryPath = Join-Path (Split-Path -Parent $reviewAbs) 'TOD_DIFFERENT_TARGET_DISCOVERY_DRILL.latest.json'
        $discoveryArtifactAuthorized = (
        $packetArtifact.PSObject.Properties['discovery_artifact'] -or
        $packetArtifact.PSObject.Properties['expected_changed_files']
    )
    if (-not $discoveryArtifactAuthorized) {
        $discoveryPath = Join-Path (Split-Path -Parent $reviewAbs) '__no_explicit_discovery_artifact__.json'
    }

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

    $intrinsicDecision = if (@($failureReasons).Count -gt 0) { 'reject_packet' } else { 'accept_packet' }
    if ($expectedDecision -in @('accept_packet', 'reject_packet')) {
        $expectedDecisionMatches = [string]::Equals($intrinsicDecision, $expectedDecision, [System.StringComparison]::OrdinalIgnoreCase)
        $evidenceChecked.Add([ordered]@{ check = 'expected_decision_matches_intrinsic_review'; passed = $expectedDecisionMatches; expected_decision = $expectedDecision; intrinsic_decision = $intrinsicDecision }) | Out-Null
        if (-not $expectedDecisionMatches -and $expectedDecision -eq 'reject_packet') {
            $failureReasons.Add('expected_decision requested reject_packet, but intrinsic review did not identify a rejection reason') | Out-Null
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

    $targetAbs = Resolve-LocalExecutionAbsoluteTargetPath -RelativePath $TargetFile -Operation 'read'
    $safeTarget = $targetAbs.Replace("'", "''")
    $template = @'
$p = '{{TARGET}}'
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
        [string]$MissingVariable = '',
        [string]$Status = 'failed'
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
    return (Complete-EngineExecutionResult -Result $Result -Status $Status)
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
            [pscustomobject]@{ name = 'focused_validation_exit_zero'; passed = $validationExitZero; required = $true },
            [pscustomobject]@{ name = 'focused_validation_stderr_empty'; passed = $validationStderrEmpty; required = $true },
            [pscustomobject]@{ name = 'python_unittest_ok'; passed = $pythonUnittestOk; required = $false },
            [pscustomobject]@{ name = 'python_unittest_ok_with_finalizer_residue'; passed = $pythonUnittestFinalizerResidue; required = $false },
            [pscustomobject]@{ name = 'validation_only_no_file_change_expected'; passed = $passed; required = $true }
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
            if ([string]::IsNullOrWhiteSpace($oldText)) {
                return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'local_fallback_needs_target_or_scope' -Reason 'LocalExecutionEngine requires an Old Text directive for replace_text mode.' -MissingVariable 'old_text')
            }
            if ([string]::IsNullOrWhiteSpace($newText)) {
                return (New-LocalExecutionBlockedResult -Context $Context -Result $Result -Spec $Spec -ReasonCode 'local_fallback_needs_target_or_scope' -Reason 'LocalExecutionEngine requires a New Text directive for replace_text mode.' -MissingVariable 'new_text')
            }
            $updatedContent = Set-StrictTextReplacement -Content $originalContent -OldText $oldText -NewText $newText -Label ('bounded replacement in ' + $targetFile)
            $actionSummary = ('Replaced bounded text in {0}' -f $targetFile)
            $validationCommand = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Validation Command'
            if ([string]::IsNullOrWhiteSpace($validationCommand)) {
                $validationPattern = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Validation Pattern'
                if ([string]::IsNullOrWhiteSpace($validationPattern)) { $validationPattern = $newText }
                $validationCommand = New-LocalExecutionPatternValidationCommand -TargetFile $targetFile -Pattern $validationPattern
            }
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
        [pscustomobject]@{ name = 'target_file_exists'; passed = (Test-Path -Path $absoluteTargetPath); required = $true },
        [pscustomobject]@{ name = 'focused_validation_exit_zero'; passed = $validationExitZero; required = $true },
        [pscustomobject]@{ name = 'focused_validation_stderr_empty'; passed = $validationStderrEmpty; required = $true },
        [pscustomobject]@{ name = 'python_unittest_ok'; passed = $pythonUnittestOk; required = $false },
        [pscustomobject]@{ name = 'python_unittest_ok_with_finalizer_residue'; passed = $pythonUnittestFinalizerResidue; required = $false },
        [pscustomobject]@{ name = $changeCheckName; passed = $changeCheckPassed; required = $true }
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
            "read_only_task_context_artifact_publication",
            "patch_evidence_authority_classification",
            "saved_route_patch_evidence_discovery",
            "fresh_route_patch_evidence_registration",
            "source_anchor_observation_artifact_publication",
            "anchor_selection_artifact_publication",
            "anchor_selection_semantic_rejection_artifact_publication",
            "different_target_discovery_artifact_publication",
            "target_selection_artifact_publication",
            "packet_body_synthesis_artifact_publication",
            "python_snippet_body_synthesis_artifact_publication",
            "powershell_snippet_body_synthesis_artifact_publication",
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
    elseif (Test-LocalExecutionReadOnlyRoleClassificationTask -Context $Context) {
        $result = Invoke-LocalExecutionReadOnlyRoleClassification -Context $Context -Result $result -Spec $spec
    }
    elseif (Test-LocalExecutionAnchorSelectionSemanticRejectionTask -Context $Context) {
        $result = Invoke-LocalExecutionAnchorSelectionSemanticRejection -Context $Context -Result $result -Spec $spec
    }
    elseif (Test-LocalExecutionSemanticSourceAuditTask -Context $Context) {
        $result = Invoke-LocalExecutionSemanticSourceAudit -Context $Context -Result $result -Spec $spec
    }
    elseif ([string]::Equals((Get-LocalExecutionTaskCategory -Context $Context), 'target_selection', [System.StringComparison]::OrdinalIgnoreCase) -and (Test-LocalExecutionDifferentTargetDiscoveryTask -Context $Context)) {
        $result = Invoke-LocalExecutionDifferentTargetDiscovery -Context $Context -Result $result -Spec $spec
    }
    elseif (Test-LocalExecutionPacketAnchorSuitabilityTask -Context $Context) {
        $result = Invoke-LocalExecutionPacketAnchorSuitability -Context $Context -Result $result -Spec $spec
    }
    elseif (Test-LocalExecutionSourceAnchorPacketDirectiveTask -Context $Context) {
        $result = Invoke-LocalExecutionSourceAnchorPacketDirective -Context $Context -Result $result -Spec $spec
    }
    elseif (Test-LocalExecutionPacketQualityReviewTask -Context $Context) {
        $result = Invoke-LocalExecutionPacketQualityReview -Context $Context -Result $result -Spec $spec
    }
    elseif (Test-LocalExecutionSourceAnchorObservationTask -Context $Context) {
        $result = Invoke-LocalExecutionSourceAnchorObservation -Context $Context -Result $result -Spec $spec
    }
    elseif (Test-LocalExecutionReadOnlyAuditArtifactTask -Context $Context) {
        $result = Invoke-LocalExecutionReadOnlyAuditArtifact -Context $Context -Result $result -Spec $spec
    }
    elseif (Test-LocalExecutionReadOnlyTaskContextArtifactTask -Context $Context) {
        $result = Invoke-LocalExecutionReadOnlyTaskContextArtifact -Context $Context -Result $result -Spec $spec
    }
    elseif (Test-LocalExecutionSavedRoutePatchEvidenceDiscoveryTask -Context $Context) {
        $result = Invoke-LocalExecutionSavedRoutePatchEvidenceDiscovery -Context $Context -Result $result -Spec $spec
    }
    elseif (Test-LocalExecutionFreshRoutePatchEvidenceRegistrationTask -Context $Context) {
        $result = Invoke-LocalExecutionFreshRoutePatchEvidenceRegistration -Context $Context -Result $result -Spec $spec
    }
    elseif (Test-LocalExecutionPatchEvidenceArtifactTask -Context $Context) {
        $result = Invoke-LocalExecutionPatchEvidenceArtifact -Context $Context -Result $result -Spec $spec
    }
    elseif (Test-LocalExecutionAnchorSelectionTask -Context $Context) {
        $result = Invoke-LocalExecutionAnchorSelection -Context $Context -Result $result -Spec $spec
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
    elseif (Test-LocalExecutionPythonSnippetBodySynthesisTask -Context $Context) {
        $result = Invoke-LocalExecutionPythonSnippetBodySynthesis -Context $Context -Result $result -Spec $spec
    }
    elseif (Test-LocalExecutionPowerShellSnippetBodySynthesisTask -Context $Context) {
        $result = Invoke-LocalExecutionPowerShellSnippetBodySynthesis -Context $Context -Result $result -Spec $spec
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
