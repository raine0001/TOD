param(
    [string]$BriefIndexPath = "shared_state/MIM_TOD_PROJECT_BRIEFS_INDEX.latest.json",
    [string]$ProjectRegistryPath = "tod/config/project-registry.json",
    [string]$ProjectPriorityPath = "tod/config/project-priority.json",
    [string]$OutputRoot = "shared_state/agentmim",
    [switch]$EmitJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

function Resolve-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return $PathValue
    }

    return (Join-Path $repoRoot $PathValue)
}

function Get-JsonFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -Path $Path)) {
        throw "JSON file not found: $Path"
    }
    return (Get-Content -Path $Path -Raw | ConvertFrom-Json)
}

function Read-ProjectBrief {
    param([Parameter(Mandatory = $true)][string]$RuntimeBriefPath)

    $resolved = Resolve-LocalPath -PathValue $RuntimeBriefPath
    return Get-JsonFile -Path $resolved
}

function Get-JsonFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -Path $Path)) {
        throw "JSON file not found: $Path"
    }
    return (Get-Content -Path $Path -Raw | ConvertFrom-Json)
}

function To-Array {
    param($Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Array]) { return @($Value) }
    return @($Value)
}

function Find-RegistryProject {
    param(
        [Parameter(Mandatory = $true)]$Projects,
        [Parameter(Mandatory = $true)][string]$ProjectId,
        [Parameter(Mandatory = $true)][string]$ProjectName
    )

    $idLower = $ProjectId.ToLowerInvariant()
    $nameLower = $ProjectName.ToLowerInvariant()

    $match = @($Projects | Where-Object {
        ([string]$_.id).ToLowerInvariant() -eq $idLower -or
        ([string]$_.name).ToLowerInvariant() -eq $nameLower
    }) | Select-Object -First 1

    return $match
}

function Get-FallbackVerificationCommands {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectId,
        [Parameter(Mandatory = $true)][string]$SourceRoot
    )

    $fallback = @()
    $root = $SourceRoot

    if ([string]::IsNullOrWhiteSpace($root) -or -not (Test-Path -Path $root)) {
        return @($fallback)
    }

    switch ($ProjectId.ToLowerInvariant()) {
        "mim_arm" {
            if (Test-Path -Path (Join-Path $root "MIM_arm.py")) {
                $fallback += "python -m py_compile MIM_arm.py"
            }
        }
        "mimrobots.com" {
            if (Test-Path -Path (Join-Path $root "run.py")) {
                $fallback += "python -m py_compile run.py"
            }
        }
        default {
            if (Test-Path -Path (Join-Path $root "requirements.txt")) {
                $fallback += "python -m pytest --collect-only"
            }
        }
    }

    return @($fallback)
}

function Get-PreferredVerificationCommands {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectId,
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        $RegistryCommands
    )

    $commands = @()
    $id = $ProjectId.ToLowerInvariant()

    switch ($id) {
        "viasion" { $commands += "npm run test:e2e -- --list" }
        "mim_pulz" { $commands += "python -m pytest --collect-only" }
        "coachmim" { $commands += "python -m pytest --collect-only" }
        "comm_app" {
            $verificationScript = [System.IO.Path]::GetFullPath((Join-Path $repoRoot "scripts/Invoke-TODCommAppVerification.ps1"))
            $commands += ('powershell -NoProfile -ExecutionPolicy Bypass -File "{0}" -ProjectRoot "{1}"' -f $verificationScript, $SourceRoot)
            $commands += "python -m pytest --collect-only"
        }
        "mim_arm" { $commands += "python -m py_compile MIM_arm.py" }
        "mimrobots.com" { $commands += "python -m py_compile run.py" }
    }

    if (@($commands).Count -eq 0) {
        $commands += To-Array -Value $RegistryCommands
    }

    if (@($commands).Count -eq 0) {
        $commands = Get-FallbackVerificationCommands -ProjectId $ProjectId -SourceRoot $SourceRoot
    }

    return @($commands)
}

