param(
    [int]$Port = 8844,
    [int]$ReadyTimeoutSeconds = 30,
    [string]$AdvertiseHost = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$startScript = Join-Path $PSScriptRoot 'Start-TOD-UI.ps1'
$startupDiagnosticPath = Join-Path $repoRoot 'tod/out/tod-ui-startup.latest.json'

function Read-TodUiStartupDiagnostic {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if (-not (Test-Path -Path $PathValue)) {
        return $null
    }

    try {
        return (Get-Content -Path $PathValue -Raw | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Test-TodUiStartupDiagnosticReady {
    param(
        $Diagnostic,
        [int]$ExpectedPort,
        [datetime]$NotBefore
    )

    if ($null -eq $Diagnostic) {
        return $false
    }

    $generatedAt = [datetime]::MinValue
    if ($Diagnostic.PSObject.Properties['generated_at']) {
        try {
            $generatedAt = [datetime]::Parse([string]$Diagnostic.generated_at).ToUniversalTime()
        }
        catch {
            $generatedAt = [datetime]::MinValue
        }
    }

    $port = if ($Diagnostic.PSObject.Properties['port']) { [int]$Diagnostic.port } else { 0 }
    $ok = ($Diagnostic.PSObject.Properties['ok'] -and [bool]$Diagnostic.ok)
    $status = if ($Diagnostic.PSObject.Properties['status']) { [string]$Diagnostic.status } else { '' }
    $portOwner = if ($Diagnostic.PSObject.Properties['port_owner']) { $Diagnostic.port_owner } else { $null }
    $ownedPort = ($portOwner -and $portOwner.PSObject.Properties['in_use'] -and [bool]$portOwner.in_use -and (($portOwner.PSObject.Properties['is_tod_ui_process'] -and [bool]$portOwner.is_tod_ui_process) -or ($portOwner.PSObject.Properties['is_tod_ui_proxy_process'] -and [bool]$portOwner.is_tod_ui_proxy_process)))

    return ($ok -and $port -eq $ExpectedPort -and $generatedAt -ge $NotBefore -and @('started', 'started_with_fallback', 'already_running') -contains $status -and $ownedPort)
}

function Get-TodUiRestartTrackedProcesses {
    param([Parameter(Mandatory = $true)][int]$Port)

    $targetSuffix = [System.IO.Path]::GetFileName($startScript)
    return @(Get-CimInstance Win32_Process | Where-Object {
        $_.CommandLine -and (
            ($_.Name -match '^powershell(\.exe)?$' -and $_.CommandLine -like "*$targetSuffix*") -or
            ($_.Name -match '^python(\.exe)?$' -and $_.CommandLine -like '*tod_ui_lan_proxy.py*' -and ($_.CommandLine -like "*--listen-port $Port*" -or $_.CommandLine -like "*--target-port $Port*"))
        )
    })
}

if (-not (Test-Path -Path $startScript)) {
    throw "Start-TOD-UI.ps1 was not found at $startScript"
}

$processes = Get-TodUiRestartTrackedProcesses -Port $Port

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

$startTimeUtc = (Get-Date).ToUniversalTime()
$deadline = (Get-Date).AddSeconds($ReadyTimeoutSeconds)
$ready = $false
$readinessSource = 'unconfirmed'
while ((Get-Date) -lt $deadline) {
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri ("http://localhost:{0}/api/project-status" -f $Port) -TimeoutSec 5
        if ($response.StatusCode -eq 200) {
            $ready = $true
            $readinessSource = 'project_status'
            break
        }
    }
    catch {
    }

    $diagnostic = Read-TodUiStartupDiagnostic -PathValue $startupDiagnosticPath
    if (Test-TodUiStartupDiagnosticReady -Diagnostic $diagnostic -ExpectedPort $Port -NotBefore $startTimeUtc) {
        $ready = $true
        $readinessSource = 'startup_diagnostic'
        break
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
    readiness_source = $readinessSource
    ready_timeout_seconds = $ReadyTimeoutSeconds
    started_at = (Get-Date).ToUniversalTime().ToString('o')
} | ConvertTo-Json -Depth 5