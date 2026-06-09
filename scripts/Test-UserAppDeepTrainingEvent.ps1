param(
    [string]$OutputPath = "runtime/shared/USER_APP_DEEP_TRAINING_OUTCOME_AUDIT.latest.json"
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

function Read-JsonFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    $absolute = Convert-ToRepoPath -PathValue $Path
    if (-not (Test-Path -Path $absolute -PathType Leaf)) {
        return $null
    }
    return (Get-Content -Path $absolute -Raw | ConvertFrom-Json)
}

function Test-File {
    param([AllowEmptyString()][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }
    return (Test-Path -Path (Convert-ToRepoPath -PathValue $Path) -PathType Leaf)
}

function Test-RelativeGalleryLink {
    param(
        [Parameter(Mandatory = $true)][string]$GalleryPath,
        [AllowEmptyString()][string]$Href
    )
    if ([string]::IsNullOrWhiteSpace($Href)) {
        return $false
    }
    if ([System.Uri]::IsWellFormedUriString($Href, [System.UriKind]::Absolute)) {
        return $false
    }
    $galleryAbs = Convert-ToRepoPath -PathValue $GalleryPath
    $galleryDir = Split-Path -Parent $galleryAbs
    $targetAbs = [System.IO.Path]::GetFullPath((Join-Path $galleryDir $Href))
    return (Test-Path -Path $targetAbs -PathType Leaf)
}

function Convert-ToSlug {
    param([Parameter(Mandatory = $true)][string]$Text)
    $slug = $Text.Trim().ToLowerInvariant() -replace '[^a-z0-9]+', '_'
    $slug = $slug.Trim('_')
    if ([string]::IsNullOrWhiteSpace($slug)) { return 'user_app' }
    return $slug
}

$apps = @(
    "Simple Appointment Scheduler",
    "Inventory Mini Manager",
    "Receipt Expense Tracker",
    "Service Ticket Tracker",
    "Lead Pipeline Board",
    "Staff Task Board",
    "Small Business CRM",
    "Content Calendar",
    "Document Request Portal",
    "Business Meal Tracker"
)

$rows = @()
foreach ($app in $apps) {
    $slug = Convert-ToSlug -Text $app
    $constant = $slug.ToUpperInvariant()
    $prototypePath = "runtime/shared/user_app_builds/$slug/${constant}_PROTOTYPE.latest.json"
    $manifestPath = "runtime/shared/user_app_published/$slug/package.manifest.json"
    $materializationPath = "runtime/shared/user_app_materialization/$slug/materialization.plan.json"
    $repoManifestPath = "runtime/shared/user_app_repos/$slug/repo.manifest.json"
    $persistenceManifestPath = "runtime/shared/user_app_repos/$slug/persistence.manifest.json"
    $previewTargetPath = "runtime/shared/user_app_repos/$slug/preview-target.plan.json"
    $previewTargetDocPath = "runtime/shared/user_app_repos/$slug/PREVIEW_TARGET.md"
    $runtimeManifestPath = "runtime/shared/user_app_repos/$slug/runtime.manifest.json"
    $runtimeAcceptancePath = "runtime/shared/user_app_runtime_acceptance/$slug/runtime.acceptance.json"
    $staticPublishManifestPath = "runtime/shared/user_app_static_published/$slug/static-publish.manifest.json"
    $prototype = Read-JsonFile -Path $prototypePath
    $manifest = Read-JsonFile -Path $manifestPath
    $materialization = Read-JsonFile -Path $materializationPath
    $repoManifest = Read-JsonFile -Path $repoManifestPath
    $persistenceManifest = Read-JsonFile -Path $persistenceManifestPath
    $previewTarget = Read-JsonFile -Path $previewTargetPath
    $runtimeManifest = Read-JsonFile -Path $runtimeManifestPath
    $runtimeAcceptance = Read-JsonFile -Path $runtimeAcceptancePath
    $staticPublishManifest = Read-JsonFile -Path $staticPublishManifestPath
    $previewPath = if ($manifest -and $manifest.PSObject.Properties["preview_path"]) { [string]$manifest.preview_path } else { "" }
    $previewHtml = if (Test-File -Path $previewPath) { Get-Content -Path (Convert-ToRepoPath -PathValue $previewPath) -Raw } else { "" }
    $manifestSource = if ($manifest -and $manifest.PSObject.Properties["source"]) { [string]$manifest.source } else { "" }
    $designClass = if ($previewHtml -match '<body class="([^"]+)') { [string]$Matches[1] } else { "" }
    $screenKeys = if ($prototype -and $prototype.PSObject.Properties["screens"]) { @($prototype.screens | ForEach-Object { [string]$_.key }) } else { @() }
    $requiredScreens = @("front_page", "login", "dashboard", "settings", "help_support", "presentation")
    $missingScreens = @($requiredScreens | Where-Object { $screenKeys -notcontains $_ })
    $stylePreset = if ($prototype -and $prototype.PSObject.Properties["preview_ui"]) { [string]$prototype.preview_ui.style_preset } else { "" }
    $manifestStyle = if ($manifest -and $manifest.PSObject.Properties["style_preset"]) { [string]$manifest.style_preset } else { "" }
    $checks = [ordered]@{
        prototype_exists = [bool]$prototype
        generated_by_tod = ($prototype -and [string]$prototype.generated_by -eq "LocalExecutionEngine::Invoke-LocalExecutionUserAppPrototypeArtifact")
        required_foundation_screens = (@($missingScreens).Count -eq 0)
        help_page = ($screenKeys -contains "help_support")
        mim_help_scope = ($prototype -and $prototype.PSObject.Properties["mim_help"] -and [string]$prototype.mim_help.scope -eq "app_specific_help_only")
        presentation_walkthrough = ($prototype -and $prototype.PSObject.Properties["presentation_walkthrough"])
        completion_summary = ($prototype -and $prototype.PSObject.Properties["completion_summary"])
        style_tokens = (-not [string]::IsNullOrWhiteSpace($stylePreset) -and $prototype.preview_ui.PSObject.Properties["accent"] -and $prototype.preview_ui.PSObject.Properties["font_stack"])
        manifest_exists = [bool]$manifest
        published_by_tod = ($manifest -and ($manifestSource -eq "LocalExecutionEngine::Invoke-LocalExecutionUserAppPublishedPreview" -or $manifestSource.StartsWith("TOD::")))
        distinct_design_class = (-not [string]::IsNullOrWhiteSpace($designClass) -and $designClass -match '^design-')
        preview_html_exists = (Test-File -Path $previewPath)
        readme_exists = ($manifest -and (Test-File -Path ([string]$manifest.readme_path)))
        completion_summary_file_exists = ($manifest -and (Test-File -Path ([string]$manifest.completion_summary_path)))
        style_carried_to_publish = (-not [string]::IsNullOrWhiteSpace($stylePreset) -and $stylePreset -eq $manifestStyle)
        interactive_workflow_gate = ($manifest -and $manifest.PSObject.Properties["gates"] -and [string]$manifest.gates.interactive_workflow_preview -eq "ready" -and $previewHtml -match "workflow-action")
        mim_help_interaction = ($previewHtml -match "mimHelpButton")
        action_log = ($previewHtml -match "actionLog")
        last_minute_change_visible = ($manifest -and $manifest.PSObject.Properties["gates"] -and [string]$manifest.gates.last_minute_change_visible -eq "ready" -and $previewHtml -match "Last-Minute Change")
        production_deploy_honestly_gated = ($manifest -and $manifest.PSObject.Properties["gates"] -and [string]$manifest.gates.production_deploy -eq "not_selected")
        materialization_plan_exists = ($materialization -and [string]$materialization.artifact_type -eq "user_app_materialization_plan_v1")
        materialization_foundation_contract = ($materialization -and $materialization.PSObject.Properties["required_foundation"] -and $materialization.required_foundation.login -and $materialization.required_foundation.dashboard -and $materialization.required_foundation.help_support)
        materialization_next_action = ($materialization -and -not [string]::IsNullOrWhiteSpace([string]$materialization.tod_next_action))
        repo_skeleton_exists = ($repoManifest -and [string]$repoManifest.artifact_type -eq "user_app_repo_skeleton_manifest_v1")
        repo_foundation_files = ($repoManifest -and @("src/app/page.tsx", "src/app/login/page.tsx", "src/app/dashboard/page.tsx", "src/app/help/page.tsx", "src/app/settings/page.tsx", "tests/acceptance.spec.ts" | Where-Object { @($repoManifest.files) -notcontains $_ }).Count -eq 0)
        repo_deploy_honestly_gated = ($repoManifest -and $repoManifest.PSObject.Properties["gates"] -and [string]$repoManifest.gates.production_deploy -eq "not_selected")
        persistence_scaffold_exists = ($persistenceManifest -and [string]$persistenceManifest.artifact_type -eq "user_app_persistence_scaffold_manifest_v1")
        persistence_files = ($persistenceManifest -and @("src/lib/models.ts", "src/lib/seed.ts", "src/lib/localPersistence.ts", "src/lib/exportImport.ts", "tests/persistence.spec.ts" | Where-Object { @($persistenceManifest.files) -notcontains $_ }).Count -eq 0)
        local_persistence_ready = ($persistenceManifest -and $persistenceManifest.PSObject.Properties["gates"] -and [string]$persistenceManifest.gates.local_persistence -eq "ready")
        backend_database_honestly_gated = ($persistenceManifest -and $persistenceManifest.PSObject.Properties["gates"] -and [string]$persistenceManifest.gates.backend_database -eq "not_selected")
        preview_target_plan_exists = ($previewTarget -and [string]$previewTarget.artifact_type -eq "user_app_preview_target_plan_v1")
        preview_target_doc_exists = (Test-File -Path $previewTargetDocPath)
        preview_target_selected = ($previewTarget -and $previewTarget.PSObject.Properties["gates"] -and [string]$previewTarget.gates.preview_target_selected -eq "local_next_preview")
        preview_runtime_honestly_not_run = ($previewTarget -and $previewTarget.PSObject.Properties["gates"] -and [string]$previewTarget.gates.preview_runtime_verified -eq "not_run")
        preview_production_deploy_honestly_gated = ($previewTarget -and $previewTarget.PSObject.Properties["gates"] -and [string]$previewTarget.gates.production_deploy -eq "not_selected")
        runtime_scaffold_exists = ($runtimeManifest -and [string]$runtimeManifest.artifact_type -eq "user_app_runtime_scaffold_manifest_v1")
        runtime_config_ready = ($runtimeManifest -and $runtimeManifest.PSObject.Properties["gates"] -and [string]$runtimeManifest.gates.runtime_config -eq "ready")
        runtime_build_evidence = ($runtimeAcceptance -and [string]$runtimeAcceptance.artifact_type -eq "user_app_runtime_acceptance_result_v1" -and [string]$runtimeAcceptance.gates.dependency_install -eq "passed" -and [string]$runtimeAcceptance.gates.local_build -eq "passed")
        visual_acceptance = ($runtimeAcceptance -and $runtimeAcceptance.PSObject.Properties["visual_acceptance"] -and [bool]$runtimeAcceptance.visual_acceptance.passed -and [string]$runtimeAcceptance.gates.local_preview -eq "visual_acceptance_passed")
        local_preview_route_probe = ($runtimeAcceptance -and (($runtimeAcceptance.PSObject.Properties["local_preview_acceptance"] -and [bool]$runtimeAcceptance.local_preview_acceptance.passed -and [string]$runtimeAcceptance.gates.local_preview -eq "route_probe_passed") -or ($runtimeAcceptance.PSObject.Properties["visual_acceptance"] -and [bool]$runtimeAcceptance.visual_acceptance.passed -and [string]$runtimeAcceptance.gates.local_preview -eq "visual_acceptance_passed")))
        interaction_acceptance = ($runtimeAcceptance -and $runtimeAcceptance.PSObject.Properties["interaction_acceptance"] -and [bool]$runtimeAcceptance.interaction_acceptance.passed -and $runtimeAcceptance.PSObject.Properties["gates"] -and $runtimeAcceptance.gates.PSObject.Properties["interaction_preview"] -and [string]$runtimeAcceptance.gates.interaction_preview -eq "passed")
        static_publish_acceptance = ($staticPublishManifest -and [string]$staticPublishManifest.artifact_type -eq "user_app_static_publish_acceptance_v1" -and [string]$staticPublishManifest.gates.local_static_export -eq "passed" -and [string]$staticPublishManifest.gates.production_deploy -eq "not_selected")
    }
    $requiredCheckNames = @($checks.Keys)
    $failed = @($requiredCheckNames | Where-Object { -not [bool]$checks[$_] } | ForEach-Object { [string]$_ })
    $rows += [ordered]@{
        app_name = $app
        slug = $slug
        prototype_path = $prototypePath
        manifest_path = $manifestPath
        preview_path = $previewPath
        materialization_path = $materializationPath
        repo_manifest_path = $repoManifestPath
        persistence_manifest_path = $persistenceManifestPath
        preview_target_path = $previewTargetPath
        runtime_manifest_path = $runtimeManifestPath
        runtime_acceptance_path = $runtimeAcceptancePath
        static_publish_manifest_path = $staticPublishManifestPath
        data_objects = if ($materialization -and $materialization.PSObject.Properties["proposed_repo"]) { @($materialization.proposed_repo.data_objects) } else { @() }
        primary_model = if ($persistenceManifest -and $persistenceManifest.PSObject.Properties["primary_model"]) { [string]$persistenceManifest.primary_model } else { "" }
        style_preset = $stylePreset
        design_class = $designClass
        checks = $checks
        passed = (@($failed).Count -eq 0)
        failed_checks = @($failed)
        next_action = if (@($failed).Count -eq 0) { "Proceed to app-specific persistence/deploy target follow-on." } else { "Repair failed checks before claiming this app training slice complete." }
    }
}

$styles = @($rows | ForEach-Object { [string]$_["style_preset"] } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$objectSignatures = @($rows | ForEach-Object { (@($_["data_objects"]) -join "|") } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$failedRows = @($rows | Where-Object { -not [bool]$_["passed"] })
$watchdog = Read-JsonFile -Path "runtime/shared/USER_APP_DEEP_TRAINING_WATCHDOG.latest.json"
$process = Read-JsonFile -Path "runtime/shared/USER_APP_DEEP_TRAINING_WATCHDOG_PROCESS.latest.json"
$gallery = Read-JsonFile -Path "runtime/shared/user_app_published/gallery.manifest.json"
$galleryPath = if ($gallery -and $gallery.PSObject.Properties["gallery_path"]) { [string]$gallery.gallery_path } else { "" }
$galleryHtml = if (-not [string]::IsNullOrWhiteSpace($galleryPath) -and (Test-File -Path $galleryPath)) { Get-Content -Path (Convert-ToRepoPath -PathValue $galleryPath) -Raw } else { "" }
$galleryHrefs = @([regex]::Matches($galleryHtml, 'href="([^"]+preview\.html)"') | ForEach-Object { $_.Groups[1].Value })
$expectedGalleryHrefs = @($apps | ForEach-Object {
    $slug = Convert-ToSlug -Text $_
    "$slug/preview.html"
})
$missingGalleryHrefs = @($expectedGalleryHrefs | Where-Object { $galleryHrefs -notcontains $_ })
$galleryRelativeLinksOk = (
    @($missingGalleryHrefs).Count -eq 0 -and
    @($galleryHrefs | Where-Object { -not (Test-RelativeGalleryLink -GalleryPath $galleryPath -Href $_) }).Count -eq 0
)
$processAlive = $false
if ($process -and $process.PSObject.Properties["process_id"]) {
    $processAlive = ($null -ne (Get-Process -Id ([int]$process.process_id) -ErrorAction SilentlyContinue))
}

$payload = [ordered]@{
    artifact_type = "user_app_deep_training_outcome_audit_v1"
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    objective = "Run a 10-12 hour MIM/TOD deep training event for remaining sample app development."
    summary = [ordered]@{
        app_count = @($apps).Count
        apps_passed = @($rows | Where-Object { [bool]$_["passed"] }).Count
        apps_failed = @($failedRows).Count
        unique_style_count = @($styles | Select-Object -Unique).Count
        watchdog_alive = $processAlive
        watchdog_ready_count = if ($watchdog -and $watchdog.PSObject.Properties["ready_count"]) { [int]$watchdog.ready_count } else { 0 }
        watchdog_published_ready_count = if ($watchdog -and $watchdog.PSObject.Properties["published_ready_count"]) { [int]$watchdog.published_ready_count } else { 0 }
        gallery_app_count = if ($gallery -and $gallery.PSObject.Properties["app_count"]) { [int]$gallery.app_count } else { 0 }
        gallery_training_app_count = if ($gallery) { @($expectedGalleryHrefs | Where-Object { $galleryHrefs -contains $_ }).Count } else { 0 }
        materialization_ready_count = @($rows | Where-Object { [bool]$_['checks'].materialization_plan_exists -and [bool]$_['checks'].materialization_foundation_contract -and [bool]$_['checks'].materialization_next_action }).Count
        repo_skeleton_ready_count = @($rows | Where-Object { [bool]$_['checks'].repo_skeleton_exists -and [bool]$_['checks'].repo_foundation_files -and [bool]$_['checks'].repo_deploy_honestly_gated }).Count
        persistence_ready_count = @($rows | Where-Object { [bool]$_['checks'].persistence_scaffold_exists -and [bool]$_['checks'].persistence_files -and [bool]$_['checks'].local_persistence_ready -and [bool]$_['checks'].backend_database_honestly_gated }).Count
        preview_target_ready_count = @($rows | Where-Object { [bool]$_['checks'].preview_target_plan_exists -and [bool]$_['checks'].preview_target_doc_exists -and [bool]$_['checks'].preview_target_selected -and [bool]$_['checks'].preview_runtime_honestly_not_run -and [bool]$_['checks'].preview_production_deploy_honestly_gated }).Count
        runtime_scaffold_ready_count = @($rows | Where-Object { [bool]$_['checks'].runtime_scaffold_exists -and [bool]$_['checks'].runtime_config_ready }).Count
        runtime_build_passed_count = @($rows | Where-Object { [bool]$_['checks'].runtime_build_evidence }).Count
        local_preview_route_probe_passed_count = @($rows | Where-Object { [bool]$_['checks'].local_preview_route_probe }).Count
        visual_acceptance_passed_count = @($rows | Where-Object { [bool]$_['checks'].visual_acceptance }).Count
        interaction_acceptance_passed_count = @($rows | Where-Object { [bool]$_['checks'].interaction_acceptance }).Count
        static_publish_passed_count = @($rows | Where-Object { [bool]$_['checks'].static_publish_acceptance }).Count
    }
    requirements = [ordered]@{
        watchdog_every_20_minutes = $processAlive
        tod_generated_prototypes = (@($rows | Where-Object { -not [bool]$_['checks'].generated_by_tod }).Count -eq 0)
        tod_published_previews = (@($rows | Where-Object { -not [bool]$_['checks'].published_by_tod }).Count -eq 0)
        help_page_with_mim_support = (@($rows | Where-Object { -not [bool]$_['checks'].mim_help_interaction }).Count -eq 0)
        formal_presentation_walkthrough = (@($rows | Where-Object { -not [bool]$_['checks'].presentation_walkthrough }).Count -eq 0)
        completion_summary = (@($rows | Where-Object { -not [bool]$_['checks'].completion_summary }).Count -eq 0)
        last_minute_change_handling = (@($rows | Where-Object { -not [bool]$_['checks'].last_minute_change_visible }).Count -eq 0)
        unique_visual_direction = (@($styles | Select-Object -Unique).Count -eq @($apps).Count)
        production_deploy_not_fake_claimed = (@($rows | Where-Object { -not [bool]$_['checks'].production_deploy_honestly_gated }).Count -eq 0)
        published_gallery_ready = ($gallery -and [int]$gallery.app_count -ge @($apps).Count -and @($missingGalleryHrefs).Count -eq 0 -and (Test-File -Path $galleryPath))
        published_gallery_links_all_previews = ($gallery -and @($gallery.apps | Where-Object { -not (Test-File -Path ([string]$_.preview_path)) }).Count -eq 0 -and $galleryRelativeLinksOk)
        materialization_plans_ready = (@($rows | Where-Object { -not [bool]$_['checks'].materialization_plan_exists -or -not [bool]$_['checks'].materialization_foundation_contract -or -not [bool]$_['checks'].materialization_next_action }).Count -eq 0)
        repo_skeletons_ready = (@($rows | Where-Object { -not [bool]$_['checks'].repo_skeleton_exists -or -not [bool]$_['checks'].repo_foundation_files -or -not [bool]$_['checks'].repo_deploy_honestly_gated }).Count -eq 0)
        app_specific_data_objects = (@($objectSignatures | Select-Object -Unique).Count -eq @($apps).Count)
        persistence_scaffolds_ready = (@($rows | Where-Object { -not [bool]$_['checks'].persistence_scaffold_exists -or -not [bool]$_['checks'].persistence_files -or -not [bool]$_['checks'].local_persistence_ready -or -not [bool]$_['checks'].backend_database_honestly_gated }).Count -eq 0)
        preview_targets_ready = (@($rows | Where-Object { -not [bool]$_['checks'].preview_target_plan_exists -or -not [bool]$_['checks'].preview_target_doc_exists -or -not [bool]$_['checks'].preview_target_selected -or -not [bool]$_['checks'].preview_runtime_honestly_not_run -or -not [bool]$_['checks'].preview_production_deploy_honestly_gated }).Count -eq 0)
        runtime_scaffolds_ready = (@($rows | Where-Object { -not [bool]$_['checks'].runtime_scaffold_exists -or -not [bool]$_['checks'].runtime_config_ready }).Count -eq 0)
        runtime_build_first_proof = (@($rows | Where-Object { [bool]$_['checks'].runtime_build_evidence }).Count -ge 1)
        local_preview_first_route_probe = (@($rows | Where-Object { [bool]$_['checks'].local_preview_route_probe }).Count -ge 1)
        visual_acceptance_first_proof = (@($rows | Where-Object { [bool]$_['checks'].visual_acceptance }).Count -ge 1)
        interaction_acceptance_first_proof = (@($rows | Where-Object { [bool]$_['checks'].interaction_acceptance }).Count -ge 1)
        static_publish_first_proof = (@($rows | Where-Object { [bool]$_['checks'].static_publish_acceptance }).Count -ge 1)
        visual_acceptance_all_apps = (@($rows | Where-Object { -not [bool]$_['checks'].visual_acceptance }).Count -eq 0)
        interaction_acceptance_all_apps = (@($rows | Where-Object { -not [bool]$_['checks'].interaction_acceptance }).Count -eq 0)
        static_publish_all_apps = (@($rows | Where-Object { -not [bool]$_['checks'].static_publish_acceptance }).Count -eq 0)
    }
    app_results = @($rows)
    failed_apps = @($failedRows | ForEach-Object { $_["app_name"] })
    gallery = if ($gallery) {
        [ordered]@{
            manifest_path = "runtime/shared/user_app_published/gallery.manifest.json"
            gallery_path = $galleryPath
            app_count = [int]$gallery.app_count
            training_app_count = @($expectedGalleryHrefs | Where-Object { $galleryHrefs -contains $_ }).Count
            href_count = $galleryHrefs.Count
            relative_links_ok = $galleryRelativeLinksOk
            extra_app_count = [Math]::Max(0, [int]$gallery.app_count - @($apps).Count)
            deploy_target = [string]$gallery.deploy_target
            production_deploy = [string]$gallery.production_deploy
        }
    }
    else {
        $null
    }
    next_training_step = "Use these preview packages as inputs for app-specific persistence, real hosted preview deploy targets, and user feedback/change-request loops."
}

$absoluteOutput = Convert-ToRepoPath -PathValue $OutputPath
$outputDir = Split-Path -Parent $absoluteOutput
if (-not (Test-Path -Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}
$json = $payload | ConvertTo-Json -Depth 40
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($absoluteOutput, $json, $utf8NoBom)

if (@($failedRows).Count -gt 0) {
    Write-Error ("User app deep training audit failed for {0} app(s)." -f @($failedRows).Count)
}

$payload | ConvertTo-Json -Depth 12
