<#
.SYNOPSIS
    TOD Spokesperson pipeline with RunPod GPU offload for animation.

.DESCRIPTION
    Runs steps 1-4 locally (TTS, rembg extract, background generation, compositing),
    uploads composite + audio to RunPod, runs SadTalker remotely, downloads MP4,
    then finalizes output locally (optional smoothing + audio guard).

.PARAMETER Preset
    Path to media preset JSON.

.PARAMETER RunPodHost
    SSH host or IP for RunPod instance.

.PARAMETER RunPodUser
    SSH username for RunPod (default: root).

.PARAMETER RunPodPort
    SSH port (default: 22).

.PARAMETER RunPodKeyPath
    SSH private key path.

.PARAMETER RemoteRepoPath
    TOD repo path on RunPod (default: /workspace/TOD).

.PARAMETER RemoteSadTalkerPath
    SadTalker path on RunPod (default: /workspace/SadTalker).

.EXAMPLE
    .\scripts\Invoke-TODSpokesperson-RunPod.ps1 -Preset "tod/config/media-presets/gloria-cowell.json" -RunPodHost "1.2.3.4" -RunPodKeyPath "C:/keys/runpod"
#>
[CmdletBinding()]
param(
    [string]$Preset = "tod/config/media-presets/jungle-spider-demo.json",
    [string]$AvatarPath = "",
    [string]$Script = "",
    [string]$BackgroundPrompt = "",
    [string]$OutputPath = "",
    [string]$WorkDir = "",
    [string]$PythonExe = "python",
    [string]$RunPodHost = "",
    [string]$RunPodUser = "root",
    [int]$RunPodPort = 22,
    [string]$RunPodKeyPath = "",
    [string]$RemoteRepoPath = "/workspace/TOD",
    [string]$RemoteSadTalkerPath = "/workspace/SadTalker",
    [string]$RemotePythonExe = "/root/tod-venv/bin/python",
    [string]$EnvFile = ".env",
    [switch]$SkipSmoothing,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$engineRoot = Join-Path $PSScriptRoot "engines\spokesperson"
$script:RunPodSshPassword = ""

function Resolve-RepoPath([string]$RelOrAbs) {
    if ([System.IO.Path]::IsPathRooted($RelOrAbs)) { return $RelOrAbs }
    return Join-Path $repoRoot $RelOrAbs
}

function Write-Step([string]$Num, [string]$Label) {
    Write-Host ""
    Write-Host "[$Num/7] $Label" -ForegroundColor Cyan
}

function Get-DotEnvValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if (-not (Test-Path -Path $Path)) { return $null }

    $line = Get-Content -Path $Path | Where-Object {
        $_ -match "^\s*$Name\s*="
    } | Select-Object -First 1

    if (-not $line) { return $null }
    return ($line -replace "^\s*$Name\s*=\s*", "").Trim()
}

function Invoke-PythonEngine {
    param(
        [string]$Script,
        [string[]]$Arguments
    )

    $scriptPath = Join-Path $engineRoot $Script
    if (-not (Test-Path $scriptPath)) { throw "Engine not found: $scriptPath" }

    Write-Host "  > $PythonExe $Script $($Arguments -join ' ')" -ForegroundColor DarkGray

    if ($DryRun) {
        Write-Host "  [DRY RUN] skipped" -ForegroundColor Yellow
        return
    }

    & $PythonExe $scriptPath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Python engine '$Script' exited with code $LASTEXITCODE"
    }
}

function Get-SshBaseArgs {
    $sshOptions = New-Object System.Collections.Generic.List[string]
    $sshOptions.Add("-p") | Out-Null
    $sshOptions.Add([string]$RunPodPort) | Out-Null
    if (-not [string]::IsNullOrWhiteSpace($RunPodKeyPath)) {
        $sshOptions.Add("-i") | Out-Null
        $sshOptions.Add($RunPodKeyPath) | Out-Null
    }
    $sshOptions.Add("-o") | Out-Null
    $sshOptions.Add("StrictHostKeyChecking=accept-new") | Out-Null
    return $sshOptions
}

