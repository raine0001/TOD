param(
    [string]$ConfigPath,
    [string]$OutputDir,
    [string]$LibraryRoot = "E:\\",
    [int]$Top = 25,
    [switch]$SkipTests,
    [switch]$SkipSmoke,
    [switch]$SkipProjectDiscovery,
    [switch]$FailOnError
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$todScript = Join-Path $PSScriptRoot "TOD.ps1"
$testsScript = Join-Path $PSScriptRoot "Invoke-TODTests.ps1"
$smokeScript = Join-Path $PSScriptRoot "Invoke-TODSmoke.ps1"
$projectLibraryScript = Join-Path $PSScriptRoot "Update-TODProjectLibrary.ps1"

if (-not (Test-Path -Path $todScript)) {
    throw "Missing TOD script: $todScript"
}
if (-not (Test-Path -Path $testsScript)) {
    throw "Missing tests runner: $testsScript"
}
if (-not (Test-Path -Path $smokeScript)) {
    throw "Missing smoke runner: $smokeScript"
}
if (-not (Test-Path -Path $projectLibraryScript)) {
    throw "Missing project library script: $projectLibraryScript"
}

$effectiveConfigPath = if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    Join-Path $repoRoot "tod/config/tod-config.json"
}
else {
    if ([System.IO.Path]::IsPathRooted($ConfigPath)) { $ConfigPath } else { Join-Path $repoRoot $ConfigPath }
}

if (-not (Test-Path -Path $effectiveConfigPath)) {
    throw "Config file not found: $effectiveConfigPath"
}

$effectiveOutputDir = if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    Join-Path $repoRoot "tod/out/training"
}
else {
    if ([System.IO.Path]::IsPathRooted($OutputDir)) { $OutputDir } else { Join-Path $repoRoot $OutputDir }
}

if (-not (Test-Path -Path $effectiveOutputDir)) {
    New-Item -ItemType Directory -Path $effectiveOutputDir -Force | Out-Null
}

function Invoke-TodJsonAction {
    param(
        [Parameter(Mandatory = $true)][string]$Action,
        [hashtable]$ExtraArgs = @{}
    )

    $params = @{
        Action = $Action
        ConfigPath = $effectiveConfigPath
        Top = $Top
    }

    foreach ($key in $ExtraArgs.Keys) {
        $params[$key] = $ExtraArgs[$key]
    }

    $raw = & $todScript @params
    return ($raw | ConvertFrom-Json)
}

function Get-ResourceFileInfo {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -Path $Path)) {
        return $null
    }

    $item = Get-Item -Path $Path
    return [pscustomobject]@{
        path = $Path.Substring($repoRoot.Length).TrimStart([char[]]@([char]92, [char]47)) -replace "\\", "/"
        bytes = [int64]$item.Length
        updated_at = [string]$item.LastWriteTimeUtc.ToString("o")
    }
}

function Test-StateFileWritable {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -Path $Path)) {
        return $true
    }

    $stream = $null
    try {
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        return $true
    }
    catch {
        return $false
    }
    finally {
        if ($null -ne $stream) {
            $stream.Dispose()
        }
    }
}

$testSummary = $null
$smokeSummary = $null
$projectLibrary = $null
$errors = @()

if (-not $SkipTests) {
    try {
        $statePath = Join-Path $repoRoot "tod/data/state.json"
        if (-not (Test-StateFileWritable -Path $statePath)) {
            $errors += "tests: skipped because tod/data/state.json is locked (stop TOD UI or rerun with -SkipTests)"
            $SkipTests = $true
        }
    }
    catch {
        $errors += "tests precheck: $($_.Exception.Message)"
    }
}

if (-not $SkipTests) {
    try {
        $testsOut = Join-Path $effectiveOutputDir "test-summary.json"
        $testsRaw = & $testsScript -Path "tests/*.Tests.ps1" -JsonOutputPath $testsOut
        $testSummary = $testsRaw | ConvertFrom-Json
    }
    catch {
        $errors += "tests: $($_.Exception.Message)"
    }
}

