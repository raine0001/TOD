param(
    [string]$OutputPath = "runtime_remote_training/MIM_STUDIO_DATA_AUDIT_AND_RECONCILIATION_RESULT.latest.json",
    [string]$MarkdownOutputPath = "runtime_remote_training/MIM_STUDIO_DATA_AUDIT_AND_RECONCILIATION_RESULT.latest.md",
    [string]$ContextSyncRoot = "tod/out/context-sync",
    [string]$StudioBaseUrl = "",
    [switch]$EmitJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

function Resolve-RepoPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return [System.IO.Path]::GetFullPath($PathValue)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $PathValue))
}

function Convert-ToIsoUtc {
    param([DateTime]$Value)
    return $Value.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
}

function Read-JsonFileIfExists {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if (-not (Test-Path -LiteralPath $PathValue)) { return $null }
    try {
        return Get-Content -LiteralPath $PathValue -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)]$Payload
    )
    $dir = Split-Path -Parent $PathValue
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $json = ($Payload | ConvertTo-Json -Depth 40) -replace "`r`n", "`n"
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($PathValue, $json + "`n", $utf8NoBom)
}

function Get-JsonString {
    param($Object, [string]$Name)
    if ($null -ne $Object -and $Object.PSObject.Properties[$Name] -and $null -ne $Object.$Name) {
        return [string]$Object.$Name
    }
    return ""
}

function Get-SourceRecord {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [string]$Kind = "artifact"
    )
    $abs = Resolve-RepoPath -PathValue $RelativePath
    $exists = Test-Path -LiteralPath $abs
    $item = if ($exists) { Get-Item -LiteralPath $abs } else { $null }
    $json = if ($exists -and $abs.ToLowerInvariant().EndsWith(".json")) { Read-JsonFileIfExists -PathValue $abs } else { $null }
    $generatedAt = ""
    foreach ($name in @("generated_at", "updated_at", "created_at", "completed_at", "started_at")) {
        $value = Get-JsonString -Object $json -Name $name
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            $generatedAt = $value
            break
        }
    }
    $status = Get-JsonString -Object $json -Name "status"
    if ([string]::IsNullOrWhiteSpace($status)) { $status = if ($exists) { "available" } else { "missing" } }
    return [pscustomobject]@{
        label = $Label
        kind = $Kind
        path = $RelativePath
        exists = [bool]$exists
        last_write_utc = if ($item) { Convert-ToIsoUtc -Value $item.LastWriteTimeUtc } else { "" }
        generated_at = $generatedAt
        status = $status
        bytes = if ($item) { [int64]$item.Length } else { 0 }
    }
}

function Get-ApiRecord {
    param([string]$Label, [string]$Path)
    if ([string]::IsNullOrWhiteSpace($StudioBaseUrl)) { return $null }
    $url = $StudioBaseUrl.TrimEnd("/") + $Path
    try {
        $response = Invoke-RestMethod -Method Get -Uri $url -TimeoutSec 12
        return [pscustomobject]@{
            label = $Label
            kind = "studio_api"
            path = $url
            exists = $true
            last_write_utc = Convert-ToIsoUtc -Value (Get-Date)
            generated_at = Get-JsonString -Object $response -Name "generated_at"
            status = "reachable"
            bytes = 0
        }
    }
    catch {
        return [pscustomobject]@{
            label = $Label
            kind = "studio_api"
            path = $url
            exists = $false
            last_write_utc = Convert-ToIsoUtc -Value (Get-Date)
            generated_at = ""
            status = "unreachable: $([string]$_.Exception.Message)"
            bytes = 0
        }
    }
}

$nowIso = Convert-ToIsoUtc -Value (Get-Date)
$contextRoot = Resolve-RepoPath -PathValue $ContextSyncRoot
$validation = Read-JsonFileIfExists -PathValue (Join-Path $contextRoot "listener/MIM_CONTEXT_SYNC_DATA_ACCURACY_VALIDATION.latest.json")
$latestTodResult = Read-JsonFileIfExists -PathValue (Join-Path $contextRoot "listener/TOD_MIM_TASK_RESULT.latest.json")
$syncStatus = Read-JsonFileIfExists -PathValue (Join-Path $contextRoot "MIM_CONTEXT_SYNC_STATUS.latest.json")
$trainingScoreboard = Read-JsonFileIfExists -PathValue (Resolve-RepoPath -PathValue "runtime_remote_training/MIM_TOD_TRAINING_SCOREBOARD.latest.json")