function Get-ExecutionModeForProject {
    param(
        [Parameter(Mandatory = $true)]$Priority,
        [Parameter(Mandatory = $true)][string]$ProjectId
    )

    $match = @((To-Array -Value $Priority.execution_order) | Where-Object {
        ([string]$_.project_id).ToLowerInvariant() -eq $ProjectId.ToLowerInvariant()
    }) | Select-Object -First 1

    if ($null -ne $match -and $match.PSObject.Properties['mode']) {
        return [string]$match.mode
    }

    return 'advisory-first'
}

function Get-ProjectFollowUpCommands {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectId,
        [Parameter(Mandatory = $true)][string]$SourceRoot
    )

    $commands = @()

    if (-not [string]::IsNullOrWhiteSpace($SourceRoot)) {
        $managedWorkScript = [System.IO.Path]::GetFullPath((Join-Path $repoRoot 'scripts/Invoke-TODProjectManagedWork.ps1'))
        $commands += ('powershell -NoProfile -ExecutionPolicy Bypass -File "{0}" -ProjectId "{1}" -ProjectRoot "{2}"' -f $managedWorkScript, $ProjectId, $SourceRoot)
    }

    return @($commands)
}

function Get-ProjectAdvisoryCommands {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectId,
        [Parameter(Mandatory = $true)][string]$SourceRoot
    )

    $commands = @()

    switch ($ProjectId.ToLowerInvariant()) {
        'comm_app' {
            $qaScript = [System.IO.Path]::GetFullPath((Join-Path $repoRoot 'scripts/Invoke-TODCommAppSpokespersonQAGate.ps1'))
            $commands += ('powershell -NoProfile -ExecutionPolicy Bypass -File "{0}" -ProjectRoot "{1}" -Runs 1 -Duration 6' -f $qaScript, $SourceRoot)
        }
    }

    return @($commands)
}

