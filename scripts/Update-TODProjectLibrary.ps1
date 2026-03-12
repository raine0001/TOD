param(
    [string]$RootPath = "E:\\",
    [string]$RegistryPath = "tod/config/project-registry.json",
    [string]$OutputPath = "tod/data/project-library-index.json",
    [int]$SampleLimit = 25,
    [int]$MaxScanDepth = 2
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

function Resolve-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return $PathValue
    }

    return (Join-Path $repoRoot $PathValue)
}

function Normalize-Path {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    return ($PathValue -replace "[\\/]+", "/")
}

function Get-SafeChildItems {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [switch]$Directories,
        [switch]$Files
    )

    try {
        if ($Directories) {
            return @(Get-ChildItem -Path $Path -Directory -Force -ErrorAction Stop)
        }
        if ($Files) {
            return @(Get-ChildItem -Path $Path -File -Force -ErrorAction Stop)
        }
        return @(Get-ChildItem -Path $Path -Force -ErrorAction Stop)
    }
    catch {
        return @()
    }
}

function Get-FilesUpToDepth {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [int]$Depth = 2
    )

    $result = @()
    $queue = New-Object System.Collections.Queue
    $queue.Enqueue([pscustomobject]@{ path = $BasePath; depth = 0 })

    while ($queue.Count -gt 0) {
        $node = $queue.Dequeue()
        $dirs = Get-SafeChildItems -Path $node.path -Directories
        $files = Get-SafeChildItems -Path $node.path -Files
        if (@($files).Count -gt 0) {
            $result += $files
        }

        if ($node.depth -lt $Depth) {
            foreach ($dir in $dirs) {
                $queue.Enqueue([pscustomobject]@{ path = $dir.FullName; depth = $node.depth + 1 })
            }
        }
    }

    return @($result)
}

$resolvedRegistryPath = Resolve-LocalPath -PathValue $RegistryPath
$resolvedOutputPath = Resolve-LocalPath -PathValue $OutputPath

if (-not (Test-Path -Path $RootPath)) {
    throw "RootPath not found: $RootPath"
}
if (-not (Test-Path -Path $resolvedRegistryPath)) {
    throw "Registry file not found: $resolvedRegistryPath"
}

$registry = (Get-Content -Path $resolvedRegistryPath -Raw | ConvertFrom-Json)
$configuredProjects = if ($registry.PSObject.Properties["projects"]) { @($registry.projects) } else { @() }

$skipTopLevel = @('$RECYCLE.BIN', 'System Volume Information')
$topLevelDirs = @(Get-SafeChildItems -Path $RootPath -Directories | Where-Object { $skipTopLevel -notcontains $_.Name })

$projects = @()
foreach ($project in $configuredProjects) {
    $projectPath = [string]$project.path
    $fullProjectPath = if ([System.IO.Path]::IsPathRooted($projectPath)) { $projectPath } else { Join-Path $RootPath $projectPath }
    $exists = Test-Path -Path $fullProjectPath

    $files = @()
    $extCounts = @{}
    $sampleFiles = @()
    $detectedTests = @()
    $detectedEntrypoints = @()

    if ($exists) {
        $files = Get-FilesUpToDepth -BasePath $fullProjectPath -Depth $MaxScanDepth

        foreach ($file in $files) {
            $ext = [string]$file.Extension
            if ([string]::IsNullOrWhiteSpace($ext)) { $ext = "<none>" }
            if (-not $extCounts.ContainsKey($ext)) {
                $extCounts[$ext] = 0
            }
            $extCounts[$ext] = [int]$extCounts[$ext] + 1
        }

        $sampleFiles = @(
            $files |
                Sort-Object LastWriteTimeUtc -Descending |
                Select-Object -First $SampleLimit |
                ForEach-Object {
                    $relative = $_.FullName.Substring($fullProjectPath.Length).TrimStart([char[]]@([char]92, [char]47))
                    Normalize-Path -PathValue $relative
                }
        )

        $testPatterns = @("test", "tests", "pytest", ".Tests.ps1")
        $detectedTests = @(
            $files |
                Where-Object {
                    $name = $_.Name.ToLowerInvariant()
                    $name -like "*test*" -or $name -like "*.tests.ps1" -or $name -eq "pytest.ini" -or $name -eq "conftest.py"
                } |
                Select-Object -First 10 |
                ForEach-Object {
                    $relative = $_.FullName.Substring($fullProjectPath.Length).TrimStart([char[]]@([char]92, [char]47))
                    Normalize-Path -PathValue $relative
                }
        )

        $entryCandidates = @("main.py", "app.py", "server.py", "package.json", "README.md", "scripts/TOD.ps1")
        foreach ($candidate in $entryCandidates) {
            $candidateFull = Join-Path $fullProjectPath $candidate
            if (Test-Path -Path $candidateFull) {
                $detectedEntrypoints += (Normalize-Path -PathValue $candidate)
            }
        }
    }

    $extList = @()
    foreach ($key in @($extCounts.Keys | Sort-Object)) {
        $extList += [pscustomobject]@{
            extension = $key
            count = [int]$extCounts[$key]
        }
    }

    $projects += [pscustomobject]@{
        id = [string]$project.id
        name = [string]$project.name
        type = [string]$project.type
        path = (Normalize-Path -PathValue $fullProjectPath)
        exists = $exists
        risk_level = [string]$project.risk_level
        write_access = [string]$project.write_access
        language_hint = if ($project.PSObject.Properties["languages"]) { @($project.languages) } else { @() }
        configured_entry_points = if ($project.PSObject.Properties["entry_points"]) { @($project.entry_points) } else { @() }
        configured_test_commands = if ($project.PSObject.Properties["test_commands"]) { @($project.test_commands) } else { @() }
        boundaries = if ($project.PSObject.Properties["boundaries"]) { $project.boundaries } else { $null }
        discovery = [pscustomobject]@{
            scanned_at = (Get-Date).ToUniversalTime().ToString("o")
            max_depth = $MaxScanDepth
            sampled_files = @($sampleFiles)
            extension_summary = @($extList)
            detected_test_artifacts = @($detectedTests)
            detected_entrypoints = @($detectedEntrypoints)
        }
    }
}

$registeredPaths = @($configuredProjects | ForEach-Object { Normalize-Path -PathValue ([string]$_.path) })
$unregistered = @(
    $topLevelDirs |
        Where-Object {
            $full = Normalize-Path -PathValue $_.FullName
            $registeredPaths -notcontains $full
        } |
        Select-Object -ExpandProperty FullName |
        ForEach-Object { Normalize-Path -PathValue $_ }
)

$output = [pscustomobject]@{
    ok = $true
    source = "tod-project-library-index-v1"
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    library_root = (Normalize-Path -PathValue $RootPath)
    registry_path = (Normalize-Path -PathValue $resolvedRegistryPath)
    registered_project_count = @($projects).Count
    projects = @($projects)
    unregistered_top_level_directories = @($unregistered)
}

$outputDir = Split-Path -Parent $resolvedOutputPath
if (-not (Test-Path -Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$output | ConvertTo-Json -Depth 30 | Set-Content -Path $resolvedOutputPath
$output | ConvertTo-Json -Depth 12 | Write-Output
