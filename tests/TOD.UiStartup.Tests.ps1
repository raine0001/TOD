Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$startScript = Join-Path $repoRoot 'scripts/Start-TOD-UI.ps1'
$startupDiagnosticPath = Join-Path $repoRoot 'tod/out/tod-ui-startup.latest.json'

function Get-LanAdvertiseHostForTest {
    try {
        $addresses = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop | Where-Object {
            $_.IPAddress -and
            $_.IPAddress -ne '127.0.0.1' -and
            $_.IPAddress -notlike '169.254.*'
        })

        $preferred = @($addresses | Where-Object {
            $_.IPAddress -like '192.168.*' -or
            [string]$_.InterfaceAlias -match 'Ethernet|Wi-Fi'
        } | Select-Object -First 1)

        if (@($preferred).Count -gt 0) {
            return [string]$preferred[0].IPAddress
        }

        $fallback = @($addresses | Select-Object -First 1)
        if (@($fallback).Count -gt 0) {
            return [string]$fallback[0].IPAddress
        }
    }
    catch {
    }

    return ''
}

function Backup-PathContent {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    return [pscustomobject]@{
        path = $PathValue
        exists = (Test-Path -Path $PathValue -PathType Leaf)
        content = if (Test-Path -Path $PathValue -PathType Leaf) { [string](Get-Content -Path $PathValue -Raw) } else { '' }
    }
}