function Build-TaskQueue {
    param(
        [Parameter(Mandatory = $true)]$BriefIndex,
        [Parameter(Mandatory = $true)]$Registry,
        [Parameter(Mandatory = $true)]$Priority
    )

    $tasks = @()
    $queueCounter = 1

    foreach ($projectRef in (To-Array -Value $BriefIndex.projects)) {
        $runtimeBrief = Read-ProjectBrief -RuntimeBriefPath ([string]$projectRef.runtime_brief)
        $registryProject = Find-RegistryProject -Projects (To-Array -Value $Registry.projects) -ProjectId ([string]$runtimeBrief.project_id) -ProjectName ([string]$runtimeBrief.project_name)
        $testCommands = if ($null -ne $registryProject -and $registryProject.PSObject.Properties["test_commands"]) { To-Array -Value $registryProject.test_commands } else { @() }

        $sourceRoot = [string]$runtimeBrief.source_root
        $projectId = [string]$runtimeBrief.project_id
        $projectName = [string]$runtimeBrief.project_name
        $releaseTag = [string]$runtimeBrief.current_release_tag
        $executionMode = Get-ExecutionModeForProject -Priority $Priority -ProjectId $projectId

        $testCommands = Get-PreferredVerificationCommands -ProjectId $projectId -SourceRoot $sourceRoot -RegistryCommands $testCommands

        $tasks += [pscustomobject]@{
            queue_position = $queueCounter
            task_id = ("agentmim-local-verify-{0}" -f $projectId)
            project_id = $projectId
            project_name = $projectName
            category = "local-verification"
            status = "pending"
            objective = "Verify a local working test copy before live updates."
            acceptance_criteria = @(
                "Project path exists and is readable.",
                "Critical docs listed in runtime brief are present.",
                "At least one local verification command is identified.",
                "Result captured in AgentMIM execution log."
            )
            suggested_commands = @($testCommands)
            local_copy_contract = [pscustomobject]@{
                mode = "test-copy-first"
                live_writes_blocked = $true
                source_root = $sourceRoot
                release_tag = $releaseTag
            }
            blockers = To-Array -Value $runtimeBrief.blockers
            freshness_timestamp = [string]$runtimeBrief.freshness_timestamp
        }
        $queueCounter++

        $followUpCommands = Get-ProjectFollowUpCommands -ProjectId $projectId -SourceRoot $sourceRoot
        if (@($followUpCommands).Count -gt 0) {
            $tasks += [pscustomobject]@{
                queue_position = $queueCounter
                task_id = ("agentmim-managed-work-{0}" -f $projectId)
                project_id = $projectId
                project_name = $projectName
                category = "managed-work-cycle"
                status = "pending"
                objective = "Classify the live repo delta into TOD-managed product scope before edits."
                acceptance_criteria = @(
                    "Required local verification is already passing.",
                    "Managed product files are distinguished from QA/support artifacts.",
                    "Result captured in a TOD-managed work artifact.",
                    "Next edit scope is clear before live updates."
                )
                suggested_commands = @($followUpCommands)
                local_copy_contract = [pscustomobject]@{
                    mode = "tod-managed-triage"
                    source_root = $sourceRoot
                    release_tag = $releaseTag
                    execution_mode = $executionMode
                    goal = "Promote reusable TOD-managed project triage before edits."
                }
                freshness_timestamp = [string]$runtimeBrief.freshness_timestamp
            }
            $queueCounter++
        }

        $advisoryCommands = Get-ProjectAdvisoryCommands -ProjectId $projectId -SourceRoot $sourceRoot
        if (@($advisoryCommands).Count -gt 0) {
            $tasks += [pscustomobject]@{
                queue_position = $queueCounter
                task_id = ("agentmim-qa-advisory-{0}" -f $projectId)
                project_id = $projectId
                project_name = $projectName
                category = "qa-advisory"
                status = "pending"
                objective = "Run non-blocking spokesperson expression QA after the managed patch scope is identified."
                acceptance_criteria = @(
                    "QA command is present and runnable from TOD.",
                    "Result is captured as an advisory artifact.",
                    "Product patch and QA/support artifacts remain distinct.",
                    "Failure does not block product verification unless policy is promoted later."
                )
                suggested_commands = @($advisoryCommands)
                local_copy_contract = [pscustomobject]@{
                    mode = "tod-managed-advisory-qa"
                    source_root = $sourceRoot
                    release_tag = $releaseTag
                    goal = "Measure expression quality without blocking the product patch gate."
                }
                freshness_timestamp = [string]$runtimeBrief.freshness_timestamp
            }
            $queueCounter++
        }

        $tasks += [pscustomobject]@{
            queue_position = $queueCounter
            task_id = ("agentmim-capability-summary-{0}" -f $projectId)
            project_id = $projectId
            project_name = $projectName
            category = "capability-capture"
            status = "pending"
            objective = "Confirm capability surface summary and coordination rules from brief artifacts."
            acceptance_criteria = @(
                "Capability map reviewed.",
                "Coordination rules reviewed.",
                "Any unknown fields flagged for clarification."
            )
            source_artifacts = @(
                [string]$projectRef.capability_map,
                [string]$projectRef.objective_brief,
                [string]$projectRef.tree_reference
            )
            freshness_timestamp = [string]$runtimeBrief.freshness_timestamp
        }
        $queueCounter++
    }

    return ,$tasks
}

$resolvedBriefIndexPath = Resolve-LocalPath -PathValue $BriefIndexPath
$resolvedProjectRegistryPath = Resolve-LocalPath -PathValue $ProjectRegistryPath
$resolvedProjectPriorityPath = Resolve-LocalPath -PathValue $ProjectPriorityPath
$resolvedOutputRoot = Resolve-LocalPath -PathValue $OutputRoot