if (-not $SkipSmoke) {
    try {
        $smokeRaw = & $smokeScript -Top $Top
        $smokeSummary = $smokeRaw | ConvertFrom-Json
        $smokeOut = Join-Path $effectiveOutputDir "smoke-summary.json"
        $smokeSummary | ConvertTo-Json -Depth 12 | Set-Content -Path $smokeOut
    }
    catch {
        $errors += "smoke: $($_.Exception.Message)"
    }
}

if (-not $SkipProjectDiscovery) {
    try {
        $projectLibraryRaw = & $projectLibraryScript -RootPath $LibraryRoot -RegistryPath "tod/config/project-registry.json" -OutputPath "tod/data/project-library-index.json"
        $projectLibrary = $projectLibraryRaw | ConvertFrom-Json
    }
    catch {
        $errors += "project-discovery: $($_.Exception.Message)"
    }
}

$stateBus = $null
$reliability = $null
$dashboard = $null
$taxonomy = $null
$loopSummary = $null
$signal = $null
$history = $null

try { $stateBus = Invoke-TodJsonAction -Action "get-state-bus" } catch { $errors += "state-bus: $($_.Exception.Message)" }
try { $reliability = Invoke-TodJsonAction -Action "get-reliability" } catch { $errors += "reliability: $($_.Exception.Message)" }
try { $dashboard = Invoke-TodJsonAction -Action "show-reliability-dashboard" } catch { $errors += "dashboard: $($_.Exception.Message)" }
try { $taxonomy = Invoke-TodJsonAction -Action "show-failure-taxonomy" } catch { $errors += "taxonomy: $($_.Exception.Message)" }
try { $loopSummary = Invoke-TodJsonAction -Action "get-engineering-loop-summary" } catch { $errors += "loop-summary: $($_.Exception.Message)" }
try { $signal = Invoke-TodJsonAction -Action "get-engineering-signal" } catch { $errors += "signal: $($_.Exception.Message)" }
try { $history = Invoke-TodJsonAction -Action "get-engineering-loop-history" -ExtraArgs @{ HistoryKind = "scorecard_history"; Page = 1; PageSize = 25 } } catch { $errors += "history: $($_.Exception.Message)" }

$resources = @()
$seedFiles = @(
    "tod/data/engineering-memory.json",
    "tod/data/repo-index.json",
    "tod/data/module-summaries.json",
    "tod/config/project-registry.json",
    "tod/config/project-priority.json",
    "tod/config/media-pipeline-profiles.json",
    "tod/config/media-runtime.json",
    "tod/config/context-exchange.json",
    "tod/data/project-library-index.json",
    "scripts/Test-TODProjectAccessPolicy.ps1",
    "scripts/Get-TODProjectExecutionQueue.ps1",
    "scripts/Invoke-TODProjectQueueRunner.ps1",
    "scripts/Invoke-TODMediaPipeline.ps1",
    "scripts/Invoke-TODContextExchange.ps1",
    "tod/data/sample-codex-result.json",
    "tod/data/sample-journal-post.json",
    "tod/config/tod-config.json",
    "docs/tod-command-reference.md",
    "docs/tod-state-bus-contract-v1.md",
    "docs/tod-mim-shared-contract-v1.md",
    "docs/tod-mim-context-exchange-v1.md",
    "docs/mim-tod-execution-feedback-contract-v1.md",
    "docs/codex-result-format-v1.md"
)

foreach ($rel in $seedFiles) {
    $full = Join-Path $repoRoot $rel
    $info = Get-ResourceFileInfo -Path $full
    if ($null -ne $info) { $resources += $info }
}

$docsDir = Join-Path $repoRoot "docs"
if (Test-Path -Path $docsDir) {
    $docs = @(Get-ChildItem -Path $docsDir -Filter "*.md" | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 10)
    foreach ($doc in $docs) {
        $entry = [pscustomobject]@{
            path = $doc.FullName.Substring($repoRoot.Length).TrimStart([char[]]@([char]92, [char]47)) -replace "\\", "/"
            bytes = [int64]$doc.Length
            updated_at = [string]$doc.LastWriteTimeUtc.ToString("o")
        }
        $resources += $entry
    }
}

