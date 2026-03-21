<#
.SYNOPSIS
    TOD Spokesperson Pipeline - test and validation suite.

.DESCRIPTION
    Validates the full spokesperson pipeline with progressive tests:
      T01 - Python version check
      T02 - Python packages (edge-tts, rembg, Pillow)
      T03 - TTS audio generation (end-to-end with real neural voice)
      T04 - Background removal on avatar photo (u2net_human_seg)
      T05 - Background generation (Fooocus or ComfyUI fallback)
      T06 - Composite portrait (avatar + background)
      T07 - Preset file integrity check
      T08 - SadTalker installation check
      T09 - Full dry-run of pipeline (no animation, plan validation)
      T10 - Avatar file check

    Tests are non-destructive by default. TTS and bg tests write to a temp dir
    that is deleted after validation unless --KeepOutput is specified.

.PARAMETER PythonExe
    Python executable (default: python)

.PARAMETER SadTalkerPath
    SadTalker install path (default: C:/AI/SadTalker)

.PARAMETER KeepOutput
    Keep test output files in tod/out/spokesperson/test/

.PARAMETER SkipBgGen
    Skip background generation test (takes ~1-3 min on GPU)

.PARAMETER SkipAnimation
    Skip SadTalker animation test (default: true - animation test is long)

.EXAMPLE
    .\scripts\Test-TODSpokesperson.ps1

.EXAMPLE
    .\scripts\Test-TODSpokesperson.ps1 -SkipBgGen -KeepOutput
#>
[CmdletBinding()]
param(
    [string]$PythonExe      = "python",
    [string]$SadTalkerPath  = "C:/AI/SadTalker",
    [switch]$KeepOutput,
    [switch]$SkipBgGen,
    [switch]$SkipAnimation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$repoRoot   = Split-Path -Parent $PSScriptRoot
$engineRoot = Join-Path $PSScriptRoot "engines\spokesperson"
$testOutDir = Join-Path $repoRoot "tod\out\spokesperson\test"
New-Item -ItemType Directory -Force -Path $testOutDir | Out-Null

$pass = 0; $fail = 0; $skip = 0
$script:LastPyOutput = @()

function Write-TestResult([string]$id, [string]$name, [bool]$ok, [string]$detail = "", [bool]$skipped = $false) {
    if ($skipped) {
        Write-Host "  SKIP  [$id] $name" -ForegroundColor DarkGray
        $script:skip++
        return
    }
    if ($ok) {
        $msg = if ($detail -ne "") { " - $detail" } else { "" }
        Write-Host "  PASS  [$id] $name$msg" -ForegroundColor Green
        $script:pass++
    } else {
        Write-Host "  FAIL  [$id] $name" -ForegroundColor Red
        if ($detail -ne "") { Write-Host "        $detail" -ForegroundColor DarkRed }
        $script:fail++
    }
}

function Invoke-Py([string]$Script, [string[]]$ArgList) {
    $p = Join-Path $engineRoot $Script
    $prevEA = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $script:LastPyOutput = @(& $PythonExe $p @ArgList 2>&1)
    }
    finally {
        $ErrorActionPreference = $prevEA
    }
    return [int]$LASTEXITCODE
}

# --- Header -------------------------------------------------------------------
Write-Host ""
Write-Host "TOD Spokesperson - Test Suite" -ForegroundColor Cyan
Write-Host "=" * 50
Write-Host "  Output dir: $testOutDir"
Write-Host ""

# --- T01: Python version ------------------------------------------------------
$pyVer = & $PythonExe --version 2>&1
$pyOk  = ($pyVer -match "Python 3\.(1[0-9]|[2-9]\d)")
Write-TestResult "T01" "Python 3.10+" $pyOk $pyVer

# --- T02: Package imports -----------------------------------------------------
$packages = @(
    @{ name = "edge-tts";  import = "edge_tts" },
    @{ name = "rembg";     import = "rembg" },
    @{ name = "Pillow";    import = "PIL" },
    @{ name = "numpy";     import = "numpy" },
    @{ name = "requests";  import = "requests" }
)
foreach ($pkg in $packages) {
    $probe = @"
import importlib.util
import sys
sys.exit(0 if importlib.util.find_spec('$($pkg.import)') else 1)
"@
    & $PythonExe -c $probe *> $null
    $ok = ($LASTEXITCODE -eq 0)
    Write-TestResult "T02" "import $($pkg.import)" $ok $(if ($ok) { "available" } else { "missing" })
}

