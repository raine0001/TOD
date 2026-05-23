param(
    [string[]]$RootPaths = @(
        'E:\MIM',
        'E:\MIM Robotics',
        'E:\MIM BOX',
        'E:\Mimir',
        'E:\mim_devl',
        'E:\mim_pulz',
        'E:\mim_wall',
        'E:\mim images'
    ),
    [string]$PrimaryWorkingPath = 'E:\MIM Robotics\design_parts',
    [string]$OutputPath = 'runtime/shared/MIM_STATION_FILE_INDEX.latest.json',
    [int]$MaxFilesPerRoot = 20000,
    [int]$RecentDays = 14,
    [switch]$IncludeFullFileList,
    [switch]$UploadToMim,
    [string]$EnvFile = '.env',
    [string]$RemotePath = '/home/testpilot/mim/runtime/shared/MIM_STATION_FILE_INDEX.latest.json'
)

$ErrorActionPreference = 'Stop'

function Get-UtcNowText {
    return [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
}

function Get-FileCategory {
    param([string]$Extension)
    $ext = ([string]$Extension).ToLowerInvariant()
    switch ($ext) {
        '.stl' { '3d-model'; break }
        '.3mf' { '3d-model'; break }
        '.skp' { 'sketchup-model'; break }
        '.skb' { 'sketchup-backup'; break }
        '.obj' { '3d-model'; break }
        '.step' { 'cad-model'; break }
        '.stp' { 'cad-model'; break }
        '.f3d' { 'cad-model'; break }
        '.jpg' { 'image'; break }
        '.jpeg' { 'image'; break }
        '.png' { 'image'; break }
        '.webp' { 'image'; break }
        '.gif' { 'image'; break }
        '.docx' { 'document'; break }
        '.pdf' { 'document'; break }
        '.txt' { 'text'; break }
        '.md' { 'text'; break }
        '.json' { 'structured-data'; break }
        '.csv' { 'structured-data'; break }
        default { if ([string]::IsNullOrWhiteSpace($ext)) { 'unknown' } else { 'other' } }
    }
}

function Get-TokenTags {
    param([string]$PathText)
    $text = ([string]$PathText).ToLowerInvariant()
    $tags = New-Object System.Collections.Generic.List[string]
    foreach ($token in @('arm', 'base', 'servo', 'claw', 'gear', 'cap', 'camera', 'mount', 'bracket', 'shell', 'plate', 'wrist', 'turn')) {
        if ($text -match [regex]::Escape($token)) { $tags.Add($token) | Out-Null }
    }
    return @($tags | Select-Object -Unique)
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$outputAbs = if ([System.IO.Path]::IsPathRooted($OutputPath)) { $OutputPath } else { Join-Path $repoRoot $OutputPath }
$primaryResolved = if (Test-Path -LiteralPath $PrimaryWorkingPath) {
    [System.IO.Path]::GetFullPath($PrimaryWorkingPath)
} else {
    $PrimaryWorkingPath
}

$roots = New-Object System.Collections.Generic.List[object]
$allFiles = New-Object System.Collections.Generic.List[object]
$cutoff = (Get-Date).AddDays(-1 * [math]::Abs($RecentDays))

foreach ($root in $RootPaths) {
    $exists = Test-Path -LiteralPath $root
    $rootInfo = [ordered]@{
        path = $root
        exists = [bool]$exists
        indexed = $false
        file_count = 0
        error = ''
    }
    if ($exists) {
        try {
            $resolvedRoot = [System.IO.Path]::GetFullPath($root)
            $files = @(Get-ChildItem -LiteralPath $resolvedRoot -Recurse -File -Force -ErrorAction SilentlyContinue | Select-Object -First $MaxFilesPerRoot)
            $rootInfo.indexed = $true
            $rootInfo.file_count = $files.Count
            foreach ($file in $files) {
                $pathText = [string]$file.FullName
                $relative = $pathText
                if ($pathText.StartsWith($resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $relative = $pathText.Substring($resolvedRoot.Length).TrimStart('\', '/')
                }
                $isPrimary = $pathText.StartsWith($primaryResolved, [System.StringComparison]::OrdinalIgnoreCase)
                $allFiles.Add([pscustomobject]@{
                    path = $pathText
                    root = $resolvedRoot
                    relative_path = $relative
                    name = $file.Name
                    extension = $file.Extension
                    category = Get-FileCategory -Extension $file.Extension
                    size_bytes = [int64]$file.Length
                    last_write_time_local = $file.LastWriteTime.ToString('yyyy-MM-ddTHH:mm:sszzz')
                    last_write_time_utc = $file.LastWriteTimeUtc.ToString('yyyy-MM-ddTHH:mm:ssZ')
                    tags = @(Get-TokenTags -PathText $pathText)
                    primary_working_context = [bool]$isPrimary
                }) | Out-Null
            }
        } catch {
            $rootInfo.error = $_.Exception.Message
        }
    }
    $roots.Add([pscustomobject]$rootInfo) | Out-Null
}

$rootsArray = @($roots.ToArray())
$filesArray = @($allFiles.ToArray())
$primaryFiles = @($filesArray | Where-Object { $_.primary_working_context })
$recentFiles = @($filesArray | Where-Object {
    try { ([DateTime]$_.last_write_time_utc) -ge $cutoff.ToUniversalTime() } catch { $false }
} | Sort-Object last_write_time_utc -Descending | Select-Object -First 80)
$armCandidates = @($filesArray | Where-Object {
    @($_.tags) -contains 'arm' -or @($_.tags) -contains 'servo' -or @($_.tags) -contains 'claw' -or @($_.tags) -contains 'gear'
} | Sort-Object primary_working_context,last_write_time_utc -Descending | Select-Object -First 120)

$byExtension = @{}
foreach ($group in ($filesArray | Group-Object extension)) {
    $key = if ([string]::IsNullOrWhiteSpace($group.Name)) { '(none)' } else { $group.Name.ToLowerInvariant() }
    $byExtension[$key] = $group.Count
}

$payload = [ordered]@{
    packet_type = 'mim-station-file-index-v1'
    generated_at = Get-UtcNowText
    status = 'completed_with_evidence'
    success = $true
    station = $env:COMPUTERNAME
    policy = 'This artifact gives MIM/TOD metadata-level access to local MIM station files. It does not copy source model contents unless separately mirrored.'
    requested_access = @{
        requested_root = 'E:/MIM'
        requested_root_exists = [bool](Test-Path -LiteralPath 'E:\MIM')
        discovered_mim_roots = @($rootsArray | Where-Object { $_.exists } | ForEach-Object { $_.path })
        primary_working_path = $PrimaryWorkingPath
        primary_working_path_exists = [bool](Test-Path -LiteralPath $PrimaryWorkingPath)
    }
    totals = @{
        roots_requested = $RootPaths.Count
        roots_existing = @($rootsArray | Where-Object { $_.exists }).Count
        files_indexed = $filesArray.Count
        primary_working_files = $primaryFiles.Count
    }
    roots = $rootsArray
    files_by_extension = $byExtension
    primary_working_context = @{
        path = $PrimaryWorkingPath
        exists = [bool](Test-Path -LiteralPath $PrimaryWorkingPath)
        file_count = $primaryFiles.Count
        recent_files = @($primaryFiles | Sort-Object last_write_time_utc -Descending | Select-Object -First 80)
        arm_component_candidates = $armCandidates
    }
    recent_files = $recentFiles
    files = if ($IncludeFullFileList) { $filesArray } else { @() }
    full_file_list_included = [bool]$IncludeFullFileList
    next_recovery_action = if (Test-Path -LiteralPath 'E:\MIM') { '' } else { 'Create E:\MIM if that is intended as a canonical root, or keep E:\MIM Robotics as the current MIM arm design root.' }
}

$outDir = Split-Path -Parent $outputAbs
if (-not (Test-Path -LiteralPath $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}
$jsonText = $payload | ConvertTo-Json -Depth 12
[System.IO.File]::WriteAllText($outputAbs, $jsonText, (New-Object System.Text.UTF8Encoding($false)))

if ($UploadToMim) {
    $sendScript = Join-Path $repoRoot 'scripts\Send-TODMimScript.ps1'
    if (-not (Test-Path -LiteralPath $sendScript)) { throw "Upload script not found: $sendScript" }
    $uploadLocalPath = $outputAbs
    if ($outputAbs.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        $uploadLocalPath = $outputAbs.Substring($repoRoot.Length).TrimStart('\', '/')
    }
    & $sendScript -EnvFile $EnvFile -LocalPath $uploadLocalPath -RemotePath $RemotePath | Out-Null
}

$payload | ConvertTo-Json -Depth 8
