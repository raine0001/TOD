Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-ExecutionEngineInterfaceSpec {
    [pscustomobject]@{
        interface_version = "1.0"
        context_fields = @(
            "task_id",
            "objective_id",
            "title",
            "scope",
            "prompt_path",
            "allowed_files",
            "validation_commands",
            "metadata"
        )
        result_fields = @(
            "engine_name",
            "engine_version",
            "execution_id",
            "status",
            "task_id",
            "summary",
            "files_changed",
            "tests_run",
            "test_results",
            "failures",
            "recommendations",
            "needs_escalation",
            "started_at",
            "completed_at",
            "raw_output"
        )
        lifecycle_hooks = @(
            "prepare",
            "execute",
            "finalize"
        )
    }
}

function New-EngineTaskContext {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TaskId,
        [string]$ObjectiveId,
        [string]$Title,
        [string]$Scope,
        [string]$PromptPath,
        [string[]]$AllowedFiles = @(),
        [string[]]$ValidationCommands = @(),
        [hashtable]$Metadata = @{}
    )

    [pscustomobject]@{
        task_id = $TaskId
        objective_id = $ObjectiveId
        title = $Title
        scope = $Scope
        prompt_path = $PromptPath
        allowed_files = @($AllowedFiles)
        validation_commands = @($ValidationCommands)
        metadata = $Metadata
    }
}

function New-EngineExecutionResult {
    param(
        [Parameter(Mandatory = $true)][string]$EngineName,
        [Parameter(Mandatory = $true)][string]$EngineVersion,
        [Parameter(Mandatory = $true)][string]$TaskId
    )

    [pscustomobject]@{
        engine_name = $EngineName
        engine_version = $EngineVersion
        execution_id = ""
        status = "prepared"
        task_id = $TaskId
        summary = ""
        files_changed = @()
        tests_run = @()
        test_results = @()
        failures = @()
        recommendations = @()
        needs_escalation = $false
        started_at = (Get-Date).ToUniversalTime().ToString("o")
        completed_at = ""
        raw_output = $null
    }
}

function Complete-EngineExecutionResult {
    param(
        [Parameter(Mandatory = $true)]$Result,
        [string]$Status = "completed"
    )

    $Result.status = $Status
    $Result.completed_at = (Get-Date).ToUniversalTime().ToString("o")
    return $Result
}

function Test-EngineContract {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)]$Result
    )

    $spec = Get-ExecutionEngineInterfaceSpec

    $missingContext = @($spec.context_fields | Where-Object { -not $Context.PSObject.Properties[$_] })
    $missingResult = @($spec.result_fields | Where-Object { -not $Result.PSObject.Properties[$_] })

    [pscustomobject]@{
        is_valid = (@($missingContext).Count -eq 0 -and @($missingResult).Count -eq 0)
        missing_context_fields = @($missingContext)
        missing_result_fields = @($missingResult)
    }
}
