param(
    [string]$LocalPath = '',
    [string]$Query = '',
    [string]$IndexPath = 'runtime/shared/MIM_STATION_FILE_INDEX.latest.json',
    [string]$OutputPath = 'runtime/shared/MIM_STATION_FILE_MIRROR.latest.json',
    [string]$MirrorIndexPath = 'runtime/shared/MIM_STATION_FILE_MIRROR_INDEX.latest.json',
    [string]$CacheRoot = 'runtime/station_file_mirror/cache',
    [string]$RemoteMirrorRoot = '/home/testpilot/mim/runtime/station_files',
    [string]$RemoteManifestPath = '/home/testpilot/mim/runtime/shared/MIM_STATION_FILE_MIRROR.latest.json',
    [string]$RemoteMirrorIndexPath = '/home/testpilot/mim/runtime/shared/MIM_STATION_FILE_MIRROR_INDEX.latest.json',
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

function Convert-FromUtf8Mojibake {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $Text }
    try {
        $bytes = [System.Text.Encoding]::GetEncoding(1252).GetBytes($Text)
        return [System.Text.Encoding]::UTF8.GetString($bytes)
    } catch {
        return $Text
    }
}

function Get-IndexRecordCandidates {
    param($Index)
    $candidateLists = @()
    if ($Index.primary_working_context -and $Index.primary_working_context.arm_component_candidates) {
        $candidateLists += @($Index.primary_working_context.arm_component_candidates)
    }
    if ($Index.primary_working_context -and $Index.primary_working_context.recent_files) {
        $candidateLists += @($Index.primary_working_context.recent_files)
    }
    if ($Index.recent_files) {
        $candidateLists += @($Index.recent_files)
    }
    if ($Index.files) {
        $candidateLists += @($Index.files)
    }
    if ($Index.documents) {
        $candidateLists += @($Index.documents)
    }
    return @($candidateLists)
}

function Find-IndexRecordForPath {
    param(
        $Index,
        [string]$Path
    )
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    $pathText = [string]$Path
    $pathFull = ''
    try { $pathFull = [System.IO.Path]::GetFullPath($pathText) } catch { $pathFull = $pathText }
    $pathLeaf = Split-Path -Path $pathText -Leaf
    $matches = @(Get-IndexRecordCandidates -Index $Index | Where-Object {
        $recordPath = [string]$_.path
        $recordFull = ''
        if (-not [string]::IsNullOrWhiteSpace($recordPath)) {
            try { $recordFull = [System.IO.Path]::GetFullPath($recordPath) } catch { $recordFull = $recordPath }
        }
        $_ -and (
            (-not [string]::IsNullOrWhiteSpace($recordPath) -and $recordPath -eq $pathText) -or
            (-not [string]::IsNullOrWhiteSpace($recordFull) -and $recordFull -eq $pathFull) -or
            ([string]$_.relative_path -and [string]$_.relative_path -eq $pathText) -or
            ([string]$_.name -and [string]$_.name -eq $pathLeaf)
        )
    } | Select-Object -First 1)
    if ($matches.Count -gt 0) { return $matches[0] }
    return $null
}