function Resolve-SshHostAlias {
    param([Parameter(Mandatory = $true)][string]$RemoteHost)

    if ($RemoteHost -match "^\d{1,3}(?:\.\d{1,3}){3}$" -or $RemoteHost -match "\.") {
        return $RemoteHost
    }

    $sshConfigPath = Join-Path $HOME ".ssh/config"
    if (-not (Test-Path -Path $sshConfigPath)) {
        return $RemoteHost
    }

    $matchedHost = $false
    foreach ($rawLine in Get-Content -Path $sshConfigPath) {
        $line = ([string]$rawLine).Trim()
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line.StartsWith("#")) { continue }

        if ($line -match "^(?i)Host\s+(.+)$") {
            $matchedHost = $false
            $tokens = $matches[1].Trim() -split "\s+"
            foreach ($token in $tokens) {
                if ([string]::Equals([string]$token, $RemoteHost, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $matchedHost = $true
                    break
                }
            }
            continue
        }

        if ($matchedHost -and $line -match "^(?i)HostName\s+(.+)$") {
            $candidate = $matches[1].Trim()
            if (-not [string]::IsNullOrWhiteSpace($candidate)) {
                return $candidate
            }
        }
    }

    return $RemoteHost
}

function New-RunPodCredential {
    if ([string]::IsNullOrWhiteSpace($script:RunPodSshPassword)) {
        return $null
    }
    $securePassword = ConvertTo-SecureString $script:RunPodSshPassword -AsPlainText -Force
    return New-Object System.Management.Automation.PSCredential ($RunPodUser, $securePassword)
}

function Test-RemotePathExists([string]$RemotePath) {
    if ($DryRun) {
        return $true
    }

    $checkCommand = "test -d '$RemotePath' && echo EXISTS || echo MISSING"

    if (-not [string]::IsNullOrWhiteSpace($script:RunPodSshPassword)) {
        if (-not (Get-Module -ListAvailable -Name Posh-SSH)) {
            throw "Posh-SSH is required for password auth. Install-Module -Name Posh-SSH -Scope CurrentUser"
        }

        Import-Module Posh-SSH -ErrorAction Stop | Out-Null
        $resolvedHost = Resolve-SshHostAlias -RemoteHost $RunPodHost
        $credential = New-RunPodCredential
        $session = $null
        try {
            $session = New-SSHSession -ComputerName $resolvedHost -Port $RunPodPort -Credential $credential -AcceptKey -ConnectionTimeout 30000
            $result = Invoke-SSHCommand -SessionId ([int]$session.SessionId) -Command $checkCommand -TimeOut 30
            return (($result.Output | Select-Object -First 1) -eq "EXISTS")
        }
        finally {
            if ($null -ne $session) {
                Remove-SSHSession -SessionId ([int]$session.SessionId) | Out-Null
            }
        }
    }

    $target = "{0}@{1}" -f $RunPodUser, $RunPodHost
    $sshArgs = Get-SshBaseArgs
    $fullArgs = @($sshArgs + @($target, $checkCommand))
    $output = & ssh @fullArgs
    return (($output | Select-Object -First 1) -eq "EXISTS")
}