$resources = @($resources | Sort-Object path -Unique)

$governanceScore = 0
if ($stateBus -and $stateBus.PSObject.Properties["blocks"] -and $stateBus.blocks) { $governanceScore += 1 }
if ($signal -and $signal.PSObject.Properties["pending_approval_state"]) { $governanceScore += 1 }
if ($history -and $history.PSObject.Properties["items"]) { $governanceScore += 1 }
if ($signal -and $signal.PSObject.Properties["stop_reason"]) { $governanceScore += 1 }
if ($stateBus -and $stateBus.PSObject.Properties["engineering_loop_state"]) { $governanceScore += 1 }

$reliabilityScore = 0
if ($reliability -and $reliability.PSObject.Properties["current_alert_state"]) { $reliabilityScore += 2 }
if ($dashboard -and $dashboard.PSObject.Properties["retry_trend"]) { $reliabilityScore += 1 }
if ($dashboard -and $dashboard.PSObject.Properties["drift_warnings"]) { $reliabilityScore += 1 }
if ($taxonomy -and $taxonomy.PSObject.Properties["groups"]) { $reliabilityScore += 1 }

$workflowScore = 0
if ($loopSummary -and $loopSummary.PSObject.Properties["latest_score"]) { $workflowScore += 1 }
if ($signal -and $signal.PSObject.Properties["trend_direction"]) { $workflowScore += 1 }
if ($signal -and $signal.PSObject.Properties["phase_snapshot"]) { $workflowScore += 1 }
if ($stateBus -and $stateBus.PSObject.Properties["system_posture"]) { $workflowScore += 1 }
if ($history -and $history.PSObject.Properties["paging"]) { $workflowScore += 1 }

$runtimeScore = 0
if ($smokeSummary -and $smokeSummary.PSObject.Properties["passed_all"] -and [bool]$smokeSummary.passed_all) { $runtimeScore += 3 }
if ($testSummary -and $testSummary.PSObject.Properties["passed_all"] -and [bool]$testSummary.passed_all) { $runtimeScore += 2 }

$competency = [pscustomobject]@{
    governance_and_control = [Math]::Min($governanceScore, 5)
    reliability_awareness = [Math]::Min($reliabilityScore, 5)
    workflow_structure = [Math]::Min($workflowScore, 5)
    runtime_interaction = [Math]::Min($runtimeScore, 5)
}

$nextDrills = @(
    [pscustomobject]@{
        id = "drill-root-cause"
        title = "Root cause over patching"
        objective = "Fix one failing behavior with minimal surface area and explicit root-cause notes."
        evidence = @("tests/*.Tests.ps1", "show-failure-taxonomy", "recent journal entries")
    },
    [pscustomobject]@{
        id = "drill-multi-file"
        title = "Cross-module feature slice"
        objective = "Ship one feature requiring coordinated runtime + UI + tests + docs updates."
        evidence = @("get-state-bus", "get-engineering-signal", "Invoke-TODTests")
    },
    [pscustomobject]@{
        id = "drill-reliability"
        title = "Reliability regression recovery"
        objective = "Induce and recover from a degraded alert state while keeping guardrails intact."
        evidence = @("get-reliability", "show-reliability-dashboard", "Invoke-TODSmoke")
    },
    [pscustomobject]@{
        id = "drill-project-discovery"
        title = "Cross-project architecture mapping"
        objective = "Refresh project registry, verify boundaries, and summarize risky zones before implementation work."
        evidence = @("tod/config/project-registry.json", "tod/data/project-library-index.json", "Update-TODProjectLibrary")
    },
    [pscustomobject]@{
        id = "drill-policy-enforcement"
        title = "Policy-gated implementation"
        objective = "Validate proposed edits against allowed/blocked path boundaries before patching."
        evidence = @("scripts/Test-TODProjectAccessPolicy.ps1", "tod/config/project-registry.json")
    },
    [pscustomobject]@{
        id = "drill-media-pipeline"
        title = "Media generation workflow"
        objective = "Route content generation tasks through project media profiles with artifact manifests."
        evidence = @("tod/config/media-pipeline-profiles.json", "tod/config/project-priority.json", "scripts/Get-TODProjectExecutionQueue.ps1")
    }
)

