param(
    [int]$Port = 8878,
    [switch]$NoAutoOpen
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$uiPath = Join-Path $repoRoot "ui\runpod-studio.html"
$envPath = Join-Path $repoRoot ".env"
$endpointScript = Join-Path $PSScriptRoot "Set-TODRunPodEndpoint.ps1"
$renderScript = Join-Path $PSScriptRoot "Invoke-TODRunPodStudioRender.ps1"
$statusPath = Join-Path $repoRoot "tod\out\runpod-studio\status.json"
$logPath = Join-Path $repoRoot "tod\out\runpod-studio\render.log"
$avatarUploadDir = Join-Path $repoRoot "tod\data\avatars\uploads"

if (-not (Test-Path $uiPath)) { throw "UI file not found: $uiPath" }
if (-not (Test-Path $endpointScript)) { throw "Endpoint updater not found: $endpointScript" }
if (-not (Test-Path $renderScript)) { throw "Render worker not found: $renderScript" }

function Get-DotEnvValue {
    param([string]$Name)

    if (-not (Test-Path $envPath)) { return $null }
    $line = Get-Content -Path $envPath | Where-Object { $_ -match "^\s*$([regex]::Escape($Name))\s*=" } | Select-Object -First 1
    if (-not $line) { return $null }
    return ($line -replace "^\s*$([regex]::Escape($Name))\s*=\s*", "").Trim()
}

function Read-BodyText {
    param([System.Net.HttpListenerRequest]$Request)
    $reader = New-Object System.IO.StreamReader($Request.InputStream, $Request.ContentEncoding)
    try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
}

function Get-RelativeRepoPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $fullRoot = [System.IO.Path]::GetFullPath($repoRoot)
    if ($fullPath.StartsWith($fullRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        $relativePath = $fullPath.Substring($fullRoot.Length) -replace '^[\\/]+', ''
        return $relativePath -replace '\\', '/'
    }
    return $fullPath
}

function Test-PortAvailable {
    param([int]$CandidatePort)

    $listener = $null
    try {
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $CandidatePort)
        $listener.Start()
        return $true
    }
    catch {
        return $false
    }
    finally {
        if ($null -ne $listener) {
            $listener.Stop()
        }
    }
}

function Get-AvailablePort {
    param([int]$PreferredPort)

    foreach ($candidate in $PreferredPort..($PreferredPort + 10)) {
        if (Test-PortAvailable -CandidatePort $candidate) {
            return $candidate
        }
    }

    throw "No free local port found in range $PreferredPort-$($PreferredPort + 10)"
}

function Save-AvatarUpload {
    param([pscustomobject]$Payload)

    if (-not $Payload.file_name) {
        throw "Upload payload is missing file_name"
    }
    if (-not $Payload.content_base64) {
        throw "Upload payload is missing content_base64"
    }

    $safeName = [System.IO.Path]::GetFileName([string]$Payload.file_name)
    if ([string]::IsNullOrWhiteSpace($safeName)) {
        throw "Uploaded file name is invalid"
    }

    $extension = [System.IO.Path]::GetExtension($safeName)
    if ($extension -notin @('.png', '.jpg', '.jpeg', '.webp')) {
        throw "Only .png, .jpg, .jpeg, and .webp avatar uploads are supported"
    }

    New-Item -ItemType Directory -Force -Path $avatarUploadDir | Out-Null
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($safeName)
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $targetName = "{0}-{1}{2}" -f $baseName, $timestamp, $extension.ToLowerInvariant()
    $targetPath = Join-Path $avatarUploadDir $targetName
    $bytes = [Convert]::FromBase64String([string]$Payload.content_base64)
    [System.IO.File]::WriteAllBytes($targetPath, $bytes)

    return [pscustomobject]@{
        absolute_path = $targetPath
        relative_path = (Get-RelativeRepoPath -Path $targetPath)
    }
}

function Write-StudioFiles {
    param(
        [hashtable]$Status,
        [string[]]$LogLines
    )

    $statusDir = Split-Path -Parent $statusPath
    if ($statusDir) {
        New-Item -ItemType Directory -Force -Path $statusDir | Out-Null
    }

    $logDir = Split-Path -Parent $logPath
    if ($logDir) {
        New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    }

    $Status | ConvertTo-Json -Depth 8 | Set-Content -Path $statusPath -Encoding UTF8
    @($LogLines) | Set-Content -Path $logPath -Encoding UTF8
}

