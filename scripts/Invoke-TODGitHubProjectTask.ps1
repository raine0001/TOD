param(
    [Parameter(Mandatory = $true)][string]$ProjectId,
    [Parameter(Mandatory = $true)][string]$Task,
    [ValidateSet("review", "debug", "fixes", "plan", "operator")]
    [string]$Mode = "plan",
    [string[]]$TargetHints = @(),
    [string]$ProjectIndexPath = "tod/data/project-library-index.json",
    [string]$RegistryPath = "tod/config/project-registry.json",
    [string]$OutputRoot = "shared_state/conversation_eval/github_project_tasks",
    [int]$MaxCandidateFiles = 3,
    [switch]$UseAssist,
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
function ConvertTo-RepoPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    return (($PathValue -replace "[\\/]+", "/").Trim()).TrimStart("/")
}
function Test-PathPrefixMatch {
    param([Parameter(Mandatory = $true)][string]$PathValue,[Parameter(Mandatory = $true)][string]$Prefix)
    $pathNorm = (ConvertTo-RepoPath -PathValue $PathValue).ToLowerInvariant()
    $prefixNorm = (ConvertTo-RepoPath -PathValue $Prefix).ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($prefixNorm)) { return $false }
    return ($pathNorm -eq $prefixNorm -or $pathNorm.StartsWith($prefixNorm + "/"))
}
function Get-GitInfo {
    param([Parameter(Mandatory = $true)][string]$ProjectPath)
    $branch = ""
    $remote = ""
    $status = ""
    $inside = $false
    try {
        $inside = ((& git -C $ProjectPath rev-parse --is-inside-work-tree 2>$null) -eq "true")
        if ($inside) {
            $branch = [string](& git -C $ProjectPath rev-parse --abbrev-ref HEAD 2>$null)
            $remote = [string](& git -C $ProjectPath remote get-url origin 2>$null)
            $status = [string](& git -C $ProjectPath status -sb 2>$null | Out-String).Trim()
        }
    } catch {}
    [pscustomobject]@{ is_repo = $inside; branch = $branch; remote_origin = $remote; status = $status; can_publish = (-not [string]::IsNullOrWhiteSpace($remote)) }
}
function Find-CandidateFiles {
    param([Parameter(Mandatory = $true)]$Project,[string[]]$Hints,[int]$MaxFiles = 3)
    $projectRoot = [string]$Project.path
    $allowedPaths = if ($Project.boundaries -and $Project.boundaries.allowed_paths) { @($Project.boundaries.allowed_paths) } else { @() }
    $exts = @("*.ps1","*.py","*.js","*.ts","*.tsx","*.jsx","*.html","*.css","*.md")
    $hits = New-Object System.Collections.ArrayList
    foreach ($allowed in $allowedPaths) {
        $base = Join-Path $projectRoot ([string]$allowed)
        if (-not (Test-Path $base)) { continue }
        foreach ($ext in $exts) {
            foreach ($file in Get-ChildItem -Path $base -Recurse -File -Filter $ext -ErrorAction SilentlyContinue) {
                $name = $file.FullName.ToLowerInvariant()
                foreach ($hint in $Hints) {
                    if ($name -like ("*" + ([string]$hint).ToLowerInvariant() + "*")) { [void]$hits.Add($file.FullName); break }
                }
            }
        }
    }
    if ($hits.Count -eq 0) {
        foreach ($allowed in $allowedPaths) {
            $base = Join-Path $projectRoot ([string]$allowed)
            if (-not (Test-Path $base)) { continue }
            foreach ($file in (Get-ChildItem -Path $base -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First $MaxFiles)) { [void]$hits.Add($file.FullName) }
            if ($hits.Count -ge $MaxFiles) { break }
        }
    }
    @($hits | Select-Object -Unique | Select-Object -First $MaxFiles)
}

$resolvedProjectIndexPath = Resolve-LocalPath -PathValue $ProjectIndexPath
$resolvedRegistryPath = Resolve-LocalPath -PathValue $RegistryPath
$outputRootAbs = Resolve-LocalPath -PathValue $OutputRoot
if (-not (Test-Path $outputRootAbs)) { New-Item -ItemType Directory -Path $outputRootAbs -Force | Out-Null }
$index = Get-Content -Path $resolvedProjectIndexPath -Raw | ConvertFrom-Json
$project = @($index.projects | Where-Object { [string]$_.id -eq $ProjectId } | Select-Object -First 1)
if ($null -eq $project) {
    $registry = Get-Content -Path $resolvedRegistryPath -Raw | ConvertFrom-Json
    $project = @($registry.projects | Where-Object { [string]$_.id -eq $ProjectId } | Select-Object -First 1)
}
if ($null -eq $project) { throw "Project not found: $ProjectId" }

$hints = if (@($TargetHints).Count -gt 0) { $TargetHints } else { @("home","index","footer","main","app","route") }
$candidateFiles = @(Find-CandidateFiles -Project $project -Hints $hints -MaxFiles $MaxCandidateFiles)
$git = Get-GitInfo -ProjectPath ([string]$project.path)
$assist = $null
if ($UseAssist) {
    $assistScript = Join-Path $PSScriptRoot "Invoke-TODRealCodeAssist.ps1"
    $providerScript = Join-Path $PSScriptRoot "Invoke-TODConversationProvider.ps1"
    if ((Test-Path $assistScript) -and (Test-Path $providerScript) -and @($candidateFiles).Count -gt 0) {
        try {
            $status = & $providerScript -Action status -AsJson | ConvertFrom-Json
            if ([bool]$status.reachable) {
                $assist = & $assistScript -Mode $Mode -FilePaths $candidateFiles -MaxFiles $MaxCandidateFiles -EmitJson | ConvertFrom-Json
            }
        } catch {}
    }
}
$auth = [pscustomobject]@{ authenticated = $false; account = "" }
try {
    $authText = (& gh auth status 2>&1 | Out-String)
    $auth.authenticated = ($authText -match "Logged in to github.com account")
    if ($authText -match "Logged in to github.com account\s+([^\s]+)") { $auth.account = $Matches[1] }
} catch {}

$runId = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
$outputPath = Join-Path $outputRootAbs ("tod_github_project_task.{0}.json" -f $runId)
$report = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = "tod-github-project-task-v1"
    run_id = $runId
    project_id = [string]$project.id
    project_name = [string]$project.name
    task = $Task
    mode = $Mode
    candidate_files = @($candidateFiles)
    git = $git
    github = $auth
    assist = $assist
    live_readiness = [pscustomobject]@{
        simulation_only = $true
        discovery_passed = (@($candidateFiles).Count -gt 0)
        can_publish = [bool]($git.can_publish -and $auth.authenticated)
        suggested_branch = if (-not [string]::IsNullOrWhiteSpace($git.branch)) { $git.branch } else { "main" }
        suggested_commit_message = "task($ProjectId): prepare task package"
    }
}
$report | ConvertTo-Json -Depth 20 | Set-Content -Path $outputPath
if ($EmitJson) { $report | ConvertTo-Json -Depth 12 | Write-Output } else { $report }
