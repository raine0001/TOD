param(
    [string]$LocalPath = '',
    [string]$Query = '',
    [string]$IndexPath = 'runtime/shared/MIM_STATION_FILE_INDEX.latest.json',
    [string]$OutputPath = 'runtime/shared/MIM_STATION_FILE_MIRROR.latest.json',
    [string]$CacheRoot = 'runtime/station_file_mirror/cache',
    [string]$RemoteMirrorRoot = '/home/testpilot/mim/runtime/station_files',
    [string]$RemoteManifestPath = '/home/testpilot/mim/runtime/shared/MIM_STATION_FILE_MIRROR.latest.json',
    [string]$RemoteRequestPath = '/home/testpilot/mim/runtime/shared/MIM_STATION_FILE_FETCH_REQUEST.latest.json',
    [string]$EnvFile = '.env',
    [int64]$MaxBytes = 524288000,
    [switch]$FromRemoteRequest,
    [switch]$UploadToMim
)

$ErrorActionPreference = 'Stop'

function Get-UtcNowText {
    return [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
}

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Write-Utf8NoBomJson {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Path,
        [int]$Depth = 10
    )
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $json = $Object | ConvertTo-Json -Depth $Depth
    [System.IO.File]::WriteAllText($Path, $json, (New-Object System.Text.UTF8Encoding($false)))
}

