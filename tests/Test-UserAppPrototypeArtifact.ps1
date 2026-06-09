Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$intakePath = "runtime/shared/SIMPLE_APPOINTMENT_SCHEDULER_INTAKE_V1.latest.json"
$outputPath = "tod/out/tests/simple_appointment_scheduler/SIMPLE_APPOINTMENT_SCHEDULER_PROTOTYPE.test.json"
$absoluteOutput = Join-Path $repoRoot $outputPath

if (Test-Path -Path $absoluteOutput) {
    Remove-Item -Path $absoluteOutput -Force
}

$resultJson = & (Join-Path $repoRoot "scripts/New-UserAppPrototypeArtifact.ps1") -IntakePath $intakePath -OutputPath $outputPath -Source "tests/Test-UserAppPrototypeArtifact.ps1"
$result = $resultJson | ConvertFrom-Json
if ([string]$result.status -ne "succeeded") {
    throw "Generator did not succeed: $resultJson"
}

$artifact = Get-Content -Path $absoluteOutput -Raw | ConvertFrom-Json
if ([string]$artifact.artifact_type -ne "user_app_workbench_prototype_v1") {
    throw "Artifact type mismatch."
}
if ([string]$artifact.app_name -ne "Simple Appointment Scheduler") {
    throw "App name mismatch."
}

$requiredScreens = @("front_page", "login", "dashboard", "settings", "help_support")
$screenKeys = @($artifact.screens | ForEach-Object { [string]$_.key })
foreach ($screen in $requiredScreens) {
    if ($screenKeys -notcontains $screen) {
        throw "Missing required screen: $screen"
    }
}
if (@($artifact.acceptance_checklist).Count -lt 4) {
    throw "Acceptance checklist is too thin."
}
if (@($artifact.change_log).Count -lt 1) {
    throw "Missing change log."
}

"User app prototype artifact generator passed."
