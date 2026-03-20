param(
    [string]$ProjectRoot = "E:/comm_app",
    [string]$BaseUrl = "http://127.0.0.1:6001",
    [string]$DemoUser = "demo-admin",
    [string]$DemoPassword,
    [string]$DemoEmail = "demo-admin@example.com",
    [string]$OutputPath = "shared_state/agentmim/comm_app_marketing_docs_capture.latest.json",
    [switch]$Reset,
    [switch]$BootstrapAuth,
    [switch]$InstallDependencies,
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

function Find-CommandPath {
    param([Parameter(Mandatory = $true)][string]$Name)

    try {
        $command = Get-Command $Name -ErrorAction Stop
        return $command.Source
    }
    catch {
        return $null
    }
}

$resolvedProjectRoot = Resolve-LocalPath -PathValue $ProjectRoot
$resolvedOutputPath = Resolve-LocalPath -PathValue $OutputPath
$prepScript = Join-Path $PSScriptRoot "Invoke-TODCommAppMarketingDocsPrep.ps1"
$nodePath = Find-CommandPath -Name "node"
$npmPath = Find-CommandPath -Name "npm"

$report = [ordered]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = "tod-comm-app-marketing-docs-capture-v1"
    project_id = "comm_app"
    project_root = $resolvedProjectRoot
    base_url = $BaseUrl
    node_available = -not [string]::IsNullOrWhiteSpace($nodePath)
    npm_available = -not [string]::IsNullOrWhiteSpace($npmPath)
    node_path = $nodePath
    npm_path = $npmPath
    docs_prep = $null
    dependency_install = [ordered]@{ attempted = $false; success = $false; output = "" }
    auth_bootstrap = [ordered]@{ attempted = $false; success = $false; output = "" }
    screenshot_capture = [ordered]@{ attempted = $false; success = $false; output = "" }
    success = $false
    detail = "Not run."
}

$prepArgs = @{
    ProjectRoot = $resolvedProjectRoot
    DemoUser = $DemoUser
    DemoEmail = $DemoEmail
    Reset = [bool]$Reset
}
if ($PSBoundParameters.ContainsKey('DemoPassword')) {
    $prepArgs.DemoPassword = $DemoPassword
}
$prepResult = & $prepScript @prepArgs
$report.docs_prep = $prepResult

if (-not [bool]$prepResult.success) {
    $report.detail = "Marketing docs prep failed."
}
elseif (-not $report.node_available -or -not $report.npm_available) {
    $report.detail = "node and npm are required for Playwright capture."
}
else {
    $previousBaseUrl = $env:PLAYWRIGHT_BASE_URL
    $previousDocsUser = $env:MIM_DOCS_USERNAME
    $previousDocsPass = $env:MIM_DOCS_PASSWORD
    try {
        $env:PLAYWRIGHT_BASE_URL = $BaseUrl
        $env:MIM_DOCS_USERNAME = $DemoUser
        if ($PSBoundParameters.ContainsKey('DemoPassword')) {
            $env:MIM_DOCS_PASSWORD = $DemoPassword
        }

        Push-Location $resolvedProjectRoot

        if ($InstallDependencies) {
            $report.dependency_install.attempted = $true
            $installLines = @(& $npmPath install 2>&1)
            $report.dependency_install.output = ($installLines -join "`n")
            $report.dependency_install.success = ($LASTEXITCODE -eq 0)
        }

        if ($BootstrapAuth) {
            $report.auth_bootstrap.attempted = $true
            $authLines = @(& $npmPath run docs:auth 2>&1)
            $report.auth_bootstrap.output = ($authLines -join "`n")
            $report.auth_bootstrap.success = ($LASTEXITCODE -eq 0)
        }

        $report.screenshot_capture.attempted = $true
        $captureLines = @(& $npmPath run docs:marketing 2>&1)
        $report.screenshot_capture.output = ($captureLines -join "`n")
        $report.screenshot_capture.success = ($LASTEXITCODE -eq 0)

        Pop-Location

        $report.success = [bool]$report.screenshot_capture.success
        $report.detail = if ($report.success) {
            "Marketing docs capture completed."
        }
        else {
            "Marketing docs capture failed."
        }
    }
    catch {
        try { Pop-Location } catch {}
        $report.detail = $_.Exception.Message
    }
    finally {
        $env:PLAYWRIGHT_BASE_URL = $previousBaseUrl
        $env:MIM_DOCS_USERNAME = $previousDocsUser
        $env:MIM_DOCS_PASSWORD = $previousDocsPass
    }
}

$outputDir = Split-Path -Parent $resolvedOutputPath
if (-not (Test-Path -Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$json = ($report | ConvertTo-Json -Depth 8)
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