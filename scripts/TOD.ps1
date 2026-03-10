param(
    [Parameter(Mandatory = $true)]
    [ValidateSet(
        "init",
        "ping-mim",
        "new-objective",
        "list-objectives",
        "add-task",
        "list-tasks",
        "package-task",
        "add-result",
        "review-task",
        "show-journal"
    )]
    [string]$Action,

    [string]$ObjectiveId,
    [string]$TaskId,
    [string]$Title,
    [string]$Description,
    [ValidateSet("low", "medium", "high", "critical")]
    [string]$Priority = "medium",
    [string]$Constraints,
    [string]$SuccessCriteria,
    [string]$Type = "implementation",
    [string]$Scope,
    [string]$Dependencies,
    [string]$AcceptanceCriteria,
    [string]$AssignedExecutor = "codex",
    [string]$Summary,
    [string]$FilesChanged,
    [string]$TestsRun,
    [string]$TestResults,
    [string]$Failures,
    [string]$Recommendations,
    [ValidateSet("pass", "revise", "escalate")]
    [string]$Decision,
    [string]$Rationale,
    [string]$UnresolvedIssues,
    [switch]$ScopeDrift,
    [int]$Top = 25,
    [string]$ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$statePath = Join-Path $repoRoot "tod/data/state.json"
$configPath = if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    Join-Path $repoRoot "tod/config/tod-config.json"
}
else {
    $ConfigPath
}
$templatePath = Join-Path $repoRoot "tod/templates/codex-task-prompt.md"
$promptOutDir = Join-Path $repoRoot "tod/out/prompts"
$mimClientPath = Join-Path $repoRoot "client/mim_api_client.ps1"

if (Test-Path -Path $mimClientPath) {
    . $mimClientPath
}

function Get-UtcNow {
    return (Get-Date).ToUniversalTime().ToString("o")
}

function Assert-Exists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if (-not (Test-Path -Path $Path)) {
        throw "$Name not found at $Path"
    }
}

function Load-State {
    Assert-Exists -Path $statePath -Name "State file"
    $raw = Get-Content -Path $statePath -Raw
    $state = $raw | ConvertFrom-Json
    Normalize-State -State $state
    return $state
}

function Save-State {
    param([Parameter(Mandatory = $true)]$State)
    Normalize-State -State $State
    $json = $State | ConvertTo-Json -Depth 12
    Set-Content -Path $statePath -Value $json
}

function Convert-ToStringArray {
    param($Value)

    if ($null -eq $Value) {
        return ,([string[]]@())
    }

    if ($Value -is [string]) {
        if ([string]::IsNullOrWhiteSpace($Value)) {
            return ,([string[]]@())
        }
        return ,([string[]]@($Value))
    }

    $items = @($Value | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    return ,([string[]]$items)
}

function Normalize-State {
    param([Parameter(Mandatory = $true)]$State)

    foreach ($objective in @($State.objectives)) {
        $objective.constraints = Convert-ToStringArray -Value $objective.constraints
        $objective.success_criteria = Convert-ToStringArray -Value $objective.success_criteria
    }

    foreach ($task in @($State.tasks)) {
        $task.dependencies = Convert-ToStringArray -Value $task.dependencies
        $task.acceptance_criteria = Convert-ToStringArray -Value $task.acceptance_criteria
    }

    foreach ($result in @($State.execution_results)) {
        $result.files_changed = Convert-ToStringArray -Value $result.files_changed
        $result.tests_run = Convert-ToStringArray -Value $result.tests_run
        $result.test_results = Convert-ToStringArray -Value $result.test_results
        $result.failures = Convert-ToStringArray -Value $result.failures
        $result.recommendations = Convert-ToStringArray -Value $result.recommendations
    }

    foreach ($review in @($State.review_decisions)) {
        $review.unresolved_issues = Convert-ToStringArray -Value $review.unresolved_issues
    }
}

function New-Id {
    param(
        [Parameter(Mandatory = $true)][string]$Prefix,
        [Parameter(Mandatory = $true)][int]$Count
    )

    return "{0}-{1}" -f $Prefix, (($Count + 1).ToString("0000"))
}

function Add-Journal {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][string]$Actor,
        [Parameter(Mandatory = $true)][string]$ActionName,
        [Parameter(Mandatory = $true)][string]$EntityType,
        [Parameter(Mandatory = $true)][string]$EntityId,
        [Parameter(Mandatory = $true)]$Payload
    )

    $entryId = New-Id -Prefix "JRNL" -Count $State.journal.Count
    $entry = [pscustomobject]@{
        id = $entryId
        actor = $Actor
        action = $ActionName
        entity_type = $EntityType
        entity_id = $EntityId
        payload = $Payload
        created_at = Get-UtcNow
    }
    $State.journal += $entry
}

