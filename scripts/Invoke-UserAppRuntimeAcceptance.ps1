param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,

    [string]$OutputRoot = "runtime/shared/user_app_runtime_acceptance",

    [switch]$SkipInstall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$workspaceRoot = Split-Path -Parent $PSScriptRoot

function Resolve-WorkspacePath {
    param([Parameter(Mandatory = $true)][string]$Path)
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return (Resolve-Path -Path $Path).Path
    }
    return (Resolve-Path -Path (Join-Path $workspaceRoot ($Path -replace '/', [System.IO.Path]::DirectorySeparatorChar))).Path
}

function ConvertTo-WorkspaceRelativePath {
    param([Parameter(Mandatory = $true)][string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    $root = [System.IO.Path]::GetFullPath($workspaceRoot).TrimEnd('\') + '\'
    if ($full.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
        return (($full.Substring($root.Length)) -replace '\\', '/')
    }
    return $full
}

function Invoke-CapturedCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $output = & $FilePath @Arguments 2>&1 | Out-String
    $ErrorActionPreference = $previousErrorActionPreference
    $exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
    return [pscustomobject]@{
        name = $Name
        exit_code = $exitCode
        output = $output.Trim()
    }
}

$repoAbs = Resolve-WorkspacePath -Path $RepoRoot
$manifestPath = Join-Path $repoAbs "repo.manifest.json"
if (-not (Test-Path -Path $manifestPath -PathType Leaf)) {
    throw "Repo manifest not found: $manifestPath"
}

$manifest = Get-Content -Path $manifestPath -Raw | ConvertFrom-Json
$slug = [string]$manifest.slug
if ([string]::IsNullOrWhiteSpace($slug)) {
    $slug = Split-Path -Leaf $repoAbs
}
$appName = [string]$manifest.app_name
if ([string]::IsNullOrWhiteSpace($appName)) {
    $appName = ($slug -replace '_', ' ')
}

$startedAt = (Get-Date).ToUniversalTime().ToString("o")
$commands = @()

if (-not $SkipInstall) {
    $commands += Invoke-CapturedCommand -Name "npm install" -FilePath "npm.cmd" -Arguments @("install", "--silent", "--no-audit", "--no-fund", "--prefix", $repoAbs)
}

$installPassed = $true
if ($commands.Count -gt 0) {
    $installPassed = ([int]$commands[-1].exit_code -eq 0)
}

if ($installPassed) {
    $commands += Invoke-CapturedCommand -Name "npm run build" -FilePath "npm.cmd" -Arguments @("run", "build", "--prefix", $repoAbs)
}

$buildCommand = @($commands | Where-Object { $_.name -eq "npm run build" } | Select-Object -Last 1)
$buildPassed = ($buildCommand.Count -gt 0 -and [int]$buildCommand[0].exit_code -eq 0)
$completedAt = (Get-Date).ToUniversalTime().ToString("o")

$outputDir = if ([System.IO.Path]::IsPathRooted($OutputRoot)) {
    Join-Path $OutputRoot $slug
}
else {
    Join-Path $workspaceRoot (($OutputRoot + "/" + $slug) -replace '/', [System.IO.Path]::DirectorySeparatorChar)
}
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
$outputPath = Join-Path $outputDir "runtime.acceptance.json"

$status = if ($buildPassed) { "runtime_build_passed" } else { "runtime_build_failed" }
$result = [ordered]@{
    artifact_type = "user_app_runtime_acceptance_result_v1"
    generated_at = $completedAt
    app_name = $appName
    slug = $slug
    repo_root = ConvertTo-WorkspaceRelativePath -Path $repoAbs
    started_at = $startedAt
    completed_at = $completedAt
    commands = $commands
    gates = [ordered]@{
        dependency_install = if ($SkipInstall) { "skipped" } elseif ($installPassed) { "passed" } else { "failed" }
        local_build = if ($buildPassed) { "passed" } else { "failed" }
        local_preview = "not_run"
        production_deploy = "not_selected"
    }
    status = $status
    dave_needed = "no"
    tod_next_action = if ($buildPassed) {
        "Start local preview server and run browser acceptance against routes."
    }
    else {
        "Inspect the failed command output, make the smallest bounded repo fix, and rerun runtime acceptance."
    }
}

$json = $result | ConvertTo-Json -Depth 20
Set-Content -Path $outputPath -Value $json -Encoding UTF8

if (-not $buildPassed) {
    Write-Error ("Runtime acceptance failed for {0}. Evidence: {1}" -f $slug, (ConvertTo-WorkspaceRelativePath -Path $outputPath))
}

[pscustomobject]@{
    status = $status
    app_name = $appName
    slug = $slug
    output_path = ConvertTo-WorkspaceRelativePath -Path $outputPath
}