function Resolve-IndexedSourcePath {
    param(
        [Parameter(Mandatory = $true)][string]$Selected,
        $IndexRecord,
        [Parameter(Mandatory = $true)][string[]]$AllowedRoots
    )

    $script:LastIndexedSourceResolution = [ordered]@{
        selected = $Selected
        index_record_present = [bool]$IndexRecord
        relative_parent = ''
        search_roots = @()
        candidate_count = 0
        resolved_path = ''
    }

    if (Test-Path -LiteralPath $Selected -PathType Leaf) {
        $script:LastIndexedSourceResolution.resolved_path = [System.IO.Path]::GetFullPath($Selected)
        return [System.IO.Path]::GetFullPath($Selected)
    }
    $mojibakeResolved = Convert-FromUtf8Mojibake -Text $Selected
    if ($mojibakeResolved -ne $Selected -and (Test-Path -LiteralPath $mojibakeResolved -PathType Leaf)) {
        $script:LastIndexedSourceResolution.resolved_path = [System.IO.Path]::GetFullPath($mojibakeResolved)
        return [System.IO.Path]::GetFullPath($mojibakeResolved)
    }
    if (-not $IndexRecord) {
        return $Selected
    }

    $expectedExtension = [string]$IndexRecord.extension
    if ([string]::IsNullOrWhiteSpace($expectedExtension)) {
        $expectedExtension = [System.IO.Path]::GetExtension($Selected)
    }
    $expectedSize = $null
    if ($IndexRecord.PSObject.Properties['size_bytes']) {
        try { $expectedSize = [int64]$IndexRecord.size_bytes } catch { $expectedSize = $null }
    }
    $relativePath = [string]$IndexRecord.relative_path
    $relativeParent = if (-not [string]::IsNullOrWhiteSpace($relativePath)) { Split-Path -Path $relativePath -Parent } else { '' }
    $script:LastIndexedSourceResolution.relative_parent = $relativeParent
    $selectedLeaf = Split-Path -Path $Selected -Leaf

    $searchRoots = New-Object System.Collections.Generic.List[string]
    foreach ($root in $AllowedRoots) {
        if ([string]::IsNullOrWhiteSpace($root) -or -not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        if (-not [string]::IsNullOrWhiteSpace($relativeParent)) {
            $parentPath = Join-Path $root $relativeParent
            if (Test-Path -LiteralPath $parentPath -PathType Container) {
                $searchRoots.Add($parentPath) | Out-Null
                continue
            }
        }
        $searchRoots.Add($root) | Out-Null
    }
    $script:LastIndexedSourceResolution.search_roots = @($searchRoots.ToArray() | Select-Object -Unique)

    $candidates = New-Object System.Collections.Generic.List[object]
    foreach ($searchRoot in @($searchRoots.ToArray() | Select-Object -Unique)) {
        $items = @()
        if ($searchRoot -and (Test-Path -LiteralPath $searchRoot -PathType Container)) {
            $items = @(Get-ChildItem -LiteralPath $searchRoot -File -Recurse -ErrorAction SilentlyContinue)
        }
        foreach ($item in $items) {
            if (-not [string]::IsNullOrWhiteSpace($expectedExtension) -and $item.Extension -ne $expectedExtension) { continue }
            if ($expectedSize -ne $null -and [int64]$item.Length -ne $expectedSize) { continue }
            $score = 0
            if ($item.Name -eq $selectedLeaf) { $score += 100 }
            if (-not [string]::IsNullOrWhiteSpace($relativeParent) -and $item.FullName -like ("*" + $relativeParent + "*")) { $score += 25 }
            $candidates.Add([pscustomobject]@{ Path = $item.FullName; Score = $score }) | Out-Null
        }
    }
    $script:LastIndexedSourceResolution.candidate_count = $candidates.Count

    $resolved = @($candidates | Sort-Object Score, Path -Descending | Select-Object -First 2)
    if ($resolved.Count -eq 1) {
        $script:LastIndexedSourceResolution.resolved_path = [string]$resolved[0].Path
        return [string]$resolved[0].Path
    }
    if ($resolved.Count -gt 1 -and $resolved[0].Score -gt $resolved[1].Score) {
        $script:LastIndexedSourceResolution.resolved_path = [string]$resolved[0].Path
        return [string]$resolved[0].Path
    }
    return $Selected
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$indexAbs = if ([System.IO.Path]::IsPathRooted($IndexPath)) { $IndexPath } else { Join-Path $repoRoot $IndexPath }
$outputAbs = if ([System.IO.Path]::IsPathRooted($OutputPath)) { $OutputPath } else { Join-Path $repoRoot $OutputPath }
$mirrorIndexAbs = if ([System.IO.Path]::IsPathRooted($MirrorIndexPath)) { $MirrorIndexPath } else { Join-Path $repoRoot $MirrorIndexPath }
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
    if ($request.PSObject.Properties['source_artifact'] -and -not [string]::IsNullOrWhiteSpace([string]$request.source_artifact)) {
        $requestedIndex = Join-Path 'runtime/shared' ([string]$request.source_artifact)
        $requestedIndexAbs = if ([System.IO.Path]::IsPathRooted($requestedIndex)) { $requestedIndex } else { Join-Path $repoRoot $requestedIndex }
        if (Test-Path -LiteralPath $requestedIndexAbs -PathType Leaf) {
            $IndexPath = $requestedIndex
            $indexAbs = $requestedIndexAbs
            $index = Read-JsonFile -Path $indexAbs
        }
    }
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
$selectedRecord = $null
$matchSource = ''
if (-not [string]::IsNullOrWhiteSpace($LocalPath)) {
    $selected = [System.IO.Path]::GetFullPath($LocalPath)
    $selectedRecord = Find-IndexRecordForPath -Index $index -Path $LocalPath
    if (-not $selectedRecord) {
        $selectedRecord = Find-IndexRecordForPath -Index $index -Path $selected
    }
    $matchSource = 'explicit_local_path'
} elseif (-not [string]::IsNullOrWhiteSpace($Query)) {
    $queryText = $Query.Trim()
    $candidateLists = Get-IndexRecordCandidates -Index $index
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
    $selectedRecord = $matches[0]
    $selected = [string]$matches[0].path
    $matchSource = 'station_index_query'
} else {
    throw "Provide -LocalPath or -Query."
}

$resolvedSelected = Resolve-IndexedSourcePath -Selected $selected -IndexRecord $selectedRecord -AllowedRoots $allowedRoots
if ($resolvedSelected -ne $selected) {
    $selected = $resolvedSelected
    $matchSource = "$matchSource+resolved_from_index_metadata"
}

if (-not (Test-Path -LiteralPath $selected -PathType Leaf)) {
    $resolutionText = if ($script:LastIndexedSourceResolution) { ($script:LastIndexedSourceResolution | ConvertTo-Json -Depth 5 -Compress) } else { '{}' }
    throw "Selected station file not found: $selected; resolution_attempt=$resolutionText"
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
        indexed_path = if ($selectedRecord -and $selectedRecord.PSObject.Properties['path']) { [string]$selectedRecord.path } elseif (-not [string]::IsNullOrWhiteSpace($LocalPath)) { [string]$LocalPath } else { '' }
        indexed_relative_path = if ($selectedRecord -and $selectedRecord.PSObject.Properties['relative_path']) { [string]$selectedRecord.relative_path } else { '' }
        indexed_name = if ($selectedRecord -and $selectedRecord.PSObject.Properties['name']) { [string]$selectedRecord.name } elseif (-not [string]::IsNullOrWhiteSpace($LocalPath)) { Split-Path -Path ([string]$LocalPath) -Leaf } else { '' }
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

$existingIndex = Read-JsonFile -Path $mirrorIndexAbs
$existingMirrors = @()
$preserveExistingUploadedMirror = $false
if ($existingIndex -and $existingIndex.PSObject.Properties['mirrors']) {
    foreach ($existingMirror in @($existingIndex.mirrors)) {
        if (-not $existingMirror -or -not $existingMirror.source -or -not $existingMirror.source.PSObject.Properties['sha256']) {
            continue
        }
        $existingPath = if ($existingMirror.source.PSObject.Properties['path']) { [string]$existingMirror.source.path } else { '' }
        $existingIndexedPath = if ($existingMirror.source.PSObject.Properties['indexed_path']) { [string]$existingMirror.source.indexed_path } else { '' }
        $manifestIndexedPath = if ($manifest.source.PSObject.Properties['indexed_path']) { [string]$manifest.source.indexed_path } else { '' }
        $sameSource = (
            (-not [string]::IsNullOrWhiteSpace($existingPath) -and $existingPath -eq [string]$manifest.source.path) -or
            (-not [string]::IsNullOrWhiteSpace($existingIndexedPath) -and -not [string]::IsNullOrWhiteSpace($manifestIndexedPath) -and $existingIndexedPath -eq $manifestIndexedPath)
        )
        $existingRemoteUploaded = (
            $existingMirror.remote -and
            $existingMirror.remote.PSObject.Properties['uploaded'] -and
            [bool]$existingMirror.remote.uploaded -and
            $existingMirror.remote.PSObject.Properties['path'] -and
            -not [string]::IsNullOrWhiteSpace([string]$existingMirror.remote.path)
        )
        if ($sameSource -and -not $UploadToMim -and $existingRemoteUploaded) {
            $existingMirrors += $existingMirror
            $preserveExistingUploadedMirror = $true
            continue
        }
        if (-not $sameSource) {
            $existingMirrors += $existingMirror
        }
    }
}
$mirrorsForIndex = if ($preserveExistingUploadedMirror) { @($existingMirrors) } else { @($existingMirrors + @($manifest)) }
$mirrorIndex = [ordered]@{
    packet_type = 'mim-station-file-mirror-index-v1'
    generated_at = Get-UtcNowText
    status = 'updated'
    mirror_count = @($mirrorsForIndex).Count
    latest_source_sha256 = $hash
    mirrors = @($mirrorsForIndex)
    policy = 'Registry of source files safely mirrored after TOD validates each requested path against approved MIM roots.'
}
Write-Utf8NoBomJson -Object $mirrorIndex -Path $mirrorIndexAbs -Depth 14

if ($UploadToMim) {
    $sendScript = Join-Path $repoRoot 'scripts\Send-TODMimScript.ps1'
    $manifestUploadPath = $outputAbs
    if ($manifestUploadPath.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        $manifestUploadPath = $manifestUploadPath.Substring($repoRoot.Length).TrimStart('\', '/')
    }
    & $sendScript -EnvFile $EnvFile -LocalPath $manifestUploadPath -RemotePath $RemoteManifestPath | Out-Null

    $mirrorIndexUploadPath = $mirrorIndexAbs
    if ($mirrorIndexUploadPath.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        $mirrorIndexUploadPath = $mirrorIndexUploadPath.Substring($repoRoot.Length).TrimStart('\', '/')
    }
    & $sendScript -EnvFile $EnvFile -LocalPath $mirrorIndexUploadPath -RemotePath $RemoteMirrorIndexPath | Out-Null
}

$manifest | ConvertTo-Json -Depth 12