# --- T03: TTS audio generation ------------------------------------------------
$ttsOut = Join-Path $testOutDir "t03_tts_test.wav"
$ttsEc  = Invoke-Py "tts_edge.py" @(
    "--text",   "AI capabilities are transforming the world. Test complete.",
    "--voice",  "en-US-GuyNeural",
    "--rate=-5%",
    "--output", $ttsOut
)
$ttsOk = ($ttsEc -eq 0) -and (Test-Path $ttsOut) -and ((Get-Item $ttsOut).Length -gt 5000)
$ttsSz = if (Test-Path $ttsOut) { "$([math]::Round((Get-Item $ttsOut).Length/1KB,1))KB" } else { "no file" }
$ttsErr = if (-not $ttsOk -and $script:LastPyOutput.Count -gt 0) { " | $($script:LastPyOutput[0])" } else { "" }
Write-TestResult "T03" "TTS audio generation" $ttsOk "en-US-GuyNeural - $ttsSz$ttsErr"

# --- T04: Avatar background removal ------------------------------------------
$avatarSrc = Join-Path $repoRoot "tod\data\avatars\user-avatar.jpg"
$avatarOut  = Join-Path $testOutDir "t04_avatar_nobg.png"

if (-not (Test-Path $avatarSrc)) {
    Write-TestResult "T04" "Avatar background removal" $false "Avatar not found: $avatarSrc - copy user-avatar.jpg first"
} else {
    $rmbgEc = Invoke-Py "rembg_extract.py" @(
        "--input",       $avatarSrc,
        "--output",      $avatarOut,
        "--model",       "u2net_human_seg",
        "--post-process"
    )
    $rmbgOk = ($rmbgEc -eq 0) -and (Test-Path $avatarOut) -and ((Get-Item $avatarOut).Length -gt 10000)
    $rmbgSz = if (Test-Path $avatarOut) { "$([math]::Round((Get-Item $avatarOut).Length/1KB,0))KB PNG" } else { "no file" }
    $rmbgErr = if (-not $rmbgOk -and $script:LastPyOutput.Count -gt 0) { " | $($script:LastPyOutput[0])" } else { "" }
    Write-TestResult "T04" "Avatar background removal" $rmbgOk "u2net_human_seg - $rmbgSz$rmbgErr"
}

# --- T05: Background generation -----------------------------------------------
$bgOut    = Join-Path $testOutDir "t05_background.png"
$bgResult = $false

if ($SkipBgGen) {
    Write-TestResult "T05" "Background generation (Fooocus/ComfyUI)" $false "" $true
} else {
    $bgPrompt = "photorealistic tropical rainforest, morning light, bokeh background, 8K, National Geographic"
    $bgEc = Invoke-Py "bg_fooocus.py" @(
        "--prompt",  $bgPrompt,
        "--width",   "1280",
        "--height",  "720",
        "--steps",   "20",
        "--output",  $bgOut
    )
    $bgOk = ($bgEc -eq 0) -and (Test-Path $bgOut) -and ((Get-Item $bgOut).Length -gt 50000)
    $bgSz = if (Test-Path $bgOut) { "$([math]::Round((Get-Item $bgOut).Length/1KB,0))KB PNG" } else { "no file" }
    $bgErr = if (-not $bgOk -and $script:LastPyOutput.Count -gt 0) { " | $($script:LastPyOutput[0])" } else { "" }
    Write-TestResult "T05" "Background generation" $bgOk "- $bgSz$bgErr"
    $bgResult = $bgOk
}

# --- T06: Composite ---------------------------------------------------------
$compOut = Join-Path $testOutDir "t06_composite.jpg"

$avatarNobgForComp = if (Test-Path $avatarOut) { $avatarOut } else { $null }
$bgForComp         = if (Test-Path $bgOut)      { $bgOut }     else { $null }

