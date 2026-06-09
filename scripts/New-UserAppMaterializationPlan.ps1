param(
    [Parameter(Mandatory = $true)][string]$ManifestPath,
    [string]$OutputPath = "",
    [string]$Source = "CodexSupervised::UserAppMaterializationPlan"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

function Convert-ToRepoPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return $PathValue
    }
    return (Join-Path $repoRoot $PathValue)
}

function Convert-ToRepoRelativePath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    $fullPath = [System.IO.Path]::GetFullPath((Convert-ToRepoPath -PathValue $PathValue))
    $root = [System.IO.Path]::GetFullPath($repoRoot)
    if (-not $fullPath.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside repo root: $PathValue"
    }
    return ($fullPath.Substring($root.Length).TrimStart('\', '/') -replace '\\', '/')
}

function Get-DefaultDataObjects {
    param([Parameter(Mandatory = $true)][string]$Slug)
    switch ($Slug) {
        "simple_appointment_scheduler" { return @("appointment", "contact", "reminder", "calendar_connection") }
        "inventory_mini_manager" { return @("inventory_item", "stock_adjustment", "supplier", "location") }
        "receipt_expense_tracker" { return @("receipt", "expense", "category", "export_batch") }
        "service_ticket_tracker" { return @("ticket", "customer", "technician_note", "resolution") }
        "lead_pipeline_board" { return @("lead", "pipeline_stage", "activity", "opportunity") }
        "staff_task_board" { return @("task", "team_member", "assignment", "comment") }
        "small_business_crm" { return @("contact", "company", "note", "follow_up") }
        "content_calendar" { return @("content_item", "channel", "campaign", "publishing_slot") }
        "document_request_portal" { return @("document_request", "uploaded_file", "requester", "review_status") }
        "business_meal_tracker" { return @("meal", "receipt", "attendee", "business_purpose") }
        default { return @("record", "activity", "setting", "audit_log") }
    }
}

$manifestAbs = Convert-ToRepoPath -PathValue $ManifestPath
if (-not (Test-Path -Path $manifestAbs -PathType Leaf)) {
    throw "Published preview manifest not found: $ManifestPath"
}

$manifest = Get-Content -Path $manifestAbs -Raw | ConvertFrom-Json
$slug = [string]$manifest.slug
if ([string]::IsNullOrWhiteSpace($slug)) {
    throw "Manifest is missing slug."
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = "runtime/shared/user_app_materialization/$slug/materialization.plan.json"
}
$outputAbs = Convert-ToRepoPath -PathValue $OutputPath
New-Item -ItemType Directory -Path (Split-Path -Parent $outputAbs) -Force | Out-Null

$appName = [string]$manifest.app_name
$stylePreset = if ($manifest.PSObject.Properties["style_preset"]) { [string]$manifest.style_preset } else { "clean_saas" }
$visualTheme = if ($manifest.PSObject.Properties["visual_theme"]) { $manifest.visual_theme } else { [pscustomobject]@{
        background = "#f7fafc"
        panel = "#ffffff"
        ink = "#102033"
        muted = "#5a6b7d"
        accent = "#1d9bf0"
        accent_2 = "#16a34a"
        font_stack = "Inter, Segoe UI, Arial, sans-serif"
    } }
$dataObjects = @()
if ($manifest.PSObject.Properties["data_model"]) {
    $dataObjects = @($manifest.data_model.objects | ForEach-Object { [string]$_.name })
}
if (@($dataObjects).Count -eq 0) {
    $dataObjects = @(Get-DefaultDataObjects -Slug $slug)
}

$payload = [ordered]@{
    artifact_type = "user_app_materialization_plan_v1"
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = $Source
    app_name = $appName
    slug = $slug
    style_preset = $stylePreset
    visual_theme = $visualTheme
    source_manifest = Convert-ToRepoRelativePath -PathValue $manifestAbs
    output_path = Convert-ToRepoRelativePath -PathValue $outputAbs
    current_state = "published_static_preview_ready"
    honest_boundary = "This is not a production hosted app until repo, database, auth, deploy target, and approval gates are selected."
    required_foundation = [ordered]@{
        front_page = "What the app does, who it is for, primary call to action."
        login = "Email/password login, forgot password, reset password, verification flow."
        dashboard = "Primary work queue, key metrics, and next action prompts."
        help_support = "How to use the app plus scoped MIM Help for app-only questions."
        user_settings = "Profile, preferences, password reset, notifications, privacy choices."
        admin_backend = "Required if multi-user, subscriptions, team management, or audit review are enabled."
    }
    materialization_decisions = [ordered]@{
        app_type = "Decide single-user, multi-user, or team/admin model before backend generation."
        platforms = "Decide desktop web, mobile web, or installable mobile shell."
        auth_provider = "Choose local auth, hosted auth provider, or existing MIMTOD account identity."
        data_backend = "Choose Postgres, SQLite, managed app DB, or local-only prototype mode."
        payments = "Decide free, subscription, one-time purchase, or no billing."
        deploy_target = "Choose local static preview, hosted preview, production host, or Git-only export."
        repo_target = "Choose generated repo path, user Git account, or MIM-managed repo."
    }
    proposed_repo = [ordered]@{
        files = @(
            "README.md",
            "package.json",
            "src/app/layout.tsx",
            "src/app/page.tsx",
            "src/app/login/page.tsx",
            "src/app/dashboard/page.tsx",
            "src/app/help/page.tsx",
            "src/app/settings/page.tsx",
            "src/lib/auth.ts",
            "src/lib/db.ts",
            "src/lib/audit-log.ts",
            "src/components/MimHelpPanel.tsx",
            "tests/acceptance.spec.ts"
        )
        data_objects = @($dataObjects)
        api_routes = @($dataObjects | ForEach-Object { "/api/$($_)" })
    }
    gates = [ordered]@{
        repo_manifest = "needed"
        backend_schema = "needed"
        auth_flow = "needed"
        acceptance_tests = "needed"
        preview_deploy = "not_selected"
        production_deploy = "not_selected"
        rollback_plan = "needed"
        user_approval = "needed"
    }
    tod_next_action = "Create the generated repo manifest for this app, then materialize one foundation screen and one primary workflow with tests."
    mim_next_action = "Ask only unresolved materialization questions; otherwise choose safe defaults and keep the app moving."
    dave_needed = "no"
}

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($outputAbs, ($payload | ConvertTo-Json -Depth 30), $utf8NoBom)
$payload | ConvertTo-Json -Depth 12
