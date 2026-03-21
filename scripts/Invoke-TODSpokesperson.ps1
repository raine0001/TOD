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
    if ($AvatarPath -eq "") {
        $avatarDir = Join-Path $repoRoot "tod\data\avatars"
        if (Test-Path $avatarDir) {
            $fallback = @(Get-ChildItem -Path (Join-Path $avatarDir "*") -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -in @('.jpg', '.jpeg', '.png') } |
                Where-Object { $_.Name -ne "README.md" } |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1)
            if ($fallback.Count -gt 0) {
                $avatarSrc = $fallback[0].FullName
                Write-Host "Avatar fallback selected: $($fallback[0].Name)" -ForegroundColor Yellow
            }
        }
    }
}

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
    composite = Join-Path $WorkDir "composited.png"
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
    "--rate=$([string]$cfg.tts.rate)",
    "--pitch=$([string]$cfg.tts.pitch)",
    "--volume=$([string]$cfg.tts.volume)",
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
$finalSourceMp4 = $animatedMp4

if (-not $DryRun) {
    if (-not (Test-Path $animatedMp4)) {
        # Try finding any mp4 in workdir
        $found = Get-ChildItem -Path $WorkDir -Filter "*.mp4" -Recurse | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($found) { $animatedMp4 = $found.FullName }
        else { throw "No output MP4 found in $WorkDir" }
    }

    # Optional temporal smoothing to reduce visible micro-jitter in motion.
    if ($cfg.output -and $cfg.output.PSObject.Properties["smoothing"] -and [bool]$cfg.output.smoothing.enabled) {
        $ffmpegExe = $null
        $ffmpegCandidates = @(
            "ffmpeg",
            "C:\Program Files\FFmpeg\bin\ffmpeg.exe"
        )
        $wingetFfmpeg = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Directory -Filter "Gyan.FFmpeg_*" -ErrorAction SilentlyContinue |
            ForEach-Object { Join-Path $_.FullName "ffmpeg-8.1-full_build\bin\ffmpeg.exe" } |
            Where-Object { Test-Path $_ } |
            Select-Object -First 1
        if ($wingetFfmpeg) { $ffmpegCandidates += $wingetFfmpeg }

        foreach ($candidate in $ffmpegCandidates) {
            $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
            if ($cmd) { $ffmpegExe = $cmd.Source; break }
            if (Test-Path $candidate) { $ffmpegExe = $candidate; break }
        }

        if ($ffmpegExe) {
            $smoothMp4 = Join-Path $WorkDir "animated_smooth.mp4"
            $targetFps = if ($cfg.output.smoothing.PSObject.Properties["target_fps"]) { [int]$cfg.output.smoothing.target_fps } else { 30 }
            $miMode = if ($cfg.output.smoothing.PSObject.Properties["mode"]) { [string]$cfg.output.smoothing.mode } else { "mci" }
            $mcMode = if ($cfg.output.smoothing.PSObject.Properties["mc_mode"]) { [string]$cfg.output.smoothing.mc_mode } else { "aobmc" }
            $meMode = if ($cfg.output.smoothing.PSObject.Properties["me_mode"]) { [string]$cfg.output.smoothing.me_mode } else { "bidir" }
            $vsbmc = if ($cfg.output.smoothing.PSObject.Properties["vsbmc"]) { [int]$cfg.output.smoothing.vsbmc } else { 1 }
            $crf = if ($cfg.output.smoothing.PSObject.Properties["crf"]) { [int]$cfg.output.smoothing.crf } else { 18 }
            $preset = if ($cfg.output.smoothing.PSObject.Properties["preset"]) { [string]$cfg.output.smoothing.preset } else { "medium" }

            $vf = "minterpolate=fps=$targetFps`:mi_mode=$miMode`:mc_mode=$mcMode`:me_mode=$meMode`:vsbmc=$vsbmc"
            Write-Host "  Applying temporal smoothing with ffmpeg ($targetFps fps)..." -ForegroundColor DarkGray
            & $ffmpegExe -y -i $animatedMp4 -vf $vf -c:v libx264 -preset $preset -crf $crf -c:a copy $smoothMp4 | Out-Null
            if ($LASTEXITCODE -eq 0 -and (Test-Path $smoothMp4)) {
                $finalSourceMp4 = $smoothMp4
                Write-Host "  Smoothing complete: $smoothMp4" -ForegroundColor DarkGray
            } else {
                Write-Host "  WARN: ffmpeg smoothing failed; using original animation output" -ForegroundColor Yellow
            }
        } else {
            Write-Host "  WARN: ffmpeg not found; skipping smoothing stage" -ForegroundColor Yellow
        }
    }

    # Ensure the final deliverable has an audio stream; if missing, mux from TTS source.
    $probeExe = $null
    $probeCandidates = @(
        "ffprobe",
        "C:\Program Files\FFmpeg\bin\ffprobe.exe"
    )
    $wingetProbe = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Directory -Filter "Gyan.FFmpeg_*" -ErrorAction SilentlyContinue |
        ForEach-Object { Join-Path $_.FullName "ffmpeg-8.1-full_build\bin\ffprobe.exe" } |
        Where-Object { Test-Path $_ } |
        Select-Object -First 1
    if ($wingetProbe) { $probeCandidates += $wingetProbe }

    foreach ($candidate in $probeCandidates) {
        $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($cmd) { $probeExe = $cmd.Source; break }
        if (Test-Path $candidate) { $probeExe = $candidate; break }
    }

    if ($probeExe) {
        $hasAudio = & $probeExe -v error -select_streams a -show_entries stream=codec_type -of csv=p=0 $finalSourceMp4 2>$null
        if ([string]::IsNullOrWhiteSpace([string]$hasAudio) -and (Test-Path $paths.audio)) {
            $ffmpegExe = $null
            $ffmpegCandidates = @(
                "ffmpeg",
                "C:\Program Files\FFmpeg\bin\ffmpeg.exe"
            )
            $wingetFfmpeg = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Directory -Filter "Gyan.FFmpeg_*" -ErrorAction SilentlyContinue |
                ForEach-Object { Join-Path $_.FullName "ffmpeg-8.1-full_build\bin\ffmpeg.exe" } |
                Where-Object { Test-Path $_ } |
                Select-Object -First 1
            if ($wingetFfmpeg) { $ffmpegCandidates += $wingetFfmpeg }

            foreach ($candidate in $ffmpegCandidates) {
                $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
                if ($cmd) { $ffmpegExe = $cmd.Source; break }
                if (Test-Path $candidate) { $ffmpegExe = $candidate; break }
            }

            if ($ffmpegExe) {
                $muxedMp4 = Join-Path $WorkDir "animated_with_audio.mp4"
                Write-Host "  Final audio stream missing; muxing TTS audio into output..." -ForegroundColor DarkGray
                & $ffmpegExe -y -i $finalSourceMp4 -i $paths.audio -c:v copy -c:a aac -shortest $muxedMp4 | Out-Null
                if ($LASTEXITCODE -eq 0 -and (Test-Path $muxedMp4)) {
                    $finalSourceMp4 = $muxedMp4
                } else {
                    Write-Host "  WARN: final audio mux failed; output may be silent" -ForegroundColor Yellow
                }
            }
        }
    }

    $outDir = Split-Path -Parent $OutputPath
    if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
    Copy-Item -Path $finalSourceMp4 -Destination $OutputPath -Force

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
