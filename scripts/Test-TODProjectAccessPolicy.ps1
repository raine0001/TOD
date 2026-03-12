param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectId,
    [Parameter(Mandatory = $true)]
    [string[]]$RelativePaths,
    [string]$RegistryPath = "tod/config/project-registry.json",
    [ValidateSet("read", "write", "delete", "rename")]
    [string]$Operation = "write"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

function Resolve-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) { return $PathValue }
    return (Join-Path $repoRoot $PathValue)
}

function Normalize-Path {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    $p = ($PathValue -replace "[\\/]+", "/").Trim()
    return $p.TrimStart("/")
}

function Test-PathPrefixMatch {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)][string]$Prefix
    )

    $pathNorm = (Normalize-Path -PathValue $PathValue).ToLowerInvariant()
    $prefixNorm = (Normalize-Path -PathValue $Prefix).ToLowerInvariant()

    if ([string]::IsNullOrWhiteSpace($prefixNorm)) { return $false }
    return ($pathNorm -eq $prefixNorm -or $pathNorm.StartsWith($prefixNorm + "/"))
}

$resolvedRegistryPath = Resolve-LocalPath -PathValue $RegistryPath
if (-not (Test-Path -Path $resolvedRegistryPath)) {
    throw "Registry file not found: $resolvedRegistryPath"
}

$registry = (Get-Content -Path $resolvedRegistryPath -Raw | ConvertFrom-Json)
$projects = if ($registry.PSObject.Properties["projects"]) { @($registry.projects) } else { @() }
$project = @($projects | Where-Object { [string]$_.id -eq $ProjectId }) | Select-Object -First 1

if ($null -eq $project) {
    throw "Project not found in registry: $ProjectId"
}

$boundaries = if ($project.PSObject.Properties["boundaries"]) { $project.boundaries } else { $null }
$allowed = if ($boundaries -and $boundaries.PSObject.Properties["allowed_paths"]) { @($boundaries.allowed_paths) } else { @() }
$blocked = if ($boundaries -and $boundaries.PSObject.Properties["blocked_paths"]) { @($boundaries.blocked_paths) } else { @() }

$checks = @()
$allAllowed = $true

foreach ($path in $RelativePaths) {
    $normalizedPath = Normalize-Path -PathValue $path

    $matchedAllowed = $false
    if (@($allowed).Count -eq 0) {
        $matchedAllowed = $true
    }
    else {
        foreach ($allowPrefix in $allowed) {
            if (Test-PathPrefixMatch -PathValue $normalizedPath -Prefix ([string]$allowPrefix)) {
                $matchedAllowed = $true
                break
            }
        }
    }

    $matchedBlocked = $false
    foreach ($blockedPrefix in $blocked) {
        if (Test-PathPrefixMatch -PathValue $normalizedPath -Prefix ([string]$blockedPrefix)) {
            $matchedBlocked = $true
            break
        }
    }

    $pathAllowed = $matchedAllowed -and (-not $matchedBlocked)
    if (-not $pathAllowed) { $allAllowed = $false }

    $checks += [pscustomobject]@{
        relative_path = $normalizedPath
        in_allowed_scope = $matchedAllowed
        in_blocked_scope = $matchedBlocked
        allowed = $pathAllowed
    }
}

$result = [pscustomobject]@{
    ok = $allAllowed
    project_id = [string]$project.id
    project_name = [string]$project.name
    operation = $Operation
    write_access = [string]$project.write_access
    risk_level = [string]$project.risk_level
    checks = @($checks)
    policy_notes = if ($boundaries -and $boundaries.PSObject.Properties["notes"]) { [string]$boundaries.notes } else { "" }
}

$result | ConvertTo-Json -Depth 12 | Write-Output

if (-not $allAllowed) {
    exit 2
}
