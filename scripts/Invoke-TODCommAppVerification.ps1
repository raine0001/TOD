param(
    [string]$ProjectRoot = "E:/comm_app",
    [string]$OutputPath = "shared_state/agentmim/comm_app_verification.latest.json",
    [switch]$FailOnError,
    [switch]$EmitJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

function Resolve-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return [System.IO.Path]::GetFullPath($PathValue)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $PathValue))
}

function New-Check {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][bool]$Passed,
        [Parameter(Mandatory = $true)][string]$Detail,
        [bool]$Required = $true
    )

    return [pscustomobject]@{
        name = $Name
        passed = $Passed
        detail = $Detail
        required = $Required
    }
}

function Find-ProjectPython {
    param([Parameter(Mandatory = $true)][string]$Root)

    $candidates = @(
        (Join-Path $Root ".venv/Scripts/python.exe"),
        (Join-Path $Root "venv/Scripts/python.exe"),
        (Join-Path $Root ".venv/bin/python"),
        (Join-Path $Root "venv/bin/python")
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -Path $candidate -PathType Leaf) {
            return [System.IO.Path]::GetFullPath($candidate)
        }
    }

    return $null
}

function Get-GitSummary {
    param([Parameter(Mandatory = $true)][string]$Root)

    $result = [ordered]@{
        available = $false
        command_ok = $false
        branch = "unknown"
        raw = ""
        modified_count = 0
        untracked_count = 0
        ahead_behind = ""
    }

    try {
        $null = Get-Command git -ErrorAction Stop
        $result.available = $true
    }
    catch {
        return [pscustomobject]$result
    }

    try {
        $statusLines = @(git -C $Root status --short --branch 2>&1)
        if ($LASTEXITCODE -ne 0) {
            return [pscustomobject]$result
        }

        $result.command_ok = $true
        $result.raw = ($statusLines -join "`n")

        if (@($statusLines).Count -gt 0) {
            $header = [string]$statusLines[0]
            if ($header -match '^##\s+([^\.\s]+)') {
                $result.branch = $Matches[1]
            }
            if ($header -match 'ahead\s+(\d+)') {
                $result.ahead_behind = ($result.ahead_behind + "ahead " + $Matches[1]).Trim()
            }
            if ($header -match 'behind\s+(\d+)') {
                $result.ahead_behind = (($result.ahead_behind + " behind " + $Matches[1]).Trim())
            }
        }

        $body = @($statusLines | Select-Object -Skip 1)
        foreach ($line in $body) {
            $text = [string]$line
            if ([string]::IsNullOrWhiteSpace($text)) { continue }
            if ($text.StartsWith('??')) {
                $result.untracked_count++
            }
            else {
                $result.modified_count++
            }
        }
    }
    catch {
    }

    return [pscustomobject]$result
}

$resolvedProjectRoot = Resolve-LocalPath -PathValue $ProjectRoot
$resolvedOutputPath = Resolve-LocalPath -PathValue $OutputPath
$checks = @()

$smokeScript = Join-Path $PSScriptRoot "Invoke-TODCommAppMarketingSmoke.ps1"
$smokeOutputPath = Join-Path (Split-Path -Parent $resolvedOutputPath) "comm_app_marketing_smoke.latest.json"

$smokeReport = $null
$smokePassed = $false
$smokeDetail = "Marketing smoke did not run."
try {
    $smokeReport = & $smokeScript -ProjectRoot $resolvedProjectRoot -OutputPath $smokeOutputPath
    if ($smokeReport -and $smokeReport.PSObject.Properties['summary']) {
        $smokePassed = [bool]$smokeReport.summary.passed_all
        $smokeDetail = "Marketing smoke passed: $([string]$smokeReport.summary.passed)/$([string]$smokeReport.summary.total) checks."
    }
    else {
        $smokeDetail = "Marketing smoke returned no summary."
    }
}
catch {
    $smokeDetail = $_.Exception.Message
}
$checks += New-Check -Name "marketing_smoke" -Passed $smokePassed -Detail $smokeDetail