function Invoke-RemoteCommand([string]$Command) {
    $target = "{0}@{1}" -f $RunPodUser, $RunPodHost
    $sshArgs = Get-SshBaseArgs
    $fullArgs = @($sshArgs + @($target, $Command))

    Write-Host "  > ssh $target '$Command'" -ForegroundColor DarkGray
    if ($DryRun) {
        Write-Host "  [DRY RUN] skipped" -ForegroundColor Yellow
        return
    }

    if (-not [string]::IsNullOrWhiteSpace($script:RunPodSshPassword)) {
        if (-not (Get-Module -ListAvailable -Name Posh-SSH)) {
            throw "Posh-SSH is required for password auth. Install-Module -Name Posh-SSH -Scope CurrentUser"
        }

        Import-Module Posh-SSH -ErrorAction Stop | Out-Null
        $resolvedHost = Resolve-SshHostAlias -RemoteHost $RunPodHost
        $credential = New-RunPodCredential
        $session = $null
        try {
            $session = New-SSHSession -ComputerName $resolvedHost -Port $RunPodPort -Credential $credential -AcceptKey -ConnectionTimeout 30000
            $result = Invoke-SSHCommand -SessionId ([int]$session.SessionId) -Command $Command -TimeOut 0
            if ($result.Output) {
                foreach ($line in $result.Output) {
                    if (-not [string]::IsNullOrWhiteSpace([string]$line)) {
                        Write-Host "    $line" -ForegroundColor DarkGray
                    }
                }
            }
            $exitStatus = if ($result.PSObject.Properties["ExitStatus"]) { [int]$result.ExitStatus } else { 0 }
            if ($exitStatus -ne 0) {
                throw "Remote SSH command failed with exit status $exitStatus"
            }
            return
        }
        finally {
            if ($null -ne $session) {
                Remove-SSHSession -SessionId ([int]$session.SessionId) | Out-Null
            }
        }
    }

    & ssh @fullArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Remote SSH command failed with code $LASTEXITCODE"
    }
}

function Copy-ToRemote([string]$LocalPath, [string]$RemotePath) {
    $target = "{0}@{1}:{2}" -f $RunPodUser, $RunPodHost, $RemotePath
    $scpArgs = Get-SshBaseArgs
    $scpArgs[0] = "-P"
    $fullArgs = @($scpArgs + @($LocalPath, $target))

    Write-Host "  > scp $LocalPath -> $target" -ForegroundColor DarkGray
    if ($DryRun) {
        Write-Host "  [DRY RUN] skipped" -ForegroundColor Yellow
        return
    }

    if (-not [string]::IsNullOrWhiteSpace($script:RunPodSshPassword)) {
        if (-not (Get-Module -ListAvailable -Name Posh-SSH)) {
            throw "Posh-SSH is required for password auth. Install-Module -Name Posh-SSH -Scope CurrentUser"
        }

        Import-Module Posh-SSH -ErrorAction Stop | Out-Null
        $resolvedHost = Resolve-SshHostAlias -RemoteHost $RunPodHost
        $credential = New-RunPodCredential
        $session = $null
        try {
            $session = New-SFTPSession -ComputerName $resolvedHost -Port $RunPodPort -Credential $credential -AcceptKey -ConnectionTimeout 30000
            $remoteDir = if ($RemotePath -match "^(.+)/[^/]+$") { $matches[1] } else { "." }
            Set-SFTPItem -SessionId ([int]$session.SessionId) -Path $LocalPath -Destination $remoteDir -Force -ErrorAction Stop | Out-Null
            return
        }
        finally {
            if ($null -ne $session) {
                Remove-SFTPSession -SessionId ([int]$session.SessionId) | Out-Null
            }
        }
    }

    & scp @fullArgs
    if ($LASTEXITCODE -ne 0) {
        throw "SCP upload failed with code $LASTEXITCODE"
    }
}

function Copy-FromRemote([string]$RemotePath, [string]$LocalPath) {
    $source = "{0}@{1}:{2}" -f $RunPodUser, $RunPodHost, $RemotePath
    $scpArgs = Get-SshBaseArgs
    $scpArgs[0] = "-P"
    $fullArgs = @($scpArgs + @($source, $LocalPath))

    Write-Host "  > scp $source -> $LocalPath" -ForegroundColor DarkGray
    if ($DryRun) {
        Write-Host "  [DRY RUN] skipped" -ForegroundColor Yellow
        return
    }

    if (-not [string]::IsNullOrWhiteSpace($script:RunPodSshPassword)) {
        if (-not (Get-Module -ListAvailable -Name Posh-SSH)) {
            throw "Posh-SSH is required for password auth. Install-Module -Name Posh-SSH -Scope CurrentUser"
        }

        Import-Module Posh-SSH -ErrorAction Stop | Out-Null
        $resolvedHost = Resolve-SshHostAlias -RemoteHost $RunPodHost
        $credential = New-RunPodCredential
        $session = $null
        try {
            $session = New-SFTPSession -ComputerName $resolvedHost -Port $RunPodPort -Credential $credential -AcceptKey -ConnectionTimeout 30000
            $localDir = Split-Path -Parent $LocalPath
            if (-not (Test-Path $localDir)) {
                New-Item -ItemType Directory -Path $localDir -Force | Out-Null
            }
            Get-SFTPItem -SessionId ([int]$session.SessionId) -Path $RemotePath -Destination $localDir -Force -ErrorAction Stop | Out-Null
            return
        }
        finally {
            if ($null -ne $session) {
                Remove-SFTPSession -SessionId ([int]$session.SessionId) | Out-Null
            }
        }
    }

    & scp @fullArgs
    if ($LASTEXITCODE -ne 0) {
        throw "SCP download failed with code $LASTEXITCODE"
    }
}

