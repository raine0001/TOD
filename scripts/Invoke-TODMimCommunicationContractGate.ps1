param(
    [string]$OutputPath = "tod/out/results-v2/tod-mim-communication-contract.latest.json",
    [string]$MarkdownOutputPath = "tod/out/results-v2/tod-mim-communication-contract.latest.md",
    [switch]$FailOnFailure,
    [switch]$EmitJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$testRunner = Join-Path $PSScriptRoot 'Invoke-TODTests.ps1'
$testSuites = @(
    [pscustomobject]@{
        name = 'next_step_consensus'
        path = 'tests/TOD.NextStepConsensus.Tests.ps1'
        purpose = 'Same-session adjudication, reminder flow, and structured finding consensus behavior.'
    },
    [pscustomobject]@{
        name = 'conversation_simulation'
        path = 'tests/TOD.TODMimConversationSimulation.Tests.ps1'
        purpose = 'Synthetic dialog routing, inbox semantics, supersede/reissue, and end-to-end consensus roundtrip behavior.'
    }
)

function Resolve-RepoPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return [System.IO.Path]::GetFullPath($PathValue)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $PathValue))
}

function Ensure-Directory {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if (-not (Test-Path -Path $PathValue)) {
        New-Item -ItemType Directory -Path $PathValue -Force | Out-Null
    }
}

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $dir = Split-Path -Parent $PathValue
    if (-not [string]::IsNullOrWhiteSpace($dir)) {
        Ensure-Directory -PathValue $dir
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($PathValue, $Content, $utf8NoBom)
}

if (-not (Test-Path -Path $testRunner)) {
    throw "Missing test runner: $testRunner"
}

$resolvedOutputPath = Resolve-RepoPath -PathValue $OutputPath
$resolvedMarkdownPath = Resolve-RepoPath -PathValue $MarkdownOutputPath
$outputDir = Split-Path -Parent $resolvedOutputPath
$suiteOutputDir = Join-Path $outputDir 'tod-mim-communication-contract-suites'
Ensure-Directory -PathValue $suiteOutputDir

$suiteResults = @()
foreach ($suite in $testSuites) {
    $suiteOutputPath = Join-Path $suiteOutputDir ($suite.name + '.latest.json')
    $suiteStarted = Get-Date
    $suiteSummary = (& $testRunner -Path $suite.path -JsonOutputPath $suiteOutputPath -SkipSharedStateSync) | ConvertFrom-Json
    $suiteDurationSeconds = [math]::Round(((Get-Date) - $suiteStarted).TotalSeconds, 3)

    $suiteResults += [pscustomobject]@{
        name = [string]$suite.name
        path = [string]$suite.path
        purpose = [string]$suite.purpose
        synthetic_only = $true
        passed = [bool]$suiteSummary.passed_all
        total = [int]$suiteSummary.total
        passed_count = [int]$suiteSummary.passed
        failed_count = [int]$suiteSummary.failed
        duration_seconds = $suiteDurationSeconds
        summary_path = $suiteOutputPath
        summary = $suiteSummary
    }
}

$totalTests = [int]((@($suiteResults | Measure-Object -Property total -Sum).Sum))
$passedTests = [int]((@($suiteResults | Measure-Object -Property passed_count -Sum).Sum))
$failedTests = [int]((@($suiteResults | Measure-Object -Property failed_count -Sum).Sum))
$failedSuites = @($suiteResults | Where-Object { -not [bool]$_.passed })
$gatePassed = (@($failedSuites).Count -eq 0)

$report = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    source = 'tod-mim-communication-contract-gate-v1'
    label = 'TOD<->MIM communication contract'
    scope = [pscustomobject]@{
        synthetic_only = $true
        contract_lane = 'dialog_adjudication_only'
        live_runtime_validation = $false
        authority_boundary = 'listener-stage execution authority remains validated separately'
    }
    coverage = [pscustomobject]@{
        included = @(
            'dialog routing',
            'actionable inbox and session index semantics',
            'same-session reply expectation handling',
            'next-step consensus flow',
            'timeout reminder behavior',
            'supersede and reissue semantics'
        )
        excluded = @(
            'live listener execution validation',
            'request-trigger-ack-result execution-lane certification',
            'production-like shared root mutation'
        )
    }
    canonical_command = '.\scripts\Invoke-TODMimCommunicationContractGate.ps1 -EmitJson'
    artifacts = [pscustomobject]@{
        latest_path = $resolvedOutputPath
        markdown_path = $resolvedMarkdownPath
        suite_output_dir = $suiteOutputDir
    }
    summary = [pscustomobject]@{
        gate_passed = $gatePassed
        suites_total = @($suiteResults).Count
        suites_passed = @(@($suiteResults | Where-Object { [bool]$_.passed })).Count
        suites_failed = @($failedSuites).Count
        tests_total = $totalTests
        tests_passed = $passedTests
        tests_failed = $failedTests
    }
    suites = @($suiteResults)
}

$reportJson = ($report | ConvertTo-Json -Depth 20) -replace "`r`n", "`n"
Write-Utf8NoBom -PathValue $resolvedOutputPath -Content $reportJson

$markdownLines = @(
    '# TOD MIM Communication Contract Gate',
    '',
    ('- generated_at: {0}' -f [string]$report.generated_at),
    ('- source: {0}' -f [string]$report.source),
    ('- label: {0}' -f [string]$report.label),
    ('- synthetic_only: {0}' -f [string]$report.scope.synthetic_only),
    ('- contract_lane: {0}' -f [string]$report.scope.contract_lane),
    ('- live_runtime_validation: {0}' -f [string]$report.scope.live_runtime_validation),
    ('- gate_passed: {0}' -f [string]$report.summary.gate_passed),
    ('- suites: {0}/{1}' -f [string]$report.summary.suites_passed, [string]$report.summary.suites_total),
    ('- tests: {0}/{1}' -f [string]$report.summary.tests_passed, [string]$report.summary.tests_total),
    ('- canonical_command: {0}' -f [string]$report.canonical_command),
    '',
    '## Included Coverage',
    ''
)

foreach ($item in @($report.coverage.included)) {
    $markdownLines += ('- {0}' -f [string]$item)
}

$markdownLines += @(
    '',
    '## Excluded Coverage',
    ''
)

foreach ($item in @($report.coverage.excluded)) {
    $markdownLines += ('- {0}' -f [string]$item)
}

$markdownLines += @(
    '',
    '## Suite Results',
    ''
)

foreach ($suite in $suiteResults) {
    $markdownLines += ('- {0}: passed={1} tests={2}/{3} path={4}' -f [string]$suite.name, [string]$suite.passed, [string]$suite.passed_count, [string]$suite.total, [string]$suite.path)
}

$markdownContent = ($markdownLines -join "`n") + "`n"
Write-Utf8NoBom -PathValue $resolvedMarkdownPath -Content $markdownContent

Write-Host ('TOD_MIM_COMMUNICATION_CONTRACT_PATH={0}' -f $OutputPath)
Write-Host ('TOD_MIM_COMMUNICATION_CONTRACT_MARKDOWN_PATH={0}' -f $MarkdownOutputPath)
Write-Host ('TOD_MIM_COMMUNICATION_CONTRACT_STATUS={0}' -f $(if ($gatePassed) { 'pass' } else { 'fail' }))

if ($EmitJson) {
    $reportJson | Write-Output
}
else {
    $report
}

if ($FailOnFailure -and -not $gatePassed) {
    throw ('TOD<->MIM communication contract gate failed. See artifact: {0}' -f $resolvedOutputPath)
}