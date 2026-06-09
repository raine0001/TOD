Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $repoRoot "tod/out/tests/user-app-materialization-plan"
if (Test-Path -Path $testRoot) {
    Remove-Item -Path $testRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

$prototypePath = "tod/out/tests/user-app-materialization-plan/user_app_builds/sample_app/SAMPLE_APP_PROTOTYPE.latest.json"
$manifestPath = "tod/out/tests/user-app-materialization-plan/user_app_published/sample_app/package.manifest.json"
$planPath = "tod/out/tests/user-app-materialization-plan/user_app_materialization/sample_app/materialization.plan.json"
$intakePath = "tod/out/tests/user-app-materialization-plan/SAMPLE_APP_INTAKE_V1.latest.json"
$intakeAbs = Join-Path $repoRoot ($intakePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
New-Item -ItemType Directory -Path (Split-Path -Parent $intakeAbs) -Force | Out-Null
@{
    app_name = "Sample App"
    app_type = "multi_user"
    prompt = "Build a small sample app."
} | ConvertTo-Json -Depth 5 | Set-Content -Path $intakeAbs -Encoding UTF8

& "$repoRoot/scripts/New-UserAppPrototypeArtifact.ps1" -IntakePath $intakePath -OutputPath $prototypePath | Out-Null
& "$repoRoot/scripts/New-UserAppPublishedPreview.ps1" -PrototypePath $prototypePath -OutputManifestPath $manifestPath | Out-Null
& "$repoRoot/scripts/New-UserAppMaterializationPlan.ps1" -ManifestPath $manifestPath -OutputPath $planPath | Out-Null

$planAbs = Join-Path $repoRoot ($planPath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
if (-not (Test-Path -Path $planAbs -PathType Leaf)) {
    throw "Materialization plan was not created."
}

$plan = Get-Content -Path $planAbs -Raw | ConvertFrom-Json
$checks = @(
    @{ name = "json_round_trip"; passed = ($plan.artifact_type -eq "user_app_materialization_plan_v1") },
    @{ name = "foundation_present"; passed = ($plan.required_foundation.login -and $plan.required_foundation.dashboard -and $plan.required_foundation.help_support) },
    @{ name = "honest_boundary"; passed = ([string]$plan.honest_boundary -match "not a production hosted app") },
    @{ name = "repo_files_present"; passed = (@($plan.proposed_repo.files).Count -ge 8) },
    @{ name = "deploy_gated"; passed = ($plan.gates.production_deploy -eq "not_selected") }
)

$failed = @($checks | Where-Object { -not $_.passed })
if (@($failed).Count -gt 0) {
    throw ("Materialization plan test failed: " + (($failed | ForEach-Object { $_.name }) -join ", "))
}

"User app materialization plan generator passed."
