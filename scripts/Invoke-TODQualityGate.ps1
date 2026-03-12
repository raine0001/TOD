param(
    [int]$BurnInRuns = 3,
    [string]$TestScript = "tests/TOD.Tests.ps1",
    [int]$MaxTransientLockFailureRuns = 0,
    [string]$OutputPath = "tod/out/training/quality-gate-summary.json",
    [switch]$SkipSharedStateSync,
    [string]$SharedStateSyncScript = "scripts/Invoke-TODSharedStateSync.ps1"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$resolvedTestScript = if ([System.IO.Path]::IsPathRooted($TestScript)) { $TestScript } else { Join-Path $repoRoot $TestScript }
$resolvedOutputPath = if ([System.IO.Path]::IsPathRooted($OutputPath)) { $OutputPath } else { Join-Path $repoRoot $OutputPath }

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
        Write-Warning ("Shared state sync failed after quality gate: {0}" -f $_.Exception.Message)
    }
}

if (-not (Test-Path -Path $resolvedTestScript)) {
    throw "Test script not found: $resolvedTestScript"
}

function Test-IsTransientLockFailure {
    param([string]$Message)

    if ([string]::IsNullOrWhiteSpace($Message)) { return $false }

    $m = $Message.ToLowerInvariant()
    return (
        ($m -match "state\.json") -and
        ($m -match "used by another process|cannot access the file")
    )
}

function Get-ResultCount {
    param(
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)][string]$PropertyName
    )

    if ($Result.PSObject.Properties[$PropertyName]) {
        return [int]$Result.$PropertyName
    }

    return 0
}

$runs = @()
for ($i = 1; $i -le $BurnInRuns; $i++) {
    $started = Get-Date
    $p = Invoke-Pester -Script $resolvedTestScript -PassThru
    $duration = [math]::Round(((Get-Date) - $started).TotalSeconds, 2)

    $failedTests = @($p.TestResult | Where-Object { -not [bool]$_.Passed })
    $transientFailures = @()
    $deterministicFailures = @()

    foreach ($t in $failedTests) {
        $msg = [string]$t.FailureMessage
        $entry = [pscustomobject]@{
            name = [string]$t.Name
            describe = [string]$t.Describe
            message = $msg
        }

        if (Test-IsTransientLockFailure -Message $msg) {
            $transientFailures += $entry
        }
        else {
            $deterministicFailures += $entry
        }
    }

    $runs += [pscustomobject]@{
        run = $i
        total = Get-ResultCount -Result $p -PropertyName "TotalCount"
        passed = Get-ResultCount -Result $p -PropertyName "PassedCount"
        failed = Get-ResultCount -Result $p -PropertyName "FailedCount"
        skipped = Get-ResultCount -Result $p -PropertyName "SkippedCount"
        pending = Get-ResultCount -Result $p -PropertyName "PendingCount"
        inconclusive = Get-ResultCount -Result $p -PropertyName "InconclusiveCount"
        duration_seconds = $duration
        transient_lock_failures = @($transientFailures)
        deterministic_failures = @($deterministicFailures)
        passed_all = ((Get-ResultCount -Result $p -PropertyName "FailedCount") -eq 0)
    }

    Write-Host ("QUALITY_GATE_RUN {0}/{1} passed={2} failed={3} transient={4} deterministic={5} duration={6}s" -f
        $i,
        $BurnInRuns,
        [int]$p.PassedCount,
        [int]$p.FailedCount,
        @($transientFailures).Count,
        @($deterministicFailures).Count,
        $duration)
}

$transientFailureRuns = [int]@($runs | Where-Object { @($_.transient_lock_failures).Count -gt 0 }).Count
$deterministicFailureRuns = [int]@($runs | Where-Object { @($_.deterministic_failures).Count -gt 0 }).Count
$allFailedTests = [int](@($runs | ForEach-Object { [int]$_.failed } | Measure-Object -Sum).Sum)

$gatePassed = ($deterministicFailureRuns -eq 0 -and $transientFailureRuns -le $MaxTransientLockFailureRuns)

$result = [pscustomobject]@{
    ok = $gatePassed
    source = "tod-quality-gate-v1"
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    policy = [pscustomobject]@{
        burn_in_runs = $BurnInRuns
        max_transient_lock_failure_runs = $MaxTransientLockFailureRuns
    }
    summary = [pscustomobject]@{
        run_success_rate = [math]::Round(([double]@($runs | Where-Object { [bool]$_.passed_all }).Count / [double][math]::Max(1, $BurnInRuns)), 4)
        failed_tests_total = $allFailedTests
        transient_lock_failure_runs = $transientFailureRuns
        deterministic_failure_runs = $deterministicFailureRuns
    }
    runs = @($runs)
}

$outputDir = Split-Path -Parent $resolvedOutputPath
if (-not [string]::IsNullOrWhiteSpace($outputDir) -and -not (Test-Path -Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$result | ConvertTo-Json -Depth 20 | Set-Content -Path $resolvedOutputPath
$result | ConvertTo-Json -Depth 20 | Write-Output

Invoke-SharedStateSyncIfEnabled

if (-not $gatePassed) {
    exit 2
}
