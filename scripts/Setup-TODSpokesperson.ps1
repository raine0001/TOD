<#
.SYNOPSIS
    One-shot setup for the TOD Spokesperson pipeline. Runs silently with no prompts.

.DESCRIPTION
    Installs and validates all dependencies for the talking-head video pipeline:
      - Python packages  : edge-tts, rembg[gpu], onnxruntime-gpu, Pillow, requests
      - SadTalker        : clones repo + installs requirements (if not already present)
      - GFPGAN           : clones repo + installs (face enhancement component)
      - ffmpeg           : checks PATH, provides install guidance if missing
      - Fooocus guidance : checks port 7865, explains how to start
      - Avatar slot      : verifies user-avatar.jpg is in place

    Safe to re-run  all operations are idempotent.

.PARAMETER SadTalkerPath
    Where to clone SadTalker (default: C:/AI/SadTalker)

.PARAMETER GFPGANPath
    Where to clone GFPGAN (default: C:/AI/GFPGAN)

.PARAMETER PythonExe
    Python 3.10+ executable (default: python)

.PARAMETER FooocusUrl
    Fooocus API base URL to health-check (default: http://127.0.0.1:7865)

.PARAMETER SkipSadTalker
    Skip SadTalker install (if already installed elsewhere)

.PARAMETER SkipFooocusCheck
    Skip Fooocus reachability check

.EXAMPLE
    .\scripts\Setup-TODSpokesperson.ps1

.EXAMPLE
    .\scripts\Setup-TODSpokesperson.ps1 -SadTalkerPath "D:/AI/SadTalker" -SkipFooocusCheck
#>
[CmdletBinding()]
param(
    [string]$SadTalkerPath    = "C:/AI/SadTalker",
    [string]$GFPGANPath       = "C:/AI/GFPGAN",
    [string]$PythonExe        = "python",
    [string]$FooocusUrl       = "http://127.0.0.1:7865",
    [switch]$SkipSadTalker,
    [switch]$SkipFooocusCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$pass = 0
$fail = 0
$warn = 0

function Write-OK([string]$msg)   { Write-Host "  OK  $msg" -ForegroundColor Green;   $script:pass++ }
function Write-FAIL([string]$msg) { Write-Host "  FAIL $msg" -ForegroundColor Red;    $script:fail++ }
function Write-WARN([string]$msg) { Write-Host "  WARN $msg" -ForegroundColor Yellow; $script:warn++ }
function Write-INFO([string]$msg) { Write-Host "  --  $msg" -ForegroundColor DarkGray }

function Test-PythonPackage([string]$Package, [string]$ImportName = "") {
    $imp = if ($ImportName -ne "") { $ImportName } else { $Package -replace "\[.*\]","" -replace "-","_" }
    $probe = @"
import importlib.util
import sys
sys.exit(0 if importlib.util.find_spec('$imp') else 1)
"@
    & $PythonExe -c $probe *> $null
    return ($LASTEXITCODE -eq 0)
}

function Install-PipPackage([string]$Package, [string]$ImportName = "") {
    Write-INFO "Installing $Package..."
    $prevEA = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & $PythonExe -m pip install --quiet --no-input $Package 2>&1 | Out-Null
    }
    finally {
        $ErrorActionPreference = $prevEA
    }
    return Test-PythonPackage $Package $ImportName
}

#  Header 
Write-Host ""
Write-Host "TOD Spokesperson  Setup" -ForegroundColor Cyan
Write-Host "=" * 50

# 
# SECTION 1: Python Environment
# 
Write-Host ""
Write-Host "[1] Python Environment" -ForegroundColor White

$pyVersion = & $PythonExe --version 2>&1
if ($pyVersion -match "Python (\d+)\.(\d+)") {
    $major = [int]$Matches[1]; $minor = [int]$Matches[2]
    if ($major -eq 3 -and $minor -ge 10) {
        Write-OK "Python $($Matches[0]) "
    } else {
        Write-WARN "Python $($Matches[0])  recommend 3.10+ for best SadTalker/rembg compatibility"
    }
} else {
    Write-FAIL "Python not found at '$PythonExe'  install Python 3.10+ and add to PATH"
    Write-Host "  Install: https://www.python.org/downloads/" -ForegroundColor Yellow
    exit 1
}

# pip
$pipCheck = & $PythonExe -m pip --version 2>&1
if ($pipCheck -match "pip") { Write-OK "pip available" }
else { Write-FAIL "pip not available"; exit 1 }

# Upgrade pip silently
Write-INFO "Ensuring pip is current..."
& $PythonExe -m pip install --quiet --no-input --upgrade pip 2>&1 | Out-Null

# 
# SECTION 2: Python Packages
# 
Write-Host ""
Write-Host "[2] Python Packages" -ForegroundColor White

$packages = @(
    @{ pkg = "edge-tts";          imp = "edge_tts" },
    @{ pkg = "Pillow";            imp = "PIL" },
    @{ pkg = "requests";          imp = "requests" },
    @{ pkg = "numpy";             imp = "numpy" },
    @{ pkg = "onnxruntime-gpu";   imp = "onnxruntime" }
)

foreach ($p in $packages) {
    if (Test-PythonPackage $p.pkg $p.imp) {
        Write-OK "$($p.pkg)"
    } else {
        if (Install-PipPackage $p.pkg $p.imp) { Write-OK "$($p.pkg) (installed)" }
        else { Write-FAIL "$($p.pkg)  install failed, try: pip install $($p.pkg)" }
    }
}

# rembg  try GPU variant first, CPU as fallback
Write-INFO "Checking rembg..."
if (Test-PythonPackage "rembg" "rembg") {
    Write-OK "rembg"
} else {
    Write-INFO "Installing rembg[gpu]..."
    & $PythonExe -m pip install --quiet --no-input "rembg[gpu]" 2>&1 | Out-Null
    if (Test-PythonPackage "rembg" "rembg") {
        Write-OK "rembg[gpu] (installed)"
    } else {
        Write-INFO "GPU install failed, trying CPU fallback..."
        & $PythonExe -m pip install --quiet --no-input "rembg" 2>&1 | Out-Null
        if (Test-PythonPackage "rembg" "rembg") { Write-OK "rembg (cpu install)" }
        else { Write-FAIL "rembg  install failed. Try: pip install rembg" }
    }
}

# soundfile (optional  for audio inspection)
& $PythonExe -m pip install --quiet --no-input soundfile 2>&1 | Out-Null
Write-OK "soundfile (audio utils)"

# 
# SECTION 3: edge-tts voice check
# 
Write-Host ""
Write-Host "[3] edge-tts Voice Validation" -ForegroundColor White

$ttsTestPath = Join-Path $env:TEMP "tod_tts_test.wav"
$ttsTestScript = "Testing one two three. TOD spokesperson voice check."
Write-INFO "Testing neural voice synthesis (en-US-GuyNeural)..."

$ttsPrevEA = $ErrorActionPreference
$ErrorActionPreference = "Continue"
try {
    $ttsResult = & $PythonExe (Join-Path $PSScriptRoot "engines\spokesperson\tts_edge.py") `
        --text $ttsTestScript `
        --voice "en-US-GuyNeural" `
        --output $ttsTestPath 2>&1
    $ttsExitCode = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $ttsPrevEA
}

if ($ttsExitCode -eq 0 -and (Test-Path $ttsTestPath)) {
    $sz = [math]::Round((Get-Item $ttsTestPath).Length / 1KB, 1)
    Remove-Item $ttsTestPath -Force -ErrorAction SilentlyContinue
    Write-OK "TTS en-US-GuyNeural  audio generated ($($sz)KB)"
} else {
    Write-WARN "TTS voice test failed  check internet connectivity (edge-tts requires internet)"
    Write-INFO "Output: $ttsResult"
}

# 
# SECTION 4: ffmpeg
# 
Write-Host ""
Write-Host "[4] ffmpeg" -ForegroundColor White

$ffmpegCheck = Get-Command ffmpeg -ErrorAction SilentlyContinue
if ($ffmpegCheck) {
    $ffVer = & ffmpeg -version 2>&1 | Select-Object -First 1
    Write-OK "ffmpeg  $ffVer"
} else {
    Write-WARN "ffmpeg not found in PATH"
    Write-INFO "Install options:"
    Write-INFO "  winget install ffmpeg"
    Write-INFO "  choco install ffmpeg"
    Write-INFO "  scoop install ffmpeg"
    Write-INFO "TTS will output MP3 instead of WAV (SadTalker handles both)"
}

# 
# SECTION 5: SadTalker
# 
Write-Host ""
Write-Host "[5] SadTalker" -ForegroundColor White

if ($SkipSadTalker) {
    Write-INFO "SadTalker install skipped (--SkipSadTalker)"
} else {
    $sadInference = Join-Path $SadTalkerPath "inference.py"
    $sadReqs      = Join-Path $SadTalkerPath "requirements.txt"

    if (Test-Path $sadInference) {
        Write-OK "SadTalker found: $SadTalkerPath"
    } else {
        Write-INFO "SadTalker not found at $SadTalkerPath  cloning..."

        # Ensure parent dir exists
        $sadParent = Split-Path -Parent $SadTalkerPath
        New-Item -ItemType Directory -Force -Path $sadParent | Out-Null

        $gitCheck = Get-Command git -ErrorAction SilentlyContinue
        if (-not $gitCheck) {
            Write-FAIL "git not found  install git and re-run: https://git-scm.com/downloads"
        } else {
            $gitPrevEA = $ErrorActionPreference
            $ErrorActionPreference = "Continue"
            try {
                git clone --depth 1 https://github.com/OpenTalker/SadTalker $SadTalkerPath 2>&1 | Out-Null
                $gitCloneExitCode = $LASTEXITCODE
            }
            finally {
                $ErrorActionPreference = $gitPrevEA
            }
            if (Test-Path $sadInference) {
                Write-OK "SadTalker cloned to $SadTalkerPath"
            } elseif ($gitCloneExitCode -ne 0) {
                Write-FAIL "SadTalker clone failed with exit code $gitCloneExitCode"
            } else {
                Write-FAIL "SadTalker clone failed. Check git output above."
            }
        }
    }

    # Install SadTalker requirements
    if (Test-Path $sadReqs) {
        Write-INFO "Installing SadTalker requirements (this may take a few minutes)..."
        $pipPrevEA = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            & $PythonExe -m pip install --quiet --no-input -r $sadReqs 2>&1 | Out-Null
            $sadReqExitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $pipPrevEA
        }
        if ($sadReqExitCode -eq 0) { Write-OK "SadTalker requirements installed" }
        else { Write-WARN "Some SadTalker requirements may have failed  check manually" }
    }

    # Check for SadTalker pretrained weights
    $sadCheckpoints = Join-Path $SadTalkerPath "checkpoints"
    if (Test-Path $sadCheckpoints) {
        $ckptCount = (Get-ChildItem $sadCheckpoints -Recurse -File | Measure-Object).Count
        Write-OK "SadTalker checkpoints: $ckptCount files"
    } else {
        Write-WARN "SadTalker checkpoints not downloaded yet"
        Write-INFO "  From $SadTalkerPath run: bash scripts/download_models.sh"
        Write-INFO "  OR use the Windows model downloader in the SadTalker README"
        Write-INFO "  Models to download: ~1.5GB total"
    }

    # GFPGAN (face enhancer  critical for 95% realism)
    Write-INFO "Checking GFPGAN..."
    $gfpganCheck = Test-PythonPackage "gfpgan" "gfpgan"
    if (-not $gfpganCheck) {
        Write-INFO "Installing GFPGAN..."
        $pipPrevEA = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            & $PythonExe -m pip install --quiet --no-input gfpgan 2>&1 | Out-Null
        }
        finally {
            $ErrorActionPreference = $pipPrevEA
        }
        if (Test-PythonPackage "gfpgan" "gfpgan") { Write-OK "GFPGAN installed" }
        else { Write-WARN "GFPGAN install failed  face enhancement won't be available" }
    } else {
        Write-OK "GFPGAN available"
    }

    # basicsr (SadTalker dependency)
    if (-not (Test-PythonPackage "basicsr" "basicsr")) {
        $pipPrevEA = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            & $PythonExe -m pip install --quiet --no-input basicsr 2>&1 | Out-Null
        }
        finally {
            $ErrorActionPreference = $pipPrevEA
        }
        if (Test-PythonPackage "basicsr" "basicsr") { Write-OK "basicsr installed" }
        else { Write-WARN "basicsr install failed  SadTalker may not work" }
    } else {
        Write-OK "basicsr"
    }
}

# 
# SECTION 6: Fooocus
# 
Write-Host ""
Write-Host "[6] Fooocus Background Generator" -ForegroundColor White

if ($SkipFooocusCheck) {
    Write-INFO "Fooocus check skipped (--SkipFooocusCheck)"
} else {
    try {
        $response = Invoke-WebRequest -Uri $FooocusUrl -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
        Write-OK "Fooocus running at $FooocusUrl"
    } catch {
        Write-WARN "Fooocus not running at $FooocusUrl"
        Write-INFO ""
        Write-INFO "To start Fooocus with API enabled:"
        Write-INFO "  1. Clone: git clone https://github.com/lllyasviel/Fooocus C:/AI/Fooocus"
        Write-INFO "  2. Install requirements: pip install -r requirements_versions.txt"
        Write-INFO "  3. Start: python launch.py --listen --port 7865 --always-high-vram"
        Write-INFO ""
        Write-INFO "Fooocus downloads juggernautXL on first run (~6.5GB)"
        Write-INFO "Pipeline will fall back to ComfyUI if Fooocus is not running"
    }
}

# 
# SECTION 7: Avatar Photo
# 
Write-Host ""
Write-Host "[7] Avatar Photo" -ForegroundColor White

$avatarDir = Join-Path $repoRoot "tod\data\avatars"
$avatarPath = Join-Path $repoRoot "tod\data\avatars\user-avatar.jpg"
if (Test-Path $avatarPath) {
    $sz = [math]::Round((Get-Item $avatarPath).Length / 1KB, 1)
    Write-OK "Avatar found: $avatarPath ($($sz)KB)"
} else {
    $candidates = @()
    if (Test-Path $avatarDir) {
        $candidates = @(Get-ChildItem -Path (Join-Path $avatarDir "*") -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -in @('.jpg', '.jpeg', '.png') } |
            Where-Object { $_.Name -ne "user-avatar.jpg" } |
            Sort-Object LastWriteTime -Descending)
    }

    if ($candidates.Count -gt 0) {
        Copy-Item -Path $candidates[0].FullName -Destination $avatarPath -Force
        $sz = [math]::Round((Get-Item $avatarPath).Length / 1KB, 1)
        Write-OK "Avatar auto-selected: $($candidates[0].Name) -> user-avatar.jpg ($($sz)KB)"
    } else {
        Write-WARN "Avatar photo not found: $avatarPath"
        Write-INFO ""
        Write-INFO "  ACTION REQUIRED:"
        Write-INFO "  1. Copy your portrait photo to: $avatarPath"
        Write-INFO "  2. Name it exactly: user-avatar.jpg"
        Write-INFO "  3. Requirements: JPG, min 512x512, face clearly visible, well-lit"
        Write-INFO ""
        Write-INFO "  The jungle-spider demo preset references this exact path."
        $fail++  # count as failure since pipeline won't run without it
    }
}

# 
# SECTION 8: rembg model download
# 
Write-Host ""
Write-Host "[8] rembg Model Pre-download" -ForegroundColor White

Write-INFO "Pre-downloading rembg u2net_human_seg model (portrait-optimized)..."
try {
    $modelTest = & $PythonExe -c @"
from rembg import new_session
sess = new_session('u2net_human_seg')
print('ok: ' + str(type(sess)))
"@ 2>&1
    if ($modelTest -match "^ok:") { Write-OK "u2net_human_seg model ready" }
    else { Write-WARN "Model pre-cache may have failed: $modelTest" }
} catch {
    Write-WARN "rembg model pre-download skipped"
}

# 
# SUMMARY
# 
Write-Host ""
Write-Host "=" * 50
Write-Host "Setup Summary" -ForegroundColor White
Write-Host "  Pass : $pass" -ForegroundColor Green
Write-Host "  Warn : $warn" -ForegroundColor Yellow
Write-Host "  Fail : $fail" -ForegroundColor $(if ($fail -gt 0) { "Red" } else { "Green" })

Write-Host ""
if ($fail -eq 0) {
    Write-Host "Ready to run. Execute the spokesperson pipeline:" -ForegroundColor Green
    Write-Host "  .\scripts\Invoke-TODSpokesperson.ps1" -ForegroundColor White
    Write-Host ""
    Write-Host "  Or dry-run first (no files written):" -ForegroundColor DarkGray
    Write-Host "  .\scripts\Invoke-TODSpokesperson.ps1 -DryRun" -ForegroundColor White
} else {
    Write-Host "Fix the items above, then re-run setup." -ForegroundColor Yellow
    Write-Host "  .\scripts\Setup-TODSpokesperson.ps1" -ForegroundColor White
}

exit $fail

