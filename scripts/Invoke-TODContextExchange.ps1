param(
    [ValidateSet("export", "ingest", "status")]
    [string]$Action = "export",
    [string]$ContextConfigPath = "tod/config/context-exchange.json",
    [string]$TodConfigPath = "tod/config/tod-config.json",
    [string]$TodScriptPath = "scripts/TOD.ps1",
    [int]$Top = 10,
    [string[]]$NextActions,
    [int]$ProjectLimit = 0,
    [string]$InputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

function Resolve-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) { return $PathValue }
    return (Join-Path $repoRoot $PathValue)
}

function Read-JsonFile {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    $resolved = Resolve-LocalPath -PathValue $PathValue
    if (-not (Test-Path -Path $resolved)) { throw "File not found: $resolved" }
    return (Get-Content -Path $resolved -Raw | ConvertFrom-Json)
}

function New-DirectoryIfMissing {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if (-not (Test-Path -Path $PathValue)) {
        New-Item -ItemType Directory -Path $PathValue -Force | Out-Null
    }
}

function Get-OptionalJsonFile {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if (-not (Test-Path -Path $PathValue)) { return $null }
    try {
        return (Get-Content -Path $PathValue -Raw | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Get-TodAction {
    param(
        [Parameter(Mandatory = $true)][string]$TodScript,
        [Parameter(Mandatory = $true)][string]$TodConfig,
        [Parameter(Mandatory = $true)][string]$ActionName,
        [int]$Top = 10
    )

    try {
        $raw = & $TodScript -Action $ActionName -ConfigPath $TodConfig -Top $Top
        return ($raw | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Get-TestSummaryText {
    param($TestSummary)
    if ($null -eq $TestSummary) { return "regression suite run: unavailable" }

    $passed = if ($TestSummary.PSObject.Properties["passed"]) { [int]$TestSummary.passed } else { 0 }
    $total = if ($TestSummary.PSObject.Properties["total"]) { [int]$TestSummary.total } else { 0 }
    $status = if ($TestSummary.PSObject.Properties["passed_all"] -and [bool]$TestSummary.passed_all) { "pass" } else { "attention" }
    return "regression suite run: $status ($passed/$total)"
}

function Get-SmokeActionText {
    param($SmokeSummary)
    if ($null -eq $SmokeSummary) { return "runtime health checks: unavailable" }

    $ok = if ($SmokeSummary.PSObject.Properties["passed_all"]) { [bool]$SmokeSummary.passed_all } else { $false }
    if ($ok) { return "runtime health verified" }
    return "runtime health checks require follow-up"
}

function ConvertTo-ContextYaml {
    param(
        [Parameter(Mandatory = $true)]$Context
    )

    $lines = @()
    $lines += "MIM_CONTEXT_EXPORT"
    $lines += ""
    $lines += "system:"
    $lines += "  name: $($Context.system.name)"
    $lines += "  environment: $($Context.system.environment)"
    $lines += "  gpu: $($Context.system.gpu)"
    $lines += ""
    $lines += "status:"
    $lines += "  objective_active: $($Context.status.objective_active)"
    $lines += "  phase: $($Context.status.phase)"
    $lines += "  reliability: $($Context.status.reliability)"
    $lines += "  trend: $($Context.status.trend)"
    $lines += "  blockers: $($Context.status.blockers)"
    $lines += ""
    $lines += "recent_actions:"
    foreach ($item in @($Context.recent_actions)) {
        $lines += "  - $item"
    }
    $lines += ""
    $lines += "projects:"
    foreach ($item in @($Context.projects)) {
        $lines += "  - $item"
    }
    $lines += ""
    $lines += "next_actions:"
    foreach ($item in @($Context.next_actions)) {
        $lines += "  - $item"
    }

    return ($lines -join [Environment]::NewLine)
}

$contextCfg = Read-JsonFile -PathValue $ContextConfigPath
$todCfgAbs = Resolve-LocalPath -PathValue $TodConfigPath
$todScriptAbs = Resolve-LocalPath -PathValue $TodScriptPath

if (-not (Test-Path -Path $todCfgAbs)) { throw "TOD config file not found: $todCfgAbs" }
if (-not (Test-Path -Path $todScriptAbs)) { throw "TOD script not found: $todScriptAbs" }

$exportDir = Resolve-LocalPath -PathValue ([string]$contextCfg.paths.export_dir)
$latestYamlPath = Resolve-LocalPath -PathValue ([string]$contextCfg.paths.latest_export_file)
$latestJsonPath = Resolve-LocalPath -PathValue ([string]$contextCfg.paths.latest_export_json)
$inboxDir = Resolve-LocalPath -PathValue ([string]$contextCfg.paths.inbox_dir)
$processedDir = Resolve-LocalPath -PathValue ([string]$contextCfg.paths.processed_dir)
$updatesLogPath = Resolve-LocalPath -PathValue ([string]$contextCfg.paths.updates_log)

New-DirectoryIfMissing -PathValue $exportDir
New-DirectoryIfMissing -PathValue $inboxDir
New-DirectoryIfMissing -PathValue $processedDir
New-DirectoryIfMissing -PathValue (Split-Path -Parent $latestYamlPath)
New-DirectoryIfMissing -PathValue (Split-Path -Parent $updatesLogPath)

if ($Action -eq "status") {
    $pending = @()
    if (Test-Path -Path $inboxDir) {
        $pending = @(Get-ChildItem -Path $inboxDir -File -Filter "*.json" | Sort-Object LastWriteTimeUtc)
    }

    $result = [pscustomobject]@{
        ok = $true
        source = "tod-context-exchange-v1"
        action = "status"
        generated_at = (Get-Date).ToUniversalTime().ToString("o")
        paths = [pscustomobject]@{
            export_dir = $exportDir
            latest_export_file = $latestYamlPath
            latest_export_json = $latestJsonPath
            inbox_dir = $inboxDir
            processed_dir = $processedDir
            updates_log = $updatesLogPath
        }
        latest_export_exists = (Test-Path -Path $latestYamlPath)
        pending_update_files = @($pending | ForEach-Object { $_.FullName })
        pending_update_count = @($pending).Count
    }

    $result | ConvertTo-Json -Depth 10 | Write-Output
    return
}

if ($Action -eq "ingest") {
    $files = @()
    if (-not [string]::IsNullOrWhiteSpace($InputPath)) {
        $candidate = Resolve-LocalPath -PathValue $InputPath
        if (-not (Test-Path -Path $candidate)) { throw "Input file not found: $candidate" }
        $files = @((Get-Item -Path $candidate))
    }
    else {
        $files = @(Get-ChildItem -Path $inboxDir -File -Filter "*.json" | Sort-Object LastWriteTimeUtc)
    }

    $accepted = @()
    $rejected = @()

    foreach ($file in $files) {
        try {
            $payload = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json
            $entry = [pscustomobject]@{
                id = "CTXUPD-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 10).ToUpperInvariant())
                imported_at = (Get-Date).ToUniversalTime().ToString("o")
                source = if ($payload.PSObject.Properties["source"]) { [string]$payload.source } else { "unknown" }
                actor = if ($payload.PSObject.Properties["actor"]) { [string]$payload.actor } else { "unknown" }
                channel = if ($payload.PSObject.Properties["channel"]) { [string]$payload.channel } else { "collaborator" }
                summary = if ($payload.PSObject.Properties["summary"]) { [string]$payload.summary } else { "" }
                update_type = if ($payload.PSObject.Properties["update_type"]) { [string]$payload.update_type } else { "status" }
                project = if ($payload.PSObject.Properties["project"]) { [string]$payload.project } else { "" }
                data = $payload
                file_name = $file.Name
            }

            ($entry | ConvertTo-Json -Depth 20) + [Environment]::NewLine | Add-Content -Path $updatesLogPath

            $target = Join-Path $processedDir $file.Name
            Move-Item -Path $file.FullName -Destination $target -Force

            $accepted += [pscustomobject]@{
                file = $file.FullName
                update_id = $entry.id
                source = $entry.source
                summary = $entry.summary
                processed_path = $target
            }
        }
        catch {
            $rejected += [pscustomobject]@{
                file = $file.FullName
                error = $_.Exception.Message
            }
        }
    }

    $result = [pscustomobject]@{
        ok = (@($rejected).Count -eq 0)
        source = "tod-context-exchange-v1"
        action = "ingest"
        generated_at = (Get-Date).ToUniversalTime().ToString("o")
        accepted_count = @($accepted).Count
        rejected_count = @($rejected).Count
        accepted = @($accepted)
        rejected = @($rejected)
        updates_log = $updatesLogPath
    }

    $result | ConvertTo-Json -Depth 12 | Write-Output
    if (@($rejected).Count -gt 0) { exit 2 }
    return
}

$testSummary = Get-OptionalJsonFile -PathValue (Join-Path $repoRoot "tod/out/training/test-summary.json")
$smokeSummary = Get-OptionalJsonFile -PathValue (Join-Path $repoRoot "tod/out/training/smoke-summary.json")
$registry = Get-OptionalJsonFile -PathValue (Join-Path $repoRoot "tod/config/project-registry.json")

$engineeringSignal = Get-TodAction -TodScript $todScriptAbs -TodConfig $todCfgAbs -ActionName "get-engineering-signal" -Top $Top
$reliability = Get-TodAction -TodScript $todScriptAbs -TodConfig $todCfgAbs -ActionName "get-reliability" -Top $Top

$objectiveActive = if ($smokeSummary -and $smokeSummary.PSObject.Properties["facts"] -and $smokeSummary.facts.PSObject.Properties["objective_count"]) {
    [int]$smokeSummary.facts.objective_count
}
else {
    0
}

$phase = if ($engineeringSignal -and $engineeringSignal.PSObject.Properties["current_engineering_loop_status"]) {
    [string]$engineeringSignal.current_engineering_loop_status
}
else {
    "unknown"
}

$trend = if ($engineeringSignal -and $engineeringSignal.PSObject.Properties["trend_direction"]) {
    [string]$engineeringSignal.trend_direction
}
else {
    "unknown"
}

$blockers = "none"
if ($engineeringSignal -and $engineeringSignal.PSObject.Properties["pending_approval_state"] -and $engineeringSignal.pending_approval_state.PSObject.Properties["pending"] -and [bool]$engineeringSignal.pending_approval_state.pending) {
    $count = if ($engineeringSignal.pending_approval_state.PSObject.Properties["count"]) { [int]$engineeringSignal.pending_approval_state.count } else { 0 }
    $blockers = "pending approvals ($count)"
}

$reliabilityScore = "n/a"
if ($reliability -and $reliability.PSObject.Properties["reliability_scorecard"] -and $reliability.reliability_scorecard.PSObject.Properties["score"]) {
    $reliabilityScore = [math]::Round([double]$reliability.reliability_scorecard.score, 3)
}

$recentActions = @(
    (Get-TestSummaryText -TestSummary $testSummary),
    (Get-SmokeActionText -SmokeSummary $smokeSummary),
    "SSH connectivity: verify with scripts/Connect-Mim.ps1 as needed"
)

$projectNames = @()
if ($registry -and $registry.PSObject.Properties["projects"]) {
    $projectNames = @($registry.projects | ForEach-Object { [string]$_.name })
}

$effectiveProjectLimit = if ($ProjectLimit -gt 0) { $ProjectLimit } elseif ($contextCfg.defaults.PSObject.Properties["project_limit"]) { [int]$contextCfg.defaults.project_limit } else { 8 }
if (@($projectNames).Count -gt $effectiveProjectLimit) {
    $projectNames = @($projectNames | Select-Object -First $effectiveProjectLimit)
}

$effectiveNextActions = if ($null -ne $NextActions -and @($NextActions).Count -gt 0) { @($NextActions) } elseif ($contextCfg.defaults.PSObject.Properties["next_actions"]) { @($contextCfg.defaults.next_actions) } else { @("finalize verification gate") }

$context = [pscustomobject]@{
    source = "tod-context-exchange-v1"
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    system = [pscustomobject]@{
        name = [string]$contextCfg.system.name
        environment = [string]$contextCfg.system.environment
        gpu = [string]$contextCfg.system.gpu
    }
    status = [pscustomobject]@{
        objective_active = $objectiveActive
        phase = $phase
        reliability = $reliabilityScore
        trend = $trend
        blockers = $blockers
    }
    recent_actions = @($recentActions)
    projects = @($projectNames)
    next_actions = @($effectiveNextActions)
}

$yamlText = ConvertTo-ContextYaml -Context $context
$slug = (Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmmss")
$versionedYaml = Join-Path $exportDir ("MIM_CONTEXT_EXPORT-{0}.yaml" -f $slug)
$versionedJson = Join-Path $exportDir ("MIM_CONTEXT_EXPORT-{0}.json" -f $slug)

$yamlText | Set-Content -Path $versionedYaml
$context | ConvertTo-Json -Depth 20 | Set-Content -Path $versionedJson
$yamlText | Set-Content -Path $latestYamlPath
$context | ConvertTo-Json -Depth 20 | Set-Content -Path $latestJsonPath

$result = [pscustomobject]@{
    ok = $true
    source = "tod-context-exchange-v1"
    action = "export"
    generated_at = $context.generated_at
    latest_yaml = $latestYamlPath
    latest_json = $latestJsonPath
    versioned_yaml = $versionedYaml
    versioned_json = $versionedJson
    inbox_dir = $inboxDir
    processed_dir = $processedDir
    updates_log = $updatesLogPath
    preview = $yamlText
}

$result | ConvertTo-Json -Depth 20 | Write-Output
