param(
    [string]$SuitePath = "tod/conversation_eval/repo_edit_test_recover_suite_v1.json",
    [string]$ProjectIndexPath = "tod/data/project-library-index.json",
    [string]$RegistryPath = "tod/config/project-registry.json",
    [string]$OutputRoot = "shared_state/conversation_eval/repo_edit_test_recover",
    [int]$MaxCandidateFiles = 4,
    [switch]$UseAssist,
    [switch]$EmitJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

function Resolve-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) { return [System.IO.Path]::GetFullPath($PathValue) }
    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $PathValue))
}

function ConvertTo-RepoPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    return (($PathValue -replace "[\\/]+", "/").Trim()).TrimStart("/")
}

function Test-PathPrefixMatch {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)][string]$Prefix
    )

    $pathNorm = (ConvertTo-RepoPath -PathValue $PathValue).ToLowerInvariant()
    $prefixNorm = (ConvertTo-RepoPath -PathValue $Prefix).ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($prefixNorm)) { return $false }
    return ($pathNorm -eq $prefixNorm -or $pathNorm.StartsWith($prefixNorm + "/"))
}

function Get-GitInfo {
    param([Parameter(Mandatory = $true)][string]$ProjectPath)

    $result = [ordered]@{
        is_repo = $false
        branch = ""
        remote_origin = ""
        status = ""
        can_publish = $false
    }

    try {
        $inside = (& git -C $ProjectPath rev-parse --is-inside-work-tree 2>$null)
        if ([string]$inside -eq "true") {
            $result.is_repo = $true
            $result.branch = [string](& git -C $ProjectPath rev-parse --abbrev-ref HEAD 2>$null)
            $result.remote_origin = [string](& git -C $ProjectPath remote get-url origin 2>$null)
            $result.status = [string](& git -C $ProjectPath status -sb 2>$null | Out-String).Trim()
            $result.can_publish = (-not [string]::IsNullOrWhiteSpace($result.remote_origin))
        }
    }
    catch {
    }

    return [pscustomobject]$result
}

function Find-CandidateFiles {
    param(
        [Parameter(Mandatory = $true)]$Project,
        [Parameter(Mandatory = $true)][string[]]$Hints,
        [int]$MaxFiles = 4
    )

    $projectRoot = [string]$Project.path
    $allowedPaths = if ($Project.boundaries -and $Project.boundaries.allowed_paths) { @($Project.boundaries.allowed_paths) } else { @() }
    $extensions = @("*.ps1", "*.py", "*.js", "*.ts", "*.tsx", "*.jsx", "*.html", "*.css", "*.md", "*.json")
    $hits = New-Object System.Collections.ArrayList

    foreach ($allowed in $allowedPaths) {
        $base = Join-Path $projectRoot ([string]$allowed)
        if (-not (Test-Path -Path $base)) { continue }
        foreach ($pattern in $extensions) {
            $files = Get-ChildItem -Path $base -Recurse -File -Filter $pattern -ErrorAction SilentlyContinue
            foreach ($file in $files) {
                $name = $file.FullName.ToLowerInvariant()
                foreach ($hint in $Hints) {
                    if ($name -like ("*" + ([string]$hint).ToLowerInvariant() + "*")) {
                        [void]$hits.Add($file.FullName)
                        break
                    }
                }
            }
        }
    }

    if ($hits.Count -eq 0) {
        foreach ($allowed in $allowedPaths) {
            $base = Join-Path $projectRoot ([string]$allowed)
            if (-not (Test-Path -Path $base)) { continue }
            $fallback = Get-ChildItem -Path $base -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -in ".ps1", ".py", ".js", ".ts", ".tsx", ".jsx", ".html", ".css", ".md", ".json" } |
                Select-Object -First $MaxFiles
            foreach ($file in $fallback) {
                [void]$hits.Add($file.FullName)
            }
            if ($hits.Count -ge $MaxFiles) { break }
        }
    }

    return @($hits | Select-Object -Unique | Select-Object -First $MaxFiles)
}

