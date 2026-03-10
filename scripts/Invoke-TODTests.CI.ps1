param(
    [string]$SummaryPath = "tod/out/results-v2/tod-tests-summary.json",
    [string]$TestPath = "tests/*.Tests.ps1"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$runnerPath = Join-Path $repoRoot "scripts/Invoke-TODTests.ps1"

if (-not (Test-Path -Path $runnerPath)) {
    throw "Missing test runner: $runnerPath"
}

$result = & $runnerPath -Path $TestPath -JsonOutputPath $SummaryPath -FailOnTestFailure
$summaryObj = $result | ConvertFrom-Json

# CI logs can grep this single line reliably.
Write-Host ("TOD_TEST_SUMMARY_PATH={0}" -f $SummaryPath)

if (-not [bool]$summaryObj.passed_all) {
    throw ("TOD test suite failed. See summary: {0}" -f $SummaryPath)
}
