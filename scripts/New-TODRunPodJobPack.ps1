[CmdletBinding()]
param(
    [string]$Preset = "tod/config/media-presets/gloria-cowell.json",
    [string]$AvatarPath = "",
    [string]$Script = "",
    [string]$BackgroundPrompt = "",
    [string]$WorkDir = "",
    [string]$PythonExe = "python",
    [string]$OutputDir = "tod/out/runpod-jobs",
    [string]$ArchiveName = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$repoRoot = Split-Path -Parent $PSScriptRoot
$engineRoot = Join-Path $PSScriptRoot "engines\spokesperson"

function Resolve-RepoPath([string]$RelOrAbs) {
    if ([System.IO.Path]::IsPathRooted($RelOrAbs)) { return $RelOrAbs }
    return Join-Path $repoRoot $RelOrAbs
}

function Write-Step([string]$Num, [string]$Label) {
    Write-Host ""
    Write-Host "[$Num/4] $Label" -ForegroundColor Cyan
}

function Resolve-AvatarSource {
    param(
        [Parameter(Mandatory = $true)][string]$CandidatePath,
        [Parameter(Mandatory = $true)][string]$RepoRootPath,
        [string]$ExplicitAvatarPath = ""
    )

    if (Test-Path $CandidatePath) {
        return $CandidatePath
    }

    if (-not [string]::IsNullOrWhiteSpace($ExplicitAvatarPath)) {
        return $CandidatePath
    }

    $avatarDir = Join-Path $RepoRootPath "tod\data\avatars"
    if (Test-Path $avatarDir) {
        $fallback = @(Get-ChildItem -Path (Join-Path $avatarDir "*") -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -in @('.jpg', '.jpeg', '.png', '.webp') } |
            Where-Object { $_.Name -ne "README.md" } |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1)
        if ($fallback.Count -gt 0) {
            Write-Host "Avatar fallback selected: $($fallback[0].Name)" -ForegroundColor Yellow
            return $fallback[0].FullName
        }
    }

    return $CandidatePath
}

function Invoke-PythonEngine {
    param(
        [string]$Script,
        [string[]]$Arguments
    )

    $scriptPath = Join-Path $engineRoot $Script
    if (-not (Test-Path $scriptPath)) { throw "Engine not found: $scriptPath" }

    Write-Host "  > $PythonExe $Script $($Arguments -join ' ')" -ForegroundColor DarkGray
    & $PythonExe $scriptPath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Python engine '$Script' exited with code $LASTEXITCODE"
    }
}

$presetPath = Resolve-RepoPath $Preset
if (-not (Test-Path $presetPath)) { throw "Preset not found: $presetPath" }

$cfg = Get-Content $presetPath -Raw | ConvertFrom-Json

$avatarSrc = if ($AvatarPath -ne "") { $AvatarPath } else { Resolve-RepoPath ([string]$cfg.avatar.source_path) }
$avatarSrc = Resolve-AvatarSource -CandidatePath $avatarSrc -RepoRootPath $repoRoot -ExplicitAvatarPath $AvatarPath
$ttsScript = if ($Script -ne "") { $Script } else { [string]$cfg.tts.script }
$bgPrompt = if ($BackgroundPrompt -ne "") { $BackgroundPrompt } else { [string]$cfg.background.prompt }

if (-not (Test-Path $avatarSrc)) {
    throw "Avatar image not found: $avatarSrc`n`nSolution: place a portrait at tod/data/avatars/user-avatar.jpg or pass -AvatarPath explicitly."
}

$jobId = "RJP-" + [guid]::NewGuid().ToString("N").Substring(0, 8).ToUpperInvariant()
if ($WorkDir -eq "") {
    $WorkDir = Join-Path $repoRoot "tod\out\runpod-jobs\$jobId"
}
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

$paths = @{
    audio = Join-Path $WorkDir "tts_audio.wav"
    avatarBg = Join-Path $WorkDir "avatar_nobg.png"
    bg = Join-Path $WorkDir "background.png"
    composite = Join-Path $WorkDir "composited.png"
    manifest = Join-Path $WorkDir "job.json"
}

Write-Host ""
Write-Host "TOD RunPod Job Pack" -ForegroundColor Green
Write-Host "Preset: $($cfg.id)" -ForegroundColor Green
Write-Host "Job ID: $jobId" -ForegroundColor DarkCyan
Write-Host "WorkDir: $WorkDir" -ForegroundColor DarkCyan