function Test-Boundaries {
    param(
        [Parameter(Mandatory = $true)]$Project,
        [string[]]$FullPaths = @()
    )

    $projectRoot = [string]$Project.path
    $allowed = if ($Project.boundaries -and $Project.boundaries.allowed_paths) { @($Project.boundaries.allowed_paths) } else { @() }
    $blocked = if ($Project.boundaries -and $Project.boundaries.blocked_paths) { @($Project.boundaries.blocked_paths) } else { @() }

    if (@($FullPaths).Count -eq 0) {
        return [pscustomobject]@{
            ok = $false
            checks = @()
        }
    }

    $checks = @()
    $ok = $true
    foreach ($fullPath in $FullPaths) {
        $relative = ConvertTo-RepoPath -PathValue ($fullPath.Substring($projectRoot.Length).TrimStart([char[]]@([char]92, [char]47)))
        $inAllowed = ($allowed.Count -eq 0)
        foreach ($allowPrefix in $allowed) {
            if (Test-PathPrefixMatch -PathValue $relative -Prefix ([string]$allowPrefix)) {
                $inAllowed = $true
                break
            }
        }
        $inBlocked = $false
        foreach ($blockedPrefix in $blocked) {
            if (Test-PathPrefixMatch -PathValue $relative -Prefix ([string]$blockedPrefix)) {
                $inBlocked = $true
                break
            }
        }
        $allowedResult = $inAllowed -and (-not $inBlocked)
        if (-not $allowedResult) { $ok = $false }
        $checks += [pscustomobject]@{
            full_path = $fullPath
            relative_path = $relative
            allowed = $allowedResult
            in_allowed_scope = $inAllowed
            in_blocked_scope = $inBlocked
        }
    }

    return [pscustomobject]@{
        ok = $ok
        checks = @($checks)
    }
}