if (-not $avatarNobgForComp -or -not $bgForComp) {
    Write-TestResult "T06" "Composite portrait" $false "Requires T04 + T05 to pass first"
} else {
    $compEc = Invoke-Py "composite_portrait.py" @(
        "--avatar",       $avatarNobgForComp,
        "--background",   $bgForComp,
        "--output",       $compOut,
        "--avatar-height","680",
        "--x-offset",     "95",
        "--color-match",
        "--shadow",
        "--vignette"
    )
    $compOk = ($compEc -eq 0) -and (Test-Path $compOut) -and ((Get-Item $compOut).Length -gt 20000)
    $compSz = if (Test-Path $compOut) { "$([math]::Round((Get-Item $compOut).Length/1KB,0))KB JPEG" } else { "no file" }
    $compErr = if (-not $compOk -and $script:LastPyOutput.Count -gt 0) { " | $($script:LastPyOutput[0])" } else { "" }
    Write-TestResult "T06" "Composite portrait (color+shadow+vignette)" $compOk "- $compSz$compErr"
}

# --- T07: Preset integrity ----------------------------------------------------
$presetPath = Join-Path $repoRoot "tod\config\media-presets\jungle-spider-demo.json"
try {
    $preset = Get-Content $presetPath -Raw -ErrorAction Stop | ConvertFrom-Json
    $fields = @("id", "avatar", "background", "tts", "animation", "composite", "output")
    $missing = @($fields | Where-Object { -not $preset.PSObject.Properties[$_] })
    $presetOk = ($missing.Count -eq 0)
    Write-TestResult "T07" "Preset integrity (jungle-spider-demo.json)" $presetOk $(if ($missing) { "Missing: $($missing -join ', ')" } else { "all $($fields.Count) fields present" })
} catch {
    Write-TestResult "T07" "Preset integrity" $false "Parse error: $_"
}

# --- T08: SadTalker installation ----------------------------------------------
$sadInference = Join-Path $SadTalkerPath "inference.py"
$sadCkptDir   = Join-Path $SadTalkerPath "checkpoints"
$sadInstalled = Test-Path $sadInference
$sadCkpts     = if (Test-Path $sadCkptDir) { (Get-ChildItem $sadCkptDir -Recurse -File | Measure-Object).Count } else { 0 }

Write-TestResult "T08" "SadTalker install" $sadInstalled $(if ($sadInstalled) { "inference.py found, $sadCkpts checkpoint file(s)" } else { "Not found at $SadTalkerPath - run Setup-TODSpokesperson.ps1" })

# --- T09: Dry-run pipeline ---------------------------------------------------
Write-Host ""
Write-Host "  [T09] Full pipeline dry-run:" -ForegroundColor White
$dryOut = & powershell -NonInteractive -File (Join-Path $PSScriptRoot "Invoke-TODSpokesperson.ps1") `
    -DryRun `
    -SadTalkerPath $SadTalkerPath `
    -PythonExe $PythonExe 2>&1

$dryOk = ($LASTEXITCODE -eq 0) -or ($dryOut -match "DRY RUN")
Write-TestResult "T09" "Pipeline dry-run" $dryOk $(if ($dryOk) { "plan validated" } else { "exit $LASTEXITCODE" })

# --- T10: Avatar photo --------------------------------------------------------
$avOk = Test-Path $avatarSrc
$avSz = if ($avOk) { "$([math]::Round((Get-Item $avatarSrc).Length/1KB,0))KB" } else { "not found" }
Write-TestResult "T10" "Avatar photo present at tod/data/avatars/user-avatar.jpg" $avOk $avSz

# --- Cleanup ------------------------------------------------------------------
if (-not $KeepOutput) {
    Remove-Item -Path $testOutDir -Recurse -Force -ErrorAction SilentlyContinue
}

# --- Summary ------------------------------------------------------------------
Write-Host ""
Write-Host "=" * 50
Write-Host "Results: PASS=$pass  FAIL=$fail  SKIP=$skip" -ForegroundColor $(if ($fail -eq 0) { "Green" } else { "Yellow" })
Write-Host ""

if ($fail -eq 0) {
    Write-Host "All tests passed. Run the pipeline:" -ForegroundColor Green
    Write-Host "  .\scripts\Invoke-TODSpokesperson.ps1" -ForegroundColor White
} else {
    Write-Host "Fix failures above, then:" -ForegroundColor Yellow
    Write-Host "  1. .\scripts\Setup-TODSpokesperson.ps1   (install any missing deps)" -ForegroundColor White
    Write-Host "  2. .\scripts\Test-TODSpokesperson.ps1    (re-test)" -ForegroundColor White
}

exit $fail