function Split-List {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ,([string[]]@())
    }

    $items = @($Value.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    return ,([string[]]$items)
}

function Load-TodConfig {
    if (-not (Test-Path -Path $configPath)) {
        return [pscustomobject]@{
            mim_base_url = "http://192.168.1.120:8000"
            mode = "hybrid"
            timeout_seconds = 15
            fallback_to_local = $true
        }
    }

    $raw = Get-Content -Path $configPath -Raw
    $cfg = $raw | ConvertFrom-Json
    if ([string]::IsNullOrWhiteSpace($cfg.mode)) { $cfg.mode = "hybrid" }
    if (-not $cfg.timeout_seconds) { $cfg.timeout_seconds = 15 }
    if ($null -eq $cfg.fallback_to_local) { $cfg.fallback_to_local = $true }
    return $cfg
}

function Use-Remote {
    param([Parameter(Mandatory = $true)]$Config)
    return @("remote", "hybrid") -contains ([string]$Config.mode).ToLowerInvariant()
}

function Use-Local {
    param([Parameter(Mandatory = $true)]$Config)
    return @("local", "hybrid") -contains ([string]$Config.mode).ToLowerInvariant()
}

function Invoke-MimSafely {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][scriptblock]$ApiCall,
        [string]$Operation = "MIM API call"
    )

    try {
        return & $ApiCall
    }
    catch {
        if (([string]$Config.mode).ToLowerInvariant() -eq "hybrid" -and [bool]$Config.fallback_to_local) {
            Write-Warning "$Operation failed against MIM, falling back to local state. Error: $($_.Exception.Message)"
            return $null
        }

        throw "$Operation failed against MIM. Error: $($_.Exception.Message)"
    }
}

function Try-ParseInt {
    param([string]$Value)

    $parsed = 0
    if ([int]::TryParse($Value, [ref]$parsed)) {
        return $parsed
    }
    return $null
}

function Resolve-RemoteObjectiveId {
    param(
        [string]$ObjectiveId,
        $State
    )

    $direct = Try-ParseInt -Value $ObjectiveId
    if ($null -ne $direct) { return $direct }

    if ($null -eq $State) { return $null }
    $objective = $State.objectives | Where-Object { $_.id -eq $ObjectiveId } | Select-Object -First 1
    if ($null -eq $objective) { return $null }

    if ($objective.PSObject.Properties["remote_objective_id"]) {
        return Try-ParseInt -Value ([string]$objective.remote_objective_id)
    }
    return $null
}

function Resolve-RemoteTaskId {
    param(
        [string]$TaskId,
        $State
    )

    $direct = Try-ParseInt -Value $TaskId
    if ($null -ne $direct) { return $direct }

    if ($null -eq $State) { return $null }
    $task = $State.tasks | Where-Object { $_.id -eq $TaskId } | Select-Object -First 1
    if ($null -eq $task) { return $null }

    if ($task.PSObject.Properties["remote_task_id"]) {
        return Try-ParseInt -Value ([string]$task.remote_task_id)
    }
    return $null
}

