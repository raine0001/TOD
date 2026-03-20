param(
    [string]$ProjectRoot = "E:/comm_app",
    [int]$Runs = 1,
    [int]$Duration = 6,
    [string]$Pipeline = "auto",
    [string]$OutputPath = "shared_state/agentmim/comm_app_spokesperson_qa.latest.json",
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
        [bool]$Required = $false
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

$resolvedProjectRoot = Resolve-LocalPath -PathValue $ProjectRoot
$resolvedOutputPath = Resolve-LocalPath -PathValue $OutputPath
$checks = @()

if ($Runs -lt 1) {
    throw 'Runs must be greater than or equal to 1.'
}

$pythonExe = Find-ProjectPython -Root $resolvedProjectRoot
$pythonFound = -not [string]::IsNullOrWhiteSpace($pythonExe)
$checks += New-Check -Name 'project_local_python' -Passed $pythonFound -Detail $(if ($pythonFound) { $pythonExe } else { 'No project-local python interpreter found under .venv or venv.' })

$qaScript = Join-Path $resolvedProjectRoot 'scripts/qa_spokesperson_expression.py'
$qaScriptExists = Test-Path -Path $qaScript -PathType Leaf
$checks += New-Check -Name 'qa_script_present' -Passed $qaScriptExists -Detail $qaScript

$qaOutputPath = Join-Path (Split-Path -Parent $resolvedOutputPath) 'comm_app_spokesperson_qa_run.latest.json'
$qaRunPassed = $false
$qaRunDetail = 'QA advisory gate did not run.'
$qaStdout = ''
$qaReport = $null

if ($Duration -lt 5) {
    $checks += New-Check -Name 'qa_duration_valid' -Passed $false -Detail 'QA advisory requires duration >= 5 seconds to satisfy JobRequest validation.' -Required $false
}
else {
    $checks += New-Check -Name 'qa_duration_valid' -Passed $true -Detail ('Using advisory duration of {0} seconds.' -f $Duration) -Required $false
}

if ($pythonFound -and $qaScriptExists -and $Duration -ge 5) {
    try {
        $previousNativePreference = $false
        if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
            $previousNativePreference = [bool]$PSNativeCommandUseErrorActionPreference
        }
        $PSNativeCommandUseErrorActionPreference = $false
        Push-Location $resolvedProjectRoot
        $stdoutLines = @(& $pythonExe $qaScript --runs $Runs --duration $Duration --pipeline $Pipeline --output-json $qaOutputPath 2>&1)
        $exitCode = $LASTEXITCODE
        Pop-Location
        $PSNativeCommandUseErrorActionPreference = $previousNativePreference

        $qaStdout = ($stdoutLines -join "`n")
        if (Test-Path -Path $qaOutputPath -PathType Leaf) {
            $qaReport = Get-Content -Path $qaOutputPath -Raw | ConvertFrom-Json
        }

        $qaRunPassed = ($exitCode -eq 0)
        if ($null -ne $qaReport -and $qaReport.PSObject.Properties['summary']) {
            $qaRunDetail = 'QA advisory pass rate: ' + [string]$qaReport.summary.pass_rate_percent + '% (' + [string]$qaReport.summary.passes + '/' + [string]$qaReport.summary.runs + ').'
        }
        elseif ($qaRunPassed) {
            $qaRunDetail = 'QA advisory gate completed successfully.'
        }
        else {
            $qaRunDetail = 'QA advisory gate completed with a non-zero exit code.'
        }
    }
    catch {
        try { Pop-Location } catch {}
        if (Get-Variable -Name previousNativePreference -ErrorAction SilentlyContinue) {
            $PSNativeCommandUseErrorActionPreference = $previousNativePreference
        }
        $qaRunDetail = $_.Exception.Message
    }
}

$checks += New-Check -Name 'spokesperson_expression_advisory' -Passed $qaRunPassed -Detail $qaRunDetail -Required $false

$requiredFailures = @($checks | Where-Object { [bool]$_.required -and -not [bool]$_.passed }).Count
$warningCount = @($checks | Where-Object { -not [bool]$_.required -and -not [bool]$_.passed }).Count

$report = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    source = 'tod-comm-app-spokesperson-qa-v1'
    project_id = 'comm_app'
    project_root = $resolvedProjectRoot
    acceptance_surface = '/admin/marketing/?tab=video#video'
    advisory = $true
    settings = [pscustomobject]@{
        runs = $Runs
        duration = $Duration
        pipeline = $Pipeline
    }
    checks = @($checks)
    qa_script = $qaScript
    qa_output_path = $qaOutputPath
    qa_report = $qaReport
    qa_stdout = $qaStdout
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
    throw 'comm_app spokesperson QA gate reported required failures.'
}