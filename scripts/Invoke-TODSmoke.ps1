param(
    [int]$PreferredPort = 8844,
    [int]$MaxPortSearch = 30,
    [int]$Top = 10,
    [switch]$FailOnError,
    [switch]$SkipSharedStateSync,
    [string]$SharedStateSyncScript = "scripts/Invoke-TODSharedStateSync.ps1"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

function Invoke-SharedStateSyncIfEnabled {
    if ($SkipSharedStateSync) {
        return
    }

    $syncScriptPath = if ([System.IO.Path]::IsPathRooted($SharedStateSyncScript)) {
        $SharedStateSyncScript
    }
    else {
        Join-Path $repoRoot $SharedStateSyncScript
    }

    if (-not (Test-Path -Path $syncScriptPath)) {
        Write-Warning "Shared state sync script not found: $syncScriptPath"
        return
    }

    try {
        & $syncScriptPath | Out-Null
    }
    catch {
        Write-Warning ("Shared state sync failed after smoke run: {0}" -f $_.Exception.Message)
    }
}

function Test-PortFree {
    param([int]$Port)

    try {
        $conn = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
        return ($null -eq $conn)
    }
    catch {
        return $true
    }
}

function Find-FreePort {
    param(
        [int]$Start,
        [int]$MaxAttempts
    )

    for ($i = 0; $i -lt $MaxAttempts; $i++) {
        $candidate = $Start + $i
        if (Test-PortFree -Port $candidate) {
            return $candidate
        }
    }

    throw "No free port found from $Start to $($Start + $MaxAttempts - 1)."
}

function Invoke-Json {
    param(
        [string]$Uri,
        [string]$Method,
        [string]$Body
    )

    if ([string]::IsNullOrWhiteSpace($Body)) {
        return Invoke-RestMethod -Uri $Uri -Method $Method -TimeoutSec 20
    }

    return Invoke-RestMethod -Uri $Uri -Method $Method -ContentType "application/json" -Body $Body -TimeoutSec 20
}

function Invoke-JsonSafe {
    param(
        [string]$Uri,
        [string]$Method,
        [string]$Body
    )

    try {
        return [pscustomobject]@{
            ok = $true
            data = Invoke-Json -Uri $Uri -Method $Method -Body $Body
            error = ''
        }
    }
    catch {
        return [pscustomobject]@{
            ok = $false
            data = $null
            error = $_.Exception.Message
        }
    }
}

$uiScript = Join-Path $PSScriptRoot "Start-TOD-UI.ps1"
if (-not (Test-Path -Path $uiScript)) {
    throw "Missing UI script: $uiScript"
}

$port = Find-FreePort -Start $PreferredPort -MaxAttempts $MaxPortSearch
$baseUrl = "http://localhost:$port"
$server = $null

try {
    $server = Start-Process -FilePath powershell -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $uiScript,
        "-Port", [string]$port
    ) -PassThru

    Start-Sleep -Seconds 2

    $project = Invoke-Json -Uri "$baseUrl/api/project-status" -Method "Get" -Body ""
    $busResponse = Invoke-JsonSafe -Uri "$baseUrl/api/run" -Method "Post" -Body (@{ action = "get-state-bus"; top = $Top } | ConvertTo-Json -Depth 5)
    $reliabilityResponse = Invoke-JsonSafe -Uri "$baseUrl/api/run" -Method "Post" -Body (@{ action = "get-reliability"; top = $Top } | ConvertTo-Json -Depth 5)
    $logs = Invoke-Json -Uri "$baseUrl/api/logs?tail=5" -Method "Get" -Body ""

    $projectStatusMode = if ($project.PSObject.Properties['data_sources'] -and $project.data_sources -and $project.data_sources.PSObject.Properties['project_status_mode']) { [string]$project.data_sources.project_status_mode } else { '' }
    $listenerFallbackActive = ($projectStatusMode -eq 'listener_telemetry_fallback')
    $bus = if ($busResponse.ok) { $busResponse.data } else { $null }
    $reliability = if ($reliabilityResponse.ok) { $reliabilityResponse.data } else { $null }
    $stateBusOk = if ($busResponse.ok -and $bus -and $bus.PSObject.Properties['ok']) { [bool]$bus.ok } elseif ($listenerFallbackActive) { $true } else { $false }
    $reliabilityOk = if ($reliabilityResponse.ok -and $reliability -and $reliability.PSObject.Properties['ok']) { [bool]$reliability.ok } elseif ($listenerFallbackActive) { $true } else { $false }
    $currentAlertState = 'unknown'
    if ($bus -and $bus.PSObject.Properties['result'] -and $bus.result -and $bus.result.PSObject.Properties['system_posture']) {
        $currentAlertState = [string]$bus.result.system_posture.current_alert_state
    }
    elseif ($project.PSObject.Properties['cadence_health'] -and $project.cadence_health -and $project.cadence_health.PSObject.Properties['severity']) {
        $currentAlertState = [string]$project.cadence_health.severity
    }
    elseif ($project.PSObject.Properties['steady_state'] -and $project.steady_state -and $project.steady_state.PSObject.Properties['status']) {
        $currentAlertState = [string]$project.steady_state.status
    }

    $result = [pscustomobject]@{
        generated_at = (Get-Date).ToUniversalTime().ToString("o")
        source = "tod-smoke"
        port = $port
        base_url = $baseUrl
        checks = [pscustomobject]@{
            project_status_ok = [bool]$project.ok
            state_bus_ok = $stateBusOk
            reliability_ok = $reliabilityOk
            logs_ok = [bool]$logs.ok
        }
        facts = [pscustomobject]@{
            objective_count = if ($project.PSObject.Properties["objective_options"] -and $null -ne $project.objective_options) { [int]@($project.objective_options).Count } else { 0 }
            current_alert_state = $currentAlertState
            logs_tail_count = if ($logs.PSObject.Properties["count"]) { [int]$logs.count } else { 0 }
            project_status_mode = if ([string]::IsNullOrWhiteSpace($projectStatusMode)) { 'unknown' } else { $projectStatusMode }
        }
    }

    $allOk = [bool]($result.checks.project_status_ok -and $result.checks.state_bus_ok -and $result.checks.reliability_ok -and $result.checks.logs_ok)
    $result | Add-Member -NotePropertyName passed_all -NotePropertyValue $allOk

    $json = $result | ConvertTo-Json -Depth 8
    Write-Output $json

    Invoke-SharedStateSyncIfEnabled

    if ($FailOnError -and -not $allOk) {
        throw "TOD smoke checks reported one or more failures."
    }
}
finally {
    if ($null -ne $server) {
        try {
            Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue
        }
        catch {
        }
    }
}
