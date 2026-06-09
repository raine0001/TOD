param(
    [Parameter(Mandatory = $true)][string]$IntakePath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [AllowEmptyString()][string]$AppName,
    [AllowEmptyString()][string]$AppType,
    [AllowEmptyString()][string]$Source
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Source)) {
    $Source = 'tod-local-app-prototype-factory'
}

$repoRoot = Split-Path -Parent $PSScriptRoot

function Convert-ToRepoPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return $PathValue
    }
    return (Join-Path $repoRoot $PathValue)
}

function Convert-ToSlug {
    param([Parameter(Mandatory = $true)][string]$Text)

    $slug = ([string]$Text).Trim().ToLowerInvariant()
    $slug = $slug -replace "[^a-z0-9]+", "_"
    $slug = $slug.Trim("_")
    if ([string]::IsNullOrWhiteSpace($slug)) {
        return "user_app"
    }
    return $slug
}

function Get-PropertyValue {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string[]]$Names,
        $Default = $null
    )

    foreach ($name in $Names) {
        if ($null -ne $Object -and $Object.PSObject.Properties[$name] -and $null -ne $Object.$name) {
            return $Object.$name
        }
    }
    return $Default
}

function Convert-ToArray {
    param($Value)

    if ($null -eq $Value) {
        return @()
    }
    if ($Value -is [string]) {
        if ([string]::IsNullOrWhiteSpace($Value)) {
            return @()
        }
        return @($Value)
    }
    return @($Value)
}

function New-Screen {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Title,
        [string[]]$Features = @()
    )

    [ordered]@{
        key = $Key
        title = $Title
        purpose = ""
        features = @($Features)
    }
}

function Ensure-Screen {
    param(
        [Parameter(Mandatory = $true)]$Screens,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Title,
        [string[]]$Features = @()
    )

    $existing = @($Screens | Where-Object { $_.key -eq $Key -or (([string]$_.title).ToLowerInvariant() -eq $Title.ToLowerInvariant()) })
    if (@($existing).Count -gt 0) {
        return @($Screens)
    }
    return @($Screens) + (New-Screen -Key $Key -Title $Title -Features $Features)
}

