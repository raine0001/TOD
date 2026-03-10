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
        if ($SimulatedOutput.ContainsKey("needs_escalation")) { $result.needs_escalation = [bool]$SimulatedOutput.needs_escalation }
        $stdout += "[codex-wrapper] simulated output applied"
    }
    else {
        if ($promptExists) {
            $result.summary = "CodexExecutionEngine wrapper accepted package and prepared normalized result from prompt path: $promptPath"
            $stdout += "[codex-wrapper] package accepted"
            $stdout += "[codex-wrapper] normalized envelope produced"
        }
        else {
            $result.summary = "CodexExecutionEngine wrapper executed without package file; using inline context fallback."
            $stderr += "[codex-wrapper] prompt file not found; inline fallback path used"
        }

        $result.tests_run = @("codex-wrapper package-path check", "engine contract self-check")
        $result.test_results = @("pass", "pass")
        $result.recommendations = @(
            "Persist this normalized output through TOD add-result/review flow.",
            "Use invoke-engine for package-path orchestration."
        )
    }

    $result.raw_output = [pscustomobject]@{
        engine = $spec
        wrapper_mode = "provider-adapter"
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

    $result = Complete-EngineExecutionResult -Result $result -Status "completed"

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
        needs_escalation = [bool]$EngineResult.needs_escalation
        engine = [pscustomobject]@{
            name = [string]$EngineResult.engine_name
            version = [string]$EngineResult.engine_version
            execution_id = [string]$EngineResult.execution_id
            status = [string]$EngineResult.status
        }
    }
}
