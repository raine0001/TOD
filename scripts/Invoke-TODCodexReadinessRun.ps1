param(
    [ValidateSet("review", "debug", "fixes", "plan", "operator")]
    [string]$Mode = "review",
    [string[]]$FilePaths = @(),
    [string]$OutputRoot = "shared_state/conversation_eval/codex_readiness",
    [int]$MaxFiles = 3,
    [int]$MaxLinesPerFile = 120,
    [double]$MinAverageUtility = 0.74,
    [int]$MaxAssistFailures = 0,
    [int]$MaxChangedFiles = 4,
    [string[]]$AllowedEditPaths = @("scripts/", "tod/", "shared_state/conversation_eval/"),
    [string]$TestCommand = "",
    [switch]$RequireCleanWorktree,
    [switch]$EmitJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

function Resolve-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) { return [System.IO.Path]::GetFullPath($PathValue) }
    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $PathValue))
}

function Get-GitChangedPaths {
    param([Parameter(Mandatory = $true)][string]$RepoRoot)

    $paths = @()
    try {
        $inside = (& git -C $RepoRoot rev-parse --is-inside-work-tree 2>$null)
        if ([string]$inside -ne "true") {
            return @()
        }

        $rows = @(& git -C $RepoRoot status --porcelain)
        foreach ($row in $rows) {
            $line = [string]$row
            if ([string]::IsNullOrWhiteSpace($line) -or $line.Length -lt 4) { continue }
            $candidate = $line.Substring(3).Trim()
            if ($candidate -like "*->*") {
                $candidate = ($candidate -split "->")[-1].Trim()
            }
            $candidate = $candidate -replace "\\", "/"
            if (-not [string]::IsNullOrWhiteSpace($candidate)) {
                $paths += $candidate
            }
        }
    }
    catch {
        return @()
    }

    return @($paths | Select-Object -Unique)
}

function Measure-Rate {
    param([double]$Numerator, [double]$Denominator)
    if ($Denominator -le 0) { return 0.0 }
    return [math]::Round(($Numerator / $Denominator), 4)
}

$assistScript = Join-Path $PSScriptRoot "Invoke-TODRealCodeAssist.ps1"
if (-not (Test-Path -Path $assistScript)) {
    throw "Missing assist script: $assistScript"
}

$outputRootAbs = Resolve-LocalPath -PathValue $OutputRoot
if (-not (Test-Path -Path $outputRootAbs)) {
    New-Item -ItemType Directory -Path $outputRootAbs -Force | Out-Null
}

$runId = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
$runPath = Join-Path $outputRootAbs ("tod_codex_readiness.{0}.json" -f $runId)
$latestPath = Join-Path $outputRootAbs "tod_codex_readiness.latest.json"

$beforePaths = @(Get-GitChangedPaths -RepoRoot $repoRoot)
$assist = & $assistScript -Mode $Mode -FilePaths $FilePaths -MaxFiles $MaxFiles -MaxLinesPerFile $MaxLinesPerFile -EmitJson | ConvertFrom-Json
$afterPaths = @(Get-GitChangedPaths -RepoRoot $repoRoot)

$deltaPaths = @($afterPaths | Where-Object { $beforePaths -notcontains $_ })
$normalizedAllowed = @($AllowedEditPaths | ForEach-Object { ([string]$_).Replace("\\", "/") })
$disallowedPaths = @($deltaPaths | Where-Object {
        $p = [string]$_
        $ok = $false
        foreach ($prefix in $normalizedAllowed) {
            if ([string]::IsNullOrWhiteSpace($prefix)) { continue }
            if ($p.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                $ok = $true
                break
            }
        }
        -not $ok
    })

$testsPassed = $true
$testExitCode = 0
$testOutput = ""
if (-not [string]::IsNullOrWhiteSpace($TestCommand)) {
    try {
        $testOutput = (& powershell -NoProfile -Command $TestCommand 2>&1 | Out-String)
        $testExitCode = $LASTEXITCODE
        $testsPassed = ($testExitCode -eq 0)
    }
    catch {
        $testsPassed = $false
        $testExitCode = 1
        $testOutput = $_.Exception.Message
    }
}

