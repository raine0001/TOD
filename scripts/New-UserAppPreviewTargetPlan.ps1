param(
    [Parameter(Mandatory = $true)][string]$PersistenceManifestPath,
    [string]$Source = "CodexSupervised::UserAppPreviewTargetPlan"
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

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

$persistenceAbs = Convert-ToRepoPath -PathValue $PersistenceManifestPath
if (-not (Test-Path -Path $persistenceAbs -PathType Leaf)) {
    throw "Persistence manifest not found: $PersistenceManifestPath"
}

$persistence = Get-Content -Path $persistenceAbs -Raw | ConvertFrom-Json
if ([string]$persistence.artifact_type -ne "user_app_persistence_scaffold_manifest_v1") {
    throw "Unsupported persistence manifest artifact type: $($persistence.artifact_type)"
}

$repoAbs = Convert-ToRepoPath -PathValue ([string]$persistence.repo_root)
$repoManifestAbs = Convert-ToRepoPath -PathValue ([string]$persistence.source_repo_manifest)
$repoManifest = Get-Content -Path $repoManifestAbs -Raw | ConvertFrom-Json
$appName = [string]$persistence.app_name
$slug = [string]$persistence.slug
$primaryModel = [string]$persistence.primary_model

$plan = [ordered]@{
    artifact_type = "user_app_preview_target_plan_v1"
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = $Source
    app_name = $appName
    slug = $slug
    source_persistence_manifest = Convert-ToRepoRelativePath -PathValue $persistenceAbs
    repo_root = Convert-ToRepoRelativePath -PathValue $repoAbs
    preview_target = [ordered]@{
        type = "local_next_preview"
        status = "planned"
        install_command = "npm install"
        run_command = "npm run dev -- --host 127.0.0.1"
        expected_base_url = "http://127.0.0.1:3000"
        routes = @("/", "/login", "/dashboard", "/help", "/settings")
    }
    acceptance = [ordered]@{
        static_files_present = "ready"
        local_persistence_scaffold = "ready"
        dashboard_persistence_wiring = "next"
        command_to_run = "npm test"
        required_visible_text = @($appName, "Primary Workflow", "MIM Help")
        required_model = $primaryModel
    }
    gates = [ordered]@{
        preview_target_selected = "local_next_preview"
        preview_runtime_verified = "not_run"
        acceptance_tests = "planned"
        backend_database = "not_selected"
        production_deploy = "not_selected"
    }
    dave_needed = "no"
    tod_next_action = "Run the local preview target, wire dashboard actions to local persistence for $primaryModel, and record acceptance output."
}

$instructions = @"
# Preview Target Plan: $appName

## Local preview

1. Run: ``npm install``
2. Run: ``npm run dev -- --host 127.0.0.1``
3. Open: ``http://127.0.0.1:3000``
4. Verify routes: `/`, `/login`, `/dashboard`, `/help`, `/settings`

## Acceptance

- App title visible: $appName
- Dashboard visible: Primary Workflow
- Help visible: MIM Help
- Primary model: $primaryModel

## Honest gates

- Backend database: not selected
- Production deploy: not selected
- Runtime preview verification: not run
"@

Write-Utf8NoBom -Path (Join-Path $repoAbs "preview-target.plan.json") -Content ($plan | ConvertTo-Json -Depth 30)
Write-Utf8NoBom -Path (Join-Path $repoAbs "PREVIEW_TARGET.md") -Content $instructions

$plan | ConvertTo-Json -Depth 12
