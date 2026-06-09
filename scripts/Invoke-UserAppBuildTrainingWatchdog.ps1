param(
    [int]$MaxCycles = 36,
    [int]$IntervalMinutes = 20,
    [switch]$RunOnce,
    [switch]$DeployRemote
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$sharedRoot = Join-Path $repoRoot "runtime/shared"
$statusPath = Join-Path $sharedRoot "USER_APP_DEEP_TRAINING_WATCHDOG.latest.json"
$logPath = Join-Path $sharedRoot "USER_APP_DEEP_TRAINING_WATCHDOG.log.jsonl"
$eventPath = Join-Path $sharedRoot "USER_APP_DEEP_TRAINING_EVENT_V1.latest.json"

function Convert-ToSlug {
    param([Parameter(Mandatory = $true)][string]$Text)
    $slug = $Text.Trim().ToLowerInvariant() -replace '[^a-z0-9]+', '_'
    $slug = $slug.Trim('_')
    if ([string]::IsNullOrWhiteSpace($slug)) { return 'user_app' }
    return $slug
}

function Convert-ToConstantName {
    param([Parameter(Mandatory = $true)][string]$Text)
    return ((Convert-ToSlug -Text $Text).ToUpperInvariant())
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Payload,
        [int]$Depth = 30
    )
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $json = $Payload | ConvertTo-Json -Depth $Depth
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $json, $utf8NoBom)
}

function Read-JsonFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -Path $Path -PathType Leaf)) { return $null }
    try { return (Get-Content -Path $Path -Raw | ConvertFrom-Json) }
    catch { return $null }
}

function Get-AppSpecs {
    return @(
        [ordered]@{
            name = "Simple Appointment Scheduler"; type = "Scheduling"; style = "bright calendar SaaS with clean blue/green accents";
            prompt = "I want a simple appointment scheduler that works on mobile and desktop, syncs with Google/Outlook/ICS calendars, sends invites, supports reminders, and lets appointments be private or shared.";
            workflows = @("set availability", "book appointment", "send invite", "sync calendar", "set reminder", "reschedule")
            objects = @("user", "service", "availability", "appointment", "contact", "calendar_account", "invite", "reminder")
            lastMinuteChange = "Add a month/week/day calendar toggle and a visible sync health card."
        },
        [ordered]@{
            name = "Inventory Mini Manager"; type = "Inventory"; style = "warehouse clipboard feel with compact tables, barcode-inspired accents, and amber low-stock warnings";
            prompt = "I want a small inventory app for a shop or lab that tracks items, quantities, suppliers, reorder thresholds, and low-stock alerts.";
            workflows = @("add item", "adjust quantity", "set reorder threshold", "view low stock", "track supplier")
            objects = @("item", "supplier", "stock_adjustment", "reorder_rule", "location")
            lastMinuteChange = "Add a quick receive-stock action and make low-stock rows visually urgent."
        },
        [ordered]@{
            name = "Receipt Expense Tracker"; type = "Accounting / expenses"; style = "clean financial dashboard with receipt-card thumbnails and green export accents";
            prompt = "I want an expense tracker where users upload receipts, categorize expenses, see monthly totals, flag missing data, and export reports.";
            workflows = @("upload receipt", "extract fields", "categorize expense", "review monthly totals", "export report")
            objects = @("receipt", "expense", "category", "report", "export")
            lastMinuteChange = "Add a missing-data queue and a one-click monthly CSV export preview."
        },
        [ordered]@{
            name = "Service Ticket Tracker"; type = "Support / operations"; style = "service desk console with priority colors and resolution timeline";
            prompt = "I want a service ticket tracker for customer issues, priorities, assigned owners, status changes, and resolution notes.";
            workflows = @("create ticket", "assign owner", "set priority", "update status", "record resolution")
            objects = @("ticket", "customer", "assignee", "priority", "resolution")
            lastMinuteChange = "Add an escalation badge when a high-priority ticket is open too long."
        },
        [ordered]@{
            name = "Lead Pipeline Board"; type = "Sales pipeline"; style = "sales board with stage columns, value chips, and confident dark/gold accents";
            prompt = "I want a lead pipeline app that tracks lead source, stage, value, next action, close probability, and pipeline totals.";
            workflows = @("add lead", "move stage", "set next action", "estimate value", "review pipeline")
            objects = @("lead", "stage", "activity", "pipeline", "forecast")
            lastMinuteChange = "Add drag-style stage movement and show weighted pipeline value."
        },
        [ordered]@{
            name = "Staff Task Board"; type = "Task management"; style = "team operations board with owner avatars, due-date heat, and blocker lanes";
            prompt = "I want a staff task board for tasks, owner, due date, status, blockers, and completion notes.";
            workflows = @("create task", "assign owner", "set due date", "flag blocker", "complete task")
            objects = @("task", "owner", "blocker", "completion_note", "team")
            lastMinuteChange = "Add a blocker review lane and make overdue tasks sort to the top."
        },
        [ordered]@{
            name = "Small Business CRM"; type = "CRM"; style = "relationship dashboard with warm professional cards and interaction history timeline";
            prompt = "I want a small business CRM for companies, contacts, interactions, opportunities, reminders, and relationship history.";
            workflows = @("add company", "add contact", "log interaction", "create opportunity", "set reminder")
            objects = @("company", "contact", "interaction", "opportunity", "reminder")
            lastMinuteChange = "Add a relationship health score and next-best-action recommendation."
        },
        [ordered]@{
            name = "Content Calendar"; type = "Marketing / content"; style = "editorial calendar with channel colors, draft cards, and performance notes";
            prompt = "I want a content calendar for post ideas, channels, publish dates, status, and performance notes.";
            workflows = @("create post idea", "assign channel", "schedule date", "track status", "record performance")
            objects = @("post", "channel", "schedule", "performance_note", "campaign")
            lastMinuteChange = "Add channel filter chips and a monthly calendar preview."
        },
        [ordered]@{
            name = "Document Request Portal"; type = "Portal / document workflow"; style = "secure client portal with checklist progress, upload states, and review badges";
            prompt = "I want a document request portal for document requests, upload checklist, admin review, missing items, and approval status.";
            workflows = @("create request", "upload document", "review submission", "mark missing item", "approve packet")
            objects = @("request", "document", "checklist_item", "review", "approval")
            lastMinuteChange = "Add a client-facing checklist progress bar and missing-items email draft."
        },
        [ordered]@{
            name = "Business Meal Tracker"; type = "Expense / tax substantiation"; style = "mobile receipt capture with audit-ready badges, calm financial colors, and itemized receipt panels";
            prompt = "I want a business meal tracker where users photograph receipts, OCR extracts receipt details, and MIM asks attendees, relationship, purpose, and missing substantiation questions.";
            workflows = @("add meal", "capture receipt", "extract fields", "ask substantiation questions", "flag missing details", "export meal log")
            objects = @("meal", "receipt", "receipt_line_item", "attendee", "business_purpose", "export")
            lastMinuteChange = "Add an audit-ready badge and a missing-substantiation queue."
        }
    )
}