function Find-Tool([string[]]$Candidates) {
    foreach ($candidate in $Candidates) {
        $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
        if (Test-Path $candidate) { return $candidate }
    }
    return $null
}

# Apply .env defaults for RunPod connection.
$envPath = Resolve-RepoPath -RelOrAbs $EnvFile
if ([string]::IsNullOrWhiteSpace($RunPodHost)) {
    $RunPodHost = [string](Get-DotEnvValue -Path $envPath -Name "RUNPOD_SSH_HOST")
    if ([string]::IsNullOrWhiteSpace($RunPodHost)) {
        $RunPodHost = [string](Get-DotEnvValue -Path $envPath -Name "MIM_SSH_HOST")
        if (-not [string]::IsNullOrWhiteSpace($RunPodHost)) {
            Write-Host "WARN: RUNPOD_SSH_HOST not set; using MIM_SSH_HOST fallback from .env" -ForegroundColor Yellow
        }
    }
}
if ($RunPodUser -eq "root") {
    $envUser = [string](Get-DotEnvValue -Path $envPath -Name "RUNPOD_SSH_USER")
    if (-not [string]::IsNullOrWhiteSpace($envUser)) {
        $RunPodUser = $envUser
    } else {
        $mimUser = [string](Get-DotEnvValue -Path $envPath -Name "MIM_SSH_USER")
        if (-not [string]::IsNullOrWhiteSpace($mimUser)) { $RunPodUser = $mimUser }
    }
}
if ($RunPodPort -eq 22) {
    $envPort = [string](Get-DotEnvValue -Path $envPath -Name "RUNPOD_SSH_PORT")
    if (-not [string]::IsNullOrWhiteSpace($envPort)) {
        $RunPodPort = [int]$envPort
    } else {
        $mimPort = [string](Get-DotEnvValue -Path $envPath -Name "MIM_SSH_PORT")
        if (-not [string]::IsNullOrWhiteSpace($mimPort)) { $RunPodPort = [int]$mimPort }
    }
}
if ([string]::IsNullOrWhiteSpace($RunPodKeyPath)) {
    $RunPodKeyPath = [string](Get-DotEnvValue -Path $envPath -Name "RUNPOD_SSH_KEY")
}
$runpodEndpointId = [string](Get-DotEnvValue -Path $envPath -Name "RUNPOD_ENDPOINT_ID")
$runpodPassword = [string](Get-DotEnvValue -Path $envPath -Name "RUNPOD_SSH_PASSWORD")
if ([string]::IsNullOrWhiteSpace($runpodPassword) -and ($RunPodHost -eq [string](Get-DotEnvValue -Path $envPath -Name "MIM_SSH_HOST"))) {
    $runpodPassword = [string](Get-DotEnvValue -Path $envPath -Name "MIM_SSH_PASSWORD")
}
if (-not [string]::IsNullOrWhiteSpace($runpodPassword) -and $runpodPassword -ne "CHANGE_ME") {
    $script:RunPodSshPassword = $runpodPassword
}
$envRepoPath = [string](Get-DotEnvValue -Path $envPath -Name "RUNPOD_REPO_PATH")
if (-not [string]::IsNullOrWhiteSpace($envRepoPath)) { $RemoteRepoPath = $envRepoPath }
$envSadTalker = [string](Get-DotEnvValue -Path $envPath -Name "RUNPOD_SADTALKER_PATH")
if (-not [string]::IsNullOrWhiteSpace($envSadTalker)) { $RemoteSadTalkerPath = $envSadTalker }
$envRemotePython = [string](Get-DotEnvValue -Path $envPath -Name "RUNPOD_PYTHON_EXE")
if (-not [string]::IsNullOrWhiteSpace($envRemotePython)) { $RemotePythonExe = $envRemotePython }