Write-Step "1" "Generating TTS audio ($($cfg.tts.voice))"
Invoke-PythonEngine "tts_edge.py" @(
    "--text", $ttsScript,
    "--voice", [string]$cfg.tts.voice,
    "--rate=$([string]$cfg.tts.rate)",
    "--pitch=$([string]$cfg.tts.pitch)",
    "--volume=$([string]$cfg.tts.volume)",
    "--output", $paths.audio
)

Write-Step "2" "Removing avatar background"
$rembgArgs = @(
    "--input", $avatarSrc,
    "--output", $paths.avatarBg,
    "--model", [string]$cfg.avatar.rembg_model
)
if ([bool]$cfg.avatar.post_process_alpha) { $rembgArgs += "--post-process" }
Invoke-PythonEngine "rembg_extract.py" $rembgArgs

Write-Step "3" "Generating background"
$effectivePrompt = $bgPrompt
if ($cfg.spider_prop -and [bool]$cfg.spider_prop.enabled -and $cfg.spider_prop.PSObject.Properties["prompt_addition"]) {
    $effectivePrompt = "$effectivePrompt, $($cfg.spider_prop.prompt_addition)"
}

$fooocusStyles = if ($cfg.background.PSObject.Properties["fooocus_styles"]) {
    ($cfg.background.fooocus_styles -join ",")
} else { "Fooocus V2,Fooocus Photograph,Fooocus Realistic" }

Invoke-PythonEngine "bg_fooocus.py" @(
    "--prompt", $effectivePrompt,
    "--negative", [string]$cfg.background.negative_prompt,
    "--width", [string]$cfg.background.width,
    "--height", [string]$cfg.background.height,
    "--steps", [string]$cfg.background.steps,
    "--guidance", [string]$cfg.background.guidance_scale,
    "--model", [string]$cfg.background.model,
    "--styles", $fooocusStyles,
    "--output", $paths.bg
)

Write-Step "4" "Compositing avatar onto background"
$compArgs = @(
    "--avatar", $paths.avatarBg,
    "--background", $paths.bg,
    "--output", $paths.composite,
    "--avatar-height", [string]$cfg.composite.avatar_height,
    "--x-offset", [string]$cfg.composite.x_offset,
    "--y-offset", [string]$cfg.composite.y_offset,
    "--jpeg-quality", [string]$cfg.composite.jpeg_quality
)
if ([bool]$cfg.composite.color_match) { $compArgs += "--color-match" }
if ([bool]$cfg.composite.shadow) { $compArgs += "--shadow" }
if ([bool]$cfg.composite.vignette) { $compArgs += "--vignette" }
Invoke-PythonEngine "composite_portrait.py" $compArgs

$manifest = [ordered]@{
    job_id = $jobId
    preset_id = [string]$cfg.id
    output_name = [string]$cfg.output.filename
    animation = [ordered]@{
        enhancer = [string]$cfg.animation.enhancer
        size = [int]$cfg.animation.size
        preprocess = [string]$cfg.animation.preprocess
        pose_style = [int]$cfg.animation.pose_style
        expression_scale = [double]$cfg.animation.expression_scale
        still = [bool]$cfg.animation.still
    }
    files = [ordered]@{
        audio = "tts_audio.wav"
        source_image = "composited.png"
    }
}

$manifest | ConvertTo-Json -Depth 6 | Set-Content -Path $paths.manifest -Encoding UTF8

$resolvedOutputDir = Resolve-RepoPath $OutputDir
New-Item -ItemType Directory -Force -Path $resolvedOutputDir | Out-Null

if ([string]::IsNullOrWhiteSpace($ArchiveName)) {
    $ArchiveName = "runpod-job-$($cfg.id)-$jobId.zip"
}
if (-not $ArchiveName.EndsWith(".zip", [System.StringComparison]::OrdinalIgnoreCase)) {
    $ArchiveName = "$ArchiveName.zip"
}

$archivePath = Join-Path $resolvedOutputDir $ArchiveName
if (Test-Path $archivePath) {
    Remove-Item -LiteralPath $archivePath -Force
}

$zip = [System.IO.Compression.ZipFile]::Open($archivePath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($name in @("tts_audio.wav", "composited.png", "job.json")) {
        $filePath = Join-Path $WorkDir $name
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $filePath, $name, [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
}
finally {
    $zip.Dispose()
}

Write-Host ""
Write-Host "Created RunPod job pack:" -ForegroundColor Green
Write-Host $archivePath -ForegroundColor Cyan

[pscustomobject]@{
    job_id = $jobId
    archive = $archivePath
    work_dir = $WorkDir
    composite = $paths.composite
    audio = $paths.audio
    manifest = $paths.manifest
} | ConvertTo-Json -Depth 5 | Write-Output