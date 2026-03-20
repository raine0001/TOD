param(
    [string]$TaskQueuePath = "shared_state/agentmim/MIM_TOD_AGENT_TASK_QUEUE.latest.json",
    [string]$OutputPath = "shared_state/agentmim/MIM_TOD_LOCAL_VERIFICATION_RESULTS.latest.json",
    [switch]$EmitJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

function Resolve-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) { return $PathValue }
    return (Join-Path $repoRoot $PathValue)
}

function To-Array {
    param($Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Array]) { return @($Value) }
    return @($Value)
}

function Test-CommandAvailable {
    param([Parameter(Mandatory = $true)][string]$CommandName)
    try {
        $null = Get-Command $CommandName -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

$resolvedTaskQueuePath = Resolve-LocalPath -PathValue $TaskQueuePath
$resolvedOutputPath = Resolve-LocalPath -PathValue $OutputPath

if (-not (Test-Path -Path $resolvedTaskQueuePath)) {
    throw "Task queue not found: $resolvedTaskQueuePath"
}

$queueObj = Get-Content -Path $resolvedTaskQueuePath -Raw | ConvertFrom-Json
$tasks = To-Array -Value $queueObj.task_queue | Where-Object { [string]$_.category -eq "local-verification" }

$results = @()
foreach ($task in $tasks) {
    $projectId = [string]$task.project_id
    $projectName = [string]$task.project_name
    $sourceRoot = [string]$task.local_copy_contract.source_root
    $releaseTag = [string]$task.local_copy_contract.release_tag
    $criticalDocs = @()

    # Use the runtime brief to gather critical docs for this project.
    $runtimeBriefPath = Join-Path $repoRoot ("shared_state/project_briefs/{0}/MIM_TOD_RUNTIME_BRIEF.latest.json" -f $projectId)
    if (Test-Path -Path $runtimeBriefPath) {
        $runtimeBrief = Get-Content -Path $runtimeBriefPath -Raw | ConvertFrom-Json
        if ($runtimeBrief.PSObject.Properties["critical_docs_paths"]) {
            $criticalDocs = To-Array -Value $runtimeBrief.critical_docs_paths
        }
    }

    $pathExists = Test-Path -Path $sourceRoot

    $docChecks = @()
    foreach ($doc in $criticalDocs) {
        $docChecks += [pscustomobject]@{
            path = [string]$doc
            exists = (Test-Path -Path ([string]$doc))
        }
    }

    $docsPresent = $true
    if (@($docChecks).Count -gt 0) {
        $docsPresent = @($docChecks | Where-Object { -not [bool]$_.exists }).Count -eq 0
    }

    $suggestedCommands = To-Array -Value $task.suggested_commands
    $commandChecks = @()
    foreach ($cmd in $suggestedCommands) {
        $commandName = ([string]$cmd).Split(' ')[0]
        if ([string]::IsNullOrWhiteSpace($commandName)) { continue }
        $commandChecks += [pscustomobject]@{
            command = [string]$cmd
            available = (Test-CommandAvailable -CommandName $commandName)
        }
    }

    $verificationCommandIdentified = @($suggestedCommands).Count -gt 0
    $commandAvailable = if (@($commandChecks).Count -gt 0) { @($commandChecks | Where-Object { [bool]$_.available }).Count -gt 0 } else { $false }

    $git = [pscustomobject]@{
        repository = $false
        branch = "n/a"
        latest_tag = "n/a"
    }

    if ($pathExists -and (Test-Path -Path (Join-Path $sourceRoot ".git"))) {
        $branch = "unknown"
        $latestTag = "none"
        try {
            Push-Location $sourceRoot
            $branch = (git rev-parse --abbrev-ref HEAD 2>$null)
            $tag = (git tag --sort=-creatordate | Select-Object -First 1)
            if (-not [string]::IsNullOrWhiteSpace([string]$tag)) {
                $latestTag = [string]$tag
            }
            Pop-Location
        }
        catch {
            Pop-Location
        }

        $git = [pscustomobject]@{
            repository = $true
            branch = [string]$branch
            latest_tag = [string]$latestTag
        }
    }

    $checks = [pscustomobject]@{
        path_exists = [bool]$pathExists
        critical_docs_present = [bool]$docsPresent
        verification_command_identified = [bool]$verificationCommandIdentified
        suggested_command_available = [bool]$commandAvailable
    }

    $strictPass = (
        $checks.path_exists -and
        $checks.critical_docs_present -and
        $checks.verification_command_identified -and
        $checks.suggested_command_available
    )

    $degradedPass = (
        $checks.path_exists -and
        $checks.critical_docs_present -and
        $checks.verification_command_identified
    )

    $results += [pscustomobject]@{
        project_id = $projectId
        project_name = $projectName
        release_tag = $releaseTag
        source_root = $sourceRoot
        required_checks = $checks
        pass_required_gate = [bool]$strictPass
        pass_degraded_gate = [bool]$degradedPass
        command_checks = @($commandChecks)
        critical_docs = @($docChecks)
        git = $git
        task_id = [string]$task.task_id
    }
}

$strictPassCount = @($results | Where-Object { [bool]$_.pass_required_gate }).Count
$degradedPassCount = @($results | Where-Object { [bool]$_.pass_degraded_gate }).Count
$total = @($results).Count

$output = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = "tod-agentmim-local-verification-v1"
    summary = [pscustomobject]@{
        total_projects = $total
        strict_gate_passed = $strictPassCount
        strict_gate_failed = ($total - $strictPassCount)
        degraded_gate_passed = $degradedPassCount
        degraded_gate_failed = ($total - $degradedPassCount)
        strict_live_update_ready = ($strictPassCount -eq $total)
        degraded_live_update_ready = ($degradedPassCount -eq $total)
        required_gate_passed = $strictPassCount
        required_gate_failed = ($total - $strictPassCount)
        live_update_ready = ($strictPassCount -eq $total)
    }
    results = @($results)
}

$outputDir = Split-Path -Parent $resolvedOutputPath
if (-not (Test-Path -Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$output | ConvertTo-Json -Depth 20 | Set-Content -Path $resolvedOutputPath

if ($EmitJson) {
    $output | ConvertTo-Json -Depth 12 | Write-Output
}
else {
    $output
}
