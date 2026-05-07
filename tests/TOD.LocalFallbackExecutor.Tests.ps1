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
        Import-ScriptFunction -ScriptPath $todScript -Name 'Publish-LocalExecutionArtifacts'
        Import-ScriptFunctionWithLiteralRoot -ScriptPath $todScript -Name 'Invoke-ExecutionEngine' -LiteralRoot (Join-Path $repoRoot 'scripts')

        . $localEngineScript
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