if ([string]::IsNullOrWhiteSpace($RunPodHost)) {
    throw "RunPod host is required. Pass -RunPodHost or set RUNPOD_SSH_HOST in .env"
}
if (($RunPodHost -eq [string](Get-DotEnvValue -Path $envPath -Name "MIM_SSH_HOST")) -and -not [string]::IsNullOrWhiteSpace($runpodEndpointId)) {
    Write-Host "WARN: RUNPOD_ENDPOINT_ID is set, but this SSH-based launcher still needs RUNPOD_SSH_HOST." -ForegroundColor Yellow
    Write-Host "WARN: Endpoint IDs identify serverless endpoints or workers, not a direct SSH host for this workflow." -ForegroundColor Yellow
}
if ([string]::IsNullOrWhiteSpace($RunPodKeyPath) -and [string]::IsNullOrWhiteSpace($script:RunPodSshPassword)) {
    throw "RunPod SSH authentication is not configured. Set RUNPOD_SSH_KEY to your local private key path after adding the public key to the pod, or set RUNPOD_SSH_PASSWORD if your pod supports password auth."
}
if (-not [string]::IsNullOrWhiteSpace($RunPodKeyPath) -and -not (Test-Path (Resolve-RepoPath -RelOrAbs $RunPodKeyPath))) {
    throw "RunPod SSH key not found: $RunPodKeyPath"
}

$presetPath = Resolve-RepoPath -RelOrAbs $Preset
if (-not (Test-Path $presetPath)) { throw "Preset not found: $presetPath" }
$cfg = Get-Content $presetPath -Raw | ConvertFrom-Json

Write-Host ""
Write-Host "TOD Spokesperson Pipeline (RunPod Offload)" -ForegroundColor Green
Write-Host "Preset: $($cfg.id) - $($cfg.description)" -ForegroundColor Green
Write-Host ("RunPod: {0}@{1}:{2}" -f $RunPodUser, $RunPodHost, $RunPodPort) -ForegroundColor Green

$avatarSrc = if ($AvatarPath -ne "") { $AvatarPath } else { Resolve-RepoPath -RelOrAbs ([string]$cfg.avatar.source_path) }
$ttsScript = if ($Script -ne "") { $Script } else { [string]$cfg.tts.script }
$bgPrompt = if ($BackgroundPrompt -ne "") { $BackgroundPrompt } else { [string]$cfg.background.prompt }

