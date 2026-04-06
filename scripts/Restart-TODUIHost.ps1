param(
    [int]$Port = 8844,
    [int]$ReadyTimeoutSeconds = 30,
    [string]$AdvertiseHost = ''
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$startScript = Join-Path $PSScriptRoot 'Start-TOD-UI.ps1'
$startupDiagnosticPath = Join-Path $repoRoot 'tod/out/tod-ui-startup.latest.json'

if (-not (Test-Path -Path $startScript)) {
    throw "Start-TOD-UI.ps1 was not found at $startScript"
}

$targetSuffix = [System.IO.Path]::GetFileName($startScript)
$processes = Get-CimInstance Win32_Process | Where-Object {
    $_.Name -match '^powershell(\.exe)?$' -and
    $_.CommandLine -and
    $_.CommandLine -like "*$targetSuffix*"
}

foreach ($process in @($processes)) {
    try {
        [void](Invoke-CimMethod -InputObject $process -MethodName Terminate)
    }
    catch {
    }
}

Start-Sleep -Seconds 2

$argumentList = @(
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', $startScript,
    '-Port', $Port,
    '-NoAutoOpen'
)
if (-not [string]::IsNullOrWhiteSpace([string]$AdvertiseHost)) {
    $argumentList += @('-AdvertiseHost', [string]$AdvertiseHost)
}

$process = Start-Process -FilePath 'powershell.exe' -ArgumentList $argumentList -WorkingDirectory $repoRoot -PassThru -WindowStyle Hidden

$deadline = (Get-Date).AddSeconds($ReadyTimeoutSeconds)
$ready = $false
while ((Get-Date) -lt $deadline) {
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri ("http://localhost:{0}/api/project-status" -f $Port) -TimeoutSec 5
        if ($response.StatusCode -eq 200) {
            $ready = $true
            break
        }
    }
    catch {
    }
    Start-Sleep -Milliseconds 750
}

if (-not $ready) {
    $diagnosticHint = if (Test-Path -Path $startupDiagnosticPath) { " See $startupDiagnosticPath" } else { '' }
    throw "TOD UI host did not become ready on port $Port within $ReadyTimeoutSeconds seconds.$diagnosticHint"
}

[pscustomobject]@{
    ok = $true
    port = $Port
    pid = $process.Id
    ready_timeout_seconds = $ReadyTimeoutSeconds
    started_at = (Get-Date).ToUniversalTime().ToString('o')
} | ConvertTo-Json -Depth 5