$briefIndex = Get-JsonFile -Path $resolvedBriefIndexPath
$registry = Get-JsonFile -Path $resolvedProjectRegistryPath
$priority = Get-JsonFile -Path $resolvedProjectPriorityPath

if (-not (Test-Path -Path $resolvedOutputRoot)) {
    New-Item -ItemType Directory -Path $resolvedOutputRoot -Force | Out-Null
}

$generatedAt = (Get-Date).ToUniversalTime().ToString("o")
$queue = Build-TaskQueue -BriefIndex $briefIndex -Registry $registry -Priority $priority

$queueArtifact = [pscustomobject]@{
    generated_at = $generatedAt
    source = "tod-agentmim-starter-pack-v1"
    task_count = @($queue).Count
    task_queue = @($queue)
}

$gateArtifact = [pscustomobject]@{
    generated_at = $generatedAt
    source = "tod-agentmim-local-gate-v1"
    policy = [pscustomobject]@{
        name = "local_test_copy_before_live_updates"
        status = "active"
        live_updates_blocked_until = "all_local_verification_tasks_pass"
        gate_modes = [pscustomobject]@{
            strict = "path_exists + critical_docs_present + verification_command_identified + suggested_command_available"
            degraded = "path_exists + critical_docs_present + verification_command_identified"
        }
        required_checks = @(
            "path_exists",
            "critical_docs_present",
            "verification_command_identified",
            "result_logged"
        )
    }
    current_scope = [pscustomobject]@{
        projects = To-Array -Value $briefIndex.projects | ForEach-Object { [string]$_.project_id }
        objective = "Give TOD small real AgentMIM tasks with local verification first."
    }
    execution_order = @($queue | Where-Object { [string]$_.category -eq "local-verification" } | Select-Object -ExpandProperty task_id)
}

$summaryPath = Join-Path $resolvedOutputRoot "MIM_TOD_AGENTMIM_STARTER_SUMMARY.latest.md"
$summaryLines = @()
$summaryLines += "# AgentMIM Starter Summary"
$summaryLines += ""
$summaryLines += ("Generated: {0}" -f $generatedAt)
$summaryLines += ""
$summaryLines += "## Goal"
$summaryLines += ""
$summaryLines += "Enable small real TOD tasks in AgentMIM with a strict test-copy-first gate before live updates."
$summaryLines += ""
$summaryLines += "## Starter Queue"
$summaryLines += ""
foreach ($item in @($queue | Select-Object -First 12)) {
    $summaryLines += ("- {0} | {1} | {2}" -f [string]$item.task_id, [string]$item.project_id, [string]$item.category)
}
$summaryLines += ""
$summaryLines += "## Live Update Gate"
$summaryLines += ""
$summaryLines += "- policy: local_test_copy_before_live_updates"
$summaryLines += "- status: active"
$summaryLines += "- live updates remain blocked until local verification tasks pass"

$queuePath = Join-Path $resolvedOutputRoot "MIM_TOD_AGENT_TASK_QUEUE.latest.json"
$gatePath = Join-Path $resolvedOutputRoot "MIM_TOD_LOCAL_TEST_GATE.latest.json"

$queueArtifact | ConvertTo-Json -Depth 20 | Set-Content -Path $queuePath
$gateArtifact | ConvertTo-Json -Depth 20 | Set-Content -Path $gatePath
$summaryLines -join [Environment]::NewLine | Set-Content -Path $summaryPath

$result = [pscustomobject]@{
    ok = $true
    generated_at = $generatedAt
    output_root = $resolvedOutputRoot
    artifacts = [pscustomobject]@{
        task_queue = $queuePath
        local_test_gate = $gatePath
        starter_summary = $summaryPath
    }
    task_count = @($queue).Count
}

if ($EmitJson) {
    $result | ConvertTo-Json -Depth 12 | Write-Output
}
else {
    $result
}
