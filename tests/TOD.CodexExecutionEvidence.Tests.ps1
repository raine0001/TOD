Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$todScript = Join-Path $repoRoot 'scripts/TOD.ps1'
$codexScript = Join-Path $repoRoot 'scripts/engines/CodexExecutionEngine.ps1'
$executionEngineScript = Join-Path $repoRoot 'scripts/engines/ExecutionEngine.ps1'
$global:repoRoot = $repoRoot

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

Describe 'TOD codex execution evidence repair' {
    BeforeAll {
        Import-ScriptFunction -ScriptPath $executionEngineScript -Name 'Get-ExecutionEngineInterfaceSpec'
        Import-ScriptFunction -ScriptPath $executionEngineScript -Name 'New-EngineExecutionResult'
        Import-ScriptFunction -ScriptPath $executionEngineScript -Name 'Complete-EngineExecutionResult'
        Import-ScriptFunction -ScriptPath $executionEngineScript -Name 'Test-EngineContract'

        Import-ScriptFunction -ScriptPath $todScript -Name 'Get-UtcNow'
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

        Import-ScriptFunction -ScriptPath $codexScript -Name 'Get-CodexExecutionEngineSpec'
        Import-ScriptFunction -ScriptPath $codexScript -Name 'Get-PackagePreview'
        Import-ScriptFunction -ScriptPath $codexScript -Name 'Invoke-CodexExecutionEngineWrapper'
        Import-ScriptFunction -ScriptPath $codexScript -Name 'Invoke-CodexExecutionEngine'
    }

    It 'marks wrapper-only codex output as not_implemented with an explicit reason code' {
        $tempPrompt = Join-Path $repoRoot ('tod/out/tests/codex-wrapper-' + [guid]::NewGuid().ToString('N') + '.md')
        $tempDir = Split-Path -Parent $tempPrompt
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        Set-Content -Path $tempPrompt -Value '# prompt' -Encoding utf8

        $context = [pscustomobject]@{
            task_id = 'TSK-WRAP-1'
            objective_id = 'OBJ-WRAP-1'
            title = 'Patch target file'
            scope = 'Patch the bounded target file and validate it.'
            prompt_path = $tempPrompt
            allowed_files = @()
            validation_commands = @()
            metadata = @{}
        }

        $result = Invoke-CodexExecutionEngine -Context $context

        [string]$result.status | Should Be 'not_implemented'
        [string]$result.reason_code | Should Be 'codex_wrapper_only_no_execution'
        [string]$result.structured_findings[0].function | Should Be 'Invoke-CodexExecutionEngineWrapper'
        [string]$result.summary | Should Match 'did not execute'

        Remove-Item -Path $tempPrompt -Force
    }

    It 'builds a specific blocker result after wrapper-only codex and unsupported local fallback' {
        $task = [pscustomobject]@{
            id = 'TSK-FALLBACK-1'
            objective_id = 'OBJ-FALLBACK-1'
            title = 'Patch token extraction'
            scope = 'Patch token extraction so only the identifier value is captured.'
            type = 'implementation'
            task_category = 'code_change'
        }
        $primaryResult = [pscustomobject]@{
            engine_name = 'codex'
            engine_version = '1.1-wrapper'
            execution_id = 'CDEX-TEST-1'
            status = 'not_implemented'
            task_id = 'TSK-FALLBACK-1'
            summary = 'CodexExecutionEngine wrapper accepted the packaged prompt but did not execute task instructions.'
            files_changed = @()
            tests_run = @('codex-wrapper package-path check', 'codex-wrapper execution handoff')
            test_results = @('pass', 'not_implemented')
            failures = @('Codex wrapper only accepted the task package; no patch, command execution, validation artifact, or changed-file evidence was produced.')
            recommendations = @('Attempt safe local fallback for this task when a bounded local executor is available.')
            structured_findings = @(
                [pscustomobject]@{ type = 'blocker'; reason_code = 'codex_wrapper_only_no_execution'; function = 'Invoke-CodexExecutionEngineWrapper' }
            )
            needs_escalation = $false
            raw_output = [pscustomobject]@{ engine = [pscustomobject]@{ name = 'codex' } }
            reason_code = 'codex_wrapper_only_no_execution'
            recovery_state = 'local_fallback_or_replan_required'
        }
        $fallbackResult = [pscustomobject]@{
            engine_name = 'local'
            engine_version = '1.0'
            execution_id = 'LOCAL-TEST-1'
            status = 'not_implemented'
            task_id = 'TSK-FALLBACK-1'
            summary = 'LocalExecutionEngine is implemented for bounded execution-loop, README, and TOD config bootstrap objectives, but this task did not match a supported scope.'
            files_changed = @()
            tests_run = @('local-engine task scope match')
            test_results = @('not-supported')
            failures = @('Task did not match the current bounded local engine capability.')
            recommendations = @('Extend LocalExecutionEngine with the next bounded action capability before retrying broader tasks.')
            structured_findings = @()
            needs_escalation = $true
            raw_output = [pscustomobject]@{ message = 'bounded_local_scope_not_matched' }
        }

        $result = New-ExecutionEngineBlockedResult -Task $task -TaskId 'TSK-FALLBACK-1' -PackagePath 'E:\TOD\tod\out\prompts\TSK-FALLBACK-1.md' -PrimaryResult $primaryResult -FallbackResult $fallbackResult -AttemptedEngines @('codex', 'local') -AttemptDetails @() -FallbackEngine 'local'

        [string]$result.reason_code | Should Be 'codex_wrapper_only_no_execution'
        [string]$result.recovery_state | Should Match 'replan'
        ([string]::Join(' ', @($result.failures)) -match 'Wrapper-only codex output') | Should Be $true
        [string]$result.structured_findings[1].function | Should Be 'Invoke-LocalExecutionEngine'
    }

    It 'publishes explicit blocker reason codes as blocked_with_reason instead of no_op_rejected' {
        function global:Get-TodExecutionSharedRoots {
            return ,(Join-Path $repoRoot ('tod/out/tests/codex-artifacts-' + [guid]::NewGuid().ToString('N')))
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

        $task = [pscustomobject]@{
            id = 'TSK-BLOCK-1'
            objective_id = 'OBJ-BLOCK-1'
            title = 'Patch token extraction'
            scope = 'Patch token extraction so only the identifier value is captured.'
            type = 'implementation'
            task_category = 'code_change'
        }
        $payload = [pscustomobject]@{
            summary = 'Codex wrapper only accepted the task package.'
            files_changed = @()
            tests_run = @('codex-wrapper package-path check', 'local-engine task scope match')
            test_results = @('pass', 'not-supported')
            failures = @('Wrapper-only codex output did not execute the bounded code-change task.')
            recommendations = @('Replan the bounded task.')
            structured_findings = @(
                [pscustomobject]@{ type = 'blocker'; reason_code = 'codex_wrapper_only_no_execution'; file = 'scripts/engines/CodexExecutionEngine.ps1'; function = 'Invoke-CodexExecutionEngineWrapper'; reason = 'No execution occurred.' }
            )
            needs_escalation = $false
            reason_code = 'codex_wrapper_only_no_execution'
            recovery_state = 'replan_required_after_local_fallback'
        }

        $published = Publish-LocalExecutionArtifacts -Task $task -Objective $null -ResultPayload $payload -ReviewDecision 'revise' -ExecutionId 'EXEC-BLOCK-1' -PackagePath 'E:\TOD\tod\out\prompts\TSK-BLOCK-1.md' -ExecutionReadiness ([pscustomobject]@{ status = 'valid' })

        [string]$published.active_task.execution_state | Should Be 'blocked_with_reason'
        [string]$published.execution_result.reason_code | Should Be 'codex_wrapper_only_no_execution'
        [string]$published.active_task.next_step | Should Match 'replan'

        Remove-Item function:\Get-TodExecutionSharedRoots -ErrorAction SilentlyContinue
        Remove-Item function:\Write-TodExecutionSharedJson -ErrorAction SilentlyContinue
        Remove-Item function:\Publish-RemoteTodExecutionArtifacts -ErrorAction SilentlyContinue
    }
}