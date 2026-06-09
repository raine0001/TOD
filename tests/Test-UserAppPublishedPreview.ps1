$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$tmpRoot = Join-Path $repoRoot "tod/out/tests/user-app-published-preview"
if (Test-Path -Path $tmpRoot) {
    Remove-Item -Path $tmpRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null

$intakePath = "tod/out/tests/user-app-published-preview/SAMPLE_APP_INTAKE_V1.latest.json"
$prototypePath = "tod/out/tests/user-app-published-preview/user_app_builds/sample_app/SAMPLE_APP_PROTOTYPE.latest.json"
$manifestPath = "tod/out/tests/user-app-published-preview/user_app_published/sample_app/package.manifest.json"

$intake = [ordered]@{
    artifact_type = "user_app_intake_v1"
    app_name = "Sample App"
    app_type = "Training"
    summary = "A sample app for publisher validation."
    workflows = @("create record", "review record")
    screens = @(
        @{ key = "dashboard"; title = "Dashboard"; purpose = "Review activity."; features = @("cards", "next_action") }
    )
    acceptance_checklist = @("User can review the published preview.")
}
$intakeAbs = Join-Path $repoRoot ($intakePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
New-Item -ItemType Directory -Path (Split-Path -Parent $intakeAbs) -Force | Out-Null
$intake | ConvertTo-Json -Depth 20 | Set-Content -Path $intakeAbs -Encoding utf8

& (Join-Path $repoRoot "scripts/New-UserAppPrototypeArtifact.ps1") -IntakePath $intakePath -OutputPath $prototypePath -Source "test"
& (Join-Path $repoRoot "scripts/New-UserAppPublishedPreview.ps1") -PrototypePath $prototypePath -OutputManifestPath $manifestPath -Source "test"

$manifestAbs = Join-Path $repoRoot ($manifestPath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
if (-not (Test-Path -Path $manifestAbs -PathType Leaf)) {
    throw "Manifest was not created."
}
$manifest = Get-Content -Path $manifestAbs -Raw | ConvertFrom-Json
if ([string]$manifest.artifact_type -ne "user_app_published_preview_manifest_v1") {
    throw "Unexpected manifest artifact type."
}
foreach ($pathValue in @($manifest.preview_path, $manifest.completion_summary_path, $manifest.readme_path)) {
    $abs = Join-Path $repoRoot ([string]$pathValue -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -Path $abs -PathType Leaf)) {
        throw "Published preview file missing: $pathValue"
    }
}
if ([string]$manifest.status -ne "published_preview_ready") {
    throw "Published preview status was not ready."
}

"User app published preview generator passed."
