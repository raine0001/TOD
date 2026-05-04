Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. "$PSScriptRoot/ExecutionEngine.ps1"

function Get-CodexExecutionEngineSpec {
    [pscustomobject]@{
        name = "codex"
        version = "1.1-wrapper"
        lifecycle = @("prepare", "execute", "finalize")
        supports = @(
            "prompt_path_input",
            "structured_result_output",
            "engine_metadata",
            "wrapper_stdout_stderr_equivalent"
        )
    }
}

function Get-PackagePreview {
    param([string]$Path, [int]$MaxChars = 400)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -Path $Path)) {
        return ""
    }

    $raw = Get-Content -Path $Path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) { return "" }
    if ($raw.Length -le $MaxChars) { return $raw }
    return ($raw.Substring(0, $MaxChars) + " ...")
}

function Invoke-CodexExecutionEngineWrapper {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [hashtable]$SimulatedOutput
    )

    $spec = Get-CodexExecutionEngineSpec
    $result = New-EngineExecutionResult -EngineName $spec.name -EngineVersion $spec.version -TaskId ([string]$Context.task_id)
    $result.execution_id = "CDEX-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 10).ToUpperInvariant())
    $result.status = "running"

    $promptPath = [string]$Context.prompt_path
    $promptExists = -not [string]::IsNullOrWhiteSpace($promptPath) -and (Test-Path -Path $promptPath)
    $promptPreview = Get-PackagePreview -Path $promptPath -MaxChars 400

    $stdout = @()
    $stderr = @()
    $stdout += ("[codex-wrapper] task_id={0}" -f [string]$Context.task_id)
    $stdout += ("[codex-wrapper] prompt_path={0}" -f $promptPath)

    if ($null -ne $SimulatedOutput) {
        if ($SimulatedOutput.ContainsKey("summary")) { $result.summary = [string]$SimulatedOutput.summary }
        if ($SimulatedOutput.ContainsKey("files_changed")) { $result.files_changed = @($SimulatedOutput.files_changed) }
        if ($SimulatedOutput.ContainsKey("tests_run")) { $result.tests_run = @($SimulatedOutput.tests_run) }
        if ($SimulatedOutput.ContainsKey("test_results")) { $result.test_results = @($SimulatedOutput.test_results) }
        if ($SimulatedOutput.ContainsKey("failures")) { $result.failures = @($SimulatedOutput.failures) }
        if ($SimulatedOutput.ContainsKey("recommendations")) { $result.recommendations = @($SimulatedOutput.recommendations) }
        if ($SimulatedOutput.ContainsKey("structured_findings")) { $result.structured_findings = @($SimulatedOutput.structured_findings) }
        if ($SimulatedOutput.ContainsKey("needs_escalation")) { $result.needs_escalation = [bool]$SimulatedOutput.needs_escalation }
        $stdout += "[codex-wrapper] simulated output applied"
    }
    else {
        if ($promptExists) {
            $result.summary = "CodexExecutionEngine wrapper accepted the packaged prompt but did not execute task instructions or produce code-change evidence from prompt path: $promptPath"
            $result.failures = @(
                'Codex wrapper only accepted the task package; no patch, command execution, validation artifact, or changed-file evidence was produced.'
            )
            $result.recommendations = @(
                'Attempt safe local fallback for this task when a bounded local executor is available.',
                'If local fallback is unsupported, publish the blocker details and replan the bounded task instead of counting wrapper acceptance as progress.'
            )
            $result.structured_findings = @(
                [pscustomobject]@{
                    type = 'blocker'
                    reason_code = 'codex_wrapper_only_no_execution'
                    file = 'scripts/engines/CodexExecutionEngine.ps1'
                    function = 'Invoke-CodexExecutionEngineWrapper'
                    reason = 'The codex wrapper accepted the packaged prompt path and emitted a normalized envelope without executing task instructions or producing task evidence.'
                    prompt_path = $promptPath
                    next_action = 'attempt_local_fallback_or_replan'
                }
            )
            $result.needs_escalation = $false
            $stdout += "[codex-wrapper] package accepted"
            $stdout += "[codex-wrapper] normalized envelope produced"
            $stdout += "[codex-wrapper] wrapper_only_no_execution"
        }
        else {
            $result.summary = "CodexExecutionEngine wrapper executed without package file; using inline context fallback."
            $result.failures = @('Codex wrapper could not locate the packaged prompt, so task execution did not start.')
            $result.recommendations = @('Repackage the task and retry the engine only after the prompt path exists.')
            $stderr += "[codex-wrapper] prompt file not found; inline fallback path used"
        }

        $result.tests_run = @("codex-wrapper package-path check", "codex-wrapper execution handoff")
        $result.test_results = @($(if ($promptExists) { 'pass' } else { 'fail' }), 'not_implemented')
    }

    $result.raw_output = [pscustomobject]@{
        engine = $spec
        wrapper_mode = "provider-adapter"
        execution_performed = $false
        reason_code = $(if ($promptExists) { 'codex_wrapper_only_no_execution' } else { 'codex_prompt_missing' })
        task_context = [pscustomobject]@{
            task_id = [string]$Context.task_id
            objective_id = [string]$Context.objective_id
            title = [string]$Context.title
            scope = [string]$Context.scope
            prompt_path = $promptPath
            prompt_exists = $promptExists
        }
        io_capture = [pscustomobject]@{
            stdout = @($stdout)
            stderr = @($stderr)
        }
        package_preview = $promptPreview
        generated_at = (Get-Date).ToUniversalTime().ToString("o")
    }

    $result | Add-Member -NotePropertyName reason_code -NotePropertyValue $(if ($promptExists) { 'codex_wrapper_only_no_execution' } else { 'codex_prompt_missing' }) -Force
    $result | Add-Member -NotePropertyName recovery_state -NotePropertyValue $(if ($promptExists) { 'local_fallback_or_replan_required' } else { 'repackage_required' }) -Force
    $result = Complete-EngineExecutionResult -Result $result -Status $(if ($promptExists) { 'not_implemented' } else { 'failed' })

    $validation = Test-EngineContract -Context $Context -Result $result
    if (-not [bool]$validation.is_valid) {
        throw "CodexExecutionEngine wrapper output failed interface validation."
    }

    return $result
}

function Invoke-CodexExecutionEngine {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [hashtable]$SimulatedOutput
    )

    return (Invoke-CodexExecutionEngineWrapper -Context $Context -SimulatedOutput $SimulatedOutput)
}

function Convert-CodexEngineResultToTodResult {
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
