Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. "$PSScriptRoot/ExecutionEngine.ps1"

function Get-LocalExecutionEngineSpec {
    [pscustomobject]@{
        name = "local"
        version = "0.1-placeholder"
        lifecycle = @("prepare", "execute", "finalize")
        supports = @(
            "structured_result_output",
            "engine_metadata"
        )
        mode = "placeholder"
    }
}

function Invoke-LocalExecutionEngine {
    param(
        [Parameter(Mandatory = $true)]$Context
    )

    $spec = Get-LocalExecutionEngineSpec
    $result = New-EngineExecutionResult -EngineName $spec.name -EngineVersion $spec.version -TaskId ([string]$Context.task_id)
    $result.execution_id = "LOCAL-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 10).ToUpperInvariant())

    $result.summary = "LocalExecutionEngine placeholder is not implemented yet."
    $result.tests_run = @("local-engine placeholder check")
    $result.test_results = @("not-implemented")
    $result.failures = @("LocalExecutionEngine execution path is a placeholder.")
    $result.recommendations = @(
        "Use execution_engine.active=codex for active execution.",
        "Implement local execution strategy in Task 29+ follow-up."
    )
    $result.needs_escalation = $true

    $result.raw_output = [pscustomobject]@{
        engine = $spec
        task_context = [pscustomobject]@{
            task_id = [string]$Context.task_id
            objective_id = [string]$Context.objective_id
            title = [string]$Context.title
            scope = [string]$Context.scope
        }
        message = "placeholder_not_implemented"
        generated_at = (Get-Date).ToUniversalTime().ToString("o")
    }

    $result = Complete-EngineExecutionResult -Result $result -Status "not_implemented"

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
        needs_escalation = [bool]$EngineResult.needs_escalation
        engine = [pscustomobject]@{
            name = [string]$EngineResult.engine_name
            version = [string]$EngineResult.engine_version
            execution_id = [string]$EngineResult.execution_id
            status = [string]$EngineResult.status
        }
    }
}
