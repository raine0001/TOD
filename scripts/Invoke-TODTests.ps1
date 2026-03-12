param(
    [string]$Path = "tests/*.Tests.ps1",
    [string]$JsonOutputPath = "tod/out/training/test-summary.json",
    [switch]$FailOnTestFailure,
    [switch]$SkipSharedStateSync,
    [string]$SharedStateSyncScript = "scripts/Invoke-TODSharedStateSync.ps1"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$testPath = Join-Path $repoRoot $Path

function Test-IsTransientLockFailure {
    param([string]$Message)

    if ([string]::IsNullOrWhiteSpace($Message)) { return $false }

    $m = $Message.ToLowerInvariant()
    return (
        ($m -match "state\.json") -and
        ($m -match "used by another process|cannot access the file")
    )
}

function Invoke-SharedStateSyncIfEnabled {
    if ($SkipSharedStateSync) {
        return
    }

    $syncScriptPath = if ([System.IO.Path]::IsPathRooted($SharedStateSyncScript)) {
        $SharedStateSyncScript
    }
    else {
        Join-Path $repoRoot $SharedStateSyncScript
    }

    if (-not (Test-Path -Path $syncScriptPath)) {
        Write-Warning "Shared state sync script not found: $syncScriptPath"
        return
    }

    try {
        & $syncScriptPath | Out-Null
    }
    catch {
        Write-Warning ("Shared state sync failed after tests: {0}" -f $_.Exception.Message)
    }
}

if (-not (Test-Path -Path $testPath)) {
    throw "Test file not found: $testPath"
}

$pesterModule = Get-Module -ListAvailable -Name Pester | Sort-Object Version -Descending | Select-Object -First 1
if ($null -eq $pesterModule) {
    throw "Pester is not installed. Install with: Install-Module -Name Pester -Scope CurrentUser"
}

Import-Module Pester -RequiredVersion $pesterModule.Version -ErrorAction Stop | Out-Null

$invokePester = Get-Command -Name Invoke-Pester -ErrorAction Stop
$paramNames = @($invokePester.Parameters.Keys)

if ($paramNames -contains "Script") {
    $result = Invoke-Pester -Script $testPath -PassThru
}
elseif ($paramNames -contains "Path") {
    $result = Invoke-Pester -Path $testPath -PassThru
}
else {
    throw "Unsupported Pester Invoke-Pester parameter set on this machine."
}

$failedTestsRaw = @($result.TestResult | Where-Object { -not [bool]$_.Passed })
$failedTests = @()
$failedTransient = @()
$failedDeterministic = @()

foreach ($testItem in $failedTestsRaw) {
    $failureMessage = [string]$testItem.FailureMessage
    $isTransient = Test-IsTransientLockFailure -Message $failureMessage

    $entry = [pscustomobject]@{
        name = [string]$testItem.Name
        describe = [string]$testItem.Describe
        message = $failureMessage
        classification = if ($isTransient) { "transient" } else { "deterministic" }
    }

    $failedTests += $entry
    if ($isTransient) {
        $failedTransient += $entry
    }
    else {
        $failedDeterministic += $entry
    }
}

$summary = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = "tod-tests"
    path = $Path
    total = [int]$result.TotalCount
    passed = [int]$result.PassedCount
    failed = [int]$result.FailedCount
    skipped = [int]$result.SkippedCount
    pending = [int]$result.PendingCount
    inconclusive = if ($result.PSObject.Properties["InconclusiveCount"] -and $null -ne $result.InconclusiveCount) { [int]$result.InconclusiveCount } else { 0 }
    duration_seconds = [math]::Round(([double]$result.Time.TotalSeconds), 3)
    passed_all = ([int]$result.FailedCount -eq 0)
    failed_tests = @($failedTests)
    failed_test_classification = [pscustomobject]@{
        deterministic = @($failedDeterministic).Count
        transient = @($failedTransient).Count
    }
}

if (-not [string]::IsNullOrWhiteSpace($JsonOutputPath)) {
    $outputPath = if ([System.IO.Path]::IsPathRooted($JsonOutputPath)) { $JsonOutputPath } else { Join-Path $repoRoot $JsonOutputPath }
    $outDir = Split-Path -Parent $outputPath
    if (-not [string]::IsNullOrWhiteSpace($outDir) -and -not (Test-Path -Path $outDir)) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }

    $summary | ConvertTo-Json -Depth 8 | Set-Content -Path $outputPath
    Write-Host ("Wrote test summary JSON: {0}" -f $outputPath)
}

Invoke-SharedStateSyncIfEnabled

if ($FailOnTestFailure -and -not [bool]$summary.passed_all) {
    throw ("TOD tests failed. failed={0} passed={1}" -f $summary.failed, $summary.passed)
}

$summary | ConvertTo-Json -Depth 8