function Get-AppVisualTheme {
    param(
        [Parameter(Mandatory = $true)][string]$AppName,
        [AllowEmptyString()][string]$StyleDirection
    )

    $signature = (([string]$AppName) + " " + ([string]$StyleDirection)).ToLowerInvariant()
    if ($signature -match "content|marketing|editorial") {
        return [ordered]@{ preset = "editorial_calendar"; background = "#0f172a"; panel = "#172033"; ink = "#f8fafc"; muted = "#bad0e8"; accent = "#e879f9"; accent_2 = "#38bdf8"; font_stack = "Manrope, Segoe UI, Arial, sans-serif"; banner_prompt = "editorial calendar with channel colors draft cards and performance notes" }
    }
    if ($signature -match "document|portal|request|upload checklist") {
        return [ordered]@{ preset = "secure_portal"; background = "#07111f"; panel = "#0f1b2d"; ink = "#f2f8ff"; muted = "#b2c4d8"; accent = "#14b8a6"; accent_2 = "#93c5fd"; font_stack = "Source Sans 3, Segoe UI, Arial, sans-serif"; banner_prompt = "secure document portal with upload checklist and review badges" }
    }
    if ($signature -match "appointment|calendar|schedule") {
        return [ordered]@{ preset = "calendar_bright"; background = "#f8fbff"; panel = "#ffffff"; ink = "#102033"; muted = "#5a6b7d"; accent = "#1d9bf0"; accent_2 = "#16a34a"; font_stack = "Inter, Segoe UI, Arial, sans-serif"; banner_prompt = "clean calendar dashboard with appointment cards and sync health indicators" }
    }
    if ($signature -match "call|phone|screen|spam|voice") {
        return [ordered]@{ preset = "mobile_call_guard"; background = "#050816"; panel = "#101528"; ink = "#f7fbff"; muted = "#aeb9d4"; accent = "#22d3ee"; accent_2 = "#f43f5e"; font_stack = "Inter, Segoe UI, Arial, sans-serif"; banner_prompt = "mobile incoming call screen with voice assistant waveform spam badge and message summary card" }
    }
    if ($signature -match "chef|recipe|meal|cook|food|pantry|nutrition") {
        return [ordered]@{ preset = "chef_recipe_mobile"; background = "#fff7ed"; panel = "#ffffff"; ink = "#2b2118"; muted = "#7a6655"; accent = "#f97316"; accent_2 = "#16a34a"; font_stack = "Nunito Sans, Segoe UI, Arial, sans-serif"; banner_prompt = "warm recipe assistant with meal cards pantry checklist nutrition chips and camera dish recreation" }
    }
    if ($signature -match "inventory|warehouse|stock") {
        return [ordered]@{ preset = "warehouse_clipboard"; background = "#10140f"; panel = "#182016"; ink = "#f3f7ec"; muted = "#b7c4aa"; accent = "#f59e0b"; accent_2 = "#84cc16"; font_stack = "Roboto Condensed, Segoe UI, Arial, sans-serif"; banner_prompt = "compact warehouse inventory clipboard with low stock amber highlights" }
    }
    if ($signature -match "meal|attendee|substantiation|business purpose") {
        return [ordered]@{ preset = "meal_substantiation"; background = "#11130c"; panel = "#1d2115"; ink = "#fbf8ef"; muted = "#d4c9a8"; accent = "#d97706"; accent_2 = "#22c55e"; font_stack = "Libre Franklin, Segoe UI, Arial, sans-serif"; banner_prompt = "business meal receipt capture with attendee cards and audit substantiation checklist" }
    }
    if ($signature -match "receipt|expense|meal|tax|accounting") {
        return [ordered]@{ preset = "financial_receipt"; background = "#07130f"; panel = "#102018"; ink = "#eefcf3"; muted = "#a7c5b4"; accent = "#22c55e"; accent_2 = "#38bdf8"; font_stack = "Inter, Segoe UI, Arial, sans-serif"; banner_prompt = "mobile receipt capture with audit ready badges and financial summary cards" }
    }
    if ($signature -match "ticket|support|service") {
        return [ordered]@{ preset = "service_console"; background = "#0d1117"; panel = "#151b23"; ink = "#f0f6fc"; muted = "#9fb1c1"; accent = "#f97316"; accent_2 = "#60a5fa"; font_stack = "IBM Plex Sans, Segoe UI, Arial, sans-serif"; banner_prompt = "service desk console with priority badges and resolution timeline" }
    }
    if ($signature -match "lead|pipeline|sales") {
        return [ordered]@{ preset = "sales_pipeline"; background = "#120f0a"; panel = "#1f1a10"; ink = "#fff7e6"; muted = "#d5c19a"; accent = "#fbbf24"; accent_2 = "#f472b6"; font_stack = "Aptos, Segoe UI, Arial, sans-serif"; banner_prompt = "sales pipeline board with value chips and stage columns" }
    }
    if ($signature -match "staff|task|team") {
        return [ordered]@{ preset = "team_ops"; background = "#0a1220"; panel = "#111c2d"; ink = "#edf6ff"; muted = "#a9bdd3"; accent = "#818cf8"; accent_2 = "#2dd4bf"; font_stack = "Segoe UI, Inter, Arial, sans-serif"; banner_prompt = "team task board with owner avatars due date heat and blocker lane" }
    }
    if ($signature -match "crm|relationship|client") {
        return [ordered]@{ preset = "relationship_crm"; background = "#111827"; panel = "#1f2937"; ink = "#f9fafb"; muted = "#c7d2fe"; accent = "#a78bfa"; accent_2 = "#f472b6"; font_stack = "Nunito Sans, Segoe UI, Arial, sans-serif"; banner_prompt = "relationship dashboard with warm contact cards and interaction timeline" }
    }
    return [ordered]@{ preset = "clean_saas"; background = "#071019"; panel = "#101b29"; ink = "#eef7ff"; muted = "#a9c1d9"; accent = "#65e4d3"; accent_2 = "#9ad0ff"; font_stack = "Inter, Segoe UI, Arial, sans-serif"; banner_prompt = "clean app dashboard with product cards and workflow highlights" }
}

