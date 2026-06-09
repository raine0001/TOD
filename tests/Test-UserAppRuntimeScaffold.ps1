Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $repoRoot "tod/out/tests/user-app-runtime-scaffold"
if (Test-Path -Path $testRoot) {
    Remove-Item -Path $testRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

$intakePath = "tod/out/tests/user-app-runtime-scaffold/SAMPLE_APP_INTAKE_V1.latest.json"
$prototypePath = "tod/out/tests/user-app-runtime-scaffold/user_app_builds/sample_app/SAMPLE_APP_PROTOTYPE.latest.json"
$publishManifestPath = "tod/out/tests/user-app-runtime-scaffold/user_app_published/sample_app/package.manifest.json"
$planPath = "tod/out/tests/user-app-runtime-scaffold/user_app_materialization/sample_app/materialization.plan.json"
$repoOut = "tod/out/tests/user-app-runtime-scaffold/user_app_repos/sample_app"
$repoManifestPath = "$repoOut/repo.manifest.json"
$persistenceManifestPath = "$repoOut/persistence.manifest.json"
$previewTargetPath = "$repoOut/preview-target.plan.json"

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
& "$repoRoot/scripts/Add-UserAppRuntimeScaffold.ps1" -PreviewTargetPlanPath $previewTargetPath | Out-Null

$runtimeManifestAbs = Join-Path $repoRoot (($repoOut + "/runtime.manifest.json") -replace '/', [System.IO.Path]::DirectorySeparatorChar)
if (-not (Test-Path -Path $runtimeManifestAbs -PathType Leaf)) {
    throw "Runtime manifest was not created."
}

$manifest = Get-Content -Path $runtimeManifestAbs -Raw | ConvertFrom-Json
$requiredFiles = @("next.config.mjs", "tsconfig.json", "next-env.d.ts", ".gitignore")
$missing = @($requiredFiles | Where-Object {
        $path = Join-Path $repoRoot (($repoOut + "/" + $_) -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        -not (Test-Path -Path $path -PathType Leaf)
    })
if (@($missing).Count -gt 0) {
    throw ("Missing runtime files: " + ($missing -join ", "))
}
if ([string]$manifest.artifact_type -ne "user_app_runtime_scaffold_manifest_v1") {
    throw "Wrong runtime manifest artifact type."
}
if ([string]$manifest.gates.runtime_config -ne "ready") {
    throw "Runtime config should be ready."
}
if ([string]$manifest.gates.local_build -ne "not_run") {
    throw "Local build must remain not_run until actually executed."
}

"User app runtime scaffold generator passed."
