[CmdletBinding()]
param(
    [string]$OutputDir = "tod/out/runpod-bootstrap",
    [string]$ArchiveName = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$repoRoot = Split-Path -Parent $PSScriptRoot

function Resolve-RepoPath([string]$RelativePath) {
    return Join-Path $repoRoot $RelativePath
}

function Copy-FilteredTree {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source,

        [Parameter(Mandatory = $true)]
        [string]$Destination
    )

    if (-not (Test-Path $Source)) {
        throw "Path not found: $Source"
    }

    $sourceItem = Get-Item -LiteralPath $Source
    if ($sourceItem.PSIsContainer) {
        New-Item -ItemType Directory -Force -Path $Destination | Out-Null

        Get-ChildItem -LiteralPath $Source -Force | ForEach-Object {
            if ($_.Name -eq "__pycache__") { return }
            if (-not $_.PSIsContainer -and $_.Extension -eq ".pyc") { return }

            $childDestination = Join-Path $Destination $_.Name
            Copy-FilteredTree -Source $_.FullName -Destination $childDestination
        }
        return
    }

    $parentDir = Split-Path -Parent $Destination
    if ($parentDir) {
        New-Item -ItemType Directory -Force -Path $parentDir | Out-Null
    }

    Copy-Item -LiteralPath $Source -Destination $Destination -Force
}

$requiredPaths = @(
    "README.md",
    "scripts/Invoke-TODSpokesperson.ps1",
    "scripts/Invoke-TODSpokesperson-RunPod.ps1",
    "scripts/Setup-TODSpokesperson.ps1",
    "scripts/Test-TODSpokesperson.ps1",
    "scripts/goTODRunPodGloria.ps1",
    "scripts/bootstrap_runpod_pod.sh",
    "scripts/engines/spokesperson",
    "tod/data/avatars/README.md",
    "tod/config/media-presets/gloria-cowell.json",
    "tod/config/media-presets/jungle-spider-demo.json"
)

$optionalPaths = @(
    "tod/data/avatars/gloria cowell.png",
    "tod/data/avatars/user-avatar.jpg"
)

$resolvedOutputDir = Resolve-RepoPath $OutputDir
New-Item -ItemType Directory -Force -Path $resolvedOutputDir | Out-Null

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
if ([string]::IsNullOrWhiteSpace($ArchiveName)) {
    $ArchiveName = "tod-runpod-bootstrap-$stamp.zip"
}
if (-not $ArchiveName.EndsWith(".zip", [System.StringComparison]::OrdinalIgnoreCase)) {
    $ArchiveName = "$ArchiveName.zip"
}

$archivePath = Join-Path $resolvedOutputDir $ArchiveName
$stagingRoot = Join-Path $env:TEMP ("tod-runpod-bootstrap-" + [guid]::NewGuid().ToString("N"))
$packageRoot = Join-Path $stagingRoot "TOD"

try {
    New-Item -ItemType Directory -Force -Path $packageRoot | Out-Null

    foreach ($relativePath in $requiredPaths) {
        $sourcePath = Resolve-RepoPath $relativePath
        if (-not (Test-Path $sourcePath)) {
            throw "Required path is missing from the workspace: $relativePath"
        }

        $destinationPath = Join-Path $packageRoot $relativePath
        Copy-FilteredTree -Source $sourcePath -Destination $destinationPath
    }

    foreach ($relativePath in $optionalPaths) {
        $sourcePath = Resolve-RepoPath $relativePath
        if (-not (Test-Path $sourcePath)) {
            Write-Warning "Optional RunPod bootstrap asset missing: $relativePath"
            continue
        }

        $destinationPath = Join-Path $packageRoot $relativePath
        Copy-FilteredTree -Source $sourcePath -Destination $destinationPath
    }

    if (Test-Path $archivePath) {
        Remove-Item -LiteralPath $archivePath -Force
    }

    $zip = [System.IO.Compression.ZipFile]::Open($archivePath, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        Get-ChildItem -LiteralPath $packageRoot -Recurse -File | ForEach-Object {
            $relativePath = [System.IO.Path]::GetRelativePath($packageRoot, $_.FullName)
            $entryName = $relativePath -replace "\\", "/"
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $_.FullName, $entryName, [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
        }
    }
    finally {
        $zip.Dispose()
    }

    Write-Host "Created RunPod bootstrap pack:" -ForegroundColor Green
    Write-Host $archivePath -ForegroundColor Cyan
}
finally {
    if (Test-Path $stagingRoot) {
        Remove-Item -LiteralPath $stagingRoot -Recurse -Force
    }
}