function Test-UnderRoot {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$Roots
    )
    $full = [System.IO.Path]::GetFullPath($Path)
    foreach ($root in $Roots) {
        if ([string]::IsNullOrWhiteSpace($root) -or -not (Test-Path -LiteralPath $root)) { continue }
        $rootFull = [System.IO.Path]::GetFullPath($root).TrimEnd('\', '/') + '\'
        if (($full + '\').StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase) -or $full.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

function Get-RemoteSafeName {
    param([string]$Name)
    $safe = [regex]::Replace($Name, '[^A-Za-z0-9._-]+', '_')
    if ([string]::IsNullOrWhiteSpace($safe)) { return 'station-file.bin' }
    return $safe
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$indexAbs = if ([System.IO.Path]::IsPathRooted($IndexPath)) { $IndexPath } else { Join-Path $repoRoot $IndexPath }
$outputAbs = if ([System.IO.Path]::IsPathRooted($OutputPath)) { $OutputPath } else { Join-Path $repoRoot $OutputPath }
$cacheAbs = if ([System.IO.Path]::IsPathRooted($CacheRoot)) { $CacheRoot } else { Join-Path $repoRoot $CacheRoot }

$index = Read-JsonFile -Path $indexAbs
if (-not $index) {
    throw "Station file index not found. Run .\scripts\Update-MIMStationFileIndex.ps1 first."
}

if ($FromRemoteRequest -and [string]::IsNullOrWhiteSpace($LocalPath) -and [string]::IsNullOrWhiteSpace($Query)) {
    $connectScript = Join-Path $repoRoot 'scripts\Connect-Mim.ps1'
    if (-not (Test-Path -LiteralPath $connectScript)) { throw "Connect script not found: $connectScript" }
    $remoteOutput = & $connectScript -EnvFile $EnvFile -Command ('cat ' + $RemoteRequestPath + ' 2>/dev/null || true')
    $remoteText = ($remoteOutput | Out-String)
    $jsonStart = $remoteText.IndexOf('{')
    if ($jsonStart -lt 0) { throw "No remote station file fetch request found at $RemoteRequestPath" }
    $request = $remoteText.Substring($jsonStart).Trim() | ConvertFrom-Json
    if ($request.PSObject.Properties['local_path'] -and -not [string]::IsNullOrWhiteSpace([string]$request.local_path)) {
        $LocalPath = [string]$request.local_path
    } elseif ($request.PSObject.Properties['query'] -and -not [string]::IsNullOrWhiteSpace([string]$request.query)) {
        $Query = [string]$request.query
    } else {
        throw "Remote request did not include query or local_path."
    }
}

$roots = New-Object System.Collections.Generic.List[string]
if ($index.requested_access -and $index.requested_access.discovered_mim_roots) {
    foreach ($root in @($index.requested_access.discovered_mim_roots)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$root)) { $roots.Add([string]$root) | Out-Null }
    }
}
if ($index.requested_access -and $index.requested_access.primary_working_path) {
    $roots.Add([string]$index.requested_access.primary_working_path) | Out-Null
}
$allowedRoots = @($roots.ToArray() | Select-Object -Unique)

$selected = $null
$matchSource = ''
if (-not [string]::IsNullOrWhiteSpace($LocalPath)) {
    $selected = [System.IO.Path]::GetFullPath($LocalPath)
    $matchSource = 'explicit_local_path'
} elseif (-not [string]::IsNullOrWhiteSpace($Query)) {
    $queryText = $Query.Trim()
    $candidateLists = @()
    if ($index.primary_working_context -and $index.primary_working_context.arm_component_candidates) {
        $candidateLists += @($index.primary_working_context.arm_component_candidates)
    }
    if ($index.primary_working_context -and $index.primary_working_context.recent_files) {
        $candidateLists += @($index.primary_working_context.recent_files)
    }
    if ($index.recent_files) {
        $candidateLists += @($index.recent_files)
    }
    $matches = @($candidateLists | Where-Object {
        $_ -and $_.path -and (
            [string]$_.name -like "*$queryText*" -or
            [string]$_.relative_path -like "*$queryText*" -or
            [string]$_.path -like "*$queryText*"
        )
    } | Select-Object -First 10)
    if (@($matches).Count -lt 1) {
        throw "No indexed file matched query: $Query"
    }
    $selected = [string]$matches[0].path
    $matchSource = 'station_index_query'
} else {
    throw "Provide -LocalPath or -Query."
}

if (-not (Test-Path -LiteralPath $selected -PathType Leaf)) {
    throw "Selected station file not found: $selected"
}
if (-not (Test-UnderRoot -Path $selected -Roots $allowedRoots)) {
    throw "Refusing to mirror outside approved MIM station roots: $selected"
}

$item = Get-Item -LiteralPath $selected
if ($item.Length -gt $MaxBytes) {
    throw "Refusing to mirror file larger than MaxBytes=${MaxBytes}: $selected ($($item.Length) bytes)"
}

$hash = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
$hashPrefix = $hash.Substring(0, 16)
$safeName = Get-RemoteSafeName -Name $item.Name
$cacheDir = Join-Path $cacheAbs $hashPrefix
if (-not (Test-Path -LiteralPath $cacheDir)) {
    New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
}
$cacheFile = Join-Path $cacheDir $safeName
Copy-Item -LiteralPath $item.FullName -Destination $cacheFile -Force

$relativeCachePath = $cacheFile
if ($cacheFile.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    $relativeCachePath = $cacheFile.Substring($repoRoot.Length).TrimStart('\', '/')
}
$remotePath = ('{0}/{1}/{2}' -f $RemoteMirrorRoot.TrimEnd('/'), $hashPrefix, $safeName)

$uploadResult = $null
if ($UploadToMim) {
    $sendScript = Join-Path $repoRoot 'scripts\Send-TODMimScript.ps1'
    $uploadResult = & $sendScript -EnvFile $EnvFile -LocalPath $relativeCachePath -RemotePath $remotePath | ConvertFrom-Json
}

$manifest = [ordered]@{
    packet_type = 'mim-station-file-mirror-v1'
    generated_at = Get-UtcNowText
    status = if ($UploadToMim) { 'completed_with_evidence' } else { 'prepared_local_cache' }
    success = $true
    request = @{
        local_path = $LocalPath
        query = $Query
        match_source = $matchSource
    }
    source = @{
        path = $item.FullName
        name = $item.Name
        extension = $item.Extension
        size_bytes = [int64]$item.Length
        last_write_time_utc = $item.LastWriteTimeUtc.ToString('yyyy-MM-ddTHH:mm:ssZ')
        sha256 = $hash
    }
    local_cache = @{
        path = $cacheFile
        relative_path = $relativeCachePath
        sha256 = (Get-FileHash -LiteralPath $cacheFile -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    remote = @{
        uploaded = [bool]$UploadToMim
        path = if ($UploadToMim) { $remotePath } else { '' }
        manifest_path = if ($UploadToMim) { $RemoteManifestPath } else { '' }
        upload_result = $uploadResult
    }
    allowed_roots = $allowedRoots
    policy = 'Station files are mirrored only after TOD validates the requested path against approved MIM roots.'
    next_recovery_action = ''
}

Write-Utf8NoBomJson -Object $manifest -Path $outputAbs -Depth 12

if ($UploadToMim) {
    $sendScript = Join-Path $repoRoot 'scripts\Send-TODMimScript.ps1'
    $manifestUploadPath = $outputAbs
    if ($manifestUploadPath.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        $manifestUploadPath = $manifestUploadPath.Substring($repoRoot.Length).TrimStart('\', '/')
    }
    & $sendScript -EnvFile $EnvFile -LocalPath $manifestUploadPath -RemotePath $RemoteManifestPath | Out-Null
}

$manifest | ConvertTo-Json -Depth 12