function New-AppIntakeArtifact {
    param([Parameter(Mandatory = $true)]$Spec)
    $constant = Convert-ToConstantName -Text ([string]$Spec.name)
    $path = Join-Path $sharedRoot ("{0}_INTAKE_V1.latest.json" -f $constant)
    if (Test-Path -Path $path -PathType Leaf) { return $path }
    $payload = [ordered]@{
        artifact_type = "user_app_intake_v1"
        app_name = [string]$Spec.name
        app_type = [string]$Spec.type
        summary = [string]$Spec.prompt
        target_users = "User to confirm during intake; MIM may infer a practical small-business default for training."
        user_model = "single_user_first_multi_user_ready"
        platform = "responsive_web_mobile_first"
        admin_backend_required = $true
        billing = "unknown_user_to_confirm"
        legal = "privacy_terms_required_if_public_multi_user_or_paid"
        style_direction = [string]$Spec.style
        required_questions = @(
            "Is this single-user or multi-user?",
            "Should this target mobile, desktop/web, or both?",
            "Does it need admin tools for users, roles, billing, or account management?",
            "Does it need privacy, terms, cookie notice, or cancellation/subscription policy?",
            "Should MIM generate banner/graphics or should the user upload branding?",
            "Which style preset should be used first?",
            "What is the first workflow that must be fully interactive?"
        )
        screens = @(
            @{ key = "front_page"; title = "Front Page"; purpose = "Explain what the app does and route to login/get started."; features = @("value_proposition", "login_or_get_started", "style_signal") },
            @{ key = "login"; title = "Login"; purpose = "Authenticate users."; features = @("email_password_login", "forgot_password", "reset_password") },
            @{ key = "dashboard"; title = "Dashboard"; purpose = "Show current status, next actions, and primary app metrics."; features = @("summary_cards", "next_actions", "recent_activity") },
            @{ key = "core_workflow"; title = "Core Workflow"; purpose = "Let the user complete the app's main job."; features = @($Spec.workflows) },
            @{ key = "detail_view"; title = "Detail View"; purpose = "Review and edit one record."; features = @("record_details", "history", "change_log") },
            @{ key = "settings"; title = "Settings"; purpose = "Manage profile, preferences, password, exports, and integrations."; features = @("profile", "preferences", "password_reset") },
            @{ key = "help_support"; title = "Help / Support"; purpose = "Explain how to use the app and provide MIM app-specific help."; features = @("how_to_use_app", "mim_app_help", "support_contact") },
            @{ key = "presentation"; title = "Presentation Walkthrough"; purpose = "Walk the user through all planned components and current limitations."; features = @("planned_components", "completion_summary", "next_steps") }
        )
        workflows = @($Spec.workflows)
        data_objects = [ordered]@{}
        sample_records = @()
        acceptance_checklist = @(
            "App has a front page, login, forgot/reset password, dashboard, settings, help/support, presentation walkthrough, and completion summary.",
            "App has a unique visual style direction and app-specific sample records.",
            "App has one primary workflow represented as an interactive Workbench plan.",
            "App has MIM app-specific help, not generic MIM platform help.",
            "App records a last-minute change request and shows how MIM/TOD adjusted."
        )
        last_minute_change_request = [string]$Spec.lastMinuteChange
    }
    foreach ($objectName in @($Spec.objects)) {
        $payload.data_objects[$objectName] = @("id", "name", "status", "created_at", "updated_at")
    }
    for ($i = 1; $i -le 3; $i++) {
        $payload.sample_records += [ordered]@{ name = ("{0} Sample {1}" -f $Spec.name, $i); status = @("active", "review", "complete")[$i - 1]; note = "Training sample record for Workbench presentation." }
    }
    Write-JsonFile -Path $path -Payload $payload -Depth 30
    return $path
}

