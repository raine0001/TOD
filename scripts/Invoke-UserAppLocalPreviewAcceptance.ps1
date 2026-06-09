param(
    [Parameter(Mandatory = $true)]
    [string]$RuntimeAcceptancePath,

    [Parameter(Mandatory = $true)]
    [string]$BaseUrl,

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

$acceptanceAbs = Resolve-WorkspacePath -Path $RuntimeAcceptancePath
$acceptance = Get-Content -Path $acceptanceAbs -Raw | ConvertFrom-Json
$checkedAt = (Get-Date).ToUniversalTime().ToString("o")
$base = $BaseUrl.TrimEnd("/")

$checks = @()
foreach ($route in $Routes) {
    $path = if ($route.StartsWith("/")) { $route } else { "/" + $route }
    $url = $base + $path
    try {
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 20
        $content = [string]$response.Content
        $checks += [pscustomobject]@{
            route = $path
            url = $url
            status_code = [int]$response.StatusCode
            passed = ([int]$response.StatusCode -ge 200 -and [int]$response.StatusCode -lt 400)
            content_markers = @{
                has_html = $content.Contains("<html")
                has_next_data = $content.Contains("__next")
                has_app_text = ($content.Contains([string]$acceptance.app_name) -or $content.Contains("MIM Help") -or $content.Contains("Dashboard"))
            }
        }
    }
    catch {
        $checks += [pscustomobject]@{
            route = $path
            url = $url
            status_code = 0
            passed = $false
            error = $_.Exception.Message
        }
    }
}

$allPassed = @($checks | Where-Object { -not $_.passed }).Count -eq 0
$acceptance.gates.local_preview = if ($allPassed) { "route_probe_passed" } else { "route_probe_failed" }
$acceptance | Add-Member -NotePropertyName local_preview_acceptance -NotePropertyValue ([ordered]@{
        checked_at = $checkedAt
        base_url = $base
        method = "http_route_probe"
        browser_visual_check = "not_available_iab"
        routes = $checks
        passed = $allPassed
    }) -Force
$acceptance.status = if ($allPassed -and [string]$acceptance.gates.local_build -eq "passed") { "local_preview_route_probe_passed" } else { [string]$acceptance.status }
$acceptance.tod_next_action = if ($allPassed) {
    "Run browser visual acceptance when Browser/iab is available, then select a real preview deploy target."
}
else {
    "Inspect failed preview routes, repair the generated app route, and rerun local preview acceptance."
}

Set-Content -Path $acceptanceAbs -Value ($acceptance | ConvertTo-Json -Depth 20) -Encoding UTF8

if (-not $allPassed) {
    Write-Error ("Local preview acceptance failed for {0}. Evidence: {1}" -f $acceptance.slug, (ConvertTo-WorkspaceRelativePath -Path $acceptanceAbs))
}

[pscustomobject]@{
    status = $acceptance.status
    slug = $acceptance.slug
    local_preview = $acceptance.gates.local_preview
    route_count = @($checks).Count
    output_path = ConvertTo-WorkspaceRelativePath -Path $acceptanceAbs
}
