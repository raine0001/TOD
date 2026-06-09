Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $repoRoot "tod/out/tests/user-app-persistence-scaffold"
if (Test-Path -Path $testRoot) {
    Remove-Item -Path $testRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

$intakePath = "tod/out/tests/user-app-persistence-scaffold/SAMPLE_APP_INTAKE_V1.latest.json"
$prototypePath = "tod/out/tests/user-app-persistence-scaffold/user_app_builds/sample_app/SAMPLE_APP_PROTOTYPE.latest.json"
$publishManifestPath = "tod/out/tests/user-app-persistence-scaffold/user_app_published/sample_app/package.manifest.json"
$planPath = "tod/out/tests/user-app-persistence-scaffold/user_app_materialization/sample_app/materialization.plan.json"
$repoOut = "tod/out/tests/user-app-persistence-scaffold/user_app_repos/sample_app"
$repoManifestPath = "$repoOut/repo.manifest.json"

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

$persistenceManifestAbs = Join-Path $repoRoot (($repoOut + "/persistence.manifest.json") -replace '/', [System.IO.Path]::DirectorySeparatorChar)
if (-not (Test-Path -Path $persistenceManifestAbs -PathType Leaf)) {
    throw "Persistence manifest was not created."
}

$manifest = Get-Content -Path $persistenceManifestAbs -Raw | ConvertFrom-Json
$requiredFiles = @(
    "src/lib/models.ts",
    "src/lib/seed.ts",
    "src/lib/localPersistence.ts",
    "src/lib/exportImport.ts",
    "tests/persistence.spec.ts"
)
$missing = @($requiredFiles | Where-Object {
        $path = Join-Path $repoRoot (($repoOut + "/" + $_) -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        -not (Test-Path -Path $path -PathType Leaf)
    })
if (@($missing).Count -gt 0) {
    throw ("Missing persistence files: " + ($missing -join ", "))
}
if ([string]$manifest.artifact_type -ne "user_app_persistence_scaffold_manifest_v1") {
    throw "Wrong persistence manifest artifact type."
}
if ([string]$manifest.gates.backend_database -ne "not_selected") {
    throw "Persistence scaffold must not claim backend database readiness."
}
if ([string]$manifest.gates.local_persistence -ne "ready") {
    throw "Local persistence gate should be ready."
}

"User app persistence scaffold generator passed."