$resolvedIntakePath = Convert-ToRepoPath -PathValue $IntakePath
$resolvedOutputPath = Convert-ToRepoPath -PathValue $OutputPath

if (-not (Test-Path -Path $resolvedIntakePath -PathType Leaf)) {
    throw "Intake file was not found: $IntakePath"
}

$intake = Get-Content -Path $resolvedIntakePath -Raw | ConvertFrom-Json
$resolvedAppName = if (-not [string]::IsNullOrWhiteSpace($AppName)) { $AppName } else { [string](Get-PropertyValue -Object $intake -Names @("app_name", "project", "name", "title") -Default "User App") }
$resolvedAppType = if (-not [string]::IsNullOrWhiteSpace($AppType)) { $AppType } else { [string](Get-PropertyValue -Object $intake -Names @("app_type", "category", "type") -Default "User App") }
$slug = Convert-ToSlug -Text $resolvedAppName

$summary = [string](Get-PropertyValue -Object $intake -Names @("summary", "goal", "description") -Default ("Workbench prototype for " + $resolvedAppName + "."))
$targetUsers = [string](Get-PropertyValue -Object $intake -Names @("target_users", "audience") -Default "User to confirm during app intake.")
$workflows = Convert-ToArray (Get-PropertyValue -Object $intake -Names @("workflows", "core_workflows", "required_workflows") -Default @())
$requiredQuestions = Convert-ToArray (Get-PropertyValue -Object $intake -Names @("required_questions", "questions") -Default @())
$integrations = Convert-ToArray (Get-PropertyValue -Object $intake -Names @("required_integrations", "integrations") -Default @())
$acceptance = Convert-ToArray (Get-PropertyValue -Object $intake -Names @("acceptance", "acceptance_checklist", "success_criteria") -Default @())
$styleDirection = [string](Get-PropertyValue -Object $intake -Names @("style_direction", "visual_style", "design_direction") -Default "")
$visualTheme = Get-AppVisualTheme -AppName $resolvedAppName -StyleDirection $styleDirection

$screens = @()
$rawScreens = Get-PropertyValue -Object $intake -Names @("screens", "required_screens") -Default @()
foreach ($screen in Convert-ToArray $rawScreens) {
    if ($screen -is [string]) {
        $screenTitle = [string]$screen
        $screens += (New-Screen -Key (Convert-ToSlug -Text $screenTitle) -Title $screenTitle)
    }
    else {
        $screenKey = [string](Get-PropertyValue -Object $screen -Names @("key") -Default (Convert-ToSlug -Text ([string](Get-PropertyValue -Object $screen -Names @("title", "name") -Default "screen"))))
        $screenTitle = [string](Get-PropertyValue -Object $screen -Names @("title", "name") -Default $screenKey)
        $screenFeatures = Convert-ToArray (Get-PropertyValue -Object $screen -Names @("features") -Default @())
        $screens += [ordered]@{
            key = $screenKey
            title = $screenTitle
            purpose = [string](Get-PropertyValue -Object $screen -Names @("purpose") -Default "")
            features = @($screenFeatures)
        }
    }
}

$screens = Ensure-Screen -Screens $screens -Key "front_page" -Title "Front Page" -Features @("plain_language_value_proposition", "login_or_get_started")
$screens = Ensure-Screen -Screens $screens -Key "login" -Title "Login" -Features @("email_password_login", "forgot_password", "reset_password")
$screens = Ensure-Screen -Screens $screens -Key "account_setup" -Title "Account Setup" -Features @("workspace_or_profile_setup", "preferences", "password_reset")
$screens = Ensure-Screen -Screens $screens -Key "dashboard" -Title "Dashboard" -Features @("primary_status", "recent_activity", "next_actions")
$screens = Ensure-Screen -Screens $screens -Key "settings" -Title "User Settings" -Features @("profile", "preferences", "password_reset")
$screens = Ensure-Screen -Screens $screens -Key "help_support" -Title "Help / Support" -Features @("how_to_use_app", "mim_app_help")
$screens = Ensure-Screen -Screens $screens -Key "presentation" -Title "Presentation Walkthrough" -Features @("planned_components", "current_demo_path", "completion_summary", "next_steps")