$fileCount = [int]$assist.config.file_count
$passCount = [int]$assist.summary.pass_count
$failCount = [int]$assist.summary.failure_count
$taskSuccessRate = Measure-Rate -Numerator $passCount -Denominator $fileCount
$firstPassSuccessRate = $taskSuccessRate
$reworkRate = [math]::Round((1.0 - $taskSuccessRate), 4)
$acceptWithoutEditRate = if ($Mode -eq "fixes") {
    Measure-Rate -Numerator ([double]($fileCount - $failCount)) -Denominator $fileCount
}
else {
    if (@($deltaPaths).Count -eq 0) { 1.0 } else { 0.0 }
}

$utilityGatePassed = ([double]$assist.summary.average_utility -ge $MinAverageUtility)
$assistFailuresGatePassed = ($failCount -le $MaxAssistFailures)
$changedFileCountGatePassed = (@($deltaPaths).Count -le $MaxChangedFiles)
$allowedPathsGatePassed = (@($disallowedPaths).Count -eq 0)
$noUnexpectedEditsGatePassed = if ($Mode -eq "fixes") { $true } else { @($deltaPaths).Count -eq 0 }
$cleanWorktreeGatePassed = if ($RequireCleanWorktree) { @($beforePaths).Count -eq 0 } else { $true }
$testsGatePassed = $testsPassed

$hardPatchGates = [pscustomobject]@{
    clean_worktree_before_run = $cleanWorktreeGatePassed
    min_average_utility_passed = $utilityGatePassed
    max_assist_failures_passed = $assistFailuresGatePassed
    max_changed_files_passed = $changedFileCountGatePassed
    allowed_paths_only_passed = $allowedPathsGatePassed
    no_unexpected_edits_passed = $noUnexpectedEditsGatePassed
    tests_passed = $testsGatePassed
}

$gatePassed = [bool](
    $cleanWorktreeGatePassed -and
    $utilityGatePassed -and
    $assistFailuresGatePassed -and
    $changedFileCountGatePassed -and
    $allowedPathsGatePassed -and
    $noUnexpectedEditsGatePassed -and
    $testsGatePassed
)

$report = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = "tod-codex-readiness-runner-v1"
    run_id = $runId
    config = [pscustomobject]@{
        mode = $Mode
        output_root = $OutputRoot
        max_files = $MaxFiles
        max_lines_per_file = $MaxLinesPerFile
        min_average_utility = $MinAverageUtility
        max_assist_failures = $MaxAssistFailures
        max_changed_files = $MaxChangedFiles
        allowed_edit_paths = @($AllowedEditPaths)
        test_command = $TestCommand
        require_clean_worktree = [bool]$RequireCleanWorktree
    }
    summary = [pscustomobject]@{
        gate_passed = $gatePassed
        average_utility = [double]$assist.summary.average_utility
        file_count = $fileCount
        pass_count = $passCount
        failure_count = $failCount
        task_success_rate = $taskSuccessRate
        first_pass_success_rate = $firstPassSuccessRate
        rework_rate = $reworkRate
        accept_without_edit_rate = $acceptWithoutEditRate
        changed_files_delta_count = @($deltaPaths).Count
    }
    hard_patch_gates = $hardPatchGates
    git = [pscustomobject]@{
        changed_paths_before = @($beforePaths)
        changed_paths_after = @($afterPaths)
        changed_paths_delta = @($deltaPaths)
        disallowed_paths_delta = @($disallowedPaths)
    }
    tests = [pscustomobject]@{
        command = $TestCommand
        passed = $testsPassed
        exit_code = $testExitCode
        output = $testOutput
    }
    assist_summary = $assist.summary
    assist_results = $assist.results
    artifacts = [pscustomobject]@{
        run_path = $runPath
        latest_path = $latestPath
        assist_latest_path = "shared_state/conversation_eval/real_usage/tod_real_code_assist.latest.json"
    }
}

$report | ConvertTo-Json -Depth 30 | Set-Content -Path $runPath
$report | ConvertTo-Json -Depth 30 | Set-Content -Path $latestPath

if ($EmitJson) {
    $report | ConvertTo-Json -Depth 12 | Write-Output
}
else {
    $report
}