function Write-JsonResponse {
    param(
        [System.Net.HttpListenerResponse]$Response,
        [int]$StatusCode,
        [object]$Payload
    )

    $json = $Payload | ConvertTo-Json -Depth 8
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $Response.StatusCode = $StatusCode
    $Response.ContentType = "application/json; charset=utf-8"
    $Response.Headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
    $Response.Headers["Pragma"] = "no-cache"
    $Response.Headers["Expires"] = "0"
    $Response.ContentLength64 = $bytes.LongLength
    $Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Response.OutputStream.Close()
    $Response.Close()
}

function Write-TextResponse {
    param(
        [System.Net.HttpListenerResponse]$Response,
        [int]$StatusCode,
        [string]$Content,
        [string]$ContentType
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Content)
    $Response.StatusCode = $StatusCode
    $Response.ContentType = $ContentType
    $Response.Headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
    $Response.Headers["Pragma"] = "no-cache"
    $Response.Headers["Expires"] = "0"
    $Response.ContentLength64 = $bytes.LongLength
    $Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Response.OutputStream.Close()
    $Response.Close()
}

function Get-StudioStatus {
    $status = if (Test-Path $statusPath) {
        Get-Content -Path $statusPath -Raw | ConvertFrom-Json
    } else {
        [pscustomobject]@{
            state = "idle"
            preset = "tod/config/media-presets/gloria-cowell.json"
            avatar_path = $null
            script = $null
            background_prompt = $null
            started_at = $null
            finished_at = $null
            pid = $null
            output = $null
            error = $null
        }
    }

    $isRunning = $false
    if ($status.pid) {
        $proc = Get-Process -Id ([int]$status.pid) -ErrorAction SilentlyContinue
        $isRunning = ($null -ne $proc)
    }

    if ($status.state -eq "running" -and -not $isRunning) {
        $status.state = "unknown"
    }

    $logTail = @(if (Test-Path $logPath) { Get-Content -Path $logPath -Tail 80 -ErrorAction SilentlyContinue })
    $logPayload = if (@($logTail).Length -gt 0) { @($logTail) } else { @("") }
    return [pscustomobject]@{
        config = [pscustomobject]@{
            host = (Get-DotEnvValue "RUNPOD_SSH_HOST")
            port = (Get-DotEnvValue "RUNPOD_SSH_PORT")
            user = (Get-DotEnvValue "RUNPOD_SSH_USER")
            python = (Get-DotEnvValue "RUNPOD_PYTHON_EXE")
            repoPath = (Get-DotEnvValue "RUNPOD_REPO_PATH")
            sadTalkerPath = (Get-DotEnvValue "RUNPOD_SADTALKER_PATH")
        }
        status = $status
        log = $logPayload
    }
}

$resolvedPort = Get-AvailablePort -PreferredPort $Port
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://localhost:$resolvedPort/")
$listener.Start()