$pages = @(
    [pscustomobject]@{
        page = "training"
        route = "/studio/training"
        status = "source_traceable"
        owner = "MIM + TOD"
        sources = @(
            Get-SourceRecord -Label "Training Scoreboard" -RelativePath "runtime_remote_training/MIM_TOD_TRAINING_SCOREBOARD.latest.json"
            Get-SourceRecord -Label "Hourly Reflection" -RelativePath "runtime_remote_training/MIM_TOD_HOURLY_REFLECTION.latest.json"
            Get-SourceRecord -Label "Context Sync Validation" -RelativePath "tod/out/context-sync/listener/MIM_CONTEXT_SYNC_DATA_ACCURACY_VALIDATION.latest.json"
            Get-SourceRecord -Label "TOD Validation Result" -RelativePath "runtime_remote_training/TOD_VALIDATION_RESULT.latest.json"
        )
        findings = @("Training must show source files for scoreboard, reflection, TOD validation, and context-sync validation.")
    },
    [pscustomobject]@{
        page = "health"
        route = "/studio/health"
        status = "source_traceable"
        owner = "TOD"
        sources = @(
            Get-SourceRecord -Label "Context Sync Status" -RelativePath "tod/out/context-sync/MIM_CONTEXT_SYNC_STATUS.latest.json"
            Get-SourceRecord -Label "Context Sync Validation" -RelativePath "tod/out/context-sync/listener/MIM_CONTEXT_SYNC_DATA_ACCURACY_VALIDATION.latest.json"
            Get-SourceRecord -Label "TOD Integration Status" -RelativePath "tod/out/context-sync/listener/TOD_INTEGRATION_STATUS.latest.json"
            Get-SourceRecord -Label "TOD Latest Result" -RelativePath "tod/out/context-sync/listener/TOD_MIM_TASK_RESULT.latest.json"
        )
        findings = @("Health must expose the current context-sync validation and latest TOD task/source status.")
    },
    [pscustomobject]@{
        page = "projects"
        route = "/studio/projects"
        status = "source_traceable"
        owner = "MIM + TOD"
        sources = @(
            [pscustomobject]@{ label = "Studio Projects Table"; kind = "database_table"; path = "studio_projects"; exists = $true; last_write_utc = ""; generated_at = ""; status = "queried_by_page"; bytes = 0 }
            [pscustomobject]@{ label = "Studio Project Events Table"; kind = "database_table"; path = "studio_project_events"; exists = $true; last_write_utc = ""; generated_at = ""; status = "queried_by_page"; bytes = 0 }
            Get-SourceRecord -Label "TOD Latest Result" -RelativePath "tod/out/context-sync/listener/TOD_MIM_TASK_RESULT.latest.json"
        )
        findings = @("Project counts, progress, movement, and Dave-needed flags must show DB/table and event-source accountability.")
    },
    [pscustomobject]@{
        page = "apps"
        route = "/studio/apps"
        status = "source_traceable"
        owner = "TOD"
        sources = @(
            [pscustomobject]@{ label = "App Source Registry"; kind = "code_registry"; path = "tmp_remote_mim/core/routers/studio.py::APP_SOURCE_REGISTRY"; exists = $true; last_write_utc = ""; generated_at = ""; status = "registered"; bytes = 0 }
            Get-SourceRecord -Label "TOD App Source Scan" -RelativePath "runtime_remote_training/MIM_TOD_APP_SOURCE_SCAN.latest.json"
            Get-SourceRecord -Label "AgentMIM Verification" -RelativePath "shared_state/agentmim/comm_app_verification.latest.json"
        )
        findings = @("Apps must separate registered source, TOD scan evidence, and DB binding proof.")
    },
    [pscustomobject]@{
        page = "reports"
        route = "/studio/reports"
        status = "source_traceable"
        owner = "MIM"
        sources = @(
            [pscustomobject]@{ label = "Report Dataset Registry"; kind = "code_registry"; path = "tmp_remote_mim/core/routers/studio.py::REPORT_DATASETS"; exists = $true; last_write_utc = ""; generated_at = ""; status = "registered"; bytes = 0 }
            [pscustomobject]@{ label = "Report Canvases Table"; kind = "database_table"; path = "studio_report_canvases"; exists = $true; last_write_utc = ""; generated_at = ""; status = "queried_by_page"; bytes = 0 }
        )
        findings = @("Reports must expose dataset source metadata and generated report source path/API JSON.")
    }
)