$pythonExe = Find-ProjectPython -Root $resolvedProjectRoot
$pythonFound = -not [string]::IsNullOrWhiteSpace($pythonExe)
$pythonDetail = if ($pythonFound) { $pythonExe } else { "No project-local python interpreter found under .venv or venv." }
$checks += New-Check -Name "project_local_python" -Passed $pythonFound -Detail $pythonDetail

$collectPassed = $false
$collectCount = $null
$collectOutput = ""
$collectDetail = "pytest collection not run."
if ($pythonFound) {
    try {
        Push-Location $resolvedProjectRoot
        $collectLines = @(& $pythonExe -m pytest --collect-only 2>&1)
        $exitCode = $LASTEXITCODE
        Pop-Location

        $collectOutput = ($collectLines -join "`n")
        if ($collectOutput -match 'collected\s+(\d+)\s+items') {
            $collectCount = [int]$Matches[1]
        }
        $collectPassed = ($exitCode -eq 0)
        $collectDetail = if ($collectPassed) {
            if ($null -ne $collectCount) {
                "pytest collection passed with $collectCount tests discovered."
            }
            else {
                "pytest collection passed."
            }
        }
        else {
            "pytest collection failed."
        }
    }
    catch {
        try { Pop-Location } catch {}
        $collectDetail = $_.Exception.Message
    }
}
$checks += New-Check -Name "pytest_collect_only" -Passed $collectPassed -Detail $collectDetail

$gitSummary = Get-GitSummary -Root $resolvedProjectRoot
$gitStatusPassed = [bool]($gitSummary.available -and $gitSummary.command_ok)
$gitStatusDetail = if ($gitSummary.command_ok) {
    "Git status read successfully."
}
elseif ($gitSummary.available) {
    "git is available but status failed."
}
else {
    "git command not available."
}
$checks += New-Check -Name "git_status_readable" -Passed $gitStatusPassed -Detail $gitStatusDetail

$repoClean = ([int]$gitSummary.modified_count -eq 0) -and ([int]$gitSummary.untracked_count -eq 0)
$repoCleanDetail = if ($repoClean) {
    "Repository working tree is clean."
}
else {
    "Repository has $([int]$gitSummary.modified_count) modified and $([int]$gitSummary.untracked_count) untracked entries."
}
$checks += New-Check -Name "repo_clean" -Passed $repoClean -Detail $repoCleanDetail -Required $false

$requiredFailures = @($checks | Where-Object { [bool]$_.required -and -not [bool]$_.passed }).Count
$warningCount = @($checks | Where-Object { -not [bool]$_.required -and -not [bool]$_.passed }).Count

$report = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = "tod-comm-app-verification-v1"
    project_id = "comm_app"
    project_root = $resolvedProjectRoot
    acceptance_surface = "/admin/marketing/?tab=video#video"
    local_python = $pythonExe
    facts = [pscustomobject]@{
        collected_tests = $collectCount
        git_branch = [string]$gitSummary.branch
        git_ahead_behind = [string]$gitSummary.ahead_behind
        git_modified_count = [int]$gitSummary.modified_count
        git_untracked_count = [int]$gitSummary.untracked_count
    }
    checks = @($checks)
    smoke = $smokeReport
    git = $gitSummary
    pytest_collect_output = $collectOutput
    summary = [pscustomobject]@{
        total = @($checks).Count
        required_failures = $requiredFailures
        warning_failures = $warningCount
        passed_required_gate = ($requiredFailures -eq 0)
        passed_all = ($requiredFailures -eq 0 -and $warningCount -eq 0)
    }
}

$outputDir = Split-Path -Parent $resolvedOutputPath
if (-not (Test-Path -Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$report | ConvertTo-Json -Depth 20 | Set-Content -Path $resolvedOutputPath

if ($EmitJson) {
    $report | ConvertTo-Json -Depth 12 | Write-Output
}
else {
    $report
}

if ($FailOnError -and $requiredFailures -gt 0) {
    throw "comm_app verification reported one or more required failures."
}