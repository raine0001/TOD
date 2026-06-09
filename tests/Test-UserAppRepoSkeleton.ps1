Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $repoRoot "tod/out/tests/user-app-repo-skeleton"
if (Test-Path -Path $testRoot) {
    Remove-Item -Path $testRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

$intakePath = "tod/out/tests/user-app-repo-skeleton/SAMPLE_APP_INTAKE_V1.latest.json"
$prototypePath = "tod/out/tests/user-app-repo-skeleton/user_app_builds/sample_app/SAMPLE_APP_PROTOTYPE.latest.json"
$publishManifestPath = "tod/out/tests/user-app-repo-skeleton/user_app_published/sample_app/package.manifest.json"
$planPath = "tod/out/tests/user-app-repo-skeleton/user_app_materialization/sample_app/materialization.plan.json"
$repoOut = "tod/out/tests/user-app-repo-skeleton/user_app_repos/sample_app"

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

$manifestAbs = Join-Path $repoRoot (($repoOut + "/repo.manifest.json") -replace '/', [System.IO.Path]::DirectorySeparatorChar)
if (-not (Test-Path -Path $manifestAbs -PathType Leaf)) {
    throw "Repo manifest was not created."
}

$manifest = Get-Content -Path $manifestAbs -Raw | ConvertFrom-Json
$requiredFiles = @(
    "README.md",
    "package.json",
    "src/app/page.tsx",
    "src/app/login/page.tsx",
    "src/app/dashboard/page.tsx",
    "src/app/help/page.tsx",
    "src/app/settings/page.tsx",
    "tests/acceptance.spec.ts"
)

$missing = @($requiredFiles | Where-Object {
        $path = Join-Path $repoRoot (($repoOut + "/" + $_) -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        -not (Test-Path -Path $path -PathType Leaf)
    })
if (@($missing).Count -gt 0) {
    throw ("Missing repo files: " + ($missing -join ", "))
}
if ([string]$manifest.artifact_type -ne "user_app_repo_skeleton_manifest_v1") {
    throw "Wrong repo manifest artifact type."
}
if ([string]$manifest.gates.production_deploy -ne "not_selected") {
    throw "Repo skeleton must not claim production deploy."
}
if ([string]::IsNullOrWhiteSpace([string]$manifest.tod_next_action)) {
    throw "Repo skeleton must include TOD next action."
}

"User app repo skeleton generator passed."