function Get-TestCommands {
    param([Parameter(Mandatory = $true)]$Project)

    $commands = @()
    if ($Project.configured_test_commands) { $commands += @($Project.configured_test_commands) }
    elseif ($Project.test_commands) { $commands += @($Project.test_commands) }
    return @($commands | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
}

function Get-RelativeCandidateCoverage {
    param(
        [Parameter(Mandatory = $true)][string[]]$CandidateFiles,
        [Parameter(Mandatory = $true)][string]$ProjectPath,
        [string[]]$RelativePathCandidates = @()
    )

    if (@($CandidateFiles).Count -eq 0 -or @($RelativePathCandidates).Count -eq 0) {
        return $false
    }

    foreach ($fullPath in @($CandidateFiles)) {
        $relative = ConvertTo-RepoPath -PathValue ($fullPath.Substring($ProjectPath.Length).TrimStart([char[]]@([char]92, [char]47)))
        foreach ($prefix in @($RelativePathCandidates)) {
            if (Test-PathPrefixMatch -PathValue $relative -Prefix ([string]$prefix)) {
                return $true
            }
        }
    }

    return $false
}

function New-StageChecklist {
    param(
        [Parameter(Mandatory = $true)]$Scenario,
        [Parameter(Mandatory = $true)]$Project,
        [Parameter(Mandatory = $true)][string[]]$CandidateFiles,
        [Parameter(Mandatory = $true)]$Boundary,
        [Parameter(Mandatory = $true)]$GitInfo,
        [Parameter(Mandatory = $true)][string[]]$TestCommands
    )

    $inspectStage = [pscustomobject]@{
        name = 'inspect'
        ready = (@($CandidateFiles).Count -gt 0)
        evidence = if (@($CandidateFiles).Count -gt 0) { 'candidate_files_found' } else { 'candidate_files_missing' }
    }
    $understandStage = [pscustomobject]@{
        name = 'understand'
        ready = (-not [string]::IsNullOrWhiteSpace([string]$Scenario.task))
        evidence = if (-not [string]::IsNullOrWhiteSpace([string]$Scenario.task)) { 'task_present' } else { 'task_missing' }
    }
    $patchStage = [pscustomobject]@{
        name = 'patch'
        ready = ([bool]$Boundary.ok -and @($CandidateFiles).Count -gt 0)
        evidence = if ([bool]$Boundary.ok) { 'bounded_patch_scope_ready' } else { 'candidate_files_outside_allowed_scope' }
    }
    $validateStage = [pscustomobject]@{
        name = 'validate'
        ready = (@($TestCommands).Count -gt 0)
        evidence = if (@($TestCommands).Count -gt 0) { 'test_commands_present' } else { 'test_commands_missing' }
    }
    $recoverStage = [pscustomobject]@{
        name = 'recover'
        ready = ([bool]$GitInfo.is_repo -and @($Scenario.recovery_expectations).Count -gt 0)
        evidence = if ([bool]$GitInfo.is_repo -and @($Scenario.recovery_expectations).Count -gt 0) { 'recovery_plan_possible' } else { 'recovery_plan_missing' }
    }
    $explainStage = [pscustomobject]@{
        name = 'explain'
        ready = (@($Scenario.expected_outcome).Count -gt 0)
        evidence = if (@($Scenario.expected_outcome).Count -gt 0) { 'expected_outcome_present' } else { 'expected_outcome_missing' }
    }
    return @($inspectStage, $understandStage, $patchStage, $validateStage, $recoverStage, $explainStage)
}

function Get-AssistResult {
    param(
        [Parameter(Mandatory = $true)][bool]$ProviderReachable,
        [Parameter(Mandatory = $true)][string]$AssistScript,
        [Parameter(Mandatory = $true)][string]$Mode,
        [Parameter(Mandatory = $true)][string[]]$CandidateFiles,
        [int]$MaxFiles = 4
    )

    if (-not $ProviderReachable -or @($CandidateFiles).Count -eq 0) {
        return $null
    }

    try {
        return (& $AssistScript -Mode $Mode -FilePaths $CandidateFiles -MaxFiles $MaxFiles -EmitJson | ConvertFrom-Json)
    }
    catch {
        return [pscustomobject]@{
            summary = [pscustomobject]@{ average_utility = 0.0; pass_count = 0; failure_count = @($CandidateFiles).Count }
            results = @()
            error = $_.Exception.Message
        }
    }
}

$assistScript = Join-Path $PSScriptRoot "Invoke-TODRealCodeAssist.ps1"
$providerScript = Join-Path $PSScriptRoot "Invoke-TODConversationProvider.ps1"
$assistAvailable = $UseAssist.IsPresent -and (Test-Path -Path $assistScript) -and (Test-Path -Path $providerScript)
$providerReachable = $false
if ($assistAvailable) {
    try {
        $status = & $providerScript -Action status -AsJson | ConvertFrom-Json
        $providerReachable = [bool]$status.reachable
    }
    catch {
        $providerReachable = $false
    }
}

$resolvedSuitePath = Resolve-LocalPath -PathValue $SuitePath
$resolvedProjectIndexPath = Resolve-LocalPath -PathValue $ProjectIndexPath
$resolvedRegistryPath = Resolve-LocalPath -PathValue $RegistryPath
$outputRootAbs = Resolve-LocalPath -PathValue $OutputRoot

if (-not (Test-Path -Path $resolvedSuitePath)) { throw "Simulation suite not found: $resolvedSuitePath" }
if (-not (Test-Path -Path $resolvedProjectIndexPath)) { throw "Project index not found: $resolvedProjectIndexPath" }
if (-not (Test-Path -Path $resolvedRegistryPath)) { throw "Project registry not found: $resolvedRegistryPath" }
if (-not (Test-Path -Path $outputRootAbs)) { New-Item -ItemType Directory -Path $outputRootAbs -Force | Out-Null }

$suite = Get-Content -Path $resolvedSuitePath -Raw | ConvertFrom-Json
$projectIndex = Get-Content -Path $resolvedProjectIndexPath -Raw | ConvertFrom-Json
$registry = Get-Content -Path $resolvedRegistryPath -Raw | ConvertFrom-Json
$projects = @($projectIndex.projects)
$registryProjects = @($registry.projects)

$githubAuth = [pscustomobject]@{ authenticated = $false; account = "" }
try {
    $authText = (& gh auth status 2>&1 | Out-String)
    $githubAuth.authenticated = ($authText -match "Logged in to github.com account")
    if ($authText -match "Logged in to github.com account\s+([^\s]+)") {
        $githubAuth.account = $Matches[1]
    }
}
catch {
}

$runId = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
$runPath = Join-Path $outputRootAbs ("tod_repo_edit_test_recover.{0}.json" -f $runId)
$latestPath = Join-Path $outputRootAbs "tod_repo_edit_test_recover.latest.json"

$scenarioResults = @()
foreach ($scenario in @($suite.scenarios)) {
    $project = @($projects | Where-Object { [string]$_.id -eq [string]$scenario.project_id } | Select-Object -First 1)
    if ($null -eq $project) {
        $project = @($registryProjects | Where-Object { [string]$_.id -eq [string]$scenario.project_id } | Select-Object -First 1)
    }

    if ($null -eq $project) {
        $scenarioResults += [pscustomobject]@{
            scenario_id = [string]$scenario.id
            project_id = [string]$scenario.project_id
            passed = $false
            reason = "project_not_found"
        }
        continue
    }

    $candidateFiles = @(Find-CandidateFiles -Project $project -Hints @($scenario.target_hints) -MaxFiles $MaxCandidateFiles)
    $boundary = Test-Boundaries -Project $project -FullPaths $candidateFiles
    $gitInfo = Get-GitInfo -ProjectPath ([string]$project.path)
    $testCommands = Get-TestCommands -Project $project
    $assist = Get-AssistResult -ProviderReachable $providerReachable -AssistScript $assistScript -Mode ([string]$scenario.mode) -CandidateFiles $candidateFiles -MaxFiles $MaxCandidateFiles
    $stages = @(New-StageChecklist -Scenario $scenario -Project $project -CandidateFiles $candidateFiles -Boundary $boundary -GitInfo $gitInfo -TestCommands $testCommands)
    $requiredStageNames = @($scenario.required_loop_stages)
    $requiredStages = @($stages | Where-Object { @($requiredStageNames) -contains [string]$_.name })
    $requiredReadyCount = @($requiredStages | Where-Object { [bool]$_.ready }).Count
    $requiredTotal = [Math]::Max(1, @($requiredStages).Count)
    $stageCoverage = [math]::Round(($requiredReadyCount / $requiredTotal), 4)
    $averageUtility = if ($assist -and $assist.summary) { [double]$assist.summary.average_utility } else { 0.0 }
    $relativeCoverage = Get-RelativeCandidateCoverage -CandidateFiles $candidateFiles -ProjectPath ([string]$project.path) -RelativePathCandidates @($scenario.relative_path_candidates)
    $testReady = (@($testCommands).Count -gt 0)
    $recoveryReady = ([bool]$gitInfo.is_repo -and @($scenario.recovery_expectations).Count -gt 0)
    $simulationPassed = [bool](
        @($candidateFiles).Count -gt 0 -and
        [bool]$boundary.ok -and
        $relativeCoverage -and
        ($stageCoverage -ge 0.8) -and
        ((-not $providerReachable) -or ($averageUtility -ge 0.72))
    )

    $scenarioResults += [pscustomobject]@{
        scenario_id = [string]$scenario.id
        project_id = [string]$project.id
        project_name = [string]$project.name
        task = [string]$scenario.task
        mode = [string]$scenario.mode
        simulation_only = [bool]$suite.simulation_only
        passed = $simulationPassed
        candidate_files = @($candidateFiles)
        relative_candidate_coverage = $relativeCoverage
        boundary_passed = [bool]$boundary.ok
        git = $gitInfo
        github = $githubAuth
        test_ready = $testReady
        recovery_ready = $recoveryReady
        test_commands = @($testCommands)
        required_loop_stages = @($scenario.required_loop_stages)
        stage_checklist = @($stages)
        stage_coverage = $stageCoverage
        expected_outcome = @($scenario.expected_outcome)
        recovery_expectations = @($scenario.recovery_expectations)
        assist_average_utility = [math]::Round($averageUtility, 4)
        assist_results = if ($assist -and $assist.results) { @($assist.results) } else { @() }
        loop_contract = [pscustomobject]@{
            inspect = 'find owning files before editing'
            understand = 'state one falsifiable local hypothesis'
            patch = 'prefer the smallest bounded code change'
            validate = if ($testReady) { 'run the narrowest configured validation command first' } else { 'no configured test command found; validation gap remains' }
            recover = if ($recoveryReady) { 'repair the same slice first; if falsified, step to the nearest controlling file' } else { 'no repo/recovery expectation available' }
            explain = 'publish root cause, fix, validation, residual risk, and next options'
        }
        operator_ready_packet = [pscustomobject]@{
            suggested_commit_message = "sim($($project.id)): rehearse repo-edit-test-recover loop for $([string]$scenario.id.ToLowerInvariant())"
            validation_commands = @($testCommands)
            recovery_notes = @($scenario.recovery_expectations)
            publish_checklist = @(
                'confirm the candidate files are the intended patch surface',
                'make the smallest bounded edit possible',
                'run the narrowest validation command before widening scope',
                'if validation fails, repair or recover before continuing',
                'summarize the final result and residual risks'
            )
        }
    }
}

$summary = [pscustomobject]@{
    scenario_count = @($scenarioResults).Count
    pass_count = [int](@($scenarioResults | Where-Object { [bool]$_.passed }).Count)
    test_ready_count = [int](@($scenarioResults | Where-Object { [bool]$_.test_ready }).Count)
    recovery_ready_count = [int](@($scenarioResults | Where-Object { [bool]$_.recovery_ready }).Count)
    average_stage_coverage = if (@($scenarioResults).Count -gt 0) { [math]::Round(((@($scenarioResults | ForEach-Object { [double]$_.stage_coverage }) | Measure-Object -Average).Average), 4) } else { 0.0 }
    average_assist_utility = if (@($scenarioResults).Count -gt 0) { [math]::Round(((@($scenarioResults | ForEach-Object { [double]$_.assist_average_utility }) | Measure-Object -Average).Average), 4) } else { 0.0 }
    provider_reachable = $providerReachable
    github_authenticated = [bool]$githubAuth.authenticated
    github_account = [string]$githubAuth.account
}

$report = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = "tod-repo-edit-test-recover-simulation-v1"
    run_id = $runId
    config = [pscustomobject]@{
        suite_path = $SuitePath
        project_index_path = $ProjectIndexPath
        registry_path = $RegistryPath
        output_root = $OutputRoot
        max_candidate_files = $MaxCandidateFiles
        use_assist = $providerReachable
        simulation_only = [bool]$suite.simulation_only
    }
    summary = $summary
    scenarios = @($scenarioResults)
    artifacts = [pscustomobject]@{
        run_path = $runPath
        latest_path = $latestPath
    }
}

$report | ConvertTo-Json -Depth 30 | Set-Content -Path $runPath
$report | ConvertTo-Json -Depth 30 | Set-Content -Path $latestPath

if ($EmitJson) {
    $report | ConvertTo-Json -Depth 12 | Write-Output
}
else {
    $report
}