$apiRecords = @()
$apiChecks = @(
    @{ Label = "Projects State API"; Path = "/studio/api/projects/state" },
    @{ Label = "Apps State API"; Path = "/studio/api/apps/state" },
    @{ Label = "Reports State API"; Path = "/studio/api/reports/state" }
)
foreach ($check in $apiChecks) {
    $record = Get-ApiRecord -Label $check.Label -Path $check.Path
    if ($null -ne $record) { $apiRecords += $record }
}

$allSources = @($pages | ForEach-Object { $_.sources }) + $apiRecords
$missingSources = @($allSources | Where-Object { -not [bool]$_.exists })
$contextFindings = @($validation.findings)
$remainingSuspects = @($contextFindings | Where-Object {
    $status = Get-JsonString -Object $_ -Name "classification"
    -not [string]::IsNullOrWhiteSpace($status) -and $status -notmatch "superseded"
})

$payload = [ordered]@{
    artifact_id = "MIM-STUDIO-DATA-AUDIT-AND-RECONCILIATION-RESULT"
    objective_id = "MIM-STUDIO-DATA-AUDIT-AND-RECONCILIATION-V1"
    generated_at = $nowIso
    status = if ($missingSources.Count -eq 0 -and $remainingSuspects.Count -eq 0) { "passed_with_watch" } else { "needs_attention" }
    owner = "TOD"
    accountable_to = "MIM"
    operator = "Dave"
    summary = "Studio pages now have a source-led audit target: every displayed metric should resolve to a DB table, artifact, registry, or API source."
    latest_tod_task = [ordered]@{
        request_id = Get-JsonString -Object $latestTodResult -Name "request_id"
        task_id = Get-JsonString -Object $latestTodResult -Name "task_id"
        status = Get-JsonString -Object $latestTodResult -Name "status"
    }
    context_sync = [ordered]@{
        validation_status = Get-JsonString -Object $validation -Name "status"
        sync_status = Get-JsonString -Object $syncStatus -Name "state"
        suspect_count = $remainingSuspects.Count
    }
    training = [ordered]@{
        scoreboard_generated_at = Get-JsonString -Object $trainingScoreboard -Name "generated_at"
        scoreboard_status = Get-JsonString -Object $trainingScoreboard -Name "status"
    }
    pages = $pages
    studio_api_checks = $apiRecords
    missing_sources = $missingSources
    accountability_function = [ordered]@{
        script = "scripts/Invoke-StudioDataAudit.ps1"
        cadence = "run after context-sync truth repair, after Studio page changes, and during TOD periodic accountability checks"
        outputs = @($OutputPath, $MarkdownOutputPath)
        owner = "TOD"
    }
    next_action = "Keep this objective active until Studio Training, Health, Projects, Apps, and Reports expose the audit artifact and source rows in the UI."
}

$outputAbs = Resolve-RepoPath -PathValue $OutputPath
$markdownAbs = Resolve-RepoPath -PathValue $MarkdownOutputPath
Write-JsonFile -PathValue $outputAbs -Payload $payload

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Studio Data Audit And Reconciliation V1")
$lines.Add("")
$lines.Add("- Status: $($payload.status)")
$lines.Add("- Generated: $nowIso")
$lines.Add("- Context-sync validation: $($payload.context_sync.validation_status)")
$lines.Add("- Latest TOD task: $($payload.latest_tod_task.task_id) / $($payload.latest_tod_task.status)")
$lines.Add("")
$lines.Add("## Pages")
foreach ($page in $pages) {
    $lines.Add("")
    $lines.Add("### $($page.page)")
    $lines.Add("- Route: $($page.route)")
    $lines.Add("- Status: $($page.status)")
    foreach ($source in $page.sources) {
        $lines.Add("- Source: $($source.label) :: $($source.kind) :: $($source.path) :: $($source.status)")
    }
}
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($markdownAbs, (($lines -join "`n") + "`n"), $utf8NoBom)

if ($EmitJson) {
    ($payload | ConvertTo-Json -Depth 40) | Write-Output
}
else {
    "studio_data_audit_status=$($payload.status)"
    "pages=$($pages.Count)"
    "missing_sources=$($missingSources.Count)"
    "output=$outputAbs"
}