$dataObjects = Get-PropertyValue -Object $intake -Names @("data_objects", "objects", "schema") -Default $null
if ($null -eq $dataObjects) {
    $dataObjects = [ordered]@{
        user = @("id", "name", "email", "role")
        workspace = @("id", "name", "owner_id")
        change_log_entry = @("id", "what_changed", "who_requested_it", "why_it_changed", "created_at")
    }
}

$sampleRecords = Convert-ToArray (Get-PropertyValue -Object $intake -Names @("sample_records", "examples") -Default @())
if (@($sampleRecords).Count -eq 0) {
    $sampleRecords = @(
        [ordered]@{ name = "Sample Record 1"; status = "active"; note = "Replace with real app-specific sample data." },
        [ordered]@{ name = "Sample Record 2"; status = "review"; note = "Used by Workbench preview only." }
    )
}

$intakeLimitations = Convert-ToArray (Get-PropertyValue -Object $intake -Names @("known_limitations", "limitations") -Default @())
$complianceNotes = Convert-ToArray (Get-PropertyValue -Object $intake -Names @("compliance_notes", "safety_notes", "legal_notes") -Default @())
$knownLimitations = @(
    "This is a prototype artifact, not a deployed production app.",
    "External integrations are mocked until credentials and provider gates are selected.",
    "Backend persistence and publish/deploy targets remain follow-on materialization steps."
) + @($intakeLimitations | ForEach-Object { [string]$_ })
if (@($complianceNotes).Count -gt 0) {
    $knownLimitations += @($complianceNotes | ForEach-Object { "Compliance note: {0}" -f [string]$_ })
}
$knownLimitations = @($knownLimitations | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)

if (@($acceptance).Count -eq 0) {
    $acceptance = @(
        "User can understand what the app does from the front page.",
        "User can log in, recover password access, open settings, and find help.",
        "User can complete the primary workflow in a reviewable Workbench preview.",
        "Prototype records remaining backend, integration, legal, billing, mobile, and publish gates honestly."
    )
}