if ($Action -eq "init") {
    if (-not (Test-Path -Path (Split-Path -Parent $statePath))) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $statePath) -Force | Out-Null
    }
    if (-not (Test-Path -Path $statePath)) {
        @{
            objectives = @()
            tasks = @()
            execution_results = @()
            review_decisions = @()
            journal = @()
        } | ConvertTo-Json -Depth 6 | Set-Content -Path $statePath
    }
    if (-not (Test-Path -Path $promptOutDir)) {
        New-Item -ItemType Directory -Path $promptOutDir -Force | Out-Null
    }
    if (-not (Test-Path -Path (Split-Path -Parent $configPath))) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $configPath) -Force | Out-Null
    }
    if (-not (Test-Path -Path $configPath)) {
        @{
            mim_base_url = "http://192.168.1.120:8000"
            mode = "hybrid"
            timeout_seconds = 15
            fallback_to_local = $true
        } | ConvertTo-Json -Depth 6 | Set-Content -Path $configPath
    }
    Write-Host "TOD initialized." -ForegroundColor Green
    return
}

$state = Load-State
$config = Load-TodConfig

if ((Use-Remote -Config $config) -and -not (Get-Command -Name Get-MimHealth -ErrorAction SilentlyContinue)) {
    throw "MIM client functions are unavailable. Ensure client/mim_api_client.ps1 exists."
}

