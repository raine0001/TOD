<#
.SYNOPSIS
    TOD Spokesperson Video Pipeline - orchestrates the full talking-head video creation workflow.

.DESCRIPTION
    Generates a photorealistic talking-head spokesperson video using:
      1. edge-tts  - neural TTS audio (no API key, no prompts)
      2. rembg     - GPU background removal from avatar portrait
      3. Fooocus   - SDXL photorealistic background scene generation
      4. composite - avatar composited onto background (color matched, shadow, vignette)
      5. SadTalker - face animation with GFPGAN enhancement (95% realism target)

    The default preset produces: "you in a jungle talking to a spider about AI capabilities."

.PARAMETER Preset
    Path to a media-preset JSON file (default: tod/config/media-presets/jungle-spider-demo.json)

.PARAMETER AvatarPath
    Override avatar image path (overrides preset avatar.source_path)

.PARAMETER Script
    Override TTS script text (overrides preset tts.script)

.PARAMETER BackgroundPrompt
    Override background scene prompt (overrides preset background.prompt)

.PARAMETER OutputPath
    Output MP4 path (overrides preset output settings)

.PARAMETER WorkDir
    Scratch directory for intermediate files (default: tod/out/spokesperson/<job-id>)

.PARAMETER SadTalkerPath
    Path to local SadTalker clone (default: C:/AI/SadTalker)

.PARAMETER PythonExe
    Python executable path (default: python)

.PARAMETER DryRun
    Plan only - print what would run but do nothing.

.PARAMETER KeepIntermediate
    Keep all intermediate files (audio, bg image, composer frames) after completion.

.EXAMPLE
    # Run the jungle-spider demo (default)
    .\scripts\Invoke-TODSpokesperson.ps1

.EXAMPLE
    # Custom topic, same jungle background
    .\scripts\Invoke-TODSpokesperson.ps1 -Script "Today I want to talk about machine learning..."

