param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,

    [string]$PublishedRoot = "runtime/shared/user_app_static_published",

    [string[]]$Routes = @("/", "/login", "/dashboard", "/settings", "/help")
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
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory
    )
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $output = & $FilePath @Arguments 2>&1 | Out-String
    $ErrorActionPreference = $previousErrorActionPreference
    $exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
    return [pscustomobject]@{
        name = $Name
        exit_code = $exitCode
        working_directory = ConvertTo-WorkspaceRelativePath -Path $WorkingDirectory
        output = $output.Trim()
    }
}

$repoAbs = Resolve-WorkspacePath -Path $RepoRoot
$repoManifestPath = Join-Path $repoAbs "repo.manifest.json"
if (-not (Test-Path -Path $repoManifestPath -PathType Leaf)) {
    throw "Repo manifest not found: $repoManifestPath"
}
$repoManifest = Get-Content -Path $repoManifestPath -Raw | ConvertFrom-Json
$slug = [string]$repoManifest.slug
$appName = [string]$repoManifest.app_name

$runtimeAcceptancePath = Join-Path $workspaceRoot ("runtime/shared/user_app_runtime_acceptance/$slug/runtime.acceptance.json" -replace '/', [System.IO.Path]::DirectorySeparatorChar)
if (-not (Test-Path -Path $runtimeAcceptancePath -PathType Leaf)) {
    throw "Runtime acceptance result not found: $runtimeAcceptancePath"
}

$startedAt = (Get-Date).ToUniversalTime().ToString("o")
$commands = @()
$commands += Invoke-CapturedCommand -Name "npm run build static export" -FilePath "npm.cmd" -Arguments @("run", "build", "--prefix", $repoAbs) -WorkingDirectory $repoAbs
$buildPassed = ([int]$commands[-1].exit_code -eq 0)

$outDir = Join-Path $repoAbs "out"
$routeChecks = @()
if ($buildPassed -and (Test-Path -Path $outDir -PathType Container)) {
    foreach ($route in $Routes) {
        $relative = if ($route -eq "/") { "index.html" } else { ($route.Trim("/") + "/index.html") }
        $filePath = Join-Path $outDir ($relative -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $content = if (Test-Path -Path $filePath -PathType Leaf) { Get-Content -Path $filePath -Raw } else { "" }
        $routeChecks += [pscustomobject]@{
            route = $route
            file = ConvertTo-WorkspaceRelativePath -Path $filePath
            exists = (Test-Path -Path $filePath -PathType Leaf)
            has_html = $content.Contains("<html")
            has_app_marker = ($content.Contains($appName) -or $content.Contains("Dashboard") -or $content.Contains("MIM Help") -or $content.Contains("User Settings"))
            passed = ((Test-Path -Path $filePath -PathType Leaf) -and $content.Contains("<html") -and ($content.Contains($appName) -or $content.Contains("Dashboard") -or $content.Contains("MIM Help") -or $content.Contains("User Settings")))
        }
    }
}
else {
    foreach ($route in $Routes) {
        $routeChecks += [pscustomobject]@{
            route = $route
            exists = $false
            has_html = $false
            has_app_marker = $false
            passed = $false
        }
    }
}

$allRoutesPassed = @($routeChecks | Where-Object { -not $_.passed }).Count -eq 0
$publishedAbs = Join-Path $workspaceRoot (($PublishedRoot + "/" + $slug) -replace '/', [System.IO.Path]::DirectorySeparatorChar)
if (Test-Path -Path $publishedAbs) {
    Remove-Item -Path $publishedAbs -Recurse -Force
}
if ($allRoutesPassed) {
    New-Item -ItemType Directory -Path $publishedAbs -Force | Out-Null
    Copy-Item -Path (Join-Path $outDir "*") -Destination $publishedAbs -Recurse -Force
}

$completedAt = (Get-Date).ToUniversalTime().ToString("o")
$manifestPath = Join-Path $publishedAbs "static-publish.manifest.json"
$publishManifest = [ordered]@{
    artifact_type = "user_app_static_publish_acceptance_v1"
    generated_at = $completedAt
    app_name = $appName
    slug = $slug
    repo_root = ConvertTo-WorkspaceRelativePath -Path $repoAbs
    published_root = ConvertTo-WorkspaceRelativePath -Path $publishedAbs
    started_at = $startedAt
    completed_at = $completedAt
    commands = $commands
    routes = $routeChecks
    gates = [ordered]@{
        local_static_export = if ($allRoutesPassed) { "passed" } else { "failed" }
        hosted_preview = "not_selected"
        production_deploy = "not_selected"
    }
    status = if ($allRoutesPassed) { "static_publish_passed" } else { "static_publish_failed" }
    dave_needed = "no"
    tod_next_action = if ($allRoutesPassed) {
        "Select hosted preview target and run hosted acceptance before production packaging."
    }
    else {
        "Inspect static export failure, repair the route/build issue, and rerun static publish acceptance."
    }
}
if ($allRoutesPassed) {
    Set-Content -Path $manifestPath -Value ($publishManifest | ConvertTo-Json -Depth 30) -Encoding UTF8
}

$runtimeAcceptance = Get-Content -Path $runtimeAcceptancePath -Raw | ConvertFrom-Json
$runtimeAcceptance | Add-Member -NotePropertyName static_publish_acceptance -NotePropertyValue $publishManifest -Force
$runtimeAcceptance.gates | Add-Member -NotePropertyName static_publish -NotePropertyValue $publishManifest.gates.local_static_export -Force
if ($allRoutesPassed) {
    $runtimeAcceptance.status = "static_publish_passed"
    $runtimeAcceptance.tod_next_action = "Select hosted preview target and run hosted acceptance before production packaging."
}
else {
    $runtimeAcceptance.status = "static_publish_failed"
    $runtimeAcceptance.tod_next_action = "Repair static publish failure and rerun static publish acceptance."
}
Set-Content -Path $runtimeAcceptancePath -Value ($runtimeAcceptance | ConvertTo-Json -Depth 40) -Encoding UTF8

if (-not $allRoutesPassed) {
    Write-Error ("Static publish acceptance failed for {0}. Evidence: {1}" -f $slug, (ConvertTo-WorkspaceRelativePath -Path $runtimeAcceptancePath))
}

[pscustomobject]@{
    status = $publishManifest.status
    app_name = $appName
    slug = $slug
    route_count = @($routeChecks).Count
    published_root = ConvertTo-WorkspaceRelativePath -Path $publishedAbs
    manifest = if ($allRoutesPassed) { ConvertTo-WorkspaceRelativePath -Path $manifestPath } else { "" }
}
