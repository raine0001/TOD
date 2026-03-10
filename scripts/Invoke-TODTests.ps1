param(
    [string]$Path = "tests/*.Tests.ps1",
    [string]$JsonOutputPath,
    [switch]$FailOnTestFailure
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$testPath = Join-Path $repoRoot $Path

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

if ($FailOnTestFailure -and -not [bool]$summary.passed_all) {
    throw ("TOD tests failed. failed={0} passed={1}" -f $summary.failed, $summary.passed)
}

$summary | ConvertTo-Json -Depth 8