switch ($Action) {
    "ping-mim" {
        if (-not (Use-Remote -Config $config)) {
            throw "ping-mim requires mode 'remote' or 'hybrid' in tod/config/tod-config.json"
        }

        $start = Get-Date
        $health = Invoke-MimSafely -Config $config -Operation "GET /health" -ApiCall {
            Get-MimHealth -BaseUrl $config.mim_base_url -TimeoutSeconds ([int]$config.timeout_seconds)
        }
        $status = Invoke-MimSafely -Config $config -Operation "GET /status" -ApiCall {
            Get-MimStatus -BaseUrl $config.mim_base_url -TimeoutSeconds ([int]$config.timeout_seconds)
        }
        $elapsedMs = [int]((Get-Date) - $start).TotalMilliseconds

        if ($null -eq $health -or $null -eq $status) {
            throw "MIM is not reachable and fallback is not applicable for ping-mim."
        }

        [pscustomobject]@{
            base_url = $config.mim_base_url
            mode = $config.mode
            reachable = $true
            elapsed_ms = $elapsedMs
            health = $health
            status = $status
        } | ConvertTo-Json -Depth 10
    }

    "new-objective" {
        if ([string]::IsNullOrWhiteSpace($Title)) { throw "-Title is required" }
        if ([string]::IsNullOrWhiteSpace($Description)) { throw "-Description is required" }
        if ([string]::IsNullOrWhiteSpace($SuccessCriteria)) { throw "-SuccessCriteria is required" }

        $id = New-Id -Prefix "OBJ" -Count $state.objectives.Count
        $obj = [pscustomobject]@{
            id = $id
            title = $Title
            description = $Description
            priority = $Priority
            constraints = [string[]](Split-List -Value $Constraints)
            success_criteria = [string[]](Split-List -Value $SuccessCriteria)
            status = "open"
            created_at = Get-UtcNow
            updated_at = Get-UtcNow
        }

        $remoteCreated = $null
        if (Use-Remote -Config $config) {
            $remoteCreated = Invoke-MimSafely -Config $config -Operation "POST /objectives" -ApiCall {
                New-MimObjective -BaseUrl $config.mim_base_url -TimeoutSeconds ([int]$config.timeout_seconds) -Objective $obj
            }
        }

        if ($remoteCreated -and $remoteCreated.PSObject.Properties["objective_id"]) {
            $obj.id = [string]$remoteCreated.objective_id
            if ($remoteCreated.PSObject.Properties["status"]) {
                $obj.status = [string]$remoteCreated.status
            }
            if ($remoteCreated.PSObject.Properties["created_at"] -and -not [string]::IsNullOrWhiteSpace([string]$remoteCreated.created_at)) {
                $obj.created_at = [string]$remoteCreated.created_at
            }
            $obj.updated_at = Get-UtcNow
            $obj | Add-Member -NotePropertyName remote_objective_id -NotePropertyValue ([string]$remoteCreated.objective_id) -Force
        }

        $persistLocal = (Use-Local -Config $config)
        if ((([string]$config.mode).ToLowerInvariant() -eq "hybrid") -and $null -eq $remoteCreated -and -not [bool]$config.fallback_to_local) {
            throw "MIM objective creation failed and fallback_to_local=false."
        }

        if ($persistLocal) {
            $state.objectives += $obj
            $journalAction = if ($remoteCreated) { "create_objective_remote_cached" } else { "create_objective" }
            Add-Journal -State $state -Actor "user" -ActionName $journalAction -EntityType "objective" -EntityId ([string]$obj.id) -Payload $obj
            Save-State -State $state
        }

        if (Use-Local -Config $config) {
            if ($remoteCreated) {
                [pscustomobject]@{
                    mode = $config.mode
                    local = $obj
                    remote = $remoteCreated
                } | ConvertTo-Json -Depth 12
            }
            else {
                $obj | ConvertTo-Json -Depth 8
            }
        }
        else {
            $remoteCreated | ConvertTo-Json -Depth 12
        }
    }

    "list-objectives" {
        if (Use-Remote -Config $config) {
            $remoteObjectives = Invoke-MimSafely -Config $config -Operation "GET /objectives" -ApiCall {
                Get-MimObjectives -BaseUrl $config.mim_base_url -TimeoutSeconds ([int]$config.timeout_seconds)
            }

            if ($null -ne $remoteObjectives) {
                $remoteObjectives | ConvertTo-Json -Depth 12
                break
            }
        }

        $state.objectives | Select-Object id, title, priority, status, updated_at | Format-Table -AutoSize
    }

    "add-task" {
        if ([string]::IsNullOrWhiteSpace($ObjectiveId)) { throw "-ObjectiveId is required" }
        if ([string]::IsNullOrWhiteSpace($Title)) { throw "-Title is required" }
        if ([string]::IsNullOrWhiteSpace($Scope)) { throw "-Scope is required" }
        if ([string]::IsNullOrWhiteSpace($AcceptanceCriteria)) { throw "-AcceptanceCriteria is required" }

        if (Use-Local -Config $config) {
            $objective = $state.objectives | Where-Object { $_.id -eq $ObjectiveId } | Select-Object -First 1
            if (-not $objective) { throw "Objective not found: $ObjectiveId" }
        }

        $id = New-Id -Prefix "TSK" -Count $state.tasks.Count
        $task = [pscustomobject]@{
            id = $id
            objective_id = $ObjectiveId
            title = $Title
            type = $Type
            scope = $Scope
            dependencies = [string[]](Split-List -Value $Dependencies)
            acceptance_criteria = [string[]](Split-List -Value $AcceptanceCriteria)
            status = "planned"
            assigned_executor = $AssignedExecutor
            created_at = Get-UtcNow
            updated_at = Get-UtcNow
        }

        $remoteCreated = $null
        $remoteObjectiveId = $null
        if (Use-Remote -Config $config) {
            $remoteObjectiveId = Resolve-RemoteObjectiveId -ObjectiveId $ObjectiveId -State $state
            $remoteCreated = Invoke-MimSafely -Config $config -Operation "POST /tasks" -ApiCall {
                New-MimTask -BaseUrl $config.mim_base_url -TimeoutSeconds ([int]$config.timeout_seconds) -Task $task -RemoteObjectiveId $remoteObjectiveId
            }
        }

        if ($remoteCreated -and $remoteCreated.PSObject.Properties["task_id"]) {
            $task.id = [string]$remoteCreated.task_id
            if ($null -ne $remoteObjectiveId) {
                $task.objective_id = [string]$remoteObjectiveId
            }
            if ($remoteCreated.PSObject.Properties["status"]) {
                $task.status = [string]$remoteCreated.status
            }
            $task.updated_at = Get-UtcNow
            $task | Add-Member -NotePropertyName remote_task_id -NotePropertyValue ([string]$remoteCreated.task_id) -Force
        }

        if ((Use-Local -Config $config) -or ((([string]$config.mode).ToLowerInvariant() -eq "hybrid") -and $null -eq $remoteCreated -and [bool]$config.fallback_to_local)) {
            $state.tasks += $task
            $journalAction = if ($remoteCreated) { "add_task_remote_cached" } else { "add_task" }
            Add-Journal -State $state -Actor "tod" -ActionName $journalAction -EntityType "task" -EntityId ([string]$task.id) -Payload $task
            Save-State -State $state
        }

        if (Use-Local -Config $config) {
            if ($remoteCreated) {
                [pscustomobject]@{
                    mode = $config.mode
                    local = $task
                    remote = $remoteCreated
                } | ConvertTo-Json -Depth 12
            }
            else {
                $task | ConvertTo-Json -Depth 8
            }
        }
        else {
            $remoteCreated | ConvertTo-Json -Depth 12
        }
    }

    "list-tasks" {
        if (Use-Remote -Config $config) {
            $remoteTasks = Invoke-MimSafely -Config $config -Operation "GET /tasks" -ApiCall {
                Get-MimTasks -BaseUrl $config.mim_base_url -ObjectiveId $ObjectiveId -TimeoutSeconds ([int]$config.timeout_seconds)
            }

            if ($null -ne $remoteTasks) {
                $remoteTasks | ConvertTo-Json -Depth 12
                break
            }
        }

        $tasks = $state.tasks
        if (-not [string]::IsNullOrWhiteSpace($ObjectiveId)) {
            $tasks = $tasks | Where-Object { $_.objective_id -eq $ObjectiveId }
        }
        $tasks | Select-Object id, objective_id, title, type, status, assigned_executor, updated_at | Format-Table -AutoSize
    }

    "package-task" {
        if ([string]::IsNullOrWhiteSpace($TaskId)) { throw "-TaskId is required" }
        Assert-Exists -Path $templatePath -Name "Prompt template"

        $task = $state.tasks | Where-Object { $_.id -eq $TaskId } | Select-Object -First 1
        if (-not $task) { throw "Task not found: $TaskId" }

        $objective = $state.objectives | Where-Object { $_.id -eq $task.objective_id } | Select-Object -First 1
        if (-not $objective) { throw "Objective not found for task: $($task.objective_id)" }

        $template = Get-Content -Path $templatePath -Raw
        $rendered = $template
        $rendered = $rendered.Replace("{{OBJECTIVE_ID}}", [string]$objective.id)
        $rendered = $rendered.Replace("{{OBJECTIVE_TITLE}}", [string]$objective.title)
        $rendered = $rendered.Replace("{{OBJECTIVE_DESCRIPTION}}", [string]$objective.description)
        $rendered = $rendered.Replace("{{OBJECTIVE_PRIORITY}}", [string]$objective.priority)
        $rendered = $rendered.Replace("{{OBJECTIVE_CONSTRAINTS}}", (($objective.constraints) -join ", "))
        $rendered = $rendered.Replace("{{OBJECTIVE_SUCCESS_CRITERIA}}", (($objective.success_criteria) -join ", "))
        $rendered = $rendered.Replace("{{TASK_ID}}", [string]$task.id)
        $rendered = $rendered.Replace("{{TASK_TITLE}}", [string]$task.title)
        $rendered = $rendered.Replace("{{TASK_TYPE}}", [string]$task.type)
        $rendered = $rendered.Replace("{{TASK_SCOPE}}", [string]$task.scope)
        $rendered = $rendered.Replace("{{TASK_DEPENDENCIES}}", (($task.dependencies) -join ", "))
        $rendered = $rendered.Replace("{{TASK_ACCEPTANCE_CRITERIA}}", (($task.acceptance_criteria) -join ", "))
        $rendered = $rendered.Replace("{{TASK_ASSIGNED_EXECUTOR}}", [string]$task.assigned_executor)

        if (-not (Test-Path -Path $promptOutDir)) {
            New-Item -ItemType Directory -Path $promptOutDir -Force | Out-Null
        }

        $outPath = Join-Path $promptOutDir ("{0}.md" -f $TaskId)
        Set-Content -Path $outPath -Value $rendered

        $task.status = "packaged"
        $task.updated_at = Get-UtcNow
        Add-Journal -State $state -Actor "tod" -ActionName "package_task" -EntityType "task" -EntityId $TaskId -Payload @{ prompt_path = $outPath }
        Save-State -State $state
        Write-Host "Packaged task prompt: $outPath" -ForegroundColor Green
    }

    "add-result" {
        if ([string]::IsNullOrWhiteSpace($TaskId)) { throw "-TaskId is required" }
        if ([string]::IsNullOrWhiteSpace($Summary)) { throw "-Summary is required" }

        $task = $null
        if (Use-Local -Config $config) {
            $task = $state.tasks | Where-Object { $_.id -eq $TaskId } | Select-Object -First 1
            if (-not $task) { throw "Task not found: $TaskId" }
        }

        $resultId = New-Id -Prefix "RES" -Count $state.execution_results.Count
        $result = [pscustomobject]@{
            id = $resultId
            task_id = $TaskId
            summary = $Summary
            files_changed = [string[]](Split-List -Value $FilesChanged)
            tests_run = [string[]](Split-List -Value $TestsRun)
            test_results = [string[]](Split-List -Value $TestResults)
            failures = [string[]](Split-List -Value $Failures)
            recommendations = [string[]](Split-List -Value $Recommendations)
            created_at = Get-UtcNow
        }

        $remoteCreated = $null
        if (Use-Remote -Config $config) {
            $remoteTaskId = Resolve-RemoteTaskId -TaskId $TaskId -State $state
            if ($null -ne $remoteTaskId) {
                $remoteCreated = Invoke-MimSafely -Config $config -Operation "POST /results" -ApiCall {
                    New-MimResult -BaseUrl $config.mim_base_url -TimeoutSeconds ([int]$config.timeout_seconds) -Result $result -RemoteTaskId $remoteTaskId
                }
            }
            elseif (([string]$config.mode).ToLowerInvariant() -eq "remote") {
                throw "Cannot submit result to MIM without a remote integer task ID for task '$TaskId'."
            }
            else {
                Write-Warning "Skipping remote result submission because no remote task ID is available for task '$TaskId'."
            }
        }

        if ($remoteCreated -and $remoteCreated.PSObject.Properties["result_id"]) {
            $result.id = [string]$remoteCreated.result_id
            $result.task_id = [string]$remoteTaskId
            if ($remoteCreated.PSObject.Properties["created_at"] -and -not [string]::IsNullOrWhiteSpace([string]$remoteCreated.created_at)) {
                $result.created_at = [string]$remoteCreated.created_at
            }
        }

        if ((Use-Local -Config $config) -or ((([string]$config.mode).ToLowerInvariant() -eq "hybrid") -and $null -eq $remoteCreated -and [bool]$config.fallback_to_local)) {
            $state.execution_results += $result
            if ($task) {
                if ($remoteCreated -and $remoteCreated.PSObject.Properties["task_id"]) {
                    $task.id = [string]$remoteCreated.task_id
                }
                $task.status = if ($remoteCreated -and $remoteCreated.PSObject.Properties["status"]) { [string]$remoteCreated.status } else { "implemented" }
                $task.updated_at = Get-UtcNow
            }
            $journalAction = if ($remoteCreated) { "add_result_remote_cached" } else { "add_result" }
            Add-Journal -State $state -Actor "codex" -ActionName $journalAction -EntityType "execution_result" -EntityId ([string]$result.id) -Payload $result
            Save-State -State $state
        }

        if (Use-Local -Config $config) {
            if ($remoteCreated) {
                [pscustomobject]@{
                    mode = $config.mode
                    local = $result
                    remote = $remoteCreated
                } | ConvertTo-Json -Depth 12
            }
            else {
                $result | ConvertTo-Json -Depth 8
            }
        }
        else {
            $remoteCreated | ConvertTo-Json -Depth 12
        }
    }

    "review-task" {
        if ([string]::IsNullOrWhiteSpace($TaskId)) { throw "-TaskId is required" }
        if ([string]::IsNullOrWhiteSpace($Decision)) { throw "-Decision is required" }
        if ([string]::IsNullOrWhiteSpace($Rationale)) { throw "-Rationale is required" }

        $task = $null
        if (Use-Local -Config $config) {
            $task = $state.tasks | Where-Object { $_.id -eq $TaskId } | Select-Object -First 1
            if (-not $task) { throw "Task not found: $TaskId" }
        }

        $reviewId = New-Id -Prefix "REV" -Count $state.review_decisions.Count
        $review = [pscustomobject]@{
            id = $reviewId
            task_id = $TaskId
            decision = $Decision
            rationale = $Rationale
            unresolved_issues = [string[]](Split-List -Value $UnresolvedIssues)
            scope_drift_detected = [bool]$ScopeDrift
            created_at = Get-UtcNow
        }

        $remoteCreated = $null
        if (Use-Remote -Config $config) {
            $remoteTaskId = Resolve-RemoteTaskId -TaskId $TaskId -State $state
            if ($null -ne $remoteTaskId) {
                $remoteCreated = Invoke-MimSafely -Config $config -Operation "POST /reviews" -ApiCall {
                    New-MimReview -BaseUrl $config.mim_base_url -TimeoutSeconds ([int]$config.timeout_seconds) -Review $review -RemoteTaskId $remoteTaskId
                }
            }
            elseif (([string]$config.mode).ToLowerInvariant() -eq "remote") {
                throw "Cannot submit review to MIM without a remote integer task ID for task '$TaskId'."
            }
            else {
                Write-Warning "Skipping remote review submission because no remote task ID is available for task '$TaskId'."
            }
        }

        if ($remoteCreated -and $remoteCreated.PSObject.Properties["review_id"]) {
            $review.id = [string]$remoteCreated.review_id
            $review.task_id = [string]$remoteTaskId
            if ($remoteCreated.PSObject.Properties["created_at"] -and -not [string]::IsNullOrWhiteSpace([string]$remoteCreated.created_at)) {
                $review.created_at = [string]$remoteCreated.created_at
            }
        }

        if ((Use-Local -Config $config) -or ((([string]$config.mode).ToLowerInvariant() -eq "hybrid") -and $null -eq $remoteCreated -and [bool]$config.fallback_to_local)) {
            if ($task) {
                $task.status = if ($remoteCreated -and $remoteCreated.PSObject.Properties["decision"]) { [string]$remoteCreated.decision } else {
                    switch ($Decision) {
                        "pass" { "reviewed_pass" }
                        "revise" { "needs_revision" }
                        "escalate" { "escalated" }
                    }
                }
                $task.updated_at = Get-UtcNow
            }

            $state.review_decisions += $review
            $journalAction = if ($remoteCreated) { "review_task_remote_cached" } else { "review_task" }
            Add-Journal -State $state -Actor "tod" -ActionName $journalAction -EntityType "review_decision" -EntityId ([string]$review.id) -Payload $review
            Save-State -State $state
        }

        if (Use-Local -Config $config) {
            if ($remoteCreated) {
                [pscustomobject]@{
                    mode = $config.mode
                    local = $review
                    remote = $remoteCreated
                } | ConvertTo-Json -Depth 12
            }
            else {
                $review | ConvertTo-Json -Depth 8
            }
        }
        else {
            $remoteCreated | ConvertTo-Json -Depth 12
        }
    }

    "show-journal" {
        if (Use-Remote -Config $config) {
            $remoteJournal = Invoke-MimSafely -Config $config -Operation "GET /journal" -ApiCall {
                Get-MimJournal -BaseUrl $config.mim_base_url -Top $Top -TimeoutSeconds ([int]$config.timeout_seconds)
            }

            if ($null -ne $remoteJournal) {
                $remoteJournal | ConvertTo-Json -Depth 12
                break
            }
        }

        $state.journal |
            Sort-Object -Property created_at -Descending |
            Select-Object -First $Top id, created_at, actor, action, entity_type, entity_id |
            Format-Table -AutoSize
    }

    default {
        throw "Unsupported action: $Action"
    }
}