$url = "http://localhost:$resolvedPort/"
Write-Host "RunPod Studio listening at $url" -ForegroundColor Green
if ($resolvedPort -ne $Port) {
    Write-Host "Requested port $Port was unavailable. Using $resolvedPort instead." -ForegroundColor Yellow
}
Write-Host "Press Ctrl+C to stop." -ForegroundColor DarkGray
if (-not $NoAutoOpen) {
    Start-Process $url | Out-Null
}

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response
        $path = $request.Url.AbsolutePath

        try {
            switch ($path) {
                "/" {
                    Write-TextResponse -Response $response -StatusCode 200 -Content (Get-Content -Path $uiPath -Raw) -ContentType "text/html; charset=utf-8"
                    continue
                }
                "/api/status" {
                    Write-JsonResponse -Response $response -StatusCode 200 -Payload (Get-StudioStatus)
                    continue
                }
                "/api/endpoint" {
                    if ($request.HttpMethod -ne "POST") {
                        Write-JsonResponse -Response $response -StatusCode 405 -Payload @{ ok = $false; error = "Method not allowed" }
                        continue
                    }

                    $payload = Read-BodyText -Request $request | ConvertFrom-Json
                    & $endpointScript -RunPodHost ([string]$payload.host) -Port ([int]$payload.port) -User ([string]$payload.user)
                    Write-JsonResponse -Response $response -StatusCode 200 -Payload @{ ok = $true; status = (Get-StudioStatus) }
                    continue
                }
                "/api/upload-avatar" {
                    if ($request.HttpMethod -ne "POST") {
                        Write-JsonResponse -Response $response -StatusCode 405 -Payload @{ ok = $false; error = "Method not allowed" }
                        continue
                    }

                    $payload = Read-BodyText -Request $request | ConvertFrom-Json
                    $saved = Save-AvatarUpload -Payload $payload
                    Write-JsonResponse -Response $response -StatusCode 200 -Payload @{ ok = $true; avatar = $saved }
                    continue
                }
                "/api/render" {
                    if ($request.HttpMethod -ne "POST") {
                        Write-JsonResponse -Response $response -StatusCode 405 -Payload @{ ok = $false; error = "Method not allowed" }
                        continue
                    }

                    $current = Get-StudioStatus
                    if ($current.status.state -eq "running") {
                        Write-JsonResponse -Response $response -StatusCode 409 -Payload @{ ok = $false; error = "A render is already running." }
                        continue
                    }

                    $payload = Read-BodyText -Request $request | ConvertFrom-Json
                    $preset = if ($payload.preset) { [string]$payload.preset } else { "tod/config/media-presets/gloria-cowell.json" }
                    $avatarPath = if ($payload.avatarPath) { [string]$payload.avatarPath } else { "" }
                    $script = if ($payload.script) { [string]$payload.script } else { "" }
                    $backgroundPrompt = if ($payload.backgroundPrompt) { [string]$payload.backgroundPrompt } else { "" }
                    $requestedAt = (Get-Date).ToUniversalTime().ToString("o")

                    $startingStatus = @{
                        state = "starting"
                        preset = $preset
                        avatar_path = $avatarPath
                        script = $script
                        background_prompt = $backgroundPrompt
                        started_at = $requestedAt
                        finished_at = $null
                        pid = $null
                        output = $null
                        error = $null
                    }
                    $startingLog = @(
                        "[{0}] Render request accepted" -f $requestedAt,
                        "[{0}] Waiting for background worker to attach" -f $requestedAt
                    )
                    Write-StudioFiles -Status $startingStatus -LogLines $startingLog

                    $args = @(
                        "-NoProfile",
                        "-ExecutionPolicy", "Bypass",
                        "-File", $renderScript,
                        "-Preset", $preset,
                        "-StatusPath", $statusPath,
                        "-LogPath", $logPath
                    )
                    if (-not [string]::IsNullOrWhiteSpace($avatarPath)) {
                        $args += @("-AvatarPath", $avatarPath)
                    }
                    if (-not [string]::IsNullOrWhiteSpace($script)) {
                        $args += @("-Script", $script)
                    }
                    if (-not [string]::IsNullOrWhiteSpace($backgroundPrompt)) {
                        $args += @("-BackgroundPrompt", $backgroundPrompt)
                    }
                    $proc = Start-Process -FilePath "powershell" -ArgumentList $args -PassThru -WindowStyle Hidden

                    $startingStatus.pid = $proc.Id
                    Write-StudioFiles -Status $startingStatus -LogLines ($startingLog + ("[{0}] Worker process started (PID {1})" -f ((Get-Date).ToUniversalTime().ToString("o")), $proc.Id))

                    Start-Sleep -Milliseconds 300
                    Write-JsonResponse -Response $response -StatusCode 202 -Payload @{ ok = $true; pid = $proc.Id; status = (Get-StudioStatus) }
                    continue
                }
                default {
                    Write-JsonResponse -Response $response -StatusCode 404 -Payload @{ ok = $false; error = "Not found" }
                    continue
                }
            }
        }
        catch {
            Write-JsonResponse -Response $response -StatusCode 500 -Payload @{ ok = $false; error = [string]$_.Exception.Message }
        }
    }
}
finally {
    $listener.Stop()
    $listener.Close()
}