.EXAMPLE
    # Full custom run with a different background
    .\scripts\Invoke-TODSpokesperson.ps1 `
        -BackgroundPrompt "photorealistic modern tech office, floor-to-ceiling windows, city skyline" `
        -Script "Welcome to our platform..." `
        -OutputPath "E:/mim images/video/office-intro.mp4"
#>
[CmdletBinding()]
param(
    [string]$Preset             = "tod/config/media-presets/jungle-spider-demo.json",
    [string]$AvatarPath         = "",
    [string]$Script             = "",
    [string]$BackgroundPrompt   = "",
    [string]$OutputPath         = "",
    [string]$WorkDir            = "",
    [string]$SadTalkerPath      = "C:/AI/SadTalker",
    [string]$PythonExe          = "python",
    [switch]$DryRun,
    [switch]$KeepIntermediate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot   = Split-Path -Parent $PSScriptRoot
$engineRoot = Join-Path $PSScriptRoot "engines\spokesperson"

function Resolve-RepoPath([string]$RelOrAbs) {
    if ([System.IO.Path]::IsPathRooted($RelOrAbs)) { return $RelOrAbs }
    return Join-Path $repoRoot $RelOrAbs
}

function Write-Step([string]$Num, [string]$Label) {
    Write-Host ""
    Write-Host "[$Num/6] $Label" -ForegroundColor Cyan
}

function Invoke-PythonEngine {
    param(
        [string]$Script,
        [string[]]$Arguments,
        [switch]$AllowFail
    )
    $scriptPath = Join-Path $engineRoot $Script
    if (-not (Test-Path $scriptPath)) { throw "Engine not found: $scriptPath" }

    Write-Host "  > $PythonExe $Script $($Arguments -join ' ')" -ForegroundColor DarkGray

    if ($DryRun) {
        Write-Host "  [DRY RUN] skipped" -ForegroundColor Yellow
        return $true
    }

    & $PythonExe $scriptPath @Arguments
    $ec = $LASTEXITCODE
    if ($ec -ne 0 -and -not $AllowFail) {
        throw "Python engine '$Script' exited with code $ec"
    }
    return ($ec -eq 0)
}

# --- Load preset --------------------------------------------------------------
$presetPath = Resolve-RepoPath -RelOrAbs $Preset
if (-not (Test-Path $presetPath)) { throw "Preset not found: $presetPath" }
$cfg = Get-Content $presetPath -Raw | ConvertFrom-Json
Write-Host ""
Write-Host "TOD Spokesperson Pipeline" -ForegroundColor Green
Write-Host "Preset: $($cfg.id) - $($cfg.description)" -ForegroundColor Green

# --- Apply overrides ----------------------------------------------------------
$avatarSrc = if ($AvatarPath -ne "") { $AvatarPath } else { Resolve-RepoPath -RelOrAbs ([string]$cfg.avatar.source_path) }
$ttsScript  = if ($Script -ne "")    { $Script }      else { [string]$cfg.tts.script }
$bgPrompt   = if ($BackgroundPrompt -ne "") { $BackgroundPrompt } else { [string]$cfg.background.prompt }

if (-not (Test-Path $avatarSrc)) {
    throw "Avatar image not found: $avatarSrc`n`nSolution: Copy your portrait photo to: $avatarSrc"
}

# --- Work directory -----------------------------------------------------------
$jobId = "SPK-" + [guid]::NewGuid().ToString("N").Substring(0, 8).ToUpperInvariant()
if ($WorkDir -eq "") {
    $WorkDir = Join-Path $repoRoot "tod\out\spokesperson\$jobId"
}
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
Write-Host "Job ID : $jobId" -ForegroundColor DarkCyan
Write-Host "WorkDir: $WorkDir" -ForegroundColor DarkCyan

# --- Resolve output path ------------------------------------------------------
if ($OutputPath -eq "") {
    $outDir  = Join-Path $repoRoot "tod\out\spokesperson"
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    $outFile = [string]$cfg.output.filename -replace "\.mp4$", "-$jobId.mp4"
    $OutputPath = Join-Path $outDir $outFile
}

# --- Intermediate paths -------------------------------------------------------
$paths = @{
    audio     = Join-Path $WorkDir "tts_audio.wav"
    avatarBg  = Join-Path $WorkDir "avatar_nobg.png"
    bg        = Join-Path $WorkDir "background.png"
    composite = Join-Path $WorkDir "composited.jpg"
    output    = $OutputPath
}

Write-Host ""
Write-Host "Plan:" -ForegroundColor White
Write-Host "  Avatar   : $avatarSrc"
Write-Host "  Audio    : $($paths.audio)"
Write-Host "  Background: $($paths.bg)"
Write-Host "  Composite : $($paths.composite)"
Write-Host "  Output    : $($paths.output)"
Write-Host ""

if ($DryRun) {
    Write-Host "[DRY RUN MODE - no files will be created]" -ForegroundColor Yellow
}

# -------------------------------------------------------------------------------
# STEP 1 - TTS Audio
# -------------------------------------------------------------------------------
Write-Step "1" "Generating TTS audio ($($cfg.tts.voice))"
Invoke-PythonEngine "tts_edge.py" @(
    "--text",   $ttsScript,
    "--voice",  [string]$cfg.tts.voice,
    "--rate",   [string]$cfg.tts.rate,
    "--pitch",  [string]$cfg.tts.pitch,
    "--volume", [string]$cfg.tts.volume,
    "--output", $paths.audio
)

# -------------------------------------------------------------------------------
# STEP 2 - Avatar Background Removal
# -------------------------------------------------------------------------------
Write-Step "2" "Removing avatar background (rembg $($cfg.avatar.rembg_model))"
$rembgArgs = @(
    "--input",  $avatarSrc,
    "--output", $paths.avatarBg,
    "--model",  [string]$cfg.avatar.rembg_model
)
if ([bool]$cfg.avatar.post_process_alpha) { $rembgArgs += "--post-process" }
Invoke-PythonEngine "rembg_extract.py" $rembgArgs

# -------------------------------------------------------------------------------
# STEP 3 - Background Scene Generation
# -------------------------------------------------------------------------------
Write-Step "3" "Generating background scene (Fooocus - ComfyUI fallback)"

# If spider prop is enabled, append to prompt
$effectivePrompt = $bgPrompt
if ($cfg.spider_prop -and [bool]$cfg.spider_prop.enabled -and $cfg.spider_prop.PSObject.Properties["prompt_addition"]) {
    $effectivePrompt = "$effectivePrompt, $($cfg.spider_prop.prompt_addition)"
}

$fooocusStyles = if ($cfg.background.PSObject.Properties["fooocus_styles"]) {
    ($cfg.background.fooocus_styles -join ",")
} else { "Fooocus V2,Fooocus Photograph,Fooocus Realistic" }

Invoke-PythonEngine "bg_fooocus.py" @(
    "--prompt",         $effectivePrompt,
    "--negative",       [string]$cfg.background.negative_prompt,
    "--width",          [string]$cfg.background.width,
    "--height",         [string]$cfg.background.height,
    "--steps",          [string]$cfg.background.steps,
    "--guidance",       [string]$cfg.background.guidance_scale,
    "--model",          [string]$cfg.background.model,
    "--styles",         $fooocusStyles,
    "--output",         $paths.bg
)

# -------------------------------------------------------------------------------
# STEP 4 - Composite Avatar onto Background
# -------------------------------------------------------------------------------
Write-Step "4" "Compositing avatar onto background scene"
$compArgs = @(
    "--avatar",         $paths.avatarBg,
    "--background",     $paths.bg,
    "--output",         $paths.composite,
    "--avatar-height",  [string]$cfg.composite.avatar_height,
    "--x-offset",       [string]$cfg.composite.x_offset,
    "--y-offset",       [string]$cfg.composite.y_offset,
    "--jpeg-quality",   [string]$cfg.composite.jpeg_quality
)
if ([bool]$cfg.composite.color_match) { $compArgs += "--color-match" }
if ([bool]$cfg.composite.shadow)      { $compArgs += "--shadow" }
if ([bool]$cfg.composite.vignette)    { $compArgs += "--vignette" }
Invoke-PythonEngine "composite_portrait.py" $compArgs

# -------------------------------------------------------------------------------
# STEP 5 - SadTalker Face Animation
# -------------------------------------------------------------------------------
Write-Step "5" "Animating talking-head (SadTalker size=$($cfg.animation.size) enhancer=$($cfg.animation.enhancer))"
$animArgs = @(
    "--source-image",      $paths.composite,
    "--driven-audio",      $paths.audio,
    "--output-dir",        $WorkDir,
    "--output-name",       "animated.mp4",
    "--sadtalker-path",    $SadTalkerPath,
    "--python-exe",        $PythonExe,
    "--enhancer",          [string]$cfg.animation.enhancer,
    "--size",              [string]$cfg.animation.size,
    "--preprocess",        [string]$cfg.animation.preprocess,
    "--pose-style",        [string]$cfg.animation.pose_style,
    "--expression-scale",  [string]$cfg.animation.expression_scale
)
if ([bool]$cfg.animation.still) { $animArgs += "--still" }
Invoke-PythonEngine "animate_sadtalker.py" $animArgs

# -------------------------------------------------------------------------------
# STEP 6 - Copy final output to destination
# -------------------------------------------------------------------------------
Write-Step "6" "Finalizing output"

$animatedMp4 = Join-Path $WorkDir "animated.mp4"

if (-not $DryRun) {
    if (-not (Test-Path $animatedMp4)) {
        # Try finding any mp4 in workdir
        $found = Get-ChildItem -Path $WorkDir -Filter "*.mp4" -Recurse | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($found) { $animatedMp4 = $found.FullName }
        else { throw "No output MP4 found in $WorkDir" }
    }

    $outDir = Split-Path -Parent $OutputPath
    if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
    Copy-Item -Path $animatedMp4 -Destination $OutputPath -Force

    $sizeMb = [math]::Round((Get-Item $OutputPath).Length / 1MB, 1)
    Write-Host ""
    Write-Host "- Complete!" -ForegroundColor Green
    Write-Host "  Output : $OutputPath ($sizeMb MB)" -ForegroundColor Green
    Write-Host "  Job ID : $jobId" -ForegroundColor DarkCyan

    if (-not $KeepIntermediate) {
        Write-Host "  Cleaning up intermediate files..." -ForegroundColor DarkGray
        Remove-Item -Path $WorkDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
else {
    Write-Host ""
    Write-Host "[DRY RUN] Pipeline plan complete. No files written." -ForegroundColor Yellow
    Write-Host "  Would output to: $OutputPath" -ForegroundColor Yellow
}

# --- Return summary -----------------------------------------------------------
[pscustomobject]@{
    ok         = (-not $DryRun)
    job_id     = $jobId
    preset     = $cfg.id
    output     = $OutputPath
    dry_run    = [bool]$DryRun
    avatar_src = $avatarSrc
} | ConvertTo-Json -Depth 5 | Write-Output
