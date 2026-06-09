Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $repoRoot "tod/out/tests/user-app-preview-target-plan"
if (Test-Path -Path $testRoot) {
    Remove-Item -Path $testRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

$intakePath = "tod/out/tests/user-app-preview-target-plan/SAMPLE_APP_INTAKE_V1.latest.json"
$prototypePath = "tod/out/tests/user-app-preview-target-plan/user_app_builds/sample_app/SAMPLE_APP_PROTOTYPE.latest.json"
$publishManifestPath = "tod/out/tests/user-app-preview-target-plan/user_app_published/sample_app/package.manifest.json"
$planPath = "tod/out/tests/user-app-preview-target-plan/user_app_materialization/sample_app/materialization.plan.json"
$repoOut = "tod/out/tests/user-app-preview-target-plan/user_app_repos/sample_app"
$repoManifestPath = "$repoOut/repo.manifest.json"
$persistenceManifestPath = "$repoOut/persistence.manifest.json"

$intakeAbs = Join-Path $repoRoot ($intakePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
New-Item -ItemType Directory -Path (Split-Path -Parent $intakeAbs) -Force | Out-Null
@{
    app_name = "Sample App"
    app_type = "multi_user"
    prompt = "Build a small sample app."
} | ConvertTo-Json -Depth 5 | Set-Content -Path $intakeAbs -Encoding UTF8

& "$repoRoot/scripts/New-UserAppPrototypeArtifact.ps1" -IntakePath $intakePath -OutputPath $prototypePath | Out-Null
& "$repoRoot/scripts/New-UserAppPublishedPreview.ps1" -PrototypePath $prototypePath -OutputManifestPath $publishManifestPath | Out-Null
& "$repoRoot/scripts/New-UserAppMaterializationPlan.ps1" -ManifestPath $publishManifestPath -OutputPath $planPath | Out-Null
& "$repoRoot/scripts/New-UserAppRepoSkeleton.ps1" -PlanPath $planPath -OutputRoot $repoOut | Out-Null
& "$repoRoot/scripts/Add-UserAppPersistenceScaffold.ps1" -RepoManifestPath $repoManifestPath | Out-Null
& "$repoRoot/scripts/New-UserAppPreviewTargetPlan.ps1" -PersistenceManifestPath $persistenceManifestPath | Out-Null

$previewPlanAbs = Join-Path $repoRoot (($repoOut + "/preview-target.plan.json") -replace '/', [System.IO.Path]::DirectorySeparatorChar)
$previewDocAbs = Join-Path $repoRoot (($repoOut + "/PREVIEW_TARGET.md") -replace '/', [System.IO.Path]::DirectorySeparatorChar)
if (-not (Test-Path -Path $previewPlanAbs -PathType Leaf)) {
    throw "Preview target plan was not created."
}
if (-not (Test-Path -Path $previewDocAbs -PathType Leaf)) {
    throw "Preview target instructions were not created."
}

$manifest = Get-Content -Path $previewPlanAbs -Raw | ConvertFrom-Json
if ([string]$manifest.artifact_type -ne "user_app_preview_target_plan_v1") {
    throw "Wrong preview target artifact type."
}
if ([string]$manifest.gates.preview_target_selected -ne "local_next_preview") {
    throw "Preview target was not selected."
}
if ([string]$manifest.gates.preview_runtime_verified -ne "not_run") {
    throw "Preview runtime must remain not_run until actually verified."
}
if ([string]$manifest.gates.production_deploy -ne "not_selected") {
    throw "Preview plan must not claim production deploy."
}

"User app preview target plan generator passed."
