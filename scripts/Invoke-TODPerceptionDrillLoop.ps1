param(
    [string]$OutputDir = 'tod/out/training/perception-drills',
    [switch]$SkipTests,
    [switch]$SkipSample,
    [switch]$FailOnError
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$effectiveOutputDir = if ([System.IO.Path]::IsPathRooted($OutputDir)) { $OutputDir } else { Join-Path $repoRoot $OutputDir }
$testsPath = Join-Path $repoRoot 'tests/TOD.PerceptionExecutionReadiness.Tests.ps1'
$sampleScriptPath = Join-Path $PSScriptRoot 'Invoke-TODPerceptionWorkspaceExecutionSample.ps1'
$sampleArtifactPath = Join-Path $repoRoot 'shared_state/bus_perception_workspace_execution_sample.json'

if (-not (Test-Path -Path $effectiveOutputDir)) {
    New-Item -ItemType Directory -Path $effectiveOutputDir -Force | Out-Null
}

$errors = @()
$testSummary = $null
$sampleSummary = $null

if (-not $SkipTests) {
    try {
        $pester = Invoke-Pester -Path $testsPath -PassThru
        $failedCount = if ($pester.PSObject.Properties['FailedCount']) { [int]$pester.FailedCount } else { 0 }
        $passedCount = if ($pester.PSObject.Properties['PassedCount']) { [int]$pester.PassedCount } else { 0 }
        $totalCount = if ($pester.PSObject.Properties['TotalCount']) { [int]$pester.TotalCount } else { ($passedCount + $failedCount) }
        $testSummary = [pscustomobject]@{
            passed = $passedCount
            failed = $failedCount
            total = $totalCount
            passed_all = ($failedCount -eq 0)
            path = $testsPath
        }
    }
    catch {
        $errors += "perception-tests: $($_.Exception.Message)"
    }
}

if (-not $SkipSample) {
    try {
        & $sampleScriptPath -RunSampleLoop | Out-Null
        $sample = if (Test-Path -Path $sampleArtifactPath) { Get-Content -Path $sampleArtifactPath -Raw | ConvertFrom-Json } else { $null }
        $reasonCodes = @()
        if ($sample -and $sample.PSObject.Properties['bounded_execution_flow'] -and $sample.bounded_execution_flow.PSObject.Properties['lifecycle_reason_codes']) {
            $reasonCodes = @($sample.bounded_execution_flow.lifecycle_reason_codes)
        }
        $sampleSummary = [pscustomobject]@{
            artifact_path = $sampleArtifactPath
            available = ($null -ne $sample)
            source_domain = if ($sample) { [string]$sample.bounded_execution_flow.source_domain } else { '' }
            source_context = if ($sample) { [string]$sample.bounded_execution_flow.source_context } else { '' }
            lifecycle_reason_codes = @($reasonCodes)
        }
    }
    catch {
        $errors += "perception-sample: $($_.Exception.Message)"
    }
}

$report = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    source = 'tod-perception-drill-loop-v1'
    tests = if ($null -ne $testSummary) { $testSummary } else { [pscustomobject]@{ skipped = [bool]$SkipTests } }
    sample = if ($null -ne $sampleSummary) { $sampleSummary } else { [pscustomobject]@{ skipped = [bool]$SkipSample } }
    next_focus = @(
        'Expand perception drills to cover degraded-but-safe contexts with richer source_context routing.',
        'Feed drill summaries into the continuous training report for broader competency scoring.',
        'Add a recurring idle-time perception drill task once the lightweight training pipeline is stable.'
    )
    errors = @($errors)
}

$jsonPath = Join-Path $effectiveOutputDir 'perception-drill-report.json'
$mdPath = Join-Path $effectiveOutputDir 'perception-drill-report.md'
$report | ConvertTo-Json -Depth 20 | Set-Content -Path $jsonPath

$md = @()
$md += '# TOD Perception Drill Report'
$md += ''
$md += "Generated: $($report.generated_at)"
$md += ''
$md += '## Tests'
if ($testSummary) {
    $md += "- Passed: $($testSummary.passed)"
    $md += "- Failed: $($testSummary.failed)"
    $md += "- Total: $($testSummary.total)"
} else {
    $md += '- Skipped'
}
$md += ''
$md += '## Sample Loop'
if ($sampleSummary) {
    $md += "- Artifact: $($sampleSummary.artifact_path)"
    $md += "- Source domain: $($sampleSummary.source_domain)"
    $md += "- Source context: $($sampleSummary.source_context)"
    $md += "- Reason codes: $([string]::Join(', ', @($sampleSummary.lifecycle_reason_codes)))"
} else {
    $md += '- Skipped'
}
if (@($errors).Count -gt 0) {
    $md += ''
    $md += '## Errors'
    foreach ($err in $errors) { $md += "- $err" }
}
$md -join [Environment]::NewLine | Set-Content -Path $mdPath

$result = [pscustomobject]@{
    ok = (@($errors).Count -eq 0)
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    report_json = $jsonPath
    report_markdown = $mdPath
    errors = @($errors)
}

$result | ConvertTo-Json -Depth 10 | Write-Output

if ($FailOnError -and @($errors).Count -gt 0) {
    throw 'Perception drill loop completed with errors.'
}