if (-not (Test-Path $avatarSrc)) {
    if ($AvatarPath -eq "") {
        $avatarDir = Join-Path $repoRoot "tod\data\avatars"
        if (Test-Path $avatarDir) {
            $fallback = @(Get-ChildItem -Path (Join-Path $avatarDir "*") -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -in @('.jpg', '.jpeg', '.png', '.webp') } |
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
    throw "Avatar image not found: $avatarSrc`n`nSolution: place a portrait at tod/data/avatars/user-avatar.jpg, upload one in RunPod Studio, or pass -AvatarPath explicitly."
}

$jobId = "SPK-" + [guid]::NewGuid().ToString("N").Substring(0, 8).ToUpperInvariant()
if ($WorkDir -eq "") {
    $WorkDir = Join-Path $repoRoot "tod\out\spokesperson\$jobId"
}
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

if ($OutputPath -eq "") {
    $outDir = Join-Path $repoRoot "tod\out\spokesperson"
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    $outFile = [string]$cfg.output.filename -replace "\.mp4$", "-$jobId.mp4"
    $OutputPath = Join-Path $outDir $outFile
}

$paths = @{
    audio = Join-Path $WorkDir "tts_audio.wav"
    avatarBg = Join-Path $WorkDir "avatar_nobg.png"
    bg = Join-Path $WorkDir "background.png"
    composite = Join-Path $WorkDir "composited.png"
    animated = Join-Path $WorkDir "animated.mp4"
    output = $OutputPath
}

$remoteJobDir = "$RemoteRepoPath/tod/out/spokesperson/$jobId"
$remoteComposite = "$remoteJobDir/composited.png"
$remoteAudio = "$remoteJobDir/tts_audio.wav"
$remoteAnimated = "$remoteJobDir/animated.mp4"

Write-Host ""
Write-Host "Plan:" -ForegroundColor White
Write-Host "  Local workdir : $WorkDir"
Write-Host "  Remote workdir: $remoteJobDir"
Write-Host "  Output        : $OutputPath"

Write-Step "1" "Generating TTS audio ($($cfg.tts.voice))"
Invoke-PythonEngine "tts_edge.py" @(
    "--text", $ttsScript,
    "--voice", [string]$cfg.tts.voice,
    "--rate=$([string]$cfg.tts.rate)",
    "--pitch=$([string]$cfg.tts.pitch)",
    "--volume=$([string]$cfg.tts.volume)",
    "--output", $paths.audio
)

Write-Step "2" "Removing avatar background (rembg $($cfg.avatar.rembg_model))"
$rembgArgs = @(
    "--input", $avatarSrc,
    "--output", $paths.avatarBg,
    "--model", [string]$cfg.avatar.rembg_model
)
if ([bool]$cfg.avatar.post_process_alpha) { $rembgArgs += "--post-process" }
Invoke-PythonEngine "rembg_extract.py" $rembgArgs

Write-Step "3" "Generating background scene"
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

Write-Step "5" "Offloading SadTalker animation to RunPod"
if (-not (Test-RemotePathExists -RemotePath $RemoteRepoPath)) {
    throw "Remote repo path '$RemoteRepoPath' does not exist on $RunPodUser@$RunPodHost. This host does not look like the RunPod render box. Set RUNPOD_SSH_HOST in .env or pass -RunPodHost with the actual RunPod endpoint."
}
if (-not (Test-RemotePathExists -RemotePath $RemoteSadTalkerPath)) {
    throw "Remote SadTalker path '$RemoteSadTalkerPath' does not exist on $RunPodUser@$RunPodHost. Set RUNPOD_SADTALKER_PATH or point the launcher at the correct RunPod machine."
}
Invoke-RemoteCommand "mkdir -p '$remoteJobDir'"
Copy-ToRemote -LocalPath $paths.composite -RemotePath $remoteComposite
Copy-ToRemote -LocalPath $paths.audio -RemotePath $remoteAudio

$remoteAnimCmd = @(
    "cd '$RemoteRepoPath'",
    "$RemotePythonExe scripts/engines/spokesperson/animate_sadtalker.py --source-image '$remoteComposite' --driven-audio '$remoteAudio' --output-dir '$remoteJobDir' --output-name 'animated.mp4' --sadtalker-path '$RemoteSadTalkerPath' --python-exe '$RemotePythonExe' --enhancer '$([string]$cfg.animation.enhancer)' --size '$([string]$cfg.animation.size)' --preprocess '$([string]$cfg.animation.preprocess)' --pose-style '$([string]$cfg.animation.pose_style)' --expression-scale '$([string]$cfg.animation.expression_scale)' --still"
) -join " && "
Invoke-RemoteCommand $remoteAnimCmd

Write-Step "6" "Downloading animated MP4 from RunPod"
Copy-FromRemote -RemotePath $remoteAnimated -LocalPath $paths.animated

Write-Step "7" "Finalizing output"
$finalSourceMp4 = $paths.animated

if (-not $SkipSmoothing -and $cfg.output -and $cfg.output.PSObject.Properties["smoothing"] -and [bool]$cfg.output.smoothing.enabled) {
    $ffmpegExe = Find-Tool @(
        "ffmpeg",
        "C:\Program Files\FFmpeg\bin\ffmpeg.exe"
    )

    if ($ffmpegExe) {
        $smoothMp4 = Join-Path $WorkDir "animated_smooth.mp4"
        $targetFps = if ($cfg.output.smoothing.PSObject.Properties["target_fps"]) { [int]$cfg.output.smoothing.target_fps } else { 30 }
        $miMode = if ($cfg.output.smoothing.PSObject.Properties["mode"]) { [string]$cfg.output.smoothing.mode } else { "mci" }
        $mcMode = if ($cfg.output.smoothing.PSObject.Properties["mc_mode"]) { [string]$cfg.output.smoothing.mc_mode } else { "aobmc" }
        $meMode = if ($cfg.output.smoothing.PSObject.Properties["me_mode"]) { [string]$cfg.output.smoothing.me_mode } else { "bidir" }
        $vsbmc = if ($cfg.output.smoothing.PSObject.Properties["vsbmc"]) { [int]$cfg.output.smoothing.vsbmc } else { 1 }
        $crf = if ($cfg.output.smoothing.PSObject.Properties["crf"]) { [int]$cfg.output.smoothing.crf } else { 18 }
        $presetName = if ($cfg.output.smoothing.PSObject.Properties["preset"]) { [string]$cfg.output.smoothing.preset } else { "medium" }

        $vf = "minterpolate=fps=$targetFps`:mi_mode=$miMode`:mc_mode=$mcMode`:me_mode=$meMode`:vsbmc=$vsbmc"
        Write-Host "  Applying temporal smoothing with ffmpeg ($targetFps fps)..." -ForegroundColor DarkGray
        if (-not $DryRun) {
            & $ffmpegExe -y -i $paths.animated -vf $vf -c:v libx264 -preset $presetName -crf $crf -c:a copy $smoothMp4 | Out-Null
            if ($LASTEXITCODE -eq 0 -and (Test-Path $smoothMp4)) {
                $finalSourceMp4 = $smoothMp4
                Write-Host "  Smoothing complete: $smoothMp4" -ForegroundColor DarkGray
            } else {
                Write-Host "  WARN: smoothing failed; using original animation output" -ForegroundColor Yellow
            }
        }
    } else {
        Write-Host "  WARN: ffmpeg not found locally; skipping smoothing" -ForegroundColor Yellow
    }
}

if (-not $DryRun) {
    $probeExe = Find-Tool @(
        "ffprobe",
        "C:\Program Files\FFmpeg\bin\ffprobe.exe"
    )
    $ffmpegExe = Find-Tool @(
        "ffmpeg",
        "C:\Program Files\FFmpeg\bin\ffmpeg.exe"
    )

    if ($probeExe -and $ffmpegExe) {
        $hasAudio = & $probeExe -v error -select_streams a -show_entries stream=codec_type -of csv=p=0 $finalSourceMp4 2>$null
        if ([string]::IsNullOrWhiteSpace([string]$hasAudio)) {
            Write-Host "  Audio stream missing; remuxing TTS audio into final output..." -ForegroundColor Yellow
            $muxed = Join-Path $WorkDir "animated_with_audio.mp4"
            & $ffmpegExe -y -i $finalSourceMp4 -i $paths.audio -c:v copy -c:a aac -shortest $muxed | Out-Null
            if ($LASTEXITCODE -eq 0 -and (Test-Path $muxed)) {
                $finalSourceMp4 = $muxed
            } else {
                Write-Host "  WARN: audio remux failed; continuing with source file" -ForegroundColor Yellow
            }
        }
    }

    Copy-Item -Path $finalSourceMp4 -Destination $OutputPath -Force
    $sizeMb = [Math]::Round(((Get-Item $OutputPath).Length / 1MB), 2)
    Write-Host ""
    Write-Host "DONE output=$OutputPath size=${sizeMb}MB job=$jobId" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "[DRY RUN] complete" -ForegroundColor Yellow
}