$now = (Get-Date).ToUniversalTime().ToString("o")
$artifact = [ordered]@{
    artifact_type = "user_app_workbench_prototype_v1"
    app_name = $resolvedAppName
    app_type = $resolvedAppType
    generated_at = $now
    status = "app_foundation_prototype"
    generated_by = $Source
    source_intake = ($IntakePath -replace "\\", "/")
    summary = $summary
    target_users = $targetUsers
    classification = [ordered]@{
        user_model = [string](Get-PropertyValue -Object $intake -Names @("user_model") -Default "single_or_multi_user_to_confirm")
        platform = [string](Get-PropertyValue -Object $intake -Names @("platform") -Default "responsive_web")
        admin_backend_required = [bool](Get-PropertyValue -Object $intake -Names @("admin_backend_required") -Default $true)
        integrations = @($integrations)
        billing = [string](Get-PropertyValue -Object $intake -Names @("billing") -Default "unknown_user_to_confirm")
        legal = [string](Get-PropertyValue -Object $intake -Names @("legal") -Default "privacy_terms_required_if_multi_user_public_or_paid")
    }
    required_questions = @($requiredQuestions)
    screens = @($screens)
    workflows = @($workflows)
    data_objects = $dataObjects
    sample_records = @($sampleRecords)
    preview_ui = [ordered]@{
        style_preset = [string]$visualTheme.preset
        style_direction = $styleDirection
        mobile_first = $true
        banner = "upload_or_generate_ready"
        banner_prompt = [string]$visualTheme.banner_prompt
        background = [string]$visualTheme.background
        panel = [string]$visualTheme.panel
        ink = [string]$visualTheme.ink
        muted = [string]$visualTheme.muted
        accent = [string]$visualTheme.accent
        accent_2 = [string]$visualTheme.accent_2
        font_stack = [string]$visualTheme.font_stack
        supports_style_customization = $true
        style_options = @("clean_saas", "warm_service", "clinical", "field_ops", "executive", "consumer_mobile", "creative_studio", "dark_control_room", "high_contrast", "minimal")
    }
    mim_help = [ordered]@{
        scope = "app_specific_help_only"
        sample_questions = @(
            ("How do I use {0}?" -f $resolvedAppName),
            "How do I add a record?",
            "How do I change settings?",
            "What still needs setup before publishing?"
        )
        response_rule = "Answer only questions about using this app preview and its planned workflows."
    }
    presentation_walkthrough = [ordered]@{
        title = ("{0} app walkthrough" -f $resolvedAppName)
        sections = @(
            "Front page and value proposition",
            "Login/account setup",
            "Dashboard",
            "Primary workflow",
            "Detail/review page",
            "Settings",
            "Help with MIM support",
            "Publish/export gates"
        )
        last_minute_change_request = [string](Get-PropertyValue -Object $intake -Names @("last_minute_change_request") -Default "Add one small user-requested refinement and record whether it changes scope.")
    }
    completion_summary = [ordered]@{
        status = "prototype_artifact_ready"
        summary = "App foundation prototype is ready for Workbench rendering and the first interactive workflow slice."
        completed_components = @("intake", "foundation screens", "data object plan", "sample records", "acceptance checklist", "change log", "presentation walkthrough", "MIM help scope")
        remaining_components = @("Workbench UI rendering", "interactive primary workflow", "backend persistence", "publish/export target")
    }
    acceptance_checklist = @($acceptance)
    app_package_contract = [ordered]@{
        must_include = @("README", "frontend", "backend_api_contract", "database_schema", "auth_flow", "settings", "help", "tests", "change_log", "rollback_plan", "publish_gate")
        not_complete_until = @("reviewable_workbench_preview", "primary_workflow_validation", "persistence_plan", "publish_or_export_target_selected")
    }
    change_log = @(
        [ordered]@{
            what_changed = "Generated first app foundation prototype artifact."
            who_requested_it = "MIM/TOD app-build lane"
            why_it_changed = "TOD must produce a real reviewable artifact from intake instead of stopping at package metadata."
            created_at = $now
            scope_changed_yes_no = "no"
            follow_on_task_required = "yes"
            acceptance_changed_yes_no = "yes"
        }
    )
    known_limitations = @($knownLimitations)
    next_bounded_slice = "Render this artifact in Workbench and implement the first app-specific interactive workflow."
    tod_execution_evidence = [ordered]@{
        generator = "scripts/New-UserAppPrototypeArtifact.ps1"
        intake_path = ($IntakePath -replace "\\", "/")
        output_path = ($OutputPath -replace "\\", "/")
        generated_at = $now
    }
}

$outputDir = Split-Path -Parent $resolvedOutputPath
if (-not (Test-Path -Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$json = $artifact | ConvertTo-Json -Depth 40
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($resolvedOutputPath, $json, $utf8NoBom)

$validated = Get-Content -Path $resolvedOutputPath -Raw | ConvertFrom-Json
$checks = @(
    [ordered]@{ name = "output_file_exists"; passed = (Test-Path -Path $resolvedOutputPath -PathType Leaf) },
    [ordered]@{ name = "json_round_trip"; passed = ($null -ne $validated -and $validated.artifact_type -eq "user_app_workbench_prototype_v1") },
    [ordered]@{ name = "foundation_screens_present"; passed = (@($validated.screens | Where-Object { $_.key -in @("front_page", "login", "dashboard", "settings", "help_support") }).Count -ge 5) },
    [ordered]@{ name = "acceptance_present"; passed = (@($validated.acceptance_checklist).Count -gt 0) },
    [ordered]@{ name = "change_log_present"; passed = (@($validated.change_log).Count -gt 0) }
)
$passed = -not (@($checks | Where-Object { -not [bool]$_.passed }).Count)

[pscustomobject]@{
    status = $(if ($passed) { "succeeded" } else { "failed" })
    app_name = $resolvedAppName
    slug = $slug
    intake_path = $resolvedIntakePath
    output_path = $resolvedOutputPath
    files_changed = @($OutputPath -replace "\\", "/")
    tests_run = @($checks | ForEach-Object { [string]$_.name })
    test_results = @($checks | ForEach-Object { if ([bool]$_.passed) { "pass" } else { "fail" } })
    checks = @($checks)
    next_action = "Render the prototype artifact in Workbench and implement the first app-specific interactive workflow."
} | ConvertTo-Json -Depth 20