function Restore-PathContent {
    param([Parameter(Mandatory = $true)]$Backup)

    if ([bool]$Backup.exists) {
        $directory = Split-Path -Parent ([string]$Backup.path)
        if (-not (Test-Path -Path $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }

        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText([string]$Backup.path, [string]$Backup.content, $utf8NoBom)
    }
    elseif (Test-Path -Path ([string]$Backup.path)) {
        Remove-Item -Path ([string]$Backup.path) -Force
    }
}

function Get-FileContentOrEmpty {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if (Test-Path -Path $PathValue -PathType Leaf) {
        return [string](Get-Content -Path $PathValue -Raw)
    }

    return ''
}

function Wait-TodUrlReady {
    param(
        [Parameter(Mandatory = $true)][string]$BaseUrl,
        [int]$TimeoutSeconds = 20
    )

    $deadline = (Get-Date).ToUniversalTime().AddSeconds($TimeoutSeconds)
    while ((Get-Date).ToUniversalTime() -lt $deadline) {
        try {
            $response = Invoke-WebRequest -UseBasicParsing -Uri (([string]$BaseUrl).TrimEnd('/') + '/api/project-status?readiness=1') -TimeoutSec 3
            if ($response.StatusCode -eq 200) {
                return $true
            }
        }
        catch {
        }
        Start-Sleep -Milliseconds 400
    }

    return $false
}

function Stop-TodUiDisposableProcesses {
    param([Parameter(Mandatory = $true)][int]$Port)

    $internalPort = $Port + 10000
    $processes = @(Get-CimInstance Win32_Process | Where-Object {
        ($_.Name -match '^powershell(\.exe)?$' -and $_.CommandLine -and $_.CommandLine -like '*Start-TOD-UI.ps1*' -and $_.CommandLine -like ("*-Port {0}*" -f $Port)) -or
        ($_.Name -match 'python(\.exe)?' -and $_.CommandLine -and $_.CommandLine -like '*tod_ui_lan_proxy.py*' -and ($_.CommandLine -like ("*--listen-port {0}*" -f $Port) -or $_.CommandLine -like ("*--target-port {0}*" -f $internalPort)))
    })

    foreach ($process in $processes) {
        try {
            Stop-Process -Id ([int]$process.ProcessId) -Force -ErrorAction SilentlyContinue
        }
        catch {
        }
    }
}

function Start-StaleTodUiProxyForTest {
    param(
        [Parameter(Mandatory = $true)][int]$Port,
        [Parameter(Mandatory = $true)][int]$TargetPort
    )

    $pythonPath = if (Test-Path (Join-Path $repoRoot '.venv/Scripts/python.exe')) { Join-Path $repoRoot '.venv/Scripts/python.exe' } else { 'python' }
    $proxyScript = Join-Path $repoRoot 'scripts/tod_ui_lan_proxy.py'
    return (Start-Process -FilePath $pythonPath -ArgumentList @($proxyScript, '--listen-host', '0.0.0.0', '--listen-port', [string]$Port, '--target-host', '127.0.0.1', '--target-port', [string]$TargetPort) -WorkingDirectory $repoRoot -PassThru -WindowStyle Hidden)
}

Describe 'TOD UI startup hardening' {
    It 'reuses a healthy UI instance on repeated launch without changing the requested port and advertises the LAN URL when available' {
        $port = 8864
        $advertiseHost = Get-LanAdvertiseHostForTest
        $startupBackup = Backup-PathContent -PathValue $startupDiagnosticPath
        $process = $null
        $stdoutPath = Join-Path $repoRoot 'tod/out/ui-startup-test.stdout.log'
        $stderrPath = Join-Path $repoRoot 'tod/out/ui-startup-test.stderr.log'

        try {
            Stop-TodUiDisposableProcesses -Port $port
            Remove-Item -Path $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue

            $argumentList = @(
                '-NoProfile',
                '-ExecutionPolicy', 'Bypass',
                '-File', $startScript,
                '-Port', $port,
                '-NoAutoOpen'
            )
            if (-not [string]::IsNullOrWhiteSpace([string]$advertiseHost)) {
                $argumentList += @('-AdvertiseHost', [string]$advertiseHost)
            }

            $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $argumentList -WorkingDirectory $repoRoot -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath

            $localhostReady = Wait-TodUrlReady -BaseUrl ("http://localhost:{0}" -f $port) -TimeoutSeconds 25
            if (-not $localhostReady) {
                $process.Refresh()
                throw ("TOD UI localhost endpoint did not become ready. HasExited={0}; ExitCode={1}; stdout={2}; stderr={3}" -f $process.HasExited, $(if ($process.HasExited) { $process.ExitCode } else { 'running' }), (Get-FileContentOrEmpty -PathValue $stdoutPath), (Get-FileContentOrEmpty -PathValue $stderrPath))
            }
            $localhostReady | Should Be $true

            if (-not [string]::IsNullOrWhiteSpace([string]$advertiseHost)) {
                (Wait-TodUrlReady -BaseUrl ("http://{0}:{1}" -f $advertiseHost, $port) -TimeoutSeconds 10) | Should Be $true
            }

            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $startScript -Port $port -NoAutoOpen @($(if (-not [string]::IsNullOrWhiteSpace([string]$advertiseHost)) { @('-AdvertiseHost', [string]$advertiseHost) } else { @() })) | Out-Null
            $LASTEXITCODE | Should Be 0

            $doc = Get-Content -Path $startupDiagnosticPath -Raw | ConvertFrom-Json
            [bool]$doc.ok | Should Be $true
            [string]$doc.status | Should Be 'already_running'
            [int]$doc.port | Should Be $port
            (@($doc.listen_hosts) -contains 'localhost') | Should Be $true
            if (-not [string]::IsNullOrWhiteSpace([string]$advertiseHost)) {
                [string]$doc.advertise_host | Should Be $advertiseHost
                [string]$doc.advertise_url | Should Be ("http://{0}:{1}" -f $advertiseHost, $port)
                (@($doc.listen_hosts) -contains [string]$advertiseHost) | Should Be $true
            }
        }
        finally {
            if ($process -and -not $process.HasExited) {
                try {
                    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                }
                catch {
                }
            }
            Stop-TodUiDisposableProcesses -Port $port
            Restore-PathContent -Backup $startupBackup
        }
    }

    It 'reclaims a stale TOD LAN proxy that occupies the requested public port' {
        $port = 8866
        $advertiseHost = Get-LanAdvertiseHostForTest
        if ([string]::IsNullOrWhiteSpace([string]$advertiseHost)) {
            $advertiseHost = 'localhost'
        }

        $startupBackup = Backup-PathContent -PathValue $startupDiagnosticPath
        $proxyProcess = $null
        $process = $null
        $stdoutPath = Join-Path $repoRoot 'tod/out/ui-startup-proxy-reclaim.stdout.log'
        $stderrPath = Join-Path $repoRoot 'tod/out/ui-startup-proxy-reclaim.stderr.log'

        try {
            Stop-TodUiDisposableProcesses -Port $port
            Remove-Item -Path $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue

            $proxyProcess = Start-StaleTodUiProxyForTest -Port $port -TargetPort ($port + 10000)
            Start-Sleep -Seconds 1

            $argumentList = @(
                '-NoProfile',
                '-ExecutionPolicy', 'Bypass',
                '-File', $startScript,
                '-Port', $port,
                '-NoAutoOpen',
                '-AdvertiseHost', [string]$advertiseHost
            )

            $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $argumentList -WorkingDirectory $repoRoot -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath

            $localhostReady = Wait-TodUrlReady -BaseUrl ("http://localhost:{0}" -f $port) -TimeoutSeconds 25
            if (-not $localhostReady) {
                $process.Refresh()
                throw ("TOD UI localhost endpoint did not become ready after stale proxy reclaim. HasExited={0}; ExitCode={1}; stdout={2}; stderr={3}" -f $process.HasExited, $(if ($process.HasExited) { $process.ExitCode } else { 'running' }), (Get-FileContentOrEmpty -PathValue $stdoutPath), (Get-FileContentOrEmpty -PathValue $stderrPath))
            }

            $doc = Get-Content -Path $startupDiagnosticPath -Raw | ConvertFrom-Json
            [bool]$doc.ok | Should Be $true
            [string]$doc.status | Should Be 'started'
            [int]$doc.port | Should Be $port
            [string]$doc.advertise_url | Should Be ("http://{0}:{1}" -f $advertiseHost, $port)
        }
        finally {
            if ($process -and -not $process.HasExited) {
                try {
                    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                }
                catch {
                }
            }
            if ($proxyProcess -and -not $proxyProcess.HasExited) {
                try {
                    Stop-Process -Id $proxyProcess.Id -Force -ErrorAction SilentlyContinue
                }
                catch {
                }
            }
            Stop-TodUiDisposableProcesses -Port $port
            Restore-PathContent -Backup $startupBackup
        }
    }
}
