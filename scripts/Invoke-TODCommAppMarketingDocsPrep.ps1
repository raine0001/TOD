param(
    [string]$ProjectRoot = "E:/comm_app",
    [string]$DemoUser = "demo-admin",
    [string]$DemoPassword,
    [string]$DemoEmail = "demo-admin@example.com",
    [string]$OutputPath = "shared_state/agentmim/comm_app_marketing_docs_prep.latest.json",
    [switch]$Reset,
    [switch]$EmitJson,
    [switch]$FailOnError
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
$pythonExe = Find-ProjectPython -Root $resolvedProjectRoot

$report = [ordered]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = "tod-comm-app-marketing-docs-prep-v1"
    project_id = "comm_app"
    project_root = $resolvedProjectRoot
    command = "flask seed-marketing-demo"
    local_python = $pythonExe
    demo_user = $DemoUser
    demo_email = $DemoEmail
    reset = [bool]$Reset
    success = $false
    detail = "Not run."
    output = ""
}

if ([string]::IsNullOrWhiteSpace($pythonExe)) {
    $report.detail = "No project-local python interpreter found under .venv or venv."
}
else {
    $previousFlaskApp = $env:FLASK_APP
    $previousDemoUser = $env:MARKETING_DEMO_USER
    $previousDemoPass = $env:MARKETING_DEMO_PASS
    $previousDemoEmail = $env:MARKETING_DEMO_EMAIL

    try {
        $env:FLASK_APP = "run.py"
        $env:MARKETING_DEMO_USER = $DemoUser
        $env:MARKETING_DEMO_EMAIL = $DemoEmail
        if ($PSBoundParameters.ContainsKey('DemoPassword')) {
            $env:MARKETING_DEMO_PASS = $DemoPassword
        }

        $arguments = @("-m", "flask", "seed-marketing-demo")
        if ($Reset) {
            $arguments += "--reset"
        }
        if ($PSBoundParameters.ContainsKey('DemoPassword')) {
            $arguments += @("--password", $DemoPassword)
        }
        if ($PSBoundParameters.ContainsKey('DemoUser')) {
            $arguments += @("--username", $DemoUser)
        }
        if ($PSBoundParameters.ContainsKey('DemoEmail')) {
            $arguments += @("--email", $DemoEmail)
        }

        Push-Location $resolvedProjectRoot
        $commandOutput = @(& $pythonExe @arguments 2>&1)
        $exitCode = $LASTEXITCODE
        Pop-Location

        $report.output = ($commandOutput -join "`n")
        $report.success = ($exitCode -eq 0)
        $report.detail = if ($report.success) {
            "Marketing docs prep completed."
        }
        else {
            "Marketing docs prep failed."
        }
    }
    catch {
        try { Pop-Location } catch {}
        $report.detail = $_.Exception.Message
    }
    finally {
        $env:FLASK_APP = $previousFlaskApp
        $env:MARKETING_DEMO_USER = $previousDemoUser
        $env:MARKETING_DEMO_PASS = $previousDemoPass
        $env:MARKETING_DEMO_EMAIL = $previousDemoEmail
    }
}

$outputDir = Split-Path -Parent $resolvedOutputPath
if (-not (Test-Path -Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$json = ($report | ConvertTo-Json -Depth 6)
Set-Content -Path $resolvedOutputPath -Value $json -Encoding UTF8

if ($EmitJson) {
    $json
}
else {
    [pscustomobject]$report
}

if ($FailOnError -and -not [bool]$report.success) {
    throw $report.detail
}