$report = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = "tod-training-loop-v1"
    config_path = $effectiveConfigPath
    output_dir = $effectiveOutputDir
    run = [pscustomobject]@{
        tests = if ($null -ne $testSummary) { $testSummary } else { [pscustomobject]@{ skipped = [bool]$SkipTests } }
        smoke = if ($null -ne $smokeSummary) { $smokeSummary } else { [pscustomobject]@{ skipped = [bool]$SkipSmoke } }
        project_discovery = if ($null -ne $projectLibrary) { [pscustomobject]@{ skipped = $false; projects = @($projectLibrary.projects).Count; unregistered = @($projectLibrary.unregistered_top_level_directories).Count } } else { [pscustomobject]@{ skipped = [bool]$SkipProjectDiscovery } }
        errors = @($errors)
    }
    resources = [pscustomobject]@{
        total = @($resources).Count
        files = @($resources)
    }
    evidence = [pscustomobject]@{
        engineering_signal = $signal
        engineering_summary = $loopSummary
        state_bus = $stateBus
        reliability = $reliability
        reliability_dashboard = $dashboard
        failure_taxonomy = $taxonomy
        scorecard_history = $history
        project_library = $projectLibrary
    }
    competency_snapshot = $competency
    next_drills = @($nextDrills)
}

$jsonPath = Join-Path $effectiveOutputDir "training-report.json"
$mdPath = Join-Path $effectiveOutputDir "training-report.md"
$report | ConvertTo-Json -Depth 30 | Set-Content -Path $jsonPath

$md = @()
$md += "# TOD Training Report"
$md += ""
$md += "Generated: $($report.generated_at)"
$md += ""
$md += "## Competency Snapshot"
$md += "- Governance and control: $($report.competency_snapshot.governance_and_control)/5"
$md += "- Reliability awareness: $($report.competency_snapshot.reliability_awareness)/5"
$md += "- Workflow structure: $($report.competency_snapshot.workflow_structure)/5"
$md += "- Runtime interaction: $($report.competency_snapshot.runtime_interaction)/5"
$md += ""
$md += "## Existing Consumable Resources"
$md += "- Total files: $($report.resources.total)"
foreach ($file in @($report.resources.files | Select-Object -First 20)) {
    $md += "- $($file.path)"
}
$md += ""
$md += "## Run Summary"
if ($null -ne $testSummary) {
    $md += "- Tests: passed=$($testSummary.passed) failed=$($testSummary.failed)"
} else {
    $md += "- Tests: skipped"
}
if ($null -ne $smokeSummary) {
    $md += "- Smoke checks passed: $([bool]$smokeSummary.passed_all)"
} else {
    $md += "- Smoke checks: skipped"
}
if ($null -ne $projectLibrary) {
    $md += "- Project discovery: projects=$(@($projectLibrary.projects).Count) unregistered_top_level=$(@($projectLibrary.unregistered_top_level_directories).Count)"
} else {
    $md += "- Project discovery: skipped"
}
if (@($errors).Count -gt 0) {
    $md += "- Errors:"
    foreach ($e in $errors) {
        $md += "  - $e"
    }
}
$md += ""
$md += "## Next Drills"
foreach ($drill in $nextDrills) {
    $md += "- [$($drill.id)] $($drill.title): $($drill.objective)"
}

$md -join [Environment]::NewLine | Set-Content -Path $mdPath

$result = [pscustomobject]@{
    ok = (@($errors).Count -eq 0)
    path = "/tod/training/report"
    source = "tod-training-loop-v1"
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    report_json = $jsonPath
    report_markdown = $mdPath
    competency_snapshot = $competency
    resources_count = @($resources).Count
    errors = @($errors)
}

$result | ConvertTo-Json -Depth 10 | Write-Output

if ($FailOnError -and @($errors).Count -gt 0) {
    throw "Training loop completed with errors."
}