function Invoke-TodPrototypeTask {
    param(
        [Parameter(Mandatory = $true)]$Spec,
        [Parameter(Mandatory = $true)][string]$IntakePath,
        [Parameter(Mandatory = $true)][int]$CycleNumber
    )
    $slug = Convert-ToSlug -Text ([string]$Spec.name)
    $constant = Convert-ToConstantName -Text ([string]$Spec.name)
    $targetRel = "runtime/shared/user_app_builds/$slug/${constant}_PROTOTYPE.latest.json"
    $targetAbs = Join-Path $repoRoot ($targetRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    $intakeRel = (($IntakePath.Substring($repoRoot.Length)).TrimStart('\') -replace '\\', '/')
    $stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmss")
    $taskId = "{0}-prototype-artifact-watchdog-c{1}-{2}" -f $slug, $CycleNumber, $stamp
    $scope = "Generate $targetRel from $intakeRel using the local user app prototype artifact factory. This is a user_app_build Workbench prototype artifact and app foundation task. Include unique style direction, foundation screens, primary workflow, Help with MIM support, presentation walkthrough, completion summary, last-minute change request, acceptance checklist, and change log. Style direction: $($Spec.style). User prompt: $($Spec.prompt)"
    $acceptance = "TOD generated the prototype artifact through LocalExecutionEngine user_app_prototype_artifact_generation; JSON round-trip passes; foundation screens are present; acceptance and change log are present; MIM/TOD did not mark complete without Workbench/presentation/help/completion evidence."
    $result = & (Join-Path $repoRoot "scripts/TOD.ps1") execute-chat-task `
        -ObjectiveId "3466" `
        -TaskId $taskId `
        -RequestId $taskId `
        -Title ("Generate {0} Workbench prototype artifact" -f $Spec.name) `
        -Description ("MIM acts as product manager and TOD acts as builder for {0}. Codex supervises only." -f $Spec.name) `
        -Scope $scope `
        -AcceptanceCriteria $acceptance `
        -TaskCategory "user_app_build" `
        -AssignedExecutor "tod" `
        -TargetFile $targetRel `
        -ExecutionMode sync
    $artifactExists = Test-Path -Path $targetAbs -PathType Leaf
    return [ordered]@{
        task_id = $taskId
        target = $targetRel
        artifact_exists = $artifactExists
        result_seen = $null -ne $result
    }
}

function Invoke-TodPublishPreviewTask {
    param(
        [Parameter(Mandatory = $true)]$Spec,
        [Parameter(Mandatory = $true)][int]$CycleNumber
    )
    $slug = Convert-ToSlug -Text ([string]$Spec.name)
    $constant = Convert-ToConstantName -Text ([string]$Spec.name)
    $prototypeRel = "runtime/shared/user_app_builds/$slug/${constant}_PROTOTYPE.latest.json"
    $manifestRel = "runtime/shared/user_app_published/$slug/package.manifest.json"
    $manifestAbs = Join-Path $repoRoot ($manifestRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    $stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmss")
    $taskId = "{0}-publish-preview-watchdog-c{1}-{2}" -f $slug, $CycleNumber, $stamp
    $scope = "Publish a Workbench presentation preview package for $($Spec.name) from $prototypeRel into $manifestRel. This is a user_app_build published preview package and package manifest task with preview HTML, README, MIM help, presentation walkthrough, and completion summary evidence. Production deploy remains gated until a deploy target is selected."
    $acceptance = "TOD generated package.manifest.json through LocalExecutionEngine user_app_published_preview_generation; preview.html exists; completion_summary.json exists; README.md exists; manifest JSON round-trip passes; production deploy remains honestly gated until target selected."
    $result = & (Join-Path $repoRoot "scripts/TOD.ps1") execute-chat-task `
        -ObjectiveId "3466" `
        -TaskId $taskId `
        -RequestId $taskId `
        -Title ("Publish {0} Workbench preview package" -f $Spec.name) `
        -Description ("MIM acts as product manager and TOD publishes the reviewable preview package for {0}. Codex supervises only." -f $Spec.name) `
        -Scope $scope `
        -AcceptanceCriteria $acceptance `
        -TaskCategory "user_app_build" `
        -AssignedExecutor "tod" `
        -TargetFile $manifestRel `
        -ExecutionMode sync
    $manifestExists = Test-Path -Path $manifestAbs -PathType Leaf
    return [ordered]@{
        task_id = $taskId
        target = $manifestRel
        artifact_exists = $manifestExists
        result_seen = $null -ne $result
    }
}

function Get-AppStatus {
    param([Parameter(Mandatory = $true)]$Spec)
    $slug = Convert-ToSlug -Text ([string]$Spec.name)
    $constant = Convert-ToConstantName -Text ([string]$Spec.name)
    $targetRel = "runtime/shared/user_app_builds/$slug/${constant}_PROTOTYPE.latest.json"
    $targetAbs = Join-Path $repoRoot ($targetRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    $artifact = Read-JsonFile -Path $targetAbs
    $hasHelp = $false
    $hasPresentation = $false
    $hasSummary = $false
    if ($artifact) {
        $screenKeys = @($artifact.screens | ForEach-Object { [string]$_.key })
        $hasHelp = $screenKeys -contains "help_support"
        $hasPresentation = (($screenKeys -contains "presentation") -or ($artifact.PSObject.Properties.Name -contains "presentation_walkthrough"))
        $hasSummary = (($artifact.PSObject.Properties.Name -contains "completion_summary") -or -not [string]::IsNullOrWhiteSpace([string]$artifact.summary))
    }
    return [ordered]@{
        app_name = [string]$Spec.name
        target = $targetRel
        artifact_exists = [bool]$artifact
        generated_by = if ($artifact -and $artifact.PSObject.Properties['generated_by']) { [string]$artifact.generated_by } else { "" }
        has_help = $hasHelp
        has_presentation = $hasPresentation
        has_completion_summary = $hasSummary
        status = if ($artifact -and $hasHelp -and $hasPresentation -and $hasSummary) { "prototype_ready" } elseif ($artifact) { "artifact_needs_enrichment" } else { "needs_tod_generation" }
    }
}

function Get-AppPublishStatus {
    param([Parameter(Mandatory = $true)]$Spec)
    $slug = Convert-ToSlug -Text ([string]$Spec.name)
    $manifestRel = "runtime/shared/user_app_published/$slug/package.manifest.json"
    $manifestAbs = Join-Path $repoRoot ($manifestRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    $manifest = Read-JsonFile -Path $manifestAbs
    $previewExists = $false
    $summaryExists = $false
    $readmeExists = $false
    $gatesReady = $false
    $interactiveReady = $false
    $lastMinuteChangeVisible = $false
    if ($manifest) {
        foreach ($pair in @(
                @{ name = "previewExists"; path = if ($manifest.PSObject.Properties["preview_path"]) { [string]$manifest.preview_path } else { "" } },
                @{ name = "summaryExists"; path = if ($manifest.PSObject.Properties["completion_summary_path"]) { [string]$manifest.completion_summary_path } else { "" } },
                @{ name = "readmeExists"; path = if ($manifest.PSObject.Properties["readme_path"]) { [string]$manifest.readme_path } else { "" } }
            )) {
            if (-not [string]::IsNullOrWhiteSpace([string]$pair.path)) {
                $absolute = Join-Path $repoRoot (([string]$pair.path) -replace '/', [System.IO.Path]::DirectorySeparatorChar)
                $exists = Test-Path -Path $absolute -PathType Leaf
                switch ([string]$pair.name) {
                    "previewExists" { $previewExists = $exists }
                    "summaryExists" { $summaryExists = $exists }
                    "readmeExists" { $readmeExists = $exists }
                }
            }
        }
        if ($manifest.PSObject.Properties["gates"]) {
            $gatesReady = (
                [string]$manifest.gates.presentation_walkthrough -eq "ready" -and
                [string]$manifest.gates.mim_help -eq "ready" -and
                [string]$manifest.gates.completion_summary -eq "ready"
            )
            $interactiveReady = ([string]$manifest.gates.interactive_workflow_preview -eq "ready")
            $lastMinuteChangeVisible = ([string]$manifest.gates.last_minute_change_visible -eq "ready")
        }
    }
    $status = if ($manifest -and [string]$manifest.status -eq "published_preview_ready" -and $previewExists -and $summaryExists -and $readmeExists -and $gatesReady -and $interactiveReady -and $lastMinuteChangeVisible) {
        "published_preview_ready"
    }
    elseif ($manifest) {
        "published_preview_needs_repair"
    }
    else {
        "needs_publish_preview"
    }
    return [ordered]@{
        app_name = [string]$Spec.name
        target = $manifestRel
        manifest_exists = [bool]$manifest
        status = $status
        source = if ($manifest -and $manifest.PSObject.Properties["source"]) { [string]$manifest.source } else { "" }
        preview_exists = $previewExists
        completion_summary_exists = $summaryExists
        readme_exists = $readmeExists
        gates_ready = $gatesReady
        interactive_workflow_preview = $interactiveReady
        last_minute_change_visible = $lastMinuteChangeVisible
        production_deploy = if ($manifest -and $manifest.PSObject.Properties["gates"]) { [string]$manifest.gates.production_deploy } else { "" }
    }
}

function Get-AppMaterializationStatus {
    param([Parameter(Mandatory = $true)]$Spec)
    $slug = Convert-ToSlug -Text ([string]$Spec.name)
    $planRel = "runtime/shared/user_app_materialization/$slug/materialization.plan.json"
    $planAbs = Join-Path $repoRoot ($planRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    $plan = Read-JsonFile -Path $planAbs
    $foundationReady = $false
    $nextActionReady = $false
    if ($plan) {
        $foundationReady = (
            $plan.PSObject.Properties["required_foundation"] -and
            $plan.required_foundation.PSObject.Properties["login"] -and
            $plan.required_foundation.PSObject.Properties["dashboard"] -and
            $plan.required_foundation.PSObject.Properties["help_support"]
        )
        $nextActionReady = -not [string]::IsNullOrWhiteSpace([string]$plan.tod_next_action)
    }
    $status = if ($plan -and [string]$plan.artifact_type -eq "user_app_materialization_plan_v1" -and $foundationReady -and $nextActionReady) {
        "materialization_plan_ready"
    }
    elseif ($plan) {
        "materialization_plan_needs_repair"
    }
    else {
        "needs_materialization_plan"
    }
    return [ordered]@{
        app_name = [string]$Spec.name
        target = $planRel
        plan_exists = [bool]$plan
        status = $status
        foundation_contract = $foundationReady
        tod_next_action = if ($plan -and $plan.PSObject.Properties["tod_next_action"]) { [string]$plan.tod_next_action } else { "" }
        dave_needed = if ($plan -and $plan.PSObject.Properties["dave_needed"]) { [string]$plan.dave_needed } else { "" }
        production_deploy = if ($plan -and $plan.PSObject.Properties["gates"]) { [string]$plan.gates.production_deploy } else { "" }
    }
}

function Get-AppRepoSkeletonStatus {
    param([Parameter(Mandatory = $true)]$Spec)
    $slug = Convert-ToSlug -Text ([string]$Spec.name)
    $manifestRel = "runtime/shared/user_app_repos/$slug/repo.manifest.json"
    $manifestAbs = Join-Path $repoRoot ($manifestRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    $manifest = Read-JsonFile -Path $manifestAbs
    $requiredFiles = @("src/app/page.tsx", "src/app/login/page.tsx", "src/app/dashboard/page.tsx", "src/app/help/page.tsx", "src/app/settings/page.tsx", "tests/acceptance.spec.ts")
    $foundationReady = $false
    if ($manifest) {
        $manifestFiles = @($manifest.files | ForEach-Object { [string]$_ })
        $foundationReady = (@($requiredFiles | Where-Object { $manifestFiles -notcontains $_ }).Count -eq 0)
    }
    $status = if ($manifest -and [string]$manifest.artifact_type -eq "user_app_repo_skeleton_manifest_v1" -and $foundationReady -and [string]$manifest.gates.production_deploy -eq "not_selected") {
        "repo_skeleton_ready"
    }
    elseif ($manifest) {
        "repo_skeleton_needs_repair"
    }
    else {
        "needs_repo_skeleton"
    }
    return [ordered]@{
        app_name = [string]$Spec.name
        target = $manifestRel
        manifest_exists = [bool]$manifest
        status = $status
        foundation_files = $foundationReady
        file_count = if ($manifest -and $manifest.PSObject.Properties["file_count"]) { [int]$manifest.file_count } else { 0 }
        production_deploy = if ($manifest -and $manifest.PSObject.Properties["gates"]) { [string]$manifest.gates.production_deploy } else { "" }
        tod_next_action = if ($manifest -and $manifest.PSObject.Properties["tod_next_action"]) { [string]$manifest.tod_next_action } else { "" }
    }
}

function Get-AppPersistenceStatus {
    param([Parameter(Mandatory = $true)]$Spec)
    $slug = Convert-ToSlug -Text ([string]$Spec.name)
    $manifestRel = "runtime/shared/user_app_repos/$slug/persistence.manifest.json"
    $manifestAbs = Join-Path $repoRoot ($manifestRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    $manifest = Read-JsonFile -Path $manifestAbs
    $requiredFiles = @("src/lib/models.ts", "src/lib/seed.ts", "src/lib/localPersistence.ts", "src/lib/exportImport.ts", "tests/persistence.spec.ts")
    $filesReady = $false
    if ($manifest) {
        $manifestFiles = @($manifest.files | ForEach-Object { [string]$_ })
        $filesReady = (@($requiredFiles | Where-Object { $manifestFiles -notcontains $_ }).Count -eq 0)
    }
    $status = if ($manifest -and [string]$manifest.artifact_type -eq "user_app_persistence_scaffold_manifest_v1" -and $filesReady -and [string]$manifest.gates.local_persistence -eq "ready" -and [string]$manifest.gates.backend_database -eq "not_selected") {
        "persistence_scaffold_ready"
    }
    elseif ($manifest) {
        "persistence_scaffold_needs_repair"
    }
    else {
        "needs_persistence_scaffold"
    }
    return [ordered]@{
        app_name = [string]$Spec.name
        target = $manifestRel
        manifest_exists = [bool]$manifest
        status = $status
        files_ready = $filesReady
        primary_model = if ($manifest -and $manifest.PSObject.Properties["primary_model"]) { [string]$manifest.primary_model } else { "" }
        local_persistence = if ($manifest -and $manifest.PSObject.Properties["gates"]) { [string]$manifest.gates.local_persistence } else { "" }
        backend_database = if ($manifest -and $manifest.PSObject.Properties["gates"]) { [string]$manifest.gates.backend_database } else { "" }
        tod_next_action = if ($manifest -and $manifest.PSObject.Properties["tod_next_action"]) { [string]$manifest.tod_next_action } else { "" }
    }
}

function Get-AppPreviewTargetStatus {
    param([Parameter(Mandatory = $true)]$Spec)
    $slug = Convert-ToSlug -Text ([string]$Spec.name)
    $planRel = "runtime/shared/user_app_repos/$slug/preview-target.plan.json"
    $docRel = "runtime/shared/user_app_repos/$slug/PREVIEW_TARGET.md"
    $planAbs = Join-Path $repoRoot ($planRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    $docAbs = Join-Path $repoRoot ($docRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    $plan = Read-JsonFile -Path $planAbs
    $status = if (
        $plan -and
        [string]$plan.artifact_type -eq "user_app_preview_target_plan_v1" -and
        (Test-Path -Path $docAbs -PathType Leaf) -and
        [string]$plan.gates.preview_target_selected -eq "local_next_preview" -and
        [string]$plan.gates.preview_runtime_verified -eq "not_run" -and
        [string]$plan.gates.production_deploy -eq "not_selected"
    ) {
        "preview_target_plan_ready"
    }
    elseif ($plan) {
        "preview_target_plan_needs_repair"
    }
    else {
        "needs_preview_target_plan"
    }
    return [ordered]@{
        app_name = [string]$Spec.name
        target = $planRel
        manifest_exists = [bool]$plan
        doc_exists = (Test-Path -Path $docAbs -PathType Leaf)
        status = $status
        preview_target = if ($plan -and $plan.PSObject.Properties["preview_target"]) { [string]$plan.preview_target.type } else { "" }
        runtime_verified = if ($plan -and $plan.PSObject.Properties["gates"]) { [string]$plan.gates.preview_runtime_verified } else { "" }
        production_deploy = if ($plan -and $plan.PSObject.Properties["gates"]) { [string]$plan.gates.production_deploy } else { "" }
        tod_next_action = if ($plan -and $plan.PSObject.Properties["tod_next_action"]) { [string]$plan.tod_next_action } else { "" }
    }
}

function Get-AppRuntimeStatus {
    param([Parameter(Mandatory = $true)]$Spec)
    $slug = Convert-ToSlug -Text ([string]$Spec.name)
    $manifestRel = "runtime/shared/user_app_repos/$slug/runtime.manifest.json"
    $acceptanceRel = "runtime/shared/user_app_runtime_acceptance/$slug/runtime.acceptance.json"
    $staticPublishRel = "runtime/shared/user_app_static_published/$slug/static-publish.manifest.json"
    $manifestAbs = Join-Path $repoRoot ($manifestRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    $acceptanceAbs = Join-Path $repoRoot ($acceptanceRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    $staticPublishAbs = Join-Path $repoRoot ($staticPublishRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    $manifest = Read-JsonFile -Path $manifestAbs
    $acceptance = Read-JsonFile -Path $acceptanceAbs
    $staticPublish = Read-JsonFile -Path $staticPublishAbs
    $scaffoldReady = ($manifest -and [string]$manifest.artifact_type -eq "user_app_runtime_scaffold_manifest_v1" -and [string]$manifest.gates.runtime_config -eq "ready")
    $buildPassed = ($acceptance -and [string]$acceptance.artifact_type -eq "user_app_runtime_acceptance_result_v1" -and [string]$acceptance.gates.dependency_install -eq "passed" -and [string]$acceptance.gates.local_build -eq "passed")
    $routeProbePassed = ($buildPassed -and $acceptance.PSObject.Properties["local_preview_acceptance"] -and [bool]$acceptance.local_preview_acceptance.passed -and [string]$acceptance.gates.local_preview -eq "route_probe_passed")
    $visualPassed = ($buildPassed -and $acceptance.PSObject.Properties["visual_acceptance"] -and [bool]$acceptance.visual_acceptance.passed -and [string]$acceptance.gates.local_preview -eq "visual_acceptance_passed")
    $interactionPassed = ($buildPassed -and $acceptance.PSObject.Properties["interaction_acceptance"] -and [bool]$acceptance.interaction_acceptance.passed -and $acceptance.gates.PSObject.Properties["interaction_preview"] -and [string]$acceptance.gates.interaction_preview -eq "passed")
    $staticPublishPassed = ($staticPublish -and [string]$staticPublish.artifact_type -eq "user_app_static_publish_acceptance_v1" -and [string]$staticPublish.gates.local_static_export -eq "passed")
    $status = if ($staticPublishPassed) {
        "static_publish_passed"
    }
    elseif ($interactionPassed) {
        "interaction_acceptance_passed"
    }
    elseif ($visualPassed) {
        "visual_acceptance_passed"
    }
    elseif ($routeProbePassed) {
        "local_preview_route_probe_passed"
    }
    elseif ($buildPassed) {
        "runtime_build_passed"
    }
    elseif ($scaffoldReady) {
        "runtime_scaffold_ready"
    }
    elseif ($manifest) {
        "runtime_scaffold_needs_repair"
    }
    else {
        "needs_runtime_scaffold"
    }
    return [ordered]@{
        app_name = [string]$Spec.name
        target = $manifestRel
        acceptance = $acceptanceRel
        static_publish = $staticPublishRel
        manifest_exists = [bool]$manifest
        status = $status
        runtime_config = if ($manifest -and $manifest.PSObject.Properties["gates"]) { [string]$manifest.gates.runtime_config } else { "" }
        dependency_install = if ($acceptance -and $acceptance.PSObject.Properties["gates"]) { [string]$acceptance.gates.dependency_install } else { "not_run" }
        local_build = if ($acceptance -and $acceptance.PSObject.Properties["gates"]) { [string]$acceptance.gates.local_build } else { "not_run" }
        local_preview = if ($acceptance -and $acceptance.PSObject.Properties["gates"]) { [string]$acceptance.gates.local_preview } else { "not_run" }
        interaction_preview = if ($acceptance -and $acceptance.PSObject.Properties["gates"] -and $acceptance.gates.PSObject.Properties["interaction_preview"]) { [string]$acceptance.gates.interaction_preview } else { "not_run" }
        static_publish_gate = if ($staticPublish -and $staticPublish.PSObject.Properties["gates"]) { [string]$staticPublish.gates.local_static_export } else { "not_run" }
        preview_acceptance_method = if ($acceptance -and $acceptance.PSObject.Properties["local_preview_acceptance"]) { [string]$acceptance.local_preview_acceptance.method } else { "not_run" }
        browser_visual_check = if ($acceptance -and $acceptance.PSObject.Properties["visual_acceptance"]) { [string]$acceptance.visual_acceptance.browser_visual_check } elseif ($acceptance -and $acceptance.PSObject.Properties["local_preview_acceptance"]) { [string]$acceptance.local_preview_acceptance.browser_visual_check } else { "not_run" }
        production_deploy = if ($manifest -and $manifest.PSObject.Properties["gates"]) { [string]$manifest.gates.production_deploy } else { "" }
    }
}

function Invoke-TrainingCycle {
    param([int]$CycleNumber)
    $apps = Get-AppSpecs
    $statuses = @($apps | ForEach-Object { Get-AppStatus -Spec $_ })
    $next = $null
    foreach ($item in $statuses) {
        if ([string]$item.status -ne "prototype_ready") {
            $next = @($apps | Where-Object { [string]$_.name -eq [string]$item.app_name })[0]
            break
        }
    }
    $dispatch = $null
    if ($next) {
        $intakePath = New-AppIntakeArtifact -Spec $next
        $dispatch = Invoke-TodPrototypeTask -Spec $next -IntakePath $intakePath -CycleNumber $CycleNumber
    }
    $updatedStatuses = @($apps | ForEach-Object { Get-AppStatus -Spec $_ })
    $readyCount = @($updatedStatuses | Where-Object { $_.status -eq "prototype_ready" }).Count
    $publishStatuses = @($apps | ForEach-Object { Get-AppPublishStatus -Spec $_ })
    $publishReadyCount = @($publishStatuses | Where-Object { $_.status -eq "published_preview_ready" }).Count
    $materializationStatuses = @($apps | ForEach-Object { Get-AppMaterializationStatus -Spec $_ })
    $materializationReadyCount = @($materializationStatuses | Where-Object { $_.status -eq "materialization_plan_ready" }).Count
    $repoStatuses = @($apps | ForEach-Object { Get-AppRepoSkeletonStatus -Spec $_ })
    $repoReadyCount = @($repoStatuses | Where-Object { $_.status -eq "repo_skeleton_ready" }).Count
    $persistenceStatuses = @($apps | ForEach-Object { Get-AppPersistenceStatus -Spec $_ })
    $persistenceReadyCount = @($persistenceStatuses | Where-Object { $_.status -eq "persistence_scaffold_ready" }).Count
    $previewTargetStatuses = @($apps | ForEach-Object { Get-AppPreviewTargetStatus -Spec $_ })
    $previewTargetReadyCount = @($previewTargetStatuses | Where-Object { $_.status -eq "preview_target_plan_ready" }).Count
    $runtimeStatuses = @($apps | ForEach-Object { Get-AppRuntimeStatus -Spec $_ })
    $runtimeScaffoldReadyCount = @($runtimeStatuses | Where-Object { $_.status -eq "runtime_scaffold_ready" -or $_.status -eq "runtime_build_passed" -or $_.status -eq "local_preview_route_probe_passed" -or $_.status -eq "visual_acceptance_passed" -or $_.status -eq "interaction_acceptance_passed" -or $_.status -eq "static_publish_passed" }).Count
    $runtimeBuildPassedCount = @($runtimeStatuses | Where-Object { $_.status -eq "runtime_build_passed" -or $_.status -eq "local_preview_route_probe_passed" -or $_.status -eq "visual_acceptance_passed" -or $_.status -eq "interaction_acceptance_passed" -or $_.status -eq "static_publish_passed" }).Count
    $localPreviewRouteProbePassedCount = @($runtimeStatuses | Where-Object { $_.status -eq "local_preview_route_probe_passed" -or $_.status -eq "visual_acceptance_passed" -or $_.status -eq "interaction_acceptance_passed" -or $_.status -eq "static_publish_passed" }).Count
    $visualAcceptancePassedCount = @($runtimeStatuses | Where-Object { $_.status -eq "visual_acceptance_passed" -or $_.status -eq "interaction_acceptance_passed" -or $_.status -eq "static_publish_passed" }).Count
    $interactionAcceptancePassedCount = @($runtimeStatuses | Where-Object { $_.status -eq "interaction_acceptance_passed" -or $_.status -eq "static_publish_passed" }).Count
    $staticPublishPassedCount = @($runtimeStatuses | Where-Object { $_.status -eq "static_publish_passed" }).Count
    if (-not $dispatch -and $readyCount -ge @($apps).Count) {
        $nextPublish = $null
        foreach ($item in $publishStatuses) {
            if ([string]$item.status -ne "published_preview_ready") {
                $nextPublish = @($apps | Where-Object { [string]$_.name -eq [string]$item.app_name })[0]
                break
            }
        }
        if ($nextPublish) {
            $dispatch = Invoke-TodPublishPreviewTask -Spec $nextPublish -CycleNumber $CycleNumber
            $publishStatuses = @($apps | ForEach-Object { Get-AppPublishStatus -Spec $_ })
            $publishReadyCount = @($publishStatuses | Where-Object { $_.status -eq "published_preview_ready" }).Count
            $materializationStatuses = @($apps | ForEach-Object { Get-AppMaterializationStatus -Spec $_ })
            $materializationReadyCount = @($materializationStatuses | Where-Object { $_.status -eq "materialization_plan_ready" }).Count
            $repoStatuses = @($apps | ForEach-Object { Get-AppRepoSkeletonStatus -Spec $_ })
            $repoReadyCount = @($repoStatuses | Where-Object { $_.status -eq "repo_skeleton_ready" }).Count
            $persistenceStatuses = @($apps | ForEach-Object { Get-AppPersistenceStatus -Spec $_ })
            $persistenceReadyCount = @($persistenceStatuses | Where-Object { $_.status -eq "persistence_scaffold_ready" }).Count
            $previewTargetStatuses = @($apps | ForEach-Object { Get-AppPreviewTargetStatus -Spec $_ })
            $previewTargetReadyCount = @($previewTargetStatuses | Where-Object { $_.status -eq "preview_target_plan_ready" }).Count
            $runtimeStatuses = @($apps | ForEach-Object { Get-AppRuntimeStatus -Spec $_ })
            $runtimeScaffoldReadyCount = @($runtimeStatuses | Where-Object { $_.status -eq "runtime_scaffold_ready" -or $_.status -eq "runtime_build_passed" -or $_.status -eq "local_preview_route_probe_passed" -or $_.status -eq "visual_acceptance_passed" -or $_.status -eq "interaction_acceptance_passed" -or $_.status -eq "static_publish_passed" }).Count
            $runtimeBuildPassedCount = @($runtimeStatuses | Where-Object { $_.status -eq "runtime_build_passed" -or $_.status -eq "local_preview_route_probe_passed" -or $_.status -eq "visual_acceptance_passed" -or $_.status -eq "interaction_acceptance_passed" -or $_.status -eq "static_publish_passed" }).Count
            $localPreviewRouteProbePassedCount = @($runtimeStatuses | Where-Object { $_.status -eq "local_preview_route_probe_passed" -or $_.status -eq "visual_acceptance_passed" -or $_.status -eq "interaction_acceptance_passed" -or $_.status -eq "static_publish_passed" }).Count
            $visualAcceptancePassedCount = @($runtimeStatuses | Where-Object { $_.status -eq "visual_acceptance_passed" -or $_.status -eq "interaction_acceptance_passed" -or $_.status -eq "static_publish_passed" }).Count
            $interactionAcceptancePassedCount = @($runtimeStatuses | Where-Object { $_.status -eq "interaction_acceptance_passed" -or $_.status -eq "static_publish_passed" }).Count
            $staticPublishPassedCount = @($runtimeStatuses | Where-Object { $_.status -eq "static_publish_passed" }).Count
        }
    }
    $payload = [ordered]@{
        artifact_type = "user_app_deep_training_watchdog_v1"
        generated_at = (Get-Date).ToUniversalTime().ToString("o")
        cycle = $CycleNumber
        interval_minutes = $IntervalMinutes
        max_cycles = $MaxCycles
        event = "USER-APP-DEEP-TRAINING-20260609-OVERNIGHT"
        ready_count = $readyCount
        total_count = @($apps).Count
        active_training_rule = "MIM/TOD do the app work; Codex supervises and repairs blockers only."
        latest_dispatch = $dispatch
        statuses = @($updatedStatuses)
        published_ready_count = $publishReadyCount
        publish_statuses = @($publishStatuses)
        materialization_ready_count = $materializationReadyCount
        materialization_statuses = @($materializationStatuses)
        repo_skeleton_ready_count = $repoReadyCount
        repo_skeleton_statuses = @($repoStatuses)
        persistence_ready_count = $persistenceReadyCount
        persistence_statuses = @($persistenceStatuses)
        preview_target_ready_count = $previewTargetReadyCount
        preview_target_statuses = @($previewTargetStatuses)
        runtime_scaffold_ready_count = $runtimeScaffoldReadyCount
        runtime_build_passed_count = $runtimeBuildPassedCount
        local_preview_route_probe_passed_count = $localPreviewRouteProbePassedCount
        visual_acceptance_passed_count = $visualAcceptancePassedCount
        interaction_acceptance_passed_count = $interactionAcceptancePassedCount
        static_publish_passed_count = $staticPublishPassedCount
        runtime_statuses = @($runtimeStatuses)
        next_action = if ($readyCount -lt @($apps).Count) {
            "Continue next 20-minute cycle and dispatch the next non-ready app prototype."
        }
        elseif ($publishReadyCount -lt @($apps).Count) {
            "All prototypes are ready; continue publishing preview packages through TOD."
        }
        elseif ($materializationReadyCount -lt @($apps).Count) {
            "Preview packages are ready; create or repair app materialization plans before claiming app build maturity."
        }
        elseif ($repoReadyCount -lt @($apps).Count) {
            "Materialization plans are ready; create or repair generated repo skeletons before persistence/deploy work."
        }
        elseif ($persistenceReadyCount -lt @($apps).Count) {
            "Repo skeletons are ready; create or repair local persistence scaffolds before preview-target testing."
        }
        elseif ($previewTargetReadyCount -lt @($apps).Count) {
            "Persistence scaffolds are ready; create or repair preview-target plans before runtime acceptance testing."
        }
        elseif ($runtimeScaffoldReadyCount -lt @($apps).Count) {
            "Preview-target plans are ready; create runtime config scaffolds before build testing."
        }
        elseif ($runtimeBuildPassedCount -lt 1) {
            "Runtime scaffolds are ready; run the first local build acceptance proof and record output."
        }
        elseif ($localPreviewRouteProbePassedCount -lt 1) {
            "Runtime builds are ready; start one local preview and run route acceptance before claiming app runtime maturity."
        }
        elseif ($visualAcceptancePassedCount -lt 1) {
            "Local preview route probes are ready; run Playwright visual acceptance against one generated app before claiming reviewable app maturity."
        }
        elseif ($interactionAcceptancePassedCount -lt 1) {
            "Visual acceptance is ready; run dashboard interaction acceptance before claiming the apps respond to user work."
        }
        elseif ($staticPublishPassedCount -lt 1) {
            "Interaction acceptance is ready; run local static publish/export acceptance before claiming apps are publishable."
        }
        else {
            "All sample app layers build, route-probe, render visually, pass dashboard interaction, and export to local static published packages; continue watchdog monitoring and move to hosted deploy-target selection."
        }
    }
    Write-JsonFile -Path $statusPath -Payload $payload -Depth 30
    Add-Content -Path $logPath -Value (($payload | ConvertTo-Json -Depth 30) -replace "`r?`n", "")
    return $payload
}

if (-not (Test-Path -Path $eventPath -PathType Leaf)) {
    throw "Training event artifact missing: $eventPath"
}

$cycleLimit = if ($RunOnce.IsPresent) { 1 } else { [Math]::Max(1, $MaxCycles) }
for ($cycle = 1; $cycle -le $cycleLimit; $cycle++) {
    $payload = Invoke-TrainingCycle -CycleNumber $cycle
    if ($payload.ready_count -ge $payload.total_count -and $payload.published_ready_count -ge $payload.total_count -and $payload.materialization_ready_count -ge $payload.total_count -and $payload.repo_skeleton_ready_count -ge $payload.total_count -and $payload.persistence_ready_count -ge $payload.total_count -and $payload.preview_target_ready_count -ge $payload.total_count) { break }
    if ($RunOnce.IsPresent) { break }
    Start-Sleep -Seconds ([Math]::Max(1, $IntervalMinutes) * 60)
}
